// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CommandVerifier.swift
// T1Pal Mobile
//
// Command verification for pump safety
// Requirements: REQ-AID-006
//
// Verifies pump state before command execution and handles
// communication failures with retry logic.

import Foundation

// MARK: - Verification Errors

/// Errors specific to command verification
public enum CommandVerificationError: Error, Sendable, Equatable {
    /// Pump is not connected
    case notConnected
    /// Pump is suspended and cannot deliver insulin
    case pumpSuspended
    /// Pump is in error state
    case pumpInError
    /// Insufficient reservoir for delivery
    case insufficientReservoir(required: Double, available: Double)
    /// Battery too low for safe delivery
    case lowBattery(level: Double)
    /// Bolus already in progress
    case bolusInProgress
    /// Command conflicts with current state
    case stateConflict(message: String)
    /// Communication with pump failed
    case communicationFailed(attempts: Int)
    /// Verification timeout
    case timeout
}

// MARK: - Verification Result

/// Result of command verification
public struct CommandVerificationResult: Sendable {
    /// Whether the command can proceed
    public let canProceed: Bool
    /// Warnings that don't prevent execution but should be noted
    public let warnings: [CommandWarning]
    /// Error if command cannot proceed
    public let error: CommandVerificationError?
    
    public static func success(warnings: [CommandWarning] = []) -> CommandVerificationResult {
        CommandVerificationResult(canProceed: true, warnings: warnings, error: nil)
    }
    
    public static func failure(_ error: CommandVerificationError) -> CommandVerificationResult {
        CommandVerificationResult(canProceed: false, warnings: [], error: error)
    }
}

/// Warning that doesn't prevent command but should be logged
public enum CommandWarning: Sendable, Equatable {
    /// Reservoir level is low
    case lowReservoir(level: Double)
    /// Battery level is low but acceptable
    case lowBattery(level: Double)
    /// Last communication was some time ago
    case staleCommunication(lastContact: Date)
    /// Large bolus requested
    case largeBolus(units: Double)
    /// High temp basal rate
    case highTempBasal(rate: Double)
}

// MARK: - Command Verifier

/// Verifies pump state before command execution
/// Requirements: REQ-AID-006
public struct CommandVerifier: Sendable {
    
    // MARK: - Configuration
    
    /// Configuration for verification thresholds
    public struct Configuration: Sendable {
        /// Minimum battery level for delivery (0-1)
        public let minimumBatteryLevel: Double
        /// Warning battery level (0-1)
        public let warningBatteryLevel: Double
        /// Warning reservoir level (units)
        public let warningReservoirLevel: Double
        /// Large bolus warning threshold (units)
        public let largeBolusThreshold: Double
        /// High temp basal warning threshold (U/hr)
        public let highTempBasalThreshold: Double
        /// Max stale communication time before warning
        public let staleCommunicationInterval: TimeInterval
        
        public static let `default` = Configuration(
            minimumBatteryLevel: 0.10,
            warningBatteryLevel: 0.20,
            warningReservoirLevel: 20.0,
            largeBolusThreshold: 10.0,
            highTempBasalThreshold: 5.0,
            staleCommunicationInterval: 300 // 5 minutes
        )
        
        public init(
            minimumBatteryLevel: Double = 0.10,
            warningBatteryLevel: Double = 0.20,
            warningReservoirLevel: Double = 20.0,
            largeBolusThreshold: Double = 10.0,
            highTempBasalThreshold: Double = 5.0,
            staleCommunicationInterval: TimeInterval = 300
        ) {
            self.minimumBatteryLevel = minimumBatteryLevel
            self.warningBatteryLevel = warningBatteryLevel
            self.warningReservoirLevel = warningReservoirLevel
            self.largeBolusThreshold = largeBolusThreshold
            self.highTempBasalThreshold = highTempBasalThreshold
            self.staleCommunicationInterval = staleCommunicationInterval
        }
    }
    
    private let configuration: Configuration
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Verification Methods
    
    /// Verify pump state before executing any command
    public func verify(
        command: PumpCommand,
        status: PumpStatus,
        deliveryState: DeliveryState? = nil
    ) -> CommandVerificationResult {
        // Check connection state first
        switch status.connectionState {
        case .disconnected, .connecting:
            return .failure(.notConnected)
        case .suspended:
            // Only resume is allowed when suspended
            if case .resume = command {
                return .success()
            }
            return .failure(.pumpSuspended)
        case .error:
            return .failure(.pumpInError)
        case .connected:
            break // Continue with other checks
        }
        
        // Command-specific verification
        switch command {
        case .bolus(let bolusCommand):
            return verifyBolus(bolusCommand, status: status, deliveryState: deliveryState)
        case .tempBasal(let tempBasalCommand):
            return verifyTempBasal(tempBasalCommand, status: status)
        case .cancelTempBasal:
            return verifyCancelTempBasal(status: status)
        case .cancelBolus:
            return verifyCancelBolus(deliveryState: deliveryState)
        case .suspend:
            return verifySuspend(status: status)
        case .resume:
            return verifyResume(status: status)
        }
    }
    
    // MARK: - Bolus Verification
    
    private func verifyBolus(
        _ command: BolusCommand,
        status: PumpStatus,
        deliveryState: DeliveryState?
    ) -> CommandVerificationResult {
        var warnings: [CommandWarning] = []
        
        // Check if bolus already in progress
        if let state = deliveryState, state.bolusInProgress != nil {
            return .failure(.bolusInProgress)
        }
        
        // Check reservoir level
        if let reservoir = status.reservoirLevel {
            if reservoir < command.units {
                return .failure(.insufficientReservoir(required: command.units, available: reservoir))
            }
            if reservoir < configuration.warningReservoirLevel {
                warnings.append(.lowReservoir(level: reservoir))
            }
        }
        
        // Check battery
        if let battery = status.batteryLevel {
            if battery < configuration.minimumBatteryLevel {
                return .failure(.lowBattery(level: battery))
            }
            if battery < configuration.warningBatteryLevel {
                warnings.append(.lowBattery(level: battery))
            }
        }
        
        // Large bolus warning
        if command.units >= configuration.largeBolusThreshold {
            warnings.append(.largeBolus(units: command.units))
        }
        
        return .success(warnings: warnings)
    }
    
    // MARK: - Temp Basal Verification
    
    private func verifyTempBasal(
        _ command: TempBasalCommand,
        status: PumpStatus
    ) -> CommandVerificationResult {
        var warnings: [CommandWarning] = []
        
        // Check battery
        if let battery = status.batteryLevel {
            if battery < configuration.minimumBatteryLevel {
                return .failure(.lowBattery(level: battery))
            }
            if battery < configuration.warningBatteryLevel {
                warnings.append(.lowBattery(level: battery))
            }
        }
        
        // Check reservoir for total temp basal delivery
        if let reservoir = status.reservoirLevel {
            let totalUnits = command.totalUnits
            if reservoir < totalUnits {
                return .failure(.insufficientReservoir(required: totalUnits, available: reservoir))
            }
            if reservoir < configuration.warningReservoirLevel {
                warnings.append(.lowReservoir(level: reservoir))
            }
        }
        
        // High rate warning
        if command.rate >= configuration.highTempBasalThreshold {
            warnings.append(.highTempBasal(rate: command.rate))
        }
        
        return .success(warnings: warnings)
    }
    
    // MARK: - Other Verifications
    
    private func verifyCancelTempBasal(status: PumpStatus) -> CommandVerificationResult {
        // Cancel temp basal is generally safe if connected
        return .success()
    }
    
    private func verifyCancelBolus(deliveryState: DeliveryState?) -> CommandVerificationResult {
        // Warn if no bolus to cancel
        if let state = deliveryState, state.bolusInProgress == nil {
            return .failure(.stateConflict(message: "No bolus in progress to cancel"))
        }
        return .success()
    }
    
    private func verifySuspend(status: PumpStatus) -> CommandVerificationResult {
        if status.connectionState == .suspended {
            return .failure(.stateConflict(message: "Pump already suspended"))
        }
        return .success()
    }
    
    private func verifyResume(status: PumpStatus) -> CommandVerificationResult {
        if status.connectionState != .suspended {
            return .failure(.stateConflict(message: "Pump not suspended"))
        }
        return .success()
    }
}

// MARK: - Retry Executor

import BLEKit

/// Executes pump commands with retry logic
/// Requirements: REQ-AID-006
/// 
/// This is a thin wrapper around BLEKit.RetryExecutor providing pump-specific
/// configuration and error classification.
/// Trace: COMPL-DUP-003
public actor PumpRetryExecutor {
    
    /// Configuration for retry behavior (maps to BLEKit.RetryPolicy)
    public struct Configuration: Sendable {
        /// Maximum number of retry attempts
        public let maxAttempts: Int
        /// Initial delay between retries
        public let initialDelay: TimeInterval
        /// Maximum delay between retries
        public let maxDelay: TimeInterval
        /// Backoff multiplier
        public let backoffMultiplier: Double
        
        public static let `default` = Configuration(
            maxAttempts: 3,
            initialDelay: 1.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )
        
        public init(
            maxAttempts: Int = 3,
            initialDelay: TimeInterval = 1.0,
            maxDelay: TimeInterval = 30.0,
            backoffMultiplier: Double = 2.0
        ) {
            self.maxAttempts = maxAttempts
            self.initialDelay = initialDelay
            self.maxDelay = maxDelay
            self.backoffMultiplier = backoffMultiplier
        }
        
        /// Convert to BLEKit.RetryPolicy
        var asRetryPolicy: RetryPolicy {
            RetryPolicy(
                baseDelay: initialDelay,
                maxDelay: maxDelay,
                maxAttempts: maxAttempts,
                multiplier: backoffMultiplier,
                jitter: .equal  // Use equal jitter for pump commands (predictable minimum delay)
            )
        }
    }
    
    private let configuration: Configuration
    private let backoffCalculator: BackoffCalculator
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.backoffCalculator = BackoffCalculator(policy: configuration.asRetryPolicy)
    }
    
    /// Execute an async operation with retry logic
    public func execute<T: Sendable>(
        operation: @Sendable () async throws -> T,
        isRetryable: @Sendable (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var attempts = 0
        
        // Use the BLEKit executor's retry policy for delays but handle error classification here
        while attempts < configuration.maxAttempts {
            attempts += 1
            do {
                return try await operation()
            } catch {
                // Non-retryable errors propagate immediately
                guard isRetryable(error) else {
                    throw error
                }
                
                // Don't delay after last attempt
                if attempts < configuration.maxAttempts {
                    // Use BLEKit's BackoffCalculator for delay with jitter
                    let delay = backoffCalculator.delay(forAttempt: attempts - 1)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All retries exhausted
        throw CommandVerificationError.communicationFailed(attempts: attempts)
    }
    
    /// Check if a pump error is retryable
    public static func isRetryable(_ error: Error) -> Bool {
        guard let pumpError = error as? PumpError else {
            return false
        }
        
        switch pumpError {
        case .communicationError, .connectionFailed:
            return true
        case .deliveryFailed, .suspended, .reservoirEmpty, .occluded, .expired,
             .notConnected, .noSession, .exceedsMaxBasal, .exceedsMaxBolus, .noPodPaired,
             .alreadyActivated, .pumpFaulted, .insufficientReservoir:
            return false
        }
    }
}

/// Backward compatibility alias
@available(*, deprecated, renamed: "PumpRetryExecutor")
public typealias RetryExecutor = PumpRetryExecutor

// MARK: - Safe Command Executor

/// Helper class for tracking retry attempts safely across Sendable boundaries
private final class AttemptCounter: @unchecked Sendable {
    var count = 0
}

/// Combines verification and retry for safe command execution
/// Requirements: REQ-AID-006
public actor SafeCommandExecutor {
    private let verifier: CommandVerifier
    private let retryExecutor: PumpRetryExecutor
    
    public init(
        verifier: CommandVerifier = CommandVerifier(),
        retryExecutor: PumpRetryExecutor = PumpRetryExecutor()
    ) {
        self.verifier = verifier
        self.retryExecutor = retryExecutor
    }
    
    /// Result of a safe command execution
    public struct ExecutionResult<T: Sendable>: Sendable {
        public let value: T?
        public let warnings: [CommandWarning]
        public let error: Error?
        public let attempts: Int
        
        public var succeeded: Bool { error == nil && value != nil }
    }
    
    /// Execute a command safely with verification and retry
    public func execute<T: Sendable>(
        command: PumpCommand,
        pump: any PumpManagerProtocol,
        deliveryState: DeliveryState? = nil,
        operation: @Sendable () async throws -> T
    ) async -> ExecutionResult<T> {
        // Get current status
        let status = await pump.status
        
        // Verify command
        let verification = verifier.verify(
            command: command,
            status: status,
            deliveryState: deliveryState
        )
        
        guard verification.canProceed else {
            return ExecutionResult(
                value: nil,
                warnings: verification.warnings,
                error: verification.error,
                attempts: 0
            )
        }
        
        // Execute with retry - use class to track attempts safely
        let counter = AttemptCounter()
        do {
            let result = try await retryExecutor.execute(
                operation: {
                    counter.count += 1
                    return try await operation()
                },
                isRetryable: { @Sendable error in PumpRetryExecutor.isRetryable(error) }
            )
            
            return ExecutionResult(
                value: result,
                warnings: verification.warnings,
                error: nil,
                attempts: counter.count
            )
        } catch {
            return ExecutionResult(
                value: nil,
                warnings: verification.warnings,
                error: error,
                attempts: counter.count
            )
        }
    }
}
