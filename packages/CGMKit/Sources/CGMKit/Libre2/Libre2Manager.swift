// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre2Manager.swift
// CGMKit - Libre2
//
// FreeStyle Libre 2 CGM driver using BLEKit abstraction.
// Trace: PRD-004 REQ-CGM-002 CGM-021, LOG-ADOPT-003

import Foundation
import T1PalCore
import BLEKit

// MARK: - Libre2 Connection State

/// Libre 2 connection state
public enum Libre2ConnectionState: String, Sendable {
    case idle
    case scanning
    case connecting
    case unlocking
    case streaming
    case disconnecting
    case error
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension Libre2ConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .idle: return .disconnected
        case .scanning: return .scanning
        case .connecting, .unlocking, .disconnecting: return .connecting
        case .streaming: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Libre2 Sensor Info

/// Information about a Libre 2 sensor (from NFC activation)
public struct Libre2SensorInfo: Sendable, Codable {
    /// Sensor UID (8 bytes from NFC)
    public let sensorUID: Data
    
    /// Patch info (6 bytes from NFC command 0xa1)
    public let patchInfo: Data
    
    /// Timestamp when sensor was enabled
    public let enableTime: UInt32
    
    /// Serial number (derived from UID)
    public let serialNumber: String?
    
    /// Sensor type
    public let sensorType: Libre2SensorType
    
    public init(
        sensorUID: Data,
        patchInfo: Data,
        enableTime: UInt32,
        serialNumber: String? = nil,
        sensorType: Libre2SensorType = .libre2
    ) {
        self.sensorUID = sensorUID
        self.patchInfo = patchInfo
        self.enableTime = enableTime
        self.serialNumber = serialNumber
        self.sensorType = sensorType
    }
}

/// Libre sensor type
public enum Libre2SensorType: String, Sendable, Codable {
    case libre2
    case libreUS14day
    case libre3  // Future
}

// MARK: - Libre2 Manager

/// FreeStyle Libre 2 CGM Manager
///
/// Full Libre 2 BLE driver using BLEKit abstraction.
/// Requires NFC-scanned sensor info for authentication.
/// Can be used with MockBLE for testing or real BLE implementations.
public actor Libre2Manager: CGMManagerProtocol {
    
    // MARK: - CGMManagerProtocol
    
    public let displayName = "FreeStyle Libre 2"
    public let cgmType = CGMType.libre2
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    // MARK: - Libre2-Specific
    
    /// Current connection state
    public private(set) var connectionState: Libre2ConnectionState = .idle
    
    /// Connection state change callback
    public var onConnectionStateChanged: (@Sendable (Libre2ConnectionState) -> Void)?
    
    /// Sensor information (from NFC)
    public let sensorInfo: Libre2SensorInfo
    
    /// Unlock counter (increments each connection)
    public private(set) var unlockCount: UInt16 = 0
    
    // MARK: - Private
    
    private let central: any BLECentralProtocol
    private var peripheral: (any BLEPeripheralProtocol)?
    private var scanTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    
    // Discovered characteristics
    private var writeCharacteristic: BLECharacteristic?
    private var notifyCharacteristic: BLECharacteristic?
    
    // Fault injection for testing
    private var faultInjector: LibreFaultInjector?
    
    // Protocol logger for diagnostic tracing. Trace: LIBRE-DIAG-001
    private var protocolLogger: Libre2ProtocolLogger?
    
    // Factory calibration info (from NFC FRAM scan). Trace: LIBRE-IMPL-007
    private var calibrationInfo: LibreCalibrationInfo?
    
    // PROD-HARDEN-032: Whether simulation is allowed
    private let allowSimulation: Bool
    
    // MARK: - Initialization
    
    /// Create a Libre2 manager with sensor info and BLE central.
    /// - Parameters:
    ///   - sensorInfo: Sensor information from NFC scan
    ///   - central: BLE central implementation (real or mock)
    ///   - initialUnlockCount: Initial unlock counter value (for persistence). Trace: BLE-QUIRK-003
    ///   - faultInjector: Optional fault injector for testing (default: nil). Trace: LIBRE-FIX-015
    ///   - protocolLogger: Optional protocol logger for diagnostic tracing (default: nil). Trace: LIBRE-DIAG-001
    ///   - calibrationInfo: Optional factory calibration info (default: nil). Trace: LIBRE-IMPL-007
    ///   - allowSimulation: Allow simulated BLE central (default: false for production safety)
    public init(
        sensorInfo: Libre2SensorInfo,
        central: any BLECentralProtocol,
        initialUnlockCount: UInt16 = 0,
        faultInjector: LibreFaultInjector? = nil,
        protocolLogger: Libre2ProtocolLogger? = nil,
        calibrationInfo: LibreCalibrationInfo? = nil,
        allowSimulation: Bool = false
    ) {
        self.sensorInfo = sensorInfo
        self.central = central
        self.unlockCount = initialUnlockCount
        self.faultInjector = faultInjector
        self.protocolLogger = protocolLogger
        self.calibrationInfo = calibrationInfo
        self.allowSimulation = allowSimulation
        CGMLogger.general.info("Libre2Manager: initialized with sensor \(sensorInfo.serialNumber ?? "unknown"), unlockCount=\(initialUnlockCount), hasCalibration=\(calibrationInfo != nil)")
        
        // Note: Protocol logger configured asynchronously via setProtocolLogger(). Trace: LIBRE-DIAG-001
    }
    
    /// Current unlock counter value for persistence.
    /// Save this value and pass to initialUnlockCount on next app launch.
    /// Trace: BLE-QUIRK-003
    public var persistableUnlockCount: UInt16 { unlockCount }
    
    /// Set factory calibration info for accurate glucose conversion.
    /// Call this after extracting calibration from NFC FRAM scan.
    /// Trace: LIBRE-IMPL-007
    public func setCalibrationInfo(_ info: LibreCalibrationInfo) {
        self.calibrationInfo = info
        CGMLogger.general.info("Libre2Manager: calibration info set (i2=\(info.i2), i3=\(info.i3), i4=\(info.i4))")
    }
    
    /// Check if factory calibration is available for accurate glucose conversion.
    /// Trace: LIBRE-IMPL-007
    public var hasCalibration: Bool { calibrationInfo != nil }
    
    // MARK: - CGMManagerProtocol Implementation
    
    public func startScanning() async throws {
        // PROD-HARDEN-032: Validate simulation settings before starting
        try validateBLECentral(central, allowSimulation: allowSimulation, component: "Libre2Manager")
        
        guard connectionState == .idle || connectionState == .error else {
            return
        }
        
        let state = await central.state
        guard state == .poweredOn else {
            setConnectionState(.error)
            await protocolLogger?.log(.sensorDisconnected, error: "Bluetooth unavailable")
            throw CGMError.bluetoothUnavailable
        }
        
        setConnectionState(.scanning)
        
        scanTask = Task {
            do {
                // Scan for Libre 2 devices (FDE3 service or ABBOTT name)
                for try await result in central.scan(for: [.libre2Service]) {
                    // Check if name matches ABBOTT pattern
                    if let name = result.advertisement.localName,
                       name.hasPrefix("ABBOTT") || name.contains(sensorInfo.serialNumber ?? "") {
                        // Found our sensor. Trace: LIBRE-DIAG-001
                        await protocolLogger?.logSensorLifecycle(
                            .sensorDiscovered,
                            sensorUID: sensorInfo.sensorUID,
                            sensorType: sensorInfo.sensorType.rawValue
                        )
                        try await connectToDevice(result.peripheral)
                        break
                    }
                }
            } catch {
                setConnectionState(.error)
                await protocolLogger?.log(.sensorDisconnected, error: error.localizedDescription)
                onError?(.connectionFailed)
            }
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
    }
    
    public func disconnect() async {
        CGMLogger.general.info("Libre2Manager: Disconnecting")
        await protocolLogger?.logSensorLifecycle(.sensorDisconnected)
        scanTask?.cancel()
        streamTask?.cancel()
        
        if let peripheral = peripheral {
            await central.disconnect(peripheral)
        }
        
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        
        setConnectionState(.idle)
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    // MARK: - Connection Flow
    
    private func connectToDevice(_ peripheralInfo: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        CGMLogger.transmitter.info("Libre2Manager: Connecting to \(self.sensorInfo.serialNumber ?? "unknown")")
        
        do {
            peripheral = try await central.connect(to: peripheralInfo)
            
            guard let peripheral = peripheral else {
                await protocolLogger?.log(.sensorDisconnected, error: "Connection failed - no peripheral")
                throw CGMError.connectionFailed
            }
            
            // Log successful connection. Trace: LIBRE-DIAG-001
            await protocolLogger?.logSensorLifecycle(.sensorConnected, sensorUID: sensorInfo.sensorUID)
            
            // Discover Libre 2 service
            let services = try await peripheral.discoverServices([.libre2Service])
            
            guard let service = services.first(where: { $0.uuid == .libre2Service }) else {
                await protocolLogger?.log(.sensorDisconnected, error: "Libre2 service not found")
                throw CGMError.sensorNotFound
            }
            
            // Discover characteristics
            let characteristics = try await peripheral.discoverCharacteristics(
                [.libre2WriteCharacteristic, .libre2NotifyCharacteristic],
                for: service
            )
            
            writeCharacteristic = characteristics.first { $0.uuid == .libre2WriteCharacteristic }
            notifyCharacteristic = characteristics.first { $0.uuid == .libre2NotifyCharacteristic }
            
            guard writeCharacteristic != nil, notifyCharacteristic != nil else {
                await protocolLogger?.log(.sensorDisconnected, error: "Required characteristics not found")
                throw CGMError.sensorNotFound
            }
            
            // Unlock sensor for streaming
            try await unlockSensor()
            
            // Start streaming
            try await startStreaming()
            
        } catch {
            CGMLogger.general.error("Libre2Manager: Connection failed - \(error.localizedDescription)")
            await protocolLogger?.log(.sensorDisconnected, error: error.localizedDescription)
            setConnectionState(.error)
            onError?(.connectionFailed)
            throw error
        }
    }
    
    private func unlockSensor() async throws {
        guard let peripheral = peripheral,
              let writeChar = writeCharacteristic else {
            await protocolLogger?.log(.bleUnlockFailed, error: "No peripheral or write characteristic")
            throw CGMError.connectionFailed
        }
        
        setConnectionState(.unlocking)
        CGMLogger.sensor.info("Libre2Manager: Unlocking sensor for streaming")
        
        // Generate unlock payload. Trace: LIBRE-DIAG-001
        unlockCount += 1
        let unlockPayload = Libre2Crypto.streamingUnlockPayload(
            sensorUID: sensorInfo.sensorUID,
            patchInfo: sensorInfo.patchInfo,
            enableTime: sensorInfo.enableTime,
            unlockCount: unlockCount
        )
        
        // Log unlock payload computation. Trace: LIBRE-DIAG-001
        await protocolLogger?.log(
            .bleUnlockPayloadComputed,
            computedBytes: Data(unlockPayload),
            message: "unlockCount=\(unlockCount), enableTime=\(sensorInfo.enableTime)"
        )
        await protocolLogger?.log(
            .unlockCounterIncremented,
            message: "unlockCount=\(unlockCount)"
        )
        
        // Write unlock command
        try await peripheral.writeValue(Data(unlockPayload), for: writeChar, type: .withResponse)
        
        // Log unlock success. Trace: LIBRE-DIAG-001
        await protocolLogger?.logUnlock(
            enableTime: sensorInfo.enableTime,
            unlockCount: Int(unlockCount),
            payload: Data(unlockPayload),
            success: true
        )
        
        CGMLogger.sensor.sensorStarted(serialNumber: self.sensorInfo.serialNumber, insertionDate: Date())
    }
    
    private func startStreaming() async throws {
        guard let peripheral = peripheral,
              let notifyChar = notifyCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        setConnectionState(.streaming)
        CGMLogger.general.info("Libre2Manager: Started streaming glucose data")
        sensorState = .active
        onSensorStateChanged?(.active)
        
        streamTask = Task {
            do {
                for try await data in peripheral.subscribe(to: notifyChar) {
                    await processNotification(data)
                }
            } catch {
                CGMLogger.general.error("Libre2Manager: Stream error - \(error.localizedDescription)")
                await protocolLogger?.log(.bleDataReceived, error: error.localizedDescription)
                setConnectionState(.error)
                onError?(.dataUnavailable)
            }
        }
    }
    
    // MARK: - Data Processing
    
    private func processNotification(_ data: Data) async {
        guard data.count >= 46 else {
            await protocolLogger?.log(.bleDataReceived, rawBytes: data, message: "Packet too small (\(data.count) bytes)")
            return
        }
        
        // Log received data. Trace: LIBRE-DIAG-001
        await protocolLogger?.log(.bleDataReceived, rawBytes: data, message: "\(data.count) bytes")
        
        do {
            // Decrypt the notification
            let sensorUID = [UInt8](sensorInfo.sensorUID)
            let encryptedData = [UInt8](data)
            
            let decrypted = try Libre2Crypto.decryptBLE(
                sensorUID: sensorUID,
                data: encryptedData
            )
            
            // Log decryption success. Trace: LIBRE-DIAG-001
            await protocolLogger?.log(.bleDataDecrypted, computedBytes: Data(decrypted))
            
            // Parse glucose data
            if let reading = parseGlucoseData(decrypted) {
                CGMLogger.readings.glucoseReading(
                    value: reading.glucose,
                    trend: reading.trend.rawValue,
                    timestamp: reading.timestamp
                )
                
                // Log glucose extraction. Trace: LIBRE-DIAG-001
                await protocolLogger?.logGlucose(
                    rawValue: UInt16(reading.glucose * 8.5),
                    calibratedValue: reading.glucose,
                    calibrationFactor: 8.5,
                    trend: reading.trend.rawValue
                )
                
                latestReading = reading
                onReadingReceived?(reading)
            } else {
                await protocolLogger?.log(.bleDataParsed, error: "Failed to parse glucose data")
            }
            
        } catch {
            // CRC mismatch or decryption error - skip this packet
            await protocolLogger?.log(.crcFailed, rawBytes: data, error: error.localizedDescription)
        }
    }
    
    private func parseGlucoseData(_ data: [UInt8]) -> GlucoseReading? {
        guard data.count >= 42 else {
            return nil
        }
        
        // Parse trend data (first 7 measurements, 1-minute intervals)
        // Each measurement is 6 bytes at positions based on bit offsets
        
        // Get the most recent glucose value using proper bit extraction
        // Source: LibreTransmitter/Measurement.swift lines 101-109
        let rawGlucose = readBits(data, byteOffset: 0, bitOffset: 0, bitCount: 14)
        
        guard rawGlucose > 0 else {
            return nil
        }
        
        // Convert raw to mg/dL using factory calibration if available
        // Trace: LIBRE-IMPL-007
        let glucose: Double
        if let calibration = calibrationInfo,
           let measurement = LibreRawMeasurement.extract(from: Array(data[0..<min(6, data.count)])) {
            // Use full temperature-compensated calibration algorithm
            glucose = LibreGlucoseCalculator.glucoseValueFromRaw(
                measurement: measurement,
                calibration: calibration
            )
            CGMLogger.general.debug("Libre2Manager: using calibrated glucose \(glucose) from raw \(rawGlucose)")
        } else {
            // Fallback: simple linear calibration (less accurate)
            glucose = LibreGlucoseCalculator.glucoseValueSimple(rawGlucose: rawGlucose)
            CGMLogger.general.debug("Libre2Manager: using simple glucose \(glucose) from raw \(rawGlucose) (no calibration)")
        }
        
        // Calculate trend from multiple readings if available
        let trend = calculateTrend(from: data)
        
        return GlucoseReading(
            glucose: glucose,
            timestamp: Date(),
            trend: trend,
            source: "Libre2"
        )
    }
    
    private func calculateTrend(from data: [UInt8]) -> GlucoseTrend {
        // Extract last 3 glucose values to calculate trend
        var glucoseValues: [Int] = []
        
        for i in 0..<3 {
            let raw = readBits(data, byteOffset: i * 4, bitOffset: 0, bitCount: 14)
            if raw > 0 {
                glucoseValues.append(raw)
            }
        }
        
        guard glucoseValues.count >= 2 else {
            return .notComputable
        }
        
        // Calculate rate of change (mg/dL per minute)
        let delta = Double(glucoseValues[0] - glucoseValues[1]) / 8.5
        
        switch delta {
        case ..<(-3): return .doubleDown
        case -3..<(-2): return .singleDown
        case -2..<(-1): return .fortyFiveDown
        case -1...1: return .flat
        case 1..<2: return .fortyFiveUp
        case 2..<3: return .singleUp
        default: return .doubleUp
        }
    }
    
    // MARK: - Helpers
    
    private func setConnectionState(_ state: Libre2ConnectionState) {
        let oldState = connectionState
        connectionState = state
        CGMLogger.general.info("Libre2Manager: \(oldState.rawValue) → \(state.rawValue)")
        onConnectionStateChanged?(state)
    }
    
    /// Read bits from byte array (little-endian)
    private func readBits(_ buffer: [UInt8], byteOffset: Int, bitOffset: Int, bitCount: Int) -> Int {
        guard bitCount > 0 else { return 0 }
        
        var result = 0
        for i in 0..<bitCount {
            let totalBitOffset = byteOffset * 8 + bitOffset + i
            let byte = totalBitOffset / 8
            let bit = totalBitOffset % 8
            
            guard byte < buffer.count else { break }
            
            if (Int(buffer[byte]) >> bit) & 0x1 == 1 {
                result = result | (1 << i)
            }
        }
        return result
    }
    
    // MARK: - Fault Injection
    
    /// Set fault injector for testing. Trace: LIBRE-FIX-015
    public func setFaultInjector(_ injector: LibreFaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Current fault injector. Trace: LIBRE-FIX-015
    public var currentFaultInjector: LibreFaultInjector? {
        faultInjector
    }
    
    // MARK: - Protocol Logger
    
    /// Set protocol logger for diagnostic tracing. Trace: LIBRE-DIAG-001
    public func setProtocolLogger(_ logger: Libre2ProtocolLogger?) async {
        self.protocolLogger = logger
        await logger?.setSensorUID(sensorInfo.sensorUID)
        await logger?.log(.sensorTypeDetected, message: sensorInfo.sensorType.rawValue)
    }
    
    /// Current protocol logger. Trace: LIBRE-DIAG-001
    public var currentProtocolLogger: Libre2ProtocolLogger? {
        protocolLogger
    }
}

// MARK: - Libre2 Errors

/// Libre2-specific errors
public enum Libre2Error: Error, Sendable, LocalizedError {
    case nfcRequired
    case sensorNotActivated
    case unlockFailed
    case decryptionFailed
    case invalidSensorInfo
    
    public var errorDescription: String? {
        switch self {
        case .nfcRequired:
            return "NFC scan required to activate Libre 2 sensor."
        case .sensorNotActivated:
            return "Libre 2 sensor is not yet activated. Please scan with NFC first."
        case .unlockFailed:
            return "Failed to unlock Libre 2 Bluetooth streaming."
        case .decryptionFailed:
            return "Failed to decrypt Libre 2 glucose data."
        case .invalidSensorInfo:
            return "Invalid Libre 2 sensor information."
        }
    }
}

// MARK: - Libre2Error + T1PalErrorProtocol

extension Libre2Error: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .cgm }
    
    public var code: String {
        switch self {
        case .nfcRequired: return "LIBRE2-NFC-001"
        case .sensorNotActivated: return "LIBRE2-SENSOR-001"
        case .unlockFailed: return "LIBRE2-BLE-001"
        case .decryptionFailed: return "LIBRE2-CRYPTO-001"
        case .invalidSensorInfo: return "LIBRE2-SENSOR-002"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .nfcRequired: return .warning
        case .sensorNotActivated: return .error
        case .unlockFailed: return .error
        case .decryptionFailed: return .critical
        case .invalidSensorInfo: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .nfcRequired: return .checkDevice  // User needs to scan
        case .sensorNotActivated: return .checkDevice
        case .unlockFailed: return .retry
        case .decryptionFailed: return .contactSupport
        case .invalidSensorInfo: return .contactSupport
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown Libre 2 error"
    }
}
