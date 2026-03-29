// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7GlucoseSessionConformanceTests.swift
// CGMKitTests
//
// Session-level conformance tests for G7 glucose read sequence.
// Tests complete flow from authenticated state through glucose reception.
// Task: G7-GLUC-001
// Source: conformance/protocol/dexcom/fixture_g7_glucose_session.json

import Testing
import Foundation
@testable import CGMKit

// MARK: - Session Fixture Types

struct G7GlucoseSessionFixture: Decodable {
    let fixture_id: String
    let fixture_name: String
    let prerequisite: G7SessionPrerequisite
    let state_machine: G7SessionStateMachine
    let steps: [G7SessionStep]
    let test_vectors: [G7SessionTestVector]
    let lifecycle_vectors: [G7LifecycleSessionVector]
    let backfill_vectors: [G7BackfillSessionVector]
    let algorithm_states: [String: G7AlgorithmStateInfo]
}

struct G7SessionPrerequisite: Decodable {
    let session_id: String
    let state: String
    let description: String
}

struct G7SessionStateMachine: Decodable {
    let initial: String
    let final: String
    let transitions: [G7SessionTransition]
}

struct G7SessionTransition: Decodable {
    let from: String
    let to: String
    let trigger: String
}

struct G7SessionStep: Decodable {
    let step: Int
    let state: String
    let operation: String
    let description: String
}

struct G7SessionTestVector: Decodable {
    let name: String
    let id: String
    let hex: String
    let expected: G7SessionExpected
}

struct G7SessionExpected: Decodable {
    let glucose: Int?
    let glucoseTimestamp: UInt32?
    let glucoseIsDisplayOnly: Bool?
    let sequence: UInt16?
    let age: UInt16?
    let predicted: UInt16?
    let trend: Double?
    let algorithmState: String?
    let messageTimestamp: UInt32?
}

struct G7LifecycleSessionVector: Decodable {
    let id: String
    let description: String
    let hex: String
    let expected: G7SessionExpected
}

struct G7BackfillSessionVector: Decodable {
    let id: String
    let description: String
    let hex: String
    let expected: G7BackfillSessionExpected
}

struct G7BackfillSessionExpected: Decodable {
    let timestamp: UInt32?
    let glucose: Int?
    let algorithmState: String?
    let glucoseIsDisplayOnly: Bool?
    let hasReliableGlucose: Bool?
}

struct G7AlgorithmStateInfo: Decodable {
    let name: String
    let description: String
}

// MARK: - Helper Extension

extension Data {
    init?(sessionHexString: String) {
        let hex = sessionHexString.lowercased()
        var data = Data()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard nextIndex != index else { break }
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - Session Conformance Tests

@Suite("G7 Glucose Session Conformance Tests")
struct G7GlucoseSessionConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadSessionFixture() throws -> G7GlucoseSessionFixture {
        let conformancePath = "conformance/protocol/dexcom/fixture_g7_glucose_session.json"
        
        // Try multiple paths for different test environments
        let paths = [
            FileManager.default.currentDirectoryPath + "/" + conformancePath,
            FileManager.default.currentDirectoryPath + "/../../../" + conformancePath
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(G7GlucoseSessionFixture.self, from: data)
            }
        }
        
        throw SessionFixtureError.notFound("fixture_g7_glucose_session.json")
    }
    
    enum SessionFixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Session Structure Tests
    
    @Test("Session fixture has correct ID")
    func sessionFixtureID() throws {
        let fixture = try Self.loadSessionFixture()
        #expect(fixture.fixture_id == "G7-GLUC-001")
    }
    
    @Test("Session has J-PAKE prerequisite")
    func sessionPrerequisite() throws {
        let fixture = try Self.loadSessionFixture()
        #expect(fixture.prerequisite.session_id == "SESSION-G7-001e")
        #expect(fixture.prerequisite.state == "authenticated")
    }
    
    @Test("State machine starts at authenticated")
    func stateMachineInitial() throws {
        let fixture = try Self.loadSessionFixture()
        #expect(fixture.state_machine.initial == "authenticated")
        #expect(fixture.state_machine.final == "glucose_received")
    }
    
    @Test("State machine has correct transitions")
    func stateMachineTransitions() throws {
        let fixture = try Self.loadSessionFixture()
        #expect(fixture.state_machine.transitions.count == 2)
        
        let firstTransition = fixture.state_machine.transitions[0]
        #expect(firstTransition.from == "authenticated")
        #expect(firstTransition.to == "streaming")
        
        let secondTransition = fixture.state_machine.transitions[1]
        #expect(secondTransition.from == "streaming")
        #expect(secondTransition.to == "glucose_received")
    }
    
    @Test("Session has 3 steps")
    func sessionSteps() throws {
        let fixture = try Self.loadSessionFixture()
        #expect(fixture.steps.count == 3)
        
        // Verify step sequence
        #expect(fixture.steps[0].operation == "SUBSCRIBE_CONTROL")
        #expect(fixture.steps[1].operation == "GLUCOSE_NOTIFICATION")
        #expect(fixture.steps[2].operation == "PARSE_GLUCOSE")
    }
    
    // MARK: - Test Vector Validation
    
    @Test("All glucose test vectors parse correctly")
    func allGlucoseVectorsParse() throws {
        let fixture = try Self.loadSessionFixture()
        
        for vector in fixture.test_vectors {
            guard let data = Data(sessionHexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7GlucoseMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id): \(vector.name)")
        }
    }
    
    @Test("Basic glucose reading matches expected values")
    func basicGlucoseReading() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "basic_reading" }) else {
            Issue.record("Vector 'basic_reading' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse basic_reading")
            return
        }
        
        #expect(msg.glucose == 138)
        #expect(msg.glucoseTimestamp == 87485)
        #expect(msg.glucoseIsDisplayOnly == false)
    }
    
    @Test("Display-only flag correctly detected")
    func displayOnlyFlag() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "calibration_display_only" }) else {
            Issue.record("Vector 'calibration_display_only' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse calibration_display_only")
            return
        }
        
        #expect(msg.glucose == 104)
        #expect(msg.glucoseIsDisplayOnly == true)
    }
    
    @Test("Trend values parse correctly including negative")
    func trendValuesParse() throws {
        let fixture = try Self.loadSessionFixture()
        
        // Positive trend
        if let vector = fixture.test_vectors.first(where: { $0.id == "detailed_reading" }),
           let data = Data(sessionHexString: vector.hex),
           let msg = G7GlucoseMessage(data: data) {
            #expect(msg.trend == 0.3)
        }
        
        // Negative trend
        if let vector = fixture.test_vectors.first(where: { $0.id == "negative_trend" }),
           let data = Data(sessionHexString: vector.hex),
           let msg = G7GlucoseMessage(data: data) {
            #expect(msg.trend == -0.2)
        }
        
        // Missing trend
        if let vector = fixture.test_vectors.first(where: { $0.id == "missing_trend" }),
           let data = Data(sessionHexString: vector.hex),
           let msg = G7GlucoseMessage(data: data) {
            #expect(msg.trend == nil)
        }
    }
    
    @Test("Age field handles large values")
    func ageFieldLargeValues() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "two_byte_age" }) else {
            Issue.record("Vector 'two_byte_age' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse two_byte_age")
            return
        }
        
        #expect(msg.age == 298)
        #expect(msg.messageTimestamp == 154105)
        #expect(msg.glucoseTimestamp == 153807)
    }
    
    // MARK: - Lifecycle State Tests
    
    @Test("All lifecycle vectors parse correctly")
    func allLifecycleVectorsParse() throws {
        let fixture = try Self.loadSessionFixture()
        
        for vector in fixture.lifecycle_vectors {
            guard let data = Data(sessionHexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7GlucoseMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id)")
        }
    }
    
    @Test("Stopped state has no glucose")
    func stoppedStateNoGlucose() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.lifecycle_vectors.first(where: { $0.id == "lifecycle_0_stopped" }) else {
            Issue.record("Vector 'lifecycle_0_stopped' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_0_stopped")
            return
        }
        
        #expect(msg.glucose == nil)
        #expect(msg.algorithmState == .known(.stopped))
    }
    
    @Test("OK state has valid glucose")
    func okStateHasGlucose() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.lifecycle_vectors.first(where: { $0.id == "lifecycle_6_ok" }) else {
            Issue.record("Vector 'lifecycle_6_ok' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_6_ok")
            return
        }
        
        #expect(msg.glucose == 84)
        #expect(msg.algorithmState == .known(.ok))
    }
    
    @Test("Expired state is correctly detected")
    func expiredStateDetected() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.lifecycle_vectors.first(where: { $0.id == "lifecycle_8_expired" }) else {
            Issue.record("Vector 'lifecycle_8_expired' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_8_expired")
            return
        }
        
        #expect(msg.algorithmState == .known(.expired))
        #expect(msg.sequence == 3028)
    }
    
    // MARK: - Backfill Message Tests
    
    @Test("All backfill vectors parse correctly")
    func allBackfillVectorsParse() throws {
        let fixture = try Self.loadSessionFixture()
        
        for vector in fixture.backfill_vectors {
            guard let data = Data(sessionHexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7BackfillMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id)")
        }
    }
    
    @Test("Basic backfill has reliable glucose")
    func basicBackfillReliable() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.backfill_vectors.first(where: { $0.id == "backfill_basic" }) else {
            Issue.record("Vector 'backfill_basic' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7BackfillMessage(data: data) else {
            Issue.record("Failed to parse backfill_basic")
            return
        }
        
        #expect(msg.timestamp == 153807)
        #expect(msg.glucose == 143)
        #expect(msg.hasReliableGlucose == true)
        #expect(msg.glucoseIsDisplayOnly == false)
    }
    
    @Test("Backfill calibration marked as display-only")
    func backfillCalibrationDisplayOnly() throws {
        let fixture = try Self.loadSessionFixture()
        guard let vector = fixture.backfill_vectors.first(where: { $0.id == "backfill_calibration" }) else {
            Issue.record("Vector 'backfill_calibration' not found")
            return
        }
        
        guard let data = Data(sessionHexString: vector.hex),
              let msg = G7BackfillMessage(data: data) else {
            Issue.record("Failed to parse backfill_calibration")
            return
        }
        
        #expect(msg.glucoseIsDisplayOnly == true)
    }
    
    // MARK: - Algorithm State Coverage
    
    @Test("Fixture defines all known algorithm states")
    func algorithmStatesCoverage() throws {
        let fixture = try Self.loadSessionFixture()
        
        let expectedStates = ["0x01", "0x02", "0x03", "0x04", "0x06", "0x18"]
        for state in expectedStates {
            #expect(fixture.algorithm_states[state] != nil, "Missing algorithm state: \(state)")
        }
    }
    
    // MARK: - Session Flow Integration
    
    @Test("Complete session flow from authenticated to glucose_received")
    func completeSessionFlow() throws {
        let fixture = try Self.loadSessionFixture()
        
        // 1. Verify prerequisite
        #expect(fixture.prerequisite.state == "authenticated")
        
        // 2. Verify state transitions
        var currentState = fixture.state_machine.initial
        for transition in fixture.state_machine.transitions {
            #expect(transition.from == currentState)
            currentState = transition.to
        }
        #expect(currentState == fixture.state_machine.final)
        
        // 3. Verify we can parse a glucose message at the end
        guard let vector = fixture.test_vectors.first(where: { $0.id == "basic_reading" }),
              let data = Data(sessionHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to verify glucose parsing")
            return
        }
        
        #expect(msg.glucose != nil)
        #expect(msg.glucose! > 0 && msg.glucose! < 500)
    }
}
