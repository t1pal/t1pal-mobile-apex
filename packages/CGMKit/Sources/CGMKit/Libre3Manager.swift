// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre3Manager.swift
// T1Pal Mobile
//
// Abbott Libre 3 BLE CGM driver
// Requirements: CGM-003 → REQ-CGM-004
// LIBRE-IMPL-002: Wire BLECentral for real BLE operations

import Foundation
import T1PalCore
import BLEKit

// MARK: - Libre 3 Constants

/// Libre 3 BLE service and characteristic UUIDs
/// Source: externals/Juggluco/Common/src/main/java/tk/glucodata/SuperGattCallback.java
/// LIBRE3-002: Verified against Juggluco implementation 2026-02-25
public enum Libre3UUID {
    // MARK: - Services
    
    /// Data service (primary glucose data)
    public static let dataService = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Security service (authentication/pairing)
    public static let securityService = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Debug service (diagnostic data)
    public static let debugService = "08982400-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    // MARK: - Data Characteristics
    
    /// BLE login characteristic
    public static let bleLogin = "0000F001-0000-1000-8000-00805F9B34FB"
    
    /// Patch control (commands to sensor)
    public static let patchControl = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Patch status (sensor state notifications)
    public static let patchStatus = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Glucose data (real-time readings) ← PRIMARY DATA
    public static let glucoseData = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Historic data (backfill readings)
    public static let historicData = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Clinical data (fast updates)
    public static let clinicalData = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Event log (sensor events)
    public static let eventLog = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Factory data (calibration info)
    public static let factoryData = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    // MARK: - Security Characteristics
    
    /// Command response (security commands)
    public static let commandResponse = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Challenge data (ECDH challenge)
    public static let challengeData = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    /// Certificate data (app/patch certificates)
    public static let certData = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"
    
    // MARK: - Standard BLE Services
    
    /// Device info service
    public static let deviceInfo = "0000180A-0000-1000-8000-00805F9B34FB"
    
    /// Manufacturer name characteristic
    public static let manufacturer = "00002A29-0000-1000-8000-00805F9B34FB"
    
    /// Serial number characteristic
    public static let serialNumber = "00002A25-0000-1000-8000-00805F9B34FB"
    
    // MARK: - Legacy Aliases (deprecated)
    
    @available(*, deprecated, renamed: "dataService")
    public static let service = dataService
    
    @available(*, deprecated, renamed: "patchControl")
    public static let control = patchControl
    
    @available(*, deprecated, renamed: "commandResponse")
    public static let auth = commandResponse
}

// MARK: - Libre 3 Sensor State

/// Libre 3 specific sensor states
public enum Libre3SensorState: UInt8, Sendable {
    case notActivated = 0x01
    case warmingUp = 0x02
    case ready = 0x03
    case expired = 0x04
    case shutdown = 0x05
    case failure = 0x06
    
    /// Convert to common SensorState
    public var sensorState: SensorState {
        switch self {
        case .notActivated: return .notStarted
        case .warmingUp: return .warmingUp
        case .ready: return .active
        case .expired: return .expired
        case .shutdown: return .stopped
        case .failure: return .failed
        }
    }
}

// MARK: - Libre 3 Reading

/// Raw Libre 3 glucose reading from BLE
public struct Libre3Reading: Sendable, Equatable {
    public let rawValue: UInt16        // Raw glucose value
    public let timestamp: Date          // Reading timestamp
    public let quality: UInt8           // Quality flag
    public let trendArrow: UInt8        // Trend indicator
    public let sensorAge: UInt16        // Minutes since activation
    
    public init(
        rawValue: UInt16,
        timestamp: Date,
        quality: UInt8,
        trendArrow: UInt8,
        sensorAge: UInt16
    ) {
        self.rawValue = rawValue
        self.timestamp = timestamp
        self.quality = quality
        self.trendArrow = trendArrow
        self.sensorAge = sensorAge
    }
    
    /// Convert raw value to mg/dL
    public var glucoseMgdL: Double {
        // Libre 3 raw values are already in mg/dL (no calibration needed)
        Double(rawValue)
    }
    
    /// Check if reading is valid
    public var isValid: Bool {
        quality == 0 && rawValue > 39 && rawValue < 501
    }
    
    /// Convert trend arrow to GlucoseTrend
    /// Source: Juggluco trend2rate() - trend values 0-5
    /// Rate mapping: (trend - 3) * 1.3 mg/dL/min
    public var trend: GlucoseTrend {
        switch trendArrow {
        case 0: return .notComputable  // NAN/unknown
        case 1: return .doubleDown     // -2.6 mg/dL/min (falling quickly)
        case 2: return .singleDown     // -1.3 mg/dL/min (falling)
        case 3: return .flat           // 0.0 mg/dL/min (stable)
        case 4: return .singleUp       // +1.3 mg/dL/min (rising)
        case 5: return .doubleUp       // +2.6 mg/dL/min (rising quickly)
        default: return .notComputable
        }
    }
    
    /// Rate of change in mg/dL/min (from trend arrow)
    public var rateOfChange: Double? {
        guard trendArrow > 0 && trendArrow <= 5 else { return nil }
        return Double(Int(trendArrow) - 3) * 1.3
    }
    
    /// Convert to GlucoseReading
    public func toGlucoseReading() -> GlucoseReading? {
        guard isValid else { return nil }
        return GlucoseReading(
            glucose: glucoseMgdL,
            timestamp: timestamp,
            trend: trend,
            source: "Libre3"
        )
    }
}

// MARK: - Libre 3 Sensor Info

/// Libre 3 sensor information
public struct Libre3SensorInfo: Sendable, Equatable {
    public let serialNumber: String
    public let sensorState: Libre3SensorState
    public let startDate: Date
    public let expirationDate: Date
    public let firmwareVersion: String
    
    public init(
        serialNumber: String,
        sensorState: Libre3SensorState,
        startDate: Date,
        expirationDate: Date,
        firmwareVersion: String = ""
    ) {
        self.serialNumber = serialNumber
        self.sensorState = sensorState
        self.startDate = startDate
        self.expirationDate = expirationDate
        self.firmwareVersion = firmwareVersion
    }
    
    /// Time remaining on sensor
    public var timeRemaining: TimeInterval {
        max(0, expirationDate.timeIntervalSinceNow)
    }
    
    /// Days remaining (rounded down)
    public var daysRemaining: Int {
        Int(timeRemaining / 86400)
    }
    
    /// Is sensor expired?
    public var isExpired: Bool {
        timeRemaining <= 0
    }
    
    /// Sensor age in days
    public var sensorAgeDays: Double {
        Date().timeIntervalSince(startDate) / 86400
    }
}

// MARK: - Libre 3 Packet Parser

/// Parse Libre 3 BLE packets
public struct Libre3PacketParser: Sendable {
    
    public init() {}
    
    /// Parse glucose data packet
    public func parseGlucosePacket(_ data: Data) -> Libre3Reading? {
        guard data.count >= 10 else { return nil }
        
        // Read UInt16 at offset 0 (little endian)
        let rawValue = UInt16(data[0]) | (UInt16(data[1]) << 8)
        
        // Read UInt32 at offset 2 (little endian)
        let timestamp = UInt32(data[2]) |
                       (UInt32(data[3]) << 8) |
                       (UInt32(data[4]) << 16) |
                       (UInt32(data[5]) << 24)
        
        let quality = data[6]
        let trendArrow = data[7]
        
        // Read UInt16 at offset 8 (little endian)
        let sensorAge = UInt16(data[8]) | (UInt16(data[9]) << 8)
        
        // Convert timestamp (seconds since sensor activation)
        let readingDate = Date(timeIntervalSince1970: Double(timestamp))
        
        return Libre3Reading(
            rawValue: rawValue,
            timestamp: readingDate,
            quality: quality,
            trendArrow: trendArrow,
            sensorAge: sensorAge
        )
    }
    
    /// Parse sensor info packet
    public func parseSensorInfoPacket(_ data: Data) -> Libre3SensorInfo? {
        guard data.count >= 24 else { return nil }
        
        // Serial number (first 10 bytes as ASCII)
        let serialBytes = data.prefix(10)
        let serialNumber = String(data: serialBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
        
        // Sensor state (byte 10)
        let stateRaw = data[10]
        let sensorState = Libre3SensorState(rawValue: stateRaw) ?? .failure
        
        // Start timestamp (bytes 11-14, little endian)
        let startTimestamp = UInt32(data[11]) |
                            (UInt32(data[12]) << 8) |
                            (UInt32(data[13]) << 16) |
                            (UInt32(data[14]) << 24)
        let startDate = Date(timeIntervalSince1970: Double(startTimestamp))
        
        // Expiration (14 days from start)
        let expirationDate = startDate.addingTimeInterval(14 * 24 * 3600)
        
        // Firmware version (bytes 20-21)
        let fwMajor = data[20]
        let fwMinor = data[21]
        let firmwareVersion = "\(fwMajor).\(fwMinor)"
        
        return Libre3SensorInfo(
            serialNumber: serialNumber,
            sensorState: sensorState,
            startDate: startDate,
            expirationDate: expirationDate,
            firmwareVersion: firmwareVersion
        )
    }
}

// MARK: - Libre 3 Connection State

/// BLE connection state for Libre 3
/// LIBRE-IMPL-005: Added cloudFallback state
public enum Libre3ConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case authenticating
    case connected
    case cloudFallback  // LIBRE-IMPL-005: Using LibreLinkUp cloud API
    case error(String)
    
    public var isConnected: Bool {
        switch self {
        case .connected, .cloudFallback:
            return true
        default:
            return false
        }
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension Libre3ConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .scanning: return .scanning
        case .connecting, .authenticating: return .connecting
        case .connected, .cloudFallback: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Libre 3 Manager Config

/// Configuration for Libre3Manager
/// LIBRE-IMPL-002: Following DexcomG6ManagerConfig pattern
/// LIBRE-IMPL-005: Added cloud fallback credentials
public struct Libre3ManagerConfig: Sendable {
    /// Sensor serial number (from NFC scan)
    public let sensorSerial: String?
    
    /// Whether to auto-reconnect on disconnect
    public let autoReconnect: Bool
    
    /// Initial delay before reconnection attempt (seconds)
    public let reconnectDelay: TimeInterval
    
    /// Maximum reconnection attempts (0 = unlimited)
    public let maxReconnectAttempts: Int
    
    /// Whether to allow simulated/mock BLE centrals
    public let allowSimulation: Bool
    
    /// LIBRE-IMPL-005: LibreLinkUp credentials for cloud fallback
    public let cloudCredentials: LibreLinkUpCredentials?
    
    /// LIBRE-IMPL-005: Enable cloud fallback when BLE unavailable
    public let enableCloudFallback: Bool
    
    public init(
        sensorSerial: String? = nil,
        autoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 2.0,
        maxReconnectAttempts: Int = 0,
        allowSimulation: Bool = false,
        cloudCredentials: LibreLinkUpCredentials? = nil,
        enableCloudFallback: Bool = false
    ) {
        self.sensorSerial = sensorSerial
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.allowSimulation = allowSimulation
        self.cloudCredentials = cloudCredentials
        self.enableCloudFallback = enableCloudFallback
    }
}

// MARK: - Libre 3 Manager

/// Libre 3 CGM manager with BLE abstraction
/// Requirements: CGM-003 → REQ-CGM-004
/// LIBRE-IMPL-002: Wired with BLECentralProtocol for real BLE operations
public actor Libre3Manager: CGMManagerProtocol {
    public let displayName = "Libre 3"
    public let cgmType = CGMType.libre3
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    public private(set) var connectionState: Libre3ConnectionState = .disconnected
    public private(set) var sensorInfo: Libre3SensorInfo?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    public var onConnectionStateChanged: (@Sendable (Libre3ConnectionState) -> Void)?
    
    // MARK: - Private Properties
    
    private let parser = Libre3PacketParser()
    private var readingHistory: [Libre3Reading] = []
    private let maxHistoryCount = 288 // 24 hours at 5-min intervals
    
    // LIBRE-IMPL-002: BLE infrastructure
    private let central: any BLECentralProtocol
    private let config: Libre3ManagerConfig
    private var peripheral: (any BLEPeripheralProtocol)?
    private var scanTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    
    // Discovered characteristics
    private var glucoseCharacteristic: BLECharacteristic?
    private var controlCharacteristic: BLECharacteristic?
    private var authCharacteristic: BLECharacteristic?
    
    // LIBRE-IMPL-005: Cloud fallback client
    private var cloudClient: LibreLinkUpClient?
    private var cloudFallbackTask: Task<Void, Never>?
    
    // LIBRE3-014: Heartbeat/coexistence mode
    private var connectionEventsTask: Task<Void, Never>?
    private var heartbeatEnabled: Bool = false
    
    /// Callback for LibreLink app connection detection (LIBRE3-014a)
    public var onLibreLinkConnectionDetected: (@Sendable (Bool) -> Void)?
    
    // MARK: - Initialization
    
    /// Create a Libre3Manager with BLE central
    /// - Parameters:
    ///   - config: Manager configuration
    ///   - central: BLE central implementation (real or mock)
    public init(
        config: Libre3ManagerConfig = Libre3ManagerConfig(),
        central: any BLECentralProtocol
    ) {
        self.config = config
        self.central = central
        
        // LIBRE-IMPL-005: Initialize cloud client if credentials provided
        if let credentials = config.cloudCredentials, config.enableCloudFallback {
            self.cloudClient = LibreLinkUpClient(credentials: credentials)
            CGMLogger.general.info("Libre3Manager: cloud fallback enabled")
        }
        
        CGMLogger.general.info("Libre3Manager: initialized with sensorSerial=\(config.sensorSerial ?? "nil")")
    }
    
    /// Legacy init for compatibility (creates stub without BLE)
    @available(*, deprecated, message: "Use init(config:central:) for real BLE operations")
    public init() {
        self.config = Libre3ManagerConfig(allowSimulation: true)
        // Create a placeholder - this won't work for real BLE
        // but maintains API compatibility during migration
        self.central = MockBLECentral()
        CGMLogger.general.warning("Libre3Manager: initialized without BLE central (stub mode)")
    }
    
    // MARK: - CGMManagerProtocol
    
    public func startScanning() async throws {
        // PROD-HARDEN-032: Validate simulation settings before starting
        try validateBLECentral(central, allowSimulation: config.allowSimulation, component: "Libre3Manager")
        
        let state = await central.state
        guard state == .poweredOn else {
            // LIBRE-IMPL-005: Try cloud fallback if BLE unavailable
            if config.enableCloudFallback, cloudClient != nil {
                CGMLogger.general.info("Libre3Manager: BLE unavailable, using cloud fallback")
                try await startCloudFallback()
                return
            }
            throw CGMError.bluetoothUnavailable
        }
        
        setConnectionState(.scanning)
        CGMLogger.general.info("Libre3Manager: Starting BLE scan for Libre 3 sensors")
        
        // Scan for Libre 3 service UUID (using BLEKit predefined UUID)
        let scanStream = central.scan(for: [.libre3Service])
        
        scanTask = Task {
            do {
                for try await result in scanStream {
                    CGMLogger.general.debug("Libre3Manager: Found device \(result.peripheral.identifier)")
                    
                    // If we have a target serial, match it
                    if let targetSerial = config.sensorSerial {
                        if let name = result.peripheral.name, name.contains(targetSerial.suffix(4)) {
                            CGMLogger.general.info("Libre3Manager: Found matching sensor \(targetSerial)")
                            await central.stopScan()
                            try await connectToPeripheral(result.peripheral)
                            break
                        }
                    } else {
                        // Connect to first Libre 3 found
                        CGMLogger.general.info("Libre3Manager: Connecting to first Libre 3 found")
                        await central.stopScan()
                        try await connectToPeripheral(result.peripheral)
                        break
                    }
                }
            } catch {
                CGMLogger.general.error("Libre3Manager: Scan error - \(error.localizedDescription)")
                setConnectionState(.error(error.localizedDescription))
                onError?(.connectionFailed)
            }
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        guard sensor.type == .libre3 else {
            throw CGMError.sensorNotFound
        }
        setConnectionState(.connecting)
        // Would need peripheral info from scan result
        throw CGMError.configurationRequired("Use startScanning() for Libre 3 connection")
    }
    
    public func disconnect() async {
        scanTask?.cancel()
        streamTask?.cancel()
        
        // LIBRE-IMPL-005: Stop cloud fallback if active
        stopCloudFallback()
        
        if let peripheral = peripheral {
            await central.disconnect(peripheral)
        }
        
        peripheral = nil
        glucoseCharacteristic = nil
        controlCharacteristic = nil
        authCharacteristic = nil
        
        setConnectionState(.disconnected)
        CGMLogger.general.info("Libre3Manager: Disconnected")
    }
    
    // MARK: - Private BLE Methods
    
    private func connectToPeripheral(_ info: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        
        do {
            peripheral = try await central.connect(to: info)
            try await discoverServices()
            try await startGlucoseNotifications()
        } catch {
            CGMLogger.general.error("Libre3Manager: Connection failed - \(error.localizedDescription)")
            setConnectionState(.error(error.localizedDescription))
            throw CGMError.connectionFailed
        }
    }
    
    private func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw CGMError.connectionFailed
        }
        
        // Use BLEKit predefined UUID
        let services = try await peripheral.discoverServices([.libre3Service])
        
        guard let libreService = services.first(where: { 
            $0.uuid.description.uppercased() == BLEUUID.libre3Service.description.uppercased() 
        }) else {
            throw CGMError.sensorNotFound
        }
        
        let characteristics = try await peripheral.discoverCharacteristics(nil, for: libreService)
        
        for char in characteristics {
            let uuidUpper = char.uuid.description.uppercased()
            if uuidUpper == BLEUUID.libre3GlucoseData.description.uppercased() {
                glucoseCharacteristic = char
            } else if uuidUpper == BLEUUID.libre3Control.description.uppercased() {
                controlCharacteristic = char
            } else if uuidUpper == BLEUUID.libre3Auth.description.uppercased() {
                authCharacteristic = char
            }
        }
        
        CGMLogger.general.info("Libre3Manager: Discovered characteristics - glucose=\(self.glucoseCharacteristic != nil), control=\(self.controlCharacteristic != nil), auth=\(self.authCharacteristic != nil)")
    }
    
    private func startGlucoseNotifications() async throws {
        guard let peripheral = peripheral,
              let glucoseChar = glucoseCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        // Enable notifications for glucose data
        let glucoseStream = await peripheral.prepareNotificationStream(for: glucoseChar)
        try await peripheral.enableNotifications(for: glucoseChar)
        
        setConnectionState(.connected)
        sensorState = .active
        onSensorStateChanged?(.active)
        CGMLogger.general.info("Libre3Manager: Glucose notifications enabled, streaming started")
        
        streamTask = Task {
            do {
                for try await data in glucoseStream {
                    processReceivedData(data, characteristicUUID: Libre3UUID.glucoseData)
                }
            } catch {
                if !Task.isCancelled {
                    CGMLogger.general.error("Libre3Manager: Stream error - \(error.localizedDescription)")
                    setConnectionState(.error(error.localizedDescription))
                    onError?(.dataUnavailable)
                }
            }
        }
    }
    
    private func setConnectionState(_ state: Libre3ConnectionState) {
        connectionState = state
        onConnectionStateChanged?(state)
    }
    
    // MARK: - Libre 3 Specific
    
    /// Process received BLE data
    public func processReceivedData(_ data: Data, characteristicUUID: String) {
        switch characteristicUUID {
        case Libre3UUID.glucoseData:
            if let reading = parser.parseGlucosePacket(data) {
                handleNewReading(reading)
            }
        case Libre3UUID.patchControl:
            if let info = parser.parseSensorInfoPacket(data) {
                handleSensorInfo(info)
            }
        default:
            break
        }
    }
    
    /// Handle new glucose reading
    private func handleNewReading(_ reading: Libre3Reading) {
        // Store in history
        readingHistory.insert(reading, at: 0)
        if readingHistory.count > maxHistoryCount {
            readingHistory.removeLast()
        }
        
        // Convert and notify
        if let glucoseReading = reading.toGlucoseReading() {
            latestReading = glucoseReading
            onReadingReceived?(glucoseReading)
        }
    }
    
    /// Handle sensor info update
    private func handleSensorInfo(_ info: Libre3SensorInfo) {
        sensorInfo = info
        
        let newState = info.sensorState.sensorState
        if newState != sensorState {
            sensorState = newState
            onSensorStateChanged?(newState)
        }
    }
    
    /// Get reading history
    public func getHistory() -> [Libre3Reading] {
        readingHistory
    }
    
    /// Get sensor time remaining
    public func getSensorTimeRemaining() -> TimeInterval? {
        sensorInfo?.timeRemaining
    }
    
    // MARK: - Authentication
    
    /// Security context after authentication (session keys)
    private var securityContext: Libre3SecurityContext?
    
    /// ECDH instance for current authentication session
    private var ecdh: Libre3ECDH?
    
    /// Security version (detected from sensor or default)
    private var securityVersion: Libre3SecurityVersion = .version1
    
    /// Authenticate with sensor using ECDH key exchange
    /// CGM-PG-005: Wire Libre3ECDH to authenticate()
    /// - Parameter authData: Optional authentication data (e.g., from sensor discovery)
    /// - Throws: CGMError if authentication fails
    public func authenticate(with authData: Data = Data()) async throws {
        connectionState = .authenticating
        onConnectionStateChanged?(.authenticating)
        
        guard let peripheral = peripheral else {
            throw CGMError.connectionFailed
        }
        
        // Discover security service and characteristics if not already done
        let securityServices = try await peripheral.discoverServices([
            .libre3SecurityService
        ])
        
        guard let securityService = securityServices.first else {
            CGMLogger.general.error("Libre3Manager: Security service not found")
            throw CGMError.authenticationFailed
        }
        
        let secChars = try await peripheral.discoverCharacteristics(nil, for: securityService)
        
        // Find the characteristics we need
        var challengeChar: BLECharacteristic?
        var certChar: BLECharacteristic?
        var commandChar: BLECharacteristic?
        
        for char in secChars {
            let uuidUpper = char.uuid.description.uppercased()
            if uuidUpper.contains("22CE") {
                challengeChar = char
            } else if uuidUpper.contains("23FA") {
                certChar = char
            } else if uuidUpper.contains("2198") {
                commandChar = char
            }
        }
        
        CGMLogger.general.debug("Libre3Manager: Security chars - challenge=\(challengeChar != nil), cert=\(certChar != nil), command=\(commandChar != nil)")
        
        // Initialize ECDH with ephemeral key pair
        ecdh = Libre3ECDH(securityVersion: securityVersion)
        
        guard let ecdh = ecdh, let certChar = certChar else {
            throw CGMError.authenticationFailed
        }
        
        // Phase 1: Send app certificate (162 bytes)
        CGMLogger.general.info("Libre3Manager: Sending app certificate...")
        let certificate = ecdh.appCertificate
        try await peripheral.writeValue(certificate, for: certChar, type: .withResponse)
        
        // Phase 2: Send ephemeral public key (65 bytes)
        CGMLogger.general.info("Libre3Manager: Sending ephemeral public key...")
        try await peripheral.writeValue(ecdh.ephemeralPublicKey, for: certChar, type: .withResponse)
        
        // Phase 3: Read patch ephemeral public key from challenge characteristic
        guard let challengeChar = challengeChar else {
            throw CGMError.authenticationFailed
        }
        
        // Enable notifications on challenge characteristic
        let challengeStream = await peripheral.prepareNotificationStream(for: challengeChar)
        try await peripheral.enableNotifications(for: challengeChar)
        
        // Read patch ephemeral key (65 bytes)
        CGMLogger.general.info("Libre3Manager: Reading patch ephemeral key...")
        let patchEphemeral = try await peripheral.readValue(for: challengeChar)
        
        guard patchEphemeral.count == 65 else {
            CGMLogger.general.error("Libre3Manager: Invalid patch ephemeral length: \(patchEphemeral.count)")
            throw CGMError.authenticationFailed
        }
        
        // Phase 4: Perform ECDH key agreement
        CGMLogger.general.info("Libre3Manager: Performing ECDH key agreement...")
        let sharedSecret = try ecdh.deriveSharedSecret(patchEphemeralKey: patchEphemeral)
        
        // Derive kAuth from shared secret
        let kAuth = Libre3X962KDF.deriveKAuth(from: sharedSecret)
        CGMLogger.general.debug("Libre3Manager: Derived kAuth (\(kAuth.count) bytes)")
        
        // Phase 5: Wait for encrypted challenge from sensor
        CGMLogger.general.info("Libre3Manager: Waiting for encrypted challenge...")
        var encryptedChallenge: Data?
        
        for try await notification in challengeStream {
            if notification.count >= 60 {  // Encrypted challenge + tag
                encryptedChallenge = notification
                break
            }
        }
        
        guard let encryptedChallenge = encryptedChallenge else {
            throw CGMError.authenticationFailed
        }
        
        // Phase 6: Decrypt challenge to extract session keys
        CGMLogger.general.info("Libre3Manager: Decrypting challenge...")
        
        // Build nonce for decryption (13 bytes: ivEnc[8] + counter[4] + 0x00)
        // For initial challenge, use zeros as IV base
        let challengeNonce = Data(repeating: 0, count: 13)
        
        let decryptedChallenge = try Libre3AesCcm.decrypt(
            ciphertext: encryptedChallenge,
            key: kAuth,
            nonce: challengeNonce
        )
        
        // Extract session keys (kEnc, ivEnc)
        securityContext = try Libre3ECDH.extractSessionKeys(from: decryptedChallenge)
        CGMLogger.general.info("Libre3Manager: Session keys extracted successfully")
        
        // Authentication complete
        connectionState = .connected
        onConnectionStateChanged?(.connected)
        sensorState = .active
        onSensorStateChanged?(.active)
        
        CGMLogger.general.info("Libre3Manager: Authentication complete with ECDH")
    }
    
    /// Get current security context (for data decryption)
    public var currentSecurityContext: Libre3SecurityContext? {
        securityContext
    }
    
    // MARK: - Cloud Fallback (LIBRE-IMPL-005)
    
    /// Start cloud-based glucose fetching as fallback
    private func startCloudFallback() async throws {
        guard let client = cloudClient else {
            throw CGMError.notConfigured
        }
        
        setConnectionState(.cloudFallback)
        sensorState = .active
        onSensorStateChanged?(.active)
        CGMLogger.general.info("Libre3Manager: Starting cloud fallback polling")
        
        // Start periodic cloud polling
        cloudFallbackTask = Task {
            while !Task.isCancelled {
                do {
                    if let reading = try await client.fetchLatest() {
                        latestReading = reading
                        onReadingReceived?(reading)
                        CGMLogger.general.debug("Libre3Manager: Cloud reading \(reading.glucose) mg/dL")
                    }
                } catch {
                    CGMLogger.general.error("Libre3Manager: Cloud fetch error - \(error.localizedDescription)")
                    onError?(.connectionFailed)
                }
                
                // Poll every 60 seconds (LibreLinkUp rate limit aware)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }
    
    /// Stop cloud fallback polling
    private func stopCloudFallback() {
        cloudFallbackTask?.cancel()
        cloudFallbackTask = nil
    }
    
    /// Check if cloud fallback is available
    public var isCloudFallbackAvailable: Bool {
        cloudClient != nil && config.enableCloudFallback
    }
    
    /// Manually fetch from cloud (for one-time sync)
    public func fetchFromCloud() async throws -> GlucoseReading? {
        guard let client = cloudClient else {
            throw CGMError.notConfigured
        }
        return try await client.fetchLatest()
    }
    
    // MARK: - Heartbeat/Coexistence Mode (LIBRE3-014)
    
    /// Start heartbeat mode: monitor for LibreLink app connections and fetch from cloud
    /// This is the xDrip4iOS pattern - detect BLE activity, pull from LibreLinkUp cloud
    /// - Requires: cloudCredentials in config
    /// Trace: LIBRE3-014a, LIBRE3-014b, LIBRE3-014c
    public func startHeartbeatMode() async throws {
        guard config.enableCloudFallback, cloudClient != nil else {
            throw CGMError.notConfigured
        }
        
        // Validate BLE is available
        let state = await central.state
        guard state == .poweredOn else {
            throw CGMError.bluetoothUnavailable
        }
        
        heartbeatEnabled = true
        CGMLogger.general.info("Libre3Manager: Starting heartbeat mode (LIBRE3-014)")
        
        // LIBRE3-014a: Register for Libre 3 BLE connection events
        await central.registerForConnectionEvents(matchingServices: [.libre3Service])
        
        // Start monitoring connection events
        startConnectionEventsMonitoring()
        
        // Set state to indicate we're monitoring
        setConnectionState(.scanning)
    }
    
    /// Stop heartbeat mode
    public func stopHeartbeatMode() {
        heartbeatEnabled = false
        stopConnectionEventsMonitoring()
        CGMLogger.general.info("Libre3Manager: Stopped heartbeat mode")
    }
    
    /// LIBRE3-014a: Monitor BLE connection events for LibreLink app activity
    private func startConnectionEventsMonitoring() {
        connectionEventsTask?.cancel()
        
        // Capture callback outside of Task to avoid isolation issues
        let callback = self.onLibreLinkConnectionDetected
        
        connectionEventsTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await event in self.central.connectionEvents {
                // Only handle peerConnected events (LibreLink app connected to sensor)
                guard event.eventType == .peerConnected else { continue }
                
                CGMLogger.general.info("Libre3Manager: LibreLink connection detected for \(event.peripheral.identifier)")
                
                // Notify callback
                callback?(true)
                
                // LIBRE3-014b: Trigger cloud fetch on heartbeat
                await self.triggerHeartbeatFetch()
            }
        }
    }
    
    /// Stop connection events monitoring
    private func stopConnectionEventsMonitoring() {
        connectionEventsTask?.cancel()
        connectionEventsTask = nil
    }
    
    /// LIBRE3-014b: Fetch glucose from LibreLinkUp when heartbeat detected
    private func triggerHeartbeatFetch() async {
        guard heartbeatEnabled, let client = cloudClient else { return }
        
        CGMLogger.general.debug("Libre3Manager: Heartbeat triggered cloud fetch")
        
        do {
            if let reading = try await client.fetchLatest() {
                latestReading = reading
                onReadingReceived?(reading)
                
                // Update connection state to show we're receiving data
                if connectionState != .cloudFallback {
                    setConnectionState(.cloudFallback)
                    sensorState = .active
                    onSensorStateChanged?(.active)
                }
                
                CGMLogger.general.info("Libre3Manager: Heartbeat fetch got \(reading.glucose) mg/dL")
            }
        } catch {
            CGMLogger.general.error("Libre3Manager: Heartbeat fetch failed - \(error.localizedDescription)")
            // Don't report error for heartbeat failures - they're opportunistic
        }
    }
    
    /// Check if heartbeat mode is active
    public var isHeartbeatModeActive: Bool {
        heartbeatEnabled && connectionEventsTask != nil
    }
}

// MARK: - Libre 3 Simulator

/// Simulated Libre 3 for testing
public actor Libre3Simulator: CGMManagerProtocol {
    public let displayName = "Libre 3 (Simulated)"
    public let cgmType = CGMType.libre3
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private var simulationTask: Task<Void, Never>?
    private var baseGlucose: Double = 120
    
    public init() {}
    
    public func startScanning() async throws {
        // Immediately "find" simulated sensor
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        sensorState = .warmingUp
        onSensorStateChanged?(.warmingUp)
        
        // Brief warmup
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        sensorState = .active
        onSensorStateChanged?(.active)
        
        // Start generating readings
        startSimulation()
    }
    
    public func disconnect() async {
        simulationTask?.cancel()
        simulationTask = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    private func startSimulation() {
        simulationTask = Task {
            while !Task.isCancelled {
                // Generate reading with some variation
                let variation = Double.random(in: -10...10)
                baseGlucose += variation * 0.3
                baseGlucose = max(70, min(200, baseGlucose))
                
                let trend: GlucoseTrend = variation > 5 ? .fortyFiveUp :
                                          variation < -5 ? .fortyFiveDown : .flat
                
                let reading = GlucoseReading(
                    glucose: baseGlucose,
                    timestamp: Date(),
                    trend: trend,
                    source: "Libre3Sim"
                )
                
                latestReading = reading
                onReadingReceived?(reading)
                
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds (accelerated)
            }
        }
    }
}
