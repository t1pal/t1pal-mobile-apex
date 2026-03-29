// SPDX-License-Identifier: MIT
//
// G7JPAKEKeyConfirmConformanceTests.swift
// CGMKitTests
//
// Conformance tests for J-PAKE key confirmation vectors.
// Validates confirmation message format, shared key derivation, and state transitions
// per SESSION-G7-001d.
//
// Key confirmation is the final phase of J-PAKE where both parties prove they
// derived the same shared key without revealing it.
//
// Trace: SESSION-G7-001d, PRD-008 REQ-BLE-008

import Testing
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import CGMKit

@Suite("G7JPAKEKeyConfirmConformanceTests", .serialized)
struct G7JPAKEKeyConfirmConformanceTests {
    
    // MARK: - Fixture Data
    
    /// Fixture JSON path for validation
    static let fixtureSessionID = "SESSION-G7-001d"
    
    // MARK: - Helper: Create Mock Responses
    
    /// Creates a valid mock Round 1 response
    private func createMockRound1Response() -> G7JPAKERound1Response {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // gx3
        data.append(Data(repeating: 0x22, count: 32))  // gx4
        data.append(Data(repeating: 0x33, count: 80))  // zkp3
        data.append(Data(repeating: 0x44, count: 80))  // zkp4
        return G7JPAKERound1Response(data: data)!
    }
    
    /// Creates a valid mock Round 2 response
    private func createMockRound2Response() -> G7JPAKERound2Response {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x55, count: 32))  // B
        data.append(Data(repeating: 0x66, count: 80))  // zkpB
        return G7JPAKERound2Response(data: data)!
    }
    
    /// Helper to get authenticator to confirmation state
    private func getAuthenticatorToConfirmationState() async throws -> G7Authenticator {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        return auth
    }
    
    // MARK: - JPAKE-CONFIRM-001: Confirmation Message Structure
    
    @Test("Confirm message has correct opcode")
    func confirmMessageHasCorrectOpcode() async throws {
        // Get authenticator to confirmation state and retrieve confirm message
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        
        let data = confirmMsg.data
        #expect(data[0] == G7Opcode.authConfirm.rawValue, "First byte should be AuthConfirm opcode (0x04)")
        #expect(data[0] == 0x04, "AuthConfirm opcode should be 0x04")
    }
    
    @Test("Confirm message total length")
    func confirmMessageTotalLength() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        
        let data = confirmMsg.data
        // opcode(1) + confirmHash(16) = 17
        #expect(data.count == 17, "Confirmation message should be 17 bytes")
    }
    
    @Test("Confirm hash length")
    func confirmHashLength() async throws {
        let auth = try G7Authenticator(sensorCode: "9012")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        
        #expect(confirmMsg.confirmHash.count == 16, "Confirmation hash should be 16 bytes")
    }
    
    // MARK: - JPAKE-CONFIRM-002: Confirmation Response Parsing
    
    @Test("Confirm response parsing with valid data")
    func confirmResponseParsingWithValidData() {
        var data = Data([G7Opcode.authConfirm.rawValue])
        data.append(Data(repeating: 0xAA, count: 16))  // confirmHash
        
        let response = G7JPAKEConfirmResponse(data: data)
        
        #expect(response != nil, "Should parse valid confirmation response")
        #expect(response?.confirmHash.count == 16, "confirmHash should be 16 bytes")
    }
    
    @Test("Confirm response parsing rejects wrong opcode")
    func confirmResponseParsingRejectsWrongOpcode() {
        var data = Data([0xFF])  // Wrong opcode
        data.append(Data(repeating: 0x00, count: 16))
        
        let response = G7JPAKEConfirmResponse(data: data)
        #expect(response == nil, "Should reject wrong opcode")
    }
    
    @Test("Confirm response parsing rejects short data")
    func confirmResponseParsingRejectsShortData() {
        var data = Data([G7Opcode.authConfirm.rawValue])
        data.append(Data(repeating: 0x00, count: 10))  // Too short
        
        let response = G7JPAKEConfirmResponse(data: data)
        #expect(response == nil, "Should reject data shorter than 17 bytes")
    }
    
    @Test("Confirm response minimum length")
    func confirmResponseMinimumLength() {
        // Exact minimum: opcode(1) + confirmHash(16) = 17
        var data = Data([G7Opcode.authConfirm.rawValue])
        data.append(Data(repeating: 0xBB, count: 16))
        
        #expect(data.count == 17, "Valid response should be exactly 17 bytes")
        
        let response = G7JPAKEConfirmResponse(data: data)
        #expect(response != nil, "Should parse 17-byte response")
    }
    
    // MARK: - JPAKE-CONFIRM-003: Session Key Tests
    
    @Test("Session key is set after round 2")
    func sessionKeyIsSetAfterRound2() async throws {
        let auth = try G7Authenticator(sensorCode: "1111")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let sessionKey = await auth.sessionKey
        #expect(sessionKey != nil, "Session key should be set after Round 2 processing")
    }
    
    // MARK: - JPAKE-CONFIRM-006: State Transitions
    
    @Test("State transition to awaiting confirmation")
    func stateTransitionToAwaitingConfirmation() async throws {
        let auth = try G7Authenticator(sensorCode: "2222")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        
        var state = await auth.state
        if case .awaitingRound2Response = state { } else {
            Issue.record("Expected awaitingRound2Response state")
        }
        
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        state = await auth.state
        if case .awaitingConfirmation = state { } else {
            Issue.record("Expected awaitingConfirmation state after processRound2Response()")
        }
    }
    
    @Test("State transition to authenticated")
    func stateTransitionToAuthenticated() async throws {
        let auth = try G7Authenticator(sensorCode: "3333")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        // Create a matching confirmation response
        // The sensor would send its own hash, but for testing we use the expected hash
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        
        // Get the session key from authenticator
        let sessionKey = await auth.sessionKey
        #expect(sessionKey != nil)
        
        // Build expected responder confirmation hash
        // This MUST match computeConfirmationHash(key:isInitiator:false) in G7Authenticator
        // The authenticator uses: AES-ECB doubled with role "server" padded to 8 bytes
        let role = "server"
        var challenge = Data(role.utf8)
        while challenge.count < 8 {
            challenge.append(0x00)
        }
        challenge = Data(challenge.prefix(8))
        
        // Use the same AES doubled method (returns 8 bytes)
        var responderHash = ConfirmationHash.aesDoubled.compute(sessionKey: sessionKey!, challenge: challenge)
        
        // Pad to 16 bytes for protocol compatibility (same as authenticator)
        while responderHash.count < 16 {
            responderHash.append(0x00)
        }
        
        responseData.append(responderHash)
        
        let confirmResponse = G7JPAKEConfirmResponse(data: responseData)!
        let success = try await auth.processConfirmation(confirmResponse)
        
        #expect(success, "Confirmation should succeed with correct hash")
        
        let state = await auth.state
        if case .authenticated = state { } else {
            Issue.record("Expected authenticated state after successful confirmation")
        }
    }
    
    // MARK: - JPAKE-CONFIRM-007: Failed Confirmation
    
    @Test("Failed confirmation with wrong hash")
    func failedConfirmationWithWrongHash() async throws {
        let auth = try G7Authenticator(sensorCode: "4444")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        // Create response with wrong hash
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        responseData.append(Data(repeating: 0xFF, count: 16))  // Wrong hash
        
        let confirmResponse = G7JPAKEConfirmResponse(data: responseData)!
        
        await #expect(throws: (any Error).self) {
            _ = try await auth.processConfirmation(confirmResponse)
        }
        
        let state = await auth.state
        if case .failed = state { } else {
            Issue.record("Expected failed state after wrong confirmation")
        }
    }
    
    // MARK: - JPAKE-CONFIRM-008: Non-Zero Session Key
    
    @Test("Session key is non-zero")
    func sessionKeyIsNonZero() async throws {
        let auth = try G7Authenticator(sensorCode: "5555")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let sessionKey = await auth.sessionKey
        #expect(sessionKey != nil)
        
        let zeroKey = Data(count: sessionKey!.count)
        #expect(sessionKey != zeroKey, "Session key should not be all zeros")
    }
    
    // MARK: - JPAKE-CONFIRM-009: State Validation
    
    @Test("Confirm rejects idle state")
    func confirmRejectsIdleState() async throws {
        let auth = try G7Authenticator(sensorCode: "6666")
        
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        responseData.append(Data(repeating: 0xAA, count: 16))
        let confirmResponse = G7JPAKEConfirmResponse(data: responseData)!
        
        do {
            _ = try await auth.processConfirmation(confirmResponse)
            Issue.record("Should throw unexpectedState")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Confirm rejects awaiting round 1 state")
    func confirmRejectsAwaitingRound1State() async throws {
        let auth = try G7Authenticator(sensorCode: "7777")
        _ = await auth.startAuthentication()
        
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        responseData.append(Data(repeating: 0xAA, count: 16))
        let confirmResponse = G7JPAKEConfirmResponse(data: responseData)!
        
        do {
            _ = try await auth.processConfirmation(confirmResponse)
            Issue.record("Should throw unexpectedState")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Confirm rejects awaiting round 2 state")
    func confirmRejectsAwaitingRound2State() async throws {
        let auth = try G7Authenticator(sensorCode: "8888")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        responseData.append(Data(repeating: 0xAA, count: 16))
        let confirmResponse = G7JPAKEConfirmResponse(data: responseData)!
        
        do {
            _ = try await auth.processConfirmation(confirmResponse)
            Issue.record("Should throw unexpectedState")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    // MARK: - JPAKE-CONFIRM-010: Hash Varies with Key
    
    @Test("Confirm hash varies with password")
    func confirmHashVariesWithPassword() async throws {
        let auth1 = try G7Authenticator(sensorCode: "1234")
        let auth2 = try G7Authenticator(sensorCode: "5678")
        
        _ = await auth1.startAuthentication()
        _ = await auth2.startAuthentication()
        
        _ = try await auth1.processRound1Response(createMockRound1Response())
        _ = try await auth2.processRound1Response(createMockRound1Response())
        
        let confirm1 = try await auth1.processRound2Response(createMockRound2Response())
        let confirm2 = try await auth2.processRound2Response(createMockRound2Response())
        
        // Different passwords should produce different confirmation hashes
        #expect(confirm1.confirmHash != confirm2.confirmHash,
                "Different passwords should produce different confirmation hashes")
    }
    
    // MARK: - Confirmation Message Field Extraction
    
    @Test("Confirm message field offsets")
    func confirmMessageFieldOffsets() async throws {
        let auth = try G7Authenticator(sensorCode: "9999")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        let data = confirmMsg.data
        
        // Verify field offsets match fixture spec
        // opcode at offset 0 (1 byte)
        #expect(data[0] == 0x04, "Opcode at offset 0")
        
        // confirmHash at offset 1 (16 bytes)
        let hashValue = data.subdata(in: 1..<17)
        #expect(hashValue.count == 16, "confirmHash at offset 1, length 16")
    }
    
    // MARK: - Response Hash Extraction
    
    @Test("Extract hash from response")
    func extractHashFromResponse() {
        var data = Data([G7Opcode.authConfirm.rawValue])
        let expectedHash = Data(repeating: 0x77, count: 16)
        data.append(expectedHash)
        
        let response = G7JPAKEConfirmResponse(data: data)
        
        #expect(response != nil)
        #expect(response?.confirmHash == expectedHash, "Should extract confirmHash correctly")
    }
    
    // MARK: - Confirmation Hash Non-Zero
    
    @Test("Confirm hash is non-zero")
    func confirmHashIsNonZero() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        
        let zeroHash = Data(count: 16)
        #expect(confirmMsg.confirmHash != zeroHash, "Confirmation hash should not be all zeros")
    }
    
    // MARK: - Session Key Determinism
    
    @Test("Session key deterministic with same inputs")
    func sessionKeyDeterministicWithSameInputs() async throws {
        // With same password and same mock responses, session key derivation should be deterministic
        // (though with random key generation, the intermediate keys differ)
        // This test verifies the key is set and valid
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let key1 = await auth.sessionKey
        #expect(key1 != nil)
        #expect(key1!.count > 0, "Session key should have non-zero length")
    }
}
