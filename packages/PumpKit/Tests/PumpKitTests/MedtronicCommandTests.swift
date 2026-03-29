// SPDX-License-Identifier: MIT
//
// MedtronicCommandTests.swift
// PumpKitTests
//
// Tests for Medtronic pump command implementation
// Trace: PUMP-MDT-006

import Testing
import Foundation
@testable import PumpKit

@Suite("MedtronicCommandTests", .serialized)
struct MedtronicCommandTests {
    
    var rileyLink: RileyLinkManager
    
    init() async throws {
        rileyLink = RileyLinkManager.shared
        
        // Disconnect any existing connection before reconnecting
        // This ensures test isolation when using the shared singleton
        await rileyLink.disconnect()
        
        // Wait for disconnect to complete
        try await Task.sleep(for: .milliseconds(50))
        
        // WIRE-016: Enable test mode for instant responses
        // IMPORTANT: Must be AFTER disconnect() since disconnect() resets to .live mode
        await rileyLink.enableTestMode()
        
        // Connect to simulated device
        let device = RileyLinkDevice(
            id: "test-rl-001",
            name: "OrangeLink-Test",
            rssi: -50,
            deviceType: .orangeLink
        )
        try await rileyLink.connect(to: device)
        try await rileyLink.tune(to: MedtronicRFConstants.frequencyNA)
    }
    
    // MARK: - Status Commands
    
    /// Integration test - requires real hardware or command-aware simulator
    /// Skip in test mode since ARCH-007 enforces explicit failure (no ACK fallback)
    @Test("Get status", .disabled("Requires real hardware - simulator returns ACK, not full Medtronic response"))
    func getStatus() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        let status = try await commander.getStatus()
        
        #expect(!status.bolusing)
        #expect(!status.suspended)
        #expect(status.normalBasalRunning)
        #expect(status.reservoirLevel > 0)
        #expect(status.batteryPercent > 0)
        #expect(status.canDeliver)
    }
    
    @Test("Get model", .disabled("Requires real hardware - simulator returns ACK, not full Medtronic response"))
    func getModel() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        let model = try await commander.getModel()
        
        #expect(!model.isEmpty)
    }
    
    /// Integration test - requires real hardware or command-aware simulator
    /// Skip in test mode since ARCH-007 enforces explicit failure (no ACK fallback)
    @Test("Get reservoir level", .disabled("Requires real hardware - simulator returns ACK, not full Medtronic response"))
    func getReservoirLevel() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        let level = try await commander.getReservoirLevel()
        
        #expect(level > 0)
    }
    
    /// MDT-FID-004: Battery level requires full Medtronic response
    /// Skip in test mode since simulator returns ACK, not full battery data
    @Test("Get battery level", .disabled("Requires real hardware - simulator returns ACK, not full Medtronic response"))
    func getBatteryLevel() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        let level = try await commander.getBatteryLevel()
        
        #expect(level > 0)
        #expect(level <= 100)
    }
    
    // MARK: - Temp Basal Commands
    
    @Test("Set temp basal")
    func setTempBasal() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        try await commander.setTempBasal(rate: 1.5, duration: 30 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.hasTempBasal)
    }
    
    @Test("Cancel temp basal")
    func cancelTempBasal() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        // Set then cancel
        try await commander.setTempBasal(rate: 1.0, duration: 60 * 60)
        try await commander.cancelTempBasal()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(!diagnostics.hasTempBasal)
    }
    
    @Test("Invalid temp basal duration")
    func invalidTempBasalDuration() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        do {
            try await commander.setTempBasal(rate: 1.0, duration: 10 * 60) // Too short
            Issue.record("Should throw invalidDuration")
        } catch let error as MedtronicCommandError {
            #expect(error == .invalidDuration)
        }
    }
    
    @Test("Invalid temp basal rate")
    func invalidTempBasalRate() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        do {
            try await commander.setTempBasal(rate: 100.0, duration: 30 * 60) // Too high
            Issue.record("Should throw invalidRate")
        } catch let error as MedtronicCommandError {
            #expect(error == .invalidRate)
        }
    }
    
    // MARK: - Bolus Commands
    
    @Test("Deliver bolus")
    func deliverBolus() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        // Get status first to enable delivery
        _ = try await commander.getStatus()
        
        try await commander.deliverBolus(units: 2.0)
        
        // No exception = success
    }
    
    @Test("Invalid bolus amount")
    func invalidBolusAmount() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.deliverBolus(units: 50.0) // Too high
            Issue.record("Should throw invalidBolusAmount")
        } catch let error as MedtronicCommandError {
            #expect(error == .invalidBolusAmount)
        }
    }
    
    @Test("Zero bolus amount")
    func zeroBolusAmount() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.deliverBolus(units: 0.0)
            Issue.record("Should throw invalidBolusAmount")
        } catch let error as MedtronicCommandError {
            #expect(error == .invalidBolusAmount)
        }
    }
    
    // MARK: - Suspend/Resume
    
    @Test("Suspend")
    func suspend() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        try await commander.suspend()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.isSuspended)
    }
    
    @Test("Resume")
    func resume() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        try await commander.suspend()
        try await commander.resume()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(!diagnostics.isSuspended)
    }
    
    @Test("Suspend cancels temp basal")
    func suspendCancelsTempBasal() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3"
        )
        
        try await commander.setTempBasal(rate: 1.0, duration: 60 * 60)
        try await commander.suspend()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.isSuspended)
        #expect(!diagnostics.hasTempBasal)
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostics")
    func diagnostics() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "A1B2C3",
            variant: .model554_NA
        )
        
        _ = try await commander.getStatus()
        
        let diagnostics = await commander.diagnosticInfo()
        
        #expect(diagnostics.pumpId == "A1B2C3")
        #expect(!diagnostics.isSuspended)
        #expect(diagnostics.lastStatus != nil)
        #expect(diagnostics.description.contains("A1B2C3"))
    }
    
    // MARK: - Opcodes
    
    @Test("Opcode properties")
    func opcodeProperties() throws {
        #expect(MedtronicOpcode.getStatus.displayName == "Get Status")
        #expect(!MedtronicOpcode.getStatus.isWriteCommand)
        
        #expect(MedtronicOpcode.setTempBasal.displayName == "Set Temp Basal")
        #expect(MedtronicOpcode.setTempBasal.isWriteCommand)
        
        #expect(MedtronicOpcode.setBolus.displayName == "Set Bolus")
        #expect(MedtronicOpcode.setBolus.isWriteCommand)
    }
    
    // MARK: - Status Response
    
    @Test("Status response")
    func statusResponse() throws {
        let status = MedtronicStatusResponse(
            bolusing: false,
            suspended: false,
            normalBasalRunning: true,
            tempBasalRunning: false,
            reservoirLevel: 150.0,
            batteryPercent: 80
        )
        
        #expect(status.canDeliver)
        #expect(!status.isLowReservoir)
        #expect(!status.isLowBattery)
        
        let lowStatus = MedtronicStatusResponse(
            reservoirLevel: 15.0,
            batteryPercent: 15
        )
        
        #expect(lowStatus.isLowReservoir)
        #expect(lowStatus.isLowBattery)
        
        let suspendedStatus = MedtronicStatusResponse(
            suspended: true,
            reservoirLevel: 100.0,
            batteryPercent: 80
        )
        
        #expect(!suspendedStatus.canDeliver)
    }
    
    // MARK: - Temp Basal Struct
    
    @Test("Temp basal struct")
    func tempBasalStruct() throws {
        let startTime = Date()
        let tempBasal = MedtronicTempBasal(
            rate: 1.5,
            duration: 30 * 60,
            startTime: startTime
        )
        
        #expect(tempBasal.rate == 1.5)
        #expect(tempBasal.durationMinutes == 30)
        #expect(!tempBasal.isExpired)
        #expect(tempBasal.remainingDuration > 0)
        
        // Test expired
        let oldTempBasal = MedtronicTempBasal(
            rate: 1.0,
            duration: 30 * 60,
            startTime: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        
        #expect(oldTempBasal.isExpired)
        #expect(oldTempBasal.remainingDuration == 0)
    }
    
    // MARK: - Multiple Variants
    
    @Test("Worldwide variant")
    func worldwideVariant() async throws {
        let commander = MedtronicCommander(
            rileyLink: rileyLink,
            pumpId: "D1E2F3",
            variant: .model523_WW
        )
        
        let status = try await commander.getStatus()
        #expect(status != nil)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.variant.region == .worldWide)
    }
    
    // MARK: - Reservoir Response Parsing (MDT-HIST-020)
    
    /// Helper to strip 5-byte header from full packet, matching production code
    func stripHeader(from packet: Data) -> Data {
        guard packet.count > 5 else { return packet }
        return packet.subdata(in: 5..<packet.count)
    }
    
    /// Test parsing x23+ reservoir response using MinimedKit test vector
    /// Source: MinimedKitTests/Messages/ReadRemainingInsulinMessageBodyTests.swift
    /// MDT-DIAG-FIX: parse() expects BODY ONLY - strip 5-byte header first
    @Test("Reservoir parsing 723")
    func reservoirParsing723() throws {
        // Test vector from MinimedKit: 723 model, expected 80.875 units
        // Full packet: [packetType][address:3][msgType][body:65]
        // a7 = packetType, 594040 = address, 73 = msgType (readRemainingInsulin)
        // Body: 04 00 00 0c a3 ... (reservoir strokes at body[3:5] = 0x0ca3 = 3235)
        let packetHex = "a7594040730400000ca300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        let packetData = Data(hexString: packetHex)!
        
        // Strip 5-byte header to get body only (matching production code)
        let bodyData = stripHeader(from: packetData)
        let result = MedtronicReservoirResponse.parse(from: bodyData, scale: 40)
        
        #expect(result != nil)
        #expect(abs(result!.unitsRemaining - 80.875) < 0.001)
    }
    
    /// Test parsing x22 reservoir response using MinimedKit test vector
    /// Source: MinimedKitTests/Messages/ReadRemainingInsulinMessageBodyTests.swift
    /// MDT-DIAG-FIX: parse() expects BODY ONLY - strip 5-byte header first
    @Test("Reservoir parsing 522")
    func reservoirParsing522() throws {
        // Test vector from MinimedKit: 522 model, expected 135.0 units
        // Full packet: [packetType][address:3][msgType][body:65]
        // a7 = packetType, 578398 = address, 73 = msgType
        // Body: 02 05 46 00 ... (reservoir strokes at body[1:3] = 0x0546 = 1350)
        let packetHex = "a757839873020546000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        let packetData = Data(hexString: packetHex)!
        
        // Strip 5-byte header to get body only (matching production code)
        let bodyData = stripHeader(from: packetData)
        let result = MedtronicReservoirResponse.parse(from: bodyData, scale: 10)
        
        #expect(result != nil)
        #expect(abs(result!.unitsRemaining - 135.0) < 0.001)
    }
    
    /// Test parsing fails with too-short body
    /// MDT-DIAG-FIX: Testing body length, not packet length
    @Test("Reservoir parsing too short")
    func reservoirParsingTooShort() throws {
        // Body only - too short (only 4 bytes, need 5 for x23+ indices [3:5])
        let shortBody = Data([0x04, 0x00, 0x00, 0x0c])  // missing last byte
        
        let result = MedtronicReservoirResponse.parse(from: shortBody, scale: 40)
        
        #expect(result == nil)
    }
}
