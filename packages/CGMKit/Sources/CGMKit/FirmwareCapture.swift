// SPDX-License-Identifier: AGPL-3.0-or-later
//
// FirmwareCapture.swift
// CGMKit
//
// Unified firmware version capture from CGM protocol messages.
// Trace: BLE-DIAG-002
// Integrates with BLEKit.DeviceInfo from BLE-DIAG-001

import Foundation
import BLEKit

// MARK: - CGM Firmware Info

/// Firmware and version information captured from CGM protocol messages
public struct CGMFirmwareInfo: Codable, Sendable, Equatable {
    /// Device type (G6, G7, Libre2, etc.)
    public var deviceType: CGMDeviceType
    
    /// Firmware version string
    public var firmwareVersion: String
    
    /// Bluetooth/radio firmware version (if available)
    public var bluetoothVersion: String?
    
    /// Hardware revision (if available)
    public var hardwareRevision: String?
    
    /// ASIC version (for G6 transmitters)
    public var asicVersion: String?
    
    /// Sensor serial number (for G7)
    public var sensorSerial: String?
    
    /// Transmitter ID
    public var transmitterID: String?
    
    /// Timestamp when captured
    public var capturedAt: Date
    
    /// Source of the firmware info
    public var source: FirmwareSource
    
    public init(
        deviceType: CGMDeviceType,
        firmwareVersion: String,
        bluetoothVersion: String? = nil,
        hardwareRevision: String? = nil,
        asicVersion: String? = nil,
        sensorSerial: String? = nil,
        transmitterID: String? = nil,
        capturedAt: Date = Date(),
        source: FirmwareSource = .protocolMessage
    ) {
        self.deviceType = deviceType
        self.firmwareVersion = firmwareVersion
        self.bluetoothVersion = bluetoothVersion
        self.hardwareRevision = hardwareRevision
        self.asicVersion = asicVersion
        self.sensorSerial = sensorSerial
        self.transmitterID = transmitterID
        self.capturedAt = capturedAt
        self.source = source
    }
    
    /// Summary for display
    public var summary: String {
        var parts = ["\(deviceType.displayName): \(firmwareVersion)"]
        if let bt = bluetoothVersion { parts.append("BT:\(bt)") }
        if let hw = hardwareRevision { parts.append("HW:\(hw)") }
        return parts.joined(separator: " ")
    }
    
    /// Convert to BLEKit DeviceInfo for unified storage
    public func toDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            manufacturerName: deviceType.manufacturer,
            modelNumber: deviceType.displayName,
            serialNumber: sensorSerial ?? transmitterID,
            hardwareRevision: hardwareRevision,
            firmwareRevision: firmwareVersion,
            softwareRevision: bluetoothVersion,
            readAt: capturedAt
        )
    }
}

// MARK: - Firmware Source

/// Where the firmware info was captured from
public enum FirmwareSource: String, Codable, Sendable {
    /// From BLE protocol message (0x20/0x21 opcodes)
    case protocolMessage
    
    /// From BLE Device Info Service (0x180A)
    case deviceInfoService
    
    /// From advertisement data
    case advertisement
    
    /// Manually entered or from API
    case manual
}

// MARK: - G6 Firmware Capture

/// Capture firmware from Dexcom G6 protocol messages
public enum G6FirmwareCapture {
    
    /// Create CGMFirmwareInfo from G6 FirmwareVersionRxMessage
    public static func capture(
        from message: FirmwareVersionRxMessage,
        transmitterID: String? = nil
    ) -> CGMFirmwareInfo {
        CGMFirmwareInfo(
            deviceType: .dexcomG6,
            firmwareVersion: message.firmwareVersion,
            bluetoothVersion: message.bluetoothVersion,
            hardwareRevision: message.hardwareRevision,
            asicVersion: message.asicVersion,
            transmitterID: transmitterID,
            source: .protocolMessage
        )
    }
    
    /// Parse raw firmware response data
    public static func capture(
        from data: Data,
        transmitterID: String? = nil
    ) -> CGMFirmwareInfo? {
        guard let message = FirmwareVersionRxMessage(data: data) else {
            return nil
        }
        return capture(from: message, transmitterID: transmitterID)
    }
}

// MARK: - G7 Firmware Capture

/// Capture firmware from Dexcom G7 protocol messages
public enum G7FirmwareCapture {
    
    /// Create CGMFirmwareInfo from G7 SensorInfoRxMessage
    /// Note: G7 uses SensorInfo (0x20/0x21) instead of FirmwareVersion
    public static func capture(
        from message: G7SensorInfoRxMessage
    ) -> CGMFirmwareInfo {
        CGMFirmwareInfo(
            deviceType: .dexcomG7,
            firmwareVersion: "G7", // G7 doesn't report firmware version in SensorInfo
            sensorSerial: message.sensorSerial,
            source: .protocolMessage
        )
    }
    
    /// Parse raw sensor info response data
    public static func capture(from data: Data) -> CGMFirmwareInfo? {
        guard let message = G7SensorInfoRxMessage(data: data) else {
            return nil
        }
        return capture(from: message)
    }
}
