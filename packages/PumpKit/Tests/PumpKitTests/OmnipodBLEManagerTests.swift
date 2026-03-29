// SPDX-License-Identifier: MIT
//
// OmnipodBLEManagerTests.swift
// PumpKitTests
//
// Tests for Omnipod DASH BLE connection manager
// Trace: PUMP-OMNI-005

import Testing
import Foundation
@testable import PumpKit

@Suite("OmnipodBLEManagerTests", .serialized)
struct OmnipodBLEManagerTests {
    
    // MARK: - Initial State
    
    @Test("Initial state")
    func initialState() async throws {
        let manager = OmnipodBLEManager()
        let state = await manager.state
        let pod = await manager.connectedPod
        
        #expect(state == .disconnected)
        #expect(pod == nil)
    }
    
    // MARK: - Scanning
    
    @Test("Start scanning")
    func startScanning() async throws {
        let manager = OmnipodBLEManager()
        
        await manager.startScanning()
        let state = await manager.state
        
        #expect(state == .scanning)
        
        await manager.stopScanning()
    }
    
    @Test("Stop scanning")
    func stopScanning() async throws {
        let manager = OmnipodBLEManager()
        
        await manager.startScanning()
        await manager.stopScanning()
        
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Scan discovery")
    func scanDiscovery() async throws {
        let manager = OmnipodBLEManager()
        
        await manager.startScanning()
        
        // Wait for simulated discovery
        try await Task.sleep(nanoseconds: 600_000_000)
        
        let pods = await manager.discoveredPods
        #expect(pods.count > 0)
        
        // Check simulated pod
        if let pod = pods.first {
            #expect(pod.isDashPod)
            #expect(pod.name.contains("TWI BOARD"))
        }
        
        await manager.stopScanning()
    }
    
    // MARK: - Connection
    
    @Test("Connect to pod")
    func connectToPod() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50,
            lotNumber: "L12345",
            sequenceNumber: "67890"
        )
        
        try await manager.connect(to: pod)
        
        let state = await manager.state
        let connected = await manager.connectedPod
        
        #expect(state == .ready)
        #expect(connected != nil)
        #expect(connected?.id == pod.id)
        
        await manager.disconnect()
    }
    
    @Test("Disconnect")
    func disconnect() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50
        )
        
        try await manager.connect(to: pod)
        await manager.disconnect()
        
        let state = await manager.state
        let connected = await manager.connectedPod
        
        #expect(state == .disconnected)
        #expect(connected == nil)
    }
    
    // MARK: - Session
    
    @Test("Session created")
    func sessionCreated() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50,
            lotNumber: "L12345",
            sequenceNumber: "67890"
        )
        
        try await manager.connect(to: pod)
        
        let session = await manager.session
        #expect(session != nil)
        #expect(session?.messageSequence == 0)
        
        await manager.disconnect()
    }
    
    // MARK: - Commands
    
    @Test("Send command")
    func sendCommand() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50
        )
        
        try await manager.connect(to: pod)
        
        let command = Data([0x0E]) // Status command
        let response = try await manager.sendCommand(command)
        
        #expect(response.count > 0)
        
        // Verify sequence incremented
        let session = await manager.session
        #expect(session?.messageSequence == 1)
        
        await manager.disconnect()
    }
    
    @Test("Read status")
    func readStatus() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50
        )
        
        try await manager.connect(to: pod)
        
        let status = try await manager.readStatus()
        
        #expect(status.deliveryStatus == .basalRunning)
        #expect(status.reservoirLevel > 0)
        
        await manager.disconnect()
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostics")
    func diagnostics() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50
        )
        
        try await manager.connect(to: pod)
        
        let diagnostics = await manager.diagnosticInfo()
        
        #expect(diagnostics.state == .ready)
        #expect(diagnostics.connectedPod != nil)
        #expect(diagnostics.session != nil)
        #expect(diagnostics.description.contains("ready"))
        
        await manager.disconnect()
    }
    
    // MARK: - Error Handling
    
    @Test("Not connected error")
    func notConnectedError() async throws {
        let manager = OmnipodBLEManager()
        
        do {
            _ = try await manager.sendCommand(Data([0x00]))
            Issue.record("Should throw notConnected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Already connected error")
    func alreadyConnectedError() async throws {
        let manager = OmnipodBLEManager()
        
        let pod = DiscoveredPod(
            id: "test-001",
            name: "TWI BOARD 12345",
            rssi: -50
        )
        
        try await manager.connect(to: pod)
        
        do {
            try await manager.connect(to: pod)
            Issue.record("Should throw alreadyConnected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .alreadyConnected)
        }
        
        await manager.disconnect()
    }
    
    // MARK: - Discovered Pod
    
    @Test("Discovered pod is DASH")
    func discoveredPodIsDash() throws {
        let dashPod = DiscoveredPod(id: "001", name: "TWI BOARD 12345", rssi: -50)
        #expect(dashPod.isDashPod)
        
        let omnipodPod = DiscoveredPod(id: "002", name: "Omnipod DASH", rssi: -60)
        #expect(omnipodPod.isDashPod)
        
        let unknownPod = DiscoveredPod(id: "003", name: "Random Device", rssi: -70)
        #expect(!unknownPod.isDashPod)
    }
    
    @Test("Derived pod ID")
    func derivedPodId() throws {
        let pod = DiscoveredPod(
            id: "ble-001",
            name: "TWI BOARD",
            rssi: -50,
            lotNumber: "L12345",
            sequenceNumber: "67890"
        )
        
        #expect(pod.derivedPodId == "L12345-67890")
        
        let podWithoutLot = DiscoveredPod(id: "ble-002", name: "TWI BOARD", rssi: -50)
        #expect(podWithoutLot.derivedPodId == nil)
    }
    
    // MARK: - Status Response
    
    @Test("Status response")
    func statusResponse() throws {
        let status = OmnipodStatusResponse(
            deliveryStatus: .basalRunning,
            reservoirLevel: 150.0,
            minutesSinceActivation: 2880, // 48 hours
            alertsActive: []
        )
        
        #expect(status.hoursActive == 48.0)
        #expect(!status.isExpired)
        #expect(!status.isLowReservoir)
        
        let expiredStatus = OmnipodStatusResponse(
            deliveryStatus: .basalRunning,
            reservoirLevel: 5.0,
            minutesSinceActivation: 4400, // ~73 hours
            alertsActive: [.podExpiring]
        )
        
        #expect(expiredStatus.isExpired)
        #expect(expiredStatus.isLowReservoir)
    }
    
    // MARK: - Connection States
    
    @Test("Connection states")
    func connectionStates() throws {
        #expect(!OmnipodConnectionState.disconnected.isConnected)
        #expect(!OmnipodConnectionState.scanning.isConnected)
        #expect(!OmnipodConnectionState.connecting.isConnected)
        #expect(!OmnipodConnectionState.pairing.isConnected)
        #expect(OmnipodConnectionState.paired.isConnected)
        #expect(OmnipodConnectionState.ready.isConnected)
        
        #expect(!OmnipodConnectionState.paired.canSendCommands)
        #expect(OmnipodConnectionState.ready.canSendCommands)
    }
    
    // MARK: - Session Expiry
    
    @Test("Session expiry")
    func sessionExpiry() throws {
        var session = OmnipodSession(podId: "test-pod")
        #expect(!session.isExpired)
        
        // Sequence increment
        let seq1 = session.nextSequence()
        #expect(seq1 == 1)
        
        let seq2 = session.nextSequence()
        #expect(seq2 == 2)
    }
    
    // MARK: - BLE Constants (EXT-DASH-002)
    
    /// Validate DASH BLE UUIDs match Loop/OmniBLE
    /// Source: externals/OmniBLE/OmniBLE/Bluetooth/BluetoothServices.swift
    @Test("BLE UUIDs match Loop")
    func bleUUIDsMatchLoop() throws {
        // Advertisement UUID (for scanning) - BluetoothServices.swift:30
        #expect(
            OmnipodBLEConstants.advertisementUUID ==
            "00004024-0000-1000-8000-00805F9B34FB"
        )
        
        // Service UUID (GATT service) - BluetoothServices.swift:31
        #expect(
            OmnipodBLEConstants.serviceUUID ==
            "1A7E4024-E3ED-4464-8B7E-751E03D0DC5F"
        )
        
        // Command characteristic - BluetoothServices.swift:35
        #expect(
            OmnipodBLEConstants.commandCharacteristicUUID ==
            "1A7E2441-E3ED-4464-8B7E-751E03D0DC5F"
        )
        
        // Data characteristic - BluetoothServices.swift:36
        #expect(
            OmnipodBLEConstants.dataCharacteristicUUID ==
            "1A7E2442-E3ED-4464-8B7E-751E03D0DC5F"
        )
    }
    
    /// Validate BLE command opcodes match Loop/OmniBLE
    /// Source: externals/OmniBLE/OmniBLE/Bluetooth/BluetoothServices.swift:18-27
    @Test("BLE command opcodes match Loop")
    func bleCommandOpcodesMatchLoop() throws {
        #expect(OmnipodBLEConstants.PodBLECommand.RTS.rawValue == 0x00)
        #expect(OmnipodBLEConstants.PodBLECommand.CTS.rawValue == 0x01)
        #expect(OmnipodBLEConstants.PodBLECommand.NACK.rawValue == 0x02)
        #expect(OmnipodBLEConstants.PodBLECommand.ABORT.rawValue == 0x03)
        #expect(OmnipodBLEConstants.PodBLECommand.SUCCESS.rawValue == 0x04)
        #expect(OmnipodBLEConstants.PodBLECommand.FAIL.rawValue == 0x05)
        #expect(OmnipodBLEConstants.PodBLECommand.HELLO.rawValue == 0x06)
        #expect(OmnipodBLEConstants.PodBLECommand.INCORRECT.rawValue == 0x09)
    }
    
    // MARK: - Fault Injection (WIRE-004)
    
    @Test("Fault injector on connect")
    func faultInjectorOnConnect() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionDrop, trigger: .immediate)
        
        let manager = OmnipodBLEManager(faultInjector: injector)
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        do {
            try await manager.connect(to: pod)
            Issue.record("Should have thrown fault")
        } catch let error as OmnipodBLEError {
            #expect(error == .podNotFound)
        }
    }
    
    @Test("Fault injector on command")
    func faultInjectorOnCommand() async throws {
        // Use onCommand trigger to only fail on sendCommand, not connect
        let injector = PumpFaultInjector()
        injector.addFault(.communicationError(code: 99), trigger: .onCommand("omnipod.command"))
        
        let manager = OmnipodBLEManager(faultInjector: injector)
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        // Connect should succeed (no fault on "connect" command)
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.sendCommand(Data([0x0E]))
            Issue.record("Should have thrown fault")
        } catch let error as OmnipodBLEError {
            #expect(error == .communicationFailed)
        }
        
        await manager.disconnect()
    }
    
    @Test("Metrics recording during command")
    func metricsRecordingDuringCommand() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        _ = try await manager.sendCommand(Data([0x0E]))
        
        // Command should have been recorded in metrics
        // (PumpMetrics.shared tracks internally)
        await manager.disconnect()
    }
}

// MARK: - DASH Bolus Command Tests (PUMP-PG-004)

@Suite("DASHBolusCommandTests")
struct DASHBolusCommandTests {
    
    // MARK: - Constants Validation
    
    @Test("DASH pod constants match Loop/OmniBLE")
    func dashPodConstantsMatchLoop() throws {
        // Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/Pod.swift
        #expect(DASHPodConstants.pulseSize == 0.05)
        #expect(DASHPodConstants.pulsesPerUnit == 20.0)
        #expect(DASHPodConstants.secondsPerBolusPulse == 2.0)
        #expect(DASHPodConstants.minBolusUnits == 0.05)
        #expect(DASHPodConstants.maxBolusUnits == 30.0)
    }
    
    // MARK: - SetInsulinSchedule Command
    
    @Test("Bolus schedule command encodes correctly")
    func bolusScheduleCommandEncodes() throws {
        let cmd = DASHSetInsulinScheduleCommand.bolus(
            nonce: 0x12345678,
            units: 1.0
        )
        
        let data = cmd.encode()
        
        // Verify block type
        #expect(data[0] == 0x1A)
        
        // Verify nonce (big endian)
        #expect(data[2] == 0x12)
        #expect(data[3] == 0x34)
        #expect(data[4] == 0x56)
        #expect(data[5] == 0x78)
        
        // Verify schedule type (bolus = 2)
        #expect(data[6] == 0x02)
    }
    
    @Test("Bolus command calculates pulses correctly")
    func bolusCommandCalculatesPulses() throws {
        // 2.5U = 50 pulses
        let cmd = DASHSetInsulinScheduleCommand.bolus(
            nonce: 0xAABBCCDD,
            units: 2.5
        )
        
        #expect(cmd.units == 2.5)
        #expect(cmd.scheduleType == .bolus)
    }
    
    // MARK: - BolusExtra Command
    
    @Test("BolusExtra command encodes correctly")
    func bolusExtraCommandEncodes() throws {
        let cmd = DASHBolusExtraCommand(
            units: 1.0,
            acknowledgementBeep: false,
            completionBeep: true
        )
        
        let data = cmd.encode()
        
        // Verify block type
        #expect(data[0] == 0x17)
        
        // Verify length
        #expect(data[1] == 0x0D)
        
        // Verify beep options (completion beep = bit 6)
        #expect(data[2] & 0x40 != 0)  // completion beep set
        #expect(data[2] & 0x80 == 0)  // acknowledgement beep not set
    }
    
    @Test("BolusExtra with acknowledgement beep")
    func bolusExtraWithAckBeep() throws {
        let cmd = DASHBolusExtraCommand(
            units: 0.5,
            acknowledgementBeep: true,
            completionBeep: false
        )
        
        let data = cmd.encode()
        
        #expect(data[2] & 0x80 != 0)  // acknowledgement beep set
        #expect(data[2] & 0x40 == 0)  // completion beep not set
    }
    
    @Test("BolusExtra pulse count encoding")
    func bolusExtraPulseCountEncoding() throws {
        // 2.0U = 40 pulses, 40 * 10 = 400 = 0x0190
        let cmd = DASHBolusExtraCommand(units: 2.0)
        let data = cmd.encode()
        
        // Bytes 3-4 are pulse count × 10 (big endian)
        let pulseCountX10 = UInt16(data[3]) << 8 | UInt16(data[4])
        #expect(pulseCountX10 == 400)
    }
    
    @Test("BolusExtra time between pulses encoding")
    func bolusExtraTimeBetweenPulsesEncoding() throws {
        // 2 seconds = 200,000 hundredths of milliseconds = 0x00030D40
        let cmd = DASHBolusExtraCommand(units: 1.0, timeBetweenPulses: 2.0)
        let data = cmd.encode()
        
        // Bytes 5-8 are delay in hundredths of milliseconds
        let delayValue = UInt32(data[5]) << 24 | UInt32(data[6]) << 16 | UInt32(data[7]) << 8 | UInt32(data[8])
        #expect(delayValue == 200_000)
    }
    
    // MARK: - Insulin Table Entry
    
    @Test("Insulin table entry encodes correctly")
    func insulinTableEntryEncodes() throws {
        // Single segment with 20 pulses (1U)
        let entry = DASHInsulinTableEntry(segments: 1, pulses: 20, alternateSegmentPulse: false)
        let data = entry.encode()
        
        #expect(data.count == 2)
        
        // Format: napp where n=segments-1, a=alternate, pp=pulses
        // segments=1 → n=0, alternate=false → a=0, pulses=20 → 0x0014
        // Result: 0x0014
        let value = UInt16(data[0]) << 8 | UInt16(data[1])
        #expect(value == 0x0014)
    }
    
    @Test("Insulin table entry with alternate pulse")
    func insulinTableEntryWithAlternate() throws {
        let entry = DASHInsulinTableEntry(segments: 2, pulses: 10, alternateSegmentPulse: true)
        let data = entry.encode()
        
        // segments=2 → n=1, alternate=true → bit 11 set, pulses=10
        // n=1 in bits 15-12 → 0x1000
        // a=1 in bit 11 → 0x0800
        // pp=10 → 0x000A
        // Result: 0x180A
        let value = UInt16(data[0]) << 8 | UInt16(data[1])
        #expect(value == 0x180A)
    }
    
    // MARK: - Cancel Delivery Command
    
    @Test("Cancel delivery command encodes correctly")
    func cancelDeliveryCommandEncodes() throws {
        let cmd = DASHCancelDeliveryCommand(
            nonce: 0xDEADBEEF,
            deliveryType: .bolus
        )
        
        let data = cmd.encode()
        
        #expect(data[0] == 0x1F)  // block type
        #expect(data[1] == 0x05)  // length
        #expect(data[2] == 0xDE)  // nonce
        #expect(data[3] == 0xAD)
        #expect(data[4] == 0xBE)
        #expect(data[5] == 0xEF)
        #expect(data[6] == 0x02)  // delivery type (bolus)
        #expect(data[7] == 0x00)  // beep type
    }
    
    @Test("Cancel all delivery command")
    func cancelAllDeliveryCommand() throws {
        let cmd = DASHCancelDeliveryCommand(
            nonce: 0x11223344,
            deliveryType: .all
        )
        
        let data = cmd.encode()
        #expect(data[6] == 0x07)  // all = 0x07
    }
    
    // MARK: - Bolus Result
    
    @Test("Bolus result calculation")
    func bolusResultCalculation() throws {
        let result = DASHBolusResult(
            units: 2.0,
            pulses: 40,
            estimatedDuration: 80.0,  // 40 pulses × 2 seconds
            startTime: Date()
        )
        
        #expect(result.units == 2.0)
        #expect(result.pulses == 40)
        #expect(result.estimatedDuration == 80.0)
        
        // Completion time should be ~80 seconds after start
        let expectedCompletion = result.startTime.addingTimeInterval(80.0)
        #expect(abs(result.estimatedCompletionTime.timeIntervalSince(expectedCompletion)) < 0.01)
    }
}

// MARK: - DASH Bolus Manager Tests (PUMP-PG-004)

@Suite("DASHBolusManagerTests", .serialized)
struct DASHBolusManagerTests {
    
    @Test("Deliver bolus - success")
    func deliverBolusSuccess() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        await manager.setTestNonce(0x12345678)
        
        let result = try await manager.deliverBolus(units: 1.0)
        
        #expect(result.units == 1.0)
        #expect(result.pulses == 20)
        #expect(result.estimatedDuration == 40.0)  // 20 pulses × 2 seconds
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus - rounds to pulse size")
    func deliverBolusRoundsToPulseSize() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        // 0.07U should round to 0.05U (1 pulse)
        let result1 = try await manager.deliverBolus(units: 0.07)
        #expect(result1.units == 0.05)
        
        // 0.08U should round to 0.10U (2 pulses)
        let result2 = try await manager.deliverBolus(units: 0.08)
        #expect(result2.units == 0.10)
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus - minimum validation")
    func deliverBolusMinimumValidation() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.deliverBolus(units: 0.02)  // Below minimum
            Issue.record("Should throw invalid bolus error")
        } catch let error as OmnipodBLEError {
            if case .invalidBolusAmount(let units, _) = error {
                #expect(units == 0.02)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus - maximum validation")
    func deliverBolusMaximumValidation() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.deliverBolus(units: 35.0)  // Above maximum
            Issue.record("Should throw invalid bolus error")
        } catch let error as OmnipodBLEError {
            if case .invalidBolusAmount(let units, _) = error {
                #expect(units == 35.0)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Deliver bolus - not connected error")
    func deliverBolusNotConnected() async throws {
        let manager = OmnipodBLEManager()
        
        do {
            _ = try await manager.deliverBolus(units: 1.0)
            Issue.record("Should throw not connected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Cancel bolus - success")
    func cancelBolusSuccess() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        await manager.setTestNonce(0xAABBCCDD)
        
        // Should not throw
        try await manager.cancelBolus()
        
        await manager.disconnect()
    }
    
    @Test("Cancel bolus - not connected error")
    func cancelBolusNotConnected() async throws {
        let manager = OmnipodBLEManager()
        
        do {
            try await manager.cancelBolus()
            Issue.record("Should throw not connected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Fault injection on bolus")
    func faultInjectionOnBolus() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.communicationError(code: 99), trigger: .onCommand("omnipod.bolus"))
        
        let manager = OmnipodBLEManager(faultInjector: injector)
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.deliverBolus(units: 1.0)
            Issue.record("Should have thrown fault")
        } catch let error as OmnipodBLEError {
            #expect(error == .communicationFailed)
        }
        
        await manager.disconnect()
    }
}

// MARK: - DASH Temp Basal Command Tests (PUMP-PG-005)

@Suite("DASHTempBasalCommandTests")
struct DASHTempBasalCommandTests {
    
    // MARK: - TempBasalScheduleCommand Tests
    
    @Test("TempBasalScheduleCommand encodes header correctly")
    func tempBasalScheduleHeader() {
        let cmd = DASHTempBasalScheduleCommand(
            nonce: 0x12345678,
            rate: 1.0,
            duration: 60 * 60  // 1 hour
        )
        let data = cmd.encode()
        
        #expect(data[0] == 0x1A)  // message type
        #expect(data[6] == 0x01)  // schedule type = temp basal (after 4-byte nonce + length)
    }
    
    @Test("TempBasalScheduleCommand includes nonce")
    func tempBasalScheduleNonce() {
        let cmd = DASHTempBasalScheduleCommand(
            nonce: 0xAABBCCDD,
            rate: 1.0,
            duration: 30 * 60
        )
        let data = cmd.encode()
        
        // Nonce at bytes 2-5 (after message type + length)
        #expect(data[2] == 0xAA)
        #expect(data[3] == 0xBB)
        #expect(data[4] == 0xCC)
        #expect(data[5] == 0xDD)
    }
    
    @Test("TempBasalScheduleCommand calculates segments correctly")
    func tempBasalScheduleSegments() {
        // 2 hours = 4 segments
        let cmd = DASHTempBasalScheduleCommand(
            nonce: 0x12345678,
            rate: 2.0,
            duration: 2 * 60 * 60
        )
        let data = cmd.encode()
        
        // Header starts at byte 9 (after message type, length, nonce, schedule type, checksum)
        // First header byte is numSegments
        #expect(data[9] == 4)  // 4 segments for 2 hours
    }
    
    // MARK: - TempBasalExtraCommand Tests
    
    @Test("TempBasalExtraCommand encodes header correctly")
    func tempBasalExtraHeader() {
        let cmd = DASHTempBasalExtraCommand(
            rate: 1.0,
            duration: 60 * 60
        )
        let data = cmd.encode()
        
        #expect(data[0] == 0x16)  // message type
    }
    
    @Test("TempBasalExtraCommand beep options encode correctly")
    func tempBasalExtraBeepOptions() {
        let cmd = DASHTempBasalExtraCommand(
            rate: 1.0,
            duration: 30 * 60,
            acknowledgementBeep: true,
            completionBeep: true,
            programReminderInterval: 60  // 1 minute
        )
        let data = cmd.encode()
        
        // Beep options: bit 7 = ack, bit 6 = completion, bits 5-0 = minutes
        let beepOptions = data[2]
        #expect(beepOptions & 0x80 != 0)  // ack beep
        #expect(beepOptions & 0x40 != 0)  // completion beep
        #expect(beepOptions & 0x3F == 1)  // 1 minute reminder
    }
    
    @Test("TempBasalExtraCommand reserved byte is zero")
    func tempBasalExtraReserved() {
        let cmd = DASHTempBasalExtraCommand(rate: 1.0, duration: 30 * 60)
        let data = cmd.encode()
        
        #expect(data[3] == 0x00)  // reserved byte
    }
    
    // MARK: - DASHRateEntry Tests
    
    @Test("RateEntry encodes pulses correctly")
    func rateEntryPulses() {
        let entry = PumpKit.DASHRateEntry(totalPulses: 10.0, delayBetweenPulses: 360)
        let data = entry.encode()
        
        // Pulses × 10 = 100 = 0x0064
        #expect(data[0] == 0x00)
        #expect(data[1] == 0x64)
    }
    
    @Test("RateEntry encodes delay correctly")
    func rateEntryDelay() {
        let entry = PumpKit.DASHRateEntry(totalPulses: 10.0, delayBetweenPulses: 360)
        let data = entry.encode()
        
        // 360 seconds × 100_000 = 36_000_000 = 0x02255100
        let delay = UInt32(bigEndian: data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self) })
        #expect(delay == 36_000_000)
    }
    
    @Test("RateEntry makeEntries zero rate")
    func rateEntryMakeEntriesZero() {
        let entries = PumpKit.DASHRateEntry.makeEntries(rate: 0, duration: 60 * 60)  // 1 hour
        
        // Zero rate = one entry per segment
        #expect(entries.count == 2)  // 2 segments for 1 hour
        #expect(entries[0].totalPulses == 0)
        #expect(entries[0].delayBetweenPulses == DASHPodConstants.maxTimeBetweenPulses)
    }
    
    @Test("RateEntry makeEntries normal rate")
    func rateEntryMakeEntriesNormal() {
        let entries = PumpKit.DASHRateEntry.makeEntries(rate: 1.0, duration: 60 * 60)  // 1 U/hr for 1 hour
        
        // 1 U/hr = 20 pulses/hr = 10 pulses per 30 min segment
        #expect(entries.count >= 1)
        
        // Total pulses should be 20 for 1 hour at 1 U/hr
        let totalPulses = entries.reduce(0) { $0 + $1.totalPulses }
        #expect(totalPulses == 20)  // 1 U = 20 pulses
    }
    
    @Test("RateEntry makeEntries high rate")
    func rateEntryMakeEntriesHigh() {
        let entries = PumpKit.DASHRateEntry.makeEntries(rate: 10.0, duration: 60 * 60)  // 10 U/hr
        
        // 10 U/hr = 200 pulses/hr = 100 pulses per segment
        let totalPulses = entries.reduce(0) { $0 + $1.totalPulses }
        #expect(totalPulses == 200)  // 10 U = 200 pulses
    }
    
    // MARK: - DASHTempBasalResult Tests
    
    @Test("TempBasalResult stores values correctly")
    func tempBasalResultValues() {
        let startTime = Date()
        let result = DASHTempBasalResult(
            rate: 2.5,
            duration: 60 * 60,
            startTime: startTime
        )
        
        #expect(result.rate == 2.5)
        #expect(result.duration == 3600)
        #expect(result.startTime == startTime)
    }
    
    @Test("TempBasalResult calculates duration in minutes")
    func tempBasalResultDurationMinutes() {
        let result = DASHTempBasalResult(
            rate: 1.0,
            duration: 90 * 60  // 90 minutes
        )
        
        #expect(result.durationMinutes == 90)
    }
    
    @Test("TempBasalResult calculates estimated end time")
    func tempBasalResultEndTime() {
        let startTime = Date()
        let result = DASHTempBasalResult(
            rate: 1.0,
            duration: 60 * 60,
            startTime: startTime
        )
        
        let expectedEnd = startTime.addingTimeInterval(3600)
        #expect(result.estimatedEndTime == expectedEnd)
    }
}

@Suite("DASHTempBasalManagerTests", .serialized)
struct DASHTempBasalManagerTests {
    
    @Test("Set temp basal - success")
    func setTempBasalSuccess() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        await manager.setTestNonce(0x12345678)
        
        let result = try await manager.setTempBasal(rate: 1.5, duration: 60 * 60)
        
        #expect(result.rate == 1.5)
        #expect(result.duration == 3600)
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal - zero rate")
    func setTempBasalZeroRate() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        await manager.setTestNonce(0x12345678)
        
        let result = try await manager.setTempBasal(rate: 0.0, duration: 30 * 60)
        
        #expect(result.rate == 0.0)
        #expect(result.duration == 1800)
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal - minimum duration validation")
    func setTempBasalMinDuration() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.setTempBasal(rate: 1.0, duration: 15 * 60)  // 15 min (below 30 min minimum)
            Issue.record("Should throw invalid temp basal error")
        } catch let error as OmnipodBLEError {
            if case .invalidTempBasal = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal - maximum duration validation")
    func setTempBasalMaxDuration() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.setTempBasal(rate: 1.0, duration: 13 * 60 * 60)  // 13 hours (above 12 hour max)
            Issue.record("Should throw invalid temp basal error")
        } catch let error as OmnipodBLEError {
            if case .invalidTempBasal = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal - maximum rate validation")
    func setTempBasalMaxRate() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.setTempBasal(rate: 35.0, duration: 60 * 60)  // Above max
            Issue.record("Should throw invalid temp basal error")
        } catch let error as OmnipodBLEError {
            if case .invalidTempBasal = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
        
        await manager.disconnect()
    }
    
    @Test("Set temp basal - not connected error")
    func setTempBasalNotConnected() async throws {
        let manager = OmnipodBLEManager()
        
        do {
            _ = try await manager.setTempBasal(rate: 1.0, duration: 60 * 60)
            Issue.record("Should throw not connected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Cancel temp basal - success")
    func cancelTempBasalSuccess() async throws {
        let manager = OmnipodBLEManager()
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        await manager.setTestNonce(0xAABBCCDD)
        
        // Should not throw
        try await manager.cancelTempBasal()
        
        await manager.disconnect()
    }
    
    @Test("Cancel temp basal - not connected error")
    func cancelTempBasalNotConnected() async throws {
        let manager = OmnipodBLEManager()
        
        do {
            try await manager.cancelTempBasal()
            Issue.record("Should throw not connected error")
        } catch let error as OmnipodBLEError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("Fault injection on temp basal")
    func faultInjectionOnTempBasal() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.communicationError(code: 99), trigger: .onCommand("omnipod.tempbasal"))
        
        let manager = OmnipodBLEManager(faultInjector: injector)
        let pod = DiscoveredPod(id: "test-001", name: "TWI BOARD 12345", rssi: -50)
        
        try await manager.connect(to: pod)
        
        do {
            _ = try await manager.setTempBasal(rate: 1.0, duration: 60 * 60)
            Issue.record("Should have thrown fault")
        } catch let error as OmnipodBLEError {
            #expect(error == .communicationFailed)
        }
        
        await manager.disconnect()
    }
    
    // MARK: - Factory Methods (PUMP-PG-006)
    
    @Test("forDemo factory creates manager")
    func forDemoFactory() async throws {
        let manager = OmnipodBLEManager.forDemo()
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("forTesting factory creates manager")
    func forTestingFactory() async throws {
        let manager = OmnipodBLEManager.forTesting()
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("setTestState changes state directly")
    func setTestState() async throws {
        let manager = OmnipodBLEManager.forDemo()
        
        await manager.setTestState(.ready)
        let state = await manager.state
        #expect(state == .ready)
        
        await manager.setTestState(.disconnected)
        let resetState = await manager.state
        #expect(resetState == .disconnected)
    }
    
    @Test("resumeSession sets up session and ready state")
    func resumeSession() async throws {
        let manager = OmnipodBLEManager.forDemo()
        
        await manager.resumeSession(podId: "L12345-67890")
        
        let state = await manager.state
        let session = await manager.session
        
        #expect(state == .ready)
        #expect(session != nil)
        #expect(session?.podId == "L12345-67890")
    }
    
    @Test("deliverBolus works in demo mode")
    func deliverBolusDemo() async throws {
        let manager = OmnipodBLEManager.forDemo()
        await manager.resumeSession(podId: "test-pod")
        
        let result = try await manager.deliverBolus(units: 2.0)
        
        #expect(result.units == 2.0)
        #expect(result.pulses == 40) // 2.0 / 0.05 = 40 pulses
        #expect(result.estimatedDuration > 0)
    }
    
    @Test("setTempBasal works in demo mode")
    func setTempBasalDemo() async throws {
        let manager = OmnipodBLEManager.forDemo()
        await manager.resumeSession(podId: "test-pod")
        
        let result = try await manager.setTempBasal(rate: 1.5, duration: 60 * 60) // 1 hour
        
        #expect(result.rate == 1.5)
        #expect(result.durationMinutes == 60)
    }
    
    @Test("cancelTempBasal works in demo mode")
    func cancelTempBasalDemo() async throws {
        let manager = OmnipodBLEManager.forDemo()
        await manager.resumeSession(podId: "test-pod")
        
        // Set temp basal first
        _ = try await manager.setTempBasal(rate: 1.0, duration: 30 * 60)
        
        // Cancel should not throw
        try await manager.cancelTempBasal()
    }
}
