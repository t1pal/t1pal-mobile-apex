// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosPythonCompatTests.swift
// PumpKitTests
//
// EROS-SYNTH-009: PYTHON-COMPAT conformance tests for Omnipod Eros protocol.
// Validates Swift parsing against Python eros_parsers.py using fixture data.
//
// These tests load JSON fixtures from tools/eros-cli/fixtures/ and verify
// that Swift parsing produces identical results to the Python reference.
//
// Trace: EROS-SYNTH-009, PRD-005

import Testing
import Foundation
@testable import PumpKit

// MARK: - CRC Fixture Types

struct ErosCRCFixture: Decodable {
    let crc16_vectors: [ErosCRC16Vector]
    let crc8_vectors: [ErosCRC8Vector]
}

struct ErosCRC16Vector: Decodable {
    let id: String
    let description: String
    let source: String
    let hex: String
    let expectedCRC16: String
    let expectedCRC16Decimal: Int
}

struct ErosCRC8Vector: Decodable {
    let id: String
    let description: String
    let source: String
    let hex: String
    let expectedCRC8: String
    let expectedCRC8Decimal: Int
}

// MARK: - Packet Fixture Types

struct ErosPacketFixture: Decodable {
    let packet_vectors: [ErosPacketVector]
    let crc8_vectors: [ErosPacketCRC8Vector]
}

struct ErosPacketVector: Decodable {
    let id: String
    let description: String
    let source: String
    let hex: String?
    let expected: ErosPacketExpected?
    let longMessageHex: String?
    let fragment: ErosPacketFragment?
}

struct ErosPacketExpected: Decodable {
    let address: String?
    let addressDecimal: UInt32?
    let packetType: String?
    let packetTypeRaw: Int?
    let sequenceNum: Int?
    let data: String?
    let dataLen: Int?
    let crc8: String?
}

struct ErosPacketFragment: Decodable {
    let index: Int
    let offsetStart: Int?
    let dataHex: String
    let dataLen: Int
}

struct ErosPacketCRC8Vector: Decodable {
    let id: String
    let description: String
    let source: String?
    let inputHex: String
    let expectedCrc8: String
    let expectedCrc8Decimal: Int
}

// MARK: - Bolus Fixture Types

struct ErosBolusFixture: Decodable {
    let immediate_bolus_vectors: [ErosBolusVector]
    let extended_bolus_vectors: [ErosBolusVector]?
}

struct ErosBolusVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let setInsulinScheduleHex: String?
    let bolusExtraHex: String?
    let expected: ErosBolusExpected
}

struct ErosBolusExpected: Decodable {
    let type: String
    let nonce: String?
    let nonceDecimal: UInt32?
    let units: Double?
    let timeBetweenPulses: Double?
    let timeBetweenPulsesUs: Int?
    let acknowledgementBeep: Bool?
    let completionBeep: Bool?
    let programReminderInterval: Int?
    let extendedUnits: Double?
    let extendedDuration: Double?
    let extendedDurationHours: Double?
    let tableEntries: [ErosBolusTableEntry]?
}

struct ErosBolusTableEntry: Decodable {
    let segments: Int
    let pulses: Int
    let alternateSegmentPulse: Bool
}

// MARK: - Message Fixture Types

struct ErosMessageFixture: Decodable {
    let message_vectors: [ErosMessageVector]
}

struct ErosMessageVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let hex: String?
    let expectedHex: String?
    let input: ErosMessageInput?
    let expected: ErosMessageExpected?
    let packets: [ErosMessagePacketInput]?
}

struct ErosMessageInput: Decodable {
    let address: String
    let addressDecimal: UInt32
    let sequenceNum: Int
    let expectFollowOn: Bool
    let messageBlocks: [ErosMessageBlockInput]
}

struct ErosMessageBlockInput: Decodable {
    let type: String
    let typeRaw: String
    let data: String
}

struct ErosMessageExpected: Decodable {
    let address: String?
    let addressDecimal: UInt32?
    let sequenceNum: Int?
    let expectFollowOn: Bool?
    let messageBlocks: [ErosMessageBlockExpected]?
    let totalLength: Int?
}

struct ErosMessageBlockExpected: Decodable {
    let type: String
    let typeRaw: String?
    let data: String?
    let decoded: ErosMessageBlockDecoded?
}

struct ErosMessageBlockDecoded: Decodable {
    let deliveryStatus: String?
    let podProgressStatus: String?
    let timeActiveMinutes: Int?
    let reservoirLevel: Double?
    let insulinDelivered: Double?
    let bolusNotDelivered: Double?
    let lastProgrammingMessageSeqNum: Int?
    let alerts: [String]?
}

struct ErosMessagePacketInput: Decodable {
    let type: String
    let hex: String
    let dataHex: String
}

// MARK: - Temp Basal Fixture Types

struct ErosTempBasalFixture: Decodable {
    let set_insulin_schedule_vectors: [ErosTempBasalVector]
    let temp_basal_extra_vectors: [ErosTempBasalExtraVector]?
    let cancel_temp_basal_vectors: [ErosCancelTempBasalVector]?
}

struct ErosTempBasalVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let hex: String
    let expected: ErosTempBasalExpected
}

struct ErosTempBasalExpected: Decodable {
    let type: String
    let nonce: String?
    let nonceDecimal: UInt32?
    let rate: Double?
    let duration: Double?
    let durationMinutes: Int?
    let segments: Int?
    let tableEntries: [ErosTempBasalTableEntry]?
}

struct ErosTempBasalTableEntry: Decodable {
    let segments: Int
    let pulses: Int
    let alternateSegmentPulse: Bool
}

struct ErosTempBasalExtraVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let hex: String
    let expected: ErosTempBasalExtraExpected
}

struct ErosTempBasalExtraExpected: Decodable {
    let type: String
    let rate: Double?
    let durationMinutes: Int?
    let remainingPulses: Double?
}

struct ErosCancelTempBasalVector: Decodable {
    let id: String
    let description: String
    let source: String
    let hex: String
    let expected: ErosCancelExpected
}

struct ErosCancelExpected: Decodable {
    let type: String
    let nonce: String?
    let nonceDecimal: UInt32?
    let deliveryType: String?
}

// MARK: - Schedule Fixture Types

struct ErosScheduleFixture: Decodable {
    let insulin_table_entry_vectors: [ErosInsulinTableEntryVector]?
    let set_basal_schedule_vectors: [ErosBasalScheduleVector]?
    let basal_schedule_extra_vectors: [ErosBasalExtraVector]?
    let cancel_basal_vectors: [ErosCancelBasalVector]?
}

struct ErosInsulinTableEntryVector: Decodable {
    let id: String
    let description: String
    let source: String
    let input: ErosInsulinTableEntryInput
    let expected: ErosInsulinTableEntryExpected
}

struct ErosInsulinTableEntryInput: Decodable {
    let segments: Int
    let pulses: Int
    let alternateSegmentPulse: Bool
}

struct ErosInsulinTableEntryExpected: Decodable {
    let checksum: String
    let checksumDecimal: Int
    let notes: String?
}

struct ErosBasalScheduleVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let hex: String?
    let expected: ErosBasalScheduleExpected
}

struct ErosBasalScheduleExpected: Decodable {
    let type: String?
    let nonce: String?
    let nonceDecimal: UInt32?
    let rates: [Double]?
    let currentSegment: String?  // Changed to String - fixture has "0x20"
    let pulsesRemaining: Int?
    let tableEntries: [ErosScheduleTableEntry]?
}

struct ErosScheduleTableEntry: Decodable {
    let segments: Int?
    let pulses: Int?
    let alternateSegmentPulse: Bool?
    let rate: Double?
}

struct ErosBasalExtraVector: Decodable {
    let id: String
    let description: String
    let source: String
    let operation: String
    let hex: String?
    let expected: ErosBasalExtraExpected?
}

struct ErosBasalExtraExpected: Decodable {
    let type: String?
    let currentEntryIndex: Int?
    let remainingPulses: Double?
    let delaySeconds: Double?
    let entries: [ErosBasalExtraEntry]?
    let hex: String?
}

struct ErosBasalExtraEntry: Decodable {
    let totalPulses: Double?
    let delayBetweenSeconds: Double?
    let rate: Double?
}

struct ErosCancelBasalVector: Decodable {
    let id: String
    let description: String
    let source: String
    let hex: String
    let expected: ErosCancelExpected
}

// MARK: - PYTHON-COMPAT Conformance Tests

@Suite("Eros PYTHON-COMPAT Tests (EROS-SYNTH-009)")
struct ErosPythonCompatTests {
    
    // MARK: - Fixture Loading
    
    enum FixtureError: Error {
        case notFound(String)
        case invalidHex(String)
        case parseError(String)
    }
    
    static func loadCRCFixture() throws -> ErosCRCFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_crc", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_crc.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosCRCFixture.self, from: data)
    }
    
    static func loadPacketFixture() throws -> ErosPacketFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_packets", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_packets.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosPacketFixture.self, from: data)
    }
    
    static func loadBolusFixture() throws -> ErosBolusFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_bolus", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_bolus.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosBolusFixture.self, from: data)
    }
    
    static func loadMessageFixture() throws -> ErosMessageFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_messages", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_messages.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosMessageFixture.self, from: data)
    }
    
    static func loadTempBasalFixture() throws -> ErosTempBasalFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_tempbasal", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_tempbasal.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosTempBasalFixture.self, from: data)
    }
    
    static func loadScheduleFixture() throws -> ErosScheduleFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_eros_schedule", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_eros_schedule.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ErosScheduleFixture.self, from: data)
    }
    
    // MARK: - CRC16 Tests (PYTHON-COMPAT)
    
    @Test("CRC16 matches Python eros_parsers.crc16()")
    func crc16MatchesPython() throws {
        let fixture = try Self.loadCRCFixture()
        
        for vector in fixture.crc16_vectors {
            guard let data = Data(erosHex: vector.hex) else {
                throw FixtureError.invalidHex(vector.hex)
            }
            
            let computed = data.erosCRC16()
            #expect(computed == UInt16(vector.expectedCRC16Decimal),
                    "CRC16 mismatch for \(vector.id): expected \(vector.expectedCRC16), got 0x\(String(computed, radix: 16))")
        }
    }
    
    // MARK: - CRC8 Tests (PYTHON-COMPAT)
    
    @Test("CRC8 matches Python eros_parsers.crc8()")
    func crc8MatchesPython() throws {
        let fixture = try Self.loadCRCFixture()
        
        for vector in fixture.crc8_vectors {
            guard let data = Data(erosHex: vector.hex) else {
                throw FixtureError.invalidHex(vector.hex)
            }
            
            let computed = data.erosCRC8()
            #expect(computed == UInt8(vector.expectedCRC8Decimal),
                    "CRC8 mismatch for \(vector.id): expected \(vector.expectedCRC8), got 0x\(String(computed, radix: 16))")
        }
    }
    
    // MARK: - Packet Tests (PYTHON-COMPAT)
    
    @Test("Packet CRC8 matches Python")
    func packetCRC8MatchesPython() throws {
        let fixture = try Self.loadPacketFixture()
        
        for vector in fixture.crc8_vectors {
            guard let data = Data(erosHex: vector.inputHex) else {
                throw FixtureError.invalidHex(vector.inputHex)
            }
            
            let computed = data.erosCRC8()
            #expect(computed == UInt8(vector.expectedCrc8Decimal),
                    "Packet CRC8 mismatch for \(vector.id): expected \(vector.expectedCrc8), got 0x\(String(computed, radix: 16))")
        }
    }
    
    @Test("Packet decode matches Python parse_eros_packet()")
    func packetDecodeMatchesPython() throws {
        let fixture = try Self.loadPacketFixture()
        
        for vector in fixture.packet_vectors {
            guard let hex = vector.hex,
                  let expected = vector.expected,
                  let data = Data(erosHex: hex) else {
                continue // Skip fragmentation tests
            }
            
            // Decode packet
            let packet = try ErosPacket(encodedData: data)
            
            // Verify address
            if let expectedAddress = expected.addressDecimal {
                #expect(packet.address == expectedAddress,
                        "\(vector.id): address mismatch")
            }
            
            // Verify sequence number
            if let expectedSeq = expected.sequenceNum {
                #expect(packet.sequenceNum == expectedSeq,
                        "\(vector.id): sequenceNum mismatch")
            }
            
            // Verify packet type
            if let expectedType = expected.packetType {
                let actualType: String
                switch packet.packetType {
                case .pod: actualType = "pod"
                case .pdm: actualType = "pdm"
                case .con: actualType = "con"
                case .ack: actualType = "ack"
                }
                #expect(actualType == expectedType,
                        "\(vector.id): packetType mismatch - expected \(expectedType), got \(actualType)")
            }
            
            // Verify data
            if let expectedData = expected.data {
                #expect(packet.dataHex == expectedData,
                        "\(vector.id): data mismatch - expected \(expectedData), got \(packet.dataHex)")
            }
        }
    }
    
    @Test("Packet encode matches Python encode_eros_packet()")
    func packetEncodeMatchesPython() throws {
        let fixture = try Self.loadPacketFixture()
        
        for vector in fixture.packet_vectors {
            guard let expectedHex = vector.hex,
                  let expected = vector.expected,
                  let expectedData = expected.data,
                  let messageData = Data(erosHex: expectedData),
                  let expectedAddress = expected.addressDecimal,
                  let expectedSeq = expected.sequenceNum,
                  let expectedType = expected.packetType else {
                continue
            }
            
            let packetType: ErosPacketType
            switch expectedType {
            case "pod": packetType = .pod
            case "pdm": packetType = .pdm
            case "con": packetType = .con
            case "ack": packetType = .ack
            default: continue
            }
            
            let packet = ErosPacket(
                address: expectedAddress,
                packetType: packetType,
                sequenceNum: expectedSeq,
                data: messageData
            )
            
            let encoded = packet.encoded()
            #expect(encoded.erosHex == expectedHex,
                    "\(vector.id): encoded packet mismatch - expected \(expectedHex), got \(encoded.erosHex)")
        }
    }
    
    // MARK: - Bolus Command Tests (PYTHON-COMPAT)
    
    @Test("Bolus command parsing matches Python")
    func bolusCommandMatchesPython() throws {
        let fixture = try Self.loadBolusFixture()
        
        for vector in fixture.immediate_bolus_vectors {
            // Test BolusExtraCommand parsing
            if let bolusExtraHex = vector.bolusExtraHex,
               let data = Data(erosHex: bolusExtraHex) {
                // Verify basic structure
                #expect(data[0] == 0x17, "\(vector.id): BolusExtraCommand type should be 0x17")
                
                if let expectedUnits = vector.expected.units {
                    // Pulses from bytes 3-4 (big-endian) divided by 10, then * 0.05 for units
                    // Format: 17 LL BB NNNN XXXXXXXX YYYY ZZZZZZZZ
                    //         [0][1][2][3-4][5-8]   [9-10][11-14]
                    let pulsesTens = UInt16(data[3]) << 8 | UInt16(data[4])
                    let pulses = Double(pulsesTens) / 10.0
                    let units = pulses * 0.05
                    #expect(abs(units - expectedUnits) < 0.01,
                            "\(vector.id): units mismatch - expected \(expectedUnits), got \(units)")
                }
                
                if let expectedAck = vector.expected.acknowledgementBeep {
                    // Beep byte format: (ack << 7) | (completion << 6) | (reminder & 0x3F)
                    let ackBeep = (data[2] & 0x80) != 0
                    #expect(ackBeep == expectedAck,
                            "\(vector.id): acknowledgementBeep mismatch")
                }
                
                if let expectedCompletion = vector.expected.completionBeep {
                    // Beep byte format: (ack << 7) | (completion << 6) | (reminder & 0x3F)
                    let completionBeep = (data[2] & 0x40) != 0
                    #expect(completionBeep == expectedCompletion,
                            "\(vector.id): completionBeep mismatch")
                }
            }
            
            // Test SetInsulinScheduleCommand parsing
            if let setInsulinHex = vector.setInsulinScheduleHex,
               let data = Data(erosHex: setInsulinHex) {
                #expect(data[0] == 0x1a, "\(vector.id): SetInsulinScheduleCommand type should be 0x1a")
                
                if let expectedNonce = vector.expected.nonceDecimal {
                    let nonce = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                                UInt32(data[4]) << 8 | UInt32(data[5])
                    #expect(nonce == expectedNonce,
                            "\(vector.id): nonce mismatch - expected \(expectedNonce), got \(nonce)")
                }
            }
        }
    }
    
    // MARK: - Message Tests (PYTHON-COMPAT)
    
    @Test("Message CRC16 matches Python")
    func messageCRC16MatchesPython() throws {
        let fixture = try Self.loadMessageFixture()
        
        for vector in fixture.message_vectors {
            // Test encoding case
            if vector.operation == "encode",
               let expectedHex = vector.expectedHex,
               let data = Data(erosHex: expectedHex) {
                // CRC16 is last 2 bytes
                let bodyData = data.dropLast(2)
                let expectedCRC = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
                let computed = bodyData.erosCRC16()
                
                #expect(computed == expectedCRC,
                        "\(vector.id): CRC16 mismatch - expected 0x\(String(expectedCRC, radix: 16)), got 0x\(String(computed, radix: 16))")
            }
            
            // Test decoding case
            if vector.operation == "decode",
               let hex = vector.hex,
               let data = Data(erosHex: hex) {
                // Verify CRC
                let bodyData = data.dropLast(2)
                let expectedCRC = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
                let computed = bodyData.erosCRC16()
                
                #expect(computed == expectedCRC,
                        "\(vector.id): CRC16 mismatch - expected 0x\(String(expectedCRC, radix: 16)), got 0x\(String(computed, radix: 16))")
                
                // Verify address and sequence if available
                if let expected = vector.expected,
                   let expectedAddress = expected.addressDecimal,
                   let expectedSeq = expected.sequenceNum {
                    let address = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 |
                                  UInt32(data[2]) << 8 | UInt32(data[3])
                    #expect(address == expectedAddress,
                            "\(vector.id): address mismatch")
                    
                    // Verify sequence number
                    let control = data[4]
                    let seq = Int((control >> 2) & 0x0F)
                    #expect(seq == expectedSeq,
                            "\(vector.id): sequenceNum mismatch - expected \(expectedSeq), got \(seq)")
                }
            }
        }
    }
    
    // MARK: - Temp Basal Tests (PYTHON-COMPAT)
    
    @Test("Temp basal parsing matches Python")
    func tempBasalMatchesPython() throws {
        let fixture = try Self.loadTempBasalFixture()
        
        for vector in fixture.set_insulin_schedule_vectors {
            guard let data = Data(erosHex: vector.hex) else {
                continue
            }
            
            let vectorId = String(vector.id)
            #expect(data[0] == 0x1a, Comment(rawValue: "\(vectorId): SetInsulinScheduleCommand type should be 0x1a"))
            
            // Delivery type should be 0x01 for temp basal
            #expect(data[6] == 0x01, Comment(rawValue: "\(vectorId): delivery type should be 0x01 (temp basal)"))
            
            if let expectedNonce = vector.expected.nonceDecimal {
                let b2 = UInt32(data[2])
                let b3 = UInt32(data[3])
                let b4 = UInt32(data[4])
                let b5 = UInt32(data[5])
                let nonce = (b2 << 24) | (b3 << 16) | (b4 << 8) | b5
                #expect(nonce == expectedNonce, Comment(rawValue: "\(vectorId): nonce mismatch"))
            }
        }
    }
    
    // MARK: - Basal Schedule Tests (PYTHON-COMPAT)
    
    @Test("Basal schedule parsing matches Python")
    func basalScheduleMatchesPython() throws {
        let fixture = try Self.loadScheduleFixture()
        
        // Test insulin table entry checksums
        if let entryVectors = fixture.insulin_table_entry_vectors {
            for vector in entryVectors {
                // Formula: checksumPerSegment = (pulses & 0xff) + (pulses >> 8)
                //          checksum = checksumPerSegment * segments + (alternate ? segments / 2 : 0)
                let input = vector.input
                let checksumPerSegment = (input.pulses & 0xff) + (input.pulses >> 8)
                let checksum = checksumPerSegment * input.segments + (input.alternateSegmentPulse ? input.segments / 2 : 0)
                let expected = vector.expected.checksumDecimal
                
                #expect(checksum == expected, "Checksum mismatch for \(vector.id)")
            }
        }
        
        // Test set insulin schedule vectors
        if let scheduleVectors = fixture.set_basal_schedule_vectors {
            for vector in scheduleVectors {
                guard let hexStr = vector.hex,
                      let data = Data(erosHex: hexStr) else {
                    continue
                }
                
                let vectorId = vector.id
                #expect(data[0] == 0x1a, "SetInsulinScheduleCommand type should be 0x1a for \(vectorId)")
                
                // Delivery type should be 0x00 for scheduled basal
                #expect(data[6] == 0x00, "Delivery type should be 0x00 (scheduled basal) for \(vectorId)")
                
                if let expectedNonce = vector.expected.nonceDecimal {
                    let b2 = UInt32(data[2])
                    let b3 = UInt32(data[3])
                    let b4 = UInt32(data[4])
                    let b5 = UInt32(data[5])
                    let nonce = (b2 << 24) | (b3 << 16) | (b4 << 8) | b5
                    #expect(nonce == expectedNonce, "Nonce mismatch for \(vectorId)")
                }
                
                if let expectedSegmentStr = vector.expected.currentSegment {
                    // Parse hex string like "0x20" to Int
                    let expectedSegment: Int
                    if expectedSegmentStr.hasPrefix("0x") {
                        expectedSegment = Int(expectedSegmentStr.dropFirst(2), radix: 16) ?? -1
                    } else {
                        expectedSegment = Int(expectedSegmentStr) ?? -1
                    }
                    let currentSegment = Int(data[9])
                    #expect(currentSegment == expectedSegment, "CurrentSegment mismatch for \(vectorId)")
                }
            }
        }
    }
}

// MARK: - Fixture Count Summary Test

@Suite("Eros Fixture Coverage (EROS-SYNTH-009)")
struct ErosFixtureCoverageTests {
    
    @Test("Core fixtures load successfully")
    func coreFixturesLoad() throws {
        // CRC fixture - most important for PYTHON-COMPAT
        let crc = try ErosPythonCompatTests.loadCRCFixture()
        #expect(crc.crc16_vectors.count > 0, "CRC16 vectors should not be empty")
        #expect(crc.crc8_vectors.count > 0, "CRC8 vectors should not be empty")
        
        // Packet fixture
        let packets = try ErosPythonCompatTests.loadPacketFixture()
        #expect(packets.packet_vectors.count > 0, "Packet vectors should not be empty")
        
        // Bolus fixture
        let bolus = try ErosPythonCompatTests.loadBolusFixture()
        #expect(bolus.immediate_bolus_vectors.count > 0, "Bolus vectors should not be empty")
        
        // Message fixture
        let messages = try ErosPythonCompatTests.loadMessageFixture()
        #expect(messages.message_vectors.count > 0, "Message vectors should not be empty")
        
        // Temp basal fixture
        let tempBasal = try ErosPythonCompatTests.loadTempBasalFixture()
        #expect(tempBasal.set_insulin_schedule_vectors.count > 0, "Temp basal vectors should not be empty")
    }
    
    @Test("Fixture vector counts for core fixtures")
    func fixtureVectorCounts() throws {
        let crc = try ErosPythonCompatTests.loadCRCFixture()
        let packets = try ErosPythonCompatTests.loadPacketFixture()
        let bolus = try ErosPythonCompatTests.loadBolusFixture()
        let messages = try ErosPythonCompatTests.loadMessageFixture()
        let tempBasal = try ErosPythonCompatTests.loadTempBasalFixture()
        
        // Report vector counts for traceability
        let totalVectors = crc.crc16_vectors.count + crc.crc8_vectors.count +
                          packets.packet_vectors.count + packets.crc8_vectors.count +
                          bolus.immediate_bolus_vectors.count +
                          messages.message_vectors.count +
                          tempBasal.set_insulin_schedule_vectors.count
        
        #expect(totalVectors >= 20, "Should have at least 20 test vectors across core fixtures")
    }
}
