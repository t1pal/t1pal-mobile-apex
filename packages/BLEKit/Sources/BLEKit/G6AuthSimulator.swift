// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6AuthSimulator.swift
// BLEKit
//
// Server-side Dexcom G6 AES-128-ECB authentication for transmitter simulation.
// Trace: PRD-007 REQ-SIM-003

import Foundation

// MARK: - Authentication State

/// State of the authentication handshake
public enum G6AuthState: String, Sendable, Codable {
    /// Waiting for client's initial auth request
    case awaitingAuthRequest
    
    /// Sent challenge, waiting for client's response
    case awaitingChallengeResponse
    
    /// Successfully authenticated
    case authenticated
    
    /// Authentication failed
    case failed
    
    /// Bonded (persistent authentication)
    case bonded
}

// MARK: - Authentication Result

/// Result of processing an authentication message
public enum G6AuthResult: Sendable {
    /// Send this response to the client
    case sendResponse(Data)
    
    /// Authentication succeeded
    case authenticated(bonded: Bool)
    
    /// Authentication failed
    case failed(reason: String)
    
    /// Invalid or unexpected message
    case invalidMessage(String)
}

// MARK: - G6 Auth Simulator

/// Server-side G6 authentication handler for transmitter simulation
///
/// Implements the Dexcom G6 authentication protocol from the transmitter's perspective:
/// 1. Receive AuthRequestTx (0x01) with client's token
/// 2. Hash the token, generate challenge, send AuthChallengeRx (0x05)
/// 3. Receive AuthChallengeTx (0x04) with client's challenge response
/// 4. Verify response, send AuthStatusRx (0x06)
///
/// ## Usage
/// ```swift
/// let simulator = G6AuthSimulator(transmitterId: "8G1234")
/// 
/// // When client sends data on Authentication characteristic:
/// let result = simulator.processMessage(clientData)
/// switch result {
/// case .sendResponse(let data):
///     // Send data back on Authentication characteristic
/// case .authenticated(let bonded):
///     // Client is now authenticated
/// case .failed(let reason):
///     // Authentication failed
/// }
/// ```
public final class G6AuthSimulator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Transmitter ID
    public let transmitterId: String
    
    /// Derived AES-128 encryption key
    public let cryptKey: Data
    
    /// Current authentication state
    public private(set) var state: G6AuthState = .awaitingAuthRequest
    
    /// Pending challenge sent to client (stored to verify response)
    private var pendingChallenge: Data?
    
    /// Whether the client is bonded (persistent auth)
    public private(set) var isBonded: Bool = false
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Create an authentication simulator for a transmitter
    /// - Parameter transmitterId: 6-character transmitter ID
    public init(transmitterId: String) {
        self.transmitterId = transmitterId.uppercased()
        self.cryptKey = G6AuthSimulator.deriveKey(from: self.transmitterId)
    }
    
    /// Create with a SimulatorTransmitterID
    public convenience init(transmitterId: SimulatorTransmitterID) {
        self.init(transmitterId: transmitterId.rawValue)
    }
    
    // MARK: - Key Derivation
    
    /// Derive the 16-byte AES key from transmitter ID
    ///
    /// Format: 0x00 0x00 + ID[0..5] + 0x00 0x00 + ID[0..5]
    public static func deriveKey(from id: String) -> Data {
        let idData = id.data(using: .utf8) ?? Data()
        
        var key = Data(count: 16)
        key[0] = 0x00
        key[1] = 0x00
        
        for (i, byte) in idData.prefix(6).enumerated() {
            key[2 + i] = byte
        }
        
        key[8] = 0x00
        key[9] = 0x00
        
        for (i, byte) in idData.prefix(6).enumerated() {
            key[10 + i] = byte
        }
        
        return key
    }
    
    // MARK: - Message Processing
    
    /// Process an incoming authentication message
    /// - Parameter data: Raw message data from client
    /// - Returns: Result indicating what action to take
    public func processMessage(_ data: Data) -> G6AuthResult {
        lock.lock()
        defer { lock.unlock() }
        
        guard !data.isEmpty else {
            return .invalidMessage("Empty message")
        }
        
        let opcode = data[0]
        
        switch opcode {
        case G6SimOpcode.authRequestTx:
            return handleAuthRequest(data)
            
        case G6SimOpcode.authChallengeTx:
            return handleChallengeResponse(data)
            
        case G6SimOpcode.bondRequest:
            return handleBondRequest(data)
            
        case G6SimOpcode.keepAlive:
            return handleKeepAlive(data)
            
        default:
            return .invalidMessage("Unknown opcode: \(String(format: "0x%02X", opcode))")
        }
    }
    
    // MARK: - Auth Request (Step 1)
    
    /// Handle AuthRequestTx (0x01) from client
    private func handleAuthRequest(_ data: Data) -> G6AuthResult {
        // Format: opcode (1) + token (8) = 9 bytes
        guard data.count >= 9 else {
            return .invalidMessage("AuthRequest too short: \(data.count) bytes")
        }
        
        let clientToken = data.subdata(in: 1..<9)
        
        // Hash the client's token
        let tokenHash = hashData(clientToken)
        
        // Generate our challenge
        let challenge = generateChallenge()
        pendingChallenge = challenge
        
        // Build AuthChallengeRx response
        // Format: opcode (0x05) + tokenHash (8) + challenge (8) = 17 bytes
        var response = Data([G6SimOpcode.authChallengeRx])
        response.append(tokenHash)
        response.append(challenge)
        
        state = .awaitingChallengeResponse
        
        return .sendResponse(response)
    }
    
    // MARK: - Challenge Response (Step 2)
    
    /// Handle AuthChallengeTx (0x04) from client
    private func handleChallengeResponse(_ data: Data) -> G6AuthResult {
        // Format: opcode (1) + challengeResponse (8) = 9 bytes
        guard data.count >= 9 else {
            return .invalidMessage("AuthChallenge too short: \(data.count) bytes")
        }
        
        guard state == .awaitingChallengeResponse else {
            return .invalidMessage("Unexpected challenge response in state: \(state)")
        }
        
        guard let pendingChallenge = pendingChallenge else {
            return .failed(reason: "No pending challenge")
        }
        
        let clientResponse = data.subdata(in: 1..<9)
        
        // Verify the client's response
        let expectedResponse = hashData(pendingChallenge)
        
        let authenticated = clientResponse == expectedResponse
        
        // Build AuthStatusRx response
        // Format: opcode (0x06) + authenticated (1) + bonded (1) = 3 bytes
        var response = Data([G6SimOpcode.authStatusRx])
        response.append(authenticated ? 0x01 : 0x00)
        response.append(isBonded ? 0x01 : 0x00)
        
        if authenticated {
            state = isBonded ? .bonded : .authenticated
            self.pendingChallenge = nil
            return .sendResponse(response)
        } else {
            state = .failed
            self.pendingChallenge = nil
            return .failed(reason: "Challenge response mismatch")
        }
    }
    
    // MARK: - Bond Request
    
    /// Handle BondRequest (0x08) from client
    private func handleBondRequest(_ data: Data) -> G6AuthResult {
        guard state == .authenticated else {
            return .invalidMessage("Cannot bond in state: \(state)")
        }
        
        isBonded = true
        state = .bonded
        
        // No response needed for bond request, but return auth status
        var response = Data([G6SimOpcode.authStatusRx])
        response.append(0x01)  // authenticated
        response.append(0x01)  // bonded
        
        return .authenticated(bonded: true)
    }
    
    // MARK: - Keep Alive
    
    /// Handle KeepAlive (0x07) from client
    private func handleKeepAlive(_ data: Data) -> G6AuthResult {
        // Keep alive is just acknowledged, no response needed
        // But we can return a status to indicate we're still alive
        return .authenticated(bonded: isBonded)
    }
    
    // MARK: - Crypto Operations
    
    /// Generate a random 8-byte challenge
    private func generateChallenge() -> Data {
        var challenge = Data(count: 8)
        for i in 0..<8 {
            challenge[i] = UInt8.random(in: 0...255)
        }
        return challenge
    }
    
    /// Hash 8 bytes of data using AES-ECB encryption
    /// - Parameter data: 8-byte data to hash
    /// - Returns: First 8 bytes of AES encryption result
    public func hashData(_ data: Data) -> Data {
        // Pad to 16 bytes
        var padded = Data(count: 16)
        for (i, byte) in data.prefix(8).enumerated() {
            padded[i] = byte
        }
        
        // Encrypt with AES-ECB
        let encrypted = aesEncryptECB(data: padded, key: cryptKey)
        
        // Return first 8 bytes
        return encrypted.prefix(8)
    }
    
    // MARK: - State Management
    
    /// Reset authentication state
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        state = .awaitingAuthRequest
        pendingChallenge = nil
        // Note: isBonded persists across resets
    }
    
    /// Unbond the client
    public func unbond() {
        lock.lock()
        defer { lock.unlock() }
        
        isBonded = false
        state = .awaitingAuthRequest
        pendingChallenge = nil
    }
    
    /// Check if currently authenticated
    public var isAuthenticated: Bool {
        state == .authenticated || state == .bonded
    }
}

// MARK: - Opcodes

/// G6 opcodes used in simulation
public enum G6SimOpcode {
    public static let authRequestTx: UInt8 = 0x01
    public static let authRequest2Tx: UInt8 = 0x02  // G6+ (Firefly)
    public static let authChallengeRx: UInt8 = 0x05
    public static let authChallengeTx: UInt8 = 0x04
    public static let authStatusRx: UInt8 = 0x06
    public static let keepAlive: UInt8 = 0x07
    public static let bondRequest: UInt8 = 0x08
    public static let disconnect: UInt8 = 0x09
}

// MARK: - AES-ECB Implementation

extension G6AuthSimulator {
    
    /// AES-128-ECB encryption (single block)
    func aesEncryptECB(data: Data, key: Data) -> Data {
        #if canImport(CommonCrypto)
        return aesEncryptCommonCrypto(data: data, key: key)
        #else
        return aesEncryptPureSwift(data: data, key: key)
        #endif
    }
}

#if canImport(CommonCrypto)
import CommonCrypto

extension G6AuthSimulator {
    /// AES encryption using CommonCrypto (Darwin)
    fileprivate func aesEncryptCommonCrypto(data: Data, key: Data) -> Data {
        var outData = Data(count: data.count)
        let outDataCount = outData.count
        var numBytesEncrypted: size_t = 0
        
        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, key.count,
                        nil,
                        dataBytes.baseAddress, data.count,
                        outBytes.baseAddress, outDataCount,
                        &numBytesEncrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            return Data(count: 16)
        }
        
        return outData
    }
}
#endif

// Pure Swift AES implementation for Linux
extension G6AuthSimulator {
    /// Pure Swift AES-128 encryption (for Linux compatibility)
    fileprivate func aesEncryptPureSwift(data: Data, key: Data) -> Data {
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
        
        let rcon: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]
        
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
                let t = temp[0]
                temp[0] = temp[1]
                temp[1] = temp[2]
                temp[2] = temp[3]
                temp[3] = t
                for j in 0..<4 {
                    temp[j] = sbox[Int(temp[j])]
                }
                temp[0] ^= rcon[i / 4 - 1]
            }
            for j in 0..<4 {
                expandedKey[i * 4 + j] = expandedKey[(i - 4) * 4 + j] ^ temp[j]
            }
        }
        
        var state = [[UInt8]](repeating: [UInt8](repeating: 0, count: 4), count: 4)
        let dataBytes = [UInt8](data)
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] = dataBytes[r + 4 * c]
            }
        }
        
        for r in 0..<4 {
            for c in 0..<4 {
                state[r][c] ^= expandedKey[r + 4 * c]
            }
        }
        
        for round in 1..<10 {
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
            
            for r in 0..<4 {
                for c in 0..<4 {
                    state[r][c] ^= expandedKey[round * 16 + r + 4 * c]
                }
            }
        }
        
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
        
        var output = Data(count: 16)
        for r in 0..<4 {
            for c in 0..<4 {
                output[r + 4 * c] = state[r][c]
            }
        }
        
        return output
    }
    
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
