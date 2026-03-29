// SPDX-License-Identifier: MIT
//
// CommandVerifierTests.swift
// T1Pal Mobile
//
// Unit tests for CommandVerifier
// Requirements: REQ-AID-006

import Testing
import Foundation
@testable import PumpKit

// MARK: - CommandVerifier Tests

@Suite("Command Verifier")
struct CommandVerifierTests {
    
    let verifier = CommandVerifier()
    
    // MARK: - Connection State Tests
    
    @Test("Disconnected pump fails verification")
    func disconnectedFails() {
        let status = PumpStatus(connectionState: .disconnected)
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .notConnected)
    }
    
    @Test("Connecting pump fails verification")
    func connectingFails() {
        let status = PumpStatus(connectionState: .connecting)
        let command = PumpCommand.tempBasal(TempBasalCommand(rate: 1.5, duration: 1800))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .notConnected)
    }
    
    @Test("Error state fails verification")
    func errorStateFails() {
        let status = PumpStatus(connectionState: .error)
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .pumpInError)
    }
    
    @Test("Connected pump passes basic verification")
    func connectedPasses() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.error == nil)
    }
    
    // MARK: - Suspended State Tests
    
    @Test("Suspended pump blocks bolus")
    func suspendedBlocksBolus() {
        let status = PumpStatus(connectionState: .suspended, reservoirLevel: 100)
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .pumpSuspended)
    }
    
    @Test("Suspended pump allows resume")
    func suspendedAllowsResume() {
        let status = PumpStatus(connectionState: .suspended)
        let command = PumpCommand.resume(ResumeCommand())
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
    }
    
    @Test("Connected pump blocks resume")
    func connectedBlocksResume() {
        let status = PumpStatus(connectionState: .connected)
        let command = PumpCommand.resume(ResumeCommand())
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        if case .stateConflict(let msg) = result.error {
            #expect(msg.contains("not suspended"))
        } else {
            Issue.record("Expected stateConflict error")
        }
    }
    
    @Test("Suspended pump blocks duplicate suspend")
    func suspendedBlocksSuspend() {
        let status = PumpStatus(connectionState: .suspended)
        let command = PumpCommand.suspend(SuspendCommand())
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .pumpSuspended)
    }
}

// MARK: - Bolus Verification Tests

@Suite("Bolus Verification")
struct BolusVerificationTests {
    
    let verifier = CommandVerifier()
    
    @Test("Insufficient reservoir blocks bolus")
    func insufficientReservoir() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 5.0,
            batteryLevel: 0.80
        )
        let command = PumpCommand.bolus(BolusCommand.normal(10.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        if case .insufficientReservoir(let required, let available) = result.error {
            #expect(required == 10.0)
            #expect(available == 5.0)
        } else {
            Issue.record("Expected insufficientReservoir error")
        }
    }
    
    @Test("Low battery blocks bolus")
    func lowBatteryBlocks() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.05
        )
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        if case .lowBattery(let level) = result.error {
            #expect(level == 0.05)
        } else {
            Issue.record("Expected lowBattery error")
        }
    }
    
    @Test("Bolus in progress blocks new bolus")
    func bolusInProgressBlocks() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let existingBolus = BolusProgress(
            command: BolusCommand.normal(2.0),
            deliveredUnits: 1.0,
            startTime: Date()
        )
        let deliveryState = DeliveryState(bolusInProgress: existingBolus)
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(!result.canProceed)
        #expect(result.error == .bolusInProgress)
    }
    
    @Test("Large bolus generates warning")
    func largeBolusWarning() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let command = PumpCommand.bolus(BolusCommand.normal(12.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.warnings.contains(.largeBolus(units: 12.0)))
    }
    
    @Test("Low reservoir generates warning")
    func lowReservoirWarning() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 15.0,
            batteryLevel: 0.80
        )
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.warnings.contains(.lowReservoir(level: 15.0)))
    }
    
    @Test("Warning battery generates warning")
    func warningBatteryWarning() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.15
        )
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.warnings.contains(.lowBattery(level: 0.15)))
    }
}

// MARK: - TempBasal Verification Tests

@Suite("TempBasal Verification")
struct TempBasalVerificationTests {
    
    let verifier = CommandVerifier()
    
    @Test("TempBasal with sufficient reservoir passes")
    func sufficientReservoirPasses() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let command = PumpCommand.tempBasal(TempBasalCommand(rate: 2.0, duration: 3600))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
    }
    
    @Test("TempBasal checks total delivery against reservoir")
    func tempBasalReservoirCheck() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 1.0,
            batteryLevel: 0.80
        )
        // 2 U/hr for 2 hours = 4 units required
        let command = PumpCommand.tempBasal(TempBasalCommand(rate: 2.0, duration: 7200))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        if case .insufficientReservoir(let required, let available) = result.error {
            #expect(abs(required - 4.0) < 0.01)
            #expect(available == 1.0)
        } else {
            Issue.record("Expected insufficientReservoir error")
        }
    }
    
    @Test("High temp basal generates warning")
    func highTempBasalWarning() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let command = PumpCommand.tempBasal(TempBasalCommand(rate: 6.0, duration: 1800))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.warnings.contains(.highTempBasal(rate: 6.0)))
    }
}

// MARK: - Cancel Command Tests

@Suite("Cancel Commands")
struct CancelCommandTests {
    
    let verifier = CommandVerifier()
    
    @Test("Cancel temp basal when connected passes")
    func cancelTempBasalPasses() {
        let status = PumpStatus(connectionState: .connected)
        let command = PumpCommand.cancelTempBasal
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
    }
    
    @Test("Cancel bolus with no bolus fails")
    func cancelBolusNoBolusInProgress() {
        let status = PumpStatus(connectionState: .connected)
        let deliveryState = DeliveryState()  // No bolus in progress
        let command = PumpCommand.cancelBolus
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(!result.canProceed)
        if case .stateConflict(let msg) = result.error {
            #expect(msg.contains("No bolus"))
        } else {
            Issue.record("Expected stateConflict error")
        }
    }
    
    @Test("Cancel bolus with bolus in progress passes")
    func cancelBolusWithBolusInProgress() {
        let status = PumpStatus(connectionState: .connected)
        let bolus = BolusProgress(
            command: BolusCommand.normal(2.0),
            deliveredUnits: 1.0,
            startTime: Date()
        )
        let deliveryState = DeliveryState(bolusInProgress: bolus)
        let command = PumpCommand.cancelBolus
        
        let result = verifier.verify(command: command, status: status, deliveryState: deliveryState)
        
        #expect(result.canProceed)
    }
}

// MARK: - Custom Configuration Tests

@Suite("Verifier Configuration")
struct VerifierConfigurationTests {
    
    @Test("Custom thresholds are respected")
    func customThresholds() {
        let config = CommandVerifier.Configuration(
            minimumBatteryLevel: 0.25,
            warningBatteryLevel: 0.50,
            warningReservoirLevel: 50.0,
            largeBolusThreshold: 5.0,
            highTempBasalThreshold: 3.0
        )
        let verifier = CommandVerifier(configuration: config)
        
        // Battery at 20% should fail with custom 25% minimum
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.20
        )
        let command = PumpCommand.bolus(BolusCommand.normal(1.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(!result.canProceed)
        #expect(result.error == .lowBattery(level: 0.20))
    }
    
    @Test("Custom large bolus threshold")
    func customLargeBolusThreshold() {
        let config = CommandVerifier.Configuration(largeBolusThreshold: 5.0)
        let verifier = CommandVerifier(configuration: config)
        
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 100,
            batteryLevel: 0.80
        )
        let command = PumpCommand.bolus(BolusCommand.normal(6.0))
        
        let result = verifier.verify(command: command, status: status)
        
        #expect(result.canProceed)
        #expect(result.warnings.contains(.largeBolus(units: 6.0)))
    }
}

// MARK: - RetryExecutor Tests

@Suite("Retry Executor")
struct PumpRetryExecutorTests {
    
    @Test("Successful operation returns immediately")
    func successfulOperation() async throws {
        let executor = PumpRetryExecutor()
        
        let result = try await executor.execute {
            return "success"
        }
        
        #expect(result == "success")
    }
    
    @Test("Retries on failure")
    func retriesOnFailure() async throws {
        let executor = PumpRetryExecutor(configuration: .init(
            maxAttempts: 3,
            initialDelay: 0.01,  // Fast for tests
            maxDelay: 0.05,
            backoffMultiplier: 2.0
        ))
        
        let counter = AttemptCounter()
        
        let result = try await executor.execute {
            let count = await counter.increment()
            if count < 3 {
                throw PumpError.communicationError
            }
            return count
        }
        
        #expect(result == 3)
    }
    
    @Test("Throws after max attempts")
    func throwsAfterMaxAttempts() async {
        let executor = PumpRetryExecutor(configuration: .init(
            maxAttempts: 2,
            initialDelay: 0.01,
            maxDelay: 0.05,
            backoffMultiplier: 2.0
        ))
        
        await #expect(throws: CommandVerificationError.self) {
            try await executor.execute {
                throw PumpError.communicationError
            }
        }
    }
    
    @Test("Non-retryable errors throw immediately")
    func nonRetryableErrorsThrowImmediately() async {
        let executor = PumpRetryExecutor()
        let counter = AttemptCounter()
        
        await #expect(throws: PumpError.self) {
            try await executor.execute(
                operation: {
                    await counter.increment()
                    throw PumpError.reservoirEmpty
                },
                isRetryable: PumpRetryExecutor.isRetryable
            )
        }
        
        let attempts = await counter.count
        #expect(attempts == 1)
    }
}

// MARK: - Retryable Error Classification

@Suite("Retryable Error Classification")
struct RetryableErrorTests {
    
    @Test("Communication error is retryable")
    func communicationErrorRetryable() {
        #expect(PumpRetryExecutor.isRetryable(PumpError.communicationError))
    }
    
    @Test("Connection failed is retryable")
    func connectionFailedRetryable() {
        #expect(PumpRetryExecutor.isRetryable(PumpError.connectionFailed))
    }
    
    @Test("Delivery failed is not retryable")
    func deliveryFailedNotRetryable() {
        #expect(!PumpRetryExecutor.isRetryable(PumpError.deliveryFailed))
    }
    
    @Test("Reservoir empty is not retryable")
    func reservoirEmptyNotRetryable() {
        #expect(!PumpRetryExecutor.isRetryable(PumpError.reservoirEmpty))
    }
    
    @Test("Occlusion is not retryable")
    func occlusionNotRetryable() {
        #expect(!PumpRetryExecutor.isRetryable(PumpError.occluded))
    }
}

// MARK: - CommandVerificationError Tests

@Suite("Command Verification Errors")
struct CommandVerificationErrorTests {
    
    @Test("All error cases are defined")
    func allErrorCases() {
        let errors: [CommandVerificationError] = [
            .notConnected,
            .pumpSuspended,
            .pumpInError,
            .insufficientReservoir(required: 5, available: 2),
            .lowBattery(level: 0.05),
            .bolusInProgress,
            .stateConflict(message: "test"),
            .communicationFailed(attempts: 3),
            .timeout
        ]
        #expect(errors.count == 9)
    }
    
    @Test("Errors are equatable")
    func errorsEquatable() {
        #expect(CommandVerificationError.notConnected == .notConnected)
        #expect(CommandVerificationError.insufficientReservoir(required: 5, available: 2) ==
                .insufficientReservoir(required: 5, available: 2))
        #expect(CommandVerificationError.communicationFailed(attempts: 3) !=
                .communicationFailed(attempts: 2))
    }
}

// MARK: - Warning Tests

@Suite("Command Warnings")
struct CommandWarningTests {
    
    @Test("All warning cases are defined")
    func allWarningCases() {
        let warnings: [CommandWarning] = [
            .lowReservoir(level: 15),
            .lowBattery(level: 0.15),
            .staleCommunication(lastContact: Date()),
            .largeBolus(units: 12),
            .highTempBasal(rate: 6)
        ]
        #expect(warnings.count == 5)
    }
    
    @Test("Warnings are equatable")
    func warningsEquatable() {
        #expect(CommandWarning.lowReservoir(level: 15) == .lowReservoir(level: 15))
        #expect(CommandWarning.largeBolus(units: 10) != .largeBolus(units: 12))
    }
}

// MARK: - Helper

actor AttemptCounter {
    private(set) var count = 0
    
    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}
