// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// HeartbeatMonitor.swift
// BLEKit
//
// Created for T1Pal - BLE-CONN-004
// Async keepalive heartbeat to detect silent disconnects

import Foundation

// MARK: - Heartbeat Configuration

/// Configuration for heartbeat monitoring
public struct HeartbeatConfig: Sendable, Equatable {
    /// Interval between heartbeat checks
    public let interval: TimeInterval
    
    /// Number of missed heartbeats before declaring disconnect
    public let missedThreshold: Int
    
    /// Timeout for individual heartbeat response
    public let responseTimeout: TimeInterval
    
    /// Whether to automatically restart after disconnect detection
    public let autoRestart: Bool
    
    public init(
        interval: TimeInterval = 30,
        missedThreshold: Int = 3,
        responseTimeout: TimeInterval = 10,
        autoRestart: Bool = true
    ) {
        self.interval = max(0.01, interval)
        self.missedThreshold = max(1, missedThreshold)
        self.responseTimeout = max(0.01, responseTimeout)
        self.autoRestart = autoRestart
    }
    
    // MARK: - Presets
    
    /// Default BLE heartbeat - moderate frequency
    public static let bleDefault = HeartbeatConfig(
        interval: 30,
        missedThreshold: 3,
        responseTimeout: 10,
        autoRestart: true
    )
    
    /// Aggressive monitoring for critical connections
    public static let aggressive = HeartbeatConfig(
        interval: 10,
        missedThreshold: 2,
        responseTimeout: 5,
        autoRestart: true
    )
    
    /// Conservative monitoring to save battery
    public static let conservative = HeartbeatConfig(
        interval: 60,
        missedThreshold: 5,
        responseTimeout: 15,
        autoRestart: true
    )
    
    /// Testing configuration with fast intervals
    public static let testing = HeartbeatConfig(
        interval: 0.1,
        missedThreshold: 2,
        responseTimeout: 0.05,
        autoRestart: false
    )
}

// MARK: - Heartbeat State

/// Current state of the heartbeat monitor
public enum HeartbeatState: String, Sendable, CaseIterable {
    /// Monitor is stopped
    case stopped
    
    /// Monitor is running, connection healthy
    case healthy
    
    /// Heartbeats being missed, connection degraded
    case degraded
    
    /// Too many missed heartbeats, connection lost
    case disconnected
}

// MARK: - Heartbeat Event

/// Events emitted by the heartbeat monitor
public enum HeartbeatEvent: Sendable, Equatable {
    /// Heartbeat succeeded
    case heartbeatSuccess(latency: TimeInterval)
    
    /// Heartbeat failed/timed out
    case heartbeatMissed(consecutiveMisses: Int, threshold: Int)
    
    /// State changed
    case stateChanged(from: HeartbeatState, to: HeartbeatState)
    
    /// Silent disconnect detected
    case silentDisconnectDetected
    
    /// Monitor started
    case started
    
    /// Monitor stopped
    case stopped
}

// MARK: - Heartbeat Result

/// Result of a single heartbeat check
public struct HeartbeatResult: Sendable, Equatable {
    public let success: Bool
    public let latency: TimeInterval?
    public let timestamp: Date
    public let error: String?
    
    public init(success: Bool, latency: TimeInterval? = nil, error: String? = nil) {
        self.success = success
        self.latency = latency
        self.timestamp = Date()
        self.error = error
    }
    
    public static func success(latency: TimeInterval) -> HeartbeatResult {
        HeartbeatResult(success: true, latency: latency)
    }
    
    public static func failure(error: String) -> HeartbeatResult {
        HeartbeatResult(success: false, error: error)
    }
}

// MARK: - Heartbeat Check Protocol

/// Protocol for performing actual heartbeat checks
public protocol HeartbeatChecker: Sendable {
    /// Perform a heartbeat check
    /// - Returns: true if device responded, false otherwise
    func performHeartbeat() async throws -> Bool
}

// MARK: - Heartbeat Monitor

/// Monitors connection health via periodic heartbeats
public actor HeartbeatMonitor {
    
    // MARK: - Properties
    
    private let config: HeartbeatConfig
    private let deviceId: String
    private var state: HeartbeatState = .stopped
    private var consecutiveMisses: Int = 0
    private var heartbeatTask: Task<Void, Never>?
    private var lastSuccessfulHeartbeat: Date?
    private var totalHeartbeats: Int = 0
    private var successfulHeartbeats: Int = 0
    private var eventHandler: (@Sendable (HeartbeatEvent) -> Void)?
    private var heartbeatChecker: HeartbeatChecker?
    
    // MARK: - Initialization
    
    public init(deviceId: String, config: HeartbeatConfig = .bleDefault) {
        self.deviceId = deviceId
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Current state of the monitor
    public var currentState: HeartbeatState {
        state
    }
    
    /// Whether the monitor is running
    public var isRunning: Bool {
        heartbeatTask != nil && !heartbeatTask!.isCancelled
    }
    
    /// Set event handler for heartbeat events
    public func setEventHandler(_ handler: @escaping @Sendable (HeartbeatEvent) -> Void) {
        self.eventHandler = handler
    }
    
    /// Set the heartbeat checker implementation
    public func setHeartbeatChecker(_ checker: HeartbeatChecker) {
        self.heartbeatChecker = checker
    }
    
    /// Start the heartbeat monitor
    public func start() {
        guard heartbeatTask == nil else { return }
        
        consecutiveMisses = 0
        transition(to: .healthy)
        emit(.started)
        
        heartbeatTask = Task { [weak self] in
            await self?.runHeartbeatLoop()
        }
    }
    
    /// Stop the heartbeat monitor
    public func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        transition(to: .stopped)
        emit(.stopped)
    }
    
    /// Manually trigger a heartbeat check
    public func checkNow() async -> HeartbeatResult {
        return await performHeartbeatCheck()
    }
    
    /// Report external heartbeat success (e.g., from data received)
    public func reportHeartbeat() {
        recordSuccess(latency: 0)
    }
    
    /// Get statistics about heartbeat history
    public func statistics() -> HeartbeatStatistics {
        HeartbeatStatistics(
            state: state,
            deviceId: deviceId,
            consecutiveMisses: consecutiveMisses,
            missedThreshold: config.missedThreshold,
            totalHeartbeats: totalHeartbeats,
            successfulHeartbeats: successfulHeartbeats,
            lastSuccessfulHeartbeat: lastSuccessfulHeartbeat,
            successRate: totalHeartbeats > 0 
                ? Double(successfulHeartbeats) / Double(totalHeartbeats) 
                : 1.0
        )
    }
    
    /// Reset statistics
    public func resetStatistics() {
        totalHeartbeats = 0
        successfulHeartbeats = 0
        consecutiveMisses = 0
        lastSuccessfulHeartbeat = nil
    }
    
    // MARK: - Private Implementation
    
    private func runHeartbeatLoop() async {
        while !Task.isCancelled {
            // Wait for interval
            do {
                try await Task.sleep(for: .seconds(config.interval))
            } catch {
                break // Cancelled
            }
            
            guard !Task.isCancelled else { break }
            
            // Perform heartbeat
            _ = await performHeartbeatCheck()
            
            // Check if we should stop
            if state == .disconnected && !config.autoRestart {
                break
            }
        }
    }
    
    private func performHeartbeatCheck() async -> HeartbeatResult {
        totalHeartbeats += 1
        
        let startTime = Date()
        var success = false
        var errorMessage: String?
        
        if let checker = heartbeatChecker {
            do {
                // Race heartbeat against timeout
                success = try await withThrowingTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        try await checker.performHeartbeat()
                    }
                    
                    group.addTask {
                        try await Task.sleep(for: .seconds(self.config.responseTimeout))
                        throw HeartbeatError.timeout
                    }
                    
                    // Return first result
                    if let result = try await group.next() {
                        group.cancelAll()
                        return result
                    }
                    return false
                }
            } catch is HeartbeatError {
                errorMessage = "Heartbeat timeout"
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // No checker configured - simulate success for testing
            success = true
        }
        
        let latency = Date().timeIntervalSince(startTime)
        
        if success {
            recordSuccess(latency: latency)
            return .success(latency: latency)
        } else {
            recordMiss()
            return .failure(error: errorMessage ?? "Unknown error")
        }
    }
    
    private func recordSuccess(latency: TimeInterval) {
        successfulHeartbeats += 1
        consecutiveMisses = 0
        lastSuccessfulHeartbeat = Date()
        
        emit(.heartbeatSuccess(latency: latency))
        
        if state != .healthy && state != .stopped {
            transition(to: .healthy)
        }
    }
    
    private func recordMiss() {
        consecutiveMisses += 1
        
        emit(.heartbeatMissed(
            consecutiveMisses: consecutiveMisses,
            threshold: config.missedThreshold
        ))
        
        if consecutiveMisses >= config.missedThreshold {
            if state != .disconnected {
                emit(.silentDisconnectDetected)
                transition(to: .disconnected)
            }
        } else if state == .healthy {
            transition(to: .degraded)
        }
    }
    
    private func transition(to newState: HeartbeatState) {
        let oldState = state
        guard oldState != newState else { return }
        
        state = newState
        emit(.stateChanged(from: oldState, to: newState))
    }
    
    private func emit(_ event: HeartbeatEvent) {
        eventHandler?(event)
    }
}

// MARK: - Heartbeat Error

enum HeartbeatError: Error {
    case timeout
}

// MARK: - Statistics

/// Statistics about heartbeat monitor state
public struct HeartbeatStatistics: Sendable, Equatable {
    public let state: HeartbeatState
    public let deviceId: String
    public let consecutiveMisses: Int
    public let missedThreshold: Int
    public let totalHeartbeats: Int
    public let successfulHeartbeats: Int
    public let lastSuccessfulHeartbeat: Date?
    public let successRate: Double
    
    /// Whether connection is considered healthy
    public var isHealthy: Bool {
        state == .healthy
    }
    
    /// Time since last successful heartbeat
    public var timeSinceLastSuccess: TimeInterval? {
        guard let last = lastSuccessfulHeartbeat else { return nil }
        return Date().timeIntervalSince(last)
    }
}

// MARK: - Multi-Device Manager

/// Manages heartbeat monitors for multiple devices
public actor HeartbeatManager {
    private var monitors: [String: HeartbeatMonitor] = [:]
    private let defaultConfig: HeartbeatConfig
    
    public init(config: HeartbeatConfig = .bleDefault) {
        self.defaultConfig = config
    }
    
    /// Get or create monitor for a device
    public func monitor(for deviceId: String) -> HeartbeatMonitor {
        if let existing = monitors[deviceId] {
            return existing
        }
        
        let monitor = HeartbeatMonitor(deviceId: deviceId, config: defaultConfig)
        monitors[deviceId] = monitor
        return monitor
    }
    
    /// Start monitoring a device
    public func startMonitoring(deviceId: String) async {
        await monitor(for: deviceId).start()
    }
    
    /// Stop monitoring a device
    public func stopMonitoring(deviceId: String) async {
        await monitors[deviceId]?.stop()
    }
    
    /// Stop all monitors
    public func stopAll() async {
        for monitor in monitors.values {
            await monitor.stop()
        }
    }
    
    /// Get state for a device
    public func state(for deviceId: String) async -> HeartbeatState {
        await monitors[deviceId]?.currentState ?? .stopped
    }
    
    /// Get all device states
    public func allStates() async -> [String: HeartbeatState] {
        var states: [String: HeartbeatState] = [:]
        for (id, monitor) in monitors {
            states[id] = await monitor.currentState
        }
        return states
    }
    
    /// Get count of disconnected devices
    public func disconnectedCount() async -> Int {
        var count = 0
        for monitor in monitors.values {
            if await monitor.currentState == .disconnected {
                count += 1
            }
        }
        return count
    }
    
    /// Remove monitor for a device
    public func remove(deviceId: String) async {
        await monitors[deviceId]?.stop()
        monitors.removeValue(forKey: deviceId)
    }
    
    /// Report external heartbeat for a device
    public func reportHeartbeat(for deviceId: String) async {
        await monitors[deviceId]?.reportHeartbeat()
    }
}

// MARK: - Mock Heartbeat Checker

/// Mock heartbeat checker for testing
public final class MockHeartbeatChecker: HeartbeatChecker, @unchecked Sendable {
    private var shouldSucceed: Bool
    private var delay: TimeInterval
    private let lock = NSLock()
    
    public init(shouldSucceed: Bool = true, delay: TimeInterval = 0) {
        self.shouldSucceed = shouldSucceed
        self.delay = delay
    }
    
    public func setShouldSucceed(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        shouldSucceed = value
    }
    
    public func setDelay(_ value: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        delay = value
    }
    
    public func performHeartbeat() async throws -> Bool {
        // Use withLock for Swift 6 compatibility (BUILD-002)
        let (currentDelay, currentSuccess) = lock.withLock {
            (delay, shouldSucceed)
        }
        
        if currentDelay > 0 {
            try await Task.sleep(for: .seconds(currentDelay))
        }
        return currentSuccess
    }
}
