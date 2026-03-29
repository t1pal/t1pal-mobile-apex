// SPDX-License-Identifier: MIT
// OnboardingTests.swift
// T1PalCoreTests
//
// Tests for Onboarding framework
// Trace: APP-ONBOARD-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Validation Result Tests

@Suite("OnboardingValidationResult")
struct OnboardingValidationResultTests {
    
    @Test("Valid result is valid")
    func validResultIsValid() {
        let result = OnboardingValidationResult.valid
        #expect(result.isValid)
        #expect(result.canProceed)
        #expect(result.errorMessage == nil)
    }
    
    @Test("Invalid result blocks proceeding")
    func invalidResultBlocksProceeding() {
        let result = OnboardingValidationResult.invalid("Test error")
        #expect(!result.isValid)
        #expect(!result.canProceed)
        #expect(result.errorMessage == "Test error")
    }
    
    @Test("Warning allows proceeding")
    func warningAllowsProceeding() {
        let result = OnboardingValidationResult.warning("Test warning")
        #expect(!result.isValid)
        #expect(result.canProceed)
        #expect(result.errorMessage == "Test warning")
    }
}

// MARK: - Simple Onboarding Step Tests

@Suite("SimpleOnboardingStep")
struct SimpleOnboardingStepTests {
    
    @Test("Step has correct properties")
    func stepHasCorrectProperties() {
        let step = SimpleOnboardingStep(
            id: "test",
            title: "Test Step",
            subtitle: "Test subtitle",
            iconName: "star",
            isSkippable: true,
            isComplete: false
        )
        
        #expect(step.id == "test")
        #expect(step.title == "Test Step")
        #expect(step.subtitle == "Test subtitle")
        #expect(step.iconName == "star")
        #expect(step.isSkippable)
        #expect(!step.isComplete)
    }
    
    @Test("Step validates with default validator")
    func stepValidatesWithDefault() async {
        let step = SimpleOnboardingStep(
            id: "test",
            title: "Test"
        )
        
        let result = await step.validate()
        #expect(result.isValid)
    }
    
    @Test("Step validates with custom validator")
    func stepValidatesWithCustom() async {
        let step = SimpleOnboardingStep(
            id: "test",
            title: "Test",
            validator: { .invalid("Custom error") }
        )
        
        let result = await step.validate()
        #expect(!result.isValid)
        #expect(result.errorMessage == "Custom error")
    }
}

// MARK: - Onboarding State Tests

@Suite("OnboardingState")
struct OnboardingStateTests {
    
    @Test("States are equatable")
    func statesAreEquatable() {
        #expect(OnboardingState.notStarted == .notStarted)
        #expect(OnboardingState.completed == .completed)
        #expect(OnboardingState.skipped == .skipped)
        #expect(OnboardingState.inProgress(stepIndex: 0) == .inProgress(stepIndex: 0))
        #expect(OnboardingState.inProgress(stepIndex: 0) != .inProgress(stepIndex: 1))
    }
}

// MARK: - Onboarding Coordinator Tests

#if canImport(SwiftUI)
@Suite("OnboardingCoordinator")
@MainActor
struct OnboardingCoordinatorTests {
    
    @available(iOS 17.0, macOS 14.0, *)
    func makeTestSteps() -> [SimpleOnboardingStep] {
        [
            SimpleOnboardingStep(id: "step1", title: "Step 1"),
            SimpleOnboardingStep(id: "step2", title: "Step 2", isSkippable: true),
            SimpleOnboardingStep(id: "step3", title: "Step 3"),
        ]
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Coordinator initializes with steps")
    func coordinatorInitializes() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        
        #expect(coordinator.steps.count == 3)
        #expect(coordinator.currentStepIndex == 0)
        #expect(coordinator.state == .notStarted)
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Empty coordinator is immediately complete")
    func emptyCoordinatorComplete() {
        let coordinator = OnboardingCoordinator<SimpleOnboardingStep>(steps: [])
        coordinator.start()
        
        #expect(coordinator.state == .completed)
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Start begins at first step")
    func startBeginsAtFirst() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        coordinator.start()
        
        #expect(coordinator.currentStepIndex == 0)
        #expect(coordinator.state == .inProgress(stepIndex: 0))
        #expect(coordinator.currentStep?.id == "step1")
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Progress is calculated correctly")
    func progressIsCorrect() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        coordinator.start()
        
        #expect(coordinator.progress == 1.0 / 3.0)
        
        coordinator.goToStep(1)
        #expect(coordinator.progress == 2.0 / 3.0)
        
        coordinator.goToStep(2)
        #expect(coordinator.progress == 1.0)
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Can go back from later steps")
    func canGoBack() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        coordinator.start()
        
        #expect(!coordinator.canGoBack)
        
        coordinator.goToStep(1)
        #expect(coordinator.canGoBack)
        
        coordinator.back()
        #expect(coordinator.currentStepIndex == 0)
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Is last step detected correctly")
    func isLastStepDetected() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        coordinator.start()
        
        #expect(!coordinator.isLastStep)
        
        coordinator.goToStep(2)
        #expect(coordinator.isLastStep)
    }
    
    @available(iOS 17.0, macOS 14.0, *)
    @Test("Reset returns to start")
    func resetReturns() {
        let coordinator = OnboardingCoordinator(steps: makeTestSteps())
        coordinator.start()
        coordinator.goToStep(2)
        coordinator.reset()
        
        #expect(coordinator.currentStepIndex == 0)
        #expect(coordinator.state == .notStarted)
    }
}
#endif

// MARK: - Onboarding Persistence Tests

@Suite("OnboardingPersistence")
struct OnboardingPersistenceTests {
    
    @Test("Marks flow as complete")
    func marksFlowComplete() {
        let defaults = UserDefaults(suiteName: "test_onboarding")!
        defaults.removePersistentDomain(forName: "test_onboarding")
        
        let persistence = OnboardingPersistence(defaults: defaults, appIdentifier: "test")
        
        #expect(!persistence.isComplete(flowId: "main"))
        
        persistence.markComplete(flowId: "main")
        #expect(persistence.isComplete(flowId: "main"))
        #expect(persistence.completionDate(flowId: "main") != nil)
    }
    
    @Test("Reset clears completion")
    func resetClearsCompletion() {
        let defaults = UserDefaults(suiteName: "test_onboarding_reset")!
        defaults.removePersistentDomain(forName: "test_onboarding_reset")
        
        let persistence = OnboardingPersistence(defaults: defaults, appIdentifier: "test")
        persistence.markComplete(flowId: "main")
        persistence.reset(flowId: "main")
        
        #expect(!persistence.isComplete(flowId: "main"))
    }
    
    @Test("Saves and loads step progress")
    func savesStepProgress() {
        let defaults = UserDefaults(suiteName: "test_onboarding_progress")!
        defaults.removePersistentDomain(forName: "test_onboarding_progress")
        
        let persistence = OnboardingPersistence(defaults: defaults, appIdentifier: "test")
        
        persistence.saveProgress(flowId: "main", stepIndex: 2)
        #expect(persistence.lastCompletedStep(flowId: "main") == 2)
    }
}

// MARK: - Common Step Type Tests

@Suite("CommonOnboardingStepType")
struct CommonOnboardingStepTypeTests {
    
    @Test("All step types have titles")
    func allTypesHaveTitles() {
        for stepType in CommonOnboardingStepType.allCases {
            #expect(!stepType.title.isEmpty)
        }
    }
    
    @Test("All step types have icons")
    func allTypesHaveIcons() {
        for stepType in CommonOnboardingStepType.allCases {
            #expect(!stepType.iconName.isEmpty)
        }
    }
    
    @Test("Expected step types exist")
    func expectedTypesExist() {
        let types = CommonOnboardingStepType.allCases
        #expect(types.contains(.welcome))
        #expect(types.contains(.healthKit))
        #expect(types.contains(.cgmSetup))
        #expect(types.contains(.pumpSetup))
        #expect(types.contains(.safetyReview))
    }
}
