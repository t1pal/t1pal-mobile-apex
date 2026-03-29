// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EmergencySuspensionHandler.swift
// T1Pal Mobile
//
// Emergency suspension handling with state machine
// Requirements: PROD-AID-005, REQ-SAFETY-003
//
// Trace: PROD-AID-005, PRD-009

import Foundation
import T1PalCore

// MARK: - Suspension State

/// Current suspension state
public enum SuspensionState: String, Codable, Sendable, CaseIterable {
    case active = "active"
    case suspended = "suspended"
    case resuming = "resuming"
    case emergencySuspended = "emergency_suspended"
}

/// Reason for suspension
public enum SuspensionReason: String, Codable, Sendable, CaseIterable {
    case userRequested = "user_requested"
    case lowGlucose = "low_glucose"
    case predictedLow = "predicted_low"
    case sensorError = "sensor_error"
    case pumpError = "pump_error"
    case safetyLimit = "safety_limit"
    case appCrash = "app_crash"
    case maintenance = "maintenance"
    case unknown = "unknown"
}

// MARK: - Suspension Event

/// A suspension event record
public struct SuspensionEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let action: SuspensionAction
    public let reason: SuspensionReason
    public let source: SuspensionSource
    public let glucoseAtEvent: Double?
    public let iobAtEvent: Double?
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: SuspensionAction,
        reason: SuspensionReason,
        source: SuspensionSource = .user,
        glucoseAtEvent: Double? = nil,
        iobAtEvent: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.reason = reason
        self.source = source
        self.glucoseAtEvent = glucoseAtEvent
        self.iobAtEvent = iobAtEvent
        self.notes = notes
    }
}

/// Suspension action type
public enum SuspensionAction: String, Codable, Sendable {
    case suspend = "suspend"
    case resume = "resume"
    case extend = "extend"
}

/// Source of suspension action
public enum SuspensionSource: String, Codable, Sendable, CaseIterable {
    case user = "user"
    case algorithm = "algorithm"
    case safety = "safety"
    case automatic = "automatic"
}

// MARK: - Suspension Configuration

/// Configuration for suspension behavior
public struct SuspensionConfiguration: Sendable, Codable {
    /// Maximum suspension duration in seconds
    public let maxSuspensionDuration: TimeInterval
    
    /// Low glucose threshold for auto-suspend (mg/dL)
    public let lowGlucoseThreshold: Double
    
    /// Predicted low threshold for auto-suspend (mg/dL)
    public let predictedLowThreshold: Double
    
    /// Prediction time window in seconds
    public let predictionWindow: TimeInterval
    
    /// Whether to enable auto-suspend on low glucose
    public let autoSuspendOnLow: Bool
    
    /// Whether to enable auto-resume
    public let autoResumeEnabled: Bool
    
    /// Glucose threshold for auto-resume (mg/dL)
    public let autoResumeThreshold: Double
    
    /// Minimum suspension time before auto-resume (seconds)
    public let minimumSuspensionTime: TimeInterval
    
    /// Warning before suspension expires (seconds)
    public let expirationWarningTime: TimeInterval
    
    public init(
        maxSuspensionDuration: TimeInterval = 7200,  // 2 hours
        lowGlucoseThreshold: Double = 70,
        predictedLowThreshold: Double = 80,
        predictionWindow: TimeInterval = 1800,  // 30 minutes
        autoSuspendOnLow: Bool = true,
        autoResumeEnabled: Bool = false,
        autoResumeThreshold: Double = 100,
        minimumSuspensionTime: TimeInterval = 900,  // 15 minutes
        expirationWarningTime: TimeInterval = 600  // 10 minutes
    ) {
        self.maxSuspensionDuration = maxSuspensionDuration
        self.lowGlucoseThreshold = lowGlucoseThreshold
        self.predictedLowThreshold = predictedLowThreshold
        self.predictionWindow = predictionWindow
        self.autoSuspendOnLow = autoSuspendOnLow
        self.autoResumeEnabled = autoResumeEnabled
        self.autoResumeThreshold = autoResumeThreshold
        self.minimumSuspensionTime = minimumSuspensionTime
        self.expirationWarningTime = expirationWarningTime
    }
    
    /// Default safe configuration
    public static let `default` = SuspensionConfiguration()
    
    /// Conservative configuration (longer suspension, lower thresholds)
    public static let conservative = SuspensionConfiguration(
        maxSuspensionDuration: 14400,  // 4 hours
        lowGlucoseThreshold: 80,
        predictedLowThreshold: 90,
        autoSuspendOnLow: true,
        autoResumeEnabled: false
    )
    
    /// Aggressive configuration (auto-resume enabled)
    public static let aggressive = SuspensionConfiguration(
        maxSuspensionDuration: 3600,  // 1 hour
        lowGlucoseThreshold: 65,
        predictedLowThreshold: 75,
        autoSuspendOnLow: true,
        autoResumeEnabled: true,
        autoResumeThreshold: 90,
        minimumSuspensionTime: 600  // 10 minutes
    )
}

// MARK: - Suspension Status

/// Current suspension status
public struct SuspensionStatus: Sendable, Codable {
    public let state: SuspensionState
    public let suspendedAt: Date?
    public let reason: SuspensionReason?
    public let source: SuspensionSource?
    public let expectedResumeAt: Date?
    public let glucoseAtSuspend: Double?
    
    public init(
        state: SuspensionState,
        suspendedAt: Date? = nil,
        reason: SuspensionReason? = nil,
        source: SuspensionSource? = nil,
        expectedResumeAt: Date? = nil,
        glucoseAtSuspend: Double? = nil
    ) {
        self.state = state
        self.suspendedAt = suspendedAt
        self.reason = reason
        self.source = source
        self.expectedResumeAt = expectedResumeAt
        self.glucoseAtSuspend = glucoseAtSuspend
    }
    
    /// Whether currently suspended
    public var isSuspended: Bool {
        state == .suspended || state == .emergencySuspended
    }
    
    /// Time since suspension started
    public var suspensionDuration: TimeInterval? {
        guard let start = suspendedAt else { return nil }
        return Date().timeIntervalSince(start)
    }
    
    /// Time until expected resume
    public var timeUntilResume: TimeInterval? {
        guard let resume = expectedResumeAt else { return nil }
        return resume.timeIntervalSinceNow
    }
    
    /// Whether suspension is about to expire
    public func isNearExpiration(warningTime: TimeInterval) -> Bool {
        guard let remaining = timeUntilResume else { return false }
        return remaining > 0 && remaining <= warningTime
    }
    
    /// Active status (not suspended)
    public static let active = SuspensionStatus(state: .active)
}

// MARK: - Suspension History

/// History of suspension events
public struct SuspensionHistory: Sendable, Codable {
    public var events: [SuspensionEvent]
    
    /// Maximum events to keep
    public static let maxEvents = 500
    
    public init(events: [SuspensionEvent] = []) {
        self.events = events
    }
    
    /// Add an event
    public mutating func addEvent(_ event: SuspensionEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events = Array(events.prefix(Self.maxEvents))
        }
    }
    
    /// Get events from last N hours
    public func events(lastHours: Int) -> [SuspensionEvent] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        return events.filter { $0.timestamp >= cutoff }
    }
    
    /// Count suspensions in last N hours
    public func suspensionCount(lastHours: Int) -> Int {
        events(lastHours: lastHours)
            .filter { $0.action == .suspend }
            .count
    }
    
    /// Total time suspended in last N hours
    public func totalSuspensionTime(lastHours: Int) -> TimeInterval {
        let recent = events(lastHours: lastHours).sorted { $0.timestamp < $1.timestamp }
        
        var totalTime: TimeInterval = 0
        var lastSuspend: Date?
        
        for event in recent {
            switch event.action {
            case .suspend:
                lastSuspend = event.timestamp
            case .resume:
                if let start = lastSuspend {
                    totalTime += event.timestamp.timeIntervalSince(start)
                    lastSuspend = nil
                }
            case .extend:
                break
            }
        }
        
        // If still suspended, add time from last suspend to now
        if let start = lastSuspend {
            totalTime += Date().timeIntervalSince(start)
        }
        
        return totalTime
    }
}

// MARK: - Suspension Statistics

/// Statistics for suspension behavior
public struct SuspensionStatistics: Sendable {
    public let totalSuspensions: Int
    public let userSuspensions: Int
    public let automaticSuspensions: Int
    public let lowGlucoseSuspensions: Int
    public let totalSuspensionTime: TimeInterval
    public let averageSuspensionDuration: TimeInterval
    
    public init(
        totalSuspensions: Int,
        userSuspensions: Int,
        automaticSuspensions: Int,
        lowGlucoseSuspensions: Int,
        totalSuspensionTime: TimeInterval,
        averageSuspensionDuration: TimeInterval
    ) {
        self.totalSuspensions = totalSuspensions
        self.userSuspensions = userSuspensions
        self.automaticSuspensions = automaticSuspensions
        self.lowGlucoseSuspensions = lowGlucoseSuspensions
        self.totalSuspensionTime = totalSuspensionTime
        self.averageSuspensionDuration = averageSuspensionDuration
    }
    
    /// Calculate from history
    public static func from(history: SuspensionHistory, lastHours: Int = 24) -> SuspensionStatistics {
        let recent = history.events(lastHours: lastHours)
        let suspends = recent.filter { $0.action == .suspend }
        
        let total = suspends.count
        let user = suspends.filter { $0.source == .user }.count
        let automatic = suspends.filter { $0.source == .automatic || $0.source == .safety }.count
        let lowGlucose = suspends.filter { $0.reason == .lowGlucose || $0.reason == .predictedLow }.count
        
        let totalTime = history.totalSuspensionTime(lastHours: lastHours)
        let avgDuration = total > 0 ? totalTime / Double(total) : 0
        
        return SuspensionStatistics(
            totalSuspensions: total,
            userSuspensions: user,
            automaticSuspensions: automatic,
            lowGlucoseSuspensions: lowGlucose,
            totalSuspensionTime: totalTime,
            averageSuspensionDuration: avgDuration
        )
    }
}

// MARK: - Emergency Suspension Handler

/// Handles suspension state machine and emergency suspensions
public actor EmergencySuspensionHandler {
    
    // MARK: - State
    
    private var currentStatus: SuspensionStatus = .active
    private var history: SuspensionHistory = SuspensionHistory()
    private var configuration: SuspensionConfiguration
    
    // MARK: - Dependencies
    
    private var pumpController: (any PumpController)?
    
    // MARK: - Callbacks
    
    public var onStateChange: (@Sendable (SuspensionStatus) -> Void)?
    public var onSuspend: (@Sendable (SuspensionReason) -> Void)?
    public var onResume: (@Sendable () -> Void)?
    public var onExpirationWarning: (@Sendable (TimeInterval) -> Void)?
    
    // MARK: - Initialization
    
    public init(configuration: SuspensionConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Configure with pump controller
    public func configure(pumpController: any PumpController) {
        self.pumpController = pumpController
    }
    
    /// Update configuration
    public func updateConfiguration(_ config: SuspensionConfiguration) {
        self.configuration = config
    }
    
    // MARK: - Suspension Control
    
    /// Suspend insulin delivery
    public func suspend(
        reason: SuspensionReason = .userRequested,
        source: SuspensionSource = .user,
        duration: TimeInterval? = nil,
        glucoseAtEvent: Double? = nil,
        iobAtEvent: Double? = nil
    ) async throws {
        guard !currentStatus.isSuspended else {
            throw SuspensionError.alreadySuspended
        }
        
        let actualDuration = min(
            duration ?? configuration.maxSuspensionDuration,
            configuration.maxSuspensionDuration
        )
        
        // Send suspend command to pump
        if let pump = pumpController {
            try await pump.setTempBasal(rate: 0, duration: actualDuration)
        }
        
        // Update state
        let isEmergency = reason == .lowGlucose || reason == .predictedLow || reason == .safetyLimit
        
        currentStatus = SuspensionStatus(
            state: isEmergency ? .emergencySuspended : .suspended,
            suspendedAt: Date(),
            reason: reason,
            source: source,
            expectedResumeAt: Date().addingTimeInterval(actualDuration),
            glucoseAtSuspend: glucoseAtEvent
        )
        
        // Record event
        let event = SuspensionEvent(
            action: .suspend,
            reason: reason,
            source: source,
            glucoseAtEvent: glucoseAtEvent,
            iobAtEvent: iobAtEvent
        )
        history.addEvent(event)
        
        onStateChange?(currentStatus)
        onSuspend?(reason)
    }
    
    /// Resume insulin delivery
    public func resume(
        source: SuspensionSource = .user
    ) async throws {
        guard currentStatus.isSuspended else {
            throw SuspensionError.notSuspended
        }
        
        // Check minimum suspension time for automatic resume
        if source == .automatic {
            if let duration = currentStatus.suspensionDuration,
               duration < configuration.minimumSuspensionTime {
                throw SuspensionError.minimumTimeNotMet(
                    remaining: configuration.minimumSuspensionTime - duration
                )
            }
        }
        
        // Update state first (transitional)
        currentStatus = SuspensionStatus(state: .resuming)
        onStateChange?(currentStatus)
        
        // Send resume command to pump
        if let pump = pumpController {
            try await pump.cancelTempBasal()
        }
        
        // Update to active
        currentStatus = .active
        
        // Record event
        let event = SuspensionEvent(
            action: .resume,
            reason: history.events.first?.reason ?? .unknown,
            source: source
        )
        history.addEvent(event)
        
        onStateChange?(currentStatus)
        onResume?()
    }
    
    /// Extend suspension
    public func extendSuspension(additionalDuration: TimeInterval) async throws {
        guard currentStatus.isSuspended else {
            throw SuspensionError.notSuspended
        }
        
        guard let currentExpiry = currentStatus.expectedResumeAt else {
            throw SuspensionError.invalidState
        }
        
        let newExpiry = currentExpiry.addingTimeInterval(additionalDuration)
        let totalDuration = newExpiry.timeIntervalSinceNow
        
        // Check max duration
        if totalDuration > configuration.maxSuspensionDuration {
            throw SuspensionError.maxDurationExceeded
        }
        
        // Update pump
        if let pump = pumpController {
            try await pump.setTempBasal(rate: 0, duration: totalDuration)
        }
        
        // Update status
        currentStatus = SuspensionStatus(
            state: currentStatus.state,
            suspendedAt: currentStatus.suspendedAt,
            reason: currentStatus.reason,
            source: currentStatus.source,
            expectedResumeAt: newExpiry,
            glucoseAtSuspend: currentStatus.glucoseAtSuspend
        )
        
        // Record event
        let event = SuspensionEvent(
            action: .extend,
            reason: currentStatus.reason ?? .unknown,
            source: .user
        )
        history.addEvent(event)
        
        onStateChange?(currentStatus)
    }
    
    // MARK: - Auto-Suspension Logic
    
    /// Check if suspension is needed based on glucose
    public func checkForAutoSuspend(
        currentGlucose: Double,
        predictedGlucose: Double? = nil
    ) async throws -> Bool {
        guard configuration.autoSuspendOnLow else { return false }
        guard !currentStatus.isSuspended else { return false }
        
        // Check current low
        if currentGlucose <= configuration.lowGlucoseThreshold {
            try await suspend(
                reason: .lowGlucose,
                source: .automatic,
                glucoseAtEvent: currentGlucose
            )
            return true
        }
        
        // Check predicted low
        if let predicted = predictedGlucose,
           predicted <= configuration.predictedLowThreshold {
            try await suspend(
                reason: .predictedLow,
                source: .automatic,
                glucoseAtEvent: currentGlucose
            )
            return true
        }
        
        return false
    }
    
    /// Check if auto-resume is appropriate
    public func checkForAutoResume(currentGlucose: Double) async throws -> Bool {
        guard configuration.autoResumeEnabled else { return false }
        guard currentStatus.isSuspended else { return false }
        
        // Only auto-resume from automatic suspensions
        guard currentStatus.source == .automatic || currentStatus.source == .safety else {
            return false
        }
        
        // Check minimum time
        guard let duration = currentStatus.suspensionDuration,
              duration >= configuration.minimumSuspensionTime else {
            return false
        }
        
        // Check glucose is safe
        if currentGlucose >= configuration.autoResumeThreshold {
            try await resume(source: .automatic)
            return true
        }
        
        return false
    }
    
    /// Check suspension expiration
    public func checkExpiration() async throws {
        guard currentStatus.isSuspended else { return }
        
        if let remaining = currentStatus.timeUntilResume {
            if remaining <= 0 {
                // Expired - auto-resume
                try await resume(source: .automatic)
            } else if currentStatus.isNearExpiration(warningTime: configuration.expirationWarningTime) {
                // Warning
                onExpirationWarning?(remaining)
            }
        }
    }
    
    // MARK: - Status
    
    /// Get current status
    public func getStatus() -> SuspensionStatus {
        currentStatus
    }
    
    /// Get suspension history
    public func getHistory() -> SuspensionHistory {
        history
    }
    
    /// Get statistics
    public func getStatistics(lastHours: Int = 24) -> SuspensionStatistics {
        SuspensionStatistics.from(history: history, lastHours: lastHours)
    }
    
    /// Check if suspended
    public func isSuspended() -> Bool {
        currentStatus.isSuspended
    }
}

// MARK: - Suspension Errors

/// Errors for suspension operations
public enum SuspensionError: Error, LocalizedError {
    case alreadySuspended
    case notSuspended
    case maxDurationExceeded
    case minimumTimeNotMet(remaining: TimeInterval)
    case invalidState
    case pumpError(String)
    
    public var errorDescription: String? {
        switch self {
        case .alreadySuspended:
            return "Delivery is already suspended"
        case .notSuspended:
            return "Delivery is not currently suspended"
        case .maxDurationExceeded:
            return "Maximum suspension duration exceeded"
        case .minimumTimeNotMet(let remaining):
            return "Minimum suspension time not met (\(Int(remaining)) seconds remaining)"
        case .invalidState:
            return "Invalid suspension state"
        case .pumpError(let message):
            return "Pump error: \(message)"
        }
    }
}
