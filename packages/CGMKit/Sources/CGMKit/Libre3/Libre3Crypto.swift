//
//  Libre3Crypto.swift
//  CGMKit
//
//  ECDH key exchange and session crypto for Libre 3 sensors.
//  Based on protocol documented in docs/protocols/LIBRE3-KEY-DERIVATION.md
//
//  Copyright (C) 2026 T1Pal. Licensed under MIT.
//  ECDH keys from Juggluco (GPLv3) - see Libre3Keys.swift
//

import Foundation
import CryptoSwift

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

// MARK: - BCSecurityContext

/// Session encryption context after ECDH handshake completes.
/// Matches DiaBLE's BCSecurityContext structure.
public struct Libre3SecurityContext: Sendable {
    /// Session encryption key (16 bytes, from ECDH KDF)
    public let kEnc: Data
    
    /// Session initialization vector (8 bytes, from ECDH KDF)
    public let ivEnc: Data
    
    /// Outgoing packet sequence number (little-endian in nonce)
    public var outCryptoSequence: UInt16 = 0
    
    /// Incoming packet sequence number
    public var inCryptoSequence: UInt16 = 0
    
    /// AES-CCM tag length (4 bytes for Libre 3)
    public static let tagLength = 4
    
    /// Nonce length (13 bytes)
    public static let nonceLength = 13
    
    public init(kEnc: Data, ivEnc: Data) {
        precondition(kEnc.count == 16, "kEnc must be 16 bytes")
        precondition(ivEnc.count == 8, "ivEnc must be 8 bytes")
        self.kEnc = kEnc
        self.ivEnc = ivEnc
    }
    
    /// Build 13-byte nonce for AES-CCM
    /// Format: [sequence(2)][descriptor(3)][ivEnc(8)]
    public func buildNonce(packetType: Int = 0, outgoing: Bool = true) -> Data {
        var nonce = Data(count: Self.nonceLength)
        let seq = outgoing ? outCryptoSequence : inCryptoSequence
        
        // Bytes 0-1: sequence number (little-endian)
        nonce[0] = UInt8(seq & 0xFF)
        nonce[1] = UInt8((seq >> 8) & 0xFF)
        
        // Bytes 2-4: packet descriptor
        let descriptor = Libre3PacketDescriptor.descriptor(for: packetType)
        nonce[2] = descriptor[0]
        nonce[3] = descriptor[1]
        nonce[4] = descriptor[2]
        
        // Bytes 5-12: ivEnc
        for i in 0..<8 {
            nonce[5 + i] = ivEnc[i]
        }
        
        return nonce
    }
    
    /// Increment outgoing sequence after sending a packet
    public mutating func incrementOutSequence() {
        outCryptoSequence &+= 1
    }
    
    /// Increment incoming sequence after receiving a packet
    public mutating func incrementInSequence() {
        inCryptoSequence &+= 1
    }
}

// MARK: - ECDH Key Exchange

/// ECDH key exchange for Libre 3 authentication.
/// Uses P-256 (secp256r1) curve via CryptoKit.
public struct Libre3ECDH: Sendable {
    
    /// Our ephemeral key pair
    public let ephemeralPrivateKey: P256.KeyAgreement.PrivateKey
    
    /// Our ephemeral public key (65 bytes, uncompressed)
    public var ephemeralPublicKey: Data {
        // CryptoKit returns x963 representation: 0x04 + X + Y
        ephemeralPrivateKey.publicKey.x963Representation
    }
    
    /// Security version being used
    public let securityVersion: Libre3SecurityVersion
    
    /// Initialize ECDH with a new ephemeral key pair
    public init(securityVersion: Libre3SecurityVersion = .version1) {
        self.ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        self.securityVersion = securityVersion
    }
    
    /// Initialize ECDH with existing private key (for testing)
    public init(privateKey: P256.KeyAgreement.PrivateKey, securityVersion: Libre3SecurityVersion = .version1) {
        self.ephemeralPrivateKey = privateKey
        self.securityVersion = securityVersion
    }
    
    /// Get the app certificate for this security version
    public var appCertificate: Data {
        Libre3AppCertificates.certificate(for: securityVersion)
    }
    
    /// Perform ECDH key agreement with sensor's ephemeral public key
    /// - Parameter patchEphemeralKey: Sensor's 65-byte ephemeral public key (0x04 + X + Y)
    /// - Returns: Shared secret (32 bytes)
    public func deriveSharedSecret(patchEphemeralKey: Data) throws -> Data {
        guard patchEphemeralKey.count == 65 else {
            throw Libre3CryptoError.invalidKeyLength(expected: 65, actual: patchEphemeralKey.count)
        }
        guard patchEphemeralKey[0] == 0x04 else {
            throw Libre3CryptoError.invalidKeyFormat
        }
        
        // Parse sensor's public key from x963 representation
        let patchPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: patchEphemeralKey)
        
        // Perform ECDH
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: patchPublicKey)
        
        // Return raw shared secret bytes
        return sharedSecret.withUnsafeBytes { Data($0) }
    }
    
    /// Derive session keys from decrypted challenge response.
    /// The decrypted challenge contains: [r2(16)][r1(16)][kEnc(16)][ivEnc(8)]
    /// - Parameter decryptedChallenge: 56-byte decrypted challenge data
    /// - Returns: Security context with session keys
    public static func extractSessionKeys(from decryptedChallenge: Data) throws -> Libre3SecurityContext {
        guard decryptedChallenge.count >= 56 else {
            throw Libre3CryptoError.insufficientData(expected: 56, actual: decryptedChallenge.count)
        }
        
        // Bytes 32-47: kEnc (session encryption key)
        let kEnc = decryptedChallenge.subdata(in: 32..<48)
        
        // Bytes 48-55: ivEnc (session IV)
        let ivEnc = decryptedChallenge.subdata(in: 48..<56)
        
        return Libre3SecurityContext(kEnc: kEnc, ivEnc: ivEnc)
    }
}

// MARK: - X9.62 Key Derivation Function

/// X9.62 Key Derivation Function (ECDH_KDF_X9_62)
///
/// Implements ANSI X9.62-2005 key derivation as used by Libre 3 for kAuth derivation.
/// KDF(Z, keyLen, sharedInfo) = SHA256(counter || Z || sharedInfo) for each 32-byte block
///
/// Reference: docs/protocols/LIBRE3-KEY-DERIVATION.md
/// Trace: LIBRE3-024d, LIBRE3-024g
public struct Libre3X962KDF: Sendable {
    
    /// Derive key material from ECDH shared secret using X9.62 KDF
    ///
    /// - Parameters:
    ///   - sharedSecret: ECDH shared secret (Z), typically 32 bytes for P-256
    ///   - keyLength: Desired output key length in bytes
    ///   - sharedInfo: Additional info to include in derivation (may be empty)
    /// - Returns: Derived key material of requested length
    public static func deriveKey(
        sharedSecret: Data,
        keyLength: Int,
        sharedInfo: Data = Data()
    ) -> Data {
        var result = Data()
        var counter: UInt32 = 1
        
        while result.count < keyLength {
            // Build input: counter (big-endian) || Z || sharedInfo
            var hashInput = Data()
            
            // Counter as 4-byte big-endian
            hashInput.append(UInt8((counter >> 24) & 0xFF))
            hashInput.append(UInt8((counter >> 16) & 0xFF))
            hashInput.append(UInt8((counter >> 8) & 0xFF))
            hashInput.append(UInt8(counter & 0xFF))
            
            // Shared secret (Z)
            hashInput.append(sharedSecret)
            
            // Shared info
            hashInput.append(sharedInfo)
            
            // SHA-256 hash
            #if canImport(CryptoKit)
            let digest = SHA256.hash(data: hashInput)
            result.append(contentsOf: digest)
            #elseif canImport(Crypto)
            let digest = SHA256.hash(data: hashInput)
            result.append(contentsOf: digest)
            #endif
            
            counter += 1
        }
        
        // Truncate to requested length
        return result.prefix(keyLength)
    }
    
    /// Derive kAuth from ECDH shared secret for Libre 3 authentication
    ///
    /// This is the intermediate key used to decrypt the challenge containing session keys.
    /// The sensor generates fresh kEnc/ivEnc each session, providing forward secrecy.
    ///
    /// - Parameter sharedSecret: 32-byte ECDH shared secret
    /// - Returns: 16-byte kAuth for challenge decryption
    public static func deriveKAuth(from sharedSecret: Data) -> Data {
        // kAuth is 16 bytes (AES-128 key)
        // sharedInfo appears to be empty based on Juggluco analysis
        return deriveKey(sharedSecret: sharedSecret, keyLength: 16, sharedInfo: Data())
    }
}

// MARK: - AES-CCM Implementation

/// AES-CCM encryption/decryption for Libre 3 session data.
/// Uses 128-bit key, 4-byte tag, 13-byte nonce.
public struct Libre3AesCcm: Sendable {
    
    /// Encrypt plaintext using AES-CCM
    /// - Parameters:
    ///   - plaintext: Data to encrypt
    ///   - key: 16-byte encryption key
    ///   - nonce: 13-byte nonce
    ///   - tagLength: Authentication tag length (default 4)
    /// - Returns: Ciphertext with appended tag
    public static func encrypt(
        plaintext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int = 4
    ) throws -> Data {
        guard key.count == 16 else {
            throw Libre3CryptoError.invalidKeyLength(expected: 16, actual: key.count)
        }
        guard nonce.count == 13 else {
            throw Libre3CryptoError.invalidNonceLength(expected: 13, actual: nonce.count)
        }
        
        // Use CryptoSwift AES-CCM
        let aes = try AES(
            key: Array(key),
            blockMode: CCM(
                iv: Array(nonce),
                tagLength: tagLength,
                messageLength: plaintext.count,
                additionalAuthenticatedData: []
            ),
            padding: .noPadding
        )
        let encrypted = try aes.encrypt(Array(plaintext))
        return Data(encrypted)
    }
    
    /// Decrypt ciphertext using AES-CCM
    /// - Parameters:
    ///   - ciphertext: Data to decrypt (includes tag at end)
    ///   - key: 16-byte encryption key
    ///   - nonce: 13-byte nonce
    ///   - tagLength: Authentication tag length (default 4)
    /// - Returns: Decrypted plaintext
    public static func decrypt(
        ciphertext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int = 4
    ) throws -> Data {
        guard key.count == 16 else {
            throw Libre3CryptoError.invalidKeyLength(expected: 16, actual: key.count)
        }
        guard nonce.count == 13 else {
            throw Libre3CryptoError.invalidNonceLength(expected: 13, actual: nonce.count)
        }
        guard ciphertext.count >= tagLength else {
            throw Libre3CryptoError.insufficientData(expected: tagLength, actual: ciphertext.count)
        }
        
        // Use CryptoSwift AES-CCM
        let messageLength = ciphertext.count - tagLength
        let aes = try AES(
            key: Array(key),
            blockMode: CCM(
                iv: Array(nonce),
                tagLength: tagLength,
                messageLength: messageLength,
                additionalAuthenticatedData: []
            ),
            padding: .noPadding
        )
        let decrypted = try aes.decrypt(Array(ciphertext))
        return Data(decrypted)
    }
}

// MARK: - Errors

/// Crypto errors for Libre 3 operations
public enum Libre3CryptoError: Error, Sendable {
    case invalidKeyLength(expected: Int, actual: Int)
    case invalidKeyFormat
    case invalidNonceLength(expected: Int, actual: Int)
    case insufficientData(expected: Int, actual: Int)
    case authenticationFailed
    case notImplemented(String)
    case ecdhFailed(String)
}

// MARK: - CommonCrypto AES-CCM (iOS/macOS only)

#if canImport(CommonCrypto)
import CommonCrypto

/// AES-CCM implementation for iOS/macOS (delegates to CryptoSwift-based Libre3AesCcm).
/// 
/// **Note**: Now uses CryptoSwift which is pure Swift and cross-platform.
/// This wrapper exists for API compatibility.
public struct Libre3AesCcmCommonCrypto: Sendable {
    
    /// Encrypt plaintext using AES-CCM
    public static func encrypt(
        plaintext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int = 4
    ) throws -> Data {
        try Libre3AesCcm.encrypt(plaintext: plaintext, key: key, nonce: nonce, tagLength: tagLength)
    }
    
    /// Decrypt ciphertext using AES-CCM
    public static func decrypt(
        ciphertext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int = 4
    ) throws -> Data {
        try Libre3AesCcm.decrypt(ciphertext: ciphertext, key: key, nonce: nonce, tagLength: tagLength)
    }
}
#endif
