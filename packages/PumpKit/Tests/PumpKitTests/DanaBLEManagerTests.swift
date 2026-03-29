// SPDX-License-Identifier: MIT
//
// DanaBLEManagerTests.swift
// PumpKitTests
//
// Tests for Dana-i/RS BLE connection manager
// Trace: PUMP-DANA-004

import Testing
import Foundation
@testable import PumpKit

@Suite("DanaBLEManager Tests", .serialized)
struct DanaBLEManagerTests {
    
    // MARK: - Initial State
    
    @Test("Initial state is disconnected with no pump")
    func initialState() async throws {
        let manager = DanaBLEManager()
        let state = await manager.state
        let pump = await manager.connectedPump
        
        #expect(state == .disconnected)
        #expect(pump == nil)
    }
    
    // MARK: - Scanning
    
    @Test("Start scanning sets state to scanning")
    func startScanning() async throws {
        let manager = DanaBLEManager()
        
        await manager.startScanning()
        let state = await manager.state
        
        #expect(state == .scanning)
        
        await manager.stopScanning()
    }
    
    @Test("Stop scanning sets state to disconnected")
    func stopScanning() async throws {
        let manager = DanaBLEManager()
        
        await manager.startScanning()
        await manager.stopScanning()
        
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Scan discovers Dana pumps")
    func scanDiscovery() async throws {
        let manager = DanaBLEManager()
        
        await manager.startScanning()
        
        // Wait for simulated discovery
        try await Task.sleep(nanoseconds: 600_000_000)
        
        let pumps = await manager.discoveredPumps
        #expect(pumps.count > 0)
        
        // Check simulated pump
        if let pump = pumps.first {
            #expect(pump.isDanaPump)
            #expect(pump.inferredGeneration == .danaI)
        }
        
        await manager.stopScanning()
    }
    
    // MARK: - Connection
    
    @Test("Connect to pump sets state to ready")
    func connectToPump() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50,
            generation: .danaI
        )
        
        try await manager.connect(to: pump)
        
        let state = await manager.state
        let connected = await manager.connectedPump
        
        #expect(state == .ready)
        #expect(connected != nil)
        #expect(connected?.id == pump.id)
        
        await manager.disconnect()
    }
    
    @Test("Disconnect clears connection state")
    func disconnect() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        await manager.disconnect()
        
        let state = await manager.state
        let connected = await manager.connectedPump
        
        #expect(state == .disconnected)
        #expect(connected == nil)
    }
    
    // MARK: - Session
    
    @Test("Session is created on connect")
    func sessionCreated() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50,
            generation: .danaI
        )
        
        try await manager.connect(to: pump)
        
        let session = await manager.session
        #expect(session != nil)
        #expect(session?.messageSequence == 0)
        #expect(session?.encryptionType == .ble5)
        #expect(session?.generation == .danaI)
        
        await manager.disconnect()
    }
    
    @Test("Session key is generated (128-bit)")
    func sessionKeyGenerated() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50,
            generation: .danaI
        )
        
        try await manager.connect(to: pump)
        
        let session = await manager.session
        #expect(session?.sessionKey != nil)
        #expect(session?.sessionKey.count == 16) // 128-bit key
        
        await manager.disconnect()
    }
    
    // MARK: - Commands
    
    @Test("Send command increments sequence")
    func sendCommand() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        
        let command = Data([0x00]) // Status command
        let response = try await manager.sendCommand(command, type: .general)
        
        #expect(response.count > 0)
        
        // Verify sequence incremented
        let session = await manager.session
        #expect(session?.messageSequence == 1)
        
        await manager.disconnect()
    }
    
    @Test("Read status returns valid pump status")
    func readStatus() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        
        let status = try await manager.readStatus()
        
        #expect(status.errorState == .none)
        #expect(status.reservoirLevel > 0)
        #expect(status.batteryPercent > 0)
        #expect(status.canDeliver)
        
        await manager.disconnect()
    }
    
    @Test("Read basal rate returns positive value")
    func readBasalRate() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        
        let basalRate = try await manager.readBasalRate()
        
        #expect(basalRate > 0)
        
        await manager.disconnect()
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostics returns connection info")
    func diagnostics() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50,
            generation: .danaI
        )
        
        try await manager.connect(to: pump)
        
        let diagnostics = await manager.diagnosticInfo()
        
        #expect(diagnostics.state == .ready)
        #expect(diagnostics.connectedPump != nil)
        #expect(diagnostics.session != nil)
        #expect(diagnostics.description.contains("Ready"))
        #expect(diagnostics.description.contains("BLE 5.0"))
        
        await manager.disconnect()
    }
    
    // MARK: - Error Handling
    
    @Test("Sending command when not connected throws error")
    func notConnectedError() async throws {
        let manager = DanaBLEManager()
        
        do {
            _ = try await manager.sendCommand(Data([0x00]), type: .general)
            Issue.record("Should throw notConnected error")
        } catch let error as DanaBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Connecting when already connected throws error")
    func alreadyConnectedError() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        
        do {
            try await manager.connect(to: pump)
            Issue.record("Should throw alreadyConnected error")
        } catch let error as DanaBLEError {
            #expect(error == .alreadyConnected)
        }
        
        await manager.disconnect()
    }
    
    // MARK: - Discovered Pump
    
    @Test("Discovered pump isDanaPump detection")
    func discoveredPumpIsDana() throws {
        let danaPump = DiscoveredDanaPump(id: "001", name: "Dana-i", rssi: -50)
        #expect(danaPump.isDanaPump)
        
        let danaRSPump = DiscoveredDanaPump(id: "002", name: "Dana-RS", rssi: -60)
        #expect(danaRSPump.isDanaPump)
        
        let unknownPump = DiscoveredDanaPump(id: "003", name: "Random Device", rssi: -70)
        #expect(!unknownPump.isDanaPump)
    }
    
    @Test("Inferred generation from pump name")
    func inferredGeneration() throws {
        let danaIPump = DiscoveredDanaPump(id: "001", name: "Dana-i", rssi: -50)
        #expect(danaIPump.inferredGeneration == .danaI)
        
        let danaRSPump = DiscoveredDanaPump(id: "002", name: "Dana-RS", rssi: -50)
        #expect(danaRSPump.inferredGeneration == .danaRS)
        
        let danaRPump = DiscoveredDanaPump(id: "003", name: "Dana-R", rssi: -50)
        #expect(danaRPump.inferredGeneration == .danaR)
    }
    
    @Test("Encryption type by generation")
    func encryptionType() throws {
        let danaIPump = DiscoveredDanaPump(id: "001", name: "Dana-i", rssi: -50)
        #expect(danaIPump.encryptionType == .ble5)
        
        let danaRSPump = DiscoveredDanaPump(id: "002", name: "Dana-RS", rssi: -50)
        #expect(danaRSPump.encryptionType == .rsv3)
        
        let danaRPump = DiscoveredDanaPump(id: "003", name: "Dana-R", rssi: -50)
        #expect(danaRPump.encryptionType == .legacy)
    }
    
    // MARK: - Status Response
    
    @Test("Status response flags")
    func statusResponse() throws {
        let status = DanaStatusResponse(
            errorState: .none,
            reservoirLevel: 150.0,
            batteryPercent: 75,
            isSuspended: false,
            isTempBasalRunning: false,
            isExtendedBolusRunning: false,
            dailyTotalUnits: 15.0
        )
        
        #expect(status.canDeliver)
        #expect(!status.isLowReservoir)
        #expect(!status.isLowBattery)
        
        let lowStatus = DanaStatusResponse(
            errorState: .none,
            reservoirLevel: 15.0,
            batteryPercent: 15,
            isSuspended: false
        )
        
        #expect(lowStatus.isLowReservoir)
        #expect(lowStatus.isLowBattery)
        
        let suspendedStatus = DanaStatusResponse(
            errorState: .none,
            reservoirLevel: 100.0,
            batteryPercent: 80,
            isSuspended: true
        )
        
        #expect(!suspendedStatus.canDeliver)
    }
    
    // MARK: - Connection States
    
    @Test("Connection state flags")
    func connectionStates() throws {
        #expect(!DanaConnectionState.disconnected.isConnected)
        #expect(!DanaConnectionState.scanning.isConnected)
        #expect(!DanaConnectionState.connecting.isConnected)
        #expect(!DanaConnectionState.handshaking.isConnected)
        #expect(!DanaConnectionState.encrypting.isConnected)
        #expect(DanaConnectionState.authenticated.isConnected)
        #expect(DanaConnectionState.ready.isConnected)
        
        #expect(!DanaConnectionState.authenticated.canSendCommands)
        #expect(DanaConnectionState.ready.canSendCommands)
    }
    
    // MARK: - Session Sequence
    
    @Test("Session sequence increments correctly")
    func sessionSequence() throws {
        var session = DanaSession(pumpId: "test-pump", generation: .danaI)
        #expect(session.messageSequence == 0)
        #expect(!session.isStale)
        
        let seq1 = session.nextSequence()
        #expect(seq1 == 1)
        
        let seq2 = session.nextSequence()
        #expect(seq2 == 2)
        
        // Session key is 128-bit
        #expect(session.sessionKey.count == 16)
    }
    
    // MARK: - Error States
    
    @Test("Error state delivery flags")
    func errorStates() throws {
        #expect(DanaErrorState.none.canDeliver)
        #expect(!DanaErrorState.suspended.canDeliver)
        #expect(!DanaErrorState.dailyMax.canDeliver)
        #expect(!DanaErrorState.bolusBlock.canDeliver)
    }
    
    // MARK: - Dana-RS Connection
    
    @Test("Dana-RS connection uses RSv3 encryption")
    func danaRSConnection() async throws {
        let manager = DanaBLEManager()
        
        let pump = DiscoveredDanaPump(
            id: "test-rs-001",
            name: "Dana-RS",
            rssi: -55,
            generation: .danaRS
        )
        
        try await manager.connect(to: pump)
        
        let session = await manager.session
        #expect(session?.encryptionType == .rsv3)
        #expect(session?.generation == .danaRS)
        
        await manager.disconnect()
    }
    
    // MARK: - Fault Injection Tests (WIRE-001)
    
    @Test("Fault injection blocks connect")
    func faultInjectionBlocksConnect() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .immediate)
        
        let manager = DanaBLEManager(faultInjector: injector)
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        do {
            try await manager.connect(to: pump)
            Issue.record("Should have thrown an error")
        } catch {
            // Expected - fault was injected
            #expect(error is DanaBLEError)
        }
    }
    
    @Test("Fault injection blocks command")
    func faultInjectionBlocksCommand() async throws {
        let injector = PumpFaultInjector()
        let manager = DanaBLEManager(faultInjector: injector)
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        // Connect successfully first
        try await manager.connect(to: pump)
        
        // Now add fault for command
        injector.addFault(.communicationError(code: 0x01), trigger: .immediate)
        
        do {
            let command = Data([0x00])
            _ = try await manager.sendCommand(command, type: .general)
            Issue.record("Should have thrown an error")
        } catch {
            // Expected - fault was injected
            #expect(error is DanaBLEError)
        }
        
        await manager.disconnect()
    }
    
    @Test("No fault injector allows connect")
    func noFaultInjectorAllowsConnect() async throws {
        // No fault injector - should work normally
        let manager = DanaBLEManager(faultInjector: nil)
        
        let pump = DiscoveredDanaPump(
            id: "test-001",
            name: "Dana-i",
            rssi: -50
        )
        
        try await manager.connect(to: pump)
        let state = await manager.state
        #expect(state == .ready)
        
        await manager.disconnect()
    }
}

// MARK: - Dana Delivery Tests (PUMP-DELIVERY-007/008)

@Suite("Dana Delivery Tests", .serialized)
struct DanaDeliveryTests {
    
    // MARK: - Helper
    
    private func createConnectedManager() async throws -> DanaBLEManager {
        let manager = DanaBLEManager()
        let pump = DiscoveredDanaPump(
            id: "test-delivery",
            name: "Dana-i",
            rssi: -50
        )
        try await manager.connect(to: pump)
        return manager
    }
    
    // MARK: - Bolus Tests
    
    @Test("Deliver bolus with valid amount")
    func deliverBolusValid() async throws {
        let manager = try await createConnectedManager()
        
        let startTime = try await manager.deliverBolus(units: 1.5)
        
        #expect(startTime > Date.distantPast)
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus validates amount not negative")
    func deliverBolusValidatesNegative() async throws {
        let manager = try await createConnectedManager()
        
        do {
            _ = try await manager.deliverBolus(units: -1.0)
            Issue.record("Should have thrown for negative amount")
        } catch {
            if case DanaBLEError.invalidBolusAmount(_, _) = error {
                // Expected
            } else {
                Issue.record("Expected invalidBolusAmount, got: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus validates amount not above max")
    func deliverBolusValidatesMax() async throws {
        let manager = try await createConnectedManager()
        
        do {
            _ = try await manager.deliverBolus(units: 30.0)  // Above max of 25
            Issue.record("Should have thrown for excessive amount")
        } catch {
            if case DanaBLEError.invalidBolusAmount(_, _) = error {
                // Expected
            } else {
                Issue.record("Expected invalidBolusAmount, got: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus requires connected state")
    func deliverBolusRequiresConnection() async throws {
        let manager = DanaBLEManager()
        // Not connected
        
        do {
            _ = try await manager.deliverBolus(units: 1.0)
            Issue.record("Should have thrown for not connected")
        } catch {
            if case DanaBLEError.notConnected = error {
                // Expected
            } else {
                Issue.record("Expected notConnected, got: \(error)")
            }
        }
    }
    
    @Test("Cancel bolus sends stop command")
    func cancelBolus() async throws {
        let manager = try await createConnectedManager()
        
        // Start a bolus first
        _ = try await manager.deliverBolus(units: 2.0)
        
        // Cancel it
        try await manager.cancelBolus()
        
        // No error means success
        await manager.disconnect()
    }
    
    // MARK: - Temp Basal Tests
    
    @Test("Set temp basal with valid parameters")
    func setTempBasalValid() async throws {
        let manager = try await createConnectedManager()
        
        let startTime = try await manager.setTempBasal(percent: 150, durationMinutes: 60)
        
        #expect(startTime > Date.distantPast)
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal validates percent range")
    func setTempBasalValidatesPercent() async throws {
        let manager = try await createConnectedManager()
        
        // Test percent too high
        do {
            _ = try await manager.setTempBasal(percent: 250, durationMinutes: 60)
            Issue.record("Should have thrown for percent > 200")
        } catch {
            if case DanaBLEError.invalidTempBasal(_, _, _) = error {
                // Expected
            } else {
                Issue.record("Expected invalidTempBasal, got: \(error)")
            }
        }
        
        // Test negative percent
        do {
            _ = try await manager.setTempBasal(percent: -10, durationMinutes: 60)
            Issue.record("Should have thrown for negative percent")
        } catch {
            if case DanaBLEError.invalidTempBasal(_, _, _) = error {
                // Expected
            } else {
                Issue.record("Expected invalidTempBasal, got: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal validates duration")
    func setTempBasalValidatesDuration() async throws {
        let manager = try await createConnectedManager()
        
        // Test duration too short
        do {
            _ = try await manager.setTempBasal(percent: 100, durationMinutes: 5)
            Issue.record("Should have thrown for duration < 15 min")
        } catch {
            if case DanaBLEError.invalidTempBasal(_, _, _) = error {
                // Expected
            } else {
                Issue.record("Expected invalidTempBasal, got: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal requires connected state")
    func setTempBasalRequiresConnection() async throws {
        let manager = DanaBLEManager()
        // Not connected
        
        do {
            _ = try await manager.setTempBasal(percent: 150, durationMinutes: 60)
            Issue.record("Should have thrown for not connected")
        } catch {
            if case DanaBLEError.notConnected = error {
                // Expected
            } else {
                Issue.record("Expected notConnected, got: \(error)")
            }
        }
    }
    
    @Test("Cancel temp basal sends cancel command")
    func cancelTempBasal() async throws {
        let manager = try await createConnectedManager()
        
        // Set temp basal first
        _ = try await manager.setTempBasal(percent: 150, durationMinutes: 60)
        
        // Cancel it
        try await manager.cancelTempBasal()
        
        // No error means success
        await manager.disconnect()
    }
    
    // MARK: - Suspend/Resume Tests
    
    @Test("Suspend delivery returns start time")
    func suspendDelivery() async throws {
        let manager = try await createConnectedManager()
        
        let suspendTime = try await manager.suspendDelivery()
        
        #expect(suspendTime > Date.distantPast)
        
        await manager.disconnect()
    }
    
    @Test("Resume delivery returns start time")
    func resumeDelivery() async throws {
        let manager = try await createConnectedManager()
        
        // Suspend first
        _ = try await manager.suspendDelivery()
        
        // Resume
        let resumeTime = try await manager.resumeDelivery()
        
        #expect(resumeTime > Date.distantPast)
        
        await manager.disconnect()
    }
    
    @Test("Suspend requires connected state")
    func suspendRequiresConnection() async throws {
        let manager = DanaBLEManager()
        // Not connected
        
        do {
            _ = try await manager.suspendDelivery()
            Issue.record("Should have thrown for not connected")
        } catch {
            if case DanaBLEError.notConnected = error {
                // Expected
            } else {
                Issue.record("Expected notConnected, got: \(error)")
            }
        }
    }
    
    @Test("Resume requires connected state")
    func resumeRequiresConnection() async throws {
        let manager = DanaBLEManager()
        // Not connected
        
        do {
            _ = try await manager.resumeDelivery()
            Issue.record("Should have thrown for not connected")
        } catch {
            if case DanaBLEError.notConnected = error {
                // Expected
            } else {
                Issue.record("Expected notConnected, got: \(error)")
            }
        }
    }
}

// MARK: - Dana Bolus Speed Tests

@Suite("Dana Bolus Speed")
struct DanaBolusSpeedTests {
    
    @Test("Speed display names are correct")
    func speedDisplayNames() {
        #expect(DanaBolusSpeed.speed12.displayName == "12 sec/U")
        #expect(DanaBolusSpeed.speed30.displayName == "30 sec/U")
        #expect(DanaBolusSpeed.speed60.displayName == "60 sec/U")
    }
    
    @Test("Speed raw values are correct")
    func speedRawValues() {
        #expect(DanaBolusSpeed.speed12.rawValue == 0)
        #expect(DanaBolusSpeed.speed30.rawValue == 1)
        #expect(DanaBolusSpeed.speed60.rawValue == 2)
    }
    
    @Test("Duration calculation is accurate")
    func durationCalculation() {
        let units = 2.0
        
        #expect(DanaBolusSpeed.speed12.duration(forUnits: units) == 24.0)  // 12 * 2
        #expect(DanaBolusSpeed.speed30.duration(forUnits: units) == 60.0)  // 30 * 2
        #expect(DanaBolusSpeed.speed60.duration(forUnits: units) == 120.0) // 60 * 2
    }
}

// MARK: - Dana Error Code Tests

@Suite("Dana Bolus Error Codes")
struct DanaBolusErrorTests {
    
    @Test("Error code descriptions")
    func errorCodeDescriptions() {
        #expect(DanaBolusError.description(for: 0x01).contains("suspended"))
        #expect(DanaBolusError.description(for: 0x04).contains("timeout"))
        #expect(DanaBolusError.description(for: 0x10).contains("Max bolus"))
        #expect(DanaBolusError.description(for: 0x20).contains("Command"))
        #expect(DanaBolusError.description(for: 0x40).contains("speed"))
        #expect(DanaBolusError.description(for: 0x80).contains("Insulin limit"))
        #expect(DanaBolusError.description(for: 0xFF).contains("Unknown"))
    }
}
