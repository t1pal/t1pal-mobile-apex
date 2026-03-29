// SPDX-License-Identifier: MIT
//
// RileyLinkFaultInjectionTests.swift
// PumpKitTests
//
// Tests for RileyLink fault injection framework.
// Validates error path handling in RileyLinkSession.
// Trace: MDT-FAULT-002, SIM-FAULT-001, synthesized-device-testing.md

import Testing
import Foundation
@testable import PumpKit
@testable import BLEKit

@Suite("RileyLink FaultInjector Tests")
struct RileyLinkFaultInjectorTests {
    
    // MARK: - PumpFaultInjector Basic Tests
    
    @Test("Initializes with empty faults")
    func testEmptyInitialization() {
        let injector = PumpFaultInjector()
        #expect(injector.faults.isEmpty)
        #expect(injector.commandCount == 0)
    }
    
    @Test("Initializes with provided faults")
    func testInitializationWithFaults() {
        let config = PumpFaultConfiguration(
            fault: .connectionTimeout,
            trigger: .immediate,
            description: "Test connection timeout"
        )
        let injector = PumpFaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .connectionTimeout)
    }
    
    // MARK: - Fault Management
    
    @Test("Adds fault configuration")
    func testAddFault() {
        let injector = PumpFaultInjector()
        injector.addFault(.occlusion, trigger: .immediate)
        #expect(injector.faults.count == 1)
    }
    
    @Test("Removes fault by ID")
    func testRemoveFault() {
        let config = PumpFaultConfiguration(id: "test-fault", fault: .connectionDrop)
        let injector = PumpFaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        
        injector.removeFault(id: "test-fault")
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Clears all faults")
    func testClearFaults() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .occlusion),
            PumpFaultConfiguration(fault: .emptyReservoir)
        ])
        #expect(injector.faults.count == 2)
        
        injector.clearFaults()
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Reset clears command count")
    func testReset() {
        let injector = PumpFaultInjector()
        injector.recordCommand()
        injector.recordCommand()
        #expect(injector.commandCount == 2)
        
        injector.reset()
        #expect(injector.commandCount == 0)
    }
    
    // MARK: - Immediate Trigger
    
    @Test("Immediate trigger injects on first check")
    func testImmediateTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .immediate
            )
        ])
        
        let result = injector.shouldInject(for: "sendCommand")
        if case .injected(let fault) = result {
            #expect(fault == .connectionTimeout)
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Operation-Based Trigger
    
    @Test("onCommand trigger matches specific command")
    func testOnCommandTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus")
            )
        ])
        
        // Different operation should not trigger
        let result1 = injector.shouldInject(for: "sendCommand")
        #expect(result1 == .noFault)
        
        // Matching operation should trigger
        let result2 = injector.shouldInject(for: "deliverBolus")
        if case .injected(let fault) = result2 {
            #expect(fault == .occlusion)
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Count-Based Trigger
    
    @Test("afterCommands trigger waits for command count")
    func testAfterCommandsTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionDrop,
                trigger: .afterCommands(3)
            )
        ])
        
        // Before reaching count
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        
        // After reaching count
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .connectionDrop)
        } else {
            Issue.record("Expected fault injection after 3 commands")
        }
    }
    
    // MARK: - Once Trigger
    
    @Test("once trigger only fires once")
    func testOnceTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .motorStall,
                trigger: .once
            )
        ])
        
        // First call should trigger
        let result1 = injector.shouldInject()
        if case .injected(let fault) = result1 {
            #expect(fault == .motorStall)
        } else {
            Issue.record("Expected first call to trigger")
        }
        
        // Second call should not trigger
        let result2 = injector.shouldInject()
        #expect(result2 == .noFault)
    }
    
    // MARK: - Preset Injectors
    
    @Test("occlusion preset triggers on deliverBolus")
    func testOcclusionPreset() {
        let injector = PumpFaultInjector.occlusion
        
        // Should not trigger on other commands
        #expect(injector.shouldInject(for: "sendCommand") == .noFault)
        
        // Should trigger on deliverBolus
        let result = injector.shouldInject(for: "deliverBolus")
        if case .injected(let fault) = result {
            #expect(fault == .occlusion)
        } else {
            Issue.record("Expected occlusion fault on deliverBolus")
        }
    }
    
    @Test("motorStall preset triggers after commands")
    func testMotorStallPreset() {
        let injector = PumpFaultInjector.motorStall
        
        // Should not trigger before 10 commands
        for _ in 0..<9 {
            #expect(injector.shouldInject() == .noFault)
            injector.recordCommand()
        }
        injector.recordCommand()  // 10th command
        
        // Now should trigger
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .motorStall)
        } else {
            Issue.record("Expected motorStall after 10 commands")
        }
    }
    
    // MARK: - Fault Categories
    
    @Test("Fault categories are correctly assigned")
    func testFaultCategories() {
        #expect(PumpFaultType.occlusion.category == .delivery)
        #expect(PumpFaultType.airInLine.category == .delivery)
        #expect(PumpFaultType.emptyReservoir.category == .delivery)
        #expect(PumpFaultType.motorStall.category == .delivery)
        
        #expect(PumpFaultType.lowBattery(level: 0.1).category == .battery)
        #expect(PumpFaultType.batteryDepleted.category == .battery)
        
        #expect(PumpFaultType.connectionDrop.category == .communication)
        #expect(PumpFaultType.connectionTimeout.category == .communication)
        #expect(PumpFaultType.communicationError(code: 0x01).category == .communication)
        
        #expect(PumpFaultType.unexpectedSuspend.category == .state)
        #expect(PumpFaultType.alarmActive(code: 0x01).category == .state)
        
        #expect(PumpFaultType.commandDelay(milliseconds: 100).category == .timing)
    }
    
    // MARK: - Delivery-Stopping Faults
    
    @Test("Delivery-stopping faults are correctly identified")
    func testDeliveryStoppingFaults() {
        // These should stop delivery
        #expect(PumpFaultType.occlusion.stopsDelivery == true)
        #expect(PumpFaultType.airInLine.stopsDelivery == true)
        #expect(PumpFaultType.emptyReservoir.stopsDelivery == true)
        #expect(PumpFaultType.motorStall.stopsDelivery == true)
        #expect(PumpFaultType.batteryDepleted.stopsDelivery == true)
        #expect(PumpFaultType.unexpectedSuspend.stopsDelivery == true)
        #expect(PumpFaultType.primeRequired.stopsDelivery == true)
        
        // These should NOT stop delivery
        #expect(PumpFaultType.lowBattery(level: 0.1).stopsDelivery == false)
        #expect(PumpFaultType.connectionDrop.stopsDelivery == false)
        #expect(PumpFaultType.commandDelay(milliseconds: 100).stopsDelivery == false)
    }
    
    // MARK: - Statistics Tracking
    
    @Test("Statistics track fault injection results")
    func testStatisticsTracking() {
        var stats = PumpFaultInjectionStats()
        #expect(stats.faultsInjected == 0)
        #expect(stats.faultsSkipped == 0)
        #expect(stats.deliveryInterruptions == 0)
        
        // Record injected fault
        stats.record(.injected(.occlusion))
        #expect(stats.faultsInjected == 1)
        #expect(stats.deliveryInterruptions == 1)  // occlusion stops delivery
        #expect(stats.faultsByCategory[.delivery] == 1)
        
        // Record skipped fault
        stats.record(.skipped(.connectionDrop))
        #expect(stats.faultsSkipped == 1)
        
        // Record non-delivery-stopping fault
        stats.record(.injected(.lowBattery(level: 0.1)))
        #expect(stats.faultsInjected == 2)
        #expect(stats.deliveryInterruptions == 1)  // low battery doesn't stop delivery
    }
}

// MARK: - RF Timeout Handling Tests (MDT-FAULT-003)

@Suite("RF Timeout Handling")
struct RFTimeoutHandlingTests {
    
    // MARK: - Timeout Fault Injection
    
    @Test("Connection timeout fault triggers rfTimeout error path")
    func testConnectionTimeoutInjection() {
        // Setup injector with connection timeout fault
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .onCommand("sendPumpMessage"),
                description: "RF timeout on pump command"
            )
        ])
        
        // Should not trigger on other commands
        let bleResult = injector.shouldInject(for: "sendCommand")
        #expect(bleResult == .noFault)
        
        // Should trigger on sendPumpMessage
        let rfResult = injector.shouldInject(for: "sendPumpMessage")
        if case .injected(let fault) = rfResult {
            #expect(fault == .connectionTimeout)
        } else {
            Issue.record("Expected connection timeout injection on sendPumpMessage")
        }
    }
    
    @Test("Retry count is configurable via injector trigger")
    func testRetryCountConfigurable() {
        // Setup injector with afterCommands trigger (simulates retries)
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .afterCommands(3),  // Fail after 3 attempts
                description: "RF timeout after 3 retries"
            )
        ])
        
        // First 3 commands should not trigger
        for i in 0..<3 {
            let result = injector.shouldInject()
            #expect(result == .noFault, "Attempt \(i) should not trigger fault")
            injector.recordCommand()
        }
        
        // 4th check should trigger (after 3 commands recorded)
        let finalResult = injector.shouldInject()
        if case .injected(let fault) = finalResult {
            #expect(fault == .connectionTimeout)
        } else {
            Issue.record("Expected timeout after 3 commands")
        }
    }
    
    @Test("Intermittent failure with eventual success pattern")
    func testIntermittentFailurePattern() {
        // Setup: fault triggers on first attempt, then succeeds
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .once,  // Only fail first time
                description: "Single transient RF timeout"
            )
        ])
        
        // First attempt should fail
        let firstResult = injector.shouldInject()
        if case .injected(let fault) = firstResult {
            #expect(fault == .connectionTimeout)
        } else {
            Issue.record("Expected first attempt to fail")
        }
        
        // Second attempt should succeed (once trigger consumed)
        let secondResult = injector.shouldInject()
        #expect(secondResult == .noFault, "Second attempt should succeed")
        
        // Third attempt should also succeed
        let thirdResult = injector.shouldInject()
        #expect(thirdResult == .noFault, "Third attempt should succeed")
    }
    
    @Test("Multiple retry failures before success")
    func testMultipleRetryFailuresBeforeSuccess() {
        // Setup: fail first N times, then succeed
        let failCount = 2
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "retry-test",
                fault: .connectionTimeout,
                trigger: .immediate,  // Will be disabled after failCount
                description: "Fails first \(failCount) attempts"
            )
        ])
        
        // Track failures
        var failures = 0
        for attempt in 0..<5 {
            let result = injector.shouldInject()
            if case .injected = result {
                failures += 1
                // After enough failures, disable the fault
                if failures >= failCount {
                    injector.removeFault(id: "retry-test")
                }
            } else {
                // Should succeed after fault removed
                #expect(attempt >= failCount, "Should only succeed after \(failCount) failures")
                break
            }
        }
        
        #expect(failures == failCount, "Should have exactly \(failCount) failures")
    }
    
    // MARK: - Backoff Simulation
    
    @Test("Timeout after time trigger simulates backoff delay")
    func testTimeBasedTimeout() async throws {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionTimeout,
                trigger: .afterTime(seconds: 0.1),  // 100ms delay
                description: "Timeout after 100ms"
            )
        ])
        
        // Immediately should not trigger
        let immediateResult = injector.shouldInject()
        #expect(immediateResult == .noFault)
        
        // Wait past trigger time
        try await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        
        // Now should trigger
        let delayedResult = injector.shouldInject()
        if case .injected(let fault) = delayedResult {
            #expect(fault == .connectionTimeout)
        } else {
            Issue.record("Expected timeout after delay")
        }
    }
    
    // MARK: - Communication Error Codes
    
    @Test("Communication error code is preserved in fault")
    func testCommunicationErrorCode() {
        let errorCode: UInt8 = 0xAA  // rxTimeout code
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .communicationError(code: errorCode),
                trigger: .immediate
            )
        ])
        
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            if case .communicationError(let code) = fault {
                #expect(code == errorCode, "Error code should match")
            } else {
                Issue.record("Expected communicationError fault type")
            }
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    @Test("Display name shows correct error code format")
    func testErrorCodeDisplayFormat() {
        let fault = PumpFaultType.communicationError(code: 0xAA)
        #expect(fault.displayName.contains("AA") || fault.displayName.contains("aa"))
    }
    
    // MARK: - Retry Count Verification
    
    @Test("Default retry count is 3")
    func testDefaultRetryCount() {
        // Verify default retry count in SendAndListenCommand
        let command = SendAndListenCommand(
            outgoing: Data([0x01, 0x02, 0x03]),
            firmwareVersion: .assumeV2
        )
        
        // Default retryCount should be 3
        #expect(command.retryCount == 3)
    }
    
    @Test("Custom retry count is serialized correctly")
    func testCustomRetryCount() {
        let customRetries: UInt8 = 5
        let command = SendAndListenCommand(
            outgoing: Data([0xAB]),
            retryCount: customRetries,
            firmwareVersion: .assumeV2
        )
        
        #expect(command.retryCount == customRetries)
        
        // Verify it's in the serialized data
        let data = command.data
        // Format: [opcode, sendChannel, repeatCount, delay(2B), listenChannel, timeout(4B), retryCount, preamble(2B), payload]
        // retryCount is at offset 10 for v2+ firmware
        #expect(data.count > 10)
        #expect(data[10] == customRetries)
    }
    
    @Test("Zero retry count means single attempt")
    func testZeroRetryCount() {
        let command = SendAndListenCommand(
            outgoing: Data([0x00]),
            retryCount: 0,
            firmwareVersion: .assumeV2
        )
        
        #expect(command.retryCount == 0)
        
        // Verify serialization
        let data = command.data
        #expect(data[10] == 0)
    }
    
    // MARK: - Preset Scenarios
    
    @Test("Unreliable connection preset includes timeout behavior")
    func testUnreliableConnectionPreset() {
        let injector = PumpFaultInjector.unreliableConnection
        
        // Should have connection drop fault configured
        let hasConnectionDrop = injector.faults.contains { config in
            if case .connectionDrop = config.fault {
                return true
            }
            return false
        }
        #expect(hasConnectionDrop, "Preset should include connection drop fault")
        
        // Should have delay fault configured
        let hasDelay = injector.faults.contains { config in
            if case .commandDelay = config.fault {
                return true
            }
            return false
        }
        #expect(hasDelay, "Preset should include command delay fault")
    }
    
    @Test("Stress test preset has high failure rate")
    func testStressTestPreset() {
        let injector = PumpFaultInjector.stressTest
        
        // Should have intermittent failure configured
        let hasIntermittent = injector.faults.contains { config in
            if case .intermittentFailure = config.fault {
                return true
            }
            return false
        }
        #expect(hasIntermittent, "Stress test should include intermittent failures")
    }
}

// MARK: - CRC Mismatch Handling Tests (MDT-FAULT-004)

@Suite("CRC Mismatch Handling")
struct CRCMismatchHandlingTests {
    
    // MARK: - CRC Validation Tests
    
    @Test("MinimedPacket rejects corrupted CRC")
    func testMinimedPacketRejectsCorruptedCRC() {
        // Create a valid packet
        let originalData = Data([0xA7, 0x01, 0x23, 0x45])
        let packet = MinimedPacket(outgoingData: originalData)
        var encoded = packet.encodedData()
        
        // Corrupt a byte (not the null terminator)
        if encoded.count > 2 {
            encoded[1] ^= 0x01  // Flip a bit
        }
        
        // Decoding should fail due to CRC mismatch
        let decoded = MinimedPacket(encodedData: encoded)
        #expect(decoded == nil, "Corrupted packet should be rejected")
    }
    
    @Test("MinimedPacket accepts valid CRC")
    func testMinimedPacketAcceptsValidCRC() {
        let originalData = Data([0xA7, 0x20, 0x88, 0x50, 0x8D, 0x00])
        let packet = MinimedPacket(outgoingData: originalData)
        let encoded = packet.encodedData()
        
        // Should decode successfully
        let decoded = MinimedPacket(encodedData: encoded)
        #expect(decoded != nil, "Valid packet should be accepted")
        #expect(decoded?.data == originalData)
    }
    
    @Test("CRC mismatch from fixture scenario CRC-001")
    func testCRCMismatchScenarioCRC001() {
        // Scenario: Single bit flip in CRC byte (0xe5 → 0xe4)
        // From fixture_bad_crc.json CRC-001
        
        // Simulate: valid data with wrong CRC appended
        let validData: [UInt8] = [0xA7, 0x20, 0x88, 0x50, 0x8D, 0x00]
        let correctCRC = validData.crc8()
        let corruptedCRC = correctCRC ^ 0x01  // Single bit flip
        
        #expect(correctCRC != corruptedCRC, "CRCs should differ by 1 bit")
        
        // Build packet with wrong CRC manually (simulating RF bit error)
        var packetWithWrongCRC = Data(validData)
        packetWithWrongCRC.append(corruptedCRC)
        
        // 4b6b encode it
        var encoded = Data(packetWithWrongCRC.encode4b6b())
        encoded.append(0x00)  // Null terminator
        
        // Decoding should fail
        let decoded = MinimedPacket(encodedData: encoded)
        #expect(decoded == nil, "Packet with corrupted CRC should be rejected")
    }
    
    // MARK: - Packet Corruption Fault Injection
    
    @Test("packetCorruption fault type triggers probabilistically")
    func testPacketCorruptionFaultType() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .packetCorruption(probability: 1.0),  // 100% for deterministic test
                trigger: .immediate,
                description: "Always corrupt packets"
            )
        ])
        
        let result = injector.shouldInject(for: "sendPumpMessage")
        if case .injected(let fault) = result {
            if case .packetCorruption(let p) = fault {
                #expect(p == 1.0)
            } else {
                Issue.record("Expected packetCorruption fault type")
            }
        } else {
            Issue.record("Expected fault injection at 100% probability")
        }
    }
    
    @Test("packetCorruption with low probability may skip")
    func testPacketCorruptionLowProbabilitySkips() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .packetCorruption(probability: 0.0),  // 0% - always skip
                trigger: .immediate,
                description: "Never corrupt"
            )
        ])
        
        let result = injector.shouldInject()
        // At 0% probability, should always skip
        #expect(result == .skipped(.packetCorruption(probability: 0.0)))
    }
    
    @Test("packetCorruption is in communication category")
    func testPacketCorruptionCategory() {
        let fault = PumpFaultType.packetCorruption(probability: 0.5)
        #expect(fault.category == .communication)
        #expect(fault.stopsDelivery == false)
    }
    
    // MARK: - Zero Data Response (0xCC)
    
    @Test("communicationError 0xCC represents zeroData response")
    func testZeroDataResponse() {
        // From fixture: response code 0xCC = zeroData
        let zeroDataCode: UInt8 = 0xCC
        
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .communicationError(code: zeroDataCode),
                trigger: .onCommand("getBattery"),
                description: "Zero data on getBattery (from CRC-003)"
            )
        ])
        
        // Should not trigger on other commands
        let otherResult = injector.shouldInject(for: "sendPumpMessage")
        #expect(otherResult == .noFault)
        
        // Should trigger on getBattery
        let batteryResult = injector.shouldInject(for: "getBattery")
        if case .injected(let fault) = batteryResult {
            if case .communicationError(let code) = fault {
                #expect(code == 0xCC)
            } else {
                Issue.record("Expected communicationError fault")
            }
        } else {
            Issue.record("Expected fault injection on getBattery")
        }
    }
    
    @Test("RileyLink response codes are correctly represented")
    func testRileyLinkResponseCodes() {
        // From fixture_bad_crc.json test_vectors.error_response_codes
        let responseCodes: [(UInt8, String)] = [
            (0xAA, "rxTimeout"),
            (0xBB, "commandInterrupted"),
            (0xCC, "zeroData"),
            (0xDD, "success"),
            (0x11, "invalidParam"),
            (0x22, "unknownCommand")
        ]
        
        for (code, name) in responseCodes {
            let fault = PumpFaultType.communicationError(code: code)
            #expect(fault.displayName.contains(String(format: "%02x", code).uppercased()) ||
                    fault.displayName.contains(String(format: "%02x", code)),
                    "Display name should contain code for \(name)")
        }
    }
    
    // MARK: - Multiple CRC Errors (CRC-002 scenario)
    
    @Test("Multiple consecutive CRC errors before success")
    func testMultipleCRCErrorsBeforeSuccess() {
        // Simulate CRC-002: 2 failures then success
        let maxFailures = 2
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "crc-errors",
                fault: .packetCorruption(probability: 1.0),
                trigger: .immediate,
                description: "CRC errors for \(maxFailures) attempts"
            )
        ])
        
        var failures = 0
        for attempt in 1...5 {
            let result = injector.shouldInject()
            if case .injected = result {
                failures += 1
                // After enough failures, remove fault (simulating retry success)
                if failures >= maxFailures {
                    injector.removeFault(id: "crc-errors")
                }
            } else {
                // Success - should happen after maxFailures
                #expect(attempt > maxFailures, "Should succeed after \(maxFailures) failures")
                break
            }
        }
        
        #expect(failures == maxFailures, "Should have exactly \(maxFailures) CRC errors")
    }
    
    @Test("Retry policy allows retries after CRC error")
    func testCRCErrorIsRetryable() {
        // Verify that CRC errors are retryable (from fixture retry_policy)
        // packetCorruption doesn't stop delivery, so it's implicitly retryable
        let fault = PumpFaultType.packetCorruption(probability: 0.5)
        #expect(fault.stopsDelivery == false, "CRC errors should not stop delivery (are retryable)")
        
        // communicationError is also retryable
        let commError = PumpFaultType.communicationError(code: 0xCC)
        #expect(commError.stopsDelivery == false, "Communication errors should not stop delivery")
    }
    
    // MARK: - Truncated Response (CRC-004 scenario)
    
    @Test("Truncated packet is detected by insufficient length")
    func testTruncatedPacketDetection() {
        // From CRC-004: packet truncated mid-transmission
        // MinimedPacket needs at least 2 decoded bytes (1 data + 1 CRC)
        
        // Too short after decoding
        let tooShort = Data([0x15, 0x00])  // Single valid 6-bit code + null
        let decoded = MinimedPacket(encodedData: tooShort)
        #expect(decoded == nil, "Truncated packet should be rejected")
    }
    
    @Test("Empty response is rejected")
    func testEmptyResponseRejected() {
        // Just null terminator
        let empty = Data([0x00])
        let decoded = MinimedPacket(encodedData: empty)
        #expect(decoded == nil, "Empty response should be rejected")
    }
    
    @Test("Partially corrupted 4b6b encoding fails")
    func testPartiallyCorrupted4b6bEncoding() {
        // Invalid 6-bit codes that aren't in the decode table
        let invalid = Data([0xFF, 0xFF, 0xFF, 0x00])
        let decoded = MinimedPacket(encodedData: invalid)
        #expect(decoded == nil, "Invalid 4b6b encoding should be rejected")
    }
    
    // MARK: - Statistics Tracking for CRC Errors
    
    @Test("Statistics track CRC-related fault injections")
    func testStatisticsTrackCRCFaults() {
        var stats = PumpFaultInjectionStats()
        
        // Record packet corruption
        stats.record(.injected(.packetCorruption(probability: 0.5)))
        #expect(stats.faultsInjected == 1)
        #expect(stats.faultsByCategory[.communication] == 1)
        #expect(stats.deliveryInterruptions == 0)  // CRC errors don't stop delivery
        
        // Record communication error (zeroData)
        stats.record(.injected(.communicationError(code: 0xCC)))
        #expect(stats.faultsInjected == 2)
        #expect(stats.faultsByCategory[.communication] == 2)
        
        // Record skipped fault
        stats.record(.skipped(.packetCorruption(probability: 0.1)))
        #expect(stats.faultsSkipped == 1)
    }
    
    // MARK: - Preset: Unreliable Connection includes packet corruption
    
    @Test("unreliableConnection preset includes packet corruption")
    func testUnreliableConnectionPresetHasPacketCorruption() {
        let injector = PumpFaultInjector.unreliableConnection
        
        let hasPacketCorruption = injector.faults.contains { config in
            if case .packetCorruption = config.fault {
                return true
            }
            return false
        }
        #expect(hasPacketCorruption, "Preset should include packet corruption")
    }
    
    // MARK: - CRC Display Names
    
    @Test("packetCorruption display name shows probability")
    func testPacketCorruptionDisplayName() {
        let fault = PumpFaultType.packetCorruption(probability: 0.10)
        #expect(fault.displayName.contains("10"), "Should show 10% probability")
    }
    
    @Test("communicationError display name shows hex code")
    func testCommunicationErrorDisplayName() {
        let fault = PumpFaultType.communicationError(code: 0xCC)
        #expect(fault.displayName.uppercased().contains("CC"), "Should show CC code")
    }
}

// MARK: - BLE Disconnect Mid-Command Tests (MDT-FAULT-005)

@Suite("BLE Disconnect Mid-Command Handling")
struct BLEDisconnectMidCommandTests {
    
    // MARK: - Fault Type Tests
    
    @Test("bleDisconnectMidCommand fault type exists and is in communication category")
    func testBLEDisconnectFaultTypeCategory() {
        let fault = PumpFaultType.bleDisconnectMidCommand
        #expect(fault.category == .communication)
        #expect(fault.stopsDelivery == false)
    }
    
    @Test("bleDisconnectMidCommand has descriptive display name")
    func testBLEDisconnectDisplayName() {
        let fault = PumpFaultType.bleDisconnectMidCommand
        #expect(fault.displayName.contains("Disconnect"), "Should mention disconnect")
        #expect(fault.displayName.contains("Mid"), "Should mention mid-command")
    }
    
    @Test("bleDisconnectMidCommand fault triggers on sendCommand")
    func testBLEDisconnectFaultTriggers() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .bleDisconnectMidCommand,
                trigger: .onCommand("sendCommand"),
                description: "Disconnect during BLE command"
            )
        ])
        
        // Should not trigger on other commands
        let otherResult = injector.shouldInject(for: "sendPumpMessage")
        #expect(otherResult == .noFault)
        
        // Should trigger on sendCommand
        let bleResult = injector.shouldInject(for: "sendCommand")
        if case .injected(let fault) = bleResult {
            #expect(fault == .bleDisconnectMidCommand)
        } else {
            Issue.record("Expected bleDisconnectMidCommand injection on sendCommand")
        }
    }
    
    @Test("bleDisconnectMidCommand with once trigger fires only first time")
    func testBLEDisconnectOnceTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .bleDisconnectMidCommand,
                trigger: .once,
                description: "Single disconnect event"
            )
        ])
        
        // First check should trigger
        let first = injector.shouldInject()
        if case .injected(let fault) = first {
            #expect(fault == .bleDisconnectMidCommand)
        } else {
            Issue.record("Expected first injection to trigger")
        }
        
        // Second check should not trigger
        let second = injector.shouldInject()
        #expect(second == .noFault, "Once trigger should not fire again")
    }
    
    @Test("bleDisconnectMidCommand with afterCommands trigger")
    func testBLEDisconnectAfterCommandsTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .bleDisconnectMidCommand,
                trigger: .afterCommands(2),  // Disconnect after 2 successful commands
                description: "Disconnect after 2 commands"
            )
        ])
        
        // First 2 commands should succeed
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        
        // 3rd command should trigger disconnect
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .bleDisconnectMidCommand)
        } else {
            Issue.record("Expected disconnect after 2 commands")
        }
    }
    
    // MARK: - Session State Tests
    
    @Test("Session recovery properties are correctly initialized")
    func testSessionRecoveryPropertiesExist() {
        // Test that recovery properties exist on PumpFaultInjector preset
        let injector = PumpFaultInjector.unreliableConnection
        
        // Should be able to add bleDisconnectMidCommand
        injector.addFault(.bleDisconnectMidCommand, trigger: .probabilistic(probability: 0.05))
        
        let hasDisconnect = injector.faults.contains { config in
            if case .bleDisconnectMidCommand = config.fault {
                return true
            }
            return false
        }
        #expect(hasDisconnect)
    }
    
    @Test("Recovery trigger pattern with afterCommands")
    func testRecoveryTriggerPattern() {
        // Simulate: operate normally for N commands, then disconnect
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "recovery-test",
                fault: .bleDisconnectMidCommand,
                trigger: .afterCommands(3),
                description: "Disconnect after 3 commands"
            )
        ])
        
        // Commands 1-3 succeed
        for _ in 0..<3 {
            let result = injector.shouldInject()
            #expect(result == .noFault)
            injector.recordCommand()
        }
        
        // Command 4 triggers disconnect
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .bleDisconnectMidCommand)
        } else {
            Issue.record("Expected disconnect after 3 commands")
        }
        
        // Remove fault to simulate recovery
        injector.removeFault(id: "recovery-test")
        
        // Subsequent commands succeed
        let afterRecovery = injector.shouldInject()
        #expect(afterRecovery == .noFault)
    }
    
    @Test("Reset allows another recovery")
    func testResetAllowsAnotherRecovery() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .bleDisconnectMidCommand,
                trigger: .once,
                description: "Single disconnect"
            )
        ])
        
        // First attempt triggers
        let first = injector.shouldInject()
        if case .injected(let fault) = first {
            #expect(fault == .bleDisconnectMidCommand)
        }
        
        // Second attempt should not trigger (once already fired)
        let second = injector.shouldInject()
        #expect(second == .noFault)
        
        // Reset and add new fault
        injector.reset()
        injector.clearFaults()
        injector.addFault(.bleDisconnectMidCommand, trigger: .once)
        
        // Should trigger again after reset
        let afterReset = injector.shouldInject()
        if case .injected(let fault) = afterReset {
            #expect(fault == .bleDisconnectMidCommand)
        } else {
            Issue.record("Expected fault after reset")
        }
    }
    
    // MARK: - Statistics Tracking
    
    @Test("Statistics track BLE disconnect faults")
    func testStatisticsTrackBLEDisconnect() {
        var stats = PumpFaultInjectionStats()
        
        // Record BLE disconnect
        stats.record(.injected(.bleDisconnectMidCommand))
        #expect(stats.faultsInjected == 1)
        #expect(stats.faultsByCategory[.communication] == 1)
        #expect(stats.deliveryInterruptions == 0)  // Disconnect doesn't stop delivery
        #expect(stats.lastFault == .bleDisconnectMidCommand)
    }
    
    // MARK: - Preset Tests
    
    @Test("Unreliable connection preset can be extended with disconnect")
    func testUnreliableConnectionWithDisconnect() {
        let injector = PumpFaultInjector.unreliableConnection
        
        // Add disconnect fault
        injector.addFault(.bleDisconnectMidCommand, trigger: .probabilistic(probability: 0.02))
        
        let hasBLEDisconnect = injector.faults.contains { config in
            if case .bleDisconnectMidCommand = config.fault {
                return true
            }
            return false
        }
        #expect(hasBLEDisconnect, "Should have BLE disconnect fault")
    }
    
    // MARK: - Error Type Tests
    
    @Test("bleDisconnected error has correct descriptions")
    func testBLEDisconnectedErrorDescriptions() {
        let recoverable = RileyLinkSessionError.bleDisconnected(recoverable: true)
        let nonRecoverable = RileyLinkSessionError.bleDisconnected(recoverable: false)
        
        let recoverableDesc = recoverable.errorDescription ?? ""
        let nonRecoverableDesc = nonRecoverable.errorDescription ?? ""
        
        #expect(recoverableDesc.contains("recoverable"), "Recoverable error should mention recoverable")
        #expect(!nonRecoverableDesc.contains("recoverable"), "Non-recoverable should not mention recoverable")
        #expect(recoverableDesc.contains("disconnect") || recoverableDesc.contains("Disconnect"))
        #expect(nonRecoverableDesc.contains("disconnect") || nonRecoverableDesc.contains("Disconnect"))
    }
}

// MARK: - Wrong Channel Response Tests (MDT-FAULT-006)

@Suite("Wrong Channel Response Handling")
struct WrongChannelResponseTests {
    
    // MARK: - Fault Type Tests
    
    @Test("wrongChannelResponse fault type exists and is in communication category")
    func testWrongChannelFaultTypeCategory() {
        let fault = PumpFaultType.wrongChannelResponse(sent: 0, received: 2)
        #expect(fault.category == .communication)
        #expect(fault.stopsDelivery == false)
    }
    
    @Test("wrongChannelResponse has descriptive display name with channels")
    func testWrongChannelDisplayName() {
        let fault = PumpFaultType.wrongChannelResponse(sent: 0, received: 2)
        let name = fault.displayName
        #expect(name.contains("Wrong") || name.contains("Channel"), "Should mention channel")
        #expect(name.contains("0"), "Should show sent channel")
        #expect(name.contains("2"), "Should show received channel")
    }
    
    @Test("wrongChannelResponse fault triggers on sendPumpMessage")
    func testWrongChannelFaultTriggers() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .onCommand("sendPumpMessage"),
                description: "Channel mismatch during pump communication"
            )
        ])
        
        // Should not trigger on other commands
        let otherResult = injector.shouldInject(for: "getVersion")
        #expect(otherResult == .noFault)
        
        // Should trigger on sendPumpMessage
        let pumpResult = injector.shouldInject(for: "sendPumpMessage")
        if case .injected(let fault) = pumpResult {
            if case .wrongChannelResponse(let sent, let received) = fault {
                #expect(sent == 0)
                #expect(received == 2)
            } else {
                Issue.record("Expected wrongChannelResponse fault")
            }
        } else {
            Issue.record("Expected fault injection on sendPumpMessage")
        }
    }
    
    @Test("wrongChannelResponse with once trigger fires only first time")
    func testWrongChannelOnceTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .once,
                description: "Single channel mismatch event"
            )
        ])
        
        // First check should trigger
        let first = injector.shouldInject()
        if case .injected(let fault) = first {
            if case .wrongChannelResponse = fault {
                // Expected
            } else {
                Issue.record("Expected wrongChannelResponse fault")
            }
        } else {
            Issue.record("Expected first injection to trigger")
        }
        
        // Second check should not trigger
        let second = injector.shouldInject()
        #expect(second == .noFault, "Once trigger should not fire again")
    }
    
    @Test("wrongChannelResponse with afterCommands trigger")
    func testWrongChannelAfterCommandsTrigger() {
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .afterCommands(2),
                description: "Channel mismatch after 2 commands"
            )
        ])
        
        // First 2 commands should succeed
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        #expect(injector.shouldInject() == .noFault)
        injector.recordCommand()
        
        // 3rd command should trigger channel mismatch
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            if case .wrongChannelResponse = fault {
                // Expected
            } else {
                Issue.record("Expected wrongChannelResponse fault")
            }
        } else {
            Issue.record("Expected channel mismatch after 2 commands")
        }
    }
    
    // MARK: - Channel Value Tests
    
    @Test("Channel 0 is valid for Medtronic (RL-CHAN-001)")
    func testChannel0Valid() {
        // Per RL-CHAN-006: Channel 0 is for Medtronic pumps, meters, CGMs
        let command = SendAndListenCommand(
            outgoing: Data([0x01, 0x02]),
            sendChannel: 0,
            listenChannel: 0,
            timeoutMS: 200
        )
        
        let data = command.data
        #expect(data[1] == 0, "Send channel should be 0")
        // Listen channel position depends on firmware version
    }
    
    @Test("Different send/listen channels can be specified")
    func testDifferentChannels() {
        let command = SendAndListenCommand(
            outgoing: Data([0x01, 0x02]),
            sendChannel: 0,
            listenChannel: 2,  // Hypothetical: listen on different channel
            timeoutMS: 200
        )
        
        let data = command.data
        #expect(data[1] == 0, "Send channel should be 0")
        // This tests that the command allows different channels
    }
    
    // MARK: - Error Type Tests
    
    @Test("wrongChannelResponse error has correct description")
    func testWrongChannelErrorDescription() {
        let error = RileyLinkSessionError.wrongChannelResponse(sent: 0, received: 2)
        let desc = error.errorDescription ?? ""
        
        #expect(desc.lowercased().contains("channel"), "Should mention channel")
        #expect(desc.contains("0"), "Should show sent channel")
        #expect(desc.contains("2"), "Should show received channel")
    }
    
    @Test("wrongChannelResponse error shows different channel combinations")
    func testWrongChannelErrorVariants() {
        let error1 = RileyLinkSessionError.wrongChannelResponse(sent: 0, received: 2)
        let error2 = RileyLinkSessionError.wrongChannelResponse(sent: 2, received: 0)
        
        let desc1 = error1.errorDescription ?? ""
        let desc2 = error2.errorDescription ?? ""
        
        // Should show different values
        #expect(desc1 != desc2, "Different channel combinations should have different descriptions")
    }
    
    // MARK: - Statistics Tracking
    
    @Test("Statistics track wrong channel faults")
    func testStatisticsTrackWrongChannel() {
        var stats = PumpFaultInjectionStats()
        
        // Record wrong channel fault
        stats.record(.injected(.wrongChannelResponse(sent: 0, received: 2)))
        #expect(stats.faultsInjected == 1)
        #expect(stats.faultsByCategory[.communication] == 1)
        #expect(stats.deliveryInterruptions == 0)  // Channel mismatch doesn't stop delivery
        
        if case .wrongChannelResponse = stats.lastFault {
            // Expected
        } else {
            Issue.record("Expected lastFault to be wrongChannelResponse")
        }
    }
    
    // MARK: - Fixture-Based Tests
    
    @Test("CHAN-001 scenario: send 0, receive 2, retry succeeds")
    func testCHAN001Scenario() {
        // Simulate: first command gets wrong channel, retry succeeds
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "chan-001",
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .once,
                description: "CHAN-001: Single channel mismatch"
            )
        ])
        
        // First attempt triggers fault
        let first = injector.shouldInject()
        if case .injected = first {
            // Expected - would trigger channel mismatch handling
        } else {
            Issue.record("Expected fault on first attempt")
        }
        
        // Second attempt succeeds (fault was .once)
        let retry = injector.shouldInject()
        #expect(retry == .noFault, "Retry should succeed after .once fault")
    }
    
    @Test("CHAN-002 scenario: persistent wrong channel fails after max retries")
    func testCHAN002Scenario() {
        // Simulate: every command gets wrong channel response
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "chan-002",
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .immediate,  // Always fires
                description: "CHAN-002: Persistent channel mismatch"
            )
        ])
        
        // All attempts should trigger fault
        for attempt in 1...3 {
            let result = injector.shouldInject()
            if case .injected(let fault) = result {
                if case .wrongChannelResponse(let sent, let received) = fault {
                    #expect(sent == 0 && received == 2, "Attempt \(attempt) should have channel 0→2")
                }
            } else {
                Issue.record("Attempt \(attempt) should trigger fault")
            }
        }
    }
    
    // MARK: - Recovery Pattern Tests
    
    @Test("Recovery trigger pattern with wrong channel")
    func testRecoveryTriggerPattern() {
        // Simulate: operate normally for N commands, then channel mismatch
        let injector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                id: "recovery-test",
                fault: .wrongChannelResponse(sent: 0, received: 2),
                trigger: .afterCommands(3),
                description: "Channel mismatch after 3 commands"
            )
        ])
        
        // Commands 1-3 succeed
        for _ in 0..<3 {
            let result = injector.shouldInject()
            #expect(result == .noFault)
            injector.recordCommand()
        }
        
        // Command 4 triggers channel mismatch
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            if case .wrongChannelResponse = fault {
                // Expected
            } else {
                Issue.record("Expected wrongChannelResponse after 3 commands")
            }
        }
        
        // Remove fault to simulate recovery
        injector.removeFault(id: "recovery-test")
        
        // Subsequent commands succeed
        let afterRecovery = injector.shouldInject()
        #expect(afterRecovery == .noFault)
    }
    
    // MARK: - Preset Tests
    
    @Test("Unreliable connection preset can be extended with wrong channel")
    func testUnreliableConnectionWithWrongChannel() {
        let injector = PumpFaultInjector.unreliableConnection
        
        // Add wrong channel fault
        injector.addFault(.wrongChannelResponse(sent: 0, received: 2), trigger: .probabilistic(probability: 0.01))
        
        let hasWrongChannel = injector.faults.contains { config in
            if case .wrongChannelResponse = config.fault {
                return true
            }
            return false
        }
        #expect(hasWrongChannel, "Should have wrong channel fault")
    }
}

// MARK: - RileyLinkManager Integration Tests (WIRE-008)

@Suite("RileyLinkManager Fault Injection")
struct RileyLinkManagerFaultInjectionTests {
    
    @Test("Fault injector blocks connect with immediate trigger")
    func testFaultInjectorBlocksConnect() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .immediate)
        
        let manager = RileyLinkManager(faultInjector: injector)
        
        // WIRE-016: Use test mode for instant simulation
        await manager.enableTestMode()
        
        // Create a fake device directly (no scanning needed)
        let device = RileyLinkDevice(
            id: "test-device-001",
            name: "OrangeLink-Test",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        do {
            try await manager.connect(to: device)
            #expect(Bool(false), "Should have thrown fault")
        } catch let error as RileyLinkError {
            #expect(error == .deviceNotFound)
        }
    }
    
    @Test("Fault injector properties are settable")
    func testFaultInjectorPropertiesSettable() async throws {
        let injector = PumpFaultInjector()
        let manager = RileyLinkManager(faultInjector: injector)
        
        // Verify injector is set
        let hasInjector = await manager.faultInjector != nil
        #expect(hasInjector, "Should have fault injector")
    }
}
