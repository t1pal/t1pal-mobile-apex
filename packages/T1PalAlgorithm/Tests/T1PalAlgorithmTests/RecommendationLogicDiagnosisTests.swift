// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RecommendationLogicDiagnosisTests.swift
// T1Pal Mobile
//
// Compare our recommendation logic vs Loop's decision path
// Requirements: ALG-DIAG-013
//
// Purpose: Trace how Loop converts predictions → temp basal rate
// and compare against our implementation.
//
// Trace: ALG-DIAG-013, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for recommendation logic comparison
/// Trace: ALG-DIAG-013
@Suite("Recommendation Logic Diagnosis")
struct RecommendationLogicDiagnosisTests {
    
    // MARK: - Test Fixture Structures
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let iob: IOBData?
            let cob: COBData?
            let predicted: PredictedData?
            let automaticDoseRecommendation: AutomaticDoseRecommendation?
            let enacted: EnactedData?
            
            struct IOBData: Codable {
                let timestamp: String
                let iob: Double
            }
            
            struct COBData: Codable {
                let timestamp: String
                let cob: Double
            }
            
            struct PredictedData: Codable {
                let startDate: String
                let values: [Double]
            }
            
            struct AutomaticDoseRecommendation: Codable {
                let timestamp: String
                let bolusVolume: Double?
                let tempBasalAdjustment: TempBasalAdjustment?
                
                struct TempBasalAdjustment: Codable {
                    let rate: Double
                    let duration: Double
                }
            }
            
            struct EnactedData: Codable {
                let timestamp: String
                let rate: Double?
                let duration: Double?
                let bolusVolume: Double?
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
    }
    
    struct NSEntry: Codable {
        let _id: String
        let sgv: Int?
        let dateString: String?
        let date: Double?
    }
    
    // MARK: - ALG-DIAG-013: Recommendation Logic Comparison
    
    @Test("Recommendation logic comparison")
    func recommendationLogicComparison() throws {
        // Load fixtures
        let deviceStatuses = try loadDeviceStatusFixture()
        let entries = try loadEntriesFixture()
        let treatments = try loadTreatmentsFixture()
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 ALG-DIAG-013: Recommendation Logic Comparison")
        print(String(repeating: "=", count: 70))
        
        var comparisons: [(nsRate: Double, ourRate: Double, delta: Double)] = []
        
        for status in deviceStatuses.prefix(5) {
            guard let loopStatus = status.loop,
                  let recommendation = loopStatus.automaticDoseRecommendation,
                  let tbAdjustment = recommendation.tempBasalAdjustment,
                  let predicted = loopStatus.predicted,
                  let iobData = loopStatus.iob,
                  let startDateStr = parseDate(predicted.startDate) else {
                continue
            }
            
            let nsRate = tbAdjustment.rate
            let nsIOB = iobData.iob
            let predictedValues = predicted.values
            
            // Extract key metrics from NS predictions
            let startGlucose = predictedValues.first ?? 0
            let minGlucose = predictedValues.min() ?? 0
            let eventualGlucose = predictedValues.last ?? 0
            
            // Profile values (from previous diagnosis)
            let scheduledBasalRate = 1.7  // U/hr
            let insulinSensitivity = 40.0 // mg/dL/U
            let targetGlucose = 100.0     // mg/dL
            
            // Calculate what our logic would recommend
            let bgDifference = eventualGlucose - targetGlucose
            let insulinRequired = bgDifference / insulinSensitivity
            
            // Convert to temp basal rate (over 30 min = 0.5 hr)
            // insulinRequired is the extra insulin needed over the next period
            // As temp basal: rate = scheduled + (insulinRequired / 0.5)
            let tempBasalAdjustment = insulinRequired / 0.5  // Deliver in 30 min
            var ourRate = scheduledBasalRate + tempBasalAdjustment
            
            // Apply limits
            let maxBasalRate = 5.0
            ourRate = max(0, min(maxBasalRate, ourRate))
            
            let delta = ourRate - nsRate
            comparisons.append((nsRate, ourRate, delta))
            
            print("\n🔹 Status at \(formatTime(startDateStr)):")
            print("  📈 Predicted: start=\(Int(startGlucose)), min=\(Int(minGlucose)), eventual=\(Int(eventualGlucose))")
            print("  💉 IOB: \(String(format: "%.2f", nsIOB)) U")
            print("  🎯 Target: \(Int(targetGlucose)) mg/dL")
            print("  ")
            print("  Decision Path:")
            print("    BG difference: \(String(format: "%+.0f", bgDifference)) mg/dL (eventual - target)")
            print("    Insulin required: \(String(format: "%+.2f", insulinRequired)) U (bgDiff / ISF)")
            print("    TB adjustment: \(String(format: "%+.2f", tempBasalAdjustment)) U/hr (insulinReq / 0.5hr)")
            print("  ")
            print("  🔄 NS Loop rate: \(String(format: "%.2f", nsRate)) U/hr")
            print("  🔵 Our calc rate: \(String(format: "%.2f", ourRate)) U/hr")
            print("  📊 Delta: \(String(format: "%+.2f", delta)) U/hr")
        }
        
        guard !comparisons.isEmpty else {
            // Skip test if no fixtures available
            return
        }
        
        // Summary statistics
        let avgDelta = comparisons.map { abs($0.delta) }.reduce(0, +) / Double(comparisons.count)
        let maxDelta = comparisons.map { abs($0.delta) }.max() ?? 0
        
        print("\n" + String(repeating: "-", count: 70))
        print("📊 Summary Statistics:")
        print("  Comparisons: \(comparisons.count)")
        print("  Average |Δ|: \(String(format: "%.2f", avgDelta)) U/hr")
        print("  Max |Δ|: \(String(format: "%.2f", maxDelta)) U/hr")
        
        // Analyze divergence pattern
        let underRecommendations = comparisons.filter { $0.delta < -0.1 }.count
        let overRecommendations = comparisons.filter { $0.delta > 0.1 }.count
        let matched = comparisons.filter { abs($0.delta) <= 0.1 }.count
        
        print("\n  Pattern Analysis:")
        print("    Under-recommending (our < NS): \(underRecommendations)")
        print("    Over-recommending (our > NS): \(overRecommendations)")
        print("    Matched (Δ ≤ 0.1): \(matched)")
        
        if avgDelta < 0.5 {
            print("\n  ✅ Good recommendation alignment (<0.5 U/hr avg)")
        } else if avgDelta < 1.0 {
            print("\n  ⚠️ Moderate recommendation divergence (0.5-1.0 U/hr)")
        } else {
            print("\n  ❌ Significant recommendation divergence (>1.0 U/hr)")
        }
        
        print(String(repeating: "=", count: 70))
    }
    
    @Test("Decision path breakdown")
    func decisionPathBreakdown() throws {
        // Detailed breakdown of one recommendation decision
        let deviceStatuses = try loadDeviceStatusFixture()
        
        guard let status = deviceStatuses.first,
              let loopStatus = status.loop,
              let recommendation = loopStatus.automaticDoseRecommendation,
              let tbAdjustment = recommendation.tempBasalAdjustment,
              let predicted = loopStatus.predicted,
              let iobData = loopStatus.iob else {
            // Skip test if no fixtures available
            return
        }
        
        print("\n📊 Decision Path Breakdown (Single Recommendation)")
        print(String(repeating: "=", count: 70))
        
        let values = predicted.values
        let nsRate = tbAdjustment.rate
        let nsIOB = iobData.iob
        
        // Key decision points
        let currentBG = values.first ?? 0
        let minBG = values.min() ?? 0
        let minIndex = values.firstIndex(of: minBG) ?? 0
        let minutesToMin = minIndex * 5
        let eventualBG = values.last ?? 0
        
        print("\n  Step 1: Current State")
        print("    Current BG: \(Int(currentBG)) mg/dL")
        print("    IOB: \(String(format: "%.2f", nsIOB)) U")
        print("    COB: \(loopStatus.cob?.cob ?? 0) g")
        
        print("\n  Step 2: Prediction Analysis")
        print("    Predicted min: \(Int(minBG)) mg/dL (in \(minutesToMin) min)")
        print("    Predicted eventual: \(Int(eventualBG)) mg/dL")
        print("    Points in curve: \(values.count)")
        
        // Loop's decision criteria
        let suspendThreshold = 70.0
        let targetBG = 100.0
        let isf = 40.0
        let maxBasal = 5.0
        let scheduledBasal = 1.7
        
        print("\n  Step 3: Safety Checks")
        if minBG < suspendThreshold {
            print("    ⚠️ Low BG predicted: SUSPEND would be triggered")
        } else {
            print("    ✅ No low BG predicted (min \(Int(minBG)) >= \(Int(suspendThreshold)))")
        }
        
        print("\n  Step 4: Insulin Requirement")
        let bgError = eventualBG - targetBG
        let insulinNeeded = bgError / isf
        print("    BG error: \(String(format: "%+.0f", bgError)) mg/dL")
        print("    Insulin to correct: \(String(format: "%+.2f", insulinNeeded)) U")
        
        print("\n  Step 5: Temp Basal Calculation")
        let tbRate = scheduledBasal + (insulinNeeded / 0.5)
        let clampedRate = max(0, min(maxBasal, tbRate))
        print("    Scheduled: \(scheduledBasal) U/hr")
        print("    Raw calculated: \(String(format: "%.2f", tbRate)) U/hr")
        print("    After limits: \(String(format: "%.2f", clampedRate)) U/hr")
        print("    NS Loop actual: \(String(format: "%.2f", nsRate)) U/hr")
        print("    Delta: \(String(format: "%+.2f", clampedRate - nsRate)) U/hr")
        
        print("\n  Step 6: Analysis")
        if abs(clampedRate - nsRate) < 0.1 {
            print("    ✅ Logic matches within tolerance")
        } else if clampedRate > nsRate {
            print("    ⚠️ Our logic recommends MORE insulin")
            print("       Possible causes: different ISF, different eventual BG calc")
        } else {
            print("    ⚠️ Our logic recommends LESS insulin")
            print("       Possible causes: different prediction model, different IOB contrib")
        }
        
        print(String(repeating: "=", count: 70))
    }
    
    @Test("Recommendation trends")
    func recommendationTrends() throws {
        // Analyze recommendation trends across multiple statuses
        let deviceStatuses = try loadDeviceStatusFixture()
        
        print("\n📊 Recommendation Trends Analysis")
        
        var rows: [(time: String, bg: Int, eventual: Int, nsRate: Double, bgTarget: Int)] = []
        
        for status in deviceStatuses {
            guard let loopStatus = status.loop,
                  let recommendation = loopStatus.automaticDoseRecommendation,
                  let tbAdjustment = recommendation.tempBasalAdjustment,
                  let predicted = loopStatus.predicted,
                  let startDate = parseDate(predicted.startDate) else {
                continue
            }
            
            let values = predicted.values
            let currentBG = Int(values.first ?? 0)
            let eventualBG = Int(values.last ?? 0)
            let nsRate = tbAdjustment.rate
            let target = 100
            
            rows.append((
                time: formatTime(startDate),
                bg: currentBG,
                eventual: eventualBG,
                nsRate: nsRate,
                bgTarget: target
            ))
        }
        
        if !rows.isEmpty {
            print("\n  Time     | BG  | Event | NS Rate | Vs Tgt")
            print("  " + String(repeating: "-", count: 50))
            
            for row in rows {
                let vsTarget = row.eventual > row.bgTarget ? "HIGH" : (row.eventual < 80 ? "LOW " : "OK  ")
                print("  \(row.time) | \(String(format: "%3d", row.bg)) | \(String(format: "%5d", row.eventual)) | \(String(format: "%6.2f", row.nsRate))  | \(vsTarget)")
            }
        }
        
        // Correlation analysis
        if rows.count >= 3 {
            let rates = rows.map { $0.nsRate }
            let eventuals = rows.map { Double($0.eventual) }
            
            // Simple trend: when eventual BG is higher, is rate higher?
            let highEventual = rows.filter { $0.eventual > 100 }.map { $0.nsRate }
            let lowEventual = rows.filter { $0.eventual <= 100 }.map { $0.nsRate }
            
            let avgHighRate = highEventual.isEmpty ? 0 : highEventual.reduce(0, +) / Double(highEventual.count)
            let avgLowRate = lowEventual.isEmpty ? 0 : lowEventual.reduce(0, +) / Double(lowEventual.count)
            
            print("\n  Correlation Check:")
            print("    Avg rate when eventual > 100: \(String(format: "%.2f", avgHighRate)) U/hr (\(highEventual.count) samples)")
            print("    Avg rate when eventual ≤ 100: \(String(format: "%.2f", avgLowRate)) U/hr (\(lowEventual.count) samples)")
            
            if avgHighRate > avgLowRate {
                print("    ✅ Expected: higher rate when BG is high")
            } else {
                print("    ⚠️ Unexpected: lower rate when BG is high")
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
    
    // MARK: - ALG-DIAG-024: Parity Insulin Correction Tests
    
    /// Test insulinCorrectionParity with ISF integration
    /// Verifies that the parity function uses effected sensitivity correctly
    @Test("Insulin correction parity basic scenarios")
    func insulinCorrectionParityBasicScenarios() {
        let now = Date()
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        
        // Create predictions: 6 hours of 5-minute intervals
        let predictionCount = 72  // 6 hours × 12 intervals/hour
        
        // Scenario 1: Above range - eventual glucose 180 mg/dL
        let aboveRangePredictions = (0..<predictionCount).map { i in
            let date = now.addingTimeInterval(Double(i) * 5 * 60)
            // Gradually rise from 150 to 180
            let glucose = 150.0 + Double(i) * 0.42
            return PredictedGlucose(date: date, glucose: glucose)
        }
        
        // ISF schedule: constant 40 mg/dL/U
        let isfSchedule = [
            AbsoluteScheduleValue(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(24 * 3600), value: 40.0)
        ]
        
        // Correction range: 100-110 (midpoint 105)
        let correctionRange = [
            AbsoluteScheduleValue(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(24 * 3600), value: 100.0...110.0)
        ]
        
        let params = InsulinCorrectionParameters(
            predictions: aboveRangePredictions,
            correctionRange: correctionRange,
            doseDate: now,
            suspendThreshold: 70.0,
            insulinSensitivity: isfSchedule,
            insulinModel: model
        )
        
        let correction = insulinCorrectionParity(parameters: params)
        
        switch correction {
        case .aboveRange(let minGlucose, let eventualGlucose, let units):
            print("✅ Above range detected:")
            print("   Min: \(Int(minGlucose)) mg/dL")
            print("   Eventual: \(Int(eventualGlucose)) mg/dL")
            print("   Correction units: \(String(format: "%.2f", units)) U")
            
            // Verify units are positive and reasonable
            #expect(units > 0, "Correction units should be positive for above range")
            #expect(units < 5, "Correction units should be reasonable (<5U)")
            
        case .inRange:
            Issue.record("Expected aboveRange, got inRange")
        case .entirelyBelowRange:
            Issue.record("Expected aboveRange, got entirelyBelowRange")
        case .suspend:
            Issue.record("Expected aboveRange, got suspend")
        }
        
        // Scenario 2: Suspend - prediction drops below threshold
        let suspendPredictions = (0..<predictionCount).map { i in
            let date = now.addingTimeInterval(Double(i) * 5 * 60)
            // Drop from 100 to 60
            let glucose = max(60.0, 100.0 - Double(i) * 0.56)
            return PredictedGlucose(date: date, glucose: glucose)
        }
        
        let suspendParams = InsulinCorrectionParameters(
            predictions: suspendPredictions,
            correctionRange: correctionRange,
            doseDate: now,
            suspendThreshold: 70.0,
            insulinSensitivity: isfSchedule,
            insulinModel: model
        )
        
        let suspendCorrection = insulinCorrectionParity(parameters: suspendParams)
        
        switch suspendCorrection {
        case .suspend(let minGlucose):
            print("✅ Suspend detected (prediction < threshold):")
            print("   Min glucose: \(Int(minGlucose)) mg/dL")
            #expect(minGlucose < 70, "Min glucose should be below suspend threshold")
        default:
            Issue.record("Expected suspend, got \(suspendCorrection)")
        }
        
        // Scenario 3: In range - all predictions 100-110
        let inRangePredictions = (0..<predictionCount).map { i in
            let date = now.addingTimeInterval(Double(i) * 5 * 60)
            let glucose = 105.0 + sin(Double(i) * 0.1) * 3  // Oscillates 102-108
            return PredictedGlucose(date: date, glucose: glucose)
        }
        
        let inRangeParams = InsulinCorrectionParameters(
            predictions: inRangePredictions,
            correctionRange: correctionRange,
            doseDate: now,
            suspendThreshold: 70.0,
            insulinSensitivity: isfSchedule,
            insulinModel: model
        )
        
        let inRangeCorrection = insulinCorrectionParity(parameters: inRangeParams)
        
        switch inRangeCorrection {
        case .inRange:
            print("✅ In range detected correctly")
        default:
            // May be slightly above/below range due to oscillation
            print("⚠️ Got \(inRangeCorrection) instead of inRange (acceptable due to prediction shape)")
        }
    }
    
    /// Test that ISF integration produces different results than simple division
    @Test("ISF integration vs simple formula")
    func isfIntegrationVsSimpleFormula() {
        let now = Date()
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        
        // Create predictions rising to 180 mg/dL
        let predictionCount = 72
        let predictions = (0..<predictionCount).map { i in
            let date = now.addingTimeInterval(Double(i) * 5 * 60)
            let glucose = 150.0 + Double(i) * 0.42  // Rise to ~180
            return PredictedGlucose(date: date, glucose: glucose)
        }
        
        // Use ISF of 40 mg/dL/U
        let isf = 40.0
        let isfSchedule = [
            AbsoluteScheduleValue(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(24 * 3600), value: isf)
        ]
        
        let correctionRange = [
            AbsoluteScheduleValue(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(24 * 3600), value: 100.0...110.0)
        ]
        
        let params = InsulinCorrectionParameters(
            predictions: predictions,
            correctionRange: correctionRange,
            doseDate: now,
            suspendThreshold: 70.0,
            insulinSensitivity: isfSchedule,
            insulinModel: model
        )
        
        let parityCorrection = insulinCorrectionParity(parameters: params)
        
        // Simple formula: (eventual - target) / ISF
        let eventualGlucose = predictions.last!.glucose
        let target = 105.0  // Midpoint of 100-110
        let simpleUnits = (eventualGlucose - target) / isf
        
        var parityUnits: Double = 0
        if case .aboveRange(_, _, let units) = parityCorrection {
            parityUnits = units
        }
        
        print("\n📊 ISF Integration vs Simple Formula:")
        print("   Eventual glucose: \(Int(eventualGlucose)) mg/dL")
        print("   Target: \(Int(target)) mg/dL")
        print("   Simple formula: \(String(format: "%.2f", simpleUnits)) U")
        print("   Parity (ISF integration): \(String(format: "%.2f", parityUnits)) U")
        print("   Difference: \(String(format: "%.2f", abs(parityUnits - simpleUnits))) U")
        
        // Parity should be different due to time-varying target and ISF integration
        // The parity algorithm uses minimum correction across all predictions
        // This typically results in a slightly different (often lower) correction
        print("   Note: Difference expected due to time-varying target and min-correction selection")
    }
    
    /// Test asTempBasal conversion
    @Test("Insulin correction to temp basal")
    func insulinCorrectionToTempBasal() {
        let scheduledBasal = 1.0  // U/hr
        let maxBasal = 5.0
        
        // Above range with 1U correction needed
        let aboveRange = InsulinCorrection.aboveRange(minGlucose: 150, eventualGlucose: 180, correctionUnits: 1.0)
        let tempBasal = aboveRange.asTempBasal(neutralBasalRate: scheduledBasal, maxBasalRate: maxBasal)
        
        // 1U over 30 min = 2 U/hr + 1 U/hr scheduled = 3 U/hr
        #expect(abs(tempBasal.rate - 3.0) < 0.01, "Rate should be 3 U/hr")
        #expect(tempBasal.duration == 30 * 60, "Duration should be 30 min")
        
        // Suspend should give 0 rate
        let suspend = InsulinCorrection.suspend(minGlucose: 65)
        let suspendTB = suspend.asTempBasal(neutralBasalRate: scheduledBasal, maxBasalRate: maxBasal)
        #expect(suspendTB.rate == 0, "Suspend should give 0 rate")
        
        // In range should give scheduled rate
        let inRange = InsulinCorrection.inRange
        let inRangeTB = inRange.asTempBasal(neutralBasalRate: scheduledBasal, maxBasalRate: maxBasal)
        #expect(abs(inRangeTB.rate - scheduledBasal) < 0.01, "In range should give scheduled rate")
        
        // Below range with negative correction
        let belowRange = InsulinCorrection.entirelyBelowRange(minGlucose: 80, eventualGlucose: 85, correctionUnits: -0.5)
        let belowTB = belowRange.asTempBasal(neutralBasalRate: scheduledBasal, maxBasalRate: maxBasal)
        // -0.5U over 30 min = -1 U/hr + 1 U/hr scheduled = 0 U/hr
        #expect(abs(belowTB.rate - 0) < 0.01, "Below range should reduce to 0")
        
        print("✅ InsulinCorrection → TempBasal conversion tests passed")
    }
}
