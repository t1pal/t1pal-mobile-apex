// SPDX-License-Identifier: MIT
//
// DanaManagerTests.swift
// PumpKitTests
//
// Tests for DanaManager PumpManagerProtocol implementation
// Trace: DANA-IMPL-004, PUMP-APP-005

import Testing
import Foundation
@testable import PumpKit
@testable import T1PalCore

@Suite("Dana Manager Tests", .serialized)
struct DanaManagerTests {
    
    // MARK: - Protocol Conformance
    
    @Test("Dana manager implements protocol")
    func danaManagerImplementsProtocol() async throws {
        let manager = DanaManager()
        
        // Verify protocol properties
        #expect(manager.displayName == "Dana Pump")
        #expect(manager.pumpType == .danaRS)
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    @Test("Initial status")
    func initialStatus() async throws {
        let manager = DanaManager()
        let status = await manager.status
        
        #expect(status.connectionState == .disconnected)
        #expect(status.reservoirLevel == nil)
        #expect(status.batteryLevel == nil)
        #expect(status.insulinOnBoard == 0)
        #expect(status.lastDelivery == nil)
    }
    
    @Test("Custom initialization")
    func customInitialization() async throws {
        let manager = DanaManager(basalRate: 0.5, maxBolus: 20.0, maxBasalRate: 3.0)
        
        #expect(manager.displayName == "Dana Pump")
    }
    
    // MARK: - Factory Integration
    
    @Test("Factory creates Dana manager")
    func factoryCreatesDanaManager() throws {
        let config = PumpDeviceConfig(
            pumpType: .dana,
            pumpSerial: "TEST-DANA-001"
        )
        
        let context = DataContext(
            sourceType: .ble,
            pumpConfig: config
        )
        
        let manager = PumpManagerFactory.create(for: context)
        
        #expect(manager != nil)
        #expect(manager?.pumpType == .danaRS)
        #expect(manager?.displayName == "Dana Pump")
    }
    
    @Test("Factory no Dana simulation")
    func factoryNoDanaSimulation() throws {
        // Verify Dana doesn't fall back to simulation
        let config = PumpDeviceConfig(
            pumpType: .dana,
            pumpSerial: "TEST-DANA-002"
        )
        
        let context = DataContext(
            sourceType: .ble,
            pumpConfig: config
        )
        
        let manager = PumpManagerFactory.create(for: context)
        
        // Should be DanaManager, not SimulationPump
        #expect(manager != nil)
        #expect(manager?.displayName != "Simulation Pump")
    }
    
    // MARK: - Temp Basal Error Paths (PUMP-APP-005)
    
    @Test("Set temp basal requires connection")
    func setTempBasalRequiresConnection() async throws {
        let manager = DanaManager()
        
        // When not connected, setTempBasal should fail with notConnected
        do {
            try await manager.setTempBasal(rate: 0.5, duration: 1800)
            Issue.record("Expected PumpError.notConnected")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Cancel temp basal requires connection")
    func cancelTempBasalRequiresConnection() async throws {
        let manager = DanaManager()
        
        // When not connected, cancelTempBasal should fail with notConnected
        do {
            try await manager.cancelTempBasal()
            Issue.record("Expected PumpError.notConnected")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    // MARK: - Bolus Error Paths (PUMP-APP-006)
    
    @Test("Deliver bolus requires connection")
    func deliverBolusRequiresConnection() async throws {
        let manager = DanaManager()
        
        // When not connected, deliverBolus should fail with notConnected
        do {
            try await manager.deliverBolus(units: 1.0)
            Issue.record("Expected PumpError.notConnected")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Deliver bolus exceeds max fails")
    func deliverBolusExceedsMaxFails() async throws {
        // Manager with low max bolus limit
        let manager = DanaManager(maxBolus: 5.0)
        await manager.enableTestMode()
        
        // Connect first
        try await manager.connect()
        
        // Attempt bolus exceeding max
        do {
            try await manager.deliverBolus(units: 10.0)
            Issue.record("Expected PumpError.exceedsMaxBolus")
        } catch let error as PumpError {
            #expect(error == .exceedsMaxBolus)
        }
    }
}
