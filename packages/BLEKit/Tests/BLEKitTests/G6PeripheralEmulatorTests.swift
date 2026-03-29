// SPDX-License-Identifier: MIT
//
// G6PeripheralEmulatorTests.swift
// BLEKitTests
//
// Tests for the G6 peripheral emulator.
// Trace: CLI-SIM-004

import Foundation
import Testing
@testable import BLEKit

@Suite("G6 Peripheral Emulator")
struct G6PeripheralEmulatorTests {
    
    // MARK: - Initialization Tests
    
    @Test("Default configuration creates valid emulator")
    func defaultConfig() async {
        let emulator = await G6PeripheralEmulator.forTesting()
        let status = await emulator.status
        
        #expect(status.state == .idle)
        #expect(status.transmitterId == "80H123")
        #expect(status.pattern == .flat)
        #expect(status.readingCount == 0)
        #expect(!status.isAuthenticated)
    }
    
    @Test("Custom configuration is applied")
    func customConfig() async {
        let config = G6EmulatorConfig(
            transmitterId: "8GTEST",
            pattern: .sine,
            patternConfig: PatternConfig(baseGlucose: 150, amplitude: 50),
            skipWarmup: false
        )
        
        let emulator = await G6PeripheralEmulator.forTesting(config: config)
        let status = await emulator.status
        
        #expect(status.transmitterId == "8GTEST")
        #expect(status.pattern == .sine)
    }
    
    // MARK: - State Machine Tests
    
    @Test("Start changes state to advertising")
    func startAdvertising() async throws {
        let emulator = await G6PeripheralEmulator.forTesting()
        
        try await emulator.start()
        let status = await emulator.status
        
        #expect(status.state == .advertising)
    }
    
    @Test("Stop changes state to stopped")
    func stopEmulator() async throws {
        let emulator = await G6PeripheralEmulator.forTesting()
        
        try await emulator.start()
        await emulator.stop()
        
        let status = await emulator.status
        #expect(status.state == .stopped)
    }
    
    @Test("Cannot start from running state")
    func cannotDoubleStart() async throws {
        let emulator = await G6PeripheralEmulator.forTesting()
        
        try await emulator.start()
        
        do {
            try await emulator.start()
            Issue.record("Expected error when starting already running emulator")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test("All pattern types are valid")
    func allPatternTypes() async {
        for pattern in GlucosePatternType.allCases {
            let config = G6EmulatorConfig(pattern: pattern)
            let emulator = await G6PeripheralEmulator.forTesting(config: config)
            let status = await emulator.status
            
            #expect(status.pattern == pattern)
        }
    }
    
    @Test("Update config only allowed when idle")
    func updateConfigWhenIdle() async throws {
        let emulator = await G6PeripheralEmulator.forTesting()
        
        // Should work when idle
        try await emulator.updateConfig(G6EmulatorConfig(transmitterId: "8GNEW1"))
        let status1 = await emulator.status
        #expect(status1.transmitterId == "8GNEW1")
        
        // Start emulator
        try await emulator.start()
        
        // Should fail when running
        do {
            try await emulator.updateConfig(G6EmulatorConfig(transmitterId: "8GNEW2"))
            Issue.record("Expected error when updating config while running")
        } catch {
            // Expected
        }
        
        // Transmitter ID should be unchanged
        let status2 = await emulator.status
        #expect(status2.transmitterId == "8GNEW1")
    }
    
    // MARK: - Mock Peripheral Manager Tests
    
    @Test("Service is added on start")
    func serviceAddedOnStart() async throws {
        let mockManager = MockBLEPeripheralManager()
        let emulator = G6PeripheralEmulator(
            config: .default,
            peripheralManager: mockManager
        )
        
        try await emulator.start()
        
        // Check service was added
        let service = await mockManager.getService(uuid: .dexcomService)
        #expect(service != nil)
        #expect(service?.isPrimary == true)
        #expect(service?.characteristics.count == 3)
    }
    
    @Test("Advertising starts on start")
    func advertisingStartsOnStart() async throws {
        let mockManager = MockBLEPeripheralManager()
        let emulator = G6PeripheralEmulator(
            config: G6EmulatorConfig(autoAdvertise: true),
            peripheralManager: mockManager
        )
        
        try await emulator.start()
        
        let isAdvertising = await mockManager.isAdvertising
        #expect(isAdvertising)
    }
    
    @Test("Services cleared on stop")
    func servicesClearedOnStop() async throws {
        let mockManager = MockBLEPeripheralManager()
        let emulator = G6PeripheralEmulator(
            config: .default,
            peripheralManager: mockManager
        )
        
        try await emulator.start()
        await emulator.stop()
        
        let service = await mockManager.getService(uuid: .dexcomService)
        #expect(service == nil)
    }
    
    // MARK: - Traffic Logger Tests
    
    @Test("Traffic logger is available")
    func trafficLoggerAvailable() async {
        let emulator = await G6PeripheralEmulator.forTesting()
        let log = await emulator.exportTraffic()
        
        // Should be valid JSON (empty array)
        #expect(log.contains("["))
    }
    
    // MARK: - Status Tests
    
    @Test("Status reflects current state")
    func statusReflectsState() async throws {
        let emulator = await G6PeripheralEmulator.forTesting()
        
        var status = await emulator.status
        #expect(status.state == .idle)
        #expect(status.subscriptionCount == 0)
        #expect(!status.hasConnectedCentral)
        
        try await emulator.start()
        status = await emulator.status
        #expect(status.state == .advertising)
        
        await emulator.stop()
        status = await emulator.status
        #expect(status.state == .stopped)
    }
    
    // MARK: - G6EmulatorConfig Tests
    
    @Test("Default config has sensible values")
    func defaultConfigValues() {
        let config = G6EmulatorConfig.default
        
        #expect(config.transmitterId == "80H123")
        #expect(config.pattern == .flat)
        #expect(config.skipWarmup == true)
        #expect(config.intervalSeconds == 300)
        #expect(config.autoAdvertise == true)
    }
    
    @Test("PatternConfig has sensible defaults")
    func patternConfigDefaults() {
        let config = PatternConfig()
        
        #expect(config.baseGlucose == 120)
        #expect(config.amplitude == 40)
        #expect(config.periodMinutes == 180)
        #expect(config.stepSize == 5)
    }
}

@Suite("G6 Emulator Integration")
struct G6EmulatorIntegrationTests {
    
    @Test("Emulator works with mock peripheral manager")
    func emulatorWithMockManager() async throws {
        let mockManager = MockBLEPeripheralManager()
        let emulator = G6PeripheralEmulator(
            config: G6EmulatorConfig(
                transmitterId: "8GINT1",
                pattern: .flat,
                patternConfig: PatternConfig(baseGlucose: 100)
            ),
            peripheralManager: mockManager
        )
        
        try await emulator.start()
        
        // Verify state
        let status = await emulator.status
        #expect(status.state == .advertising)
        #expect(status.transmitterId == "8GINT1")
        
        // Stop
        await emulator.stop()
        let finalStatus = await emulator.status
        #expect(finalStatus.state == .stopped)
    }
    
    @Test("Multiple emulators can coexist")
    func multipleEmulators() async throws {
        let emulator1 = await G6PeripheralEmulator.forTesting(
            config: G6EmulatorConfig(transmitterId: "8GMUL1")
        )
        let emulator2 = await G6PeripheralEmulator.forTesting(
            config: G6EmulatorConfig(transmitterId: "8GMUL2")
        )
        
        try await emulator1.start()
        try await emulator2.start()
        
        let status1 = await emulator1.status
        let status2 = await emulator2.status
        
        #expect(status1.transmitterId == "8GMUL1")
        #expect(status2.transmitterId == "8GMUL2")
        #expect(status1.state == .advertising)
        #expect(status2.state == .advertising)
        
        await emulator1.stop()
        await emulator2.stop()
    }
}
