// SPDX-License-Identifier: MIT
//
// G6AuthenticatorTests.swift
// CGMKitTests
//
// Unit tests for Dexcom G6 AES authentication.

import Testing
import Foundation
@testable import CGMKit

@Suite("G6Authenticator Tests")
struct G6AuthenticatorTests {
    
    @Test("Key derivation from transmitter ID")
    func keyDerivation() {
        // CGMBLEKit format: "00" + id + "00" + id as UTF-8 string
        // "00" is ASCII '0' '0' (0x30 0x30), NOT null bytes
        let key = G6Authenticator.deriveKey(from: "80AB12")
        
        #expect(key.count == 16)
        // "0080AB120080AB12" as UTF-8
        #expect(key[0] == 0x30)  // '0'
        #expect(key[1] == 0x30)  // '0'
        #expect(key[2] == 0x38)  // '8'
        #expect(key[3] == 0x30)  // '0'
        #expect(key[4] == 0x41)  // 'A'
        #expect(key[5] == 0x42)  // 'B'
        #expect(key[6] == 0x31)  // '1'
        #expect(key[7] == 0x32)  // '2'
        #expect(key[8] == 0x30)  // '0'
        #expect(key[9] == 0x30)  // '0'
        #expect(key[10] == 0x38) // '8'
    }
    
    @Test("Authenticator initialization")
    func initialization() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        #expect(auth.transmitterId == tx)
        #expect(auth.cryptKey.count == 16)
    }
    
    @Test("Token generation is random")
    func tokenGeneration() {
        let token1 = G6Authenticator.generateToken()
        let token2 = G6Authenticator.generateToken()
        
        #expect(token1.count == 8)
        #expect(token2.count == 8)
        #expect(token1 != token2)  // Very unlikely to be equal
    }
    
    @Test("Auth request creation")
    func authRequestCreation() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let (message, token) = auth.createAuthRequest()
        
        // CGMBLEKit format: opcode(1) + token(8) + endByte(1) = 10 bytes
        #expect(message.data.count == 10)
        #expect(message.data[0] == G6Opcode.authRequestTx.rawValue)
        #expect(message.data[9] == 0x02)  // End byte
        #expect(token.count == 8)
    }
    
    @Test("Token hashing produces consistent results")
    func tokenHashing() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let hash1 = auth.hashToken(token)
        let hash2 = auth.hashToken(token)
        
        #expect(hash1.count == 8)
        #expect(hash1 == hash2)
    }
    
    @Test("Different tokens produce different hashes")
    func differentTokensDifferentHashes() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let token2 = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])
        
        let hash1 = auth.hashToken(token1)
        let hash2 = auth.hashToken(token2)
        
        #expect(hash1 != hash2)
    }
    
    @Test("Different transmitters produce different hashes")
    func differentTransmittersDifferentHashes() {
        let tx1 = TransmitterID("80AB12")!
        let tx2 = TransmitterID("81CD34")!
        
        let auth1 = G6Authenticator(transmitterId: tx1)
        let auth2 = G6Authenticator(transmitterId: tx2)
        
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        let hash1 = auth1.hashToken(token)
        let hash2 = auth2.hashToken(token)
        
        #expect(hash1 != hash2)
    }
    
    @Test("Challenge encryption produces consistent results")
    func challengeEncryption() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let challenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        let response1 = auth.encryptChallenge(challenge)
        let response2 = auth.encryptChallenge(challenge)
        
        #expect(response1.count == 8)
        #expect(response1 == response2)
    }
    
    @Test("Process challenge with valid token hash")
    func processChallengeValid() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Simulate the flow
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let expectedHash = auth.hashToken(token)
        let challenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        // Build a mock challenge response (opcode 0x03 = authRequestRx)
        var challengeData = Data([G6Opcode.authRequestRx.rawValue])
        challengeData.append(expectedHash)
        challengeData.append(challenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeData)!
        
        let response = auth.processChallenge(challengeRx, sentToken: token)
        
        #expect(response != nil)
        #expect(response?.data.count == 9)
    }
    
    @Test("Process challenge with invalid token hash")
    func processChallengeInvalid() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let wrongHash = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let challenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        var challengeData = Data([G6Opcode.authRequestRx.rawValue])  // 0x03 - server challenge
        challengeData.append(wrongHash)
        challengeData.append(challenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeData)!
        
        let response = auth.processChallenge(challengeRx, sentToken: token)
        
        #expect(response == nil)
    }
}

@Suite("AES-128-ECB Tests")
struct AESTests {
    
    @Test("AES encryption is reversible in key space")
    func aesConsistency() {
        // Same input with same key should produce same output
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let data1 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        let data2 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        
        let enc1 = auth.encryptChallenge(data1)
        let enc2 = auth.encryptChallenge(data2)
        
        #expect(enc1 == enc2)
    }
    
    @Test("AES produces non-trivial output")
    func aesNonTrivial() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let encrypted = auth.encryptChallenge(data)
        
        // Encrypted data should not be all zeros
        #expect(encrypted != Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }
    
    @Test("Key derivation is deterministic")
    func keyDerivationDeterministic() {
        let key1 = G6Authenticator.deriveKey(from: "80AB12")
        let key2 = G6Authenticator.deriveKey(from: "80AB12")
        
        #expect(key1 == key2)
    }
    
    @Test("Different IDs produce different keys")
    func differentIdsDifferentKeys() {
        let key1 = G6Authenticator.deriveKey(from: "80AB12")
        let key2 = G6Authenticator.deriveKey(from: "81CD34")
        
        #expect(key1 != key2)
    }
    
    // MARK: - G6+ (Firefly) Format Flexibility Tests
    
    @Test("G6+ auth request uses opcode 0x02")
    func g6PlusAuthRequestOpcode() {
        let tx = TransmitterID("8GAB12")!  // G6+ (Firefly) ID
        #expect(tx.generation == .g6Plus)
        
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest()
        
        // G6+ should use opcode 0x02 (authRequest2Tx)
        #expect(message.data[0] == G6Opcode.authRequest2Tx.rawValue)
        #expect(message.data[0] == 0x02)
    }
    
    @Test("G6 auth request uses opcode 0x01")
    func g6AuthRequestOpcode() {
        let tx = TransmitterID("80AB12")!  // Standard G6 ID
        #expect(tx.generation == .g6)
        
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest()
        
        // Standard G6 should use opcode 0x01 (authRequestTx)
        #expect(message.data[0] == G6Opcode.authRequestTx.rawValue)
        #expect(message.data[0] == 0x01)
    }
    
    @Test("AuthRequestTxMessage with generation parameter")
    func authRequestMessageGeneration() {
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        // G6 generation
        let g6Message = AuthRequestTxMessage(singleUseToken: token, generation: .g6)
        #expect(g6Message.opcode == 0x01)
        
        // G6+ generation
        let g6PlusMessage = AuthRequestTxMessage(singleUseToken: token, generation: .g6Plus)
        #expect(g6PlusMessage.opcode == 0x02)
        
        // G5 falls back to G6 opcode
        let g5Message = AuthRequestTxMessage(singleUseToken: token, generation: .g5)
        #expect(g5Message.opcode == 0x01)
    }
    
    // MARK: - App Level Key Authentication Tests
    // Trace: CGM-065, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    
    @Test("App Level Key authenticator uses provided key")
    func appLevelKeyAuthenticator() {
        let tx = TransmitterID("80AB12")!
        let appKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let auth = G6Authenticator(transmitterId: tx, appLevelKey: appKey)
        
        #expect(auth.cryptKey == appKey)
        #expect(auth.usingAppLevelKey == true)
    }
    
    @Test("App Level Key auth always uses opcode 0x02")
    func appLevelKeyAuthOpcode() {
        // Even for standard G6 (not Firefly), App Level Key auth uses opcode 0x02
        let tx = TransmitterID("80AB12")!
        #expect(tx.generation == .g6)  // Standard G6
        
        let appKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let auth = G6Authenticator(transmitterId: tx, appLevelKey: appKey)
        let (message, _) = auth.createAuthRequest()
        
        // App Level Key auth should use opcode 0x02 regardless of generation
        #expect(message.data[0] == G6Opcode.authRequest2Tx.rawValue)
        #expect(message.data[0] == 0x02)
    }
    
    @Test("Standard auth does not use App Level Key")
    func standardAuthNotAppLevelKey() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        #expect(auth.usingAppLevelKey == false)
        // Standard auth derives key from TX ID
        #expect(auth.cryptKey == G6Authenticator.deriveKey(from: tx.id))
    }
    
    @Test("App Level Key auth produces valid challenge response")
    func appLevelKeyAuthChallenge() {
        let tx = TransmitterID("80AB12")!
        let appKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let auth = G6Authenticator(transmitterId: tx, appLevelKey: appKey)
        let (_, token) = auth.createAuthRequest()
        
        // Verify token hash is computed with the App Level Key
        let expectedHash = auth.hashToken(token)
        #expect(expectedHash.count == 8)
        
        // Create a challenge that would verify correctly
        var challengeData = Data([G6Opcode.authRequestRx.rawValue])
        challengeData.append(expectedHash)
        challengeData.append(Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])) // challenge
        
        let challenge = AuthChallengeRxMessage(data: challengeData)!
        let response = auth.processChallenge(challenge, sentToken: token)
        
        // Should succeed with matching token hash
        #expect(response != nil)
    }
    
    // MARK: - G6-VALIDATE-004: Full Auth Flow Simulation
    
    @Test("G6-VALIDATE-004: Full auth flow simulation - success path")
    func fullAuthFlowSuccess() {
        // Simulate complete G6 authentication flow without hardware
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Phase 1: Create auth request
        let (request, token) = auth.createAuthRequest()
        #expect(request.data.count > 0, "Auth request should have data")
        #expect(token.count == 8, "Token should be 8 bytes")
        
        // Phase 2: Simulate transmitter response with correct token hash
        let expectedHash = auth.hashToken(token)
        let simulatedChallenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        var challengeRxData = Data([G6Opcode.authRequestRx.rawValue])
        challengeRxData.append(expectedHash)
        challengeRxData.append(simulatedChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeRxData)!
        
        // Phase 3: Process challenge and create response
        let responseTx = auth.processChallenge(challengeRx, sentToken: token)
        #expect(responseTx != nil, "Should produce response for valid challenge")
        
        // Phase 4: Verify response format
        let responseData = responseTx!.data
        #expect(responseData.count == 9, "Challenge response should be 9 bytes (opcode + 8)")
        #expect(responseData[0] == G6Opcode.authChallengeTx.rawValue)
        
        // Verify the encrypted challenge is deterministic
        let expectedResponse = auth.encryptChallenge(simulatedChallenge)
        #expect(responseData.dropFirst() == expectedResponse, "Encrypted response should match")
    }
    
    @Test("G6-VALIDATE-004: Full auth flow simulation - token hash mismatch")
    func fullAuthFlowTokenMismatch() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Create auth request
        let (_, token) = auth.createAuthRequest()
        
        // Simulate transmitter with WRONG token hash (attacker scenario)
        let wrongHash = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        let simulatedChallenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        var challengeRxData = Data([G6Opcode.authRequestRx.rawValue])
        challengeRxData.append(wrongHash)
        challengeRxData.append(simulatedChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeRxData)!
        
        // Should reject - token hash doesn't match
        let responseTx = auth.processChallenge(challengeRx, sentToken: token)
        #expect(responseTx == nil, "Should reject challenge with wrong token hash")
    }
    
    @Test("G6-VALIDATE-004: Auth flow with G6 vs G6+ opcodes")
    func authFlowOpcodeSelection() {
        // G6 (4-char prefix like "80") uses authRequestTx (0x01)
        let txG6 = TransmitterID("80AB12")!
        let authG6 = G6Authenticator(transmitterId: txG6)
        let (requestG6, _) = authG6.createAuthRequest()
        #expect(requestG6.data[0] == G6Opcode.authRequestTx.rawValue, "G6 should use 0x01")
        
        // G6+ (4-char prefix like "8G") uses authRequest2Tx (0x02)
        let txG6Plus = TransmitterID("8GAB12")!
        let authG6Plus = G6Authenticator(transmitterId: txG6Plus)
        let (requestG6Plus, _) = authG6Plus.createAuthRequest()
        #expect(requestG6Plus.data[0] == G6Opcode.authRequest2Tx.rawValue, "G6+ should use 0x02")
    }
    
    @Test("G6-VALIDATE-004: Auth flow with App Level Key")
    func authFlowAppLevelKey() {
        let tx = TransmitterID("80AB12")!
        let appLevelKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                                 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let auth = G6Authenticator(transmitterId: tx, appLevelKey: appLevelKey)
        let (request, token) = auth.createAuthRequest()
        
        // App Level Key auth always uses 0x02 regardless of transmitter generation
        #expect(request.data[0] == G6Opcode.authRequest2Tx.rawValue)
        
        // Simulate correct challenge-response with app level key
        let expectedHash = auth.hashToken(token)
        let simulatedChallenge = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        
        var challengeRxData = Data([G6Opcode.authRequestRx.rawValue])
        challengeRxData.append(expectedHash)
        challengeRxData.append(simulatedChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeRxData)!
        let responseTx = auth.processChallenge(challengeRx, sentToken: token)
        
        #expect(responseTx != nil, "Should succeed with App Level Key")
        
        // Verify the response uses the App Level Key for encryption
        let expectedResponse = auth.encryptChallenge(simulatedChallenge)
        #expect(responseTx!.data.dropFirst() == expectedResponse)
    }
}

// MARK: - CGM-046: Slot Selection Tests

@Suite("G6 Slot Selection Tests")
struct G6SlotSelectionTests {
    
    @Test("Default slot is consumer (coexistence-friendly)")
    func defaultSlotIsConsumer() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest()
        
        // Default is consumer slot (0x02) for coexistence mode
        // Auth request format: opcode(1) + token(8) + slot(1) = 10 bytes
        #expect(message.data.count == 10)
        #expect(message.data[9] == G6Slot.consumer.rawValue)
        #expect(message.data[9] == 0x02)
    }
    
    @Test("Explicit medical slot")
    func explicitMedicalSlot() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest(slot: .medical)
        
        #expect(message.data[9] == 0x01)
    }
    
    @Test("Consumer slot selection")
    func consumerSlot() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest(slot: .consumer)
        
        // Consumer slot is 0x02
        #expect(message.data[9] == G6Slot.consumer.rawValue)
        #expect(message.data[9] == 0x02)
    }
    
    @Test("Wearable slot selection")
    func wearableSlot() {
        let tx = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: tx)
        let (message, _) = auth.createAuthRequest(slot: .wearable)
        
        // Wearable slot is 0x03 (G7/Firefly+ coexistence)
        #expect(message.data[9] == G6Slot.wearable.rawValue)
        #expect(message.data[9] == 0x03)
    }
    
    @Test("Slot selection with App Level Key")
    func slotWithAppLevelKey() {
        let tx = TransmitterID("80AB12")!
        let appKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        let auth = G6Authenticator(transmitterId: tx, appLevelKey: appKey)
        let (message, _) = auth.createAuthRequest(slot: .wearable)
        
        // Should use opcode 0x02 (App Level Key) AND wearable slot
        #expect(message.data[0] == G6Opcode.authRequest2Tx.rawValue)
        #expect(message.data[9] == G6Slot.wearable.rawValue)
    }
    
    @Test("AuthRequestTxMessage slot encoding")
    func authRequestTxMessageSlot() {
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        // Medical slot
        let medicalMsg = AuthRequestTxMessage(singleUseToken: token, generation: .g6, slot: .medical)
        #expect(medicalMsg.data.last == 0x01)
        
        // Consumer slot  
        let consumerMsg = AuthRequestTxMessage(singleUseToken: token, generation: .g6, slot: .consumer)
        #expect(consumerMsg.data.last == 0x02)
        
        // Wearable slot
        let wearableMsg = AuthRequestTxMessage(singleUseToken: token, generation: .g6, slot: .wearable)
        #expect(wearableMsg.data.last == 0x03)
    }
    
    @Test("Slot display names")
    func slotDisplayNames() {
        #expect(G6Slot.medical.displayName == "Medical")
        #expect(G6Slot.consumer.displayName == "Consumer")
        #expect(G6Slot.wearable.displayName == "Wearable")
    }
}
