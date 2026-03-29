// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// LibreSensorLifecycleMonitorTests.swift
// CGMKitTests
//
// Tests for LibreSensorLifecycleMonitor (LIFE-CGM-005, LIFE-CGM-006)

import Testing
import Foundation
@testable import CGMKit

// MARK: - LibreSensorConfig Tests

@Suite("LibreSensorConfig Tests")
struct LibreSensorConfigTests {
    
    @Test("Warmup duration is 1 hour")
    func warmupDuration() {
        #expect(LibreSensorConfig.warmupDurationSeconds == 3600)
        #expect(LibreSensorConfig.warmupDurationMinutes == 60)
    }
    
    @Test("Lifetime is 14 days")
    func lifetime() {
        #expect(LibreSensorConfig.lifetimeDays == 14)
        #expect(LibreSensorConfig.lifetimeHours == 336)
        #expect(LibreSensorConfig.lifetimeSeconds == 336 * 3600)
    }
    
    @Test("Expiration warning thresholds")
    func warningThresholds() {
        #expect(LibreSensorConfig.expirationWarningHours.contains(24))
        #expect(LibreSensorConfig.expirationWarningHours.contains(6))
        #expect(LibreSensorConfig.expirationWarningHours.contains(1))
    }
}

// MARK: - LibreSensorState Tests

@Suite("LibreSensorState Tests")
struct LibreSensorStateTests {
    
    @Test("State has display text")
    func displayText() {
        #expect(LibreSensorState.warmingUp.displayText == "Warming Up")
        #expect(LibreSensorState.active.displayText == "Active")
        #expect(LibreSensorState.expiringSoon.displayText == "Expiring Soon")
        #expect(LibreSensorState.expired.displayText == "Expired")
        #expect(LibreSensorState.failed.displayText == "Failed")
    }
    
    @Test("State indicates reading availability")
    func hasReadings() {
        #expect(LibreSensorState.warmingUp.hasReadings == false)
        #expect(LibreSensorState.active.hasReadings == true)
        #expect(LibreSensorState.expiringSoon.hasReadings == true)
        #expect(LibreSensorState.expired.hasReadings == false)
        #expect(LibreSensorState.failed.hasReadings == false)
    }
    
    @Test("State has color indicators")
    func colorIndicators() {
        #expect(LibreSensorState.warmingUp.colorIndicator == "🔵")
        #expect(LibreSensorState.active.colorIndicator == "🟢")
        #expect(LibreSensorState.expiringSoon.colorIndicator == "🟡")
        #expect(LibreSensorState.expired.colorIndicator == "🔴")
    }
    
    @Test("State is CaseIterable")
    func caseIterable() {
        #expect(LibreSensorState.allCases.count == 5)
    }
}

// MARK: - LibreSensorSession Tests

@Suite("LibreSensorSession Tests")
struct LibreSensorSessionTests {
    
    @Test("Session calculates warmup end date")
    func warmupEndDate() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        let expectedWarmupEnd = now.addingTimeInterval(3600)  // 1 hour
        #expect(abs(session.warmupEndDate.timeIntervalSince(expectedWarmupEnd)) < 1)
    }
    
    @Test("Session calculates expiration date")
    func expirationDate() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        let expectedExpiration = now.addingTimeInterval(336 * 3600)  // 14 days
        #expect(abs(session.expirationDate.timeIntervalSince(expectedExpiration)) < 1)
    }
    
    @Test("Warmup not complete at activation")
    func warmupNotCompleteInitially() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        #expect(session.isWarmupComplete(at: now) == false)
        #expect(session.warmupRemaining(at: now) != nil)
    }
    
    @Test("Warmup complete after 1 hour")
    func warmupCompleteAfterOneHour() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        let afterWarmup = now.addingTimeInterval(3601)  // Just over 1 hour
        #expect(session.isWarmupComplete(at: afterWarmup) == true)
        #expect(session.warmupRemaining(at: afterWarmup) == nil)
    }
    
    @Test("Warmup remaining minutes")
    func warmupRemainingMinutes() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // At 30 minutes
        let at30min = now.addingTimeInterval(30 * 60)
        #expect(session.warmupRemainingMinutes(at: at30min) == 30)
        
        // At 55 minutes
        let at55min = now.addingTimeInterval(55 * 60)
        #expect(session.warmupRemainingMinutes(at: at55min) == 5)
    }
    
    @Test("Warmup progress calculation")
    func warmupProgress() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // At start
        #expect(session.warmupProgress(at: now) == 0.0)
        
        // Halfway
        let halfway = now.addingTimeInterval(30 * 60)
        #expect(abs(session.warmupProgress(at: halfway) - 0.5) < 0.01)
        
        // Complete
        let complete = now.addingTimeInterval(60 * 60)
        #expect(session.warmupProgress(at: complete) == 1.0)
    }
    
    @Test("Session not expired initially")
    func notExpiredInitially() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        #expect(session.isExpired(at: now) == false)
    }
    
    @Test("Session expired after 14 days")
    func expiredAfter14Days() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        let after14days = now.addingTimeInterval(336 * 3600 + 1)
        #expect(session.isExpired(at: after14days) == true)
    }
    
    @Test("Hours remaining calculation")
    func hoursRemaining() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // At activation: 336 hours remaining
        #expect(abs(session.hoursRemaining(at: now) - 336) < 0.01)
        
        // After 12 hours: 324 remaining
        let after12h = now.addingTimeInterval(12 * 3600)
        #expect(abs(session.hoursRemaining(at: after12h) - 324) < 0.01)
    }
    
    @Test("Days remaining calculation")
    func daysRemaining() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // At activation: 14 days remaining
        #expect(abs(session.daysRemaining(at: now) - 14) < 0.01)
        
        // After 7 days: 7 remaining
        let after7d = now.addingTimeInterval(7 * 24 * 3600)
        #expect(abs(session.daysRemaining(at: after7d) - 7) < 0.01)
    }
    
    @Test("State transitions correctly")
    func stateTransitions() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // At activation: warming up
        #expect(session.state(at: now) == .warmingUp)
        
        // After 2 hours: active
        let after2h = now.addingTimeInterval(2 * 3600)
        #expect(session.state(at: after2h) == .active)
        
        // Day 12: still active (>24h remaining)
        let day12 = now.addingTimeInterval(12 * 24 * 3600)
        #expect(session.state(at: day12) == .active)
        
        // Within 24 hours of expiration: expiring soon
        let almostExpired = now.addingTimeInterval((336 - 12) * 3600)
        #expect(session.state(at: almostExpired) == .expiringSoon)
        
        // After 14 days: expired
        let expired = now.addingTimeInterval(337 * 3600)
        #expect(session.state(at: expired) == .expired)
    }
    
    @Test("Session is Codable")
    func codable() throws {
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: Date())
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LibreSensorSession.self, from: data)
        
        #expect(decoded.sensorId == session.sensorId)
        #expect(decoded.sensorType == session.sensorType)
    }
    
    @Test("Time remaining text formatting")
    func timeRemainingText() {
        let now = Date()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: now)
        
        // Multiple days
        #expect(session.timeRemainingText(at: now) == "14 days")
        
        // Less than a day
        let lessThanDay = now.addingTimeInterval(330 * 3600)
        #expect(session.timeRemainingText(at: lessThanDay) == "6 hours")
        
        // Expired
        let expired = now.addingTimeInterval(340 * 3600)
        #expect(session.timeRemainingText(at: expired) == "Expired")
    }
}

// MARK: - LibreSensorType Tests

@Suite("LibreSensorType Tests")
struct LibreSensorTypeTests {
    
    @Test("Sensor types have display names")
    func displayNames() {
        #expect(LibreSensorType.libre2.displayName == "Libre 2")
        #expect(LibreSensorType.libreUS14day.displayName == "Libre 14-day")
        #expect(LibreSensorType.libre3.displayName == "Libre 3")
    }
    
    @Test("All types have 60 min warmup")
    func warmupMinutes() {
        for type in LibreSensorType.allCases {
            #expect(type.warmupMinutes == 60)
        }
    }
    
    @Test("All types have 14 day lifetime")
    func lifetimeDays() {
        for type in LibreSensorType.allCases {
            #expect(type.lifetimeDays == 14)
        }
    }
}

// MARK: - LibreWarmupNotification Tests

@Suite("LibreWarmupNotification Tests")
struct LibreWarmupNotificationTests {
    
    @Test("Warmup events have titles")
    func eventTitles() {
        #expect(LibreWarmupNotification.WarmupEvent.started.title == "Sensor Warming Up")
        #expect(LibreWarmupNotification.WarmupEvent.halfwayComplete.title == "Warmup Halfway")
        #expect(LibreWarmupNotification.WarmupEvent.almostComplete.title == "Warmup Almost Complete")
        #expect(LibreWarmupNotification.WarmupEvent.complete.title == "Sensor Ready")
    }
    
    @Test("Warmup events have bodies")
    func eventBodies() {
        let body = LibreWarmupNotification.WarmupEvent.complete.body(minutesRemaining: nil)
        #expect(body.contains("Glucose readings are now available"))
    }
    
    @Test("Notification converts to content")
    func toNotificationContent() {
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: Date())
        let notification = LibreWarmupNotification(session: session, event: .complete)
        
        let content = notification.toNotificationContent()
        
        #expect(content.type == .warmupComplete)
        #expect(content.title == "Sensor Ready")
    }
}

// MARK: - InMemoryLibreSensorLifecyclePersistence Tests

@Suite("InMemoryLibreSensorLifecyclePersistence Tests")
struct InMemoryLibreSensorLifecyclePersistenceTests {
    
    @Test("Persistence saves and loads session")
    func saveLoadSession() async {
        let persistence = InMemoryLibreSensorLifecyclePersistence()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: Date())
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded?.sensorId == "TEST123")
    }
    
    @Test("Persistence clears session")
    func clearSession() async {
        let persistence = InMemoryLibreSensorLifecyclePersistence()
        let session = LibreSensorSession(sensorId: "TEST123", activationDate: Date())
        
        await persistence.saveSession(session)
        await persistence.clearSession()
        let loaded = await persistence.loadSession()
        
        #expect(loaded == nil)
    }
    
    @Test("Persistence saves and loads warmup state")
    func saveLoadWarmupState() async {
        let persistence = InMemoryLibreSensorLifecyclePersistence()
        var state = LibreWarmupState(sensorId: "TEST123")
        state.markSent(.started)
        
        await persistence.saveWarmupState(state)
        let loaded = await persistence.loadWarmupState(for: "TEST123")
        
        #expect(loaded?.wasSent(.started) == true)
    }
}

// MARK: - LibreSensorLifecycleMonitor Tests

@Suite("LibreSensorLifecycleMonitor Tests")
struct LibreSensorLifecycleMonitorTests {
    
    @Test("Monitor activates sensor")
    func activateSensor() async {
        let persistence = InMemoryLibreSensorLifecyclePersistence()
        let monitor = LibreSensorLifecycleMonitor(persistence: persistence)
        
        await monitor.activateSensor(sensorId: "TEST123")
        
        let session = await monitor.currentSession()
        #expect(session?.sensorId == "TEST123")
    }
    
    @Test("Monitor ends session")
    func endSession() async {
        let monitor = LibreSensorLifecycleMonitor()
        
        await monitor.activateSensor(sensorId: "TEST123")
        await monitor.endSession()
        
        let session = await monitor.currentSession()
        #expect(session == nil)
    }
    
    @Test("Monitor returns no session initially")
    func noSessionInitially() async {
        let monitor = LibreSensorLifecycleMonitor()
        
        let result = await monitor.checkLifecycle()
        
        #expect(result == .noSession)
    }
    
    @Test("Monitor returns warming up state")
    func warmingUpState() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        
        // Check at 15 minutes (25% - before halfway milestone)
        let result = await monitor.checkLifecycle(at: now.addingTimeInterval(15 * 60))
        
        switch result {
        case .warmingUp(let minutesRemaining, let progress):
            #expect(minutesRemaining == 45)
            #expect(abs(progress - 0.25) < 0.01)
        default:
            Issue.record("Expected warmingUp state, got \(result)")
        }
    }
    
    @Test("Monitor returns warmup complete event")
    func warmupCompleteEvent() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        
        // After warmup complete
        let afterWarmup = now.addingTimeInterval(61 * 60)
        let result = await monitor.checkLifecycle(at: afterWarmup)
        
        switch result {
        case .warmupEvent(let notification):
            #expect(notification.event == .complete)
        default:
            Issue.record("Expected warmupEvent")
        }
    }
    
    @Test("Monitor returns active after warmup acknowledged")
    func activeAfterWarmupAcknowledged() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        await monitor.markWarmupEventSent(.complete)
        
        // After warmup
        let afterWarmup = now.addingTimeInterval(2 * 3600)
        let result = await monitor.checkLifecycle(at: afterWarmup)
        
        switch result {
        case .active(let hoursRemaining):
            #expect(hoursRemaining > 330)
        default:
            Issue.record("Expected active state")
        }
    }
    
    @Test("Monitor returns expiration warning")
    func expirationWarning() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        await monitor.markWarmupEventSent(.complete)
        
        // Within 24 hours of expiration (day 13.5)
        let nearExpiration = now.addingTimeInterval((336 - 12) * 3600)
        let result = await monitor.checkLifecycle(at: nearExpiration)
        
        switch result {
        case .expirationWarning(let notification):
            #expect(notification.warning == .hours24)
        default:
            Issue.record("Expected expirationWarning")
        }
    }
    
    @Test("Monitor returns expired state")
    func expiredState() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        await monitor.markWarmupEventSent(.complete)
        
        // After 14 days
        let expired = now.addingTimeInterval(337 * 3600)
        let result = await monitor.checkLifecycle(at: expired)
        
        #expect(result == .expired)
    }
    
    @Test("Monitor reports is warming up")
    func isWarmingUp() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        
        let warming = await monitor.isWarmingUp(at: now)
        #expect(warming == true)
        
        let notWarming = await monitor.isWarmingUp(at: now.addingTimeInterval(2 * 3600))
        #expect(notWarming == false)
    }
    
    @Test("Monitor reports is expired")
    func isExpired() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        
        let notExpired = await monitor.isExpired(at: now)
        #expect(notExpired == false)
        
        let expired = await monitor.isExpired(at: now.addingTimeInterval(337 * 3600))
        #expect(expired == true)
    }
    
    @Test("Monitor restores session from persistence")
    func restoreSession() async {
        let persistence = InMemoryLibreSensorLifecyclePersistence()
        
        // First monitor saves
        let monitor1 = LibreSensorLifecycleMonitor(persistence: persistence)
        await monitor1.activateSensor(sensorId: "TEST123")
        
        // Second monitor restores
        let monitor2 = LibreSensorLifecycleMonitor(persistence: persistence)
        await monitor2.restoreSession()
        
        let session = await monitor2.currentSession()
        #expect(session?.sensorId == "TEST123")
    }
    
    @Test("Monitor progress calculation")
    func progressCalculation() async {
        let monitor = LibreSensorLifecycleMonitor()
        let now = Date()
        
        await monitor.activateSensor(sensorId: "TEST123", activationDate: now)
        
        // At start
        let progress0 = await monitor.progress(at: now)
        #expect(progress0 == 0.0)
        
        // Halfway through lifetime (7 days)
        let halfway = now.addingTimeInterval(168 * 3600)
        let progress50 = await monitor.progress(at: halfway)
        #expect(abs(progress50! - 0.5) < 0.01)
    }
}
