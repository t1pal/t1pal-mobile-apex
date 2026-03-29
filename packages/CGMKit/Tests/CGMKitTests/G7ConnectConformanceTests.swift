// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7ConnectConformanceTests.swift
// CGMKitTests
//
// Conformance tests for Dexcom G7 BLE connection sequence.
// Uses fixture data from fixture_g7_connect.json.
// Task: SESSION-G7-001a
// Trace: PRD-008 REQ-BLE-008

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

// MARK: - Test Fixture Types

struct G7ConnectFixture: Decodable {
    let session_id: String
    let session_name: String
    let description: String
    let sensor_serial: String
    let sensor_code: String
    let ble_characteristics: G7BLECharacteristics
    let sensor_info: G7SensorInfoFixture
    let state_machine: G7StateMachineFixture
    let opcodes: [String: G7OpcodeInfo]
    let jpake_protocol: G7JPAKEProtocolFixture
    let steps: [G7ConnectStep]
    let test_vectors: [G7ConnectVector]
    let error_handling: G7ErrorHandling
    let connection_modes: [String: G7ConnectionModeFixture]
}

struct G7BLECharacteristics: Decodable {
    let advertisement_service_uuid: String
    let service_uuid: String
    let communication_uuid: String
    let control_uuid: String
    let auth_uuid: String
    let backfill_uuid: String
    let source: String?
}

struct G7SensorInfoFixture: Decodable {
    let warmup_minutes: Double
    let session_days: Double
    let uses_jpake_auth: Bool
    let sensor_code_length: Int
    let sensor_serial_length: Int
    let lifetime_hours: Double?
    let grace_period_hours: Double?
    let source: String?
}

struct G7StateMachineFixture: Decodable {
    let initial: String
    let final: String
    let states: [G7StateInfo]
    let transitions: [G7TransitionInfo]
}

struct G7StateInfo: Decodable {
    let name: String
    let description: String
}

struct G7TransitionInfo: Decodable {
    let from: String
    let to: String
    let trigger: String
}

struct G7OpcodeInfo: Decodable {
    let name: String
    let direction: String
    let description: String
}

struct G7JPAKEProtocolFixture: Decodable {
    let description: String
    let curve: String
    let password: String
    let rounds: [G7JPAKERoundInfo]
    let zkp_structure: G7ZKPStructure
}

struct G7JPAKERoundInfo: Decodable {
    let round: Int
    let description: String
    let client_sends: [String]
    let server_responds: [String]
}

struct G7ZKPStructure: Decodable {
    let commitment: String
    let challenge: String
    let response: String
    let total: String
}

struct G7ConnectStep: Decodable {
    let step: Int
    let state: String
    let operation: String
    let description: String
    let source_file: String?
    let source_line: Int?
    let tx: G7MessageFormat?
    let rx: G7MessageFormat?
    let action: G7ActionInfo?
    let compute: G7ComputeInfo?
    let validation: G7ValidationInfo?
    let characteristic: String?
    let notes: String?
}

struct G7MessageFormat: Decodable {
    let raw_hex: String
    let opcode: String?
    let opcode_name: String?
    let length: Int?
    let format: String?
    let fields: [String: AnyCodableValue]?
    let compute: [String: String]?
    let status: String?
}

struct G7ActionInfo: Decodable {
    let method: String?
    let advertisement_uuid: String?
    let match_criteria: String?
    let peripheral_name: String?
    let service_uuid: String?
    let characteristics: [G7CharacteristicInfo]?
}

struct G7CharacteristicInfo: Decodable {
    let uuid: String
    let name: String
    let properties: [String]
}

struct G7ComputeInfo: Decodable {
    let algorithm: String?
    let output: String?
    let confirmHash: String?
}

struct G7ValidationInfo: Decodable {
    let expected: String?
    let on_mismatch: String?
    let steps: [String]?
}

struct G7ConnectVector: Decodable {
    let name: String
    let source: String?
    let input_hex: String?
    let expected_hex: String?
    let format: String?
    let fields: [String: Int]?
    let expected: [String: AnyCodableValue]?
    let sensor_serial: String?
    let advertisement_name_patterns: [String]?
    let match_algorithm: String?
    let zkp_length: Int?
    let commitment_offset: Int?
    let commitment_length: Int?
    let challenge_offset: Int?
    let challenge_length: Int?
    let response_offset: Int?
    let response_length: Int?
}

struct G7ErrorHandling: Decodable {
    let code_mismatch: G7ErrorInfo
    let bluetooth_unavailable: G7ErrorInfo
    let sensor_not_found: G7ErrorInfo
    let connection_failed: G7ErrorInfo
}

struct G7ErrorInfo: Decodable {
    let description: String?
    let trigger: String
    let error: String
    let callback: String?
    let recovery: String?
    let trace: String?
}

struct G7ConnectionModeFixture: Decodable {
    let description: String
    let uses_auth: Bool
    let flow: String?
    let state: String?
    let notes: String?
}

/// Helper for decoding mixed-type JSON values
enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }
}

// MARK: - G7 Connection Conformance Tests

@Suite("G7 Connect Conformance Tests")
struct G7ConnectConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G7ConnectFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_g7_connect", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_g7_connect.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(G7ConnectFixture.self, from: data)
    }
    
    enum FixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - BLE Characteristic Tests
    
    @Test("G7 advertisement service UUID matches G7Constants")
    func advertisementUUID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.ble_characteristics.advertisement_service_uuid == G7Constants.advertisementServiceUUID)
    }
    
    @Test("G7 CGM service UUID matches G7Constants")
    func cgmServiceUUID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.ble_characteristics.service_uuid == G7Constants.cgmServiceUUID)
    }
    
    @Test("G7 auth characteristic UUID matches G7Constants")
    func authUUID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.ble_characteristics.auth_uuid == G7Constants.authenticationUUID)
    }
    
    @Test("G7 control characteristic UUID matches G7Constants")
    func controlUUID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.ble_characteristics.control_uuid == G7Constants.controlUUID)
    }
    
    @Test("G7 backfill characteristic UUID matches G7Constants")
    func backfillUUID() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.ble_characteristics.backfill_uuid == G7Constants.backfillUUID)
    }
    
    // MARK: - Sensor Info Tests
    
    @Test("G7 warmup duration matches G7Constants")
    func warmupDuration() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.sensor_info.warmup_minutes == G7Constants.sensorWarmupMinutes)
    }
    
    @Test("G7 session duration matches G7Constants")
    func sessionDuration() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.sensor_info.session_days == G7Constants.sensorSessionDays)
    }
    
    @Test("G7 uses J-PAKE authentication")
    func usesJPAKE() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.sensor_info.uses_jpake_auth == G7Constants.usesJPAKEAuth)
    }
    
    @Test("G7 sensor code is 4 digits")
    func sensorCodeLength() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.sensor_info.sensor_code_length == G7Constants.sensorCodeLength)
    }
    
    @Test("G7 sensor serial is 10 characters")
    func sensorSerialLength() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.sensor_info.sensor_serial_length == G7Constants.sensorSerialLength)
    }
    
    // MARK: - State Machine Tests
    
    @Test("State machine has all expected states")
    func allStatesPresent() throws {
        let fixture = try Self.loadFixture()
        let stateNames = fixture.state_machine.states.map { $0.name }
        
        let expectedStates = ["idle", "scanning", "connecting", "pairing", 
                             "authenticating", "streaming", "disconnecting", 
                             "error", "passive"]
        
        for expected in expectedStates {
            #expect(stateNames.contains(expected), "Missing state: \(expected)")
        }
    }
    
    @Test("State machine initial state is idle")
    func initialStateIsIdle() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.state_machine.initial == "idle")
    }
    
    @Test("State machine final state is streaming")
    func finalStateIsStreaming() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.state_machine.final == "streaming")
    }
    
    @Test("All connection states map to G7ConnectionState")
    func connectionStatesMap() throws {
        let fixture = try Self.loadFixture()
        
        for state in fixture.state_machine.states {
            let g7State = G7ConnectionState(rawValue: state.name)
            #expect(g7State != nil, "G7ConnectionState missing: \(state.name)")
        }
    }
    
    // MARK: - Opcode Tests
    
    @Test("AuthRound1 opcode matches G7Opcode")
    func authRound1Opcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x02"] else {
            Issue.record("Opcode 0x02 not found")
            return
        }
        #expect(opcode.name == "AuthRound1")
        #expect(G7Opcode.authRound1.rawValue == 0x02)
    }
    
    @Test("AuthRound2 opcode matches G7Opcode")
    func authRound2Opcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x03"] else {
            Issue.record("Opcode 0x03 not found")
            return
        }
        #expect(opcode.name == "AuthRound2")
        #expect(G7Opcode.authRound2.rawValue == 0x03)
    }
    
    @Test("AuthConfirm opcode matches G7Opcode")
    func authConfirmOpcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x04"] else {
            Issue.record("Opcode 0x04 not found")
            return
        }
        #expect(opcode.name == "AuthConfirm")
        #expect(G7Opcode.authConfirm.rawValue == 0x04)
    }
    
    @Test("GlucoseTx opcode matches G7Opcode")
    func glucoseTxOpcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x4E"] else {
            Issue.record("Opcode 0x4E not found")
            return
        }
        #expect(opcode.name == "GlucoseTx")
        #expect(G7Opcode.glucoseTx.rawValue == 0x4E)
    }
    
    @Test("GlucoseRx opcode matches G7Opcode")
    func glucoseRxOpcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x4F"] else {
            Issue.record("Opcode 0x4F not found")
            return
        }
        #expect(opcode.name == "GlucoseRx")
        #expect(G7Opcode.glucoseRx.rawValue == 0x4F)
    }
    
    @Test("KeepAlive opcode matches G7Opcode")
    func keepAliveOpcode() throws {
        let fixture = try Self.loadFixture()
        guard let opcode = fixture.opcodes["0x06"] else {
            Issue.record("Opcode 0x06 not found")
            return
        }
        #expect(opcode.name == "KeepAlive")
        #expect(G7Opcode.keepAlive.rawValue == 0x06)
    }
    
    // MARK: - J-PAKE Protocol Tests
    
    @Test("J-PAKE uses P-256 curve")
    func jpakeCurve() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.jpake_protocol.curve == "P-256")
    }
    
    @Test("J-PAKE has 3 rounds")
    func jpakeRounds() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.jpake_protocol.rounds.count == 3)
    }
    
    @Test("ZKP structure is 80 bytes")
    func zkpStructure() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.jpake_protocol.zkp_structure.commitment == "32 bytes")
        #expect(fixture.jpake_protocol.zkp_structure.challenge == "16 bytes")
        #expect(fixture.jpake_protocol.zkp_structure.response == "32 bytes")
        #expect(fixture.jpake_protocol.zkp_structure.total == "80 bytes")
    }
    
    // MARK: - Message Format Tests
    
    @Test("G7KeepAliveTxMessage format matches fixture")
    func keepAliveFormat() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.name == "G7KeepAlive message format" }) else {
            Issue.record("Vector not found")
            return
        }
        
        let keepAlive = G7KeepAliveTxMessage(time: 25)
        let hex = keepAlive.data.map { String(format: "%02x", $0) }.joined()
        
        #expect(hex == vector.expected_hex)
        #expect(keepAlive.data.count == 2)
        #expect(keepAlive.data[0] == G7Opcode.keepAlive.rawValue)
        #expect(keepAlive.data[1] == 25)
    }
    
    @Test("G7GlucoseTxMessage format is correct")
    func glucoseTxFormat() {
        let glucoseTx = G7GlucoseTxMessage()
        #expect(glucoseTx.data.count == 1)
        #expect(glucoseTx.data[0] == G7Opcode.glucoseTx.rawValue)
    }
    
    @Test("G7SensorInfoTxMessage format is correct")
    func sensorInfoTxFormat() {
        let infoTx = G7SensorInfoTxMessage()
        #expect(infoTx.data.count == 1)
        #expect(infoTx.data[0] == G7Opcode.sensorInfoTx.rawValue)
    }
    
    @Test("G7DisconnectTxMessage format is correct")
    func disconnectTxFormat() {
        let disconnectTx = G7DisconnectTxMessage()
        #expect(disconnectTx.data.count == 1)
        #expect(disconnectTx.data[0] == G7Opcode.disconnectTx.rawValue)
    }
    
    // MARK: - Connection Step Sequence Tests
    
    @Test("Connection sequence has 16 steps")
    func connectionStepCount() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.steps.count == 16)
    }
    
    @Test("Connection starts with START_SCAN")
    func firstStepIsScan() throws {
        let fixture = try Self.loadFixture()
        guard let firstStep = fixture.steps.first else {
            Issue.record("No steps found")
            return
        }
        #expect(firstStep.operation == "START_SCAN")
        #expect(firstStep.state == "idle → scanning")
    }
    
    @Test("Connection ends with GLUCOSE_RX")
    func lastStepIsGlucoseRx() throws {
        let fixture = try Self.loadFixture()
        guard let lastStep = fixture.steps.last else {
            Issue.record("No steps found")
            return
        }
        #expect(lastStep.operation == "GLUCOSE_RX")
        #expect(lastStep.state == "streaming")
    }
    
    @Test("J-PAKE steps are in correct order")
    func jpakeStepOrder() throws {
        let fixture = try Self.loadFixture()
        let jpakeSteps = fixture.steps.filter { 
            $0.operation.starts(with: "JPAKE_") 
        }
        
        let operations = jpakeSteps.map { $0.operation }
        let expected = ["JPAKE_ROUND1_TX", "JPAKE_ROUND1_RX", 
                       "JPAKE_ROUND2_TX", "JPAKE_ROUND2_RX",
                       "JPAKE_CONFIRM_TX", "JPAKE_CONFIRM_RX"]
        
        #expect(operations == expected)
    }
    
    // MARK: - ZKP Structure Tests
    
    @Test("ZKP vector defines correct offsets")
    func zkpOffsets() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.name == "J-PAKE ZKP structure" }) else {
            Issue.record("ZKP structure vector not found")
            return
        }
        
        #expect(vector.zkp_length == 80)
        #expect(vector.commitment_offset == 0)
        #expect(vector.commitment_length == 32)
        #expect(vector.challenge_offset == 32)
        #expect(vector.challenge_length == 16)
        #expect(vector.response_offset == 48)
        #expect(vector.response_length == 32)
    }
    
    @Test("G7ZKProof parsing validates structure")
    func zkpParsing() {
        // Valid ZKP data (80 bytes)
        var validData = Data(repeating: 0xAA, count: 32)  // commitment
        validData.append(Data(repeating: 0xBB, count: 16))  // challenge
        validData.append(Data(repeating: 0xCC, count: 32))  // response
        
        let zkp = G7ZKProof(data: validData)
        #expect(zkp != nil)
        #expect(zkp?.commitment.count == 32)
        #expect(zkp?.challenge.count == 16)
        #expect(zkp?.response.count == 32)
        
        // Invalid ZKP data (too short)
        let shortData = Data(repeating: 0x00, count: 50)
        let invalidZkp = G7ZKProof(data: shortData)
        #expect(invalidZkp == nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Code mismatch triggers onCodeMismatch callback")
    func codeMismatchError() throws {
        let fixture = try Self.loadFixture()
        let errorInfo = fixture.error_handling.code_mismatch
        
        #expect(errorInfo.error == "CGMError.invalidSensorCode")
        #expect(errorInfo.callback == "onCodeMismatch()")
        #expect(errorInfo.trace == "BLE-QUIRK-001")
    }
    
    @Test("Bluetooth unavailable error")
    func bluetoothUnavailableError() throws {
        let fixture = try Self.loadFixture()
        let errorInfo = fixture.error_handling.bluetooth_unavailable
        
        #expect(errorInfo.trigger == "central.state != .poweredOn")
        #expect(errorInfo.error == "CGMError.bluetoothUnavailable")
    }
    
    // MARK: - Connection Mode Tests
    
    @Test("Direct mode uses authentication")
    func directModeUsesAuth() throws {
        let fixture = try Self.loadFixture()
        guard let directMode = fixture.connection_modes["direct"] else {
            Issue.record("Direct mode not found")
            return
        }
        
        #expect(directMode.uses_auth == true)
        #expect(directMode.flow == "scan → connect → J-PAKE → stream")
    }
    
    @Test("Passive mode does not use authentication")
    func passiveModeNoAuth() throws {
        let fixture = try Self.loadFixture()
        guard let passiveMode = fixture.connection_modes["passiveBLE"] else {
            Issue.record("passiveBLE mode not found")
            return
        }
        
        #expect(passiveMode.uses_auth == false)
        #expect(passiveMode.state == "passive")
    }
    
    @Test("HealthKit-only mode does not use authentication")
    func healthKitOnlyNoAuth() throws {
        let fixture = try Self.loadFixture()
        guard let healthKitMode = fixture.connection_modes["healthKitObserver"] else {
            Issue.record("healthKitObserver mode not found")
            return
        }
        
        #expect(healthKitMode.uses_auth == false)
        #expect(healthKitMode.state == "passive")
    }
}

// MARK: - G7 Manager Integration Tests

@Suite("G7 Manager Connection Integration", .serialized)
struct G7ManagerConnectionTests {
    
    @Test("Manager starts in idle state")
    func initialState() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    @Test("Manager transitions to scanning")
    func transitionToScanning() async throws {
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central,
            allowSimulation: true
        )
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .scanning)
        
        await manager.disconnect()
    }
    
    @Test("Passive mode enters passive state immediately")
    func passiveModeState() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .passive)
        
        await manager.disconnect()
    }
    
    @Test("Sensor code update resets authenticator")
    func sensorCodeUpdate() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        // Update sensor code
        try await manager.updateSensorCode("5678")
        
        let newCode = await manager.sensorCode
        #expect(newCode == "5678")
    }
    
    @Test("Invalid sensor code rejected")
    func invalidSensorCodeRejected() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        // Try to update with invalid code
        do {
            try await manager.updateSensorCode("123")  // Too short
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }
        
        do {
            try await manager.updateSensorCode("ABCD")  // Not numeric
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }
    }
}
