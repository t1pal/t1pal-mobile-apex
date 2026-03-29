// ProtocolLoggerTests.swift - Tests for protocol logging interface
// Part of BLEKit
// Trace: INSTR-001

import Foundation
import Testing
@testable import BLEKit

// MARK: - Log Level Tests

@Suite("Log Level")
struct LogLevelTests {
    @Test("All levels available")
    func allLevelsAvailable() {
        let levels = LogLevel.allCases
        #expect(levels.count == 6)
    }
    
    @Test("Level ordering")
    func levelOrdering() {
        #expect(LogLevel.trace < LogLevel.debug)
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.warning)
        #expect(LogLevel.warning < LogLevel.error)
        #expect(LogLevel.error < LogLevel.critical)
    }
    
    @Test("Level labels")
    func levelLabels() {
        #expect(LogLevel.trace.label == "TRACE")
        #expect(LogLevel.debug.label == "DEBUG")
        #expect(LogLevel.info.label == "INFO")
        #expect(LogLevel.warning.label == "WARN")
        #expect(LogLevel.error.label == "ERROR")
        #expect(LogLevel.critical.label == "CRIT")
    }
    
    @Test("Level emojis")
    func levelEmojis() {
        #expect(LogLevel.trace.emoji == "🔍")
        #expect(LogLevel.error.emoji == "❌")
        #expect(LogLevel.critical.emoji == "🚨")
    }
    
    @Test("Level is Codable")
    func levelCodable() throws {
        let level = LogLevel.warning
        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(LogLevel.self, from: data)
        #expect(decoded == level)
    }
}

// MARK: - Log Category Tests

@Suite("Log Category")
struct LogCategoryTests {
    @Test("All categories available")
    func allCategoriesAvailable() {
        let categories = LogCategory.allCases
        #expect(categories.count == 10)
    }
    
    @Test("Category display names")
    func categoryDisplayNames() {
        #expect(LogCategory.connection.displayName == "connection")
        #expect(LogCategory.protocol_.displayName == "protocol")
        #expect(LogCategory.bluetooth.displayName == "bluetooth")
    }
    
    @Test("Category is Codable")
    func categoryCodable() throws {
        let category = LogCategory.authentication
        let data = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(LogCategory.self, from: data)
        #expect(decoded == category)
    }
}

// MARK: - Log Entry Tests

@Suite("Log Entry")
struct LogEntryTests {
    @Test("Create log entry")
    func createLogEntry() {
        let entry = LogEntry(
            level: .info,
            category: .connection,
            message: "Connected to device"
        )
        
        #expect(entry.level == .info)
        #expect(entry.category == .connection)
        #expect(entry.message == "Connected to device")
    }
    
    @Test("Entry with metadata")
    func entryWithMetadata() {
        let entry = LogEntry(
            level: .debug,
            category: .data,
            message: "Received data",
            metadata: ["bytes": "128", "type": "glucose"]
        )
        
        #expect(entry.metadata["bytes"] == "128")
        #expect(entry.metadata["type"] == "glucose")
    }
    
    @Test("Entry with source location")
    func entryWithSourceLocation() {
        let entry = LogEntry(
            level: .error,
            category: .error,
            message: "Connection failed",
            file: "ConnectionManager.swift",
            function: "connect()",
            line: 42
        )
        
        #expect(entry.file == "ConnectionManager.swift")
        #expect(entry.function == "connect()")
        #expect(entry.line == 42)
    }
    
    @Test("Entry formatted output")
    func entryFormattedOutput() {
        let entry = LogEntry(
            level: .info,
            category: .connection,
            message: "Connected"
        )
        
        let formatted = entry.formatted(includeTimestamp: false)
        #expect(formatted.contains("[INFO]"))
        #expect(formatted.contains("[connection]"))
        #expect(formatted.contains("Connected"))
    }
    
    @Test("Entry formatted with source")
    func entryFormattedWithSource() {
        let entry = LogEntry(
            level: .error,
            category: .error,
            message: "Failed",
            file: "/path/to/File.swift",
            line: 100
        )
        
        let formatted = entry.formatted(includeTimestamp: false, includeSource: true)
        #expect(formatted.contains("(File.swift:100)"))
    }
    
    @Test("Entry is Codable")
    func entryCodable() throws {
        let entry = LogEntry(
            level: .warning,
            category: .authentication,
            message: "Auth timeout",
            metadata: ["attempt": "3"],
            deviceId: "device123",
            sessionId: "session456"
        )
        
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)
        #expect(decoded == entry)
    }
    
    @Test("Entry is Identifiable")
    func entryIdentifiable() {
        let entry1 = LogEntry(level: .info, category: .data, message: "Test 1")
        let entry2 = LogEntry(level: .info, category: .data, message: "Test 2")
        
        #expect(entry1.id != entry2.id)
    }
}

// MARK: - Standard Protocol Logger Tests

@Suite("Standard Protocol Logger")
struct StandardProtocolLoggerTests {
    @Test("Create logger")
    func createLogger() {
        let logger = StandardProtocolLogger()
        
        #expect(logger.minimumLevel == .info)
        #expect(logger.sessionId != nil)
    }
    
    @Test("Log entry")
    func logEntry() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        
        logger.log(LogEntry(level: .info, category: .connection, message: "Test"))
        
        let entries = logger.getEntries()
        #expect(entries.count == 1)
        #expect(entries[0].message == "Test")
    }
    
    @Test("Filter by minimum level")
    func filterByMinimumLevel() {
        let logger = StandardProtocolLogger(minimumLevel: .warning)
        
        logger.log(LogEntry(level: .debug, category: .data, message: "Debug"))
        logger.log(LogEntry(level: .warning, category: .data, message: "Warning"))
        logger.log(LogEntry(level: .error, category: .error, message: "Error"))
        
        let entries = logger.getEntries()
        #expect(entries.count == 2)
    }
    
    @Test("Get entries by level")
    func getEntriesByLevel() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        
        logger.log(LogEntry(level: .info, category: .data, message: "Info"))
        logger.log(LogEntry(level: .error, category: .error, message: "Error"))
        
        let errors = logger.getEntries(minLevel: .error)
        #expect(errors.count == 1)
        #expect(errors[0].level == .error)
    }
    
    @Test("Get entries by category")
    func getEntriesByCategory() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        
        logger.log(LogEntry(level: .info, category: .connection, message: "Connection"))
        logger.log(LogEntry(level: .info, category: .data, message: "Data"))
        logger.log(LogEntry(level: .info, category: .connection, message: "Connection 2"))
        
        let connectionLogs = logger.getEntries(category: .connection)
        #expect(connectionLogs.count == 2)
    }
    
    @Test("Get entries by time range")
    func getEntriesByTimeRange() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        let now = Date()
        
        logger.log(LogEntry(timestamp: now.addingTimeInterval(-3600), level: .info, category: .data, message: "Old"))
        logger.log(LogEntry(timestamp: now, level: .info, category: .data, message: "Now"))
        logger.log(LogEntry(timestamp: now.addingTimeInterval(3600), level: .info, category: .data, message: "Future"))
        
        let rangeEntries = logger.getEntries(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(60))
        #expect(rangeEntries.count == 1)
        #expect(rangeEntries[0].message == "Now")
    }
    
    @Test("Clear entries")
    func clearEntries() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        
        logger.log(LogEntry(level: .info, category: .data, message: "Test"))
        #expect(logger.getEntries().count == 1)
        
        logger.clear()
        #expect(logger.getEntries().count == 0)
    }
    
    @Test("Max entries limit")
    func maxEntriesLimit() {
        let logger = StandardProtocolLogger(minimumLevel: .trace, maxEntries: 5)
        
        for i in 0..<10 {
            logger.log(LogEntry(level: .info, category: .data, message: "Entry \(i)"))
        }
        
        let entries = logger.getEntries()
        #expect(entries.count == 5)
        #expect(entries[0].message == "Entry 5") // Oldest kept
    }
    
    @Test("Export to JSON")
    func exportToJSON() throws {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        logger.log(LogEntry(level: .info, category: .connection, message: "Test"))
        
        let json = try logger.exportJSON()
        #expect(!json.isEmpty)
        
        let string = String(data: json, encoding: .utf8)!
        #expect(string.contains("Test"))
    }
    
    @Test("Export formatted")
    func exportFormatted() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        logger.log(LogEntry(level: .info, category: .connection, message: "Line 1"))
        logger.log(LogEntry(level: .warning, category: .data, message: "Line 2"))
        
        let formatted = logger.exportFormatted(includeTimestamp: false)
        #expect(formatted.contains("[INFO]"))
        #expect(formatted.contains("[WARN]"))
        #expect(formatted.contains("Line 1"))
        #expect(formatted.contains("Line 2"))
    }
    
    @Test("Convenience log methods")
    func convenienceLogMethods() {
        let logger = StandardProtocolLogger(minimumLevel: .trace)
        
        logger.trace("Trace message")
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        logger.critical("Critical message")
        
        let entries = logger.getEntries()
        #expect(entries.count == 6)
    }
}

// MARK: - Composite Logger Tests

@Suite("Composite Protocol Logger")
struct CompositeProtocolLoggerTests {
    @Test("Forward to multiple loggers")
    func forwardToMultipleLoggers() {
        let logger1 = StandardProtocolLogger(minimumLevel: .trace)
        let logger2 = StandardProtocolLogger(minimumLevel: .trace)
        
        let composite = CompositeProtocolLogger(loggers: [logger1, logger2])
        composite.log(LogEntry(level: .info, category: .data, message: "Test"))
        
        #expect(logger1.getEntries().count == 1)
        #expect(logger2.getEntries().count == 1)
    }
    
    @Test("Add logger dynamically")
    func addLoggerDynamically() {
        let logger1 = StandardProtocolLogger(minimumLevel: .trace)
        let composite = CompositeProtocolLogger(loggers: [logger1])
        
        composite.log(LogEntry(level: .info, category: .data, message: "Before"))
        
        let logger2 = StandardProtocolLogger(minimumLevel: .trace)
        composite.addLogger(logger2)
        
        composite.log(LogEntry(level: .info, category: .data, message: "After"))
        
        #expect(logger1.getEntries().count == 2)
        #expect(logger2.getEntries().count == 1)
    }
    
    @Test("Remove all loggers")
    func removeAllLoggers() {
        let logger1 = StandardProtocolLogger(minimumLevel: .trace)
        let composite = CompositeProtocolLogger(loggers: [logger1])
        
        composite.removeAllLoggers()
        composite.log(LogEntry(level: .info, category: .data, message: "Test"))
        
        #expect(logger1.getEntries().count == 0)
    }
}

// MARK: - Null Logger Tests

@Suite("Null Protocol Logger")
struct NullProtocolLoggerTests {
    @Test("Discards all entries")
    func discardsAllEntries() {
        let logger = NullProtocolLogger()
        
        logger.log(LogEntry(level: .critical, category: .error, message: "Critical error"))
        
        // No way to verify entries are discarded, but it shouldn't crash
        #expect(logger.minimumLevel == .critical)
    }
    
    @Test("Convenience methods work")
    func convenienceMethodsWork() {
        let logger = NullProtocolLogger()
        
        logger.info("Test")
        logger.error("Error")
        logger.critical("Critical")
        
        // Should not crash
        #expect(Bool(true))
    }
}

// MARK: - Filtered Logger Tests

@Suite("Filtered Protocol Logger")
struct FilteredProtocolLoggerTests {
    @Test("Filter by custom predicate")
    func filterByCustomPredicate() {
        let underlying = StandardProtocolLogger(minimumLevel: .trace)
        let filtered = FilteredProtocolLogger(wrapping: underlying) { entry in
            entry.message.hasPrefix("KEEP:")
        }
        
        filtered.log(LogEntry(level: .info, category: .data, message: "SKIP: Not wanted"))
        filtered.log(LogEntry(level: .info, category: .data, message: "KEEP: This is wanted"))
        
        #expect(underlying.getEntries().count == 1)
        #expect(underlying.getEntries()[0].message.hasPrefix("KEEP:"))
    }
    
    @Test("Filter by categories")
    func filterByCategories() {
        let underlying = StandardProtocolLogger(minimumLevel: .trace)
        let filtered = FilteredProtocolLogger.byCategories(
            [.connection, .authentication],
            wrapping: underlying
        )
        
        filtered.log(LogEntry(level: .info, category: .connection, message: "Connection"))
        filtered.log(LogEntry(level: .info, category: .data, message: "Data"))
        filtered.log(LogEntry(level: .info, category: .authentication, message: "Auth"))
        
        #expect(underlying.getEntries().count == 2)
    }
    
    @Test("Exclude categories")
    func excludeCategories() {
        let underlying = StandardProtocolLogger(minimumLevel: .trace)
        let filtered = FilteredProtocolLogger.excludingCategories(
            [.performance],
            wrapping: underlying
        )
        
        filtered.log(LogEntry(level: .info, category: .connection, message: "Connection"))
        filtered.log(LogEntry(level: .info, category: .performance, message: "Performance"))
        
        #expect(underlying.getEntries().count == 1)
    }
    
    @Test("Filter by device")
    func filterByDevice() {
        let underlying = StandardProtocolLogger(minimumLevel: .trace)
        let filtered = FilteredProtocolLogger.byDevice("device123", wrapping: underlying)
        
        filtered.log(LogEntry(level: .info, category: .data, message: "Other", deviceId: "device456"))
        filtered.log(LogEntry(level: .info, category: .data, message: "Target", deviceId: "device123"))
        
        #expect(underlying.getEntries().count == 1)
        #expect(underlying.getEntries()[0].deviceId == "device123")
    }
}

// MARK: - Log Statistics Tests

@Suite("Log Statistics")
struct LogStatisticsTests {
    @Test("Calculate from empty entries")
    func calculateFromEmpty() {
        let stats = LogStatistics.calculate(from: [])
        
        #expect(stats.totalEntries == 0)
        #expect(stats.errorCount == 0)
        #expect(stats.warningCount == 0)
    }
    
    @Test("Calculate from entries")
    func calculateFromEntries() {
        let entries = [
            LogEntry(level: .info, category: .connection, message: "Info"),
            LogEntry(level: .warning, category: .data, message: "Warning"),
            LogEntry(level: .error, category: .error, message: "Error"),
            LogEntry(level: .error, category: .error, message: "Error 2"),
            LogEntry(level: .critical, category: .error, message: "Critical")
        ]
        
        let stats = LogStatistics.calculate(from: entries)
        
        #expect(stats.totalEntries == 5)
        #expect(stats.errorCount == 3) // 2 errors + 1 critical
        #expect(stats.warningCount == 1)
        #expect(stats.entriesByLevel[.info] == 1)
        #expect(stats.entriesByLevel[.error] == 2)
        #expect(stats.entriesByCategory[.error] == 3)
    }
    
    @Test("Statistics time range")
    func statisticsTimeRange() {
        let now = Date()
        let entries = [
            LogEntry(timestamp: now.addingTimeInterval(-3600), level: .info, category: .data, message: "Early"),
            LogEntry(timestamp: now, level: .info, category: .data, message: "Now"),
            LogEntry(timestamp: now.addingTimeInterval(3600), level: .info, category: .data, message: "Late")
        ]
        
        let stats = LogStatistics.calculate(from: entries)
        
        #expect(stats.startTime != nil)
        #expect(stats.endTime != nil)
        #expect(stats.startTime! < stats.endTime!)
    }
    
    @Test("Statistics is Codable")
    func statisticsCodable() throws {
        let stats = LogStatistics(
            totalEntries: 100,
            entriesByLevel: [.info: 50, .error: 10],
            entriesByCategory: [.connection: 30, .data: 70],
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            errorCount: 10,
            warningCount: 5
        )
        
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(LogStatistics.self, from: data)
        #expect(decoded == stats)
    }
}

// MARK: - Log Session Tests

@Suite("Log Session")
struct LogSessionTests {
    @Test("Create session")
    func createSession() {
        let session = LogSession()
        
        #expect(session.isActive)
        #expect(session.duration == nil)
    }
    
    @Test("Session with end time")
    func sessionWithEndTime() {
        let start = Date()
        let end = start.addingTimeInterval(300)
        
        let session = LogSession(startTime: start, endTime: end)
        
        #expect(!session.isActive)
        #expect(session.duration == 300)
    }
    
    @Test("Session with metadata")
    func sessionWithMetadata() {
        let session = LogSession(
            deviceType: "dexcomG7",
            deviceId: "abc123",
            appVersion: "1.0.0",
            platform: "iOS 17.2"
        )
        
        #expect(session.deviceType == "dexcomG7")
        #expect(session.platform == "iOS 17.2")
    }
    
    @Test("Session is Codable")
    func sessionCodable() throws {
        let session = LogSession(
            deviceType: "libre2",
            appVersion: "2.0.0"
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LogSession.self, from: data)
        #expect(decoded == session)
    }
}

// MARK: - Protocol Log Report Tests

@Suite("Protocol Log Report")
struct ProtocolLogReportTests {
    @Test("Create report")
    func createReport() {
        let session = LogSession()
        let entries = [
            LogEntry(level: .info, category: .connection, message: "Connected"),
            LogEntry(level: .info, category: .data, message: "Data received")
        ]
        
        let report = ProtocolLogReport(session: session, entries: entries)
        
        #expect(report.entries.count == 2)
        #expect(report.statistics.totalEntries == 2)
    }
    
    @Test("Export to JSON")
    func exportToJSON() throws {
        let session = LogSession()
        let entries = [LogEntry(level: .info, category: .data, message: "Test")]
        let report = ProtocolLogReport(session: session, entries: entries)
        
        let json = try report.toJSON()
        #expect(!json.isEmpty)
        
        let string = String(data: json, encoding: .utf8)!
        #expect(string.contains("Test"))
    }
    
    @Test("Round-trip JSON")
    func roundTripJSON() throws {
        let session = LogSession(deviceType: "dexcomG7")
        let entries = [
            LogEntry(level: .info, category: .connection, message: "Test"),
            LogEntry(level: .error, category: .error, message: "Error")
        ]
        let report = ProtocolLogReport(session: session, entries: entries)
        
        let json = try report.toJSON()
        let decoded = try ProtocolLogReport.fromJSON(json)
        
        #expect(decoded.session.id == report.session.id)
        #expect(decoded.session.deviceType == report.session.deviceType)
        #expect(decoded.entries.count == report.entries.count)
        #expect(decoded.entries[0].message == report.entries[0].message)
        #expect(decoded.entries[1].message == report.entries[1].message)
        #expect(decoded.statistics.totalEntries == report.statistics.totalEntries)
        #expect(decoded.statistics.errorCount == report.statistics.errorCount)
    }
}

// MARK: - Log Entry Builder Tests

@Suite("Log Entry Builder")
struct LogEntryBuilderTests {
    @Test("Build simple entry")
    func buildSimpleEntry() {
        let entry = LogEntryBuilder()
            .level(.info)
            .category(.connection)
            .message("Connected")
            .build()
        
        #expect(entry.level == .info)
        #expect(entry.category == .connection)
        #expect(entry.message == "Connected")
    }
    
    @Test("Build with metadata")
    func buildWithMetadata() {
        let entry = LogEntryBuilder()
            .level(.debug)
            .category(.data)
            .message("Received")
            .metadata("bytes", "256")
            .metadata("type", "glucose")
            .build()
        
        #expect(entry.metadata["bytes"] == "256")
        #expect(entry.metadata["type"] == "glucose")
    }
    
    @Test("Build with device info")
    func buildWithDeviceInfo() {
        let entry = LogEntryBuilder()
            .level(.info)
            .message("Test")
            .deviceId("device123")
            .sessionId("session456")
            .build()
        
        #expect(entry.deviceId == "device123")
        #expect(entry.sessionId == "session456")
    }
    
    @Test("Builder is immutable")
    func builderIsImmutable() {
        let base = LogEntryBuilder().level(.info)
        let modified = base.level(.error)
        
        let entry1 = base.message("Info").build()
        let entry2 = modified.message("Error").build()
        
        #expect(entry1.level == .info)
        #expect(entry2.level == .error)
    }
}
