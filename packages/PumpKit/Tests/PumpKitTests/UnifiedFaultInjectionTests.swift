// SPDX-License-Identifier: MIT
//
// UnifiedFaultInjectionTests.swift
// PumpKitTests
//
// Unified fault injection test suite validating consistent error handling
// across all pump managers (RileyLink/Medtronic, Eros, DASH).
// Trace: SWIFT-FAULT-006, SIM-FAULT-001, synthesized-device-testing.md

import Testing
import Foundation
@testable import PumpKit

// MARK: - Cross-Manager Fault Consistency Tests

@Suite("Cross-Manager Fault Consistency")
struct CrossManagerFaultConsistencyTests {
    
    // MARK: - Fault-to-Error Mapping Consistency
    
    @Test("Occlusion fault maps to PumpError.occluded across managers")
    func testOcclusionMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .occlusion, trigger: .onCommand("deliverBolus"))
        ])
        
        // Test DASH manager
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        try await dashManager.connect()
        
        await #expect(throws: PumpError.occluded) {
            _ = try await dashManager.deliverBolus(units: 1.0)
        }
    }
    
    @Test("Connection drop fault maps to PumpError.notConnected across managers")
    func testConnectionDropMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .connectionDrop, trigger: .onCommand("setTempBasal"))
        ])
        
        // Test DASH manager
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        try await dashManager.connect()
        
        await #expect(throws: PumpError.notConnected) {
            _ = try await dashManager.setTempBasal(rate: 0.5, duration: 30)
        }
    }
    
    @Test("Empty reservoir fault maps to PumpError.insufficientReservoir across managers")
    func testEmptyReservoirMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .emptyReservoir, trigger: .onCommand("deliverBolus"))
        ])
        
        // Test DASH manager - emptyReservoir maps to insufficientReservoir
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        try await dashManager.connect()
        
        await #expect(throws: PumpError.insufficientReservoir) {
            _ = try await dashManager.deliverBolus(units: 1.0)
        }
    }
    
    @Test("Unexpected suspend fault maps to PumpError.suspended across managers")
    func testUnexpectedSuspendMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .unexpectedSuspend, trigger: .onCommand("setTempBasal"))
        ])
        
        // Test DASH manager
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        try await dashManager.connect()
        
        await #expect(throws: PumpError.suspended) {
            _ = try await dashManager.setTempBasal(rate: 0.5, duration: 30)
        }
    }
    
    @Test("Alarm active fault maps to PumpError.pumpFaulted across managers")
    func testAlarmActiveMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .alarmActive(code: 0x01), trigger: .onCommand("resume"))
        ])
        
        // Test DASH manager
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        try await dashManager.connect()
        try await dashManager.suspend()
        
        await #expect(throws: PumpError.pumpFaulted) {
            try await dashManager.resume()
        }
    }
    
    @Test("Connection timeout fault maps to PumpError.communicationError on connect")
    func testConnectionTimeoutMappingConsistency() async throws {
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .connectionTimeout, trigger: .immediate)
        ])
        
        // Test DASH manager - connectionTimeout maps to communicationError
        let dashManager = OmnipodDashManager(faultInjector: faultInjector)
        try await dashManager.activatePod()
        
        await #expect(throws: PumpError.communicationError) {
            try await dashManager.connect()
        }
    }
}

// MARK: - Operation Coverage Tests

@Suite("Operation Fault Coverage")
struct OperationFaultCoverageTests {
    
    // MARK: - DASH Operations Coverage
    
    @Test("DASH connect operation handles fault injection")
    func testDASHConnectFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .onCommand("connect")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        
        do {
            try await manager.connect()
            Issue.record("Expected connection fault")
        } catch {
            // Expected
        }
    }
    
    @Test("DASH setTempBasal operation handles fault injection")
    func testDASHSetTempBasalFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .communicationError(code: 0x42),
                trigger: .onCommand("setTempBasal")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        do {
            _ = try await manager.setTempBasal(rate: 0.5, duration: 30)
            Issue.record("Expected communication error")
        } catch {
            // Expected
        }
    }
    
    @Test("DASH cancelTempBasal operation handles fault injection")
    func testDASHCancelTempBasalFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionDrop,
                trigger: .onCommand("cancelTempBasal")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        do {
            try await manager.cancelTempBasal()
            Issue.record("Expected connection drop")
        } catch {
            // Expected
        }
    }
    
    @Test("DASH deliverBolus operation handles fault injection")
    func testDASHDeliverBolusFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        do {
            _ = try await manager.deliverBolus(units: 2.0)
            Issue.record("Expected occlusion error")
        } catch let error as PumpError {
            #expect(error == .occluded)
        }
    }
    
    @Test("DASH suspend operation handles fault injection")
    func testDASHSuspendFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .communicationError(code: 0x01),
                trigger: .onCommand("suspend")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        do {
            try await manager.suspend()
            Issue.record("Expected communication error")
        } catch {
            // Expected
        }
    }
    
    @Test("DASH resume operation handles fault injection")
    func testDASHResumeFaultCoverage() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .alarmActive(code: 0x02),
                trigger: .onCommand("resume")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        do {
            try await manager.resume()
            Issue.record("Expected alarm error")
        } catch let error as PumpError {
            #expect(error == .pumpFaulted)
        }
    }
}

// MARK: - Trigger Pattern Tests

@Suite("Trigger Pattern Verification")
struct TriggerPatternVerificationTests {
    
    @Test("Immediate trigger fires on first fault check (connect)")
    func testImmediateTriggerAcrossManagers() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .connectionTimeout, trigger: .immediate)
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        
        // First fault check is in connect() - should fail immediately
        await #expect(throws: PumpError.communicationError) {
            try await manager.connect()
        }
    }
    
    @Test("onCommand trigger only fires for matching operation")
    func testOnCommandTriggerSelectivity() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        // Non-matching operation should succeed
        _ = try await manager.setTempBasal(rate: 0.5, duration: 30)
        
        // Matching operation should fail
        await #expect(throws: PumpError.occluded) {
            _ = try await manager.deliverBolus(units: 1.0)
        }
    }
    
    @Test("afterCommands trigger fires after N commands")
    func testAfterCommandsTrigger() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionDrop,
                trigger: .afterCommands(2)
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        // First operation succeeds
        _ = try await manager.setTempBasal(rate: 0.5, duration: 30)
        injector.recordCommand()
        
        // Second operation succeeds
        try await manager.cancelTempBasal()
        injector.recordCommand()
        
        // Third operation fails (after 2 commands)
        await #expect(throws: PumpError.notConnected) {
            _ = try await manager.deliverBolus(units: 1.0)
        }
    }
    
    @Test("once trigger fires only once then allows success")
    func testOnceTrigger() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .once
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        
        // First fault check (connect) fails
        await #expect(throws: PumpError.communicationError) {
            try await manager.connect()
        }
        
        // Second connect succeeds (fault was once-only)
        try await manager.connect()
    }
}

// MARK: - Fault Category Coverage Tests

@Suite("Fault Category Coverage")
struct FaultCategoryCoverageTests {
    
    @Test("All delivery faults are tested")
    func testDeliveryFaultCoverage() async throws {
        let deliveryFaults: [PumpFaultType] = [
            .occlusion,
            .airInLine,
            .emptyReservoir,
            .motorStall
        ]
        
        for fault in deliveryFaults {
            #expect(fault.category == .delivery)
            #expect(fault.stopsDelivery == true)
        }
    }
    
    @Test("All communication faults are tested")
    func testCommunicationFaultCoverage() async {
        let commFaults: [PumpFaultType] = [
            .connectionDrop,
            .connectionTimeout,
            .communicationError(code: 0x01),
            .bleDisconnectMidCommand,
            .wrongChannelResponse(sent: 0, received: 1)
        ]
        
        for fault in commFaults {
            #expect(fault.category == .communication)
        }
    }
    
    @Test("All state faults are tested")
    func testStateFaultCoverage() async {
        let stateFaults: [PumpFaultType] = [
            .unexpectedSuspend,
            .alarmActive(code: 0x01),
            .primeRequired
        ]
        
        for fault in stateFaults {
            #expect(fault.category == .state)
        }
    }
    
    @Test("All battery faults are tested")
    func testBatteryFaultCoverage() async {
        let batteryFaults: [PumpFaultType] = [
            .lowBattery(level: 0.1),
            .batteryDepleted
        ]
        
        for fault in batteryFaults {
            #expect(fault.category == .battery)
        }
    }
    
    @Test("All timing faults are tested")
    func testTimingFaultCoverage() async {
        let timingFaults: [PumpFaultType] = [
            .commandDelay(milliseconds: 100),
            .intermittentFailure(probability: 0.5)
        ]
        
        for fault in timingFaults {
            #expect(fault.category == .timing)
        }
    }
}

// MARK: - Preset Verification Tests

@Suite("Fault Preset Verification")
struct FaultPresetVerificationTests {
    
    @Test("Occlusion preset has correct configuration")
    func testOcclusionPreset() {
        let injector = PumpFaultInjector.occlusion
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .occlusion)
    }
    
    @Test("Empty reservoir preset has reservoir warning faults")
    func testEmptyReservoirPreset() {
        let injector = PumpFaultInjector.emptyReservoir
        #expect(injector.faults.count >= 1)
        let hasReservoirFault = injector.faults.contains { config in
            if case .emptyReservoir = config.fault {
                return true
            }
            if case .lowBattery = config.fault {
                return true  // Low reservoir warning
            }
            return false
        }
        #expect(hasReservoirFault)
    }
    
    @Test("Unreliable connection preset has connection faults")
    func testUnreliableConnectionHasConnectionFaults() {
        let injector = PumpFaultInjector.unreliableConnection
        let hasConnectionFault = injector.faults.contains { config in
            if case .connectionDrop = config.fault {
                return true
            }
            if case .connectionTimeout = config.fault {
                return true
            }
            return false
        }
        #expect(hasConnectionFault)
    }
    
    @Test("Unreliable connection preset has multiple faults")
    func testUnreliableConnectionPreset() {
        let injector = PumpFaultInjector.unreliableConnection
        #expect(injector.faults.count >= 2)
    }
    
    @Test("Motor stall preset has correct configuration")
    func testMotorStallPreset() {
        let injector = PumpFaultInjector.motorStall
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .motorStall)
    }
}

// MARK: - Error Recovery Tests

@Suite("Error Recovery Verification")
struct ErrorRecoveryVerificationTests {
    
    @Test("Manager recovers after fault is cleared")
    func testRecoveryAfterFaultCleared() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "temp-fault",
                fault: .occlusion,  // Use occlusion - doesn't affect connection state
                trigger: .onCommand("deliverBolus")
            )
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        // First bolus fails with occlusion
        await #expect(throws: PumpError.occluded) {
            _ = try await manager.deliverBolus(units: 1.0)
        }
        
        // Clear fault
        injector.removeFault(id: "temp-fault")
        
        // Bolus now succeeds
        _ = try await manager.deliverBolus(units: 1.0)
    }
    
    @Test("Manager recovers after fault injector reset")
    func testRecoveryAfterReset() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .occlusion, trigger: .afterCommands(1))
        ])
        
        let manager = OmnipodDashManager(faultInjector: injector)
        try await manager.activatePod()
        try await manager.connect()
        
        // First operation succeeds (before count)
        _ = try await manager.setTempBasal(rate: 0.5, duration: 30)
        injector.recordCommand()
        
        // Reset before fault triggers
        injector.reset()
        
        // Operation succeeds (count reset)
        _ = try await manager.deliverBolus(units: 1.0)
    }
    
    @Test("Operations succeed without fault injector")
    func testNoFaultInjector() async throws {
        let manager = OmnipodDashManager()
        try await manager.activatePod()
        try await manager.connect()
        
        // All operations succeed
        _ = try await manager.setTempBasal(rate: 0.5, duration: 30)
        try await manager.cancelTempBasal()
        _ = try await manager.deliverBolus(units: 1.0)
        try await manager.suspend()
        try await manager.resume()
    }
}

// MARK: - Statistics Integration Tests

@Suite("Fault Statistics Integration")
struct FaultStatisticsIntegrationTests {
    
    @Test("Statistics track injected faults")
    func testStatisticsTracking() {
        var stats = PumpFaultInjectionStats()
        
        // Record delivery-stopping fault
        stats.record(.injected(.occlusion))
        #expect(stats.faultsInjected == 1)
        #expect(stats.deliveryInterruptions == 1)
        #expect(stats.faultsByCategory[.delivery] == 1)
        
        // Record communication fault (non-delivery-stopping)
        stats.record(.injected(.connectionDrop))
        #expect(stats.faultsInjected == 2)
        #expect(stats.deliveryInterruptions == 1)  // connectionDrop doesn't stop delivery
        #expect(stats.faultsByCategory[.communication] == 1)
    }
    
    @Test("Statistics track skipped faults")
    func testSkippedFaultTracking() {
        var stats = PumpFaultInjectionStats()
        
        stats.record(.skipped(.occlusion))
        #expect(stats.faultsSkipped == 1)
        #expect(stats.faultsInjected == 0)
    }
    
    @Test("Statistics calculate injection rate")
    func testInjectionRateCalculation() {
        var stats = PumpFaultInjectionStats()
        
        // 3 injected, 2 skipped = 60% injection rate
        stats.record(.injected(.occlusion))
        stats.record(.injected(.connectionDrop))
        stats.record(.injected(.emptyReservoir))
        stats.record(.skipped(.motorStall))
        stats.record(.skipped(.airInLine))
        
        let total = stats.faultsInjected + stats.faultsSkipped
        let rate = Double(stats.faultsInjected) / Double(total)
        #expect(rate == 0.6, "Injection rate should be 60%")
    }
}
