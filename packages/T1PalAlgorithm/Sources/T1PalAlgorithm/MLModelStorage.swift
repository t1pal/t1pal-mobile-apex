// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLModelStorage.swift
// T1PalAlgorithm
//
// Per-user ML model storage with versioning and rollback capability.
// Persists trained models, normalizers, and metadata to disk.
//
// Trace: ALG-SHADOW-030, PRD-028

import Foundation

// MARK: - Storage Configuration

/// Configuration for ML model storage
public struct MLModelStorageConfig: Codable, Sendable {
    /// Base directory for model storage
    public let baseDirectory: URL
    
    /// Maximum number of model versions to retain
    public let maxVersions: Int
    
    /// Whether to compress stored models
    public let compressModels: Bool
    
    /// Whether to auto-cleanup old versions
    public let autoCleanup: Bool
    
    public init(
        baseDirectory: URL,
        maxVersions: Int = 5,
        compressModels: Bool = true,
        autoCleanup: Bool = true
    ) {
        self.baseDirectory = baseDirectory
        self.maxVersions = maxVersions
        self.compressModels = compressModels
        self.autoCleanup = autoCleanup
    }
    
    /// Default storage in app's documents directory
    public static func defaultConfig() -> MLModelStorageConfig? {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        
        let mlModelsDir = documentsURL.appendingPathComponent("MLModels", isDirectory: true)
        return MLModelStorageConfig(baseDirectory: mlModelsDir)
    }
}

// MARK: - Stored Model Version

/// A stored model version with metadata
public struct StoredModelVersion: Codable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let algorithmId: String
    public let createdAt: Date
    public let trainingRows: Int
    public let validationAccuracy: Double
    public let trainingDataRange: DateRange
    public let expiresAt: Date
    public let fileSize: Int64
    public let checksum: String
    
    /// Whether this version has expired
    public var isExpired: Bool {
        Date() > expiresAt
    }
    
    /// Days until expiration
    public var daysUntilExpiration: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
    }
}

/// Date range for training data
public struct DateRange: Codable, Sendable {
    public let start: Date
    public let end: Date
    
    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
    
    public var durationInDays: Int {
        Int(duration / 86400)
    }
}

// MARK: - Storage Index

/// Index of all stored models
struct StorageIndex: Codable {
    var versions: [StoredModelVersion]
    var activeVersionId: String?
    var lastUpdated: Date
    
    init() {
        self.versions = []
        self.activeVersionId = nil
        self.lastUpdated = Date()
    }
    
    mutating func addVersion(_ version: StoredModelVersion) {
        versions.append(version)
        versions.sort { $0.createdAt > $1.createdAt }  // Most recent first
        lastUpdated = Date()
    }
    
    mutating func removeVersion(id: String) {
        versions.removeAll { $0.id == id }
        if activeVersionId == id {
            activeVersionId = versions.first?.id
        }
        lastUpdated = Date()
    }
    
    mutating func setActive(id: String) {
        if versions.contains(where: { $0.id == id }) {
            activeVersionId = id
            lastUpdated = Date()
        }
    }
    
    var activeVersion: StoredModelVersion? {
        guard let id = activeVersionId else { return nil }
        return versions.first { $0.id == id }
    }
}

// MARK: - Model Bundle

/// A complete model bundle with all artifacts
public struct MLModelBundle: Sendable {
    public let metadata: MLModelMetadata
    public let normalizer: FeatureNormalizer
    public let modelData: Data?  // CoreML model data (nil if placeholder)
    
    public init(
        metadata: MLModelMetadata,
        normalizer: FeatureNormalizer,
        modelData: Data? = nil
    ) {
        self.metadata = metadata
        self.normalizer = normalizer
        self.modelData = modelData
    }
}

/// Serializable bundle for storage
struct SerializedModelBundle: Codable {
    let metadata: MLModelMetadata
    let normalizer: FeatureNormalizer
    let hasModelData: Bool
}

// MARK: - Storage Errors

public enum MLModelStorageError: Error, LocalizedError {
    case storageNotConfigured
    case versionNotFound(String)
    case corruptedData(String)
    case writeError(Error)
    case readError(Error)
    case checksumMismatch
    case noActiveModel
    
    public var errorDescription: String? {
        switch self {
        case .storageNotConfigured:
            return "Model storage not configured"
        case .versionNotFound(let id):
            return "Model version not found: \(id)"
        case .corruptedData(let reason):
            return "Corrupted model data: \(reason)"
        case .writeError(let error):
            return "Failed to write model: \(error.localizedDescription)"
        case .readError(let error):
            return "Failed to read model: \(error.localizedDescription)"
        case .checksumMismatch:
            return "Model checksum mismatch - data may be corrupted"
        case .noActiveModel:
            return "No active model available"
        }
    }
}

// MARK: - ML Model Storage Actor

/// Per-user ML model storage with versioning and rollback
public actor MLModelStorage {
    
    // MARK: - State
    
    private let config: MLModelStorageConfig
    private var index: StorageIndex
    private var isInitialized: Bool = false
    
    // MARK: - Initialization
    
    public init(config: MLModelStorageConfig) {
        self.config = config
        self.index = StorageIndex()
    }
    
    /// Initialize storage, creating directories and loading index
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        // Create base directory
        try FileManager.default.createDirectory(
            at: config.baseDirectory,
            withIntermediateDirectories: true
        )
        
        // Load existing index
        let indexURL = indexFileURL
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            index = try JSONDecoder().decode(StorageIndex.self, from: data)
        }
        
        // Cleanup expired if enabled
        if config.autoCleanup {
            await cleanupExpired()
        }
        
        isInitialized = true
    }
    
    // MARK: - File Paths
    
    private var indexFileURL: URL {
        config.baseDirectory.appendingPathComponent("index.json")
    }
    
    private func versionDirectory(id: String) -> URL {
        config.baseDirectory.appendingPathComponent("v_\(id)", isDirectory: true)
    }
    
    private func bundleFileURL(versionId: String) -> URL {
        versionDirectory(id: versionId).appendingPathComponent("bundle.json")
    }
    
    private func modelDataFileURL(versionId: String) -> URL {
        versionDirectory(id: versionId).appendingPathComponent("model.mlmodel")
    }
    
    // MARK: - Save Operations
    
    /// Save a trained model bundle
    public func save(
        bundle: MLModelBundle,
        trainingResult: MLTrainingResult
    ) async throws -> StoredModelVersion {
        try await ensureInitialized()
        
        let versionId = UUID().uuidString
        let versionDir = versionDirectory(id: versionId)
        
        // Create version directory
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        
        // Serialize bundle
        let serializedBundle = SerializedModelBundle(
            metadata: bundle.metadata,
            normalizer: bundle.normalizer,
            hasModelData: bundle.modelData != nil
        )
        
        let bundleData = try JSONEncoder().encode(serializedBundle)
        try bundleData.write(to: bundleFileURL(versionId: versionId))
        
        // Save model data if present
        if let modelData = bundle.modelData {
            try modelData.write(to: modelDataFileURL(versionId: versionId))
        }
        
        // Calculate checksum
        let checksum = calculateChecksum(bundleData)
        
        // Calculate file size
        let fileSize = try FileManager.default.attributesOfItem(
            atPath: bundleFileURL(versionId: versionId).path
        )[.size] as? Int64 ?? 0
        
        // Create stored version entry
        let storedVersion = StoredModelVersion(
            id: versionId,
            version: bundle.metadata.version,
            algorithmId: bundle.metadata.algorithmId,
            createdAt: Date(),
            trainingRows: trainingResult.trainingRows,
            validationAccuracy: trainingResult.validationAccuracy ?? 0,
            trainingDataRange: DateRange(
                start: bundle.metadata.trainingDataStart,
                end: bundle.metadata.trainingDataEnd
            ),
            expiresAt: bundle.metadata.expiresAt,
            fileSize: fileSize,
            checksum: checksum
        )
        
        // Update index
        index.addVersion(storedVersion)
        
        // Set newest as active (new training supersedes old)
        index.activeVersionId = versionId
        
        // Persist index
        try await persistIndex()
        
        // Cleanup old versions if needed
        if config.autoCleanup {
            await cleanupOldVersions()
        }
        
        return storedVersion
    }
    
    // MARK: - Load Operations
    
    /// Load the active model bundle
    public func loadActive() async throws -> MLModelBundle {
        try await ensureInitialized()
        
        guard let activeId = index.activeVersionId else {
            throw MLModelStorageError.noActiveModel
        }
        
        return try await load(versionId: activeId)
    }
    
    /// Load a specific model version
    public func load(versionId: String) async throws -> MLModelBundle {
        try await ensureInitialized()
        
        guard index.versions.contains(where: { $0.id == versionId }) else {
            throw MLModelStorageError.versionNotFound(versionId)
        }
        
        let bundleURL = bundleFileURL(versionId: versionId)
        
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw MLModelStorageError.versionNotFound(versionId)
        }
        
        do {
            let bundleData = try Data(contentsOf: bundleURL)
            let serialized = try JSONDecoder().decode(SerializedModelBundle.self, from: bundleData)
            
            // Load model data if exists
            var modelData: Data? = nil
            let modelDataURL = modelDataFileURL(versionId: versionId)
            if serialized.hasModelData && FileManager.default.fileExists(atPath: modelDataURL.path) {
                modelData = try Data(contentsOf: modelDataURL)
            }
            
            return MLModelBundle(
                metadata: serialized.metadata,
                normalizer: serialized.normalizer,
                modelData: modelData
            )
        } catch {
            throw MLModelStorageError.readError(error)
        }
    }
    
    // MARK: - Version Management
    
    /// List all stored versions
    public func listVersions() async -> [StoredModelVersion] {
        return index.versions
    }
    
    /// Get the active version
    public func activeVersion() async -> StoredModelVersion? {
        return index.activeVersion
    }
    
    /// Set the active version (rollback)
    public func setActive(versionId: String) async throws {
        try await ensureInitialized()
        
        guard index.versions.contains(where: { $0.id == versionId }) else {
            throw MLModelStorageError.versionNotFound(versionId)
        }
        
        index.setActive(id: versionId)
        try await persistIndex()
    }
    
    /// Delete a specific version
    public func delete(versionId: String) async throws {
        try await ensureInitialized()
        
        // Can't delete active version unless it's the only one
        if versionId == index.activeVersionId && index.versions.count > 1 {
            // Activate the next most recent
            let nextVersion = index.versions.first { $0.id != versionId }
            if let next = nextVersion {
                index.setActive(id: next.id)
            }
        }
        
        // Remove from index
        index.removeVersion(id: versionId)
        
        // Delete files
        let versionDir = versionDirectory(id: versionId)
        if FileManager.default.fileExists(atPath: versionDir.path) {
            try FileManager.default.removeItem(at: versionDir)
        }
        
        try await persistIndex()
    }
    
    /// Rollback to previous version
    public func rollback() async throws -> StoredModelVersion? {
        try await ensureInitialized()
        
        guard let currentId = index.activeVersionId,
              let currentIndex = index.versions.firstIndex(where: { $0.id == currentId }),
              currentIndex < index.versions.count - 1 else {
            return nil  // No previous version
        }
        
        // Versions are sorted most recent first, so "previous" is the next in array
        let previousVersion = index.versions[currentIndex + 1]
        try await setActive(versionId: previousVersion.id)
        
        return previousVersion
    }
    
    // MARK: - Cleanup
    
    /// Remove expired versions
    public func cleanupExpired() async {
        let expiredIds = index.versions.filter { $0.isExpired }.map { $0.id }
        
        for id in expiredIds {
            // Don't delete if it's the only version
            if index.versions.count > 1 {
                try? await delete(versionId: id)
            }
        }
    }
    
    /// Remove old versions beyond maxVersions
    private func cleanupOldVersions() async {
        while index.versions.count > config.maxVersions {
            // Remove oldest (last in sorted array)
            if let oldest = index.versions.last, oldest.id != index.activeVersionId {
                try? await delete(versionId: oldest.id)
            } else {
                break  // Don't delete active version
            }
        }
    }
    
    /// Clear all stored models
    public func clearAll() async throws {
        try await ensureInitialized()
        
        // Remove all version directories
        for version in index.versions {
            let versionDir = versionDirectory(id: version.id)
            if FileManager.default.fileExists(atPath: versionDir.path) {
                try FileManager.default.removeItem(at: versionDir)
            }
        }
        
        // Reset index
        index = StorageIndex()
        try await persistIndex()
    }
    
    // MARK: - Statistics
    
    /// Get storage statistics
    public func statistics() async -> MLModelStorageStats {
        let totalSize = index.versions.reduce(0) { $0 + $1.fileSize }
        let oldestDate = index.versions.last?.createdAt
        let newestDate = index.versions.first?.createdAt
        
        return MLModelStorageStats(
            versionCount: index.versions.count,
            activeVersionId: index.activeVersionId,
            totalSizeBytes: totalSize,
            oldestVersion: oldestDate,
            newestVersion: newestDate,
            expiredCount: index.versions.filter { $0.isExpired }.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }
    
    private func persistIndex() async throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexFileURL)
    }
    
    private func calculateChecksum(_ data: Data) -> String {
        // Simple checksum using hash
        var hasher = Hasher()
        hasher.combine(data)
        let hash = hasher.finalize()
        return String(format: "%08x", abs(hash))
    }
}

// MARK: - Storage Statistics

/// Statistics about model storage
public struct MLModelStorageStats: Sendable {
    public let versionCount: Int
    public let activeVersionId: String?
    public let totalSizeBytes: Int64
    public let oldestVersion: Date?
    public let newestVersion: Date?
    public let expiredCount: Int
    
    /// Total size in human-readable format
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSizeBytes)
    }
}

// MARK: - MLTrainingPipeline Integration

extension MLTrainingPipeline {
    
    /// Save trained model to storage
    public func saveToStorage(
        _ storage: MLModelStorage,
        result: MLTrainingResult
    ) async throws -> StoredModelVersion? {
        guard result.success,
              let activeModel = self.activeModel,
              let normalizer = self.featureNormalizer else {
            return nil
        }
        
        let bundle = MLModelBundle(
            metadata: activeModel,
            normalizer: normalizer,
            modelData: nil  // CoreML data would go here
        )
        
        return try await storage.save(bundle: bundle, trainingResult: result)
    }
    
    /// Load model from storage
    public func loadFromStorage(_ storage: MLModelStorage) async throws -> Bool {
        _ = try await storage.loadActive()
        
        // Restore pipeline state from bundle
        // This would restore normalizer and model metadata
        // Actual implementation depends on pipeline internals
        
        return true
    }
}
