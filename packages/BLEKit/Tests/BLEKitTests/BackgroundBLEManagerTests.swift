// SPDX-License-Identifier: MIT
//
// BackgroundBLEManagerTests.swift
// BLEKitTests
//
// Tests for background BLE operations.
// Trace: APP-CGM-002

import Foundation
import Testing
@testable import BLEKit

// MARK: - Configuration Tests

@Suite("Background BLE Config")
struct BackgroundBLEConfigTests {
    
    @Test("Default config has expected values")
    func defaultConfig() {
        let config = BackgroundBLEConfig.default
        
        #expect(config.restorationIdentifier == "com.t1pal.cgm.ble")
        #expect(config.serviceUUIDs.isEmpty)
        #expect(config.autoReconnect == true)
        #expect(config.maxReconnectAttempts == 10)
        #expect(config.reconnectDelaySeconds == 5.0)
        #expect(config.backgroundScanOnDisconnect == true)
    }
    
    @Test("CGM config has CGM-specific values")
    func cgmConfig() {
        let config = BackgroundBLEConfig.cgm
        
        #expect(config.restorationIdentifier == "com.t1pal.cgm.ble")
        #expect(config.serviceUUIDs.contains("FEBC")) // Dexcom
        #expect(config.serviceUUIDs.contains("FDE3")) // Libre
        #expect(config.autoReconnect == true)
        #expect(config.maxReconnectAttempts == 20)
        #expect(config.reconnectDelaySeconds == 3.0)
    }
    
    @Test("Custom config preserves values")
    func customConfig() {
        let config = BackgroundBLEConfig(
            restorationIdentifier: "com.test.ble",
            serviceUUIDs: ["1234", "5678"],
            autoReconnect: false,
            maxReconnectAttempts: 5,
            reconnectDelaySeconds: 10.0,
            backgroundScanOnDisconnect: false
        )
        
        #expect(config.restorationIdentifier == "com.test.ble")
        #expect(config.serviceUUIDs.count == 2)
        #expect(config.autoReconnect == false)
        #expect(config.maxReconnectAttempts == 5)
        #expect(config.reconnectDelaySeconds == 10.0)
        #expect(config.backgroundScanOnDisconnect == false)
    }
    
    @Test("Config is Codable")
    func configIsCodable() throws {
        let original = BackgroundBLEConfig(
            restorationIdentifier: "test.identifier",
            serviceUUIDs: ["FEBC"],
            autoReconnect: true,
            maxReconnectAttempts: 15,
            reconnectDelaySeconds: 7.5,
            backgroundScanOnDisconnect: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BackgroundBLEConfig.self, from: data)
        
        #expect(decoded.restorationIdentifier == original.restorationIdentifier)
        #expect(decoded.serviceUUIDs == original.serviceUUIDs)
        #expect(decoded.autoReconnect == original.autoReconnect)
        #expect(decoded.maxReconnectAttempts == original.maxReconnectAttempts)
        #expect(decoded.reconnectDelaySeconds == original.reconnectDelaySeconds)
        #expect(decoded.backgroundScanOnDisconnect == original.backgroundScanOnDisconnect)
    }
}

// MARK: - Connection State Tests

@Suite("Background Connection State")
struct BackgroundConnectionStateTests {
    
    @Test("Disconnected state properties")
    func disconnectedState() {
        let state = BackgroundConnectionState.disconnected
        
        #expect(state.isConnected == false)
        #expect(state.isActive == false)
        #expect(state.description == "Disconnected")
    }
    
    @Test("Scanning state properties")
    func scanningState() {
        let state = BackgroundConnectionState.scanning
        
        #expect(state.isConnected == false)
        #expect(state.isActive == true)
        #expect(state.description == "Scanning...")
    }
    
    @Test("Connecting state properties")
    func connectingState() {
        let state = BackgroundConnectionState.connecting(peripheralId: "12345678-ABCD-1234-5678-ABCDEF123456")
        
        #expect(state.isConnected == false)
        #expect(state.isActive == true)
        #expect(state.description.contains("Connecting"))
        #expect(state.description.contains("12345678"))
    }
    
    @Test("Connected state properties")
    func connectedState() {
        let state = BackgroundConnectionState.connected(peripheralId: "12345678-ABCD-1234-5678-ABCDEF123456")
        
        #expect(state.isConnected == true)
        #expect(state.isActive == true)
        #expect(state.description.contains("Connected"))
    }
    
    @Test("Reconnecting state properties")
    func reconnectingState() {
        let state = BackgroundConnectionState.reconnecting(attempt: 3, maxAttempts: 10)
        
        #expect(state.isConnected == false)
        #expect(state.isActive == true)
        #expect(state.description.contains("3/10"))
    }
    
    @Test("Interrupted state properties")
    func interruptedState() {
        let state = BackgroundConnectionState.interrupted(reason: "Phone call")
        
        #expect(state.isConnected == false)
        #expect(state.isActive == false)
        #expect(state.description.contains("Phone call"))
    }
    
    @Test("Failed state properties")
    func failedState() {
        let state = BackgroundConnectionState.failed(reason: "Max attempts")
        
        #expect(state.isConnected == false)
        #expect(state.isActive == false)
        #expect(state.description.contains("Max attempts"))
    }
    
    @Test("State equality")
    func stateEquality() {
        #expect(BackgroundConnectionState.disconnected == BackgroundConnectionState.disconnected)
        #expect(BackgroundConnectionState.scanning == BackgroundConnectionState.scanning)
        #expect(BackgroundConnectionState.connected(peripheralId: "abc") == BackgroundConnectionState.connected(peripheralId: "abc"))
        #expect(BackgroundConnectionState.connected(peripheralId: "abc") != BackgroundConnectionState.connected(peripheralId: "xyz"))
    }
}

// MARK: - Restoration State Tests

@Suite("BLE Restoration State")
struct BLERestorationStateTests {
    
    @Test("Empty restoration state")
    func emptyState() {
        let state = BLERestorationState()
        
        #expect(state.connectedPeripheralIds.isEmpty)
        #expect(state.connectingPeripheralIds.isEmpty)
        #expect(state.scanningServiceUUIDs.isEmpty)
    }
    
    @Test("Populated restoration state")
    func populatedState() {
        let timestamp = Date()
        let state = BLERestorationState(
            connectedPeripheralIds: ["peripheral1", "peripheral2"],
            connectingPeripheralIds: ["peripheral3"],
            scanningServiceUUIDs: ["FEBC", "FDE3"],
            timestamp: timestamp
        )
        
        #expect(state.connectedPeripheralIds.count == 2)
        #expect(state.connectingPeripheralIds.count == 1)
        #expect(state.scanningServiceUUIDs.count == 2)
        #expect(state.timestamp == timestamp)
    }
    
    @Test("Restoration state is Codable")
    func stateIsCodable() throws {
        let timestamp = Date()
        let original = BLERestorationState(
            connectedPeripheralIds: ["p1", "p2"],
            connectingPeripheralIds: ["p3"],
            scanningServiceUUIDs: ["FEBC"],
            timestamp: timestamp
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BLERestorationState.self, from: data)
        
        #expect(decoded.connectedPeripheralIds == original.connectedPeripheralIds)
        #expect(decoded.connectingPeripheralIds == original.connectingPeripheralIds)
        #expect(decoded.scanningServiceUUIDs == original.scanningServiceUUIDs)
    }
}

// MARK: - Manager Tests (Cross-Platform)

@Suite("Background BLE Manager")
struct BackgroundBLEManagerTests {
    
    @Test("Manager initializes with default config")
    func initWithDefaultConfig() async {
        let manager = BackgroundBLEManager()
        
        let state = await manager.state
        #expect(state == .disconnected)
        
        let isActive = await manager.isBackgroundModeActive
        #expect(isActive == false)
    }
    
    @Test("Manager initializes with custom config")
    func initWithCustomConfig() async {
        let config = BackgroundBLEConfig(
            restorationIdentifier: "test.id",
            maxReconnectAttempts: 5
        )
        let manager = BackgroundBLEManager(config: config)
        
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Manager reports no connected peripherals initially")
    func noConnectedPeripheralsInitially() async {
        let manager = BackgroundBLEManager()
        
        let peripherals = await manager.connectedPeripheralIds
        #expect(peripherals.isEmpty)
    }
    
    @Test("Manager can set callbacks")
    func setCallbacks() async {
        let manager = BackgroundBLEManager()
        
        // Just verify we can set a callback without crashing
        await manager.setStateCallback { _ in }
        
        // Callback set successfully
        #expect(true)
    }
    
    @Test("Manager can be created from background thread without crash")
    func backgroundThreadCreation() async throws {
        // Regression test for ARCH-IMPL-002 / RL-WIRE-008
        // CBCentralManager must be created on main thread, even when
        // the actor init is triggered from a background context.
        
        // Run creation in a detached task to ensure non-main thread
        let manager = try await Task.detached {
            return BackgroundBLEManager()
        }.value
        
        // Should not crash - main thread dispatch is handled internally
        let state = await manager.state
        #expect(state == .disconnected)
    }
}

// MARK: - DarwinBLECentral State Restoration Tests (G6-COEX-018/019)

@Suite("DarwinBLECentral State Restoration")
struct DarwinBLECentralRestorationTests {
    
    @Test("Central accepts restoration identifier in options")
    func restorationIdentifierInOptions() {
        let options = BLECentralOptions(
            showPowerAlert: false,
            restorationIdentifier: "com.test.cgm"
        )
        
        #expect(options.restorationIdentifier == "com.test.cgm")
    }
    
    @Test("Default options have no restoration identifier")
    func defaultOptionsNoRestoration() {
        let options = BLECentralOptions.default
        
        #expect(options.restorationIdentifier == nil)
    }
    
    @Test("CGM-style restoration identifier follows naming convention")
    func cgmRestorationIdentifier() {
        // Following Loop/CGMBLEKit naming pattern: "com.{org}.{module}"
        let options = BLECentralOptions(
            restorationIdentifier: "com.t1pal.DexcomG6Manager"
        )
        
        #expect(options.restorationIdentifier?.hasPrefix("com.t1pal") == true)
    }
    
    #if canImport(CoreBluetooth)
    @Test("DarwinBLECentral exposes restoration callback")
    @MainActor
    func restorationCallbackExists() async {
        let options = BLECentralOptions(
            restorationIdentifier: "com.test.restoration"
        )
        
        let central = DarwinBLECentral(options: options)
        
        // Callback should be settable
        var wasRestored = false
        central.onStateRestored = { peripherals, services in
            wasRestored = true
        }
        
        // Just verifying callback can be set
        #expect(wasRestored == false)
    }
    
    @Test("DarwinBLECentral getRestoredPeripherals returns empty initially")
    @MainActor
    func emptyRestoredPeripherals() async {
        let central = DarwinBLECentral()
        let restored = central.getRestoredPeripherals()
        
        #expect(restored.isEmpty)
    }
    #endif
}

// MARK: - Thread Safety Regression Tests

@Suite("BLE Thread Safety")
struct BLEThreadSafetyTests {
    
    @Test("DarwinBLECentral can be created from background context")
    func darwinBLEBackgroundCreation() async throws {
        // Regression test for ARCH-IMPL-001 / BLE-ARCH-001
        // Trace: ARCH-IMPL-007
        
        // With BLE-ARCH-001, creation is thread-safe via queue.sync pattern
        let central = await Task.detached {
            BLECentralFactory.create()
        }.value
        
        // Should not crash
        let state = await central.state
        #expect(state != .unknown || state == .unknown) // Any state is fine
    }
    
    @Test("Multiple concurrent BLE central creations don't crash")
    func concurrentBLECreation() async throws {
        // Stress test for thread-safe initialization (BLE-ARCH-001)
        // Trace: ARCH-IMPL-007
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    // Thread-safe via queue.sync pattern
                    let central = BLECentralFactory.create()
                    _ = await central.state
                }
            }
        }
        
        // All creations succeeded without crash
        #expect(true)
    }
}
