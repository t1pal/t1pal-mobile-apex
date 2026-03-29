// SPDX-License-Identifier: MIT
//
// PumpKitTests.swift
// T1Pal Mobile
//
// Unit tests for PumpKit
// Requirements: REQ-AID-001

import Testing
import Foundation
@testable import PumpKit

// MARK: - PumpManager Protocol Tests

@Suite("PumpManager Protocol")
struct PumpManagerProtocolTests {
    
    @Test("SimulationPump conforms to protocol")
    func simulationPumpConforms() async {
        let pump = SimulationPump()
        #expect(pump.displayName == "Simulation Pump")
        #expect(pump.pumpType == .simulation)
    }
    
    @Test("Initial status is disconnected")
    func initialStatus() async {
        let pump = SimulationPump()
        let status = await pump.status
        #expect(status.connectionState == .disconnected)
    }
    
    @Test("Connect changes state")
    func connectChangesState() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        let status = await pump.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Disconnect after connect")
    func disconnectAfterConnect() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        await pump.disconnect()
        let status = await pump.status
        #expect(status.connectionState == .disconnected)
    }
}

// MARK: - TempBasal Tests

@Suite("TempBasal Commands")
struct TempBasalTests {
    
    @Test("TempBasalCommand creation")
    func tempBasalCreation() {
        let cmd = TempBasalCommand(rate: 1.5, duration: 1800)
        #expect(cmd.rate == 1.5)
        #expect(cmd.durationMinutes == 30)
        #expect(abs(cmd.totalUnits - 0.75) < 0.01)
    }
    
    @Test("TempBasalState active status")
    func tempBasalStateActive() {
        let state = TempBasalState(
            rate: 2.0,
            startTime: Date().addingTimeInterval(-300),
            endTime: Date().addingTimeInterval(1500)
        )
        #expect(state.isActive)
        #expect(state.remainingDuration > 0)
    }
    
    @Test("TempBasalState expired")
    func tempBasalStateExpired() {
        let state = TempBasalState(
            rate: 2.0,
            startTime: Date().addingTimeInterval(-1800),
            endTime: Date().addingTimeInterval(-300)
        )
        #expect(!state.isActive)
        #expect(state.remainingDuration == 0)
    }
    
    @Test("Set temp basal on connected pump")
    func setTempBasal() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        try await pump.setTempBasal(rate: 1.5, duration: 1800)
        // Should not throw
    }
    
    @Test("Set temp basal on disconnected pump fails")
    func setTempBasalDisconnected() async {
        let pump = SimulationPump()
        await #expect(throws: PumpError.self) {
            try await pump.setTempBasal(rate: 1.5, duration: 1800)
        }
    }
}

// MARK: - Bolus Tests

@Suite("Bolus Commands")
struct BolusTests {
    
    @Test("BolusCommand normal creation")
    func bolusNormal() {
        let cmd = BolusCommand.normal(2.5)
        #expect(cmd.units == 2.5)
        #expect(cmd.type == .normal)
        #expect(cmd.duration == nil)
    }
    
    @Test("BolusCommand extended creation")
    func bolusExtended() {
        let cmd = BolusCommand.extended(3.0, duration: 7200)
        #expect(cmd.units == 3.0)
        #expect(cmd.type == .extended)
        #expect(cmd.duration == 7200)
    }
    
    @Test("BolusProgress calculation")
    func bolusProgress() {
        let cmd = BolusCommand.normal(4.0)
        let progress = BolusProgress(command: cmd, deliveredUnits: 1.0, startTime: Date())
        #expect(progress.percentComplete == 0.25)
        #expect(progress.remainingUnits == 3.0)
        #expect(!progress.isComplete)
    }
    
    @Test("BolusProgress complete")
    func bolusProgressComplete() {
        let cmd = BolusCommand.normal(2.0)
        let progress = BolusProgress(command: cmd, deliveredUnits: 2.0, startTime: Date())
        #expect(progress.percentComplete == 1.0)
        #expect(progress.remainingUnits == 0)
        #expect(progress.isComplete)
    }
    
    @Test("Deliver bolus updates reservoir")
    func deliverBolusReservoir() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        let initialStatus = await pump.status
        let initialReservoir = initialStatus.reservoirLevel ?? 200
        
        try await pump.deliverBolus(units: 1.0)
        
        let status = await pump.status
        #expect(status.reservoirLevel == initialReservoir - 1.0)
        #expect(status.lastDelivery != nil)
    }
}

// MARK: - Suspend/Resume Tests

@Suite("Suspend Resume Commands")
struct SuspendResumeTests {
    
    @Test("SuspendCommand with reason")
    func suspendWithReason() {
        let cmd = SuspendCommand(reason: .lowGlucose)
        #expect(cmd.reason == .lowGlucose)
    }
    
    @Test("Suspend pump")
    func suspendPump() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        try await pump.suspend()
        let status = await pump.status
        #expect(status.connectionState == .suspended)
    }
    
    @Test("Resume pump")
    func resumePump() async throws {
        let pump = SimulationPump()
        try await pump.connect()
        try await pump.suspend()
        try await pump.resume()
        let status = await pump.status
        #expect(status.connectionState == .connected)
    }
}

// MARK: - DeliveryState Tests

@Suite("Delivery State")
struct DeliveryStateTests {
    
    @Test("Default delivery state")
    func defaultDeliveryState() {
        let state = DeliveryState()
        #expect(state.basalRate == 0)
        #expect(state.tempBasal == nil)
        #expect(state.bolusInProgress == nil)
        #expect(!state.isSuspended)
    }
    
    @Test("Effective basal with temp")
    func effectiveBasalWithTemp() {
        let temp = TempBasalState(
            rate: 2.5,
            startTime: Date().addingTimeInterval(-300),
            endTime: Date().addingTimeInterval(1500)
        )
        let state = DeliveryState(basalRate: 1.0, tempBasal: temp)
        #expect(state.effectiveBasalRate == 2.5)
    }
    
    @Test("Effective basal when suspended")
    func effectiveBasalSuspended() {
        let state = DeliveryState(basalRate: 1.0, isSuspended: true)
        #expect(state.effectiveBasalRate == 0)
    }
    
    @Test("Effective basal with expired temp")
    func effectiveBasalExpiredTemp() {
        let temp = TempBasalState(
            rate: 2.5,
            startTime: Date().addingTimeInterval(-1800),
            endTime: Date().addingTimeInterval(-300)
        )
        let state = DeliveryState(basalRate: 1.0, tempBasal: temp)
        #expect(state.effectiveBasalRate == 1.0)
    }
}

// MARK: - PumpCommand Tests

@Suite("Pump Commands")
struct PumpCommandTests {
    
    @Test("PumpCommand display names")
    func commandDisplayNames() {
        let temp = PumpCommand.tempBasal(TempBasalCommand(rate: 1.5, duration: 1800))
        #expect(temp.displayName.contains("1.5"))
        
        let bolus = PumpCommand.bolus(BolusCommand.normal(2.0))
        #expect(bolus.displayName.contains("2.0"))
        
        #expect(PumpCommand.cancelTempBasal.displayName == "Cancel Temp Basal")
        #expect(PumpCommand.suspend(SuspendCommand()).displayName == "Suspend")
        #expect(PumpCommand.resume(ResumeCommand()).displayName == "Resume")
    }
    
    @Test("QueuedCommand creation")
    func queuedCommandCreation() {
        let cmd = PumpCommand.bolus(BolusCommand.normal(1.0))
        let queued = QueuedCommand(command: cmd)
        
        #expect(queued.status == .pending)
        #expect(queued.enqueuedAt <= Date())
    }
}

// MARK: - PumpType Tests

@Suite("Pump Types")
struct PumpTypeTests {
    
    @Test("All pump types defined")
    func allPumpTypes() {
        let types: [PumpType] = [.omnipodEros, .omnipodDash, .danaRS, .danaI, .medtronic, .simulation]
        #expect(types.count == 6)
    }
    
    @Test("PumpType codable")
    func pumpTypeCodable() throws {
        let type = PumpType.omnipodDash
        let encoded = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(PumpType.self, from: encoded)
        #expect(decoded == type)
    }
}

// MARK: - PumpError Tests

@Suite("Pump Errors")
struct PumpErrorTests {
    
    @Test("PumpError cases")
    func pumpErrorCases() {
        let errors: [PumpError] = [
            .connectionFailed,
            .communicationError,
            .deliveryFailed,
            .suspended,
            .reservoirEmpty,
            .occluded,
            .expired
        ]
        #expect(errors.count == 7)
    }
}

// MARK: - PumpStatus Tests

@Suite("Pump Status")
struct PumpStatusTests {
    
    @Test("PumpStatus initialization")
    func pumpStatusInit() {
        let status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 150.5,
            batteryLevel: 0.75,
            insulinOnBoard: 2.5,
            lastDelivery: Date()
        )
        
        #expect(status.connectionState == .connected)
        #expect(status.reservoirLevel == 150.5)
        #expect(status.batteryLevel == 0.75)
        #expect(status.insulinOnBoard == 2.5)
        #expect(status.lastDelivery != nil)
    }
    
    @Test("PumpStatus defaults")
    func pumpStatusDefaults() {
        let status = PumpStatus()
        #expect(status.connectionState == .disconnected)
        #expect(status.reservoirLevel == nil)
        #expect(status.insulinOnBoard == 0)
    }
}

// MARK: - Callback Tests

@Suite("Pump Callbacks")
struct PumpCallbackTests {
    
    @Test("Status callback fires on connect")
    func statusCallbackOnConnect() async throws {
        let pump = SimulationPump()
        
        let callbackFired = CallbackTracker()
        await pump.setStatusCallback { _ in
            Task { await callbackFired.fire() }
        }
        
        try await pump.connect()
        // Wait briefly for callback to propagate
        try await Task.sleep(nanoseconds: 50_000_000)
        let fired = await callbackFired.didFire
        #expect(fired)
    }
}

// Actor to track callback in thread-safe manner
actor CallbackTracker {
    private(set) var didFire = false
    func fire() { didFire = true }
}

// Extension to make callback setting testable
extension SimulationPump {
    func setStatusCallback(_ callback: @escaping @Sendable (PumpStatus) -> Void) {
        self.onStatusChanged = callback
    }
}

// MARK: - Unified Callback Naming Tests (ARCH-001)

@Suite("Unified Callback Naming")
struct UnifiedCallbackNamingTests {
    
    @Test("Pump onDataReceived alias works")
    func pumpOnDataReceivedAlias() async throws {
        let pump = SimulationPump()
        
        let callbackFired = CallbackTracker()
        // Use unified alias instead of onStatusChanged
        await pump.setDataReceivedCallback { _ in
            Task { await callbackFired.fire() }
        }
        
        try await pump.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        let fired = await callbackFired.didFire
        #expect(fired)
    }
    
    @Test("Pump onStateChanged alias works")
    func pumpOnStateChangedAlias() async throws {
        let pump = SimulationPump()
        
        let callbackFired = CallbackTracker()
        // Use unified alias instead of onStatusChanged
        await pump.setStateChangedCallback { _ in
            Task { await callbackFired.fire() }
        }
        
        try await pump.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        let fired = await callbackFired.didFire
        #expect(fired)
    }
}

// Extension for unified alias testing
extension SimulationPump {
    func setDataReceivedCallback(_ callback: @escaping @Sendable (PumpStatus) -> Void) {
        self.onDataReceived = callback
    }
    
    func setStateChangedCallback(_ callback: @escaping @Sendable (PumpStatus) -> Void) {
        self.onStateChanged = callback
    }
}

// MARK: - Bolus Delivery State Tests (BOLUS-001)

@Suite("BolusDeliveryState")
struct BolusDeliveryStateTests {
    
    @Test("Idle state properties")
    func idleState() {
        let state = BolusDeliveryState.idle
        #expect(!state.isActive)
        #expect(state.deliveredUnits == 0)
        #expect(state.remainingUnits == 0)
        #expect(state.progress == nil)
    }
    
    @Test("Initiating state properties")
    func initiatingState() {
        let state = BolusDeliveryState.initiating(requested: 2.0)
        #expect(state.isActive)
        #expect(state.deliveredUnits == 0)
        #expect(state.remainingUnits == 2.0)
        #expect(state.progress == 0)
    }
    
    @Test("Delivering state properties")
    func deliveringState() {
        let state = BolusDeliveryState.delivering(requested: 2.0, delivered: 0.5, remaining: 1.5)
        #expect(state.isActive)
        #expect(state.deliveredUnits == 0.5)
        #expect(state.remainingUnits == 1.5)
        #expect(state.progress == 0.25)
    }
    
    @Test("Completing state properties")
    func completingState() {
        let state = BolusDeliveryState.completing(total: 2.0)
        #expect(state.isActive)
        #expect(state.deliveredUnits == 2.0)
        #expect(state.remainingUnits == 0)
        #expect(state.progress == 1.0)
    }
    
    @Test("Completed state properties")
    func completedState() {
        let state = BolusDeliveryState.completed(total: 2.0, timestamp: Date())
        #expect(!state.isActive)
        #expect(state.deliveredUnits == 2.0)
        #expect(state.remainingUnits == 0)
        #expect(state.progress == nil)
    }
    
    @Test("Cancelled state properties")
    func cancelledState() {
        let state = BolusDeliveryState.cancelled(delivered: 0.75, reason: .userRequested)
        #expect(!state.isActive)
        #expect(state.deliveredUnits == 0.75)
        #expect(state.remainingUnits == 0)
    }
    
    @Test("Failed state properties")
    func failedState() {
        let state = BolusDeliveryState.failed(delivered: 0.5, error: .occluded)
        #expect(!state.isActive)
        #expect(state.deliveredUnits == 0.5)
    }
    
    @Test("Progress calculation at 50%")
    func progressAt50Percent() {
        let state = BolusDeliveryState.delivering(requested: 4.0, delivered: 2.0, remaining: 2.0)
        #expect(state.progress == 0.5)
    }
}

// MARK: - Active Bolus Delivery Tests

@Suite("ActiveBolusDelivery")
struct ActiveBolusDeliveryTests {
    
    @Test("Initial state is initiating")
    func initialState() {
        let bolus = ActiveBolusDelivery(requestedUnits: 2.0)
        #expect(bolus.requestedUnits == 2.0)
        if case .initiating(let requested) = bolus.state {
            #expect(requested == 2.0)
        } else {
            Issue.record("Expected initiating state")
        }
    }
    
    @Test("Elapsed time calculation")
    func elapsedTime() async throws {
        let bolus = ActiveBolusDelivery(requestedUnits: 1.0)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        #expect(bolus.elapsedTime > 0)
    }
}

// MARK: - Bolus Cancel Reason Tests

@Suite("BolusCancelReason")
struct BolusCancelReasonTests {
    
    @Test("All cancel reasons are defined")
    func allReasonsExist() {
        let reasons: [BolusCancelReason] = [
            .userRequested,
            .pumpDisconnected,
            .pumpFaulted,
            .occlusionDetected,
            .lowReservoir,
            .timeout
        ]
        #expect(reasons.count == 6)
    }
}

// MARK: - BOLUS-003: Protocol Bolus Tracking Tests

@Suite("PumpManagerProtocol Bolus Tracking")
struct PumpManagerBolusTrackingTests {
    
    @Test("SimulationPump has activeBolusDelivery property")
    func simulationPumpHasActiveBolusDelivery() async {
        let pump = SimulationPump()
        let delivery = await pump.activeBolusDelivery
        #expect(delivery == nil) // No active bolus initially
    }
    
    @Test("SimulationPump has bolusProgressDelegate property")
    func simulationPumpHasBolusProgressDelegate() async {
        let pump = SimulationPump()
        let delegate = await pump.bolusProgressDelegate
        #expect(delegate == nil) // No delegate initially
    }
    
    @Test("DanaManager has activeBolusDelivery property")
    func danaManagerHasActiveBolusDelivery() async {
        let pump = DanaManager()
        let delivery = await pump.activeBolusDelivery
        #expect(delivery == nil)
    }
    
    @Test("OmnipodDashManager has activeBolusDelivery property")
    func omnipodDashManagerHasActiveBolusDelivery() async {
        let pump = OmnipodDashManager()
        let delivery = await pump.activeBolusDelivery
        #expect(delivery == nil)
    }
    
    @Test("OmnipodErosManager has activeBolusDelivery property")
    func omnipodErosManagerHasActiveBolusDelivery() async {
        let pump = OmnipodErosManager()
        let delivery = await pump.activeBolusDelivery
        #expect(delivery == nil)
    }
    
    @Test("MinimedManager has activeBolusDelivery property")
    func minimedManagerHasActiveBolusDelivery() async {
        let pump = MinimedManager()
        let delivery = await pump.activeBolusDelivery
        #expect(delivery == nil)
    }
}

