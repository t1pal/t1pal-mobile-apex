// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEPeripheralManager.swift
// BLEKit
//
// Platform-agnostic BLE peripheral manager protocol for advertising and GATT server.
// Trace: PRD-007 REQ-SIM-001, PRD-008 REQ-BLE-002

import Foundation

// MARK: - BLE Peripheral Manager Protocol

/// Platform-agnostic BLE Peripheral Manager API for advertising and GATT server
///
/// Implementations:
/// - `DarwinBLEPeripheralManager` for iOS/macOS (uses CBPeripheralManager)
/// - `LinuxBLEPeripheralManager` for Linux (uses GATT)
/// - `MockBLEPeripheralManager` for testing
public protocol BLEPeripheralManagerProtocol: Sendable {
    /// Current peripheral manager state
    var state: BLEPeripheralManagerState { get async }
    
    /// State change notifications
    var stateUpdates: AsyncStream<BLEPeripheralManagerState> { get }
    
    /// Add a GATT service to the local database
    /// - Parameter service: Service definition with characteristics
    func addService(_ service: BLEMutableService) async throws
    
    /// Remove a service from the local database
    /// - Parameter serviceUUID: UUID of service to remove
    func removeService(_ serviceUUID: BLEUUID) async
    
    /// Remove all services
    func removeAllServices() async
    
    /// Start advertising with specified data
    /// - Parameter advertisement: Advertisement data to broadcast
    func startAdvertising(_ advertisement: BLEAdvertisementData) async throws
    
    /// Stop advertising
    func stopAdvertising() async
    
    /// Whether currently advertising
    var isAdvertising: Bool { get async }
    
    /// Update value for a characteristic and notify subscribed centrals
    /// - Parameters:
    ///   - value: New value data
    ///   - characteristic: Characteristic to update
    ///   - centrals: Specific centrals to notify (nil for all subscribed)
    /// - Returns: Whether the update was queued (false if queue is full)
    func updateValue(_ value: Data, for characteristic: BLEMutableCharacteristic, onSubscribedCentrals centrals: [BLECentralInfo]?) async -> Bool
    
    /// Stream of read requests from centrals
    var readRequests: AsyncStream<BLEATTReadRequest> { get }
    
    /// Stream of write requests from centrals
    var writeRequests: AsyncStream<BLEATTWriteRequest> { get }
    
    /// Stream of subscription changes
    var subscriptionChanges: AsyncStream<BLESubscriptionChange> { get }
    
    /// Respond to a read request
    /// - Parameters:
    ///   - request: The read request to respond to
    ///   - result: Result code
    func respond(to request: BLEATTReadRequest, withResult result: BLEATTError) async
    
    /// Respond to a write request
    /// - Parameters:
    ///   - request: The write request to respond to
    ///   - result: Result code
    func respond(to request: BLEATTWriteRequest, withResult result: BLEATTError) async
}

// MARK: - Peripheral Manager State

/// Peripheral manager state
public enum BLEPeripheralManagerState: String, Sendable, Codable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

// MARK: - Mutable Service/Characteristic (for GATT server)

/// A mutable GATT service for the peripheral role
public struct BLEMutableService: Sendable, Hashable, Identifiable {
    public var id: BLEUUID { uuid }
    
    /// Service UUID
    public let uuid: BLEUUID
    
    /// Whether this is a primary service
    public let isPrimary: Bool
    
    /// Characteristics in this service
    public var characteristics: [BLEMutableCharacteristic]
    
    public init(uuid: BLEUUID, isPrimary: Bool = true, characteristics: [BLEMutableCharacteristic] = []) {
        self.uuid = uuid
        self.isPrimary = isPrimary
        self.characteristics = characteristics
    }
}

/// A mutable GATT characteristic for the peripheral role
public struct BLEMutableCharacteristic: Sendable, Hashable, Identifiable {
    public var id: BLEUUID { uuid }
    
    /// Characteristic UUID
    public let uuid: BLEUUID
    
    /// Properties (read, write, notify, etc.)
    public let properties: BLECharacteristicProperties
    
    /// Permissions for access control
    public let permissions: BLEAttributePermissions
    
    /// Initial value (can be nil)
    public var value: Data?
    
    public init(
        uuid: BLEUUID,
        properties: BLECharacteristicProperties,
        permissions: BLEAttributePermissions,
        value: Data? = nil
    ) {
        self.uuid = uuid
        self.properties = properties
        self.permissions = permissions
        self.value = value
    }
}

/// Attribute permissions for characteristics
public struct BLEAttributePermissions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let readable = BLEAttributePermissions(rawValue: 1 << 0)
    public static let writeable = BLEAttributePermissions(rawValue: 1 << 1)
    public static let readEncryptionRequired = BLEAttributePermissions(rawValue: 1 << 2)
    public static let writeEncryptionRequired = BLEAttributePermissions(rawValue: 1 << 3)
}

// MARK: - Advertisement Data

/// Data to include in BLE advertisement
public struct BLEAdvertisementData: Sendable {
    /// Local name to advertise
    public let localName: String?
    
    /// Service UUIDs to include in advertisement
    public let serviceUUIDs: [BLEUUID]
    
    /// Manufacturer-specific data
    public let manufacturerData: Data?
    
    public init(
        localName: String? = nil,
        serviceUUIDs: [BLEUUID] = [],
        manufacturerData: Data? = nil
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
        self.manufacturerData = manufacturerData
    }
    
    /// Create Dexcom-style advertisement
    /// - Parameters:
    ///   - transmitterID: Dexcom transmitter ID (e.g., "8G1234")
    ///   - isG7: Whether this is a G7 transmitter
    public static func dexcom(transmitterID: String, isG7: Bool = false) -> BLEAdvertisementData {
        BLEAdvertisementData(
            localName: "Dexcom\(transmitterID.suffix(2))",
            serviceUUIDs: [isG7 ? .dexcomG7Advertisement : .dexcomAdvertisement],
            manufacturerData: nil
        )
    }
}

// MARK: - Central Info

/// Information about a connected central
public struct BLECentralInfo: Sendable, Hashable, Identifiable {
    public var id: BLEUUID { identifier }
    
    /// Unique identifier
    public let identifier: BLEUUID
    
    /// Maximum update value length
    public let maximumUpdateValueLength: Int
    
    public init(identifier: BLEUUID, maximumUpdateValueLength: Int = 512) {
        self.identifier = identifier
        self.maximumUpdateValueLength = maximumUpdateValueLength
    }
}

// MARK: - ATT Requests

/// A read request from a central
public struct BLEATTReadRequest: Sendable, Identifiable {
    public let id: UUID
    
    /// The central making the request
    public let central: BLECentralInfo
    
    /// The characteristic being read
    public let characteristicUUID: BLEUUID
    
    /// Offset for long reads
    public let offset: Int
    
    public init(id: UUID = UUID(), central: BLECentralInfo, characteristicUUID: BLEUUID, offset: Int = 0) {
        self.id = id
        self.central = central
        self.characteristicUUID = characteristicUUID
        self.offset = offset
    }
}

/// A write request from a central
public struct BLEATTWriteRequest: Sendable, Identifiable {
    public let id: UUID
    
    /// The central making the request
    public let central: BLECentralInfo
    
    /// The characteristic being written
    public let characteristicUUID: BLEUUID
    
    /// The value being written
    public let value: Data
    
    /// Offset for long writes
    public let offset: Int
    
    public init(id: UUID = UUID(), central: BLECentralInfo, characteristicUUID: BLEUUID, value: Data, offset: Int = 0) {
        self.id = id
        self.central = central
        self.characteristicUUID = characteristicUUID
        self.value = value
        self.offset = offset
    }
}

/// Subscription change notification
public struct BLESubscriptionChange: Sendable {
    /// The central that subscribed/unsubscribed
    public let central: BLECentralInfo
    
    /// The characteristic
    public let characteristicUUID: BLEUUID
    
    /// Whether subscribed (true) or unsubscribed (false)
    public let isSubscribed: Bool
    
    public init(central: BLECentralInfo, characteristicUUID: BLEUUID, isSubscribed: Bool) {
        self.central = central
        self.characteristicUUID = characteristicUUID
        self.isSubscribed = isSubscribed
    }
}

// MARK: - ATT Error Codes

/// ATT protocol error codes for responses
public enum BLEATTError: UInt8, Sendable {
    case success = 0x00
    case invalidHandle = 0x01
    case readNotPermitted = 0x02
    case writeNotPermitted = 0x03
    case invalidPDU = 0x04
    case insufficientAuthentication = 0x05
    case requestNotSupported = 0x06
    case invalidOffset = 0x07
    case insufficientAuthorization = 0x08
    case prepareQueueFull = 0x09
    case attributeNotFound = 0x0A
    case attributeNotLong = 0x0B
    case insufficientEncryptionKeySize = 0x0C
    case invalidAttributeValueLength = 0x0D
    case unlikelyError = 0x0E
    case insufficientEncryption = 0x0F
    case unsupportedGroupType = 0x10
    case insufficientResources = 0x11
}

// MARK: - Peripheral Manager Factory

/// Factory for creating platform-appropriate BLE peripheral manager
public enum BLEPeripheralManagerFactory {
    /// Create a BLE peripheral manager for the current platform
    /// - Parameter options: Platform-specific options
    /// - Returns: Platform-appropriate peripheral manager
    public static func create(options: BLEPeripheralManagerOptions = .default) -> any BLEPeripheralManagerProtocol {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        return DarwinBLEPeripheralManager(options: options)
        #else
        return MockBLEPeripheralManager(options: options)
        #endif
    }
}

/// Options for peripheral manager creation
public struct BLEPeripheralManagerOptions: Sendable {
    /// Whether to show power alert on iOS
    public let showPowerAlert: Bool
    
    /// Restoration identifier for iOS background
    public let restorationIdentifier: String?
    
    /// Default options
    public static let `default` = BLEPeripheralManagerOptions(showPowerAlert: false, restorationIdentifier: nil)
    
    public init(showPowerAlert: Bool = false, restorationIdentifier: String? = nil) {
        self.showPowerAlert = showPowerAlert
        self.restorationIdentifier = restorationIdentifier
    }
}
