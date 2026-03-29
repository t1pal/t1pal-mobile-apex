// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MiaomiaoManager.swift
// CGMKit - Miaomiao
//
// Miaomiao transmitter CGM driver for Libre 1/2 sensors.
// Uses Nordic UART Service (NUS) for BLE communication.
// Trace: PRD-004 REQ-CGM-002 CGM-023

import Foundation
import T1PalCore
import BLEKit

// MARK: - Miaomiao Constants

/// Miaomiao protocol constants
public enum MiaomiaoConstants {
    /// Device name prefix for scanning
    public static let deviceNamePrefix = "miaomiao"
    
    /// Alternative device name prefix
    public static let altDeviceNamePrefix = "Tomato"
    
    /// Firmware request command
    public static let getFirmware: UInt8 = 0xD0
    
    /// Start reading command
    public static let startReading: UInt8 = 0xF0
    
    /// New sensor detected notification
    public static let newSensor: UInt8 = 0x32
    
    /// No sensor found notification
    public static let noSensor: UInt8 = 0x34
    
    /// FRAM data packet notification
    public static let framData: UInt8 = 0x28
    
    /// Firmware version response
    public static let firmwareResponse: UInt8 = 0xD1
    
    /// Expected FRAM size (344 bytes = 43 blocks × 8 bytes)
    public static let framSize = 344
    
    /// Full packet size including headers
    public static let fullPacketSize = 363
    
    /// Libre 1 header offset
    public static let libre1HeaderOffset = 18
}

// MARK: - Miaomiao Connection State

/// Miaomiao connection state
public enum MiaomiaoConnectionState: String, Sendable {
    case idle
    case scanning
    case connecting
    case requestingFirmware
    case waitingForSensor
    case receivingData
    case processingData
    case disconnecting
    case error
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension MiaomiaoConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .idle: return .disconnected
        case .scanning: return .scanning
        case .connecting, .requestingFirmware, .disconnecting: return .connecting
        case .waitingForSensor, .receivingData, .processingData: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Miaomiao Hardware Info

/// Miaomiao hardware information
public struct MiaomiaoHardwareInfo: Sendable, Codable, Equatable {
    /// Firmware version string
    public let firmware: String
    
    /// Hardware version (if available)
    public let hardware: String?
    
    /// Battery level (0-100)
    public let batteryLevel: UInt8?
    
    public init(firmware: String, hardware: String? = nil, batteryLevel: UInt8? = nil) {
        self.firmware = firmware
        self.hardware = hardware
        self.batteryLevel = batteryLevel
    }
}

// MARK: - Miaomiao Sensor Info

/// Information about the attached Libre sensor
public struct MiaomiaoSensorInfo: Sendable, Codable, Equatable {
    /// Sensor serial number
    public let serialNumber: String
    
    /// Sensor UID (8 bytes)
    public let sensorUID: Data
    
    /// Patch info (6 bytes, for Libre 2 decryption)
    public let patchInfo: Data?
    
    /// Sensor type
    public let sensorType: MiaomiaoSensorType
    
    /// Minutes since sensor was started
    public let sensorAge: UInt16
    
    /// Maximum sensor lifetime in minutes
    public let maxLife: UInt16
    
    /// Whether sensor is in warmup period
    public var isWarmingUp: Bool {
        sensorAge < 60  // 1 hour warmup
    }
    
    /// Whether sensor is expired
    public var isExpired: Bool {
        sensorAge >= maxLife
    }
    
    /// Remaining sensor life in minutes
    public var remainingLife: UInt16 {
        sensorAge >= maxLife ? 0 : maxLife - sensorAge
    }
    
    public init(
        serialNumber: String,
        sensorUID: Data,
        patchInfo: Data? = nil,
        sensorType: MiaomiaoSensorType,
        sensorAge: UInt16,
        maxLife: UInt16 = 14400  // 10 days default
    ) {
        self.serialNumber = serialNumber
        self.sensorUID = sensorUID
        self.patchInfo = patchInfo
        self.sensorType = sensorType
        self.sensorAge = sensorAge
        self.maxLife = maxLife
    }
}

/// Libre sensor types supported by Miaomiao
public enum MiaomiaoSensorType: String, Sendable, Codable {
    case libre1
    case libreProH
    case libre2
    case libreUS14day
    case unknown
    
    /// Initialize from patch info byte
    public init(patchInfoByte: UInt8) {
        switch patchInfoByte {
        case 0xDF:
            self = .libre1
        case 0xA2:
            self = .libre1
        case 0xE5:
            self = .libreUS14day
        case 0x9D:
            self = .libre2
        case 0x70:
            self = .libreProH
        default:
            self = .unknown
        }
    }
    
    /// Whether this sensor type requires decryption
    public var requiresDecryption: Bool {
        switch self {
        case .libre2, .libreUS14day:
            return true
        case .libre1, .libreProH, .unknown:
            return false
        }
    }
}

// MARK: - Miaomiao Reading

/// Raw glucose reading from Miaomiao
public struct MiaomiaoReading: Sendable, Equatable {
    /// Raw glucose value (needs calibration)
    public let rawGlucose: UInt16
    
    /// Minutes ago this reading was taken
    public let minutesAgo: UInt16
    
    /// Temperature at reading time
    public let temperature: Double?
    
    public init(rawGlucose: UInt16, minutesAgo: UInt16, temperature: Double? = nil) {
        self.rawGlucose = rawGlucose
        self.minutesAgo = minutesAgo
        self.temperature = temperature
    }
    
    /// Convert raw glucose to mg/dL using simple slope/intercept calibration
    public func calibratedGlucose(slope: Double = 1.0, intercept: Double = 0.0) -> Double {
        Double(rawGlucose) * slope + intercept
    }
}

// MARK: - Miaomiao Manager

/// Miaomiao transmitter CGM Manager
///
/// Reads Libre 1/2 sensors via Miaomiao transmitter using Nordic UART Service.
/// Parses FRAM data to extract glucose readings and sensor information.
public actor MiaomiaoManager: CGMManagerProtocol {
    
    // MARK: - CGMManagerProtocol
    
    public let displayName = "Miaomiao"
    public let cgmType = CGMType.miaomiao
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    // MARK: - Miaomiao-Specific State
    
    /// Hardware info from firmware response
    public private(set) var hardwareInfo: MiaomiaoHardwareInfo?
    
    /// Current sensor information
    public private(set) var miaomiaoSensorInfo: MiaomiaoSensorInfo?
    
    /// Miaomiao-specific connection state
    public private(set) var connectionState: MiaomiaoConnectionState = .idle
    
    /// Connection state change callback
    public var onConnectionStateChanged: (@Sendable (MiaomiaoConnectionState) -> Void)?
    
    /// Recent readings from last FRAM read
    public private(set) var recentReadings: [MiaomiaoReading] = []
    
    /// Trend readings (last 15 minutes, 1 per minute)
    public private(set) var trendReadings: [MiaomiaoReading] = []
    
    /// History readings (last 8 hours, 1 per 15 minutes)
    public private(set) var historyReadings: [MiaomiaoReading] = []
    
    // MARK: - Private State
    
    /// BLE central for scanning/connecting
    private let central: any BLECentralProtocol
    
    /// PROD-HARDEN-032: Whether simulation is allowed
    private let allowSimulation: Bool
    
    /// Connected peripheral
    private var peripheral: (any BLEPeripheralProtocol)?
    
    /// Nordic UART RX characteristic for notifications
    private var rxCharacteristic: BLECharacteristic?
    
    /// Nordic UART TX characteristic for commands
    private var txCharacteristic: BLECharacteristic?
    
    /// Incoming data buffer for fragmented packets
    private var dataBuffer = Data()
    
    /// Expected packet size
    private var expectedPacketSize: Int = 0
    
    /// Scan task
    private var scanTask: Task<Void, Never>?
    
    /// Calibration slope
    public var calibrationSlope: Double = 1.0
    
    /// Calibration intercept
    public var calibrationIntercept: Double = 0.0
    
    // MARK: - Initialization
    
    /// Create a Miaomiao manager with BLE central
    /// - Parameters:
    ///   - central: BLE central implementation (real or mock)
    ///   - allowSimulation: Allow simulated BLE central (default: false for production safety)
    public init(central: any BLECentralProtocol, allowSimulation: Bool = false) {
        self.central = central
        self.allowSimulation = allowSimulation
    }
    
    // MARK: - CGMManagerProtocol Methods
    
    public func startScanning() async throws {
        // PROD-HARDEN-032: Validate simulation settings before starting
        try validateBLECentral(central, allowSimulation: allowSimulation, component: "MiaomiaoManager")
        
        guard connectionState == .idle || connectionState == .error else {
            return
        }
        
        let state = await central.state
        guard state == .poweredOn else {
            setConnectionState(.error)
            throw CGMError.bluetoothUnavailable
        }
        
        setConnectionState(.scanning)
        
        scanTask = Task {
            do {
                // Scan for Nordic UART service (Miaomiao, Tomato)
                for try await result in central.scan(for: [.nordicUARTService]) {
                    // Check if name matches Miaomiao pattern
                    if let name = result.advertisement.localName?.lowercased(),
                       name.contains(MiaomiaoConstants.deviceNamePrefix) ||
                       name.contains(MiaomiaoConstants.altDeviceNamePrefix.lowercased()) {
                        // Found Miaomiao
                        try await connectToDevice(result.peripheral)
                        break
                    }
                }
            } catch {
                setConnectionState(.error)
                onError?(.connectionFailed)
            }
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
    }
    
    public func disconnect() async {
        scanTask?.cancel()
        scanTask = nil
        
        setConnectionState(.disconnecting)
        
        if let peripheral = peripheral {
            await central.disconnect(peripheral)
        }
        
        peripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        setConnectionState(.idle)
        setSensorState(.stopped)
    }
    
    // MARK: - Connection Management
    
    private func connectToDevice(_ peripheralInfo: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        
        do {
            peripheral = try await central.connect(to: peripheralInfo)
            
            guard let device = peripheral else {
                throw CGMError.connectionFailed
            }
            
            // Discover Nordic UART service
            let services = try await device.discoverServices([.nordicUARTService])
            guard let nusService = services.first(where: { $0.uuid == .nordicUARTService }) else {
                throw CGMError.serviceNotFound
            }
            
            // Discover characteristics
            let characteristics = try await device.discoverCharacteristics(
                [.nordicUARTTX, .nordicUARTRX],
                for: nusService
            )
            
            txCharacteristic = characteristics.first { $0.uuid == .nordicUARTTX }
            rxCharacteristic = characteristics.first { $0.uuid == .nordicUARTRX }
            
            guard txCharacteristic != nil, let rxChar = rxCharacteristic else {
                throw CGMError.characteristicNotFound
            }
            
            // Subscribe to notifications on RX
            // Note: We'll handle notifications via subscribe stream in a separate task
            
            setConnectionState(.requestingFirmware)
            setSensorState(.active)
            
            // Start notification handling task
            Task {
                for try await data in device.subscribe(to: rxChar) {
                    self.handleNotification(data)
                }
            }
            
            // Request firmware info
            try await sendCommand(MiaomiaoConstants.getFirmware)
            
        } catch {
            setConnectionState(.error)
            onError?(.connectionFailed)
            throw error
        }
    }
    
    // MARK: - Data Processing
    
    /// Handle incoming notification data from Nordic UART RX
    public func handleNotification(_ data: Data) {
        guard !data.isEmpty else { return }
        
        let firstByte = data[0]
        
        switch firstByte {
        case MiaomiaoConstants.firmwareResponse:
            handleFirmwareResponse(data)
            
        case MiaomiaoConstants.newSensor:
            // Sensor was just scanned, data follows
            setConnectionState(.receivingData)
            dataBuffer = Data()
            expectedPacketSize = MiaomiaoConstants.fullPacketSize
            
        case MiaomiaoConstants.noSensor:
            setConnectionState(.error)
            setSensorState(.failed)
            onError?(.sensorNotFound)
            
        case MiaomiaoConstants.framData:
            handleFramPacket(data)
            
        default:
            // Continuation packet - append to buffer
            if connectionState == .receivingData {
                dataBuffer.append(data)
                
                if dataBuffer.count >= expectedPacketSize {
                    processCompletePacket()
                }
            }
        }
    }
    
    /// Request a new sensor reading
    public func requestReading() async throws {
        guard connectionState == .waitingForSensor else {
            throw CGMError.notConnected
        }
        
        try await sendCommand(MiaomiaoConstants.startReading)
    }
    
    // MARK: - Private Methods
    
    private func setConnectionState(_ newState: MiaomiaoConnectionState) {
        connectionState = newState
        onConnectionStateChanged?(newState)
    }
    
    private func setSensorState(_ newState: SensorState) {
        sensorState = newState
        onSensorStateChanged?(newState)
    }
    
    private func sendCommand(_ command: UInt8) async throws {
        guard let tx = txCharacteristic, let peripheral = peripheral else {
            throw CGMError.notConnected
        }
        
        try await peripheral.writeValue(Data([command]), for: tx, type: .withResponse)
    }
    
    private func handleFirmwareResponse(_ data: Data) {
        // Parse firmware version from response
        if data.count >= 4 {
            let versionBytes = data[1..<min(data.count, 12)]
            let firmware = String(bytes: versionBytes.filter { $0 != 0 }, encoding: .utf8) ?? "Unknown"
            
            var batteryLevel: UInt8? = nil
            if data.count > 12 {
                batteryLevel = data[12]
            }
            
            hardwareInfo = MiaomiaoHardwareInfo(
                firmware: firmware,
                hardware: nil,
                batteryLevel: batteryLevel
            )
        }
        
        setConnectionState(.waitingForSensor)
    }
    
    private func handleFramPacket(_ data: Data) {
        setConnectionState(.receivingData)
        dataBuffer = data
        expectedPacketSize = MiaomiaoConstants.fullPacketSize
        
        if dataBuffer.count >= expectedPacketSize {
            processCompletePacket()
        }
    }
    
    private func processCompletePacket() {
        setConnectionState(.processingData)
        
        guard dataBuffer.count >= MiaomiaoConstants.fullPacketSize else {
            setConnectionState(.error)
            onError?(.dataCorrupted)
            return
        }
        
        do {
            // Extract sensor info from header
            let sensorInfo = try parseSensorInfo(from: dataBuffer)
            self.miaomiaoSensorInfo = sensorInfo
            
            // Check sensor state
            if sensorInfo.isWarmingUp {
                setSensorState(.warmingUp)
            } else if sensorInfo.isExpired {
                setSensorState(.expired)
            } else {
                setSensorState(.active)
            }
            
            // Extract FRAM data (starts after Miaomiao header)
            let framStart = MiaomiaoConstants.libre1HeaderOffset
            let framData = Array(dataBuffer[framStart..<(framStart + MiaomiaoConstants.framSize)])
            
            // Parse glucose readings from FRAM
            let (trend, history) = try parseGlucoseReadings(
                from: framData,
                sensorType: sensorInfo.sensorType,
                sensorUID: sensorInfo.sensorUID,
                patchInfo: sensorInfo.patchInfo
            )
            
            self.trendReadings = trend
            self.historyReadings = history
            self.recentReadings = trend
            
            // Update latest reading
            if let latest = trend.first {
                let glucoseValue = latest.calibratedGlucose(slope: calibrationSlope, intercept: calibrationIntercept)
                let reading = GlucoseReading(
                    glucose: glucoseValue,
                    timestamp: Date().addingTimeInterval(-TimeInterval(latest.minutesAgo * 60)),
                    trend: calculateTrend(from: trend),
                    source: "miaomiao"
                )
                latestReading = reading
                onReadingReceived?(reading)
            }
            
            setConnectionState(.waitingForSensor)
            
        } catch {
            setConnectionState(.error)
            onError?(.dataCorrupted)
        }
        
        dataBuffer = Data()
    }
    
    private func parseSensorInfo(from data: Data) throws -> MiaomiaoSensorInfo {
        guard data.count >= MiaomiaoConstants.libre1HeaderOffset + 26 else {
            throw MiaomiaoError.packetTooShort
        }
        
        // Sensor UID at bytes 5-12 of Miaomiao packet
        let uidStart = 5
        let sensorUID = data.subdata(in: uidStart..<(uidStart + 8))
        
        // Sensor age at byte 317-318 of full FRAM (relative to header)
        let ageOffset = MiaomiaoConstants.libre1HeaderOffset + 317
        var sensorAge: UInt16 = 0
        if data.count > ageOffset + 1 {
            sensorAge = UInt16(data[ageOffset]) | (UInt16(data[ageOffset + 1]) << 8)
        }
        
        // Patch info at bytes 13-18
        var patchInfo: Data? = nil
        if data.count >= 19 {
            patchInfo = data.subdata(in: 13..<19)
        }
        
        // Determine sensor type from patch info
        let sensorType: MiaomiaoSensorType
        if let patch = patchInfo, !patch.isEmpty {
            sensorType = MiaomiaoSensorType(patchInfoByte: patch[0])
        } else {
            sensorType = .libre1
        }
        
        // Serial number from UID
        let serialNumber = generateSerialNumber(from: sensorUID)
        
        return MiaomiaoSensorInfo(
            serialNumber: serialNumber,
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            sensorType: sensorType,
            sensorAge: sensorAge
        )
    }
    
    private func parseGlucoseReadings(
        from fram: [UInt8],
        sensorType: MiaomiaoSensorType,
        sensorUID: Data,
        patchInfo: Data?
    ) throws -> (trend: [MiaomiaoReading], history: [MiaomiaoReading]) {
        
        var framData = fram
        
        // Decrypt if needed
        if sensorType.requiresDecryption, let patchInfo = patchInfo {
            let cryptoType: Libre2Crypto.SensorType = sensorType == .libre2 ? .libre2 : .libreUS14day
            framData = try Libre2Crypto.decryptFRAM(
                type: cryptoType,
                sensorUID: Array(sensorUID),
                patchInfo: patchInfo,
                data: fram
            )
        }
        
        // Parse trend (16 readings, 1 per minute)
        let trendIndex = Int(framData[26]) & 0x0F
        var trend: [MiaomiaoReading] = []
        
        for i in 0..<16 {
            let index = ((trendIndex - 1 - i) + 16) % 16
            let offset = 28 + (index * 6)
            
            if offset + 6 <= framData.count {
                let rawGlucose = UInt16(framData[offset]) | (UInt16(framData[offset + 1] & 0x1F) << 8)
                if rawGlucose > 0 {
                    trend.append(MiaomiaoReading(
                        rawGlucose: rawGlucose,
                        minutesAgo: UInt16(i)
                    ))
                }
            }
        }
        
        // Parse history (32 readings, 1 per 15 minutes)
        let historyIndex = Int(framData[27]) & 0x1F
        var history: [MiaomiaoReading] = []
        
        for i in 0..<32 {
            let index = ((historyIndex - 1 - i) + 32) % 32
            let offset = 124 + (index * 6)
            
            if offset + 6 <= framData.count {
                let rawGlucose = UInt16(framData[offset]) | (UInt16(framData[offset + 1] & 0x1F) << 8)
                if rawGlucose > 0 {
                    history.append(MiaomiaoReading(
                        rawGlucose: rawGlucose,
                        minutesAgo: UInt16(i * 15)
                    ))
                }
            }
        }
        
        return (trend, history)
    }
    
    private func calculateTrend(from readings: [MiaomiaoReading]) -> GlucoseTrend {
        guard readings.count >= 3 else { return .flat }
        
        // Calculate rate of change from last 3 readings
        let r1 = Double(readings[0].rawGlucose)
        let r3 = Double(readings[2].rawGlucose)
        let deltaPerMinute = (r1 - r3) / 2.0
        
        // Convert to trend (mg/dL per minute)
        switch deltaPerMinute {
        case let d where d > 3:
            return .doubleUp
        case let d where d > 2:
            return .singleUp
        case let d where d > 1:
            return .fortyFiveUp
        case let d where d < -3:
            return .doubleDown
        case let d where d < -2:
            return .singleDown
        case let d where d < -1:
            return .fortyFiveDown
        default:
            return .flat
        }
    }
    
    private func generateSerialNumber(from uid: Data) -> String {
        // Libre serial number encoding from UID
        let chars = "0123456789ACDEFGHJKLMNPQRTUVWXYZ"
        var serial = ""
        
        if uid.count >= 8 {
            // Extract 5 bytes that encode the serial
            let bytes = [uid[5], uid[6], uid[7], uid[3], uid[4]]
            var value: UInt64 = 0
            for byte in bytes {
                value = (value << 8) | UInt64(byte)
            }
            
            // Decode to base-32 characters
            for _ in 0..<10 {
                let index = Int(value % 32)
                serial = String(chars[chars.index(chars.startIndex, offsetBy: index)]) + serial
                value /= 32
            }
        }
        
        return serial
    }
}

// MARK: - Miaomiao Errors

/// Miaomiao-specific errors
public enum MiaomiaoError: Error, Sendable, LocalizedError {
    case packetTooShort
    case invalidPacketType
    case checksumMismatch
    case decryptionFailed
    case sensorExpired
    case sensorWarmingUp
    
    public var errorDescription: String? {
        switch self {
        case .packetTooShort:
            return "Received incomplete data from Miaomiao transmitter."
        case .invalidPacketType:
            return "Invalid packet type from Miaomiao transmitter."
        case .checksumMismatch:
            return "Data checksum error from Miaomiao transmitter."
        case .decryptionFailed:
            return "Failed to decrypt Libre sensor data."
        case .sensorExpired:
            return "The Libre sensor has expired."
        case .sensorWarmingUp:
            return "The Libre sensor is still warming up."
        }
    }
}
