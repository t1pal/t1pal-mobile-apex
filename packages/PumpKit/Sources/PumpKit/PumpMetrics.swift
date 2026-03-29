// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpMetrics.swift
// PumpKit
//
// Metrics instrumentation for pump operations.
// Records timing, success rates, and operational metrics for pump sources.
// Trace: PUMP-CTX-006, OBS-002
//
// Usage:
//   PumpMetrics.shared.recordCommand(.setTempBasal, duration: 0.15, success: true)
//   let stats = await PumpMetrics.shared.summary()

import Foundation

// MARK: - Pump Metric Types

/// Categories of pump metrics
public enum PumpMetricCategory: String, Codable, Sendable, CaseIterable {
    case command = "command"       // Individual commands (bolus, temp basal, etc)
    case connection = "connection" // Connect/disconnect events
    case status = "status"         // Status read operations
    case protocol_ = "protocol"    // Low-level protocol bytes
}

/// Individual pump metric types
public enum PumpMetricType: String, Codable, Sendable, CaseIterable {
    // Command metrics
    case commandDuration = "pump.command.duration"
    case commandSuccess = "pump.command.success"
    case commandFailure = "pump.command.failure"
    
    // Connection metrics
    case connectDuration = "pump.connect.duration"
    case disconnectCount = "pump.disconnect.count"
    case reconnectCount = "pump.reconnect.count"
    
    // Status metrics
    case statusReadDuration = "pump.status.duration"
    case statusReadSuccess = "pump.status.success"
    
    // Protocol metrics
    case packetsSent = "pump.protocol.tx"
    case packetsReceived = "pump.protocol.rx"
    case protocolErrors = "pump.protocol.errors"
    
    public var category: PumpMetricCategory {
        switch self {
        case .commandDuration, .commandSuccess, .commandFailure:
            return .command
        case .connectDuration, .disconnectCount, .reconnectCount:
            return .connection
        case .statusReadDuration, .statusReadSuccess:
            return .status
        case .packetsSent, .packetsReceived, .protocolErrors:
            return .protocol_
        }
    }
}

// MARK: - Pump Metric Data Point

/// Single metric data point
public struct PumpMetricDataPoint: Sendable, Codable {
    public let type: PumpMetricType
    public let timestamp: Date
    public let value: Double
    public let tags: [String: String]
    
    public init(type: PumpMetricType, value: Double, tags: [String: String] = [:]) {
        self.type = type
        self.timestamp = Date()
        self.value = value
        self.tags = tags
    }
}

// MARK: - Pump Metrics Summary

/// Summary statistics for pump metrics
public struct PumpMetricsSummary: Sendable {
    public let totalCommands: Int
    public let successfulCommands: Int
    public let failedCommands: Int
    public let avgCommandDuration: TimeInterval
    public let totalConnects: Int
    public let totalDisconnects: Int
    public let avgConnectDuration: TimeInterval
    public let packetsSent: Int
    public let packetsReceived: Int
    public let protocolErrors: Int
    public let successRate: Double
    
    public init(
        totalCommands: Int = 0,
        successfulCommands: Int = 0,
        failedCommands: Int = 0,
        avgCommandDuration: TimeInterval = 0,
        totalConnects: Int = 0,
        totalDisconnects: Int = 0,
        avgConnectDuration: TimeInterval = 0,
        packetsSent: Int = 0,
        packetsReceived: Int = 0,
        protocolErrors: Int = 0
    ) {
        self.totalCommands = totalCommands
        self.successfulCommands = successfulCommands
        self.failedCommands = failedCommands
        self.avgCommandDuration = avgCommandDuration
        self.totalConnects = totalConnects
        self.totalDisconnects = totalDisconnects
        self.avgConnectDuration = avgConnectDuration
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.protocolErrors = protocolErrors
        self.successRate = totalCommands > 0 ? Double(successfulCommands) / Double(totalCommands) : 0
    }
}

// MARK: - Pump Metrics Collector

/// Collects and stores pump metrics
/// Thread-safe implementation using actor
public actor PumpMetrics {
    
    // MARK: - Singleton
    
    public static let shared = PumpMetrics()
    
    // MARK: - State
    
    private var metrics: [PumpMetricDataPoint] = []
    private let maxCapacity: Int
    
    // Counters for fast summary
    private var commandSuccesses: Int = 0
    private var commandFailures: Int = 0
    private var commandDurations: [TimeInterval] = []
    private var connectCount: Int = 0
    private var disconnectCount: Int = 0
    private var connectDurations: [TimeInterval] = []
    private var txPackets: Int = 0
    private var rxPackets: Int = 0
    private var errors: Int = 0
    
    // MARK: - Thresholds
    
    /// Warning threshold for command duration (150ms)
    public static let commandDurationWarning: TimeInterval = 0.150
    
    /// Warning threshold for connect duration (2s)
    public static let connectDurationWarning: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    public init(maxCapacity: Int = 5000) {
        self.maxCapacity = maxCapacity
    }
    
    // MARK: - Recording Methods
    
    /// Record a pump command execution
    public func recordCommand(
        _ command: String,
        duration: TimeInterval,
        success: Bool,
        sourceType: PumpDataSourceType = .simulated,
        pumpType: PumpType = .simulation
    ) {
        let tags = [
            "command": command,
            "source": sourceType.rawValue,
            "pump": pumpType.rawValue
        ]
        
        // Record timing
        store(PumpMetricDataPoint(
            type: .commandDuration,
            value: duration,
            tags: tags
        ))
        commandDurations.append(duration)
        
        // Record success/failure
        if success {
            store(PumpMetricDataPoint(type: .commandSuccess, value: 1, tags: tags))
            commandSuccesses += 1
        } else {
            store(PumpMetricDataPoint(type: .commandFailure, value: 1, tags: tags))
            commandFailures += 1
        }
        
        // Check threshold
        checkThreshold(duration: duration, command: command)
    }
    
    /// Record a connection event
    public func recordConnect(duration: TimeInterval, sourceType: PumpDataSourceType = .simulated) {
        let tags = ["source": sourceType.rawValue]
        
        store(PumpMetricDataPoint(
            type: .connectDuration,
            value: duration,
            tags: tags
        ))
        connectCount += 1
        connectDurations.append(duration)
        
        if duration > Self.connectDurationWarning {
            PumpLogger.connection.warning("SLOW: pump.connect took \(String(format: "%.1f", duration * 1000))ms (threshold: \(String(format: "%.0f", Self.connectDurationWarning * 1000))ms)")
        }
    }
    
    /// Record a disconnect event
    public func recordDisconnect(sourceType: PumpDataSourceType = .simulated, reason: String = "") {
        let tags = [
            "source": sourceType.rawValue,
            "reason": reason
        ]
        
        store(PumpMetricDataPoint(type: .disconnectCount, value: 1, tags: tags))
        disconnectCount += 1
    }
    
    /// Record a status read operation
    public func recordStatusRead(duration: TimeInterval, success: Bool, sourceType: PumpDataSourceType = .simulated) {
        let tags = ["source": sourceType.rawValue]
        
        store(PumpMetricDataPoint(
            type: .statusReadDuration,
            value: duration,
            tags: tags
        ))
        
        if success {
            store(PumpMetricDataPoint(type: .statusReadSuccess, value: 1, tags: tags))
        }
    }
    
    /// Record protocol TX/RX
    public func recordProtocolTx(bytes: Int, context: String = "") {
        store(PumpMetricDataPoint(
            type: .packetsSent,
            value: Double(bytes),
            tags: ["context": context]
        ))
        txPackets += bytes
    }
    
    public func recordProtocolRx(bytes: Int, context: String = "") {
        store(PumpMetricDataPoint(
            type: .packetsReceived,
            value: Double(bytes),
            tags: ["context": context]
        ))
        rxPackets += bytes
    }
    
    public func recordProtocolError(message: String) {
        store(PumpMetricDataPoint(
            type: .protocolErrors,
            value: 1,
            tags: ["message": message]
        ))
        errors += 1
    }
    
    // MARK: - Query Methods
    
    /// Get summary statistics
    public func summary() -> PumpMetricsSummary {
        let avgCommandDuration = commandDurations.isEmpty ? 0 : commandDurations.reduce(0, +) / Double(commandDurations.count)
        let avgConnectDuration = connectDurations.isEmpty ? 0 : connectDurations.reduce(0, +) / Double(connectDurations.count)
        
        return PumpMetricsSummary(
            totalCommands: commandSuccesses + commandFailures,
            successfulCommands: commandSuccesses,
            failedCommands: commandFailures,
            avgCommandDuration: avgCommandDuration,
            totalConnects: connectCount,
            totalDisconnects: disconnectCount,
            avgConnectDuration: avgConnectDuration,
            packetsSent: txPackets,
            packetsReceived: rxPackets,
            protocolErrors: errors
        )
    }
    
    /// Get all metrics
    public func allMetrics() -> [PumpMetricDataPoint] {
        metrics
    }
    
    /// Get metrics by type
    public func metrics(ofType type: PumpMetricType) -> [PumpMetricDataPoint] {
        metrics.filter { $0.type == type }
    }
    
    /// Get metrics within time range
    public func metrics(from startDate: Date, to endDate: Date) -> [PumpMetricDataPoint] {
        metrics.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
    }
    
    /// Clear all metrics
    public func clear() {
        metrics.removeAll()
        commandSuccesses = 0
        commandFailures = 0
        commandDurations.removeAll()
        connectCount = 0
        disconnectCount = 0
        connectDurations.removeAll()
        txPackets = 0
        rxPackets = 0
        errors = 0
    }
    
    // MARK: - Private Methods
    
    private func store(_ point: PumpMetricDataPoint) {
        metrics.append(point)
        
        // Trim if over capacity
        if metrics.count > maxCapacity {
            metrics.removeFirst(metrics.count - maxCapacity)
        }
        
        #if DEBUG
        switch point.type {
        case .commandDuration:
            PumpLogger.protocol_.debug("command duration: \(String(format: "%.1f", point.value * 1000))ms \(point.tags)")
        case .protocolErrors:
            PumpLogger.protocol_.warning("protocol error: \(point.tags["message"] ?? "")")
        default:
            break
        }
        #endif
    }
    
    private func checkThreshold(duration: TimeInterval, command: String) {
        if duration > Self.commandDurationWarning {
            PumpLogger.protocol_.warning("SLOW: pump.command.\(command) took \(String(format: "%.1f", duration * 1000))ms (threshold: \(String(format: "%.0f", Self.commandDurationWarning * 1000))ms)")
        }
    }
}

// MARK: - Convenience Extensions

extension PumpSourceCommand {
    /// Metric-friendly command name
    public var metricName: String {
        switch self {
        case .setTempBasal: return "setTempBasal"
        case .cancelTempBasal: return "cancelTempBasal"
        case .deliverBolus: return "deliverBolus"
        case .suspend: return "suspend"
        case .resume: return "resume"
        case .readStatus: return "readStatus"
        }
    }
}
