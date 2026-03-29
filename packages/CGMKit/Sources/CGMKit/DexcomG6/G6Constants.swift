// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6Constants.swift
// CGMKit - DexcomG6
//
// Dexcom G6 BLE service and characteristic UUIDs and constants.
// Trace: PRD-008 REQ-BLE-007
// Source documentation added PROD-HARDEN-014 (2026-02-21).
//
// External sources:
// - CGMBLEKit/CGMBLEKit/BluetoothServices.swift:42-55 (UUIDs)
// - CGMBLEKit/CGMBLEKit/Transmitter.swift:483 (keepAlive=25)
// - CGMBLEKit/CGMBLEKit/Transmitter.swift:498 (control timeout=15)
// - xDrip4iOS/.../CGMG6FireflyTransmitter.swift (cross-ref)

import Foundation

/// Dexcom G6 BLE constants
public enum G6Constants {
    
    // MARK: - Advertisement
    
    /// Dexcom advertisement service UUID (0xFEBC)
    public static let advertisementServiceUUID = "FEBC"
    
    // MARK: - Service UUIDs
    
    /// Main Dexcom CGM service
    public static let cgmServiceUUID = "F8083532-849E-531C-C594-30F1F86A4EA5"
    
    // MARK: - Characteristic UUIDs
    // Source: externals/CGMBLEKit/CGMBLEKit/BluetoothServices.swift:42-55
    // Cross-ref: externals/xDrip4iOS/.../CGMG6FireflyTransmitter.swift
    
    /// Communication characteristic (Read/Notify) - receives notifications
    public static let communicationUUID = "F8083533-849E-531C-C594-30F1F86A4EA5"
    
    /// Control characteristic (Write/Indicate) - used for commands and responses
    public static let controlUUID = "F8083534-849E-531C-C594-30F1F86A4EA5"
    
    /// Authentication characteristic (Write/Indicate) - used for auth handshake
    public static let authenticationUUID = "F8083535-849E-531C-C594-30F1F86A4EA5"
    
    /// Backfill characteristic (Read/Write/Notify) - used for historical data
    public static let backfillUUID = "F8083536-849E-531C-C594-30F1F86A4EA5"
    
    // MARK: - Timing Constants
    // Source: CGMBLEKit/Transmitter.swift:483,498
    
    /// Default keep-alive interval in seconds
    /// - External: CGMBLEKit/Transmitter.swift:483 — `KeepAliveTxMessage(time: 25)`
    public static let defaultKeepAliveTime: UInt8 = 25
    
    /// Maximum time to wait for connection (seconds)
    /// - External: CGMBLEKit/Transmitter.swift:498 — `setNotifyValue(..., timeout: 15)`
    public static let connectionTimeout: TimeInterval = 15.0
    
    /// Time between glucose readings (seconds)
    public static let glucoseInterval: TimeInterval = 300.0  // 5 minutes
    
    /// Sensor warmup period (hours)
    public static let sensorWarmupHours: Double = 2.0
    
    /// Sensor session duration (days)
    public static let sensorSessionDays: Double = 10.0
    
    /// Transmitter battery life (days, approximate)
    public static let transmitterLifeDays: Double = 90.0
    
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
    /// When transmitter reports this as sessionStartTime, there is no active sensor session.
    /// Conditions: sensor expired, stopped, failed, or between sensor insertions.
    /// xDrip names this INVALID_TIME; CGMBLEKit had a bug not checking for this.
    public static let invalidSessionTime: UInt32 = 0xFFFFFFFF
    
    /// Maximum reasonable session age in seconds (15 days = 1,296,000 seconds)
    /// Used to detect corrupt session ages from underflow
    public static let maxReasonableSessionAge: UInt32 = 15 * 24 * 60 * 60
}

// MARK: - Sensor State

/// Dexcom sensor state
public enum G6SensorState: UInt8, Sendable, Codable {
    case stopped = 0x01
    case warmup = 0x02
    case okay = 0x04  // First glucose after warmup
    case firstReading = 0x05
    case secondReading = 0x06
    case running = 0x07  // Normal operation
    case failed = 0x08
    case expired = 0x09
    case ended = 0x0A
    case sensorError = 0x0B
    case unknown = 0xFF
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .warmup: return "Warming Up"
        case .okay: return "Starting"
        case .firstReading: return "First Reading"
        case .secondReading: return "Second Reading"
        case .running: return "Running"
        case .failed: return "Failed"
        case .expired: return "Expired"
        case .ended: return "Ended"
        case .sensorError: return "Sensor Error"
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
}

// MARK: - Calibration State

/// Dexcom G6 calibration/algorithm state
/// Enhanced to match Loop CGMBLEKit CalibrationState
/// Trace: G6-DIRECT-030, G6-DIRECT-013
public enum G6CalibrationState: UInt8, Sendable, Codable {
    case stopped = 0x01
    case warmup = 0x02
    // 0x03 undocumented
    case needsFirstCalibration = 0x04
    case needsSecondCalibration = 0x05
    case okay = 0x06
    case needsCalibration = 0x07
    case calibrationError1 = 0x08
    case calibrationError2 = 0x09
    case calibrationLinearityError = 0x0A
    case sensorFailed = 0x0B
    case sensorFailedDays = 0x0C
    case calibrationError3 = 0x0D
    case needsCalibration14 = 0x0E
    case sessionFailure1 = 0x0F
    case sessionFailure2 = 0x10
    case sessionFailure3 = 0x11
    case questionMarks = 0x12
    case unknown = 0xFF
    
    /// Initialize from raw byte, mapping unknown values to .unknown
    public init(fromByte byte: UInt8) {
        self = G6CalibrationState(rawValue: byte) ?? .unknown
    }
    
    /// Whether calibration is needed
    public var needsCalibration: Bool {
        switch self {
        case .needsFirstCalibration, .needsSecondCalibration, .needsCalibration, .needsCalibration14:
            return true
        default:
            return false
        }
    }
    
    /// Whether glucose readings in this state are reliable for dosing
    public var hasReliableGlucose: Bool {
        switch self {
        case .okay, .needsCalibration, .needsCalibration14:
            return true
        default:
            return false
        }
    }
    
    /// Whether readings are valid (alias for hasReliableGlucose)
    public var isValid: Bool {
        hasReliableGlucose
    }
    
    /// Whether sensor has failed
    public var hasFailed: Bool {
        switch self {
        case .sensorFailed, .sensorFailedDays, .sessionFailure1, .sessionFailure2, .sessionFailure3:
            return true
        default:
            return false
        }
    }
    
    /// Whether sensor is warming up
    public var isWarmingUp: Bool {
        self == .warmup
    }
}
