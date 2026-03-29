// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7LifecycleConformanceTests.swift
// CGMKitTests
//
// Conformance tests for G7 sensor lifecycle state machine.
// Tests state transitions: stopped → warmup → ok → gracePeriod → expired
// Task: G7-LIFE-001
// Source: conformance/protocol/dexcom/fixture_g7_lifecycle_session.json

import Testing
import Foundation
@testable import CGMKit

// MARK: - Fixture Types

struct G7LifecycleSessionFixture: Decodable {
    let fixture_id: String
    let fixture_name: String
    let timing_constants: G7TimingConstants
    let lifecycle_state_machine: G7LifecycleStateMachineFixture
    let algorithm_state_machine: G7AlgorithmStateMachineFixture
    let lifecycle_test_vectors: [G7LifecycleTestVector]
    let timing_calculation_examples: G7TimingCalculationExamples
}

struct G7TimingConstants: Decodable {
    let defaultLifetime: G7TimingValue
    let defaultWarmupDuration: G7TimingValue
    let gracePeriod: G7TimingValue
    let totalLifetime: G7TimingValue
    let glucoseInterval: G7TimingValue
}

struct G7TimingValue: Decodable {
    let value: UInt32
    let unit: String
    let description: String
}

struct G7LifecycleStateMachineFixture: Decodable {
    let states: [String: G7LifecycleStateInfo]
    let transitions: [G7LifecycleTransition]
}

struct G7LifecycleStateInfo: Decodable {
    let description: String
    let has_glucose: Bool
    let is_connected: Bool?
    let algorithm_states: [String]?
}

struct G7LifecycleTransition: Decodable {
    let from: String
    let to: String
    let trigger: String
    let description: String
}

struct G7AlgorithmStateMachineFixture: Decodable {
    let states: [String: G7AlgorithmStateFixtureInfo]
}

struct G7AlgorithmStateFixtureInfo: Decodable {
    let name: String
    let enum_name: String
    let description: String
    let has_reliable_glucose: Bool
    let is_in_warmup: Bool
    let sensor_failed: Bool
    let has_temporary_error: Bool?
}

struct G7LifecycleTestVector: Decodable {
    let id: String
    let description: String
    let hex: String
    let expected: G7LifecycleExpected
    let lifecycle_state: String
    let timing_notes: String?
}

struct G7LifecycleExpected: Decodable {
    let glucose: Int?
    let algorithmState: String
    let algorithmStateName: String
    let hasReliableGlucose: Bool
    let isInWarmup: Bool?
    let sensorFailed: Bool?
    let hasTemporaryError: Bool?
    let sequence: UInt16?
    let messageTimestamp: UInt32?
    let glucoseTimestamp: UInt32?
    let age: UInt16?
}

struct G7TimingCalculationExamples: Decodable {
    let examples: [G7TimingCalculationExample]
}

struct G7TimingCalculationExample: Decodable {
    let name: String
    let messageTimestamp: UInt32
    let warmupComplete: Bool
    let sessionExpired: Bool
    let graceExpired: Bool
}

// MARK: - Helper Extension

extension Data {
    init?(lifecycleHexString: String) {
        let hex = lifecycleHexString.lowercased()
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

// MARK: - Lifecycle State Calculator

/// Calculates lifecycle state from timing and algorithm state
struct G7LifecycleCalculator {
    let defaultLifetime: UInt32 = 864000      // 10 days in seconds
    let warmupDuration: UInt32 = 1620         // 27 minutes in seconds
    let gracePeriod: UInt32 = 43200           // 12 hours in seconds
    
    var totalLifetime: UInt32 {
        defaultLifetime + gracePeriod  // 907200 seconds = 10.5 days
    }
    
    func isWarmupComplete(timestamp: UInt32) -> Bool {
        timestamp >= warmupDuration
    }
    
    func isSessionExpired(timestamp: UInt32) -> Bool {
        timestamp >= defaultLifetime
    }
    
    func isGraceExpired(timestamp: UInt32) -> Bool {
        timestamp >= totalLifetime
    }
    
    /// Calculate lifecycle state from message timestamp and algorithm state
    func lifecycleState(messageTimestamp: UInt32, algorithmStateRaw: UInt8) -> String {
        // Check for failure states first
        let failureStates: Set<UInt8> = [0x0B, 0x0C, 0x10, 0x11, 0x13, 0x14, 0x15, 0x16, 0x19]
        if failureStates.contains(algorithmStateRaw) {
            return "failed"
        }
        
        // Check for expired
        if algorithmStateRaw == 0x18 {
            return "expired"
        }
        
        // Check for warmup
        if algorithmStateRaw == 0x02 {
            return "warmup"
        }
        
        // Check for stopped
        if algorithmStateRaw == 0x01 {
            return "searching"
        }
        
        // For ok state, determine based on timing
        if algorithmStateRaw == 0x06 {
            if isGraceExpired(timestamp: messageTimestamp) {
                return "expired"
            } else if isSessionExpired(timestamp: messageTimestamp) {
                return "gracePeriod"
            } else {
                return "ok"
            }
        }
        
        // Default to ok for other states
        return "ok"
    }
}

// MARK: - Conformance Tests

@Suite("G7 Lifecycle Conformance Tests")
struct G7LifecycleConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G7LifecycleSessionFixture {
        let conformancePath = "conformance/protocol/dexcom/fixture_g7_lifecycle_session.json"
        
        let paths = [
            FileManager.default.currentDirectoryPath + "/" + conformancePath,
            FileManager.default.currentDirectoryPath + "/../../../" + conformancePath
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(G7LifecycleSessionFixture.self, from: data)
            }
        }
        
        throw LifecycleFixtureError.notFound("fixture_g7_lifecycle_session.json")
    }
    
    enum LifecycleFixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Session Structure Tests
    
    @Test("Session fixture has correct ID")
    func sessionFixtureID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.fixture_id == "G7-LIFE-001")
    }
    
    @Test("Session fixture has correct name")
    func sessionFixtureName() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.fixture_name == "Dexcom G7 Sensor Lifecycle")
    }
    
    // MARK: - Timing Constants Tests
    
    @Test("Default lifetime is 10 days")
    func defaultLifetimeIs10Days() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.timing_constants.defaultLifetime.value == 864000)
    }
    
    @Test("Warmup duration is 27 minutes")
    func warmupDurationIs27Minutes() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.timing_constants.defaultWarmupDuration.value == 1620)
    }
    
    @Test("Grace period is 12 hours")
    func gracePeriodIs12Hours() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.timing_constants.gracePeriod.value == 43200)
    }
    
    @Test("Total lifetime is 10.5 days")
    func totalLifetimeIs10Point5Days() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.timing_constants.totalLifetime.value == 907200)
    }
    
    @Test("Glucose interval is 5 minutes")
    func glucoseIntervalIs5Minutes() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.timing_constants.glucoseInterval.value == 300)
    }
    
    // MARK: - Lifecycle State Machine Tests
    
    @Test("Lifecycle state machine has 6 states")
    func lifecycleStateMachineHas6States() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.lifecycle_state_machine.states.count == 6)
    }
    
    @Test("All lifecycle states defined")
    func allLifecycleStatesDefined() throws {
        let fixture = try Self.loadFixture()
        let expectedStates = ["searching", "warmup", "ok", "failed", "gracePeriod", "expired"]
        
        for state in expectedStates {
            #expect(fixture.lifecycle_state_machine.states[state] != nil, "Missing state: \(state)")
        }
    }
    
    @Test("Lifecycle state machine has 7 transitions")
    func lifecycleStateMachineHas7Transitions() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.lifecycle_state_machine.transitions.count == 7)
    }
    
    @Test("Warmup to ok transition exists")
    func warmupToOkTransitionExists() throws {
        let fixture = try Self.loadFixture()
        let transition = fixture.lifecycle_state_machine.transitions.first { 
            $0.from == "warmup" && $0.to == "ok" 
        }
        #expect(transition != nil)
        #expect(transition?.trigger == "warmup_complete")
    }
    
    @Test("Ok to gracePeriod transition exists")
    func okToGracePeriodTransitionExists() throws {
        let fixture = try Self.loadFixture()
        let transition = fixture.lifecycle_state_machine.transitions.first { 
            $0.from == "ok" && $0.to == "gracePeriod" 
        }
        #expect(transition != nil)
        #expect(transition?.trigger == "session_expired")
    }
    
    // MARK: - Algorithm State Tests
    
    @Test("Algorithm state machine has 22+ states")
    func algorithmStateMachineHas22States() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.algorithm_state_machine.states.count >= 22)
    }
    
    @Test("Algorithm state 0x06 is ok with reliable glucose")
    func algorithmState06IsOk() throws {
        let fixture = try Self.loadFixture()
        guard let state = fixture.algorithm_state_machine.states["0x06"] else {
            Issue.record("State 0x06 not found")
            return
        }
        
        #expect(state.name == "ok")
        #expect(state.has_reliable_glucose == true)
        #expect(state.is_in_warmup == false)
        #expect(state.sensor_failed == false)
    }
    
    @Test("Algorithm state 0x02 is warmup")
    func algorithmState02IsWarmup() throws {
        let fixture = try Self.loadFixture()
        guard let state = fixture.algorithm_state_machine.states["0x02"] else {
            Issue.record("State 0x02 not found")
            return
        }
        
        #expect(state.name == "warmup")
        #expect(state.is_in_warmup == true)
        #expect(state.has_reliable_glucose == false)
    }
    
    @Test("Algorithm state 0x18 is expired")
    func algorithmState18IsExpired() throws {
        let fixture = try Self.loadFixture()
        guard let state = fixture.algorithm_state_machine.states["0x18"] else {
            Issue.record("State 0x18 not found")
            return
        }
        
        #expect(state.name == "expired")
        #expect(state.has_reliable_glucose == false)
    }
    
    @Test("Sensor failed states are correctly marked")
    func sensorFailedStatesMarked() throws {
        let fixture = try Self.loadFixture()
        let failedStateKeys = ["0x0B", "0x0C", "0x10", "0x11", "0x13", "0x14", "0x15", "0x16", "0x19"]
        
        for key in failedStateKeys {
            guard let state = fixture.algorithm_state_machine.states[key] else {
                Issue.record("State \(key) not found")
                continue
            }
            #expect(state.sensor_failed == true, "State \(key) should be sensor_failed")
        }
    }
    
    // MARK: - Lifecycle Test Vectors
    
    @Test("All lifecycle test vectors parse correctly")
    func allLifecycleVectorsParse() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.lifecycle_test_vectors {
            guard let data = Data(lifecycleHexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7GlucoseMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id): \(vector.description)")
        }
    }
    
    @Test("Stopped state vector parses correctly")
    func stoppedStateVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_stopped" }) else {
            Issue.record("Vector 'lifecycle_stopped' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_stopped")
            return
        }
        
        #expect(msg.glucose == nil)
        #expect(msg.algorithmStateRaw == 0x01)
        #expect(vector.lifecycle_state == "searching")
    }
    
    @Test("Warmup state vector parses correctly")
    func warmupStateVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_warmup_early" }) else {
            Issue.record("Vector 'lifecycle_warmup_early' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_warmup_early")
            return
        }
        
        #expect(msg.glucose == nil)
        #expect(msg.algorithmStateRaw == 0x02)
        #expect(vector.lifecycle_state == "warmup")
    }
    
    @Test("First reading state vector parses correctly")
    func firstReadingStateVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_first_reading" }) else {
            Issue.record("Vector 'lifecycle_first_reading' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_first_reading")
            return
        }
        
        #expect(msg.glucose == 84)
        #expect(msg.algorithmStateRaw == 0x06)
        #expect(vector.lifecycle_state == "ok")
    }
    
    @Test("Expired state vector parses correctly")
    func expiredStateVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_expired" }) else {
            Issue.record("Vector 'lifecycle_expired' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_expired")
            return
        }
        
        #expect(msg.algorithmStateRaw == 0x18)
        #expect(vector.lifecycle_state == "expired")
        #expect(msg.sequence == 3028)
    }
    
    @Test("Sensor failed vector parses correctly")
    func sensorFailedVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_sensor_failed" }) else {
            Issue.record("Vector 'lifecycle_sensor_failed' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_sensor_failed")
            return
        }
        
        #expect(msg.glucose == nil)
        #expect(msg.algorithmStateRaw == 0x19)
        #expect(vector.lifecycle_state == "failed")
    }
    
    @Test("Grace period vector parses correctly")
    func gracePeriodVector() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_test_vectors.first(where: { $0.id == "lifecycle_grace_period" }) else {
            Issue.record("Vector 'lifecycle_grace_period' not found")
            return
        }
        
        guard let data = Data(lifecycleHexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_grace_period")
            return
        }
        
        #expect(msg.glucose == 104)
        #expect(msg.algorithmStateRaw == 0x06)  // Still ok algorithm state
        #expect(vector.lifecycle_state == "gracePeriod")  // But lifecycle is grace period
    }
    
    // MARK: - Lifecycle Calculator Tests
    
    @Test("Calculator warmup complete logic")
    func calculatorWarmupComplete() {
        let calc = G7LifecycleCalculator()
        
        #expect(calc.isWarmupComplete(timestamp: 1000) == false)  // 16.6 min < 27 min
        #expect(calc.isWarmupComplete(timestamp: 1620) == true)   // 27 min = 27 min
        #expect(calc.isWarmupComplete(timestamp: 2000) == true)   // 33 min > 27 min
    }
    
    @Test("Calculator session expired logic")
    func calculatorSessionExpired() {
        let calc = G7LifecycleCalculator()
        
        #expect(calc.isSessionExpired(timestamp: 800000) == false)   // ~9.25 days
        #expect(calc.isSessionExpired(timestamp: 864000) == true)    // 10 days exactly
        #expect(calc.isSessionExpired(timestamp: 900000) == true)    // ~10.4 days
    }
    
    @Test("Calculator grace expired logic")
    func calculatorGraceExpired() {
        let calc = G7LifecycleCalculator()
        
        #expect(calc.isGraceExpired(timestamp: 900000) == false)   // ~10.4 days
        #expect(calc.isGraceExpired(timestamp: 907200) == true)    // 10.5 days exactly
        #expect(calc.isGraceExpired(timestamp: 950000) == true)    // ~11 days
    }
    
    @Test("Calculator lifecycle state determination")
    func calculatorLifecycleStateDetermination() {
        let calc = G7LifecycleCalculator()
        
        // Stopped
        #expect(calc.lifecycleState(messageTimestamp: 100, algorithmStateRaw: 0x01) == "searching")
        
        // Warmup
        #expect(calc.lifecycleState(messageTimestamp: 1000, algorithmStateRaw: 0x02) == "warmup")
        
        // Ok (normal operation)
        #expect(calc.lifecycleState(messageTimestamp: 500000, algorithmStateRaw: 0x06) == "ok")
        
        // Grace period (session expired but algorithm still ok)
        #expect(calc.lifecycleState(messageTimestamp: 880000, algorithmStateRaw: 0x06) == "gracePeriod")
        
        // Expired (algorithm says expired)
        #expect(calc.lifecycleState(messageTimestamp: 920000, algorithmStateRaw: 0x18) == "expired")
        
        // Failed
        #expect(calc.lifecycleState(messageTimestamp: 500000, algorithmStateRaw: 0x19) == "failed")
    }
    
    // MARK: - Timing Calculation Examples
    
    @Test("Timing calculation examples match expectations")
    func timingCalculationExamples() throws {
        let fixture = try Self.loadFixture()
        let calc = G7LifecycleCalculator()
        
        for example in fixture.timing_calculation_examples.examples {
            let warmupComplete = calc.isWarmupComplete(timestamp: example.messageTimestamp)
            let sessionExpired = calc.isSessionExpired(timestamp: example.messageTimestamp)
            let graceExpired = calc.isGraceExpired(timestamp: example.messageTimestamp)
            
            #expect(warmupComplete == example.warmupComplete, 
                   "Warmup mismatch for \(example.name): got \(warmupComplete), expected \(example.warmupComplete)")
            #expect(sessionExpired == example.sessionExpired,
                   "Session expired mismatch for \(example.name): got \(sessionExpired), expected \(example.sessionExpired)")
            #expect(graceExpired == example.graceExpired,
                   "Grace expired mismatch for \(example.name): got \(graceExpired), expected \(example.graceExpired)")
        }
    }
    
    // MARK: - Coverage Tests
    
    @Test("All lifecycle states have test vectors")
    func allLifecycleStatesHaveVectors() throws {
        let fixture = try Self.loadFixture()
        let coveredStates = Set(fixture.lifecycle_test_vectors.map { $0.lifecycle_state })
        let requiredStates: Set<String> = ["searching", "warmup", "ok", "gracePeriod", "expired", "failed"]
        
        for state in requiredStates {
            #expect(coveredStates.contains(state), "No test vector for lifecycle state: \(state)")
        }
    }
    
    @Test("Fixture has 11 test vectors")
    func fixtureHas11TestVectors() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.lifecycle_test_vectors.count == 11)
    }
}
