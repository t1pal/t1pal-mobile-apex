// QualityDashboardExporterTests.swift - Tests for quality dashboard export
// Part of BLEKit
// Trace: EVID-006

import Foundation
import Testing
@testable import BLEKit

// MARK: - Export Format Tests

@Suite("Export Format")
struct ExportFormatTests {
    @Test("All formats available")
    func allFormatsAvailable() {
        let formats = ExportFormat.allCases
        #expect(formats.count == 4)
        #expect(formats.contains(.json))
        #expect(formats.contains(.jsonCompact))
        #expect(formats.contains(.csv))
        #expect(formats.contains(.summary))
    }
}

// MARK: - Dashboard Metrics Tests

@Suite("Dashboard Metrics")
struct DashboardMetricsTests {
    @Test("Create empty metrics")
    func createEmptyMetrics() {
        let metrics = DashboardMetrics.empty
        
        #expect(metrics.overallSuccessRate == 0.0)
        #expect(metrics.totalAttempts == 0)
        #expect(metrics.totalSuccesses == 0)
        #expect(metrics.totalFailures == 0)
    }
    
    @Test("Create metrics with values")
    func createMetricsWithValues() {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            avgConnectionTime: 2.5,
            p95ConnectionTime: 5.0
        )
        
        #expect(metrics.overallSuccessRate == 0.85)
        #expect(metrics.totalAttempts == 100)
        #expect(metrics.avgConnectionTime == 2.5)
    }
    
    @Test("Metrics are Equatable")
    func metricsEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let m1 = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 50,
            totalSuccesses: 45,
            totalFailures: 5,
            generatedAt: fixedDate
        )
        
        let m2 = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 50,
            totalSuccesses: 45,
            totalFailures: 5,
            generatedAt: fixedDate
        )
        
        #expect(m1 == m2)
    }
    
    @Test("Metrics are Codable")
    func metricsCodable() throws {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            successByDevice: ["dexcomG7": 0.9, "libre2": 0.8],
            avgConnectionTime: 2.5
        )
        
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(DashboardMetrics.self, from: data)
        #expect(decoded == metrics)
    }
}

// MARK: - Metrics Period Tests

@Suite("Metrics Period")
struct MetricsPeriodTests {
    @Test("All time period")
    func allTimePeriod() {
        let period = MetricsPeriod.allTime
        #expect(period.label == "All Time")
        #expect(period.start == nil)
        #expect(period.end == nil)
    }
    
    @Test("Last 24 hours period")
    func last24Hours() {
        let period = MetricsPeriod.last24Hours
        #expect(period.label == "Last 24 Hours")
        #expect(period.start != nil)
        #expect(period.end != nil)
    }
    
    @Test("Last 7 days period")
    func last7Days() {
        let period = MetricsPeriod.last7Days
        #expect(period.label == "Last 7 Days")
    }
    
    @Test("Last 30 days period")
    func last30Days() {
        let period = MetricsPeriod.last30Days
        #expect(period.label == "Last 30 Days")
    }
    
    @Test("Period is Codable")
    func periodCodable() throws {
        let period = MetricsPeriod(
            start: Date(),
            end: Date().addingTimeInterval(3600),
            label: "Custom Period"
        )
        
        let data = try JSONEncoder().encode(period)
        let decoded = try JSONDecoder().decode(MetricsPeriod.self, from: data)
        #expect(decoded.label == period.label)
    }
}

// MARK: - Failure Mode Count Tests

@Suite("Failure Mode Count")
struct FailureModeCountTests {
    @Test("Create failure mode count")
    func createFailureModeCount() {
        let count = FailureModeCount(
            mode: "connectionTimeout",
            count: 15,
            percentage: 0.25
        )
        
        #expect(count.mode == "connectionTimeout")
        #expect(count.count == 15)
        #expect(count.percentage == 0.25)
    }
}

// MARK: - Quality Snapshot Tests

@Suite("Quality Snapshot")
struct QualitySnapshotTests {
    @Test("Create snapshot")
    func createSnapshot() {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 100,
            totalSuccesses: 90,
            totalFailures: 10
        )
        
        let snapshot = QualitySnapshot(
            metrics: metrics,
            appVersion: "1.0.0"
        )
        
        #expect(snapshot.metrics.overallSuccessRate == 0.9)
        #expect(snapshot.appVersion == "1.0.0")
    }
    
    @Test("Snapshot is Codable")
    func snapshotCodable() throws {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 50,
            totalSuccesses: 42,
            totalFailures: 8
        )
        
        let snapshot = QualitySnapshot(
            metrics: metrics,
            versionSummary: VersionSummary(bestVersion: "1.2.0", versionCount: 3),
            platformSummary: PlatformSummary(bestPlatform: "iOS 17.2", platformCount: 5)
        )
        
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(QualitySnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

// MARK: - Version Summary Tests

@Suite("Version Summary")
struct VersionSummaryTests {
    @Test("Create version summary")
    func createVersionSummary() {
        let summary = VersionSummary(
            bestVersion: "1.5.0",
            worstVersion: "1.2.0",
            versionCount: 10,
            overallTrend: 0.15
        )
        
        #expect(summary.bestVersion == "1.5.0")
        #expect(summary.overallTrend == 0.15)
    }
}

// MARK: - Platform Summary Tests

@Suite("Platform Summary")
struct PlatformSummaryTests {
    @Test("Create platform summary")
    func createPlatformSummary() {
        let summary = PlatformSummary(
            bestPlatform: "iOS 17.2",
            worstPlatform: "iOS 16.4",
            platformCount: 5,
            overallTrend: 0.10
        )
        
        #expect(summary.bestPlatform == "iOS 17.2")
        #expect(summary.platformCount == 5)
    }
}

// MARK: - Failure Summary Tests

@Suite("Failure Summary")
struct FailureSummaryTests {
    @Test("Create failure summary")
    func createFailureSummary() {
        let summary = FailureSummary(
            totalFailures: 25,
            uniqueFailureModes: 8,
            topCategory: "connection",
            criticalCount: 3
        )
        
        #expect(summary.totalFailures == 25)
        #expect(summary.criticalCount == 3)
    }
}

// MARK: - Quality Dashboard Exporter Tests

@Suite("Quality Dashboard Exporter")
struct QualityDashboardExporterTests {
    @Test("Export JSON")
    func exportJSON() throws {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15
        )
        
        let data = try exporter.exportJSON(metrics)
        #expect(!data.isEmpty)
        
        let string = String(data: data, encoding: .utf8)!
        #expect(string.contains("overallSuccessRate"))
        #expect(string.contains("0.85"))
    }
    
    @Test("Export compact JSON")
    func exportCompactJSON() throws {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 50,
            totalSuccesses: 45,
            totalFailures: 5
        )
        
        let regular = try exporter.exportJSON(metrics, compact: false)
        let compact = try exporter.exportJSON(metrics, compact: true)
        
        // Compact should be smaller (no pretty printing)
        #expect(compact.count <= regular.count)
    }
    
    @Test("Export CSV")
    func exportCSV() {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            avgConnectionTime: 2.5
        )
        
        let csv = exporter.exportCSV(metrics)
        
        #expect(csv.contains("metric,value"))
        #expect(csv.contains("overall_success_rate,85.0%"))
        #expect(csv.contains("total_attempts,100"))
        #expect(csv.contains("avg_connection_time,2.50"))
    }
    
    @Test("Export device breakdown CSV")
    func exportDeviceBreakdownCSV() {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            successByDevice: ["dexcomG7": 0.95, "libre2": 0.75]
        )
        
        let csv = exporter.exportDeviceBreakdownCSV(metrics)
        
        #expect(csv.contains("device_type,success_rate"))
        #expect(csv.contains("dexcomG7,95.0%"))
        #expect(csv.contains("libre2,75.0%"))
    }
    
    @Test("Export platform breakdown CSV")
    func exportPlatformBreakdownCSV() {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            successByPlatform: ["17.2": 0.92, "16.4": 0.78]
        )
        
        let csv = exporter.exportPlatformBreakdownCSV(metrics)
        
        #expect(csv.contains("platform_version,success_rate"))
        #expect(csv.contains("17.2,92.0%"))
    }
    
    @Test("Export failure modes CSV")
    func exportFailureModesCSV() {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            topFailureModes: [
                FailureModeCount(mode: "timeout", count: 10, percentage: 0.67),
                FailureModeCount(mode: "authFailed", count: 5, percentage: 0.33)
            ]
        )
        
        let csv = exporter.exportFailureModesCSV(metrics)
        
        #expect(csv.contains("failure_mode,count,percentage"))
        #expect(csv.contains("timeout,10,67.0%"))
    }
    
    @Test("Export summary")
    func exportSummary() {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.85,
            totalAttempts: 100,
            totalSuccesses: 85,
            totalFailures: 15,
            avgConnectionTime: 2.5,
            p95ConnectionTime: 5.0,
            uniqueDevices: 3,
            uniquePlatforms: 2
        )
        
        let summary = exporter.exportSummary(metrics)
        
        #expect(summary.contains("Quality Dashboard Summary"))
        #expect(summary.contains("Overall Success Rate: 85.0%"))
        #expect(summary.contains("Total Attempts: 100"))
    }
    
    @Test("Export in all formats")
    func exportInAllFormats() throws {
        let exporter = QualityDashboardExporter()
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 50,
            totalSuccesses: 45,
            totalFailures: 5
        )
        
        for format in ExportFormat.allCases {
            let data = try exporter.export(metrics, format: format)
            #expect(!data.isEmpty)
        }
    }
    
    @Test("Export snapshot to JSON")
    func exportSnapshotToJSON() throws {
        let exporter = QualityDashboardExporter()
        let snapshot = QualitySnapshot(
            metrics: DashboardMetrics(
                period: .allTime,
                overallSuccessRate: 0.9,
                totalAttempts: 100,
                totalSuccesses: 90,
                totalFailures: 10
            )
        )
        
        let data = try exporter.exportSnapshot(snapshot)
        #expect(!data.isEmpty)
        
        let string = String(data: data, encoding: .utf8)!
        #expect(string.contains("metrics"))
    }
}

// MARK: - Export Config Tests

@Suite("Export Config")
struct ExportConfigTests {
    @Test("Default config")
    func defaultConfig() {
        let config = ExportConfig.default
        
        #expect(config.includeDeviceBreakdown)
        #expect(config.includePlatformBreakdown)
        #expect(config.includeFirmwareBreakdown)
        #expect(config.maxFailureModes == 10)
    }
    
    @Test("Minimal config")
    func minimalConfig() {
        let config = ExportConfig.minimal
        
        #expect(!config.includeDeviceBreakdown)
        #expect(!config.includePlatformBreakdown)
        #expect(config.maxFailureModes == 5)
    }
    
    @Test("Config is Codable")
    func configCodable() throws {
        let config = ExportConfig(
            includeDeviceBreakdown: true,
            maxFailureModes: 20
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ExportConfig.self, from: data)
        #expect(decoded == config)
    }
}

// MARK: - Metrics Builder Tests

@Suite("Metrics Builder")
struct MetricsBuilderTests {
    @Test("Build empty metrics")
    func buildEmptyMetrics() {
        let builder = MetricsBuilder()
        let metrics = builder.build()
        
        #expect(metrics.totalAttempts == 0)
        #expect(metrics.overallSuccessRate == 0.0)
    }
    
    @Test("Build metrics from attempts")
    func buildMetricsFromAttempts() {
        var builder = MetricsBuilder()
        
        builder.addAttempt(ConnectionAttempt(
            success: true,
            deviceType: "dexcomG7",
            platformVersion: "17.2",
            connectionTime: 2.0
        ))
        builder.addAttempt(ConnectionAttempt(
            success: true,
            deviceType: "dexcomG7",
            platformVersion: "17.2",
            connectionTime: 3.0
        ))
        builder.addAttempt(ConnectionAttempt(
            success: false,
            deviceType: "libre2",
            platformVersion: "16.4",
            failureReason: "timeout"
        ))
        
        let metrics = builder.build()
        
        #expect(metrics.totalAttempts == 3)
        #expect(metrics.totalSuccesses == 2)
        #expect(metrics.totalFailures == 1)
        #expect(metrics.avgConnectionTime == 2.5)
    }
    
    @Test("Build with device breakdown")
    func buildWithDeviceBreakdown() {
        var builder = MetricsBuilder()
        
        builder.addAttempt(ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"))
        builder.addAttempt(ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"))
        builder.addAttempt(ConnectionAttempt(success: false, deviceType: "libre2", platformVersion: "17.2"))
        
        let metrics = builder.build()
        
        #expect(metrics.successByDevice["dexcomG7"] == 1.0)
        #expect(metrics.successByDevice["libre2"] == 0.0)
    }
    
    @Test("Build with platform breakdown")
    func buildWithPlatformBreakdown() {
        var builder = MetricsBuilder()
        
        builder.addAttempt(ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"))
        builder.addAttempt(ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"))
        builder.addAttempt(ConnectionAttempt(success: false, deviceType: "dexcomG7", platformVersion: "16.4"))
        
        let metrics = builder.build()
        
        #expect(metrics.successByPlatform["17.2"] == 1.0)
        #expect(metrics.successByPlatform["16.4"] == 0.0)
    }
    
    @Test("Build with failure modes")
    func buildWithFailureModes() {
        var builder = MetricsBuilder()
        
        builder.addAttempt(ConnectionAttempt(success: false, deviceType: "dexcomG7", platformVersion: "17.2", failureReason: "timeout"))
        builder.addAttempt(ConnectionAttempt(success: false, deviceType: "dexcomG7", platformVersion: "17.2", failureReason: "timeout"))
        builder.addAttempt(ConnectionAttempt(success: false, deviceType: "dexcomG7", platformVersion: "17.2", failureReason: "authFailed"))
        
        let metrics = builder.build()
        
        #expect(metrics.topFailureModes.count == 2)
        #expect(metrics.topFailureModes[0].mode == "timeout")
        #expect(metrics.topFailureModes[0].count == 2)
    }
    
    @Test("Calculate P95 connection time")
    func calculateP95() {
        var builder = MetricsBuilder()
        
        // Add 20 attempts with varying connection times
        for i in 1...20 {
            builder.addAttempt(ConnectionAttempt(
                success: true,
                deviceType: "dexcomG7",
                platformVersion: "17.2",
                connectionTime: Double(i)
            ))
        }
        
        let metrics = builder.build()
        
        // P95 should be around 19 (95th percentile of 1-20)
        #expect(metrics.p95ConnectionTime >= 18.0)
        #expect(metrics.p95ConnectionTime <= 20.0)
    }
    
    @Test("Set period")
    func setPeriod() {
        var builder = MetricsBuilder()
        builder.setPeriod(.last7Days)
        builder.addAttempt(ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"))
        
        let metrics = builder.build()
        
        #expect(metrics.period.label == "Last 7 Days")
    }
    
    @Test("Add multiple attempts")
    func addMultipleAttempts() {
        var builder = MetricsBuilder()
        
        let attempts = [
            ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"),
            ConnectionAttempt(success: true, deviceType: "dexcomG7", platformVersion: "17.2"),
            ConnectionAttempt(success: false, deviceType: "libre2", platformVersion: "16.4")
        ]
        
        builder.addAttempts(attempts)
        let metrics = builder.build()
        
        #expect(metrics.totalAttempts == 3)
    }
}

// MARK: - Connection Attempt Tests

@Suite("Connection Attempt")
struct ConnectionAttemptTests {
    @Test("Create success attempt")
    func createSuccessAttempt() {
        let attempt = ConnectionAttempt(
            success: true,
            deviceType: "dexcomG7",
            platformVersion: "17.2",
            connectionTime: 2.5
        )
        
        #expect(attempt.success)
        #expect(attempt.connectionTime == 2.5)
    }
    
    @Test("Create failure attempt")
    func createFailureAttempt() {
        let attempt = ConnectionAttempt(
            success: false,
            deviceType: "libre2",
            platformVersion: "16.4",
            failureReason: "Connection timeout"
        )
        
        #expect(!attempt.success)
        #expect(attempt.failureReason == "Connection timeout")
    }
    
    @Test("Attempt is Codable")
    func attemptCodable() throws {
        let attempt = ConnectionAttempt(
            success: true,
            deviceType: "dexcomG7",
            platformVersion: "17.2",
            firmwareVersion: "1.5.0",
            connectionTime: 2.0
        )
        
        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(ConnectionAttempt.self, from: data)
        #expect(decoded == attempt)
    }
}

// MARK: - Dashboard Response Tests

@Suite("Dashboard Response")
struct DashboardResponseTests {
    @Test("Success response")
    func successResponse() {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 100,
            totalSuccesses: 90,
            totalFailures: 10
        )
        
        let response = DashboardResponse.success(metrics)
        
        #expect(response.success)
        #expect(response.data != nil)
        #expect(response.error == nil)
    }
    
    @Test("Error response")
    func errorResponse() {
        let response = DashboardResponse.error("Failed to fetch data")
        
        #expect(!response.success)
        #expect(response.data == nil)
        #expect(response.error == "Failed to fetch data")
    }
    
    @Test("Response is Codable")
    func responseCodable() throws {
        let metrics = DashboardMetrics(
            period: .allTime,
            overallSuccessRate: 0.9,
            totalAttempts: 50,
            totalSuccesses: 45,
            totalFailures: 5
        )
        
        let response = DashboardResponse.success(metrics)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DashboardResponse.self, from: data)
        #expect(decoded == response)
    }
}

// MARK: - Batch Export Tests

@Suite("Batch Export")
struct BatchExportTests {
    @Test("Create batch request")
    func createBatchRequest() {
        let snapshots = [
            QualitySnapshot(metrics: DashboardMetrics.empty),
            QualitySnapshot(metrics: DashboardMetrics.empty)
        ]
        
        let request = BatchExportRequest(
            snapshots: snapshots,
            format: .json,
            includeAggregates: true
        )
        
        #expect(request.snapshots.count == 2)
        #expect(request.format == .json)
    }
    
    @Test("Batch export result")
    func batchExportResult() {
        let result = BatchExportResult(
            snapshotCount: 5,
            format: .csv,
            dataSize: 1024
        )
        
        #expect(result.snapshotCount == 5)
        #expect(result.format == .csv)
        #expect(result.dataSize == 1024)
    }
}

// MARK: - Aggregate Exporter Tests

@Suite("Aggregate Exporter")
struct AggregateExporterTests {
    @Test("Aggregate empty snapshots")
    func aggregateEmptySnapshots() {
        let exporter = AggregateExporter()
        let metrics = exporter.aggregate([])
        
        #expect(metrics.totalAttempts == 0)
    }
    
    @Test("Aggregate single snapshot")
    func aggregateSingleSnapshot() {
        let exporter = AggregateExporter()
        let snapshot = QualitySnapshot(
            metrics: DashboardMetrics(
                period: .allTime,
                overallSuccessRate: 0.9,
                totalAttempts: 100,
                totalSuccesses: 90,
                totalFailures: 10
            )
        )
        
        let aggregated = exporter.aggregate([snapshot])
        
        #expect(aggregated.totalAttempts == 100)
        #expect(aggregated.totalSuccesses == 90)
    }
    
    @Test("Aggregate multiple snapshots")
    func aggregateMultipleSnapshots() {
        let exporter = AggregateExporter()
        let snapshots = [
            QualitySnapshot(
                metrics: DashboardMetrics(
                    period: .allTime,
                    overallSuccessRate: 0.8,
                    totalAttempts: 50,
                    totalSuccesses: 40,
                    totalFailures: 10
                )
            ),
            QualitySnapshot(
                metrics: DashboardMetrics(
                    period: .allTime,
                    overallSuccessRate: 0.9,
                    totalAttempts: 50,
                    totalSuccesses: 45,
                    totalFailures: 5
                )
            )
        ]
        
        let aggregated = exporter.aggregate(snapshots)
        
        #expect(aggregated.totalAttempts == 100)
        #expect(aggregated.totalSuccesses == 85)
        #expect(aggregated.totalFailures == 15)
    }
    
    @Test("Calculate trend from snapshots")
    func calculateTrend() {
        let exporter = AggregateExporter()
        let now = Date()
        
        let snapshots = [
            QualitySnapshot(
                timestamp: now.addingTimeInterval(-3600),
                metrics: DashboardMetrics(
                    period: .allTime,
                    overallSuccessRate: 0.7,
                    totalAttempts: 50,
                    totalSuccesses: 35,
                    totalFailures: 15
                )
            ),
            QualitySnapshot(
                timestamp: now,
                metrics: DashboardMetrics(
                    period: .allTime,
                    overallSuccessRate: 0.9,
                    totalAttempts: 50,
                    totalSuccesses: 45,
                    totalFailures: 5
                )
            )
        ]
        
        let aggregated = exporter.aggregate(snapshots)
        
        // Trend should be positive (0.9 - 0.7 = 0.2)
        #expect(aggregated.trend > 0)
    }
    
    @Test("Export batch")
    func exportBatch() throws {
        let exporter = AggregateExporter()
        let snapshots = [
            QualitySnapshot(
                metrics: DashboardMetrics(
                    period: .allTime,
                    overallSuccessRate: 0.85,
                    totalAttempts: 100,
                    totalSuccesses: 85,
                    totalFailures: 15
                )
            )
        ]
        
        let request = BatchExportRequest(
            snapshots: snapshots,
            format: .json,
            includeAggregates: true
        )
        
        let (data, result) = try exporter.exportBatch(request)
        
        #expect(!data.isEmpty)
        #expect(result.snapshotCount == 1)
        #expect(result.format == .json)
        #expect(result.dataSize > 0)
    }
}
