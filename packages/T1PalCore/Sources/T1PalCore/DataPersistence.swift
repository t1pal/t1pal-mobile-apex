// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DataPersistence.swift - Glucose and treatment persistence layer
// Part of T1PalCore
// Trace: PROD-PERSIST-001

import Foundation

// MARK: - DataLayer Protocol (DATA-COHESIVE-005)

/// Common interface for all persistence stores.
/// Provides base operations that all stores share.
public protocol DataLayer: Sendable {
    /// Associated type for the stored entity
    associatedtype Entity: Identifiable & Sendable
    
    /// Save a single entity.
    func save(_ entity: Entity) async throws
    
    /// Save multiple entities.
    func save(_ entities: [Entity]) async throws
    
    /// Delete entities older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all entities.
    func deleteAll() async throws
    
    /// Count of all entities.
    func count() async throws -> Int
}

// MARK: - Glucose Store Protocol

/// Protocol for glucose reading persistence.
/// Requirements: REQ-DATA-001, REQ-PERSIST-001
public protocol GlucoseStore: Sendable {
    /// Save a glucose reading.
    func save(_ reading: GlucoseReading) async throws
    
    /// Save multiple glucose readings.
    func save(_ readings: [GlucoseReading]) async throws
    
    /// Fetch readings in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [GlucoseReading]
    
    /// Fetch the most recent N readings.
    func fetchLatest(_ count: Int) async throws -> [GlucoseReading]
    
    /// Fetch the most recent reading.
    func fetchMostRecent() async throws -> GlucoseReading?
    
    /// Fetch by sync identifier for deduplication. (DATA-COHESIVE-001)
    func fetch(syncIdentifier: String) async throws -> GlucoseReading?
    
    /// Delete readings older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all readings.
    func deleteAll() async throws
    
    /// Count of all readings.
    func count() async throws -> Int
}

// MARK: - Treatment Type

/// Treatment event type for persistence.
public enum PersistenceTreatmentType: String, Codable, Sendable, CaseIterable {
    case bolus = "Bolus"
    case carbs = "Meal Bolus"
    case tempBasal = "Temp Basal"
    case suspend = "Suspend Pump"
    case resume = "Resume Pump"
    case siteChange = "Site Change"
    case sensorStart = "Sensor Start"
    case profileSwitch = "Profile Switch"
    case tempTarget = "Temporary Target"
    case bgCheck = "BG Check"
    case note = "Note"
    case exercise = "Exercise"
    case announcement = "Announcement"
}

// MARK: - Treatment

/// Local treatment record for persistence.
public struct Treatment: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let type: PersistenceTreatmentType
    public let timestamp: Date
    public let insulin: Double?
    public let carbs: Double?
    public let duration: TimeInterval?
    public let rate: Double?
    public let notes: String?
    public let source: String
    public let syncIdentifier: String?
    
    public init(
        id: UUID = UUID(),
        type: PersistenceTreatmentType,
        timestamp: Date = Date(),
        insulin: Double? = nil,
        carbs: Double? = nil,
        duration: TimeInterval? = nil,
        rate: Double? = nil,
        notes: String? = nil,
        source: String = "T1Pal",
        syncIdentifier: String? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.insulin = insulin
        self.carbs = carbs
        self.duration = duration
        self.rate = rate
        self.notes = notes
        self.source = source
        self.syncIdentifier = syncIdentifier
    }
    
    /// Create a bolus treatment.
    public static func bolus(
        units: Double,
        timestamp: Date = Date(),
        source: String = "T1Pal"
    ) -> Treatment {
        Treatment(
            type: .bolus,
            timestamp: timestamp,
            insulin: units,
            source: source
        )
    }
    
    /// Create a carb entry.
    public static func carbs(
        grams: Double,
        timestamp: Date = Date(),
        source: String = "T1Pal"
    ) -> Treatment {
        Treatment(
            type: .carbs,
            timestamp: timestamp,
            carbs: grams,
            source: source
        )
    }
    
    /// Create a temp basal treatment.
    public static func tempBasal(
        rate: Double,
        duration: TimeInterval,
        timestamp: Date = Date(),
        source: String = "T1Pal"
    ) -> Treatment {
        Treatment(
            type: .tempBasal,
            timestamp: timestamp,
            duration: duration,
            rate: rate,
            source: source
        )
    }
}

// MARK: - Treatment Store Protocol

/// Protocol for treatment persistence.
/// Requirements: REQ-DATA-002, REQ-PERSIST-002
public protocol TreatmentStore: Sendable {
    /// Save a treatment.
    func save(_ treatment: Treatment) async throws
    
    /// Save multiple treatments.
    func save(_ treatments: [Treatment]) async throws
    
    /// Fetch treatments in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [Treatment]
    
    /// Fetch treatments by type in a date range.
    func fetch(type: PersistenceTreatmentType, from start: Date, to end: Date) async throws -> [Treatment]
    
    /// Fetch the most recent N treatments.
    func fetchLatest(_ count: Int) async throws -> [Treatment]
    
    /// Fetch the most recent treatment. (DATA-COHESIVE-001)
    func fetchMostRecent() async throws -> Treatment?
    
    /// Fetch by sync identifier for deduplication.
    func fetch(syncIdentifier: String) async throws -> Treatment?
    
    /// Delete treatments older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all treatments.
    func deleteAll() async throws
    
    /// Count of all treatments.
    func count() async throws -> Int
}

// MARK: - DeviceStatus Type

/// Local device status record for persistence.
/// Simplified from NightscoutDeviceStatus for local storage.
/// Trace: BENCH-IMPL-001
public struct DeviceStatus: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let device: String
    
    // Loop/algorithm status
    public let iob: Double?
    public let cob: Double?
    public let eventualBG: Double?
    public let recommendedBolus: Double?
    
    // Pump status
    public let pumpBattery: Double?
    public let reservoirUnits: Double?
    public let suspended: Bool
    
    // Uploader status
    public let uploaderBattery: Double?
    
    // Metadata
    public let source: String
    public let syncIdentifier: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        device: String,
        iob: Double? = nil,
        cob: Double? = nil,
        eventualBG: Double? = nil,
        recommendedBolus: Double? = nil,
        pumpBattery: Double? = nil,
        reservoirUnits: Double? = nil,
        suspended: Bool = false,
        uploaderBattery: Double? = nil,
        source: String = "unknown",
        syncIdentifier: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.iob = iob
        self.cob = cob
        self.eventualBG = eventualBG
        self.recommendedBolus = recommendedBolus
        self.pumpBattery = pumpBattery
        self.reservoirUnits = reservoirUnits
        self.suspended = suspended
        self.uploaderBattery = uploaderBattery
        self.source = source
        self.syncIdentifier = syncIdentifier
    }
}

// MARK: - DeviceStatus Store Protocol

/// Protocol for device status persistence.
/// DeviceStatus is the largest dataset (~288/day at 5-min intervals).
/// Trace: BENCH-IMPL-001
public protocol DeviceStatusStore: Sendable {
    /// Save a device status.
    func save(_ status: DeviceStatus) async throws
    
    /// Save multiple device statuses.
    func save(_ statuses: [DeviceStatus]) async throws
    
    /// Fetch statuses in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [DeviceStatus]
    
    /// Fetch the most recent N statuses.
    func fetchLatest(_ count: Int) async throws -> [DeviceStatus]
    
    /// Fetch the most recent status.
    func fetchMostRecent() async throws -> DeviceStatus?
    
    /// Fetch by sync identifier for deduplication.
    func fetch(syncIdentifier: String) async throws -> DeviceStatus?
    
    /// Delete statuses older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all statuses.
    func deleteAll() async throws
    
    /// Count of all statuses.
    func count() async throws -> Int
}

// MARK: - Agent Proposal Type (for persistence)

/// Proposal status for persistence.
/// Trace: BENCH-IMPL-002
public enum PersistenceProposalStatus: String, Codable, Sendable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case expired = "expired"
    case executed = "executed"
}

/// Proposal type for persistence.
/// Trace: BENCH-IMPL-002
public enum PersistenceProposalType: String, Codable, Sendable {
    case override = "override"
    case tempTarget = "tempTarget"
    case suspendDelivery = "suspendDelivery"
    case resumeDelivery = "resumeDelivery"
    case profile = "profile"
    case carbs = "carbs"
    case annotation = "annotation"
}

/// Agent proposal for local persistence.
/// Simplified from NightscoutKit AgentProposal for local storage.
/// Trace: BENCH-IMPL-002
public struct PersistenceAgentProposal: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let agentId: String
    public let agentName: String
    public let proposalType: PersistenceProposalType
    public let description: String
    public let rationale: String
    public let expiresAt: Date
    public var status: PersistenceProposalStatus
    public var reviewedBy: String?
    public var reviewedAt: Date?
    public var reviewNote: String?
    
    // Serialized JSON for override/target details
    public let detailsJSON: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentId: String,
        agentName: String,
        proposalType: PersistenceProposalType,
        description: String,
        rationale: String,
        expiresAt: Date,
        status: PersistenceProposalStatus = .pending,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil,
        reviewNote: String? = nil,
        detailsJSON: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentId = agentId
        self.agentName = agentName
        self.proposalType = proposalType
        self.description = description
        self.rationale = rationale
        self.expiresAt = expiresAt
        self.status = status
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.reviewNote = reviewNote
        self.detailsJSON = detailsJSON
    }
    
    /// Check if proposal has expired.
    public var isExpired: Bool {
        Date() > expiresAt
    }
    
    /// Check if proposal can be acted upon.
    public var isActionable: Bool {
        status == .pending && !isExpired
    }
}

// MARK: - Proposal Store Protocol

/// Protocol for agent proposal persistence.
/// Used for propose-authorize-enact workflow history.
/// Trace: BENCH-IMPL-002
public protocol ProposalStore: Sendable {
    /// Save a proposal.
    func save(_ proposal: PersistenceAgentProposal) async throws
    
    /// Save multiple proposals.
    func save(_ proposals: [PersistenceAgentProposal]) async throws
    
    /// Fetch proposals in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [PersistenceAgentProposal]
    
    /// Fetch by status.
    func fetch(status: PersistenceProposalStatus) async throws -> [PersistenceAgentProposal]
    
    /// Fetch pending proposals.
    func fetchPending() async throws -> [PersistenceAgentProposal]
    
    /// Fetch the most recent N proposals.
    func fetchLatest(_ count: Int) async throws -> [PersistenceAgentProposal]
    
    /// Fetch by proposal ID.
    func fetch(id: UUID) async throws -> PersistenceAgentProposal?
    
    /// Update proposal status (approve/reject/execute).
    func update(_ proposal: PersistenceAgentProposal) async throws
    
    /// Delete proposals older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all proposals.
    func deleteAll() async throws
    
    /// Count of all proposals.
    func count() async throws -> Int
    
    /// Count of pending proposals.
    func countPending() async throws -> Int
}

// MARK: - Persistence Error

/// Errors that can occur during data persistence.
public enum PersistenceError: Error, LocalizedError, Sendable {
    case saveFailed(String)
    case fetchFailed(String)
    case deleteFailed(String)
    case fileNotFound
    case decodingFailed(String)
    case encodingFailed(String)
    case storageUnavailable
    case diskFull  // DATA-FAULT-001: Disk full simulation
    case quotaExceeded  // DATA-FAULT-005: Storage quota exceeded
    case dataCorrupted(String)  // DATA-FAULT-002: Corrupted data detected
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed(let reason): return "Save failed: \(reason)"
        case .fetchFailed(let reason): return "Fetch failed: \(reason)"
        case .deleteFailed(let reason): return "Delete failed: \(reason)"
        case .fileNotFound: return "Data file not found"
        case .decodingFailed(let reason): return "Decoding failed: \(reason)"
        case .encodingFailed(let reason): return "Encoding failed: \(reason)"
        case .storageUnavailable: return "Storage unavailable"
        case .diskFull: return "Disk is full"
        case .quotaExceeded: return "Storage quota exceeded"
        case .dataCorrupted(let reason): return "Data corrupted: \(reason)"
        }
    }
}

// MARK: - PersistenceError + T1PalErrorProtocol

extension PersistenceError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .storage }
    
    public var code: String {
        switch self {
        case .saveFailed: return "PERSIST-SAVE-001"
        case .fetchFailed: return "PERSIST-FETCH-001"
        case .deleteFailed: return "PERSIST-DELETE-001"
        case .fileNotFound: return "PERSIST-FILE-001"
        case .decodingFailed: return "PERSIST-DECODE-001"
        case .encodingFailed: return "PERSIST-ENCODE-001"
        case .storageUnavailable: return "PERSIST-STORAGE-001"
        case .diskFull: return "PERSIST-DISK-001"
        case .quotaExceeded: return "PERSIST-QUOTA-001"
        case .dataCorrupted: return "PERSIST-CORRUPT-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .saveFailed: return .error
        case .fetchFailed: return .error
        case .deleteFailed: return .warning
        case .fileNotFound: return .warning
        case .decodingFailed: return .error
        case .encodingFailed: return .error
        case .storageUnavailable: return .critical
        case .diskFull: return .critical
        case .quotaExceeded: return .critical
        case .dataCorrupted: return .critical
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .saveFailed: return .retry
        case .fetchFailed: return .retry
        case .deleteFailed: return .retry
        case .fileNotFound: return .none  // Expected in some cases
        case .decodingFailed: return .contactSupport
        case .encodingFailed: return .contactSupport
        case .storageUnavailable: return .checkDevice
        case .diskFull: return .checkDevice  // User needs to free space
        case .quotaExceeded: return .checkDevice
        case .dataCorrupted: return .contactSupport
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown persistence error"
    }
}

// MARK: - Fault Injection (DATA-FAULT-001)

/// Fault injection types for testing persistence layer resilience.
public enum FaultType: Sendable {
    case none
    case diskFull
    case quotaExceeded
    case dataCorrupted
    case writeInterrupted
    case networkTimeout  // For remote stores
}

/// Configuration for persistence fault injection testing.
/// Trace: DATA-FAULT-001, DATA-FAULT-002, DATA-FAULT-004, DATA-FAULT-005
public final class FaultInjector: @unchecked Sendable {
    public static let shared = FaultInjector()
    
    private var _currentFault: FaultType = .none
    private let lock = NSLock()
    
    public var currentFault: FaultType {
        get { lock.withLock { _currentFault } }
        set { lock.withLock { _currentFault = newValue } }
    }
    
    /// Probability of fault occurring (0.0-1.0). Default is 1.0 (always).
    public var faultProbability: Double = 1.0
    
    public init() {}
    
    /// Check if a fault should be injected on save.
    public func shouldFaultOnSave() -> Bool {
        guard currentFault != .none else { return false }
        return Double.random(in: 0...1) <= faultProbability
    }
    
    /// Inject the configured fault by throwing appropriate error.
    public func injectFault() throws {
        switch currentFault {
        case .none:
            return
        case .diskFull:
            throw PersistenceError.diskFull
        case .quotaExceeded:
            throw PersistenceError.quotaExceeded
        case .dataCorrupted:
            throw PersistenceError.dataCorrupted("Injected fault")
        case .writeInterrupted:
            throw PersistenceError.saveFailed("Write interrupted")
        case .networkTimeout:
            throw PersistenceError.saveFailed("Network timeout")
        }
    }
    
    /// Reset fault injection to no faults.
    public func reset() {
        currentFault = .none
        faultProbability = 1.0
    }
}

// MARK: - In-Memory Glucose Store

/// In-memory implementation for testing.
public actor InMemoryGlucoseStore: GlucoseStore {
    private var readings: [UUID: GlucoseReading] = [:]
    
    public init() {}
    
    public func save(_ reading: GlucoseReading) async throws {
        readings[reading.id] = reading
    }
    
    public func save(_ readings: [GlucoseReading]) async throws {
        for reading in readings {
            self.readings[reading.id] = reading
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [GlucoseReading] {
        readings.values
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [GlucoseReading] {
        Array(readings.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(count))
    }
    
    public func fetchMostRecent() async throws -> GlucoseReading? {
        readings.values.max { $0.timestamp < $1.timestamp }
    }
    
    /// DATA-COHESIVE-001: Fetch by sync identifier for deduplication
    public func fetch(syncIdentifier: String) async throws -> GlucoseReading? {
        readings.values.first { $0.syncIdentifier == syncIdentifier }
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let toDelete = readings.values.filter { $0.timestamp < date }
        for reading in toDelete {
            readings.removeValue(forKey: reading.id)
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        readings.removeAll()
    }
    
    public func count() async throws -> Int {
        readings.count
    }
}

// MARK: - In-Memory Treatment Store

/// In-memory implementation for testing.
public actor InMemoryTreatmentStore: TreatmentStore {
    private var treatments: [UUID: Treatment] = [:]
    
    public init() {}
    
    public func save(_ treatment: Treatment) async throws {
        treatments[treatment.id] = treatment
    }
    
    public func save(_ treatments: [Treatment]) async throws {
        for treatment in treatments {
            self.treatments[treatment.id] = treatment
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [Treatment] {
        treatments.values
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func fetch(type: PersistenceTreatmentType, from start: Date, to end: Date) async throws -> [Treatment] {
        treatments.values
            .filter { $0.type == type && $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [Treatment] {
        Array(treatments.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(count))
    }
    
    /// DATA-COHESIVE-001: Fetch the most recent treatment
    public func fetchMostRecent() async throws -> Treatment? {
        treatments.values.max { $0.timestamp < $1.timestamp }
    }
    
    public func fetch(syncIdentifier: String) async throws -> Treatment? {
        treatments.values.first { $0.syncIdentifier == syncIdentifier }
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let toDelete = treatments.values.filter { $0.timestamp < date }
        for treatment in toDelete {
            treatments.removeValue(forKey: treatment.id)
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        treatments.removeAll()
    }
    
    public func count() async throws -> Int {
        treatments.count
    }
}

// FileGlucoseStore moved to FileGlucoseStore.swift (DATA-REFACTOR-001)

// FileTreatmentStore moved to FileTreatmentStore.swift (DATA-REFACTOR-002)

// MARK: - Data Store Manager

/// Unified access point for all data stores.
/// DATA-SCALE-003: Includes record count metrics for monitoring store sizes
public final class DataStoreManager: @unchecked Sendable {
    
    /// Shared instance with default stores.
    public static let shared = DataStoreManager()
    
    /// Glucose reading store.
    public let glucoseStore: any GlucoseStore
    
    /// Treatment store.
    public let treatmentStore: any TreatmentStore
    
    /// Metrics collector for record count tracking (DATA-SCALE-003)
    private let metrics: any MetricsCollector
    
    /// Initialize with default file-based stores.
    public init(metrics: (any MetricsCollector)? = nil) {
        self.glucoseStore = FileGlucoseStore.defaultStore()
        self.treatmentStore = FileTreatmentStore.defaultStore()
        self.metrics = metrics ?? MetricsCollectorFactory.create()
    }
    
    /// Initialize with custom stores (for testing).
    public init(glucoseStore: any GlucoseStore, treatmentStore: any TreatmentStore, metrics: (any MetricsCollector)? = nil) {
        self.glucoseStore = glucoseStore
        self.treatmentStore = treatmentStore
        self.metrics = metrics ?? MetricsCollectorFactory.create()
    }
    
    /// Create a manager with in-memory stores for testing.
    public static func inMemory() -> DataStoreManager {
        DataStoreManager(
            glucoseStore: InMemoryGlucoseStore(),
            treatmentStore: InMemoryTreatmentStore()
        )
    }
    
    // MARK: - Store Statistics (DATA-SCALE-003, DATA-SCALE-004)
    
    /// Estimated memory size per GlucoseReading in bytes.
    /// UUID (16) + Double (8) + Date (8) + GlucoseTrend enum (1) + String (~16 avg) + overhead (~15)
    private static let glucoseReadingByteSize: Int = 64
    
    /// Estimated memory size per Treatment in bytes.
    /// UUID (16) + enum (1) + Date (8) + 4 optionals (~40) + 2 strings (~32) + overhead (~31)
    private static let treatmentByteSize: Int = 128
    
    /// Statistics about data store record counts and memory usage.
    public struct StoreStatistics: Sendable {
        /// Number of glucose readings in store.
        public let glucoseCount: Int
        /// Number of treatments in store.
        public let treatmentCount: Int
        /// Estimated memory for glucose readings in bytes.
        public let glucoseMemoryBytes: Int
        /// Estimated memory for treatments in bytes.
        public let treatmentMemoryBytes: Int
        /// Actual database file size in bytes (nil for in-memory stores).
        /// Trace: NS-CACHE-004
        public let databaseSizeBytes: Int64?
        
        /// Total records across all stores.
        public var totalCount: Int { glucoseCount + treatmentCount }
        /// Total estimated memory in bytes.
        public var totalMemoryBytes: Int { glucoseMemoryBytes + treatmentMemoryBytes }
        /// Total estimated memory in kilobytes.
        public var totalMemoryKB: Double { Double(totalMemoryBytes) / 1024.0 }
        /// Total estimated memory in megabytes.
        public var totalMemoryMB: Double { Double(totalMemoryBytes) / (1024.0 * 1024.0) }
        /// Database file size in kilobytes (nil for in-memory stores).
        public var databaseSizeKB: Double? { 
            databaseSizeBytes.map { Double($0) / 1024.0 }
        }
        /// Database file size in megabytes (nil for in-memory stores).
        public var databaseSizeMB: Double? {
            databaseSizeBytes.map { Double($0) / (1024.0 * 1024.0) }
        }
    }
    
    /// Get current record counts and memory estimates from all stores.
    /// - Returns: Statistics with record counts and memory estimates per store
    public func getStatistics() async throws -> StoreStatistics {
        let startTime = Date().timeIntervalSinceReferenceDate
        
        let glucoseCount = try await glucoseStore.count()
        let treatmentCount = try await treatmentStore.count()
        
        let glucoseMemory = glucoseCount * Self.glucoseReadingByteSize
        let treatmentMemory = treatmentCount * Self.treatmentByteSize
        
        // Try to get database size if store supports it (NS-CACHE-004)
        // GRDBGlucoseStore only available on Darwin
        var dbSize: Int64? = nil
        #if canImport(Darwin)
        if let grdbStore = glucoseStore as? GRDBGlucoseStore {
            dbSize = try? await grdbStore.databaseSize()
        }
        #endif
        
        let stats = StoreStatistics(
            glucoseCount: glucoseCount,
            treatmentCount: treatmentCount,
            glucoseMemoryBytes: glucoseMemory,
            treatmentMemoryBytes: treatmentMemory,
            databaseSizeBytes: dbSize
        )
        
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("store_manager.get_statistics", duration: duration, tags: [
            "glucose_count": "\(glucoseCount)",
            "treatment_count": "\(treatmentCount)",
            "total_count": "\(stats.totalCount)",
            "memory_kb": String(format: "%.1f", stats.totalMemoryKB)
        ])
        
        return stats
    }
    
    /// Record current store counts as gauge metrics.
    /// Call periodically to track store growth over time.
    public func recordCountMetrics() async throws {
        let stats = try await getStatistics()
        metrics.recordGauge("store_manager.glucose_records", value: Double(stats.glucoseCount), tags: [:])
        metrics.recordGauge("store_manager.treatment_records", value: Double(stats.treatmentCount), tags: [:])
        metrics.recordGauge("store_manager.total_records", value: Double(stats.totalCount), tags: [:])
    }
    
    /// Record current memory usage as gauge metrics (DATA-SCALE-004).
    /// Call periodically to track memory consumption over time.
    public func recordMemoryMetrics() async throws {
        let stats = try await getStatistics()
        metrics.recordGauge("store_manager.glucose_memory_bytes", value: Double(stats.glucoseMemoryBytes), tags: [:])
        metrics.recordGauge("store_manager.treatment_memory_bytes", value: Double(stats.treatmentMemoryBytes), tags: [:])
        metrics.recordGauge("store_manager.total_memory_bytes", value: Double(stats.totalMemoryBytes), tags: [:])
        metrics.recordGauge("store_manager.total_memory_mb", value: stats.totalMemoryMB, tags: [:])
    }
}

// MARK: - Retention Policy

/// Data retention configuration.
public struct RetentionPolicy: Codable, Sendable {
    /// Maximum age for glucose readings in days.
    public let glucoseRetentionDays: Int
    
    /// Maximum age for treatments in days.
    public let treatmentRetentionDays: Int
    
    /// Default retention: 90 days for readings, 365 days for treatments.
    public static let standard = RetentionPolicy(
        glucoseRetentionDays: 90,
        treatmentRetentionDays: 365
    )
    
    /// Extended retention: 180 days for readings, 730 days for treatments.
    public static let extended = RetentionPolicy(
        glucoseRetentionDays: 180,
        treatmentRetentionDays: 730
    )
    
    /// Minimal retention: 30 days for readings, 90 days for treatments.
    public static let minimal = RetentionPolicy(
        glucoseRetentionDays: 30,
        treatmentRetentionDays: 90
    )
    
    public init(glucoseRetentionDays: Int, treatmentRetentionDays: Int) {
        self.glucoseRetentionDays = glucoseRetentionDays
        self.treatmentRetentionDays = treatmentRetentionDays
    }
    
    /// Calculate cutoff date for glucose readings.
    public var glucoseCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -glucoseRetentionDays, to: Date()) ?? Date()
    }
    
    /// Calculate cutoff date for treatments.
    public var treatmentCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -treatmentRetentionDays, to: Date()) ?? Date()
    }
}

// MARK: - Retention Manager

/// Manages data retention and cleanup.
public actor RetentionManager {
    private let glucoseStore: any GlucoseStore
    private let treatmentStore: any TreatmentStore
    private var policy: RetentionPolicy
    
    public init(
        glucoseStore: any GlucoseStore,
        treatmentStore: any TreatmentStore,
        policy: RetentionPolicy = .standard
    ) {
        self.glucoseStore = glucoseStore
        self.treatmentStore = treatmentStore
        self.policy = policy
    }
    
    /// Update retention policy.
    public func setPolicy(_ policy: RetentionPolicy) {
        self.policy = policy
    }
    
    /// Run cleanup based on retention policy.
    /// Returns tuple of (glucose deleted, treatments deleted).
    public func runCleanup() async throws -> (Int, Int) {
        let glucoseDeleted = try await glucoseStore.deleteOlderThan(policy.glucoseCutoffDate)
        let treatmentDeleted = try await treatmentStore.deleteOlderThan(policy.treatmentCutoffDate)
        return (glucoseDeleted, treatmentDeleted)
    }
}
