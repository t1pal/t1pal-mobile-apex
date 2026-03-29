// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TransmitterIdentity.swift
// BLEKit
//
// Dexcom transmitter identity types for CGM simulation.
// Trace: PRD-007 REQ-SIM-002

import Foundation

// MARK: - Transmitter Type

/// Dexcom transmitter generation
public enum TransmitterType: String, Sendable, Codable, CaseIterable {
    case g5 = "G5"
    case g6 = "G6"
    case g7 = "G7"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .g5: return "Dexcom G5"
        case .g6: return "Dexcom G6"
        case .g7: return "Dexcom G7"
        }
    }
    
    /// Service UUID for advertisement
    /// G7-COEX-FIX-006: G6 and G7 both use FEBC (verified Loop/G7SensorKit)
    public var advertisementUUID: BLEUUID {
        switch self {
        case .g5, .g6: return .dexcomAdvertisement   // 0xFEBC
        case .g7: return .dexcomG7Advertisement       // 0xFEBC (same as G6)
        }
    }
    
    /// Whether this type uses AES authentication (G5/G6) or J-PAKE (G7)
    public var usesAESAuthentication: Bool {
        switch self {
        case .g5, .g6: return true
        case .g7: return false
        }
    }
    
    /// Default firmware version for this transmitter type
    public var defaultFirmwareVersion: String {
        switch self {
        case .g5: return "1.0.4.10"
        case .g6: return "1.6.5.25"
        case .g7: return "2.18.2.67"
        }
    }
}

// MARK: - Transmitter ID

/// A validated Dexcom transmitter ID for simulation
///
/// Transmitter IDs are 6 alphanumeric characters. The first character
/// indicates the transmitter generation:
/// - `4` prefix: G7 (e.g., "4P1234")
/// - `8` prefix: G6 (e.g., "8G1234")
/// - `9` prefix: G7 ONE (e.g., "9N1234")
/// - Other: G5 or older
public struct SimulatorTransmitterID: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The raw 6-character ID string
    public let rawValue: String
    
    /// Detected transmitter type based on ID prefix
    public let detectedType: TransmitterType
    
    /// Create a transmitter ID from a string
    /// - Parameter id: 6 alphanumeric character ID
    /// - Returns: nil if validation fails
    public init?(_ id: String) {
        let cleaned = id.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Must be exactly 6 characters
        guard cleaned.count == 6 else { return nil }
        
        // Must be alphanumeric only
        guard cleaned.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        
        self.rawValue = cleaned
        self.detectedType = SimulatorTransmitterID.detectType(from: cleaned)
    }
    
    /// Create a transmitter ID with explicit type override
    /// - Parameters:
    ///   - id: 6 alphanumeric character ID
    ///   - type: Explicit transmitter type (overrides detection)
    public init?(_ id: String, type: TransmitterType) {
        let cleaned = id.uppercased().trimmingCharacters(in: .whitespaces)
        
        guard cleaned.count == 6 else { return nil }
        guard cleaned.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        
        self.rawValue = cleaned
        self.detectedType = type
    }
    
    /// Detect transmitter type from ID prefix
    private static func detectType(from id: String) -> TransmitterType {
        guard let firstChar = id.first else { return .g6 }
        
        switch firstChar {
        case "4":
            return .g7  // G7 standard
        case "9":
            return .g7  // G7 ONE / newer G7
        case "8":
            return .g6  // G6
        default:
            // Older transmitters (G5) or unknown
            return .g5
        }
    }
    
    /// Generate BLE advertisement name
    ///
    /// Dexcom transmitters advertise as "DexcomXX" where XX is the
    /// last two characters of the transmitter ID.
    public var advertisementName: String {
        let suffix = String(rawValue.suffix(2))
        return "Dexcom\(suffix)"
    }
    
    /// Last 2 characters of the ID (used in advertisement)
    public var suffix: String {
        String(rawValue.suffix(2))
    }
    
    /// First character (generation indicator)
    public var prefix: Character {
        rawValue.first!
    }
    
    public var description: String {
        rawValue
    }
    
    // MARK: - Generation
    
    /// Generate a random valid transmitter ID
    /// - Parameter type: Desired transmitter type
    /// - Returns: A random valid transmitter ID
    public static func random(type: TransmitterType = .g6) -> SimulatorTransmitterID {
        let prefixChar: Character
        switch type {
        case .g5:
            prefixChar = ["0", "1", "2", "3", "5", "6", "7"].randomElement()!
        case .g6:
            prefixChar = "8"
        case .g7:
            prefixChar = ["4", "9"].randomElement()!
        }
        
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomPart = String((0..<5).map { _ in chars.randomElement()! })
        
        return SimulatorTransmitterID("\(prefixChar)\(randomPart)")!
    }
}

// MARK: - Firmware Version

/// Dexcom firmware version in X.Y.Z.W format
public struct FirmwareVersion: Sendable, Hashable, Codable, CustomStringConvertible, Comparable {
    public let major: UInt8
    public let minor: UInt8
    public let patch: UInt8
    public let build: UInt8
    
    /// Create from version components
    public init(major: UInt8, minor: UInt8, patch: UInt8, build: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
    }
    
    /// Parse from string "X.Y.Z.W"
    public init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts[2]
        self.build = parts[3]
    }
    
    public var description: String {
        "\(major).\(minor).\(patch).\(build)"
    }
    
    /// Binary representation for BLE packets (4 bytes)
    public var bytes: Data {
        Data([major, minor, patch, build])
    }
    
    public static func < (lhs: FirmwareVersion, rhs: FirmwareVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return lhs.build < rhs.build
    }
}

// MARK: - Transmitter Configuration

/// Complete configuration for a simulated transmitter
public struct SimulatorTransmitterConfig: Sendable, Codable {
    /// Transmitter ID (6 alphanumeric)
    public let id: SimulatorTransmitterID
    
    /// Serial number (10+ digits)
    public let serialNumber: String
    
    /// Firmware version
    public let firmwareVersion: FirmwareVersion
    
    /// Transmitter type (may differ from auto-detected if overridden)
    public let type: TransmitterType
    
    /// Transmitter start time (for calculating session age)
    public let activationDate: Date
    
    /// Create a transmitter configuration
    public init(
        id: SimulatorTransmitterID,
        serialNumber: String? = nil,
        firmwareVersion: FirmwareVersion? = nil,
        type: TransmitterType? = nil,
        activationDate: Date = Date()
    ) {
        self.id = id
        self.serialNumber = serialNumber ?? SimulatorTransmitterConfig.generateSerialNumber()
        self.firmwareVersion = firmwareVersion ?? FirmwareVersion(id.detectedType.defaultFirmwareVersion)!
        self.type = type ?? id.detectedType
        self.activationDate = activationDate
    }
    
    /// Generate a random serial number
    private static func generateSerialNumber() -> String {
        let digits = "0123456789"
        return String((0..<10).map { _ in digits.randomElement()! })
    }
    
    /// Create BLE advertisement data for this transmitter
    public var advertisementData: BLEAdvertisementData {
        BLEAdvertisementData(
            localName: id.advertisementName,
            serviceUUIDs: [type.advertisementUUID],
            manufacturerData: nil
        )
    }
    
    /// Session age in seconds since activation
    public var sessionAge: TimeInterval {
        Date().timeIntervalSince(activationDate)
    }
    
    /// Days since activation
    public var sessionDays: Int {
        Int(sessionAge / 86400)
    }
    
    // MARK: - Presets
    
    /// Create a G6 transmitter with default settings
    public static func g6(id: String = "8G1234") -> SimulatorTransmitterConfig? {
        guard let txId = SimulatorTransmitterID(id) else { return nil }
        return SimulatorTransmitterConfig(id: txId, type: .g6)
    }
    
    /// Create a G7 transmitter with default settings
    public static func g7(id: String = "4P5678") -> SimulatorTransmitterConfig? {
        guard let txId = SimulatorTransmitterID(id) else { return nil }
        return SimulatorTransmitterConfig(id: txId, type: .g7)
    }
    
    /// Create a random transmitter
    public static func random(type: TransmitterType = .g6) -> SimulatorTransmitterConfig {
        SimulatorTransmitterConfig(id: .random(type: type), type: type)
    }
}

// MARK: - Transmitter State

/// Current operational state of a transmitter
public enum TransmitterState: String, Sendable, Codable {
    /// Not activated, waiting for sensor
    case inactive
    
    /// Sensor warming up (2 hours for G6, 30 min for G7)
    case warmup
    
    /// Normal operation, providing glucose values
    case active
    
    /// Sensor session expired
    case expired
    
    /// Transmitter battery low
    case lowBattery
    
    /// Error state
    case error
}

// MARK: - Session Info

/// Information about the current sensor session
public struct SensorSession: Sendable, Codable {
    /// Session start time
    public let startTime: Date
    
    /// Current session state
    public var state: TransmitterState
    
    /// Warmup duration for this transmitter type
    public let warmupDuration: TimeInterval
    
    /// Maximum session duration
    public let maxSessionDuration: TimeInterval
    
    /// Create a new sensor session
    public init(
        startTime: Date = Date(),
        state: TransmitterState = .warmup,
        transmitterType: TransmitterType = .g6
    ) {
        self.startTime = startTime
        self.state = state
        
        switch transmitterType {
        case .g5, .g6:
            self.warmupDuration = 2 * 60 * 60  // 2 hours
            self.maxSessionDuration = 10 * 24 * 60 * 60  // 10 days
        case .g7:
            self.warmupDuration = 30 * 60  // 30 minutes
            self.maxSessionDuration = 10.5 * 24 * 60 * 60  // 10.5 days
        }
    }
    
    /// Time elapsed since session start
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Whether warmup is complete
    public var isWarmupComplete: Bool {
        elapsed >= warmupDuration
    }
    
    /// Whether session is expired
    public var isExpired: Bool {
        elapsed >= maxSessionDuration
    }
    
    /// Remaining session time
    public var remainingTime: TimeInterval {
        max(0, maxSessionDuration - elapsed)
    }
    
    /// Update state based on elapsed time
    public mutating func updateState() {
        if isExpired {
            state = .expired
        } else if isWarmupComplete && state == .warmup {
            state = .active
        }
    }
}
