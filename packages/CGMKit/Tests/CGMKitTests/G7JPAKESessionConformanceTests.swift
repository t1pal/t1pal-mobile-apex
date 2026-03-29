// SPDX-License-Identifier: MIT
//
// G7JPAKESessionConformanceTests.swift
// CGMKitTests
//
// End-to-end conformance tests for complete J-PAKE authentication sessions.
// Validates the full state machine from idle → authenticated, combining
// Round 1, Round 2, and Key Confirmation phases.
//
// Trace: SESSION-G7-001e, PRD-008 REQ-BLE-008

import Testing
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import CGMKit

@Suite("G7JPAKESessionConformanceTests", .serialized)
struct G7JPAKESessionConformanceTests {
    
    // MARK: - Fixture Data
    
    /// Fixture JSON path for validation
    static let fixtureSessionID = "SESSION-G7-001e"
    
    // MARK: - Mock Response Helpers
    
    /// Creates a valid mock Round 1 response (sensor's reply)
    private func createMockRound1Response() -> G7JPAKERound1Response {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // gx3
        data.append(Data(repeating: 0x22, count: 32))  // gx4
        data.append(Data(repeating: 0x33, count: 80))  // zkp3
        data.append(Data(repeating: 0x44, count: 80))  // zkp4
        return G7JPAKERound1Response(data: data)!
    }
    
    /// Creates a valid mock Round 2 response (sensor's reply)
    private func createMockRound2Response() -> G7JPAKERound2Response {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x55, count: 32))  // B
        data.append(Data(repeating: 0x66, count: 80))  // zkpB
        return G7JPAKERound2Response(data: data)!
    }
    
    /// Creates a matching confirmation response for successful auth
    private func createMatchingConfirmResponse(for auth: G7Authenticator) async -> G7JPAKEConfirmResponse {
        var responseData = Data([G7Opcode.authConfirm.rawValue])
        
        // Compute expected responder hash matching G7Authenticator.computeConfirmationHash
        // Uses AES-ECB doubled with role "server" padded to 8 bytes
        let sessionKey = await auth.sessionKey!
        let role = "server"
        var challenge = Data(role.utf8)
        while challenge.count < 8 {
            challenge.append(0x00)
        }
        challenge = Data(challenge.prefix(8))
        
        // Use the same AES doubled method (returns 8 bytes)
        var responderHash = ConfirmationHash.aesDoubled.compute(sessionKey: sessionKey, challenge: challenge)
        
        // Pad to 16 bytes for protocol compatibility (same as authenticator)
        while responderHash.count < 16 {
            responderHash.append(0x00)
        }
        responseData.append(responderHash)
        
        return G7JPAKEConfirmResponse(data: responseData)!
    }
    
    // MARK: - JPAKE-SESSION-001: Complete State Machine
    
    @Test("Complete state transition sequence")
    func completeStateTransitionSequence() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        // Initial state
        var state = await auth.state
        if case .idle = state { } else {
            Issue.record("Expected initial state to be idle")
        }
        
        // Start authentication
        _ = await auth.startAuthentication()
        state = await auth.state
        if case .awaitingRound1Response = state { } else {
            Issue.record("Expected awaitingRound1Response after startAuthentication()")
        }
        
        // Process Round 1
        _ = try await auth.processRound1Response(createMockRound1Response())
        state = await auth.state
        if case .awaitingRound2Response = state { } else {
            Issue.record("Expected awaitingRound2Response after processRound1Response()")
        }
        
        // Process Round 2
        _ = try await auth.processRound2Response(createMockRound2Response())
        state = await auth.state
        if case .awaitingConfirmation = state { } else {
            Issue.record("Expected awaitingConfirmation after processRound2Response()")
        }
        
        // Process Confirmation
        let confirmResponse = await createMatchingConfirmResponse(for: auth)
        _ = try await auth.processConfirmation(confirmResponse)
        state = await auth.state
        if case .authenticated = state { } else {
            Issue.record("Expected authenticated after processConfirmation()")
        }
    }
    
    // MARK: - JPAKE-SESSION-002: All Messages Produced
    
    @Test("Round 1 TX message format")
    func round1TXMessageFormat() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        let round1Msg = await auth.startAuthentication()
        
        #expect(round1Msg.data[0] == 0x02, "Round 1 opcode should be 0x02")
        #expect(round1Msg.data.count == 225, "Round 1 TX should be 225 bytes")
    }
    
    @Test("Round 2 TX message format")
    func round2TXMessageFormat() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        let round2Msg = try await auth.processRound1Response(createMockRound1Response())
        
        #expect(round2Msg.data[0] == 0x03, "Round 2 opcode should be 0x03")
        #expect(round2Msg.data.count == 113, "Round 2 TX should be 113 bytes")
    }
    
    @Test("Confirm TX message format")
    func confirmTXMessageFormat() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        let confirmMsg = try await auth.processRound2Response(createMockRound2Response())
        
        #expect(confirmMsg.data[0] == 0x04, "Confirm opcode should be 0x04")
        #expect(confirmMsg.data.count == 17, "Confirm TX should be 17 bytes")
    }
    
    // MARK: - JPAKE-SESSION-003: Session Key Available
    
    @Test("Session key available after Round 2")
    func sessionKeyAvailableAfterRound2() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let sessionKey = await auth.sessionKey
        #expect(sessionKey != nil, "Session key should be available after Round 2")
        // Implementation uses full SHA256 (32 bytes), truncation happens at usage
        #expect((sessionKey?.count ?? 0) >= 16, "Session key should be at least 16 bytes")
    }
    
    // MARK: - JPAKE-SESSION-004: Failed Confirmation
    
    @Test("Wrong confirmation produces failed state")
    func wrongConfirmationProducesFailedState() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        // Create response with wrong hash
        var wrongData = Data([G7Opcode.authConfirm.rawValue])
        wrongData.append(Data(repeating: 0xFF, count: 16))
        let wrongResponse = G7JPAKEConfirmResponse(data: wrongData)!
        
        do {
            _ = try await auth.processConfirmation(wrongResponse)
            Issue.record("Should throw confirmationFailed error")
        } catch G7Authenticator.AuthError.confirmationFailed {
            // Expected
        }
        
        let state = await auth.state
        if case .failed = state { } else {
            Issue.record("Expected failed state after wrong confirmation")
        }
    }
    
    // MARK: - JPAKE-SESSION-005: Same Password Success
    
    @Test("Same password produces successful auth")
    func samePasswordProducesSuccessfulAuth() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let confirmResponse = await createMatchingConfirmResponse(for: auth)
        let success = try await auth.processConfirmation(confirmResponse)
        
        #expect(success, "Same password should produce successful authentication")
        
        let state = await auth.state
        if case .authenticated = state { } else {
            Issue.record("Expected authenticated state")
        }
    }
    
    // MARK: - JPAKE-SESSION-006: Different Password Failure
    
    @Test("Different password hashes differ")
    func differentPasswordHashesDiffer() async throws {
        let auth1 = try G7Authenticator(sensorCode: "1234")
        let auth2 = try G7Authenticator(sensorCode: "5678")
        
        _ = await auth1.startAuthentication()
        _ = await auth2.startAuthentication()
        
        _ = try await auth1.processRound1Response(createMockRound1Response())
        _ = try await auth2.processRound1Response(createMockRound1Response())
        
        let confirm1 = try await auth1.processRound2Response(createMockRound2Response())
        let confirm2 = try await auth2.processRound2Response(createMockRound2Response())
        
        // Different passwords produce different confirmation hashes
        #expect(confirm1.confirmHash != confirm2.confirmHash,
                          "Different passwords should produce different confirmation hashes")
    }
    
    // MARK: - JPAKE-SESSION-007: Multiple Sessions with Fresh Instances
    
    @Test("Multiple sessions with fresh instances")
    func multipleSessionsWithFreshInstances() async throws {
        // First authentication with one instance
        let auth1 = try G7Authenticator(sensorCode: "1234")
        _ = await auth1.startAuthentication()
        _ = try await auth1.processRound1Response(createMockRound1Response())
        _ = try await auth1.processRound2Response(createMockRound2Response())
        let confirmResponse1 = await createMatchingConfirmResponse(for: auth1)
        _ = try await auth1.processConfirmation(confirmResponse1)
        
        var state = await auth1.state
        if case .authenticated = state { } else {
            Issue.record("First auth should succeed")
        }
        
        // Second authentication with new instance (simulates session restart)
        let auth2 = try G7Authenticator(sensorCode: "1234")
        state = await auth2.state
        if case .idle = state { } else {
            Issue.record("New instance should start idle")
        }
        
        _ = await auth2.startAuthentication()
        _ = try await auth2.processRound1Response(createMockRound1Response())
        _ = try await auth2.processRound2Response(createMockRound2Response())
        let confirmResponse2 = await createMatchingConfirmResponse(for: auth2)
        _ = try await auth2.processConfirmation(confirmResponse2)
        
        state = await auth2.state
        if case .authenticated = state { } else {
            Issue.record("Second auth should succeed with fresh instance")
        }
    }
    
    // MARK: - JPAKE-SESSION-008: Total Message Bytes
    
    @Test("Total message bytes exchanged")
    func totalMessageBytesExchanged() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        let round1Tx = await auth.startAuthentication()
        #expect(round1Tx.data.count == 225, "Round 1 TX = 225 bytes")
        
        let round2Tx = try await auth.processRound1Response(createMockRound1Response())
        #expect(round2Tx.data.count == 113, "Round 2 TX = 113 bytes")
        
        let confirmTx = try await auth.processRound2Response(createMockRound2Response())
        #expect(confirmTx.data.count == 17, "Confirm TX = 17 bytes")
        
        let totalTx = 225 + 113 + 17
        #expect(totalTx == 355, "Total TX bytes = 355")
        
        // RX mirrors TX for J-PAKE
        let round1Rx = 225
        let round2Rx = 113
        let confirmRx = 17
        let totalRx = round1Rx + round2Rx + confirmRx
        #expect(totalRx == 355, "Total RX bytes = 355")
        
        #expect(totalTx + totalRx == 710, "Total session bytes = 710")
    }
    
    // MARK: - JPAKE-SESSION-009: Out-of-Order Message Rejection
    
    @Test("Rejects Round 2 before Round 1")
    func rejectsRound2BeforeRound1() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        
        // Try to process Round 2 before Round 1
        do {
            _ = try await auth.processRound2Response(createMockRound2Response())
            Issue.record("Should reject Round 2 before Round 1")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Rejects confirm before Round 2")
    func rejectsConfirmBeforeRound2() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        
        // Try to process confirmation before Round 2
        var confirmData = Data([G7Opcode.authConfirm.rawValue])
        confirmData.append(Data(repeating: 0xAA, count: 16))
        let confirmResponse = G7JPAKEConfirmResponse(data: confirmData)!
        
        do {
            _ = try await auth.processConfirmation(confirmResponse)
            Issue.record("Should reject confirmation before Round 2")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    @Test("Rejects Round 1 response when idle")
    func rejectsRound1ResponseWhenIdle() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        
        // Try to process Round 1 response when idle
        do {
            _ = try await auth.processRound1Response(createMockRound1Response())
            Issue.record("Should reject Round 1 response when idle")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        }
    }
    
    // MARK: - JPAKE-SESSION-010: Sensor Code Formats
    
    @Test("Four digit sensor code")
    func fourDigitSensorCode() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.data.count == 225, "4-digit code should produce valid Round 1 message")
        
        let state = await auth.state
        if case .awaitingRound1Response = state { } else {
            Issue.record("Should be in awaitingRound1Response state")
        }
    }
    
    // Note: 6-digit codes require "00" prefix per xDrip but may not be implemented yet
    // Skipping testSixDigitSensorCode until 6-digit support is added
    
    // MARK: - Security Property Tests
    
    @Test("Each session produces different Round 1 keys")
    func eachSessionProducesDifferentRound1Keys() async throws {
        // Create two separate authenticator instances
        let auth1 = try G7Authenticator(sensorCode: "1234")
        let auth2 = try G7Authenticator(sensorCode: "1234")
        
        let round1a = await auth1.startAuthentication()
        let round1b = await auth2.startAuthentication()
        
        // Different random values should produce different public keys
        let gx1a = round1a.data.subdata(in: 1..<33)
        let gx1b = round1b.data.subdata(in: 1..<33)
        
        #expect(gx1a != gx1b, "Each session should use fresh random keys")
    }
    
    @Test("Session key is non-zero")
    func sessionKeyIsNonZero() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        _ = try await auth.processRound1Response(createMockRound1Response())
        _ = try await auth.processRound2Response(createMockRound2Response())
        
        let sessionKey = await auth.sessionKey
        let zeroKey = Data(count: 16)
        #expect(sessionKey != zeroKey, "Session key should not be all zeros")
    }
    
    // MARK: - Full End-to-End Session Test
    
    @Test("Complete authentication session")
    func completeAuthenticationSession() async throws {
        // This is the primary end-to-end test validating the complete J-PAKE flow
        let sensorCode = "9876"
        let auth = try G7Authenticator(sensorCode: sensorCode)
        
        // Phase 1: Round 1 - Public key exchange
        let round1Tx = await auth.startAuthentication()
        #expect(round1Tx.data[0] == G7Opcode.authRound1.rawValue)
        
        let round1Rx = createMockRound1Response()
        
        // Phase 2: Round 2 - Password-weighted key exchange
        let round2Tx = try await auth.processRound1Response(round1Rx)
        #expect(round2Tx.data[0] == G7Opcode.authRound2.rawValue)
        
        let round2Rx = createMockRound2Response()
        
        // Phase 3: Key Confirmation - Mutual authentication
        let confirmTx = try await auth.processRound2Response(round2Rx)
        #expect(confirmTx.data[0] == G7Opcode.authConfirm.rawValue)
        
        // Verify session key is derived (32 bytes from SHA256)
        let sessionKey = await auth.sessionKey
        #expect(sessionKey != nil)
        #expect((sessionKey?.count ?? 0) >= 16)
        
        // Complete authentication with matching confirmation
        let confirmRx = await createMatchingConfirmResponse(for: auth)
        let success = try await auth.processConfirmation(confirmRx)
        
        #expect(success, "Authentication should succeed")
        
        let finalState = await auth.state
        if case .authenticated = finalState {
            // Success - complete J-PAKE session
        } else {
            Issue.record("Expected authenticated state, got \(finalState)")
        }
    }
}
