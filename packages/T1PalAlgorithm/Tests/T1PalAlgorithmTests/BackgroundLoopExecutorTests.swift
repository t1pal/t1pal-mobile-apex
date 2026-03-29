// SPDX-License-Identifier: MIT
//
// BackgroundLoopExecutorTests.swift
// T1Pal Mobile
//
// Tests for background loop execution
// Trace: PROD-AID-001

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Background Loop Configuration Tests

@Suite("Background Loop Configuration")
struct BackgroundLoopConfigurationTests {
    
    @Test("Default configuration values")
    func defaultConfigurationValues() {
        let config = BackgroundLoopConfiguration.default
        
        #expect(config.loopInterval == 300)  // 5 minutes
        #expect(config.maxExecutionTime == 30)  // 30 seconds
        #expect(config.requiresExternalPower == false)
        #expect(config.requiresNetwork == false)
        #expect(config.minimumBatteryLevel == 10)
        #expect(config.maxConsecutiveFailures == 3)
    }
    
    @Test("Aggressive configuration")
    func aggressiveConfiguration() {
        let config = BackgroundLoopConfiguration.aggressive
        
        #expect(config.loopInterval == 300)
        #expect(config.maxExecutionTime == 45)  // Longer execution time
        #expect(config.minimumBatteryLevel == 5)  // Lower battery requirement
        #expect(config.maxConsecutiveFailures == 5)  // More tolerance
    }
    
    @Test("Conservative configuration")
    func conservativeConfiguration() {
        let config = BackgroundLoopConfiguration.conservative
        
        #expect(config.loopInterval == 300)
        #expect(config.maxExecutionTime == 20)  // Shorter execution time
        #expect(config.minimumBatteryLevel == 20)  // Higher battery requirement
        #expect(config.maxConsecutiveFailures == 2)  // Less tolerance
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = BackgroundLoopConfiguration(
            loopInterval: 180,  // 3 minutes
            maxExecutionTime: 60,
            requiresExternalPower: true,
            requiresNetwork: true,
            minimumBatteryLevel: 50,
            allowsCellular: false,
            maxConsecutiveFailures: 10
        )
        
        #expect(config.loopInterval == 180)
        #expect(config.maxExecutionTime == 60)
        #expect(config.requiresExternalPower == true)
        #expect(config.requiresNetwork == true)
        #expect(config.minimumBatteryLevel == 50)
        #expect(config.allowsCellular == false)
        #expect(config.maxConsecutiveFailures == 10)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = BackgroundLoopConfiguration(
            loopInterval: 240,
            maxExecutionTime: 45,
            requiresExternalPower: true,
            minimumBatteryLevel: 25
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackgroundLoopConfiguration.self, from: data)
        
        #expect(decoded.loopInterval == original.loopInterval)
        #expect(decoded.maxExecutionTime == original.maxExecutionTime)
        #expect(decoded.requiresExternalPower == original.requiresExternalPower)
        #expect(decoded.minimumBatteryLevel == original.minimumBatteryLevel)
    }
}

// MARK: - Loop Execution State Tests

@Suite("Loop Execution State")
struct LoopExecutionStateTests {
    
    @Test("All states have raw values")
    func allStatesHaveRawValues() {
        for state in LoopExecutionState.allCases {
            #expect(!state.rawValue.isEmpty)
        }
    }
    
    @Test("States are unique")
    func statesAreUnique() {
        let rawValues = LoopExecutionState.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
}

// MARK: - Loop Execution Result Tests

@Suite("Loop Execution Result")
struct LoopExecutionResultTests {
    
    @Test("Create success result")
    func createSuccessResult() {
        let summary = LoopIterationSummary(
            glucose: 120.0,
            iob: 2.5,
            cob: 30.0,
            suggestedTempBasal: 0.8,
            enacted: true
        )
        
        let result = LoopExecutionResult.success(
            duration: 2.5,
            loopResult: summary,
            doseEnacted: true
        )
        
        #expect(result.success == true)
        #expect(result.duration == 2.5)
        #expect(result.doseEnacted == true)
        #expect(result.loopResult?.glucose == 120.0)
        #expect(result.errorMessage == nil)
    }
    
    @Test("Create failure result")
    func createFailureResult() {
        let result = LoopExecutionResult.failure("CGM data too old", duration: 0.5)
        
        #expect(result.success == false)
        #expect(result.duration == 0.5)
        #expect(result.errorMessage == "CGM data too old")
        #expect(result.loopResult == nil)
        #expect(result.doseEnacted == false)
    }
}

// MARK: - Loop Iteration Summary Tests

@Suite("Loop Iteration Summary")
struct LoopIterationSummaryTests {
    
    @Test("Create summary with all fields")
    func createSummaryWithAllFields() {
        let summary = LoopIterationSummary(
            glucose: 150.0,
            iob: 3.0,
            cob: 45.0,
            suggestedTempBasal: 1.2,
            suggestedSMB: 0.5,
            enacted: true,
            reason: "High BG, increasing insulin"
        )
        
        #expect(summary.glucose == 150.0)
        #expect(summary.iob == 3.0)
        #expect(summary.cob == 45.0)
        #expect(summary.suggestedTempBasal == 1.2)
        #expect(summary.suggestedSMB == 0.5)
        #expect(summary.enacted == true)
        #expect(summary.reason == "High BG, increasing insulin")
    }
    
    @Test("Default values")
    func defaultValues() {
        let summary = LoopIterationSummary()
        
        #expect(summary.glucose == nil)
        #expect(summary.iob == 0)
        #expect(summary.cob == 0)
        #expect(summary.suggestedTempBasal == nil)
        #expect(summary.suggestedSMB == nil)
        #expect(summary.enacted == false)
        #expect(summary.reason == "")
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = LoopIterationSummary(
            glucose: 100.0,
            iob: 1.5,
            cob: 20.0,
            suggestedTempBasal: 0.5,
            enacted: true,
            reason: "Test"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoopIterationSummary.self, from: data)
        
        #expect(decoded.glucose == original.glucose)
        #expect(decoded.iob == original.iob)
        #expect(decoded.cob == original.cob)
        #expect(decoded.suggestedTempBasal == original.suggestedTempBasal)
        #expect(decoded.enacted == original.enacted)
    }
}

// MARK: - Loop Execution History Tests

@Suite("Loop Execution History")
struct LoopExecutionHistoryTests {
    
    @Test("Add entries to history")
    func addEntriesToHistory() {
        var history = LoopExecutionHistory()
        
        let entry1 = LoopExecutionHistoryEntry(success: true, duration: 2.0)
        let entry2 = LoopExecutionHistoryEntry(success: false, duration: 1.0, errorMessage: "Error")
        
        history.addEntry(entry1)
        history.addEntry(entry2)
        
        #expect(history.entries.count == 2)
        // Most recent should be first
        #expect(history.entries.first?.success == false)
    }
    
    @Test("History respects max entries")
    func historyRespectsMaxEntries() {
        var history = LoopExecutionHistory()
        
        for i in 0..<300 {
            let entry = LoopExecutionHistoryEntry(success: i % 2 == 0, duration: 1.0)
            history.addEntry(entry)
        }
        
        #expect(history.entries.count == LoopExecutionHistory.maxEntries)
    }
    
    @Test("Filter entries by time")
    func filterEntriesByTime() {
        var history = LoopExecutionHistory()
        
        // Recent entry
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 1.0))
        
        let entries = history.entries(lastHours: 1)
        #expect(entries.count == 1)
    }
    
    @Test("Calculate success rate")
    func calculateSuccessRate() {
        var history = LoopExecutionHistory()
        
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 1.0))
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 1.0))
        history.addEntry(LoopExecutionHistoryEntry(success: false, duration: 1.0))
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 1.0))
        
        let rate = history.successRate(lastHours: 1)
        #expect(rate == 75.0)
    }
    
    @Test("Success rate with no entries")
    func successRateWithNoEntries() {
        let history = LoopExecutionHistory()
        let rate = history.successRate(lastHours: 1)
        #expect(rate == 0)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        var history = LoopExecutionHistory()
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 2.0))
        history.addEntry(LoopExecutionHistoryEntry(success: false, duration: 1.0))
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoopExecutionHistory.self, from: data)
        
        #expect(decoded.entries.count == 2)
    }
}

// MARK: - Loop Execution History Entry Tests

@Suite("Loop Execution History Entry")
struct LoopExecutionHistoryEntryTests {
    
    @Test("Create entry with all fields")
    func createEntryWithAllFields() {
        let entry = LoopExecutionHistoryEntry(
            success: true,
            duration: 2.5,
            doseEnacted: true,
            glucose: 120.0,
            errorMessage: nil
        )
        
        #expect(entry.success == true)
        #expect(entry.duration == 2.5)
        #expect(entry.doseEnacted == true)
        #expect(entry.glucose == 120.0)
        #expect(entry.errorMessage == nil)
    }
    
    @Test("Create failed entry")
    func createFailedEntry() {
        let entry = LoopExecutionHistoryEntry(
            success: false,
            duration: 0.5,
            errorMessage: "Pump communication failed"
        )
        
        #expect(entry.success == false)
        #expect(entry.errorMessage == "Pump communication failed")
    }
    
    @Test("Entry is identifiable")
    func entryIsIdentifiable() {
        let entry1 = LoopExecutionHistoryEntry(success: true, duration: 1.0)
        let entry2 = LoopExecutionHistoryEntry(success: true, duration: 1.0)
        
        #expect(entry1.id != entry2.id)
    }
}

// MARK: - Loop Execution Statistics Tests

@Suite("Loop Execution Statistics")
struct LoopExecutionStatisticsTests {
    
    @Test("Calculate statistics from history")
    func calculateStatisticsFromHistory() {
        var history = LoopExecutionHistory()
        
        // 3 successful, 1 failed
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 2.0, doseEnacted: true))
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 3.0, doseEnacted: false))
        history.addEntry(LoopExecutionHistoryEntry(success: false, duration: 1.0))
        history.addEntry(LoopExecutionHistoryEntry(success: true, duration: 2.0, doseEnacted: true))
        
        let stats = LoopExecutionStatistics.from(history: history, lastHours: 1)
        
        #expect(stats.totalExecutions == 4)
        #expect(stats.successfulExecutions == 3)
        #expect(stats.failedExecutions == 1)
        #expect(stats.dosesEnacted == 2)
        #expect(stats.successRate == 75.0)
    }
    
    @Test("Statistics with empty history")
    func statisticsWithEmptyHistory() {
        let history = LoopExecutionHistory()
        let stats = LoopExecutionStatistics.from(history: history)
        
        #expect(stats.totalExecutions == 0)
        #expect(stats.successRate == 0)
        #expect(stats.lastExecutionTime == nil)
    }
}

// MARK: - Background Loop Executor Tests

@Suite("Background Loop Executor")
struct BackgroundLoopExecutorTests {
    
    @Test("Initial state is idle")
    func initialStateIsIdle() async {
        let executor = BackgroundLoopExecutor()
        let state = await executor.state
        #expect(state == .idle)
    }
    
    @Test("Start changes state to scheduled")
    func startChangesStateToScheduled() async throws {
        let executor = BackgroundLoopExecutor()
        try await executor.start()
        
        let state = await executor.state
        #expect(state == .scheduled)
    }
    
    @Test("Stop returns to idle")
    func stopReturnsToIdle() async throws {
        let executor = BackgroundLoopExecutor()
        try await executor.start()
        await executor.stop()
        
        let state = await executor.state
        #expect(state == .idle)
    }
    
    @Test("Pause from scheduled")
    func pauseFromScheduled() async throws {
        let executor = BackgroundLoopExecutor()
        try await executor.start()
        await executor.pause()
        
        let state = await executor.state
        #expect(state == .paused)
    }
    
    @Test("Resume after pause")
    func resumeAfterPause() async throws {
        let executor = BackgroundLoopExecutor()
        try await executor.start()
        await executor.pause()
        try await executor.resume()
        
        let state = await executor.state
        #expect(state == .scheduled)
    }
    
    @Test("Execute loop without handler returns failure")
    func executeLoopWithoutHandler() async {
        let executor = BackgroundLoopExecutor()
        try? await executor.start()
        
        let result = await executor.executeLoop()
        
        #expect(result.success == false)
        #expect(result.errorMessage?.contains("not configured") == true)
    }
    
    @Test("Execute loop with handler")
    func executeLoopWithHandler() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure { 
            LoopExecutionResult.success(
                duration: 1.5,
                loopResult: LoopIterationSummary(glucose: 110.0),
                doseEnacted: true
            )
        }
        
        try await executor.start()
        let result = await executor.executeLoop()
        
        #expect(result.success == true)
        #expect(result.doseEnacted == true)
    }
    
    @Test("History tracks executions")
    func historyTracksExecutions() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            LoopExecutionResult.success(duration: 1.0, loopResult: nil, doseEnacted: false)
        }
        
        try await executor.start()
        _ = await executor.executeLoop()
        _ = await executor.executeLoop()
        _ = await executor.executeLoop()
        
        let history = await executor.getHistory()
        #expect(history.entries.count == 3)
    }
    
    @Test("Statistics calculated correctly")
    func statisticsCalculatedCorrectly() async throws {
        let executor = BackgroundLoopExecutor()
        
        // Alternate success/failure using a stateless approach
        let alternator = AlternatingResultProvider()
        await executor.configure {
            await alternator.next()
        }
        
        try await executor.start()
        _ = await executor.executeLoop()  // Success
        _ = await executor.executeLoop()  // Failure
        _ = await executor.executeLoop()  // Success
        _ = await executor.executeLoop()  // Failure
        
        let stats = await executor.getStatistics(lastHours: 1)
        
        #expect(stats.totalExecutions == 4)
        #expect(stats.successfulExecutions == 2)
        #expect(stats.failedExecutions == 2)
        #expect(stats.successRate == 50.0)
    }
    
    @Test("Consecutive failures tracked")
    func consecutiveFailuresTracked() async throws {
        let executor = BackgroundLoopExecutor()
        
        await executor.configure {
            LoopExecutionResult.failure("Always fail")
        }
        
        try await executor.start()
        _ = await executor.executeLoop()
        _ = await executor.executeLoop()
        
        let failures = await executor.getConsecutiveFailures()
        #expect(failures == 2)
    }
    
    @Test("Consecutive failures reset on success")
    func consecutiveFailuresResetOnSuccess() async throws {
        let executor = BackgroundLoopExecutor()
        
        // Use a switchable provider
        let provider = SwitchableResultProvider()
        await executor.configure {
            await provider.getResult()
        }
        
        try await executor.start()
        _ = await executor.executeLoop()  // Failure
        _ = await executor.executeLoop()  // Failure
        
        await provider.setSuccess()
        _ = await executor.executeLoop()  // Success
        
        let failures = await executor.getConsecutiveFailures()
        #expect(failures == 0)
    }
    
    @Test("State changes to error on too many failures")
    func stateChangesToErrorOnTooManyFailures() async throws {
        let config = BackgroundLoopConfiguration(maxConsecutiveFailures: 2)
        let executor = BackgroundLoopExecutor(configuration: config)
        
        await executor.configure {
            LoopExecutionResult.failure("Always fail")
        }
        
        try await executor.start()
        _ = await executor.executeLoop()
        _ = await executor.executeLoop()
        
        let state = await executor.state
        #expect(state == .error)
    }
    
    @Test("Update configuration")
    func updateConfiguration() async {
        let executor = BackgroundLoopExecutor()
        let newConfig = BackgroundLoopConfiguration(loopInterval: 180)
        
        await executor.updateConfiguration(newConfig)
        
        let config = await executor.configuration
        #expect(config.loopInterval == 180)
    }
}

// MARK: - Helper Actors for Testing

/// Alternating result provider for concurrency-safe testing
private actor AlternatingResultProvider {
    private var count = 0
    
    func next() -> LoopExecutionResult {
        count += 1
        if count % 2 == 0 {
            return LoopExecutionResult.failure("Test failure")
        }
        return LoopExecutionResult.success(duration: 1.0, loopResult: nil, doseEnacted: false)
    }
}

/// Switchable result provider for testing state changes
private actor SwitchableResultProvider {
    private var returnSuccess = false
    
    func setSuccess() {
        returnSuccess = true
    }
    
    func getResult() -> LoopExecutionResult {
        if returnSuccess {
            return LoopExecutionResult.success(duration: 1.0, loopResult: nil, doseEnacted: false)
        }
        return LoopExecutionResult.failure("Fail")
    }
}

// MARK: - Mock Executor Tests

@Suite("Mock Background Loop Executor")
struct MockBackgroundLoopExecutorTests {
    
    @Test("Mock tracks method calls")
    func mockTracksMethodCalls() async throws {
        let mock = MockBackgroundLoopExecutor()
        
        try await mock.start()
        _ = await mock.executeLoop()
        _ = await mock.executeLoop()
        await mock.stop()
        
        let startCount = await mock.startCallCount
        let stopCount = await mock.stopCallCount
        let executeCount = await mock.executeCallCount
        
        #expect(startCount == 1)
        #expect(stopCount == 1)
        #expect(executeCount == 2)
    }
    
    @Test("Mock returns default result")
    func mockReturnsDefaultResult() async {
        let mock = MockBackgroundLoopExecutor()
        
        let result = await mock.executeLoop()
        
        #expect(result.success == true)
    }
}

// MARK: - Loop Executor Error Tests

@Suite("Loop Executor Error")
struct LoopExecutorErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let errors: [LoopExecutorError] = [
            .invalidState(current: .idle, expected: .running),
            .notConfigured,
            .executionTimeout,
            .schedulingFailed("Test reason")
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("Invalid state error includes states")
    func invalidStateErrorIncludesStates() {
        let error = LoopExecutorError.invalidState(current: .paused, expected: .running)
        let description = error.errorDescription ?? ""
        
        #expect(description.contains("paused"))
        #expect(description.contains("running"))
    }
}

// MARK: - Loop Task Identifier Tests

@Suite("Loop Task Identifier")
struct LoopTaskIdentifierTests {
    
    @Test("Task identifiers are defined")
    func taskIdentifiersAreDefined() {
        #expect(!LoopTaskIdentifier.loopProcess.isEmpty)
        #expect(!LoopTaskIdentifier.algorithmProcess.isEmpty)
        #expect(!LoopTaskIdentifier.pumpCommunication.isEmpty)
    }
    
    @Test("Task identifiers are unique")
    func taskIdentifiersAreUnique() {
        let identifiers = [
            LoopTaskIdentifier.loopProcess,
            LoopTaskIdentifier.algorithmProcess,
            LoopTaskIdentifier.pumpCommunication
        ]
        let unique = Set(identifiers)
        #expect(identifiers.count == unique.count)
    }
    
    @Test("Task identifiers follow naming convention")
    func taskIdentifiersFollowNamingConvention() {
        #expect(LoopTaskIdentifier.loopProcess.hasPrefix("com.t1pal."))
        #expect(LoopTaskIdentifier.algorithmProcess.hasPrefix("com.t1pal."))
        #expect(LoopTaskIdentifier.pumpCommunication.hasPrefix("com.t1pal."))
    }
}
