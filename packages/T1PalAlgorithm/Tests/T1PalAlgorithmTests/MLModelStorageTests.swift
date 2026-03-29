// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLModelStorageTests.swift
// T1PalAlgorithm
//
// Tests for per-user ML model storage.
//
// Trace: ALG-SHADOW-030

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("ML Model Storage")
struct MLModelStorageTests {
    
    /// Creates a temp directory for testing
    private func createTempDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLModelStorageTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
    }
    
    /// Cleans up temp directory
    private func cleanup(_ tempDirectory: URL) {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test("Default config values")
    func defaultConfig() throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        
        #expect(config.maxVersions == 5)
        #expect(config.compressModels)
        #expect(config.autoCleanup)
    }
    
    @Test("Custom config values")
    func customConfig() throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(
            baseDirectory: tempDirectory,
            maxVersions: 10,
            compressModels: false,
            autoCleanup: false
        )
        
        #expect(config.maxVersions == 10)
        #expect(!config.compressModels)
        #expect(!config.autoCleanup)
    }
    
    // MARK: - Initialization Tests
    
    @Test("Initialization creates directory")
    func initialization() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        
        try await storage.initialize()
        
        // Should create base directory
        #expect(FileManager.default.fileExists(atPath: tempDirectory.path))
        
        // Should have empty versions
        let versions = await storage.listVersions()
        #expect(versions.isEmpty)
        
        let active = await storage.activeVersion()
        #expect(active == nil)
    }
    
    // MARK: - Save and Load Tests
    
    @Test("Save and load model")
    func saveAndLoadModel() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        // Create a model bundle
        let bundle = createTestBundle()
        let trainingResult = createTestTrainingResult()
        
        // Save
        let storedVersion = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        #expect(storedVersion.algorithmId == "test-algorithm")
        #expect(storedVersion.trainingRows == 4000)
        #expect(storedVersion.validationAccuracy == 0.85)
        #expect(!storedVersion.isExpired)
        
        // Should be active
        let active = await storage.activeVersion()
        #expect(active?.id == storedVersion.id)
        
        // Load
        let loadedBundle = try await storage.loadActive()
        #expect(loadedBundle.metadata.algorithmId == bundle.metadata.algorithmId)
        #expect(loadedBundle.metadata.version == bundle.metadata.version)
    }
    
    @Test("Multiple versions")
    func multipleVersions() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory, autoCleanup: false)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        // Save multiple versions
        let bundle1 = createTestBundle(version: "1.0")
        let bundle2 = createTestBundle(version: "2.0")
        let bundle3 = createTestBundle(version: "3.0")
        let trainingResult = createTestTrainingResult()
        
        _ = try await storage.save(bundle: bundle1, trainingResult: trainingResult)
        _ = try await storage.save(bundle: bundle2, trainingResult: trainingResult)
        let v3 = try await storage.save(bundle: bundle3, trainingResult: trainingResult)
        
        // Should have 3 versions
        let versions = await storage.listVersions()
        #expect(versions.count == 3)
        
        // Most recent should be first
        #expect(versions[0].version == "3.0")
        
        // Newest should be active (new training supersedes old)
        let active = await storage.activeVersion()
        #expect(active?.id == v3.id)
    }
    
    // MARK: - Version Management Tests
    
    @Test("Set active version")
    func setActiveVersion() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let bundle1 = createTestBundle(version: "1.0")
        let bundle2 = createTestBundle(version: "2.0")
        let trainingResult = createTestTrainingResult()
        
        let v1 = try await storage.save(bundle: bundle1, trainingResult: trainingResult)
        let v2 = try await storage.save(bundle: bundle2, trainingResult: trainingResult)
        
        // v2 should be active (newest)
        var active = await storage.activeVersion()
        #expect(active?.id == v2.id)
        
        // Change back to v1
        try await storage.setActive(versionId: v1.id)
        active = await storage.activeVersion()
        #expect(active?.id == v1.id)
    }
    
    @Test("Rollback")
    func rollback() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let bundle1 = createTestBundle(version: "1.0")
        let bundle2 = createTestBundle(version: "2.0")
        let trainingResult = createTestTrainingResult()
        
        let v1 = try await storage.save(bundle: bundle1, trainingResult: trainingResult)
        let v2 = try await storage.save(bundle: bundle2, trainingResult: trainingResult)
        
        // v2 is already active (newest)
        var active = await storage.activeVersion()
        #expect(active?.id == v2.id)
        
        // Rollback should return v1
        let rolled = try await storage.rollback()
        #expect(rolled?.id == v1.id)
        
        // Active should now be v1
        active = await storage.activeVersion()
        #expect(active?.id == v1.id)
    }
    
    @Test("Delete version")
    func deleteVersion() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let bundle1 = createTestBundle(version: "1.0")
        let bundle2 = createTestBundle(version: "2.0")
        let trainingResult = createTestTrainingResult()
        
        let v1 = try await storage.save(bundle: bundle1, trainingResult: trainingResult)
        let v2 = try await storage.save(bundle: bundle2, trainingResult: trainingResult)
        
        // Delete v2
        try await storage.delete(versionId: v2.id)
        
        let versions = await storage.listVersions()
        #expect(versions.count == 1)
        #expect(versions[0].id == v1.id)
    }
    
    // MARK: - Cleanup Tests
    
    @Test("Auto cleanup old versions")
    func autoCleanupOldVersions() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(
            baseDirectory: tempDirectory,
            maxVersions: 2,
            autoCleanup: true
        )
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let trainingResult = createTestTrainingResult()
        
        // Save 4 versions
        for i in 1...4 {
            let bundle = createTestBundle(version: "\(i).0")
            _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        }
        
        // Should only have maxVersions (2)
        let versions = await storage.listVersions()
        #expect(versions.count == 2)
        
        // Most recent should be preserved
        #expect(versions[0].version == "4.0")
        #expect(versions[1].version == "3.0")
    }
    
    // MARK: - Statistics Tests
    
    @Test("Statistics")
    func statistics() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let bundle = createTestBundle()
        let trainingResult = createTestTrainingResult()
        
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        let stats = await storage.statistics()
        
        #expect(stats.versionCount == 1)
        #expect(stats.activeVersionId != nil)
        #expect(stats.totalSizeBytes > 0)
        #expect(stats.expiredCount == 0)
    }
    
    @Test("Clear all")
    func clearAll() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let bundle = createTestBundle()
        let trainingResult = createTestTrainingResult()
        
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        // Clear
        try await storage.clearAll()
        
        let versions = await storage.listVersions()
        #expect(versions.isEmpty)
        
        let active = await storage.activeVersion()
        #expect(active == nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Load nonexistent version")
    func loadNonexistentVersion() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        do {
            _ = try await storage.load(versionId: "nonexistent-id")
            Issue.record("Should throw error")
        } catch MLModelStorageError.versionNotFound {
            // Expected
        }
    }
    
    @Test("Load active with no models")
    func loadActiveWithNoModels() async throws {
        let tempDirectory = try createTempDirectory()
        defer { cleanup(tempDirectory) }
        
        let config = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        do {
            _ = try await storage.loadActive()
            Issue.record("Should throw error")
        } catch MLModelStorageError.noActiveModel {
            // Expected
        }
    }
    
    // MARK: - StoredModelVersion Tests
    
    @Test("Stored model version expiration")
    func storedModelVersionExpiration() {
        let version = StoredModelVersion(
            id: "test",
            version: "1.0",
            algorithmId: "test",
            createdAt: Date(),
            trainingRows: 4000,
            validationAccuracy: 0.85,
            trainingDataRange: DateRange(
                start: Date().addingTimeInterval(-86400 * 14),
                end: Date()
            ),
            expiresAt: Date().addingTimeInterval(86400 * 90),
            fileSize: 1024,
            checksum: "abc123"
        )
        
        #expect(!version.isExpired)
        #expect(version.daysUntilExpiration > 85)
    }
    
    @Test("Date range duration")
    func dateRangeDuration() {
        let range = DateRange(
            start: Date().addingTimeInterval(-86400 * 14),
            end: Date()
        )
        
        #expect(range.durationInDays == 14)
    }
    
    // MARK: - Helper Methods
    
    private func createTestBundle(version: String = "1.0") -> MLModelBundle {
        let metadata = MLModelMetadata(
            modelId: UUID().uuidString,
            version: version,
            createdAt: Date(),
            trainingDataStart: Date().addingTimeInterval(-86400 * 14),
            trainingDataEnd: Date(),
            trainingRows: 4000,
            validationAccuracy: 0.85,
            algorithmId: "test-algorithm",
            expiresAt: Date().addingTimeInterval(86400 * 90)
        )
        
        let normalizer = FeatureNormalizer(
            means: ["glucose": 120, "iob": 3],
            stds: ["glucose": 30, "iob": 1.5],
            mins: ["glucose": 70, "iob": 0],
            maxs: ["glucose": 300, "iob": 10]
        )
        
        return MLModelBundle(
            metadata: metadata,
            normalizer: normalizer,
            modelData: nil
        )
    }
    
    private func createTestTrainingResult() -> MLTrainingResult {
        let metrics = TrainingMetrics(
            scalingFactorMAE: 0.08,
            scalingFactorRMSE: 0.12,
            within20Percent: 0.85,
            trainingDuration: 2.5,
            iterationsCompleted: 100
        )
        
        return MLTrainingResult.success(
            modelId: UUID().uuidString,
            modelVersion: "1.0",
            trainingRows: 4000,
            validationRows: 800,
            validationAccuracy: 0.85,
            metrics: metrics
        )
    }
}
