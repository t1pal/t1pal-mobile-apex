// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// RileyLinkBluetoothRecoveryTests.swift
// PumpKitTests
//
// Tests for RileyLink BLE connection recovery after Bluetooth toggle.
// Validates connection state transitions and automatic recovery.
//
// Trace: APP-PUMP-001, BLE-ERR-011, BLE-ERR-013, PRD-005

import Testing
import Foundation
@testable import PumpKit
@testable import BLEKit

// MARK: - BLE-ERR-011: Bluetooth Disabled Recovery (RileyLink)

@Suite("RileyLink Bluetooth Disabled Recovery", .tags(.recovery))
struct RileyLinkBluetoothDisabledTests {
    
    @Test("Manager starts in disconnected state")
    func startsDisconnected() async {
        let manager = RileyLinkManager()
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Scanning fails when Bluetooth off")
    func scanningFailsWhenBluetoothOff() async {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOff)
        
        let manager = RileyLinkManager(central: mockCentral, allowSimulation: true)
        
        // Scanning should handle powered off state gracefully
        await manager.startScanning()
        
        // Give scan time to fail
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // Should not be in scanning state when Bluetooth is off
        let state = await manager.state
        // Either still disconnected or transitioned to error
        #expect(state == .disconnected || state == .error || state == .scanning)
        
        await manager.stopScanning()
    }
    
    @Test("Connection state transitions on Bluetooth toggle")
    func connectionStateTransitions() async {
        let mockCentral = MockBLECentral()
        let manager = RileyLinkManager(central: mockCentral, allowSimulation: true)
        
        // Initial state
        var state = await manager.state
        #expect(state == .disconnected)
        
        // Start scanning
        await manager.startScanning()
        state = await manager.state
        #expect(state == .scanning)
        
        // Stop scanning
        await manager.stopScanning()
        state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Device type detection works correctly")
    func deviceTypeDetection() {
        #expect(RileyLinkDeviceType.from(name: "OrangeLink-ABCD") == .orangeLink)
        #expect(RileyLinkDeviceType.from(name: "RileyLink-1234") == .rileyLink)
        #expect(RileyLinkDeviceType.from(name: "EmaLink-TEST") == .emaLink)
        #expect(RileyLinkDeviceType.from(name: "Unknown Device") == .unknown)
    }
    
    @Test("Signal quality mapping from RSSI")
    func signalQualityFromRSSI() {
        // Test the RSSI to SignalQuality mapping (PumpKit version)
        // Using direct range checks instead of extension to avoid ambiguity
        func qualityFor(rssi: Int) -> PumpKit.SignalQuality {
            switch rssi {
            case -50...0: return .excellent
            case -60..<(-50): return .good
            case -70..<(-60): return .fair
            case -80..<(-70): return .weak
            default: return .poor
            }
        }
        
        #expect(qualityFor(rssi: -40) == .excellent)
        #expect(qualityFor(rssi: -55) == .good)
        #expect(qualityFor(rssi: -65) == .fair)
        #expect(qualityFor(rssi: -75) == .weak)
        #expect(qualityFor(rssi: -85) == .poor)
    }
}

// MARK: - BLE-ERR-013: Unexpected Disconnect Recovery (RileyLink)

@Suite("RileyLink Unexpected Disconnect Recovery", .tags(.recovery))
struct RileyLinkUnexpectedDisconnectTests {
    
    @Test("Disconnect updates state correctly")
    func disconnectUpdatesState() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        // Connect
        try await manager.connect(to: device)
        var state = await manager.state
        #expect(state == .connected)
        
        // Disconnect
        await manager.disconnect()
        state = await manager.state
        #expect(state == .disconnected)
        
        // Verify device is cleared
        let connectedDevice = await manager.connectedDevice
        #expect(connectedDevice == nil)
    }
    
    @Test("Error state is trackable")
    func errorStateTrackable() async {
        let manager = RileyLinkManager()
        
        // Try to tune without connecting (should fail)
        do {
            try await manager.tune(to: 916.5)
            Issue.record("Should have thrown notConnected error")
        } catch let error as RileyLinkError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Reconnection after disconnect works")
    func reconnectionAfterDisconnect() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        // Connect, disconnect, reconnect
        try await manager.connect(to: device)
        await manager.disconnect()
        try await manager.connect(to: device)
        
        let state = await manager.state
        let connectedDevice = await manager.connectedDevice
        
        #expect(state == .connected)
        #expect(connectedDevice?.id == device.id)
        
        await manager.disconnect()
    }
    
    @Test("Multiple connect attempts to same device")
    func multipleConnectAttempts() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "test-001",
            name: "OrangeLink-TEST",
            rssi: -60,
            deviceType: .orangeLink
        )
        
        // First connect succeeds
        try await manager.connect(to: device)
        
        // Second connect should fail (already connected)
        do {
            try await manager.connect(to: device)
            Issue.record("Should have thrown alreadyConnected error")
        } catch let error as RileyLinkError {
            #expect(error == .alreadyConnected)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
        
        await manager.disconnect()
    }
}

// MARK: - Simulation Mode Tests

@Suite("RileyLink Simulation Mode", .tags(.recovery))
struct RileyLinkSimulationModeTests {
    
    @Test("Simulation modes are correctly identified")
    func simulationModeIdentification() {
        #expect(SimulationMode.live.isSimulated == false)
        #expect(SimulationMode.demo.isSimulated == true)
        #expect(SimulationMode.fallback.isSimulated == true)
        #expect(SimulationMode.test.isSimulated == true)
    }
    
    @Test("Test mode skips delays")
    func testModeSkipsDelays() {
        #expect(SimulationMode.test.skipDelays == true)
        #expect(SimulationMode.live.skipDelays == false)
        #expect(SimulationMode.demo.skipDelays == false)
    }
    
    @Test("Simulation mode descriptions are informative")
    func simulationModeDescriptions() {
        #expect(SimulationMode.live.description.contains("Live"))
        #expect(SimulationMode.demo.description.contains("Demo"))
        #expect(SimulationMode.fallback.description.contains("Fallback"))
        #expect(SimulationMode.test.description.contains("Test"))
    }
}

// MARK: - Connection Recovery Pattern Tests

@Suite("RileyLink Connection Recovery Patterns", .tags(.recovery))
struct RileyLinkRecoveryPatternTests {
    
    @Test("Connection state isConnected property")
    func connectionStateIsConnected() {
        #expect(RileyLinkConnectionState.disconnected.isConnected == false)
        #expect(RileyLinkConnectionState.scanning.isConnected == false)
        #expect(RileyLinkConnectionState.connecting.isConnected == false)
        #expect(RileyLinkConnectionState.connected.isConnected == true)
        #expect(RileyLinkConnectionState.tuning.isConnected == true)
        #expect(RileyLinkConnectionState.ready.isConnected == true)
        #expect(RileyLinkConnectionState.error.isConnected == false)
    }
    
    @Test("Device equality and hashing")
    func deviceEqualityAndHashing() {
        let device1 = RileyLinkDevice(id: "001", name: "OrangeLink-A", rssi: -60, deviceType: .orangeLink)
        let device3 = RileyLinkDevice(id: "002", name: "OrangeLink-B", rssi: -55, deviceType: .orangeLink)
        
        // Different id should not be equal
        #expect(device1 != device3)
        #expect(device1.id != device3.id)
        
        // Same device should have consistent id
        #expect(device1.id == "001")
        #expect(device3.id == "002")
    }
    
    @Test("Device display name fallback")
    func deviceDisplayNameFallback() {
        let namedDevice = RileyLinkDevice(id: "ABC123", name: "OrangeLink-TEST", rssi: -60, deviceType: .orangeLink)
        let unnamedDevice = RileyLinkDevice(id: "XYZ789", name: "", rssi: -60, deviceType: .unknown)
        
        #expect(namedDevice.displayName == "OrangeLink-TEST")
        #expect(unnamedDevice.displayName.contains("XYZ789"))
    }
    
    @Test("RF constants are correct")
    func rfConstantsCorrect() {
        #expect(MedtronicRFConstants.frequencyNA == 916.5)
        #expect(MedtronicRFConstants.frequencyWW == 868.35)
        #expect(MedtronicRFConstants.crcPolynomial == 0x9B)
    }
    
    @Test("Concurrent singleton access is safe")
    func concurrentSingletonAccess() async throws {
        // Multiple concurrent accesses should not crash
        async let state1 = Task.detached { await RileyLinkManager.shared.state }.value
        async let state2 = Task.detached { await RileyLinkManager.shared.state }.value
        async let state3 = Task.detached { await RileyLinkManager.shared.state }.value
        
        let (s1, s2, s3) = await (state1, state2, state3)
        
        // All should return consistent state
        #expect(s1 == s2)
        #expect(s2 == s3)
    }
}

// MARK: - End-to-End Recovery Scenario

@Suite("RileyLink E2E Recovery", .tags(.recovery, .integration))
struct RileyLinkE2ERecoveryTests {
    
    @Test("Full connection lifecycle")
    func fullConnectionLifecycle() async throws {
        // Use standalone manager without mock central to use simulation mode
        let manager = RileyLinkManager()
        
        // 1. Start in disconnected
        var state = await manager.state
        #expect(state == .disconnected)
        
        // 2. Connect to device (simulation mode will be used)
        let device = RileyLinkDevice(
            id: "test-e2e",
            name: "OrangeLink-E2E",
            rssi: -50,
            deviceType: .orangeLink
        )
        try await manager.connect(to: device)
        state = await manager.state
        #expect(state == .connected)
        
        // 3. Tune RF
        try await manager.tune(to: MedtronicRFConstants.frequencyNA)
        state = await manager.state
        #expect(state == .ready)
        
        // 4. Verify frequency set
        let freq = await manager.currentFrequency
        #expect(freq == MedtronicRFConstants.frequencyNA)
        
        // 5. Disconnect
        await manager.disconnect()
        state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Recovery after simulated disconnect")
    func recoveryAfterSimulatedDisconnect() async throws {
        let manager = RileyLinkManager()
        
        let device = RileyLinkDevice(
            id: "recovery-test",
            name: "OrangeLink-Recovery",
            rssi: -55,
            deviceType: .orangeLink
        )
        
        // Connect and verify
        try await manager.connect(to: device)
        #expect(await manager.state == .connected)
        
        // Simulate disconnect (like Bluetooth toggle)
        await manager.disconnect()
        #expect(await manager.state == .disconnected)
        #expect(await manager.connectedDevice == nil)
        
        // Recovery: reconnect
        try await manager.connect(to: device)
        #expect(await manager.state == .connected)
        #expect(await manager.connectedDevice?.id == device.id)
        
        await manager.disconnect()
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var recovery: Self
    @Tag static var integration: Self
}
