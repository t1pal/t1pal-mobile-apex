// SPDX-License-Identifier: MIT
//
// OmnipodDashFaultInjectionTests.swift
// PumpKitTests
//
// Tests for Omnipod DASH fault injection framework.
// Validates error path handling in OmnipodDashManager.
// Trace: SWIFT-FAULT-005, SIM-FAULT-001, synthesized-device-testing.md

import Testing
import Foundation
@testable import PumpKit

@Suite("Omnipod DASH FaultInjector Tests")
struct OmnipodDashFaultInjectorTests {
    
    // MARK: - Setup Helper
    
    /// Create a manager with a fault injector and activated pod
    func createManagerWithPod(faultInjector: PumpFaultInjector? = nil) async throws -> OmnipodDashManager {
        let manager = OmnipodDashManager(faultInjector: faultInjector)
        try await manager.activatePod()
        try await manager.connect()
        return manager
    }
    
    // MARK: - Basic Initialization
    
    @Test("Manager initializes with fault injector")
    func testInitWithFaultInjector() async {
        let injector = PumpFaultInjector()
        let manager = OmnipodDashManager(faultInjector: injector)
        let current = await manager.currentFaultInjector
        #expect(current != nil)
    }
    
    @Test("Manager initializes without fault injector")
    func testInitWithoutFaultInjector() async {
        let manager = OmnipodDashManager()
        let current = await manager.currentFaultInjector
        #expect(current == nil)
    }
    
    @Test("Set fault injector after initialization")
    func testSetFaultInjector() async {
        let manager = OmnipodDashManager()
        var current = await manager.currentFaultInjector
        #expect(current == nil)
        
        let injector = PumpFaultInjector()
        await manager.setFaultInjector(injector)
        current = await manager.currentFaultInjector
        #expect(current != nil)
    }
    
    // MARK: - Connection Faults
    
    @Test("Connection timeout fault on connect")
    func testConnectionTimeoutOnConnect() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .onCommand("connect"))
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        
        await #expect(throws: PumpError.communicationError) {
            try await manager.connect()
        }
    }
    
    @Test("Connection drop fault on setTempBasal")
    func testConnectionDropOnTempBasal() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionDrop, trigger: .onCommand("setTempBasal"))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        
        await #expect(throws: PumpError.notConnected) {
            try await manager.setTempBasal(rate: 1.5, duration: 1800)
        }
    }
    
    // MARK: - Delivery Faults
    
    @Test("Occlusion fault on bolus")
    func testOcclusionOnBolus() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.occlusion, trigger: .onCommand("deliverBolus"))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        
        await #expect(throws: PumpError.occluded) {
            try await manager.deliverBolus(units: 2.0)
        }
    }
    
    @Test("Empty reservoir fault on bolus")
    func testEmptyReservoirOnBolus() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.emptyReservoir, trigger: .onCommand("deliverBolus"))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        
        await #expect(throws: PumpError.insufficientReservoir) {
            try await manager.deliverBolus(units: 2.0)
        }
    }
    
    // MARK: - State Faults
    
    @Test("Unexpected suspend fault")
    func testUnexpectedSuspend() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.unexpectedSuspend, trigger: .onCommand("setTempBasal"))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        
        await #expect(throws: PumpError.suspended) {
            try await manager.setTempBasal(rate: 1.0, duration: 1800)
        }
        
        // Verify pod state changed to suspended
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .suspended)
    }
    
    @Test("Alarm active fault")
    func testAlarmActive() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.alarmActive(code: 0x52), trigger: .onCommand("resume"))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        try await manager.suspend()
        
        await #expect(throws: PumpError.pumpFaulted) {
            try await manager.resume()
        }
        
        // Verify pod state changed to faulted with correct code
        let podState = await manager.currentPodState
        #expect(podState?.deliveryState == .faulted)
        #expect(podState?.faultCode == 0x52)
    }
    
    // MARK: - Trigger Types
    
    @Test("Immediate trigger fires on first operation")
    func testImmediateTrigger() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .immediate)
        
        // Don't use helper - verify fault fires on connect
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        
        // Should throw on connect (first fault-checked operation)
        await #expect(throws: PumpError.communicationError) {
            try await manager.connect()
        }
    }
    
    @Test("Probabilistic trigger respects probability")
    func testProbabilisticTrigger() async throws {
        let injector = PumpFaultInjector()
        // 0% probability = never fire
        injector.addFault(.connectionTimeout, trigger: .probabilistic(probability: 0.0))
        
        let manager = try await createManagerWithPod(faultInjector: injector)
        
        // Should not throw with 0% probability
        try await manager.setTempBasal(rate: 1.0, duration: 1800)
        try await manager.cancelTempBasal()
    }
    
    // MARK: - No Fault Injection (Baseline)
    
    @Test("Operations succeed without fault injector")
    func testNoFaultInjection() async throws {
        let manager = try await createManagerWithPod()
        
        try await manager.setTempBasal(rate: 1.5, duration: 1800)
        try await manager.cancelTempBasal()
        try await manager.suspend()
        try await manager.resume()
    }
}
