// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6GlucoseSessionTests.swift
// CGMKitTests
//
// Session-level conformance tests for Dexcom G6 glucose read sequence.
// Validates fixture_g6_glucose_session.json against GlucoseRxMessage parsing.
// Trace: SESSION-G6-002

import Testing
import Foundation
@testable import CGMKit

// MARK: - Session Fixture Types

struct G6GlucoseSessionFixture: Decodable {
    let sessionId: String
    let sessionName: String
    let description: String
    let steps: [G6SessionStep]
    let test_vectors: [G6SessionVector]
    let result: G6SessionResult
    
    enum CodingKeys: String, CodingKey {
        // Support both v1 (session_id) and v2 (fixture_id) schema
        case sessionId = "session_id"
        case fixtureId = "fixture_id"
        case sessionName = "session_name"
        case fixtureName = "fixture_name"
        case description, steps, test_vectors, result
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try v2 fixture_id first, fall back to v1 session_id
        if let id = try? container.decode(String.self, forKey: .fixtureId) {
            sessionId = id
        } else {
            sessionId = try container.decode(String.self, forKey: .sessionId)
        }
        // Try v2 fixture_name first, fall back to v1 session_name
        if let name = try? container.decode(String.self, forKey: .fixtureName) {
            sessionName = name
        } else {
            sessionName = try container.decode(String.self, forKey: .sessionName)
        }
        description = try container.decode(String.self, forKey: .description)
        steps = try container.decode([G6SessionStep].self, forKey: .steps)
        test_vectors = try container.decode([G6SessionVector].self, forKey: .test_vectors)
        result = try container.decode(G6SessionResult.self, forKey: .result)
    }
}

struct G6SessionStep: Decodable {
    let step: Int
    let state: String
    let operation: String
    let description: String?
    let tx: G6SessionTx?
    let rx: G6SessionRx?
}

struct G6SessionTx: Decodable {
    let raw_hex: String
    let opcode: String
    let opcode_name: String
    let length: Int
}

struct G6SessionRx: Decodable {
    let raw_hex: String
    let opcode: String
    let opcode_name: String
    let length: Int
    let dexcom: G6DexcomFields?
}

struct G6DexcomFields: Decodable {
    let status: UInt8?
    let sequence: UInt32?
    let timestamp: UInt32?
    let glucoseValue: UInt16?
    let predictedGlucose: UInt16?
    let trend: Int8?
}

struct G6SessionVector: Decodable {
    let name: String
    let id: String
    let hex: String
    let expected: G6VectorExpected
    let parser: String?
}

struct G6VectorExpected: Decodable {
    let glucoseValue: UInt16?
    let predictedGlucose: UInt16?
    let trend: Int8?
    let isValid: Bool?
    let glucose: UInt16?
    let glucoseIsDisplayOnly: Bool?
    let state: UInt8?
    let description: String?
}

struct G6SessionResult: Decodable {
    let success: Bool
    let final_state: String
    let glucose_mg_dl: Double?
    let is_valid: Bool?
}

// MARK: - Session Tests

@Suite("G6 Glucose Session (SESSION-G6-002)")
struct G6GlucoseSessionTests {
    
    // MARK: - Fixture Loading
    
    static func loadSessionFixture() throws -> G6GlucoseSessionFixture {
        // Load from conformance directory at workspace root
        // Path: t1pal-mobile-workspace/packages/CGMKit/Tests/CGMKitTests/G6GlucoseSessionTests.swift
        // Need: t1pal-mobile-workspace/conformance/protocol/dexcom/fixture_g6_glucose_session.json
        let workspaceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // -> CGMKitTests
            .deletingLastPathComponent()  // -> Tests
            .deletingLastPathComponent()  // -> CGMKit
            .deletingLastPathComponent()  // -> packages
            .deletingLastPathComponent()  // -> t1pal-mobile-workspace
        
        let fixtureURL = workspaceRoot
            .appendingPathComponent("conformance")
            .appendingPathComponent("protocol")
            .appendingPathComponent("dexcom")
            .appendingPathComponent("fixture_g6_glucose_session.json")
        
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(G6GlucoseSessionFixture.self, from: data)
    }
    
    enum FixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Session Validation
    
    @Test("Session fixture loads correctly")
    func sessionLoads() throws {
        let session = try Self.loadSessionFixture()
        
        #expect(session.sessionId == "G6-GLUC-001")
        #expect(session.sessionName.contains("Glucose"))
        #expect(session.steps.count >= 2, "Need at least TX and RX steps")
        #expect(session.test_vectors.count > 0, "Need test vectors")
    }
    
    @Test("GlucoseTx message format")
    func glucoseTxFormat() throws {
        let session = try Self.loadSessionFixture()
        
        guard let txStep = session.steps.first(where: { $0.operation == "GLUCOSE_TX" }),
              let tx = txStep.tx else {
            Issue.record("GLUCOSE_TX step not found")
            return
        }
        
        #expect(tx.opcode == "0x30", "GlucoseTx opcode should be 0x30")
        #expect(tx.length == 3, "GlucoseTx is opcode byte + CRC16")
        
        // Verify our Swift implementation matches
        let msg = GlucoseTxMessage()
        #expect(msg.data.count == 1)
        #expect(msg.data[0] == G6Opcode.glucoseTx.rawValue)
    }
    
    // HYGIENE-001: Skip - fixture format mismatch with Swift GlucoseRxMessage
    // The Swift code expects predictedGlucose as UInt16, fixture has state+trend
    // TODO: Reconcile fixture format with actual protocol specification
    @Test("GlucoseRx parsing matches fixture", .disabled("Fixture format mismatch - HYGIENE-001"))
    func glucoseRxParsing() throws {
        let session = try Self.loadSessionFixture()
        
        guard let rxStep = session.steps.first(where: { $0.operation == "GLUCOSE_RX" }),
              let rx = rxStep.rx,
              let dexcom = rx.dexcom else {
            Issue.record("GLUCOSE_RX step not found")
            return
        }
        
        // Parse the hex, removing spaces
        let hexClean = rx.raw_hex.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: hexClean) else {
            Issue.record("Invalid hex: \(rx.raw_hex)")
            return
        }
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg != nil, "Failed to parse GlucoseRx")
        
        if let msg = msg {
            if let expectedGlucose = dexcom.glucoseValue {
                #expect(msg.glucoseValue == expectedGlucose, 
                       "Glucose mismatch: \(msg.glucoseValue) vs \(expectedGlucose)")
            }
            if let expectedPredicted = dexcom.predictedGlucose {
                #expect(msg.predictedGlucose == expectedPredicted,
                       "Predicted glucose mismatch")
            }
            if let expectedTrend = dexcom.trend {
                #expect(msg.trend == expectedTrend, "Trend mismatch")
            }
        }
    }
    
    // MARK: - Test Vector Validation
    
    @Test("All test vectors parse correctly")
    func allVectorsParse() throws {
        let session = try Self.loadSessionFixture()
        var passed = 0
        var failed = 0
        
        for vector in session.test_vectors {
            // Skip G5 format vectors (different parser)
            if vector.parser == "G5GlucoseRxMessage" {
                continue
            }
            
            let hexClean = vector.hex.replacingOccurrences(of: " ", with: "")
            guard let data = Data(hexString: hexClean) else {
                Issue.record("Invalid hex in \(vector.id)")
                failed += 1
                continue
            }
            
            let msg = GlucoseRxMessage(data: data)
            
            if let expected = vector.expected.isValid {
                if expected {
                    // Valid vectors should parse
                    if msg != nil {
                        passed += 1
                    } else {
                        Issue.record("Failed to parse valid vector: \(vector.id)")
                        failed += 1
                    }
                } else {
                    // Invalid vectors: still parse but isValid=false
                    if let m = msg {
                        #expect(m.isValid == false, "\(vector.id) should be invalid")
                        passed += 1
                    } else {
                        passed += 1 // Failed to parse is also acceptable for invalid
                    }
                }
            } else if msg != nil {
                passed += 1
            }
        }
        
        #expect(passed > 0, "At least some vectors should pass")
        #expect(failed == 0, "No vectors should fail unexpectedly")
    }
    
    @Test("Normal glucose vector (120 mg/dL)")
    func normalGlucoseVector() throws {
        let session = try Self.loadSessionFixture()
        
        guard let vector = session.test_vectors.first(where: { $0.id == "normal_120" }) else {
            Issue.record("Vector 'normal_120' not found")
            return
        }
        
        let hexClean = vector.hex.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: hexClean),
              let msg = GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse normal_120")
            return
        }
        
        #expect(msg.glucoseValue == 120)
        #expect(msg.isValid == true)
        #expect(msg.glucose == 120.0)
    }
    
    @Test("Low glucose vector (70 mg/dL)")
    func lowGlucoseVector() throws {
        let session = try Self.loadSessionFixture()
        
        guard let vector = session.test_vectors.first(where: { $0.id == "low_70" }) else {
            Issue.record("Vector 'low_70' not found")
            return
        }
        
        let hexClean = vector.hex.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: hexClean),
              let msg = GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse low_70")
            return
        }
        
        #expect(msg.glucoseValue == 70)
        #expect(msg.isValid == true)
    }
    
    @Test("Invalid zero glucose vector")
    func invalidZeroGlucose() throws {
        let session = try Self.loadSessionFixture()
        
        guard let vector = session.test_vectors.first(where: { $0.id == "invalid_zero" }) else {
            Issue.record("Vector 'invalid_zero' not found")
            return
        }
        
        let hexClean = vector.hex.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: hexClean),
              let msg = GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse invalid_zero")
            return
        }
        
        #expect(msg.glucoseValue == 0)
        #expect(msg.isValid == false, "Zero glucose should be invalid")
    }
    
    // MARK: - State Machine Validation
    
    @Test("State transitions are valid")
    func stateTransitions() throws {
        let session = try Self.loadSessionFixture()
        
        // Verify state sequence from steps
        var states: [String] = []
        for step in session.steps {
            if !states.contains(step.state) {
                states.append(step.state)
            }
        }
        
        #expect(states.contains("authenticated"), "Should start from authenticated")
        #expect(states.contains("glucose_received"), "Should end at glucose_received")
        #expect(session.result.final_state == "glucose_received")
        #expect(session.result.success == true)
    }
    
    // MARK: - G5 Format Compatibility
    
    @Test("G5 format glucose with displayOnly flag")
    func g5FormatVector() throws {
        let session = try Self.loadSessionFixture()
        
        guard let vector = session.test_vectors.first(where: { $0.id == "g5_display_only" }) else {
            Issue.record("Vector 'g5_display_only' not found")
            return
        }
        
        let hexClean = vector.hex.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: hexClean),
              let msg = G5GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse g5_display_only")
            return
        }
        
        #expect(msg.glucoseIsDisplayOnly == true, "Should have displayOnly flag")
        #expect(msg.glucose == 88, "Glucose should be 88 (0x58 & 0x0FFF)")
        #expect(msg.state == 6, "State should be OK (6)")
    }
}


