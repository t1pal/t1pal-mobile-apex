// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7FieldArithmetic.swift
// CGMKit - DexcomG7
//
// P-256 field arithmetic for elliptic curve operations.
// Extracted from G7ECOperations.swift (CODE-020)
//
// Trace: JPAKE-EC-001

import Foundation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif
// MARK: - Field Arithmetic for P-256

/// Modular arithmetic operations over P-256 field
/// **Note:** Only decompressPoint and decompressToPublicKey are used.
/// The BigInt functions (add, subtract, multiply, etc.) support point decompression.
/// EC point arithmetic uses AuditedECOperations (OpenSSL) instead.
public enum FieldArithmetic {
    
    /// Add two field elements: (a + b) mod p
    public static func add(_ a: [UInt8], _ b: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 33)
        var carry: UInt16 = 0
        
        for i in (0..<32).reversed() {
            let sum = UInt16(a[i]) + UInt16(b[i]) + carry
            result[i + 1] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
        result[0] = UInt8(carry)
        
        // Reduce mod p if needed
        return modReduce(Array(result), modulus: p)
    }
    
    /// Subtract two field elements: (a - b) mod p
    public static func subtract(_ a: [UInt8], _ b: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        // If a >= b, simple subtraction
        if compare(a, b) >= 0 {
            return subtractUnsigned(a, b)
        }
        
        // a < b: compute p - (b - a)
        let diff = subtractUnsigned(b, a)
        return subtractUnsigned(p, diff)
    }
    
    /// Multiply two field elements: (a * b) mod p
    public static func multiply(_ a: [UInt8], _ b: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        // Schoolbook multiplication to get 64-byte product
        var product = [UInt32](repeating: 0, count: 64)
        
        for i in (0..<32).reversed() {
            for j in (0..<32).reversed() {
                let prod = UInt32(a[i]) * UInt32(b[j])
                let pos = i + j + 1
                product[pos] += prod
            }
        }
        
        // Carry propagation
        for i in (1..<64).reversed() {
            product[i - 1] += product[i] >> 8
            product[i] &= 0xFF
        }
        
        // Convert to bytes
        let productBytes = product.map { UInt8($0 & 0xFF) }
        
        // Reduce mod p
        return modReduceWide(productBytes, modulus: p)
    }
    
    /// Compute modular inverse: a^(-1) mod p using Binary Extended GCD
    /// This is significantly faster than Fermat's little theorem for large primes
    public static func modInverse(_ a: [UInt8], modulus p: [UInt8]) -> [UInt8]? {
        // Binary Extended GCD algorithm
        // Returns x such that a*x ≡ 1 (mod p)
        
        // Check for zero
        if a.allSatisfy({ $0 == 0 }) { return nil }
        
        // Use Extended Euclidean Algorithm with binary optimization
        var u = a
        var v = p
        var x1: [UInt8] = [UInt8](repeating: 0, count: 31) + [1]  // 1
        var x2: [UInt8] = [UInt8](repeating: 0, count: 32)        // 0
        
        // Pad to 32 bytes
        while u.count < 32 { u.insert(0, at: 0) }
        while v.count < 32 { v.insert(0, at: 0) }
        
        var iterations = 0
        let maxIterations = 512  // Enough for 256-bit values
        
        while !isOne(u) && !isOne(v) && iterations < maxIterations {
            iterations += 1
            
            // While u is even
            while isEven(u) {
                u = shiftRight(u)
                if isEven(x1) {
                    x1 = shiftRight(x1)
                } else {
                    x1 = shiftRight(addBigEndian(x1, p))
                }
            }
            
            // While v is even
            while isEven(v) {
                v = shiftRight(v)
                if isEven(x2) {
                    x2 = shiftRight(x2)
                } else {
                    x2 = shiftRight(addBigEndian(x2, p))
                }
            }
            
            // Compare u and v
            if compare(u, v) >= 0 {
                u = subtractUnsigned(u, v)
                x1 = subtractMod(x1, x2, modulus: p)
            } else {
                v = subtractUnsigned(v, u)
                x2 = subtractMod(x2, x1, modulus: p)
            }
        }
        
        if isOne(u) {
            return modReduce(x1, modulus: p)
        } else {
            return modReduce(x2, modulus: p)
        }
    }
    
    /// Check if value is 1
    private static func isOne(_ a: [UInt8]) -> Bool {
        guard let last = a.last, last == 1 else { return false }
        for i in 0..<(a.count - 1) {
            if a[i] != 0 { return false }
        }
        return true
    }
    
    /// Check if value is even (LSB = 0)
    private static func isEven(_ a: [UInt8]) -> Bool {
        guard let last = a.last else { return true }
        return (last & 1) == 0
    }
    
    /// Right shift by 1 bit (divide by 2)
    private static func shiftRight(_ a: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: a.count)
        var carry: UInt8 = 0
        
        for i in 0..<a.count {
            let newCarry = (a[i] & 1) << 7
            result[i] = (a[i] >> 1) | carry
            carry = newCarry
        }
        
        return result
    }
    
    /// Add two big-endian values (for inverse computation)
    private static func addBigEndian(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        var result = [UInt8](repeating: 0, count: maxLen + 1)
        var carry: UInt16 = 0
        
        for i in 0..<maxLen {
            let aIdx = a.count - 1 - i
            let bIdx = b.count - 1 - i
            let rIdx = maxLen - i
            
            let aVal: UInt16 = aIdx >= 0 ? UInt16(a[aIdx]) : 0
            let bVal: UInt16 = bIdx >= 0 ? UInt16(b[bIdx]) : 0
            
            let sum = aVal + bVal + carry
            result[rIdx] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
        result[0] = UInt8(carry)
        
        // Remove leading zeros but keep at least 32 bytes
        while result.count > 32 && result[0] == 0 {
            result.removeFirst()
        }
        while result.count < 32 {
            result.insert(0, at: 0)
        }
        
        return result
    }
    
    /// Modular subtraction for inverse computation
    private static func subtractMod(_ a: [UInt8], _ b: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        if compare(a, b) >= 0 {
            return subtractUnsigned(a, b)
        } else {
            // a < b: return (a + p) - b = a - b + p
            let aPlusP = addBigEndian(a, p)
            return subtractUnsigned(Array(aPlusP.suffix(32)), b)
        }
    }
    
    /// Modular exponentiation: a^e mod p using square-and-multiply (MSB first)
    /// Uses right-to-left binary method: process bits from MSB to LSB
    public static func modExp(_ base: [UInt8], _ exp: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [UInt8](repeating: 0, count: 31) + [1]  // 1
        var current = base
        
        // Pad base to 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        
        // Process exponent bits from MSB to LSB (left-to-right binary method)
        var started = false
        for byteIdx in 0..<32 {
            for bitIdx in (0..<8).reversed() {
                let bit = (exp[byteIdx] >> bitIdx) & 1
                
                if started {
                    // Square result
                    result = multiply(result, result, modulus: p)
                }
                
                if bit == 1 {
                    started = true
                    // Multiply result by base
                    result = multiply(result, current, modulus: p)
                }
            }
        }
        
        // If exponent was 0, result should be 1
        if !started {
            return [UInt8](repeating: 0, count: 31) + [1]
        }
        
        return result
    }
    
    // MARK: - Compressed Point Y Recovery (G7-RESEARCH-006)
    
    /// Decompress a SEC1 compressed EC point to full X||Y format
    /// Uses CryptoKit on Apple platforms, software implementation on Linux
    /// Compressed format: 0x02/0x03 || X (33 bytes)
    /// - Parameter compressed: 33-byte compressed point
    /// - Returns: 64-byte uncompressed point (X || Y), or nil on error
    public static func decompressPoint(_ compressed: Data) -> Data? {
        guard compressed.count == 33 else { return nil }
        
        let prefix = compressed[0]
        guard prefix == 0x02 || prefix == 0x03 else { return nil }
        
        // Use CryptoKit/swift-crypto built-in decompression
        if let publicKey = ECPointOperations.parseCompressedPoint(compressed) {
            return publicKey.rawRepresentation
        }
        
        // Fallback to software implementation
        return decompressPointSoftware(compressed)
    }
    
    /// Software implementation of point decompression (for when CryptoKit fails)
    /// - Parameter compressed: 33-byte compressed point
    /// - Returns: 64-byte uncompressed point (X || Y), or nil on error
    private static func decompressPointSoftware(_ compressed: Data) -> Data? {
        guard compressed.count == 33 else { return nil }
        
        let prefix = compressed[0]
        guard prefix == 0x02 || prefix == 0x03 else { return nil }
        
        let x = Array(compressed[1..<33])
        let p = ECPointOperations.fieldPrime
        let a = ECPointOperations.curveA
        let b = ECPointOperations.curveB
        
        // Compute y² = x³ + ax + b (mod p)
        let x2 = multiply(x, x, modulus: p)
        let x3 = multiply(x2, x, modulus: p)
        let ax = multiply(a, x, modulus: p)
        let x3_ax = add(x3, ax, modulus: p)
        let y2 = add(x3_ax, b, modulus: p)
        
        // Compute y = sqrt(y²) mod p using Tonelli-Shanks
        guard let y = sqrtModP(y2) else {
            return nil  // Point not on curve
        }
        
        // Select correct y based on prefix (parity of y)
        let yIsOdd = (y.last ?? 0) & 1
        let wantOdd = (prefix == 0x03)
        
        var finalY = y
        if (yIsOdd == 1) != wantOdd {
            finalY = subtract(p, y, modulus: p)
        }
        
        while finalY.count < 32 {
            finalY.insert(0, at: 0)
        }
        
        return Data(x) + Data(finalY)
    }
    
    /// Decompress and create P256 public key from compressed representation
    /// - Parameter compressed: 33-byte SEC1 compressed point
    /// - Returns: P256 public key, or nil on error
    public static func decompressToPublicKey(_ compressed: Data) -> P256.Signing.PublicKey? {
        // Try CryptoKit first
        if let key = ECPointOperations.parseCompressedPoint(compressed) {
            return key
        }
        
        // Fallback to software decompression + key creation
        guard let uncompressed = decompressPointSoftware(compressed) else { return nil }
        return ECPointOperations.parseUncompressedPoint(Data([0x04]) + uncompressed)
    }
    
    /// Compute modular square root for P-256 field
    /// For P-256, p ≡ 3 (mod 4), so sqrt(a) = a^((p+1)/4) mod p
    /// - Parameter value: Field element to compute square root of (32 bytes)
    /// - Returns: Square root if it exists, nil otherwise
    public static func sqrtModP(_ value: [UInt8]) -> [UInt8]? {
        let p = ECPointOperations.fieldPrime
        
        // Pad value to 32 bytes if needed
        var paddedValue = value
        while paddedValue.count < 32 {
            paddedValue.insert(0, at: 0)
        }
        
        // Compute exponent (p + 1) / 4
        // p = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
        // (p + 1) / 4 = 0x3FFFFFFFC0000000400000000000000000000000400000000000000000000000
        let sqrtExp: [UInt8] = [
            0x3F, 0xFF, 0xFF, 0xFF, 0xC0, 0x00, 0x00, 0x00,
            0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        
        // Compute candidate root: value^((p+1)/4) mod p
        let candidate = modExpOptimized(paddedValue, sqrtExp, modulus: p)
        
        // Verify: candidate² should equal value (mod p)
        let squared = multiply(candidate, candidate, modulus: p)
        
        // Compare squared result with original value
        if compare(squared, paddedValue) == 0 {
            return candidate
        }
        
        return nil  // No square root exists (value is not a quadratic residue)
    }
    
    /// Optimized modular exponentiation for large exponents
    /// Uses standard square-and-multiply with fixed window
    private static func modExpOptimized(_ base: [UInt8], _ exp: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [UInt8](repeating: 0, count: 31) + [1]  // 1
        var base32 = base
        while base32.count < 32 { base32.insert(0, at: 0) }
        
        // Process bits from MSB to LSB
        var started = false
        for byteIdx in 0..<32 {
            let byte = exp[byteIdx]
            for bitIdx in (0..<8).reversed() {
                if started {
                    result = multiply(result, result, modulus: p)
                }
                
                let bit = (byte >> bitIdx) & 1
                if bit == 1 {
                    if started {
                        result = multiply(result, base32, modulus: p)
                    } else {
                        result = base32
                        started = true
                    }
                }
            }
        }
        
        if !started {
            return [UInt8](repeating: 0, count: 31) + [1]
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    /// Compare two big-endian byte arrays
    /// Returns: -1 if a < b, 0 if a == b, 1 if a > b
    public static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let maxLen = max(a.count, b.count)
        let paddedA = [UInt8](repeating: 0, count: maxLen - a.count) + a
        let paddedB = [UInt8](repeating: 0, count: maxLen - b.count) + b
        
        for i in 0..<maxLen {
            if paddedA[i] < paddedB[i] { return -1 }
            if paddedA[i] > paddedB[i] { return 1 }
        }
        return 0
    }
    
    /// Unsigned subtraction (assumes a >= b)
    private static func subtractUnsigned(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32)
        var borrow: Int16 = 0
        
        let aLen = a.count
        let bLen = b.count
        
        for i in (0..<32).reversed() {
            let aIdx = aLen - (32 - i)
            let bIdx = bLen - (32 - i)
            
            let aVal: Int16 = aIdx >= 0 ? Int16(a[aIdx]) : 0
            let bVal: Int16 = bIdx >= 0 ? Int16(b[bIdx]) : 0
            
            var diff = aVal - bVal - borrow
            if diff < 0 {
                diff += 256
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = UInt8(diff)
        }
        
        return result
    }
    
    /// Reduce a value mod p (for values up to 33 bytes)
    private static func modReduce(_ value: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        var current = value
        
        // Remove leading zeros
        while current.count > 32 && current[0] == 0 {
            current.removeFirst()
        }
        
        // Pad to 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        
        // Subtract p while current >= p
        while current.count >= 32 && compare(Array(current.suffix(32)), p) >= 0 {
            current = Array(subtractUnsigned(Array(current.suffix(32)), p))
        }
        
        // Ensure 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        
        return Array(current.prefix(32))
    }
    
    /// Reduce a wide value (up to 64 bytes) mod p
    private static func modReduceWide(_ value: [UInt8], modulus p: [UInt8]) -> [UInt8] {
        var current = Array(value)
        
        // Remove leading zeros
        while current.count > 32 && current[0] == 0 {
            current.removeFirst()
        }
        
        // Use repeated subtraction with shift for reduction
        var iterations = 0
        let maxIterations = 2000
        
        while current.count > 32 && iterations < maxIterations {
            iterations += 1
            
            // Remove leading zeros
            while current.count > 32 && current[0] == 0 {
                current.removeFirst()
            }
            
            if current.count <= 32 { break }
            
            // Shift p left and subtract
            let shift = current.count - 32
            let shifted = [UInt8](repeating: 0, count: shift) + p
            
            if compare(current, shifted) >= 0 {
                current = subtractWide(current, shifted)
            } else if shift > 0 {
                let smallerShift = [UInt8](repeating: 0, count: shift - 1) + p
                if compare(current, smallerShift) >= 0 {
                    current = subtractWide(current, smallerShift)
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        // Final reduction
        while current.count == 32 && compare(current, p) >= 0 {
            current = subtractUnsigned(current, p)
        }
        
        // Ensure exactly 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        while current.count > 32 {
            current.removeFirst()
        }
        
        return current
    }
    
    /// Wide subtraction for reduction
    private static func subtractWide(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        var result = [UInt8](repeating: 0, count: maxLen)
        var borrow: Int16 = 0
        
        for i in (0..<maxLen).reversed() {
            let aIdx = a.count - (maxLen - i)
            let bIdx = b.count - (maxLen - i)
            
            let aVal: Int16 = aIdx >= 0 ? Int16(a[aIdx]) : 0
            let bVal: Int16 = bIdx >= 0 ? Int16(b[bIdx]) : 0
            
            var diff = aVal - bVal - borrow
            if diff < 0 {
                diff += 256
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = UInt8(diff)
        }
        
        return result
    }
}

