// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosBLEManagerTests.swift
// PumpKitTests
//
// Unit tests for ErosBLEManager Omnipod Eros RF communication.
// Trace: EROS-IMPL-002
//
// Tests cover:
// - Connection state management
// - Session handling
// - Packet building
// - Response parsing
// - Error handling

import Testing
import Foundation
@testable import PumpKit

// MARK: - ErosBLEManager Tests

@Suite("Eros BLE Manager Tests", .serialized)
struct ErosBLEManagerTests {
    
    // MARK: - Initialization Tests
    
    @Test("Initialization sets disconnected state")
    func initialization() async {
        let manager = ErosBLEManager.forTesting()
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("forTesting sets test mode")
    func forTesting() async {
        let manager = ErosBLEManager.forTesting()
        let mode = await manager.simulationMode
        #expect(mode == .test)
    }
    
    @Test("forDemo sets demo mode")
    func forDemo() async {
        let manager = ErosBLEManager.forDemo()
        let mode = await manager.simulationMode
        #expect(mode == .demo)
    }
    
    // MARK: - State Tests
    
    @Test("Connection state isConnected flag")
    func connectionStateIsConnected() {
        #expect(!ErosConnectionState.disconnected.isConnected)
        #expect(!ErosConnectionState.connectingToBridge.isConnected)
        #expect(!ErosConnectionState.bridgeConnected.isConnected)
        #expect(!ErosConnectionState.tuning.isConnected)
        #expect(!ErosConnectionState.searchingForPod.isConnected)
        #expect(ErosConnectionState.paired.isConnected)
        #expect(ErosConnectionState.ready.isConnected)
        #expect(!ErosConnectionState.error.isConnected)
    }
    
    @Test("Connection state canSendCommands flag")
    func connectionStateCanSendCommands() {
        #expect(!ErosConnectionState.disconnected.canSendCommands)
        #expect(!ErosConnectionState.paired.canSendCommands)
        #expect(ErosConnectionState.ready.canSendCommands)
    }
    
    @Test("Connection state display name")
    func connectionStateDisplayName() {
        #expect(ErosConnectionState.disconnected.displayName == "Disconnected")
        #expect(ErosConnectionState.ready.displayName == "Ready")
        #expect(ErosConnectionState.tuning.displayName == "Tuning RF...")
    }
    
    // MARK: - Session Tests
    
    @Test("Session initialization")
    func sessionInit() {
        let session = ErosSession(podAddress: 0x1F01482A)
        #expect(session.podAddress == 0x1F01482A)
        #expect(session.packetSequence == 0)
        #expect(session.messageSequence == 0)
        #expect(session.isValid)
    }
    
    @Test("Session increment packet sequence")
    func sessionIncrementPacketSequence() {
        var session = ErosSession(podAddress: 0x1F01482A)
        #expect(session.packetSequence == 0)
        
        session.incrementPacketSequence()
        #expect(session.packetSequence == 1)
        
        // Test wraparound at 0x1F
        session.packetSequence = 0x1F
        session.incrementPacketSequence()
        #expect(session.packetSequence == 0)
    }
    
    @Test("Session increment message sequence")
    func sessionIncrementMessageSequence() {
        var session = ErosSession(podAddress: 0x1F01482A)
        #expect(session.messageSequence == 0)
        
        session.incrementMessageSequence()
        #expect(session.messageSequence == 1)
        
        // Test wraparound at 0x0F
        session.messageSequence = 0x0F
        session.incrementMessageSequence()
        #expect(session.messageSequence == 0)
    }
    
    // MARK: - Pod Info Tests
    
    @Test("Pod info address hex")
    func podInfoAddressHex() {
        let info = ErosPodInfo(
            address: 0x1F01482A,
            lot: 12345,
            tid: 67890,
            pmVersion: "2.7.0",
            piVersion: "2.7.0",
            reservoirLevel: 45.5,
            podProgressStatus: 9,
            faultCode: nil,
            minutesSinceActivation: 120
        )
        #expect(info.addressHex == "0x1F01482A")
    }
    
    @Test("Pod info isActive")
    func podInfoIsActive() {
        // Active progress states: 8, 9, 10
        let active = ErosPodInfo(
            address: 0, lot: 0, tid: 0,
            pmVersion: "", piVersion: "",
            reservoirLevel: nil,
            podProgressStatus: 9,
            faultCode: nil,
            minutesSinceActivation: 0
        )
        #expect(active.isActive)
        
        let inactive = ErosPodInfo(
            address: 0, lot: 0, tid: 0,
            pmVersion: "", piVersion: "",
            reservoirLevel: nil,
            podProgressStatus: 3,  // Setup
            faultCode: nil,
            minutesSinceActivation: 0
        )
        #expect(!inactive.isActive)
    }
    
    @Test("Pod info isFaulted")
    func podInfoIsFaulted() {
        let faulted = ErosPodInfo(
            address: 0, lot: 0, tid: 0,
            pmVersion: "", piVersion: "",
            reservoirLevel: nil,
            podProgressStatus: 9,
            faultCode: 0x14,
            minutesSinceActivation: 0
        )
        #expect(faulted.isFaulted)
        
        let healthy = ErosPodInfo(
            address: 0, lot: 0, tid: 0,
            pmVersion: "", piVersion: "",
            reservoirLevel: nil,
            podProgressStatus: 9,
            faultCode: nil,
            minutesSinceActivation: 0
        )
        #expect(!healthy.isFaulted)
    }
    
    // MARK: - Constants Tests
    
    @Test("Eros BLE constants")
    func erosBLEConstants() {
        #expect(ErosBLEConstants.rfFrequency == 433.91)
        #expect(ErosBLEConstants.preamble == [0xAA, 0xAA, 0xAA, 0xAA])
        #expect(ErosBLEConstants.maxRetries == 3)
        #expect(ErosBLEConstants.defaultPDMAddress == 0xFFFFFFFF)
    }
    
    // MARK: - Error Tests
    
    @Test("Eros BLE error equatable")
    func erosBLEErrorEquatable() {
        #expect(ErosBLEError.notConnected == ErosBLEError.notConnected)
        #expect(ErosBLEError.podNotPaired == ErosBLEError.podNotPaired)
        #expect(ErosBLEError.timeout == ErosBLEError.timeout)
        #expect(ErosBLEError.notConnected != ErosBLEError.timeout)
    }
    
    @Test("Eros BLE error with payload")
    func erosBLEErrorWithPayload() {
        let error1 = ErosBLEError.rfCommunicationError("test error")
        let error2 = ErosBLEError.rfCommunicationError("test error")
        let error3 = ErosBLEError.rfCommunicationError("different error")
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }
    
    // MARK: - Resume Session Tests
    
    @Test("Resume session")
    func resumeSession() async {
        let manager = ErosBLEManager.forTesting()
        
        await manager.resumeSession(
            podAddress: 0x1F01482A,
            packetSequence: 5,
            messageSequence: 3
        )
        
        let session = await manager.currentSession
        #expect(session != nil)
        #expect(session?.podAddress == 0x1F01482A)
        #expect(session?.packetSequence == 5)
        #expect(session?.messageSequence == 3)
    }
    
    // MARK: - Disconnect Tests
    
    @Test("Disconnect clears state")
    func disconnect() async {
        let manager = ErosBLEManager.forTesting()
        
        // Setup some state
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        
        // Disconnect
        await manager.disconnect()
        
        let state = await manager.state
        let session = await manager.currentSession
        
        #expect(state == .disconnected)
        #expect(session == nil)
    }
    
    // MARK: - Error When Not Connected Tests
    
    @Test("Get pod status when not paired throws error")
    func getPodStatusWhenNotPaired() async {
        let manager = ErosBLEManager.forTesting()
        
        do {
            _ = try await manager.getPodStatus()
            Issue.record("Expected error")
        } catch let error as ErosBLEError {
            #expect(error == .podNotPaired)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("Deliver bolus when not paired throws error")
    func deliverBolusWhenNotPaired() async {
        let manager = ErosBLEManager.forTesting()
        
        do {
            try await manager.deliverBolus(units: 1.0)
            Issue.record("Expected error")
        } catch let error as ErosBLEError {
            #expect(error == .podNotPaired)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("Set temp basal when not paired throws error")
    func setTempBasalWhenNotPaired() async {
        let manager = ErosBLEManager.forTesting()
        
        do {
            try await manager.setTempBasal(rate: 0.5, duration: 1800)
            Issue.record("Expected error")
        } catch let error as ErosBLEError {
            #expect(error == .podNotPaired)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("Cancel delivery when not paired throws error")
    func cancelDeliveryWhenNotPaired() async {
        let manager = ErosBLEManager.forTesting()
        
        do {
            try await manager.cancelDelivery()
            Issue.record("Expected error")
        } catch let error as ErosBLEError {
            #expect(error == .podNotPaired)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    @Test("Deactivate pod when not paired throws error")
    func deactivatePodWhenNotPaired() async {
        let manager = ErosBLEManager.forTesting()
        
        do {
            try await manager.deactivatePod()
            Issue.record("Expected error")
        } catch let error as ErosBLEError {
            #expect(error == .podNotPaired)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Observer Tests
    
    @Test("Observer add and remove")
    func observerAddAndRemove() async {
        let manager = ErosBLEManager.forTesting()
        let observerId = UUID()
        
        // Use actor to safely track count
        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }
        let counter = Counter()
        
        await manager.addObserver(observerId) { @Sendable _ in
            Task { await counter.increment() }
        }
        
        // Trigger notification via disconnect
        await manager.disconnect()
        
        // Give time for notification
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let count = await counter.getCount()
        #expect(count > 0)
        
        // Remove observer
        await manager.removeObserver(observerId)
    }
}

// MARK: - ErosPacket Integration Tests

@Suite("Eros Packet Integration Tests")
struct ErosPacketIntegrationTests {
    
    @Test("Eros packet creation for manager")
    func erosPacketCreationForManager() {
        // Test that packets can be created with addresses used by manager
        let packet = ErosPacket(
            address: 0x1F01482A,
            packetType: .pdm,
            sequenceNum: 13,
            data: Data([0x0E, 0x00])  // GetStatus
        )
        
        #expect(packet.address == 0x1F01482A)
        #expect(packet.packetType == .pdm)
        #expect(packet.sequenceNum == 13)
        #expect(packet.data.count == 2)
    }
    
    @Test("Eros packet encode decode")
    func erosPacketEncodeDecode() throws {
        let original = ErosPacket(
            address: 0x1F01482A,
            packetType: .pdm,
            sequenceNum: 7,
            data: Data([0x0E, 0x00])
        )
        
        let encoded = original.encoded()
        let decoded = try ErosPacket(encodedData: encoded)
        
        #expect(decoded.address == original.address)
        #expect(decoded.packetType == original.packetType)
        #expect(decoded.sequenceNum == original.sequenceNum)
        #expect(decoded.data == original.data)
    }
    
    @Test("Pod response packet")
    func podResponsePacket() throws {
        // Simulate a pod response packet
        let response = ErosPacket(
            address: 0x1F01482A,
            packetType: .pod,
            sequenceNum: 8,
            data: Data([0x1D, 0x09, 0x00, 0x01, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
        
        #expect(response.packetType == .pod)
        
        // Encode and decode
        let encoded = response.encoded()
        let decoded = try ErosPacket(encodedData: encoded)
        
        #expect(decoded.packetType == .pod)
        #expect(decoded.data[0] == 0x1D)  // Response type
        #expect(decoded.data[1] == 0x09)  // Progress status
    }
}

// MARK: - Eros Bolus Command Tests (PUMP-PG-001)

@Suite("Eros Bolus Command Tests")
struct ErosBolusCommandTests {
    
    // MARK: - Pod Constants Tests
    
    @Test("Pod constants match OmniKit")
    func podConstants() {
        #expect(ErosPodConstants.pulseSize == 0.05)
        #expect(ErosPodConstants.pulsesPerUnit == 20.0)
        #expect(ErosPodConstants.secondsPerBolusPulse == 2.0)
        #expect(ErosPodConstants.bolusDeliveryRate == 0.025)  // 0.05U / 2s
        #expect(ErosPodConstants.maxBolus == 30.0)
    }
    
    // MARK: - Insulin Table Entry Tests
    
    @Test("Insulin table entry for simple bolus")
    func insulinTableEntry() {
        let entry = ErosInsulinTableEntry(segments: 1, pulses: 20, alternateSegmentPulse: false)
        
        #expect(entry.segments == 1)
        #expect(entry.pulses == 20)
        #expect(!entry.alternateSegmentPulse)
        #expect(entry.checksum() == 21)  // 1 + 20
    }
    
    // MARK: - Bolus Delivery Table Tests
    
    @Test("Bolus delivery table for 1U")
    func bolusDeliveryTable1U() {
        let table = ErosBolusDeliveryTable(units: 1.0)
        
        #expect(table.entries.count == 1)
        #expect(table.entries[0].pulses == 20)  // 1U = 20 pulses
        #expect(table.numSegments() == 1)
    }
    
    @Test("Bolus delivery table for 2.5U")
    func bolusDeliveryTable2_5U() {
        let table = ErosBolusDeliveryTable(units: 2.5)
        
        #expect(table.entries.count == 1)
        #expect(table.entries[0].pulses == 50)  // 2.5U = 50 pulses
    }
    
    // MARK: - SetInsulinSchedule Command Tests
    
    @Test("SetInsulinSchedule command for bolus")
    func setInsulinScheduleCommand() {
        let command = ErosSetInsulinScheduleCommand(
            nonce: 0x12345678,
            units: 1.0
        )
        
        #expect(command.scheduleType == .bolus)
        #expect(command.units == 1.0)
        
        let data = command.data
        #expect(data[0] == 0x1A)  // Block type
        #expect(data.count > 8)   // Has header + schedule data
    }
    
    @Test("SetInsulinSchedule encodes nonce correctly")
    func setInsulinScheduleNonce() {
        let command = ErosSetInsulinScheduleCommand(
            nonce: 0xAABBCCDD,
            units: 0.5
        )
        
        let data = command.data
        
        // Nonce at bytes 2-5 (big-endian)
        #expect(data[2] == 0xAA)
        #expect(data[3] == 0xBB)
        #expect(data[4] == 0xCC)
        #expect(data[5] == 0xDD)
    }
    
    // MARK: - BolusExtra Command Tests
    
    @Test("BolusExtra command encoding")
    func bolusExtraCommand() {
        let command = ErosBolusExtraCommand(
            units: 1.5,
            acknowledgementBeep: true,
            completionBeep: true
        )
        
        let data = command.data
        
        #expect(data[0] == 0x17)  // Block type
        #expect(data[1] == 0x0D)  // Length
        #expect(data[2] & 0xC0 == 0xC0)  // Both beeps enabled
    }
    
    @Test("BolusExtra with extended bolus")
    func bolusExtraExtended() {
        let command = ErosBolusExtraCommand(
            units: 2.0,
            extendedUnits: 1.0,
            extendedDuration: 3600  // 1 hour
        )
        
        let data = command.data
        #expect(data.count == 15)  // Full command length
    }
    
    // MARK: - CancelDelivery Command Tests
    
    @Test("CancelDelivery command for bolus")
    func cancelDeliveryBolus() {
        let command = ErosCancelDeliveryCommand(
            nonce: 0x11223344,
            cancelType: .bolus
        )
        
        let data = command.data
        
        #expect(data[0] == 0x1F)  // Block type
        #expect(data[1] == 0x05)  // Length
        #expect(data[6] & 0x04 != 0)  // Bolus cancel flag
    }
    
    @Test("CancelDelivery command for all")
    func cancelDeliveryAll() {
        let command = ErosCancelDeliveryCommand(
            nonce: 0x00000000,
            cancelType: .all
        )
        
        let data = command.data
        #expect(data[6] == 0x07)  // All flags set
    }
    
    // MARK: - ErosPodInfo Tests
    
    @Test("ErosPodInfo delivery status flags")
    func podInfoDeliveryStatus() {
        // Create pod info with bolusing status
        let bolusInfo = ErosPodInfo(
            address: 0x1F01482A,
            lot: 12345,
            tid: 67890,
            pmVersion: "2.7.0",
            piVersion: "2.7.0",
            reservoirLevel: 40.0,
            podProgressStatus: 9,
            deliveryStatus: 0x04,  // Bolusing
            faultCode: nil,
            minutesSinceActivation: 100
        )
        
        #expect(bolusInfo.isBolusing)
        #expect(!bolusInfo.isTempBasalActive)
        #expect(!bolusInfo.isSuspended)
        
        // Create suspended pod info
        let suspendedInfo = ErosPodInfo(
            address: 0x1F01482A,
            lot: 12345,
            tid: 67890,
            pmVersion: "2.7.0",
            piVersion: "2.7.0",
            reservoirLevel: 40.0,
            podProgressStatus: 9,
            deliveryStatus: 0x0F,  // Suspended
            faultCode: nil,
            minutesSinceActivation: 100
        )
        
        #expect(suspendedInfo.isSuspended)
        #expect(!suspendedInfo.isBolusing)
    }
}

// MARK: - Eros Bolus Manager Tests (PUMP-PG-001)

@Suite("Eros Bolus Manager Tests", .serialized)
struct ErosBolusManagerTests {
    
    @Test("Deliver bolus requires paired pod")
    func deliverBolusRequiresPaired() async throws {
        let manager = ErosBLEManager.forTesting()
        
        do {
            try await manager.deliverBolus(units: 1.0)
            Issue.record("Should throw podNotPaired")
        } catch ErosBLEError.podNotPaired {
            // Expected
        }
    }
    
    @Test("Deliver bolus validates amount")
    func deliverBolusValidatesAmount() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        
        // Set state to ready for commands
        await manager.setTestState(.ready)
        
        // Zero amount should fail
        do {
            try await manager.deliverBolus(units: 0)
            Issue.record("Should throw for zero amount")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("positive"))
        }
    }
    
    @Test("Deliver bolus validates max")
    func deliverBolusValidatesMax() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        
        // Over max should fail
        do {
            try await manager.deliverBolus(units: 35.0)
            Issue.record("Should throw for amount over max")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("maximum"))
        }
    }
    
    @Test("Session nonce increments")
    func sessionNonceIncrements() {
        var session = ErosSession(podAddress: 0x12345678)
        let initialNonce = session.currentNonce
        
        session.incrementNonce()
        
        #expect(session.currentNonce == initialNonce &+ 1)
    }
}

// MARK: - Temp Basal Command Tests (PUMP-PG-002)

@Suite("Eros Temp Basal Command Tests")
struct ErosTempBasalCommandTests {
    
    @Test("ErosRateEntry encodes correctly")
    func rateEntryEncoding() {
        // 1 U/hr = 20 pulses/hr = 10 pulses per 30 min
        // Delay between pulses = 3600 / 20 = 180 seconds
        let entry = ErosRateEntry(totalPulses: 10, delayBetweenPulses: 180)
        let data = entry.data
        
        // Format: PPPP (2 bytes) TTTTTTTT (4 bytes)
        // totalPulses × 10 = 100 = 0x0064
        // delay × 100000 = 180 × 100000 = 18000000 = 0x01 12 A8 80
        #expect(data.count == 6)
        #expect(data[0] == 0x00)  // pulses high
        #expect(data[1] == 0x64)  // pulses low (100)
    }
    
    @Test("ErosRateEntry calculates rate")
    func rateEntryRate() {
        // 10 pulses in 30 min = 20 pulses/hr = 1 U/hr
        let entry = ErosRateEntry(totalPulses: 10, delayBetweenPulses: 180)
        #expect(abs(entry.rate - 1.0) < 0.01)
    }
    
    @Test("ErosRateEntry zero rate")
    func rateEntryZero() {
        let entry = ErosRateEntry(totalPulses: 0, delayBetweenPulses: ErosPodConstants.maxTimeBetweenPulses)
        #expect(entry.rate == 0)
        #expect(entry.duration == 30 * 60)  // 30 minutes
    }
    
    @Test("ErosRateEntry.makeEntries creates correct entries for 1 U/hr × 1 hour")
    func makeEntriesOneUnit() {
        let entries = ErosRateEntry.makeEntries(rate: 1.0, duration: 3600)  // 1 hour
        
        #expect(entries.count >= 1)
        
        // Total pulses for 1 U/hr × 1 hr = 20 pulses
        let totalPulses = entries.reduce(0.0) { $0 + $1.totalPulses }
        #expect(abs(totalPulses - 20) < 1)
    }
    
    @Test("ErosRateEntry.makeEntries handles zero rate")
    func makeEntriesZero() {
        let entries = ErosRateEntry.makeEntries(rate: 0, duration: 3600)  // 1 hour = 2 segments
        
        // Zero rate: one entry per 30-min segment
        #expect(entries.count == 2)
        #expect(entries[0].totalPulses == 0)
        #expect(entries[0].delayBetweenPulses == ErosPodConstants.maxTimeBetweenPulses)
    }
    
    @Test("ErosTempBasalExtraCommand encodes correctly")
    func tempBasalExtraEncoding() {
        let command = ErosTempBasalExtraCommand(
            rate: 1.0,
            duration: 1800,  // 30 minutes
            acknowledgementBeep: true,
            completionBeep: false
        )
        
        let data = command.data
        
        // Block type = 0x16
        #expect(data[0] == 0x16)
        
        // Beep byte: bit 7 = ack (1), bit 6 = complete (0), bits 0-5 = reminder (0)
        #expect(data[2] == 0x80)
        
        // Reserved = 0
        #expect(data[3] == 0x00)
    }
    
    @Test("ErosTempBasalDeliveryTable creates correct segment count")
    func tempBasalTableSegments() {
        // 30 minutes = 1 segment
        let table30min = ErosTempBasalDeliveryTable(rate: 1.0, duration: 1800)
        #expect(table30min.numSegments() == 1)
        
        // 2 hours = 4 segments
        let table2hr = ErosTempBasalDeliveryTable(rate: 1.0, duration: 7200)
        #expect(table2hr.numSegments() == 4)
    }
    
    @Test("ErosTempBasalScheduleCommand encodes schedule type 1")
    func tempBasalScheduleEncoding() {
        let command = ErosTempBasalScheduleCommand(
            nonce: 0x12345678,
            rate: 1.0,
            duration: 1800  // 30 min
        )
        
        let data = command.data
        
        // Block type = 0x1A
        #expect(data[0] == 0x1A)
        
        // Nonce at bytes 2-5
        #expect(data[2] == 0x12)
        #expect(data[3] == 0x34)
        #expect(data[4] == 0x56)
        #expect(data[5] == 0x78)
        
        // Schedule type at byte 6 = 1 (temp basal)
        #expect(data[6] == 0x01)
    }
    
    @Test("ErosCancelDeliveryCommand temp basal cancel type")
    func cancelTempBasalType() {
        let command = ErosCancelDeliveryCommand(
            nonce: 0x12345678,
            cancelType: .tempBasal,
            beepType: 0x04
        )
        
        let data = command.data
        
        // Block type = 0x1F
        #expect(data[0] == 0x1F)
        
        // Length = 0x05
        #expect(data[1] == 0x05)
        
        // Cancel type byte = beep (0x04) | tempBasal (0x02) = 0x06
        #expect(data[6] == 0x06)
    }
}

// MARK: - Temp Basal Manager Tests (PUMP-PG-002)

@Suite("Eros Temp Basal Manager Tests", .serialized)
struct ErosTempBasalManagerTests {
    
    @Test("Set temp basal succeeds in simulation")
    func setTempBasalSimulation() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        await manager.setTestFrequency(433.91)
        
        try await manager.setTempBasal(rate: 1.0, duration: 1800)  // 30 min
        
        let podInfo = await manager.podInfo
        #expect(podInfo?.isTempBasalActive == true)
    }
    
    @Test("Set temp basal validates rate")
    func setTempBasalValidatesRate() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        
        // Negative rate should fail
        do {
            try await manager.setTempBasal(rate: -1.0, duration: 1800)
            Issue.record("Should throw for negative rate")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("negative"))
        }
    }
    
    @Test("Set temp basal validates max rate")
    func setTempBasalValidatesMaxRate() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        
        // Over max should fail
        do {
            try await manager.setTempBasal(rate: 35.0, duration: 1800)
            Issue.record("Should throw for rate over max")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("maximum"))
        }
    }
    
    @Test("Set temp basal validates min duration")
    func setTempBasalValidatesMinDuration() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        
        // Under min duration should fail
        do {
            try await manager.setTempBasal(rate: 1.0, duration: 600)  // 10 min
            Issue.record("Should throw for duration under min")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("30"))
        }
    }
    
    @Test("Set temp basal validates max duration")
    func setTempBasalValidatesMaxDuration() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        
        // Over max duration should fail
        do {
            try await manager.setTempBasal(rate: 1.0, duration: 50000)  // ~14 hours
            Issue.record("Should throw for duration over max")
        } catch ErosBLEError.messageError(let msg) {
            #expect(msg.contains("12"))
        }
    }
    
    @Test("Set temp basal requires pod")
    func setTempBasalRequiresPod() async throws {
        let manager = ErosBLEManager.forTesting()
        // No session setup
        
        do {
            try await manager.setTempBasal(rate: 1.0, duration: 1800)
            Issue.record("Should throw without pod")
        } catch ErosBLEError.podNotPaired {
            // Expected
        }
    }
    
    @Test("Cancel temp basal succeeds in simulation")
    func cancelTempBasalSimulation() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        await manager.setTestFrequency(433.91)
        
        // Set then cancel
        try await manager.setTempBasal(rate: 1.0, duration: 1800)
        try await manager.cancelTempBasal()
        
        let podInfo = await manager.podInfo
        #expect(podInfo?.isTempBasalActive == false)
    }
    
    @Test("Cancel all delivery succeeds in simulation")
    func cancelDeliverySimulation() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        await manager.setTestFrequency(433.91)
        
        try await manager.cancelDelivery()
        
        let podInfo = await manager.podInfo
        // Should return to normal basal
        #expect(podInfo?.isBolusing == false)
        #expect(podInfo?.isTempBasalActive == false)
    }
    
    @Test("Zero temp basal creates correct entries")
    func zeroTempBasal() async throws {
        let manager = ErosBLEManager.forTesting()
        await manager.resumeSession(podAddress: 0x1F01482A, packetSequence: 0, messageSequence: 0)
        await manager.setTestState(.ready)
        await manager.setTestFrequency(433.91)
        
        // Zero temp basal (suspend)
        try await manager.setTempBasal(rate: 0, duration: 1800)
        
        let podInfo = await manager.podInfo
        #expect(podInfo?.isTempBasalActive == true)
    }
}
