// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodErosManagerTests.swift
// PumpKitTests
//
// Unit tests for OmnipodErosManager.
// Trace: EROS-IMPL-003

import Testing
import Foundation
@testable import PumpKit

// MARK: - OmnipodErosManager Tests

@Suite("OmnipodErosManager Tests", .serialized)
struct OmnipodErosManagerTests {
    
    // MARK: - Initialization Tests
    
    @Test("Manager initializes with disconnected state")
    func managerInit() async {
        let manager = OmnipodErosManager.forTesting()
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    @Test("Manager has correct display name")
    func displayName() async {
        let manager = OmnipodErosManager.forTesting()
        #expect(manager.displayName == "Omnipod (Eros)")
    }
    
    @Test("Manager has correct pump type")
    func pumpType() async {
        let manager = OmnipodErosManager.forTesting()
        #expect(manager.pumpType == .omnipodEros)
    }
    
    // MARK: - Pod State Tests
    
    @Test("ErosPodState initializes correctly")
    func erosPodStateInit() {
        let state = ErosPodState(podAddress: 0x1F01482A)
        #expect(state.podAddress == 0x1F01482A)
        #expect(state.addressHex == "0x1F01482A")
        #expect(state.deliveryState == .basalRunning)
        #expect(state.reservoirLevel == nil)
        #expect(state.faultCode == nil)
        #expect(!state.isExpired)
        #expect(!state.isLowReservoir)
    }
    
    @Test("ErosPodState detects expired pod")
    func erosPodStateExpired() {
        let state = ErosPodState(
            podAddress: 0x1F01482A,
            activationDate: Date().addingTimeInterval(-73 * 3600) // 73 hours ago
        )
        #expect(state.isExpired)
    }
    
    @Test("ErosPodState detects low reservoir")
    func erosPodStateLowReservoir() {
        let state = ErosPodState(
            podAddress: 0x1F01482A,
            reservoirLevel: 5.0
        )
        #expect(state.isLowReservoir)
    }
    
    // MARK: - Delivery State Tests
    
    @Test("Delivery state raw values are correct")
    func deliveryStateRawValues() {
        #expect(ErosDeliveryState.basalRunning.rawValue == "basalRunning")
        #expect(ErosDeliveryState.suspended.rawValue == "suspended")
        #expect(ErosDeliveryState.faulted.rawValue == "faulted")
    }
    
    // MARK: - Temp Basal State Tests
    
    @Test("Temp basal state is active when running")
    func tempBasalStateActive() {
        let state = ErosTempBasalState(
            rate: 1.5,
            startTime: Date(),
            duration: 3600
        )
        #expect(state.isActive)
        #expect(state.rate == 1.5)
    }
    
    @Test("Temp basal state is inactive when expired")
    func tempBasalStateExpired() {
        let state = ErosTempBasalState(
            rate: 1.5,
            startTime: Date().addingTimeInterval(-3700), // Started 3700s ago
            duration: 3600  // Duration was 3600s
        )
        #expect(!state.isActive)
    }
    
    // MARK: - Pod Alert Tests
    
    @Test("Pod alert raw values are correct")
    func podAlertRawValues() {
        #expect(ErosPodAlert.lowReservoir.rawValue == "lowReservoir")
        #expect(ErosPodAlert.podExpiring.rawValue == "podExpiring")
        #expect(ErosPodAlert.occlusionDetected.rawValue == "occlusionDetected")
    }
    
    // MARK: - Simulated Pod Tests
    
    @Test("Simulate active pod sets correct state")
    func simulateActivePod() async {
        let manager = OmnipodErosManager.forTesting()
        
        await manager.simulateActivePod(address: 0xABCD1234, reservoirLevel: 100)
        
        let state = await manager.currentPodState
        #expect(state != nil)
        #expect(state?.podAddress == 0xABCD1234)
        #expect(state?.reservoirLevel == 100)
        #expect(state?.deliveryState == .basalRunning)
        
        let status = await manager.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Simulate faulted pod sets correct state")
    func simulateFaultedPod() async {
        let manager = OmnipodErosManager.forTesting()
        
        await manager.simulateFaultedPod(address: 0xDEADBEEF, faultCode: 0x14)
        
        let state = await manager.currentPodState
        #expect(state != nil)
        #expect(state?.faultCode == 0x14)
        #expect(state?.deliveryState == .faulted)
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    // MARK: - Load Pod State Tests
    
    @Test("Load pod state restores existing state")
    func loadPodState() async {
        let manager = OmnipodErosManager.forTesting()
        
        let existingState = ErosPodState(
            podAddress: 0x12345678,
            lotNumber: 11111,
            tid: 22222,
            reservoirLevel: 75
        )
        
        await manager.loadPodState(existingState)
        
        let state = await manager.currentPodState
        #expect(state?.podAddress == 0x12345678)
        #expect(state?.lotNumber == 11111)
        #expect(state?.tid == 22222)
        #expect(state?.reservoirLevel == 75)
    }
    
    // MARK: - Discard Pod Tests
    
    @Test("Discard pod clears state")
    func discardPod() async {
        let manager = OmnipodErosManager.forTesting()
        
        await manager.simulateActivePod()
        var state = await manager.currentPodState
        #expect(state != nil)
        
        await manager.discardPod()
        state = await manager.currentPodState
        #expect(state == nil)
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    // MARK: - Connect/Disconnect Tests
    
    @Test("Connect sets connected state")
    func connect() async throws {
        let manager = OmnipodErosManager.forTesting()
        
        try await manager.connect()
        
        let status = await manager.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Disconnect sets disconnected state")
    func disconnect() async throws {
        let manager = OmnipodErosManager.forTesting()
        
        try await manager.connect()
        await manager.disconnect()
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    // MARK: - Error When Not Connected Tests
    
    @Test("Refresh status throws when not connected")
    func refreshStatusWhenNotConnected() async {
        let manager = OmnipodErosManager.forTesting()
        
        do {
            try await manager.refreshStatus()
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Deliver bolus throws when not connected")
    func deliverBolusWhenNotConnected() async {
        let manager = OmnipodErosManager.forTesting()
        
        do {
            try await manager.deliverBolus(units: 1.0)
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Set temp basal throws when not connected")
    func setTempBasalWhenNotConnected() async {
        let manager = OmnipodErosManager.forTesting()
        
        do {
            try await manager.setTempBasal(rate: 1.0, duration: 3600)
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    // MARK: - Bolus Validation Tests
    
    @Test("Bolus exceeding max throws error")
    func bolusExceedsMax() async throws {
        let manager = OmnipodErosManager.forTesting()
        await manager.simulateActivePod()
        
        do {
            try await manager.deliverBolus(units: 100.0)  // Max is 10
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .exceedsMaxBolus)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Bolus with insufficient reservoir throws error")
    func bolusInsufficientReservoir() async throws {
        let manager = OmnipodErosManager.forTesting()
        await manager.simulateActivePod(reservoirLevel: 2.0)
        
        do {
            try await manager.deliverBolus(units: 5.0)
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .insufficientReservoir)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    // MARK: - Temp Basal Validation Tests
    
    @Test("Temp basal exceeding max throws error")
    func tempBasalExceedsMax() async throws {
        let manager = OmnipodErosManager.forTesting()
        await manager.simulateActivePod()
        
        do {
            try await manager.setTempBasal(rate: 100.0, duration: 3600)
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .exceedsMaxBasal)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Temp basal with duration too short throws error")
    func tempBasalDurationTooShort() async throws {
        let manager = OmnipodErosManager.forTesting()
        await manager.simulateActivePod()
        
        do {
            try await manager.setTempBasal(rate: 1.0, duration: 600)  // < 1800s
            Issue.record("Expected error")
        } catch let error as PumpError {
            #expect(error == .exceedsMaxBasal)
        } catch {
            Issue.record("Wrong error type")
        }
    }
}
