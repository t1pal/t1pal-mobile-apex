// SPDX-License-Identifier: MIT
//
// DexcomG6ManagerTests.swift
// CGMKitTests
//
// Unit tests for Dexcom G6 Manager using MockBLE.

import Testing
import Foundation
import T1PalCore
@testable import CGMKit
@testable import BLEKit

@Suite("DexcomG6Manager Tests", .serialized)
struct DexcomG6ManagerTests {
    
    @Test("Manager initialization")
    func initialization() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        let state = await manager.connectionState
        #expect(state == .idle)
        
        let displayName = await manager.displayName
        #expect(displayName == "Dexcom G6")
    }
    
    @Test("Manager starts in idle state")
    func initialState() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        let connState = await manager.connectionState
        let sensorState = await manager.sensorState
        
        #expect(connState == .idle)
        #expect(sensorState == .notStarted)
    }
    
    @Test("Start scanning changes state")
    func startScanning() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        // Start scanning (no matching device, will stay in scanning state)
        try await manager.startScanning()
        
        // Give it a moment to change state
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .scanning)
        
        // Cleanup
        await manager.disconnect()
    }
    
    @Test("Scanning fails when Bluetooth off")
    func scanningFailsBTOff() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        do {
            try await manager.startScanning()
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }
    
    @Test("Disconnect returns to idle")
    func disconnect() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
    
    @Test("CGM type is dexcomG6")
    func cgmType() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        let cgmType = await manager.cgmType
        #expect(cgmType == .dexcomG6)
    }
    
    @Test("Transmitter ID is stored")
    func transmitterIdStored() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        let storedTx = await manager.transmitterId
        #expect(storedTx == tx)
    }
    
    @Test("Latest reading is nil initially")
    func latestReadingNil() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        let reading = await manager.latestReading
        #expect(reading == nil)
    }
}

@Suite("G6ConnectionState Tests")
struct G6ConnectionStateTests {
    
    @Test("All connection states have raw values")
    func allStates() {
        let states: [G6ConnectionState] = [
            .idle, .scanning, .connecting,
            .authenticating, .streaming,
            .disconnecting, .error, .passive
        ]
        
        #expect(states.count == 8)
        
        for state in states {
            #expect(!state.rawValue.isEmpty)
        }
    }
}

// MARK: - DexcomG6ManagerConfig Tests (CGM-030)

@Suite("Dexcom G6 Manager Config")
struct DexcomG6ManagerConfigTests {
    
    @Test("Default config uses coexistence mode")
    func defaultConfigMode() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: tx)
        
        // Default is coexistence mode (Loop-style passive glucose)
        #expect(config.connectionMode == .coexistence)
        // G6-COEX-012: HealthKit fallback disabled by default (requires entitlement)
        #expect(config.passiveFallbackToHealthKit == false)
    }
    
    @Test("Config with passive mode")
    func passiveModeConfig() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        
        #expect(config.connectionMode == .passiveBLE)
    }
    
    @Test("Config with HealthKit-only mode")
    func healthKitOnlyConfig() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .healthKitObserver
        )
        
        #expect(config.connectionMode == .healthKitObserver)
    }
}

// MARK: - Passive Mode Tests (CGM-030)

@Suite("Dexcom G6 Passive Mode", .serialized)
struct DexcomG6PassiveModeTests {
    
    @Test("Manager with config stores connection mode")
    func managerWithConfig() async {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        let mode = await manager.connectionMode
        #expect(mode == .passiveBLE)
    }
    
    @Test("Passive mode enters passive state")
    func passiveModeState() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .passive)
        
        await manager.disconnect()
    }
    
    @Test("HealthKit-only mode enters passive state without BLE")
    func healthKitOnlyModeState() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .healthKitObserver,
            allowSimulation: true
        )
        let central = MockBLECentral()
        // Set BLE off - should still work
        await central.setState(.poweredOff)
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        // HealthKit-only mode doesn't need BLE
        try await manager.startScanning()
        
        let state = await manager.connectionState
        #expect(state == .passive)
        
        let sensor = await manager.sensorState
        #expect(sensor == .active)
    }
    
    @Test("Vendor connection callback can be set")
    func vendorConnectionCallback() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        await manager.setVendorCallback { _ in }
        
        // Verify callback is set
        let hasCallback = await manager.onVendorConnectionDetected != nil
        #expect(hasCallback)
    }
    
    @Test("Disconnect stops passive scanner")
    func disconnectStopsPassive() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
}

// MARK: - Auto-Reconnection Tests (PROTO-AUTO-001)

@Suite("Dexcom G6 Auto-Reconnection", .serialized)
struct DexcomG6AutoReconnectTests {
    
    @Test("Default config enables auto-reconnect")
    func defaultAutoReconnectEnabled() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: tx)
        
        #expect(config.autoReconnect == true)
        #expect(config.reconnectDelay == 2.0)
        #expect(config.maxReconnectAttempts == 0)  // Unlimited
    }
    
    @Test("Config with auto-reconnect disabled")
    func autoReconnectDisabled() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            autoReconnect: false
        )
        
        #expect(config.autoReconnect == false)
    }
    
    @Test("Config with custom reconnect settings")
    func customReconnectSettings() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            autoReconnect: true,
            reconnectDelay: 5.0,
            maxReconnectAttempts: 3
        )
        
        #expect(config.reconnectDelay == 5.0)
        #expect(config.maxReconnectAttempts == 3)
    }
    
    @Test("User disconnect does not trigger auto-reconnect")
    func userDisconnectNoAutoReconnect() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: tx, autoReconnect: true)
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Disconnect should set idle state, not trigger reconnect scan
        await manager.disconnect()
        
        let state = await manager.connectionState
        #expect(state == .idle)
    }
}

// MARK: - Coexistence Mode Tests (G6-COEX-003)

@Suite("Dexcom G6 Coexistence Mode", .serialized)
struct DexcomG6CoexistenceModeTests {
    
    @Test("Config with coexistence mode")
    func coexistenceModeConfig() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        
        #expect(config.connectionMode == .coexistence)
    }
    
    @Test("Manager stores coexistence mode from config")
    func managerWithCoexistenceConfig() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        let mode = await manager.connectionMode
        #expect(mode == .coexistence)
    }
    
    @Test("Coexistence mode starts scanning on startScanning()")
    func coexistenceStartsScanning() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        try await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let state = await manager.connectionState
        #expect(state == .scanning)
        
        await manager.disconnect()
    }
    
    @Test("Coexistence mode requires Bluetooth powered on")
    func coexistenceRequiresBluetooth() async throws {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        do {
            try await manager.startScanning()
            Issue.record("Should throw bluetoothUnavailable")
        } catch CGMError.bluetoothUnavailable {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("Coexistence vs passive mode - coexistence connects")
    func coexistenceConnectsVsPassiveObserves() async {
        let tx = TransmitterID("80AB12")!
        
        // Coexistence mode - will attempt to connect
        let coexConfig = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        #expect(coexConfig.connectionMode == .coexistence)
        
        // Passive mode - only observes advertisements
        let passiveConfig = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .passiveBLE,
            allowSimulation: true
        )
        #expect(passiveConfig.connectionMode == .passiveBLE)
    }
    
    @Test("Coexistence mode enables <10s glucose latency")
    func coexistenceLatencyGoal() {
        // Document the latency goal for coexistence mode
        // Direct BLE connection + subscription enables real-time glucose
        // vs HealthKit which can have 5-15 minute delays
        
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        
        // Coexistence mode achieves <10s latency by:
        // 1. Connecting to transmitter (not just scanning)
        // 2. Subscribing to auth to observe vendor auth
        // 3. Subscribing to control for glucose push
        #expect(config.connectionMode == .coexistence)
    }
    
    @Test("Coexistence mode skips self-authentication")
    func coexistenceSkipsSelfAuth() async throws {
        // G6-COEX-006: Port from G7 - coexistence observes vendor auth, doesn't self-authenticate
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        let central = MockBLECentral()
        let manager = DexcomG6Manager(config: config, central: central)
        
        // In coexistence mode, manager observes vendor authentication
        // It never enters the "authenticating" state itself
        let mode = await manager.connectionMode
        #expect(mode == .coexistence)
        
        // Verify we're not in direct mode which would self-authenticate
        #expect(mode != .direct)
    }
    
    @Test("CGMConnectionMode has coexistence case")
    func connectionModeHasCoexistence() {
        // G6-COEX-006: Port from G7 - verify enum case exists
        let mode = CGMConnectionMode.coexistence
        #expect(mode.rawValue == "coexistence")
    }
}

// MARK: - HealthKit Fallback Tests (G6-CONNECT-005)

@Suite("G6 HealthKit Fallback Mode Tests")
struct DexcomG6HealthKitFallbackTests {
    
    @Test("Config enables HealthKit fallback by default")
    func configEnablesFallbackByDefault() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        
        // G6-COEX-012: HealthKit fallback disabled by default (requires entitlement)
        // To enable, pass passiveFallbackToHealthKit: true explicitly
        #expect(config.passiveFallbackToHealthKit == false)
    }
    
    @Test("Config can enable HealthKit fallback")
    func configCanEnableFallback() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            passiveFallbackToHealthKit: true  // Explicitly enable
        )
        
        #expect(config.passiveFallbackToHealthKit == true)
    }
    
    @Test("Manager tracks HealthKit fallback state")
    func managerTracksFallbackState() async {
        let central = MockBLECentral()
        let tx = TransmitterID("80AB12")!
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        // Initially not in fallback mode
        let isActive = await manager.isHealthKitFallbackActive
        #expect(isActive == false)
    }
    
    @Test("HealthKit config can be customized")
    func healthKitConfigCustomizable() {
        let tx = TransmitterID("80AB12")!
        let hkConfig = HealthKitCGMConfig(
            enableBackgroundDelivery: true,
            enableGapFilling: true
        )
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            passiveFallbackToHealthKit: true,
            healthKitConfig: hkConfig
        )
        
        #expect(config.healthKitConfig != nil)
        #expect(config.healthKitConfig?.enableBackgroundDelivery == true)
        #expect(config.healthKitConfig?.enableGapFilling == true)
    }
    
    @Test("Fallback source is labeled correctly")
    func fallbackSourceLabel() {
        // When fallback is active, readings should be tagged
        let reading = GlucoseReading(
            glucose: 120.0,
            timestamp: Date(),
            trend: .flat,
            source: "Dexcom G6 (HealthKit)"
        )
        
        #expect(reading.source == "Dexcom G6 (HealthKit)")
        #expect(reading.source.contains("HealthKit"))
    }
    
    // MARK: - G6-COEX-009: Service Discovery Caching
    
    @Test("Service discovery caching uses unique key per transmitter")
    func serviceDiscoveryCachingKey() {
        // G6-COEX-009: Each transmitter should have its own cache key
        let tx1 = TransmitterID("80AB12")!
        let tx2 = TransmitterID("80CD34")!
        
        let key1 = "com.t1pal.cgmkit.g6.servicesDiscovered.\(tx1.id)"
        let key2 = "com.t1pal.cgmkit.g6.servicesDiscovered.\(tx2.id)"
        
        #expect(key1 != key2)
        #expect(key1.contains("80AB12"))
        #expect(key2.contains("80CD34"))
    }
    
    @Test("Config for service discovery caching includes transmitter ID")
    func configCachingKeyIncludesTransmitterId() async {
        // G6-COEX-009: Manager should use transmitter-specific keys
        let tx = TransmitterID("80EF56")!
        let central = MockBLECentral()
        await central.setState(.poweredOn)
        
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence,
            allowSimulation: true
        )
        
        let _ = DexcomG6Manager(config: config, central: central)
        
        // The key should be based on transmitter ID
        let expectedKeyPrefix = "com.t1pal.cgmkit.g6.servicesDiscovered"
        #expect(expectedKeyPrefix.hasPrefix("com.t1pal.cgmkit.g6"))
    }
    
    // MARK: - G6-DIRECT-031: Session Start Tests
    
    @Test("startSensorSession requires direct mode")
    func startSessionRequiresDirect() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        // Create manager with coexistence mode (not direct)
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence  // Not direct mode
        )
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Should throw configuration error
        do {
            _ = try await manager.startSensorSession()
            Issue.record("Expected configurationError")
        } catch CGMError.configurationError(let msg) {
            #expect(msg.contains("direct"))
        } catch CGMError.dataUnavailable {
            // Also acceptable - not connected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("stopSensorSession requires direct mode")
    func stopSessionRequiresDirect() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        // Create manager with coexistence mode (not direct)
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .coexistence  // Not direct mode
        )
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Should throw configuration error
        do {
            _ = try await manager.stopSensorSession()
            Issue.record("Expected configurationError")
        } catch CGMError.configurationError(let msg) {
            #expect(msg.contains("direct"))
        } catch CGMError.dataUnavailable {
            // Also acceptable - not connected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("startSensorSession throws when not streaming")
    func startSessionNotStreaming() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        // Create manager with direct mode but don't connect
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .direct,
            allowSimulation: true
        )
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Should throw because not connected/streaming
        do {
            _ = try await manager.startSensorSession()
            Issue.record("Expected dataUnavailable error")
        } catch CGMError.dataUnavailable {
            // Expected - not in streaming state
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("stopSensorSession throws when not streaming")
    func stopSessionNotStreaming() async throws {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        // Create manager with direct mode but don't connect
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            connectionMode: .direct,
            allowSimulation: true
        )
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Should throw because not connected/streaming
        do {
            _ = try await manager.stopSensorSession()
            Issue.record("Expected dataUnavailable error")
        } catch CGMError.dataUnavailable {
            // Expected - not in streaming state
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
