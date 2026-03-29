// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// StoreMigration.swift - JSON to SQLite migration coordinator
// Part of T1PalCore
// Trace: BENCH-IMPL-003
// See: docs/architecture/PERSISTENCE-DATA-PATTERNS.md

import Foundation

// MARK: - Migration State

/// Tracks migration progress and history.
/// Persisted to UserDefaults for cross-launch state.
/// Trace: BENCH-IMPL-003
public final class MigrationState: @unchecked Sendable {
    public static let shared = MigrationState()
    
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.t1pal.migration.state")
    
    // UserDefaults keys
    private enum Keys {
        static let migrationComplete = "t1pal.migration.complete"
        static let migrationStartedAt = "t1pal.migration.startedAt"
        static let migrationCompletedAt = "t1pal.migration.completedAt"
        static let migrationFailureCount = "t1pal.migration.failureCount"
        static let migrationLastError = "t1pal.migration.lastError"
        static let migrationRecordCount = "t1pal.migration.recordCount"
        static let autoMigrationDisabled = "t1pal.migration.autoDisabled"
    }
    
    private init() {}
    
    /// Whether migration has completed successfully.
    public var isComplete: Bool {
        queue.sync { defaults.bool(forKey: Keys.migrationComplete) }
    }
    
    /// Whether auto-migration is disabled (after too many failures).
    public var isAutoMigrationDisabled: Bool {
        queue.sync { defaults.bool(forKey: Keys.autoMigrationDisabled) }
    }
    
    /// Number of migration failures.
    public var failureCount: Int {
        queue.sync { defaults.integer(forKey: Keys.migrationFailureCount) }
    }
    
    /// Last error message if migration failed.
    public var lastError: String? {
        queue.sync { defaults.string(forKey: Keys.migrationLastError) }
    }
    
    /// Timestamp when migration started.
    public var startedAt: Date? {
        queue.sync { defaults.object(forKey: Keys.migrationStartedAt) as? Date }
    }
    
    /// Timestamp when migration completed.
    public var completedAt: Date? {
        queue.sync { defaults.object(forKey: Keys.migrationCompletedAt) as? Date }
    }
    
    /// Record count migrated.
    public var recordCount: Int {
        queue.sync { defaults.integer(forKey: Keys.migrationRecordCount) }
    }
    
    /// Mark migration as started.
    public func markStarted() {
        queue.sync {
            defaults.set(Date(), forKey: Keys.migrationStartedAt)
            defaults.set(false, forKey: Keys.migrationComplete)
        }
    }
    
    /// Mark migration as complete.
    public func markComplete(recordCount: Int) {
        queue.sync {
            defaults.set(true, forKey: Keys.migrationComplete)
            defaults.set(Date(), forKey: Keys.migrationCompletedAt)
            defaults.set(recordCount, forKey: Keys.migrationRecordCount)
            defaults.removeObject(forKey: Keys.migrationLastError)
        }
    }
    
    /// Record a migration failure.
    public func recordFailure(_ error: Error) {
        queue.sync {
            let count = defaults.integer(forKey: Keys.migrationFailureCount) + 1
            defaults.set(count, forKey: Keys.migrationFailureCount)
            defaults.set(error.localizedDescription, forKey: Keys.migrationLastError)
            defaults.set(false, forKey: Keys.migrationComplete)
            
            // Disable auto-migration after 3 failures
            if count >= 3 {
                defaults.set(true, forKey: Keys.autoMigrationDisabled)
            }
        }
    }
    
    /// Reset migration state (for manual retry).
    public func reset() {
        queue.sync {
            defaults.removeObject(forKey: Keys.migrationComplete)
            defaults.removeObject(forKey: Keys.migrationStartedAt)
            defaults.removeObject(forKey: Keys.migrationCompletedAt)
            defaults.removeObject(forKey: Keys.migrationFailureCount)
            defaults.removeObject(forKey: Keys.migrationLastError)
            defaults.removeObject(forKey: Keys.migrationRecordCount)
            defaults.removeObject(forKey: Keys.autoMigrationDisabled)
        }
    }
    
    /// Re-enable auto-migration (for manual override).
    public func enableAutoMigration() {
        queue.sync {
            defaults.set(false, forKey: Keys.autoMigrationDisabled)
            defaults.set(0, forKey: Keys.migrationFailureCount)
        }
    }
}

// MARK: - Migration Error

/// Errors that can occur during migration.
/// Trace: BENCH-IMPL-003
public enum MigrationError: Error, LocalizedError, Sendable {
    case alreadyInProgress
    case countMismatch(json: Int, grdb: Int)
    case loadFailed(String)
    case saveFailed(String)
    case verificationFailed(String)
    case autoMigrationDisabled
    
    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "Migration is already in progress"
        case .countMismatch(let json, let grdb):
            return "Count mismatch after migration: JSON=\(json), GRDB=\(grdb)"
        case .loadFailed(let reason):
            return "Failed to load from JSON: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save to SQLite: \(reason)"
        case .verificationFailed(let reason):
            return "Verification failed: \(reason)"
        case .autoMigrationDisabled:
            return "Auto-migration disabled due to repeated failures"
        }
    }
}

// MARK: - Migration Progress

/// Progress callback for migration UI.
public struct MigrationProgress: Sendable {
    public let phase: Phase
    public let current: Int
    public let total: Int
    public let message: String
    
    public enum Phase: String, Sendable {
        case starting = "Starting"
        case loading = "Loading"
        case saving = "Saving"
        case verifying = "Verifying"
        case complete = "Complete"
        case failed = "Failed"
    }
    
    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Migration Coordinator (Cross-Platform)
// ADR-012: GRDB works on Linux with auto-disabled SNAPSHOT

import GRDB

/// Coordinates migration from JSON to SQLite storage.
/// Trace: BENCH-IMPL-003
public actor MigrationCoordinator {
    public static let shared = MigrationCoordinator()
    
    public enum State: Sendable {
        case idle
        case migrating
        case verifying
        case complete
        case failed(Error)
    }
    
    private(set) public var state: State = .idle
    private var progressCallback: (@Sendable (MigrationProgress) -> Void)?
    
    private init() {}
    
    /// Set progress callback for UI updates.
    public func setProgressCallback(_ callback: (@Sendable (MigrationProgress) -> Void)?) {
        self.progressCallback = callback
    }
    
    /// Check if migration should auto-trigger.
    public nonisolated func shouldAutoMigrate() -> Bool {
        guard !MigrationState.shared.isComplete else { return false }
        guard !MigrationState.shared.isAutoMigrationDisabled else { return false }
        return true // Could add threshold checks here
    }
    
    /// Start glucose store migration.
    public func migrateGlucoseStore() async throws -> Int {
        guard case .idle = state else {
            throw MigrationError.alreadyInProgress
        }
        
        guard !MigrationState.shared.isAutoMigrationDisabled else {
            throw MigrationError.autoMigrationDisabled
        }
        
        state = .migrating
        MigrationState.shared.markStarted()
        
        report(.init(phase: .starting, current: 0, total: 0, message: "Initializing migration"))
        
        do {
            // 1. Create stores
            let grdbStore = try GRDBGlucoseStore.defaultStore()
            let jsonStore = FileGlucoseStore.defaultStore()
            
            // 2. Get total count for progress
            let totalCount = try await jsonStore.count()
            report(.init(phase: .loading, current: 0, total: totalCount, message: "Loading \(totalCount) records"))
            
            // 3. Migrate in batches - use wide date range to get all
            let batchSize = 5000
            var migrated = 0
            
            // Fetch all using very wide date range (1970 to now)
            let allReadings = try await jsonStore.fetch(from: Date.distantPast, to: Date.distantFuture)
            
            for batch in stride(from: 0, to: allReadings.count, by: batchSize) {
                let end = min(batch + batchSize, allReadings.count)
                let batchData = Array(allReadings[batch..<end])
                
                report(.init(phase: .saving, current: migrated, total: totalCount, 
                            message: "Saving batch \(batch/batchSize + 1)"))
                
                try await grdbStore.save(batchData)
                migrated += batchData.count
            }
            
            // 4. Verify
            state = .verifying
            report(.init(phase: .verifying, current: migrated, total: totalCount, message: "Verifying migration"))
            
            let grdbCount = try await grdbStore.count()
            guard totalCount == grdbCount else {
                throw MigrationError.countMismatch(json: totalCount, grdb: grdbCount)
            }
            
            // 5. Complete
            state = .complete
            MigrationState.shared.markComplete(recordCount: migrated)
            report(.init(phase: .complete, current: migrated, total: totalCount, 
                        message: "Migrated \(migrated) records"))
            
            return migrated
            
        } catch {
            state = .failed(error)
            MigrationState.shared.recordFailure(error)
            report(.init(phase: .failed, current: 0, total: 0, message: error.localizedDescription))
            throw error
        }
    }
    
    /// Reset for retry.
    public func reset() {
        state = .idle
        MigrationState.shared.reset()
    }
    
    private func report(_ progress: MigrationProgress) {
        progressCallback?(progress)
    }
}

// MARK: - Glucose Store Factory

/// Factory for creating platform-appropriate glucose stores.
/// Trace: BENCH-IMPL-003
public struct GlucoseStoreFactory {
    /// Create the default glucose store for the current platform.
    public static func createDefault() -> any GlucoseStore {
        // Check if GRDB migration is complete
        if MigrationState.shared.isComplete {
            do {
                return try GRDBGlucoseStore.defaultStore()
            } catch {
                // Fall back to JSON if GRDB fails
                return FileGlucoseStore.defaultStore()
            }
        }
        
        // Check if auto-migration should trigger
        if MigrationCoordinator.shared.shouldAutoMigrate() {
            Task {
                do {
                    _ = try await MigrationCoordinator.shared.migrateGlucoseStore()
                } catch {
                    // Migration failed, continue with JSON
                }
            }
        }
        
        return FileGlucoseStore.defaultStore()
    }
    
    /// Force creation of GRDB store (for testing or manual migration).
    public static func createGRDB() throws -> GRDBGlucoseStore {
        try GRDBGlucoseStore.defaultStore()
    }
    
    /// Create JSON-based store (for fallback or Linux).
    public static func createJSON() -> FileGlucoseStore {
        FileGlucoseStore.defaultStore()
    }
    
    /// Create a glucose store for a specific followed user (FOLLOW-CACHE-002).
    /// Uses per-user SQLite isolation for multi-user cache separation.
    /// Path: ~/Application Support/T1Pal/followed/{userId}/glucose.sqlite
    public static func createForUser(_ userId: UUID) -> any GlucoseStore {
        do {
            return try GRDBGlucoseStore.createForUser(userId)
        } catch {
            // Fall back to shared store if per-user fails
            return createDefault()
        }
    }
}

// MARK: - Device Status Store Factory

/// Factory for creating platform-appropriate device status stores.
/// Trace: BENCH-IMPL-003
public struct DeviceStatusStoreFactory {
    /// Create the default device status store for the current platform.
    public static func createDefault() -> any DeviceStatusStore {
        // For now, always use GRDB on Darwin since DeviceStatus is new
        do {
            return try GRDBDeviceStatusStore.defaultStore()
        } catch {
            // No fallback for DeviceStatus - it's a new store
            fatalError("Failed to create DeviceStatusStore: \(error)")
        }
    }
    
    /// Create in-memory store for testing.
    public static func createInMemory() throws -> GRDBDeviceStatusStore {
        try GRDBDeviceStatusStore.inMemoryStore()
    }
}

// MARK: - Proposal Store Factory

/// Factory for creating platform-appropriate proposal stores.
/// Trace: BENCH-IMPL-003
public struct ProposalStoreFactory {
    /// Create the default proposal store for the current platform.
    public static func createDefault() -> any ProposalStore {
        // Proposals are new, always use GRDB on Darwin
        do {
            return try GRDBProposalStore.defaultStore()
        } catch {
            fatalError("Failed to create ProposalStore: \(error)")
        }
    }
    
    /// Create in-memory store for testing.
    public static func createInMemory() throws -> GRDBProposalStore {
        try GRDBProposalStore.inMemoryStore()
    }
}

// MARK: - Treatment Store Factory

/// Factory for creating platform-appropriate treatment stores.
/// Trace: BENCH-IMPL-005
public struct TreatmentStoreFactory {
    /// Create the default treatment store for the current platform.
    public static func createDefault() -> any TreatmentStore {
        // Try GRDB first on Darwin
        do {
            return try GRDBTreatmentStore.defaultStore()
        } catch {
            // Fall back to JSON if GRDB fails
            return FileTreatmentStore.defaultStore()
        }
    }
    
    /// Force creation of GRDB store (for testing or manual migration).
    public static func createGRDB() throws -> GRDBTreatmentStore {
        try GRDBTreatmentStore.defaultStore()
    }
    
    /// Create JSON-based store (for fallback or Linux).
    public static func createJSON() -> FileTreatmentStore {
        FileTreatmentStore.defaultStore()
    }
    
    /// Create in-memory store for testing.
    public static func createInMemory() throws -> GRDBTreatmentStore {
        try GRDBTreatmentStore.inMemoryStore()
    }
}

// MARK: - Follower Cache Migration (FOLLOW-CACHE-005)

/// Handles migration from legacy shared cache to per-user cache isolation.
/// On first launch after upgrade, clears ambiguous shared follower data.
/// Trace: FOLLOW-CACHE-005, ADR-013
public final class FollowerCacheMigration: @unchecked Sendable {
    public static let shared = FollowerCacheMigration()
    
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.t1pal.follower.cache.migration")
    
    private enum Keys {
        static let migrationComplete = "t1pal.follower.cache.migration.complete"
        static let migrationDate = "t1pal.follower.cache.migration.date"
        static let legacyCacheCleared = "t1pal.follower.cache.legacy.cleared"
    }
    
    private init() {}
    
    /// Whether the follower cache migration has been completed.
    public var isComplete: Bool {
        queue.sync { defaults.bool(forKey: Keys.migrationComplete) }
    }
    
    /// Date when migration was completed.
    public var completedAt: Date? {
        queue.sync { defaults.object(forKey: Keys.migrationDate) as? Date }
    }
    
    /// Whether legacy cache was found and cleared.
    public var legacyCacheWasCleared: Bool {
        queue.sync { defaults.bool(forKey: Keys.legacyCacheCleared) }
    }
    
    /// Run the migration if not already completed.
    /// Call this at app launch for the Follower app.
    /// - Returns: true if migration ran and cleared data, false if already complete or no data to clear
    @discardableResult
    public func runIfNeeded() -> Bool {
        if isComplete {
            return false
        }
        
        let cleared = clearLegacySharedCache()
        markComplete(clearedData: cleared)
        return cleared
    }
    
    /// Clear the legacy shared glucose cache that may contain mixed user data.
    /// The legacy path is ~/Application Support/T1Pal/glucose.sqlite (shared)
    /// vs the new per-user path ~/Application Support/T1Pal/followed/{userId}/glucose.sqlite
    private func clearLegacySharedCache() -> Bool {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        
        // Check for legacy shared cache file (non-per-user)
        let legacyGlucosePath = appSupport.appendingPathComponent("T1Pal/glucose.sqlite")
        let legacyGlucoseWalPath = appSupport.appendingPathComponent("T1Pal/glucose.sqlite-wal")
        let legacyGlucoseShmPath = appSupport.appendingPathComponent("T1Pal/glucose.sqlite-shm")
        
        var clearedAny = false
        
        // Only clear if the "followed" directory exists (indicates we're using per-user stores)
        // This prevents clearing the main app's glucose store
        let followedDir = appSupport.appendingPathComponent("T1Pal/followed")
        guard fileManager.fileExists(atPath: followedDir.path) else {
            // Not a follower app context, skip
            return false
        }
        
        // Clear legacy files if they exist
        for path in [legacyGlucosePath, legacyGlucoseWalPath, legacyGlucoseShmPath] {
            if fileManager.fileExists(atPath: path.path) {
                do {
                    try fileManager.removeItem(at: path)
                    clearedAny = true
                } catch {
                    // Log but continue
                    print("[FOLLOW-CACHE-005] Failed to clear \(path.lastPathComponent): \(error)")
                }
            }
        }
        
        if clearedAny {
            print("[FOLLOW-CACHE-005] Cleared legacy shared glucose cache")
        }
        
        return clearedAny
    }
    
    private func markComplete(clearedData: Bool) {
        queue.sync {
            defaults.set(true, forKey: Keys.migrationComplete)
            defaults.set(Date(), forKey: Keys.migrationDate)
            defaults.set(clearedData, forKey: Keys.legacyCacheCleared)
        }
    }
    
    /// Reset migration state (for testing).
    public func reset() {
        queue.sync {
            defaults.removeObject(forKey: Keys.migrationComplete)
            defaults.removeObject(forKey: Keys.migrationDate)
            defaults.removeObject(forKey: Keys.legacyCacheCleared)
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance

extension MigrationError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .storage }
    
    public var code: String {
        switch self {
        case .alreadyInProgress: return "MIG-PROGRESS-001"
        case .countMismatch: return "MIG-COUNT-001"
        case .loadFailed: return "MIG-LOAD-001"
        case .saveFailed: return "MIG-SAVE-001"
        case .verificationFailed: return "MIG-VERIFY-001"
        case .autoMigrationDisabled: return "MIG-DISABLED-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .alreadyInProgress: return .warning
        case .countMismatch, .verificationFailed: return .error
        case .loadFailed, .saveFailed: return .critical
        case .autoMigrationDisabled: return .warning
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .alreadyInProgress: return .waitAndRetry
        case .countMismatch, .verificationFailed: return .retry
        case .loadFailed, .saveFailed: return .contactSupport
        case .autoMigrationDisabled: return .contactSupport
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown migration error"
    }
}
