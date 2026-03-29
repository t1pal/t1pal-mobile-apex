// SPDX-License-Identifier: AGPL-3.0-or-later
// T1PalCore - FaultTypes
// Fault injection types for testing error handling
// Trace: PRD-025 REQ-FAULT-002, REQ-FAULT-003, OBS-003, OBS-004

import Foundation

// MARK: - Data Fault Types (REQ-FAULT-002)

/// Fault types for data layer testing
/// Used to simulate various data quality issues for error handling validation
public enum DataFaultType: Sendable, Codable, Equatable, Hashable {
    /// No new readings for specified duration
    case staleData(gapMinutes: Int)
    
    /// Insert gap in glucose history
    case dataGap(startMinutesAgo: Int, durationMinutes: Int)
    
    /// Return invalid glucose value (e.g., -1, 999, NaN)
    case invalidValue(value: Double)
    
    /// Duplicate readings (same timestamp)
    case duplicateReadings(count: Int)
    
    /// Out-of-order readings
    case outOfOrderReadings
    
    /// Future-dated readings
    case futureReadings(minutesAhead: Int)
    
    /// Missing trend arrow
    case missingTrend
    
    /// Conflicting sources (HK vs BLE mismatch)
    case conflictingSource(deltaMilligrams: Int)
}

extension DataFaultType {
    /// Human-readable description of the fault
    public var description: String {
        switch self {
        case .staleData(let minutes):
            return "Stale data (\(minutes) min gap)"
        case .dataGap(let start, let duration):
            return "Data gap (\(duration) min starting \(start) min ago)"
        case .invalidValue(let value):
            return "Invalid value (\(value))"
        case .duplicateReadings(let count):
            return "Duplicate readings (\(count)x)"
        case .outOfOrderReadings:
            return "Out-of-order readings"
        case .futureReadings(let minutes):
            return "Future readings (\(minutes) min ahead)"
        case .missingTrend:
            return "Missing trend arrow"
        case .conflictingSource(let delta):
            return "Conflicting source (Δ\(delta) mg/dL)"
        }
    }
    
    /// Severity level for UI display
    public var severity: FaultSeverity {
        switch self {
        case .staleData, .dataGap:
            return .warning
        case .invalidValue, .outOfOrderReadings, .futureReadings:
            return .error
        case .duplicateReadings, .missingTrend:
            return .info
        case .conflictingSource:
            return .warning
        }
    }
}

// MARK: - Network Fault Types (REQ-FAULT-003)

/// Fault types for network layer testing
/// Used to simulate various network issues for error handling validation
public enum NetworkFaultType: Sendable, Codable, Equatable, Hashable {
    /// Nightscout API timeout
    case timeout(afterSeconds: Double)
    
    /// Nightscout rate limiting (429)
    case rateLimited(retryAfterSeconds: Int)
    
    /// Server error (5xx)
    case serverError(statusCode: Int)
    
    /// DNS resolution failure
    case dnsFailure
    
    /// Connection refused
    case connectionRefused
    
    /// SSL/TLS certificate error
    case certificateError
    
    /// Malformed response (invalid JSON)
    case malformedResponse
    
    /// Partial response (truncated)
    case partialResponse(percentComplete: Int)
}

extension NetworkFaultType {
    /// Human-readable description of the fault
    public var description: String {
        switch self {
        case .timeout(let seconds):
            return "Timeout after \(String(format: "%.1f", seconds))s"
        case .rateLimited(let retry):
            return "Rate limited (retry in \(retry)s)"
        case .serverError(let code):
            return "Server error (\(code))"
        case .dnsFailure:
            return "DNS resolution failed"
        case .connectionRefused:
            return "Connection refused"
        case .certificateError:
            return "Certificate error"
        case .malformedResponse:
            return "Malformed response"
        case .partialResponse(let percent):
            return "Partial response (\(percent)%)"
        }
    }
    
    /// Severity level for UI display
    public var severity: FaultSeverity {
        switch self {
        case .timeout, .rateLimited:
            return .warning
        case .serverError, .dnsFailure, .connectionRefused, .certificateError:
            return .error
        case .malformedResponse, .partialResponse:
            return .error
        }
    }
}

// MARK: - Fault Severity

/// Severity levels for fault display
public enum FaultSeverity: String, Sendable, Codable {
    case info
    case warning
    case error
    
    /// SF Symbol name for severity
    public var iconName: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}

// MARK: - Fault Configuration

/// Configuration for active faults
public struct FaultConfiguration: Sendable, Codable, Equatable, Hashable {
    /// Active data faults
    public var dataFaults: [DataFaultType]
    
    /// Active network faults
    public var networkFaults: [NetworkFaultType]
    
    /// Whether fault injection is enabled
    public var isEnabled: Bool
    
    public init(
        dataFaults: [DataFaultType] = [],
        networkFaults: [NetworkFaultType] = [],
        isEnabled: Bool = false
    ) {
        self.dataFaults = dataFaults
        self.networkFaults = networkFaults
        self.isEnabled = isEnabled
    }
    
    /// Empty configuration (no faults)
    public static let none = FaultConfiguration()
    
    /// Check if any faults are configured
    public var hasFaults: Bool {
        !dataFaults.isEmpty || !networkFaults.isEmpty
    }
}

// MARK: - Preset Fault Scenarios

/// Common fault scenarios for quick testing
public enum FaultPreset: String, CaseIterable, Sendable {
    // Data fault presets
    case staleG6 = "Stale G6 (15 min)"
    case sensorWarmup = "Sensor Warmup"
    case signalLoss = "Signal Loss"
    case badData = "Bad Data Quality"
    case compressionLow = "Compression Low"
    
    // Network fault presets
    case networkFlaky = "Flaky Network"
    case serverDown = "Server Down"
    case networkOutage = "Network Outage"
    case slowConnection = "Slow Connection"
    case authExpired = "Auth Expired"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .staleG6: return "Simulates 15-minute data gap from Dexcom G6"
        case .sensorWarmup: return "First 2 hours of sensor session with gaps"
        case .signalLoss: return "CGM transmitter out of range"
        case .badData: return "Invalid readings and duplicate data"
        case .compressionLow: return "Compression artifact readings"
        case .networkFlaky: return "Intermittent timeouts and rate limits"
        case .serverDown: return "503 Service Unavailable from server"
        case .networkOutage: return "Complete network failure"
        case .slowConnection: return "High latency responses"
        case .authExpired: return "Authentication token expired"
        }
    }
    
    /// Category for grouping in UI
    public var category: FaultPresetCategory {
        switch self {
        case .staleG6, .sensorWarmup, .signalLoss, .badData, .compressionLow:
            return .data
        case .networkFlaky, .serverDown, .networkOutage, .slowConnection, .authExpired:
            return .network
        }
    }
    
    /// SF Symbol for preset
    public var systemImage: String {
        switch self {
        case .staleG6: return "clock.badge.exclamationmark"
        case .sensorWarmup: return "thermometer.medium"
        case .signalLoss: return "antenna.radiowaves.left.and.right.slash"
        case .badData: return "exclamationmark.triangle"
        case .compressionLow: return "arrow.down.right"
        case .networkFlaky: return "wifi.exclamationmark"
        case .serverDown: return "server.rack"
        case .networkOutage: return "network.slash"
        case .slowConnection: return "tortoise"
        case .authExpired: return "key.slash"
        }
    }
    
    /// Get fault configuration for preset
    public var configuration: FaultConfiguration {
        switch self {
        case .staleG6:
            return FaultConfiguration(
                dataFaults: [.staleData(gapMinutes: 15)],
                isEnabled: true
            )
        case .sensorWarmup:
            return FaultConfiguration(
                dataFaults: [.dataGap(startMinutesAgo: 120, durationMinutes: 90), .staleData(gapMinutes: 30)],
                isEnabled: true
            )
        case .signalLoss:
            return FaultConfiguration(
                dataFaults: [.staleData(gapMinutes: 60), .missingTrend],
                isEnabled: true
            )
        case .badData:
            return FaultConfiguration(
                dataFaults: [.invalidValue(value: -1), .duplicateReadings(count: 3), .missingTrend],
                isEnabled: true
            )
        case .compressionLow:
            return FaultConfiguration(
                dataFaults: [.invalidValue(value: 40), .outOfOrderReadings],
                isEnabled: true
            )
        case .networkFlaky:
            return FaultConfiguration(
                networkFaults: [.timeout(afterSeconds: 5), .rateLimited(retryAfterSeconds: 30)],
                isEnabled: true
            )
        case .serverDown:
            return FaultConfiguration(
                networkFaults: [.serverError(statusCode: 503)],
                isEnabled: true
            )
        case .networkOutage:
            return FaultConfiguration(
                networkFaults: [.connectionRefused, .dnsFailure],
                isEnabled: true
            )
        case .slowConnection:
            return FaultConfiguration(
                networkFaults: [.timeout(afterSeconds: 30), .partialResponse(percentComplete: 80)],
                isEnabled: true
            )
        case .authExpired:
            return FaultConfiguration(
                networkFaults: [.serverError(statusCode: 401)],
                isEnabled: true
            )
        }
    }
}

/// Category for grouping fault presets
public enum FaultPresetCategory: String, CaseIterable, Sendable {
    case data = "Data Faults"
    case network = "Network Faults"
    
    public var systemImage: String {
        switch self {
        case .data: return "waveform.path.ecg"
        case .network: return "network"
        }
    }
}
