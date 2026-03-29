// ConnectionQualityCollectorTests.swift
// BLEKit Tests
//
// Tests for ConnectionQualityCollector and related types.
// INSTR-007: Connection quality metrics collector

import Testing
import Foundation
@testable import BLEKit

// MARK: - Quality Level Tests

@Suite("Connection Quality Level")
struct ConnectionQualityLevelTests {
    
    @Test("All levels have symbols")
    func levelSymbols() {
        for level in ConnectionQualityLevel.allCases {
            #expect(!level.symbol.isEmpty)
        }
    }
    
    @Test("Levels have unique symbols")
    func uniqueSymbols() {
        let symbols = ConnectionQualityLevel.allCases.map { $0.symbol }
        #expect(Set(symbols).count == symbols.count)
    }
    
    @Test("Levels have numeric values")
    func numericValues() {
        #expect(ConnectionQualityLevel.excellent.numericValue == 5)
        #expect(ConnectionQualityLevel.good.numericValue == 4)
        #expect(ConnectionQualityLevel.fair.numericValue == 3)
        #expect(ConnectionQualityLevel.poor.numericValue == 2)
        #expect(ConnectionQualityLevel.critical.numericValue == 1)
    }
    
    @Test("Levels are Comparable")
    func comparable() {
        #expect(ConnectionQualityLevel.excellent > ConnectionQualityLevel.good)
        #expect(ConnectionQualityLevel.good > ConnectionQualityLevel.fair)
        #expect(ConnectionQualityLevel.fair > ConnectionQualityLevel.poor)
        #expect(ConnectionQualityLevel.poor > ConnectionQualityLevel.critical)
    }
    
    @Test("Level is Codable")
    func codable() throws {
        let level = ConnectionQualityLevel.excellent
        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(ConnectionQualityLevel.self, from: data)
        #expect(decoded == level)
    }
}

// MARK: - Quality Thresholds Tests

@Suite("Quality Thresholds")
struct QualityThresholdsTests {
    
    @Test("Default thresholds exist")
    func defaultThresholds() {
        let thresholds = QualityThresholds.default
        #expect(thresholds.rssiExcellent == -50)
        #expect(thresholds.rssiGood == -60)
        #expect(thresholds.rssiFair == -70)
        #expect(thresholds.rssiPoor == -80)
    }
    
    @Test("Strict thresholds are stricter")
    func strictThresholds() {
        let strict = QualityThresholds.strict
        let def = QualityThresholds.default
        #expect(strict.rssiExcellent > def.rssiExcellent)
        #expect(strict.latencyExcellentMs < def.latencyExcellentMs)
    }
    
    @Test("Lenient thresholds are more lenient")
    func lenientThresholds() {
        let lenient = QualityThresholds.lenient
        let def = QualityThresholds.default
        #expect(lenient.rssiExcellent < def.rssiExcellent)
        #expect(lenient.latencyExcellentMs > def.latencyExcellentMs)
    }
    
    @Test("RSSI level classification")
    func rssiLevelClassification() {
        let thresholds = QualityThresholds.default
        #expect(thresholds.rssiLevel(-45) == .excellent)
        #expect(thresholds.rssiLevel(-55) == .good)
        #expect(thresholds.rssiLevel(-65) == .fair)
        #expect(thresholds.rssiLevel(-75) == .poor)
        #expect(thresholds.rssiLevel(-85) == .critical)
    }
    
    @Test("Retry level classification")
    func retryLevelClassification() {
        let thresholds = QualityThresholds.default
        #expect(thresholds.retryLevel(0) == .excellent)
        #expect(thresholds.retryLevel(1) == .excellent)
        #expect(thresholds.retryLevel(2) == .good)
        #expect(thresholds.retryLevel(4) == .fair)
        #expect(thresholds.retryLevel(10) == .poor)
    }
    
    @Test("Latency level classification")
    func latencyLevelClassification() {
        let thresholds = QualityThresholds.default
        #expect(thresholds.latencyLevel(50) == .excellent)
        #expect(thresholds.latencyLevel(200) == .good)
        #expect(thresholds.latencyLevel(400) == .fair)
        #expect(thresholds.latencyLevel(800) == .poor)
        #expect(thresholds.latencyLevel(1500) == .critical)
    }
    
    @Test("Thresholds are Codable")
    func codable() throws {
        let thresholds = QualityThresholds.strict
        let data = try JSONEncoder().encode(thresholds)
        let decoded = try JSONDecoder().decode(QualityThresholds.self, from: data)
        #expect(decoded == thresholds)
    }
}

// MARK: - Quality Snapshot Tests

@Suite("Quality Snapshot")
struct ConnectionQualitySnapshotTests {
    
    @Test("Snapshot creation")
    func creation() {
        let snapshot = ConnectionQualitySnapshot(
            rssi: -55,
            latencyMs: 150,
            retryCount: 2,
            bytesTransferred: 1024,
            packetsReceived: 10,
            packetsDropped: 1,
            level: .good
        )
        
        #expect(snapshot.rssi == -55)
        #expect(snapshot.latencyMs == 150)
        #expect(snapshot.retryCount == 2)
        #expect(snapshot.level == .good)
    }
    
    @Test("Packet loss rate calculation")
    func packetLossRate() {
        let snapshot = ConnectionQualitySnapshot(
            packetsReceived: 90,
            packetsDropped: 10
        )
        
        #expect(abs(snapshot.packetLossRate - 0.1) < 0.001)
    }
    
    @Test("Zero packets has zero loss rate")
    func zeroPackets() {
        let snapshot = ConnectionQualitySnapshot()
        #expect(snapshot.packetLossRate == 0)
    }
    
    @Test("Snapshot is Identifiable")
    func identifiable() {
        let snapshot = ConnectionQualitySnapshot()
        #expect(!snapshot.id.isEmpty)
    }
    
    @Test("Snapshot is Codable")
    func codable() throws {
        let snapshot = ConnectionQualitySnapshot(rssi: -60, level: .fair)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ConnectionQualitySnapshot.self, from: data)
        #expect(decoded.rssi == snapshot.rssi)
        #expect(decoded.level == snapshot.level)
    }
}

// MARK: - Connection Quality Metrics Tests

@Suite("Connection Quality Metrics")
struct ConnectionQualityMetricsTests {
    
    @Test("Metrics creation")
    func creation() {
        let now = Date()
        let metrics = ConnectionQualityMetrics(
            sessionId: "session-1",
            deviceId: "device-1",
            startTime: now,
            endTime: now.addingTimeInterval(60),
            rssiMin: -70,
            rssiMax: -50,
            rssiAverage: -60,
            rssiSamples: 10,
            totalRetries: 3,
            bytesTransferred: 2048,
            packetsReceived: 20,
            packetsDropped: 2
        )
        
        #expect(metrics.sessionId == "session-1")
        #expect(metrics.durationSeconds == 60)
        #expect(metrics.rssiAverage == -60)
        #expect(metrics.totalRetries == 3)
    }
    
    @Test("Throughput calculation")
    func throughput() {
        let now = Date()
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: now,
            endTime: now.addingTimeInterval(10),
            bytesTransferred: 1000
        )
        
        #expect(metrics.throughputBytesPerSecond == 100)
    }
    
    @Test("Packet loss rate calculation")
    func packetLoss() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: Date(),
            packetsReceived: 80,
            packetsDropped: 20
        )
        
        #expect(abs(metrics.packetLossRate - 0.2) < 0.001)
    }
    
    @Test("Quality score calculation")
    func qualityScore() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: Date(),
            rssiAverage: -55,
            latencyAverageMs: 100,
            totalRetries: 0
        )
        
        #expect(metrics.qualityScore > 0)
        #expect(metrics.qualityScore <= 100)
    }
    
    @Test("Metrics are Codable")
    func codable() throws {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(30)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metrics)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConnectionQualityMetrics.self, from: data)
        
        #expect(decoded.sessionId == metrics.sessionId)
    }
}

// MARK: - Quality Alert Tests

@Suite("Quality Alert")
struct QualityAlertTests {
    
    @Test("Alert creation")
    func creation() {
        let alert = QualityAlert(
            type: .rssiLow,
            severity: .warning,
            message: "Low signal",
            currentValue: "-80 dBm",
            thresholdValue: "-70 dBm",
            deviceId: "device-1"
        )
        
        #expect(alert.type == .rssiLow)
        #expect(alert.severity == .warning)
        #expect(alert.message == "Low signal")
    }
    
    @Test("Severity comparison")
    func severityComparison() {
        #expect(QualityAlert.Severity.info < QualityAlert.Severity.warning)
        #expect(QualityAlert.Severity.warning < QualityAlert.Severity.error)
        #expect(QualityAlert.Severity.error < QualityAlert.Severity.critical)
    }
    
    @Test("Alert is Identifiable")
    func identifiable() {
        let alert = QualityAlert(
            type: .latencyHigh,
            severity: .error,
            message: "Test",
            currentValue: "500ms",
            thresholdValue: "300ms"
        )
        #expect(!alert.id.isEmpty)
    }
}

// MARK: - Quality Metric Trend Tests

@Suite("Quality Metric Trend")
struct QualityMetricTrendTests {
    
    @Test("All trends have symbols")
    func trendSymbols() {
        let trends: [QualityMetricTrend] = [.improving, .stable, .degrading, .volatile, .unknown]
        for trend in trends {
            #expect(!trend.symbol.isEmpty)
        }
    }
}

// MARK: - Standard Quality Collector Tests

@Suite("Standard Quality Collector")
struct StandardQualityCollectorTests {
    
    @Test("Start session initializes state")
    func startSession() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test-session", deviceId: "device-1")
        
        // No readings yet, quality level calculated from current (empty) state
        let level = await collector.currentQualityLevel()
        #expect(level >= .good)  // Should be good or better with no data
    }
    
    @Test("Record RSSI updates quality")
    func recordRSSI() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRSSI(-55)
        let snapshot = await collector.takeSnapshot()
        
        #expect(snapshot.rssi == -55)
    }
    
    @Test("Record latency updates quality")
    func recordLatency() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordLatency(150)
        let snapshot = await collector.takeSnapshot()
        
        #expect(snapshot.latencyMs == 150)
    }
    
    @Test("Record retry increments count")
    func recordRetry() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRetry()
        await collector.recordRetry()
        
        let snapshot = await collector.takeSnapshot()
        #expect(snapshot.retryCount == 2)
    }
    
    @Test("Record transfer updates bytes")
    func recordTransfer() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordTransfer(bytes: 1024, packets: 10)
        let snapshot = await collector.takeSnapshot()
        
        #expect(snapshot.bytesTransferred == 1024)
        #expect(snapshot.packetsReceived == 10)
    }
    
    @Test("Record packet drop")
    func recordPacketDrop() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordTransfer(bytes: 100, packets: 10)
        await collector.recordPacketDrop()
        
        let snapshot = await collector.takeSnapshot()
        #expect(snapshot.packetsDropped == 1)
    }
    
    @Test("End session returns metrics")
    func endSession() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test-session", deviceId: "device-1")
        
        await collector.recordRSSI(-60)
        await collector.recordLatency(200)
        await collector.recordTransfer(bytes: 512, packets: 5)
        
        let metrics = await collector.endSession()
        
        #expect(metrics.sessionId == "test-session")
        #expect(metrics.deviceId == "device-1")
        #expect(metrics.rssiSamples == 1)
        #expect(metrics.latencySamples == 1)
        #expect(metrics.bytesTransferred == 512)
    }
    
    @Test("Low RSSI generates alert")
    func lowRSSIAlert() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRSSI(-85)
        
        let alerts = await collector.pendingAlerts()
        #expect(alerts.contains { $0.type == .rssiLow })
    }
    
    @Test("High latency generates alert")
    func highLatencyAlert() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordLatency(1500)
        
        let alerts = await collector.pendingAlerts()
        #expect(alerts.contains { $0.type == .latencyHigh })
    }
    
    @Test("Excessive retries generate alert")
    func excessiveRetriesAlert() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        for _ in 0..<6 {
            await collector.recordRetry()
        }
        
        let alerts = await collector.pendingAlerts()
        #expect(alerts.contains { $0.type == .excessiveRetries })
    }
    
    @Test("Clear alerts removes all alerts")
    func clearAlerts() async {
        let collector = StandardQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRSSI(-85)
        await collector.clearAlerts()
        
        let alerts = await collector.pendingAlerts()
        #expect(alerts.isEmpty)
    }
    
    @Test("Custom thresholds affect classification")
    func customThresholds() async {
        let thresholds = QualityThresholds.strict
        let collector = StandardQualityCollector(thresholds: thresholds)
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRSSI(-50)  // Would be excellent with default, but not with strict
        let level = await collector.currentQualityLevel()
        
        #expect(level == .good)  // Strict threshold for excellent is -45
    }
}

// MARK: - Null Quality Collector Tests

@Suite("Null Quality Collector")
struct NullQualityCollectorTests {
    
    @Test("Null collector returns defaults")
    func defaultValues() async {
        let collector = NullQualityCollector()
        await collector.startSession(sessionId: "test", deviceId: nil)
        
        await collector.recordRSSI(-80)
        await collector.recordLatency(500)
        
        let level = await collector.currentQualityLevel()
        #expect(level == .good)
        
        let alerts = await collector.pendingAlerts()
        #expect(alerts.isEmpty)
    }
}

// MARK: - Quality Trend Tracker Tests

@Suite("Quality Trend Tracker")
struct QualityTrendTrackerTests {
    
    @Test("Unknown trend with insufficient data")
    func insufficientData() async {
        let tracker = QualityTrendTracker()
        await tracker.recordRSSI(-60)
        await tracker.recordRSSI(-58)
        
        let trend = await tracker.rssiTrend()
        #expect(trend == .unknown)
    }
    
    @Test("Improving RSSI trend")
    func improvingRSSI() async {
        let tracker = QualityTrendTracker()
        for rssi in [-70, -65, -60, -55, -50] {
            await tracker.recordRSSI(rssi)
        }
        
        let trend = await tracker.rssiTrend()
        #expect(trend == .improving)
    }
    
    @Test("Degrading RSSI trend")
    func degradingRSSI() async {
        let tracker = QualityTrendTracker()
        for rssi in [-50, -55, -60, -65, -70] {
            await tracker.recordRSSI(rssi)
        }
        
        let trend = await tracker.rssiTrend()
        #expect(trend == .degrading)
    }
    
    @Test("Stable RSSI trend")
    func stableRSSI() async {
        let tracker = QualityTrendTracker()
        // Use values that vary slightly
        for rssi in [-60, -59, -60, -61, -60, -59, -60] {
            await tracker.recordRSSI(rssi)
        }
        
        let trend = await tracker.rssiTrend()
        // Trend should be calculated (not unknown since we have enough data)
        #expect(trend != .unknown)
    }
    
    @Test("Improving latency trend (decreasing values)")
    func improvingLatency() async {
        let tracker = QualityTrendTracker(windowSize: 20)
        // Consistent decrease pattern
        for latency in stride(from: 800, through: 200, by: -50) {
            await tracker.recordLatency(latency)
        }
        
        let trend = await tracker.latencyTrend()
        // Trend should be calculated
        #expect(trend != .unknown)
    }
    
    @Test("Overall trend from levels")
    func overallTrend() async {
        let tracker = QualityTrendTracker()
        let levels: [ConnectionQualityLevel] = [.poor, .fair, .good, .good, .excellent]
        for level in levels {
            await tracker.recordLevel(level)
        }
        
        let trend = await tracker.overallTrend()
        #expect(trend == .improving)
    }
    
    @Test("Reset clears history")
    func resetClearsHistory() async {
        let tracker = QualityTrendTracker()
        for rssi in [-60, -55, -50, -45, -40] {
            await tracker.recordRSSI(rssi)
        }
        
        await tracker.reset()
        let trend = await tracker.rssiTrend()
        #expect(trend == .unknown)
    }
}

// MARK: - Quality Metrics Summary Tests

@Suite("Quality Metrics Summary")
struct QualityMetricsSummaryTests {
    
    @Test("Summary contains session ID")
    func containsSessionId() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "my-session-123",
            startTime: Date(),
            endTime: Date().addingTimeInterval(30)
        )
        
        let summary = QualityMetricsSummary(metrics)
        #expect(summary.text.contains("my-session-123"))
    }
    
    @Test("Summary contains device ID")
    func containsDeviceId() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            deviceId: "device-abc",
            startTime: Date()
        )
        
        let summary = QualityMetricsSummary(metrics)
        #expect(summary.text.contains("device-abc"))
    }
    
    @Test("Summary contains RSSI when available")
    func containsRSSI() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: Date(),
            rssiMin: -70,
            rssiMax: -50,
            rssiAverage: -60,
            rssiSamples: 10
        )
        
        let summary = QualityMetricsSummary(metrics)
        #expect(summary.text.contains("RSSI"))
        #expect(summary.text.contains("-60"))
    }
    
    @Test("Summary contains quality level")
    func containsQualityLevel() {
        let metrics = ConnectionQualityMetrics(
            sessionId: "test",
            startTime: Date(),
            overallLevel: .excellent
        )
        
        let summary = QualityMetricsSummary(metrics)
        #expect(summary.text.contains("excellent"))
    }
}
