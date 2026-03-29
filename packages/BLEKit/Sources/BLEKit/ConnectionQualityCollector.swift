// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ConnectionQualityCollector.swift
// BLEKit
//
// Connection quality metrics collection for BLE sessions.
// Tracks RSSI, duration, retry count, throughput, and connection stability.
//
// INSTR-007: Connection quality metrics collector

import Foundation

// MARK: - Quality Level

/// Connection quality level classification.
public enum ConnectionQualityLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case excellent
    case good
    case fair
    case poor
    case critical
    
    public var symbol: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        case .critical: return "⚫"
        }
    }
    
    public var numericValue: Int {
        switch self {
        case .excellent: return 5
        case .good: return 4
        case .fair: return 3
        case .poor: return 2
        case .critical: return 1
        }
    }
    
    public static func < (lhs: ConnectionQualityLevel, rhs: ConnectionQualityLevel) -> Bool {
        lhs.numericValue < rhs.numericValue
    }
}

// MARK: - Quality Thresholds

/// Configurable thresholds for quality level classification.
public struct QualityThresholds: Sendable, Equatable, Codable {
    public let rssiExcellent: Int
    public let rssiGood: Int
    public let rssiFair: Int
    public let rssiPoor: Int
    
    public let retryCountGood: Int
    public let retryCountFair: Int
    public let retryCountPoor: Int
    
    public let latencyExcellentMs: Int
    public let latencyGoodMs: Int
    public let latencyFairMs: Int
    public let latencyPoorMs: Int
    
    public init(
        rssiExcellent: Int = -50,
        rssiGood: Int = -60,
        rssiFair: Int = -70,
        rssiPoor: Int = -80,
        retryCountGood: Int = 1,
        retryCountFair: Int = 3,
        retryCountPoor: Int = 5,
        latencyExcellentMs: Int = 100,
        latencyGoodMs: Int = 300,
        latencyFairMs: Int = 500,
        latencyPoorMs: Int = 1000
    ) {
        self.rssiExcellent = rssiExcellent
        self.rssiGood = rssiGood
        self.rssiFair = rssiFair
        self.rssiPoor = rssiPoor
        self.retryCountGood = retryCountGood
        self.retryCountFair = retryCountFair
        self.retryCountPoor = retryCountPoor
        self.latencyExcellentMs = latencyExcellentMs
        self.latencyGoodMs = latencyGoodMs
        self.latencyFairMs = latencyFairMs
        self.latencyPoorMs = latencyPoorMs
    }
    
    public static let `default` = QualityThresholds()
    
    public static let strict = QualityThresholds(
        rssiExcellent: -45,
        rssiGood: -55,
        rssiFair: -65,
        rssiPoor: -75,
        retryCountGood: 0,
        retryCountFair: 2,
        retryCountPoor: 4,
        latencyExcellentMs: 50,
        latencyGoodMs: 150,
        latencyFairMs: 300,
        latencyPoorMs: 500
    )
    
    public static let lenient = QualityThresholds(
        rssiExcellent: -55,
        rssiGood: -70,
        rssiFair: -80,
        rssiPoor: -90,
        retryCountGood: 2,
        retryCountFair: 5,
        retryCountPoor: 10,
        latencyExcellentMs: 200,
        latencyGoodMs: 500,
        latencyFairMs: 1000,
        latencyPoorMs: 2000
    )
    
    public func rssiLevel(_ rssi: Int) -> ConnectionQualityLevel {
        if rssi >= rssiExcellent { return .excellent }
        if rssi >= rssiGood { return .good }
        if rssi >= rssiFair { return .fair }
        if rssi >= rssiPoor { return .poor }
        return .critical
    }
    
    public func retryLevel(_ retryCount: Int) -> ConnectionQualityLevel {
        if retryCount <= retryCountGood { return .excellent }
        if retryCount <= retryCountFair { return .good }
        if retryCount <= retryCountPoor { return .fair }
        return .poor
    }
    
    public func latencyLevel(_ latencyMs: Int) -> ConnectionQualityLevel {
        if latencyMs <= latencyExcellentMs { return .excellent }
        if latencyMs <= latencyGoodMs { return .good }
        if latencyMs <= latencyFairMs { return .fair }
        if latencyMs <= latencyPoorMs { return .poor }
        return .critical
    }
}

// MARK: - Quality Snapshot

/// Point-in-time connection quality reading.
public struct ConnectionQualitySnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let rssi: Int?
    public let latencyMs: Int?
    public let retryCount: Int
    public let bytesTransferred: Int
    public let packetsReceived: Int
    public let packetsDropped: Int
    public let level: ConnectionQualityLevel
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        rssi: Int? = nil,
        latencyMs: Int? = nil,
        retryCount: Int = 0,
        bytesTransferred: Int = 0,
        packetsReceived: Int = 0,
        packetsDropped: Int = 0,
        level: ConnectionQualityLevel = .good
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rssi = rssi
        self.latencyMs = latencyMs
        self.retryCount = retryCount
        self.bytesTransferred = bytesTransferred
        self.packetsReceived = packetsReceived
        self.packetsDropped = packetsDropped
        self.level = level
    }
    
    public var packetLossRate: Double {
        let total = packetsReceived + packetsDropped
        guard total > 0 else { return 0 }
        return Double(packetsDropped) / Double(total)
    }
}

// MARK: - Connection Quality Metrics

/// Aggregate connection quality metrics for a session.
public struct ConnectionQualityMetrics: Sendable, Equatable, Codable {
    public let sessionId: String
    public let deviceId: String?
    public let startTime: Date
    public let endTime: Date?
    public let durationSeconds: Double
    
    // RSSI metrics
    public let rssiMin: Int?
    public let rssiMax: Int?
    public let rssiAverage: Int?
    public let rssiSamples: Int
    
    // Latency metrics
    public let latencyMinMs: Int?
    public let latencyMaxMs: Int?
    public let latencyAverageMs: Int?
    public let latencySamples: Int
    
    // Retry metrics
    public let totalRetries: Int
    public let maxConsecutiveRetries: Int
    
    // Throughput metrics
    public let bytesTransferred: Int
    public let packetsReceived: Int
    public let packetsDropped: Int
    public let throughputBytesPerSecond: Double
    
    // Overall quality
    public let overallLevel: ConnectionQualityLevel
    public let lowestLevel: ConnectionQualityLevel
    public let qualityScore: Double
    
    public init(
        sessionId: String,
        deviceId: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        rssiMin: Int? = nil,
        rssiMax: Int? = nil,
        rssiAverage: Int? = nil,
        rssiSamples: Int = 0,
        latencyMinMs: Int? = nil,
        latencyMaxMs: Int? = nil,
        latencyAverageMs: Int? = nil,
        latencySamples: Int = 0,
        totalRetries: Int = 0,
        maxConsecutiveRetries: Int = 0,
        bytesTransferred: Int = 0,
        packetsReceived: Int = 0,
        packetsDropped: Int = 0,
        overallLevel: ConnectionQualityLevel = .good,
        lowestLevel: ConnectionQualityLevel = .good
    ) {
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
        self.rssiMin = rssiMin
        self.rssiMax = rssiMax
        self.rssiAverage = rssiAverage
        self.rssiSamples = rssiSamples
        self.latencyMinMs = latencyMinMs
        self.latencyMaxMs = latencyMaxMs
        self.latencyAverageMs = latencyAverageMs
        self.latencySamples = latencySamples
        self.totalRetries = totalRetries
        self.maxConsecutiveRetries = maxConsecutiveRetries
        self.bytesTransferred = bytesTransferred
        self.packetsReceived = packetsReceived
        self.packetsDropped = packetsDropped
        self.throughputBytesPerSecond = durationSeconds > 0 ? Double(bytesTransferred) / durationSeconds : 0
        self.overallLevel = overallLevel
        self.lowestLevel = lowestLevel
        self.qualityScore = Self.calculateScore(
            rssiAverage: rssiAverage,
            latencyAverageMs: latencyAverageMs,
            totalRetries: totalRetries,
            packetLossRate: packetsReceived + packetsDropped > 0 ? Double(packetsDropped) / Double(packetsReceived + packetsDropped) : 0
        )
    }
    
    private static func calculateScore(
        rssiAverage: Int?,
        latencyAverageMs: Int?,
        totalRetries: Int,
        packetLossRate: Double
    ) -> Double {
        var score = 100.0
        
        // RSSI component (0-30 points)
        if let rssi = rssiAverage {
            let rssiScore = max(0, min(30, Double(rssi + 100) / 2))
            score = score - 30 + rssiScore
        }
        
        // Latency component (0-30 points)
        if let latency = latencyAverageMs {
            let latencyScore = max(0, 30 - Double(latency) / 33.33)
            score = score - 30 + latencyScore
        }
        
        // Retry penalty (up to 20 points)
        let retryPenalty = min(20, Double(totalRetries) * 2)
        score -= retryPenalty
        
        // Packet loss penalty (up to 20 points)
        let lossPenalty = packetLossRate * 20
        score -= lossPenalty
        
        return max(0, min(100, score))
    }
    
    public var packetLossRate: Double {
        let total = packetsReceived + packetsDropped
        guard total > 0 else { return 0 }
        return Double(packetsDropped) / Double(total)
    }
}

// MARK: - Quality Alert

/// Alert when quality drops below threshold.
public struct QualityAlert: Sendable, Equatable, Codable, Identifiable {
    public enum AlertType: String, Sendable, Codable {
        case rssiLow
        case latencyHigh
        case excessiveRetries
        case packetLoss
        case connectionUnstable
        case qualityDegraded
    }
    
    public enum Severity: String, Sendable, Codable, Comparable {
        case info
        case warning
        case error
        case critical
        
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.info, .warning, .error, .critical]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }
    
    public let id: String
    public let timestamp: Date
    public let type: AlertType
    public let severity: Severity
    public let message: String
    public let currentValue: String
    public let thresholdValue: String
    public let deviceId: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: AlertType,
        severity: Severity,
        message: String,
        currentValue: String,
        thresholdValue: String,
        deviceId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
        self.message = message
        self.currentValue = currentValue
        self.thresholdValue = thresholdValue
        self.deviceId = deviceId
    }
}

// MARK: - Quality Trend

/// Trend direction for quality metrics.
public enum QualityMetricTrend: String, Sendable, Codable {
    case improving
    case stable
    case degrading
    case volatile
    case unknown
    
    public var symbol: String {
        switch self {
        case .improving: return "↗️"
        case .stable: return "➡️"
        case .degrading: return "↘️"
        case .volatile: return "↕️"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Connection Quality Collector Protocol

/// Protocol for collecting connection quality metrics.
public protocol ConnectionQualityCollector: Sendable {
    /// Start collecting metrics for a session.
    func startSession(sessionId: String, deviceId: String?) async
    
    /// Record an RSSI reading.
    func recordRSSI(_ rssi: Int) async
    
    /// Record latency for an operation.
    func recordLatency(_ latencyMs: Int) async
    
    /// Record a retry attempt.
    func recordRetry() async
    
    /// Record bytes transferred.
    func recordTransfer(bytes: Int, packets: Int) async
    
    /// Record a dropped packet.
    func recordPacketDrop() async
    
    /// Take a quality snapshot.
    func takeSnapshot() async -> ConnectionQualitySnapshot
    
    /// End the session and get final metrics.
    func endSession() async -> ConnectionQualityMetrics
    
    /// Get current quality level.
    func currentQualityLevel() async -> ConnectionQualityLevel
    
    /// Get any pending alerts.
    func pendingAlerts() async -> [QualityAlert]
    
    /// Clear pending alerts.
    func clearAlerts() async
}

// MARK: - Standard Quality Collector

/// Standard implementation of connection quality collector.
public actor StandardQualityCollector: ConnectionQualityCollector {
    private var sessionId: String = ""
    private var deviceId: String?
    private var startTime: Date = Date()
    private var thresholds: QualityThresholds
    
    private var rssiReadings: [Int] = []
    private var latencyReadings: [Int] = []
    private var retryCount: Int = 0
    private var consecutiveRetries: Int = 0
    private var maxConsecutiveRetries: Int = 0
    private var bytesTransferred: Int = 0
    private var packetsReceived: Int = 0
    private var packetsDropped: Int = 0
    private var snapshots: [ConnectionQualitySnapshot] = []
    private var alerts: [QualityAlert] = []
    private var lowestLevel: ConnectionQualityLevel = .excellent
    private var lastSuccessfulOperation: Date = Date()
    
    public init(thresholds: QualityThresholds = .default) {
        self.thresholds = thresholds
    }
    
    public func startSession(sessionId: String, deviceId: String?) {
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.startTime = Date()
        self.rssiReadings = []
        self.latencyReadings = []
        self.retryCount = 0
        self.consecutiveRetries = 0
        self.maxConsecutiveRetries = 0
        self.bytesTransferred = 0
        self.packetsReceived = 0
        self.packetsDropped = 0
        self.snapshots = []
        self.alerts = []
        self.lowestLevel = .excellent
        self.lastSuccessfulOperation = Date()
    }
    
    public func recordRSSI(_ rssi: Int) {
        rssiReadings.append(rssi)
        
        let level = thresholds.rssiLevel(rssi)
        if level < lowestLevel {
            lowestLevel = level
        }
        
        if level <= .poor {
            let alert = QualityAlert(
                type: .rssiLow,
                severity: level == .critical ? .critical : .warning,
                message: "Signal strength is \(level.rawValue)",
                currentValue: "\(rssi) dBm",
                thresholdValue: "\(thresholds.rssiPoor) dBm",
                deviceId: deviceId
            )
            alerts.append(alert)
        }
        
        consecutiveRetries = 0
        lastSuccessfulOperation = Date()
    }
    
    public func recordLatency(_ latencyMs: Int) {
        latencyReadings.append(latencyMs)
        
        let level = thresholds.latencyLevel(latencyMs)
        if level < lowestLevel {
            lowestLevel = level
        }
        
        if level <= .poor {
            let alert = QualityAlert(
                type: .latencyHigh,
                severity: level == .critical ? .critical : .warning,
                message: "Latency is \(level.rawValue)",
                currentValue: "\(latencyMs) ms",
                thresholdValue: "\(thresholds.latencyPoorMs) ms",
                deviceId: deviceId
            )
            alerts.append(alert)
        }
        
        consecutiveRetries = 0
        lastSuccessfulOperation = Date()
    }
    
    public func recordRetry() {
        retryCount += 1
        consecutiveRetries += 1
        if consecutiveRetries > maxConsecutiveRetries {
            maxConsecutiveRetries = consecutiveRetries
        }
        
        let level = thresholds.retryLevel(retryCount)
        if level < lowestLevel {
            lowestLevel = level
        }
        
        if consecutiveRetries >= thresholds.retryCountPoor {
            let alert = QualityAlert(
                type: .excessiveRetries,
                severity: .error,
                message: "Excessive consecutive retries",
                currentValue: "\(consecutiveRetries)",
                thresholdValue: "\(thresholds.retryCountPoor)",
                deviceId: deviceId
            )
            alerts.append(alert)
        }
    }
    
    public func recordTransfer(bytes: Int, packets: Int) {
        bytesTransferred += bytes
        packetsReceived += packets
        consecutiveRetries = 0
        lastSuccessfulOperation = Date()
    }
    
    public func recordPacketDrop() {
        packetsDropped += 1
        
        let totalPackets = packetsReceived + packetsDropped
        if totalPackets >= 10 {
            let lossRate = Double(packetsDropped) / Double(totalPackets)
            if lossRate > 0.1 {
                let alert = QualityAlert(
                    type: .packetLoss,
                    severity: lossRate > 0.2 ? .error : .warning,
                    message: "High packet loss rate",
                    currentValue: String(format: "%.1f%%", lossRate * 100),
                    thresholdValue: "10%",
                    deviceId: deviceId
                )
                alerts.append(alert)
            }
        }
    }
    
    public func takeSnapshot() -> ConnectionQualitySnapshot {
        let level = calculateCurrentLevel()
        let snapshot = ConnectionQualitySnapshot(
            timestamp: Date(),
            rssi: rssiReadings.last,
            latencyMs: latencyReadings.last,
            retryCount: retryCount,
            bytesTransferred: bytesTransferred,
            packetsReceived: packetsReceived,
            packetsDropped: packetsDropped,
            level: level
        )
        snapshots.append(snapshot)
        return snapshot
    }
    
    public func endSession() -> ConnectionQualityMetrics {
        let endTime = Date()
        
        let rssiAvg = rssiReadings.isEmpty ? nil : rssiReadings.reduce(0, +) / rssiReadings.count
        let latencyAvg = latencyReadings.isEmpty ? nil : latencyReadings.reduce(0, +) / latencyReadings.count
        
        return ConnectionQualityMetrics(
            sessionId: sessionId,
            deviceId: deviceId,
            startTime: startTime,
            endTime: endTime,
            rssiMin: rssiReadings.min(),
            rssiMax: rssiReadings.max(),
            rssiAverage: rssiAvg,
            rssiSamples: rssiReadings.count,
            latencyMinMs: latencyReadings.min(),
            latencyMaxMs: latencyReadings.max(),
            latencyAverageMs: latencyAvg,
            latencySamples: latencyReadings.count,
            totalRetries: retryCount,
            maxConsecutiveRetries: maxConsecutiveRetries,
            bytesTransferred: bytesTransferred,
            packetsReceived: packetsReceived,
            packetsDropped: packetsDropped,
            overallLevel: calculateCurrentLevel(),
            lowestLevel: lowestLevel
        )
    }
    
    public func currentQualityLevel() -> ConnectionQualityLevel {
        calculateCurrentLevel()
    }
    
    public func pendingAlerts() -> [QualityAlert] {
        alerts
    }
    
    public func clearAlerts() {
        alerts.removeAll()
    }
    
    private func calculateCurrentLevel() -> ConnectionQualityLevel {
        var levels: [ConnectionQualityLevel] = []
        
        if let lastRSSI = rssiReadings.last {
            levels.append(thresholds.rssiLevel(lastRSSI))
        }
        
        if let lastLatency = latencyReadings.last {
            levels.append(thresholds.latencyLevel(lastLatency))
        }
        
        levels.append(thresholds.retryLevel(consecutiveRetries))
        
        // Return the worst level
        return levels.min() ?? .good
    }
}

// MARK: - Null Quality Collector

/// No-op implementation for testing or disabled metrics.
public actor NullQualityCollector: ConnectionQualityCollector {
    public init() {}
    
    public func startSession(sessionId: String, deviceId: String?) {}
    public func recordRSSI(_ rssi: Int) {}
    public func recordLatency(_ latencyMs: Int) {}
    public func recordRetry() {}
    public func recordTransfer(bytes: Int, packets: Int) {}
    public func recordPacketDrop() {}
    
    public func takeSnapshot() -> ConnectionQualitySnapshot {
        ConnectionQualitySnapshot()
    }
    
    public func endSession() -> ConnectionQualityMetrics {
        ConnectionQualityMetrics(
            sessionId: "",
            startTime: Date(),
            endTime: Date()
        )
    }
    
    public func currentQualityLevel() -> ConnectionQualityLevel {
        .good
    }
    
    public func pendingAlerts() -> [QualityAlert] {
        []
    }
    
    public func clearAlerts() {}
}

// MARK: - Quality Trend Tracker

/// Tracks quality trends over a rolling window.
public actor QualityTrendTracker {
    private var windowSize: Int
    private var rssiHistory: [Int] = []
    private var latencyHistory: [Int] = []
    private var levelHistory: [ConnectionQualityLevel] = []
    
    public init(windowSize: Int = 10) {
        self.windowSize = max(3, windowSize)
    }
    
    public func recordRSSI(_ rssi: Int) {
        rssiHistory.append(rssi)
        if rssiHistory.count > windowSize {
            rssiHistory.removeFirst()
        }
    }
    
    public func recordLatency(_ latencyMs: Int) {
        latencyHistory.append(latencyMs)
        if latencyHistory.count > windowSize {
            latencyHistory.removeFirst()
        }
    }
    
    public func recordLevel(_ level: ConnectionQualityLevel) {
        levelHistory.append(level)
        if levelHistory.count > windowSize {
            levelHistory.removeFirst()
        }
    }
    
    public func rssiTrend() -> QualityMetricTrend {
        analyzeTrend(rssiHistory, higherIsBetter: true)
    }
    
    public func latencyTrend() -> QualityMetricTrend {
        analyzeTrend(latencyHistory, higherIsBetter: false)
    }
    
    public func overallTrend() -> QualityMetricTrend {
        guard levelHistory.count >= 3 else { return .unknown }
        
        let values = levelHistory.map { $0.numericValue }
        return analyzeTrend(values, higherIsBetter: true)
    }
    
    private func analyzeTrend(_ values: [Int], higherIsBetter: Bool) -> QualityMetricTrend {
        guard values.count >= 3 else { return .unknown }
        
        let n = Double(values.count)
        let indices = (0..<values.count).map { Double($0) }
        let doubleValues = values.map { Double($0) }
        
        let sumX = indices.reduce(0, +)
        let sumY = doubleValues.reduce(0, +)
        let sumXY = zip(indices, doubleValues).map { $0 * $1 }.reduce(0, +)
        let sumX2 = indices.map { $0 * $0 }.reduce(0, +)
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return .stable }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        let avgY = sumY / n
        
        // Check volatility
        let variance = doubleValues.map { pow($0 - avgY, 2) }.reduce(0, +) / n
        let stdDev = sqrt(variance)
        let cv = avgY != 0 ? stdDev / abs(avgY) : 0
        
        if cv > 0.3 {
            return .volatile
        }
        
        let threshold = avgY * 0.05
        if abs(slope) < threshold {
            return .stable
        }
        
        let isIncreasing = slope > 0
        if higherIsBetter {
            return isIncreasing ? .improving : .degrading
        } else {
            return isIncreasing ? .degrading : .improving
        }
    }
    
    public func reset() {
        rssiHistory.removeAll()
        latencyHistory.removeAll()
        levelHistory.removeAll()
    }
}

// MARK: - Quality Metrics Summary

/// Human-readable summary of connection quality metrics.
public struct QualityMetricsSummary: Sendable {
    public let metrics: ConnectionQualityMetrics
    
    public init(_ metrics: ConnectionQualityMetrics) {
        self.metrics = metrics
    }
    
    public var text: String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════")
        lines.append("CONNECTION QUALITY METRICS")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        
        lines.append("Session: \(metrics.sessionId)")
        if let deviceId = metrics.deviceId {
            lines.append("Device: \(deviceId)")
        }
        lines.append("Duration: \(String(format: "%.1f", metrics.durationSeconds))s")
        lines.append("")
        
        lines.append("─── QUALITY ───")
        lines.append("Overall: \(metrics.overallLevel.symbol) \(metrics.overallLevel.rawValue)")
        lines.append("Lowest: \(metrics.lowestLevel.symbol) \(metrics.lowestLevel.rawValue)")
        lines.append("Score: \(String(format: "%.0f", metrics.qualityScore))/100")
        lines.append("")
        
        if metrics.rssiSamples > 0 {
            lines.append("─── RSSI ───")
            if let avg = metrics.rssiAverage {
                lines.append("Average: \(avg) dBm")
            }
            if let min = metrics.rssiMin, let max = metrics.rssiMax {
                lines.append("Range: \(min) to \(max) dBm")
            }
            lines.append("Samples: \(metrics.rssiSamples)")
            lines.append("")
        }
        
        if metrics.latencySamples > 0 {
            lines.append("─── LATENCY ───")
            if let avg = metrics.latencyAverageMs {
                lines.append("Average: \(avg) ms")
            }
            if let min = metrics.latencyMinMs, let max = metrics.latencyMaxMs {
                lines.append("Range: \(min) to \(max) ms")
            }
            lines.append("Samples: \(metrics.latencySamples)")
            lines.append("")
        }
        
        lines.append("─── RELIABILITY ───")
        lines.append("Total Retries: \(metrics.totalRetries)")
        lines.append("Max Consecutive: \(metrics.maxConsecutiveRetries)")
        lines.append("Packet Loss: \(String(format: "%.1f%%", metrics.packetLossRate * 100))")
        lines.append("")
        
        lines.append("─── THROUGHPUT ───")
        lines.append("Bytes: \(metrics.bytesTransferred)")
        lines.append("Packets: \(metrics.packetsReceived) received, \(metrics.packetsDropped) dropped")
        lines.append("Rate: \(String(format: "%.1f", metrics.throughputBytesPerSecond)) bytes/s")
        
        return lines.joined(separator: "\n")
    }
}
