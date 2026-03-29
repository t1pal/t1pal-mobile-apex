// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DoseHistoryDiagnosisTests.swift
// T1Pal Mobile
//
// Diagnose dose history reconstruction: are we getting the same doses as Loop?
// Requirements: ALG-DIAG-004
//
// Purpose: Compare dose data we load from NS treatments against what
// Loop would have seen to identify reconstruction errors.
//
// Trace: ALG-DIAG-004, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for dose history reconstruction diagnosis
/// Trace: ALG-DIAG-004
@Suite("Dose History Diagnosis")
struct DoseHistoryDiagnosisTests {
    
    // MARK: - Test Fixture Loading
    
    struct NSTreatment: Codable {
        let _id: String
        let eventType: String?
        let timestamp: String?
        let created_at: String?
        let rate: Double?
        let absolute: Double?
        let duration: Double?
        let amount: Double?
        let insulin: Double?
        let automatic: Bool?
    }
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let iob: IOBData?
            
            struct IOBData: Codable {
                let timestamp: String
                let iob: Double
            }
        }
    }
    
    struct NSProfile: Codable {
        let defaultProfile: String?
        let store: [String: ProfileData]?
        
        struct ProfileData: Codable {
            let basal: [BasalEntry]?
            
            struct BasalEntry: Codable {
                let time: String
                let value: Double
                let timeAsSeconds: Int?
            }
        }
    }
    
    // MARK: - ALG-DIAG-004: Dose History Analysis
    
    @Test("Dose history summary")
    func doseHistorySummary() throws {
        let treatments = try loadTreatmentsFixture()
        #expect(!treatments.isEmpty, "Should have treatment entries")
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 ALG-DIAG-004: Dose History Diagnosis Report")
        print(String(repeating: "=", count: 70))
        
        // Group by event type
        var byType: [String: [NSTreatment]] = [:]
        for t in treatments {
            let eventType = t.eventType ?? "Unknown"
            byType[eventType, default: []].append(t)
        }
        
        print("\nDose Types in Fixture:")
        for (type, items) in byType.sorted(by: { $0.key < $1.key }) {
            print("  \(type): \(items.count) events")
        }
        
        // Analyze temp basals specifically
        let tempBasals = byType["Temp Basal"] ?? []
        if !tempBasals.isEmpty {
            analyzeTempBasals(tempBasals)
        }
        
        // Analyze boluses
        let boluses = (byType["Bolus"] ?? []) + 
                      (byType["Correction Bolus"] ?? []) + 
                      (byType["SMB"] ?? [])
        if !boluses.isEmpty {
            analyzeBoluses(boluses)
        }
        
        print(String(repeating: "=", count: 70))
    }
    
    @Test("Temp basal net calculation")
    func tempBasalNetCalculation() throws {
        let treatments = try loadTreatmentsFixture()
        let profile = try loadProfileFixture()
        
        // Get scheduled basal rate
        let scheduledRate = getScheduledBasalRate(from: profile, at: Date())
        
        print("\n📊 Temp Basal Net Calculation Analysis")
        print("  Scheduled basal rate: \(String(format: "%.2f", scheduledRate)) U/hr")
        
        let tempBasals = treatments.filter { $0.eventType == "Temp Basal" }
        
        var totalDelivered: Double = 0
        var totalScheduled: Double = 0
        var totalNet: Double = 0
        
        for tb in tempBasals {
            let rate = tb.rate ?? tb.absolute ?? 0
            let durationMin = tb.duration ?? 30
            let durationHrs = durationMin / 60.0
            
            let delivered = rate * durationHrs
            let scheduled = scheduledRate * durationHrs
            let net = delivered - scheduled
            
            totalDelivered += delivered
            totalScheduled += scheduled
            totalNet += net
        }
        
        print("\n  Temp Basal Summary (\(tempBasals.count) events):")
        print("    Total delivered:  \(String(format: "%.3f", totalDelivered)) U")
        print("    Total scheduled:  \(String(format: "%.3f", totalScheduled)) U")
        print("    Total NET:        \(String(format: "%.3f", totalNet)) U")
        
        // The NET should be close to the IOB contribution from temp basals
        // If we're seeing higher IOB divergence, it could be:
        // 1. Not using NET calculation
        // 2. Wrong scheduled rate
        // 3. Missing dose events
        
        print("\n  ⚠️ Key Insight:")
        print("    If IOB divergence is ~2.5U higher than expected,")
        print("    check: using absolute instead of net temp basal?")
        print("    Difference: \(String(format: "%.3f", totalDelivered)) U (abs) vs \(String(format: "%.3f", totalNet)) U (net)")
    }
    
    @Test("IOB with different models")
    func iobWithDifferentModels() throws {
        let treatments = try loadTreatmentsFixture()
        let deviceStatuses = try loadDeviceStatusFixture()
        let profile = try loadProfileFixture()
        
        // Find a deviceStatus with IOB
        guard let status = deviceStatuses.first(where: { $0.loop?.iob != nil }),
              let loopIOB = status.loop?.iob,
              let timestamp = parseDate(loopIOB.timestamp) else {
            print("⏭️ No deviceStatus with IOB found")
            return
        }
        
        let nsIOB = loopIOB.iob
        let scheduledRate = getScheduledBasalRate(from: profile, at: timestamp)
        
        print("\n📊 IOB Model Comparison at \(formatTime(timestamp))")
        print("  NS reported IOB: \(String(format: "%.3f", nsIOB)) U")
        print("  Scheduled basal: \(String(format: "%.2f", scheduledRate)) U/hr")
        
        // Calculate IOB with different approaches
        let iobAbsolute = calculateIOB(at: timestamp, treatments: treatments, 
                                        scheduledRate: 0, // absolute
                                        label: "Absolute (no net)")
        
        let iobNet = calculateIOB(at: timestamp, treatments: treatments,
                                   scheduledRate: scheduledRate,
                                   label: "Net (scheduled subtracted)")
        
        print("\n  Results:")
        print("    Absolute IOB: \(String(format: "%.3f", iobAbsolute)) U (Δ=\(String(format: "%.3f", abs(iobAbsolute - nsIOB))))")
        print("    Net IOB:      \(String(format: "%.3f", iobNet)) U (Δ=\(String(format: "%.3f", abs(iobNet - nsIOB))))")
        
        // Which is closer?
        let absError = abs(iobAbsolute - nsIOB)
        let netError = abs(iobNet - nsIOB)
        
        if netError < absError {
            print("\n  ✅ Net calculation is closer to NS (as expected)")
        } else {
            print("\n  ⚠️ Absolute calculation is closer - investigate further")
        }
    }
    
    // MARK: - Analysis Helpers
    
    func analyzeTempBasals(_ tempBasals: [NSTreatment]) {
        print("\nTemp Basal Analysis:")
        
        // Time range
        let dates = tempBasals.compactMap { t -> Date? in
            guard let ts = t.timestamp ?? t.created_at else { return nil }
            return parseDate(ts)
        }
        
        if let minDate = dates.min(), let maxDate = dates.max() {
            print("  Time range: \(formatTime(minDate)) - \(formatTime(maxDate))")
            print("  Duration: \(String(format: "%.1f", maxDate.timeIntervalSince(minDate) / 3600)) hours")
        }
        
        // Rate statistics
        let rates = tempBasals.compactMap { $0.rate ?? $0.absolute }
        if !rates.isEmpty {
            let avgRate = rates.reduce(0, +) / Double(rates.count)
            print("  Rate range: \(String(format: "%.2f", rates.min() ?? 0)) - \(String(format: "%.2f", rates.max() ?? 0)) U/hr")
            print("  Avg rate: \(String(format: "%.2f", avgRate)) U/hr")
        }
        
        // Duration statistics
        let durations = tempBasals.compactMap { $0.duration }
        if !durations.isEmpty {
            let avgDuration = durations.reduce(0, +) / Double(durations.count)
            print("  Avg duration: \(String(format: "%.0f", avgDuration)) min")
        }
        
        // Show first few
        print("\n  Sample (first 5):")
        for (i, tb) in tempBasals.prefix(5).enumerated() {
            let ts = tb.timestamp ?? tb.created_at ?? "?"
            let rate = tb.rate ?? tb.absolute ?? 0
            let dur = tb.duration ?? 0
            print("    \(i+1). \(formatTimeStr(ts)): \(String(format: "%.2f", rate)) U/hr × \(String(format: "%.0f", dur)) min")
        }
    }
    
    func analyzeBoluses(_ boluses: [NSTreatment]) {
        print("\nBolus Analysis:")
        print("  Total boluses: \(boluses.count)")
        
        let amounts = boluses.compactMap { $0.insulin ?? $0.amount }
        if !amounts.isEmpty {
            let total = amounts.reduce(0, +)
            print("  Total insulin: \(String(format: "%.2f", total)) U")
            print("  Avg bolus: \(String(format: "%.2f", total / Double(amounts.count))) U")
        }
    }
    
    func calculateIOB(at date: Date, treatments: [NSTreatment], 
                      scheduledRate: Double, label: String) -> Double {
        var totalIOB: Double = 0.0
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        let activityWindow: TimeInterval = 6 * 3600 + 10 * 60
        
        for treatment in treatments {
            guard let eventType = treatment.eventType,
                  let timestampStr = treatment.timestamp ?? treatment.created_at,
                  let doseDate = parseDate(timestampStr) else {
                continue
            }
            
            let age = date.timeIntervalSince(doseDate)
            guard age >= 0 && age <= activityWindow else { continue }
            
            let isTempBasal = eventType == "Temp Basal"
            let volume: Double
            
            if let insulin = treatment.insulin, insulin > 0 {
                volume = insulin
            } else if isTempBasal {
                let rate = treatment.rate ?? treatment.absolute ?? 0
                let durationMin = treatment.duration ?? 30
                let durationHrs = durationMin / 60.0
                let delivered = rate * durationHrs
                let scheduled = scheduledRate * durationHrs
                volume = delivered - scheduled
            } else if let amount = treatment.amount, amount > 0 {
                volume = amount
            } else {
                continue
            }
            
            let percentRemaining = model.percentEffectRemaining(at: age)
            totalIOB += volume * percentRemaining
        }
        
        return totalIOB
    }
    
    func getScheduledBasalRate(from profile: [NSProfile], at date: Date) -> Double {
        // Get the basal schedule from the active profile
        guard let activeProfile = profile.first,
              let defaultName = activeProfile.defaultProfile,
              let profileData = activeProfile.store?[defaultName],
              let basalEntries = profileData.basal,
              !basalEntries.isEmpty else {
            return 1.7  // fallback
        }
        
        // Find the rate active at the given time
        let calendar = Calendar.current
        let secondsIntoDay = calendar.component(.hour, from: date) * 3600 +
                             calendar.component(.minute, from: date) * 60 +
                             calendar.component(.second, from: date)
        
        var activeRate = basalEntries.first?.value ?? 1.7
        for entry in basalEntries {
            let entrySeconds = entry.timeAsSeconds ?? parseTimeToSeconds(entry.time)
            if entrySeconds <= secondsIntoDay {
                activeRate = entry.value
            }
        }
        
        return activeRate
    }
    
    func parseTimeToSeconds(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else {
            return 0
        }
        return hours * 3600 + minutes * 60
    }
    
    // MARK: - Fixture Loaders
    
    func loadTreatmentsFixture() throws -> [NSTreatment] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_treatments_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSTreatment].self, from: data)
    }
    
    func loadDeviceStatusFixture() throws -> [NSDeviceStatus] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_devicestatus_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSDeviceStatus].self, from: data)
    }
    
    func loadProfileFixture() throws -> [NSProfile] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_profile_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSProfile].self, from: data)
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
    
    func formatTimeStr(_ str: String) -> String {
        guard let date = parseDate(str) else { return str }
        return formatTime(date)
    }
}
