// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7AuthSimulator.swift
// BLEKit
//
// Server-side Dexcom G7 J-PAKE authentication for transmitter simulation.
// Implements the responder (sensor) side of the J-PAKE protocol.
// Trace: PRD-007 REQ-SIM-003, APP-SIM-010

import Foundation

// MARK: - G7 Authentication State

/// State of the G7 J-PAKE authentication handshake
public enum G7AuthState: String, Sendable, Codable {
    /// Waiting for client's Round 1 message
    case awaitingRound1
    
    /// Sent Round 1 response, waiting for Round 2
    case awaitingRound2
    
    /// Sent Round 2 response, waiting for confirmation
    case awaitingConfirmation
    
    /// Successfully authenticated
    case authenticated
    
    /// Authentication failed
    case failed
}

// MARK: - G7 Authentication Result

/// Result of processing a G7 authentication message
public enum G7AuthResult: Sendable {
    /// Send this response to the client
    case sendResponse(Data)
    
    /// Authentication succeeded with session key
    case authenticated(sessionKey: Data)
    
    /// Authentication failed
    case failed(reason: String)
    
    /// Invalid or unexpected message
    case invalidMessage(String)
}

// MARK: - G7 Auth Simulator

/// Server-side G7 J-PAKE authentication handler for transmitter simulation
///
/// Implements the Dexcom G7 J-PAKE authentication protocol from the sensor's perspective:
/// 1. Receive Round 1 from client (g^x1, g^x2 with ZK proofs)
/// 2. Generate own Round 1 values (g^x3, g^x4), send response
/// 3. Receive Round 2 from client (A with ZK proof)
/// 4. Generate Round 2 value (B), send response
/// 5. Receive confirmation, verify and send final confirmation
///
/// ## Usage
/// ```swift
/// let simulator = G7AuthSimulator(sensorCode: "1234")
///
/// // When client sends auth message:
/// let result = simulator.processMessage(clientData)
/// switch result {
/// case .sendResponse(let data):
///     // Send data back on Authentication characteristic
/// case .authenticated(let sessionKey):
///     // Client is now authenticated with sessionKey
/// case .failed(let reason):
///     // Authentication failed
/// }
/// ```
public final class G7AuthSimulator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Sensor code (4-digit shared secret)
    public let sensorCode: String
    
    /// Current authentication state
    public private(set) var state: G7AuthState = .awaitingRound1
    
    /// Derived session key after successful authentication
    public private(set) var sessionKey: Data?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - J-PAKE Values (Responder Side)
    
    // Generator (same as client)
    private static let generator: [UInt8] = [
        0x6B, 0x17, 0xD1, 0xF2, 0xE1, 0x2C, 0x42, 0x47,
        0xF8, 0xBC, 0xE6, 0xE5, 0x63, 0xA4, 0x40, 0xF2,
        0x77, 0x03, 0x7D, 0x81, 0x2D, 0xEB, 0x33, 0xA0,
        0xF4, 0xA1, 0x39, 0x45, 0xD8, 0x98, 0xC2, 0x96
    ]
    
    // Our random values (x3, x4)
    private var x3: Data?
    private var x4: Data?
    private var gx3: Data?
    private var gx4: Data?
    
    // Received values from client (x1, x2)
    private var gx1: Data?
    private var gx2: Data?
    
    // Round 2 values
    private var clientRound2Value: Data?
    private var ourRound2Value: Data?
    
    // MARK: - Initialization
    
    /// Create a G7 auth simulator with sensor code
    /// - Parameter sensorCode: 4-digit sensor code (shared secret)
    public init(sensorCode: String) {
        // Validate or accept any 4-digit code
        let code = sensorCode.count == 4 ? sensorCode : "0000"
        self.sensorCode = code
    }
    
    // MARK: - Message Processing
    
    /// Process an incoming authentication message
    /// - Parameter data: Raw message data from client
    /// - Returns: Result indicating what action to take
    public func processMessage(_ data: Data) -> G7AuthResult {
        lock.lock()
        defer { lock.unlock() }
        
        guard !data.isEmpty else {
            return .invalidMessage("Empty message")
        }
        
        let opcode = data[0]
        
        switch opcode {
        case G7SimOpcode.authRound1:
            return handleRound1(data)
            
        case G7SimOpcode.authRound2:
            return handleRound2(data)
            
        case G7SimOpcode.authConfirm:
            return handleConfirmation(data)
            
        default:
            return .invalidMessage("Unknown opcode: 0x\(String(format: "%02X", opcode))")
        }
    }
    
    // MARK: - Round 1 Handler
    
    /// Handle Round 1 from client
    private func handleRound1(_ data: Data) -> G7AuthResult {
        guard state == .awaitingRound1 else {
            return .invalidMessage("Unexpected Round 1 in state: \(state)")
        }
        
        // Parse client's Round 1 message
        // Format: opcode(1) + gx1(32) + gx2(32) + zkp1(80) + zkp2(80) = 225 bytes
        guard data.count >= 225 else {
            return .invalidMessage("Round 1 too short: \(data.count) bytes")
        }
        
        // Extract client values
        gx1 = data.subdata(in: 1..<33)
        gx2 = data.subdata(in: 33..<65)
        
        // Verify ZK proofs (simplified verification)
        let zkp1 = data.subdata(in: 65..<145)
        let zkp2 = data.subdata(in: 145..<225)
        
        guard verifyZKProof(zkp1, publicValue: gx1!),
              verifyZKProof(zkp2, publicValue: gx2!) else {
            state = .failed
            return .failed(reason: "Invalid ZK proofs in Round 1")
        }
        
        // Generate our Round 1 values (x3, x4)
        x3 = generateRandomScalar()
        x4 = generateRandomScalar()
        gx3 = computeGroupElement(x3!)
        gx4 = computeGroupElement(x4!)
        
        // Generate our ZK proofs
        let zkp3 = generateZKProof(exponent: x3!, publicValue: gx3!)
        let zkp4 = generateZKProof(exponent: x4!, publicValue: gx4!)
        
        // Build Round 1 response
        var response = Data([G7SimOpcode.authRound1])
        response.append(gx3!)
        response.append(gx4!)
        response.append(zkp3)
        response.append(zkp4)
        
        state = .awaitingRound2
        
        return .sendResponse(response)
    }
    
    // MARK: - Round 2 Handler
    
    /// Handle Round 2 from client
    private func handleRound2(_ data: Data) -> G7AuthResult {
        guard state == .awaitingRound2 else {
            return .invalidMessage("Unexpected Round 2 in state: \(state)")
        }
        
        // Parse client's Round 2 message
        // Format: opcode(1) + A(32) + zkpA(80) = 113 bytes
        guard data.count >= 113 else {
            return .invalidMessage("Round 2 too short: \(data.count) bytes")
        }
        
        clientRound2Value = data.subdata(in: 1..<33)
        let zkpA = data.subdata(in: 33..<113)
        
        // Verify ZK proof for A
        guard verifyZKProof(zkpA, publicValue: clientRound2Value!) else {
            state = .failed
            return .failed(reason: "Invalid ZK proof in Round 2")
        }
        
        // Compute our Round 2 value B
        let passwordScalar = derivePasswordScalar(from: sensorCode)
        ourRound2Value = computeRound2Value(passwordScalar: passwordScalar)
        
        // Generate ZK proof for B
        let zkpB = generateZKProof(exponent: x4!, publicValue: ourRound2Value!)
        
        // Build Round 2 response
        var response = Data([G7SimOpcode.authRound2])
        response.append(ourRound2Value!)
        response.append(zkpB)
        
        state = .awaitingConfirmation
        
        return .sendResponse(response)
    }
    
    // MARK: - Confirmation Handler
    
    /// Handle confirmation from client
    private func handleConfirmation(_ data: Data) -> G7AuthResult {
        guard state == .awaitingConfirmation else {
            return .invalidMessage("Unexpected confirmation in state: \(state)")
        }
        
        // Parse confirmation message
        // Format: opcode(1) + confirmHash(16) = 17 bytes
        guard data.count >= 17 else {
            return .invalidMessage("Confirmation too short: \(data.count) bytes")
        }
        
        let clientConfirmHash = data.subdata(in: 1..<17)
        
        // Compute shared session key
        guard let clientValue = clientRound2Value, let ourValue = ourRound2Value, let x4 = x4 else {
            state = .failed
            return .failed(reason: "Missing values for key derivation")
        }
        
        let sharedKey = computeSharedKey(clientRound2: clientValue, ourRound2: ourValue, x4: x4)
        
        // Verify client's confirmation hash
        let expectedClientHash = computeConfirmationHash(key: sharedKey, isInitiator: true)
        
        guard clientConfirmHash == expectedClientHash else {
            state = .failed
            return .failed(reason: "Confirmation hash mismatch")
        }
        
        // Generate our confirmation hash
        let ourConfirmHash = computeConfirmationHash(key: sharedKey, isInitiator: false)
        
        // Build confirmation response
        var response = Data([G7SimOpcode.authConfirm])
        response.append(ourConfirmHash)
        
        sessionKey = sharedKey
        state = .authenticated
        
        return .sendResponse(response)
    }
    
    // MARK: - Cryptographic Operations
    
    /// Generate a random 32-byte scalar
    private func generateRandomScalar() -> Data {
        var scalar = Data(count: 32)
        for i in 0..<32 {
            scalar[i] = UInt8.random(in: 0...255)
        }
        return scalar
    }
    
    /// Compute group element g^x (simplified hash-based for demo)
    private func computeGroupElement(_ exponent: Data) -> Data {
        return sha256(Self.generator + exponent)
    }
    
    /// Generate zero-knowledge proof (Schnorr-style)
    private func generateZKProof(exponent: Data, publicValue: Data) -> Data {
        let k = generateRandomScalar()  // Random nonce
        let gk = computeGroupElement(k)  // Commitment
        
        // Challenge c = H(g, Y, g^k)
        let challenge = sha256(Self.generator + publicValue + gk)
        
        // Response r = k XOR H(c, x)
        let response = xorBytes(k, sha256(challenge + exponent))
        
        // Pack: commitment(32) + challenge(16) + response(32) = 80 bytes
        var proof = Data()
        proof.append(gk)
        proof.append(challenge.prefix(16))
        proof.append(response)
        return proof
    }
    
    /// Verify ZK proof (simplified)
    private func verifyZKProof(_ proof: Data, publicValue: Data) -> Bool {
        // For demo/testing, accept any well-formed proof
        return proof.count >= 80 && publicValue.count == 32
    }
    
    /// Derive scalar from password
    private func derivePasswordScalar(from password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        return sha256(passwordData + Data("G7-JPAKE-PASSWORD".utf8))
    }
    
    /// Compute Round 2 value B
    private func computeRound2Value(passwordScalar: Data) -> Data {
        guard let x4 = x4, let gx1 = gx1, let gx2 = gx2, let gx3 = gx3 else {
            return Data(count: 32)
        }
        
        // B = (gx1 * gx2 * gx3)^(x4 * s)
        // Simplified: hash-based computation
        let combined = sha256(gx1 + gx2 + gx3)
        let exponent = sha256(x4 + passwordScalar)
        return sha256(combined + exponent)
    }
    
    /// Compute shared key
    private func computeSharedKey(clientRound2 a: Data, ourRound2 b: Data, x4: Data) -> Data {
        // K = (A / g^(x1*x2*s))^x4
        // Simplified: hash-based key derivation
        let intermediate = sha256(a + b + x4)
        return sha256(intermediate + Data("G7-SESSION-KEY".utf8))
    }
    
    /// Compute confirmation hash
    private func computeConfirmationHash(key: Data, isInitiator: Bool) -> Data {
        let role = isInitiator ? "initiator" : "responder"
        return sha256(key + Data(role.utf8) + Data("G7-CONFIRM".utf8)).prefix(16)
    }
    
    /// XOR two byte arrays
    private func xorBytes(_ a: Data, _ b: Data) -> Data {
        var result = Data(count: max(a.count, b.count))
        for i in 0..<min(a.count, b.count) {
            result[i] = a[i] ^ b[i]
        }
        // Pad remaining bytes
        for i in min(a.count, b.count)..<result.count {
            result[i] = i < a.count ? a[i] : b[i]
        }
        return result.prefix(32)
    }
    
    /// SHA-256 hash
    private func sha256(_ data: Data) -> Data {
        #if canImport(CommonCrypto)
        return sha256CommonCrypto(data)
        #else
        return sha256PureSwift(data)
        #endif
    }
    
    // MARK: - State Management
    
    /// Reset authentication state
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        state = .awaitingRound1
        sessionKey = nil
        x3 = nil
        x4 = nil
        gx1 = nil
        gx2 = nil
        gx3 = nil
        gx4 = nil
        clientRound2Value = nil
        ourRound2Value = nil
    }
    
    /// Check if authenticated
    public var isAuthenticated: Bool {
        state == .authenticated
    }
}

// MARK: - G7 Simulator Opcodes

/// G7 opcodes for simulation
public enum G7SimOpcode {
    public static let authInit: UInt8 = 0x01
    public static let authRound1: UInt8 = 0x02
    public static let authRound2: UInt8 = 0x03
    public static let authConfirm: UInt8 = 0x04
    public static let authStatus: UInt8 = 0x05
}

// MARK: - SHA-256 Implementation

#if canImport(CommonCrypto)
import CommonCrypto

extension G7AuthSimulator {
    fileprivate func sha256CommonCrypto(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
#endif

// Pure Swift SHA-256 for Linux
extension G7AuthSimulator {
    fileprivate func sha256PureSwift(_ data: Data) -> Data {
        // SHA-256 constants
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        
        // Initial hash values
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        
        // Pre-processing: adding padding bits
        var message = [UInt8](data)
        let originalLength = message.count
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0x00)
        }
        
        // Append original length in bits as 64-bit big-endian
        let bitLength = UInt64(originalLength) * 8
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLength >> (i * 8)) & 0xFF))
        }
        
        // Process each 512-bit chunk
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            
            // Break chunk into sixteen 32-bit big-endian words
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = UInt32(message[offset]) << 24 |
                       UInt32(message[offset + 1]) << 16 |
                       UInt32(message[offset + 2]) << 8 |
                       UInt32(message[offset + 3])
            }
            
            // Extend the sixteen 32-bit words into sixty-four 32-bit words
            for i in 16..<64 {
                let s0 = w[i-15].rotateRight(7) ^ w[i-15].rotateRight(18) ^ (w[i-15] >> 3)
                let s1 = w[i-2].rotateRight(17) ^ w[i-2].rotateRight(19) ^ (w[i-2] >> 10)
                w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
            }
            
            // Initialize working variables
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            
            // Main loop
            for i in 0..<64 {
                let S1 = e.rotateRight(6) ^ e.rotateRight(11) ^ e.rotateRight(25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = a.rotateRight(2) ^ a.rotateRight(13) ^ a.rotateRight(22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj
                
                hh = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            
            // Add the compressed chunk to the current hash value
            h[0] &+= a
            h[1] &+= b
            h[2] &+= c
            h[3] &+= d
            h[4] &+= e
            h[5] &+= f
            h[6] &+= g
            h[7] &+= hh
        }
        
        // Produce the final hash value (big-endian)
        var hash = Data(capacity: 32)
        for value in h {
            hash.append(UInt8((value >> 24) & 0xFF))
            hash.append(UInt8((value >> 16) & 0xFF))
            hash.append(UInt8((value >> 8) & 0xFF))
            hash.append(UInt8(value & 0xFF))
        }
        return hash
    }
}

// Helper for bit rotation
private extension UInt32 {
    func rotateRight(_ n: UInt32) -> UInt32 {
        return (self >> n) | (self << (32 - n))
    }
}
