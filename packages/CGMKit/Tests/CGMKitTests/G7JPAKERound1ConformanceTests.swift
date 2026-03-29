// SPDX-License-Identifier: MIT
//
// G7JPAKERound1ConformanceTests.swift
// CGMKitTests
//
// Conformance tests for J-PAKE Round 1 vectors.
// Validates message format, ZKP structure, and EC operations per SESSION-G7-001b.
//
// Trace: SESSION-G7-001b, PRD-008 REQ-BLE-008

import Testing
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import CGMKit

@Suite("G7JPAKERound1ConformanceTests", .serialized)
struct G7JPAKERound1ConformanceTests {
    
    // MARK: - Fixture Data
    
    /// Fixture JSON path for validation
    static let fixtureSessionID = "SESSION-G7-001b"
    
    // MARK: - JPAKE-R1-001: Round 1 Message Structure
    
    @Test("Round 1 message has correct opcode")
    func round1MessageHasCorrectOpcode() async throws {
        let auth = try G7Authenticator(sensorCode: "1234")
        let round1 = await auth.startAuthentication()
        
        let data = round1.data
        #expect(data[0] == G7Opcode.authRound1.rawValue, "First byte should be AuthRound1 opcode (0x02)")
        #expect(data[0] == 0x02, "AuthRound1 opcode should be 0x02")
    }
    
    @Test("Round 1 message total length")
    func round1MessageTotalLength() async throws {
        let auth = try G7Authenticator(sensorCode: "5678")
        let round1 = await auth.startAuthentication()
        
        let data = round1.data
        // opcode(1) + gx1(32) + gx2(32) + zkp1(80) + zkp2(80) = 225
        #expect(data.count == 225, "Round 1 message should be 225 bytes")
    }
    
    @Test("Round 1 public key lengths")
    func round1PublicKeyLengths() async throws {
        let auth = try G7Authenticator(sensorCode: "9012")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.gx1.count == 32, "gx1 should be 32 bytes (P-256 X coordinate)")
        #expect(round1.gx2.count == 32, "gx2 should be 32 bytes (P-256 X coordinate)")
    }
    
    // MARK: - JPAKE-R1-002: ZKP Structure Validation
    
    @Test("ZKP commitment length")
    func zkpCommitmentLength() async throws {
        let auth = try G7Authenticator(sensorCode: "1111")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.zkp1.commitment.count == 32, "ZKP commitment should be 32 bytes")
        #expect(round1.zkp2.commitment.count == 32, "ZKP commitment should be 32 bytes")
    }
    
    @Test("ZKP challenge length")
    func zkpChallengeLength() async throws {
        let auth = try G7Authenticator(sensorCode: "2222")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.zkp1.challenge.count == 16, "ZKP challenge should be 16 bytes (truncated hash)")
        #expect(round1.zkp2.challenge.count == 16, "ZKP challenge should be 16 bytes (truncated hash)")
    }
    
    @Test("ZKP response length")
    func zkpResponseLength() async throws {
        let auth = try G7Authenticator(sensorCode: "3333")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.zkp1.response.count == 32, "ZKP response should be 32 bytes (scalar mod n)")
        #expect(round1.zkp2.response.count == 32, "ZKP response should be 32 bytes (scalar mod n)")
    }
    
    @Test("ZKP total serialized length")
    func zkpTotalSerializedLength() async throws {
        let auth = try G7Authenticator(sensorCode: "4444")
        let round1 = await auth.startAuthentication()
        
        #expect(round1.zkp1.data.count == 80, "Serialized ZKP should be 80 bytes")
        #expect(round1.zkp2.data.count == 80, "Serialized ZKP should be 80 bytes")
    }
    
    // MARK: - JPAKE-R1-003: Public Key Randomness
    
    @Test("Public key randomness across instances")
    func publicKeyRandomnessAcrossInstances() async throws {
        let auth1 = try G7Authenticator(sensorCode: "5555")
        let auth2 = try G7Authenticator(sensorCode: "5555")
        
        let round1a = await auth1.startAuthentication()
        let round1b = await auth2.startAuthentication()
        
        #expect(round1a.gx1 != round1b.gx1, "gx1 should be randomly generated each time")
        #expect(round1a.gx2 != round1b.gx2, "gx2 should be randomly generated each time")
    }
    
    @Test("ZKP randomness across instances")
    func zkpRandomnessAcrossInstances() async throws {
        let auth1 = try G7Authenticator(sensorCode: "6666")
        let auth2 = try G7Authenticator(sensorCode: "6666")
        
        let round1a = await auth1.startAuthentication()
        let round1b = await auth2.startAuthentication()
        
        // ZKP commitments should also be random (from random nonce)
        #expect(round1a.zkp1.commitment != round1b.zkp1.commitment, "ZKP commitments should be random")
        #expect(round1a.zkp2.commitment != round1b.zkp2.commitment, "ZKP commitments should be random")
    }
    
    // MARK: - JPAKE-R1-004: Round 1 Response Parsing
    
    @Test("Round 1 response parsing with valid data")
    func round1ResponseParsingWithValidData() {
        // Build valid Round 1 response
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x11, count: 32))  // gx3
        data.append(Data(repeating: 0x22, count: 32))  // gx4
        data.append(Data(repeating: 0x33, count: 80))  // zkp3
        data.append(Data(repeating: 0x44, count: 80))  // zkp4
        
        let response = G7JPAKERound1Response(data: data)
        
        #expect(response != nil, "Should parse valid Round 1 response")
        #expect(response?.gx3.count == 32, "gx3 should be 32 bytes")
        #expect(response?.gx4.count == 32, "gx4 should be 32 bytes")
        #expect(response?.zkp3.data.count == 80, "zkp3 should be 80 bytes")
        #expect(response?.zkp4.data.count == 80, "zkp4 should be 80 bytes")
    }
    
    @Test("Round 1 response parsing rejects wrong opcode")
    func round1ResponseParsingRejectsWrongOpcode() {
        var data = Data([0xFF])  // Wrong opcode
        data.append(Data(repeating: 0x00, count: 224))
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response == nil, "Should reject wrong opcode")
    }
    
    @Test("Round 1 response parsing rejects short data")
    func round1ResponseParsingRejectsShortData() {
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0x00, count: 100))  // Too short
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response == nil, "Should reject data shorter than 225 bytes")
    }
    
    @Test("Round 1 response minimum length")
    func round1ResponseMinimumLength() {
        // Exact minimum: opcode(1) + gx3(32) + gx4(32) + zkp3(80) + zkp4(80) = 225
        var data = Data([G7Opcode.authRound1.rawValue])
        data.append(Data(repeating: 0xAA, count: 32))  // gx3
        data.append(Data(repeating: 0xBB, count: 32))  // gx4
        data.append(Data(repeating: 0xCC, count: 80))  // zkp3
        data.append(Data(repeating: 0xDD, count: 80))  // zkp4
        
        #expect(data.count == 225, "Valid response should be exactly 225 bytes")
        
        let response = G7JPAKERound1Response(data: data)
        #expect(response != nil, "Should parse 225-byte response")
    }
    
    // MARK: - JPAKE-R1-005: ZKP Parsing
    
    @Test("ZKP parsing from data")
    func zkpParsingFromData() {
        var data = Data()
        data.append(Data(repeating: 0xAA, count: 32))  // commitment
        data.append(Data(repeating: 0xBB, count: 16))  // challenge
        data.append(Data(repeating: 0xCC, count: 32))  // response
        
        let zkp = G7ZKProof(data: data)
        
        #expect(zkp != nil)
        #expect(zkp?.commitment == Data(repeating: 0xAA, count: 32))
        #expect(zkp?.challenge == Data(repeating: 0xBB, count: 16))
        #expect(zkp?.response == Data(repeating: 0xCC, count: 32))
    }
    
    @Test("ZKP serialization roundtrip")
    func zkpSerializationRoundtrip() {
        let commitment = Data(repeating: 0x11, count: 32)
        let challenge = Data(repeating: 0x22, count: 16)
        let response = Data(repeating: 0x33, count: 32)
        
        let original = G7ZKProof(commitment: commitment, challenge: challenge, response: response)
        let serialized = original.data
        let parsed = G7ZKProof(data: serialized)
        
        #expect(parsed?.commitment == original.commitment)
        #expect(parsed?.challenge == original.challenge)
        #expect(parsed?.response == original.response)
    }
    
    @Test("ZKP parsing rejects short data")
    func zkpParsingRejectsShortData() {
        let shortData = Data(repeating: 0x00, count: 50)  // Less than 80 bytes
        let zkp = G7ZKProof(data: shortData)
        #expect(zkp == nil, "Should reject data shorter than 80 bytes")
    }
    
    // MARK: - JPAKE-R1-006: Key Pair Generation
    
    @Test("Key pair private key length")
    func keyPairPrivateKeyLength() {
        let keyPair = JPAKEKeyPair()
        #expect(keyPair.privateKeyBytes.count == 32, "Private key should be 32 bytes")
    }
    
    @Test("Key pair raw public key length")
    func keyPairRawPublicKeyLength() {
        let keyPair = JPAKEKeyPair()
        #expect(keyPair.rawPublicKey.count == 64, "Raw public key should be 64 bytes (X || Y)")
    }
    
    @Test("Key pair uncompressed public key format")
    func keyPairUncompressedPublicKeyFormat() {
        let keyPair = JPAKEKeyPair()
        #expect(keyPair.uncompressedPublicKey.count == 65, "Uncompressed public key should be 65 bytes")
        #expect(keyPair.uncompressedPublicKey[0] == 0x04, "Uncompressed point starts with 0x04")
    }
    
    @Test("Key pair XY coordinates")
    func keyPairXYCoordinates() {
        let keyPair = JPAKEKeyPair()
        #expect(keyPair.publicKeyX.count == 32, "X coordinate should be 32 bytes")
        #expect(keyPair.publicKeyY.count == 32, "Y coordinate should be 32 bytes")
        
        // Raw = X || Y
        #expect(keyPair.publicKeyX == Data(keyPair.rawPublicKey.prefix(32)))
        #expect(keyPair.publicKeyY == Data(keyPair.rawPublicKey.suffix(32)))
    }
    
    @Test("Key pair recovery from private key")
    func keyPairRecoveryFromPrivateKey() throws {
        let original = JPAKEKeyPair()
        let recovered = try JPAKEKeyPair(privateKeyBytes: original.privateKeyBytes)
        
        #expect(recovered.rawPublicKey == original.rawPublicKey, "Same private key should yield same public key")
    }
    
    // MARK: - JPAKE-R1-007: Password to Scalar Conversion
    
    @Test("Password to scalar 4 digit")
    func passwordToScalar4Digit() {
        let scalar = ScalarOperations.passwordToScalar("1234")
        #expect(scalar.count == 4, "4-digit password should yield 4-byte scalar")
        #expect(scalar == Data([0x31, 0x32, 0x33, 0x34]), "Should be UTF-8 bytes of '1234'")
    }
    
    @Test("Password to scalar 4 digit zeros")
    func passwordToScalar4DigitZeros() {
        let scalar = ScalarOperations.passwordToScalar("0000")
        #expect(scalar == Data([0x30, 0x30, 0x30, 0x30]), "Should be UTF-8 bytes of '0000'")
    }
    
    @Test("Password to scalar 4 digit nines")
    func passwordToScalar4DigitNines() {
        let scalar = ScalarOperations.passwordToScalar("9999")
        #expect(scalar == Data([0x39, 0x39, 0x39, 0x39]), "Should be UTF-8 bytes of '9999'")
    }
    
    @Test("Password to scalar 6 digit")
    func passwordToScalar6Digit() {
        let scalar = ScalarOperations.passwordToScalar("123456")
        #expect(scalar.count == 8, "6-digit password should yield 8-byte scalar (with '00' prefix)")
        #expect(scalar == Data([0x30, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
                       "Should be '00' + UTF-8 bytes of '123456' per xDrip format")
    }
    
    // MARK: - JPAKE-R1-008: Message Field Extraction
    
    @Test("Round 1 message field offsets")
    func round1MessageFieldOffsets() async throws {
        let auth = try G7Authenticator(sensorCode: "7777")
        let round1 = await auth.startAuthentication()
        let data = round1.data
        
        // Verify field offsets match fixture spec
        // opcode at offset 0 (1 byte)
        #expect(data[0] == 0x02, "Opcode at offset 0")
        
        // gx1 at offset 1 (32 bytes)
        let gx1 = data.subdata(in: 1..<33)
        #expect(gx1.count == 32, "gx1 at offset 1, length 32")
        
        // gx2 at offset 33 (32 bytes)
        let gx2 = data.subdata(in: 33..<65)
        #expect(gx2.count == 32, "gx2 at offset 33, length 32")
        
        // zkp1 at offset 65 (80 bytes)
        let zkp1Data = data.subdata(in: 65..<145)
        #expect(zkp1Data.count == 80, "zkp1 at offset 65, length 80")
        
        // zkp2 at offset 145 (80 bytes)
        let zkp2Data = data.subdata(in: 145..<225)
        #expect(zkp2Data.count == 80, "zkp2 at offset 145, length 80")
    }
    
    // MARK: - P-256 Constants Tests
    
    @Test("P256 field size")
    func p256FieldSize() {
        #expect(P256Constants.fieldSize == 32)
    }
    
    @Test("P256 point sizes")
    func p256PointSizes() {
        #expect(P256Constants.uncompressedPointSize == 65)
        #expect(P256Constants.compressedPointSize == 33)
    }
    
    @Test("P256 packet size")
    func p256PacketSize() {
        #expect(P256Constants.packetSize == 160, "J-PAKE packet size = 5 * field_size")
    }
    
    @Test("Curve order length")
    func curveOrderLength() {
        #expect(ScalarOperations.curveOrder.count == 32, "Curve order should be 32 bytes")
    }
    
    // MARK: - EC Point Parsing Tests
    
    @Test("Parse uncompressed point")
    func parseUncompressedPoint() {
        let keyPair = JPAKEKeyPair()
        let uncompressed = keyPair.uncompressedPublicKey
        
        let parsed = ECPointOperations.parseUncompressedPoint(uncompressed)
        #expect(parsed != nil, "Should parse valid uncompressed point")
        #expect(parsed?.rawRepresentation == keyPair.rawPublicKey)
    }
    
    @Test("Parse raw point")
    func parseRawPoint() {
        let keyPair = JPAKEKeyPair()
        let raw = keyPair.rawPublicKey
        
        let parsed = ECPointOperations.parseRawPoint(raw)
        #expect(parsed != nil, "Should parse valid raw point (64 bytes)")
        #expect(parsed?.rawRepresentation == raw)
    }
    
    @Test("Reject invalid point data")
    func rejectInvalidPointData() {
        // Too short for uncompressed
        #expect(ECPointOperations.parseUncompressedPoint(Data(repeating: 0x04, count: 32)) == nil)
        
        // Wrong format byte
        var wrongFormat = Data(repeating: 0x00, count: 65)
        wrongFormat[0] = 0x05
        #expect(ECPointOperations.parseUncompressedPoint(wrongFormat) == nil)
    }
    
    // MARK: - State Transition Tests
    
    @Test("State transition to awaiting Round 1 response")
    func stateTransitionToAwaitingRound1Response() async throws {
        let auth = try G7Authenticator(sensorCode: "8888")
        
        // Initially idle
        var state = await auth.state
        if case .idle = state { } else {
            Issue.record("Expected idle state initially")
        }
        
        // After starting auth, should be awaiting Round 1 response
        _ = await auth.startAuthentication()
        state = await auth.state
        if case .awaitingRound1Response = state { } else {
            Issue.record("Expected awaitingRound1Response state after startAuthentication()")
        }
    }
    
    // MARK: - Hash to Scalar Tests
    
    @Test("Hash to scalar length")
    func hashToScalarLength() {
        let input = Data("test input".utf8)
        let scalar = ScalarOperations.hashToScalar(input)
        #expect(scalar.count == 32, "Hash to scalar should produce 32 bytes")
    }
    
    @Test("Hash to scalar deterministic")
    func hashToScalarDeterministic() {
        let input = Data("same input".utf8)
        let scalar1 = ScalarOperations.hashToScalar(input)
        let scalar2 = ScalarOperations.hashToScalar(input)
        #expect(scalar1 == scalar2, "Same input should produce same scalar")
    }
    
    @Test("Hash to scalar different inputs")
    func hashToScalarDifferentInputs() {
        let scalar1 = ScalarOperations.hashToScalar(Data("input1".utf8))
        let scalar2 = ScalarOperations.hashToScalar(Data("input2".utf8))
        #expect(scalar1 != scalar2, "Different inputs should produce different scalars")
    }
    
    // MARK: - Random Scalar Tests
    
    @Test("Random scalar length")
    func randomScalarLength() {
        let scalar = ScalarOperations.randomScalar()
        #expect(scalar.count == 32, "Random scalar should be 32 bytes")
    }
    
    @Test("Random scalar uniqueness")
    func randomScalarUniqueness() {
        let scalar1 = ScalarOperations.randomScalar()
        let scalar2 = ScalarOperations.randomScalar()
        #expect(scalar1 != scalar2, "Random scalars should be unique")
    }
}
