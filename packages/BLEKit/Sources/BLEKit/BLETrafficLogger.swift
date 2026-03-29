// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLETrafficLogger.swift
// BLEKit
//
// Captures and logs BLE traffic for debugging and analysis.
// Supports filtering, export, and replay functionality.
// Trace: PRD-007 REQ-SIM-008

import Foundation

// MARK: - Traffic Direction

/// Direction of BLE traffic
public enum TrafficDirection: String, Sendable, Codable {
    /// Data sent from central to peripheral (write)
    case outgoing
    
    /// Data received from peripheral to central (notify/read)
    case incoming
}

// MARK: - Traffic Entry

/// A single BLE traffic log entry
public struct TrafficEntry: Sendable, Codable, Identifiable {
    /// Unique identifier
    public let id: UUID
    
    /// Timestamp of the traffic
    public let timestamp: Date
    
    /// Direction of traffic
    public let direction: TrafficDirection
    
    /// Opcode (first byte of data)
    public let opcode: UInt8
    
    /// Full packet data
    public let data: Data
    
    /// Optional characteristic UUID
    public let characteristic: String?
    
    /// Optional service UUID
    public let service: String?
    
    /// Optional note or description
    public var note: String?
    
    /// Create a traffic entry
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: TrafficDirection,
        data: Data,
        characteristic: String? = nil,
        service: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.opcode = data.first ?? 0
        self.data = data
        self.characteristic = characteristic
        self.service = service
        self.note = note
    }
    
    /// Data as hex string
    public var hexString: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Packet size in bytes
    public var size: Int {
        data.count
    }
    
    /// Short description for logging
    public var shortDescription: String {
        let dir = direction == .outgoing ? "→" : "←"
        let opcodeStr = String(format: "0x%02X", opcode)
        return "\(dir) [\(opcodeStr)] \(size) bytes"
    }
}

// MARK: - Traffic Filter

/// Filter criteria for traffic entries
public struct TrafficFilter: Sendable {
    /// Filter by direction
    public var direction: TrafficDirection?
    
    /// Filter by opcodes (include only these)
    public var opcodes: Set<UInt8>?
    
    /// Exclude these opcodes
    public var excludeOpcodes: Set<UInt8>?
    
    /// Filter by time range start
    public var startTime: Date?
    
    /// Filter by time range end
    public var endTime: Date?
    
    /// Filter by characteristic UUID
    public var characteristic: String?
    
    /// Filter by service UUID
    public var service: String?
    
    /// Minimum data size
    public var minSize: Int?
    
    /// Maximum data size
    public var maxSize: Int?
    
    /// Create an empty filter (matches all)
    public init() {}
    
    /// Create a filter for specific direction
    public static func direction(_ dir: TrafficDirection) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.direction = dir
        return filter
    }
    
    /// Create a filter for specific opcodes
    public static func opcodes(_ codes: UInt8...) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.opcodes = Set(codes)
        return filter
    }
    
    /// Create a filter for time range
    public static func timeRange(start: Date, end: Date) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.startTime = start
        filter.endTime = end
        return filter
    }
    
    /// Check if an entry matches this filter
    public func matches(_ entry: TrafficEntry) -> Bool {
        // Direction filter
        if let dir = direction, entry.direction != dir {
            return false
        }
        
        // Opcode include filter
        if let codes = opcodes, !codes.contains(entry.opcode) {
            return false
        }
        
        // Opcode exclude filter
        if let exclude = excludeOpcodes, exclude.contains(entry.opcode) {
            return false
        }
        
        // Time range filter
        if let start = startTime, entry.timestamp < start {
            return false
        }
        if let end = endTime, entry.timestamp > end {
            return false
        }
        
        // Characteristic filter
        if let char = characteristic, entry.characteristic != char {
            return false
        }
        
        // Service filter
        if let svc = service, entry.service != svc {
            return false
        }
        
        // Size filters
        if let min = minSize, entry.size < min {
            return false
        }
        if let max = maxSize, entry.size > max {
            return false
        }
        
        return true
    }
}

// MARK: - Export Format

/// Export format for traffic logs
public enum TrafficExportFormat: String, Sendable {
    /// JSON format with full metadata
    case json
    
    /// Hex dump format (one line per packet)
    case hexDump
    
    /// CSV format
    case csv
    
    /// Wireshark-compatible pcap (simplified)
    case pcapText
}

// MARK: - Traffic Statistics

/// Statistics about captured traffic
public struct TrafficStatistics: Sendable {
    /// Total number of entries
    public let totalEntries: Int
    
    /// Number of outgoing packets
    public let outgoingCount: Int
    
    /// Number of incoming packets
    public let incomingCount: Int
    
    /// Total bytes sent
    public let bytesSent: Int
    
    /// Total bytes received
    public let bytesReceived: Int
    
    /// Unique opcodes seen
    public let uniqueOpcodes: Set<UInt8>
    
    /// First entry timestamp
    public let firstTimestamp: Date?
    
    /// Last entry timestamp
    public let lastTimestamp: Date?
    
    /// Duration of capture
    public var duration: TimeInterval {
        guard let first = firstTimestamp, let last = lastTimestamp else {
            return 0
        }
        return last.timeIntervalSince(first)
    }
    
    /// Average packet size
    public var averagePacketSize: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(bytesSent + bytesReceived) / Double(totalEntries)
    }
}

// MARK: - BLE Traffic Logger

/// Captures and manages BLE traffic logs for debugging
///
/// ## Usage
/// ```swift
/// let logger = BLETrafficLogger()
///
/// // Log packets
/// logger.log(direction: .outgoing, data: commandData)
/// logger.log(direction: .incoming, data: responseData)
///
/// // Filter entries
/// let outgoing = logger.filter(.direction(.outgoing))
/// let authPackets = logger.filter(.opcodes(0x01, 0x04, 0x05, 0x06))
///
/// // Export
/// let json = logger.export(format: .json)
/// let hexDump = logger.export(format: .hexDump)
/// ```
public final class BLETrafficLogger: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// All logged entries
    public private(set) var entries: [TrafficEntry] = []
    
    /// Maximum entries to keep (0 = unlimited)
    public var maxEntries: Int = 0
    
    /// Whether logging is enabled
    public var isEnabled: Bool = true
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Create a traffic logger
    /// - Parameter maxEntries: Maximum entries to keep (0 = unlimited)
    public init(maxEntries: Int = 0) {
        self.maxEntries = maxEntries
    }
    
    // MARK: - Logging
    
    /// Log a traffic entry
    /// - Parameters:
    ///   - direction: Direction of traffic
    ///   - data: Packet data
    ///   - characteristic: Optional characteristic UUID
    ///   - service: Optional service UUID
    ///   - note: Optional note
    /// - Returns: The created entry (or nil if logging disabled)
    @discardableResult
    public func log(
        direction: TrafficDirection,
        data: Data,
        characteristic: String? = nil,
        service: String? = nil,
        note: String? = nil
    ) -> TrafficEntry? {
        guard isEnabled, !data.isEmpty else { return nil }
        
        let entry = TrafficEntry(
            direction: direction,
            data: data,
            characteristic: characteristic,
            service: service,
            note: note
        )
        
        lock.lock()
        defer { lock.unlock() }
        
        entries.append(entry)
        
        // Trim if needed
        if maxEntries > 0 && entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        return entry
    }
    
    /// Log outgoing data (convenience)
    @discardableResult
    public func logOutgoing(_ data: Data, note: String? = nil) -> TrafficEntry? {
        log(direction: .outgoing, data: data, note: note)
    }
    
    /// Log incoming data (convenience)
    @discardableResult
    public func logIncoming(_ data: Data, note: String? = nil) -> TrafficEntry? {
        log(direction: .incoming, data: data, note: note)
    }
    
    // MARK: - Filtering
    
    /// Filter entries by criteria
    /// - Parameter filter: Filter criteria
    /// - Returns: Matching entries
    public func filter(_ filter: TrafficFilter) -> [TrafficEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        return entries.filter { filter.matches($0) }
    }
    
    /// Get entries by direction
    public func entries(direction: TrafficDirection) -> [TrafficEntry] {
        filter(.direction(direction))
    }
    
    /// Get entries by opcode
    public func entries(opcode: UInt8) -> [TrafficEntry] {
        filter(.opcodes(opcode))
    }
    
    /// Get entries in time range
    public func entries(from start: Date, to end: Date) -> [TrafficEntry] {
        filter(.timeRange(start: start, end: end))
    }
    
    // MARK: - Statistics
    
    /// Get traffic statistics
    public var statistics: TrafficStatistics {
        lock.lock()
        defer { lock.unlock() }
        
        var outCount = 0
        var inCount = 0
        var bytesSent = 0
        var bytesReceived = 0
        var opcodes = Set<UInt8>()
        
        for entry in entries {
            opcodes.insert(entry.opcode)
            
            if entry.direction == .outgoing {
                outCount += 1
                bytesSent += entry.size
            } else {
                inCount += 1
                bytesReceived += entry.size
            }
        }
        
        return TrafficStatistics(
            totalEntries: entries.count,
            outgoingCount: outCount,
            incomingCount: inCount,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            uniqueOpcodes: opcodes,
            firstTimestamp: entries.first?.timestamp,
            lastTimestamp: entries.last?.timestamp
        )
    }
    
    // MARK: - Export
    
    /// Export traffic log in specified format
    /// - Parameters:
    ///   - format: Export format
    ///   - filter: Optional filter to apply
    /// - Returns: Exported string
    public func export(format: TrafficExportFormat, filter: TrafficFilter? = nil) -> String {
        lock.lock()
        let entriesToExport = filter.map { f in entries.filter { f.matches($0) } } ?? entries
        lock.unlock()
        
        switch format {
        case .json:
            return exportJSON(entriesToExport)
        case .hexDump:
            return exportHexDump(entriesToExport)
        case .csv:
            return exportCSV(entriesToExport)
        case .pcapText:
            return exportPcapText(entriesToExport)
        }
    }
    
    private func exportJSON(_ entries: [TrafficEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(entries),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
    
    private func exportHexDump(_ entries: [TrafficEntry]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        var lines: [String] = []
        for entry in entries {
            let time = dateFormatter.string(from: entry.timestamp)
            let dir = entry.direction == .outgoing ? "TX" : "RX"
            let hex = entry.hexString
            lines.append("[\(time)] \(dir): \(hex)")
        }
        return lines.joined(separator: "\n")
    }
    
    private func exportCSV(_ entries: [TrafficEntry]) -> String {
        var lines = ["timestamp,direction,opcode,size,data"]
        
        let dateFormatter = ISO8601DateFormatter()
        
        for entry in entries {
            let time = dateFormatter.string(from: entry.timestamp)
            let dir = entry.direction.rawValue
            let opcode = String(format: "0x%02X", entry.opcode)
            let size = entry.size
            let hex = entry.hexString
            lines.append("\(time),\(dir),\(opcode),\(size),\"\(hex)\"")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func exportPcapText(_ entries: [TrafficEntry]) -> String {
        var lines: [String] = []
        lines.append("# BLE Traffic Capture")
        lines.append("# Generated by BLEKit")
        lines.append("")
        
        for (index, entry) in entries.enumerated() {
            let dir = entry.direction == .outgoing ? "Central -> Peripheral" : "Peripheral -> Central"
            lines.append("Frame \(index + 1): \(entry.size) bytes on wire")
            lines.append("    \(dir)")
            lines.append("    Data: \(entry.hexString)")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Management
    
    /// Clear all logged entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
    
    /// Replace all entries with new entries
    /// - Parameter newEntries: Entries to replace with
    public func replaceEntries(_ newEntries: [TrafficEntry]) {
        lock.lock()
        defer { lock.unlock() }
        
        entries = newEntries
        
        // Trim if needed
        if maxEntries > 0 && entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
    }
    
    /// Append entries
    /// - Parameter newEntries: Entries to append
    public func appendEntries(_ newEntries: [TrafficEntry]) {
        lock.lock()
        defer { lock.unlock() }
        
        entries.append(contentsOf: newEntries)
        entries.sort { $0.timestamp < $1.timestamp }
        
        // Trim if needed
        if maxEntries > 0 && entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
    }
    
    /// Number of logged entries
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
    
    /// Get all entries (thread-safe copy)
    public func allEntries() -> [TrafficEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    
    /// Get the last N entries
    public func lastEntries(_ count: Int) -> [TrafficEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(count))
    }
    
    /// Find entries matching a data pattern
    public func find(containing pattern: Data) -> [TrafficEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        return entries.filter { entry in
            if pattern.count > entry.data.count { return false }
            for i in 0...(entry.data.count - pattern.count) {
                if entry.data[i..<(i + pattern.count)] == pattern {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Logger Session

/// A capture session with start/stop semantics
public struct LoggerSession: Sendable {
    /// Session ID
    public let id: UUID
    
    /// Start time
    public let startTime: Date
    
    /// End time (nil if still running)
    public var endTime: Date?
    
    /// Session name
    public let name: String
    
    /// Captured entries
    public var entries: [TrafficEntry]
    
    /// Session duration
    public var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    public init(name: String = "Session") {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.name = name
        self.entries = []
    }
}

extension BLETrafficLogger {
    /// Start a new capture session
    public func startSession(name: String = "Session") -> LoggerSession {
        clear()
        return LoggerSession(name: name)
    }
    
    /// End a session and return it with captured entries
    public func endSession(_ session: inout LoggerSession) {
        lock.lock()
        session.entries = entries
        lock.unlock()
        session.endTime = Date()
    }
}
