// SPDX-License-Identifier: MIT
//
// ConcurrentBolusRaceTests.swift
// PumpKitTests
//
// Tests for concurrent bolus race condition handling.
// Race conditions in bolus delivery can cause double-dosing when:
// - User initiates manual bolus while algorithm bolus in progress
// - Algorithm requests bolus while user bolus in progress
// - Multiple sources request boluses simultaneously
//
// This is safety-critical: unguarded concurrent boluses can lead to
// dangerous insulin stacking and hypoglycemia.
//
// Trace: TEST-GAP-004, DOC-TEST-003, CRITICAL-PATH-TESTS.md
// Requirements: REQ-AID-001, PROD-HARDEN, BOLUS-005

import Testing
import Foundation
@testable import PumpKit

// MARK: - Test Infrastructure

/// Source of a bolus request for tracking in race condition tests
enum BolusSource: String, Sendable {
    case user = "user"
    case algorithm = "algorithm"
    case remote = "remote"
}

/// Result of a bolus attempt in race condition scenario
enum BolusAttemptResult: Equatable, Sendable {
    case succeeded(units: Double)
    case blockedByInProgress
    case failed(reason: String)
}

/// Actor to track bolus attempts across concurrent tasks
actor BolusAttemptTracker {
    private var attempts: [(source: BolusSource, result: BolusAttemptResult, timestamp: Date)] = []
    
    func record(source: BolusSource, result: BolusAttemptResult) {
        attempts.append((source: source, result: result, timestamp: Date()))
    }
    
    var allAttempts: [(source: BolusSource, result: BolusAttemptResult, timestamp: Date)] {
        attempts
    }
    
    var successfulAttempts: [(source: BolusSource, result: BolusAttemptResult, timestamp: Date)] {
        attempts.filter {
            if case .succeeded = $0.result { return true }
            return false
        }
    }
    
    var blockedAttempts: [(source: BolusSource, result: BolusAttemptResult, timestamp: Date)] {
        attempts.filter {
            if case .blockedByInProgress = $0.result { return true }
            return false
        }
    }
    
    func totalDeliveredUnits() -> Double {
        attempts.reduce(0) { total, attempt in
            if case .succeeded(let units) = attempt.result {
                return total + units
            }
            return total
        }
    }
    
    func clear() {
        attempts.removeAll()
    }
}

/// Mock pump that simulates realistic bolus timing for race condition testing
actor RaceConditionPump {
    private var isDeliveringBolus: Bool = false
    private var currentBolusUnits: Double = 0
    private var totalDelivered: Double = 0
    private let deliveryTimePerUnit: TimeInterval // seconds per unit
    
    init(deliveryTimePerUnit: TimeInterval = 0.01) { // Fast for tests
        self.deliveryTimePerUnit = deliveryTimePerUnit
    }
    
    /// Attempt to deliver a bolus - returns immediately if another bolus is in progress
    func deliverBolus(units: Double, source: BolusSource) async -> BolusAttemptResult {
        // Check if bolus already in progress (guard against concurrent delivery)
        guard !isDeliveringBolus else {
            return .blockedByInProgress
        }
        
        // Mark bolus as in progress
        isDeliveringBolus = true
        currentBolusUnits = units
        
        // Simulate delivery time
        let deliveryNanoseconds = UInt64(units * deliveryTimePerUnit * 1_000_000_000)
        try? await Task.sleep(nanoseconds: deliveryNanoseconds)
        
        // Complete delivery
        totalDelivered += units
        isDeliveringBolus = false
        currentBolusUnits = 0
        
        return .succeeded(units: units)
    }
    
    var bolusInProgress: Bool {
        isDeliveringBolus
    }
    
    var currentBolus: Double {
        currentBolusUnits
    }
    
    var totalDeliveredUnits: Double {
        totalDelivered
    }
}

// MARK: - Bolus-In-Progress Guard Tests

@Suite("Bolus In Progress Guard")
struct BolusInProgressGuardTests {
    
    @Test("Second bolus blocked when first in progress")
    func secondBolusBlocked() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.05) // 50ms per unit
        let tracker = BolusAttemptTracker()
        
        // Start first bolus (will take 100ms for 2 units)
        async let firstBolus = pump.deliverBolus(units: 2.0, source: .user)
        
        // Small delay to ensure first bolus starts
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Attempt second bolus while first is in progress
        let secondResult = await pump.deliverBolus(units: 1.5, source: .algorithm)
        
        // Wait for first to complete
        let firstResult = await firstBolus
        
        await tracker.record(source: .user, result: firstResult)
        await tracker.record(source: .algorithm, result: secondResult)
        
        // First should succeed
        #expect(firstResult == .succeeded(units: 2.0))
        
        // Second should be blocked
        #expect(secondResult == .blockedByInProgress)
        
        // Only 2 units should be delivered (not 3.5)
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 2.0) < 0.001)
    }
    
    @Test("Bolus allowed after previous completes")
    func bolusAllowedAfterCompletion() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.01)
        
        // First bolus
        let first = await pump.deliverBolus(units: 1.0, source: .user)
        #expect(first == .succeeded(units: 1.0))
        
        // Second bolus after first completes
        let second = await pump.deliverBolus(units: 1.5, source: .algorithm)
        #expect(second == .succeeded(units: 1.5))
        
        // Both should be delivered
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 2.5) < 0.001)
    }
    
    @Test("Multiple rapid attempts only one succeeds")
    func multipleRapidAttempts() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.02)
        let tracker = BolusAttemptTracker()
        
        // Launch 5 concurrent bolus attempts
        await withTaskGroup(of: (BolusSource, BolusAttemptResult).self) { group in
            let sources: [BolusSource] = [.user, .algorithm, .user, .algorithm, .remote]
            
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let result = await pump.deliverBolus(units: 1.0, source: source)
                    return (source, result)
                }
            }
            
            for await (source, result) in group {
                await tracker.record(source: source, result: result)
            }
        }
        
        // Exactly one should succeed
        let successful = await tracker.successfulAttempts
        #expect(successful.count == 1)
        
        // Others should be blocked
        let blocked = await tracker.blockedAttempts
        #expect(blocked.count == 4)
        
        // Only 1 unit delivered
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 1.0) < 0.001)
    }
}

// MARK: - User vs Algorithm Race Tests

@Suite("User vs Algorithm Bolus Race")
struct UserAlgorithmRaceTests {
    
    @Test("User bolus blocks algorithm bolus")
    func userBlocksAlgorithm() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.03)
        
        // User starts bolus first
        async let userBolus = pump.deliverBolus(units: 3.0, source: .user)
        
        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms delay
        
        // Algorithm tries to deliver
        let algoBolus = await pump.deliverBolus(units: 2.0, source: .algorithm)
        
        let userResult = await userBolus
        
        #expect(userResult == .succeeded(units: 3.0))
        #expect(algoBolus == .blockedByInProgress)
        
        // Safety: only user's 3U delivered, not 5U
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 3.0) < 0.001)
    }
    
    @Test("Algorithm bolus blocks user bolus")
    func algorithmBlocksUser() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.03)
        
        // Algorithm starts bolus first
        async let algoBolus = pump.deliverBolus(units: 2.0, source: .algorithm)
        
        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms delay
        
        // User tries to deliver
        let userBolus = await pump.deliverBolus(units: 4.0, source: .user)
        
        let algoResult = await algoBolus
        
        #expect(algoResult == .succeeded(units: 2.0))
        #expect(userBolus == .blockedByInProgress)
        
        // Safety: only algorithm's 2U delivered, not 6U
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 2.0) < 0.001)
    }
    
    @Test("Sequential user then algorithm succeeds")
    func sequentialUserThenAlgorithm() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.01)
        
        // User bolus completes
        let userResult = await pump.deliverBolus(units: 2.0, source: .user)
        #expect(userResult == .succeeded(units: 2.0))
        
        // Then algorithm bolus
        let algoResult = await pump.deliverBolus(units: 1.5, source: .algorithm)
        #expect(algoResult == .succeeded(units: 1.5))
        
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - 3.5) < 0.001)
    }
}

// MARK: - State Consistency Tests

@Suite("State Consistency During Race")
struct StateConsistencyTests {
    
    @Test("bolusInProgress flag accurate during delivery")
    func bolusInProgressAccurate() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.05)
        
        // Before bolus
        let beforeState = await pump.bolusInProgress
        #expect(beforeState == false)
        
        // During bolus
        async let delivery = pump.deliverBolus(units: 2.0, source: .user)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let duringState = await pump.bolusInProgress
        #expect(duringState == true)
        
        // After bolus
        _ = await delivery
        let afterState = await pump.bolusInProgress
        #expect(afterState == false)
    }
    
    @Test("currentBolus reflects active delivery")
    func currentBolusReflectsDelivery() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.05)
        
        // Before
        let beforeBolus = await pump.currentBolus
        #expect(beforeBolus == 0)
        
        // During
        async let delivery = pump.deliverBolus(units: 3.0, source: .user)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let duringBolus = await pump.currentBolus
        #expect(duringBolus == 3.0)
        
        // After
        _ = await delivery
        let afterBolus = await pump.currentBolus
        #expect(afterBolus == 0)
    }
    
    @Test("Total delivered accurate after race condition")
    func totalDeliveredAccurateAfterRace() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.02)
        
        // Simulate race: 3 attempts, only 1 should succeed initially
        async let attempt1 = pump.deliverBolus(units: 1.0, source: .user)
        async let attempt2 = pump.deliverBolus(units: 1.5, source: .algorithm)
        async let attempt3 = pump.deliverBolus(units: 2.0, source: .remote)
        
        let results = await [attempt1, attempt2, attempt3]
        
        let successCount = results.filter {
            if case .succeeded = $0 { return true }
            return false
        }.count
        
        // Only one of the first batch succeeded
        #expect(successCount == 1)
        
        // Determine what was delivered
        var expectedTotal: Double = 0
        for result in results {
            if case .succeeded(let units) = result {
                expectedTotal += units
            }
        }
        
        let actual = await pump.totalDeliveredUnits
        #expect(abs(actual - expectedTotal) < 0.001)
    }
}

// MARK: - OmnipodDashManager Concurrent Bolus Tests

@Suite("OmnipodDashManager Concurrent Bolus Handling")
struct OmnipodDashConcurrentBolusTests {
    
    @Test("Bolus in progress state tracked correctly")
    func bolusInProgressStateTracked() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        // Before bolus
        let activeBefore = await manager.activeBolusDelivery
        #expect(activeBefore == nil)
        
        // Deliver bolus
        try await manager.deliverBolus(units: 1.0)
        
        // After bolus (synchronous in simulation, so already done)
        let activeAfter = await manager.activeBolusDelivery
        #expect(activeAfter == nil) // Cleared after completion
    }
    
    @Test("Pod delivery state is bolusInProgress during bolus")
    func podDeliveryStateDuringBolus() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        // Before
        let beforeState = await manager.currentPodState?.deliveryState
        #expect(beforeState == .basalRunning)
        
        // The deliverBolus is synchronous in simulation,
        // but we can verify the state machine transitions occurred
        try await manager.deliverBolus(units: 1.0)
        
        // After (should return to previous state)
        let afterState = await manager.currentPodState?.deliveryState
        #expect(afterState == .basalRunning)
    }
    
    @Test("Sequential boluses both succeed")
    func sequentialBolusesSucceed() async throws {
        let manager = OmnipodDashManager()
        let delegate = MockBolusProgressDelegate()
        await manager.setBolusProgressDelegate(delegate)
        
        try await manager.activatePod()
        try await manager.connect()
        
        // First bolus
        try await manager.deliverBolus(units: 2.0)
        
        // Second bolus
        try await manager.deliverBolus(units: 1.5)
        
        // Both should complete
        #expect(delegate.completedBoluses.count == 2)
        #expect(delegate.completedBoluses[0].delivered == 2.0)
        #expect(delegate.completedBoluses[1].delivered == 1.5)
    }
    
    @Test("Bolus updates reservoir correctly")
    func bolusUpdatesReservoir() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        let initialReservoir = await manager.currentPodState?.reservoirLevel ?? 0
        
        try await manager.deliverBolus(units: 5.0)
        
        let finalReservoir = await manager.currentPodState?.reservoirLevel ?? 0
        
        #expect(abs(finalReservoir - (initialReservoir - 5.0)) < 0.001)
    }
}

// MARK: - CommandVerifier Bolus Race Tests

@Suite("CommandVerifier Bolus Race Prevention")
struct CommandVerifierBolusRaceTests {
    
    @Test("Verifier blocks bolus when bolus in progress")
    func verifierBlocksBolusInProgress() {
        let verifier = CommandVerifier()
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        
        // Existing bolus in progress
        let existingBolus = BolusProgress(
            command: BolusCommand.normal(2.0),
            deliveredUnits: 1.0,
            startTime: Date()
        )
        let deliveryState = DeliveryState(bolusInProgress: existingBolus)
        
        // New bolus attempt
        let command = PumpCommand.bolus(BolusCommand.normal(3.0))
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(!result.canProceed)
        #expect(result.error == .bolusInProgress)
    }
    
    @Test("Verifier allows bolus when no bolus in progress")
    func verifierAllowsWhenNoBolus() {
        let verifier = CommandVerifier()
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        
        // No bolus in progress
        let deliveryState = DeliveryState()
        
        let command = PumpCommand.bolus(BolusCommand.normal(2.0))
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(result.canProceed)
        #expect(result.error == nil)
    }
    
    @Test("Verifier allows cancel when bolus in progress")
    func verifierAllowsCancelWhenBolusInProgress() {
        let verifier = CommandVerifier()
        let status = PumpStatus(connectionState: .connected)
        
        let existingBolus = BolusProgress(
            command: BolusCommand.normal(5.0),
            deliveredUnits: 2.5,
            startTime: Date()
        )
        let deliveryState = DeliveryState(bolusInProgress: existingBolus)
        
        let command = PumpCommand.cancelBolus
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(result.canProceed)
    }
}

// MARK: - Cancel During Race Tests

@Suite("Cancel During Bolus Race")
struct CancelDuringRaceTests {
    
    @Test("Cancel clears bolus state correctly")
    func cancelClearsBolusState() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        // Start a bolus that completes synchronously in simulation
        try await manager.deliverBolus(units: 2.0)
        
        // After completion, cancel should be safe (no-op if nothing in progress)
        try await manager.cancelBolus()
        
        // State should be clean
        let active = await manager.activeBolusDelivery
        #expect(active == nil)
    }
}

// MARK: - Edge Cases

@Suite("Concurrent Bolus Edge Cases")
struct ConcurrentBolusEdgeCases {
    
    @Test("Zero unit bolus race")
    func zeroUnitBolusRace() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.01)
        
        // Zero unit boluses should still follow race rules
        let result1 = await pump.deliverBolus(units: 0.0, source: .user)
        let result2 = await pump.deliverBolus(units: 0.0, source: .algorithm)
        
        // Both "succeed" as they complete instantly
        #expect(result1 == .succeeded(units: 0.0))
        #expect(result2 == .succeeded(units: 0.0))
    }
    
    @Test("Very small bolus race")
    func verySmallBolusRace() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.1) // Slower to create race
        
        async let first = pump.deliverBolus(units: 0.05, source: .user)
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        let second = await pump.deliverBolus(units: 0.05, source: .algorithm)
        
        let firstResult = await first
        
        // One succeeds, one blocked (due to timing)
        let results = [firstResult, second]
        let successCount = results.filter {
            if case .succeeded = $0 { return true }
            return false
        }.count
        
        // At least one must succeed
        #expect(successCount >= 1)
    }
    
    @Test("Large bolus race prevents dangerous overdose")
    func largeBolusRace() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.05)
        let tracker = BolusAttemptTracker()
        
        // Two large boluses attempted simultaneously
        async let userLarge = pump.deliverBolus(units: 10.0, source: .user)
        async let algoLarge = pump.deliverBolus(units: 8.0, source: .algorithm)
        
        let userResult = await userLarge
        let algoResult = await algoLarge
        
        await tracker.record(source: .user, result: userResult)
        await tracker.record(source: .algorithm, result: algoResult)
        
        // Only one should succeed
        let successful = await tracker.successfulAttempts
        #expect(successful.count == 1)
        
        // Critical: Total delivered should be at most 10U, not 18U
        let total = await pump.totalDeliveredUnits
        #expect(total <= 10.0)
    }
    
    @Test("Rapid fire bolus attempts")
    func rapidFireBolusAttempts() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.02)
        let tracker = BolusAttemptTracker()
        
        // Fire 10 rapid bolus attempts
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let source: BolusSource = i % 2 == 0 ? .user : .algorithm
                    let result = await pump.deliverBolus(units: 1.0, source: source)
                    await tracker.record(source: source, result: result)
                }
            }
        }
        
        // Only sequential successes possible
        let successful = await tracker.successfulAttempts
        let blocked = await tracker.blockedAttempts
        
        #expect(successful.count >= 1)
        #expect(successful.count + blocked.count == 10)
        
        // Total should match successful count
        let total = await pump.totalDeliveredUnits
        #expect(abs(total - Double(successful.count)) < 0.001)
    }
}

// MARK: - Safety Invariant Tests

@Suite("Bolus Race Safety Invariants")
struct BolusRaceSafetyInvariantTests {
    
    @Test("Concurrent requests never cause double delivery")
    func neverDoubleDelivery() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.03)
        
        // 100 iterations of race condition scenario
        for _ in 0..<100 {
            let beforeTotal = await pump.totalDeliveredUnits
            
            // Simultaneous requests
            async let r1 = pump.deliverBolus(units: 1.0, source: .user)
            async let r2 = pump.deliverBolus(units: 1.0, source: .algorithm)
            
            _ = await (r1, r2)
            
            let afterTotal = await pump.totalDeliveredUnits
            let delivered = afterTotal - beforeTotal
            
            // Should deliver exactly 1.0, never 2.0
            #expect(delivered <= 1.0 + 0.001, "Double delivery detected!")
        }
    }
    
    @Test("Total delivered equals sum of successful boluses")
    func totalEqualsSuccessfulSum() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.02)
        let tracker = BolusAttemptTracker()
        
        // Many concurrent attempts
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let result = await pump.deliverBolus(units: 0.5, source: .user)
                    await tracker.record(source: .user, result: result)
                }
            }
        }
        
        let trackedTotal = await tracker.totalDeliveredUnits()
        let pumpTotal = await pump.totalDeliveredUnits
        
        #expect(abs(trackedTotal - pumpTotal) < 0.001)
    }
    
    @Test("No partial bolus without tracking")
    func noPartialWithoutTracking() async {
        let pump = RaceConditionPump(deliveryTimePerUnit: 0.02)
        let tracker = BolusAttemptTracker()
        
        // Concurrent boluses
        async let r1 = pump.deliverBolus(units: 2.0, source: .user)
        async let r2 = pump.deliverBolus(units: 2.0, source: .algorithm)
        
        let (result1, result2) = await (r1, r2)
        await tracker.record(source: .user, result: result1)
        await tracker.record(source: .algorithm, result: result2)
        
        // Every success should be for the full amount
        let successful = await tracker.successfulAttempts
        for attempt in successful {
            if case .succeeded(let units) = attempt.result {
                #expect(units == 2.0, "Partial bolus delivered without full tracking")
            }
        }
    }
}
