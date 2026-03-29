// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7Messages.swift
// CGMKit - DexcomG7
//
// Dexcom G7 BLE message types for communication with sensor.
// G7 uses different opcodes and message formats than G6.
// J-PAKE authentication is handled separately (CGM-015).
// Trace: PRD-008 REQ-BLE-008

import Foundation

// MARK: - Message Opcodes

/// Dexcom G7 message opcodes
public enum G7Opcode: UInt8, Sendable {
    // Authentication (J-PAKE phases)
    case authInit = 0x01
    case authRound1 = 0x02
    case authRound2 = 0x03
    case authConfirm = 0x04
    case authStatus = 0x05
    case keepAlive = 0x06
    case bondRequest = 0x07
    case pairRequest = 0x08
    
    // Control
    case disconnectTx = 0x09
    case glucoseTx = 0x4E  // Different from G6
    case glucoseRx = 0x4F  // Different from G6
    case egvTx = 0x50
    case egvRx = 0x51
    // Note: 0x52/0x53 serve dual purpose in G7 protocol
    // G7SensorKit: extendedVersionTx/Rx (session length, warmup duration)
    // xDrip: backfillTx/Rx (request/response for historical data)
    // Both interpretations valid — backfill data arrives on separate characteristic (3536)
    case backfillTx = 0x52
    case backfillRx = 0x53
    case backfillFinished = 0x59  // Marks end of backfill stream (on control characteristic)
    
    // Sensor info
    case sensorInfoTx = 0x20
    case sensorInfoRx = 0x21
    case sensorTimeTx = 0x24
    case sensorTimeRx = 0x25
    case sensorSessionTx = 0x26
    case sensorSessionRx = 0x27
    
    // Calibration (G7 is factory calibrated but allows optional calibration)
    case calibrationTx = 0x34
    case calibrationRx = 0x35
}

// MARK: - Auth Messages (J-PAKE placeholders)

/// J-PAKE authentication initialization (outgoing)
/// Full implementation in CGM-015
public struct G7AuthInitMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.authInit.rawValue
    public let sensorCode: Data
    
    public init(sensorCode: String) {
        // Convert 4-digit sensor code to bytes
        self.sensorCode = sensorCode.data(using: .utf8) ?? Data()
    }
    
    public var data: Data {
        var message = Data([opcode])
        message.append(sensorCode)
        return message
    }
}

/// J-PAKE authentication status (incoming)
public struct G7AuthStatusMessage: Sendable {
    public let opcode: UInt8
    public let authenticated: Bool
    public let bonded: Bool
    public let pairingComplete: Bool
    
    public init?(data: Data) {
        guard data.count >= 4 else { return nil }
        guard data[0] == G7Opcode.authStatus.rawValue else { return nil }
        
        self.opcode = data[0]
        self.authenticated = data[1] == 0x01
        self.bonded = data[2] == 0x01
        self.pairingComplete = data[3] == 0x01
    }
}

// MARK: - Glucose Messages

/// Glucose reading request (outgoing)
public struct G7GlucoseTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.glucoseTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// Glucose reading response (incoming)
/// G7 uses a different format than G6
public struct G7GlucoseRxMessage: Sendable {
    public let opcode: UInt8
    public let algorithmState: UInt8
    public let sensorState: UInt8
    public let sequence: UInt16  // G7-COEX-FIX-011: Aligned with Loop (2 bytes, not 4)
    public let timestamp: UInt32
    public let glucoseValue: UInt16
    public let predictedGlucose: UInt16
    public let trend: Int8
    public let transmitterTime: UInt32
    public let age: UInt16  // G7-COEX-FIX-011: Age field from Loop's G7GlucoseMessage
    public let rawData: Data  // PROTO-G7-DIAG: Store raw data for logging
    
    public init?(data: Data) {
        // G7-COEX-FIX-011: G7 sensor sends glucose with opcode 0x4E (glucoseTx)
        // NOT 0x4F. The "Tx" means "transmitted by sensor" - we are the receiver.
        // Reference: Loop's G7SensorKit G7Sensor.swift line 268: case .glucoseTx
        guard data.count >= 19 else { return nil }  // Loop uses >= 19, not 20
        guard data[0] == G7Opcode.glucoseTx.rawValue else { return nil }
        
        self.rawData = data  // PROTO-G7-DIAG
        self.opcode = data[0]
        // G7-COEX-FIX-011: Align field layout with Loop's G7GlucoseMessage
        // Loop format (19 bytes min):
        //    0  1  2 3 4 5  6 7  8  9 1011 1213 14 15 1617 18
        //         TTTTTTTT SQSQ       AGAG BGBG SS TR PRPR C
        // data[0] = opcode (0x4E)
        // data[1] = status (should be 0x00)
        // data[2..5] = messageTimestamp
        // data[6..7] = sequence
        // data[10..11] = age
        // data[12..13] = glucose
        // data[14] = algorithm state
        // data[15] = trend
        // data[16..17] = predicted
        // data[18] = calibration/state flags
        guard data[1] == 0x00 else { return nil }  // Status check like Loop
        self.timestamp = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.sequence = data.subdata(in: 6..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.age = data.subdata(in: 10..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        
        let glucoseData = data.subdata(in: 12..<14).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        if glucoseData != 0xFFFF {
            self.glucoseValue = glucoseData & 0xFFF  // 12-bit glucose
        } else {
            self.glucoseValue = 0  // Invalid
        }
        
        self.algorithmState = data[14]
        self.trend = Int8(bitPattern: data[15])
        
        let predData = data.subdata(in: 16..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        if predData != 0xFFFF {
            self.predictedGlucose = predData & 0xFFF
        } else {
            self.predictedGlucose = 0
        }
        
        self.sensorState = data.count > 18 ? data[18] : 0  // Calibration/state byte
        self.transmitterTime = UInt32(self.timestamp) - UInt32(self.age)  // Glucose timestamp
    }
    
    /// Glucose value in mg/dL
    public var glucose: Int {
        Int(glucoseValue)
    }
    
    /// Whether this is a valid glucose reading
    /// G7-COEX-FIX-002: Use isReliable instead of exact okay match
    /// This allows firstReading and secondReading states which are valid glucose
    public var isValid: Bool {
        glucoseValue > 0 && glucoseValue < 500 && parsedAlgorithmState.isReliable
    }
    
    /// Parsed sensor state
    public var parsedSensorState: G7SensorState {
        G7SensorState(rawValue: sensorState) ?? .unknown
    }
    
    /// Parsed algorithm state
    public var parsedAlgorithmState: G7AlgorithmState {
        G7AlgorithmState(rawValue: algorithmState) ?? .unknown
    }
}

// MARK: - EGV Messages (Estimated Glucose Value)

/// EGV request (outgoing)
public struct G7EGVTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.egvTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// EGV response (incoming)
/// Contains the final estimated glucose value after algorithm processing
public struct G7EGVRxMessage: Sendable {
    public let opcode: UInt8
    public let sequence: UInt32
    public let timestamp: Int
    public let egv: UInt16
    public let trend: Int8
    public let status: UInt8
    public let rawData: Data  // PROTO-G7-DIAG: Store raw data for logging
    
    public init?(data: Data) {
        guard data.count >= 14 else { return nil }
        guard data[0] == G7Opcode.egvRx.rawValue else { return nil }
        
        self.rawData = data  // PROTO-G7-DIAG
        self.opcode = data[0]
        self.sequence = data.subdata(in: 1..<5).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.timestamp = Int(data.subdata(in: 5..<9).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        self.egv = data.subdata(in: 9..<11).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.trend = Int8(bitPattern: data[11])
        self.status = data[12]
    }
    
    /// EGV in mg/dL
    public var glucose: Int {
        Int(egv)
    }
    
    /// Whether this is a valid reading
    public var isValid: Bool {
        egv > 0 && egv < 500 && status == 0
    }
}

// MARK: - Backfill Messages

/// Glucose backfill request (outgoing)
public struct G7BackfillTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.backfillTx.rawValue
    public let startTime: UInt32
    public let endTime: UInt32
    
    public init(startTime: UInt32, endTime: UInt32) {
        self.startTime = startTime
        self.endTime = endTime
    }
    
    public var data: Data {
        var message = Data([opcode])
        withUnsafeBytes(of: startTime) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: endTime) { message.append(contentsOf: $0) }
        return message
    }
}

/// Glucose backfill response (incoming)
public struct G7BackfillRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let identifier: UInt8
    public let startTime: UInt32
    public let endTime: UInt32
    public let readings: [G7BackfillReading]
    
    public init?(data: Data) {
        guard data.count >= 11 else { return nil }
        guard data[0] == G7Opcode.backfillRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.identifier = data[2]
        self.startTime = data.subdata(in: 3..<7).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.endTime = data.subdata(in: 7..<11).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        
        // Parse readings (6 bytes each: timestamp offset + glucose + trend)
        var parsedReadings: [G7BackfillReading] = []
        var offset = 11
        while offset + 6 <= data.count {
            let timestampOffset = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let glucose = data.subdata(in: (offset + 2)..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let trend = Int8(bitPattern: data[offset + 4])
            let state = data[offset + 5]
            
            let reading = G7BackfillReading(
                timestampOffset: timestampOffset,
                glucoseValue: glucose,
                trend: trend,
                state: state
            )
            parsedReadings.append(reading)
            offset += 6
        }
        self.readings = parsedReadings
    }
}

/// Single backfill reading
public struct G7BackfillReading: Sendable, Codable {
    public let timestampOffset: UInt16
    public let glucoseValue: UInt16
    public let trend: Int8
    public let state: UInt8
    
    public var glucose: Double {
        Double(glucoseValue)
    }
    
    public var isValid: Bool {
        glucoseValue > 0 && glucoseValue < 500
    }
}

// MARK: - Sensor Info Messages

/// Sensor info request (outgoing)
public struct G7SensorInfoTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.sensorInfoTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// Sensor info response (incoming)
public struct G7SensorInfoRxMessage: Sendable {
    public let opcode: UInt8
    public let sensorState: UInt8
    public let sensorAge: UInt32
    public let warmupRemaining: UInt16
    public let sensorSerial: String
    
    public init?(data: Data) {
        guard data.count >= 17 else { return nil }
        guard data[0] == G7Opcode.sensorInfoRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.sensorState = data[1]
        self.sensorAge = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.warmupRemaining = data.subdata(in: 6..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        
        // Sensor serial is 10 bytes starting at offset 7
        let serialData = data.subdata(in: 7..<17)
        self.sensorSerial = String(data: serialData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    
    /// Parsed sensor state
    public var parsedState: G7SensorState {
        G7SensorState(rawValue: sensorState) ?? .unknown
    }
    
    /// Sensor age in hours
    public var ageHours: Double {
        Double(sensorAge) / 3600.0
    }
    
    /// Warmup remaining in minutes
    public var warmupMinutes: Double {
        Double(warmupRemaining) / 60.0
    }
}

// MARK: - Sensor Time Messages

/// Sensor time request (outgoing)
public struct G7SensorTimeTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.sensorTimeTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// Sensor time response (incoming)
public struct G7SensorTimeRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let currentTime: UInt32
    public let sessionStartTime: UInt32
    
    public init?(data: Data) {
        guard data.count >= 10 else { return nil }
        guard data[0] == G7Opcode.sensorTimeRx.rawValue else { return nil }
        
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
    
    /// Session age in hours
    /// Warning: May be incorrect if no active session - check hasActiveSession first
    public var sessionAgeHours: Double {
        Double(sessionAge) / 3600.0
    }
    
    /// Whether there is an active sensor session
    /// Returns false when sessionStartTime is the sentinel value (0xFFFFFFFF),
    /// indicating no session (sensor expired, stopped, failed, or not started).
    /// Trace: GAP-API-021 (future-dated entries fix)
    public var hasActiveSession: Bool {
        sessionStartTime != G7Constants.invalidSessionTime
    }
    
    /// Safe session age that returns nil if no active session
    /// Trace: GAP-API-021 (future-dated entries fix)
    public var safeSessionAge: UInt32? {
        guard hasActiveSession else { return nil }
        let age = sessionAge
        // Also check for unreasonable values from underflow
        guard age <= G7Constants.maxReasonableSessionAge else { return nil }
        return age
    }
}

// MARK: - Control Messages

/// Keep alive message (outgoing)
public struct G7KeepAliveTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.keepAlive.rawValue
    public let time: UInt8
    
    public init(time: UInt8 = 25) {
        self.time = time
    }
    
    public var data: Data {
        Data([opcode, time])
    }
}

/// Bond request message (outgoing)
public struct G7BondRequestTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.bondRequest.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

/// Pair request message (outgoing) - G7 specific
public struct G7PairRequestTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.pairRequest.rawValue
    public let sensorCode: Data
    
    public init(sensorCode: String) {
        self.sensorCode = sensorCode.data(using: .utf8) ?? Data()
    }
    
    public var data: Data {
        var message = Data([opcode])
        message.append(sensorCode)
        return message
    }
}

/// Disconnect message (outgoing)
public struct G7DisconnectTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.disconnectTx.rawValue
    
    public init() {}
    
    public var data: Data {
        Data([opcode])
    }
}

// MARK: - Calibration Messages (Optional for G7)

/// Calibration request (outgoing)
public struct G7CalibrationTxMessage: Sendable {
    public let opcode: UInt8 = G7Opcode.calibrationTx.rawValue
    public let glucoseValue: UInt16
    
    public init(glucoseValue: UInt16) {
        self.glucoseValue = glucoseValue
    }
    
    public var data: Data {
        var message = Data([opcode])
        withUnsafeBytes(of: glucoseValue) { message.append(contentsOf: $0) }
        return message
    }
}

/// Calibration response (incoming)
public struct G7CalibrationRxMessage: Sendable {
    public let opcode: UInt8
    public let status: UInt8
    public let accepted: Bool
    
    public init?(data: Data) {
        guard data.count >= 3 else { return nil }
        guard data[0] == G7Opcode.calibrationRx.rawValue else { return nil }
        
        self.opcode = data[0]
        self.status = data[1]
        self.accepted = data[2] == 0x01
    }
}

// MARK: - Extended Version Message

/// G7 Extended Version Message - Loop/Trio compatible format
/// Source: G7SensorKit/ExtendedVersionMessage.swift
/// Task: G7-SYNTH-003
/// Format: 15 bytes starting with 0x52
///
/// Byte layout:
/// ```
///    0  1  2 3 4 5  6 7  8 9 10 11  12  13 14
///       00 LLLLLLLL WWWW AAAAAAAA  HH  MMMM
/// ```
/// - bytes[0]: opcode (0x52 = extendedVersionTx)
/// - bytes[1]: reserved (0x00)
/// - bytes[2-5]: sessionLength (UInt32 LE, seconds)
/// - bytes[6-7]: warmupDuration (UInt16 LE, seconds)
/// - bytes[8-11]: algorithmVersion (UInt32 LE)
/// - bytes[12]: hardwareVersion (UInt8)
/// - bytes[13-14]: maxLifetimeDays (UInt16 LE)
public struct G7ExtendedVersionMessage: Sendable, Equatable {
    public static let opcode: UInt8 = 0x52
    
    /// Session length in seconds
    public let sessionLengthSeconds: UInt32
    
    /// Warmup duration in seconds
    public let warmupDurationSeconds: UInt16
    
    /// Algorithm version number
    public let algorithmVersion: UInt32
    
    /// Hardware version number
    public let hardwareVersion: UInt8
    
    /// Maximum sensor lifetime in days
    public let maxLifetimeDays: UInt16
    
    /// Raw data
    public let data: Data
    
    /// Session length as TimeInterval
    public var sessionLength: TimeInterval {
        TimeInterval(sessionLengthSeconds)
    }
    
    /// Session length in days
    public var sessionLengthDays: Double {
        Double(sessionLengthSeconds) / 86400.0
    }
    
    /// Warmup duration as TimeInterval
    public var warmupDuration: TimeInterval {
        TimeInterval(warmupDurationSeconds)
    }
    
    /// Warmup duration in minutes
    public var warmupDurationMinutes: Double {
        Double(warmupDurationSeconds) / 60.0
    }
    
    public init?(data: Data) {
        guard data.count >= 15 else { return nil }
        guard data[0] == Self.opcode else { return nil }
        
        self.data = data
        self.sessionLengthSeconds = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.warmupDurationSeconds = data.subdata(in: 6..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.algorithmVersion = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.hardwareVersion = data[12]
        self.maxLifetimeDays = data.subdata(in: 13..<15).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    }
}

extension G7ExtendedVersionMessage: CustomDebugStringConvertible {
    public var debugDescription: String {
        "G7ExtendedVersionMessage(sessionLength:\(sessionLength), warmupDuration:\(warmupDuration) algorithmVersion:\(algorithmVersion) hardwareVersion:\(hardwareVersion) maxLifetimeDays:\(maxLifetimeDays))"
    }
}

// MARK: - Loop-Compatible G7 Messages (G7SensorKit format)

/// G7 Glucose Message - Loop/Trio compatible format
/// Source: G7SensorKit/G7GlucoseMessage.swift
/// Format: 19 bytes starting with 0x4E
///
/// Byte layout (from Loop tests):
/// ```
///  0  1  2 3 4 5  6 7  8  9 10 11 1213 14 15 16 17 18
///       TTTTTTTT SQSQ       AGAG BGBG SS          C
/// ```
/// - bytes[0]: opcode (0x4E)
/// - bytes[1]: reserved
/// - bytes[2-5]: timestamp (little-endian UInt32, sensor time in seconds)
/// - bytes[6-7]: sequence (little-endian UInt16)
/// - bytes[8]: reserved
/// - bytes[9]: session indicator (1 = active)
/// - bytes[10-11]: age in seconds since reading (little-endian UInt16)
/// - bytes[12-13]: glucose value (little-endian UInt16, mg/dL)
/// - bytes[14]: algorithm state (0x06 = OK, 0x02 = warmup, etc.)
/// - bytes[15]: trend (signed Int8, rate * 10)
/// - bytes[16-17]: predicted glucose (little-endian UInt16)
/// - bytes[18]: condition byte
public struct G7GlucoseMessage: Sendable {
    public static let opcode: UInt8 = 0x4E
    
    public let messageTimestamp: UInt32
    public let sequence: UInt16
    public let age: UInt16
    public let glucoseValue: UInt16?
    public let algorithmStateRaw: UInt8
    public let trendRaw: Int8?
    public let predicted: UInt16?
    public let conditionRaw: UInt8
    
    /// Glucose value in mg/dL
    public var glucose: UInt16? {
        glucoseValue
    }
    
    /// Glucose timestamp (message timestamp - age)
    public var glucoseTimestamp: UInt32 {
        messageTimestamp - UInt32(age)
    }
    
    /// Trend rate in mg/dL/min (raw value / 10)
    public var trend: Double? {
        guard let raw = trendRaw, raw != 0x7F else { return nil }
        return Double(raw) / 10.0
    }
    
    /// Whether glucose is for display only (not for dosing decisions)
    public var glucoseIsDisplayOnly: Bool {
        // Condition byte bit 4 indicates calibration/display-only
        (conditionRaw & 0x10) != 0
    }
    
    /// Algorithm state interpretation
    public var algorithmState: G7AlgorithmStateKnown {
        G7AlgorithmStateKnown.from(raw: algorithmStateRaw)
    }
    
    public init?(data: Data) {
        guard data.count >= 19 else { return nil }
        guard data[0] == Self.opcode else { return nil }
        
        self.messageTimestamp = data.subdata(in: 2..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        self.sequence = data.subdata(in: 6..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.age = data.subdata(in: 10..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        
        let rawGlucose = data.subdata(in: 12..<14).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.glucoseValue = rawGlucose > 0 && rawGlucose != 0xFFFF ? rawGlucose : nil
        
        self.algorithmStateRaw = data[14]
        
        let rawTrend = Int8(bitPattern: data[15])
        self.trendRaw = rawTrend != 0x7F ? rawTrend : nil
        
        let rawPredicted = data.subdata(in: 16..<18).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        self.predicted = rawPredicted != 0xFFFF ? rawPredicted : nil
        
        self.conditionRaw = data[18]
    }
}

/// G7 Algorithm state with known/unknown wrapper
public enum G7AlgorithmStateKnown: Sendable, Equatable {
    case known(G7LoopAlgorithmState)
    case unknown(UInt8)
    
    public static func from(raw: UInt8) -> G7AlgorithmStateKnown {
        if let state = G7LoopAlgorithmState(rawValue: raw) {
            return .known(state)
        }
        return .unknown(raw)
    }
}

/// G7 Algorithm states as defined in Loop/G7SensorKit
public enum G7LoopAlgorithmState: UInt8, Sendable {
    case stopped = 0x01
    case warmup = 0x02
    case excessNoise = 0x03
    case sensorFailed = 0x04
    case unknown05 = 0x05
    case ok = 0x06
    case sensorFailed7 = 0x07
    case sensorFailed8 = 0x08
    case expired = 0x18
}

/// G7 Backfill Message - Loop/Trio compatible format
/// Source: G7SensorKit/G7BackfillMessage.swift
/// Format: 9 bytes
///
/// Byte layout (from Loop):
/// ```
///    0 1 2  3  4 5  6  7  8
///   TTTTTT    BGBG SS    TR
///   45a100 00 9600 06 0f fc
/// ```
/// - bytes[0-2]: timestamp (3 bytes, little-endian)
/// - bytes[3]: reserved/padding
/// - bytes[4-5]: glucose value (little-endian UInt16, 0xFFFF = invalid)
/// - bytes[6]: algorithm state (0x06 = ok)
/// - bytes[7]: flags (bit 4 = displayOnly)
/// - bytes[8]: trend (signed Int8, 0x7F = missing)
public struct G7BackfillMessage: Sendable {
    public let timestamp: UInt32
    public let glucoseValue: UInt16?
    public let algorithmStateRaw: UInt8
    public let trendRaw: Int8?
    private let flagsRaw: UInt8
    
    public var glucose: UInt16 {
        glucoseValue ?? 0
    }
    
    public var algorithmState: G7AlgorithmStateKnown {
        G7AlgorithmStateKnown.from(raw: algorithmStateRaw)
    }
    
    /// Whether glucose is for display only
    public var glucoseIsDisplayOnly: Bool {
        (flagsRaw & 0x10) != 0
    }
    
    /// Whether glucose reading is reliable
    public var hasReliableGlucose: Bool {
        if case .known(.ok) = algorithmState {
            return true
        }
        return false
    }
    
    /// Condition byte (nil if not applicable)
    public var condition: UInt8? {
        // In Loop, condition is derived from glucose limits, not a raw field
        // Return nil if no glucose condition detected
        nil
    }
    
    public init?(data: Data) {
        guard data.count == 9 else { return nil }
        
        // Timestamp is 3 bytes little-endian (bytes 0-2)
        var timestampBytes = Data(data[0..<3])
        timestampBytes.append(0x00)  // Pad to 4 bytes
        self.timestamp = timestampBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        
        // Glucose is bytes 4-5 (little-endian UInt16)
        let glucoseBytes = data.subdata(in: 4..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        if glucoseBytes != 0xFFFF {
            self.glucoseValue = glucoseBytes & 0x0FFF  // Lower 12 bits
        } else {
            self.glucoseValue = nil
        }
        
        // Algorithm state is byte 6
        self.algorithmStateRaw = data[6]
        
        // Flags is byte 7 (bit 4 = displayOnly)
        self.flagsRaw = data[7]
        
        // Trend is byte 8 (signed, 0x7F = missing)
        let rawTrend = Int8(bitPattern: data[8])
        self.trendRaw = rawTrend != 0x7F ? rawTrend : nil
    }
}
