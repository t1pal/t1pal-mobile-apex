//
//  OpenSSLECOperations.swift
//  CryptoValidation
//
//  EC operations using OpenSSL (audited backend)
//  - Apple: krzyzanowskim/OpenSSL-Package (XCFramework)
//  - Linux: System OpenSSL via CLinuxOpenSSL module (EC-LIB-017)
//  Part of EC-LIB-016/017 evaluation
//

import Foundation

#if canImport(Darwin)
import OpenSSL
#elseif os(Linux)
import CLinuxOpenSSL
import Glibc
#endif

/// EC operations using OpenSSL's audited EC_POINT_* functions
/// Provides P-256 point arithmetic needed for G7 J-PAKE authentication
public struct OpenSSLECOperations {
    
    #if canImport(Darwin) || os(Linux)
    /// P-256 curve NID
    private static let curveNID: Int32 = NID_X9_62_prime256v1
    
    /// Verify OpenSSL is working by computing 2G
    public static func verify() throws -> Bool {
        // Create EC group for P-256
        guard let group = EC_GROUP_new_by_curve_name(curveNID) else {
            throw OpenSSLError.failedToCreateGroup
        }
        defer { EC_GROUP_free(group) }
        
        // Get generator point G
        guard let generator = EC_GROUP_get0_generator(group) else {
            throw OpenSSLError.failedToGetGenerator
        }
        
        // Create BN_CTX for temporary variables
        guard let ctx = BN_CTX_new() else {
            throw OpenSSLError.failedToCreateContext
        }
        defer { BN_CTX_free(ctx) }
        
        // Create scalar = 2
        guard let scalar = BN_new() else {
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(scalar) }
        BN_set_word(scalar, 2)
        
        // Create result point
        guard let result = EC_POINT_new(group) else {
            throw OpenSSLError.failedToCreatePoint
        }
        defer { EC_POINT_free(result) }
        
        // Compute 2G = G * 2
        guard EC_POINT_mul(group, result, nil, generator, scalar, ctx) == 1 else {
            throw OpenSSLError.multiplyFailed
        }
        
        // Get X coordinate
        guard let x = BN_new(), let y = BN_new() else {
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(x); BN_free(y) }
        
        guard EC_POINT_get_affine_coordinates(group, result, x, y, ctx) == 1 else {
            throw OpenSSLError.failedToGetCoordinates
        }
        
        // Convert X to hex and verify against known 2G.x value
        guard let xHex = BN_bn2hex(x) else {
            throw OpenSSLError.failedToConvert
        }
        // OPENSSL_free is a macro expanding to CRYPTO_free
        defer { CRYPTO_free(xHex, #file, #line) }
        
        let xHexString = String(cString: xHex)
        
        // Known 2G.x for P-256 (NIST test vector)
        // 2G.x = 7CF27B188D034F7E8A52380304B51AC3C08969E277F21B35A60B48FC47669978
        let expected2Gx = "7CF27B188D034F7E8A52380304B51AC3C08969E277F21B35A60B48FC47669978"
        
        return xHexString.uppercased() == expected2Gx
    }
    
    /// Add two EC points: R = P + Q
    public static func addPoints(_ p: ECPoint, _ q: ECPoint) throws -> ECPoint {
        guard let group = EC_GROUP_new_by_curve_name(curveNID) else {
            throw OpenSSLError.failedToCreateGroup
        }
        defer { EC_GROUP_free(group) }
        
        guard let ctx = BN_CTX_new() else {
            throw OpenSSLError.failedToCreateContext
        }
        defer { BN_CTX_free(ctx) }
        
        // Convert input points to EC_POINT
        let pPoint = try createPoint(from: p, group: group, ctx: ctx)
        defer { EC_POINT_free(pPoint) }
        
        let qPoint = try createPoint(from: q, group: group, ctx: ctx)
        defer { EC_POINT_free(qPoint) }
        
        // Create result point
        guard let result = EC_POINT_new(group) else {
            throw OpenSSLError.failedToCreatePoint
        }
        defer { EC_POINT_free(result) }
        
        // Add: result = p + q
        guard EC_POINT_add(group, result, pPoint, qPoint, ctx) == 1 else {
            throw OpenSSLError.addFailed
        }
        
        return try extractPoint(from: result, group: group, ctx: ctx)
    }
    
    /// Multiply EC point by scalar: R = P * k
    public static func multiplyPoint(_ p: ECPoint, by scalar: Data) throws -> ECPoint {
        guard let group = EC_GROUP_new_by_curve_name(curveNID) else {
            throw OpenSSLError.failedToCreateGroup
        }
        defer { EC_GROUP_free(group) }
        
        guard let ctx = BN_CTX_new() else {
            throw OpenSSLError.failedToCreateContext
        }
        defer { BN_CTX_free(ctx) }
        
        // Convert input point
        let pPoint = try createPoint(from: p, group: group, ctx: ctx)
        defer { EC_POINT_free(pPoint) }
        
        // Convert scalar to BIGNUM
        guard let k = BN_new() else {
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(k) }
        
        scalar.withUnsafeBytes { bytes in
            _ = BN_bin2bn(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(bytes.count), k)
        }
        
        // Create result
        guard let result = EC_POINT_new(group) else {
            throw OpenSSLError.failedToCreatePoint
        }
        defer { EC_POINT_free(result) }
        
        // Multiply: result = p * k
        guard EC_POINT_mul(group, result, nil, pPoint, k, ctx) == 1 else {
            throw OpenSSLError.multiplyFailed
        }
        
        return try extractPoint(from: result, group: group, ctx: ctx)
    }
    
    /// Multiply generator by scalar: R = G * k (base point multiplication)
    public static func multiplyGenerator(by scalar: Data) throws -> ECPoint {
        guard let group = EC_GROUP_new_by_curve_name(curveNID) else {
            throw OpenSSLError.failedToCreateGroup
        }
        defer { EC_GROUP_free(group) }
        
        guard let ctx = BN_CTX_new() else {
            throw OpenSSLError.failedToCreateContext
        }
        defer { BN_CTX_free(ctx) }
        
        // Convert scalar to BIGNUM
        guard let k = BN_new() else {
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(k) }
        
        scalar.withUnsafeBytes { bytes in
            _ = BN_bin2bn(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(bytes.count), k)
        }
        
        // Create result
        guard let result = EC_POINT_new(group) else {
            throw OpenSSLError.failedToCreatePoint
        }
        defer { EC_POINT_free(result) }
        
        // Multiply generator: result = G * k (first arg is scalar for generator)
        guard EC_POINT_mul(group, result, k, nil, nil, ctx) == 1 else {
            throw OpenSSLError.multiplyFailed
        }
        
        return try extractPoint(from: result, group: group, ctx: ctx)
    }
    
    // MARK: - Private Helpers
    
    private static func createPoint(from point: ECPoint, group: OpaquePointer, ctx: OpaquePointer) throws -> OpaquePointer {
        guard let ecPoint = EC_POINT_new(group) else {
            throw OpenSSLError.failedToCreatePoint
        }
        
        guard let x = BN_new(), let y = BN_new() else {
            EC_POINT_free(ecPoint)
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(x); BN_free(y) }
        
        point.x.withUnsafeBytes { bytes in
            _ = BN_bin2bn(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(bytes.count), x)
        }
        point.y.withUnsafeBytes { bytes in
            _ = BN_bin2bn(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(bytes.count), y)
        }
        
        guard EC_POINT_set_affine_coordinates(group, ecPoint, x, y, ctx) == 1 else {
            EC_POINT_free(ecPoint)
            throw OpenSSLError.failedToSetCoordinates
        }
        
        return ecPoint
    }
    
    private static func extractPoint(from ecPoint: OpaquePointer, group: OpaquePointer, ctx: OpaquePointer) throws -> ECPoint {
        guard let x = BN_new(), let y = BN_new() else {
            throw OpenSSLError.failedToCreateBigNum
        }
        defer { BN_free(x); BN_free(y) }
        
        guard EC_POINT_get_affine_coordinates(group, ecPoint, x, y, ctx) == 1 else {
            throw OpenSSLError.failedToGetCoordinates
        }
        
        // Convert to Data (32 bytes for P-256)
        var xData = Data(count: 32)
        var yData = Data(count: 32)
        
        // BN_num_bytes is a macro: ((BN_num_bits(a)+7)/8)
        // Swift can't use C macros, so we inline the calculation
        let xLen = Int((BN_num_bits(x) + 7) / 8)
        let yLen = Int((BN_num_bits(y) + 7) / 8)
        
        xData.withUnsafeMutableBytes { bytes in
            // Pad with leading zeros
            let offset = 32 - xLen
            _ = BN_bn2bin(x, bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self))
        }
        yData.withUnsafeMutableBytes { bytes in
            let offset = 32 - yLen
            _ = BN_bn2bin(y, bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self))
        }
        
        return ECPoint(x: xData, y: yData)
    }
    
    #else
    // Unsupported platform stub
    public static func verify() throws -> Bool {
        throw OpenSSLError.platformNotSupported
    }
    
    public static func addPoints(_ p: ECPoint, _ q: ECPoint) throws -> ECPoint {
        throw OpenSSLError.platformNotSupported
    }
    
    public static func multiplyPoint(_ p: ECPoint, by scalar: Data) throws -> ECPoint {
        throw OpenSSLError.platformNotSupported
    }
    
    public static func multiplyGenerator(by scalar: Data) throws -> ECPoint {
        throw OpenSSLError.platformNotSupported
    }
    #endif
}

/// Simple EC point representation (uncompressed coordinates)
public struct ECPoint: Equatable {
    public let x: Data
    public let y: Data
    
    public init(x: Data, y: Data) {
        self.x = x
        self.y = y
    }
    
    /// Create from raw 64-byte format (X || Y)
    public init?(raw: Data) {
        guard raw.count == 64 else { return nil }
        self.x = raw.prefix(32)
        self.y = raw.suffix(32)
    }
    
    /// Convert to raw 64-byte format (X || Y)
    public var raw: Data {
        return x + y
    }
}

/// OpenSSL operation errors
public enum OpenSSLError: Error {
    case failedToCreateGroup
    case failedToGetGenerator
    case failedToCreateContext
    case failedToCreateBigNum
    case failedToCreatePoint
    case failedToSetCoordinates
    case failedToGetCoordinates
    case failedToConvert
    case multiplyFailed
    case addFailed
    case platformNotSupported
}

// MARK: - AuditedECOperations (EC-LIB-018)

/// Audited EC operations conforming to ECOperationsProvider protocol.
///
/// This adapter wraps OpenSSLECOperations to provide the same interface
/// as the hand-rolled ECPointOperations, but using audited OpenSSL backend.
///
/// **Migration Path (EC-LIB-018):**
/// Replace `ReferenceECOperations` (hand-rolled, 5 bugs) with `AuditedECOperations`
/// in production code for correct EC point arithmetic.
///
/// Trace: EC-LIB-018, PRD-008 REQ-BLE-008
public enum AuditedECOperations: ECOperationsProvider {
    
    // MARK: - P-256 Constants
    
    /// P-256 field prime (for point negation)
    private static let fieldPrime: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    ]
    
    // MARK: - ECOperationsProvider Conformance
    
    /// Add two EC points: result = p1 + p2
    public static func addPoints(_ p1: Data, _ p2: Data) -> Data? {
        guard let point1 = ECPoint(raw: p1),
              let point2 = ECPoint(raw: p2) else {
            return nil
        }
        
        do {
            let result = try OpenSSLECOperations.addPoints(point1, point2)
            return result.raw
        } catch {
            return nil
        }
    }
    
    /// Multiply point by scalar: result = point * scalar
    public static func scalarMultiply(point: Data, scalar: Data) -> Data? {
        guard let ecPoint = ECPoint(raw: point) else {
            return nil
        }
        
        do {
            let result = try OpenSSLECOperations.multiplyPoint(ecPoint, by: scalar)
            return result.raw
        } catch {
            return nil
        }
    }
    
    /// Multiply generator by scalar: result = G * scalar
    public static func scalarBaseMultiply(scalar: Data) -> Data? {
        do {
            let result = try OpenSSLECOperations.multiplyGenerator(by: scalar)
            return result.raw
        } catch {
            return nil
        }
    }
    
    /// Negate a point: result = -P (same X, negated Y mod p)
    public static func negatePoint(_ point: Data) -> Data? {
        guard point.count == 64 else { return nil }
        
        let x = point.prefix(32)
        let y = point.suffix(32)
        
        // Negate Y: -Y = p - Y (mod p)
        let p = Data(fieldPrime)
        guard let negY = subtractModP(p, Data(y)) else { return nil }
        
        return x + negY
    }
    
    /// Check if point is valid and on P-256 curve
    public static func isValidPoint(_ data: Data) -> Bool {
        guard data.count == 64 else { return false }
        
        // Use PlatformECOperations for validation (CryptoKit can parse valid points)
        return PlatformECOperations.isValidPoint(data)
    }
    
    // MARK: - Private Helpers
    
    /// Subtract two 256-bit numbers: result = a - b mod p
    private static func subtractModP(_ a: Data, _ b: Data) -> Data? {
        guard a.count == 32, b.count == 32 else { return nil }
        
        // Convert to arrays for arithmetic
        var result = [UInt8](repeating: 0, count: 32)
        var borrow: Int = 0
        
        // Subtract byte-by-byte from least significant
        for i in (0..<32).reversed() {
            let diff = Int(a[i]) - Int(b[i]) - borrow
            if diff < 0 {
                result[i] = UInt8((diff + 256) & 0xFF)
                borrow = 1
            } else {
                result[i] = UInt8(diff & 0xFF)
                borrow = 0
            }
        }
        
        // If borrow remains, result would be negative - add p back
        // (but for our use case in negation, a is always p and b < p, so no borrow)
        
        return Data(result)
    }
}
