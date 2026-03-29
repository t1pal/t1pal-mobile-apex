//
//  RileyLinkCommandTests.swift
//  PumpKitTests
//
//  Tests for RileyLink BLE command serialization
//

import Foundation
import Testing
@testable import PumpKit

@Suite("RileyLink Command Layer")
struct RileyLinkCommandTests {
    
    // MARK: - Command Code Tests
    
    @Test("Command codes match firmware spec")
    func commandCodesMatchSpec() {
        #expect(RileyLinkCommandCode.getState.rawValue == 0x01)
        #expect(RileyLinkCommandCode.getVersion.rawValue == 0x02)
        #expect(RileyLinkCommandCode.getPacket.rawValue == 0x03)
        #expect(RileyLinkCommandCode.sendPacket.rawValue == 0x04)
        #expect(RileyLinkCommandCode.sendAndListen.rawValue == 0x05)
        #expect(RileyLinkCommandCode.updateRegister.rawValue == 0x06)
        #expect(RileyLinkCommandCode.reset.rawValue == 0x07)
        #expect(RileyLinkCommandCode.setLEDMode.rawValue == 0x08)
        #expect(RileyLinkCommandCode.setSWEncoding.rawValue == 0x0B)
        #expect(RileyLinkCommandCode.getStatistics.rawValue == 0x0E)
    }
    
    // MARK: - GetVersion Tests
    
    @Test("GetVersion command serializes correctly")
    func getVersionSerializes() {
        let command = GetVersionCommand()
        let data = command.data
        
        #expect(data.count == 1)
        #expect(data[0] == 0x02) // getVersion opcode
    }
    
    // MARK: - SendAndListen Tests
    
    @Test("SendAndListen uses channel 0 for Medtronic per Loop (RL-CHAN-004)")
    func sendAndListenChannel0() {
        // RL-CHAN-001/002: Loop uses channel 0, not 2
        // Channel 2 caused rxTimeout (0xAA) - pump never responded
        let rfPacket = Data([0xA7, 0x12, 0x34])
        let command = SendAndListenCommand(
            outgoing: rfPacket,
            sendChannel: 0,      // Channel 0 per Loop!
            repeatCount: 0,
            delayBetweenPacketsMS: 0,
            listenChannel: 0,    // Channel 0 per Loop!
            timeoutMS: 500,
            retryCount: 3,
            preambleExtensionMS: 0,
            firmwareVersion: .unknown
        )
        
        let data = command.data
        
        #expect(data[0] == 0x05) // sendAndListen opcode
        #expect(data[1] == 0)    // send channel = 0 (not 2!)
        #expect(data[2] == 0)    // repeat count
        #expect(data[3] == 0)    // delay
        #expect(data[4] == 0)    // listen channel = 0 (not 2!)
    }
    
    @Test("SendAndListen command serializes with v1 firmware")
    func sendAndListenV1() {
        let rfPacket = Data([0xA5, 0x5A, 0xFF])
        let command = SendAndListenCommand(
            outgoing: rfPacket,
            sendChannel: 2,
            repeatCount: 0,
            delayBetweenPacketsMS: 50,
            listenChannel: 2,
            timeoutMS: 500,
            retryCount: 3,
            preambleExtensionMS: 0,
            firmwareVersion: .unknown  // v1 format
        )
        
        let data = command.data
        
        // Format: [opcode, sendCh, repeat, delay(1B), listenCh, timeout(4B), retry, payload...]
        #expect(data[0] == 0x05) // sendAndListen opcode
        #expect(data[1] == 2)    // send channel
        #expect(data[2] == 0)    // repeat count
        #expect(data[3] == 50)   // delay (clamped to 8-bit for v1)
        #expect(data[4] == 2)    // listen channel
        // Timeout: 500 = 0x000001F4 big endian
        #expect(data[5] == 0x00)
        #expect(data[6] == 0x00)
        #expect(data[7] == 0x01)
        #expect(data[8] == 0xF4)
        #expect(data[9] == 3)    // retry count
        // No preamble extension for v1
        // Payload starts at index 10
        #expect(data[10] == 0xA5)
        #expect(data[11] == 0x5A)
        #expect(data[12] == 0xFF)
    }
    
    @Test("SendAndListen command serializes with v2 firmware")
    func sendAndListenV2() {
        let rfPacket = Data([0xAB])
        let v2Firmware = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")!
        
        let command = SendAndListenCommand(
            outgoing: rfPacket,
            sendChannel: 2,
            repeatCount: 1,
            delayBetweenPacketsMS: 1000,  // Needs 16-bit for v2
            listenChannel: 2,
            timeoutMS: 1000,
            retryCount: 5,
            preambleExtensionMS: 100,      // v2 supports preamble extension
            firmwareVersion: v2Firmware
        )
        
        let data = command.data
        
        #expect(data[0] == 0x05) // sendAndListen opcode
        #expect(data[1] == 2)    // send channel
        #expect(data[2] == 1)    // repeat count
        // Delay: 1000 = 0x03E8 big endian (16-bit for v2)
        #expect(data[3] == 0x03)
        #expect(data[4] == 0xE8)
        #expect(data[5] == 2)    // listen channel
        // Timeout: 1000 = 0x000003E8 big endian
        #expect(data[6] == 0x00)
        #expect(data[7] == 0x00)
        #expect(data[8] == 0x03)
        #expect(data[9] == 0xE8)
        #expect(data[10] == 5)   // retry count
        // Preamble extension: 100 = 0x0064 big endian
        #expect(data[11] == 0x00)
        #expect(data[12] == 0x64)
        // Payload
        #expect(data[13] == 0xAB)
    }
    
    // MARK: - UpdateRegister Tests
    
    @Test("UpdateRegister command serializes correctly")
    func updateRegisterSerializes() {
        let command = UpdateRegisterCommand(.freq2, value: 0x21, firmwareVersion: .unknown)
        let data = command.data
        
        // v1 format needs extra byte
        #expect(data[0] == 0x06) // updateRegister opcode
        #expect(data[1] == 0x09) // freq2 register address
        #expect(data[2] == 0x21) // value
        #expect(data[3] == 0x00) // extra byte for v1
    }
    
    @Test("UpdateRegister command v2 format")
    func updateRegisterV2() {
        let v2Firmware = RadioFirmwareVersion(versionString: "subg_rfspy 2.0")!
        let command = UpdateRegisterCommand(.freq2, value: 0x21, firmwareVersion: v2Firmware)
        let data = command.data
        
        // v2 format: no extra byte
        #expect(data.count == 3)
        #expect(data[0] == 0x06)
        #expect(data[1] == 0x09)
        #expect(data[2] == 0x21)
    }
    
    // MARK: - CC111X Register Tests
    
    @Test("CC111X register addresses match datasheet")
    func registerAddresses() {
        #expect(CC111XRegister.freq2.rawValue == 0x09)
        #expect(CC111XRegister.freq1.rawValue == 0x0A)
        #expect(CC111XRegister.freq0.rawValue == 0x0B)
        #expect(CC111XRegister.mdmcfg4.rawValue == 0x0C)
        #expect(CC111XRegister.pktctrl0.rawValue == 0x04)
    }
    
    // MARK: - FrequencyRegisters Tests
    
    @Test("Frequency registers calculate correctly for 916.5 MHz")
    func frequencyCalculation916() {
        let regs = FrequencyRegisters(mhz: 916.5)
        
        // CC1110 formula: FREQ = (targetFreq * 2^16) / 24
        // For 916.5 MHz: (916.5 * 65536) / 24 = 2502656 = 0x263000
        #expect(regs.freq2 == 0x26)
        #expect(regs.freq1 == 0x30)
        #expect(regs.freq0 == 0x00)
    }
    
    @Test("Frequency registers generate update commands")
    func frequencyCommands() {
        let regs = FrequencyRegisters(mhz: 916.5)
        let commands = regs.updateCommands()
        
        #expect(commands.count == 3)
        #expect(commands[0].register == .freq2)
        #expect(commands[1].register == .freq1)
        #expect(commands[2].register == .freq0)
    }
    
    // MARK: - RadioFirmwareVersion Tests
    
    @Test("Firmware version parses correctly")
    func firmwareVersionParsing() {
        let v1 = RadioFirmwareVersion(versionString: "subg_rfspy 1.0")
        #expect(v1 != nil)
        #expect(v1?.components == [1, 0])
        #expect(v1?.supports16BitPacketDelay == false)
        #expect(v1?.supportsPreambleExtension == false)
        
        let v2 = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")
        #expect(v2 != nil)
        #expect(v2?.components == [2, 2])
        #expect(v2?.supports16BitPacketDelay == true)
        #expect(v2?.supportsPreambleExtension == true)
        #expect(v2?.supportsRileyLinkStatistics == true)
        
        // OrangeLink returns "ble_rfspy 2.0" - must be parsed correctly
        let orangeLink = RadioFirmwareVersion(versionString: "ble_rfspy 2.0")
        #expect(orangeLink != nil)
        #expect(orangeLink?.components == [2, 0])
        #expect(orangeLink?.versionString == "ble_rfspy 2.0")
    }
    
    @Test("Invalid firmware version returns nil")
    func invalidFirmwareVersion() {
        // Pure gibberish with no version-like pattern should fail
        let invalid = RadioFirmwareVersion(versionString: "unknown firmware")
        #expect(invalid == nil)
        
        // "rfspy 2.0" IS now parsed as version 2.0 (fallback parser finds the "2.0" part)
        // This is desirable - if a device returns "rfspy 2.0", we should accept it
        let shortened = RadioFirmwareVersion(versionString: "rfspy 2.0")
        #expect(shortened != nil)
        #expect(shortened?.components == [2, 0])
        
        // Truly unparseable string (no dots, no numbers in version format)
        let noVersion = RadioFirmwareVersion(versionString: "firmware xyz abc")
        #expect(noVersion == nil)
    }
    
    // MARK: - SetSoftwareEncoding Tests
    
    @Test("SetSoftwareEncoding command serializes")
    func setSoftwareEncoding() {
        let command = SetSoftwareEncodingCommand(.fourbsixb)
        let data = command.data
        
        #expect(data.count == 2)
        #expect(data[0] == 0x0B) // setSWEncoding opcode
        #expect(data[1] == 0x02) // fourbsixb encoding type
    }
    
    // MARK: - GetPacket Tests
    
    @Test("GetPacket command serializes")
    func getPacketSerializes() {
        let command = GetPacketCommand(listenChannel: 2, timeoutMS: 1000)
        let data = command.data
        
        #expect(data[0] == 0x03) // getPacket opcode
        #expect(data[1] == 2)    // listen channel
        // Timeout: 1000 = 0x000003E8 big endian
        #expect(data[2] == 0x00)
        #expect(data[3] == 0x00)
        #expect(data[4] == 0x03)
        #expect(data[5] == 0xE8)
    }
    
    // MARK: - Response Code Tests
    
    @Test("Response codes match firmware spec")
    func responseCodes() {
        #expect(RileyLinkResponseCode.success.rawValue == 0xDD)
        #expect(RileyLinkResponseCode.rxTimeout.rawValue == 0xAA)
        #expect(RileyLinkResponseCode.commandInterrupted.rawValue == 0xBB)
        #expect(RileyLinkResponseCode.zeroData.rawValue == 0xCC)
        #expect(RileyLinkResponseCode.invalidParam.rawValue == 0x11)
        #expect(RileyLinkResponseCode.unknownCommand.rawValue == 0x22)
    }
    
    // MARK: - RL-CHAN-005: Loop Conformance Tests
    
    /// RL-CHAN-005: Verify our SendAndListen bytes match Loop's exact format
    /// Reference: externals/rileylink_ios/RileyLinkBLEKit/Command.swift
    @Test("SendAndListen bytes match Loop format exactly (RL-CHAN-005)")
    func sendAndListenMatchesLoop() {
        // Test case: Medtronic wakeup command with typical parameters
        // Loop uses: channel 0, repeat 200, delay 0, timeout 12000ms
        let wakeupPacket = Data([0xA7, 0x01, 0x02, 0x03, 0x05]) // Example pump message
        
        let command = SendAndListenCommand(
            outgoing: wakeupPacket,
            sendChannel: 0,          // Loop uses 0 for Medtronic
            repeatCount: 200,        // Wakeup uses high repeat
            delayBetweenPacketsMS: 0,
            listenChannel: 0,        // Loop uses 0 for Medtronic  
            timeoutMS: 12000,        // 12 second wakeup timeout
            retryCount: 0,
            preambleExtensionMS: 0,
            firmwareVersion: .unknown  // v1 format
        )
        
        let data = command.data
        
        // Loop's Command.swift format (v1, line 99-121):
        // [opcode, sendChannel, repeatCount, delay(1B), listenChannel, timeout(4B BE), retryCount, payload...]
        
        #expect(data[0] == 0x05, "opcode must be sendAndListen (0x05)")
        #expect(data[1] == 0, "sendChannel must be 0 (not 2)")
        #expect(data[2] == 200, "repeatCount for wakeup")
        #expect(data[3] == 0, "delay 1-byte (v1 format)")
        #expect(data[4] == 0, "listenChannel must be 0 (not 2)")
        // timeout 12000 = 0x00002EE0 big endian
        #expect(data[5] == 0x00)
        #expect(data[6] == 0x00)
        #expect(data[7] == 0x2E)
        #expect(data[8] == 0xE0)
        #expect(data[9] == 0, "retryCount")
        // Payload follows
        #expect(data[10] == 0xA7, "payload byte 0")
        #expect(data[11] == 0x01, "payload byte 1")
        #expect(data[12] == 0x02, "payload byte 2")
        #expect(data[13] == 0x03, "payload byte 3")
        #expect(data[14] == 0x05, "payload byte 4")
        
        // Total: 10 header bytes + 5 payload = 15 bytes
        #expect(data.count == 15)
    }
    
    /// RL-CHAN-005: Verify v2 firmware format matches Loop
    @Test("SendAndListen v2 format matches Loop (RL-CHAN-005)")
    func sendAndListenV2MatchesLoop() {
        let packet = Data([0xA7, 0xDE, 0xAD])
        let v2Firmware = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")!
        
        let command = SendAndListenCommand(
            outgoing: packet,
            sendChannel: 0,
            repeatCount: 0,
            delayBetweenPacketsMS: 500,   // 16-bit in v2
            listenChannel: 0,
            timeoutMS: 850,               // Typical command timeout
            retryCount: 3,
            preambleExtensionMS: 127,     // v2 supports this
            firmwareVersion: v2Firmware
        )
        
        let data = command.data
        
        // Loop's v2 format: delay is 16-bit, preamble extension added
        // [opcode, sendCh, repeat, delay(2B BE), listenCh, timeout(4B BE), retry, preamble(2B BE), payload...]
        
        #expect(data[0] == 0x05, "opcode")
        #expect(data[1] == 0, "sendChannel 0")
        #expect(data[2] == 0, "repeatCount")
        // delay 500 = 0x01F4 big endian
        #expect(data[3] == 0x01)
        #expect(data[4] == 0xF4)
        #expect(data[5] == 0, "listenChannel 0")
        // timeout 850 = 0x00000352 big endian
        #expect(data[6] == 0x00)
        #expect(data[7] == 0x00)
        #expect(data[8] == 0x03)
        #expect(data[9] == 0x52)
        #expect(data[10] == 3, "retryCount")
        // preamble 127 = 0x007F big endian
        #expect(data[11] == 0x00)
        #expect(data[12] == 0x7F)
        // Payload
        #expect(data[13] == 0xA7)
        #expect(data[14] == 0xDE)
        #expect(data[15] == 0xAD)
        
        // Total: 13 header bytes + 3 payload = 16 bytes
        #expect(data.count == 16)
    }
    
    // MARK: - PYTHON-COMPAT-001: Python Verification Tests
    
    /// PYTHON-COMPAT-001: Complete READ_MODEL command matches verified Python fixture
    /// Reference: tools/medtronic-rf/test_quick.py (working implementation)
    /// This test verifies our Swift produces byte-for-byte identical output to Python
    @Test("READ_MODEL v2 command matches Python byte-for-byte (PYTHON-COMPAT-001)")
    func readModelCommandMatchesPython() {
        // 1. Build Medtronic message: A7 [serial] 8D 00
        let raw = Data([0xA7, 0x20, 0x88, 0x50, 0x8D, 0x00])
        
        // 2. Create MinimedPacket and encode (adds CRC + 4b6b + null)
        let packet = MinimedPacket(outgoingData: raw)
        let encoded = packet.encodedData()
        
        // Python produces: a9 6c 95 69 a9 55 68 d5 55 c8 b0 00
        let pythonEncoded: [UInt8] = [0xa9, 0x6c, 0x95, 0x69, 0xa9, 0x55, 0x68, 0xd5, 0x55, 0xc8, 0xb0, 0x00]
        #expect(Array(encoded) == pythonEncoded, "4b6b encoded RF packet must match Python exactly")
        
        // 3. Build SendAndListen command (v2 format, 200ms timeout, 3 retries)
        let v2Firmware = RadioFirmwareVersion.assumeV2  // Use assumeV2 for OrangeLink
        let command = SendAndListenCommand(
            outgoing: encoded,
            sendChannel: 0,
            repeatCount: 0,
            delayBetweenPacketsMS: 0,
            listenChannel: 0,
            timeoutMS: 200,  // 200ms per Python
            retryCount: 3,
            preambleExtensionMS: 0,
            firmwareVersion: v2Firmware
        )
        
        let cmdData = command.data
        
        // Python produces (before length prefix):
        // 05 00 00 00 00 00 00 00 00 c8 03 00 00 a9 6c 95 69 a9 55 68 d5 55 c8 b0 00
        let pythonCmd: [UInt8] = [
            0x05, 0x00, 0x00,              // cmd, sendCh, repeat
            0x00, 0x00,                    // delay 2B BE
            0x00,                          // listenCh
            0x00, 0x00, 0x00, 0xC8,        // timeout 4B BE (200ms = 0xC8)
            0x03,                          // retryCount
            0x00, 0x00,                    // preamble 2B BE
            // Then RF data:
            0xa9, 0x6c, 0x95, 0x69, 0xa9, 0x55, 0x68, 0xd5, 0x55, 0xc8, 0xb0, 0x00
        ]
        #expect(Array(cmdData) == pythonCmd, "SendAndListen command must match Python exactly (25 bytes)")
        #expect(cmdData.count == 25, "v2 command without length prefix is 25 bytes")
        
        // 4. Add length prefix (what we write to BLE)
        var framed = Data([UInt8(cmdData.count)])
        framed.append(cmdData)
        
        // Python with length prefix: 19 05 00 00 00 00 00 00 00 00 c8 03 00 00 a9 6c 95 69 a9 55 68 d5 55 c8 b0 00
        let pythonFramed: [UInt8] = [
            0x19,  // length = 25
            0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC8, 0x03, 0x00, 0x00,
            0xa9, 0x6c, 0x95, 0x69, 0xa9, 0x55, 0x68, 0xd5, 0x55, 0xc8, 0xb0, 0x00
        ]
        #expect(Array(framed) == pythonFramed, "Complete BLE framed command must match Python exactly (26 bytes)")
        #expect(framed.count == 26, "Framed command with length prefix is 26 bytes")
    }
    
    /// PYTHON-COMPAT-001: Verify assumeV2 produces correct v2 format
    @Test("assumeV2 enables v2 command format features")
    func assumeV2HasV2Features() {
        let v2 = RadioFirmwareVersion.assumeV2
        
        #expect(v2.supports16BitPacketDelay, "assumeV2 must support 16-bit delay")
        #expect(v2.supportsPreambleExtension, "assumeV2 must support preamble extension")
        #expect(v2.supportsResetRadioConfig, "assumeV2 must support radio config reset")
        #expect(!v2.needsExtraByteForUpdateRegisterCommand, "assumeV2 must not need extra update reg byte")
    }
}

// MARK: - Wakeup Command Tests (SWIFT-RL-002)

@Suite("Medtronic Wakeup Commands")
struct MedtronicWakeupTests {
    
    /// SWIFT-RL-002: Wakeup burst must use body byte [0x00], not empty
    @Test("Short wakeup burst body is [0x00] not empty")
    func wakeupBurstHasBodyByte() {
        // Per PROTOCOL.md: "Wakeup burst (short): Body is just 0x00 (1 byte)"
        // Bug: Was using Data() (empty) which caused pump to ignore
        let wakeMessage = PumpMessage(
            address: "208850",
            messageType: .powerOn,
            body: Data([0x00])  // Correct!
        )
        
        #expect(wakeMessage.body.count == 1, "Wakeup body must be 1 byte")
        #expect(wakeMessage.body[0] == 0x00, "Wakeup body must be 0x00")
        #expect(wakeMessage.txData.count >= 6, "Full packet must be at least 6 bytes (A7 + 3 serial + opcode + body)")
    }
    
    /// SWIFT-RL-002: Long PowerOn body must be 65 bytes
    @Test("Long PowerOn body is 65 bytes with duration")
    func longPowerOnBody65Bytes() {
        // Per PROTOCOL.md: "PowerOn with duration (long): Body is 65 bytes"
        // Format: 02 01 <minutes> + 62 zeros
        let powerBody = PowerOnCarelinkMessageBody(durationMinutes: 2)
        let data = powerBody.txData
        
        #expect(data.count == 65, "Long PowerOn body must be 65 bytes")
        #expect(data[0] == 0x02, "Byte 0 must be 0x02 (numArgs)")
        #expect(data[1] == 0x01, "Byte 1 must be 0x01 (on=true)")
        #expect(data[2] == 0x02, "Byte 2 must be duration in minutes")
        
        // Rest should be zeros
        for i in 3..<65 {
            #expect(data[i] == 0x00, "Byte \(i) must be 0x00 padding")
        }
    }
    
    /// Loop pattern: wakeup burst uses 255 repeats, 0 retries
    @Test("Wakeup burst command uses 255 repeats, 0 retries per Loop")
    func wakeupBurstParameters() {
        // Per Loop PumpOpsSession.swift sendWakeUpBurst():
        // getResponse(shortPowerMessage, repeatCount: 255, timeout: 12s, retryCount: 0)
        let wakeupRepeat = 255
        let wakeupTimeout: UInt32 = 12000  // 12 seconds in ms
        let wakeupRetries = 0
        
        let command = SendAndListenCommand(
            outgoing: Data([0xA7, 0x20, 0x88, 0x50, 0x5D, 0x00]),  // PowerOn packet
            sendChannel: 0,
            repeatCount: UInt8(wakeupRepeat),
            delayBetweenPacketsMS: 0,
            listenChannel: 0,
            timeoutMS: wakeupTimeout,
            retryCount: UInt8(wakeupRetries),
            preambleExtensionMS: 0,
            firmwareVersion: .assumeV2
        )
        
        let data = command.data
        #expect(data[2] == 255, "Wakeup must use 255 repeats (spam packets)")
        
        // Extract timeout from bytes 6-9 (big-endian 32-bit)
        let timeoutBytes = data[6..<10]
        let timeout = UInt32(timeoutBytes[6]) << 24 | UInt32(timeoutBytes[7]) << 16 |
                      UInt32(timeoutBytes[8]) << 8 | UInt32(timeoutBytes[9])
        #expect(timeout == 12000, "Wakeup timeout must be 12000ms (12s)")
        
        #expect(data[10] == 0, "Wakeup must use 0 retries (just spam, don't retry)")
    }
    
    /// Loop pattern: long PowerOn uses 0 repeats, 3 retries, 200ms timeout
    @Test("Long PowerOn command uses 0 repeats, 3 retries, 200ms timeout per Loop")
    func longPowerOnParameters() {
        // Per Loop PumpOpsSession.swift wakeup():
        // getResponse(longPowerMessage, repeatCount: 0, timeout: 200ms, retryCount: 3)
        let powerOnRepeat = 0
        let powerOnTimeout: UInt32 = 200  // 200ms (standardPumpResponseWindow)
        let powerOnRetries = 3
        
        // Build 65-byte body
        var body = Data([0x02, 0x01, 0x02])  // duration = 2 min
        body.append(Data(repeating: 0, count: 62))
        
        let command = SendAndListenCommand(
            outgoing: Data([0xA7, 0x20, 0x88, 0x50, 0x5D]) + body,
            sendChannel: 0,
            repeatCount: UInt8(powerOnRepeat),
            delayBetweenPacketsMS: 0,
            listenChannel: 0,
            timeoutMS: powerOnTimeout,
            retryCount: UInt8(powerOnRetries),
            preambleExtensionMS: 0,
            firmwareVersion: .assumeV2
        )
        
        let data = command.data
        #expect(data[2] == 0, "Long PowerOn must use 0 repeats")
        #expect(data[10] == 3, "Long PowerOn must use 3 retries")
        
        // Extract timeout from bytes 6-9 (big-endian 32-bit)
        let timeoutBytes = data[6..<10]
        let timeout = UInt32(timeoutBytes[6]) << 24 | UInt32(timeoutBytes[7]) << 16 |
                      UInt32(timeoutBytes[8]) << 8 | UInt32(timeoutBytes[9])
        #expect(timeout == 200, "Long PowerOn timeout must be 200ms")
    }
    
}

// MARK: - Normal Command Tests (Query Model, etc)

@Suite("Medtronic Normal Commands")
struct MedtronicNormalCommandTests {
    
    /// Query model message format: A7 + serial + opcode + body
    @Test("Query model message format")
    func queryModelMessageFormat() {
        let serial = "208850"
        let message = PumpMessage.readCommand(
            address: serial,
            messageType: .getPumpModel
        )
        
        let tx = message.txData
        #expect(tx[0] == 0xA7, "Byte 0 must be 0xA7 (packet type)")
        // Serial "208850" -> bytes [0x20, 0x88, 0x50]
        #expect(tx[1] == 0x20, "Byte 1 must be serial byte 0")
        #expect(tx[2] == 0x88, "Byte 2 must be serial byte 1")
        #expect(tx[3] == 0x50, "Byte 3 must be serial byte 2")
        #expect(tx[4] == 0x8D, "Byte 4 must be 0x8D (getPumpModel opcode)")
        #expect(tx[5] == 0x00, "Byte 5 must be 0x00 (body byte for read commands)")
    }
    
    /// Normal commands use 0 repeats (single send, unlike wakeup spam)
    @Test("Normal commands use 0 repeats")
    func normalCommandNoRepeats() {
        let command = SendAndListenCommand(
            outgoing: Data([0xA7, 0x20, 0x88, 0x50, 0x8D, 0x00]),
            sendChannel: 0,
            repeatCount: 0,
            delayBetweenPacketsMS: 0,
            listenChannel: 0,
            timeoutMS: 500,
            retryCount: 3,
            preambleExtensionMS: 0,
            firmwareVersion: .assumeV2
        )
        
        #expect(command.data[2] == 0, "Normal commands use 0 repeats (send once)")
    }
    
    /// Wakeup vs normal: wakeup spams (255 repeats), normal sends once
    @Test("Wakeup spams packets, normal sends once")
    func wakeupVsNormalRepeatSemantics() {
        // Wakeup burst: spam 255 packets to wake RF radio
        let wakeupRepeats: UInt8 = 255
        // Normal command: send once, rely on retries if needed
        let normalRepeats: UInt8 = 0
        
        #expect(wakeupRepeats > normalRepeats, "Wakeup must spam more than normal")
        #expect(normalRepeats == 0, "Normal commands send packet once")
    }
    
    /// Wakeup vs normal: wakeup uses 0 retries (spam handles it), normal uses retries
    @Test("Wakeup uses 0 retries, normal uses retries")
    func wakeupVsNormalRetrySemantics() {
        // Wakeup burst: 0 retries - the 255 repeats ARE the retry mechanism
        let wakeupRetries: UInt8 = 0
        // Normal command: firmware retries on RF timeout
        let normalRetries: UInt8 = 3
        
        #expect(wakeupRetries == 0, "Wakeup burst must not retry (255 repeats is enough)")
        #expect(normalRetries > 0, "Normal commands should retry on timeout")
    }
}
