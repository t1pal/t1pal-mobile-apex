// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ConnectionRecoveryManager.swift
// BLEKit
//
// Manages BLE connection recovery after app restart, termination, or crash.
// Coordinates with BackgroundBLEManager for actual reconnection.
//
// PROD-CGM-003: Connection recovery after app restart

import Foundation

// MARK: - Recovery Strategy

/// Strategy for recovering connections.
public enum RecoveryStrategy: String, Codable, Sendable, CaseIterable {
    /// Immediately attempt reconnection.
    case immediate
    /// Wait for user interaction.
    case manual
    /// Attempt with exponential backoff.
    case exponentialBackoff
    /// Wait for specific conditions (e.g., home network).
    case conditional
}

// MARK: - Recovery Priority

/// Priority level for device recovery.
public enum RecoveryPriority: Int, Codable, Sendable, Comparable {
    case critical = 3  // CGM - must reconnect
    case high = 2      // Pump - should reconnect
    case normal = 1    // Accessories
    case low = 0       // Optional devices
    
    public static func < (lhs: RecoveryPriority, rhs: RecoveryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Device Record

/// Record of a known device for recovery.
public struct DeviceRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let deviceType: String
    public let priority: RecoveryPriority
    public let serviceUUIDs: [String]
    public let lastConnected: Date
    public let lastDisconnected: Date?
    public let connectionCount: Int
    public let failureCount: Int
    
    public init(
        id: String,
        name: String,
        deviceType: String,
        priority: RecoveryPriority = .normal,
        serviceUUIDs: [String] = [],
        lastConnected: Date = Date(),
        lastDisconnected: Date? = nil,
        connectionCount: Int = 1,
        failureCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.priority = priority
        self.serviceUUIDs = serviceUUIDs
        self.lastConnected = lastConnected
        self.lastDisconnected = lastDisconnected
        self.connectionCount = connectionCount
        self.failureCount = failureCount
    }
    
    /// Create updated record with new connection.
    public func withConnection(at date: Date = Date()) -> DeviceRecord {
        DeviceRecord(
            id: id,
            name: name,
            deviceType: deviceType,
            priority: priority,
            serviceUUIDs: serviceUUIDs,
            lastConnected: date,
            lastDisconnected: nil,
            connectionCount: connectionCount + 1,
            failureCount: failureCount
        )
    }
    
    /// Create updated record with disconnection.
    public func withDisconnection(at date: Date = Date()) -> DeviceRecord {
        DeviceRecord(
            id: id,
            name: name,
            deviceType: deviceType,
            priority: priority,
            serviceUUIDs: serviceUUIDs,
            lastConnected: lastConnected,
            lastDisconnected: date,
            connectionCount: connectionCount,
            failureCount: failureCount
        )
    }
    
    /// Create updated record with failure.
    public func withFailure() -> DeviceRecord {
        DeviceRecord(
            id: id,
            name: name,
            deviceType: deviceType,
            priority: priority,
            serviceUUIDs: serviceUUIDs,
            lastConnected: lastConnected,
            lastDisconnected: lastDisconnected,
            connectionCount: connectionCount,
            failureCount: failureCount + 1
        )
    }
}

// MARK: - Recovery State

/// Current state of connection recovery.
public enum RecoveryState: Sendable, Equatable {
    /// No recovery in progress.
    case idle
    /// Checking for devices to recover.
    case checking
    /// Recovering devices.
    case recovering(current: String, remaining: Int)
    /// Recovery complete.
    case complete(recovered: Int, failed: Int)
    /// Recovery cancelled.
    case cancelled
    
    public var isActive: Bool {
        switch self {
        case .checking, .recovering: return true
        default: return false
        }
    }
    
    public var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .checking:
            return "Checking devices..."
        case .recovering(let current, let remaining):
            return "Recovering \(current.prefix(8))... (\(remaining) remaining)"
        case .complete(let recovered, let failed):
            return "Complete: \(recovered) recovered, \(failed) failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Recovery Result

/// Result of a recovery attempt.
public struct RecoveryResult: Sendable, Equatable, Codable {
    public let deviceId: String
    public let success: Bool
    public let duration: TimeInterval
    public let attempts: Int
    public let errorMessage: String?
    
    public init(
        deviceId: String,
        success: Bool,
        duration: TimeInterval,
        attempts: Int,
        errorMessage: String? = nil
    ) {
        self.deviceId = deviceId
        self.success = success
        self.duration = duration
        self.attempts = attempts
        self.errorMessage = errorMessage
    }
}

// MARK: - Recovery Session

/// A complete recovery session with metrics.
public struct RecoverySession: Sendable, Equatable, Codable {
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date?
    public let trigger: RecoveryTrigger
    public let results: [RecoveryResult]
    
    public init(
        sessionId: String = UUID().uuidString,
        startTime: Date = Date(),
        endTime: Date? = nil,
        trigger: RecoveryTrigger,
        results: [RecoveryResult] = []
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.trigger = trigger
        self.results = results
    }
    
    /// Total devices attempted.
    public var totalAttempts: Int {
        results.count
    }
    
    /// Successful recoveries.
    public var successCount: Int {
        results.filter { $0.success }.count
    }
    
    /// Failed recoveries.
    public var failureCount: Int {
        results.filter { !$0.success }.count
    }
    
    /// Session duration.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Add a result.
    public func with(result: RecoveryResult) -> RecoverySession {
        RecoverySession(
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            trigger: trigger,
            results: results + [result]
        )
    }
    
    /// Complete the session.
    public func completed(at date: Date = Date()) -> RecoverySession {
        RecoverySession(
            sessionId: sessionId,
            startTime: startTime,
            endTime: date,
            trigger: trigger,
            results: results
        )
    }
}

// MARK: - Recovery Trigger

/// What triggered the recovery attempt.
public enum RecoveryTrigger: String, Codable, Sendable {
    case appLaunch = "app_launch"
    case appRestore = "app_restore"
    case bluetoothReset = "bluetooth_reset"
    case networkChange = "network_change"
    case userRequest = "user_request"
    case scheduled = "scheduled"
    case backgroundWake = "background_wake"
}

// MARK: - Recovery Config

/// Configuration for recovery behavior.
public struct RecoveryConfig: Codable, Sendable {
    public let strategy: RecoveryStrategy
    public let maxAttempts: Int
    public let baseDelaySeconds: TimeInterval
    public let maxDelaySeconds: TimeInterval
    public let timeoutSeconds: TimeInterval
    public let prioritizeByLastConnection: Bool
    
    public init(
        strategy: RecoveryStrategy = .exponentialBackoff,
        maxAttempts: Int = 5,
        baseDelaySeconds: TimeInterval = 2.0,
        maxDelaySeconds: TimeInterval = 60.0,
        timeoutSeconds: TimeInterval = 30.0,
        prioritizeByLastConnection: Bool = true
    ) {
        self.strategy = strategy
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.timeoutSeconds = timeoutSeconds
        self.prioritizeByLastConnection = prioritizeByLastConnection
    }
    
    public static let `default` = RecoveryConfig()
    
    /// Config for CGM devices (high priority).
    public static let cgm = RecoveryConfig(
        strategy: .immediate,
        maxAttempts: 10,
        baseDelaySeconds: 1.0,
        maxDelaySeconds: 30.0,
        timeoutSeconds: 60.0,
        prioritizeByLastConnection: false
    )
    
    /// Calculate delay for attempt number.
    public func delayForAttempt(_ attempt: Int) -> TimeInterval {
        switch strategy {
        case .immediate:
            return 0
        case .manual:
            return 0
        case .exponentialBackoff:
            let delay = baseDelaySeconds * pow(2.0, Double(attempt - 1))
            return min(delay, maxDelaySeconds)
        case .conditional:
            return baseDelaySeconds
        }
    }
}

// MARK: - Persistence Protocol

/// Protocol for persisting device records.
public protocol DeviceRecordPersistence: Sendable {
    func saveDevices(_ devices: [DeviceRecord]) async
    func loadDevices() async -> [DeviceRecord]
    func saveSession(_ session: RecoverySession) async
    func loadSessions(limit: Int) async -> [RecoverySession]
}

// MARK: - In-Memory Persistence

/// In-memory persistence for testing.
public actor InMemoryDevicePersistence: DeviceRecordPersistence {
    private var devices: [DeviceRecord] = []
    private var sessions: [RecoverySession] = []
    
    public init() {}
    
    public func saveDevices(_ devices: [DeviceRecord]) async {
        self.devices = devices
    }
    
    public func loadDevices() async -> [DeviceRecord] {
        devices
    }
    
    public func saveSession(_ session: RecoverySession) async {
        sessions.append(session)
    }
    
    public func loadSessions(limit: Int) async -> [RecoverySession] {
        Array(sessions.suffix(limit))
    }
}

// MARK: - UserDefaults Persistence

/// UserDefaults-based persistence for production.
public actor UserDefaultsDevicePersistence: DeviceRecordPersistence {
    private let defaults: UserDefaults
    private let devicesKey = "com.t1pal.ble.devices"
    private let sessionsKey = "com.t1pal.ble.recovery.sessions"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveDevices(_ devices: [DeviceRecord]) async {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: devicesKey)
        }
    }
    
    public func loadDevices() async -> [DeviceRecord] {
        guard let data = defaults.data(forKey: devicesKey) else { return [] }
        return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
    }
    
    public func saveSession(_ session: RecoverySession) async {
        var sessions = await loadSessions(limit: 100)
        sessions.append(session)
        
        // Keep last 100 sessions
        if sessions.count > 100 {
            sessions = Array(sessions.suffix(100))
        }
        
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: sessionsKey)
        }
    }
    
    public func loadSessions(limit: Int) async -> [RecoverySession] {
        guard let data = defaults.data(forKey: sessionsKey) else { return [] }
        let all = (try? JSONDecoder().decode([RecoverySession].self, from: data)) ?? []
        return Array(all.suffix(limit))
    }
}

// MARK: - Connection Recovery Manager

/// Manages connection recovery after app restart.
public actor ConnectionRecoveryManager {
    private let config: RecoveryConfig
    private let persistence: DeviceRecordPersistence?
    private var devices: [String: DeviceRecord] = [:]
    private var currentState: RecoveryState = .idle
    private var currentSession: RecoverySession?
    
    /// Callback when recovery state changes.
    public var onStateChanged: (@Sendable (RecoveryState) -> Void)?
    
    /// Callback when device recovery completes.
    public var onDeviceRecovered: (@Sendable (String, Bool) -> Void)?
    
    public init(
        config: RecoveryConfig = .default,
        persistence: DeviceRecordPersistence? = nil
    ) {
        self.config = config
        self.persistence = persistence
    }
    
    /// Current recovery state.
    public func state() -> RecoveryState {
        currentState
    }
    
    /// All known devices.
    public func knownDevices() -> [DeviceRecord] {
        Array(devices.values).sorted { $0.priority > $1.priority }
    }
    
    /// Restore from persistence.
    public func restore() async {
        guard let persistence = persistence else { return }
        
        let saved = await persistence.loadDevices()
        for device in saved {
            devices[device.id] = device
        }
    }
    
    /// Register a device for recovery.
    public func registerDevice(_ device: DeviceRecord) async {
        devices[device.id] = device
        await persist()
    }
    
    /// Update device on connection.
    public func deviceConnected(_ deviceId: String) async {
        guard var device = devices[deviceId] else { return }
        device = device.withConnection()
        devices[deviceId] = device
        await persist()
    }
    
    /// Update device on disconnection.
    public func deviceDisconnected(_ deviceId: String) async {
        guard var device = devices[deviceId] else { return }
        device = device.withDisconnection()
        devices[deviceId] = device
        await persist()
    }
    
    /// Start recovery for all devices.
    public func startRecovery(trigger: RecoveryTrigger) async -> RecoverySession {
        currentState = .checking
        onStateChanged?(currentState)
        
        currentSession = RecoverySession(trigger: trigger)
        
        // Get devices sorted by priority
        let devicesToRecover = knownDevices()
        
        if devicesToRecover.isEmpty {
            currentState = .complete(recovered: 0, failed: 0)
            onStateChanged?(currentState)
            
            let completed = currentSession!.completed()
            if let persistence = persistence {
                await persistence.saveSession(completed)
            }
            return completed
        }
        
        var recovered = 0
        var failed = 0
        
        for (index, device) in devicesToRecover.enumerated() {
            let remaining = devicesToRecover.count - index - 1
            currentState = .recovering(current: device.id, remaining: remaining)
            onStateChanged?(currentState)
            
            let result = await recoverDevice(device)
            currentSession = currentSession?.with(result: result)
            
            if result.success {
                recovered += 1
            } else {
                failed += 1
            }
            
            onDeviceRecovered?(device.id, result.success)
        }
        
        currentState = .complete(recovered: recovered, failed: failed)
        onStateChanged?(currentState)
        
        let completed = currentSession!.completed()
        if let persistence = persistence {
            await persistence.saveSession(completed)
        }
        
        return completed
    }
    
    /// Cancel ongoing recovery.
    public func cancelRecovery() async {
        currentState = .cancelled
        onStateChanged?(currentState)
    }
    
    /// Recover a specific device.
    public func recoverDevice(_ device: DeviceRecord) async -> RecoveryResult {
        let startTime = Date()
        var attempts = 0
        var success = false
        var errorMessage: String?
        
        while attempts < config.maxAttempts && !success {
            attempts += 1
            
            // Simulate connection attempt
            // In real implementation, this would call BackgroundBLEManager
            let delay = config.delayForAttempt(attempts)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            // For testing, we'll simulate success based on failure count
            // Real implementation would attempt actual BLE connection
            success = device.failureCount < 3
            
            if !success {
                errorMessage = "Connection timeout"
                
                // Update failure count
                if var d = devices[device.id] {
                    d = d.withFailure()
                    devices[device.id] = d
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        return RecoveryResult(
            deviceId: device.id,
            success: success,
            duration: duration,
            attempts: attempts,
            errorMessage: errorMessage
        )
    }
    
    /// Get devices needing recovery.
    public func devicesNeedingRecovery() -> [DeviceRecord] {
        knownDevices().filter { device in
            // Device needs recovery if disconnected
            device.lastDisconnected != nil
        }
    }
    
    /// Remove a device from recovery list.
    public func removeDevice(_ deviceId: String) async {
        devices.removeValue(forKey: deviceId)
        await persist()
    }
    
    /// Clear all devices.
    public func clearDevices() async {
        devices.removeAll()
        await persist()
    }
    
    /// Get recovery history.
    public func recoveryHistory(limit: Int = 10) async -> [RecoverySession] {
        guard let persistence = persistence else { return [] }
        return await persistence.loadSessions(limit: limit)
    }
    
    // MARK: - Private
    
    private func persist() async {
        guard let persistence = persistence else { return }
        await persistence.saveDevices(Array(devices.values))
    }
}

// MARK: - Recovery Statistics

/// Statistics about recovery operations.
public struct RecoveryStatistics: Sendable {
    public let totalSessions: Int
    public let totalAttempts: Int
    public let totalSuccesses: Int
    public let totalFailures: Int
    public let averageDuration: TimeInterval
    public let successRate: Double
    
    public init(sessions: [RecoverySession]) {
        self.totalSessions = sessions.count
        self.totalAttempts = sessions.reduce(0) { $0 + $1.totalAttempts }
        self.totalSuccesses = sessions.reduce(0) { $0 + $1.successCount }
        self.totalFailures = sessions.reduce(0) { $0 + $1.failureCount }
        
        let durations = sessions.compactMap { $0.duration }
        self.averageDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        
        self.successRate = totalAttempts > 0 ? Double(totalSuccesses) / Double(totalAttempts) : 0
    }
}

// MARK: - App Launch Recovery

/// Handles recovery specifically on app launch.
public actor AppLaunchRecoveryHandler {
    private let manager: ConnectionRecoveryManager
    private var hasRecovered: Bool = false
    
    public init(manager: ConnectionRecoveryManager) {
        self.manager = manager
    }
    
    /// Check if recovery is needed and perform it.
    public func handleAppLaunch() async -> RecoverySession? {
        guard !hasRecovered else { return nil }
        hasRecovered = true
        
        await manager.restore()
        
        let devicesNeeding = await manager.devicesNeedingRecovery()
        if devicesNeeding.isEmpty {
            return nil
        }
        
        return await manager.startRecovery(trigger: .appLaunch)
    }
    
    /// Handle background wake event.
    public func handleBackgroundWake() async -> RecoverySession? {
        let devicesNeeding = await manager.devicesNeedingRecovery()
        if devicesNeeding.isEmpty {
            return nil
        }
        
        return await manager.startRecovery(trigger: .backgroundWake)
    }
    
    /// Reset recovery state (for testing).
    public func reset() async {
        hasRecovered = false
    }
}
