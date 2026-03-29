// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RetryPolicy.swift
// BLEKit
//
// Exponential backoff with jitter for BLE connection retries.
// Trace: BLE-CONN-001
// Reference: AWS Architecture Blog - Exponential Backoff and Jitter

import Foundation

// MARK: - Retry Policy

/// Configuration for retry behavior with exponential backoff
public struct RetryPolicy: Sendable, Equatable {
    /// Base delay in seconds (first retry delay)
    public let baseDelay: TimeInterval
    
    /// Maximum delay cap in seconds
    public let maxDelay: TimeInterval
    
    /// Maximum number of retry attempts (0 = no retries)
    public let maxAttempts: Int
    
    /// Exponential multiplier (typically 2.0)
    public let multiplier: Double
    
    /// Jitter strategy
    public let jitter: JitterStrategy
    
    /// Creates a retry policy
    public init(
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 5,
        multiplier: Double = 2.0,
        jitter: JitterStrategy = .full
    ) {
        self.baseDelay = max(0.1, baseDelay)
        self.maxDelay = max(baseDelay, maxDelay)
        self.maxAttempts = max(0, maxAttempts)
        self.multiplier = max(1.0, multiplier)
        self.jitter = jitter
    }
    
    // MARK: - Presets
    
    /// Default BLE connection retry policy
    public static let bleDefault = RetryPolicy(
        baseDelay: 1.0,
        maxDelay: 30.0,
        maxAttempts: 5,
        multiplier: 2.0,
        jitter: .decorrelated
    )
    
    /// Aggressive retry for quick reconnection attempts
    public static let aggressive = RetryPolicy(
        baseDelay: 0.5,
        maxDelay: 10.0,
        maxAttempts: 10,
        multiplier: 1.5,
        jitter: .full
    )
    
    /// Conservative retry for battery-sensitive scenarios
    public static let conservative = RetryPolicy(
        baseDelay: 2.0,
        maxDelay: 120.0,
        maxAttempts: 3,
        multiplier: 3.0,
        jitter: .equal
    )
    
    /// No retries - fail immediately
    public static let noRetry = RetryPolicy(
        baseDelay: 0,
        maxDelay: 0,
        maxAttempts: 0
    )
    
    /// Linear backoff (multiplier = 1)
    public static let linear = RetryPolicy(
        baseDelay: 3.0,
        maxDelay: 30.0,
        maxAttempts: 5,
        multiplier: 1.0,
        jitter: .none
    )
}

// MARK: - Jitter Strategy

/// Jitter strategies for randomizing retry delays
/// Reference: https://aws.amazon.com/blogs/architecture/exponential-back-off-and-jitter/
public enum JitterStrategy: String, Sendable, Codable, Equatable {
    /// No jitter - use exact calculated delay
    case none
    
    /// Full jitter: random(0, delay)
    /// Most aggressive decorrelation, can have very short delays
    case full
    
    /// Equal jitter: delay/2 + random(0, delay/2)
    /// Guarantees at least half the delay, good balance
    case equal
    
    /// Decorrelated jitter: random(baseDelay, min(maxDelay, previousDelay * 3))
    /// Best for reducing collision in distributed systems
    case decorrelated
}

// MARK: - Backoff Calculator

/// Calculator for exponential backoff delays
public struct BackoffCalculator: Sendable {
    private let policy: RetryPolicy
    private let randomSource: RandomSource
    
    /// Create with a retry policy
    public init(policy: RetryPolicy, randomSource: RandomSource = .system) {
        self.policy = policy
        self.randomSource = randomSource
    }
    
    /// Calculate delay for a given attempt number (0-indexed)
    /// - Parameter attempt: The attempt number (0 = first retry after initial failure)
    /// - Returns: Delay in seconds before the next attempt
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 0, attempt < policy.maxAttempts else {
            return 0
        }
        
        // Calculate base exponential delay
        let exponentialDelay = policy.baseDelay * pow(policy.multiplier, Double(attempt))
        let cappedDelay = min(exponentialDelay, policy.maxDelay)
        
        // Apply jitter
        return applyJitter(to: cappedDelay, attempt: attempt)
    }
    
    /// Calculate delay using decorrelated jitter (needs previous delay)
    public func decorrelatedDelay(previousDelay: TimeInterval) -> TimeInterval {
        let upper = min(policy.maxDelay, previousDelay * 3)
        return randomSource.random(in: policy.baseDelay...max(policy.baseDelay, upper))
    }
    
    /// Check if more retries are allowed
    public func shouldRetry(attempt: Int) -> Bool {
        attempt < policy.maxAttempts
    }
    
    /// Total maximum time all retries could take (worst case)
    public var maxTotalTime: TimeInterval {
        var total: TimeInterval = 0
        for i in 0..<policy.maxAttempts {
            // Use max possible delay (no jitter reduction)
            let exponentialDelay = policy.baseDelay * pow(policy.multiplier, Double(i))
            total += min(exponentialDelay, policy.maxDelay)
        }
        return total
    }
    
    // MARK: - Private
    
    private func applyJitter(to delay: TimeInterval, attempt: Int) -> TimeInterval {
        switch policy.jitter {
        case .none:
            return delay
            
        case .full:
            // random(0, delay)
            return randomSource.random(in: 0...delay)
            
        case .equal:
            // delay/2 + random(0, delay/2)
            let half = delay / 2
            return half + randomSource.random(in: 0...half)
            
        case .decorrelated:
            // For decorrelated, we use previous delay tracking
            // Simplified: random(baseDelay, delay)
            return randomSource.random(in: policy.baseDelay...max(policy.baseDelay, delay))
        }
    }
}

// MARK: - Random Source

/// Abstraction for random number generation (enables testing)
public struct RandomSource: Sendable {
    private let generator: @Sendable (ClosedRange<Double>) -> Double
    
    public init(generator: @escaping @Sendable (ClosedRange<Double>) -> Double) {
        self.generator = generator
    }
    
    /// System random source
    public static let system = RandomSource { range in
        Double.random(in: range)
    }
    
    /// Fixed value for testing (returns midpoint of range)
    public static let fixed = RandomSource { range in
        (range.lowerBound + range.upperBound) / 2
    }
    
    /// Minimum value for testing (returns lower bound)
    public static let minimum = RandomSource { range in
        range.lowerBound
    }
    
    /// Maximum value for testing (returns upper bound)
    public static let maximum = RandomSource { range in
        range.upperBound
    }
    
    func random(in range: ClosedRange<Double>) -> Double {
        generator(range)
    }
}

// MARK: - Retry State

/// Tracks state across retry attempts
public struct RetryState: Sendable {
    /// Current attempt number (0 = first attempt, not a retry)
    public private(set) var attempt: Int
    
    /// Previous delay used (for decorrelated jitter)
    public private(set) var previousDelay: TimeInterval
    
    /// Total time spent waiting
    public private(set) var totalWaitTime: TimeInterval
    
    /// Timestamps of each attempt
    public private(set) var attemptTimestamps: [Date]
    
    /// Last error encountered
    public var lastError: String?
    
    /// The retry policy being used
    public let policy: RetryPolicy
    
    /// The backoff calculator
    private let calculator: BackoffCalculator
    
    /// Create initial retry state
    public init(policy: RetryPolicy = .bleDefault, randomSource: RandomSource = .system) {
        self.attempt = 0
        self.previousDelay = policy.baseDelay
        self.totalWaitTime = 0
        self.attemptTimestamps = []
        self.policy = policy
        self.calculator = BackoffCalculator(policy: policy, randomSource: randomSource)
    }
    
    /// Record an attempt
    public mutating func recordAttempt(at date: Date = Date()) {
        attemptTimestamps.append(date)
    }
    
    /// Get delay for next retry and advance state
    /// - Returns: Delay in seconds, or nil if no more retries allowed
    public mutating func nextRetryDelay() -> TimeInterval? {
        guard calculator.shouldRetry(attempt: attempt) else {
            return nil
        }
        
        let delay: TimeInterval
        if policy.jitter == .decorrelated && attempt > 0 {
            delay = calculator.decorrelatedDelay(previousDelay: previousDelay)
        } else {
            delay = calculator.delay(forAttempt: attempt)
        }
        
        previousDelay = delay
        totalWaitTime += delay
        attempt += 1
        
        return delay
    }
    
    /// Check if more retries are available
    public var canRetry: Bool {
        calculator.shouldRetry(attempt: attempt)
    }
    
    /// Number of retries remaining
    public var retriesRemaining: Int {
        max(0, policy.maxAttempts - attempt)
    }
    
    /// Reset state for a new connection attempt
    public mutating func reset() {
        attempt = 0
        previousDelay = policy.baseDelay
        totalWaitTime = 0
        attemptTimestamps = []
        lastError = nil
    }
}

// MARK: - Retry Executor

/// Executes an async operation with retry logic
public actor RetryExecutor {
    private var state: RetryState
    
    public init(policy: RetryPolicy = .bleDefault) {
        self.state = RetryState(policy: policy)
    }
    
    /// Execute an operation with retries
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - shouldRetry: Closure to determine if error is retryable
    /// - Returns: The operation result
    public func execute<T>(
        operation: @Sendable () async throws -> T,
        shouldRetry: @Sendable (Error) -> Bool = { _ in true }
    ) async throws -> T {
        state.reset()
        
        while true {
            state.recordAttempt()
            
            do {
                return try await operation()
            } catch {
                state.lastError = String(describing: error)
                
                guard shouldRetry(error), let delay = state.nextRetryDelay() else {
                    throw error
                }
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    /// Get current retry state
    public func getState() -> RetryState {
        state
    }
    
    /// Reset the executor state
    public func reset() {
        state.reset()
    }
}
