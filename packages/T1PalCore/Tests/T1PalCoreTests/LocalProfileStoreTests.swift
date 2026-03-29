// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LocalProfileStoreTests.swift
// T1Pal - Open Source AID
//
// Tests for LocalProfileStore implementation.
//
// Trace: CRIT-PROFILE-003

import Testing
import Foundation
@testable import T1PalCore

// MARK: - LocalProfileStore Tests

@Suite("LocalProfileStore Tests")
struct LocalProfileStoreTests {
    
    // MARK: - Basic Operations
    
    @Test("Load returns default profile when no data stored")
    func testLoadReturnsDefault() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.load.default")
        
        let profile = try await store.load()
        
        #expect(profile.maxIOB == TherapyProfile.default.maxIOB)
        #expect(profile.maxBolus == TherapyProfile.default.maxBolus)
    }
    
    @Test("Save and load round-trips profile")
    func testSaveAndLoad() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.load")
        
        var profile = TherapyProfile.default
        profile.maxIOB = 15.0
        profile.maxBolus = 8.0
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.maxIOB == 15.0)
        #expect(loaded.maxBolus == 8.0)
    }
    
    @Test("Save persists basal rates")
    func testSaveBasalRates() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.basal")
        
        var profile = TherapyProfile.default
        profile.basalRates = [
            BasalRate(startTime: 0, rate: 0.8),
            BasalRate(startTime: 21600, rate: 1.2),  // 6 AM
            BasalRate(startTime: 43200, rate: 1.0)   // 12 PM
        ]
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.basalRates.count == 3)
        #expect(loaded.basalRates[0].rate == 0.8)
        #expect(loaded.basalRates[1].rate == 1.2)
        #expect(loaded.basalRates[2].rate == 1.0)
    }
    
    @Test("Save persists carb ratios")
    func testSaveCarbRatios() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.carb")
        
        var profile = TherapyProfile.default
        profile.carbRatios = [
            CarbRatio(startTime: 0, ratio: 12),
            CarbRatio(startTime: 43200, ratio: 8)
        ]
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.carbRatios.count == 2)
        #expect(loaded.carbRatios[0].ratio == 12)
        #expect(loaded.carbRatios[1].ratio == 8)
    }
    
    @Test("Save persists sensitivity factors")
    func testSaveSensitivityFactors() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.isf")
        
        var profile = TherapyProfile.default
        profile.sensitivityFactors = [
            SensitivityFactor(startTime: 0, factor: 40),
            SensitivityFactor(startTime: 28800, factor: 50)  // 8 AM
        ]
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.sensitivityFactors.count == 2)
        #expect(loaded.sensitivityFactors[0].factor == 40)
        #expect(loaded.sensitivityFactors[1].factor == 50)
    }
    
    @Test("Save persists target glucose")
    func testSaveTargetGlucose() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.target")
        
        var profile = TherapyProfile.default
        profile.targetGlucose = TargetRange(low: 90, high: 120)
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.targetGlucose.low == 90)
        #expect(loaded.targetGlucose.high == 120)
    }
    
    // MARK: - Update Operations
    
    @Test("Update modifies profile and sets hasChanges")
    func testUpdate() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.update")
        
        try await store.update { profile in
            profile.maxIOB = 20.0
        }
        
        let hasChanges = await store.hasUnsavedChanges
        #expect(hasChanges, "Should have unsaved changes after update")
        
        let profile = await store.currentProfile
        #expect(profile.maxIOB == 20.0)
    }
    
    @Test("Update changes are not persisted until save")
    func testUpdateNotPersisted() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.update.persist")
        
        // Save initial profile
        var initial = TherapyProfile.default
        initial.maxIOB = 5.0
        try await store.save(initial)
        
        // Update without saving
        try await store.update { profile in
            profile.maxIOB = 25.0
        }
        
        // Reload from storage
        let reloaded = try await store.load()
        
        // Should have original value
        #expect(reloaded.maxIOB == 5.0)
    }
    
    // MARK: - Reset Operations
    
    @Test("Reset restores default profile")
    func testReset() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.reset")
        
        // Save custom profile
        var custom = TherapyProfile.default
        custom.maxIOB = 99.0
        try await store.save(custom)
        
        // Reset
        try await store.reset()
        
        let profile = await store.currentProfile
        #expect(profile.maxIOB == TherapyProfile.default.maxIOB)
    }
    
    @Test("Reset clears hasUnsavedChanges")
    func testResetClearsChanges() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.reset.changes")
        
        try await store.update { profile in
            profile.maxBolus = 50.0
        }
        
        let beforeReset = await store.hasUnsavedChanges
        #expect(beforeReset)
        
        try await store.reset()
        
        let afterReset = await store.hasUnsavedChanges
        #expect(!afterReset)
    }
    
    // MARK: - Discard Changes
    
    @Test("Discard changes reloads from storage")
    func testDiscardChanges() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.discard")
        
        // Save initial
        var initial = TherapyProfile.default
        initial.maxIOB = 10.0
        try await store.save(initial)
        
        // Make changes
        try await store.update { profile in
            profile.maxIOB = 50.0
        }
        
        // Discard
        try await store.discardChanges()
        
        let profile = await store.currentProfile
        #expect(profile.maxIOB == 10.0)
        
        let hasChanges = await store.hasUnsavedChanges
        #expect(!hasChanges)
    }
    
    // MARK: - Validation
    
    @Test("Save validates profile before saving")
    func testSaveValidates() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.validate")
        
        var invalid = TherapyProfile.default
        invalid.basalRates = []  // Invalid: empty basal rates
        
        do {
            try await store.save(invalid)
            #expect(Bool(false), "Should have thrown validation error")
        } catch let error as ProfileStoreError {
            if case .validationFailed = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Additional Properties
    
    @Test("LastSavedDate is nil before first save")
    func testLastSavedDateNil() async {
        let store = LocalProfileStore.testInstance(suiteName: "test.lastSaved.nil")
        
        let date = await store.lastSavedDate
        #expect(date == nil)
    }
    
    @Test("LastSavedDate is set after save")
    func testLastSavedDateSet() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.lastSaved.set")
        
        let before = Date()
        try await store.save(TherapyProfile.default)
        let after = Date()
        
        let savedDate = await store.lastSavedDate
        #expect(savedDate != nil)
        #expect(savedDate! >= before)
        #expect(savedDate! <= after)
    }
    
    @Test("HasStoredProfile is false initially")
    func testHasStoredProfileFalse() async {
        let store = LocalProfileStore.testInstance(suiteName: "test.hasStored.false")
        
        let hasStored = await store.hasStoredProfile
        #expect(!hasStored)
    }
    
    @Test("HasStoredProfile is true after save")
    func testHasStoredProfileTrue() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.hasStored.true")
        
        try await store.save(TherapyProfile.default)
        
        let hasStored = await store.hasStoredProfile
        #expect(hasStored)
    }
    
    // MARK: - NS-IOB-001b: Insulin Model Persistence
    
    @Test("Save persists insulin model")
    func testSaveInsulinModel() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.save.insulinModel")
        
        var profile = TherapyProfile.default
        profile.insulinModel = "fiasp"
        
        try await store.save(profile)
        let loaded = try await store.load()
        
        #expect(loaded.insulinModel == "fiasp")
    }
    
    @Test("Insulin model defaults to nil")
    func testInsulinModelDefault() async throws {
        let store = LocalProfileStore.testInstance(suiteName: "test.insulinModel.default")
        
        let profile = try await store.load()
        
        #expect(profile.insulinModel == nil)
    }
    
    @Test("Save persists all insulin model presets")
    func testAllInsulinModelPresets() async throws {
        let presets = ["rapidActingAdult", "rapidActingChild", "fiasp", "lyumjev", "afrezza"]
        
        for preset in presets {
            let store = LocalProfileStore.testInstance(suiteName: "test.insulinModel.\(preset)")
            
            var profile = TherapyProfile.default
            profile.insulinModel = preset
            
            try await store.save(profile)
            let loaded = try await store.load()
            
            #expect(loaded.insulinModel == preset, "Failed for preset: \(preset)")
        }
    }
}

// MARK: - LocalProfileStore Keys Tests

@Suite("LocalProfileStoreKeys Tests")
struct LocalProfileStoreKeysTests {
    
    @Test("Keys have expected values")
    func testKeyValues() {
        #expect(LocalProfileStoreKeys.profile == "t1pal.profile.data")
        #expect(LocalProfileStoreKeys.hasChanges == "t1pal.profile.hasChanges")
        #expect(LocalProfileStoreKeys.lastSaved == "t1pal.profile.lastSaved")
    }
}
