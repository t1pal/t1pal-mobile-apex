// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// FailureClassifier.swift - Failure mode classification for diagnostics
// Part of BLEKit
// Trace: EVID-005

import Foundation

// MARK: - Failure Mode

/// Detailed failure modes for BLE and protocol operations
public enum FailureMode: String, CaseIterable, Sendable, Codable {
    // Connection failures
    case connectionTimeout
    case connectionRefused
    case connectionDropped
    case deviceNotFound
    case deviceNotReachable
    case bluetoothDisabled
    case bluetoothUnauthorized
    
    // Authentication failures
    case authenticationFailed
    case authenticationTimeout
    case invalidCredentials
    case encryptionFailed
    case pairingFailed
    case bondingFailed
    
    // Protocol failures
    case protocolMismatch
    case invalidResponse
    case unexpectedMessage
    case checksumError
    case parsingError
    case sequenceError
    
    // Communication failures
    case writeTimeout
    case readTimeout
    case notifyTimeout
    case characteristicNotFound
    case serviceNotFound
    case mtuNegotiationFailed
    
    // Device-specific failures
    case sensorExpired
    case sensorWarmup
    case deviceBusy
    case batteryLow
    case firmwareError
    
    // Resource failures
    case resourceExhausted
    case memoryError
    case queueFull
    
    // Unknown
    case unknown
    
    /// Category this failure belongs to
    public var category: ErrorCategory {
        switch self {
        case .connectionTimeout, .connectionRefused, .connectionDropped,
             .deviceNotFound, .deviceNotReachable, .bluetoothDisabled, .bluetoothUnauthorized:
            return .connection
            
        case .authenticationFailed, .authenticationTimeout, .invalidCredentials,
             .encryptionFailed, .pairingFailed, .bondingFailed:
            return .authentication
            
        case .protocolMismatch, .invalidResponse, .unexpectedMessage,
             .checksumError, .parsingError, .sequenceError:
            return .protocol_
            
        case .writeTimeout, .readTimeout, .notifyTimeout:
            return .timeout
            
        case .characteristicNotFound, .serviceNotFound, .mtuNegotiationFailed,
             .sensorExpired, .sensorWarmup, .deviceBusy, .batteryLow, .firmwareError,
             .resourceExhausted, .memoryError, .queueFull, .unknown:
            return .unknown
        }
    }
    
    /// Human-readable description
    public var displayName: String {
        switch self {
        case .connectionTimeout: return "Connection Timeout"
        case .connectionRefused: return "Connection Refused"
        case .connectionDropped: return "Connection Dropped"
        case .deviceNotFound: return "Device Not Found"
        case .deviceNotReachable: return "Device Not Reachable"
        case .bluetoothDisabled: return "Bluetooth Disabled"
        case .bluetoothUnauthorized: return "Bluetooth Unauthorized"
        case .authenticationFailed: return "Authentication Failed"
        case .authenticationTimeout: return "Authentication Timeout"
        case .invalidCredentials: return "Invalid Credentials"
        case .encryptionFailed: return "Encryption Failed"
        case .pairingFailed: return "Pairing Failed"
        case .bondingFailed: return "Bonding Failed"
        case .protocolMismatch: return "Protocol Mismatch"
        case .invalidResponse: return "Invalid Response"
        case .unexpectedMessage: return "Unexpected Message"
        case .checksumError: return "Checksum Error"
        case .parsingError: return "Parsing Error"
        case .sequenceError: return "Sequence Error"
        case .writeTimeout: return "Write Timeout"
        case .readTimeout: return "Read Timeout"
        case .notifyTimeout: return "Notify Timeout"
        case .characteristicNotFound: return "Characteristic Not Found"
        case .serviceNotFound: return "Service Not Found"
        case .mtuNegotiationFailed: return "MTU Negotiation Failed"
        case .sensorExpired: return "Sensor Expired"
        case .sensorWarmup: return "Sensor Warmup"
        case .deviceBusy: return "Device Busy"
        case .batteryLow: return "Battery Low"
        case .firmwareError: return "Firmware Error"
        case .resourceExhausted: return "Resource Exhausted"
        case .memoryError: return "Memory Error"
        case .queueFull: return "Queue Full"
        case .unknown: return "Unknown"
        }
    }
    
    /// Suggested remediation action
    public var remediation: String {
        switch self {
        case .connectionTimeout, .connectionRefused:
            return "Move closer to device and retry"
        case .connectionDropped:
            return "Check for interference and reconnect"
        case .deviceNotFound:
            return "Ensure device is powered on and in range"
        case .deviceNotReachable:
            return "Check device status and Bluetooth settings"
        case .bluetoothDisabled:
            return "Enable Bluetooth in Settings"
        case .bluetoothUnauthorized:
            return "Grant Bluetooth permission in Settings"
        case .authenticationFailed, .invalidCredentials:
            return "Verify pairing code and retry"
        case .authenticationTimeout:
            return "Retry authentication"
        case .encryptionFailed, .pairingFailed, .bondingFailed:
            return "Remove pairing and re-pair device"
        case .protocolMismatch:
            return "Check device firmware version"
        case .invalidResponse, .unexpectedMessage, .checksumError, .parsingError, .sequenceError:
            return "Restart device and retry"
        case .writeTimeout, .readTimeout, .notifyTimeout:
            return "Check connection stability and retry"
        case .characteristicNotFound, .serviceNotFound:
            return "Ensure device supports this feature"
        case .mtuNegotiationFailed:
            return "Reconnect to device"
        case .sensorExpired:
            return "Replace sensor"
        case .sensorWarmup:
            return "Wait for sensor warmup to complete"
        case .deviceBusy:
            return "Wait and retry"
        case .batteryLow:
            return "Charge or replace battery"
        case .firmwareError:
            return "Update device firmware"
        case .resourceExhausted, .memoryError, .queueFull:
            return "Restart app and retry"
        case .unknown:
            return "Check logs and contact support"
        }
    }
    
    /// Severity level (1-5, 5 being most severe)
    public var severity: Int {
        switch self {
        case .sensorWarmup, .deviceBusy:
            return 1  // Transient, will resolve
        case .writeTimeout, .readTimeout, .notifyTimeout, .connectionTimeout:
            return 2  // Retryable
        case .connectionRefused, .connectionDropped, .mtuNegotiationFailed:
            return 3  // Needs reconnection
        case .authenticationFailed, .invalidCredentials, .encryptionFailed,
             .protocolMismatch, .invalidResponse:
            return 4  // Configuration issue
        case .bluetoothDisabled, .bluetoothUnauthorized, .sensorExpired,
             .deviceNotFound, .firmwareError:
            return 5  // User action required
        default:
            return 3
        }
    }
}

// MARK: - Classified Failure

/// A failure with classification metadata
public struct ClassifiedFailure: Sendable, Codable, Equatable {
    /// The failure mode
    public let mode: FailureMode
    
    /// When the failure occurred
    public let timestamp: Date
    
    /// Original error message (if available)
    public let message: String?
    
    /// Error code (if available)
    public let code: Int?
    
    /// Context information
    public let context: [String: String]
    
    /// Confidence of classification (0.0-1.0)
    public let confidence: Double
    
    public init(
        mode: FailureMode,
        timestamp: Date = Date(),
        message: String? = nil,
        code: Int? = nil,
        context: [String: String] = [:],
        confidence: Double = 1.0
    ) {
        self.mode = mode
        self.timestamp = timestamp
        self.message = message
        self.code = code
        self.context = context
        self.confidence = min(1.0, max(0.0, confidence))
    }
}

// MARK: - Failure Pattern

/// Pattern for matching failures from error messages
public struct FailurePattern: Sendable {
    /// Pattern name
    public let name: String
    
    /// Regular expression pattern
    public let pattern: String
    
    /// Failure mode to assign when matched
    public let mode: FailureMode
    
    /// Base confidence for this pattern
    public let confidence: Double
    
    public init(name: String, pattern: String, mode: FailureMode, confidence: Double = 0.9) {
        self.name = name
        self.pattern = pattern
        self.mode = mode
        self.confidence = confidence
    }
}

// MARK: - Classification Result

/// Result of classifying failures in a report
public struct ClassificationResult: Sendable, Codable, Equatable {
    /// Total failures classified
    public let totalClassified: Int
    
    /// Failures by mode
    public let modeBreakdown: [String: Int]
    
    /// Failures by category
    public let categoryBreakdown: [String: Int]
    
    /// Failures by severity
    public let severityBreakdown: [Int: Int]
    
    /// Most common failure mode
    public let mostCommonMode: FailureMode?
    
    /// Most common remediation
    public let topRemediation: String?
    
    /// Average severity
    public let averageSeverity: Double
    
    /// Classified failures
    public let failures: [ClassifiedFailure]
    
    public init(
        totalClassified: Int,
        modeBreakdown: [String: Int],
        categoryBreakdown: [String: Int],
        severityBreakdown: [Int: Int],
        mostCommonMode: FailureMode?,
        topRemediation: String?,
        averageSeverity: Double,
        failures: [ClassifiedFailure]
    ) {
        self.totalClassified = totalClassified
        self.modeBreakdown = modeBreakdown
        self.categoryBreakdown = categoryBreakdown
        self.severityBreakdown = severityBreakdown
        self.mostCommonMode = mostCommonMode
        self.topRemediation = topRemediation
        self.averageSeverity = averageSeverity
        self.failures = failures
    }
    
    /// Empty result
    public static let empty = ClassificationResult(
        totalClassified: 0,
        modeBreakdown: [:],
        categoryBreakdown: [:],
        severityBreakdown: [:],
        mostCommonMode: nil,
        topRemediation: nil,
        averageSeverity: 0,
        failures: []
    )
}

// MARK: - Failure Classifier

/// Classifies failures from error messages and reports
///
/// Trace: EVID-005
///
/// Provides pattern-based classification of failure modes from error
/// messages, log entries, and diagnostic reports. Supports both built-in
/// patterns and custom pattern registration.
public struct FailureClassifier: Sendable {
    
    // MARK: - Properties
    
    private let patterns: [FailurePattern]
    private let compiledPatterns: [(NSRegularExpression, FailurePattern)]
    
    // MARK: - Built-in Patterns
    
    /// Default patterns for common BLE/protocol errors
    public static let defaultPatterns: [FailurePattern] = [
        // Specific timeout patterns first (before generic timeout)
        FailurePattern(name: "write_timeout", pattern: "(?i)write\\s*timeout", mode: .writeTimeout),
        FailurePattern(name: "read_timeout", pattern: "(?i)read\\s*timeout", mode: .readTimeout),
        FailurePattern(name: "notify_timeout", pattern: "(?i)notif(y|ication)\\s*timeout", mode: .notifyTimeout),
        FailurePattern(name: "auth_timeout", pattern: "(?i)auth(entication)?\\s*timeout", mode: .authenticationTimeout),
        
        // Connection patterns
        FailurePattern(name: "timeout", pattern: "(?i)timeout|timed\\s*out", mode: .connectionTimeout),
        FailurePattern(name: "refused", pattern: "(?i)connection\\s*refused|refused", mode: .connectionRefused),
        FailurePattern(name: "dropped", pattern: "(?i)connection\\s*(dropped|lost)|disconnected", mode: .connectionDropped),
        FailurePattern(name: "not_found", pattern: "(?i)device\\s*not\\s*found|no\\s*device", mode: .deviceNotFound),
        FailurePattern(name: "unreachable", pattern: "(?i)unreachable|not\\s*reachable", mode: .deviceNotReachable),
        FailurePattern(name: "bt_off", pattern: "(?i)bluetooth\\s*(is\\s*)?(off|disabled)", mode: .bluetoothDisabled),
        FailurePattern(name: "bt_unauth", pattern: "(?i)bluetooth\\s*(not\\s*)?authorized|permission\\s*denied", mode: .bluetoothUnauthorized),
        
        // Authentication patterns
        FailurePattern(name: "auth_fail", pattern: "(?i)auth(entication)?\\s*fail(ed)?", mode: .authenticationFailed),
        FailurePattern(name: "invalid_cred", pattern: "(?i)invalid\\s*(credentials?|password|code)", mode: .invalidCredentials),
        FailurePattern(name: "encrypt_fail", pattern: "(?i)encrypt(ion)?\\s*fail(ed)?", mode: .encryptionFailed),
        FailurePattern(name: "pair_fail", pattern: "(?i)pair(ing)?\\s*fail(ed)?", mode: .pairingFailed),
        FailurePattern(name: "bond_fail", pattern: "(?i)bond(ing)?\\s*fail(ed)?", mode: .bondingFailed),
        
        // Protocol patterns
        FailurePattern(name: "protocol_mismatch", pattern: "(?i)protocol\\s*mismatch|unsupported\\s*protocol", mode: .protocolMismatch),
        FailurePattern(name: "invalid_response", pattern: "(?i)invalid\\s*response|bad\\s*response", mode: .invalidResponse),
        FailurePattern(name: "unexpected_msg", pattern: "(?i)unexpected\\s*(message|packet|data)", mode: .unexpectedMessage),
        FailurePattern(name: "checksum", pattern: "(?i)checksum\\s*(error|mismatch|invalid)|crc\\s*error", mode: .checksumError),
        FailurePattern(name: "parse_error", pattern: "(?i)pars(e|ing)\\s*error|failed\\s*to\\s*parse", mode: .parsingError),
        FailurePattern(name: "sequence", pattern: "(?i)sequence\\s*error|out\\s*of\\s*order", mode: .sequenceError),
        
        // Discovery patterns
        FailurePattern(name: "char_not_found", pattern: "(?i)characteristic\\s*not\\s*found", mode: .characteristicNotFound),
        FailurePattern(name: "service_not_found", pattern: "(?i)service\\s*not\\s*found", mode: .serviceNotFound),
        FailurePattern(name: "mtu_fail", pattern: "(?i)mtu\\s*(negotiation)?\\s*fail(ed)?", mode: .mtuNegotiationFailed),
        
        // Device-specific patterns
        FailurePattern(name: "sensor_expired", pattern: "(?i)sensor\\s*expired|session\\s*ended", mode: .sensorExpired),
        FailurePattern(name: "warmup", pattern: "(?i)warm(ing)?\\s*up|sensor\\s*warmup", mode: .sensorWarmup),
        FailurePattern(name: "busy", pattern: "(?i)device\\s*busy|resource\\s*busy", mode: .deviceBusy),
        FailurePattern(name: "battery", pattern: "(?i)battery\\s*(low|critical)", mode: .batteryLow),
        FailurePattern(name: "firmware", pattern: "(?i)firmware\\s*(error|fault)", mode: .firmwareError),
        
        // Resource patterns
        FailurePattern(name: "exhausted", pattern: "(?i)resource\\s*exhausted|out\\s*of\\s*resources", mode: .resourceExhausted),
        FailurePattern(name: "memory", pattern: "(?i)memory\\s*(error|exhausted)|out\\s*of\\s*memory", mode: .memoryError),
        FailurePattern(name: "queue_full", pattern: "(?i)queue\\s*(is\\s*)?full", mode: .queueFull)
    ]
    
    // MARK: - Initialization
    
    public init(patterns: [FailurePattern] = FailureClassifier.defaultPatterns) {
        self.patterns = patterns
        self.compiledPatterns = patterns.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: []) else {
                return nil
            }
            return (regex, pattern)
        }
    }
    
    /// Create classifier with custom patterns added to defaults
    public static func withAdditionalPatterns(_ additional: [FailurePattern]) -> FailureClassifier {
        FailureClassifier(patterns: defaultPatterns + additional)
    }
    
    // MARK: - Classification
    
    /// Classify a single error message
    public func classify(_ message: String, timestamp: Date = Date()) -> ClassifiedFailure {
        let range = NSRange(message.startIndex..., in: message)
        
        for (regex, pattern) in compiledPatterns {
            if regex.firstMatch(in: message, range: range) != nil {
                return ClassifiedFailure(
                    mode: pattern.mode,
                    timestamp: timestamp,
                    message: message,
                    confidence: pattern.confidence
                )
            }
        }
        
        return ClassifiedFailure(
            mode: .unknown,
            timestamp: timestamp,
            message: message,
            confidence: 0.5
        )
    }
    
    /// Classify from an error code (common BLE error codes)
    public func classifyCode(_ code: Int, timestamp: Date = Date()) -> ClassifiedFailure {
        let mode: FailureMode
        let confidence: Double
        
        switch code {
        // CoreBluetooth error codes
        case 0: // Unknown
            mode = .unknown
            confidence = 0.5
        case 1: // Invalid parameters
            mode = .protocolMismatch
            confidence = 0.8
        case 2: // Invalid handle
            mode = .characteristicNotFound
            confidence = 0.8
        case 3: // Not connected
            mode = .connectionDropped
            confidence = 0.9
        case 4: // Out of space
            mode = .resourceExhausted
            confidence = 0.9
        case 5: // Operation cancelled
            mode = .connectionDropped
            confidence = 0.7
        case 6: // Connection timeout
            mode = .connectionTimeout
            confidence = 0.95
        case 7: // Peripheral disconnected
            mode = .connectionDropped
            confidence = 0.95
        case 8: // UUID not allowed
            mode = .bluetoothUnauthorized
            confidence = 0.8
        case 9: // Already advertising
            mode = .deviceBusy
            confidence = 0.8
        case 10: // Connection failed
            mode = .connectionRefused
            confidence = 0.9
        case 11: // Connection limit reached
            mode = .resourceExhausted
            confidence = 0.9
        case 12: // Unknown device
            mode = .deviceNotFound
            confidence = 0.9
        case 13: // Operation not supported
            mode = .protocolMismatch
            confidence = 0.8
        case 14: // Peer removed pairing
            mode = .pairingFailed
            confidence = 0.9
        case 15: // Encryption timed out
            mode = .authenticationTimeout
            confidence = 0.9
        default:
            mode = .unknown
            confidence = 0.3
        }
        
        return ClassifiedFailure(
            mode: mode,
            timestamp: timestamp,
            code: code,
            confidence: confidence
        )
    }
    
    /// Classify multiple error messages
    public func classifyAll(_ messages: [String]) -> ClassificationResult {
        let failures = messages.map { classify($0) }
        return buildResult(from: failures)
    }
    
    /// Classify failures from an aggregate report
    public func classifyReport(_ report: AggregateReport) -> ClassificationResult {
        // Extract error info from the report's error breakdown
        var failures: [ClassifiedFailure] = []
        
        for (category, count) in report.errorBreakdown.categoryCounts {
            let mode = modeFromCategory(category)
            for _ in 0..<count {
                failures.append(ClassifiedFailure(
                    mode: mode,
                    confidence: 0.7  // Lower confidence when derived from category
                ))
            }
        }
        
        return buildResult(from: failures)
    }
    
    /// Map category string back to a failure mode
    private func modeFromCategory(_ category: String) -> FailureMode {
        switch category.lowercased() {
        case "connection": return .connectionDropped
        case "authentication": return .authenticationFailed
        case "protocol", "protocol_": return .protocolMismatch
        case "timeout": return .connectionTimeout
        default: return .unknown
        }
    }
    
    /// Build classification result from failures
    private func buildResult(from failures: [ClassifiedFailure]) -> ClassificationResult {
        guard !failures.isEmpty else {
            return .empty
        }
        
        var modeBreakdown: [String: Int] = [:]
        var categoryBreakdown: [String: Int] = [:]
        var severityBreakdown: [Int: Int] = [:]
        var totalSeverity = 0
        
        for failure in failures {
            modeBreakdown[failure.mode.rawValue, default: 0] += 1
            categoryBreakdown[failure.mode.category.rawValue, default: 0] += 1
            severityBreakdown[failure.mode.severity, default: 0] += 1
            totalSeverity += failure.mode.severity
        }
        
        let mostCommonModeStr = modeBreakdown.max(by: { $0.value < $1.value })?.key
        let mostCommonMode = mostCommonModeStr.flatMap { FailureMode(rawValue: $0) }
        
        return ClassificationResult(
            totalClassified: failures.count,
            modeBreakdown: modeBreakdown,
            categoryBreakdown: categoryBreakdown,
            severityBreakdown: severityBreakdown,
            mostCommonMode: mostCommonMode,
            topRemediation: mostCommonMode?.remediation,
            averageSeverity: Double(totalSeverity) / Double(failures.count),
            failures: failures
        )
    }
    
    // MARK: - Analysis
    
    /// Analyze failure trends across time periods
    public func analyzeTrends(_ failures: [ClassifiedFailure]) -> FailureTrendAnalysis {
        guard !failures.isEmpty else {
            return FailureTrendAnalysis.empty
        }
        
        let sortedFailures = failures.sorted { $0.timestamp < $1.timestamp }
        let firstDate = sortedFailures.first!.timestamp
        let lastDate = sortedFailures.last!.timestamp
        
        // Group by hour
        var hourlyBreakdown: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH"
        
        for failure in sortedFailures {
            let hourKey = formatter.string(from: failure.timestamp)
            hourlyBreakdown[hourKey, default: 0] += 1
        }
        
        // Identify peak hour
        let peakHour = hourlyBreakdown.max(by: { $0.value < $1.value })
        
        // Calculate rate
        let duration = lastDate.timeIntervalSince(firstDate)
        let failuresPerHour = duration > 0 ? Double(failures.count) / (duration / 3600) : Double(failures.count)
        
        return FailureTrendAnalysis(
            totalFailures: failures.count,
            periodStart: firstDate,
            periodEnd: lastDate,
            failuresPerHour: failuresPerHour,
            hourlyBreakdown: hourlyBreakdown,
            peakHour: peakHour?.key,
            peakHourCount: peakHour?.value ?? 0
        )
    }
    
    /// Identify correlated failures (failures that occur together)
    public func findCorrelations(_ failures: [ClassifiedFailure], windowSeconds: TimeInterval = 60) -> [FailureCorrelation] {
        guard failures.count >= 2 else {
            return []
        }
        
        var correlations: [String: FailureCorrelation] = [:]
        let sortedFailures = failures.sorted { $0.timestamp < $1.timestamp }
        
        for i in 0..<sortedFailures.count {
            for j in (i+1)..<sortedFailures.count {
                let f1 = sortedFailures[i]
                let f2 = sortedFailures[j]
                
                let timeDiff = f2.timestamp.timeIntervalSince(f1.timestamp)
                if timeDiff > windowSeconds {
                    break  // Outside window
                }
                
                // Create correlation key (sorted to make pairs unique)
                let modes = [f1.mode.rawValue, f2.mode.rawValue].sorted()
                let key = "\(modes[0])|\(modes[1])"
                
                if var existing = correlations[key] {
                    existing = FailureCorrelation(
                        mode1: existing.mode1,
                        mode2: existing.mode2,
                        cooccurrenceCount: existing.cooccurrenceCount + 1,
                        averageTimeDelta: (existing.averageTimeDelta * Double(existing.cooccurrenceCount) + timeDiff) / Double(existing.cooccurrenceCount + 1)
                    )
                    correlations[key] = existing
                } else {
                    correlations[key] = FailureCorrelation(
                        mode1: f1.mode,
                        mode2: f2.mode,
                        cooccurrenceCount: 1,
                        averageTimeDelta: timeDiff
                    )
                }
            }
        }
        
        return Array(correlations.values).sorted { $0.cooccurrenceCount > $1.cooccurrenceCount }
    }
}

// MARK: - Trend Analysis

/// Analysis of failure trends over time
public struct FailureTrendAnalysis: Sendable, Codable {
    /// Total failures in the period
    public let totalFailures: Int
    
    /// Start of analysis period
    public let periodStart: Date
    
    /// End of analysis period
    public let periodEnd: Date
    
    /// Average failures per hour
    public let failuresPerHour: Double
    
    /// Failures by hour
    public let hourlyBreakdown: [String: Int]
    
    /// Hour with most failures
    public let peakHour: String?
    
    /// Count at peak hour
    public let peakHourCount: Int
    
    public init(
        totalFailures: Int,
        periodStart: Date,
        periodEnd: Date,
        failuresPerHour: Double,
        hourlyBreakdown: [String: Int],
        peakHour: String?,
        peakHourCount: Int
    ) {
        self.totalFailures = totalFailures
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.failuresPerHour = failuresPerHour
        self.hourlyBreakdown = hourlyBreakdown
        self.peakHour = peakHour
        self.peakHourCount = peakHourCount
    }
    
    /// Empty analysis
    public static let empty = FailureTrendAnalysis(
        totalFailures: 0,
        periodStart: Date(),
        periodEnd: Date(),
        failuresPerHour: 0,
        hourlyBreakdown: [:],
        peakHour: nil,
        peakHourCount: 0
    )
}

// MARK: - Failure Correlation

/// Correlation between two failure modes
public struct FailureCorrelation: Sendable, Codable, Equatable {
    /// First failure mode
    public let mode1: FailureMode
    
    /// Second failure mode
    public let mode2: FailureMode
    
    /// Number of times these failures occurred together
    public let cooccurrenceCount: Int
    
    /// Average time between the two failures
    public let averageTimeDelta: TimeInterval
    
    public init(
        mode1: FailureMode,
        mode2: FailureMode,
        cooccurrenceCount: Int,
        averageTimeDelta: TimeInterval
    ) {
        self.mode1 = mode1
        self.mode2 = mode2
        self.cooccurrenceCount = cooccurrenceCount
        self.averageTimeDelta = averageTimeDelta
    }
    
    /// Whether this might indicate a causal relationship
    public var potentiallyCausal: Bool {
        averageTimeDelta < 5 && cooccurrenceCount >= 3
    }
}
