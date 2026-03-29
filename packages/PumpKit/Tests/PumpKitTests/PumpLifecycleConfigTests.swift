// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PumpLifecycleConfigTests.swift
// PumpKitTests
//
// Tests for PumpLifecycleConfig (LIFE-PUMP-006, LIFE-PUMP-007)

import Testing
import Foundation
@testable import PumpKit

// MARK: - PumpLifecycleConfig Tests

@Suite("PumpLifecycleConfig Tests")
struct PumpLifecycleConfigTests {
    
    @Test("Dana RS has 300U reservoir")
    func danaRSReservoir() {
        let config = PumpLifecycleConfig.danaRS
        #expect(config.reservoirCapacity == 300)
        #expect(config.consumableName == "Reservoir")
        #expect(config.displayName == "Dana RS")
    }
    
    @Test("Dana-i has 300U reservoir")
    func danaIReservoir() {
        let config = PumpLifecycleConfig.danaI
        #expect(config.reservoirCapacity == 300)
        #expect(config.consumableName == "Reservoir")
        #expect(config.displayName == "Dana-i")
    }
    
    @Test("Tandem X2 has 300U cartridge")
    func tandemCartridge() {
        let config = PumpLifecycleConfig.tandemX2
        #expect(config.reservoirCapacity == 300)
        #expect(config.consumableName == "Cartridge")
        #expect(config.displayName == "Tandem t:slim X2")
    }
    
    @Test("Dana has rechargeable battery")
    func danaRechargeableBattery() {
        let config = PumpLifecycleConfig.danaRS
        #expect(config.hasRechargeableBattery == true)
        #expect(config.batteryType.lowercased().contains("rechargeable"))
    }
    
    @Test("Tandem has rechargeable battery")
    func tandemRechargeableBattery() {
        let config = PumpLifecycleConfig.tandemX2
        #expect(config.hasRechargeableBattery == true)
    }
    
    @Test("Medtronic has replaceable battery")
    func medtronicReplaceableBattery() {
        let config = PumpLifecycleConfig.medtronic(model: .model723)
        #expect(config.hasRechargeableBattery == false)
        #expect(config.batteryType.lowercased().contains("aaa"))
    }
    
    @Test("All configs support site change reminder")
    func siteChangeSupport() {
        let configs: [PumpLifecycleConfig] = [
            .danaRS,
            .danaI,
            .tandemX2,
            .medtronic(model: .model723)
        ]
        
        for config in configs {
            #expect(config.supportsSiteChangeReminder == true)
            #expect(config.siteChangeIntervalHours == 72)  // 3 days
        }
    }
    
    @Test("Site change warnings include 6h and 1h")
    func siteChangeWarnings() {
        let config = PumpLifecycleConfig.tandemX2
        #expect(config.siteChangeWarningHours.contains(6))
        #expect(config.siteChangeWarningHours.contains(1))
    }
    
    @Test("Custom config works")
    func customConfig() {
        let custom = CustomPumpConfig(
            displayName: "My Pump",
            reservoirCapacity: 250,
            consumableName: "Tank",
            changeVerb: "Replace tank"
        )
        
        let config = PumpLifecycleConfig.custom(custom)
        #expect(config.reservoirCapacity == 250)
        #expect(config.consumableName == "Tank")
        #expect(config.displayName == "My Pump")
    }
}

// MARK: - MedtronicModel Tests

@Suite("MedtronicModel Tests")
struct MedtronicModelTests {
    
    @Test("Different models have different capacities")
    func modelCapacities() {
        // Smaller reservoir models (1.76mL)
        #expect(MedtronicModel.model522.reservoirCapacity == 176)
        #expect(MedtronicModel.model715.reservoirCapacity == 176)
        
        // Larger reservoir models (3.0mL)
        #expect(MedtronicModel.model523.reservoirCapacity == 300)
        #expect(MedtronicModel.model723.reservoirCapacity == 300)
    }
    
    @Test("Models have display names")
    func modelDisplayNames() {
        #expect(MedtronicModel.model723.displayName == "Medtronic 723")
        #expect(MedtronicModel.model522.displayName == "Medtronic 522")
    }
    
    @Test("All models are case iterable")
    func allCases() {
        #expect(MedtronicModel.allCases.count == 8)
    }
}

// MARK: - SiteChangeSession Tests

@Suite("SiteChangeSession Tests")
struct SiteChangeSessionTests {
    
    @Test("Session calculates recommended change date")
    func recommendedChangeDate() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        // 72 hours = 3 days
        let expected = now.addingTimeInterval(72 * 3600)
        #expect(abs(session.recommendedChangeDate.timeIntervalSince(expected)) < 1)
    }
    
    @Test("Session calculates hours remaining")
    func hoursRemaining() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        // At activation: 72 hours remaining
        #expect(abs(session.hoursRemaining(at: now) - 72) < 0.01)
        
        // After 24 hours: 48 remaining
        let after24h = now.addingTimeInterval(24 * 3600)
        #expect(abs(session.hoursRemaining(at: after24h) - 48) < 0.01)
    }
    
    @Test("Session detects change due")
    func changeDue() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        #expect(session.isChangeDue(at: now) == false)
        
        let at72h = now.addingTimeInterval(72 * 3600)
        #expect(session.isChangeDue(at: at72h) == true)
    }
    
    @Test("Session detects overdue")
    func overdue() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        // Due but not overdue
        let at73h = now.addingTimeInterval(73 * 3600)
        #expect(session.isOverdue(at: at73h) == false)
        
        // Overdue (12+ hours past due)
        let at85h = now.addingTimeInterval(85 * 3600)
        #expect(session.isOverdue(at: at85h) == true)
    }
    
    @Test("Session calculates progress")
    func progress() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        #expect(session.progress(at: now) == 0.0)
        
        let halfway = now.addingTimeInterval(36 * 3600)
        #expect(abs(session.progress(at: halfway) - 0.5) < 0.01)
        
        let complete = now.addingTimeInterval(72 * 3600)
        #expect(abs(session.progress(at: complete) - 1.0) < 0.01)
    }
    
    @Test("Session formats time remaining")
    func timeRemainingText() {
        let now = Date()
        let session = SiteChangeSession(
            pumpConfig: .tandemX2,
            siteActivationDate: now
        )
        
        // At activation
        #expect(session.timeRemainingText(at: now) == "3d 0h")
        
        // Near due
        let near = now.addingTimeInterval(70 * 3600)
        #expect(session.timeRemainingText(at: near) == "2 hours")
        
        // Overdue
        let overdue = now.addingTimeInterval(80 * 3600)
        #expect(session.timeRemainingText(at: overdue).contains("overdue"))
    }
    
    @Test("Session is Codable")
    func codable() throws {
        let session = SiteChangeSession(
            pumpConfig: .danaRS,
            siteActivationDate: Date()
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SiteChangeSession.self, from: data)
        
        #expect(decoded.pumpType == session.pumpType)
    }
}

// MARK: - SiteChangeWarning Tests

@Suite("SiteChangeWarning Tests")
struct SiteChangeWarningTests {
    
    @Test("Warning has titles and bodies")
    func warningContent() {
        #expect(SiteChangeWarning.hours6.title == "Site Change Coming")
        #expect(SiteChangeWarning.hours1.title == "Site Change Soon")
        #expect(SiteChangeWarning.due.title == "Site Change Due")
        #expect(SiteChangeWarning.overdue.title == "Site Change Overdue")
        
        #expect(!SiteChangeWarning.due.body.isEmpty)
    }
    
    @Test("Overdue is critical")
    func overdueIsCritical() {
        #expect(SiteChangeWarning.overdue.isCritical == true)
        #expect(SiteChangeWarning.hours6.isCritical == false)
        #expect(SiteChangeWarning.due.isCritical == false)
    }
    
    @Test("Warning determined by hours remaining")
    func warningForHours() {
        #expect(SiteChangeWarning.forHoursRemaining(10) == nil)
        #expect(SiteChangeWarning.forHoursRemaining(5) == .hours6)
        #expect(SiteChangeWarning.forHoursRemaining(0.5) == .hours1)
        #expect(SiteChangeWarning.forHoursRemaining(0) == .due)
        #expect(SiteChangeWarning.forHoursRemaining(-5) == .due)
        #expect(SiteChangeWarning.forHoursRemaining(-15) == .overdue)
    }
    
    @Test("Warnings are comparable")
    func comparable() {
        #expect(SiteChangeWarning.overdue < SiteChangeWarning.due)
        #expect(SiteChangeWarning.due < SiteChangeWarning.hours1)
        #expect(SiteChangeWarning.hours1 < SiteChangeWarning.hours6)
    }
}

// MARK: - SiteChangeWarningState Tests

@Suite("SiteChangeWarningState Tests")
struct SiteChangeWarningStateTests {
    
    @Test("State tracks sent warnings")
    func tracksSentWarnings() {
        var state = SiteChangeWarningState(sessionId: UUID())
        
        #expect(state.wasSent(.hours6) == false)
        
        state.markSent(.hours6)
        #expect(state.wasSent(.hours6) == true)
        #expect(state.wasSent(.hours1) == false)
    }
    
    @Test("State returns next pending warning")
    func nextPendingWarning() {
        var state = SiteChangeWarningState(sessionId: UUID())
        
        // At 5 hours remaining, should warn at 6h level
        #expect(state.nextPendingWarning(hoursRemaining: 5) == .hours6)
        
        // After marking sent
        state.markSent(.hours6)
        #expect(state.nextPendingWarning(hoursRemaining: 5) == nil)
        
        // At 0.5 hours, should warn at 1h level
        #expect(state.nextPendingWarning(hoursRemaining: 0.5) == .hours1)
    }
}

// MARK: - InMemorySiteChangeMonitorPersistence Tests

@Suite("InMemorySiteChangeMonitorPersistence Tests")
struct InMemorySiteChangeMonitorPersistenceTests {
    
    @Test("Persistence saves and loads session")
    func saveLoadSession() async {
        let persistence = InMemorySiteChangeMonitorPersistence()
        let session = SiteChangeSession(pumpConfig: .tandemX2)
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSession()
        
        #expect(loaded?.pumpType == "Tandem t:slim X2")
    }
    
    @Test("Persistence clears session")
    func clearSession() async {
        let persistence = InMemorySiteChangeMonitorPersistence()
        let session = SiteChangeSession(pumpConfig: .danaRS)
        
        await persistence.saveSession(session)
        await persistence.clearSession()
        let loaded = await persistence.loadSession()
        
        #expect(loaded == nil)
    }
    
    @Test("Persistence saves and loads warning state")
    func saveLoadWarningState() async {
        let persistence = InMemorySiteChangeMonitorPersistence()
        let sessionId = UUID()
        var state = SiteChangeWarningState(sessionId: sessionId)
        state.markSent(.hours6)
        
        await persistence.saveWarningState(state)
        let loaded = await persistence.loadWarningState(for: sessionId)
        
        #expect(loaded?.wasSent(.hours6) == true)
    }
}

// MARK: - SiteChangeMonitor Tests

@Suite("SiteChangeMonitor Tests")
struct SiteChangeMonitorTests {
    
    @Test("Monitor starts session")
    func startSession() async {
        let monitor = SiteChangeMonitor()
        
        await monitor.startSession(pumpConfig: .tandemX2)
        
        let session = await monitor.currentSession()
        #expect(session?.pumpType == "Tandem t:slim X2")
    }
    
    @Test("Monitor ends session")
    func endSession() async {
        let monitor = SiteChangeMonitor()
        
        await monitor.startSession(pumpConfig: .danaRS)
        await monitor.endSession()
        
        let session = await monitor.currentSession()
        #expect(session == nil)
    }
    
    @Test("Monitor returns no session initially")
    func noSessionInitially() async {
        let monitor = SiteChangeMonitor()
        
        let result = await monitor.checkSiteChange()
        
        #expect(result == .noSession)
    }
    
    @Test("Monitor returns healthy status")
    func healthyStatus() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .tandemX2, activationDate: now)
        
        // Check at 24 hours (48 remaining - healthy)
        let result = await monitor.checkSiteChange(at: now.addingTimeInterval(24 * 3600))
        
        switch result {
        case .healthy(let hoursRemaining):
            #expect(abs(hoursRemaining - 48) < 0.1)
        default:
            Issue.record("Expected healthy status")
        }
    }
    
    @Test("Monitor returns warning")
    func warningStatus() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .tandemX2, activationDate: now)
        
        // Check at 67 hours (5 remaining - should warn)
        let result = await monitor.checkSiteChange(at: now.addingTimeInterval(67 * 3600))
        
        switch result {
        case .warning(let notification):
            #expect(notification.warning == .hours6)
        default:
            Issue.record("Expected warning status")
        }
    }
    
    @Test("Monitor returns overdue")
    func overdueStatus() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .tandemX2, activationDate: now)
        await monitor.markWarningSent(.hours6)
        await monitor.markWarningSent(.hours1)
        await monitor.markWarningSent(.due)
        await monitor.markWarningSent(.overdue)
        
        // Check at 85 hours (13 hours overdue)
        let result = await monitor.checkSiteChange(at: now.addingTimeInterval(85 * 3600))
        
        switch result {
        case .overdue(let hoursOverdue):
            #expect(hoursOverdue > 12)
        default:
            Issue.record("Expected overdue status, got \(result)")
        }
    }
    
    @Test("Monitor reports change due")
    func changeDue() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .tandemX2, activationDate: now)
        
        let notDue = await monitor.isChangeDue(at: now)
        #expect(notDue == false)
        
        let isDue = await monitor.isChangeDue(at: now.addingTimeInterval(73 * 3600))
        #expect(isDue == true)
    }
    
    @Test("Monitor reports overdue")
    func reportOverdue() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .danaRS, activationDate: now)
        
        let notOverdue = await monitor.isOverdue(at: now)
        #expect(notOverdue == false)
        
        let isOverdue = await monitor.isOverdue(at: now.addingTimeInterval(85 * 3600))
        #expect(isOverdue == true)
    }
    
    @Test("Monitor restores session")
    func restoreSession() async {
        let persistence = InMemorySiteChangeMonitorPersistence()
        
        // First monitor saves
        let monitor1 = SiteChangeMonitor(persistence: persistence)
        await monitor1.startSession(pumpConfig: .tandemX2)
        
        // Second monitor restores
        let monitor2 = SiteChangeMonitor(persistence: persistence)
        await monitor2.restoreSession()
        
        let session = await monitor2.currentSession()
        #expect(session?.pumpType == "Tandem t:slim X2")
    }
    
    @Test("Monitor calculates progress")
    func progressCalculation() async {
        let monitor = SiteChangeMonitor()
        let now = Date()
        
        await monitor.startSession(pumpConfig: .danaRS, activationDate: now)
        
        let progress0 = await monitor.progress(at: now)
        #expect(progress0 == 0.0)
        
        let progress50 = await monitor.progress(at: now.addingTimeInterval(36 * 3600))
        #expect(abs(progress50! - 0.5) < 0.01)
    }
}
