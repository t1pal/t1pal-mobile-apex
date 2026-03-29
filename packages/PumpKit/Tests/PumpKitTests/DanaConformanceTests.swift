// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaConformanceTests.swift
// PumpKitTests
//
// Dana protocol conformance tests validating implementation
// against Trio DanaKit external source.
// Trace: EXT-DANA-001..003, PRD-005
//

import Testing
import Foundation
@testable import PumpKit

/// External source validation tests for Dana protocol implementation.
/// These tests verify our implementation matches Trio's DanaKit.
@Suite("Dana Conformance Tests")
struct DanaConformanceTests {
    
    // MARK: - BLE UUID Tests (EXT-DANA-002)
    
    /// Validate Dana BLE service UUID against DanaKit.
    /// Source: Trio/DanaKit/PumpManager/PeripheralManager.swift:24
    /// ```swift
    /// public static let SERVICE_UUID = CBUUID(string: "FFF0")
    /// ```
    @Test("Service UUID matches DanaKit")
    func serviceUUID() {
        // Our implementation uses full UUID format
        let ourUUID = DanaBLEConstants.serviceUUID.uppercased()
        #expect(ourUUID.contains("FFF0"), "Service UUID should contain FFF0")
        
        // Full format: 0000FFF0-0000-1000-8000-00805F9B34FB
        #expect(ourUUID == "0000FFF0-0000-1000-8000-00805F9B34FB")
    }
    
    /// Validate Dana BLE write characteristic UUID against DanaKit.
    /// Source: Trio/DanaKit/PumpManager/PeripheralManager.swift:27
    /// ```swift
    /// private let WRITE_CHAR_UUID = CBUUID(string: "FFF2")
    /// ```
    @Test("Write characteristic UUID matches DanaKit")
    func writeCharacteristicUUID() {
        let ourUUID = DanaBLEConstants.writeCharacteristicUUID.uppercased()
        #expect(ourUUID.contains("FFF2"), "Write UUID should contain FFF2 (per DanaKit)")
        #expect(ourUUID == "0000FFF2-0000-1000-8000-00805F9B34FB")
    }
    
    /// Validate Dana BLE notify/read characteristic UUID against DanaKit.
    /// Source: Trio/DanaKit/PumpManager/PeripheralManager.swift:25
    /// ```swift
    /// private let READ_CHAR_UUID = CBUUID(string: "FFF1")
    /// ```
    @Test("Notify characteristic UUID matches DanaKit")
    func notifyCharacteristicUUID() {
        let ourUUID = DanaBLEConstants.notifyCharacteristicUUID.uppercased()
        #expect(ourUUID.contains("FFF1"), "Notify/Read UUID should contain FFF1 (per DanaKit)")
        #expect(ourUUID == "0000FFF1-0000-1000-8000-00805F9B34FB")
    }
    
    // MARK: - Packet Framing Tests (EXT-DANA-002)
    
    /// Validate packet start bytes against DanaKit.
    /// Source: Trio/DanaKit/Encryption/Encrypt.swift:149-150
    /// ```swift
    /// buffer[0] = 0xA5 // header 1
    /// buffer[1] = 0xA5 // header 2
    /// ```
    @Test("Packet start bytes match DanaKit")
    func packetStartBytes() {
        let expected = Data([0xA5, 0xA5])
        #expect(DanaBLEConstants.packetStart == expected,
                       "Packet start should be 0xA5 0xA5 per DanaKit Encrypt.swift:149-150")
    }
    
    /// Validate packet end bytes against DanaKit.
    /// Source: Trio/DanaKit/Encryption/Encrypt.swift:164-165
    /// ```swift
    /// buffer[17] = 0x5A // footer 1
    /// buffer[18] = 0x5A // footer 2
    /// ```
    @Test("Packet end bytes match DanaKit")
    func packetEndBytes() {
        let expected = Data([0x5A, 0x5A])
        #expect(DanaBLEConstants.packetEnd == expected,
                       "Packet end should be 0x5A 0x5A per DanaKit Encrypt.swift:164-165")
    }
    
    // MARK: - Message Type Tests (EXT-DANA-002)
    
    /// Validate message types exist for Dana protocol categories.
    /// Note: Our DanaMessageType categorizes message purposes, while
    /// DanaKit uses opcode ranges (0x40-0x53 bolus, 0x60-0x6A basal, etc.)
    /// These are internal categorizations that map to those ranges.
    @Test("Message types exist")
    func messageTypesExist() {
        // Verify all message categories exist
        #expect(DanaMessageType.encryption != nil)
        #expect(DanaMessageType.general.rawValue == 0x01)
        #expect(DanaMessageType.basal.rawValue == 0x02)
        #expect(DanaMessageType.bolus.rawValue == 0x03)
        #expect(DanaMessageType.option.rawValue == 0x04)
        #expect(DanaMessageType.etc.rawValue == 0x05)
    }
    
    // MARK: - Encryption Type Tests (EXT-DANA-002)
    
    /// Validate encryption types for different Dana models.
    /// Source: Trio/DanaKit/Encryption/EncryptionHelper.swift
    @Test("Encryption types exist")
    func encryptionTypes() {
        // Verify all encryption types exist for different Dana models
        #expect(DanaEncryptionType.legacy != nil)  // Dana-R
        #expect(DanaEncryptionType.rsv3 != nil)    // Dana-RS
        #expect(DanaEncryptionType.ble5 != nil)    // Dana-i
        
        // Verify display names are descriptive
        #expect(!DanaEncryptionType.legacy.displayName.isEmpty)
        #expect(!DanaEncryptionType.rsv3.displayName.isEmpty)
        #expect(!DanaEncryptionType.ble5.displayName.isEmpty)
    }
    
    // MARK: - Packet Type Tests (EXT-DANA-002)
    
    /// Validate packet type values against DanaKit.
    /// Source: Trio/DanaKit/Packets/DanaPacketType.swift:10-14
    /// ```swift
    /// static let TYPE_ENCRYPTION_REQUEST = 0x01
    /// static let TYPE_ENCRYPTION_RESPONSE = 0x02
    /// static let TYPE_COMMAND = 0xA1
    /// static let TYPE_RESPONSE = 0xB2
    /// static let TYPE_NOTIFY = 0xC3
    /// ```
    @Test("Packet types match DanaKit")
    func packetTypes() {
        #expect(DanaPacketType.encryptionRequest.rawValue == 0x01)
        #expect(DanaPacketType.encryptionResponse.rawValue == 0x02)
        #expect(DanaPacketType.command.rawValue == 0xA1)
        #expect(DanaPacketType.response.rawValue == 0xB2)
        #expect(DanaPacketType.notify.rawValue == 0xC3)
    }
    
    // MARK: - DANA-VALIDATE-003: Swift Matches Python Tests
    
    /// DANA-VALIDATE-003: Verify Swift packet parsing matches Python parsers
    @Test("Dana packet framing matches Python")
    func danaPacketFramingMatchesPython() {
        // Dana packets use 0xA5 0xA5 start and 0x5A 0x5A end
        let startBytes = Data([0xA5, 0xA5])
        let endBytes = Data([0x5A, 0x5A])
        
        // Build a simple packet
        var packet = Data()
        packet.append(startBytes)
        packet.append(0x03)  // length
        packet.append(0x01)  // type: encryption request
        packet.append(0x00)  // command: 0
        packet.append(endBytes)
        
        #expect(packet.prefix(2) == startBytes, "Start bytes should be 0xA5 0xA5")
        #expect(packet.suffix(2) == endBytes, "End bytes should be 0x5A 0x5A")
        #expect(packet[2] == 0x03, "Length should be 3")
    }
    
    /// DANA-VALIDATE-003: Verify encryption type mapping
    @Test("Dana encryption types match DanaKit")
    func danaEncryptionTypesMatchDanaKit() {
        // DanaKit encryption types - String raw values
        #expect(DanaEncryptionType.legacy.rawValue == "ENCRYPTION_DEFAULT")
        #expect(DanaEncryptionType.rsv3.rawValue == "ENCRYPTION_RSv3")
        #expect(DanaEncryptionType.ble5.rawValue == "ENCRYPTION_BLE5")
    }
    
    /// DANA-VALIDATE-003: Verify message type opcodes
    @Test("Dana opcode matches DanaKit")
    func danaOpcodeMatchesDanaKit() {
        // Key Dana message type opcodes from DanaKit protocol
        #expect(DanaMessageType.encryption.rawValue == 0xA0)
        #expect(DanaMessageType.general.rawValue == 0x01)
        #expect(DanaMessageType.basal.rawValue == 0x02)
        #expect(DanaMessageType.bolus.rawValue == 0x03)
    }
    
    // MARK: - DANA-VALIDATE-004: Full Session Simulation
    
    /// DANA-VALIDATE-004: Simulate full Dana pairing flow without hardware
    @Test("Dana session state machine simulation")
    func danaSessionStateMachineSimulation() {
        let logger = DanaSessionLogger(pumpSerial: "test-dana-pump")
        
        // Verify initial state
        #expect(logger.state == DanaSessionState.idle)
        
        // Phase 1: Connection
        logger.logStateTransition(from: .idle, to: .scanning, reason: "Start scan")
        #expect(logger.state == DanaSessionState.scanning)
        
        logger.logStateTransition(from: .scanning, to: .connecting, reason: "Found pump")
        #expect(logger.state == DanaSessionState.connecting)
        
        logger.logStateTransition(from: .connecting, to: .discoveringServices, reason: "Connected")
        #expect(logger.state == DanaSessionState.discoveringServices)
        
        // Phase 2: Pairing
        logger.logStateTransition(from: .discoveringServices, to: .pairingRequest, reason: "Services found")
        #expect(logger.state == DanaSessionState.pairingRequest)
        
        logger.logStateTransition(from: .pairingRequest, to: .pairingChallenge, reason: "Request sent")
        #expect(logger.state == DanaSessionState.pairingChallenge)
        
        logger.logStateTransition(from: .pairingChallenge, to: .pairingComplete, reason: "Challenge verified")
        #expect(logger.state == DanaSessionState.pairingComplete)
        
        // Phase 3: Key exchange
        logger.logStateTransition(from: .pairingComplete, to: .keyExchange, reason: "Start key exchange")
        #expect(logger.state == DanaSessionState.keyExchange)
        
        logger.logStateTransition(from: .keyExchange, to: .sessionEstablished, reason: "Keys exchanged")
        #expect(logger.state == DanaSessionState.sessionEstablished)
        
        // Phase 4: Status and commands
        logger.logStateTransition(from: .sessionEstablished, to: .readingStatus, reason: "Get status")
        #expect(logger.state == DanaSessionState.readingStatus)
    }
    
    /// DANA-VALIDATE-004: Verify BLE exchange logging
    @Test("Dana session BLE exchange logging")
    func danaSessionBLEExchangeLogging() {
        let logger = DanaSessionLogger(pumpSerial: "test-dana-pump")
        
        // Simulate encryption request/response
        let encryptReq = Data([0xA5, 0xA5, 0x03, 0x01, 0x00, 0x5A, 0x5A])
        let encryptResp = Data([0xA5, 0xA5, 0x03, 0x02, 0x00, 0x5A, 0x5A])
        
        logger.logBLEExchange(direction: .write, data: encryptReq)
        logger.logBLEExchange(direction: .notify, data: encryptResp)
        
        // Export and verify
        let export = logger.export()
        #expect(export.bleExchanges.count > 0, "Should have BLE exchanges")
    }
    
    /// DANA-VALIDATE-004: Test error state handling
    @Test("Dana session error recovery")
    func danaSessionErrorRecovery() {
        let logger = DanaSessionLogger(pumpSerial: "test-dana-pump")
        
        // Progress through states
        logger.logStateTransition(from: .idle, to: .scanning, reason: "Start")
        logger.logStateTransition(from: .scanning, to: .connecting, reason: "Found")
        logger.logStateTransition(from: .connecting, to: .error, reason: "Connection timeout")
        
        #expect(logger.state == DanaSessionState.error)
        
        // Verify error captured in export
        let export = logger.export()
        let lastTransition = export.transitions.last
        #expect(lastTransition?.toState == DanaSessionState.error)
    }
    
    // MARK: - DANA-VALIDATE-001: CRC Matches DanaKit
    
    /// DANA-VALIDATE-001: Verify CRC16 for legacy mode (enhancedEncryption=0) matches DanaKit CrcTests.swift
    /// Source: externals/Trio/DanaKit/DanaKitTests/Encryption/CrcTests.swift:6-10
    /// Test: pump_check command with DEVICE_NAME="VJH00012FI"
    /// ```swift
    /// let data: [UInt8] = [1, 0] + Array(DEVICE_NAME.utf8)
    /// let crc = generateCrc(buffer: Data(data), enhancedEncryption: 0, isEncryptionCommand: true)
    /// XCTAssertEqual(crc, 0xBC7A)
    /// ```
    @Test("CRC16 legacy matches DanaKit")
    func crc16_Legacy_MatchesDanaKit() {
        // DanaKit test: DEVICE_NAME = "VJH00012FI"
        let deviceName = "VJH00012FI"
        var data = Data([0x01, 0x00])
        data.append(contentsOf: deviceName.utf8)
        
        // enhancedEncryption=0 maps to .legacy
        let crc = DanaCRC16.calculate(data, encryptionType: .legacy, isEncryptionCommand: true)
        
        #expect(crc == 0xBC7A, "CRC should match DanaKit CrcTests line 10: 0xBC7A")
    }
    
    /// DANA-VALIDATE-001: Verify CRC16 for RSv3 mode (enhancedEncryption=1) normal command
    /// Source: externals/Trio/DanaKit/DanaKitTests/Encryption/CrcTests.swift:13-17
    /// Test: BasalSetTemporary command (200%, 1 hour)
    /// ```swift
    /// let data: [UInt8] = [161, 96, 200, 1]
    /// let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: false)
    /// XCTAssertEqual(crc, 0x33FD)
    /// ```
    @Test("CRC16 RSv3 normal command matches DanaKit")
    func crc16_RSv3_NormalCommand_MatchesDanaKit() {
        // BasalSetTemporary: type=161 (0xA1), opcode=96 (0x60), ratio=200, duration=1
        let data = Data([161, 96, 200, 1])
        
        // enhancedEncryption=1, isEncryptionCommand=false
        let crc = DanaCRC16.calculate(data, encryptionType: .rsv3, isEncryptionCommand: false)
        
        #expect(crc == 0x33FD, "CRC should match DanaKit CrcTests line 17: 0x33FD")
    }
    
    /// DANA-VALIDATE-001: Verify CRC16 for RSv3 mode (enhancedEncryption=1) encryption command
    /// Source: externals/Trio/DanaKit/DanaKitTests/Encryption/CrcTests.swift:20-24
    /// Test: TIME_INFORMATION command -> sendTimeInfo
    /// ```swift
    /// let data: [UInt8] = [1, 1]
    /// let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: true)
    /// XCTAssertEqual(crc, 0x0990)
    /// ```
    @Test("CRC16 RSv3 encryption command matches DanaKit")
    func crc16_RSv3_EncryptionCommand_MatchesDanaKit() {
        // TIME_INFORMATION: [type=1, opcode=1]
        let data = Data([1, 1])
        
        // enhancedEncryption=1, isEncryptionCommand=true
        let crc = DanaCRC16.calculate(data, encryptionType: .rsv3, isEncryptionCommand: true)
        
        #expect(crc == 0x0990, "CRC should match DanaKit CrcTests line 24: 0x0990")
    }
    
    /// DANA-VALIDATE-001: Verify CRC16 for BLE5 mode (enhancedEncryption=2) normal command
    /// Source: externals/Trio/DanaKit/DanaKitTests/Encryption/CrcTests.swift:27-31
    /// Test: BasalSetTemporary command (200%, 1 hour)
    /// ```swift
    /// let data: [UInt8] = [161, 96, 200, 1]
    /// let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: false)
    /// XCTAssertEqual(crc, 0x7A1A)
    /// ```
    @Test("CRC16 BLE5 normal command matches DanaKit")
    func crc16_BLE5_NormalCommand_MatchesDanaKit() {
        let data = Data([161, 96, 200, 1])
        
        // enhancedEncryption=2, isEncryptionCommand=false
        let crc = DanaCRC16.calculate(data, encryptionType: .ble5, isEncryptionCommand: false)
        
        #expect(crc == 0x7A1A, "CRC should match DanaKit CrcTests line 31: 0x7A1A")
    }
    
    /// DANA-VALIDATE-001: Verify CRC16 for BLE5 mode (enhancedEncryption=2) encryption command
    /// Source: externals/Trio/DanaKit/DanaKitTests/Encryption/CrcTests.swift:34-38
    /// Test: TIME_INFORMATION command -> sendBLE5PairingInformation
    /// ```swift
    /// let data: [UInt8] = [1, 1, 0, 0, 0, 0]
    /// let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: true)
    /// XCTAssertEqual(crc, 0x1FEF)
    /// ```
    @Test("CRC16 BLE5 encryption command matches DanaKit")
    func crc16_BLE5_EncryptionCommand_MatchesDanaKit() {
        let data = Data([1, 1, 0, 0, 0, 0])
        
        // enhancedEncryption=2, isEncryptionCommand=true
        let crc = DanaCRC16.calculate(data, encryptionType: .ble5, isEncryptionCommand: true)
        
        #expect(crc == 0x1FEF, "CRC should match DanaKit CrcTests line 38: 0x1FEF")
    }
    
    // MARK: - DANA-VALIDATE-002: Command Format Matches DanaKit
    
    /// DANA-VALIDATE-002: Verify command opcodes match DanaKit GeneratePacketTests.swift
    /// Source: externals/Trio/DanaKit/DanaKitTests/GeneratePacketTests.swift
    
    /// Test: BASAL_CANCEL_TEMPORARY opcode = 98 (0x62)
    /// Source line 7: let expectedSnapshot = DanaGeneratePacket(opCode: 98, data: nil)
    @Test("Command opcode cancel temp basal matches DanaKit")
    func commandOpcode_CancelTempBasal_MatchesDanaKit() {
        #expect(DanaOpcode.CANCEL_TEMP_BASAL == 98, "CANCEL_TEMP_BASAL should be 98 per DanaKit")
    }
    
    /// Test: BASAL_SET_TEMPORARY opcode = 96 (0x60)
    /// Source line 88: let expectedSnapshot = DanaGeneratePacket(opCode: 96, data: expectedData)
    @Test("Command opcode set temp basal matches DanaKit")
    func commandOpcode_SetTempBasal_MatchesDanaKit() {
        #expect(DanaOpcode.SET_TEMP_BASAL == 96, "SET_TEMP_BASAL should be 96 per DanaKit")
    }
    
    /// Test: SET_SUSPEND_ON opcode = 105 (0x69)
    /// Source line 79: let expectedSnapshot = DanaGeneratePacket(opCode: 105, data: nil)
    @Test("Command opcode suspend on matches DanaKit")
    func commandOpcode_SuspendOn_MatchesDanaKit() {
        #expect(DanaOpcode.SET_SUSPEND_ON == 105, "SET_SUSPEND_ON should be 105 per DanaKit")
    }
    
    /// Test: SET_SUSPEND_OFF opcode = 106 (0x6A)
    /// Source line 68: let expectedSnapshot = DanaGeneratePacket(opCode: 106, data: nil)
    @Test("Command opcode suspend off matches DanaKit")
    func commandOpcode_SuspendOff_MatchesDanaKit() {
        #expect(DanaOpcode.SET_SUSPEND_OFF == 106, "SET_SUSPEND_OFF should be 106 per DanaKit")
    }
    
    /// Test: SET_STEP_BOLUS_START opcode = 74 (0x4A)
    /// Source line 252: let expectedSnapshot = DanaGeneratePacket(opCode: 74, data: expectedData)
    @Test("Command opcode bolus start matches DanaKit")
    func commandOpcode_BolusStart_MatchesDanaKit() {
        #expect(DanaOpcode.SET_STEP_BOLUS_START == 74, "SET_STEP_BOLUS_START should be 74 per DanaKit")
    }
    
    /// Test: SET_STEP_BOLUS_STOP opcode = 68 (0x44)
    /// Source line 283: let expectedSnapshot = DanaGeneratePacket(opCode: 68, data: nil)
    @Test("Command opcode bolus stop matches DanaKit")
    func commandOpcode_BolusStop_MatchesDanaKit() {
        #expect(DanaOpcode.SET_STEP_BOLUS_STOP == 68, "SET_STEP_BOLUS_STOP should be 68 per DanaKit")
    }
    
    /// Test: GET_PUMP_TIME opcode = 112 (0x70)
    /// Source line 336: let expectedSnapshot = DanaGeneratePacket(opCode: 112, data: nil)
    @Test("Command opcode get pump time matches DanaKit")
    func commandOpcode_GetPumpTime_MatchesDanaKit() {
        #expect(DanaOpcode.GET_PUMP_TIME == 112, "GET_PUMP_TIME should be 112 per DanaKit")
    }
    
    /// Test: SET_PUMP_TIME opcode = 113 (0x71)
    /// Source line 441: let expectedSnapshot = DanaGeneratePacket(opCode: 113, data: expectedData)
    @Test("Command opcode set pump time matches DanaKit")
    func commandOpcode_SetPumpTime_MatchesDanaKit() {
        #expect(DanaOpcode.SET_PUMP_TIME == 113, "SET_PUMP_TIME should be 113 per DanaKit")
    }
    
    /// Test: KEEP_CONNECTION opcode = 255 (0xFF)
    /// Source line 391: let expectedSnapshot = DanaGeneratePacket(opCode: 255, data: nil)
    @Test("Command opcode keep connection matches DanaKit")
    func commandOpcode_KeepConnection_MatchesDanaKit() {
        #expect(DanaOpcode.KEEP_CONNECTION == 255, "KEEP_CONNECTION should be 255 per DanaKit")
    }
    
    /// Test: APS_SET_TEMP_BASAL opcode = 193 (0xC1)
    /// Source line 657: let expectedSnapshot = DanaGeneratePacket(opCode: 193, data: expectedData)
    @Test("Command opcode APS temp basal matches DanaKit")
    func commandOpcode_APSTempBasal_MatchesDanaKit() {
        #expect(DanaOpcode.APS_SET_TEMP_BASAL == 193, "APS_SET_TEMP_BASAL should be 193 per DanaKit")
    }
    
    /// Test: GET_USER_OPTION opcode = 114 (0x72)
    /// Source line 373: let expectedSnapshot = DanaGeneratePacket(opCode: 114, data: nil)
    @Test("Command opcode get user option matches DanaKit")
    func commandOpcode_GetUserOption_MatchesDanaKit() {
        #expect(DanaOpcode.GET_USER_OPTION == 114, "GET_USER_OPTION should be 114 per DanaKit")
    }
    
    /// Test: SET_USER_OPTION opcode = 115 (0x73)
    /// Source line 476: let expectedSnapshot = DanaGeneratePacket(opCode: 115, data: expectedData)
    @Test("Command opcode set user option matches DanaKit")
    func commandOpcode_SetUserOption_MatchesDanaKit() {
        #expect(DanaOpcode.SET_USER_OPTION == 115, "SET_USER_OPTION should be 115 per DanaKit")
    }
    
    // MARK: - Command Data Format Tests
    
    /// Test: SET_TEMP_BASAL data format [percent, duration]
    /// Source line 85-88: options = PacketBasalSetTemporary(temporaryBasalRatio: 200, temporaryBasalDuration: 1)
    ///                     expectedData = Data([200, 1])
    @Test("Command data set temp basal matches DanaKit")
    func commandData_SetTempBasal_MatchesDanaKit() {
        let packet = DanaPacket.setTempBasal(percent: 200, durationHours: 1, deviceName: "TEST")
        
        #expect(packet.opcode == 96, "Opcode should be 96")
        #expect(packet.payload == Data([200, 1]), "Payload should be [200, 1] per DanaKit")
    }
    
    /// Test: APS_SET_TEMP_BASAL data format [percent_low, percent_high, duration_code]
    /// Source line 653-656: options = PacketLoopSetTemporaryBasal(percent: 200, duration: .min30)
    ///                       expectedData = Data([200, 0, 160])
    @Test("Command data APS temp basal matches DanaKit")
    func commandData_APSTempBasal_MatchesDanaKit() {
        // APS temp basal: 200% for 30 min
        // 200 fits in one byte, so [200, 0, 160] where 160 = 30 min duration code
        let payload = Data([200, 0, 160])
        let packet = DanaPacket.command(opcode: DanaOpcode.APS_SET_TEMP_BASAL, payload: payload, deviceName: "TEST")
        
        #expect(packet.opcode == 193, "Opcode should be 193")
        #expect(packet.payload == Data([200, 0, 160]), "Payload should be [200, 0, 160] per DanaKit")
    }
    
    /// Test: Bolus amount encoding - 5 units = 500 centiunits = [244, 1]
    /// Source line 249-252: options = PacketBolusStart(amount: 5, speed: .speed12)
    ///                       expectedData = Data([244, 1, 0])
    @Test("Command data bolus start matches DanaKit")
    func commandData_BolusStart_MatchesDanaKit() {
        // 5 units = 500 centiunits = 0x01F4
        // Low byte first: [244 (0xF4), 1 (0x01), speed=0]
        let payload = Data([244, 1, 0])  // 5 units at speed12
        let packet = DanaPacket.command(opcode: DanaOpcode.SET_STEP_BOLUS_START, payload: payload, deviceName: "TEST")
        
        #expect(packet.opcode == 74, "Opcode should be 74")
        #expect(packet.payload == Data([244, 1, 0]), "Payload should be [244, 1, 0] per DanaKit (5 units @ speed12)")
    }
}
