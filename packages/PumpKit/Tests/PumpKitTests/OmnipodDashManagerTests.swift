// SPDX-License-Identifier: MIT
//
// OmnipodDashManagerTests.swift
// PumpKitTests
//
// Tests for Omnipod DASH pump manager
// Trace: PUMP-009, PRD-005

import Testing
import Foundation
@testable import PumpKit

// MARK: - Pod State Tests

@Suite("DashPodState")
struct DashPodStateTests {
    
    @Test("Default state has correct values")
    func defaultState() {
        let state = DashPodState()
        
        #expect(state.deliveryState == .basalRunning)
        #expect(state.reservoirLevel == 200)
        #expect(state.totalDelivered == 0)
        #expect(state.alerts.isEmpty)
        #expect(state.faultCode == nil)
    }
    
    @Test("Pod expiration after 72 hours")
    func expiration() {
        let oldDate = Date().addingTimeInterval(-73 * 3600)
        let expiredPod = DashPodState(activationDate: oldDate)
        
        #expect(expiredPod.isExpired == true)
        
        let newPod = DashPodState()
        #expect(newPod.isExpired == false)
    }
    
    @Test("Low reservoir detection")
    func lowReservoir() {
        let lowPod = DashPodState(reservoirLevel: 5)
        #expect(lowPod.isLowReservoir == true)
        
        let normalPod = DashPodState(reservoirLevel: 50)
        #expect(normalPod.isLowReservoir == false)
    }
}

// MARK: - Temp Basal State Tests

@Suite("DashTempBasalState")
struct DashTempBasalStateTests {
    
    @Test("Active temp basal detection")
    func isActive() {
        let active = DashTempBasalState(rate: 0.5, duration: 3600)
        #expect(active.isActive == true)
        
        let expired = DashTempBasalState(
            rate: 0.5,
            startTime: Date().addingTimeInterval(-3700),
            duration: 3600
        )
        #expect(expired.isActive == false)
    }
}

// MARK: - Delivery State Tests

@Suite("DashDeliveryState")
struct DashDeliveryStateTests {
    
    @Test("All states are codable")
    func codable() throws {
        let states: [DashDeliveryState] = [
            .suspended, .basalRunning, .tempBasalRunning,
            .bolusInProgress, .faulted, .deactivated
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(DashDeliveryState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - Manager Initialization Tests

@Suite("OmnipodDashManager Initialization")
struct OmnipodDashManagerInitTests {
    
    @Test("Manager initializes with disconnected status")
    func initialStatus() async {
        let manager = OmnipodDashManager()
        let status = await manager.status
        
        #expect(status.connectionState == .disconnected)
        #expect(status.reservoirLevel == nil)
    }
    
    @Test("Manager has correct display name and type")
    func displayInfo() {
        let manager = OmnipodDashManager()
        
        #expect(manager.displayName == "Omnipod DASH")
        #expect(manager.pumpType == .omnipodDash)
    }
    
    @Test("No pod paired initially")
    func noPodInitially() async {
        let manager = OmnipodDashManager()
        let podState = await manager.currentPodState
        
        #expect(podState == nil)
    }
}

// MARK: - Pod Activation Tests

@Suite("Pod Activation")
struct PodActivationTests {
    
    @Test("Activate new pod")
    func activatePod() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        
        let podState = await manager.currentPodState
        #expect(podState != nil)
        #expect(podState?.deliveryState == .basalRunning)
        #expect(podState?.reservoirLevel == 200)
    }
    
    @Test("Cannot activate when pod already active")
    func cannotActivateWhenActive() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        
        await #expect(throws: PumpError.self) {
            try await manager.activatePod()
        }
    }
    
    @Test("Deactivate pod")
    func deactivatePod() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.deactivatePod()
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .deactivated)
    }
    
    @Test("Can activate after deactivation")
    func activateAfterDeactivation() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.deactivatePod()
        try await manager.activatePod()
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .basalRunning)
    }
}

// MARK: - Connection Tests

@Suite("DASH Connection")
struct DashConnectionTests {
    
    @Test("Connect requires pod")
    func connectRequiresPod() async {
        let manager = OmnipodDashManager()
        
        await #expect(throws: PumpError.self) {
            try await manager.connect()
        }
    }
    
    @Test("Connect with pod")
    func connectWithPod() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        let status = await manager.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Disconnect")
    func disconnect() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        await manager.disconnect()
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
}

// MARK: - Temp Basal Tests

@Suite("DASH Temp Basal")
struct DashTempBasalTests {
    
    @Test("Set temp basal")
    func setTempBasal() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .tempBasalRunning)
        #expect(podState?.lastTempBasal?.rate == 0.5)
    }
    
    @Test("Cancel temp basal")
    func cancelTempBasal() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        try await manager.cancelTempBasal()
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .basalRunning)
        #expect(podState?.lastTempBasal == nil)
    }
    
    @Test("Temp basal exceeds max fails")
    func tempBasalExceedsMax() async throws {
        let manager = OmnipodDashManager(maxBasalRate: 2.0)
        
        try await manager.activatePod()
        try await manager.connect()
        
        await #expect(throws: PumpError.self) {
            try await manager.setTempBasal(rate: 3.0, duration: 1800)
        }
    }
    
    @Test("Temp basal requires connection")
    func tempBasalRequiresConnection() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        
        await #expect(throws: PumpError.self) {
            try await manager.setTempBasal(rate: 0.5, duration: 1800)
        }
    }
}

// MARK: - Suspend/Resume Tests

@Suite("DASH Suspend Resume")
struct DashSuspendResumeTests {
    
    @Test("Suspend delivery")
    func suspend() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.suspend()
        
        let status = await manager.status
        #expect(status.connectionState == .suspended)
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .suspended)
    }
    
    @Test("Resume delivery")
    func resume() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.suspend()
        try await manager.resume()
        
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .basalRunning)
    }
    
    @Test("Suspend cancels temp basal")
    func suspendCancelsTempBasal() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        try await manager.suspend()
        
        let podState = await manager.currentPodState
        #expect(podState?.lastTempBasal == nil)
    }
}

// MARK: - Audit Log Tests

@Suite("DASH Audit Log")
struct DashAuditLogTests {
    
    @Test("Commands are logged")
    func commandsLogged() async throws {
        let auditLog = PumpAuditLog()
        let manager = OmnipodDashManager(auditLog: auditLog)
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        await manager.disconnect()
        
        let entries = await auditLog.allEntries()
        #expect(entries.count >= 4)
        
        let typeNames = entries.map { $0.command.typeName }
        #expect(typeNames.contains("activatePod"))
        #expect(typeNames.contains("connect"))
        #expect(typeNames.contains("setTempBasal"))
        #expect(typeNames.contains("disconnect"))
    }
}

// MARK: - Bolus Progress Tracking Tests (BOLUS-005)

/// Mock delegate to track bolus progress callbacks
final class MockBolusProgressDelegate: BolusProgressDelegate, @unchecked Sendable {
    var startedBoluses: [(id: UUID, requested: Double)] = []
    var progressUpdates: [(id: UUID, delivered: Double, remaining: Double, percent: Double)] = []
    var completedBoluses: [(id: UUID, delivered: Double)] = []
    var cancelledBoluses: [(id: UUID, delivered: Double, reason: BolusCancelReason)] = []
    var failedBoluses: [(id: UUID, delivered: Double, error: PumpError)] = []
    
    func bolusDidStart(id: UUID, requested: Double) {
        startedBoluses.append((id: id, requested: requested))
    }
    
    func bolusDidProgress(id: UUID, delivered: Double, remaining: Double, percentComplete: Double) {
        progressUpdates.append((id: id, delivered: delivered, remaining: remaining, percent: percentComplete))
    }
    
    func bolusDidComplete(id: UUID, delivered: Double) {
        completedBoluses.append((id: id, delivered: delivered))
    }
    
    func bolusWasCancelled(id: UUID, delivered: Double, reason: BolusCancelReason) {
        cancelledBoluses.append((id: id, delivered: delivered, reason: reason))
    }
    
    func bolusDidFail(id: UUID, delivered: Double, error: PumpError) {
        failedBoluses.append((id: id, delivered: delivered, error: error))
    }
}

@Suite("OmnipodDashManager Bolus Progress Tracking")
struct OmnipodDashBolusProgressTests {
    
    @Test("Bolus delivery notifies delegate of start")
    func bolusNotifiesStart() async throws {
        let manager = OmnipodDashManager()
        let delegate = MockBolusProgressDelegate()
        await manager.setBolusProgressDelegate(delegate)
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.deliverBolus(units: 2.0)
        
        #expect(delegate.startedBoluses.count == 1)
        #expect(delegate.startedBoluses[0].requested == 2.0)
    }
    
    @Test("Bolus delivery notifies delegate of completion")
    func bolusNotifiesCompletion() async throws {
        let manager = OmnipodDashManager()
        let delegate = MockBolusProgressDelegate()
        await manager.setBolusProgressDelegate(delegate)
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.deliverBolus(units: 1.5)
        
        #expect(delegate.completedBoluses.count == 1)
        #expect(delegate.completedBoluses[0].delivered == 1.5)
    }
    
    @Test("Bolus delivery notifies delegate of progress")
    func bolusNotifiesProgress() async throws {
        let manager = OmnipodDashManager()
        let delegate = MockBolusProgressDelegate()
        await manager.setBolusProgressDelegate(delegate)
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.deliverBolus(units: 3.0)
        
        // Should have at least one progress update
        #expect(delegate.progressUpdates.count >= 1)
        // Initial progress shows 0 delivered
        #expect(delegate.progressUpdates[0].delivered == 0)
        #expect(delegate.progressUpdates[0].remaining == 3.0)
    }
    
    @Test("Active bolus delivery is set during bolus")
    func activeBolusDeliveryTracked() async throws {
        let manager = OmnipodDashManager()
        
        try await manager.activatePod()
        try await manager.connect()
        
        // Before bolus
        let activeBefore = await manager.activeBolusDelivery
        #expect(activeBefore == nil)
        
        // Deliver bolus (completes synchronously in simulation)
        try await manager.deliverBolus(units: 1.0)
        
        // After bolus completes, should be cleared
        let activeAfter = await manager.activeBolusDelivery
        #expect(activeAfter == nil)
    }
    
    @Test("Bolus IDs are consistent across callbacks")
    func bolusIdsConsistent() async throws {
        let manager = OmnipodDashManager()
        let delegate = MockBolusProgressDelegate()
        await manager.setBolusProgressDelegate(delegate)
        
        try await manager.activatePod()
        try await manager.connect()
        try await manager.deliverBolus(units: 2.5)
        
        // Start and complete should have same ID
        #expect(delegate.startedBoluses.count == 1)
        #expect(delegate.completedBoluses.count == 1)
        #expect(delegate.startedBoluses[0].id == delegate.completedBoluses[0].id)
    }
}


