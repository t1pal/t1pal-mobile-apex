// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaPacket.swift
// PumpKit
//
// Dana pump command serialization and packet construction.
// Implements command encoding/decoding for all Dana pump variants.
// Trace: DANA-IMPL-003, PRD-PUMP-002
//
// Usage:
//   let command = DanaPacket.pumpCheck(deviceName: "DANA-i123")
//   let packet = command.encode(encryption: &encryption)

import Foundation

// MARK: - Dana Packet Types

// MARK: - Dana Opcodes

/// Dana command opcodes organized by category
public enum DanaOpcode {
    // Encryption commands (pairing/handshake)
    public static let PUMP_CHECK: UInt8 = 0x00
    public static let TIME_INFORMATION: UInt8 = 0x01
    public static let CHECK_PASSKEY: UInt8 = 0xD0
    public static let PASSKEY_REQUEST: UInt8 = 0xD1
    public static let PASSKEY_RETURN: UInt8 = 0xD2
    public static let GET_PUMP_CHECK: UInt8 = 0xF3
    public static let GET_EASYMENU_CHECK: UInt8 = 0xF4
    
    // Review commands (status/history)
    public static let INITIAL_SCREEN: UInt8 = 0x02
    public static let DELIVERY_STATUS: UInt8 = 0x03
    public static let GET_PASSWORD: UInt8 = 0x04
    public static let BOLUS_AVG: UInt8 = 0x10
    public static let HISTORY_BOLUS: UInt8 = 0x11
    public static let HISTORY_DAILY: UInt8 = 0x12
    public static let HISTORY_PRIME: UInt8 = 0x13
    public static let HISTORY_REFILL: UInt8 = 0x14
    public static let HISTORY_BG: UInt8 = 0x15
    public static let HISTORY_CARB: UInt8 = 0x16
    public static let HISTORY_TEMP: UInt8 = 0x17
    public static let HISTORY_SUSPEND: UInt8 = 0x18
    public static let HISTORY_ALARM: UInt8 = 0x19
    public static let HISTORY_BASAL: UInt8 = 0x1A
    public static let HISTORY_ALL: UInt8 = 0x1F
    public static let GET_SHIPPING_INFO: UInt8 = 0x20
    public static let GET_PUMP_CHECK_REVIEW: UInt8 = 0x21
    public static let GET_USER_TIME_CHANGE: UInt8 = 0x22
    public static let CLEAR_USER_TIME_CHANGE: UInt8 = 0x23
    public static let GET_MORE_INFO: UInt8 = 0x24
    public static let SET_HISTORY_UPLOAD: UInt8 = 0x25
    public static let GET_TODAY_DELIVERY: UInt8 = 0x26
    
    // Bolus commands
    public static let GET_STEP_BOLUS_INFO: UInt8 = 0x40
    public static let GET_EXTENDED_BOLUS_STATE: UInt8 = 0x41
    public static let GET_EXTENDED_BOLUS: UInt8 = 0x42
    public static let GET_DUAL_BOLUS: UInt8 = 0x43
    public static let SET_STEP_BOLUS_STOP: UInt8 = 0x44
    public static let GET_CARB_CALC_INFO: UInt8 = 0x45
    public static let GET_EXTENDED_MENU_STATE: UInt8 = 0x46
    public static let SET_EXTENDED_BOLUS: UInt8 = 0x47
    public static let SET_DUAL_BOLUS: UInt8 = 0x48
    public static let SET_EXTENDED_BOLUS_CANCEL: UInt8 = 0x49
    public static let SET_STEP_BOLUS_START: UInt8 = 0x4A
    public static let GET_CALC_INFO: UInt8 = 0x4B
    public static let GET_BOLUS_RATE: UInt8 = 0x4C
    public static let SET_BOLUS_RATE: UInt8 = 0x4D
    public static let GET_CIR_CF_ARRAY: UInt8 = 0x4E
    public static let SET_CIR_CF_ARRAY: UInt8 = 0x4F
    public static let GET_BOLUS_OPTION: UInt8 = 0x50
    public static let SET_BOLUS_OPTION: UInt8 = 0x51
    public static let GET_24_CIR_CF_ARRAY: UInt8 = 0x52
    public static let SET_24_CIR_CF_ARRAY: UInt8 = 0x53
    
    // Basal commands
    public static let SET_TEMP_BASAL: UInt8 = 0x60
    public static let TEMP_BASAL_STATE: UInt8 = 0x61
    public static let CANCEL_TEMP_BASAL: UInt8 = 0x62
    public static let GET_PROFILE_NUMBER: UInt8 = 0x63
    public static let SET_PROFILE_NUMBER: UInt8 = 0x64
    public static let GET_PROFILE_BASAL_RATE: UInt8 = 0x65
    public static let SET_PROFILE_BASAL_RATE: UInt8 = 0x66
    public static let GET_BASAL_RATE: UInt8 = 0x67
    public static let SET_BASAL_RATE: UInt8 = 0x68
    public static let SET_SUSPEND_ON: UInt8 = 0x69
    public static let SET_SUSPEND_OFF: UInt8 = 0x6A
    
    // Option commands
    public static let GET_PUMP_TIME: UInt8 = 0x70
    public static let SET_PUMP_TIME: UInt8 = 0x71
    public static let GET_USER_OPTION: UInt8 = 0x72
    public static let SET_USER_OPTION: UInt8 = 0x73
    public static let GET_EASY_MENU_OPTION: UInt8 = 0x74
    public static let SET_EASY_MENU_OPTION: UInt8 = 0x75
    public static let GET_EASY_MENU_STATUS: UInt8 = 0x76
    public static let SET_EASY_MENU_STATUS: UInt8 = 0x77
    public static let GET_PUMP_UTC_TIMEZONE: UInt8 = 0x78
    public static let SET_PUMP_UTC_TIMEZONE: UInt8 = 0x79
    public static let GET_PUMP_TIMEZONE: UInt8 = 0x7A
    public static let SET_PUMP_TIMEZONE: UInt8 = 0x7B
    
    // APS commands (for looping)
    public static let APS_SET_TEMP_BASAL: UInt8 = 0xC1
    public static let APS_HISTORY_EVENTS: UInt8 = 0xC2
    public static let APS_SET_EVENT_HISTORY: UInt8 = 0xC3
    
    // General commands
    public static let GET_PUMP_DEC_RATIO: UInt8 = 0x80
    public static let GET_SHIPPING_VERSION: UInt8 = 0x81
    
    // Misc commands
    public static let SET_HISTORY_SAVE: UInt8 = 0xE0
    public static let KEEP_CONNECTION: UInt8 = 0xFF
}

// MARK: - Dana Packet

/// Dana command packet with payload and encoding
public struct DanaPacket: Sendable {
    /// Packet type (encryption request, command, etc.)
    public let packetType: DanaPacketType
    
    /// Command opcode
    public let opcode: UInt8
    
    /// Optional payload data
    public let payload: Data
    
    /// Whether this is an encryption/pairing command
    public let isEncryptionCommand: Bool
    
    /// Device name for serial number encoding
    public let deviceName: String
    
    // MARK: - Initialization
    
    /// Create a command with specified parameters
    public init(
        packetType: DanaPacketType,
        opcode: UInt8,
        payload: Data = Data(),
        isEncryptionCommand: Bool = false,
        deviceName: String = ""
    ) {
        self.packetType = packetType
        self.opcode = opcode
        self.payload = payload
        self.isEncryptionCommand = isEncryptionCommand
        self.deviceName = deviceName
    }
    
    // MARK: - Factory Methods (Encryption Commands)
    
    /// Create PUMP_CHECK command (initial handshake)
    public static func pumpCheck(deviceName: String) -> DanaPacket {
        // Device name goes in payload (10 bytes, null-padded)
        var nameData = Data(count: 10)
        let nameBytes = Array(deviceName.utf8.prefix(10))
        for (i, byte) in nameBytes.enumerated() {
            nameData[i] = byte
        }
        
        return DanaPacket(
            packetType: .encryptionRequest,
            opcode: DanaOpcode.PUMP_CHECK,
            payload: nameData,
            isEncryptionCommand: true,
            deviceName: deviceName
        )
    }
    
    /// Create TIME_INFORMATION command
    public static func timeInformation(
        data: Data? = nil,
        deviceName: String,
        encryptionType: DanaEncryptionType
    ) -> DanaPacket {
        var payload = data ?? Data()
        
        // BLE5 (Dana-i) requires special byte modification
        if encryptionType == .ble5, payload.count >= 4 {
            // Constants from Trio: timeInformationEnhancedEncryption2Lookup
            payload[1] = 0x17 ^ 0x1A  // 0x0D
            payload[2] = 0xD1 ^ 0xC0  // 0x11
            payload[3] = 0xAF ^ 0xA9  // 0x06
        }
        
        return DanaPacket(
            packetType: .encryptionRequest,
            opcode: DanaOpcode.TIME_INFORMATION,
            payload: payload,
            isEncryptionCommand: true,
            deviceName: deviceName
        )
    }
    
    /// Create CHECK_PASSKEY command
    public static func checkPasskey(
        passkey: Data,
        deviceName: String
    ) -> DanaPacket {
        // Encode passkey bytes with device name
        var encodedPasskey = Data(count: passkey.count)
        let nameSum = deviceName.utf8.prefix(10).reduce(UInt8(0)) { $0 &+ $1 }
        for (i, byte) in passkey.enumerated() {
            encodedPasskey[i] = byte ^ nameSum
        }
        
        return DanaPacket(
            packetType: .encryptionRequest,
            opcode: DanaOpcode.CHECK_PASSKEY,
            payload: encodedPasskey,
            isEncryptionCommand: true,
            deviceName: deviceName
        )
    }
    
    /// Create simple encryption request command (no payload)
    public static func encryptionRequest(
        opcode: UInt8,
        deviceName: String
    ) -> DanaPacket {
        DanaPacket(
            packetType: .encryptionRequest,
            opcode: opcode,
            payload: Data(),
            isEncryptionCommand: true,
            deviceName: deviceName
        )
    }
    
    // MARK: - Factory Methods (Normal Commands)
    
    /// Create a general command (non-encryption)
    public static func command(
        opcode: UInt8,
        payload: Data = Data(),
        deviceName: String
    ) -> DanaPacket {
        DanaPacket(
            packetType: .command,
            opcode: opcode,
            payload: payload,
            isEncryptionCommand: false,
            deviceName: deviceName
        )
    }
    
    /// Create GET_PUMP_TIME command
    public static func getPumpTime(deviceName: String) -> DanaPacket {
        command(opcode: DanaOpcode.GET_PUMP_TIME, deviceName: deviceName)
    }
    
    /// Create SET_TEMP_BASAL command
    public static func setTempBasal(
        percent: UInt8,
        durationHours: UInt8,
        deviceName: String
    ) -> DanaPacket {
        let payload = Data([percent, durationHours])
        return command(opcode: DanaOpcode.SET_TEMP_BASAL, payload: payload, deviceName: deviceName)
    }
    
    /// Create CANCEL_TEMP_BASAL command
    public static func cancelTempBasal(deviceName: String) -> DanaPacket {
        command(opcode: DanaOpcode.CANCEL_TEMP_BASAL, deviceName: deviceName)
    }
    
    /// Create GET_DELIVERY_STATUS command (reservoir, battery, etc.)
    public static func getDeliveryStatus(deviceName: String) -> DanaPacket {
        command(opcode: DanaOpcode.DELIVERY_STATUS, deviceName: deviceName)
    }
    
    /// Create KEEP_CONNECTION command (heartbeat)
    public static func keepConnection(deviceName: String) -> DanaPacket {
        command(opcode: DanaOpcode.KEEP_CONNECTION, deviceName: deviceName)
    }
    
    /// Create SET_STEP_BOLUS_START command
    public static func startBolus(
        amount: Double,
        speed: UInt8 = 12,  // Default speed
        deviceName: String
    ) -> DanaPacket {
        // Amount in 0.01U units (2 bytes, little-endian)
        let units = UInt16(amount * 100)
        let payload = Data([
            UInt8(units & 0xFF),
            UInt8((units >> 8) & 0xFF),
            speed
        ])
        return command(opcode: DanaOpcode.SET_STEP_BOLUS_START, payload: payload, deviceName: deviceName)
    }
    
    /// Create SET_STEP_BOLUS_STOP command
    public static func stopBolus(deviceName: String) -> DanaPacket {
        command(opcode: DanaOpcode.SET_STEP_BOLUS_STOP, deviceName: deviceName)
    }
    
    // MARK: - Packet Encoding
    
    /// Encode command into packet bytes
    /// - Parameters:
    ///   - encryption: Encryption engine (modified with randomSyncKey updates)
    /// - Returns: Encoded packet ready for BLE transmission
    public func encode(encryption: inout DanaEncryption) -> Data {
        // Calculate total packet size:
        // 2 (header) + 1 (length) + 1 (type) + 1 (opcode) + payload + 2 (CRC) + 2 (footer)
        let payloadLength = payload.count
        let totalLength = 9 + payloadLength
        
        var buffer = Data(count: totalLength)
        
        // Header
        buffer[0] = 0xA5
        buffer[1] = 0xA5
        
        // Length (type + opcode + payload)
        buffer[2] = UInt8(2 + payloadLength)
        
        // Packet type and opcode
        buffer[3] = packetType.rawValue
        buffer[4] = opcode
        
        // Payload
        if payloadLength > 0 {
            for i in 0..<payloadLength {
                buffer[5 + i] = payload[i]
            }
        }
        
        // Calculate CRC on type + opcode + payload
        let crcData = buffer.subdata(in: 3..<(5 + payloadLength))
        let crc = DanaCRC16.calculate(crcData, encryptionType: encryption.encryptionType, isEncryptionCommand: isEncryptionCommand)
        buffer[5 + payloadLength] = UInt8((crc >> 8) & 0xFF)
        buffer[6 + payloadLength] = UInt8(crc & 0xFF)
        
        // Footer
        buffer[7 + payloadLength] = 0x5A
        buffer[8 + payloadLength] = 0x5A
        
        // Apply serial number encoding
        applySerialNumberEncoding(&buffer)
        
        // Apply encryption if not legacy encryption command
        if isEncryptionCommand {
            // Encryption commands only get serial number encoding in legacy mode
            // For RSv3/BLE5, they don't get second-level encryption
            return buffer
        } else {
            // Normal commands get full encryption
            return encryption.encrypt(buffer, isEncryptionCommand: false)
        }
    }
    
    /// Apply device serial number XOR encoding
    private func applySerialNumberEncoding(_ buffer: inout Data) {
        guard !deviceName.isEmpty else { return }
        
        let nameBytes = Array(deviceName.utf8.prefix(10))
        guard nameBytes.count >= 10 else { return }
        
        // Create 3-byte XOR key from device name
        let key = Data([
            nameBytes[0] &+ nameBytes[1] &+ nameBytes[2],
            nameBytes[3] &+ nameBytes[4] &+ nameBytes[5] &+ nameBytes[6] &+ nameBytes[7],
            nameBytes[8] &+ nameBytes[9]
        ])
        
        // XOR bytes 3 to (length - 5) with rotating key
        for i in 0..<(buffer.count - 5) {
            buffer[i + 3] ^= key[i % 3]
        }
    }
}

// MARK: - Dana Response

/// Parsed Dana pump response
public struct DanaResponse: Sendable {
    /// Packet type from response
    public let packetType: UInt8
    
    /// Command opcode this is responding to
    public let opcode: UInt8
    
    /// Response payload data
    public let payload: Data
    
    /// Whether CRC was valid
    public let crcValid: Bool
    
    /// Whether this is an error response
    public var isError: Bool {
        // Check for common error indicators
        if payload.isEmpty { return false }
        // Byte 0 often indicates success (0) or error (non-zero)
        return payload[0] != 0
    }
    
    /// Success indicator (first byte is 0)
    public var isSuccess: Bool {
        if payload.isEmpty { return true }
        return payload[0] == 0
    }
    
    // MARK: - Parsing
    
    /// Parse response from decrypted packet data
    public static func parse(
        from data: Data,
        encryption: inout DanaEncryption,
        deviceName: String,
        isEncryptionResponse: Bool = false
    ) -> DanaResponse? {
        guard data.count >= 9 else { return nil }
        
        // Decrypt if needed
        var buffer = encryption.decrypt(data, isEncryptionCommand: isEncryptionResponse)
        
        // Remove serial number encoding
        removeSerialNumberEncoding(&buffer, deviceName: deviceName)
        
        // Verify header
        guard buffer[0] == 0xA5 && buffer[1] == 0xA5 else { return nil }
        
        // Get length
        let length = Int(buffer[2])
        guard buffer.count >= 7 + length else { return nil }
        
        // Verify footer
        let footerStart = 5 + length
        guard buffer[footerStart] == 0x5A && buffer[footerStart + 1] == 0x5A else { return nil }
        
        // Extract packet type and opcode
        let packetType = buffer[3]
        let opcode = buffer[4]
        
        // Extract payload
        let payloadLength = length - 2
        let payload: Data
        if payloadLength > 0 {
            payload = buffer.subdata(in: 5..<(5 + payloadLength))
        } else {
            payload = Data()
        }
        
        // Verify CRC
        let crcData = buffer.subdata(in: 3..<(5 + payloadLength))
        let receivedCRC = (UInt16(buffer[5 + payloadLength]) << 8) | UInt16(buffer[6 + payloadLength])
        let calculatedCRC = DanaCRC16.calculate(crcData, encryptionType: encryption.encryptionType, isEncryptionCommand: isEncryptionResponse)
        let crcValid = receivedCRC == calculatedCRC
        
        return DanaResponse(
            packetType: packetType,
            opcode: opcode,
            payload: payload,
            crcValid: crcValid
        )
    }
    
    /// Remove device serial number XOR encoding from buffer
    private static func removeSerialNumberEncoding(_ buffer: inout Data, deviceName: String) {
        guard !deviceName.isEmpty else { return }
        
        let nameBytes = Array(deviceName.utf8.prefix(10))
        guard nameBytes.count >= 10 else { return }
        
        // Create 3-byte XOR key from device name
        let key = Data([
            nameBytes[0] &+ nameBytes[1] &+ nameBytes[2],
            nameBytes[3] &+ nameBytes[4] &+ nameBytes[5] &+ nameBytes[6] &+ nameBytes[7],
            nameBytes[8] &+ nameBytes[9]
        ])
        
        // XOR bytes 3 to (length - 5) with rotating key (same operation undoes itself)
        for i in 0..<(buffer.count - 5) {
            buffer[i + 3] ^= key[i % 3]
        }
    }
}

// MARK: - Pump Check Response

/// Parsed PUMP_CHECK response with encryption type detection
public struct DanaPumpCheckResponse: Sendable {
    /// Detected encryption type from packet markers
    public let encryptionType: DanaEncryptionType
    
    /// Hardware model number
    public let hardwareModel: UInt8
    
    /// Protocol version
    public let protocolVersion: UInt8
    
    /// Product code
    public let productCode: UInt8
    
    /// Parse from raw BLE response data
    public static func parse(from data: Data) -> DanaPumpCheckResponse? {
        guard data.count >= 8 else { return nil }
        
        // Detect encryption type from markers
        guard let encType = DanaEncryption.detectEncryptionType(from: data) else {
            return nil
        }
        
        // Payload starts at offset 5 (after header, length, type, opcode)
        let hwModel = data.count > 5 ? data[5] : 0
        let protoVer = data.count > 6 ? data[6] : 0
        let prodCode = data.count > 7 ? data[7] : 0
        
        return DanaPumpCheckResponse(
            encryptionType: encType,
            hardwareModel: hwModel,
            protocolVersion: protoVer,
            productCode: prodCode
        )
    }
}
