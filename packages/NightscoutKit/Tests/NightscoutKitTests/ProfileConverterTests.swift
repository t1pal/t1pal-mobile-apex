// SPDX-License-Identifier: MIT
//
// ProfileConverterTests.swift
// NightscoutKitTests
//
// Tests for ProfileConverter
// Trace: CONTROL-001, agent-control-plane-integration.md

import Testing
import Foundation
@testable import NightscoutKit
@testable import T1PalAlgorithm

// MARK: - ProfileConverter Tests

@Suite("ProfileConverter")
struct ProfileConverterTests {
    
    let converter = ProfileConverter()
    
    // MARK: - Basic Conversion
    
    @Test("Converts valid profile")
    func convertsValidProfile() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)],
            timezone: "America/New_York",
            units: "mg/dL"
        )
        
        let profile = try converter.convert(store, name: "Test Profile")
        
        #expect(profile.name == "Test Profile")
        #expect(profile.dia == 5.0)
        #expect(profile.timezone == "America/New_York")
        #expect(profile.basalSchedule.entries.count == 1)
        #expect(profile.isfSchedule.entries.count == 1)
        #expect(profile.icrSchedule.entries.count == 1)
        #expect(profile.targetSchedule.entries.count == 1)
    }
    
    @Test("Uses default DIA when not provided")
    func usesDefaultDIA() throws {
        let store = ProfileStore(
            dia: nil,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.dia == 5.0)  // Default from Config
    }
    
    @Test("Uses UTC timezone when not provided")
    func usesDefaultTimezone() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            timezone: nil
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.timezone == "UTC")
    }
    
    // MARK: - Schedule Conversions
    
    @Test("Converts multiple basal entries")
    func convertsMultipleBasalEntries() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8),
                ScheduleEntry(time: "06:00", timeAsSeconds: 21600, value: 1.0),
                ScheduleEntry(time: "12:00", timeAsSeconds: 43200, value: 0.9),
                ScheduleEntry(time: "18:00", timeAsSeconds: 64800, value: 0.85)
            ],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.basalSchedule.entries.count == 4)
        #expect(profile.basalSchedule.entries[0].rate == 0.8)
        #expect(profile.basalSchedule.entries[1].rate == 1.0)
        #expect(profile.basalSchedule.entries[2].rate == 0.9)
        #expect(profile.basalSchedule.entries[3].rate == 0.85)
    }
    
    @Test("Converts ISF entries")
    func convertsISFEntries() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50),
                ScheduleEntry(time: "12:00", timeAsSeconds: 43200, value: 40)
            ],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.isfSchedule.entries.count == 2)
        #expect(profile.isfSchedule.entries[0].sensitivity == 50)
        #expect(profile.isfSchedule.entries[1].sensitivity == 40)
    }
    
    @Test("Converts ICR entries")
    func convertsICREntries() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 12),
                ScheduleEntry(time: "08:00", timeAsSeconds: 28800, value: 10),
                ScheduleEntry(time: "18:00", timeAsSeconds: 64800, value: 14)
            ],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.icrSchedule.entries.count == 3)
        #expect(profile.icrSchedule.entries[0].ratio == 12)
        #expect(profile.icrSchedule.entries[1].ratio == 10)
        #expect(profile.icrSchedule.entries[2].ratio == 14)
    }
    
    @Test("Converts target range entries")
    func convertsTargetRangeEntries() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100),
                ScheduleEntry(time: "22:00", timeAsSeconds: 79200, value: 110)
            ],
            target_high: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 120),
                ScheduleEntry(time: "22:00", timeAsSeconds: 79200, value: 130)
            ]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.targetSchedule.entries.count == 2)
        #expect(profile.targetSchedule.entries[0].low == 100)
        #expect(profile.targetSchedule.entries[0].high == 120)
        #expect(profile.targetSchedule.entries[1].low == 110)
        #expect(profile.targetSchedule.entries[1].high == 130)
    }
    
    // MARK: - Unit Conversion
    
    @Test("Converts mmol/L ISF to mg/dL")
    func convertsMMOLISF() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 2.8)],  // mmol/L
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 5.5)],  // mmol/L
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 6.1)],
            units: "mmol/L"
        )
        
        let profile = try converter.convert(store)
        
        // 2.8 mmol/L * 18.0182 ≈ 50.45
        #expect(profile.isfSchedule.entries[0].sensitivity > 50)
        #expect(profile.isfSchedule.entries[0].sensitivity < 51)
        
        // Targets should also be converted
        #expect(profile.targetSchedule.entries[0].low > 99)  // 5.5 * 18 ≈ 99
        #expect(profile.targetSchedule.entries[0].low < 100)
    }
    
    @Test("Handles mg/dL units without conversion")
    func handlesMGDLUnits() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            units: "mg/dL"
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.isfSchedule.entries[0].sensitivity == 50)
        #expect(profile.targetSchedule.entries[0].low == 100)
    }
    
    // MARK: - Error Handling
    
    @Test("Throws for empty basal schedule")
    func throwsForEmptyBasal() {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        #expect(throws: ProfileConverter.ConversionError.self) {
            try converter.convert(store)
        }
    }
    
    @Test("Throws for empty sensitivity schedule")
    func throwsForEmptySens() {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        #expect(throws: ProfileConverter.ConversionError.self) {
            try converter.convert(store)
        }
    }
    
    @Test("Throws for empty carb ratio schedule")
    func throwsForEmptyCarbratio() {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        #expect(throws: ProfileConverter.ConversionError.self) {
            try converter.convert(store)
        }
    }
    
    @Test("Throws for nil basal schedule")
    func throwsForNilBasal() {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: nil,
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        #expect(throws: ProfileConverter.ConversionError.self) {
            try converter.convert(store)
        }
    }
    
    // MARK: - Time Parsing
    
    @Test("Parses time from timeAsSeconds")
    func parsesTimeAsSeconds() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: nil, timeAsSeconds: 28800, value: 10)],  // 8:00 AM
            sens: [ScheduleEntry(time: nil, timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: nil, timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: nil, timeAsSeconds: 0, value: 100)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.icrSchedule.entries[0].startTime == 28800)
    }
    
    @Test("Parses time from time string")
    func parsesTimeString() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "08:30", timeAsSeconds: nil, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: nil, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: nil, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: nil, value: 100)]
        )
        
        let profile = try converter.convert(store)
        
        // 8:30 = 8*3600 + 30*60 = 28800 + 1800 = 30600
        #expect(profile.icrSchedule.entries[0].startTime == 30600)
    }
}

// MARK: - NightscoutProfile Extension Tests

@Suite("NightscoutProfile Conversion")
struct NightscoutProfileConversionTests {
    
    @Test("Converts active profile")
    func convertsActiveProfile() throws {
        let profileStore = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)]
        )
        
        let nsProfile = NightscoutProfile(
            defaultProfile: "Default",
            startDate: "2026-02-03T00:00:00Z",
            store: ["Default": profileStore]
        )
        
        let profile = try nsProfile.toAlgorithmProfile()
        
        #expect(profile != nil)
        #expect(profile?.name == "Default")
    }
    
    @Test("Returns nil for empty profile")
    func returnsNilForEmptyProfile() throws {
        let nsProfile = NightscoutProfile(
            defaultProfile: "Missing",
            startDate: "2026-02-03T00:00:00Z",
            store: [:]
        )
        
        let profile = try nsProfile.toAlgorithmProfile()
        
        #expect(profile == nil)
    }
    
    @Test("Converts all profiles")
    func convertsAllProfiles() throws {
        let store1 = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        let store2 = ProfileStore(
            dia: 6.0,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 12)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 45)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 1.0)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)]
        )
        
        let nsProfile = NightscoutProfile(
            defaultProfile: "Default",
            startDate: "2026-02-03T00:00:00Z",
            store: ["Default": store1, "Exercise": store2]
        )
        
        let allProfiles = nsProfile.allAsAlgorithmProfiles()
        
        #expect(allProfiles.count == 2)
        
        if case .success(let defaultProfile) = allProfiles["Default"] {
            #expect(defaultProfile.dia == 5.0)
        } else {
            #expect(Bool(false), "Expected Default profile to succeed")
        }
        
        if case .success(let exerciseProfile) = allProfiles["Exercise"] {
            #expect(exerciseProfile.dia == 6.0)
        } else {
            #expect(Bool(false), "Expected Exercise profile to succeed")
        }
    }
}

// MARK: - Config Tests

@Suite("ProfileConverter Config")
struct ProfileConverterConfigTests {
    
    @Test("Default config has expected values")
    func defaultConfigValues() {
        let config = ProfileConverter.Config.default
        
        #expect(config.defaultDIA == 5.0)
        #expect(config.defaultMaxBasal == 2.0)
        #expect(config.defaultMaxBolus == 10.0)
        #expect(config.defaultMaxIOB == 8.0)
        #expect(config.defaultMaxCOB == 120.0)
        #expect(config.defaultAutosensMax == 1.2)
        #expect(config.defaultAutosensMin == 0.8)
    }
    
    @Test("Custom config applied")
    func customConfigApplied() throws {
        let customConfig = ProfileConverter.Config(
            defaultDIA: 6.0,
            defaultMaxBasal: 3.0,
            defaultMaxBolus: 15.0,
            defaultMaxIOB: 12.0,
            defaultMaxCOB: 150.0,
            defaultAutosensMax: 1.5,
            defaultAutosensMin: 0.7
        )
        
        let converter = ProfileConverter(config: customConfig)
        
        let store = ProfileStore(
            dia: nil,  // Should use default
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)]
        )
        
        let profile = try converter.convert(store)
        
        #expect(profile.dia == 6.0)  // From custom config
        #expect(profile.maxBasal == 3.0)
        #expect(profile.maxBolus == 15.0)
        #expect(profile.maxIOB == 12.0)
        #expect(profile.maxCOB == 150.0)
        #expect(profile.autosensMax == 1.5)
        #expect(profile.autosensMin == 0.7)
    }
    
    @Test("mmol to mg/dL conversion factor")
    func mmolConversionFactor() {
        #expect(ProfileConverter.Config.mmolToMgdl > 18.0)
        #expect(ProfileConverter.Config.mmolToMgdl < 18.1)
    }
}

// MARK: - AlgorithmProfile Convenience Init Tests

@Suite("AlgorithmProfile Nightscout Init")
struct AlgorithmProfileNightscoutInitTests {
    
    @Test("Convenience init works")
    func convenienceInit() throws {
        let store = ProfileStore(
            dia: 5.5,
            carbratio: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8)],
            target_low: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 100)],
            target_high: [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 110)]
        )
        
        let profile = try AlgorithmProfile(fromNightscout: store, name: "My Profile")
        
        #expect(profile.name == "My Profile")
        #expect(profile.dia == 5.5)
    }
}
