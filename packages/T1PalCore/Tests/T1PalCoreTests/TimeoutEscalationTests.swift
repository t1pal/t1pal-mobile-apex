/// Tests for TimeoutEscalation handling
/// BEHAV-007 verification

import XCTest
@testable import T1PalCore

final class TimeoutEscalationTests: XCTestCase {
    
    // MARK: - RetryPolicy Tests
    
    func testStandardPolicy() {
        let policy = RetryPolicy.standard
        
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.delayBetweenRetries, .milliseconds(500))
        XCTAssertEqual(policy.totalTimeout, .seconds(30))
        XCTAssertFalse(policy.useExponentialBackoff)
    }
    
    func testQuickPolicy() {
        let policy = RetryPolicy.quick
        
        XCTAssertEqual(policy.maxRetries, 2)
        XCTAssertEqual(policy.delayBetweenRetries, .milliseconds(200))
        XCTAssertEqual(policy.totalTimeout, .seconds(10))
    }
    
    func testPatientPolicy() {
        let policy = RetryPolicy.patient
        
        XCTAssertEqual(policy.maxRetries, 5)
        XCTAssertTrue(policy.useExponentialBackoff)
        XCTAssertEqual(policy.backoffMultiplier, 2.0)
    }
    
    func testNoRetryPolicy() {
        let policy = RetryPolicy.noRetry
        
        XCTAssertEqual(policy.maxRetries, 0)
    }
    
    func testDelayCalculationLinear() {
        let policy = RetryPolicy.standard
        
        // Linear policy returns same delay for all attempts
        XCTAssertEqual(policy.delayFor(attempt: 1), policy.delayBetweenRetries)
        XCTAssertEqual(policy.delayFor(attempt: 2), policy.delayBetweenRetries)
        XCTAssertEqual(policy.delayFor(attempt: 3), policy.delayBetweenRetries)
    }
    
    func testCustomPolicy() {
        let policy = RetryPolicy(
            maxRetries: 5,
            delayBetweenRetries: .seconds(1),
            totalTimeout: .seconds(60),
            useExponentialBackoff: true,
            backoffMultiplier: 1.5,
            maxBackoffDelay: .seconds(5)
        )
        
        XCTAssertEqual(policy.maxRetries, 5)
        XCTAssertEqual(policy.delayBetweenRetries, .seconds(1))
        XCTAssertTrue(policy.useExponentialBackoff)
    }
    
    // MARK: - CommunicationRetryTracker Tests
    
    func testTrackerInitialState() {
        let tracker = CommunicationRetryTracker()
        
        XCTAssertEqual(tracker.currentAttempt, 0)
        XCTAssertNil(tracker.lastError)
        XCTAssertNil(tracker.firstFailureTime)
        XCTAssertEqual(tracker.totalFailures, 0)
        XCTAssertEqual(tracker.escalationLevel, .none)
    }
    
    func testRecordSuccess() {
        var tracker = CommunicationRetryTracker()
        
        // Record some failures first
        _ = tracker.recordFailure(error: TestError.test)
        _ = tracker.recordFailure(error: TestError.test)
        
        XCTAssertEqual(tracker.currentAttempt, 2)
        XCTAssertEqual(tracker.totalFailures, 2)
        
        // Record success
        tracker.recordSuccess()
        
        XCTAssertEqual(tracker.currentAttempt, 0)
        XCTAssertNil(tracker.lastError)
        XCTAssertEqual(tracker.escalationLevel, .none)
        // Total failures preserved for metrics
        XCTAssertEqual(tracker.totalFailures, 2)
    }
    
    func testRecordFailureReturnsRetry() {
        var tracker = CommunicationRetryTracker(policy: .standard)
        
        let action = tracker.recordFailure(error: TestError.test)
        
        if case .retry = action {
            // Expected
        } else {
            XCTFail("Expected retry action")
        }
        
        XCTAssertEqual(tracker.currentAttempt, 1)
        XCTAssertNotNil(tracker.lastError)
        XCTAssertNotNil(tracker.firstFailureTime)
    }
    
    func testRetryExhaustedReturnsAbort() {
        var tracker = CommunicationRetryTracker(policy: .standard) // 3 retries
        
        // Exhaust all retries
        _ = tracker.recordFailure(error: TestError.test)
        _ = tracker.recordFailure(error: TestError.test)
        _ = tracker.recordFailure(error: TestError.test)
        
        // Fourth attempt should abort
        let action = tracker.recordFailure(error: TestError.test)
        
        XCTAssertEqual(action, .abort)
        XCTAssertEqual(tracker.escalationLevel, .alert)
    }
    
    func testEscalationProgression() {
        var tracker = CommunicationRetryTracker(policy: .standard) // 3 retries
        
        // First attempt - no escalation
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertEqual(tracker.escalationLevel, .none)
        
        // Second attempt (50% of 3) - warning
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertEqual(tracker.escalationLevel, .warning)
        
        // Third attempt - still warning
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertEqual(tracker.escalationLevel, .warning)
        
        // Fourth attempt (exhausted) - alert
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertEqual(tracker.escalationLevel, .alert)
    }
    
    func testShouldNotifyUser() {
        var tracker = CommunicationRetryTracker(policy: .standard)
        
        // Initially no notification
        XCTAssertFalse(tracker.shouldNotifyUser)
        
        // First failure - still no
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertFalse(tracker.shouldNotifyUser)
        
        // Second failure (warning) - yes
        _ = tracker.recordFailure(error: TestError.test)
        XCTAssertTrue(tracker.shouldNotifyUser)
    }
    
    func testStatus() {
        var tracker = CommunicationRetryTracker(policy: .standard)
        
        let initialStatus = tracker.status
        XCTAssertEqual(initialStatus.progressDescription, "Ready")
        XCTAssertEqual(initialStatus.retriesRemaining, 3)
        
        _ = tracker.recordFailure(error: TestError.test)
        let status1 = tracker.status
        XCTAssertEqual(status1.progressDescription, "Attempt 1/3")
        XCTAssertEqual(status1.retriesRemaining, 2)
        
        _ = tracker.recordFailure(error: TestError.test)
        _ = tracker.recordFailure(error: TestError.test)
        _ = tracker.recordFailure(error: TestError.test)
        let exhaustedStatus = tracker.status
        XCTAssertEqual(exhaustedStatus.progressDescription, "Retries exhausted")
        XCTAssertEqual(exhaustedStatus.retriesRemaining, 0)
    }
    
    // MARK: - Escalation Level Tests
    
    func testEscalationLevelComparable() {
        XCTAssertTrue(CommunicationRetryTracker.EscalationLevel.none < .warning)
        XCTAssertTrue(CommunicationRetryTracker.EscalationLevel.warning < .alert)
        XCTAssertTrue(CommunicationRetryTracker.EscalationLevel.none < .alert)
    }
    
    func testEscalationLevelElementState() {
        XCTAssertEqual(CommunicationRetryTracker.EscalationLevel.none.elementState, .normalPump)
        XCTAssertEqual(CommunicationRetryTracker.EscalationLevel.warning.elementState, .warning)
        XCTAssertEqual(CommunicationRetryTracker.EscalationLevel.alert.elementState, .critical)
    }
    
    // MARK: - TimeoutEscalationManager Tests
    
    func testManagerTrackerCreation() {
        var manager = TimeoutEscalationManager()
        
        let tracker = manager.tracker(for: .pumpStatus)
        XCTAssertEqual(tracker.currentAttempt, 0)
    }
    
    func testManagerRecordSuccess() {
        var manager = TimeoutEscalationManager()
        
        // Record some failures
        _ = manager.recordFailure(for: .pumpStatus, error: TestError.test)
        _ = manager.recordFailure(for: .pumpStatus, error: TestError.test)
        
        // Record success
        manager.recordSuccess(for: .pumpStatus)
        
        let tracker = manager.tracker(for: .pumpStatus)
        XCTAssertEqual(tracker.currentAttempt, 0)
        XCTAssertEqual(tracker.escalationLevel, .none)
    }
    
    func testManagerRecordFailure() {
        var manager = TimeoutEscalationManager()
        
        let action = manager.recordFailure(for: .cgmReading, error: TestError.test)
        
        if case .retry = action {
            // Expected
        } else {
            XCTFail("Expected retry action")
        }
    }
    
    func testManagerOperationSpecificPolicies() {
        var manager = TimeoutEscalationManager()
        
        // Bolus uses quick policy (2 retries)
        let bolusTracker = manager.tracker(for: .bolus)
        XCTAssertEqual(bolusTracker.policy.maxRetries, 2)
        
        // Pump history uses patient policy (5 retries)
        let historyTracker = manager.tracker(for: .pumpHistory)
        XCTAssertEqual(historyTracker.policy.maxRetries, 5)
    }
    
    func testManagerAllStatus() {
        var manager = TimeoutEscalationManager()
        
        _ = manager.recordFailure(for: .pumpStatus, error: TestError.test)
        _ = manager.recordFailure(for: .cgmReading, error: TestError.test)
        
        let allStatus = manager.allStatus
        XCTAssertEqual(allStatus.count, 2)
        XCTAssertNotNil(allStatus[.pumpStatus])
        XCTAssertNotNil(allStatus[.cgmReading])
    }
    
    func testManagerResetAll() {
        var manager = TimeoutEscalationManager()
        
        _ = manager.recordFailure(for: .pumpStatus, error: TestError.test)
        _ = manager.recordFailure(for: .cgmReading, error: TestError.test)
        
        manager.resetAll()
        
        let allStatus = manager.allStatus
        for (_, status) in allStatus {
            XCTAssertEqual(status.currentAttempt, 0)
        }
    }
    
    // MARK: - TimeoutAlert Tests
    
    func testAlertFromEscalationEvent() {
        let event = TimeoutEscalationManager.EscalationEvent(
            operation: .pumpStatus,
            level: .alert,
            error: "Connection timeout",
            attempt: 4,
            maxRetries: 3
        )
        
        let alert = TimeoutAlert(event: event)
        
        XCTAssertEqual(alert.title, "Connection Failed")
        XCTAssertTrue(alert.message.contains("Connection timeout"))
        XCTAssertFalse(alert.recoverySuggestions.isEmpty)
        XCTAssertEqual(alert.level, .alert)
    }
    
    func testAlertWarningLevel() {
        let event = TimeoutEscalationManager.EscalationEvent(
            operation: .cgmReading,
            level: .warning,
            error: "No response",
            attempt: 2,
            maxRetries: 3
        )
        
        let alert = TimeoutAlert(event: event)
        
        XCTAssertEqual(alert.title, "Connection Delayed")
        XCTAssertEqual(alert.level, .warning)
    }
    
    func testAlertNoneLevel() {
        let event = TimeoutEscalationManager.EscalationEvent(
            operation: .settings,
            level: .none,
            error: "",
            attempt: 1,
            maxRetries: 3
        )
        
        let alert = TimeoutAlert(event: event)
        
        XCTAssertEqual(alert.title, "Connecting")
        XCTAssertTrue(alert.recoverySuggestions.isEmpty)
    }
    
    func testCustomAlert() {
        let alert = TimeoutAlert(
            title: "Custom Title",
            message: "Custom message",
            recoverySuggestions: ["Try this"],
            level: .warning
        )
        
        XCTAssertEqual(alert.title, "Custom Title")
        XCTAssertEqual(alert.message, "Custom message")
        XCTAssertEqual(alert.recoverySuggestions.count, 1)
        XCTAssertEqual(alert.level, .warning)
    }
    
    // MARK: - Escalation Event Tests
    
    func testEscalationEventMessage() {
        let warningEvent = TimeoutEscalationManager.EscalationEvent(
            operation: .pumpStatus,
            level: .warning,
            error: "Timeout",
            attempt: 2,
            maxRetries: 3
        )
        
        XCTAssertTrue(warningEvent.message.contains("2 of 3"))
        
        let alertEvent = TimeoutEscalationManager.EscalationEvent(
            operation: .cgmReading,
            level: .alert,
            error: "Failed",
            attempt: 4,
            maxRetries: 3
        )
        
        XCTAssertTrue(alertEvent.message.contains("CGM"))
    }
    
    // MARK: - CommunicationError Tests
    
    func testCommunicationErrorDescriptions() {
        XCTAssertNotNil(CommunicationError.retriesExhausted.errorDescription)
        XCTAssertNotNil(CommunicationError.timeout.errorDescription)
        XCTAssertNotNil(CommunicationError.connectionLost.errorDescription)
    }
    
    // MARK: - Policy Codable Tests
    
    func testPolicyCodable() throws {
        let policy = RetryPolicy.patient
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RetryPolicy.self, from: data)
        
        XCTAssertEqual(decoded.maxRetries, policy.maxRetries)
        XCTAssertEqual(decoded.useExponentialBackoff, policy.useExponentialBackoff)
    }
    
    // MARK: - Retry Action Tests
    
    func testRetryActionEquatable() {
        let retry1 = CommunicationRetryTracker.RetryAction.retry(delay: .seconds(1))
        let retry2 = CommunicationRetryTracker.RetryAction.retry(delay: .seconds(1))
        let retry3 = CommunicationRetryTracker.RetryAction.retry(delay: .seconds(2))
        let abort = CommunicationRetryTracker.RetryAction.abort
        
        XCTAssertEqual(retry1, retry2)
        XCTAssertNotEqual(retry1, retry3)
        XCTAssertNotEqual(retry1, abort)
        XCTAssertEqual(abort, .abort)
    }
}

// MARK: - Test Helpers

enum TestError: Error, LocalizedError {
    case test
    
    var errorDescription: String? { "Test error" }
}
