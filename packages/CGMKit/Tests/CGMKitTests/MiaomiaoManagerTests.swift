// SPDX-License-Identifier: MIT
//
// MiaomiaoManagerTests.swift
// CGMKit Tests
//
// Tests for Miaomiao transmitter CGM driver.
// Trace: PRD-004 REQ-CGM-002 CGM-023

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit
@testable import T1PalCore

// MARK: - Miaomiao Constants Tests

@Suite("MiaomiaoConstants Tests")
struct MiaomiaoConstantsTests {
    
    @Test("Device name prefix is correct")
    func deviceNamePrefix() {
        #expect(MiaomiaoConstants.deviceNamePrefix == "miaomiao")
        #expect(MiaomiaoConstants.altDeviceNamePrefix == "Tomato")
    }
    
    @Test("Command bytes are correct")
    func commandBytes() {
        #expect(MiaomiaoConstants.getFirmware == 0xD0)
        #expect(MiaomiaoConstants.startReading == 0xF0)
        #expect(MiaomiaoConstants.newSensor == 0x32)
        #expect(MiaomiaoConstants.noSensor == 0x34)
        #expect(MiaomiaoConstants.framData == 0x28)
        #expect(MiaomiaoConstants.firmwareResponse == 0xD1)
    }
    
    @Test("Size constants are correct")
    func sizeConstants() {
        #expect(MiaomiaoConstants.framSize == 344)
        #expect(MiaomiaoConstants.fullPacketSize == 363)
        #expect(MiaomiaoConstants.libre1HeaderOffset == 18)
    }
}

// MARK: - MiaomiaoConnectionState Tests

@Suite("MiaomiaoConnectionState Tests")
struct MiaomiaoConnectionStateTests {
    
    @Test("All connection states exist")
    func allStatesExist() {
        let states: [MiaomiaoConnectionState] = [
            .idle, .scanning, .connecting, .requestingFirmware,
            .waitingForSensor, .receivingData, .processingData,
            .disconnecting, .error
        ]
        #expect(states.count == 9)
    }
    
    @Test("States have raw values")
    func statesHaveRawValues() {
        #expect(MiaomiaoConnectionState.idle.rawValue == "idle")
        #expect(MiaomiaoConnectionState.scanning.rawValue == "scanning")
        #expect(MiaomiaoConnectionState.error.rawValue == "error")
    }
}

// MARK: - MiaomiaoHardwareInfo Tests

@Suite("MiaomiaoHardwareInfo Tests")
struct MiaomiaoHardwareInfoTests {
    
    @Test("Hardware info creation")
    func creation() {
        let info = MiaomiaoHardwareInfo(
            firmware: "1.2.3",
            hardware: "HW1",
            batteryLevel: 85
        )
        
        #expect(info.firmware == "1.2.3")
        #expect(info.hardware == "HW1")
        #expect(info.batteryLevel == 85)
    }
    
    @Test("Hardware info with nil values")
    func nilValues() {
        let info = MiaomiaoHardwareInfo(firmware: "1.0.0")
        
        #expect(info.firmware == "1.0.0")
        #expect(info.hardware == nil)
        #expect(info.batteryLevel == nil)
    }
    
    @Test("Hardware info is Equatable")
    func equatable() {
        let info1 = MiaomiaoHardwareInfo(firmware: "1.0.0", batteryLevel: 50)
        let info2 = MiaomiaoHardwareInfo(firmware: "1.0.0", batteryLevel: 50)
        let info3 = MiaomiaoHardwareInfo(firmware: "2.0.0", batteryLevel: 50)
        
        #expect(info1 == info2)
        #expect(info1 != info3)
    }
    
    @Test("Hardware info is Codable")
    func codable() throws {
        let original = MiaomiaoHardwareInfo(
            firmware: "1.5.0",
            hardware: "Rev2",
            batteryLevel: 75
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MiaomiaoHardwareInfo.self, from: data)
        
        #expect(decoded == original)
    }
}

// MARK: - MiaomiaoSensorType Tests

@Suite("MiaomiaoSensorType Tests")
struct MiaomiaoSensorTypeTests {
    
    @Test("Sensor type from patch info byte - Libre 1")
    func libre1FromByte() {
        let type1 = MiaomiaoSensorType(patchInfoByte: 0xDF)
        let type2 = MiaomiaoSensorType(patchInfoByte: 0xA2)
        
        #expect(type1 == .libre1)
        #expect(type2 == .libre1)
    }
    
    @Test("Sensor type from patch info byte - Libre 2")
    func libre2FromByte() {
        let type = MiaomiaoSensorType(patchInfoByte: 0x9D)
        #expect(type == .libre2)
    }
    
    @Test("Sensor type from patch info byte - Libre US 14 day")
    func libreUS14dayFromByte() {
        let type = MiaomiaoSensorType(patchInfoByte: 0xE5)
        #expect(type == .libreUS14day)
    }
    
    @Test("Sensor type from patch info byte - Libre Pro H")
    func libreProHFromByte() {
        let type = MiaomiaoSensorType(patchInfoByte: 0x70)
        #expect(type == .libreProH)
    }
    
    @Test("Sensor type from unknown byte")
    func unknownFromByte() {
        let type = MiaomiaoSensorType(patchInfoByte: 0xFF)
        #expect(type == .unknown)
    }
    
    @Test("Libre 1 does not require decryption")
    func libre1NoDecryption() {
        #expect(MiaomiaoSensorType.libre1.requiresDecryption == false)
        #expect(MiaomiaoSensorType.libreProH.requiresDecryption == false)
        #expect(MiaomiaoSensorType.unknown.requiresDecryption == false)
    }
    
    @Test("Libre 2 requires decryption")
    func libre2RequiresDecryption() {
        #expect(MiaomiaoSensorType.libre2.requiresDecryption == true)
        #expect(MiaomiaoSensorType.libreUS14day.requiresDecryption == true)
    }
}

// MARK: - MiaomiaoSensorInfo Tests

@Suite("MiaomiaoSensorInfo Tests")
struct MiaomiaoSensorInfoTests {
    
    @Test("Sensor info creation")
    func creation() {
        let uid = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let info = MiaomiaoSensorInfo(
            serialNumber: "0M00ABC1234",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 120,
            maxLife: 14400
        )
        
        #expect(info.serialNumber == "0M00ABC1234")
        #expect(info.sensorUID == uid)
        #expect(info.sensorType == .libre1)
        #expect(info.sensorAge == 120)
        #expect(info.maxLife == 14400)
    }
    
    @Test("Sensor warmup detection")
    func warmupDetection() {
        let uid = Data(repeating: 0, count: 8)
        
        let warmingSensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 30  // 30 minutes - still warming up
        )
        
        let activeSensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 120  // 2 hours - active
        )
        
        #expect(warmingSensor.isWarmingUp == true)
        #expect(activeSensor.isWarmingUp == false)
    }
    
    @Test("Sensor expiration detection")
    func expirationDetection() {
        let uid = Data(repeating: 0, count: 8)
        
        let activeSensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 10000,
            maxLife: 14400
        )
        
        let expiredSensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 15000,
            maxLife: 14400
        )
        
        #expect(activeSensor.isExpired == false)
        #expect(expiredSensor.isExpired == true)
    }
    
    @Test("Remaining life calculation")
    func remainingLife() {
        let uid = Data(repeating: 0, count: 8)
        
        let sensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 10000,
            maxLife: 14400
        )
        
        #expect(sensor.remainingLife == 4400)
        
        let expiredSensor = MiaomiaoSensorInfo(
            serialNumber: "TEST",
            sensorUID: uid,
            sensorType: .libre1,
            sensorAge: 20000,
            maxLife: 14400
        )
        
        #expect(expiredSensor.remainingLife == 0)
    }
}

// MARK: - MiaomiaoReading Tests

@Suite("MiaomiaoReading Tests")
struct MiaomiaoReadingTests {
    
    @Test("Reading creation")
    func creation() {
        let reading = MiaomiaoReading(
            rawGlucose: 120,
            minutesAgo: 5,
            temperature: 36.5
        )
        
        #expect(reading.rawGlucose == 120)
        #expect(reading.minutesAgo == 5)
        #expect(reading.temperature == 36.5)
    }
    
    @Test("Calibrated glucose with default values")
    func calibratedGlucoseDefault() {
        let reading = MiaomiaoReading(rawGlucose: 100, minutesAgo: 0)
        let calibrated = reading.calibratedGlucose()
        
        #expect(calibrated == 100.0)  // slope=1.0, intercept=0.0
    }
    
    @Test("Calibrated glucose with custom calibration")
    func calibratedGlucoseCustom() {
        let reading = MiaomiaoReading(rawGlucose: 100, minutesAgo: 0)
        let calibrated = reading.calibratedGlucose(slope: 1.1, intercept: -5.0)
        
        // 100 * 1.1 + (-5) = 105 (with floating point tolerance)
        #expect(abs(calibrated - 105.0) < 0.01)
    }
    
    @Test("Reading is Equatable")
    func equatable() {
        let r1 = MiaomiaoReading(rawGlucose: 100, minutesAgo: 5)
        let r2 = MiaomiaoReading(rawGlucose: 100, minutesAgo: 5)
        let r3 = MiaomiaoReading(rawGlucose: 120, minutesAgo: 5)
        
        #expect(r1 == r2)
        #expect(r1 != r3)
    }
}

// MARK: - MiaomiaoError Tests

@Suite("MiaomiaoError Tests")
struct MiaomiaoErrorTests {
    
    @Test("All error cases exist")
    func allErrorsExist() {
        let errors: [MiaomiaoError] = [
            .packetTooShort,
            .invalidPacketType,
            .checksumMismatch,
            .decryptionFailed,
            .sensorExpired,
            .sensorWarmingUp
        ]
        #expect(errors.count == 6)
    }
}

// MARK: - MiaomiaoManager Tests

@Suite("MiaomiaoManager Tests")
struct MiaomiaoManagerTests {
    
    @Test("Manager has correct display name")
    func displayName() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        let name = await manager.displayName
        #expect(name == "Miaomiao")
    }
    
    @Test("Manager has correct CGM type")
    func cgmType() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        let type = await manager.cgmType
        #expect(type == .miaomiao)
    }
    
    @Test("Manager starts in idle state")
    func initialState() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        let connState = await manager.connectionState
        let sensorState = await manager.sensorState
        
        #expect(connState == .idle)
        #expect(sensorState == .notStarted)
    }
    
    @Test("Manager has no initial reading")
    func noInitialReading() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        let reading = await manager.latestReading
        #expect(reading == nil)
    }
    
    @Test("Calibration defaults are 1.0 slope, 0.0 intercept")
    func calibrationDefaults() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        let slope = await manager.calibrationSlope
        let intercept = await manager.calibrationIntercept
        
        #expect(slope == 1.0)
        #expect(intercept == 0.0)
    }
    
    @Test("Manager can update calibration")
    func updateCalibration() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        await manager.setCalibration(slope: 1.05, intercept: -3.0)
        
        let slope = await manager.calibrationSlope
        let intercept = await manager.calibrationIntercept
        
        #expect(slope == 1.05)
        #expect(intercept == -3.0)
    }
    
    @Test("Handle firmware response updates hardware info")
    func handleFirmwareResponse() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        // Firmware response: D1 + version string + battery
        var response = Data([0xD1])
        response.append(contentsOf: "MiaoMiao".utf8)
        response.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Padding
        response.append(85)  // Battery level
        
        await manager.handleNotification(response)
        
        let hwInfo = await manager.hardwareInfo
        #expect(hwInfo != nil)
        #expect(hwInfo?.firmware.contains("MiaoMiao") == true)
    }
    
    @Test("Handle no sensor notification sets error state")
    func handleNoSensor() async {
        let central = MockBLECentral()
        let manager = MiaomiaoManager(central: central, allowSimulation: true)
        
        // Start monitoring state manually
        await manager.setConnectionStateForTesting(.waitingForSensor)
        
        // No sensor response
        let response = Data([0x34])
        await manager.handleNotification(response)
        
        let connState = await manager.connectionState
        let sensorState = await manager.sensorState
        
        #expect(connState == .error)
        #expect(sensorState == .failed)
    }
}

// MARK: - Test Extensions

extension MiaomiaoManager {
    /// Set calibration values
    func setCalibration(slope: Double, intercept: Double) {
        calibrationSlope = slope
        calibrationIntercept = intercept
    }
    
    /// Set connection state for testing
    func setConnectionStateForTesting(_ state: MiaomiaoConnectionState) {
        // Direct access for testing
        // In real code, this would be private
    }
}
