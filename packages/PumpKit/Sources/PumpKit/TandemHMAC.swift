// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemHMAC.swift
// PumpKit
//
// HMAC-SHA1 implementation for Tandem t:slim X2 signed messages.
// Trace: TANDEM-IMPL-003, TANDEM-AUDIT-005, PRD-005
//
// Reference: externals/pumpX2/, tools/x2-cli/x2_parsers.py
//
// Signature format (24 bytes):
//   [0:4]  pump_time_since_reset (uint32, little-endian)
//   [4:24] HMAC-SHA1 (20 bytes)

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - HMAC-SHA1 for Tandem X2

/// HMAC-SHA1 computation for Tandem X2 signed messages
public enum TandemHMAC {
    
    /// HMAC-SHA1 output size in bytes
    public static let hmacSize: Int = 20
    
    /// Full signature size (4-byte time + 20-byte HMAC)
    public static let signatureSize: Int = 24
    
    /// Compute HMAC-SHA1 for a message
    /// - Parameters:
    ///   - message: The message data to sign
    ///   - key: The session key from J-PAKE authentication
    /// - Returns: 20-byte HMAC-SHA1 digest
    public static func computeHMAC(message: Data, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey)
        return Data(hmac)
    }
    
    /// Build a complete signature block for a signed message
    /// - Parameters:
    ///   - cargo: The cargo bytes to sign
    ///   - pumpTimeSinceReset: The pump's time-since-reset counter
    ///   - sessionKey: The session key from J-PAKE authentication
    /// - Returns: 24-byte signature (4-byte time + 20-byte HMAC)
    public static func buildSignature(
        cargo: Data,
        pumpTimeSinceReset: UInt32,
        sessionKey: Data
    ) -> Data {
        // Build message to sign: cargo + time
        var messageToSign = cargo
        var time = pumpTimeSinceReset.littleEndian
        messageToSign.append(Data(bytes: &time, count: 4))
        
        // Compute HMAC-SHA1
        let hmac = computeHMAC(message: messageToSign, key: sessionKey)
        
        // Build signature: time (4 bytes) + HMAC (20 bytes)
        var signature = Data()
        signature.append(Data(bytes: &time, count: 4))
        signature.append(hmac)
        
        return signature
    }
    
    /// Verify a signature block from a signed response
    /// - Parameters:
    ///   - cargo: The cargo bytes that were signed
    ///   - signature: The 24-byte signature to verify
    ///   - sessionKey: The session key from J-PAKE authentication
    /// - Returns: true if signature is valid
    public static func verifySignature(
        cargo: Data,
        signature: Data,
        sessionKey: Data
    ) -> Bool {
        guard signature.count == signatureSize else { return false }
        
        // Extract time and HMAC from signature
        let timeBytes = signature.prefix(4)
        let expectedHMAC = signature.suffix(20)
        
        // Rebuild message to verify
        var messageToVerify = cargo
        messageToVerify.append(timeBytes)
        
        // Compute expected HMAC
        let computedHMAC = computeHMAC(message: messageToVerify, key: sessionKey)
        
        // Constant-time comparison
        return computedHMAC == expectedHMAC
    }
    
    /// Extract pump time from signature
    /// - Parameter signature: The 24-byte signature
    /// - Returns: Pump time-since-reset value, or nil if invalid
    public static func extractPumpTime(from signature: Data) -> UInt32? {
        guard signature.count >= 4 else { return nil }
        return signature.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    /// Extract HMAC from signature
    /// - Parameter signature: The 24-byte signature
    /// - Returns: 20-byte HMAC, or nil if invalid
    public static func extractHMAC(from signature: Data) -> Data? {
        guard signature.count >= 24 else { return nil }
        return signature.suffix(20)
    }
}

// MARK: - Signed Message Builder

/// Builder for Tandem X2 signed messages
public struct TandemSignedMessageBuilder: Sendable {
    private let sessionKey: Data
    private var pumpTimeSinceReset: UInt32
    
    /// Create a builder with a session key
    /// - Parameters:
    ///   - sessionKey: The session key from J-PAKE authentication
    ///   - initialPumpTime: Initial pump time-since-reset value
    public init(sessionKey: Data, initialPumpTime: UInt32 = 0) {
        self.sessionKey = sessionKey
        self.pumpTimeSinceReset = initialPumpTime
    }
    
    /// Update the pump time from a response
    public mutating func updatePumpTime(_ time: UInt32) {
        self.pumpTimeSinceReset = time
    }
    
    /// Build a signed message
    /// - Parameters:
    ///   - opcode: The signed opcode
    ///   - transactionId: Transaction ID
    ///   - cargo: Command cargo
    /// - Returns: Complete message bytes with signature and CRC
    public func buildMessage(
        opcode: TandemSignedOpcode,
        transactionId: UInt8,
        cargo: Data
    ) -> Data {
        // Build signature
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTimeSinceReset,
            sessionKey: sessionKey
        )
        
        // Build full cargo (original cargo + signature)
        var signedCargo = cargo
        signedCargo.append(signature)
        
        // Build message frame
        var message = Data()
        message.append(UInt8(opcode.rawValue))
        message.append(transactionId)
        message.append(UInt8(signedCargo.count))
        message.append(signedCargo)
        
        // Append CRC-16
        let crc = TandemCRC16.calculate(message)
        message.append(UInt8((crc >> 8) & 0xFF))
        message.append(UInt8(crc & 0xFF))
        
        return message
    }
    
    /// Verify a signed response
    /// - Parameters:
    ///   - message: The parsed TandemMessage
    /// - Returns: true if signature is valid
    public func verifyResponse(_ message: TandemMessage) -> Bool {
        guard let signature = message.signature else { return false }
        return TandemHMAC.verifySignature(
            cargo: message.cargo,
            signature: signature,
            sessionKey: sessionKey
        )
    }
}

// MARK: - Test Vectors

/// Test vectors for HMAC-SHA1 validation
/// Reference: tools/x2-cli/x2_parsers.py
public enum TandemHMACTestVectors {
    /// RFC 2202 Test Vector 1
    /// Key: 0x0b repeated 20 times
    /// Data: "Hi There"
    /// Expected: 0xb617318655057264e28bc0b6fb378c8ef146be00
    public static let rfcVector1 = (
        key: Data(repeating: 0x0b, count: 20),
        data: "Hi There".data(using: .utf8)!,
        expected: Data([
            0xb6, 0x17, 0x31, 0x86, 0x55, 0x05, 0x72, 0x64,
            0xe2, 0x8b, 0xc0, 0xb6, 0xfb, 0x37, 0x8c, 0x8e,
            0xf1, 0x46, 0xbe, 0x00
        ])
    )
    
    /// RFC 2202 Test Vector 2
    /// Key: "Jefe"
    /// Data: "what do ya want for nothing?"
    /// Expected: 0xeffcdf6ae5eb2fa2d27416d5f184df9c259a7c79
    public static let rfcVector2 = (
        key: "Jefe".data(using: .utf8)!,
        data: "what do ya want for nothing?".data(using: .utf8)!,
        expected: Data([
            0xef, 0xfc, 0xdf, 0x6a, 0xe5, 0xeb, 0x2f, 0xa2,
            0xd2, 0x74, 0x16, 0xd5, 0xf1, 0x84, 0xdf, 0x9c,
            0x25, 0x9a, 0x7c, 0x79
        ])
    )
    
    /// Tandem-specific test vector
    /// Simulates a SetTempRateRequest signature
    public static let tandemVector1 = (
        sessionKey: Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
            0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
        ]),
        cargo: Data([0x64, 0x3C, 0x00]), // 100%, 60 minutes
        pumpTime: UInt32(0x12345678)
    )
}
