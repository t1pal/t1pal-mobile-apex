// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6Messages.swift
// CGMKit - DexcomG6
//
// Dexcom G6 BLE message types for communication with transmitter.
// Trace: PRD-008 REQ-BLE-007

import Foundation

// MARK: - CRC16 Support

/// CRC-CCITT (XModem) implementation for Dexcom protocol
/// Reference: http://www.lammertbies.nl/comm/info/crc-calculation.html
extension Collection where Element == UInt8 {
    /// Compute CRC-CCITT (XModem) checksum
    var crc16: UInt16 {
        var crc: UInt16 = 0
        for byte in self {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = crc << 1 ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}

extension Data {
    /// Validate CRC16 in last 2 bytes
    var isCRCValid: Bool {
        guard count >= 2 else { return false }
        let computed = dropLast(2).crc16
        let stored = suffix(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        return computed == stored
    }
    
    /// Append CRC16 to data
    func appendingCRC() -> Data {
        var data = self
        let crc = crc16
        Swift.withUnsafeBytes(of: crc) { data.append(contentsOf: $0) }
        return data
    }
}

// MARK: - Message Opcodes

/// Dexcom G6 message opcodes
public enum G6Opcode: UInt8, Sendable {
    // Authentication
    case authRequestTx = 0x01
    case authRequest2Tx = 0x02  // G6+ (Firefly)
    case authRequestRx = 0x03   // Server response: tokenHash + challenge (CGMBLEKit naming)
    case authChallengeTx = 0x04
    case authChallengeRx = 0x05 // Auth status (authenticated + bonded)
    case keepAlive = 0x06       // Also authStatusRx context
    case bondRequest = 0x07
    
    // Control
    case disconnectTx = 0x09
    
    // App Level Key (G6+/Firefly)
    // Trace: CGM-063, CGM-064, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    case changeAppLevelKeyTx = 0x0f
    case appLevelKeyAcceptedRx = 0x10
    
    case glucoseG6Tx = 0x4E     // G6-specific glucose request (Control Point)
    case glucoseG6Rx = 0x4F     // G6-specific glucose response (EGV message)
    case glucoseTx = 0x30
    case glucoseRx = 0x31
    case calibrationDataTx = 0x32
    case calibrationDataRx = 0x33
    case calibrateGlucoseTx = 0x34  // G6-DIRECT-033: Submit calibration
    case calibrateGlucoseRx = 0x35  // G6-DIRECT-033: Calibration response
    case glucoseBackfillTx = 0x50
    case glucoseBackfillRx = 0x51
    
    // Transmitter info
    case transmitterTimeTx = 0x24
    case transmitterTimeRx = 0x25
    case firmwareVersionTx = 0x20
    case firmwareVersionRx = 0x21
    case batteryStatusTx = 0x22
    case batteryStatusRx = 0x23
    
    // Session
    case sensorSessionStartTx = 0x26
    case sensorSessionStartRx = 0x27
    case sensorSessionStopTx = 0x28
    case sensorSessionStopRx = 0x29
}

// MARK: - Auth Messages

/// Connection slot for G6 authentication
/// Trace: CGM-052, CGM-048
public enum G6Slot: UInt8, Sendable, CaseIterable, Codable {
    /// Medical slot (0x01) - typically used by dedicated receiver
    case medical = 0x01
    /// Consumer slot (0x02) - used by phone apps (default)
    case consumer = 0x02
    /// Wearable slot (0x03) - used by smartwatches (G7/Firefly+)
    case wearable = 0x03
    
    /// Auto selection - consumer for phones, wearable for watches
    public static var auto: G6Slot {
        #if os(watchOS)
        return .wearable
        #else
        return .consumer
        #endif
    }
    
    /// Human-readable name
    public var displayName: String {
        switch self {
        case .medical: return "Medical"
        case .consumer: return "Consumer"
        case .wearable: return "Wearable"
        }
    }
    
    /// Description for UI
    public var description: String {
        switch self {
        case .medical: return "Dedicated receiver slot"
        case .consumer: return "Phone app slot"
        case .wearable: return "Smartwatch slot"
        }
    }
}

/// Authentication request message (outgoing)
/// Supports both G6 (opcode 0x01) and G6+ Firefly (opcode 0x02)
/// Trace: CGM-052 - Added configurable slot parameter
public struct AuthRequestTxMessage: Sendable {
    public let opcode: UInt8
    public let singleUseToken: Data
    public let slot: G6Slot
    
    /// Create auth request for standard G6 with default consumer slot
    public init(singleUseToken: Data) {
        self.opcode = G6Opcode.authRequestTx.rawValue
        self.singleUseToken = singleUseToken
        self.slot = .consumer
    }
    
    /// Create auth request with specific opcode (for G6+ Firefly) and slot
    public init(singleUseToken: Data, generation: DexcomGeneration, slot: G6Slot = .consumer) {
        switch generation {
        case .g6Plus:
            self.opcode = G6Opcode.authRequest2Tx.rawValue
        default:
            self.opcode = G6Opcode.authRequestTx.rawValue
        }
        self.singleUseToken = singleUseToken
        self.slot = slot
    }
    
    public var data: Data {
        var message = Data([opcode])
        message.append(singleUseToken)
        message.append(slot.rawValue)
        return message
    }
}

/// Authentication request response (incoming) - server sends tokenHash + challenge
/// Note: CGMBLEKit calls this AuthRequestRxMessage (opcode 0x03)
public struct AuthChallengeRxMessage: Sendable {
    public let opcode: UInt8
    public let tokenHash: Data
    public let challenge: Data
    
    public init?(data: Data) {
        guard data.count >= 17 else { return nil }
        guard data[0] == G6Opcode.authRequestRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.tokenHash = data.subdata(in: 1..<9)
        self.challenge = data.subdata(in: 9..<17)
    }
}

/// Authentication challenge response (outgoing)
public struct AuthChallengeTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.authChallengeTx.rawValue
    public let challengeResponse: Data
    
    public init(challengeResponse: Data) {
        self.challengeResponse = challengeResponse
    }
    
    public var data: Data {
        var message = Data([opcode])
        message.append(challengeResponse)
        return message
    }
}

/// Authentication status (incoming)
/// Note: CGMBLEKit calls this AuthChallengeRxMessage (opcode 0x05)
public struct AuthStatusRxMessage: Sendable {
    public let opcode: UInt8
    public let authenticated: Bool
    public let bonded: Bool
    
    public init?(data: Data) {
        guard data.count >= 3 else { return nil }
        guard data[0] == G6Opcode.authChallengeRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.authenticated = data[1] == 0x01
        self.bonded = data[2] == 0x01
    }
}

// MARK: - App Level Key Messages

/// Change App Level Key request (outgoing)
/// Sets a 16-byte cryptographic key on the transmitter for persistent authentication
/// Trace: CGM-064, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
public struct ChangeAppLevelKeyTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.changeAppLevelKeyTx.rawValue
    public let key: Data
    
    /// Initialize with a 16-byte key
    /// - Parameter key: The 16-byte App Level Key to set on the transmitter
    public init(key: Data) {
        precondition(key.count == 16, "App Level Key must be exactly 16 bytes")
        self.key = key
    }
    
    /// Generate a random App Level Key
    public static func generateRandomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }
    
    public var data: Data {
        var result = Data([opcode])
        result.append(key)
        return result
    }
}

/// App Level Key accepted response (incoming)
/// Confirms the transmitter has accepted the new App Level Key
/// Trace: CGM-064, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
public struct AppLevelKeyAcceptedRxMessage: Sendable {
    public let opcode: UInt8
    public let accepted: Bool
    
    public init?(data: Data) {
        guard data.count >= 1 else { return nil }
        guard data[0] == G6Opcode.appLevelKeyAcceptedRx.rawValue else { return nil }
        
        self.opcode = data[0]
        // If we receive the opcode, the key was accepted
        // Additional status bytes may be present but are not documented
        self.accepted = true
    }
}

// MARK: - Glucose Messages

/// Glucose reading request (outgoing) - Legacy format without CRC
/// Note: Use GlucoseG6TxMessage for real G6 hardware which requires CRC
public struct GlucoseTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.glucoseTx.rawValue
    
    public var data: Data {
        Data([opcode])
    }
}

/// G6-specific glucose reading request (outgoing) with CRC
/// Trace: CGM-050 - Hardware requires [opcode][CRC16] = 3 bytes
/// Uses opcode 0x4E for Control Point writes
public struct GlucoseG6TxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.glucoseG6Tx.rawValue
    
    public init() {}
    
    /// Data with CRC16 appended (3 bytes total)
    public var data: Data {
        Data([opcode]).appendingCRC()
    }
}

/// Glucose reading response (incoming)
public struct GlucoseRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let sequence: UInt32
    public let timestamp: UInt32
    public let glucoseValue: UInt16
    public let glucoseIsDisplayOnly: Bool
    public let state: UInt8
    public let trend: Int8
    
    public init?(data: Data) {
        // Loop format: 16 bytes minimum with CRC
        // [opcode:1][status:1][sequence:4][timestamp:4][glucose:2][state:1][trend:1][crc:2]
        guard data.count >= 14 else { return nil }
        // Accept both glucoseRx (0x31) and glucoseG6Rx (0x4F)
        guard data[0] == G6Opcode.glucoseRx.rawValue || data[0] == G6Opcode.glucoseG6Rx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.sequence = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.timestamp = data.subdata(in: 6..<10).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        
        // Glucose is masked - high nibble indicates display-only
        let glucoseBytes = data.subdata(in: 10..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.glucoseIsDisplayOnly = (glucoseBytes & 0xF000) > 0
        self.glucoseValue = glucoseBytes & 0x0FFF
        
        self.state = data[12]
        self.trend = Int8(bitPattern: data[13])
    }
    
    // Legacy property for compatibility
    public var predictedGlucose: UInt16 { glucoseValue }
    
    /// Glucose value in mg/dL
    public var glucose: Double {
        Double(glucoseValue)
    }
    
    /// Parsed calibration state (G6-DIRECT-030)
    public var calibrationState: G6CalibrationState {
        G6CalibrationState(fromByte: state)
    }
    
    /// Whether this is a valid glucose reading
    public var isValid: Bool {
        glucoseValue > 0 && glucoseValue < 500 && calibrationState.hasReliableGlucose
    }
}

// MARK: - G5 Compatible Glucose Message (CGMBLEKit Format)

/// G5-compatible glucose reading response (CGMBLEKit format)
/// This matches the real G5/G6 protocol format from CGMBLEKit
/// Trace: G6-SYNTH-007
public struct G5GlucoseRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let sequence: UInt32
    public let timestamp: UInt32
    public let glucoseIsDisplayOnly: Bool
    public let glucose: UInt16
    public let state: UInt8
    public let trend: Int8
    
    public init?(data: Data) {
        // Minimum 14 bytes required (16 with CRC)
        guard data.count >= 14 else { return nil }
        guard data[0] == G6Opcode.glucoseRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.sequence = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.timestamp = data.subdata(in: 6..<10).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        
        // bytes[10-11]: glucose with displayOnly flag in upper bits
        let glucoseBytes = data.subdata(in: 10..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.glucoseIsDisplayOnly = (glucoseBytes & 0xF000) > 0
        self.glucose = glucoseBytes & 0x0FFF
        
        // byte[12]: state
        self.state = data[12]
        
        // byte[13]: trend (signed Int8)
        self.trend = Int8(bitPattern: data[13])
    }
    
    /// Glucose value in mg/dL
    public var glucoseValue: Double {
        Double(glucose)
    }
    
    /// Parsed calibration state (G6-DIRECT-030)
    public var calibrationState: G6CalibrationState {
        G6CalibrationState(fromByte: state)
    }
    
    /// Whether this is a valid glucose reading
    public var isValid: Bool {
        glucose > 0 && glucose < 500 && calibrationState.hasReliableGlucose
    }
}

// MARK: - Backfill Messages

/// Glucose backfill request (outgoing)
/// Format: [opcode:1][byte1:1][byte2:1][identifier:1][startTime:4][endTime:4][length:4][backfillCRC:2][messageCRC:2] = 20 bytes
/// Trace: SESSION-G6-003
public struct GlucoseBackfillTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.glucoseBackfillTx.rawValue
    public let byte1: UInt8
    public let byte2: UInt8
    public let identifier: UInt8
    public let startTime: UInt32
    public let endTime: UInt32
    public let length: UInt32
    public let backfillCRC: UInt16
    
    /// Create a backfill request
    /// - Parameters:
    ///   - startTime: Session time to start backfill from
    ///   - endTime: Session time to end backfill at
    ///   - byte1: Control byte 1 (typically 5)
    ///   - byte2: Control byte 2 (typically 2)
    ///   - identifier: Transaction identifier (increments per request)
    public init(startTime: UInt32, endTime: UInt32, byte1: UInt8 = 5, byte2: UInt8 = 2, identifier: UInt8 = 0) {
        self.startTime = startTime
        self.endTime = endTime
        self.byte1 = byte1
        self.byte2 = byte2
        self.identifier = identifier
        self.length = 0
        self.backfillCRC = 0
    }
    
    /// Raw data for transmission (without CRC - caller must add)
    public var dataWithoutCRC: Data {
        var message = Data([opcode, byte1, byte2, identifier])
        withUnsafeBytes(of: startTime) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: endTime) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: length) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: backfillCRC) { message.append(contentsOf: $0) }
        return message
    }
    
    /// Raw data for transmission (with CRC16 appended)
    public var data: Data {
        var message = dataWithoutCRC
        let crc = message.crc16
        withUnsafeBytes(of: crc) { message.append(contentsOf: $0) }
        return message
    }
}

/// Glucose backfill response (incoming)
/// Format: [opcode:1][status:1][backfillStatus:1][identifier:1][startTime:4][endTime:4][bufferLength:4][bufferCRC:2][messageCRC:2] = 20 bytes
/// Trace: SESSION-G6-003
public struct GlucoseBackfillRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let backfillStatus: UInt8
    public let identifier: UInt8
    public let startTime: UInt32
    public let endTime: UInt32
    public let bufferLength: UInt32
    public let bufferCRC: UInt16
    
    public init?(data: Data) {
        // Full message is 20 bytes with CRC
        guard data.count >= 18 else { return nil }
        guard data[0] == G6Opcode.glucoseBackfillRx.rawValue else { return nil }
        
        // Validate CRC if full 20-byte message
        if data.count >= 20 {
            let messageCRC = data.subdata(in: 18..<20).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let computed = data.subdata(in: 0..<18).crc16
            guard messageCRC == computed else { return nil }
        }
        
        self.opcode = data[0]
        self.status = data[1]
        self.backfillStatus = data[2]
        self.identifier = data[3]
        self.startTime = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.endTime = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.bufferLength = data.subdata(in: 12..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.bufferCRC = data.subdata(in: 16..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    }
    
    /// Whether the backfill request was accepted
    public var isSuccess: Bool {
        status == 0 && backfillStatus == 1
    }
}

/// Individual glucose reading from backfill data (8 bytes per reading)
/// Format: [timestamp:4][glucose:2 with displayOnly flag][state:1][trend:1]
/// Trace: SESSION-G6-003
public struct GlucoseSubMessage: Sendable, Equatable {
    public static let size = 8
    
    public let timestamp: UInt32
    public let glucoseIsDisplayOnly: Bool
    public let glucose: UInt16
    public let state: UInt8
    public let trend: Int8
    
    public init?(data: Data) {
        guard data.count >= GlucoseSubMessage.size else { return nil }
        
        // Ensure we work with the right byte range
        let start = data.startIndex
        
        // bytes[0-3]: timestamp (little-endian)
        self.timestamp = data.subdata(in: start..<(start + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        
        // bytes[4-5]: glucose with displayOnly flag in upper bits
        let glucoseBytes = data.subdata(in: (start + 4)..<(start + 6)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.glucoseIsDisplayOnly = (glucoseBytes & 0xF000) > 0
        self.glucose = glucoseBytes & 0x0FFF
        
        // byte[6]: state/calibration status
        self.state = data[start + 6]
        
        // byte[7]: trend (signed Int8)
        self.trend = Int8(bitPattern: data[start + 7])
    }
    
    /// Create from explicit values (for testing)
    public init(timestamp: UInt32, glucose: UInt16, glucoseIsDisplayOnly: Bool = false, state: UInt8, trend: Int8) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.glucoseIsDisplayOnly = glucoseIsDisplayOnly
        self.state = state
        self.trend = trend
    }
}

/// Buffer for accumulating backfill frames from BLE notifications
/// Frames arrive on the Backfill characteristic and must be reassembled
/// Trace: SESSION-G6-003
public struct GlucoseBackfillFrameBuffer: Sendable {
    public let identifier: UInt8
    private var frames: [Data] = []
    
    public init(identifier: UInt8) {
        self.identifier = identifier
    }
    
    /// Append a backfill frame (notification from Backfill characteristic)
    /// - Parameter frame: Raw frame data [frameIndex:1][identifier:1][payload:...]
    public mutating func append(_ frame: Data) {
        // Byte 0 is the frame index (1-based)
        // Byte 1 is the identifier (should match our session)
        guard frame.count > 2,
              frame[0] == frames.count + 1,
              frame[1] == identifier else {
            return
        }
        frames.append(frame)
    }
    
    /// Total bytes accumulated (including frame headers)
    public var count: Int {
        frames.reduce(0) { $0 + $1.count }
    }
    
    /// Number of frames received
    public var frameCount: Int {
        frames.count
    }
    
    /// CRC16 of all accumulated frame data
    public var crc16: UInt16 {
        frames.reduce(into: Data()) { $0.append($1) }.crc16
    }
    
    /// Parse accumulated frames into glucose readings
    /// Returns array of GlucoseSubMessage, one per 5-minute reading
    public var glucose: [GlucoseSubMessage] {
        // Drop the first 2 bytes (frame index + identifier) from each frame
        let data = frames.reduce(into: Data()) { $0.append($1.dropFirst(2)) }
        
        // Drop the first 4 bytes from the combined message (header bytes)
        // Byte 0-1: buffer header (observed: 0xbc46, 0x6e3c, etc.)
        // Byte 2-3: unknown (typically 0x0000)
        guard data.count >= 4 else { return [] }
        let glucoseData = data.dropFirst(4)
        
        // Parse 8-byte glucose submessages
        return stride(from: glucoseData.startIndex, to: glucoseData.endIndex, by: GlucoseSubMessage.size)
            .compactMap { index in
                let endIndex = index + GlucoseSubMessage.size
                guard glucoseData.endIndex >= endIndex else { return nil }
                return GlucoseSubMessage(data: glucoseData[index..<endIndex])
            }
    }
}

// MARK: - Calibration Messages (PROTO-G6-001)

/// Calibration data request (outgoing)
/// Reference: CGMBLEKit CalibrationDataTxMessage
/// Format: [opcode:1][messageCRC:2] = 3 bytes
public struct CalibrationDataTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.calibrationDataTx.rawValue
    
    public init() {}
    
    /// Raw data for transmission (without CRC)
    public var dataWithoutCRC: Data {
        Data([opcode])
    }
    
    /// Complete message with CRC
    public var data: Data {
        dataWithoutCRC.appendingCRC()
    }
}

/// Calibration data response (incoming)
/// Reference: CGMBLEKit CalibrationDataRxMessage
/// Format: [opcode:1][unknown:10][glucose:2][timestamp:4][messageCRC:2] = 19 bytes
/// - glucose is at bytes 11-12, lower 12 bits (masked with 0x0FFF)
/// - timestamp is at bytes 13-16 (session time in seconds)
/// Trace: PROTO-G6-001
public struct CalibrationDataRxMessage: Sendable {
    public static let expectedLength = 19
    
    public let opcode: UInt8
    /// Raw unknown bytes (positions 1-10)
    public let unknownData: Data
    /// Glucose value (lower 12 bits of bytes 11-12)
    public let glucose: UInt16
    /// Session timestamp (seconds since session start)
    public let timestamp: UInt32
    /// Original raw data for debugging
    public let rawData: Data
    
    /// Parse from raw BLE response
    /// - Parameter data: Raw 19-byte response data
    /// - Returns: Parsed message or nil if invalid
    public init?(data: Data) {
        guard data.count == Self.expectedLength else { return nil }
        guard data.isCRCValid else { return nil }
        guard data[0] == G6Opcode.calibrationDataRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.unknownData = data[1..<11]
        self.rawData = data
        
        // Glucose at bytes 11-12, little-endian, lower 12 bits
        let rawGlucose = UInt16(data[11]) | (UInt16(data[12]) << 8)
        self.glucose = rawGlucose & 0x0FFF
        
        // Timestamp at bytes 13-16, little-endian
        self.timestamp = UInt32(data[13]) |
                        (UInt32(data[14]) << 8) |
                        (UInt32(data[15]) << 16) |
                        (UInt32(data[16]) << 24)
    }
    
    /// Computed glucose value in mg/dL
    public var glucoseMgDl: Double {
        Double(glucose)
    }
    
    /// Whether calibration is valid (glucose > 0)
    public var isValid: Bool {
        glucose > 0
    }
    
    /// Raw data as hex string for debugging
    public var rawHex: String {
        rawData.map { String(format: "%02x", $0) }.joined()
    }
}

/// Calibration submission request (outgoing) - G6-DIRECT-033
/// Reference: CGMBLEKit CalibrateGlucoseTxMessage
/// Format: [opcode:1][glucose:2][time:4][messageCRC:2] = 9 bytes
/// - glucose: Calibration value in mg/dL (UInt16)
/// - time: Session time in seconds since transmitter activation (UInt32)
public struct CalibrateGlucoseTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.calibrateGlucoseTx.rawValue
    
    /// Glucose value for calibration in mg/dL
    public let glucose: UInt16
    
    /// Session time in seconds since transmitter activation
    public let time: UInt32
    
    /// Initialize calibration message
    /// - Parameters:
    ///   - glucose: Glucose value in mg/dL (e.g., from fingerstick)
    ///   - time: Session time in seconds since transmitter activation
    public init(glucose: UInt16, time: UInt32) {
        self.glucose = glucose
        self.time = time
    }
    
    /// Raw data for transmission (without CRC)
    public var dataWithoutCRC: Data {
        var data = Data([opcode])
        // Glucose (little-endian UInt16)
        data.append(UInt8(glucose & 0xFF))
        data.append(UInt8((glucose >> 8) & 0xFF))
        // Time (little-endian UInt32)
        data.append(UInt8(time & 0xFF))
        data.append(UInt8((time >> 8) & 0xFF))
        data.append(UInt8((time >> 16) & 0xFF))
        data.append(UInt8((time >> 24) & 0xFF))
        return data
    }
    
    /// Complete message with CRC
    public var data: Data {
        dataWithoutCRC.appendingCRC()
    }
}

/// Calibration submission response (incoming) - G6-DIRECT-033
/// Reference: CGMBLEKit CalibrateGlucoseRxMessage
/// Format: [opcode:1][status:1][?:1][messageCRC:2] = 5 bytes
/// The response is minimal - primarily confirms receipt of calibration
public struct CalibrateGlucoseRxMessage: Sendable {
    public static let expectedLength = 5
    
    public let opcode: UInt8
    public let status: UInt8
    public let reserved: UInt8
    
    /// Parse from raw BLE response
    /// - Parameter data: Raw 5-byte response data
    /// - Returns: Parsed message or nil if invalid
    public init?(data: Data) {
        guard data.count == Self.expectedLength else { return nil }
        guard data.isCRCValid else { return nil }
        guard data[0] == G6Opcode.calibrateGlucoseRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.reserved = data[2]
    }
    
    /// Whether calibration was accepted
    public var isSuccess: Bool {
        status == 0
    }
}

// MARK: - Transmitter Info Messages

/// Battery status request (outgoing)
public struct BatteryStatusTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.batteryStatusTx.rawValue
    
    public var data: Data {
        Data([opcode])
    }
}

/// Battery status response (incoming)
public struct BatteryStatusRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let voltageA: UInt16
    public let voltageB: UInt16
    public let resistance: UInt16
    public let runtime: UInt8
    public let temperature: UInt8
    
    public init?(data: Data) {
        guard data.count >= 10 else { return nil }
        guard data[0] == G6Opcode.batteryStatusRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.voltageA = data.subdata(in: 2..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.voltageB = data.subdata(in: 4..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.resistance = data.subdata(in: 6..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.runtime = data[8]
        self.temperature = data[9]
    }
    
    /// Battery is low
    public var isLow: Bool {
        voltageA < 300 || voltageB < 300
    }
}

/// Transmitter time request (outgoing)
public struct TransmitterTimeTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.transmitterTimeTx.rawValue
    
    public var data: Data {
        Data([opcode])
    }
}

/// Transmitter time response (incoming)
public struct TransmitterTimeRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let currentTime: UInt32
    public let sessionStartTime: UInt32
    
    public init?(data: Data) {
        guard data.count >= 10 else { return nil }
        guard data[0] == G6Opcode.transmitterTimeRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.currentTime = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.sessionStartTime = data.subdata(in: 6..<10).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    
    /// Session age in seconds
    /// Warning: May underflow if sessionStartTime is invalidSessionTime (0xFFFFFFFF)
    /// Always check hasActiveSession before using this value
    public var sessionAge: UInt32 {
        currentTime &- sessionStartTime  // Wrapping subtraction to allow underflow detection
    }
    
    /// Whether there is an active sensor session
    /// Returns false when sessionStartTime is the sentinel value (0xFFFFFFFF),
    /// indicating no session (sensor expired, stopped, failed, or not started).
    /// Trace: GAP-API-021 (future-dated entries fix)
    public var hasActiveSession: Bool {
        sessionStartTime != G6Constants.invalidSessionTime
    }
    
    /// Safe session age that returns nil if no active session
    /// Trace: GAP-API-021 (future-dated entries fix)
    public var safeSessionAge: UInt32? {
        guard hasActiveSession else { return nil }
        let age = sessionAge
        // Also check for unreasonable values from underflow
        guard age <= G6Constants.maxReasonableSessionAge else { return nil }
        return age
    }
}

/// Firmware version request (outgoing)
/// Trace: BLE-DIAG-002
public struct FirmwareVersionTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.firmwareVersionTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// Firmware version response (incoming)
/// Trace: BLE-DIAG-002
public struct FirmwareVersionRxMessage: Sendable {
    public let opcode: UInt8
    public let firmwareVersion: String
    public let bluetoothVersion: String?
    public let hardwareRevision: String?
    public let asicVersion: String?
    
    public init?(data: Data) {
        guard data.count >= 2 else { return nil }
        guard data[0] == G6Opcode.firmwareVersionRx.rawValue else { return nil }
        
        self.opcode = data[0]
        
        // Parse firmware string from remaining bytes
        let versionData = data.dropFirst()
        
        // G6 firmware response format varies by transmitter type
        // Common format: major.minor.patch as null-terminated strings
        // Some transmitters include Bluetooth/hardware versions
        if let parsed = Self.parseVersionStrings(from: versionData) {
            self.firmwareVersion = parsed.firmware
            self.bluetoothVersion = parsed.bluetooth
            self.hardwareRevision = parsed.hardware
            self.asicVersion = parsed.asic
        } else {
            // Fallback: treat entire payload as single version string
            self.firmwareVersion = String(data: versionData, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters) ?? "unknown"
            self.bluetoothVersion = nil
            self.hardwareRevision = nil
            self.asicVersion = nil
        }
    }
    
    /// Parse null-separated version strings
    private static func parseVersionStrings(from data: Data) -> (firmware: String, bluetooth: String?, hardware: String?, asic: String?)? {
        guard !data.isEmpty else { return nil }
        
        // Split by null bytes
        var strings: [String] = []
        var current = Data()
        
        for byte in data {
            if byte == 0 {
                if !current.isEmpty {
                    if let str = String(data: current, encoding: .utf8) {
                        strings.append(str)
                    }
                    current = Data()
                }
            } else {
                current.append(byte)
            }
        }
        
        // Handle last string without null terminator
        if !current.isEmpty, let str = String(data: current, encoding: .utf8) {
            strings.append(str)
        }
        
        guard !strings.isEmpty else { return nil }
        
        return (
            firmware: strings[0],
            bluetooth: strings.count > 1 ? strings[1] : nil,
            hardware: strings.count > 2 ? strings[2] : nil,
            asic: strings.count > 3 ? strings[3] : nil
        )
    }
    
    /// Summary string for display
    public var summary: String {
        var parts = [firmwareVersion]
        if let bt = bluetoothVersion { parts.append("BT:\(bt)") }
        if let hw = hardwareRevision { parts.append("HW:\(hw)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Session Messages

/// Session start request (outgoing)
/// Trace: G6-DIRECT-031 - Loop-compatible format with CRC
/// Format: [opcode:1][startTime:4][secondsSince1970:4][CRC:2] = 11 bytes
public struct SessionStartTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.sensorSessionStartTx.rawValue
    /// Time since transmitter activation in seconds
    public let startTime: UInt32
    /// Unix timestamp (seconds since 1970)
    public let secondsSince1970: UInt32
    
    public init(startTime: UInt32, secondsSince1970: UInt32) {
        self.startTime = startTime
        self.secondsSince1970 = secondsSince1970
    }
    
    /// Convenience initializer using dates
    /// - Parameters:
    ///   - sensorStartDate: When the sensor was physically inserted
    ///   - transmitterActivationDate: When the transmitter was first powered on
    public init(sensorStartDate: Date, transmitterActivationDate: Date) {
        self.startTime = UInt32(sensorStartDate.timeIntervalSince(transmitterActivationDate))
        self.secondsSince1970 = UInt32(sensorStartDate.timeIntervalSince1970)
    }
    
    public var data: Data {
        var message = Data([opcode])
        withUnsafeBytes(of: startTime) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: secondsSince1970) { message.append(contentsOf: $0) }
        return message.appendingCRC()
    }
}

/// Session start response (incoming)
/// G6-SYNTH-006: Parsing validated against Python g6_parsers.py parse_session_start_rx()
public struct SessionStartRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let received: UInt8
    public let requestedStartTime: UInt32
    public let sessionStartTime: UInt32
    public let transmitterTime: UInt32
    
    public init?(data: Data) {
        guard data.count >= 15 else { return nil }
        guard data[0] == G6Opcode.sensorSessionStartRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.received = data[2]
        self.requestedStartTime = data.subdata(in: 3..<7).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.sessionStartTime = data.subdata(in: 7..<11).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.transmitterTime = data.subdata(in: 11..<15).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    
    /// Whether the session was successfully started
    public var isSuccess: Bool {
        status == 0 && received == 1
    }
}

/// Session stop request (outgoing)
/// Trace: G6-DIRECT-032 - Loop-compatible format with CRC
/// Format: [opcode:1][stopTime:4][CRC:2] = 7 bytes
public struct SessionStopTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.sensorSessionStopTx.rawValue
    public let stopTime: UInt32
    
    public init(stopTime: UInt32) {
        self.stopTime = stopTime
    }
    
    /// Convenience initializer using dates
    /// - Parameters:
    ///   - stopDate: When to stop the session (typically now)
    ///   - transmitterActivationDate: When the transmitter was first powered on
    public init(stopDate: Date, transmitterActivationDate: Date) {
        self.stopTime = UInt32(stopDate.timeIntervalSince(transmitterActivationDate))
    }
    
    public var data: Data {
        var message = Data([opcode])
        withUnsafeBytes(of: stopTime) { message.append(contentsOf: $0) }
        return message.appendingCRC()
    }
}

/// Session stop response (incoming)
/// Trace: G6-DIRECT-032 - Loop-compatible format
/// Format: [opcode:1][status:1][received:1][sessionStopTime:4][sessionStartTime:4][transmitterTime:4][CRC:2] = 17 bytes
public struct SessionStopRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let received: UInt8
    public let sessionStopTime: UInt32
    public let sessionStartTime: UInt32
    public let transmitterTime: UInt32
    
    public init?(data: Data) {
        guard data.count >= 15 else { return nil }
        guard data[0] == G6Opcode.sensorSessionStopRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.received = data[2]
        self.sessionStopTime = data.subdata(in: 3..<7).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.sessionStartTime = data.subdata(in: 7..<11).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.transmitterTime = data.subdata(in: 11..<15).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    
    /// Whether the session was successfully stopped
    public var isSuccess: Bool {
        status == 0 && received == 1
    }
}

// MARK: - Control Messages

/// Keep alive message (outgoing)
public struct KeepAliveTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.keepAlive.rawValue
    public let time: UInt8
    
    public init(time: UInt8 = 25) {
        self.time = time
    }
    
    public var data: Data {
        Data([opcode, time])
    }
}

/// Bond request message (outgoing)
public struct BondRequestTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.bondRequest.rawValue
    
    public var data: Data {
        Data([opcode])
    }
}

/// Disconnect message (outgoing)
public struct DisconnectTxMessage: Sendable {
    public let opcode: UInt8 = G6Opcode.disconnectTx.rawValue
    
    public var data: Data {
        Data([opcode])
    }
}
