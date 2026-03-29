// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SettingsDiagnosisTests.swift
// T1Pal Mobile
//
// Diagnose settings loading: ISF, CR, basal schedule, targets from NS profile
// Requirements: ALG-DIAG-005
//
// Purpose: Verify we're loading and using the same settings as Loop
// to eliminate settings misalignment as a divergence cause.
//
// Trace: ALG-DIAG-005, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for settings alignment with Nightscout profile
/// Trace: ALG-DIAG-005
@Suite("Settings Diagnosis")
struct SettingsDiagnosisTests {
    
    // MARK: - Test Fixture Loading
    
    struct NSProfile: Codable {
        let _id: String
        let defaultProfile: String?
        let loopSettings: LoopSettings?
        let store: [String: ProfileData]?
        let units: String?
        
        struct LoopSettings: Codable {
            let dosingStrategy: String?
            let maximumBasalRatePerHour: Double?
            let maximumBolus: Double?
            let minimumBGGuard: Double?
            let dosingEnabled: Bool?
        }
        
        struct ProfileData: Codable {
            let basal: [ScheduleEntry]?
            let sens: [ScheduleEntry]?
            let carbratio: [ScheduleEntry]?
            let target_low: [ScheduleEntry]?
            let target_high: [ScheduleEntry]?
            let dia: Double?
            let timezone: String?
            let units: String?
            
            struct ScheduleEntry: Codable {
                let time: String
                let value: Double
                let timeAsSeconds: Int?
            }
        }
    }
    
    // MARK: - ALG-DIAG-005: Settings Diagnosis
    
    @Test("Profile settings summary")
    func profileSettingsSummary() throws {
        let profiles = try loadProfileFixture()
        #expect(!profiles.isEmpty, "Should have profile entries")
        
        guard let profile = profiles.first,
              let defaultName = profile.defaultProfile,
              let profileData = profile.store?[defaultName] else {
            print("⏭️ Could not find default profile")
            return
        }
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 ALG-DIAG-005: Settings Diagnosis Report")
        print(String(repeating: "=", count: 70))
        
        print("\nProfile: \(defaultName)")
        print("Units: \(profileData.units ?? profile.units ?? "mg/dL")")
        print("Timezone: \(profileData.timezone ?? "?")")
        print("DIA: \(profileData.dia ?? 0) hours")
        
        // Basal Schedule
        if let basal = profileData.basal {
            print("\n📋 Basal Schedule (\(basal.count) entries):")
            for entry in basal {
                print("  \(entry.time): \(String(format: "%.2f", entry.value)) U/hr")
            }
        }
        
        // ISF Schedule
        if let sens = profileData.sens {
            print("\n📋 ISF Schedule (\(sens.count) entries):")
            for entry in sens {
                print("  \(entry.time): \(String(format: "%.0f", entry.value)) mg/dL/U")
            }
        }
        
        // Carb Ratio Schedule
        if let carbratio = profileData.carbratio {
            print("\n📋 Carb Ratio Schedule (\(carbratio.count) entries):")
            for entry in carbratio {
                print("  \(entry.time): \(String(format: "%.1f", entry.value)) g/U")
            }
        }
        
        // Target Range
        if let targetLow = profileData.target_low,
           let targetHigh = profileData.target_high {
            print("\n📋 Target Range:")
            for (low, high) in zip(targetLow, targetHigh) {
                print("  \(low.time): \(String(format: "%.0f", low.value))-\(String(format: "%.0f", high.value)) mg/dL")
            }
        }
        
        // Loop Settings
        if let loopSettings = profile.loopSettings {
            print("\n📋 Loop Settings:")
            print("  Dosing Strategy: \(loopSettings.dosingStrategy ?? "?")")
            print("  Max Basal Rate: \(String(format: "%.1f", loopSettings.maximumBasalRatePerHour ?? 0)) U/hr")
            print("  Max Bolus: \(String(format: "%.1f", loopSettings.maximumBolus ?? 0)) U")
            print("  Min BG Guard: \(String(format: "%.0f", loopSettings.minimumBGGuard ?? 0)) mg/dL")
            print("  Dosing Enabled: \(loopSettings.dosingEnabled ?? false)")
        }
        
        print(String(repeating: "=", count: 70))
    }
    
    @Test("Basal schedule rate at specific times")
    func basalScheduleRateAtSpecificTimes() throws {
        let profiles = try loadProfileFixture()
        guard let profile = profiles.first,
              let defaultName = profile.defaultProfile,
              let profileData = profile.store?[defaultName],
              let basal = profileData.basal else {
            print("⏭️ Could not find basal schedule")
            return
        }
        
        // Test specific time lookups
        let testCases: [(hour: Int, minute: Int, expected: Double)] = [
            (0, 0, 1.8),    // 00:00 -> 1.8
            (3, 0, 1.8),    // 03:00 -> 1.8
            (5, 30, 1.7),   // 05:30 -> 1.7
            (12, 0, 1.7),   // 12:00 -> 1.7
            (21, 0, 1.7),   // 21:00 -> 1.7
            (22, 30, 1.8),  // 22:30 -> 1.8
            (23, 59, 1.8),  // 23:59 -> 1.8
        ]
        
        print("\n📊 Basal Schedule Lookup Test:")
        
        var allPassed = true
        for testCase in testCases {
            let secondsIntoDay = testCase.hour * 3600 + testCase.minute * 60
            let actualRate = getBasalRate(at: secondsIntoDay, from: basal)
            let passed = abs(actualRate - testCase.expected) < 0.01
            let symbol = passed ? "✅" : "❌"
            print("  \(symbol) \(String(format: "%02d:%02d", testCase.hour, testCase.minute)): expected \(testCase.expected), got \(String(format: "%.2f", actualRate))")
            if !passed { allPassed = false }
        }
        
        #expect(allPassed, "All basal rate lookups should match expected values")
    }
    
    @Test("ISF and CR at test data time")
    func isfAndCRAtTestDataTime() throws {
        let profiles = try loadProfileFixture()
        guard let profile = profiles.first,
              let defaultName = profile.defaultProfile,
              let profileData = profile.store?[defaultName] else {
            print("⏭️ Could not find profile data")
            return
        }
        
        // Test data is around 21:xx (9 PM)
        let testHour = 21
        let testMinute = 30
        let secondsIntoDay = testHour * 3600 + testMinute * 60
        
        print("\n📊 Settings at Test Data Time (\(testHour):\(String(format: "%02d", testMinute))):")
        
        // ISF
        if let sens = profileData.sens {
            let isf = getSetting(at: secondsIntoDay, from: sens)
            print("  ISF: \(String(format: "%.0f", isf)) mg/dL/U")
            #expect(abs(isf - 40.0) < 0.1, "ISF should be 40 mg/dL/U")
        }
        
        // Carb Ratio
        if let carbratio = profileData.carbratio {
            let cr = getSetting(at: secondsIntoDay, from: carbratio)
            print("  CR: \(String(format: "%.0f", cr)) g/U")
            #expect(abs(cr - 10.0) < 0.1, "CR should be 10 g/U")
        }
        
        // Basal
        if let basal = profileData.basal {
            let basalRate = getBasalRate(at: secondsIntoDay, from: basal)
            print("  Basal: \(String(format: "%.2f", basalRate)) U/hr")
            #expect(abs(basalRate - 1.7) < 0.01, "Basal at 21:30 should be 1.7 U/hr")
        }
        
        // DIA
        let dia = profileData.dia ?? 6.0
        print("  DIA: \(dia) hours")
        #expect(abs(dia - 6.0) < 0.5, "DIA should be around 6 hours")
    }
    
    @Test("Settings vs hardcoded values")
    func settingsVsHardcodedValues() throws {
        let profiles = try loadProfileFixture()
        guard let profile = profiles.first,
              let defaultName = profile.defaultProfile,
              let profileData = profile.store?[defaultName],
              let basal = profileData.basal else {
            print("⏭️ Could not find profile data")
            return
        }
        
        // Compare against hardcoded values used in IOBDivergenceDiagnosisTests
        let hardcodedBasalRate: Double = 1.7  // From IOBDivergenceDiagnosisTests
        
        // At 21:00-22:30, the scheduled rate should be 1.7 U/hr
        let secondsAt21 = 21 * 3600
        let actualRate = getBasalRate(at: secondsAt21, from: basal)
        
        print("\n📊 Settings Consistency Check:")
        print("  Hardcoded basal (IOBDivergenceDiagnosisTests): \(hardcodedBasalRate) U/hr")
        print("  Profile basal at 21:00: \(String(format: "%.2f", actualRate)) U/hr")
        
        if abs(actualRate - hardcodedBasalRate) < 0.01 {
            print("  ✅ Values match")
        } else {
            print("  ⚠️ Values differ - update hardcoded value!")
        }
        
        #expect(abs(actualRate - hardcodedBasalRate) < 0.01,
               "Hardcoded basal rate should match profile")
    }
    
    // MARK: - Helpers
    
    func getBasalRate(at secondsIntoDay: Int, from entries: [NSProfile.ProfileData.ScheduleEntry]) -> Double {
        var activeValue = entries.first?.value ?? 0
        for entry in entries {
            let entrySeconds = entry.timeAsSeconds ?? parseTimeToSeconds(entry.time)
            if entrySeconds <= secondsIntoDay {
                activeValue = entry.value
            }
        }
        return activeValue
    }
    
    func getSetting(at secondsIntoDay: Int, from entries: [NSProfile.ProfileData.ScheduleEntry]) -> Double {
        return getBasalRate(at: secondsIntoDay, from: entries)
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
    
    func loadProfileFixture() throws -> [NSProfile] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_profile_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSProfile].self, from: data)
    }
}
