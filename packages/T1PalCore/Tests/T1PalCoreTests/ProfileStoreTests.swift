// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ProfileStoreTests.swift
// T1Pal - Open Source AID
//
// Tests for ProfileStore protocol and related types.
//
// Trace: CRIT-PROFILE-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Profile Validation Tests

@Suite("ProfileValidator Tests")
struct ProfileValidatorTests {
    
    let validator = ProfileValidator()
    
    @Test("Valid profile passes validation")
    func testValidProfile() {
        let profile = TherapyProfile.default
        let result = validator.validate(profile)
        
        #expect(result.isValid, "Default profile should be valid")
        #expect(result.errors.isEmpty, "Valid profile should have no errors")
    }
    
    @Test("Empty basal rates fails validation")
    func testEmptyBasalRates() {
        var profile = TherapyProfile.default
        profile.basalRates = []
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("basal rate") })
    }
    
    @Test("Empty carb ratios fails validation")
    func testEmptyCarbRatios() {
        var profile = TherapyProfile.default
        profile.carbRatios = []
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("carb ratio") })
    }
    
    @Test("Empty ISF fails validation")
    func testEmptyISF() {
        var profile = TherapyProfile.default
        profile.sensitivityFactors = []
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("ISF") })
    }
    
    @Test("Zero basal rate fails validation")
    func testZeroBasalRate() {
        var profile = TherapyProfile.default
        profile.basalRates = [BasalRate(startTime: 0, rate: 0)]
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Basal rate must be greater than 0") })
    }
    
    @Test("Excessive basal rate fails validation")
    func testExcessiveBasalRate() {
        var profile = TherapyProfile.default
        profile.basalRates = [BasalRate(startTime: 0, rate: 40)]  // > 35
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("exceeds maximum") })
    }
    
    @Test("Target low >= high fails validation")
    func testInvalidTargetRange() {
        var profile = TherapyProfile.default
        profile.targetGlucose = TargetRange(low: 120, high: 100)
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Target low must be less than target high") })
    }
    
    @Test("Target low below 70 fails validation")
    func testTargetTooLow() {
        var profile = TherapyProfile.default
        profile.targetGlucose = TargetRange(low: 60, high: 100)
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("below minimum") })
    }
    
    @Test("Target high above 180 fails validation")
    func testTargetTooHigh() {
        var profile = TherapyProfile.default
        profile.targetGlucose = TargetRange(low: 100, high: 200)
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("exceeds maximum") })
    }
    
    @Test("Negative maxIOB fails validation")
    func testNegativeMaxIOB() {
        var profile = TherapyProfile.default
        profile.maxIOB = -1
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Max IOB cannot be negative") })
    }
    
    @Test("Negative maxBolus fails validation")
    func testNegativeMaxBolus() {
        var profile = TherapyProfile.default
        profile.maxBolus = -1
        
        let result = validator.validate(profile)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Max bolus cannot be negative") })
    }
}

// MARK: - Profile Store Error Tests

@Suite("ProfileStoreError Tests")
struct ProfileStoreErrorTests {
    
    @Test("All errors have descriptions")
    func testErrorDescriptions() {
        let errors: [ProfileStoreError] = [
            .loadFailed(underlying: nil),
            .saveFailed(underlying: nil),
            .validationFailed(reason: "test"),
            .networkError(underlying: nil),
            .conflictDetected(local: TherapyProfile.default, remote: TherapyProfile.default),
            .unavailable(reason: "test")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil, "Error \(error) should have description")
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Validation error includes reason")
    func testValidationErrorReason() {
        let error = ProfileStoreError.validationFailed(reason: "test reason")
        #expect(error.errorDescription?.contains("test reason") == true)
    }
}

// MARK: - Profile Store Event Tests

@Suite("ProfileStoreEvent Tests")
struct ProfileStoreEventTests {
    
    @Test("Events are Sendable")
    func testEventsSendable() {
        let events: [ProfileStoreEvent] = [
            .loaded(TherapyProfile.default),
            .saved(TherapyProfile.default),
            .reset,
            .error(.loadFailed(underlying: nil)),
            .syncStarted,
            .syncCompleted
        ]
        
        // Verify all events can be created
        #expect(events.count == 6)
    }
}

// MARK: - Profile Validation Result Tests

@Suite("ProfileValidationResult Tests")
struct ProfileValidationResultTests {
    
    @Test("Valid result has no errors")
    func testValidResult() {
        let result = ProfileValidationResult(isValid: true, errors: [])
        
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Invalid result has errors")
    func testInvalidResult() {
        let result = ProfileValidationResult(isValid: false, errors: ["Error 1", "Error 2"])
        
        #expect(!result.isValid)
        #expect(result.errors.count == 2)
    }
}

// MARK: - Profile Store Type Tests

@Suite("ProfileStoreType Tests")
struct ProfileStoreTypeTests {
    
    @Test("All store types are defined")
    func testStoreTypes() {
        let types = ProfileStoreType.allCases
        
        #expect(types.count == 3)
        #expect(types.contains(.local))
        #expect(types.contains(.nightscout))
        #expect(types.contains(.pump))
    }
    
    @Test("Store types have raw values")
    func testStoreTypeRawValues() {
        #expect(ProfileStoreType.local.rawValue == "local")
        #expect(ProfileStoreType.nightscout.rawValue == "nightscout")
        #expect(ProfileStoreType.pump.rawValue == "pump")
    }
}

// MARK: - Mock Profile Store for Testing

/// Mock implementation of ProfileStore for testing
actor MockProfileStore: ProfileStore {
    var storedProfile: TherapyProfile = TherapyProfile.default
    var savedProfile: TherapyProfile?
    var shouldFail: Bool = false
    var _hasUnsavedChanges: Bool = false
    
    nonisolated var currentProfile: TherapyProfile {
        get async {
            await storedProfile
        }
    }
    
    func load() async throws -> TherapyProfile {
        if shouldFail {
            throw ProfileStoreError.loadFailed(underlying: nil)
        }
        return storedProfile
    }
    
    func save(_ profile: TherapyProfile) async throws {
        if shouldFail {
            throw ProfileStoreError.saveFailed(underlying: nil)
        }
        storedProfile = profile
        savedProfile = profile
        _hasUnsavedChanges = false
    }
    
    func update(_ update: @Sendable (inout TherapyProfile) -> Void) async throws {
        if shouldFail {
            throw ProfileStoreError.saveFailed(underlying: nil)
        }
        update(&storedProfile)
        _hasUnsavedChanges = true
    }
    
    func reset() async throws {
        if shouldFail {
            throw ProfileStoreError.saveFailed(underlying: nil)
        }
        storedProfile = TherapyProfile.default
        _hasUnsavedChanges = false
    }
    
    nonisolated var hasUnsavedChanges: Bool {
        get async {
            await _hasUnsavedChanges
        }
    }
    
    func discardChanges() async throws {
        _hasUnsavedChanges = false
    }
}

// MARK: - Mock Profile Store Tests

@Suite("MockProfileStore Tests")
struct MockProfileStoreTests {
    
    @Test("Load returns stored profile")
    func testLoad() async throws {
        let store = MockProfileStore()
        let profile = try await store.load()
        
        #expect(profile.maxIOB == TherapyProfile.default.maxIOB)
    }
    
    @Test("Save stores profile")
    func testSave() async throws {
        let store = MockProfileStore()
        var profile = TherapyProfile.default
        profile.maxIOB = 15.0
        
        try await store.save(profile)
        
        let loaded = try await store.load()
        #expect(loaded.maxIOB == 15.0)
    }
    
    @Test("Update modifies profile")
    func testUpdate() async throws {
        let store = MockProfileStore()
        
        try await store.update { profile in
            profile.maxBolus = 20.0
        }
        
        let profile = try await store.load()
        #expect(profile.maxBolus == 20.0)
        
        let hasChanges = await store.hasUnsavedChanges
        #expect(hasChanges)
    }
    
    @Test("Reset restores defaults")
    func testReset() async throws {
        let store = MockProfileStore()
        
        try await store.update { profile in
            profile.maxIOB = 99.0
        }
        
        try await store.reset()
        
        let profile = try await store.load()
        #expect(profile.maxIOB == TherapyProfile.default.maxIOB)
    }
    
    @Test("Failure mode throws errors")
    func testFailureMode() async {
        let store = MockProfileStore()
        await store.setShouldFail(true)
        
        do {
            _ = try await store.load()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is ProfileStoreError)
        }
    }
}

extension MockProfileStore {
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
}

// MARK: - Profile Conflict Detection Tests (CRIT-PROFILE-025)

@Suite("ProfileConflict Tests")
struct ProfileConflictTests {
    
    @Test("Identical profiles show no differences")
    func testIdenticalProfiles() {
        let profile1 = TherapyProfile.default
        let profile2 = TherapyProfile.default
        
        let conflict = ProfileConflict(local: profile1, remote: profile2)
        
        #expect(!conflict.hasDifferences, "Identical profiles should have no differences")
        #expect(conflict.differences.summary.isEmpty)
    }
    
    @Test("Different basal rates detected")
    func testBasalRateDifference() {
        let local = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 5.0
        )
        
        let remote = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.5)],  // Different
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 5.0
        )
        
        let conflict = ProfileConflict(local: local, remote: remote)
        
        #expect(conflict.hasDifferences)
        #expect(conflict.differences.basalRatesDiffer)
        #expect(!conflict.differences.carbRatiosDiffer)
        #expect(conflict.differences.summary.contains("Basal rates"))
    }
    
    @Test("Different safety limits detected")
    func testSafetyLimitsDifference() {
        let local = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 5.0
        )
        
        let remote = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 15.0,  // Different
            maxBolus: 5.0
        )
        
        let conflict = ProfileConflict(local: local, remote: remote)
        
        #expect(conflict.hasDifferences)
        #expect(conflict.differences.safetyLimitsDiffer)
        #expect(!conflict.differences.basalRatesDiffer)
        #expect(conflict.differences.summary.contains("Safety limits"))
    }
    
    @Test("Multiple differences detected")
    func testMultipleDifferences() {
        let local = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 5.0
        )
        
        let remote = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.5)],  // Different
            carbRatios: [CarbRatio(startTime: 0, ratio: 12)],  // Different
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 45)],  // Different
            targetGlucose: TargetRange(low: 90, high: 110),  // Different
            maxIOB: 15.0,  // Different
            maxBolus: 6.0
        )
        
        let conflict = ProfileConflict(local: local, remote: remote)
        
        #expect(conflict.hasDifferences)
        #expect(conflict.differences.basalRatesDiffer)
        #expect(conflict.differences.carbRatiosDiffer)
        #expect(conflict.differences.sensitivityFactorsDiffer)
        #expect(conflict.differences.targetGlucoseDiffers)
        #expect(conflict.differences.safetyLimitsDiffer)
        #expect(conflict.differences.summary.count == 5)
    }
    
    @Test("Resolution enum has correct display names")
    func testResolutionDisplayNames() {
        #expect(ProfileConflictResolution.keepLocal.displayName == "Keep Local")
        #expect(ProfileConflictResolution.useRemote.displayName == "Use Nightscout")
        #expect(ProfileConflictResolution.cancelSync.displayName == "Cancel")
    }
}
