// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7ECPointOps.swift
// CGMKit - DexcomG7
//
// EC Point and Scalar operations for P-256 curve.
// Extracted from: G7ECOperations.swift
// Trace: JPAKE-EC-001, FILE-HYGIENE-007

import Foundation
import CryptoValidation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

// MARK: - EC Point Operations

/// Elliptic curve point operations for J-PAKE
/// Implements P-256 point arithmetic using CryptoKit where possible,
/// with pure Swift fallback for operations not directly supported.
public enum ECPointOperations {
    
    // MARK: - P-256 Field Constants (JPAKE-EC-001)
    
    /// P-256 field prime p
    /// p = 2^256 - 2^224 + 2^192 + 2^96 - 1
    public static let fieldPrime: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    ]
    
    /// P-256 curve coefficient a = -3 mod p
    /// Stored as p - 3
    public static let curveA: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFC
    ]
    
    /// P-256 curve coefficient b
    public static let curveB: [UInt8] = [
        0x5A, 0xC6, 0x35, 0xD8, 0xAA, 0x3A, 0x93, 0xE7,
        0xB3, 0xEB, 0xBD, 0x55, 0x76, 0x98, 0x86, 0xBC,
        0x65, 0x1D, 0x06, 0xB0, 0xCC, 0x53, 0xB0, 0xF6,
        0x3B, 0xCE, 0x3C, 0x3E, 0x27, 0xD2, 0x60, 0x4B
    ]
    
    /// P-256 generator point G (X coordinate)
    public static let generatorX: [UInt8] = [
        0x6B, 0x17, 0xD1, 0xF2, 0xE1, 0x2C, 0x42, 0x47,
        0xF8, 0xBC, 0xE6, 0xE5, 0x63, 0xA4, 0x40, 0xF2,
        0x77, 0x03, 0x7D, 0x81, 0x2D, 0xEB, 0x33, 0xA0,
        0xF4, 0xA1, 0x39, 0x45, 0xD8, 0x98, 0xC2, 0x96
    ]
    
    /// P-256 generator point G (Y coordinate)
    public static let generatorY: [UInt8] = [
        0x4F, 0xE3, 0x42, 0xE2, 0xFE, 0x1A, 0x7F, 0x9B,
        0x8E, 0xE7, 0xEB, 0x4A, 0x7C, 0x0F, 0x9E, 0x16,
        0x2B, 0xCE, 0x33, 0x57, 0x6B, 0x31, 0x5E, 0xCE,
        0xCB, 0xB6, 0x40, 0x68, 0x37, 0xBF, 0x51, 0xF5
    ]
    
    /// Generator point G as raw 64 bytes (X || Y)
    public static var generatorRaw: Data {
        Data(generatorX) + Data(generatorY)
    }
    
    // MARK: - Point Parsing
    
    /// Parse uncompressed EC point from 65-byte data
    /// - Parameter data: 65 bytes: 0x04 || X (32) || Y (32)
    /// - Returns: P256 public key if valid
    public static func parseUncompressedPoint(_ data: Data) -> P256.Signing.PublicKey? {
        guard data.count == 65, data[0] == 0x04 else { return nil }
        
        do {
            // swift-crypto expects 64-byte raw representation (X || Y)
            return try P256.Signing.PublicKey(rawRepresentation: data.dropFirst())
        } catch {
            return nil
        }
    }
    
    /// Parse raw 64-byte point (X || Y without format prefix)
    public static func parseRawPoint(_ data: Data) -> P256.Signing.PublicKey? {
        guard data.count == 64 else { return nil }
        
        do {
            return try P256.Signing.PublicKey(rawRepresentation: data)
        } catch {
            return nil
        }
    }
    
    /// Parse 32-byte X coordinate only (for specific protocol formats)
    /// Note: This requires Y coordinate recovery which swift-crypto doesn't directly support
    /// For J-PAKE, we typically use uncompressed points
    public static func parseCompressedPoint(_ data: Data) -> P256.Signing.PublicKey? {
        guard data.count == 33, (data[0] == 0x02 || data[0] == 0x03) else { return nil }
        
        do {
            return try P256.Signing.PublicKey(compressedRepresentation: data)
        } catch {
            return nil
        }
    }
    
    /// Serialize public key as uncompressed point (65 bytes)
    public static func serializeUncompressed(_ publicKey: P256.Signing.PublicKey) -> Data {
        var data = Data([0x04])
        data.append(publicKey.rawRepresentation)
        return data
    }
    
    /// Serialize public key as raw X || Y (64 bytes)
    public static func serializeRaw(_ publicKey: P256.Signing.PublicKey) -> Data {
        publicKey.rawRepresentation
    }
    
    // MARK: - EC Point Arithmetic (JPAKE-EC-001)
    
    /// Multiply a point by a scalar: result = point * scalar
    /// Uses OpenSSL via AuditedECOperations for correct, fast EC math.
    /// - Parameters:
    ///   - point: EC point as raw 64 bytes (X || Y) or P256 public key
    ///   - scalar: 32-byte scalar value
    /// - Returns: Result point as raw 64 bytes, or nil on error
    public static func scalarMultiply(point: Data, scalar: Data) -> Data? {
        // Validate inputs
        guard point.count == 64, scalar.count == 32 else { return nil }
        
        // EC-LIB-018: Use audited OpenSSL backend instead of hand-rolled
        return AuditedECOperations.scalarMultiply(point: point, scalar: scalar)
    }
    
    /// Add two EC points: result = p1 + p2
    /// Uses OpenSSL via AuditedECOperations for correct, fast EC math.
    /// - Parameters:
    ///   - p1: First point as raw 64 bytes
    ///   - p2: Second point as raw 64 bytes
    /// - Returns: Sum point as raw 64 bytes
    public static func addPoints(p1: Data, p2: Data) -> Data? {
        guard p1.count == 64, p2.count == 64 else { return nil }
        
        // EC-LIB-018: Use audited OpenSSL backend instead of hand-rolled
        return AuditedECOperations.addPoints(p1, p2)
    }
    
    /// Compute G * scalar (generator point multiplication)
    /// Uses OpenSSL via AuditedECOperations for correct, fast EC math.
    /// - Parameter scalar: 32-byte scalar
    /// - Returns: Result point as raw 64 bytes
    public static func scalarBaseMultiply(scalar: Data) -> Data? {
        // EC-LIB-018: Use audited OpenSSL backend instead of hand-rolled
        return AuditedECOperations.scalarBaseMultiply(scalar: scalar)
    }
}

// Field arithmetic moved to G7FieldArithmetic.swift (CODE-020)

// MARK: - Scalar Operations

/// Scalar (big integer) operations mod P-256 curve order
/// Used for ZKP challenge/response and key derivation
public enum ScalarOperations {
    
    /// P-256 curve order (n)
    /// n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
    public static let curveOrder: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
    ]
    
    /// Generate random scalar in range [1, n-1]
    public static func randomScalar() -> Data {
        // Generate 32 random bytes and reduce mod n
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }
    
    /// Convert password string to scalar
    /// Matches xDrip format: UTF-8 bytes, with "00" prefix for 6-digit codes
    public static func passwordToScalar(_ password: String) -> Data {
        var bytes = password.data(using: .utf8) ?? Data()
        if password.count == 6 {
            // xDrip prefixes 6-digit codes with "00"
            bytes = Data([0x30, 0x30]) + bytes
        }
        return bytes
    }
    
    /// SHA-256 hash to scalar (mod curve order)
    /// Used for ZKP challenge computation
    public static func hashToScalar(_ data: Data) -> Data {
        let hash = SHA256.hash(data: data)
        // Return raw hash bytes - mod reduction happens in EC multiplication
        return Data(hash)
    }
}
