// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ECOperationsProvider.swift
// CryptoValidation
//
// Protocol defining EC point operations for J-PAKE.
// Enables cross-validation between hand-rolled and audited implementations.
//
// Trace: EC-LIB-012, EC-LIB-014, PRD-008 REQ-BLE-008

import Foundation

// MARK: - EC Operations Protocol

/// Protocol for elliptic curve point operations on P-256.
///
/// This protocol enables swapping between implementations:
/// - `ReferenceECOperations`: Hand-rolled, used as validation oracle
/// - `PlatformECOperations`: CryptoKit/swift-crypto for production
///
/// **Validation Strategy (EC-LIB-012):**
/// When tests compare Reference vs Platform and they differ,
/// the Platform (audited library) is almost certainly correct.
/// This process discovers bugs in the Reference implementation.
public protocol ECOperationsProvider {
    
    /// Add two EC points: result = p1 + p2
    /// - Parameters:
    ///   - p1: First point as raw 64 bytes (X || Y)
    ///   - p2: Second point as raw 64 bytes (X || Y)
    /// - Returns: Sum point as raw 64 bytes, or nil on error
    static func addPoints(_ p1: Data, _ p2: Data) -> Data?
    
    /// Multiply point by scalar: result = point * scalar
    /// - Parameters:
    ///   - point: EC point as raw 64 bytes (X || Y)
    ///   - scalar: 32-byte scalar value
    /// - Returns: Result point as raw 64 bytes, or nil on error
    static func scalarMultiply(point: Data, scalar: Data) -> Data?
    
    /// Multiply generator by scalar: result = G * scalar
    /// - Parameter scalar: 32-byte scalar value
    /// - Returns: Result point as raw 64 bytes, or nil on error
    static func scalarBaseMultiply(scalar: Data) -> Data?
    
    /// Negate a point: result = -P (same X, negated Y)
    /// - Parameter point: EC point as raw 64 bytes (X || Y)
    /// - Returns: Negated point as raw 64 bytes, or nil on error
    static func negatePoint(_ point: Data) -> Data?
    
    /// Parse raw 64-byte point and validate it's on curve
    /// - Parameter data: 64 bytes (X || Y)
    /// - Returns: true if point is valid and on P-256 curve
    static func isValidPoint(_ data: Data) -> Bool
}

// MARK: - Default Implementations

public extension ECOperationsProvider {
    
    /// Subtract two points: result = p1 - p2 = p1 + (-p2)
    static func subtractPoints(_ p1: Data, _ p2: Data) -> Data? {
        guard let negP2 = negatePoint(p2) else { return nil }
        return addPoints(p1, negP2)
    }
}

// MARK: - Validation Result

/// Result of comparing two EC implementations
public struct ECValidationResult: Sendable {
    public let operation: String
    public let referenceResult: Data?
    public let platformResult: Data?
    public let match: Bool
    
    public init(operation: String, reference: Data?, platform: Data?) {
        self.operation = operation
        self.referenceResult = reference
        self.platformResult = platform
        self.match = reference == platform
    }
}

// MARK: - Cross-Validator

/// Utility to compare Reference vs Platform EC implementations
public enum ECCrossValidator {
    
    /// Compare addPoints operation
    public static func validateAddPoints<R: ECOperationsProvider, P: ECOperationsProvider>(
        reference: R.Type,
        platform: P.Type,
        p1: Data,
        p2: Data
    ) -> ECValidationResult {
        let refResult = reference.addPoints(p1, p2)
        let platResult = platform.addPoints(p1, p2)
        return ECValidationResult(operation: "addPoints", reference: refResult, platform: platResult)
    }
    
    /// Compare scalarMultiply operation
    public static func validateScalarMultiply<R: ECOperationsProvider, P: ECOperationsProvider>(
        reference: R.Type,
        platform: P.Type,
        point: Data,
        scalar: Data
    ) -> ECValidationResult {
        let refResult = reference.scalarMultiply(point: point, scalar: scalar)
        let platResult = platform.scalarMultiply(point: point, scalar: scalar)
        return ECValidationResult(operation: "scalarMultiply", reference: refResult, platform: platResult)
    }
    
    /// Compare scalarBaseMultiply operation
    public static func validateScalarBaseMultiply<R: ECOperationsProvider, P: ECOperationsProvider>(
        reference: R.Type,
        platform: P.Type,
        scalar: Data
    ) -> ECValidationResult {
        let refResult = reference.scalarBaseMultiply(scalar: scalar)
        let platResult = platform.scalarBaseMultiply(scalar: scalar)
        return ECValidationResult(operation: "scalarBaseMultiply", reference: refResult, platform: platResult)
    }
}
