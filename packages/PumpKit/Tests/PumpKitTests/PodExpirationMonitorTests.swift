// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PodExpirationMonitorTests.swift
// PumpKitTests
//
// Tests for pod expiration monitoring and warning system.
// LIFE-PUMP-001: Omnipod 8-hour grace period
// LIFE-PUMP-002: Pod expiration notifications (8h/4h/1h/expired)

import Testing
import Foundation
@testable import PumpKit

// MARK: - PodLifetime Tests

@Suite("PodLifetime Tests")
struct PodLifetimeTests {
    
    @Test("Eros lifetime is 80 hours active + 8 grace")
    func testErosLifetime() {
        let lifetime = PodLifetime.eros
        #expect(lifetime.activeHours == 80)
        #expect(lifetime.graceHours == 8)
        #expect(lifetime.totalHours == 88)
    }
    
    @Test("DASH lifetime is 80 hours active + 8 grace")
    func testDashLifetime() {
        let lifetime = PodLifetime.dash
        #expect(lifetime.activeHours == 80)
        #expect(lifetime.graceHours == 8)
        #expect(lifetime.totalHours == 88)
    }
    
    @Test("Custom lifetime")
    func testCustomLifetime() {
        let lifetime = PodLifetime.custom(activeHours: 72, graceHours: 6)
        #expect(lifetime.activeHours == 72)
        #expect(lifetime.graceHours == 6)
        #expect(lifetime.totalHours == 78)
    }
    
    @Test("Lifetime seconds conversion")
    func testLifetimeSeconds() {
        let lifetime = PodLifetime.dash
        #expect(lifetime.activeSeconds == 80 * 3600)
        #expect(lifetime.totalSeconds == 88 * 3600)
    }
    
    @Test("forVariant returns correct lifetime")
    func testForVariant() {
        let erosLifetime = PodLifetime.forVariant(.eros)
        #expect(erosLifetime.activeHours == 80)
        
        let dashLifetime = PodLifetime.forVariant(.dash)
        #expect(dashLifetime.activeHours == 80)
    }
}

// MARK: - PodSession Tests

@Suite("PodSession Tests")
struct PodSessionTests {
    
    @Test("Session calculates expiration date correctly")
    func testExpirationDate() {
        let activation = Date(timeIntervalSince1970: 1000000)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        let expected = activation.addingTimeInterval(80 * 3600)
        #expect(session.expirationDate == expected)
    }
    
    @Test("Session calculates hard stop date correctly")
    func testHardStopDate() {
        let activation = Date(timeIntervalSince1970: 1000000)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        let expected = activation.addingTimeInterval(88 * 3600)
        #expect(session.hardStopDate == expected)
    }
    
    @Test("Hours remaining calculation")
    func testHoursRemaining() {
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        // At activation, should have ~80 hours
        let remaining = session.hoursRemaining(at: activation)
        #expect(remaining > 79.9 && remaining <= 80.0)
        
        // 40 hours later
        let midpoint = activation.addingTimeInterval(40 * 3600)
        let midRemaining = session.hoursRemaining(at: midpoint)
        #expect(midRemaining > 39.9 && midRemaining <= 40.0)
    }
    
    @Test("isExpired detection")
    func testIsExpired() {
        let activation = Date(timeIntervalSince1970: 0)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        // Before expiration
        let before = activation.addingTimeInterval(79 * 3600)
        #expect(!session.isExpired(at: before))
        
        // After expiration
        let after = activation.addingTimeInterval(81 * 3600)
        #expect(session.isExpired(at: after))
    }
    
    @Test("isPastGrace detection")
    func testIsPastGrace() {
        let activation = Date(timeIntervalSince1970: 0)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        // In grace period (82 hours)
        let inGrace = activation.addingTimeInterval(82 * 3600)
        #expect(session.isExpired(at: inGrace))
        #expect(!session.isPastGrace(at: inGrace))
        #expect(session.isInGracePeriod(at: inGrace))
        
        // Past grace period (89 hours)
        let pastGrace = activation.addingTimeInterval(89 * 3600)
        #expect(session.isPastGrace(at: pastGrace))
        #expect(!session.isInGracePeriod(at: pastGrace))
    }
    
    @Test("Progress calculation")
    func testProgress() {
        let activation = Date(timeIntervalSince1970: 0)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        // At activation
        #expect(session.progress(at: activation) == 0.0)
        
        // At 40 hours (50%)
        let midpoint = activation.addingTimeInterval(40 * 3600)
        #expect(session.progress(at: midpoint) == 0.5)
        
        // At 80 hours (100%)
        let expiration = activation.addingTimeInterval(80 * 3600)
        #expect(session.progress(at: expiration) == 1.0)
    }
}

// MARK: - PodWarning Tests

@Suite("PodWarning Tests")
struct PodWarningTests {
    
    @Test("Warning messages are appropriate")
    func testWarningMessages() {
        #expect(PodWarning.hours8.message.contains("8 hours"))
        #expect(PodWarning.hours4.message.contains("4 hours"))
        #expect(PodWarning.hours1.message.contains("1 hour"))
        #expect(PodWarning.expired.message.contains("expired"))
        #expect(PodWarning.hardStop.message.contains("stopped"))
    }
    
    @Test("forHoursRemaining returns correct warnings")
    func testForHoursRemaining() {
        // 10 hours remaining - no warning
        #expect(PodWarning.forHoursRemaining(10, graceHoursRemaining: 18) == nil)
        
        // 8 hours remaining
        #expect(PodWarning.forHoursRemaining(8, graceHoursRemaining: 16) == .hours8)
        
        // 4 hours remaining
        #expect(PodWarning.forHoursRemaining(4, graceHoursRemaining: 12) == .hours4)
        
        // 1 hour remaining
        #expect(PodWarning.forHoursRemaining(1, graceHoursRemaining: 9) == .hours1)
        
        // Expired but in grace (6 hours of grace left)
        #expect(PodWarning.forHoursRemaining(-2, graceHoursRemaining: 6) == .expired)
        
        // Late in grace period (3 hours left)
        #expect(PodWarning.forHoursRemaining(-5, graceHoursRemaining: 3) == .gracePeriod)
        
        // Past grace
        #expect(PodWarning.forHoursRemaining(-10, graceHoursRemaining: -2) == .hardStop)
    }
    
    @Test("Critical warnings are correctly identified")
    func testCriticalWarnings() {
        #expect(!PodWarning.hours8.isCritical)
        #expect(!PodWarning.hours4.isCritical)
        #expect(!PodWarning.hours1.isCritical)
        #expect(!PodWarning.expired.isCritical)
        #expect(PodWarning.hardStop.isCritical)
    }
    
    @Test("Grace warnings are correctly identified")
    func testGraceWarnings() {
        #expect(!PodWarning.hours8.isGraceWarning)
        #expect(!PodWarning.hours4.isGraceWarning)
        #expect(!PodWarning.hours1.isGraceWarning)
        #expect(PodWarning.expired.isGraceWarning)
        #expect(PodWarning.gracePeriod.isGraceWarning)
        #expect(PodWarning.hardStop.isGraceWarning)
    }
}

// MARK: - PodWarningState Tests

@Suite("PodWarningState Tests")
struct PodWarningStateTests {
    
    @Test("Initial state has no sent warnings")
    func testInitialState() {
        let state = PodWarningState(podId: "pod1")
        #expect(!state.wasSent(.hours8))
        #expect(!state.wasSent(.hours4))
        #expect(!state.wasSent(.hours1))
        #expect(!state.wasSent(.expired))
    }
    
    @Test("Marking warning as sent works")
    func testMarkSent() {
        var state = PodWarningState(podId: "pod1")
        state.markSent(.hours8)
        
        #expect(state.wasSent(.hours8))
        #expect(!state.wasSent(.hours4))
        #expect(state.lastWarningDate != nil)
    }
    
    @Test("nextPendingWarning returns correct warning")
    func testNextPendingWarning() {
        var state = PodWarningState(podId: "pod1")
        
        // 7 hours remaining - should return hours8
        var pending = state.nextPendingWarning(hoursRemaining: 7, graceHoursRemaining: 15)
        #expect(pending == .hours8)
        
        // Mark hours8 as sent
        state.markSent(.hours8)
        
        // Still 7 hours - should return nil (already sent)
        pending = state.nextPendingWarning(hoursRemaining: 7, graceHoursRemaining: 15)
        #expect(pending == nil)
        
        // 3 hours remaining - should return hours4
        pending = state.nextPendingWarning(hoursRemaining: 3, graceHoursRemaining: 11)
        #expect(pending == .hours4)
    }
}

// MARK: - PodExpirationMonitor Tests

@Suite("PodExpirationMonitor Tests")
struct PodExpirationMonitorTests {
    
    @Test("Start session creates warning state")
    func testStartSession() async {
        let monitor = PodExpirationMonitor()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        await monitor.startSession(session)
        
        let current = await monitor.currentSession()
        #expect(current != nil)
        #expect(current?.podId == "pod1")
    }
    
    @Test("End session clears state")
    func testEndSession() async {
        let monitor = PodExpirationMonitor()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        await monitor.startSession(session)
        await monitor.endSession()
        
        let current = await monitor.currentSession()
        #expect(current == nil)
    }
    
    @Test("Check expiration returns noSession when no session")
    func testNoSession() async {
        let monitor = PodExpirationMonitor()
        let result = await monitor.checkExpiration(at: Date())
        
        if case .noSession = result {
            // Expected
        } else {
            Issue.record("Expected noSession result")
        }
    }
    
    @Test("Check expiration returns healthy when pod is fresh")
    func testHealthyPod() async {
        let monitor = PodExpirationMonitor()
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        // Check 10 hours into pod life
        let checkTime = activation.addingTimeInterval(10 * 3600)
        let result = await monitor.checkExpiration(at: checkTime)
        
        if case .healthy(let remaining) = result {
            #expect(remaining > 69 && remaining < 71) // ~70 hours remaining
        } else {
            Issue.record("Expected healthy result, got \(result)")
        }
    }
    
    @Test("Check expiration returns warning at 8 hour threshold")
    func testWarningAt8Hours() async {
        let monitor = PodExpirationMonitor()
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        // Check at 73 hours (7 hours remaining)
        let checkTime = activation.addingTimeInterval(73 * 3600)
        let result = await monitor.checkExpiration(at: checkTime)
        
        if case .warning(let notification) = result {
            #expect(notification.warning == .hours8)
            #expect(notification.hoursRemaining > 6 && notification.hoursRemaining < 8)
        } else {
            Issue.record("Expected warning result, got \(result)")
        }
    }
    
    @Test("Mark warning sent prevents duplicate warnings")
    func testMarkWarningSent() async {
        let monitor = PodExpirationMonitor()
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        let checkTime = activation.addingTimeInterval(73 * 3600)
        
        // First check should return warning
        let result1 = await monitor.checkExpiration(at: checkTime)
        if case .warning(let notification) = result1 {
            #expect(notification.warning == .hours8)
            await monitor.markWarningSent(.hours8)
        }
        
        // Second check should return alreadySent
        let result2 = await monitor.checkExpiration(at: checkTime)
        if case .alreadySent(let warning) = result2 {
            #expect(warning == .hours8)
        } else {
            Issue.record("Expected alreadySent result, got \(result2)")
        }
    }
    
    @Test("Check expiration returns inGracePeriod when expired")
    func testInGracePeriod() async {
        let monitor = PodExpirationMonitor()
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        // Mark all pre-expiration warnings as sent
        await monitor.markWarningSent(.hours8)
        await monitor.markWarningSent(.hours4)
        await monitor.markWarningSent(.hours1)
        await monitor.markWarningSent(.expired)
        
        // Check at 82 hours (2 hours past expiration, 6 hours of grace left)
        let checkTime = activation.addingTimeInterval(82 * 3600)
        let result = await monitor.checkExpiration(at: checkTime)
        
        if case .inGracePeriod(let graceRemaining) = result {
            #expect(graceRemaining > 5 && graceRemaining < 7) // ~6 hours
        } else {
            Issue.record("Expected inGracePeriod result, got \(result)")
        }
    }
    
    @Test("Check expiration returns stopped past grace period")
    func testStoppedPastGrace() async {
        let monitor = PodExpirationMonitor()
        let activation = Date()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        // Check at 90 hours (past grace)
        let checkTime = activation.addingTimeInterval(90 * 3600)
        let result = await monitor.checkExpiration(at: checkTime)
        
        if case .stopped = result {
            // Expected
        } else {
            Issue.record("Expected stopped result, got \(result)")
        }
    }
}

// MARK: - Persistence Tests

@Suite("PodPersistence Tests")
struct PodPersistenceTests {
    
    @Test("InMemoryPodPersistence saves and loads session")
    func testInMemorySaveLoad() async {
        let persistence = InMemoryPodPersistence()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded != nil)
        #expect(loaded?.podId == "pod1")
    }
    
    @Test("InMemoryPodPersistence clears session")
    func testInMemoryClear() async {
        let persistence = InMemoryPodPersistence()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        await persistence.saveSession(session)
        await persistence.clearSession()
        let loaded = await persistence.loadSession()
        
        #expect(loaded == nil)
    }
    
    @Test("InMemoryPodPersistence handles warning state")
    func testInMemoryWarningState() async {
        let persistence = InMemoryPodPersistence()
        var state = PodWarningState(podId: "pod1")
        state.markSent(.hours8)
        
        await persistence.saveWarningState(state)
        let loaded = await persistence.loadWarningState(for: "pod1")
        
        #expect(loaded != nil)
        #expect(loaded?.wasSent(.hours8) == true)
    }
    
    @Test("Monitor with persistence restores session")
    func testMonitorWithPersistence() async {
        let persistence = InMemoryPodPersistence()
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        // Save with first monitor
        let monitor1 = PodExpirationMonitor(persistence: persistence)
        await monitor1.startSession(session)
        
        // Restore with second monitor
        let monitor2 = PodExpirationMonitor(persistence: persistence)
        await monitor2.restoreSession()
        
        let restored = await monitor2.currentSession()
        #expect(restored != nil)
        #expect(restored?.podId == "pod1")
    }
}

// MARK: - Notification Tests

@Suite("PodExpirationNotification Tests")
struct PodExpirationNotificationTests {
    
    @Test("Time remaining string for active pod")
    func testTimeRemainingActive() {
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        let notification = PodExpirationNotification(
            session: session,
            warning: .hours4,
            hoursRemaining: 4.5,
            graceHoursRemaining: 12.5
        )
        
        #expect(notification.timeRemainingString == "4h 30m")
    }
    
    @Test("Time remaining string for grace period")
    func testTimeRemainingGrace() {
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        let notification = PodExpirationNotification(
            session: session,
            warning: .expired,
            hoursRemaining: -2,
            graceHoursRemaining: 6.0
        )
        
        #expect(notification.timeRemainingString == "Grace: 6h 0m")
    }
    
    @Test("Time remaining string for stopped pod")
    func testTimeRemainingStopped() {
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: Date()
        )
        
        let notification = PodExpirationNotification(
            session: session,
            warning: .hardStop,
            hoursRemaining: -10,
            graceHoursRemaining: -2
        )
        
        #expect(notification.timeRemainingString == "Stopped")
    }
}

// MARK: - Scheduler Tests

@Suite("PodExpirationScheduler Tests")
struct PodExpirationSchedulerTests {
    
    @Test("Scheduler starts and stops")
    func testStartStop() async {
        let monitor = PodExpirationMonitor()
        let scheduler = PodExpirationScheduler(
            monitor: monitor,
            checkInterval: 1.0
        ) { _ in }
        
        await scheduler.start()
        let running1 = await scheduler.running
        #expect(running1 == true)
        
        await scheduler.stop()
        let running2 = await scheduler.running
        #expect(running2 == false)
    }
    
    @Test("Scheduler triggers handler on warning")
    func testSchedulerTriggersHandler() async {
        let monitor = PodExpirationMonitor()
        let activation = Date().addingTimeInterval(-73 * 3600) // 73 hours ago = 7h remaining
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        await monitor.startSession(session)
        
        // Use actor to safely capture notification
        actor NotificationCapture {
            var notification: PodExpirationNotification?
            func set(_ n: PodExpirationNotification) { notification = n }
            func get() -> PodExpirationNotification? { notification }
        }
        let capture = NotificationCapture()
        
        let scheduler = PodExpirationScheduler(
            monitor: monitor,
            checkInterval: 1.0
        ) { notification in
            await capture.set(notification)
        }
        
        // Perform single check instead of starting scheduler loop
        await scheduler.performCheck()
        
        let received = await capture.get()
        #expect(received != nil)
        #expect(received?.warning == .hours8)
    }
}

// MARK: - PodProgress Tests

@Suite("PodProgress Tests")
struct PodProgressTests {
    
    @Test("Progress remainingText for active pod")
    func testRemainingTextActive() {
        let activation = Date().addingTimeInterval(-40 * 3600) // 40 hours ago
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        let progress = PodProgress(session: session)
        
        // ~40 hours remaining = 1d 16h
        #expect(progress.remainingText.contains("d") || progress.remainingText.contains("h"))
        #expect(progress.statusText == "Pod active")
    }
    
    @Test("Progress remainingText for grace period")
    func testRemainingTextGrace() {
        let activation = Date().addingTimeInterval(-82 * 3600) // 82 hours ago (2h into grace)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        let progress = PodProgress(session: session)
        
        #expect(progress.isInGracePeriod == true)
        #expect(progress.remainingText.contains("Grace"))
        #expect(progress.statusText.contains("expired"))
    }
    
    @Test("Progress remainingText for stopped pod")
    func testRemainingTextStopped() {
        let activation = Date().addingTimeInterval(-90 * 3600) // 90 hours ago (past grace)
        let session = PodSession(
            podId: "pod1",
            variant: .dash,
            activationDate: activation
        )
        
        let progress = PodProgress(session: session)
        
        #expect(progress.remainingText == "Stopped")
        #expect(progress.statusText == "Pod delivery stopped")
    }
}
