// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// TransmitterExpirationMonitor.swift
// CGMKit
//
// Monitors transmitter lifetime and triggers expiration warnings.
// Sends notifications at 14d, 7d, 3d, 1d before 90-day expiration.
//
// LIFE-CGM-001: Transmitter 90-day lifecycle tracking
// LIFE-CGM-002: Transmitter activation date persistence
// LIFE-CGM-003: Transmitter replacement warnings
// LIFE-CGM-004: Battery low notification

import Foundation
import T1PalCore

// MARK: - Transmitter Lifetime

/// Standard transmitter lifetimes by CGM type.
public enum TransmitterLifetime: Sendable {
    /// Dexcom G6 transmitter (90 days)
    case dexcomG6
    /// Dexcom G7 (integrated, same as sensor session — 10 days)
    case dexcomG7
    /// Custom lifetime in days
    case custom(days: Int)
    
    /// Lifetime in days.
    public var days: Int {
        switch self {
        case .dexcomG6: return 90    // G6Constants.transmitterLifeDays
        case .dexcomG7: return 10    // G7 is integrated, no separate transmitter
        case .custom(let days): return days
        }
    }
    
    /// Lifetime in hours.
    public var hours: Int {
        days * 24
    }
    
    /// Lifetime in seconds.
    public var seconds: TimeInterval {
        TimeInterval(days) * 86400
    }
    
    /// Get lifetime for CGM type.
    public static func forType(_ type: CGMType) -> TransmitterLifetime {
        switch type {
        case .dexcomG6: return .dexcomG6
        case .dexcomG7: return .dexcomG7  // Integrated transmitter
        default: return .custom(days: 90)  // Default 90 days
        }
    }
    
    /// Whether this CGM type has a separate transmitter.
    public static func hasSeparateTransmitter(_ type: CGMType) -> Bool {
        switch type {
        case .dexcomG6: return true
        case .dexcomG7: return false  // Integrated
        case .libre2, .libre3: return false  // No transmitter
        case .miaomiao, .bubble: return true  // Third-party transmitters
        default: return false
        }
    }
}

// MARK: - Transmitter Session

/// Active transmitter session with expiration tracking.
public struct TransmitterSession: Sendable, Codable, Equatable {
    public let transmitterId: String
    public let cgmType: CGMType
    public let activationDate: Date
    public let lifetimeDays: Int
    
    public init(
        transmitterId: String,
        cgmType: CGMType,
        activationDate: Date,
        lifetimeDays: Int? = nil
    ) {
        self.transmitterId = transmitterId
        self.cgmType = cgmType
        self.activationDate = activationDate
        self.lifetimeDays = lifetimeDays ?? TransmitterLifetime.forType(cgmType).days
    }
    
    /// Expiration date based on activation + lifetime.
    public var expirationDate: Date {
        activationDate.addingTimeInterval(TimeInterval(lifetimeDays) * 86400)
    }
    
    /// Time remaining until expiration.
    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        expirationDate.timeIntervalSince(date)
    }
    
    /// Days remaining until expiration.
    public func daysRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 86400.0
    }
    
    /// Hours remaining until expiration.
    public func hoursRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 3600.0
    }
    
    /// Whether transmitter has expired.
    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expirationDate
    }
    
    /// Age of transmitter in days.
    public func ageDays(at date: Date = Date()) -> Double {
        date.timeIntervalSince(activationDate) / 86400.0
    }
    
    /// Progress through transmitter lifetime (0.0 to 1.0+).
    public func progress(at date: Date = Date()) -> Double {
        ageDays(at: date) / Double(lifetimeDays)
    }
}

// MARK: - Transmitter Warning

/// Transmitter expiration warning threshold (in days).
public enum TransmitterWarning: Int, CaseIterable, Comparable, Sendable {
    case days14 = 14
    case days7 = 7
    case days3 = 3
    case days1 = 1
    case expired = 0
    
    /// Warning message.
    /// Trace: LIFE-NOTIFY-002
    public var message: String {
        switch self {
        case .days14:
            return LifecycleL10n.Transmitter.expires14dMessage.localized(
                fallback: "Transmitter expires in 2 weeks")
        case .days7:
            return LifecycleL10n.Transmitter.expires7dMessage.localized(
                fallback: "Transmitter expires in 1 week")
        case .days3:
            return LifecycleL10n.Transmitter.expires3dMessage.localized(
                fallback: "Transmitter expires in 3 days")
        case .days1:
            return LifecycleL10n.Transmitter.expires1dMessage.localized(
                fallback: "Transmitter expires tomorrow")
        case .expired:
            return LifecycleL10n.Transmitter.expiredMessage.localized(
                fallback: "Transmitter has expired")
        }
    }
    
    /// Title for notification.
    /// Trace: LIFE-NOTIFY-002
    public var title: String {
        switch self {
        case .days14:
            return LifecycleL10n.Transmitter.expires14dTitle.localized(
                fallback: "Transmitter Expiring Soon")
        case .days7:
            return LifecycleL10n.Transmitter.expires7dTitle.localized(
                fallback: "Transmitter Expiring")
        case .days3:
            return LifecycleL10n.Transmitter.expires3dTitle.localized(
                fallback: "Transmitter Replacement Needed")
        case .days1:
            return LifecycleL10n.Transmitter.expires1dTitle.localized(
                fallback: "Transmitter Expires Tomorrow")
        case .expired:
            return LifecycleL10n.Transmitter.expiredTitle.localized(
                fallback: "Transmitter Expired")
        }
    }
    
    /// Determine warning level for remaining days.
    public static func forDaysRemaining(_ days: Double) -> TransmitterWarning? {
        if days <= 0 {
            return .expired
        } else if days <= 1 {
            return .days1
        } else if days <= 3 {
            return .days3
        } else if days <= 7 {
            return .days7
        } else if days <= 14 {
            return .days14
        } else {
            return nil
        }
    }
    
    public static func < (lhs: TransmitterWarning, rhs: TransmitterWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Warning State

/// Tracks which transmitter warnings have been sent.
public struct TransmitterWarningState: Sendable, Codable, Equatable {
    public let transmitterId: String
    public private(set) var sentWarnings: Set<Int>
    public private(set) var lastWarningDate: Date?
    public private(set) var batteryLowSent: Bool
    
    public init(transmitterId: String) {
        self.transmitterId = transmitterId
        self.sentWarnings = []
        self.lastWarningDate = nil
        self.batteryLowSent = false
    }
    
    /// Check if warning was already sent.
    public func wasSent(_ warning: TransmitterWarning) -> Bool {
        sentWarnings.contains(warning.rawValue)
    }
    
    /// Mark warning as sent.
    public mutating func markSent(_ warning: TransmitterWarning, at date: Date = Date()) {
        sentWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Mark battery low warning as sent.
    public mutating func markBatteryLowSent(at date: Date = Date()) {
        batteryLowSent = true
        lastWarningDate = date
    }
    
    /// Get next pending warning for remaining days.
    public func nextPendingWarning(daysRemaining: Double) -> TransmitterWarning? {
        for warning in TransmitterWarning.allCases.sorted(by: >) {
            if daysRemaining <= Double(warning.rawValue) && !wasSent(warning) {
                return warning
            }
        }
        return nil
    }
}

// MARK: - Transmitter Notification

/// Notification content for transmitter expiration.
public struct TransmitterExpirationNotification: Sendable, Equatable {
    public let session: TransmitterSession
    public let warning: TransmitterWarning
    public let daysRemaining: Double
    public let timestamp: Date
    
    public init(
        session: TransmitterSession,
        warning: TransmitterWarning,
        daysRemaining: Double,
        timestamp: Date = Date()
    ) {
        self.session = session
        self.warning = warning
        self.daysRemaining = daysRemaining
        self.timestamp = timestamp
    }
    
    /// Notification title.
    public var title: String {
        warning.title
    }
    
    /// Notification body.
    public var body: String {
        let transmitterName = session.cgmType == .dexcomG6 ? "Dexcom G6" : "CGM"
        
        switch warning {
        case .expired:
            return "\(transmitterName) transmitter (\(session.transmitterId)) has expired. Replace transmitter."
        case .days1:
            return "\(transmitterName) transmitter expires tomorrow. Order replacement."
        case .days3:
            return "\(transmitterName) transmitter expires in 3 days. Prepare replacement."
        case .days7:
            return "\(transmitterName) transmitter expires in 1 week."
        case .days14:
            return "\(transmitterName) transmitter expires in 2 weeks. Plan replacement."
        }
    }
    
    /// Convert to GlucoseNotificationContent.
    public func toNotificationContent() -> GlucoseNotificationContent {
        GlucoseNotificationContent(
            type: .transmitterExpiring,
            title: title,
            body: body,
            timestamp: timestamp,
            userInfo: [
                "transmitterId": session.transmitterId,
                "cgmType": session.cgmType.rawValue,
                "warning": String(warning.rawValue),
                "daysRemaining": String(format: "%.1f", daysRemaining)
            ]
        )
    }
}

// MARK: - Battery Low Notification

/// Notification for transmitter battery low.
public struct TransmitterBatteryNotification: Sendable, Equatable {
    public let transmitterId: String
    public let cgmType: CGMType
    public let voltageA: Int?  // Battery A voltage in millivolts
    public let voltageB: Int?  // Battery B voltage in millivolts
    public let timestamp: Date
    
    public init(
        transmitterId: String,
        cgmType: CGMType,
        voltageA: Int? = nil,
        voltageB: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.transmitterId = transmitterId
        self.cgmType = cgmType
        self.voltageA = voltageA
        self.voltageB = voltageB
        self.timestamp = timestamp
    }
    
    /// Notification title.
    public var title: String {
        "Transmitter Battery Low"
    }
    
    /// Notification body.
    public var body: String {
        let transmitterName = cgmType == .dexcomG6 ? "Dexcom G6" : "CGM"
        return "\(transmitterName) transmitter (\(transmitterId)) battery is low. Consider replacement soon."
    }
    
    /// Convert to GlucoseNotificationContent.
    public func toNotificationContent() -> GlucoseNotificationContent {
        var userInfo: [String: String] = [
            "transmitterId": transmitterId,
            "cgmType": cgmType.rawValue,
            "type": "batteryLow"
        ]
        if let voltageA = voltageA {
            userInfo["voltageA"] = String(voltageA)
        }
        if let voltageB = voltageB {
            userInfo["voltageB"] = String(voltageB)
        }
        
        return GlucoseNotificationContent(
            type: .transmitterBatteryLow,
            title: title,
            body: body,
            timestamp: timestamp,
            userInfo: userInfo
        )
    }
}

// MARK: - Battery Status

/// Transmitter battery status.
public struct TransmitterBatteryStatus: Sendable, Codable, Equatable {
    /// Battery A voltage in millivolts.
    public let voltageA: Int?
    /// Battery B voltage in millivolts.
    public let voltageB: Int?
    /// Resist value (internal).
    public let resist: Int?
    /// Runtime in seconds (internal).
    public let runtime: Int?
    /// Temperature in Celsius.
    public let temperature: Int?
    /// Status byte.
    public let status: UInt8?
    /// Timestamp of reading.
    public let timestamp: Date
    
    public init(
        voltageA: Int? = nil,
        voltageB: Int? = nil,
        resist: Int? = nil,
        runtime: Int? = nil,
        temperature: Int? = nil,
        status: UInt8? = nil,
        timestamp: Date = Date()
    ) {
        self.voltageA = voltageA
        self.voltageB = voltageB
        self.resist = resist
        self.runtime = runtime
        self.temperature = temperature
        self.status = status
        self.timestamp = timestamp
    }
    
    /// Low battery threshold for voltage A (millivolts).
    public static let lowVoltageThresholdA: Int = 300  // 3.0V
    
    /// Low battery threshold for voltage B (millivolts).
    public static let lowVoltageThresholdB: Int = 290  // 2.9V
    
    /// Whether battery A is low.
    public var isVoltageALow: Bool {
        guard let voltage = voltageA else { return false }
        return voltage <= Self.lowVoltageThresholdA
    }
    
    /// Whether battery B is low.
    public var isVoltageBLow: Bool {
        guard let voltage = voltageB else { return false }
        return voltage <= Self.lowVoltageThresholdB
    }
    
    /// Whether any battery is low.
    public var isBatteryLow: Bool {
        isVoltageALow || isVoltageBLow
    }
}

// MARK: - Monitor Result

/// Result of checking transmitter expiration state.
public enum TransmitterExpirationCheckResult: Sendable, Equatable {
    /// No session active.
    case noSession
    /// Session active, no warning needed.
    case healthy(daysRemaining: Double)
    /// Warning threshold reached.
    case warning(TransmitterExpirationNotification)
    /// Warning already sent for this threshold.
    case alreadySent(TransmitterWarning)
    /// Transmitter has expired.
    case expired
}

/// Result of checking battery status.
public enum TransmitterBatteryCheckResult: Sendable, Equatable {
    /// No battery info available.
    case unknown
    /// Battery is healthy.
    case healthy
    /// Battery is low, notification needed.
    case low(TransmitterBatteryNotification)
    /// Battery low notification already sent.
    case alreadyNotified
}

// MARK: - Monitor Protocol

/// Protocol for transmitter expiration monitoring.
public protocol TransmitterExpirationMonitoring: Sendable {
    /// Start tracking a new transmitter session.
    func startSession(_ session: TransmitterSession) async
    /// End the current session.
    func endSession() async
    /// Get current session.
    func currentSession() async -> TransmitterSession?
    /// Check for pending expiration warning.
    func checkExpiration(at date: Date) async -> TransmitterExpirationCheckResult
    /// Mark warning as sent.
    func markWarningSent(_ warning: TransmitterWarning) async
    /// Update battery status.
    func updateBatteryStatus(_ status: TransmitterBatteryStatus) async
    /// Check for battery low warning.
    func checkBattery() async -> TransmitterBatteryCheckResult
    /// Mark battery low warning as sent.
    func markBatteryLowSent() async
}

// MARK: - Monitor Actor

/// Actor that monitors transmitter expiration and battery, triggers warnings.
public actor TransmitterExpirationMonitor: TransmitterExpirationMonitoring {
    private var session: TransmitterSession?
    private var warningState: TransmitterWarningState?
    private var batteryStatus: TransmitterBatteryStatus?
    private let persistence: TransmitterStatePersistence?
    
    public init(persistence: TransmitterStatePersistence? = nil) {
        self.persistence = persistence
    }
    
    /// Start tracking a new transmitter session.
    public func startSession(_ session: TransmitterSession) async {
        self.session = session
        self.warningState = TransmitterWarningState(transmitterId: session.transmitterId)
        
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
        batteryStatus = nil
        
        if let persistence = persistence {
            await persistence.clearSession()
        }
    }
    
    /// Get current session.
    public func currentSession() async -> TransmitterSession? {
        session
    }
    
    /// Get current battery status.
    public func currentBatteryStatus() async -> TransmitterBatteryStatus? {
        batteryStatus
    }
    
    /// Restore session from persistence.
    public func restoreSession() async {
        guard let persistence = persistence else { return }
        
        if let saved = await persistence.loadSession() {
            self.session = saved
        }
        
        if let session = session,
           let savedState = await persistence.loadWarningState(for: session.transmitterId) {
            self.warningState = savedState
        }
        
        if let savedBattery = await persistence.loadBatteryStatus() {
            self.batteryStatus = savedBattery
        }
    }
    
    /// Check for pending expiration warning.
    public func checkExpiration(at date: Date = Date()) async -> TransmitterExpirationCheckResult {
        guard let session = session else {
            return .noSession
        }
        
        let daysRemaining = session.daysRemaining(at: date)
        
        // Check if expired
        if daysRemaining <= 0 {
            return .expired
        }
        
        // Check for pending warning
        guard let warningState = warningState else {
            return .healthy(daysRemaining: daysRemaining)
        }
        
        if let pendingWarning = warningState.nextPendingWarning(daysRemaining: daysRemaining) {
            let notification = TransmitterExpirationNotification(
                session: session,
                warning: pendingWarning,
                daysRemaining: daysRemaining,
                timestamp: date
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = TransmitterWarning.forDaysRemaining(daysRemaining),
           warningState.wasSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(daysRemaining: daysRemaining)
    }
    
    /// Mark warning as sent.
    public func markWarningSent(_ warning: TransmitterWarning) async {
        warningState?.markSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Update battery status.
    public func updateBatteryStatus(_ status: TransmitterBatteryStatus) async {
        self.batteryStatus = status
        
        if let persistence = persistence {
            await persistence.saveBatteryStatus(status)
        }
    }
    
    /// Check for battery low warning.
    public func checkBattery() async -> TransmitterBatteryCheckResult {
        guard let batteryStatus = batteryStatus else {
            return .unknown
        }
        
        // Already notified?
        if let warningState = warningState, warningState.batteryLowSent {
            return .alreadyNotified
        }
        
        // Check if battery is low
        if batteryStatus.isBatteryLow {
            guard let session = session else {
                return .unknown
            }
            
            let notification = TransmitterBatteryNotification(
                transmitterId: session.transmitterId,
                cgmType: session.cgmType,
                voltageA: batteryStatus.voltageA,
                voltageB: batteryStatus.voltageB,
                timestamp: batteryStatus.timestamp
            )
            return .low(notification)
        }
        
        return .healthy
    }
    
    /// Mark battery low warning as sent.
    public func markBatteryLowSent() async {
        warningState?.markBatteryLowSent()
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Update session from transmitter reading.
    public func updateFromReading(
        transmitterId: String,
        cgmType: CGMType,
        transmitterAgeDays: Double
    ) async {
        // Calculate activation date from age
        let activationDate = Date().addingTimeInterval(-transmitterAgeDays * 86400)
        
        // Check if this is a new transmitter
        if let current = session, current.transmitterId == transmitterId {
            // Same transmitter, no update needed
            return
        }
        
        // New transmitter detected
        let newSession = TransmitterSession(
            transmitterId: transmitterId,
            cgmType: cgmType,
            activationDate: activationDate
        )
        
        await startSession(newSession)
    }
}

// MARK: - Persistence Protocol

/// Protocol for persisting transmitter state.
public protocol TransmitterStatePersistence: Sendable {
    func saveSession(_ session: TransmitterSession) async
    func loadSession() async -> TransmitterSession?
    func clearSession() async
    func saveWarningState(_ state: TransmitterWarningState) async
    func loadWarningState(for transmitterId: String) async -> TransmitterWarningState?
    func saveBatteryStatus(_ status: TransmitterBatteryStatus) async
    func loadBatteryStatus() async -> TransmitterBatteryStatus?
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing.
public actor InMemoryTransmitterPersistence: TransmitterStatePersistence {
    private var session: TransmitterSession?
    private var warningStates: [String: TransmitterWarningState] = [:]
    private var batteryStatus: TransmitterBatteryStatus?
    
    public init() {}
    
    public func saveSession(_ session: TransmitterSession) async {
        self.session = session
    }
    
    public func loadSession() async -> TransmitterSession? {
        session
    }
    
    public func clearSession() async {
        session = nil
        batteryStatus = nil
    }
    
    public func saveWarningState(_ state: TransmitterWarningState) async {
        warningStates[state.transmitterId] = state
    }
    
    public func loadWarningState(for transmitterId: String) async -> TransmitterWarningState? {
        warningStates[transmitterId]
    }
    
    public func saveBatteryStatus(_ status: TransmitterBatteryStatus) async {
        self.batteryStatus = status
    }
    
    public func loadBatteryStatus() async -> TransmitterBatteryStatus? {
        batteryStatus
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults-based persistence for production.
public actor UserDefaultsTransmitterPersistence: TransmitterStatePersistence {
    private let defaults: UserDefaults
    private let sessionKey = "com.t1pal.transmitter.session"
    private let warningPrefix = "com.t1pal.transmitter.warning."
    private let batteryKey = "com.t1pal.transmitter.battery"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveSession(_ session: TransmitterSession) async {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
    
    public func loadSession() async -> TransmitterSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(TransmitterSession.self, from: data)
    }
    
    public func clearSession() async {
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: batteryKey)
    }
    
    public func saveWarningState(_ state: TransmitterWarningState) async {
        let key = warningPrefix + state.transmitterId
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
    
    public func loadWarningState(for transmitterId: String) async -> TransmitterWarningState? {
        let key = warningPrefix + transmitterId
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TransmitterWarningState.self, from: data)
    }
    
    public func saveBatteryStatus(_ status: TransmitterBatteryStatus) async {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: batteryKey)
        }
    }
    
    public func loadBatteryStatus() async -> TransmitterBatteryStatus? {
        guard let data = defaults.data(forKey: batteryKey) else { return nil }
        return try? JSONDecoder().decode(TransmitterBatteryStatus.self, from: data)
    }
}

// MARK: - Transmitter Scheduler

/// Schedules periodic transmitter expiration checks.
public actor TransmitterExpirationScheduler {
    private let monitor: TransmitterExpirationMonitor
    private let expirationHandler: @Sendable (TransmitterExpirationNotification) async -> Void
    private let batteryHandler: @Sendable (TransmitterBatteryNotification) async -> Void
    private let checkInterval: TimeInterval
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?
    
    public init(
        monitor: TransmitterExpirationMonitor,
        checkInterval: TimeInterval = 86400, // 24 hours default (transmitter lifecycle is 90 days)
        expirationHandler: @escaping @Sendable (TransmitterExpirationNotification) async -> Void,
        batteryHandler: @escaping @Sendable (TransmitterBatteryNotification) async -> Void = { _ in }
    ) {
        self.monitor = monitor
        self.checkInterval = checkInterval
        self.expirationHandler = expirationHandler
        self.batteryHandler = batteryHandler
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
        // Check expiration
        let expirationResult = await monitor.checkExpiration()
        switch expirationResult {
        case .warning(let notification):
            await monitor.markWarningSent(notification.warning)
            await expirationHandler(notification)
        default:
            break
        }
        
        // Check battery
        let batteryResult = await monitor.checkBattery()
        switch batteryResult {
        case .low(let notification):
            await monitor.markBatteryLowSent()
            await batteryHandler(notification)
        default:
            break
        }
    }
}

// MARK: - Progress Display

/// Transmitter progress for UI display.
public struct TransmitterProgress: Sendable {
    public let session: TransmitterSession
    public let daysRemaining: Double
    public let daysElapsed: Double
    public let progress: Double
    public let warningLevel: TransmitterWarning?
    public let batteryStatus: TransmitterBatteryStatus?
    
    public init(session: TransmitterSession, batteryStatus: TransmitterBatteryStatus? = nil, at date: Date = Date()) {
        self.session = session
        self.daysRemaining = session.daysRemaining(at: date)
        self.daysElapsed = session.ageDays(at: date)
        self.progress = session.progress(at: date)
        self.warningLevel = TransmitterWarning.forDaysRemaining(daysRemaining)
        self.batteryStatus = batteryStatus
    }
    
    /// Formatted remaining time.
    public var remainingText: String {
        if daysRemaining <= 0 {
            return "Expired"
        } else if daysRemaining < 1 {
            let hours = Int(daysRemaining * 24)
            return "\(hours) hours"
        } else if daysRemaining < 7 {
            let days = Int(daysRemaining)
            return "\(days) days"
        } else {
            let weeks = daysRemaining / 7
            return String(format: "%.1f weeks", weeks)
        }
    }
    
    /// Formatted elapsed time.
    public var elapsedText: String {
        if daysElapsed < 1 {
            let hours = Int(daysElapsed * 24)
            return "\(hours) hours"
        } else if daysElapsed < 7 {
            let days = Int(daysElapsed)
            return "\(days) days"
        } else {
            let weeks = daysElapsed / 7
            return String(format: "%.0f weeks", weeks)
        }
    }
    
    /// Color category for progress display.
    public var colorCategory: String {
        switch warningLevel {
        case .expired: return "expired"
        case .days1: return "critical"
        case .days3: return "warning"
        case .days7: return "attention"
        case .days14: return "caution"
        case nil: return "healthy"
        }
    }
    
    /// Battery status text.
    public var batteryText: String? {
        guard let battery = batteryStatus else { return nil }
        
        if battery.isBatteryLow {
            return "Low"
        } else if let voltageA = battery.voltageA {
            return String(format: "%.2fV", Double(voltageA) / 100.0)
        }
        return nil
    }
}
