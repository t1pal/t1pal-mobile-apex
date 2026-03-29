// SensorExpirationMonitorTests.swift
// CGMKitTests
//
// Tests for sensor expiration monitoring and warnings.
// PROD-CGM-004: Sensor expiration warning

import Testing
import Foundation
@testable import CGMKit
import T1PalCore

// MARK: - Test Helpers

/// Helper actor for safely capturing notifications in tests.
private actor NotificationCollector {
    var notification: SensorExpirationNotification?
    
    func set(_ notification: SensorExpirationNotification) {
        self.notification = notification
    }
}

// MARK: - Sensor Lifetime Tests

@Suite("Sensor Lifetime")
struct SensorLifetimeTests {
    
    @Test("Dexcom 10-day is 240 hours")
    func dexcom10Day() {
        let lifetime = SensorLifetime.dexcom10Day
        #expect(lifetime.hours == 240)
        #expect(lifetime.seconds == 240 * 3600)
    }
    
    @Test("Libre 14-day is 336 hours")
    func libre14Day() {
        let lifetime = SensorLifetime.libre14Day
        #expect(lifetime.hours == 336)
    }
    
    @Test("Custom lifetime")
    func customLifetime() {
        let lifetime = SensorLifetime.custom(hours: 180)
        #expect(lifetime.hours == 180)
    }
    
    @Test("Lifetime for CGM type - G6")
    func lifetimeForG6() {
        let lifetime = SensorLifetime.forType(.dexcomG6)
        #expect(lifetime.hours == 240)
    }
    
    @Test("Lifetime for CGM type - G7")
    func lifetimeForG7() {
        let lifetime = SensorLifetime.forType(.dexcomG7)
        #expect(lifetime.hours == 240)
    }
    
    @Test("Lifetime for CGM type - Libre2")
    func lifetimeForLibre2() {
        let lifetime = SensorLifetime.forType(.libre2)
        #expect(lifetime.hours == 336)
    }
    
    @Test("Lifetime for unknown type defaults to 7 days")
    func lifetimeForUnknown() {
        let lifetime = SensorLifetime.forType(.simulation)
        #expect(lifetime.hours == 168)
    }
}

// MARK: - Sensor Session Tests

@Suite("Sensor Session")
struct SensorSessionTests {
    
    @Test("Creates session with default lifetime")
    func createWithDefaultLifetime() {
        let session = SensorSession(
            sensorId: "ABC123",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        #expect(session.sensorId == "ABC123")
        #expect(session.cgmType == .dexcomG7)
        #expect(session.lifetimeHours == 240)
    }
    
    @Test("Creates session with custom lifetime")
    func createWithCustomLifetime() {
        let session = SensorSession(
            sensorId: "XYZ789",
            cgmType: .libre2,
            startDate: Date(),
            lifetimeHours: 300
        )
        
        #expect(session.lifetimeHours == 300)
    }
    
    @Test("Calculates expiration date")
    func expirationDate() {
        let start = Date()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: start
        )
        
        let expected = start.addingTimeInterval(240 * 3600)
        #expect(abs(session.expirationDate.timeIntervalSince(expected)) < 1)
    }
    
    @Test("Calculates time remaining")
    func timeRemaining() {
        let start = Date().addingTimeInterval(-100 * 3600) // Started 100 hours ago
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: start
        )
        
        // Should have 140 hours remaining (240 - 100)
        let remaining = session.hoursRemaining()
        #expect(remaining > 139 && remaining < 141)
    }
    
    @Test("Detects expired sensor")
    func isExpired() {
        let start = Date().addingTimeInterval(-250 * 3600) // Started 250 hours ago
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: start
        )
        
        #expect(session.isExpired())
    }
    
    @Test("Calculates progress")
    func progress() {
        let start = Date().addingTimeInterval(-120 * 3600) // 50% through
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: start
        )
        
        let progress = session.progress()
        #expect(progress > 0.49 && progress < 0.51)
    }
    
    @Test("Session is Codable")
    func isCodable() throws {
        let session = SensorSession(
            sensorId: "ENCODE",
            cgmType: .dexcomG6,
            startDate: Date()
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SensorSession.self, from: data)
        
        #expect(decoded.sensorId == session.sensorId)
        #expect(decoded.cgmType == session.cgmType)
    }
}

// MARK: - Expiration Warning Tests

@Suite("Expiration Warning")
struct ExpirationWarningTests {
    
    @Test("Warning for 5 hours remaining")
    func warningFor5Hours() {
        let warning = ExpirationWarning.forHoursRemaining(5)
        #expect(warning == .hours6)
    }
    
    @Test("Warning for 0.5 hours remaining")
    func warningForHalfHour() {
        let warning = ExpirationWarning.forHoursRemaining(0.5)
        #expect(warning == .hours1)
    }
    
    @Test("Warning for expired")
    func warningForExpired() {
        let warning = ExpirationWarning.forHoursRemaining(-1)
        #expect(warning == .expired)
    }
    
    @Test("No warning for 48 hours")
    func noWarningFor48Hours() {
        let warning = ExpirationWarning.forHoursRemaining(48)
        #expect(warning == nil)
    }
    
    @Test("Warning messages")
    func warningMessages() {
        #expect(ExpirationWarning.hours24.message.contains("24"))
        #expect(ExpirationWarning.hours6.message.contains("6"))
        #expect(ExpirationWarning.hours1.message.contains("1"))
        #expect(ExpirationWarning.expired.message.contains("expired"))
    }
    
    @Test("Warnings are comparable")
    func warningsAreComparable() {
        #expect(ExpirationWarning.expired < ExpirationWarning.hours1)
        #expect(ExpirationWarning.hours1 < ExpirationWarning.hours6)
        #expect(ExpirationWarning.hours6 < ExpirationWarning.hours24)
    }
}

// MARK: - Warning State Tests

@Suite("Warning State")
struct WarningStateTests {
    
    @Test("Creates empty state")
    func createsEmptyState() {
        let state = ExpirationWarningState(sensorId: "TEST")
        
        #expect(state.sensorId == "TEST")
        #expect(state.sentWarnings.isEmpty)
        #expect(state.lastWarningDate == nil)
    }
    
    @Test("Marks warning as sent")
    func marksSent() {
        var state = ExpirationWarningState(sensorId: "TEST")
        state.markSent(.hours24)
        
        #expect(state.wasSent(.hours24))
        #expect(!state.wasSent(.hours6))
        #expect(state.lastWarningDate != nil)
    }
    
    @Test("Next pending warning")
    func nextPending() {
        var state = ExpirationWarningState(sensorId: "TEST")
        state.markSent(.hours24)
        
        // At 5 hours remaining, should get hours6 (not hours24 already sent)
        let next = state.nextPendingWarning(hoursRemaining: 5)
        #expect(next == .hours6)
    }
    
    @Test("No pending when all sent")
    func noPendingWhenAllSent() {
        var state = ExpirationWarningState(sensorId: "TEST")
        state.markSent(.hours24)
        state.markSent(.hours6)
        state.markSent(.hours1)
        state.markSent(.expired)
        
        // Even at expired level, if all warnings sent, next is nil
        let next = state.nextPendingWarning(hoursRemaining: -0.5)
        #expect(next == nil)
    }
    
    @Test("State is Codable")
    func isCodable() throws {
        var state = ExpirationWarningState(sensorId: "ENCODE")
        state.markSent(.hours24)
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ExpirationWarningState.self, from: data)
        
        #expect(decoded.sensorId == state.sensorId)
        #expect(decoded.wasSent(.hours24))
    }
}

// MARK: - Expiration Notification Tests

@Suite("Expiration Notification")
struct ExpirationNotificationTests {
    
    @Test("Creates notification")
    func createsNotification() {
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        let notification = SensorExpirationNotification(
            session: session,
            warning: .hours24,
            hoursRemaining: 23.5
        )
        
        #expect(notification.title.contains("Expir"))
        #expect(!notification.body.isEmpty)
    }
    
    @Test("Converts to GlucoseNotificationContent")
    func convertsToContent() {
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG6,
            startDate: Date()
        )
        
        let notification = SensorExpirationNotification(
            session: session,
            warning: .hours6,
            hoursRemaining: 5.5
        )
        
        let content = notification.toNotificationContent()
        
        #expect(content.type == .sensorExpiring)
        #expect(content.userInfo["sensorId"] == "TEST")
        #expect(content.userInfo["warning"] == "6")
    }
}

// MARK: - Monitor Tests

@Suite("Sensor Expiration Monitor")
struct SensorExpirationMonitorTests {
    
    @Test("Starts with no session")
    func startsWithNoSession() async {
        let monitor = SensorExpirationMonitor()
        let session = await monitor.currentSession()
        #expect(session == nil)
    }
    
    @Test("Starts session")
    func startsSession() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        await monitor.startSession(session)
        let current = await monitor.currentSession()
        
        #expect(current?.sensorId == "TEST")
    }
    
    @Test("Ends session")
    func endsSession() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        await monitor.startSession(session)
        await monitor.endSession()
        let current = await monitor.currentSession()
        
        #expect(current == nil)
    }
    
    @Test("Check returns no session")
    func checkNoSession() async {
        let monitor = SensorExpirationMonitor()
        let result = await monitor.checkExpiration()
        
        #expect(result == .noSession)
    }
    
    @Test("Check returns healthy")
    func checkHealthy() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date() // Just started
        )
        
        await monitor.startSession(session)
        let result = await monitor.checkExpiration()
        
        if case .healthy(let hours) = result {
            #expect(hours > 239)
        } else {
            Issue.record("Expected healthy result")
        }
    }
    
    @Test("Check returns warning at 24h")
    func checkWarning24() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-220 * 3600) // 20h remaining
        )
        
        await monitor.startSession(session)
        let result = await monitor.checkExpiration()
        
        if case .warning(let notification) = result {
            #expect(notification.warning == .hours24)
        } else {
            Issue.record("Expected warning result")
        }
    }
    
    @Test("Check returns already sent")
    func checkAlreadySent() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-220 * 3600)
        )
        
        await monitor.startSession(session)
        await monitor.markWarningSent(.hours24)
        let result = await monitor.checkExpiration()
        
        if case .alreadySent(let warning) = result {
            #expect(warning == .hours24)
        } else {
            Issue.record("Expected already sent result")
        }
    }
    
    @Test("Check returns expired")
    func checkExpired() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-250 * 3600) // Expired
        )
        
        await monitor.startSession(session)
        let result = await monitor.checkExpiration()
        
        #expect(result == .expired)
    }
    
    @Test("Update from reading - new sensor")
    func updateFromReadingNew() async {
        let monitor = SensorExpirationMonitor()
        
        await monitor.updateFromReading(
            sensorId: "NEW123",
            cgmType: .dexcomG7,
            sensorAgeHours: 48
        )
        
        let session = await monitor.currentSession()
        #expect(session?.sensorId == "NEW123")
        #expect(session?.ageHours() ?? 0 > 47)
    }
    
    @Test("Update from reading - same sensor")
    func updateFromReadingSame() async {
        let monitor = SensorExpirationMonitor()
        let originalSession = SensorSession(
            sensorId: "SAME",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-24 * 3600)
        )
        await monitor.startSession(originalSession)
        
        // Should not create new session
        await monitor.updateFromReading(
            sensorId: "SAME",
            cgmType: .dexcomG7,
            sensorAgeHours: 25
        )
        
        let session = await monitor.currentSession()
        #expect(session?.startDate == originalSession.startDate)
    }
}

// MARK: - Persistence Tests

@Suite("Expiration Persistence")
struct ExpirationPersistenceTests {
    
    @Test("In-memory saves and loads session")
    func inMemorySession() async {
        let persistence = InMemoryExpirationPersistence()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded?.sensorId == "TEST")
    }
    
    @Test("In-memory clears session")
    func inMemoryClears() async {
        let persistence = InMemoryExpirationPersistence()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        await persistence.saveSession(session)
        await persistence.clearSession()
        let loaded = await persistence.loadSession()
        
        #expect(loaded == nil)
    }
    
    @Test("In-memory saves warning state")
    func inMemoryWarningState() async {
        let persistence = InMemoryExpirationPersistence()
        var state = ExpirationWarningState(sensorId: "TEST")
        state.markSent(.hours24)
        
        await persistence.saveWarningState(state)
        let loaded = await persistence.loadWarningState(for: "TEST")
        
        #expect(loaded?.wasSent(.hours24) == true)
    }
    
    @Test("Monitor with persistence restores")
    func monitorRestore() async {
        let persistence = InMemoryExpirationPersistence()
        let session = SensorSession(
            sensorId: "PERSIST",
            cgmType: .dexcomG6,
            startDate: Date()
        )
        await persistence.saveSession(session)
        
        let monitor = SensorExpirationMonitor(persistence: persistence)
        await monitor.restoreSession()
        
        let current = await monitor.currentSession()
        #expect(current?.sensorId == "PERSIST")
    }
}

// MARK: - Scheduler Tests

@Suite("Expiration Scheduler")
struct ExpirationSchedulerTests {
    
    @Test("Scheduler performs check")
    func performsCheck() async {
        let monitor = SensorExpirationMonitor()
        let session = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-220 * 3600)
        )
        await monitor.startSession(session)
        
        // Use actor to safely capture notification
        let collector = NotificationCollector()
        
        let scheduler = ExpirationScheduler(
            monitor: monitor,
            checkInterval: 1
        ) { notification in
            await collector.set(notification)
        }
        
        await scheduler.performCheck()
        
        let received = await collector.notification
        #expect(received?.warning == .hours24)
    }
    
    @Test("Scheduler can start and stop")
    func startStop() async {
        let monitor = SensorExpirationMonitor()
        
        let scheduler = ExpirationScheduler(
            monitor: monitor,
            checkInterval: 3600
        ) { _ in }
        
        await scheduler.start()
        await scheduler.stop()
        // No assertion needed - just verify it doesn't crash
    }
}

// MARK: - Progress Tests

@Suite("Sensor Progress")
struct SensorProgressTests {
    
    @Test("Progress for new sensor")
    func progressNew() {
        let session = SensorSession(
            sensorId: "NEW",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        let progress = SensorProgress(session: session)
        
        #expect(progress.progress < 0.01)
        #expect(progress.warningLevel == nil)
        #expect(progress.colorCategory == "healthy")
    }
    
    @Test("Progress for expiring sensor")
    func progressExpiring() {
        let session = SensorSession(
            sensorId: "OLD",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-235 * 3600)
        )
        
        let progress = SensorProgress(session: session)
        
        #expect(progress.warningLevel == .hours6)
        #expect(progress.colorCategory == "warning")
    }
    
    @Test("Progress for expired sensor")
    func progressExpired() {
        let session = SensorSession(
            sensorId: "EXPIRED",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-250 * 3600)
        )
        
        let progress = SensorProgress(session: session)
        
        #expect(progress.warningLevel == .expired)
        #expect(progress.remainingText == "Expired")
        #expect(progress.colorCategory == "expired")
    }
    
    @Test("Remaining text formats correctly")
    func remainingTextFormats() {
        // 5 days remaining
        let session5Days = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-120 * 3600)
        )
        let progress5Days = SensorProgress(session: session5Days)
        #expect(progress5Days.remainingText.contains("days"))
        
        // 12 hours remaining
        let session12Hours = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-228 * 3600)
        )
        let progress12Hours = SensorProgress(session: session12Hours)
        #expect(progress12Hours.remainingText.contains("hr"))
        
        // 30 minutes remaining
        let session30Min = SensorSession(
            sensorId: "TEST",
            cgmType: .dexcomG7,
            startDate: Date().addingTimeInterval(-239.5 * 3600)
        )
        let progress30Min = SensorProgress(session: session30Min)
        #expect(progress30Min.remainingText.contains("min"))
    }
}

// MARK: - UserDefaults Persistence Tests

@Suite("UserDefaults Persistence")
struct UserDefaultsPersistenceTests {
    
    @Test("Saves and loads session")
    func savesAndLoads() async {
        let defaults = UserDefaults(suiteName: "test.sensor.\(UUID().uuidString)")!
        let persistence = UserDefaultsExpirationPersistence(defaults: defaults)
        
        let session = SensorSession(
            sensorId: "UDTEST",
            cgmType: .libre2,
            startDate: Date()
        )
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded?.sensorId == "UDTEST")
        #expect(loaded?.cgmType == .libre2)
    }
    
    @Test("Clears session")
    func clearsSession() async {
        let defaults = UserDefaults(suiteName: "test.sensor.\(UUID().uuidString)")!
        let persistence = UserDefaultsExpirationPersistence(defaults: defaults)
        
        let session = SensorSession(
            sensorId: "CLEAR",
            cgmType: .dexcomG7,
            startDate: Date()
        )
        
        await persistence.saveSession(session)
        await persistence.clearSession()
        let loaded = await persistence.loadSession()
        
        #expect(loaded == nil)
    }
    
    @Test("Saves and loads warning state")
    func warningState() async {
        let defaults = UserDefaults(suiteName: "test.sensor.\(UUID().uuidString)")!
        let persistence = UserDefaultsExpirationPersistence(defaults: defaults)
        
        var state = ExpirationWarningState(sensorId: "WARN")
        state.markSent(.hours24)
        state.markSent(.hours6)
        
        await persistence.saveWarningState(state)
        let loaded = await persistence.loadWarningState(for: "WARN")
        
        #expect(loaded?.wasSent(.hours24) == true)
        #expect(loaded?.wasSent(.hours6) == true)
        #expect(loaded?.wasSent(.hours1) == false)
    }
}
