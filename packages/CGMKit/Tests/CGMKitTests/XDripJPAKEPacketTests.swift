// SPDX-License-Identifier: MIT
//
// XDripJPAKEPacketTests.swift
// CGMKitTests
//
// Conformance tests for xDrip-compatible J-PAKE packet format (160 bytes).
// Validates serialization matches externals/xDrip/libkeks/Packet.java
//
// Trace: G7-FID-001, PRD-008 REQ-BLE-008

import Testing
import Foundation

@testable import CGMKit

@Suite("XDripJPAKEPacketTests")
struct XDripJPAKEPacketTests {
    
    // MARK: - G7-FID-001a: Packet Size Constants
    
    @Test("Packet size is 160 bytes")
    func packetSizeIs160Bytes() {
        #expect(XDripJPAKEPacket.size == 160, "xDrip packet size should be 160 bytes (5 * 32)")
        #expect(P256Constants.packetSize == 160, "P256 constants should define 160-byte packet")
    }
    
    @Test("Field size is 32 bytes")
    func fieldSizeIs32Bytes() {
        #expect(P256Constants.fieldSize == 32, "Field size should be 32 bytes")
    }
    
    // MARK: - G7-FID-001b: Packet Structure
    
    @Test("Packet component sizes")
    func packetComponentSizes() {
        let proof = Data(repeating: 0x11, count: 32)
        let publicKey = Data(repeating: 0x22, count: 64)
        let commitment = Data(repeating: 0x33, count: 64)
        
        let packet = XDripJPAKEPacket(proof: proof, publicKey: publicKey, commitment: commitment)
        
        #expect(packet.proof.count == 32, "Proof should be 32 bytes")
        #expect(packet.publicKey.count == 64, "Public key should be 64 bytes")
        #expect(packet.commitment.count == 64, "Commitment should be 64 bytes")
        #expect(packet.isValid)
    }
    
    @Test("Packet serialization size")
    func packetSerializationSize() {
        let proof = Data(repeating: 0xAA, count: 32)
        let publicKeyX = Data(repeating: 0xBB, count: 32)
        let publicKeyY = Data(repeating: 0xCC, count: 32)
        let commitmentX = Data(repeating: 0xDD, count: 32)
        let commitmentY = Data(repeating: 0xEE, count: 32)
        
        let packet = XDripJPAKEPacket(
            proof: proof,
            publicKeyX: publicKeyX,
            publicKeyY: publicKeyY,
            commitmentX: commitmentX,
            commitmentY: commitmentY
        )
        
        let data = packet.data
        #expect(data.count == 160, "Serialized packet should be 160 bytes")
    }
    
    // MARK: - G7-FID-001c: Serialization Order
    
    /// Verifies xDrip Packet.java order: publicKey(64) + commitment(64) + proof(32)
    @Test("Serialization matches xDrip order")
    func serializationMatchesXDripOrder() {
        // Create distinct patterns for each field
        let proof = Data(repeating: 0xAA, count: 32)
        let publicKey = Data(repeating: 0xBB, count: 32) + Data(repeating: 0xCC, count: 32)
        let commitment = Data(repeating: 0xDD, count: 32) + Data(repeating: 0xEE, count: 32)
        
        let packet = XDripJPAKEPacket(proof: proof, publicKey: publicKey, commitment: commitment)
        let data = packet.data
        
        // xDrip order: publicKey(64) + commitment(64) + proof(32)
        #expect(data.subdata(in: 0..<32) == Data(repeating: 0xBB, count: 32), "Bytes 0-31: publicKey.x")
        #expect(data.subdata(in: 32..<64) == Data(repeating: 0xCC, count: 32), "Bytes 32-63: publicKey.y")
        #expect(data.subdata(in: 64..<96) == Data(repeating: 0xDD, count: 32), "Bytes 64-95: commitment.x")
        #expect(data.subdata(in: 96..<128) == Data(repeating: 0xEE, count: 32), "Bytes 96-127: commitment.y")
        #expect(data.subdata(in: 128..<160) == Data(repeating: 0xAA, count: 32), "Bytes 128-159: proof")
    }
    
    // MARK: - G7-FID-001d: Parse-Serialize Round Trip
    
    @Test("Parse serialize round trip")
    func parseSerializeRoundTrip() {
        let originalData = Data((0..<160).map { UInt8($0 % 256) })
        
        guard let packet = XDripJPAKEPacket(data: originalData) else {
            Issue.record("Should parse 160-byte data")
            return
        }
        
        let reserialized = packet.data
        #expect(reserialized == originalData, "Round trip should preserve data")
    }
    
    @Test("Parse rejects short data")
    func parseRejectsShortData() {
        let shortData = Data(repeating: 0x00, count: 159)
        #expect(XDripJPAKEPacket(data: shortData) == nil, "Should reject < 160 bytes")
    }
    
    // MARK: - G7-FID-001e: Coordinate Accessors
    
    @Test("Coordinate accessors")
    func coordinateAccessors() {
        let publicKeyX = Data((0..<32).map { UInt8($0) })
        let publicKeyY = Data((32..<64).map { UInt8($0) })
        let commitmentX = Data((64..<96).map { UInt8($0) })
        let commitmentY = Data((96..<128).map { UInt8($0) })
        let proof = Data((128..<160).map { UInt8($0) })
        
        let packet = XDripJPAKEPacket(
            proof: proof,
            publicKeyX: publicKeyX,
            publicKeyY: publicKeyY,
            commitmentX: commitmentX,
            commitmentY: commitmentY
        )
        
        #expect(packet.publicKeyX == publicKeyX)
        #expect(packet.publicKeyY == publicKeyY)
        #expect(packet.commitmentX == commitmentX)
        #expect(packet.commitmentY == commitmentY)
    }
    
    // MARK: - G7-FID-001f: Round 1 Message (2x Packet)
    
    @Test("Round 1 message size")
    func round1MessageSize() {
        let packet1 = XDripJPAKEPacket(
            proof: Data(repeating: 0x11, count: 32),
            publicKey: Data(repeating: 0x22, count: 64),
            commitment: Data(repeating: 0x33, count: 64)
        )
        let packet2 = XDripJPAKEPacket(
            proof: Data(repeating: 0x44, count: 32),
            publicKey: Data(repeating: 0x55, count: 64),
            commitment: Data(repeating: 0x66, count: 64)
        )
        
        let message = XDripJPAKERound1Message(packet1: packet1, packet2: packet2)
        let data = message.data(opcode: 0x02)
        
        // 1 (opcode) + 160 + 160 = 321 bytes
        #expect(data.count == 321, "Round 1 message should be 321 bytes (opcode + 2 packets)")
    }
    
    @Test("Round 1 message opcode")
    func round1MessageOpcode() {
        let packet = XDripJPAKEPacket(
            proof: Data(repeating: 0x00, count: 32),
            publicKey: Data(repeating: 0x00, count: 64),
            commitment: Data(repeating: 0x00, count: 64)
        )
        let message = XDripJPAKERound1Message(packet1: packet, packet2: packet)
        
        let data = message.data(opcode: 0x02)
        #expect(data[0] == 0x02, "First byte should be opcode")
    }
    
    @Test("Round 1 message parse round trip")
    func round1MessageParseRoundTrip() {
        let packet1 = XDripJPAKEPacket(
            proof: Data(repeating: 0xAA, count: 32),
            publicKey: Data(repeating: 0xBB, count: 64),
            commitment: Data(repeating: 0xCC, count: 64)
        )
        let packet2 = XDripJPAKEPacket(
            proof: Data(repeating: 0xDD, count: 32),
            publicKey: Data(repeating: 0xEE, count: 64),
            commitment: Data(repeating: 0xFF, count: 64)
        )
        
        let original = XDripJPAKERound1Message(packet1: packet1, packet2: packet2)
        let serialized = original.data(opcode: 0x02)
        
        guard let parsed = XDripJPAKERound1Message(data: serialized, expectedOpcode: 0x02) else {
            Issue.record("Should parse valid message")
            return
        }
        
        #expect(parsed.packet1.proof == packet1.proof)
        #expect(parsed.packet2.proof == packet2.proof)
    }
    
    // MARK: - G7-FID-002: Round 2/3 Type Aliases
    
    @Test("Round 2 packet type alias")
    func round2PacketTypeAlias() {
        // Round 2 uses same format as Round 1
        let packet: XDripJPAKERound2Packet = XDripJPAKEPacket(
            proof: Data(repeating: 0x22, count: 32),
            publicKey: Data(repeating: 0x33, count: 64),
            commitment: Data(repeating: 0x44, count: 64)
        )
        
        #expect(packet.data.count == 160, "Round 2 packet should be 160 bytes")
        #expect(packet.isValid)
    }
    
    @Test("Round 3 packet type alias")
    func round3PacketTypeAlias() {
        // Round 3 uses same format - contains A value
        let packet: XDripJPAKERound3Packet = XDripJPAKEPacket(
            proof: Data(repeating: 0x55, count: 32),
            publicKey: Data(repeating: 0x66, count: 64),  // A value
            commitment: Data(repeating: 0x77, count: 64)   // ZKP commitment
        )
        
        #expect(packet.data.count == 160, "Round 3 packet should be 160 bytes")
        #expect(packet.isValid)
    }
    
    @Test("All rounds use same packet size")
    func allRoundsUseSamePacketSize() {
        // Verify xDrip protocol: all rounds use 160-byte packets
        #expect(XDripJPAKEPacket.size == 160)
        
        // Type aliases should all resolve to same underlying size
        let r1 = XDripJPAKEPacket(
            proof: Data(count: 32), publicKey: Data(count: 64), commitment: Data(count: 64))
        let r2: XDripJPAKERound2Packet = XDripJPAKEPacket(
            proof: Data(count: 32), publicKey: Data(count: 64), commitment: Data(count: 64))
        let r3: XDripJPAKERound3Packet = XDripJPAKEPacket(
            proof: Data(count: 32), publicKey: Data(count: 64), commitment: Data(count: 64))
        
        #expect(r1.data.count == r2.data.count)
        #expect(r2.data.count == r3.data.count)
    }
    
    // MARK: - G7-FID-003: Key Confirmation Types
    
    @Test("Auth challenge TX message size")
    func authChallengeTxMessageSize() {
        let hash = Data(repeating: 0xAA, count: 8)
        let message = XDripAuthChallengeTxMessage(challengeHash: hash)
        
        #expect(message.data.count == 9, "AuthChallengeTx should be 9 bytes")
        #expect(XDripAuthChallengeTxMessage.size == 9)
    }
    
    @Test("Auth challenge TX message opcode")
    func authChallengeTxMessageOpcode() {
        let hash = Data(repeating: 0xBB, count: 8)
        let message = XDripAuthChallengeTxMessage(challengeHash: hash)
        
        #expect(message.data[0] == 0x04, "Opcode should be 0x04")
        #expect(XDripAuthChallengeTxMessage.opcode == 0x04)
    }
    
    @Test("Auth challenge TX message round trip")
    func authChallengeTxMessageRoundTrip() {
        let originalHash = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        let original = XDripAuthChallengeTxMessage(challengeHash: originalHash)
        let serialized = original.data
        
        guard let parsed = XDripAuthChallengeTxMessage(data: serialized) else {
            Issue.record("Should parse valid message")
            return
        }
        
        #expect(parsed.challengeHash == originalHash)
    }
    
    @Test("Auth challenge TX message from challenge and key")
    func authChallengeTxMessageFromChallengeAndKey() {
        // Test computing hash from challenge and key
        let challenge = Data(repeating: 0x12, count: 8)
        let sessionKey = Data(repeating: 0x34, count: 16)
        
        let message = XDripAuthChallengeTxMessage(challenge: challenge, sessionKey: sessionKey)
        
        #expect(message.challengeHash.count == 8, "Hash should be 8 bytes")
        #expect(message.data.count == 9, "Message should be 9 bytes")
    }
    
    @Test("Challenge extraction")
    func challengeExtraction() {
        // Simulate auth response with challenge at offset 9
        var authResponse = Data(repeating: 0x00, count: 20)
        let challenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22])
        authResponse.replaceSubrange(9..<17, with: challenge)
        
        let extracted = XDripChallengeExtractor.extractChallenge(from: authResponse)
        
        #expect(extracted != nil)
        #expect(extracted == challenge)
    }
    
    @Test("Challenge extraction rejects short data")
    func challengeExtractionRejectsShortData() {
        let shortData = Data(repeating: 0x00, count: 16)  // Too short
        #expect(XDripChallengeExtractor.extractChallenge(from: shortData) == nil)
    }
}
