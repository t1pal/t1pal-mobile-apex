// TransmitterExpirationMonitorTests.swift
// CGMKitTests
//
// Tests for transmitter expiration monitoring and warnings.
// LIFE-CGM-001: Transmitter 90-day lifecycle tracking
// LIFE-CGM-002: Transmitter activation date persistence
// LIFE-CGM-003: Transmitter replacement warnings
// LIFE-CGM-004: Battery low notification

import Testing
import Foundation
@testable import CGMKit
import T1PalCore

// MARK: - Test Helpers

/// Helper actor for safely capturing transmitter notifications in tests.
private actor TransmitterNotificationCollector {
    var expirationNotification: TransmitterExpirationNotification?
    var batteryNotification: TransmitterBatteryNotification?
    
    func setExpiration(_ notification: TransmitterExpirationNotification) {
        self.expirationNotification = notification
    }
    
    func setBattery(_ notification: TransmitterBatteryNotification) {
        self.batteryNotification = notification
    }
}

// MARK: - Transmitter Lifetime Tests

@Suite("Transmitter Lifetime")
struct TransmitterLifetimeTests {
    
    @Test("Dexcom G6 is 90 days")
    func dexcomG6Lifetime() {
        let lifetime = TransmitterLifetime.dexcomG6
        #expect(lifetime.days == 90)
        #expect(lifetime.hours == 90 * 24)
        #expect(lifetime.seconds == 90 * 86400)
    }
    
    @Test("Dexcom G7 is 10 days (integrated)")
    func dexcomG7Lifetime() {
        let lifetime = TransmitterLifetime.dexcomG7
        #expect(lifetime.days == 10)
    }
    
    @Test("Custom lifetime")
    func customLifetime() {
        let lifetime = TransmitterLifetime.custom(days: 120)
        #expect(lifetime.days == 120)
    }
    
    @Test("Lifetime for CGM type - G6")
    func lifetimeForG6() {
        let lifetime = TransmitterLifetime.forType(.dexcomG6)
        #expect(lifetime.days == 90)
    }
    
    @Test("Lifetime for CGM type - G7")
    func lifetimeForG7() {
        let lifetime = TransmitterLifetime.forType(.dexcomG7)
        #expect(lifetime.days == 10)  // Integrated with sensor
    }
    
    @Test("G6 has separate transmitter")
    func g6HasSeparateTransmitter() {
        #expect(TransmitterLifetime.hasSeparateTransmitter(.dexcomG6) == true)
    }
    
    @Test("G7 does not have separate transmitter")
    func g7NoSeparateTransmitter() {
        #expect(TransmitterLifetime.hasSeparateTransmitter(.dexcomG7) == false)
    }
    
    @Test("Libre does not have separate transmitter")
    func libreNoSeparateTransmitter() {
        #expect(TransmitterLifetime.hasSeparateTransmitter(.libre2) == false)
        #expect(TransmitterLifetime.hasSeparateTransmitter(.libre3) == false)
    }
    
    @Test("MiaoMiao has separate transmitter")
    func miaomiaoHasSeparateTransmitter() {
        #expect(TransmitterLifetime.hasSeparateTransmitter(.miaomiao) == true)
    }
}

// MARK: - Transmitter Session Tests

@Suite("Transmitter Session")
struct TransmitterSessionTests {
    
    @Test("Creates session with default lifetime")
    func createWithDefaultLifetime() {
        let session = TransmitterSession(
            transmitterId: "8G1ABC",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        #expect(session.transmitterId == "8G1ABC")
        #expect(session.cgmType == .dexcomG6)
        #expect(session.lifetimeDays == 90)
    }
    
    @Test("Creates session with custom lifetime")
    func createWithCustomLifetime() {
        let session = TransmitterSession(
            transmitterId: "8G2XYZ",
            cgmType: .dexcomG6,
            activationDate: Date(),
            lifetimeDays: 110
        )
        
        #expect(session.lifetimeDays == 110)
    }
    
    @Test("Calculates expiration date correctly")
    func expirationDate() {
        let activationDate = Date()
        let session = TransmitterSession(
            transmitterId: "8G3DEF",
            cgmType: .dexcomG6,
            activationDate: activationDate
        )
        
        let expectedExpiration = activationDate.addingTimeInterval(90 * 86400)
        #expect(abs(session.expirationDate.timeIntervalSince(expectedExpiration)) < 1.0)
    }
    
    @Test("Days remaining calculation")
    func daysRemaining() {
        let activationDate = Date().addingTimeInterval(-80 * 86400)  // 80 days ago
        let session = TransmitterSession(
            transmitterId: "8G4GHI",
            cgmType: .dexcomG6,
            activationDate: activationDate
        )
        
        let daysRemaining = session.daysRemaining()
        #expect(daysRemaining > 9.9)
        #expect(daysRemaining < 10.1)
    }
    
    @Test("Progress calculation")
    func progress() {
        let activationDate = Date().addingTimeInterval(-45 * 86400)  // 45 days ago (half way)
        let session = TransmitterSession(
            transmitterId: "8G5JKL",
            cgmType: .dexcomG6,
            activationDate: activationDate
        )
        
        let progress = session.progress()
        #expect(progress > 0.49)
        #expect(progress < 0.51)
    }
    
    @Test("Is expired check")
    func isExpired() {
        let expiredActivation = Date().addingTimeInterval(-100 * 86400)  // 100 days ago
        let activeActivation = Date().addingTimeInterval(-50 * 86400)    // 50 days ago
        
        let expiredSession = TransmitterSession(
            transmitterId: "8G6MNO",
            cgmType: .dexcomG6,
            activationDate: expiredActivation
        )
        
        let activeSession = TransmitterSession(
            transmitterId: "8G7PQR",
            cgmType: .dexcomG6,
            activationDate: activeActivation
        )
        
        #expect(expiredSession.isExpired() == true)
        #expect(activeSession.isExpired() == false)
    }
}

// MARK: - Transmitter Warning Tests

@Suite("Transmitter Warning")
struct TransmitterWarningTests {
    
    @Test("Warning for 14 days remaining")
    func warning14Days() {
        let warning = TransmitterWarning.forDaysRemaining(14.0)
        #expect(warning == .days14)
    }
    
    @Test("Warning for 7 days remaining")
    func warning7Days() {
        let warning = TransmitterWarning.forDaysRemaining(7.0)
        #expect(warning == .days7)
    }
    
    @Test("Warning for 3 days remaining")
    func warning3Days() {
        let warning = TransmitterWarning.forDaysRemaining(3.0)
        #expect(warning == .days3)
    }
    
    @Test("Warning for 1 day remaining")
    func warning1Day() {
        let warning = TransmitterWarning.forDaysRemaining(1.0)
        #expect(warning == .days1)
    }
    
    @Test("Warning for expired")
    func warningExpired() {
        let warning = TransmitterWarning.forDaysRemaining(0.0)
        #expect(warning == .expired)
        
        let negativeWarning = TransmitterWarning.forDaysRemaining(-5.0)
        #expect(negativeWarning == .expired)
    }
    
    @Test("No warning for healthy transmitter")
    func noWarningForHealthy() {
        let warning = TransmitterWarning.forDaysRemaining(50.0)
        #expect(warning == nil)
    }
    
    @Test("Warning messages are descriptive")
    func warningMessages() {
        #expect(TransmitterWarning.days14.message.contains("2 weeks"))
        #expect(TransmitterWarning.days7.message.contains("1 week"))
        #expect(TransmitterWarning.days3.message.contains("3 days"))
        #expect(TransmitterWarning.days1.message.contains("tomorrow"))
        #expect(TransmitterWarning.expired.message.contains("expired"))
    }
    
    @Test("Warning titles are appropriate")
    func warningTitles() {
        #expect(TransmitterWarning.days1.title.contains("Tomorrow"))
        #expect(TransmitterWarning.expired.title.contains("Expired"))
    }
}

// MARK: - Warning State Tests

@Suite("Transmitter Warning State")
struct TransmitterWarningStateTests {
    
    @Test("Initial state has no sent warnings")
    func initialState() {
        let state = TransmitterWarningState(transmitterId: "8G8STU")
        
        #expect(state.wasSent(.days14) == false)
        #expect(state.wasSent(.days7) == false)
        #expect(state.wasSent(.days3) == false)
        #expect(state.wasSent(.days1) == false)
        #expect(state.wasSent(.expired) == false)
        #expect(state.batteryLowSent == false)
    }
    
    @Test("Marks warning as sent")
    func markSent() {
        var state = TransmitterWarningState(transmitterId: "8G9VWX")
        
        state.markSent(.days14)
        
        #expect(state.wasSent(.days14) == true)
        #expect(state.wasSent(.days7) == false)
        #expect(state.lastWarningDate != nil)
    }
    
    @Test("Marks battery low as sent")
    func markBatteryLowSent() {
        var state = TransmitterWarningState(transmitterId: "8GAABC")
        
        state.markBatteryLowSent()
        
        #expect(state.batteryLowSent == true)
        #expect(state.lastWarningDate != nil)
    }
    
    @Test("Next pending warning returns unsent warning")
    func nextPendingWarning() {
        var state = TransmitterWarningState(transmitterId: "8GBDEF")
        
        // At 10 days remaining, should get days14 first (since it's a wider threshold)
        let firstWarning = state.nextPendingWarning(daysRemaining: 10.0)
        #expect(firstWarning == .days14)
        
        // Mark 14-day as sent
        state.markSent(.days14)
        
        // Now should get days7
        let secondWarning = state.nextPendingWarning(daysRemaining: 5.0)
        #expect(secondWarning == .days7)
    }
}

// MARK: - Battery Status Tests

@Suite("Transmitter Battery Status")
struct TransmitterBatteryStatusTests {
    
    @Test("Voltage A low threshold")
    func voltageALow() {
        let lowBattery = TransmitterBatteryStatus(voltageA: 290)
        let healthyBattery = TransmitterBatteryStatus(voltageA: 310)
        
        #expect(lowBattery.isVoltageALow == true)
        #expect(healthyBattery.isVoltageALow == false)
    }
    
    @Test("Voltage B low threshold")
    func voltageBLow() {
        let lowBattery = TransmitterBatteryStatus(voltageB: 280)
        let healthyBattery = TransmitterBatteryStatus(voltageB: 300)
        
        #expect(lowBattery.isVoltageBLow == true)
        #expect(healthyBattery.isVoltageBLow == false)
    }
    
    @Test("Is battery low overall")
    func isBatteryLow() {
        let bothHealthy = TransmitterBatteryStatus(voltageA: 320, voltageB: 310)
        let aLow = TransmitterBatteryStatus(voltageA: 290, voltageB: 310)
        let bLow = TransmitterBatteryStatus(voltageA: 320, voltageB: 280)
        
        #expect(bothHealthy.isBatteryLow == false)
        #expect(aLow.isBatteryLow == true)
        #expect(bLow.isBatteryLow == true)
    }
    
    @Test("No voltage data means not low")
    func noVoltageData() {
        let noData = TransmitterBatteryStatus()
        
        #expect(noData.isVoltageALow == false)
        #expect(noData.isVoltageBLow == false)
        #expect(noData.isBatteryLow == false)
    }
}

// MARK: - Monitor Tests

@Suite("Transmitter Expiration Monitor")
struct TransmitterExpirationMonitorTests {
    
    @Test("Monitor returns no session initially")
    func noSessionInitially() async {
        let monitor = TransmitterExpirationMonitor()
        
        let result = await monitor.checkExpiration()
        #expect(result == .noSession)
    }
    
    @Test("Monitor tracks new session")
    func trackNewSession() async {
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GCGHI",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        await monitor.startSession(session)
        
        let current = await monitor.currentSession()
        #expect(current?.transmitterId == "8GCGHI")
    }
    
    @Test("Monitor returns healthy for new transmitter")
    func healthyNewTransmitter() async {
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GDJKL",
            cgmType: .dexcomG6,
            activationDate: Date()  // Just activated
        )
        
        await monitor.startSession(session)
        
        let result = await monitor.checkExpiration()
        
        if case .healthy(let daysRemaining) = result {
            #expect(daysRemaining > 89.9)
        } else {
            Issue.record("Expected healthy result")
        }
    }
    
    @Test("Monitor returns warning at 14 days")
    func warningAt14Days() async {
        let monitor = TransmitterExpirationMonitor()
        
        // Activated 78 days ago (12 days remaining)
        let session = TransmitterSession(
            transmitterId: "8GEMNO",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-78 * 86400)
        )
        
        await monitor.startSession(session)
        
        let result = await monitor.checkExpiration()
        
        if case .warning(let notification) = result {
            #expect(notification.warning == .days14)
        } else {
            Issue.record("Expected warning result")
        }
    }
    
    @Test("Monitor returns expired for old transmitter")
    func expiredTransmitter() async {
        let monitor = TransmitterExpirationMonitor()
        
        // Activated 100 days ago
        let session = TransmitterSession(
            transmitterId: "8GFPQR",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-100 * 86400)
        )
        
        await monitor.startSession(session)
        
        let result = await monitor.checkExpiration()
        #expect(result == .expired)
    }
    
    @Test("Monitor tracks sent warnings")
    func tracksSentWarnings() async {
        let monitor = TransmitterExpirationMonitor()
        
        // 12 days remaining
        let session = TransmitterSession(
            transmitterId: "8GGSTU",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-78 * 86400)
        )
        
        await monitor.startSession(session)
        
        // First check should give warning
        let firstResult = await monitor.checkExpiration()
        if case .warning(let notification) = firstResult {
            await monitor.markWarningSent(notification.warning)
        }
        
        // Second check should show already sent
        let secondResult = await monitor.checkExpiration()
        #expect(secondResult == .alreadySent(.days14))
    }
    
    @Test("Monitor ends session")
    func endSession() async {
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GHVWX",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        await monitor.startSession(session)
        await monitor.endSession()
        
        let current = await monitor.currentSession()
        #expect(current == nil)
        
        let result = await monitor.checkExpiration()
        #expect(result == .noSession)
    }
    
    @Test("Battery check returns unknown without data")
    func batteryUnknown() async {
        let monitor = TransmitterExpirationMonitor()
        
        let result = await monitor.checkBattery()
        #expect(result == .unknown)
    }
    
    @Test("Battery check returns healthy for good battery")
    func batteryHealthy() async {
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GIABC",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        await monitor.startSession(session)
        
        let status = TransmitterBatteryStatus(voltageA: 320, voltageB: 310)
        await monitor.updateBatteryStatus(status)
        
        let result = await monitor.checkBattery()
        #expect(result == .healthy)
    }
    
    @Test("Battery check returns low for depleted battery")
    func batteryLow() async {
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GJDEF",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        await monitor.startSession(session)
        
        let status = TransmitterBatteryStatus(voltageA: 290, voltageB: 280)
        await monitor.updateBatteryStatus(status)
        
        let result = await monitor.checkBattery()
        
        if case .low(let notification) = result {
            #expect(notification.transmitterId == "8GJDEF")
        } else {
            Issue.record("Expected battery low result")
        }
    }
}

// MARK: - Persistence Tests

@Suite("Transmitter Persistence")
struct TransmitterPersistenceTests {
    
    @Test("In-memory persistence saves and loads session")
    func inMemorySession() async {
        let persistence = InMemoryTransmitterPersistence()
        
        let session = TransmitterSession(
            transmitterId: "8GKGHI",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded?.transmitterId == "8GKGHI")
    }
    
    @Test("In-memory persistence saves and loads warning state")
    func inMemoryWarningState() async {
        let persistence = InMemoryTransmitterPersistence()
        
        var state = TransmitterWarningState(transmitterId: "8GLJKL")
        state.markSent(.days14)
        
        await persistence.saveWarningState(state)
        let loaded = await persistence.loadWarningState(for: "8GLJKL")
        
        #expect(loaded?.wasSent(.days14) == true)
    }
    
    @Test("In-memory persistence saves and loads battery status")
    func inMemoryBattery() async {
        let persistence = InMemoryTransmitterPersistence()
        
        let status = TransmitterBatteryStatus(voltageA: 315, voltageB: 305)
        
        await persistence.saveBatteryStatus(status)
        let loaded = await persistence.loadBatteryStatus()
        
        #expect(loaded?.voltageA == 315)
        #expect(loaded?.voltageB == 305)
    }
    
    @Test("Monitor restores session from persistence")
    func monitorRestoresSession() async {
        let persistence = InMemoryTransmitterPersistence()
        
        let session = TransmitterSession(
            transmitterId: "8GMMNO",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        await persistence.saveSession(session)
        
        let monitor = TransmitterExpirationMonitor(persistence: persistence)
        await monitor.restoreSession()
        
        let current = await monitor.currentSession()
        #expect(current?.transmitterId == "8GMMNO")
    }
}

// MARK: - Progress Display Tests

@Suite("Transmitter Progress")
struct TransmitterProgressTests {
    
    @Test("Progress remaining text for days")
    func remainingTextDays() {
        let session = TransmitterSession(
            transmitterId: "8GNPQR",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-85 * 86400)  // 5 days remaining
        )
        
        let progress = TransmitterProgress(session: session)
        
        #expect(progress.remainingText.contains("5") || progress.remainingText.contains("days"))
    }
    
    @Test("Progress remaining text for weeks")
    func remainingTextWeeks() {
        let session = TransmitterSession(
            transmitterId: "8GOSTU",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-30 * 86400)  // 60 days remaining
        )
        
        let progress = TransmitterProgress(session: session)
        
        #expect(progress.remainingText.contains("weeks"))
    }
    
    @Test("Progress color category")
    func colorCategory() {
        let healthySession = TransmitterSession(
            transmitterId: "8GPVWX",
            cgmType: .dexcomG6,
            activationDate: Date()  // Brand new
        )
        
        let urgentSession = TransmitterSession(
            transmitterId: "8GQABC",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-88 * 86400)  // 2 days remaining
        )
        
        let healthyProgress = TransmitterProgress(session: healthySession)
        let urgentProgress = TransmitterProgress(session: urgentSession)
        
        #expect(healthyProgress.colorCategory == "healthy")
        #expect(urgentProgress.colorCategory == "warning")
    }
    
    @Test("Battery text display")
    func batteryText() {
        let session = TransmitterSession(
            transmitterId: "8GRDEF",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        let healthyBattery = TransmitterBatteryStatus(voltageA: 320)
        let lowBattery = TransmitterBatteryStatus(voltageA: 290)
        
        let healthyProgress = TransmitterProgress(session: session, batteryStatus: healthyBattery)
        let lowProgress = TransmitterProgress(session: session, batteryStatus: lowBattery)
        
        #expect(healthyProgress.batteryText?.contains("V") == true)
        #expect(lowProgress.batteryText == "Low")
    }
}

// MARK: - Notification Tests

@Suite("Transmitter Notifications")
struct TransmitterNotificationTests {
    
    @Test("Expiration notification content")
    func expirationNotificationContent() {
        let session = TransmitterSession(
            transmitterId: "8GSGHI",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        let notification = TransmitterExpirationNotification(
            session: session,
            warning: .days7,
            daysRemaining: 7.0
        )
        
        #expect(notification.title.contains("Expiring"))
        #expect(notification.body.contains("Dexcom G6"))
        // Transmitter ID is included in expired/1-day messages, not all warnings
    }
    
    @Test("Battery notification content")
    func batteryNotificationContent() {
        let notification = TransmitterBatteryNotification(
            transmitterId: "8GTJKL",
            cgmType: .dexcomG6,
            voltageA: 290,
            voltageB: 280
        )
        
        #expect(notification.title.contains("Battery"))
        #expect(notification.body.contains("low"))
        #expect(notification.body.contains("8GTJKL"))
    }
    
    @Test("Expiration converts to GlucoseNotificationContent")
    func expirationToGlucoseNotification() {
        let session = TransmitterSession(
            transmitterId: "8GUMNO",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        
        let notification = TransmitterExpirationNotification(
            session: session,
            warning: .days3,
            daysRemaining: 3.0
        )
        
        let content = notification.toNotificationContent()
        
        #expect(content.type == .transmitterExpiring)
        #expect(content.userInfo["transmitterId"] == "8GUMNO")
    }
    
    @Test("Battery converts to GlucoseNotificationContent")
    func batteryToGlucoseNotification() {
        let notification = TransmitterBatteryNotification(
            transmitterId: "8GVPQR",
            cgmType: .dexcomG6,
            voltageA: 290
        )
        
        let content = notification.toNotificationContent()
        
        #expect(content.type == .transmitterBatteryLow)
        #expect(content.userInfo["type"] == "batteryLow")
    }
}

// MARK: - Scheduler Tests

@Suite("Transmitter Scheduler")
struct TransmitterSchedulerTests {
    
    @Test("Scheduler calls handler on warning")
    func schedulerCallsHandler() async {
        let collector = TransmitterNotificationCollector()
        let monitor = TransmitterExpirationMonitor()
        
        // 5 days remaining - this is in the days7 zone, but days14 warning hasn't been sent
        // So the first unsent warning in the zone will be days14 (since days14 > days7 > days3 > days1)
        let session = TransmitterSession(
            transmitterId: "8GWSTU",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-85 * 86400)
        )
        await monitor.startSession(session)
        
        let scheduler = TransmitterExpirationScheduler(
            monitor: monitor,
            expirationHandler: { notification in
                await collector.setExpiration(notification)
            },
            batteryHandler: { notification in
                await collector.setBattery(notification)
            }
        )
        
        // Perform a check
        await scheduler.performCheck()
        
        // Should have triggered days14 warning first (it's the widest unsent threshold)
        let notification = await collector.expirationNotification
        #expect(notification?.warning == .days14)
    }
    
    @Test("Scheduler calls battery handler on low battery")
    func schedulerCallsBatteryHandler() async {
        let collector = TransmitterNotificationCollector()
        let monitor = TransmitterExpirationMonitor()
        
        let session = TransmitterSession(
            transmitterId: "8GXVWX",
            cgmType: .dexcomG6,
            activationDate: Date()
        )
        await monitor.startSession(session)
        
        // Set low battery
        let status = TransmitterBatteryStatus(voltageA: 290)
        await monitor.updateBatteryStatus(status)
        
        let scheduler = TransmitterExpirationScheduler(
            monitor: monitor,
            expirationHandler: { _ in },
            batteryHandler: { notification in
                await collector.setBattery(notification)
            }
        )
        
        await scheduler.performCheck()
        
        let notification = await collector.batteryNotification
        #expect(notification != nil)
        #expect(notification?.transmitterId == "8GXVWX")
    }
}
