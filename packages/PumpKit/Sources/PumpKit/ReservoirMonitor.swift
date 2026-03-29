// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ReservoirMonitor.swift
// PumpKit
//
// Monitors reservoir level and battery status for pumps.
// Sends notifications at configurable thresholds (default: 50U, 20U, 10U for reservoir).
//
// LIFE-PUMP-004: Medtronic reservoir low notifications
// LIFE-PUMP-005: Medtronic battery low notification
// LIFE-NOTIFY-002: Localized lifecycle notifications

import Foundation
import T1PalCore

// MARK: - Reservoir Warning

/// Warning levels for reservoir status.
public enum ReservoirWarning: Int, CaseIterable, Sendable, Codable, Comparable {
    case units50 = 50
    case units20 = 20
    case units10 = 10
    case empty = 0
    
    /// Warning message.
    /// Trace: LIFE-NOTIFY-002
    public var message: String {
        switch self {
        case .units50:
            return LifecycleL10n.Reservoir.low50Message.localized(
                fallback: "Reservoir low: 50 units remaining")
        case .units20:
            return LifecycleL10n.Reservoir.low20Message.localized(
                fallback: "Reservoir low: 20 units remaining")
        case .units10:
            return LifecycleL10n.Reservoir.low10Message.localized(
                fallback: "Reservoir very low: 10 units remaining")
        case .empty:
            return LifecycleL10n.Reservoir.emptyMessage.localized(
                fallback: "Reservoir empty")
        }
    }
    
    /// Title for notification.
    /// Trace: LIFE-NOTIFY-002
    public var title: String {
        switch self {
        case .units50:
            return LifecycleL10n.Reservoir.low50Title.localized(
                fallback: "Reservoir Low")
        case .units20:
            return LifecycleL10n.Reservoir.low20Title.localized(
                fallback: "Reservoir Low")
        case .units10:
            return LifecycleL10n.Reservoir.low10Title.localized(
                fallback: "Reservoir Very Low")
        case .empty:
            return LifecycleL10n.Reservoir.emptyTitle.localized(
                fallback: "Reservoir Empty")
        }
    }
    
    /// Whether this is a critical warning.
    public var isCritical: Bool {
        switch self {
        case .empty: return true
        default: return false
        }
    }
    
    /// Determine warning level for remaining units.
    public static func forUnitsRemaining(_ units: Double) -> ReservoirWarning? {
        if units <= 0 {
            return .empty
        } else if units <= 10 {
            return .units10
        } else if units <= 20 {
            return .units20
        } else if units <= 50 {
            return .units50
        }
        return nil
    }
    
    public static func < (lhs: ReservoirWarning, rhs: ReservoirWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Battery Warning

/// Warning levels for pump battery.
public enum PumpBatteryWarning: Int, CaseIterable, Sendable, Codable, Comparable {
    case low = 20      // 20% threshold
    case critical = 10 // 10% threshold
    case empty = 0     // 0%
    
    /// Warning message.
    /// Trace: LIFE-NOTIFY-002
    public var message: String {
        switch self {
        case .low:
            return LifecycleL10n.PumpBattery.lowMessage.localized(
                fallback: "Pump battery low")
        case .critical:
            return LifecycleL10n.PumpBattery.criticalMessage.localized(
                fallback: "Pump battery critically low")
        case .empty:
            return LifecycleL10n.PumpBattery.emptyMessage.localized(
                fallback: "Pump battery empty")
        }
    }
    
    /// Title for notification.
    /// Trace: LIFE-NOTIFY-002
    public var title: String {
        switch self {
        case .low:
            return LifecycleL10n.PumpBattery.lowTitle.localized(
                fallback: "Pump Battery Low")
        case .critical:
            return LifecycleL10n.PumpBattery.criticalTitle.localized(
                fallback: "Pump Battery Critical")
        case .empty:
            return LifecycleL10n.PumpBattery.emptyTitle.localized(
                fallback: "Pump Battery Empty")
        }
    }
    
    /// Whether this is a critical warning.
    public var isCritical: Bool {
        switch self {
        case .critical, .empty: return true
        default: return false
        }
    }
    
    /// Determine warning level for battery percentage (0-1 scale).
    public static func forBatteryLevel(_ level: Double) -> PumpBatteryWarning? {
        let percent = level * 100
        if percent <= 0 {
            return .empty
        } else if percent <= 10 {
            return .critical
        } else if percent <= 20 {
            return .low
        }
        return nil
    }
    
    public static func < (lhs: PumpBatteryWarning, rhs: PumpBatteryWarning) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Reservoir Status

/// Current reservoir status.
public struct ReservoirStatus: Sendable, Codable, Equatable {
    public let pumpId: String
    public let currentLevel: Double
    public let capacity: Double
    public let timestamp: Date
    
    public init(
        pumpId: String,
        currentLevel: Double,
        capacity: Double,
        timestamp: Date = Date()
    ) {
        self.pumpId = pumpId
        self.currentLevel = currentLevel
        self.capacity = capacity
        self.timestamp = timestamp
    }
    
    /// Percentage remaining (0-1).
    public var percentRemaining: Double {
        guard capacity > 0 else { return 0 }
        return min(1.0, max(0.0, currentLevel / capacity))
    }
    
    /// Current warning level.
    public var warningLevel: ReservoirWarning? {
        ReservoirWarning.forUnitsRemaining(currentLevel)
    }
}

// MARK: - Battery Status

/// Current pump battery status.
public struct PumpBatteryStatus: Sendable, Codable, Equatable {
    public let pumpId: String
    public let level: Double  // 0-1 scale
    public let timestamp: Date
    
    public init(
        pumpId: String,
        level: Double,
        timestamp: Date = Date()
    ) {
        self.pumpId = pumpId
        self.level = level
        self.timestamp = timestamp
    }
    
    /// Percentage (0-100).
    public var percentage: Int {
        Int(level * 100)
    }
    
    /// Current warning level.
    public var warningLevel: PumpBatteryWarning? {
        PumpBatteryWarning.forBatteryLevel(level)
    }
}

// MARK: - Warning State

/// Tracks which warnings have been sent.
public struct ReservoirWarningState: Sendable, Codable, Equatable {
    public let pumpId: String
    public private(set) var sentReservoirWarnings: Set<Int>
    public private(set) var sentBatteryWarnings: Set<Int>
    public private(set) var lastWarningDate: Date?
    
    public init(pumpId: String) {
        self.pumpId = pumpId
        self.sentReservoirWarnings = []
        self.sentBatteryWarnings = []
        self.lastWarningDate = nil
    }
    
    /// Check if reservoir warning was already sent.
    public func wasReservoirWarningSent(_ warning: ReservoirWarning) -> Bool {
        sentReservoirWarnings.contains(warning.rawValue)
    }
    
    /// Check if battery warning was already sent.
    public func wasBatteryWarningSent(_ warning: PumpBatteryWarning) -> Bool {
        sentBatteryWarnings.contains(warning.rawValue)
    }
    
    /// Mark reservoir warning as sent.
    public mutating func markReservoirWarningSent(_ warning: ReservoirWarning, at date: Date = Date()) {
        sentReservoirWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Mark battery warning as sent.
    public mutating func markBatteryWarningSent(_ warning: PumpBatteryWarning, at date: Date = Date()) {
        sentBatteryWarnings.insert(warning.rawValue)
        lastWarningDate = date
    }
    
    /// Reset reservoir warnings (e.g., after reservoir change).
    public mutating func resetReservoirWarnings() {
        sentReservoirWarnings = []
    }
    
    /// Reset battery warnings (e.g., after battery change).
    public mutating func resetBatteryWarnings() {
        sentBatteryWarnings = []
    }
    
    /// Get next pending reservoir warning for current level.
    public func nextPendingReservoirWarning(unitsRemaining: Double) -> ReservoirWarning? {
        guard let appropriateWarning = ReservoirWarning.forUnitsRemaining(unitsRemaining) else {
            return nil
        }
        return wasReservoirWarningSent(appropriateWarning) ? nil : appropriateWarning
    }
    
    /// Get next pending battery warning for current level.
    public func nextPendingBatteryWarning(batteryLevel: Double) -> PumpBatteryWarning? {
        guard let appropriateWarning = PumpBatteryWarning.forBatteryLevel(batteryLevel) else {
            return nil
        }
        return wasBatteryWarningSent(appropriateWarning) ? nil : appropriateWarning
    }
}

// MARK: - Notifications

/// Notification content for reservoir warning.
public struct ReservoirNotification: Sendable, Equatable {
    public let pumpId: String
    public let warning: ReservoirWarning
    public let unitsRemaining: Double
    public let timestamp: Date
    
    public init(
        pumpId: String,
        warning: ReservoirWarning,
        unitsRemaining: Double,
        timestamp: Date = Date()
    ) {
        self.pumpId = pumpId
        self.warning = warning
        self.unitsRemaining = unitsRemaining
        self.timestamp = timestamp
    }
}

/// Notification content for battery warning.
public struct PumpBatteryNotification: Sendable, Equatable {
    public let pumpId: String
    public let warning: PumpBatteryWarning
    public let batteryLevel: Double
    public let timestamp: Date
    
    public init(
        pumpId: String,
        warning: PumpBatteryWarning,
        batteryLevel: Double,
        timestamp: Date = Date()
    ) {
        self.pumpId = pumpId
        self.warning = warning
        self.batteryLevel = batteryLevel
        self.timestamp = timestamp
    }
}

// MARK: - Check Results

/// Result of checking reservoir status.
public enum ReservoirCheckResult: Sendable, Equatable {
    /// No pump tracked.
    case noPump
    /// Reservoir level healthy.
    case healthy(unitsRemaining: Double)
    /// Warning threshold reached.
    case warning(ReservoirNotification)
    /// Warning already sent for this threshold.
    case alreadySent(ReservoirWarning)
}

/// Result of checking battery status.
public enum BatteryCheckResult: Sendable, Equatable {
    /// No pump tracked.
    case noPump
    /// Battery level healthy.
    case healthy(level: Double)
    /// Warning threshold reached.
    case warning(PumpBatteryNotification)
    /// Warning already sent for this threshold.
    case alreadySent(PumpBatteryWarning)
}

// MARK: - Monitor Protocol

/// Protocol for reservoir and battery monitoring.
public protocol ReservoirMonitoring: Sendable {
    /// Start tracking a pump.
    func startTracking(pumpId: String, reservoirCapacity: Double) async
    /// Stop tracking.
    func stopTracking() async
    /// Update reservoir level.
    func updateReservoirLevel(_ level: Double) async
    /// Update battery level.
    func updateBatteryLevel(_ level: Double) async
    /// Check for pending reservoir warning.
    func checkReservoir() async -> ReservoirCheckResult
    /// Check for pending battery warning.
    func checkBattery() async -> BatteryCheckResult
    /// Mark reservoir warning as sent.
    func markReservoirWarningSent(_ warning: ReservoirWarning) async
    /// Mark battery warning as sent.
    func markBatteryWarningSent(_ warning: PumpBatteryWarning) async
    /// Reset warnings after reservoir change.
    func reservoirChanged() async
    /// Reset warnings after battery change.
    func batteryChanged() async
}

// MARK: - Monitor Actor

/// Actor that monitors reservoir and battery levels, triggers warnings.
public actor ReservoirMonitor: ReservoirMonitoring {
    private var pumpId: String?
    private var reservoirCapacity: Double = 0
    private var currentReservoirLevel: Double = 0
    private var currentBatteryLevel: Double = 1.0
    private var warningState: ReservoirWarningState?
    private let persistence: ReservoirStatePersistence?
    
    public init(persistence: ReservoirStatePersistence? = nil) {
        self.persistence = persistence
    }
    
    /// Start tracking a pump.
    public func startTracking(pumpId: String, reservoirCapacity: Double) async {
        self.pumpId = pumpId
        self.reservoirCapacity = reservoirCapacity
        self.warningState = ReservoirWarningState(pumpId: pumpId)
        
        if let persistence = persistence {
            await persistence.saveWarningState(warningState!)
        }
    }
    
    /// Stop tracking.
    public func stopTracking() async {
        pumpId = nil
        warningState = nil
        currentReservoirLevel = 0
        currentBatteryLevel = 1.0
        
        if let persistence = persistence {
            await persistence.clearState()
        }
    }
    
    /// Get current pump ID.
    public func currentPumpId() -> String? {
        pumpId
    }
    
    /// Get current reservoir status.
    public func currentReservoirStatus() -> ReservoirStatus? {
        guard let pumpId = pumpId else { return nil }
        return ReservoirStatus(
            pumpId: pumpId,
            currentLevel: currentReservoirLevel,
            capacity: reservoirCapacity
        )
    }
    
    /// Get current battery status.
    public func currentBatteryStatus() -> PumpBatteryStatus? {
        guard let pumpId = pumpId else { return nil }
        return PumpBatteryStatus(
            pumpId: pumpId,
            level: currentBatteryLevel
        )
    }
    
    /// Update reservoir level.
    public func updateReservoirLevel(_ level: Double) async {
        currentReservoirLevel = max(0, level)
        
        if let persistence = persistence, let pumpId = pumpId {
            let status = ReservoirStatus(
                pumpId: pumpId,
                currentLevel: currentReservoirLevel,
                capacity: reservoirCapacity
            )
            await persistence.saveReservoirStatus(status)
        }
    }
    
    /// Update battery level.
    public func updateBatteryLevel(_ level: Double) async {
        currentBatteryLevel = min(1.0, max(0, level))
        
        if let persistence = persistence, let pumpId = pumpId {
            let status = PumpBatteryStatus(
                pumpId: pumpId,
                level: currentBatteryLevel
            )
            await persistence.saveBatteryStatus(status)
        }
    }
    
    /// Check for pending reservoir warning.
    public func checkReservoir() async -> ReservoirCheckResult {
        guard let pumpId = pumpId else {
            return .noPump
        }
        
        guard let warningState = warningState else {
            return .healthy(unitsRemaining: currentReservoirLevel)
        }
        
        if let pendingWarning = warningState.nextPendingReservoirWarning(unitsRemaining: currentReservoirLevel) {
            let notification = ReservoirNotification(
                pumpId: pumpId,
                warning: pendingWarning,
                unitsRemaining: currentReservoirLevel
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = ReservoirWarning.forUnitsRemaining(currentReservoirLevel),
           warningState.wasReservoirWarningSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(unitsRemaining: currentReservoirLevel)
    }
    
    /// Check for pending battery warning.
    public func checkBattery() async -> BatteryCheckResult {
        guard let pumpId = pumpId else {
            return .noPump
        }
        
        guard let warningState = warningState else {
            return .healthy(level: currentBatteryLevel)
        }
        
        if let pendingWarning = warningState.nextPendingBatteryWarning(batteryLevel: currentBatteryLevel) {
            let notification = PumpBatteryNotification(
                pumpId: pumpId,
                warning: pendingWarning,
                batteryLevel: currentBatteryLevel
            )
            return .warning(notification)
        }
        
        // Check if we're in a warning zone but already sent
        if let currentLevel = PumpBatteryWarning.forBatteryLevel(currentBatteryLevel),
           warningState.wasBatteryWarningSent(currentLevel) {
            return .alreadySent(currentLevel)
        }
        
        return .healthy(level: currentBatteryLevel)
    }
    
    /// Mark reservoir warning as sent.
    public func markReservoirWarningSent(_ warning: ReservoirWarning) async {
        warningState?.markReservoirWarningSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Mark battery warning as sent.
    public func markBatteryWarningSent(_ warning: PumpBatteryWarning) async {
        warningState?.markBatteryWarningSent(warning)
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Reset warnings after reservoir change.
    public func reservoirChanged() async {
        warningState?.resetReservoirWarnings()
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Reset warnings after battery change.
    public func batteryChanged() async {
        warningState?.resetBatteryWarnings()
        
        if let persistence = persistence, let warningState = warningState {
            await persistence.saveWarningState(warningState)
        }
    }
    
    /// Restore state from persistence.
    public func restoreState() async {
        guard let persistence = persistence else { return }
        
        if let savedState = await persistence.loadWarningState() {
            self.pumpId = savedState.pumpId
            self.warningState = savedState
        }
        
        if let savedReservoir = await persistence.loadReservoirStatus() {
            self.currentReservoirLevel = savedReservoir.currentLevel
            self.reservoirCapacity = savedReservoir.capacity
        }
        
        if let savedBattery = await persistence.loadBatteryStatus() {
            self.currentBatteryLevel = savedBattery.level
        }
    }
}

// MARK: - Persistence Protocol

/// Protocol for persisting reservoir monitor state.
public protocol ReservoirStatePersistence: Sendable {
    func saveWarningState(_ state: ReservoirWarningState) async
    func loadWarningState() async -> ReservoirWarningState?
    func saveReservoirStatus(_ status: ReservoirStatus) async
    func loadReservoirStatus() async -> ReservoirStatus?
    func saveBatteryStatus(_ status: PumpBatteryStatus) async
    func loadBatteryStatus() async -> PumpBatteryStatus?
    func clearState() async
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing.
public actor InMemoryReservoirPersistence: ReservoirStatePersistence {
    private var warningState: ReservoirWarningState?
    private var reservoirStatus: ReservoirStatus?
    private var batteryStatus: PumpBatteryStatus?
    
    public init() {}
    
    public func saveWarningState(_ state: ReservoirWarningState) async {
        self.warningState = state
    }
    
    public func loadWarningState() async -> ReservoirWarningState? {
        warningState
    }
    
    public func saveReservoirStatus(_ status: ReservoirStatus) async {
        self.reservoirStatus = status
    }
    
    public func loadReservoirStatus() async -> ReservoirStatus? {
        reservoirStatus
    }
    
    public func saveBatteryStatus(_ status: PumpBatteryStatus) async {
        self.batteryStatus = status
    }
    
    public func loadBatteryStatus() async -> PumpBatteryStatus? {
        batteryStatus
    }
    
    public func clearState() async {
        warningState = nil
        reservoirStatus = nil
        batteryStatus = nil
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults-based persistence for production use.
public actor UserDefaultsReservoirPersistence: ReservoirStatePersistence {
    private let defaults: UserDefaults
    private let warningStateKey = "t1pal.reservoir.warningState"
    private let reservoirStatusKey = "t1pal.reservoir.status"
    private let batteryStatusKey = "t1pal.reservoir.battery"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveWarningState(_ state: ReservoirWarningState) async {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: warningStateKey)
        }
    }
    
    public func loadWarningState() async -> ReservoirWarningState? {
        guard let data = defaults.data(forKey: warningStateKey) else { return nil }
        return try? JSONDecoder().decode(ReservoirWarningState.self, from: data)
    }
    
    public func saveReservoirStatus(_ status: ReservoirStatus) async {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: reservoirStatusKey)
        }
    }
    
    public func loadReservoirStatus() async -> ReservoirStatus? {
        guard let data = defaults.data(forKey: reservoirStatusKey) else { return nil }
        return try? JSONDecoder().decode(ReservoirStatus.self, from: data)
    }
    
    public func saveBatteryStatus(_ status: PumpBatteryStatus) async {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: batteryStatusKey)
        }
    }
    
    public func loadBatteryStatus() async -> PumpBatteryStatus? {
        guard let data = defaults.data(forKey: batteryStatusKey) else { return nil }
        return try? JSONDecoder().decode(PumpBatteryStatus.self, from: data)
    }
    
    public func clearState() async {
        defaults.removeObject(forKey: warningStateKey)
        defaults.removeObject(forKey: reservoirStatusKey)
        defaults.removeObject(forKey: batteryStatusKey)
    }
}

// MARK: - Scheduler

/// Schedules periodic reservoir and battery checks.
public actor ReservoirScheduler {
    private let monitor: ReservoirMonitor
    private let reservoirHandler: @Sendable (ReservoirNotification) async -> Void
    private let batteryHandler: @Sendable (PumpBatteryNotification) async -> Void
    private let checkInterval: TimeInterval
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?
    
    public init(
        monitor: ReservoirMonitor,
        checkInterval: TimeInterval = 3600, // 1 hour default
        reservoirHandler: @escaping @Sendable (ReservoirNotification) async -> Void,
        batteryHandler: @escaping @Sendable (PumpBatteryNotification) async -> Void = { _ in }
    ) {
        self.monitor = monitor
        self.checkInterval = checkInterval
        self.reservoirHandler = reservoirHandler
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
        // Check reservoir
        let reservoirResult = await monitor.checkReservoir()
        switch reservoirResult {
        case .warning(let notification):
            await monitor.markReservoirWarningSent(notification.warning)
            await reservoirHandler(notification)
        default:
            break
        }
        
        // Check battery
        let batteryResult = await monitor.checkBattery()
        switch batteryResult {
        case .warning(let notification):
            await monitor.markBatteryWarningSent(notification.warning)
            await batteryHandler(notification)
        default:
            break
        }
    }
    
    /// Get whether scheduler is running.
    public var running: Bool {
        isRunning
    }
}
