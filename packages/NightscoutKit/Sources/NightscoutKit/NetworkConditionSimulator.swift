// NetworkConditionSimulator.swift
// NightscoutKit
//
// SPDX-License-Identifier: AGPL-3.0-or-later
// Trace: INT-006

import Foundation

// MARK: - Network Condition Types

/// Represents a network condition that can be simulated.
public enum NetworkCondition: Sendable, Equatable {
    /// Normal network conditions (no delays, no errors)
    case normal
    
    /// Slow network with configurable latency
    case slow(latencyMs: UInt)
    
    /// Very slow network (3G-like conditions)
    case veryPoor
    
    /// Intermittent connection with packet loss
    case intermittent(dropRate: Double)
    
    /// Completely offline
    case offline
    
    /// Custom condition with specific parameters
    case custom(NetworkConditionParameters)
}

/// Parameters for custom network conditions.
public struct NetworkConditionParameters: Sendable, Equatable {
    /// Base latency in milliseconds
    public let latencyMs: UInt
    
    /// Random additional latency range (jitter) in milliseconds
    public let jitterMs: UInt
    
    /// Probability of request failure (0.0 to 1.0)
    public let dropRate: Double
    
    /// Probability of timeout (0.0 to 1.0)
    public let timeoutRate: Double
    
    /// Whether to simulate bandwidth throttling
    public let throttled: Bool
    
    public init(
        latencyMs: UInt = 0,
        jitterMs: UInt = 0,
        dropRate: Double = 0,
        timeoutRate: Double = 0,
        throttled: Bool = false
    ) {
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.dropRate = max(0, min(1, dropRate))
        self.timeoutRate = max(0, min(1, timeoutRate))
        self.throttled = throttled
    }
}

/// Preset network condition profiles
public extension NetworkCondition {
    /// Simulates WiFi conditions (low latency, reliable)
    static let wifi = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 20,
        jitterMs: 10
    ))
    
    /// Simulates 4G/LTE conditions
    static let lte = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 50,
        jitterMs: 30
    ))
    
    /// Simulates 3G conditions (higher latency)
    static let threeG = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 300,
        jitterMs: 100
    ))
    
    /// Simulates EDGE/2G conditions (very slow)
    static let edge = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 800,
        jitterMs: 200,
        timeoutRate: 0.1
    ))
    
    /// Simulates flaky connection (frequent drops)
    static let flaky = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 100,
        jitterMs: 200,
        dropRate: 0.3
    ))
    
    /// Simulates satellite connection (high latency)
    static let satellite = NetworkCondition.custom(NetworkConditionParameters(
        latencyMs: 600,
        jitterMs: 50
    ))
}

// MARK: - Network Error Types

/// Errors that can be simulated by the network condition simulator.
public enum NetworkSimulatedError: Error, Sendable {
    case offline
    case timeout
    case connectionDropped
    case dnsFailure
    case sslError
    case serverUnreachable
}

extension NetworkSimulatedError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline:
            return "The network connection appears to be offline."
        case .timeout:
            return "The request timed out."
        case .connectionDropped:
            return "The network connection was lost."
        case .dnsFailure:
            return "The server name could not be resolved."
        case .sslError:
            return "A secure connection could not be established."
        case .serverUnreachable:
            return "The server is not reachable."
        }
    }
}

// MARK: - Condition Application Result

/// Result of applying network conditions to a request.
public enum ConditionResult: Sendable {
    /// Request should proceed after the specified delay
    case proceed(delayMs: UInt)
    
    /// Request should fail with the specified error
    case fail(NetworkSimulatedError)
    
    /// Request timed out
    case timeout
}

// MARK: - Recorded Condition Event

/// A record of a network condition being applied.
public struct ConditionEvent: Sendable {
    public let timestamp: Date
    public let path: String
    public let condition: NetworkCondition
    public let result: ConditionResult
    
    public init(
        timestamp: Date = Date(),
        path: String,
        condition: NetworkCondition,
        result: ConditionResult
    ) {
        self.timestamp = timestamp
        self.path = path
        self.condition = condition
        self.result = result
    }
}

// MARK: - Network Condition Simulator

/// Simulates various network conditions for testing.
///
/// Use this actor to inject latency, packet loss, and offline conditions
/// into your network requests during testing.
///
/// ```swift
/// let simulator = NetworkConditionSimulator()
/// await simulator.setCondition(.slow(latencyMs: 500))
///
/// // Apply to a request
/// let result = await simulator.apply(to: "/api/v1/entries.json")
/// switch result {
/// case .proceed(let delayMs):
///     try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
///     // Continue with request
/// case .fail(let error):
///     throw error
/// case .timeout:
///     throw NetworkSimulatedError.timeout
/// }
/// ```
public actor NetworkConditionSimulator {
    
    // MARK: - Properties
    
    /// Global condition applied to all requests
    private var globalCondition: NetworkCondition = .normal
    
    /// Path-specific conditions (override global)
    private var pathConditions: [String: NetworkCondition] = [:]
    
    /// History of applied conditions
    private var eventHistory: [ConditionEvent] = []
    
    /// Whether the simulator is enabled
    private var isEnabled: Bool = true
    
    /// Specific error type to simulate when offline
    private var specificErrorType: NetworkSimulatedError?
    
    // MARK: - Initialization
    
    public init() {}
    
    public init(condition: NetworkCondition) {
        self.globalCondition = condition
    }
    
    // MARK: - Configuration
    
    /// Sets the global network condition.
    public func setCondition(_ condition: NetworkCondition) {
        self.globalCondition = condition
    }
    
    /// Gets the current global condition.
    public func getCondition() -> NetworkCondition {
        return globalCondition
    }
    
    /// Sets a condition for a specific path.
    public func setCondition(_ condition: NetworkCondition, forPath path: String) {
        pathConditions[path] = condition
    }
    
    /// Removes a path-specific condition.
    public func removeCondition(forPath path: String) {
        pathConditions.removeValue(forKey: path)
    }
    
    /// Clears all path-specific conditions.
    public func clearPathConditions() {
        pathConditions.removeAll()
    }
    
    /// Enables or disables the simulator.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    /// Sets a specific error type to return when condition indicates failure.
    public func setErrorType(_ errorType: NetworkSimulatedError) {
        specificErrorType = errorType
    }
    
    /// Clears the specific error type.
    public func clearErrorType() {
        specificErrorType = nil
    }
    
    /// Resets the simulator to default state.
    public func reset() {
        globalCondition = .normal
        pathConditions.removeAll()
        eventHistory.removeAll()
        isEnabled = true
        specificErrorType = nil
    }
    
    // MARK: - Condition Application
    
    /// Applies network conditions to a request and returns the result.
    ///
    /// - Parameter path: The request path
    /// - Returns: The condition result (proceed, fail, or timeout)
    public func apply(to path: String) -> ConditionResult {
        guard isEnabled else {
            return .proceed(delayMs: 0)
        }
        
        // Get applicable condition (path-specific overrides global)
        let condition = pathConditions.first { path.hasPrefix($0.key) }?.value ?? globalCondition
        
        let result = evaluateCondition(condition)
        
        // Record the event
        let event = ConditionEvent(
            path: path,
            condition: condition,
            result: result
        )
        eventHistory.append(event)
        
        return result
    }
    
    /// Applies network conditions and waits for the delay.
    ///
    /// - Parameter path: The request path
    /// - Throws: NetworkSimulatedError if the condition causes a failure
    public func applyAndWait(for path: String) async throws {
        let result = apply(to: path)
        
        switch result {
        case .proceed(let delayMs):
            if delayMs > 0 {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        case .fail(let error):
            throw error
        case .timeout:
            throw NetworkSimulatedError.timeout
        }
    }
    
    // MARK: - History
    
    /// Gets the history of condition events.
    public func getEventHistory() -> [ConditionEvent] {
        return eventHistory
    }
    
    /// Gets events for a specific path.
    public func getEvents(forPath path: String) -> [ConditionEvent] {
        return eventHistory.filter { $0.path.hasPrefix(path) }
    }
    
    /// Gets the count of events that resulted in failures.
    public func failureCount() -> Int {
        return eventHistory.filter { event in
            switch event.result {
            case .fail, .timeout:
                return true
            case .proceed:
                return false
            }
        }.count
    }
    
    /// Clears the event history.
    public func clearHistory() {
        eventHistory.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func evaluateCondition(_ condition: NetworkCondition) -> ConditionResult {
        switch condition {
        case .normal:
            return .proceed(delayMs: 0)
            
        case .slow(let latencyMs):
            return .proceed(delayMs: latencyMs)
            
        case .veryPoor:
            let delay = UInt.random(in: 500...2000)
            return .proceed(delayMs: delay)
            
        case .intermittent(let dropRate):
            if Double.random(in: 0...1) < dropRate {
                return .fail(specificErrorType ?? .connectionDropped)
            }
            let delay = UInt.random(in: 50...300)
            return .proceed(delayMs: delay)
            
        case .offline:
            return .fail(specificErrorType ?? .offline)
            
        case .custom(let params):
            return evaluateCustomCondition(params)
        }
    }
    
    private func evaluateCustomCondition(_ params: NetworkConditionParameters) -> ConditionResult {
        // Check for drop
        if Double.random(in: 0...1) < params.dropRate {
            return .fail(specificErrorType ?? .connectionDropped)
        }
        
        // Check for timeout
        if Double.random(in: 0...1) < params.timeoutRate {
            return .timeout
        }
        
        // Calculate delay with jitter
        var delay = params.latencyMs
        if params.jitterMs > 0 {
            let jitter = UInt.random(in: 0...params.jitterMs)
            delay += jitter
        }
        
        return .proceed(delayMs: delay)
    }
}

// MARK: - Convenience Extensions

public extension NetworkConditionSimulator {
    /// Creates a simulator preset for offline testing.
    static func offline() -> NetworkConditionSimulator {
        let simulator = NetworkConditionSimulator()
        Task { await simulator.setCondition(.offline) }
        return simulator
    }
    
    /// Creates a simulator preset for slow network testing.
    static func slow(latencyMs: UInt = 500) -> NetworkConditionSimulator {
        let simulator = NetworkConditionSimulator()
        Task { await simulator.setCondition(.slow(latencyMs: latencyMs)) }
        return simulator
    }
    
    /// Creates a simulator preset for flaky connection testing.
    static func flaky(dropRate: Double = 0.3) -> NetworkConditionSimulator {
        let simulator = NetworkConditionSimulator()
        Task { await simulator.setCondition(.intermittent(dropRate: dropRate)) }
        return simulator
    }
}

// MARK: - Integration with MockNightscoutServer

public extension NetworkConditionSimulator {
    /// Calculates the response delay for a MockNightscoutResponse.
    ///
    /// Use this to add network condition delays to mock responses.
    ///
    /// ```swift
    /// let condition = await simulator.apply(to: path)
    /// if case .proceed(let delayMs) = condition {
    ///     let delay = TimeInterval(delayMs) / 1000.0
    ///     response = MockNightscoutResponse.json(data, delay: delay)
    /// }
    /// ```
    func responseDelay(for path: String) -> TimeInterval {
        let result = apply(to: path)
        switch result {
        case .proceed(let delayMs):
            return TimeInterval(delayMs) / 1000.0
        case .fail, .timeout:
            return 0
        }
    }
}
