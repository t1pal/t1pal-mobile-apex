// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PumpHistoryManager.swift
// PumpKit
//
// Manages history of past pump consumable sessions (pods, reservoirs, cartridges).
// Enables users to view consumable usage patterns over time.
//
// LIFE-PUMP-008: Pump consumable history log

import Foundation

// MARK: - Pump Consumable Entry

/// Record of a completed pump consumable usage period
public struct PumpConsumableEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let pumpType: PumpType
    public let activationDate: Date
    public let deactivationDate: Date
    public let plannedLifetimeHours: Int
    public let actualDurationHours: Double
    public let endReason: PumpConsumableEndReason
    public let insulinDelivered: Double?  // Total units delivered
    public let podLotNumber: String?      // For Omnipod
    public let serialNumber: String?      // For pumps with serial numbers
    
    public init(
        id: UUID = UUID(),
        pumpType: PumpType,
        activationDate: Date,
        deactivationDate: Date,
        plannedLifetimeHours: Int,
        endReason: PumpConsumableEndReason = .expired,
        insulinDelivered: Double? = nil,
        podLotNumber: String? = nil,
        serialNumber: String? = nil
    ) {
        self.id = id
        self.pumpType = pumpType
        self.activationDate = activationDate
        self.deactivationDate = deactivationDate
        self.plannedLifetimeHours = plannedLifetimeHours
        self.actualDurationHours = deactivationDate.timeIntervalSince(activationDate) / 3600
        self.endReason = endReason
        self.insulinDelivered = insulinDelivered
        self.podLotNumber = podLotNumber
        self.serialNumber = serialNumber
    }
    
    /// Whether this consumable was used for its full lifetime
    public var usedFullLifetime: Bool {
        actualDurationHours >= Double(plannedLifetimeHours) * 0.95
    }
    
    /// Duration formatted for display
    public var durationText: String {
        let hours = Int(actualDurationHours)
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else {
            return "\(hours)h"
        }
    }
    
    /// Consumable name based on pump type
    public var consumableName: String {
        switch pumpType {
        case .omnipodDash, .omnipodEros:
            return "Pod"
        case .medtronic:
            return "Reservoir"
        case .tandemX2:
            return "Cartridge"
        case .danaRS, .danaI:
            return "Reservoir"
        case .simulation:
            return "Simulated"
        }
    }
}

// MARK: - Pump Consumable End Reason

/// Reason for consumable ending
public enum PumpConsumableEndReason: String, Sendable, Codable, CaseIterable {
    case expired = "expired"
    case empty = "empty"
    case userReplaced = "user_replaced"
    case occlusion = "occlusion"
    case podFault = "pod_fault"
    case siteFailure = "site_failure"
    case communication = "communication_lost"
    case unknown = "unknown"
    
    /// Human-readable description
    public var displayText: String {
        switch self {
        case .expired: return "Expired"
        case .empty: return "Empty"
        case .userReplaced: return "Replaced by user"
        case .occlusion: return "Occlusion detected"
        case .podFault: return "Pod fault"
        case .siteFailure: return "Site failure"
        case .communication: return "Communication lost"
        case .unknown: return "Unknown"
        }
    }
    
    /// Whether this represents an unexpected failure
    public var isFailure: Bool {
        switch self {
        case .occlusion, .podFault, .siteFailure, .communication:
            return true
        case .expired, .empty, .userReplaced, .unknown:
            return false
        }
    }
}

// MARK: - Pump History Summary

/// Summary statistics for pump consumable history
public struct PumpHistorySummary: Sendable {
    public let totalConsumables: Int
    public let averageDurationHours: Double
    public let averageInsulinDelivered: Double?
    public let failureRate: Double  // 0-1
    public let byPumpType: [PumpType: Int]
    public let byEndReason: [PumpConsumableEndReason: Int]
    
    public init(history: [PumpConsumableEntry]) {
        self.totalConsumables = history.count
        
        if history.isEmpty {
            self.averageDurationHours = 0
            self.averageInsulinDelivered = nil
            self.failureRate = 0
            self.byPumpType = [:]
            self.byEndReason = [:]
        } else {
            self.averageDurationHours = history.map(\.actualDurationHours).reduce(0, +) / Double(history.count)
            
            let insulinEntries = history.compactMap(\.insulinDelivered)
            if insulinEntries.isEmpty {
                self.averageInsulinDelivered = nil
            } else {
                self.averageInsulinDelivered = insulinEntries.reduce(0, +) / Double(insulinEntries.count)
            }
            
            let failures = history.filter { $0.endReason.isFailure }.count
            self.failureRate = Double(failures) / Double(history.count)
            
            var typeCount: [PumpType: Int] = [:]
            var reasonCount: [PumpConsumableEndReason: Int] = [:]
            for entry in history {
                typeCount[entry.pumpType, default: 0] += 1
                reasonCount[entry.endReason, default: 0] += 1
            }
            self.byPumpType = typeCount
            self.byEndReason = reasonCount
        }
    }
    
    /// Average duration formatted for display
    public var averageDurationText: String {
        let hours = Int(averageDurationHours)
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else {
            return "\(hours)h"
        }
    }
    
    /// Failure rate formatted as percentage
    public var failureRateText: String {
        String(format: "%.1f%%", failureRate * 100)
    }
}

// MARK: - Pump History Persistence Protocol

/// Protocol for persisting pump consumable history
public protocol PumpHistoryPersistence: Sendable {
    func saveEntry(_ entry: PumpConsumableEntry) async
    func loadHistory() async -> [PumpConsumableEntry]
    func clearHistory() async
}

// MARK: - In-Memory History Persistence

/// In-memory persistence for testing
public actor InMemoryPumpHistoryPersistence: PumpHistoryPersistence {
    private var history: [PumpConsumableEntry] = []
    
    public init() {}
    
    public func saveEntry(_ entry: PumpConsumableEntry) async {
        history.append(entry)
    }
    
    public func loadHistory() async -> [PumpConsumableEntry] {
        history.sorted { $0.deactivationDate > $1.deactivationDate }
    }
    
    public func clearHistory() async {
        history.removeAll()
    }
}

// MARK: - UserDefaults History Persistence

/// UserDefaults-based persistence for production
public actor UserDefaultsPumpHistoryPersistence: PumpHistoryPersistence {
    private let defaults: UserDefaults
    private let historyKey = "com.t1pal.pump.consumable.history"
    private let maxHistoryEntries: Int
    
    public init(defaults: UserDefaults = .standard, maxHistoryEntries: Int = 200) {
        self.defaults = defaults
        self.maxHistoryEntries = maxHistoryEntries
    }
    
    public func saveEntry(_ entry: PumpConsumableEntry) async {
        var history = await loadHistory()
        history.append(entry)
        
        // Keep only most recent entries
        if history.count > maxHistoryEntries {
            history = Array(history.sorted { $0.deactivationDate > $1.deactivationDate }.prefix(maxHistoryEntries))
        }
        
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }
    
    public func loadHistory() async -> [PumpConsumableEntry] {
        guard let data = defaults.data(forKey: historyKey) else { return [] }
        return (try? JSONDecoder().decode([PumpConsumableEntry].self, from: data)) ?? []
    }
    
    public func clearHistory() async {
        defaults.removeObject(forKey: historyKey)
    }
}

// MARK: - Pump History Manager

/// Manages pump consumable history logging (LIFE-PUMP-008)
public actor PumpHistoryManager {
    private let persistence: PumpHistoryPersistence
    
    public init(persistence: PumpHistoryPersistence = UserDefaultsPumpHistoryPersistence()) {
        self.persistence = persistence
    }
    
    // MARK: - Logging
    
    /// Log a completed consumable session
    public func logConsumable(_ entry: PumpConsumableEntry) async {
        await persistence.saveEntry(entry)
    }
    
    /// Log a consumable with explicit parameters
    public func logConsumable(
        pumpType: PumpType,
        activationDate: Date,
        deactivationDate: Date,
        plannedLifetimeHours: Int,
        endReason: PumpConsumableEndReason = .expired,
        insulinDelivered: Double? = nil,
        podLotNumber: String? = nil,
        serialNumber: String? = nil
    ) async {
        let entry = PumpConsumableEntry(
            pumpType: pumpType,
            activationDate: activationDate,
            deactivationDate: deactivationDate,
            plannedLifetimeHours: plannedLifetimeHours,
            endReason: endReason,
            insulinDelivered: insulinDelivered,
            podLotNumber: podLotNumber,
            serialNumber: serialNumber
        )
        await persistence.saveEntry(entry)
    }
    
    // MARK: - Retrieval
    
    /// Get full history
    public func getHistory() async -> [PumpConsumableEntry] {
        await persistence.loadHistory()
    }
    
    /// Get recent history (last N entries)
    public func getRecentHistory(limit: Int = 10) async -> [PumpConsumableEntry] {
        let history = await persistence.loadHistory()
        return Array(history.sorted { $0.deactivationDate > $1.deactivationDate }.prefix(limit))
    }
    
    /// Get history for a specific pump type
    public func getHistory(for pumpType: PumpType) async -> [PumpConsumableEntry] {
        let history = await persistence.loadHistory()
        return history.filter { $0.pumpType == pumpType }
    }
    
    /// Get history with specific end reason
    public func getHistory(endReason: PumpConsumableEndReason) async -> [PumpConsumableEntry] {
        let history = await persistence.loadHistory()
        return history.filter { $0.endReason == endReason }
    }
    
    /// Get failures only
    public func getFailures() async -> [PumpConsumableEntry] {
        let history = await persistence.loadHistory()
        return history.filter { $0.endReason.isFailure }
    }
    
    // MARK: - Statistics
    
    /// Get history summary
    public func getSummary() async -> PumpHistorySummary {
        let history = await persistence.loadHistory()
        return PumpHistorySummary(history: history)
    }
    
    /// Get summary for specific pump type
    public func getSummary(for pumpType: PumpType) async -> PumpHistorySummary {
        let history = await persistence.loadHistory()
        return PumpHistorySummary(history: history.filter { $0.pumpType == pumpType })
    }
    
    /// Get average duration for a pump type
    public func getAverageDuration(for pumpType: PumpType) async -> TimeInterval? {
        let history = await persistence.loadHistory()
        let typeHistory = history.filter { $0.pumpType == pumpType }
        guard !typeHistory.isEmpty else { return nil }
        let avgHours = typeHistory.map(\.actualDurationHours).reduce(0, +) / Double(typeHistory.count)
        return avgHours * 3600
    }
    
    /// Get failure rate for a pump type
    public func getFailureRate(for pumpType: PumpType) async -> Double? {
        let history = await persistence.loadHistory()
        let typeHistory = history.filter { $0.pumpType == pumpType }
        guard !typeHistory.isEmpty else { return nil }
        let failures = typeHistory.filter { $0.endReason.isFailure }.count
        return Double(failures) / Double(typeHistory.count)
    }
    
    // MARK: - Management
    
    /// Clear all history
    public func clearHistory() async {
        await persistence.clearHistory()
    }
    
    /// Get total consumable count
    public func getTotalCount() async -> Int {
        let history = await persistence.loadHistory()
        return history.count
    }
    
    /// Get total insulin delivered
    public func getTotalInsulinDelivered() async -> Double {
        let history = await persistence.loadHistory()
        return history.compactMap(\.insulinDelivered).reduce(0, +)
    }
}
