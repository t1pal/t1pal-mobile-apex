// SPDX-License-Identifier: MIT
//
// DoseHistoryLoggerTests.swift
// T1Pal Mobile
//
// Tests for dose history logging
// Trace: PROD-AID-004

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Dose Type Tests

@Suite("Dose Type")
struct DoseTypeTests {
    
    @Test("All dose types have raw values")
    func allDoseTypesHaveRawValues() {
        for type in DoseType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test("Dose types are unique")
    func doseTypesAreUnique() {
        let rawValues = DoseType.allCases.map { $0.rawValue }
        let unique = Set(rawValues)
        #expect(rawValues.count == unique.count)
    }
}

// MARK: - Dose Source Tests

@Suite("Dose Source")
struct DoseSourceTests {
    
    @Test("All sources have raw values")
    func allSourcesHaveRawValues() {
        for source in DoseSource.allCases {
            #expect(!source.rawValue.isEmpty)
        }
    }
}

// MARK: - Dose Entry Tests

@Suite("Dose Entry")
struct DoseEntryTests {
    
    @Test("Create bolus entry")
    func createBolusEntry() {
        let entry = DoseEntry.bolus(
            units: 2.5,
            source: .user,
            glucoseAtDose: 180.0
        )
        
        #expect(entry.type == .bolus)
        #expect(entry.units == 2.5)
        #expect(entry.source == .user)
        #expect(entry.glucoseAtDose == 180.0)
        #expect(entry.status == .delivered)
    }
    
    @Test("Create SMB entry")
    func createSMBEntry() {
        let entry = DoseEntry.smb(
            units: 0.5,
            glucoseAtDose: 150.0,
            iobAtDose: 2.0,
            algorithmReason: "UAM detected"
        )
        
        #expect(entry.type == .smb)
        #expect(entry.units == 0.5)
        #expect(entry.source == .algorithm)
        #expect(entry.algorithmReason == "UAM detected")
    }
    
    @Test("Create temp basal entry")
    func createTempBasalEntry() {
        let entry = DoseEntry.tempBasal(
            rate: 1.5,
            duration: 1800,  // 30 minutes
            algorithmReason: "Decreasing BG"
        )
        
        #expect(entry.type == .tempBasal)
        #expect(entry.rate == 1.5)
        #expect(entry.duration == 1800)
        // Units = 1.5 U/hr * 0.5 hr = 0.75 U
        #expect(entry.units == 0.75)
        #expect(entry.endTime != nil)
    }
    
    @Test("Create scheduled basal entry")
    func createScheduledBasalEntry() {
        let entry = DoseEntry.scheduledBasal(rate: 0.8, duration: 3600)
        
        #expect(entry.type == .scheduledBasal)
        #expect(entry.rate == 0.8)
        #expect(entry.source == .pump)
        // Units = 0.8 U/hr * 1 hr = 0.8 U
        #expect(entry.units == 0.8)
    }
    
    @Test("Entry age calculation")
    func entryAgeCalculation() {
        let oldEntry = DoseEntry(
            type: .bolus,
            startTime: Date().addingTimeInterval(-120),
            units: 1.0
        )
        
        #expect(oldEntry.age >= 120)
        #expect(oldEntry.age < 125)
    }
    
    @Test("Entry is identifiable")
    func entryIsIdentifiable() {
        let entry1 = DoseEntry.bolus(units: 1.0)
        let entry2 = DoseEntry.bolus(units: 1.0)
        
        #expect(entry1.id != entry2.id)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = DoseEntry(
            type: .smb,
            units: 0.5,
            source: .algorithm,
            glucoseAtDose: 160.0,
            iobAtDose: 2.5,
            cobAtDose: 20.0,
            algorithmReason: "Test reason"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DoseEntry.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.units == original.units)
        #expect(decoded.glucoseAtDose == original.glucoseAtDose)
    }
}

// MARK: - In-Memory Store Tests

@Suite("In-Memory Dose History Store")
struct InMemoryDoseHistoryStoreTests {
    
    @Test("Log and retrieve entries")
    func logAndRetrieveEntries() async throws {
        let store = InMemoryDoseHistoryStore()
        
        let entry1 = DoseEntry.bolus(units: 2.0)
        let entry2 = DoseEntry.smb(units: 0.5)
        
        try await store.log(entry1)
        try await store.log(entry2)
        
        let entries = try await store.entries(lastHours: 1)
        #expect(entries.count == 2)
    }
    
    @Test("Entries sorted by time")
    func entriesSortedByTime() async throws {
        let store = InMemoryDoseHistoryStore()
        
        let entry1 = DoseEntry.bolus(units: 1.0)
        let entry2 = DoseEntry.bolus(units: 2.0)
        
        try await store.log(entry1)
        try await store.log(entry2)
        
        let entries = try await store.entries(lastHours: 1)
        // Most recent first
        #expect(entries.first?.units == 2.0)
    }
    
    @Test("Update entry status")
    func updateEntryStatus() async throws {
        let store = InMemoryDoseHistoryStore()
        
        var entry = DoseEntry.bolus(units: 1.0)
        entry.status = .pending
        try await store.log(entry)
        
        try await store.updateStatus(id: entry.id, status: .delivered)
        
        let entries = try await store.entries(lastHours: 1)
        #expect(entries.first?.status == .delivered)
    }
    
    @Test("Delete entry")
    func deleteEntry() async throws {
        let store = InMemoryDoseHistoryStore()
        
        let entry = DoseEntry.bolus(units: 1.0)
        try await store.log(entry)
        
        try await store.delete(id: entry.id)
        
        let count = try await store.count()
        #expect(count == 0)
    }
    
    @Test("Clear old history")
    func clearOldHistory() async throws {
        let store = InMemoryDoseHistoryStore()
        
        // Log recent entry
        try await store.log(DoseEntry.bolus(units: 1.0))
        
        // Clear entries older than 0 hours (all)
        try await store.clearHistory(olderThan: 0)
        
        let count = try await store.count()
        #expect(count == 0)
    }
    
    @Test("Respects max entries")
    func respectsMaxEntries() async throws {
        let store = InMemoryDoseHistoryStore()
        
        // Log more than max entries
        for _ in 0..<3000 {
            try await store.log(DoseEntry.bolus(units: 0.1))
        }
        
        let count = try await store.count()
        #expect(count == InMemoryDoseHistoryStore.maxEntries)
    }
}

// MARK: - File Store Tests

@Suite("File Dose History Store")
struct FileDoseHistoryStoreTests {
    
    @Test("Log and load from file")
    func logAndLoadFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileDoseHistoryStore(directory: tempDir)
        
        try await store.log(DoseEntry.bolus(units: 2.5))
        try await store.log(DoseEntry.smb(units: 0.5))
        
        // Create new store to verify persistence
        let store2 = try FileDoseHistoryStore(directory: tempDir)
        let entries = try await store2.entries(lastHours: 1)
        
        #expect(entries.count == 2)
    }
    
    @Test("Update status persists")
    func updateStatusPersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileDoseHistoryStore(directory: tempDir)
        
        var entry = DoseEntry.bolus(units: 1.0)
        entry.status = .pending
        try await store.log(entry)
        try await store.updateStatus(id: entry.id, status: .delivered)
        
        let store2 = try FileDoseHistoryStore(directory: tempDir)
        let entries = try await store2.entries(lastHours: 1)
        
        #expect(entries.first?.status == .delivered)
    }
}

// MARK: - Dose History Statistics Tests

@Suite("Dose History Statistics")
struct DoseHistoryStatisticsTests {
    
    @Test("Calculate from entries")
    func calculateFromEntries() {
        var bolus1 = DoseEntry.bolus(units: 2.0)
        bolus1.status = .delivered
        var bolus2 = DoseEntry.bolus(units: 3.0)
        bolus2.status = .delivered
        var smb = DoseEntry.smb(units: 0.5)
        smb.status = .delivered
        var temp = DoseEntry.tempBasal(rate: 1.0, duration: 1800)
        temp.status = .delivered
        var failed = DoseEntry.bolus(units: 5.0)
        failed.status = .failed
        
        let entries = [bolus1, bolus2, smb, temp, failed]
        let stats = DoseHistoryStatistics.from(entries: entries)
        
        #expect(stats.totalDoses == 4)  // Excludes failed
        #expect(stats.bolusUnits == 5.0)  // 2 + 3
        #expect(stats.smbUnits == 0.5)
        #expect(stats.bolusCount == 2)
        #expect(stats.smbCount == 1)
        #expect(stats.averageBolusSize == 2.5)  // 5 / 2
        #expect(stats.averageSMBSize == 0.5)
    }
    
    @Test("Empty entries statistics")
    func emptyEntriesStatistics() {
        let stats = DoseHistoryStatistics.from(entries: [])
        
        #expect(stats.totalDoses == 0)
        #expect(stats.totalUnits == 0)
        #expect(stats.averageBolusSize == 0)
    }
}

// MARK: - Dose History Logger Tests

@Suite("Dose History Logger")
struct DoseHistoryLoggerTests {
    
    @Test("Log bolus")
    func logBolus() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logBolus(
            units: 2.5,
            glucoseAtDose: 180.0,
            iobAtDose: 1.5
        )
        
        let doses = try await logger.getRecentDoses(hours: 1)
        #expect(doses.count == 1)
        #expect(doses.first?.type == .bolus)
        #expect(doses.first?.units == 2.5)
    }
    
    @Test("Log SMB")
    func logSMB() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logSMB(
            units: 0.5,
            glucoseAtDose: 160.0,
            algorithmReason: "UAM active"
        )
        
        let doses = try await logger.getRecentDoses(hours: 1)
        #expect(doses.count == 1)
        #expect(doses.first?.type == .smb)
        #expect(doses.first?.algorithmReason == "UAM active")
    }
    
    @Test("Log temp basal")
    func logTempBasal() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logTempBasal(
            rate: 1.5,
            duration: 1800,
            algorithmReason: "BG rising"
        )
        
        let doses = try await logger.getRecentDoses(hours: 1)
        #expect(doses.count == 1)
        #expect(doses.first?.type == .tempBasal)
        #expect(doses.first?.rate == 1.5)
    }
    
    @Test("Get total insulin")
    func getTotalInsulin() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logBolus(units: 3.0)
        try await logger.logSMB(units: 0.5)
        try await logger.logBolus(units: 2.0)
        
        let total = try await logger.getTotalInsulin(lastHours: 1)
        #expect(total == 5.5)
    }
    
    @Test("Get statistics")
    func getStatistics() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logBolus(units: 2.0)
        try await logger.logBolus(units: 3.0)
        try await logger.logSMB(units: 0.5)
        
        let stats = try await logger.getStatistics(lastHours: 1)
        
        #expect(stats.totalDoses == 3)
        #expect(stats.bolusCount == 2)
        #expect(stats.smbCount == 1)
    }
    
    @Test("Update status")
    func updateStatus() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logBolus(units: 1.0)
        
        let doses = try await logger.getRecentDoses(hours: 1)
        let id = doses.first!.id
        
        try await logger.updateStatus(id: id, status: .cancelled)
        
        let updated = try await logger.getRecentDoses(hours: 1)
        #expect(updated.first?.status == .cancelled)
    }
    
    @Test("Log from pump command result")
    func logFromPumpCommandResult() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        let command = PumpCommand.bolus(amount: 2.0)
        let result = PumpCommandResult(
            command: command,
            success: true,
            duration: 1.5
        )
        
        try await logger.logFromCommand(result)
        
        let doses = try await logger.getRecentDoses(hours: 1)
        #expect(doses.count == 1)
        #expect(doses.first?.units == 2.0)
        #expect(doses.first?.commandID == command.id)
    }
    
    @Test("Does not log failed commands")
    func doesNotLogFailedCommands() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        let command = PumpCommand.bolus(amount: 2.0)
        let result = PumpCommandResult(
            command: command,
            success: false,
            errorMessage: "Pump error"
        )
        
        try await logger.logFromCommand(result)
        
        let doses = try await logger.getRecentDoses(hours: 1)
        #expect(doses.count == 0)
    }
    
    @Test("Get doses in time range")
    func getDosesInTimeRange() async throws {
        let logger = DoseHistoryLogger.inMemory()
        
        try await logger.logBolus(units: 1.0)
        try await logger.logBolus(units: 2.0)
        
        let start = Date().addingTimeInterval(-60)
        let end = Date().addingTimeInterval(60)
        
        let doses = try await logger.getDoses(from: start, to: end)
        #expect(doses.count == 2)
    }
}

// MARK: - Dose History Error Tests

@Suite("Dose History Error")
struct DoseHistoryErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let errors: [DoseHistoryError] = [
            .entryNotFound,
            .invalidEntry("Missing units"),
            .storageFailed(NSError(domain: "test", code: 1))
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
}
