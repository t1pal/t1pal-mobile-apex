// SPDX-License-Identifier: MIT
//
// Libre2ManagerTests.swift
// CGMKit
//
// Tests for Libre2Manager driver.
// Trace: PRD-004 REQ-CGM-002 CGM-021

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

@Suite("Libre2Manager Tests")
struct Libre2ManagerTests {
    
    // MARK: - Test Data
    
    static let testSensorUID = Data([0x2f, 0xe7, 0xb1, 0x00, 0x00, 0xa4, 0x07, 0xe0])
    static let testPatchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
    static let testEnableTime: UInt32 = 1000000
    
    static var testSensorInfo: Libre2SensorInfo {
        Libre2SensorInfo(
            sensorUID: testSensorUID,
            patchInfo: testPatchInfo,
            enableTime: testEnableTime,
            serialNumber: "ABC123",
            sensorType: .libre2
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test("CGM type is libre2")
    func cgmType() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let type = await manager.cgmType
        #expect(type == .libre2)
    }
    
    @Test("Display name is FreeStyle Libre 2")
    func displayName() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let name = await manager.displayName
        #expect(name == "FreeStyle Libre 2")
    }
    
    @Test("Latest reading is nil initially")
    func latestReadingNil() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let reading = await manager.latestReading
        #expect(reading == nil)
    }
    
    @Test("Sensor state is notStarted initially")
    func sensorStateNotStarted() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let state = await manager.sensorState
        #expect(state == .notStarted)
    }
    
    @Test("Connection state is idle initially")
    func connectionStateIdle() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    @Test("Unlock count is 0 initially")
    func unlockCountZero() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        let count = await manager.unlockCount
        #expect(count == 0)
    }
    
    // MARK: - Scanning Tests
    
    @Test("Scanning fails when Bluetooth off")
    func scanningFailsBluetoothOff() async {
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        do {
            try await manager.startScanning()
            Issue.record("Expected error")
        } catch {
            let state = await manager.connectionState
            #expect(state == .error)
        }
    }
    
    @Test("Start scanning changes state")
    func startScanningChangesState() async throws {
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        // Start scanning in background (will wait for devices)
        Task {
            try? await manager.startScanning()
        }
        
        // Give it time to start
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let state = await manager.connectionState
        #expect(state == .scanning)
    }
    
    @Test("Disconnect returns to idle")
    func disconnectReturnsToIdle() async throws {
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        // Start scanning
        Task {
            try? await manager.startScanning()
        }
        
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Disconnect
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    // MARK: - Libre2SensorInfo Tests
    
    @Test("Libre2SensorInfo stores values correctly")
    func sensorInfoStoresValues() {
        let info = Self.testSensorInfo
        
        #expect(info.sensorUID == Self.testSensorUID)
        #expect(info.patchInfo == Self.testPatchInfo)
        #expect(info.enableTime == Self.testEnableTime)
        #expect(info.serialNumber == "ABC123")
        #expect(info.sensorType == .libre2)
    }
    
    @Test("Libre2SensorInfo default sensor type is libre2")
    func sensorInfoDefaultType() {
        let info = Libre2SensorInfo(
            sensorUID: Self.testSensorUID,
            patchInfo: Self.testPatchInfo,
            enableTime: Self.testEnableTime
        )
        
        #expect(info.sensorType == .libre2)
    }
    
    // MARK: - Libre2ConnectionState Tests
    
    @Test("All connection states have raw values")
    func connectionStatesHaveRawValues() {
        let states: [Libre2ConnectionState] = [
            .idle, .scanning, .connecting, .unlocking, .streaming, .disconnecting, .error
        ]
        
        for state in states {
            #expect(!state.rawValue.isEmpty)
        }
    }
    
    // MARK: - Libre2SensorType Tests
    
    @Test("All sensor types have raw values")
    func sensorTypesHaveRawValues() {
        let types: [Libre2SensorType] = [.libre2, .libreUS14day, .libre3]
        
        for type in types {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    // MARK: - Libre2Error Tests
    
    @Test("Libre2Error is Error type")
    func libre2ErrorIsError() {
        let errors: [Libre2Error] = [
            .nfcRequired,
            .sensorNotActivated,
            .unlockFailed,
            .decryptionFailed,
            .invalidSensorInfo
        ]
        
        for error in errors {
            #expect(error is Error)
        }
    }
}

// MARK: - Protocol Logger Integration Tests (LIBRE-DIAG-001)

@Suite("Libre2Manager Protocol Logger Integration")
struct Libre2ManagerProtocolLoggerTests {
    
    static var testSensorInfo: Libre2SensorInfo {
        Libre2SensorInfo(
            sensorUID: Data([0x2f, 0xe7, 0xb1, 0x00, 0x00, 0xa4, 0x07, 0xe0]),
            patchInfo: Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25]),
            enableTime: 1000000,
            serialNumber: "ABC123",
            sensorType: .libre2
        )
    }
    
    @Test("Can initialize with protocol logger")
    func initWithProtocolLogger() async {
        let central = MockBLECentral()
        let logger = Libre2ProtocolLogger()
        
        let manager = Libre2Manager(
            sensorInfo: Self.testSensorInfo,
            central: central,
            protocolLogger: logger,
            allowSimulation: true
        )
        
        let currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger != nil)
    }
    
    @Test("Can set protocol logger after init")
    func setProtocolLoggerAfterInit() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        
        // Initially nil
        var currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger == nil)
        
        // Set logger
        let logger = Libre2ProtocolLogger()
        await manager.setProtocolLogger(logger)
        
        // Now set
        currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger != nil)
    }
    
    @Test("Protocol logger logs sensor type on set")
    func loggerLogsSensorTypeOnSet() async {
        let central = MockBLECentral()
        let manager = Libre2Manager(sensorInfo: Self.testSensorInfo, central: central, allowSimulation: true)
        let logger = Libre2ProtocolLogger()
        
        await manager.setProtocolLogger(logger)
        
        let entries = await logger.getAllEntries()
        // Should have at least one entry for sensor type
        #expect(entries.count >= 1)
        
        let sensorTypeEntry = entries.first { $0.event == .sensorTypeDetected }
        #expect(sensorTypeEntry != nil)
    }
    
    @Test("Protocol logger receives disconnect event")
    func loggerReceivesDisconnectEvent() async {
        let central = MockBLECentral()
        let logger = Libre2ProtocolLogger()
        let manager = Libre2Manager(
            sensorInfo: Self.testSensorInfo,
            central: central,
            protocolLogger: logger,
            allowSimulation: true
        )
        
        await manager.disconnect()
        
        let entries = await logger.getAllEntries()
        let disconnectEntry = entries.first { $0.event == .sensorDisconnected }
        #expect(disconnectEntry != nil)
    }
    
    @Test("Protocol logger can be cleared")
    func loggerCanBeCleared() async {
        let central = MockBLECentral()
        let logger = Libre2ProtocolLogger()
        let manager = Libre2Manager(
            sensorInfo: Self.testSensorInfo,
            central: central,
            protocolLogger: logger,
            allowSimulation: true
        )
        
        await manager.disconnect()
        
        var entries = await logger.getAllEntries()
        #expect(entries.count > 0)
        
        await logger.clear()
        entries = await logger.getAllEntries()
        #expect(entries.count == 0)
    }
    
    @Test("Protocol logger tracks sensor UID")
    func loggerTracksSensorUID() async {
        let central = MockBLECentral()
        let logger = Libre2ProtocolLogger()
        let manager = Libre2Manager(
            sensorInfo: Self.testSensorInfo,
            central: central,
            protocolLogger: logger,
            allowSimulation: true
        )
        
        await manager.setProtocolLogger(logger)
        
        let entries = await logger.getAllEntries()
        // Check entries have sensor UID
        let entryWithUID = entries.first { $0.sensorUID != nil }
        #expect(entryWithUID != nil)
    }
}
