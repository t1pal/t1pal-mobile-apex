// SPDX-License-Identifier: MIT
//
// ConnectionMetricsTests.swift
// BLEKit
//
// Tests for BLE connection quality metrics.
// Trace: BLE-DIAG-004

import Foundation
import Testing
@testable import BLEKit

// MARK: - RSSISample Tests

@Suite("RSSISample")
struct RSSISampleTests {
    @Test("Init with RSSI value")
    func rssiSampleInit() {
        let sample = RSSISample(rssi: -65)
        #expect(sample.rssi == -65)
        #expect(sample.timestamp != nil)
    }
    
    @Test("Codable encoding/decoding")
    func rssiSampleCodable() throws {
        let original = RSSISample(rssi: -70, timestamp: Date())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RSSISample.self, from: data)
        #expect(decoded.rssi == original.rssi)
    }
}

// MARK: - SignalQuality Tests

@Suite("SignalQuality")
struct SignalQualityTests {
    @Test("Excellent signal quality")
    func signalQualityExcellent() {
        #expect(SignalQuality(rssi: -40) == .excellent)
        #expect(SignalQuality(rssi: -49) == .excellent)
    }
    
    @Test("Good signal quality")
    func signalQualityGood() {
        #expect(SignalQuality(rssi: -50) == .good)
        #expect(SignalQuality(rssi: -65) == .good)
    }
    
    @Test("Fair signal quality")
    func signalQualityFair() {
        #expect(SignalQuality(rssi: -66) == .fair)
        #expect(SignalQuality(rssi: -80) == .fair)
    }
    
    @Test("Weak signal quality")
    func signalQualityWeak() {
        #expect(SignalQuality(rssi: -81) == .weak)
        #expect(SignalQuality(rssi: -90) == .weak)
    }
    
    @Test("Poor signal quality")
    func signalQualityPoor() {
        #expect(SignalQuality(rssi: -91) == .poor)
        #expect(SignalQuality(rssi: -100) == .poor)
    }
    
    @Test("Signal bars")
    func signalQualityBars() {
        #expect(SignalQuality.excellent.bars == 4)
        #expect(SignalQuality.good.bars == 3)
        #expect(SignalQuality.fair.bars == 2)
        #expect(SignalQuality.weak.bars == 1)
        #expect(SignalQuality.poor.bars == 0)
    }
    
    @Test("Display name")
    func signalQualityDisplayName() {
        #expect(SignalQuality.excellent.displayName == "Excellent")
        #expect(SignalQuality.good.displayName == "Good")
        #expect(SignalQuality.fair.displayName == "Fair")
    }
}

// MARK: - ConnectionEvent Tests

@Suite("ConnectionEvent")
struct ConnectionEventTests {
    @Test("Success event")
    func connectionEventSuccess() {
        let event = ConnectionEvent(
            success: true,
            durationMs: 150,
            deviceID: "device-1"
        )
        #expect(event.success)
        #expect(event.durationMs == 150)
        #expect(event.errorReason == nil)
    }
    
    @Test("Failure event")
    func connectionEventFailure() {
        let event = ConnectionEvent(
            success: false,
            errorReason: "Timeout",
            deviceID: "device-1"
        )
        #expect(!event.success)
        #expect(event.errorReason == "Timeout")
    }
}

// MARK: - ConnectionMetrics RSSI Tests

@Suite("ConnectionMetrics RSSI")
struct ConnectionMetricsRSSITests {
    @Test("Record RSSI samples")
    func connectionMetricsRecordRSSI() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordRSSI(-60)
        metrics.recordRSSI(-65)
        metrics.recordRSSI(-55)
        
        #expect(metrics.rssiHistory.count == 3)
        #expect(metrics.currentRSSI == -55)  // Most recent
    }
    
    @Test("Average RSSI")
    func connectionMetricsAverageRSSI() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordRSSI(-60)
        metrics.recordRSSI(-70)
        metrics.recordRSSI(-80)
        
        #expect(metrics.averageRSSI == -70.0)
    }
    
    @Test("Min/Max RSSI")
    func connectionMetricsMinMaxRSSI() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordRSSI(-50)
        metrics.recordRSSI(-90)
        metrics.recordRSSI(-70)
        
        #expect(metrics.minRSSI == -90)
        #expect(metrics.maxRSSI == -50)
    }
    
    @Test("RSSI standard deviation")
    func connectionMetricsRSSIStdDev() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        // Add values with known std dev
        metrics.recordRSSI(-60)
        metrics.recordRSSI(-60)
        metrics.recordRSSI(-60)
        
        // All same values = 0 std dev
        #expect(abs((metrics.rssiStandardDeviation ?? -1) - 0.0) < 0.001)
    }
    
    @Test("Signal quality from RSSI")
    func connectionMetricsSignalQuality() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        #expect(metrics.signalQuality == .unknown)
        
        metrics.recordRSSI(-55)
        #expect(metrics.signalQuality == .good)
    }
    
    @Test("RSSI history trimming")
    func connectionMetricsRSSITrimming() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        // Add more than max samples
        for i in 0..<150 {
            metrics.recordRSSI(-50 - (i % 50))
        }
        
        #expect(metrics.rssiHistory.count == ConnectionMetrics.maxRSSISamples)
    }
}

// MARK: - ConnectionMetrics Connection Tests

@Suite("ConnectionMetrics Connection")
struct ConnectionMetricsConnectionTests {
    @Test("Record connection attempts")
    func connectionMetricsRecordConnection() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordConnection(success: true, durationMs: 100)
        metrics.recordConnection(success: true, durationMs: 150)
        metrics.recordConnection(success: false, errorReason: "Timeout")
        
        #expect(metrics.totalConnectionAttempts == 3)
        #expect(metrics.successfulConnections == 2)
        #expect(metrics.failedConnections == 1)
    }
    
    @Test("Success rate")
    func connectionMetricsSuccessRate() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordConnection(success: true)
        metrics.recordConnection(success: true)
        metrics.recordConnection(success: false)
        metrics.recordConnection(success: true)
        
        #expect(abs((metrics.successRate ?? -1) - 0.75) < 0.001)
    }
    
    @Test("Average connection time")
    func connectionMetricsAverageConnectionTime() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordConnection(success: true, durationMs: 100)
        metrics.recordConnection(success: true, durationMs: 200)
        metrics.recordConnection(success: true, durationMs: 300)
        
        #expect(abs((metrics.averageConnectionTimeMs ?? -1) - 200.0) < 0.001)
    }
    
    @Test("Most common error")
    func connectionMetricsMostCommonError() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordConnection(success: false, errorReason: "Timeout")
        metrics.recordConnection(success: false, errorReason: "Disconnected")
        metrics.recordConnection(success: false, errorReason: "Timeout")
        metrics.recordConnection(success: false, errorReason: "Timeout")
        
        #expect(metrics.mostCommonError == "Timeout")
    }
    
    @Test("Connection history trimming")
    func connectionMetricsConnectionTrimming() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        // Add more than max events
        for _ in 0..<100 {
            metrics.recordConnection(success: true)
        }
        
        #expect(metrics.connectionHistory.count == ConnectionMetrics.maxConnectionEvents)
    }
}

// MARK: - ConnectionMetrics Summary Tests

@Suite("ConnectionMetrics Summary")
struct ConnectionMetricsSummaryTests {
    @Test("Summary with data")
    func connectionMetricsSummary() {
        var metrics = ConnectionMetrics(deviceID: "test-device")
        
        metrics.recordRSSI(-60)
        metrics.recordConnection(success: true, durationMs: 100)
        metrics.recordConnection(success: true, durationMs: 100)
        
        let summary = metrics.summary
        #expect(summary.contains("RSSI"))
        #expect(summary.contains("Success"))
    }
    
    @Test("Empty summary")
    func connectionMetricsEmptySummary() {
        let metrics = ConnectionMetrics(deviceID: "test-device")
        #expect(metrics.summary == "No metrics")
    }
    
    @Test("Codable encoding/decoding")
    func connectionMetricsCodable() throws {
        var original = ConnectionMetrics(deviceID: "test-device", deviceType: "G6")
        original.recordRSSI(-65)
        original.recordConnection(success: true, durationMs: 100)
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionMetrics.self, from: data)
        
        #expect(decoded.deviceID == original.deviceID)
        #expect(decoded.deviceType == original.deviceType)
        #expect(decoded.rssiHistory.count == 1)
        #expect(decoded.connectionHistory.count == 1)
    }
}

// MARK: - MetricsCollector Tests

@Suite("MetricsCollector")
struct MetricsCollectorTests {
    @Test("Record RSSI for device")
    func metricsCollectorRecordRSSI() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordRSSI(-70, for: "device-1")
        
        let metrics = await collector.getMetrics(for: "device-1")
        #expect(metrics != nil)
        #expect(metrics?.rssiHistory.count == 2)
        #expect(metrics?.currentRSSI == -70)
    }
    
    @Test("Record connection for device")
    func metricsCollectorRecordConnection() async {
        let collector = MetricsCollector()
        
        await collector.recordConnection(success: true, for: "device-1", durationMs: 100)
        await collector.recordConnection(success: false, for: "device-1", errorReason: "Timeout")
        
        let metrics = await collector.getMetrics(for: "device-1")
        #expect(metrics?.totalConnectionAttempts == 2)
        #expect(abs((metrics?.successRate ?? -1) - 0.5) < 0.001)
    }
    
    @Test("Multiple devices")
    func metricsCollectorMultipleDevices() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordRSSI(-70, for: "device-2")
        await collector.recordRSSI(-80, for: "device-3")
        
        let deviceIDs = await collector.allDeviceIDs()
        #expect(deviceIDs.count == 3)
    }
    
    @Test("Aggregate stats")
    func metricsCollectorAggregateStats() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordRSSI(-80, for: "device-2")
        await collector.recordConnection(success: true, for: "device-1")
        await collector.recordConnection(success: true, for: "device-2")
        await collector.recordConnection(success: false, for: "device-2")
        
        let stats = await collector.aggregateStats()
        #expect(stats.deviceCount == 2)
        #expect(stats.totalAttempts == 3)
        #expect(stats.totalSuccesses == 2)
        #expect(abs((stats.overallSuccessRate ?? -1) - 2.0/3.0) < 0.001)
        #expect(abs((stats.averageRSSI ?? -1) - (-70.0)) < 0.001)
    }
    
    @Test("Clear metrics for device")
    func metricsCollectorClearMetrics() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordRSSI(-70, for: "device-2")
        
        await collector.clearMetrics(for: "device-1")
        
        let metrics1 = await collector.getMetrics(for: "device-1")
        let metrics2 = await collector.getMetrics(for: "device-2")
        
        #expect(metrics1 == nil)
        #expect(metrics2 != nil)
    }
    
    @Test("Clear all metrics")
    func metricsCollectorClearAllMetrics() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordRSSI(-70, for: "device-2")
        
        await collector.clearAllMetrics()
        
        let deviceIDs = await collector.allDeviceIDs()
        #expect(deviceIDs.count == 0)
    }
    
    @Test("Export metrics")
    func metricsCollectorExportMetrics() async {
        let collector = MetricsCollector()
        
        await collector.recordRSSI(-60, for: "device-1")
        await collector.recordConnection(success: true, for: "device-1")
        
        let exported = await collector.exportMetrics()
        #expect(exported.count == 1)
        #expect(exported.first?.deviceID == "device-1")
    }
}

// MARK: - AggregateConnectionStats Tests

@Suite("AggregateConnectionStats")
struct AggregateConnectionStatsTests {
    @Test("Empty stats")
    func aggregateStatsEmpty() {
        let stats = AggregateConnectionStats(from: [])
        #expect(stats.deviceCount == 0)
        #expect(stats.totalAttempts == 0)
        #expect(stats.overallSuccessRate == nil)
        #expect(stats.averageRSSI == nil)
    }
    
    @Test("Best/worst device")
    func aggregateStatsBestWorstDevice() {
        var metrics1 = ConnectionMetrics(deviceID: "device-1")
        metrics1.recordRSSI(-50)  // Best
        
        var metrics2 = ConnectionMetrics(deviceID: "device-2")
        metrics2.recordRSSI(-90)  // Worst
        
        var metrics3 = ConnectionMetrics(deviceID: "device-3")
        metrics3.recordRSSI(-70)  // Middle
        
        let stats = AggregateConnectionStats(from: [metrics1, metrics2, metrics3])
        #expect(stats.bestSignalDevice == "device-1")
        #expect(stats.worstSignalDevice == "device-2")
    }
}
