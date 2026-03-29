// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ReportAnonymizer.swift - Privacy-safe report anonymization
// Part of BLEKit
// Trace: EVID-001

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Anonymization Strategy

/// Strategy for anonymizing identifiers
public enum AnonymizationStrategy: String, CaseIterable, Sendable {
    /// SHA-256 hash with salt
    case hash
    
    /// Replace with fixed placeholder
    case redact
    
    /// Replace with sequential ID
    case sequential
    
    /// Remove entirely
    case remove
}

// MARK: - PII Type

/// Types of personally identifiable information
public enum PIIType: String, CaseIterable, Sendable {
    /// Device serial numbers
    case serialNumber
    
    /// Bluetooth UUIDs
    case bluetoothUUID
    
    /// Device names
    case deviceName
    
    /// MAC addresses
    case macAddress
    
    /// IP addresses
    case ipAddress
    
    /// User names or identifiers
    case userName
    
    /// Email addresses
    case email
    
    /// Phone numbers
    case phoneNumber
    
    /// Location data
    case location
    
    /// Timestamps (can be de-anonymizing in some contexts)
    case timestamp
    
    /// Pattern for detecting this PII type
    public var pattern: String? {
        switch self {
        case .serialNumber:
            return nil  // Device-specific patterns
        case .bluetoothUUID:
            return "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        case .deviceName:
            return nil  // Context-dependent
        case .macAddress:
            return "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}"
        case .ipAddress:
            return "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"
        case .userName:
            return nil  // Context-dependent
        case .email:
            return "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        case .phoneNumber:
            return "\\+?\\d{10,15}"
        case .location:
            return nil  // Complex patterns
        case .timestamp:
            return nil  // Handled separately
        }
    }
}

// MARK: - Anonymization Result

/// Result of anonymization operation
public struct AnonymizationResult: Sendable {
    /// Number of fields anonymized
    public let fieldsAnonymized: Int
    
    /// Types of PII found and removed
    public let piiTypesFound: Set<PIIType>
    
    /// Hash mappings (original hash -> anonymized ID) for reference
    public let hashMappings: [String: String]
    
    /// Any warnings generated
    public let warnings: [String]
    
    public init(
        fieldsAnonymized: Int = 0,
        piiTypesFound: Set<PIIType> = [],
        hashMappings: [String: String] = [:],
        warnings: [String] = []
    ) {
        self.fieldsAnonymized = fieldsAnonymized
        self.piiTypesFound = piiTypesFound
        self.hashMappings = hashMappings
        self.warnings = warnings
    }
}

// MARK: - Report Anonymizer

/// Anonymizes diagnostic reports to remove PII
///
/// Trace: EVID-001
///
/// Provides privacy-safe anonymization of device IDs, UUIDs, and other
/// personally identifiable information in diagnostic reports. Uses
/// consistent hashing to allow correlation across reports while
/// preventing identification of specific devices.
public struct ReportAnonymizer: Sendable {
    
    // MARK: - Configuration
    
    /// Configuration for anonymization
    public struct Config: Sendable {
        /// Salt for hashing (should be unique per installation)
        public let salt: String
        
        /// Strategy for device IDs
        public let deviceIdStrategy: AnonymizationStrategy
        
        /// Strategy for UUIDs
        public let uuidStrategy: AnonymizationStrategy
        
        /// Strategy for device names
        public let deviceNameStrategy: AnonymizationStrategy
        
        /// Strategy for timestamps
        public let timestampStrategy: TimestampStrategy
        
        /// Whether to anonymize packet data
        public let anonymizePacketData: Bool
        
        /// Prefix length to preserve in hashed IDs (for readability)
        public let hashPrefixLength: Int
        
        /// Standard configuration
        public static func standard(salt: String = UUID().uuidString) -> Config {
            Config(
                salt: salt,
                deviceIdStrategy: .hash,
                uuidStrategy: .hash,
                deviceNameStrategy: .redact,
                timestampStrategy: .relative,
                anonymizePacketData: false,
                hashPrefixLength: 8
            )
        }
        
        /// Maximum privacy (remove everything)
        public static func maxPrivacy(salt: String = UUID().uuidString) -> Config {
            Config(
                salt: salt,
                deviceIdStrategy: .hash,
                uuidStrategy: .hash,
                deviceNameStrategy: .remove,
                timestampStrategy: .rounded,
                anonymizePacketData: true,
                hashPrefixLength: 6
            )
        }
        
        /// Research configuration (preserve more data with consent)
        public static func research(salt: String) -> Config {
            Config(
                salt: salt,
                deviceIdStrategy: .hash,
                uuidStrategy: .hash,
                deviceNameStrategy: .hash,
                timestampStrategy: .relative,
                anonymizePacketData: false,
                hashPrefixLength: 12
            )
        }
        
        public init(
            salt: String,
            deviceIdStrategy: AnonymizationStrategy = .hash,
            uuidStrategy: AnonymizationStrategy = .hash,
            deviceNameStrategy: AnonymizationStrategy = .redact,
            timestampStrategy: TimestampStrategy = .relative,
            anonymizePacketData: Bool = false,
            hashPrefixLength: Int = 8
        ) {
            self.salt = salt
            self.deviceIdStrategy = deviceIdStrategy
            self.uuidStrategy = uuidStrategy
            self.deviceNameStrategy = deviceNameStrategy
            self.timestampStrategy = timestampStrategy
            self.anonymizePacketData = anonymizePacketData
            self.hashPrefixLength = min(32, max(4, hashPrefixLength))
        }
    }
    
    /// Strategy for handling timestamps
    public enum TimestampStrategy: String, Sendable {
        /// Keep exact timestamps
        case exact
        
        /// Convert to relative (seconds from start)
        case relative
        
        /// Round to nearest minute
        case rounded
        
        /// Remove timestamps
        case remove
    }
    
    // MARK: - Properties
    
    private let config: Config
    private var sequentialCounter: Int = 0
    private var hashCache: [String: String] = [:]
    
    // MARK: - Initialization
    
    public init(config: Config = .standard()) {
        self.config = config
    }
    
    // MARK: - Hashing
    
    /// Hash a string with the configured salt
    public func hash(_ value: String) -> String {
        let input = value + config.salt
        
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(input.utf8))
        let hashString = digest.map { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(config.hashPrefixLength))
        #else
        // Fallback for platforms without CryptoKit
        return fallbackHash(input)
        #endif
    }
    
    /// Fallback hash for platforms without CryptoKit
    private func fallbackHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hashString = String(format: "%016llx", hash)
        return String(hashString.prefix(config.hashPrefixLength))
    }
    
    // MARK: - Anonymization Methods
    
    /// Anonymize a device ID
    public mutating func anonymizeDeviceId(_ deviceId: String) -> String {
        switch config.deviceIdStrategy {
        case .hash:
            if let cached = hashCache[deviceId] {
                return cached
            }
            let hashed = "DEV-" + hash(deviceId)
            hashCache[deviceId] = hashed
            return hashed
        case .redact:
            return "[REDACTED-DEVICE]"
        case .sequential:
            sequentialCounter += 1
            return "DEV-\(String(format: "%04d", sequentialCounter))"
        case .remove:
            return ""
        }
    }
    
    /// Anonymize a UUID
    public mutating func anonymizeUUID(_ uuid: String) -> String {
        switch config.uuidStrategy {
        case .hash:
            if let cached = hashCache[uuid] {
                return cached
            }
            let hashed = hash(uuid)
            // Format as UUID-like structure
            let anonymized = "\(hashed)-0000-0000-0000-000000000000"
            hashCache[uuid] = anonymized
            return anonymized
        case .redact:
            return "00000000-0000-0000-0000-000000000000"
        case .sequential:
            sequentialCounter += 1
            return String(format: "%08d-0000-0000-0000-000000000000", sequentialCounter)
        case .remove:
            return ""
        }
    }
    
    /// Anonymize a device name
    public mutating func anonymizeDeviceName(_ name: String) -> String {
        switch config.deviceNameStrategy {
        case .hash:
            return "Device-" + hash(name)
        case .redact:
            return "[REDACTED-NAME]"
        case .sequential:
            sequentialCounter += 1
            return "Device-\(sequentialCounter)"
        case .remove:
            return ""
        }
    }
    
    /// Anonymize a timestamp
    public func anonymizeTimestamp(_ timestamp: Date, referenceDate: Date) -> Date? {
        switch config.timestampStrategy {
        case .exact:
            return timestamp
        case .relative:
            // Return as offset from reference
            let offset = timestamp.timeIntervalSince(referenceDate)
            return Date(timeIntervalSince1970: offset)
        case .rounded:
            // Round to nearest minute
            let interval = timestamp.timeIntervalSince1970
            let rounded = (interval / 60).rounded() * 60
            return Date(timeIntervalSince1970: rounded)
        case .remove:
            return nil
        }
    }
    
    /// Anonymize a MAC address
    public mutating func anonymizeMacAddress(_ mac: String) -> String {
        return hash(mac).prefix(12).enumerated().map { i, c in
            i > 0 && i % 2 == 0 ? ":\(c)" : String(c)
        }.joined()
    }
    
    // MARK: - Traffic Entry Anonymization
    
    /// Anonymize a traffic entry
    public mutating func anonymize(_ entry: TrafficEntry, referenceDate: Date) -> TrafficEntry {
        var anonymizedEntry = entry
        
        // Anonymize UUID if present
        if let characteristic = entry.characteristic {
            anonymizedEntry = TrafficEntry(
                id: UUID(),  // New ID
                timestamp: anonymizeTimestamp(entry.timestamp, referenceDate: referenceDate) ?? entry.timestamp,
                direction: entry.direction,
                data: config.anonymizePacketData ? anonymizePacketData(entry.data) : entry.data,
                characteristic: anonymizeUUID(characteristic),
                service: entry.service.map { anonymizeUUID($0) },
                note: anonymizeNote(entry.note)
            )
        } else {
            anonymizedEntry = TrafficEntry(
                id: UUID(),
                timestamp: anonymizeTimestamp(entry.timestamp, referenceDate: referenceDate) ?? entry.timestamp,
                direction: entry.direction,
                data: config.anonymizePacketData ? anonymizePacketData(entry.data) : entry.data,
                characteristic: nil,
                service: entry.service.map { anonymizeUUID($0) },
                note: anonymizeNote(entry.note)
            )
        }
        
        return anonymizedEntry
    }
    
    /// Anonymize a collection of traffic entries
    public mutating func anonymize(_ entries: [TrafficEntry]) -> ([TrafficEntry], AnonymizationResult) {
        guard !entries.isEmpty else {
            return ([], AnonymizationResult())
        }
        
        let referenceDate = entries.map { $0.timestamp }.min() ?? Date()
        var anonymizedEntries: [TrafficEntry] = []
        var fieldsAnonymized = 0
        var piiTypesFound: Set<PIIType> = []
        
        for entry in entries {
            let anonymized = anonymize(entry, referenceDate: referenceDate)
            anonymizedEntries.append(anonymized)
            
            // Track what was anonymized
            if entry.characteristic != nil {
                fieldsAnonymized += 1
                piiTypesFound.insert(.bluetoothUUID)
            }
            if entry.service != nil {
                fieldsAnonymized += 1
            }
            if entry.note != nil {
                fieldsAnonymized += 1
            }
        }
        
        let result = AnonymizationResult(
            fieldsAnonymized: fieldsAnonymized,
            piiTypesFound: piiTypesFound,
            hashMappings: hashCache,
            warnings: []
        )
        
        return (anonymizedEntries, result)
    }
    
    // MARK: - String Anonymization
    
    /// Anonymize a note field (may contain PII)
    private mutating func anonymizeNote(_ note: String?) -> String? {
        guard var text = note else { return nil }
        
        // Remove email addresses
        if let emailPattern = PIIType.email.pattern,
           let regex = try? NSRegularExpression(pattern: emailPattern) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[EMAIL]")
        }
        
        // Remove MAC addresses
        if let macPattern = PIIType.macAddress.pattern,
           let regex = try? NSRegularExpression(pattern: macPattern) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[MAC]")
        }
        
        // Remove IP addresses
        if let ipPattern = PIIType.ipAddress.pattern,
           let regex = try? NSRegularExpression(pattern: ipPattern) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[IP]")
        }
        
        // Remove UUIDs
        if let uuidPattern = PIIType.bluetoothUUID.pattern,
           let regex = try? NSRegularExpression(pattern: uuidPattern) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[UUID]")
        }
        
        return text
    }
    
    /// Anonymize packet data (if configured)
    private func anonymizePacketData(_ data: Data) -> Data {
        // For packet data, we typically want to preserve structure but mask specific bytes
        // This is a simplified implementation - real anonymization would be protocol-aware
        guard data.count > 4 else { return data }
        
        var anonymized = Data(data)
        // Mask bytes 2-5 which often contain device-specific data
        for i in 2..<min(6, anonymized.count) {
            anonymized[i] = 0x00
        }
        return anonymized
    }
    
    // MARK: - Text Scanning
    
    /// Scan text for potential PII
    public func scanForPII(_ text: String) -> [PIIType] {
        var found: [PIIType] = []
        
        for piiType in PIIType.allCases {
            if let pattern = piiType.pattern,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                found.append(piiType)
            }
        }
        
        return found
    }
    
    /// Redact all detected PII from text
    public func redactPII(_ text: String) -> String {
        var result = text
        
        for piiType in PIIType.allCases {
            guard let pattern = piiType.pattern,
                  let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[\(piiType.rawValue.uppercased())]")
        }
        
        return result
    }
    
    // MARK: - Status
    
    /// Get current hash cache size
    public var cacheSize: Int {
        hashCache.count
    }
    
    /// Get configuration
    public func getConfig() -> Config {
        config
    }
    
    /// Reset the anonymizer state
    public mutating func reset() {
        sequentialCounter = 0
        hashCache.removeAll()
    }
}

// MARK: - Anonymized Report

/// A fully anonymized diagnostic report
public struct AnonymizedReport: Sendable, Codable {
    /// Report version
    public let version: String
    
    /// Anonymized device identifier
    public let deviceId: String
    
    /// Report generation timestamp (may be relative)
    public let generatedAt: Date
    
    /// Anonymized traffic entries
    public let entries: [TrafficEntry]
    
    /// Session duration in seconds
    public let sessionDuration: TimeInterval
    
    /// Entry count
    public let entryCount: Int
    
    /// Error count
    public let errorCount: Int
    
    /// Anonymization metadata
    public let anonymizationInfo: AnonymizationInfo
    
    public init(
        version: String = "1.0",
        deviceId: String,
        generatedAt: Date = Date(),
        entries: [TrafficEntry],
        sessionDuration: TimeInterval,
        entryCount: Int,
        errorCount: Int,
        anonymizationInfo: AnonymizationInfo
    ) {
        self.version = version
        self.deviceId = deviceId
        self.generatedAt = generatedAt
        self.entries = entries
        self.sessionDuration = sessionDuration
        self.entryCount = entryCount
        self.errorCount = errorCount
        self.anonymizationInfo = anonymizationInfo
    }
}

/// Metadata about anonymization applied
public struct AnonymizationInfo: Sendable, Codable {
    /// Strategy used for device IDs
    public let deviceIdStrategy: String
    
    /// Strategy used for UUIDs
    public let uuidStrategy: String
    
    /// Strategy used for timestamps
    public let timestampStrategy: String
    
    /// Whether packet data was anonymized
    public let packetDataAnonymized: Bool
    
    /// Number of unique devices in report
    public let uniqueDeviceCount: Int
    
    /// PII types that were redacted
    public let redactedPIITypes: [String]
    
    public init(
        deviceIdStrategy: String,
        uuidStrategy: String,
        timestampStrategy: String,
        packetDataAnonymized: Bool,
        uniqueDeviceCount: Int,
        redactedPIITypes: [String]
    ) {
        self.deviceIdStrategy = deviceIdStrategy
        self.uuidStrategy = uuidStrategy
        self.timestampStrategy = timestampStrategy
        self.packetDataAnonymized = packetDataAnonymized
        self.uniqueDeviceCount = uniqueDeviceCount
        self.redactedPIITypes = redactedPIITypes
    }
}

// MARK: - Report Builder

/// Builder for creating anonymized reports
public struct AnonymizedReportBuilder {
    
    private var anonymizer: ReportAnonymizer
    private let originalDeviceId: String
    
    public init(deviceId: String, config: ReportAnonymizer.Config = .standard()) {
        self.originalDeviceId = deviceId
        self.anonymizer = ReportAnonymizer(config: config)
    }
    
    /// Build an anonymized report from traffic entries
    public mutating func build(from entries: [TrafficEntry], errorCount: Int = 0) -> AnonymizedReport {
        let (anonymizedEntries, result) = anonymizer.anonymize(entries)
        
        let sessionDuration: TimeInterval
        if let first = entries.first?.timestamp, let last = entries.last?.timestamp {
            sessionDuration = last.timeIntervalSince(first)
        } else {
            sessionDuration = 0
        }
        
        let config = anonymizer.getConfig()
        
        let info = AnonymizationInfo(
            deviceIdStrategy: config.deviceIdStrategy.rawValue,
            uuidStrategy: config.uuidStrategy.rawValue,
            timestampStrategy: config.timestampStrategy.rawValue,
            packetDataAnonymized: config.anonymizePacketData,
            uniqueDeviceCount: 1,  // Single device per report
            redactedPIITypes: result.piiTypesFound.map { $0.rawValue }
        )
        
        return AnonymizedReport(
            deviceId: anonymizer.anonymizeDeviceId(originalDeviceId),
            entries: anonymizedEntries,
            sessionDuration: sessionDuration,
            entryCount: entries.count,
            errorCount: errorCount,
            anonymizationInfo: info
        )
    }
}
