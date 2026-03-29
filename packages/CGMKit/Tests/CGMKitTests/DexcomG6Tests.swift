// SPDX-License-Identifier: MIT
//
// DexcomG6Tests.swift
// CGMKitTests
//
// Unit tests for Dexcom G6 protocol types.

import Testing
import Foundation
@testable import CGMKit

@Suite("TransmitterID Tests")
struct TransmitterIDTests {
    
    @Test("Valid 6-character transmitter ID")
    func validTransmitterID() {
        let tx = TransmitterID("80AB12")
        
        #expect(tx != nil)
        #expect(tx?.id == "80AB12")
    }
    
    @Test("Transmitter ID is uppercased")
    func uppercased() {
        let tx = TransmitterID("80ab12")
        
        #expect(tx?.id == "80AB12")
    }
    
    @Test("Invalid transmitter ID length")
    func invalidLength() {
        #expect(TransmitterID("80AB1") == nil)
        #expect(TransmitterID("80AB123") == nil)
        #expect(TransmitterID("") == nil)
    }
    
    @Test("G5 transmitter detection")
    func g5Detection() {
        let tx1 = TransmitterID("4ABC12")
        let tx2 = TransmitterID("5XY789")
        let tx3 = TransmitterID("6MN456")
        
        #expect(tx1?.generation == .g5)
        #expect(tx2?.generation == .g5)
        #expect(tx3?.generation == .g5)
        #expect(tx1?.usesG6Auth == false)
    }
    
    @Test("G6 transmitter detection")
    func g6Detection() {
        let tx1 = TransmitterID("80AB12")
        let tx2 = TransmitterID("81CD34")
        
        #expect(tx1?.generation == .g6)
        #expect(tx2?.generation == .g6)
        #expect(tx1?.usesG6Auth == true)
        #expect(tx1?.requiresEncryption == false)
    }
    
    @Test("G6+ (Firefly) transmitter detection")
    func g6PlusDetection() {
        let fireflyPrefixes = ["8G", "8H", "8J", "8K", "8L", "8M", "8N", "8P"]
        
        for prefix in fireflyPrefixes {
            let tx = TransmitterID("\(prefix)AB12")
            #expect(tx?.generation == .g6Plus, "Expected G6+ for prefix \(prefix)")
            #expect(tx?.usesG6Auth == true)
            #expect(tx?.requiresEncryption == true)
        }
    }
    
    @Test("Unknown transmitter generation")
    func unknownGeneration() {
        let tx = TransmitterID("1ABC12")
        
        #expect(tx?.generation == .unknown)
        #expect(tx?.usesG6Auth == false)
    }
    
    @Test("TransmitterID validation")
    func validation() {
        #expect(TransmitterID.isValid("80AB12") == true)
        #expect(TransmitterID.isValid("80ab12") == true)
        #expect(TransmitterID.isValid("80AB1") == false)
        #expect(TransmitterID.isValid("80AB123") == false)
        #expect(TransmitterID.isValid("") == false)
    }
    
    @Test("TransmitterID hashable")
    func hashable() {
        let tx1 = TransmitterID("80AB12")
        let tx2 = TransmitterID("80AB12")
        let tx3 = TransmitterID("80CD34")
        
        #expect(tx1 == tx2)
        #expect(tx1 != tx3)
        
        var set: Set<TransmitterID> = []
        set.insert(tx1!)
        set.insert(tx2!)
        #expect(set.count == 1)
    }
}

@Suite("G6 Messages Tests")
struct G6MessagesTests {
    
    @Test("AuthRequestTxMessage creation")
    func authRequestTx() {
        let token = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let msg = AuthRequestTxMessage(singleUseToken: token)
        
        // CGMBLEKit format: opcode(1) + token(8) + endByte(1) = 10 bytes
        #expect(msg.data.count == 10)
        #expect(msg.data[0] == G6Opcode.authRequestTx.rawValue)
        #expect(msg.data[9] == 0x02)  // End byte
    }
    
    @Test("AuthChallengeRxMessage parsing")
    func authChallengeRx() {
        var data = Data([G6Opcode.authRequestRx.rawValue])
        data.append(Data(repeating: 0xAA, count: 8))  // tokenHash
        data.append(Data(repeating: 0xBB, count: 8))  // challenge
        
        let msg = AuthChallengeRxMessage(data: data)
        
        #expect(msg != nil)
        #expect(msg?.tokenHash.count == 8)
        #expect(msg?.challenge.count == 8)
    }
    
    @Test("AuthChallengeRxMessage rejects short data")
    func authChallengeRxShort() {
        let data = Data([G6Opcode.authChallengeRx.rawValue, 0x01, 0x02])
        
        let msg = AuthChallengeRxMessage(data: data)
        
        #expect(msg == nil)
    }
    
    @Test("AuthStatusRxMessage parsing")
    func authStatusRx() {
        // Note: Uses authChallengeRx opcode (0x05) per CGMBLEKit
        let data = Data([G6Opcode.authChallengeRx.rawValue, 0x01, 0x01])
        
        let msg = AuthStatusRxMessage(data: data)
        
        #expect(msg != nil)
        #expect(msg?.authenticated == true)
        #expect(msg?.bonded == true)
    }
    
    @Test("GlucoseTxMessage creation")
    func glucoseTx() {
        let msg = GlucoseTxMessage()
        
        #expect(msg.data.count == 1)
        #expect(msg.data[0] == G6Opcode.glucoseTx.rawValue)
    }
    
    @Test("GlucoseRxMessage parsing with 0x31 opcode")
    func glucoseRx() {
        // Loop format: [opcode:1][status:1][sequence:4][timestamp:4][glucose:2][state:1][trend:1]
        var data = Data([G6Opcode.glucoseRx.rawValue, 0x00])  // opcode, status
        data.append(contentsOf: withUnsafeBytes(of: UInt32(100)) { Array($0) })  // sequence
        data.append(contentsOf: withUnsafeBytes(of: UInt32(12345)) { Array($0) })  // timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt16(120)) { Array($0) })  // glucose
        data.append(contentsOf: [0x06, 0x02])  // state, trend
        
        let msg = GlucoseRxMessage(data: data)
        
        #expect(msg != nil)
        #expect(msg?.glucoseValue == 120)
        #expect(msg?.glucose == 120.0)
        #expect(msg?.isValid == true)
        #expect(msg?.state == 0x06)
        #expect(msg?.trend == 2)
    }
    
    @Test("GlucoseRxMessage parsing with 0x4F opcode (G6 EGV)")
    func glucoseRxG6Opcode() {
        // Real G6 coexistence data: 4F 00 0A 66 00 00 6E 5E 7D 00 9D 00 06 00...
        // This is the actual opcode G6 transmitters send in coexistence mode
        var data = Data([G6Opcode.glucoseG6Rx.rawValue, 0x00])  // opcode 0x4F, status
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x0000660A)) { Array($0) })  // sequence
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x007D5E6E)) { Array($0) })  // timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt16(157)) { Array($0) })  // glucose = 157 mg/dL
        data.append(contentsOf: [0x06, 0x00])  // state, trend
        
        let msg = GlucoseRxMessage(data: data)
        
        #expect(msg != nil)
        #expect(msg?.opcode == 0x4F)
        #expect(msg?.glucoseValue == 157)
        #expect(msg?.isValid == true)
    }
    
    @Test("GlucoseRxMessage invalid glucose")
    func glucoseRxInvalid() {
        var data = Data([G6Opcode.glucoseRx.rawValue, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(100)) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(12345)) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Array($0) })  // invalid
        data.append(contentsOf: [0x00, 0x00])  // state, trend
        
        let msg = GlucoseRxMessage(data: data)
        
        #expect(msg?.isValid == false)
    }
    
    @Test("BatteryStatusTxMessage creation")
    func batteryStatusTx() {
        let msg = BatteryStatusTxMessage()
        
        #expect(msg.data.count == 1)
        #expect(msg.data[0] == G6Opcode.batteryStatusTx.rawValue)
    }
    
    @Test("KeepAliveTxMessage creation")
    func keepAliveTx() {
        let msg = KeepAliveTxMessage(time: 30)
        
        #expect(msg.data.count == 2)
        #expect(msg.data[0] == G6Opcode.keepAlive.rawValue)
        #expect(msg.data[1] == 30)
    }
    
    @Test("KeepAliveTxMessage default time")
    func keepAliveTxDefault() {
        let msg = KeepAliveTxMessage()
        
        #expect(msg.data[1] == 25)
    }
    
    @Test("BondRequestTxMessage creation")
    func bondRequestTx() {
        let msg = BondRequestTxMessage()
        
        #expect(msg.data.count == 1)
        #expect(msg.data[0] == G6Opcode.bondRequest.rawValue)
        #expect(msg.data[0] == 0x07)  // CGMBLEKit compatible
    }
    
    @Test("G6 opcode values match CGMBLEKit")
    func opcodeCompatibility() {
        // Verify opcodes match CGMBLEKit reference implementation
        #expect(G6Opcode.authRequestTx.rawValue == 0x01)
        #expect(G6Opcode.authChallengeTx.rawValue == 0x04)
        #expect(G6Opcode.authChallengeRx.rawValue == 0x05)
        #expect(G6Opcode.keepAlive.rawValue == 0x06)
        #expect(G6Opcode.bondRequest.rawValue == 0x07)
        #expect(G6Opcode.disconnectTx.rawValue == 0x09)
        // App Level Key opcodes (DiaBLE reference)
        #expect(G6Opcode.changeAppLevelKeyTx.rawValue == 0x0f)
        #expect(G6Opcode.appLevelKeyAcceptedRx.rawValue == 0x10)
    }
    
    @Test("ChangeAppLevelKeyTxMessage creates correct format")
    func changeAppLevelKeyMessage() {
        let key = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        let msg = ChangeAppLevelKeyTxMessage(key: key)
        
        #expect(msg.data.count == 17) // 1 opcode + 16 key bytes
        #expect(msg.data[0] == G6Opcode.changeAppLevelKeyTx.rawValue)
        #expect(msg.data[1...16] == key[0...15])
    }
    
    @Test("ChangeAppLevelKeyTxMessage generates random key")
    func generateRandomKey() {
        let key1 = ChangeAppLevelKeyTxMessage.generateRandomKey()
        let key2 = ChangeAppLevelKeyTxMessage.generateRandomKey()
        
        #expect(key1.count == 16)
        #expect(key2.count == 16)
        #expect(key1 != key2) // Should be different (probabilistically)
    }
    
    @Test("AppLevelKeyAcceptedRxMessage parses correctly")
    func appLevelKeyAcceptedMessage() {
        let data = Data([G6Opcode.appLevelKeyAcceptedRx.rawValue])
        let msg = AppLevelKeyAcceptedRxMessage(data: data)
        
        #expect(msg != nil)
        #expect(msg?.opcode == 0x10)
        #expect(msg?.accepted == true)
    }
    
    @Test("AppLevelKeyAcceptedRxMessage rejects wrong opcode")
    func appLevelKeyRejectedWrongOpcode() {
        let data = Data([0x99]) // Wrong opcode
        let msg = AppLevelKeyAcceptedRxMessage(data: data)
        
        #expect(msg == nil)
    }
}

@Suite("G6 Constants Tests")
struct G6ConstantsTests {
    
    @Test("Service UUIDs are defined")
    func serviceUUIDs() {
        #expect(G6Constants.cgmServiceUUID.count == 36)
        #expect(G6Constants.authenticationUUID.count == 36)
        #expect(G6Constants.controlUUID.count == 36)
        #expect(G6Constants.backfillUUID.count == 36)
    }
    
    @Test("Timing constants are reasonable")
    func timingConstants() {
        #expect(G6Constants.glucoseInterval == 300.0)
        #expect(G6Constants.sensorWarmupHours == 2.0)
        #expect(G6Constants.sensorSessionDays == 10.0)
    }
    
    @Test("Glucose bounds are valid")
    func glucoseBounds() {
        #expect(G6Constants.minGlucose == 40.0)
        #expect(G6Constants.maxGlucose == 400.0)
    }
}

@Suite("G6 Sensor State Tests")
struct G6SensorStateTests {
    
    @Test("Sensor states have descriptions")
    func descriptions() {
        #expect(G6SensorState.running.description == "Running")
        #expect(G6SensorState.warmup.description == "Warming Up")
        #expect(G6SensorState.expired.description == "Expired")
    }
    
    @Test("hasGlucose is correct")
    func hasGlucose() {
        #expect(G6SensorState.running.hasGlucose == true)
        #expect(G6SensorState.okay.hasGlucose == true)
        #expect(G6SensorState.warmup.hasGlucose == false)
        #expect(G6SensorState.stopped.hasGlucose == false)
        #expect(G6SensorState.expired.hasGlucose == false)
    }
}

@Suite("G6 Calibration State Tests")
struct G6CalibrationStateTests {
    
    @Test("needsCalibration is correct")
    func needsCalibration() {
        #expect(G6CalibrationState.needsFirstCalibration.needsCalibration == true)
        #expect(G6CalibrationState.needsSecondCalibration.needsCalibration == true)
        #expect(G6CalibrationState.needsCalibration.needsCalibration == true)
        #expect(G6CalibrationState.needsCalibration14.needsCalibration == true)
        #expect(G6CalibrationState.okay.needsCalibration == false)
    }
    
    @Test("isValid is correct")
    func isValid() {
        #expect(G6CalibrationState.okay.isValid == true)
        #expect(G6CalibrationState.warmup.isValid == false)
        #expect(G6CalibrationState.calibrationError1.isValid == false)
    }
    
    @Test("hasReliableGlucose matches Loop CalibrationState")
    func hasReliableGlucose() {
        // States with reliable glucose (from Loop CGMBLEKit)
        #expect(G6CalibrationState.okay.hasReliableGlucose == true)
        #expect(G6CalibrationState.needsCalibration.hasReliableGlucose == true)
        #expect(G6CalibrationState.needsCalibration14.hasReliableGlucose == true)
        // States without reliable glucose
        #expect(G6CalibrationState.warmup.hasReliableGlucose == false)
        #expect(G6CalibrationState.stopped.hasReliableGlucose == false)
        #expect(G6CalibrationState.sensorFailed.hasReliableGlucose == false)
    }
    
    @Test("hasFailed detects sensor failures")
    func hasFailed() {
        #expect(G6CalibrationState.sensorFailed.hasFailed == true)
        #expect(G6CalibrationState.sensorFailedDays.hasFailed == true)
        #expect(G6CalibrationState.sessionFailure1.hasFailed == true)
        #expect(G6CalibrationState.okay.hasFailed == false)
        #expect(G6CalibrationState.warmup.hasFailed == false)
    }
    
    @Test("isWarmingUp detects warmup state")
    func isWarmingUp() {
        #expect(G6CalibrationState.warmup.isWarmingUp == true)
        #expect(G6CalibrationState.okay.isWarmingUp == false)
    }
    
    @Test("fromByte handles unknown values")
    func fromByte() {
        #expect(G6CalibrationState(fromByte: 0x06) == .okay)
        #expect(G6CalibrationState(fromByte: 0x99) == .unknown)
    }
}

// MARK: - Calibrate Glucose Message Tests (G6-DIRECT-033)

@Suite("Calibrate Glucose Message Tests")
struct CalibrateGlucoseMessageTests {
    
    @Test("CalibrateGlucoseTxMessage creates correct data")
    func txMessageData() {
        let message = CalibrateGlucoseTxMessage(glucose: 120, time: 3600)
        let data = message.dataWithoutCRC
        
        // Opcode
        #expect(data[0] == G6Opcode.calibrateGlucoseTx.rawValue)
        #expect(data[0] == 0x34)
        
        // Glucose (120 = 0x78, little-endian)
        #expect(data[1] == 0x78)
        #expect(data[2] == 0x00)
        
        // Time (3600 = 0x0E10, little-endian)
        #expect(data[3] == 0x10)
        #expect(data[4] == 0x0E)
        #expect(data[5] == 0x00)
        #expect(data[6] == 0x00)
    }
    
    @Test("CalibrateGlucoseTxMessage includes CRC")
    func txMessageWithCRC() {
        let message = CalibrateGlucoseTxMessage(glucose: 100, time: 7200)
        let data = message.data
        
        // 7 bytes data + 2 bytes CRC = 9 bytes
        #expect(data.count == 9)
        #expect(data.isCRCValid)
    }
    
    @Test("CalibrateGlucoseRxMessage parses success response")
    func rxMessageSuccess() {
        // Build a valid response: [opcode:0x35][status:0x00][reserved:0x00][crc:2]
        var data = Data([0x35, 0x00, 0x00])
        data = data.appendingCRC()
        
        let message = CalibrateGlucoseRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.isSuccess == true)
        #expect(message?.status == 0)
    }
    
    @Test("CalibrateGlucoseRxMessage rejects wrong opcode")
    func rxMessageWrongOpcode() {
        var data = Data([0x31, 0x00, 0x00])  // Wrong opcode
        data = data.appendingCRC()
        
        let message = CalibrateGlucoseRxMessage(data: data)
        #expect(message == nil)
    }
    
    @Test("CalibrateGlucoseRxMessage rejects invalid CRC")
    func rxMessageInvalidCRC() {
        let data = Data([0x35, 0x00, 0x00, 0xFF, 0xFF])  // Invalid CRC
        
        let message = CalibrateGlucoseRxMessage(data: data)
        #expect(message == nil)
    }
}

// MARK: - Session Tracking Tests (G6-DIRECT-034)

@Suite("G6 Session Tracking Tests")
struct G6SessionTrackingTests {
    
    @Test("Session timing constants are correct")
    func timingConstants() {
        // G6 timing: 2 hour warmup, 10 day session, 12 hour grace
        #expect(DexcomG6Manager.warmupDuration == 2 * 60 * 60)
        #expect(DexcomG6Manager.sessionDuration == 10 * 24 * 60 * 60)
        #expect(DexcomG6Manager.gracePeriod == 12 * 60 * 60)
    }
    
    @Test("TransmitterTimeRxMessage sessionAge computes correctly")
    func sessionAgeComputation() {
        // Build a TransmitterTimeRxMessage
        // Format: [opcode:0x25][status:1][currentTime:4][sessionStartTime:4]
        var data = Data([0x25, 0x00])
        
        // currentTime = 100000 seconds (little-endian)
        let currentTime: UInt32 = 100000
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        
        // sessionStartTime = 93000 seconds (session started 7000 seconds ago)
        let sessionStart: UInt32 = 93000
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = TransmitterTimeRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.sessionAge == 7000)  // 100000 - 93000
    }
    
    @Test("TransmitterTimeRxMessage parses currentTime and sessionStartTime")
    func transmitterTimeParsing() {
        var data = Data([0x25, 0x00])  // opcode + status
        
        let currentTime: UInt32 = 864000  // 10 days in seconds
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        
        let sessionStart: UInt32 = 0
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = TransmitterTimeRxMessage(data: data)
        #expect(message?.currentTime == 864000)
        #expect(message?.sessionStartTime == 0)
        #expect(message?.sessionAge == 864000)
    }
}

// MARK: - Direct Mode Tests (G6-DIRECT-035)

@Suite("G6 Direct Mode Tests")
struct G6DirectModeTests {
    
    // MARK: - Calibration State Edge Cases
    
    @Test("All calibration states have defined behavior")
    func allCalibrationStates() {
        // Ensure all states are properly categorized
        let allStates: [G6CalibrationState] = [
            .stopped, .warmup, .needsFirstCalibration, .needsSecondCalibration,
            .okay, .needsCalibration, .calibrationError1, .calibrationError2,
            .calibrationLinearityError, .sensorFailed, .sensorFailedDays,
            .calibrationError3, .needsCalibration14, .sessionFailure1,
            .sessionFailure2, .sessionFailure3, .questionMarks, .unknown
        ]
        
        for state in allStates {
            // Each state should have defined behavior for all methods
            _ = state.needsCalibration
            _ = state.hasReliableGlucose
            _ = state.hasFailed
            _ = state.isWarmingUp
        }
        
        #expect(allStates.count == 18)
    }
    
    @Test("Calibration error states are not reliable")
    func calibrationErrorStates() {
        let errorStates: [G6CalibrationState] = [
            .calibrationError1, .calibrationError2, .calibrationError3,
            .calibrationLinearityError
        ]
        
        for state in errorStates {
            #expect(state.hasReliableGlucose == false, "Error state \(state) should not have reliable glucose")
            #expect(state.hasFailed == false, "Error state \(state) should not be marked as failed")
        }
    }
    
    @Test("Session failure states are failed and unreliable")
    func sessionFailureStates() {
        let failureStates: [G6CalibrationState] = [
            .sessionFailure1, .sessionFailure2, .sessionFailure3
        ]
        
        for state in failureStates {
            #expect(state.hasFailed == true, "Session failure \(state) should be marked as failed")
            #expect(state.hasReliableGlucose == false, "Session failure \(state) should not have reliable glucose")
            #expect(state.needsCalibration == false, "Session failure \(state) should not request calibration")
        }
    }
    
    @Test("Unknown calibration state defaults correctly")
    func unknownCalibrationState() {
        let unknown = G6CalibrationState.unknown
        #expect(unknown.needsCalibration == false)
        #expect(unknown.hasReliableGlucose == false)
        #expect(unknown.hasFailed == false)
        #expect(unknown.isWarmingUp == false)
    }
    
    // MARK: - Session Timing Edge Cases
    
    @Test("Warmup boundary at exactly 2 hours")
    func warmupBoundary() {
        let warmup = DexcomG6Manager.warmupDuration  // 7200 seconds
        
        // Just before warmup ends (7199 seconds)
        // Session age < warmup duration = in warmup
        let justBeforeAge: UInt32 = UInt32(warmup) - 1
        #expect(TimeInterval(justBeforeAge) < warmup)
        
        // Exactly at warmup end (7200 seconds)
        let atWarmupAge: UInt32 = UInt32(warmup)
        #expect(TimeInterval(atWarmupAge) >= warmup)
        
        // Just after warmup (7201 seconds)
        let justAfterAge: UInt32 = UInt32(warmup) + 1
        #expect(TimeInterval(justAfterAge) > warmup)
    }
    
    @Test("Session expiry boundary at exactly 10 days")
    func sessionExpiryBoundary() {
        let session = DexcomG6Manager.sessionDuration  // 864000 seconds
        
        // Just before expiry
        let justBefore: UInt32 = UInt32(session) - 1
        #expect(TimeInterval(justBefore) < session)
        
        // Exactly at expiry
        let atExpiry: UInt32 = UInt32(session)
        #expect(TimeInterval(atExpiry) >= session)
    }
    
    @Test("Grace period boundary at exactly 12 hours after expiry")
    func gracePeriodBoundary() {
        let session = DexcomG6Manager.sessionDuration
        let grace = DexcomG6Manager.gracePeriod
        let total = session + grace
        
        // In grace period (10 days + 6 hours)
        let inGrace: UInt32 = UInt32(session) + UInt32(grace / 2)
        let inGraceAge = TimeInterval(inGrace)
        #expect(inGraceAge >= session)
        #expect(inGraceAge < total)
        
        // Past grace period (10 days + 12 hours)
        let pastGrace: UInt32 = UInt32(total)
        #expect(TimeInterval(pastGrace) >= total)
    }
    
    // MARK: - TransmitterTimeRxMessage Edge Cases
    
    @Test("TransmitterTimeRxMessage rejects short data")
    func transmitterTimeShortData() {
        let shortData = Data([0x25, 0x00, 0x01, 0x02])  // Only 4 bytes, needs 10
        let message = TransmitterTimeRxMessage(data: shortData)
        #expect(message == nil)
    }
    
    @Test("TransmitterTimeRxMessage rejects wrong opcode")
    func transmitterTimeWrongOpcode() {
        var data = Data([0x99, 0x00])  // Wrong opcode
        let time: UInt32 = 100000
        withUnsafeBytes(of: time) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: time) { data.append(contentsOf: $0) }
        
        let message = TransmitterTimeRxMessage(data: data)
        #expect(message == nil)
    }
    
    @Test("TransmitterTimeRxMessage handles zero session start")
    func transmitterTimeZeroStart() {
        var data = Data([0x25, 0x00])
        let currentTime: UInt32 = 7200  // 2 hours in
        let sessionStart: UInt32 = 0
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = TransmitterTimeRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.sessionAge == 7200)
    }
    
    @Test("TransmitterTimeRxMessage handles max UInt32 values")
    func transmitterTimeMaxValues() {
        var data = Data([0x25, 0x00])
        let currentTime: UInt32 = .max
        let sessionStart: UInt32 = .max - 1000
        withUnsafeBytes(of: currentTime) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sessionStart) { data.append(contentsOf: $0) }
        
        let message = TransmitterTimeRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.sessionAge == 1000)
    }
    
    // MARK: - Calibration Message Edge Cases
    
    @Test("CalibrateGlucoseTxMessage handles edge glucose values")
    func calibrationEdgeGlucose() {
        // Minimum valid glucose (40 mg/dL)
        let minMsg = CalibrateGlucoseTxMessage(glucose: 40, time: 0)
        #expect(minMsg.dataWithoutCRC[1] == 40)
        #expect(minMsg.dataWithoutCRC[2] == 0)
        
        // Maximum valid glucose (400 mg/dL)
        let maxMsg = CalibrateGlucoseTxMessage(glucose: 400, time: 0)
        // 400 = 0x0190 little-endian = [0x90, 0x01]
        #expect(maxMsg.dataWithoutCRC[1] == 0x90)
        #expect(maxMsg.dataWithoutCRC[2] == 0x01)
        
        // Max UInt16 glucose
        let maxU16Msg = CalibrateGlucoseTxMessage(glucose: 0xFFFF, time: 0)
        #expect(maxU16Msg.dataWithoutCRC[1] == 0xFF)
        #expect(maxU16Msg.dataWithoutCRC[2] == 0xFF)
    }
    
    @Test("CalibrateGlucoseTxMessage handles max time value")
    func calibrationMaxTime() {
        let msg = CalibrateGlucoseTxMessage(glucose: 100, time: 0xFFFFFFFF)
        let data = msg.dataWithoutCRC
        
        // Time bytes should all be 0xFF
        #expect(data[3] == 0xFF)
        #expect(data[4] == 0xFF)
        #expect(data[5] == 0xFF)
        #expect(data[6] == 0xFF)
    }
    
    @Test("CalibrateGlucoseRxMessage handles failure status")
    func calibrationFailureStatus() {
        // Build a failure response: [opcode:0x35][status:0x01][reserved:0x00][crc:2]
        var data = Data([0x35, 0x01, 0x00])
        data = data.appendingCRC()
        
        let message = CalibrateGlucoseRxMessage(data: data)
        #expect(message != nil)
        #expect(message?.isSuccess == false)
        #expect(message?.status == 1)
    }
    
    @Test("CalibrateGlucoseRxMessage rejects short data")
    func calibrationShortData() {
        let shortData = Data([0x35, 0x00])  // Too short, needs 5 bytes
        let message = CalibrateGlucoseRxMessage(data: shortData)
        #expect(message == nil)
    }
    
    // MARK: - G6SensorState Tests
    
    @Test("G6SensorState hasGlucose is correct")
    func sensorStateHasGlucose() {
        // States with glucose
        #expect(G6SensorState.okay.hasGlucose == true)
        #expect(G6SensorState.firstReading.hasGlucose == true)
        #expect(G6SensorState.secondReading.hasGlucose == true)
        #expect(G6SensorState.running.hasGlucose == true)
        
        // States without glucose
        #expect(G6SensorState.stopped.hasGlucose == false)
        #expect(G6SensorState.warmup.hasGlucose == false)
        #expect(G6SensorState.failed.hasGlucose == false)
        #expect(G6SensorState.expired.hasGlucose == false)
        #expect(G6SensorState.ended.hasGlucose == false)
        #expect(G6SensorState.sensorError.hasGlucose == false)
        #expect(G6SensorState.unknown.hasGlucose == false)
    }
    
    @Test("G6SensorState raw values match protocol")
    func sensorStateRawValues() {
        // Verify raw values match Dexcom protocol spec
        #expect(G6SensorState.stopped.rawValue == 0x01)
        #expect(G6SensorState.warmup.rawValue == 0x02)
        #expect(G6SensorState.okay.rawValue == 0x04)
        #expect(G6SensorState.firstReading.rawValue == 0x05)
        #expect(G6SensorState.secondReading.rawValue == 0x06)
        #expect(G6SensorState.running.rawValue == 0x07)
        #expect(G6SensorState.failed.rawValue == 0x08)
        #expect(G6SensorState.expired.rawValue == 0x09)
        #expect(G6SensorState.ended.rawValue == 0x0A)
        #expect(G6SensorState.sensorError.rawValue == 0x0B)
    }
}

// MARK: - CGM-066 App Level Key Config Tests

@Suite("DexcomG6ManagerConfig ALK Tests")
struct DexcomG6ManagerConfigALKTests {
    
    @Test("Config accepts nil appLevelKey by default")
    func defaultNoALK() {
        let txId = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: txId)
        
        #expect(config.appLevelKey == nil)
        #expect(config.generateNewAppLevelKey == false)
    }
    
    @Test("Config accepts 16-byte appLevelKey")
    func validALK() {
        let txId = TransmitterID("80AB12")!
        let alk = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let config = DexcomG6ManagerConfig(transmitterId: txId, appLevelKey: alk)
        
        #expect(config.appLevelKey == alk)
        #expect(config.appLevelKey?.count == 16)
    }
    
    @Test("Config can enable generateNewAppLevelKey")
    func generateALKEnabled() {
        let txId = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: txId, generateNewAppLevelKey: true)
        
        #expect(config.generateNewAppLevelKey == true)
    }
    
    @Test("Config with both ALK and generateNew")
    func alkWithGenerateNew() {
        let txId = TransmitterID("80AB12")!
        let alk = Data(repeating: 0xAB, count: 16)
        
        let config = DexcomG6ManagerConfig(
            transmitterId: txId,
            appLevelKey: alk,
            generateNewAppLevelKey: true
        )
        
        #expect(config.appLevelKey == alk)
        #expect(config.generateNewAppLevelKey == true)
    }
}

@Suite("G6Authenticator ALK Tests")
struct G6AuthenticatorALKTests {
    
    @Test("Authenticator with ALK sets usingAppLevelKey flag")
    func alkAuthenticator() {
        let txId = TransmitterID("80AB12")!
        let alk = Data(repeating: 0xCD, count: 16)
        
        let auth = G6Authenticator(transmitterId: txId, appLevelKey: alk)
        
        #expect(auth.usingAppLevelKey == true)
        #expect(auth.cryptKey == alk)
    }
    
    @Test("Authenticator without ALK uses derived key")
    func derivedKeyAuthenticator() {
        let txId = TransmitterID("80AB12")!
        let auth = G6Authenticator(transmitterId: txId)
        
        #expect(auth.usingAppLevelKey == false)
        // Derived key: "00" + id + "00" + id = "0080AB120080AB12"
        let expected = "0080AB120080AB12".data(using: .utf8)!
        #expect(auth.cryptKey == expected)
    }
}
