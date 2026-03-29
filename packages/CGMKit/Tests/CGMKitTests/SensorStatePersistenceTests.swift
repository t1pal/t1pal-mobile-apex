// SensorStatePersistenceTests.swift - Tests for sensor state persistence
// Part of CGMKit
// Trace: PROD-CGM-002

import Testing
import Foundation
@testable import CGMKit

// MARK: - Persisted Sensor Status Tests

@Suite("Persisted Sensor Status")
struct PersistedSensorStatusTests {
    
    @Test("Create persisted status directly")
    func createPersistedStatusDirectly() {
        let persisted = PersistedSensorStatus(
            sensorType: "Dexcom G6",
            transmitterID: "8G1234",
            sensorStartDate: Date().addingTimeInterval(-3600),
            isWarmingUp: false,
            isExpired: false
        )
        
        #expect(persisted.sensorType == "Dexcom G6")
        #expect(persisted.transmitterID == "8G1234")
        #expect(persisted.isWarmingUp == false)
    }
    
    @Test("Persisted status fields")
    func persistedStatusFields() {
        let persisted = PersistedSensorStatus(
            sensorType: "Libre 2",
            transmitterID: "ABC123",
            calibrationCount: 3,
            isWarmingUp: true
        )
        
        #expect(persisted.sensorType == "Libre 2")
        #expect(persisted.transmitterID == "ABC123")
        #expect(persisted.calibrationCount == 3)
        #expect(persisted.isWarmingUp == true)
    }
    
    @Test("Age calculation")
    func ageCalculation() {
        let oldDate = Date().addingTimeInterval(-60) // 1 minute ago
        let persisted = PersistedSensorStatus(
            sensorType: "Test",
            lastUpdated: oldDate
        )
        
        #expect(persisted.age >= 59)
        #expect(persisted.age <= 65)
    }
    
    @Test("Stale detection")
    func staleDetection() {
        let fresh = PersistedSensorStatus(
            sensorType: "Test",
            lastUpdated: Date()
        )
        #expect(fresh.isStale(threshold: 300) == false)
        
        let stale = PersistedSensorStatus(
            sensorType: "Test",
            lastUpdated: Date().addingTimeInterval(-600)
        )
        #expect(stale.isStale(threshold: 300) == true)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedSensorStatus(
            sensorType: "Dexcom G7",
            transmitterID: "DX7890",
            sensorStartDate: Date(),
            calibrationCount: 2,
            batteryLevel: 85
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PersistedSensorStatus.self, from: data)
        
        #expect(decoded.sensorType == original.sensorType)
        #expect(decoded.transmitterID == original.transmitterID)
        #expect(decoded.batteryLevel == 85)
    }
}

// MARK: - Sensor History Entry Tests

@Suite("Sensor History Entry")
struct SensorHistoryEntryTests {
    
    @Test("Duration calculation")
    func durationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(7 * 24 * 3600) // 7 days
        
        let entry = SensorHistoryEntry(
            sensorType: "Dexcom G6",
            startDate: start,
            endDate: end,
            endReason: .expired
        )
        
        #expect(entry.duration != nil)
        #expect(entry.durationDays! >= 6.9 && entry.durationDays! <= 7.1)
    }
    
    @Test("Duration is nil without end date")
    func durationNilWithoutEndDate() {
        let entry = SensorHistoryEntry(
            sensorType: "Test",
            startDate: Date(),
            endDate: nil
        )
        
        #expect(entry.duration == nil)
        #expect(entry.durationDays == nil)
    }
    
    @Test("All end reasons have raw values")
    func allEndReasonsHaveRawValues() {
        for reason in SensorEndReason.allCases {
            #expect(!reason.rawValue.isEmpty)
        }
    }
    
    @Test("History entry is codable")
    func historyEntryIsCodable() throws {
        let entry = SensorHistoryEntry(
            sensorType: "Libre 3",
            transmitterID: "LB3456",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400),
            endReason: .removed,
            calibrationCount: 5
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(SensorHistoryEntry.self, from: data)
        
        #expect(decoded.id == entry.id)
        #expect(decoded.sensorType == entry.sensorType)
        #expect(decoded.endReason == .removed)
    }
}

// MARK: - Calibration Record Tests

@Suite("Calibration Record")
struct CalibrationRecordTests {
    
    @Test("Difference calculation")
    func differenceCalculation() {
        let record = CalibrationRecord(
            sensorId: "sensor1",
            bloodGlucose: 120,
            sensorGlucose: 115
        )
        
        #expect(record.difference == 5)
    }
    
    @Test("Difference nil without sensor glucose")
    func differenceNilWithoutSensor() {
        let record = CalibrationRecord(
            sensorId: "sensor1",
            bloodGlucose: 120
        )
        
        #expect(record.difference == nil)
    }
    
    @Test("Calibration record is codable")
    func calibrationIsCodable() throws {
        let record = CalibrationRecord(
            sensorId: "sensor123",
            bloodGlucose: 110,
            sensorGlucose: 108,
            slope: 1.02,
            intercept: -2.0
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(record)
        let decoded = try decoder.decode(CalibrationRecord.self, from: data)
        
        #expect(decoded.bloodGlucose == 110)
        #expect(decoded.slope == 1.02)
    }
}

// MARK: - In-Memory Store Tests

@Suite("In-Memory Sensor State Store")
struct InMemorySensorStateStoreTests {
    
    @Test("Save and load status")
    func saveLoadStatus() async throws {
        let store = InMemorySensorStateStore()
        let status = PersistedSensorStatus(
            sensorType: "Dexcom G6",
            transmitterID: "8G1234"
        )
        
        try await store.saveStatus(status)
        let loaded = try await store.loadStatus()
        
        #expect(loaded != nil)
        #expect(loaded?.sensorType == "Dexcom G6")
    }
    
    @Test("Clear status")
    func clearStatus() async throws {
        let store = InMemorySensorStateStore()
        try await store.saveStatus(PersistedSensorStatus(sensorType: "Test"))
        
        try await store.clearStatus()
        let loaded = try await store.loadStatus()
        
        #expect(loaded == nil)
    }
    
    @Test("Save and load history")
    func saveLoadHistory() async throws {
        let store = InMemorySensorStateStore()
        let entry = SensorHistoryEntry(
            sensorType: "Libre 2",
            startDate: Date(),
            endReason: .expired
        )
        
        try await store.saveHistoryEntry(entry)
        let history = try await store.loadHistory(limit: nil)
        
        #expect(history.count == 1)
        #expect(history[0].sensorType == "Libre 2")
    }
    
    @Test("History respects limit")
    func historyRespectsLimit() async throws {
        let store = InMemorySensorStateStore()
        
        for i in 0..<5 {
            let entry = SensorHistoryEntry(
                sensorType: "Sensor \(i)",
                startDate: Date().addingTimeInterval(Double(-i * 86400))
            )
            try await store.saveHistoryEntry(entry)
        }
        
        let limited = try await store.loadHistory(limit: 3)
        #expect(limited.count == 3)
    }
    
    @Test("History filtered by date range")
    func historyFilteredByDateRange() async throws {
        let store = InMemorySensorStateStore()
        let now = Date()
        
        // Old entry
        try await store.saveHistoryEntry(SensorHistoryEntry(
            sensorType: "Old",
            startDate: now.addingTimeInterval(-30 * 86400)
        ))
        
        // Recent entry
        try await store.saveHistoryEntry(SensorHistoryEntry(
            sensorType: "Recent",
            startDate: now.addingTimeInterval(-5 * 86400)
        ))
        
        let filtered = try await store.loadHistory(
            from: now.addingTimeInterval(-10 * 86400),
            to: now
        )
        
        #expect(filtered.count == 1)
        #expect(filtered[0].sensorType == "Recent")
    }
    
    @Test("Save and load calibrations")
    func saveLoadCalibrations() async throws {
        let store = InMemorySensorStateStore()
        let calibration = CalibrationRecord(
            sensorId: "sensor1",
            bloodGlucose: 120
        )
        
        try await store.saveCalibration(calibration)
        let loaded = try await store.loadCalibrations(sensorId: "sensor1")
        
        #expect(loaded.count == 1)
        #expect(loaded[0].bloodGlucose == 120)
    }
    
    @Test("Calibrations filtered by sensor ID")
    func calibrationsFilteredBySensorId() async throws {
        let store = InMemorySensorStateStore()
        
        try await store.saveCalibration(CalibrationRecord(
            sensorId: "sensor1",
            bloodGlucose: 100
        ))
        try await store.saveCalibration(CalibrationRecord(
            sensorId: "sensor2",
            bloodGlucose: 110
        ))
        
        let sensor1Calibrations = try await store.loadCalibrations(sensorId: "sensor1")
        
        #expect(sensor1Calibrations.count == 1)
        #expect(sensor1Calibrations[0].sensorId == "sensor1")
    }
    
    @Test("Delete old history")
    func deleteOldHistory() async throws {
        let store = InMemorySensorStateStore()
        let now = Date()
        
        try await store.saveHistoryEntry(SensorHistoryEntry(
            sensorType: "Old",
            startDate: now.addingTimeInterval(-100 * 86400)
        ))
        try await store.saveHistoryEntry(SensorHistoryEntry(
            sensorType: "Recent",
            startDate: now.addingTimeInterval(-5 * 86400)
        ))
        
        let deleted = try await store.deleteHistoryOlderThan(now.addingTimeInterval(-30 * 86400))
        
        #expect(deleted == 1)
        
        let remaining = try await store.loadHistory(limit: nil)
        #expect(remaining.count == 1)
        #expect(remaining[0].sensorType == "Recent")
    }
}

// MARK: - File Store Tests

@Suite("File Sensor State Store")
struct FileSensorStateStoreTests {
    
    @Test("Save and load status from file")
    func saveLoadStatusFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileSensorStateStore(directory: tempDir)
        let status = PersistedSensorStatus(
            sensorType: "Dexcom G7",
            batteryLevel: 90
        )
        
        try await store.saveStatus(status)
        
        // Create new store to load from file
        let store2 = FileSensorStateStore(directory: tempDir)
        let loaded = try await store2.loadStatus()
        
        #expect(loaded != nil)
        #expect(loaded?.sensorType == "Dexcom G7")
        #expect(loaded?.batteryLevel == 90)
    }
    
    @Test("Save and load history from file")
    func saveLoadHistoryFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileSensorStateStore(directory: tempDir)
        let entry = SensorHistoryEntry(
            sensorType: "Libre 3",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400),
            endReason: .expired
        )
        
        try await store.saveHistoryEntry(entry)
        
        // Create new store to load from file
        let store2 = FileSensorStateStore(directory: tempDir)
        let history = try await store2.loadHistory(limit: nil)
        
        #expect(history.count == 1)
        #expect(history[0].sensorType == "Libre 3")
    }
    
    @Test("Clear status removes file data")
    func clearStatusRemovesFileData() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileSensorStateStore(directory: tempDir)
        try await store.saveStatus(PersistedSensorStatus(sensorType: "Test"))
        
        try await store.clearStatus()
        
        // New store should find nothing
        let store2 = FileSensorStateStore(directory: tempDir)
        let loaded = try await store2.loadStatus()
        
        #expect(loaded == nil)
    }
}

// MARK: - Sensor State Manager Tests

@Suite("Sensor State Manager")
struct SensorStateManagerTests {
    
    @Test("Update status with PersistedSensorStatus")
    func updateStatusWithPersistedStatus() async throws {
        let manager = SensorStateManager.inMemory()
        let status = PersistedSensorStatus(
            sensorType: "Dexcom G6",
            transmitterID: "8G5678",
            calibrationCount: 2
        )
        
        try await manager.updateStatus(status)
        let loaded = try await manager.getCurrentPersistedStatus()
        
        #expect(loaded != nil)
        #expect(loaded?.sensorType == "Dexcom G6")
        #expect(loaded?.calibrationCount == 2)
    }
    
    @Test("Status stale detection")
    func statusStaleDetection() async throws {
        let store = InMemorySensorStateStore()
        let manager = SensorStateManager(store: store)
        
        // No status = stale
        var isStale = await manager.isStatusStale()
        #expect(isStale == true)
        
        // Fresh status
        try await store.saveStatus(PersistedSensorStatus(
            sensorType: "Test",
            lastUpdated: Date()
        ))
        isStale = await manager.isStatusStale()
        #expect(isStale == false)
    }
    
    @Test("End sensor session records history")
    func endSensorSessionRecordsHistory() async throws {
        let manager = SensorStateManager.inMemory()
        
        try await manager.endSensorSession(
            sensorType: "Libre 2",
            transmitterID: "LB1234",
            startDate: Date().addingTimeInterval(-7 * 86400),
            endDate: Date(),
            reason: .expired,
            calibrationCount: 4
        )
        
        let history = try await manager.getRecentHistory()
        
        #expect(history.count == 1)
        #expect(history[0].sensorType == "Libre 2")
        #expect(history[0].endReason == .expired)
    }
    
    @Test("Record calibration")
    func recordCalibration() async throws {
        let manager = SensorStateManager.inMemory()
        
        try await manager.recordCalibration(
            sensorId: "sensor123",
            bloodGlucose: 115,
            sensorGlucose: 112
        )
        
        let calibrations = try await manager.getCalibrations(sensorId: "sensor123")
        
        #expect(calibrations.count == 1)
        #expect(calibrations[0].bloodGlucose == 115)
        #expect(calibrations[0].sensorGlucose == 112)
    }
    
    @Test("Get sensor statistics")
    func getSensorStatistics() async throws {
        let manager = SensorStateManager.inMemory()
        
        // Add some history
        for i in 0..<5 {
            let reason: SensorEndReason = i == 0 ? .failed : .expired
            try await manager.endSensorSession(
                sensorType: "Sensor \(i)",
                transmitterID: nil,
                startDate: Date().addingTimeInterval(Double(-i * 10 * 86400)),
                endDate: Date().addingTimeInterval(Double(-i * 10 * 86400 + 7 * 86400)),
                reason: reason
            )
        }
        
        let stats = try await manager.getSensorStatistics()
        
        #expect(stats.totalSensors == 5)
        #expect(stats.failedCount == 1)
        #expect(stats.expiredCount == 4)
        #expect(stats.successRate != nil)
    }
}

// MARK: - Sensor Statistics Tests

@Suite("Sensor Statistics")
struct SensorStatisticsTests {
    
    @Test("Calculate from empty history")
    func calculateFromEmptyHistory() {
        let stats = SensorStatistics(from: [])
        
        #expect(stats.totalSensors == 0)
        #expect(stats.averageDurationDays == nil)
        #expect(stats.successRate == nil)
    }
    
    @Test("Calculate success rate")
    func calculateSuccessRate() {
        let history = [
            SensorHistoryEntry(sensorType: "A", startDate: Date(), endReason: .expired),
            SensorHistoryEntry(sensorType: "B", startDate: Date(), endReason: .expired),
            SensorHistoryEntry(sensorType: "C", startDate: Date(), endReason: .failed),
            SensorHistoryEntry(sensorType: "D", startDate: Date(), endReason: .expired),
        ]
        
        let stats = SensorStatistics(from: history)
        
        #expect(stats.totalSensors == 4)
        #expect(stats.failedCount == 1)
        #expect(stats.successRate == 75.0) // 3/4 = 75%
    }
    
    @Test("Calculate average duration")
    func calculateAverageDuration() {
        let now = Date()
        let history = [
            SensorHistoryEntry(
                sensorType: "A",
                startDate: now.addingTimeInterval(-10 * 86400),
                endDate: now.addingTimeInterval(-3 * 86400) // 7 days
            ),
            SensorHistoryEntry(
                sensorType: "B",
                startDate: now.addingTimeInterval(-20 * 86400),
                endDate: now.addingTimeInterval(-10 * 86400) // 10 days
            ),
        ]
        
        let stats = SensorStatistics(from: history)
        
        #expect(stats.averageDurationDays != nil)
        #expect(stats.averageDurationDays! >= 8.4 && stats.averageDurationDays! <= 8.6)
    }
}

// MARK: - Sensor State Error Tests

@Suite("Sensor State Error")
struct SensorStateErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [SensorStateError] = [
            .saveFailed("disk full"),
            .loadFailed("corrupted"),
            .notFound,
            .encodingFailed,
            .decodingFailed,
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}
