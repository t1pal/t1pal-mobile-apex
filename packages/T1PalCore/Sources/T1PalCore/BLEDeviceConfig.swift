// SPDX-License-Identifier: AGPL-3.0-or-later
// T1PalCore - BLEDeviceConfig
// Configuration for BLE-connected CGM and pump devices
// Trace: PRD-021, BLE-CTX-001, BLE-CTX-002, CODE-QUALITY-007

import Foundation

// MARK: - Backward Compatibility

/// Deprecated typealias - use BLECGMType instead
/// Trace: CODE-QUALITY-007 - renamed to clarify BLE-specific scope
@available(*, deprecated, renamed: "BLECGMType", message: "Use BLECGMType to distinguish from CGMKit.CGMType")
public typealias CGMType = BLECGMType

// MARK: - BLE CGM Device Type

/// Supported CGM device types for BLE connection
///
/// - Important: This enum is **non-frozen** and may gain new cases in future versions.
///   Switch statements should either:
///   1. Handle all cases exhaustively (recommended for core logic), or
///   2. Use `@unknown default` to future-proof against new cases
///
/// - Note: This is the BLE-specific CGM type for direct device connections.
///   See also `CGMKit.CGMType` which includes additional source types
///   (Share, Nightscout, HealthKit, simulation, etc.).
///
/// Trace: PRD-021, BLE-CTX-001, CODE-QUALITY-007
public enum BLECGMType: String, Codable, Sendable, CaseIterable, Hashable {
    /// Dexcom G6 transmitter
    case dexcomG6 = "dexcom_g6"
    
    /// Dexcom G7 transmitter
    case dexcomG7 = "dexcom_g7"
    
    /// Dexcom ONE+
    case dexcomONEPlus = "dexcom_one_plus"
    
    /// Abbott Libre 2
    case libre2 = "libre_2"
    
    /// Abbott Libre 3
    case libre3 = "libre_3"
    
    /// MiaoMiao transmitter (for Libre sensors)
    case miaomiao = "miaomiao"
    
    /// Bubble transmitter (for Libre sensors)
    case bubble = "bubble"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .dexcomG6: return "Dexcom G6"
        case .dexcomG7: return "Dexcom G7"
        case .dexcomONEPlus: return "Dexcom ONE+"
        case .libre2: return "Libre 2"
        case .libre3: return "Libre 3"
        case .miaomiao: return "MiaoMiao"
        case .bubble: return "Bubble"
        }
    }
    
    /// Whether this device requires a transmitter ID
    public var requiresTransmitterId: Bool {
        switch self {
        case .dexcomG6, .dexcomG7, .dexcomONEPlus:
            return true
        case .libre2, .libre3, .miaomiao, .bubble:
            return false
        }
    }
    
    /// Whether this device requires a sensor code
    public var requiresSensorCode: Bool {
        switch self {
        case .dexcomG6:
            return true  // Optional but recommended
        case .dexcomG7, .dexcomONEPlus:
            return false  // Auto-pairing
        case .libre2, .libre3, .miaomiao, .bubble:
            return false
        }
    }
    
    /// SF Symbol icon for the device
    public var iconName: String {
        switch self {
        case .dexcomG6, .dexcomG7, .dexcomONEPlus:
            return "waveform.path.ecg"
        case .libre2, .libre3:
            return "sensor.tag.radiowaves.forward"
        case .miaomiao, .bubble:
            return "antenna.radiowaves.left.and.right"
        }
    }
    
    /// SF Symbol for SwiftUI (alias for iconName)
    public var systemImage: String { iconName }
    
    /// Device manufacturer name
    public var manufacturer: String {
        switch self {
        case .dexcomG6, .dexcomG7, .dexcomONEPlus:
            return "Dexcom"
        case .libre2, .libre3:
            return "Abbott"
        case .miaomiao:
            return "MiaoMiao"
        case .bubble:
            return "Bubble"
        }
    }
}

// MARK: - BLE Device Config

/// BLE connection mode for CGM devices
/// Maps to CGMKit.CGMConnectionMode at runtime
/// Trace: G6-APP-002
public enum BLEConnectionMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// T1Pal connects directly to sensor via BLE (exclusive)
    case direct
    /// T1Pal connects and subscribes while vendor app authenticates (Loop pattern)
    case coexistence
    /// T1Pal observes BLE advertisements only (no connection)
    case passiveBLE
    /// Vendor app controls sensor; T1Pal reads from HealthKit only
    case healthKitObserver
    /// Read from cloud service (Dexcom Share, LibreLinkUp)
    case cloudFollower
    /// Read from Nightscout
    case nightscoutFollower
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .direct: return "Direct BLE"
        case .coexistence: return "Via Dexcom App"
        case .passiveBLE: return "Passive BLE"
        case .healthKitObserver: return "HealthKit"
        case .cloudFollower: return "Cloud"
        case .nightscoutFollower: return "Nightscout"
        }
    }
}

/// Configuration for a BLE-connected CGM device
/// Part of DataContext for .ble source type
public struct BLEDeviceConfig: Codable, Sendable, Equatable, Hashable {
    /// The type of CGM device
    public let cgmType: BLECGMType
    
    /// Transmitter ID (required for Dexcom)
    /// Format: 6 alphanumeric characters (e.g., "8G1234")
    public let transmitterId: String?
    
    /// Sensor code (for Dexcom G6 calibration-free mode)
    /// Format: 4 digits (e.g., "1234")
    public let sensorCode: String?
    
    /// Connection mode - how to connect to the device
    /// Trace: G6-APP-002
    public let connectionMode: BLEConnectionMode
    
    /// Optional user-defined name for this config
    public let displayName: String?
    
    /// Timestamp when this config was created
    public let configuredAt: Date
    
    /// App Level Key for G6+/Firefly authentication
    /// Trace: CGM-066e
    public let appLevelKey: Data?
    
    /// Whether to generate a new App Level Key on next connection
    /// Trace: CGM-066e
    public let generateNewAppLevelKey: Bool
    
    public init(
        cgmType: BLECGMType,
        transmitterId: String? = nil,
        sensorCode: String? = nil,
        connectionMode: BLEConnectionMode = .direct,
        displayName: String? = nil,
        configuredAt: Date = Date(),
        appLevelKey: Data? = nil,
        generateNewAppLevelKey: Bool = false
    ) {
        self.cgmType = cgmType
        self.transmitterId = transmitterId
        self.sensorCode = sensorCode
        self.connectionMode = connectionMode
        self.displayName = displayName
        self.configuredAt = configuredAt
        self.appLevelKey = appLevelKey
        self.generateNewAppLevelKey = generateNewAppLevelKey
    }
    
    /// Validation: Check if required fields are present
    public var isValid: Bool {
        if cgmType.requiresTransmitterId && (transmitterId?.isEmpty ?? true) {
            return false
        }
        return true
    }
    
    /// Human-readable description
    public var description: String {
        if let name = displayName {
            return name
        }
        if let txId = transmitterId {
            return "\(cgmType.displayName) (\(txId))"
        }
        return cgmType.displayName
    }
}

// MARK: - Factory Methods

extension BLEDeviceConfig {
    /// Create a Dexcom G6 configuration
    public static func dexcomG6(transmitterId: String, sensorCode: String? = nil) -> BLEDeviceConfig {
        BLEDeviceConfig(
            cgmType: .dexcomG6,
            transmitterId: transmitterId,
            sensorCode: sensorCode
        )
    }
    
    /// Create a Dexcom G7 configuration
    public static func dexcomG7(transmitterId: String) -> BLEDeviceConfig {
        BLEDeviceConfig(
            cgmType: .dexcomG7,
            transmitterId: transmitterId
        )
    }
    
    /// Create a Libre 2 configuration
    public static func libre2() -> BLEDeviceConfig {
        BLEDeviceConfig(cgmType: .libre2)
    }
    
    /// Create a Libre 3 configuration
    public static func libre3() -> BLEDeviceConfig {
        BLEDeviceConfig(cgmType: .libre3)
    }
    
    /// Create a MiaoMiao configuration
    public static func miaomiao() -> BLEDeviceConfig {
        BLEDeviceConfig(cgmType: .miaomiao)
    }
}

// MARK: - Pump Device Type (BLE-CTX-002)

/// Supported pump device types for BLE connection
public enum PumpDeviceType: String, Codable, Sendable, CaseIterable, Hashable {
    /// Medtronic 5xx/7xx series (via RileyLink)
    case medtronic = "medtronic"
    
    /// Omnipod Eros (via RileyLink)
    case omnipodEros = "omnipod_eros"
    
    /// Omnipod DASH (direct BLE)
    case omnipodDash = "omnipod_dash"
    
    /// Dana-i / Dana RS
    case dana = "dana"
    
    /// Tandem t:slim X2 (direct BLE)
    case tandemX2 = "tandem_x2"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .medtronic: return "Medtronic"
        case .omnipodEros: return "Omnipod Eros"
        case .omnipodDash: return "Omnipod DASH"
        case .dana: return "Dana-i/RS"
        case .tandemX2: return "Tandem t:slim X2"
        }
    }
    
    /// Whether this pump requires a bridge device (RileyLink/OrangeLink)
    public var requiresBridge: Bool {
        switch self {
        case .medtronic, .omnipodEros:
            return true
        case .omnipodDash, .dana, .tandemX2:
            return false
        }
    }
    
    /// SF Symbol icon for the pump
    public var iconName: String {
        switch self {
        case .medtronic:
            return "cable.connector"
        case .omnipodEros, .omnipodDash:
            return "circle.hexagongrid"
        case .dana:
            return "ivfluid.bag"
        case .tandemX2:
            return "cross.vial"
        }
    }
    
    /// SF Symbol for SwiftUI (alias for iconName)
    public var systemImage: String { iconName }
    
    /// Device manufacturer name
    public var manufacturer: String {
        switch self {
        case .medtronic: return "Medtronic"
        case .omnipodEros, .omnipodDash: return "Insulet"
        case .dana: return "Dana/SOOIL"
        case .tandemX2: return "Tandem Diabetes Care"
        }
    }
}

/// Type of RileyLink-compatible bridge device
public enum BridgeDeviceType: String, Codable, Sendable, CaseIterable, Hashable {
    case rileyLink = "rileylink"
    case orangeLink = "orangelink"
    case emaLink = "emalink"
    
    public var displayName: String {
        switch self {
        case .rileyLink: return "RileyLink"
        case .orangeLink: return "OrangeLink"
        case .emaLink: return "EmaLink"
        }
    }
}

// MARK: - Pump Device Config (BLE-CTX-002)

/// Configuration for a BLE-connected insulin pump
public struct PumpDeviceConfig: Codable, Sendable, Equatable, Hashable {
    /// The type of pump
    public let pumpType: PumpDeviceType
    
    /// Pump serial number (for Medtronic)
    public let pumpSerial: String?
    
    /// Bridge device type (for RileyLink-based pumps)
    public let bridgeType: BridgeDeviceType?
    
    /// Bridge device identifier
    public let bridgeId: String?
    
    /// Pod lot number (for Omnipod)
    public let podLotNumber: String?
    
    /// Optional user-defined name
    public let displayName: String?
    
    /// Timestamp when configured
    public let configuredAt: Date
    
    public init(
        pumpType: PumpDeviceType,
        pumpSerial: String? = nil,
        bridgeType: BridgeDeviceType? = nil,
        bridgeId: String? = nil,
        podLotNumber: String? = nil,
        displayName: String? = nil,
        configuredAt: Date = Date()
    ) {
        self.pumpType = pumpType
        self.pumpSerial = pumpSerial
        self.bridgeType = bridgeType
        self.bridgeId = bridgeId
        self.podLotNumber = podLotNumber
        self.displayName = displayName
        self.configuredAt = configuredAt
    }
    
    /// Validation: Check if required fields are present
    public var isValid: Bool {
        switch pumpType {
        case .medtronic:
            return !(pumpSerial?.isEmpty ?? true) && bridgeType != nil
        case .omnipodEros:
            return bridgeType != nil
        case .omnipodDash, .dana, .tandemX2:
            return true
        }
    }
    
    /// Human-readable description
    public var description: String {
        if let name = displayName {
            return name
        }
        if let serial = pumpSerial {
            return "\(pumpType.displayName) (\(serial))"
        }
        return pumpType.displayName
    }
}

// MARK: - Medtronic Pump Region (PUMP-002)

/// Region for Medtronic pump RF frequency selection
public enum MedtronicPumpRegion: String, Codable, Sendable, CaseIterable {
    /// North America (916.5 MHz)
    case northAmerica = "NA"
    /// World Wide (868.35 MHz)
    case worldWide = "WW"
    
    public var displayName: String {
        switch self {
        case .northAmerica: return "North America"
        case .worldWide: return "World Wide (Europe/Asia)"
        }
    }
    
    public var frequency: String {
        switch self {
        case .northAmerica: return "916.5 MHz"
        case .worldWide: return "868.35 MHz"
        }
    }
}

// MARK: - Pump Serial Validation (PUMP-001, PUMP-002)

extension PumpDeviceConfig {
    /// PUMP-001: Validate Medtronic pump serial format
    /// Medtronic serials are 6 alphanumeric characters
    public static func isValidMedtronicSerial(_ serial: String) -> Bool {
        let trimmed = serial.trimmingCharacters(in: .whitespaces).uppercased()
        // Must be exactly 6 alphanumeric characters
        guard trimmed.count == 6 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber }
    }
    
    /// PUMP-002: Detect region from Medtronic pump serial
    /// NA pumps typically have serial numbers starting with certain prefixes
    /// WW pumps use different RF frequency and often have different prefixes
    public static func detectRegion(from serial: String) -> MedtronicPumpRegion? {
        let trimmed = serial.trimmingCharacters(in: .whitespaces).uppercased()
        guard isValidMedtronicSerial(trimmed) else { return nil }
        
        // Region detection based on serial prefix patterns:
        // - NA pumps: Often start with letters A-H, N, or numbers
        // - WW pumps: Often start with letters J-M, P-Z
        // This is a heuristic - user should confirm
        let firstChar = trimmed.first!
        
        switch firstChar {
        case "A"..."H", "N", "0"..."9":
            return .northAmerica
        case "J"..."M", "P"..."Z":
            return .worldWide
        default:
            // Default to NA if unclear, user can override
            return .northAmerica
        }
    }
    
    /// PUMP-001: Validation error for serial
    public static func serialValidationError(_ serial: String) -> String? {
        let trimmed = serial.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Serial number is required"
        }
        if trimmed.count < 6 {
            return "Serial must be 6 characters (\(trimmed.count)/6)"
        }
        if trimmed.count > 6 {
            return "Serial must be 6 characters (too long)"
        }
        if !trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return "Serial must be alphanumeric only"
        }
        return nil
    }
}

// MARK: - Factory Methods

extension PumpDeviceConfig {
    /// Create a Medtronic pump configuration
    public static func medtronic(serial: String, bridge: BridgeDeviceType, bridgeId: String? = nil) -> PumpDeviceConfig {
        PumpDeviceConfig(
            pumpType: .medtronic,
            pumpSerial: serial,
            bridgeType: bridge,
            bridgeId: bridgeId
        )
    }
    
    /// Create an Omnipod Eros configuration
    public static func omnipodEros(bridge: BridgeDeviceType, bridgeId: String? = nil) -> PumpDeviceConfig {
        PumpDeviceConfig(
            pumpType: .omnipodEros,
            bridgeType: bridge,
            bridgeId: bridgeId
        )
    }
    
    /// Create an Omnipod DASH configuration
    public static func omnipodDash() -> PumpDeviceConfig {
        PumpDeviceConfig(pumpType: .omnipodDash)
    }
    
    /// Create a Dana pump configuration
    public static func dana() -> PumpDeviceConfig {
        PumpDeviceConfig(pumpType: .dana)
    }
    
    /// Create a Tandem t:slim X2 pump configuration
    public static func tandemX2() -> PumpDeviceConfig {
        PumpDeviceConfig(pumpType: .tandemX2)
    }
}
