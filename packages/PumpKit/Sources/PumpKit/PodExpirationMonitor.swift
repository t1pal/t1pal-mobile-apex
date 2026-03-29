// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PodExpirationMonitor.swift
// PumpKit
//
// Monitors Omnipod pod lifetime and triggers expiration warnings.
// Pods have 80-hour lifetime with 8-hour grace period (88 hours total).
// Sends notifications at 8h/4h/1h before expiration and when expired.
//
// LIFE-PUMP-001: Omnipod 8-hour grace period
// LIFE-PUMP-002: Pod expiration notifications (8h/4h/1h/expired)
// LIFE-NOTIFY-002: Localized lifecycle notifications

import Foundation
import T1PalCore

// MARK: - Pod Lifetime

/// Pod lifetime configuration.
public enum PodLifetime: Sendable {
    /// Omnipod Eros (80 hours active + 8 hours grace)
    case eros
    /// Omnipod DASH (80 hours active + 8 hours grace)
    case dash
    /// Custom lifetime in hours
    case custom(activeHours: Int, graceHours: Int)
    
    /// Active lifetime in hours (before expiration warning).
    public var activeHours: Int {
        switch self {
        case .eros, .dash: return 80
        case .custom(let active, _): return active
        }
    }
    
    /// Grace period in hours (after official expiration).
    public var graceHours: Int {
        switch self {
        case .eros, .dash: return 8
        case .custom(_, let grace): return grace
        }
    }
    
    /// Total lifetime in hours (active + grace).
    public var totalHours: Int {
        activeHours + graceHours
    }
    
    /// Active lifetime in seconds.
    public var activeSeconds: TimeInterval {
        TimeInterval(activeHours) * 3600
    }
    
    /// Total lifetime in seconds.
    public var totalSeconds: TimeInterval {
        TimeInterval(totalHours) * 3600
    }
    
    /// Get lifetime for Omnipod variant.
    public static func forVariant(_ variant: OmnipodGeneration) -> PodLifetime {
        switch variant {
        case .eros: return .eros
        case .dash, .five: return .dash
        }
    }
}

// MARK: - Pod Session

/// Active pod session with expiration tracking.
public struct PodSession: Sendable, Codable, Equatable {
    public let podId: String
    public let variant: OmnipodGeneration
    public let activationDate: Date
    public let activeHours: Int
    public let graceHours: Int
    
    public init(
        podId: String,
        variant: OmnipodGeneration,
        activationDate: Date,
        activeHours: Int? = nil,
        graceHours: Int? = nil
    ) {
        self.podId = podId
        self.variant = variant
        self.activationDate = activationDate
        let lifetime = PodLifetime.forVariant(variant)
        self.activeHours = activeHours ?? lifetime.activeHours
        self.graceHours = graceHours ?? lifetime.graceHours
    }
    
    /// Official expiration date (end of active period).
    public var expirationDate: Date {
        activationDate.addingTimeInterval(TimeInterval(activeHours) * 3600)
    }
    
    /// Hard stop date (end of grace period).
    public var hardStopDate: Date {
        activationDate.addingTimeInterval(TimeInterval(activeHours + graceHours) * 3600)
    }
    
    /// Hours remaining until official expiration.
    public func hoursRemaining(at date: Date = Date()) -> Double {
        expirationDate.timeIntervalSince(date) / 3600.0
    }
    
    /// Hours remaining in grace period (negative = in grace, very negative = past grace).
    public func graceHoursRemaining(at date: Date = Date()) -> Double {
        hardStopDate.timeIntervalSince(date) / 3600.0
    }
    
    /// Whether pod has reached official expiration (but may still be in grace).
    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expirationDate
    }
    
    /// Whether pod has passed hard stop (grace period exhausted).
    public func isPastGrace(at date: Date = Date()) -> Bool {
        date >= hardStopDate
    }
    
    /// Whether pod is currently in grace period.
    public func isInGracePeriod(at date: Date = Date()) -> Bool {
        isExpired(at: date) && !isPastGrace(at: date)
    }
    
    /// Pod age in hours.
    public func ageHours(at date: Date = Date()) -> Double {
        date.timeIntervalSince(activationDate) / 3600.0
    }
    
    /// Progress through active lifetime (0.0 to 1.0+).
    public func progress(at date: Date = Date()) -> Double {
        let age = ageHours(at: date)
        return age / Double(activeHours)
    }
}

// MARK: - Pod Warning

/// Warning levels for pod expiration.
public enum PodWarning: Int, CaseIterable, Sendable, Codable, Comparable {
    case hours8 = 8
    case hours4 = 4
    case hours1 = 1
    case expired = 0
    case gracePeriod = -1  // In grace period
    case hardStop = -8     // Grace period exhausted
    
    /// Warning message.
    /// Trace: LIFE-NOTIFY-002
    public var message: String {
        switch self {
        case .hours8:
            return LifecycleL10n.Pod.expires8hMessage.localized(
                fallback: "Pod expires in 8 hours")
        case .hours4:
            return LifecycleL10n.Pod.expires4hMessage.localized(
                fallback: "Pod expires in 4 hours")
        case .hours1:
            return LifecycleL10n.Pod.expires1hMessage.localized(
                fallback: "Pod expires in 1 hour")
        case .expired:
            return LifecycleL10n.Pod.expiredMessage.localized(
                fallback: "Pod has expired — 8 hour grace period active")
        case .gracePeriod:
            return LifecycleL10n.Pod.gracePeriodMessage.localized(
                fallback: "Pod in grace period — change soon")
        case .hardStop:
            return LifecycleL10n.Pod.hardStopMessage.localized(
                fallback: "Pod grace period exhausted — insulin delivery stopped")
        }
    }
    
    /// Title for notification.
    /// Trace: LIFE-NOTIFY-002
    public var title: String {
        switch self {
        case .hours8:
            return LifecycleL10n.Pod.expires8hTitle.localized(
                fallback: "Pod Expiring Soon")
        case .hours4:
            return LifecycleL10n.Pod.expires4hTitle.localized(
                fallback: "Pod Expiring")
        case .hours1:
            return LifecycleL10n.Pod.expires1hTitle.localized(
                fallback: "Pod Expires in 1 Hour")
        case .expired:
            return LifecycleL10n.Pod.expiredTitle.localized(
                fallback: "Pod Expired — Grace Period")
        case .gracePeriod:
            return LifecycleL10n.Pod.gracePeriodTitle.localized(
                fallback: "Pod Grace Period")
        case .hardStop:
            return LifecycleL10n.Pod.hardStopTitle.localized(
                fallback: "Pod Delivery Stopped")
        }
    }
    
    /// Whether this warning is critical (requires immediate action).
    public var isCritical: Bool {
        switch self {
        case .hardStop: return true
        default: return false
        }
    }
    
    /// Whether this warning indicates grace period state.
    public var isGraceWarning: Bool {
        switch self {
        case .expired, .gracePeriod, .hardStop: return true
        default: return false
        }
    }
    
    /// Determine warning level for remaining hours.
    public static func forHoursRemaining(_ hours: Double, graceHoursRemaining: Double) -> PodWarning? {
        // Check grace period states first
        if graceHoursRemaining <= 0 {
            return .hardStop
        } else if hours <= 0 {
            // In grace period - use gracePeriod for middle of grace
            if graceHoursRemaining <= 4 {
                return .gracePeriod  // More urgent reminder in late grace
            }
            return .expired
        }
        
        // Pre-expiration warnings
        if hours <= 1 {
            return .hours1
        } else if hours <= 4 {
            return .hours4
        } else if hours <= 8 {
            return .hours8
        }
        
        return nil
    }
    
    public static func < (lhs: PodWarning, rhs: PodWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Warning State

/// Tracks which pod warnings have been sent.
public struct PodWarningState: Sendable, Codable, Equatable {
    public let podId: String
    public private(set) var sentWarnings: Set<Int>
    public private(set) var lastWarningDate: Date?
    
    public init(podId: String) {
        self.podId = podId
        self.sentWarnings = []
        self.lastWarningDate = nil
    }
    
    /// Check if warning was already sent.
    public func wasSent(_ warning: PodWarning) -> Bool {
        sentWarnings.contains(warning.rawValue)
    }
    
    /// Mark warning as sent.
    public mutating func markSent(_ warning: PodWarning, at date: Date = Date()) {
        sentWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Get next pending warning for remaining hours.
    public func nextPendingWarning(hoursRemaining: Double, graceHoursRemaining: Double) -> PodWarning? {
        // Find the appropriate warning level
        guard let appropriateWarning = PodWarning.forHoursRemaining(hoursRemaining, graceHoursRemaining: graceHoursRemaining) else {
            return nil
        }
        
        // Return it if not already sent
        if !wasSent(appropriateWarning) {
            return appropriateWarning
        }
        
        return nil
    }
}

// MARK: - Pod Notification

/// Notification content for pod expiration.
public struct PodExpirationNotification: Sendable, Equatable {
    public let session: PodSession
    public let warning: PodWarning
    public let hoursRemaining: Double
    public let graceHoursRemaining: Double
    public let timestamp: Date
    
    public init(
        session: PodSession,
        warning: PodWarning,
        hoursRemaining: Double,
        graceHoursRemaining: Double,
        timestamp: Date = Date()
    ) {
        self.session = session
        self.warning = warning
        self.hoursRemaining = hoursRemaining
        self.graceHoursRemaining = graceHoursRemaining
        self.timestamp = timestamp
    }
    
    /// Formatted time remaining string.
    public var timeRemainingString: String {
        if hoursRemaining > 0 {
            let hours = Int(hoursRemaining)
            let minutes = Int((hoursRemaining - Double(hours)) * 60)
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes) minutes"
            }
        } else if graceHoursRemaining > 0 {
            let hours = Int(graceHoursRemaining)
            let minutes = Int((graceHoursRemaining - Double(hours)) * 60)
            return "Grace: \(hours)h \(minutes)m"
        } else {
            return "Stopped"
        }
    }
}

// MARK: - Monitor Result

/// Result of checking pod expiration state.
public enum PodExpirationCheckResult: Sendable, Equatable {
    /// No session active.
    case noSession
    /// Session active, no warning needed.
    case healthy(hoursRemaining: Double)
    /// Warning threshold reached.
    case warning(PodExpirationNotification)
    /// Warning already sent for this threshold.
    case alreadySent(PodWarning)
    /// Pod is in grace period.
    case inGracePeriod(graceHoursRemaining: Double)
    /// Pod delivery has stopped (past grace).
    case stopped
}

// MARK: - Monitor Protocol

/// Protocol for pod expiration monitoring.
public protocol PodExpirationMonitoring: Sendable {
    /// Start tracking a new pod session.
    func startSession(_ session: PodSession) async
    /// End the current session.
    func endSession() async
    /// Get current session.
    func currentSession() async -> PodSession?
    /// Check for pending expiration warning.
    func checkExpiration(at date: Date) async -> PodExpirationCheckResult
    /// Mark warning as sent.
    func markWarningSent(_ warning: PodWarning) async
}

// MARK: - Monitor Actor

/// Actor that monitors pod expiration and triggers warnings.
public actor PodExpirationMonitor: PodExpirationMonitoring {
    private var session: PodSession?
    private var warningState: PodWarningState?
    private let persistence: PodStatePersistence?
    
    public init(persistence: PodStatePersistence? = nil) {
        self.persistence = persistence
    }
    
    /// Start tracking a new pod session.
    public func startSession(_ session: PodSession) async {
        self.session = session
        self.warningState = PodWarningState(podId: session.podId)
        
        if let persistence = persistence {
            await persistence.saveSession(session)
            await persistence.saveWarningState(warningState!)
        }
    }
    
    /// End the current session.
    public func endSession() async {
        session = nil
        warningState = nil
        
        if let persistence = persistence {
            await persistence.clearSession()
        }
    }
    
    /// Get current session.
    public func currentSession() async -> PodSession? {
        session
    }
    
    /// Get current warning state.
    public func currentWarningState() async -> PodWarningState? {
        warningState
    }
    
    /// Restore session from persistence.
    public func restoreSession() async {
        guard let persistence = persistence else { return }
        
        if let saved = await persistence.loadSession() {
            self.session = saved
        }
        
        if let session = session,
           let savedState = await persistence.loadWarningState(for: session.podId) {
            self.warningState = savedState
        }
    }
    
    /// Check for pending expiration warning.
    public func checkExpiration(at date: Date = Date()) async -> PodExpirationCheckResult {
        guard let session = session else {
            return .noSession
        }
        
        let hoursRemaining = session.hoursRemaining(at: date)
        let graceHoursRemaining = session.graceHoursRemaining(at: date)
        
        // Check if completely stopped
        if graceHoursRemaining <= 0 {
            return .stopped
        }
        
        // Check if in grace period (but not stopped)
        if hoursRemaining <= 0 {
            // Check for pending grace period warnings
            if let warningState = warningState,
               let pendingWarning = warningState.nextPendingWarning(
                   hoursRemaining: hoursRemaining,
                   graceHoursRemaining: graceHoursRemaining
               ) {
                let notification = PodExpirationNotification(
                    session: session,
                    warning: pendingWarning,
                    hoursRemaining: hoursRemaining,
                    graceHoursRemaining: graceHoursRemaining,
                    timestamp: date
                )
                return .warning(notification)
            }
            return .inGracePeriod(graceHoursRemaining: graceHoursRemaining)
        }
        
        // Check for pending warning
        guard let warningState = warningState else {
            return .healthy(hoursRemaining: hoursRemaining)
        }
        
        if let pendingWarning = warningState.nextPendingWarning(
            hoursRemaining: hoursRemaining,
            graceHoursRemaining: graceHoursRemaining
        ) {
            let notification = PodExpirationNotification(
                session: session,
                warning: pendingWarning,
                hoursRemaining: hoursRemaining,
                graceHoursRemaining: graceHoursRemaining,
                timestamp: date
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = PodWarning.forHoursRemaining(hoursRemaining, graceHoursRemaining: graceHoursRemaining),
           warningState.wasSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(hoursRemaining: hoursRemaining)
    }
    
    /// Mark warning as sent.
    public func markWarningSent(_ warning: PodWarning) async {
        warningState?.markSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Update session from pod state.
    public func updateFromPodState(
        podId: String,
        variant: OmnipodGeneration,
        activationDate: Date
    ) async {
        // Check if this is a new pod
        if let current = session, current.podId == podId {
            // Same pod, no update needed
            return
        }
        
        // New pod detected
        let newSession = PodSession(
            podId: podId,
            variant: variant,
            activationDate: activationDate
        )
        
        await startSession(newSession)
    }
}

// MARK: - Persistence Protocol

/// Protocol for persisting pod state.
public protocol PodStatePersistence: Sendable {
    func saveSession(_ session: PodSession) async
    func loadSession() async -> PodSession?
    func clearSession() async
    func saveWarningState(_ state: PodWarningState) async
    func loadWarningState(for podId: String) async -> PodWarningState?
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing.
public actor InMemoryPodPersistence: PodStatePersistence {
    private var session: PodSession?
    private var warningStates: [String: PodWarningState] = [:]
    
    public init() {}
    
    public func saveSession(_ session: PodSession) async {
        self.session = session
    }
    
    public func loadSession() async -> PodSession? {
        session
    }
    
    public func clearSession() async {
        session = nil
    }
    
    public func saveWarningState(_ state: PodWarningState) async {
        warningStates[state.podId] = state
    }
    
    public func loadWarningState(for podId: String) async -> PodWarningState? {
        warningStates[podId]
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults-based persistence for production use.
public actor UserDefaultsPodPersistence: PodStatePersistence {
    private let defaults: UserDefaults
    private let sessionKey = "t1pal.pod.session"
    private let warningStateKeyPrefix = "t1pal.pod.warning."
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveSession(_ session: PodSession) async {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
    
    public func loadSession() async -> PodSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(PodSession.self, from: data)
    }
    
    public func clearSession() async {
        defaults.removeObject(forKey: sessionKey)
    }
    
    public func saveWarningState(_ state: PodWarningState) async {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: warningStateKeyPrefix + state.podId)
        }
    }
    
    public func loadWarningState(for podId: String) async -> PodWarningState? {
        guard let data = defaults.data(forKey: warningStateKeyPrefix + podId) else { return nil }
        return try? JSONDecoder().decode(PodWarningState.self, from: data)
    }
}

// MARK: - Pod Expiration Scheduler

/// Schedules periodic pod expiration checks.
/// For pods, check more frequently than transmitters since lifetime is in hours, not days.
public actor PodExpirationScheduler {
    private let monitor: PodExpirationMonitor
    private let expirationHandler: @Sendable (PodExpirationNotification) async -> Void
    private let checkInterval: TimeInterval
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?
    
    public init(
        monitor: PodExpirationMonitor,
        checkInterval: TimeInterval = 3600, // 1 hour default (pod lifecycle is 80h + 8h grace)
        expirationHandler: @escaping @Sendable (PodExpirationNotification) async -> Void
    ) {
        self.monitor = monitor
        self.checkInterval = checkInterval
        self.expirationHandler = expirationHandler
    }
    
    /// Start periodic checking.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        task = Task {
            while !Task.isCancelled && isRunning {
                await performCheck()
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop periodic checking.
    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }
    
    /// Perform a single check.
    public func performCheck() async {
        let result = await monitor.checkExpiration()
        switch result {
        case .warning(let notification):
            await monitor.markWarningSent(notification.warning)
            await expirationHandler(notification)
        default:
            break
        }
    }
    
    /// Get whether scheduler is running.
    public var running: Bool {
        isRunning
    }
}

// MARK: - Pod Progress Display

/// Pod progress for UI display.
public struct PodProgress: Sendable {
    public let session: PodSession
    public let hoursRemaining: Double
    public let hoursElapsed: Double
    public let progress: Double
    public let warningLevel: PodWarning?
    public let isInGracePeriod: Bool
    public let graceHoursRemaining: Double
    
    public init(session: PodSession, at date: Date = Date()) {
        self.session = session
        self.hoursRemaining = session.hoursRemaining(at: date)
        self.hoursElapsed = session.ageHours(at: date)
        self.progress = session.progress(at: date)
        self.graceHoursRemaining = session.graceHoursRemaining(at: date)
        self.isInGracePeriod = session.isInGracePeriod(at: date)
        self.warningLevel = PodWarning.forHoursRemaining(hoursRemaining, graceHoursRemaining: graceHoursRemaining)
    }
    
    /// Formatted remaining time.
    public var remainingText: String {
        if hoursRemaining <= 0 {
            if graceHoursRemaining <= 0 {
                return "Stopped"
            } else {
                let hours = Int(graceHoursRemaining)
                let minutes = Int((graceHoursRemaining - Double(hours)) * 60)
                return "Grace: \(hours)h \(minutes)m"
            }
        } else if hoursRemaining < 1 {
            let minutes = Int(hoursRemaining * 60)
            return "\(minutes) minutes"
        } else {
            let hours = Int(hoursRemaining)
            let minutes = Int((hoursRemaining - Double(hours)) * 60)
            if hours >= 24 {
                let days = hours / 24
                let remainingHours = hours % 24
                return "\(days)d \(remainingHours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
    
    /// Status text for UI.
    public var statusText: String {
        if graceHoursRemaining <= 0 {
            return "Pod delivery stopped"
        } else if isInGracePeriod {
            return "Pod expired — grace period active"
        } else if let warning = warningLevel {
            return warning.message
        } else {
            return "Pod active"
        }
    }
}
