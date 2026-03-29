// SPDX-License-Identifier: MIT
//
// CapabilityDetectorTests.swift
// T1PalCore Tests
//
// Tests for capability detection and tier progression
// Backlog: ENHANCE-TIER1-001

import Foundation
import Testing
@testable import T1PalCore

// MARK: - App Tier Tests

@Suite("App Tier")
struct AppTierTests {
    
    @Test("Tier ordering")
    func testTierOrdering() {
        #expect(AppTier.demo < AppTier.identity)
        #expect(AppTier.identity < AppTier.cgm)
        #expect(AppTier.cgm < AppTier.aid)
    }
    
    @Test("All tiers exist")
    func testAllCases() {
        let tiers = AppTier.allCases
        #expect(tiers.count == 4)
        #expect(tiers.contains(.demo))
        #expect(tiers.contains(.identity))
        #expect(tiers.contains(.cgm))
        #expect(tiers.contains(.aid))
    }
    
    @Test("Display names")
    func testDisplayNames() {
        #expect(AppTier.demo.displayName == "Demo Mode")
        #expect(AppTier.identity.displayName == "Connected")
        #expect(AppTier.cgm.displayName == "CGM Active")
        #expect(AppTier.aid.displayName == "AID Mode")
    }
    
    @Test("Symbol names")
    func testSymbolNames() {
        #expect(!AppTier.demo.symbolName.isEmpty)
        #expect(!AppTier.identity.symbolName.isEmpty)
        #expect(!AppTier.cgm.symbolName.isEmpty)
        #expect(!AppTier.aid.symbolName.isEmpty)
    }
    
    @Test("Demo tier has no prerequisites")
    func testDemoPrerequisites() {
        #expect(AppTier.demo.prerequisites.isEmpty)
    }
    
    @Test("Identity tier prerequisites")
    func testIdentityPrerequisites() {
        let prereqs = AppTier.identity.prerequisites
        #expect(prereqs.contains(.authentication))
        #expect(prereqs.contains(.nightscoutConnection))
    }
    
    @Test("CGM tier prerequisites")
    func testCGMPrerequisites() {
        let prereqs = AppTier.cgm.prerequisites
        #expect(prereqs.contains(.bluetoothAccess))
        #expect(prereqs.contains(.cgmDevice))
    }
    
    @Test("AID tier prerequisites")
    func testAIDPrerequisites() {
        let prereqs = AppTier.aid.prerequisites
        #expect(prereqs.contains(.pumpDevice))
        #expect(prereqs.contains(.aidTrainingComplete))
    }
    
    @Test("Tier is Codable")
    func testCodable() throws {
        let tier = AppTier.cgm
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(tier)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppTier.self, from: data)
        
        #expect(decoded == tier)
    }
}

// MARK: - Capability Tests

@Suite("Capability")
struct CapabilityTests {
    
    @Test("All capabilities exist")
    func testAllCases() {
        let capabilities = Capability.allCases
        #expect(capabilities.count >= 13)
    }
    
    @Test("Display names are not empty")
    func testDisplayNames() {
        for capability in Capability.allCases {
            #expect(!capability.displayName.isEmpty)
        }
    }
    
    @Test("Descriptions are not empty")
    func testDescriptions() {
        for capability in Capability.allCases {
            #expect(!capability.capabilityDescription.isEmpty)
        }
    }
    
    @Test("Required tier mapping")
    func testRequiredTiers() {
        #expect(Capability.authentication.requiredForTier == .identity)
        #expect(Capability.nightscoutConnection.requiredForTier == .identity)
        #expect(Capability.cgmDevice.requiredForTier == .cgm)
        #expect(Capability.pumpDevice.requiredForTier == .aid)
    }
    
    @Test("Capability is Codable")
    func testCodable() throws {
        let capability = Capability.authentication
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(capability)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Capability.self, from: data)
        
        #expect(decoded == capability)
    }
}

// MARK: - Capability Status Tests

@Suite("Capability Status")
struct CapabilityStatusTests {
    
    @Test("Create available status")
    func testAvailable() {
        let status = CapabilityStatus.available(.authentication)
        
        #expect(status.isAvailable == true)
        #expect(status.capability == .authentication)
        #expect(status.reason == nil)
    }
    
    @Test("Create unavailable status")
    func testUnavailable() {
        let status = CapabilityStatus.unavailable(
            .bluetoothAccess,
            reason: "Permission denied",
            canRequest: true
        )
        
        #expect(status.isAvailable == false)
        #expect(status.capability == .bluetoothAccess)
        #expect(status.reason == "Permission denied")
        #expect(status.canRequest == true)
    }
    
    @Test("Status equality")
    func testEquality() {
        let status1 = CapabilityStatus.available(.authentication)
        let status2 = CapabilityStatus.available(.authentication)
        let status3 = CapabilityStatus.unavailable(.authentication, reason: "Test")
        
        #expect(status1 == status2)
        #expect(status1 != status3)
    }
}

// MARK: - Mock Capability Detector Tests

@Suite("Mock Capability Detector")
struct MockCapabilityDetectorTests {
    
    @Test("Starts with demo tier")
    func testStartsWithDemo() async {
        let detector = MockCapabilityDetector()
        
        let tier = await detector.detectCurrentTier()
        #expect(tier == .demo)
    }
    
    @Test("Enable identity tier")
    func testEnableIdentityTier() async {
        let detector = MockCapabilityDetector()
        
        await detector.enableTier(.identity)
        
        let tier = await detector.detectCurrentTier()
        #expect(tier == .identity)
    }
    
    @Test("Enable CGM tier includes identity prerequisites")
    func testEnableCGMTier() async {
        let detector = MockCapabilityDetector()
        
        // Enable identity first
        await detector.enableTier(.identity)
        // Then CGM
        await detector.enableTier(.cgm)
        
        let tier = await detector.detectCurrentTier()
        #expect(tier == .cgm)
    }
    
    @Test("Check specific capability")
    func testCheckCapability() async {
        let detector = MockCapabilityDetector()
        
        // Initially unavailable
        var status = await detector.checkCapability(.authentication)
        #expect(status.isAvailable == false)
        
        // Enable it
        await detector.setCapability(.authentication, available: true)
        
        status = await detector.checkCapability(.authentication)
        #expect(status.isAvailable == true)
    }
    
    @Test("Check prerequisites for tier")
    func testCheckPrerequisites() async {
        let detector = MockCapabilityDetector()
        
        let statuses = await detector.checkPrerequisites(for: .identity)
        
        #expect(statuses.count == AppTier.identity.prerequisites.count)
        #expect(statuses.allSatisfy { !$0.isAvailable })
    }
    
    @Test("Missing capabilities for tier")
    func testMissingCapabilities() async {
        let detector = MockCapabilityDetector()
        
        // Enable only authentication
        await detector.setCapability(.authentication, available: true)
        
        let missing = await detector.missingCapabilities(for: .identity)
        
        #expect(!missing.contains(.authentication))
        #expect(missing.contains(.nightscoutConnection))
    }
    
    @Test("Can achieve tier")
    func testCanAchieveTier() async {
        let detector = MockCapabilityDetector()
        
        // All capabilities can be requested by default
        let canAchieve = await detector.canAchieveTier(.identity)
        #expect(canAchieve == true)
    }
    
    @Test("Check count is tracked")
    func testCheckCount() async {
        let detector = MockCapabilityDetector()
        
        _ = await detector.checkCapability(.authentication)
        _ = await detector.checkCapability(.bluetoothAccess)
        _ = await detector.checkCapability(.cgmDevice)
        
        let count = await detector.checkCount
        #expect(count == 3)
    }
}

// MARK: - Live Capability Detector Tests

@Suite("Live Capability Detector")
struct LiveCapabilityDetectorTests {
    
    @Test("Starts with demo tier when nothing configured")
    func testStartsWithDemo() async {
        let detector = LiveCapabilityDetector(
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        
        let tier = await detector.detectCurrentTier()
        #expect(tier == .demo)
    }
    
    @Test("Cache can be cleared")
    func testClearCache() async {
        let detector = LiveCapabilityDetector()
        await detector.clearCache()
        // No error means success
    }
    
    @Test("Check prerequisites returns correct count")
    func testCheckPrerequisitesCount() async {
        let detector = LiveCapabilityDetector()
        
        let statuses = await detector.checkPrerequisites(for: .identity)
        #expect(statuses.count == AppTier.identity.prerequisites.count)
    }
}

// MARK: - Tier Progress Tests

@Suite("Tier Progress")
struct TierProgressTests {
    
    @Test("Create progress")
    func testCreateProgress() {
        let progress = TierProgress(
            targetTier: .identity,
            completedCapabilities: [.authentication],
            missingCapabilities: [.nightscoutConnection]
        )
        
        #expect(progress.targetTier == .identity)
        #expect(progress.completedCapabilities.count == 1)
        #expect(progress.missingCapabilities.count == 1)
        #expect(progress.progress == 0.5)
    }
    
    @Test("Complete progress")
    func testCompleteProgress() {
        let progress = TierProgress(
            targetTier: .identity,
            completedCapabilities: [.authentication, .nightscoutConnection],
            missingCapabilities: []
        )
        
        #expect(progress.isComplete == true)
        #expect(progress.progress == 1.0)
        #expect(progress.nextStep == nil)
    }
    
    @Test("Next step is first missing capability")
    func testNextStep() {
        let progress = TierProgress(
            targetTier: .identity,
            completedCapabilities: [],
            missingCapabilities: [.authentication, .nightscoutConnection]
        )
        
        #expect(progress.nextStep == .authentication)
    }
    
    @Test("Empty progress is complete")
    func testEmptyProgress() {
        let progress = TierProgress(
            targetTier: .demo,
            completedCapabilities: [],
            missingCapabilities: []
        )
        
        #expect(progress.isComplete == true)
        #expect(progress.progress == 1.0)
    }
}

// MARK: - Tier Progress Calculator Tests

@Suite("Tier Progress Calculator")
struct TierProgressCalculatorTests {
    
    @Test("Calculate progress for tier")
    func testProgressForTier() async {
        let detector = MockCapabilityDetector()
        await detector.setCapability(.authentication, available: true)
        
        let calculator = TierProgressCalculator(detector: detector)
        let progress = await calculator.progress(for: .identity)
        
        #expect(progress.targetTier == .identity)
        #expect(progress.completedCapabilities.contains(.authentication))
        #expect(progress.missingCapabilities.contains(.nightscoutConnection))
    }
    
    @Test("Calculate all tier progress")
    func testAllTierProgress() async {
        let detector = MockCapabilityDetector()
        let calculator = TierProgressCalculator(detector: detector)
        
        let allProgress = await calculator.allTierProgress()
        
        #expect(allProgress.count == AppTier.allCases.count)
        #expect(allProgress[.demo] != nil)
        #expect(allProgress[.identity] != nil)
    }
    
    @Test("Next achievable tier")
    func testNextAchievableTier() async {
        let detector = MockCapabilityDetector()
        let calculator = TierProgressCalculator(detector: detector)
        
        // From demo, identity should be achievable
        let next = await calculator.nextAchievableTier()
        #expect(next == .identity)
    }
    
    @Test("Next achievable tier after identity")
    func testNextAchievableTierAfterIdentity() async {
        let detector = MockCapabilityDetector()
        await detector.enableTier(.identity)
        
        let calculator = TierProgressCalculator(detector: detector)
        let next = await calculator.nextAchievableTier()
        
        #expect(next == .cgm)
    }
}
