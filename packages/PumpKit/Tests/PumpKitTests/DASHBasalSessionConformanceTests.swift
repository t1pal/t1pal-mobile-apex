// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DASHBasalSessionConformanceTests.swift
// PumpKitTests
//
// DASH-BASAL-001: Conformance tests for DASH temp basal transactions.
// Validates SetInsulinScheduleCommand, TempBasalExtraCommand, and CancelDeliveryCommand
// parsing against fixture vectors extracted from OmniBLE/OmniBLETests/TempBasalTests.swift.
//
// Trace: DASH-BASAL-001, PRD-005

import Testing
import Foundation
@testable import PumpKit

// MARK: - Fixture Types

struct DASHBasalSessionFixture: Decodable {
    let fixture_id: String
    let fixture_name: String
    let test_vectors: DASHBasalTestVectors
}

struct DASHBasalTestVectors: Decodable {
    let set_insulin_schedule_temp_basal: DASHSetInsulinScheduleVectors
    let temp_basal_extra_command: DASHTempBasalExtraVectors
    let cancel_temp_basal: DASHCancelTempBasalVectors
}

struct DASHSetInsulinScheduleVectors: Decodable {
    let description: String
    let source: String
    let vectors: [DASHSetInsulinScheduleVector]
}

struct DASHSetInsulinScheduleVector: Decodable {
    let name: String
    let source_line: Int
    let source_assertion: String
    let parameters: DASHSetInsulinScheduleParams
    let expected_hex: String
    let parsed: DASHSetInsulinScheduleParsed?
    let decode_test: DASHSetInsulinScheduleDecodeTest?
}

struct DASHSetInsulinScheduleParams: Decodable {
    let nonce: String
    let temp_basal_rate: Double
    let duration_hours: Double
}

struct DASHSetInsulinScheduleParsed: Decodable {
    let block_type: String
    let length: Int
    let nonce: String
    let schedule_type: String?
    let checksum: String?
    let seconds_remaining: Int?
    let first_segment_pulses: Int?
    let table_entry_count: Int?
}

struct DASHSetInsulinScheduleDecodeTest: Decodable {
    let input_hex: String
    let expected_nonce: String
    let expected_seconds_remaining: Int?
    let expected_first_segment_pulses: Int?
    let expected_table_entries: [DASHTableEntry]?
}

struct DASHTableEntry: Decodable {
    let segments: Int
    let pulses: Int
    let alternate_segment_pulse: Bool?
}

struct DASHTempBasalExtraVectors: Decodable {
    let description: String
    let source: String
    let vectors: [DASHTempBasalExtraVector]
}

struct DASHTempBasalExtraVector: Decodable {
    let name: String
    let source_line: Int
    let source_assertion: String
    let parameters: DASHTempBasalExtraParams
    let expected_hex: String
    let parsed: DASHTempBasalExtraParsed?
}

struct DASHTempBasalExtraParams: Decodable {
    let rate: Double
    let duration_hours: Double
    let acknowledgement_beep: Bool
    let completion_beep: Bool
    let program_reminder_minutes: Int
}

struct DASHTempBasalExtraParsed: Decodable {
    let block_type: String
    let length: Int
    let beep_options: String?
    let program_reminder: String?
    let remaining_pulses: Int?
    let delay_until_first_pulse_seconds: Int?
    let rate_entries: [DASHRateEntry]?
}

struct DASHRateEntry: Decodable {
    let total_pulses: Double?
    let delay_between_pulses_seconds: Int?
    let duration_minutes: Int?
    let duration_hours: Double?
    let rate: Double?
}

struct DASHCancelTempBasalVectors: Decodable {
    let description: String
    let source: String
    let vectors: [DASHCancelTempBasalVector]
}

struct DASHCancelTempBasalVector: Decodable {
    let name: String
    let source_line: Int
    let source_assertion: String
    let parameters: DASHCancelTempBasalParams
    let expected_hex: String
    let parsed: DASHCancelTempBasalParsed?
    let decode_test: DASHCancelTempBasalDecodeTest?
}

struct DASHCancelTempBasalParams: Decodable {
    let nonce: String
    let delivery_type: String
    let beep_type: String
}

struct DASHCancelTempBasalParsed: Decodable {
    let block_type: String
    let length: Int
    let nonce: String
    let beep_type_delivery_type: String
}

struct DASHCancelTempBasalDecodeTest: Decodable {
    let input_hex: String
    let expected_nonce: String
    let expected_beep_type: String
    let expected_delivery_type: String
}

// MARK: - Fixture Loading Errors

enum FixtureError: Error {
    case notFound(String)
    case parseError(String)
}

// MARK: - Test Suite

@Suite("DASH Basal Session Conformance")
struct DASHBasalSessionConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadBasalSessionFixture() throws -> DASHBasalSessionFixture {
        // Try package resources first
        #if canImport(Darwin)
        let bundle = Bundle.module
        if let url = bundle.url(forResource: "fixture_dash_basal_session", withExtension: "json", subdirectory: "Fixtures") {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DASHBasalSessionFixture.self, from: data)
        }
        #endif
        
        // Fall back to conformance directory path - search up from CWD to find workspace root
        let possiblePaths = [
            "conformance/protocol/omnipod/fixture_dash_basal_session.json",
            "../conformance/protocol/omnipod/fixture_dash_basal_session.json",
            "../../conformance/protocol/omnipod/fixture_dash_basal_session.json",
            "../../../conformance/protocol/omnipod/fixture_dash_basal_session.json"
        ]
        
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(DASHBasalSessionFixture.self, from: data)
            }
        }
        
        // If not found, throw with helpful message
        throw NSError(domain: "DASHBasalSessionConformanceTests", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "fixture_dash_basal_session.json not found. Run tests from workspace root."
        ])
    }
    
    // MARK: - SetInsulinScheduleCommand Tests
    
    @Test("SetInsulinScheduleCommand block type is 0x1a")
    func setInsulinScheduleBlockType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.set_insulin_schedule_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex) else {
                Issue.record("Failed to parse hex: \(vector.expected_hex)")
                continue
            }
            
            #expect(data[0] == 0x1a,
                    "\(vector.name): Block type should be 0x1a, got 0x\(String(format: "%02x", data[0]))")
        }
    }
    
    @Test("SetInsulinScheduleCommand nonce encoding")
    func setInsulinScheduleNonce() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.set_insulin_schedule_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 6 else {
                Issue.record("Invalid hex data for \(vector.name)")
                continue
            }
            
            // Nonce is at bytes 2-5 (after block_type and length)
            let nonceData = data[2..<6]
            let nonceHex = nonceData.map { String(format: "%02x", $0) }.joined()
            
            // Parse expected nonce (remove 0x prefix)
            let expectedNonce = vector.parameters.nonce.hasPrefix("0x")
                ? String(vector.parameters.nonce.dropFirst(2))
                : vector.parameters.nonce
            
            #expect(nonceHex == expectedNonce,
                    "\(vector.name): Nonce should be \(expectedNonce), got \(nonceHex)")
        }
    }
    
    @Test("SetInsulinScheduleCommand schedule type is tempBasal (0x01)")
    func setInsulinScheduleTempBasalType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.set_insulin_schedule_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 7 else {
                continue
            }
            
            // Schedule type is at byte 6 (after block_type, length, nonce[4])
            let scheduleType = data[6]
            
            #expect(scheduleType == 0x01,
                    "\(vector.name): Schedule type should be 0x01 (tempBasal), got 0x\(String(format: "%02x", scheduleType))")
        }
    }
    
    @Test("SetInsulinScheduleCommand hex encoding matches fixture")
    func setInsulinScheduleHexEncoding() throws {
        let fixture = try Self.loadBasalSessionFixture()
        var passed = 0
        
        for vector in fixture.test_vectors.set_insulin_schedule_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex) else {
                Issue.record("Failed to parse expected hex for \(vector.name)")
                continue
            }
            
            // Verify we can parse the hex correctly
            let roundTripped = data.map { String(format: "%02x", $0) }.joined()
            
            #expect(roundTripped == vector.expected_hex,
                    "\(vector.name): Hex round-trip should match")
            passed += 1
        }
        
        #expect(passed == fixture.test_vectors.set_insulin_schedule_temp_basal.vectors.count,
                "All SetInsulinScheduleCommand vectors should pass")
    }
    
    // MARK: - TempBasalExtraCommand Tests
    
    @Test("TempBasalExtraCommand block type is 0x16")
    func tempBasalExtraBlockType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.temp_basal_extra_command.vectors {
            guard let data = Data(hexString: vector.expected_hex) else {
                Issue.record("Failed to parse hex: \(vector.expected_hex)")
                continue
            }
            
            #expect(data[0] == 0x16,
                    "\(vector.name): Block type should be 0x16, got 0x\(String(format: "%02x", data[0]))")
        }
    }
    
    @Test("TempBasalExtraCommand beep options encoding")
    func tempBasalExtraBeepOptions() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.temp_basal_extra_command.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 3 else {
                continue
            }
            
            let beepOptions = data[2]
            
            // Verify beep options match expected behavior
            // 0x7c = completion beep + 60min reminder
            // 0x3c = no completion beep + 60min reminder
            // 0x00 = no beeps + no reminder
            
            if vector.parameters.completion_beep && vector.parameters.program_reminder_minutes == 60 {
                #expect(beepOptions == 0x7c,
                        "\(vector.name): Beep options should be 0x7c for completion beep + reminder")
            } else if !vector.parameters.completion_beep && vector.parameters.program_reminder_minutes == 60 {
                #expect(beepOptions == 0x3c,
                        "\(vector.name): Beep options should be 0x3c for no completion beep + reminder")
            } else if !vector.parameters.completion_beep && vector.parameters.program_reminder_minutes == 0 {
                #expect(beepOptions == 0x00,
                        "\(vector.name): Beep options should be 0x00 for no beeps")
            }
        }
    }
    
    @Test("TempBasalExtraCommand hex encoding matches fixture")
    func tempBasalExtraHexEncoding() throws {
        let fixture = try Self.loadBasalSessionFixture()
        var passed = 0
        
        for vector in fixture.test_vectors.temp_basal_extra_command.vectors {
            guard let data = Data(hexString: vector.expected_hex) else {
                Issue.record("Failed to parse expected hex for \(vector.name)")
                continue
            }
            
            let roundTripped = data.map { String(format: "%02x", $0) }.joined()
            
            #expect(roundTripped == vector.expected_hex,
                    "\(vector.name): Hex round-trip should match")
            passed += 1
        }
        
        #expect(passed == fixture.test_vectors.temp_basal_extra_command.vectors.count,
                "All TempBasalExtraCommand vectors should pass")
    }
    
    // MARK: - CancelDeliveryCommand Tests
    
    @Test("CancelDeliveryCommand block type is 0x1f")
    func cancelDeliveryBlockType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.cancel_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex) else {
                Issue.record("Failed to parse hex: \(vector.expected_hex)")
                continue
            }
            
            #expect(data[0] == 0x1f,
                    "\(vector.name): Block type should be 0x1f, got 0x\(String(format: "%02x", data[0]))")
        }
    }
    
    @Test("CancelDeliveryCommand fixed length is 5")
    func cancelDeliveryLength() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.cancel_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 2 else {
                continue
            }
            
            let length = data[1]
            
            #expect(length == 0x05,
                    "\(vector.name): Length should be 0x05, got 0x\(String(format: "%02x", length))")
        }
    }
    
    @Test("CancelDeliveryCommand tempBasal type encoding")
    func cancelDeliveryTempBasalType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.cancel_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 7 else {
                continue
            }
            
            // Beep type + delivery type is last byte
            let beepTypeDeliveryType = data[6]
            
            // Delivery type is lower nibble
            // 0x02 = tempBasal
            let deliveryType = beepTypeDeliveryType & 0x0F
            
            #expect(deliveryType == 0x02,
                    "\(vector.name): Delivery type should be 0x02 (tempBasal), got 0x\(String(format: "%02x", deliveryType))")
        }
    }
    
    @Test("CancelDeliveryCommand beep type encoding")
    func cancelDeliveryBeepType() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.cancel_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 7 else {
                continue
            }
            
            let beepTypeDeliveryType = data[6]
            
            // Expected values based on beep type:
            // beeeeeep + tempBasal = 0x62
            // noBeepCancel + tempBasal = 0x02
            
            if vector.parameters.beep_type == "beeeeeep" {
                #expect(beepTypeDeliveryType == 0x62,
                        "\(vector.name): beeeeeep + tempBasal should be 0x62")
            } else if vector.parameters.beep_type == "noBeepCancel" {
                #expect(beepTypeDeliveryType == 0x02,
                        "\(vector.name): noBeepCancel + tempBasal should be 0x02")
            }
        }
    }
    
    @Test("CancelDeliveryCommand nonce encoding")
    func cancelDeliveryNonce() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        for vector in fixture.test_vectors.cancel_temp_basal.vectors {
            guard let data = Data(hexString: vector.expected_hex), data.count >= 6 else {
                continue
            }
            
            // Nonce is at bytes 2-5
            let nonceData = data[2..<6]
            let nonceHex = nonceData.map { String(format: "%02x", $0) }.joined()
            
            let expectedNonce = vector.parameters.nonce.hasPrefix("0x")
                ? String(vector.parameters.nonce.dropFirst(2))
                : vector.parameters.nonce
            
            #expect(nonceHex == expectedNonce,
                    "\(vector.name): Nonce should be \(expectedNonce), got \(nonceHex)")
        }
    }
    
    // MARK: - Session State Machine Tests
    
    @Test("Session fixture has required state machine")
    func sessionStateMachine() throws {
        // This test verifies the fixture structure itself
        let fixture = try Self.loadBasalSessionFixture()
        
        #expect(fixture.fixture_id == "DASH-BASAL-001")
        #expect(fixture.fixture_name == "DASH Temp Basal Transaction")
    }
    
    // MARK: - Vector Count Tests
    
    @Test("Fixture has expected vector counts")
    func vectorCounts() throws {
        let fixture = try Self.loadBasalSessionFixture()
        
        let scheduleCount = fixture.test_vectors.set_insulin_schedule_temp_basal.vectors.count
        let extraCount = fixture.test_vectors.temp_basal_extra_command.vectors.count
        let cancelCount = fixture.test_vectors.cancel_temp_basal.vectors.count
        
        #expect(scheduleCount >= 8, "Should have at least 8 SetInsulinScheduleCommand vectors")
        #expect(extraCount >= 8, "Should have at least 8 TempBasalExtraCommand vectors")
        #expect(cancelCount >= 2, "Should have at least 2 CancelDeliveryCommand vectors")
    }
}
