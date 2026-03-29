// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemJPAKEConformanceTests.swift
// PumpKitTests
//
// Conformance tests for Tandem J-PAKE authentication.
// Validates message structures against fixture_x2_auth.json test vectors.
//
// Trace: TANDEM-IMPL-002, X2-VALIDATE-001

import Testing
import Foundation
@testable import PumpKit

@Suite("TandemJPAKE Conformance Tests", .serialized)
struct TandemJPAKEConformanceTests {
    
    // MARK: - Opcode Tests
    
    /// JPAKE-CONFORM-001: Verify J-PAKE opcodes match fixture
    @Test("J-PAKE opcodes match fixture")
    func jpakeOpcodesMatchFixture() {
        // From fixture_x2_auth.json jpake_ecjpake.steps
        #expect(TandemJPAKEOpcode.jpake1aRequest.rawValue == 32)
        #expect(TandemJPAKEOpcode.jpake1aResponse.rawValue == 33)
        #expect(TandemJPAKEOpcode.jpake1bRequest.rawValue == 34)
        #expect(TandemJPAKEOpcode.jpake1bResponse.rawValue == 35)
        #expect(TandemJPAKEOpcode.jpake2Request.rawValue == 36)
        #expect(TandemJPAKEOpcode.jpake2Response.rawValue == 37)
        #expect(TandemJPAKEOpcode.jpake3SessionKeyRequest.rawValue == 38)
        #expect(TandemJPAKEOpcode.jpake3SessionKeyResponse.rawValue == 39)
        #expect(TandemJPAKEOpcode.jpake4KeyConfirmationRequest.rawValue == 40)
        #expect(TandemJPAKEOpcode.jpake4KeyConfirmationResponse.rawValue == 41)
    }
    
    /// JPAKE-CONFORM-002: Verify request opcodes are even, response are odd
    @Test("J-PAKE opcode convention")
    func jpakeOpcodeConvention() {
        for opcode in TandemJPAKEOpcode.allCases {
            let isRequest = opcode.isRequest
            let isEven = opcode.rawValue % 2 == 0
            #expect(isRequest == isEven, "\(opcode) request flag should match even/odd convention")
        }
    }
    
    // MARK: - Constants Tests
    
    /// JPAKE-CONFORM-003: Verify protocol constants
    @Test("J-PAKE constants")
    func jpakeConstants() {
        #expect(TandemJPAKEConstants.pairingCodeLength == 6)
        #expect(TandemJPAKEConstants.round1TotalSize == 330)
        #expect(TandemJPAKEConstants.round1ChunkSize == 165)
        #expect(TandemJPAKEConstants.sessionKeySize == 32)
        #expect(TandemJPAKEConstants.serverNonceSize == 16)
        #expect(TandemJPAKEConstants.fieldSize == 32)
        #expect(TandemJPAKEConstants.uncompressedPointSize == 65)
    }
    
    /// JPAKE-CONFORM-004: Verify authorization characteristic UUID
    @Test("Authorization characteristic UUID")
    func authorizationCharacteristicUUID() {
        #expect(
            TandemJPAKEConstants.authorizationCharUUID.uppercased() ==
            "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
        )
    }
    
    // MARK: - State Machine Tests
    
    /// JPAKE-CONFORM-005: Verify state machine states match fixture
    @Test("J-PAKE states exist")
    func jpakeStates() {
        // All states from fixture state_machine.states
        let expectedStates = [
            "BOOTSTRAP_INITIAL",
            "ROUND_1A_SENT",
            "ROUND_1A_RECEIVED",
            "ROUND_1B_SENT",
            "ROUND_1B_RECEIVED",
            "ROUND_2_SENT",
            "ROUND_2_RECEIVED",
            "CONFIRM_INITIAL",
            "CONFIRM_3_SENT",
            "CONFIRM_3_RECEIVED",
            "CONFIRM_4_SENT",
            "CONFIRM_4_RECEIVED",
            "COMPLETE",
            "INVALID"
        ]
        
        for stateName in expectedStates {
            #expect(TandemJPAKEState(rawValue: stateName) != nil, "State \(stateName) should exist")
        }
    }
    
    /// JPAKE-CONFORM-006: Verify state progress values
    @Test("J-PAKE state progress values")
    func jpakeStateProgress() {
        #expect(TandemJPAKEState.bootstrapInitial.progress == 0)
        #expect(TandemJPAKEState.round1aReceived.progress == 10)
        #expect(TandemJPAKEState.round1bReceived.progress == 30)
        #expect(TandemJPAKEState.round2Received.progress == 50)
        #expect(TandemJPAKEState.confirm3Received.progress == 70)
        #expect(TandemJPAKEState.confirm4Received.progress == 90)
        #expect(TandemJPAKEState.complete.progress == 100)
    }
    
    // MARK: - Message Encoding Tests
    
    /// JPAKE-CONFORM-007: Verify Jpake1aRequest encoding
    @Test("Jpake1aRequest encoding")
    func jpake1aRequestEncoding() {
        let challenge = Data(count: 165)  // 165 bytes of round 1 data
        let request = Jpake1aRequest(appInstanceId: 1, centralChallenge: challenge)
        
        let encoded = request.encode()
        
        // Format: appInstanceId (2 bytes LE) + centralChallenge (165 bytes)
        #expect(encoded.count == 167)
        #expect(encoded[0] == 0x01)  // appInstanceId low byte
        #expect(encoded[1] == 0x00)  // appInstanceId high byte
    }
    
    /// JPAKE-CONFORM-008: Verify Jpake1aResponse decoding
    @Test("Jpake1aResponse decoding")
    func jpake1aResponseDecoding() throws {
        var data = Data()
        data.append(contentsOf: [0x01, 0x00])  // appInstanceId = 1
        data.append(Data(repeating: 0xAA, count: 165))  // server round 1 part 1
        
        let response = try Jpake1aResponse.decode(from: data)
        
        #expect(response.appInstanceId == 1)
        #expect(response.serverRound1Part1.count == 165)
        #expect(response.serverRound1Part1[0] == 0xAA)
    }
    
    /// JPAKE-CONFORM-009: Verify Jpake3SessionKeyRequest encoding (minimal message)
    @Test("Jpake3SessionKeyRequest encoding")
    func jpake3SessionKeyRequestEncoding() {
        let request = Jpake3SessionKeyRequest(challengeParam: 0)
        let encoded = request.encode()
        
        // Format: challengeParam (2 bytes LE)
        #expect(encoded.count == 2)
        #expect(encoded[0] == 0x00)
        #expect(encoded[1] == 0x00)
    }
    
    /// JPAKE-CONFORM-010: Verify Jpake3SessionKeyResponse decoding
    @Test("Jpake3SessionKeyResponse decoding")
    func jpake3SessionKeyResponseDecoding() throws {
        var data = Data()
        data.append(contentsOf: [0x01, 0x00])  // appInstanceId = 1
        data.append(Data(repeating: 0xBB, count: 16))  // 16-byte server nonce
        
        let response = try Jpake3SessionKeyResponse.decode(from: data)
        
        #expect(response.appInstanceId == 1)
        #expect(response.serverNonce.count == 16)
        #expect(response.serverNonce[0] == 0xBB)
    }
    
    // MARK: - Message Framing Tests
    
    /// JPAKE-CONFORM-011: Verify message framing with opcode header
    @Test("Message framing")
    func messageFraming() {
        let request = Jpake3SessionKeyRequest(challengeParam: 0)
        let framed = TandemJPAKECodec.frame(request, transactionId: 5)
        
        // Format: [opcode: 1][txId: 1][length: 1][cargo]
        #expect(framed[0] == 38)  // Jpake3SessionKeyRequest opcode
        #expect(framed[1] == 5)   // transaction ID
        #expect(framed[2] == 2)   // cargo length
    }
    
    /// JPAKE-CONFORM-012: Verify message unframing
    @Test("Message unframing")
    func messageUnframing() throws {
        // Build a framed response: opcode 39, txId 5, length 18, cargo (18 bytes)
        var framed = Data()
        framed.append(39)  // Jpake3SessionKeyResponse opcode
        framed.append(5)   // txId
        framed.append(18)  // cargo length
        framed.append(contentsOf: [0x01, 0x00])  // appInstanceId
        framed.append(Data(repeating: 0xCC, count: 16))  // nonce
        
        let (opcode, txId, cargo) = try TandemJPAKECodec.unframe(framed)
        
        #expect(opcode == .jpake3SessionKeyResponse)
        #expect(txId == 5)
        #expect(cargo.count == 18)
    }
    
    // MARK: - Error Tests
    
    /// JPAKE-CONFORM-013: Verify error for short messages
    @Test("Short message error")
    func shortMessageError() throws {
        let shortData = Data([0x01])  // Only 1 byte, need at least 2
        
        do {
            _ = try Jpake1aResponse.decode(from: shortData)
            Issue.record("Expected messageTooShort error")
        } catch let error as TandemJPAKEError {
            switch error {
            case .messageTooShort:
                break // Expected
            default:
                Issue.record("Expected messageTooShort error, got \(error)")
            }
        }
    }
    
    /// JPAKE-CONFORM-014: Verify error for invalid opcode
    @Test("Invalid opcode error")
    func invalidOpcodeError() throws {
        var badFramed = Data()
        badFramed.append(99)  // Invalid opcode
        badFramed.append(0)   // txId
        badFramed.append(0)   // length
        
        do {
            _ = try TandemJPAKECodec.unframe(badFramed)
            Issue.record("Expected invalidOpcode error")
        } catch let error as TandemJPAKEError {
            switch error {
            case .invalidOpcode:
                break // Expected
            default:
                Issue.record("Expected invalidOpcode error, got \(error)")
            }
        }
    }
    
    // MARK: - Engine Tests
    
    /// JPAKE-CONFORM-015: Verify engine initialization with valid code
    @Test("Engine init with valid code")
    func engineInitWithValidCode() async throws {
        let engine = try TandemJPAKEEngine(pairingCode: "123456")
        
        let state = await engine.state
        let isAuth = await engine.isAuthenticated
        
        #expect(state == .bootstrapInitial)
        #expect(!isAuth)
    }
    
    /// JPAKE-CONFORM-016: Verify engine rejects invalid pairing codes
    @Test("Engine rejects invalid code")
    func engineRejectsInvalidCode() {
        // Too short
        do {
            _ = try TandemJPAKEEngine(pairingCode: "12345")
            Issue.record("Expected invalidPairingCode error")
        } catch let error as TandemJPAKEError {
            switch error {
            case .invalidPairingCode:
                break // Expected
            default:
                Issue.record("Expected invalidPairingCode error")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
        
        // Too long
        do {
            _ = try TandemJPAKEEngine(pairingCode: "1234567")
            Issue.record("Expected invalidPairingCode error")
        } catch let error as TandemJPAKEError {
            switch error {
            case .invalidPairingCode:
                break // Expected
            default:
                Issue.record("Expected invalidPairingCode error")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
        
        // Non-numeric
        do {
            _ = try TandemJPAKEEngine(pairingCode: "12345a")
            Issue.record("Expected invalidPairingCode error")
        } catch let error as TandemJPAKEError {
            switch error {
            case .invalidPairingCode:
                break // Expected
            default:
                Issue.record("Expected invalidPairingCode error")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
    }
    
    /// JPAKE-CONFORM-017: Verify round 1 data generation
    @Test("Engine round 1 generation")
    func engineRound1Generation() async throws {
        let engine = try TandemJPAKEEngine(pairingCode: "123456")
        
        let round1 = await engine.generateRound1()
        
        // Round 1 should be 330 bytes
        #expect(round1.count == 330)
        
        // Parts should be 165 bytes each
        let part1 = await engine.getRound1Part1()
        let part2 = await engine.getRound1Part2()
        #expect(part1.count == 165)
        #expect(part2.count == 165)
        
        // State should be round1aSent
        let state = await engine.state
        #expect(state == .round1aSent)
    }
    
    /// JPAKE-CONFORM-018: Verify message creation helpers
    @Test("Engine message creation")
    func engineMessageCreation() async throws {
        let engine = try TandemJPAKEEngine(pairingCode: "123456")
        
        // Generate round 1 first
        _ = await engine.generateRound1()
        
        let jpake1a = await engine.createJpake1aRequest()
        let jpake1b = await engine.createJpake1bRequest()
        
        #expect(jpake1a.centralChallenge.count == 165)
        #expect(jpake1b.centralChallenge.count == 165)
        
        // App instance ID should match
        let expectedId = await engine.appInstanceId
        #expect(jpake1a.appInstanceId == expectedId)
        #expect(jpake1b.appInstanceId == expectedId)
    }
    
    // MARK: - Fixture Test Vector Tests
    
    /// JPAKE-CONFORM-019: Verify message sizes match fixture
    @Test("Message sizes match fixture")
    func messageSizesMatchFixture() {
        // From fixture: step sizes
        // Jpake1aRequest: 167 = 2 (appInstanceId) + 165 (challenge)
        // Jpake3SessionKeyRequest: 2 = 2 (challengeParam)
        // Jpake3SessionKeyResponse: 18 = 2 (appInstanceId) + 16 (nonce)
        
        let jpake1a = Jpake1aRequest(appInstanceId: 1, centralChallenge: Data(count: 165))
        #expect(jpake1a.encode().count == 167)
        
        let jpake3 = Jpake3SessionKeyRequest()
        #expect(jpake3.encode().count == 2)
        
        var nonce = Data([0x01, 0x00])
        nonce.append(Data(count: 16))
        let jpake3Response = try! Jpake3SessionKeyResponse.decode(from: nonce)
        #expect(jpake3Response.encode().count == 18)
    }
    
    /// JPAKE-CONFORM-020: Verify round-trip encoding/decoding
    @Test("Message round-trip")
    func messageRoundTrip() throws {
        // Jpake1aRequest
        let original1a = Jpake1aRequest(
            appInstanceId: 0x1234,
            centralChallenge: Data(repeating: 0x42, count: 165)
        )
        let decoded1a = try Jpake1aRequest.decode(from: original1a.encode())
        #expect(decoded1a.appInstanceId == original1a.appInstanceId)
        #expect(decoded1a.centralChallenge == original1a.centralChallenge)
        
        // Jpake3SessionKeyRequest
        let original3 = Jpake3SessionKeyRequest(challengeParam: 0)
        let decoded3 = try Jpake3SessionKeyRequest.decode(from: original3.encode())
        #expect(decoded3.challengeParam == original3.challengeParam)
        
        // Jpake4KeyConfirmationRequest
        let hash = Data(repeating: 0xAB, count: 32)
        let original4 = Jpake4KeyConfirmationRequest(appInstanceId: 5, confirmationHash: hash)
        let decoded4 = try Jpake4KeyConfirmationRequest.decode(from: original4.encode())
        #expect(decoded4.appInstanceId == original4.appInstanceId)
        #expect(decoded4.confirmationHash == original4.confirmationHash)
    }
}
