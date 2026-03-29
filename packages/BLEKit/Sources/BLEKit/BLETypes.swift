// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLETypes.swift
// BLEKit
//
// Core BLE types for cross-platform abstraction.
// Trace: PRD-008 REQ-BLE-003

import Foundation
import T1PalCore

// MARK: - BLEUUID

/// Platform-agnostic Bluetooth UUID
public struct BLEUUID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The underlying UUID bytes
    public let data: Data
    
    /// Create from 16-bit short UUID
    public init(short: UInt16) {
        // Bluetooth Base UUID: 00000000-0000-1000-8000-00805F9B34FB
        var bytes = Data([
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00,
            0x10, 0x00,
            0x80, 0x00,
            0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB
        ])
        bytes[2] = UInt8((short >> 8) & 0xFF)
        bytes[3] = UInt8(short & 0xFF)
        self.data = bytes
    }
    
    /// Create from 128-bit UUID string
    public init?(string: String) {
        let cleaned = string.replacingOccurrences(of: "-", with: "").uppercased()
        guard cleaned.count == 32 else { return nil }
        
        var bytes = Data()
        var index = cleaned.startIndex
        for _ in 0..<16 {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.data = bytes
    }
    
    /// Create from Foundation UUID
    public init(_ uuid: UUID) {
        var bytes = [UInt8](repeating: 0, count: 16)
        let uuidValue = uuid.uuid
        bytes[0] = uuidValue.0
        bytes[1] = uuidValue.1
        bytes[2] = uuidValue.2
        bytes[3] = uuidValue.3
        bytes[4] = uuidValue.4
        bytes[5] = uuidValue.5
        bytes[6] = uuidValue.6
        bytes[7] = uuidValue.7
        bytes[8] = uuidValue.8
        bytes[9] = uuidValue.9
        bytes[10] = uuidValue.10
        bytes[11] = uuidValue.11
        bytes[12] = uuidValue.12
        bytes[13] = uuidValue.13
        bytes[14] = uuidValue.14
        bytes[15] = uuidValue.15
        self.data = Data(bytes)
    }
    
    /// Create from raw data
    public init(data: Data) {
        self.data = data
    }
    
    /// 16-bit short UUID if applicable
    public var shortUUID: UInt16? {
        guard data.count == 16 else { return nil }
        // Check if matches Bluetooth Base UUID pattern
        let basePrefix = Data([0x00, 0x00])
        let baseSuffix = Data([0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB])
        
        guard data.prefix(2) == basePrefix,
              data.suffix(12) == baseSuffix else { return nil }
        
        return UInt16(data[2]) << 8 | UInt16(data[3])
    }
    
    /// String representation
    public var description: String {
        if let short = shortUUID {
            return String(format: "%04X", short)
        }
        
        let hex = data.map { String(format: "%02X", $0) }.joined()
        guard hex.count == 32 else { return hex }
        
        // Format as standard UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let i1 = hex.index(hex.startIndex, offsetBy: 8)
        let i2 = hex.index(i1, offsetBy: 4)
        let i3 = hex.index(i2, offsetBy: 4)
        let i4 = hex.index(i3, offsetBy: 4)
        
        return "\(hex[..<i1])-\(hex[i1..<i2])-\(hex[i2..<i3])-\(hex[i3..<i4])-\(hex[i4...])"
    }
    
    // MARK: - Dexcom UUIDs
    // Source: EXT-G6-001..009, EXT-G7-001..008 audits
    // G6 and G7 share the same service UUID but differ in characteristic assignments
    // G7-COEX-FIX-006: G6 and G7 BOTH use FEBC for advertisements (verified Loop/G7SensorKit)
    
    public static let dexcomAdvertisement = BLEUUID(short: 0xFEBC)
    public static let dexcomG7Advertisement = BLEUUID(short: 0xFEBC)  // Same as G6, NOT 0xFE59
    public static let dexcomService = BLEUUID(string: "F8083532-849E-531C-C594-30F1F86A4EA5")!
    
    // G6 characteristics (verified against Loop/CGMBLEKit)
    public static let dexcomCommunication = BLEUUID(string: "F8083533-849E-531C-C594-30F1F86A4EA5")!
    public static let dexcomControl = BLEUUID(string: "F8083534-849E-531C-C594-30F1F86A4EA5")!
    public static let dexcomAuthentication = BLEUUID(string: "F8083535-849E-531C-C594-30F1F86A4EA5")!
    public static let dexcomBackfill = BLEUUID(string: "F8083536-849E-531C-C594-30F1F86A4EA5")!
    
    // G7 uses same authentication characteristic as G6 (3535)
    public static let dexcomG7Authentication = BLEUUID(string: "F8083535-849E-531C-C594-30F1F86A4EA5")!
    public static let dexcomG7Backfill = BLEUUID(string: "F8083536-849E-531C-C594-30F1F86A4EA5")!
    
    // MARK: - FreeStyle Libre UUIDs (CGM-019)
    // Trace: PRD-004 REQ-CGM-002
    
    /// Libre 2/3 Direct BLE Service
    public static let libre2Service = BLEUUID(short: 0xFDE3)
    /// Libre 2/3 Write Characteristic (commands)
    public static let libre2WriteCharacteristic = BLEUUID(short: 0xF001)
    /// Libre 2/3 Notify Characteristic (glucose data)
    public static let libre2NotifyCharacteristic = BLEUUID(short: 0xF002)
    
    // MARK: - Libre 3 UUIDs (LIBRE-IMPL-002)
    // Source: externals/Juggluco/Common/src/main/java/tk/glucodata/SuperGattCallback.java
    // LIBRE3-002: Updated UUIDs from Juggluco implementation 2026-02-25
    
    /// Libre 3 data service UUID (primary)
    public static let libre3Service = BLEUUID(string: "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 security service UUID (authentication)
    public static let libre3SecurityService = BLEUUID(string: "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 glucose data characteristic (real-time readings)
    public static let libre3GlucoseData = BLEUUID(string: "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 historic data characteristic (backfill)
    public static let libre3HistoricData = BLEUUID(string: "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 patch control characteristic (commands)
    public static let libre3Control = BLEUUID(string: "08981338-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 patch status characteristic (state)
    public static let libre3PatchStatus = BLEUUID(string: "08981482-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 certificate data characteristic (ECDH)
    public static let libre3CertData = BLEUUID(string: "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4")!
    /// Libre 3 challenge data characteristic (auth)
    public static let libre3Auth = BLEUUID(string: "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4")!
    
    // MARK: - Third-Party Transmitter UUIDs (Miaomiao, Bubble)
    // Nordic UART Service for Libre 1/2 transmitters
    
    /// Nordic UART Service (Miaomiao, Bubble, Tomato)
    public static let nordicUARTService = BLEUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!
    /// Nordic UART TX Characteristic (write commands)
    public static let nordicUARTTX = BLEUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")!
    /// Nordic UART RX Characteristic (receive notifications)
    public static let nordicUARTRX = BLEUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")!
    
    // MARK: - RileyLink/OrangeLink/EmaLink UUIDs
    // Trace: PRD-005 REQ-AID-001, RL-001
    // Source: ps2/rileylink_ios RileyLinkBLEKit/PeripheralManager+RileyLink.swift
    
    /// RileyLink main service (BLE-to-RF bridge)
    public static let rileyLinkService = BLEUUID(string: "0235733B-99C5-4197-B856-69219C2A3845")!
    /// RileyLink data characteristic (RF packet exchange)
    public static let rileyLinkData = BLEUUID(string: "C842E849-5028-42E2-867C-016ADADA9155")!
    /// RileyLink response count characteristic
    public static let rileyLinkResponseCount = BLEUUID(string: "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A")!
    /// RileyLink custom name characteristic
    public static let rileyLinkCustomName = BLEUUID(string: "D93B2AF0-1E28-11E4-8C21-0800200C9A66")!
    /// RileyLink timer tick characteristic
    public static let rileyLinkTimerTick = BLEUUID(string: "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E")!
    /// RileyLink firmware version characteristic
    public static let rileyLinkFirmwareVersion = BLEUUID(string: "30D99DC9-7C91-4295-A051-0A104D238CF2")!
    /// RileyLink LED mode characteristic
    public static let rileyLinkLEDMode = BLEUUID(string: "C6D84241-F1A7-4F9C-A25F-FCE16732F14E")!
    
    /// OrangeLink extended service (Nordic UART compatible)
    /// Note: Same as nordicUARTService but OrangeLink-specific characteristics
    public static let orangeLinkService = BLEUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!
    /// OrangeLink RX characteristic (receive from device)
    public static let orangeLinkRX = BLEUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")!
    /// OrangeLink TX characteristic (send to device)
    public static let orangeLinkTX = BLEUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")!
    
    /// Battery service (standard BLE)
    public static let batteryService = BLEUUID(short: 0x180F)
    /// Battery level characteristic
    public static let batteryLevel = BLEUUID(short: 0x2A19)
    
    /// Secure DFU service (firmware update)
    public static let secureDFUService = BLEUUID(short: 0xFE59)
    /// Secure DFU control characteristic
    public static let secureDFUControl = BLEUUID(string: "8EC90001-F315-4F60-9FB8-838830DAEA50")!
}

// MARK: - BLE States

/// Central manager state
public enum BLECentralState: String, Sendable, Codable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

/// Peripheral connection state
public enum BLEPeripheralState: String, Sendable, Codable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// MARK: - Scan Result

/// Result from BLE scan
public struct BLEScanResult: Sendable {
    /// Peripheral info for connection
    public let peripheral: BLEPeripheralInfo
    
    /// Signal strength
    public let rssi: Int
    
    /// Advertisement data
    public let advertisement: BLEAdvertisement
    
    public init(peripheral: BLEPeripheralInfo, rssi: Int, advertisement: BLEAdvertisement) {
        self.peripheral = peripheral
        self.rssi = rssi
        self.advertisement = advertisement
    }
}

/// Peripheral identifier for connection
public struct BLEPeripheralInfo: Sendable, Hashable {
    /// Unique identifier
    public let identifier: BLEUUID
    
    /// Local name (may be nil)
    public let name: String?
    
    public init(identifier: BLEUUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
}

/// Advertisement data from scan
public struct BLEAdvertisement: Sendable {
    /// Local name
    public let localName: String?
    
    /// Advertised service UUIDs
    public let serviceUUIDs: [BLEUUID]
    
    /// Manufacturer data
    public let manufacturerData: Data?
    
    /// Is connectable
    public let isConnectable: Bool
    
    public init(
        localName: String? = nil,
        serviceUUIDs: [BLEUUID] = [],
        manufacturerData: Data? = nil,
        isConnectable: Bool = true
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
        self.manufacturerData = manufacturerData
        self.isConnectable = isConnectable
    }
}

// MARK: - Service and Characteristic

/// Discovered BLE service
public struct BLEService: Sendable, Hashable {
    /// Service UUID
    public let uuid: BLEUUID
    
    /// Whether this is a primary service
    public let isPrimary: Bool
    
    public init(uuid: BLEUUID, isPrimary: Bool = true) {
        self.uuid = uuid
        self.isPrimary = isPrimary
    }
}

/// Characteristic properties
public struct BLECharacteristicProperties: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let read = BLECharacteristicProperties(rawValue: 1 << 0)
    public static let writeWithoutResponse = BLECharacteristicProperties(rawValue: 1 << 1)
    public static let write = BLECharacteristicProperties(rawValue: 1 << 2)
    public static let notify = BLECharacteristicProperties(rawValue: 1 << 3)
    public static let indicate = BLECharacteristicProperties(rawValue: 1 << 4)
}

/// Discovered BLE characteristic
public struct BLECharacteristic: Sendable, Hashable {
    /// Characteristic UUID
    public let uuid: BLEUUID
    
    /// Properties
    public let properties: BLECharacteristicProperties
    
    /// Parent service UUID
    public let serviceUUID: BLEUUID
    
    public init(uuid: BLEUUID, properties: BLECharacteristicProperties, serviceUUID: BLEUUID) {
        self.uuid = uuid
        self.properties = properties
        self.serviceUUID = serviceUUID
    }
}

/// Write type
public enum BLEWriteType: Sendable {
    case withResponse
    case withoutResponse
}

// MARK: - Connection Events (G7-PASSIVE-001)

/// Connection event type for registerForConnectionEvents API
/// Maps to CBConnectionEvent on Darwin platforms
/// Trace: G7-PASSIVE-001, G7-PASSIVE-003
public enum BLEConnectionEventType: Int, Sendable {
    /// Peer app disconnected from the peripheral
    case peerDisconnected = 0
    /// Peer app connected to the peripheral
    case peerConnected = 1
}

/// Connection event from registerForConnectionEvents
/// Enables coexistence mode by notifying when other apps (e.g., Dexcom) connect
/// Trace: G7-PASSIVE-001, G7-PASSIVE-003
public struct BLEConnectionEvent: Sendable {
    /// Type of connection event
    public let eventType: BLEConnectionEventType
    /// Peripheral involved in the event
    public let peripheral: BLEPeripheralInfo
    
    public init(eventType: BLEConnectionEventType, peripheral: BLEPeripheralInfo) {
        self.eventType = eventType
        self.peripheral = peripheral
    }
}

// MARK: - Errors

/// BLE operation errors
public enum BLEError: Error, Sendable, LocalizedError {
    case notPoweredOn
    case unauthorized
    case unsupported
    case notSupported(String)  // Platform/feature not available
    case scanFailed(String)
    case connectionFailed(String)
    case connectionTimeout
    case disconnected
    case serviceNotFound(BLEUUID)
    case characteristicNotFound(BLEUUID)
    case readFailed(String)
    case writeFailed(String)
    case notificationFailed(String)
    case invalidState(String)
    
    public var errorDescription: String? {
        switch self {
        case .notPoweredOn:
            return "Bluetooth is not powered on"
        case .unauthorized:
            return "Bluetooth access is not authorized"
        case .unsupported:
            return "Bluetooth is not supported on this device"
        case .notSupported(let feature):
            return "Feature not supported: \(feature)"
        case .scanFailed(let reason):
            return "Scan failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionTimeout:
            return "Connection timed out"
        case .disconnected:
            return "Device disconnected"
        case .serviceNotFound(let uuid):
            return "Service not found: \(uuid.description)"
        case .characteristicNotFound(let uuid):
            return "Characteristic not found: \(uuid.description)"
        case .readFailed(let reason):
            return "Read failed: \(reason)"
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        case .notificationFailed(let reason):
            return "Notification failed: \(reason)"
        case .invalidState(let reason):
            return "Invalid state: \(reason)"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance (PROD-HARDEN-033)

extension BLEError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .ble }
    
    public var code: String {
        switch self {
        case .notPoweredOn: return "NOT_POWERED_ON"
        case .unauthorized: return "UNAUTHORIZED"
        case .unsupported: return "UNSUPPORTED"
        case .notSupported: return "NOT_SUPPORTED"
        case .scanFailed: return "SCAN_FAILED"
        case .connectionFailed: return "CONNECTION_FAILED"
        case .connectionTimeout: return "CONNECTION_TIMEOUT"
        case .disconnected: return "DISCONNECTED"
        case .serviceNotFound: return "SERVICE_NOT_FOUND"
        case .characteristicNotFound: return "CHAR_NOT_FOUND"
        case .readFailed: return "READ_FAILED"
        case .writeFailed: return "WRITE_FAILED"
        case .notificationFailed: return "NOTIFICATION_FAILED"
        case .invalidState: return "INVALID_STATE"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .notPoweredOn, .unauthorized, .unsupported:
            return .warning
        case .connectionTimeout, .disconnected:
            return .error
        default:
            return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .notPoweredOn:
            return .checkDevice
        case .unauthorized:
            return .none  // User must enable in Settings
        case .connectionTimeout, .disconnected, .connectionFailed:
            return .reconnect
        default:
            return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "BLE error"
    }
}
