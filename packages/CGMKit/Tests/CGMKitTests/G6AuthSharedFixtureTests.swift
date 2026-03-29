// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6AuthSharedFixtureTests.swift
// CGMKitTests
//
// PY-SWIFT-010: Shared fixture validation for G6 authentication.
// Tests Swift G6Authenticator against the same JSON fixtures used by Python g6-auth.py.
//
// Trace: PY-SWIFT-010
// Fixture: Fixtures/g6auth/test-vectors.json
// Python: tools/g6-cli/g6-auth.py --test

import Testing
import Foundation
@testable import CGMKit

// MARK: - Fixture Models

struct G6AuthFixture: Decodable {
    let keyDerivation: [KeyDerivationVector]
    let tokenHash: [TokenHashVector]
    let messageEncoding: [MessageEncodingVector]
    
    struct KeyDerivationVector: Decodable {
        let description: String
        let transmitterId: String
        let expectedKeyHex: String
        let expectedKeyString: String
    }
    
    struct TokenHashVector: Decodable {
        let description: String
        let transmitterId: String
        let tokenHex: String
        let expectedHashHex: String
    }
    
    struct MessageEncodingVector: Decodable {
        let description: String
        let tokenHex: String?
        let expectedMessageHex: String?
        let messageHex: String?
        let expectedTokenHash: String?
        let expectedChallenge: String?
        let expectedAuthenticated: Bool?
        let expectedBonded: Bool?
    }
}

// MARK: - Shared Fixture Tests

@Suite("G6 Auth Shared Fixture Tests (PY-SWIFT-010)")
struct G6AuthSharedFixtureTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G6AuthFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "test-vectors", withExtension: "json", subdirectory: "Fixtures/g6auth") else {
            throw TestError("Fixture not found: Fixtures/g6auth/test-vectors.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(G6AuthFixture.self, from: data)
    }
    
    struct TestError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
    
    // MARK: - Key Derivation Tests (Python: derive_key)
    
    @Test("Key derivation matches Python derive_key()")
    func keyDerivationMatchesPython() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.keyDerivation {
            let key = G6Authenticator.deriveKey(from: vector.transmitterId)
            let keyHex = key.map { String(format: "%02x", $0) }.joined()
            
            #expect(keyHex == vector.expectedKeyHex.lowercased(),
                """
                Key derivation mismatch for '\(vector.transmitterId)'
                Description: \(vector.description)
                Expected: \(vector.expectedKeyHex)
                Got:      \(keyHex)
                
                Python: derive_key('\(vector.transmitterId)') should match
                """)
        }
    }
    
    // MARK: - Token Hash Tests (Python: compute_hash)
    
    @Test("Token hash matches Python compute_hash()")
    func tokenHashMatchesPython() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.tokenHash {
            let tx = TransmitterID(vector.transmitterId)!
            let auth = G6Authenticator(transmitterId: tx)
            
            // Parse token from hex
            let token = Data(hexString: vector.tokenHex)!
            let hash = auth.hashToken(token)
            let hashHex = hash.map { String(format: "%02x", $0) }.joined()
            
            #expect(hashHex == vector.expectedHashHex.lowercased(),
                """
                Token hash mismatch for '\(vector.transmitterId)'
                Description: \(vector.description)
                Token:    \(vector.tokenHex)
                Expected: \(vector.expectedHashHex)
                Got:      \(hashHex)
                
                Python: compute_hash('\(vector.transmitterId)', '\(vector.tokenHex)') should match
                """)
        }
    }
    
    // MARK: - Message Encoding Tests (Python: create_auth_request_tx, parse_auth_*)
    
    @Test("AuthRequestTx encoding matches Python")
    func authRequestTxMatchesPython() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.messageEncoding {
            guard let tokenHex = vector.tokenHex,
                  let expectedHex = vector.expectedMessageHex else { continue }
            
            let token = Data(hexString: tokenHex)!
            let message = AuthRequestTxMessage(singleUseToken: token)
            let messageHex = message.data.map { String(format: "%02x", $0) }.joined()
            
            #expect(messageHex == expectedHex.lowercased(),
                """
                AuthRequestTx encoding mismatch
                Description: \(vector.description)
                Token:    \(tokenHex)
                Expected: \(expectedHex)
                Got:      \(messageHex)
                
                Python: create_auth_request_tx('\(tokenHex)') should match
                """)
        }
    }
    
    @Test("AuthChallengeRxMessage parsing matches Python AuthRequestRx")
    func authChallengeRxMatchesPython() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.messageEncoding {
            guard let messageHex = vector.messageHex,
                  let expectedTokenHash = vector.expectedTokenHash,
                  let expectedChallenge = vector.expectedChallenge else { continue }
            
            // Process fixture's "AuthRequestRx" (opcode 0x03) using our AuthChallengeRxMessage
            // Fixed: AuthChallengeRxMessage now correctly expects opcode 0x03 (authRequestRx)
            guard messageHex.hasPrefix("03") else { continue }
            
            let data = Data(hexString: messageHex)!
            let parsed = AuthChallengeRxMessage(data: data)
            
            #expect(parsed != nil, "Failed to parse AuthChallengeRxMessage: \(messageHex)")
            
            if let parsed = parsed {
                let tokenHashHex = parsed.tokenHash.map { String(format: "%02x", $0) }.joined()
                let challengeHex = parsed.challenge.map { String(format: "%02x", $0) }.joined()
                
                #expect(tokenHashHex == expectedTokenHash.lowercased(),
                    "TokenHash mismatch for \(messageHex)")
                #expect(challengeHex == expectedChallenge.lowercased(),
                    "Challenge mismatch for \(messageHex)")
            }
        }
    }
    
    @Test("AuthStatusRx parsing matches Python")
    func authStatusRxMatchesPython() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.messageEncoding {
            guard let messageHex = vector.messageHex,
                  let expectedAuth = vector.expectedAuthenticated,
                  let expectedBonded = vector.expectedBonded else { continue }
            
            // Only process AuthStatusRx messages (opcode 0x05)
            // Note: CGMBLEKit calls this AuthChallengeRxMessage, we call it AuthStatusRxMessage
            guard messageHex.hasPrefix("05") else { continue }
            
            let data = Data(hexString: messageHex)!
            let parsed = AuthStatusRxMessage(data: data)
            
            #expect(parsed != nil, "Failed to parse AuthStatusRx: \(messageHex)")
            
            if let parsed = parsed {
                #expect(parsed.authenticated == expectedAuth,
                    """
                    Authenticated mismatch for \(messageHex)
                    Description: \(vector.description)
                    Expected: \(expectedAuth)
                    Got:      \(parsed.authenticated)
                    """)
                #expect(parsed.bonded == expectedBonded,
                    """
                    Bonded mismatch for \(messageHex)
                    Description: \(vector.description)
                    Expected: \(expectedBonded)
                    Got:      \(parsed.bonded)
                    """)
            }
        }
    }
    
    // MARK: - Cross-Validation Summary
    
    @Test("Fixture coverage summary")
    func fixtureCoverageSummary() throws {
        let fixture = try Self.loadFixture()
        
        // Report coverage
        let keyVectors = fixture.keyDerivation.count
        let hashVectors = fixture.tokenHash.count
        let msgVectors = fixture.messageEncoding.count
        
        #expect(keyVectors >= 3, "Should have at least 3 key derivation vectors")
        #expect(hashVectors >= 1, "Should have at least 1 token hash vector")
        #expect(msgVectors >= 5, "Should have at least 5 message encoding vectors")
        
        // This test documents that fixture is being used
        print("""
            G6 Auth Shared Fixture Coverage:
            - Key derivation vectors: \(keyVectors)
            - Token hash vectors: \(hashVectors)
            - Message encoding vectors: \(msgVectors)
            
            Python validation: tools/g6-cli/g6-auth.py --test
            Swift validation: swift test --filter G6AuthSharedFixtureTests
            """)
    }
}
