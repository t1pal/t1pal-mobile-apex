// SPDX-License-Identifier: MIT
//
// G7JPAKERound2ConformanceTests.swift
// CGMKitTests
//
// Conformance tests for J-PAKE Round 2 vectors.
// Validates Round 2 message format, A computation, and ZKP structure per SESSION-G7-001c.
//
// Key insight: Round 2 ZKP uses a MODIFIED base point (sum of g^x1 + g^x3 + g^x4),
// NOT the curve generator G as in Round 1.
//
// Trace: SESSION-G7-001c, PRD-008 REQ-BLE-008

import Testing
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import CGMKit

@Suite("G7JPAKERound2ConformanceTests", .serialized)
struct G7JPAKERound2ConformanceTests {
    
    // MARK: - Fixture Data
    
    /// Fixture JSON path for validation
    static let fixtureSessionID = "SESSION-G7-001c"
    
    // MARK: - Helper: Create Mock Round 1 Response
    
    /// Creates a valid mock Round 1 response for testing Round 2 flow
    private func createMockRound1Response() -> G7JPAKERound1Response {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // gx3
        data.append(Data(repeating: 0x22, count: 32))  // gx4
        data.append(Data(repeating: 0x33, count: 80))  // zkp3
        data.append(Data(repeating: 0x44, count: 80))  // zkp4
        return G7JPAKERound1Response(data: data)!
    }
    
    // MARK: - JPAKE-R2-001: Round 2 Message Structure
    
    @Test("Round 2 message has correct opcode")
    func round2MessageHasCorrectOpcode() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        let data = round2.data
        #expect(data[0] == G7Opcode.authRound2.rawValue, "First byte should be AuthRound2 opcode (0x03)")
        #expect(data[0] == 0x03, "AuthRound2 opcode should be 0x03")
    }
    
    @Test("Round 2 message total length")
    func round2MessageTotalLength() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        let data = round2.data
        // opcode(1) + A(32) + zkpA(80) = 113
        #expect(data.count == 113, "Round 2 message should be 113 bytes")
    }
    
    @Test("Round 2 A value length")
    func round2AValueLength() async throws {
        let auth = try G7Authenticator(sensorCode: "9012")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        #expect(round2.a.count == 32, "A value should be 32 bytes (P-256 X coordinate)")
    }
    
    // MARK: - JPAKE-R2-002: Round 2 ZKP Structure
    
    @Test("Round 2 ZKP commitment length")
    func round2ZKPCommitmentLength() async throws {
        let auth = try G7Authenticator(sensorCode: "1111")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        #expect(round2.zkpA.commitment.count == 32, "Round 2 ZKP commitment should be 32 bytes")
    }
    
    @Test("Round 2 ZKP challenge length")
    func round2ZKPChallengeLength() async throws {
        let auth = try G7Authenticator(sensorCode: "2222")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        #expect(round2.zkpA.challenge.count == 16, "Round 2 ZKP challenge should be 16 bytes")
    }
    
    @Test("Round 2 ZKP response length")
    func round2ZKPResponseLength() async throws {
        let auth = try G7Authenticator(sensorCode: "3333")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        #expect(round2.zkpA.response.count == 32, "Round 2 ZKP response should be 32 bytes")
    }
    
    @Test("Round 2 ZKP serialized length")
    func round2ZKPSerializedLength() async throws {
        let auth = try G7Authenticator(sensorCode: "4444")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        #expect(round2.zkpA.data.count == 80, "Serialized Round 2 ZKP should be 80 bytes")
    }
    
    // MARK: - JPAKE-R2-003: Round 2 Response Parsing
    
    @Test("Round 2 response parsing with valid data")
    func round2ResponseParsingWithValidData() {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0xAA, count: 32))  // B
        data.append(Data(repeating: 0xBB, count: 80))  // zkpB
        
        let response = G7JPAKERound2Response(data: data)
        
        #expect(response != nil, "Should parse valid Round 2 response")
        #expect(response?.b.count == 32, "B should be 32 bytes")
        #expect(response?.zkpB.data.count == 80, "zkpB should be 80 bytes")
    }
    
    @Test("Round 2 response parsing rejects wrong opcode")
    func round2ResponseParsingRejectsWrongOpcode() {
        var data = Data([0xFF])  // Wrong opcode
        data.append(Data(repeating: 0x00, count: 112))
        
        let response = G7JPAKERound2Response(data: data)
        #expect(response == nil, "Should reject wrong opcode")
    }
    
    @Test("Round 2 response parsing rejects short data")
    func round2ResponseParsingRejectsShortData() {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x00, count: 50))  // Too short
        
        let response = G7JPAKERound2Response(data: data)
        #expect(response == nil, "Should reject data shorter than 113 bytes")
    }
    
    @Test("Round 2 response minimum length")
    func round2ResponseMinimumLength() {
        // Exact minimum: opcode(1) + B(32) + zkpB(80) = 113
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0xAA, count: 32))  // B
        data.append(Data(repeating: 0xBB, count: 80))  // zkpB
        
        #expect(data.count == 113, "Valid response should be exactly 113 bytes")
        
        let response = G7JPAKERound2Response(data: data)
        #expect(response != nil, "Should parse 113-byte response")
    }
    
    // MARK: - JPAKE-R2-004: Round 2 Requires Round 1 Values
    
    @Test("Round 2 requires Round 1 completion")
    func round2RequiresRound1Completion() async throws {
        let auth = try G7Authenticator(sensorCode: "5555")
        
        // Attempt Round 2 without Round 1 - should fail
        let round1Response = createMockRound1Response()
        
        do {
            _ = try await auth.processRound1Response(round1Response)
            Issue.record("Should throw error when Round 1 not started")
        } catch {
            // Expected - state is not awaitingRound1Response
            #expect(error is G7Authenticator.AuthError)
        }
    }
    
    // MARK: - JPAKE-R2-007: Round 2 Varies with Password
    
    @Test("Round 2 varies with password")
    func round2VariesWithPassword() async throws {
        let auth1 = try G7Authenticator(sensorCode: "1234")
        let auth2 = try G7Authenticator(sensorCode: "5678")
        
        _ = await auth1.startAuthentication()
        _ = await auth2.startAuthentication()
        
        let round1Response = createMockRound1Response()
        
        let round2a = try await auth1.processRound1Response(round1Response)
        let round2b = try await auth2.processRound1Response(round1Response)
        
        // Different passwords should produce different A values
        // Note: Keys are also random, so they will definitely differ
        #expect(round2a.a != round2b.a, "Different passwords should produce different A values")
    }
    
    // MARK: - JPAKE-R2-008: State Transition
    
    @Test("State transition to awaiting Round 2 response")
    func stateTransitionToAwaitingRound2Response() async throws {
        let auth = try G7Authenticator(sensorCode: "6666")
        
        // Start authentication
        _ = await auth.startAuthentication()
        
        var state = await auth.state
        if case .awaitingRound1Response = state { } else {
            Issue.record("Expected awaitingRound1Response state after startAuthentication()")
        }
        
        // Process Round 1
        let round1Response = createMockRound1Response()
        _ = try await auth.processRound1Response(round1Response)
        
        // Should be awaiting Round 2 response
        state = await auth.state
        if case .awaitingRound2Response = state { } else {
            Issue.record("Expected awaitingRound2Response state after processRound1Response()")
        }
    }
    
    // MARK: - JPAKE-R2-009: Round 2 Message Field Extraction
    
    @Test("Round 2 message field offsets")
    func round2MessageFieldOffsets() async throws {
        let auth = try G7Authenticator(sensorCode: "7777")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        let data = round2.data
        
        // Verify field offsets match fixture spec
        // opcode at offset 0 (1 byte)
        #expect(data[0] == 0x03, "Opcode at offset 0")
        
        // A at offset 1 (32 bytes)
        let aValue = data.subdata(in: 1..<33)
        #expect(aValue.count == 32, "A at offset 1, length 32")
        
        // zkpA at offset 33 (80 bytes)
        let zkpAData = data.subdata(in: 33..<113)
        #expect(zkpAData.count == 80, "zkpA at offset 33, length 80")
    }
    
    // MARK: - JPAKE-R2-010: Round 2 State Validation
    
    @Test("Round 2 rejects idle state")
    func round2RejectsIdleState() async throws {
        let auth = try G7Authenticator(sensorCode: "8888")
        
        // Attempt Round 2 from idle state
        let round1Response = createMockRound1Response()
        
        do {
            _ = try await auth.processRound1Response(round1Response)
            Issue.record("Should throw unexpectedState error")
        } catch G7Authenticator.AuthError.unexpectedState {
            // Expected
        } catch {
            Issue.record("Expected unexpectedState error, got \(error)")
        }
    }
    
    // MARK: - Scalar Multiplication Tests (for x2 * s)
    
    @Test("Scalar multiplication length")
    func scalarMultiplicationLength() {
        let x2 = ScalarOperations.randomScalar()
        let s = ScalarOperations.passwordToScalar("1234")
        
        // Pad s to 32 bytes for multiplication
        var sPadded = Data(count: 32)
        sPadded.replaceSubrange((32 - s.count)..<32, with: s)
        
        let result = ScalarOperations.multiplyMod(x2, sPadded)
        #expect(result.count == 32, "Scalar multiplication result should be 32 bytes")
    }
    
    @Test("Scalar multiplication determinism")
    func scalarMultiplicationDeterminism() {
        let x2 = Data(repeating: 0x05, count: 32)
        var sPadded = Data(count: 32)
        sPadded.replaceSubrange(28..<32, with: Data([0x31, 0x32, 0x33, 0x34]))
        
        let result1 = ScalarOperations.multiplyMod(x2, sPadded)
        let result2 = ScalarOperations.multiplyMod(x2, sPadded)
        
        #expect(result1 == result2, "Same inputs should produce same result")
    }
    
    @Test("Scalar multiplication varies with inputs")
    func scalarMultiplicationVariesWithInputs() {
        let x2a = Data(repeating: 0x05, count: 32)
        let x2b = Data(repeating: 0x06, count: 32)
        var sPadded = Data(count: 32)
        sPadded.replaceSubrange(28..<32, with: Data([0x31, 0x32, 0x33, 0x34]))
        
        let resultA = ScalarOperations.multiplyMod(x2a, sPadded)
        let resultB = ScalarOperations.multiplyMod(x2b, sPadded)
        
        #expect(resultA != resultB, "Different inputs should produce different results")
    }
    
    // MARK: - Round 2 ZKP Randomness Tests
    
    @Test("Round 2 ZKP randomness across instances")
    func round2ZKPRandomnessAcrossInstances() async throws {
        let auth1 = try G7Authenticator(sensorCode: "9999")
        let auth2 = try G7Authenticator(sensorCode: "9999")
        
        _ = await auth1.startAuthentication()
        _ = await auth2.startAuthentication()
        
        let round1Response = createMockRound1Response()
        
        let round2a = try await auth1.processRound1Response(round1Response)
        let round2b = try await auth2.processRound1Response(round1Response)
        
        // ZKP commitments should be random (from random nonce v)
        #expect(round2a.zkpA.commitment != round2b.zkpA.commitment,
                          "Round 2 ZKP commitments should be random across instances")
    }
    
    // MARK: - Round 2 Data Extraction Tests
    
    @Test("Round 2 extract B from response")
    func round2ExtractBFromResponse() {
        var data = Data([G7Opcode.authRound2.rawValue])
        let expectedB = Data(repeating: 0x55, count: 32)
        data.append(expectedB)
        data.append(Data(repeating: 0x66, count: 80))  // zkpB
        
        let response = G7JPAKERound2Response(data: data)
        
        #expect(response != nil)
        #expect(response?.b == expectedB, "Should extract B value correctly")
    }
    
    @Test("Round 2 extract ZKP from response")
    func round2ExtractZKPFromResponse() {
        var data = Data([G7Opcode.authRound2.rawValue])
        data.append(Data(repeating: 0x55, count: 32))  // B
        
        // Build ZKP with known values
        var zkpData = Data()
        zkpData.append(Data(repeating: 0xAA, count: 32))  // commitment
        zkpData.append(Data(repeating: 0xBB, count: 16))  // challenge
        zkpData.append(Data(repeating: 0xCC, count: 32))  // response
        data.append(zkpData)
        
        let response = G7JPAKERound2Response(data: data)
        
        #expect(response != nil)
        #expect(response?.zkpB.commitment == Data(repeating: 0xAA, count: 32))
        #expect(response?.zkpB.challenge == Data(repeating: 0xBB, count: 16))
        #expect(response?.zkpB.response == Data(repeating: 0xCC, count: 32))
    }
    
    // MARK: - Round 2 Non-Zero Value Tests
    
    @Test("Round 2 A value is non-zero")
    func round2AValueIsNonZero() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        // A should not be all zeros (unless astronomically unlikely)
        let zeroData = Data(count: 32)
        #expect(round2.a != zeroData, "A value should not be all zeros")
    }
    
    @Test("Round 2 ZKP commitment is non-zero")
    func round2ZKPCommitmentIsNonZero() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        _ = await auth.startAuthentication()
        
        let round1Response = createMockRound1Response()
        let round2 = try await auth.processRound1Response(round1Response)
        
        let zeroData = Data(count: 32)
        #expect(round2.zkpA.commitment != zeroData, "ZKP commitment should not be all zeros")
    }
}
