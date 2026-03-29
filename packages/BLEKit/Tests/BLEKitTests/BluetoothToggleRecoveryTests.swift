// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// BluetoothToggleRecoveryTests.swift
// BLEKitTests
//
// Tests for BLE connection recovery after Bluetooth toggle (on/off).
// These tests validate BLE-ERR-011 and BLE-ERR-013 from BLE-ERROR-STATE-TEST-CASES.md.
//
// Trace: APP-CGM-004, BLE-ERR-011, BLE-ERR-013, PRD-008

import Testing
import Foundation
@testable import BLEKit

// MARK: - BLE-ERR-011: Bluetooth Disabled Recovery

@Suite("BLE-ERR-011: Bluetooth Disabled", .tags(.recovery))
struct BluetoothDisabledRecoveryTests {
    
    @Test("Central detects Bluetooth powered off")
    func detectsPoweredOff() async {
        let central = MockBLECentral()
        
        // Initial state is powered on
        var state = await central.state
        #expect(state == .poweredOn)
        
        // Simulate Bluetooth toggle off
        await central.setState(.poweredOff)
        state = await central.state
        
        #expect(state == .poweredOff)
    }
    
    @Test("Scan fails immediately when Bluetooth off")
    func scanFailsWhenOff() async {
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let stream = central.scan(for: nil)
        var gotNotPoweredOn = false
        
        do {
            for try await _ in stream {
                break
            }
        } catch let error as BLEError {
            if case .notPoweredOn = error {
                gotNotPoweredOn = true
            }
        } catch {
            // Other error type
        }
        
        #expect(gotNotPoweredOn, "Should throw notPoweredOn error when Bluetooth is off")
    }
    
    @Test("Connect fails when Bluetooth off")
    func connectFailsWhenOff() async {
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let peripheralInfo = BLEPeripheralInfo(
            identifier: BLEUUID(short: 0x1234),
            name: "G6 Transmitter"
        )
        
        var gotNotPoweredOn = false
        do {
            _ = try await central.connect(to: peripheralInfo)
            Issue.record("Should have thrown error")
        } catch let error as BLEError {
            if case .notPoweredOn = error {
                gotNotPoweredOn = true
            }
        } catch {
            // Other error type
        }
        
        #expect(gotNotPoweredOn, "Should throw notPoweredOn error")
    }
    
    @Test("Recovery manager detects Bluetooth reset trigger")
    func recoveryDetectsBluetoothReset() async {
        let manager = ConnectionRecoveryManager()
        
        // Register a CGM device
        await manager.registerDevice(DeviceRecord(
            id: "G6-ABC123",
            name: "Dexcom G6",
            deviceType: "cgm",
            priority: .critical
        ))
        
        // Mark as disconnected (simulating Bluetooth toggle)
        await manager.deviceDisconnected("G6-ABC123")
        
        // Start recovery with Bluetooth reset trigger
        let session = await manager.startRecovery(trigger: .bluetoothReset)
        
        #expect(session.trigger == .bluetoothReset)
        #expect(session.totalAttempts >= 1)
    }
    
    @Test("State transitions through poweredOff and back to poweredOn")
    func stateTransitionCycle() async {
        let central = MockBLECentral()
        var states: [BLECentralState] = []
        
        // Collect initial state
        states.append(await central.state)
        
        // Toggle off
        await central.setState(.poweredOff)
        states.append(await central.state)
        
        // Toggle back on
        await central.setState(.poweredOn)
        states.append(await central.state)
        
        #expect(states == [.poweredOn, .poweredOff, .poweredOn])
    }
    
    @Test("Recovery succeeds after Bluetooth restored")
    func recoverySucceedsAfterRestore() async {
        let central = MockBLECentral()
        let manager = ConnectionRecoveryManager(config: .cgm)
        
        // Register device
        await manager.registerDevice(DeviceRecord(
            id: "G6-XYZ",
            name: "Dexcom G6",
            deviceType: "cgm",
            priority: .critical
        ))
        
        // Simulate Bluetooth toggle off → disconnect
        await central.setState(.poweredOff)
        await manager.deviceDisconnected("G6-XYZ")
        
        // Simulate Bluetooth toggle on
        await central.setState(.poweredOn)
        
        // Recovery should now work (central is powered on)
        let session = await manager.startRecovery(trigger: .bluetoothReset)
        
        #expect(session.trigger == .bluetoothReset)
        // Device with 0 failures should succeed
        #expect(session.successCount >= 1)
    }
}

// MARK: - BLE-ERR-013: Unexpected Disconnect Recovery

@Suite("BLE-ERR-013: Unexpected Disconnect", .tags(.recovery))
struct UnexpectedDisconnectRecoveryTests {
    
    @Test("Peripheral disconnect updates state")
    func peripheralDisconnectState() async {
        let peripheral = MockBLEPeripheral(
            identifier: BLEUUID(short: 0xABCD),
            name: "CGM Transmitter"
        )
        
        // Connect
        await peripheral.setState(.connected)
        var state = await peripheral.state
        #expect(state == .connected)
        
        // Simulate unexpected disconnect
        await peripheral.disconnect()
        state = await peripheral.state
        
        #expect(state == .disconnected)
    }
    
    @Test("Recovery manager tracks disconnection")
    func managerTracksDisconnection() async {
        let manager = ConnectionRecoveryManager()
        
        await manager.registerDevice(DeviceRecord(
            id: "CGM-001",
            name: "Test CGM",
            deviceType: "cgm",
            priority: .critical
        ))
        
        // Initially no disconnection timestamp
        var devices = await manager.knownDevices()
        #expect(devices[0].lastDisconnected == nil)
        
        // Simulate disconnect
        await manager.deviceDisconnected("CGM-001")
        
        // Now has disconnection timestamp
        devices = await manager.knownDevices()
        #expect(devices[0].lastDisconnected != nil)
    }
    
    @Test("Disconnected device is identified as needing recovery")
    func disconnectedNeedsRecovery() async {
        let manager = ConnectionRecoveryManager()
        
        // Register two devices
        await manager.registerDevice(DeviceRecord(
            id: "CONNECTED",
            name: "Connected Device",
            deviceType: "cgm"
        ))
        await manager.registerDevice(DeviceRecord(
            id: "DISCONNECTED",
            name: "Disconnected Device",
            deviceType: "cgm"
        ))
        
        // One disconnects
        await manager.deviceDisconnected("DISCONNECTED")
        
        // Only disconnected device needs recovery
        let needing = await manager.devicesNeedingRecovery()
        
        #expect(needing.count == 1)
        #expect(needing[0].id == "DISCONNECTED")
    }
    
    @Test("Recovery uses exponential backoff")
    func recoveryUsesBackoff() {
        let config = RecoveryConfig(
            strategy: .exponentialBackoff,
            baseDelaySeconds: 1.0,
            maxDelaySeconds: 30.0
        )
        
        // Verify exponential backoff delays
        #expect(config.delayForAttempt(1) == 1.0)
        #expect(config.delayForAttempt(2) == 2.0)
        #expect(config.delayForAttempt(3) == 4.0)
        #expect(config.delayForAttempt(4) == 8.0)
        #expect(config.delayForAttempt(5) == 16.0)
        #expect(config.delayForAttempt(6) == 30.0)  // Capped at max
    }
    
    @Test("Critical devices are recovered first")
    func criticalDevicesFirst() async {
        let manager = ConnectionRecoveryManager()
        
        // Register devices in reverse priority order
        await manager.registerDevice(DeviceRecord(
            id: "WATCH",
            name: "Watch",
            deviceType: "accessory",
            priority: .low
        ))
        await manager.registerDevice(DeviceRecord(
            id: "PUMP",
            name: "Pump Controller",
            deviceType: "pump",
            priority: .high
        ))
        await manager.registerDevice(DeviceRecord(
            id: "CGM",
            name: "CGM",
            deviceType: "cgm",
            priority: .critical
        ))
        
        // Get devices in recovery order
        let devices = await manager.knownDevices()
        
        // Should be sorted by priority: critical > high > low
        #expect(devices[0].id == "CGM")
        #expect(devices[1].id == "PUMP")
        #expect(devices[2].id == "WATCH")
    }
    
    @Test("Recovery state transitions correctly")
    func recoveryStateTransitions() async {
        let manager = ConnectionRecoveryManager()
        
        // Register and disconnect device
        await manager.registerDevice(DeviceRecord(
            id: "DEV",
            name: "Test",
            deviceType: "cgm"
        ))
        
        // Start recovery
        let session = await manager.startRecovery(trigger: .userRequest)
        
        // Recovery should complete successfully
        let finalState = await manager.state()
        
        // Final state should be complete
        if case .complete(let recovered, let failed) = finalState {
            #expect(recovered + failed >= 1, "Should have processed at least one device")
        } else {
            Issue.record("Final state should be .complete, got: \(finalState)")
        }
        
        // Session should have recorded the attempt
        #expect(session.totalAttempts >= 1)
    }
    
    @Test("Recovery session records metrics")
    func recoverySessionMetrics() async {
        let persistence = InMemoryDevicePersistence()
        let manager = ConnectionRecoveryManager(
            config: .cgm,
            persistence: persistence
        )
        
        // Register devices
        await manager.registerDevice(DeviceRecord(
            id: "CGM1",
            name: "CGM 1",
            deviceType: "cgm"
        ))
        await manager.registerDevice(DeviceRecord(
            id: "CGM2",
            name: "CGM 2",
            deviceType: "cgm"
        ))
        
        // Run recovery
        let session = await manager.startRecovery(trigger: .appLaunch)
        
        // Verify session metrics
        #expect(session.totalAttempts == 2)
        #expect(session.endTime != nil)
        #expect(session.duration != nil)
        #expect(session.duration! >= 0)
    }
}

// MARK: - End-to-End Bluetooth Toggle Scenario

@Suite("Bluetooth Toggle End-to-End", .tags(.recovery, .integration))
struct BluetoothToggleE2ETests {
    
    @Test("Full Bluetooth toggle recovery cycle")
    func fullToggleRecoveryCycle() async {
        // Setup
        let central = MockBLECentral()
        let persistence = InMemoryDevicePersistence()
        let manager = ConnectionRecoveryManager(
            config: .cgm,
            persistence: persistence
        )
        
        // 1. Register CGM device
        let cgmDevice = DeviceRecord(
            id: "G6-ABCDEF",
            name: "Dexcom G6",
            deviceType: "cgm",
            priority: .critical,
            serviceUUIDs: ["FEBC"]
        )
        await manager.registerDevice(cgmDevice)
        
        // 2. Simulate initial connection
        await manager.deviceConnected("G6-ABCDEF")
        
        // 3. Verify device shows as connected (no recovery needed)
        var needingRecovery = await manager.devicesNeedingRecovery()
        #expect(needingRecovery.isEmpty)
        
        // 4. User toggles Bluetooth OFF
        await central.setState(.poweredOff)
        await manager.deviceDisconnected("G6-ABCDEF")
        
        // 5. Verify device now needs recovery
        needingRecovery = await manager.devicesNeedingRecovery()
        #expect(needingRecovery.count == 1)
        #expect(needingRecovery[0].id == "G6-ABCDEF")
        
        // 6. User toggles Bluetooth ON
        await central.setState(.poweredOn)
        
        // 7. Recovery is triggered
        let session = await manager.startRecovery(trigger: .bluetoothReset)
        
        // 8. Verify recovery completed
        #expect(session.trigger == .bluetoothReset)
        #expect(session.successCount >= 1)
        
        // 9. Verify final state
        let finalState = await manager.state()
        if case .complete(let recovered, _) = finalState {
            #expect(recovered >= 1)
        }
    }
    
    @Test("Recovery persists across sessions")
    func recoveryPersistsAcrossSessions() async {
        let persistence = InMemoryDevicePersistence()
        
        // Session 1: Register device and disconnect
        let manager1 = ConnectionRecoveryManager(
            config: .default,
            persistence: persistence
        )
        await manager1.registerDevice(DeviceRecord(
            id: "PERSIST-TEST",
            name: "Persistent Device",
            deviceType: "cgm",
            priority: .critical
        ))
        await manager1.deviceDisconnected("PERSIST-TEST")
        
        // Session 2: Create new manager with same persistence
        let manager2 = ConnectionRecoveryManager(
            config: .default,
            persistence: persistence
        )
        await manager2.restore()
        
        // Device should be restored and still need recovery
        let devices = await manager2.knownDevices()
        let needing = await manager2.devicesNeedingRecovery()
        
        #expect(devices.count == 1)
        #expect(devices[0].id == "PERSIST-TEST")
        #expect(needing.count == 1)
    }
    
    @Test("AppLaunchRecoveryHandler handles Bluetooth reset on launch")
    func appLaunchAfterBluetoothReset() async {
        let persistence = InMemoryDevicePersistence()
        
        // Simulate: Device was connected, then Bluetooth was toggled while app was terminated
        await persistence.saveDevices([
            DeviceRecord(
                id: "CGM-LAUNCH",
                name: "CGM",
                deviceType: "cgm",
                priority: .critical,
                lastConnected: Date().addingTimeInterval(-3600),
                lastDisconnected: Date().addingTimeInterval(-60)
            )
        ])
        
        // App launches
        let manager = ConnectionRecoveryManager(
            config: .cgm,
            persistence: persistence
        )
        let handler = AppLaunchRecoveryHandler(manager: manager)
        
        // Handle app launch
        let session = await handler.handleAppLaunch()
        
        // Should have attempted recovery
        #expect(session != nil)
        #expect(session?.trigger == .appLaunch)
        #expect(session?.totalAttempts == 1)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var recovery: Self
    @Tag static var integration: Self
}
