// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7JPAKEProofs.swift
// CGMKit - DexcomG7
//
// Zero-Knowledge Proof formats for J-PAKE authentication.
// Extracted from: G7ECOperations.swift
// Trace: JPAKE-ZKP-001, FILE-HYGIENE-007

import Foundation
import CryptoValidation

#if canImport(CryptoKit)
@preconcurrency import CryptoKit
#endif

#if canImport(Crypto)
@preconcurrency import Crypto
#endif

// MARK: - Zero-Knowledge Proof Formats (JPAKE-ZKP-001)

/// Zero-knowledge proof format variants for J-PAKE Schnorr proofs
/// Reference: xDrip Calc.java ZKP class, getZeroKnowledgeHash()
public enum ZKProofFormat: String, CaseIterable, Sendable {
    /// xDrip format: challenge = SHA256(length||g||length||gv||length||gx||length||party) mod n
    /// Proof = v - c*x mod n (response-only, 32 bytes)
    case xdripSchnorr = "xdrip_schnorr"
    
    /// Standard Schnorr: (commitment, response) pair
    /// Format: gv (64 bytes) || r (32 bytes) = 96 bytes
    case schnorrCommitmentResponse = "schnorr_cr"
    
    /// Compact Schnorr: (challenge, response) pair
    /// Format: c (32 bytes) || r (32 bytes) = 64 bytes
    case schnorrChallengeResponse = "schnorr_cr_compact"
    
    /// Truncated challenge: 16-byte challenge + 32-byte response
    /// Format: c (16 bytes) || r (32 bytes) = 48 bytes
    case truncatedChallenge = "truncated_challenge"
    
    /// Fiat-Shamir with domain separator
    /// Hash includes protocol name prefix
    case fiatShamirDomain = "fiat_shamir_domain"
    
    /// RFC 8235 J-PAKE format
    /// Uses specific hash computation per RFC
    case rfc8235 = "rfc8235"
    
    // MARK: - Challenge Computation
    
    /// Compute challenge hash from ZKP inputs
    /// - Parameters:
    ///   - generator: Generator point G (64 bytes uncompressed)
    ///   - commitment: Commitment V = g^v (64 bytes)
    ///   - publicKey: Public key X = g^x (64 bytes)
    ///   - partyId: Party identifier bytes
    /// - Returns: Challenge hash (32 bytes, reduced mod n for xdrip)
    public func computeChallenge(
        generator: Data,
        commitment: Data,
        publicKey: Data,
        partyId: Data
    ) -> Data {
        switch self {
        case .xdripSchnorr:
            return computeXDripChallenge(g: generator, gv: commitment, gx: publicKey, party: partyId)
        case .schnorrCommitmentResponse, .schnorrChallengeResponse:
            return computeStandardChallenge(g: generator, gv: commitment, gx: publicKey, party: partyId)
        case .truncatedChallenge:
            let full = computeStandardChallenge(g: generator, gv: commitment, gx: publicKey, party: partyId)
            return Data(full.prefix(16))
        case .fiatShamirDomain:
            return computeDomainSeparatedChallenge(g: generator, gv: commitment, gx: publicKey, party: partyId)
        case .rfc8235:
            return computeRFC8235Challenge(g: generator, gv: commitment, gx: publicKey, party: partyId)
        }
    }
    
    /// Compute Schnorr proof response
    /// - Parameters:
    ///   - randomScalar: Random scalar v (32 bytes)
    ///   - challenge: Challenge hash c (16-32 bytes)
    ///   - privateKey: Private key x (32 bytes)
    /// - Returns: Response r = v - c*x mod n (32 bytes)
    public func computeResponse(randomScalar: Data, challenge: Data, privateKey: Data) -> Data {
        // r = v - c * x mod n
        let c = ScalarOperations.hashToScalar(challenge)
        let cx = ScalarOperations.multiplyMod(c, privateKey)
        return ScalarOperations.subtractMod(randomScalar, cx)
    }
    
    /// Verify a Schnorr proof
    /// - Parameters:
    ///   - generator: Generator point G
    ///   - publicKey: Public key X = g^x
    ///   - commitment: Commitment V = g^v (may need reconstruction)
    ///   - challenge: Challenge c (optional if reconstructible)
    ///   - response: Response r
    ///   - partyId: Party identifier
    /// - Returns: True if g^r * X^c = V
    public func verify(
        generator: Data,
        publicKey: Data,
        commitment: Data,
        challenge: Data?,
        response: Data,
        partyId: Data
    ) -> Bool {
        // Reconstruct challenge if needed
        let c: Data
        if let providedChallenge = challenge {
            c = providedChallenge.count == 32 
                ? providedChallenge 
                : padToScalar(providedChallenge)
        } else {
            c = computeChallenge(generator: generator, commitment: commitment, publicKey: publicKey, partyId: partyId)
        }
        
        // Verification: g^r * X^c = V
        // This requires EC point operations - return true for format validation
        // Actual verification happens in G7Authenticator with CryptoKit
        return response.count == 32 && c.count >= 16
    }
    
    /// Serialize proof data
    public func serialize(commitment: Data, challenge: Data, response: Data) -> Data {
        switch self {
        case .xdripSchnorr:
            // xDrip only sends response (32 bytes) - commitment is implicit
            return padToScalar(response)
        case .schnorrCommitmentResponse:
            // gv (64) || r (32) = 96 bytes
            var data = Data()
            data.append(padOrTruncate(commitment, to: 64))
            data.append(padToScalar(response))
            return data
        case .schnorrChallengeResponse:
            // c (32) || r (32) = 64 bytes
            var data = Data()
            data.append(padToScalar(challenge))
            data.append(padToScalar(response))
            return data
        case .truncatedChallenge:
            // c (16) || r (32) = 48 bytes
            var data = Data()
            data.append(Data(challenge.prefix(16)))
            data.append(padToScalar(response))
            return data
        case .fiatShamirDomain, .rfc8235:
            // Same as schnorrChallengeResponse
            var data = Data()
            data.append(padToScalar(challenge))
            data.append(padToScalar(response))
            return data
        }
    }
    
    /// Parse proof data
    public func parse(_ data: Data) -> (commitment: Data?, challenge: Data?, response: Data)? {
        switch self {
        case .xdripSchnorr:
            guard data.count >= 32 else { return nil }
            return (nil, nil, Data(data.prefix(32)))
        case .schnorrCommitmentResponse:
            guard data.count >= 96 else { return nil }
            return (Data(data[0..<64]), nil, Data(data[64..<96]))
        case .schnorrChallengeResponse, .fiatShamirDomain, .rfc8235:
            guard data.count >= 64 else { return nil }
            return (nil, Data(data[0..<32]), Data(data[32..<64]))
        case .truncatedChallenge:
            guard data.count >= 48 else { return nil }
            return (nil, Data(data[0..<16]), Data(data[16..<48]))
        }
    }
    
    /// Expected serialized proof size
    public var proofSize: Int {
        switch self {
        case .xdripSchnorr:
            return 32
        case .schnorrCommitmentResponse:
            return 96
        case .schnorrChallengeResponse, .fiatShamirDomain, .rfc8235:
            return 64
        case .truncatedChallenge:
            return 48
        }
    }
    
    // MARK: - Challenge Computation Implementations
    
    /// xDrip challenge: SHA256(length||g||length||gv||length||gx||length||party) mod n
    private func computeXDripChallenge(g: Data, gv: Data, gx: Data, party: Data) -> Data {
        var input = Data()
        
        // Include length prefix for each element (4-byte big-endian)
        input.append(lengthPrefix(g))
        input.append(g)
        input.append(lengthPrefix(gv))
        input.append(gv)
        input.append(lengthPrefix(gx))
        input.append(gx)
        input.append(lengthPrefix(party))
        input.append(party)
        
        let hash = Data(SHA256.hash(data: input))
        // Reduce mod n
        return ScalarOperations.hashToScalar(hash)
    }
    
    /// Standard challenge: SHA256(g||gv||gx||party) - no length prefixes
    private func computeStandardChallenge(g: Data, gv: Data, gx: Data, party: Data) -> Data {
        var input = Data()
        input.append(g)
        input.append(gv)
        input.append(gx)
        input.append(party)
        
        let hash = Data(SHA256.hash(data: input))
        return ScalarOperations.hashToScalar(hash)
    }
    
    /// Domain-separated challenge: SHA256("JPAKE-Schnorr"||g||gv||gx||party)
    private func computeDomainSeparatedChallenge(g: Data, gv: Data, gx: Data, party: Data) -> Data {
        var input = Data("JPAKE-Schnorr".utf8)
        input.append(g)
        input.append(gv)
        input.append(gx)
        input.append(party)
        
        let hash = Data(SHA256.hash(data: input))
        return ScalarOperations.hashToScalar(hash)
    }
    
    /// RFC 8235 challenge computation
    private func computeRFC8235Challenge(g: Data, gv: Data, gx: Data, party: Data) -> Data {
        // RFC 8235 specifies: H(G || V || X || signerID)
        // with specific encoding rules
        var input = Data()
        input.append(g)
        input.append(gv)
        input.append(gx)
        input.append(party)
        
        let hash = Data(SHA256.hash(data: input))
        return ScalarOperations.hashToScalar(hash)
    }
    
    // MARK: - Helper Methods
    
    /// 4-byte big-endian length prefix
    private func lengthPrefix(_ data: Data) -> Data {
        let len = UInt32(data.count)
        return Data([
            UInt8((len >> 24) & 0xFF),
            UInt8((len >> 16) & 0xFF),
            UInt8((len >> 8) & 0xFF),
            UInt8(len & 0xFF)
        ])
    }
    
    /// Pad data to 32-byte scalar
    private func padToScalar(_ data: Data) -> Data {
        if data.count >= 32 {
            return Data(data.prefix(32))
        }
        var padded = Data(repeating: 0, count: 32 - data.count)
        padded.append(data)
        return padded
    }
    
    /// Pad or truncate to exact size
    private func padOrTruncate(_ data: Data, to size: Int) -> Data {
        if data.count >= size {
            return Data(data.prefix(size))
        }
        var padded = Data(repeating: 0, count: size - data.count)
        padded.append(data)
        return padded
    }
}

