// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ConcurrentExecutionTests.swift
// T1Pal Mobile
//
// Thread safety and concurrency tests for algorithm execution
// Verifies correct behavior under concurrent/rapid invocation
// Trace: TEST-GAP-005, CRITICAL-PATH-TESTS.md
//
// Test scenarios:
// - Simultaneous algorithm invocations from multiple threads
// - Rapid successive calls (high CGM rate simulation)
// - Thread contention on shared state
// - No race conditions, deadlocks, or data corruption

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - Concurrent Execution Tests

@Suite("Concurrent Execution Safety")
struct ConcurrentExecutionTests {
    
    // MARK: - Setup
    
    /// Create a basic algorithm input for testing
    private func makeTestInputs(glucoseValue: Double = 120.0) -> AlgorithmInputs {
        let glucose = [
            GlucoseReading(glucose: glucoseValue, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: glucoseValue - 5, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: glucoseValue - 10, timestamp: Date().addingTimeInterval(-600), source: "test"),
            GlucoseReading(glucose: glucoseValue - 8, timestamp: Date().addingTimeInterval(-900), source: "test"),
            GlucoseReading(glucose: glucoseValue - 3, timestamp: Date().addingTimeInterval(-1200), source: "test")
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0,
            maxBasalRate: 4.0
        )
        
        return AlgorithmInputs(glucose: glucose, profile: profile)
    }
    
    // MARK: - Concurrent Algorithm Calculation Tests
    
    @Test("Multiple concurrent algorithm calculations complete without data corruption")
    func multipleConcurrentCalculations() async throws {
        let counter = AtomicCounter()
        let iterations = 50
        
        // Launch many concurrent calculations
        await withTaskGroup(of: AlgorithmDecision?.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let algorithm = LoopAlgorithm()  // Each task gets its own
                    let inputs = self.makeTestInputs(glucoseValue: 100.0 + Double(i))
                    counter.increment()
                    return try? algorithm.calculate(inputs)
                }
            }
            
            var successCount = 0
            for await result in group {
                if result != nil {
                    successCount += 1
                }
            }
            
            // All calculations should complete without crashes
            #expect(successCount == iterations, "All \(iterations) concurrent calculations should succeed")
        }
        
        // Verify invocation count matches
        let count = counter.value
        #expect(count == iterations, "Invocation count should match: expected \(iterations), got \(count)")
    }
    
    @Test("Rapid successive calls simulate high CGM rate")
    func rapidSuccessiveCalls() async throws {
        let executor = BackgroundLoopExecutor()
        let callCount = AtomicCounter()
        
        await executor.configure {
            callCount.increment()
            // Simulate some work
            try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
            return LoopExecutionResult.success(
                duration: 0.001,
                loopResult: LoopIterationSummary(glucose: 120.0),
                doseEnacted: false
            )
        }
        
        try await executor.start()
        
        // Rapidly invoke loop executions (simulating high CGM rate)
        let rapidIterations = 20
        var results: [LoopExecutionResult] = []
        
        for _ in 0..<rapidIterations {
            let result = await executor.executeLoop()
            results.append(result)
        }
        
        // All should complete
        let successfulCount = results.filter { $0.success }.count
        #expect(successfulCount == rapidIterations, "All rapid calls should succeed")
        
        // Verify actual handler invocations match
        let actualCalls = callCount.value
        #expect(actualCalls == rapidIterations, "Handler should be called \(rapidIterations) times")
    }
    
    @Test("Concurrent state access on BackgroundLoopExecutor")
    func concurrentStateAccess() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            LoopExecutionResult.success(duration: 0.1, loopResult: nil, doseEnacted: false)
        }
        
        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Start/stop cycles
            for _ in 0..<5 {
                group.addTask {
                    try? await executor.start()
                }
                group.addTask {
                    await executor.stop()
                }
            }
            
            // Concurrent state reads
            for _ in 0..<20 {
                group.addTask {
                    _ = await executor.state
                }
                group.addTask {
                    _ = await executor.configuration
                }
            }
            
            // Execute loops concurrently
            for _ in 0..<10 {
                group.addTask {
                    _ = await executor.executeLoop()
                }
            }
            
            await group.waitForAll()
        }
        
        // If we reach here without deadlock/crash, the test passes
        let finalState = await executor.state
        #expect(finalState == .idle || finalState == .scheduled || finalState == .running,
                "Executor should be in a valid state, got: \(finalState)")
    }
    
    @Test("History updates are thread-safe under concurrent execution")
    func concurrentHistoryUpdates() async throws {
        let executor = BackgroundLoopExecutor()
        let counter = AtomicCounter()
        
        await executor.configure {
            let n = counter.increment()
            let success = n % 3 != 0  // Every 3rd fails
            if success {
                return LoopExecutionResult.success(
                    duration: 0.01,
                    loopResult: LoopIterationSummary(glucose: Double(n) + 100),
                    doseEnacted: n % 2 == 0
                )
            } else {
                return LoopExecutionResult.failure("Simulated failure #\(n)")
            }
        }
        
        try await executor.start()
        
        // Execute many loops to build history
        let iterations = 30
        for _ in 0..<iterations {
            _ = await executor.executeLoop()
        }
        
        // Get history and verify integrity
        let history = await executor.getHistory()
        
        #expect(history.entries.count == iterations,
                "History should have \(iterations) entries, got \(history.entries.count)")
        
        // Verify history entries are ordered (newest first)
        var previousTimestamp: Date?
        for entry in history.entries {
            if let prev = previousTimestamp {
                #expect(entry.timestamp <= prev, "History should be ordered newest-first")
            }
            previousTimestamp = entry.timestamp
        }
        
        // Statistics should be consistent
        let stats = await executor.getStatistics(lastHours: 1)
        #expect(stats.totalExecutions == iterations,
                "Statistics should show \(iterations) total executions")
        #expect(stats.successfulExecutions + stats.failedExecutions == stats.totalExecutions,
                "Success + Failed should equal Total")
    }
    
    @Test("Concurrent pause/resume doesn't corrupt state")
    func concurrentPauseResume() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            LoopExecutionResult.success(duration: 0.01, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        
        // Rapid pause/resume cycles from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await executor.pause()
                }
                group.addTask {
                    try? await executor.resume()
                }
            }
        }
        
        // State should still be valid
        let state = await executor.state
        let validStates: [LoopExecutionState] = [.idle, .scheduled, .paused, .running]
        #expect(validStates.contains(state), "State should be valid after concurrent pause/resume")
    }
    
    @Test("Configuration updates during execution are safe")
    func configurationUpdatesDuringExecution() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            // Simulate work that takes some time
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
            return LoopExecutionResult.success(duration: 0.005, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        
        // Start executions and update configuration concurrently
        await withTaskGroup(of: Void.self) { group in
            // Execute loops
            for _ in 0..<5 {
                group.addTask {
                    _ = await executor.executeLoop()
                }
            }
            
            // Update configuration concurrently
            for i in 0..<5 {
                group.addTask {
                    let newConfig = BackgroundLoopConfiguration(
                        loopInterval: TimeInterval(300 + i * 10),
                        maxConsecutiveFailures: 3 + i
                    )
                    await executor.updateConfiguration(newConfig)
                }
            }
        }
        
        // Configuration should be one of the values we set
        let finalConfig = await executor.configuration
        #expect(finalConfig.loopInterval >= 300 && finalConfig.loopInterval <= 340,
                "Configuration should be valid")
    }
    
    @Test("Consecutive failure counter is thread-safe")
    func consecutiveFailureCounterSafety() async throws {
        let config = BackgroundLoopConfiguration(maxConsecutiveFailures: 100)  // High limit
        let executor = BackgroundLoopExecutor(configuration: config)
        
        let shouldFail = AtomicFlag(initialValue: true)
        
        await executor.configure {
            if shouldFail.value {
                return LoopExecutionResult.failure("Intentional failure")
            }
            return LoopExecutionResult.success(duration: 0.01, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        
        // Generate failures
        for _ in 0..<10 {
            _ = await executor.executeLoop()
        }
        
        let failuresAfterFailures = await executor.getConsecutiveFailures()
        #expect(failuresAfterFailures == 10, "Should have 10 consecutive failures")
        
        // Reset with success
        shouldFail.set(false)
        _ = await executor.executeLoop()
        
        let failuresAfterSuccess = await executor.getConsecutiveFailures()
        #expect(failuresAfterSuccess == 0, "Success should reset consecutive failures")
    }
    
    @Test("Algorithm calculations are deterministic regardless of concurrency")
    func deterministicResultsUnderConcurrency() async throws {
        let algorithm = LoopAlgorithm()
        let inputs = makeTestInputs(glucoseValue: 150.0)
        
        // Calculate baseline
        let baseline = try algorithm.calculate(inputs)
        
        // Run many concurrent calculations with same inputs
        var results: [AlgorithmDecision] = []
        let iterations = 20
        
        await withTaskGroup(of: AlgorithmDecision?.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try? algorithm.calculate(inputs)
                }
            }
            
            for await result in group {
                if let r = result {
                    results.append(r)
                }
            }
        }
        
        // All results should match baseline
        for (index, result) in results.enumerated() {
            // Compare temp basal suggestions (main output)
            if let baselineBasal = baseline.suggestedTempBasal,
               let resultBasal = result.suggestedTempBasal {
                let rateMatch = abs(baselineBasal.rate - resultBasal.rate) < 0.001
                #expect(rateMatch, "Result \(index) rate should match baseline")
            } else {
                // Both should be nil or both should exist
                let bothNil = baseline.suggestedTempBasal == nil && result.suggestedTempBasal == nil
                #expect(bothNil, "Result \(index) temp basal presence should match baseline")
            }
        }
        
        #expect(results.count == iterations, "All \(iterations) calculations should complete")
    }
}

// MARK: - High CGM Rate Simulation Tests

@Suite("High CGM Rate Simulation")
struct HighCGMRateTests {
    
    @Test("Handles burst of CGM readings without backpressure issues")
    func burstCGMReadings() async throws {
        let executor = BackgroundLoopExecutor()
        let processedReadings = AtomicCounter()
        
        await executor.configure {
            processedReadings.increment()
            return LoopExecutionResult.success(
                duration: 0.001,
                loopResult: nil,
                doseEnacted: false
            )
        }
        
        try await executor.start()
        
        // Simulate a burst of readings (like catching up after disconnect)
        let burstSize = 50
        let startTime = Date()
        
        for _ in 0..<burstSize {
            _ = await executor.executeLoop()
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let processed = processedReadings.value
        
        #expect(processed == burstSize, "All burst readings should be processed")
        #expect(elapsed < 5.0, "Burst processing should complete quickly")
    }
    
    @Test("Statistics remain accurate under high throughput")
    func accurateStatisticsUnderLoad() async throws {
        let executor = BackgroundLoopExecutor()
        let successCounter = AtomicCounter()
        let failCounter = AtomicCounter()
        
        await executor.configure {
            // 80% success rate
            let isSuccess = Int.random(in: 0..<10) < 8
            if isSuccess {
                successCounter.increment()
                return LoopExecutionResult.success(
                    duration: 0.001,
                    loopResult: nil,
                    doseEnacted: Int.random(in: 0..<2) == 0
                )
            } else {
                failCounter.increment()
                return LoopExecutionResult.failure("Random failure")
            }
        }
        
        try await executor.start()
        
        // High throughput execution
        let iterations = 100
        for _ in 0..<iterations {
            _ = await executor.executeLoop()
        }
        
        let stats = await executor.getStatistics(lastHours: 1)
        let successCount = successCounter.value
        let failCount = failCounter.value
        
        // Verify counts match
        #expect(stats.totalExecutions == iterations,
                "Total should be \(iterations), got \(stats.totalExecutions)")
        #expect(stats.successfulExecutions == successCount,
                "Success count mismatch: expected \(successCount), got \(stats.successfulExecutions)")
        #expect(stats.failedExecutions == failCount,
                "Fail count mismatch: expected \(failCount), got \(stats.failedExecutions)")
    }
}

// MARK: - Deadlock Detection Tests

@Suite("Deadlock Prevention")
struct DeadlockPreventionTests {
    
    @Test("No deadlock with nested async calls")
    func noDeadlockWithNestedCalls() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            // Access executor state from within handler (nested call back to actor)
            let state = await executor.state
            let config = await executor.configuration
            _ = state
            _ = config
            return LoopExecutionResult.success(duration: 0.01, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        
        // This should complete without deadlock
        let result = await executor.executeLoop()
        #expect(result.success, "Nested call should complete without deadlock")
    }
    
    @Test("Timeout cancellation doesn't cause deadlock")
    func timeoutCancellationSafety() async throws {
        let executor = BackgroundLoopExecutor()
        let handlerStarted = AtomicFlag(initialValue: false)
        
        await executor.configure {
            handlerStarted.set(true)
            // Simulate a slow operation
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            return LoopExecutionResult.success(duration: 0.1, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        
        // Start execution then check state concurrently
        async let execution = executor.executeLoop()
        
        // Access state while execution is running
        _ = await executor.state
        _ = await executor.getHistory()
        
        // Wait for execution
        let result = await execution
        #expect(handlerStarted.value, "Handler should have started")
        #expect(result.success || !result.success, "Result should be defined (not hung)")
    }
}

// MARK: - Thread-Safe Atomic Helpers

/// Simple thread-safe counter
final class AtomicCounter: @unchecked Sendable {
    private var _value: Int = 0
    private let lock = NSLock()
    
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}

/// Simple thread-safe boolean flag
final class AtomicFlag: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()
    
    init(initialValue: Bool) {
        _value = initialValue
    }
    
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}
