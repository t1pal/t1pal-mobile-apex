// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ReportAggregator.swift - Aggregate multiple anonymized reports
// Part of BLEKit
// Trace: EVID-002

import Foundation

// MARK: - Aggregate Statistics

/// Statistics aggregated across multiple reports
public struct AggregateStatistics: Sendable, Codable, Equatable {
    /// Total number of reports aggregated
    public let reportCount: Int
    
    /// Total number of traffic entries
    public let totalEntries: Int
    
    /// Total number of errors across all reports
    public let totalErrors: Int
    
    /// Success rate (reports with 0 errors / total reports)
    public let successRate: Double
    
    /// Average entries per report
    public let averageEntriesPerReport: Double
    
    /// Average session duration in seconds
    public let averageSessionDuration: TimeInterval
    
    /// Minimum session duration
    public let minSessionDuration: TimeInterval
    
    /// Maximum session duration
    public let maxSessionDuration: TimeInterval
    
    /// Total session time across all reports
    public let totalSessionTime: TimeInterval
    
    public init(
        reportCount: Int,
        totalEntries: Int,
        totalErrors: Int,
        successRate: Double,
        averageEntriesPerReport: Double,
        averageSessionDuration: TimeInterval,
        minSessionDuration: TimeInterval,
        maxSessionDuration: TimeInterval,
        totalSessionTime: TimeInterval
    ) {
        self.reportCount = reportCount
        self.totalEntries = totalEntries
        self.totalErrors = totalErrors
        self.successRate = successRate
        self.averageEntriesPerReport = averageEntriesPerReport
        self.averageSessionDuration = averageSessionDuration
        self.minSessionDuration = minSessionDuration
        self.maxSessionDuration = maxSessionDuration
        self.totalSessionTime = totalSessionTime
    }
    
    /// Empty statistics
    public static let empty = AggregateStatistics(
        reportCount: 0,
        totalEntries: 0,
        totalErrors: 0,
        successRate: 0,
        averageEntriesPerReport: 0,
        averageSessionDuration: 0,
        minSessionDuration: 0,
        maxSessionDuration: 0,
        totalSessionTime: 0
    )
}

// MARK: - Device Group

/// Reports grouped by device type
public struct DeviceGroup: Sendable, Codable, Equatable {
    /// Device identifier prefix (e.g., "DEV-abc123")
    public let deviceId: String
    
    /// Number of reports from this device
    public let reportCount: Int
    
    /// Statistics for this device
    public let statistics: AggregateStatistics
    
    /// First report timestamp
    public let firstReportDate: Date
    
    /// Last report timestamp
    public let lastReportDate: Date
    
    public init(
        deviceId: String,
        reportCount: Int,
        statistics: AggregateStatistics,
        firstReportDate: Date,
        lastReportDate: Date
    ) {
        self.deviceId = deviceId
        self.reportCount = reportCount
        self.statistics = statistics
        self.firstReportDate = firstReportDate
        self.lastReportDate = lastReportDate
    }
}

// MARK: - Error Category

/// Categories of errors for classification
public enum ErrorCategory: String, CaseIterable, Sendable, Codable {
    /// Connection-related errors
    case connection
    
    /// Authentication errors
    case authentication
    
    /// Protocol/communication errors
    case protocol_
    
    /// Timeout errors
    case timeout
    
    /// Unknown/other errors
    case unknown
    
    /// Display name
    public var displayName: String {
        switch self {
        case .connection: return "Connection"
        case .authentication: return "Authentication"
        case .protocol_: return "Protocol"
        case .timeout: return "Timeout"
        case .unknown: return "Unknown"
        }
    }
}

/// Error breakdown by category
public struct ErrorBreakdown: Sendable, Codable, Equatable {
    /// Counts by error category
    public let categoryCounts: [String: Int]
    
    /// Total errors
    public let totalErrors: Int
    
    /// Most common error category
    public let mostCommonCategory: String?
    
    public init(categoryCounts: [String: Int]) {
        self.categoryCounts = categoryCounts
        self.totalErrors = categoryCounts.values.reduce(0, +)
        self.mostCommonCategory = categoryCounts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Empty breakdown
    public static let empty = ErrorBreakdown(categoryCounts: [:])
}

// MARK: - Time Period Statistics

/// Statistics grouped by time period
public struct TimePeriodStatistics: Sendable, Codable, Equatable {
    /// Period identifier (e.g., "2026-02", "2026-W06")
    public let periodId: String
    
    /// Start of period
    public let periodStart: Date
    
    /// End of period
    public let periodEnd: Date
    
    /// Statistics for this period
    public let statistics: AggregateStatistics
    
    public init(
        periodId: String,
        periodStart: Date,
        periodEnd: Date,
        statistics: AggregateStatistics
    ) {
        self.periodId = periodId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.statistics = statistics
    }
}

// MARK: - Aggregate Report

/// Aggregated report combining multiple individual reports
public struct AggregateReport: Sendable, Codable {
    /// Version of the aggregate report format
    public let version: String
    
    /// When the aggregate was generated
    public let generatedAt: Date
    
    /// Time range covered
    public let coverageStart: Date
    public let coverageEnd: Date
    
    /// Overall statistics
    public let statistics: AggregateStatistics
    
    /// Reports grouped by device
    public let deviceGroups: [DeviceGroup]
    
    /// Error breakdown
    public let errorBreakdown: ErrorBreakdown
    
    /// Statistics by time period (daily/weekly)
    public let timePeriods: [TimePeriodStatistics]
    
    /// Metadata about source reports
    public let sourceReportCount: Int
    
    public init(
        version: String = "1.0",
        generatedAt: Date = Date(),
        coverageStart: Date,
        coverageEnd: Date,
        statistics: AggregateStatistics,
        deviceGroups: [DeviceGroup],
        errorBreakdown: ErrorBreakdown,
        timePeriods: [TimePeriodStatistics],
        sourceReportCount: Int
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.statistics = statistics
        self.deviceGroups = deviceGroups
        self.errorBreakdown = errorBreakdown
        self.timePeriods = timePeriods
        self.sourceReportCount = sourceReportCount
    }
}

// MARK: - Report Aggregator

/// Aggregates multiple anonymized reports into summary statistics
///
/// Trace: EVID-002
///
/// Combines individual AnonymizedReport instances into aggregate statistics,
/// grouping by device, time period, and error category. Designed to work
/// with privacy-safe anonymized data from ReportAnonymizer.
public struct ReportAggregator: Sendable {
    
    // MARK: - Configuration
    
    /// Configuration for aggregation
    public struct Config: Sendable {
        /// Time period for grouping (daily, weekly, monthly)
        public let periodGrouping: PeriodGrouping
        
        /// Whether to include individual entries in output
        public let includeEntries: Bool
        
        /// Maximum reports to process (0 = unlimited)
        public let maxReports: Int
        
        public init(
            periodGrouping: PeriodGrouping = .daily,
            includeEntries: Bool = false,
            maxReports: Int = 0
        ) {
            self.periodGrouping = periodGrouping
            self.includeEntries = includeEntries
            self.maxReports = maxReports
        }
        
        /// Default configuration
        public static let `default` = Config()
        
        /// Configuration for weekly summaries
        public static let weekly = Config(periodGrouping: .weekly)
        
        /// Configuration for monthly summaries
        public static let monthly = Config(periodGrouping: .monthly)
    }
    
    /// Time period grouping options
    public enum PeriodGrouping: String, Sendable {
        case daily
        case weekly
        case monthly
    }
    
    // MARK: - Properties
    
    private let config: Config
    private let calendar: Calendar
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = cal
    }
    
    // MARK: - Aggregation
    
    /// Aggregate multiple reports into summary statistics
    public func aggregate(_ reports: [AnonymizedReport]) -> AggregateReport {
        let limitedReports: [AnonymizedReport]
        if config.maxReports > 0 && reports.count > config.maxReports {
            limitedReports = Array(reports.prefix(config.maxReports))
        } else {
            limitedReports = reports
        }
        
        guard !limitedReports.isEmpty else {
            return emptyReport()
        }
        
        let statistics = computeStatistics(limitedReports)
        let deviceGroups = groupByDevice(limitedReports)
        let errorBreakdown = computeErrorBreakdown(limitedReports)
        let timePeriods = groupByTimePeriod(limitedReports)
        
        let dates = limitedReports.map { $0.generatedAt }
        let coverageStart = dates.min() ?? Date()
        let coverageEnd = dates.max() ?? Date()
        
        return AggregateReport(
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            statistics: statistics,
            deviceGroups: deviceGroups,
            errorBreakdown: errorBreakdown,
            timePeriods: timePeriods,
            sourceReportCount: limitedReports.count
        )
    }
    
    /// Compute aggregate statistics from reports
    public func computeStatistics(_ reports: [AnonymizedReport]) -> AggregateStatistics {
        guard !reports.isEmpty else {
            return .empty
        }
        
        let totalEntries = reports.reduce(0) { $0 + $1.entryCount }
        let totalErrors = reports.reduce(0) { $0 + $1.errorCount }
        let successCount = reports.filter { $0.errorCount == 0 }.count
        let successRate = Double(successCount) / Double(reports.count)
        
        let durations = reports.map { $0.sessionDuration }
        let totalDuration = durations.reduce(0, +)
        let avgDuration = totalDuration / Double(reports.count)
        let minDuration = durations.min() ?? 0
        let maxDuration = durations.max() ?? 0
        
        return AggregateStatistics(
            reportCount: reports.count,
            totalEntries: totalEntries,
            totalErrors: totalErrors,
            successRate: successRate,
            averageEntriesPerReport: Double(totalEntries) / Double(reports.count),
            averageSessionDuration: avgDuration,
            minSessionDuration: minDuration,
            maxSessionDuration: maxDuration,
            totalSessionTime: totalDuration
        )
    }
    
    /// Group reports by device ID
    public func groupByDevice(_ reports: [AnonymizedReport]) -> [DeviceGroup] {
        var deviceReports: [String: [AnonymizedReport]] = [:]
        
        for report in reports {
            deviceReports[report.deviceId, default: []].append(report)
        }
        
        return deviceReports.map { deviceId, deviceReportList in
            let stats = computeStatistics(deviceReportList)
            let dates = deviceReportList.map { $0.generatedAt }
            
            return DeviceGroup(
                deviceId: deviceId,
                reportCount: deviceReportList.count,
                statistics: stats,
                firstReportDate: dates.min() ?? Date(),
                lastReportDate: dates.max() ?? Date()
            )
        }.sorted { $0.reportCount > $1.reportCount }
    }
    
    /// Compute error breakdown by category
    public func computeErrorBreakdown(_ reports: [AnonymizedReport]) -> ErrorBreakdown {
        var categoryCounts: [String: Int] = [:]
        
        for report in reports {
            if report.errorCount > 0 {
                // Classify based on available information
                let category = classifyErrors(report)
                categoryCounts[category.rawValue, default: 0] += report.errorCount
            }
        }
        
        return ErrorBreakdown(categoryCounts: categoryCounts)
    }
    
    /// Classify errors in a report (heuristic-based)
    private func classifyErrors(_ report: AnonymizedReport) -> ErrorCategory {
        // Simple heuristic - in a real implementation, error details would be included
        // For now, classify based on session duration and entry count
        
        if report.sessionDuration < 5 {
            return .connection
        } else if report.entryCount < 3 {
            return .authentication
        } else if report.sessionDuration < 30 {
            return .timeout
        } else {
            return .protocol_
        }
    }
    
    /// Group reports by time period
    public func groupByTimePeriod(_ reports: [AnonymizedReport]) -> [TimePeriodStatistics] {
        var periodReports: [String: [AnonymizedReport]] = [:]
        var periodDates: [String: (start: Date, end: Date)] = [:]
        
        for report in reports {
            let (periodId, start, end) = periodInfo(for: report.generatedAt)
            periodReports[periodId, default: []].append(report)
            periodDates[periodId] = (start, end)
        }
        
        return periodReports.compactMap { periodId, periodReportList in
            guard let dates = periodDates[periodId] else { return nil }
            let stats = computeStatistics(periodReportList)
            
            return TimePeriodStatistics(
                periodId: periodId,
                periodStart: dates.start,
                periodEnd: dates.end,
                statistics: stats
            )
        }.sorted { $0.periodStart < $1.periodStart }
    }
    
    /// Get period identifier and date range for a date
    private func periodInfo(for date: Date) -> (id: String, start: Date, end: Date) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        switch config.periodGrouping {
        case .daily:
            formatter.dateFormat = "yyyy-MM-dd"
            let id = formatter.string(from: date)
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (id, start, end)
            
        case .weekly:
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let id = String(format: "%04d-W%02d", year, weekOfYear)
            
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            components.weekday = calendar.firstWeekday
            let start = calendar.date(from: components)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (id, start, end)
            
        case .monthly:
            formatter.dateFormat = "yyyy-MM"
            let id = formatter.string(from: date)
            
            var components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: components)!
            components.month! += 1
            let end = calendar.date(from: components)!
            return (id, start, end)
        }
    }
    
    /// Create empty aggregate report
    private func emptyReport() -> AggregateReport {
        let now = Date()
        return AggregateReport(
            coverageStart: now,
            coverageEnd: now,
            statistics: .empty,
            deviceGroups: [],
            errorBreakdown: .empty,
            timePeriods: [],
            sourceReportCount: 0
        )
    }
    
    // MARK: - Comparison
    
    /// Compare two aggregate reports
    public func compare(_ report1: AggregateReport, _ report2: AggregateReport) -> ComparisonResult {
        let successDelta = report2.statistics.successRate - report1.statistics.successRate
        let errorDelta = report2.statistics.totalErrors - report1.statistics.totalErrors
        let durationDelta = report2.statistics.averageSessionDuration - report1.statistics.averageSessionDuration
        
        return ComparisonResult(
            report1Period: "\(report1.coverageStart) - \(report1.coverageEnd)",
            report2Period: "\(report2.coverageStart) - \(report2.coverageEnd)",
            successRateDelta: successDelta,
            errorCountDelta: errorDelta,
            avgDurationDelta: durationDelta,
            report1ReportCount: report1.sourceReportCount,
            report2ReportCount: report2.sourceReportCount
        )
    }
}

// MARK: - Comparison Result

/// Result of comparing two aggregate reports
public struct ComparisonResult: Sendable, Codable {
    /// Period description for first report
    public let report1Period: String
    
    /// Period description for second report
    public let report2Period: String
    
    /// Change in success rate (positive = improvement)
    public let successRateDelta: Double
    
    /// Change in error count (negative = improvement)
    public let errorCountDelta: Int
    
    /// Change in average session duration
    public let avgDurationDelta: TimeInterval
    
    /// Number of reports in first aggregate
    public let report1ReportCount: Int
    
    /// Number of reports in second aggregate
    public let report2ReportCount: Int
    
    /// Whether quality improved overall
    public var isImproved: Bool {
        successRateDelta > 0 || (successRateDelta == 0 && errorCountDelta < 0)
    }
    
    public init(
        report1Period: String,
        report2Period: String,
        successRateDelta: Double,
        errorCountDelta: Int,
        avgDurationDelta: TimeInterval,
        report1ReportCount: Int,
        report2ReportCount: Int
    ) {
        self.report1Period = report1Period
        self.report2Period = report2Period
        self.successRateDelta = successRateDelta
        self.errorCountDelta = errorCountDelta
        self.avgDurationDelta = avgDurationDelta
        self.report1ReportCount = report1ReportCount
        self.report2ReportCount = report2ReportCount
    }
}

// MARK: - Streaming Aggregator

/// Streaming aggregator for incremental report processing
public actor StreamingReportAggregator {
    
    private var reports: [AnonymizedReport] = []
    private let maxReportsInMemory: Int
    private var runningStats: RunningStatistics
    
    /// Running statistics for incremental updates
    private struct RunningStatistics {
        var reportCount: Int = 0
        var totalEntries: Int = 0
        var totalErrors: Int = 0
        var successCount: Int = 0
        var totalDuration: TimeInterval = 0
        var minDuration: TimeInterval = .infinity
        var maxDuration: TimeInterval = 0
        var firstDate: Date?
        var lastDate: Date?
        var deviceCounts: [String: Int] = [:]
        var errorCategoryCounts: [String: Int] = [:]
    }
    
    public init(maxReportsInMemory: Int = 1000) {
        self.maxReportsInMemory = maxReportsInMemory
        self.runningStats = RunningStatistics()
    }
    
    /// Add a report to the aggregation
    public func addReport(_ report: AnonymizedReport) {
        // Update running statistics
        runningStats.reportCount += 1
        runningStats.totalEntries += report.entryCount
        runningStats.totalErrors += report.errorCount
        if report.errorCount == 0 {
            runningStats.successCount += 1
        }
        runningStats.totalDuration += report.sessionDuration
        runningStats.minDuration = min(runningStats.minDuration, report.sessionDuration)
        runningStats.maxDuration = max(runningStats.maxDuration, report.sessionDuration)
        
        if runningStats.firstDate == nil || report.generatedAt < runningStats.firstDate! {
            runningStats.firstDate = report.generatedAt
        }
        if runningStats.lastDate == nil || report.generatedAt > runningStats.lastDate! {
            runningStats.lastDate = report.generatedAt
        }
        
        runningStats.deviceCounts[report.deviceId, default: 0] += 1
        
        // Keep reports in memory up to limit
        if reports.count < maxReportsInMemory {
            reports.append(report)
        }
    }
    
    /// Get current aggregate statistics
    public func getCurrentStatistics() -> AggregateStatistics {
        guard runningStats.reportCount > 0 else {
            return .empty
        }
        
        return AggregateStatistics(
            reportCount: runningStats.reportCount,
            totalEntries: runningStats.totalEntries,
            totalErrors: runningStats.totalErrors,
            successRate: Double(runningStats.successCount) / Double(runningStats.reportCount),
            averageEntriesPerReport: Double(runningStats.totalEntries) / Double(runningStats.reportCount),
            averageSessionDuration: runningStats.totalDuration / Double(runningStats.reportCount),
            minSessionDuration: runningStats.minDuration == .infinity ? 0 : runningStats.minDuration,
            maxSessionDuration: runningStats.maxDuration,
            totalSessionTime: runningStats.totalDuration
        )
    }
    
    /// Get device report counts
    public func getDeviceCounts() -> [String: Int] {
        runningStats.deviceCounts
    }
    
    /// Get coverage dates
    public func getCoverageDates() -> (start: Date?, end: Date?) {
        (runningStats.firstDate, runningStats.lastDate)
    }
    
    /// Get report count
    public func getReportCount() -> Int {
        runningStats.reportCount
    }
    
    /// Reset the aggregator
    public func reset() {
        reports = []
        runningStats = RunningStatistics()
    }
}
