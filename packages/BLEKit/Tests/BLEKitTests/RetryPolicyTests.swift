// SPDX-License-Identifier: MIT
//
// RetryPolicyTests.swift
// BLEKit
//
// Tests for exponential backoff with jitter.
// Trace: BLE-CONN-001

import Foundation
import Testing
@testable import BLEKit

// MARK: - Test Helpers

enum TestError: Error {
    case temporary
    case permanent
}

actor AttemptCounter {
    private(set) var value: Int = 0
    
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

// MARK: - RetryPolicy Tests

@Suite("RetryPolicy Configuration")
struct RetryPolicyConfigurationTests {
    @Test("Default values")
    func retryPolicyDefaults() {
        let policy = RetryPolicy()
        #expect(policy.baseDelay == 1.0)
        #expect(policy.maxDelay == 60.0)
        #expect(policy.maxAttempts == 5)
        #expect(policy.multiplier == 2.0)
        #expect(policy.jitter == .full)
    }
    
    @Test("BLE default preset")
    func retryPolicyBLEDefault() {
        let policy = RetryPolicy.bleDefault
        #expect(policy.baseDelay == 1.0)
        #expect(policy.maxDelay == 30.0)
        #expect(policy.maxAttempts == 5)
        #expect(policy.jitter == .decorrelated)
    }
    
    @Test("Aggressive preset")
    func retryPolicyAggressive() {
        let policy = RetryPolicy.aggressive
        #expect(policy.baseDelay == 0.5)
        #expect(policy.maxAttempts == 10)
    }
    
    @Test("Conservative preset")
    func retryPolicyConservative() {
        let policy = RetryPolicy.conservative
        #expect(policy.maxAttempts == 3)
        #expect(policy.multiplier == 3.0)
    }
    
    @Test("No retry preset")
    func retryPolicyNoRetry() {
        let policy = RetryPolicy.noRetry
        #expect(policy.maxAttempts == 0)
    }
    
    @Test("Linear preset")
    func retryPolicyLinear() {
        let policy = RetryPolicy.linear
        #expect(policy.multiplier == 1.0)
        #expect(policy.jitter == .none)
    }
    
    @Test("Minimum values enforced")
    func retryPolicyMinimumValues() {
        let policy = RetryPolicy(
            baseDelay: -1,
            maxDelay: 0,
            maxAttempts: -5,
            multiplier: 0.5
        )
        #expect(policy.baseDelay == 0.1)  // Min enforced
        #expect(policy.maxAttempts == 0)  // Min enforced
        #expect(policy.multiplier == 1.0) // Min enforced
    }
}

// MARK: - BackoffCalculator Tests

@Suite("BackoffCalculator Exponential")
struct BackoffCalculatorExponentialTests {
    @Test("Exponential backoff no jitter")
    func exponentialNoJitter() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: .none
        )
        let calculator = BackoffCalculator(policy: policy)
        
        #expect(calculator.delay(forAttempt: 0) == 1.0)   // 1 * 2^0 = 1
        #expect(calculator.delay(forAttempt: 1) == 2.0)   // 1 * 2^1 = 2
        #expect(calculator.delay(forAttempt: 2) == 4.0)   // 1 * 2^2 = 4
        #expect(calculator.delay(forAttempt: 3) == 8.0)   // 1 * 2^3 = 8
        #expect(calculator.delay(forAttempt: 4) == 16.0)  // 1 * 2^4 = 16
    }
    
    @Test("Max delay cap")
    func maxDelayCap() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            maxDelay: 5.0,
            maxAttempts: 10,
            multiplier: 2.0,
            jitter: .none
        )
        let calculator = BackoffCalculator(policy: policy)
        
        #expect(calculator.delay(forAttempt: 0) == 1.0)
        #expect(calculator.delay(forAttempt: 1) == 2.0)
        #expect(calculator.delay(forAttempt: 2) == 4.0)
        #expect(calculator.delay(forAttempt: 3) == 5.0)  // Capped
        #expect(calculator.delay(forAttempt: 4) == 5.0)  // Capped
    }
    
    @Test("Out of bounds attempt")
    func outOfBoundsAttempt() {
        let policy = RetryPolicy(maxAttempts: 3)
        let calculator = BackoffCalculator(policy: policy)
        
        #expect(calculator.delay(forAttempt: -1) == 0)
        #expect(calculator.delay(forAttempt: 5) == 0)
    }
    
    @Test("Should retry")
    func shouldRetry() {
        let policy = RetryPolicy(maxAttempts: 3)
        let calculator = BackoffCalculator(policy: policy)
        
        #expect(calculator.shouldRetry(attempt: 0))
        #expect(calculator.shouldRetry(attempt: 2))
        #expect(!calculator.shouldRetry(attempt: 3))
        #expect(!calculator.shouldRetry(attempt: 10))
    }
    
    @Test("Max total time")
    func maxTotalTime() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 4,
            multiplier: 2.0,
            jitter: .none
        )
        let calculator = BackoffCalculator(policy: policy)
        
        // 1 + 2 + 4 + 8 = 15
        #expect(calculator.maxTotalTime == 15.0)
    }
}

// MARK: - Jitter Tests

@Suite("BackoffCalculator Jitter")
struct BackoffCalculatorJitterTests {
    @Test("Jitter none")
    func jitterNone() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .none)
        let calculator = BackoffCalculator(policy: policy, randomSource: .system)
        
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 4.0)
    }
    
    @Test("Jitter full with fixed random")
    func jitterFullWithFixedRandom() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .full)
        let calculator = BackoffCalculator(policy: policy, randomSource: .fixed)
        
        // Fixed returns midpoint: 4.0 / 2 = 2.0
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 2.0)
    }
    
    @Test("Jitter full with min random")
    func jitterFullWithMinRandom() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .full)
        let calculator = BackoffCalculator(policy: policy, randomSource: .minimum)
        
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 0.0)
    }
    
    @Test("Jitter full with max random")
    func jitterFullWithMaxRandom() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .full)
        let calculator = BackoffCalculator(policy: policy, randomSource: .maximum)
        
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 4.0)
    }
    
    @Test("Jitter equal with fixed random")
    func jitterEqualWithFixedRandom() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .equal)
        let calculator = BackoffCalculator(policy: policy, randomSource: .fixed)
        
        // Equal: 4/2 + midpoint(0, 4/2) = 2 + 1 = 3
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 3.0)
    }
    
    @Test("Jitter equal guarantees minimum")
    func jitterEqualGuaranteesMinimum() {
        let policy = RetryPolicy(baseDelay: 4.0, jitter: .equal)
        let calculator = BackoffCalculator(policy: policy, randomSource: .minimum)
        
        // Equal with min random: 4/2 + 0 = 2
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 2.0)
    }
    
    @Test("Jitter decorrelated")
    func jitterDecorrelated() {
        let policy = RetryPolicy(baseDelay: 1.0, maxDelay: 100.0, jitter: .decorrelated)
        let calculator = BackoffCalculator(policy: policy, randomSource: .fixed)
        
        // Decorrelated: random(baseDelay, delay)
        // With fixed (midpoint), for attempt 0 with delay 1: (1+1)/2 = 1
        let delay = calculator.delay(forAttempt: 0)
        #expect(delay == 1.0)
    }
    
    @Test("Decorrelated delay with previous")
    func decorrelatedDelayWithPrevious() {
        let policy = RetryPolicy(baseDelay: 1.0, maxDelay: 100.0)
        let calculator = BackoffCalculator(policy: policy, randomSource: .fixed)
        
        // Previous delay 5, so range is (1, min(100, 15))
        // Fixed returns midpoint: (1 + 15) / 2 = 8
        let delay = calculator.decorrelatedDelay(previousDelay: 5.0)
        #expect(delay == 8.0)
    }
}

// MARK: - RetryState Tests

@Suite("RetryState")
struct RetryStateTests {
    @Test("Initial state")
    func retryStateInitial() {
        let state = RetryState(policy: .bleDefault)
        #expect(state.attempt == 0)
        #expect(state.canRetry)
        #expect(state.retriesRemaining == 5)
        #expect(state.totalWaitTime == 0)
    }
    
    @Test("Next retry delay")
    func retryStateNextRetryDelay() {
        var state = RetryState(
            policy: RetryPolicy(baseDelay: 1.0, maxAttempts: 3, jitter: .none),
            randomSource: .fixed
        )
        
        let delay1 = state.nextRetryDelay()
        #expect(delay1 == 1.0)
        #expect(state.attempt == 1)
        
        let delay2 = state.nextRetryDelay()
        #expect(delay2 == 2.0)
        #expect(state.attempt == 2)
        
        let delay3 = state.nextRetryDelay()
        #expect(delay3 == 4.0)
        #expect(state.attempt == 3)
        
        // No more retries
        let delay4 = state.nextRetryDelay()
        #expect(delay4 == nil)
    }
    
    @Test("Total wait time")
    func retryStateTotalWaitTime() {
        var state = RetryState(
            policy: RetryPolicy(baseDelay: 1.0, maxAttempts: 3, jitter: .none),
            randomSource: .fixed
        )
        
        _ = state.nextRetryDelay()  // 1
        _ = state.nextRetryDelay()  // 2
        _ = state.nextRetryDelay()  // 4
        
        #expect(state.totalWaitTime == 7.0)
    }
    
    @Test("Reset")
    func retryStateReset() {
        var state = RetryState(policy: .bleDefault)
        state.lastError = "Connection failed"
        _ = state.nextRetryDelay()
        _ = state.nextRetryDelay()
        
        state.reset()
        
        #expect(state.attempt == 0)
        #expect(state.totalWaitTime == 0)
        #expect(state.lastError == nil)
        #expect(state.attemptTimestamps.isEmpty)
    }
    
    @Test("Record attempt")
    func retryStateRecordAttempt() {
        var state = RetryState(policy: .bleDefault)
        let now = Date()
        
        state.recordAttempt(at: now)
        
        #expect(state.attemptTimestamps.count == 1)
        #expect(state.attemptTimestamps.first == now)
    }
    
    @Test("No retry policy")
    func retryStateNoRetryPolicy() {
        var state = RetryState(policy: .noRetry)
        
        #expect(!state.canRetry)
        #expect(state.retriesRemaining == 0)
        #expect(state.nextRetryDelay() == nil)
    }
}

// MARK: - RetryExecutor Tests

@Suite("RetryExecutor Success")
struct RetryExecutorSuccessTests {
    @Test("Succeeds first attempt")
    func retryExecutorSucceedsFirstAttempt() async throws {
        let executor = RetryExecutor(policy: .bleDefault)
        let counter = AttemptCounter()
        
        let result = try await executor.execute {
            await counter.increment()
            return "success"
        }
        
        #expect(result == "success")
        let count = await counter.value
        #expect(count == 1)
    }
    
    @Test("Succeeds after retries")
    func retryExecutorSucceedsAfterRetries() async throws {
        let executor = RetryExecutor(policy: RetryPolicy(baseDelay: 0.01, maxAttempts: 5))
        let counter = AttemptCounter()
        
        let result = try await executor.execute {
            let current = await counter.increment()
            if current < 3 {
                throw TestError.temporary
            }
            return "success after retries"
        }
        
        #expect(result == "success after retries")
        let count = await counter.value
        #expect(count == 3)
    }
    
    @Test("Tracks state")
    func retryExecutorTracksState() async throws {
        let executor = RetryExecutor(policy: RetryPolicy(baseDelay: 0.01, maxAttempts: 3))
        let counter = AttemptCounter()
        
        _ = try await executor.execute {
            let current = await counter.increment()
            if current < 2 {
                throw TestError.temporary
            }
            return "done"
        }
        
        let state = await executor.getState()
        #expect(state.attempt == 1)  // 1 retry used
        #expect(state.totalWaitTime > 0)
    }
    
    @Test("Reset")
    func retryExecutorReset() async {
        let executor = RetryExecutor(policy: .bleDefault)
        
        await executor.reset()
        let state = await executor.getState()
        
        #expect(state.attempt == 0)
        #expect(state.totalWaitTime == 0)
    }
}

@Suite("RetryExecutor Failure")
struct RetryExecutorFailureTests {
    @Test("Exhausts retries")
    func retryExecutorExhaustsRetries() async throws {
        let executor = RetryExecutor(policy: RetryPolicy(baseDelay: 0.01, maxAttempts: 3))
        let counter = AttemptCounter()
        
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown")
        } catch {
            let count = await counter.value
            #expect(count == 4)  // Initial + 3 retries
        }
    }
    
    @Test("Respects no retry policy")
    func retryExecutorRespectsNoRetryPolicy() async throws {
        let executor = RetryExecutor(policy: .noRetry)
        let counter = AttemptCounter()
        
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw TestError.permanent
            }
            Issue.record("Should have thrown")
        } catch {
            let count = await counter.value
            #expect(count == 1)  // No retries
        }
    }
    
    @Test("Should retry filter")
    func retryExecutorShouldRetryFilter() async throws {
        let executor = RetryExecutor(policy: RetryPolicy(baseDelay: 0.01, maxAttempts: 5))
        let counter = AttemptCounter()
        
        do {
            _ = try await executor.execute(
                operation: {
                    await counter.increment()
                    throw TestError.permanent
                },
                shouldRetry: { error in
                    // Only retry temporary errors
                    if case TestError.temporary = error { return true }
                    return false
                }
            )
            Issue.record("Should have thrown")
        } catch {
            let count = await counter.value
            #expect(count == 1)  // Permanent error not retried
        }
    }
}
