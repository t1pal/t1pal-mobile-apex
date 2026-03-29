// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6Authenticator.swift
// CGMKit - DexcomG6
//
// Dexcom G6 AES-128-ECB authentication implementation.
// Trace: PRD-008 REQ-BLE-007

import Foundation

/// Dexcom G6 authentication handler
///
/// The G6 uses AES-128-ECB for authentication:
/// 1. Generate 8-byte random token
/// 2. Derive cryptKey from transmitter ID
/// 3. Send token to transmitter
/// 4. Receive challenge (encrypted token hash + 8-byte challenge)
/// 5. Verify token hash matches
/// 6. Encrypt challenge with cryptKey and send back
public struct G6Authenticator: Sendable {
    
    /// The transmitter ID
    public let transmitterId: TransmitterID
    
    /// Derived encryption key (16 bytes)
    public let cryptKey: Data
    
    /// Whether using App Level Key authentication
    /// Trace: CGM-065, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public let usingAppLevelKey: Bool
    
    /// Create authenticator for a transmitter using TX ID-derived key
    /// - Parameter transmitterId: The transmitter ID
    public init(transmitterId: TransmitterID) {
        self.transmitterId = transmitterId
        self.cryptKey = Self.deriveKey(from: transmitterId.id)
        self.usingAppLevelKey = false
    }
    
    /// Create authenticator using an App Level Key
    /// - Parameters:
    ///   - transmitterId: The transmitter ID
    ///   - appLevelKey: 16-byte App Level Key (stored from previous ChangeAppLevelKeyTx)
    /// Trace: CGM-065, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public init(transmitterId: TransmitterID, appLevelKey: Data) {
        precondition(appLevelKey.count == 16, "App Level Key must be exactly 16 bytes")
        self.transmitterId = transmitterId
        self.cryptKey = appLevelKey
        self.usingAppLevelKey = true
    }
    
    // MARK: - Key Derivation
    
    /// Derive the 16-byte AES key from transmitter ID
    /// - Parameter id: 6-character transmitter ID
    /// - Returns: 16-byte key
    public static func deriveKey(from id: String) -> Data {
        // CGMBLEKit format: "00" + id + "00" + id as UTF-8 string
        // "00" is the characters '0' '0', NOT null bytes
        // For 6-char ID, this produces exactly 16 bytes
        let keyString = "00\(id)00\(id)"
        return keyString.data(using: .utf8) ?? Data(count: 16)
    }
    
    // MARK: - Token Generation
    
    /// Generate a random 8-byte authentication token
    /// - Returns: 8-byte random token
    public static func generateToken() -> Data {
        var token = Data(count: 8)
        for i in 0..<8 {
            token[i] = UInt8.random(in: 0...255)
        }
        return token
    }
    
    // MARK: - Authentication Flow
    
    /// Create the initial auth request message
    /// - Parameter slot: Connection slot for authentication (CGM-046)
    /// - Returns: Auth request with random token (uses generation-aware opcode)
    /// Note: For App Level Key auth, always uses opcode 0x02 regardless of generation
    /// Trace: CGM-046a, CGM-046b - Wire slot selection into auth flow
    public func createAuthRequest(slot: G6Slot = .consumer) -> (message: AuthRequestTxMessage, token: Data) {
        let token = Self.generateToken()
        let message: AuthRequestTxMessage
        
        if usingAppLevelKey {
            // App Level Key auth always uses opcode 0x02 (authRequest2Tx)
            // Trace: CGM-065, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
            message = AuthRequestTxMessage(singleUseToken: token, generation: .g6Plus, slot: slot)
        } else {
            // Standard TX ID auth uses generation-aware opcode
            message = AuthRequestTxMessage(singleUseToken: token, generation: transmitterId.generation, slot: slot)
        }
        
        return (message, token)
    }
    
    /// Process auth challenge response and create challenge reply
    /// - Parameters:
    ///   - challenge: The challenge response from transmitter
    ///   - sentToken: The token we sent in the auth request
    /// - Returns: Challenge reply message, or nil if verification failed
    public func processChallenge(_ challenge: AuthChallengeRxMessage, sentToken: Data) -> AuthChallengeTxMessage? {
        // Verify the token hash matches what we expect
        let expectedHash = hashToken(sentToken)
        
        guard challenge.tokenHash == expectedHash else {
            // Token hash mismatch - authentication failed
            return nil
        }
        
        // Encrypt the challenge and send it back
        let response = encryptChallenge(challenge.challenge)
        return AuthChallengeTxMessage(challengeResponse: response)
    }
    
    // MARK: - Crypto Operations
    
    /// Hash a token using AES-ECB encryption
    /// - Parameter token: 8-byte token to hash
    /// - Returns: 8-byte hash (first 8 bytes of encrypted result)
    public func hashToken(_ token: Data) -> Data {
        // CGMBLEKit format: Duplicate token to fill 16 bytes
        // token + token = 16 bytes (not token + zeros)
        var doubleData = Data(capacity: 16)
        doubleData.append(token.prefix(8))
        doubleData.append(token.prefix(8))
        
        // Encrypt with AES-ECB
        let encrypted = aesEncryptECB(data: doubleData, key: cryptKey)
        
        // Return first 8 bytes
        return encrypted.prefix(8)
    }
    
    /// Encrypt a challenge for response
    /// - Parameter challenge: 8-byte challenge from transmitter
    /// - Returns: 8-byte encrypted response
    public func encryptChallenge(_ challenge: Data) -> Data {
        // CGMBLEKit format: Duplicate challenge to fill 16 bytes
        var doubleData = Data(capacity: 16)
        doubleData.append(challenge.prefix(8))
        doubleData.append(challenge.prefix(8))
        
        // Encrypt with AES-ECB
        let encrypted = aesEncryptECB(data: doubleData, key: cryptKey)
        
        // Return first 8 bytes
        return encrypted.prefix(8)
    }
    
    // MARK: - AES-ECB Implementation
    
    /// AES-128-ECB encryption (single block)
    /// - Parameters:
    ///   - data: 16-byte data block
    ///   - key: 16-byte key
    /// - Returns: 16-byte encrypted block
    private func aesEncryptECB(data: Data, key: Data) -> Data {
        #if canImport(CommonCrypto)
        return aesEncryptCommonCrypto(data: data, key: key)
        #else
        return aesEncryptPureSwift(data: data, key: key)
        #endif
    }
}

// MARK: - Platform-Specific AES

#if canImport(CommonCrypto)
import CommonCrypto

extension G6Authenticator {
    /// AES encryption using CommonCrypto (Darwin)
    fileprivate func aesEncryptCommonCrypto(data: Data, key: Data) -> Data {
        var outData = Data(count: data.count)
        let outDataCount = outData.count  // Capture count before mutable borrow
        var numBytesEncrypted: size_t = 0
        
        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, key.count,
                        nil,  // No IV for ECB
                        dataBytes.baseAddress, data.count,
                        outBytes.baseAddress, outDataCount,
                        &numBytesEncrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            return Data(count: 16)  // Return zeros on error
        }
        
        return outData
    }
}
#endif

// Pure Swift AES implementation for Linux
extension G6Authenticator {
    /// Pure Swift AES-128 encryption (for Linux compatibility)
    fileprivate func aesEncryptPureSwift(data: Data, key: Data) -> Data {
        // AES S-box
        let sbox: [UInt8] = [
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
        
        // Rcon for key expansion
        let rcon: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]
        
        // Key expansion
        var expandedKey = [UInt8](repeating: 0, count: 176)
        let keyBytes = [UInt8](key)
        for i in 0..<16 {
            expandedKey[i] = keyBytes[i]
        }
        
        var temp = [UInt8](repeating: 0, count: 4)
        for i in 4..<44 {
            for j in 0..<4 {
                temp[j] = expandedKey[(i - 1) * 4 + j]
            }
            if i % 4 == 0 {
                // RotWord
                let t = temp[0]
                temp[0] = temp[1]
                temp[1] = temp[2]
                temp[2] = temp[3]
                temp[3] = t
                // SubWord
                for j in 0..<4 {
                    temp[j] = sbox[Int(temp[j])]
                }
                temp[0] ^= rcon[i / 4 - 1]
            }
            for j in 0..<4 {
                expandedKey[i * 4 + j] = expandedKey[(i - 4) * 4 + j] ^ temp[j]
            }
        }
        
        // State
        var state = [[UInt8]](repeating: [UInt8](repeating: 0, count: 4), count: 4)
        let dataBytes = [UInt8](data)
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] = dataBytes[r + 4 * c]
            }
        }
        
        // Initial round key addition
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] ^= expandedKey[r + 4 * c]
            }
        }
        
        // Main rounds
        for round in 1..<10 {
            // SubBytes
            for r in 0..<4 {
                for c in 0..<4 {
                    state[r][c] = sbox[Int(state[r][c])]
                }
            }
            
            // ShiftRows
            var t = state[1][0]
            state[1][0] = state[1][1]
            state[1][1] = state[1][2]
            state[1][2] = state[1][3]
            state[1][3] = t
            
            t = state[2][0]
            state[2][0] = state[2][2]
            state[2][2] = t
            t = state[2][1]
            state[2][1] = state[2][3]
            state[2][3] = t
            
            t = state[3][3]
            state[3][3] = state[3][2]
            state[3][2] = state[3][1]
            state[3][1] = state[3][0]
            state[3][0] = t
            
            // MixColumns
            for c in 0..<4 {
                let s0 = state[0][c]
                let s1 = state[1][c]
                let s2 = state[2][c]
                let s3 = state[3][c]
                
                state[0][c] = gmul(2, s0) ^ gmul(3, s1) ^ s2 ^ s3
                state[1][c] = s0 ^ gmul(2, s1) ^ gmul(3, s2) ^ s3
                state[2][c] = s0 ^ s1 ^ gmul(2, s2) ^ gmul(3, s3)
                state[3][c] = gmul(3, s0) ^ s1 ^ s2 ^ gmul(2, s3)
            }
            
            // AddRoundKey
            for r in 0..<4 {
                for c in 0..<4 {
                    state[r][c] ^= expandedKey[round * 16 + r + 4 * c]
                }
            }
        }
        
        // Final round (no MixColumns)
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] = sbox[Int(state[r][c])]
            }
        }
        
        var t = state[1][0]
        state[1][0] = state[1][1]
        state[1][1] = state[1][2]
        state[1][2] = state[1][3]
        state[1][3] = t
        
        t = state[2][0]
        state[2][0] = state[2][2]
        state[2][2] = t
        t = state[2][1]
        state[2][1] = state[2][3]
        state[2][3] = t
        
        t = state[3][3]
        state[3][3] = state[3][2]
        state[3][2] = state[3][1]
        state[3][1] = state[3][0]
        state[3][0] = t
        
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] ^= expandedKey[160 + r + 4 * c]
            }
        }
        
        // Convert state back to bytes
        var output = Data(count: 16)
        for r in 0..<4 {
            for c in 0..<4 {
                output[r + 4 * c] = state[r][c]
            }
        }
        
        return output
    }
    
    /// Galois field multiplication
    private func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var p: UInt8 = 0
        var aa = a
        var bb = b
        for _ in 0..<8 {
            if bb & 1 != 0 {
                p ^= aa
            }
            let hiBit = aa & 0x80
            aa <<= 1
            if hiBit != 0 {
                aa ^= 0x1b
            }
            bb >>= 1
        }
        return p
    }
}
