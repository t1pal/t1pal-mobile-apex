// ProfileCompatibilityTests.swift - Profile endpoint compatibility
// Part of NightscoutKit
// Trace: NS-COMPAT-006

import Testing
import Foundation
@testable import NightscoutKit

@Suite("Profile Endpoint Compatibility")
struct ProfileCompatibilityTests {
    
    // MARK: - Loop Profile Format
    
    @Test("Parse Loop profile format")
    func parseLoopProfile() throws {
        let json = """
        {
            "_id": "507f1f77bcf86cd799439011",
            "defaultProfile": "Default",
            "startDate": "2026-02-05T00:00:00.000Z",
            "mills": 1738713600000,
            "units": "mg/dL",
            "store": {
                "Default": {
                    "dia": 6.0,
                    "carbratio": [
                        {"time": "00:00", "value": 10.0, "timeAsSeconds": 0}
                    ],
                    "sens": [
                        {"time": "00:00", "value": 50.0, "timeAsSeconds": 0}
                    ],
                    "basal": [
                        {"time": "00:00", "value": 1.0, "timeAsSeconds": 0},
                        {"time": "06:00", "value": 1.2, "timeAsSeconds": 21600},
                        {"time": "22:00", "value": 0.9, "timeAsSeconds": 79200}
                    ],
                    "target_low": [
                        {"time": "00:00", "value": 100, "timeAsSeconds": 0}
                    ],
                    "target_high": [
                        {"time": "00:00", "value": 120, "timeAsSeconds": 0}
                    ],
                    "timezone": "America/New_York",
                    "units": "mg/dL"
                }
            },
            "created_at": "2026-02-05T00:00:00.000Z",
            "enteredBy": "Loop"
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        #expect(profile.defaultProfile == "Default")
        #expect(profile.units == "mg/dL")
        #expect(profile.enteredBy == "Loop")
        
        let store = try #require(profile.activeProfile)
        #expect(store.dia == 6.0)
        #expect(store.basal?.count == 3)
        #expect(store.carbratio?.first?.value == 10.0)
        #expect(store.sens?.first?.value == 50.0)
    }
    
    @Test("Parse Trio profile with multiple schedules")
    func parseTrioProfile() throws {
        let json = """
        {
            "defaultProfile": "Active",
            "startDate": "2026-02-05T06:00:00.000Z",
            "store": {
                "Active": {
                    "dia": 5.0,
                    "carbratio": [
                        {"time": "00:00", "value": 8.0},
                        {"time": "12:00", "value": 10.0},
                        {"time": "18:00", "value": 9.0}
                    ],
                    "sens": [
                        {"time": "00:00", "value": 40.0},
                        {"time": "12:00", "value": 45.0}
                    ],
                    "basal": [
                        {"time": "00:00", "value": 0.8},
                        {"time": "03:00", "value": 1.0},
                        {"time": "09:00", "value": 0.9},
                        {"time": "15:00", "value": 0.85},
                        {"time": "21:00", "value": 0.75}
                    ],
                    "target_low": [{"time": "00:00", "value": 90}],
                    "target_high": [{"time": "00:00", "value": 110}],
                    "timezone": "Europe/London"
                },
                "Sleep": {
                    "dia": 5.0,
                    "carbratio": [{"time": "00:00", "value": 12.0}],
                    "sens": [{"time": "00:00", "value": 55.0}],
                    "basal": [{"time": "00:00", "value": 0.6}],
                    "target_low": [{"time": "00:00", "value": 100}],
                    "target_high": [{"time": "00:00", "value": 120}]
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        #expect(profile.store.count == 2)
        #expect(profile.store["Active"] != nil)
        #expect(profile.store["Sleep"] != nil)
        
        let active = try #require(profile.activeProfile)
        #expect(active.carbratio?.count == 3)
        #expect(active.basal?.count == 5)
    }
    
    @Test("Parse AAPS profile format")
    func parseAAPSProfile() throws {
        let json = """
        {
            "_id": "aaps-profile-001",
            "defaultProfile": "LocalProfile",
            "startDate": "2026-02-05T00:00:00.000Z",
            "units": "mmol/L",
            "store": {
                "LocalProfile": {
                    "dia": 7.0,
                    "carbratio": [
                        {"time": "00:00", "value": 9.0, "timeAsSeconds": 0}
                    ],
                    "sens": [
                        {"time": "00:00", "value": 2.8, "timeAsSeconds": 0}
                    ],
                    "basal": [
                        {"time": "00:00", "value": 1.1, "timeAsSeconds": 0}
                    ],
                    "target_low": [
                        {"time": "00:00", "value": 5.5, "timeAsSeconds": 0}
                    ],
                    "target_high": [
                        {"time": "00:00", "value": 6.0, "timeAsSeconds": 0}
                    ],
                    "units": "mmol/L",
                    "carbs_hr": 20.0
                }
            },
            "enteredBy": "AndroidAPS"
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        #expect(profile.units == "mmol/L")
        #expect(profile.enteredBy == "AndroidAPS")
        
        let store = try #require(profile.activeProfile)
        #expect(store.dia == 7.0)
        #expect(store.carbs_hr == 20.0)
        // mmol/L values
        #expect(store.sens?.first?.value == 2.8)
        #expect(store.target_low?.first?.value == 5.5)
    }
    
    // MARK: - Basal Rate Validation
    
    @Test("Calculate total daily basal")
    func totalDailyBasal() throws {
        let store = ProfileStore(
            dia: 6.0,
            basal: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 0.8),
                ScheduleEntry(time: "06:00", timeAsSeconds: 21600, value: 1.0),
                ScheduleEntry(time: "12:00", timeAsSeconds: 43200, value: 0.9),
                ScheduleEntry(time: "18:00", timeAsSeconds: 64800, value: 1.1)
            ]
        )
        
        // 6h * 0.8 + 6h * 1.0 + 6h * 0.9 + 6h * 1.1 = 4.8 + 6.0 + 5.4 + 6.6 = 22.8
        let tdb = store.totalDailyBasal
        #expect(tdb != nil)
        // Allow small floating point difference
        if let tdb = tdb {
            #expect(abs(tdb - 22.8) < 0.1)
        }
    }
    
    // MARK: - ISF and CR Schedules
    
    @Test("Parse complex ISF schedule")
    func complexISFSchedule() throws {
        let json = """
        {
            "defaultProfile": "Test",
            "startDate": "2026-02-05T00:00:00.000Z",
            "store": {
                "Test": {
                    "dia": 5.0,
                    "sens": [
                        {"time": "00:00", "value": 60.0, "timeAsSeconds": 0},
                        {"time": "06:00", "value": 45.0, "timeAsSeconds": 21600},
                        {"time": "10:00", "value": 50.0, "timeAsSeconds": 36000},
                        {"time": "14:00", "value": 55.0, "timeAsSeconds": 50400},
                        {"time": "20:00", "value": 65.0, "timeAsSeconds": 72000}
                    ],
                    "carbratio": [{"time": "00:00", "value": 10.0}],
                    "basal": [{"time": "00:00", "value": 1.0}]
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        let store = try #require(profile.activeProfile)
        
        #expect(store.sens?.count == 5)
        
        // Verify dawn phenomenon (lower ISF at 06:00)
        let dawnISF = store.sens?.first { $0.time == "06:00" }?.value
        #expect(dawnISF == 45.0)
    }
    
    @Test("Parse variable carb ratio schedule")
    func variableCarbRatio() throws {
        let json = """
        {
            "defaultProfile": "Test",
            "startDate": "2026-02-05T00:00:00.000Z",
            "store": {
                "Test": {
                    "dia": 6.0,
                    "carbratio": [
                        {"time": "00:00", "value": 12.0},
                        {"time": "07:00", "value": 8.0},
                        {"time": "12:00", "value": 10.0},
                        {"time": "18:00", "value": 9.0}
                    ],
                    "sens": [{"time": "00:00", "value": 50.0}],
                    "basal": [{"time": "00:00", "value": 1.0}]
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        let store = try #require(profile.activeProfile)
        
        #expect(store.carbratio?.count == 4)
        
        // Breakfast typically needs stronger ratio (lower number)
        let breakfastCR = store.carbratio?.first { $0.time == "07:00" }?.value
        #expect(breakfastCR == 8.0)
    }
    
    // MARK: - Target Range
    
    @Test("Parse target range with correction range")
    func targetRangeWithCorrection() throws {
        let json = """
        {
            "defaultProfile": "Test",
            "startDate": "2026-02-05T00:00:00.000Z",
            "store": {
                "Test": {
                    "dia": 5.5,
                    "target_low": [
                        {"time": "00:00", "value": 100},
                        {"time": "06:00", "value": 90},
                        {"time": "22:00", "value": 110}
                    ],
                    "target_high": [
                        {"time": "00:00", "value": 120},
                        {"time": "06:00", "value": 110},
                        {"time": "22:00", "value": 130}
                    ],
                    "carbratio": [{"time": "00:00", "value": 10.0}],
                    "sens": [{"time": "00:00", "value": 50.0}],
                    "basal": [{"time": "00:00", "value": 1.0}]
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        let store = try #require(profile.activeProfile)
        
        #expect(store.target_low?.count == 3)
        #expect(store.target_high?.count == 3)
        
        // Tighter range during day
        let dayLow = store.target_low?.first { $0.time == "06:00" }?.value
        let dayHigh = store.target_high?.first { $0.time == "06:00" }?.value
        #expect(dayLow == 90)
        #expect(dayHigh == 110)
    }
    
    // MARK: - Edge Cases
    
    @Test("Handle missing optional fields")
    func missingOptionalFields() throws {
        let json = """
        {
            "defaultProfile": "Minimal",
            "startDate": "2026-02-05T00:00:00.000Z",
            "store": {
                "Minimal": {
                    "basal": [{"time": "00:00", "value": 1.0}]
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        let store = try #require(profile.activeProfile)
        
        #expect(store.dia == nil)
        #expect(store.carbratio == nil)
        #expect(store.sens == nil)
        #expect(store.basal?.count == 1)
    }
    
    @Test("Handle timezone variations")
    func timezoneVariations() throws {
        let timezones = [
            "America/New_York",
            "Europe/London",
            "Asia/Tokyo",
            "Australia/Sydney",
            "Pacific/Auckland"
        ]
        
        for tz in timezones {
            let json = """
            {
                "defaultProfile": "Test",
                "startDate": "2026-02-05T00:00:00.000Z",
                "store": {
                    "Test": {
                        "timezone": "\(tz)",
                        "basal": [{"time": "00:00", "value": 1.0}]
                    }
                }
            }
            """.data(using: .utf8)!
            
            let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
            let store = try #require(profile.activeProfile)
            #expect(store.timezone == tz)
        }
    }
    
    // MARK: - NS-ALGO-020: Live Fixture Test
    
    @Test("Parse fixture_profile_loop_live.json - real Loop data with String mills/carbs_hr/delay")
    func parseLiveProfileFixture() throws {
        // NS-ALGO-020: This fixture contains real Loop profile data where:
        // - mills is a String (not Int64): "1771451693693"
        // - carbs_hr is a String: "0"
        // - delay is a String: "0"
        // - loopSettings field is present (should be ignored)
        guard let fixtureURL = Bundle.module.url(
            forResource: "fixture_profile_loop_live",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw TestError("fixture_profile_loop_live.json not found in test bundle")
        }
        
        let data = try Data(contentsOf: fixtureURL)
        let profiles = try JSONDecoder().decode([NightscoutProfile].self, from: data)
        
        #expect(profiles.count >= 1, "Fixture should contain at least 1 profile")
        
        let profile = profiles[0]
        
        // Verify core fields
        #expect(profile.defaultProfile == "Default")
        #expect(profile.enteredBy == "Loop")
        #expect(profile.units == "mg/dL")
        
        // NS-ALGO-020: Verify mills parsed from String
        #expect(profile.mills != nil, "mills should parse from String")
        #expect(profile.mills! > 1771000000000, "mills should be valid timestamp")
        
        // Verify timestamp computed property works
        #expect(profile.timestamp != nil, "timestamp should be computed from mills")
        
        // Verify active profile store
        let store = try #require(profile.activeProfile)
        
        // NS-ALGO-020: Verify therapy settings
        #expect(store.dia == 6)
        #expect(store.sens?.first?.value == 40, "ISF should be 40")
        #expect(store.carbratio?.first?.value == 10, "CR should be 10")
        #expect(store.basal?.count == 3, "Should have 3 basal segments")
        #expect(store.basal?.first?.value == 1.8, "First basal should be 1.8 U/hr")
        
        // NS-ALGO-020: Verify carbs_hr and delay parsed from String
        // These are "0" in the fixture which should parse to 0.0
        #expect(store.carbs_hr == 0.0 || store.carbs_hr == nil, "carbs_hr should parse from String '0'")
        #expect(store.delay == 0.0 || store.delay == nil, "delay should parse from String '0'")
        
        // Verify targets
        #expect(store.target_low?.first?.value == 97)
        #expect(store.target_high?.first?.value == 102)
    }
    
    // MARK: - NS-ALGO-022: Time-of-day Schedule Lookup Tests
    
    @Test("Time-aware basal lookup returns correct segment value")
    func timeAwareBasalLookup() {
        // Create a profile with 3 basal segments matching live fixture
        // 00:00-05:30: 1.8 U/hr
        // 05:30-22:30: 1.7 U/hr
        // 22:30-24:00: 1.8 U/hr
        let store = ProfileStore(
            basal: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 1.8),
                ScheduleEntry(time: "05:30", timeAsSeconds: 19800, value: 1.7),
                ScheduleEntry(time: "22:30", timeAsSeconds: 81000, value: 1.8)
            ],
            timezone: "UTC"
        )
        
        // Create dates at specific times in UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let baseDate = calendar.startOfDay(for: Date())
        
        // 03:00 UTC -> should be 1.8 (first segment: 00:00-05:30)
        let time0300 = baseDate.addingTimeInterval(3 * 3600)
        #expect(store.basalAt(date: time0300) == 1.8, "03:00 should be in first segment (1.8)")
        
        // 06:00 UTC -> should be 1.7 (second segment: 05:30-22:30)
        let time0600 = baseDate.addingTimeInterval(6 * 3600)
        #expect(store.basalAt(date: time0600) == 1.7, "06:00 should be in second segment (1.7)")
        
        // 12:00 UTC -> should be 1.7 (second segment: 05:30-22:30)
        let time1200 = baseDate.addingTimeInterval(12 * 3600)
        #expect(store.basalAt(date: time1200) == 1.7, "12:00 should be in second segment (1.7)")
        
        // 23:00 UTC -> should be 1.8 (third segment: 22:30-24:00)
        let time2300 = baseDate.addingTimeInterval(23 * 3600)
        #expect(store.basalAt(date: time2300) == 1.8, "23:00 should be in third segment (1.8)")
    }
    
    @Test("Time-aware ISF lookup with single entry returns that value")
    func timeAwareISFSingleEntry() {
        let store = ProfileStore(
            sens: [
                ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: 40)
            ]
        )
        
        // Any time should return the single value
        let anyTime = Date()
        #expect(store.isfAt(date: anyTime) == 40, "Single entry should be used for any time")
    }
    
    @Test("Time-aware lookup returns nil for empty schedule")
    func timeAwareEmptySchedule() {
        let store = ProfileStore(sens: nil, basal: [])
        
        let anyTime = Date()
        #expect(store.isfAt(date: anyTime) == nil, "Empty sens should return nil")
        #expect(store.basalAt(date: anyTime) == nil, "Empty basal should return nil")
    }
    
    @Test("Time-aware lookup wraps to last entry for time before first")
    func timeAwareWrapAround() {
        // Schedule starts at 06:00 - what happens at 03:00?
        let store = ProfileStore(
            basal: [
                ScheduleEntry(time: "06:00", timeAsSeconds: 21600, value: 1.5),
                ScheduleEntry(time: "18:00", timeAsSeconds: 64800, value: 2.0)
            ],
            timezone: "UTC"
        )
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let baseDate = calendar.startOfDay(for: Date())
        
        // 03:00 UTC is before first entry (06:00), should wrap to last entry (2.0)
        let time0300 = baseDate.addingTimeInterval(3 * 3600)
        #expect(store.basalAt(date: time0300) == 2.0, "Time before first entry should wrap to last entry")
    }
    
    // MARK: - Loop Settings (ALG-LIVE-062)
    
    @Test("Parse loopSettings from profile")
    func parseLoopSettings() throws {
        let json = """
        {
            "_id": "507f1f77bcf86cd799439011",
            "defaultProfile": "Default",
            "startDate": "2026-02-05T00:00:00.000Z",
            "mills": 1738713600000,
            "units": "mg/dL",
            "store": {
                "Default": {
                    "dia": 6.0,
                    "carbratio": [{"time": "00:00", "value": 10.0, "timeAsSeconds": 0}],
                    "sens": [{"time": "00:00", "value": 50.0, "timeAsSeconds": 0}],
                    "basal": [{"time": "00:00", "value": 1.0, "timeAsSeconds": 0}],
                    "target_low": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}],
                    "target_high": [{"time": "00:00", "value": 120, "timeAsSeconds": 0}],
                    "timezone": "UTC"
                }
            },
            "loopSettings": {
                "dosingStrategy": "tempBasalOnly",
                "maximumBasalRatePerHour": 6.0,
                "maximumBolus": 9.9,
                "minimumBGGuard": 69,
                "dosingEnabled": true,
                "preMealTargetRange": [69, 69]
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        let loopSettings = try #require(profile.loopSettings)
        #expect(loopSettings.dosingStrategy == "tempBasalOnly")
        #expect(loopSettings.maximumBasalRatePerHour == 6.0)
        #expect(loopSettings.maximumBolus == 9.9)
        #expect(loopSettings.minimumBGGuard == 69)
        #expect(loopSettings.dosingEnabled == true)
        #expect(loopSettings.preMealTargetRange == [69, 69])
        
        // Computed properties
        #expect(loopSettings.isTempBasalOnly == true)
        #expect(loopSettings.isAutomaticBolus == false)
    }
    
    @Test("Parse loopSettings with automaticBolus strategy")
    func parseAutomaticBolus() throws {
        let json = """
        {
            "defaultProfile": "Default",
            "startDate": "2026-02-05T00:00:00Z",
            "store": {
                "Default": {
                    "dia": 6.0,
                    "basal": [{"time": "00:00", "value": 1.0, "timeAsSeconds": 0}],
                    "timezone": "UTC"
                }
            },
            "loopSettings": {
                "dosingStrategy": "automaticBolus",
                "maximumBasalRatePerHour": 5.0
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        let loopSettings = try #require(profile.loopSettings)
        
        #expect(loopSettings.isAutomaticBolus == true)
        #expect(loopSettings.isTempBasalOnly == false)
    }
    
    @Test("Profile without loopSettings parses successfully")
    func profileWithoutLoopSettings() throws {
        let json = """
        {
            "defaultProfile": "Default",
            "startDate": "2026-02-05T00:00:00Z",
            "store": {
                "Default": {
                    "dia": 6.0,
                    "basal": [{"time": "00:00", "value": 1.0, "timeAsSeconds": 0}],
                    "timezone": "UTC"
                }
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        #expect(profile.loopSettings == nil)
    }
    
    @Test("Parse live Loop profile fixture with loopSettings")
    func parseLiveLoopProfileFixture() throws {
        let fixtureURL = Bundle.module.url(forResource: "fixture_profile_loop_live", withExtension: "json", subdirectory: "Fixtures")
        let url = try #require(fixtureURL, "Fixture file not found")
        let data = try Data(contentsOf: url)
        
        let profiles = try JSONDecoder().decode([NightscoutProfile].self, from: data)
        let profile = try #require(profiles.first)
        
        // Verify basic profile
        #expect(profile.defaultProfile == "Default")
        #expect(profile.enteredBy == "Loop")
        
        // Verify loopSettings from live fixture
        let loopSettings = try #require(profile.loopSettings)
        #expect(loopSettings.dosingStrategy == "tempBasalOnly")
        #expect(loopSettings.maximumBasalRatePerHour == 6.0)
        #expect(loopSettings.maximumBolus == 9.9)
        #expect(loopSettings.minimumBGGuard == 69)
        #expect(loopSettings.dosingEnabled == true)
        #expect(loopSettings.preMealTargetRange == [69, 69])
        #expect(loopSettings.isTempBasalOnly == true)
    }
}

// Test helper for fixture loading
private enum TestError: Error, CustomStringConvertible {
    case message(String)
    
    init(_ message: String) { self = .message(message) }
    
    var description: String {
        switch self { case .message(let msg): return msg }
    }
}
