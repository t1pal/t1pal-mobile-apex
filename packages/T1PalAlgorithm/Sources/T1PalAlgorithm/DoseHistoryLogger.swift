// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DoseHistoryLogger.swift
// T1Pal Mobile
//
// Dose history logging for all insulin deliveries
// Requirements: PROD-AID-004, REQ-SAFETY-002
//
// Trace: PROD-AID-004, PRD-009

import Foundation
import T1PalCore

// MARK: - Dose Entry Types

/// Type of insulin dose
public enum DoseType: String, Codable, Sendable, CaseIterable {
    case bolus = "bolus"
    case smb = "smb"
    case tempBasal = "temp_basal"
    case scheduledBasal = "scheduled_basal"
    case prime = "prime"
    case correction = "correction"
}

/// Source of dose entry
public enum DoseSource: String, Codable, Sendable, CaseIterable {
    case algorithm = "algorithm"
    case user = "user"
    case manual = "manual"
    case pump = "pump"
    case imported = "imported"
}

/// Status of a dose entry
public enum DoseStatus: String, Codable, Sendable {
    case pending = "pending"
    case delivered = "delivered"
    case failed = "failed"
    case cancelled = "cancelled"
    case partial = "partial"
}

// MARK: - Dose Entry

/// A recorded insulin dose
public struct DoseEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    
    /// Type of dose
    public let type: DoseType
    
    /// When the dose started
    public let startTime: Date
    
    /// When the dose ended (for temp basals)
    public let endTime: Date?
    
    /// Dose amount in units
    public let units: Double
    
    /// Temp basal rate (U/hr) if applicable
    public let rate: Double?
    
    /// Duration in seconds (for temp basals)
    public let duration: TimeInterval?
    
    /// Source of the dose
    public let source: DoseSource
    
    /// Current status
    public var status: DoseStatus
    
    /// Associated glucose value at time of dose
    public let glucoseAtDose: Double?
    
    /// Associated IOB at time of dose
    public let iobAtDose: Double?
    
    /// Associated COB at time of dose
    public let cobAtDose: Double?
    
    /// Algorithm reason if from algorithm
    public let algorithmReason: String?
    
    /// Pump command ID reference
    public let commandID: UUID?
    
    /// Any notes or annotations
    public var notes: String?
    
    public init(
        id: UUID = UUID(),
        type: DoseType,
        startTime: Date = Date(),
        endTime: Date? = nil,
        units: Double,
        rate: Double? = nil,
        duration: TimeInterval? = nil,
        source: DoseSource = .algorithm,
        status: DoseStatus = .delivered,
        glucoseAtDose: Double? = nil,
        iobAtDose: Double? = nil,
        cobAtDose: Double? = nil,
        algorithmReason: String? = nil,
        commandID: UUID? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.units = units
        self.rate = rate
        self.duration = duration
        self.source = source
        self.status = status
        self.glucoseAtDose = glucoseAtDose
        self.iobAtDose = iobAtDose
        self.cobAtDose = cobAtDose
        self.algorithmReason = algorithmReason
        self.commandID = commandID
        self.notes = notes
    }
    
    /// Age of dose entry in seconds
    public var age: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Create bolus entry
    public static func bolus(
        units: Double,
        source: DoseSource = .user,
        glucoseAtDose: Double? = nil,
        iobAtDose: Double? = nil
    ) -> DoseEntry {
        DoseEntry(
            type: .bolus,
            units: units,
            source: source,
            glucoseAtDose: glucoseAtDose,
            iobAtDose: iobAtDose
        )
    }
    
    /// Create SMB entry
    public static func smb(
        units: Double,
        glucoseAtDose: Double? = nil,
        iobAtDose: Double? = nil,
        algorithmReason: String? = nil
    ) -> DoseEntry {
        DoseEntry(
            type: .smb,
            units: units,
            source: .algorithm,
            glucoseAtDose: glucoseAtDose,
            iobAtDose: iobAtDose,
            algorithmReason: algorithmReason
        )
    }
    
    /// Create temp basal entry
    public static func tempBasal(
        rate: Double,
        duration: TimeInterval,
        source: DoseSource = .algorithm,
        algorithmReason: String? = nil
    ) -> DoseEntry {
        let units = (rate * duration) / 3600.0  // Convert to units
        return DoseEntry(
            type: .tempBasal,
            endTime: Date().addingTimeInterval(duration),
            units: units,
            rate: rate,
            duration: duration,
            source: source,
            algorithmReason: algorithmReason
        )
    }
    
    /// Create scheduled basal entry
    public static func scheduledBasal(
        rate: Double,
        duration: TimeInterval
    ) -> DoseEntry {
        let units = (rate * duration) / 3600.0
        return DoseEntry(
            type: .scheduledBasal,
            endTime: Date().addingTimeInterval(duration),
            units: units,
            rate: rate,
            duration: duration,
            source: .pump
        )
    }
}

// MARK: - Dose History Store Protocol

/// Protocol for dose history persistence
public protocol DoseHistoryStore: Sendable {
    /// Log a new dose entry
    func log(_ entry: DoseEntry) async throws
    
    /// Get entries for a time range
    func entries(from start: Date, to end: Date) async throws -> [DoseEntry]
    
    /// Get entries for last N hours
    func entries(lastHours: Int) async throws -> [DoseEntry]
    
    /// Update entry status
    func updateStatus(id: UUID, status: DoseStatus) async throws
    
    /// Delete entry by ID
    func delete(id: UUID) async throws
    
    /// Clear all entries older than specified hours
    func clearHistory(olderThan hours: Int) async throws
    
    /// Get total entry count
    func count() async throws -> Int
}

// MARK: - In-Memory Store

/// In-memory implementation for testing
public actor InMemoryDoseHistoryStore: DoseHistoryStore {
    private var entries: [DoseEntry] = []
    
    /// Maximum entries to keep
    public static let maxEntries = 2880  // 10 days at 5-min intervals
    
    public init() {}
    
    public func log(_ entry: DoseEntry) async throws {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }
    
    public func entries(from start: Date, to end: Date) async throws -> [DoseEntry] {
        return entries.filter { $0.startTime >= start && $0.startTime <= end }
            .sorted { $0.startTime > $1.startTime }
    }
    
    public func entries(lastHours: Int) async throws -> [DoseEntry] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        return entries.filter { $0.startTime >= cutoff }
            .sorted { $0.startTime > $1.startTime }
    }
    
    public func updateStatus(id: UUID, status: DoseStatus) async throws {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].status = status
        }
    }
    
    public func delete(id: UUID) async throws {
        entries.removeAll { $0.id == id }
    }
    
    public func clearHistory(olderThan hours: Int) async throws {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        entries = entries.filter { $0.startTime >= cutoff }
    }
    
    public func count() async throws -> Int {
        return entries.count
    }
    
    /// Testing helper - get all entries
    public func getAllEntries() -> [DoseEntry] {
        entries
    }
}

// MARK: - File-Based Store

/// File-based implementation for production
public actor FileDoseHistoryStore: DoseHistoryStore {
    private let fileURL: URL
    private var cachedEntries: [DoseEntry]?
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    /// Maximum entries to keep
    public static let maxEntries = 2880
    
    public init(directory: URL? = nil) throws {
        let baseDir: URL
        if let dir = directory {
            baseDir = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseDir = appSupport.appendingPathComponent("T1Pal/DoseHistory", isDirectory: true)
        }
        
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        self.fileURL = baseDir.appendingPathComponent("dose-history.json")
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    public func log(_ entry: DoseEntry) async throws {
        var entries = try await loadEntries()
        entries.insert(entry, at: 0)
        
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        
        try await saveEntries(entries)
    }
    
    public func entries(from start: Date, to end: Date) async throws -> [DoseEntry] {
        let all = try await loadEntries()
        return all.filter { $0.startTime >= start && $0.startTime <= end }
            .sorted { $0.startTime > $1.startTime }
    }
    
    public func entries(lastHours: Int) async throws -> [DoseEntry] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        let all = try await loadEntries()
        return all.filter { $0.startTime >= cutoff }
            .sorted { $0.startTime > $1.startTime }
    }
    
    public func updateStatus(id: UUID, status: DoseStatus) async throws {
        var entries = try await loadEntries()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].status = status
            try await saveEntries(entries)
        }
    }
    
    public func delete(id: UUID) async throws {
        var entries = try await loadEntries()
        entries.removeAll { $0.id == id }
        try await saveEntries(entries)
    }
    
    public func clearHistory(olderThan hours: Int) async throws {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        var entries = try await loadEntries()
        entries = entries.filter { $0.startTime >= cutoff }
        try await saveEntries(entries)
    }
    
    public func count() async throws -> Int {
        let entries = try await loadEntries()
        return entries.count
    }
    
    private func loadEntries() async throws -> [DoseEntry] {
        if let cached = cachedEntries {
            return cached
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: fileURL)
        let entries = try decoder.decode([DoseEntry].self, from: data)
        cachedEntries = entries
        return entries
    }
    
    private func saveEntries(_ entries: [DoseEntry]) async throws {
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
        cachedEntries = entries
    }
}

// MARK: - Dose History Statistics

/// Statistics calculated from dose history
public struct DoseHistoryStatistics: Sendable {
    public let totalDoses: Int
    public let totalUnits: Double
    public let bolusUnits: Double
    public let smbUnits: Double
    public let basalUnits: Double
    public let averageBolusSize: Double
    public let averageSMBSize: Double
    public let bolusCount: Int
    public let smbCount: Int
    public let tempBasalCount: Int
    
    public init(
        totalDoses: Int,
        totalUnits: Double,
        bolusUnits: Double,
        smbUnits: Double,
        basalUnits: Double,
        averageBolusSize: Double,
        averageSMBSize: Double,
        bolusCount: Int,
        smbCount: Int,
        tempBasalCount: Int
    ) {
        self.totalDoses = totalDoses
        self.totalUnits = totalUnits
        self.bolusUnits = bolusUnits
        self.smbUnits = smbUnits
        self.basalUnits = basalUnits
        self.averageBolusSize = averageBolusSize
        self.averageSMBSize = averageSMBSize
        self.bolusCount = bolusCount
        self.smbCount = smbCount
        self.tempBasalCount = tempBasalCount
    }
    
    /// Calculate from entries
    public static func from(entries: [DoseEntry]) -> DoseHistoryStatistics {
        let delivered = entries.filter { $0.status == .delivered }
        
        let boluses = delivered.filter { $0.type == .bolus }
        let smbs = delivered.filter { $0.type == .smb }
        let basals = delivered.filter { $0.type == .tempBasal || $0.type == .scheduledBasal }
        
        let bolusUnits = boluses.reduce(0.0) { $0 + $1.units }
        let smbUnits = smbs.reduce(0.0) { $0 + $1.units }
        let basalUnits = basals.reduce(0.0) { $0 + $1.units }
        
        let avgBolus = boluses.isEmpty ? 0 : bolusUnits / Double(boluses.count)
        let avgSMB = smbs.isEmpty ? 0 : smbUnits / Double(smbs.count)
        
        return DoseHistoryStatistics(
            totalDoses: delivered.count,
            totalUnits: bolusUnits + smbUnits + basalUnits,
            bolusUnits: bolusUnits,
            smbUnits: smbUnits,
            basalUnits: basalUnits,
            averageBolusSize: avgBolus,
            averageSMBSize: avgSMB,
            bolusCount: boluses.count,
            smbCount: smbs.count,
            tempBasalCount: basals.count
        )
    }
}

// MARK: - Dose History Logger

/// High-level manager for dose history logging
public actor DoseHistoryLogger {
    private let store: DoseHistoryStore
    
    /// Default retention period in hours
    public static let defaultRetentionHours = 240  // 10 days
    
    // MARK: - Callbacks
    
    public var onDoseLogged: (@Sendable (DoseEntry) -> Void)?
    
    // MARK: - Initialization
    
    public init(store: DoseHistoryStore) {
        self.store = store
    }
    
    /// Create in-memory logger for testing
    public static func inMemory() -> DoseHistoryLogger {
        DoseHistoryLogger(store: InMemoryDoseHistoryStore())
    }
    
    /// Create file-based logger for production
    public static func fileBased() throws -> DoseHistoryLogger {
        let store = try FileDoseHistoryStore()
        return DoseHistoryLogger(store: store)
    }
    
    // MARK: - Logging
    
    /// Log a bolus dose
    public func logBolus(
        units: Double,
        source: DoseSource = .user,
        glucoseAtDose: Double? = nil,
        iobAtDose: Double? = nil
    ) async throws {
        let entry = DoseEntry.bolus(
            units: units,
            source: source,
            glucoseAtDose: glucoseAtDose,
            iobAtDose: iobAtDose
        )
        try await store.log(entry)
        onDoseLogged?(entry)
    }
    
    /// Log an SMB dose
    public func logSMB(
        units: Double,
        glucoseAtDose: Double? = nil,
        iobAtDose: Double? = nil,
        algorithmReason: String? = nil
    ) async throws {
        let entry = DoseEntry.smb(
            units: units,
            glucoseAtDose: glucoseAtDose,
            iobAtDose: iobAtDose,
            algorithmReason: algorithmReason
        )
        try await store.log(entry)
        onDoseLogged?(entry)
    }
    
    /// Log a temp basal dose
    public func logTempBasal(
        rate: Double,
        duration: TimeInterval,
        source: DoseSource = .algorithm,
        algorithmReason: String? = nil
    ) async throws {
        let entry = DoseEntry.tempBasal(
            rate: rate,
            duration: duration,
            source: source,
            algorithmReason: algorithmReason
        )
        try await store.log(entry)
        onDoseLogged?(entry)
    }
    
    /// Log from a pump command result
    public func logFromCommand(_ result: PumpCommandResult) async throws {
        guard result.success else { return }
        
        let command = result.command
        var entry: DoseEntry?
        
        switch command.type {
        case .bolus:
            if let amount = command.bolusAmount {
                entry = DoseEntry(
                    type: .bolus,
                    units: amount,
                    source: command.source == .algorithm ? .algorithm : .user,
                    commandID: command.id
                )
            }
            
        case .smb:
            if let amount = command.bolusAmount {
                entry = DoseEntry(
                    type: .smb,
                    units: amount,
                    source: .algorithm,
                    commandID: command.id
                )
            }
            
        case .tempBasal:
            if let rate = command.tempBasalRate,
               let duration = command.tempBasalDuration {
                let units = (rate * duration) / 3600.0
                entry = DoseEntry(
                    type: .tempBasal,
                    endTime: Date().addingTimeInterval(duration),
                    units: units,
                    rate: rate,
                    duration: duration,
                    source: command.source == .algorithm ? .algorithm : .user,
                    commandID: command.id
                )
            }
            
        default:
            // Suspend/resume/cancel don't create dose entries
            break
        }
        
        if let entry = entry {
            try await store.log(entry)
            onDoseLogged?(entry)
        }
    }
    
    // MARK: - Queries
    
    /// Get recent doses
    public func getRecentDoses(hours: Int = 24) async throws -> [DoseEntry] {
        try await store.entries(lastHours: hours)
    }
    
    /// Get doses in time range
    public func getDoses(from start: Date, to end: Date) async throws -> [DoseEntry] {
        try await store.entries(from: start, to: end)
    }
    
    /// Get total insulin delivered in last N hours
    public func getTotalInsulin(lastHours: Int = 24) async throws -> Double {
        let entries = try await store.entries(lastHours: lastHours)
        return entries
            .filter { $0.status == .delivered }
            .reduce(0.0) { $0 + $1.units }
    }
    
    /// Get statistics for last N hours
    public func getStatistics(lastHours: Int = 24) async throws -> DoseHistoryStatistics {
        let entries = try await store.entries(lastHours: lastHours)
        return DoseHistoryStatistics.from(entries: entries)
    }
    
    // MARK: - Maintenance
    
    /// Clean up old entries
    public func performMaintenance() async throws {
        try await store.clearHistory(olderThan: Self.defaultRetentionHours)
    }
    
    /// Update entry status
    public func updateStatus(id: UUID, status: DoseStatus) async throws {
        try await store.updateStatus(id: id, status: status)
    }
}

// MARK: - Dose History Error

/// Errors for dose history operations
public enum DoseHistoryError: Error, LocalizedError {
    case entryNotFound
    case invalidEntry(String)
    case storageFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "Dose entry not found"
        case .invalidEntry(let reason):
            return "Invalid dose entry: \(reason)"
        case .storageFailed(let error):
            return "Storage failed: \(error.localizedDescription)"
        }
    }
}
