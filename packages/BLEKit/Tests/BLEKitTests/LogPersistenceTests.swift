// SPDX-License-Identifier: MIT
// LogPersistenceTests.swift
// Trace: BLE-DIAG-013

import Testing
import Foundation
@testable import BLEKit

// MARK: - Log Persistence Metadata Tests

@Suite("Log Persistence Metadata")
struct LogPersistenceMetadataTests {
    
    @Test("Empty metadata")
    func testEmptyMetadata() {
        let metadata = LogPersistenceMetadata.empty
        
        #expect(metadata.entryCount == 0)
        #expect(metadata.sizeBytes == 0)
        #expect(metadata.oldestEntry == nil)
        #expect(metadata.newestEntry == nil)
        #expect(metadata.lastSaved == nil)
    }
    
    @Test("Metadata with values")
    func testMetadataWithValues() {
        let now = Date()
        let metadata = LogPersistenceMetadata(
            entryCount: 100,
            sizeBytes: 5000,
            oldestEntry: now.addingTimeInterval(-3600),
            newestEntry: now,
            lastSaved: now,
            storageLocation: "TestLocation"
        )
        
        #expect(metadata.entryCount == 100)
        #expect(metadata.sizeBytes == 5000)
        #expect(metadata.oldestEntry != nil)
        #expect(metadata.newestEntry != nil)
        #expect(metadata.lastSaved != nil)
        #expect(metadata.storageLocation == "TestLocation")
    }
    
    @Test("Metadata is codable")
    func testMetadataCodable() throws {
        let original = LogPersistenceMetadata(
            entryCount: 50,
            sizeBytes: 2500,
            storageLocation: "Test"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LogPersistenceMetadata.self, from: data)
        
        #expect(decoded.entryCount == original.entryCount)
        #expect(decoded.sizeBytes == original.sizeBytes)
    }
}

// MARK: - Log Persistence Error Tests

@Suite("Log Persistence Errors")
struct LogPersistenceErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [LogPersistenceError] = [
            .encodingFailed("test"),
            .decodingFailed("test"),
            .writeError("test"),
            .readError("test"),
            .directoryCreationFailed("test"),
            .rotationFailed("test")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription!.contains("test"))
        }
    }
}

// MARK: - In-Memory Persistence Tests

@Suite("In-Memory Log Persistence")
struct InMemoryLogPersistenceTests {
    
    func makeEntries(count: Int) -> [TrafficEntry] {
        (0..<count).map { i in
            TrafficEntry(
                direction: i % 2 == 0 ? .outgoing : .incoming,
                data: Data([UInt8(i), 0x01, 0x02])
            )
        }
    }
    
    @Test("Save and load")
    func testSaveAndLoad() async throws {
        let persistence = InMemoryLogPersistence()
        let entries = makeEntries(count: 5)
        
        try await persistence.save(entries)
        let loaded = try await persistence.load()
        
        #expect(loaded.count == 5)
    }
    
    @Test("Clear")
    func testClear() async throws {
        let persistence = InMemoryLogPersistence()
        let entries = makeEntries(count: 5)
        
        try await persistence.save(entries)
        try await persistence.clear()
        let loaded = try await persistence.load()
        
        #expect(loaded.isEmpty)
    }
    
    @Test("Metadata")
    func testMetadata() async throws {
        let persistence = InMemoryLogPersistence()
        let entries = makeEntries(count: 10)
        
        try await persistence.save(entries)
        let metadata = await persistence.metadata()
        
        #expect(metadata.entryCount == 10)
        #expect(metadata.storageLocation == "InMemory")
    }
    
    @Test("Empty load returns empty array")
    func testEmptyLoad() async throws {
        let persistence = InMemoryLogPersistence()
        let loaded = try await persistence.load()
        
        #expect(loaded.isEmpty)
    }
}

// MARK: - UserDefaults Persistence Tests

@Suite("UserDefaults Log Persistence")
struct UserDefaultsLogPersistenceTests {
    
    let testConfig = UserDefaultsLogPersistence.Config(
        maxEntries: 50,
        storageKey: "com.t1pal.blekit.test-\(UUID().uuidString)"
    )
    
    func makeEntries(count: Int) -> [TrafficEntry] {
        (0..<count).map { i in
            TrafficEntry(
                direction: i % 2 == 0 ? .outgoing : .incoming,
                data: Data([UInt8(i % 256), 0x01, 0x02])
            )
        }
    }
    
    @Test("Save and load")
    func testSaveAndLoad() async throws {
        let key = "com.t1pal.blekit.test-save-\(UUID().uuidString)"
        let config = UserDefaultsLogPersistence.Config(
            maxEntries: 50,
            storageKey: key
        )
        let persistence = UserDefaultsLogPersistence(config: config)
        let entries = makeEntries(count: 10)
        
        try await persistence.save(entries)
        
        // Small delay to ensure UserDefaults sync on Linux
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        
        // Create new persistence with same key to verify actual storage
        let persistence2 = UserDefaultsLogPersistence(config: config)
        let loaded = try await persistence2.load()
        
        #expect(loaded.count == 10)
        
        // Cleanup
        try await persistence.clear()
    }
    
    @Test("Respects max entries limit")
    func testMaxEntriesLimit() async throws {
        let config = UserDefaultsLogPersistence.Config(
            maxEntries: 20,
            storageKey: "com.t1pal.blekit.test-limit-\(UUID().uuidString)"
        )
        let persistence = UserDefaultsLogPersistence(config: config)
        let entries = makeEntries(count: 100)
        
        try await persistence.save(entries)
        
        // Allow time for UserDefaults sync on Linux
        try await Task.sleep(for: .milliseconds(100))
        
        let loaded = try await persistence.load()
        
        #expect(loaded.count == 20)
        
        // Cleanup
        try await persistence.clear()
    }
    
    @Test("Clear removes data")
    func testClear() async throws {
        let config = UserDefaultsLogPersistence.Config(
            maxEntries: 50,
            storageKey: "com.t1pal.blekit.test-clear-\(UUID().uuidString)"
        )
        let persistence = UserDefaultsLogPersistence(config: config)
        let entries = makeEntries(count: 5)
        
        try await persistence.save(entries)
        try await persistence.clear()
        let loaded = try await persistence.load()
        
        #expect(loaded.isEmpty)
    }
    
    @Test("Metadata reports correctly")
    func testMetadata() async throws {
        let config = UserDefaultsLogPersistence.Config(
            maxEntries: 50,
            storageKey: "com.t1pal.blekit.test-meta-\(UUID().uuidString)"
        )
        let persistence = UserDefaultsLogPersistence(config: config)
        let entries = makeEntries(count: 15)
        
        try await persistence.save(entries)
        let metadata = await persistence.metadata()
        
        #expect(metadata.entryCount == 15)
        #expect(metadata.sizeBytes > 0)
        #expect(metadata.storageLocation.contains("UserDefaults"))
        
        // Cleanup
        try await persistence.clear()
    }
    
    @Test("Empty persistence returns empty array")
    func testEmptyPersistence() async throws {
        let config = UserDefaultsLogPersistence.Config(
            storageKey: "com.t1pal.blekit.test-empty-\(UUID().uuidString)"
        )
        let persistence = UserDefaultsLogPersistence(config: config)
        
        let loaded = try await persistence.load()
        #expect(loaded.isEmpty)
    }
}

// MARK: - File Persistence Tests

@Suite("File Log Persistence")
struct FileLogPersistenceTests {
    
    func testDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BLEKitTests-\(UUID().uuidString)", isDirectory: true)
    }
    
    func makeEntries(count: Int) -> [TrafficEntry] {
        (0..<count).map { i in
            TrafficEntry(
                direction: i % 2 == 0 ? .outgoing : .incoming,
                data: Data([UInt8(i % 256), 0x01, 0x02])
            )
        }
    }
    
    @Test("Save and load")
    func testSaveAndLoad() async throws {
        let dir = testDirectory()
        let config = FileLogPersistence.Config(
            maxFileSize: 1024 * 1024,
            directory: dir
        )
        let persistence = FileLogPersistence(config: config)
        let entries = makeEntries(count: 10)
        
        try await persistence.save(entries)
        let loaded = try await persistence.load()
        
        #expect(loaded.count == 10)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
    
    @Test("Clear removes files")
    func testClear() async throws {
        let dir = testDirectory()
        let config = FileLogPersistence.Config(directory: dir)
        let persistence = FileLogPersistence(config: config)
        let entries = makeEntries(count: 5)
        
        try await persistence.save(entries)
        try await persistence.clear()
        let loaded = try await persistence.load()
        
        #expect(loaded.isEmpty)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
    
    @Test("Metadata reports correctly")
    func testMetadata() async throws {
        let dir = testDirectory()
        let config = FileLogPersistence.Config(directory: dir)
        let persistence = FileLogPersistence(config: config)
        let entries = makeEntries(count: 20)
        
        try await persistence.save(entries)
        let metadata = await persistence.metadata()
        
        #expect(metadata.entryCount == 20)
        #expect(metadata.sizeBytes > 0)
        #expect(metadata.storageLocation == dir.path)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
    
    @Test("Empty persistence returns empty array")
    func testEmptyPersistence() async throws {
        let dir = testDirectory()
        let config = FileLogPersistence.Config(directory: dir)
        let persistence = FileLogPersistence(config: config)
        
        let loaded = try await persistence.load()
        #expect(loaded.isEmpty)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
    
    @Test("Total size calculation")
    func testTotalSize() async throws {
        let dir = testDirectory()
        let config = FileLogPersistence.Config(directory: dir)
        let persistence = FileLogPersistence(config: config)
        let entries = makeEntries(count: 50)
        
        try await persistence.save(entries)
        let size = await persistence.totalSize()
        
        #expect(size > 0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - BLETrafficLogger Persistence Extension Tests

@Suite("BLETrafficLogger Persistence")
struct BLETrafficLoggerPersistenceTests {
    
    func makeLogger(count: Int) -> BLETrafficLogger {
        let logger = BLETrafficLogger()
        for i in 0..<count {
            logger.log(
                direction: i % 2 == 0 ? .outgoing : .incoming,
                data: Data([UInt8(i % 256), 0x01, 0x02])
            )
        }
        return logger
    }
    
    @Test("Save to persistence")
    func testSaveToPersistence() async throws {
        let logger = makeLogger(count: 10)
        let persistence = InMemoryLogPersistence()
        
        try await logger.save(to: persistence)
        let metadata = await persistence.metadata()
        
        #expect(metadata.entryCount == 10)
    }
    
    @Test("Load from persistence replaces entries")
    func testLoadFromPersistence() async throws {
        let persistence = InMemoryLogPersistence()
        
        // Save some entries
        let entries = (0..<5).map { i in
            TrafficEntry(direction: .outgoing, data: Data([UInt8(i)]))
        }
        try await persistence.save(entries)
        
        // Load into logger
        let logger = BLETrafficLogger()
        logger.log(direction: .incoming, data: Data([0xFF])) // Add one entry
        
        try await logger.load(from: persistence, append: false)
        
        #expect(logger.count == 5)
    }
    
    @Test("Load from persistence appends entries")
    func testLoadFromPersistenceAppend() async throws {
        let persistence = InMemoryLogPersistence()
        
        // Save some entries
        let entries = (0..<5).map { i in
            TrafficEntry(direction: .outgoing, data: Data([UInt8(i)]))
        }
        try await persistence.save(entries)
        
        // Load into logger with existing entries
        let logger = BLETrafficLogger()
        logger.log(direction: .incoming, data: Data([0xFF]))
        
        try await logger.load(from: persistence, append: true)
        
        #expect(logger.count == 6)
    }
    
    @Test("Clear persistence")
    func testClearPersistence() async throws {
        let logger = makeLogger(count: 10)
        let persistence = InMemoryLogPersistence()
        
        try await logger.save(to: persistence)
        try await logger.clearPersistence(persistence)
        
        let loaded = try await persistence.load()
        #expect(loaded.isEmpty)
    }
    
    @Test("Get persistence metadata")
    func testPersistenceMetadata() async throws {
        let logger = makeLogger(count: 15)
        let persistence = InMemoryLogPersistence()
        
        try await logger.save(to: persistence)
        let metadata = await logger.persistenceMetadata(persistence)
        
        #expect(metadata.entryCount == 15)
    }
}

// MARK: - Auto-Persisting Logger Tests

@Suite("Auto-Persisting Traffic Logger")
struct AutoPersistingTrafficLoggerTests {
    
    @Test("Basic logging")
    func testBasicLogging() async {
        let persistence = InMemoryLogPersistence()
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 0, // Disable auto-save
            saveThreshold: 0 // Disable threshold save
        )
        
        autoLogger.log(direction: .outgoing, data: Data([0x01, 0x02]))
        autoLogger.log(direction: .incoming, data: Data([0x03, 0x04]))
        
        #expect(autoLogger.logger.count == 2)
    }
    
    @Test("Save threshold triggers save")
    func testSaveThreshold() async throws {
        let persistence = InMemoryLogPersistence()
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 0,
            saveThreshold: 5
        )
        
        // Log 5 entries to trigger threshold
        for i in 0..<5 {
            autoLogger.log(direction: .outgoing, data: Data([UInt8(i)]))
        }
        
        // Poll for async save completion (up to 2 seconds)
        var metadata = await persistence.metadata()
        for _ in 0..<20 where metadata.entryCount < 5 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            metadata = await persistence.metadata()
        }
        
        #expect(metadata.entryCount == 5)
    }
    
    @Test("Manual save")
    func testManualSave() async throws {
        let persistence = InMemoryLogPersistence()
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 0,
            saveThreshold: 0
        )
        
        autoLogger.log(direction: .outgoing, data: Data([0x01]))
        autoLogger.log(direction: .outgoing, data: Data([0x02]))
        
        await autoLogger.saveNow()
        
        let metadata = await persistence.metadata()
        #expect(metadata.entryCount == 2)
    }
    
    @Test("Load from persistence")
    func testLoadFromPersistence() async throws {
        let persistence = InMemoryLogPersistence()
        
        // Pre-populate persistence
        let entries = (0..<3).map { i in
            TrafficEntry(direction: .outgoing, data: Data([UInt8(i)]))
        }
        try await persistence.save(entries)
        
        // Create logger and load
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 0,
            saveThreshold: 0
        )
        
        try await autoLogger.loadFromPersistence()
        
        #expect(autoLogger.logger.count == 3)
    }
    
    @Test("Metadata access")
    func testMetadataAccess() async throws {
        let persistence = InMemoryLogPersistence()
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 0,
            saveThreshold: 0
        )
        
        autoLogger.log(direction: .outgoing, data: Data([0x01]))
        await autoLogger.saveNow()
        
        let metadata = await autoLogger.metadata()
        #expect(metadata.entryCount == 1)
    }
    
    @Test("Stop auto-save")
    func testStopAutoSave() async {
        let persistence = InMemoryLogPersistence()
        let autoLogger = AutoPersistingTrafficLogger(
            persistence: persistence,
            autoSaveInterval: 1,
            saveThreshold: 0
        )
        
        autoLogger.stopAutoSave()
        
        // Just verify it doesn't crash
        #expect(autoLogger.logger.count == 0)
    }
}

// MARK: - File Persistence Config Tests

@Suite("File Persistence Configuration")
struct FileLogPersistenceConfigTests {
    
    @Test("Default config")
    func testDefaultConfig() {
        let config = FileLogPersistence.Config.default
        
        #expect(config.maxFileSize == 5 * 1024 * 1024)
        #expect(config.maxRotatedFiles == 5)
        #expect(config.maxAge == 7 * 24 * 3600)
        #expect(config.baseFilename == "ble-traffic")
    }
    
    @Test("Testing config")
    func testTestingConfig() {
        let config = FileLogPersistence.Config.testing
        
        #expect(config.maxFileSize == 1024)
        #expect(config.maxRotatedFiles == 2)
        #expect(config.maxAge == 60)
        #expect(config.baseFilename == "test-ble-traffic")
    }
    
    @Test("Custom config")
    func testCustomConfig() {
        let customDir = FileManager.default.temporaryDirectory
        let config = FileLogPersistence.Config(
            maxFileSize: 1000,
            maxRotatedFiles: 3,
            maxAge: 120,
            baseFilename: "custom-log",
            directory: customDir
        )
        
        #expect(config.maxFileSize == 1000)
        #expect(config.maxRotatedFiles == 3)
        #expect(config.maxAge == 120)
        #expect(config.baseFilename == "custom-log")
        #expect(config.directory == customDir)
    }
}

// MARK: - UserDefaults Persistence Config Tests

@Suite("UserDefaults Persistence Configuration")
struct UserDefaultsLogPersistenceConfigTests {
    
    @Test("Default config")
    func testDefaultConfig() {
        let config = UserDefaultsLogPersistence.Config.default
        
        #expect(config.maxEntries == 1000)
        #expect(config.suiteName == nil)
        #expect(config.storageKey == "com.t1pal.blekit.traffic-log")
    }
    
    @Test("Testing config")
    func testTestingConfig() {
        let config = UserDefaultsLogPersistence.Config.testing
        
        #expect(config.maxEntries == 100)
        #expect(config.storageKey == "com.t1pal.blekit.traffic-log-test")
    }
    
    @Test("Custom config")
    func testCustomConfig() {
        let config = UserDefaultsLogPersistence.Config(
            maxEntries: 500,
            suiteName: "group.test",
            storageKey: "custom.key"
        )
        
        #expect(config.maxEntries == 500)
        #expect(config.suiteName == "group.test")
        #expect(config.storageKey == "custom.key")
    }
}
