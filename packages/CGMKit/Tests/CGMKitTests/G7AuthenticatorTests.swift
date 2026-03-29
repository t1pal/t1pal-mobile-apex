// SPDX-License-Identifier: MIT
//
// G7AuthenticatorTests.swift
// CGMKitTests
//
// Unit tests for Dexcom G7 J-PAKE authentication.
// Trace: PRD-008 REQ-BLE-008

import Testing
import Foundation
@testable import CGMKit

@Suite("G7AuthenticatorTests")
struct G7AuthenticatorTests {
    
    // MARK: - Initialization Tests
    
    @Test("Authenticator initialization with valid code")
    func authenticatorInitializationWithValidCode() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        let state = await auth.state
        let sensorCode = await auth.sensorCode
        
        #expect(sensorCode == "1234")
        if case .idle = state {
            // Expected
        } else {
            Issue.record("Expected idle state")
        }
    }
    
    @Test("Authenticator initialization with invalid code length")
    func authenticatorInitializationWithInvalidCodeLength() throws {
        do {
            _ = try G7Authenticator(sensorCode: "123")
            Issue.record("Should throw invalidSensorCode")
        } catch G7Authenticator.AuthError.invalidSensorCode {
            // Expected
        }
        
        do {
            _ = try G7Authenticator(sensorCode: "12345")
            Issue.record("Should throw invalidSensorCode")
        } catch G7Authenticator.AuthError.invalidSensorCode {
            // Expected
        }
    }
    
    @Test("Authenticator initialization with non-numeric code")
    func authenticatorInitializationWithNonNumericCode() throws {
        do {
            _ = try G7Authenticator(sensorCode: "ABCD")
            Issue.record("Should throw invalidSensorCode")
        } catch G7Authenticator.AuthError.invalidSensorCode {
            // Expected
        }
        
        do {
            _ = try G7Authenticator(sensorCode: "12AB")
            Issue.record("Should throw invalidSensorCode")
        } catch G7Authenticator.AuthError.invalidSensorCode {
            // Expected
        }
    }
    
    // MARK: - Round 1 Tests
    
    @Test("Start authentication generates Round 1 message")
    func startAuthenticationGeneratesRound1Message() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        
        let round1 = await auth.startAuthentication()
        
        // Verify message structure
        #expect(round1.gx1.count == 32, "gx1 should be 32 bytes")
        #expect(round1.gx2.count == 32, "gx2 should be 32 bytes")
        #expect(round1.zkp1.commitment.count == 32, "ZKP1 commitment should be 32 bytes")
        #expect(round1.zkp2.commitment.count == 32, "ZKP2 commitment should be 32 bytes")
        
        // Check state transition
        let state = await auth.state
        if case .awaitingRound1Response = state {
            // Expected
        } else {
            Issue.record("Expected awaitingRound1Response state")
        }
    }
    
    @Test("Round 1 message serialization")
    func round1MessageSerialization() async throws {
        let auth = try G7Authenticator(sensorCode: "9012")
        
        let round1 = await auth.startAuthentication()
        let data = round1.data
        
        // Opcode + gx1(32) + gx2(32) + zkp1(80) + zkp2(80) = 225 bytes
        #expect(data[0] == G7Opcode.authRound1.rawValue)
        #expect(data.count > 64, "Round 1 message should contain gx1 and gx2")
    }
    
    @Test("Round 1 generates different values each time")
    func round1GeneratesDifferentValuesEachTime() async throws {
        let auth1 = try G7Authenticator(sensorCode: "1111")
        let auth2 = try G7Authenticator(sensorCode: "1111")
        
        let round1a = await auth1.startAuthentication()
        let round1b = await auth2.startAuthentication()
        
        // Random values should be different
        #expect(round1a.gx1 != round1b.gx1, "gx1 should be random")
        #expect(round1a.gx2 != round1b.gx2, "gx2 should be random")
    }
    
    // MARK: - ZK Proof Tests
    
    @Test("ZK proof structure")
    func zkProofStructure() {
        let commitment = Data(repeating: 0x42, count: 32)
        let challenge = Data(repeating: 0x24, count: 16)
        let response = Data(repeating: 0x18, count: 32)
        
        let proof = G7ZKProof(commitment: commitment, challenge: challenge, response: response)
        
        #expect(proof.commitment == commitment)
        #expect(proof.challenge == challenge)
        #expect(proof.response == response)
    }
    
    @Test("ZK proof serialization")
    func zkProofSerialization() {
        let commitment = Data(repeating: 0x11, count: 32)
        let challenge = Data(repeating: 0x22, count: 16)
        let response = Data(repeating: 0x33, count: 32)
        
        let proof = G7ZKProof(commitment: commitment, challenge: challenge, response: response)
        let data = proof.data
        
        #expect(data.count == 80)
        #expect(data.prefix(32) == commitment)
        #expect(data.subdata(in: 32..<48) == challenge)
        #expect(data.subdata(in: 48..<80) == response)
    }
    
    @Test("ZK proof parsing")
    func zkProofParsing() {
        var data = Data()
        data.append(Data(repeating: 0xAA, count: 32))  // commitment
        data.append(Data(repeating: 0xBB, count: 16))  // challenge
        data.append(Data(repeating: 0xCC, count: 32))  // response
        
        let proof = G7ZKProof(data: data)
        #expect(proof != nil)
        #expect(proof?.commitment == Data(repeating: 0xAA, count: 32))
        #expect(proof?.challenge == Data(repeating: 0xBB, count: 16))
        #expect(proof?.response == Data(repeating: 0xCC, count: 32))
    }
    
    @Test("ZK proof parsing fails with insufficient data")
    func zkProofParsingFailsWithInsufficientData() {
        let shortData = Data(repeating: 0x00, count: 50)  // Less than 80 bytes
        let proof = G7ZKProof(data: shortData)
        #expect(proof == nil)
    }
    
    // MARK: - Round 1 Response Tests
    
    @Test("Round 1 response parsing")
    func round1ResponseParsing() {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // gx3
        data.append(Data(repeating: 0x22, count: 32))  // gx4
        data.append(Data(repeating: 0x33, count: 80))  // zkp3
        data.append(Data(repeating: 0x44, count: 80))  // zkp4
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response != nil)
        #expect(response?.gx3.count == 32)
        #expect(response?.gx4.count == 32)
    }
    
    @Test("Round 1 response parsing fails with wrong opcode")
    func round1ResponseParsingFailsWithWrongOpcode() {
        var data = Data([0xFF])  // Wrong opcode
        data.append(Data(repeating: 0x00, count: 224))
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response == nil)
    }
    
    @Test("Round 1 response parsing fails with insufficient data")
    func round1ResponseParsingFailsWithInsufficientData() {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x00, count: 50))  // Not enough data
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response == nil)
    }
    
    // MARK: - Round 2 Tests
    
    @Test("Round 2 message serialization")
    func round2MessageSerialization() {
        let a = Data(repeating: 0xAB, count: 32)
        let zkpA = G7ZKProof(
            commitment: Data(repeating: 0x01, count: 32),
            challenge: Data(repeating: 0x02, count: 16),
            response: Data(repeating: 0x03, count: 32)
        )
        
        let message = G7JPAKERound2Message(a: a, zkpA: zkpA)
        let data = message.data
        
        #expect(data[0] == G7Opcode.authRound2.rawValue)
        #expect(data.count > 32)
    }
    
    @Test("Round 2 response parsing")
    func round2ResponseParsing() {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x55, count: 32))  // b
        data.append(Data(repeating: 0x66, count: 80))  // zkpB
        
        let response = G7JPAKERound2Response(data: data)
        #expect(response != nil)
        #expect(response?.b.count == 32)
    }
    
    // MARK: - Confirmation Tests
    
    @Test("Confirm message serialization")
    func confirmMessageSerialization() {
        let confirmHash = Data(repeating: 0x77, count: 16)
        let message = G7JPAKEConfirmMessage(confirmHash: confirmHash)
        let data = message.data
        
        #expect(data[0] == G7Opcode.authConfirm.rawValue)
        #expect(data.count == 17)
        #expect(data.subdata(in: 1..<17) == confirmHash)
    }
    
    @Test("Confirm response parsing")
    func confirmResponseParsing() {
        var data = Data([G7Opcode.authConfirm.rawValue])
        data.append(Data(repeating: 0x88, count: 16))
        
        let response = G7JPAKEConfirmResponse(data: data)
        #expect(response != nil)
        #expect(response?.confirmHash.count == 16)
    }
    
    @Test("Confirm response parsing fails with insufficient data")
    func confirmResponseParsingFailsWithInsufficientData() {
        let data = Data([G7Opcode.authConfirm.rawValue, 0x00, 0x01])  // Only 3 bytes
        
        let response = G7JPAKEConfirmResponse(data: data)
        #expect(response == nil)
    }
    
    // MARK: - State Machine Tests
    
    @Test("Process Round 1 fails in wrong state")
    func processRound1FailsInWrongState() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        // Create dummy Round 1 response
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))
        data.append(Data(repeating: 0x22, count: 32))
        data.append(Data(repeating: 0x33, count: 80))
        data.append(Data(repeating: 0x44, count: 80))
        let response = G7JPAKERound1Response(data: data)!
        
        // Try to process without starting authentication
        do {
            _ = try await auth.processRound1Response(response)
            Issue.record("Should throw unexpectedState error")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Process Round 2 fails in wrong state")
    func processRound2FailsInWrongState() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        // Create dummy Round 2 response
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x55, count: 32))
        data.append(Data(repeating: 0x66, count: 80))
        let response = G7JPAKERound2Response(data: data)!
        
        // Try to process in wrong state
        do {
            _ = try await auth.processRound2Response(response)
            Issue.record("Should throw unexpectedState error")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Process confirmation fails in wrong state")
    func processConfirmationFailsInWrongState() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        // Create dummy confirmation response
        var data = Data([G7Opcode.authConfirm.rawValue])
        data.append(Data(repeating: 0x99, count: 16))
        let response = G7JPAKEConfirmResponse(data: data)!
        
        // Try to process in wrong state
        do {
            _ = try await auth.processConfirmation(response)
            Issue.record("Should throw unexpectedState error")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    // MARK: - Full Flow Simulation Test
    
    @Test("Full authentication flow starts correctly")
    func fullAuthenticationFlowStartsCorrectly() async throws {
        let auth = try G7Authenticator(sensorCode: "4321")
        
        // Start authentication
        let round1 = await auth.startAuthentication()
        
        // Verify Round 1 message is valid
        #expect(round1.gx1.count == 32)
        #expect(round1.gx2.count == 32)
        #expect(round1.zkp1.commitment.count == 32)
        #expect(round1.zkp2.commitment.count == 32)
        
        // State should be awaiting Round 1 response
        let state = await auth.state
        if case .awaitingRound1Response = state {
            // Success
        } else {
            Issue.record("Expected awaitingRound1Response state")
        }
    }
    
    // MARK: - Session Key Tests
    
    @Test("Session key is nil before authentication")
    func sessionKeyIsNilBeforeAuthentication() async throws {
        let auth = try G7Authenticator(sensorCode: "9999")
        let sessionKey = await auth.sessionKey
        #expect(sessionKey == nil)
    }
}
