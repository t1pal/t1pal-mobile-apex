// SPDX-License-Identifier: MIT
//
// TierUpgradeFlowTests.swift
// T1PalCore Tests
//
// Tests for tier upgrade orchestration and data migration
// Backlog: ENHANCE-FLOW-001

import Foundation
import Testing
@testable import T1PalCore

// MARK: - Tier Transition Tests

@Suite("Tier Transition")
struct TierTransitionTests {
    
    @Test("Upgrade from demo to identity")
    func testDemoToIdentity() {
        let transition = TierTransition(from: .demo, to: .identity)
        
        #expect(transition.isUpgrade == true)
        #expect(transition.fromTier == .demo)
        #expect(transition.toTier == .identity)
        #expect(transition.requiredSteps.contains(.validateAuthentication))
        #expect(transition.requiredSteps.contains(.syncNightscoutProfile))
    }
    
    @Test("Upgrade from identity to CGM")
    func testIdentityToCGM() {
        let transition = TierTransition(from: .identity, to: .cgm)
        
        #expect(transition.isUpgrade == true)
        #expect(transition.requiredSteps.contains(.requestBluetoothPermission))
        #expect(transition.requiredSteps.contains(.configureCGMDevice))
    }
    
    @Test("Upgrade from CGM to AID")
    func testCGMToAID() {
        let transition = TierTransition(from: .cgm, to: .aid)
        
        #expect(transition.isUpgrade == true)
        #expect(transition.requiredSteps.contains(.configurePumpDevice))
        #expect(transition.requiredSteps.contains(.validateAIDTraining))
        #expect(transition.requiredSteps.contains(.enableAIDMode))
    }
    
    @Test("Downgrade from AID to CGM")
    func testAIDToCGM() {
        let transition = TierTransition(from: .aid, to: .cgm)
        
        #expect(transition.isUpgrade == false)
        #expect(transition.requiredSteps.contains(.disableAIDMode))
        #expect(transition.requiredSteps.contains(.disconnectPump))
    }
    
    @Test("Multi-tier upgrade includes all intermediate steps")
    func testMultiTierUpgrade() {
        let transition = TierTransition(from: .demo, to: .cgm)
        
        #expect(transition.isUpgrade == true)
        // Should include identity steps
        #expect(transition.requiredSteps.contains(.validateAuthentication))
        // And CGM steps
        #expect(transition.requiredSteps.contains(.configureCGMDevice))
    }
    
    @Test("AID upgrade requires confirmation")
    func testAIDRequiresConfirmation() {
        let transition = TierTransition(from: .cgm, to: .aid)
        
        #expect(transition.requiresConfirmation == true)
    }
    
    @Test("Downgrade requires confirmation")
    func testDowngradeRequiresConfirmation() {
        let transition = TierTransition(from: .cgm, to: .identity)
        
        #expect(transition.requiresConfirmation == true)
    }
    
    @Test("Identity upgrade does not require confirmation")
    func testIdentityNoConfirmation() {
        let transition = TierTransition(from: .demo, to: .identity)
        
        #expect(transition.requiresConfirmation == false)
    }
    
    @Test("Display description")
    func testDisplayDescription() {
        let upgrade = TierTransition(from: .demo, to: .identity)
        let downgrade = TierTransition(from: .cgm, to: .identity)
        
        #expect(upgrade.displayDescription.contains("Upgrade"))
        #expect(downgrade.displayDescription.contains("Downgrade"))
    }
}

// MARK: - Migration Step Tests

@Suite("Migration Step")
struct MigrationStepTests {
    
    @Test("All steps have display names")
    func testDisplayNames() {
        for step in TierMigrationStep.allCases {
            #expect(!step.displayName.isEmpty)
        }
    }
    
    @Test("All steps have estimated duration")
    func testEstimatedDuration() {
        for step in TierMigrationStep.allCases {
            #expect(step.estimatedDuration > 0)
        }
    }
    
    @Test("Interactive steps are marked")
    func testInteractiveSteps() {
        #expect(TierMigrationStep.requestBluetoothPermission.requiresInteraction == true)
        #expect(TierMigrationStep.configureCGMDevice.requiresInteraction == true)
        #expect(TierMigrationStep.validateAuthentication.requiresInteraction == false)
    }
}

// MARK: - Transition State Tests

@Suite("Transition State")
struct TransitionStateTests {
    
    @Test("Initial state")
    func testInitialState() {
        let transition = TierTransition(from: .demo, to: .identity)
        let state = TierTransitionState(transition: transition)
        
        #expect(state.currentStepIndex == 0)
        #expect(state.completedSteps.isEmpty)
        #expect(state.progress == 0.0)
        #expect(state.isInProgress == true)
        #expect(state.isComplete == false)
        #expect(state.hasFailed == false)
    }
    
    @Test("Current step")
    func testCurrentStep() {
        let transition = TierTransition(from: .demo, to: .identity)
        let state = TierTransitionState(transition: transition)
        
        #expect(state.currentStep == transition.requiredSteps.first)
    }
    
    @Test("Progress calculation")
    func testProgressCalculation() {
        let transition = TierTransition(from: .demo, to: .identity)
        let steps = transition.requiredSteps
        
        var state = TierTransitionState(transition: transition)
        #expect(state.progress == 0.0)
        
        // Complete first step
        if let step = steps.first {
            state = state.withStepCompleted(step)
            #expect(state.progress > 0.0)
            #expect(state.progress <= 1.0)
        }
    }
    
    @Test("Complete state")
    func testCompleteState() {
        let transition = TierTransition(from: .demo, to: .identity)
        var state = TierTransitionState(transition: transition)
        
        // Complete all steps
        for step in transition.requiredSteps {
            state = state.withStepCompleted(step)
        }
        
        #expect(state.isComplete == true)
        #expect(state.isInProgress == false)
        #expect(state.progress == 1.0)
        #expect(state.completedAt != nil)
    }
    
    @Test("Failed state")
    func testFailedState() {
        let transition = TierTransition(from: .demo, to: .identity)
        let state = TierTransitionState(transition: transition)
        
        let failedState = state.withStepFailed(
            .validateAuthentication,
            error: .prerequisiteNotMet(.authentication)
        )
        
        #expect(failedState.hasFailed == true)
        #expect(failedState.isInProgress == false)
        #expect(failedState.failedStep == .validateAuthentication)
        #expect(failedState.error != nil)
    }
    
    @Test("Remaining steps")
    func testRemainingSteps() {
        let transition = TierTransition(from: .demo, to: .identity)
        var state = TierTransitionState(transition: transition)
        
        let initialRemaining = state.remainingSteps.count
        
        if let step = transition.requiredSteps.first {
            state = state.withStepCompleted(step)
            #expect(state.remainingSteps.count == initialRemaining - 1)
        }
    }
    
    @Test("Estimated remaining time")
    func testEstimatedRemainingTime() {
        let transition = TierTransition(from: .demo, to: .identity)
        let state = TierTransitionState(transition: transition)
        
        #expect(state.estimatedRemainingTime > 0)
    }
}

// MARK: - Upgrade Error Tests

@Suite("Upgrade Error")
struct UpgradeErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [TierUpgradeError] = [
            .prerequisiteNotMet(.authentication),
            .stepFailed(.validateAuthentication, "Test"),
            .permissionDenied("Bluetooth"),
            .deviceNotFound("CGM"),
            .validationFailed("Test"),
            .userCancelled,
            .timeout(.configureCGMDevice),
            .alreadyAtTier(.identity),
            .invalidTransition(from: .demo, to: .demo)
        ]
        
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
    
    @Test("Error equality")
    func testErrorEquality() {
        let error1 = TierUpgradeError.userCancelled
        let error2 = TierUpgradeError.userCancelled
        let error3 = TierUpgradeError.alreadyAtTier(.demo)
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - Mock Coordinator Tests

@Suite("Mock Tier Upgrade Coordinator")
struct MockTierUpgradeCoordinatorTests {
    
    @Test("Can upgrade")
    func testCanUpgrade() async {
        let coordinator = MockTierUpgradeCoordinator()
        
        let canUpgrade = await coordinator.canUpgrade(to: .identity)
        #expect(canUpgrade == true)
    }
    
    @Test("Cannot upgrade when disabled")
    func testCannotUpgrade() async {
        let coordinator = MockTierUpgradeCoordinator()
        await coordinator.setCanUpgrade(false)
        
        let canUpgrade = await coordinator.canUpgrade(to: .identity)
        #expect(canUpgrade == false)
    }
    
    @Test("Start upgrade")
    func testStartUpgrade() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        
        let state = try await coordinator.startUpgrade(to: .identity)
        
        #expect(state.transition.toTier == .identity)
        #expect(state.isInProgress == true)
        
        let count = await coordinator.upgradeCount
        #expect(count == 1)
    }
    
    @Test("Already at tier throws error")
    func testAlreadyAtTier() async {
        let coordinator = MockTierUpgradeCoordinator()
        await coordinator.setCurrentTier(.identity)
        
        do {
            _ = try await coordinator.startUpgrade(to: .identity)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TierUpgradeError {
            #expect(error == .alreadyAtTier(.identity))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("Execute next step")
    func testExecuteNextStep() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        _ = try await coordinator.startUpgrade(to: .identity)
        
        let state = try await coordinator.executeNextStep()
        
        #expect(state.completedSteps.count == 1)
    }
    
    @Test("Execute all steps completes upgrade")
    func testCompleteUpgrade() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        var state = try await coordinator.startUpgrade(to: .identity)
        
        while state.isInProgress {
            state = try await coordinator.executeNextStep()
        }
        
        #expect(state.isComplete == true)
        
        let tier = await coordinator.currentTier
        #expect(tier == .identity)
    }
    
    @Test("Step failure")
    func testStepFailure() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        await coordinator.setShouldFail(true)
        
        _ = try await coordinator.startUpgrade(to: .identity)
        
        do {
            _ = try await coordinator.executeNextStep()
            #expect(Bool(false), "Should have thrown")
        } catch {
            let state = await coordinator.getCurrentState()
            #expect(state?.hasFailed == true)
        }
    }
    
    @Test("Retry failed step")
    func testRetryFailedStep() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        await coordinator.setShouldFail(true)
        
        _ = try await coordinator.startUpgrade(to: .identity)
        
        // First attempt fails
        do {
            _ = try await coordinator.executeNextStep()
        } catch {
            // Expected
        }
        
        // Retry succeeds (shouldFail is reset)
        let state = try await coordinator.retryFailedStep()
        #expect(state.hasFailed == false)
        #expect(state.completedSteps.count == 1)
    }
    
    @Test("Cancel transition")
    func testCancelTransition() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        _ = try await coordinator.startUpgrade(to: .identity)
        
        await coordinator.cancelTransition()
        
        let state = await coordinator.getCurrentState()
        #expect(state == nil)
    }
}

// MARK: - Live Coordinator Tests

@Suite("Live Tier Upgrade Coordinator")
struct LiveTierUpgradeCoordinatorTests {
    
    @Test("Can upgrade check")
    func testCanUpgrade() async {
        let detector = MockCapabilityDetector()
        let coordinator = LiveTierUpgradeCoordinator(capabilityDetector: detector)
        
        let canUpgrade = await coordinator.canUpgrade(to: .identity)
        #expect(canUpgrade == true) // All capabilities requestable by default
    }
    
    @Test("Start upgrade creates state")
    func testStartUpgrade() async throws {
        let detector = MockCapabilityDetector()
        let coordinator = LiveTierUpgradeCoordinator(capabilityDetector: detector)
        
        let state = try await coordinator.startUpgrade(to: .identity)
        
        #expect(state.transition.toTier == .identity)
        #expect(state.isInProgress == true)
    }
    
    @Test("Get current state")
    func testGetCurrentState() async throws {
        let detector = MockCapabilityDetector()
        let coordinator = LiveTierUpgradeCoordinator(capabilityDetector: detector)
        
        let initialState = await coordinator.getCurrentState()
        #expect(initialState == nil)
        
        _ = try await coordinator.startUpgrade(to: .identity)
        
        let activeState = await coordinator.getCurrentState()
        #expect(activeState != nil)
    }
}

// MARK: - Tier Upgrade Flow Helper Tests

@Suite("Tier Upgrade Flow Helper")
struct TierUpgradeFlowHelperTests {
    
    @Test("Complete upgrade executes all steps")
    func testCompleteUpgrade() async throws {
        let coordinator = MockTierUpgradeCoordinator()
        let flow = TierUpgradeFlow(coordinator: coordinator)
        
        let state = try await flow.completeUpgrade(to: .identity)
        
        #expect(state.isComplete == true)
    }
    
    @Test("Is upgrade possible")
    func testIsUpgradePossible() async {
        let coordinator = MockTierUpgradeCoordinator()
        let flow = TierUpgradeFlow(coordinator: coordinator)
        
        let possible = await flow.isUpgradePossible(to: .identity)
        #expect(possible == true)
        
        await coordinator.setCurrentTier(.aid)
        let notPossible = await flow.isUpgradePossible(to: .identity)
        #expect(notPossible == false)
    }
}
