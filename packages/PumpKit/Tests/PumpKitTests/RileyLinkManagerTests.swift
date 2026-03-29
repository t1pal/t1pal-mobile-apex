// SPDX-License-Identifier: MIT
//
// RileyLinkManagerTests.swift
// PumpKitTests
//
// Tests for RileyLink connection manager
// Trace: PUMP-MDT-005

import Testing
import Foundation
@testable import PumpKit
@testable import BLEKit

@Suite("RileyLinkManager Tests", .serialized)
struct RileyLinkManagerTests {
    
    // MARK: - Device Type Detection
    
    @Test("Device type detection from name")
    func deviceTypeFromName() async throws {
        #expect(RileyLinkDeviceType.from(name: "OrangeLink-ABCD") == .orangeLink)
        #expect(RileyLinkDeviceType.from(name: "RileyLink-1234") == .rileyLink)
        #expect(RileyLinkDeviceType.from(name: "EmaLink-TEST") == .emaLink)
        #expect(RileyLinkDeviceType.from(name: "Unknown Device") == .unknown)
    }
    
    // MARK: - Initial State
    
    @Test("Initial state is disconnected")
    func initialState() async throws {
        let manager = RileyLinkManager()
        let state = await manager.state
        let device = await manager.connectedDevice
        
        #expect(state == .disconnected)
        #expect(device == nil)
    }
    
    // MARK: - Scanning
    
    @Test("Start scanning changes state")
    func startScanning() async throws {
        let mockCentral = MockBLECentral()
        let manager = RileyLinkManager(central: mockCentral, allowSimulation: true)
        
        await manager.startScanning()
        let state = await manager.state
        
        #expect(state == .scanning)
        
        await manager.stopScanning()
    }
    
    @Test("Stop scanning returns to disconnected")
    func stopScanning() async throws {
        let mockCentral = MockBLECentral()
        let manager = RileyLinkManager(central: mockCentral, allowSimulation: true)
        
        await manager.startScanning()
        await manager.stopScanning()
        
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Scan discovers devices")
    func scanDiscovery() async throws {
        // Create mock central with simulated RileyLink device
        let mockCentral = MockBLECentral()
        let mockDevice = BLEPeripheralInfo(
            identifier: BLEUUID(string: "12345678-1234-1234-1234-123456789ABC")!,
            name: "OrangeLink-TEST"
        )
        let mockResult = BLEScanResult(
            peripheral: mockDevice,
            rssi: -50,
            advertisement: BLEAdvertisement(
                localName: "OrangeLink-TEST",
                serviceUUIDs: [.rileyLinkService],
                manufacturerData: nil,
                isConnectable: true
            )
        )
        await mockCentral.addScanResult(mockResult)
        
        let manager = RileyLinkManager(central: mockCentral, allowSimulation: true)
        
        await manager.startScanning()
        
        // Wait for simulated discovery
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let devices = await manager.discoveredDevices
        #expect(devices.count > 0)
        
        // Check simulated device
        if let device = devices.first {
            #expect(device.deviceType == .orangeLink)
            #expect(device.name.contains("OrangeLink"))
        }
        
        await manager.stopScanning()
    }
    
    // MARK: - Connection
    
    @Test("Connect to device")
    func connectToDevice() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        
        let state = await manager.state
        let connected = await manager.connectedDevice
        
        #expect(state == .connected)
        #expect(connected != nil)
        #expect(connected?.id == device.id)
        
        await manager.disconnect()
    }
    
    @Test("Disconnect from device")
    func disconnectFromDevice() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        await manager.disconnect()
        
        let state = await manager.state
        let connected = await manager.connectedDevice
        
        #expect(state == .disconnected)
        #expect(connected == nil)
    }
    
    // MARK: - RF Tuning
    
    @Test("Tune frequency")
    func tuneFrequency() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        try await manager.tune(to: MedtronicRFConstants.frequencyNA)
        
        let state = await manager.state
        let freq = await manager.currentFrequency
        
        #expect(state == .ready)
        #expect(freq == MedtronicRFConstants.frequencyNA)
        
        await manager.disconnect()
    }
    
    // MARK: - Command Send
    
    @Test("Send command")
    func sendCommand() async throws {
        let manager = RileyLinkManager()
        
        // WIRE-011: Enable test mode for instant responses (no delays)
        await manager.enableTestMode()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        try await manager.tune(to: MedtronicRFConstants.frequencyNA)
        
        let command = Data([0xA7, 0x01, 0x02, 0x03])
        let response = try await manager.sendCommand(command)
        
        #expect(response.count > 0)
        #expect(response[0] == 0x06) // ACK
        
        await manager.disconnect()
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostic info")
    func diagnostics() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        
        let diagnostics = await manager.diagnosticInfo()
        
        #expect(diagnostics.state == .connected)
        #expect(diagnostics.connectedDevice != nil)
        #expect(diagnostics.description.contains("OrangeLink"))
        
        await manager.disconnect()
    }
    
    // MARK: - Error Handling
    
    @Test("Not connected error")
    func notConnectedError() async throws {
        let manager = RileyLinkManager()
        
        do {
            try await manager.tune(to: 916.5)
            Issue.record("Should throw notConnected error")
        } catch let error as RileyLinkError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Already connected error")
    func alreadyConnectedError() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        try await manager.connect(to: device)
        
        do {
            try await manager.connect(to: device)
            Issue.record("Should throw alreadyConnected error")
        } catch let error as RileyLinkError {
            #expect(error == .alreadyConnected)
        }
        
        await manager.disconnect()
    }
    
    // MARK: - RF Constants
    
    @Test("RF constants values")
    func rfConstants() throws {
        // Verify frequency constants
        #expect(MedtronicRFConstants.frequencyNA == 916.5)
        #expect(MedtronicRFConstants.frequencyWW == 868.35)
        
        // Verify CRC polynomial (0x9B, NOT 0x31 - fixed in EXT-MDT-004)
        // Source: externals/MinimedKit/MinimedKit/Radio/CRC8.swift:11
        #expect(MedtronicRFConstants.crcPolynomial == 0x9B)
        
        // Test CRC calculation
        let testData = Data([0xA7, 0x01, 0x02, 0x03])
        let crc = MedtronicRFConstants.crc8(testData)
        #expect(crc > 0)
        
        // CRC should be deterministic
        let crc2 = MedtronicRFConstants.crc8(testData)
        #expect(crc == crc2)
    }
    
    // MARK: - Variant Registry
    
    @Test("Variant registry contains all variants")
    func variantRegistry() throws {
        // All predefined variants should be in registry (14 with 551/751 added in EXT-MDT-005)
        let allVariants = MedtronicVariantRegistry.allVariants
        #expect(allVariants.count == 14)
        
        // Test lookup by model number (returns first match)
        let variant522 = MedtronicVariantRegistry.variant(forModel: "522")
        #expect(variant522 != nil)
        #expect(variant522?.generation == .paradigm)
        
        let variant722 = MedtronicVariantRegistry.variant(forModel: "722")
        #expect(variant722 != nil)
        #expect(variant722?.generation == .paradigm)
        
        // Test supported variants (non-encrypted)
        let supported = MedtronicVariantRegistry.supportedVariants
        #expect(supported.count > 0)
        #expect(supported.allSatisfy { $0.isSupported })
    }
    
    // MARK: - Device Equality
    
    @Test("Device equality comparison")
    func deviceEquality() throws {
        let device1 = RileyLinkDevice(id: "001", name: "OrangeLink-A", rssi: -60, deviceType: .orangeLink)
        let device2 = RileyLinkDevice(id: "001", name: "OrangeLink-A", rssi: -60, deviceType: .orangeLink)
        let device3 = RileyLinkDevice(id: "002", name: "OrangeLink-B", rssi: -60, deviceType: .orangeLink)
        
        // Devices with same fields should be equal
        #expect(device1.id == device2.id)
        #expect(device1.name == device2.name)
        
        // Devices with different id should not be equal
        #expect(device1 != device3)
        #expect(device1.id != device3.id)
    }
    
    // MARK: - Background Thread Init (ARCH-006)
    
    /// Regression test for RL-WIRE-008: Ensure singleton can be accessed from background queue
    /// without causing CBCentralManager assertion failures.
    ///
    /// Note: The actual main-thread assertion only fires on iOS with real CoreBluetooth.
    /// This test verifies the pattern works correctly - the actor isolates access properly.
    @Test("Singleton access from background queue")
    func singletonAccessFromBackgroundQueue() async throws {
        // Reset singleton state for test isolation
        await RileyLinkManager.shared.disconnect()
        
        // Wait for disconnect to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // Access the shared singleton from a background task
        // This exercises the code path that caused RL-WIRE-008
        let state = await Task.detached {
            await RileyLinkManager.shared.state
        }.value
        
        // Should successfully return the disconnected state
        #expect(state == .disconnected)
    }
    
    /// Verify multiple concurrent accesses to singleton don't cause issues
    @Test("Concurrent singleton access")
    func concurrentSingletonAccess() async throws {
        // Reset singleton state for test isolation
        await RileyLinkManager.shared.disconnect()
        
        // Wait for disconnect to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // Launch multiple concurrent tasks accessing the singleton
        async let state1 = Task.detached { await RileyLinkManager.shared.state }.value
        async let state2 = Task.detached { await RileyLinkManager.shared.state }.value
        async let state3 = Task.detached { await RileyLinkManager.shared.state }.value
        
        let (s1, s2, s3) = await (state1, state2, state3)
        
        // All should return consistent disconnected state
        #expect(s1 == .disconnected)
        #expect(s2 == .disconnected)
        #expect(s3 == .disconnected)
    }
    
    // MARK: - NUS Mode (PROTO-RL-001)
    
    @Test("NUS mode initially false")
    func nusModePropertyInitiallyFalse() async throws {
        let manager = RileyLinkManager()
        let isNUS = await manager.isUsingNUSMode
        #expect(!isNUS, "NUS mode should be false initially")
    }
    
    // MARK: - Signal Quality (PROTO-RL-002)
    
    @Test("Signal quality symbol names")
    func signalQualityFromRSSI() {
        // Test RSSI to SignalQuality mapping
        #expect(SignalQuality.excellent.symbolName == "wifi.circle.fill")
        #expect(SignalQuality.good.symbolName == "wifi.circle")
        #expect(SignalQuality.fair.symbolName == "wifi")
        #expect(SignalQuality.weak.symbolName == "wifi.exclamationmark")
        #expect(SignalQuality.poor.symbolName == "wifi.slash")
        #expect(SignalQuality.unknown.symbolName == "questionmark.circle")
    }
    
    @Test("Signal quality initially unknown")
    func signalQualityInitiallyUnknown() async throws {
        let manager = RileyLinkManager()
        let quality = await manager.signalQuality
        #expect(quality == .unknown, "Signal quality should be unknown initially")
    }
}

// MARK: - Test Helpers

func expectContains(_ string: String, _ substring: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
    #expect(string.contains(substring), "Expected \"\(string)\" to contain \"\(substring)\"", sourceLocation: sourceLocation)
}
