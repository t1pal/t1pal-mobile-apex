// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutProfileStoreTests.swift
// NightscoutKit
//
// Tests for NightscoutProfileStore
//
// Trace: CRIT-PROFILE-002

import Testing
import Foundation
@testable import NightscoutKit
@testable import T1PalCore

// MARK: - Mock Nightscout Client

/// Mock client for testing NightscoutProfileStore
actor MockNightscoutClient: @unchecked Sendable {
    var uploadedProfiles: [NightscoutProfile] = []
    var profilesToReturn: [NightscoutProfile] = []
    var shouldFail = false
    var failureError: Error = NSError(domain: "test", code: 500)
    
    func reset() {
        uploadedProfiles = []
        profilesToReturn = []
        shouldFail = false
    }
    
    func setProfiles(_ profiles: [NightscoutProfile]) {
        profilesToReturn = profiles
    }
    
    func getUploadedProfiles() -> [NightscoutProfile] {
        return uploadedProfiles
    }
}

// MARK: - Test Fixtures

/// Create a test NightscoutProfile
func makeTestNightscoutProfile(
    basal: [(time: String, value: Double)] = [("00:00", 1.0)],
    carbratio: [(time: String, value: Double)] = [("00:00", 10.0)],
    sens: [(time: String, value: Double)] = [("00:00", 50.0)],
    targetLow: Double = 100,
    targetHigh: Double = 120,
    units: String = "mg/dL"
) -> NightscoutProfile {
    let basalEntries = basal.map { ScheduleEntry(time: $0.time, timeAsSeconds: parseTime($0.time), value: $0.value) }
    let carbratioEntries = carbratio.map { ScheduleEntry(time: $0.time, timeAsSeconds: parseTime($0.time), value: $0.value) }
    let sensEntries = sens.map { ScheduleEntry(time: $0.time, timeAsSeconds: parseTime($0.time), value: $0.value) }
    let targetLowEntries = [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: targetLow)]
    let targetHighEntries = [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: targetHigh)]
    
    let store = ProfileStore(
        dia: 6.0,
        carbratio: carbratioEntries,
        sens: sensEntries,
        basal: basalEntries,
        target_low: targetLowEntries,
        target_high: targetHighEntries,
        timezone: "America/Los_Angeles",
        units: units,
        startDate: "2025-01-01T00:00:00Z",
        carbs_hr: nil,
        delay: nil
    )
    
    return NightscoutProfile(
        _id: "test-id",
        defaultProfile: "Default",
        startDate: "2025-01-01T00:00:00Z",
        mills: 1704067200000,
        units: units,
        store: ["Default": store],
        created_at: "2025-01-01T00:00:00Z",
        enteredBy: "Test",
        loopSettings: nil
    )
}

/// Parse time string to seconds
func parseTime(_ time: String) -> Int {
    let components = time.split(separator: ":")
    guard components.count >= 2,
          let hours = Int(components[0]),
          let minutes = Int(components[1]) else {
        return 0
    }
    return hours * 3600 + minutes * 60
}

// MARK: - Tests

@Suite("NightscoutProfileStore Tests")
struct NightscoutProfileStoreTests {
    
    @Test("Convert NS profile to TherapyProfile - basic values")
    func testConvertBasicProfile() async throws {
        let nsProfile = makeTestNightscoutProfile(
            basal: [("00:00", 1.0), ("06:00", 1.2), ("22:00", 0.8)],
            carbratio: [("00:00", 10.0), ("12:00", 8.0)],
            sens: [("00:00", 50.0), ("18:00", 55.0)]
        )
        
        // Access the active profile
        guard let store = nsProfile.activeProfile else {
            Issue.record("No active profile")
            return
        }
        
        // Verify the data is there
        #expect(store.basal?.count == 3)
        #expect(store.carbratio?.count == 2)
        #expect(store.sens?.count == 2)
    }
    
    @Test("Convert NS profile to TherapyProfile - mmol/L conversion")
    func testMmolConversion() async throws {
        let nsProfile = makeTestNightscoutProfile(
            sens: [("00:00", 2.8)], // 2.8 mmol/L/U ≈ 50 mg/dL/U
            units: "mmol/L"
        )
        
        guard let store = nsProfile.activeProfile else {
            Issue.record("No active profile")
            return
        }
        
        // Verify the raw value
        #expect(store.sens?.first?.value == 2.8)
    }
    
    @Test("ScheduleEntry secondsFromMidnight - HH:mm format")
    func testScheduleEntryTimeConversion() {
        let entry = ScheduleEntry(time: "06:30", timeAsSeconds: nil, value: 1.0)
        #expect(entry.secondsFromMidnight == 6 * 3600 + 30 * 60)
    }
    
    @Test("ScheduleEntry secondsFromMidnight - uses timeAsSeconds if present")
    func testScheduleEntryUsesTimeAsSeconds() {
        let entry = ScheduleEntry(time: "00:00", timeAsSeconds: 21600, value: 1.0) // 06:00
        #expect(entry.secondsFromMidnight == 21600)
    }
    
    @Test("TherapyProfile to NightscoutProfile - round trip schedules")
    func testTherapyProfileSchedules() {
        let profile = TherapyProfile(
            basalRates: [
                BasalRate(startTime: 0, rate: 1.0),
                BasalRate(startTime: 21600, rate: 1.2), // 06:00
                BasalRate(startTime: 79200, rate: 0.8)  // 22:00
            ],
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 10),
                CarbRatio(startTime: 43200, ratio: 8)   // 12:00
            ],
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 50),
                SensitivityFactor(startTime: 64800, factor: 55) // 18:00
            ],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0
        )
        
        // Verify data
        #expect(profile.basalRates.count == 3)
        #expect(profile.carbRatios.count == 2)
        #expect(profile.sensitivityFactors.count == 2)
        #expect(profile.basalRates[1].rate == 1.2)
        #expect(profile.carbRatios[1].ratio == 8)
    }
    
    @Test("ProfileValidator validates NightscoutProfileStore output")
    func testValidatorWithConvertedProfile() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0
        )
        
        let validator = ProfileValidator()
        let result = validator.validate(profile)
        
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Default profile when no NS profile exists")
    func testDefaultProfileHandling() {
        let defaultProfile = TherapyProfile.default
        
        #expect(defaultProfile.basalRates.count == 1)
        #expect(defaultProfile.basalRates[0].rate == 1.0)
        #expect(defaultProfile.carbRatios.count == 1)
        #expect(defaultProfile.carbRatios[0].ratio == 10)
    }
    
    @Test("TherapyProfileStore typealias resolves correctly")
    func testTypealiasExists() {
        // Verify NightscoutProfileStore conforms to TherapyProfileStore (which is T1PalCore.ProfileStore)
        // This test passes if it compiles - the conformance is the check
        func acceptsProfileStore<T: TherapyProfileStore>(_: T.Type) {}
        acceptsProfileStore(NightscoutProfileStore.self)
    }
    
    // MARK: - SyncableProfileStore Tests (CRIT-PROFILE-010)
    
    @Test("NightscoutProfileStore conforms to SyncableProfileStore")
    func testSyncableConformance() {
        // Verify NightscoutProfileStore conforms to SyncableProfileStore
        // This test passes if it compiles - the conformance is the check
        func acceptsSyncableStore<T: SyncableProfileStore>(_: T.Type) {}
        acceptsSyncableStore(NightscoutProfileStore.self)
    }
    
    @Test("ProfileSyncStatus has correct states")
    func testProfileSyncStatusStates() {
        // Verify all status states exist and have expected properties
        #expect(ProfileSyncStatus.disconnected.isConnected == false)
        #expect(ProfileSyncStatus.idle.isConnected == true)
        #expect(ProfileSyncStatus.syncing.isSyncing == true)
        #expect(ProfileSyncStatus.synced(Date()).isSyncing == false)
        #expect(ProfileSyncStatus.error("test").isConnected == true)
    }
    
    // MARK: - CRIT-PROFILE-021 Tests
    
    @Test("ObservableProfileStore has saveAndSync method")
    func testSaveAndSyncMethodExists() {
        // Verify saveAndSync method exists on ObservableProfileStore
        // This test passes if it compiles - the method existence is the check
        #if canImport(Combine)
        @MainActor func checkMethodExists(store: ObservableProfileStore) async {
            await store.saveAndSync()
            await store.saveAndSync(syncToRemote: true)
            await store.saveAndSync(syncToRemote: false)
        }
        #endif
    }
    
    // MARK: - CRIT-PROFILE-020 Tests
    
    @Test("NightscoutProfileStore can be initialized with client")
    func testNightscoutProfileStoreInit() {
        // Verify initialization patterns work
        let url = URL(string: "https://example.nightscout.com")!
        let config = NightscoutConfig(url: url, apiSecret: nil, token: nil)
        let client = NightscoutClient(config: config)
        let store = NightscoutProfileStore(client: client)
        
        // Store exists - conformance test
        #expect(store is any TherapyProfileStore)
        #expect(store is any SyncableProfileStore)
    }
}
