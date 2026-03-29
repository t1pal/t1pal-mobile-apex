// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpProtocolLogger.swift
// PumpKit
//
// Byte-level protocol logging for pump debugging and analysis.
// Captures raw TX/RX bytes with timestamps for protocol decoding.
// Trace: PUMP-INFRA-001, PRD-005
//
// Usage:
//   let logger = PumpProtocolLogger()
//   logger.log(direction: .tx, bytes: commandBytes, context: "SetTempBasal")
//   logger.log(direction: .rx, bytes: responseBytes, context: "ACK")
//   let export = logger.exportSession()  // JSON for sharing

import Foundation

// MARK: - Protocol Direction

/// Direction of protocol message
public enum ProtocolDirection: String, Codable, Sendable {
    case tx = "TX"
    case rx = "RX"
}

// MARK: - Protocol Entry

/// Single protocol log entry with byte data
public struct ProtocolLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let direction: ProtocolDirection
    public let bytes: Data
    public let hexString: String
    public let context: String
    public let sequenceNumber: Int
    public let elapsedMs: Double
    
    init(
        direction: ProtocolDirection,
        bytes: Data,
        context: String,
        sequenceNumber: Int,
        elapsedMs: Double
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.direction = direction
        self.bytes = bytes
        self.hexString = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        self.context = context
        self.sequenceNumber = sequenceNumber
        self.elapsedMs = elapsedMs
    }
    
    /// Formatted single-line representation
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let dir = direction.rawValue
        return "[\(ms)ms] \(dir) [\(bytes.count) bytes] \(hexString) // \(context)"
    }
}

// MARK: - Session Metadata

/// Metadata for a protocol logging session
public struct ProtocolSessionMetadata: Codable, Sendable {
    public let sessionId: UUID
    public let startTime: Date
    public let pumpType: String
    public let pumpId: String
    public let deviceInfo: String
    
    public init(
        pumpType: String,
        pumpId: String,
        deviceInfo: String = ""
    ) {
        self.sessionId = UUID()
        self.startTime = Date()
        self.pumpType = pumpType
        self.pumpId = pumpId
        self.deviceInfo = deviceInfo
    }
}

// MARK: - Session Export

/// Complete session export for sharing/analysis
public struct ProtocolSessionExport: Codable, Sendable {
    public let metadata: ProtocolSessionMetadata
    public let entries: [ProtocolLogEntry]
    public let endTime: Date
    public let entryCount: Int
    public let totalBytes: Int
    
    public init(metadata: ProtocolSessionMetadata, entries: [ProtocolLogEntry]) {
        self.metadata = metadata
        self.entries = entries
        self.endTime = Date()
        self.entryCount = entries.count
        self.totalBytes = entries.reduce(0) { $0 + $1.bytes.count }
    }
    
    /// Export as formatted text (human-readable)
    public func asText() -> String {
        var lines: [String] = []
        lines.append("=== Pump Protocol Session ===")
        lines.append("Session ID: \(metadata.sessionId.uuidString)")
        lines.append("Pump: \(metadata.pumpType) [\(metadata.pumpId)]")
        lines.append("Started: \(ISO8601DateFormatter().string(from: metadata.startTime))")
        lines.append("Ended: \(ISO8601DateFormatter().string(from: endTime))")
        lines.append("Entries: \(entryCount), Total: \(totalBytes) bytes")
        lines.append("")
        lines.append("--- Protocol Trace ---")
        for entry in entries {
            lines.append(entry.formatted)
        }
        lines.append("--- End Trace ---")
        return lines.joined(separator: "\n")
    }
    
    /// Export as JSON data
    public func asJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Protocol Logger

/// Thread-safe byte-level protocol logger
public final class PumpProtocolLogger: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ProtocolLogEntry] = []
    private var sequenceCounter: Int = 0
    private let startTime: Date
    private let metadata: ProtocolSessionMetadata
    private let maxEntries: Int
    
    /// Whether logging is enabled (can be disabled for production)
    public var isEnabled: Bool = true
    
    /// Initialize with session metadata
    public init(
        pumpType: String,
        pumpId: String,
        deviceInfo: String = "",
        maxEntries: Int = 10000
    ) {
        self.metadata = ProtocolSessionMetadata(
            pumpType: pumpType,
            pumpId: pumpId,
            deviceInfo: deviceInfo
        )
        self.startTime = Date()
        self.maxEntries = maxEntries
    }
    
    /// Log a protocol message
    public func log(direction: ProtocolDirection, bytes: Data, context: String = "") {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000  // ms
        sequenceCounter += 1
        
        let entry = ProtocolLogEntry(
            direction: direction,
            bytes: bytes,
            context: context,
            sequenceNumber: sequenceCounter,
            elapsedMs: elapsed
        )
        
        entries.append(entry)
        
        // Trim if over max (keep recent entries)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // Also log to console in debug builds
        #if DEBUG
        print("[PumpProtocol] \(entry.formatted)")
        #endif
    }
    
    /// Log TX bytes
    public func tx(_ bytes: Data, context: String = "") {
        log(direction: .tx, bytes: bytes, context: context)
    }
    
    /// Log TX from byte array
    public func tx(_ bytes: [UInt8], context: String = "") {
        log(direction: .tx, bytes: Data(bytes), context: context)
    }
    
    /// Log RX bytes
    public func rx(_ bytes: Data, context: String = "") {
        log(direction: .rx, bytes: bytes, context: context)
    }
    
    /// Log RX from byte array
    public func rx(_ bytes: [UInt8], context: String = "") {
        log(direction: .rx, bytes: Data(bytes), context: context)
    }
    
    /// Get current entry count
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
    
    /// Get all entries
    public func getEntries() -> [ProtocolLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    
    /// Export session
    public func exportSession() -> ProtocolSessionExport {
        lock.lock()
        defer { lock.unlock() }
        return ProtocolSessionExport(metadata: metadata, entries: entries)
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        sequenceCounter = 0
    }
}

// MARK: - Singleton for Shared Logging

/// Shared protocol logger registry
public final class PumpProtocolLoggerRegistry: @unchecked Sendable {
    public static let shared = PumpProtocolLoggerRegistry()
    
    private let lock = NSLock()
    private var loggers: [String: PumpProtocolLogger] = [:]
    
    private init() {}
    
    /// Get or create logger for pump
    public func logger(for pumpId: String, pumpType: String) -> PumpProtocolLogger {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = loggers[pumpId] {
            return existing
        }
        
        let logger = PumpProtocolLogger(pumpType: pumpType, pumpId: pumpId)
        loggers[pumpId] = logger
        return logger
    }
    
    /// Export all sessions
    public func exportAll() -> [ProtocolSessionExport] {
        lock.lock()
        defer { lock.unlock() }
        return loggers.values.map { $0.exportSession() }
    }
    
    /// Clear all loggers
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        loggers.values.forEach { $0.clear() }
    }
}
