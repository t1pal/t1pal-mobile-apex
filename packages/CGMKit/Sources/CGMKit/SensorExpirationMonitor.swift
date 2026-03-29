// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SensorExpirationMonitor.swift
// CGMKit
//
// Monitors sensor lifetime and triggers expiration warnings.
// Sends notifications at 24h, 6h, 1h before expiration.
//
// PROD-CGM-004: Sensor expiration warning

import Foundation
import T1PalCore

// MARK: - Sensor Lifetime

/// Standard sensor lifetimes by CGM type.
public enum SensorLifetime: Sendable {
    /// 10-day Dexcom sensors
    case dexcom10Day
    /// 7-day Dexcom sensors
    case dexcom7Day
    /// 14-day Libre sensors
    case libre14Day
    /// 10-day Libre sensors
    case libre10Day
    /// Custom lifetime in hours
    case custom(hours: Int)
    
    /// Lifetime in hours.
    public var hours: Int {
        switch self {
        case .dexcom10Day: return 240  // 10 days
        case .dexcom7Day: return 168   // 7 days
        case .libre14Day: return 336   // 14 days
        case .libre10Day: return 240   // 10 days
        case .custom(let hours): return hours
        }
    }
    
    /// Lifetime in seconds.
    public var seconds: TimeInterval {
        TimeInterval(hours * 3600)
    }
    
    /// Get lifetime for CGM type.
    public static func forType(_ type: CGMType) -> SensorLifetime {
        switch type {
        case .dexcomG6: return .dexcom10Day
        case .dexcomG7: return .dexcom10Day
        case .libre2: return .libre14Day
        case .libre3: return .libre14Day
        case .miaomiao, .bubble: return .libre14Day  // Libre transmitters
        default: return .custom(hours: 168)  // Default 7 days
        }
    }
}

// MARK: - Sensor Session

/// Active sensor session with expiration tracking.
public struct SensorSession: Sendable, Codable, Equatable {
    public let sensorId: String
    public let cgmType: CGMType
    public let startDate: Date
    public let lifetimeHours: Int
    
    public init(
        sensorId: String,
        cgmType: CGMType,
        startDate: Date,
        lifetimeHours: Int? = nil
    ) {
        self.sensorId = sensorId
        self.cgmType = cgmType
        self.startDate = startDate
        self.lifetimeHours = lifetimeHours ?? SensorLifetime.forType(cgmType).hours
    }
    
    /// Expiration date based on start + lifetime.
    public var expirationDate: Date {
        startDate.addingTimeInterval(TimeInterval(lifetimeHours) * 3600)
    }
    
    /// Time remaining until expiration.
    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        expirationDate.timeIntervalSince(date)
    }
    
    /// Hours remaining until expiration.
    public func hoursRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 3600.0
    }
    
    /// Whether sensor has expired.
    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expirationDate
    }
    
    /// Age of sensor in hours.
    public func ageHours(at date: Date = Date()) -> Double {
        date.timeIntervalSince(startDate) / 3600.0
    }
    
    /// Progress through sensor lifetime (0.0 to 1.0+).
    public func progress(at date: Date = Date()) -> Double {
        ageHours(at: date) / Double(lifetimeHours)
    }
}

// MARK: - Expiration Warning

/// Expiration warning threshold.
public enum ExpirationWarning: Int, CaseIterable, Comparable, Sendable {
    case hours24 = 24
    case hours6 = 6
    case hours1 = 1
    case expired = 0
    
    /// Warning message.
    /// Trace: LIFE-NOTIFY-002
    public var message: String {
        switch self {
        case .hours24:
            return LifecycleL10n.Sensor.expiresMessage24h.localized(
                fallback: "Sensor expires in 24 hours")
        case .hours6:
            return LifecycleL10n.Sensor.expiresMessage6h.localized(
                fallback: "Sensor expires in 6 hours")
        case .hours1:
            return LifecycleL10n.Sensor.expiresMessage1h.localized(
                fallback: "Sensor expires in 1 hour")
        case .expired:
            return LifecycleL10n.Sensor.expiredMessage.localized(
                fallback: "Sensor has expired")
        }
    }
    
    /// Title for notification.
    /// Trace: LIFE-NOTIFY-002
    public var title: String {
        switch self {
        case .hours24:
            return LifecycleL10n.Sensor.expires24hTitle.localized(
                fallback: "Sensor Expiring Soon")
        case .hours6:
            return LifecycleL10n.Sensor.expires6hTitle.localized(
                fallback: "Sensor Expiring")
        case .hours1:
            return LifecycleL10n.Sensor.expires1hTitle.localized(
                fallback: "Sensor Expiring Soon")
        case .expired:
            return LifecycleL10n.Sensor.expiredTitle.localized(
                fallback: "Sensor Expired")
        }
    }
    
    /// Determine warning level for remaining hours.
    public static func forHoursRemaining(_ hours: Double) -> ExpirationWarning? {
        if hours <= 0 {
            return .expired
        } else if hours <= 1 {
            return .hours1
        } else if hours <= 6 {
            return .hours6
        } else if hours <= 24 {
            return .hours24
        } else {
            return nil
        }
    }
    
    public static func < (lhs: ExpirationWarning, rhs: ExpirationWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Warning State

/// Tracks which warnings have been sent.
public struct ExpirationWarningState: Sendable, Codable, Equatable {
    public let sensorId: String
    public private(set) var sentWarnings: Set<Int>
    public private(set) var lastWarningDate: Date?
    
    public init(sensorId: String) {
        self.sensorId = sensorId
        self.sentWarnings = []
        self.lastWarningDate = nil
    }
    
    /// Check if warning was already sent.
    public func wasSent(_ warning: ExpirationWarning) -> Bool {
        sentWarnings.contains(warning.rawValue)
    }
    
    /// Mark warning as sent.
    public mutating func markSent(_ warning: ExpirationWarning, at date: Date = Date()) {
        sentWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Get next pending warning for remaining hours.
    public func nextPendingWarning(hoursRemaining: Double) -> ExpirationWarning? {
        for warning in ExpirationWarning.allCases.sorted(by: >) {
            if hoursRemaining <= Double(warning.rawValue) && !wasSent(warning) {
                return warning
            }
        }
        return nil
    }
}

// MARK: - Expiration Notification

/// Notification content for sensor expiration.
public struct SensorExpirationNotification: Sendable, Equatable {
    public let session: SensorSession
    public let warning: ExpirationWarning
    public let hoursRemaining: Double
    public let timestamp: Date
    
    public init(
        session: SensorSession,
        warning: ExpirationWarning,
        hoursRemaining: Double,
        timestamp: Date = Date()
    ) {
        self.session = session
        self.warning = warning
        self.hoursRemaining = hoursRemaining
        self.timestamp = timestamp
    }
    
    /// Notification title.
    public var title: String {
        warning.title
    }
    
    /// Notification body.
    /// Trace: LIFE-NOTIFY-002
    public var body: String {
        let sensorName = session.cgmType.rawValue.replacingOccurrences(of: "dexcom", with: "Dexcom ")
            .replacingOccurrences(of: "libre", with: "Libre ")
        
        switch warning {
        case .expired:
            return LifecycleL10n.Sensor.expiredBody.localized(
                fallback: "\(sensorName) sensor has expired. Replace sensor.")
        case .hours1:
            return LifecycleL10n.Sensor.expires1hBody.localized(
                fallback: "\(sensorName) expires in about 1 hour. Prepare replacement.")
        case .hours6:
            return LifecycleL10n.Sensor.expires6hBody.localized(
                fallback: "\(sensorName) expires in about 6 hours.")
        case .hours24:
            return LifecycleL10n.Sensor.expires24hBody.localized(
                fallback: "\(sensorName) expires tomorrow. Plan replacement.")
        }
    }
    
    /// Convert to GlucoseNotificationContent.
    public func toNotificationContent() -> GlucoseNotificationContent {
        GlucoseNotificationContent(
            type: .sensorExpiring,
            title: title,
            body: body,
            timestamp: timestamp,
            userInfo: [
                "sensorId": session.sensorId,
                "cgmType": session.cgmType.rawValue,
                "warning": String(warning.rawValue),
                "hoursRemaining": String(format: "%.1f", hoursRemaining)
            ]
        )
    }
}

// MARK: - Monitor Result

/// Result of checking expiration state.
public enum ExpirationCheckResult: Sendable, Equatable {
    /// No session active.
    case noSession
    /// Session active, no warning needed.
    case healthy(hoursRemaining: Double)
    /// Warning threshold reached.
    case warning(SensorExpirationNotification)
    /// Warning already sent for this threshold.
    case alreadySent(ExpirationWarning)
    /// Sensor has expired.
    case expired
}

// MARK: - Monitor Protocol

/// Protocol for sensor expiration monitoring.
public protocol SensorExpirationMonitoring: Sendable {
    /// Start tracking a new sensor session.
    func startSession(_ session: SensorSession) async
    /// End the current session.
    func endSession() async
    /// Get current session.
    func currentSession() async -> SensorSession?
    /// Check for pending expiration warning.
    func checkExpiration(at date: Date) async -> ExpirationCheckResult
    /// Mark warning as sent.
    func markWarningSent(_ warning: ExpirationWarning) async
}

// MARK: - Monitor Actor

/// Actor that monitors sensor expiration and triggers warnings.
public actor SensorExpirationMonitor: SensorExpirationMonitoring {
    private var session: SensorSession?
    private var warningState: ExpirationWarningState?
    private let persistence: ExpirationStatePersistence?
    
    public init(persistence: ExpirationStatePersistence? = nil) {
        self.persistence = persistence
    }
    
    /// Start tracking a new sensor session.
    public func startSession(_ session: SensorSession) async {
        self.session = session
        self.warningState = ExpirationWarningState(sensorId: session.sensorId)
        
        // Persist state
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
    public func currentSession() async -> SensorSession? {
        session
    }
    
    /// Restore session from persistence.
    public func restoreSession() async {
        guard let persistence = persistence else { return }
        
        if let saved = await persistence.loadSession() {
            self.session = saved
        }
        
        if let session = session,
           let savedState = await persistence.loadWarningState(for: session.sensorId) {
            self.warningState = savedState
        }
    }
    
    /// Check for pending expiration warning.
    public func checkExpiration(at date: Date = Date()) async -> ExpirationCheckResult {
        guard let session = session else {
            return .noSession
        }
        
        let hoursRemaining = session.hoursRemaining(at: date)
        
        // Check if expired
        if hoursRemaining <= 0 {
            return .expired
        }
        
        // Check for pending warning
        guard let warningState = warningState else {
            return .healthy(hoursRemaining: hoursRemaining)
        }
        
        if let pendingWarning = warningState.nextPendingWarning(hoursRemaining: hoursRemaining) {
            let notification = SensorExpirationNotification(
                session: session,
                warning: pendingWarning,
                hoursRemaining: hoursRemaining,
                timestamp: date
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = ExpirationWarning.forHoursRemaining(hoursRemaining),
           warningState.wasSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(hoursRemaining: hoursRemaining)
    }
    
    /// Mark warning as sent.
    public func markWarningSent(_ warning: ExpirationWarning) async {
        warningState?.markSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Update session from CGM reading.
    public func updateFromReading(
        sensorId: String,
        cgmType: CGMType,
        sensorAgeHours: Double
    ) async {
        // Calculate start date from age
        let startDate = Date().addingTimeInterval(-sensorAgeHours * 3600)
        
        // Check if this is a new sensor
        if let current = session, current.sensorId == sensorId {
            // Same sensor, no update needed
            return
        }
        
        // New sensor detected
        let newSession = SensorSession(
            sensorId: sensorId,
            cgmType: cgmType,
            startDate: startDate
        )
        
        await startSession(newSession)
    }
}

// MARK: - Persistence Protocol

/// Protocol for persisting expiration state.
public protocol ExpirationStatePersistence: Sendable {
    func saveSession(_ session: SensorSession) async
    func loadSession() async -> SensorSession?
    func clearSession() async
    func saveWarningState(_ state: ExpirationWarningState) async
    func loadWarningState(for sensorId: String) async -> ExpirationWarningState?
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing.
public actor InMemoryExpirationPersistence: ExpirationStatePersistence {
    private var session: SensorSession?
    private var warningStates: [String: ExpirationWarningState] = [:]
    
    public init() {}
    
    public func saveSession(_ session: SensorSession) async {
        self.session = session
    }
    
    public func loadSession() async -> SensorSession? {
        session
    }
    
    public func clearSession() async {
        session = nil
    }
    
    public func saveWarningState(_ state: ExpirationWarningState) async {
        warningStates[state.sensorId] = state
    }
    
    public func loadWarningState(for sensorId: String) async -> ExpirationWarningState? {
        warningStates[sensorId]
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults-based persistence for production.
public actor UserDefaultsExpirationPersistence: ExpirationStatePersistence {
    private let defaults: UserDefaults
    private let sessionKey = "com.t1pal.sensor.session"
    private let warningPrefix = "com.t1pal.sensor.warning."
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveSession(_ session: SensorSession) async {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
    
    public func loadSession() async -> SensorSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(SensorSession.self, from: data)
    }
    
    public func clearSession() async {
        defaults.removeObject(forKey: sessionKey)
    }
    
    public func saveWarningState(_ state: ExpirationWarningState) async {
        let key = warningPrefix + state.sensorId
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
    
    public func loadWarningState(for sensorId: String) async -> ExpirationWarningState? {
        let key = warningPrefix + sensorId
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ExpirationWarningState.self, from: data)
    }
}

// MARK: - Expiration Scheduler

/// Schedules periodic expiration checks.
public actor ExpirationScheduler {
    private let monitor: SensorExpirationMonitor
    private let notificationHandler: @Sendable (SensorExpirationNotification) async -> Void
    private let checkInterval: TimeInterval
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?
    
    public init(
        monitor: SensorExpirationMonitor,
        checkInterval: TimeInterval = 3600, // 1 hour default
        notificationHandler: @escaping @Sendable (SensorExpirationNotification) async -> Void
    ) {
        self.monitor = monitor
        self.checkInterval = checkInterval
        self.notificationHandler = notificationHandler
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
            await notificationHandler(notification)
        default:
            break
        }
    }
}

// MARK: - Progress Display

/// Sensor progress for UI display.
public struct SensorProgress: Sendable {
    public let session: SensorSession
    public let hoursRemaining: Double
    public let hoursElapsed: Double
    public let progress: Double
    public let warningLevel: ExpirationWarning?
    
    public init(session: SensorSession, at date: Date = Date()) {
        self.session = session
        self.hoursRemaining = session.hoursRemaining(at: date)
        self.hoursElapsed = session.ageHours(at: date)
        self.progress = session.progress(at: date)
        self.warningLevel = ExpirationWarning.forHoursRemaining(hoursRemaining)
    }
    
    /// Formatted remaining time.
    /// Trace: LIFE-NOTIFY-002
    public var remainingText: String {
        if hoursRemaining <= 0 {
            return LifecycleL10n.Sensor.remainingExpired.localized(fallback: "Expired")
        } else if hoursRemaining < 1 {
            let minutes = Int(hoursRemaining * 60)
            let format = LifecycleL10n.Sensor.remainingMinutes.localized(fallback: "%d min")
            return String(format: format, minutes)
        } else if hoursRemaining < 24 {
            let hours = Int(hoursRemaining)
            let format = LifecycleL10n.Sensor.remainingHours.localized(fallback: "%d hr")
            return String(format: format, hours)
        } else {
            let days = hoursRemaining / 24
            let format = LifecycleL10n.Sensor.remainingDays.localized(fallback: "%.1f days")
            return String(format: format, days)
        }
    }
    
    /// Color category for progress display.
    public var colorCategory: String {
        switch warningLevel {
        case .expired: return "expired"
        case .hours1: return "critical"
        case .hours6: return "warning"
        case .hours24: return "attention"
        case nil: return "healthy"
        }
    }
}
