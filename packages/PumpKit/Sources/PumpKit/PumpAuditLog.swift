// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpAuditLog.swift
// T1Pal Mobile
//
// Audit logging for pump commands
// Requirements: CLI-SIM-003, REQ-AID-006

import Foundation

// MARK: - Audit Entry Types

/// A single pump command audit entry
public struct PumpAuditEntry: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let command: AuditCommand
    public let success: Bool
    public let errorMessage: String?
    public let context: [String: String]?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        command: AuditCommand,
        success: Bool,
        errorMessage: String? = nil,
        context: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.command = command
        self.success = success
        self.errorMessage = errorMessage
        self.context = context
    }
}

/// Audit command types for pump logging
public enum AuditCommand: Sendable, Equatable {
    case connect
    case disconnect
    case setTempBasal(rate: Double, durationMinutes: Double)
    case cancelTempBasal
    case deliverBolus(units: Double)
    case suspend
    case resume
    case activatePod(podId: String)
    case deactivatePod(podId: String)
    case pairPump(pumpId: String, model: String)
    case unpairPump(pumpId: String)
    
    public var description: String {
        switch self {
        case .connect: return "Connect"
        case .disconnect: return "Disconnect"
        case .setTempBasal(let rate, let duration):
            return "Set temp basal \(String(format: "%.2f", rate)) U/hr for \(Int(duration)) min"
        case .cancelTempBasal: return "Cancel temp basal"
        case .deliverBolus(let units):
            return "Deliver bolus \(String(format: "%.2f", units)) U"
        case .suspend: return "Suspend"
        case .resume: return "Resume"
        case .activatePod(let podId): return "Activate pod \(podId)"
        case .deactivatePod(let podId): return "Deactivate pod \(podId)"
        case .pairPump(let pumpId, let model): return "Pair pump \(pumpId) (\(model))"
        case .unpairPump(let pumpId): return "Unpair pump \(pumpId)"
        }
    }
    
    /// Command type name for serialization
    public var typeName: String {
        switch self {
        case .connect: return "connect"
        case .disconnect: return "disconnect"
        case .setTempBasal: return "setTempBasal"
        case .cancelTempBasal: return "cancelTempBasal"
        case .deliverBolus: return "deliverBolus"
        case .suspend: return "suspend"
        case .resume: return "resume"
        case .activatePod: return "activatePod"
        case .deactivatePod: return "deactivatePod"
        case .pairPump: return "pairPump"
        case .unpairPump: return "unpairPump"
        }
    }
}

// MARK: - AuditCommand Codable

extension AuditCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, rate, durationMinutes, units, podId, pumpId, model
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "connect": self = .connect
        case "disconnect": self = .disconnect
        case "setTempBasal":
            let rate = try container.decode(Double.self, forKey: .rate)
            let duration = try container.decode(Double.self, forKey: .durationMinutes)
            self = .setTempBasal(rate: rate, durationMinutes: duration)
        case "cancelTempBasal": self = .cancelTempBasal
        case "deliverBolus":
            let units = try container.decode(Double.self, forKey: .units)
            self = .deliverBolus(units: units)
        case "suspend": self = .suspend
        case "resume": self = .resume
        case "activatePod":
            let podId = try container.decode(String.self, forKey: .podId)
            self = .activatePod(podId: podId)
        case "deactivatePod":
            let podId = try container.decode(String.self, forKey: .podId)
            self = .deactivatePod(podId: podId)
        case "pairPump":
            let pumpId = try container.decode(String.self, forKey: .pumpId)
            let model = try container.decode(String.self, forKey: .model)
            self = .pairPump(pumpId: pumpId, model: model)
        case "unpairPump":
            let pumpId = try container.decode(String.self, forKey: .pumpId)
            self = .unpairPump(pumpId: pumpId)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown command type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        
        switch self {
        case .setTempBasal(let rate, let durationMinutes):
            try container.encode(rate, forKey: .rate)
            try container.encode(durationMinutes, forKey: .durationMinutes)
        case .deliverBolus(let units):
            try container.encode(units, forKey: .units)
        case .activatePod(let podId), .deactivatePod(let podId):
            try container.encode(podId, forKey: .podId)
        case .pairPump(let pumpId, let model):
            try container.encode(pumpId, forKey: .pumpId)
            try container.encode(model, forKey: .model)
        case .unpairPump(let pumpId):
            try container.encode(pumpId, forKey: .pumpId)
        default:
            break
        }
    }
}

// MARK: - Audit Log

/// Thread-safe audit log for pump commands
/// Requirements: CLI-SIM-003
public actor PumpAuditLog {
    private var entries: [PumpAuditEntry] = []
    private let maxEntries: Int
    
    public init(maxEntries: Int = 10000) {
        self.maxEntries = maxEntries
    }
    
    /// Record a successful command
    public func record(
        _ command: AuditCommand,
        context: [String: String]? = nil
    ) {
        let entry = PumpAuditEntry(
            command: command,
            success: true,
            context: context
        )
        append(entry)
    }
    
    /// Record a failed command
    public func recordFailure(
        _ command: AuditCommand,
        error: String,
        context: [String: String]? = nil
    ) {
        let entry = PumpAuditEntry(
            command: command,
            success: false,
            errorMessage: error,
            context: context
        )
        append(entry)
    }
    
    /// Get all entries
    public func allEntries() -> [PumpAuditEntry] {
        entries
    }
    
    /// Get entries within a time range
    public func entries(from start: Date, to end: Date) -> [PumpAuditEntry] {
        entries.filter { $0.timestamp >= start && $0.timestamp <= end }
    }
    
    /// Get entries for a specific command type
    public func entries(matching predicate: @Sendable (AuditCommand) -> Bool) -> [PumpAuditEntry] {
        entries.filter { predicate($0.command) }
    }
    
    /// Count of entries
    public var count: Int { entries.count }
    
    /// Count of successful entries
    public var successCount: Int {
        entries.filter(\.success).count
    }
    
    /// Count of failed entries
    public var failureCount: Int {
        entries.filter { !$0.success }.count
    }
    
    /// Clear all entries
    public func clear() {
        entries.removeAll()
    }
    
    /// Export to JSON data
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
    
    /// Export to JSON string
    public func exportJSONString() throws -> String {
        let data = try exportJSON()
        guard let string = String(data: data, encoding: .utf8) else {
            throw AuditLogError.encodingFailed
        }
        return string
    }
    
    /// Write to file
    public func writeToFile(_ path: String) throws {
        let data = try exportJSON()
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }
    
    /// Summary statistics
    public func summary() -> AuditSummary {
        var tempBasalCount = 0
        var bolusCount = 0
        var totalBolusUnits = 0.0
        var suspendCount = 0
        
        for entry in entries where entry.success {
            switch entry.command {
            case .setTempBasal:
                tempBasalCount += 1
            case .deliverBolus(let units):
                bolusCount += 1
                totalBolusUnits += units
            case .suspend:
                suspendCount += 1
            default:
                break
            }
        }
        
        return AuditSummary(
            totalCommands: entries.count,
            successfulCommands: successCount,
            failedCommands: failureCount,
            tempBasalAdjustments: tempBasalCount,
            bolusDeliveries: bolusCount,
            totalBolusUnits: totalBolusUnits,
            suspendEvents: suspendCount,
            startTime: entries.first?.timestamp,
            endTime: entries.last?.timestamp
        )
    }
    
    // MARK: - Private
    
    private func append(_ entry: PumpAuditEntry) {
        entries.append(entry)
        
        // Trim if exceeds max
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

// MARK: - Supporting Types

/// Summary of audit log statistics
public struct AuditSummary: Sendable {
    public let totalCommands: Int
    public let successfulCommands: Int
    public let failedCommands: Int
    public let tempBasalAdjustments: Int
    public let bolusDeliveries: Int
    public let totalBolusUnits: Double
    public let suspendEvents: Int
    public let startTime: Date?
    public let endTime: Date?
    
    public var successRate: Double {
        guard totalCommands > 0 else { return 0 }
        return Double(successfulCommands) / Double(totalCommands)
    }
    
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

/// Audit log errors
public enum AuditLogError: Error, Sendable {
    case encodingFailed
    case writeFailed(String)
}
