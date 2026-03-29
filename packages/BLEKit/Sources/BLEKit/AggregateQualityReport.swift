// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// AggregateQualityReport.swift
// BLEKit
//
// Cross-device/version aggregation for quality metrics.
// Provides aggregate analysis across devices, firmware versions, and time periods.
//
// INSTR-005: AggregateQualityReport schema

import Foundation

// MARK: - Quality Trend

/// Trend direction for quality metrics.
public enum QualityTrend: String, Sendable, Codable, CaseIterable {
    case improving
    case stable
    case degrading
    case insufficient
    case unknown
    
    public var symbol: String {
        switch self {
        case .improving: return "📈"
        case .stable: return "➡️"
        case .degrading: return "📉"
        case .insufficient: return "❓"
        case .unknown: return "—"
        }
    }
}

/// Trend analysis result with confidence.
public struct TrendAnalysis: Sendable, Equatable, Codable {
    public let trend: QualityTrend
    public let confidence: Double
    public let changePercent: Double?
    public let dataPoints: Int
    public let message: String
    
    public init(
        trend: QualityTrend,
        confidence: Double,
        changePercent: Double? = nil,
        dataPoints: Int,
        message: String = ""
    ) {
        self.trend = trend
        self.confidence = min(1.0, max(0.0, confidence))
        self.changePercent = changePercent
        self.dataPoints = dataPoints
        self.message = message
    }
    
    public static func insufficient(dataPoints: Int) -> TrendAnalysis {
        TrendAnalysis(
            trend: .insufficient,
            confidence: 0,
            dataPoints: dataPoints,
            message: "Insufficient data for trend analysis"
        )
    }
    
    public static func analyze(values: [Double], threshold: Double = 0.05) -> TrendAnalysis {
        guard values.count >= 3 else {
            return .insufficient(dataPoints: values.count)
        }
        
        // Simple linear regression
        let n = Double(values.count)
        let indices = (0..<values.count).map { Double($0) }
        let sumX = indices.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(indices, values).map { $0 * $1 }.reduce(0, +)
        let sumX2 = indices.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let avgY = sumY / n
        
        let changePercent = avgY != 0 ? (slope * n / avgY) * 100 : 0
        
        let trend: QualityTrend
        if abs(changePercent) < threshold * 100 {
            trend = .stable
        } else if changePercent > 0 {
            trend = .improving
        } else {
            trend = .degrading
        }
        
        // Confidence based on data consistency
        let variance = values.map { pow($0 - avgY, 2) }.reduce(0, +) / n
        let stdDev = sqrt(variance)
        let cv = avgY != 0 ? stdDev / abs(avgY) : 1.0
        let confidence = max(0, 1 - cv)
        
        return TrendAnalysis(
            trend: trend,
            confidence: confidence,
            changePercent: changePercent,
            dataPoints: values.count,
            message: "\(trend.symbol) \(String(format: "%.1f", changePercent))% change"
        )
    }
}

// MARK: - Time Series Quality

/// Quality data point for a time bucket.
public struct QualityDataPoint: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let successRate: Double
    public let attemptCount: Int
    public let successCount: Int
    public let averageLatencyMs: Int?
    public let errorCount: Int
    
    public init(
        timestamp: Date,
        successRate: Double,
        attemptCount: Int,
        successCount: Int,
        averageLatencyMs: Int? = nil,
        errorCount: Int = 0
    ) {
        self.timestamp = timestamp
        self.successRate = successRate
        self.attemptCount = attemptCount
        self.successCount = successCount
        self.averageLatencyMs = averageLatencyMs
        self.errorCount = errorCount
    }
}

/// Time bucket size for aggregation.
public enum TimeBucket: String, Sendable, Codable, CaseIterable {
    case hour
    case day
    case week
    case month
    
    public var seconds: TimeInterval {
        switch self {
        case .hour: return 3600
        case .day: return 86400
        case .week: return 604800
        case .month: return 2592000
        }
    }
}

/// Time series quality data.
public struct TimeSeriesQuality: Sendable, Equatable, Codable {
    public let bucket: TimeBucket
    public let startDate: Date
    public let endDate: Date
    public let dataPoints: [QualityDataPoint]
    public let trend: TrendAnalysis
    
    public init(
        bucket: TimeBucket,
        startDate: Date,
        endDate: Date,
        dataPoints: [QualityDataPoint]
    ) {
        self.bucket = bucket
        self.startDate = startDate
        self.endDate = endDate
        self.dataPoints = dataPoints
        self.trend = TrendAnalysis.analyze(values: dataPoints.map { $0.successRate })
    }
    
    public var averageSuccessRate: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.map { $0.successRate }.reduce(0, +) / Double(dataPoints.count)
    }
    
    public var totalAttempts: Int {
        dataPoints.map { $0.attemptCount }.reduce(0, +)
    }
    
    public var totalSuccesses: Int {
        dataPoints.map { $0.successCount }.reduce(0, +)
    }
    
    public var totalErrors: Int {
        dataPoints.map { $0.errorCount }.reduce(0, +)
    }
}

// MARK: - Device Quality Stats

/// Quality statistics for a specific device.
public struct DeviceQualityStats: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let deviceId: String
    public let deviceName: String?
    public let firstSeen: Date
    public let lastSeen: Date
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let successRate: Double
    public let averageLatencyMs: Int
    public let minLatencyMs: Int
    public let maxLatencyMs: Int
    public let totalRetries: Int
    public let totalTimeouts: Int
    public let errorBreakdown: [String: Int]
    
    public init(
        deviceId: String,
        deviceName: String? = nil,
        firstSeen: Date,
        lastSeen: Date,
        totalAttempts: Int,
        successfulAttempts: Int,
        averageLatencyMs: Int = 0,
        minLatencyMs: Int = 0,
        maxLatencyMs: Int = 0,
        totalRetries: Int = 0,
        totalTimeouts: Int = 0,
        errorBreakdown: [String: Int] = [:]
    ) {
        self.id = deviceId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.successRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        self.averageLatencyMs = averageLatencyMs
        self.minLatencyMs = minLatencyMs
        self.maxLatencyMs = maxLatencyMs
        self.totalRetries = totalRetries
        self.totalTimeouts = totalTimeouts
        self.errorBreakdown = errorBreakdown
    }
    
    public var failedAttempts: Int { totalAttempts - successfulAttempts }
    public var sessionCount: Int { totalAttempts }
    public var mostCommonError: String? {
        errorBreakdown.max { $0.value < $1.value }?.key
    }
    
    public func redacted() -> DeviceQualityStats {
        DeviceQualityStats(
            deviceId: "[REDACTED]",
            deviceName: deviceName.map { _ in "[REDACTED]" },
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            totalAttempts: totalAttempts,
            successfulAttempts: successfulAttempts,
            averageLatencyMs: averageLatencyMs,
            minLatencyMs: minLatencyMs,
            maxLatencyMs: maxLatencyMs,
            totalRetries: totalRetries,
            totalTimeouts: totalTimeouts,
            errorBreakdown: errorBreakdown
        )
    }
}

// MARK: - Version Quality Stats

/// Quality statistics for a specific firmware version.
public struct VersionQualityStats: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let version: String
    public let deviceCount: Int
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let successRate: Double
    public let averageLatencyMs: Int
    public let commonErrors: [String: Int]
    public let recommendation: VersionRecommendation
    
    public init(
        version: String,
        deviceCount: Int,
        totalAttempts: Int,
        successfulAttempts: Int,
        averageLatencyMs: Int = 0,
        commonErrors: [String: Int] = [:]
    ) {
        self.id = version
        self.version = version
        self.deviceCount = deviceCount
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.successRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        self.averageLatencyMs = averageLatencyMs
        self.commonErrors = commonErrors
        self.recommendation = Self.calculateRecommendation(successRate: self.successRate, attempts: totalAttempts)
    }
    
    private static func calculateRecommendation(successRate: Double, attempts: Int) -> VersionRecommendation {
        if attempts < 10 { return .insufficientData }
        if successRate >= 0.95 { return .recommended }
        if successRate >= 0.80 { return .acceptable }
        if successRate >= 0.60 { return .problematic }
        return .avoid
    }
}

/// Recommendation for a firmware version.
public enum VersionRecommendation: String, Sendable, Codable {
    case recommended
    case acceptable
    case problematic
    case avoid
    case insufficientData
    
    public var symbol: String {
        switch self {
        case .recommended: return "✅"
        case .acceptable: return "⚠️"
        case .problematic: return "🔶"
        case .avoid: return "❌"
        case .insufficientData: return "❓"
        }
    }
}

// MARK: - Platform Quality Stats

/// Quality statistics for a specific platform/OS version.
public struct PlatformQualityStats: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let platform: String
    public let osVersion: String
    public let deviceCount: Int
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let successRate: Double
    public let commonIssues: [String]
    
    public init(
        platform: String,
        osVersion: String,
        deviceCount: Int,
        totalAttempts: Int,
        successfulAttempts: Int,
        commonIssues: [String] = []
    ) {
        self.id = "\(platform)-\(osVersion)"
        self.platform = platform
        self.osVersion = osVersion
        self.deviceCount = deviceCount
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.successRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        self.commonIssues = commonIssues
    }
}

// MARK: - Protocol Quality Stats

/// Quality statistics for a specific protocol.
public struct ProtocolQualityStats: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let protocolName: String
    public let protocolVersion: String
    public let deviceCount: Int
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let successRate: Double
    public let averageLatencyMs: Int
    public let phaseSuccessRates: [String: Double]
    
    public init(
        protocolName: String,
        protocolVersion: String,
        deviceCount: Int,
        totalAttempts: Int,
        successfulAttempts: Int,
        averageLatencyMs: Int = 0,
        phaseSuccessRates: [String: Double] = [:]
    ) {
        self.id = "\(protocolName)-\(protocolVersion)"
        self.protocolName = protocolName
        self.protocolVersion = protocolVersion
        self.deviceCount = deviceCount
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.successRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        self.averageLatencyMs = averageLatencyMs
        self.phaseSuccessRates = phaseSuccessRates
    }
    
    public var weakestPhase: String? {
        phaseSuccessRates.min { $0.value < $1.value }?.key
    }
}

// MARK: - Aggregate Quality Report

/// Complete aggregate quality report across devices/versions.
public struct AggregateQualityReport: Sendable, Equatable, Codable, Identifiable {
    public static let schemaVersion = "1.0.0"
    
    public let id: String
    public let schemaVersion: String
    public let title: String
    public let description: String
    public let createdAt: Date
    public let periodStart: Date
    public let periodEnd: Date
    
    // Summary metrics
    public let totalDevices: Int
    public let totalAttempts: Int
    public let totalSuccesses: Int
    public let overallSuccessRate: Double
    public let overallTrend: TrendAnalysis
    
    // Breakdown stats
    public let deviceStats: [DeviceQualityStats]
    public let versionStats: [VersionQualityStats]
    public let platformStats: [PlatformQualityStats]
    public let protocolStats: [ProtocolQualityStats]
    public let timeSeries: TimeSeriesQuality?
    
    // Insights
    public let topPerformingDevices: [String]
    public let problematicDevices: [String]
    public let recommendedVersions: [String]
    public let avoidVersions: [String]
    
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        createdAt: Date = Date(),
        periodStart: Date,
        periodEnd: Date,
        deviceStats: [DeviceQualityStats] = [],
        versionStats: [VersionQualityStats] = [],
        platformStats: [PlatformQualityStats] = [],
        protocolStats: [ProtocolQualityStats] = [],
        timeSeries: TimeSeriesQuality? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.schemaVersion = Self.schemaVersion
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.deviceStats = deviceStats
        self.versionStats = versionStats
        self.platformStats = platformStats
        self.protocolStats = protocolStats
        self.timeSeries = timeSeries
        self.metadata = metadata
        
        // Calculate summary metrics
        self.totalDevices = deviceStats.count
        self.totalAttempts = deviceStats.map { $0.totalAttempts }.reduce(0, +)
        self.totalSuccesses = deviceStats.map { $0.successfulAttempts }.reduce(0, +)
        self.overallSuccessRate = totalAttempts > 0 ? Double(totalSuccesses) / Double(totalAttempts) : 0
        self.overallTrend = timeSeries?.trend ?? TrendAnalysis.insufficient(dataPoints: 0)
        
        // Calculate insights
        self.topPerformingDevices = deviceStats
            .filter { $0.successRate >= 0.95 && $0.totalAttempts >= 5 }
            .sorted { $0.successRate > $1.successRate }
            .prefix(5)
            .map { $0.deviceId }
        
        self.problematicDevices = deviceStats
            .filter { $0.successRate < 0.70 && $0.totalAttempts >= 5 }
            .sorted { $0.successRate < $1.successRate }
            .prefix(5)
            .map { $0.deviceId }
        
        self.recommendedVersions = versionStats
            .filter { $0.recommendation == .recommended }
            .map { $0.version }
        
        self.avoidVersions = versionStats
            .filter { $0.recommendation == .avoid }
            .map { $0.version }
    }
    
    public var periodDuration: TimeInterval {
        periodEnd.timeIntervalSince(periodStart)
    }
    
    public var failedAttempts: Int { totalAttempts - totalSuccesses }
    
    public func toJSON(prettyPrint: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(self)
    }
    
    public static func fromJSON(_ data: Data) throws -> AggregateQualityReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AggregateQualityReport.self, from: data)
    }
    
    public func redacted() -> AggregateQualityReport {
        AggregateQualityReport(
            id: id,
            title: title,
            description: description,
            createdAt: createdAt,
            periodStart: periodStart,
            periodEnd: periodEnd,
            deviceStats: deviceStats.map { $0.redacted() },
            versionStats: versionStats,
            platformStats: platformStats,
            protocolStats: protocolStats,
            timeSeries: timeSeries,
            metadata: metadata
        )
    }
}

// MARK: - Aggregate Report Builder

/// Fluent builder for creating aggregate quality reports.
public final class AggregateReportBuilder: @unchecked Sendable {
    private var title: String = "Quality Report"
    private var description: String = ""
    private var periodStart: Date = Date()
    private var periodEnd: Date = Date()
    private var deviceStats: [DeviceQualityStats] = []
    private var versionStats: [VersionQualityStats] = []
    private var platformStats: [PlatformQualityStats] = []
    private var protocolStats: [ProtocolQualityStats] = []
    private var timeSeries: TimeSeriesQuality?
    private var metadata: [String: String] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func title(_ title: String) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        self.title = title
        return self
    }
    
    public func description(_ description: String) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        self.description = description
        return self
    }
    
    public func period(start: Date, end: Date) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        self.periodStart = start
        self.periodEnd = end
        return self
    }
    
    public func addDeviceStats(_ stats: DeviceQualityStats) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        deviceStats.append(stats)
        return self
    }
    
    public func addVersionStats(_ stats: VersionQualityStats) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        versionStats.append(stats)
        return self
    }
    
    public func addPlatformStats(_ stats: PlatformQualityStats) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        platformStats.append(stats)
        return self
    }
    
    public func addProtocolStats(_ stats: ProtocolQualityStats) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        protocolStats.append(stats)
        return self
    }
    
    public func timeSeries(_ timeSeries: TimeSeriesQuality) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        self.timeSeries = timeSeries
        return self
    }
    
    public func metadata(_ key: String, _ value: String) -> AggregateReportBuilder {
        lock.lock()
        defer { lock.unlock() }
        metadata[key] = value
        return self
    }
    
    public func build() -> AggregateQualityReport {
        lock.lock()
        defer { lock.unlock() }
        
        return AggregateQualityReport(
            title: title,
            description: description,
            periodStart: periodStart,
            periodEnd: periodEnd,
            deviceStats: deviceStats,
            versionStats: versionStats,
            platformStats: platformStats,
            protocolStats: protocolStats,
            timeSeries: timeSeries,
            metadata: metadata
        )
    }
}

// MARK: - Quality Aggregator

/// Aggregates quality data from multiple protocol reports.
public struct QualityAggregator: Sendable {
    public init() {}
    
    /// Aggregate device stats from protocol reports.
    public func aggregateByDevice(_ reports: [ProtocolReport]) -> [DeviceQualityStats] {
        var deviceData: [String: (
            name: String?,
            firstSeen: Date,
            lastSeen: Date,
            attempts: Int,
            successes: Int,
            latencies: [Int],
            retries: Int,
            timeouts: Int,
            errors: [String: Int]
        )] = [:]
        
        for report in reports {
            guard let deviceId = report.deviceInfo?.deviceId else { continue }
            
            var data = deviceData[deviceId] ?? (
                name: report.deviceInfo?.name,
                firstSeen: report.createdAt,
                lastSeen: report.createdAt,
                attempts: 0,
                successes: 0,
                latencies: [],
                retries: 0,
                timeouts: 0,
                errors: [:]
            )
            
            data.attempts += report.attemptCount
            data.successes += report.successfulAttempts
            data.retries += report.metrics.retryCount
            data.timeouts += report.metrics.timeoutCount
            
            if report.createdAt < data.firstSeen {
                data.firstSeen = report.createdAt
            }
            if report.createdAt > data.lastSeen {
                data.lastSeen = report.createdAt
            }
            
            if report.metrics.totalDurationMs > 0 {
                data.latencies.append(report.metrics.totalDurationMs)
            }
            
            if let error = report.errorSummary {
                data.errors[error, default: 0] += 1
            }
            
            deviceData[deviceId] = data
        }
        
        return deviceData.map { deviceId, data in
            let avgLatency = data.latencies.isEmpty ? 0 : data.latencies.reduce(0, +) / data.latencies.count
            let minLatency = data.latencies.min() ?? 0
            let maxLatency = data.latencies.max() ?? 0
            
            return DeviceQualityStats(
                deviceId: deviceId,
                deviceName: data.name,
                firstSeen: data.firstSeen,
                lastSeen: data.lastSeen,
                totalAttempts: data.attempts,
                successfulAttempts: data.successes,
                averageLatencyMs: avgLatency,
                minLatencyMs: minLatency,
                maxLatencyMs: maxLatency,
                totalRetries: data.retries,
                totalTimeouts: data.timeouts,
                errorBreakdown: data.errors
            )
        }.sorted { $0.totalAttempts > $1.totalAttempts }
    }
    
    /// Aggregate version stats from protocol reports.
    public func aggregateByVersion(_ reports: [ProtocolReport]) -> [VersionQualityStats] {
        var versionData: [String: (
            devices: Set<String>,
            attempts: Int,
            successes: Int,
            latencies: [Int],
            errors: [String: Int]
        )] = [:]
        
        for report in reports {
            guard let version = report.deviceInfo?.firmware else { continue }
            let deviceId = report.deviceInfo?.deviceId ?? "unknown"
            
            var data = versionData[version] ?? (
                devices: [],
                attempts: 0,
                successes: 0,
                latencies: [],
                errors: [:]
            )
            
            data.devices.insert(deviceId)
            data.attempts += report.attemptCount
            data.successes += report.successfulAttempts
            
            if report.metrics.totalDurationMs > 0 {
                data.latencies.append(report.metrics.totalDurationMs)
            }
            
            if let error = report.errorSummary {
                data.errors[error, default: 0] += 1
            }
            
            versionData[version] = data
        }
        
        return versionData.map { version, data in
            let avgLatency = data.latencies.isEmpty ? 0 : data.latencies.reduce(0, +) / data.latencies.count
            
            return VersionQualityStats(
                version: version,
                deviceCount: data.devices.count,
                totalAttempts: data.attempts,
                successfulAttempts: data.successes,
                averageLatencyMs: avgLatency,
                commonErrors: data.errors
            )
        }.sorted { $0.version > $1.version }
    }
    
    /// Create time series from protocol reports.
    public func createTimeSeries(_ reports: [ProtocolReport], bucket: TimeBucket) -> TimeSeriesQuality? {
        guard !reports.isEmpty else { return nil }
        
        let sortedReports = reports.sorted { $0.createdAt < $1.createdAt }
        guard let startDate = sortedReports.first?.createdAt,
              let endDate = sortedReports.last?.createdAt else { return nil }
        
        var buckets: [Date: (attempts: Int, successes: Int, latencies: [Int], errors: Int)] = [:]
        
        for report in sortedReports {
            let bucketStart = floor(report.createdAt.timeIntervalSince1970 / bucket.seconds) * bucket.seconds
            let bucketDate = Date(timeIntervalSince1970: bucketStart)
            
            var data = buckets[bucketDate] ?? (attempts: 0, successes: 0, latencies: [], errors: 0)
            data.attempts += report.attemptCount
            data.successes += report.successfulAttempts
            if report.metrics.totalDurationMs > 0 {
                data.latencies.append(report.metrics.totalDurationMs)
            }
            if !report.success {
                data.errors += 1
            }
            buckets[bucketDate] = data
        }
        
        let dataPoints = buckets.map { date, data in
            let avgLatency = data.latencies.isEmpty ? nil : data.latencies.reduce(0, +) / data.latencies.count
            let successRate = data.attempts > 0 ? Double(data.successes) / Double(data.attempts) : 0
            
            return QualityDataPoint(
                timestamp: date,
                successRate: successRate,
                attemptCount: data.attempts,
                successCount: data.successes,
                averageLatencyMs: avgLatency,
                errorCount: data.errors
            )
        }.sorted { $0.timestamp < $1.timestamp }
        
        return TimeSeriesQuality(
            bucket: bucket,
            startDate: startDate,
            endDate: endDate,
            dataPoints: dataPoints
        )
    }
    
    /// Build a complete aggregate report from protocol reports.
    public func buildReport(
        title: String,
        reports: [ProtocolReport],
        bucket: TimeBucket = .day
    ) -> AggregateQualityReport {
        let deviceStats = aggregateByDevice(reports)
        let versionStats = aggregateByVersion(reports)
        let timeSeries = createTimeSeries(reports, bucket: bucket)
        
        let sortedReports = reports.sorted { $0.createdAt < $1.createdAt }
        let periodStart = sortedReports.first?.createdAt ?? Date()
        let periodEnd = sortedReports.last?.createdAt ?? Date()
        
        return AggregateQualityReport(
            title: title,
            periodStart: periodStart,
            periodEnd: periodEnd,
            deviceStats: deviceStats,
            versionStats: versionStats,
            timeSeries: timeSeries
        )
    }
}

// MARK: - Report Summary

/// Human-readable summary of an aggregate quality report.
public struct AggregateReportSummary: Sendable {
    public let report: AggregateQualityReport
    
    public init(_ report: AggregateQualityReport) {
        self.report = report
    }
    
    public var text: String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════")
        lines.append("AGGREGATE QUALITY REPORT: \(report.title)")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        
        let dateFormatter = ISO8601DateFormatter()
        lines.append("Period: \(dateFormatter.string(from: report.periodStart)) to \(dateFormatter.string(from: report.periodEnd))")
        lines.append("Created: \(dateFormatter.string(from: report.createdAt))")
        lines.append("")
        
        lines.append("─── SUMMARY ───")
        lines.append("Devices: \(report.totalDevices)")
        lines.append("Total Attempts: \(report.totalAttempts)")
        lines.append("Successful: \(report.totalSuccesses) (\(String(format: "%.1f%%", report.overallSuccessRate * 100)))")
        lines.append("Failed: \(report.failedAttempts)")
        lines.append("Trend: \(report.overallTrend.trend.symbol) \(report.overallTrend.trend.rawValue)")
        lines.append("")
        
        if !report.versionStats.isEmpty {
            lines.append("─── VERSION BREAKDOWN ───")
            for stat in report.versionStats.prefix(5) {
                lines.append("\(stat.recommendation.symbol) v\(stat.version): \(String(format: "%.1f%%", stat.successRate * 100)) (\(stat.totalAttempts) attempts)")
            }
            lines.append("")
        }
        
        if !report.recommendedVersions.isEmpty {
            lines.append("✅ Recommended: \(report.recommendedVersions.joined(separator: ", "))")
        }
        
        if !report.avoidVersions.isEmpty {
            lines.append("❌ Avoid: \(report.avoidVersions.joined(separator: ", "))")
        }
        
        if !report.problematicDevices.isEmpty {
            lines.append("")
            lines.append("⚠️ Problematic Devices: \(report.problematicDevices.count)")
        }
        
        return lines.joined(separator: "\n")
    }
}
