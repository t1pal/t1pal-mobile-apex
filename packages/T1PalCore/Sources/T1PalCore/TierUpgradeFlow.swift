// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TierUpgradeFlow.swift
// T1PalCore
//
// Tier upgrade orchestration and data migration
// Backlog: ENHANCE-FLOW-001
// PRD: PRD-013-progressive-enhancement.md

import Foundation

// MARK: - Tier Transition

/// Represents a transition between tiers
public struct TierTransition: Sendable, Equatable {
    public let fromTier: AppTier
    public let toTier: AppTier
    public let requiredSteps: [TierMigrationStep]
    public let isUpgrade: Bool
    
    public init(from: AppTier, to: AppTier) {
        self.fromTier = from
        self.toTier = to
        self.isUpgrade = to > from
        self.requiredSteps = TierTransition.calculateSteps(from: from, to: to)
    }
    
    /// Calculate required migration steps for this transition
    private static func calculateSteps(from: AppTier, to: AppTier) -> [TierMigrationStep] {
        var steps: [TierMigrationStep] = []
        
        if to > from {
            // Upgrading - add steps for each tier we're passing through
            for tier in AppTier.allCases where tier > from && tier <= to {
                steps.append(contentsOf: stepsForTier(tier))
            }
        } else if to < from {
            // Downgrading - add cleanup steps in reverse
            for tier in AppTier.allCases.reversed() where tier <= from && tier > to {
                steps.append(contentsOf: cleanupStepsForTier(tier))
            }
        }
        
        return steps
    }
    
    /// Steps required to enter a tier
    private static func stepsForTier(_ tier: AppTier) -> [TierMigrationStep] {
        switch tier {
        case .demo:
            return []
        case .identity:
            return [.validateAuthentication, .syncNightscoutProfile]
        case .cgm:
            return [.requestBluetoothPermission, .configureCGMDevice, .validateCGMData]
        case .aid:
            return [.configurePumpDevice, .validateAIDTraining, .enableAIDMode]
        }
    }
    
    /// Cleanup steps when leaving a tier
    private static func cleanupStepsForTier(_ tier: AppTier) -> [TierMigrationStep] {
        switch tier {
        case .demo:
            return []
        case .identity:
            return [.clearSessionData]
        case .cgm:
            return [.disconnectCGM, .archiveCGMData]
        case .aid:
            return [.disableAIDMode, .disconnectPump]
        }
    }
    
    /// Whether this transition requires user confirmation
    public var requiresConfirmation: Bool {
        // Downgrades and AID transitions require confirmation
        !isUpgrade || toTier == .aid
    }
    
    /// Display description
    public var displayDescription: String {
        if isUpgrade {
            return "Upgrade from \(fromTier.displayName) to \(toTier.displayName)"
        } else {
            return "Downgrade from \(fromTier.displayName) to \(toTier.displayName)"
        }
    }
}

// MARK: - Migration Step

/// Individual migration steps during tier transitions
public enum TierMigrationStep: String, Sendable, CaseIterable {
    // Identity tier steps
    case validateAuthentication = "validate_authentication"
    case syncNightscoutProfile = "sync_nightscout_profile"
    case clearSessionData = "clear_session_data"
    
    // CGM tier steps
    case requestBluetoothPermission = "request_bluetooth_permission"
    case configureCGMDevice = "configure_cgm_device"
    case validateCGMData = "validate_cgm_data"
    case disconnectCGM = "disconnect_cgm"
    case archiveCGMData = "archive_cgm_data"
    
    // AID tier steps
    case configurePumpDevice = "configure_pump_device"
    case validateAIDTraining = "validate_aid_training"
    case enableAIDMode = "enable_aid_mode"
    case disableAIDMode = "disable_aid_mode"
    case disconnectPump = "disconnect_pump"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .validateAuthentication: return "Verify Sign In"
        case .syncNightscoutProfile: return "Sync Profile"
        case .clearSessionData: return "Clear Session"
        case .requestBluetoothPermission: return "Enable Bluetooth"
        case .configureCGMDevice: return "Configure CGM"
        case .validateCGMData: return "Verify CGM Data"
        case .disconnectCGM: return "Disconnect CGM"
        case .archiveCGMData: return "Archive CGM Data"
        case .configurePumpDevice: return "Configure Pump"
        case .validateAIDTraining: return "Verify Training"
        case .enableAIDMode: return "Enable AID"
        case .disableAIDMode: return "Disable AID"
        case .disconnectPump: return "Disconnect Pump"
        }
    }
    
    /// Estimated duration in seconds
    public var estimatedDuration: TimeInterval {
        switch self {
        case .validateAuthentication: return 1
        case .syncNightscoutProfile: return 5
        case .clearSessionData: return 1
        case .requestBluetoothPermission: return 2
        case .configureCGMDevice: return 10
        case .validateCGMData: return 3
        case .disconnectCGM: return 2
        case .archiveCGMData: return 5
        case .configurePumpDevice: return 15
        case .validateAIDTraining: return 2
        case .enableAIDMode: return 3
        case .disableAIDMode: return 2
        case .disconnectPump: return 3
        }
    }
    
    /// Whether this step requires user interaction
    public var requiresInteraction: Bool {
        switch self {
        case .requestBluetoothPermission, .configureCGMDevice,
             .configurePumpDevice, .validateAIDTraining:
            return true
        default:
            return false
        }
    }
}

// MARK: - Transition State

/// Current state of a tier transition
public struct TierTransitionState: Sendable, Equatable {
    public let transition: TierTransition
    public let currentStepIndex: Int
    public let completedSteps: [TierMigrationStep]
    public let failedStep: TierMigrationStep?
    public let error: TierUpgradeError?
    public let startedAt: Date
    public let completedAt: Date?
    
    public init(
        transition: TierTransition,
        currentStepIndex: Int = 0,
        completedSteps: [TierMigrationStep] = [],
        failedStep: TierMigrationStep? = nil,
        error: TierUpgradeError? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.transition = transition
        self.currentStepIndex = currentStepIndex
        self.completedSteps = completedSteps
        self.failedStep = failedStep
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
    
    /// Current step being executed
    public var currentStep: TierMigrationStep? {
        guard currentStepIndex < transition.requiredSteps.count else { return nil }
        return transition.requiredSteps[currentStepIndex]
    }
    
    /// Progress as a fraction (0.0 to 1.0)
    public var progress: Double {
        guard !transition.requiredSteps.isEmpty else { return 1.0 }
        return Double(completedSteps.count) / Double(transition.requiredSteps.count)
    }
    
    /// Whether transition is complete
    public var isComplete: Bool {
        completedSteps.count == transition.requiredSteps.count && failedStep == nil
    }
    
    /// Whether transition failed
    public var hasFailed: Bool {
        failedStep != nil
    }
    
    /// Whether transition is in progress
    public var isInProgress: Bool {
        !isComplete && !hasFailed
    }
    
    /// Remaining steps
    public var remainingSteps: [TierMigrationStep] {
        Array(transition.requiredSteps.dropFirst(completedSteps.count))
    }
    
    /// Estimated remaining time in seconds
    public var estimatedRemainingTime: TimeInterval {
        remainingSteps.reduce(0) { $0 + $1.estimatedDuration }
    }
    
    /// Create state with next step completed
    public func withStepCompleted(_ step: TierMigrationStep) -> TierTransitionState {
        TierTransitionState(
            transition: transition,
            currentStepIndex: currentStepIndex + 1,
            completedSteps: completedSteps + [step],
            failedStep: nil,
            error: nil,
            startedAt: startedAt,
            completedAt: currentStepIndex + 1 >= transition.requiredSteps.count ? Date() : nil
        )
    }
    
    /// Create state with step failed
    public func withStepFailed(_ step: TierMigrationStep, error: TierUpgradeError) -> TierTransitionState {
        TierTransitionState(
            transition: transition,
            currentStepIndex: currentStepIndex,
            completedSteps: completedSteps,
            failedStep: step,
            error: error,
            startedAt: startedAt,
            completedAt: nil
        )
    }
}

// MARK: - Upgrade Error

/// Errors during tier upgrade
public enum TierUpgradeError: Error, Sendable, Equatable {
    case prerequisiteNotMet(Capability)
    case stepFailed(TierMigrationStep, String)
    case permissionDenied(String)
    case deviceNotFound(String)
    case validationFailed(String)
    case userCancelled
    case timeout(TierMigrationStep)
    case alreadyAtTier(AppTier)
    case invalidTransition(from: AppTier, to: AppTier)
    
    public var localizedDescription: String {
        switch self {
        case .prerequisiteNotMet(let capability):
            return "Missing prerequisite: \(capability.displayName)"
        case .stepFailed(let step, let reason):
            return "\(step.displayName) failed: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)"
        case .deviceNotFound(let device):
            return "Device not found: \(device)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .userCancelled:
            return "Upgrade cancelled"
        case .timeout(let step):
            return "\(step.displayName) timed out"
        case .alreadyAtTier(let tier):
            return "Already at \(tier.displayName)"
        case .invalidTransition(let from, let to):
            return "Cannot transition from \(from.displayName) to \(to.displayName)"
        }
    }
}

// MARK: - Tier Upgrade Coordinator Protocol

/// Protocol for tier upgrade coordination
public protocol TierUpgradeCoordinatorProtocol: Sendable {
    /// Check if upgrade is possible
    func canUpgrade(to tier: AppTier) async -> Bool
    
    /// Start tier upgrade
    func startUpgrade(to tier: AppTier) async throws -> TierTransitionState
    
    /// Execute next step in current transition
    func executeNextStep() async throws -> TierTransitionState
    
    /// Cancel current transition
    func cancelTransition() async
    
    /// Get current transition state
    func getCurrentState() async -> TierTransitionState?
    
    /// Retry failed step
    func retryFailedStep() async throws -> TierTransitionState
}

// MARK: - Live Tier Upgrade Coordinator

/// Live implementation of tier upgrade coordination
public actor LiveTierUpgradeCoordinator: TierUpgradeCoordinatorProtocol {
    private let capabilityDetector: CapabilityDetectorProtocol
    private let stepExecutor: TierStepExecutorProtocol
    private var currentState: TierTransitionState?
    
    public init(
        capabilityDetector: CapabilityDetectorProtocol,
        stepExecutor: TierStepExecutorProtocol? = nil
    ) {
        self.capabilityDetector = capabilityDetector
        self.stepExecutor = stepExecutor ?? DefaultTierStepExecutor()
    }
    
    public func canUpgrade(to tier: AppTier) async -> Bool {
        await capabilityDetector.canAchieveTier(tier)
    }
    
    public func startUpgrade(to tier: AppTier) async throws -> TierTransitionState {
        let currentTier = await capabilityDetector.detectCurrentTier()
        
        guard tier != currentTier else {
            throw TierUpgradeError.alreadyAtTier(tier)
        }
        
        let transition = TierTransition(from: currentTier, to: tier)
        
        guard !transition.requiredSteps.isEmpty else {
            throw TierUpgradeError.invalidTransition(from: currentTier, to: tier)
        }
        
        let state = TierTransitionState(transition: transition)
        self.currentState = state
        return state
    }
    
    public func executeNextStep() async throws -> TierTransitionState {
        guard var state = currentState else {
            throw TierUpgradeError.validationFailed("No active transition")
        }
        
        guard let step = state.currentStep else {
            throw TierUpgradeError.validationFailed("No more steps to execute")
        }
        
        do {
            try await stepExecutor.execute(step)
            state = state.withStepCompleted(step)
            currentState = state
            return state
        } catch let error as TierUpgradeError {
            state = state.withStepFailed(step, error: error)
            currentState = state
            throw error
        } catch {
            let upgradeError = TierUpgradeError.stepFailed(step, error.localizedDescription)
            state = state.withStepFailed(step, error: upgradeError)
            currentState = state
            throw upgradeError
        }
    }
    
    public func cancelTransition() async {
        currentState = nil
    }
    
    public func getCurrentState() async -> TierTransitionState? {
        currentState
    }
    
    public func retryFailedStep() async throws -> TierTransitionState {
        guard let state = currentState, state.hasFailed else {
            throw TierUpgradeError.validationFailed("No failed step to retry")
        }
        
        // Reset the failed step and retry
        currentState = TierTransitionState(
            transition: state.transition,
            currentStepIndex: state.currentStepIndex,
            completedSteps: state.completedSteps,
            failedStep: nil,
            error: nil,
            startedAt: state.startedAt,
            completedAt: nil
        )
        
        return try await executeNextStep()
    }
}

// MARK: - Mock Tier Upgrade Coordinator

/// Mock implementation for testing
public actor MockTierUpgradeCoordinator: TierUpgradeCoordinatorProtocol {
    public var currentTier: AppTier = .demo
    public var canUpgradeResult: Bool = true
    public var shouldFail: Bool = false
    public var failAtStep: TierMigrationStep? = nil
    
    private var currentState: TierTransitionState?
    public private(set) var upgradeCount = 0
    public private(set) var executeCount = 0
    
    public init() {}
    
    public func setCurrentTier(_ tier: AppTier) {
        self.currentTier = tier
    }
    
    public func setCanUpgrade(_ canUpgrade: Bool) {
        self.canUpgradeResult = canUpgrade
    }
    
    public func setShouldFail(_ shouldFail: Bool, atStep: TierMigrationStep? = nil) {
        self.shouldFail = shouldFail
        self.failAtStep = atStep
    }
    
    public func canUpgrade(to tier: AppTier) async -> Bool {
        canUpgradeResult && tier > currentTier
    }
    
    public func startUpgrade(to tier: AppTier) async throws -> TierTransitionState {
        upgradeCount += 1
        
        guard tier != currentTier else {
            throw TierUpgradeError.alreadyAtTier(tier)
        }
        
        let transition = TierTransition(from: currentTier, to: tier)
        let state = TierTransitionState(transition: transition)
        self.currentState = state
        return state
    }
    
    public func executeNextStep() async throws -> TierTransitionState {
        executeCount += 1
        
        guard var state = currentState else {
            throw TierUpgradeError.validationFailed("No active transition")
        }
        
        guard let step = state.currentStep else {
            throw TierUpgradeError.validationFailed("No more steps")
        }
        
        if shouldFail && (failAtStep == nil || failAtStep == step) {
            let error = TierUpgradeError.stepFailed(step, "Mock failure")
            state = state.withStepFailed(step, error: error)
            currentState = state
            throw error
        }
        
        state = state.withStepCompleted(step)
        currentState = state
        
        if state.isComplete {
            currentTier = state.transition.toTier
        }
        
        return state
    }
    
    public func cancelTransition() async {
        currentState = nil
    }
    
    public func getCurrentState() async -> TierTransitionState? {
        currentState
    }
    
    public func retryFailedStep() async throws -> TierTransitionState {
        guard let state = currentState, state.hasFailed else {
            throw TierUpgradeError.validationFailed("No failed step")
        }
        
        currentState = TierTransitionState(
            transition: state.transition,
            currentStepIndex: state.currentStepIndex,
            completedSteps: state.completedSteps,
            failedStep: nil,
            error: nil,
            startedAt: state.startedAt,
            completedAt: nil
        )
        
        shouldFail = false // Allow retry to succeed
        return try await executeNextStep()
    }
}

// MARK: - Step Executor Protocol

/// Protocol for executing individual migration steps
public protocol TierStepExecutorProtocol: Sendable {
    func execute(_ step: TierMigrationStep) async throws
}

/// Default step executor using UserDefaults
public struct DefaultTierStepExecutor: TierStepExecutorProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func execute(_ step: TierMigrationStep) async throws {
        // Simulate step execution with small delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        switch step {
        case .validateAuthentication:
            guard userDefaults.bool(forKey: "user_authenticated") else {
                throw TierUpgradeError.prerequisiteNotMet(.authentication)
            }
            
        case .syncNightscoutProfile:
            guard userDefaults.string(forKey: "nightscout_url") != nil else {
                throw TierUpgradeError.prerequisiteNotMet(.nightscoutConnection)
            }
            
        case .requestBluetoothPermission:
            guard userDefaults.bool(forKey: "bluetooth_authorized") else {
                throw TierUpgradeError.permissionDenied("Bluetooth")
            }
            
        case .configureCGMDevice:
            guard userDefaults.bool(forKey: "cgm_configured") else {
                throw TierUpgradeError.deviceNotFound("CGM")
            }
            
        case .validateCGMData:
            guard userDefaults.bool(forKey: "cgm_data_valid") else {
                throw TierUpgradeError.validationFailed("No valid CGM data")
            }
            
        case .configurePumpDevice:
            guard userDefaults.bool(forKey: "pump_configured") else {
                throw TierUpgradeError.deviceNotFound("Pump")
            }
            
        case .validateAIDTraining:
            guard userDefaults.bool(forKey: "aid_training_complete") else {
                throw TierUpgradeError.prerequisiteNotMet(.aidTrainingComplete)
            }
            
        case .enableAIDMode:
            userDefaults.set(true, forKey: "aid_mode_enabled")
            
        case .disableAIDMode:
            userDefaults.set(false, forKey: "aid_mode_enabled")
            
        case .clearSessionData, .disconnectCGM, .archiveCGMData, .disconnectPump:
            // Cleanup steps - always succeed
            break
        }
    }
}

// MARK: - Tier Upgrade Flow Helper

/// High-level helper for common tier upgrade scenarios
public struct TierUpgradeFlow {
    private let coordinator: TierUpgradeCoordinatorProtocol
    
    public init(coordinator: TierUpgradeCoordinatorProtocol) {
        self.coordinator = coordinator
    }
    
    /// Execute all steps to complete upgrade
    public func completeUpgrade(to tier: AppTier) async throws -> TierTransitionState {
        var state = try await coordinator.startUpgrade(to: tier)
        
        while state.isInProgress {
            state = try await coordinator.executeNextStep()
        }
        
        return state
    }
    
    /// Check if direct upgrade to tier is possible
    public func isUpgradePossible(to tier: AppTier) async -> Bool {
        await coordinator.canUpgrade(to: tier)
    }
}
