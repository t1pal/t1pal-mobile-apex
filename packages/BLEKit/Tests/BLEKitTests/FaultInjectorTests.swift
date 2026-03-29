// SPDX-License-Identifier: MIT
//
// FaultInjectorTests.swift
// BLEKitTests
//
// Tests for FaultInjector and fault injection framework.
// Trace: SIM-FAULT-001, synthesized-device-testing.md

import Testing
@testable import BLEKit

@Suite("FaultInjector Tests")
struct FaultInjectorTests {
    
    // MARK: - Basic Initialization
    
    @Test("Initializes with empty faults")
    func testEmptyInitialization() {
        let injector = FaultInjector()
        #expect(injector.faults.isEmpty)
        #expect(injector.packetCount == 0)
    }
    
    @Test("Initializes with provided faults")
    func testInitializationWithFaults() {
        let config = FaultConfiguration(
            fault: .timeout,
            trigger: .immediate,
            description: "Test timeout"
        )
        let injector = FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .timeout)
    }
    
    // MARK: - Fault Management
    
    @Test("Adds fault configuration")
    func testAddFault() {
        let injector = FaultInjector()
        injector.addFault(.timeout, trigger: .immediate)
        #expect(injector.faults.count == 1)
    }
    
    @Test("Removes fault by ID")
    func testRemoveFault() {
        let config = FaultConfiguration(id: "test-fault", fault: .timeout)
        let injector = FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        
        injector.removeFault(id: "test-fault")
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Clears all faults")
    func testClearFaults() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout),
            FaultConfiguration(fault: .occlusion)
        ])
        #expect(injector.faults.count == 2)
        
        injector.clearFaults()
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Reset clears packet count and time")
    func testReset() {
        let injector = FaultInjector()
        injector.recordPacket()
        injector.recordPacket()
        #expect(injector.packetCount == 2)
        
        injector.reset()
        #expect(injector.packetCount == 0)
    }
    
    // MARK: - Immediate Trigger
    
    @Test("Immediate trigger injects on first check")
    func testImmediateTrigger() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .immediate)
        ])
        
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .timeout)
        } else {
            Issue.record("Expected .injected, got \(result)")
        }
    }
    
    // MARK: - Packet-Based Trigger
    
    @Test("After-packets trigger waits for packet count")
    func testAfterPacketsTrigger() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .afterPackets(3))
        ])
        
        // Before threshold
        var result = injector.shouldInject()
        #expect(result == .noFault)
        
        injector.recordPacket()
        result = injector.shouldInject()
        #expect(result == .noFault)
        
        injector.recordPacket()
        result = injector.shouldInject()
        #expect(result == .noFault)
        
        injector.recordPacket() // Now at 3
        result = injector.shouldInject()
        if case .injected = result {
            // Good
        } else {
            Issue.record("Expected .injected after 3 packets")
        }
    }
    
    // MARK: - Time-Based Trigger
    
    @Test("After-time trigger checks elapsed time")
    func testAfterTimeTrigger() async throws {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .afterTime(seconds: 0.1))
        ])
        
        // Immediately - should not trigger
        var result = injector.shouldInject()
        #expect(result == .noFault)
        
        // Wait past threshold
        try await Task.sleep(for: .milliseconds(150))
        
        result = injector.shouldInject()
        if case .injected = result {
            // Good
        } else {
            Issue.record("Expected .injected after time elapsed")
        }
    }
    
    // MARK: - Operation-Based Trigger
    
    @Test("Operation trigger matches operation name")
    func testOperationTrigger() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .onOperation("authenticate"))
        ])
        
        // Wrong operation
        var result = injector.shouldInject(for: "connect")
        #expect(result == .noFault)
        
        // Matching operation
        result = injector.shouldInject(for: "authenticate")
        if case .injected = result {
            // Good
        } else {
            Issue.record("Expected .injected for matching operation")
        }
    }
    
    // MARK: - Once Trigger
    
    @Test("Once trigger only fires once")
    func testOnceTrigger() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .once)
        ])
        
        // First check - should trigger
        var result = injector.shouldInject()
        if case .injected = result {
            // Good
        } else {
            Issue.record("Expected .injected on first check")
        }
        
        // Second check - should not trigger
        result = injector.shouldInject()
        #expect(result == .noFault)
    }
    
    // MARK: - Probabilistic Faults
    
    @Test("Probabilistic fault with 100% fires every time")
    func testProbabilistic100Percent() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(
                fault: .corruptChecksum(probability: 1.0),
                trigger: .immediate
            )
        ])
        
        // Should always inject with 100% probability
        for _ in 0..<10 {
            let result = injector.shouldInject()
            if case .injected = result {
                // Good
            } else {
                Issue.record("Expected .injected with 100% probability")
                break
            }
        }
    }
    
    @Test("Probabilistic fault with 0% never fires")
    func testProbabilistic0Percent() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(
                fault: .corruptChecksum(probability: 0.0),
                trigger: .immediate
            )
        ])
        
        // Should never inject with 0% probability
        for _ in 0..<10 {
            let result = injector.shouldInject()
            if case .skipped = result {
                // Good
            } else if case .noFault = result {
                // Also acceptable
            } else {
                Issue.record("Expected .skipped or .noFault with 0% probability, got \(result)")
                break
            }
        }
    }
    
    // MARK: - Fault Type Tests
    
    @Test("Fault categories are correct")
    func testFaultCategories() {
        #expect(FaultType.dropConnection(afterPackets: 1).category == .connection)
        #expect(FaultType.timeout.category == .connection)
        #expect(FaultType.corruptChecksum(probability: 0.5).category == .protocol)
        #expect(FaultType.forceWarmup.category == .state)
        #expect(FaultType.delayResponse(milliseconds: 100).category == .timing)
        #expect(FaultType.lowBattery(level: 10).category == .resource)
    }
    
    @Test("Fault display names are descriptive")
    func testFaultDisplayNames() {
        let fault = FaultType.dropConnection(afterPackets: 5)
        #expect(fault.displayName.contains("5"))
        #expect(fault.displayName.contains("packet"))
        
        let corrupt = FaultType.corruptChecksum(probability: 0.5)
        #expect(corrupt.displayName.contains("50"))
    }
    
    // MARK: - Preset Tests
    
    @Test("Connection drop preset is configured correctly")
    func testConnectionDropPreset() {
        let injector = FaultInjector.connectionDrop
        #expect(injector.faults.count == 1)
        
        if case .dropConnection(let packets) = injector.faults.first?.fault {
            #expect(packets == 3)
        } else {
            Issue.record("Expected dropConnection fault")
        }
    }
    
    @Test("Unreliable preset has multiple faults")
    func testUnreliablePreset() {
        let injector = FaultInjector.unreliable
        #expect(injector.faults.count == 3)
    }
    
    @Test("Low battery preset includes battery and connection faults")
    func testLowBatteryPreset() {
        let injector = FaultInjector.lowBattery
        #expect(injector.faults.count == 2)
        
        let categories = injector.faults.map { $0.fault.category }
        #expect(categories.contains(.resource))
        #expect(categories.contains(.connection))
    }
    
    // MARK: - Statistics Tests
    
    @Test("Statistics tracks injected faults")
    func testStatisticsTracking() {
        var stats = FaultInjectionStats()
        #expect(stats.faultsInjected == 0)
        
        stats.record(.injected(.timeout))
        #expect(stats.faultsInjected == 1)
        #expect(stats.lastFault == .timeout)
        #expect(stats.faultsByCategory[.connection] == 1)
        
        stats.record(.skipped(.occlusion))
        #expect(stats.faultsSkipped == 1)
        #expect(stats.faultsInjected == 1) // Unchanged
    }
    
    // MARK: - Fault Category Tests
    
    @Test("All fault categories have cases")
    func testFaultCategoryCompleteness() {
        #expect(FaultCategory.allCases.count == 5)
    }
    
    // MARK: - Disabled Fault Tests
    
    @Test("Disabled faults are not injected")
    func testDisabledFaults() {
        var config = FaultConfiguration(fault: .timeout, trigger: .immediate)
        config.enabled = false
        
        let injector = FaultInjector(faults: [config])
        let result = injector.shouldInject()
        #expect(result == .noFault)
    }
    
    // MARK: - Multiple Faults
    
    @Test("First matching fault is injected")
    func testMultipleFaultsFirstMatch() {
        let injector = FaultInjector(faults: [
            FaultConfiguration(fault: .timeout, trigger: .afterPackets(5)),
            FaultConfiguration(fault: .occlusion, trigger: .immediate)
        ])
        
        // Occlusion is immediate, timeout needs packets
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .occlusion)
        } else {
            Issue.record("Expected .injected with occlusion")
        }
    }
}

// MARK: - FaultInjectionResult Equatable Extension

extension FaultInjectionResult: Equatable {
    public static func == (lhs: FaultInjectionResult, rhs: FaultInjectionResult) -> Bool {
        switch (lhs, rhs) {
        case (.noFault, .noFault):
            return true
        case (.injected(let l), .injected(let r)):
            return l == r
        case (.skipped(let l), .skipped(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}
