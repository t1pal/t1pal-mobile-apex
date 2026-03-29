// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeviceInfoService.swift
// BLEKit
//
// BLE Device Information Service (0x180A) reader
// Trace: BLE-DIAG-001
// Reference: https://www.bluetooth.com/specifications/gatt/services/

import Foundation

// MARK: - Device Info Service UUIDs

/// Standard BLE Device Information Service UUIDs
/// Reference: Bluetooth SIG Assigned Numbers
public enum DeviceInfoServiceUUIDs {
    /// Device Information Service (0x180A)
    public static let service = BLEUUID(short: 0x180A)
    
    /// Manufacturer Name String (0x2A29)
    public static let manufacturerName = BLEUUID(short: 0x2A29)
    
    /// Model Number String (0x2A24)
    public static let modelNumber = BLEUUID(short: 0x2A24)
    
    /// Serial Number String (0x2A25)
    public static let serialNumber = BLEUUID(short: 0x2A25)
    
    /// Hardware Revision String (0x2A27)
    public static let hardwareRevision = BLEUUID(short: 0x2A27)
    
    /// Firmware Revision String (0x2A26)
    public static let firmwareRevision = BLEUUID(short: 0x2A26)
    
    /// Software Revision String (0x2A28)
    public static let softwareRevision = BLEUUID(short: 0x2A28)
    
    /// System ID (0x2A23)
    public static let systemID = BLEUUID(short: 0x2A23)
    
    /// All characteristic UUIDs for discovery
    public static let allCharacteristics: [BLEUUID] = [
        manufacturerName,
        modelNumber,
        serialNumber,
        hardwareRevision,
        firmwareRevision,
        softwareRevision,
        systemID
    ]
}

// MARK: - Device Info

/// Parsed device information from BLE Device Information Service
public struct DeviceInfo: Codable, Sendable, Equatable {
    /// Manufacturer name (e.g., "Dexcom", "Abbott")
    public var manufacturerName: String?
    
    /// Model number (e.g., "G6", "Libre 2")
    public var modelNumber: String?
    
    /// Serial number
    public var serialNumber: String?
    
    /// Hardware revision
    public var hardwareRevision: String?
    
    /// Firmware revision
    public var firmwareRevision: String?
    
    /// Software revision
    public var softwareRevision: String?
    
    /// System ID (8 bytes, typically encoded as hex)
    public var systemID: String?
    
    /// Timestamp when info was read
    public var readAt: Date
    
    /// Device identifier (peripheral UUID or address)
    public var deviceIdentifier: String?
    
    public init(
        manufacturerName: String? = nil,
        modelNumber: String? = nil,
        serialNumber: String? = nil,
        hardwareRevision: String? = nil,
        firmwareRevision: String? = nil,
        softwareRevision: String? = nil,
        systemID: String? = nil,
        readAt: Date = Date(),
        deviceIdentifier: String? = nil
    ) {
        self.manufacturerName = manufacturerName
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.hardwareRevision = hardwareRevision
        self.firmwareRevision = firmwareRevision
        self.softwareRevision = softwareRevision
        self.systemID = systemID
        self.readAt = readAt
        self.deviceIdentifier = deviceIdentifier
    }
    
    /// Check if any device info is available
    public var hasInfo: Bool {
        manufacturerName != nil ||
        modelNumber != nil ||
        serialNumber != nil ||
        hardwareRevision != nil ||
        firmwareRevision != nil ||
        softwareRevision != nil ||
        systemID != nil
    }
    
    /// Summary string for display
    public var summary: String {
        var parts: [String] = []
        if let manufacturer = manufacturerName {
            parts.append(manufacturer)
        }
        if let model = modelNumber {
            parts.append(model)
        }
        if let firmware = firmwareRevision {
            parts.append("FW: \(firmware)")
        }
        return parts.isEmpty ? "Unknown Device" : parts.joined(separator: " ")
    }
}

// MARK: - Device Info Parser

/// Parser for Device Information Service characteristic values
public enum DeviceInfoParser {
    
    /// Parse a string characteristic value
    public static func parseString(_ data: Data) -> String? {
        // Device Info strings are UTF-8 encoded, may have null terminator
        var stringData = data
        if let lastByte = stringData.last, lastByte == 0 {
            stringData = stringData.dropLast()
        }
        return String(data: stringData, encoding: .utf8)
    }
    
    /// Parse System ID (8 bytes) to hex string
    public static func parseSystemID(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        return data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    /// Update DeviceInfo from characteristic data
    public static func update(
        deviceInfo: inout DeviceInfo,
        characteristic: BLEUUID,
        data: Data
    ) {
        switch characteristic {
        case DeviceInfoServiceUUIDs.manufacturerName:
            deviceInfo.manufacturerName = parseString(data)
            
        case DeviceInfoServiceUUIDs.modelNumber:
            deviceInfo.modelNumber = parseString(data)
            
        case DeviceInfoServiceUUIDs.serialNumber:
            deviceInfo.serialNumber = parseString(data)
            
        case DeviceInfoServiceUUIDs.hardwareRevision:
            deviceInfo.hardwareRevision = parseString(data)
            
        case DeviceInfoServiceUUIDs.firmwareRevision:
            deviceInfo.firmwareRevision = parseString(data)
            
        case DeviceInfoServiceUUIDs.softwareRevision:
            deviceInfo.softwareRevision = parseString(data)
            
        case DeviceInfoServiceUUIDs.systemID:
            deviceInfo.systemID = parseSystemID(data)
            
        default:
            break
        }
    }
}

// MARK: - Device Info Reader Protocol

/// Protocol for reading Device Information Service from a BLE peripheral
public protocol DeviceInfoReader {
    /// Read device information from a connected peripheral
    /// - Parameter peripheralID: The peripheral identifier
    /// - Returns: Parsed device information
    func readDeviceInfo(from peripheralID: String) async throws -> DeviceInfo
}

// MARK: - Device Info Service Errors

/// Errors from Device Info Service operations
public enum DeviceInfoError: Error, Sendable {
    case notConnected
    case serviceNotFound
    case characteristicNotFound(BLEUUID)
    case readFailed(String)
    case timeout
}

extension DeviceInfoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Device not connected"
        case .serviceNotFound:
            return "Device Information Service (0x180A) not found"
        case .characteristicNotFound(let uuid):
            return "Characteristic \(uuid) not found"
        case .readFailed(let reason):
            return "Read failed: \(reason)"
        case .timeout:
            return "Read operation timed out"
        }
    }
}
