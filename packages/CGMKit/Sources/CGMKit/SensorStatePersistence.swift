// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SensorStatePersistence.swift - Sensor state persistence layer
// Part of CGMKit
// Trace: PROD-CGM-002

import Foundation

// MARK: - Persisted Sensor Status

/// Codable version of SensorStatus for persistence.
public struct PersistedSensorStatus: Codable, Sendable, Equatable {
    public let sensorType: String
    public let transmitterID: String?
    public let sensorStartDate: Date?
    public let sensorEndDate: Date?
    public let lastCalibrationDate: Date?
    public let calibrationCount: Int
    public let signalStrength: Int?
    public let batteryLevel: Int?
    public let warmupRemaining: TimeInterval?
    public let isWarmingUp: Bool
    public let isExpired: Bool
    public let errorCode: String?
    public let lastUpdated: Date
    
    public init(
        sensorType: String,
        transmitterID: String? = nil,
        sensorStartDate: Date? = nil,
        sensorEndDate: Date? = nil,
        lastCalibrationDate: Date? = nil,
        calibrationCount: Int = 0,
        signalStrength: Int? = nil,
        batteryLevel: Int? = nil,
        warmupRemaining: TimeInterval? = nil,
        isWarmingUp: Bool = false,
        isExpired: Bool = false,
        errorCode: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.sensorType = sensorType
        self.transmitterID = transmitterID
        self.sensorStartDate = sensorStartDate
        self.sensorEndDate = sensorEndDate
        self.lastCalibrationDate = lastCalibrationDate
        self.calibrationCount = calibrationCount
        self.signalStrength = signalStrength
        self.batteryLevel = batteryLevel
        self.warmupRemaining = warmupRemaining
        self.isWarmingUp = isWarmingUp
        self.isExpired = isExpired
        self.errorCode = errorCode
        self.lastUpdated = lastUpdated
    }
    
    #if canImport(SwiftUI)
    /// Create from SensorStatus.
    public init(from status: SensorStatus) {
        self.sensorType = status.sensorType
        self.transmitterID = status.transmitterID
        self.sensorStartDate = status.sensorStartDate
        self.sensorEndDate = status.sensorEndDate
        self.lastCalibrationDate = status.lastCalibrationDate
        self.calibrationCount = status.calibrationCount
        self.signalStrength = status.signalStrength
        self.batteryLevel = status.batteryLevel
        self.warmupRemaining = status.warmupRemaining
        self.isWarmingUp = status.isWarmingUp
        self.isExpired = status.isExpired
        self.errorCode = status.errorCode
        self.lastUpdated = Date()
    }
    
    /// Convert to SensorStatus.
    public func toSensorStatus() -> SensorStatus {
        SensorStatus(
            sensorType: sensorType,
            transmitterID: transmitterID,
            sensorStartDate: sensorStartDate,
            sensorEndDate: sensorEndDate,
            lastCalibrationDate: lastCalibrationDate,
            calibrationCount: calibrationCount,
            signalStrength: signalStrength,
            batteryLevel: batteryLevel,
            warmupRemaining: warmupRemaining,
            isWarmingUp: isWarmingUp,
            isExpired: isExpired,
            errorCode: errorCode
        )
    }
    #endif
    
    /// Age of this persisted state.
    public var age: TimeInterval {
        Date().timeIntervalSince(lastUpdated)
    }
    
    /// Whether this state is considered stale (older than threshold).
    public func isStale(threshold: TimeInterval = 300) -> Bool {
        age > threshold
    }
}

// MARK: - Sensor History Entry

/// Historical sensor session record.
public struct SensorHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sensorType: String
    public let transmitterID: String?
    public let startDate: Date
    public let endDate: Date?
    public let endReason: SensorEndReason
    public let calibrationCount: Int
    public let averageSignalStrength: Int?
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        sensorType: String,
        transmitterID: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        endReason: SensorEndReason = .unknown,
        calibrationCount: Int = 0,
        averageSignalStrength: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.sensorType = sensorType
        self.transmitterID = transmitterID
        self.startDate = startDate
        self.endDate = endDate
        self.endReason = endReason
        self.calibrationCount = calibrationCount
        self.averageSignalStrength = averageSignalStrength
        self.notes = notes
    }
    
    /// Duration of sensor session.
    public var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }
    
    /// Duration in days.
    public var durationDays: Double? {
        guard let dur = duration else { return nil }
        return dur / 86400.0
    }
}

// MARK: - Sensor End Reason

/// Reason for sensor session ending.
public enum SensorEndReason: String, Codable, Sendable, CaseIterable {
    case expired = "Expired"
    case removed = "Removed by user"
    case failed = "Sensor failure"
    case replaced = "Replaced with new sensor"
    case error = "Error"
    case unknown = "Unknown"
}

// MARK: - Calibration Record

/// Record of a calibration event.
public struct CalibrationRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sensorId: String
    public let timestamp: Date
    public let bloodGlucose: Double
    public let sensorGlucose: Double?
    public let slope: Double?
    public let intercept: Double?
    
    public init(
        id: UUID = UUID(),
        sensorId: String,
        timestamp: Date = Date(),
        bloodGlucose: Double,
        sensorGlucose: Double? = nil,
        slope: Double? = nil,
        intercept: Double? = nil
    ) {
        self.id = id
        self.sensorId = sensorId
        self.timestamp = timestamp
        self.bloodGlucose = bloodGlucose
        self.sensorGlucose = sensorGlucose
        self.slope = slope
        self.intercept = intercept
    }
    
    /// Difference between blood and sensor glucose.
    public var difference: Double? {
        guard let sensor = sensorGlucose else { return nil }
        return bloodGlucose - sensor
    }
}

// MARK: - Sensor State Store Protocol

/// Protocol for sensor state persistence.
public protocol SensorStateStore: Sendable {
    /// Save current sensor status.
    func saveStatus(_ status: PersistedSensorStatus) async throws
    
    /// Load current sensor status.
    func loadStatus() async throws -> PersistedSensorStatus?
    
    /// Clear current sensor status.
    func clearStatus() async throws
    
    /// Save sensor history entry.
    func saveHistoryEntry(_ entry: SensorHistoryEntry) async throws
    
    /// Load sensor history.
    func loadHistory(limit: Int?) async throws -> [SensorHistoryEntry]
    
    /// Load history for date range.
    func loadHistory(from start: Date, to end: Date) async throws -> [SensorHistoryEntry]
    
    /// Save calibration record.
    func saveCalibration(_ calibration: CalibrationRecord) async throws
    
    /// Load calibrations for sensor.
    func loadCalibrations(sensorId: String) async throws -> [CalibrationRecord]
    
    /// Delete old history entries.
    func deleteHistoryOlderThan(_ date: Date) async throws -> Int
}

// MARK: - Sensor State Error

/// Errors for sensor state operations.
public enum SensorStateError: Error, LocalizedError, Sendable {
    case saveFailed(String)
    case loadFailed(String)
    case notFound
    case encodingFailed
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed(let reason): return "Save failed: \(reason)"
        case .loadFailed(let reason): return "Load failed: \(reason)"
        case .notFound: return "Sensor state not found"
        case .encodingFailed: return "Failed to encode sensor state"
        case .decodingFailed: return "Failed to decode sensor state"
        }
    }
}

// MARK: - In-Memory Sensor State Store

/// In-memory implementation for testing.
public actor InMemorySensorStateStore: SensorStateStore {
    private var currentStatus: PersistedSensorStatus?
    private var history: [UUID: SensorHistoryEntry] = [:]
    private var calibrations: [UUID: CalibrationRecord] = [:]
    
    public init() {}
    
    public func saveStatus(_ status: PersistedSensorStatus) async throws {
        currentStatus = status
    }
    
    public func loadStatus() async throws -> PersistedSensorStatus? {
        currentStatus
    }
    
    public func clearStatus() async throws {
        currentStatus = nil
    }
    
    public func saveHistoryEntry(_ entry: SensorHistoryEntry) async throws {
        history[entry.id] = entry
    }
    
    public func loadHistory(limit: Int?) async throws -> [SensorHistoryEntry] {
        let sorted = history.values.sorted { $0.startDate > $1.startDate }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }
    
    public func loadHistory(from start: Date, to end: Date) async throws -> [SensorHistoryEntry] {
        history.values
            .filter { $0.startDate >= start && $0.startDate <= end }
            .sorted { $0.startDate > $1.startDate }
    }
    
    public func saveCalibration(_ calibration: CalibrationRecord) async throws {
        calibrations[calibration.id] = calibration
    }
    
    public func loadCalibrations(sensorId: String) async throws -> [CalibrationRecord] {
        calibrations.values
            .filter { $0.sensorId == sensorId }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func deleteHistoryOlderThan(_ date: Date) async throws -> Int {
        let toDelete = history.values.filter { $0.startDate < date }
        for entry in toDelete {
            history.removeValue(forKey: entry.id)
        }
        return toDelete.count
    }
}

// MARK: - File-Based Sensor State Store

/// JSON file-based persistence for production.
public actor FileSensorStateStore: SensorStateStore {
    private let directory: URL
    private let statusFilename = "sensor-status.json"
    private let historyFilename = "sensor-history.json"
    private let calibrationsFilename = "calibrations.json"
    
    private var cachedStatus: PersistedSensorStatus?
    private var cachedHistory: [UUID: SensorHistoryEntry]?
    private var cachedCalibrations: [UUID: CalibrationRecord]?
    
    public init(directory: URL) {
        self.directory = directory
    }
    
    /// Initialize with default app support directory.
    public static func defaultStore() -> FileSensorStateStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/CGM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileSensorStateStore(directory: dir)
    }
    
    // MARK: - Status
    
    public func saveStatus(_ status: PersistedSensorStatus) async throws {
        cachedStatus = status
        let url = directory.appendingPathComponent(statusFilename)
        do {
            let data = try JSONEncoder().encode(status)
            try data.write(to: url, options: .atomic)
        } catch {
            throw SensorStateError.saveFailed(error.localizedDescription)
        }
    }
    
    public func loadStatus() async throws -> PersistedSensorStatus? {
        if let cached = cachedStatus { return cached }
        
        let url = directory.appendingPathComponent(statusFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            let status = try JSONDecoder().decode(PersistedSensorStatus.self, from: data)
            cachedStatus = status
            return status
        } catch {
            throw SensorStateError.decodingFailed
        }
    }
    
    public func clearStatus() async throws {
        cachedStatus = nil
        let url = directory.appendingPathComponent(statusFilename)
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - History
    
    private func loadHistoryFromDisk() async throws -> [UUID: SensorHistoryEntry] {
        if let cached = cachedHistory { return cached }
        
        let url = directory.appendingPathComponent(historyFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        
        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([SensorHistoryEntry].self, from: data)
            let dict = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            cachedHistory = dict
            return dict
        } catch {
            throw SensorStateError.decodingFailed
        }
    }
    
    private func saveHistoryToDisk() async throws {
        guard let history = cachedHistory else { return }
        let url = directory.appendingPathComponent(historyFilename)
        do {
            let entries = Array(history.values)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            throw SensorStateError.saveFailed(error.localizedDescription)
        }
    }
    
    public func saveHistoryEntry(_ entry: SensorHistoryEntry) async throws {
        var history = try await loadHistoryFromDisk()
        history[entry.id] = entry
        cachedHistory = history
        try await saveHistoryToDisk()
    }
    
    public func loadHistory(limit: Int?) async throws -> [SensorHistoryEntry] {
        let history = try await loadHistoryFromDisk()
        let sorted = history.values.sorted { $0.startDate > $1.startDate }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }
    
    public func loadHistory(from start: Date, to end: Date) async throws -> [SensorHistoryEntry] {
        let history = try await loadHistoryFromDisk()
        return history.values
            .filter { $0.startDate >= start && $0.startDate <= end }
            .sorted { $0.startDate > $1.startDate }
    }
    
    public func deleteHistoryOlderThan(_ date: Date) async throws -> Int {
        var history = try await loadHistoryFromDisk()
        let toDelete = history.values.filter { $0.startDate < date }
        for entry in toDelete {
            history.removeValue(forKey: entry.id)
        }
        cachedHistory = history
        try await saveHistoryToDisk()
        return toDelete.count
    }
    
    // MARK: - Calibrations
    
    private func loadCalibrationsFromDisk() async throws -> [UUID: CalibrationRecord] {
        if let cached = cachedCalibrations { return cached }
        
        let url = directory.appendingPathComponent(calibrationsFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        
        do {
            let data = try Data(contentsOf: url)
            let records = try JSONDecoder().decode([CalibrationRecord].self, from: data)
            let dict = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            cachedCalibrations = dict
            return dict
        } catch {
            throw SensorStateError.decodingFailed
        }
    }
    
    private func saveCalibrationsToDisk() async throws {
        guard let calibrations = cachedCalibrations else { return }
        let url = directory.appendingPathComponent(calibrationsFilename)
        do {
            let records = Array(calibrations.values)
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            throw SensorStateError.saveFailed(error.localizedDescription)
        }
    }
    
    public func saveCalibration(_ calibration: CalibrationRecord) async throws {
        var calibrations = try await loadCalibrationsFromDisk()
        calibrations[calibration.id] = calibration
        cachedCalibrations = calibrations
        try await saveCalibrationsToDisk()
    }
    
    public func loadCalibrations(sensorId: String) async throws -> [CalibrationRecord] {
        let calibrations = try await loadCalibrationsFromDisk()
        return calibrations.values
            .filter { $0.sensorId == sensorId }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Sensor State Manager

/// Unified manager for sensor state persistence.
public actor SensorStateManager {
    private let store: any SensorStateStore
    
    public init(store: any SensorStateStore) {
        self.store = store
    }
    
    /// Create with default file-based store.
    public static func defaultManager() -> SensorStateManager {
        SensorStateManager(store: FileSensorStateStore.defaultStore())
    }
    
    /// Create with in-memory store for testing.
    public static func inMemory() -> SensorStateManager {
        SensorStateManager(store: InMemorySensorStateStore())
    }
    
    // MARK: - Status Operations
    
    #if canImport(SwiftUI)
    /// Update sensor status from SensorStatus.
    public func updateStatus(from status: SensorStatus) async throws {
        let persisted = PersistedSensorStatus(from: status)
        try await store.saveStatus(persisted)
    }
    
    /// Get current sensor status.
    public func getCurrentStatus() async throws -> SensorStatus? {
        guard let persisted = try await store.loadStatus() else { return nil }
        return persisted.toSensorStatus()
    }
    #endif
    
    /// Update sensor status from PersistedSensorStatus.
    public func updateStatus(_ status: PersistedSensorStatus) async throws {
        try await store.saveStatus(status)
    }
    
    /// Get current persisted sensor status.
    public func getCurrentPersistedStatus() async throws -> PersistedSensorStatus? {
        try await store.loadStatus()
    }
    
    /// Check if current status is stale.
    public func isStatusStale(threshold: TimeInterval = 300) async -> Bool {
        guard let status = try? await store.loadStatus() else { return true }
        return status.isStale(threshold: threshold)
    }
    
    /// Clear current status (sensor removed).
    public func clearStatus() async throws {
        try await store.clearStatus()
    }
    
    // MARK: - History Operations
    
    /// Record sensor session end.
    public func endSensorSession(
        sensorType: String,
        transmitterID: String?,
        startDate: Date,
        endDate: Date,
        reason: SensorEndReason,
        calibrationCount: Int = 0
    ) async throws {
        let entry = SensorHistoryEntry(
            sensorType: sensorType,
            transmitterID: transmitterID,
            startDate: startDate,
            endDate: endDate,
            endReason: reason,
            calibrationCount: calibrationCount
        )
        try await store.saveHistoryEntry(entry)
    }
    
    /// Get recent sensor history.
    public func getRecentHistory(limit: Int = 10) async throws -> [SensorHistoryEntry] {
        try await store.loadHistory(limit: limit)
    }
    
    /// Get sensor statistics.
    public func getSensorStatistics() async throws -> SensorStatistics {
        let history = try await store.loadHistory(limit: nil)
        return SensorStatistics(from: history)
    }
    
    // MARK: - Calibration Operations
    
    /// Record a calibration.
    public func recordCalibration(
        sensorId: String,
        bloodGlucose: Double,
        sensorGlucose: Double? = nil
    ) async throws {
        let record = CalibrationRecord(
            sensorId: sensorId,
            bloodGlucose: bloodGlucose,
            sensorGlucose: sensorGlucose
        )
        try await store.saveCalibration(record)
    }
    
    /// Get calibrations for current sensor.
    public func getCalibrations(sensorId: String) async throws -> [CalibrationRecord] {
        try await store.loadCalibrations(sensorId: sensorId)
    }
}

// MARK: - Sensor Statistics

/// Aggregated sensor statistics.
public struct SensorStatistics: Sendable {
    public let totalSensors: Int
    public let averageDurationDays: Double?
    public let expiredCount: Int
    public let failedCount: Int
    public let removedEarlyCount: Int
    public let lastSensorDate: Date?
    
    public init(from history: [SensorHistoryEntry]) {
        self.totalSensors = history.count
        
        let durations = history.compactMap { $0.durationDays }
        self.averageDurationDays = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        
        self.expiredCount = history.filter { $0.endReason == .expired }.count
        self.failedCount = history.filter { $0.endReason == .failed }.count
        self.removedEarlyCount = history.filter { $0.endReason == .removed }.count
        self.lastSensorDate = history.first?.startDate
    }
    
    /// Success rate (expired normally vs. failed/removed).
    public var successRate: Double? {
        guard totalSensors > 0 else { return nil }
        let successful = totalSensors - failedCount
        return Double(successful) / Double(totalSensors) * 100
    }
}
