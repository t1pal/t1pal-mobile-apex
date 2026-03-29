// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PredictedGlucoseDiagnosisTests.swift
// T1Pal Mobile
//
// Compare our predicted glucose curves vs Loop's NS deviceStatus predictions
// Requirements: ALG-DIAG-012
//
// Purpose: If our predictions match Loop's, the divergence is in recommendation
// logic. If predictions diverge, the issue is in the prediction model itself.
//
// Trace: ALG-DIAG-012, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for predicted glucose curve comparison
/// Trace: ALG-DIAG-012
@Suite("Predicted Glucose Diagnosis")
struct PredictedGlucoseDiagnosisTests {
    
    // MARK: - Test Fixture Structures
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let iob: IOBData?
            let predicted: PredictedData?
            let enacted: EnactedData?
            
            struct IOBData: Codable {
                let timestamp: String
                let iob: Double
            }
            
            struct PredictedData: Codable {
                let startDate: String
                let values: [Double]
            }
            
            struct EnactedData: Codable {
                let timestamp: String
                let rate: Double?
            }
        }
    }
    
    struct NSTreatment: Codable {
        let _id: String
        let eventType: String?
        let timestamp: String?
        let created_at: String?
        let rate: Double?
        let absolute: Double?
        let duration: Double?
        let insulin: Double?
        let carbs: Double?
    }
    
    struct NSEntry: Codable {
        let _id: String
        let sgv: Int?
        let dateString: String?
        let date: Double?  // Can be decimal timestamp
    }
    
    struct NSProfile: Codable {
        let _id: String
        let store: [String: ProfileStore]
        let defaultProfile: String
        
        struct ProfileStore: Codable {
            let basal: [BasalEntry]?
            let sens: [SensEntry]?
            let carbratio: [CREntry]?
            
            struct BasalEntry: Codable {
                let time: String
                let value: Double
                let timeAsSeconds: Int
            }
            
            struct SensEntry: Codable {
                let time: String
                let value: Double
                let timeAsSeconds: Int
            }
            
            struct CREntry: Codable {
                let time: String
                let value: Double
                let timeAsSeconds: Int
            }
        }
    }
    
    // MARK: - ALG-DIAG-012: Predicted Glucose Comparison
    
    @Test("Predicted glucose curve comparison")
    func predictedGlucoseCurveComparison() throws {
        // Load NS deviceStatus with Loop's predictions
        let deviceStatuses = try loadDeviceStatusFixture()
        let entries = try loadEntriesFixture()
        let treatments = try loadTreatmentsFixture()
        
        guard let status = deviceStatuses.first,
              let loopStatus = status.loop,
              let predicted = loopStatus.predicted,
              let startDateStr = parseDate(predicted.startDate) else {
            return  // Skip if no predicted data in fixture
        }
        
        let nsPredictedValues = predicted.values
        let nsStartDate = startDateStr
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 ALG-DIAG-012: Predicted Glucose Curve Comparison")
        print(String(repeating: "=", count: 70))
        
        print("\n🔹 NS Loop Prediction:")
        print("  Start: \(formatTime(nsStartDate))")
        print("  Points: \(nsPredictedValues.count)")
        print("  Duration: \(nsPredictedValues.count * 5) minutes (\(String(format: "%.1f", Double(nsPredictedValues.count * 5) / 60)) hours)")
        print("  First 5 values: \(nsPredictedValues.prefix(5).map { String(format: "%.0f", $0) }.joined(separator: ", "))")
        print("  Last 5 values: \(nsPredictedValues.suffix(5).map { String(format: "%.0f", $0) }.joined(separator: ", "))")
        
        // Get starting glucose from NS entries
        let sortedEntries = entries
            .compactMap { entry -> (date: Date, sgv: Int)? in
                guard let sgv = entry.sgv,
                      let dateStr = entry.dateString,
                      let date = parseDate(dateStr) else { return nil }
                return (date, sgv)
            }
            .sorted { $0.date > $1.date }
        
        guard let latestEntry = sortedEntries.first else {
            return  // Skip if no glucose entries
        }
        
        // ALG-DIAG-023: Use Loop's predicted start value for fair comparison
        // Loop may use a smoothed/interpolated value, not the raw CGM reading
        let loopStartingGlucose = nsPredictedValues.first ?? Double(latestEntry.sgv)
        let cgmStartingGlucose = Double(latestEntry.sgv)
        
        print("\n🔹 Starting Glucose:")
        print("  CGM value: \(Int(cgmStartingGlucose)) mg/dL at \(formatTime(latestEntry.date))")
        print("  NS predicted start: \(Int(loopStartingGlucose)) mg/dL at \(formatTime(nsStartDate))")
        print("  Delta: \(Int(cgmStartingGlucose - loopStartingGlucose)) mg/dL")
        
        // Use Loop's starting value for fair comparison
        let startingGlucose = loopStartingGlucose
        
        // Build glucose history for momentum calculation
        let glucoseHistory = sortedEntries.prefix(12).reversed().map { entry in
            GlucoseReading(glucose: Double(entry.sgv), timestamp: entry.date)
        }
        
        print("\n🔹 Glucose History (for momentum):")
        print("  Points: \(glucoseHistory.count)")
        if let first = glucoseHistory.first, let last = glucoseHistory.last {
            let delta = last.glucose - first.glucose
            let duration = last.timestamp.timeIntervalSince(first.timestamp) / 60
            print("  Trend: \(String(format: "%+.1f", delta)) mg/dL over \(Int(duration)) min")
            let rate = delta / duration
            print("  Rate: \(String(format: "%+.1f", rate)) mg/dL/min")
        }
        
        // Get temp basals for insulin effect - raw doses for parity path
        // ALG-DIAG-023: Use raw rates, let parity annotate with basal schedule
        let tempBasals = treatments
            .filter { $0.eventType == "Temp Basal" }
            .compactMap { treatment -> InsulinDose? in
                guard let ts = treatment.timestamp ?? treatment.created_at,
                      let date = parseDate(ts),
                      let rate = treatment.rate ?? treatment.absolute,
                      let duration = treatment.duration else { return nil }
                
                // Use actual delivered units (rate × duration in hours)
                // The parity path will calculate net vs scheduled basal
                let units = rate * (duration / 60)
                
                // ALG-DIAG-023: Source must indicate temp_basal for parity path
                // Include duration so toRawInsulinDose() can calculate end time
                let source = "temp_basal_\(Int(duration))min"
                
                return InsulinDose(
                    units: units,
                    timestamp: date,
                    type: .novolog,
                    source: source
                )
            }
        
        print("\n🔹 Insulin Doses for Prediction:")
        print("  Temp basals in window: \(tempBasals.count)")
        let totalDelivered = tempBasals.reduce(0.0) { $0 + $1.units }
        print("  Total delivered insulin: \(String(format: "%.2f", totalDelivered)) U")
        
        // Load basal schedule from profile for parity prediction path
        // ALG-DIAG-023: Required to match Loop's net-basal insulin effect
        let profiles = try loadProfileFixture()
        let basalSchedule: [AbsoluteScheduleValue<Double>]
        if let profile = profiles.first {
            basalSchedule = buildBasalSchedule(from: profile, referenceDate: nsStartDate)
            print("  Using parity path with basal schedule (\(basalSchedule.count) entries)")
        } else {
            basalSchedule = []
            print("  ⚠️ No basal schedule - using legacy path (will diverge from Loop)")
        }
        
        // Generate our prediction
        let predictor = LoopGlucosePrediction(
            configuration: .init(
                predictionDuration: 6 * 3600,  // 6 hours like Loop
                predictionInterval: 5 * 60,    // 5-min intervals
                momentumDuration: 30 * 60
            )
        )
        
        let insulinSensitivity = 40.0  // From profile
        let carbRatio = 10.0           // From profile
        
        // ALG-DIAG-023: Pass basalSchedule for parity insulin effect calculation
        let ourPrediction = predictor.predict(
            currentGlucose: startingGlucose,
            glucoseHistory: Array(glucoseHistory),
            doses: tempBasals,
            carbEntries: [],  // No carbs in fixture
            insulinSensitivity: insulinSensitivity,
            carbRatio: carbRatio,
            startDate: nsStartDate,
            basalSchedule: basalSchedule.isEmpty ? nil : basalSchedule
        )
        
        print("\n🔹 Our Prediction:")
        print("  Points generated: \(ourPrediction.count)")
        if !ourPrediction.isEmpty {
            print("  First 5 values: \(ourPrediction.prefix(5).map { String(format: "%.0f", $0.glucose) }.joined(separator: ", "))")
            print("  Last 5 values: \(ourPrediction.suffix(5).map { String(format: "%.0f", $0.glucose) }.joined(separator: ", "))")
        }
        
        // Compare curves
        print("\n🔹 Curve Comparison (first 20 points):")
        print("  Time      | NS Loop | Ours    | Δ")
        print("  " + String(repeating: "-", count: 40))
        
        var totalDelta = 0.0
        var maxDelta = 0.0
        var comparisonCount = 0
        
        for i in 0..<min(20, min(nsPredictedValues.count, ourPrediction.count)) {
            let nsValue = nsPredictedValues[i]
            let ourValue = ourPrediction[i].glucose
            let delta = ourValue - nsValue
            
            totalDelta += abs(delta)
            maxDelta = max(maxDelta, abs(delta))
            comparisonCount += 1
            
            let time = nsStartDate.addingTimeInterval(Double(i) * 5 * 60)
            let deltaStr = delta >= 0 ? String(format: "+%.0f", delta) : String(format: "%.0f", delta)
            print("  \(formatTime(time)) | \(String(format: "%6.0f", nsValue))  | \(String(format: "%6.0f", ourValue))  | \(deltaStr)")
        }
        
        let avgDelta = comparisonCount > 0 ? totalDelta / Double(comparisonCount) : 0
        
        print("\n🔹 Summary Statistics:")
        print("  Points compared: \(comparisonCount)")
        print("  Average |Δ|: \(String(format: "%.1f", avgDelta)) mg/dL")
        print("  Max |Δ|: \(String(format: "%.1f", maxDelta)) mg/dL")
        
        // Analyze divergence pattern
        if avgDelta < 10 {
            print("\n  ✅ Excellent prediction match (<10 mg/dL avg)")
            print("     → Divergence likely in recommendation logic, not prediction")
        } else if avgDelta < 30 {
            print("\n  ⚠️ Moderate prediction difference (10-30 mg/dL avg)")
            print("     → Check insulin effect model and momentum calculation")
        } else {
            print("\n  ❌ Significant prediction divergence (>30 mg/dL avg)")
            print("     → Prediction model needs investigation")
        }
        
        print(String(repeating: "=", count: 70))
        
        // Record test data for tracking
        #expect(comparisonCount > 0)
    }
    
    @Test("Prediction trend alignment")
    func predictionTrendAlignment() throws {
        // Check if our prediction trend matches NS trend direction
        let deviceStatuses = try loadDeviceStatusFixture()
        
        guard let status = deviceStatuses.first,
              let predicted = status.loop?.predicted else {
            return  // Skip if no predicted data
        }
        
        let values = predicted.values
        guard values.count >= 10 else {
            return  // Skip if not enough prediction points
        }
        
        print("\n📊 Prediction Trend Analysis")
        
        // Analyze NS prediction trend
        let first10 = Array(values.prefix(10))
        let last10 = Array(values.suffix(10))
        
        let shortTermTrend = (first10.last ?? 0) - (first10.first ?? 0)
        let longTermTrend = (last10.last ?? 0) - (values.first ?? 0)
        
        print("  NS Short-term trend (0-45 min): \(String(format: "%+.1f", shortTermTrend)) mg/dL")
        print("  NS Long-term trend (0-end): \(String(format: "%+.1f", longTermTrend)) mg/dL")
        
        // Categorize trend
        let trendDirection: String
        if longTermTrend < -20 {
            trendDirection = "📉 Falling"
        } else if longTermTrend > 20 {
            trendDirection = "📈 Rising"
        } else {
            trendDirection = "➡️ Stable"
        }
        
        print("  Overall direction: \(trendDirection)")
        
        // Final value analysis
        let finalValue = values.last ?? 0
        let targetRange = 80.0...120.0
        
        print("\n  Final predicted value: \(Int(finalValue)) mg/dL")
        if targetRange.contains(finalValue) {
            print("  ✅ Converges to target range (80-120)")
        } else if finalValue < 80 {
            print("  ⚠️ Predicts below target (<80)")
        } else {
            print("  ⚠️ Predicts above target (>120)")
        }
    }
    
    @Test("Multiple device status comparison")
    func multipleDeviceStatusComparison() throws {
        // Compare predictions across multiple deviceStatus entries
        let deviceStatuses = try loadDeviceStatusFixture()
        
        print("\n📊 Multi-Status Prediction Analysis")
        print("  Device statuses: \(deviceStatuses.count)")
        
        var analysisRows: [(time: String, start: Int, end: Int, trend: String, points: Int)] = []
        
        for status in deviceStatuses {
            guard let predicted = status.loop?.predicted,
                  let startDate = parseDate(predicted.startDate) else {
                continue
            }
            
            let values = predicted.values
            guard !values.isEmpty else { continue }
            
            let startVal = Int(values.first ?? 0)
            let endVal = Int(values.last ?? 0)
            let trend = endVal - startVal
            let trendStr = trend >= 0 ? "+\(trend)" : "\(trend)"
            
            analysisRows.append((
                time: formatTime(startDate),
                start: startVal,
                end: endVal,
                trend: trendStr,
                points: values.count
            ))
        }
        
        if !analysisRows.isEmpty {
            print("\n  Time     | Start | End   | Trend  | Points")
            print("  " + String(repeating: "-", count: 45))
            for row in analysisRows {
                print("  \(row.time) | \(String(format: "%5d", row.start)) | \(String(format: "%5d", row.end)) | \(String(format: "%6s", row.trend)) | \(row.points)")
            }
        }
        
        // Consistency check - predictions should be somewhat similar at overlapping times
        if analysisRows.count >= 2 {
            let startVals = analysisRows.map { Double($0.start) }
            let avg = startVals.reduce(0, +) / Double(startVals.count)
            let variance = startVals.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(startVals.count)
            let stdDev = sqrt(variance)
            
            print("\n  Starting value consistency:")
            print("    Mean: \(Int(avg)) mg/dL")
            print("    Std Dev: \(String(format: "%.1f", stdDev)) mg/dL")
            
            if stdDev < 30 {
                print("    ✅ Consistent starting values")
            } else {
                print("    ⚠️ Variable starting values (glucose changing rapidly)")
            }
        }
    }
    
    // MARK: - Helpers
    
    func loadDeviceStatusFixture() throws -> [NSDeviceStatus] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_devicestatus_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Device status fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSDeviceStatus].self, from: data)
    }
    
    func loadEntriesFixture() throws -> [NSEntry] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_entries_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Entries fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSEntry].self, from: data)
    }
    
    func loadTreatmentsFixture() throws -> [NSTreatment] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_treatments_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Treatments fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSTreatment].self, from: data)
    }
    
    func loadProfileFixture() throws -> [NSProfile] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_profile_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSProfile].self, from: data)
    }
    
    /// Build basal schedule from NS profile for parity prediction path
    /// ALG-DIAG-023: Required for accurate insulin effect calculation
    func buildBasalSchedule(from profile: NSProfile, referenceDate: Date) -> [AbsoluteScheduleValue<Double>] {
        guard let store = profile.store[profile.defaultProfile],
              let basalEntries = store.basal, !basalEntries.isEmpty else {
            return []
        }
        
        // Sort by time of day
        let sorted = basalEntries.sorted { $0.timeAsSeconds < $1.timeAsSeconds }
        
        // Build absolute schedule - extend 24 hours back and 6 hours forward
        let startOfDay = Calendar.current.startOfDay(for: referenceDate)
        let historyStart = startOfDay.addingTimeInterval(-24 * 3600)
        let predictionEnd = referenceDate.addingTimeInterval(6 * 3600)
        
        var schedule: [AbsoluteScheduleValue<Double>] = []
        
        // Generate entries for each day needed
        var currentDay = historyStart
        while currentDay < predictionEnd {
            for (index, entry) in sorted.enumerated() {
                let entryStart = currentDay.addingTimeInterval(Double(entry.timeAsSeconds))
                
                // Calculate end time as start of next entry (or midnight)
                let nextEntrySeconds: Int
                if index + 1 < sorted.count {
                    nextEntrySeconds = sorted[index + 1].timeAsSeconds
                } else {
                    nextEntrySeconds = 24 * 3600  // End of day
                }
                let entryEnd = currentDay.addingTimeInterval(Double(nextEntrySeconds))
                
                // Only add if relevant to our window
                if entryEnd > historyStart && entryStart < predictionEnd {
                    schedule.append(AbsoluteScheduleValue(
                        startDate: max(entryStart, historyStart),
                        endDate: min(entryEnd, predictionEnd),
                        value: entry.value
                    ))
                }
            }
            currentDay = currentDay.addingTimeInterval(24 * 3600)
        }
        
        // Sort and deduplicate
        schedule.sort { $0.startDate < $1.startDate }
        return schedule
    }
    
    func parseDate(_ string: String) -> Date? {
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
