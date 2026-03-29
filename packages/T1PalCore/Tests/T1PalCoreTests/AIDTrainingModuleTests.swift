// SPDX-License-Identifier: MIT
//
// AIDTrainingModuleTests.swift
// T1PalCore Tests
//
// Tests for AID safety training and confirmation flow
// Backlog: ENHANCE-TIER3-001

import Foundation
import Testing
@testable import T1PalCore

// MARK: - Training Step Tests

@Suite("Training Step")
struct TrainingStepTests {
    
    @Test("All steps exist")
    func testAllCases() {
        #expect(TrainingStep.allCases.count == 10)
    }
    
    @Test("All steps have titles")
    func testTitles() {
        for step in TrainingStep.allCases {
            #expect(!step.title.isEmpty)
        }
    }
    
    @Test("All steps have descriptions")
    func testDescriptions() {
        for step in TrainingStep.allCases {
            #expect(!step.description.isEmpty)
        }
    }
    
    @Test("All steps have symbols")
    func testSymbols() {
        for step in TrainingStep.allCases {
            #expect(!step.symbolName.isEmpty)
        }
    }
    
    @Test("All steps have positive duration")
    func testDurations() {
        for step in TrainingStep.allCases {
            #expect(step.estimatedDuration > 0)
        }
    }
    
    @Test("Welcome has no prerequisites")
    func testWelcomePrerequisites() {
        #expect(TrainingStep.welcome.prerequisites.isEmpty)
    }
    
    @Test("Acknowledgment has all prerequisites")
    func testAcknowledgmentPrerequisites() {
        let prereqs = TrainingStep.acknowledgment.prerequisites
        #expect(!prereqs.isEmpty)
    }
    
    @Test("Critical steps require acknowledgment")
    func testAcknowledgmentRequired() {
        #expect(TrainingStep.safetyLimits.requiresAcknowledgment == true)
        #expect(TrainingStep.emergencyProcedures.requiresAcknowledgment == true)
        #expect(TrainingStep.acknowledgment.requiresAcknowledgment == true)
    }
    
    @Test("Informational steps do not require acknowledgment")
    func testNoAcknowledgmentRequired() {
        #expect(TrainingStep.welcome.requiresAcknowledgment == false)
        #expect(TrainingStep.howAIDWorks.requiresAcknowledgment == false)
    }
    
    @Test("Step is Codable")
    func testCodable() throws {
        let step = TrainingStep.safetyLimits
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(step)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrainingStep.self, from: data)
        
        #expect(decoded == step)
    }
}

// MARK: - Training Progress Tests

@Suite("Training Progress")
struct TrainingProgressTests {
    
    @Test("Empty progress")
    func testEmptyProgress() {
        let progress = TrainingProgress.empty
        
        #expect(progress.completedSteps.isEmpty)
        #expect(progress.progress == 0.0)
        #expect(progress.isComplete == false)
        #expect(progress.hasStarted == false)
    }
    
    @Test("Current step is first")
    func testCurrentStep() {
        let progress = TrainingProgress.empty
        
        #expect(progress.currentStep == .welcome)
    }
    
    @Test("Complete step updates progress")
    func testCompleteStep() {
        let progress = TrainingProgress.empty
        let updated = progress.withStepCompleted(.welcome)
        
        #expect(updated.completedSteps.contains(.welcome))
        #expect(updated.progress > 0.0)
        #expect(updated.hasStarted == true)
        #expect(updated.startedAt != nil)
        #expect(updated.lastActivityAt != nil)
    }
    
    @Test("Acknowledge step")
    func testAcknowledgeStep() {
        let progress = TrainingProgress.empty
        let updated = progress.withStepAcknowledged(.safetyLimits)
        
        #expect(updated.acknowledgedSteps.contains(.safetyLimits))
    }
    
    @Test("Complete all steps")
    func testCompleteAll() {
        var progress = TrainingProgress.empty
        
        for step in TrainingStep.allCases {
            progress = progress.withStepCompleted(step)
        }
        
        #expect(progress.isComplete == true)
        #expect(progress.progress == 1.0)
        #expect(progress.completedAt != nil)
        #expect(progress.remainingSteps.isEmpty)
    }
    
    @Test("Remaining steps")
    func testRemainingSteps() {
        var progress = TrainingProgress.empty
        progress = progress.withStepCompleted(.welcome)
        progress = progress.withStepCompleted(.howAIDWorks)
        
        let remaining = progress.remainingSteps
        #expect(!remaining.contains(.welcome))
        #expect(!remaining.contains(.howAIDWorks))
        #expect(remaining.contains(.safetyLimits))
    }
    
    @Test("Estimated remaining time")
    func testEstimatedRemainingTime() {
        let progress = TrainingProgress.empty
        
        #expect(progress.estimatedRemainingTime > 0)
        #expect(progress.estimatedRemainingTime == progress.totalEstimatedTime)
    }
    
    @Test("Progress is Codable")
    func testCodable() throws {
        var progress = TrainingProgress.empty
        progress = progress.withStepCompleted(.welcome)
        progress = progress.withStepAcknowledged(.safetyLimits)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(progress)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrainingProgress.self, from: data)
        
        #expect(decoded.completedSteps == progress.completedSteps)
        #expect(decoded.acknowledgedSteps == progress.acknowledgedSteps)
    }
}

// MARK: - Safety Acknowledgment Tests

@Suite("Safety Acknowledgment")
struct SafetyAcknowledgmentTests {
    
    @Test("Create acknowledgment")
    func testCreate() {
        let ack = SafetyAcknowledgment(deviceId: "test-device")
        
        #expect(ack.deviceId == "test-device")
        #expect(ack.version == "1.0")
        #expect(!ack.agreementText.isEmpty)
    }
    
    @Test("New acknowledgment is valid")
    func testIsValid() {
        let ack = SafetyAcknowledgment(deviceId: "test")
        
        #expect(ack.isValid == true)
        #expect(ack.daysUntilExpiration > 360)
    }
    
    @Test("Expired acknowledgment is invalid")
    func testExpired() {
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let ack = SafetyAcknowledgment(
            acknowledgedAt: oldDate,
            version: "1.0",
            deviceId: "test"
        )
        
        #expect(ack.isValid == false)
        #expect(ack.daysUntilExpiration == 0)
    }
    
    @Test("Default agreement text exists")
    func testDefaultText() {
        #expect(!SafetyAcknowledgment.defaultAgreementText.isEmpty)
        #expect(SafetyAcknowledgment.defaultAgreementText.contains("understand"))
    }
    
    @Test("Acknowledgment is Codable")
    func testCodable() throws {
        let ack = SafetyAcknowledgment(deviceId: "test-device")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(ack)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SafetyAcknowledgment.self, from: data)
        
        #expect(decoded.deviceId == ack.deviceId)
        #expect(decoded.version == ack.version)
    }
}

// MARK: - Training Error Tests

@Suite("Training Error")
struct TrainingErrorTests {
    
    @Test("Error descriptions")
    func testDescriptions() {
        let errors: [TrainingError] = [
            .stepNotAvailable(.welcome),
            .prerequisiteNotMet(.howAIDWorks),
            .acknowledgmentRequired(.safetyLimits),
            .alreadyCompleted,
            .notStarted,
            .expired
        ]
        
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
    
    @Test("Error equality")
    func testEquality() {
        let error1 = TrainingError.alreadyCompleted
        let error2 = TrainingError.alreadyCompleted
        let error3 = TrainingError.notStarted
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - Mock Training Manager Tests

@Suite("Mock AID Training Manager")
struct MockAIDTrainingManagerTests {
    
    @Test("Initial progress is empty")
    func testInitialProgress() async {
        let manager = MockAIDTrainingManager()
        
        let progress = await manager.getProgress()
        #expect(progress.completedSteps.isEmpty)
    }
    
    @Test("Start training")
    func testStartTraining() async throws {
        let manager = MockAIDTrainingManager()
        
        let progress = try await manager.startTraining()
        
        #expect(progress.hasStarted == true)
        
        let count = await manager.startCount
        #expect(count == 1)
    }
    
    @Test("Complete step")
    func testCompleteStep() async throws {
        let manager = MockAIDTrainingManager()
        
        let progress = try await manager.completeStep(.welcome)
        
        #expect(progress.completedSteps.contains(.welcome))
        
        let count = await manager.completeCount
        #expect(count == 1)
    }
    
    @Test("Acknowledge step")
    func testAcknowledgeStep() async throws {
        let manager = MockAIDTrainingManager()
        
        let progress = try await manager.acknowledgeStep(.safetyLimits)
        
        #expect(progress.acknowledgedSteps.contains(.safetyLimits))
        
        let count = await manager.acknowledgeCount
        #expect(count == 1)
    }
    
    @Test("Set completed")
    func testSetCompleted() async {
        let manager = MockAIDTrainingManager()
        
        await manager.setCompleted()
        
        let progress = await manager.getProgress()
        #expect(progress.isComplete == true)
        
        let ack = await manager.getAcknowledgment()
        #expect(ack != nil)
    }
    
    @Test("Submit acknowledgment")
    func testSubmitAcknowledgment() async throws {
        let manager = MockAIDTrainingManager()
        await manager.setCompleted()
        
        let ack = try await manager.submitAcknowledgment(deviceId: "my-device")
        
        #expect(ack.deviceId == "my-device")
    }
    
    @Test("Submit acknowledgment without completion fails")
    func testSubmitWithoutCompletion() async {
        let manager = MockAIDTrainingManager()
        
        do {
            _ = try await manager.submitAcknowledgment(deviceId: "test")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TrainingError {
            #expect(error == .notStarted)
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("Reset training")
    func testReset() async throws {
        let manager = MockAIDTrainingManager()
        await manager.setCompleted()
        
        await manager.resetTraining()
        
        let progress = await manager.getProgress()
        #expect(progress.completedSteps.isEmpty)
        
        let ack = await manager.getAcknowledgment()
        #expect(ack == nil)
    }
    
    @Test("Is training valid")
    func testIsTrainingValid() async {
        let manager = MockAIDTrainingManager()
        
        var isValid = await manager.isTrainingValid()
        #expect(isValid == false)
        
        await manager.setCompleted()
        
        isValid = await manager.isTrainingValid()
        #expect(isValid == true)
    }
    
    @Test("Failure simulation")
    func testFailure() async throws {
        let manager = MockAIDTrainingManager()
        await manager.setShouldFail(true)
        
        do {
            _ = try await manager.completeStep(.welcome)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected
        }
    }
}

// MARK: - Live Training Manager Tests

@Suite("Live AID Training Manager")
struct LiveAIDTrainingManagerTests {
    
    @Test("Creates with defaults")
    func testCreatesWithDefaults() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = LiveAIDTrainingManager(userDefaults: defaults)
        
        let progress = await manager.getProgress()
        #expect(progress.completedSteps.isEmpty)
    }
    
    @Test("Start training sets date")
    func testStartTraining() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = LiveAIDTrainingManager(userDefaults: defaults)
        
        let progress = try await manager.startTraining()
        
        #expect(progress.hasStarted == true)
        #expect(progress.startedAt != nil)
    }
    
    @Test("Cannot start if already complete")
    func testCannotRestartComplete() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = LiveAIDTrainingManager(userDefaults: defaults)
        
        // Complete all steps
        _ = try await manager.startTraining()
        for step in TrainingStep.allCases {
            if step.requiresAcknowledgment {
                _ = try await manager.acknowledgeStep(step)
            }
            _ = try await manager.completeStep(step)
        }
        
        // Try to start again
        do {
            _ = try await manager.startTraining()
            #expect(Bool(false), "Should have thrown")
        } catch let error as TrainingError {
            #expect(error == .alreadyCompleted)
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("Check prerequisite enforcement")
    func testPrerequisites() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = LiveAIDTrainingManager(userDefaults: defaults)
        
        // Try to complete safetyLimits without prerequisites
        do {
            _ = try await manager.completeStep(.safetyLimits)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TrainingError {
            if case .prerequisiteNotMet = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
}

// MARK: - Training Flow Helper Tests

@Suite("AID Training Flow Helper")
struct AIDTrainingFlowHelperTests {
    
    @Test("Complete all steps")
    func testCompleteAllSteps() async throws {
        let manager = MockAIDTrainingManager()
        let flow = AIDTrainingFlow(manager: manager)
        
        let progress = try await flow.completeAllSteps()
        
        #expect(progress.isComplete == true)
    }
    
    @Test("Can enable AID")
    func testCanEnableAID() async {
        let manager = MockAIDTrainingManager()
        let flow = AIDTrainingFlow(manager: manager)
        
        var canEnable = await flow.canEnableAID()
        #expect(canEnable == false)
        
        await manager.setCompleted()
        
        canEnable = await flow.canEnableAID()
        #expect(canEnable == true)
    }
    
    @Test("Get summary")
    func testGetSummary() async {
        let manager = MockAIDTrainingManager()
        let flow = AIDTrainingFlow(manager: manager)
        
        var summary = await flow.getSummary()
        #expect(summary.canEnableAID == false)
        #expect(summary.statusMessage.contains("not started"))
        
        await manager.setCompleted()
        
        summary = await flow.getSummary()
        #expect(summary.canEnableAID == true)
        #expect(summary.statusMessage.contains("complete"))
    }
}
