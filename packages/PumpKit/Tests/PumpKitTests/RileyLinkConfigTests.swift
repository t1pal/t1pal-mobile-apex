// RileyLinkConfigTests.swift
// PumpKitTests
//
// SPDX-License-Identifier: MIT
// Copyright 2026 T1Pal.org
// Trace: RL-CONFIG-ARCH-001, RL-DIAG-003, RL-DIAG-006

import Testing
import Foundation
@testable import PumpKit

@Suite("RileyLink Config")
struct RileyLinkConfigTests {
    
    // MARK: - PacketLogEntry Tests
    
    @Test("Hex string formats bytes correctly")
    func hexStringFormat() {
        let entry = PacketLogEntry(
            direction: .tx,
            data: Data([0xA7, 0x01, 0x63, 0x35]),
            label: "Test"
        )
        
        #expect(entry.hexString == "A7 01 63 35")
    }
    
    @Test("Empty data returns empty hex string")
    func emptyHexString() {
        let entry = PacketLogEntry(
            direction: .rx,
            data: Data(),
            label: "Empty"
        )
        
        #expect(entry.hexString == "")
        #expect(entry.hexDump == "(empty)")
    }
    
    // RL-DIAG-003: Hex dump format tests
    
    @Test("Hex dump shows offset and ASCII")
    func hexDumpFormat() {
        // "Hello" in bytes
        let entry = PacketLogEntry(
            direction: .tx,
            data: Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
            label: "Hello"
        )
        
        let dump = entry.hexDump
        #expect(dump.contains("0000:"))
        #expect(dump.contains("|Hello|"))
    }
    
    @Test("Hex dump handles non-printable as dots")
    func hexDumpNonPrintable() {
        let entry = PacketLogEntry(
            direction: .rx,
            data: Data([0x00, 0x01, 0x02, 0x7F]),
            label: "Binary"
        )
        
        let dump = entry.hexDump
        #expect(dump.contains("|....|"))
    }
    
    @Test("Hex dump splits at 16 bytes per line")
    func hexDumpMultiLine() {
        // 20 bytes should produce 2 lines
        let entry = PacketLogEntry(
            direction: .tx,
            data: Data(repeating: 0x41, count: 20),  // 20 x 'A'
            label: "Long"
        )
        
        let dump = entry.hexDump
        let lines = dump.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(dump.contains("0000:"))
        #expect(dump.contains("0010:"))  // Second line starts at offset 16
    }
    
    @Test("Byte count returns correct length")
    func byteCount() {
        let entry = PacketLogEntry(
            direction: .tx,
            data: Data([0x01, 0x02, 0x03]),
            label: "Test"
        )
        
        #expect(entry.byteCount == 3)
    }
}

// MARK: - RL-DIAG-006: End-to-End Logging Trace Verification

@Suite("RL Logging Trace")
struct RLLoggingTraceTests {
    
    // MARK: - TimingTraceEntry Tests (RL-DIAG-005)
    
    @Test("TimingTraceEntry captures command name and phases")
    func timingTraceCapturesPhases() {
        let phases: [TimingTraceEntry.Phase] = [
            TimingTraceEntry.Phase(name: "BLE Write", duration: 0.015),
            TimingTraceEntry.Phase(name: "Poll Response", duration: 0.085),
            TimingTraceEntry.Phase(name: "Read Response", duration: 0.010)
        ]
        
        let entry = TimingTraceEntry(
            commandName: "SendAndListenCommand",
            phases: phases,
            totalDuration: 0.110
        )
        
        #expect(entry.commandName == "SendAndListenCommand")
        #expect(entry.phases.count == 3)
        #expect(entry.totalDuration == 0.110)
    }
    
    @Test("TimingTraceEntry formats duration as milliseconds")
    func timingTraceFormatsDuration() {
        let entry = TimingTraceEntry(
            commandName: "TestCommand",
            phases: [TimingTraceEntry.Phase(name: "Phase1", duration: 0.025)],
            totalDuration: 0.025
        )
        
        #expect(entry.formattedTotalDuration == "25.0 ms")
        #expect(entry.phases[0].formattedDuration == "25.0 ms")
    }
    
    @Test("TimingTraceEntry provides summary and breakdown")
    func timingTraceSummary() {
        let phases: [TimingTraceEntry.Phase] = [
            TimingTraceEntry.Phase(name: "BLE Write", duration: 0.010),
            TimingTraceEntry.Phase(name: "Poll", duration: 0.090)
        ]
        
        let entry = TimingTraceEntry(
            commandName: "UpdateRegisterCommand",
            phases: phases,
            totalDuration: 0.100
        )
        
        #expect(entry.summary.contains("UpdateRegisterCommand"))
        #expect(entry.summary.contains("100.0 ms"))
        #expect(entry.detailedBreakdown.contains("BLE Write"))
        #expect(entry.detailedBreakdown.contains("Poll"))
    }
    
    // MARK: - RileyLinkConfig Integration Tests
    
    @MainActor
    @Test("Config captures BLE packet log entries")
    func configCapturesPackets() {
        let config = RileyLinkConfig()
        
        // Simulate TX packet (BLE write)
        config.addPacket(direction: .tx, data: Data([0x02, 0x00, 0x01]), label: "GetVersion")
        
        // Simulate RX packet (BLE read)
        config.addPacket(direction: .rx, data: Data([0x73, 0x75, 0x62, 0x67]), label: "Response")
        
        #expect(config.packetLog.count == 2)
        #expect(config.packetLog[0].direction == .tx)
        #expect(config.packetLog[0].label == "GetVersion")
        #expect(config.packetLog[1].direction == .rx)
        #expect(config.packetLog[1].label == "Response")
    }
    
    @MainActor
    @Test("Config captures timing trace entries")
    func configCapturesTimingTrace() {
        let config = RileyLinkConfig()
        
        let phases: [TimingTraceEntry.Phase] = [
            TimingTraceEntry.Phase(name: "Read Initial RC", duration: 0.005),
            TimingTraceEntry.Phase(name: "BLE Write", duration: 0.012),
            TimingTraceEntry.Phase(name: "Poll Response (5x)", duration: 0.500),
            TimingTraceEntry.Phase(name: "Read Response", duration: 0.008)
        ]
        
        config.addTimingTrace(commandName: "SendAndListenCommand", phases: phases, totalDuration: 0.525)
        
        #expect(config.timingLog.count == 1)
        #expect(config.timingLog[0].commandName == "SendAndListenCommand")
        #expect(config.timingLog[0].phases.count == 4)
    }
    
    @MainActor
    @Test("Config respects max log entries limit")
    func configRespectsMaxEntries() {
        let config = RileyLinkConfig()
        config.maxPacketLogEntries = 5
        config.maxTimingLogEntries = 3
        
        // Add more entries than the limit
        for i in 0..<10 {
            config.addPacket(direction: .tx, data: Data([UInt8(i)]), label: "Packet\(i)")
        }
        for i in 0..<5 {
            config.addTimingTrace(commandName: "Command\(i)", phases: [], totalDuration: 0.1)
        }
        
        #expect(config.packetLog.count == 5)
        #expect(config.timingLog.count == 3)
        
        // Verify oldest entries were trimmed (FIFO)
        #expect(config.packetLog[0].label == "Packet5")
        #expect(config.timingLog[0].commandName == "Command2")
    }
    
    @MainActor
    @Test("Config clears logs")
    func configClearsLogs() {
        let config = RileyLinkConfig()
        
        config.addPacket(direction: .tx, data: Data([0x01]), label: "Test")
        config.addTimingTrace(commandName: "Test", phases: [], totalDuration: 0.1)
        
        #expect(config.packetLog.count == 1)
        #expect(config.timingLog.count == 1)
        
        config.clearPacketLog()
        config.clearTimingLog()
        
        #expect(config.packetLog.isEmpty)
        #expect(config.timingLog.isEmpty)
    }
    
    // MARK: - End-to-End Trace Verification (RL-DIAG-006)
    
    @MainActor
    @Test("End-to-end trace captures BLE TX, BLE RX, and timing")
    func endToEndTraceCapturesAllEvents() {
        let config = RileyLinkConfig()
        
        // Simulate a complete pump command cycle:
        // 1. BLE TX: SendAndListen command
        let txData = Data([0x12, 0x04, 0x00, 0x00, 0x00, 0x00, 0xF4, 0x01, 0x00])
        config.addPacket(direction: .tx, data: txData, label: "SendAndListenCommand")
        
        // 2. BLE RX: Response with pump data
        let rxData = Data([0xDD, 0x60, 0x01, 0xA7, 0x01, 0x63, 0x35, 0x00])
        config.addPacket(direction: .rx, data: rxData, label: "Response")
        
        // 3. Timing trace for the command
        let phases: [TimingTraceEntry.Phase] = [
            TimingTraceEntry.Phase(name: "Read Initial RC", duration: 0.008),
            TimingTraceEntry.Phase(name: "BLE Write", duration: 0.015),
            TimingTraceEntry.Phase(name: "Poll Response (3x)", duration: 0.312),
            TimingTraceEntry.Phase(name: "Read Response", duration: 0.010)
        ]
        config.addTimingTrace(commandName: "SendAndListenCommand", phases: phases, totalDuration: 0.345)
        
        // Verify complete trace
        #expect(config.packetLog.count == 2, "Expected BLE TX and RX packets")
        #expect(config.timingLog.count == 1, "Expected timing trace entry")
        
        // Verify BLE TX packet (command to RileyLink)
        let txEntry = config.packetLog[0]
        #expect(txEntry.direction == .tx, "First packet should be TX")
        #expect(txEntry.label == "SendAndListenCommand")
        #expect(txEntry.byteCount > 0, "TX packet should have data")
        
        // Verify BLE RX packet (response from RileyLink including pump data)
        let rxEntry = config.packetLog[1]
        #expect(rxEntry.direction == .rx, "Second packet should be RX")
        #expect(rxEntry.data[0] == 0xDD, "Response should have success code 0xDD")
        
        // Verify timing trace captures command phases
        let timing = config.timingLog[0]
        #expect(timing.commandName == "SendAndListenCommand")
        #expect(timing.phases.count == 4, "Should capture all timing phases")
        #expect(timing.phases.contains { $0.name.contains("BLE Write") }, "Should include BLE write phase")
        #expect(timing.phases.contains { $0.name.contains("Poll") }, "Should include poll phase")
        #expect(timing.phases.contains { $0.name.contains("Read Response") }, "Should include read phase")
        #expect(timing.totalDuration > 0, "Total duration should be positive")
    }
    
    @MainActor
    @Test("Trace includes RF layer identification via packet labels")
    func traceIdentifiesRFLayer() {
        let config = RileyLinkConfig()
        
        // Simulate wakeup and command sequence
        config.addPacket(direction: .tx, data: Data([0x00, 0x5D]), label: "PowerOn")
        config.addPacket(direction: .rx, data: Data([0xAA]), label: "RF Timeout")
        config.addPacket(direction: .tx, data: Data([0x00, 0x8D]), label: "GetPumpModel")
        config.addPacket(direction: .rx, data: Data([0xDD, 0x60, 0x01]), label: "Pump Response")
        
        // Verify we can identify different command types
        let powerOnPacket = config.packetLog.first { $0.label == "PowerOn" }
        #expect(powerOnPacket != nil, "Should capture PowerOn packet")
        
        let pumpResponse = config.packetLog.first { $0.label == "Pump Response" }
        #expect(pumpResponse != nil, "Should capture pump response")
        #expect(pumpResponse?.data[0] == 0xDD, "Pump response should have success code")
    }
    
    @MainActor
    @Test("Trace provides exportable format via hexDump and detailedBreakdown")
    func traceExportableFormat() {
        let config = RileyLinkConfig()
        
        // Add sample data
        config.addPacket(
            direction: .tx,
            data: Data([0xA7, 0x01, 0x63, 0x35, 0x00, 0x8D, 0x00, 0x5D]),
            label: "GetPumpModel"
        )
        config.addTimingTrace(
            commandName: "GetPumpModel",
            phases: [
                TimingTraceEntry.Phase(name: "BLE Write", duration: 0.012),
                TimingTraceEntry.Phase(name: "Poll Response", duration: 0.156)
            ],
            totalDuration: 0.168
        )
        
        // Verify packet provides hex dump for debugging
        let packet = config.packetLog[0]
        #expect(!packet.hexDump.isEmpty, "hexDump should be non-empty")
        #expect(packet.hexDump.contains("A7 01 63 35"), "hexDump should contain packet bytes")
        
        // Verify timing provides detailed breakdown for debugging
        let timing = config.timingLog[0]
        #expect(timing.detailedBreakdown.contains("BLE Write"), "breakdown should include phase names")
        #expect(timing.detailedBreakdown.contains("ms"), "breakdown should show durations in ms")
    }
}
