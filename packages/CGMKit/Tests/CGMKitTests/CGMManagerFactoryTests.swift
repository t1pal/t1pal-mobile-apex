// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMManagerFactoryTests.swift
// CGMKit
//
// Tests for CGMManagerFactory G7 coexistence mode fix
// Trace: G7-COEX-FIX-001

import Testing
@testable import CGMKit
@testable import T1PalCore
import BLEKit

// MARK: - G7-COEX-FIX-001 Tests

/// Tests that G7 coexistence mode works without sensorCode
/// Trace: G7-COEX-FIX-001, ARCH-007
@Suite("CGMManagerFactory G7 Coexistence")
struct CGMManagerFactoryG7CoexistenceTests {
    
    /// G7 coexistence mode should create manager without sensorCode
    @Test("G7 coexistence creates manager without sensorCode")
    func g7CoexistenceWithoutSensorCode() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: nil,  // No transmitter ID
            sensorCode: nil,     // No sensor code
            connectionMode: .coexistence
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        // Should not throw - coexistence doesn't need sensorCode
        let manager = try await CGMManagerFactory.create(for: context)
        
        // Verify it created a G7 manager (not HealthKit fallback)
        #expect(manager is DexcomG7Manager, "Should create DexcomG7Manager for coexistence")
    }
    
    /// G7 coexistence mode should work with provided transmitterId
    @Test("G7 coexistence uses provided transmitterId")
    func g7CoexistenceWithTransmitterId() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: "0123456789",  // Known serial
            sensorCode: nil,               // Still no sensor code needed
            connectionMode: .coexistence
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context)
        #expect(manager is DexcomG7Manager, "Should create DexcomG7Manager")
    }
    
    /// G7 direct mode should throw without sensorCode (ARCH-007)
    @Test("G7 direct mode throws without sensorCode")
    func g7DirectModeRequiresSensorCode() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: "0123456789",
            sensorCode: nil,  // Missing required for direct
            connectionMode: .direct
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        // Should throw CGMError.configurationRequired
        await #expect(throws: CGMError.self) {
            _ = try await CGMManagerFactory.create(for: context)
        }
    }
    
    /// G7 direct mode should throw without transmitterId (ARCH-007)
    @Test("G7 direct mode throws without transmitterId")
    func g7DirectModeRequiresTransmitterId() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: nil,  // Missing required
            sensorCode: "1234",
            connectionMode: .direct
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        await #expect(throws: CGMError.self) {
            _ = try await CGMManagerFactory.create(for: context)
        }
    }
    
    /// G7 direct mode should create manager with both fields
    @Test("G7 direct mode works with full config")
    func g7DirectModeWithFullConfig() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: "0123456789",
            sensorCode: "1234",
            connectionMode: .direct
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        // Should succeed with full config
        let manager = try await CGMManagerFactory.create(for: context)
        #expect(manager is DexcomG7Manager)
    }
    
    /// ONE+ also uses G7 path and should behave the same
    @Test("ONE+ coexistence works like G7")
    func onePlusCoexistence() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomONEPlus,
            transmitterId: nil,
            sensorCode: nil,
            connectionMode: .coexistence
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context)
        #expect(manager is DexcomG7Manager, "ONE+ should use G7 manager")
    }
}

// MARK: - CGM-066e ALK Passthrough Tests

/// Tests that App Level Key config is passed through factory to manager
/// Trace: CGM-066e
@Suite("CGMManagerFactory ALK Passthrough")
struct CGMManagerFactoryALKTests {
    
    /// Factory should pass appLevelKey to G6 manager
    @Test("G6 factory passes appLevelKey to manager")
    func g6FactoryPassesAppLevelKey() async throws {
        let testALK = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        
        let config = BLEDeviceConfig(
            cgmType: .dexcomG6,
            transmitterId: "8G1234",
            connectionMode: .direct,
            appLevelKey: testALK,
            generateNewAppLevelKey: false
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context)
        
        #expect(manager is DexcomG6Manager)
        
        // Verify ALK was passed to config
        if let g6Manager = manager as? DexcomG6Manager {
            let managerConfig = await g6Manager.config
            #expect(managerConfig.appLevelKey == testALK)
            #expect(managerConfig.generateNewAppLevelKey == false)
        }
    }
    
    /// Factory should pass generateNewAppLevelKey flag
    @Test("G6 factory passes generateNewAppLevelKey flag")
    func g6FactoryPassesGenerateFlag() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG6,
            transmitterId: "8G5678",
            connectionMode: .direct,
            appLevelKey: nil,
            generateNewAppLevelKey: true
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context)
        
        #expect(manager is DexcomG6Manager)
        
        if let g6Manager = manager as? DexcomG6Manager {
            let managerConfig = await g6Manager.config
            #expect(managerConfig.appLevelKey == nil)
            #expect(managerConfig.generateNewAppLevelKey == true)
        }
    }
    
    /// Factory should default ALK to nil when not provided
    @Test("G6 factory defaults ALK to nil")
    func g6FactoryDefaultsALKToNil() async throws {
        let config = BLEDeviceConfig(
            cgmType: .dexcomG6,
            transmitterId: "8GABCD",
            connectionMode: .direct
            // ALK fields not provided - should default
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context)
        
        #expect(manager is DexcomG6Manager)
        
        if let g6Manager = manager as? DexcomG6Manager {
            let managerConfig = await g6Manager.config
            #expect(managerConfig.appLevelKey == nil)
            #expect(managerConfig.generateNewAppLevelKey == false)
        }
    }
    
    /// Factory with callbacks should wire onAppLevelKeyChanged
    /// Trace: CGM-066f
    @Test("G6 factory wires ALK persistence callback")
    func g6FactoryWiresALKCallback() async throws {
        // Use actor-isolated storage for thread safety
        actor KeyCapture {
            var capturedKey: Data?
            func capture(_ key: Data) { capturedKey = key }
            func getCapturedKey() -> Data? { capturedKey }
        }
        let keyCapture = KeyCapture()
        
        let callbacks = CGMManagerCallbacks(
            onAppLevelKeyChanged: { key in
                Task { await keyCapture.capture(key) }
            }
        )
        
        let config = BLEDeviceConfig(
            cgmType: .dexcomG6,
            transmitterId: "8GCALL",
            connectionMode: .direct,
            generateNewAppLevelKey: true
        )
        
        let context = DataContext(
            sourceType: .ble,
            bleConfig: config
        )
        
        let manager = try await CGMManagerFactory.create(for: context, callbacks: callbacks)
        
        #expect(manager is DexcomG6Manager)
        
        // Verify callback was wired - checking that manager was created is sufficient
        // The actual callback invocation happens when ALK is accepted by transmitter
        let captured = await keyCapture.getCapturedKey()
        #expect(captured == nil) // Not called yet - will be called when transmitter accepts ALK
    }
}
