// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7Constants.swift
// CGMKit - DexcomG7
//
// Dexcom G7 BLE service and characteristic UUIDs and constants.
// G7 uses different UUIDs and is a one-piece sensor (no separate transmitter).
// Trace: PRD-008 REQ-BLE-008
// Source documentation added PROD-HARDEN-014 (2026-02-21).
//
// External sources:
// - G7SensorKit/G7SensorKit/BluetoothServices.swift:18-38 (UUIDs)
// - G7SensorKit/G7SensorKit/G7CGMManager/G7Sensor.swift:67-69 (lifetime, warmup, grace)
// - G7SensorKit/G7SensorKit/G7CGMManager/G7PeripheralManager.swift:95,169,553 (timeouts)
// - xDrip4iOS CGMG7Transmitter.swift (cross-ref)

import Foundation

/// Dexcom G7 BLE constants
public enum G7Constants {
    
    // MARK: - Advertisement
    // Source: externals/G7SensorKit/G7SensorKit/BluetoothServices.swift:19
    
    /// Dexcom G7 advertisement service UUID (same as G6)
    public static let advertisementServiceUUID = "FEBC"
    
    // MARK: - Service UUIDs
    // Source: externals/G7SensorKit/G7SensorKit/BluetoothServices.swift:18-23
    
    /// Dexcom G7 CGM service (same base as G6)
    public static let cgmServiceUUID = "F8083532-849E-531C-C594-30F1F86A4EA5"
    
    /// Service B (secondary service)
    public static let serviceBUUID = "F8084532-849E-531C-C594-30F1F86A4EA5"
    
    // MARK: - Characteristic UUIDs
    // Source: externals/G7SensorKit/G7SensorKit/BluetoothServices.swift:25-38
    // Cross-ref: externals/xDrip4iOS CGMG7Transmitter.swift
    
    /// Communication characteristic (Read/Notify)
    public static let communicationUUID = "F8083533-849E-531C-C594-30F1F86A4EA5"
    
    /// Control characteristic (Write/Indicate) - commands and responses
    public static let controlUUID = "F8083534-849E-531C-C594-30F1F86A4EA5"
    
    /// Authentication characteristic (Write/Indicate)
    public static let authenticationUUID = "F8083535-849E-531C-C594-30F1F86A4EA5"
    
    /// Backfill characteristic (Read/Write/Notify) - historical data
    public static let backfillUUID = "F8083536-849E-531C-C594-30F1F86A4EA5"
    
    // MARK: - Timing Constants
    // Source: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7Sensor.swift:67-69
    // Source: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7PeripheralManager.swift:169,95,553
    
    /// Default keep-alive interval in seconds
    public static let defaultKeepAliveTime: UInt8 = 25
    
    /// Maximum time to wait for connection (seconds)
    public static let connectionTimeout: TimeInterval = 30.0
    
    /// Time between glucose readings (seconds)
    public static let glucoseInterval: TimeInterval = 300.0  // 5 minutes
    
    /// Sensor warmup period (minutes) - G7 default is 27 min
    /// Source: G7Sensor.swift:68 — `defaultWarmupDuration = TimeInterval(minutes: 27)`
    public static let sensorWarmupMinutes: Double = 27.0
    
    /// Sensor session duration (hours) - G7 is 10 days = 240 hours
    /// Source: G7Sensor.swift:67 — `defaultLifetime = TimeInterval(hours: 10 * 24)`
    public static let sensorLifetimeHours: Double = 240.0
    
    /// Grace period after expiration (hours) - sensor continues for 12 extra hours
    /// Source: G7Sensor.swift:69 — `gracePeriod = TimeInterval(hours: 12)`
    public static let gracePeriodHours: Double = 12.0
    
    /// Total usable sensor life (days) - lifetime + grace = 10.5 days
    public static let sensorSessionDays: Double = 10.5
    
    /// G7 sensor life (days) - one-piece, no separate transmitter
    public static let sensorLifeDays: Double = 10.5
    
    // MARK: - BLE Operation Timeouts
    // Source: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7PeripheralManager.swift
    // Trace: PROD-HARDEN-022
    
    /// Service/characteristic discovery timeout (seconds)
    /// Source: G7PeripheralManager.swift:169 — `discoveryTimeout: TimeInterval = 2`
    public static let discoveryTimeout: TimeInterval = 2.0
    
    /// Write operation timeout (seconds)
    /// Source: G7PeripheralManager.swift:95 — `timeout: 1`
    public static let writeTimeout: TimeInterval = 1.0
    
    /// Generic command timeout (seconds)
    /// Source: G7PeripheralManager.swift:553 — `timeout: TimeInterval = 2`
    public static let commandTimeout: TimeInterval = 2.0
    
    /// J-PAKE authentication timeout (seconds)
    /// J-PAKE has 3 rounds: Round1 + Round2 + Confirmation
    /// Each round may take several seconds over BLE
    /// Trace: PROD-HARDEN-022
    public static let authenticationTimeout: TimeInterval = 30.0
    
    /// Overall connection timeout (seconds)
    /// Includes scanning, connecting, discovery, and authentication
    /// Trace: PROD-HARDEN-022
    public static let overallConnectionTimeout: TimeInterval = 60.0
    
    /// Single authentication round timeout (seconds)
    /// Each J-PAKE round should complete within this time
    /// Trace: PROD-HARDEN-022
    public static let authRoundTimeout: TimeInterval = 10.0
    
    // MARK: - Glucose Constants
    
    /// Minimum valid glucose value (mg/dL)
    public static let minGlucose: Double = 40.0
    
    /// Maximum valid glucose value (mg/dL)
    public static let maxGlucose: Double = 400.0
    
    /// Value indicating sensor not ready/warming up
    public static let glucoseNotReady: UInt16 = 0
    
    /// Value indicating sensor error
    public static let glucoseError: UInt16 = 0xFFFF
    
    // MARK: - Session Sentinel
    // Trace: GAP-API-021 (future-dated entries fix)
    // Source: xDrip CalibrationState.java INVALID_TIME, CGMBLEKit issue #191
    
    /// Sentinel value indicating no active session
    /// When sensor reports this as sessionStartTime, there is no active sensor session.
    /// Conditions: sensor expired, stopped, failed, or between sensor insertions.
    public static let invalidSessionTime: UInt32 = 0xFFFFFFFF
    
    /// Maximum reasonable session age in seconds (15 days = 1,296,000 seconds)
    /// Used to detect corrupt session ages from underflow
    public static let maxReasonableSessionAge: UInt32 = 15 * 24 * 60 * 60
    
    // MARK: - G7-Specific Constants
    
    /// G7 uses J-PAKE authentication instead of AES
    public static let usesJPAKEAuth = true
    
    /// Maximum sensor code length
    public static let sensorCodeLength = 4
    
    /// G7 sensor serial number length
    public static let sensorSerialLength = 10
}

// MARK: - Sensor State

/// Dexcom G7 sensor state
public enum G7SensorState: UInt8, Sendable, Codable {
    case stopped = 0x01
    case warmup = 0x02
    case paired = 0x03
    case okay = 0x04
    case firstReading = 0x05
    case secondReading = 0x06
    case running = 0x07
    case failed = 0x08
    case expired = 0x09
    case ended = 0x0A
    case sensorError = 0x0B
    case pairing = 0x0C
    case unknown = 0xFF
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .warmup: return "Warming Up"
        case .paired: return "Paired"
        case .okay: return "Starting"
        case .firstReading: return "First Reading"
        case .secondReading: return "Second Reading"
        case .running: return "Running"
        case .failed: return "Failed"
        case .expired: return "Expired"
        case .ended: return "Ended"
        case .sensorError: return "Sensor Error"
        case .pairing: return "Pairing"
        case .unknown: return "Unknown"
        }
    }
    
    /// Whether readings are available
    public var hasGlucose: Bool {
        switch self {
        case .okay, .firstReading, .secondReading, .running:
            return true
        default:
            return false
        }
    }
    
    /// Whether sensor is in usable state
    public var isActive: Bool {
        switch self {
        case .warmup, .paired, .okay, .firstReading, .secondReading, .running:
            return true
        default:
            return false
        }
    }
}

// MARK: - Algorithm State

/// Dexcom G7 algorithm state
/// Values from xDrip CalibrationState.java and Loop G7SensorKit
public enum G7AlgorithmState: UInt8, Sendable, Codable {
    case unknown = 0x00
    case stopped = 0x01
    case warmup = 0x02
    case excessNoise = 0x03
    case needsFirstCalibration = 0x04
    case needsSecondCalibration = 0x05
    case okay = 0x06
    case needsCalibration = 0x07
    case calibrationError1 = 0x08
    case calibrationError2 = 0x09
    case needsDifferentCalibration = 0x0A
    case sensorFailed = 0x0B
    case sensorFailed2 = 0x0C
    case unusualCalibration = 0x0D
    case insufficientCalibration = 0x0E
    case ended = 0x0F
    case sensorFailed3 = 0x10
    case transmitterProblem = 0x11
    case sensorErrors = 0x12
    case sensorFailed4 = 0x13
    case sensorFailed5 = 0x14
    case sensorFailed6 = 0x15
    case sensorFailedStart = 0x16
    case sensorExpired = 0x18
    case sessionEnded = 0x1A
    
    /// Whether readings are reliable (usable glucose)
    /// Matches xDrip CalibrationState.usableGlucose()
    public var isReliable: Bool {
        switch self {
        case .okay, .needsCalibration:
            return true
        default:
            return false
        }
    }
}

// MARK: - G7 Sensor Info

/// Dexcom G7 sensor information
public struct G7SensorInfo: Sendable, Codable, Equatable {
    /// Sensor serial number (10 characters)
    public let sensorSerial: String
    
    /// Sensor code (4 digits for pairing)
    public let sensorCode: String?
    
    /// Sensor start time
    public let activationDate: Date?
    
    /// Session end time
    public let expirationDate: Date?
    
    public init(
        sensorSerial: String,
        sensorCode: String? = nil,
        activationDate: Date? = nil,
        expirationDate: Date? = nil
    ) {
        self.sensorSerial = sensorSerial
        self.sensorCode = sensorCode
        self.activationDate = activationDate
        self.expirationDate = expirationDate
    }
    
    /// Whether the sensor is expired
    public var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }
    
    /// Remaining sensor life in hours
    public var remainingHours: Double? {
        guard let expiration = expirationDate else { return nil }
        let remaining = expiration.timeIntervalSince(Date()) / 3600.0
        return max(0, remaining)
    }
}
