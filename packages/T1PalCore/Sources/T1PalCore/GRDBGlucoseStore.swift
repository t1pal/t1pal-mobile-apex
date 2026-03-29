// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// GRDBGlucoseStore.swift - SQLite-backed glucose store using GRDB
// Trace: DATA-MIGRATE-003, ADR-012
// See: docs/architecture/ADR-012-sqlite-backend-strategy.md
//
// NOTE: GRDB works cross-platform. Linux auto-disables SNAPSHOT via Package.swift.
// GRDB 7.x builds on Linux (Swift 6.1+) with contributor-maintained support.

import Foundation
import GRDB

// MARK: - GRDB Record Type

/// GRDB-compatible record for glucose readings.
/// Conforms to FetchableRecord and PersistableRecord for database operations.
public struct GlucoseReadingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "glucose_readings"
    
    public let id: String  // UUID as string
    public let glucose: Double
    public let timestamp: Date
    public let trend: String
    public let source: String
    public let syncIdentifier: String?
    
    public init(from reading: GlucoseReading) {
        self.id = reading.id.uuidString
        self.glucose = reading.glucose
        self.timestamp = reading.timestamp
        self.trend = reading.trend.rawValue
        self.source = reading.source
        self.syncIdentifier = reading.syncIdentifier
    }
    
    public func toGlucoseReading() -> GlucoseReading {
        GlucoseReading(
            id: UUID(uuidString: id) ?? UUID(),
            glucose: glucose,
            timestamp: timestamp,
            trend: GlucoseTrend(rawValue: trend) ?? .flat,
            source: source,
            syncIdentifier: syncIdentifier
        )
    }
}

// MARK: - Database Migration

/// Database migrator for glucose store schema.
public struct GlucoseStoreMigrator {
    public static func migrate(_ db: Database) throws {
        // Version 1: Initial schema
        try db.create(table: GlucoseReadingRecord.databaseTableName, ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("glucose", .double).notNull()
            t.column("timestamp", .datetime).notNull().indexed()
            t.column("trend", .text).notNull()
            t.column("source", .text).notNull()
            t.column("syncIdentifier", .text).indexed()
        }
        
        // Create index for date range queries
        try db.create(index: "idx_glucose_timestamp", on: GlucoseReadingRecord.databaseTableName,
                      columns: ["timestamp"], ifNotExists: true)
    }
}

// MARK: - GRDB Glucose Store

/// SQLite-backed glucose store using GRDB.
/// Provides O(log n) indexed queries vs O(n) JSON filter.
/// Trace: DATA-MIGRATE-003
public actor GRDBGlucoseStore: GlucoseStore {
    private let dbWriter: any DatabaseWriter
    private let metrics: any MetricsCollector
    
    /// Initialize with a database writer.
    public init(dbWriter: any DatabaseWriter, metrics: (any MetricsCollector)? = nil) throws {
        self.dbWriter = dbWriter
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        // Run migrations synchronously during init
        try dbWriter.write { db in
            try GlucoseStoreMigrator.migrate(db)
        }
    }
    
    /// Initialize with a file path for the SQLite database.
    public init(path: String, metrics: (any MetricsCollector)? = nil) throws {
        let dbQueue = try DatabaseQueue(path: path)
        self.dbWriter = dbQueue
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbQueue.write { db in
            try GlucoseStoreMigrator.migrate(db)
        }
    }
    
    /// Create a default store in app support directory.
    public static func defaultStore() throws -> GRDBGlucoseStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("glucose.sqlite").path
        return try GRDBGlucoseStore(path: dbPath)
    }
    
    /// Create an in-memory store for testing.
    public static func inMemoryStore() throws -> GRDBGlucoseStore {
        let dbQueue = try DatabaseQueue()
        return try GRDBGlucoseStore(dbWriter: dbQueue)
    }
    
    /// Create a glucose store for a specific followed user (FOLLOW-CACHE-001).
    /// Path: ~/Application Support/T1Pal/followed/{userId}/glucose.sqlite
    public static func createForUser(_ userId: UUID) throws -> GRDBGlucoseStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed/\(userId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("glucose.sqlite").path
        
        // FOLLOW-CACHE-003: Update access time for retention tracking
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: directory.path
        )
        
        return try GRDBGlucoseStore(path: dbPath)
    }
    
    // MARK: - Cache Retention (FOLLOW-CACHE-003)
    
    /// Configuration for per-user cache retention policy.
    public struct RetentionPolicy {
        /// How long to keep inactive user caches (default: 30 days)
        public let maxInactivityDays: Int
        
        /// Default retention policy: 30 days of inactivity
        public static let standard = RetentionPolicy(maxInactivityDays: 30)
        
        /// Aggressive retention for testing: 1 day
        public static let aggressive = RetentionPolicy(maxInactivityDays: 1)
        
        public init(maxInactivityDays: Int) {
            self.maxInactivityDays = maxInactivityDays
        }
    }
    
    /// Clean up per-user cache directories that haven't been accessed recently.
    /// Returns the number of user caches deleted.
    /// - Parameter policy: Retention policy defining max inactivity period
    public static func cleanupInactiveUserCaches(policy: RetentionPolicy = .standard) throws -> Int {
        let fileManager = FileManager.default
        let followedDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed", isDirectory: true)
        
        guard fileManager.fileExists(atPath: followedDir.path) else {
            return 0
        }
        
        let cutoffDate = Date().addingTimeInterval(-Double(policy.maxInactivityDays) * 24 * 60 * 60)
        var deletedCount = 0
        
        let contents = try fileManager.contentsOfDirectory(
            at: followedDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        for userDir in contents {
            // Only process UUID directories
            guard UUID(uuidString: userDir.lastPathComponent) != nil else {
                continue
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: userDir.path)
            if let modDate = attributes[.modificationDate] as? Date,
               modDate < cutoffDate {
                try fileManager.removeItem(at: userDir)
                deletedCount += 1
            }
        }
        
        return deletedCount
    }
    
    /// List all per-user cache directories with their last access dates.
    /// Useful for diagnostics and monitoring cache usage.
    public static func listUserCaches() throws -> [(userId: UUID, lastAccess: Date, sizeBytes: Int64)] {
        let fileManager = FileManager.default
        let followedDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed", isDirectory: true)
        
        guard fileManager.fileExists(atPath: followedDir.path) else {
            return []
        }
        
        var results: [(userId: UUID, lastAccess: Date, sizeBytes: Int64)] = []
        
        let contents = try fileManager.contentsOfDirectory(
            at: followedDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        for userDir in contents {
            guard let userId = UUID(uuidString: userDir.lastPathComponent) else {
                continue
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: userDir.path)
            let modDate = attributes[.modificationDate] as? Date ?? Date.distantPast
            
            // Calculate total size of directory contents
            var totalSize: Int64 = 0
            if let enumerator = fileManager.enumerator(at: userDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    let fileAttributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                    if let size = fileAttributes?[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }
            
            results.append((userId: userId, lastAccess: modDate, sizeBytes: totalSize))
        }
        
        return results.sorted { $0.lastAccess > $1.lastAccess }
    }
    
    // MARK: - GlucoseStore Protocol
    
    public func save(_ reading: GlucoseReading) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.save", duration: duration, tags: ["count": "1"])
        }
        
        let record = GlucoseReadingRecord(from: reading)
        try await dbWriter.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }
    
    public func save(_ readings: [GlucoseReading]) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.save", duration: duration, tags: ["count": "\(readings.count)"])
        }
        
        let records = readings.map { GlucoseReadingRecord(from: $0) }
        try await dbWriter.write { db in
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [GlucoseReading] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.fetch_range", duration: duration, tags: [:])
        }
        
        let records = try await dbWriter.read { db in
            try GlucoseReadingRecord
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toGlucoseReading() }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [GlucoseReading] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.fetch_latest", duration: duration, tags: ["count": "\(count)"])
        }
        
        let records = try await dbWriter.read { db in
            try GlucoseReadingRecord
                .order(Column("timestamp").desc)
                .limit(count)
                .fetchAll(db)
        }
        return records.map { $0.toGlucoseReading() }
    }
    
    public func fetchMostRecent() async throws -> GlucoseReading? {
        let results = try await fetchLatest(1)
        return results.first
    }
    
    public func fetch(syncIdentifier: String) async throws -> GlucoseReading? {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.fetch_sync_id", duration: duration, tags: [:])
        }
        
        let record = try await dbWriter.read { db in
            try GlucoseReadingRecord
                .filter(Column("syncIdentifier") == syncIdentifier)
                .fetchOne(db)
        }
        return record?.toGlucoseReading()
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.delete_old", duration: duration, tags: [:])
        }
        
        return try await dbWriter.write { db in
            try GlucoseReadingRecord
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
    
    public func deleteAll() async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_glucose_store.delete_all", duration: duration, tags: [:])
        }
        
        _ = try await dbWriter.write { db in
            try GlucoseReadingRecord.deleteAll(db)
        }
    }
    
    public func count() async throws -> Int {
        try await dbWriter.read { db in
            try GlucoseReadingRecord.fetchCount(db)
        }
    }
    
    // MARK: - GRDB-Specific Features
    
    /// Vacuum the database to reclaim space after deletions.
    public func vacuum() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    /// Get database file size in bytes.
    public func databaseSize() async throws -> Int64 {
        try await dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
            return row?["size"] ?? 0
        }
    }
}

// MARK: - Device Status GRDB Record

/// GRDB-compatible record for device status.
/// Trace: BENCH-IMPL-001
public struct DeviceStatusRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "device_status"
    
    public let id: String  // UUID as string
    public let timestamp: Date
    public let device: String
    public let iob: Double?
    public let cob: Double?
    public let eventualBG: Double?
    public let recommendedBolus: Double?
    public let pumpBattery: Double?
    public let reservoirUnits: Double?
    public let suspended: Bool
    public let uploaderBattery: Double?
    public let source: String
    public let syncIdentifier: String?
    
    public init(from status: DeviceStatus) {
        self.id = status.id.uuidString
        self.timestamp = status.timestamp
        self.device = status.device
        self.iob = status.iob
        self.cob = status.cob
        self.eventualBG = status.eventualBG
        self.recommendedBolus = status.recommendedBolus
        self.pumpBattery = status.pumpBattery
        self.reservoirUnits = status.reservoirUnits
        self.suspended = status.suspended
        self.uploaderBattery = status.uploaderBattery
        self.source = status.source
        self.syncIdentifier = status.syncIdentifier
    }
    
    public func toDeviceStatus() -> DeviceStatus {
        DeviceStatus(
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: timestamp,
            device: device,
            iob: iob,
            cob: cob,
            eventualBG: eventualBG,
            recommendedBolus: recommendedBolus,
            pumpBattery: pumpBattery,
            reservoirUnits: reservoirUnits,
            suspended: suspended,
            uploaderBattery: uploaderBattery,
            source: source,
            syncIdentifier: syncIdentifier
        )
    }
}

// MARK: - Device Status Database Migration

/// Database migrator for device status schema.
public struct DeviceStatusMigrator {
    public static func migrate(_ db: Database) throws {
        try db.create(table: DeviceStatusRecord.databaseTableName, ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("timestamp", .datetime).notNull().indexed()
            t.column("device", .text).notNull()
            t.column("iob", .double)
            t.column("cob", .double)
            t.column("eventualBG", .double)
            t.column("recommendedBolus", .double)
            t.column("pumpBattery", .double)
            t.column("reservoirUnits", .double)
            t.column("suspended", .boolean).notNull().defaults(to: false)
            t.column("uploaderBattery", .double)
            t.column("source", .text).notNull()
            t.column("syncIdentifier", .text).indexed()
        }
        
        // Create index for date range queries
        try db.create(index: "idx_devicestatus_timestamp", on: DeviceStatusRecord.databaseTableName,
                      columns: ["timestamp"], ifNotExists: true)
    }
}

// MARK: - GRDB Device Status Store

/// SQLite-backed device status store using GRDB.
/// DeviceStatus is the largest dataset (~288/day).
/// Trace: BENCH-IMPL-001
public actor GRDBDeviceStatusStore: DeviceStatusStore {
    private let dbWriter: any DatabaseWriter
    private let metrics: any MetricsCollector
    
    /// Initialize with a database writer.
    public init(dbWriter: any DatabaseWriter, metrics: (any MetricsCollector)? = nil) throws {
        self.dbWriter = dbWriter
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbWriter.write { db in
            try DeviceStatusMigrator.migrate(db)
        }
    }
    
    /// Initialize with a file path for the SQLite database.
    public init(path: String, metrics: (any MetricsCollector)? = nil) throws {
        let dbQueue = try DatabaseQueue(path: path)
        self.dbWriter = dbQueue
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbQueue.write { db in
            try DeviceStatusMigrator.migrate(db)
        }
    }
    
    /// Create a default store in app support directory.
    public static func defaultStore() throws -> GRDBDeviceStatusStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("devicestatus.sqlite").path
        return try GRDBDeviceStatusStore(path: dbPath)
    }
    
    /// Create an in-memory store for testing.
    public static func inMemoryStore() throws -> GRDBDeviceStatusStore {
        let dbQueue = try DatabaseQueue()
        return try GRDBDeviceStatusStore(dbWriter: dbQueue)
    }
    
    // MARK: - DeviceStatusStore Protocol
    
    public func save(_ status: DeviceStatus) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.save", duration: duration, tags: ["count": "1"])
        }
        
        let record = DeviceStatusRecord(from: status)
        try await dbWriter.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }
    
    public func save(_ statuses: [DeviceStatus]) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.save", duration: duration, tags: ["count": "\(statuses.count)"])
        }
        
        let records = statuses.map { DeviceStatusRecord(from: $0) }
        try await dbWriter.write { db in
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [DeviceStatus] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.fetch_range", duration: duration, tags: [:])
        }
        
        let records = try await dbWriter.read { db in
            try DeviceStatusRecord
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toDeviceStatus() }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [DeviceStatus] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.fetch_latest", duration: duration, tags: ["count": "\(count)"])
        }
        
        let records = try await dbWriter.read { db in
            try DeviceStatusRecord
                .order(Column("timestamp").desc)
                .limit(count)
                .fetchAll(db)
        }
        return records.map { $0.toDeviceStatus() }
    }
    
    public func fetchMostRecent() async throws -> DeviceStatus? {
        let results = try await fetchLatest(1)
        return results.first
    }
    
    public func fetch(syncIdentifier: String) async throws -> DeviceStatus? {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.fetch_sync_id", duration: duration, tags: [:])
        }
        
        let record = try await dbWriter.read { db in
            try DeviceStatusRecord
                .filter(Column("syncIdentifier") == syncIdentifier)
                .fetchOne(db)
        }
        return record?.toDeviceStatus()
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.delete_old", duration: duration, tags: [:])
        }
        
        return try await dbWriter.write { db in
            try DeviceStatusRecord
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
    
    public func deleteAll() async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_devicestatus_store.delete_all", duration: duration, tags: [:])
        }
        
        _ = try await dbWriter.write { db in
            try DeviceStatusRecord.deleteAll(db)
        }
    }
    
    public func count() async throws -> Int {
        try await dbWriter.read { db in
            try DeviceStatusRecord.fetchCount(db)
        }
    }
    
    // MARK: - GRDB-Specific Features
    
    /// Vacuum the database to reclaim space after deletions.
    public func vacuum() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    /// Get database file size in bytes.
    public func databaseSize() async throws -> Int64 {
        try await dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
            return row?["size"] ?? 0
        }
    }
}

// MARK: - Proposal GRDB Record

/// GRDB-compatible record for agent proposals.
/// Trace: BENCH-IMPL-002
public struct ProposalRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "proposals"
    
    public let id: String  // UUID as string
    public let timestamp: Date
    public let agentId: String
    public let agentName: String
    public let proposalType: String
    public let description: String
    public let rationale: String
    public let expiresAt: Date
    public var status: String
    public var reviewedBy: String?
    public var reviewedAt: Date?
    public var reviewNote: String?
    public let detailsJSON: String?
    
    public init(from proposal: PersistenceAgentProposal) {
        self.id = proposal.id.uuidString
        self.timestamp = proposal.timestamp
        self.agentId = proposal.agentId
        self.agentName = proposal.agentName
        self.proposalType = proposal.proposalType.rawValue
        self.description = proposal.description
        self.rationale = proposal.rationale
        self.expiresAt = proposal.expiresAt
        self.status = proposal.status.rawValue
        self.reviewedBy = proposal.reviewedBy
        self.reviewedAt = proposal.reviewedAt
        self.reviewNote = proposal.reviewNote
        self.detailsJSON = proposal.detailsJSON
    }
    
    public func toProposal() -> PersistenceAgentProposal {
        PersistenceAgentProposal(
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: timestamp,
            agentId: agentId,
            agentName: agentName,
            proposalType: PersistenceProposalType(rawValue: proposalType) ?? .annotation,
            description: description,
            rationale: rationale,
            expiresAt: expiresAt,
            status: PersistenceProposalStatus(rawValue: status) ?? .pending,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            reviewNote: reviewNote,
            detailsJSON: detailsJSON
        )
    }
}

// MARK: - Proposal Database Migration

/// Database migrator for proposal store schema.
public struct ProposalMigrator {
    public static func migrate(_ db: Database) throws {
        try db.create(table: ProposalRecord.databaseTableName, ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("timestamp", .datetime).notNull().indexed()
            t.column("agentId", .text).notNull().indexed()
            t.column("agentName", .text).notNull()
            t.column("proposalType", .text).notNull()
            t.column("description", .text).notNull()
            t.column("rationale", .text).notNull()
            t.column("expiresAt", .datetime).notNull()
            t.column("status", .text).notNull().indexed()
            t.column("reviewedBy", .text)
            t.column("reviewedAt", .datetime)
            t.column("reviewNote", .text)
            t.column("detailsJSON", .text)
        }
        
        // Create indexes for common queries
        try db.create(index: "idx_proposal_timestamp", on: ProposalRecord.databaseTableName,
                      columns: ["timestamp"], ifNotExists: true)
        try db.create(index: "idx_proposal_status", on: ProposalRecord.databaseTableName,
                      columns: ["status"], ifNotExists: true)
    }
}

// MARK: - GRDB Proposal Store

/// SQLite-backed proposal store using GRDB.
/// Stores agent proposals for propose-authorize-enact workflow.
/// Trace: BENCH-IMPL-002
public actor GRDBProposalStore: ProposalStore {
    private let dbWriter: any DatabaseWriter
    private let metrics: any MetricsCollector
    
    /// Initialize with a database writer.
    public init(dbWriter: any DatabaseWriter, metrics: (any MetricsCollector)? = nil) throws {
        self.dbWriter = dbWriter
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbWriter.write { db in
            try ProposalMigrator.migrate(db)
        }
    }
    
    /// Initialize with a file path for the SQLite database.
    public init(path: String, metrics: (any MetricsCollector)? = nil) throws {
        let dbQueue = try DatabaseQueue(path: path)
        self.dbWriter = dbQueue
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbQueue.write { db in
            try ProposalMigrator.migrate(db)
        }
    }
    
    /// Create a default store in app support directory.
    public static func defaultStore() throws -> GRDBProposalStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("proposals.sqlite").path
        return try GRDBProposalStore(path: dbPath)
    }
    
    /// Create an in-memory store for testing.
    public static func inMemoryStore() throws -> GRDBProposalStore {
        let dbQueue = try DatabaseQueue()
        return try GRDBProposalStore(dbWriter: dbQueue)
    }
    
    // MARK: - ProposalStore Protocol
    
    public func save(_ proposal: PersistenceAgentProposal) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.save", duration: duration, tags: ["count": "1"])
        }
        
        let record = ProposalRecord(from: proposal)
        try await dbWriter.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }
    
    public func save(_ proposals: [PersistenceAgentProposal]) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.save", duration: duration, tags: ["count": "\(proposals.count)"])
        }
        
        let records = proposals.map { ProposalRecord(from: $0) }
        try await dbWriter.write { db in
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [PersistenceAgentProposal] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.fetch_range", duration: duration, tags: [:])
        }
        
        let records = try await dbWriter.read { db in
            try ProposalRecord
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toProposal() }
    }
    
    public func fetch(status: PersistenceProposalStatus) async throws -> [PersistenceAgentProposal] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.fetch_status", duration: duration, tags: ["status": status.rawValue])
        }
        
        let records = try await dbWriter.read { db in
            try ProposalRecord
                .filter(Column("status") == status.rawValue)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toProposal() }
    }
    
    public func fetchPending() async throws -> [PersistenceAgentProposal] {
        try await fetch(status: .pending)
    }
    
    public func fetchLatest(_ count: Int) async throws -> [PersistenceAgentProposal] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.fetch_latest", duration: duration, tags: ["count": "\(count)"])
        }
        
        let records = try await dbWriter.read { db in
            try ProposalRecord
                .order(Column("timestamp").desc)
                .limit(count)
                .fetchAll(db)
        }
        return records.map { $0.toProposal() }
    }
    
    public func fetch(id: UUID) async throws -> PersistenceAgentProposal? {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.fetch_id", duration: duration, tags: [:])
        }
        
        let record = try await dbWriter.read { db in
            try ProposalRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
        return record?.toProposal()
    }
    
    public func update(_ proposal: PersistenceAgentProposal) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.update", duration: duration, tags: [:])
        }
        
        let record = ProposalRecord(from: proposal)
        try await dbWriter.write { db in
            try record.update(db)
        }
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.delete_old", duration: duration, tags: [:])
        }
        
        return try await dbWriter.write { db in
            try ProposalRecord
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
    
    public func deleteAll() async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_proposal_store.delete_all", duration: duration, tags: [:])
        }
        
        _ = try await dbWriter.write { db in
            try ProposalRecord.deleteAll(db)
        }
    }
    
    public func count() async throws -> Int {
        try await dbWriter.read { db in
            try ProposalRecord.fetchCount(db)
        }
    }
    
    public func countPending() async throws -> Int {
        try await dbWriter.read { db in
            try ProposalRecord
                .filter(Column("status") == PersistenceProposalStatus.pending.rawValue)
                .fetchCount(db)
        }
    }
    
    // MARK: - GRDB-Specific Features
    
    /// Vacuum the database to reclaim space after deletions.
    public func vacuum() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    /// Get database file size in bytes.
    public func databaseSize() async throws -> Int64 {
        try await dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
            return row?["size"] ?? 0
        }
    }
}

// MARK: - Treatment GRDB Record

/// GRDB-compatible record for treatments.
/// Trace: BENCH-IMPL-005
public struct TreatmentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "treatments"
    
    public let id: String  // UUID as string
    public let type: String
    public let timestamp: Date
    public let insulin: Double?
    public let carbs: Double?
    public let duration: Double?
    public let rate: Double?
    public let notes: String?
    public let source: String
    public let syncIdentifier: String?
    
    public init(from treatment: Treatment) {
        self.id = treatment.id.uuidString
        self.type = treatment.type.rawValue
        self.timestamp = treatment.timestamp
        self.insulin = treatment.insulin
        self.carbs = treatment.carbs
        self.duration = treatment.duration
        self.rate = treatment.rate
        self.notes = treatment.notes
        self.source = treatment.source
        self.syncIdentifier = treatment.syncIdentifier
    }
    
    public func toTreatment() -> Treatment {
        Treatment(
            id: UUID(uuidString: id) ?? UUID(),
            type: PersistenceTreatmentType(rawValue: type) ?? .note,
            timestamp: timestamp,
            insulin: insulin,
            carbs: carbs,
            duration: duration,
            rate: rate,
            notes: notes,
            source: source,
            syncIdentifier: syncIdentifier
        )
    }
}

// MARK: - Treatment Database Migration

/// Database migrator for treatment store schema.
public struct TreatmentMigrator {
    public static func migrate(_ db: Database) throws {
        try db.create(table: TreatmentRecord.databaseTableName, ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("type", .text).notNull().indexed()
            t.column("timestamp", .datetime).notNull().indexed()
            t.column("insulin", .double)
            t.column("carbs", .double)
            t.column("duration", .double)
            t.column("rate", .double)
            t.column("notes", .text)
            t.column("source", .text).notNull()
            t.column("syncIdentifier", .text).indexed()
        }
        
        // Create indexes for common queries
        try db.create(index: "idx_treatment_timestamp", on: TreatmentRecord.databaseTableName,
                      columns: ["timestamp"], ifNotExists: true)
        try db.create(index: "idx_treatment_type", on: TreatmentRecord.databaseTableName,
                      columns: ["type"], ifNotExists: true)
    }
}

// MARK: - GRDB Treatment Store

/// SQLite-backed treatment store using GRDB.
/// Trace: BENCH-IMPL-005
public actor GRDBTreatmentStore: TreatmentStore {
    private let dbWriter: any DatabaseWriter
    private let metrics: any MetricsCollector
    
    /// Initialize with a database writer.
    public init(dbWriter: any DatabaseWriter, metrics: (any MetricsCollector)? = nil) throws {
        self.dbWriter = dbWriter
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbWriter.write { db in
            try TreatmentMigrator.migrate(db)
        }
    }
    
    /// Initialize with a file path for the SQLite database.
    public init(path: String, metrics: (any MetricsCollector)? = nil) throws {
        let dbQueue = try DatabaseQueue(path: path)
        self.dbWriter = dbQueue
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        
        try dbQueue.write { db in
            try TreatmentMigrator.migrate(db)
        }
    }
    
    /// Create a default store in app support directory.
    public static func defaultStore() throws -> GRDBTreatmentStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("treatments.sqlite").path
        return try GRDBTreatmentStore(path: dbPath)
    }
    
    /// Create an in-memory store for testing.
    public static func inMemoryStore() throws -> GRDBTreatmentStore {
        let dbQueue = try DatabaseQueue()
        return try GRDBTreatmentStore(dbWriter: dbQueue)
    }
    
    // MARK: - TreatmentStore Protocol
    
    public func save(_ treatment: Treatment) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.save", duration: duration, tags: ["count": "1"])
        }
        
        let record = TreatmentRecord(from: treatment)
        try await dbWriter.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }
    
    public func save(_ treatments: [Treatment]) async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.save", duration: duration, tags: ["count": "\(treatments.count)"])
        }
        
        let records = treatments.map { TreatmentRecord(from: $0) }
        try await dbWriter.write { db in
            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [Treatment] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.fetch_range", duration: duration, tags: [:])
        }
        
        let records = try await dbWriter.read { db in
            try TreatmentRecord
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toTreatment() }
    }
    
    public func fetch(type: PersistenceTreatmentType, from start: Date, to end: Date) async throws -> [Treatment] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.fetch_type_range", duration: duration, tags: ["type": type.rawValue])
        }
        
        let records = try await dbWriter.read { db in
            try TreatmentRecord
                .filter(Column("type") == type.rawValue)
                .filter(Column("timestamp") >= start && Column("timestamp") <= end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
        return records.map { $0.toTreatment() }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [Treatment] {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.fetch_latest", duration: duration, tags: ["count": "\(count)"])
        }
        
        let records = try await dbWriter.read { db in
            try TreatmentRecord
                .order(Column("timestamp").desc)
                .limit(count)
                .fetchAll(db)
        }
        return records.map { $0.toTreatment() }
    }
    
    public func fetchMostRecent() async throws -> Treatment? {
        let results = try await fetchLatest(1)
        return results.first
    }
    
    public func fetch(syncIdentifier: String) async throws -> Treatment? {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.fetch_sync_id", duration: duration, tags: [:])
        }
        
        let record = try await dbWriter.read { db in
            try TreatmentRecord
                .filter(Column("syncIdentifier") == syncIdentifier)
                .fetchOne(db)
        }
        return record?.toTreatment()
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.delete_old", duration: duration, tags: [:])
        }
        
        return try await dbWriter.write { db in
            try TreatmentRecord
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
    
    public func deleteAll() async throws {
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("grdb_treatment_store.delete_all", duration: duration, tags: [:])
        }
        
        _ = try await dbWriter.write { db in
            try TreatmentRecord.deleteAll(db)
        }
    }
    
    public func count() async throws -> Int {
        try await dbWriter.read { db in
            try TreatmentRecord.fetchCount(db)
        }
    }
    
    // MARK: - GRDB-Specific Features
    
    /// Vacuum the database to reclaim space after deletions.
    public func vacuum() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    /// Get database file size in bytes.
    public func databaseSize() async throws -> Int64 {
        try await dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
            return row?["size"] ?? 0
        }
    }
}
