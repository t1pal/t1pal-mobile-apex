// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// LifecycleNotificationTests.swift
// Trace: LIFE-NOTIFY-001, LIFE-NOTIFY-004

import Testing
import Foundation
@testable import T1PalCore

// MARK: - PumpType Tests

@Suite("PumpType Tests")
struct PumpTypeTests {
    
    @Test("Omnipod DASH has correct consumable name")
    func omnipodDashConsumableName() {
        let pumpType = PumpType.omnipodDash
        #expect(pumpType.consumableName == "pod")
        #expect(pumpType.changeVerb == "change")
        #expect(pumpType.deviceName == "Omnipod DASH")
    }
    
    @Test("Omnipod Eros has correct consumable name")
    func omnipodErosConsumableName() {
        let pumpType = PumpType.omnipodEros
        #expect(pumpType.consumableName == "pod")
        #expect(pumpType.changeVerb == "change")
    }
    
    @Test("Medtronic has reservoir terminology")
    func medtronicTerminology() {
        let pumpType = PumpType.medtronicMini
        #expect(pumpType.consumableName == "reservoir")
        #expect(pumpType.changeVerb == "refill")
    }
    
    @Test("Tandem has cartridge terminology")
    func tandemTerminology() {
        let pumpType = PumpType.tandem
        #expect(pumpType.consumableName == "cartridge")
        #expect(pumpType.changeVerb == "refill")
    }
    
    @Test("Dana has reservoir terminology")
    func danaTerminology() {
        let pumpType = PumpType.dana
        #expect(pumpType.consumableName == "reservoir")
        #expect(pumpType.changeVerb == "refill")
    }
    
    @Test("Generic pump has generic terminology")
    func genericTerminology() {
        let pumpType = PumpType.generic
        #expect(pumpType.consumableName == "consumable")
        #expect(pumpType.changeVerb == "replace")
    }
    
    @Test("All pump types are iterable")
    func allPumpTypesIterable() {
        #expect(PumpType.allCases.count == 6)
    }
}

// MARK: - LifecycleNotificationFactory Tests

@Suite("LifecycleNotificationFactory Tests")
struct LifecycleNotificationFactoryTests {
    
    // MARK: Pod Expiration
    
    @Test("Pod expiring with 24 hours remaining")
    func podExpiring24Hours() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 24
        )
        
        #expect(content.type == .podExpiring)
        #expect(content.pumpType == .omnipodDash)
        #expect(content.title.contains("Pod"))
        #expect(content.hoursRemaining == 24)
    }
    
    @Test("Pod expiring with 8 hours shows yellow warning")
    func podExpiring8Hours() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 8
        )
        
        #expect(content.title.contains("🟡"))
        #expect(content.body.contains("8 hours"))
    }
    
    @Test("Pod expiring with 4 hours shows orange warning")
    func podExpiring4Hours() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 4
        )
        
        #expect(content.title.contains("🟠"))
        #expect(content.body.contains("4 hours"))
    }
    
    @Test("Pod expiring with 1 hour shows red warning")
    func podExpiring1Hour() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 0.5
        )
        
        #expect(content.title.contains("🔴"))
        #expect(content.body.contains("less than 1 hour"))
    }
    
    @Test("Pod in grace period shows warning")
    func podInGracePeriod() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodEros,
            hoursRemaining: 4,
            isGracePeriod: true
        )
        
        #expect(content.title.contains("⚠️"))
        #expect(content.title.contains("Grace Period"))
        #expect(content.body.contains("expired"))
    }
    
    @Test("Pod expired notification")
    func podExpired() {
        let content = LifecycleNotificationFactory.podExpired(pumpType: .omnipodDash)
        
        #expect(content.type == .podExpired)
        #expect(content.title.contains("🛑"))
        #expect(content.body.contains("stopped"))
        #expect(content.body.lowercased().contains("change"))
    }
    
    // MARK: Reservoir
    
    @Test("Reservoir low with 50 units")
    func reservoirLow50Units() {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: .medtronicMini,
            unitsRemaining: 50
        )
        
        #expect(content.type == .reservoirLow)
        #expect(content.title.contains("🟡"))
        #expect(content.body.contains("50 units"))
    }
    
    @Test("Reservoir low with 20 units shows orange")
    func reservoirLow20Units() {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: .medtronicMini,
            unitsRemaining: 20
        )
        
        #expect(content.title.contains("🟠"))
        #expect(content.body.contains("20 units"))
    }
    
    @Test("Reservoir very low with 10 units shows red")
    func reservoirLow10Units() {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: .medtronicMini,
            unitsRemaining: 10
        )
        
        #expect(content.title.contains("🔴"))
        #expect(content.body.contains("10"))
    }
    
    @Test("Reservoir empty notification")
    func reservoirEmpty() {
        let content = LifecycleNotificationFactory.reservoirEmpty(pumpType: .medtronicMini)
        
        #expect(content.type == .reservoirLow)
        #expect(content.title.contains("🛑"))
        #expect(content.body.contains("empty"))
        #expect(content.body.contains("stopped"))
    }
    
    // MARK: Battery
    
    @Test("Battery low at 20%")
    func batteryLow20Percent() {
        let content = LifecycleNotificationFactory.batteryLow(
            pumpType: .medtronicMini,
            batteryPercent: 0.20
        )
        
        #expect(content.type == .pumpBatteryLow)
        #expect(content.title.contains("🟡"))
        #expect(content.body.contains("20%"))
    }
    
    @Test("Battery very low at 10%")
    func batteryLow10Percent() {
        let content = LifecycleNotificationFactory.batteryLow(
            pumpType: .medtronicMini,
            batteryPercent: 0.10
        )
        
        #expect(content.title.contains("🟠"))
        #expect(content.body.contains("10%"))
    }
    
    @Test("Battery critical at 5%")
    func batteryCritical5Percent() {
        let content = LifecycleNotificationFactory.batteryLow(
            pumpType: .medtronicMini,
            batteryPercent: 0.05
        )
        
        #expect(content.title.contains("🔴"))
        #expect(content.body.contains("5%"))
    }
    
    // MARK: Content Conversion
    
    @Test("LifecycleNotificationContent converts to GlucoseNotificationContent")
    func contentConversion() {
        let lifecycle = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 8
        )
        
        let glucose = lifecycle.toGlucoseNotificationContent()
        
        #expect(glucose.type == .podExpiring)
        #expect(glucose.title == lifecycle.title)
        #expect(glucose.body == lifecycle.body)
        #expect(glucose.userInfo["pumpType"] == "Omnipod DASH")
        #expect(glucose.userInfo["hoursRemaining"] == "8.0")
    }
}

// MARK: - LifecycleWarningSchedule Tests

@Suite("LifecycleWarningSchedule Tests")
struct LifecycleWarningScheduleTests {
    
    @Test("Default pod schedule has advance warnings")
    func defaultPodSchedule() {
        let schedule = LifecycleWarningSchedule.pod
        
        #expect(schedule.advanceWarnings.contains(24))
        #expect(schedule.advanceWarnings.contains(8))
        #expect(schedule.advanceWarnings.contains(4))
        #expect(schedule.advanceWarnings.contains(1))
        #expect(schedule.notifyAtExpiration == true)
        #expect(schedule.gracePeriodReminders == true)
    }
    
    @Test("Reservoir schedule has no time-based warnings")
    func reservoirSchedule() {
        let schedule = LifecycleWarningSchedule.reservoir
        
        #expect(schedule.advanceWarnings.isEmpty)
        #expect(schedule.notifyAtExpiration == false)
    }
    
    @Test("Custom schedule can be created")
    func customSchedule() {
        let schedule = LifecycleWarningSchedule(
            advanceWarnings: [12, 6, 2],
            notifyAtExpiration: false,
            gracePeriodReminders: false
        )
        
        #expect(schedule.advanceWarnings.count == 3)
        #expect(schedule.notifyAtExpiration == false)
    }
}

// MARK: - LifecycleNotificationScheduler Tests

@Suite("LifecycleNotificationScheduler Tests")
struct LifecycleNotificationSchedulerTests {
    
    @Test("Scheduler can be created")
    func schedulerCreation() async {
        let scheduler = LifecycleNotificationScheduler()
        let times = await scheduler.getScheduledTimes(for: .omnipodDash)
        
        #expect(times.isEmpty)
    }
    
    @Test("onPodActivated schedules warnings")
    func podActivationSchedulesWarnings() async {
        let scheduler = LifecycleNotificationScheduler()
        let activationDate = Date()
        
        await scheduler.onPodActivated(
            pumpType: .omnipodDash,
            activationDate: activationDate,
            lifetimeHours: 80
        )
        
        let times = await scheduler.getScheduledTimes(for: .omnipodDash)
        // Should have scheduled warnings (24h, 8h, 4h, 1h before expiration + expiration)
        #expect(times.count >= 1)
    }
    
    @Test("onPodDeactivated clears schedules")
    func podDeactivationClearsSchedules() async {
        let scheduler = LifecycleNotificationScheduler()
        
        await scheduler.onPodActivated(
            pumpType: .omnipodDash,
            activationDate: Date(),
            lifetimeHours: 80
        )
        
        await scheduler.onPodDeactivated(pumpType: .omnipodDash)
        
        let times = await scheduler.getScheduledTimes(for: .omnipodDash)
        #expect(times.isEmpty)
    }
}

// MARK: - Idiomatic Text Tests (LIFE-NOTIFY-001)

@Suite("Idiomatic Text Tests")
struct IdiomaticTextTests {
    
    @Test("Omnipod uses 'pod' and 'change' terminology")
    func omnipodTerminology() {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 4
        )
        
        #expect(content.body.contains("pod"))
        #expect(content.body.contains("change"))
        #expect(!content.body.contains("reservoir"))
        #expect(!content.body.contains("cartridge"))
    }
    
    @Test("Medtronic uses 'reservoir' and 'refill' terminology")
    func medtronicTerminology() {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: .medtronicMini,
            unitsRemaining: 20
        )
        
        #expect(content.title.contains("Reservoir"))
        #expect(content.body.contains("Medtronic"))
    }
    
    @Test("Tandem uses 'cartridge' terminology")
    func tandemTerminology() {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: .tandem,
            unitsRemaining: 20
        )
        
        #expect(content.title.contains("Cartridge"))
        #expect(content.body.contains("t:slim"))
    }
    
    @Test("Messages are actionable")
    func messagesAreActionable() {
        let podContent = LifecycleNotificationFactory.podExpiring(
            pumpType: .omnipodDash,
            hoursRemaining: 4
        )
        
        // Should contain action guidance
        #expect(podContent.body.contains("Plan") || podContent.body.contains("Prepare") || podContent.body.contains("Consider"))
    }
    
    @Test("Critical messages have urgent wording")
    func criticalMessagesUrgent() {
        let expiredContent = LifecycleNotificationFactory.podExpired(pumpType: .omnipodDash)
        
        #expect(expiredContent.body.contains("immediately"))
        #expect(expiredContent.body.contains("stopped"))
    }
}

// MARK: - Snooze Duration Tests (LIFE-NOTIFY-005)

@Suite("SnoozeDuration Tests")
struct SnoozeDurationTests {
    
    @Test("All snooze durations available")
    func allDurationsAvailable() {
        #expect(SnoozeDuration.allCases.count == 5)
    }
    
    @Test("Fifteen minutes duration")
    func fifteenMinutes() {
        let duration = SnoozeDuration.fifteenMinutes
        #expect(duration.rawValue == 15)
        #expect(duration.seconds == 900)
        #expect(duration.shortText == "15m")
        #expect(duration.displayText == "15 minutes")
    }
    
    @Test("One hour duration")
    func oneHour() {
        let duration = SnoozeDuration.oneHour
        #expect(duration.rawValue == 60)
        #expect(duration.seconds == 3600)
        #expect(duration.shortText == "1h")
        #expect(duration.displayText == "1 hour")
    }
    
    @Test("Four hours duration")
    func fourHours() {
        let duration = SnoozeDuration.fourHours
        #expect(duration.rawValue == 240)
        #expect(duration.seconds == 14400)
        #expect(duration.shortText == "4h")
    }
    
    @Test("Lifecycle defaults include common options")
    func lifecycleDefaults() {
        let defaults = SnoozeDuration.lifecycleDefaults
        #expect(defaults.contains(.fifteenMinutes))
        #expect(defaults.contains(.thirtyMinutes))
        #expect(defaults.contains(.oneHour))
        #expect(defaults.contains(.fourHours))
    }
}

// MARK: - Snoozeable Tests (LIFE-NOTIFY-005)

@Suite("Snoozeable Tests")
struct SnoozeableTests {
    
    @Test("Pod expiring is snoozeable")
    func podExpiringIsSnoozeable() {
        #expect(GlucoseNotificationType.podExpiring.isSnoozeable == true)
    }
    
    @Test("Pod expired is NOT snoozeable")
    func podExpiredNotSnoozeable() {
        #expect(GlucoseNotificationType.podExpired.isSnoozeable == false)
    }
    
    @Test("Reservoir low is snoozeable")
    func reservoirLowIsSnoozeable() {
        #expect(GlucoseNotificationType.reservoirLow.isSnoozeable == true)
    }
    
    @Test("Pump battery low is snoozeable")
    func pumpBatteryLowIsSnoozeable() {
        #expect(GlucoseNotificationType.pumpBatteryLow.isSnoozeable == true)
    }
    
    @Test("Urgent low is NOT snoozeable")
    func urgentLowNotSnoozeable() {
        #expect(GlucoseNotificationType.urgentLow.isSnoozeable == false)
    }
    
    @Test("Urgent high is NOT snoozeable")
    func urgentHighNotSnoozeable() {
        #expect(GlucoseNotificationType.urgentHigh.isSnoozeable == false)
    }
    
    @Test("Sensor expiring is snoozeable")
    func sensorExpiringIsSnoozeable() {
        #expect(GlucoseNotificationType.sensorExpiring.isSnoozeable == true)
    }
    
    @Test("Transmitter expiring is snoozeable")
    func transmitterExpiringIsSnoozeable() {
        #expect(GlucoseNotificationType.transmitterExpiring.isSnoozeable == true)
    }
}

// MARK: - LifecycleSnoozeManager Tests (LIFE-NOTIFY-005)

@Suite("LifecycleSnoozeManager Tests")
struct LifecycleSnoozeManagerTests {
    
    @Test("Manager can be created")
    func managerCreation() async {
        let manager = LifecycleSnoozeManager()
        let isSnoozed = await manager.isSnoozed(type: .podExpiring, pumpType: .omnipodDash)
        #expect(isSnoozed == false)
    }
    
    @Test("Snooze snoozeable type succeeds")
    func snoozeSnoozeable() async {
        let manager = LifecycleSnoozeManager()
        let result = await manager.snooze(type: .podExpiring, pumpType: .omnipodDash, duration: .fifteenMinutes)
        #expect(result == true)
        
        let isSnoozed = await manager.isSnoozed(type: .podExpiring, pumpType: .omnipodDash)
        #expect(isSnoozed == true)
    }
    
    @Test("Snooze critical type fails")
    func snoozeCriticalFails() async {
        let manager = LifecycleSnoozeManager()
        let result = await manager.snooze(type: .podExpired, pumpType: .omnipodDash, duration: .fifteenMinutes)
        #expect(result == false)
        
        let isSnoozed = await manager.isSnoozed(type: .podExpired, pumpType: .omnipodDash)
        #expect(isSnoozed == false)
    }
    
    @Test("Unsnooze clears snooze state")
    func unsnoozeClears() async {
        let manager = LifecycleSnoozeManager()
        _ = await manager.snooze(type: .reservoirLow, pumpType: .medtronicMini, duration: .oneHour)
        
        await manager.unsnooze(type: .reservoirLow, pumpType: .medtronicMini)
        
        let isSnoozed = await manager.isSnoozed(type: .reservoirLow, pumpType: .medtronicMini)
        #expect(isSnoozed == false)
    }
    
    @Test("Snooze remaining returns time")
    func snoozeRemainingReturnsTime() async {
        let manager = LifecycleSnoozeManager()
        _ = await manager.snooze(type: .podExpiring, pumpType: .omnipodEros, duration: .thirtyMinutes)
        
        let remaining = await manager.snoozeRemaining(type: .podExpiring, pumpType: .omnipodEros)
        #expect(remaining != nil)
        #expect(remaining! > 0)
        #expect(remaining! <= 1800) // 30 minutes in seconds
    }
    
    @Test("Clear all snoozes works")
    func clearAllSnoozesWorks() async {
        let manager = LifecycleSnoozeManager()
        _ = await manager.snooze(type: .podExpiring, pumpType: .omnipodDash, duration: .oneHour)
        _ = await manager.snooze(type: .reservoirLow, pumpType: .medtronicMini, duration: .oneHour)
        
        await manager.clearAllSnoozes()
        
        let keys = await manager.snoozedAlertKeys()
        #expect(keys.isEmpty)
    }
}

// MARK: - Notification Action Tests (LIFE-NOTIFY-005)

@Suite("LifecycleNotificationAction Tests")
struct LifecycleNotificationActionTests {
    
    @Test("Snooze actions have correct durations")
    func snoozeActionDurations() {
        #expect(LifecycleNotificationAction.snooze15.snoozeDuration == .fifteenMinutes)
        #expect(LifecycleNotificationAction.snooze30.snoozeDuration == .thirtyMinutes)
        #expect(LifecycleNotificationAction.snooze60.snoozeDuration == .oneHour)
        #expect(LifecycleNotificationAction.snooze240.snoozeDuration == .fourHours)
    }
    
    @Test("Non-snooze actions have no duration")
    func nonSnoozeActionsNoDuration() {
        #expect(LifecycleNotificationAction.acknowledge.snoozeDuration == nil)
        #expect(LifecycleNotificationAction.openApp.snoozeDuration == nil)
    }
    
    @Test("Action titles are user-friendly")
    func actionTitles() {
        #expect(LifecycleNotificationAction.snooze15.title == "Snooze 15m")
        #expect(LifecycleNotificationAction.acknowledge.title == "OK")
        #expect(LifecycleNotificationAction.openApp.title == "Open App")
    }
}

// MARK: - Notification Category Tests (LIFE-NOTIFY-005)

@Suite("LifecycleNotificationCategory Tests")
struct LifecycleNotificationCategoryTests {
    
    @Test("Snoozeable types get snoozeable category")
    func snoozeableCategory() {
        let category = LifecycleNotificationCategory.category(for: .podExpiring)
        #expect(category == .lifecycleSnoozeable)
    }
    
    @Test("Critical types get critical category")
    func criticalCategory() {
        let category = LifecycleNotificationCategory.category(for: .podExpired)
        #expect(category == .lifecycleCritical)
    }
    
    @Test("Urgent glucose gets critical category")
    func urgentGlucoseCategory() {
        let urgentLowCategory = LifecycleNotificationCategory.category(for: .urgentLow)
        let urgentHighCategory = LifecycleNotificationCategory.category(for: .urgentHigh)
        #expect(urgentLowCategory == .lifecycleCritical)
        #expect(urgentHighCategory == .lifecycleCritical)
    }
}
