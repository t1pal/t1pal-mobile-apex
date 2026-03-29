// AggregateQualityReportTests.swift
// BLEKit Tests
//
// Tests for AggregateQualityReport and related types.
// INSTR-005: AggregateQualityReport schema

import Testing
import Foundation
@testable import BLEKit

// MARK: - Quality Trend Tests

@Suite("Quality Trend")
struct QualityTrendTests {
    
    @Test("All trend cases have symbols")
    func trendSymbols() {
        for trend in QualityTrend.allCases {
            #expect(!trend.symbol.isEmpty)
        }
    }
    
    @Test("Trend symbols are unique")
    func uniqueSymbols() {
        let symbols = QualityTrend.allCases.map { $0.symbol }
        let uniqueSymbols = Set(symbols)
        #expect(symbols.count == uniqueSymbols.count)
    }
    
    @Test("Trend is Codable")
    func trendCodable() throws {
        let trend = QualityTrend.improving
        let data = try JSONEncoder().encode(trend)
        let decoded = try JSONDecoder().decode(QualityTrend.self, from: data)
        #expect(decoded == trend)
    }
}

// MARK: - Trend Analysis Tests

@Suite("Quality Trend Analysis")
struct QualityTrendAnalysisTests {
    
    @Test("Insufficient data with less than 3 points")
    func insufficientData() {
        let analysis = TrendAnalysis.analyze(values: [0.9, 0.85])
        #expect(analysis.trend == .insufficient)
        #expect(analysis.dataPoints == 2)
    }
    
    @Test("Stable trend for flat data")
    func stableTrend() {
        let analysis = TrendAnalysis.analyze(values: [0.90, 0.91, 0.90, 0.89, 0.90])
        #expect(analysis.trend == .stable)
        #expect(analysis.dataPoints == 5)
    }
    
    @Test("Improving trend for increasing data")
    func improvingTrend() {
        let analysis = TrendAnalysis.analyze(values: [0.70, 0.75, 0.80, 0.85, 0.90])
        #expect(analysis.trend == .improving)
        #expect(analysis.changePercent != nil)
        if let change = analysis.changePercent {
            #expect(change > 0)
        }
    }
    
    @Test("Degrading trend for decreasing data")
    func degradingTrend() {
        let analysis = TrendAnalysis.analyze(values: [0.95, 0.90, 0.85, 0.80, 0.75])
        #expect(analysis.trend == .degrading)
        #expect(analysis.changePercent != nil)
        if let change = analysis.changePercent {
            #expect(change < 0)
        }
    }
    
    @Test("Confidence is bounded 0-1")
    func confidenceBounds() {
        let analysis = TrendAnalysis(
            trend: .stable,
            confidence: 1.5,
            dataPoints: 10
        )
        #expect(analysis.confidence <= 1.0)
        #expect(analysis.confidence >= 0.0)
    }
    
    @Test("Trend analysis is Codable")
    func trendAnalysisCodable() throws {
        let analysis = TrendAnalysis.analyze(values: [0.80, 0.85, 0.90])
        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(TrendAnalysis.self, from: data)
        #expect(decoded == analysis)
    }
}

// MARK: - Time Series Tests

@Suite("Time Series Quality")
struct TimeSeriesTests {
    
    @Test("Quality data point creation")
    func dataPointCreation() {
        let point = QualityDataPoint(
            timestamp: Date(),
            successRate: 0.95,
            attemptCount: 100,
            successCount: 95,
            averageLatencyMs: 250,
            errorCount: 5
        )
        #expect(point.successRate == 0.95)
        #expect(point.attemptCount == 100)
        #expect(point.successCount == 95)
        #expect(point.errorCount == 5)
    }
    
    @Test("Time bucket seconds values")
    func bucketSeconds() {
        #expect(TimeBucket.hour.seconds == 3600)
        #expect(TimeBucket.day.seconds == 86400)
        #expect(TimeBucket.week.seconds == 604800)
        #expect(TimeBucket.month.seconds == 2592000)
    }
    
    @Test("Time series calculates aggregates")
    func timeSeriesAggregates() {
        let now = Date()
        let points = [
            QualityDataPoint(timestamp: now, successRate: 0.90, attemptCount: 100, successCount: 90, errorCount: 10),
            QualityDataPoint(timestamp: now.addingTimeInterval(3600), successRate: 0.80, attemptCount: 100, successCount: 80, errorCount: 20)
        ]
        
        let series = TimeSeriesQuality(
            bucket: .hour,
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            dataPoints: points
        )
        
        #expect(abs(series.averageSuccessRate - 0.85) < 0.001)
        #expect(series.totalAttempts == 200)
        #expect(series.totalSuccesses == 170)
        #expect(series.totalErrors == 30)
    }
    
    @Test("Empty time series has zero aggregates")
    func emptyTimeSeries() {
        let now = Date()
        let series = TimeSeriesQuality(
            bucket: .day,
            startDate: now,
            endDate: now,
            dataPoints: []
        )
        
        #expect(series.averageSuccessRate == 0)
        #expect(series.totalAttempts == 0)
        #expect(series.trend.trend == .insufficient)
    }
}

// MARK: - Device Quality Stats Tests

@Suite("Device Quality Stats")
struct DeviceStatsTests {
    
    @Test("Device stats calculation")
    func statsCalculation() {
        let now = Date()
        let stats = DeviceQualityStats(
            deviceId: "device-123",
            deviceName: "Test Device",
            firstSeen: now,
            lastSeen: now.addingTimeInterval(3600),
            totalAttempts: 100,
            successfulAttempts: 95,
            averageLatencyMs: 250,
            minLatencyMs: 100,
            maxLatencyMs: 500,
            totalRetries: 5,
            totalTimeouts: 2,
            errorBreakdown: ["timeout": 2, "disconnected": 3]
        )
        
        #expect(stats.successRate == 0.95)
        #expect(stats.failedAttempts == 5)
        #expect(stats.mostCommonError == "disconnected")
    }
    
    @Test("Device stats redaction")
    func statsRedaction() {
        let stats = DeviceQualityStats(
            deviceId: "device-123",
            deviceName: "My Device",
            firstSeen: Date(),
            lastSeen: Date(),
            totalAttempts: 100,
            successfulAttempts: 95
        )
        
        let redacted = stats.redacted()
        #expect(redacted.deviceId == "[REDACTED]")
        #expect(redacted.deviceName == "[REDACTED]")
        #expect(redacted.totalAttempts == 100)
    }
    
    @Test("Device stats is Identifiable")
    func identifiable() {
        let stats = DeviceQualityStats(
            deviceId: "device-abc",
            firstSeen: Date(),
            lastSeen: Date(),
            totalAttempts: 50,
            successfulAttempts: 45
        )
        
        #expect(stats.id == "device-abc")
    }
}

// MARK: - Version Quality Stats Tests

@Suite("Version Quality Stats")
struct VersionStatsTests {
    
    @Test("Version stats recommendation - recommended")
    func recommendedVersion() {
        let stats = VersionQualityStats(
            version: "1.0.5",
            deviceCount: 10,
            totalAttempts: 100,
            successfulAttempts: 96
        )
        
        #expect(stats.recommendation == .recommended)
        #expect(stats.successRate == 0.96)
    }
    
    @Test("Version stats recommendation - acceptable")
    func acceptableVersion() {
        let stats = VersionQualityStats(
            version: "1.0.4",
            deviceCount: 10,
            totalAttempts: 100,
            successfulAttempts: 85
        )
        
        #expect(stats.recommendation == .acceptable)
    }
    
    @Test("Version stats recommendation - problematic")
    func problematicVersion() {
        let stats = VersionQualityStats(
            version: "1.0.3",
            deviceCount: 10,
            totalAttempts: 100,
            successfulAttempts: 65
        )
        
        #expect(stats.recommendation == .problematic)
    }
    
    @Test("Version stats recommendation - avoid")
    func avoidVersion() {
        let stats = VersionQualityStats(
            version: "1.0.2",
            deviceCount: 10,
            totalAttempts: 100,
            successfulAttempts: 50
        )
        
        #expect(stats.recommendation == .avoid)
    }
    
    @Test("Version stats recommendation - insufficient data")
    func insufficientDataVersion() {
        let stats = VersionQualityStats(
            version: "1.0.1",
            deviceCount: 2,
            totalAttempts: 5,
            successfulAttempts: 5
        )
        
        #expect(stats.recommendation == .insufficientData)
    }
    
    @Test("Recommendation symbols are unique")
    func recommendationSymbols() {
        let all: [VersionRecommendation] = [.recommended, .acceptable, .problematic, .avoid, .insufficientData]
        let symbols = all.map { $0.symbol }
        #expect(Set(symbols).count == symbols.count)
    }
}

// MARK: - Platform Quality Stats Tests

@Suite("Platform Quality Stats")
struct PlatformStatsTests {
    
    @Test("Platform stats creation")
    func statsCreation() {
        let stats = PlatformQualityStats(
            platform: "iOS",
            osVersion: "17.0",
            deviceCount: 50,
            totalAttempts: 1000,
            successfulAttempts: 950,
            commonIssues: ["Background mode timeout"]
        )
        
        #expect(stats.id == "iOS-17.0")
        #expect(stats.successRate == 0.95)
        #expect(stats.commonIssues.count == 1)
    }
}

// MARK: - Protocol Quality Stats Tests

@Suite("Protocol Quality Stats")
struct ProtocolStatsTests {
    
    @Test("Protocol stats with phase breakdown")
    func protocolPhases() {
        let stats = ProtocolQualityStats(
            protocolName: "DexcomG7",
            protocolVersion: "1.0",
            deviceCount: 20,
            totalAttempts: 500,
            successfulAttempts: 475,
            averageLatencyMs: 800,
            phaseSuccessRates: [
                "discovery": 0.98,
                "authentication": 0.92,
                "dataTransfer": 0.95
            ]
        )
        
        #expect(stats.id == "DexcomG7-1.0")
        #expect(stats.successRate == 0.95)
        #expect(stats.weakestPhase == "authentication")
    }
    
    @Test("Protocol stats without phases")
    func noPhases() {
        let stats = ProtocolQualityStats(
            protocolName: "Generic",
            protocolVersion: "1.0",
            deviceCount: 5,
            totalAttempts: 100,
            successfulAttempts: 90
        )
        
        #expect(stats.weakestPhase == nil)
    }
}

// MARK: - Aggregate Quality Report Tests

@Suite("Aggregate Quality Report Schema")
struct AggregateQualityReportSchemaTests {
    
    @Test("Report creation with stats")
    func reportCreation() {
        let now = Date()
        let deviceStats = [
            DeviceQualityStats(deviceId: "d1", firstSeen: now, lastSeen: now, totalAttempts: 100, successfulAttempts: 98),
            DeviceQualityStats(deviceId: "d2", firstSeen: now, lastSeen: now, totalAttempts: 100, successfulAttempts: 60)
        ]
        
        let versionStats = [
            VersionQualityStats(version: "1.0.5", deviceCount: 1, totalAttempts: 100, successfulAttempts: 98),
            VersionQualityStats(version: "1.0.2", deviceCount: 1, totalAttempts: 100, successfulAttempts: 50)
        ]
        
        let report = AggregateQualityReport(
            title: "Test Report",
            periodStart: now,
            periodEnd: now.addingTimeInterval(86400),
            deviceStats: deviceStats,
            versionStats: versionStats
        )
        
        #expect(report.title == "Test Report")
        #expect(report.totalDevices == 2)
        #expect(report.totalAttempts == 200)
        #expect(report.totalSuccesses == 158)
        #expect(report.overallSuccessRate == 0.79)
        #expect(report.topPerformingDevices.contains("d1"))
        #expect(report.problematicDevices.contains("d2"))
        #expect(report.recommendedVersions.contains("1.0.5"))
        #expect(report.avoidVersions.contains("1.0.2"))
    }
    
    @Test("Report schema version")
    func schemaVersion() {
        let report = AggregateQualityReport(
            title: "Test",
            periodStart: Date(),
            periodEnd: Date()
        )
        
        #expect(report.schemaVersion == "1.0.0")
        #expect(report.schemaVersion == AggregateQualityReport.schemaVersion)
    }
    
    @Test("Report period duration")
    func periodDuration() {
        let now = Date()
        let report = AggregateQualityReport(
            title: "Test",
            periodStart: now,
            periodEnd: now.addingTimeInterval(86400)
        )
        
        #expect(report.periodDuration == 86400)
    }
    
    @Test("Report JSON round-trip")
    func jsonRoundTrip() throws {
        let now = Date()
        let report = AggregateQualityReport(
            title: "JSON Test",
            description: "Testing serialization",
            periodStart: now,
            periodEnd: now.addingTimeInterval(3600),
            deviceStats: [
                DeviceQualityStats(deviceId: "d1", firstSeen: now, lastSeen: now, totalAttempts: 50, successfulAttempts: 48)
            ],
            metadata: ["source": "test"]
        )
        
        let json = try report.toJSON()
        let decoded = try AggregateQualityReport.fromJSON(json)
        
        #expect(decoded.title == report.title)
        #expect(decoded.description == report.description)
        #expect(decoded.schemaVersion == report.schemaVersion)
        #expect(decoded.deviceStats.count == 1)
        #expect(decoded.metadata["source"] == "test")
    }
    
    @Test("Report redaction")
    func reportRedaction() {
        let now = Date()
        let report = AggregateQualityReport(
            title: "Test",
            periodStart: now,
            periodEnd: now,
            deviceStats: [
                DeviceQualityStats(deviceId: "secret-123", deviceName: "My Device", firstSeen: now, lastSeen: now, totalAttempts: 10, successfulAttempts: 9)
            ]
        )
        
        let redacted = report.redacted()
        #expect(redacted.deviceStats[0].deviceId == "[REDACTED]")
        #expect(redacted.title == "Test")
    }
    
    @Test("Empty report has zero metrics")
    func emptyReport() {
        let report = AggregateQualityReport(
            title: "Empty",
            periodStart: Date(),
            periodEnd: Date()
        )
        
        #expect(report.totalDevices == 0)
        #expect(report.totalAttempts == 0)
        #expect(report.overallSuccessRate == 0)
    }
}

// MARK: - Aggregate Report Builder Tests

@Suite("Aggregate Report Builder")
struct AggregateBuilderTests {
    
    @Test("Builder creates report")
    func builderCreation() {
        let now = Date()
        let report = AggregateReportBuilder()
            .title("Builder Test")
            .description("Built with builder")
            .period(start: now, end: now.addingTimeInterval(3600))
            .metadata("key", "value")
            .build()
        
        #expect(report.title == "Builder Test")
        #expect(report.description == "Built with builder")
        #expect(report.metadata["key"] == "value")
    }
    
    @Test("Builder adds device stats")
    func builderDeviceStats() {
        let now = Date()
        let stats = DeviceQualityStats(
            deviceId: "d1",
            firstSeen: now,
            lastSeen: now,
            totalAttempts: 100,
            successfulAttempts: 95
        )
        
        let report = AggregateReportBuilder()
            .title("Test")
            .period(start: now, end: now)
            .addDeviceStats(stats)
            .build()
        
        #expect(report.deviceStats.count == 1)
        #expect(report.totalDevices == 1)
    }
    
    @Test("Builder adds version stats")
    func builderVersionStats() {
        let stats = VersionQualityStats(
            version: "1.0.5",
            deviceCount: 5,
            totalAttempts: 100,
            successfulAttempts: 98
        )
        
        let report = AggregateReportBuilder()
            .title("Test")
            .period(start: Date(), end: Date())
            .addVersionStats(stats)
            .build()
        
        #expect(report.versionStats.count == 1)
    }
    
    @Test("Builder adds platform stats")
    func builderPlatformStats() {
        let stats = PlatformQualityStats(
            platform: "iOS",
            osVersion: "17.0",
            deviceCount: 10,
            totalAttempts: 500,
            successfulAttempts: 490
        )
        
        let report = AggregateReportBuilder()
            .title("Test")
            .period(start: Date(), end: Date())
            .addPlatformStats(stats)
            .build()
        
        #expect(report.platformStats.count == 1)
    }
    
    @Test("Builder adds protocol stats")
    func builderProtocolStats() {
        let stats = ProtocolQualityStats(
            protocolName: "DexcomG7",
            protocolVersion: "1.0",
            deviceCount: 15,
            totalAttempts: 300,
            successfulAttempts: 285
        )
        
        let report = AggregateReportBuilder()
            .title("Test")
            .period(start: Date(), end: Date())
            .addProtocolStats(stats)
            .build()
        
        #expect(report.protocolStats.count == 1)
    }
    
    @Test("Builder adds time series")
    func builderTimeSeries() {
        let now = Date()
        let series = TimeSeriesQuality(
            bucket: .hour,
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            dataPoints: [
                QualityDataPoint(timestamp: now, successRate: 0.95, attemptCount: 100, successCount: 95)
            ]
        )
        
        let report = AggregateReportBuilder()
            .title("Test")
            .period(start: now, end: now.addingTimeInterval(3600))
            .timeSeries(series)
            .build()
        
        #expect(report.timeSeries != nil)
    }
}

// MARK: - Quality Aggregator Tests

@Suite("Quality Aggregator")
struct QualityAggregatorTests {
    
    func createTestReport(deviceId: String, firmware: String, success: Bool, latencyMs: Int = 500) -> ProtocolReport {
        let now = Date()
        return ProtocolReportBuilder()
            .sessionId(UUID().uuidString)
            .protocolName("Test")
            .deviceInfo(ReportDeviceInfo(deviceId: deviceId, name: "Test", firmware: firmware))
            .addAttempt(AttemptRecord(
                attemptNumber: 1,
                startTime: now,
                endTime: now.addingTimeInterval(Double(latencyMs) / 1000),
                success: success,
                errorMessage: success ? nil : "Error"
            ))
            .build()
    }
    
    @Test("Aggregate by device")
    func aggregateByDevice() {
        let aggregator = QualityAggregator()
        let reports = [
            createTestReport(deviceId: "d1", firmware: "1.0", success: true),
            createTestReport(deviceId: "d1", firmware: "1.0", success: true),
            createTestReport(deviceId: "d2", firmware: "1.0", success: false)
        ]
        
        let stats = aggregator.aggregateByDevice(reports)
        #expect(stats.count == 2)
        
        let d1Stats = stats.first { $0.deviceId == "d1" }
        #expect(d1Stats?.totalAttempts == 2)
        #expect(d1Stats?.successfulAttempts == 2)
    }
    
    @Test("Aggregate by version")
    func aggregateByVersion() {
        let aggregator = QualityAggregator()
        let reports = [
            createTestReport(deviceId: "d1", firmware: "1.0.5", success: true),
            createTestReport(deviceId: "d2", firmware: "1.0.5", success: true),
            createTestReport(deviceId: "d3", firmware: "1.0.2", success: false)
        ]
        
        let stats = aggregator.aggregateByVersion(reports)
        #expect(stats.count == 2)
        
        let v105 = stats.first { $0.version == "1.0.5" }
        #expect(v105?.deviceCount == 2)
        #expect(v105?.successRate == 1.0)
    }
    
    @Test("Create time series")
    func createTimeSeries() {
        let aggregator = QualityAggregator()
        let now = Date()
        
        var reports: [ProtocolReport] = []
        for i in 0..<5 {
            let reportTime = now.addingTimeInterval(Double(i) * 3600)
            let report = ProtocolReportBuilder()
                .sessionId(UUID().uuidString)
                .protocolName("Test")
                .deviceInfo(ReportDeviceInfo(deviceId: "d1", name: "Test", firmware: "1.0"))
                .addAttempt(AttemptRecord(
                    attemptNumber: 1,
                    startTime: reportTime,
                    endTime: reportTime.addingTimeInterval(0.5),
                    success: true
                ))
                .build()
            reports.append(report)
        }
        
        let series = aggregator.createTimeSeries(reports, bucket: .hour)
        #expect(series != nil)
        #expect(series!.bucket == .hour)
    }
    
    @Test("Build complete report")
    func buildCompleteReport() {
        let aggregator = QualityAggregator()
        let reports = [
            createTestReport(deviceId: "d1", firmware: "1.0.5", success: true),
            createTestReport(deviceId: "d1", firmware: "1.0.5", success: true),
            createTestReport(deviceId: "d2", firmware: "1.0.2", success: false)
        ]
        
        let report = aggregator.buildReport(title: "Test Report", reports: reports)
        
        #expect(report.title == "Test Report")
        #expect(report.deviceStats.count == 2)
        #expect(report.versionStats.count == 2)
    }
    
    @Test("Empty reports produce empty aggregation")
    func emptyAggregation() {
        let aggregator = QualityAggregator()
        let deviceStats = aggregator.aggregateByDevice([])
        let versionStats = aggregator.aggregateByVersion([])
        let timeSeries = aggregator.createTimeSeries([], bucket: .day)
        
        #expect(deviceStats.isEmpty)
        #expect(versionStats.isEmpty)
        #expect(timeSeries == nil)
    }
}

// MARK: - Report Summary Tests

@Suite("Aggregate Report Summary")
struct ReportSummaryTests {
    
    @Test("Summary contains title")
    func summaryTitle() {
        let report = AggregateQualityReport(
            title: "My Quality Report",
            periodStart: Date(),
            periodEnd: Date()
        )
        
        let summary = AggregateReportSummary(report)
        #expect(summary.text.contains("My Quality Report"))
    }
    
    @Test("Summary contains metrics")
    func summaryMetrics() {
        let now = Date()
        let report = AggregateQualityReport(
            title: "Test",
            periodStart: now,
            periodEnd: now,
            deviceStats: [
                DeviceQualityStats(deviceId: "d1", firstSeen: now, lastSeen: now, totalAttempts: 100, successfulAttempts: 95)
            ]
        )
        
        let summary = AggregateReportSummary(report)
        #expect(summary.text.contains("Devices: 1"))
        #expect(summary.text.contains("Total Attempts: 100"))
    }
    
    @Test("Summary includes version breakdown")
    func summaryVersions() {
        let now = Date()
        let report = AggregateQualityReport(
            title: "Test",
            periodStart: now,
            periodEnd: now,
            versionStats: [
                VersionQualityStats(version: "1.0.5", deviceCount: 5, totalAttempts: 100, successfulAttempts: 98)
            ]
        )
        
        let summary = AggregateReportSummary(report)
        #expect(summary.text.contains("VERSION BREAKDOWN"))
        #expect(summary.text.contains("1.0.5"))
    }
}
