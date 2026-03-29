// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// LibreSensorLifecycleMonitor.swift
// CGMKit
//
// Monitors Libre sensor lifecycle including warmup and expiration.
// Libre sensors have a 1-hour warmup period before readings are available.
// Libre 2/3 sensors have a 14-day (336 hour) lifetime.
//
// LIFE-CGM-005: Libre 14-day sensor lifecycle
// LIFE-CGM-006: Libre sensor warmup tracking (1 hour)

import Foundation
import T1PalCore

// MARK: - Libre Sensor Configuration

/// Libre sensor configuration constants
public enum LibreSensorConfig: Sendable {
    /// Warmup duration in seconds (1 hour)
    public static let warmupDurationSeconds: TimeInterval = 3600
    
    /// Warmup duration in minutes
    public static let warmupDurationMinutes: Int = 60
    
    /// Sensor lifetime in days
    public static let lifetimeDays: Int = 14
    
    /// Sensor lifetime in hours
    public static let lifetimeHours: Int = 336
    
    /// Sensor lifetime in seconds
    public static let lifetimeSeconds: TimeInterval = 336 * 3600
    
    /// Warning thresholds in hours before expiration
    public static let expirationWarningHours: [Int] = [24, 6, 1]
}

// MARK: - Libre Sensor State

/// Current state of a Libre sensor
public enum LibreSensorState: String, Sendable, Codable, CaseIterable {
    /// Sensor just activated, waiting for warmup
    case warmingUp = "warming_up"
    
    /// Warmup complete, sensor providing readings
    case active = "active"
    
    /// Sensor approaching expiration (within 24 hours)
    case expiringSoon = "expiring_soon"
    
    /// Sensor has expired
    case expired = "expired"
    
    /// Sensor failed or encountered error
    case failed = "failed"
    
    /// Human-readable description
    public var displayText: String {
        switch self {
        case .warmingUp: return "Warming Up"
        case .active: return "Active"
        case .expiringSoon: return "Expiring Soon"
        case .expired: return "Expired"
        case .failed: return "Failed"
        }
    }
    
    /// Whether readings are available
    public var hasReadings: Bool {
        switch self {
        case .active, .expiringSoon: return true
        case .warmingUp, .expired, .failed: return false
        }
    }
    
    /// Color indicator for UI
    public var colorIndicator: String {
        switch self {
        case .warmingUp: return "🔵"  // Blue - warming
        case .active: return "🟢"     // Green - active
        case .expiringSoon: return "🟡"  // Yellow - warning
        case .expired: return "🔴"    // Red - expired
        case .failed: return "⚫"     // Black - failed
        }
    }
}

// MARK: - Libre Sensor Session

/// Represents an active Libre sensor session
public struct LibreSensorSession: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let sensorId: String
    public let sensorType: LibreSensorType
    public let activationDate: Date
    public let warmupEndDate: Date
    public let expirationDate: Date
    
    public init(
        id: UUID = UUID(),
        sensorId: String,
        sensorType: LibreSensorType = .libre2,
        activationDate: Date
    ) {
        self.id = id
        self.sensorId = sensorId
        self.sensorType = sensorType
        self.activationDate = activationDate
        self.warmupEndDate = activationDate.addingTimeInterval(LibreSensorConfig.warmupDurationSeconds)
        self.expirationDate = activationDate.addingTimeInterval(LibreSensorConfig.lifetimeSeconds)
    }
    
    // MARK: - Time Calculations
    
    /// Whether warmup is complete
    public func isWarmupComplete(at date: Date = Date()) -> Bool {
        date >= warmupEndDate
    }
    
    /// Time remaining in warmup (nil if complete)
    public func warmupRemaining(at date: Date = Date()) -> TimeInterval? {
        let remaining = warmupEndDate.timeIntervalSince(date)
        return remaining > 0 ? remaining : nil
    }
    
    /// Warmup remaining in minutes
    public func warmupRemainingMinutes(at date: Date = Date()) -> Int? {
        guard let remaining = warmupRemaining(at: date) else { return nil }
        return Int(ceil(remaining / 60))
    }
    
    /// Whether sensor has expired
    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expirationDate
    }
    
    /// Time remaining until expiration
    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        expirationDate.timeIntervalSince(date)
    }
    
    /// Hours remaining until expiration
    public func hoursRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 3600.0
    }
    
    /// Days remaining until expiration
    public func daysRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 86400.0
    }
    
    /// Sensor age in hours
    public func ageHours(at date: Date = Date()) -> Double {
        date.timeIntervalSince(activationDate) / 3600.0
    }
    
    /// Progress through sensor lifetime (0.0 to 1.0+)
    public func progress(at date: Date = Date()) -> Double {
        ageHours(at: date) / Double(LibreSensorConfig.lifetimeHours)
    }
    
    /// Warmup progress (0.0 to 1.0)
    public func warmupProgress(at date: Date = Date()) -> Double {
        if isWarmupComplete(at: date) { return 1.0 }
        let elapsed = date.timeIntervalSince(activationDate)
        return min(1.0, elapsed / LibreSensorConfig.warmupDurationSeconds)
    }
    
    /// Current state based on time
    public func state(at date: Date = Date()) -> LibreSensorState {
        if !isWarmupComplete(at: date) {
            return .warmingUp
        } else if isExpired(at: date) {
            return .expired
        } else if hoursRemaining(at: date) <= 24 {
            return .expiringSoon
        } else {
            return .active
        }
    }
    
    // MARK: - Formatted Strings
    
    /// Warmup remaining formatted for display
    public func warmupRemainingText(at date: Date = Date()) -> String? {
        guard let minutes = warmupRemainingMinutes(at: date) else { return nil }
        if minutes >= 60 {
            return "1 hour"
        } else {
            return "\(minutes) min\(minutes == 1 ? "" : "s")"
        }
    }
    
    /// Time remaining formatted for display
    public func timeRemainingText(at date: Date = Date()) -> String {
        let days = daysRemaining(at: date)
        if days < 0 {
            return "Expired"
        } else if days < 1 {
            let hours = Int(hoursRemaining(at: date))
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let d = Int(days)
            return "\(d) day\(d == 1 ? "" : "s")"
        }
    }
}

// MARK: - Libre Sensor Type (from Libre2Manager)

/// Extended Libre sensor type
public enum LibreSensorType: String, Sendable, Codable, CaseIterable {
    case libre2
    case libreUS14day
    case libre3
    
    /// Display name
    public var displayName: String {
        switch self {
        case .libre2: return "Libre 2"
        case .libreUS14day: return "Libre 14-day"
        case .libre3: return "Libre 3"
        }
    }
    
    /// Warmup duration in minutes
    public var warmupMinutes: Int {
        LibreSensorConfig.warmupDurationMinutes  // All Libre variants use 60 min
    }
    
    /// Lifetime in days
    public var lifetimeDays: Int {
        LibreSensorConfig.lifetimeDays  // All use 14 days
    }
}

// MARK: - Warmup Notification

/// Notification content for warmup events
public struct LibreWarmupNotification: Sendable, Equatable {
    public let session: LibreSensorSession
    public let event: WarmupEvent
    public let timestamp: Date
    
    public enum WarmupEvent: String, Sendable, CaseIterable {
        case started = "started"
        case halfwayComplete = "halfway"
        case almostComplete = "almost_complete"  // 5 minutes remaining
        case complete = "complete"
        
        public var title: String {
            switch self {
            case .started: return "Sensor Warming Up"
            case .halfwayComplete: return "Warmup Halfway"
            case .almostComplete: return "Warmup Almost Complete"
            case .complete: return "Sensor Ready"
            }
        }
        
        public func body(minutesRemaining: Int?) -> String {
            switch self {
            case .started:
                return "Your Libre sensor is warming up. Readings will be available in about 1 hour."
            case .halfwayComplete:
                return "Warmup is 50% complete. About 30 minutes remaining."
            case .almostComplete:
                return "Warmup is almost done. Readings will be available in about 5 minutes."
            case .complete:
                return "Your Libre sensor is ready. Glucose readings are now available."
            }
        }
    }
    
    public init(session: LibreSensorSession, event: WarmupEvent, timestamp: Date = Date()) {
        self.session = session
        self.event = event
        self.timestamp = timestamp
    }
    
    /// Convert to notification content
    public func toNotificationContent() -> GlucoseNotificationContent {
        GlucoseNotificationContent(
            type: .warmupComplete,
            title: event.title,
            body: event.body(minutesRemaining: session.warmupRemainingMinutes(at: timestamp)),
            timestamp: timestamp,
            userInfo: [
                "sensorId": session.sensorId,
                "sensorType": session.sensorType.rawValue,
                "event": event.rawValue
            ]
        )
    }
}

// MARK: - Warmup Warning State

/// Tracks which warmup notifications have been sent
public struct LibreWarmupState: Sendable, Codable, Equatable {
    public let sensorId: String
    public private(set) var sentEvents: Set<String>
    
    public init(sensorId: String) {
        self.sensorId = sensorId
        self.sentEvents = []
    }
    
    public func wasSent(_ event: LibreWarmupNotification.WarmupEvent) -> Bool {
        sentEvents.contains(event.rawValue)
    }
    
    public mutating func markSent(_ event: LibreWarmupNotification.WarmupEvent) {
        sentEvents.insert(event.rawValue)
    }
}

// MARK: - Lifecycle Check Result

/// Result of checking Libre sensor lifecycle
public enum LibreLifecycleCheckResult: Sendable, Equatable {
    /// No session active
    case noSession
    
    /// Still warming up
    case warmingUp(minutesRemaining: Int, warmupProgress: Double)
    
    /// Warmup event ready to notify
    case warmupEvent(LibreWarmupNotification)
    
    /// Sensor active and healthy
    case active(hoursRemaining: Double)
    
    /// Expiration warning needed
    case expirationWarning(SensorExpirationNotification)
    
    /// Sensor expired
    case expired
}

// MARK: - Libre Sensor Lifecycle Persistence

/// Protocol for persisting Libre sensor lifecycle state
public protocol LibreSensorLifecyclePersistence: Sendable {
    func saveSession(_ session: LibreSensorSession) async
    func loadSession() async -> LibreSensorSession?
    func clearSession() async
    
    func saveWarmupState(_ state: LibreWarmupState) async
    func loadWarmupState(for sensorId: String) async -> LibreWarmupState?
    
    func saveExpirationState(_ state: ExpirationWarningState) async
    func loadExpirationState(for sensorId: String) async -> ExpirationWarningState?
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing
public actor InMemoryLibreSensorLifecyclePersistence: LibreSensorLifecyclePersistence {
    private var session: LibreSensorSession?
    private var warmupStates: [String: LibreWarmupState] = [:]
    private var expirationStates: [String: ExpirationWarningState] = [:]
    
    public init() {}
    
    public func saveSession(_ session: LibreSensorSession) async {
        self.session = session
    }
    
    public func loadSession() async -> LibreSensorSession? {
        session
    }
    
    public func clearSession() async {
        session = nil
    }
    
    public func saveWarmupState(_ state: LibreWarmupState) async {
        warmupStates[state.sensorId] = state
    }
    
    public func loadWarmupState(for sensorId: String) async -> LibreWarmupState? {
        warmupStates[sensorId]
    }
    
    public func saveExpirationState(_ state: ExpirationWarningState) async {
        expirationStates[state.sensorId] = state
    }
    
    public func loadExpirationState(for sensorId: String) async -> ExpirationWarningState? {
        expirationStates[sensorId]
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults persistence for production
public actor UserDefaultsLibreSensorLifecyclePersistence: LibreSensorLifecyclePersistence {
    private let defaults: UserDefaults
    private let sessionKey = "com.t1pal.libre.sensor.session"
    private let warmupStatePrefix = "com.t1pal.libre.warmup."
    private let expirationStatePrefix = "com.t1pal.libre.expiration."
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveSession(_ session: LibreSensorSession) async {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
    
    public func loadSession() async -> LibreSensorSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(LibreSensorSession.self, from: data)
    }
    
    public func clearSession() async {
        defaults.removeObject(forKey: sessionKey)
    }
    
    public func saveWarmupState(_ state: LibreWarmupState) async {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: warmupStatePrefix + state.sensorId)
        }
    }
    
    public func loadWarmupState(for sensorId: String) async -> LibreWarmupState? {
        guard let data = defaults.data(forKey: warmupStatePrefix + sensorId) else { return nil }
        return try? JSONDecoder().decode(LibreWarmupState.self, from: data)
    }
    
    public func saveExpirationState(_ state: ExpirationWarningState) async {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: expirationStatePrefix + state.sensorId)
        }
    }
    
    public func loadExpirationState(for sensorId: String) async -> ExpirationWarningState? {
        guard let data = defaults.data(forKey: expirationStatePrefix + sensorId) else { return nil }
        return try? JSONDecoder().decode(ExpirationWarningState.self, from: data)
    }
}

// MARK: - Libre Sensor Lifecycle Monitor

/// Actor that monitors Libre sensor lifecycle including warmup and expiration
public actor LibreSensorLifecycleMonitor {
    private var session: LibreSensorSession?
    private var warmupState: LibreWarmupState?
    private var expirationState: ExpirationWarningState?
    private let persistence: LibreSensorLifecyclePersistence?
    
    public init(persistence: LibreSensorLifecyclePersistence? = nil) {
        self.persistence = persistence
    }
    
    // MARK: - Session Management
    
    /// Activate a new Libre sensor
    public func activateSensor(
        sensorId: String,
        sensorType: LibreSensorType = .libre2,
        activationDate: Date = Date()
    ) async {
        let newSession = LibreSensorSession(
            sensorId: sensorId,
            sensorType: sensorType,
            activationDate: activationDate
        )
        
        self.session = newSession
        self.warmupState = LibreWarmupState(sensorId: sensorId)
        self.expirationState = ExpirationWarningState(sensorId: sensorId)
        
        // Mark warmup started
        warmupState?.markSent(.started)
        
        if let persistence = persistence {
            await persistence.saveSession(newSession)
            await persistence.saveWarmupState(warmupState!)
            await persistence.saveExpirationState(expirationState!)
        }
    }
    
    /// End current sensor session
    public func endSession() async {
        session = nil
        warmupState = nil
        expirationState = nil
        
        if let persistence = persistence {
            await persistence.clearSession()
        }
    }
    
    /// Get current session
    public func currentSession() -> LibreSensorSession? {
        session
    }
    
    /// Get current sensor state
    public func currentState(at date: Date = Date()) -> LibreSensorState? {
        session?.state(at: date)
    }
    
    /// Restore session from persistence
    public func restoreSession() async {
        guard let persistence = persistence else { return }
        
        if let saved = await persistence.loadSession() {
            self.session = saved
            
            if let warmup = await persistence.loadWarmupState(for: saved.sensorId) {
                self.warmupState = warmup
            } else {
                self.warmupState = LibreWarmupState(sensorId: saved.sensorId)
            }
            
            if let expiration = await persistence.loadExpirationState(for: saved.sensorId) {
                self.expirationState = expiration
            } else {
                self.expirationState = ExpirationWarningState(sensorId: saved.sensorId)
            }
        }
    }
    
    // MARK: - Lifecycle Checks
    
    /// Check current lifecycle state and return any pending notifications
    public func checkLifecycle(at date: Date = Date()) async -> LibreLifecycleCheckResult {
        guard let session = session else {
            return .noSession
        }
        
        // Check warmup first
        if !session.isWarmupComplete(at: date) {
            let minutesRemaining = session.warmupRemainingMinutes(at: date) ?? 0
            let progress = session.warmupProgress(at: date)
            
            // Check for warmup milestones
            if let pendingEvent = checkWarmupMilestone(session: session, at: date) {
                return .warmupEvent(pendingEvent)
            }
            
            return .warmingUp(minutesRemaining: minutesRemaining, warmupProgress: progress)
        }
        
        // Check warmup complete notification
        if warmupState?.wasSent(.complete) == false {
            let notification = LibreWarmupNotification(
                session: session,
                event: .complete,
                timestamp: date
            )
            return .warmupEvent(notification)
        }
        
        // Check expiration
        if session.isExpired(at: date) {
            return .expired
        }
        
        // Check for expiration warnings
        let hoursRemaining = session.hoursRemaining(at: date)
        
        if let expirationState = expirationState,
           let pendingWarning = expirationState.nextPendingWarning(hoursRemaining: hoursRemaining) {
            // Convert to SensorSession for compatibility
            let sensorSession = SensorSession(
                sensorId: session.sensorId,
                cgmType: .libre2,
                startDate: session.activationDate,
                lifetimeHours: LibreSensorConfig.lifetimeHours
            )
            
            let notification = SensorExpirationNotification(
                session: sensorSession,
                warning: pendingWarning,
                hoursRemaining: hoursRemaining,
                timestamp: date
            )
            
            return .expirationWarning(notification)
        }
        
        return .active(hoursRemaining: hoursRemaining)
    }
    
    /// Check for warmup milestone notifications
    private func checkWarmupMilestone(session: LibreSensorSession, at date: Date) -> LibreWarmupNotification? {
        guard let warmupState = warmupState else { return nil }
        
        let progress = session.warmupProgress(at: date)
        let minutesRemaining = session.warmupRemainingMinutes(at: date) ?? 0
        
        // Check for halfway milestone (50%)
        if progress >= 0.5 && !warmupState.wasSent(.halfwayComplete) {
            return LibreWarmupNotification(session: session, event: .halfwayComplete, timestamp: date)
        }
        
        // Check for almost complete (5 minutes remaining)
        if minutesRemaining <= 5 && minutesRemaining > 0 && !warmupState.wasSent(.almostComplete) {
            return LibreWarmupNotification(session: session, event: .almostComplete, timestamp: date)
        }
        
        return nil
    }
    
    // MARK: - Event Acknowledgment
    
    /// Mark warmup event as sent
    public func markWarmupEventSent(_ event: LibreWarmupNotification.WarmupEvent) async {
        warmupState?.markSent(event)
        
        if let persistence = persistence, let warmupState = warmupState {
            await persistence.saveWarmupState(warmupState)
        }
    }
    
    /// Mark expiration warning as sent
    public func markExpirationWarningSent(_ warning: ExpirationWarning) async {
        expirationState?.markSent(warning)
        
        if let persistence = persistence, let expirationState = expirationState {
            await persistence.saveExpirationState(expirationState)
        }
    }
    
    // MARK: - Status Queries
    
    /// Get warmup remaining in minutes (nil if complete or no session)
    public func warmupRemainingMinutes(at date: Date = Date()) -> Int? {
        session?.warmupRemainingMinutes(at: date)
    }
    
    /// Get time remaining until expiration
    public func timeRemaining(at date: Date = Date()) -> TimeInterval? {
        guard let session = session else { return nil }
        let remaining = session.timeRemaining(at: date)
        return remaining > 0 ? remaining : nil
    }
    
    /// Get hours remaining until expiration
    public func hoursRemaining(at date: Date = Date()) -> Double? {
        session?.hoursRemaining(at: date)
    }
    
    /// Whether sensor is currently warming up
    public func isWarmingUp(at date: Date = Date()) -> Bool {
        guard let session = session else { return false }
        return !session.isWarmupComplete(at: date)
    }
    
    /// Whether sensor has expired
    public func isExpired(at date: Date = Date()) -> Bool {
        session?.isExpired(at: date) ?? false
    }
    
    /// Get sensor progress (0.0 to 1.0+)
    public func progress(at date: Date = Date()) -> Double? {
        session?.progress(at: date)
    }
}
