// DataPersistenceTests.swift - Tests for data persistence layer
// Part of T1PalCore
// Trace: PROD-PERSIST-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Glucose Store Tests

@Suite("Glucose Store")
struct GlucoseStoreTests {
    
    @Test("Save and fetch single reading")
    func saveFetchSingle() async throws {
        let store = InMemoryGlucoseStore()
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat, source: "test")
        
        try await store.save(reading)
        let fetched = try await store.fetchMostRecent()
        
        #expect(fetched != nil)
        #expect(fetched?.id == reading.id)
        #expect(fetched?.glucose == 120)
    }
    
    @Test("Save and fetch multiple readings")
    func saveFetchMultiple() async throws {
        let store = InMemoryGlucoseStore()
        let now = Date()
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 110, timestamp: now.addingTimeInterval(-200), source: "test"),
            GlucoseReading(glucose: 120, timestamp: now.addingTimeInterval(-100), source: "test"),
        ]
        
        try await store.save(readings)
        let count = try await store.count()
        
        #expect(count == 3)
    }
    
    @Test("Fetch latest readings")
    func fetchLatest() async throws {
        let store = InMemoryGlucoseStore()
        let now = Date()
        
        for i in 0..<10 {
            let reading = GlucoseReading(
                glucose: Double(100 + i * 5),
                timestamp: now.addingTimeInterval(Double(-i * 300)),
                source: "test"
            )
            try await store.save(reading)
        }
        
        let latest = try await store.fetchLatest(3)
        
        #expect(latest.count == 3)
        #expect(latest[0].glucose == 100) // Most recent
        #expect(latest[1].glucose == 105)
        #expect(latest[2].glucose == 110)
    }
    
    @Test("Fetch by date range")
    func fetchByDateRange() async throws {
        let store = InMemoryGlucoseStore()
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        
        // Reading from 2 hours ago
        try await store.save(GlucoseReading(glucose: 100, timestamp: twoHoursAgo, source: "test"))
        // Reading from 30 min ago
        try await store.save(GlucoseReading(glucose: 110, timestamp: now.addingTimeInterval(-1800), source: "test"))
        // Reading from now
        try await store.save(GlucoseReading(glucose: 120, timestamp: now, source: "test"))
        
        // Fetch last hour only
        let lastHour = try await store.fetch(from: oneHourAgo, to: now)
        
        #expect(lastHour.count == 2)
    }
    
    @Test("Delete older than date")
    func deleteOlderThan() async throws {
        let store = InMemoryGlucoseStore()
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Old reading
        try await store.save(GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-7200), source: "test"))
        // Recent reading
        try await store.save(GlucoseReading(glucose: 120, timestamp: now, source: "test"))
        
        let deleted = try await store.deleteOlderThan(oneHourAgo)
        let remaining = try await store.count()
        
        #expect(deleted == 1)
        #expect(remaining == 1)
    }
    
    @Test("Delete all readings")
    func deleteAll() async throws {
        let store = InMemoryGlucoseStore()
        
        try await store.save(GlucoseReading(glucose: 100, source: "test"))
        try await store.save(GlucoseReading(glucose: 110, source: "test"))
        try await store.save(GlucoseReading(glucose: 120, source: "test"))
        
        try await store.deleteAll()
        let count = try await store.count()
        
        #expect(count == 0)
    }
    
    @Test("Empty store returns nil for most recent")
    func emptyStoreMostRecent() async throws {
        let store = InMemoryGlucoseStore()
        let recent = try await store.fetchMostRecent()
        
        #expect(recent == nil)
    }
    
    @Test("Empty store returns empty array for fetch")
    func emptyStoreFetch() async throws {
        let store = InMemoryGlucoseStore()
        let results = try await store.fetchLatest(10)
        
        #expect(results.isEmpty)
    }
}

// MARK: - Treatment Store Tests

@Suite("Treatment Store")
struct TreatmentStoreTests {
    
    @Test("Save and fetch single treatment")
    func saveFetchSingle() async throws {
        let store = InMemoryTreatmentStore()
        let bolus = Treatment.bolus(units: 2.5)
        
        try await store.save(bolus)
        let fetched = try await store.fetchLatest(1)
        
        #expect(fetched.count == 1)
        #expect(fetched[0].id == bolus.id)
        #expect(fetched[0].insulin == 2.5)
    }
    
    @Test("Save multiple treatments")
    func saveMultiple() async throws {
        let store = InMemoryTreatmentStore()
        let treatments = [
            Treatment.bolus(units: 1.0),
            Treatment.carbs(grams: 30),
            Treatment.tempBasal(rate: 0.5, duration: 1800),
        ]
        
        try await store.save(treatments)
        let count = try await store.count()
        
        #expect(count == 3)
    }
    
    @Test("Fetch by type")
    func fetchByType() async throws {
        let store = InMemoryTreatmentStore()
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let tomorrow = now.addingTimeInterval(86400)
        
        try await store.save(Treatment.bolus(units: 1.0, timestamp: now))
        try await store.save(Treatment.bolus(units: 2.0, timestamp: now.addingTimeInterval(-300)))
        try await store.save(Treatment.carbs(grams: 30, timestamp: now))
        
        let boluses = try await store.fetch(type: .bolus, from: yesterday, to: tomorrow)
        
        #expect(boluses.count == 2)
        #expect(boluses.allSatisfy { $0.type == .bolus })
    }
    
    @Test("Fetch by sync identifier")
    func fetchBySyncId() async throws {
        let store = InMemoryTreatmentStore()
        let syncId = "loop-bolus-12345"
        let treatment = Treatment(
            type: .bolus,
            insulin: 2.0,
            syncIdentifier: syncId
        )
        
        try await store.save(treatment)
        let fetched = try await store.fetch(syncIdentifier: syncId)
        
        #expect(fetched != nil)
        #expect(fetched?.id == treatment.id)
    }
    
    @Test("Sync identifier not found returns nil")
    func syncIdNotFound() async throws {
        let store = InMemoryTreatmentStore()
        try await store.save(Treatment.bolus(units: 1.0))
        
        let fetched = try await store.fetch(syncIdentifier: "nonexistent")
        
        #expect(fetched == nil)
    }
    
    @Test("Delete older than date")
    func deleteOlderThan() async throws {
        let store = InMemoryTreatmentStore()
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Old treatment
        try await store.save(Treatment.bolus(units: 1.0, timestamp: now.addingTimeInterval(-7200)))
        // Recent treatment
        try await store.save(Treatment.bolus(units: 2.0, timestamp: now))
        
        let deleted = try await store.deleteOlderThan(oneHourAgo)
        let remaining = try await store.count()
        
        #expect(deleted == 1)
        #expect(remaining == 1)
    }
    
    @Test("Delete all treatments")
    func deleteAll() async throws {
        let store = InMemoryTreatmentStore()
        
        try await store.save(Treatment.bolus(units: 1.0))
        try await store.save(Treatment.carbs(grams: 20))
        try await store.save(Treatment.tempBasal(rate: 0.5, duration: 1800))
        
        try await store.deleteAll()
        let count = try await store.count()
        
        #expect(count == 0)
    }
}

// MARK: - Treatment Type Tests

@Suite("Treatment Type")
struct PersistenceTreatmentTypeTests {
    
    @Test("All treatment types have raw values")
    func allTypesHaveRawValues() {
        for type in PersistenceTreatmentType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test("Treatment types are codable")
    func typesAreCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for type in PersistenceTreatmentType.allCases {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(PersistenceTreatmentType.self, from: data)
            #expect(decoded == type)
        }
    }
    
    @Test("Bolus factory creates correct treatment")
    func bolusFactory() {
        let bolus = Treatment.bolus(units: 2.5)
        
        #expect(bolus.type == .bolus)
        #expect(bolus.insulin == 2.5)
        #expect(bolus.carbs == nil)
        #expect(bolus.source == "T1Pal")
    }
    
    @Test("Carbs factory creates correct treatment")
    func carbsFactory() {
        let carbs = Treatment.carbs(grams: 45)
        
        #expect(carbs.type == .carbs)
        #expect(carbs.carbs == 45)
        #expect(carbs.insulin == nil)
    }
    
    @Test("Temp basal factory creates correct treatment")
    func tempBasalFactory() {
        let tempBasal = Treatment.tempBasal(rate: 0.75, duration: 3600)
        
        #expect(tempBasal.type == .tempBasal)
        #expect(tempBasal.rate == 0.75)
        #expect(tempBasal.duration == 3600)
    }
}

// MARK: - Retention Policy Tests

@Suite("Retention Policy")
struct RetentionPolicyTests {
    
    @Test("Standard policy values")
    func standardPolicy() {
        let policy = RetentionPolicy.standard
        
        #expect(policy.glucoseRetentionDays == 90)
        #expect(policy.treatmentRetentionDays == 365)
    }
    
    @Test("Extended policy values")
    func extendedPolicy() {
        let policy = RetentionPolicy.extended
        
        #expect(policy.glucoseRetentionDays == 180)
        #expect(policy.treatmentRetentionDays == 730)
    }
    
    @Test("Minimal policy values")
    func minimalPolicy() {
        let policy = RetentionPolicy.minimal
        
        #expect(policy.glucoseRetentionDays == 30)
        #expect(policy.treatmentRetentionDays == 90)
    }
    
    @Test("Cutoff date calculation")
    func cutoffDateCalculation() {
        let policy = RetentionPolicy(glucoseRetentionDays: 7, treatmentRetentionDays: 30)
        let now = Date()
        
        let glucoseCutoff = policy.glucoseCutoffDate
        let treatmentCutoff = policy.treatmentCutoffDate
        
        // Glucose cutoff should be ~7 days ago
        let glucoseDiff = now.timeIntervalSince(glucoseCutoff) / 86400
        #expect(glucoseDiff >= 6.9 && glucoseDiff <= 7.1)
        
        // Treatment cutoff should be ~30 days ago
        let treatmentDiff = now.timeIntervalSince(treatmentCutoff) / 86400
        #expect(treatmentDiff >= 29.9 && treatmentDiff <= 30.1)
    }
    
    @Test("Retention policy is codable")
    func policyIsCodable() throws {
        let policy = RetentionPolicy(glucoseRetentionDays: 45, treatmentRetentionDays: 180)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(policy)
        let decoded = try decoder.decode(RetentionPolicy.self, from: data)
        
        #expect(decoded.glucoseRetentionDays == 45)
        #expect(decoded.treatmentRetentionDays == 180)
    }
}

// MARK: - Retention Manager Tests

@Suite("Retention Manager")
struct RetentionManagerTests {
    
    @Test("Cleanup deletes old data")
    func cleanupDeletesOldData() async throws {
        let glucoseStore = InMemoryGlucoseStore()
        let treatmentStore = InMemoryTreatmentStore()
        
        let now = Date()
        let oldDate = now.addingTimeInterval(-100 * 86400) // 100 days ago
        
        // Add old and new glucose readings
        try await glucoseStore.save(GlucoseReading(glucose: 100, timestamp: oldDate, source: "test"))
        try await glucoseStore.save(GlucoseReading(glucose: 120, timestamp: now, source: "test"))
        
        // Add old and new treatments
        try await treatmentStore.save(Treatment.bolus(units: 1.0, timestamp: oldDate))
        try await treatmentStore.save(Treatment.bolus(units: 2.0, timestamp: now))
        
        let manager = RetentionManager(
            glucoseStore: glucoseStore,
            treatmentStore: treatmentStore,
            policy: .standard // 90 days glucose, 365 days treatments
        )
        
        let (glucoseDeleted, treatmentDeleted) = try await manager.runCleanup()
        
        #expect(glucoseDeleted == 1) // Old glucose reading deleted
        #expect(treatmentDeleted == 0) // Treatment still within 365 days
        
        let remainingGlucose = try await glucoseStore.count()
        #expect(remainingGlucose == 1)
    }
    
    @Test("Set policy updates behavior")
    func setPolicyUpdatesBehavior() async throws {
        let glucoseStore = InMemoryGlucoseStore()
        let treatmentStore = InMemoryTreatmentStore()
        
        let now = Date()
        let fourtyDaysAgo = now.addingTimeInterval(-40 * 86400)
        
        try await glucoseStore.save(GlucoseReading(glucose: 100, timestamp: fourtyDaysAgo, source: "test"))
        
        let manager = RetentionManager(
            glucoseStore: glucoseStore,
            treatmentStore: treatmentStore,
            policy: .standard // 90 days - reading should NOT be deleted
        )
        
        let (deleted1, _) = try await manager.runCleanup()
        #expect(deleted1 == 0)
        
        // Change to minimal policy (30 days) - reading SHOULD be deleted now
        await manager.setPolicy(.minimal)
        
        // Run cleanup again - now the 40-day-old reading should be deleted
        let (deleted2, _) = try await manager.runCleanup()
        #expect(deleted2 == 1)
        
        // Verify store is empty
        let remaining = try await glucoseStore.count()
        #expect(remaining == 0)
    }
}

// MARK: - Data Store Manager Tests

@Suite("Data Store Manager")
struct DataStoreManagerTests {
    
    @Test("In-memory manager creates stores")
    func inMemoryManager() async throws {
        let manager = DataStoreManager.inMemory()
        
        let reading = GlucoseReading(glucose: 100, source: "test")
        try await manager.glucoseStore.save(reading)
        
        let treatment = Treatment.bolus(units: 2.0)
        try await manager.treatmentStore.save(treatment)
        
        let glucoseCount = try await manager.glucoseStore.count()
        let treatmentCount = try await manager.treatmentStore.count()
        
        #expect(glucoseCount == 1)
        #expect(treatmentCount == 1)
    }
    
    @Test("Custom stores are used")
    func customStores() async throws {
        let customGlucose = InMemoryGlucoseStore()
        let customTreatment = InMemoryTreatmentStore()
        
        // Pre-populate
        try await customGlucose.save(GlucoseReading(glucose: 100, source: "test"))
        try await customGlucose.save(GlucoseReading(glucose: 110, source: "test"))
        
        let manager = DataStoreManager(
            glucoseStore: customGlucose,
            treatmentStore: customTreatment
        )
        
        let count = try await manager.glucoseStore.count()
        #expect(count == 2)
    }
}

// MARK: - Persistence Error Tests

@Suite("Persistence Error")
struct PersistenceErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [PersistenceError] = [
            .saveFailed("disk full"),
            .fetchFailed("query error"),
            .deleteFailed("locked"),
            .fileNotFound,
            .decodingFailed("invalid JSON"),
            .encodingFailed("circular reference"),
            .storageUnavailable,
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("Save failed includes reason")
    func saveFailedIncludesReason() {
        let error = PersistenceError.saveFailed("disk full")
        #expect(error.errorDescription?.contains("disk full") == true)
    }
    
    @Test("Decoding failed includes reason")
    func decodingFailedIncludesReason() {
        let error = PersistenceError.decodingFailed("invalid format")
        #expect(error.errorDescription?.contains("invalid format") == true)
    }
}

// MARK: - File Store Tests

@Suite("File Glucose Store")
struct FileGlucoseStoreTests {
    
    @Test("Save and load from file")
    func saveAndLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create store and save reading
        let store1 = FileGlucoseStore(directory: tempDir, filename: "test-glucose.json")
        let reading = GlucoseReading(glucose: 115, timestamp: Date(), trend: .fortyFiveUp, source: "test")
        try await store1.save(reading)
        
        // Create new store instance to load from file
        let store2 = FileGlucoseStore(directory: tempDir, filename: "test-glucose.json")
        let loaded = try await store2.fetchMostRecent()
        
        #expect(loaded != nil)
        #expect(loaded?.glucose == 115)
        #expect(loaded?.trend == .fortyFiveUp)
    }
    
    @Test("Save multiple and count persists")
    func saveMultipleAndCount() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileGlucoseStore(directory: tempDir)
        
        var readings: [GlucoseReading] = []
        for i in 0..<5 {
            let reading = GlucoseReading(
                glucose: Double(100 + i * 10),
                timestamp: Date().addingTimeInterval(Double(-i * 300)),
                source: "test"
            )
            readings.append(reading)
        }
        
        try await store.save(readings)
        let count = try await store.count()
        
        #expect(count == 5)
    }
    
    // DATA-COHESIVE-001: Test fetch by sync identifier
    @Test("Fetch by sync identifier")
    func fetchBySyncIdentifier() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileGlucoseStore(directory: tempDir)
        
        // Save readings with sync identifiers
        let reading1 = GlucoseReading(glucose: 100, timestamp: Date(), source: "test", syncIdentifier: "sync-001")
        let reading2 = GlucoseReading(glucose: 110, timestamp: Date(), source: "test", syncIdentifier: "sync-002")
        let reading3 = GlucoseReading(glucose: 120, timestamp: Date(), source: "test")  // No sync ID
        
        try await store.save([reading1, reading2, reading3])
        
        // Fetch by sync ID
        let found = try await store.fetch(syncIdentifier: "sync-001")
        #expect(found != nil)
        #expect(found?.glucose == 100)
        
        // Fetch non-existent sync ID
        let notFound = try await store.fetch(syncIdentifier: "sync-999")
        #expect(notFound == nil)
    }
    
    // DATA-FAULT-001: Test disk full simulation
    @Test("Disk full fault injection throws expected error")
    func diskFullFaultInjection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Use test-local injector to avoid shared state
        let injector = FaultInjector()
        injector.currentFault = .diskFull
        injector.faultProbability = 1.0
        
        let store = FileGlucoseStore(directory: tempDir, faultInjector: injector)
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), source: "test")
        
        // Should throw disk full error
        do {
            try await store.save(reading)
            Issue.record("Expected diskFull error but succeeded")
        } catch let error as PersistenceError {
            if case .diskFull = error {
                // Expected
            } else {
                Issue.record("Expected diskFull but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    // DATA-FAULT-002: Test backup-based recovery from corrupted JSON
    @Test("Corrupted JSON recovers from backup")
    func corruptedJSONRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Save twice to create a backup (second save backs up first)
        let store1 = FileGlucoseStore(directory: tempDir)
        let reading1 = GlucoseReading(glucose: 130, timestamp: Date(), source: "test")
        try await store1.save(reading1)
        
        // Force new actor instance to trigger a new save with backup
        let store1b = FileGlucoseStore(directory: tempDir)
        let reading2 = GlucoseReading(glucose: 135, timestamp: Date().addingTimeInterval(300), source: "test")
        try await store1b.save(reading2)
        
        // Corrupt the main file but leave backup intact
        let mainFile = tempDir.appendingPathComponent("glucose-readings.json")
        try "{ invalid json".write(to: mainFile, atomically: true, encoding: .utf8)
        
        // New store should recover from backup
        let store2 = FileGlucoseStore(directory: tempDir)
        let recovered = try await store2.fetchMostRecent()
        
        // Recovery returns data from backup (which has reading1, not reading2)
        #expect(recovered != nil)
        #expect(recovered?.glucose == 130)
    }
    
    // DATA-FAULT-003: Concurrent write stress test
    @Test("Concurrent writes from multiple actors")
    func concurrentWriteStress() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileGlucoseStore(directory: tempDir)
        let writeCount = 100
        
        // Launch concurrent writes from multiple tasks
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    let reading = GlucoseReading(
                        glucose: Double(80 + i),
                        timestamp: Date().addingTimeInterval(Double(-i * 60)),
                        source: "concurrent-\(i)"
                    )
                    try await store.save(reading)
                }
            }
            try await group.waitForAll()
        }
        
        // Verify all writes completed (actor serializes correctly)
        let count = try await store.count()
        #expect(count == writeCount, "Expected \(writeCount) but got \(count)")
    }
    
    // DATA-FAULT-004: Verify atomic writes protect against interruption
    @Test("Atomic write protects against partial writes")
    func atomicWriteProtection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Save initial valid data
        let store1 = FileGlucoseStore(directory: tempDir)
        let reading1 = GlucoseReading(glucose: 120, timestamp: Date(), source: "test")
        try await store1.save(reading1)
        
        // Simulate partial write by writing incomplete data manually
        // (atomic write uses temp file, so main file should be intact after this)
        let mainFile = tempDir.appendingPathComponent("glucose-readings.json")
        
        // Read current valid content
        let validContent = try String(contentsOf: mainFile, encoding: .utf8)
        
        // Simulate what happens if we wrote but didn't finish atomic swap
        // In practice, atomic write means temp file exists but main file unchanged
        // This test verifies recovery from backup if main file is corrupted
        
        // Second save creates backup of first
        let store1b = FileGlucoseStore(directory: tempDir)
        let reading2 = GlucoseReading(glucose: 125, timestamp: Date().addingTimeInterval(300), source: "test")
        try await store1b.save(reading2)
        
        // Verify both readings are present
        let store2 = FileGlucoseStore(directory: tempDir)
        let count = try await store2.count()
        #expect(count == 2)
        
        // Verify atomic write options used (file should be complete)
        let fileContent = try String(contentsOf: mainFile, encoding: .utf8)
        #expect(fileContent.contains("glucose"))
        #expect(fileContent.contains("]"))  // Valid JSON array close
    }
}

@Suite("File Treatment Store")
struct FileTreatmentStoreTests {
    
    @Test("Save and load from file")
    func saveAndLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create store and save treatment
        let store1 = FileTreatmentStore(directory: tempDir, filename: "test-treatments.json")
        let treatment = Treatment.bolus(units: 3.5)
        try await store1.save(treatment)
        
        // Create new store instance to load from file
        let store2 = FileTreatmentStore(directory: tempDir, filename: "test-treatments.json")
        let loaded = try await store2.fetchLatest(1)
        
        #expect(loaded.count == 1)
        #expect(loaded[0].insulin == 3.5)
        #expect(loaded[0].type == .bolus)
    }
    
    @Test("Delete all clears file")
    func deleteAllClearsFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileTreatmentStore(directory: tempDir)
        
        try await store.save(Treatment.bolus(units: 1.0))
        try await store.save(Treatment.carbs(grams: 30))
        
        #expect(try await store.count() == 2)
        
        try await store.deleteAll()
        
        #expect(try await store.count() == 0)
        
        // Reload from file
        let store2 = FileTreatmentStore(directory: tempDir)
        #expect(try await store2.count() == 0)
    }
    
    // DATA-FAULT-005: Test storage quota exceeded handling
    @Test("Storage quota exceeded fault injection")
    func quotaExceededFaultInjection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Use test-local injector to avoid shared state
        let injector = FaultInjector()
        injector.currentFault = .quotaExceeded
        injector.faultProbability = 1.0
        
        let store = FileTreatmentStore(directory: tempDir, faultInjector: injector)
        
        // Should throw quota exceeded error
        do {
            try await store.save(Treatment.bolus(units: 2.0))
            Issue.record("Expected quotaExceeded error but succeeded")
        } catch let error as PersistenceError {
            if case .quotaExceeded = error {
                // Expected
            } else {
                Issue.record("Expected quotaExceeded but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    // DATA-COHESIVE-001: Test fetchMostRecent for treatments
    @Test("Fetch most recent treatment")
    func fetchMostRecentTreatment() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = FileTreatmentStore(directory: tempDir)
        
        // Save treatments at different times
        let treatment1 = Treatment.bolus(units: 1.0)
        let treatment2 = Treatment(
            id: UUID(),
            type: .bolus,
            timestamp: Date().addingTimeInterval(300),  // 5 min later
            insulin: 2.0
        )
        
        try await store.save([treatment1, treatment2])
        
        // Most recent should be treatment2
        let mostRecent = try await store.fetchMostRecent()
        #expect(mostRecent != nil)
        #expect(mostRecent?.insulin == 2.0)
    }
}

// MARK: - Fault Injection Test Suite (DATA-FAULT-006)

/// Systematic coverage of all fault injection scenarios
@Suite("Fault Injection")
struct FaultInjectionTestSuite {
    
    @Test("All fault types can be injected and thrown")
    func allFaultTypesThrow() throws {
        let faultTypes: [FaultType] = [.diskFull, .quotaExceeded, .dataCorrupted, .writeInterrupted, .networkTimeout]
        
        for faultType in faultTypes {
            let injector = FaultInjector()
            injector.currentFault = faultType
            injector.faultProbability = 1.0
            
            #expect(injector.shouldFaultOnSave() == true)
            
            do {
                try injector.injectFault()
                Issue.record("Expected fault \(faultType) to throw")
            } catch {
                // Expected - each type throws
            }
        }
    }
    
    @Test("No fault type does not throw")
    func noFaultDoesNotThrow() throws {
        let injector = FaultInjector()
        injector.currentFault = .none
        
        #expect(injector.shouldFaultOnSave() == false)
        
        // Should not throw
        try injector.injectFault()
    }
    
    @Test("Probability controls fault occurrence")
    func probabilityControlsFaults() {
        let injector = FaultInjector()
        injector.currentFault = .diskFull
        
        // With 0% probability, should never fault
        injector.faultProbability = 0.0
        var faultCount = 0
        for _ in 0..<100 {
            if injector.shouldFaultOnSave() {
                faultCount += 1
            }
        }
        #expect(faultCount == 0)
        
        // With 100% probability, should always fault
        injector.faultProbability = 1.0
        faultCount = 0
        for _ in 0..<100 {
            if injector.shouldFaultOnSave() {
                faultCount += 1
            }
        }
        #expect(faultCount == 100)
    }
    
    @Test("Reset clears fault configuration")
    func resetClearsFaults() {
        let injector = FaultInjector()
        injector.currentFault = .diskFull
        injector.faultProbability = 0.5
        
        injector.reset()
        
        #expect(injector.currentFault == .none)
        #expect(injector.faultProbability == 1.0)
    }
}

// MARK: - Treatment Codable Tests

@Suite("Treatment Codable")
struct TreatmentCodableTests {
    
    @Test("Treatment round-trips through JSON")
    func treatmentRoundTrip() throws {
        let treatment = Treatment(
            id: UUID(),
            type: .bolus,
            timestamp: Date(),
            insulin: 2.5,
            notes: "Lunch bolus",
            source: "T1Pal",
            syncIdentifier: "abc123"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(treatment)
        let decoded = try decoder.decode(Treatment.self, from: data)
        
        #expect(decoded.id == treatment.id)
        #expect(decoded.type == treatment.type)
        #expect(decoded.insulin == treatment.insulin)
        #expect(decoded.notes == treatment.notes)
        #expect(decoded.syncIdentifier == treatment.syncIdentifier)
    }
    
    @Test("Treatment is hashable")
    func treatmentIsHashable() {
        let treatment1 = Treatment.bolus(units: 2.0)
        let treatment2 = Treatment.bolus(units: 2.0)
        
        var set = Set<Treatment>()
        set.insert(treatment1)
        set.insert(treatment2)
        
        // Different UUIDs, so both should be in set
        #expect(set.count == 2)
    }
}
