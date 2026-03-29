// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AIDTrainingModule.swift
// T1PalCore
//
// AID safety training and confirmation flow
// Backlog: ENHANCE-TIER3-001
// PRD: PRD-013-progressive-enhancement.md

import Foundation

// MARK: - Training Step

/// Individual training steps for AID safety
public enum TrainingStep: String, Sendable, CaseIterable, Codable {
    case welcome = "welcome"
    case howAIDWorks = "how_aid_works"
    case safetyLimits = "safety_limits"
    case whenToIntervene = "when_to_intervene"
    case emergencyProcedures = "emergency_procedures"
    case pumpFailure = "pump_failure"
    case cgmLoss = "cgm_loss"
    case exerciseGuidance = "exercise_guidance"
    case mealHandling = "meal_handling"
    case acknowledgment = "acknowledgment"
    
    /// Display title
    public var title: String {
        switch self {
        case .welcome: return "Welcome to AID"
        case .howAIDWorks: return "How AID Works"
        case .safetyLimits: return "Safety Limits"
        case .whenToIntervene: return "When to Intervene"
        case .emergencyProcedures: return "Emergency Procedures"
        case .pumpFailure: return "Pump Failure Response"
        case .cgmLoss: return "CGM Signal Loss"
        case .exerciseGuidance: return "Exercise & Activity"
        case .mealHandling: return "Meal Handling"
        case .acknowledgment: return "Safety Agreement"
        }
    }
    
    /// Detailed description
    public var description: String {
        switch self {
        case .welcome:
            return "Learn how automated insulin delivery can help manage your glucose levels."
        case .howAIDWorks:
            return "Understand the algorithm that adjusts your basal insulin automatically."
        case .safetyLimits:
            return "Review the safety limits that protect you from over-delivery."
        case .whenToIntervene:
            return "Know when manual intervention may be needed."
        case .emergencyProcedures:
            return "What to do in case of severe hypoglycemia or hyperglycemia."
        case .pumpFailure:
            return "Steps to take if your pump stops working."
        case .cgmLoss:
            return "How the system behaves when CGM data is unavailable."
        case .exerciseGuidance:
            return "Adjusting AID settings for physical activity."
        case .mealHandling:
            return "Best practices for meal announcements and boluses."
        case .acknowledgment:
            return "Confirm you understand the risks and responsibilities."
        }
    }
    
    /// SF Symbol for the step
    public var symbolName: String {
        switch self {
        case .welcome: return "hand.wave"
        case .howAIDWorks: return "gearshape.2"
        case .safetyLimits: return "shield.checkered"
        case .whenToIntervene: return "exclamationmark.triangle"
        case .emergencyProcedures: return "cross.circle"
        case .pumpFailure: return "xmark.octagon"
        case .cgmLoss: return "waveform.slash"
        case .exerciseGuidance: return "figure.run"
        case .mealHandling: return "fork.knife"
        case .acknowledgment: return "signature"
        }
    }
    
    /// Estimated reading time in seconds
    public var estimatedDuration: TimeInterval {
        switch self {
        case .welcome: return 60
        case .howAIDWorks: return 180
        case .safetyLimits: return 120
        case .whenToIntervene: return 150
        case .emergencyProcedures: return 180
        case .pumpFailure: return 120
        case .cgmLoss: return 90
        case .exerciseGuidance: return 120
        case .mealHandling: return 120
        case .acknowledgment: return 60
        }
    }
    
    /// Whether this step requires explicit acknowledgment
    public var requiresAcknowledgment: Bool {
        switch self {
        case .safetyLimits, .whenToIntervene, .emergencyProcedures, .acknowledgment:
            return true
        default:
            return false
        }
    }
    
    /// Steps that must be completed before this one
    public var prerequisites: [TrainingStep] {
        switch self {
        case .welcome:
            return []
        case .howAIDWorks:
            return [.welcome]
        case .safetyLimits:
            return [.howAIDWorks]
        case .whenToIntervene:
            return [.safetyLimits]
        case .emergencyProcedures:
            return [.whenToIntervene]
        case .pumpFailure:
            return [.emergencyProcedures]
        case .cgmLoss:
            return [.pumpFailure]
        case .exerciseGuidance:
            return [.cgmLoss]
        case .mealHandling:
            return [.exerciseGuidance]
        case .acknowledgment:
            return [.mealHandling]
        }
    }
}

// MARK: - Training Progress

/// Progress through AID training
public struct TrainingProgress: Sendable, Equatable, Codable {
    public let completedSteps: Set<TrainingStep>
    public let acknowledgedSteps: Set<TrainingStep>
    public let startedAt: Date?
    public let completedAt: Date?
    public let lastActivityAt: Date?
    
    public init(
        completedSteps: Set<TrainingStep> = [],
        acknowledgedSteps: Set<TrainingStep> = [],
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.completedSteps = completedSteps
        self.acknowledgedSteps = acknowledgedSteps
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastActivityAt = lastActivityAt
    }
    
    /// Progress as a fraction (0.0 to 1.0)
    public var progress: Double {
        Double(completedSteps.count) / Double(TrainingStep.allCases.count)
    }
    
    /// Whether all steps are complete
    public var isComplete: Bool {
        completedSteps.count == TrainingStep.allCases.count
    }
    
    /// Whether training has started
    public var hasStarted: Bool {
        startedAt != nil
    }
    
    /// Current step (first incomplete)
    public var currentStep: TrainingStep? {
        TrainingStep.allCases.first { !completedSteps.contains($0) }
    }
    
    /// Next required step
    public var nextStep: TrainingStep? {
        currentStep
    }
    
    /// Remaining steps
    public var remainingSteps: [TrainingStep] {
        TrainingStep.allCases.filter { !completedSteps.contains($0) }
    }
    
    /// Estimated remaining time
    public var estimatedRemainingTime: TimeInterval {
        remainingSteps.reduce(0) { $0 + $1.estimatedDuration }
    }
    
    /// Total estimated time
    public var totalEstimatedTime: TimeInterval {
        TrainingStep.allCases.reduce(0) { $0 + $1.estimatedDuration }
    }
    
    /// Create progress with step completed
    public func withStepCompleted(_ step: TrainingStep, at date: Date = Date()) -> TrainingProgress {
        var newCompleted = completedSteps
        newCompleted.insert(step)
        
        let isNowComplete = newCompleted.count == TrainingStep.allCases.count
        
        return TrainingProgress(
            completedSteps: newCompleted,
            acknowledgedSteps: acknowledgedSteps,
            startedAt: startedAt ?? date,
            completedAt: isNowComplete ? date : nil,
            lastActivityAt: date
        )
    }
    
    /// Create progress with step acknowledged
    public func withStepAcknowledged(_ step: TrainingStep, at date: Date = Date()) -> TrainingProgress {
        var newAcknowledged = acknowledgedSteps
        newAcknowledged.insert(step)
        
        return TrainingProgress(
            completedSteps: completedSteps,
            acknowledgedSteps: newAcknowledged,
            startedAt: startedAt,
            completedAt: completedAt,
            lastActivityAt: date
        )
    }
    
    /// Empty progress
    public static let empty = TrainingProgress()
}

// MARK: - Safety Acknowledgment

/// User's acknowledgment of AID safety requirements
public struct SafetyAcknowledgment: Sendable, Equatable, Codable {
    public let acknowledgedAt: Date
    public let version: String
    public let deviceId: String
    public let agreementText: String
    
    public init(
        acknowledgedAt: Date = Date(),
        version: String = "1.0",
        deviceId: String,
        agreementText: String = SafetyAcknowledgment.defaultAgreementText
    ) {
        self.acknowledgedAt = acknowledgedAt
        self.version = version
        self.deviceId = deviceId
        self.agreementText = agreementText
    }
    
    /// Default safety agreement text
    public static let defaultAgreementText = """
        I understand that:
        
        1. Automated Insulin Delivery (AID) is a tool to assist with glucose management, not a replacement for diabetes self-care.
        
        2. I must monitor my glucose levels and be prepared to take manual action when needed.
        
        3. AID has safety limits but cannot prevent all hypoglycemia or hyperglycemia events.
        
        4. I should know how to operate my pump and CGM manually if the automated system fails.
        
        5. I will consult my healthcare provider before making significant changes to my diabetes management.
        
        6. I accept responsibility for my diabetes management decisions while using AID.
        """
    
    /// Whether acknowledgment is still valid (within 1 year)
    public var isValid: Bool {
        let oneYear: TimeInterval = 365 * 24 * 60 * 60
        return Date().timeIntervalSince(acknowledgedAt) < oneYear
    }
    
    /// Days until expiration
    public var daysUntilExpiration: Int {
        let oneYear: TimeInterval = 365 * 24 * 60 * 60
        let expirationDate = acknowledgedAt.addingTimeInterval(oneYear)
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0)
    }
}

// MARK: - Training Error

/// Errors during AID training
public enum TrainingError: Error, Sendable, Equatable {
    case stepNotAvailable(TrainingStep)
    case prerequisiteNotMet(TrainingStep)
    case acknowledgmentRequired(TrainingStep)
    case alreadyCompleted
    case notStarted
    case expired
    
    public var localizedDescription: String {
        switch self {
        case .stepNotAvailable(let step):
            return "\(step.title) is not available"
        case .prerequisiteNotMet(let step):
            return "Complete \(step.title) first"
        case .acknowledgmentRequired(let step):
            return "Please acknowledge \(step.title)"
        case .alreadyCompleted:
            return "Training already completed"
        case .notStarted:
            return "Training has not started"
        case .expired:
            return "Training has expired, please refresh"
        }
    }
}

// MARK: - Training Manager Protocol

/// Protocol for AID training management
public protocol AIDTrainingManagerProtocol: Sendable {
    /// Get current training progress
    func getProgress() async -> TrainingProgress
    
    /// Start training
    func startTraining() async throws -> TrainingProgress
    
    /// Complete a training step
    func completeStep(_ step: TrainingStep) async throws -> TrainingProgress
    
    /// Acknowledge a step
    func acknowledgeStep(_ step: TrainingStep) async throws -> TrainingProgress
    
    /// Get safety acknowledgment
    func getAcknowledgment() async -> SafetyAcknowledgment?
    
    /// Submit final acknowledgment
    func submitAcknowledgment(deviceId: String) async throws -> SafetyAcknowledgment
    
    /// Reset training progress
    func resetTraining() async
    
    /// Check if training is complete and valid
    func isTrainingValid() async -> Bool
}

// MARK: - Live Training Manager

/// Live implementation of AID training management
public actor LiveAIDTrainingManager: AIDTrainingManagerProtocol {
    private let userDefaults: UserDefaults
    private var progress: TrainingProgress = .empty
    private var acknowledgment: SafetyAcknowledgment?
    
    private let progressKey = "aid_training_progress"
    private let acknowledgmentKey = "aid_safety_acknowledgment"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Defer actor-isolated state loading to Task (Swift 6 compatibility)
        Task { await self.loadPersistedState() }
    }
    
    private func loadPersistedState() {
        if let data = userDefaults.data(forKey: progressKey),
           let decoded = try? JSONDecoder().decode(TrainingProgress.self, from: data) {
            self.progress = decoded
        }
        
        if let data = userDefaults.data(forKey: acknowledgmentKey),
           let decoded = try? JSONDecoder().decode(SafetyAcknowledgment.self, from: data) {
            self.acknowledgment = decoded
        }
    }
    
    private func persistProgress() {
        if let data = try? JSONEncoder().encode(progress) {
            userDefaults.set(data, forKey: progressKey)
        }
    }
    
    private func persistAcknowledgment() {
        if let ack = acknowledgment, let data = try? JSONEncoder().encode(ack) {
            userDefaults.set(data, forKey: acknowledgmentKey)
        }
    }
    
    public func getProgress() async -> TrainingProgress {
        progress
    }
    
    public func startTraining() async throws -> TrainingProgress {
        if progress.isComplete {
            throw TrainingError.alreadyCompleted
        }
        
        if !progress.hasStarted {
            progress = TrainingProgress(startedAt: Date(), lastActivityAt: Date())
            persistProgress()
        }
        
        return progress
    }
    
    public func completeStep(_ step: TrainingStep) async throws -> TrainingProgress {
        // Check prerequisites
        for prereq in step.prerequisites {
            if !progress.completedSteps.contains(prereq) {
                throw TrainingError.prerequisiteNotMet(prereq)
            }
        }
        
        // Check acknowledgment if required
        if step.requiresAcknowledgment && !progress.acknowledgedSteps.contains(step) {
            throw TrainingError.acknowledgmentRequired(step)
        }
        
        progress = progress.withStepCompleted(step)
        persistProgress()
        
        return progress
    }
    
    public func acknowledgeStep(_ step: TrainingStep) async throws -> TrainingProgress {
        guard step.requiresAcknowledgment else {
            return progress
        }
        
        progress = progress.withStepAcknowledged(step)
        persistProgress()
        
        return progress
    }
    
    public func getAcknowledgment() async -> SafetyAcknowledgment? {
        acknowledgment
    }
    
    public func submitAcknowledgment(deviceId: String) async throws -> SafetyAcknowledgment {
        guard progress.isComplete else {
            throw TrainingError.notStarted
        }
        
        let ack = SafetyAcknowledgment(deviceId: deviceId)
        self.acknowledgment = ack
        persistAcknowledgment()
        
        // Mark training complete in UserDefaults for capability detection
        userDefaults.set(true, forKey: "aid_training_complete")
        userDefaults.set(true, forKey: "aid_safety_acknowledged")
        
        return ack
    }
    
    public func resetTraining() async {
        progress = .empty
        acknowledgment = nil
        userDefaults.removeObject(forKey: progressKey)
        userDefaults.removeObject(forKey: acknowledgmentKey)
        userDefaults.set(false, forKey: "aid_training_complete")
        userDefaults.set(false, forKey: "aid_safety_acknowledged")
    }
    
    public func isTrainingValid() async -> Bool {
        guard progress.isComplete else { return false }
        guard let ack = acknowledgment else { return false }
        return ack.isValid
    }
}

// MARK: - Mock Training Manager

/// Mock implementation for testing
public actor MockAIDTrainingManager: AIDTrainingManagerProtocol {
    public var progress: TrainingProgress = .empty
    public var acknowledgment: SafetyAcknowledgment?
    public var shouldFail: Bool = false
    public var failAtStep: TrainingStep?
    
    public private(set) var startCount = 0
    public private(set) var completeCount = 0
    public private(set) var acknowledgeCount = 0
    
    public init() {}
    
    /// Set failure mode for testing
    public func setShouldFail(_ fail: Bool, atStep: TrainingStep? = nil) {
        self.shouldFail = fail
        self.failAtStep = atStep
    }
    
    /// Configure mock for complete training
    public func setCompleted(deviceId: String = "test-device") {
        progress = TrainingProgress(
            completedSteps: Set(TrainingStep.allCases),
            acknowledgedSteps: Set(TrainingStep.allCases.filter { $0.requiresAcknowledgment }),
            startedAt: Date().addingTimeInterval(-3600),
            completedAt: Date(),
            lastActivityAt: Date()
        )
        acknowledgment = SafetyAcknowledgment(deviceId: deviceId)
    }
    
    public func getProgress() async -> TrainingProgress {
        progress
    }
    
    public func startTraining() async throws -> TrainingProgress {
        startCount += 1
        
        if shouldFail {
            throw TrainingError.alreadyCompleted
        }
        
        if !progress.hasStarted {
            progress = TrainingProgress(startedAt: Date(), lastActivityAt: Date())
        }
        
        return progress
    }
    
    public func completeStep(_ step: TrainingStep) async throws -> TrainingProgress {
        completeCount += 1
        
        if shouldFail || failAtStep == step {
            throw TrainingError.stepNotAvailable(step)
        }
        
        progress = progress.withStepCompleted(step)
        return progress
    }
    
    public func acknowledgeStep(_ step: TrainingStep) async throws -> TrainingProgress {
        acknowledgeCount += 1
        progress = progress.withStepAcknowledged(step)
        return progress
    }
    
    public func getAcknowledgment() async -> SafetyAcknowledgment? {
        acknowledgment
    }
    
    public func submitAcknowledgment(deviceId: String) async throws -> SafetyAcknowledgment {
        if !progress.isComplete {
            throw TrainingError.notStarted
        }
        
        let ack = SafetyAcknowledgment(deviceId: deviceId)
        acknowledgment = ack
        return ack
    }
    
    public func resetTraining() async {
        progress = .empty
        acknowledgment = nil
    }
    
    public func isTrainingValid() async -> Bool {
        progress.isComplete && (acknowledgment?.isValid ?? false)
    }
}

// MARK: - Training Flow Helper

/// High-level helper for common training scenarios
public struct AIDTrainingFlow {
    private let manager: AIDTrainingManagerProtocol
    
    public init(manager: AIDTrainingManagerProtocol) {
        self.manager = manager
    }
    
    /// Complete all training steps (for testing/demo)
    public func completeAllSteps() async throws -> TrainingProgress {
        _ = try await manager.startTraining()
        
        for step in TrainingStep.allCases {
            if step.requiresAcknowledgment {
                _ = try await manager.acknowledgeStep(step)
            }
            _ = try await manager.completeStep(step)
        }
        
        return await manager.getProgress()
    }
    
    /// Check if user can enable AID
    public func canEnableAID() async -> Bool {
        await manager.isTrainingValid()
    }
    
    /// Get training summary
    public func getSummary() async -> TrainingSummary {
        let progress = await manager.getProgress()
        let acknowledgment = await manager.getAcknowledgment()
        
        return TrainingSummary(
            progress: progress,
            acknowledgment: acknowledgment,
            canEnableAID: progress.isComplete && (acknowledgment?.isValid ?? false)
        )
    }
}

/// Summary of training status
public struct TrainingSummary: Sendable {
    public let progress: TrainingProgress
    public let acknowledgment: SafetyAcknowledgment?
    public let canEnableAID: Bool
    
    public var statusMessage: String {
        if canEnableAID {
            return "Training complete - AID ready"
        } else if progress.isComplete {
            return "Please submit safety acknowledgment"
        } else if progress.hasStarted {
            let percent = Int(progress.progress * 100)
            return "Training \(percent)% complete"
        } else {
            return "Training not started"
        }
    }
}
