// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// EvidenceCollector.swift
// BLEKit
//
// Evidence collection infrastructure for diagnostic reports.
// Supports collecting, organizing, and exporting diagnostic evidence.
//
// INSTR-003: EvidenceCollector protocol definition

import Foundation

// MARK: - Evidence Type

/// Type of evidence that can be collected.
public enum EvidenceType: String, Sendable, Codable, CaseIterable {
    case log
    case metric
    case screenshot
    case configuration
    case connectionAttempt
    case errorTrace
    case deviceInfo
    case protocolTrace
    case userAction
    case systemEvent
    case crashReport
    case networkTrace
    case blePacket
    case timestamp
    case annotation
}

/// Category for organizing evidence.
public enum EvidenceCategory: String, Sendable, Codable, CaseIterable {
    case connection
    case authentication
    case communication
    case performance
    case error
    case configuration
    case userInterface
    case system
    case network
    case bluetooth
    case algorithm
    case general
}

/// Priority level for evidence items.
public enum EvidencePriority: Int, Sendable, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: EvidencePriority, rhs: EvidencePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Evidence Metadata

/// Metadata associated with evidence.
public struct EvidenceMetadata: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let source: String
    public let deviceId: String?
    public let sessionId: String?
    public let tags: Set<String>
    public let properties: [String: String]
    
    public init(
        timestamp: Date = Date(),
        source: String,
        deviceId: String? = nil,
        sessionId: String? = nil,
        tags: Set<String> = [],
        properties: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.source = source
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.tags = tags
        self.properties = properties
    }
    
    public func withTag(_ tag: String) -> EvidenceMetadata {
        var newTags = tags
        newTags.insert(tag)
        return EvidenceMetadata(
            timestamp: timestamp,
            source: source,
            deviceId: deviceId,
            sessionId: sessionId,
            tags: newTags,
            properties: properties
        )
    }
    
    public func withProperty(_ key: String, _ value: String) -> EvidenceMetadata {
        var newProps = properties
        newProps[key] = value
        return EvidenceMetadata(
            timestamp: timestamp,
            source: source,
            deviceId: deviceId,
            sessionId: sessionId,
            tags: tags,
            properties: newProps
        )
    }
}

// MARK: - Evidence Item

/// Individual piece of evidence.
public struct EvidenceItem: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let type: EvidenceType
    public let category: EvidenceCategory
    public let priority: EvidencePriority
    public let title: String
    public let description: String
    public let content: String
    public let metadata: EvidenceMetadata
    public let redacted: Bool
    
    public init(
        id: String = UUID().uuidString,
        type: EvidenceType,
        category: EvidenceCategory,
        priority: EvidencePriority = .normal,
        title: String,
        description: String = "",
        content: String,
        metadata: EvidenceMetadata,
        redacted: Bool = false
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.priority = priority
        self.title = title
        self.description = description
        self.content = content
        self.metadata = metadata
        self.redacted = redacted
    }
    
    public func withRedaction() -> EvidenceItem {
        EvidenceItem(
            id: id,
            type: type,
            category: category,
            priority: priority,
            title: title,
            description: description,
            content: redactContent(content),
            metadata: metadata,
            redacted: true
        )
    }
    
    private func redactContent(_ content: String) -> String {
        // Redact common sensitive patterns
        var redacted = content
        
        // Redact device IDs (alphanumeric 8+ chars)
        let deviceIdPattern = #"[A-F0-9]{8,}"#
        if let regex = try? NSRegularExpression(pattern: deviceIdPattern, options: .caseInsensitive) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "[REDACTED]")
        }
        
        // Redact API keys/tokens
        let tokenPattern = #"(token|key|secret|password)[=:]\s*\S+"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "[REDACTED]")
        }
        
        return redacted
    }
}

// MARK: - Evidence Session

/// Session for evidence collection with timing.
public struct EvidenceSession: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let startTime: Date
    public private(set) var endTime: Date?
    public let purpose: String
    public let deviceId: String?
    public private(set) var itemCount: Int
    public private(set) var status: SessionStatus
    
    public enum SessionStatus: String, Sendable, Codable {
        case active
        case completed
        case failed
        case cancelled
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date = Date(),
        purpose: String = "",
        deviceId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = nil
        self.purpose = purpose
        self.deviceId = deviceId
        self.itemCount = 0
        self.status = .active
    }
    
    public var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    public var isActive: Bool { status == .active }
    
    public mutating func incrementCount() {
        itemCount += 1
    }
    
    public mutating func complete() {
        endTime = Date()
        status = .completed
    }
    
    public mutating func fail() {
        endTime = Date()
        status = .failed
    }
    
    public mutating func cancel() {
        endTime = Date()
        status = .cancelled
    }
}

// MARK: - Evidence Statistics

/// Statistics about collected evidence.
public struct EvidenceStatistics: Sendable, Equatable, Codable {
    public let totalItems: Int
    public let byType: [EvidenceType: Int]
    public let byCategory: [EvidenceCategory: Int]
    public let byPriority: [EvidencePriority: Int]
    public let redactedCount: Int
    public let sessionCount: Int
    public let oldestTimestamp: Date?
    public let newestTimestamp: Date?
    
    public init(
        totalItems: Int,
        byType: [EvidenceType: Int],
        byCategory: [EvidenceCategory: Int],
        byPriority: [EvidencePriority: Int],
        redactedCount: Int,
        sessionCount: Int,
        oldestTimestamp: Date?,
        newestTimestamp: Date?
    ) {
        self.totalItems = totalItems
        self.byType = byType
        self.byCategory = byCategory
        self.byPriority = byPriority
        self.redactedCount = redactedCount
        self.sessionCount = sessionCount
        self.oldestTimestamp = oldestTimestamp
        self.newestTimestamp = newestTimestamp
    }
    
    public var timeSpan: TimeInterval? {
        guard let oldest = oldestTimestamp, let newest = newestTimestamp else { return nil }
        return newest.timeIntervalSince(oldest)
    }
}

// MARK: - Evidence Filter

/// Filter for querying evidence.
public struct EvidenceFilter: Sendable {
    public let types: Set<EvidenceType>?
    public let categories: Set<EvidenceCategory>?
    public let minPriority: EvidencePriority?
    public let startDate: Date?
    public let endDate: Date?
    public let sessionId: String?
    public let deviceId: String?
    public let tags: Set<String>?
    public let searchText: String?
    public let includeRedacted: Bool
    
    public init(
        types: Set<EvidenceType>? = nil,
        categories: Set<EvidenceCategory>? = nil,
        minPriority: EvidencePriority? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        sessionId: String? = nil,
        deviceId: String? = nil,
        tags: Set<String>? = nil,
        searchText: String? = nil,
        includeRedacted: Bool = true
    ) {
        self.types = types
        self.categories = categories
        self.minPriority = minPriority
        self.startDate = startDate
        self.endDate = endDate
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.tags = tags
        self.searchText = searchText
        self.includeRedacted = includeRedacted
    }
    
    public func matches(_ item: EvidenceItem) -> Bool {
        if let types = types, !types.contains(item.type) { return false }
        if let categories = categories, !categories.contains(item.category) { return false }
        if let minPriority = minPriority, item.priority < minPriority { return false }
        if let startDate = startDate, item.metadata.timestamp < startDate { return false }
        if let endDate = endDate, item.metadata.timestamp > endDate { return false }
        if let sessionId = sessionId, item.metadata.sessionId != sessionId { return false }
        if let deviceId = deviceId, item.metadata.deviceId != deviceId { return false }
        if let tags = tags, !tags.isSubset(of: item.metadata.tags) { return false }
        if !includeRedacted && item.redacted { return false }
        
        if let searchText = searchText, !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            let matchesTitle = item.title.lowercased().contains(lowercased)
            let matchesContent = item.content.lowercased().contains(lowercased)
            let matchesDescription = item.description.lowercased().contains(lowercased)
            if !matchesTitle && !matchesContent && !matchesDescription { return false }
        }
        
        return true
    }
    
    public static let all = EvidenceFilter()
    
    public static func errors() -> EvidenceFilter {
        EvidenceFilter(categories: [.error])
    }
    
    public static func critical() -> EvidenceFilter {
        EvidenceFilter(minPriority: .critical)
    }
    
    public static func forSession(_ sessionId: String) -> EvidenceFilter {
        EvidenceFilter(sessionId: sessionId)
    }
    
    public static func forDevice(_ deviceId: String) -> EvidenceFilter {
        EvidenceFilter(deviceId: deviceId)
    }
    
    public static func recent(hours: Int) -> EvidenceFilter {
        EvidenceFilter(startDate: Date().addingTimeInterval(-Double(hours) * 3600))
    }
}

// MARK: - Evidence Report

/// Complete evidence report for export/sharing.
public struct EvidenceReport: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let createdAt: Date
    public let sessions: [EvidenceSession]
    public let items: [EvidenceItem]
    public let statistics: EvidenceStatistics
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        createdAt: Date = Date(),
        sessions: [EvidenceSession],
        items: [EvidenceItem],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.sessions = sessions
        self.items = items
        self.metadata = metadata
        self.statistics = Self.calculateStatistics(items: items, sessions: sessions)
    }
    
    private static func calculateStatistics(items: [EvidenceItem], sessions: [EvidenceSession]) -> EvidenceStatistics {
        var byType: [EvidenceType: Int] = [:]
        var byCategory: [EvidenceCategory: Int] = [:]
        var byPriority: [EvidencePriority: Int] = [:]
        var redactedCount = 0
        var oldest: Date?
        var newest: Date?
        
        for item in items {
            byType[item.type, default: 0] += 1
            byCategory[item.category, default: 0] += 1
            byPriority[item.priority, default: 0] += 1
            if item.redacted { redactedCount += 1 }
            
            if oldest == nil || item.metadata.timestamp < oldest! {
                oldest = item.metadata.timestamp
            }
            if newest == nil || item.metadata.timestamp > newest! {
                newest = item.metadata.timestamp
            }
        }
        
        return EvidenceStatistics(
            totalItems: items.count,
            byType: byType,
            byCategory: byCategory,
            byPriority: byPriority,
            redactedCount: redactedCount,
            sessionCount: sessions.count,
            oldestTimestamp: oldest,
            newestTimestamp: newest
        )
    }
    
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    public static func fromJSON(_ data: Data) throws -> EvidenceReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvidenceReport.self, from: data)
    }
    
    public func summary() -> String {
        var lines: [String] = []
        lines.append("Evidence Report: \(title)")
        lines.append("Created: \(ISO8601DateFormatter().string(from: createdAt))")
        lines.append("Items: \(items.count)")
        lines.append("Sessions: \(sessions.count)")
        
        if !statistics.byCategory.isEmpty {
            lines.append("")
            lines.append("By Category:")
            for (category, count) in statistics.byCategory.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(category.rawValue): \(count)")
            }
        }
        
        if let critical = statistics.byPriority[.critical], critical > 0 {
            lines.append("")
            lines.append("⚠️ Critical items: \(critical)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Evidence Collector Protocol

/// Protocol for evidence collectors.
public protocol EvidenceCollector: Sendable {
    /// Start a new evidence collection session.
    func startSession(name: String, purpose: String, deviceId: String?) async -> EvidenceSession
    
    /// End the current session.
    func endSession(id: String, status: EvidenceSession.SessionStatus) async
    
    /// Get the current active session.
    func currentSession() async -> EvidenceSession?
    
    /// Add an evidence item.
    func addItem(_ item: EvidenceItem) async
    
    /// Add a log entry as evidence.
    func addLog(message: String, level: EvidencePriority, source: String, category: EvidenceCategory) async
    
    /// Add an error as evidence.
    func addError(_ error: Error, context: String, category: EvidenceCategory) async
    
    /// Add a metric as evidence.
    func addMetric(name: String, value: Double, unit: String?, category: EvidenceCategory) async
    
    /// Get all items.
    func allItems() async -> [EvidenceItem]
    
    /// Get items matching a filter.
    func items(matching filter: EvidenceFilter) async -> [EvidenceItem]
    
    /// Get all sessions.
    func allSessions() async -> [EvidenceSession]
    
    /// Get a session by ID.
    func session(id: String) async -> EvidenceSession?
    
    /// Generate a report.
    func generateReport(title: String, description: String, filter: EvidenceFilter?) async -> EvidenceReport
    
    /// Get statistics.
    func statistics() async -> EvidenceStatistics
    
    /// Clear all evidence.
    func clear() async
    
    /// Clear evidence older than a date.
    func clearOlderThan(_ date: Date) async
}

// MARK: - Standard Evidence Collector

/// Thread-safe implementation of EvidenceCollector.
public actor StandardEvidenceCollector: EvidenceCollector {
    private var items: [EvidenceItem] = []
    private var sessions: [String: EvidenceSession] = [:]
    private var currentSessionId: String?
    private let maxItems: Int
    
    public init(maxItems: Int = 10000) {
        self.maxItems = maxItems
    }
    
    public func startSession(name: String, purpose: String, deviceId: String?) async -> EvidenceSession {
        // End any existing session
        if let currentId = currentSessionId {
            await endSession(id: currentId, status: .completed)
        }
        
        let session = EvidenceSession(name: name, purpose: purpose, deviceId: deviceId)
        sessions[session.id] = session
        currentSessionId = session.id
        return session
    }
    
    public func endSession(id: String, status: EvidenceSession.SessionStatus) async {
        guard var session = sessions[id] else { return }
        
        switch status {
        case .completed: session.complete()
        case .failed: session.fail()
        case .cancelled: session.cancel()
        case .active: break
        }
        
        sessions[id] = session
        
        if currentSessionId == id {
            currentSessionId = nil
        }
    }
    
    public func currentSession() async -> EvidenceSession? {
        guard let id = currentSessionId else { return nil }
        return sessions[id]
    }
    
    public func addItem(_ item: EvidenceItem) async {
        // Enforce max items limit
        if items.count >= maxItems {
            items.removeFirst()
        }
        
        items.append(item)
        
        // Update session count
        if let sessionId = item.metadata.sessionId,
           var session = sessions[sessionId] {
            session.incrementCount()
            sessions[sessionId] = session
        }
    }
    
    public func addLog(message: String, level: EvidencePriority, source: String, category: EvidenceCategory) async {
        let item = EvidenceItem(
            type: .log,
            category: category,
            priority: level,
            title: "Log: \(source)",
            description: "",
            content: message,
            metadata: EvidenceMetadata(
                source: source,
                sessionId: currentSessionId
            )
        )
        await addItem(item)
    }
    
    public func addError(_ error: Error, context: String, category: EvidenceCategory) async {
        let item = EvidenceItem(
            type: .errorTrace,
            category: category,
            priority: .high,
            title: "Error: \(context)",
            description: String(describing: type(of: error)),
            content: error.localizedDescription,
            metadata: EvidenceMetadata(
                source: context,
                sessionId: currentSessionId
            )
        )
        await addItem(item)
    }
    
    public func addMetric(name: String, value: Double, unit: String?, category: EvidenceCategory) async {
        let content = unit != nil ? "\(value) \(unit!)" : "\(value)"
        let item = EvidenceItem(
            type: .metric,
            category: category,
            priority: .normal,
            title: "Metric: \(name)",
            description: "",
            content: content,
            metadata: EvidenceMetadata(
                source: "metrics",
                sessionId: currentSessionId,
                properties: ["name": name, "value": "\(value)"]
            )
        )
        await addItem(item)
    }
    
    public func allItems() async -> [EvidenceItem] {
        items
    }
    
    public func items(matching filter: EvidenceFilter) async -> [EvidenceItem] {
        items.filter { filter.matches($0) }
    }
    
    public func allSessions() async -> [EvidenceSession] {
        Array(sessions.values).sorted { $0.startTime > $1.startTime }
    }
    
    public func session(id: String) async -> EvidenceSession? {
        sessions[id]
    }
    
    public func generateReport(title: String, description: String, filter: EvidenceFilter?) async -> EvidenceReport {
        let filteredItems = filter != nil ? items.filter { filter!.matches($0) } : items
        let allSessionsList = Array(sessions.values)
        
        return EvidenceReport(
            title: title,
            description: description,
            sessions: allSessionsList,
            items: filteredItems
        )
    }
    
    public func statistics() async -> EvidenceStatistics {
        var byType: [EvidenceType: Int] = [:]
        var byCategory: [EvidenceCategory: Int] = [:]
        var byPriority: [EvidencePriority: Int] = [:]
        var redactedCount = 0
        var oldest: Date?
        var newest: Date?
        
        for item in items {
            byType[item.type, default: 0] += 1
            byCategory[item.category, default: 0] += 1
            byPriority[item.priority, default: 0] += 1
            if item.redacted { redactedCount += 1 }
            
            if oldest == nil || item.metadata.timestamp < oldest! {
                oldest = item.metadata.timestamp
            }
            if newest == nil || item.metadata.timestamp > newest! {
                newest = item.metadata.timestamp
            }
        }
        
        return EvidenceStatistics(
            totalItems: items.count,
            byType: byType,
            byCategory: byCategory,
            byPriority: byPriority,
            redactedCount: redactedCount,
            sessionCount: sessions.count,
            oldestTimestamp: oldest,
            newestTimestamp: newest
        )
    }
    
    public func clear() async {
        items.removeAll()
        sessions.removeAll()
        currentSessionId = nil
    }
    
    public func clearOlderThan(_ date: Date) async {
        items.removeAll { $0.metadata.timestamp < date }
        sessions = sessions.filter { $0.value.startTime >= date }
    }
}

// MARK: - Composite Evidence Collector

/// Collector that forwards to multiple collectors.
public actor CompositeEvidenceCollector: EvidenceCollector {
    private var collectors: [EvidenceCollector]
    private let primary: EvidenceCollector
    
    public init(primary: EvidenceCollector, secondaries: [EvidenceCollector] = []) {
        self.primary = primary
        self.collectors = [primary] + secondaries
    }
    
    public func startSession(name: String, purpose: String, deviceId: String?) async -> EvidenceSession {
        let session = await primary.startSession(name: name, purpose: purpose, deviceId: deviceId)
        for collector in collectors.dropFirst() {
            _ = await collector.startSession(name: name, purpose: purpose, deviceId: deviceId)
        }
        return session
    }
    
    public func endSession(id: String, status: EvidenceSession.SessionStatus) async {
        for collector in collectors {
            await collector.endSession(id: id, status: status)
        }
    }
    
    public func currentSession() async -> EvidenceSession? {
        await primary.currentSession()
    }
    
    public func addItem(_ item: EvidenceItem) async {
        for collector in collectors {
            await collector.addItem(item)
        }
    }
    
    public func addLog(message: String, level: EvidencePriority, source: String, category: EvidenceCategory) async {
        for collector in collectors {
            await collector.addLog(message: message, level: level, source: source, category: category)
        }
    }
    
    public func addError(_ error: Error, context: String, category: EvidenceCategory) async {
        for collector in collectors {
            await collector.addError(error, context: context, category: category)
        }
    }
    
    public func addMetric(name: String, value: Double, unit: String?, category: EvidenceCategory) async {
        for collector in collectors {
            await collector.addMetric(name: name, value: value, unit: unit, category: category)
        }
    }
    
    public func allItems() async -> [EvidenceItem] {
        await primary.allItems()
    }
    
    public func items(matching filter: EvidenceFilter) async -> [EvidenceItem] {
        await primary.items(matching: filter)
    }
    
    public func allSessions() async -> [EvidenceSession] {
        await primary.allSessions()
    }
    
    public func session(id: String) async -> EvidenceSession? {
        await primary.session(id: id)
    }
    
    public func generateReport(title: String, description: String, filter: EvidenceFilter?) async -> EvidenceReport {
        await primary.generateReport(title: title, description: description, filter: filter)
    }
    
    public func statistics() async -> EvidenceStatistics {
        await primary.statistics()
    }
    
    public func clear() async {
        for collector in collectors {
            await collector.clear()
        }
    }
    
    public func clearOlderThan(_ date: Date) async {
        for collector in collectors {
            await collector.clearOlderThan(date)
        }
    }
}

// MARK: - Null Evidence Collector

/// Collector that discards all evidence (for production/testing).
public actor NullEvidenceCollector: EvidenceCollector {
    public init() {}
    
    public func startSession(name: String, purpose: String, deviceId: String?) async -> EvidenceSession {
        EvidenceSession(name: name, purpose: purpose, deviceId: deviceId)
    }
    
    public func endSession(id: String, status: EvidenceSession.SessionStatus) async {}
    public func currentSession() async -> EvidenceSession? { nil }
    public func addItem(_ item: EvidenceItem) async {}
    public func addLog(message: String, level: EvidencePriority, source: String, category: EvidenceCategory) async {}
    public func addError(_ error: Error, context: String, category: EvidenceCategory) async {}
    public func addMetric(name: String, value: Double, unit: String?, category: EvidenceCategory) async {}
    public func allItems() async -> [EvidenceItem] { [] }
    public func items(matching filter: EvidenceFilter) async -> [EvidenceItem] { [] }
    public func allSessions() async -> [EvidenceSession] { [] }
    public func session(id: String) async -> EvidenceSession? { nil }
    
    public func generateReport(title: String, description: String, filter: EvidenceFilter?) async -> EvidenceReport {
        EvidenceReport(title: title, description: description, sessions: [], items: [])
    }
    
    public func statistics() async -> EvidenceStatistics {
        EvidenceStatistics(
            totalItems: 0,
            byType: [:],
            byCategory: [:],
            byPriority: [:],
            redactedCount: 0,
            sessionCount: 0,
            oldestTimestamp: nil,
            newestTimestamp: nil
        )
    }
    
    public func clear() async {}
    public func clearOlderThan(_ date: Date) async {}
}

// MARK: - Evidence Item Builder

/// Fluent builder for creating evidence items.
public struct EvidenceItemBuilder: Sendable {
    private var type: EvidenceType = .log
    private var category: EvidenceCategory = .general
    private var priority: EvidencePriority = .normal
    private var title: String = ""
    private var description: String = ""
    private var content: String = ""
    private var source: String = ""
    private var deviceId: String?
    private var sessionId: String?
    private var tags: Set<String> = []
    private var properties: [String: String] = [:]
    private var redacted: Bool = false
    
    public init() {}
    
    public func type(_ type: EvidenceType) -> EvidenceItemBuilder {
        var builder = self
        builder.type = type
        return builder
    }
    
    public func category(_ category: EvidenceCategory) -> EvidenceItemBuilder {
        var builder = self
        builder.category = category
        return builder
    }
    
    public func priority(_ priority: EvidencePriority) -> EvidenceItemBuilder {
        var builder = self
        builder.priority = priority
        return builder
    }
    
    public func title(_ title: String) -> EvidenceItemBuilder {
        var builder = self
        builder.title = title
        return builder
    }
    
    public func description(_ description: String) -> EvidenceItemBuilder {
        var builder = self
        builder.description = description
        return builder
    }
    
    public func content(_ content: String) -> EvidenceItemBuilder {
        var builder = self
        builder.content = content
        return builder
    }
    
    public func source(_ source: String) -> EvidenceItemBuilder {
        var builder = self
        builder.source = source
        return builder
    }
    
    public func deviceId(_ deviceId: String) -> EvidenceItemBuilder {
        var builder = self
        builder.deviceId = deviceId
        return builder
    }
    
    public func sessionId(_ sessionId: String) -> EvidenceItemBuilder {
        var builder = self
        builder.sessionId = sessionId
        return builder
    }
    
    public func tag(_ tag: String) -> EvidenceItemBuilder {
        var builder = self
        builder.tags.insert(tag)
        return builder
    }
    
    public func property(_ key: String, _ value: String) -> EvidenceItemBuilder {
        var builder = self
        builder.properties[key] = value
        return builder
    }
    
    public func redacted(_ redacted: Bool = true) -> EvidenceItemBuilder {
        var builder = self
        builder.redacted = redacted
        return builder
    }
    
    public func build() -> EvidenceItem {
        EvidenceItem(
            type: type,
            category: category,
            priority: priority,
            title: title,
            description: description,
            content: content,
            metadata: EvidenceMetadata(
                source: source,
                deviceId: deviceId,
                sessionId: sessionId,
                tags: tags,
                properties: properties
            ),
            redacted: redacted
        )
    }
}

// MARK: - Evidence Exporter

/// Exports evidence reports to various formats.
public struct EvidenceExporter: Sendable {
    public init() {}
    
    /// Export report to JSON.
    public func exportJSON(_ report: EvidenceReport) throws -> Data {
        try report.toJSON()
    }
    
    /// Export report to formatted text.
    public func exportText(_ report: EvidenceReport) -> String {
        var lines: [String] = []
        
        lines.append("=" .padding(toLength: 60, withPad: "=", startingAt: 0))
        lines.append("EVIDENCE REPORT: \(report.title)")
        lines.append("=" .padding(toLength: 60, withPad: "=", startingAt: 0))
        lines.append("")
        lines.append("Created: \(ISO8601DateFormatter().string(from: report.createdAt))")
        lines.append("Description: \(report.description)")
        lines.append("")
        
        // Statistics
        lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
        lines.append("STATISTICS")
        lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
        lines.append("Total Items: \(report.statistics.totalItems)")
        lines.append("Sessions: \(report.statistics.sessionCount)")
        lines.append("Redacted: \(report.statistics.redactedCount)")
        lines.append("")
        
        // Sessions
        if !report.sessions.isEmpty {
            lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
            lines.append("SESSIONS")
            lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
            for session in report.sessions {
                lines.append("[\(session.status.rawValue.uppercased())] \(session.name)")
                lines.append("  Purpose: \(session.purpose)")
                lines.append("  Duration: \(String(format: "%.1f", session.duration))s")
                lines.append("  Items: \(session.itemCount)")
                lines.append("")
            }
        }
        
        // Items by priority
        let criticalItems = report.items.filter { $0.priority == .critical }
        if !criticalItems.isEmpty {
            lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
            lines.append("CRITICAL ITEMS")
            lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
            for item in criticalItems {
                lines.append("⚠️ \(item.title)")
                lines.append("   \(item.content)")
                lines.append("")
            }
        }
        
        // All items
        lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
        lines.append("ALL ITEMS (\(report.items.count))")
        lines.append("-" .padding(toLength: 40, withPad: "-", startingAt: 0))
        for item in report.items.prefix(100) {
            let timestamp = ISO8601DateFormatter().string(from: item.metadata.timestamp)
            lines.append("[\(timestamp)] [\(item.type.rawValue)] \(item.title)")
            if !item.content.isEmpty {
                lines.append("  \(item.content.prefix(200))")
            }
        }
        
        if report.items.count > 100 {
            lines.append("... and \(report.items.count - 100) more items")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export report to CSV.
    public func exportCSV(_ report: EvidenceReport) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("timestamp,type,category,priority,title,content,source,redacted")
        
        // Items
        for item in report.items {
            let timestamp = ISO8601DateFormatter().string(from: item.metadata.timestamp)
            let escapedTitle = escapeCSV(item.title)
            let escapedContent = escapeCSV(item.content)
            let escapedSource = escapeCSV(item.metadata.source)
            
            lines.append("\(timestamp),\(item.type.rawValue),\(item.category.rawValue),\(item.priority.rawValue),\(escapedTitle),\(escapedContent),\(escapedSource),\(item.redacted)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
