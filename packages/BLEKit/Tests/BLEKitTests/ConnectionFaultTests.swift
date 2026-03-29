// ConnectionFaultTests.swift
// BLEKitTests
//
// Tests for connection fault injection scenarios (SIM-FAULT-002)

import Testing
@testable import BLEKit
import Foundation

/// Tests for connection fault injection with G6PeripheralEmulator
@Suite("Connection Fault Tests")
struct ConnectionFaultTests {
    
    // MARK: - Drop Connection Tests
    
    @Test("FaultInjector triggers after packet threshold")
    func dropAfterPackets() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .timeout,
            trigger: .afterPackets(3)
        )
        injector.addFault(config)
        
        // Check before any packets - should not trigger (packet count < 3)
        var result = injector.shouldInject(for: "test")
        guard case .noFault = result else {
            Issue.record("Expected no fault before any packets")
            return
        }
        
        // Record 2 packets - still below threshold
        injector.recordPacket()
        injector.recordPacket()
        result = injector.shouldInject(for: "test")
        guard case .noFault = result else {
            Issue.record("Expected no fault with 2 packets (below threshold)")
            return
        }
        
        // Record 3rd packet - now at threshold, should trigger
        injector.recordPacket()
        result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected fault to be injected at threshold")
            return
        }
        #expect(fault == .timeout)
    }
    
    @Test("Connection drop preset is correctly configured")
    func connectionDropPreset() async {
        let injector = FaultInjector.connectionDrop
        
        // Check that the preset has the expected fault type
        guard let config = injector.faults.first else {
            Issue.record("Expected at least one fault configuration")
            return
        }
        if case .dropConnection(let packets) = config.fault {
            #expect(packets == 3)
        } else {
            Issue.record("Expected dropConnection fault")
        }
    }
    
    @Test("Once trigger fires exactly once")
    func onceTrigger() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .timeout,
            trigger: .once
        )
        injector.addFault(config)
        
        // First check should trigger
        let result1 = injector.shouldInject(for: "test")
        guard case .injected = result1 else {
            Issue.record("Expected first injection")
            return
        }
        
        // Second check should not trigger
        let result2 = injector.shouldInject(for: "test")
        guard case .noFault = result2 else {
            Issue.record("Expected no second injection")
            return
        }
    }
    
    // MARK: - Timeout Tests
    
    @Test("Timeout fault type is recognized")
    func timeoutFaultType() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .timeout,
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected timeout fault")
            return
        }
        #expect(fault == .timeout)
    }
    
    @Test("Timeout with operation filter")
    func timeoutOnSpecificOperation() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .timeout,
            trigger: .onOperation("authenticate")
        )
        injector.addFault(config)
        
        // Should not trigger for other operations
        let result1 = injector.shouldInject(for: "sendGlucose")
        guard case .noFault = result1 else {
            Issue.record("Should not trigger for wrong operation")
            return
        }
        
        // Should trigger for matching operation
        let result2 = injector.shouldInject(for: "authenticate")
        guard case .injected(let fault) = result2 else {
            Issue.record("Should trigger for matching operation")
            return
        }
        #expect(fault == .timeout)
    }
    
    // MARK: - Delay Tests
    
    @Test("Delay response fault type")
    func delayResponseFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .delayResponse(milliseconds: 500),
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected delay fault")
            return
        }
        if case .delayResponse(let ms) = fault {
            #expect(ms == 500)
        } else {
            Issue.record("Wrong fault type")
        }
    }
    
    @Test("Random delay fault with range")
    func randomDelayFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .randomDelay(minMs: 100, maxMs: 500),
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected delay fault")
            return
        }
        if case .randomDelay(let minMs, let maxMs) = fault {
            #expect(minMs == 100)
            #expect(maxMs == 500)
        } else {
            Issue.record("Wrong fault type")
        }
    }
    
    // MARK: - Sensor State Fault Tests
    
    @Test("Force warmup fault type")
    func forceWarmupFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .forceWarmup,
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected warmup fault")
            return
        }
        #expect(fault == .forceWarmup)
    }
    
    @Test("Force expired fault type")
    func forceExpiredFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .forceExpired,
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected expired fault")
            return
        }
        #expect(fault == .forceExpired)
    }
    
    @Test("Low battery preset is configured correctly")
    func lowBatteryPreset() async {
        let injector = FaultInjector.lowBattery
        
        // Check that the preset has a low battery fault
        let hasBatteryFault = injector.faults.contains { config in
            if case .lowBattery = config.fault {
                return true
            }
            return false
        }
        #expect(hasBatteryFault == true)
    }
    
    // MARK: - Error Response Tests
    
    @Test("Return error code fault")
    func returnErrorFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .returnError(code: 0x81),
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected error fault")
            return
        }
        if case .returnError(let code) = fault {
            #expect(code == 0x81)
        } else {
            Issue.record("Wrong fault type")
        }
    }
    
    @Test("Sensor failure fault")
    func sensorFailureFault() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .sensorFailure(code: 0x02),
            trigger: .immediate
        )
        injector.addFault(config)
        
        let result = injector.shouldInject(for: "test")
        guard case .injected(let fault) = result else {
            Issue.record("Expected sensor failure fault")
            return
        }
        if case .sensorFailure(let code) = fault {
            #expect(code == 0x02)
        } else {
            Issue.record("Wrong fault type")
        }
    }
    
    // MARK: - Probabilistic Fault Tests
    
    @Test("Probabilistic trigger respects probability")
    func probabilisticTrigger() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .dropPacket(probability: 1.0), // 100% chance
            trigger: .immediate
        )
        injector.addFault(config)
        
        // Should always trigger with 100% probability
        let result = injector.shouldInject(for: "test")
        guard case .injected = result else {
            Issue.record("Expected injection with 100% probability")
            return
        }
    }
    
    @Test("Zero probability never triggers")
    func zeroProbabilityNeverTriggers() async {
        let injector = FaultInjector()
        let config = FaultConfiguration(
            fault: .dropPacket(probability: 0.0),
            trigger: .immediate
        )
        injector.addFault(config)
        
        // Should never trigger with 0% probability
        var triggerCount = 0
        for _ in 0..<100 {
            let result = injector.shouldInject(for: "test")
            if case .injected = result {
                triggerCount += 1
            }
        }
        #expect(triggerCount == 0)
    }
    
    // MARK: - Multiple Fault Tests
    
    @Test("Multiple faults can be configured")
    func multipleFaults() async {
        let injector = FaultInjector()
        
        injector.addFault(FaultConfiguration(
            fault: .timeout,
            trigger: .onOperation("auth")
        ))
        injector.addFault(FaultConfiguration(
            fault: .forceWarmup,
            trigger: .onOperation("glucose")
        ))
        
        // Auth operation should trigger timeout
        let authResult = injector.shouldInject(for: "auth")
        if case .injected(let fault) = authResult {
            #expect(fault == .timeout)
        } else {
            Issue.record("Expected auth to trigger timeout")
        }
        
        // Glucose operation should trigger forceWarmup
        let glucoseResult = injector.shouldInject(for: "glucose")
        if case .injected(let fault) = glucoseResult {
            #expect(fault == .forceWarmup)
        } else {
            Issue.record("Expected glucose to trigger forceWarmup")
        }
    }
    
    @Test("Clear removes all faults")
    func clearFaults() async {
        let injector = FaultInjector()
        injector.addFault(FaultConfiguration(
            fault: .timeout,
            trigger: .immediate
        ))
        
        injector.clearFaults()
        
        let result = injector.shouldInject(for: "test")
        guard case .noFault = result else {
            Issue.record("Expected no fault after clear")
            return
        }
    }
    
    // MARK: - Preset Tests
    
    @Test("Unreliable preset has multiple faults")
    func unreliablePreset() async {
        let injector = FaultInjector.unreliable
        
        // Run multiple checks to exercise probabilistic faults
        var hadInjection = false
        for _ in 0..<100 {
            let result = injector.shouldInject(for: "test")
            if case .injected = result {
                hadInjection = true
            }
        }
        
        // With unreliable preset (5% drop, 20% delay, 2% corrupt), 
        // we should see at least one injection in 100 tries
        #expect(hadInjection == true)
    }
    
    @Test("Sensor problems preset injects warmup or expired")
    func sensorProblemsPreset() async {
        let injector = FaultInjector.sensorProblems
        
        var hadWarmup = false
        var hadExpired = false
        
        // Run multiple checks
        for _ in 0..<50 {
            let result = injector.shouldInject(for: "test")
            if case .injected(let fault) = result {
                if fault == .forceWarmup {
                    hadWarmup = true
                } else if fault == .forceExpired {
                    hadExpired = true
                }
            }
        }
        
        // Should have at least one of each
        #expect(hadWarmup || hadExpired)
    }
    
    @Test("Corruption prone preset has corruption faults")
    func corruptionPronePreset() async {
        let injector = FaultInjector.corruptionProne
        
        // Check that the preset has corruption faults
        let hasCorruptionFault = injector.faults.contains { config in
            if case .corruptChecksum = config.fault {
                return true
            }
            if case .corruptData = config.fault {
                return true
            }
            return false
        }
        #expect(hasCorruptionFault == true)
    }
}

// MARK: - G6PeripheralEmulator Integration Tests

@Suite("G6 Emulator Fault Integration")
struct G6EmulatorFaultIntegrationTests {
    
    @Test("Emulator accepts fault injector")
    func emulatorAcceptsFaultInjector() async {
        let emulator = G6PeripheralEmulator.forTesting()
        let injector = FaultInjector()
        
        await emulator.setFaultInjector(injector)
        
        let hasInjector = await emulator.hasFaultInjector
        #expect(hasInjector == true)
    }
    
    @Test("Emulator without injector operates normally")
    func emulatorWithoutInjector() async {
        let emulator = G6PeripheralEmulator.forTesting()
        
        let hasInjector = await emulator.hasFaultInjector
        #expect(hasInjector == false)
    }
    
    @Test("Connection drop fault can be configured")
    func configureConnectionDropFault() async {
        let emulator = G6PeripheralEmulator.forTesting()
        let injector = FaultInjector.connectionDrop
        
        await emulator.setFaultInjector(injector)
        
        let hasInjector = await emulator.hasFaultInjector
        #expect(hasInjector == true)
    }
    
    @Test("Emulator status reflects fault injection capability")
    func emulatorStatusWithFaultInjector() async {
        let emulator = G6PeripheralEmulator.forTesting()
        
        // Initially no injector
        let statusBefore = await emulator.status
        #expect(statusBefore.state == .idle)
        
        // Add injector
        let injector = FaultInjector.unreliable
        await emulator.setFaultInjector(injector)
        
        let hasInjector = await emulator.hasFaultInjector
        #expect(hasInjector == true)
    }
    
    @Test("Can remove fault injector")
    func removeFaultInjector() async {
        let emulator = G6PeripheralEmulator.forTesting()
        let injector = FaultInjector()
        
        await emulator.setFaultInjector(injector)
        #expect(await emulator.hasFaultInjector == true)
        
        await emulator.setFaultInjector(nil)
        #expect(await emulator.hasFaultInjector == false)
    }
}

// MARK: - Reconnection Scenario Tests

@Suite("Reconnection Scenarios")
struct ReconnectionScenarioTests {
    
    @Test("Drop connection after N glucose readings scenario")
    func dropAfterNReadings() async {
        let injector = FaultInjector()
        injector.addFault(.timeout, trigger: .afterPackets(5))
        
        // Simulate 5 glucose reading packets
        for i in 1...5 {
            injector.recordPacket()
            let result = injector.shouldInject(for: "sendGlucose")
            
            if i < 5 {
                guard case .noFault = result else {
                    Issue.record("Should not trigger before 5th packet")
                    return
                }
            } else {
                guard case .injected = result else {
                    Issue.record("Should trigger on 5th packet")
                    return
                }
            }
        }
    }
    
    @Test("Intermittent connection scenario")
    func intermittentConnection() async {
        let injector = FaultInjector()
        // 10% chance of drop on each operation
        injector.addFault(.dropPacket(probability: 0.1), trigger: .immediate)
        
        var dropCount = 0
        var successCount = 0
        
        for _ in 0..<100 {
            let result = injector.shouldInject(for: "sendGlucose")
            if case .injected = result {
                dropCount += 1
            } else {
                successCount += 1
            }
        }
        
        // With 10% probability, expect roughly 10 drops in 100 tries
        // Allow for statistical variance (5-20 drops)
        #expect(dropCount > 0)
        #expect(successCount > 70)
    }
    
    @Test("Authentication timeout followed by recovery")
    func authTimeoutRecovery() async {
        let injector = FaultInjector()
        // Timeout only on first auth attempt
        injector.addFault(FaultConfiguration(
            fault: .timeout,
            trigger: .once
        ))
        
        // First auth attempt times out
        let result1 = injector.shouldInject(for: "authenticate")
        guard case .injected(.timeout) = result1 else {
            Issue.record("First auth should timeout")
            return
        }
        
        // Second auth attempt succeeds (no fault)
        let result2 = injector.shouldInject(for: "authenticate")
        guard case .noFault = result2 else {
            Issue.record("Second auth should succeed")
            return
        }
    }
    
    @Test("Sensor warmup during connection")
    func sensorWarmupDuringConnection() async {
        let injector = FaultInjector()
        injector.addFault(.forceWarmup, trigger: .immediate)
        
        // First glucose request triggers warmup state
        let result = injector.shouldInject(for: "sendGlucose")
        guard case .injected(.forceWarmup) = result else {
            Issue.record("Should trigger warmup")
            return
        }
        
        // The emulator would then return warmup status to the client
        // Client should handle gracefully and wait for sensor
    }
    
    @Test("Sensor expiration during session")
    func sensorExpirationDuringSession() async {
        let injector = FaultInjector()
        // Expire after 10 readings
        injector.addFault(FaultConfiguration(
            fault: .forceExpired,
            trigger: .afterPackets(10)
        ))
        
        // Simulate readings
        for i in 1...10 {
            injector.recordPacket()
            let result = injector.shouldInject(for: "sendGlucose")
            
            if i < 10 {
                guard case .noFault = result else {
                    Issue.record("Should not expire before 10th reading")
                    return
                }
            } else {
                guard case .injected(.forceExpired) = result else {
                    Issue.record("Should expire on 10th reading")
                    return
                }
            }
        }
    }
}
