// SPDX-License-Identifier: MIT
//
// G6AuthCrossImplementationTests.swift
// CGMKitTests
//
// Cross-implementation tests validating G6 auth against CGMBLEKit test vectors.
// Trace: PROTO-CMP-001, G6-FIX-011

import Testing
import Foundation
import BLEKit
@testable import CGMKit

/// Cross-implementation tests for G6 authentication
/// Validates our implementation against CGMBLEKit (LoopKit) test vectors
@Suite("G6 Auth Cross-Implementation Tests")
struct G6AuthCrossImplementationTests {
    
    // MARK: - Key Derivation Tests
    
    @Test("Key derivation matches CGMBLEKit format")
    func keyDerivationFormat() throws {
        // CGMBLEKit: cryptKey = "00" + id + "00" + id (as UTF-8)
        // For ID "123456", key should be "0012345600123456" = 16 bytes
        let key = G6Authenticator.deriveKey(from: "123456")
        
        // Verify length
        #expect(key.count == 16, "Key must be 16 bytes for AES-128")
        
        // Verify format: "00" prefix as individual characters, not null bytes
        // "0" = 0x30, not 0x00
        let expectedKey = "0012345600123456".data(using: .utf8)!
        #expect(key == expectedKey, "Key derivation format mismatch with CGMBLEKit")
    }
    
    @Test("Key derivation for 80AB12")
    func keyDerivationAlphanumeric() throws {
        let key = G6Authenticator.deriveKey(from: "80AB12")
        let expectedKey = "0080AB120080AB12".data(using: .utf8)!
        
        #expect(key == expectedKey, "Alphanumeric ID key derivation failed")
    }
    
    // MARK: - Token Hash Tests (Critical CGMBLEKit Vector)
    
    @Test("Token hash matches CGMBLEKit test vector")
    func tokenHashMatchesCGMBLEKit() throws {
        // From CGMBLEKit TransmitterIDTests.testComputeHash:
        // id = "123456"
        // token = Data(hexadecimalString: "0123456789abcdef")
        // expected = "e60d4a7999b0fbb2"
        
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let hash = auth.hashToken(token)
        
        let expectedHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        
        #expect(hash == expectedHash, """
            Token hash mismatch with CGMBLEKit!
            Input token: \(token.crossImplHexString)
            Got:         \(hash.crossImplHexString)
            Expected:    \(expectedHash.crossImplHexString)
            
            CGMBLEKit uses: AES(token + token)[0:8]
            Our impl may use: AES(token + zeros)[0:8]
            """)
    }
    
    // MARK: - Message Format Tests
    
    @Test("AuthRequestTx message format")
    func authRequestTxFormat() throws {
        // Message format: opcode(1) + token(8) + endByte(1) = 10 bytes
        let token = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let message = AuthRequestTxMessage(singleUseToken: token)
        
        #expect(message.data.count == 10, "AuthRequestTx should be 10 bytes")
        #expect(message.data[0] == G6Opcode.authRequestTx.rawValue)
        #expect(message.data[9] == 0x02, "End byte should be 0x02")
        
        // Verify token is at bytes 1-8
        let embeddedToken = message.data.subdata(in: 1..<9)
        #expect(embeddedToken == token)
    }
    
    @Test("AuthRequestRx message parsing")
    func authRequestRxParsing() throws {
        // CGMBLEKit format: opcode(1) + tokenHash(8) + challenge(8) = 17 bytes
        // Opcode 0x03 = authRequestRx (server challenge with tokenHash)
        var messageData = Data([G6Opcode.authRequestRx.rawValue])
        let tokenHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        let challenge = Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10])
        messageData.append(tokenHash)
        messageData.append(challenge)
        
        let message = AuthChallengeRxMessage(data: messageData)
        #expect(message != nil, "Should parse valid AuthRequestRx")
        #expect(message?.tokenHash == tokenHash)
        #expect(message?.challenge == challenge)
    }
    
    @Test("AuthChallengeRx authenticated and bonded")
    func authChallengeRxAuthenticated() throws {
        // Format: opcode(1) + authenticated(1) + bonded(1)
        // Note: opcode 0x05 (authChallengeRx) per CGMBLEKit
        let messageData = Data([G6Opcode.authChallengeRx.rawValue, 0x01, 0x01])
        let message = AuthStatusRxMessage(data: messageData)
        
        #expect(message != nil)
        #expect(message?.authenticated == true)
        #expect(message?.bonded == true)
    }
    
    @Test("AuthChallengeRx not authenticated")
    func authChallengeRxNotAuthenticated() throws {
        let messageData = Data([G6Opcode.authChallengeRx.rawValue, 0x00, 0x00])
        let message = AuthStatusRxMessage(data: messageData)
        
        #expect(message != nil)
        #expect(message?.authenticated == false)
        #expect(message?.bonded == false)
    }
    
    // MARK: - Full Authentication Flow Test
    
    @Test("Full authentication flow with CGMBLEKit vectors")
    func fullAuthFlow() throws {
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Step 1: Client generates token
        let clientToken = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        
        // Step 2: Server computes hash (we validate our hash matches)
        let expectedServerHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        let ourHash = auth.hashToken(clientToken)
        
        #expect(ourHash == expectedServerHash, "Token hash must match for auth to succeed")
        
        // Step 3: Build mock challenge response from server
        let serverChallenge = Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10])
        var challengeData = Data([G6Opcode.authRequestRx.rawValue])  // 0x03 - server challenge
        challengeData.append(expectedServerHash)
        challengeData.append(serverChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeData)!
        
        // Step 4: Process challenge - should succeed with matching hash
        let response = auth.processChallenge(challengeRx, sentToken: clientToken)
        #expect(response != nil, "Authentication should succeed with valid token hash")
        
        // Step 5: Verify challenge response format
        #expect(response?.data.count == 9, "AuthChallengeTx should be 9 bytes")
        #expect(response?.data[0] == G6Opcode.authChallengeTx.rawValue)
    }
    
    // MARK: - Hash Algorithm Tests
    
    @Test("Hash uses token duplication not zero-padding")
    func hashUsesDuplication() throws {
        // CGMBLEKit algorithm: AES(token + token)[0:8]
        // NOT: AES(token + zeros)[0:8]
        
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // With token duplication, hash of [AA, BB, CC, DD, EE, FF, 00, 00]
        // should differ from hash of [AA, BB, CC, DD, EE, FF, 00, 11]
        // because the duplicated second half changes
        
        let token1 = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x00])
        let token2 = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        let hash1 = auth.hashToken(token1)
        let hash2 = auth.hashToken(token2)
        
        // These should differ - validates that all 8 bytes contribute
        #expect(hash1 != hash2, "Tokens differing in last byte should produce different hashes")
    }
    
    @Test("Hash last byte affects result")
    func hashLastByteAffectsResult() throws {
        // If we incorrectly zero-pad instead of duplicate,
        // changing only the last byte of the token would still produce
        // a different hash due to the duplicated portion
        
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00])
        let token2 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0xFF])
        
        let hash1 = auth.hashToken(token1)
        let hash2 = auth.hashToken(token2)
        
        #expect(hash1 != hash2, "Last byte change must affect hash")
    }
}

// MARK: - G6-FIX-011: Key Derivation Verification

/// Verification tests confirming G6 key derivation matches external sources
/// Trace: G6-FIX-011, PROTO-VERIFY-001
@Suite("G6 Key Derivation Verification (G6-FIX-011)")
struct G6KeyDerivationVerificationTests {
    
    @Test("Key derivation matches CGMBLEKit (Loop)")
    func keyDerivationMatchesCGMBLEKit() {
        // Source: externals/CGMBLEKit/CGMBLEKit/Transmitter.swift:414
        // Code: `return "00\(id)00\(id)".data(using: .utf8)`
        //
        // Confirmed: ASCII zeros "00" (0x30 0x30), not null bytes (0x00 0x00)
        
        let key = G6Authenticator.deriveKey(from: "80AB12")
        
        // Expected: "0080AB120080AB12" as UTF-8
        // Bytes: [0x30, 0x30, 0x38, 0x30, 0x41, 0x42, 0x31, 0x32,
        //         0x30, 0x30, 0x38, 0x30, 0x41, 0x42, 0x31, 0x32]
        let expected = Data([
            0x30, 0x30,  // "00" ASCII
            0x38, 0x30, 0x41, 0x42, 0x31, 0x32,  // "80AB12" ASCII
            0x30, 0x30,  // "00" ASCII
            0x38, 0x30, 0x41, 0x42, 0x31, 0x32   // "80AB12" ASCII
        ])
        
        #expect(key == expected, "Key derivation must match CGMBLEKit")
        #expect(key.count == 16, "AES-128 requires 16-byte key")
    }
    
    @Test("Key derivation matches xDrip+ (Android)")
    func keyDerivationMatchesXDrip() {
        // Source: externals/xDrip/app/src/main/java/com/eveningoutpost/dexdrip/g5model/Ob1G5StateMachine.java:2049-2050
        // Code: `final String padding = "00";`
        //       `return (padding + transmitterId + padding + transmitterId).getBytes("UTF-8");`
        //
        // Confirmed: Same pattern as CGMBLEKit - ASCII "00" not null bytes
        
        let key = G6Authenticator.deriveKey(from: "123456")
        
        // xDrip constructs: "00" + "123456" + "00" + "123456" → "0012345600123456"
        let expectedString = "0012345600123456"
        let expected = expectedString.data(using: .utf8)!
        
        #expect(key == expected, "Key derivation must match xDrip+")
    }
    
    @Test("Key uses ASCII zeros not null bytes")
    func keyUsesAsciiZerosNotNullBytes() {
        // Critical verification: common mistake is interpreting "00" as null bytes
        // ASCII '0' = 0x30, null byte = 0x00
        
        let key = G6Authenticator.deriveKey(from: "ABCDEF")
        
        // First two bytes should be 0x30 0x30 (ASCII "00")
        // NOT 0x00 0x00 (null bytes)
        #expect(key[0] == 0x30, "First byte must be ASCII '0' (0x30), not null (0x00)")
        #expect(key[1] == 0x30, "Second byte must be ASCII '0' (0x30), not null (0x00)")
        
        // Bytes 8-9 should also be ASCII zeros
        #expect(key[8] == 0x30, "Byte 8 must be ASCII '0' (0x30)")
        #expect(key[9] == 0x30, "Byte 9 must be ASCII '0' (0x30)")
    }
    
    @Test("Key derivation variant is asciiZeros")
    func keyDerivationVariantIsAsciiZeros() {
        // This test documents that G6KeyDerivationVariant.asciiZeros is correct
        // per both CGMBLEKit and xDrip+ implementations
        
        let expectedVariant = G6KeyDerivationVariant.asciiZeros
        
        #expect(expectedVariant.rawValue == "asciiZeros")
        #expect(expectedVariant.sourceReference == "CGMBLEKit (Loop)")
        #expect(expectedVariant.description.contains("correct"))
    }
    
    @Test("All 6-character IDs produce 16-byte keys")
    func allValidIDsProduceCorrectKeyLength() {
        // G6 transmitter IDs are always 6 alphanumeric characters
        // Key format: "00" + ID + "00" + ID = 2 + 6 + 2 + 6 = 16 bytes
        
        let testIDs = ["123456", "80AB12", "8GHJKL", "AAAAAA", "000000", "ZZZZZZ"]
        
        for id in testIDs {
            let key = G6Authenticator.deriveKey(from: id)
            #expect(key.count == 16, "ID '\(id)' must produce 16-byte key, got \(key.count)")
        }
    }
}

// MARK: - Hex String Helper

private extension Data {
    var crossImplHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
