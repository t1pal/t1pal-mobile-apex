// SPDX-License-Identifier: MIT
//
// DexcomG7ProtocolTests.swift
// CGMKitTests
//
// Unit tests for Dexcom G7 protocol types.
// Trace: PRD-008 REQ-BLE-008

import Testing
import Foundation
@testable import CGMKit

@Suite("DexcomG7ProtocolTests")
struct DexcomG7ProtocolTests {
    
    // MARK: - G7Constants Tests
    
    @Test("G7 constants UUIDs are correct")
    func g7ConstantsUUIDs() {
        // G7 uses same advertisement UUID as G6 (FEBC)
        // Source: externals/G7SensorKit/G7SensorKit/BluetoothServices.swift:19
        #expect(G7Constants.advertisementServiceUUID == "FEBC")
        
        // Core service UUIDs - from externals/G7SensorKit/BluetoothServices.swift
        #expect(!G7Constants.cgmServiceUUID.isEmpty)
        #expect(!G7Constants.authenticationUUID.isEmpty)
        #expect(!G7Constants.controlUUID.isEmpty)
        #expect(!G7Constants.backfillUUID.isEmpty)
        
        // Communication UUID (Read/Notify)
        #expect(!G7Constants.communicationUUID.isEmpty)
        
        // Verify correct UUIDs from external audit
        #expect(G7Constants.advertisementServiceUUID == "FEBC")
        #expect(G7Constants.authenticationUUID == "F8083535-849E-531C-C594-30F1F86A4EA5")
        #expect(G7Constants.backfillUUID == "F8083536-849E-531C-C594-30F1F86A4EA5")
    }
    
    @Test("G7 constants timing values are correct")
    func g7ConstantsTiming() {
        // G7 has shorter warmup (27 min per G7SensorKit)
        // Source: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7Sensor.swift:68
        #expect(G7Constants.sensorWarmupMinutes == 27.0)
        
        // G7 sensor life is 10.5 days (includes 12hr grace)
        #expect(G7Constants.sensorSessionDays == 10.5)
        #expect(G7Constants.sensorLifeDays == 10.5)
        
        // Grace period is 12 hours
        #expect(G7Constants.gracePeriodHours == 12.0)
        
        // Same glucose interval as G6
        #expect(G7Constants.glucoseInterval == 300.0)
        
        // BLE operation timeouts from G7PeripheralManager
        #expect(G7Constants.discoveryTimeout == 2.0)
        #expect(G7Constants.writeTimeout == 1.0)
        #expect(G7Constants.commandTimeout == 2.0)
    }
    
    @Test("G7 constants glucose values are correct")
    func g7ConstantsGlucose() {
        #expect(G7Constants.minGlucose == 40.0)
        #expect(G7Constants.maxGlucose == 400.0)
        #expect(G7Constants.glucoseNotReady == 0)
        #expect(G7Constants.glucoseError == 0xFFFF)
    }
    
    @Test("G7 uses JPAKE authentication")
    func g7UsesJPAKE() {
        // G7 uses J-PAKE authentication instead of AES
        #expect(G7Constants.usesJPAKEAuth)
        #expect(G7Constants.sensorCodeLength == 4)
    }
    
    // MARK: - G7SensorState Tests
    
    @Test("G7 sensor state raw values")
    func g7SensorStateValues() {
        #expect(G7SensorState.stopped.rawValue == 0x01)
        #expect(G7SensorState.warmup.rawValue == 0x02)
        #expect(G7SensorState.paired.rawValue == 0x03)
        #expect(G7SensorState.running.rawValue == 0x07)
        #expect(G7SensorState.expired.rawValue == 0x09)
        #expect(G7SensorState.pairing.rawValue == 0x0C)
    }
    
    @Test("G7 sensor state hasGlucose property")
    func g7SensorStateHasGlucose() {
        #expect(!G7SensorState.stopped.hasGlucose)
        #expect(!G7SensorState.warmup.hasGlucose)
        #expect(!G7SensorState.paired.hasGlucose)
        #expect(G7SensorState.okay.hasGlucose)
        #expect(G7SensorState.firstReading.hasGlucose)
        #expect(G7SensorState.running.hasGlucose)
        #expect(!G7SensorState.expired.hasGlucose)
    }
    
    @Test("G7 sensor state isActive property")
    func g7SensorStateIsActive() {
        #expect(!G7SensorState.stopped.isActive)
        #expect(G7SensorState.warmup.isActive)
        #expect(G7SensorState.paired.isActive)
        #expect(G7SensorState.running.isActive)
        #expect(!G7SensorState.expired.isActive)
        #expect(!G7SensorState.failed.isActive)
    }
    
    @Test("G7 sensor state descriptions")
    func g7SensorStateDescription() {
        #expect(G7SensorState.running.description == "Running")
        #expect(G7SensorState.warmup.description == "Warming Up")
        #expect(G7SensorState.pairing.description == "Pairing")
    }
    
    // MARK: - G7AlgorithmState Tests
    
    @Test("G7 algorithm state raw values")
    func g7AlgorithmStateValues() {
        // Values from xDrip CalibrationState.java and Loop G7SensorKit
        #expect(G7AlgorithmState.unknown.rawValue == 0x00)
        #expect(G7AlgorithmState.stopped.rawValue == 0x01)
        #expect(G7AlgorithmState.warmup.rawValue == 0x02)
        #expect(G7AlgorithmState.excessNoise.rawValue == 0x03)
        #expect(G7AlgorithmState.okay.rawValue == 0x06)
    }
    
    @Test("G7 algorithm state isReliable property")
    func g7AlgorithmStateIsReliable() {
        #expect(!G7AlgorithmState.unknown.isReliable)
        #expect(G7AlgorithmState.okay.isReliable)
        #expect(G7AlgorithmState.needsCalibration.isReliable)
        #expect(!G7AlgorithmState.warmup.isReliable)
        #expect(!G7AlgorithmState.excessNoise.isReliable)
        #expect(!G7AlgorithmState.sensorFailed.isReliable)
    }
    
    // MARK: - G7SensorInfo Tests
    
    @Test("G7 sensor info basic initialization")
    func g7SensorInfoBasic() {
        let info = G7SensorInfo(
            sensorSerial: "ABC1234567",
            sensorCode: "1234"
        )
        
        #expect(info.sensorSerial == "ABC1234567")
        #expect(info.sensorCode == "1234")
        #expect(info.activationDate == nil)
        #expect(info.expirationDate == nil)
        #expect(!info.isExpired)
        #expect(info.remainingHours == nil)
    }
    
    @Test("G7 sensor info with dates")
    func g7SensorInfoWithDates() {
        let activation = Date()
        let expiration = Date().addingTimeInterval(10.5 * 24 * 3600)  // 10.5 days
        
        let info = G7SensorInfo(
            sensorSerial: "XYZ9876543",
            sensorCode: "5678",
            activationDate: activation,
            expirationDate: expiration
        )
        
        #expect(!info.isExpired)
        #expect(info.remainingHours != nil)
        #expect(info.remainingHours! > 250.0)  // ~10.5 days in hours
    }
    
    @Test("G7 sensor info expired")
    func g7SensorInfoExpired() {
        let expiration = Date().addingTimeInterval(-3600)  // 1 hour ago
        
        let info = G7SensorInfo(
            sensorSerial: "EXPIRED123",
            expirationDate: expiration
        )
        
        #expect(info.isExpired)
        #expect(info.remainingHours == 0.0)
    }
    
    // MARK: - G7 Message Opcodes Tests
    
    @Test("G7 opcodes differ from G6")
    func g7OpcodesDifferFromG6() {
        // G7 uses different glucose opcodes
        #expect(G7Opcode.glucoseTx.rawValue == 0x4E)
        #expect(G7Opcode.glucoseRx.rawValue == 0x4F)
        
        // G7 has J-PAKE auth phases
        #expect(G7Opcode.authInit.rawValue == 0x01)
        #expect(G7Opcode.authRound1.rawValue == 0x02)
        #expect(G7Opcode.authRound2.rawValue == 0x03)
        #expect(G7Opcode.authConfirm.rawValue == 0x04)
        
        // G7-specific pairing
        #expect(G7Opcode.pairRequest.rawValue == 0x08)
    }
    
    // MARK: - G7 Glucose Message Tests
    
    @Test("G7 glucose TX message")
    func g7GlucoseTxMessage() {
        let msg = G7GlucoseTxMessage()
        #expect(msg.data == Data([0x4E]))
    }
    
    @Test("G7 glucose RX message parsing")
    func g7GlucoseRxMessageParsing() {
        // Build a valid G7 glucose response matching Loop's G7GlucoseMessage format (19+ bytes)
        // Format from G7Messages.swift:
        //   [0] = opcode (0x4E glucoseTx)
        //   [1] = status (0x00)
        //   [2..5] = timestamp (UInt32)
        //   [6..7] = sequence (UInt16)
        //   [8..9] = reserved
        //   [10..11] = age (UInt16)
        //   [12..13] = glucose (UInt16, 12-bit)
        //   [14] = algorithm state
        //   [15] = trend (Int8)
        //   [16..17] = predicted (UInt16, 12-bit)
        //   [18] = sensor state / calibration flags
        var data = Data(repeating: 0, count: 19)
        data[0] = G7Opcode.glucoseTx.rawValue  // 0x4E
        data[1] = 0x00  // status OK
        
        // timestamp at [2..5]
        var timestamp: UInt32 = 1234567890
        withUnsafeBytes(of: &timestamp) { ptr in
            data.replaceSubrange(2..<6, with: ptr)
        }
        
        // sequence at [6..7]
        var sequence: UInt16 = 100
        withUnsafeBytes(of: &sequence) { ptr in
            data.replaceSubrange(6..<8, with: ptr)
        }
        
        // age at [10..11]
        var age: UInt16 = 300
        withUnsafeBytes(of: &age) { ptr in
            data.replaceSubrange(10..<12, with: ptr)
        }
        
        // glucose at [12..13]
        var glucose: UInt16 = 120
        withUnsafeBytes(of: &glucose) { ptr in
            data.replaceSubrange(12..<14, with: ptr)
        }
        
        // algorithm state at [14]
        data[14] = G7AlgorithmState.okay.rawValue
        
        // trend at [15]
        data[15] = UInt8(bitPattern: Int8(4))
        
        // predicted at [16..17]
        var predicted: UInt16 = 125
        withUnsafeBytes(of: &predicted) { ptr in
            data.replaceSubrange(16..<18, with: ptr)
        }
        
        // sensor state at [18]
        data[18] = G7SensorState.running.rawValue
        
        let msg = G7GlucoseRxMessage(data: data)
        #expect(msg != nil)
        #expect(msg?.glucoseValue == 120)
        #expect(msg?.glucose == 120)
        #expect(msg?.predictedGlucose == 125)
        #expect(msg?.trend == 4)
        #expect(msg?.isValid ?? false)
        #expect(msg?.parsedSensorState == .running)
        #expect(msg?.parsedAlgorithmState == .okay)
    }
    
    @Test("G7 glucose RX message rejects invalid data")
    func g7GlucoseRxMessageInvalidData() {
        // Too short
        let shortData = Data([0x4F, 0x01])
        #expect(G7GlucoseRxMessage(data: shortData) == nil)
        
        // Wrong opcode
        var wrongOpcode = Data(repeating: 0, count: 20)
        wrongOpcode[0] = 0xFF
        #expect(G7GlucoseRxMessage(data: wrongOpcode) == nil)
    }
    
    // MARK: - G7 EGV Message Tests
    
    @Test("G7 EGV TX message")
    func g7EGVTxMessage() {
        let msg = G7EGVTxMessage()
        #expect(msg.data == Data([0x50]))
    }
    
    @Test("G7 EGV RX message parsing")
    func g7EGVRxMessageParsing() {
        var data = Data([G7Opcode.egvRx.rawValue])  // opcode
        
        var sequence: UInt32 = 50
        withUnsafeBytes(of: &sequence) { data.append(contentsOf: $0) }
        
        var timestamp: UInt32 = 9876543
        withUnsafeBytes(of: &timestamp) { data.append(contentsOf: $0) }
        
        var egv: UInt16 = 145
        withUnsafeBytes(of: &egv) { data.append(contentsOf: $0) }
        
        data.append(UInt8(bitPattern: Int8(6)))  // trend: rising
        data.append(0x00)  // status: OK
        data.append(0x00)  // padding
        
        let msg = G7EGVRxMessage(data: data)
        #expect(msg != nil)
        #expect(msg?.egv == 145)
        #expect(msg?.glucose == 145)
        #expect(msg?.trend == 6)
        #expect(msg?.isValid ?? false)
    }
    
    // MARK: - G7 Backfill Message Tests
    
    @Test("G7 backfill TX message")
    func g7BackfillTxMessage() {
        let msg = G7BackfillTxMessage(startTime: 1000, endTime: 2000)
        #expect(msg.data.count == 9)
        #expect(msg.data[0] == 0x52)
    }
    
    @Test("G7 backfill reading struct")
    func g7BackfillReadingStruct() {
        let reading = G7BackfillReading(
            timestampOffset: 300,
            glucoseValue: 110,
            trend: 4,
            state: G7SensorState.running.rawValue
        )
        
        #expect(reading.glucose == 110.0)
        #expect(reading.isValid)
    }
    
    // MARK: - G7 Sensor Info Message Tests
    
    @Test("G7 sensor info TX message")
    func g7SensorInfoTxMessage() {
        let msg = G7SensorInfoTxMessage()
        #expect(msg.data == Data([0x20]))
    }
    
    // MARK: - G7 Control Message Tests
    
    @Test("G7 keep alive TX message")
    func g7KeepAliveTxMessage() {
        let msg = G7KeepAliveTxMessage(time: 30)
        #expect(msg.data == Data([0x06, 30]))
    }
    
    @Test("G7 bond request TX message")
    func g7BondRequestTxMessage() {
        let msg = G7BondRequestTxMessage()
        #expect(msg.data == Data([0x07]))
    }
    
    @Test("G7 pair request TX message")
    func g7PairRequestTxMessage() {
        let msg = G7PairRequestTxMessage(sensorCode: "1234")
        #expect(msg.data.count == 5)  // opcode + 4 digit code
        #expect(msg.data[0] == 0x08)
    }
    
    @Test("G7 disconnect TX message")
    func g7DisconnectTxMessage() {
        let msg = G7DisconnectTxMessage()
        #expect(msg.data == Data([0x09]))
    }
    
    // MARK: - G7 Auth Message Tests
    
    @Test("G7 auth init message")
    func g7AuthInitMessage() {
        let msg = G7AuthInitMessage(sensorCode: "5678")
        #expect(msg.data[0] == 0x01)
        #expect(msg.data.count == 5)  // opcode + 4 digit code
    }
    
    @Test("G7 auth status message parsing")
    func g7AuthStatusMessageParsing() {
        let data = Data([
            G7Opcode.authStatus.rawValue,
            0x01,  // authenticated
            0x01,  // bonded
            0x01   // pairing complete
        ])
        
        let msg = G7AuthStatusMessage(data: data)
        #expect(msg != nil)
        #expect(msg?.authenticated ?? false)
        #expect(msg?.bonded ?? false)
        #expect(msg?.pairingComplete ?? false)
    }
    
    // MARK: - G7 Calibration Message Tests
    
    @Test("G7 calibration TX message")
    func g7CalibrationTxMessage() {
        let msg = G7CalibrationTxMessage(glucoseValue: 120)
        #expect(msg.data.count == 3)
        #expect(msg.data[0] == 0x34)
    }
    
    @Test("G7 calibration RX message parsing")
    func g7CalibrationRxMessageParsing() {
        let data = Data([
            G7Opcode.calibrationRx.rawValue,
            0x00,  // status
            0x01   // accepted
        ])
        
        let msg = G7CalibrationRxMessage(data: data)
        #expect(msg != nil)
        #expect(msg?.accepted ?? false)
    }
    
    // MARK: - G7 Session Tracking Tests (G6-DIRECT-036)
    
    @Test("G7 session timing constants")
    func g7SessionTimingConstants() {
        // G7 warmup is 27 minutes (vs G6's 2 hours)
        #expect(DexcomG7Manager.warmupDuration == 27 * 60)
        
        // Same 10 day session as G6
        #expect(DexcomG7Manager.sessionDuration == 10 * 24 * 60 * 60)
        
        // Same 12 hour grace period
        #expect(DexcomG7Manager.gracePeriod == 12 * 60 * 60)
    }
    
    @Test("G7 sensor time RX message session age")
    func g7SensorTimeRxMessageSessionAge() {
        // Build a G7SensorTimeRxMessage
        // Format: [opcode:0x25][status:1][currentTime:4][sessionStartTime:4]
        var data = Data([G7Opcode.sensorTimeRx.rawValue, 0x00])
        
        // currentTime = 100000 seconds (little-endian)
        let currentTime: UInt32 = 100000
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        
        // sessionStartTime = 93000 seconds (session started 7000 seconds ago)
        let sessionStart: UInt32 = 93000
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = G7SensorTimeRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.sessionAge == 7000)  // 100000 - 93000
    }
    
    @Test("G7 sensor time RX message rejects short data")
    func g7SensorTimeRxMessageRejectsShortData() {
        let shortData = Data([G7Opcode.sensorTimeRx.rawValue, 0x00, 0x01, 0x02])  // Only 4 bytes, needs 10
        let message = G7SensorTimeRxMessage(data: shortData)
        #expect(message == nil)
    }
    
    @Test("G7 sensor time RX message rejects wrong opcode")
    func g7SensorTimeRxMessageRejectsWrongOpcode() {
        var data = Data([0x99, 0x00])  // Wrong opcode
        let time: UInt32 = 100000
        withUnsafeBytes(of: time) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: time) { data.append(contentsOf: $0) }
        
        let message = G7SensorTimeRxMessage(data: data)
        #expect(message == nil)
    }
    
    @Test("G7 sensor time RX message session age hours")
    func g7SensorTimeRxMessageSessionAgeHours() {
        var data = Data([G7Opcode.sensorTimeRx.rawValue, 0x00])
        
        let currentTime: UInt32 = 7200  // 2 hours in seconds
        let sessionStart: UInt32 = 0
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = G7SensorTimeRxMessage(data: data)
        #expect(message != nil)
        #expect(abs(message!.sessionAgeHours - 2.0) < 0.001)
    }
    
    @Test("G7 warmup boundary")
    func g7WarmupBoundary() {
        // G7 warmup is 27 minutes (1620 seconds)
        let warmup = DexcomG7Manager.warmupDuration
        #expect(warmup == 1620)
        
        // Just before warmup ends (1619 seconds)
        let justBeforeAge: UInt32 = UInt32(warmup) - 1
        #expect(TimeInterval(justBeforeAge) < warmup)
        
        // Exactly at warmup end (1620 seconds)
        let atWarmupAge: UInt32 = UInt32(warmup)
        #expect(TimeInterval(atWarmupAge) >= warmup)
    }
}
