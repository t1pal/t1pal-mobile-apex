// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ProtocolLogger.swift - Shared protocol logging interface
// Part of BLEKit
// Trace: INSTR-001

import Foundation

// MARK: - Log Level

/// Severity level for log entries
public enum LogLevel: Int, Sendable, Codable, CaseIterable, Comparable {
    case trace = 0      // Detailed debugging information
    case debug = 1      // Debug information for development
    case info = 2       // General information
    case warning = 3    // Potential issues
    case error = 4      // Errors that don't prevent operation
    case critical = 5   // Critical errors requiring attention
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// String representation for display
    public var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRIT"
        }
    }
    
    /// Emoji representation for visual logs
    public var emoji: String {
        switch self {
        case .trace: return "🔍"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Log Category

/// Category for organizing log entries
public enum LogCategory: String, Sendable, Codable, CaseIterable {
    case connection     // Connection lifecycle events
    case authentication // Authentication/pairing events
    case data           // Data transfer events
    case command        // Command send/receive events
    case state          // State machine transitions
    case error          // Error conditions
    case performance    // Timing and performance metrics
    case bluetooth      // Low-level Bluetooth events
    case protocol_      // Protocol-specific events (renamed to avoid keyword)
    case system         // System-level events
    
    /// Display name
    public var displayName: String {
        switch self {
        case .protocol_: return "protocol"
        default: return rawValue
        }
    }
}

// MARK: - Log Entry

/// A single log entry with structured data
public struct LogEntry: Sendable, Codable, Equatable, Identifiable {
    /// Unique identifier
    public let id: String
    
    /// Timestamp when the log was created
    public let timestamp: Date
    
    /// Log level
    public let level: LogLevel
    
    /// Log category
    public let category: LogCategory
    
    /// Log message
    public let message: String
    
    /// Source file (optional)
    public let file: String?
    
    /// Source function (optional)
    public let function: String?
    
    /// Source line number (optional)
    public let line: Int?
    
    /// Associated metadata
    public let metadata: [String: String]
    
    /// Device identifier (anonymized)
    public let deviceId: String?
    
    /// Session identifier
    public let sessionId: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String? = nil,
        function: String? = nil,
        line: Int? = nil,
        metadata: [String: String] = [:],
        deviceId: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.function = function
        self.line = line
        self.metadata = metadata
        self.deviceId = deviceId
        self.sessionId = sessionId
    }
    
    /// Format as a single-line log string
    public func formatted(includeTimestamp: Bool = true, includeSource: Bool = false) -> String {
        var parts: [String] = []
        
        if includeTimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parts.append(formatter.string(from: timestamp))
        }
        
        parts.append("[\(level.label)]")
        parts.append("[\(category.displayName)]")
        parts.append(message)
        
        if includeSource, let file = file, let line = line {
            let filename = (file as NSString).lastPathComponent
            parts.append("(\(filename):\(line))")
        }
        
        return parts.joined(separator: " ")
    }
}

// MARK: - Protocol Logger

/// Protocol for structured logging across BLE protocols
public protocol ProtocolLogger: Sendable {
    /// Minimum log level to record
    var minimumLevel: LogLevel { get }
    
    /// Current session identifier
    var sessionId: String? { get }
    
    /// Log an entry
    func log(_ entry: LogEntry)
    
    /// Log with level, category, and message
    func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String],
        file: String,
        function: String,
        line: Int
    )
}

// MARK: - Default Implementation

extension ProtocolLogger {
    /// Convenience method for logging with source location
    public func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }
        
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata,
            sessionId: sessionId
        )
        log(entry)
    }
    
    // Convenience methods for each level
    
    public func trace(
        _ message: String,
        category: LogCategory = .protocol_,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .trace, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func debug(
        _ message: String,
        category: LogCategory = .protocol_,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func info(
        _ message: String,
        category: LogCategory = .protocol_,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func warning(
        _ message: String,
        category: LogCategory = .protocol_,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func error(
        _ message: String,
        category: LogCategory = .error,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func critical(
        _ message: String,
        category: LogCategory = .error,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }
}

// MARK: - Protocol Logger Delegate

/// Delegate for receiving log entries
public protocol ProtocolLoggerDelegate: AnyObject, Sendable {
    /// Called when a new log entry is recorded
    func logger(_ logger: any ProtocolLogger, didLog entry: LogEntry)
}

// MARK: - Standard Protocol Logger

/// Standard implementation of ProtocolLogger
public final class StandardProtocolLogger: ProtocolLogger, @unchecked Sendable {
    public let minimumLevel: LogLevel
    public let sessionId: String?
    
    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let maxEntries: Int
    private weak var delegate: (any ProtocolLoggerDelegate)?
    
    /// Print logs to console
    public let printToConsole: Bool
    
    public init(
        minimumLevel: LogLevel = .info,
        sessionId: String? = UUID().uuidString,
        maxEntries: Int = 1000,
        printToConsole: Bool = false,
        delegate: (any ProtocolLoggerDelegate)? = nil
    ) {
        self.minimumLevel = minimumLevel
        self.sessionId = sessionId
        self.maxEntries = maxEntries
        self.printToConsole = printToConsole
        self.delegate = delegate
    }
    
    public func log(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }
        
        lock.lock()
        entries.append(entry)
        
        // Trim old entries if needed
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
        
        if printToConsole {
            print(entry.formatted(includeTimestamp: true, includeSource: true))
        }
        
        delegate?.logger(self, didLog: entry)
    }
    
    /// Get all entries
    public func getEntries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    
    /// Get entries filtered by level
    public func getEntries(minLevel: LogLevel) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.level >= minLevel }
    }
    
    /// Get entries filtered by category
    public func getEntries(category: LogCategory) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.category == category }
    }
    
    /// Get entries within time range
    public func getEntries(from start: Date, to end: Date) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.timestamp >= start && $0.timestamp <= end }
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
    
    /// Export entries to JSON
    public func exportJSON() throws -> Data {
        lock.lock()
        let toExport = entries
        lock.unlock()
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(toExport)
    }
    
    /// Export entries to formatted string
    public func exportFormatted(includeTimestamp: Bool = true, includeSource: Bool = false) -> String {
        lock.lock()
        let toExport = entries
        lock.unlock()
        
        return toExport
            .map { $0.formatted(includeTimestamp: includeTimestamp, includeSource: includeSource) }
            .joined(separator: "\n")
    }
}

// MARK: - Composite Logger

/// Logger that forwards to multiple loggers
public final class CompositeProtocolLogger: ProtocolLogger, @unchecked Sendable {
    public let minimumLevel: LogLevel
    public let sessionId: String?
    
    private let lock = NSLock()
    private var loggers: [any ProtocolLogger]
    
    public init(
        loggers: [any ProtocolLogger],
        minimumLevel: LogLevel = .trace,
        sessionId: String? = nil
    ) {
        self.loggers = loggers
        self.minimumLevel = minimumLevel
        self.sessionId = sessionId
    }
    
    public func log(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }
        
        lock.lock()
        let currentLoggers = loggers
        lock.unlock()
        
        for logger in currentLoggers {
            logger.log(entry)
        }
    }
    
    /// Add a logger
    public func addLogger(_ logger: any ProtocolLogger) {
        lock.lock()
        loggers.append(logger)
        lock.unlock()
    }
    
    /// Remove all loggers
    public func removeAllLoggers() {
        lock.lock()
        loggers.removeAll()
        lock.unlock()
    }
}

// MARK: - Null Logger

/// Logger that discards all entries (for testing/production)
public struct NullProtocolLogger: ProtocolLogger {
    public let minimumLevel: LogLevel = .critical
    public let sessionId: String? = nil
    
    public init() {}
    
    public func log(_ entry: LogEntry) {
        // Discard
    }
}

// MARK: - Filtered Logger

/// Logger that filters entries before forwarding
public final class FilteredProtocolLogger: ProtocolLogger, @unchecked Sendable {
    public let minimumLevel: LogLevel
    public let sessionId: String?
    
    private let wrapped: any ProtocolLogger
    private let filter: @Sendable (LogEntry) -> Bool
    
    public init(
        wrapping logger: any ProtocolLogger,
        filter: @escaping @Sendable (LogEntry) -> Bool
    ) {
        self.wrapped = logger
        self.minimumLevel = logger.minimumLevel
        self.sessionId = logger.sessionId
        self.filter = filter
    }
    
    public func log(_ entry: LogEntry) {
        guard filter(entry) else { return }
        wrapped.log(entry)
    }
    
    /// Filter by categories
    public static func byCategories(
        _ categories: Set<LogCategory>,
        wrapping logger: any ProtocolLogger
    ) -> FilteredProtocolLogger {
        FilteredProtocolLogger(wrapping: logger) { entry in
            categories.contains(entry.category)
        }
    }
    
    /// Exclude categories
    public static func excludingCategories(
        _ categories: Set<LogCategory>,
        wrapping logger: any ProtocolLogger
    ) -> FilteredProtocolLogger {
        FilteredProtocolLogger(wrapping: logger) { entry in
            !categories.contains(entry.category)
        }
    }
    
    /// Filter by device
    public static func byDevice(
        _ deviceId: String,
        wrapping logger: any ProtocolLogger
    ) -> FilteredProtocolLogger {
        FilteredProtocolLogger(wrapping: logger) { entry in
            entry.deviceId == deviceId
        }
    }
}

// MARK: - Log Statistics

/// Statistics about logged entries
public struct LogStatistics: Sendable, Codable, Equatable {
    public let totalEntries: Int
    public let entriesByLevel: [LogLevel: Int]
    public let entriesByCategory: [LogCategory: Int]
    public let startTime: Date?
    public let endTime: Date?
    public let errorCount: Int
    public let warningCount: Int
    
    public init(
        totalEntries: Int,
        entriesByLevel: [LogLevel: Int],
        entriesByCategory: [LogCategory: Int],
        startTime: Date?,
        endTime: Date?,
        errorCount: Int,
        warningCount: Int
    ) {
        self.totalEntries = totalEntries
        self.entriesByLevel = entriesByLevel
        self.entriesByCategory = entriesByCategory
        self.startTime = startTime
        self.endTime = endTime
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
    
    /// Calculate statistics from entries
    public static func calculate(from entries: [LogEntry]) -> LogStatistics {
        var byLevel: [LogLevel: Int] = [:]
        var byCategory: [LogCategory: Int] = [:]
        var errorCount = 0
        var warningCount = 0
        
        for entry in entries {
            byLevel[entry.level, default: 0] += 1
            byCategory[entry.category, default: 0] += 1
            
            if entry.level == .error || entry.level == .critical {
                errorCount += 1
            }
            if entry.level == .warning {
                warningCount += 1
            }
        }
        
        let timestamps = entries.map { $0.timestamp }
        
        return LogStatistics(
            totalEntries: entries.count,
            entriesByLevel: byLevel,
            entriesByCategory: byCategory,
            startTime: timestamps.min(),
            endTime: timestamps.max(),
            errorCount: errorCount,
            warningCount: warningCount
        )
    }
}

// MARK: - Log Session

/// A logging session with metadata
public struct LogSession: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let startTime: Date
    public var endTime: Date?
    public let deviceType: String?
    public let deviceId: String?
    public let appVersion: String?
    public let platform: String?
    
    public init(
        id: String = UUID().uuidString,
        startTime: Date = Date(),
        endTime: Date? = nil,
        deviceType: String? = nil,
        deviceId: String? = nil,
        appVersion: String? = nil,
        platform: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.deviceType = deviceType
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.platform = platform
    }
    
    /// Duration of the session
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Whether the session is still active
    public var isActive: Bool {
        endTime == nil
    }
}

// MARK: - Protocol Log Report

/// A complete log report for sharing/analysis
public struct ProtocolLogReport: Sendable, Codable, Equatable {
    public let session: LogSession
    public let entries: [LogEntry]
    public let statistics: LogStatistics
    public let generatedAt: Date
    
    public init(
        session: LogSession,
        entries: [LogEntry],
        statistics: LogStatistics? = nil,
        generatedAt: Date = Date()
    ) {
        self.session = session
        self.entries = entries
        self.statistics = statistics ?? LogStatistics.calculate(from: entries)
        self.generatedAt = generatedAt
    }
    
    /// Export to JSON
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Create from JSON
    public static func fromJSON(_ data: Data) throws -> ProtocolLogReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProtocolLogReport.self, from: data)
    }
}

// MARK: - Log Builder

/// Builder for constructing log entries with fluent API
public struct LogEntryBuilder: Sendable {
    private var level: LogLevel = .info
    private var category: LogCategory = .protocol_
    private var message: String = ""
    private var metadata: [String: String] = [:]
    private var deviceId: String?
    private var sessionId: String?
    
    public init() {}
    
    public func level(_ level: LogLevel) -> LogEntryBuilder {
        var copy = self
        copy.level = level
        return copy
    }
    
    public func category(_ category: LogCategory) -> LogEntryBuilder {
        var copy = self
        copy.category = category
        return copy
    }
    
    public func message(_ message: String) -> LogEntryBuilder {
        var copy = self
        copy.message = message
        return copy
    }
    
    public func metadata(_ key: String, _ value: String) -> LogEntryBuilder {
        var copy = self
        copy.metadata[key] = value
        return copy
    }
    
    public func deviceId(_ id: String) -> LogEntryBuilder {
        var copy = self
        copy.deviceId = id
        return copy
    }
    
    public func sessionId(_ id: String) -> LogEntryBuilder {
        var copy = self
        copy.sessionId = id
        return copy
    }
    
    public func build(
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> LogEntry {
        LogEntry(
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata,
            deviceId: deviceId,
            sessionId: sessionId
        )
    }
}
