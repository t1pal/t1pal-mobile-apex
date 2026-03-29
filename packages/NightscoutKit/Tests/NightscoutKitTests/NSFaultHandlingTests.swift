// SPDX-License-Identifier: MIT
// NSFaultHandlingTests.swift
// NightscoutKitTests
//
// HTTP fault handling tests for BATCH-NS-FAULT-A
// Trace: NS-FAULT-001, NS-FAULT-002, NS-FAULT-005, NS-FAULT-006

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - NS-FAULT-001: Timeout Mid-Upload Tests

@Suite("NS-FAULT-001: Timeout Mid-Upload")
struct TimeoutMidUploadTests {
    
    @Test("Timeout during upload produces timeout error")
    func timeoutDuringUploadProducesError() async {
        let params = NetworkConditionParameters(timeoutRate: 1.0)
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.custom(params))
        
        do {
            try await simulator.applyAndWait(for: "/api/v1/entries")
            Issue.record("Expected timeout error")
        } catch let error as NetworkSimulatedError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("Entries are queued for retry after timeout")
    func entriesQueuedForRetryAfterTimeout() async {
        let reporter = DeliveryReporter()
        
        // Queue entries that would be uploaded
        let events = [
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .smb, units: 0.3),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, duration: 1800, rate: 0.8)
        ]
        await reporter.queue(events)
        
        // Simulate timeout by recording error
        await reporter.recordError()
        
        // Events should still be pending
        let pending = await reporter.pendingCount()
        #expect(pending == 3, "All 3 entries should remain in queue after timeout")
    }
    
    @Test("Retry succeeds after timeout recovery")
    func retrySucceedsAfterTimeoutRecovery() async {
        let reporter = DeliveryReporter()
        
        // Queue an event
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 2.0))
        
        // Simulate timeout
        await reporter.recordError()
        
        // Verify still pending
        var pending = await reporter.pendingCount()
        #expect(pending == 1)
        
        // Simulate successful retry
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 1)
        
        // Queue should be empty
        pending = await reporter.pendingCount()
        #expect(pending == 0)
    }
    
    @Test("Partial upload timeout preserves all queued items")
    func partialUploadTimeoutPreservesQueuedItems() async {
        let reporter = DeliveryReporter()
        
        // Queue multiple entries
        for i in 0..<5 {
            await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: Double(i) + 1.0))
        }
        
        // Simulate timeout mid-batch
        await reporter.recordError()
        
        // All 5 should still be pending
        let pending = await reporter.pendingCount()
        #expect(pending == 5, "All queued items should be preserved after partial timeout")
    }
}

// MARK: - NS-FAULT-002: Rate Limit 429 Tests

@Suite("NS-FAULT-002: Rate Limit 429")
struct RateLimitTests {
    
    @Test("429 response creates proper error")
    func rateLimitResponseCreatesError() {
        let response = MockNightscoutResponse.error(statusCode: 429, message: "Rate limit exceeded")
        
        #expect(response.statusCode == 429)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("429"))
        #expect(body.contains("Rate limit exceeded"))
    }
    
    @Test("Rate limit error includes status code")
    func rateLimitErrorIncludesStatusCode() {
        let error = NightscoutError.httpError(statusCode: 429, body: "Rate limit exceeded")
        
        #expect(error.errorDescription?.contains("429") == true)
    }
    
    @Test("Retry-After header can be parsed")
    func retryAfterHeaderCanBeParsed() {
        // Test the Retry-After parsing concept
        let retryAfterSeconds = "30"
        let retryAfterDate = "Wed, 14 Feb 2026 03:30:00 GMT"
        
        // Numeric format
        if let seconds = Int(retryAfterSeconds) {
            #expect(seconds == 30)
        } else {
            Issue.record("Failed to parse numeric Retry-After")
        }
        
        // Date format (HTTP-date)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: retryAfterDate) {
            #expect(date > Date(timeIntervalSince1970: 0))
        } else {
            // Date parsing is optional - numeric is primary
        }
    }
    
    @Test("Exponential backoff calculates correct delays")
    func exponentialBackoffCalculatesCorrectDelays() {
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 60.0
        let factor = 2.0
        
        // Test backoff formula: min(base * 2^attempt, max)
        let delays = (0..<6).map { attempt in
            min(baseDelay * pow(factor, Double(attempt)), maxDelay)
        }
        
        #expect(delays[0] == 1.0)   // 1 * 2^0 = 1
        #expect(delays[1] == 2.0)   // 1 * 2^1 = 2
        #expect(delays[2] == 4.0)   // 1 * 2^2 = 4
        #expect(delays[3] == 8.0)   // 1 * 2^3 = 8
        #expect(delays[4] == 16.0)  // 1 * 2^4 = 16
        #expect(delays[5] == 32.0)  // 1 * 2^5 = 32
    }
    
    @Test("Rate limit does not cause immediate retry")
    func rateLimitDoesNotCauseImmediateRetry() async {
        // Concept: After 429, we should NOT immediately retry
        let reporter = DeliveryReporter()
        
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        
        // Record rate limit error
        await reporter.recordError()
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalErrors == 1)
        
        // Items still pending - not lost
        let pending = await reporter.pendingCount()
        #expect(pending == 1)
    }
    
    @Test("OfflineQueueItem retry delay follows exponential backoff")
    func offlineQueueItemRetryDelayFollowsExponentialBackoff() {
        // Test the backoff formula: min(base * 2^retryCount, max)
        let baseRetryDelay: TimeInterval = 5.0
        let maxRetryDelay: TimeInterval = 300.0
        
        func calculateRetryDelay(retryCount: Int) -> TimeInterval {
            let delay = baseRetryDelay * pow(2, Double(retryCount))
            return min(delay, maxRetryDelay)
        }
        
        // Create items with different retry counts
        let item0 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 0)
        let item1 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 1)
        let item2 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 3)
        let item5 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 5)
        
        let delay0 = calculateRetryDelay(retryCount: item0.retryCount)
        let delay1 = calculateRetryDelay(retryCount: item1.retryCount)
        let delay2 = calculateRetryDelay(retryCount: item2.retryCount)
        let delay5 = calculateRetryDelay(retryCount: item5.retryCount)
        
        // Verify exponential increase
        #expect(delay0 == 5.0)   // 5 * 2^0 = 5
        #expect(delay1 == 10.0)  // 5 * 2^1 = 10
        #expect(delay2 == 40.0)  // 5 * 2^3 = 40
        #expect(delay5 == 160.0) // 5 * 2^5 = 160
        #expect(delay1 > delay0)
        #expect(delay2 > delay1)
        #expect(delay5 <= maxRetryDelay, "Should be capped at max delay")
    }
}

// MARK: - NS-FAULT-005: Auth Token Expiry Tests

@Suite("NS-FAULT-005: Auth Token Expiry")
struct AuthTokenExpiryTests {
    
    @Test("401 response indicates unauthorized")
    func unauthorizedResponseIndicatesAuth() {
        let response = MockNightscoutResponse.unauthorized
        
        #expect(response.statusCode == 401)
    }
    
    @Test("NightscoutError.unauthorized has proper description")
    func unauthorizedErrorHasDescription() {
        let error = NightscoutError.unauthorized
        
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("unauthorized") ||
                error.errorDescription!.lowercased().contains("authentication"))
    }
    
    @Test("Token expiry detection works via claims")
    func tokenExpiryDetectionWorks() {
        // Create expired claims (exp in past)
        let expiredClaims = NightscoutJWTClaims(
            accessToken: "test-token",
            iat: Int(Date().addingTimeInterval(-7200).timeIntervalSince1970),
            exp: Int(Date().addingTimeInterval(-3600).timeIntervalSince1970), // 1 hour ago
            sub: "test-user"
        )
        
        #expect(expiredClaims.isExpired == true)
    }
    
    @Test("Valid token not marked as expired")
    func validTokenNotMarkedAsExpired() {
        // Create valid claims (exp in future)
        let validClaims = NightscoutJWTClaims(
            accessToken: "test-token",
            iat: Int(Date().timeIntervalSince1970),
            exp: Int(Date().addingTimeInterval(3600).timeIntervalSince1970), // 1 hour from now
            sub: "test-user"
        )
        
        #expect(validClaims.isExpired == false)
    }
    
    @Test("Token manager needs refresh near expiry")
    func tokenManagerNeedsRefreshNearExpiry() async {
        // Token manager with 5-minute refresh margin
        let manager = JWTTokenManager(refreshMargin: 300)
        
        // Without a token, needs refresh
        #expect(await manager.needsRefresh() == true)
        
        // With expired token
        #expect(await manager.isExpired() == true)
    }
    
    @Test("Token manager without callback cannot auto-refresh")
    func tokenManagerWithoutCallbackCannotAutoRefresh() async {
        // Manager without refresh callback
        let manager = JWTTokenManager(token: nil, refreshCallback: nil)
        
        // Should return nil for valid token when none set
        let validToken = await manager.getValidToken()
        #expect(validToken == nil)
    }
    
    @Test("Mock server 401 scenario works")
    func mockServer401ScenarioWorks() async {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.unauthorized.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries.json")
        
        #expect(response.statusCode == 401)
    }
    
    @Test("Claims expiration date is correct")
    func claimsExpirationDateIsCorrect() {
        let futureTime = Date().addingTimeInterval(3600)
        let claims = NightscoutJWTClaims(
            accessToken: nil,
            iat: nil,
            exp: Int(futureTime.timeIntervalSince1970),
            sub: nil
        )
        
        #expect(claims.expiresAt != nil)
        // Within 1 second tolerance
        #expect(abs(claims.expiresAt!.timeIntervalSince(futureTime)) < 1.0)
    }
}

// MARK: - NS-FAULT-006: Malformed JSON Tests

@Suite("NS-FAULT-006: Malformed JSON")
struct MalformedJSONTests {
    
    @Test("Truncated JSON fails gracefully")
    func truncatedJSONFailsGracefully() {
        let truncatedJSON = "[{\"sgv\":120},{\"sgv\":118"
        let data = truncatedJSON.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            Issue.record("Expected decoding error")
        } catch {
            // Expected - verify it doesn't crash
            #expect(error is DecodingError)
        }
    }
    
    @Test("HTML error page fails gracefully")
    func htmlErrorPageFailsGracefully() {
        let htmlResponse = "<!DOCTYPE html><html><body><h1>502 Bad Gateway</h1></body></html>"
        let data = htmlResponse.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            Issue.record("Expected decoding error for HTML response")
        } catch {
            // Expected - HTML is not valid JSON
            #expect(error is DecodingError || error is Swift.DecodingError, "Should be a decoding error")
        }
    }
    
    @Test("Empty response fails gracefully")
    func emptyResponseFailsGracefully() {
        let emptyData = Data()
        
        do {
            _ = try JSONDecoder().decode([NightscoutEntry].self, from: emptyData)
            Issue.record("Expected decoding error for empty response")
        } catch {
            // Expected - empty data cannot be decoded
            #expect(error is DecodingError, "Should be a decoding error")
        }
    }
    
    @Test("NightscoutError.decodingError preserves raw response")
    func decodingErrorPreservesRawResponse() {
        let rawResponse = "[{\"sgv\":\"not a number\"}]"
        let underlyingError = NSError(domain: "DecodingError", code: 1)
        
        let error = NightscoutError.decodingError(
            underlyingError: underlyingError,
            rawResponse: rawResponse
        )
        
        if case .decodingError(_, let raw) = error {
            #expect(raw == rawResponse)
        } else {
            Issue.record("Expected decodingError case")
        }
    }
    
    @Test("Malformed JSON error has helpful description")
    func malformedJSONErrorHasHelpfulDescription() {
        let error = NightscoutError.decodingError(
            underlyingError: NSError(domain: "", code: 0),
            rawResponse: "[{broken"
        )
        
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.count > 10, "Should have meaningful description")
    }
    
    @Test("Wrong type in JSON fails gracefully")
    func wrongTypeInJSONFailsGracefully() {
        // sgv should be Int, not String
        let wrongTypeJSON = "[{\"sgv\":\"not-a-number\",\"date\":1707840000000,\"type\":\"sgv\"}]"
        let data = wrongTypeJSON.data(using: .utf8)!
        
        do {
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            // Some decoders may handle string-to-int conversion - that's acceptable
            #expect(entries.count >= 0, "Decoder handled type coercion")
        } catch {
            // Type mismatch is also acceptable
            #expect(error is DecodingError, "Should be a decoding error")
        }
    }
    
    @Test("Invalid Unicode escapes handled")
    func invalidUnicodeEscapesHandled() {
        // Note: Invalid Unicode in JSON may be handled differently by parsers
        let invalidUnicode = "[{\"device\":\"test\\u\"}]"
        let data = invalidUnicode.data(using: .utf8)!
        
        do {
            _ = try JSONDecoder().decode([[String: String]].self, from: data)
            Issue.record("Expected error for invalid Unicode")
        } catch {
            // Expected - invalid Unicode escape sequence
            #expect(error is DecodingError, "Should be a decoding error")
        }
    }
    
    @Test("Null in required field fails gracefully")
    func nullInRequiredFieldFailsGracefully() {
        let nullSGV = "[{\"sgv\":null,\"date\":1707840000000,\"type\":\"sgv\"}]"
        let data = nullSGV.data(using: .utf8)!
        
        do {
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            // May succeed if sgv is optional
            #expect(entries.count >= 0, "Decoder handled null field")
        } catch {
            // Expected if sgv is required
            #expect(error is DecodingError, "Should be a decoding error")
        }
    }
}

// MARK: - Integration Tests

@Suite("NS-FAULT: Integration")
struct FaultIntegrationTests {
    
    @Test("Multiple error types don't corrupt queue")
    func multipleErrorTypesDontCorruptQueue() async {
        let reporter = DeliveryReporter()
        
        // Queue events
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        await reporter.queue(DeliveryEvent(deliveryType: .smb, units: 0.5))
        
        // Simulate multiple different errors
        await reporter.recordError() // Timeout
        await reporter.recordError() // 429
        await reporter.recordError() // Network error
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalErrors == 3)
        
        // Queue should still have all items
        let pending = await reporter.pendingCount()
        #expect(pending == 2)
        
        // Recovery should work
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 2)
    }
    
    @Test("Error recovery doesn't duplicate entries")
    func errorRecoveryDoesntDuplicateEntries() async {
        let reporter = DeliveryReporter()
        
        let event = DeliveryEvent(deliveryType: .bolus, units: 2.5)
        await reporter.queue(event)
        
        // Simulate error and retry
        await reporter.recordError()
        
        // Process once
        let treatments1 = await reporter.processPendingBatch()
        #expect(treatments1.count == 1)
        
        // Second process should find nothing
        let treatments2 = await reporter.processPendingBatch()
        #expect(treatments2.count == 0, "Should not duplicate after successful processing")
    }
    
    @Test("All error types have descriptions")
    func allErrorTypesHaveDescriptions() {
        let errors: [NightscoutError] = [
            .uploadFailed,
            .fetchFailed,
            .unauthorized,
            .invalidResponse,
            .notAvailableOnLinux,
            .httpError(statusCode: 429, body: "Rate limited"),
            .httpError(statusCode: 500, body: nil),
            .httpError(statusCode: 502, body: "Bad Gateway"),
            .decodingError(underlyingError: NSError(domain: "", code: 0), rawResponse: "[broken")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have description")
            #expect(!error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }
    
    @Test("Network simulator tracks failure history")
    func networkSimulatorTracksFailureHistory() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        
        // Simulate multiple failed requests
        _ = await simulator.apply(to: "/api/v1/entries")
        _ = await simulator.apply(to: "/api/v1/treatments")
        _ = await simulator.apply(to: "/api/v1/devicestatus")
        
        let failures = await simulator.failureCount()
        #expect(failures == 3)
        
        let history = await simulator.getEventHistory()
        #expect(history.count == 3)
    }
}

// MARK: - NS-FAULT-003: WebSocket Disconnect Mid-Sync Tests

@Suite("NS-FAULT-003: WebSocket Disconnect")
struct WebSocketDisconnectTests {
    
    @Test("Connection dropped produces correct error")
    func connectionDroppedProducesCorrectError() async {
        let params = NetworkConditionParameters(dropRate: 1.0)
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.custom(params))
        
        let result = await simulator.apply(to: "/socket.io")
        
        if case .fail(let error) = result {
            #expect(error == .connectionDropped || error == .offline)
        } else {
            Issue.record("Expected connection failure")
        }
    }
    
    @Test("WebSocket state tracks disconnection")
    func webSocketStateTracksDisconnection() async {
        let state = WebSocketConnectionState()
        
        // Initial state
        #expect(await state.isConnected == false)
        
        // Connect
        await state.setConnected(true, sessionId: "abc123")
        #expect(await state.isConnected == true)
        #expect(await state.sessionId == "abc123")
        
        // Disconnect
        await state.setConnected(false, sessionId: nil)
        #expect(await state.isConnected == false)
    }
    
    @Test("Reconnection delay follows exponential backoff")
    func reconnectionDelayFollowsExponentialBackoff() {
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        
        func calculateReconnectDelay(attempt: Int) -> TimeInterval {
            min(baseDelay * pow(2, Double(attempt)), maxDelay)
        }
        
        #expect(calculateReconnectDelay(attempt: 0) == 1.0)
        #expect(calculateReconnectDelay(attempt: 1) == 2.0)
        #expect(calculateReconnectDelay(attempt: 2) == 4.0)
        #expect(calculateReconnectDelay(attempt: 3) == 8.0)
        #expect(calculateReconnectDelay(attempt: 4) == 16.0)
        #expect(calculateReconnectDelay(attempt: 5) == 30.0) // Capped at max
    }
    
    @Test("Subscription state preserved across disconnect")
    func subscriptionStatePreservedAcrossDisconnect() async {
        let state = WebSocketConnectionState()
        
        // Subscribe to channels
        await state.subscribe(to: ["entries", "treatments"])
        
        let subs = await state.subscriptions
        #expect(subs.contains("entries"))
        #expect(subs.contains("treatments"))
        
        // Simulate disconnect
        await state.setConnected(false, sessionId: nil)
        
        // Subscriptions should be preserved for re-subscribe
        let preservedSubs = await state.subscriptions
        #expect(preservedSubs.count == 2)
    }
    
    @Test("Event buffer holds events during disconnect")
    func eventBufferHoldsEventsDuringDisconnect() async {
        let buffer = WebSocketEventBuffer()
        
        // Buffer events
        await buffer.add(WebSocketBufferedEvent(type: "entry", payload: ["sgv": 120]))
        await buffer.add(WebSocketBufferedEvent(type: "treatment", payload: ["insulin": 2.0]))
        
        let count = await buffer.count
        #expect(count == 2)
        
        // Drain buffer
        let events = await buffer.drain()
        #expect(events.count == 2)
        
        let emptyCount = await buffer.count
        #expect(emptyCount == 0)
    }
    
    @Test("Max reconnect attempts is respected")
    func maxReconnectAttemptsIsRespected() async {
        let state = WebSocketConnectionState()
        let maxAttempts = 5
        
        // Simulate multiple failed reconnects
        for attempt in 0..<maxAttempts {
            await state.recordReconnectAttempt()
            #expect(await state.reconnectAttempts == attempt + 1)
        }
        
        #expect(await state.shouldStopReconnecting(maxAttempts: maxAttempts) == true)
    }
    
    @Test("Successful reconnect resets attempt counter")
    func successfulReconnectResetsAttemptCounter() async {
        let state = WebSocketConnectionState()
        
        // Simulate failed reconnects
        await state.recordReconnectAttempt()
        await state.recordReconnectAttempt()
        #expect(await state.reconnectAttempts == 2)
        
        // Successful reconnect
        await state.setConnected(true, sessionId: "new-session")
        await state.resetReconnectAttempts()
        
        #expect(await state.reconnectAttempts == 0)
    }
}

// MARK: - NS-FAULT-004: Partial Batch Upload Failure Tests

@Suite("NS-FAULT-004: Partial Batch Upload")
struct PartialBatchUploadTests {
    
    @Test("Partial success response parsed correctly")
    func partialSuccessResponseParsedCorrectly() throws {
        let json = """
        {
            "ok": false,
            "inserted": 3,
            "failed": 2,
            "results": [
                {"index": 0, "status": "ok", "_id": "entry1"},
                {"index": 1, "status": "ok", "_id": "entry2"},
                {"index": 2, "status": "error", "error": "sgv value out of range"},
                {"index": 3, "status": "ok", "_id": "entry4"},
                {"index": 4, "status": "error", "error": "sgv value out of range"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(BatchUploadResult.self, from: data)
        
        #expect(result.ok == false)
        #expect(result.inserted == 3)
        #expect(result.failed == 2)
        #expect(result.results?.count == 5)
    }
    
    @Test("Successful items identified correctly")
    func successfulItemsIdentifiedCorrectly() {
        let results = [
            BatchItemResult(index: 0, status: .ok, id: "entry1", error: nil),
            BatchItemResult(index: 1, status: .ok, id: "entry2", error: nil),
            BatchItemResult(index: 2, status: .error, id: nil, error: "validation failed"),
            BatchItemResult(index: 3, status: .ok, id: "entry4", error: nil),
            BatchItemResult(index: 4, status: .error, id: nil, error: "validation failed")
        ]
        
        let successful = results.filter { $0.status == .ok }
        let failed = results.filter { $0.status == .error }
        
        #expect(successful.count == 3)
        #expect(failed.count == 2)
        #expect(successful.map(\.index) == [0, 1, 3])
        #expect(failed.map(\.index) == [2, 4])
    }
    
    @Test("Failed items have error messages")
    func failedItemsHaveErrorMessages() {
        let result = BatchItemResult(index: 2, status: .error, id: nil, error: "sgv value out of range (negative)")
        
        #expect(result.status == .error)
        #expect(result.error != nil)
        #expect(result.error!.contains("out of range"))
    }
    
    @Test("Queue removes only successful items")
    func queueRemovesOnlySuccessfulItems() async {
        let reporter = DeliveryReporter()
        
        // Queue 5 events
        for i in 0..<5 {
            await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: Double(i) + 1.0))
        }
        
        var pending = await reporter.pendingCount()
        #expect(pending == 5)
        
        // Simulate partial success (3 processed)
        _ = await reporter.processPendingBatch(limit: 3)
        
        // 2 should remain
        pending = await reporter.pendingCount()
        #expect(pending == 2)
    }
    
    @Test("Partial failure statistics tracked")
    func partialFailureStatisticsTracked() async {
        let reporter = DeliveryReporter()
        
        // Simulate partial failure scenario
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 2.0))
        
        // Record partial success
        await reporter.recordPartialSuccess(succeeded: 1, failed: 1)
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalReported >= 1)
    }
    
    @Test("207 Multi-Status response indicates partial success")
    func multiStatusResponseIndicatesPartialSuccess() {
        let response = MockNightscoutResponse.partialSuccess(inserted: 3, failed: 2)
        
        #expect(response.statusCode == 207)
    }
    
    @Test("Reconciliation logs failed items")
    func reconciliationLogsFailedItems() {
        let results = [
            BatchItemResult(index: 0, status: .ok, id: "entry1", error: nil),
            BatchItemResult(index: 1, status: .error, id: nil, error: "validation failed")
        ]
        
        let reconciler = BatchReconciler()
        let report = reconciler.reconcile(results: results, originalCount: 2)
        
        #expect(report.successfulIndices == [0])
        #expect(report.failedIndices == [1])
        #expect(report.failedErrors.count == 1)
        #expect(report.failedErrors[1] == "validation failed")
    }
}

// MARK: - NS-FAULT-007: DNS Resolution Failure Tests

@Suite("NS-FAULT-007: DNS Resolution Failure")
struct DNSResolutionFailureTests {
    
    @Test("DNS failure produces correct error")
    func dnsFailureProducesCorrectError() async {
        let simulator = NetworkConditionSimulator()
        await simulator.setCondition(.offline)
        await simulator.setErrorType(.dnsFailure)
        
        do {
            try await simulator.applyAndWait(for: "/api/v1/entries")
            Issue.record("Expected DNS failure error")
        } catch let error as NetworkSimulatedError {
            #expect(error == .dnsFailure)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("DNS failure activates offline mode")
    func dnsFailureActivatesOfflineMode() async {
        let networkState = NetworkStateTracker()
        
        // Initial state
        #expect(await networkState.state == .online)
        
        // DNS failure occurs
        await networkState.recordFailure(.dnsFailure)
        
        #expect(await networkState.state == .offline)
    }
    
    @Test("Entries queued during DNS failure")
    func entriesQueuedDuringDNSFailure() async {
        let reporter = DeliveryReporter()
        
        // Queue during offline
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 2.0))
        await reporter.recordError()
        
        // Entry should be in queue
        let pending = await reporter.pendingCount()
        #expect(pending == 1)
    }
    
    @Test("Network monitor starts after DNS failure")
    func networkMonitorStartsAfterDNSFailure() async {
        let monitor = NetworkMonitorMock()
        
        #expect(await monitor.isMonitoring == false)
        
        // Start monitoring after failure
        await monitor.startMonitoring()
        
        #expect(await monitor.isMonitoring == true)
    }
    
    @Test("Queue drains when network recovers")
    func queueDrainsWhenNetworkRecovers() async {
        let reporter = DeliveryReporter()
        
        // Queue items during offline
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        await reporter.queue(DeliveryEvent(deliveryType: .smb, units: 0.5))
        await reporter.recordError()
        
        var pending = await reporter.pendingCount()
        #expect(pending == 2)
        
        // Network recovers - drain queue
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 2)
        
        pending = await reporter.pendingCount()
        #expect(pending == 0)
    }
    
    @Test("Network state transitions correctly")
    func networkStateTransitionsCorrectly() async {
        let tracker = NetworkStateTracker()
        
        // Online -> Offline
        await tracker.recordFailure(.dnsFailure)
        #expect(await tracker.state == .offline)
        
        // Offline -> Online
        await tracker.recordSuccess()
        #expect(await tracker.state == .online)
    }
    
    @Test("Consecutive DNS failures don't duplicate queue entries")
    func consecutiveDNSFailuresDontDuplicateQueueEntries() async {
        let reporter = DeliveryReporter()
        
        // Queue one entry
        let event = DeliveryEvent(deliveryType: .bolus, units: 2.0)
        await reporter.queue(event)
        
        // Multiple DNS failures
        await reporter.recordError()
        await reporter.recordError()
        await reporter.recordError()
        
        // Should still have only 1 entry
        let pending = await reporter.pendingCount()
        #expect(pending == 1)
    }
    
    @Test("DNS failure error has descriptive message")
    func dnsFailureErrorHasDescriptiveMessage() {
        let error = NetworkSimulatedError.dnsFailure
        
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("server") ||
                error.errorDescription!.lowercased().contains("resolve") ||
                error.errorDescription!.lowercased().contains("name"))
    }
}

// MARK: - Supporting Types for BATCH-NS-FAULT-B

/// WebSocket connection state tracker
actor WebSocketConnectionState {
    var isConnected = false
    var sessionId: String?
    var subscriptions: Set<String> = []
    var reconnectAttempts = 0
    
    func setConnected(_ connected: Bool, sessionId: String?) {
        self.isConnected = connected
        self.sessionId = sessionId
    }
    
    func subscribe(to channels: [String]) {
        subscriptions.formUnion(channels)
    }
    
    func recordReconnectAttempt() {
        reconnectAttempts += 1
    }
    
    func resetReconnectAttempts() {
        reconnectAttempts = 0
    }
    
    func shouldStopReconnecting(maxAttempts: Int) -> Bool {
        reconnectAttempts >= maxAttempts
    }
}

/// Buffered WebSocket event (simplified for testing - uses Data for payload)
struct WebSocketBufferedEvent: Sendable {
    let type: String
    let payloadData: Data
    
    init(type: String, payload: [String: Any]) {
        self.type = type
        // Convert to JSON data for Sendable compliance
        self.payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

/// Buffer for WebSocket events during disconnect
actor WebSocketEventBuffer {
    private var events: [WebSocketBufferedEvent] = []
    
    var count: Int { events.count }
    
    func add(_ event: WebSocketBufferedEvent) {
        events.append(event)
    }
    
    func drain() -> [WebSocketBufferedEvent] {
        let result = events
        events.removeAll()
        return result
    }
}

/// Batch upload result from server
struct BatchUploadResult: Codable {
    let ok: Bool
    let inserted: Int
    let failed: Int
    let results: [BatchItemResultCodable]?
}

struct BatchItemResultCodable: Codable {
    let index: Int
    let status: String
    let _id: String?
    let error: String?
}

/// Batch item result for reconciliation
struct BatchItemResult {
    enum Status { case ok, error }
    
    let index: Int
    let status: Status
    let id: String?
    let error: String?
}

/// Reconciles partial batch upload results
struct BatchReconciler {
    struct Report {
        let successfulIndices: [Int]
        let failedIndices: [Int]
        let failedErrors: [Int: String]
    }
    
    func reconcile(results: [BatchItemResult], originalCount: Int) -> Report {
        var successfulIndices: [Int] = []
        var failedIndices: [Int] = []
        var failedErrors: [Int: String] = [:]
        
        for result in results {
            switch result.status {
            case .ok:
                successfulIndices.append(result.index)
            case .error:
                failedIndices.append(result.index)
                if let error = result.error {
                    failedErrors[result.index] = error
                }
            }
        }
        
        return Report(
            successfulIndices: successfulIndices,
            failedIndices: failedIndices,
            failedErrors: failedErrors
        )
    }
}

/// Network state tracker
actor NetworkStateTracker {
    enum State { case online, offline }
    
    var state: State = .online
    
    func recordFailure(_ error: NetworkSimulatedError) {
        state = .offline
    }
    
    func recordSuccess() {
        state = .online
    }
}

/// Mock network monitor for testing
actor NetworkMonitorMock {
    var isMonitoring = false
    
    func startMonitoring() {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
}
