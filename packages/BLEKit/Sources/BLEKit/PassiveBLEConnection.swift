// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PassiveBLEConnection.swift
// BLEKit
//
// Passive BLE connection for eavesdropping on CGM notifications.
// Connects and subscribes without sending commands (coexists with vendor app).
// Trace: CGM-040, CGM-041, CGM-042, REQ-CGM-040
//
// Reference: externals/CGMBLEKit/CGMBLEKit/Transmitter.swift:161-270

import Foundation
import T1PalCore

// MARK: - Passive Connection State

/// State of a passive BLE connection
public enum PassiveConnectionState: String, Sendable {
    case disconnected
    case connecting
    case discoveringServices
    case subscribing
    case listening
    case error
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension PassiveConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .connecting, .discoveringServices, .subscribing: return .connecting
        case .listening: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Passive Glucose Reading

/// Glucose reading observed passively from BLE notifications
public struct PassiveGlucoseReading: Sendable, Equatable {
    /// Glucose value in mg/dL
    public let glucoseValue: Int
    
    /// Trend arrow (if available)
    public let trend: GlucoseTrend?
    
    /// Timestamp of reading
    public let timestamp: Date
    
    /// Transmitter ID
    public let transmitterId: String
    
    /// Whether this was from backfill
    public let isBackfill: Bool
    
    /// Raw notification data (for debugging)
    public let rawData: Data
    
    public init(
        glucoseValue: Int,
        trend: GlucoseTrend? = nil,
        timestamp: Date = Date(),
        transmitterId: String,
        isBackfill: Bool = false,
        rawData: Data = Data()
    ) {
        self.glucoseValue = glucoseValue
        self.trend = trend
        self.timestamp = timestamp
        self.transmitterId = transmitterId
        self.isBackfill = isBackfill
        self.rawData = rawData
    }
}

// MARK: - Passive BLE Connection

/// Passive BLE connection for eavesdropping on CGM glucose notifications.
///
/// This connects to a CGM transmitter and subscribes to notifications WITHOUT
/// sending any commands. This allows coexistence with the vendor app (Dexcom, etc.)
/// which continues to control the transmitter.
///
/// Pattern: Connect → Discover → Subscribe (no write) → Listen for notifications
///
/// Reference: CGMBLEKit Transmitter.swift passiveModeEnabled pattern
public actor PassiveBLEConnection {
    
    // MARK: - Properties
    
    /// BLE central for connections (optional for testing)
    private let central: (any BLECentralProtocol)?
    
    /// Current connected peripheral
    private var peripheral: (any BLEPeripheralProtocol)?
    
    /// Current connection state
    public private(set) var state: PassiveConnectionState = .disconnected
    
    /// Public accessor for connection state (async for actor isolation)
    public var connectionState: PassiveConnectionState { state }
    
    /// Transmitter ID being observed
    public private(set) var transmitterId: String?
    
    /// Control characteristic for glucose notifications
    private var controlCharacteristic: BLECharacteristic?
    
    /// Backfill characteristic for historical data
    private var backfillCharacteristic: BLECharacteristic?
    
    /// Notification subscription task
    private var subscriptionTask: Task<Void, Error>?
    
    /// Backfill subscription task
    private var backfillTask: Task<Void, Error>?
    
    // MARK: - Callbacks
    
    /// Called when glucose reading is observed
    public var onGlucoseReading: (@Sendable (PassiveGlucoseReading) -> Void)?
    
    /// Called when connection state changes
    public var onStateChange: (@Sendable (PassiveConnectionState) -> Void)?
    
    /// Called on error
    public var onError: (@Sendable (Error) -> Void)?
    
    // MARK: - Configuration
    
    /// CGM device type for parsing
    private var deviceType: CGMDeviceType = .dexcomG6
    
    /// Service UUID to discover
    private let serviceUUID: BLEUUID
    
    /// Control characteristic UUID
    private let controlUUID: BLEUUID
    
    /// Backfill characteristic UUID (optional)
    private let backfillUUID: BLEUUID?
    
    // MARK: - Initialization
    
    /// Create passive connection for Dexcom G6
    public static func forDexcomG6(central: any BLECentralProtocol) -> PassiveBLEConnection {
        PassiveBLEConnection(
            central: central,
            serviceUUID: .dexcomService,
            controlUUID: .dexcomControl,
            backfillUUID: .dexcomBackfill,
            deviceType: .dexcomG6
        )
    }
    
    /// Create passive connection for Dexcom G7
    public static func forDexcomG7(central: any BLECentralProtocol) -> PassiveBLEConnection {
        PassiveBLEConnection(
            central: central,
            serviceUUID: .dexcomService,  // G7 uses same service as G6
            controlUUID: .dexcomControl,   // Same control characteristic
            backfillUUID: .dexcomG7Backfill,  // G7 uses 3536 for backfill
            deviceType: .dexcomG7
        )
    }
    
    /// Initialize with specific UUIDs
    public init(
        central: any BLECentralProtocol,
        serviceUUID: BLEUUID,
        controlUUID: BLEUUID,
        backfillUUID: BLEUUID?,
        deviceType: CGMDeviceType = .dexcomG6
    ) {
        self.central = central
        self.serviceUUID = serviceUUID
        self.controlUUID = controlUUID
        self.backfillUUID = backfillUUID
        self.deviceType = deviceType
    }
    
    /// Test-only initializer (no central required)
    public init(deviceType: CGMDeviceType) {
        self.central = nil
        self.serviceUUID = .dexcomService
        self.controlUUID = .dexcomControl
        self.backfillUUID = .dexcomBackfill
        self.deviceType = deviceType
    }
    
    // MARK: - Connection
    
    /// Connect to a peripheral and start passive listening
    /// - Parameters:
    ///   - peripheralInfo: Peripheral to connect to
    ///   - transmitterId: Transmitter ID for tracking
    public func connect(
        to peripheralInfo: BLEPeripheralInfo,
        transmitterId: String
    ) async throws {
        guard let central = central else {
            throw PassiveConnectionError.serviceNotFound  // Test mode - no central
        }
        
        guard state == .disconnected || state == .error else {
            throw PassiveConnectionError.alreadyConnected
        }
        
        self.transmitterId = transmitterId
        updateState(.connecting)
        
        do {
            // Connect to peripheral
            let connectedPeripheral = try await central.connect(to: peripheralInfo)
            self.peripheral = connectedPeripheral
            
            // Discover services
            updateState(.discoveringServices)
            let services = try await connectedPeripheral.discoverServices([serviceUUID])
            
            guard let service = services.first else {
                throw PassiveConnectionError.serviceNotFound
            }
            
            // Discover characteristics
            var characteristicUUIDs = [controlUUID]
            if let backfillUUID = backfillUUID {
                characteristicUUIDs.append(backfillUUID)
            }
            
            let characteristics = try await connectedPeripheral.discoverCharacteristics(
                characteristicUUIDs,
                for: service
            )
            
            // Find control characteristic
            controlCharacteristic = characteristics.first { $0.uuid == controlUUID }
            guard controlCharacteristic != nil else {
                throw PassiveConnectionError.characteristicNotFound
            }
            
            // Find backfill characteristic (optional)
            if let backfillUUID = backfillUUID {
                backfillCharacteristic = characteristics.first { $0.uuid == backfillUUID }
            }
            
            // Subscribe to notifications (CGM-041: subscribe-only mode)
            updateState(.subscribing)
            try await subscribeToNotifications(connectedPeripheral)
            
            updateState(.listening)
            
        } catch {
            updateState(.error)
            onError?(error)
            throw error
        }
    }
    
    /// Subscribe to characteristic notifications without writing
    /// This is the key CGM-041 capability: setNotifyValue without write
    private func subscribeToNotifications(_ peripheral: any BLEPeripheralProtocol) async throws {
        guard let control = controlCharacteristic else {
            throw PassiveConnectionError.characteristicNotFound
        }
        
        // Subscribe to control characteristic (sync registration for fast BLE windows)
        subscriptionTask = Task {
            let stream = await peripheral.prepareNotificationStream(for: control)
            
            for try await data in stream {
                await handleControlNotification(data)
            }
        }
        
        // Subscribe to backfill if available (CGM-042)
        if let backfill = backfillCharacteristic {
            backfillTask = Task {
                let stream = await peripheral.prepareNotificationStream(for: backfill)
                
                for try await data in stream {
                    await handleBackfillNotification(data)
                }
            }
        }
    }
    
    // MARK: - Notification Handling
    
    /// Handle control characteristic notification (glucose data)
    private func handleControlNotification(_ data: Data) async {
        guard data.count > 0 else { return }
        
        let opcode = data[0]
        
        // Parse based on device type and opcode
        // Reference: CGMBLEKit Transmitter.swift:245-258
        switch deviceType {
        case .dexcomG6, .dexcomG6Plus:
            // G6 glucose opcodes: 0x31 (glucoseRx), 0x4E (glucoseG6Rx)
            if opcode == 0x31 || opcode == 0x4E {
                if let reading = parseG6GlucoseNotification(data) {
                    onGlucoseReading?(reading)
                }
            }
            
        case .dexcomG7:
            // G7 glucose opcode: 0x4F
            if opcode == 0x4F {
                if let reading = parseG7GlucoseNotification(data) {
                    onGlucoseReading?(reading)
                }
            }
            
        default:
            break
        }
    }
    
    /// Handle backfill notification (historical data)
    private func handleBackfillNotification(_ data: Data) async {
        guard data.count > 0 else { return }
        
        // Opcode 0x51 is glucoseBackfillRx
        if data[0] == 0x51 {
            if let readings = parseBackfillNotification(data) {
                for reading in readings {
                    onGlucoseReading?(reading)
                }
            }
        }
    }
    
    // MARK: - Parsing
    
    /// Convert BLE trend byte to GlucoseTrend
    private func parseTrend(_ raw: UInt8) -> GlucoseTrend? {
        // Dexcom BLE trend values:
        // 1: doubleUp, 2: singleUp, 3: fortyFiveUp, 4: flat
        // 5: fortyFiveDown, 6: singleDown, 7: doubleDown
        // 8: notComputable, 9: rateOutOfRange
        switch raw {
        case 1: return .doubleUp
        case 2: return .singleUp
        case 3: return .fortyFiveUp
        case 4: return .flat
        case 5: return .fortyFiveDown
        case 6: return .singleDown
        case 7: return .doubleDown
        case 8: return .notComputable
        case 9: return .rateOutOfRange
        default: return nil
        }
    }
    
    /// Parse G6 glucose notification
    /// Reference: CGMBLEKit GlucoseRxMessage
    private func parseG6GlucoseNotification(_ data: Data) -> PassiveGlucoseReading? {
        // G6 GlucoseRxMessage format:
        // [0]: opcode (0x31 or 0x4E)
        // [1]: status
        // [2-3]: glucose (little endian, needs /10 for display)
        // [4-7]: timestamp
        // [8]: trend
        
        guard data.count >= 9 else { return nil }
        
        let rawGlucose = UInt16(data[2]) | (UInt16(data[3]) << 8)
        let glucoseValue = Int(rawGlucose) // Raw value, actual parsing may vary
        
        let trend = parseTrend(data[8])
        
        return PassiveGlucoseReading(
            glucoseValue: glucoseValue,
            trend: trend,
            timestamp: Date(),
            transmitterId: transmitterId ?? "unknown",
            isBackfill: false,
            rawData: data
        )
    }
    
    /// Parse G7 glucose notification
    private func parseG7GlucoseNotification(_ data: Data) -> PassiveGlucoseReading? {
        // G7 has similar format but opcode 0x4F
        guard data.count >= 9 else { return nil }
        
        let rawGlucose = UInt16(data[2]) | (UInt16(data[3]) << 8)
        let glucoseValue = Int(rawGlucose)
        
        let trend = parseTrend(data[8])
        
        return PassiveGlucoseReading(
            glucoseValue: glucoseValue,
            trend: trend,
            timestamp: Date(),
            transmitterId: transmitterId ?? "unknown",
            isBackfill: false,
            rawData: data
        )
    }
    
    /// Parse backfill notification for historical readings
    private func parseBackfillNotification(_ data: Data) -> [PassiveGlucoseReading]? {
        // Backfill contains multiple glucose points
        // Reference: CGMBLEKit GlucoseBackfillRxMessage
        guard data.count >= 10 else { return nil }
        
        // This is a simplified implementation
        // Real implementation would parse the full backfill buffer
        var readings: [PassiveGlucoseReading] = []
        
        // Parse glucose entries from backfill data
        // Format varies - this is a placeholder
        let rawGlucose = UInt16(data[4]) | (UInt16(data[5]) << 8)
        
        let reading = PassiveGlucoseReading(
            glucoseValue: Int(rawGlucose),
            trend: nil,
            timestamp: Date(),
            transmitterId: transmitterId ?? "unknown",
            isBackfill: true,
            rawData: data
        )
        readings.append(reading)
        
        return readings
    }
    
    // MARK: - Disconnection
    
    /// Disconnect from the peripheral
    public func disconnect() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        
        backfillTask?.cancel()
        backfillTask = nil
        
        if let peripheral = peripheral {
            await peripheral.disconnect()
        }
        
        peripheral = nil
        controlCharacteristic = nil
        backfillCharacteristic = nil
        transmitterId = nil
        
        updateState(.disconnected)
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: PassiveConnectionState) {
        state = newState
        onStateChange?(newState)
    }
}

// MARK: - Errors

/// Errors for passive BLE connection
public enum PassiveConnectionError: Error, LocalizedError {
    case alreadyConnected
    case serviceNotFound
    case characteristicNotFound
    case subscriptionFailed
    case parsingFailed
    
    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "Already connected to a peripheral"
        case .serviceNotFound:
            return "Required BLE service not found"
        case .characteristicNotFound:
            return "Required BLE characteristic not found"
        case .subscriptionFailed:
            return "Failed to subscribe to notifications"
        case .parsingFailed:
            return "Failed to parse notification data"
        }
    }
}

// MARK: - Test Helpers

extension PassiveBLEConnection {
    /// Set callback for test - enables testing notification handling
    public func setOnGlucoseReading(_ callback: @escaping @Sendable (PassiveGlucoseReading) -> Void) {
        self.onGlucoseReading = callback
    }
    
    /// Handle notification for testing - simulates BLE notification receipt
    public func handleNotificationForTest(_ data: Data, isBackfill: Bool) async {
        if isBackfill {
            await handleBackfillNotification(data)
        } else {
            await handleControlNotification(data)
        }
    }
}
