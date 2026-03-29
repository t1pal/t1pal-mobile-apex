// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// QualityDashboardExporter.swift - Quality dashboard data export
// Part of BLEKit
// Trace: EVID-006

import Foundation

// MARK: - Export Format

/// Supported export formats for quality data
public enum ExportFormat: String, Sendable, Codable, CaseIterable {
    case json           // Full JSON with all details
    case jsonCompact    // Minified JSON
    case csv            // Tabular CSV format
    case summary        // Human-readable summary
}

// MARK: - Dashboard Metrics

/// Aggregated quality metrics for dashboard display
public struct DashboardMetrics: Sendable, Codable, Equatable {
    /// Time period covered by these metrics
    public let period: MetricsPeriod
    
    /// Overall success rate across all devices
    public let overallSuccessRate: Double
    
    /// Total connection attempts
    public let totalAttempts: Int
    
    /// Total successful connections
    public let totalSuccesses: Int
    
    /// Total failures
    public let totalFailures: Int
    
    /// Success rate by device type
    public let successByDevice: [String: Double]
    
    /// Success rate by platform version
    public let successByPlatform: [String: Double]
    
    /// Success rate by firmware version
    public let successByFirmware: [String: Double]
    
    /// Top failure modes (sorted by frequency)
    public let topFailureModes: [FailureModeCount]
    
    /// Trend indicator (-1.0 to 1.0)
    public let trend: Double
    
    /// Average connection time in seconds
    public let avgConnectionTime: Double
    
    /// 95th percentile connection time
    public let p95ConnectionTime: Double
    
    /// Number of unique devices tested
    public let uniqueDevices: Int
    
    /// Number of unique platform versions
    public let uniquePlatforms: Int
    
    /// Generated timestamp
    public let generatedAt: Date
    
    public init(
        period: MetricsPeriod,
        overallSuccessRate: Double,
        totalAttempts: Int,
        totalSuccesses: Int,
        totalFailures: Int,
        successByDevice: [String: Double] = [:],
        successByPlatform: [String: Double] = [:],
        successByFirmware: [String: Double] = [:],
        topFailureModes: [FailureModeCount] = [],
        trend: Double = 0.0,
        avgConnectionTime: Double = 0.0,
        p95ConnectionTime: Double = 0.0,
        uniqueDevices: Int = 0,
        uniquePlatforms: Int = 0,
        generatedAt: Date = Date()
    ) {
        self.period = period
        self.overallSuccessRate = overallSuccessRate
        self.totalAttempts = totalAttempts
        self.totalSuccesses = totalSuccesses
        self.totalFailures = totalFailures
        self.successByDevice = successByDevice
        self.successByPlatform = successByPlatform
        self.successByFirmware = successByFirmware
        self.topFailureModes = topFailureModes
        self.trend = trend
        self.avgConnectionTime = avgConnectionTime
        self.p95ConnectionTime = p95ConnectionTime
        self.uniqueDevices = uniqueDevices
        self.uniquePlatforms = uniquePlatforms
        self.generatedAt = generatedAt
    }
    
    /// Empty metrics
    public static let empty = DashboardMetrics(
        period: .allTime,
        overallSuccessRate: 0.0,
        totalAttempts: 0,
        totalSuccesses: 0,
        totalFailures: 0
    )
}

/// Time period for metrics
public struct MetricsPeriod: Sendable, Codable, Equatable {
    public let start: Date?
    public let end: Date?
    public let label: String
    
    public init(start: Date? = nil, end: Date? = nil, label: String) {
        self.start = start
        self.end = end
        self.label = label
    }
    
    /// All time period
    public static let allTime = MetricsPeriod(label: "All Time")
    
    /// Last 24 hours
    public static var last24Hours: MetricsPeriod {
        let now = Date()
        return MetricsPeriod(
            start: now.addingTimeInterval(-86400),
            end: now,
            label: "Last 24 Hours"
        )
    }
    
    /// Last 7 days
    public static var last7Days: MetricsPeriod {
        let now = Date()
        return MetricsPeriod(
            start: now.addingTimeInterval(-7 * 86400),
            end: now,
            label: "Last 7 Days"
        )
    }
    
    /// Last 30 days
    public static var last30Days: MetricsPeriod {
        let now = Date()
        return MetricsPeriod(
            start: now.addingTimeInterval(-30 * 86400),
            end: now,
            label: "Last 30 Days"
        )
    }
}

/// Failure mode with count
public struct FailureModeCount: Sendable, Codable, Equatable {
    public let mode: String
    public let count: Int
    public let percentage: Double
    
    public init(mode: String, count: Int, percentage: Double) {
        self.mode = mode
        self.count = count
        self.percentage = percentage
    }
}

// MARK: - Quality Snapshot

/// Point-in-time quality state snapshot
public struct QualitySnapshot: Sendable, Codable, Equatable {
    /// Unique snapshot identifier
    public let id: String
    
    /// Snapshot timestamp
    public let timestamp: Date
    
    /// Dashboard metrics
    public let metrics: DashboardMetrics
    
    /// Version correlation summary
    public let versionSummary: VersionSummary?
    
    /// Platform correlation summary
    public let platformSummary: PlatformSummary?
    
    /// Failure analysis summary
    public let failureSummary: FailureSummary?
    
    /// App version that generated this snapshot
    public let appVersion: String?
    
    /// Device identifier (anonymized)
    public let deviceId: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        metrics: DashboardMetrics,
        versionSummary: VersionSummary? = nil,
        platformSummary: PlatformSummary? = nil,
        failureSummary: FailureSummary? = nil,
        appVersion: String? = nil,
        deviceId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.metrics = metrics
        self.versionSummary = versionSummary
        self.platformSummary = platformSummary
        self.failureSummary = failureSummary
        self.appVersion = appVersion
        self.deviceId = deviceId
    }
}

/// Summary of version correlation data
public struct VersionSummary: Sendable, Codable, Equatable {
    public let bestVersion: String?
    public let worstVersion: String?
    public let versionCount: Int
    public let overallTrend: Double
    
    public init(
        bestVersion: String? = nil,
        worstVersion: String? = nil,
        versionCount: Int = 0,
        overallTrend: Double = 0.0
    ) {
        self.bestVersion = bestVersion
        self.worstVersion = worstVersion
        self.versionCount = versionCount
        self.overallTrend = overallTrend
    }
}

/// Summary of platform correlation data
public struct PlatformSummary: Sendable, Codable, Equatable {
    public let bestPlatform: String?
    public let worstPlatform: String?
    public let platformCount: Int
    public let overallTrend: Double
    
    public init(
        bestPlatform: String? = nil,
        worstPlatform: String? = nil,
        platformCount: Int = 0,
        overallTrend: Double = 0.0
    ) {
        self.bestPlatform = bestPlatform
        self.worstPlatform = worstPlatform
        self.platformCount = platformCount
        self.overallTrend = overallTrend
    }
}

/// Summary of failure analysis
public struct FailureSummary: Sendable, Codable, Equatable {
    public let totalFailures: Int
    public let uniqueFailureModes: Int
    public let topCategory: String?
    public let criticalCount: Int
    
    public init(
        totalFailures: Int = 0,
        uniqueFailureModes: Int = 0,
        topCategory: String? = nil,
        criticalCount: Int = 0
    ) {
        self.totalFailures = totalFailures
        self.uniqueFailureModes = uniqueFailureModes
        self.topCategory = topCategory
        self.criticalCount = criticalCount
    }
}

// MARK: - Quality Dashboard Exporter

/// Exports quality data in various formats for dashboard consumption
public struct QualityDashboardExporter: Sendable {
    /// Export configuration
    public let config: ExportConfig
    
    public init(config: ExportConfig = .default) {
        self.config = config
    }
    
    /// Export metrics to JSON
    public func exportJSON(_ metrics: DashboardMetrics, compact: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if !compact {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(metrics)
    }
    
    /// Export snapshot to JSON
    public func exportSnapshot(_ snapshot: QualitySnapshot, compact: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if !compact {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(snapshot)
    }
    
    /// Export metrics to CSV
    public func exportCSV(_ metrics: DashboardMetrics) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("metric,value")
        
        // Core metrics
        lines.append("overall_success_rate,\(formatPercent(metrics.overallSuccessRate))")
        lines.append("total_attempts,\(metrics.totalAttempts)")
        lines.append("total_successes,\(metrics.totalSuccesses)")
        lines.append("total_failures,\(metrics.totalFailures)")
        lines.append("avg_connection_time,\(formatDouble(metrics.avgConnectionTime))")
        lines.append("p95_connection_time,\(formatDouble(metrics.p95ConnectionTime))")
        lines.append("trend,\(formatDouble(metrics.trend))")
        lines.append("unique_devices,\(metrics.uniqueDevices)")
        lines.append("unique_platforms,\(metrics.uniquePlatforms)")
        lines.append("period,\(escapeCSV(metrics.period.label))")
        lines.append("generated_at,\(formatDate(metrics.generatedAt))")
        
        return lines.joined(separator: "\n")
    }
    
    /// Export device breakdown to CSV
    public func exportDeviceBreakdownCSV(_ metrics: DashboardMetrics) -> String {
        var lines: [String] = []
        lines.append("device_type,success_rate")
        
        for (device, rate) in metrics.successByDevice.sorted(by: { $0.key < $1.key }) {
            lines.append("\(escapeCSV(device)),\(formatPercent(rate))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export platform breakdown to CSV
    public func exportPlatformBreakdownCSV(_ metrics: DashboardMetrics) -> String {
        var lines: [String] = []
        lines.append("platform_version,success_rate")
        
        for (platform, rate) in metrics.successByPlatform.sorted(by: { $0.key < $1.key }) {
            lines.append("\(escapeCSV(platform)),\(formatPercent(rate))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export failure modes to CSV
    public func exportFailureModesCSV(_ metrics: DashboardMetrics) -> String {
        var lines: [String] = []
        lines.append("failure_mode,count,percentage")
        
        for failure in metrics.topFailureModes {
            lines.append("\(escapeCSV(failure.mode)),\(failure.count),\(formatPercent(failure.percentage))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export human-readable summary
    public func exportSummary(_ metrics: DashboardMetrics) -> String {
        var lines: [String] = []
        
        lines.append("=== Quality Dashboard Summary ===")
        lines.append("Period: \(metrics.period.label)")
        lines.append("Generated: \(formatDate(metrics.generatedAt))")
        lines.append("")
        lines.append("Overall Success Rate: \(formatPercent(metrics.overallSuccessRate))")
        lines.append("Total Attempts: \(metrics.totalAttempts)")
        lines.append("  - Successes: \(metrics.totalSuccesses)")
        lines.append("  - Failures: \(metrics.totalFailures)")
        lines.append("")
        lines.append("Connection Performance:")
        lines.append("  - Average: \(formatDouble(metrics.avgConnectionTime))s")
        lines.append("  - P95: \(formatDouble(metrics.p95ConnectionTime))s")
        lines.append("")
        lines.append("Trend: \(formatTrend(metrics.trend))")
        lines.append("Unique Devices: \(metrics.uniqueDevices)")
        lines.append("Unique Platforms: \(metrics.uniquePlatforms)")
        
        if !metrics.topFailureModes.isEmpty {
            lines.append("")
            lines.append("Top Failure Modes:")
            for (index, failure) in metrics.topFailureModes.prefix(5).enumerated() {
                lines.append("  \(index + 1). \(failure.mode): \(failure.count) (\(formatPercent(failure.percentage)))")
            }
        }
        
        if !metrics.successByDevice.isEmpty {
            lines.append("")
            lines.append("Success by Device:")
            for (device, rate) in metrics.successByDevice.sorted(by: { $0.value > $1.value }) {
                lines.append("  - \(device): \(formatPercent(rate))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export in specified format
    public func export(_ metrics: DashboardMetrics, format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            return try exportJSON(metrics, compact: false)
        case .jsonCompact:
            return try exportJSON(metrics, compact: true)
        case .csv:
            return exportCSV(metrics).data(using: .utf8) ?? Data()
        case .summary:
            return exportSummary(metrics).data(using: .utf8) ?? Data()
        }
    }
    
    // MARK: - Private Helpers
    
    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
    
    private func formatDouble(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
    
    private func formatTrend(_ trend: Double) -> String {
        if trend > 0.05 {
            return "↑ Improving (\(formatPercent(trend)))"
        } else if trend < -0.05 {
            return "↓ Declining (\(formatPercent(trend)))"
        } else {
            return "→ Stable"
        }
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

/// Export configuration
public struct ExportConfig: Sendable, Codable, Equatable {
    /// Include device breakdown
    public let includeDeviceBreakdown: Bool
    
    /// Include platform breakdown
    public let includePlatformBreakdown: Bool
    
    /// Include firmware breakdown
    public let includeFirmwareBreakdown: Bool
    
    /// Maximum failure modes to include
    public let maxFailureModes: Int
    
    /// Include timestamps
    public let includeTimestamps: Bool
    
    public init(
        includeDeviceBreakdown: Bool = true,
        includePlatformBreakdown: Bool = true,
        includeFirmwareBreakdown: Bool = true,
        maxFailureModes: Int = 10,
        includeTimestamps: Bool = true
    ) {
        self.includeDeviceBreakdown = includeDeviceBreakdown
        self.includePlatformBreakdown = includePlatformBreakdown
        self.includeFirmwareBreakdown = includeFirmwareBreakdown
        self.maxFailureModes = maxFailureModes
        self.includeTimestamps = includeTimestamps
    }
    
    /// Default configuration
    public static let `default` = ExportConfig()
    
    /// Minimal configuration (core metrics only)
    public static let minimal = ExportConfig(
        includeDeviceBreakdown: false,
        includePlatformBreakdown: false,
        includeFirmwareBreakdown: false,
        maxFailureModes: 5,
        includeTimestamps: false
    )
}

// MARK: - Metrics Builder

/// Builder for constructing DashboardMetrics from various sources
public struct MetricsBuilder: Sendable {
    private var period: MetricsPeriod = .allTime
    private var attempts: [ConnectionAttempt] = []
    private var connectionTimes: [Double] = []
    
    public init() {}
    
    /// Set the time period
    public mutating func setPeriod(_ period: MetricsPeriod) {
        self.period = period
    }
    
    /// Add a connection attempt
    public mutating func addAttempt(_ attempt: ConnectionAttempt) {
        attempts.append(attempt)
        if let time = attempt.connectionTime {
            connectionTimes.append(time)
        }
    }
    
    /// Add multiple attempts
    public mutating func addAttempts(_ newAttempts: [ConnectionAttempt]) {
        for attempt in newAttempts {
            addAttempt(attempt)
        }
    }
    
    /// Build the metrics
    public func build() -> DashboardMetrics {
        let successes = attempts.filter { $0.success }
        let failures = attempts.filter { !$0.success }
        
        let overallSuccessRate = attempts.isEmpty ? 0.0 :
            Double(successes.count) / Double(attempts.count)
        
        // Group by device
        var deviceGroups: [String: [ConnectionAttempt]] = [:]
        for attempt in attempts {
            deviceGroups[attempt.deviceType, default: []].append(attempt)
        }
        let successByDevice = deviceGroups.mapValues { group in
            Double(group.filter { $0.success }.count) / Double(group.count)
        }
        
        // Group by platform
        var platformGroups: [String: [ConnectionAttempt]] = [:]
        for attempt in attempts {
            platformGroups[attempt.platformVersion, default: []].append(attempt)
        }
        let successByPlatform = platformGroups.mapValues { group in
            Double(group.filter { $0.success }.count) / Double(group.count)
        }
        
        // Group by firmware
        var firmwareGroups: [String: [ConnectionAttempt]] = [:]
        for attempt in attempts {
            if let fw = attempt.firmwareVersion {
                firmwareGroups[fw, default: []].append(attempt)
            }
        }
        let successByFirmware = firmwareGroups.mapValues { group in
            Double(group.filter { $0.success }.count) / Double(group.count)
        }
        
        // Count failure modes
        var failureCounts: [String: Int] = [:]
        for failure in failures {
            if let reason = failure.failureReason {
                failureCounts[reason, default: 0] += 1
            }
        }
        let topFailureModes = failureCounts
            .map { FailureModeCount(
                mode: $0.key,
                count: $0.value,
                percentage: Double($0.value) / Double(max(failures.count, 1))
            )}
            .sorted { $0.count > $1.count }
        
        // Calculate connection time statistics
        let avgConnectionTime = connectionTimes.isEmpty ? 0.0 :
            connectionTimes.reduce(0.0, +) / Double(connectionTimes.count)
        
        let p95ConnectionTime: Double
        if connectionTimes.isEmpty {
            p95ConnectionTime = 0.0
        } else {
            let sorted = connectionTimes.sorted()
            let index = Int(Double(sorted.count) * 0.95)
            p95ConnectionTime = sorted[min(index, sorted.count - 1)]
        }
        
        return DashboardMetrics(
            period: period,
            overallSuccessRate: overallSuccessRate,
            totalAttempts: attempts.count,
            totalSuccesses: successes.count,
            totalFailures: failures.count,
            successByDevice: successByDevice,
            successByPlatform: successByPlatform,
            successByFirmware: successByFirmware,
            topFailureModes: topFailureModes,
            trend: 0.0, // Would need historical data to calculate
            avgConnectionTime: avgConnectionTime,
            p95ConnectionTime: p95ConnectionTime,
            uniqueDevices: Set(attempts.map { $0.deviceType }).count,
            uniquePlatforms: Set(attempts.map { $0.platformVersion }).count
        )
    }
}

/// Connection attempt for metrics building
public struct ConnectionAttempt: Sendable, Codable, Equatable {
    public let success: Bool
    public let deviceType: String
    public let platformVersion: String
    public let firmwareVersion: String?
    public let connectionTime: Double?
    public let failureReason: String?
    public let timestamp: Date
    
    public init(
        success: Bool,
        deviceType: String,
        platformVersion: String,
        firmwareVersion: String? = nil,
        connectionTime: Double? = nil,
        failureReason: String? = nil,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.deviceType = deviceType
        self.platformVersion = platformVersion
        self.firmwareVersion = firmwareVersion
        self.connectionTime = connectionTime
        self.failureReason = failureReason
        self.timestamp = timestamp
    }
}

// MARK: - Dashboard API Types

/// API response wrapper for dashboard data
public struct DashboardResponse: Sendable, Codable, Equatable {
    public let success: Bool
    public let data: DashboardMetrics?
    public let error: String?
    public let timestamp: Date
    
    public init(
        success: Bool,
        data: DashboardMetrics? = nil,
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.data = data
        self.error = error
        self.timestamp = timestamp
    }
    
    /// Success response
    public static func success(_ metrics: DashboardMetrics) -> DashboardResponse {
        DashboardResponse(success: true, data: metrics)
    }
    
    /// Error response
    public static func error(_ message: String) -> DashboardResponse {
        DashboardResponse(success: false, error: message)
    }
}

/// Batch export request
public struct BatchExportRequest: Sendable, Codable, Equatable {
    public let snapshots: [QualitySnapshot]
    public let format: ExportFormat
    public let includeAggregates: Bool
    
    public init(
        snapshots: [QualitySnapshot],
        format: ExportFormat = .json,
        includeAggregates: Bool = true
    ) {
        self.snapshots = snapshots
        self.format = format
        self.includeAggregates = includeAggregates
    }
}

/// Batch export result
public struct BatchExportResult: Sendable, Codable, Equatable {
    public let snapshotCount: Int
    public let exportedAt: Date
    public let format: ExportFormat
    public let dataSize: Int
    
    public init(
        snapshotCount: Int,
        exportedAt: Date = Date(),
        format: ExportFormat,
        dataSize: Int
    ) {
        self.snapshotCount = snapshotCount
        self.exportedAt = exportedAt
        self.format = format
        self.dataSize = dataSize
    }
}

// MARK: - Aggregate Exporter

/// Exports aggregated data across multiple snapshots
public struct AggregateExporter: Sendable {
    public init() {}
    
    /// Aggregate multiple snapshots into combined metrics
    public func aggregate(_ snapshots: [QualitySnapshot]) -> DashboardMetrics {
        guard !snapshots.isEmpty else { return .empty }
        
        var totalAttempts = 0
        var totalSuccesses = 0
        var totalFailures = 0
        var allConnectionTimes: [Double] = []
        var deviceRates: [String: (successes: Int, total: Int)] = [:]
        var platformRates: [String: (successes: Int, total: Int)] = [:]
        var failureCounts: [String: Int] = [:]
        
        for snapshot in snapshots {
            let m = snapshot.metrics
            totalAttempts += m.totalAttempts
            totalSuccesses += m.totalSuccesses
            totalFailures += m.totalFailures
            
            if m.avgConnectionTime > 0 {
                // Weight by attempt count
                for _ in 0..<m.totalSuccesses {
                    allConnectionTimes.append(m.avgConnectionTime)
                }
            }
            
            for (device, rate) in m.successByDevice {
                let current = deviceRates[device] ?? (0, 0)
                // Estimate counts from rate
                let estimated = Int(rate * Double(m.totalAttempts) / Double(m.successByDevice.count))
                deviceRates[device] = (current.successes + estimated, current.total + m.totalAttempts / m.successByDevice.count)
            }
            
            for (platform, rate) in m.successByPlatform {
                let current = platformRates[platform] ?? (0, 0)
                let estimated = Int(rate * Double(m.totalAttempts) / Double(max(m.successByPlatform.count, 1)))
                platformRates[platform] = (current.successes + estimated, current.total + m.totalAttempts / max(m.successByPlatform.count, 1))
            }
            
            for failure in m.topFailureModes {
                failureCounts[failure.mode, default: 0] += failure.count
            }
        }
        
        let overallSuccessRate = totalAttempts > 0 ?
            Double(totalSuccesses) / Double(totalAttempts) : 0.0
        
        let avgConnectionTime = allConnectionTimes.isEmpty ? 0.0 :
            allConnectionTimes.reduce(0.0, +) / Double(allConnectionTimes.count)
        
        let p95ConnectionTime: Double
        if allConnectionTimes.isEmpty {
            p95ConnectionTime = 0.0
        } else {
            let sorted = allConnectionTimes.sorted()
            let index = Int(Double(sorted.count) * 0.95)
            p95ConnectionTime = sorted[min(index, sorted.count - 1)]
        }
        
        let successByDevice = deviceRates.mapValues { pair in
            pair.total > 0 ? Double(pair.successes) / Double(pair.total) : 0.0
        }
        
        let successByPlatform = platformRates.mapValues { pair in
            pair.total > 0 ? Double(pair.successes) / Double(pair.total) : 0.0
        }
        
        let topFailureModes = failureCounts
            .map { FailureModeCount(
                mode: $0.key,
                count: $0.value,
                percentage: Double($0.value) / Double(max(totalFailures, 1))
            )}
            .sorted { $0.count > $1.count }
        
        // Determine period from snapshots
        let timestamps = snapshots.map { $0.timestamp }
        let start = timestamps.min()
        let end = timestamps.max()
        let period = MetricsPeriod(
            start: start,
            end: end,
            label: "Aggregated (\(snapshots.count) snapshots)"
        )
        
        return DashboardMetrics(
            period: period,
            overallSuccessRate: overallSuccessRate,
            totalAttempts: totalAttempts,
            totalSuccesses: totalSuccesses,
            totalFailures: totalFailures,
            successByDevice: successByDevice,
            successByPlatform: successByPlatform,
            successByFirmware: [:],
            topFailureModes: topFailureModes,
            trend: calculateTrend(snapshots),
            avgConnectionTime: avgConnectionTime,
            p95ConnectionTime: p95ConnectionTime,
            uniqueDevices: Set(snapshots.flatMap { $0.metrics.successByDevice.keys }).count,
            uniquePlatforms: Set(snapshots.flatMap { $0.metrics.successByPlatform.keys }).count
        )
    }
    
    /// Calculate trend from snapshots (oldest to newest)
    private func calculateTrend(_ snapshots: [QualitySnapshot]) -> Double {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return 0.0 }
        
        let first = sorted.first!.metrics.overallSuccessRate
        let last = sorted.last!.metrics.overallSuccessRate
        
        return last - first
    }
    
    /// Export batch of snapshots
    public func exportBatch(_ request: BatchExportRequest) throws -> (data: Data, result: BatchExportResult) {
        let exporter = QualityDashboardExporter()
        
        let dataToExport: Data
        if request.includeAggregates {
            let aggregated = aggregate(request.snapshots)
            dataToExport = try exporter.export(aggregated, format: request.format)
        } else {
            // Export each snapshot
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            dataToExport = try encoder.encode(request.snapshots)
        }
        
        let result = BatchExportResult(
            snapshotCount: request.snapshots.count,
            format: request.format,
            dataSize: dataToExport.count
        )
        
        return (dataToExport, result)
    }
}
