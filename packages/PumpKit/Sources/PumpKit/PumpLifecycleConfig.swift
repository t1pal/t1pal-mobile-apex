// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PumpLifecycleConfig.swift
// PumpKit
//
// Pump-specific lifecycle configuration for Dana and Tandem pumps.
// Provides site change reminders and pump-specific settings.
//
// LIFE-PUMP-006: Dana reservoir lifecycle tracking
// LIFE-PUMP-007: Tandem cartridge lifecycle tracking

import Foundation

// MARK: - Pump Lifecycle Configuration

/// Configuration for pump-specific lifecycle tracking
public enum PumpLifecycleConfig: Sendable {
    /// Dana RS/Dana-i configuration
    case danaRS
    case danaI
    /// Tandem t:slim X2 configuration
    case tandemX2
    /// Medtronic configuration (various models)
    case medtronic(model: MedtronicModel)
    /// Custom configuration
    case custom(CustomPumpConfig)
    
    // MARK: - Reservoir/Cartridge Properties
    
    /// Reservoir/cartridge capacity in units
    public var reservoirCapacity: Double {
        switch self {
        case .danaRS, .danaI:
            return 300  // Dana pumps use 300U reservoirs
        case .tandemX2:
            return 300  // Tandem t:slim uses 300U cartridges
        case .medtronic(let model):
            return model.reservoirCapacity
        case .custom(let config):
            return config.reservoirCapacity
        }
    }
    
    /// What the insulin container is called
    public var consumableName: String {
        switch self {
        case .danaRS, .danaI:
            return "Reservoir"
        case .tandemX2:
            return "Cartridge"
        case .medtronic:
            return "Reservoir"
        case .custom(let config):
            return config.consumableName
        }
    }
    
    /// Action verb for changing the consumable
    public var changeVerb: String {
        switch self {
        case .danaRS, .danaI:
            return "Change reservoir"
        case .tandemX2:
            return "Change cartridge"
        case .medtronic:
            return "Change reservoir"
        case .custom(let config):
            return config.changeVerb
        }
    }
    
    // MARK: - Site Change Configuration
    
    /// Whether this pump type supports site change reminders
    public var supportsSiteChangeReminder: Bool {
        switch self {
        case .tandemX2:
            return true  // Tandem recommends 3-day site changes
        case .danaRS, .danaI:
            return true  // Dana users also benefit from site reminders
        case .medtronic:
            return true
        case .custom(let config):
            return config.siteChangeIntervalHours != nil
        }
    }
    
    /// Recommended site change interval in hours
    public var siteChangeIntervalHours: Int? {
        switch self {
        case .tandemX2:
            return 72  // 3 days
        case .danaRS, .danaI:
            return 72  // 3 days (standard recommendation)
        case .medtronic:
            return 72  // 3 days
        case .custom(let config):
            return config.siteChangeIntervalHours
        }
    }
    
    /// Site change warning intervals in hours before due
    public var siteChangeWarningHours: [Int] {
        switch self {
        case .tandemX2, .danaRS, .danaI, .medtronic:
            return [6, 1]  // 6 hours and 1 hour warnings
        case .custom(let config):
            return config.siteChangeWarningHours
        }
    }
    
    // MARK: - Battery Configuration
    
    /// Whether this pump has a rechargeable battery
    public var hasRechargeableBattery: Bool {
        switch self {
        case .danaRS, .danaI:
            return true  // Dana pumps have rechargeable batteries
        case .tandemX2:
            return true  // Tandem t:slim has rechargeable battery
        case .medtronic:
            return false // Medtronic uses replaceable AAA
        case .custom(let config):
            return config.hasRechargeableBattery
        }
    }
    
    /// Battery type description
    public var batteryType: String {
        switch self {
        case .danaRS, .danaI:
            return "Built-in rechargeable"
        case .tandemX2:
            return "Built-in rechargeable (300mAh)"
        case .medtronic:
            return "AAA alkaline/lithium"
        case .custom(let config):
            return config.batteryType
        }
    }
    
    /// Battery low warning threshold (0-1 scale)
    public var batteryLowThreshold: Double {
        switch self {
        case .danaRS, .danaI:
            return 0.20  // 20%
        case .tandemX2:
            return 0.20  // 20%
        case .medtronic:
            return 0.20  // 20%
        case .custom(let config):
            return config.batteryLowThreshold
        }
    }
    
    // MARK: - Display Name
    
    /// Human-readable pump name
    public var displayName: String {
        switch self {
        case .danaRS:
            return "Dana RS"
        case .danaI:
            return "Dana-i"
        case .tandemX2:
            return "Tandem t:slim X2"
        case .medtronic(let model):
            return model.displayName
        case .custom(let config):
            return config.displayName
        }
    }
}

// MARK: - Medtronic Model

/// Medtronic pump models
public enum MedtronicModel: String, Sendable, Codable, CaseIterable {
    case model522 = "522"
    case model523 = "523"
    case model551 = "551"
    case model554 = "554"
    case model715 = "715"
    case model723 = "723"
    case model751 = "751"
    case model754 = "754"
    
    /// Reservoir capacity
    public var reservoirCapacity: Double {
        switch self {
        case .model522, .model551, .model715, .model751:
            return 176  // 1.76mL = 176U @ U100
        case .model523, .model554, .model723, .model754:
            return 300  // 3.0mL = 300U @ U100
        }
    }
    
    /// Display name
    public var displayName: String {
        "Medtronic \(rawValue)"
    }
}

// MARK: - Custom Pump Configuration

/// Custom pump configuration for unlisted pumps
public struct CustomPumpConfig: Sendable, Codable, Equatable {
    public let displayName: String
    public let reservoirCapacity: Double
    public let consumableName: String
    public let changeVerb: String
    public let siteChangeIntervalHours: Int?
    public let siteChangeWarningHours: [Int]
    public let hasRechargeableBattery: Bool
    public let batteryType: String
    public let batteryLowThreshold: Double
    
    public init(
        displayName: String,
        reservoirCapacity: Double = 300,
        consumableName: String = "Reservoir",
        changeVerb: String = "Change reservoir",
        siteChangeIntervalHours: Int? = 72,
        siteChangeWarningHours: [Int] = [6, 1],
        hasRechargeableBattery: Bool = false,
        batteryType: String = "Unknown",
        batteryLowThreshold: Double = 0.20
    ) {
        self.displayName = displayName
        self.reservoirCapacity = reservoirCapacity
        self.consumableName = consumableName
        self.changeVerb = changeVerb
        self.siteChangeIntervalHours = siteChangeIntervalHours
        self.siteChangeWarningHours = siteChangeWarningHours
        self.hasRechargeableBattery = hasRechargeableBattery
        self.batteryType = batteryType
        self.batteryLowThreshold = batteryLowThreshold
    }
}

// MARK: - Site Change Session

/// Tracks an active infusion site session
public struct SiteChangeSession: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let pumpType: String  // Stored as string for Codable
    public let siteActivationDate: Date
    public let recommendedChangeDate: Date
    
    public init(
        id: UUID = UUID(),
        pumpConfig: PumpLifecycleConfig,
        siteActivationDate: Date = Date()
    ) {
        self.id = id
        self.pumpType = pumpConfig.displayName
        self.siteActivationDate = siteActivationDate
        
        let interval = TimeInterval((pumpConfig.siteChangeIntervalHours ?? 72) * 3600)
        self.recommendedChangeDate = siteActivationDate.addingTimeInterval(interval)
    }
    
    /// Manual initialization with explicit dates
    public init(
        id: UUID = UUID(),
        pumpType: String,
        siteActivationDate: Date,
        recommendedChangeDate: Date
    ) {
        self.id = id
        self.pumpType = pumpType
        self.siteActivationDate = siteActivationDate
        self.recommendedChangeDate = recommendedChangeDate
    }
    
    /// Time remaining until recommended site change
    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        recommendedChangeDate.timeIntervalSince(date)
    }
    
    /// Hours remaining until recommended site change
    public func hoursRemaining(at date: Date = Date()) -> Double {
        timeRemaining(at: date) / 3600.0
    }
    
    /// Whether site change is due
    public func isChangeDue(at date: Date = Date()) -> Bool {
        date >= recommendedChangeDate
    }
    
    /// Whether site change is overdue (past grace period of 12 hours)
    public func isOverdue(at date: Date = Date()) -> Bool {
        date >= recommendedChangeDate.addingTimeInterval(12 * 3600)
    }
    
    /// Site age in hours
    public func ageHours(at date: Date = Date()) -> Double {
        date.timeIntervalSince(siteActivationDate) / 3600.0
    }
    
    /// Progress through site lifetime (0.0 to 1.0+)
    public func progress(at date: Date = Date()) -> Double {
        let total = recommendedChangeDate.timeIntervalSince(siteActivationDate)
        let elapsed = date.timeIntervalSince(siteActivationDate)
        guard total > 0 else { return 1.0 }
        return elapsed / total
    }
    
    /// Formatted time remaining
    public func timeRemainingText(at date: Date = Date()) -> String {
        let hours = hoursRemaining(at: date)
        if hours < 0 {
            let overdue = abs(hours)
            if overdue >= 24 {
                return "\(Int(overdue / 24))d overdue"
            } else {
                return "\(Int(overdue))h overdue"
            }
        } else if hours < 1 {
            return "< 1 hour"
        } else if hours < 24 {
            return "\(Int(hours)) hour\(Int(hours) == 1 ? "" : "s")"
        } else {
            let days = Int(hours / 24)
            let remainingHours = Int(hours.truncatingRemainder(dividingBy: 24))
            return "\(days)d \(remainingHours)h"
        }
    }
}

// MARK: - Site Change Warning

/// Site change warning level
public enum SiteChangeWarning: Int, Sendable, Codable, CaseIterable, Comparable {
    case hours6 = 6
    case hours1 = 1
    case due = 0
    case overdue = -12  // 12 hours past due
    
    /// Warning title
    public var title: String {
        switch self {
        case .hours6: return "Site Change Coming"
        case .hours1: return "Site Change Soon"
        case .due: return "Site Change Due"
        case .overdue: return "Site Change Overdue"
        }
    }
    
    /// Warning body
    public var body: String {
        switch self {
        case .hours6: return "Consider changing your infusion site in the next 6 hours."
        case .hours1: return "Your infusion site change is due in about 1 hour."
        case .due: return "Time to change your infusion site for optimal absorption."
        case .overdue: return "Your infusion site is overdue for change. Please change soon."
        }
    }
    
    /// Whether this is a critical warning
    public var isCritical: Bool {
        self == .overdue
    }
    
    /// Determine warning level for remaining hours
    public static func forHoursRemaining(_ hours: Double) -> SiteChangeWarning? {
        if hours <= -12 {
            return .overdue
        } else if hours <= 0 {
            return .due
        } else if hours <= 1 {
            return .hours1
        } else if hours <= 6 {
            return .hours6
        }
        return nil
    }
    
    public static func < (lhs: SiteChangeWarning, rhs: SiteChangeWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Site Change Warning State

/// Tracks which site change warnings have been sent
public struct SiteChangeWarningState: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public private(set) var sentWarnings: Set<Int>
    public private(set) var lastWarningDate: Date?
    
    public init(sessionId: UUID) {
        self.sessionId = sessionId
        self.sentWarnings = []
        self.lastWarningDate = nil
    }
    
    public func wasSent(_ warning: SiteChangeWarning) -> Bool {
        sentWarnings.contains(warning.rawValue)
    }
    
    public mutating func markSent(_ warning: SiteChangeWarning, at date: Date = Date()) {
        sentWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Get next pending warning for remaining hours
    public func nextPendingWarning(hoursRemaining: Double) -> SiteChangeWarning? {
        guard let appropriateWarning = SiteChangeWarning.forHoursRemaining(hoursRemaining) else {
            return nil
        }
        return wasSent(appropriateWarning) ? nil : appropriateWarning
    }
}

// MARK: - Site Change Notification

/// Notification content for site change
public struct SiteChangeNotification: Sendable, Equatable {
    public let session: SiteChangeSession
    public let warning: SiteChangeWarning
    public let hoursRemaining: Double
    public let timestamp: Date
    
    public init(
        session: SiteChangeSession,
        warning: SiteChangeWarning,
        hoursRemaining: Double,
        timestamp: Date = Date()
    ) {
        self.session = session
        self.warning = warning
        self.hoursRemaining = hoursRemaining
        self.timestamp = timestamp
    }
}

// MARK: - Site Change Check Result

/// Result of checking site change status
public enum SiteChangeCheckResult: Sendable, Equatable {
    /// No site session active
    case noSession
    /// Site is healthy
    case healthy(hoursRemaining: Double)
    /// Site change warning needed
    case warning(SiteChangeNotification)
    /// Warning already sent
    case alreadySent(SiteChangeWarning)
    /// Site change overdue
    case overdue(hoursOverdue: Double)
}

// MARK: - Site Change Monitor Persistence

/// Protocol for persisting site change state
public protocol SiteChangeMonitorPersistence: Sendable {
    func saveSession(_ session: SiteChangeSession) async
    func loadSession() async -> SiteChangeSession?
    func clearSession() async
    
    func saveWarningState(_ state: SiteChangeWarningState) async
    func loadWarningState(for sessionId: UUID) async -> SiteChangeWarningState?
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing
public actor InMemorySiteChangeMonitorPersistence: SiteChangeMonitorPersistence {
    private var session: SiteChangeSession?
    private var warningStates: [UUID: SiteChangeWarningState] = [:]
    
    public init() {}
    
    public func saveSession(_ session: SiteChangeSession) async {
        self.session = session
    }
    
    public func loadSession() async -> SiteChangeSession? {
        session
    }
    
    public func clearSession() async {
        session = nil
    }
    
    public func saveWarningState(_ state: SiteChangeWarningState) async {
        warningStates[state.sessionId] = state
    }
    
    public func loadWarningState(for sessionId: UUID) async -> SiteChangeWarningState? {
        warningStates[sessionId]
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults persistence for production
public actor UserDefaultsSiteChangeMonitorPersistence: SiteChangeMonitorPersistence {
    private let defaults: UserDefaults
    private let sessionKey = "com.t1pal.pump.site.session"
    private let warningStatePrefix = "com.t1pal.pump.site.warning."
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveSession(_ session: SiteChangeSession) async {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
    
    public func loadSession() async -> SiteChangeSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(SiteChangeSession.self, from: data)
    }
    
    public func clearSession() async {
        defaults.removeObject(forKey: sessionKey)
    }
    
    public func saveWarningState(_ state: SiteChangeWarningState) async {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: warningStatePrefix + state.sessionId.uuidString)
        }
    }
    
    public func loadWarningState(for sessionId: UUID) async -> SiteChangeWarningState? {
        guard let data = defaults.data(forKey: warningStatePrefix + sessionId.uuidString) else { return nil }
        return try? JSONDecoder().decode(SiteChangeWarningState.self, from: data)
    }
}

// MARK: - Site Change Monitor

/// Actor that monitors infusion site age and triggers change reminders
public actor SiteChangeMonitor {
    private var session: SiteChangeSession?
    private var warningState: SiteChangeWarningState?
    private let persistence: SiteChangeMonitorPersistence?
    
    public init(persistence: SiteChangeMonitorPersistence? = nil) {
        self.persistence = persistence
    }
    
    // MARK: - Session Management
    
    /// Start a new site session
    public func startSession(
        pumpConfig: PumpLifecycleConfig,
        activationDate: Date = Date()
    ) async {
        let newSession = SiteChangeSession(
            pumpConfig: pumpConfig,
            siteActivationDate: activationDate
        )
        
        self.session = newSession
        self.warningState = SiteChangeWarningState(sessionId: newSession.id)
        
        if let persistence = persistence {
            await persistence.saveSession(newSession)
            await persistence.saveWarningState(warningState!)
        }
    }
    
    /// End current site session
    public func endSession() async {
        session = nil
        warningState = nil
        
        if let persistence = persistence {
            await persistence.clearSession()
        }
    }
    
    /// Get current session
    public func currentSession() -> SiteChangeSession? {
        session
    }
    
    /// Restore session from persistence
    public func restoreSession() async {
        guard let persistence = persistence else { return }
        
        if let saved = await persistence.loadSession() {
            self.session = saved
            
            if let state = await persistence.loadWarningState(for: saved.id) {
                self.warningState = state
            } else {
                self.warningState = SiteChangeWarningState(sessionId: saved.id)
            }
        }
    }
    
    // MARK: - Status Checks
    
    /// Check for pending site change warning
    public func checkSiteChange(at date: Date = Date()) async -> SiteChangeCheckResult {
        guard let session = session else {
            return .noSession
        }
        
        let hoursRemaining = session.hoursRemaining(at: date)
        
        // Check for overdue
        if session.isOverdue(at: date) {
            return .overdue(hoursOverdue: abs(hoursRemaining))
        }
        
        // Check for pending warning
        guard let warningState = warningState else {
            return .healthy(hoursRemaining: hoursRemaining)
        }
        
        if let pendingWarning = warningState.nextPendingWarning(hoursRemaining: hoursRemaining) {
            let notification = SiteChangeNotification(
                session: session,
                warning: pendingWarning,
                hoursRemaining: hoursRemaining,
                timestamp: date
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = SiteChangeWarning.forHoursRemaining(hoursRemaining),
           warningState.wasSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(hoursRemaining: hoursRemaining)
    }
    
    /// Mark warning as sent
    public func markWarningSent(_ warning: SiteChangeWarning) async {
        warningState?.markSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    // MARK: - Convenience Queries
    
    /// Hours remaining until site change
    public func hoursRemaining(at date: Date = Date()) -> Double? {
        session?.hoursRemaining(at: date)
    }
    
    /// Whether site change is due
    public func isChangeDue(at date: Date = Date()) -> Bool {
        session?.isChangeDue(at: date) ?? false
    }
    
    /// Whether site is overdue
    public func isOverdue(at date: Date = Date()) -> Bool {
        session?.isOverdue(at: date) ?? false
    }
    
    /// Get site progress (0.0 to 1.0+)
    public func progress(at date: Date = Date()) -> Double? {
        session?.progress(at: date)
    }
}
