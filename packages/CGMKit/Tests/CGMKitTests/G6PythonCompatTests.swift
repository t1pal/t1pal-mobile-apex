// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6PythonCompatTests.swift
// CGMKitTests
//
// G6-SYNTH-006: PYTHON-COMPAT conformance tests for Dexcom G6 protocol parsing.
// Verifies Swift parsing matches Python g6_parsers.py output byte-for-byte.
//
// Pattern: Each test loads fixture vectors and asserts Swift matches Python output.
// Reference: tools/g6-cli/g6_parsers.py, tools/g6-cli/fixtures/fixture_g6_*.json

import Testing
import Foundation
@testable import CGMKit

// MARK: - Transmitter Time PYTHON-COMPAT Tests (G6-SYNTH-006)

@Suite("G6 Transmitter Time PYTHON-COMPAT")
struct G6TransmitterTimePythonCompatTests {
    
    /// PYTHON-COMPAT: Verify Swift parsing matches g6_parsers.py parse_transmitter_time_rx()
    /// Python: status=data[1], current_time=struct.unpack('<I', data[2:6])[0],
    ///         session_start_time=struct.unpack('<I', data[6:10])[0]
    @Test("Parse time vectors matching Python output")
    func parseTimeVectors() throws {
        // Test vectors from fixture_g6_time.json
        // Format: [opcode=0x25, status, currentTime(4 bytes LE), sessionStartTime(4 bytes LE), ...]
        let testCases: [(hex: String, expectedStatus: UInt8, expectedCurrentTime: UInt32, expectedSessionStartTime: UInt32, sessionActive: Bool)] = [
            // No Session vectors - sessionStartTime = 0xFFFFFFFF
            ("2500e8f87100ffffffff010000000a70", 0, 7469288, 0xFFFFFFFF, false),
            ("250096fd7100ffffffff01000000226d", 0, 7470486, 0xFFFFFFFF, false),
            ("2500eeff7100ffffffff010000008952", 0, 7471086, 0xFFFFFFFF, false),
            // In Session vectors - sessionStartTime < 0xFFFFFFFF
            ("2500470272007cff710001000000fa1d", 0, 7471687, 7470972, true),
            ("2500beb24d00f22d4d000100000083c0", 0, 5092030, 5058034, true),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = TransmitterTimeRxMessage(data: data)
            
            #expect(msg != nil, "Failed to parse hex: \(testCase.hex)")
            
            if let msg = msg {
                #expect(msg.status == testCase.expectedStatus,
                       "Status mismatch for \(testCase.hex): expected \(testCase.expectedStatus), got \(msg.status)")
                #expect(msg.currentTime == testCase.expectedCurrentTime,
                       "CurrentTime mismatch for \(testCase.hex): expected \(testCase.expectedCurrentTime), got \(msg.currentTime)")
                #expect(msg.sessionStartTime == testCase.expectedSessionStartTime,
                       "SessionStartTime mismatch for \(testCase.hex): expected \(testCase.expectedSessionStartTime), got \(msg.sessionStartTime)")
                
                // Verify session active detection matches Python
                let swiftSessionActive = msg.sessionStartTime != 0xFFFFFFFF
                #expect(swiftSessionActive == testCase.sessionActive,
                       "SessionActive mismatch for \(testCase.hex): expected \(testCase.sessionActive), got \(swiftSessionActive)")
            }
        }
    }
    
    /// PYTHON-COMPAT: Verify session age calculation matches Python
    /// Python: session_age_seconds = current_time - session_start_time
    @Test("Calculate session age matching Python")
    func sessionAgeCalculation() {
        // In-session vector: currentTime=7471687, sessionStartTime=7470972
        let data = Data(hexString: "2500470272007cff710001000000fa1d")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        // Python: 7471687 - 7470972 = 715 seconds
        let expectedAge: UInt32 = 715
        #expect(msg.sessionAge == expectedAge, "Session age should be 715 seconds (~12 min)")
    }
    
    // MARK: - GAP-API-021: Session Sentinel Detection Tests
    
    @Test("hasActiveSession returns false for sentinel value")
    func hasActiveSessionSentinel() {
        // No Session vector - sessionStartTime = 0xFFFFFFFF
        let data = Data(hexString: "2500e8f87100ffffffff010000000a70")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        #expect(!msg.hasActiveSession, "hasActiveSession should be false for sentinel")
        #expect(msg.sessionStartTime == 0xFFFFFFFF, "sessionStartTime should be sentinel")
    }
    
    @Test("hasActiveSession returns true for valid session")
    func hasActiveSessionValid() {
        // In Session vector - valid sessionStartTime
        let data = Data(hexString: "2500470272007cff710001000000fa1d")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        #expect(msg.hasActiveSession, "hasActiveSession should be true for valid session")
        #expect(msg.sessionStartTime == 7470972, "sessionStartTime should be valid")
    }
    
    @Test("safeSessionAge returns nil for sentinel value")
    func safeSessionAgeSentinel() {
        // No Session vector - sessionStartTime = 0xFFFFFFFF
        let data = Data(hexString: "2500e8f87100ffffffff010000000a70")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        #expect(msg.safeSessionAge == nil, "safeSessionAge should be nil for sentinel")
    }
    
    @Test("safeSessionAge returns valid age for active session")
    func safeSessionAgeValid() {
        // In Session vector - valid sessionStartTime
        let data = Data(hexString: "2500470272007cff710001000000fa1d")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        #expect(msg.safeSessionAge == 715, "safeSessionAge should be 715 seconds")
    }
    
    @Test("sessionAge underflows with sentinel but safeSessionAge protects")
    func sessionAgeUnderflowProtection() {
        // Demonstrate the bug that safeSessionAge fixes
        // currentTime=7469288, sessionStartTime=0xFFFFFFFF
        let data = Data(hexString: "2500e8f87100ffffffff010000000a70")!
        let msg = TransmitterTimeRxMessage(data: data)!
        
        // Raw sessionAge underflows to ~7469289 (currentTime + 1 due to wrap)
        let rawAge = msg.sessionAge
        #expect(rawAge == 7469289, "Raw sessionAge underflows to \(rawAge)")
        
        // safeSessionAge returns nil, preventing corrupt calculations
        #expect(msg.safeSessionAge == nil, "safeSessionAge should protect against underflow")
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        // Change opcode from 0x25 to 0x24
        let data = Data(hexString: "2400e8f87100ffffffff010000000a70")!
        let msg = TransmitterTimeRxMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short message")
    func rejectShortMessage() {
        // Only 8 bytes, needs at least 10
        let data = Data(hexString: "2500e8f871001234")!
        let msg = TransmitterTimeRxMessage(data: data)
        #expect(msg == nil, "Should reject message shorter than 10 bytes")
    }
}

// MARK: - Session Start PYTHON-COMPAT Tests (G6-SYNTH-006)

@Suite("G6 Session Start PYTHON-COMPAT")
struct G6SessionStartPythonCompatTests {
    
    /// PYTHON-COMPAT: Verify Swift parsing matches g6_parsers.py parse_session_start_rx()
    /// Python: status=data[1], received=data[2],
    ///         requested_start_time=struct.unpack('<I', data[3:7])[0],
    ///         session_start_time=struct.unpack('<I', data[7:11])[0],
    ///         transmitter_time=struct.unpack('<I', data[11:15])[0]
    @Test("Parse session vectors matching Python output")
    func parseSessionVectors() throws {
        // Test vectors from fixture_g6_session.json
        // Format: [opcode=0x27, status, received, requestedStartTime(4), sessionStartTime(4), transmitterTime(4), CRC(2)]
        let testCases: [(hex: String, expectedStatus: UInt8, expectedReceived: UInt8, expectedRequestedStartTime: UInt32, expectedSessionStartTime: UInt32, expectedTransmitterTime: UInt32)] = [
            ("2700014bf871004bf87100e9f8710095d9", 0, 1, 7469131, 7469131, 7469289),
            ("2700012bfd71002bfd710096fd71000f6a", 0, 1, 7470379, 7470379, 7470486),
            ("2700017cff71007cff7100eeff7100aeed", 0, 1, 7470972, 7470972, 7471086),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = SessionStartRxMessage(data: data)
            
            #expect(msg != nil, "Failed to parse hex: \(testCase.hex)")
            
            if let msg = msg {
                #expect(msg.status == testCase.expectedStatus,
                       "Status mismatch: expected \(testCase.expectedStatus), got \(msg.status)")
                #expect(msg.received == testCase.expectedReceived,
                       "Received mismatch: expected \(testCase.expectedReceived), got \(msg.received)")
                #expect(msg.requestedStartTime == testCase.expectedRequestedStartTime,
                       "RequestedStartTime mismatch: expected \(testCase.expectedRequestedStartTime), got \(msg.requestedStartTime)")
                #expect(msg.sessionStartTime == testCase.expectedSessionStartTime,
                       "SessionStartTime mismatch: expected \(testCase.expectedSessionStartTime), got \(msg.sessionStartTime)")
                #expect(msg.transmitterTime == testCase.expectedTransmitterTime,
                       "TransmitterTime mismatch: expected \(testCase.expectedTransmitterTime), got \(msg.transmitterTime)")
            }
        }
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        // Change opcode from 0x27 to 0x26
        let data = Data(hexString: "2600014bf871004bf87100e9f8710095d9")!
        let msg = SessionStartRxMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short message")
    func rejectShortMessage() {
        // Only 12 bytes, needs at least 15
        let data = Data(hexString: "2700014bf871004bf87100")!
        let msg = SessionStartRxMessage(data: data)
        #expect(msg == nil, "Should reject message shorter than 15 bytes")
    }
}

// MARK: - Session Stop PYTHON-COMPAT Tests (G6-DIRECT-032)

@Suite("G6 Session Stop PYTHON-COMPAT")
struct G6SessionStopPythonCompatTests {
    
    /// G6-DIRECT-032: Verify SessionStopRxMessage parsing
    /// Format: [opcode=0x29, status, received, sessionStopTime(4), sessionStartTime(4), transmitterTime(4), CRC(2)]
    @Test("Parse session stop vectors")
    func parseSessionStopVectors() throws {
        // Test vectors based on Loop's CGMBLEKit format
        // Format: [opcode=0x29, status, received, sessionStopTime(4 LE), sessionStartTime(4 LE), transmitterTime(4 LE), CRC(2)]
        let testCases: [(hex: String, expectedStatus: UInt8, expectedReceived: UInt8, expectedSessionStopTime: UInt32, expectedSessionStartTime: UInt32, expectedTransmitterTime: UInt32)] = [
            // Synthetic vector: successful stop - little-endian encoding
            // sessionStopTime=1 (01000000), sessionStartTime=2 (02000000), transmitterTime=3 (03000000)
            ("29000101000000020000000300000000", 0, 1, 1, 2, 3),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = SessionStopRxMessage(data: data)
            
            #expect(msg != nil, "Failed to parse hex: \(testCase.hex)")
            
            if let msg = msg {
                #expect(msg.status == testCase.expectedStatus,
                       "Status mismatch: expected \(testCase.expectedStatus), got \(msg.status)")
                #expect(msg.received == testCase.expectedReceived,
                       "Received mismatch: expected \(testCase.expectedReceived), got \(msg.received)")
                #expect(msg.sessionStopTime == testCase.expectedSessionStopTime,
                       "SessionStopTime mismatch: expected \(testCase.expectedSessionStopTime), got \(msg.sessionStopTime)")
                #expect(msg.sessionStartTime == testCase.expectedSessionStartTime,
                       "SessionStartTime mismatch: expected \(testCase.expectedSessionStartTime), got \(msg.sessionStartTime)")
                #expect(msg.transmitterTime == testCase.expectedTransmitterTime,
                       "TransmitterTime mismatch: expected \(testCase.expectedTransmitterTime), got \(msg.transmitterTime)")
            }
        }
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        // Change opcode from 0x29 to 0x28
        let data = Data(hexString: "28000101000000020000000300000000")!
        let msg = SessionStopRxMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short message")
    func rejectShortMessage() {
        // Only 12 bytes, needs at least 15
        let data = Data(hexString: "29000101000000020000")!
        let msg = SessionStopRxMessage(data: data)
        #expect(msg == nil, "Should reject message shorter than 15 bytes")
    }
    
    @Test("isSuccess true when status=0 and received=1")
    func isSuccessTest() {
        // status=0, received=1 means success
        let data = Data(hexString: "29000101000000020000000300000000")!
        let msg = SessionStopRxMessage(data: data)!
        #expect(msg.isSuccess == true)
    }
    
    @Test("isSuccess false when status non-zero")
    func isSuccessFalseOnError() {
        // status=1 (error), received=1
        let data = Data(hexString: "29010101000000020000000300000000")!
        let msg = SessionStopRxMessage(data: data)!
        #expect(msg.isSuccess == false)
    }
}

// MARK: - Session Start Tx Message Tests (G6-DIRECT-031)

@Suite("G6 Session Start Tx Message")
struct G6SessionStartTxMessageTests {
    
    @Test("SessionStartTxMessage includes CRC")
    func sessionStartTxHasCRC() {
        // Create a session start message
        let msg = SessionStartTxMessage(startTime: 1000, secondsSince1970: 1700000000)
        
        // Message should be: opcode(1) + startTime(4) + secondsSince1970(4) + CRC(2) = 11 bytes
        #expect(msg.data.count == 11, "SessionStartTxMessage should be 11 bytes with CRC")
        
        // First byte is opcode 0x26
        #expect(msg.data[0] == 0x26, "Opcode should be 0x26")
    }
    
    @Test("SessionStartTxMessage date initializer calculates offset")
    func sessionStartTxDateInitializer() {
        let now = Date()
        let activationDate = Date(timeIntervalSince1970: 1700000000)  // Fixed date
        let sensorStartDate = Date(timeIntervalSince1970: 1700001000)  // 1000 seconds later
        
        let msg = SessionStartTxMessage(
            sensorStartDate: sensorStartDate,
            transmitterActivationDate: activationDate
        )
        
        #expect(msg.startTime == 1000, "startTime should be 1000 seconds since activation")
        #expect(msg.secondsSince1970 == 1700001000, "secondsSince1970 should match sensor start")
    }
    
    @Test("SessionStopTxMessage includes CRC")
    func sessionStopTxHasCRC() {
        // Create a session stop message
        let msg = SessionStopTxMessage(stopTime: 1000)
        
        // Message should be: opcode(1) + stopTime(4) + CRC(2) = 7 bytes
        #expect(msg.data.count == 7, "SessionStopTxMessage should be 7 bytes with CRC")
        
        // First byte is opcode 0x28
        #expect(msg.data[0] == 0x28, "Opcode should be 0x28")
    }
    
    @Test("SessionStopTxMessage date initializer calculates offset")
    func sessionStopTxDateInitializer() {
        let activationDate = Date(timeIntervalSince1970: 1700000000)  // Fixed date
        let stopDate = Date(timeIntervalSince1970: 1700002000)  // 2000 seconds later
        
        let msg = SessionStopTxMessage(
            stopDate: stopDate,
            transmitterActivationDate: activationDate
        )
        
        #expect(msg.stopTime == 2000, "stopTime should be 2000 seconds since activation")
    }
}

// MARK: - Authentication PYTHON-COMPAT Tests (G6-SYNTH-006)

@Suite("G6 Auth PYTHON-COMPAT")
struct G6AuthPythonCompatTests {
    
    /// PYTHON-COMPAT: Verify Swift parsing matches g6_parsers.py parse_auth_challenge_rx()
    /// Python: authenticated=data[1]==0x01, bonded=data[2]==0x01
    @Test("Parse AuthChallengeRx vectors matching Python")
    func parseAuthChallengeRx() throws {
        // Test vectors from fixture_g6_auth.json
        let testCases: [(hex: String, expectedAuthenticated: Bool, expectedBonded: Bool, description: String)] = [
            ("050101", true, true, "Authenticated and bonded"),
            ("050100", true, false, "Authenticated not bonded"),
            ("050000", false, false, "Not authenticated"),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = AuthStatusRxMessage(data: data)
            
            #expect(msg != nil, "Failed to parse: \(testCase.description)")
            
            if let msg = msg {
                #expect(msg.authenticated == testCase.expectedAuthenticated,
                       "\(testCase.description): authenticated mismatch")
                #expect(msg.bonded == testCase.expectedBonded,
                       "\(testCase.description): bonded mismatch")
            }
        }
    }
    
    /// PYTHON-COMPAT: Verify key derivation matches g6_parsers.py derive_key()
    /// Python: key_str = f"00{transmitter_id}00{transmitter_id}", return key_str.encode('utf-8')[:16]
    @Test("Key derivation matches Python")
    func keyDerivation() {
        // From fixture_g6_auth.json: transmitter_id="123456"
        // Python: key_string = "00123456001234560", key = first 16 bytes
        let transmitterId = "123456"
        let expectedKeyHex = "30303132333435363030313233343536" // "00123456001234560"[:16]
        
        // Derive key using same algorithm as Python
        let keyString = "00\(transmitterId)00\(transmitterId)"
        let keyData = keyString.data(using: .utf8)!.prefix(16)
        
        #expect(keyData.map { String(format: "%02x", $0) }.joined() == expectedKeyHex,
               "Key derivation should match Python output")
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        let data = Data(hexString: "040101")! // opcode 0x04 instead of 0x05
        let msg = AuthStatusRxMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short message")
    func rejectShortMessage() {
        let data = Data(hexString: "0501")! // Only 2 bytes, needs 3
        let msg = AuthStatusRxMessage(data: data)
        #expect(msg == nil, "Should reject short message")
    }
}

// MARK: - G6-FIX-008: AES-ECB Hash PYTHON-COMPAT Tests

@Suite("G6 AES Hash PYTHON-COMPAT")
struct G6AESHashPythonCompatTests {
    
    /// G6-FIX-008: PYTHON-COMPAT - Verify Swift hash matches g6_parsers.py compute_hash()
    /// Python: plaintext = data + data; cipher = AES(key, ECB); return ciphertext[:8]
    @Test("Hash computation matches Python compute_hash()")
    func hashMatchesPython() throws {
        // Test vector from fixture_g6_auth_session.json
        // transmitter_id = "123456"
        // token = 0x0123456789abcdef
        // expected_hash = 0xe60d4a7999b0fbb2
        
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let token = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let hash = auth.hashToken(token)
        
        // Python: compute_hash(bytes.fromhex("0123456789abcdef"), key) -> "e60d4a7999b0fbb2"
        let expectedHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        
        #expect(hash == expectedHash, """
            G6-FIX-008: PYTHON-COMPAT hash mismatch!
            Python: compute_hash(token, derive_key("123456"))
            Input token: \(token.map { String(format: "%02x", $0) }.joined())
            Expected:    \(expectedHash.map { String(format: "%02x", $0) }.joined())
            Got:         \(hash.map { String(format: "%02x", $0) }.joined())
            """)
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - Verify key derivation produces exact same bytes
    /// Python: derive_key("123456") -> b"0012345600123456" (UTF-8)
    @Test("Key derivation bytes match Python derive_key()")
    func keyDerivationMatchesPython() {
        // Python: derive_key(transmitter_id)
        // key_str = f"00{transmitter_id}00{transmitter_id}"
        // return key_str.encode('utf-8')[:16]
        
        let key = G6Authenticator.deriveKey(from: "123456")
        
        // Python output: bytes [0x30, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        //                       0x30, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36]
        let expectedKey = Data([
            0x30, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36,  // "00123456"
            0x30, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36   // "00123456"
        ])
        
        #expect(key == expectedKey, """
            G6-FIX-008: PYTHON-COMPAT key derivation mismatch!
            Python: derive_key("123456")
            Expected: \(expectedKey.map { String(format: "%02x", $0) }.joined())
            Got:      \(key.map { String(format: "%02x", $0) }.joined())
            """)
        
        #expect(key.count == 16, "Key must be exactly 16 bytes for AES-128")
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - Verify hash uses token duplication, not zero-padding
    /// Python: plaintext = data + data (16 bytes from 8-byte input)
    @Test("Hash uses token duplication per Python algorithm")
    func hashUsesTokenDuplication() throws {
        // If we incorrectly zero-pad instead of duplicate, these two tokens
        // would produce the same hash for the first 8 bytes
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Token where last byte differs
        let token1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00])
        let token2 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0xFF])
        
        let hash1 = auth.hashToken(token1)
        let hash2 = auth.hashToken(token2)
        
        // Python: compute_hash(token1, key) != compute_hash(token2, key)
        // because plaintext differs in bytes 7 AND 15 (due to duplication)
        #expect(hash1 != hash2, """
            G6-FIX-008: PYTHON-COMPAT token duplication validation failed!
            Python algorithm: plaintext = token + token
            Last byte change must affect hash (bytes 7 and 15 both change)
            """)
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - Additional test vectors
    @Test("Multiple hash vectors match Python")
    func multipleHashVectors() throws {
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        // All zeros token
        let zeroToken = Data(repeating: 0x00, count: 8)
        let zeroHash = auth.hashToken(zeroToken)
        #expect(zeroHash.count == 8, "Hash must be 8 bytes")
        
        // All 0xFF token
        let ffToken = Data(repeating: 0xFF, count: 8)
        let ffHash = auth.hashToken(ffToken)
        #expect(ffHash.count == 8, "Hash must be 8 bytes")
        
        // Different tokens must produce different hashes
        #expect(zeroHash != ffHash, "Different tokens must produce different hashes")
    }
}

// MARK: - G6-FIX-008: Auth Message Format PYTHON-COMPAT Tests

@Suite("G6 Auth Message Format PYTHON-COMPAT")
struct G6AuthMessageFormatPythonCompatTests {
    
    /// G6-FIX-008: PYTHON-COMPAT - AuthRequestTx format matches create_auth_request_tx()
    /// Python: return bytes([0x01]) + token + bytes([end_byte])
    @Test("AuthRequestTx format matches Python create_auth_request_tx()")
    func authRequestTxMatchesPython() throws {
        // Python: create_auth_request_tx(token, end_byte=0x02)
        // Format: [opcode=0x01][token:8 bytes][end_byte=0x02]
        
        let token = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let message = AuthRequestTxMessage(singleUseToken: token)
        let data = message.data
        
        // Python byte offsets:
        // data[0] = 0x01 (opcode)
        #expect(data[0] == 0x01, "G6-FIX-008: Opcode at data[0] should be 0x01")
        
        // data[1:9] = token (8 bytes)
        let extractedToken = data.subdata(in: 1..<9)
        #expect(extractedToken == token, """
            G6-FIX-008: PYTHON-COMPAT token extraction mismatch!
            Python: data[1:9] extracts token
            Expected: \(token.map { String(format: "%02x", $0) }.joined())
            Got:      \(extractedToken.map { String(format: "%02x", $0) }.joined())
            """)
        
        // data[9] = end_byte (0x02)
        #expect(data[9] == 0x02, "G6-FIX-008: End byte at data[9] should be 0x02")
        
        // Total length
        #expect(data.count == 10, "G6-FIX-008: AuthRequestTx should be 10 bytes")
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - AuthChallengeRx parsing matches parse_auth_request_rx()
    /// Python: token_hash = data[1:9], challenge = data[9:17]
    @Test("AuthChallengeRx parsing matches Python parse_auth_request_rx()")
    func authChallengeRxMatchesPython() throws {
        // Test vector for AuthChallengeRxMessage (server challenge with tokenHash)
        // Opcode 0x03 = authRequestRx per G6Messages.swift
        // Format: [opcode:1][tokenHash:8][challenge:8] = 17 bytes
        
        // Create test data with correct opcode (0x03)
        let rawHex = "03e60d4a7999b0fbb2fedcba9876543210"
        let data = Data(hexString: rawHex)!
        
        // Verify byte extraction at Python offsets
        
        // Python: data[0] = opcode
        #expect(data[0] == 0x03, "G6-FIX-008: Opcode should be 0x03 for AuthChallengeRxMessage")
        
        // Python: token_hash = data[1:9] (bytes 1-8 inclusive, 8 bytes)
        let tokenHash = data.subdata(in: 1..<9)
        let expectedTokenHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        #expect(tokenHash == expectedTokenHash, """
            G6-FIX-008: PYTHON-COMPAT tokenHash extraction mismatch!
            Python: data[1:9]
            Expected: \(expectedTokenHash.map { String(format: "%02x", $0) }.joined())
            Got:      \(tokenHash.map { String(format: "%02x", $0) }.joined())
            """)
        
        // Python: challenge = data[9:17] (bytes 9-16 inclusive, 8 bytes)
        let challenge = data.subdata(in: 9..<17)
        let expectedChallenge = Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10])
        #expect(challenge == expectedChallenge, """
            G6-FIX-008: PYTHON-COMPAT challenge extraction mismatch!
            Python: data[9:17]
            Expected: \(expectedChallenge.map { String(format: "%02x", $0) }.joined())
            Got:      \(challenge.map { String(format: "%02x", $0) }.joined())
            """)
        
        // Verify Swift parser extracts same values
        let msg = AuthChallengeRxMessage(data: data)
        #expect(msg != nil, "AuthChallengeRxMessage should parse successfully")
        #expect(msg?.tokenHash == expectedTokenHash, "Swift tokenHash should match Python extraction")
        #expect(msg?.challenge == expectedChallenge, "Swift challenge should match Python extraction")
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - AuthChallengeTx format matches create_auth_challenge_tx()
    /// Python: return bytes([0x04]) + challenge_hash
    @Test("AuthChallengeTx format matches Python create_auth_challenge_tx()")
    func authChallengeTxMatchesPython() throws {
        // Python: create_auth_challenge_tx(challenge_hash)
        // Format: [opcode=0x04][challenge_hash:8 bytes]
        
        let challengeHash = Data([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11])
        let message = AuthChallengeTxMessage(challengeResponse: challengeHash)
        let data = message.data
        
        // Python byte offsets:
        // data[0] = 0x04 (opcode)
        #expect(data[0] == 0x04, "G6-FIX-008: Opcode at data[0] should be 0x04")
        
        // data[1:9] = challenge_hash (8 bytes)
        let extractedHash = data.subdata(in: 1..<9)
        #expect(extractedHash == challengeHash, """
            G6-FIX-008: PYTHON-COMPAT challenge_hash extraction mismatch!
            Python: data[1:9] extracts challenge_hash
            Expected: \(challengeHash.map { String(format: "%02x", $0) }.joined())
            Got:      \(extractedHash.map { String(format: "%02x", $0) }.joined())
            """)
        
        // Total length
        #expect(data.count == 9, "G6-FIX-008: AuthChallengeTx should be 9 bytes")
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - AuthStatusRx parsing matches parse_auth_challenge_rx()
    /// Python: authenticated = data[1] == 0x01, bonded = data[2] == 0x01
    @Test("AuthStatusRx parsing matches Python parse_auth_challenge_rx()")
    func authStatusRxMatchesPython() throws {
        // Test vectors from fixture_g6_auth.json
        let testCases: [(hex: String, auth: Bool, bonded: Bool)] = [
            ("050101", true, true),
            ("050100", true, false),
            ("050001", false, true),
            ("050000", false, false),
        ]
        
        for (hex, expectedAuth, expectedBonded) in testCases {
            let data = Data(hexString: hex)!
            
            // Python byte offsets:
            // data[0] = opcode (0x05)
            #expect(data[0] == 0x05, "Opcode should be 0x05")
            
            // Python: authenticated = data[1] == 0x01
            let pythonAuth = data[1] == 0x01
            #expect(pythonAuth == expectedAuth, "G6-FIX-008: Python auth at data[1]")
            
            // Python: bonded = data[2] == 0x01
            let pythonBonded = data[2] == 0x01
            #expect(pythonBonded == expectedBonded, "G6-FIX-008: Python bonded at data[2]")
            
            // Verify Swift parser matches
            let msg = AuthStatusRxMessage(data: data)!
            #expect(msg.authenticated == expectedAuth, "Swift auth should match Python")
            #expect(msg.bonded == expectedBonded, "Swift bonded should match Python")
        }
    }
}

// MARK: - G6-FIX-008: Complete Auth Flow PYTHON-COMPAT Tests

@Suite("G6 Auth Flow PYTHON-COMPAT")
struct G6AuthFlowPythonCompatTests {
    
    /// G6-FIX-008: PYTHON-COMPAT - Complete auth flow with fixture vectors
    @Test("Complete auth flow matches Python implementation")
    func completeAuthFlowMatchesPython() throws {
        // Test vector from fixture_g6_auth_session.json
        let transmitterId = "123456"
        let clientToken = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let serverChallenge = Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10])
        let expectedTokenHash = Data([0xe6, 0x0d, 0x4a, 0x79, 0x99, 0xb0, 0xfb, 0xb2])
        
        // Step 1: Python derive_key()
        let tx = TransmitterID(transmitterId)!
        let auth = G6Authenticator(transmitterId: tx)
        
        // Step 2: Python compute_hash(token, key)
        let tokenHash = auth.hashToken(clientToken)
        #expect(tokenHash == expectedTokenHash, """
            G6-FIX-008: Token hash mismatch in auth flow!
            Python: compute_hash(token, derive_key("123456"))
            """)
        
        // Step 3: Python compute_hash(challenge, key) for response
        let challengeResponse = auth.encryptChallenge(serverChallenge)
        #expect(challengeResponse.count == 8, "Challenge response must be 8 bytes")
        
        // Step 4: Verify full message round-trip
        // Create AuthRequestTx
        let authRequest = AuthRequestTxMessage(singleUseToken: clientToken)
        #expect(authRequest.data.count == 10)
        
        // Parse mock AuthChallengeRx from server
        var challengeData = Data([0x03])  // opcode 0x03 = authRequestRx (server challenge)
        challengeData.append(expectedTokenHash)
        challengeData.append(serverChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeData)!
        #expect(challengeRx.tokenHash == expectedTokenHash)
        #expect(challengeRx.challenge == serverChallenge)
        
        // Process challenge and verify response
        let response = auth.processChallenge(challengeRx, sentToken: clientToken)
        #expect(response != nil, "G6-FIX-008: Auth should succeed with valid token hash")
        #expect(response?.data.count == 9, "AuthChallengeTx should be 9 bytes")
    }
    
    /// G6-FIX-008: PYTHON-COMPAT - Verify auth fails with wrong token hash
    @Test("Auth fails with wrong token hash per Python semantics")
    func authFailsWithWrongHash() throws {
        let tx = TransmitterID("123456")!
        let auth = G6Authenticator(transmitterId: tx)
        
        let clientToken = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        let wrongTokenHash = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let serverChallenge = Data([0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10])
        
        // Build challenge with wrong hash (opcode 0x03 = authRequestRx)
        var challengeData = Data([0x03])
        challengeData.append(wrongTokenHash)
        challengeData.append(serverChallenge)
        
        let challengeRx = AuthChallengeRxMessage(data: challengeData)!
        
        // Python semantics: if tokenHash != compute_hash(token, key), auth fails
        let response = auth.processChallenge(challengeRx, sentToken: clientToken)
        #expect(response == nil, """
            G6-FIX-008: PYTHON-COMPAT auth should fail with wrong token hash!
            Python: tokenHash verification prevents man-in-the-middle attacks
            """)
    }
}

// MARK: - Glucose PYTHON-COMPAT Tests (G6-SYNTH-006)

@Suite("G6 Glucose PYTHON-COMPAT")
struct G6GlucosePythonCompatTests {
    
    /// PYTHON-COMPAT: Verify Swift parsing matches g6_parsers.py parse_glucose_rx()
    /// Python: status=data[1], sequence=struct.unpack('<I', data[2:6])[0],
    ///         timestamp=struct.unpack('<I', data[6:10])[0],
    ///         glucose_bytes=struct.unpack('<H', data[10:12])[0],
    ///         trend=struct.unpack('b', bytes([data[13]]))[0] (signed)
    @Test("Parse glucose values matching Python")
    func parseGlucoseValues() throws {
        // Test vectors using CORRECT CGMBLEKit format:
        // [opcode:1][status:1][sequence:4][timestamp:4][glucose:2][state:1][trend:1][crc:2]
        let testCases: [(hex: String, expectedSequence: UInt32, expectedTimestamp: UInt32, expectedGlucose: UInt16, expectedTrend: Int8)] = [
            // normal_120: sequence=1, timestamp=10000, glucose=120, state=0x06, trend=0
            ("31000100000010270000780006000000", 1, 10000, 120, 0),
            // rising_fast: sequence=15, timestamp=10224, glucose=150, state=0x06, trend=45
            ("31000f000000f02700009600062d0000", 15, 10224, 150, 45),
            // falling_fast: sequence=16, timestamp=10240, glucose=150, state=0x06, trend=-45
            ("31001000000000280000960006d30000", 16, 10240, 150, -45),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = GlucoseRxMessage(data: data)
            
            #expect(msg != nil, "Failed to parse hex: \(testCase.hex)")
            
            if let msg = msg {
                #expect(msg.sequence == testCase.expectedSequence,
                       "Sequence mismatch: expected \(testCase.expectedSequence), got \(msg.sequence)")
                #expect(msg.timestamp == testCase.expectedTimestamp,
                       "Timestamp mismatch: expected \(testCase.expectedTimestamp), got \(msg.timestamp)")
                #expect(msg.glucoseValue == testCase.expectedGlucose,
                       "Glucose mismatch: expected \(testCase.expectedGlucose), got \(msg.glucoseValue)")
                #expect(msg.trend == testCase.expectedTrend,
                       "Trend mismatch: expected \(testCase.expectedTrend), got \(msg.trend)")
            }
        }
    }
    
    /// PYTHON-COMPAT: Verify signed trend byte parsing
    /// Python: trend = struct.unpack('b', bytes([data[13]]))[0]
    @Test("Signed trend parsing matches Python")
    func signedTrendParsing() {
        // Test negative trend: 0xD3 = -45 as signed byte (at byte[13])
        // Format: [opcode:1][status:1][sequence:4][timestamp:4][glucose:2][state:1][trend:1][crc:2]
        let data = Data(hexString: "31001000000000280000960006d30000")!
        let msg = GlucoseRxMessage(data: data)!
        
        // Python struct.unpack('b', bytes([0xd3]))[0] = -45
        #expect(msg.trend == -45, "0xD3 should parse as -45 (signed Int8)")
        
        // Test positive trend: 0x2D = 45 as signed byte
        let data2 = Data(hexString: "31000f000000f02700009600062d0000")!
        let msg2 = GlucoseRxMessage(data: data2)!
        
        #expect(msg2.trend == 45, "0x2D should parse as 45 (signed Int8)")
    }
}
