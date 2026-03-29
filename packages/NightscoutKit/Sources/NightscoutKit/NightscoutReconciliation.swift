// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutReconciliation.swift
// T1Pal Mobile
//
// Nightscout reconciliation protocol for AID decision audit logging
// Requirements: REQ-AID-004

import Foundation

// MARK: - Decision Audit Types

/// Type of AID decision being logged
/// Requirements: REQ-AID-004
public enum DecisionType: String, Codable, Sendable {
    case tempBasal = "temp_basal"
    case smb = "smb"                    // Super micro bolus
    case suspend = "suspend"
    case resume = "resume"
    case override = "override"
    case correction = "correction"
    case carbs = "carbs"
    case profile = "profile_switch"
}

/// Reconciliation status for a decision
/// Requirements: REQ-AID-004
public enum ReconciliationStatus: String, Codable, Sendable {
    case pending = "pending"            // Decision created, not yet uploaded
    case uploaded = "uploaded"          // Uploaded to Nightscout
    case confirmed = "confirmed"        // Confirmed from Nightscout (echoed back)
    case rejected = "rejected"          // Rejected by safety check or NS error
    case expired = "expired"            // Decision timed out without confirmation
    case executed = "executed"          // Successfully executed on pump
    case failed = "failed"              // Execution failed
}

/// A single decision audit entry for Nightscout reconciliation
/// Requirements: REQ-AID-004
public struct DecisionAuditEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let decisionType: DecisionType
    public let createdAt: Date
    public var status: ReconciliationStatus
    public var uploadedAt: Date?
    public var confirmedAt: Date?
    public var executedAt: Date?
    
    // Decision details
    public let algorithmName: String
    public let reason: String
    public let glucose: Double?
    public let iob: Double?
    public let cob: Double?
    public let eventualBG: Double?
    
    // Action parameters (depending on decision type)
    public let rate: Double?            // For temp basal (U/hr)
    public let duration: Int?           // For temp basal (minutes)
    public let units: Double?           // For bolus/SMB (U)
    public let carbGrams: Double?       // For carbs
    
    // Nightscout sync
    public var nightscoutId: String?    // _id from Nightscout response
    public let syncIdentifier: String   // Deduplication key
    public let device: String
    
    public init(
        id: UUID = UUID(),
        decisionType: DecisionType,
        createdAt: Date = Date(),
        status: ReconciliationStatus = .pending,
        algorithmName: String,
        reason: String,
        glucose: Double? = nil,
        iob: Double? = nil,
        cob: Double? = nil,
        eventualBG: Double? = nil,
        rate: Double? = nil,
        duration: Int? = nil,
        units: Double? = nil,
        carbGrams: Double? = nil,
        device: String = "T1Pal"
    ) {
        self.id = id
        self.decisionType = decisionType
        self.createdAt = createdAt
        self.status = status
        self.algorithmName = algorithmName
        self.reason = reason
        self.glucose = glucose
        self.iob = iob
        self.cob = cob
        self.eventualBG = eventualBG
        self.rate = rate
        self.duration = duration
        self.units = units
        self.carbGrams = carbGrams
        self.device = device
        
        // Generate sync identifier with UUID for guaranteed uniqueness
        let formatter = ISO8601DateFormatter()
        self.syncIdentifier = "\(device):\(decisionType.rawValue):\(formatter.string(from: createdAt)):\(id.uuidString.prefix(8))"
    }
    
    /// Convert to Nightscout devicestatus format
    public func toDeviceStatus() -> [String: Any] {
        var status: [String: Any] = [
            "device": device,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "identifier": syncIdentifier
        ]
        
        // Add algorithm decision info
        var openaps: [String: Any] = [
            "enacted": [
                "reason": reason,
                "timestamp": ISO8601DateFormatter().string(from: createdAt)
            ]
        ]
        
        if let rate = rate {
            var enacted = openaps["enacted"] as? [String: Any] ?? [:]
            enacted["rate"] = rate
            enacted["duration"] = duration ?? 30
            openaps["enacted"] = enacted
        }
        
        if let units = units {
            var enacted = openaps["enacted"] as? [String: Any] ?? [:]
            enacted["units"] = units
            openaps["enacted"] = enacted
        }
        
        // Add context
        var context: [String: Any] = [:]
        if let glucose = glucose { context["glucose"] = glucose }
        if let iob = iob { context["iob"] = iob }
        if let cob = cob { context["cob"] = cob }
        if let eventualBG = eventualBG { context["eventualBG"] = eventualBG }
        
        if !context.isEmpty {
            openaps["context"] = context
        }
        
        status["openaps"] = openaps
        
        return status
    }
}

// MARK: - Reconciliation Manager

/// Manages the decision reconciliation lifecycle with Nightscout
/// Requirements: REQ-AID-004
public actor ReconciliationManager {
    
    /// Pending decisions awaiting confirmation
    private var pendingDecisions: [UUID: DecisionAuditEntry] = [:]
    
    /// Confirmed decisions (limited history)
    private var confirmedDecisions: [DecisionAuditEntry] = []
    
    /// Maximum pending decision age before expiry
    private let expiryInterval: TimeInterval
    
    /// Maximum confirmed decisions to retain
    private let maxConfirmedHistory: Int
    
    /// Upload callback type
    public typealias UploadCallback = @Sendable (DecisionAuditEntry) async throws -> String?
    
    /// Upload callback to send decision to Nightscout
    private let uploadCallback: UploadCallback?
    
    /// Initialize reconciliation manager
    /// - Parameters:
    ///   - expiryInterval: Seconds before pending decision expires (default: 60)
    ///   - maxConfirmedHistory: Maximum confirmed decisions to retain (default: 100)
    ///   - uploadCallback: Async callback to upload decision to Nightscout
    public init(
        expiryInterval: TimeInterval = 60,
        maxConfirmedHistory: Int = 100,
        uploadCallback: UploadCallback? = nil
    ) {
        self.expiryInterval = expiryInterval
        self.maxConfirmedHistory = maxConfirmedHistory
        self.uploadCallback = uploadCallback
    }
    
    /// Submit a new decision for reconciliation
    /// - Parameter decision: The decision to submit
    /// - Returns: Updated decision with new status
    public func submit(_ decision: DecisionAuditEntry) async -> DecisionAuditEntry {
        var entry = decision
        entry.status = .pending
        pendingDecisions[entry.id] = entry
        
        // Try to upload if callback available
        if let uploadCallback = uploadCallback {
            do {
                let nsId = try await uploadCallback(entry)
                entry.nightscoutId = nsId
                entry.uploadedAt = Date()
                entry.status = .uploaded
                pendingDecisions[entry.id] = entry
            } catch {
                // Upload failed, keep as pending for retry
            }
        }
        
        return entry
    }
    
    /// Confirm a decision was received by Nightscout
    /// - Parameters:
    ///   - id: Decision UUID
    ///   - nightscoutId: The _id returned from Nightscout
    /// - Returns: Updated decision or nil if not found
    @discardableResult
    public func confirm(id: UUID, nightscoutId: String? = nil) -> DecisionAuditEntry? {
        guard var entry = pendingDecisions.removeValue(forKey: id) else {
            return nil
        }
        
        entry.status = .confirmed
        entry.confirmedAt = Date()
        if let nsId = nightscoutId {
            entry.nightscoutId = nsId
        }
        
        confirmedDecisions.append(entry)
        trimConfirmedHistory()
        
        return entry
    }
    
    /// Confirm a decision by sync identifier
    /// - Parameter syncIdentifier: The sync identifier to match
    /// - Returns: Updated decision or nil if not found
    @discardableResult
    public func confirmBySyncId(_ syncIdentifier: String) -> DecisionAuditEntry? {
        guard let (id, _) = pendingDecisions.first(where: { $0.value.syncIdentifier == syncIdentifier }) else {
            return nil
        }
        return confirm(id: id)
    }
    
    /// Mark a decision as executed
    /// - Parameter id: Decision UUID
    /// - Returns: Updated decision or nil if not found
    @discardableResult
    public func markExecuted(id: UUID) -> DecisionAuditEntry? {
        // Check pending first
        if var entry = pendingDecisions.removeValue(forKey: id) {
            entry.status = .executed
            entry.executedAt = Date()
            confirmedDecisions.append(entry)
            trimConfirmedHistory()
            return entry
        }
        
        // Check confirmed
        if let index = confirmedDecisions.firstIndex(where: { $0.id == id }) {
            confirmedDecisions[index].status = .executed
            confirmedDecisions[index].executedAt = Date()
            return confirmedDecisions[index]
        }
        
        return nil
    }
    
    /// Reject a decision
    /// - Parameters:
    ///   - id: Decision UUID
    ///   - reason: Rejection reason
    /// - Returns: Updated decision or nil if not found
    @discardableResult
    public func reject(id: UUID, reason: String? = nil) -> DecisionAuditEntry? {
        guard var entry = pendingDecisions.removeValue(forKey: id) else {
            return nil
        }
        
        entry.status = .rejected
        confirmedDecisions.append(entry)
        trimConfirmedHistory()
        
        return entry
    }
    
    /// Expire old pending decisions
    /// - Returns: Number of expired decisions
    @discardableResult
    public func expireOldDecisions() -> Int {
        let cutoff = Date().addingTimeInterval(-expiryInterval)
        var expiredCount = 0
        
        for (id, var entry) in pendingDecisions {
            if entry.createdAt < cutoff {
                entry.status = .expired
                pendingDecisions.removeValue(forKey: id)
                confirmedDecisions.append(entry)
                expiredCount += 1
            }
        }
        
        trimConfirmedHistory()
        return expiredCount
    }
    
    /// Get pending decisions
    public func getPending() -> [DecisionAuditEntry] {
        Array(pendingDecisions.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get confirmed/executed decisions
    public func getHistory(limit: Int = 50) -> [DecisionAuditEntry] {
        Array(confirmedDecisions.suffix(limit))
    }
    
    /// Get a specific decision by ID
    public func getDecision(id: UUID) -> DecisionAuditEntry? {
        pendingDecisions[id] ?? confirmedDecisions.first { $0.id == id }
    }
    
    /// Clear all decisions (for testing)
    public func clear() {
        pendingDecisions.removeAll()
        confirmedDecisions.removeAll()
    }
    
    /// Trim confirmed history to max size
    private func trimConfirmedHistory() {
        if confirmedDecisions.count > maxConfirmedHistory {
            confirmedDecisions = Array(confirmedDecisions.suffix(maxConfirmedHistory))
        }
    }
}

// MARK: - Decision Builders

/// Factory for creating common decision types
/// Requirements: REQ-AID-004
public enum DecisionBuilder {
    
    /// Create a temp basal decision
    public static func tempBasal(
        rate: Double,
        duration: Int,
        reason: String,
        algorithm: String = "oref1",
        glucose: Double? = nil,
        iob: Double? = nil,
        cob: Double? = nil,
        eventualBG: Double? = nil,
        device: String = "T1Pal"
    ) -> DecisionAuditEntry {
        DecisionAuditEntry(
            decisionType: .tempBasal,
            algorithmName: algorithm,
            reason: reason,
            glucose: glucose,
            iob: iob,
            cob: cob,
            eventualBG: eventualBG,
            rate: rate,
            duration: duration,
            device: device
        )
    }
    
    /// Create an SMB (super micro bolus) decision
    public static func smb(
        units: Double,
        reason: String,
        algorithm: String = "oref1",
        glucose: Double? = nil,
        iob: Double? = nil,
        cob: Double? = nil,
        eventualBG: Double? = nil,
        device: String = "T1Pal"
    ) -> DecisionAuditEntry {
        DecisionAuditEntry(
            decisionType: .smb,
            algorithmName: algorithm,
            reason: reason,
            glucose: glucose,
            iob: iob,
            cob: cob,
            eventualBG: eventualBG,
            units: units,
            device: device
        )
    }
    
    /// Create a suspend decision
    public static func suspend(
        reason: String,
        algorithm: String = "oref1",
        glucose: Double? = nil,
        device: String = "T1Pal"
    ) -> DecisionAuditEntry {
        DecisionAuditEntry(
            decisionType: .suspend,
            algorithmName: algorithm,
            reason: reason,
            glucose: glucose,
            rate: 0,
            duration: 30,
            device: device
        )
    }
    
    /// Create a resume decision
    public static func resume(
        reason: String = "BG in range",
        algorithm: String = "oref1",
        glucose: Double? = nil,
        device: String = "T1Pal"
    ) -> DecisionAuditEntry {
        DecisionAuditEntry(
            decisionType: .resume,
            algorithmName: algorithm,
            reason: reason,
            glucose: glucose,
            device: device
        )
    }
}

// MARK: - Decision Audit Store (DATA-COHESIVE-003)

/// Protocol for persisting loop decision audit entries.
/// Follows same API patterns as GlucoseStore and TreatmentStore.
public protocol DecisionAuditStore: Sendable {
    /// Save a decision audit entry.
    func save(_ entry: DecisionAuditEntry) async throws
    
    /// Save multiple entries.
    func save(_ entries: [DecisionAuditEntry]) async throws
    
    /// Fetch entries in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [DecisionAuditEntry]
    
    /// Fetch entries by decision type.
    func fetch(type: DecisionType) async throws -> [DecisionAuditEntry]
    
    /// Fetch entries by status.
    func fetch(status: ReconciliationStatus) async throws -> [DecisionAuditEntry]
    
    /// Fetch the most recent N entries.
    func fetchLatest(_ count: Int) async throws -> [DecisionAuditEntry]
    
    /// Fetch the most recent entry.
    func fetchMostRecent() async throws -> DecisionAuditEntry?
    
    /// Fetch by sync identifier for deduplication.
    func fetch(syncIdentifier: String) async throws -> DecisionAuditEntry?
    
    /// Update an entry (for status changes).
    func update(_ entry: DecisionAuditEntry) async throws
    
    /// Delete entries older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all entries.
    func deleteAll() async throws
    
    /// Count of all entries.
    func count() async throws -> Int
}

// MARK: - In-Memory Decision Audit Store

/// In-memory implementation for testing.
public actor InMemoryDecisionAuditStore: DecisionAuditStore {
    private var entries: [UUID: DecisionAuditEntry] = [:]
    
    public init() {}
    
    public func save(_ entry: DecisionAuditEntry) async throws {
        entries[entry.id] = entry
    }
    
    public func save(_ entries: [DecisionAuditEntry]) async throws {
        for entry in entries {
            self.entries[entry.id] = entry
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [DecisionAuditEntry] {
        entries.values
            .filter { $0.createdAt >= start && $0.createdAt <= end }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    public func fetch(type: DecisionType) async throws -> [DecisionAuditEntry] {
        entries.values
            .filter { $0.decisionType == type }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    public func fetch(status: ReconciliationStatus) async throws -> [DecisionAuditEntry] {
        entries.values
            .filter { $0.status == status }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [DecisionAuditEntry] {
        Array(entries.values
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(count))
    }
    
    public func fetchMostRecent() async throws -> DecisionAuditEntry? {
        entries.values.max { $0.createdAt < $1.createdAt }
    }
    
    public func fetch(syncIdentifier: String) async throws -> DecisionAuditEntry? {
        entries.values.first { $0.syncIdentifier == syncIdentifier }
    }
    
    public func update(_ entry: DecisionAuditEntry) async throws {
        entries[entry.id] = entry
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let toDelete = entries.values.filter { $0.createdAt < date }
        for entry in toDelete {
            entries.removeValue(forKey: entry.id)
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        entries.removeAll()
    }
    
    public func count() async throws -> Int {
        entries.count
    }
}

// MARK: - Sync State (DATA-COHESIVE-004)

/// Represents sync state for a single record type
public struct SyncState: Codable, Sendable, Identifiable {
    public let id: UUID
    public let recordType: String
    public let lastSyncedAt: Date
    public let lastSyncedId: String?
    public let syncCount: Int
    public let failedCount: Int
    public let lastError: String?
    
    public init(
        id: UUID = UUID(),
        recordType: String,
        lastSyncedAt: Date = Date(),
        lastSyncedId: String? = nil,
        syncCount: Int = 0,
        failedCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.recordType = recordType
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedId = lastSyncedId
        self.syncCount = syncCount
        self.failedCount = failedCount
        self.lastError = lastError
    }
}

/// Protocol for persisting Nightscout sync state.
/// Follows same API patterns as GlucoseStore and TreatmentStore.
public protocol SyncStateStore: Sendable {
    /// Save sync state.
    func save(_ state: SyncState) async throws
    
    /// Get sync state for a record type.
    func fetch(recordType: String) async throws -> SyncState?
    
    /// Get all sync states.
    func fetchAll() async throws -> [SyncState]
    
    /// Update last synced timestamp for a record type.
    func updateLastSynced(recordType: String, syncedId: String?) async throws
    
    /// Increment sync count for a record type.
    func incrementSyncCount(recordType: String) async throws
    
    /// Record a sync failure.
    func recordFailure(recordType: String, error: String) async throws
    
    /// Reset sync state for a record type.
    func reset(recordType: String) async throws
    
    /// Delete all sync states.
    func deleteAll() async throws
}

// MARK: - In-Memory Sync State Store

/// In-memory implementation for testing.
public actor InMemorySyncStateStore: SyncStateStore {
    private var states: [String: SyncState] = [:]
    
    public init() {}
    
    public func save(_ state: SyncState) async throws {
        states[state.recordType] = state
    }
    
    public func fetch(recordType: String) async throws -> SyncState? {
        states[recordType]
    }
    
    public func fetchAll() async throws -> [SyncState] {
        Array(states.values).sorted { $0.recordType < $1.recordType }
    }
    
    public func updateLastSynced(recordType: String, syncedId: String?) async throws {
        if let state = states[recordType] {
            states[recordType] = SyncState(
                id: state.id,
                recordType: state.recordType,
                lastSyncedAt: Date(),
                lastSyncedId: syncedId,
                syncCount: state.syncCount,
                failedCount: state.failedCount,
                lastError: nil
            )
        } else {
            states[recordType] = SyncState(recordType: recordType, lastSyncedId: syncedId)
        }
    }
    
    public func incrementSyncCount(recordType: String) async throws {
        if let state = states[recordType] {
            states[recordType] = SyncState(
                id: state.id,
                recordType: state.recordType,
                lastSyncedAt: state.lastSyncedAt,
                lastSyncedId: state.lastSyncedId,
                syncCount: state.syncCount + 1,
                failedCount: state.failedCount,
                lastError: state.lastError
            )
        } else {
            states[recordType] = SyncState(recordType: recordType, syncCount: 1)
        }
    }
    
    public func recordFailure(recordType: String, error: String) async throws {
        if let state = states[recordType] {
            states[recordType] = SyncState(
                id: state.id,
                recordType: state.recordType,
                lastSyncedAt: state.lastSyncedAt,
                lastSyncedId: state.lastSyncedId,
                syncCount: state.syncCount,
                failedCount: state.failedCount + 1,
                lastError: error
            )
        } else {
            states[recordType] = SyncState(recordType: recordType, failedCount: 1, lastError: error)
        }
    }
    
    public func reset(recordType: String) async throws {
        states.removeValue(forKey: recordType)
    }
    
    public func deleteAll() async throws {
        states.removeAll()
    }
}
