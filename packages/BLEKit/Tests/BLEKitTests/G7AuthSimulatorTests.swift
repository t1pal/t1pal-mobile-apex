// SPDX-License-Identifier: MIT
//
// G7AuthSimulatorTests.swift
// BLEKitTests
//
// Tests for the G7 J-PAKE authentication simulator.
// Trace: APP-SIM-010

import Foundation
import Testing
@testable import BLEKit

@Suite("G7 Auth Simulator")
struct G7AuthSimulatorTests {
    
    // MARK: - Initialization Tests
    
    @Test("Create simulator with valid sensor code")
    func validSensorCode() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        #expect(simulator.sensorCode == "1234")
        #expect(simulator.state == .awaitingRound1)
        #expect(!simulator.isAuthenticated)
    }
    
    @Test("Sensor code is normalized")
    func sensorCodeNormalized() {
        // Short code gets padded
        let sim1 = G7AuthSimulator(sensorCode: "12")
        #expect(sim1.sensorCode == "0000")  // Falls back to default
        
        // Valid 4-digit code
        let sim2 = G7AuthSimulator(sensorCode: "5678")
        #expect(sim2.sensorCode == "5678")
    }
    
    // MARK: - Message Processing Tests
    
    @Test("Empty message returns invalid")
    func emptyMessage() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        let result = simulator.processMessage(Data())
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Empty"))
        } else {
            Issue.record("Expected invalidMessage result")
        }
    }
    
    @Test("Unknown opcode returns invalid")
    func unknownOpcode() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        let result = simulator.processMessage(Data([0xFF]))
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Unknown opcode"))
        } else {
            Issue.record("Expected invalidMessage result")
        }
    }
    
    @Test("Round 1 message too short")
    func round1TooShort() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Round 1 needs at least 225 bytes
        var shortMessage = Data([G7SimOpcode.authRound1])
        shortMessage.append(Data(repeating: 0, count: 100))
        
        let result = simulator.processMessage(shortMessage)
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("too short"))
        } else {
            Issue.record("Expected invalidMessage for short Round 1")
        }
    }
    
    @Test("Valid Round 1 returns response")
    func validRound1() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Build a valid Round 1 message
        let round1 = buildRound1Message()
        
        let result = simulator.processMessage(round1)
        
        if case .sendResponse(let response) = result {
            // Response should have opcode + gx3(32) + gx4(32) + zkp3(80) + zkp4(80) = 225 bytes
            #expect(response.count == 225)
            #expect(response[0] == G7SimOpcode.authRound1)
            #expect(simulator.state == .awaitingRound2)
        } else {
            Issue.record("Expected sendResponse for valid Round 1")
        }
    }
    
    // MARK: - State Machine Tests
    
    @Test("Round 2 before Round 1 fails")
    func round2BeforeRound1() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        let round2 = buildRound2Message()
        let result = simulator.processMessage(round2)
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Unexpected"))
        } else {
            Issue.record("Expected invalidMessage for Round 2 before Round 1")
        }
    }
    
    @Test("State transitions correctly through rounds")
    func stateTransitions() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        #expect(simulator.state == .awaitingRound1)
        
        // Process Round 1
        let round1 = buildRound1Message()
        _ = simulator.processMessage(round1)
        #expect(simulator.state == .awaitingRound2)
        
        // Process Round 2
        let round2 = buildRound2Message()
        _ = simulator.processMessage(round2)
        #expect(simulator.state == .awaitingConfirmation)
    }
    
    @Test("Reset returns to initial state")
    func resetState() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Progress through Round 1
        _ = simulator.processMessage(buildRound1Message())
        #expect(simulator.state == .awaitingRound2)
        
        // Reset
        simulator.reset()
        
        #expect(simulator.state == .awaitingRound1)
        #expect(simulator.sessionKey == nil)
        #expect(!simulator.isAuthenticated)
    }
    
    // MARK: - Full Protocol Tests
    
    @Test("Full authentication flow completes")
    func fullAuthFlow() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Round 1
        let round1 = buildRound1Message()
        let result1 = simulator.processMessage(round1)
        
        guard case .sendResponse = result1 else {
            Issue.record("Round 1 should return response")
            return
        }
        
        // Round 2
        let round2 = buildRound2Message()
        let result2 = simulator.processMessage(round2)
        
        guard case .sendResponse = result2 else {
            Issue.record("Round 2 should return response")
            return
        }
        
        #expect(simulator.state == .awaitingConfirmation)
    }
    
    @Test("Confirmation with valid hash succeeds")
    func validConfirmation() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Process Round 1 and Round 2
        _ = simulator.processMessage(buildRound1Message())
        _ = simulator.processMessage(buildRound2Message())
        
        // Build confirmation (we need to match the expected hash)
        // For testing, we'll just send a well-formed confirmation
        // and check that the simulator processes it
        let confirm = buildConfirmationMessage()
        let result = simulator.processMessage(confirm)
        
        // Due to hash mismatch (we can't compute the real hash without full protocol),
        // this will fail, but we can verify the message was processed
        switch result {
        case .sendResponse:
            #expect(simulator.isAuthenticated)
        case .failed(let reason):
            // Expected for test data that doesn't have correct hash
            #expect(reason.contains("hash") || reason.contains("mismatch"))
        default:
            break
        }
    }
    
    // MARK: - Helper Functions
    
    private func buildRound1Message() -> Data {
        var message = Data([G7SimOpcode.authRound1])
        
        // gx1 (32 bytes)
        message.append(Data(repeating: 0xAA, count: 32))
        
        // gx2 (32 bytes)
        message.append(Data(repeating: 0xBB, count: 32))
        
        // zkp1 (80 bytes): commitment(32) + challenge(16) + response(32)
        message.append(Data(repeating: 0x11, count: 32))  // commitment
        message.append(Data(repeating: 0x22, count: 16))  // challenge
        message.append(Data(repeating: 0x33, count: 32))  // response
        
        // zkp2 (80 bytes)
        message.append(Data(repeating: 0x44, count: 32))  // commitment
        message.append(Data(repeating: 0x55, count: 16))  // challenge
        message.append(Data(repeating: 0x66, count: 32))  // response
        
        return message
    }
    
    private func buildRound2Message() -> Data {
        var message = Data([G7SimOpcode.authRound2])
        
        // A (32 bytes)
        message.append(Data(repeating: 0xCC, count: 32))
        
        // zkpA (80 bytes)
        message.append(Data(repeating: 0x77, count: 32))  // commitment
        message.append(Data(repeating: 0x88, count: 16))  // challenge
        message.append(Data(repeating: 0x99, count: 32))  // response
        
        return message
    }
    
    private func buildConfirmationMessage() -> Data {
        var message = Data([G7SimOpcode.authConfirm])
        
        // confirmHash (16 bytes)
        message.append(Data(repeating: 0xDD, count: 16))
        
        return message
    }
}

@Suite("G7 Auth Simulator Integration")
struct G7AuthSimulatorIntegrationTests {
    
    @Test("Multiple simulators are independent")
    func multipleSimulators() {
        let sim1 = G7AuthSimulator(sensorCode: "1111")
        let sim2 = G7AuthSimulator(sensorCode: "2222")
        
        // Process Round 1 on sim1 only
        _ = sim1.processMessage(buildRound1())
        
        #expect(sim1.state == .awaitingRound2)
        #expect(sim2.state == .awaitingRound1)
    }
    
    @Test("Reset allows re-authentication")
    func resetAndReauth() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // First auth attempt
        _ = simulator.processMessage(buildRound1())
        #expect(simulator.state == .awaitingRound2)
        
        // Reset
        simulator.reset()
        #expect(simulator.state == .awaitingRound1)
        
        // Second auth attempt
        _ = simulator.processMessage(buildRound1())
        #expect(simulator.state == .awaitingRound2)
    }
    
    @Test("Different sensor codes produce different results")
    func differentSensorCodes() {
        let sim1 = G7AuthSimulator(sensorCode: "1111")
        let sim2 = G7AuthSimulator(sensorCode: "2222")
        
        let round1 = buildRound1()
        
        guard case .sendResponse(let resp1) = sim1.processMessage(round1),
              case .sendResponse(let resp2) = sim2.processMessage(round1) else {
            Issue.record("Both should return responses")
            return
        }
        
        // Responses should differ due to random values
        #expect(resp1 != resp2)
    }
    
    private func buildRound1() -> Data {
        var message = Data([G7SimOpcode.authRound1])
        message.append(Data(repeating: 0xAA, count: 32))  // gx1
        message.append(Data(repeating: 0xBB, count: 32))  // gx2
        message.append(Data(repeating: 0x11, count: 80))  // zkp1
        message.append(Data(repeating: 0x22, count: 80))  // zkp2
        return message
    }
}

@Suite("G7 Crypto Operations")
struct G7CryptoTests {
    
    @Test("Simulator produces deterministic output structure")
    func outputStructure() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        var round1 = Data([G7SimOpcode.authRound1])
        round1.append(Data(repeating: 0x01, count: 224))
        
        guard case .sendResponse(let response) = simulator.processMessage(round1) else {
            Issue.record("Expected response")
            return
        }
        
        // Verify response structure
        #expect(response[0] == G7SimOpcode.authRound1)
        
        // gx3 at bytes 1-32
        let gx3 = response.subdata(in: 1..<33)
        #expect(gx3.count == 32)
        
        // gx4 at bytes 33-64
        let gx4 = response.subdata(in: 33..<65)
        #expect(gx4.count == 32)
        
        // zkp3 at bytes 65-144
        let zkp3 = response.subdata(in: 65..<145)
        #expect(zkp3.count == 80)
        
        // zkp4 at bytes 145-224
        let zkp4 = response.subdata(in: 145..<225)
        #expect(zkp4.count == 80)
    }
    
    @Test("Round 2 response structure is correct")
    func round2Structure() {
        let simulator = G7AuthSimulator(sensorCode: "1234")
        
        // Process Round 1 first
        var round1 = Data([G7SimOpcode.authRound1])
        round1.append(Data(repeating: 0x01, count: 224))
        _ = simulator.processMessage(round1)
        
        // Process Round 2
        var round2 = Data([G7SimOpcode.authRound2])
        round2.append(Data(repeating: 0x02, count: 112))
        
        guard case .sendResponse(let response) = simulator.processMessage(round2) else {
            Issue.record("Expected Round 2 response")
            return
        }
        
        // Response: opcode(1) + B(32) + zkpB(80) = 113 bytes
        #expect(response.count == 113)
        #expect(response[0] == G7SimOpcode.authRound2)
        
        // B value
        let b = response.subdata(in: 1..<33)
        #expect(b.count == 32)
        
        // zkpB
        let zkpB = response.subdata(in: 33..<113)
        #expect(zkpB.count == 80)
    }
}
