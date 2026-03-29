// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaCommandSerializationTests.swift
// PumpKitTests
//
// Tests for Dana command serialization (DANA-IMPL-003).
// Verifies command encoding, response parsing, and packet structure.

import Testing
import Foundation
@testable import PumpKit

@Suite("Dana Command Serialization Tests")
struct DanaCommandSerializationTests {
    
    // MARK: - Packet Type Constants
    
    @Test("Packet type constants")
    func packetTypeConstants() {
        #expect(DanaPacketType.encryptionRequest.rawValue == 0x01)
        #expect(DanaPacketType.encryptionResponse.rawValue == 0x02)
        #expect(DanaPacketType.command.rawValue == 0xA1)
        #expect(DanaPacketType.response.rawValue == 0xB2)
        #expect(DanaPacketType.notify.rawValue == 0xC3)
    }
    
    // MARK: - Opcode Constants
    
    @Test("Opcode constants")
    func opcodeConstants() {
        // Encryption opcodes
        #expect(DanaOpcode.PUMP_CHECK == 0x00)
        #expect(DanaOpcode.TIME_INFORMATION == 0x01)
        #expect(DanaOpcode.CHECK_PASSKEY == 0xD0)
        #expect(DanaOpcode.PASSKEY_REQUEST == 0xD1)
        
        // Basal opcodes
        #expect(DanaOpcode.SET_TEMP_BASAL == 0x60)
        #expect(DanaOpcode.CANCEL_TEMP_BASAL == 0x62)
        
        // Bolus opcodes
        #expect(DanaOpcode.SET_STEP_BOLUS_START == 0x4A)
        #expect(DanaOpcode.SET_STEP_BOLUS_STOP == 0x44)
        
        // Option opcodes
        #expect(DanaOpcode.GET_PUMP_TIME == 0x70)
        
        // APS opcodes
        #expect(DanaOpcode.APS_SET_TEMP_BASAL == 0xC1)
    }
    
    // MARK: - Command Factory Tests
    
    @Test("Pump check command")
    func pumpCheckCommand() {
        let command = DanaPacket.pumpCheck(deviceName: "DANA-i1234")
        
        #expect(command.packetType == .encryptionRequest)
        #expect(command.opcode == DanaOpcode.PUMP_CHECK)
        #expect(command.isEncryptionCommand)
        #expect(command.payload.count == 10, "Device name should be 10 bytes")
        #expect(command.deviceName == "DANA-i1234")
    }
    
    @Test("Time information command")
    func timeInformationCommand() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let command = DanaPacket.timeInformation(
            data: data,
            deviceName: "DANA-i1234",
            encryptionType: .legacy
        )
        
        #expect(command.packetType == .encryptionRequest)
        #expect(command.opcode == DanaOpcode.TIME_INFORMATION)
        #expect(command.isEncryptionCommand)
    }
    
    @Test("Time information command BLE5 modification")
    func timeInformationCommand_BLE5Modification() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let command = DanaPacket.timeInformation(
            data: data,
            deviceName: "DANA-i1234",
            encryptionType: .ble5
        )
        
        // BLE5 should modify bytes 1, 2, 3
        #expect(command.payload[1] == 0x17 ^ 0x1A)  // 0x0D
        #expect(command.payload[2] == 0xD1 ^ 0xC0)  // 0x11
        #expect(command.payload[3] == 0xAF ^ 0xA9)  // 0x06
    }
    
    @Test("Check passkey command")
    func checkPasskeyCommand() {
        let passkey = Data([0x01, 0x02, 0x03, 0x04])
        let command = DanaPacket.checkPasskey(
            passkey: passkey,
            deviceName: "DANA-i1234"
        )
        
        #expect(command.packetType == .encryptionRequest)
        #expect(command.opcode == DanaOpcode.CHECK_PASSKEY)
        #expect(command.isEncryptionCommand)
        #expect(command.payload.count == passkey.count)
    }
    
    @Test("Encryption request command")
    func encryptionRequestCommand() {
        let command = DanaPacket.encryptionRequest(
            opcode: DanaOpcode.PASSKEY_REQUEST,
            deviceName: "DANA-i1234"
        )
        
        #expect(command.packetType == .encryptionRequest)
        #expect(command.opcode == DanaOpcode.PASSKEY_REQUEST)
        #expect(command.isEncryptionCommand)
        #expect(command.payload.isEmpty)
    }
    
    // MARK: - Normal Command Factory Tests
    
    @Test("Get pump time command")
    func getPumpTimeCommand() {
        let command = DanaPacket.getPumpTime(deviceName: "DANA-i1234")
        
        #expect(command.packetType == .command)
        #expect(command.opcode == DanaOpcode.GET_PUMP_TIME)
        #expect(!command.isEncryptionCommand)
        #expect(command.payload.isEmpty)
    }
    
    @Test("Set temp basal command")
    func setTempBasalCommand() {
        let command = DanaPacket.setTempBasal(
            percent: 150,
            durationHours: 2,
            deviceName: "DANA-i1234"
        )
        
        #expect(command.packetType == .command)
        #expect(command.opcode == DanaOpcode.SET_TEMP_BASAL)
        #expect(!command.isEncryptionCommand)
        #expect(command.payload.count == 2)
        #expect(command.payload[0] == 150)  // percent
        #expect(command.payload[1] == 2)    // hours
    }
    
    @Test("Cancel temp basal command")
    func cancelTempBasalCommand() {
        let command = DanaPacket.cancelTempBasal(deviceName: "DANA-i1234")
        
        #expect(command.opcode == DanaOpcode.CANCEL_TEMP_BASAL)
        #expect(command.payload.isEmpty)
    }
    
    @Test("Start bolus command")
    func startBolusCommand() {
        let command = DanaPacket.startBolus(
            amount: 2.5,
            speed: 12,
            deviceName: "DANA-i1234"
        )
        
        #expect(command.packetType == .command)
        #expect(command.opcode == DanaOpcode.SET_STEP_BOLUS_START)
        #expect(command.payload.count == 3)
        
        // 2.5 units = 250 in 0.01U = 0x00FA
        #expect(command.payload[0] == 0xFA)  // Low byte
        #expect(command.payload[1] == 0x00)  // High byte
        #expect(command.payload[2] == 12)    // Speed
    }
    
    @Test("Start bolus command larger amount")
    func startBolusCommand_LargerAmount() {
        let command = DanaPacket.startBolus(
            amount: 10.25,
            speed: 8,
            deviceName: "DANA-i1234"
        )
        
        // 10.25 units = 1025 in 0.01U = 0x0401
        #expect(command.payload[0] == 0x01)  // Low byte
        #expect(command.payload[1] == 0x04)  // High byte
        #expect(command.payload[2] == 8)     // Speed
    }
    
    @Test("Stop bolus command")
    func stopBolusCommand() {
        let command = DanaPacket.stopBolus(deviceName: "DANA-i1234")
        
        #expect(command.opcode == DanaOpcode.SET_STEP_BOLUS_STOP)
        #expect(command.payload.isEmpty)
    }
    
    @Test("Keep connection command")
    func keepConnectionCommand() {
        let command = DanaPacket.keepConnection(deviceName: "DANA-i1234")
        
        #expect(command.opcode == DanaOpcode.KEEP_CONNECTION)
        #expect(command.payload.isEmpty)
    }
    
    @Test("Get delivery status command")
    func getDeliveryStatusCommand() {
        let command = DanaPacket.getDeliveryStatus(deviceName: "DANA-i1234")
        
        #expect(command.opcode == DanaOpcode.DELIVERY_STATUS)
        #expect(command.payload.isEmpty)
    }
    
    // MARK: - Packet Encoding Tests
    
    @Test("Encode packet structure")
    func encodePacketStructure() {
        // Use a simple command to verify packet structure
        let command = DanaPacket.encryptionRequest(
            opcode: DanaOpcode.GET_PUMP_CHECK,
            deviceName: "DANA-i1234"
        )
        
        var encryption = DanaEncryption(encryptionType: .legacy)
        let packet = command.encode(encryption: &encryption)
        
        // Packet should have: header(2) + length(1) + type(1) + opcode(1) + crc(2) + footer(2) = 9 bytes minimum
        #expect(packet.count >= 9)
        
        // Note: Serial number encoding modifies packet, so we can't check raw header/footer
        // But packet size should be consistent
        #expect(packet.count == 9)  // No payload
    }
    
    @Test("Encode packet with payload")
    func encodePacketWithPayload() {
        let command = DanaPacket.setTempBasal(
            percent: 120,
            durationHours: 1,
            deviceName: "DANA-i1234"
        )
        
        var encryption = DanaEncryption(encryptionType: .legacy)
        let packet = command.encode(encryption: &encryption)
        
        // 9 base + 2 payload = 11 bytes
        #expect(packet.count == 11)
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("Dana response parsing success")
    func danaResponseParsing_Success() {
        // Create a mock response packet
        // Header: A5 A5, Length: 03, Type: B2, Opcode: 70, Payload: 00, CRC: xx xx, Footer: 5A 5A
        var responseData = Data([
            0xA5, 0xA5,  // Header
            0x03,        // Length (type + opcode + 1 payload)
            0xB2,        // Response type
            0x70,        // GET_PUMP_TIME opcode
            0x00,        // Success indicator
            0x00, 0x00,  // CRC placeholder
            0x5A, 0x5A   // Footer
        ])
        
        // Calculate and insert correct CRC
        let crcData = responseData.subdata(in: 3..<6)
        let crc = DanaCRC16.calculate(crcData, encryptionType: .legacy, isEncryptionCommand: false)
        responseData[6] = UInt8((crc >> 8) & 0xFF)
        responseData[7] = UInt8(crc & 0xFF)
        
        var encryption = DanaEncryption(encryptionType: .legacy)
        let response = DanaResponse.parse(
            from: responseData,
            encryption: &encryption,
            deviceName: "",
            isEncryptionResponse: false
        )
        
        #expect(response != nil)
        #expect(response?.packetType == DanaPacketType.response.rawValue)
        #expect(response?.opcode == DanaOpcode.GET_PUMP_TIME)
        #expect(response?.isSuccess ?? false)
        #expect(!(response?.isError ?? true))
    }
    
    @Test("Dana response parsing error")
    func danaResponseParsing_Error() {
        var responseData = Data([
            0xA5, 0xA5,  // Header
            0x03,        // Length
            0xB2,        // Response type
            0x70,        // Opcode
            0x01,        // Error indicator (non-zero)
            0x00, 0x00,  // CRC placeholder
            0x5A, 0x5A   // Footer
        ])
        
        // Calculate CRC
        let crcData = responseData.subdata(in: 3..<6)
        let crc = DanaCRC16.calculate(crcData, encryptionType: .legacy, isEncryptionCommand: false)
        responseData[6] = UInt8((crc >> 8) & 0xFF)
        responseData[7] = UInt8(crc & 0xFF)
        
        var encryption = DanaEncryption(encryptionType: .legacy)
        let response = DanaResponse.parse(
            from: responseData,
            encryption: &encryption,
            deviceName: "",
            isEncryptionResponse: false
        )
        
        #expect(response != nil)
        #expect(response?.isError ?? false)
        #expect(!(response?.isSuccess ?? true))
    }
    
    @Test("Dana response parsing too short")
    func danaResponseParsing_TooShort() {
        let responseData = Data([0xA5, 0xA5, 0x01])
        
        var encryption = DanaEncryption(encryptionType: .legacy)
        let response = DanaResponse.parse(
            from: responseData,
            encryption: &encryption,
            deviceName: "",
            isEncryptionResponse: false
        )
        
        #expect(response == nil, "Should fail to parse packet that's too short")
    }
    
    // MARK: - Pump Check Response Tests
    
    @Test("Pump check response legacy")
    func pumpCheckResponse_Legacy() {
        let data = Data([
            0xA5, 0xA5,  // Legacy markers
            0x06,        // Length
            0x02,        // Encryption response
            0x00,        // PUMP_CHECK
            0x05,        // Hardware model
            0x01,        // Protocol version
            0x02,        // Product code
            0x00, 0x00,  // CRC
            0x5A, 0x5A   // Legacy end markers
        ])
        
        let response = DanaPumpCheckResponse.parse(from: data)
        
        #expect(response != nil)
        #expect(response?.encryptionType == .legacy)
        #expect(response?.hardwareModel == 0x05)
        #expect(response?.protocolVersion == 0x01)
        #expect(response?.productCode == 0x02)
    }
    
    @Test("Pump check response RSv3")
    func pumpCheckResponse_RSv3() {
        let data = Data([
            0x7A, 0x7A,  // RSv3 markers
            0x06,        // Length
            0x02,        // Encryption response
            0x00,        // PUMP_CHECK
            0x07,        // Hardware model
            0x03,        // Protocol version
            0x01,        // Product code
            0x00, 0x00,  // CRC
            0x2E, 0x2E   // RSv3 end markers
        ])
        
        let response = DanaPumpCheckResponse.parse(from: data)
        
        #expect(response != nil)
        #expect(response?.encryptionType == .rsv3)
        #expect(response?.hardwareModel == 0x07)
    }
    
    @Test("Pump check response BLE5")
    func pumpCheckResponse_BLE5() {
        let data = Data([
            0xAA, 0xAA,  // BLE5 markers
            0x06,        // Length
            0x02,        // Encryption response
            0x00,        // PUMP_CHECK
            0x09,        // Hardware model
            0x02,        // Protocol version
            0x03,        // Product code
            0x00, 0x00,  // CRC
            0xEE, 0xEE   // BLE5 end markers
        ])
        
        let response = DanaPumpCheckResponse.parse(from: data)
        
        #expect(response != nil)
        #expect(response?.encryptionType == .ble5)
        #expect(response?.hardwareModel == 0x09)
    }
    
    @Test("Pump check response too short")
    func pumpCheckResponse_TooShort() {
        let data = Data([0xA5, 0xA5, 0x01, 0x02])
        let response = DanaPumpCheckResponse.parse(from: data)
        #expect(response == nil)
    }
    
    @Test("Pump check response unknown markers")
    func pumpCheckResponse_UnknownMarkers() {
        let data = Data([
            0x00, 0x00,  // Unknown markers
            0x06, 0x02, 0x00, 0x05, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00
        ])
        let response = DanaPumpCheckResponse.parse(from: data)
        #expect(response == nil)
    }
}
