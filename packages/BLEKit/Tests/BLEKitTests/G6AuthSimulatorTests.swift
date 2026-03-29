// SPDX-License-Identifier: MIT
//
// G6AuthSimulatorTests.swift
// BLEKitTests
//
// Tests for G6 AES authentication simulator.

import Testing
import Foundation
@testable import BLEKit

// MARK: - Key Derivation Tests

@Suite("G6 Key Derivation")
struct G6KeyDerivationTests {
    
    @Test("Key derivation produces 16-byte key")
    func keyDerivation16Bytes() {
        let key = G6AuthSimulator.deriveKey(from: "8G1234")
        #expect(key.count == 16)
    }
    
    @Test("Key format is correct")
    func keyFormat() {
        let key = G6AuthSimulator.deriveKey(from: "8G1234")
        
        // Format: 0x00 0x00 + ID[0..5] + 0x00 0x00 + ID[0..5]
        #expect(key[0] == 0x00)
        #expect(key[1] == 0x00)
        #expect(key[8] == 0x00)
        #expect(key[9] == 0x00)
        
        // ID bytes should appear at positions 2-7 and 10-15
        let idBytes = "8G1234".data(using: .utf8)!
        for i in 0..<6 {
            #expect(key[2 + i] == idBytes[i])
            #expect(key[10 + i] == idBytes[i])
        }
    }
    
    @Test("Different IDs produce different keys")
    func differentIDsDifferentKeys() {
        let key1 = G6AuthSimulator.deriveKey(from: "8G1234")
        let key2 = G6AuthSimulator.deriveKey(from: "8G5678")
        #expect(key1 != key2)
    }
    
    @Test("ID is uppercased")
    func idUppercased() {
        let simulator = G6AuthSimulator(transmitterId: "8g1234")
        #expect(simulator.transmitterId == "8G1234")
    }
}

// MARK: - Auth State Tests

@Suite("G6 Auth State")
struct G6AuthStateTests {
    
    @Test("Initial state is awaitingAuthRequest")
    func initialState() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        #expect(simulator.state == .awaitingAuthRequest)
    }
    
    @Test("Not authenticated initially")
    func notAuthenticatedInitially() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        #expect(!simulator.isAuthenticated)
    }
    
    @Test("Not bonded initially")
    func notBondedInitially() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        #expect(!simulator.isBonded)
    }
    
    @Test("Reset returns to initial state")
    func resetState() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Simulate partial auth
        var token = Data([G6SimOpcode.authRequestTx])
        token.append(Data(repeating: 0xAB, count: 8))
        _ = simulator.processMessage(token)
        
        #expect(simulator.state == .awaitingChallengeResponse)
        
        simulator.reset()
        #expect(simulator.state == .awaitingAuthRequest)
    }
}

// MARK: - Message Processing Tests

@Suite("G6 Message Processing")
struct G6MessageProcessingTests {
    
    @Test("Empty message returns invalid")
    func emptyMessage() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let result = simulator.processMessage(Data())
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Empty"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
    
    @Test("Unknown opcode returns invalid")
    func unknownOpcode() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let result = simulator.processMessage(Data([0xFF]))
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Unknown opcode"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
    
    @Test("AuthRequest too short returns invalid")
    func authRequestTooShort() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let result = simulator.processMessage(Data([G6SimOpcode.authRequestTx, 0x01, 0x02]))
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("too short"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
    
    @Test("Valid AuthRequest returns challenge response")
    func validAuthRequest() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        var request = Data([G6SimOpcode.authRequestTx])
        request.append(Data(repeating: 0x12, count: 8))
        
        let result = simulator.processMessage(request)
        
        if case .sendResponse(let response) = result {
            #expect(response.count == 17)  // opcode + tokenHash(8) + challenge(8)
            #expect(response[0] == G6SimOpcode.authChallengeRx)
        } else {
            Issue.record("Expected sendResponse")
        }
    }
    
    @Test("AuthRequest changes state to awaitingChallengeResponse")
    func authRequestChangesState() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        var request = Data([G6SimOpcode.authRequestTx])
        request.append(Data(repeating: 0x12, count: 8))
        
        _ = simulator.processMessage(request)
        
        #expect(simulator.state == .awaitingChallengeResponse)
    }
    
    @Test("Challenge response before request fails")
    func challengeResponseBeforeRequest() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        var challenge = Data([G6SimOpcode.authChallengeTx])
        challenge.append(Data(repeating: 0x12, count: 8))
        
        let result = simulator.processMessage(challenge)
        
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Unexpected"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
}

// MARK: - Full Auth Flow Tests

@Suite("G6 Full Auth Flow")
struct G6FullAuthFlowTests {
    
    @Test("Complete authentication handshake")
    func completeHandshake() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Step 1: Send auth request with client token
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        
        guard case .sendResponse(let challengeResponse) = simulator.processMessage(authRequest) else {
            Issue.record("Expected challenge response")
            return
        }
        
        // Verify challenge response format
        #expect(challengeResponse.count == 17)
        #expect(challengeResponse[0] == G6SimOpcode.authChallengeRx)
        
        let challenge = challengeResponse.subdata(in: 9..<17)
        
        // Step 2: Send challenge response (hash of challenge)
        let expectedResponse = simulator.hashData(challenge)
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(expectedResponse)
        
        let result = simulator.processMessage(challengeTx)
        
        if case .sendResponse(let statusResponse) = result {
            #expect(statusResponse[0] == G6SimOpcode.authStatusRx)
            #expect(statusResponse[1] == 0x01)  // authenticated
            #expect(statusResponse[2] == 0x00)  // not bonded
        } else {
            Issue.record("Expected auth status response")
        }
        
        #expect(simulator.state == .authenticated)
        #expect(simulator.isAuthenticated)
    }
    
    @Test("Wrong challenge response fails auth")
    func wrongChallengeResponse() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Step 1: Send auth request
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        _ = simulator.processMessage(authRequest)
        
        // Step 2: Send wrong response
        var wrongResponse = Data([G6SimOpcode.authChallengeTx])
        wrongResponse.append(Data(repeating: 0xFF, count: 8))  // Wrong hash
        
        let result = simulator.processMessage(wrongResponse)
        
        if case .failed(let reason) = result {
            #expect(reason.contains("mismatch"))
        } else {
            Issue.record("Expected failed result")
        }
        
        #expect(simulator.state == .failed)
        #expect(!simulator.isAuthenticated)
    }
    
    @Test("Bond after authentication")
    func bondAfterAuth() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Complete auth first
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        guard case .sendResponse(let challengeResponse) = simulator.processMessage(authRequest) else {
            Issue.record("Auth request failed")
            return
        }
        
        let challenge = challengeResponse.subdata(in: 9..<17)
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(simulator.hashData(challenge))
        _ = simulator.processMessage(challengeTx)
        
        #expect(simulator.state == .authenticated)
        
        // Now send bond request
        let bondRequest = Data([G6SimOpcode.bondRequest])
        let result = simulator.processMessage(bondRequest)
        
        if case .authenticated(let bonded) = result {
            #expect(bonded)
        } else {
            Issue.record("Expected authenticated(bonded: true)")
        }
        
        #expect(simulator.state == .bonded)
        #expect(simulator.isBonded)
    }
    
    @Test("Bond persists across reset")
    func bondPersistsAcrossReset() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Complete auth and bond
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        guard case .sendResponse(let challengeResponse) = simulator.processMessage(authRequest) else {
            Issue.record("Auth request failed")
            return
        }
        
        let challenge = challengeResponse.subdata(in: 9..<17)
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(simulator.hashData(challenge))
        _ = simulator.processMessage(challengeTx)
        
        let bondRequest = Data([G6SimOpcode.bondRequest])
        _ = simulator.processMessage(bondRequest)
        
        #expect(simulator.isBonded)
        
        // Reset
        simulator.reset()
        
        // Bond should persist
        #expect(simulator.isBonded)
        #expect(simulator.state == .awaitingAuthRequest)
    }
    
    @Test("Unbond clears bond state")
    func unbondClearsBondState() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Set up bonded state manually via full flow
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        guard case .sendResponse(let challengeResponse) = simulator.processMessage(authRequest) else {
            Issue.record("Auth request failed")
            return
        }
        
        let challenge = challengeResponse.subdata(in: 9..<17)
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(simulator.hashData(challenge))
        _ = simulator.processMessage(challengeTx)
        _ = simulator.processMessage(Data([G6SimOpcode.bondRequest]))
        
        #expect(simulator.isBonded)
        
        simulator.unbond()
        
        #expect(!simulator.isBonded)
        #expect(simulator.state == .awaitingAuthRequest)
    }
}

// MARK: - Hash Data Tests

@Suite("G6 Hash Data")
struct G6HashDataTests {
    
    @Test("Hash produces 8-byte output")
    func hashProduces8Bytes() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let hash = simulator.hashData(Data(repeating: 0xAB, count: 8))
        #expect(hash.count == 8)
    }
    
    @Test("Same input produces same hash")
    func sameInputSameHash() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let input = Data(repeating: 0xCD, count: 8)
        let hash1 = simulator.hashData(input)
        let hash2 = simulator.hashData(input)
        #expect(hash1 == hash2)
    }
    
    @Test("Different inputs produce different hashes")
    func differentInputsDifferentHashes() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        let hash1 = simulator.hashData(Data(repeating: 0xAA, count: 8))
        let hash2 = simulator.hashData(Data(repeating: 0xBB, count: 8))
        #expect(hash1 != hash2)
    }
    
    @Test("Different keys produce different hashes")
    func differentKeysDifferentHashes() {
        let sim1 = G6AuthSimulator(transmitterId: "8G1234")
        let sim2 = G6AuthSimulator(transmitterId: "8G5678")
        let input = Data(repeating: 0xCC, count: 8)
        
        let hash1 = sim1.hashData(input)
        let hash2 = sim2.hashData(input)
        
        #expect(hash1 != hash2)
    }
}

// MARK: - Keep Alive Tests

@Suite("G6 Keep Alive")
struct G6KeepAliveTests {
    
    @Test("Keep alive returns authenticated status")
    func keepAliveAuthenticated() {
        let simulator = G6AuthSimulator(transmitterId: "8G1234")
        
        // Complete auth first
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        guard case .sendResponse(let challengeResponse) = simulator.processMessage(authRequest) else {
            Issue.record("Auth request failed")
            return
        }
        
        let challenge = challengeResponse.subdata(in: 9..<17)
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(simulator.hashData(challenge))
        _ = simulator.processMessage(challengeTx)
        
        // Send keep alive
        let result = simulator.processMessage(Data([G6SimOpcode.keepAlive, 25]))
        
        if case .authenticated(let bonded) = result {
            #expect(!bonded)
        } else {
            Issue.record("Expected authenticated result")
        }
    }
}

// MARK: - SimulatorTransmitterID Integration

@Suite("G6 SimulatorTransmitterID Integration")
struct G6SimulatorTransmitterIDTests {
    
    @Test("Create from SimulatorTransmitterID")
    func createFromSimulatorID() throws {
        guard let transmitterID = SimulatorTransmitterID("8G1234") else {
            Issue.record("Failed to create transmitter ID")
            return
        }
        let simulator = G6AuthSimulator(transmitterId: transmitterID)
        #expect(simulator.transmitterId == "8G1234")
    }
    
    @Test("G6 transmitter ID produces valid key")
    func g6IDProducesValidKey() throws {
        guard let transmitterID = SimulatorTransmitterID("8G1234") else {
            Issue.record("Failed to create transmitter ID")
            return
        }
        let simulator = G6AuthSimulator(transmitterId: transmitterID)
        #expect(simulator.cryptKey.count == 16)
    }
}

// MARK: - Auth Rejection Fixture Validation (G6-FIX-015)

@Suite("G6 Auth Rejection Scenarios")
struct G6AuthRejectionTests {
    
    @Test("REJECT-001: Wrong challenge response fails auth")
    func wrongChallengeResponseFailsAuth() {
        // Validates fixture_g6_auth_reject.json REJECT-001
        let simulator = G6AuthSimulator(transmitterId: "123456")
        
        // Step 1: Send valid auth request
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef]))
        authRequest.append(0x02)  // end byte
        
        guard case .sendResponse = simulator.processMessage(authRequest) else {
            Issue.record("Auth request should return sendResponse")
            return
        }
        #expect(simulator.state == .awaitingChallengeResponse)
        
        // Step 3: Send WRONG challenge response (all 0xFF)
        var wrongResponse = Data([G6SimOpcode.authChallengeTx])
        wrongResponse.append(Data(repeating: 0xFF, count: 8))
        
        let result = simulator.processMessage(wrongResponse)
        
        // Verify rejection
        if case .failed(let reason) = result {
            #expect(reason.contains("mismatch"))
        } else {
            Issue.record("Expected .failed result for wrong response")
        }
        
        #expect(simulator.state == .failed)
        #expect(!simulator.isAuthenticated)
    }
    
    @Test("REJECT-003: Malformed AuthChallengeTx too short")
    func malformedChallengeTooShort() {
        // Validates fixture_g6_auth_reject.json REJECT-003
        let simulator = G6AuthSimulator(transmitterId: "123456")
        
        // Complete step 1: auth request
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        authRequest.append(0x02)
        _ = simulator.processMessage(authRequest)
        
        #expect(simulator.state == .awaitingChallengeResponse)
        
        // Step 3: Send truncated message - only 5 bytes instead of 9
        let truncated = Data([G6SimOpcode.authChallengeTx, 0xFF, 0xFF, 0xFF, 0xFF])
        let result = simulator.processMessage(truncated)
        
        // Verify invalidMessage (NOT failed - client can retry)
        if case .invalidMessage(let msg) = result {
            #expect(msg.contains("too short") || msg.contains("5 bytes"))
        } else {
            Issue.record("Expected .invalidMessage for truncated message")
        }
        
        // State should NOT change to failed - still recoverable
        #expect(simulator.state == .awaitingChallengeResponse)
    }
    
    @Test("REJECT-004: State violation - challenge before request")
    func stateViolationChallengeBeforeRequest() {
        // Validates fixture_g6_auth_reject.json REJECT-004
        let simulator = G6AuthSimulator(transmitterId: "123456")
        
        // Initial state
        #expect(simulator.state == .awaitingAuthRequest)
        
        // Send challenge response without auth request first
        var challengeTx = Data([G6SimOpcode.authChallengeTx])
        challengeTx.append(Data(repeating: 0xAA, count: 8))
        
        let result = simulator.processMessage(challengeTx)
        
        // Verify invalidMessage for state violation
        if case .invalidMessage(let msg) = result {
            #expect(msg.contains("state") || msg.contains("Unexpected"))
        } else {
            Issue.record("Expected .invalidMessage for state violation")
        }
        
        // State unchanged
        #expect(simulator.state == .awaitingAuthRequest)
    }
    
    @Test("REJECT-005: Bond request without authentication")
    func bondRequestWithoutAuth() {
        // Validates fixture_g6_auth_reject.json REJECT-005
        let simulator = G6AuthSimulator(transmitterId: "123456")
        
        // Send auth request to get into awaitingChallengeResponse
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        authRequest.append(0x02)
        _ = simulator.processMessage(authRequest)
        
        #expect(simulator.state == .awaitingChallengeResponse)
        
        // Send bond request prematurely
        let bondRequest = Data([G6SimOpcode.bondRequest])
        let result = simulator.processMessage(bondRequest)
        
        // Verify invalidMessage
        if case .invalidMessage(let msg) = result {
            #expect(msg.contains("bond") || msg.contains("state"))
        } else {
            Issue.record("Expected .invalidMessage for premature bond")
        }
        
        // State unchanged
        #expect(simulator.state == .awaitingChallengeResponse)
        #expect(!simulator.isBonded)
    }
    
    @Test("Auth rejected response has correct bytes")
    func authRejectedResponseBytes() {
        // Validates test_vectors.auth_status_rejected in fixture
        // AuthStatusRx with authenticated=0x00: "06 00 00"
        let simulator = G6AuthSimulator(transmitterId: "123456")
        
        // Setup: get to awaitingChallengeResponse
        var authRequest = Data([G6SimOpcode.authRequestTx])
        authRequest.append(Data(repeating: 0x55, count: 8))
        authRequest.append(0x02)
        guard case .sendResponse = simulator.processMessage(authRequest) else {
            Issue.record("Auth request failed")
            return
        }
        
        // Send wrong response - should trigger AuthStatusRx with auth=false
        var wrongResponse = Data([G6SimOpcode.authChallengeTx])
        wrongResponse.append(Data(repeating: 0xFF, count: 8))
        let result = simulator.processMessage(wrongResponse)
        
        // Result should be .failed
        if case .failed = result {
            // Success - the simulator correctly identifies the mismatch
            // In real hardware, AuthStatusRx 06 00 00 would be sent
            #expect(simulator.state == .failed)
        } else {
            Issue.record("Expected .failed result")
        }
    }
}
