// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CGMHistoryManager.swift
// CGMKit
//
// Manages history of past sensor sessions and transmitters.
// Enables users to view consumable usage patterns over time.
//
// LIFE-CGM-007: Sensor session history log
// LIFE-CGM-008: Transmitter history log (G6/G7)

import Foundation

// MARK: - Transmitter History Entry (LIFE-CGM-008)

/// Record of a completed transmitter usage period
public struct TransmitterHistoryEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let transmitterId: String
    public let cgmType: CGMType
    public let activationDate: Date
    public let deactivationDate: Date
    public let plannedLifetimeDays: Int
    public let actualDurationDays: Double
    public let endReason: TransmitterEndReason
    public let sensorsUsed: Int
    
    public init(
        id: UUID = UUID(),
        transmitterId: String,
        cgmType: CGMType,
        activationDate: Date,
        deactivationDate: Date,
        plannedLifetimeDays: Int,
        endReason: TransmitterEndReason = .expired,
        sensorsUsed: Int = 0
    ) {
        self.id = id
        self.transmitterId = transmitterId
        self.cgmType = cgmType
        self.activationDate = activationDate
        self.deactivationDate = deactivationDate
        self.plannedLifetimeDays = plannedLifetimeDays
        self.actualDurationDays = deactivationDate.timeIntervalSince(activationDate) / 86400
        self.endReason = endReason
        self.sensorsUsed = sensorsUsed
    }
    
    /// Create from a TransmitterSession when it ends
    public init(from session: TransmitterSession, deactivationDate: Date, endReason: TransmitterEndReason, sensorsUsed: Int = 0) {
        self.id = UUID()
        self.transmitterId = session.transmitterId
        self.cgmType = session.cgmType
        self.activationDate = session.activationDate
        self.deactivationDate = deactivationDate
        self.plannedLifetimeDays = session.lifetimeDays
        self.actualDurationDays = deactivationDate.timeIntervalSince(session.activationDate) / 86400
        self.endReason = endReason
        self.sensorsUsed = sensorsUsed
    }
    
    /// Whether this transmitter was used for its full lifetime
    public var usedFullLifetime: Bool {
        actualDurationDays >= Double(plannedLifetimeDays) * 0.95
    }
    
    /// Duration formatted for display
    public var durationText: String {
        let days = Int(actualDurationDays)
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

/// Reason for transmitter ending
public enum TransmitterEndReason: String, Sendable, Codable, CaseIterable {
    case expired = "expired"
    case batteryDepleted = "battery_depleted"
    case userReplaced = "user_replaced"
    case malfunction = "malfunction"
    case unknown = "unknown"
    
    /// Human-readable description
    public var displayText: String {
        switch self {
        case .expired: return "Expired"
        case .batteryDepleted: return "Battery depleted"
        case .userReplaced: return "Replaced by user"
        case .malfunction: return "Malfunction"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - SensorHistoryEntry Extensions (LIFE-CGM-007)

extension SensorHistoryEntry {
    /// Duration in hours (computed from start/end dates)
    public var durationHours: Double {
        guard let end = endDate else { return 0 }
        return end.timeIntervalSince(startDate) / 3600
    }
    
    /// Duration formatted for display
    public var durationText: String {
        let hours = durationHours
        let days = Int(hours / 24)
        let remainingHours = Int(hours.truncatingRemainder(dividingBy: 24))
        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else {
            return "\(remainingHours)h"
        }
    }
    
    /// CGMType derived from sensorType string
    public var cgmType: CGMType? {
        CGMType(rawValue: sensorType)
    }
}

// MARK: - CGM History Summary

/// Summary statistics for CGM history
public struct CGMHistorySummary: Sendable {
    public let totalSensors: Int
    public let totalTransmitters: Int
    public let averageSensorDurationHours: Double
    public let averageTransmitterDurationDays: Double
    
    public init(
        sensorHistory: [SensorHistoryEntry],
        transmitterHistory: [TransmitterHistoryEntry]
    ) {
        self.totalSensors = sensorHistory.count
        self.totalTransmitters = transmitterHistory.count
        
        if sensorHistory.isEmpty {
            self.averageSensorDurationHours = 0
        } else {
            let totalHours = sensorHistory.compactMap { $0.endDate }.reduce(0.0) { total, endDate in
                // Find corresponding entry
                if let entry = sensorHistory.first(where: { $0.endDate == endDate }) {
                    return total + endDate.timeIntervalSince(entry.startDate) / 3600
                }
                return total
            }
            self.averageSensorDurationHours = totalHours / Double(sensorHistory.count)
        }
        
        if transmitterHistory.isEmpty {
            self.averageTransmitterDurationDays = 0
        } else {
            self.averageTransmitterDurationDays = transmitterHistory.map(\.actualDurationDays).reduce(0, +) / Double(transmitterHistory.count)
        }
    }
}

// MARK: - CGM History Persistence Protocol

/// Protocol for persisting CGM history
public protocol CGMHistoryPersistence: Sendable {
    func saveSensorEntry(_ entry: SensorHistoryEntry) async
    func loadSensorHistory() async -> [SensorHistoryEntry]
    func clearSensorHistory() async
    
    func saveTransmitterEntry(_ entry: TransmitterHistoryEntry) async
    func loadTransmitterHistory() async -> [TransmitterHistoryEntry]
    func clearTransmitterHistory() async
}

// MARK: - In-Memory History Persistence

/// In-memory persistence for testing
public actor InMemoryCGMHistoryPersistence: CGMHistoryPersistence {
    private var sensorHistory: [SensorHistoryEntry] = []
    private var transmitterHistory: [TransmitterHistoryEntry] = []
    
    public init() {}
    
    public func saveSensorEntry(_ entry: SensorHistoryEntry) async {
        sensorHistory.append(entry)
    }
    
    public func loadSensorHistory() async -> [SensorHistoryEntry] {
        sensorHistory.sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
    }
    
    public func clearSensorHistory() async {
        sensorHistory.removeAll()
    }
    
    public func saveTransmitterEntry(_ entry: TransmitterHistoryEntry) async {
        transmitterHistory.append(entry)
    }
    
    public func loadTransmitterHistory() async -> [TransmitterHistoryEntry] {
        transmitterHistory.sorted { $0.deactivationDate > $1.deactivationDate }
    }
    
    public func clearTransmitterHistory() async {
        transmitterHistory.removeAll()
    }
}

// MARK: - UserDefaults History Persistence

/// UserDefaults-based persistence for production
public actor UserDefaultsCGMHistoryPersistence: CGMHistoryPersistence {
    private let defaults: UserDefaults
    private let sensorHistoryKey = "com.t1pal.cgm.sensor.history"
    private let transmitterHistoryKey = "com.t1pal.cgm.transmitter.history"
    private let maxHistoryEntries: Int
    
    public init(defaults: UserDefaults = .standard, maxHistoryEntries: Int = 100) {
        self.defaults = defaults
        self.maxHistoryEntries = maxHistoryEntries
    }
    
    public func saveSensorEntry(_ entry: SensorHistoryEntry) async {
        var history = await loadSensorHistory()
        history.append(entry)
        
        // Keep only most recent entries
        if history.count > maxHistoryEntries {
            history = Array(history.sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }.prefix(maxHistoryEntries))
        }
        
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: sensorHistoryKey)
        }
    }
    
    public func loadSensorHistory() async -> [SensorHistoryEntry] {
        guard let data = defaults.data(forKey: sensorHistoryKey) else { return [] }
        return (try? JSONDecoder().decode([SensorHistoryEntry].self, from: data)) ?? []
    }
    
    public func clearSensorHistory() async {
        defaults.removeObject(forKey: sensorHistoryKey)
    }
    
    public func saveTransmitterEntry(_ entry: TransmitterHistoryEntry) async {
        var history = await loadTransmitterHistory()
        history.append(entry)
        
        // Keep only most recent entries
        if history.count > maxHistoryEntries {
            history = Array(history.sorted { $0.deactivationDate > $1.deactivationDate }.prefix(maxHistoryEntries))
        }
        
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: transmitterHistoryKey)
        }
    }
    
    public func loadTransmitterHistory() async -> [TransmitterHistoryEntry] {
        guard let data = defaults.data(forKey: transmitterHistoryKey) else { return [] }
        return (try? JSONDecoder().decode([TransmitterHistoryEntry].self, from: data)) ?? []
    }
    
    public func clearTransmitterHistory() async {
        defaults.removeObject(forKey: transmitterHistoryKey)
    }
}

// MARK: - CGM History Manager

/// Manages CGM history logging (LIFE-CGM-007, LIFE-CGM-008)
public actor CGMHistoryManager {
    private let persistence: CGMHistoryPersistence
    private var sensorCount: Int = 0  // Count sensors used with current transmitter
    
    public init(persistence: CGMHistoryPersistence = UserDefaultsCGMHistoryPersistence()) {
        self.persistence = persistence
    }
    
    // MARK: - Sensor History (LIFE-CGM-007)
    
    /// Log a completed sensor session
    public func logSensorSession(_ entry: SensorHistoryEntry) async {
        await persistence.saveSensorEntry(entry)
        sensorCount += 1
    }
    
    /// Log a sensor session with explicit parameters
    public func logSensorSession(
        sensorType: String,
        transmitterId: String? = nil,
        startDate: Date,
        endDate: Date,
        endReason: SensorEndReason = .expired,
        calibrationCount: Int = 0
    ) async {
        let entry = SensorHistoryEntry(
            sensorType: sensorType,
            transmitterID: transmitterId,
            startDate: startDate,
            endDate: endDate,
            endReason: endReason,
            calibrationCount: calibrationCount
        )
        await persistence.saveSensorEntry(entry)
        sensorCount += 1
    }
    
    /// Get sensor history
    public func getSensorHistory() async -> [SensorHistoryEntry] {
        await persistence.loadSensorHistory()
    }
    
    /// Get recent sensor history (last N entries)
    public func getRecentSensorHistory(limit: Int = 10) async -> [SensorHistoryEntry] {
        let history = await persistence.loadSensorHistory()
        return Array(history.sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }.prefix(limit))
    }
    
    // MARK: - Transmitter History (LIFE-CGM-008)
    
    /// Log a completed transmitter
    public func logTransmitter(
        _ session: TransmitterSession,
        deactivationDate: Date = Date(),
        endReason: TransmitterEndReason = .expired
    ) async {
        let entry = TransmitterHistoryEntry(
            from: session,
            deactivationDate: deactivationDate,
            endReason: endReason,
            sensorsUsed: sensorCount
        )
        await persistence.saveTransmitterEntry(entry)
        sensorCount = 0  // Reset for next transmitter
    }
    
    /// Log a transmitter with explicit parameters
    public func logTransmitter(
        transmitterId: String,
        cgmType: CGMType,
        activationDate: Date,
        deactivationDate: Date,
        plannedLifetimeDays: Int,
        endReason: TransmitterEndReason = .expired,
        sensorsUsed: Int = 0
    ) async {
        let entry = TransmitterHistoryEntry(
            transmitterId: transmitterId,
            cgmType: cgmType,
            activationDate: activationDate,
            deactivationDate: deactivationDate,
            plannedLifetimeDays: plannedLifetimeDays,
            endReason: endReason,
            sensorsUsed: sensorsUsed
        )
        await persistence.saveTransmitterEntry(entry)
        sensorCount = 0
    }
    
    /// Get transmitter history
    public func getTransmitterHistory() async -> [TransmitterHistoryEntry] {
        await persistence.loadTransmitterHistory()
    }
    
    /// Get recent transmitter history (last N entries)
    public func getRecentTransmitterHistory(limit: Int = 5) async -> [TransmitterHistoryEntry] {
        let history = await persistence.loadTransmitterHistory()
        return Array(history.sorted { $0.deactivationDate > $1.deactivationDate }.prefix(limit))
    }
    
    // MARK: - Statistics
    
    /// Get history summary
    public func getSummary() async -> CGMHistorySummary {
        let sensors = await persistence.loadSensorHistory()
        let transmitters = await persistence.loadTransmitterHistory()
        return CGMHistorySummary(sensorHistory: sensors, transmitterHistory: transmitters)
    }
    
    /// Get sensors used for a specific CGM type
    public func getSensorHistory(for cgmType: CGMType) async -> [SensorHistoryEntry] {
        let history = await persistence.loadSensorHistory()
        return history.filter { $0.sensorType == cgmType.rawValue }
    }
    
    /// Get transmitters for a specific CGM type
    public func getTransmitterHistory(for cgmType: CGMType) async -> [TransmitterHistoryEntry] {
        let history = await persistence.loadTransmitterHistory()
        return history.filter { $0.cgmType == cgmType }
    }
    
    // MARK: - Management
    
    /// Clear all history
    public func clearAllHistory() async {
        await persistence.clearSensorHistory()
        await persistence.clearTransmitterHistory()
        sensorCount = 0
    }
    
    /// Reset sensor count (e.g., when new transmitter activated)
    public func resetSensorCount() {
        sensorCount = 0
    }
    
    /// Get current sensor count for active transmitter
    public func getCurrentSensorCount() -> Int {
        sensorCount
    }
}
