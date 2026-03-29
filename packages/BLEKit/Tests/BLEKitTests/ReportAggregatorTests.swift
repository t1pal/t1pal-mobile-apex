// ReportAggregatorTests.swift - Tests for report aggregation
// Part of BLEKit
// Trace: EVID-002

import Foundation
import Testing
@testable import BLEKit

// MARK: - Test Helpers

func makeTestReport(
    deviceId: String = "DEV-abc123",
    entryCount: Int = 10,
    errorCount: Int = 0,
    sessionDuration: TimeInterval = 120,
    generatedAt: Date = Date()
) -> AnonymizedReport {
    AnonymizedReport(
        deviceId: deviceId,
        generatedAt: generatedAt,
        entries: [],
        sessionDuration: sessionDuration,
        entryCount: entryCount,
        errorCount: errorCount,
        anonymizationInfo: AnonymizationInfo(
            deviceIdStrategy: "hash",
            uuidStrategy: "hash",
            timestampStrategy: "relative",
            packetDataAnonymized: false,
            uniqueDeviceCount: 1,
            redactedPIITypes: []
        )
    )
}

// MARK: - Aggregate Statistics Tests

@Suite("Aggregate Statistics")
struct AggregateStatisticsTests {
    
    @Test("Empty statistics")
    func emptyStatistics() {
        let stats = AggregateStatistics.empty
        
        #expect(stats.reportCount == 0)
        #expect(stats.totalEntries == 0)
        #expect(stats.totalErrors == 0)
        #expect(stats.successRate == 0)
    }
    
    @Test("Statistics are Equatable")
    func equatable() {
        let stats1 = AggregateStatistics.empty
        let stats2 = AggregateStatistics.empty
        
        #expect(stats1 == stats2)
    }
    
    @Test("Statistics are Codable")
    func codable() throws {
        let stats = AggregateStatistics(
            reportCount: 10,
            totalEntries: 100,
            totalErrors: 5,
            successRate: 0.9,
            averageEntriesPerReport: 10,
            averageSessionDuration: 120,
            minSessionDuration: 60,
            maxSessionDuration: 180,
            totalSessionTime: 1200
        )
        
        let encoded = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(AggregateStatistics.self, from: encoded)
        
        #expect(decoded.reportCount == stats.reportCount)
        #expect(decoded.successRate == stats.successRate)
    }
}

// MARK: - Device Group Tests

@Suite("Device Group")
struct DeviceGroupTests {
    
    @Test("Create device group")
    func createGroup() {
        let now = Date()
        let group = DeviceGroup(
            deviceId: "DEV-abc123",
            reportCount: 5,
            statistics: .empty,
            firstReportDate: now,
            lastReportDate: now
        )
        
        #expect(group.deviceId == "DEV-abc123")
        #expect(group.reportCount == 5)
    }
    
    @Test("Device group is Codable")
    func codable() throws {
        let group = DeviceGroup(
            deviceId: "DEV-test",
            reportCount: 3,
            statistics: .empty,
            firstReportDate: Date(),
            lastReportDate: Date()
        )
        
        let encoded = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(DeviceGroup.self, from: encoded)
        
        #expect(decoded.deviceId == group.deviceId)
    }
}

// MARK: - Error Category Tests

@Suite("Aggregator Error Category")
struct AggregatorErrorCategoryTests {
    
    @Test("All categories exist")
    func allCategories() {
        #expect(ErrorCategory.allCases.count == 5)
    }
    
    @Test("Display names")
    func displayNames() {
        #expect(ErrorCategory.connection.displayName == "Connection")
        #expect(ErrorCategory.authentication.displayName == "Authentication")
        #expect(ErrorCategory.protocol_.displayName == "Protocol")
        #expect(ErrorCategory.timeout.displayName == "Timeout")
        #expect(ErrorCategory.unknown.displayName == "Unknown")
    }
}

// MARK: - Error Breakdown Tests

@Suite("Error Breakdown")
struct ErrorBreakdownTests {
    
    @Test("Empty breakdown")
    func emptyBreakdown() {
        let breakdown = ErrorBreakdown.empty
        
        #expect(breakdown.totalErrors == 0)
        #expect(breakdown.mostCommonCategory == nil)
    }
    
    @Test("Breakdown with counts")
    func withCounts() {
        let breakdown = ErrorBreakdown(categoryCounts: [
            "connection": 5,
            "timeout": 3,
            "authentication": 1
        ])
        
        #expect(breakdown.totalErrors == 9)
        #expect(breakdown.mostCommonCategory == "connection")
    }
}

// MARK: - Report Aggregator Config Tests

@Suite("Report Aggregator Config")
struct ReportAggregatorConfigTests {
    
    @Test("Default config")
    func defaultConfig() {
        let config = ReportAggregator.Config.default
        
        #expect(config.periodGrouping == .daily)
        #expect(config.includeEntries == false)
        #expect(config.maxReports == 0)
    }
    
    @Test("Weekly config")
    func weeklyConfig() {
        let config = ReportAggregator.Config.weekly
        
        #expect(config.periodGrouping == .weekly)
    }
    
    @Test("Monthly config")
    func monthlyConfig() {
        let config = ReportAggregator.Config.monthly
        
        #expect(config.periodGrouping == .monthly)
    }
}

// MARK: - Report Aggregator Tests

@Suite("Report Aggregator")
struct ReportAggregatorTests {
    
    @Test("Aggregate empty list")
    func aggregateEmpty() {
        let aggregator = ReportAggregator()
        let result = aggregator.aggregate([])
        
        #expect(result.sourceReportCount == 0)
        #expect(result.statistics == .empty)
    }
    
    @Test("Aggregate single report")
    func aggregateSingle() {
        let aggregator = ReportAggregator()
        let report = makeTestReport(entryCount: 10, sessionDuration: 120)
        
        let result = aggregator.aggregate([report])
        
        #expect(result.sourceReportCount == 1)
        #expect(result.statistics.reportCount == 1)
        #expect(result.statistics.totalEntries == 10)
        #expect(result.statistics.averageSessionDuration == 120)
    }
    
    @Test("Aggregate multiple reports")
    func aggregateMultiple() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(entryCount: 10, sessionDuration: 100),
            makeTestReport(entryCount: 20, sessionDuration: 200),
            makeTestReport(entryCount: 30, sessionDuration: 300)
        ]
        
        let result = aggregator.aggregate(reports)
        
        #expect(result.sourceReportCount == 3)
        #expect(result.statistics.totalEntries == 60)
        #expect(result.statistics.averageEntriesPerReport == 20)
        #expect(result.statistics.averageSessionDuration == 200)
        #expect(result.statistics.minSessionDuration == 100)
        #expect(result.statistics.maxSessionDuration == 300)
    }
    
    @Test("Success rate calculation")
    func successRate() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(errorCount: 0),
            makeTestReport(errorCount: 0),
            makeTestReport(errorCount: 0),
            makeTestReport(errorCount: 1),  // One failure
            makeTestReport(errorCount: 2)   // Another failure
        ]
        
        let result = aggregator.aggregate(reports)
        
        #expect(result.statistics.successRate == 0.6)  // 3/5
        #expect(result.statistics.totalErrors == 3)
    }
    
    @Test("Max reports limit")
    func maxReportsLimit() {
        let config = ReportAggregator.Config(maxReports: 2)
        let aggregator = ReportAggregator(config: config)
        let reports = [
            makeTestReport(),
            makeTestReport(),
            makeTestReport(),
            makeTestReport()
        ]
        
        let result = aggregator.aggregate(reports)
        
        #expect(result.sourceReportCount == 2)
    }
}

// MARK: - Device Grouping Tests

@Suite("Device Grouping")
struct DeviceGroupingTests {
    
    @Test("Group by device")
    func groupByDevice() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(deviceId: "DEV-aaa", entryCount: 10),
            makeTestReport(deviceId: "DEV-aaa", entryCount: 20),
            makeTestReport(deviceId: "DEV-bbb", entryCount: 30)
        ]
        
        let groups = aggregator.groupByDevice(reports)
        
        #expect(groups.count == 2)
        
        // Sorted by report count descending
        let deviceAAA = groups.first { $0.deviceId == "DEV-aaa" }
        let deviceBBB = groups.first { $0.deviceId == "DEV-bbb" }
        
        #expect(deviceAAA?.reportCount == 2)
        #expect(deviceAAA?.statistics.totalEntries == 30)
        #expect(deviceBBB?.reportCount == 1)
    }
    
    @Test("Device groups sorted by count")
    func sortedByCount() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(deviceId: "DEV-less"),
            makeTestReport(deviceId: "DEV-more"),
            makeTestReport(deviceId: "DEV-more"),
            makeTestReport(deviceId: "DEV-more")
        ]
        
        let groups = aggregator.groupByDevice(reports)
        
        #expect(groups.first?.deviceId == "DEV-more")
        #expect(groups.first?.reportCount == 3)
    }
}

// MARK: - Error Breakdown Tests

@Suite("Error Breakdown Computation")
struct ErrorBreakdownComputationTests {
    
    @Test("Compute error breakdown")
    func computeBreakdown() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(errorCount: 1, sessionDuration: 2),  // Short = connection
            makeTestReport(errorCount: 2, sessionDuration: 120),  // Normal = protocol
            makeTestReport(errorCount: 0)  // No errors
        ]
        
        let breakdown = aggregator.computeErrorBreakdown(reports)
        
        #expect(breakdown.totalErrors == 3)
    }
    
    @Test("No errors produces empty breakdown")
    func noErrors() {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(errorCount: 0),
            makeTestReport(errorCount: 0)
        ]
        
        let breakdown = aggregator.computeErrorBreakdown(reports)
        
        #expect(breakdown.totalErrors == 0)
    }
}

// MARK: - Time Period Grouping Tests

@Suite("Time Period Grouping")
struct TimePeriodGroupingTests {
    
    @Test("Group by day")
    func groupByDay() {
        let aggregator = ReportAggregator(config: .default)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        
        let reports = [
            makeTestReport(generatedAt: today),
            makeTestReport(generatedAt: today),
            makeTestReport(generatedAt: yesterday)
        ]
        
        let periods = aggregator.groupByTimePeriod(reports)
        
        #expect(periods.count == 2)
    }
    
    @Test("Group by week")
    func groupByWeek() {
        let config = ReportAggregator.Config(periodGrouping: .weekly)
        let aggregator = ReportAggregator(config: config)
        let today = Date()
        
        let reports = [
            makeTestReport(generatedAt: today),
            makeTestReport(generatedAt: today)
        ]
        
        let periods = aggregator.groupByTimePeriod(reports)
        
        #expect(periods.count == 1)
        #expect(periods.first?.periodId.contains("-W") == true)
    }
    
    @Test("Group by month")
    func groupByMonth() {
        let config = ReportAggregator.Config(periodGrouping: .monthly)
        let aggregator = ReportAggregator(config: config)
        let today = Date()
        
        let reports = [
            makeTestReport(generatedAt: today),
            makeTestReport(generatedAt: today)
        ]
        
        let periods = aggregator.groupByTimePeriod(reports)
        
        #expect(periods.count == 1)
        // Monthly format: YYYY-MM
        #expect(periods.first?.periodId.count == 7)
    }
    
    @Test("Periods sorted by date")
    func periodsSorted() {
        let aggregator = ReportAggregator()
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        
        let reports = [
            makeTestReport(generatedAt: today),
            makeTestReport(generatedAt: twoDaysAgo),
            makeTestReport(generatedAt: yesterday)
        ]
        
        let periods = aggregator.groupByTimePeriod(reports)
        
        // Should be sorted oldest to newest
        if periods.count >= 2 {
            #expect(periods.first!.periodStart < periods.last!.periodStart)
        }
    }
}

// MARK: - Comparison Tests

@Suite("Report Comparison")
struct ReportComparisonTests {
    
    @Test("Compare two reports")
    func compareTwoReports() {
        let aggregator = ReportAggregator()
        
        let report1 = aggregator.aggregate([
            makeTestReport(errorCount: 2),
            makeTestReport(errorCount: 1)
        ])
        
        let report2 = aggregator.aggregate([
            makeTestReport(errorCount: 0),
            makeTestReport(errorCount: 0)
        ])
        
        let comparison = aggregator.compare(report1, report2)
        
        #expect(comparison.successRateDelta == 1.0)  // 0% -> 100%
        #expect(comparison.errorCountDelta == -3)  // 3 -> 0
        #expect(comparison.isImproved == true)
    }
    
    @Test("Improvement detection")
    func improvementDetection() {
        let aggregator = ReportAggregator()
        
        let worse = aggregator.aggregate([
            makeTestReport(errorCount: 5)
        ])
        
        let better = aggregator.aggregate([
            makeTestReport(errorCount: 0)
        ])
        
        let comparison = aggregator.compare(worse, better)
        
        #expect(comparison.isImproved == true)
    }
    
    @Test("Regression detection")
    func regressionDetection() {
        let aggregator = ReportAggregator()
        
        let good = aggregator.aggregate([
            makeTestReport(errorCount: 0)
        ])
        
        let bad = aggregator.aggregate([
            makeTestReport(errorCount: 5)
        ])
        
        let comparison = aggregator.compare(good, bad)
        
        #expect(comparison.isImproved == false)
    }
}

// MARK: - Aggregate Report Tests

@Suite("Aggregate Report")
struct AggregateReportTests {
    
    @Test("Report is Codable")
    func codable() throws {
        let aggregator = ReportAggregator()
        let reports = [
            makeTestReport(deviceId: "DEV-a"),
            makeTestReport(deviceId: "DEV-b")
        ]
        
        let aggregate = aggregator.aggregate(reports)
        
        let encoded = try JSONEncoder().encode(aggregate)
        let decoded = try JSONDecoder().decode(AggregateReport.self, from: encoded)
        
        #expect(decoded.sourceReportCount == aggregate.sourceReportCount)
        #expect(decoded.statistics.reportCount == aggregate.statistics.reportCount)
    }
    
    @Test("Report has version")
    func hasVersion() {
        let aggregator = ReportAggregator()
        let result = aggregator.aggregate([makeTestReport()])
        
        #expect(result.version == "1.0")
    }
    
    @Test("Coverage dates set correctly")
    func coverageDates() {
        let aggregator = ReportAggregator()
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        
        let reports = [
            makeTestReport(generatedAt: earlier),
            makeTestReport(generatedAt: now)
        ]
        
        let result = aggregator.aggregate(reports)
        
        #expect(result.coverageStart == earlier)
        #expect(result.coverageEnd == now)
    }
}

// MARK: - Streaming Aggregator Tests

@Suite("Streaming Report Aggregator")
struct StreamingReportAggregatorTests {
    
    @Test("Add reports incrementally")
    func addReportsIncrementally() async {
        let aggregator = StreamingReportAggregator()
        
        await aggregator.addReport(makeTestReport(entryCount: 10))
        await aggregator.addReport(makeTestReport(entryCount: 20))
        
        let stats = await aggregator.getCurrentStatistics()
        
        #expect(stats.reportCount == 2)
        #expect(stats.totalEntries == 30)
    }
    
    @Test("Track device counts")
    func trackDeviceCounts() async {
        let aggregator = StreamingReportAggregator()
        
        await aggregator.addReport(makeTestReport(deviceId: "DEV-a"))
        await aggregator.addReport(makeTestReport(deviceId: "DEV-a"))
        await aggregator.addReport(makeTestReport(deviceId: "DEV-b"))
        
        let counts = await aggregator.getDeviceCounts()
        
        #expect(counts["DEV-a"] == 2)
        #expect(counts["DEV-b"] == 1)
    }
    
    @Test("Track success rate")
    func trackSuccessRate() async {
        let aggregator = StreamingReportAggregator()
        
        await aggregator.addReport(makeTestReport(errorCount: 0))
        await aggregator.addReport(makeTestReport(errorCount: 0))
        await aggregator.addReport(makeTestReport(errorCount: 1))
        await aggregator.addReport(makeTestReport(errorCount: 0))
        
        let stats = await aggregator.getCurrentStatistics()
        
        #expect(stats.successRate == 0.75)  // 3/4
    }
    
    @Test("Track coverage dates")
    func trackCoverageDates() async {
        let aggregator = StreamingReportAggregator()
        let earlier = Date().addingTimeInterval(-3600)
        let later = Date()
        
        await aggregator.addReport(makeTestReport(generatedAt: later))
        await aggregator.addReport(makeTestReport(generatedAt: earlier))
        
        let (start, end) = await aggregator.getCoverageDates()
        
        #expect(start == earlier)
        #expect(end == later)
    }
    
    @Test("Reset clears state")
    func resetClearsState() async {
        let aggregator = StreamingReportAggregator()
        
        await aggregator.addReport(makeTestReport())
        await aggregator.addReport(makeTestReport())
        
        #expect(await aggregator.getReportCount() == 2)
        
        await aggregator.reset()
        
        #expect(await aggregator.getReportCount() == 0)
    }
    
    @Test("Min/max duration tracking")
    func minMaxDuration() async {
        let aggregator = StreamingReportAggregator()
        
        await aggregator.addReport(makeTestReport(sessionDuration: 60))
        await aggregator.addReport(makeTestReport(sessionDuration: 180))
        await aggregator.addReport(makeTestReport(sessionDuration: 120))
        
        let stats = await aggregator.getCurrentStatistics()
        
        #expect(stats.minSessionDuration == 60)
        #expect(stats.maxSessionDuration == 180)
        #expect(stats.averageSessionDuration == 120)
    }
}
