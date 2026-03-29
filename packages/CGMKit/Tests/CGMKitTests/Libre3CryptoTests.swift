//
//  Libre3CryptoTests.swift
//  CGMKitTests
//
//  Tests for Libre 3 ECDH and session crypto.
//  Validates key constants and crypto operations.
//

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(Crypto)
import Crypto
#endif

// MARK: - Key Constant Tests (LIBRE3-011)

@Suite("Libre3 Keys - Constant Validation")
struct Libre3KeysTests {
    
    @Test("App certificate 0 has correct length and format")
    func testAppCertificate0Format() {
        let cert = Libre3AppCertificates.certificate0
        #expect(cert.count == 162, "Certificate should be 162 bytes")
        #expect(cert[0] == 0x03, "Version should be 0x03")
        #expect(cert[1] == 0x00, "Security level should be 0x00")
        #expect(cert[33] == 0x04, "Public key should start with 0x04 (uncompressed)")
    }
    
    @Test("App certificate 1 has correct length and format")
    func testAppCertificate1Format() {
        let cert = Libre3AppCertificates.certificate1
        #expect(cert.count == 162, "Certificate should be 162 bytes")
        #expect(cert[0] == 0x03, "Version should be 0x03")
        #expect(cert[1] == 0x03, "Security level should be 0x03")
        #expect(cert[33] == 0x04, "Public key should start with 0x04 (uncompressed)")
    }
    
    @Test("Certificate version selector works")
    func testCertificateSelector() {
        let cert0 = Libre3AppCertificates.certificate(for: .version0)
        let cert1 = Libre3AppCertificates.certificate(for: .version1)
        
        #expect(cert0[1] == 0x00)
        #expect(cert1[1] == 0x03)
    }
    
    @Test("App private key 0 has correct length")
    func testPrivateKey0Length() {
        let key = Libre3AppPrivateKeys.privateKey0
        #expect(key.count == 165, "Private key should be 165 bytes (whiteCryption SKB format)")
    }
    
    @Test("App private key 1 has correct length")
    func testPrivateKey1Length() {
        let key = Libre3AppPrivateKeys.privateKey1
        #expect(key.count == 165, "Private key should be 165 bytes (whiteCryption SKB format)")
    }
    
    @Test("Patch signing key 0 is valid uncompressed P-256 point")
    func testPatchSigningKey0() {
        let key = Libre3PatchSigningKeys.signingKey0
        #expect(key.count == 65, "Signing key should be 65 bytes")
        #expect(key[0] == 0x04, "Should start with 0x04 (uncompressed point)")
    }
    
    @Test("Patch signing key 1 is valid uncompressed P-256 point")
    func testPatchSigningKey1() {
        let key = Libre3PatchSigningKeys.signingKey1
        #expect(key.count == 65, "Signing key should be 65 bytes")
        #expect(key[0] == 0x04, "Should start with 0x04 (uncompressed point)")
    }
    
    @Test("Signing key X/Y coordinates match full key")
    func testSigningKeyCoordinates() {
        let fullKey = Libre3PatchSigningKeys.signingKey1
        let x = Libre3PatchSigningKeys.signingKey1X
        let y = Libre3PatchSigningKeys.signingKey1Y
        
        #expect(x.count == 32)
        #expect(y.count == 32)
        #expect(fullKey.subdata(in: 1..<33) == x)
        #expect(fullKey.subdata(in: 33..<65) == y)
    }
}

// MARK: - Security Context Tests (LIBRE3-012/013)

@Suite("Libre3 Security Context")
struct Libre3SecurityContextTests {
    
    @Test("Security context initializes with correct key lengths")
    func testSecurityContextInit() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0xBB, count: 8)
        
        let context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        
        #expect(context.kEnc == kEnc)
        #expect(context.ivEnc == ivEnc)
        #expect(context.outCryptoSequence == 0)
        #expect(context.inCryptoSequence == 0)
    }
    
    @Test("Nonce construction produces 13 bytes")
    func testNonceLength() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        let context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        let nonce = context.buildNonce(packetType: 0)
        
        #expect(nonce.count == 13)
    }
    
    @Test("Nonce includes sequence number at start")
    func testNonceSequenceNumber() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0x00, count: 8)
        
        var context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        context.outCryptoSequence = 0x0102
        
        let nonce = context.buildNonce(packetType: 0)
        
        // Little-endian: 0x0102 -> [0x02, 0x01]
        #expect(nonce[0] == 0x02)
        #expect(nonce[1] == 0x01)
    }
    
    @Test("Nonce includes packet descriptor")
    func testNonceDescriptor() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0x00, count: 8)
        
        let context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        
        // Control packet (type 0)
        let nonce0 = context.buildNonce(packetType: 0)
        #expect(nonce0[2] == 0x24)
        #expect(nonce0[3] == 0x40)
        #expect(nonce0[4] == 0x00)
        
        // Data packet (type 1)
        let nonce1 = context.buildNonce(packetType: 1)
        #expect(nonce1[2] == 0x29)
        #expect(nonce1[3] == 0x40)
        #expect(nonce1[4] == 0x00)
    }
    
    @Test("Nonce includes ivEnc at end")
    func testNonceIv() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        
        let context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        let nonce = context.buildNonce(packetType: 0)
        
        // Bytes 5-12 should be ivEnc
        #expect(nonce[5] == 0x11)
        #expect(nonce[6] == 0x22)
        #expect(nonce[12] == 0x88)
    }
    
    @Test("Sequence increment works")
    func testSequenceIncrement() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0x00, count: 8)
        
        var context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        #expect(context.outCryptoSequence == 0)
        
        context.incrementOutSequence()
        #expect(context.outCryptoSequence == 1)
        
        context.incrementInSequence()
        #expect(context.inCryptoSequence == 1)
    }
}

// MARK: - ECDH Tests (LIBRE3-012)

@Suite("Libre3 ECDH Key Exchange")
struct Libre3ECDHTests {
    
    @Test("ECDH generates 65-byte ephemeral public key")
    func testEphemeralKeyGeneration() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        let pubKey = ecdh.ephemeralPublicKey
        
        #expect(pubKey.count == 65, "Public key should be 65 bytes (uncompressed P-256)")
        #expect(pubKey[0] == 0x04, "Should start with 0x04 (uncompressed)")
    }
    
    @Test("ECDH returns correct app certificate for version")
    func testAppCertificateSelection() {
        let ecdh0 = Libre3ECDH(securityVersion: .version0)
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        
        #expect(ecdh0.appCertificate[1] == 0x00)
        #expect(ecdh1.appCertificate[1] == 0x03)
    }
    
    @Test("ECDH shared secret derivation works with valid key")
    func testSharedSecretDerivation() throws {
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        let ecdh2 = Libre3ECDH(securityVersion: .version1)
        
        // Derive shared secret in both directions
        let secret1 = try ecdh1.deriveSharedSecret(patchEphemeralKey: ecdh2.ephemeralPublicKey)
        let secret2 = try ecdh2.deriveSharedSecret(patchEphemeralKey: ecdh1.ephemeralPublicKey)
        
        // Both should derive the same shared secret
        #expect(secret1 == secret2, "ECDH should produce same shared secret")
        #expect(secret1.count == 32, "Shared secret should be 32 bytes")
    }
    
    @Test("ECDH rejects invalid key length")
    func testInvalidKeyLength() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        let shortKey = Data(repeating: 0x04, count: 32)
        
        #expect(throws: Libre3CryptoError.self) {
            try ecdh.deriveSharedSecret(patchEphemeralKey: shortKey)
        }
    }
    
    @Test("ECDH rejects invalid key format")
    func testInvalidKeyFormat() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        // Key with wrong prefix (should be 0x04)
        var badKey = Data(repeating: 0x00, count: 65)
        badKey[0] = 0x02 // Compressed format, not uncompressed
        
        #expect(throws: Libre3CryptoError.self) {
            try ecdh.deriveSharedSecret(patchEphemeralKey: badKey)
        }
    }
    
    @Test("Session key extraction from challenge data")
    func testSessionKeyExtraction() throws {
        // Simulated decrypted challenge: [r2(16)][r1(16)][kEnc(16)][ivEnc(8)]
        var challenge = Data(count: 56)
        // Fill kEnc at bytes 32-47
        for i in 0..<16 {
            challenge[32 + i] = UInt8(0xA0 + i)
        }
        // Fill ivEnc at bytes 48-55
        for i in 0..<8 {
            challenge[48 + i] = UInt8(0xB0 + i)
        }
        
        let context = try Libre3ECDH.extractSessionKeys(from: challenge)
        
        #expect(context.kEnc.count == 16)
        #expect(context.ivEnc.count == 8)
        #expect(context.kEnc[0] == 0xA0)
        #expect(context.ivEnc[0] == 0xB0)
    }
    
    @Test("Session key extraction rejects short data")
    func testSessionKeyExtractionShortData() {
        let shortData = Data(count: 50) // Less than 56 bytes
        
        #expect(throws: Libre3CryptoError.self) {
            try Libre3ECDH.extractSessionKeys(from: shortData)
        }
    }
}

// MARK: - Packet Descriptor Tests

@Suite("Libre3 Packet Descriptors")
struct Libre3PacketDescriptorTests {
    
    @Test("Control packet descriptor")
    func testControlDescriptor() {
        let desc = Libre3PacketDescriptor.control
        #expect(desc == [0x24, 0x40, 0x00])
    }
    
    @Test("Data packet descriptor")
    func testDataDescriptor() {
        let desc = Libre3PacketDescriptor.data
        #expect(desc == [0x29, 0x40, 0x00])
    }
    
    @Test("Descriptor lookup by type")
    func testDescriptorLookup() {
        #expect(Libre3PacketDescriptor.descriptor(for: 0) == [0x24, 0x40, 0x00])
        #expect(Libre3PacketDescriptor.descriptor(for: 1) == [0x29, 0x40, 0x00])
        #expect(Libre3PacketDescriptor.descriptor(for: 2) == [0x25, 0x00, 0x00])
        // Unknown type defaults to control
        #expect(Libre3PacketDescriptor.descriptor(for: 99) == [0x24, 0x40, 0x00])
    }
}

// MARK: - Security Command Tests

@Suite("Libre3 Security Commands")
struct Libre3SecurityCommandTests {
    
    @Test("Security command values match protocol spec")
    func testSecurityCommandValues() {
        #expect(Libre3SecurityCommand.ecdhStart.rawValue == 0x01)
        #expect(Libre3SecurityCommand.loadCertData.rawValue == 0x02)
        #expect(Libre3SecurityCommand.ecdhComplete.rawValue == 0x10)
        #expect(Libre3SecurityCommand.verificationFailure.rawValue == 0x13)
    }
}

// MARK: - Fixture-Based Tests (LIBRE3-017)

@Suite("Libre3 Crypto Fixtures")
struct Libre3CryptoFixtureTests {
    
    /// Test vector fixture loaded from JSON (extracted from Juggluco libre3init.java)
    struct Libre3CryptoFixture: Decodable {
        let ecdhSession: ECDHSession
        let alternateTest: AlternateTest
        
        enum CodingKeys: String, CodingKey {
            case ecdhSession = "ecdh_session"
            case alternateTest = "alternate_test"
        }
        
        struct ECDHSession: Decodable {
            let rdtData: HexValue
            let data6: HexValue
            let nonce1: HexValue
            let encryptInput: HexValue
            let nonce2: HexValue
            let decryptInput: HexValue
            
            enum CodingKeys: String, CodingKey {
                case rdtData, data6, nonce1, nonce2
                case encryptInput = "encrypt_input"
                case decryptInput = "decrypt_input"
            }
        }
        
        struct AlternateTest: Decodable {
            let input: HexValue
        }
        
        struct HexValue: Decodable {
            let hex: String
            let length: Int
            
            var data: Data {
                Data(hexString: hex) ?? Data()
            }
        }
    }
    
    func loadFixture() throws -> Libre3CryptoFixture {
        let url = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Libre3CryptoFixture.self, from: data)
    }
    
    @Test("Fixture rdtData has correct length (patch certificate)")
    func testRdtDataLength() throws {
        let fixture = try loadFixture()
        #expect(fixture.ecdhSession.rdtData.length == 140)
        #expect(fixture.ecdhSession.rdtData.data.count == 140)
    }
    
    @Test("Fixture data6 is valid uncompressed P-256 point")
    func testData6Format() throws {
        let fixture = try loadFixture()
        let data6 = fixture.ecdhSession.data6.data
        
        #expect(data6.count == 65, "Ephemeral public key should be 65 bytes")
        #expect(data6[0] == 0x04, "Should start with 0x04 (uncompressed)")
    }
    
    @Test("Fixture nonces have correct length")
    func testNonceFormats() throws {
        let fixture = try loadFixture()
        
        #expect(fixture.ecdhSession.nonce1.data.count == 7)
        #expect(fixture.ecdhSession.nonce2.data.count == 7)
    }
    
    @Test("Fixture encrypt/decrypt inputs have expected lengths")
    func testCipherDataLengths() throws {
        let fixture = try loadFixture()
        
        #expect(fixture.ecdhSession.encryptInput.length == 36)
        #expect(fixture.ecdhSession.decryptInput.length == 60)
    }
    
    @Test("Alternate test vector has correct length")
    func testAlternateVector() throws {
        let fixture = try loadFixture()
        #expect(fixture.alternateTest.input.length == 140)
    }
    
    @Test("AES-CCM RFC3610 vectors have correct lengths")
    func testAesCcmVectorLengths() throws {
        let url = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let ccmVectors = json["aes_ccm_vectors"] as! [String: Any]
        let vector1 = ccmVectors["rfc3610_vector1"] as! [String: Any]
        
        let key = Data(hexString: vector1["key"] as! String)!
        let nonce = Data(hexString: vector1["nonce"] as! String)!
        let plaintext = Data(hexString: vector1["plaintext"] as! String)!
        
        #expect(key.count == 16, "AES-128 key should be 16 bytes")
        #expect(nonce.count == 13, "CCM nonce should be 13 bytes")
        #expect(plaintext.count == 23, "Plaintext should be 23 bytes")
    }
    
    @Test("Libre3 CCM config matches protocol requirements")
    func testLibre3CcmConfig() throws {
        let url = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let ccmVectors = json["aes_ccm_vectors"] as! [String: Any]
        let config = ccmVectors["libre3_ccm_config"] as! [String: Any]
        
        #expect(config["nonce_length"] as! Int == 13)
        #expect(config["tag_length"] as! Int == 4)
        #expect(config["key_length"] as! Int == 16)
    }
}

// MARK: - ECDH Oracle Tests (LIBRE3-019a)

@Suite("Libre3 ECDH Oracle")
struct Libre3ECDHOracleTests {
    
    @Test("ECDH instance generates valid ephemeral public key")
    func testEphemeralKeyGeneration() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        let publicKey = ecdh.ephemeralPublicKey
        
        #expect(publicKey.count == 65, "Ephemeral public key should be 65 bytes")
        #expect(publicKey[0] == 0x04, "Should be uncompressed point (0x04 prefix)")
    }
    
    @Test("ECDH derives shared secret with valid peer key")
    func testSharedSecretDerivation() throws {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        
        // Load data6 from fixture (patch ephemeral public key)
        let url = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let ecdhSession = json["ecdh_session"] as! [String: Any]
        let data6 = ecdhSession["data6"] as! [String: Any]
        let patchEphemeralHex = data6["hex"] as! String
        let patchEphemeralKey = Data(hexString: patchEphemeralHex)!
        
        // Derive shared secret
        let sharedSecret = try ecdh.deriveSharedSecret(patchEphemeralKey: patchEphemeralKey)
        
        #expect(sharedSecret.count == 32, "Shared secret should be 32 bytes (P-256)")
    }
    
    @Test("ECDH rejects invalid key length")
    func testInvalidKeyLengthRejected() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        let shortKey = Data(repeating: 0x04, count: 33) // Too short
        
        #expect(throws: Libre3CryptoError.self) {
            try ecdh.deriveSharedSecret(patchEphemeralKey: shortKey)
        }
    }
    
    @Test("ECDH rejects invalid key format")
    func testInvalidKeyFormatRejected() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        var invalidKey = Data(repeating: 0xAA, count: 65)
        invalidKey[0] = 0x02 // Wrong prefix (should be 0x04)
        
        #expect(throws: Libre3CryptoError.self) {
            try ecdh.deriveSharedSecret(patchEphemeralKey: invalidKey)
        }
    }
    
    @Test("ECDH produces deterministic secret with same keys")
    func testDeterministicSharedSecret() throws {
        // Create two ECDH instances
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        let ecdh2 = Libre3ECDH(securityVersion: .version1)
        
        // They should produce a shared secret when given each other's public keys
        let secret1 = try ecdh1.deriveSharedSecret(patchEphemeralKey: ecdh2.ephemeralPublicKey)
        let secret2 = try ecdh2.deriveSharedSecret(patchEphemeralKey: ecdh1.ephemeralPublicKey)
        
        #expect(secret1 == secret2, "ECDH should produce same shared secret on both sides")
    }
    
    @Test("App certificate returned for correct security version")
    func testAppCertificateSelection() {
        let ecdh0 = Libre3ECDH(securityVersion: .version0)
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        
        #expect(ecdh0.appCertificate[1] == 0x00, "Version 0 cert should have 0x00 at byte 1")
        #expect(ecdh1.appCertificate[1] == 0x03, "Version 1 cert should have 0x03 at byte 1")
    }
}

// MARK: - Session Establishment Flow Tests (LIBRE3-019b)

@Suite("Libre3 Session Establishment")
struct Libre3SessionEstablishmentTests {
    
    @Test("Extract session keys from 56-byte challenge")
    func testExtractSessionKeys() throws {
        // Create mock decrypted challenge: [r2(16)][r1(16)][kEnc(16)][ivEnc(8)]
        var challenge = Data(count: 56)
        
        // Fill r2 (bytes 0-15) with pattern
        for i in 0..<16 { challenge[i] = UInt8(i) }
        
        // Fill r1 (bytes 16-31) with pattern
        for i in 16..<32 { challenge[i] = UInt8(i + 0x10) }
        
        // Fill kEnc (bytes 32-47) with known value
        let expectedKEnc = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
                                  0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99])
        challenge.replaceSubrange(32..<48, with: expectedKEnc)
        
        // Fill ivEnc (bytes 48-55) with known value
        let expectedIvEnc = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        challenge.replaceSubrange(48..<56, with: expectedIvEnc)
        
        // Extract keys
        let context = try Libre3ECDH.extractSessionKeys(from: challenge)
        
        #expect(context.kEnc == expectedKEnc, "kEnc should be bytes 32-47")
        #expect(context.ivEnc == expectedIvEnc, "ivEnc should be bytes 48-55")
    }
    
    @Test("Extract session keys rejects short data")
    func testExtractSessionKeysRejectsShort() {
        let shortData = Data(count: 40) // Too short
        
        #expect(throws: Libre3CryptoError.self) {
            try Libre3ECDH.extractSessionKeys(from: shortData)
        }
    }
    
    @Test("Security context initializes with correct sequence numbers")
    func testSecurityContextInit() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0xBB, count: 8)
        
        let context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        
        #expect(context.outCryptoSequence == 0)
        #expect(context.inCryptoSequence == 0)
    }
    
    @Test("Security context increments sequences correctly")
    func testSecurityContextSequenceIncrement() {
        let kEnc = Data(repeating: 0xAA, count: 16)
        let ivEnc = Data(repeating: 0xBB, count: 8)
        
        var context = Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
        
        context.incrementOutSequence()
        #expect(context.outCryptoSequence == 1)
        
        context.incrementInSequence()
        #expect(context.inCryptoSequence == 1)
        
        // Increment more
        for _ in 0..<10 {
            context.incrementOutSequence()
            context.incrementInSequence()
        }
        
        #expect(context.outCryptoSequence == 11)
        #expect(context.inCryptoSequence == 11)
    }
    
    @Test("Full session flow: ECDH → shared secret → mock challenge")
    func testFullSessionFlow() throws {
        // Step 1: Initialize ECDH
        let appECDH = Libre3ECDH(securityVersion: .version1)
        let patchECDH = Libre3ECDH(securityVersion: .version1)
        
        // Step 2: Exchange public keys and derive shared secret
        let appSharedSecret = try appECDH.deriveSharedSecret(patchEphemeralKey: patchECDH.ephemeralPublicKey)
        let patchSharedSecret = try patchECDH.deriveSharedSecret(patchEphemeralKey: appECDH.ephemeralPublicKey)
        
        #expect(appSharedSecret == patchSharedSecret, "Both sides should derive same secret")
        #expect(appSharedSecret.count == 32, "P-256 shared secret is 32 bytes")
        
        // Step 3: Create mock decrypted challenge (would be encrypted with shared secret in real flow)
        var mockChallenge = Data(count: 56)
        // r2, r1 random
        for i in 0..<32 { mockChallenge[i] = UInt8.random(in: 0...255) }
        // kEnc from shared secret (first 16 bytes in mock)
        mockChallenge.replaceSubrange(32..<48, with: appSharedSecret.prefix(16))
        // ivEnc from shared secret (bytes 16-23 in mock)
        mockChallenge.replaceSubrange(48..<56, with: appSharedSecret.subdata(in: 16..<24))
        
        // Step 4: Extract session keys
        let context = try Libre3ECDH.extractSessionKeys(from: mockChallenge)
        
        #expect(context.kEnc.count == 16)
        #expect(context.ivEnc.count == 8)
        
        // Step 5: Verify nonce construction works
        let nonce = context.buildNonce(packetType: 0)
        #expect(nonce.count == 13, "Nonce should be 13 bytes")
    }
}

// MARK: - AES-CCM Tests (LIBRE3-013b/c)

@Suite("Libre3 AES-CCM")
struct Libre3AesCcmTests {
    
    @Test("AES-CCM encrypt/decrypt roundtrip")
    func testAesCcmRoundtrip() throws {
        let key = Data([0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,
                        0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF])
        let nonce = Data([0x00, 0x00, 0x00, 0x03, 0x02, 0x01, 0x00,
                          0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5])
        let plaintext = Data([0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                              0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                              0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E])
        
        let ciphertext = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        #expect(ciphertext.count == plaintext.count + 4, "Ciphertext should include 4-byte tag")
        
        let decrypted = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        #expect(decrypted == plaintext, "Decrypted should match original plaintext")
    }
    
    @Test("AES-CCM encrypt produces consistent output")
    func testAesCcmEncryptConsistent() throws {
        let key = Data(repeating: 0x42, count: 16)
        let nonce = Data(repeating: 0x13, count: 13)
        let plaintext = Data("Hello Libre3!".utf8)
        
        let ciphertext1 = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        let ciphertext2 = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        
        #expect(ciphertext1 == ciphertext2, "Same inputs should produce same ciphertext")
    }
    
    @Test("AES-CCM decrypt rejects tampered ciphertext")
    func testAesCcmDecryptRejectsTampered() throws {
        let key = Data(repeating: 0x42, count: 16)
        let nonce = Data(repeating: 0x13, count: 13)
        let plaintext = Data("Sensitive data".utf8)
        
        var ciphertext = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        
        // Tamper with ciphertext (flip a bit)
        ciphertext[5] ^= 0xFF
        
        // Should fail authentication
        #expect(throws: Error.self) {
            _ = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        }
    }
    
    @Test("AES-CCM validates key length")
    func testAesCcmValidatesKeyLength() {
        let badKey = Data(repeating: 0x42, count: 8)  // Should be 16
        let nonce = Data(repeating: 0x13, count: 13)
        let plaintext = Data("test".utf8)
        
        #expect(throws: Libre3CryptoError.self) {
            _ = try Libre3AesCcm.encrypt(plaintext: plaintext, key: badKey, nonce: nonce)
        }
    }
    
    @Test("AES-CCM validates nonce length")
    func testAesCcmValidatesNonceLength() {
        let key = Data(repeating: 0x42, count: 16)
        let badNonce = Data(repeating: 0x13, count: 7)  // Should be 13
        let plaintext = Data("test".utf8)
        
        #expect(throws: Libre3CryptoError.self) {
            _ = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: badNonce)
        }
    }
    
    @Test("AES-CCM works with empty plaintext")
    func testAesCcmEmptyPlaintext() throws {
        let key = Data(repeating: 0x42, count: 16)
        let nonce = Data(repeating: 0x13, count: 13)
        let plaintext = Data()
        
        let ciphertext = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        #expect(ciphertext.count == 4, "Empty plaintext should produce just tag")
        
        let decrypted = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        #expect(decrypted.isEmpty, "Decrypted empty plaintext")
    }
    
    @Test("AES-CCM CommonCrypto wrapper delegates correctly")
    func testCommonCryptoWrapper() throws {
        #if canImport(CommonCrypto)
        let key = Data(repeating: 0x42, count: 16)
        let nonce = Data(repeating: 0x13, count: 13)
        let plaintext = Data("Wrapper test".utf8)
        
        let ciphertext = try Libre3AesCcmCommonCrypto.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        let decrypted = try Libre3AesCcmCommonCrypto.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        
        #expect(decrypted == plaintext)
        #endif
    }
}

// MARK: - AES-CCM Oracle Tests (LIBRE3-018)

@Suite("Libre3 AES-CCM Oracle")
struct Libre3AesCcmOracleTests {
    
    /// Load fixture and return aes_ccm_oracle_vectors section
    func loadOracleVectors() throws -> [String: Any] {
        let fixtureURL = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["aes_ccm_oracle_vectors"] as! [String: Any]
    }
    
    @Test("Oracle: libre3_4byte_tag_vector1 encrypt matches Python reference")
    func testOracleVector1Encrypt() throws {
        let vectors = try loadOracleVectors()
        let v = vectors["libre3_4byte_tag_vector1"] as! [String: Any]
        
        let key = Data(hexString: v["key"] as! String)!
        let nonce = Data(hexString: v["nonce"] as! String)!
        let plaintext = Data(hexString: v["plaintext"] as! String)!
        let expectedCiphertext = Data(hexString: v["ciphertext_with_tag"] as! String)!
        
        let ciphertext = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        #expect(ciphertext == expectedCiphertext, "Encrypt should match Python reference")
    }
    
    @Test("Oracle: libre3_4byte_tag_vector1 decrypt matches Python reference")
    func testOracleVector1Decrypt() throws {
        let vectors = try loadOracleVectors()
        let v = vectors["libre3_4byte_tag_vector1"] as! [String: Any]
        
        let key = Data(hexString: v["key"] as! String)!
        let nonce = Data(hexString: v["nonce"] as! String)!
        let ciphertext = Data(hexString: v["ciphertext_with_tag"] as! String)!
        let expectedPlaintext = Data(hexString: v["plaintext"] as! String)!
        
        let plaintext = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        #expect(plaintext == expectedPlaintext, "Decrypt should match Python reference")
    }
    
    @Test("Oracle: empty plaintext produces correct tag")
    func testOracleEmptyPlaintext() throws {
        let vectors = try loadOracleVectors()
        let v = vectors["libre3_empty_plaintext"] as! [String: Any]
        
        let key = Data(hexString: v["key"] as! String)!
        let nonce = Data(hexString: v["nonce"] as! String)!
        let expectedCiphertext = Data(hexString: v["ciphertext_with_tag"] as! String)!
        
        let ciphertext = try Libre3AesCcm.encrypt(plaintext: Data(), key: key, nonce: nonce)
        #expect(ciphertext == expectedCiphertext, "Empty plaintext tag should match Python reference")
    }
    
    @Test("Oracle: short message roundtrip matches fixture")
    func testOracleShortMessage() throws {
        let vectors = try loadOracleVectors()
        let v = vectors["libre3_short_message"] as! [String: Any]
        
        let key = Data(hexString: v["key"] as! String)!
        let nonce = Data(hexString: v["nonce"] as! String)!
        let plaintext = Data(hexString: v["plaintext"] as! String)!
        let expectedCiphertext = Data(hexString: v["ciphertext_with_tag"] as! String)!
        
        // Encrypt
        let ciphertext = try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce)
        #expect(ciphertext == expectedCiphertext, "Short message encrypt should match")
        
        // Decrypt
        let decrypted = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
        #expect(decrypted == plaintext, "Short message decrypt should roundtrip")
    }
    
    @Test("Oracle: all vectors decrypt correctly")
    func testOracleAllVectorsDecrypt() throws {
        let vectors = try loadOracleVectors()
        var passCount = 0
        
        for (name, value) in vectors {
            guard let v = value as? [String: Any],
                  let keyHex = v["key"] as? String,
                  let nonceHex = v["nonce"] as? String,
                  v["nonce_length"] as? Int == 13,
                  let ciphertextHex = v["ciphertext_with_tag"] as? String,
                  let plaintextHex = v["plaintext"] as? String else {
                continue
            }
            
            let key = Data(hexString: keyHex)!
            let nonce = Data(hexString: nonceHex)!
            let ciphertext = Data(hexString: ciphertextHex)!
            let expectedPlaintext = Data(hexString: plaintextHex)!
            
            let decrypted = try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce)
            #expect(decrypted == expectedPlaintext, "Vector \(name) should decrypt correctly")
            passCount += 1
        }
        
        #expect(passCount >= 3, "Should test at least 3 vectors")
    }
}

// MARK: - Libre3GlucoseData Tests (LIBRE3-025a)

@Suite("Libre3 GlucoseData - BLE Packet Parsing")
struct Libre3GlucoseDataTests {
    
    /// Example from DiaBLE: 062DEE00FCFF0000945CF12CF0000BEE00F000010C530E72482F130000
    /// lifeCount=11526, readingMgDl=238, rateOfChange=-4, etc.
    static let diableExample = Data([
        0x06, 0x2D,  // lifeCount: 11526 (0x2D06)
        0xEE, 0x00,  // readingMgDl: 238
        0xFC, 0xFF,  // rateOfChange: -4 (signed)
        0x00, 0x00,  // esaDuration: 0
        0x94, 0x5C,  // projectedGlucose: 23700
        0xF1, 0x2C,  // historicalLifeCount: 11505
        0xF0, 0x00,  // historicalReading: 240
        0x0B,        // bitfields: 00001 011 (trend=1, flags=3)
        0xEE, 0x00,  // uncappedCurrentMgDl: 238
        0xF0, 0x00,  // uncappedHistoricMgDl: 240
        0x01, 0x0C,  // temperature: 3073
        0x53, 0x0E, 0x72, 0x48, 0x2F, 0x13, 0x00, 0x00  // fastData
    ])
    
    @Test("Parse DiaBLE example vector")
    func testParseDiableExample() throws {
        let data = Libre3GlucoseDataTests.diableExample
        let parsed = Libre3GlucoseData.parse(data)
        
        #expect(parsed != nil, "Should parse 29-byte data")
        guard let g = parsed else { return }
        
        #expect(g.lifeCount == 11526, "lifeCount should be 11526")
        #expect(g.readingMgDl == 238, "readingMgDl should be 238")
        #expect(g.rateOfChange == -4, "rateOfChange should be -4")
        #expect(g.esaDuration == 0, "esaDuration should be 0")
        #expect(g.projectedGlucose == 23700, "projectedGlucose should be 23700")
        #expect(g.historicalLifeCount == 11505, "historicalLifeCount should be 11505")
        #expect(g.historicalReading == 240, "historicalReading should be 240")
        #expect(g.bitfields == 0x0B, "bitfields should be 0x0B")
        #expect(g.trendArrow == 1, "trendArrow should be 1 (falling)")
        #expect(g.flags == 3, "flags should be 3")
        #expect(g.uncappedCurrentMgDl == 238, "uncappedCurrentMgDl should be 238")
        #expect(g.uncappedHistoricMgDl == 240, "uncappedHistoricMgDl should be 240")
        #expect(g.temperature == 3073, "temperature should be 3073")
        #expect(g.fastData.count == 8, "fastData should be 8 bytes")
    }
    
    @Test("Reject short data")
    func testRejectShortData() {
        let shortData = Data([0x06, 0x2D, 0xEE, 0x00])
        #expect(Libre3GlucoseData.parse(shortData) == nil, "Should reject data shorter than 29 bytes")
    }
    
    @Test("Parse minimum valid data")
    func testParseMinimumData() {
        var data = Data(count: 29)
        data[0] = 0x10  // lifeCount low byte = 16
        data[1] = 0x00  // lifeCount high byte = 0
        data[2] = 0x64  // readingMgDl = 100 mg/dL
        data[3] = 0x00
        
        let parsed = Libre3GlucoseData.parse(data)
        #expect(parsed != nil, "Should parse 29-byte zero-padded data")
        #expect(parsed?.lifeCount == 16, "lifeCount should be 16")
        #expect(parsed?.readingMgDl == 100, "readingMgDl should be 100")
    }
    
    @Test("Trend arrow extraction")
    func testTrendArrowExtraction() {
        // Test each trend value (0-5) encoded in bits [5:3]
        let trendTests: [(bitfield: UInt8, expectedTrend: UInt8)] = [
            (0b00000_000, 0),  // trend 0 (unknown)
            (0b00001_000, 1),  // trend 1 (falling fast)
            (0b00010_000, 2),  // trend 2 (falling)
            (0b00011_000, 3),  // trend 3 (stable)
            (0b00100_000, 4),  // trend 4 (rising)
            (0b00101_000, 5),  // trend 5 (rising fast)
        ]
        
        for test in trendTests {
            var data = Data(count: 29)
            data[14] = test.bitfield
            
            let parsed = Libre3GlucoseData.parse(data)
            #expect(parsed?.trendArrow == test.expectedTrend, 
                   "Bitfield \(String(test.bitfield, radix: 2)) should give trend \(test.expectedTrend)")
        }
    }
    
    @Test("Equatable conformance")
    func testEquatable() {
        let data = Libre3GlucoseDataTests.diableExample
        let parsed1 = Libre3GlucoseData.parse(data)
        let parsed2 = Libre3GlucoseData.parse(data)
        
        #expect(parsed1 == parsed2, "Same data should produce equal structs")
    }
}

// MARK: - Libre3PatchState Tests

@Suite("Libre3 PatchState - Sensor State Enum")
struct Libre3PatchStateTests {
    
    @Test("All state values parse correctly")
    func testAllStates() {
        let states: [(raw: UInt8, expected: Libre3PatchState)] = [
            (0, .manufacturing),
            (1, .storage),
            (2, .insertionDetection),
            (3, .insertionFailed),
            (4, .paired),
            (5, .expired),
            (6, .terminated),
            (7, .error),
            (8, .errorTerminated),
        ]
        
        for state in states {
            let parsed = Libre3PatchState(rawValue: state.raw)
            #expect(parsed == state.expected, "Raw \(state.raw) should be \(state.expected)")
        }
    }
    
    @Test("Only paired state is active")
    func testIsActive() {
        #expect(Libre3PatchState.paired.isActive == true, "paired should be active")
        #expect(Libre3PatchState.storage.isActive == false, "storage should not be active")
        #expect(Libre3PatchState.expired.isActive == false, "expired should not be active")
        #expect(Libre3PatchState.error.isActive == false, "error should not be active")
    }
    
    @Test("Description is human-readable")
    func testDescription() {
        #expect(Libre3PatchState.paired.description == "Paired")
        #expect(Libre3PatchState.storage.description == "Not activated")
        #expect(Libre3PatchState.expired.description == "Expired")
    }
}

// MARK: - Libre3PatchStatus Tests (LIBRE3-025b)

@Suite("Libre3 PatchStatus - BLE Status Parsing")
struct Libre3PatchStatusTests {
    
    /// Example from DiaBLE: FC2C00000D002104FC2C1603 (12 bytes)
    /// lifeCount=11516, patchState=4 (paired), etc.
    static let diableExample = Data([
        0xFC, 0x2C,  // lifeCount: 11516 (0x2CFC)
        0x00, 0x00,  // errorData: 0
        0x0D, 0x00,  // eventData: 13
        0x21,        // index: 33
        0x04,        // patchState: 4 (paired)
        0xFC, 0x2C,  // currentLifeCount: 11516
        0x16,        // stackDisconnectReason: 22
        0x03         // appDisconnectReason: 3
    ])
    
    @Test("Parse DiaBLE example vector")
    func testParseDiableExample() throws {
        let data = Libre3PatchStatusTests.diableExample
        let parsed = Libre3PatchStatus.parse(data)
        
        #expect(parsed != nil, "Should parse 12-byte data")
        guard let s = parsed else { return }
        
        #expect(s.lifeCount == 11516, "lifeCount should be 11516")
        #expect(s.errorData == 0, "errorData should be 0")
        #expect(s.eventData == 13, "eventData should be 13")
        #expect(s.index == 33, "index should be 33")
        #expect(s.patchStateRaw == 4, "patchStateRaw should be 4")
        #expect(s.patchState == .paired, "patchState should be .paired")
        #expect(s.currentLifeCount == 11516, "currentLifeCount should be 11516")
        #expect(s.stackDisconnectReason == 22, "stackDisconnectReason should be 22")
        #expect(s.appDisconnectReason == 3, "appDisconnectReason should be 3")
    }
    
    @Test("Reject short data")
    func testRejectShortData() {
        let shortData = Data([0xFC, 0x2C, 0x00, 0x00])
        #expect(Libre3PatchStatus.parse(shortData) == nil, "Should reject data shorter than 12 bytes")
    }
    
    @Test("hasError detection")
    func testHasError() {
        var data = Libre3PatchStatusTests.diableExample
        
        // No error
        var parsed = Libre3PatchStatus.parse(data)
        #expect(parsed?.hasError == false, "Should not have error when errorData is 0")
        
        // With error
        data[2] = 0x01  // errorData = 1
        parsed = Libre3PatchStatus.parse(data)
        #expect(parsed?.hasError == true, "Should have error when errorData is non-zero")
    }
    
    @Test("hasEventData detection")
    func testHasEventData() {
        var data = Libre3PatchStatusTests.diableExample
        
        // Has event data (index=33)
        var parsed = Libre3PatchStatus.parse(data)
        #expect(parsed?.hasEventData == true, "Should have event data when index != 255")
        
        // No event data
        data[6] = 0xFF  // index = 255
        parsed = Libre3PatchStatus.parse(data)
        #expect(parsed?.hasEventData == false, "Should not have event data when index is 255")
    }
    
    @Test("All patch states parse correctly")
    func testPatchStates() {
        var data = Libre3PatchStatusTests.diableExample
        
        let states: [(raw: UInt8, expected: Libre3PatchState)] = [
            (0, .manufacturing),
            (1, .storage),
            (4, .paired),
            (5, .expired),
            (7, .error),
        ]
        
        for state in states {
            data[7] = state.raw
            let parsed = Libre3PatchStatus.parse(data)
            #expect(parsed?.patchState == state.expected, 
                   "Raw \(state.raw) should give \(state.expected)")
        }
    }
    
    @Test("Equatable conformance")
    func testEquatable() {
        let data = Libre3PatchStatusTests.diableExample
        let parsed1 = Libre3PatchStatus.parse(data)
        let parsed2 = Libre3PatchStatus.parse(data)
        
        #expect(parsed1 == parsed2, "Same data should produce equal structs")
    }
}

// MARK: - Libre3ControlCommand Tests (LIBRE3-025c)

@Suite("Libre3 ControlCommand - Command Building")
struct Libre3ControlCommandTests {
    
    @Test("Historic command format")
    func testHistoricCommand() {
        // Request historical data from lifeCount 11520 (0x2D00)
        let cmd = Libre3ControlCommand.historic(from: 11520, sequence: 1)
        let data = cmd.build()
        
        #expect(data.count == 13, "Command should be 13 bytes")
        #expect(data[0] == 0x01, "Opcode byte 0")
        #expect(data[1] == 0x00, "Opcode byte 1")
        #expect(data[2] == 0x01, "Opcode byte 2")
        // lifeCount 11520 = 0x00002D00 little-endian: 00 2D 00 00
        #expect(data[3] == 0x00, "lifeCount byte 0")
        #expect(data[4] == 0x2D, "lifeCount byte 1")
        #expect(data[5] == 0x00, "lifeCount byte 2")
        #expect(data[6] == 0x00, "lifeCount byte 3")
        // sequence 1 little-endian: 01 00
        #expect(data[11] == 0x01, "sequence byte 0")
        #expect(data[12] == 0x00, "sequence byte 1")
    }
    
    @Test("Backfill command format")
    func testBackfillCommand() {
        // Request clinical data from lifeCount 18587 (0x489B)
        let cmd = Libre3ControlCommand.backfill(from: 18587, sequence: 2)
        let data = cmd.build()
        
        #expect(data.count == 13, "Command should be 13 bytes")
        #expect(data[0] == 0x01, "Opcode byte 0")
        #expect(data[1] == 0x01, "Opcode byte 1")
        #expect(data[2] == 0x01, "Opcode byte 2")
        // lifeCount 18587 = 0x0000489B little-endian: 9B 48 00 00
        #expect(data[3] == 0x9B, "lifeCount byte 0")
        #expect(data[4] == 0x48, "lifeCount byte 1")
        // sequence 2
        #expect(data[11] == 0x02, "sequence byte 0")
        #expect(data[12] == 0x00, "sequence byte 1")
    }
    
    @Test("EventLog command format")
    func testEventLogCommand() {
        let cmd = Libre3ControlCommand.eventLog(sequence: 3)
        let data = cmd.build()
        
        #expect(data.count == 13, "Command should be 13 bytes")
        #expect(data[0] == 0x04, "Opcode byte 0")
        #expect(data[1] == 0x01, "Opcode byte 1")
        #expect(data[2] == 0x00, "Opcode byte 2")
        // lifeCount should be 0
        #expect(data[3] == 0x00, "lifeCount should be 0")
        #expect(data[4] == 0x00, "lifeCount should be 0")
        // sequence 3
        #expect(data[11] == 0x03, "sequence byte 0")
    }
    
    @Test("FactoryData command format")
    func testFactoryDataCommand() {
        let cmd = Libre3ControlCommand.factoryData(sequence: 4)
        let data = cmd.build()
        
        #expect(data.count == 13, "Command should be 13 bytes")
        #expect(data[0] == 0x06, "Opcode byte 0")
        #expect(data[1] == 0x00, "Opcode byte 1")
        #expect(data[2] == 0x00, "Opcode byte 2")
        #expect(data[11] == 0x04, "sequence byte 0")
    }
    
    @Test("Shutdown command format")
    func testShutdownCommand() {
        let cmd = Libre3ControlCommand.shutdown(sequence: 5)
        let data = cmd.build()
        
        #expect(data.count == 13, "Command should be 13 bytes")
        #expect(data[0] == 0x05, "Opcode byte 0")
        #expect(data[1] == 0x00, "Opcode byte 1")
        #expect(data[2] == 0x00, "Opcode byte 2")
        #expect(data[11] == 0x05, "sequence byte 0")
    }
    
    @Test("Sequence number increments correctly")
    func testSequenceIncrement() {
        let cmd1 = Libre3ControlCommand.historic(from: 1000, sequence: 1)
        let cmd2 = Libre3ControlCommand.backfill(from: 2000, sequence: 2)
        let cmd3 = Libre3ControlCommand.eventLog(sequence: 3)
        
        #expect(cmd1.build()[11] == 0x01)
        #expect(cmd2.build()[11] == 0x02)
        #expect(cmd3.build()[11] == 0x03)
    }
    
    @Test("Equatable conformance")
    func testEquatable() {
        let cmd1 = Libre3ControlCommand.historic(from: 1000, sequence: 1)
        let cmd2 = Libre3ControlCommand.historic(from: 1000, sequence: 1)
        let cmd3 = Libre3ControlCommand.historic(from: 1000, sequence: 2)
        
        #expect(cmd1 == cmd2, "Same commands should be equal")
        #expect(cmd1 != cmd3, "Different sequences should not be equal")
    }
}

// MARK: - BLE Security Command Protocol Tests

@Suite("Libre3SecurityCommand BLE Tests")
struct Libre3SecurityCommandBLETests {
    
    @Test("BLE security commands have correct raw values")
    func testSecurityCommandRawValues() {
        // Using existing Libre3SecurityCommand enum
        #expect(Libre3SecurityCommand.ecdhStart.rawValue == 0x01)
        #expect(Libre3SecurityCommand.loadCertData.rawValue == 0x02)
        #expect(Libre3SecurityCommand.loadCertDone.rawValue == 0x03)
        #expect(Libre3SecurityCommand.challengeLoadDone.rawValue == 0x08)
        #expect(Libre3SecurityCommand.sendCert.rawValue == 0x09)
        #expect(Libre3SecurityCommand.keyAgreement.rawValue == 0x0D)
        #expect(Libre3SecurityCommand.ephemeralLoadDone.rawValue == 0x0E)
        #expect(Libre3SecurityCommand.authorizeSymmetric.rawValue == 0x11)
    }
    
    @Test("Key security command values match DiaBLE")
    func testKeySecurityCommands() {
        // These are the key commands used in the authentication flow
        #expect(Libre3SecurityCommand.authorizeSymmetric.rawValue == 0x11, "readChallenge equivalent")
        #expect(Libre3SecurityCommand.challengeLoadDone.rawValue == 0x08)
        #expect(Libre3SecurityCommand.loadCertDone.rawValue == 0x03)
    }
}

// MARK: - Libre3SecurityEvent Tests

@Suite("Libre3SecurityEvent Tests")
struct Libre3SecurityEventTests {
    
    @Test("All security events have correct raw values")
    func testSecurityEventRawValues() {
        #expect(Libre3SecurityEvent.unknown.rawValue == 0x00)
        #expect(Libre3SecurityEvent.certificateAccepted.rawValue == 0x04)
        #expect(Libre3SecurityEvent.challengeLoadDone.rawValue == 0x08)
        #expect(Libre3SecurityEvent.certificateReady.rawValue == 0x0A)
        #expect(Libre3SecurityEvent.ephemeralReady.rawValue == 0x0F)
    }
    
    @Test("Security events have descriptions")
    func testSecurityEventDescriptions() {
        #expect(Libre3SecurityEvent.certificateAccepted.description.contains("certificate"))
        #expect(Libre3SecurityEvent.ephemeralReady.description.contains("ephemeral"))
    }
}

// MARK: - Libre3AuthPhase Tests

@Suite("Libre3AuthPhase Tests")
struct Libre3AuthPhaseTests {
    
    @Test("All auth phases are iterable")
    func testAuthPhaseCases() {
        let phases = Libre3AuthPhase.allCases
        #expect(phases.count == 7, "Should have 7 auth phases")
    }
    
    @Test("Auth phases have descriptions")
    func testAuthPhaseDescriptions() {
        for phase in Libre3AuthPhase.allCases {
            #expect(!phase.description.isEmpty, "Phase \(phase.rawValue) should have description")
        }
    }
    
    @Test("Activation starts with certificate")
    func testActivationStartPhase() {
        #expect(Libre3BLEAuthState.activationStartPhase == .sendingCertificate)
    }
    
    @Test("Reconnection starts with challenge")
    func testReconnectionStartPhase() {
        #expect(Libre3BLEAuthState.reconnectionStartPhase == .sendingChallenge)
    }
}

// MARK: - Libre3AuthError Tests

@Suite("Libre3AuthError Tests")
struct Libre3AuthErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() {
        let errors: [Libre3AuthError] = [
            .bluetoothUnavailable,
            .deviceNotFound,
            .connectionFailed,
            .authenticationFailed(reason: "test"),
            .cryptoError("test"),
            .timeout,
            .invalidResponse(expected: 67, received: 40),
            .patchError(patchState: 7)
        ]
        
        for error in errors {
            #expect(!error.description.isEmpty, "Error should have description")
        }
    }
    
    @Test("Invalid response includes byte counts")
    func testInvalidResponseDescription() {
        let error = Libre3AuthError.invalidResponse(expected: 67, received: 40)
        #expect(error.description.contains("67"))
        #expect(error.description.contains("40"))
    }
    
    @Test("Errors are equatable")
    func testErrorEquatable() {
        let e1 = Libre3AuthError.timeout
        let e2 = Libre3AuthError.timeout
        let e3 = Libre3AuthError.connectionFailed
        
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
}

// MARK: - Libre3BLEAuthState Tests

@Suite("Libre3BLEAuthState Tests")
struct Libre3BLEAuthStateTests {
    
    @Test("Initial state is disconnected")
    func testInitialState() {
        let state = Libre3BLEAuthState.disconnected
        #expect(!state.isConnected)
        #expect(!state.canReceiveGlucose)
        #expect(!state.canSendCommands)
    }
    
    @Test("Ready state has full capabilities")
    func testReadyState() {
        let state = Libre3BLEAuthState.ready
        #expect(state.isConnected)
        #expect(state.canReceiveGlucose)
        #expect(state.canSendCommands)
    }
    
    @Test("Connecting state is connected but not ready")
    func testConnectingState() {
        let state = Libre3BLEAuthState.connecting
        #expect(state.isConnected)
        #expect(!state.canReceiveGlucose)
        #expect(!state.canSendCommands)
    }
    
    @Test("Authenticated state can send commands")
    func testAuthenticatedState() {
        let state = Libre3BLEAuthState.authenticated
        #expect(state.isConnected)
        #expect(!state.canReceiveGlucose)
        #expect(state.canSendCommands)
    }
    
    @Test("Error state is not connected")
    func testErrorState() {
        let state = Libre3BLEAuthState.error(.timeout)
        #expect(!state.isConnected)
        #expect(!state.canReceiveGlucose)
        #expect(!state.canSendCommands)
    }
    
    @Test("Disconnected can only transition to connecting")
    func testDisconnectedTransitions() {
        let state = Libre3BLEAuthState.disconnected
        let validNext = state.validNextStates
        #expect(validNext.count == 1)
        #expect(validNext.contains(.connecting))
    }
    
    @Test("Connecting can transition to auth or error")
    func testConnectingTransitions() {
        let state = Libre3BLEAuthState.connecting
        let validNext = state.validNextStates
        
        // Should include activation start, reconnection start, error, and disconnected
        #expect(validNext.count == 4)
        #expect(validNext.contains(.authenticating(phase: .sendingCertificate)))
        #expect(validNext.contains(.authenticating(phase: .sendingChallenge)))
        #expect(validNext.contains(.error(.connectionFailed)))
        #expect(validNext.contains(.disconnected))
    }
    
    @Test("Authenticating phases follow expected order for activation")
    func testActivationAuthOrder() {
        // Activation flow: certificate → patch cert → ephemeral → patch ephemeral → challenge → response → kAuth
        let phases: [Libre3AuthPhase] = [
            .sendingCertificate,
            .receivingPatchCertificate,
            .sendingEphemeral,
            .receivingPatchEphemeral,
            .sendingChallenge,
            .sendingResponse,
            .receivingKAuth
        ]
        
        for (i, phase) in phases.dropLast().enumerated() {
            let state = Libre3BLEAuthState.authenticating(phase: phase)
            let nextStates = state.validNextStates
            let expectedNext = phases[i + 1]
            
            #expect(nextStates.contains(.authenticating(phase: expectedNext)),
                    "Phase \(phase) should allow transition to \(expectedNext)")
        }
    }
    
    @Test("KAuth phase transitions to authenticated")
    func testKAuthToAuthenticated() {
        let state = Libre3BLEAuthState.authenticating(phase: .receivingKAuth)
        let validNext = state.validNextStates
        #expect(validNext.contains(.authenticated))
    }
    
    @Test("Authenticated transitions to subscribing")
    func testAuthenticatedToSubscribing() {
        let state = Libre3BLEAuthState.authenticated
        let validNext = state.validNextStates
        #expect(validNext.contains(.subscribing))
    }
    
    @Test("Subscribing transitions to ready")
    func testSubscribingToReady() {
        let state = Libre3BLEAuthState.subscribing
        let validNext = state.validNextStates
        #expect(validNext.contains(.ready))
    }
    
    @Test("States are equatable")
    func testStateEquatable() {
        let s1 = Libre3BLEAuthState.authenticating(phase: .sendingChallenge)
        let s2 = Libre3BLEAuthState.authenticating(phase: .sendingChallenge)
        let s3 = Libre3BLEAuthState.authenticating(phase: .sendingResponse)
        
        #expect(s1 == s2)
        #expect(s1 != s3)
    }
    
    @Test("Error states with same error are equal")
    func testErrorStateEquatable() {
        let s1 = Libre3BLEAuthState.error(.timeout)
        let s2 = Libre3BLEAuthState.error(.timeout)
        let s3 = Libre3BLEAuthState.error(.connectionFailed)
        
        #expect(s1 == s2)
        #expect(s1 != s3)
    }
}

// MARK: - Ephemeral-Only ECDH Flow Tests (LIBRE3-024g)

@Suite("Libre3 Ephemeral-Only ECDH Flow")
struct Libre3EphemeralOnlyECDHTests {
    
    /// LIBRE3-024g: Verify ephemeral-only ECDH works without app static private key
    ///
    /// Key insight from LIBRE3-024e: "Sensor verifies ECDH result, not key provenance"
    /// This means we can use fresh CryptoKit ephemeral keys instead of SKB-protected keys.
    
    @Test("Ephemeral key pair can be generated fresh each session")
    func testFreshEphemeralKeyGeneration() {
        // Generate two independent ephemeral key pairs
        let session1 = Libre3ECDH(securityVersion: .version1)
        let session2 = Libre3ECDH(securityVersion: .version1)
        
        // Each should have different public keys (fresh ephemeral)
        #expect(session1.ephemeralPublicKey != session2.ephemeralPublicKey,
                "Fresh sessions should generate different ephemeral keys")
        
        // Both should be valid P-256 uncompressed points
        #expect(session1.ephemeralPublicKey.count == 65)
        #expect(session2.ephemeralPublicKey.count == 65)
        #expect(session1.ephemeralPublicKey[0] == 0x04)
        #expect(session2.ephemeralPublicKey[0] == 0x04)
    }
    
    @Test("Ephemeral ECDH produces valid shared secret with any peer")
    func testEphemeralECDHWithAnyPeer() throws {
        // Simulate app side (our implementation)
        let appECDH = Libre3ECDH(securityVersion: .version1)
        
        // Simulate sensor side (another ephemeral key)
        let sensorECDH = Libre3ECDH(securityVersion: .version0)  // Different version, shouldn't matter
        
        // Both derive same shared secret
        let appSecret = try appECDH.deriveSharedSecret(patchEphemeralKey: sensorECDH.ephemeralPublicKey)
        let sensorSecret = try sensorECDH.deriveSharedSecret(patchEphemeralKey: appECDH.ephemeralPublicKey)
        
        #expect(appSecret == sensorSecret, "ECDH must produce same shared secret on both sides")
        #expect(appSecret.count == 32, "P-256 shared secret is 32 bytes")
    }
    
    @Test("Ephemeral ECDH with fixture patch key produces 32-byte secret")
    func testEphemeralECDHWithFixtureKey() throws {
        let appECDH = Libre3ECDH(securityVersion: .version1)
        
        // Load patch ephemeral from fixture (real sensor data)
        let url = Bundle.module.url(forResource: "fixture_libre3_crypto", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let ecdhSession = json["ecdh_session"] as! [String: Any]
        let data6 = ecdhSession["data6"] as! [String: Any]
        let patchEphemeralHex = data6["hex"] as! String
        let patchEphemeralKey = Data(hexString: patchEphemeralHex)!
        
        // Should successfully derive shared secret
        let sharedSecret = try appECDH.deriveSharedSecret(patchEphemeralKey: patchEphemeralKey)
        
        #expect(sharedSecret.count == 32, "Shared secret should be 32 bytes")
        #expect(sharedSecret != Data(repeating: 0, count: 32), "Shared secret should not be all zeros")
    }
    
    @Test("Static app certificate can be sent regardless of ephemeral key")
    func testStaticCertificateWithEphemeralKey() {
        // The protocol sends a static certificate (contains public key from SKB)
        // but performs ECDH with fresh ephemeral keys
        // Sensor verifies certificate format but not cryptographic binding
        
        let ephemeral = Libre3ECDH(securityVersion: .version0)
        let certificate = ephemeral.appCertificate
        
        // Certificate is always the static one for that version
        #expect(certificate == Libre3AppCertificates.certificate0)
        #expect(certificate.count == 162)
        
        // Public key in certificate is different from ephemeral key
        let certPubKey = certificate.subdata(in: 33..<98)  // 65 bytes at offset 33
        #expect(certPubKey != ephemeral.ephemeralPublicKey,
                "Certificate public key should differ from ephemeral key")
    }
    
    @Test("Full ephemeral-only session simulation")
    func testFullEphemeralOnlySession() throws {
        // === App Side ===
        let appECDH = Libre3ECDH(securityVersion: .version1)
        
        // Step 1: App sends static certificate (sensor verifies format)
        let appCert = appECDH.appCertificate
        #expect(appCert.count == 162)
        
        // === Sensor Side (simulated) ===
        let sensorECDH = Libre3ECDH(securityVersion: .version1)
        
        // Step 2: Exchange ephemeral public keys
        let appEphPub = appECDH.ephemeralPublicKey
        let sensorEphPub = sensorECDH.ephemeralPublicKey
        
        // Step 3: Both compute same shared secret
        let appShared = try appECDH.deriveSharedSecret(patchEphemeralKey: sensorEphPub)
        let sensorShared = try sensorECDH.deriveSharedSecret(patchEphemeralKey: appEphPub)
        #expect(appShared == sensorShared)
        
        // Step 4: Derive kAuth using X9.62 KDF
        let appKAuth = Libre3X962KDF.deriveKAuth(from: appShared)
        let sensorKAuth = Libre3X962KDF.deriveKAuth(from: sensorShared)
        #expect(appKAuth == sensorKAuth, "Both sides derive same kAuth")
        #expect(appKAuth.count == 16, "kAuth is 16 bytes (AES-128)")
        
        // Step 5: Sensor generates session keys and sends encrypted challenge
        let kEnc = Data((0..<16).map { UInt8($0 ^ 0xAB) })
        let ivEnc = Data((0..<8).map { UInt8($0 ^ 0xCD) })
        let r1 = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let r2 = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        var challengePlaintext = Data()
        challengePlaintext.append(r2)
        challengePlaintext.append(r1)
        challengePlaintext.append(kEnc)
        challengePlaintext.append(ivEnc)
        #expect(challengePlaintext.count == 56)
        
        // Encrypt challenge with kAuth (sensor side)
        let challengeNonce = Data((0..<13).map { UInt8($0) })
        let encryptedChallenge = try Libre3AesCcm.encrypt(
            plaintext: challengePlaintext,
            key: sensorKAuth,
            nonce: challengeNonce
        )
        
        // Step 6: App decrypts challenge
        let decryptedChallenge = try Libre3AesCcm.decrypt(
            ciphertext: encryptedChallenge,
            key: appKAuth,
            nonce: challengeNonce
        )
        #expect(decryptedChallenge == challengePlaintext)
        
        // Step 7: Extract session keys
        let context = try Libre3ECDH.extractSessionKeys(from: decryptedChallenge)
        #expect(context.kEnc == kEnc, "Extracted kEnc should match sensor's")
        #expect(context.ivEnc == ivEnc, "Extracted ivEnc should match sensor's")
        
        // === Session Established ===
        // Both sides now have kEnc/ivEnc for packet encryption
    }
}

// MARK: - X9.62 KDF Tests (LIBRE3-024g)

@Suite("Libre3 X9.62 KDF")
struct Libre3X962KDFTests {
    
    @Test("KDF produces deterministic output for same input")
    func testKDFDeterministic() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        
        let key1 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16)
        let key2 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16)
        
        #expect(key1 == key2, "Same input should produce same output")
    }
    
    @Test("KDF produces different output for different secrets")
    func testKDFDifferentSecrets() {
        let secret1 = Data((0..<32).map { UInt8($0) })
        let secret2 = Data((0..<32).map { UInt8($0 ^ 0xFF) })
        
        let key1 = Libre3X962KDF.deriveKey(sharedSecret: secret1, keyLength: 16)
        let key2 = Libre3X962KDF.deriveKey(sharedSecret: secret2, keyLength: 16)
        
        #expect(key1 != key2, "Different secrets should produce different keys")
    }
    
    @Test("KDF respects requested key length")
    func testKDFKeyLength() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        
        let key16 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16)
        let key32 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 32)
        let key48 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 48)
        
        #expect(key16.count == 16)
        #expect(key32.count == 32)
        #expect(key48.count == 48)
        
        // Longer keys should be prefix-compatible (same hash blocks)
        #expect(key32.prefix(16) == key16)
    }
    
    @Test("KDF includes sharedInfo in derivation")
    func testKDFSharedInfo() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        let sharedInfo1 = Data("info1".utf8)
        let sharedInfo2 = Data("info2".utf8)
        
        let key1 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16, sharedInfo: sharedInfo1)
        let key2 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16, sharedInfo: sharedInfo2)
        let key3 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16, sharedInfo: Data())
        
        #expect(key1 != key2, "Different sharedInfo should produce different keys")
        #expect(key1 != key3, "Empty vs non-empty sharedInfo should differ")
    }
    
    @Test("deriveKAuth produces 16-byte key")
    func testDeriveKAuth() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        
        let kAuth = Libre3X962KDF.deriveKAuth(from: sharedSecret)
        
        #expect(kAuth.count == 16, "kAuth should be 16 bytes for AES-128")
    }
    
    @Test("deriveKAuth is equivalent to deriveKey with empty sharedInfo")
    func testDeriveKAuthEquivalence() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        
        let kAuth = Libre3X962KDF.deriveKAuth(from: sharedSecret)
        let equivalent = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 16, sharedInfo: Data())
        
        #expect(kAuth == equivalent)
    }
    
    @Test("KDF with real ECDH shared secret")
    func testKDFWithRealECDH() throws {
        // Generate real ECDH keys
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        let ecdh2 = Libre3ECDH(securityVersion: .version1)
        
        let sharedSecret = try ecdh1.deriveSharedSecret(patchEphemeralKey: ecdh2.ephemeralPublicKey)
        
        // Derive kAuth
        let kAuth = Libre3X962KDF.deriveKAuth(from: sharedSecret)
        
        #expect(kAuth.count == 16)
        #expect(kAuth != Data(repeating: 0, count: 16), "kAuth should not be all zeros")
    }
    
    @Test("KDF counter increments for multi-block output")
    func testKDFMultiBlock() {
        let sharedSecret = Data((0..<32).map { UInt8($0) })
        
        // Request 64 bytes (requires 2 SHA-256 blocks)
        let key64 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 64)
        
        #expect(key64.count == 64)
        
        // First 32 bytes should match single-block derivation
        let key32 = Libre3X962KDF.deriveKey(sharedSecret: sharedSecret, keyLength: 32)
        #expect(key64.prefix(32) == key32)
        
        // Second 32 bytes should be different (counter incremented)
        #expect(key64.suffix(32) != key64.prefix(32))
    }
}

// MARK: - Libre3Manager Authentication Integration (CGM-PG-005)

@Suite("Libre3Manager ECDH Integration")
struct Libre3ManagerECDHIntegrationTests {
    
    @Test("Security context is nil before authentication")
    func securityContextInitiallyNil() async {
        let config = Libre3ManagerConfig()
        let central = MockBLECentral()
        let manager = Libre3Manager(config: config, central: central)
        
        // Before authentication, security context should be nil
        let context = await manager.currentSecurityContext
        #expect(context == nil)
    }
    
    @Test("authenticate throws when not connected")
    func authenticateRequiresConnection() async throws {
        let config = Libre3ManagerConfig()
        let central = MockBLECentral()
        let manager = Libre3Manager(config: config, central: central)
        
        // Not connected - should throw
        do {
            try await manager.authenticate()
            #expect(Bool(false), "Should throw error when not connected")
        } catch let error as CGMError {
            #expect(error == .connectionFailed)
        }
    }
    
    @Test("ECDH ephemeral key has correct length")
    func ecdhEphemeralKeyLength() {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        #expect(ecdh.ephemeralPublicKey.count == 65, "Public key should be 65 bytes (0x04 + X + Y)")
        #expect(ecdh.ephemeralPublicKey[0] == 0x04, "Public key should start with 0x04")
    }
    
    @Test("ECDH app certificate matches security version")
    func ecdhCertificateMatchesVersion() {
        let ecdh0 = Libre3ECDH(securityVersion: .version0)
        let ecdh1 = Libre3ECDH(securityVersion: .version1)
        
        #expect(ecdh0.appCertificate[1] == 0x00, "Version 0 security level")
        #expect(ecdh1.appCertificate[1] == 0x03, "Version 1 security level")
    }
    
    @Test("deriveSharedSecret rejects invalid key length")
    func deriveSharedSecretRejectsInvalidKey() throws {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        
        // Too short
        do {
            _ = try ecdh.deriveSharedSecret(patchEphemeralKey: Data(repeating: 0x04, count: 32))
            #expect(Bool(false), "Should throw for short key")
        } catch let error as Libre3CryptoError {
            if case .invalidKeyLength(let expected, let actual) = error {
                #expect(expected == 65)
                #expect(actual == 32)
            }
        }
    }
    
    @Test("deriveSharedSecret rejects invalid key format")
    func deriveSharedSecretRejectsInvalidFormat() throws {
        let ecdh = Libre3ECDH(securityVersion: .version1)
        
        // Wrong prefix (should be 0x04 for uncompressed)
        var invalidKey = Data(repeating: 0x00, count: 65)
        invalidKey[0] = 0x02  // Compressed format - not supported
        
        do {
            _ = try ecdh.deriveSharedSecret(patchEphemeralKey: invalidKey)
            #expect(Bool(false), "Should throw for wrong format")
        } catch let error as Libre3CryptoError {
            if case .invalidKeyFormat = error {
                // Expected
            } else {
                throw error
            }
        }
    }
    
    @Test("extractSessionKeys requires 56 bytes minimum")
    func extractSessionKeysRequiresMinimumLength() throws {
        // Too short
        do {
            _ = try Libre3ECDH.extractSessionKeys(from: Data(repeating: 0, count: 40))
            #expect(Bool(false), "Should throw for short data")
        } catch let error as Libre3CryptoError {
            if case .insufficientData(let expected, let actual) = error {
                #expect(expected == 56)
                #expect(actual == 40)
            }
        }
    }
    
    @Test("extractSessionKeys parses session keys correctly")
    func extractSessionKeysParsesCorrectly() throws {
        // Build mock decrypted challenge: [r2(16)][r1(16)][kEnc(16)][ivEnc(8)]
        var mockChallenge = Data()
        mockChallenge.append(Data(repeating: 0xAA, count: 16))  // r2
        mockChallenge.append(Data(repeating: 0xBB, count: 16))  // r1
        mockChallenge.append(Data(repeating: 0xCC, count: 16))  // kEnc
        mockChallenge.append(Data(repeating: 0xDD, count: 8))   // ivEnc
        
        let context = try Libre3ECDH.extractSessionKeys(from: mockChallenge)
        
        #expect(context.kEnc.count == 16)
        #expect(context.ivEnc.count == 8)
        #expect(context.kEnc == Data(repeating: 0xCC, count: 16))
        #expect(context.ivEnc == Data(repeating: 0xDD, count: 8))
    }
}
