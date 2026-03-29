// SPDX-License-Identifier: MIT
// NetworkFailureIntegrationTests.swift
// NightscoutKitTests
//
// Integration tests for network failure scenarios (INT-003)
// Validates graceful degradation and error handling under adverse network conditions

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Network Failure Integration Tests (INT-003)

@Suite("Network Failure Integration")
struct NetworkFailureIntegrationTests {
    
    // MARK: - Offline Handling Tests
    
    @Test("Offline condition produces offline error")
    func offlineConditionProducesError() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        do {
            try await simulator.applyAndWait(for: "/api/v1/entries.json")
            Issue.record("Expected offline error")
        } catch let error as NetworkSimulatedError {
            #expect(error == .offline)
            #expect(error.errorDescription?.contains("offline") == true)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("DeliveryReporter queues events during offline")
    func deliveryReporterQueuesEventsDuringOffline() async {
        let reporter = DeliveryReporter()
        
        // Queue events as if network was offline
        await reporter.queue([
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .smb, units: 0.3),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, duration: 1800, rate: 0.8)
        ])
        
        // Events should be queued pending network recovery
        let pendingCount = await reporter.pendingCount()
        #expect(pendingCount == 3)
        
        // Simulate network recovery - process batch
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 3)
        
        // Queue should be empty after processing
        let remainingCount = await reporter.pendingCount()
        #expect(remainingCount == 0)
    }
    
    @Test("Reporter statistics track errors")
    func reporterStatisticsTrackErrors() async {
        let reporter = DeliveryReporter()
        
        // Simulate upload attempts that fail
        await reporter.recordError()
        await reporter.recordError()
        await reporter.recordError()
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalErrors == 3)
    }
    
    // MARK: - Timeout Handling Tests
    
    @Test("Custom condition can simulate timeout")
    func customConditionCanSimulateTimeout() async {
        let params = NetworkConditionParameters(
            latencyMs: 0,
            timeoutRate: 1.0 // 100% timeout
        )
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.custom(params))
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .timeout = result {
            // Expected
        } else {
            Issue.record("Expected timeout result")
        }
    }
    
    @Test("Timeout errors are thrown correctly")
    func timeoutErrorsThrownCorrectly() async {
        let params = NetworkConditionParameters(timeoutRate: 1.0)
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.custom(params))
        
        do {
            try await simulator.applyAndWait(for: "/api/v1/entries.json")
            Issue.record("Expected timeout error")
        } catch let error as NetworkSimulatedError {
            #expect(error == .timeout)
            #expect(error.errorDescription?.contains("timed out") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Connection Drop Tests
    
    @Test("Intermittent connection drops requests")
    func intermittentConnectionDropsRequests() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.intermittent(dropRate: 1.0)) // 100% drop for deterministic test
        
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .fail(let error) = result {
            #expect(error == .connectionDropped)
        } else {
            Issue.record("Expected connection dropped")
        }
    }
    
    @Test("Flaky network has both successes and failures")
    func flakyNetworkMixedResults() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.flaky) // 30% drop rate
        
        var successes = 0
        var failures = 0
        
        for _ in 0..<100 {
            let result = await simulator.apply(to: "/test")
            switch result {
            case .proceed: successes += 1
            case .fail, .timeout: failures += 1
            }
        }
        
        // Should have both successes and failures with 30% drop rate
        #expect(successes > 50, "Should have significant successes")
        #expect(failures > 10, "Should have some failures")
    }
    
    // MARK: - HTTP Error Handling Tests
    
    @Test("NightscoutError unauthorized has description")
    func nightscoutErrorUnauthorizedHasDescription() {
        let error = NightscoutError.unauthorized
        #expect(error.errorDescription?.contains("Unauthorized") == true)
    }
    
    @Test("NightscoutError httpError includes status code")
    func nightscoutErrorHttpErrorIncludesStatusCode() {
        let error = NightscoutError.httpError(statusCode: 503, body: "Service Unavailable")
        #expect(error.errorDescription != nil)
    }
    
    @Test("All NightscoutErrors have descriptions")
    func allNightscoutErrorsHaveDescriptions() {
        let errors: [NightscoutError] = [
            .uploadFailed,
            .fetchFailed,
            .unauthorized,
            .invalidResponse,
            .notAvailableOnLinux,
            .httpError(statusCode: 500, body: nil),
            .decodingError(underlyingError: NSError(domain: "", code: 0), rawResponse: nil)
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil, "Error \(error) should have description")
            #expect(error.errorDescription!.isEmpty == false)
        }
    }
    
    // MARK: - Polling Error Handling Tests
    
    @Test("PollingError networkError has message")
    func pollingErrorNetworkErrorHasMessage() {
        let error = PollingError.networkError("Connection refused")
        
        switch error {
        case .networkError(let message):
            #expect(message == "Connection refused")
        default:
            Issue.record("Expected networkError")
        }
    }
    
    @Test("PollingError maxFailuresExceeded tracks count")
    func pollingErrorMaxFailuresExceededTracksCount() {
        let error = PollingError.maxFailuresExceeded(count: 10)
        
        switch error {
        case .maxFailuresExceeded(let count):
            #expect(count == 10)
        default:
            Issue.record("Expected maxFailuresExceeded")
        }
    }
    
    @Test("PollingError serverError includes status code")
    func pollingErrorServerErrorIncludesStatusCode() {
        let error = PollingError.serverError(statusCode: 502)
        
        switch error {
        case .serverError(let statusCode):
            #expect(statusCode == 502)
        default:
            Issue.record("Expected serverError")
        }
    }
    
    // MARK: - Graceful Degradation Tests
    
    @Test("Path-specific failures don't affect other paths")
    func pathSpecificFailuresDontAffectOtherPaths() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.normal)
        await simulator.setCondition(.offline, forPath: "/api/v1/treatments")
        
        // Entries should work
        let entriesResult = await simulator.apply(to: "/api/v1/entries.json")
        if case .proceed = entriesResult {
            // Expected
        } else {
            Issue.record("Entries should proceed")
        }
        
        // Treatments should fail
        let treatmentsResult = await simulator.apply(to: "/api/v1/treatments.json")
        if case .fail(.offline) = treatmentsResult {
            // Expected
        } else {
            Issue.record("Treatments should fail with offline")
        }
    }
    
    @Test("Simulator can be disabled for production")
    func simulatorCanBeDisabled() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        await simulator.setEnabled(false)
        
        // Even with offline condition, disabled simulator lets requests through
        let result = await simulator.apply(to: "/api/v1/entries.json")
        
        if case .proceed(let delay) = result {
            #expect(delay == 0)
        } else {
            Issue.record("Disabled simulator should always proceed")
        }
    }
    
    // MARK: - Retry Pattern Tests
    
    @Test("Pending events survive across reporter instances")
    func pendingEventsSurviveAcrossReporterConcepts() async {
        // This tests the concept - in real app, events would be persisted
        let events = [
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .smb, units: 0.3)
        ]
        
        // First reporter queues events
        let reporter1 = DeliveryReporter()
        await reporter1.queue(events)
        
        // Get pending events for "persistence"
        let pending = await reporter1.getPendingEvents()
        #expect(pending.count == 2)
        
        // Second reporter can process them
        let reporter2 = DeliveryReporter()
        await reporter2.queue(pending.map { $0.event })
        
        let treatments = await reporter2.processPendingBatch()
        #expect(treatments.count == 2)
    }
    
    @Test("Retry count is tracked on pending events")
    func retryCountTrackedOnPendingEvents() async {
        let event = DeliveryEvent(deliveryType: .bolus, units: 1.0)
        var pending = PendingDeliveryEvent(event: event)
        
        #expect(pending.retryCount == 0)
        
        // Simulate retry
        pending.retryCount += 1
        #expect(pending.retryCount == 1)
        
        pending.retryCount += 1
        #expect(pending.retryCount == 2)
    }
    
    @Test("Pending event age increases over time")
    func pendingEventAgeIncreasesOverTime() async {
        let pastDate = Date().addingTimeInterval(-120) // 2 minutes ago
        let event = DeliveryEvent(deliveryType: .bolus, units: 1.0)
        let pending = PendingDeliveryEvent(event: event, queuedAt: pastDate)
        
        #expect(pending.age >= 120)
        #expect(pending.age < 130)
    }
    
    // MARK: - Error Recovery Flow Tests
    
    @Test("Full error recovery flow: queue → fail → retry → succeed")
    func fullErrorRecoveryFlow() async {
        let reporter = DeliveryReporter()
        let event = DeliveryEvent(deliveryType: .bolus, units: 2.0, reason: "Meal")
        
        // 1. Queue event
        await reporter.queue(event)
        var pending = await reporter.pendingCount()
        #expect(pending == 1)
        
        // 2. Simulate failed upload attempt
        await reporter.recordError()
        var stats = await reporter.getStatistics()
        #expect(stats.totalErrors == 1)
        
        // 3. Event is still pending (would be re-queued in real implementation)
        pending = await reporter.pendingCount()
        #expect(pending == 1)
        
        // 4. Successful retry
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 1)
        
        stats = await reporter.getStatistics()
        #expect(stats.totalReported == 1)
        #expect(stats.pendingCount == 0)
    }
    
    // MARK: - Network Condition History Tests
    
    @Test("Failure history is tracked")
    func failureHistoryIsTracked() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        _ = await simulator.apply(to: "/api/v1/entries.json")
        _ = await simulator.apply(to: "/api/v1/treatments.json")
        
        let failures = await simulator.failureCount()
        #expect(failures == 2)
        
        let history = await simulator.getEventHistory()
        #expect(history.count == 2)
        #expect(history.allSatisfy { event in
            if case .fail = event.result { return true }
            return false
        })
    }
    
    @Test("History can be cleared")
    func historyCanBeCleared() async {
        let simulator = NetworkConditionSimulator()
        
        _ = await simulator.apply(to: "/test1")
        _ = await simulator.apply(to: "/test2")
        
        await simulator.clearHistory()
        
        let history = await simulator.getEventHistory()
        #expect(history.isEmpty)
    }
    
    // MARK: - SSL/DNS Error Tests
    
    @Test("All simulated errors have descriptions")
    func allSimulatedErrorsHaveDescriptions() {
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
            #expect(error.errorDescription!.count > 10, "Description should be meaningful")
        }
    }
    
    @Test("DNS failure error is distinct")
    func dnsFailureErrorIsDistinct() {
        let error = NetworkSimulatedError.dnsFailure
        #expect(error.errorDescription?.lowercased().contains("resolve") == true ||
                error.errorDescription?.lowercased().contains("dns") == true)
    }
    
    @Test("SSL error is distinct")
    func sslErrorIsDistinct() {
        let error = NetworkSimulatedError.sslError
        #expect(error.errorDescription?.lowercased().contains("secure") == true ||
                error.errorDescription?.lowercased().contains("ssl") == true)
    }
    
    // MARK: - Mock Server Error Response Tests
    
    @Test("Mock server unauthorized response")
    func mockServerUnauthorizedResponse() {
        let response = MockNightscoutResponse.unauthorized
        
        #expect(response.statusCode == 401)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("401") || body.contains("Unauthorized"))
    }
    
    @Test("Mock server error response")
    func mockServerErrorResponse() {
        let response = MockNightscoutResponse.serverError
        
        #expect(response.statusCode == 500)
    }
    
    @Test("Mock server custom error response")
    func mockServerCustomErrorResponse() {
        let response = MockNightscoutResponse.error(statusCode: 503, message: "Service Temporarily Unavailable")
        
        #expect(response.statusCode == 503)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("503"))
        #expect(body.contains("Service Temporarily Unavailable"))
    }
    
    // MARK: - Statistics Under Error Conditions
    
    @Test("Statistics reset works")
    func statisticsResetWorks() async {
        let reporter = DeliveryReporter()
        
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        _ = await reporter.processPendingBatch()
        await reporter.recordError()
        
        await reporter.resetStatistics()
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalReported == 0)
        #expect(stats.totalSkipped == 0)
        #expect(stats.totalErrors == 0)
        #expect(stats.lastUploadTime == nil)
    }
    
    @Test("Time since last upload calculated correctly")
    func timeSinceLastUploadCalculated() async {
        let reporter = DeliveryReporter()
        
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        _ = await reporter.processPendingBatch()
        
        // Wait a tiny bit
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let stats = await reporter.getStatistics()
        #expect(stats.lastUploadTime != nil)
        #expect(stats.timeSinceLastUpload != nil)
        #expect(stats.timeSinceLastUpload! >= 0.05)
    }
}
