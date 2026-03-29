// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ProtocolReport.swift
// BLEKit
//
// Standardized JSON schema for protocol attempt reports.
// Provides structured diagnostics for connection/auth attempts.
//
// INSTR-004: ProtocolReport JSON schema

import Foundation

// MARK: - Protocol Phase

/// Phase of a protocol session.
public enum ProtocolPhase: String, Sendable, Codable, CaseIterable {
    case discovery
    case connection
    case bonding
    case authentication
    case serviceDiscovery
    case characteristicDiscovery
    case subscription
    case dataExchange
    case commandExecution
    case disconnection
    case cleanup
}

/// Status of a protocol phase.
public enum PhaseStatus: String, Sendable, Codable {
    case pending
    case inProgress
    case succeeded
    case failed
    case skipped
    case timedOut
    case cancelled
}

// MARK: - Phase Result

/// Result of a protocol phase execution.
public struct PhaseResult: Sendable, Equatable, Codable {
    public let phase: ProtocolPhase
    public let status: PhaseStatus
    public let startTime: Date
    public let endTime: Date?
    public let durationMs: Int?
    public let errorCode: String?
    public let errorMessage: String?
    public let retryCount: Int
    public let metadata: [String: String]
    
    public init(
        phase: ProtocolPhase,
        status: PhaseStatus,
        startTime: Date,
        endTime: Date? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.phase = phase
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = endTime.map { Int($0.timeIntervalSince(startTime) * 1000) }
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.metadata = metadata
    }
    
    public var isSuccess: Bool { status == .succeeded }
    public var isFailure: Bool { status == .failed || status == .timedOut }
    
    public static func success(
        phase: ProtocolPhase,
        startTime: Date,
        endTime: Date,
        metadata: [String: String] = [:]
    ) -> PhaseResult {
        PhaseResult(
            phase: phase,
            status: .succeeded,
            startTime: startTime,
            endTime: endTime,
            metadata: metadata
        )
    }
    
    public static func failure(
        phase: ProtocolPhase,
        startTime: Date,
        endTime: Date,
        errorCode: String,
        errorMessage: String,
        retryCount: Int = 0
    ) -> PhaseResult {
        PhaseResult(
            phase: phase,
            status: .failed,
            startTime: startTime,
            endTime: endTime,
            errorCode: errorCode,
            errorMessage: errorMessage,
            retryCount: retryCount
        )
    }
    
    public static func timeout(
        phase: ProtocolPhase,
        startTime: Date,
        endTime: Date,
        retryCount: Int = 0
    ) -> PhaseResult {
        PhaseResult(
            phase: phase,
            status: .timedOut,
            startTime: startTime,
            endTime: endTime,
            errorCode: "TIMEOUT",
            errorMessage: "Phase timed out",
            retryCount: retryCount
        )
    }
}

// MARK: - Attempt Record

/// Record of a single connection/operation attempt.
public struct AttemptRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let attemptNumber: Int
    public let startTime: Date
    public let endTime: Date?
    public let success: Bool
    public let phases: [PhaseResult]
    public let errorCode: String?
    public let errorMessage: String?
    public let deviceId: String?
    public let rssi: Int?
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        attemptNumber: Int,
        startTime: Date,
        endTime: Date? = nil,
        success: Bool,
        phases: [PhaseResult] = [],
        errorCode: String? = nil,
        errorMessage: String? = nil,
        deviceId: String? = nil,
        rssi: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.attemptNumber = attemptNumber
        self.startTime = startTime
        self.endTime = endTime
        self.success = success
        self.phases = phases
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.deviceId = deviceId
        self.rssi = rssi
        self.metadata = metadata
    }
    
    public var durationMs: Int? {
        endTime.map { Int($0.timeIntervalSince(startTime) * 1000) }
    }
    
    public var failedPhase: PhaseResult? {
        phases.first { $0.isFailure }
    }
    
    public var completedPhases: [PhaseResult] {
        phases.filter { $0.isSuccess }
    }
    
    public var totalRetries: Int {
        phases.reduce(0) { $0 + $1.retryCount }
    }
}

// MARK: - Protocol Metrics

/// Timing and performance metrics for a protocol session.
public struct ProtocolMetrics: Sendable, Equatable, Codable {
    public let totalDurationMs: Int
    public let discoveryDurationMs: Int?
    public let connectionDurationMs: Int?
    public let authenticationDurationMs: Int?
    public let dataExchangeDurationMs: Int?
    public let averageRssi: Int?
    public let minRssi: Int?
    public let maxRssi: Int?
    public let bytesTransferred: Int
    public let packetsTransferred: Int
    public let retryCount: Int
    public let timeoutCount: Int
    
    public init(
        totalDurationMs: Int,
        discoveryDurationMs: Int? = nil,
        connectionDurationMs: Int? = nil,
        authenticationDurationMs: Int? = nil,
        dataExchangeDurationMs: Int? = nil,
        averageRssi: Int? = nil,
        minRssi: Int? = nil,
        maxRssi: Int? = nil,
        bytesTransferred: Int = 0,
        packetsTransferred: Int = 0,
        retryCount: Int = 0,
        timeoutCount: Int = 0
    ) {
        self.totalDurationMs = totalDurationMs
        self.discoveryDurationMs = discoveryDurationMs
        self.connectionDurationMs = connectionDurationMs
        self.authenticationDurationMs = authenticationDurationMs
        self.dataExchangeDurationMs = dataExchangeDurationMs
        self.averageRssi = averageRssi
        self.minRssi = minRssi
        self.maxRssi = maxRssi
        self.bytesTransferred = bytesTransferred
        self.packetsTransferred = packetsTransferred
        self.retryCount = retryCount
        self.timeoutCount = timeoutCount
    }
    
    public static func calculate(from attempts: [AttemptRecord]) -> ProtocolMetrics {
        guard !attempts.isEmpty else {
            return ProtocolMetrics(totalDurationMs: 0)
        }
        
        var totalDuration = 0
        var discoveryDuration: Int?
        var connectionDuration: Int?
        var authDuration: Int?
        var dataDuration: Int?
        var rssiValues: [Int] = []
        var retries = 0
        var timeouts = 0
        
        for attempt in attempts {
            if let duration = attempt.durationMs {
                totalDuration += duration
            }
            
            for phase in attempt.phases {
                if let duration = phase.durationMs {
                    switch phase.phase {
                    case .discovery:
                        discoveryDuration = (discoveryDuration ?? 0) + duration
                    case .connection:
                        connectionDuration = (connectionDuration ?? 0) + duration
                    case .authentication:
                        authDuration = (authDuration ?? 0) + duration
                    case .dataExchange:
                        dataDuration = (dataDuration ?? 0) + duration
                    default:
                        break
                    }
                }
                
                retries += phase.retryCount
                if phase.status == .timedOut {
                    timeouts += 1
                }
            }
            
            if let rssi = attempt.rssi {
                rssiValues.append(rssi)
            }
        }
        
        let avgRssi = rssiValues.isEmpty ? nil : rssiValues.reduce(0, +) / rssiValues.count
        let minRssi = rssiValues.min()
        let maxRssi = rssiValues.max()
        
        return ProtocolMetrics(
            totalDurationMs: totalDuration,
            discoveryDurationMs: discoveryDuration,
            connectionDurationMs: connectionDuration,
            authenticationDurationMs: authDuration,
            dataExchangeDurationMs: dataDuration,
            averageRssi: avgRssi,
            minRssi: minRssi,
            maxRssi: maxRssi,
            retryCount: retries,
            timeoutCount: timeouts
        )
    }
}

// MARK: - Device Info

/// Device information for the report.
public struct ReportDeviceInfo: Sendable, Equatable, Codable {
    public let deviceId: String
    public let name: String?
    public let manufacturer: String?
    public let model: String?
    public let firmware: String?
    public let hardware: String?
    public let serialNumber: String?
    
    public init(
        deviceId: String,
        name: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        firmware: String? = nil,
        hardware: String? = nil,
        serialNumber: String? = nil
    ) {
        self.deviceId = deviceId
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.firmware = firmware
        self.hardware = hardware
        self.serialNumber = serialNumber
    }
    
    public func redacted() -> ReportDeviceInfo {
        ReportDeviceInfo(
            deviceId: "[REDACTED]",
            name: name.map { _ in "[REDACTED]" },
            manufacturer: manufacturer,
            model: model,
            firmware: firmware,
            hardware: hardware,
            serialNumber: serialNumber.map { _ in "[REDACTED]" }
        )
    }
}

// MARK: - Platform Info

/// Platform information for the report.
public struct ReportPlatformInfo: Sendable, Equatable, Codable {
    public let os: String
    public let osVersion: String
    public let appVersion: String
    public let appBuild: String?
    public let deviceModel: String?
    public let locale: String?
    public let timezone: String?
    
    public init(
        os: String,
        osVersion: String,
        appVersion: String,
        appBuild: String? = nil,
        deviceModel: String? = nil,
        locale: String? = nil,
        timezone: String? = nil
    ) {
        self.os = os
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.deviceModel = deviceModel
        self.locale = locale
        self.timezone = timezone
    }
    
    public static func current(appVersion: String, appBuild: String? = nil) -> ReportPlatformInfo {
        #if os(iOS)
        let os = "iOS"
        #elseif os(macOS)
        let os = "macOS"
        #elseif os(Linux)
        let os = "Linux"
        #else
        let os = "Unknown"
        #endif
        
        return ReportPlatformInfo(
            os: os,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: appVersion,
            appBuild: appBuild,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
}

// MARK: - Protocol Report

/// Complete protocol session report.
public struct ProtocolReport: Sendable, Equatable, Codable, Identifiable {
    public static let schemaVersion = "1.0.0"
    
    public let id: String
    public let schemaVersion: String
    public let protocolName: String
    public let protocolVersion: String
    public let createdAt: Date
    public let sessionId: String
    public let deviceInfo: ReportDeviceInfo?
    public let platformInfo: ReportPlatformInfo?
    public let attempts: [AttemptRecord]
    public let metrics: ProtocolMetrics
    public let success: Bool
    public let errorSummary: String?
    public let notes: String?
    public let tags: [String]
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        protocolName: String,
        protocolVersion: String,
        createdAt: Date = Date(),
        sessionId: String = UUID().uuidString,
        deviceInfo: ReportDeviceInfo? = nil,
        platformInfo: ReportPlatformInfo? = nil,
        attempts: [AttemptRecord] = [],
        success: Bool,
        errorSummary: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.schemaVersion = Self.schemaVersion
        self.protocolName = protocolName
        self.protocolVersion = protocolVersion
        self.createdAt = createdAt
        self.sessionId = sessionId
        self.deviceInfo = deviceInfo
        self.platformInfo = platformInfo
        self.attempts = attempts
        self.metrics = ProtocolMetrics.calculate(from: attempts)
        self.success = success
        self.errorSummary = errorSummary
        self.notes = notes
        self.tags = tags
        self.metadata = metadata
    }
    
    public var attemptCount: Int { attempts.count }
    public var successfulAttempts: Int { attempts.filter { $0.success }.count }
    public var failedAttempts: Int { attempts.filter { !$0.success }.count }
    
    public var successRate: Double {
        guard !attempts.isEmpty else { return 0 }
        return Double(successfulAttempts) / Double(attemptCount)
    }
    
    public var lastAttempt: AttemptRecord? { attempts.last }
    public var firstSuccessfulAttempt: AttemptRecord? { attempts.first { $0.success } }
    
    public func redacted() -> ProtocolReport {
        ProtocolReport(
            id: id,
            protocolName: protocolName,
            protocolVersion: protocolVersion,
            createdAt: createdAt,
            sessionId: sessionId,
            deviceInfo: deviceInfo?.redacted(),
            platformInfo: platformInfo,
            attempts: attempts,
            success: success,
            errorSummary: errorSummary,
            notes: notes,
            tags: tags,
            metadata: metadata
        )
    }
    
    public func toJSON(prettyPrint: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(self)
    }
    
    public static func fromJSON(_ data: Data) throws -> ProtocolReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProtocolReport.self, from: data)
    }
}

// MARK: - Protocol Report Builder

/// Fluent builder for creating protocol reports.
public final class ProtocolReportBuilder: @unchecked Sendable {
    private var protocolName: String = ""
    private var protocolVersion: String = "1.0"
    private var sessionId: String = UUID().uuidString
    private var deviceInfo: ReportDeviceInfo?
    private var platformInfo: ReportPlatformInfo?
    private var attempts: [AttemptRecord] = []
    private var currentAttempt: AttemptBuilder?
    private var notes: String?
    private var tags: [String] = []
    private var metadata: [String: String] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func protocolName(_ name: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        protocolName = name
        return self
    }
    
    public func protocolVersion(_ version: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        protocolVersion = version
        return self
    }
    
    public func sessionId(_ id: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        sessionId = id
        return self
    }
    
    public func deviceInfo(_ info: ReportDeviceInfo) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        deviceInfo = info
        return self
    }
    
    public func platformInfo(_ info: ReportPlatformInfo) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        platformInfo = info
        return self
    }
    
    public func notes(_ notes: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        self.notes = notes
        return self
    }
    
    public func tag(_ tag: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        tags.append(tag)
        return self
    }
    
    public func metadata(_ key: String, _ value: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        metadata[key] = value
        return self
    }
    
    public func startAttempt() -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        if let current = currentAttempt {
            attempts.append(current.build(attemptNumber: attempts.count + 1))
        }
        currentAttempt = AttemptBuilder()
        return self
    }
    
    public func recordPhase(_ result: PhaseResult) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        currentAttempt?.addPhase(result)
        return self
    }
    
    public func setDeviceId(_ deviceId: String) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        currentAttempt?.deviceId = deviceId
        return self
    }
    
    public func setRssi(_ rssi: Int) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        currentAttempt?.rssi = rssi
        return self
    }
    
    public func endAttempt(success: Bool, errorCode: String? = nil, errorMessage: String? = nil) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        currentAttempt?.success = success
        currentAttempt?.errorCode = errorCode
        currentAttempt?.errorMessage = errorMessage
        currentAttempt?.endTime = Date()
        if let current = currentAttempt {
            attempts.append(current.build(attemptNumber: attempts.count + 1))
        }
        currentAttempt = nil
        return self
    }
    
    public func addAttempt(_ attempt: AttemptRecord) -> ProtocolReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        attempts.append(attempt)
        return self
    }
    
    public func build() -> ProtocolReport {
        lock.lock()
        defer { lock.unlock() }
        
        // Finalize any in-progress attempt
        if let current = currentAttempt {
            attempts.append(current.build(attemptNumber: attempts.count + 1))
            currentAttempt = nil
        }
        
        let success = attempts.last?.success ?? false
        let errorSummary = attempts.last { !$0.success }?.errorMessage
        
        return ProtocolReport(
            protocolName: protocolName,
            protocolVersion: protocolVersion,
            sessionId: sessionId,
            deviceInfo: deviceInfo,
            platformInfo: platformInfo,
            attempts: attempts,
            success: success,
            errorSummary: errorSummary,
            notes: notes,
            tags: tags,
            metadata: metadata
        )
    }
}

/// Internal helper for building attempts.
private class AttemptBuilder {
    var startTime: Date = Date()
    var endTime: Date?
    var success: Bool = false
    var phases: [PhaseResult] = []
    var errorCode: String?
    var errorMessage: String?
    var deviceId: String?
    var rssi: Int?
    
    func addPhase(_ result: PhaseResult) {
        phases.append(result)
    }
    
    func build(attemptNumber: Int) -> AttemptRecord {
        AttemptRecord(
            attemptNumber: attemptNumber,
            startTime: startTime,
            endTime: endTime ?? Date(),
            success: success,
            phases: phases,
            errorCode: errorCode,
            errorMessage: errorMessage,
            deviceId: deviceId,
            rssi: rssi
        )
    }
}

// MARK: - Report Validation

/// Validation result for a protocol report.
public struct ReportValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    
    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
    
    public static let valid = ReportValidationResult(isValid: true)
    
    public static func invalid(_ errors: [String]) -> ReportValidationResult {
        ReportValidationResult(isValid: false, errors: errors)
    }
}

/// Validator for protocol reports.
public struct ProtocolReportValidator: Sendable {
    public init() {}
    
    public func validate(_ report: ProtocolReport) -> ReportValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Required fields
        if report.protocolName.isEmpty {
            errors.append("Protocol name is required")
        }
        
        if report.protocolVersion.isEmpty {
            errors.append("Protocol version is required")
        }
        
        if report.sessionId.isEmpty {
            errors.append("Session ID is required")
        }
        
        // Schema version check
        if report.schemaVersion != ProtocolReport.schemaVersion {
            warnings.append("Schema version mismatch: expected \(ProtocolReport.schemaVersion), got \(report.schemaVersion)")
        }
        
        // Attempt validation
        for (index, attempt) in report.attempts.enumerated() {
            if attempt.attemptNumber != index + 1 {
                warnings.append("Attempt \(index) has incorrect attempt number: \(attempt.attemptNumber)")
            }
            
            if attempt.endTime != nil && attempt.endTime! < attempt.startTime {
                errors.append("Attempt \(attempt.attemptNumber): end time before start time")
            }
            
            // Phase validation
            for phase in attempt.phases {
                if phase.endTime != nil && phase.endTime! < phase.startTime {
                    errors.append("Attempt \(attempt.attemptNumber), phase \(phase.phase.rawValue): end time before start time")
                }
            }
        }
        
        // Success consistency
        if report.success && report.attempts.isEmpty {
            warnings.append("Report marked as success but has no attempts")
        }
        
        if report.success && (report.attempts.last?.success == false) {
            warnings.append("Report marked as success but last attempt failed")
        }
        
        // Metrics validation
        if report.metrics.totalDurationMs < 0 {
            errors.append("Total duration cannot be negative")
        }
        
        return ReportValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}

// MARK: - Report Summary

/// Human-readable summary of a protocol report.
public struct ProtocolReportSummary: Sendable {
    public let report: ProtocolReport
    
    public init(_ report: ProtocolReport) {
        self.report = report
    }
    
    public var text: String {
        var lines: [String] = []
        
        lines.append("Protocol Report: \(report.protocolName) v\(report.protocolVersion)")
        lines.append("Session: \(report.sessionId)")
        lines.append("Created: \(ISO8601DateFormatter().string(from: report.createdAt))")
        lines.append("")
        
        lines.append("Status: \(report.success ? "✅ SUCCESS" : "❌ FAILED")")
        lines.append("Attempts: \(report.attemptCount) (\(report.successfulAttempts) succeeded, \(report.failedAttempts) failed)")
        lines.append("Success Rate: \(String(format: "%.1f%%", report.successRate * 100))")
        lines.append("")
        
        lines.append("Metrics:")
        lines.append("  Total Duration: \(report.metrics.totalDurationMs)ms")
        if let discovery = report.metrics.discoveryDurationMs {
            lines.append("  Discovery: \(discovery)ms")
        }
        if let connection = report.metrics.connectionDurationMs {
            lines.append("  Connection: \(connection)ms")
        }
        if let auth = report.metrics.authenticationDurationMs {
            lines.append("  Authentication: \(auth)ms")
        }
        if report.metrics.retryCount > 0 {
            lines.append("  Retries: \(report.metrics.retryCount)")
        }
        if report.metrics.timeoutCount > 0 {
            lines.append("  Timeouts: \(report.metrics.timeoutCount)")
        }
        
        if let deviceInfo = report.deviceInfo {
            lines.append("")
            lines.append("Device:")
            lines.append("  ID: \(deviceInfo.deviceId)")
            if let name = deviceInfo.name {
                lines.append("  Name: \(name)")
            }
            if let firmware = deviceInfo.firmware {
                lines.append("  Firmware: \(firmware)")
            }
        }
        
        if let errorSummary = report.errorSummary {
            lines.append("")
            lines.append("Error: \(errorSummary)")
        }
        
        if let notes = report.notes {
            lines.append("")
            lines.append("Notes: \(notes)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Report Aggregator

/// Aggregates multiple protocol reports.
public struct ProtocolReportAggregator: Sendable {
    public init() {}
    
    /// Aggregate statistics from multiple reports.
    public func aggregate(_ reports: [ProtocolReport]) -> AggregatedReportStats {
        guard !reports.isEmpty else {
            return AggregatedReportStats(
                reportCount: 0,
                totalAttempts: 0,
                successfulAttempts: 0,
                averageSuccessRate: 0,
                averageDurationMs: 0,
                totalRetries: 0,
                totalTimeouts: 0,
                protocolBreakdown: [:]
            )
        }
        
        var totalAttempts = 0
        var successfulAttempts = 0
        var totalDuration = 0
        var totalRetries = 0
        var totalTimeouts = 0
        var protocolBreakdown: [String: Int] = [:]
        
        for report in reports {
            totalAttempts += report.attemptCount
            successfulAttempts += report.successfulAttempts
            totalDuration += report.metrics.totalDurationMs
            totalRetries += report.metrics.retryCount
            totalTimeouts += report.metrics.timeoutCount
            protocolBreakdown[report.protocolName, default: 0] += 1
        }
        
        let avgSuccessRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        let avgDuration = reports.isEmpty ? 0 : totalDuration / reports.count
        
        return AggregatedReportStats(
            reportCount: reports.count,
            totalAttempts: totalAttempts,
            successfulAttempts: successfulAttempts,
            averageSuccessRate: avgSuccessRate,
            averageDurationMs: avgDuration,
            totalRetries: totalRetries,
            totalTimeouts: totalTimeouts,
            protocolBreakdown: protocolBreakdown
        )
    }
}

/// Aggregated statistics from multiple reports.
public struct AggregatedReportStats: Sendable, Equatable {
    public let reportCount: Int
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let averageSuccessRate: Double
    public let averageDurationMs: Int
    public let totalRetries: Int
    public let totalTimeouts: Int
    public let protocolBreakdown: [String: Int]
    
    public init(
        reportCount: Int,
        totalAttempts: Int,
        successfulAttempts: Int,
        averageSuccessRate: Double,
        averageDurationMs: Int,
        totalRetries: Int,
        totalTimeouts: Int,
        protocolBreakdown: [String: Int]
    ) {
        self.reportCount = reportCount
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.averageSuccessRate = averageSuccessRate
        self.averageDurationMs = averageDurationMs
        self.totalRetries = totalRetries
        self.totalTimeouts = totalTimeouts
        self.protocolBreakdown = protocolBreakdown
    }
}
