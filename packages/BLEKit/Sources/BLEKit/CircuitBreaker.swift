// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CircuitBreaker.swift
// BLEKit
//
// Created for T1Pal - BLE-CONN-003
// Circuit breaker pattern for BLE connection resilience

import Foundation

// MARK: - Circuit Breaker State

/// States for the circuit breaker pattern
public enum CircuitBreakerState: String, Sendable, CaseIterable {
    /// Normal operation - requests allowed
    case closed
    
    /// Circuit tripped - requests rejected
    case open
    
    /// Testing recovery - limited requests allowed
    case halfOpen
}

// MARK: - Circuit Breaker Configuration

/// Configuration for circuit breaker behavior
public struct CircuitBreakerConfig: Sendable, Equatable {
    /// Number of failures before tripping (closed → open)
    public let failureThreshold: Int
    
    /// Number of successes in half-open to reset (half-open → closed)
    public let successThreshold: Int
    
    /// Time to wait before attempting recovery (open → half-open)
    public let resetTimeout: TimeInterval
    
    /// Time window for counting failures
    public let failureWindow: TimeInterval
    
    /// Maximum requests allowed in half-open state
    public let halfOpenRequests: Int
    
    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        resetTimeout: TimeInterval = 30,
        failureWindow: TimeInterval = 60,
        halfOpenRequests: Int = 3
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.successThreshold = max(1, successThreshold)
        self.resetTimeout = max(0.01, resetTimeout)
        self.failureWindow = max(0.01, failureWindow)
        self.halfOpenRequests = max(1, halfOpenRequests)
    }
    
    // MARK: - Presets
    
    /// Default BLE configuration - moderate sensitivity
    public static let bleDefault = CircuitBreakerConfig(
        failureThreshold: 5,
        successThreshold: 2,
        resetTimeout: 30,
        failureWindow: 60,
        halfOpenRequests: 3
    )
    
    /// Aggressive - trips quickly, recovers slowly
    public static let aggressive = CircuitBreakerConfig(
        failureThreshold: 3,
        successThreshold: 3,
        resetTimeout: 60,
        failureWindow: 30,
        halfOpenRequests: 2
    )
    
    /// Conservative - tolerates more failures
    public static let conservative = CircuitBreakerConfig(
        failureThreshold: 10,
        successThreshold: 1,
        resetTimeout: 15,
        failureWindow: 120,
        halfOpenRequests: 5
    )
    
    /// Testing configuration with short timeouts
    public static let testing = CircuitBreakerConfig(
        failureThreshold: 2,
        successThreshold: 1,
        resetTimeout: 1,
        failureWindow: 5,
        halfOpenRequests: 1
    )
}

// MARK: - Circuit Breaker Event

/// Events emitted by the circuit breaker
public enum CircuitBreakerEvent: Sendable, Equatable {
    /// Circuit breaker state changed
    case stateChanged(from: CircuitBreakerState, to: CircuitBreakerState)
    
    /// Request was rejected due to open circuit
    case requestRejected
    
    /// Failure recorded
    case failureRecorded(count: Int, threshold: Int)
    
    /// Success recorded
    case successRecorded(count: Int, threshold: Int)
    
    /// Circuit breaker reset
    case reset
}

// MARK: - Circuit Breaker Error

/// Errors thrown by circuit breaker
public enum CircuitBreakerError: Error, Sendable, LocalizedError {
    /// Circuit is open, request rejected
    case circuitOpen(retryAfter: TimeInterval)
    
    /// Half-open request limit exceeded
    case halfOpenLimitExceeded
    
    public var errorDescription: String? {
        switch self {
        case .circuitOpen(let retryAfter):
            return "Circuit breaker is open. Retry after \(Int(retryAfter)) seconds."
        case .halfOpenLimitExceeded:
            return "Too many requests in half-open state."
        }
    }
}

// MARK: - Circuit Breaker

/// Circuit breaker for managing connection failures
public actor CircuitBreaker {
    
    // MARK: - Properties
    
    private let config: CircuitBreakerConfig
    private var state: CircuitBreakerState = .closed
    private var failureTimestamps: [Date] = []
    private var halfOpenSuccesses: Int = 0
    private var halfOpenRequests: Int = 0
    private var lastStateChange: Date = Date()
    private var eventHandler: (@Sendable (CircuitBreakerEvent) -> Void)?
    
    // MARK: - Initialization
    
    public init(config: CircuitBreakerConfig = .bleDefault) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Current state of the circuit breaker
    public var currentState: CircuitBreakerState {
        state
    }
    
    /// Set event handler for state changes
    public func setEventHandler(_ handler: @escaping @Sendable (CircuitBreakerEvent) -> Void) {
        self.eventHandler = handler
    }
    
    /// Check if a request can proceed
    /// - Returns: true if request allowed, throws if rejected
    public func canExecute() throws -> Bool {
        let now = Date()
        
        switch state {
        case .closed:
            return true
            
        case .open:
            // Check if reset timeout has passed
            let timeSinceOpen = now.timeIntervalSince(lastStateChange)
            if timeSinceOpen >= config.resetTimeout {
                transition(to: .halfOpen)
                halfOpenRequests = 1
                return true
            } else {
                let retryAfter = config.resetTimeout - timeSinceOpen
                emit(.requestRejected)
                throw CircuitBreakerError.circuitOpen(retryAfter: retryAfter)
            }
            
        case .halfOpen:
            if halfOpenRequests < config.halfOpenRequests {
                halfOpenRequests += 1
                return true
            } else {
                throw CircuitBreakerError.halfOpenLimitExceeded
            }
        }
    }
    
    /// Record a successful operation
    public func recordSuccess() {
        switch state {
        case .closed:
            // In closed state, success just keeps things working
            break
            
        case .open:
            // Shouldn't happen, but ignore
            break
            
        case .halfOpen:
            halfOpenSuccesses += 1
            emit(.successRecorded(count: halfOpenSuccesses, threshold: config.successThreshold))
            
            if halfOpenSuccesses >= config.successThreshold {
                transition(to: .closed)
            }
        }
    }
    
    /// Record a failed operation
    public func recordFailure() {
        let now = Date()
        
        switch state {
        case .closed:
            // Add failure timestamp
            failureTimestamps.append(now)
            pruneOldFailures(before: now)
            
            let count = failureTimestamps.count
            emit(.failureRecorded(count: count, threshold: config.failureThreshold))
            
            if count >= config.failureThreshold {
                transition(to: .open)
            }
            
        case .open:
            // Already open, ignore
            break
            
        case .halfOpen:
            // Any failure in half-open trips back to open
            transition(to: .open)
        }
    }
    
    /// Force reset to closed state
    public func reset() {
        failureTimestamps.removeAll()
        halfOpenSuccesses = 0
        halfOpenRequests = 0
        
        if state != .closed {
            transition(to: .closed)
        }
        
        emit(.reset)
    }
    
    /// Get time until circuit breaker may transition from open
    public func timeUntilRetry() -> TimeInterval? {
        guard state == .open else { return nil }
        
        let timeSinceOpen = Date().timeIntervalSince(lastStateChange)
        let remaining = config.resetTimeout - timeSinceOpen
        return max(0, remaining)
    }
    
    /// Get current failure count within window
    public func failureCount() -> Int {
        pruneOldFailures(before: Date())
        return failureTimestamps.count
    }
    
    /// Get statistics about circuit breaker state
    public func statistics() -> CircuitBreakerStatistics {
        CircuitBreakerStatistics(
            state: state,
            failureCount: failureTimestamps.count,
            failureThreshold: config.failureThreshold,
            halfOpenSuccesses: halfOpenSuccesses,
            successThreshold: config.successThreshold,
            timeSinceStateChange: Date().timeIntervalSince(lastStateChange),
            timeUntilRetry: timeUntilRetry()
        )
    }
    
    // MARK: - Private Helpers
    
    private func transition(to newState: CircuitBreakerState) {
        let oldState = state
        state = newState
        lastStateChange = Date()
        
        // Reset counters on transition
        switch newState {
        case .closed:
            failureTimestamps.removeAll()
            halfOpenSuccesses = 0
            halfOpenRequests = 0
            
        case .open:
            halfOpenSuccesses = 0
            halfOpenRequests = 0
            
        case .halfOpen:
            halfOpenSuccesses = 0
            halfOpenRequests = 0
        }
        
        emit(.stateChanged(from: oldState, to: newState))
    }
    
    private func pruneOldFailures(before now: Date) {
        let cutoff = now.addingTimeInterval(-config.failureWindow)
        failureTimestamps.removeAll { $0 < cutoff }
    }
    
    private func emit(_ event: CircuitBreakerEvent) {
        eventHandler?(event)
    }
}

// MARK: - Statistics

/// Statistics about circuit breaker state
public struct CircuitBreakerStatistics: Sendable, Equatable {
    public let state: CircuitBreakerState
    public let failureCount: Int
    public let failureThreshold: Int
    public let halfOpenSuccesses: Int
    public let successThreshold: Int
    public let timeSinceStateChange: TimeInterval
    public let timeUntilRetry: TimeInterval?
    
    /// Percentage of failure threshold reached (0-100)
    public var failurePercentage: Double {
        guard failureThreshold > 0 else { return 0 }
        return min(100, Double(failureCount) / Double(failureThreshold) * 100)
    }
    
    /// Whether circuit is allowing requests
    public var isAllowingRequests: Bool {
        state != .open
    }
}

// MARK: - Circuit Breaker Wrapper

/// Convenience wrapper for executing operations with circuit breaker protection
public actor CircuitBreakerExecutor {
    private let circuitBreaker: CircuitBreaker
    
    public init(config: CircuitBreakerConfig = .bleDefault) {
        self.circuitBreaker = CircuitBreaker(config: config)
    }
    
    /// Execute an operation with circuit breaker protection
    public func execute<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        // Check if we can execute
        _ = try await circuitBreaker.canExecute()
        
        do {
            let result = try await operation()
            await circuitBreaker.recordSuccess()
            return result
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }
    
    /// Get current state
    public var state: CircuitBreakerState {
        get async {
            await circuitBreaker.currentState
        }
    }
    
    /// Get statistics
    public func statistics() async -> CircuitBreakerStatistics {
        await circuitBreaker.statistics()
    }
    
    /// Reset the circuit breaker
    public func reset() async {
        await circuitBreaker.reset()
    }
}

// MARK: - Device-Specific Circuit Breakers

/// Manages circuit breakers for multiple BLE devices
public actor DeviceCircuitBreakerManager {
    private var breakers: [String: CircuitBreaker] = [:]
    private let defaultConfig: CircuitBreakerConfig
    
    public init(config: CircuitBreakerConfig = .bleDefault) {
        self.defaultConfig = config
    }
    
    /// Get or create circuit breaker for a device
    public func breaker(for deviceId: String) -> CircuitBreaker {
        if let existing = breakers[deviceId] {
            return existing
        }
        
        let breaker = CircuitBreaker(config: defaultConfig)
        breakers[deviceId] = breaker
        return breaker
    }
    
    /// Check if device connection can proceed
    public func canConnect(to deviceId: String) async throws -> Bool {
        try await breaker(for: deviceId).canExecute()
    }
    
    /// Record successful connection/operation
    public func recordSuccess(for deviceId: String) async {
        await breaker(for: deviceId).recordSuccess()
    }
    
    /// Record failed connection/operation
    public func recordFailure(for deviceId: String) async {
        await breaker(for: deviceId).recordFailure()
    }
    
    /// Get state for a device
    public func state(for deviceId: String) async -> CircuitBreakerState {
        await breaker(for: deviceId).currentState
    }
    
    /// Get all device states
    public func allStates() async -> [String: CircuitBreakerState] {
        var states: [String: CircuitBreakerState] = [:]
        for (id, breaker) in breakers {
            states[id] = await breaker.currentState
        }
        return states
    }
    
    /// Reset circuit breaker for a device
    public func reset(for deviceId: String) async {
        await breaker(for: deviceId).reset()
    }
    
    /// Reset all circuit breakers
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
    }
    
    /// Remove circuit breaker for a device
    public func remove(deviceId: String) {
        breakers.removeValue(forKey: deviceId)
    }
    
    /// Get count of open circuits
    public func openCircuitCount() async -> Int {
        var count = 0
        for breaker in breakers.values {
            if await breaker.currentState == .open {
                count += 1
            }
        }
        return count
    }
}
