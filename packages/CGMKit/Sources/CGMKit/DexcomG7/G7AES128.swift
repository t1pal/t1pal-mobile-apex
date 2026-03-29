// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7AES128.swift
// CGMKit - DexcomG7
//
// Software AES-128 implementation for J-PAKE.
// Extracted from G7ECOperations.swift (CODE-020)
//
// Trace: G7-RESEARCH-007

import Foundation

// MARK: - Software AES-128 Implementation (G7-RESEARCH-007)

/// Pure Swift AES-128 implementation for cross-platform support
/// Implements FIPS 197 specification for single-block ECB encryption
/// Note: ECB mode should only be used for confirmation hashes, not general encryption
public enum AES128Software {
    
    // MARK: - S-Box (Substitution Box)
    
    /// AES S-Box lookup table (FIPS 197 Table 4)
    private static let sBox: [UInt8] = [
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    ]
    
    /// Round constants for key expansion (FIPS 197)
    private static let rcon: [UInt8] = [
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
    ]
    
    // MARK: - Public Interface
    
    /// Encrypt a single 16-byte block using AES-128-ECB
    /// - Parameters:
    ///   - block: 16-byte plaintext block
    ///   - key: 16-byte encryption key
    /// - Returns: 16-byte ciphertext block
    public static func encrypt(block: Data, key: Data) -> Data? {
        guard block.count == 16, key.count == 16 else { return nil }
        
        // Expand key to 11 round keys (176 bytes)
        let expandedKey = expandKey(Array(key))
        
        // Copy plaintext to state array (column-major order)
        var state = Array(block)
        
        // Initial round: AddRoundKey
        addRoundKey(&state, roundKey: Array(expandedKey[0..<16]))
        
        // Main rounds 1-9
        for round in 1..<10 {
            subBytes(&state)
            shiftRows(&state)
            mixColumns(&state)
            addRoundKey(&state, roundKey: Array(expandedKey[round * 16..<(round + 1) * 16]))
        }
        
        // Final round (no MixColumns)
        subBytes(&state)
        shiftRows(&state)
        addRoundKey(&state, roundKey: Array(expandedKey[160..<176]))
        
        return Data(state)
    }
    
    // MARK: - Key Expansion
    
    /// Expand 16-byte key to 176-byte round keys
    private static func expandKey(_ key: [UInt8]) -> [UInt8] {
        var w = [UInt8](repeating: 0, count: 176)
        
        // Copy original key
        for i in 0..<16 {
            w[i] = key[i]
        }
        
        // Generate remaining round keys
        var i = 4
        while i < 44 {
            var temp = Array(w[(i - 1) * 4..<i * 4])
            
            if i % 4 == 0 {
                // RotWord + SubWord + Rcon
                temp = [sBox[Int(temp[1])], sBox[Int(temp[2])], sBox[Int(temp[3])], sBox[Int(temp[0])]]
                temp[0] ^= rcon[i / 4 - 1]
            }
            
            for j in 0..<4 {
                w[i * 4 + j] = w[(i - 4) * 4 + j] ^ temp[j]
            }
            i += 1
        }
        
        return w
    }
    
    // MARK: - AES Round Functions
    
    /// SubBytes: Apply S-Box substitution
    private static func subBytes(_ state: inout [UInt8]) {
        for i in 0..<16 {
            state[i] = sBox[Int(state[i])]
        }
    }
    
    /// ShiftRows: Cyclic shift rows
    private static func shiftRows(_ state: inout [UInt8]) {
        // Row 1: shift left by 1
        let t1 = state[1]
        state[1] = state[5]
        state[5] = state[9]
        state[9] = state[13]
        state[13] = t1
        
        // Row 2: shift left by 2
        var t = state[2]
        state[2] = state[10]
        state[10] = t
        t = state[6]
        state[6] = state[14]
        state[14] = t
        
        // Row 3: shift left by 3 (= right by 1)
        let t3 = state[15]
        state[15] = state[11]
        state[11] = state[7]
        state[7] = state[3]
        state[3] = t3
    }
    
    /// MixColumns: Mix column transformation
    private static func mixColumns(_ state: inout [UInt8]) {
        for col in 0..<4 {
            let i = col * 4
            let s0 = state[i]
            let s1 = state[i + 1]
            let s2 = state[i + 2]
            let s3 = state[i + 3]
            
            state[i] = gmul(0x02, s0) ^ gmul(0x03, s1) ^ s2 ^ s3
            state[i + 1] = s0 ^ gmul(0x02, s1) ^ gmul(0x03, s2) ^ s3
            state[i + 2] = s0 ^ s1 ^ gmul(0x02, s2) ^ gmul(0x03, s3)
            state[i + 3] = gmul(0x03, s0) ^ s1 ^ s2 ^ gmul(0x02, s3)
        }
    }
    
    /// AddRoundKey: XOR state with round key
    private static func addRoundKey(_ state: inout [UInt8], roundKey: [UInt8]) {
        for i in 0..<16 {
            state[i] ^= roundKey[i]
        }
    }
    
    /// Galois field multiplication in GF(2^8)
    private static func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var aa = a
        var bb = b
        
        for _ in 0..<8 {
            if bb & 1 != 0 {
                result ^= aa
            }
            let hiBit = aa & 0x80
            aa <<= 1
            if hiBit != 0 {
                aa ^= 0x1b  // AES irreducible polynomial
            }
            bb >>= 1
        }
        
        return result
    }
}

