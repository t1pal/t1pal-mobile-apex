// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7JPAKEDerivation.swift
// CGMKit - DexcomG7
//
// Password derivation, session key derivation, and confirmation hash for J-PAKE.
// Extracted from: G7ECOperations.swift
// Trace: JPAKE-DERIVE-001, JPAKE-DERIVE-002, JPAKE-DERIVE-003, FILE-HYGIENE-007

import Foundation
import CryptoValidation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - Password Derivation Variants (JPAKE-DERIVE-001)

/// Password derivation method for J-PAKE authentication
/// Multiple variants to handle protocol uncertainty
public enum PasswordDerivation: String, CaseIterable, Sendable {
    /// Raw UTF-8 bytes with xDrip "00" prefix for 6-digit codes
    case raw = "raw"
    
    /// SHA-256 hash without salt
    case sha256NoSalt = "sha256_no_salt"
    
    /// SHA-256 hash with custom salt
    case sha256Salt = "sha256_salt"
    
    /// Include sensor serial in derivation
    case withSerial = "with_serial"
    
    /// PBKDF2-HMAC-SHA256 (100k iterations)
    case pbkdf2 = "pbkdf2"
    
    /// HKDF-SHA256 expansion
    case hkdf = "hkdf"
    
    /// Default salt used for salted variants
    public static let defaultSalt = Data("G7-JPAKE-PASSWORD".utf8)
    
    /// PBKDF2 iteration count
    public static let pbkdf2Iterations = 100_000
    
    /// Derive password scalar using this method
    /// - Parameters:
    ///   - password: The sensor code (4 or 6 digits)
    ///   - serial: Optional sensor serial for serial-based derivation
    /// - Returns: 32-byte scalar for J-PAKE
    public func derive(password: String, serial: String? = nil) -> Data {
        switch self {
        case .raw:
            return deriveRaw(password)
        case .sha256NoSalt:
            return deriveSHA256NoSalt(password)
        case .sha256Salt:
            return deriveSHA256Salt(password)
        case .withSerial:
            return deriveWithSerial(password, serial: serial ?? "")
        case .pbkdf2:
            return derivePBKDF2(password)
        case .hkdf:
            return deriveHKDF(password)
        }
    }
    
    // MARK: - Derivation Implementations
    
    /// Raw UTF-8 bytes (xDrip method)
    private func deriveRaw(_ password: String) -> Data {
        var bytes = password.data(using: .utf8) ?? Data()
        if password.count == 6 {
            // xDrip prefixes 6-digit codes with "00" (ASCII 0x30, 0x30)
            bytes = Data([0x30, 0x30]) + bytes
        }
        // Pad to 32 bytes for scalar operations
        var result = bytes
        while result.count < 32 {
            result.append(0x00)
        }
        return Data(result.prefix(32))
    }
    
    /// SHA-256 without salt
    private func deriveSHA256NoSalt(_ password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: passwordData))
    }
    
    /// SHA-256 with salt
    private func deriveSHA256Salt(_ password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: passwordData + Self.defaultSalt))
    }
    
    /// Include sensor serial
    private func deriveWithSerial(_ password: String, serial: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        let serialData = serial.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: passwordData + serialData + Self.defaultSalt))
    }
    
    /// PBKDF2-HMAC-SHA256
    private func derivePBKDF2(_ password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        // Simple PBKDF2 implementation using HMAC-SHA256
        return pbkdf2SHA256(password: passwordData, salt: Self.defaultSalt, iterations: Self.pbkdf2Iterations)
    }
    
    /// HKDF-SHA256 expansion
    private func deriveHKDF(_ password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        // HKDF extract then expand
        let prk = hmacSHA256(key: Self.defaultSalt, data: passwordData)
        return hkdfExpand(prk: prk, info: Data("J-PAKE".utf8), length: 32)
    }
    
    // MARK: - Crypto Helpers
    
    /// HMAC-SHA256
    private func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }
    
    /// Simple PBKDF2 implementation
    private func pbkdf2SHA256(password: Data, salt: Data, iterations: Int) -> Data {
        var result = Data(count: 32)
        let block = salt + Data([0x00, 0x00, 0x00, 0x01])  // Block index 1
        
        var u = hmacSHA256(key: password, data: block)
        result = u
        
        for _ in 1..<iterations {
            u = hmacSHA256(key: password, data: u)
            for i in 0..<32 {
                result[i] ^= u[i]
            }
        }
        return result
    }
    
    /// HKDF expand step
    private func hkdfExpand(prk: Data, info: Data, length: Int) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        
        while output.count < length {
            var input = previous
            input.append(info)
            input.append(counter)
            previous = hmacSHA256(key: prk, data: input)
            output.append(previous)
            counter += 1
        }
        return Data(output.prefix(length))
    }
}

// MARK: - Session Key Derivation (JPAKE-DERIVE-002)

/// Session key derivation method for J-PAKE authentication
/// Derives AES-128 key from shared EC point after protocol completion
public enum SessionKeyDerivation: String, CaseIterable, Sendable {
    /// SHA-256 of X coordinate, truncated to 16 bytes (xDrip method)
    case sha256Truncated = "sha256_truncated"
    
    /// Direct SHA-256 of full shared secret (32 bytes)
    case sha256Full = "sha256_full"
    
    /// HKDF-SHA256 with protocol info
    case hkdf = "hkdf"
    
    /// PBKDF2-HMAC-SHA256 with salt
    case pbkdf2 = "pbkdf2"
    
    /// Include full protocol transcript in derivation
    case transcriptBinding = "transcript_binding"
    
    /// Default info string for HKDF
    public static let hkdfInfo = Data("G7-JPAKE-SESSION".utf8)
    
    /// PBKDF2 iteration count for session key
    public static let pbkdf2Iterations = 10_000
    
    /// Derive session key from shared secret
    /// - Parameters:
    ///   - sharedSecret: The shared EC point X coordinate (32 bytes)
    ///   - transcript: Optional protocol transcript for binding
    /// - Returns: 16-byte AES key
    public func derive(sharedSecret: Data, transcript: Data? = nil) -> Data {
        switch self {
        case .sha256Truncated:
            return deriveSHA256Truncated(sharedSecret)
        case .sha256Full:
            return deriveSHA256Full(sharedSecret)
        case .hkdf:
            return deriveHKDF(sharedSecret)
        case .pbkdf2:
            return derivePBKDF2(sharedSecret)
        case .transcriptBinding:
            return deriveTranscriptBinding(sharedSecret, transcript: transcript ?? Data())
        }
    }
    
    // MARK: - Derivation Implementations
    
    /// SHA-256 truncated to 16 bytes (xDrip method)
    /// Reference: Calc.java getShortSharedKey()
    private func deriveSHA256Truncated(_ sharedSecret: Data) -> Data {
        let hash = Data(SHA256.hash(data: sharedSecret))
        return Data(hash.prefix(16))
    }
    
    /// Full SHA-256 (32 bytes)
    private func deriveSHA256Full(_ sharedSecret: Data) -> Data {
        Data(SHA256.hash(data: sharedSecret))
    }
    
    /// HKDF-SHA256 with protocol info
    private func deriveHKDF(_ sharedSecret: Data) -> Data {
        // Extract: PRK = HMAC-SHA256(salt, IKM)
        let salt = Data("G7-JPAKE".utf8)
        let prk = hmacSHA256(key: salt, data: sharedSecret)
        
        // Expand: OKM = HKDF-Expand(PRK, info, 16)
        return hkdfExpand(prk: prk, info: Self.hkdfInfo, length: 16)
    }
    
    /// PBKDF2-HMAC-SHA256
    private func derivePBKDF2(_ sharedSecret: Data) -> Data {
        let salt = Data("G7-SESSION-KEY".utf8)
        let derived = pbkdf2SHA256(password: sharedSecret, salt: salt, iterations: Self.pbkdf2Iterations)
        return Data(derived.prefix(16))
    }
    
    /// Transcript binding: include full protocol messages
    private func deriveTranscriptBinding(_ sharedSecret: Data, transcript: Data) -> Data {
        var input = sharedSecret
        input.append(transcript)
        let hash = Data(SHA256.hash(data: input))
        return Data(hash.prefix(16))
    }
    
    // MARK: - Crypto Helpers (shared with PasswordDerivation)
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }
    
    private func pbkdf2SHA256(password: Data, salt: Data, iterations: Int) -> Data {
        var result = Data(count: 32)
        let block = salt + Data([0x00, 0x00, 0x00, 0x01])
        
        var u = hmacSHA256(key: password, data: block)
        result = u
        
        for _ in 1..<iterations {
            u = hmacSHA256(key: password, data: u)
            for i in 0..<32 {
                result[i] ^= u[i]
            }
        }
        return result
    }
    
    private func hkdfExpand(prk: Data, info: Data, length: Int) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        
        while output.count < length {
            var input = previous
            input.append(info)
            input.append(counter)
            previous = hmacSHA256(key: prk, data: input)
            output.append(previous)
            counter += 1
        }
        return Data(output.prefix(length))
    }
}

// MARK: - Confirmation Hash (JPAKE-DERIVE-003)

/// Confirmation hash computation for J-PAKE authentication
/// Used to prove knowledge of shared key after protocol completion
/// Reference: xDrip Calc.java calculateHash() uses AES(key, challenge||challenge)
public enum ConfirmationHash: String, CaseIterable, Sendable {
    /// AES-ECB encryption of doubled challenge (xDrip method)
    /// Input: 8-byte challenge doubled to 16 bytes
    /// Output: First 8 bytes of AES ciphertext
    case aesDoubled = "aes_doubled"
    
    /// HMAC-SHA256 of challenge with session key
    /// Output: First 8 bytes
    case hmacSha256 = "hmac_sha256"
    
    /// HMAC-SHA256 with role prefix ("client" or "server")
    case hmacWithRole = "hmac_with_role"
    
    /// SHA-256(key || challenge) - simpler variant
    case sha256Concat = "sha256_concat"
    
    /// SHA-256(key || challenge || role) - with role binding
    case sha256WithRole = "sha256_with_role"
    
    /// Standard J-PAKE confirmation: HMAC(key, "KC_1_U" || partyId || otherPartyId || gx1 || gx2 || gx3 || gx4)
    case standardJPAKE = "standard_jpake"
    
    /// Compute confirmation hash
    /// - Parameters:
    ///   - sessionKey: The 16-byte AES session key
    ///   - challenge: The 8-byte challenge from transmitter
    ///   - role: Optional role string ("client" or "server")
    ///   - transcript: Optional protocol transcript for standard J-PAKE
    /// - Returns: 8-byte confirmation value
    public func compute(
        sessionKey: Data,
        challenge: Data,
        role: String? = nil,
        transcript: Data? = nil
    ) -> Data {
        switch self {
        case .aesDoubled:
            return computeAESDoubled(sessionKey: sessionKey, challenge: challenge)
        case .hmacSha256:
            return computeHMACSHA256(sessionKey: sessionKey, challenge: challenge)
        case .hmacWithRole:
            return computeHMACWithRole(sessionKey: sessionKey, challenge: challenge, role: role ?? "client")
        case .sha256Concat:
            return computeSHA256Concat(sessionKey: sessionKey, challenge: challenge)
        case .sha256WithRole:
            return computeSHA256WithRole(sessionKey: sessionKey, challenge: challenge, role: role ?? "client")
        case .standardJPAKE:
            return computeStandardJPAKE(sessionKey: sessionKey, transcript: transcript ?? Data())
        }
    }
    
    /// Verify a confirmation hash
    /// - Parameters:
    ///   - expected: The expected confirmation bytes (8 bytes)
    ///   - sessionKey: The session key
    ///   - challenge: The challenge
    ///   - role: Optional role string
    ///   - transcript: Optional transcript
    /// - Returns: True if confirmation matches
    public func verify(
        expected: Data,
        sessionKey: Data,
        challenge: Data,
        role: String? = nil,
        transcript: Data? = nil
    ) -> Bool {
        let computed = compute(sessionKey: sessionKey, challenge: challenge, role: role, transcript: transcript)
        guard computed.count >= expected.count else { return false }
        return computed.prefix(expected.count) == expected
    }
    
    // MARK: - Implementation Methods
    
    /// AES-ECB encryption of doubled challenge (xDrip method)
    /// Reference: Calc.java lines 104-114
    private func computeAESDoubled(sessionKey: Data, challenge: Data) -> Data {
        // Double the challenge to 16 bytes
        let paddedChallenge = challenge.count >= 8 
            ? Data(challenge.prefix(8))
            : challenge + Data(repeating: 0, count: 8 - challenge.count)
        var doubledChallenge = Data()
        doubledChallenge.append(paddedChallenge)
        doubledChallenge.append(paddedChallenge)
        
        // AES-ECB encrypt
        guard let encrypted = aesECBEncrypt(key: sessionKey, data: doubledChallenge) else {
            // Fallback to HMAC if AES fails
            return computeHMACSHA256(sessionKey: sessionKey, challenge: challenge)
        }
        return Data(encrypted.prefix(8))
    }
    
    /// HMAC-SHA256 truncated to 8 bytes
    private func computeHMACSHA256(sessionKey: Data, challenge: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: challenge, using: SymmetricKey(data: sessionKey))
        return Data(Data(hmac).prefix(8))
    }
    
    /// HMAC-SHA256 with role prefix
    private func computeHMACWithRole(sessionKey: Data, challenge: Data, role: String) -> Data {
        var input = Data(role.utf8)
        input.append(challenge)
        let hmac = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: sessionKey))
        return Data(Data(hmac).prefix(8))
    }
    
    /// SHA-256(key || challenge) truncated to 8 bytes
    private func computeSHA256Concat(sessionKey: Data, challenge: Data) -> Data {
        var input = sessionKey
        input.append(challenge)
        let hash = SHA256.hash(data: input)
        return Data(Data(hash).prefix(8))
    }
    
    /// SHA-256(key || challenge || role) truncated to 8 bytes
    private func computeSHA256WithRole(sessionKey: Data, challenge: Data, role: String) -> Data {
        var input = sessionKey
        input.append(challenge)
        input.append(Data(role.utf8))
        let hash = SHA256.hash(data: input)
        return Data(Data(hash).prefix(8))
    }
    
    /// Standard J-PAKE confirmation with transcript binding
    /// Uses HMAC(key, "KC_1_U" || transcript)
    private func computeStandardJPAKE(sessionKey: Data, transcript: Data) -> Data {
        // Standard J-PAKE uses "KC_1_U" and "KC_1_V" as key confirmation tags
        var input = Data("KC_1_U".utf8)
        input.append(transcript)
        let hmac = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: sessionKey))
        return Data(Data(hmac).prefix(8))
    }
    
    // MARK: - AES Helper
    
    /// AES-128-ECB encryption (single block)
    private func aesECBEncrypt(key: Data, data: Data) -> Data? {
        guard key.count == 16, data.count == 16 else { return nil }
        
        // Use CommonCrypto for AES-ECB on Apple platforms
        #if canImport(CommonCrypto)
        var encrypted = [UInt8](repeating: 0, count: 16)
        var numBytesEncrypted: size_t = 0
        
        let status = key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    keyBytes.baseAddress, key.count,
                    nil, // no IV for ECB
                    dataBytes.baseAddress, data.count,
                    &encrypted, encrypted.count,
                    &numBytesEncrypted
                )
            }
        }
        
        return status == kCCSuccess ? Data(encrypted) : nil
        #else
        // Linux: Use Crypto library AES
        // Note: swift-crypto doesn't expose raw AES-ECB, need platform-specific
        // For now, fall back to software implementation
        return aesECBSoftware(key: key, data: data)
        #endif
    }
    
    /// Software AES-128-ECB encryption for cross-platform support (G7-RESEARCH-007)
    /// Implements FIPS 197 AES-128 in pure Swift for Linux compatibility
    private func aesECBSoftware(key: Data, data: Data) -> Data? {
        guard key.count == 16, data.count == 16 else { return nil }
        return AES128Software.encrypt(block: data, key: key)
    }
}

// AES-128 moved to G7AES128.swift (CODE-020)

// Message framing moved to G7MessageFraming.swift (CODE-020)

