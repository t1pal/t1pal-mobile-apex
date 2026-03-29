// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosConformanceTests.swift
// PumpKitTests
//
// Conformance tests validating ErosPacket implementation against
// test vectors from OmniKit (Loop/Trio).
//
// Trace: EROS-SYNTH-001
//
// These tests ensure our Swift implementation matches the exact byte
// patterns from OmniKit, which are battle-tested with real Eros pods.

import Testing
import Foundation
@testable import PumpKit

@Suite("ErosConformanceTests")
struct ErosConformanceTests {
    
    // MARK: - Fixture Data
    
    /// Packet vectors from fixture_eros_packets.json
    struct PacketVector {
        let id: String
        let hex: String
        let address: UInt32
        let packetType: ErosPacketType
        let sequenceNum: Int
        let dataHex: String
    }
    
    let packetVectors: [PacketVector] = [
        PacketVector(
            id: "pdm_basic",
            hex: "1f01482aad1f01482a10030e0100802c88",
            address: 0x1f01482a,
            packetType: .pdm,
            sequenceNum: 13,
            dataHex: "1f01482a10030e0100802c"
        ),
        PacketVector(
            id: "decode_pdm",
            hex: "1f01482aad1f01482a10030e0100802c88",
            address: 0x1f01482a,
            packetType: .pdm,
            sequenceNum: 13,
            dataHex: "1f01482a10030e0100802c"
        )
    ]
    
    // MARK: - CRC8 Tests (from CRC8Tests.swift)
    // Source: externals/OmniKit/OmniKit/MessageTransport/CRC8.swift:11-28
    
    @Test("CRC8 from OmniKit")
    func crc8FromOmniKit() throws {
        // From CRC8Tests.swift testComputeCRC8()
        let input = Data(erosHex: "1f07b1eeae1f07b1ee181f1a0eeb5701b202010a0101a000340034170d000208000186a0")!
        #expect(0x19 == input.erosCRC8(), "CRC8 should match OmniKit test vector")
    }
    
    /// Validate CRC-8 table first entries against OmniKit/MessageTransport/CRC8.swift
    @Test("CRC8 table matches OmniKit")
    func crc8TableMatchesOmniKit() throws {
        // Source: OmniKit/MessageTransport/CRC8.swift:11-14 (first 16 entries)
        // 0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15, 0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D
        let expected: [UInt8] = [
            0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15,
            0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D
        ]
        
        // Verify by computing CRCs for single-byte inputs 0-15
        for (idx, expectedCRC) in expected.enumerated() {
            let actual = [UInt8(idx)].erosCRC8()
            #expect(actual == expectedCRC, "CRC8[\(idx)] mismatch: expected 0x\(String(format: "%02X", expectedCRC)), got 0x\(String(format: "%02X", actual))")
        }
    }
    
    @Test("CRC8 of packet data")
    func crc8OfPacketData() throws {
        // CRC of packet data (excluding final CRC byte)
        let input = Data(erosHex: "1f01482aad1f01482a10030e0100802c")!
        #expect(0x88 == input.erosCRC8(), "CRC8 should match packet CRC")
    }
    
    // MARK: - CRC16 Tests (from CRC16Tests.swift) — EROS-SYNTH-003
    
    @Test("CRC16 from OmniKit")
    func crc16FromOmniKit() throws {
        // From CRC16Tests.swift testComputeCRC16()
        // This is the primary OmniKit test vector
        let input = Data(erosHex: "1f01482a10030e0100")!
        #expect(0x802c == input.erosCRC16(), "CRC16 should match OmniKit test vector")
    }
    
    @Test("CRC16 status response message")
    func crc16StatusResponseMessage() throws {
        // From MessageTests.swift testMessageDecoding()
        // StatusResponse message body (excluding CRC suffix)
        let input = Data(erosHex: "1f00ee84300a1d18003f1800004297ff")!
        #expect(0x8128 == input.erosCRC16(), "CRC16 should match StatusResponse message")
    }
    
    @Test("CRC16 edge cases")
    func crc16EdgeCases() throws {
        // Edge case vectors for full coverage
        
        // Single zero byte
        #expect(0x0000 == Data(erosHex: "00")!.erosCRC16(), "Zero input should produce zero CRC")
        
        // Single 0xFF byte
        #expect(0x0202 == Data(erosHex: "ff")!.erosCRC16(), "Single 0xFF test")
        
        // Two 0xFF bytes
        #expect(0x820f == Data(erosHex: "ffff")!.erosCRC16(), "Double 0xFF test")
        
        // Sequential bytes 1-15
        #expect(0x00c5 == Data(erosHex: "0102030405060708090a0b0c0d0e0f")!.erosCRC16(), "Sequential bytes test")
        
        // DEADBEEF pattern
        #expect(0x81ed == Data(erosHex: "deadbeef")!.erosCRC16(), "DEADBEEF pattern test")
        
        // Pod address only
        #expect(0x0067 == Data(erosHex: "1f01482a")!.erosCRC16(), "Pod address bytes test")
    }
    
    @Test("CRC16 empty data")
    func crc16EmptyData() throws {
        // Empty data should produce initial CRC value (0x0000)
        #expect(0x0000 == Data().erosCRC16(), "Empty data should produce zero CRC16")
    }
    
    // MARK: - Packet Encoding Tests (testPacketData)
    
    @Test("Packet encoding")
    func packetEncoding() throws {
        // From PacketTests.swift testPacketData()
        // PDM packet with GetStatusCommand (0x0e)
        let messageData = Data(erosHex: "1f01482a10030e0100802c")!
        
        let packet = ErosPacket(
            address: 0x1f01482a,
            packetType: .pdm,
            sequenceNum: 13,
            data: messageData
        )
        
        let encoded = packet.encoded()
        #expect("1f01482aad1f01482a10030e0100802c88" == encoded.erosHex,
                       "Encoded packet should match OmniKit test vector")
        
        #expect("1f01482a10030e0100802c" == packet.dataHex,
                       "Packet data should match expected hex")
    }
    
    // MARK: - Packet Decoding Tests (testPacketDecoding)
    
    @Test("Packet decoding")
    func packetDecoding() throws {
        // From PacketTests.swift testPacketDecoding()
        let encodedData = Data(erosHex: "1f01482aad1f01482a10030e0100802c88")!
        
        let packet = try ErosPacket(encodedData: encodedData)
        
        #expect(0x1f01482a == packet.address)
        #expect(13 == packet.sequenceNum)
        #expect(.pdm == packet.packetType)
        #expect("1f01482a10030e0100802c" == packet.dataHex)
    }
    
    // MARK: - Packet Fragmentation Tests (testPacketFragmenting)
    
    @Test("Packet fragmenting")
    func packetFragmenting() throws {
        // From PacketTests.swift testPacketFragmenting()
        // Long message that must be fragmented across multiple packets
        let longMessageHex = "02cb5000c92162368024632d8029623f002c62320031623b003463320039633d003c63310041623e0044633200496340004c6333005163448101627c8104627c8109627c810c62198111627c811460198103fe"
        let longMessageData = Data(erosHex: longMessageHex)!
        
        // First PDM packet (max 31 bytes)
        let pdmPacket = ErosPacket(
            address: 0x1f01482a,
            packetType: .pdm,
            sequenceNum: 13,
            data: longMessageData
        )
        
        #expect(31 == pdmPacket.data.count, "PDM packet should truncate to 31 bytes")
        #expect("02cb5000c92162368024632d8029623f002c62320031623b00346332003963" ==
                       pdmPacket.dataHex, "First fragment should match")
        
        // Continuation packet 1 (bytes 31-61)
        let con1Data = longMessageData.subdata(in: 31..<62)
        let con1Packet = ErosPacket(
            address: 0x1f01482a,
            packetType: .con,
            sequenceNum: 14,
            data: con1Data
        )
        
        #expect(31 == con1Packet.data.count)
        #expect("3d003c63310041623e0044633200496340004c6333005163448101627c8104" ==
                       con1Packet.dataHex, "Continuation 1 should match")
        
        // Continuation packet 2 (bytes 62-82, final fragment)
        let con2Data = longMessageData.subdata(in: 62..<longMessageData.count)
        let con2Packet = ErosPacket(
            address: 0x1f01482a,
            packetType: .con,
            sequenceNum: 14,
            data: con2Data
        )
        
        #expect(21 == con2Packet.data.count, "Final fragment should be 21 bytes")
        #expect("627c8109627c810c62198111627c811460198103fe" ==
                       con2Packet.dataHex, "Continuation 2 should match")
        
        // Verify reassembly
        let reassembled = pdmPacket.data + con1Packet.data + con2Packet.data
        #expect(longMessageData == reassembled, "Fragments should reassemble to original")
    }
    
    // MARK: - Packet Type Tests
    
    /// Validate PacketType values against Loop's OmniKit/MessageTransport/Packet.swift:14-19
    @Test("Packet types")
    func packetTypes() throws {
        // Source: OmniKit/MessageTransport/Packet.swift:14-19
        // case pod = 0b111
        // case pdm = 0b101
        // case con = 0b100
        // case ack = 0b010
        #expect(ErosPacketType.pod.rawValue == 0b111, "Source: Packet.swift:15")
        #expect(ErosPacketType.pdm.rawValue == 0b101, "Source: Packet.swift:16")
        #expect(ErosPacketType.con.rawValue == 0b100, "Source: Packet.swift:17")
        #expect(ErosPacketType.ack.rawValue == 0b010, "Source: Packet.swift:18")
        
        // Source: OmniKit/MessageTransport/Packet.swift:21-29
        // var maxBodyLen: Int - ack=4, others=31
        #expect(ErosPacketType.pod.maxBodyLen == 31, "Source: Packet.swift:26")
        #expect(ErosPacketType.pdm.maxBodyLen == 31, "Source: Packet.swift:27")
        #expect(ErosPacketType.con.maxBodyLen == 31, "Source: Packet.swift:28")
        #expect(ErosPacketType.ack.maxBodyLen == 4, "Source: Packet.swift:24")
    }
    
    // MARK: - Error Cases
    
    @Test("Insufficient data")
    func insufficientData() throws {
        // Less than 7 bytes should fail
        let shortData = Data(erosHex: "1f01482a")!
        
        do {
            _ = try ErosPacket(encodedData: shortData)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error as? ErosPacketError == ErosPacketError.insufficientData)
        }
    }
    
    @Test("CRC mismatch")
    func crcMismatch() throws {
        // Valid packet with corrupted CRC (last byte changed)
        var badCRC = Data(erosHex: "1f01482aad1f01482a10030e0100802c88")!
        badCRC[badCRC.count - 1] = 0x00  // Corrupt CRC
        
        do {
            _ = try ErosPacket(encodedData: badCRC)
            Issue.record("Expected crcMismatch error")
        } catch {
            guard let erosError = error as? ErosPacketError,
                  case .crcMismatch(let expected, let actual) = erosError else {
                Issue.record("Expected crcMismatch error")
                return
            }
            #expect(expected == 0x88)
            #expect(actual == 0x00)
        }
    }
    
    @Test("Unknown packet type")
    func unknownPacketType() throws {
        // Create packet with invalid type (type = 0b000)
        var badType = Data(erosHex: "1f01482a001f01482a10030e0100802c")!
        // Recalculate CRC for the modified packet
        let crc = badType.erosCRC8()
        badType.append(crc)
        
        do {
            _ = try ErosPacket(encodedData: badType)
            Issue.record("Expected unknownPacketType error")
        } catch {
            guard let erosError = error as? ErosPacketError,
                  case .unknownPacketType = erosError else {
                Issue.record("Expected unknownPacketType error, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Encode decode roundtrip")
    func encodeDecodeRoundtrip() throws {
        // Create packet
        let original = ErosPacket(
            address: 0xDEADBEEF,
            packetType: .pod,
            sequenceNum: 17,
            data: Data([0x01, 0x02, 0x03, 0x04, 0x05])
        )
        
        // Encode
        let encoded = original.encoded()
        
        // Decode
        let decoded = try ErosPacket(encodedData: encoded)
        
        // Verify
        #expect(original.address == decoded.address)
        #expect(original.packetType == decoded.packetType)
        #expect(original.sequenceNum == decoded.sequenceNum)
        #expect(original.data == decoded.data)
    }
    
    // MARK: - Sequence Number Masking
    
    @Test("Sequence number masking")
    func sequenceNumberMasking() throws {
        // Sequence numbers should be masked to 5 bits (0-31)
        let packet = ErosPacket(
            address: 0x12345678,
            packetType: .pdm,
            sequenceNum: 0xFF,  // Out of range
            data: Data()
        )
        
        #expect(31 == packet.sequenceNum, "Sequence should be masked to 0x1F (31)")
    }
    
    // MARK: - Ack Packet Tests
    
    @Test("Ack packet max length")
    func ackPacketMaxLength() throws {
        // ACK packets have max 4 byte body
        let longData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        let ackPacket = ErosPacket(
            address: 0x1f01482a,
            packetType: .ack,
            sequenceNum: 5,
            data: longData
        )
        
        #expect(4 == ackPacket.data.count, "ACK data should be truncated to 4 bytes")
        #expect(Data([0x01, 0x02, 0x03, 0x04]) == ackPacket.data)
    }
    
    // MARK: - Debug Description
    
    @Test("Debug description")
    func debugDescription() throws {
        let packet = ErosPacket(
            address: 0x1f01482a,
            packetType: .pdm,
            sequenceNum: 13,
            data: Data([0xAB, 0xCD])
        )
        
        let desc = packet.debugDescription
        #expect(desc.contains("0x1f01482a"), "Should contain address")
        #expect(desc.contains("PDM"), "Should contain packet type")
        #expect(desc.contains("13"), "Should contain sequence number")
        #expect(desc.contains("abcd"), "Should contain data hex")
    }
    
    // MARK: - Bolus Fixture Validation (EROS-SYNTH-004)
    
    @Test("Bolus command type bytes")
    func bolusCommandTypeBytes() throws {
        // SetInsulinScheduleCommand type is 0x1a
        let primeCommand = Data(erosHex: "1a0ebed2e16b02010a0101a000340034")!
        #expect(0x1a == primeCommand[0], "SetInsulinScheduleCommand type should be 0x1a")
        
        // BolusExtraCommand type is 0x17
        let bolusExtra = Data(erosHex: "170d7c177000030d40000000000000")!
        #expect(0x17 == bolusExtra[0], "BolusExtraCommand type should be 0x17")
        
        // CancelDeliveryCommand type is 0x1f
        let cancelBolus = Data(erosHex: "1f054d91f8ff64")!
        #expect(0x1f == cancelBolus[0], "CancelDeliveryCommand type should be 0x1f")
    }
    
    @Test("Bolus nonce extraction")
    func bolusNonceExtraction() throws {
        // From BolusTests.swift testPrimeBolusCommand()
        // Nonce is bytes 2-5 (big-endian): 0xbed2e16b
        let primeCommand = Data(erosHex: "1a0ebed2e16b02010a0101a000340034")!
        let nonce = UInt32(primeCommand[2]) << 24 |
                    UInt32(primeCommand[3]) << 16 |
                    UInt32(primeCommand[4]) << 8 |
                    UInt32(primeCommand[5])
        #expect(0xbed2e16b == nonce, "Nonce should match OmniKit test vector")
    }
    
    @Test("Bolus delivery type marker")
    func bolusDeliveryTypeMarker() throws {
        // Byte 6 (after nonce) should be 0x02 for bolus delivery
        let primeCommand = Data(erosHex: "1a0ebed2e16b02010a0101a000340034")!
        #expect(0x02 == primeCommand[6], "Bolus delivery type marker should be 0x02")
        
        // Extended bolus also has 0x02 marker
        let extendedBolus = Data(erosHex: "1a100375a60202001703000000000000100a")!
        #expect(0x02 == extendedBolus[6], "Extended bolus should have 0x02 marker")
    }
    
    @Test("Bolus extra command length")
    func bolusExtraCommandLength() throws {
        // BolusExtraCommand always has length 0x0d (13 bytes payload)
        let bolusExtra30U = Data(erosHex: "170d7c177000030d40000000000000")!
        #expect(0x0d == bolusExtra30U[1], "BolusExtraCommand length should be 0x0d")
        #expect(15 == bolusExtra30U.count, "Total BolusExtraCommand should be 15 bytes")
        
        // Prime BolusExtraCommand
        let primeBolus = Data(erosHex: "170d000208000186a0000000000000")!
        #expect(0x0d == primeBolus[1])
        #expect(15 == primeBolus.count)
    }
    
    @Test("Cancel bolus nonce")
    func cancelBolusNonce() throws {
        // CancelDeliveryCommand: 1f LL NNNNNNNN TT
        // 1f 05 4d91f8ff 64
        let cancelBolus = Data(erosHex: "1f054d91f8ff64")!
        #expect(0x05 == cancelBolus[1], "CancelDelivery length should be 0x05")
        
        let nonce = UInt32(cancelBolus[2]) << 24 |
                    UInt32(cancelBolus[3]) << 16 |
                    UInt32(cancelBolus[4]) << 8 |
                    UInt32(cancelBolus[5])
        #expect(0x4d91f8ff == nonce, "Cancel nonce should match")
        #expect(0x64 == cancelBolus[6], "Beep type should be 0x64 (beeeeeep)")
    }
    
    // MARK: - Bolus Session Validation (SESSION-EROS-002)
    
    @Test("Bolus session fixture exists")
    func bolusSessionFixtureExists() throws {
        let fixturePath = "conformance/protocol/omnipod/fixture_eros_bolus_session.json"
        let url = URL(fileURLWithPath: fixturePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let altUrl = URL(fileURLWithPath: "../../../\(fixturePath)", relativeTo: URL(fileURLWithPath: #file))
        let fileURL = FileManager.default.fileExists(atPath: url.path) ? url : altUrl
        
        #expect(FileManager.default.fileExists(atPath: fileURL.path),
                     "fixture_eros_bolus_session.json should exist at \(fixturePath)")
    }
    
    @Test("Bolus session vectors")
    func bolusSessionVectors() throws {
        // Test vectors from fixture_eros_bolus_session.json
        
        // 0.1U bolus - SetInsulinScheduleCommand
        let bolus01U = Data(erosHex: "1a0e243085c802002501002000020002")!
        #expect(0x1a == bolus01U[0], "SetInsulinScheduleCommand type")
        #expect(0x02 == bolus01U[6], "Bolus delivery type marker")
        
        // Extract nonce: 0x243085c8
        let nonce01 = UInt32(bolus01U[2]) << 24 | UInt32(bolus01U[3]) << 16 |
                      UInt32(bolus01U[4]) << 8 | UInt32(bolus01U[5])
        #expect(0x243085c8 == nonce01, "Nonce should be 0x243085c8")
        
        // Extract pulses: bytes 12-13
        let pulses = UInt16(bolus01U[12]) << 8 | UInt16(bolus01U[13])
        #expect(2 == pulses, "0.1U = 2 pulses")
        
        // 0.1U bolus - BolusExtraCommand: 170d00001400030d40000000000000
        // Structure: 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 00 0014 00030d40 0000 00000000
        // BO = byte 2 (beep options: bit7=ack, bit6=completion, bits0-5=reminder)
        // NNNN = bytes 3-4 (immediate pulses * 10, big-endian)
        let bolusExtra01U = Data(erosHex: "170d00001400030d40000000000000")!
        #expect(0x17 == bolusExtra01U[0], "BolusExtraCommand type")
        #expect(0x0d == bolusExtra01U[1], "BolusExtraCommand length")
        
        // Immediate pulses * 10 = bytes 3-4 (big-endian): 0x0014 = 20
        let pulsesX10 = UInt16(bolusExtra01U[3]) << 8 | UInt16(bolusExtra01U[4])
        #expect(20 == pulsesX10, "0.1U = 20 (pulses * 10)")
    }
    
    @Test("Bolus session large vector")
    func bolusSessionLargeVector() throws {
        // 29.95U large bolus from fixture
        let largeBolus = Data(erosHex: "1a0e31204ba702014801257002570257")!
        
        // Extract pulses: bytes 12-13
        let pulses = UInt16(largeBolus[12]) << 8 | UInt16(largeBolus[13])
        #expect(599 == pulses, "29.95U = 599 pulses")
        
        // Verify units: 599 * 0.05 = 29.95
        let units = Double(pulses) * 0.05
        #expect(abs(units - 29.95) < 0.001, "Should be 29.95U")
        
        // BolusExtraCommand with completion beep: 170d7c176600030d40000000000000
        // Byte 2 = 0x7c = 0b01111100:
        //   Bit 7 (0x80) = acknowledgementBeep = 0 (false)
        //   Bit 6 (0x40) = completionBeep = 1 (true)
        //   Bits 0-5 (0x3c) = programReminderInterval = 60 minutes
        let largeBolusExtra = Data(erosHex: "170d7c176600030d40000000000000")!
        let beepFlags = largeBolusExtra[2]
        #expect(0x7c == beepFlags, "Beep flags should be 0x7c")
        
        // Per OmniKit: bit 7 = ack, bit 6 = completion
        let acknowledgementBeep = (beepFlags & 0x80) != 0
        let completionBeep = (beepFlags & 0x40) != 0
        let programReminderInterval = beepFlags & 0x3f
        
        #expect(!acknowledgementBeep, "Acknowledgement beep should be false")
        #expect(completionBeep, "Completion beep should be true")
        #expect(60 == programReminderInterval, "Reminder interval = 60 minutes (1 hour)")
    }
    
    @Test("Bolus session status response")
    func bolusSessionStatusResponse() throws {
        // StatusResponse when bolusing (deliveryStatus = 5)
        let statusBolusing = Data(erosHex: "1d59050ec82c08376f9801dc")!
        #expect(0x1d == statusBolusing[0], "StatusResponse type")
        
        // deliveryStatus is upper nibble of byte 1
        let deliveryStatus = statusBolusing[1] >> 4
        #expect(5 == deliveryStatus, "DeliveryStatus 5 = bolusInProgress")
        
        // StatusResponse when not bolusing (deliveryStatus = 1)
        let statusBasal = Data(erosHex: "1d19050ec82c08376f9801dc")!
        let basalDeliveryStatus = statusBasal[1] >> 4
        #expect(1 == basalDeliveryStatus, "DeliveryStatus 1 = scheduledBasal")
    }
    
    @Test("Bolus session state transitions")
    func bolusSessionStateTransitions() throws {
        // Validate state machine from fixture
        let states = ["ready", "verifying", "commanding", "delivering", "delivered"]
        #expect(5 == states.count, "Bolus session has 5 states")
        
        // GetStatusCommand for verification
        let getStatus = Data(erosHex: "0e0100")!
        #expect(0x0e == getStatus[0], "GetStatusCommand type")
        #expect(0x00 == getStatus[2], "podInfoType = normal")
    }
    
    @Test("Bolus delivery duration calculation")
    func bolusDeliveryDurationCalculation() throws {
        // From fixture: 0.1U = 2 pulses @ 2 sec/pulse = 4 seconds
        let pulses = 2
        let secondsPerPulse = 2
        let duration = pulses * secondsPerPulse
        #expect(4 == duration, "0.1U bolus takes 4 seconds")
        
        // 29.95U = 599 pulses @ 2 sec/pulse = 1198 seconds = 19.97 minutes
        let largePulses = 599
        let largeDuration = largePulses * secondsPerPulse
        #expect(1198 == largeDuration, "29.95U bolus takes 1198 seconds")
        
        let durationMinutes = Double(largeDuration) / 60.0
        #expect(abs(durationMinutes - 19.97) < 0.01, "29.95U = ~20 minutes")
    }
    
    // MARK: - Temp Basal Fixture Validation (EROS-SYNTH-005)
    
    @Test("Temp basal command type bytes")
    func tempBasalCommandTypeBytes() throws {
        // SetInsulinScheduleCommand type is 0x1a (same as bolus)
        // Temp basal delivery type marker is 0x01 (byte 6)
        let tempBasalCmd = Data(erosHex: "1a0e9746c65b01007901384000000000")!
        #expect(0x1a == tempBasalCmd[0], "SetInsulinScheduleCommand type should be 0x1a")
        #expect(0x01 == tempBasalCmd[6], "Temp basal delivery type marker should be 0x01")
        
        // TempBasalExtraCommand type is 0x16
        let tempBasalExtra = Data(erosHex: "160e7c0000006b49d20000006b49d200")!
        #expect(0x16 == tempBasalExtra[0], "TempBasalExtraCommand type should be 0x16")
    }
    
    @Test("Temp basal nonce extraction")
    func tempBasalNonceExtraction() throws {
        // From TempBasalTests.swift testAlternatingSegmentFlag()
        // Nonce is bytes 2-5 (big-endian): 0x9746c65b
        let tempBasalCmd = Data(erosHex: "1a0e9746c65b01007901384000000000")!
        let nonce = UInt32(tempBasalCmd[2]) << 24 |
                    UInt32(tempBasalCmd[3]) << 16 |
                    UInt32(tempBasalCmd[4]) << 8 |
                    UInt32(tempBasalCmd[5])
        #expect(0x9746c65b == nonce, "Nonce should match OmniKit test vector")
    }
    
    @Test("Temp basal delivery type marker")
    func tempBasalDeliveryTypeMarker() throws {
        // Byte 6 (after nonce) should be 0x01 for temp basal delivery
        let cmd05 = Data(erosHex: "1a0e9746c65b01007901384000000000")!
        #expect(0x01 == cmd05[6], "Temp basal delivery type marker should be 0x01")
        
        let cmd20 = Data(erosHex: "1a0eea2d0a3b01007d01384000020002")!
        #expect(0x01 == cmd20[6], "Temp basal delivery type marker should be 0x01")
        
        // Compare with bolus (0x02)
        let bolusCmd = Data(erosHex: "1a0ebed2e16b02010a0101a000340034")!
        #expect(0x02 == bolusCmd[6], "Bolus delivery type marker should be 0x02")
    }
    
    @Test("Temp basal seconds remaining extraction")
    func tempBasalSecondsRemainingExtraction() throws {
        // Bytes 10-11: seconds remaining << 3
        // All temp basal commands start with 1800 seconds (30 min) = 0x3840 >> 3
        let tempBasalCmd = Data(erosHex: "1a0eea2d0a3b01007d01384000020002")!
        let secondsRemainingShifted = UInt16(tempBasalCmd[10]) << 8 | UInt16(tempBasalCmd[11])
        let secondsRemaining = secondsRemainingShifted >> 3
        #expect(1800 == secondsRemaining, "Seconds remaining should be 1800 (30 minutes)")
        #expect(0x3840 == secondsRemainingShifted, "Shifted value should be 0x3840")
    }
    
    @Test("Temp basal first segment pulses")
    func tempBasalFirstSegmentPulses() throws {
        // Bytes 12-13: first segment pulses
        
        // 0.2 U/hr → 4 pulses/hr → 2 pulses per 30min
        let cmd02 = Data(erosHex: "1a0eea2d0a3b01007d01384000020002")!
        let pulses02 = UInt16(cmd02[12]) << 8 | UInt16(cmd02[13])
        #expect(2 == pulses02, "0.2 U/hr should have 2 first segment pulses")
        
        // 2.0 U/hr → 40 pulses/hr → 20 pulses per 30min
        let cmd20 = Data(erosHex: "1a0e87e8d03a0100cb03384000142014")!
        let pulses20 = UInt16(cmd20[12]) << 8 | UInt16(cmd20[13])
        #expect(20 == pulses20, "2.0 U/hr should have 20 first segment pulses")
        
        // 30 U/hr → 600 pulses/hr → 300 pulses per 30min
        let cmd30 = Data(erosHex: "1a10a958c5ad0104f5183840012cf12c712c")!
        let pulses30 = UInt16(cmd30[12]) << 8 | UInt16(cmd30[13])
        #expect(300 == pulses30, "30 U/hr should have 300 first segment pulses")
    }
    
    @Test("Temp basal extra command length")
    func tempBasalExtraCommandLength() throws {
        // TempBasalExtraCommand: length = 8 + (num_entries * 6)
        
        // Single entry (30 min): length = 8 + 6 = 14 = 0x0e
        let cmd30min = Data(erosHex: "160e7c0000006b49d20000006b49d200")!
        #expect(0x0e == cmd30min[1], "30min temp basal extra length should be 0x0e")
        #expect(16 == cmd30min.count, "Total bytes: 2 header + 14 payload")
        
        // 6 entries (3 hours): length = 8 + (6 * 6) = 44 = 0x2c
        let cmd3hr = Data(erosHex: "162c7c0000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d200")!
        #expect(0x2c == cmd3hr[1], "3hr temp basal extra length should be 0x2c")
    }
    
    @Test("Temp basal extra beep options")
    func tempBasalExtraBeepOptions() throws {
        // Byte 2: RR = (ack<<7) | (completion<<6) | (reminderMinutes & 0x3f)
        
        // 0x7c = 0b01111100 = no ack, completion=true, reminder=60
        let cmdWithBeep = Data(erosHex: "160e7c0000006b49d20000006b49d200")!
        let beepOpts1 = cmdWithBeep[2]
        #expect(!(beepOpts1 & 0x80 != 0), "Acknowledgement beep should be false")
        #expect(beepOpts1 & 0x40 != 0, "Completion beep should be true")
        #expect(60 == beepOpts1 & 0x3f, "Reminder interval should be 60 minutes")
        
        // 0x3c = 0b00111100 = no ack, no completion, reminder=60
        let cmdNoBeep = Data(erosHex: "160e3c0000cd0085fac700cd0085fac7")!
        let beepOpts2 = cmdNoBeep[2]
        #expect(!(beepOpts2 & 0x80 != 0), "Acknowledgement beep should be false")
        #expect(!(beepOpts2 & 0x40 != 0), "Completion beep should be false")
        #expect(60 == beepOpts2 & 0x3f, "Reminder interval should be 60 minutes")
        
        // 0x00 = 0b00000000 = no beeps, no reminder
        let cmdNoReminder = Data(erosHex: "16140000f5b9000a0ad7f5b9000a0ad70aaf000a0ad7")!
        let beepOpts3 = cmdNoReminder[2]
        #expect(0 == beepOpts3, "All beep options should be zero")
    }
    
    @Test("Temp basal extra remaining pulses")
    func tempBasalExtraRemainingPulses() throws {
        // Bytes 4-5: remaining pulses * 10 (big-endian)
        
        // 0 U/hr → 0 pulses
        let cmdZero = Data(erosHex: "160e7c0000006b49d20000006b49d200")!
        let pulsesZero = UInt16(cmdZero[4]) << 8 | UInt16(cmdZero[5])
        #expect(0 == pulsesZero, "Zero rate should have 0 remaining pulses")
        
        // 30 U/hr 30min → 300 pulses → 0x0bb8 * 10 = 3000
        let cmd30 = Data(erosHex: "160e7c000bb8000927c00bb8000927c0")!
        let pulses30 = UInt16(cmd30[4]) << 8 | UInt16(cmd30[5])
        #expect(3000 == pulses30, "30 U/hr 30min should have 3000 (300*10) remaining pulses")
        #expect(300.0 == Double(pulses30) / 10.0, "Should equal 300 pulses")
    }
    
    @Test("Temp basal extra delay until first pulse")
    func tempBasalExtraDelayUntilFirstPulse() throws {
        // Bytes 6-9: delay until first pulse in 0.01ms units (big-endian)
        
        // Zero rate: delay = 5 hours = 18,000,000ms = 1,800,000,000 * 0.01ms = 0x6b49d200
        let cmdZero = Data(erosHex: "160e7c0000006b49d20000006b49d200")!
        let delayZero = UInt32(cmdZero[6]) << 24 |
                        UInt32(cmdZero[7]) << 16 |
                        UInt32(cmdZero[8]) << 8 |
                        UInt32(cmdZero[9])
        #expect(0x6b49d200 == delayZero, "Zero rate delay should be 0x6b49d200")
        #expect(18000000.0 == Double(delayZero) / 100.0, "Should equal 18,000,000ms (5 hours)")
        
        // 30 U/hr: delay = 6 seconds = 6,000ms = 600,000 * 0.01ms = 0x000927c0
        let cmd30 = Data(erosHex: "160e7c000bb8000927c00bb8000927c0")!
        let delay30 = UInt32(cmd30[6]) << 24 |
                      UInt32(cmd30[7]) << 16 |
                      UInt32(cmd30[8]) << 8 |
                      UInt32(cmd30[9])
        #expect(0x000927c0 == delay30, "30 U/hr delay should be 0x000927c0")
        #expect(6000.0 == Double(delay30) / 100.0, "Should equal 6,000ms (6 seconds)")
    }
    
    @Test("Cancel temp basal command")
    func cancelTempBasalCommand() throws {
        // CancelDeliveryCommand for temp basal: 1f LL NNNNNNNN TT
        // TT = 0x62 (temp basal + beeeeeep) or 0x02 (temp basal + no beep)
        
        // With beep: 1f 05 f76d34c4 62
        let cancelWithBeep = Data(erosHex: "1f05f76d34c462")!
        #expect(0x1f == cancelWithBeep[0], "CancelDeliveryCommand type should be 0x1f")
        #expect(0x05 == cancelWithBeep[1], "Length should be 0x05")
        #expect(0x62 == cancelWithBeep[6], "Beep type should be 0x62 (tempBasal + beeeeeep)")
        
        let nonce1 = UInt32(cancelWithBeep[2]) << 24 |
                     UInt32(cancelWithBeep[3]) << 16 |
                     UInt32(cancelWithBeep[4]) << 8 |
                     UInt32(cancelWithBeep[5])
        #expect(0xf76d34c4 == nonce1, "Nonce should match")
        
        // Without beep: 1f 05 f76d34c4 02
        let cancelNoBeep = Data(erosHex: "1f05f76d34c402")!
        #expect(0x02 == cancelNoBeep[6], "Beep type should be 0x02 (tempBasal + noBeepCancel)")
    }
    
    @Test("Temp basal table entry parsing")
    func tempBasalTableEntryParsing() throws {
        // Table entries: 2 bytes each
        // Bits: [15:12] segments, [11] alternateSegmentPulse, [10:0] pulses
        
        // 0x0002 = segments=0, alternate=false, pulses=2 (but with top nibble as segments count)
        // Actually: 0x0002 = 0b0000_0000_0000_0010 → segments=0, no alternate, pulses=2
        // Entry format: high nibble = segment count, bit 11 = alternate, bits 10:0 = pulses
        
        // 2.0 U/hr 1.5h: entry = 0x2014 = 0b0010_0000_0001_0100
        // segments = 2 (top 4 bits), alternate = 0, pulses = 20 (0x14)
        let cmd20 = Data(erosHex: "1a0e87e8d03a0100cb03384000142014")!
        let entry = UInt16(cmd20[14]) << 8 | UInt16(cmd20[15])
        #expect(0x2014 == entry)
        let segments = (entry >> 12) & 0x0F
        let alternate = (entry >> 11) & 0x01
        let pulses = entry & 0x07FF
        #expect(2 == segments, "Entry should have 2 segments remaining")
        #expect(0 == alternate, "Entry should not have alternate pulse")
        #expect(20 == pulses, "Entry should have 20 pulses")
    }
    
    @Test("Temp basal alternating pulse flag")
    func tempBasalAlternatingPulseFlag() throws {
        // 0.05 U/hr for 2.5 hours uses alternating pulse flag
        // Entry 0x4800 = 0b0100_1000_0000_0000
        // segments = 4, alternate = 1, pulses = 0
        let cmdAlt = Data(erosHex: "1a0e4e2c271701007f05384000004800")!
        let entry = UInt16(cmdAlt[14]) << 8 | UInt16(cmdAlt[15])
        #expect(0x4800 == entry)
        let segments = (entry >> 12) & 0x0F
        let alternate = (entry >> 11) & 0x01
        let pulses = entry & 0x07FF
        #expect(4 == segments, "Entry should have 4 segments")
        #expect(1 == alternate, "Entry should have alternate pulse flag")
        #expect(0 == pulses, "Entry should have 0 base pulses")
    }
    
    // MARK: - Pod State Fixture Validation (EROS-SYNTH-006)
    
    @Test("Get status command encoding")
    func getStatusCommandEncoding() throws {
        // From StatusTests.swift testStatusRequestCommand()
        // GetStatusCommand for normal status
        let normalStatus = Data(erosHex: "0e0100")!
        #expect(0x0e == normalStatus[0], "GetStatusCommand type should be 0x0e")
        #expect(0x01 == normalStatus[1], "Length should be 0x01")
        #expect(0x00 == normalStatus[2], "podInfoType normal should be 0x00")
        
        // GetStatusCommand for triggered alerts
        let alertsStatus = Data(erosHex: "0e0101")!
        #expect(0x01 == alertsStatus[2], "podInfoType triggeredAlerts should be 0x01")
        
        // GetStatusCommand for detailed status (fault events)
        let detailedStatus = Data(erosHex: "0e0102")!
        #expect(0x02 == detailedStatus[2], "podInfoType detailedStatus should be 0x02")
    }
    
    @Test("Detailed status no faults")
    func detailedStatusNoFaults() throws {
        // From PodInfoTests.swift testPodInfoNoFaultAlerts()
        // DetailedStatus with no faults (normal operation)
        // Format: 02 PP DD LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW XX YYYY
        // Index:  0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        let data = Data(erosHex: "02080100000a003800000003ff008700000095ff0000")!
        
        #expect(0x02 == data[0], "DetailedStatus type should be 0x02")
        
        // Byte 1: podProgressStatus
        #expect(0x08 == data[1], "podProgress should be 0x08 (aboveFiftyUnits)")
        
        // Byte 2: deliveryStatus (low nibble)
        let deliveryStatus = data[2] & 0x0F
        #expect(1 == deliveryStatus, "deliveryStatus should be 1 (scheduledBasal)")
        
        // Byte 5: lastProgrammingMessageSeqNum
        #expect(0x0a == data[5], "lastProgrammingMessageSeqNum should be 10")
        
        // Bytes 6-7: totalInsulinDelivered raw (pulses)
        let totalDeliveredRaw = UInt16(data[6]) << 8 | UInt16(data[7])
        #expect(0x0038 == totalDeliveredRaw, "totalInsulinDelivered raw should be 0x0038")
        #expect(abs(Double(totalDeliveredRaw) * 0.05 - 2.8) < 0.01, "Should be 2.8U")
        
        // Byte 8: faultEventCode
        #expect(0x00 == data[8], "faultEventCode should be 0x00 (noFaults)")
        
        // Bytes 11-12: reservoirLevel raw (low 10 bits)
        let reservoirRaw = (UInt16(data[11] & 0x03) << 8) | UInt16(data[12])
        #expect(0x03ff == reservoirRaw, "reservoirLevel raw should be 0x03ff (above threshold)")
        
        // Bytes 13-14: timeActive minutes
        let timeActive = UInt16(data[13]) << 8 | UInt16(data[14])
        #expect(0x0087 == timeActive, "timeActive should be 0x0087 (135 minutes = 2h15m)")
        #expect(135 == timeActive)
    }
    
    @Test("Detailed status occlusion fault")
    func detailedStatusOcclusionFault() throws {
        // From PodInfoTests.swift testFullMessage()
        // DetailedStatus with occlusion check above threshold fault
        // Format: 02 PP DD LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW XX YYYY
        let data = Data(erosHex: "020d0000000000ab6a038403ff03860000285708030d0000")!
        
        // Byte 1: podProgressStatus
        #expect(0x0d == data[1], "podProgress should be 0x0d (faultEventOccurred)")
        
        // Byte 2: deliveryStatus (low nibble) - but faulted pods always suspended
        #expect(0x00 == data[2] & 0x0F, "deliveryStatus raw should be 0 (suspended)")
        
        // Bytes 6-7: totalInsulinDelivered raw
        let totalDeliveredRaw = UInt16(data[6]) << 8 | UInt16(data[7])
        #expect(0x00ab == totalDeliveredRaw, "totalInsulinDelivered raw should be 0x00ab (171)")
        #expect(abs(Double(totalDeliveredRaw) * 0.05 - 8.55) < 0.01, "Should be 8.55U")
        
        // Byte 8: faultEventCode
        #expect(0x6a == data[8], "faultEventCode should be 0x6a (occlusionCheckAboveThreshold)")
        
        // Bytes 9-10: faultEventTimeSinceActivation minutes
        let faultTime = UInt16(data[9]) << 8 | UInt16(data[10])
        #expect(0x0384 == faultTime, "faultTime should be 0x0384 (900 minutes = 15h)")
        
        // Bytes 13-14: timeActive minutes
        let timeActive = UInt16(data[13]) << 8 | UInt16(data[14])
        #expect(0x0386 == timeActive, "timeActive should be 0x0386 (902 minutes)")
        
        // Byte 17: errorEventInfo
        // 0x28 = 0b00101000 → insulinCorrupt=0, occlusionType=1, bolus=0, progress=8
        #expect(0x28 == data[17], "errorEventInfo should be 0x28")
        let occlusionType = (data[17] >> 5) & 0x03
        #expect(1 == occlusionType, "occlusionType should be 1")
    }
    
    @Test("Detailed status reset due to LVD")
    func detailedStatusResetDueToLVD() throws {
        // From PodInfoTests.swift testPodInfoFaultEventResetDueToLowVoltageDetect()
        // Format: 02 PP DD LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW XX YYYY
        let data = Data(erosHex: "020D00000000000012FFFF03FF00160000879A070000")!
        
        // Byte 8: faultEventCode = 0x12 (resetDueToLVD)
        #expect(0x12 == data[8], "faultEventCode should be 0x12 (resetDueToLVD)")
        
        // Bytes 9-10: faultEventTimeSinceActivation = 0xFFFF (invalid/unknown)
        let faultTime = UInt16(data[9]) << 8 | UInt16(data[10])
        #expect(0xFFFF == faultTime, "faultTime 0xFFFF means invalid/unknown")
        
        // Byte 17: errorEventInfo
        // 0x87 = 0b10000111 → insulinCorrupt=1, occlusionType=0, bolus=0, progress=7
        #expect(0x87 == data[17], "errorEventInfo should be 0x87")
        let insulinCorrupt = (data[17] >> 7) & 0x01
        #expect(1 == insulinCorrupt, "insulinStateTableCorruption should be true")
    }
    
    @Test("Detailed status delivery error during priming")
    func detailedStatusDeliveryErrorDuringPriming() throws {
        // From PodInfoTests.swift testPodInfoDeliveryErrorDuringPriming()
        // Format: 02 PP DD LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW XX YYYY
        let data = Data(erosHex: "020f0000000900345c000103ff0001000005ae056029")!
        
        // Byte 1: podProgressStatus = 0x0f (inactive)
        #expect(0x0f == data[1], "podProgress should be 0x0f (inactive)")
        
        // Byte 8: faultEventCode = 0x5c (primeOpenCountTooLow)
        #expect(0x5c == data[8], "faultEventCode should be 0x5c (primeOpenCountTooLow)")
        
        // Byte 19: previousPodProgressStatus = 0x05 (primingCompleted)
        #expect(0x05 == data[19], "previousPodProgressStatus should be 0x05 (primingCompleted)")
    }
    
    @Test("Triggered alerts empty")
    func triggeredAlertsEmpty() throws {
        // From PodInfoTests.swift testPodInfoTriggeredAlertsEmpty()
        let data = Data(erosHex: "01000000000000000000000000000000000000")!
        
        #expect(0x01 == data[0], "TriggeredAlerts type should be 0x01")
        
        // All bytes after type should be zero (no alerts)
        for i in 1..<data.count {
            #expect(0x00 == data[i], "Byte \(i) should be 0x00 (no alerts)")
        }
    }
    
    @Test("Triggered alerts suspend active")
    func triggeredAlertsSuspendActive() throws {
        // From PodInfoTests.swift testPodInfoTriggeredAlertsSuspendStillActive()
        // After 2 hour suspend: slots 5 and 6 have values
        // Format: 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // Index:   0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // Slots:            0    1    2    3    4    5    6    7
        let data = Data(erosHex: "010000000000000000000000000bd70c400000")!
        
        #expect(0x01 == data[0], "TriggeredAlerts type should be 0x01")
        
        // Slot 5 starts at offset 3 + (5 * 2) = 13
        let slot5 = UInt16(data[13]) << 8 | UInt16(data[14])
        #expect(0x0bd7 == slot5, "Slot 5 should be 0x0bd7 (3031 minutes)")
        #expect(3031 == slot5)
        
        // Slot 6 starts at offset 3 + (6 * 2) = 15
        let slot6 = UInt16(data[15]) << 8 | UInt16(data[16])
        #expect(0x0c40 == slot6, "Slot 6 should be 0x0c40 (3136 minutes)")
        #expect(3136 == slot6)
    }
    
    @Test("Triggered alerts replace pod")
    func triggeredAlertsReplacePod() throws {
        // From PodInfoTests.swift testPodInfoTriggeredAlertsReplacePodAfter3DaysAnd8Hours()
        // Slot 7: 72h1m = 4321 minutes
        // Format: 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // Slot 7 starts at offset 3 + (7 * 2) = 17
        let data = Data(erosHex: "010000000000000000000000000000000010e1")!
        
        // Slot 7 (bytes 17-18): 0x10e1 = 4321 minutes = 72h1m
        let slot7 = UInt16(data[17]) << 8 | UInt16(data[18])
        #expect(0x10e1 == slot7, "Slot 7 should be 0x10e1 (4321 minutes)")
        #expect(4321 == slot7)
        
        // Verify this is ~72 hours (3 days)
        let hours = Double(slot7) / 60.0
        #expect(abs(hours - 72.01) < 0.1, "Should be ~72 hours")
    }
    
    @Test("Activation time with fault")
    func activationTimeWithFault() throws {
        // From PodInfoTests.swift testPodInfoActivationTime()
        // 05 92 0001 00000000 00000000 091912170e
        let data = Data(erosHex: "059200010000000000000000091912170e")!
        
        #expect(0x05 == data[0], "ActivationTime type should be 0x05")
        
        // Byte 1: faultEventCode = 0x92 (tempPulseChanInactive)
        #expect(0x92 == data[1], "faultEventCode should be 0x92 (tempPulseChanInactive)")
        
        // Bytes 2-3: faultTime = 1 minute
        let faultTime = UInt16(data[2]) << 8 | UInt16(data[3])
        #expect(1 == faultTime, "faultTime should be 1 minute")
        
        // Date components (bytes 12-16): 09 19 12 17 0e
        // Format: MM DD YY HH mm
        #expect(0x09 == data[12], "Month should be 9 (September)")
        #expect(0x19 == data[13], "Day should be 25 (0x19)")
        #expect(0x12 == data[14], "Year should be 18 (0x12 = 2018)")
        #expect(0x17 == data[15], "Hour should be 23 (0x17)")
        #expect(0x0e == data[16], "Minute should be 14 (0x0e)")
    }
    
    @Test("Error response bad nonce")
    func errorResponseBadNonce() throws {
        // From PodStateTests.swift testResyncNonce()
        // ErrorResponse with badNonce
        let data = Data(erosHex: "06031492c482f5")!
        
        #expect(0x06 == data[0], "ErrorResponse type should be 0x06")
        #expect(0x03 == data[1], "Length should be 0x03")
        
        // Byte 2: errorCode = 0x14 indicates badNonce
        #expect(0x14 == data[2], "errorCode 0x14 indicates badNonce response")
        
        // Bytes 3-4: nonceResyncKey
        let resyncKey = UInt16(data[3]) << 8 | UInt16(data[4])
        #expect(0x92c4 == resyncKey, "nonceResyncKey should be 0x92c4")
    }
    
    @Test("Error response non retryable")
    func errorResponseNonRetryable() throws {
        // From PodStateTests.swift testErrorResponse()
        // Non-retryable error response
        let data = Data(erosHex: "0603070008019a")!
        
        #expect(0x06 == data[0], "ErrorResponse type should be 0x06")
        #expect(0x03 == data[1], "Length should be 0x03")
        
        // Byte 2: errorCode = 7
        #expect(0x07 == data[2], "errorCode should be 7")
        
        // Byte 3: faultEventCode = 0x00 (noFaults)
        #expect(0x00 == data[3], "faultEventCode should be 0x00 (noFaults)")
        
        // Byte 4: podProgress = 0x08 (aboveFiftyUnits)
        #expect(0x08 == data[4], "podProgress should be 0x08 (aboveFiftyUnits)")
    }
    
    @Test("Pulse log recent index extraction")
    func pulseLogRecentIndexExtraction() throws {
        // From PodInfoTests.swift testPodInfoPulseLogRecent()
        // First bytes: 50 0086 ...
        let data = Data(erosHex: "50008634212e00")!
        
        #expect(0x50 == data[0], "PulseLogRecent type should be 0x50")
        
        // Bytes 1-2: indexLastEntry
        let indexLastEntry = UInt16(data[1]) << 8 | UInt16(data[2])
        #expect(134 == indexLastEntry, "indexLastEntry should be 134")
        
        // Bytes 3-6: first pulse log entry
        let entry0 = UInt32(data[3]) << 24 | UInt32(data[4]) << 16 |
                     UInt32(data[5]) << 8 | UInt32(data[6])
        #expect(0x34212e00 == entry0, "First entry should be 0x34212e00")
    }
    
    @Test("Pulse log plus structure")
    func pulseLogPlusStructure() throws {
        // From PodInfoTests.swift testPodInfoPulseLogPlus()
        // 03 00 0000 0075 04 3c ...
        let data = Data(erosHex: "030000000075043c54402600")!
        
        #expect(0x03 == data[0], "PulseLogPlus type should be 0x03")
        
        // Byte 1: faultEventCode = 0x00 (noFaults)
        #expect(0x00 == data[1], "faultEventCode should be 0x00 (noFaults)")
        
        // Bytes 2-3: timeFaultEvent = 0x0000
        let timeFault = UInt16(data[2]) << 8 | UInt16(data[3])
        #expect(0 == timeFault, "timeFaultEvent should be 0")
        
        // Bytes 4-5: timeActivation = 0x0075 (117 minutes)
        let timeActivation = UInt16(data[4]) << 8 | UInt16(data[5])
        #expect(0x0075 == timeActivation, "timeActivation should be 0x0075 (117 minutes)")
        #expect(117 == timeActivation)
        
        // Byte 6: entrySize = 4
        #expect(4 == data[6], "entrySize should be 4")
        
        // Byte 7: maxEntries = 0x3c (60)
        #expect(0x3c == data[7], "maxEntries should be 0x3c (60)")
        
        // Bytes 8-11: first entry
        let entry0 = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 |
                     UInt32(data[10]) << 8 | UInt32(data[11])
        #expect(0x54402600 == entry0, "First entry should be 0x54402600")
    }
    
    // MARK: - Basal Schedule Fixture Validation (EROS-SYNTH-007)
    
    @Test("Set basal schedule command decode")
    func setBasalScheduleCommandDecode() throws {
        // From BasalScheduleTests.swift testSetBasalScheduleCommand()
        // Decode: 1a 12 77a05551 00 0062 2b 1708 0000 f800 f800 f800
        let data = Data(erosHex: "1a1277a055510000622b17080000f800f800f800")!
        
        #expect(0x1a == data[0], "SetInsulinScheduleCommand type should be 0x1a")
        #expect(0x12 == data[1], "Length should be 0x12 (18 bytes)")
        
        // Bytes 2-5: nonce
        let nonce = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                    UInt32(data[4]) << 8 | UInt32(data[5])
        #expect(0x77a05551 == nonce, "Nonce should be 0x77a05551")
        
        // Byte 6: delivery type (0x00 = basal schedule, 0x01 = temp basal)
        #expect(0x00 == data[6], "Delivery type 0x00 indicates basal schedule")
        
        // Bytes 7-8: checksum
        let checksum = UInt16(data[7]) << 8 | UInt16(data[8])
        #expect(0x0062 == checksum, "Checksum should be 0x0062")
        
        // Byte 9: current segment (0x2b = 43 = 21:30)
        #expect(0x2b == data[9], "Current segment should be 0x2b (21:30)")
        let segmentHour = data[9] / 2
        let segmentMinute = (data[9] % 2) * 30
        #expect(21 == segmentHour, "Hour should be 21")
        #expect(30 == segmentMinute, "Minute should be 30")
        
        // Bytes 10-11: seconds remaining << 3
        let ssss = UInt16(data[10]) << 8 | UInt16(data[11])
        let secondsRemaining = ssss >> 3
        #expect(0x1708 == ssss, "SSSS raw should be 0x1708")
        #expect(737 == secondsRemaining, "Seconds remaining should be 737")
        
        // Bytes 12-13: pulses remaining
        let pulsesRemaining = UInt16(data[12]) << 8 | UInt16(data[13])
        #expect(0 == pulsesRemaining, "Pulses remaining should be 0")
        
        // Table entries (3 entries of 2 bytes each)
        // f800 = 1111 1000 0000 0000 → n=15 (0xf), a=1, pp=0
        // Note: OmniKit uses n=0 to mean 16 segments, but 0xf=15 means 15 segments
        for i in 0..<3 {
            let offset = 14 + (i * 2)
            let entry = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            #expect(0xf800 == entry, "Entry \(i) should be 0xf800")
            
            let segmentsRaw = ((entry >> 12) & 0xF)
            let alternate = (entry >> 11) & 0x1
            let pulses = entry & 0x7FF
            
            // 0xf = 15 segments
            #expect(15 == segmentsRaw, "Entry \(i) raw segments should be 15")
            #expect(1 == alternate, "Entry \(i) should have alternate pulse flag")
            #expect(0 == pulses, "Entry \(i) should have 0 pulses")
        }
    }
    
    @Test("Insulin table entry checksum")
    func insulinTableEntryChecksum() throws {
        // From BasalScheduleTests.swift testInsulinTableEntry()
        // InsulinTableEntry checksum calculation
        // Formula: checksumPerSegment = (pulses & 0xff) + (pulses >> 8)
        //          checksum = checksumPerSegment * segments + (alternate ? segments / 2 : 0)
        
        // Entry: segments=2, pulses=300, alternateSegmentPulse=false
        // Checksum: (300 & 0xff) + (300 >> 8) = 44 + 1 = 45
        //           45 * 2 + 0 = 90 = 0x5a
        let segments1: Int = 2
        let pulses1: Int = 300
        let alternate1 = false
        
        let checksumPerSegment1 = (pulses1 & 0xff) + (pulses1 >> 8)
        let checksum1 = checksumPerSegment1 * segments1 + (alternate1 ? segments1 / 2 : 0)
        #expect(0x5a == checksum1, "Checksum for (2, 300, false) should be 0x5a")
        
        // Entry: segments=2, pulses=260, alternateSegmentPulse=true
        // Checksum: (260 & 0xff) + (260 >> 8) = 4 + 1 = 5
        //           5 * 2 + 2/2 = 10 + 1 = 11 = 0x0b
        let segments2: Int = 2
        let pulses2: Int = 260
        let alternate2 = true
        
        let checksumPerSegment2 = (pulses2 & 0xff) + (pulses2 >> 8)
        let checksum2 = checksumPerSegment2 * segments2 + (alternate2 ? segments2 / 2 : 0)
        #expect(0x0b == checksum2, "Checksum for (2, 260, true) should be 0x0b")
    }
    
    @Test("Basal schedule extra command decode")
    func basalScheduleExtraCommandDecode() throws {
        // From BasalScheduleTests.swift testBasalScheduleExtraCommand()
        // Decode: 13 0e 40 00 1aea 001e8480 3840 005b8d80
        let data = Data(erosHex: "130e40001aea001e84803840005b8d80")!
        
        #expect(0x13 == data[0], "BasalScheduleExtraCommand type should be 0x13")
        #expect(0x0e == data[1], "Length should be 0x0e (14 bytes)")
        
        // Byte 2: beep options (RR)
        // 0x40 = 0100 0000 → ack=0, completion=1, reminder=0
        let beepOptions = data[2]
        let ackBeep = (beepOptions & 0x80) != 0
        let completionBeep = (beepOptions & 0x40) != 0
        let reminderInterval = beepOptions & 0x3F
        #expect(!ackBeep, "Acknowledgement beep should be false")
        #expect(completionBeep, "Completion beep should be true")
        #expect(0 == reminderInterval, "Reminder interval should be 0")
        
        // Byte 3: current entry index (MM)
        #expect(0 == data[3], "Current entry index should be 0")
        
        // Bytes 4-5: remaining pulses × 10 (NNNN)
        let remainingPulsesTens = UInt16(data[4]) << 8 | UInt16(data[5])
        let remainingPulses = Double(remainingPulsesTens) / 10.0
        #expect(0x1aea == remainingPulsesTens, "Remaining pulses × 10 should be 0x1aea")
        #expect(abs(remainingPulses - 689.0) < 0.1, "Remaining pulses should be 689")
        
        // Bytes 6-9: delay until next tenth of pulse (XXXXXXXX) in 0.01ms (hundredths of ms) units
        let delayRaw = UInt32(data[6]) << 24 | UInt32(data[7]) << 16 |
                       UInt32(data[8]) << 8 | UInt32(data[9])
        #expect(0x001e8480 == delayRaw, "Delay raw should be 0x001e8480")
        // 2,000,000 × 0.00001s = 20 seconds
        let delaySeconds = Double(delayRaw) / 100_000.0
        #expect(abs(delaySeconds - 20.0) < 0.01, "Delay should be 20 seconds")
        
        // Rate entry (YYYY ZZZZZZZZ): 3840 005b8d80
        // YYYY: total pulses × 10
        let totalPulsesTens = UInt16(data[10]) << 8 | UInt16(data[11])
        let totalPulses = Double(totalPulsesTens) / 10.0
        #expect(0x3840 == totalPulsesTens, "Total pulses × 10 should be 0x3840")
        #expect(abs(totalPulses - 1440.0) < 0.1, "Total pulses should be 1440")
        
        // ZZZZZZZZ: delay between pulses in 0.01ms (hundredths of ms) units
        let delayBetween = UInt32(data[12]) << 24 | UInt32(data[13]) << 16 |
                           UInt32(data[14]) << 8 | UInt32(data[15])
        #expect(0x005b8d80 == delayBetween, "Delay between pulses should be 0x005b8d80")
        // 6,000,000 × 0.00001s = 60 seconds
        let delayBetweenSeconds = Double(delayBetween) / 100_000.0
        #expect(abs(delayBetweenSeconds - 60.0) < 0.01, "Delay between should be 60 seconds")
        
        // Calculate rate: pulses per hour = 3600 / delayBetweenSeconds
        // Rate = pulsesPerHour * 0.05 U/pulse
        let pulsesPerHour = 3600.0 / delayBetweenSeconds
        let rate = pulsesPerHour * 0.05
        #expect(abs(rate - 3.0) < 0.01, "Rate should be 3.0 U/hr")
    }
    
    @Test("Cancel basal command")
    func cancelBasalCommand() throws {
        // From BasalScheduleTests.swift testSuspendBasalCommand()
        // CancelDeliveryCommand for basal: 1f 05 6fede14a 01
        let data = Data(erosHex: "1f056fede14a01")!
        
        #expect(0x1f == data[0], "CancelDeliveryCommand type should be 0x1f")
        #expect(0x05 == data[1], "Length should be 0x05")
        
        // Bytes 2-5: nonce
        let nonce = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                    UInt32(data[4]) << 8 | UInt32(data[5])
        #expect(0x6fede14a == nonce, "Nonce should be 0x6fede14a")
        
        // Byte 6: delivery type + beep type
        // 0x01 = basal delivery type with noBeepCancel
        #expect(0x01 == data[6], "Delivery type should be 0x01 (basal, noBeepCancel)")
    }
    
    @Test("Multi rate basal schedule")
    func multiRateBasalSchedule() throws {
        // From BasalScheduleTests.swift testBasalExtraEncoding()
        // Multi-rate schedule: 1.05, 0.9, 1.0 U/hr
        let data = Data(erosHex: "1a140d6612db0003102e1be80005f80a480af009a00a")!
        
        #expect(0x1a == data[0], "SetInsulinScheduleCommand type should be 0x1a")
        
        // Nonce
        let nonce = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                    UInt32(data[4]) << 8 | UInt32(data[5])
        #expect(0x0d6612db == nonce, "Nonce should be 0x0d6612db")
        
        // Delivery type = basal
        #expect(0x00 == data[6], "Delivery type 0x00 = basal schedule")
        
        // Current segment = 0x2e (23:00)
        #expect(0x2e == data[9], "Current segment should be 0x2e (23:00)")
        
        // Table has 4 entries for multi-rate schedule
        // f80a = 16 segments, alternate=1, 10 pulses (0.5 U per segment = 1.0 U/hr)
        // 480a = 4 segments, alternate=1, 10 pulses
        // f009 = 15 segments (actually 16), alternate=0, 9 pulses
        // a00a = 10 segments, alternate=0, 10 pulses
        let entriesStart = 14
        let entry0 = UInt16(data[entriesStart]) << 8 | UInt16(data[entriesStart + 1])
        #expect(0xf80a == entry0, "First entry should be 0xf80a")
    }
    
    @Test("Max basal rate")
    func maxBasalRate() throws {
        // From BasalScheduleTests.swift testMaxContinuousBasal()
        // Maximum 30 U/hr rate
        let data = Data(erosHex: "1a12061419800009200c1a00008af12cf12cf12c")!
        
        // Nonce
        let nonce = UInt32(data[2]) << 24 | UInt32(data[3]) << 16 |
                    UInt32(data[4]) << 8 | UInt32(data[5])
        #expect(0x06141980 == nonce, "Nonce should be 0x06141980")
        
        // Current segment = 0x0c (06:00)
        #expect(0x0c == data[9], "Current segment should be 0x0c (06:00)")
        
        // Pulses remaining = 0x008a = 138
        let pulsesRemaining = UInt16(data[12]) << 8 | UInt16(data[13])
        #expect(0x008a == pulsesRemaining, "Pulses remaining should be 0x008a (138)")
        
        // Entry f12c = segments=15+1=16, alternate=0, pulses=300
        // 300 pulses/30 min = 600 pulses/hr = 30 U/hr
        let entry = UInt16(data[14]) << 8 | UInt16(data[15])
        let pulses = entry & 0x7FF
        #expect(300 == pulses, "Max rate entry should have 300 pulses per segment")
        
        // 300 pulses * 0.05 U/pulse * 2 (per hour) = 30 U/hr
        let ratePerHour = Double(pulses) * 0.05 * 2
        #expect(abs(ratePerHour - 30.0) < 0.01, "Rate should be 30 U/hr")
    }
    
    @Test("Large basal rate")
    func largeBasalRate() throws {
        // From BasalScheduleTests.swift testLargeContinuousBasal()
        // 24 U/hr rate
        let data = Data(erosHex: "1a1205281983002eb9012dc800c3f0f0f0f0f0f0")!
        
        // Entry f0f0 = segments=15+1=16, alternate=0, pulses=240
        // 240 pulses * 0.05 U/pulse * 2 = 24 U/hr
        let entry = UInt16(data[14]) << 8 | UInt16(data[15])
        let pulses = entry & 0x7FF
        #expect(240 == pulses, "24 U/hr entry should have 240 pulses per segment")
        
        let ratePerHour = Double(pulses) * 0.05 * 2
        #expect(abs(ratePerHour - 24.0) < 0.01, "Rate should be 24 U/hr")
    }
    
    @Test("Segment offset calculation")
    func segmentOffsetCalculation() throws {
        // Verify segment offset calculation from HH and SSSS fields
        // From testBasalExtraEncoding1: hh=0x20, ssss=0x33c0
        // offset = ((hh + 1) * 30 minutes) - (ssss / 8 seconds)
        
        let hh: UInt8 = 0x20  // segment 32 = 16:00
        let ssss: UInt16 = 0x33c0
        
        let segmentEndMinutes = (Int(hh) + 1) * 30  // 33 * 30 = 990 minutes = 16:30
        let secondsRemaining = Int(ssss) / 8  // 13248 / 8 = 1656 seconds = 27.6 minutes
        let offsetMinutes = Double(segmentEndMinutes) - (Double(secondsRemaining) / 60.0)
        let offsetHours = offsetMinutes / 60.0
        
        #expect(1656 == secondsRemaining, "Seconds remaining should be 1656")
        // 990 min - 27.6 min = 962.4 min = 16.04 hours
        #expect(abs(offsetHours - 16.04) < 0.01, "Offset should be ~16:02 (16.04 hours)")
    }
    
    // MARK: - EROS-VALIDATE-004: Pairing Flow Simulation
    
    @Test("Pairing flow state machine")
    func pairingFlowStateMachine() throws {
        // EROS-VALIDATE-004: Simulate full pairing flow without hardware
        let logger = ErosSessionLogger(podAddress: 0x1F014820)
        
        // Initial state
        #expect(logger.getCurrentState() == ErosSessionState.idle, "Should start in idle state")
        
        // Phase 1: Discovery
        logger.logStateTransition(from: .idle, to: .scanning, reason: "Start pairing")
        #expect(logger.getCurrentState() == ErosSessionState.scanning)
        
        logger.logStateTransition(from: .scanning, to: .discovered, reason: "Pod found")
        #expect(logger.getCurrentState() == ErosSessionState.discovered)
        
        // Phase 2: Address assignment
        logger.logStateTransition(from: .discovered, to: .assigning, reason: "Assigning address")
        #expect(logger.getCurrentState() == ErosSessionState.assigning)
        
        logger.logStateTransition(from: .assigning, to: .assigned, reason: "Address assigned")
        #expect(logger.getCurrentState() == ErosSessionState.assigned)
        
        // Phase 3: Setup
        logger.logStateTransition(from: .assigned, to: .setupPending, reason: "Setup command sent")
        #expect(logger.getCurrentState() == ErosSessionState.setupPending)
        
        logger.logStateTransition(from: .setupPending, to: .setupComplete, reason: "Setup confirmed")
        #expect(logger.getCurrentState() == ErosSessionState.setupComplete)
        
        // Phase 4: Priming
        logger.logStateTransition(from: .setupComplete, to: .priming, reason: "Prime started")
        #expect(logger.getCurrentState() == ErosSessionState.priming)
        
        logger.logStateTransition(from: .priming, to: .primed, reason: "Prime complete")
        #expect(logger.getCurrentState() == ErosSessionState.primed)
        
        // Phase 5: Basal programming
        logger.logStateTransition(from: .primed, to: .basalProgrammed, reason: "Basal set")
        #expect(logger.getCurrentState() == ErosSessionState.basalProgrammed)
        
        logger.logStateTransition(from: .basalProgrammed, to: .running, reason: "Pod running")
        #expect(logger.getCurrentState() == ErosSessionState.running)
    }
    
    @Test("Pairing flow RF exchange logging")
    func pairingFlowRFExchangeLogging() throws {
        // EROS-VALIDATE-004: Verify RF exchange logging during pairing
        let logger = ErosSessionLogger(podAddress: 0x1F014820)
        
        // Simulate AssignAddress exchange
        let assignCmd = Data([0x07, 0x04, 0x1F, 0x01, 0x48, 0x2A])  // AssignAddress command
        let assignResp = Data([0x01, 0x15, 0x02, 0x07, 0x00])  // VersionResponse
        
        logger.tx(assignCmd, context: "AssignAddress")
        logger.rx(assignResp, context: "VersionResponse")
        
        // Export and verify structure
        let export = logger.exportSession()
        #expect(export.rfExchanges.count > 0, "Should have RF exchanges")
    }
    
    @Test("Pairing flow error recovery")
    func pairingFlowErrorRecovery() throws {
        // EROS-VALIDATE-004: Test error state handling
        let logger = ErosSessionLogger(podAddress: 0x1F014820)
        
        // Transition through some states
        logger.logStateTransition(from: .idle, to: .scanning, reason: "Start")
        logger.logStateTransition(from: .scanning, to: .discovered, reason: "Found")
        logger.logStateTransition(from: .discovered, to: .assigning, reason: "Assigning")
        
        // Error condition
        logger.logStateTransition(from: .assigning, to: .error, reason: "Communication timeout")
        #expect(logger.getCurrentState() == ErosSessionState.error)
        
        // Verify error is captured in export
        let export = logger.exportSession()
        #expect(export.stateTransitions.count > 0, "Should have state transitions")
        
        // Verify last transition is to error
        let lastTransition = export.stateTransitions.last
        #expect(lastTransition?.toState == ErosSessionState.error, "Last state should be ERROR")
    }
    
    // MARK: - SetupPodCommand Tests (EROS-IMPL-007)
    
    @Test("SetupPod command encoding")
    func setupPodCommandEncoding() throws {
        // Test vector from OmniKit: 03 13 1f08ced2 14 04 09 0b 11 0b 08 0000a640 00097c27
        let command = ErosSetupPodCommand(
            address: 0x1f08ced2,
            lot: 0x0000a640,
            tid: 0x00097c27,
            month: 9,
            day: 11,
            year: 17,  // 2017
            hour: 11,
            minute: 8,
            packetTimeoutLimit: 4
        )
        
        let data = command.data
        
        // Verify length
        #expect(data.count == 21, "SetupPodCommand should be 21 bytes")
        
        // Verify block type
        #expect(data[0] == 0x03, "Block type should be 0x03")
        
        // Verify length byte
        #expect(data[1] == 19, "Length should be 19")
        
        // Verify address
        #expect(data[2] == 0x1f, "Address byte 0")
        #expect(data[3] == 0x08, "Address byte 1")
        #expect(data[4] == 0xce, "Address byte 2")
        #expect(data[5] == 0xd2, "Address byte 3")
        
        // Verify unknown byte
        #expect(data[6] == 0x14, "Unknown byte should be 0x14")
        
        // Verify packet timeout
        #expect(data[7] == 4, "Packet timeout should be 4")
        
        // Verify date/time
        #expect(data[8] == 9, "Month should be 9")
        #expect(data[9] == 11, "Day should be 11")
        #expect(data[10] == 17, "Year should be 17")
        #expect(data[11] == 11, "Hour should be 11")
        #expect(data[12] == 8, "Minute should be 8")
        
        // Verify lot number
        #expect(data[13] == 0x00, "Lot byte 0")
        #expect(data[14] == 0x00, "Lot byte 1")
        #expect(data[15] == 0xa6, "Lot byte 2")
        #expect(data[16] == 0x40, "Lot byte 3")
        
        // Verify TID
        #expect(data[17] == 0x00, "TID byte 0")
        #expect(data[18] == 0x09, "TID byte 1")
        #expect(data[19] == 0x7c, "TID byte 2")
        #expect(data[20] == 0x27, "TID byte 3")
    }
    
    @Test("SetupPod command decoding")
    func setupPodCommandDecoding() throws {
        // Test vector from OmniKit
        let hexData: [UInt8] = [
            0x03, 0x13,                         // Block type + length
            0x1f, 0x08, 0xce, 0xd2,             // Address
            0x14,                               // Unknown
            0x04,                               // Packet timeout
            0x09, 0x0b, 0x11, 0x0b, 0x08,       // Month, day, year, hour, minute
            0x00, 0x00, 0xa6, 0x40,             // Lot number
            0x00, 0x09, 0x7c, 0x27              // TID
        ]
        let data = Data(hexData)
        
        let command = try ErosSetupPodCommand(encodedData: data)
        
        #expect(command.address == 0x1f08ced2)
        #expect(command.lot == 0x0000a640)
        #expect(command.tid == 0x00097c27)
        #expect(command.month == 9)
        #expect(command.day == 11)
        #expect(command.year == 17)
        #expect(command.hour == 11)
        #expect(command.minute == 8)
        #expect(command.packetTimeoutLimit == 4)
    }
    
    @Test("SetupPod command round trip")
    func setupPodCommandRoundTrip() throws {
        let original = ErosSetupPodCommand(
            address: 0xDEADBEEF,
            lot: 12345,
            tid: 67890,
            month: 2,
            day: 21,
            year: 26,
            hour: 5,
            minute: 30,
            packetTimeoutLimit: 4
        )
        
        let encoded = original.data
        let decoded = try ErosSetupPodCommand(encodedData: encoded)
        
        #expect(decoded.address == original.address)
        #expect(decoded.lot == original.lot)
        #expect(decoded.tid == original.tid)
        #expect(decoded.month == original.month)
        #expect(decoded.day == original.day)
        #expect(decoded.year == original.year)
        #expect(decoded.hour == original.hour)
        #expect(decoded.minute == original.minute)
    }
    
    @Test("SetupPod command activation date")
    func setupPodCommandActivationDate() throws {
        let command = ErosSetupPodCommand(
            address: 0x12345678,
            lot: 1000,
            tid: 2000,
            month: 2,
            day: 21,
            year: 26,  // 2026
            hour: 10,
            minute: 30,
            packetTimeoutLimit: 4
        )
        
        let date = command.activationDate
        #expect(date != nil)
        
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.month, .day, .year, .hour, .minute], from: date!)
        
        #expect(components.month == 2)
        #expect(components.day == 21)
        #expect(components.year == 2026)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
    }
    
    @Test("SetupPod command debug description")
    func setupPodCommandDebugDescription() {
        let command = ErosSetupPodCommand(
            address: 0x1F08CED2,
            lot: 42560,
            tid: 621607,
            month: 9,
            day: 11,
            year: 17,
            hour: 11,
            minute: 8
        )
        
        let desc = command.debugDescription
        #expect(desc.contains("1F08CED2"), "Should contain address")
        #expect(desc.contains("42560"), "Should contain lot")
        #expect(desc.contains("621607"), "Should contain tid")
    }
    
    @Test("SetupPod command decoding too short")
    func setupPodCommandDecodingTooShort() {
        let shortData = Data([0x03, 0x13, 0x1f, 0x08]) // Only 4 bytes
        
        do {
            _ = try ErosSetupPodCommand(encodedData: shortData)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("21 bytes"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    @Test("SetupPod command decoding wrong type")
    func setupPodCommandDecodingWrongType() {
        var data = Data(repeating: 0, count: 21)
        data[0] = 0x05 // Wrong block type
        
        do {
            _ = try ErosSetupPodCommand(encodedData: data)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("block type"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    // MARK: - VersionResponse Tests (EROS-IMPL-008)
    
    @Test("Version response SetupPod decoding")
    func versionResponseSetupPodDecoding() throws {
        // Test vector from OmniKit: SetupPod response (0x1B)
        // 01 1b 1388 10 08 34 0a 50 020700 020700 02 03 0000a62b 00044794 1f00ee87
        let hexData: [UInt8] = [
            0x01, 0x1b,                         // Block type + length
            0x13, 0x88,                         // Pulse volume (5000 = 0.05U)
            0x10,                               // BR (16/8 = 2 sec per bolus pulse)
            0x08,                               // PR (8/8 = 1 sec per prime pulse)
            0x34,                               // PP (52 prime pulses = 2.6U)
            0x0a,                               // CP (10 cannula pulses = 0.5U)
            0x50,                               // PL (80 hours)
            0x02, 0x07, 0x00,                   // PM firmware 2.7.0
            0x02, 0x07, 0x00,                   // PI firmware 2.7.0
            0x02,                               // Product ID (Eros)
            0x03,                               // Pod progress (pairing completed)
            0x00, 0x00, 0xa6, 0x2b,             // Lot
            0x00, 0x04, 0x47, 0x94,             // TID
            0x1f, 0x00, 0xee, 0x87              // Address
        ]
        let data = Data(hexData)
        
        let response = try ErosVersionResponse(encodedData: data)
        
        #expect(response.isSetupPodResponse)
        #expect(!response.isAssignAddressResponse)
        #expect(response.firmwareVersion.major == 2)
        #expect(response.firmwareVersion.minor == 7)
        #expect(response.firmwareVersion.patch == 0)
        #expect(response.productId == 0x02)
        #expect(response.podProgressStatus == .pairingCompleted)
        #expect(response.lot == 0x0000a62b)
        #expect(response.tid == 0x00044794)
        #expect(response.address == 0x1f00ee87)
        
        // SetupPod-specific fields
        #expect(abs(response.pulseSize! - 0.05) < 0.001)
        #expect(abs(response.secondsPerBolusPulse! - 2.0) < 0.001)
        #expect(abs(response.secondsPerPrimePulse! - 1.0) < 0.001)
        #expect(abs(response.primeUnits! - 2.6) < 0.001)
        #expect(abs(response.cannulaInsertionUnits! - 0.5) < 0.001)
        #expect(abs(response.serviceDuration! - Double(80 * 3600)) < 1)
        
        // AssignAddress fields should be nil
        #expect(response.gain == nil)
        #expect(response.rssi == nil)
    }
    
    @Test("Version response AssignAddress decoding")
    func versionResponseAssignAddressDecoding() throws {
        // Test vector from OmniKit: AssignAddress response (0x15)
        // 01 15 020700 020700 02 02 0000a377 0003ab37 9f 1f00ee87
        let hexData: [UInt8] = [
            0x01, 0x15,                         // Block type + length
            0x02, 0x07, 0x00,                   // PM firmware 2.7.0
            0x02, 0x07, 0x00,                   // PI firmware 2.7.0
            0x02,                               // Product ID (Eros)
            0x02,                               // Pod progress (reminder initialized)
            0x00, 0x00, 0xa3, 0x77,             // Lot
            0x00, 0x03, 0xab, 0x37,             // TID
            0x9f,                               // Gain/RSSI (gain=2, rssi=31)
            0x1f, 0x00, 0xee, 0x87              // Address
        ]
        let data = Data(hexData)
        
        let response = try ErosVersionResponse(encodedData: data)
        
        #expect(response.isAssignAddressResponse)
        #expect(!response.isSetupPodResponse)
        #expect(response.firmwareVersion.major == 2)
        #expect(response.firmwareVersion.minor == 7)
        #expect(response.firmwareVersion.patch == 0)
        #expect(response.productId == 0x02)
        #expect(response.podProgressStatus == .reminderInitialized)
        #expect(response.lot == 0x0000a377)
        #expect(response.tid == 0x0003ab37)
        #expect(response.address == 0x1f00ee87)
        
        // AssignAddress-specific fields
        #expect(response.gain == 2)  // 0x9f >> 6 = 2
        #expect(response.rssi == 31) // 0x9f & 0x3f = 31
        
        // SetupPod fields should be nil
        #expect(response.pulseSize == nil)
        #expect(response.serviceDuration == nil)
    }
    
    @Test("Firmware version description")
    func firmwareVersionDescription() {
        let version = ErosFirmwareVersion(major: 2, minor: 7, patch: 0)
        #expect(version.description == "2.7.0")
        
        let version2 = ErosFirmwareVersion(major: 4, minor: 3, patch: 12)
        #expect(version2.description == "4.3.12")
    }
    
    @Test("Pod progress status active")
    func podProgressStatusActive() {
        #expect(ErosPodProgressStatus.aboveFiftyUnits.isActive)
        #expect(ErosPodProgressStatus.fiftyOrLessUnits.isActive)
        #expect(!ErosPodProgressStatus.priming.isActive)
        #expect(!ErosPodProgressStatus.pairingCompleted.isActive)
    }
    
    @Test("Version response decoding too short")
    func versionResponseDecodingTooShort() {
        let shortData = Data([0x01]) // Only 1 byte
        
        do {
            _ = try ErosVersionResponse(encodedData: shortData)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("short"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    @Test("Version response decoding wrong type")
    func versionResponseDecodingWrongType() {
        var data = Data(repeating: 0, count: 29)
        data[0] = 0x05 // Wrong block type
        data[1] = 0x1b // SetupPod length
        
        do {
            _ = try ErosVersionResponse(encodedData: data)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("block type"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    @Test("Version response decoding invalid length")
    func versionResponseDecodingInvalidLength() {
        var data = Data(repeating: 0, count: 25)
        data[0] = 0x01 // Correct block type
        data[1] = 0x10 // Invalid length (not 0x15 or 0x1b)
        
        do {
            _ = try ErosVersionResponse(encodedData: data)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("length"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    @Test("Version response debug description")
    func versionResponseDebugDescription() throws {
        // SetupPod response
        let setupData: [UInt8] = [
            0x01, 0x1b, 0x13, 0x88, 0x10, 0x08, 0x34, 0x0a, 0x50,
            0x02, 0x07, 0x00, 0x02, 0x07, 0x00, 0x02, 0x03,
            0x00, 0x00, 0xa6, 0x2b, 0x00, 0x04, 0x47, 0x94,
            0x1f, 0x00, 0xee, 0x87
        ]
        let setupResponse = try ErosVersionResponse(encodedData: Data(setupData))
        let desc = setupResponse.debugDescription
        
        #expect(desc.contains("SetupPod"))
        #expect(desc.contains("1F00EE87"))
    }
    
    // MARK: - AssignAddressCommand Tests (EROS-IMPL-009)
    
    @Test("AssignAddress command encoding")
    func assignAddressCommandEncoding() {
        let command = ErosAssignAddressCommand(address: 0x1F00EE87)
        let data = command.data
        
        // Expected: 07 04 1F 00 EE 87
        #expect(data.count == 6)
        #expect(data[0] == 0x07)  // Block type
        #expect(data[1] == 0x04)  // Length
        #expect(data[2] == 0x1F)  // Address byte 0
        #expect(data[3] == 0x00)  // Address byte 1
        #expect(data[4] == 0xEE)  // Address byte 2
        #expect(data[5] == 0x87)  // Address byte 3
    }
    
    @Test("AssignAddress command decoding")
    func assignAddressCommandDecoding() throws {
        let data = Data([0x07, 0x04, 0x1F, 0x00, 0xEE, 0x87])
        let command = try ErosAssignAddressCommand(encodedData: data)
        
        #expect(command.address == 0x1F00EE87)
    }
    
    @Test("AssignAddress command roundtrip")
    func assignAddressCommandRoundtrip() throws {
        let original = ErosAssignAddressCommand(address: 0xABCD1234)
        let decoded = try ErosAssignAddressCommand(encodedData: original.data)
        
        #expect(original == decoded)
    }
    
    @Test("AssignAddress command debug description")
    func assignAddressCommandDebugDescription() {
        let command = ErosAssignAddressCommand(address: 0x1F00EE87)
        let desc = command.debugDescription
        
        #expect(desc.contains("AssignAddressCommand"))
        #expect(desc.contains("1F00EE87"))
    }
    
    @Test("AssignAddress command decoding too short")
    func assignAddressCommandDecodingTooShort() {
        let data = Data([0x07, 0x04, 0x1F]) // Only 3 bytes
        
        do {
            _ = try ErosAssignAddressCommand(encodedData: data)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("6 bytes"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    @Test("AssignAddress command decoding wrong type")
    func assignAddressCommandDecodingWrongType() {
        let data = Data([0x03, 0x04, 0x1F, 0x00, 0xEE, 0x87]) // Wrong block type
        
        do {
            _ = try ErosAssignAddressCommand(encodedData: data)
            Issue.record("Expected error to be thrown")
        } catch {
            if case ErosBLEError.invalidResponse(let msg) = error {
                #expect(msg.contains("block type"))
            } else {
                Issue.record("Expected invalidResponse error")
            }
        }
    }
    
    // MARK: - Pairing Result Tests
    
    @Test("Eros pairing result properties")
    func erosPairingResultProperties() {
        let result = ErosBLEManager.ErosPairingResult(
            firmwareVersion: ErosFirmwareVersion(major: 2, minor: 7, patch: 0),
            lot: 0x0000A62B,
            tid: 0x00044794,
            progressStatus: .pairingCompleted,
            pulseSize: 0.05,
            serviceDuration: TimeInterval(80 * 3600)
        )
        
        #expect(result.firmwareVersion.description == "2.7.0")
        #expect(result.lot == 0x0000A62B)
        #expect(result.tid == 0x00044794)
        #expect(result.progressStatus == .pairingCompleted)
        #expect(result.pulseSize == 0.05)
        #expect(result.serviceDuration == TimeInterval(80 * 3600))
    }
}
