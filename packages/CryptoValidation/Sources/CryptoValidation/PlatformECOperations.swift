// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PlatformECOperations.swift
// CryptoValidation
//
// Platform EC operations using CryptoKit/swift-crypto.
// This is the audited implementation used for production and validation.
//
// Trace: EC-LIB-012, EC-LIB-014, PRD-008 REQ-BLE-008

import Foundation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

// MARK: - Platform EC Operations

/// Platform EC operations using CryptoKit (Apple) or swift-crypto (Linux).
///
/// **Limitations:**
/// CryptoKit doesn't expose raw EC point arithmetic. We use ECDH key agreement
/// to perform scalar multiplication, but point addition is NOT directly supported.
///
/// For operations CryptoKit can't do natively, we fall back to ReferenceECOperations
/// but log a warning for future replacement with a proper audited library.
///
/// **Validation Strategy (EC-LIB-012):**
/// This implementation is considered more trustworthy than hand-rolled code
/// because CryptoKit/swift-crypto are audited and tested by thousands of users.
public enum PlatformECOperations: ECOperationsProvider {
    
    // MARK: - Point Operations
    
    /// Add two EC points: result = p1 + p2
    ///
    /// **Note:** CryptoKit doesn't support raw point addition.
    /// Use `AuditedECOperations.addPoints()` instead (OpenSSL backend).
    public static func addPoints(_ p1: Data, _ p2: Data) -> Data? {
        // CryptoKit limitation: No native point addition support
        // Use AuditedECOperations for full EC operations (EC-LIB-013 complete)
        return nil
    }
    
    /// Multiply point by scalar using ECDH key agreement.
    ///
    /// ECDH computes: sharedSecret = HKDF(ECDH(privateKey, publicPoint))
    /// We can't directly extract the raw point multiplication result.
    ///
    /// **Note:** Use `AuditedECOperations.scalarMultiply()` instead (OpenSSL backend).
    public static func scalarMultiply(point: Data, scalar: Data) -> Data? {
        // CryptoKit limitation: ECDH applies HKDF, can't get raw multiplication
        // Use AuditedECOperations for full EC operations (EC-LIB-013 complete)
        return nil
    }
    
    /// Multiply generator by scalar: result = G * scalar
    ///
    /// This CAN be done with CryptoKit by creating a private key from the scalar
    /// and extracting its public key.
    public static func scalarBaseMultiply(scalar: Data) -> Data? {
        guard scalar.count == 32 else { return nil }
        
        do {
            // Create private key from scalar bytes
            let privateKey = try P256.Signing.PrivateKey(rawRepresentation: scalar)
            // The public key is G * scalar
            return privateKey.publicKey.rawRepresentation
        } catch {
            // Scalar might be invalid (0, >= order)
            return nil
        }
    }
    
    /// Negate a point: result = -P (same X, negated Y)
    ///
    /// **Note:** CryptoKit doesn't support point negation.
    /// Use `AuditedECOperations.negatePoint()` instead (OpenSSL backend).
    public static func negatePoint(_ point: Data) -> Data? {
        // CryptoKit limitation: No point negation support
        // Use AuditedECOperations for full EC operations (EC-LIB-013 complete)
        return nil
    }
    
    /// Validate that a point is on the P-256 curve.
    ///
    /// This CAN be done with CryptoKit by attempting to parse the point.
    public static func isValidPoint(_ data: Data) -> Bool {
        guard data.count == 64 else { return false }
        
        do {
            // If CryptoKit can parse it, it's valid
            _ = try P256.Signing.PublicKey(rawRepresentation: data)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Platform Capability Check

public extension PlatformECOperations {
    
    /// Operations that CryptoKit can do natively
    enum NativeCapability: String, CaseIterable, Sendable {
        case scalarBaseMultiply = "G * scalar (via private key creation)"
        case isValidPoint = "Point validation (via public key parsing)"
    }
    
    /// Operations that use AuditedECOperations (OpenSSL backend)
    enum FallbackCapability: String, CaseIterable, Sendable {
        case addPoints = "Point addition (use AuditedECOperations)"
        case scalarMultiply = "Arbitrary scalar multiplication (use AuditedECOperations)"
        case negatePoint = "Point negation (use AuditedECOperations)"
    }
    
    /// Check if an operation uses native CryptoKit implementation
    static func isNative(_ operation: String) -> Bool {
        NativeCapability.allCases.contains { $0.rawValue.contains(operation) }
    }
}
