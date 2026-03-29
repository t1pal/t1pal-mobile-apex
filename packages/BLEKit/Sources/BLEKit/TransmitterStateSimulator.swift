// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TransmitterStateSimulator.swift
// BLEKit
//
// Simulates transmitter session lifecycle with warmup, active, and expiry states.
// Provides state transition callbacks for realistic CGM behavior simulation.
// Trace: PRD-007 REQ-SIM-007

import Foundation

// MARK: - State Transition

/// A state transition event
public struct StateTransition: Sendable, Equatable {
    /// Previous state
    public let from: TransmitterState
    
    /// New state
    public let to: TransmitterState
    
    /// Time of transition
    public let timestamp: Date
    
    /// Reason for transition
    public let reason: TransitionReason
    
    public init(from: TransmitterState, to: TransmitterState, timestamp: Date = Date(), reason: TransitionReason) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
        self.reason = reason
    }
}

// MARK: - Transition Reason

/// Reason for a state transition
public enum TransitionReason: String, Sendable, Codable, Equatable {
    /// Sensor was started/inserted
    case sensorStarted
    
    /// Warmup period completed
    case warmupComplete
    
    /// Session expired (max duration reached)
    case sessionExpired
    
    /// Sensor was manually stopped
    case sensorStopped
    
    /// Sensor failure detected
    case sensorFailed
    
    /// Battery level critically low
    case batteryLow
    
    /// Error condition
    case error
    
    /// Session was reset/restarted
    case reset
}

// MARK: - State Observer

/// Protocol for observing state transitions
public protocol TransmitterStateObserver: AnyObject, Sendable {
    /// Called when state changes
    func stateDidChange(_ transition: StateTransition)
}

// MARK: - State Simulator Configuration

/// Configuration for the state simulator
public struct StateSimulatorConfig: Sendable {
    /// Warmup duration in seconds
    public let warmupDuration: TimeInterval
    
    /// Maximum session duration in seconds
    public let maxSessionDuration: TimeInterval
    
    /// Whether to auto-transition from warmup to active
    public let autoTransitionWarmup: Bool
    
    /// Whether to auto-transition to expired
    public let autoTransitionExpiry: Bool
    
    /// Time acceleration factor (1.0 = real-time, 60.0 = 1 min = 1 sec)
    public let timeAcceleration: Double
    
    /// Create configuration
    public init(
        warmupDuration: TimeInterval = 2 * 60 * 60,  // 2 hours
        maxSessionDuration: TimeInterval = 10 * 24 * 60 * 60,  // 10 days
        autoTransitionWarmup: Bool = true,
        autoTransitionExpiry: Bool = true,
        timeAcceleration: Double = 1.0
    ) {
        self.warmupDuration = warmupDuration
        self.maxSessionDuration = maxSessionDuration
        self.autoTransitionWarmup = autoTransitionWarmup
        self.autoTransitionExpiry = autoTransitionExpiry
        self.timeAcceleration = Swift.max(0.001, timeAcceleration)
    }
    
    /// Configuration for G6 transmitter
    public static let g6 = StateSimulatorConfig(
        warmupDuration: 2 * 60 * 60,
        maxSessionDuration: 10 * 24 * 60 * 60
    )
    
    /// Configuration for G7 transmitter
    public static let g7 = StateSimulatorConfig(
        warmupDuration: 30 * 60,
        maxSessionDuration: 10.5 * 24 * 60 * 60
    )
    
    /// Fast configuration for testing (10 sec warmup, 60 sec session)
    public static let fast = StateSimulatorConfig(
        warmupDuration: 10,
        maxSessionDuration: 60,
        timeAcceleration: 1.0
    )
    
    /// Instant configuration for testing (no warmup, 1 hour session)
    public static let instant = StateSimulatorConfig(
        warmupDuration: 0,
        maxSessionDuration: 3600
    )
}

// MARK: - Transmitter State Simulator

/// Simulates transmitter session lifecycle with automatic state transitions
///
/// ## Usage
/// ```swift
/// let simulator = TransmitterStateSimulator(config: .g6)
///
/// // Start a sensor session
/// simulator.startSensor()
///
/// // Check current state
/// switch simulator.state {
/// case .warmup:
///     print("Warming up, \(simulator.warmupTimeRemaining)s remaining")
/// case .active:
///     print("Active, \(simulator.sessionTimeRemaining)s remaining")
/// case .expired:
///     print("Session expired")
/// }
///
/// // Force transition (for testing)
/// simulator.transitionTo(.active, reason: .warmupComplete)
/// ```
public final class TransmitterStateSimulator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Current configuration
    public let config: StateSimulatorConfig
    
    /// Current state
    public private(set) var state: TransmitterState = .inactive
    
    /// Session start time (nil if no active session)
    public private(set) var sessionStartTime: Date?
    
    /// Warmup end time (nil if not in warmup or no session)
    public private(set) var warmupEndTime: Date?
    
    /// Session end time (nil if no session)
    public private(set) var sessionEndTime: Date?
    
    /// History of state transitions
    public private(set) var transitionHistory: [StateTransition] = []
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Observers
    private var observers: [ObjectIdentifier: WeakObserver] = [:]
    
    /// Timer for auto-transitions
    private var transitionTimer: Timer?
    
    // MARK: - Weak Observer Wrapper
    
    private struct WeakObserver {
        weak var observer: (any TransmitterStateObserver)?
    }
    
    // MARK: - Initialization
    
    /// Create a state simulator
    /// - Parameter config: Configuration for timing and behavior
    public init(config: StateSimulatorConfig = .g6) {
        self.config = config
    }
    
    deinit {
        transitionTimer?.invalidate()
    }
    
    // MARK: - Session Control
    
    /// Start a new sensor session
    /// - Parameter startTime: Optional start time (defaults to now)
    public func startSensor(at startTime: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        
        let previousState = state
        sessionStartTime = startTime
        
        if config.warmupDuration > 0 {
            warmupEndTime = startTime.addingTimeInterval(config.warmupDuration / config.timeAcceleration)
            state = .warmup
        } else {
            warmupEndTime = startTime
            state = .active
        }
        
        sessionEndTime = startTime.addingTimeInterval(config.maxSessionDuration / config.timeAcceleration)
        
        let reason: TransitionReason = config.warmupDuration > 0 ? .sensorStarted : .warmupComplete
        recordTransition(from: previousState, to: state, reason: reason)
        
        scheduleAutoTransitions()
    }
    
    /// Stop the current sensor session
    public func stopSensor() {
        lock.lock()
        defer { lock.unlock() }
        
        let previousState = state
        state = .inactive
        sessionStartTime = nil
        warmupEndTime = nil
        sessionEndTime = nil
        
        transitionTimer?.invalidate()
        transitionTimer = nil
        
        if previousState != .inactive {
            recordTransition(from: previousState, to: .inactive, reason: .sensorStopped)
        }
    }
    
    /// Reset the simulator to initial state
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        let previousState = state
        state = .inactive
        sessionStartTime = nil
        warmupEndTime = nil
        sessionEndTime = nil
        transitionHistory.removeAll()
        
        transitionTimer?.invalidate()
        transitionTimer = nil
        
        if previousState != .inactive {
            recordTransition(from: previousState, to: .inactive, reason: .reset)
        }
    }
    
    // MARK: - Manual Transitions
    
    /// Manually transition to a new state
    /// - Parameters:
    ///   - newState: Target state
    ///   - reason: Reason for transition
    public func transitionTo(_ newState: TransmitterState, reason: TransitionReason) {
        lock.lock()
        defer { lock.unlock() }
        
        guard newState != state else { return }
        
        let previousState = state
        state = newState
        
        recordTransition(from: previousState, to: newState, reason: reason)
        
        // Update timers based on new state
        if newState == .inactive || newState == .expired || newState == .error {
            transitionTimer?.invalidate()
            transitionTimer = nil
        }
    }
    
    /// Simulate sensor failure
    public func simulateFailure() {
        transitionTo(.error, reason: .sensorFailed)
    }
    
    /// Simulate low battery
    public func simulateLowBattery() {
        transitionTo(.lowBattery, reason: .batteryLow)
    }
    
    // MARK: - Time Calculations
    
    /// Current session elapsed time (accounting for acceleration)
    public var sessionElapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start) * config.timeAcceleration
    }
    
    /// Time remaining in warmup period
    public var warmupTimeRemaining: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        guard state == .warmup, let end = warmupEndTime else { return 0 }
        return Swift.max(0, end.timeIntervalSince(Date()))
    }
    
    /// Time remaining in session
    public var sessionTimeRemaining: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        guard let end = sessionEndTime else { return 0 }
        return Swift.max(0, end.timeIntervalSince(Date()))
    }
    
    /// Progress through warmup (0.0 to 1.0)
    public var warmupProgress: Double {
        guard config.warmupDuration > 0 else { return 1.0 }
        let elapsed = sessionElapsed
        return Swift.min(1.0, elapsed / config.warmupDuration)
    }
    
    /// Progress through session (0.0 to 1.0)
    public var sessionProgress: Double {
        guard config.maxSessionDuration > 0 else { return 0.0 }
        let elapsed = sessionElapsed
        return Swift.min(1.0, elapsed / config.maxSessionDuration)
    }
    
    /// Whether the session is still valid (not expired or failed)
    public var isSessionValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .warmup || state == .active
    }
    
    // MARK: - Observers
    
    /// Add an observer for state changes
    public func addObserver(_ observer: some TransmitterStateObserver) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(observer)
        observers[id] = WeakObserver(observer: observer)
    }
    
    /// Remove an observer
    public func removeObserver(_ observer: some TransmitterStateObserver) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(observer)
        observers.removeValue(forKey: id)
    }
    
    // MARK: - Private Methods
    
    private func recordTransition(from: TransmitterState, to: TransmitterState, reason: TransitionReason) {
        let transition = StateTransition(from: from, to: to, reason: reason)
        transitionHistory.append(transition)
        notifyObservers(transition)
    }
    
    private func notifyObservers(_ transition: StateTransition) {
        // Clean up nil observers and notify active ones
        var toRemove: [ObjectIdentifier] = []
        var activeObservers: [any TransmitterStateObserver] = []
        
        for (id, weak) in observers {
            if let observer = weak.observer {
                activeObservers.append(observer)
            } else {
                toRemove.append(id)
            }
        }
        
        for id in toRemove {
            observers.removeValue(forKey: id)
        }
        
        // Notify outside lock
        lock.unlock()
        for observer in activeObservers {
            observer.stateDidChange(transition)
        }
        lock.lock()
    }
    
    private func scheduleAutoTransitions() {
        transitionTimer?.invalidate()
        
        guard config.autoTransitionWarmup || config.autoTransitionExpiry else { return }
        
        // Schedule warmup completion
        if state == .warmup, config.autoTransitionWarmup, let warmupEnd = warmupEndTime {
            let delay = warmupEnd.timeIntervalSince(Date())
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.checkWarmupComplete()
                }
            } else {
                checkWarmupComplete()
            }
        }
        
        // Schedule session expiry
        if config.autoTransitionExpiry, let sessionEnd = sessionEndTime {
            let delay = sessionEnd.timeIntervalSince(Date())
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.checkSessionExpiry()
                }
            }
        }
    }
    
    private func checkWarmupComplete() {
        lock.lock()
        defer { lock.unlock() }
        
        guard state == .warmup else { return }
        
        state = .active
        recordTransition(from: .warmup, to: .active, reason: .warmupComplete)
    }
    
    private func checkSessionExpiry() {
        lock.lock()
        defer { lock.unlock() }
        
        guard state == .warmup || state == .active else { return }
        
        let previousState = state
        state = .expired
        recordTransition(from: previousState, to: .expired, reason: .sessionExpired)
    }
    
    // MARK: - Update (Manual Tick)
    
    /// Manually check and update state (for non-timer scenarios)
    public func update() {
        lock.lock()
        let currentState = state
        let warmupEnd = warmupEndTime
        let sessionEnd = sessionEndTime
        lock.unlock()
        
        let now = Date()
        
        // Check warmup completion
        if currentState == .warmup, let end = warmupEnd, now >= end {
            checkWarmupComplete()
            return
        }
        
        // Check session expiry
        if (currentState == .warmup || currentState == .active),
           let end = sessionEnd, now >= end {
            checkSessionExpiry()
        }
    }
}

// MARK: - Session Snapshot

/// A snapshot of the current session state
public struct SessionSnapshot: Sendable {
    public let state: TransmitterState
    public let sessionStartTime: Date?
    public let sessionElapsed: TimeInterval
    public let warmupProgress: Double
    public let sessionProgress: Double
    public let warmupTimeRemaining: TimeInterval
    public let sessionTimeRemaining: TimeInterval
    public let isValid: Bool
    
    public init(from simulator: TransmitterStateSimulator) {
        self.state = simulator.state
        self.sessionStartTime = simulator.sessionStartTime
        self.sessionElapsed = simulator.sessionElapsed
        self.warmupProgress = simulator.warmupProgress
        self.sessionProgress = simulator.sessionProgress
        self.warmupTimeRemaining = simulator.warmupTimeRemaining
        self.sessionTimeRemaining = simulator.sessionTimeRemaining
        self.isValid = simulator.isSessionValid
    }
}

extension TransmitterStateSimulator {
    /// Get a snapshot of the current session state
    public var snapshot: SessionSnapshot {
        SessionSnapshot(from: self)
    }
}
