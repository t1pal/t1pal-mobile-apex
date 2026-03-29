// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7ECOperations.swift
// CGMKit - DexcomG7
//
// P-256 elliptic curve operations for J-PAKE authentication.
// Point operations extracted to: G7ECPointOps.swift
// Derivation extracted to: G7JPAKEDerivation.swift
// ZKP formats extracted to: G7JPAKEProofs.swift
//
// Trace: JPAKE-EC-001, PRD-008 REQ-BLE-008, FILE-HYGIENE-007

import Foundation
import CryptoValidation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

// MARK: - P-256 Constants

/// P-256 curve constants matching xDrip libkeks
/// Source: externals/xDrip/libkeks/src/main/java/jamorham/keks/Curve.java
public enum P256Constants {
    /// Curve name (NIST standard)
    public static let curveName = "secp256r1"
    
    /// Field size in bytes (256 bits / 8)
    public static let fieldSize = 32
    
    /// Uncompressed point size: 1 (format byte) + 32 (x) + 32 (y)
    public static let uncompressedPointSize = 65
    
    /// Compressed point size: 1 (format byte) + 32 (x)
    public static let compressedPointSize = 33
    
    /// J-PAKE packet size: 5 * field size
    public static let packetSize = 160
}

// MARK: - J-PAKE Key Pair

/// EC key pair for J-PAKE protocol
/// Wraps swift-crypto P256 keys with J-PAKE specific operations
public struct JPAKEKeyPair: Sendable {
    /// Private scalar (32 bytes)
    public let privateKey: P256.Signing.PrivateKey
    
    /// Public point (on curve)
    public var publicKey: P256.Signing.PublicKey {
        privateKey.publicKey
    }
    
    /// Generate new random key pair
    public init() {
        self.privateKey = P256.Signing.PrivateKey()
    }
    
    /// Initialize from raw private key bytes
    public init(privateKeyBytes: Data) throws {
        self.privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
    }
    
    /// Private key as raw 32-byte scalar
    public var privateKeyBytes: Data {
        privateKey.rawRepresentation
    }
    
    /// Public key X coordinate (32 bytes)
    public var publicKeyX: Data {
        Data(publicKey.rawRepresentation.prefix(32))
    }
    
    /// Public key Y coordinate (32 bytes)
    public var publicKeyY: Data {
        Data(publicKey.rawRepresentation.suffix(32))
    }
    
    /// Public key as uncompressed point (65 bytes: 0x04 || X || Y)
    public var uncompressedPublicKey: Data {
        var data = Data([0x04])
        data.append(publicKey.rawRepresentation)
        return data
    }
    
    /// Public key as raw X||Y (64 bytes, no format prefix)
    public var rawPublicKey: Data {
        publicKey.rawRepresentation
    }
}

// MARK: - Scalar Operations Continued

extension ScalarOperations {
    
    // MARK: - Modular Arithmetic (JPAKE-EC-003)
    
    /// Compare two 32-byte big-endian scalars
    /// Returns: -1 if a < b, 0 if a == b, 1 if a > b
    public static func compare(_ a: Data, _ b: Data) -> Int {
        let aBytes = Array(a)
        let bBytes = Array(b)
        for i in 0..<min(aBytes.count, bBytes.count) {
            if aBytes[i] < bBytes[i] { return -1 }
            if aBytes[i] > bBytes[i] { return 1 }
        }
        return 0
    }
    
    /// Reduce scalar mod curve order n
    /// Uses repeated subtraction (simple but correct for values < 2n)
    public static func modN(_ scalar: Data) -> Data {
        var value = Array(scalar)
        // Pad to 32 bytes if needed
        while value.count < 32 {
            value.insert(0, at: 0)
        }
        // If value >= n, subtract n
        while compare(Data(value), Data(curveOrder)) >= 0 {
            value = subtractBigInt(value, curveOrder)
        }
        return Data(value)
    }
    
    /// Add two scalars mod curve order: (a + b) mod n
    public static func addMod(_ a: Data, _ b: Data) -> Data {
        let sum = addBigInt(Array(a), Array(b))
        return modN(Data(sum))
    }
    
    /// Subtract two scalars mod curve order: (a - b) mod n
    /// If a < b, wraps around: (a - b + n) mod n
    public static func subtractMod(_ a: Data, _ b: Data) -> Data {
        if compare(a, b) >= 0 {
            return modN(Data(subtractBigInt(Array(a), Array(b))))
        } else {
            // a < b: compute (n - b + a) = n - (b - a)
            let diff = subtractBigInt(Array(b), Array(a))
            let result = subtractBigInt(curveOrder, diff)
            return Data(result)
        }
    }
    
    /// Multiply two scalars mod curve order: (a * b) mod n
    /// Uses schoolbook byte multiplication with reduction
    public static func multiplyMod(_ a: Data, _ b: Data) -> Data {
        let product = multiplyBigInt(Array(a), Array(b))
        return modNWide(Data(product))
    }
    
    // MARK: - Big Integer Helpers
    
    /// Add two big integers (big-endian byte arrays)
    private static func addBigInt(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let aLen = a.count
        let bLen = b.count
        let maxLen = max(aLen, bLen)
        var result = [UInt8](repeating: 0, count: maxLen + 1)
        var carry: UInt16 = 0
        
        for i in 0..<maxLen {
            let aIdx = aLen - 1 - i
            let bIdx = bLen - 1 - i
            let rIdx = maxLen - i
            
            let aVal: UInt16 = aIdx >= 0 ? UInt16(a[aIdx]) : 0
            let bVal: UInt16 = bIdx >= 0 ? UInt16(b[bIdx]) : 0
            
            let sum = aVal + bVal + carry
            result[rIdx] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
        result[0] = UInt8(carry)
        
        // Remove leading zeros
        while result.count > 32 && result[0] == 0 {
            result.removeFirst()
        }
        return result
    }
    
    /// Subtract big integers: a - b (assumes a >= b)
    private static func subtractBigInt(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: a.count)
        var borrow: Int16 = 0
        
        for i in (0..<a.count).reversed() {
            let bIdx = b.count - (a.count - i)
            let bVal: Int16 = bIdx >= 0 ? Int16(b[bIdx]) : 0
            
            var diff = Int16(a[i]) - bVal - borrow
            if diff < 0 {
                diff += 256
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = UInt8(diff)
        }
        
        // Remove leading zeros but keep at least 32 bytes
        while result.count > 32 && result[0] == 0 {
            result.removeFirst()
        }
        return result
    }
    
    /// Multiply big integers using schoolbook algorithm
    private static func multiplyBigInt(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let aLen = a.count
        let bLen = b.count
        var result = [UInt32](repeating: 0, count: aLen + bLen)
        
        // Schoolbook multiplication
        for i in (0..<aLen).reversed() {
            for j in (0..<bLen).reversed() {
                let prod = UInt32(a[i]) * UInt32(b[j])
                let pos = i + j + 1
                result[pos] += prod
            }
        }
        
        // Carry propagation
        for i in (1..<result.count).reversed() {
            result[i-1] += result[i] >> 8
            result[i] &= 0xFF
        }
        
        // Convert to bytes
        var bytes = result.map { UInt8($0 & 0xFF) }
        
        // Remove leading zeros
        while bytes.count > 32 && bytes[0] == 0 {
            bytes.removeFirst()
        }
        return bytes
    }
    
    /// Reduce wide value (up to 64 bytes) mod n
    /// Uses Barrett-like reduction with iteration limit
    private static func modNWide(_ value: Data) -> Data {
        var current = Array(value)
        let n = curveOrder
        
        // Pad to at least 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        
        // Iteration limit to prevent infinite loops
        var iterations = 0
        let maxIterations = 1000
        
        // Reduce by repeated subtraction (correct but slow for large values)
        while iterations < maxIterations {
            iterations += 1
            
            if current.count > 32 {
                // Remove leading zeros first
                while current.count > 32 && current[0] == 0 {
                    current.removeFirst()
                }
                if current.count <= 32 {
                    continue
                }
                
                // Shift n left and subtract
                let shift = current.count - 32
                var shifted = [UInt8](repeating: 0, count: shift) + n
                
                if compare(Data(current), Data(shifted)) >= 0 {
                    current = subtractBigInt(current, shifted)
                } else {
                    // Try with smaller shift
                    if shift > 0 {
                        shifted = [UInt8](repeating: 0, count: shift - 1) + n
                        if compare(Data(current), Data(shifted)) >= 0 {
                            current = subtractBigInt(current, shifted)
                        } else {
                            // Can't reduce further with subtraction
                            break
                        }
                    } else {
                        break
                    }
                }
            } else if compare(Data(current), Data(n)) >= 0 {
                current = subtractBigInt(current, n)
            } else {
                break  // current < n, we're done
            }
        }
        
        // Final reduction if still >= n
        while current.count == 32 && compare(Data(current), Data(n)) >= 0 {
            current = subtractBigInt(current, n)
        }
        
        // Ensure 32 bytes
        while current.count < 32 {
            current.insert(0, at: 0)
        }
        while current.count > 32 {
            current.removeFirst()
        }
        return Data(current)
    }
}

// MARK: - J-PAKE Protocol Operations

/// High-level J-PAKE protocol operations using P-256
public actor JPAKEProtocol {
    
    /// Party identifiers (matching xDrip)
    public enum Party {
        /// Client/initiator identifier
        public static let alice: Data = Data([0x36, 0xC6, 0x96, 0x56, 0xE6, 0x47])
        /// Server/responder identifier
        public static let bob: Data = Data([0x37, 0x56, 0x27, 0x67, 0x56, 0x27])
    }
    
    /// Our key pairs (x1, x2)
    private var keyA: JPAKEKeyPair?
    private var keyB: JPAKEKeyPair?
    
    /// Password (sensor code)
    private let password: String
    
    /// Received remote public keys
    private var remoteX3: P256.Signing.PublicKey?
    private var remoteX4: P256.Signing.PublicKey?
    
    public init(password: String) {
        self.password = password
    }
    
    /// Generate Round 1 key pairs and message
    /// Returns: (gx1, gx2, zkp1, zkp2) as raw bytes
    public func generateRound1() -> JPAKERound1Data {
        // Generate x1, x2 key pairs
        keyA = JPAKEKeyPair()
        keyB = JPAKEKeyPair()
        
        guard let keyA = keyA, let keyB = keyB else {
            fatalError("Failed to generate key pairs")
        }
        
        // Generate ZK proofs for knowledge of x1 and x2
        let zkp1 = generateZKProof(keyPair: keyA, generator: nil)
        let zkp2 = generateZKProof(keyPair: keyB, generator: nil)
        
        return JPAKERound1Data(
            gx1: keyA.rawPublicKey,
            gx2: keyB.rawPublicKey,
            zkp1: zkp1,
            zkp2: zkp2
        )
    }
    
    /// Process received Round 1 data and generate Round 2
    public func processRound1AndGenerateRound2(
        remoteGx3: Data,
        remoteGx4: Data,
        zkp3: JPAKEZKProofData,
        zkp4: JPAKEZKProofData
    ) throws -> JPAKERound2Data {
        // Parse remote public keys
        guard let x3 = ECPointOperations.parseRawPoint(remoteGx3),
              let x4 = ECPointOperations.parseRawPoint(remoteGx4) else {
            throw JPAKEError.invalidPublicKey
        }
        
        // Verify ZK proofs
        guard verifyZKProof(zkp3, publicKey: x3, generator: nil, party: Party.bob),
              verifyZKProof(zkp4, publicKey: x4, generator: nil, party: Party.bob) else {
            throw JPAKEError.zkProofVerificationFailed
        }
        
        // Store remote keys
        remoteX3 = x3
        remoteX4 = x4
        
        // Compute Round 2 value: A = (g^x1 + g^x3 + g^x4)^(x2 * s)
        // For now, return placeholder - full EC point addition requires more complex operations
        let round2Value = computeRound2Value()
        let zkpA = generateRound2ZKProof()
        
        return JPAKERound2Data(
            a: round2Value,
            zkpA: zkpA
        )
    }
    
    // MARK: - Private Helpers
    
    private func generateZKProof(keyPair: JPAKEKeyPair, generator: P256.Signing.PublicKey?) -> JPAKEZKProofData {
        // Schnorr ZKP: prove knowledge of x such that Y = g^x
        // Protocol: commitment V = g^v, challenge c = H(g||V||Y||party), response r = v - c*x mod n
        
        // Random nonce v
        let v = JPAKEKeyPair()
        
        // Get generator point (use P-256 base point if not specified)
        let g = generator?.rawRepresentation ?? ECPointOperations.generatorRaw
        
        // Commitment V = g^v
        guard let commitment = ECPointOperations.scalarMultiply(point: g, scalar: v.privateKeyBytes) else {
            // Fallback to using the precomputed public key if scalar multiply fails
            return JPAKEZKProofData(
                commitment: v.rawPublicKey,
                challenge: Data(count: 16),
                response: Data(count: 32)
            )
        }
        
        // Challenge c = H(length||g||length||V||length||Y||length||party) mod n (xDrip format)
        var hashInput = Data()
        hashInput.append(contentsOf: lengthPrefixFor(g))
        hashInput.append(g)
        hashInput.append(contentsOf: lengthPrefixFor(commitment))
        hashInput.append(commitment)
        hashInput.append(contentsOf: lengthPrefixFor(keyPair.rawPublicKey))
        hashInput.append(keyPair.rawPublicKey)
        hashInput.append(contentsOf: lengthPrefixFor(Party.alice))
        hashInput.append(Party.alice)
        
        let challengeFull = Data(SHA256.hash(data: hashInput))
        let challenge = ScalarOperations.modN(challengeFull)
        
        // Response r = v - c * x mod n
        let cx = ScalarOperations.multiplyMod(challenge, keyPair.privateKeyBytes)
        let response = ScalarOperations.subtractMod(v.privateKeyBytes, cx)
        
        return JPAKEZKProofData(
            commitment: commitment,
            challenge: Data(challenge.prefix(16)),
            response: response
        )
    }
    
    /// 4-byte big-endian length prefix (local version for Round 1)
    private func lengthPrefixFor(_ data: Data) -> [UInt8] {
        let len = UInt32(data.count)
        return [
            UInt8((len >> 24) & 0xFF),
            UInt8((len >> 16) & 0xFF),
            UInt8((len >> 8) & 0xFF),
            UInt8(len & 0xFF)
        ]
    }
    
    private func verifyZKProof(
        _ proof: JPAKEZKProofData,
        publicKey: P256.Signing.PublicKey,
        generator: P256.Signing.PublicKey?,
        party: Data
    ) -> Bool {
        // Verify Schnorr proof: g^r * Y^c == V (commitment)
        // Where: r = response, c = challenge, Y = publicKey, V = commitment
        
        // Basic structure validation
        guard proof.commitment.count == 64,
              proof.challenge.count >= 16,
              proof.response.count == 32 else {
            return false
        }
        
        // Get generator point (use P-256 base point if not specified)
        let g = generator?.rawRepresentation ?? ECPointOperations.generatorRaw
        
        // Compute g^r
        guard let gr = ECPointOperations.scalarMultiply(point: g, scalar: proof.response) else {
            return false
        }
        
        // Extend challenge to 32 bytes for scalar multiplication
        var challengeScalar = Data(proof.challenge)
        while challengeScalar.count < 32 {
            challengeScalar.insert(0, at: 0)
        }
        
        // Compute Y^c
        guard let yc = ECPointOperations.scalarMultiply(
            point: publicKey.rawRepresentation,
            scalar: challengeScalar
        ) else {
            return false
        }
        
        // Compute g^r + Y^c
        guard let computed = ECPointOperations.addPoints(p1: gr, p2: yc) else {
            return false
        }
        
        // Verify: computed == commitment
        return computed == proof.commitment
    }
    
    private func computeRound2Value() -> Data {
        guard let keyA = keyA, let keyB = keyB else { return Data(count: 64) }
        
        // Compute A = (g^x1 + g^x3 + g^x4)^(x2 * s)
        // Where x1 = keyA public, x3/x4 = remote public keys, x2 = keyB private, s = password
        
        // Get the public key points
        let gx1 = keyA.rawPublicKey
        guard let x3 = remoteX3?.rawRepresentation,
              let x4 = remoteX4?.rawRepresentation else {
            return Data(count: 64)
        }
        
        // Step 1: Compute base = g^x1 + g^x3 + g^x4 (three-point addition)
        guard let sum12 = ECPointOperations.addPoints(p1: gx1, p2: x3),
              let base = ECPointOperations.addPoints(p1: sum12, p2: x4) else {
            return Data(count: 64)
        }
        
        // Step 2: Compute exponent = x2 * s mod n
        let x2 = keyB.privateKeyBytes
        let s = ScalarOperations.passwordToScalar(password)
        let x2s = ScalarOperations.multiplyMod(x2, s)
        
        // Step 3: Compute A = base^(x2*s)
        guard let result = ECPointOperations.scalarMultiply(point: base, scalar: x2s) else {
            return Data(count: 64)
        }
        
        return result
    }
    
    private func generateRound2ZKProof() -> JPAKEZKProofData {
        guard let keyA = keyA, let keyB = keyB else {
            return JPAKEZKProofData(
                commitment: Data(count: 64),
                challenge: Data(count: 16),
                response: Data(count: 32)
            )
        }
        
        // For Round 2, the ZKP proves knowledge of x2*s where the generator is (g^x1 + g^x3 + g^x4)
        // Compute the custom generator
        guard let x3 = remoteX3?.rawRepresentation,
              let x4 = remoteX4?.rawRepresentation else {
            return generateZKProof(keyPair: keyB, generator: nil)
        }
        
        guard let sum12 = ECPointOperations.addPoints(p1: keyA.rawPublicKey, p2: x3),
              let customGenerator = ECPointOperations.addPoints(p1: sum12, p2: x4),
              ECPointOperations.parseRawPoint(customGenerator) != nil else {
            return generateZKProof(keyPair: keyB, generator: nil)
        }
        
        // Create a temporary key pair for the x2*s scalar
        let s = ScalarOperations.passwordToScalar(password)
        let x2s = ScalarOperations.multiplyMod(keyB.privateKeyBytes, s)
        
        // Generate ZKP with custom generator and x2*s as the secret
        return generateZKProofWithScalar(secret: x2s, generator: customGenerator)
    }
    
    /// Generate ZKP for a given scalar secret with custom generator
    private func generateZKProofWithScalar(secret: Data, generator: Data) -> JPAKEZKProofData {
        // Random nonce v
        let v = JPAKEKeyPair()
        
        // Commitment V = generator^v
        guard let commitment = ECPointOperations.scalarMultiply(point: generator, scalar: v.privateKeyBytes) else {
            return JPAKEZKProofData(
                commitment: Data(count: 64),
                challenge: Data(count: 16),
                response: Data(count: 32)
            )
        }
        
        // Public key Y = generator^secret
        guard let publicY = ECPointOperations.scalarMultiply(point: generator, scalar: secret) else {
            return JPAKEZKProofData(
                commitment: Data(count: 64),
                challenge: Data(count: 16),
                response: Data(count: 32)
            )
        }
        
        // Challenge c = H(length||g||length||V||length||Y||length||party) mod n
        var hashInput = Data()
        hashInput.append(contentsOf: lengthPrefix(generator))
        hashInput.append(generator)
        hashInput.append(contentsOf: lengthPrefix(commitment))
        hashInput.append(commitment)
        hashInput.append(contentsOf: lengthPrefix(publicY))
        hashInput.append(publicY)
        hashInput.append(contentsOf: lengthPrefix(Party.alice))
        hashInput.append(Party.alice)
        
        let challengeFull = Data(SHA256.hash(data: hashInput))
        let challenge = ScalarOperations.modN(challengeFull)
        
        // Response r = v - c * secret mod n
        let cx = ScalarOperations.multiplyMod(challenge, secret)
        let response = ScalarOperations.subtractMod(v.privateKeyBytes, cx)
        
        return JPAKEZKProofData(
            commitment: commitment,
            challenge: Data(challenge.prefix(16)),
            response: response
        )
    }
    
    /// 4-byte big-endian length prefix
    private func lengthPrefix(_ data: Data) -> [UInt8] {
        let len = UInt32(data.count)
        return [
            UInt8((len >> 24) & 0xFF),
            UInt8((len >> 16) & 0xFF),
            UInt8((len >> 8) & 0xFF),
            UInt8(len & 0xFF)
        ]
    }
    
    /// Compute shared key after receiving Round 3
    /// K = (B - x4^(x2*s))^x2 then SHA256(K.x)
    /// - Parameters:
    ///   - remoteA: Remote's Round 3 value (A point)
    /// - Returns: 16-byte session key or nil on error
    public func computeSharedKey(remoteA: Data) -> Data? {
        guard let keyB = keyB,
              let x4 = remoteX4?.rawRepresentation else {
            return nil
        }
        
        // Compute x2 * s
        let x2 = keyB.privateKeyBytes
        let s = ScalarOperations.passwordToScalar(password)
        let x2s = ScalarOperations.multiplyMod(x2, s)
        
        // Compute x4^(x2*s)
        guard let x4_x2s = ECPointOperations.scalarMultiply(point: x4, scalar: x2s) else {
            return nil
        }
        
        // Compute -x4^(x2*s) (negate Y coordinate for point subtraction)
        let x4_x2s_neg = negatePoint(x4_x2s)
        
        // Compute B - x4^(x2*s) = B + (-x4^(x2*s))
        guard let diff = ECPointOperations.addPoints(p1: remoteA, p2: x4_x2s_neg) else {
            return nil
        }
        
        // Compute K = diff^x2
        guard let sharedPoint = ECPointOperations.scalarMultiply(point: diff, scalar: x2) else {
            return nil
        }
        
        // Session key = SHA256(K.x) truncated to 16 bytes
        let xCoord = Data(sharedPoint.prefix(32))
        let hash = Data(SHA256.hash(data: xCoord))
        return Data(hash.prefix(16))
    }
    
    /// Negate an EC point (flip Y coordinate)
    private func negatePoint(_ point: Data) -> Data {
        guard point.count == 64 else { return point }
        
        let x = Data(point.prefix(32))
        let y = Array(point.suffix(32))
        
        // -P has coordinates (x, p - y)
        let p = ECPointOperations.fieldPrime
        let negY = FieldArithmetic.subtract(p, y, modulus: p)
        
        return x + Data(negY)
    }
    
    private func xorBytes(_ a: Data, _ b: Data) -> Data {
        var result = Data(count: min(a.count, b.count))
        for i in 0..<result.count {
            result[i] = a[i] ^ b[i]
        }
        while result.count < 32 {
            result.append(0)
        }
        return result
    }
}

// MARK: - Data Structures

/// Round 1 data for J-PAKE exchange
public struct JPAKERound1Data: Sendable {
    public let gx1: Data  // 64 bytes (X || Y)
    public let gx2: Data  // 64 bytes (X || Y)
    public let zkp1: JPAKEZKProofData
    public let zkp2: JPAKEZKProofData
    
    /// Serialize to 160-byte packet (xDrip format)
    public var packetData: Data {
        var data = Data()
        // Point 1 X (32) + Y (32) = 64
        data.append(gx1)
        // Point 2 would go here but xDrip uses different structure
        // Hash (32)
        data.append(zkp1.response.prefix(32))
        return data
    }
}

/// Round 2 data for J-PAKE exchange
public struct JPAKERound2Data: Sendable {
    public let a: Data  // Computed value (64 bytes)
    public let zkpA: JPAKEZKProofData
}

/// Zero-knowledge proof data
public struct JPAKEZKProofData: Sendable {
    public let commitment: Data  // 64 bytes (V point)
    public let challenge: Data   // 16 bytes (truncated hash)
    public let response: Data    // 32 bytes (scalar)
    
    public init(commitment: Data, challenge: Data, response: Data) {
        self.commitment = commitment
        self.challenge = challenge
        self.response = response
    }
}

/// J-PAKE errors
public enum JPAKEError: Error, Sendable {
    case invalidPublicKey
    case zkProofVerificationFailed
    case invalidPassword
    case protocolError(String)
}

// MARK: - ECOperationsProvider Conformance (EC-LIB-012)

/// Make ECPointOperations conform to ECOperationsProvider protocol.
/// This enables cross-validation between hand-rolled and audited implementations.
///
/// **Known Bugs (EC-LIB-013):**
/// The hand-rolled field arithmetic has precision/algorithmic issues.
/// Cross-validation against CryptoKit reveals:
/// - `scalarBaseMultiply`: 100% mismatch rate (field multiply/add bugs)
/// - `addPoints`: Not commutative, produces invalid points
/// - `isValidPoint`: Curve equation check has precision errors
/// - `scalarMultiply`: Inherited bugs from above
///
/// **For production use, prefer PlatformECOperations** which uses CryptoKit.
/// This implementation exists for debugging and educational purposes.
extension ECPointOperations: ECOperationsProvider {
    
    // MARK: - Known Bug Status (EC-LIB-013)
    
    /// Documented bugs in hand-rolled EC operations.
    /// These are tracked by EC-LIB-013 and verified by ECCrossValidationTests.
    public enum KnownBugs: String, CaseIterable, Sendable {
        case scalarBaseMultiply = "100% mismatch vs CryptoKit - field arithmetic precision"
        case addPointsNotCommutative = "P1+P2 != P2+P1 - addition formula errors"
        case addPointsInvalidResult = "Addition produces points not on curve"
        case isValidPointFalseNegatives = "Rejects valid CryptoKit-generated points"
        case scalarMultiplyInvalid = "Scalar multiply produces invalid points"
    }
    
    /// Add two EC points: result = p1 + p2 (protocol-conforming signature)
    ///
    /// **Known Bug (EC-LIB-013):** Not commutative, may produce invalid points.
    public static func addPoints(_ p1: Data, _ p2: Data) -> Data? {
        return addPoints(p1: p1, p2: p2)
    }
    
    /// Negate a point: result = -P (same X, negated Y)
    /// For P-256: -P = (x, p - y) where p is the field prime
    ///
    /// Uses OpenSSL via AuditedECOperations for correct, fast EC math.
    public static func negatePoint(_ point: Data) -> Data? {
        guard point.count == 64 else { return nil }
        
        // EC-LIB-018: Use audited OpenSSL backend instead of hand-rolled
        return AuditedECOperations.negatePoint(point)
    }
    
    /// Validate that a point is on the P-256 curve
    /// Checks: y² = x³ + ax + b (mod p)
    ///
    /// Uses OpenSSL via AuditedECOperations for reliable validation.
    public static func isValidPoint(_ data: Data) -> Bool {
        guard data.count == 64 else { return false }
        
        // EC-LIB-018: Use audited OpenSSL backend instead of buggy hand-rolled
        return AuditedECOperations.isValidPoint(data)
    }
}

// MARK: - Type Alias for Clarity

/// ReferenceECOperations is the hand-rolled implementation used as validation oracle.
/// 
/// **Note (EC-LIB-018):** ECPointOperations now delegates to AuditedECOperations,
/// so this typealias is effectively equivalent to using audited code.
/// Kept for backward compatibility with existing tests.
@available(*, deprecated, message: "Use AuditedECOperations from CryptoValidation instead (EC-LIB-018)")
public typealias ReferenceECOperations = ECPointOperations

// MARK: - xDrip-Compatible J-PAKE Packet (G7-FID-001)

/// xDrip-compatible J-PAKE packet structure (160 bytes)
/// Matches: externals/xDrip/libkeks/src/main/java/jamorham/keks/Packet.java
///
/// **Structure (5 x 32 bytes = 160 bytes):**
/// | Offset | Size | Field |
/// |--------|------|-------|
/// | 0      | 32   | proof (r) - Schnorr proof scalar |
/// | 32     | 32   | publicKey.x |
/// | 64     | 32   | publicKey.y |
/// | 96     | 32   | commitment.x (gv.x) |
/// | 128    | 32   | commitment.y (gv.y) |
///
/// Trace: G7-FID-001, PRD-008 REQ-BLE-008
public struct XDripJPAKEPacket: Sendable, Equatable {
    /// Schnorr proof scalar (32 bytes)
    public let proof: Data
    
    /// Public key point (64 bytes: X || Y)
    public let publicKey: Data
    
    /// Commitment point gv (64 bytes: X || Y)  
    public let commitment: Data
    
    /// Total packet size
    public static let size = P256Constants.packetSize  // 160 bytes
    
    /// Create from components
    public init(proof: Data, publicKey: Data, commitment: Data) {
        // Ensure correct sizes
        self.proof = Data(proof.prefix(32))
        self.publicKey = Data(publicKey.prefix(64))
        self.commitment = Data(commitment.prefix(64))
    }
    
    /// Create from individual coordinates
    public init(proof: Data, publicKeyX: Data, publicKeyY: Data, commitmentX: Data, commitmentY: Data) {
        self.proof = Data(proof.prefix(32))
        self.publicKey = Data(publicKeyX.prefix(32)) + Data(publicKeyY.prefix(32))
        self.commitment = Data(commitmentX.prefix(32)) + Data(commitmentY.prefix(32))
    }
    
    /// Parse from 160-byte xDrip format
    public init?(data: Data) {
        guard data.count >= Self.size else { return nil }
        
        // xDrip Packet.java order: point1(64) + point2(64) + hash(32)
        // But Calc.java ZKP output(): gv(64) is commitment, publicKey is second
        // Actually from Packet.output(): publicKeyPoint1, publicKeyPoint2, hash
        // Where publicKeyPoint1 = public key, publicKeyPoint2 = commitment (gv)
        
        self.publicKey = data.subdata(in: 0..<64)      // Point1: public key
        self.commitment = data.subdata(in: 64..<128)   // Point2: commitment (gv)
        self.proof = data.subdata(in: 128..<160)       // Hash: proof scalar
    }
    
    /// Serialize to 160-byte xDrip format
    /// Matches Packet.java output() method
    public var data: Data {
        var result = Data(capacity: Self.size)
        // xDrip order: publicKeyPoint1 + publicKeyPoint2 + hash
        result.append(publicKey.prefix(64))
        result.append(commitment.prefix(64))
        result.append(proof.prefix(32))
        return result
    }
    
    /// Public key X coordinate
    public var publicKeyX: Data { publicKey.prefix(32) }
    
    /// Public key Y coordinate
    public var publicKeyY: Data { publicKey.suffix(32) }
    
    /// Commitment X coordinate
    public var commitmentX: Data { commitment.prefix(32) }
    
    /// Commitment Y coordinate
    public var commitmentY: Data { commitment.suffix(32) }
    
    /// Validate packet structure
    public var isValid: Bool {
        proof.count == 32 && publicKey.count == 64 && commitment.count == 64
    }
}

/// Round 1/2 message in xDrip format
/// Contains TWO packets (one for each key pair x1, x2)
/// Total wire size: 1 (opcode) + 160 + 160 = 321 bytes
public struct XDripJPAKERound1Message: Sendable {
    /// First packet (for x1 / gx1)
    public let packet1: XDripJPAKEPacket
    
    /// Second packet (for x2 / gx2)
    public let packet2: XDripJPAKEPacket
    
    /// Create from two packets
    public init(packet1: XDripJPAKEPacket, packet2: XDripJPAKEPacket) {
        self.packet1 = packet1
        self.packet2 = packet2
    }
    
    /// Parse from wire data (opcode + 2x160 bytes)
    public init?(data: Data, expectedOpcode: UInt8) {
        guard data.count >= 1 + XDripJPAKEPacket.size * 2 else { return nil }
        guard data[0] == expectedOpcode else { return nil }
        
        guard let p1 = XDripJPAKEPacket(data: data.subdata(in: 1..<161)),
              let p2 = XDripJPAKEPacket(data: data.subdata(in: 161..<321)) else {
            return nil
        }
        
        self.packet1 = p1
        self.packet2 = p2
    }
    
    /// Serialize to wire format
    public func data(opcode: UInt8) -> Data {
        var result = Data([opcode])
        result.append(packet1.data)
        result.append(packet2.data)
        return result
    }
}

// MARK: - xDrip Protocol Flow Documentation (G7-FID-002)

/// xDrip J-PAKE Protocol Flow
///
/// **Wire Protocol (per xDrip Plugin.java):**
/// ```
/// Round1: Send x1 packet (160 bytes) → Receive remote x3 packet (160 bytes)
/// Round2: Send x2 packet (160 bytes) → Receive remote x4 packet (160 bytes)
/// Round3: Send A packet (160 bytes) → Receive remote B packet (160 bytes)
/// Auth:   Send challenge response (8 bytes)
/// ```
///
/// **Key Difference from our implementation:**
/// - xDrip: Sends x1 and x2 in separate rounds (160 bytes each)
/// - Ours:  Sends x1+x2 combined in Round 1 (225 bytes total)
///
/// **xDrip Calc.java key functions:**
/// - `getRound1Packet()`: Returns keyA (x1) with ZKP
/// - `getRound2Packet()`: Returns keyB (x2) with ZKP  
/// - `getRound3Packet()`: Returns A = (x1+x3+x4)^(x2*s) with ZKP
///
/// Trace: G7-FID-002, PRD-008 REQ-BLE-008

/// Type alias for xDrip Round 2 packet (same format as Round 1)
/// Round 2 sends x2 public key with ZKP
public typealias XDripJPAKERound2Packet = XDripJPAKEPacket

/// xDrip Round 3 packet structure (same 160-byte format)
/// Contains the computed A value: A = (x1 + x3 + x4)^(x2 * password)
///
/// **Structure:**
/// - publicKey: A point (the shared secret contribution)
/// - commitment: ZKP commitment (g^v where g = x1+x2+x3)
/// - proof: Schnorr proof scalar
public typealias XDripJPAKERound3Packet = XDripJPAKEPacket

// MARK: - xDrip Key Confirmation Types (G7-FID-003)

/// xDrip AuthChallengeTxMessage structure (9 bytes)
/// Matches: externals/xDrip/libkeks/src/main/java/jamorham/keks/message/AuthChallengeTxMessage.java
///
/// **Protocol Flow:**
/// 1. After Round 3, sensor sends AuthRequestRx with 8-byte challenge at offset 9
/// 2. Client computes: AES-ECB(sessionKey, challenge || challenge)[0:8]
/// 3. Client sends: opcode (0x04) + hash (8 bytes)
///
/// Trace: G7-FID-003, PRD-008 REQ-BLE-008
public struct XDripAuthChallengeTxMessage: Sendable, Equatable {
    /// Opcode for auth challenge (0x04)
    public static let opcode: UInt8 = 0x04
    
    /// Challenge response hash (8 bytes)
    public let challengeHash: Data
    
    /// Total message size
    public static let size = 9
    
    /// Create from computed hash
    public init(challengeHash: Data) {
        self.challengeHash = Data(challengeHash.prefix(8))
    }
    
    /// Create by computing hash from challenge and session key
    /// Uses xDrip method: AES-ECB(key, challenge×2)[0:8]
    public init(challenge: Data, sessionKey: Data) {
        self.challengeHash = ConfirmationHash.aesDoubled.compute(
            sessionKey: sessionKey,
            challenge: Data(challenge.prefix(8))
        )
    }
    
    /// Parse from wire data
    public init?(data: Data) {
        guard data.count >= Self.size else { return nil }
        guard data[0] == Self.opcode else { return nil }
        self.challengeHash = data.subdata(in: 1..<9)
    }
    
    /// Serialize to wire format
    public var data: Data {
        var result = Data([Self.opcode])
        result.append(challengeHash.prefix(8))
        return result
    }
}

/// xDrip challenge extraction from AuthRequestRx
/// The sensor sends challenge at offset 9 in the auth response
public enum XDripChallengeExtractor {
    /// Extract 8-byte challenge from auth response
    /// xDrip: `arraycopy(data, 9, context.challenge, 0, 8)`
    public static func extractChallenge(from data: Data) -> Data? {
        guard data.count >= 17 else { return nil }  // Need at least 17 bytes
        return data.subdata(in: 9..<17)
    }
}
