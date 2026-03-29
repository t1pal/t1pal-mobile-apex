// SPDX-License-Identifier: MIT
//
// PumpAuditLogTests.swift
// T1Pal Mobile

import Testing
import Foundation
@testable import PumpKit

@Suite("Pump Audit Log")
struct PumpAuditLogTests {
    
    // MARK: - AuditCommand Tests
    
    @Test("AuditCommand descriptions")
    func auditCommandDescriptions() {
        #expect(AuditCommand.connect.description == "Connect")
        #expect(AuditCommand.disconnect.description == "Disconnect")
        #expect(AuditCommand.suspend.description == "Suspend")
        #expect(AuditCommand.resume.description == "Resume")
        #expect(AuditCommand.cancelTempBasal.description == "Cancel temp basal")
    }
    
    @Test("AuditCommand setTempBasal description")
    func auditCommandSetTempBasalDescription() {
        let cmd = AuditCommand.setTempBasal(rate: 1.5, durationMinutes: 30)
        #expect(cmd.description.contains("1.50"))
        #expect(cmd.description.contains("30"))
    }
    
    @Test("AuditCommand deliverBolus description")
    func auditCommandDeliverBolusDescription() {
        let cmd = AuditCommand.deliverBolus(units: 2.5)
        #expect(cmd.description.contains("2.50"))
    }
    
    @Test("AuditCommand type names")
    func auditCommandTypeNames() {
        #expect(AuditCommand.connect.typeName == "connect")
        #expect(AuditCommand.setTempBasal(rate: 1.0, durationMinutes: 30).typeName == "setTempBasal")
        #expect(AuditCommand.deliverBolus(units: 1.0).typeName == "deliverBolus")
    }
    
    @Test("AuditCommand equality")
    func auditCommandEquality() {
        #expect(AuditCommand.connect == AuditCommand.connect)
        #expect(AuditCommand.setTempBasal(rate: 1.0, durationMinutes: 30) == 
                AuditCommand.setTempBasal(rate: 1.0, durationMinutes: 30))
        #expect(AuditCommand.deliverBolus(units: 1.0) != AuditCommand.deliverBolus(units: 2.0))
    }
    
    @Test("AuditCommand Codable round-trip")
    func auditCommandCodableRoundTrip() throws {
        let commands: [AuditCommand] = [
            .connect,
            .disconnect,
            .setTempBasal(rate: 1.5, durationMinutes: 30),
            .cancelTempBasal,
            .deliverBolus(units: 2.5),
            .suspend,
            .resume
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for command in commands {
            let data = try encoder.encode(command)
            let decoded = try decoder.decode(AuditCommand.self, from: data)
            #expect(decoded == command)
        }
    }
    
    // MARK: - PumpAuditEntry Tests
    
    @Test("PumpAuditEntry creation")
    func pumpAuditEntryCreation() {
        let entry = PumpAuditEntry(
            command: .connect,
            success: true
        )
        #expect(entry.success)
        #expect(entry.errorMessage == nil)
    }
    
    @Test("PumpAuditEntry with failure")
    func pumpAuditEntryWithFailure() {
        let entry = PumpAuditEntry(
            command: .deliverBolus(units: 5.0),
            success: false,
            errorMessage: "Reservoir empty"
        )
        #expect(!entry.success)
        #expect(entry.errorMessage == "Reservoir empty")
    }
    
    @Test("PumpAuditEntry Codable round-trip")
    func pumpAuditEntryCodableRoundTrip() throws {
        let entry = PumpAuditEntry(
            command: .setTempBasal(rate: 0.5, durationMinutes: 60),
            success: true,
            context: ["reason": "low glucose"]
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(PumpAuditEntry.self, from: data)
        
        #expect(decoded.command == entry.command)
        #expect(decoded.success == entry.success)
        #expect(decoded.context?["reason"] == "low glucose")
    }
    
    // MARK: - PumpAuditLog Tests
    
    @Test("Empty audit log")
    func emptyAuditLog() async {
        let log = PumpAuditLog()
        let entries = await log.allEntries()
        #expect(entries.isEmpty)
        #expect(await log.count == 0)
    }
    
    @Test("Record successful command")
    func recordSuccessfulCommand() async {
        let log = PumpAuditLog()
        await log.record(AuditCommand.connect)
        
        let entries = await log.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].success)
        #expect(entries[0].command == .connect)
    }
    
    @Test("Record failed command")
    func recordFailedCommand() async {
        let log = PumpAuditLog()
        await log.recordFailure(
            AuditCommand.deliverBolus(units: 10.0),
            error: "Reservoir empty"
        )
        
        let entries = await log.allEntries()
        #expect(entries.count == 1)
        #expect(!entries[0].success)
        #expect(entries[0].errorMessage == "Reservoir empty")
    }
    
    @Test("Success and failure counts")
    func successAndFailureCounts() async {
        let log = PumpAuditLog()
        await log.record(AuditCommand.connect)
        await log.record(AuditCommand.setTempBasal(rate: 1.0, durationMinutes: 30))
        await log.recordFailure(AuditCommand.deliverBolus(units: 5.0), error: "Error")
        
        #expect(await log.count == 3)
        #expect(await log.successCount == 2)
        #expect(await log.failureCount == 1)
    }
    
    @Test("Clear log")
    func clearLog() async {
        let log = PumpAuditLog()
        await log.record(AuditCommand.connect)
        await log.record(AuditCommand.disconnect)
        
        #expect(await log.count == 2)
        await log.clear()
        #expect(await log.count == 0)
    }
    
    @Test("Max entries limit")
    func maxEntriesLimit() async {
        let log = PumpAuditLog(maxEntries: 5)
        
        for _ in 0..<10 {
            await log.record(AuditCommand.connect)
        }
        
        #expect(await log.count == 5)
    }
    
    @Test("Export JSON")
    func exportJSON() async throws {
        let log = PumpAuditLog()
        await log.record(AuditCommand.connect)
        await log.record(AuditCommand.deliverBolus(units: 2.5))
        
        let json = try await log.exportJSONString()
        #expect(json.contains("connect"))
        #expect(json.contains("deliverBolus"))
        #expect(json.contains("2.5"))
    }
    
    @Test("Summary statistics")
    func summaryStatistics() async {
        let log = PumpAuditLog()
        await log.record(AuditCommand.connect)
        await log.record(AuditCommand.setTempBasal(rate: 1.0, durationMinutes: 30))
        await log.record(AuditCommand.setTempBasal(rate: 0.5, durationMinutes: 60))
        await log.record(AuditCommand.deliverBolus(units: 2.0))
        await log.record(AuditCommand.deliverBolus(units: 3.0))
        await log.record(AuditCommand.suspend)
        await log.recordFailure(AuditCommand.resume, error: "Test")
        
        let summary = await log.summary()
        
        #expect(summary.totalCommands == 7)
        #expect(summary.successfulCommands == 6)
        #expect(summary.failedCommands == 1)
        #expect(summary.tempBasalAdjustments == 2)
        #expect(summary.bolusDeliveries == 2)
        #expect(summary.totalBolusUnits == 5.0)
        #expect(summary.suspendEvents == 1)
    }
    
    // MARK: - Integration Tests
    
    @Test("SimulationPump with audit log")
    func simulationPumpWithAuditLog() async throws {
        let log = PumpAuditLog()
        let pump = SimulationPump(auditLog: log)
        
        try await pump.connect()
        try await pump.setTempBasal(rate: 1.5, duration: 1800)
        await pump.disconnect()
        
        let entries = await log.allEntries()
        #expect(entries.count == 3)
        
        let summary = await log.summary()
        #expect(summary.tempBasalAdjustments == 1)
    }
}
