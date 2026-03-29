// NetworkConditionSimulatorTests.swift
// NightscoutKitTests
//
// SPDX-License-Identifier: MIT
// Trace: INT-006

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Basic Condition Tests

@Suite("Network Condition Simulator")
struct NetworkConditionSimulatorTests {
    
    @Test("Normal condition proceeds immediately")
    func normalConditionProceeds() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.normal)
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs == 0)
        } else {
            Issue.record("Expected proceed result")
        }
    }
    
    @Test("Slow condition adds latency")
    func slowConditionAddsLatency() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.slow(latencyMs: 500))
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs == 500)
        } else {
            Issue.record("Expected proceed result with delay")
        }
    }
    
    @Test("Offline condition fails")
    func offlineConditionFails() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .fail(let error) = result {
            #expect(error == .offline)
        } else {
            Issue.record("Expected fail result")
        }
    }
    
    @Test("Very poor condition adds random delay")
    func veryPoorConditionRandomDelay() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.veryPoor)
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs >= 500)
            #expect(delayMs <= 2000)
        } else {
            Issue.record("Expected proceed result with delay")
        }
    }
}

// MARK: - Path-Specific Condition Tests

@Suite("Path-Specific Conditions")
struct PathConditionTests {
    
    @Test("Path condition overrides global")
    func pathConditionOverridesGlobal() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.normal)
        await simulator.setCondition(.slow(latencyMs: 1000), forPath: "/api/v1/treatments")
        
        let entriesResult = await simulator.apply(to: "/api/v1/entries.json")
        let treatmentsResult = await simulator.apply(to: "/api/v1/treatments.json")
        
        if case .proceed(let entriesDelay) = entriesResult {
            #expect(entriesDelay == 0, "Entries should use global condition")
        }
        
        if case .proceed(let treatmentsDelay) = treatmentsResult {
            #expect(treatmentsDelay == 1000, "Treatments should use path condition")
        }
    }
    
    @Test("Remove path condition restores global")
    func removePathConditionRestoresGlobal() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.slow(latencyMs: 100))
        await simulator.setCondition(.offline, forPath: "/api/v1/entries")
        
        // Should be offline
        var result = await simulator.apply(to: "/api/v1/entries.json")
        if case .fail = result {
            // Expected
        } else {
            Issue.record("Expected fail before removal")
        }
        
        // Remove path condition
        await simulator.removeCondition(forPath: "/api/v1/entries")
        
        // Should now use global
        result = await simulator.apply(to: "/api/v1/entries.json")
        if case .proceed(let delayMs) = result {
            #expect(delayMs == 100)
        } else {
            Issue.record("Expected proceed after removal")
        }
    }
    
    @Test("Clear path conditions")
    func clearPathConditions() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.normal)
        await simulator.setCondition(.offline, forPath: "/api/v1/entries")
        await simulator.setCondition(.offline, forPath: "/api/v1/treatments")
        
        await simulator.clearPathConditions()
        
        let entriesResult = await simulator.apply(to: "/api/v1/entries.json")
        let treatmentsResult = await simulator.apply(to: "/api/v1/treatments.json")
        
        if case .proceed = entriesResult, case .proceed = treatmentsResult {
            // Both should proceed now
        } else {
            Issue.record("Expected both to proceed after clearing")
        }
    }
}

// MARK: - Custom Condition Tests

@Suite("Custom Network Conditions")
struct CustomConditionTests {
    
    @Test("Custom condition with jitter")
    func customConditionWithJitter() async {
        let params = NetworkConditionParameters(
            latencyMs: 100,
            jitterMs: 50
        )
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.custom(params))
        
        let result = await simulator.apply(to: "/test")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs >= 100)
            #expect(delayMs <= 150)
        } else {
            Issue.record("Expected proceed result")
        }
    }
    
    @Test("WiFi preset has low latency")
    func wifiPresetLowLatency() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.wifi)
        
        let result = await simulator.apply(to: "/test")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs <= 30, "WiFi should have low latency")
        } else {
            Issue.record("Expected proceed result")
        }
    }
    
    @Test("3G preset has high latency")
    func threeGPresetHighLatency() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.threeG)
        
        let result = await simulator.apply(to: "/test")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs >= 300, "3G should have high latency")
        } else {
            Issue.record("Expected proceed result")
        }
    }
}

// MARK: - Probabilistic Condition Tests

@Suite("Probabilistic Conditions")
struct ProbabilisticConditionTests {
    
    @Test("Intermittent condition eventually drops")
    func intermittentConditionDrops() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.intermittent(dropRate: 0.5))
        
        var dropCount = 0
        var proceedCount = 0
        
        for _ in 0..<100 {
            let result = await simulator.apply(to: "/test")
            switch result {
            case .proceed:
                proceedCount += 1
            case .fail:
                dropCount += 1
            case .timeout:
                break
            }
        }
        
        // With 50% drop rate over 100 requests, should have both
        #expect(dropCount > 20, "Should have some drops")
        #expect(proceedCount > 20, "Should have some successes")
    }
    
    @Test("100% drop rate always fails")
    func fullDropRateAlwaysFails() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.intermittent(dropRate: 1.0))
        
        for _ in 0..<10 {
            let result = await simulator.apply(to: "/test")
            if case .fail = result {
                // Expected
            } else {
                Issue.record("Expected all requests to fail with 100% drop rate")
            }
        }
    }
    
    @Test("0% drop rate never fails")
    func zeroDropRateNeverFails() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.intermittent(dropRate: 0.0))
        
        for _ in 0..<10 {
            let result = await simulator.apply(to: "/test")
            if case .proceed = result {
                // Expected
            } else {
                Issue.record("Expected all requests to proceed with 0% drop rate")
            }
        }
    }
}

// MARK: - Event History Tests

@Suite("Event History")
struct EventHistoryTests {
    
    @Test("Events are recorded")
    func eventsAreRecorded() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.slow(latencyMs: 100))
        
        _ = await simulator.apply(to: "/api/v1/entries.json")
        _ = await simulator.apply(to: "/api/v1/treatments.json")
        
        let history = await simulator.getEventHistory()
        #expect(history.count == 2)
        #expect(history[0].path == "/api/v1/entries.json")
        #expect(history[1].path == "/api/v1/treatments.json")
    }
    
    @Test("Get events for path")
    func getEventsForPath() async {
        let simulator = NetworkConditionSimulator()
        
        _ = await simulator.apply(to: "/api/v1/entries.json")
        _ = await simulator.apply(to: "/api/v1/treatments.json")
        _ = await simulator.apply(to: "/api/v1/entries/123")
        
        let entriesEvents = await simulator.getEvents(forPath: "/api/v1/entries")
        #expect(entriesEvents.count == 2)
    }
    
    @Test("Failure count tracks failures")
    func failureCountTracksFailures() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        _ = await simulator.apply(to: "/test1")
        _ = await simulator.apply(to: "/test2")
        _ = await simulator.apply(to: "/test3")
        
        let failures = await simulator.failureCount()
        #expect(failures == 3)
    }
    
    @Test("Clear history")
    func clearHistory() async {
        let simulator = NetworkConditionSimulator()
        
        _ = await simulator.apply(to: "/test")
        _ = await simulator.apply(to: "/test")
        
        await simulator.clearHistory()
        
        let history = await simulator.getEventHistory()
        #expect(history.isEmpty)
    }
}

// MARK: - Enable/Disable Tests

@Suite("Enable/Disable")
struct EnableDisableTests {
    
    @Test("Disabled simulator bypasses conditions")
    func disabledSimulatorBypasses() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        await simulator.setEnabled(false)
        
        let result = await simulator.apply(to: "/test")
        
        if case .proceed(let delayMs) = result {
            #expect(delayMs == 0, "Should proceed immediately when disabled")
        } else {
            Issue.record("Expected proceed when disabled")
        }
    }
    
    @Test("Re-enabled simulator applies conditions")
    func reenabledSimulatorApplies() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        await simulator.setEnabled(false)
        await simulator.setEnabled(true)
        
        let result = await simulator.apply(to: "/test")
        
        if case .fail = result {
            // Expected
        } else {
            Issue.record("Expected fail when re-enabled")
        }
    }
}

// MARK: - Reset Tests

@Suite("Reset")
struct ResetTests {
    
    @Test("Reset clears all state")
    func resetClearsAllState() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        await simulator.setCondition(.slow(latencyMs: 100), forPath: "/slow")
        await simulator.setEnabled(false)
        _ = await simulator.apply(to: "/test")
        
        await simulator.reset()
        
        let condition = await simulator.getCondition()
        let history = await simulator.getEventHistory()
        
        #expect(condition == .normal)
        #expect(history.isEmpty, "History should be cleared by reset")
        
        // After reset, path conditions should be cleared too
        let result = await simulator.apply(to: "/slow")
        if case .proceed(let delayMs) = result {
            #expect(delayMs == 0, "Should use normal condition after reset")
        }
    }
}

// MARK: - Apply and Wait Tests

@Suite("Apply and Wait")
struct ApplyAndWaitTests {
    
    @Test("Apply and wait throws on offline")
    func applyAndWaitThrowsOnOffline() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        do {
            try await simulator.applyAndWait(for: "/test")
            Issue.record("Expected error")
        } catch let error as NetworkSimulatedError {
            #expect(error == .offline)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("Apply and wait delays on slow")
    func applyAndWaitDelaysOnSlow() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.slow(latencyMs: 50))
        
        let start = Date()
        try? await simulator.applyAndWait(for: "/test")
        let elapsed = Date().timeIntervalSince(start)
        
        #expect(elapsed >= 0.04, "Should have delayed at least 40ms")
    }
}

// MARK: - Error Description Tests

@Suite("Error Descriptions")
struct ErrorDescriptionTests {
    
    @Test("All errors have descriptions")
    func allErrorsHaveDescriptions() {
        let errors: [NetworkSimulatedError] = [
            .offline,
            .timeout,
            .connectionDropped,
            .dnsFailure,
            .sslError,
            .serverUnreachable
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription!.isEmpty == false)
        }
    }
}

// MARK: - Response Delay Integration Tests

@Suite("Response Delay Integration")
struct ResponseDelayTests {
    
    @Test("Response delay calculation")
    func responseDelayCalculation() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.slow(latencyMs: 500))
        
        let delay = await simulator.responseDelay(for: "/test")
        
        #expect(delay == 0.5, "500ms should equal 0.5 seconds")
    }
    
    @Test("Response delay zero on failure")
    func responseDelayZeroOnFailure() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        let delay = await simulator.responseDelay(for: "/test")
        
        #expect(delay == 0, "Failed requests should have zero delay")
    }
}
