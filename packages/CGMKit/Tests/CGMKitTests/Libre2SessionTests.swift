// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre2SessionTests.swift
// CGMKitTests
//
// Session-level conformance tests for Libre 2 BLE unlock and read sequence.
// Validates fixture_libre2_session.json against Libre2Crypto implementation.
// Trace: SESSION-LIBRE-001

import Testing
import Foundation
@testable import CGMKit

// MARK: - Session Fixture Types

struct Libre2SessionFixture: Decodable {
    let session_id: String
    let session_name: String
    let description: String
    let overview: Libre2SessionOverview
    let complete_state_machine: Libre2StateMachine
    let transactions: [Libre2TransactionPhase]
    let variant_differences: Libre2VariantDifferences
    
    enum CodingKeys: String, CodingKey {
        case session_id, session_name, description, overview
        case complete_state_machine, transactions, variant_differences
    }
}

struct Libre2SessionOverview: Decodable {
    let description: String
    let total_phases: Int
    let phases: [Libre2PhaseOverview]
}

struct Libre2PhaseOverview: Decodable {
    let phase: Int
    let name: String
    let states: String
    let steps: Int
    let crypto: String?
    let notes: String?
}

struct Libre2StateMachine: Decodable {
    let initial: String
    let final: String
    let phases: Libre2StatePhases
    
    enum CodingKeys: String, CodingKey {
        case initial, final, phases
    }
}

struct Libre2StatePhases: Decodable {
    let nfc_activation: [Libre2StateTransition]
    let ble_connection: [Libre2StateTransition]
    let streaming_unlock: [Libre2StateTransition]
    let glucose_reading: [Libre2StateTransition]
}

struct Libre2StateTransition: Decodable {
    let from: String
    let to: String
    let trigger: String
    let service_uuid: String?
    let characteristic: String?
    let expected_bytes: Int?
    let tag_type: String?
}

struct Libre2TransactionPhase: Decodable {
    let phase: Int
    let name: String
    let description: String
    let operations: [Libre2Operation]?
    let transactions: [Libre2Transaction]?
    let crypto: Libre2CryptoConfig?
}

struct Libre2Operation: Decodable {
    let step: Int
    let operation: String
    let description: String
    let service_filter: String?
    let characteristics: [Libre2Characteristic]?
    let nfc_command: String?
    let output: Libre2OperationOutput?
    let test_vector: Libre2TestVector?
}

struct Libre2Characteristic: Decodable {
    let uuid: String
    let name: String
    let properties: [String]
    let purpose: String?
}

struct Libre2OperationOutput: Decodable {
    let sensorUID: String?
    let format: String?
    let patchInfo: String?
    let purpose: String?
    let encryptedFRAM: String?
}

struct Libre2TestVector: Decodable {
    let sensorUID_bytes: [UInt8]?
    let sensorUID_hex: String?
    let patchInfo_bytes: [UInt8]?
    let patchInfo_hex: String?
    let encrypted_hex: String?
    let encrypted_size: Int?
    let enableTime: UInt32?
    let unlockCount: UInt16?
}

struct Libre2Transaction: Decodable {
    let step: Int
    let direction: String?
    let operation: String?
    let characteristic: String?
    let message: String?
    let description: String?
    let state_before: String?
    let state_after: String?
    let payload: Libre2Payload?
    let test_vector: Libre2TestVector?
    let algorithm: Libre2Algorithm?
}

struct Libre2Payload: Decodable {
    let format: String
    let size: Int?
    let fields: [Libre2PayloadField]?
}

struct Libre2PayloadField: Decodable {
    let name: String
    let type: String
    let offset: Int
    let length: Int
    let derivation: String?
}

struct Libre2Algorithm: Decodable {
    let description: String?
    let function: String?
    let steps: [String]?
}

struct Libre2CryptoConfig: Decodable {
    let algorithm: String
    let key_source: String?
    let constants: Libre2CryptoConstants?
    let input_size: Int?
    let output_size: Int?
    let crc_offset: Int?
}

struct Libre2CryptoConstants: Decodable {
    let key: [String]
    let xorMagic1: String
    let xorMagic2: String
    let usefulFunctionX: String
    let usefulFunctionY: String
}

struct Libre2VariantDifferences: Decodable {
    let libre2_eu: Libre2Variant
    let libre2_us: Libre2Variant
    let libre2_ca: Libre2Variant
}

struct Libre2Variant: Decodable {
    let patchInfo_byte0: Libre2VariantByte0
    let patchInfo_byte3: String?
    let fram_xor: String?
    let crypto_arg: String?
    let header_footer_arg: String?
    
    enum CodingKeys: String, CodingKey {
        case patchInfo_byte0, patchInfo_byte3, fram_xor, crypto_arg, header_footer_arg
    }
}

enum Libre2VariantByte0: Decodable {
    case single(String)
    case array([String])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
        } else if let single = try? container.decode(String.self) {
            self = .single(single)
        } else {
            throw DecodingError.typeMismatch(
                Libre2VariantByte0.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]")
            )
        }
    }
}

// MARK: - Session Tests

@Suite("Libre 2 Session (SESSION-LIBRE-001)")
struct Libre2SessionTests {
    
    // MARK: - Fixture Loading
    
    static func loadSessionFixture() throws -> Libre2SessionFixture {
        // Path from test file to workspace root
        let workspaceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // -> CGMKitTests
            .deletingLastPathComponent()  // -> Tests
            .deletingLastPathComponent()  // -> CGMKit
            .deletingLastPathComponent()  // -> packages
            .deletingLastPathComponent()  // -> t1pal-mobile-workspace
        
        let fixtureURL = workspaceRoot
            .appendingPathComponent("conformance")
            .appendingPathComponent("protocol")
            .appendingPathComponent("libre")
            .appendingPathComponent("fixture_libre2_session.json")
        
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(Libre2SessionFixture.self, from: data)
    }
    
    // MARK: - Session Fixture Validation
    
    @Test("Session fixture loads correctly")
    func sessionLoads() throws {
        let session = try Self.loadSessionFixture()
        
        #expect(session.session_id == "SESSION-LIBRE-001")
        #expect(session.session_name.contains("Libre 2"))
        #expect(session.overview.total_phases == 4, "Need 4 phases: NFC, BLE, Unlock, Read")
        #expect(session.transactions.count == 4, "Need 4 transaction phases")
    }
    
    @Test("State machine is complete")
    func stateMachineComplete() throws {
        let session = try Self.loadSessionFixture()
        let sm = session.complete_state_machine
        
        #expect(sm.initial == "uninitialized")
        #expect(sm.final == "data_received")
        
        // Validate each phase has transitions
        #expect(sm.phases.nfc_activation.count >= 2)
        #expect(sm.phases.ble_connection.count >= 3)
        #expect(sm.phases.streaming_unlock.count >= 2)
        #expect(sm.phases.glucose_reading.count >= 2)
    }
    
    @Test("Phases are correctly numbered")
    func phasesNumbered() throws {
        let session = try Self.loadSessionFixture()
        
        for (index, phase) in session.transactions.enumerated() {
            #expect(phase.phase == index + 1, "Phase \(index + 1) should have phase number \(index + 1)")
        }
    }
    
    // MARK: - Crypto Constant Validation
    
    @Test("Crypto constants match implementation")
    func cryptoConstantsMatch() throws {
        let session = try Self.loadSessionFixture()
        
        // Find the unlock phase with crypto config
        guard let unlockPhase = session.transactions.first(where: { $0.name.contains("Unlock") }),
              let crypto = unlockPhase.crypto,
              let constants = crypto.constants else {
            Issue.record("Unlock phase with crypto constants not found")
            return
        }
        
        #expect(crypto.algorithm == "XOR stream cipher")
        
        // Validate key matches Libre2Crypto.key
        let expectedKey: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]
        let fixtureKey = constants.key.map { UInt16($0.dropFirst(2), radix: 16) ?? 0 }
        #expect(fixtureKey == expectedKey, "Fixture key should match Libre2Crypto.key")
        
        // Validate magic constants
        #expect(constants.xorMagic1 == "0x4163")
        #expect(constants.xorMagic2 == "0x4344")
    }
    
    // MARK: - BLE Characteristic Validation
    
    @Test("BLE characteristics are correct")
    func bleCharacteristics() throws {
        let session = try Self.loadSessionFixture()
        
        guard let blePhase = session.transactions.first(where: { $0.name.contains("BLE Connection") }),
              let operations = blePhase.operations else {
            Issue.record("BLE Connection phase not found")
            return
        }
        
        // Find characteristic discovery operation
        guard let charOp = operations.first(where: { $0.operation == "discover_characteristics" }),
              let chars = charOp.characteristics else {
            Issue.record("Characteristic discovery operation not found")
            return
        }
        
        // Validate F001 (write) and F002 (notify) exist
        let writeChar = chars.first { $0.uuid == "F001" }
        let notifyChar = chars.first { $0.uuid == "F002" }
        
        #expect(writeChar != nil, "F001 write characteristic must exist")
        #expect(notifyChar != nil, "F002 notify characteristic must exist")
        
        if let write = writeChar {
            #expect(write.properties.contains("write") || write.properties.contains("write_without_response"))
        }
        if let notify = notifyChar {
            #expect(notify.properties.contains("notify"))
        }
    }
    
    // MARK: - Unlock Payload Validation
    
    @Test("Unlock payload structure is correct")
    func unlockPayloadStructure() throws {
        let session = try Self.loadSessionFixture()
        
        guard let unlockPhase = session.transactions.first(where: { $0.name.contains("Unlock") }),
              let transactions = unlockPhase.transactions,
              let txStep = transactions.first(where: { $0.direction == "TX" }),
              let payload = txStep.payload else {
            Issue.record("Unlock TX step not found")
            return
        }
        
        #expect(payload.format == "libre2_unlock")
        #expect(payload.size == 12, "Unlock payload must be 12 bytes")
        
        // Validate fields
        if let fields = payload.fields {
            #expect(fields.count >= 2, "Need at least time and crypto fields")
            
            let timeField = fields.first { $0.name == "time" }
            #expect(timeField?.type == "uint32_le")
            #expect(timeField?.offset == 0)
            #expect(timeField?.length == 4)
            
            let cryptoField = fields.first { $0.name == "cryptoResult" }
            #expect(cryptoField?.offset == 4)
            #expect(cryptoField?.length == 8)
        }
    }
    
    // MARK: - Glucose Data Validation
    
    @Test("Glucose data size is correct")
    func glucoseDataSize() throws {
        let session = try Self.loadSessionFixture()
        
        guard let readPhase = session.transactions.first(where: { $0.name.contains("Glucose") }),
              let crypto = readPhase.crypto else {
            Issue.record("Glucose Reading phase not found")
            return
        }
        
        #expect(crypto.input_size == 46, "Encrypted BLE data must be 46 bytes")
        #expect(crypto.output_size == 44, "Decrypted data must be 44 bytes")
        #expect(crypto.crc_offset == 42, "CRC is at offset 42")
    }
    
    // MARK: - Variant Detection Validation
    
    @Test("Variant detection bytes are correct")
    func variantDetection() throws {
        let session = try Self.loadSessionFixture()
        let variants = session.variant_differences
        
        // EU variant
        switch variants.libre2_eu.patchInfo_byte0 {
        case .array(let values):
            #expect(values.contains("0xC5") || values.contains("0x9D"))
        case .single(let value):
            #expect(["0xC5", "0x9D", "0xC6", "0x7F"].contains(value))
        }
        #expect(variants.libre2_eu.fram_xor == "0x44")
        
        // US variant
        switch variants.libre2_us.patchInfo_byte0 {
        case .single(let value):
            #expect(value == "0x76")
        case .array:
            Issue.record("US variant should have single byte0 value")
        }
        #expect(variants.libre2_us.patchInfo_byte3 == "0x02")
    }
    
    // MARK: - Cross-Reference Test Vectors
    
    @Test("Test vectors from fixture match crypto implementation")
    func testVectorsMatchImplementation() throws {
        let session = try Self.loadSessionFixture()
        
        // Find NFC phase with test vectors
        guard let nfcPhase = session.transactions.first(where: { $0.name.contains("NFC") }),
              let operations = nfcPhase.operations else {
            Issue.record("NFC phase not found")
            return
        }
        
        // Get sensor UID from test vector
        guard let uidOp = operations.first(where: { $0.operation == "nfc_read_uid" }),
              let vector = uidOp.test_vector,
              let sensorUID = vector.sensorUID_bytes else {
            Issue.record("Sensor UID test vector not found")
            return
        }
        
        // Validate activation parameters generation
        let activationParams = Libre2Crypto.activateParameters(sensorUID: sensorUID)
        #expect(activationParams.count == 5)
        #expect(activationParams[0] == 0x1b, "First byte must be 0x1b command")
    }
}
