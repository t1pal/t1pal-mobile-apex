// EvidenceCollectorTests.swift
// BLEKit Tests
//
// Tests for EvidenceCollector protocol and implementations.
// INSTR-003: EvidenceCollector protocol definition

import Testing
import Foundation
@testable import BLEKit

// MARK: - Evidence Type Tests

@Suite("Evidence Type")
struct EvidenceTypeTests {
    
    @Test("All cases available")
    func allCases() {
        let cases = EvidenceType.allCases
        #expect(cases.contains(.log))
        #expect(cases.contains(.metric))
        #expect(cases.contains(.errorTrace))
        #expect(cases.contains(.connectionAttempt))
        #expect(cases.count >= 15)
    }
    
    @Test("Raw value encoding")
    func rawValue() {
        #expect(EvidenceType.log.rawValue == "log")
        #expect(EvidenceType.metric.rawValue == "metric")
        #expect(EvidenceType.errorTrace.rawValue == "errorTrace")
    }
}

// MARK: - Evidence Category Tests

@Suite("Evidence Category")
struct EvidenceCategoryTests {
    
    @Test("All cases available")
    func allCases() {
        let cases = EvidenceCategory.allCases
        #expect(cases.contains(.connection))
        #expect(cases.contains(.authentication))
        #expect(cases.contains(.error))
        #expect(cases.count >= 10)
    }
    
    @Test("Raw value encoding")
    func rawValue() {
        #expect(EvidenceCategory.connection.rawValue == "connection")
        #expect(EvidenceCategory.error.rawValue == "error")
    }
}

// MARK: - Evidence Priority Tests

@Suite("Evidence Priority")
struct EvidencePriorityTests {
    
    @Test("Priority ordering")
    func ordering() {
        #expect(EvidencePriority.low < EvidencePriority.normal)
        #expect(EvidencePriority.normal < EvidencePriority.high)
        #expect(EvidencePriority.high < EvidencePriority.critical)
    }
    
    @Test("Raw values")
    func rawValues() {
        #expect(EvidencePriority.low.rawValue == 0)
        #expect(EvidencePriority.normal.rawValue == 1)
        #expect(EvidencePriority.high.rawValue == 2)
        #expect(EvidencePriority.critical.rawValue == 3)
    }
}

// MARK: - Evidence Metadata Tests

@Suite("Evidence Metadata")
struct EvidenceMetadataTests {
    
    @Test("Create metadata")
    func createMetadata() {
        let metadata = EvidenceMetadata(source: "test")
        #expect(metadata.source == "test")
        #expect(metadata.deviceId == nil)
        #expect(metadata.tags.isEmpty)
    }
    
    @Test("Create with all options")
    func createAllOptions() {
        let metadata = EvidenceMetadata(
            source: "test",
            deviceId: "ABC123",
            sessionId: "session-1",
            tags: ["important", "debug"],
            properties: ["key": "value"]
        )
        #expect(metadata.deviceId == "ABC123")
        #expect(metadata.sessionId == "session-1")
        #expect(metadata.tags.contains("important"))
        #expect(metadata.properties["key"] == "value")
    }
    
    @Test("With tag")
    func withTag() {
        let metadata = EvidenceMetadata(source: "test")
        let updated = metadata.withTag("new-tag")
        #expect(updated.tags.contains("new-tag"))
        #expect(!metadata.tags.contains("new-tag"))
    }
    
    @Test("With property")
    func withProperty() {
        let metadata = EvidenceMetadata(source: "test")
        let updated = metadata.withProperty("key", "value")
        #expect(updated.properties["key"] == "value")
    }
}

// MARK: - Evidence Item Tests

@Suite("Evidence Item")
struct EvidenceItemTests {
    
    @Test("Create item")
    func createItem() {
        let item = EvidenceItem(
            type: .log,
            category: .connection,
            title: "Test Log",
            content: "Log content",
            metadata: EvidenceMetadata(source: "test")
        )
        #expect(item.type == .log)
        #expect(item.category == .connection)
        #expect(item.title == "Test Log")
        #expect(item.content == "Log content")
        #expect(item.priority == .normal)
        #expect(!item.redacted)
    }
    
    @Test("Create with all options")
    func createAllOptions() {
        let item = EvidenceItem(
            type: .errorTrace,
            category: .error,
            priority: .critical,
            title: "Critical Error",
            description: "An error occurred",
            content: "Error details",
            metadata: EvidenceMetadata(source: "test"),
            redacted: true
        )
        #expect(item.type == .errorTrace)
        #expect(item.priority == .critical)
        #expect(item.description == "An error occurred")
        #expect(item.redacted)
    }
    
    @Test("With redaction")
    func withRedaction() {
        let item = EvidenceItem(
            type: .log,
            category: .connection,
            title: "Device Log",
            content: "Device ID: ABCD1234EFGH connected",
            metadata: EvidenceMetadata(source: "test")
        )
        let redacted = item.withRedaction()
        #expect(redacted.redacted)
        #expect(redacted.content.contains("[REDACTED]"))
        #expect(!redacted.content.contains("ABCD1234EFGH"))
    }
    
    @Test("Redaction of tokens")
    func redactionTokens() {
        let item = EvidenceItem(
            type: .log,
            category: .authentication,
            title: "Auth Log",
            content: "token=secret123abc password: mypassword",
            metadata: EvidenceMetadata(source: "test")
        )
        let redacted = item.withRedaction()
        #expect(redacted.content.contains("[REDACTED]"))
    }
}

// MARK: - Evidence Session Tests

@Suite("Evidence Session")
struct EvidenceSessionTests {
    
    @Test("Create session")
    func createSession() {
        let session = EvidenceSession(name: "Test Session", purpose: "Testing")
        #expect(session.name == "Test Session")
        #expect(session.purpose == "Testing")
        #expect(session.status == .active)
        #expect(session.isActive)
        #expect(session.itemCount == 0)
        #expect(session.endTime == nil)
    }
    
    @Test("Complete session")
    func completeSession() {
        var session = EvidenceSession(name: "Test", purpose: "Testing")
        session.complete()
        #expect(session.status == .completed)
        #expect(!session.isActive)
        #expect(session.endTime != nil)
    }
    
    @Test("Fail session")
    func failSession() {
        var session = EvidenceSession(name: "Test", purpose: "Testing")
        session.fail()
        #expect(session.status == .failed)
    }
    
    @Test("Cancel session")
    func cancelSession() {
        var session = EvidenceSession(name: "Test", purpose: "Testing")
        session.cancel()
        #expect(session.status == .cancelled)
    }
    
    @Test("Increment count")
    func incrementCount() {
        var session = EvidenceSession(name: "Test", purpose: "Testing")
        session.incrementCount()
        session.incrementCount()
        #expect(session.itemCount == 2)
    }
    
    @Test("Duration calculation")
    func duration() {
        let start = Date()
        var session = EvidenceSession(name: "Test", startTime: start, purpose: "Testing")
        #expect(session.duration >= 0)
        session.complete()
        #expect(session.duration >= 0)
    }
}

// MARK: - Evidence Statistics Tests

@Suite("Evidence Statistics")
struct EvidenceStatisticsTests {
    
    @Test("Create statistics")
    func createStatistics() {
        let stats = EvidenceStatistics(
            totalItems: 100,
            byType: [.log: 50, .metric: 30, .errorTrace: 20],
            byCategory: [.connection: 40, .error: 30, .performance: 30],
            byPriority: [.normal: 80, .high: 15, .critical: 5],
            redactedCount: 10,
            sessionCount: 3,
            oldestTimestamp: Date().addingTimeInterval(-3600),
            newestTimestamp: Date()
        )
        #expect(stats.totalItems == 100)
        #expect(stats.byType[.log] == 50)
        #expect(stats.redactedCount == 10)
        #expect(stats.sessionCount == 3)
    }
    
    @Test("Time span calculation")
    func timeSpan() {
        let oldest = Date().addingTimeInterval(-3600)
        let newest = Date()
        let stats = EvidenceStatistics(
            totalItems: 10,
            byType: [:],
            byCategory: [:],
            byPriority: [:],
            redactedCount: 0,
            sessionCount: 1,
            oldestTimestamp: oldest,
            newestTimestamp: newest
        )
        #expect(stats.timeSpan != nil)
        #expect(stats.timeSpan! >= 3599 && stats.timeSpan! <= 3601)
    }
    
    @Test("Nil time span when no timestamps")
    func nilTimeSpan() {
        let stats = EvidenceStatistics(
            totalItems: 0,
            byType: [:],
            byCategory: [:],
            byPriority: [:],
            redactedCount: 0,
            sessionCount: 0,
            oldestTimestamp: nil,
            newestTimestamp: nil
        )
        #expect(stats.timeSpan == nil)
    }
}

// MARK: - Evidence Filter Tests

@Suite("Evidence Filter")
struct EvidenceFilterTests {
    
    func makeItem(
        type: EvidenceType = .log,
        category: EvidenceCategory = .general,
        priority: EvidencePriority = .normal,
        sessionId: String? = nil,
        deviceId: String? = nil,
        tags: Set<String> = [],
        redacted: Bool = false
    ) -> EvidenceItem {
        EvidenceItem(
            type: type,
            category: category,
            priority: priority,
            title: "Test",
            content: "Content",
            metadata: EvidenceMetadata(
                source: "test",
                deviceId: deviceId,
                sessionId: sessionId,
                tags: tags
            ),
            redacted: redacted
        )
    }
    
    @Test("All filter matches everything")
    func allFilter() {
        let filter = EvidenceFilter.all
        let item = makeItem()
        #expect(filter.matches(item))
    }
    
    @Test("Filter by type")
    func filterByType() {
        let filter = EvidenceFilter(types: [.log, .metric])
        #expect(filter.matches(makeItem(type: .log)))
        #expect(filter.matches(makeItem(type: .metric)))
        #expect(!filter.matches(makeItem(type: .errorTrace)))
    }
    
    @Test("Filter by category")
    func filterByCategory() {
        let filter = EvidenceFilter(categories: [.error, .connection])
        #expect(filter.matches(makeItem(category: .error)))
        #expect(filter.matches(makeItem(category: .connection)))
        #expect(!filter.matches(makeItem(category: .general)))
    }
    
    @Test("Filter by min priority")
    func filterByMinPriority() {
        let filter = EvidenceFilter(minPriority: .high)
        #expect(!filter.matches(makeItem(priority: .low)))
        #expect(!filter.matches(makeItem(priority: .normal)))
        #expect(filter.matches(makeItem(priority: .high)))
        #expect(filter.matches(makeItem(priority: .critical)))
    }
    
    @Test("Filter by session ID")
    func filterBySessionId() {
        let filter = EvidenceFilter.forSession("session-1")
        #expect(filter.matches(makeItem(sessionId: "session-1")))
        #expect(!filter.matches(makeItem(sessionId: "session-2")))
        #expect(!filter.matches(makeItem(sessionId: nil)))
    }
    
    @Test("Filter by device ID")
    func filterByDeviceId() {
        let filter = EvidenceFilter.forDevice("device-1")
        #expect(filter.matches(makeItem(deviceId: "device-1")))
        #expect(!filter.matches(makeItem(deviceId: "device-2")))
    }
    
    @Test("Filter by tags")
    func filterByTags() {
        let filter = EvidenceFilter(tags: ["important"])
        #expect(filter.matches(makeItem(tags: ["important", "debug"])))
        #expect(!filter.matches(makeItem(tags: ["debug"])))
        #expect(!filter.matches(makeItem(tags: [])))
    }
    
    @Test("Filter excludes redacted")
    func filterExcludesRedacted() {
        let filter = EvidenceFilter(includeRedacted: false)
        #expect(filter.matches(makeItem(redacted: false)))
        #expect(!filter.matches(makeItem(redacted: true)))
    }
    
    @Test("Errors preset filter")
    func errorsPreset() {
        let filter = EvidenceFilter.errors()
        #expect(filter.matches(makeItem(category: .error)))
        #expect(!filter.matches(makeItem(category: .connection)))
    }
    
    @Test("Critical preset filter")
    func criticalPreset() {
        let filter = EvidenceFilter.critical()
        #expect(filter.matches(makeItem(priority: .critical)))
        #expect(!filter.matches(makeItem(priority: .high)))
    }
}

// MARK: - Evidence Report Tests

@Suite("Evidence Report")
struct EvidenceReportTests {
    
    @Test("Create report")
    func createReport() {
        let sessions = [EvidenceSession(name: "Test", purpose: "Testing")]
        let items = [
            EvidenceItem(
                type: .log,
                category: .general,
                title: "Log",
                content: "Content",
                metadata: EvidenceMetadata(source: "test")
            )
        ]
        
        let report = EvidenceReport(
            title: "Test Report",
            description: "A test report",
            sessions: sessions,
            items: items
        )
        
        #expect(report.title == "Test Report")
        #expect(report.description == "A test report")
        #expect(report.sessions.count == 1)
        #expect(report.items.count == 1)
        #expect(report.statistics.totalItems == 1)
    }
    
    @Test("Statistics calculated correctly")
    func statisticsCalculated() {
        let items = [
            EvidenceItem(type: .log, category: .general, priority: .normal,
                         title: "Log", content: "", metadata: EvidenceMetadata(source: "test")),
            EvidenceItem(type: .log, category: .error, priority: .high,
                         title: "Error", content: "", metadata: EvidenceMetadata(source: "test")),
            EvidenceItem(type: .metric, category: .performance, priority: .critical,
                         title: "Metric", content: "", metadata: EvidenceMetadata(source: "test"))
        ]
        
        let report = EvidenceReport(title: "Test", sessions: [], items: items)
        
        #expect(report.statistics.totalItems == 3)
        #expect(report.statistics.byType[.log] == 2)
        #expect(report.statistics.byType[.metric] == 1)
        #expect(report.statistics.byCategory[.error] == 1)
        #expect(report.statistics.byPriority[.critical] == 1)
    }
    
    @Test("JSON round trip")
    func jsonRoundTrip() throws {
        let report = EvidenceReport(
            title: "Test Report",
            description: "Description",
            sessions: [EvidenceSession(name: "Session", purpose: "Testing")],
            items: [
                EvidenceItem(
                    type: .log,
                    category: .general,
                    title: "Log",
                    content: "Content",
                    metadata: EvidenceMetadata(source: "test")
                )
            ]
        )
        
        let json = try report.toJSON()
        let decoded = try EvidenceReport.fromJSON(json)
        
        #expect(decoded.title == report.title)
        #expect(decoded.items.count == report.items.count)
    }
    
    @Test("Summary generation")
    func summary() {
        let items = [
            EvidenceItem(type: .log, category: .error, priority: .critical,
                         title: "Critical", content: "", metadata: EvidenceMetadata(source: "test"))
        ]
        let report = EvidenceReport(title: "Test", sessions: [], items: items)
        let summary = report.summary()
        
        #expect(summary.contains("Test"))
        #expect(summary.contains("Items: 1"))
        #expect(summary.contains("Critical items: 1"))
    }
}

// MARK: - Standard Evidence Collector Tests

@Suite("Standard Evidence Collector")
struct StandardEvidenceCollectorTests {
    
    @Test("Start and get session")
    func startSession() async {
        let collector = StandardEvidenceCollector()
        let session = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        
        #expect(session.name == "Test")
        #expect(session.purpose == "Testing")
        
        let current = await collector.currentSession()
        #expect(current?.id == session.id)
    }
    
    @Test("End session")
    func endSession() async {
        let collector = StandardEvidenceCollector()
        let session = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        
        await collector.endSession(id: session.id, status: .completed)
        
        let retrieved = await collector.session(id: session.id)
        #expect(retrieved?.status == .completed)
        
        let current = await collector.currentSession()
        #expect(current == nil)
    }
    
    @Test("Add item")
    func addItem() async {
        let collector = StandardEvidenceCollector()
        
        let item = EvidenceItem(
            type: .log,
            category: .general,
            title: "Test",
            content: "Content",
            metadata: EvidenceMetadata(source: "test")
        )
        
        await collector.addItem(item)
        
        let items = await collector.allItems()
        #expect(items.count == 1)
        #expect(items.first?.title == "Test")
    }
    
    @Test("Add log")
    func addLog() async {
        let collector = StandardEvidenceCollector()
        
        await collector.addLog(
            message: "Test message",
            level: .high,
            source: "test",
            category: .connection
        )
        
        let items = await collector.allItems()
        #expect(items.count == 1)
        #expect(items.first?.type == .log)
        #expect(items.first?.priority == .high)
    }
    
    @Test("Add error")
    func addError() async {
        let collector = StandardEvidenceCollector()
        
        struct TestError: Error {
            var localizedDescription: String { "Test error" }
        }
        
        await collector.addError(TestError(), context: "testing", category: .error)
        
        let items = await collector.allItems()
        #expect(items.count == 1)
        #expect(items.first?.type == .errorTrace)
        #expect(items.first?.priority == .high)
    }
    
    @Test("Add metric")
    func addMetric() async {
        let collector = StandardEvidenceCollector()
        
        await collector.addMetric(name: "latency", value: 150.5, unit: "ms", category: .performance)
        
        let items = await collector.allItems()
        #expect(items.count == 1)
        #expect(items.first?.type == .metric)
        #expect(items.first?.content == "150.5 ms")
    }
    
    @Test("Filter items")
    func filterItems() async {
        let collector = StandardEvidenceCollector()
        
        await collector.addLog(message: "Log 1", level: .normal, source: "test", category: .general)
        await collector.addLog(message: "Log 2", level: .critical, source: "test", category: .error)
        
        let allItems = await collector.allItems()
        #expect(allItems.count == 2)
        
        let errors = await collector.items(matching: .errors())
        #expect(errors.count == 1)
        
        let critical = await collector.items(matching: .critical())
        #expect(critical.count == 1)
    }
    
    @Test("Generate report")
    func generateReport() async {
        let collector = StandardEvidenceCollector()
        _ = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        await collector.addLog(message: "Log", level: .normal, source: "test", category: .general)
        
        let report = await collector.generateReport(
            title: "Test Report",
            description: "A test",
            filter: nil
        )
        
        #expect(report.title == "Test Report")
        #expect(report.items.count == 1)
        #expect(report.sessions.count == 1)
    }
    
    @Test("Statistics")
    func statistics() async {
        let collector = StandardEvidenceCollector()
        _ = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        await collector.addLog(message: "Log 1", level: .normal, source: "test", category: .general)
        await collector.addLog(message: "Log 2", level: .high, source: "test", category: .error)
        await collector.addMetric(name: "test", value: 1.0, unit: nil, category: .performance)
        
        let stats = await collector.statistics()
        
        #expect(stats.totalItems == 3)
        #expect(stats.byType[.log] == 2)
        #expect(stats.byType[.metric] == 1)
        #expect(stats.sessionCount == 1)
    }
    
    @Test("Clear all")
    func clearAll() async {
        let collector = StandardEvidenceCollector()
        _ = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        await collector.addLog(message: "Log", level: .normal, source: "test", category: .general)
        
        await collector.clear()
        
        let items = await collector.allItems()
        let sessions = await collector.allSessions()
        let current = await collector.currentSession()
        
        #expect(items.isEmpty)
        #expect(sessions.isEmpty)
        #expect(current == nil)
    }
    
    @Test("Max items limit enforced")
    func maxItemsLimit() async {
        let collector = StandardEvidenceCollector(maxItems: 5)
        
        for i in 0..<10 {
            await collector.addLog(message: "Log \(i)", level: .normal, source: "test", category: .general)
        }
        
        let items = await collector.allItems()
        #expect(items.count == 5)
    }
    
    @Test("Session item count updated")
    func sessionItemCount() async {
        let collector = StandardEvidenceCollector()
        let session = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        
        await collector.addLog(message: "Log 1", level: .normal, source: "test", category: .general)
        await collector.addLog(message: "Log 2", level: .normal, source: "test", category: .general)
        
        let updated = await collector.session(id: session.id)
        #expect(updated?.itemCount == 2)
    }
}

// MARK: - Composite Evidence Collector Tests

@Suite("Composite Evidence Collector")
struct CompositeEvidenceCollectorTests {
    
    @Test("Forwards to all collectors")
    func forwardsToAll() async {
        let primary = StandardEvidenceCollector()
        let secondary = StandardEvidenceCollector()
        let composite = CompositeEvidenceCollector(primary: primary, secondaries: [secondary])
        
        await composite.addLog(message: "Test", level: .normal, source: "test", category: .general)
        
        let primaryItems = await primary.allItems()
        let secondaryItems = await secondary.allItems()
        
        #expect(primaryItems.count == 1)
        #expect(secondaryItems.count == 1)
    }
    
    @Test("Returns primary results")
    func returnsPrimaryResults() async {
        let primary = StandardEvidenceCollector()
        let secondary = StandardEvidenceCollector()
        let composite = CompositeEvidenceCollector(primary: primary, secondaries: [secondary])
        
        await composite.addLog(message: "Test", level: .normal, source: "test", category: .general)
        
        let items = await composite.allItems()
        #expect(items.count == 1)
    }
    
    @Test("Clear clears all")
    func clearClearsAll() async {
        let primary = StandardEvidenceCollector()
        let secondary = StandardEvidenceCollector()
        let composite = CompositeEvidenceCollector(primary: primary, secondaries: [secondary])
        
        await composite.addLog(message: "Test", level: .normal, source: "test", category: .general)
        await composite.clear()
        
        let primaryItems = await primary.allItems()
        let secondaryItems = await secondary.allItems()
        
        #expect(primaryItems.isEmpty)
        #expect(secondaryItems.isEmpty)
    }
}

// MARK: - Null Evidence Collector Tests

@Suite("Null Evidence Collector")
struct NullEvidenceCollectorTests {
    
    @Test("Discards all items")
    func discardsItems() async {
        let collector = NullEvidenceCollector()
        
        await collector.addLog(message: "Test", level: .normal, source: "test", category: .general)
        await collector.addError(NSError(domain: "test", code: 1), context: "test", category: .error)
        await collector.addMetric(name: "test", value: 1.0, unit: nil, category: .performance)
        
        let items = await collector.allItems()
        #expect(items.isEmpty)
    }
    
    @Test("Returns empty statistics")
    func emptyStatistics() async {
        let collector = NullEvidenceCollector()
        let stats = await collector.statistics()
        
        #expect(stats.totalItems == 0)
        #expect(stats.sessionCount == 0)
    }
    
    @Test("Start session returns valid session")
    func startSessionReturnsSession() async {
        let collector = NullEvidenceCollector()
        let session = await collector.startSession(name: "Test", purpose: "Testing", deviceId: nil)
        
        #expect(session.name == "Test")
    }
}

// MARK: - Evidence Item Builder Tests

@Suite("Evidence Item Builder")
struct EvidenceItemBuilderTests {
    
    @Test("Build with defaults")
    func buildDefaults() {
        let item = EvidenceItemBuilder()
            .title("Test")
            .content("Content")
            .source("test")
            .build()
        
        #expect(item.title == "Test")
        #expect(item.content == "Content")
        #expect(item.type == .log)
        #expect(item.category == .general)
        #expect(item.priority == .normal)
    }
    
    @Test("Build with all options")
    func buildAllOptions() {
        let item = EvidenceItemBuilder()
            .type(.errorTrace)
            .category(.error)
            .priority(.critical)
            .title("Error")
            .description("An error occurred")
            .content("Error details")
            .source("handler")
            .deviceId("device-1")
            .sessionId("session-1")
            .tag("important")
            .property("code", "500")
            .redacted(true)
            .build()
        
        #expect(item.type == .errorTrace)
        #expect(item.category == .error)
        #expect(item.priority == .critical)
        #expect(item.title == "Error")
        #expect(item.description == "An error occurred")
        #expect(item.metadata.deviceId == "device-1")
        #expect(item.metadata.sessionId == "session-1")
        #expect(item.metadata.tags.contains("important"))
        #expect(item.metadata.properties["code"] == "500")
        #expect(item.redacted)
    }
    
    @Test("Fluent API is immutable")
    func fluentImmutable() {
        let builder1 = EvidenceItemBuilder().title("Title 1")
        let builder2 = builder1.title("Title 2")
        
        let item1 = builder1.build()
        let item2 = builder2.build()
        
        #expect(item1.title == "Title 1")
        #expect(item2.title == "Title 2")
    }
}

// MARK: - Evidence Exporter Tests

@Suite("Evidence Exporter")
struct EvidenceExporterTests {
    let exporter = EvidenceExporter()
    
    func makeReport() -> EvidenceReport {
        let items = [
            EvidenceItem(
                type: .log,
                category: .general,
                priority: .normal,
                title: "Log Entry",
                content: "Log content",
                metadata: EvidenceMetadata(source: "test")
            ),
            EvidenceItem(
                type: .errorTrace,
                category: .error,
                priority: .critical,
                title: "Error Entry",
                content: "Error content",
                metadata: EvidenceMetadata(source: "test")
            )
        ]
        
        return EvidenceReport(
            title: "Test Report",
            description: "A test report",
            sessions: [EvidenceSession(name: "Session", purpose: "Testing")],
            items: items
        )
    }
    
    @Test("Export to JSON")
    func exportJSON() throws {
        let report = makeReport()
        let json = try exporter.exportJSON(report)
        
        #expect(!json.isEmpty)
        
        let decoded = try EvidenceReport.fromJSON(json)
        #expect(decoded.title == report.title)
    }
    
    @Test("Export to text")
    func exportText() {
        let report = makeReport()
        let text = exporter.exportText(report)
        
        #expect(text.contains("Test Report"))
        #expect(text.contains("STATISTICS"))
        #expect(text.contains("SESSIONS"))
        #expect(text.contains("CRITICAL ITEMS"))
        #expect(text.contains("ALL ITEMS"))
    }
    
    @Test("Export to CSV")
    func exportCSV() {
        let report = makeReport()
        let csv = exporter.exportCSV(report)
        
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3) // Header + 2 items
        #expect(lines[0].contains("timestamp,type,category"))
    }
    
    @Test("CSV escapes special characters")
    func csvEscapes() {
        let items = [
            EvidenceItem(
                type: .log,
                category: .general,
                title: "Title with, comma",
                content: "Content with \"quotes\"",
                metadata: EvidenceMetadata(source: "test")
            )
        ]
        
        let report = EvidenceReport(title: "Test", sessions: [], items: items)
        let csv = exporter.exportCSV(report)
        
        #expect(csv.contains("\"Title with, comma\""))
        #expect(csv.contains("\"Content with \"\"quotes\"\"\""))
    }
}
