// SPDX-License-Identifier: MIT
//
// DexcomG7ManagerTests.swift
// CGMKitTests
//
// Unit tests for Dexcom G7 Manager using MockBLE.
// Trace: PRD-008 REQ-BLE-008

import Testing
@testable import CGMKit
@testable import BLEKit
import T1PalCore

@Suite("DexcomG7ManagerTests", .serialized)
struct DexcomG7ManagerTests {
    
    // MARK: - Initialization Tests
    
    @Test("Manager initialization")
    func managerInitialization() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: mockCentral
        )
        
        let displayName = await manager.displayName
        let cgmType = await manager.cgmType
        let connectionState = await manager.connectionState
        let sensorSerial = await manager.sensorSerial
        
        #expect(displayName == "Dexcom G7")
        #expect(cgmType == .dexcomG7)
        #expect(connectionState == .idle)
        #expect(sensorSerial == "ABC1234567")
    }
    
    @Test("Manager initialization with invalid code")
    func managerInitializationWithInvalidCode() {
        let mockCentral = MockBLECentral()
        
        // Invalid sensor code (not 4 digits)
        #expect(throws: (any Error).self) {
            try DexcomG7Manager(
                sensorSerial: "ABC1234567",
                sensorCode: "123",  // Too short
                central: mockCentral
            )
        }
        
        #expect(throws: (any Error).self) {
            try DexcomG7Manager(
                sensorSerial: "ABC1234567",
                sensorCode: "ABCD",  // Not numeric
                central: mockCentral
            )
        }
    }
    
    // MARK: - Connection State Tests
    
    @Test("Connection state starts idle")
    func connectionStateStartsIdle() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "XYZ9876543",
            sensorCode: "5678",
            central: mockCentral
        )
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    @Test("Sensor state starts not started")
    func sensorStateStartsNotStarted() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "XYZ9876543",
            sensorCode: "5678",
            central: mockCentral
        )
        
        let state = await manager.sensorState
        #expect(state == .notStarted)
    }
    
    @Test("Latest reading is nil initially")
    func latestReadingIsNilInitially() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "XYZ9876543",
            sensorCode: "5678",
            central: mockCentral
        )
        
        let reading = await manager.latestReading
        #expect(reading == nil)
    }
    
    // MARK: - Scanning Tests
    
    @Test("Start scanning changes state")
    func startScanningChangesState() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "TEST123456",
            sensorCode: "9999",
            central: mockCentral,
            allowSimulation: true
        )
        
        try await manager.startScanning()
        
        // Small delay to let state change
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let state = await manager.connectionState
        #expect(state == .scanning)
    }
    
    @Test("Scanning fails when Bluetooth off")
    func scanningFailsWhenBluetoothOff() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOff)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "TEST123456",
            sensorCode: "9999",
            central: mockCentral,
            allowSimulation: true
        )
        
        do {
            try await manager.startScanning()
            Issue.record("Should throw bluetoothUnavailable")
        } catch CGMError.bluetoothUnavailable {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Disconnect Tests
    
    @Test("Disconnect returns to idle")
    func disconnectReturnsToIdle() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "TEST123456",
            sensorCode: "9999",
            central: mockCentral,
            allowSimulation: true
        )
        
        try await manager.startScanning()
        try await Task.sleep(nanoseconds: 50_000_000)
        
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    // MARK: - CGM Type Tests
    
    @Test("CGM type is Dexcom G7")
    func cgmTypeIsDexcomG7() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: mockCentral
        )
        
        let cgmType = await manager.cgmType
        #expect(cgmType == .dexcomG7)
    }
    
    // MARK: - Sensor Info Tests
    
    @Test("Sensor info is stored")
    func sensorInfoIsStored() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "SEN1234567",
            sensorCode: "4321",
            central: mockCentral
        )
        
        let sensorInfo = await manager.sensorInfo
        #expect(sensorInfo != nil)
        #expect(sensorInfo?.sensorSerial == "SEN1234567")
        #expect(sensorInfo?.sensorCode == "4321")
    }
    
    @Test("Sensor not expired initially")
    func sensorNotExpiredInitially() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "SEN1234567",
            sensorCode: "4321",
            central: mockCentral
        )
        
        let isExpired = await manager.isSensorExpired
        #expect(!isExpired)
    }
    
    // MARK: - Session Key Tests
    
    @Test("Session key is nil before auth")
    func sessionKeyIsNilBeforeAuth() async throws {
        let mockCentral = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: mockCentral
        )
        
        let sessionKey = await manager.getSessionKey()
        #expect(sessionKey == nil)
    }
}

// MARK: - Testing Framework Tests (CGM-031)

@Suite("G7ConnectionState Tests")
struct G7ConnectionStateTests {
    
    @Test("All connection states have raw values")
    func allStates() {
        let states: [G7ConnectionState] = [
            .idle, .scanning, .connecting, .pairing,
            .authenticating, .streaming,
            .disconnecting, .error, .passive
        ]
        
        #expect(states.count == 9)
        
        for state in states {
            #expect(!state.rawValue.isEmpty)
        }
    }
}

@Suite("Dexcom G7 Manager Config")
struct DexcomG7ManagerConfigTests {
    
    @Test("Default config uses direct mode")
    func defaultConfigMode() {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234"
        )
        
        #expect(config.connectionMode == .direct)
        #expect(config.passiveFallbackToHealthKit == true)
    }
    
    @Test("Config with passive mode")
    func passiveModeConfig() {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        
        #expect(config.connectionMode == .passiveBLE)
    }
    
    @Test("Config with HealthKit-only mode")
    func healthKitOnlyConfig() {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .healthKitObserver,
            allowSimulation: true
        )
        
        #expect(config.connectionMode == .healthKitObserver)
    }
}

@Suite("Dexcom G7 Passive Mode", .serialized)
struct DexcomG7PassiveModeTests {
    
    @Test("Manager with config stores connection mode")
    func managerWithConfig() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        let mode = await manager.connectionMode
        #expect(mode == .passiveBLE)
    }
    
    @Test("Passive mode enters passive state")
    func passiveModeState() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .passive)
        
        await manager.disconnect()
    }
    
    @Test("HealthKit-only mode enters passive state without BLE")
    func healthKitOnlyModeState() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .healthKitObserver,
            allowSimulation: true
        )
        let central = MockBLECentral()
        // Set BLE off - should still work
        await central.setState(.poweredOff)
        
        let manager = try DexcomG7Manager(config: config, central: central)
        
        // HealthKit-only mode doesn't need BLE
        try await manager.startScanning()
        
        let state = await manager.connectionState
        #expect(state == .passive)
        
        let sensor = await manager.sensorState
        #expect(sensor == .active)
    }
    
    @Test("Vendor connection callback can be set")
    func vendorConnectionCallback() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        await manager.setVendorCallback { _ in }
        
        // Verify callback is set
        let hasCallback = await manager.onVendorConnectionDetected != nil
        #expect(hasCallback)
    }
    
    @Test("Disconnect stops passive scanner")
    func disconnectStopsPassive() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    @Test("Passive mode skips authenticator creation")
    func passiveModeSkipsAuth() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        // In passive mode, we don't need authentication
        let sessionKey = await manager.getSessionKey()
        #expect(sessionKey == nil)
    }
}

// MARK: - Protocol Logger Integration Tests (G7-DIAG-004)

@Suite("G7 Protocol Logger Integration", .serialized)
struct G7ProtocolLoggerIntegrationTests {
    
    @Test("Manager can be initialized with protocol logger")
    func initWithLogger() async throws {
        let central = MockBLECentral()
        let logger = G7ProtocolLogger(minimumLevel: .debug)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central,
            protocolLogger: logger
        )
        
        let currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger != nil)
    }
    
    @Test("Protocol logger can be set after init")
    func setLoggerAfterInit() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        // Initially no logger
        let initialLogger = await manager.currentProtocolLogger
        #expect(initialLogger == nil)
        
        // Set logger
        let logger = G7ProtocolLogger(minimumLevel: .debug)
        await manager.setProtocolLogger(logger)
        
        let newLogger = await manager.currentProtocolLogger
        #expect(newLogger != nil)
    }
    
    @Test("Session context is nil without logger")
    func noSessionContextWithoutLogger() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        let context = await manager.getSessionContext()
        #expect(context == nil)
    }
    
    @Test("Session state is nil without logger")
    func noSessionStateWithoutLogger() async throws {
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central
        )
        
        let state = await manager.getCurrentSessionState()
        #expect(state == nil)
    }
    
    @Test("Manager with config accepts protocol logger")
    func configWithLogger() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .direct,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let logger = G7ProtocolLogger(minimumLevel: .trace)
        
        let manager = try DexcomG7Manager(
            config: config,
            central: central,
            protocolLogger: logger
        )
        
        let currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger != nil)
    }
    
    @Test("Logger can be cleared")
    func clearLogger() async throws {
        let central = MockBLECentral()
        let logger = G7ProtocolLogger(minimumLevel: .debug)
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            central: central,
            protocolLogger: logger
        )
        
        // Clear logger
        await manager.setProtocolLogger(nil)
        
        let currentLogger = await manager.currentProtocolLogger
        #expect(currentLogger == nil)
    }
}

// MARK: - Coexistence Mode Tests (G7-COEX-007)

@Suite("Dexcom G7 Coexistence Mode", .serialized)
struct DexcomG7CoexistenceModeTests {
    
    @Test("Config with coexistence mode")
    func coexistenceModeConfig() {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .coexistence,
            allowSimulation: true
        )
        
        #expect(config.connectionMode == .coexistence)
    }
    
    @Test("Manager stores coexistence mode from config")
    func managerWithCoexistenceConfig() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        let mode = await manager.connectionMode
        #expect(mode == .coexistence)
    }
    
    @Test("Coexistence mode does not create authenticator")
    func coexistenceSkipsAuthenticator() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = try DexcomG7Manager(config: config, central: central)
        
        // Coexistence mode shouldn't need the authenticator - it observes vendor auth
        // Session key should be nil since we don't authenticate ourselves
        let sessionKey = await manager.getSessionKey()
        #expect(sessionKey == nil)
    }
    
    @Test("Coexistence mode starts scanning on startScanning()")
    func coexistenceStartsScanning() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let manager = try DexcomG7Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .scanning)
        
        await manager.disconnect()
    }
    
    @Test("Coexistence mode requires Bluetooth powered on")
    func coexistenceRequiresBluetooth() async throws {
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABC1234567",
            sensorCode: "1234",
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let manager = try DexcomG7Manager(config: config, central: central)
        
        do {
            try await manager.startScanning()
            Issue.record("Should throw bluetoothUnavailable")
        } catch CGMError.bluetoothUnavailable {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("CGMConnectionMode has coexistence case")
    func connectionModeHasCoexistence() {
        let mode = CGMConnectionMode.coexistence
        #expect(mode.rawValue == "coexistence")
    }
}
