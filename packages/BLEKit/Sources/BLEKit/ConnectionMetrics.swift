// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ConnectionMetrics.swift
// BLEKit
//
// BLE connection quality metrics tracking.
// Trace: BLE-DIAG-004
// Reference: Bluetooth Core Spec Vol 4 Part E (HCI) for RSSI ranges

import Foundation

// MARK: - RSSI Sample

/// A single RSSI measurement with timestamp
public struct RSSISample: Codable, Sendable, Equatable {
    /// RSSI value in dBm (typically -100 to -30)
    public let rssi: Int
    
    /// Timestamp of measurement
    public let timestamp: Date
    
    public init(rssi: Int, timestamp: Date = Date()) {
        self.rssi = rssi
        self.timestamp = timestamp
    }
}

// MARK: - Connection Event

/// A connection attempt result
public struct ConnectionEvent: Codable, Sendable, Equatable {
    /// Whether the connection succeeded
    public let success: Bool
    
    /// Timestamp of the attempt
    public let timestamp: Date
    
    /// Duration of connection attempt (if measured)
    public let durationMs: Int?
    
    /// Error description if failed
    public let errorReason: String?
    
    /// Device identifier
    public let deviceID: String
    
    public init(
        success: Bool,
        timestamp: Date = Date(),
        durationMs: Int? = nil,
        errorReason: String? = nil,
        deviceID: String
    ) {
        self.success = success
        self.timestamp = timestamp
        self.durationMs = durationMs
        self.errorReason = errorReason
        self.deviceID = deviceID
    }
}

// MARK: - Signal Quality

/// Interpreted signal quality from RSSI
public enum SignalQuality: String, Codable, Sendable {
    case excellent  // > -50 dBm
    case good       // -50 to -65 dBm
    case fair       // -65 to -80 dBm
    case weak       // -80 to -90 dBm
    case poor       // < -90 dBm
    case unknown
    
    /// Create from RSSI value
    public init(rssi: Int) {
        switch rssi {
        case (-49)...:
            self = .excellent
        case (-65)...(-50):
            self = .good
        case (-80)...(-66):
            self = .fair
        case (-90)...(-81):
            self = .weak
        case ...(-91):
            self = .poor
        default:
            self = .unknown
        }
    }
    
    /// Display name
    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .weak: return "Weak"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }
    
    /// Signal bars (0-4)
    public var bars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .weak: return 1
        case .poor, .unknown: return 0
        }
    }
}

// MARK: - Connection Metrics

/// Aggregated connection quality metrics for a device
public struct ConnectionMetrics: Codable, Sendable, Equatable {
    /// Device identifier
    public let deviceID: String
    
    /// Device type (if known)
    public var deviceType: String?
    
    /// RSSI sample history (most recent first)
    public private(set) var rssiHistory: [RSSISample]
    
    /// Connection event history (most recent first)
    public private(set) var connectionHistory: [ConnectionEvent]
    
    /// Maximum samples to retain
    public static let maxRSSISamples = 100
    public static let maxConnectionEvents = 50
    
    /// Timestamp of first metric recorded
    public let firstSeen: Date
    
    /// Timestamp of most recent activity
    public var lastSeen: Date
    
    public init(
        deviceID: String,
        deviceType: String? = nil,
        firstSeen: Date = Date()
    ) {
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.rssiHistory = []
        self.connectionHistory = []
        self.firstSeen = firstSeen
        self.lastSeen = firstSeen
    }
    
    // MARK: - RSSI Metrics
    
    /// Add an RSSI sample
    public mutating func recordRSSI(_ rssi: Int, at timestamp: Date = Date()) {
        let sample = RSSISample(rssi: rssi, timestamp: timestamp)
        rssiHistory.insert(sample, at: 0)
        
        // Trim to max size
        if rssiHistory.count > Self.maxRSSISamples {
            rssiHistory = Array(rssiHistory.prefix(Self.maxRSSISamples))
        }
        
        lastSeen = timestamp
    }
    
    /// Most recent RSSI value
    public var currentRSSI: Int? {
        rssiHistory.first?.rssi
    }
    
    /// Current signal quality
    public var signalQuality: SignalQuality {
        guard let rssi = currentRSSI else { return .unknown }
        return SignalQuality(rssi: rssi)
    }
    
    /// Average RSSI over the history
    public var averageRSSI: Double? {
        guard !rssiHistory.isEmpty else { return nil }
        let sum = rssiHistory.reduce(0) { $0 + $1.rssi }
        return Double(sum) / Double(rssiHistory.count)
    }
    
    /// RSSI standard deviation (variability indicator)
    public var rssiStandardDeviation: Double? {
        guard rssiHistory.count >= 2, let avg = averageRSSI else { return nil }
        let variance = rssiHistory.reduce(0.0) { sum, sample in
            let diff = Double(sample.rssi) - avg
            return sum + diff * diff
        } / Double(rssiHistory.count)
        return sqrt(variance)
    }
    
    /// Minimum RSSI in history
    public var minRSSI: Int? {
        rssiHistory.map(\.rssi).min()
    }
    
    /// Maximum RSSI in history
    public var maxRSSI: Int? {
        rssiHistory.map(\.rssi).max()
    }
    
    // MARK: - Connection Metrics
    
    /// Record a connection attempt
    public mutating func recordConnection(
        success: Bool,
        durationMs: Int? = nil,
        errorReason: String? = nil,
        at timestamp: Date = Date()
    ) {
        let event = ConnectionEvent(
            success: success,
            timestamp: timestamp,
            durationMs: durationMs,
            errorReason: errorReason,
            deviceID: deviceID
        )
        connectionHistory.insert(event, at: 0)
        
        // Trim to max size
        if connectionHistory.count > Self.maxConnectionEvents {
            connectionHistory = Array(connectionHistory.prefix(Self.maxConnectionEvents))
        }
        
        lastSeen = timestamp
    }
    
    /// Total connection attempts
    public var totalConnectionAttempts: Int {
        connectionHistory.count
    }
    
    /// Successful connections
    public var successfulConnections: Int {
        connectionHistory.filter(\.success).count
    }
    
    /// Failed connections
    public var failedConnections: Int {
        connectionHistory.filter { !$0.success }.count
    }
    
    /// Connection success rate (0.0 - 1.0)
    public var successRate: Double? {
        guard !connectionHistory.isEmpty else { return nil }
        return Double(successfulConnections) / Double(totalConnectionAttempts)
    }
    
    /// Average connection time in milliseconds
    public var averageConnectionTimeMs: Double? {
        let durations = connectionHistory.compactMap(\.durationMs)
        guard !durations.isEmpty else { return nil }
        return Double(durations.reduce(0, +)) / Double(durations.count)
    }
    
    /// Most common error reason
    public var mostCommonError: String? {
        let errors = connectionHistory.compactMap(\.errorReason)
        guard !errors.isEmpty else { return nil }
        
        var counts: [String: Int] = [:]
        for error in errors {
            counts[error, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - Summary
    
    /// Human-readable summary
    public var summary: String {
        var parts: [String] = []
        
        if let rssi = currentRSSI {
            parts.append("RSSI: \(rssi) dBm (\(signalQuality.displayName))")
        }
        
        if let rate = successRate {
            let percent = Int(rate * 100)
            parts.append("Success: \(percent)% (\(successfulConnections)/\(totalConnectionAttempts))")
        }
        
        if let avgTime = averageConnectionTimeMs {
            parts.append("Avg connect: \(Int(avgTime))ms")
        }
        
        return parts.isEmpty ? "No metrics" : parts.joined(separator: ", ")
    }
}

// MARK: - Metrics Collector

/// Actor for collecting metrics across multiple devices
public actor MetricsCollector {
    /// Metrics by device ID
    private var metrics: [String: ConnectionMetrics] = [:]
    
    public init() {}
    
    /// Get metrics for a device
    public func getMetrics(for deviceID: String) -> ConnectionMetrics? {
        metrics[deviceID]
    }
    
    /// Get all device IDs with metrics
    public func allDeviceIDs() -> [String] {
        Array(metrics.keys)
    }
    
    /// Record RSSI for a device
    public func recordRSSI(_ rssi: Int, for deviceID: String, deviceType: String? = nil) {
        if metrics[deviceID] == nil {
            metrics[deviceID] = ConnectionMetrics(deviceID: deviceID, deviceType: deviceType)
        }
        metrics[deviceID]?.recordRSSI(rssi)
    }
    
    /// Record connection attempt for a device
    public func recordConnection(
        success: Bool,
        for deviceID: String,
        durationMs: Int? = nil,
        errorReason: String? = nil,
        deviceType: String? = nil
    ) {
        if metrics[deviceID] == nil {
            metrics[deviceID] = ConnectionMetrics(deviceID: deviceID, deviceType: deviceType)
        }
        metrics[deviceID]?.recordConnection(
            success: success,
            durationMs: durationMs,
            errorReason: errorReason
        )
    }
    
    /// Get aggregate stats across all devices
    public func aggregateStats() -> AggregateConnectionStats {
        let allMetrics = Array(metrics.values)
        return AggregateConnectionStats(from: allMetrics)
    }
    
    /// Clear metrics for a device
    public func clearMetrics(for deviceID: String) {
        metrics.removeValue(forKey: deviceID)
    }
    
    /// Clear all metrics
    public func clearAllMetrics() {
        metrics.removeAll()
    }
    
    /// Export all metrics as JSON-encodable array
    public func exportMetrics() -> [ConnectionMetrics] {
        Array(metrics.values)
    }
}

// MARK: - Aggregate Stats

/// Aggregate statistics across all tracked devices
public struct AggregateConnectionStats: Codable, Sendable {
    /// Total devices tracked
    public let deviceCount: Int
    
    /// Overall connection success rate
    public let overallSuccessRate: Double?
    
    /// Total connection attempts
    public let totalAttempts: Int
    
    /// Total successful connections
    public let totalSuccesses: Int
    
    /// Average RSSI across all devices
    public let averageRSSI: Double?
    
    /// Device with best signal
    public let bestSignalDevice: String?
    
    /// Device with worst signal
    public let worstSignalDevice: String?
    
    public init(from metrics: [ConnectionMetrics]) {
        self.deviceCount = metrics.count
        
        let allConnections = metrics.flatMap(\.connectionHistory)
        self.totalAttempts = allConnections.count
        self.totalSuccesses = allConnections.filter(\.success).count
        
        if totalAttempts > 0 {
            self.overallSuccessRate = Double(totalSuccesses) / Double(totalAttempts)
        } else {
            self.overallSuccessRate = nil
        }
        
        let rssiValues = metrics.compactMap(\.currentRSSI)
        if !rssiValues.isEmpty {
            self.averageRSSI = Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)
        } else {
            self.averageRSSI = nil
        }
        
        let sorted = metrics.compactMap { m -> (String, Int)? in
            guard let rssi = m.currentRSSI else { return nil }
            return (m.deviceID, rssi)
        }.sorted { $0.1 > $1.1 }
        
        self.bestSignalDevice = sorted.first?.0
        self.worstSignalDevice = sorted.last?.0
    }
}
