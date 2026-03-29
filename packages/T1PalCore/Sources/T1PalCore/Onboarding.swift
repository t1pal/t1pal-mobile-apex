// SPDX-License-Identifier: AGPL-3.0-or-later
// Onboarding.swift
// T1PalCore
//
// Cross-app onboarding flow framework.
// Trace: APP-ONBOARD-001, APP-REVIEW-ONBOARDING-STRATEGY
//
// Provides reusable onboarding infrastructure for all T1Pal apps.

import Foundation

// MARK: - Onboarding Step Protocol

/// Protocol for onboarding steps
public protocol OnboardingStep: Identifiable, Sendable {
    /// Unique identifier for this step
    var id: String { get }
    
    /// Display title for the step
    var title: String { get }
    
    /// Optional subtitle or description
    var subtitle: String? { get }
    
    /// System image name for the step icon
    var iconName: String { get }
    
    /// Whether this step can be skipped
    var isSkippable: Bool { get }
    
    /// Whether this step is complete
    var isComplete: Bool { get }
    
    /// Validate the step (async for network checks, permissions, etc.)
    func validate() async -> OnboardingValidationResult
}

// MARK: - Validation Result

/// Result of step validation
public struct OnboardingValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let errorMessage: String?
    public let canProceed: Bool
    
    public init(isValid: Bool, errorMessage: String? = nil, canProceed: Bool? = nil) {
        self.isValid = isValid
        self.errorMessage = errorMessage
        self.canProceed = canProceed ?? isValid
    }
    
    public static let valid = OnboardingValidationResult(isValid: true)
    
    public static func invalid(_ message: String) -> OnboardingValidationResult {
        OnboardingValidationResult(isValid: false, errorMessage: message)
    }
    
    public static func warning(_ message: String) -> OnboardingValidationResult {
        OnboardingValidationResult(isValid: false, errorMessage: message, canProceed: true)
    }
}

// MARK: - Onboarding State

/// Current state of the onboarding flow
public enum OnboardingState: Sendable, Equatable {
    case notStarted
    case inProgress(stepIndex: Int)
    case validating
    case completed
    case skipped
}

// MARK: - Onboarding Coordinator

#if canImport(SwiftUI)
import SwiftUI

/// Manages onboarding flow state and navigation
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class OnboardingCoordinator<Step: OnboardingStep> {
    
    // MARK: - Published State
    
    public private(set) var steps: [Step]
    public private(set) var currentStepIndex: Int = 0
    public private(set) var state: OnboardingState = .notStarted
    public private(set) var validationResult: OnboardingValidationResult?
    public private(set) var isValidating: Bool = false
    
    /// Callback when onboarding completes
    public var onComplete: (() -> Void)?
    
    /// Callback when onboarding is skipped
    public var onSkip: (() -> Void)?
    
    // MARK: - Computed Properties
    
    /// Current step
    public var currentStep: Step? {
        guard currentStepIndex >= 0 && currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    
    /// Progress as fraction (0.0 to 1.0)
    public var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(steps.count)
    }
    
    /// Whether we can go back
    public var canGoBack: Bool {
        currentStepIndex > 0
    }
    
    /// Whether we can proceed (skip or next)
    public var canProceed: Bool {
        guard let step = currentStep else { return false }
        return step.isComplete || step.isSkippable || (validationResult?.canProceed ?? false)
    }
    
    /// Whether this is the last step
    public var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }
    
    /// Whether onboarding is complete
    public var isComplete: Bool {
        state == .completed || state == .skipped
    }
    
    // MARK: - Initialization
    
    public init(steps: [Step]) {
        self.steps = steps
        self.state = steps.isEmpty ? .completed : .notStarted
    }
    
    // MARK: - Navigation
    
    /// Start the onboarding flow
    public func start() {
        guard !steps.isEmpty else {
            state = .completed
            onComplete?()
            return
        }
        currentStepIndex = 0
        state = .inProgress(stepIndex: 0)
        validationResult = nil
    }
    
    /// Go to the next step
    public func next() async {
        guard let step = currentStep else { return }
        
        // Validate current step first
        isValidating = true
        state = .validating
        let result = await step.validate()
        validationResult = result
        isValidating = false
        
        guard result.canProceed else {
            state = .inProgress(stepIndex: currentStepIndex)
            return
        }
        
        if isLastStep {
            state = .completed
            onComplete?()
        } else {
            currentStepIndex += 1
            state = .inProgress(stepIndex: currentStepIndex)
            validationResult = nil
        }
    }
    
    /// Go to the previous step
    public func back() {
        guard canGoBack else { return }
        currentStepIndex -= 1
        state = .inProgress(stepIndex: currentStepIndex)
        validationResult = nil
    }
    
    /// Skip the current step (if allowed)
    public func skipCurrent() async {
        guard let step = currentStep, step.isSkippable else { return }
        
        if isLastStep {
            state = .completed
            onComplete?()
        } else {
            currentStepIndex += 1
            state = .inProgress(stepIndex: currentStepIndex)
            validationResult = nil
        }
    }
    
    /// Skip the entire onboarding
    public func skipAll() {
        state = .skipped
        onSkip?()
    }
    
    /// Go to a specific step by index
    public func goToStep(_ index: Int) {
        guard index >= 0 && index < steps.count else { return }
        currentStepIndex = index
        state = .inProgress(stepIndex: index)
        validationResult = nil
    }
    
    /// Reset the onboarding flow
    public func reset() {
        currentStepIndex = 0
        state = .notStarted
        validationResult = nil
    }
}

#endif

// MARK: - Simple Step Implementation

/// A simple concrete onboarding step for common use cases
public struct SimpleOnboardingStep: OnboardingStep {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let iconName: String
    public let isSkippable: Bool
    public var isComplete: Bool
    
    private let validator: @Sendable () async -> OnboardingValidationResult
    
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String = "circle",
        isSkippable: Bool = false,
        isComplete: Bool = false,
        validator: @escaping @Sendable () async -> OnboardingValidationResult = { .valid }
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.isSkippable = isSkippable
        self.isComplete = isComplete
        self.validator = validator
    }
    
    public func validate() async -> OnboardingValidationResult {
        await validator()
    }
}

// MARK: - Onboarding Persistence

/// Manages persistence of onboarding completion state
/// 
/// Thread Safety: UserDefaults is thread-safe per Apple documentation.
/// The struct only stores immutable references (defaults, prefix) and all
/// operations delegate to UserDefaults' internal synchronization.
public struct OnboardingPersistence: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    
    public init(defaults: UserDefaults = .standard, appIdentifier: String) {
        self.defaults = defaults
        self.prefix = "onboarding_\(appIdentifier)_"
    }
    
    /// Check if onboarding has been completed
    public func isComplete(flowId: String) -> Bool {
        defaults.bool(forKey: prefix + flowId + "_complete")
    }
    
    /// Mark onboarding as complete
    public func markComplete(flowId: String) {
        defaults.set(true, forKey: prefix + flowId + "_complete")
        defaults.set(Date(), forKey: prefix + flowId + "_date")
    }
    
    /// Get completion date
    public func completionDate(flowId: String) -> Date? {
        defaults.object(forKey: prefix + flowId + "_date") as? Date
    }
    
    /// Reset onboarding state
    public func reset(flowId: String) {
        defaults.removeObject(forKey: prefix + flowId + "_complete")
        defaults.removeObject(forKey: prefix + flowId + "_date")
    }
    
    /// Get the last completed step index
    public func lastCompletedStep(flowId: String) -> Int {
        defaults.integer(forKey: prefix + flowId + "_step")
    }
    
    /// Save current step progress
    public func saveProgress(flowId: String, stepIndex: Int) {
        defaults.set(stepIndex, forKey: prefix + flowId + "_step")
    }
}

// MARK: - Common Onboarding Steps

// MARK: - Unified Onboarding State Manager
// UX-ONBOARD-007: Unified onboarding state management across apps

/// App identifiers for onboarding state
public enum T1PalApp: String, Sendable, CaseIterable {
    case aid = "T1PalAID"
    case cgm = "T1PalCGM"
    case follower = "T1PalFollower"
    case research = "T1PalResearch"
    case demo = "T1PalDemo"
}

#if canImport(Observation)
import Observation

/// Unified onboarding state manager for all T1Pal apps
/// Provides consistent completion tracking with migration support for legacy keys
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class OnboardingStateManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = OnboardingStateManager()
    
    // MARK: - Private State
    
    private let defaults: UserDefaults
    private let keyPrefix = "t1pal_onboarding_"
    
    /// Legacy keys to migrate from
    private let legacyKeys: [T1PalApp: String] = [
        .follower: "hasCompletedOnboarding",
        .cgm: "cgm_onboarding_complete",
        .aid: "aid_onboarding_complete"
    ]
    
    // MARK: - Observable State
    
    public private(set) var completionState: [T1PalApp: Bool] = [:]
    
    // MARK: - Initialization
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadState()
        migrateLegacyKeys()
    }
    
    // MARK: - Public API
    
    /// Check if onboarding is complete for an app
    public func isComplete(for app: T1PalApp) -> Bool {
        completionState[app] ?? false
    }
    
    /// Mark onboarding as complete for an app
    public func markComplete(for app: T1PalApp) {
        completionState[app] = true
        defaults.set(true, forKey: key(for: app, suffix: "complete"))
        defaults.set(Date(), forKey: key(for: app, suffix: "date"))
    }
    
    /// Reset onboarding state for an app
    public func reset(for app: T1PalApp) {
        completionState[app] = false
        defaults.removeObject(forKey: key(for: app, suffix: "complete"))
        defaults.removeObject(forKey: key(for: app, suffix: "date"))
        defaults.removeObject(forKey: key(for: app, suffix: "step"))
    }
    
    /// Get completion date for an app
    public func completionDate(for app: T1PalApp) -> Date? {
        defaults.object(forKey: key(for: app, suffix: "date")) as? Date
    }
    
    /// Check if this is the first launch (no onboarding attempted)
    public func isFirstLaunch(for app: T1PalApp) -> Bool {
        !defaults.bool(forKey: key(for: app, suffix: "launched"))
    }
    
    /// Mark that the app has been launched
    public func markLaunched(for app: T1PalApp) {
        defaults.set(true, forKey: key(for: app, suffix: "launched"))
    }
    
    /// Get the current onboarding step for an app
    public func currentStep(for app: T1PalApp) -> Int {
        defaults.integer(forKey: key(for: app, suffix: "step"))
    }
    
    /// Save current step progress
    public func saveStep(_ step: Int, for app: T1PalApp) {
        defaults.set(step, forKey: key(for: app, suffix: "step"))
    }
    
    /// Check if any app has completed onboarding
    public var hasAnyAppCompleted: Bool {
        completionState.values.contains(true)
    }
    
    // MARK: - Private Helpers
    
    private func key(for app: T1PalApp, suffix: String) -> String {
        "\(keyPrefix)\(app.rawValue)_\(suffix)"
    }
    
    private func loadState() {
        for app in T1PalApp.allCases {
            completionState[app] = defaults.bool(forKey: key(for: app, suffix: "complete"))
        }
    }
    
    private func migrateLegacyKeys() {
        for (app, legacyKey) in legacyKeys {
            if defaults.bool(forKey: legacyKey) && !isComplete(for: app) {
                // Migrate from legacy key
                completionState[app] = true
                defaults.set(true, forKey: key(for: app, suffix: "complete"))
                // Don't remove legacy key to maintain backward compatibility
            }
        }
    }
}
#endif

/// Pre-defined common onboarding step types
public enum CommonOnboardingStepType: String, Sendable, CaseIterable {
    case welcome = "welcome"
    case permissions = "permissions"
    case healthKit = "healthkit"
    case notifications = "notifications"
    case bluetooth = "bluetooth"
    case nightscoutSetup = "nightscout"
    case cgmSetup = "cgm"
    case pumpSetup = "pump"
    case algorithmSetup = "algorithm"
    case safetyReview = "safety"
    case complete = "complete"
    
    public var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .healthKit: return "HealthKit"
        case .notifications: return "Notifications"
        case .bluetooth: return "Bluetooth"
        case .nightscoutSetup: return "Nightscout"
        case .cgmSetup: return "CGM Setup"
        case .pumpSetup: return "Pump Setup"
        case .algorithmSetup: return "Algorithm"
        case .safetyReview: return "Safety Review"
        case .complete: return "Complete"
        }
    }
    
    public var iconName: String {
        switch self {
        case .welcome: return "hand.wave"
        case .permissions: return "shield.checkered"
        case .healthKit: return "heart.fill"
        case .notifications: return "bell.fill"
        case .bluetooth: return "bluetooth"
        case .nightscoutSetup: return "cloud.fill"
        case .cgmSetup: return "waveform.path.ecg"
        case .pumpSetup: return "cross.vial.fill"
        case .algorithmSetup: return "function"
        case .safetyReview: return "exclamationmark.shield.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}
