// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemCommands.swift
// PumpKit
//
// Tandem t:slim X2 protocol commands and opcodes.
// Trace: TANDEM-IMPL-001, TANDEM-AUDIT-001..005, PRD-005
//
// Reference: externals/pumpX2/, tools/x2-cli/x2_parsers.py

import Foundation

// MARK: - BLE Characteristics

/// Tandem X2 BLE characteristic UUIDs
public enum TandemCharacteristic: String, CaseIterable, Sendable {
    /// Current pump status (unsigned messages)
    case currentStatus = "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9"
    /// Authorization and pairing
    case authorization = "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
    /// Signed commands (HMAC-SHA1)
    case control = "7B83FFFC-9F77-4E5C-8064-AAE2C24838B9"
    /// Signed streaming data
    case controlStream = "7B83FFFD-9F77-4E5C-8064-AAE2C24838B9"
    /// History log events
    case historyLog = "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9"
    
    /// Display name for logging
    public var displayName: String {
        switch self {
        case .currentStatus: return "CURRENT_STATUS"
        case .authorization: return "AUTHORIZATION"
        case .control: return "CONTROL"
        case .controlStream: return "CONTROL_STREAM"
        case .historyLog: return "HISTORY_LOG"
        }
    }
    
    /// Whether this characteristic uses signed (HMAC-SHA1) messages
    public var requiresSignature: Bool {
        switch self {
        case .control, .controlStream:
            return true
        case .currentStatus, .authorization, .historyLog:
            return false
        }
    }
}

/// Tandem X2 BLE service UUID
public let TandemServiceUUID = "00001818-0000-1000-8000-00805F9B34FB"

// MARK: - Opcodes

/// Tandem X2 unsigned opcodes (CURRENT_STATUS characteristic)
public enum TandemUnsignedOpcode: Int, CaseIterable, Sendable {
    // Status queries
    case currentBasalStatusRequest = 41
    case currentBasalStatusResponse = 42
    case tempRateRequest = 43
    case tempRateResponse = 44
    case controllerInfoRequest = 35
    case controllerInfoResponse = 36
    
    // Profile queries (IDP = Insulin Delivery Profile)
    case profileStatusRequest = 62
    case profileStatusResponse = 63
    case idpSettingsRequest = 64
    case idpSettingsResponse = 65
    case idpSegmentRequest = 66
    case idpSegmentResponse = 67
    
    case iobRequest = 68
    case iobResponse = 69
    
    /// Display name for logging
    public var displayName: String {
        switch self {
        case .currentBasalStatusRequest: return "CurrentBasalStatusRequest"
        case .currentBasalStatusResponse: return "CurrentBasalStatusResponse"
        case .tempRateRequest: return "TempRateRequest"
        case .tempRateResponse: return "TempRateResponse"
        case .controllerInfoRequest: return "ControllerInfoRequest"
        case .controllerInfoResponse: return "ControllerInfoResponse"
        case .profileStatusRequest: return "ProfileStatusRequest"
        case .profileStatusResponse: return "ProfileStatusResponse"
        case .idpSettingsRequest: return "IDPSettingsRequest"
        case .idpSettingsResponse: return "IDPSettingsResponse"
        case .idpSegmentRequest: return "IDPSegmentRequest"
        case .idpSegmentResponse: return "IDPSegmentResponse"
        case .iobRequest: return "IOBRequest"
        case .iobResponse: return "IOBResponse"
        }
    }
    
    /// Whether this is a request (TX) or response (RX)
    public var isRequest: Bool {
        [.currentBasalStatusRequest, .tempRateRequest, .controllerInfoRequest,
         .profileStatusRequest, .idpSettingsRequest, .idpSegmentRequest,
         .iobRequest].contains(self)
    }
}

/// Tandem X2 signed opcodes (CONTROL characteristic)
/// Note: These are represented as negative values in Java, we use the unsigned byte value
public enum TandemSignedOpcode: Int, CaseIterable, Sendable {
    // Basal settings
    case basalLimitSettingsRequest = 139   // -117 in Java
    case basalLimitSettingsResponse = 140  // -116 in Java
    
    // Bolus control
    case initiateBolusRequest = 158        // -98 in Java
    case initiateBolusResponse = 159       // -97 in Java
    case cancelBolusRequest = 160          // -96 in Java
    case cancelBolusResponse = 161         // -95 in Java
    
    // Temp basal
    case setTempRateRequest = 164          // -92 in Java
    case setTempRateResponse = 165         // -91 in Java
    case stopTempRateRequest = 166         // -90 in Java
    case stopTempRateResponse = 167        // -89 in Java
    
    // Profile modification (IDP segments)
    case setIDPSegmentRequest = 170        // -86 in Java
    case setIDPSegmentResponse = 171       // -85 in Java
    
    /// Display name for logging
    public var displayName: String {
        switch self {
        case .basalLimitSettingsRequest: return "BasalLimitSettingsRequest"
        case .basalLimitSettingsResponse: return "BasalLimitSettingsResponse"
        case .initiateBolusRequest: return "InitiateBolusRequest"
        case .initiateBolusResponse: return "InitiateBolusResponse"
        case .cancelBolusRequest: return "CancelBolusRequest"
        case .cancelBolusResponse: return "CancelBolusResponse"
        case .setTempRateRequest: return "SetTempRateRequest"
        case .setTempRateResponse: return "SetTempRateResponse"
        case .stopTempRateRequest: return "StopTempRateRequest"
        case .stopTempRateResponse: return "StopTempRateResponse"
        case .setIDPSegmentRequest: return "SetIDPSegmentRequest"
        case .setIDPSegmentResponse: return "SetIDPSegmentResponse"
        }
    }
    
    /// Whether this is a request (TX) or response (RX)
    public var isRequest: Bool {
        [.basalLimitSettingsRequest, .initiateBolusRequest, .cancelBolusRequest,
         .setTempRateRequest, .stopTempRateRequest, .setIDPSegmentRequest].contains(self)
    }
    
    /// Java-style signed value
    public var signedValue: Int {
        rawValue > 127 ? rawValue - 256 : rawValue
    }
}

// MARK: - Delivery Status

/// Tandem pump delivery status
public enum TandemDeliveryStatus: Int, CaseIterable, Sendable {
    case suspended = 0
    case deliveringBasal = 1
    case deliveringBolus = 2
    
    public var displayName: String {
        switch self {
        case .suspended: return "Suspended"
        case .deliveringBasal: return "Delivering Basal"
        case .deliveringBolus: return "Delivering Bolus"
        }
    }
    
    public var isDelivering: Bool {
        self != .suspended
    }
}

// MARK: - Basal Modified Bitmask

/// Flags for basal rate modification
public struct TandemBasalModifiedFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let profileRate = TandemBasalModifiedFlags(rawValue: 1 << 0)
    public static let tempRateActive = TandemBasalModifiedFlags(rawValue: 1 << 1)
    public static let suspended = TandemBasalModifiedFlags(rawValue: 1 << 2)
    
    public var description: String {
        var flags: [String] = []
        if contains(.profileRate) { flags.append("PROFILE_RATE") }
        if contains(.tempRateActive) { flags.append("TEMP_RATE_ACTIVE") }
        if contains(.suspended) { flags.append("SUSPENDED") }
        return flags.isEmpty ? "NONE" : flags.joined(separator: ", ")
    }
}

// MARK: - Protocol Constants

/// Tandem X2 protocol constants
public enum TandemProtocol {
    /// Maximum transmission unit (bytes)
    public static let mtu: Int = 185
    
    /// Token refresh interval (seconds)
    public static let tokenRefreshInterval: TimeInterval = 120
    
    /// Signature size (4-byte time + 20-byte HMAC-SHA1)
    public static let signatureSize: Int = 24
    
    /// Minimum message size (opcode + txid + len + crc16)
    public static let minMessageSize: Int = 5
    
    /// CRC polynomial (CCITT)
    public static let crcPolynomial: UInt16 = 0x1021
    
    /// CRC initial value
    public static let crcInitial: UInt16 = 0xFFFF
}

// MARK: - CRC-16 CCITT

/// CRC-16 CCITT-FALSE calculation for Tandem messages
public enum TandemCRC16 {
    private static var table: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ TandemProtocol.crcPolynomial
                } else {
                    crc <<= 1
                }
            }
            table[i] = crc
        }
        return table
    }()
    
    /// Calculate CRC-16 CCITT-FALSE checksum
    public static func calculate(_ data: Data) -> UInt16 {
        var crc = TandemProtocol.crcInitial
        for byte in data {
            let index = Int(((crc >> 8) ^ UInt16(byte)) & 0xFF)
            crc = (crc << 8) ^ table[index]
        }
        return crc
    }
    
    /// Verify CRC-16 checksum at end of message
    public static func verify(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        let message = data.dropLast(2)
        let expectedCRC = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
        let calculatedCRC = calculate(Data(message))
        return expectedCRC == calculatedCRC
    }
}

// MARK: - Message Structure

/// Parsed Tandem X2 message
public struct TandemMessage: Sendable, Equatable {
    public let opcode: Int
    public let transactionId: UInt8
    public let cargo: Data
    public let signature: Data?
    public let crc: UInt16
    public let isSigned: Bool
    public let crcValid: Bool
    
    public init(
        opcode: Int,
        transactionId: UInt8,
        cargo: Data,
        signature: Data? = nil,
        crc: UInt16,
        isSigned: Bool,
        crcValid: Bool
    ) {
        self.opcode = opcode
        self.transactionId = transactionId
        self.cargo = cargo
        self.signature = signature
        self.crc = crc
        self.isSigned = isSigned
        self.crcValid = crcValid
    }
    
    /// Extract pump time from signature (first 4 bytes, little-endian)
    public var pumpTimeSinceReset: UInt32? {
        guard let sig = signature, sig.count >= 4 else { return nil }
        return sig.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    /// Extract HMAC from signature (last 20 bytes)
    public var hmac: Data? {
        guard let sig = signature, sig.count >= 24 else { return nil }
        return sig.suffix(20)
    }
    
    /// Unsigned opcode interpretation
    public var unsignedOpcode: TandemUnsignedOpcode? {
        TandemUnsignedOpcode(rawValue: opcode)
    }
    
    /// Signed opcode interpretation
    public var signedOpcode: TandemSignedOpcode? {
        TandemSignedOpcode(rawValue: opcode > 127 ? opcode : opcode + 256)
    }
}

/// Parse a Tandem X2 message from raw data
public func parseTandemMessage(_ data: Data, signed: Bool = false) -> TandemMessage? {
    guard data.count >= TandemProtocol.minMessageSize else { return nil }
    
    var opcode = Int(data[0])
    // Handle signed opcodes (negative in Java representation)
    if opcode > 127 {
        opcode = opcode - 256
    }
    
    let transactionId = data[1]
    let cargoLen = Int(data[2])
    
    let expectedLen: Int
    let cargo: Data
    let signature: Data?
    
    if signed {
        // Signed messages: cargo_len INCLUDES the 24-byte signature
        expectedLen = 3 + cargoLen + 2  // header + cargo_len + crc
        guard data.count >= expectedLen else { return nil }
        
        let actualCargoLen = cargoLen - TandemProtocol.signatureSize
        guard actualCargoLen >= 0 else { return nil }
        
        cargo = data.subdata(in: 3..<(3 + actualCargoLen))
        signature = data.subdata(in: (3 + actualCargoLen)..<(3 + cargoLen))
    } else {
        expectedLen = 3 + cargoLen + 2
        guard data.count >= expectedLen else { return nil }
        cargo = data.subdata(in: 3..<(3 + cargoLen))
        signature = nil
    }
    
    let crc = UInt16(data[expectedLen - 2]) << 8 | UInt16(data[expectedLen - 1])
    let crcValid = TandemCRC16.verify(data.prefix(expectedLen))
    
    return TandemMessage(
        opcode: opcode > 127 ? opcode : opcode,
        transactionId: transactionId,
        cargo: cargo,
        signature: signature,
        crc: crc,
        isSigned: signed,
        crcValid: crcValid
    )
}

// MARK: - Status Responses

/// Parsed CurrentBasalStatusResponse
public struct TandemBasalStatus: Sendable, Equatable {
    /// Profile basal rate in milliunits/hr
    public let profileBasalRateMilliunits: Int
    /// Current effective basal rate in milliunits/hr
    public let currentBasalRateMilliunits: Int
    /// Modification flags
    public let modifiedFlags: TandemBasalModifiedFlags
    
    /// Profile basal rate in U/hr
    public var profileBasalRate: Double {
        Double(profileBasalRateMilliunits) / 1000.0
    }
    
    /// Current basal rate in U/hr
    public var currentBasalRate: Double {
        Double(currentBasalRateMilliunits) / 1000.0
    }
    
    /// Whether a temp rate is active
    public var isTempRateActive: Bool {
        modifiedFlags.contains(.tempRateActive)
    }
    
    /// Whether delivery is suspended
    public var isSuspended: Bool {
        modifiedFlags.contains(.suspended)
    }
    
    /// Parse from message cargo (6 bytes)
    public static func parse(from cargo: Data) -> TandemBasalStatus? {
        guard cargo.count >= 6 else { return nil }
        
        // 2 bytes: profile rate (little-endian)
        let profileRate = Int(cargo[0]) | (Int(cargo[1]) << 8)
        // 2 bytes: current rate (little-endian)
        let currentRate = Int(cargo[2]) | (Int(cargo[3]) << 8)
        // 1 byte: bitmask
        let bitmask = cargo[4]
        
        return TandemBasalStatus(
            profileBasalRateMilliunits: profileRate,
            currentBasalRateMilliunits: currentRate,
            modifiedFlags: TandemBasalModifiedFlags(rawValue: bitmask)
        )
    }
}

/// Parsed TempRateResponse
public struct TandemTempRateStatus: Sendable, Equatable {
    /// Whether temp rate is active
    public let isActive: Bool
    /// Temp rate percentage (0-250%)
    public let percentage: Int
    /// Remaining duration in minutes
    public let remainingMinutes: Int
    
    /// Parse from message cargo
    public static func parse(from cargo: Data) -> TandemTempRateStatus? {
        guard cargo.count >= 4 else { return nil }
        
        let isActive = cargo[0] != 0
        let percentage = Int(cargo[1])
        let remaining = Int(cargo[2]) | (Int(cargo[3]) << 8)
        
        return TandemTempRateStatus(
            isActive: isActive,
            percentage: percentage,
            remainingMinutes: remaining
        )
    }
}

/// Parsed IOB response
public struct TandemIOBStatus: Sendable, Equatable {
    /// IOB in milliunits
    public let iobMilliunits: Int
    
    /// IOB in units
    public var iob: Double {
        Double(iobMilliunits) / 1000.0
    }
    
    /// Parse from message cargo
    public static func parse(from cargo: Data) -> TandemIOBStatus? {
        guard cargo.count >= 4 else { return nil }
        
        let iob = Int(cargo[0]) | (Int(cargo[1]) << 8) |
                  (Int(cargo[2]) << 16) | (Int(cargo[3]) << 24)
        
        return TandemIOBStatus(iobMilliunits: iob)
    }
}

// MARK: - Profile (IDP) Responses

/// Parsed ProfileStatusResponse - lists available insulin delivery profiles
public struct TandemProfileStatus: Sendable, Equatable {
    /// Number of profiles configured
    public let numberOfProfiles: Int
    /// Profile IDs in each slot (6 slots, -1 = empty)
    public let slotIds: [Int]
    /// Currently active segment index
    public let activeSegmentIndex: Int
    
    /// Parse from message cargo (8 bytes)
    /// Format: [numberOfProfiles, slot0Id, slot1Id, slot2Id, slot3Id, slot4Id, slot5Id, activeSegmentIndex]
    public static func parse(from cargo: Data) -> TandemProfileStatus? {
        guard cargo.count >= 8 else { return nil }
        
        let numberOfProfiles = Int(cargo[0])
        let slotIds = (1...6).map { i -> Int in
            let val = Int8(bitPattern: cargo[i])
            return Int(val)
        }
        let activeSegmentIndex = Int(Int8(bitPattern: cargo[7]))
        
        return TandemProfileStatus(
            numberOfProfiles: numberOfProfiles,
            slotIds: slotIds,
            activeSegmentIndex: activeSegmentIndex
        )
    }
    
    /// Get profile ID at a slot index (0-5), or nil if empty
    public func profileId(atSlot slot: Int) -> Int? {
        guard slot >= 0, slot < slotIds.count else { return nil }
        let id = slotIds[slot]
        return id >= 0 ? id : nil
    }
    
    /// Valid profile IDs (non-negative)
    public var validProfileIds: [Int] {
        slotIds.filter { $0 >= 0 }
    }
}

/// Parsed IDPSettingsResponse - metadata for a single profile
public struct TandemIDPSettings: Sendable, Equatable {
    /// Profile ID
    public let idpId: Int
    /// Profile name (up to 16 chars)
    public let name: String
    /// Number of time segments in this profile
    public let numberOfSegments: Int
    /// Insulin duration in minutes (DIA)
    public let insulinDuration: Int
    /// Maximum bolus in milliunits
    public let maxBolusMilliunits: Int
    /// Whether carb entry is enabled
    public let carbEntry: Bool
    
    /// Insulin duration in hours
    public var insulinDurationHours: Double {
        Double(insulinDuration) / 60.0
    }
    
    /// Maximum bolus in units
    public var maxBolus: Double {
        Double(maxBolusMilliunits) / 1000.0
    }
    
    /// Parse from message cargo (23 bytes)
    /// Format: [idpId, name(16), numberOfSegments, insulinDuration(2), maxBolus(2), carbEntry]
    public static func parse(from cargo: Data) -> TandemIDPSettings? {
        guard cargo.count >= 23 else { return nil }
        
        let idpId = Int(cargo[0])
        
        // Name is 16 bytes, null-terminated
        let nameData = cargo[1..<17]
        let name = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        let numberOfSegments = Int(cargo[17])
        let insulinDuration = Int(cargo[18]) | (Int(cargo[19]) << 8)
        let maxBolus = Int(cargo[20]) | (Int(cargo[21]) << 8)
        let carbEntry = cargo[22] != 0
        
        return TandemIDPSettings(
            idpId: idpId,
            name: name,
            numberOfSegments: numberOfSegments,
            insulinDuration: insulinDuration,
            maxBolusMilliunits: maxBolus,
            carbEntry: carbEntry
        )
    }
}

/// Segment status flags for IDP segments
public struct TandemIDPSegmentStatus: OptionSet, Sendable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let basalRate = TandemIDPSegmentStatus(rawValue: 1 << 0)
    public static let carbRatio = TandemIDPSegmentStatus(rawValue: 1 << 1)
    public static let targetBG = TandemIDPSegmentStatus(rawValue: 1 << 2)
    public static let correctionFactor = TandemIDPSegmentStatus(rawValue: 1 << 3)
    public static let startTime = TandemIDPSegmentStatus(rawValue: 1 << 4)
    
    /// All valid settings present
    public static let all: TandemIDPSegmentStatus = [.basalRate, .carbRatio, .targetBG, .correctionFactor, .startTime]
}

/// Parsed IDPSegmentResponse - a single time segment within a profile
public struct TandemIDPSegment: Sendable, Equatable {
    /// Profile ID this segment belongs to
    public let idpId: Int
    /// Segment index within profile (0-based)
    public let segmentIndex: Int
    /// Start time in minutes since midnight (0 = midnight, 480 = 8am)
    public let startTimeMinutes: Int
    /// Basal rate in milliunits/hr (1000 = 1.0 U/hr)
    public let basalRateMilliunits: Int
    /// Carb ratio (mg/dL per unit × 1000, so 3000 = 3:1)
    public let carbRatioEncoded: Int
    /// Target BG in mg/dL
    public let targetBG: Int
    /// Insulin sensitivity factor (mg/dL per unit)
    public let isf: Int
    /// Status flags indicating which values are set
    public let statusFlags: TandemIDPSegmentStatus
    
    /// Basal rate in U/hr
    public var basalRate: Double {
        Double(basalRateMilliunits) / 1000.0
    }
    
    /// Carb ratio as grams per unit (e.g., 10 means 1U per 10g carbs)
    public var carbRatio: Double {
        // Tandem encodes as mg/dL per unit × 1000, we convert to g/U
        // carbRatioEncoded of 20000 = 20:1 ratio
        Double(carbRatioEncoded) / 1000.0
    }
    
    /// Start time as hours since midnight
    public var startTimeHours: Double {
        Double(startTimeMinutes) / 60.0
    }
    
    /// Parse from message cargo (15 bytes)
    /// Format: [idpId, segmentIndex, startTime(2), basalRate(2), carbRatio(4), targetBG(2), isf(2), statusId]
    public static func parse(from cargo: Data) -> TandemIDPSegment? {
        guard cargo.count >= 15 else { return nil }
        
        let idpId = Int(cargo[0])
        let segmentIndex = Int(cargo[1])
        let startTime = Int(cargo[2]) | (Int(cargo[3]) << 8)
        let basalRate = Int(cargo[4]) | (Int(cargo[5]) << 8)
        let carbRatio = Int(cargo[6]) | (Int(cargo[7]) << 8) |
                        (Int(cargo[8]) << 16) | (Int(cargo[9]) << 24)
        let targetBG = Int(cargo[10]) | (Int(cargo[11]) << 8)
        let isf = Int(cargo[12]) | (Int(cargo[13]) << 8)
        let statusId = cargo[14]
        
        return TandemIDPSegment(
            idpId: idpId,
            segmentIndex: segmentIndex,
            startTimeMinutes: startTime,
            basalRateMilliunits: basalRate,
            carbRatioEncoded: carbRatio,
            targetBG: targetBG,
            isf: isf,
            statusFlags: TandemIDPSegmentStatus(rawValue: statusId)
        )
    }
}

/// Operation type for SetIDPSegmentRequest
public enum TandemIDPSegmentOperation: Int, Sendable {
    case modifySegment = 0
    case createSegment = 1
    case deleteSegment = 2
}

// MARK: - Basal Schedule (Loop Compatibility)

/// Tandem basal schedule - 24 hourly rates for Loop compatibility
/// Converts variable-segment IDP to fixed 24-hour representation
public struct TandemBasalSchedule: Sendable, Equatable {
    /// Source profile ID
    public let idpId: Int
    /// Profile name
    public let profileName: String
    /// 24 hourly basal rates in U/hr (index 0 = midnight, index 12 = noon)
    public let hourlyRates: [Double]
    /// Original segments for reference
    public let segments: [TandemIDPSegment]
    
    /// Create from IDP segments
    /// - Parameters:
    ///   - idpId: Profile ID
    ///   - profileName: Profile name
    ///   - segments: IDP segments (must be sorted by startTimeMinutes)
    public init(idpId: Int, profileName: String, segments: [TandemIDPSegment]) {
        self.idpId = idpId
        self.profileName = profileName
        self.segments = segments
        
        // Convert variable segments to 24 fixed hourly rates
        var rates = [Double](repeating: 0.0, count: 24)
        let sortedSegments = segments.sorted { $0.startTimeMinutes < $1.startTimeMinutes }
        
        for hour in 0..<24 {
            let minuteOfDay = hour * 60
            
            // Find the segment that covers this hour
            // Segments are defined by their start time; a segment covers time from its start
            // until the next segment's start (or midnight wrap)
            var activeRate = 0.0
            
            for (i, segment) in sortedSegments.enumerated() {
                let segmentStart = segment.startTimeMinutes
                let segmentEnd: Int
                
                if i + 1 < sortedSegments.count {
                    segmentEnd = sortedSegments[i + 1].startTimeMinutes
                } else {
                    // Last segment covers until midnight (1440 minutes)
                    segmentEnd = 1440
                }
                
                // Check if this hour falls within this segment
                if minuteOfDay >= segmentStart && minuteOfDay < segmentEnd {
                    activeRate = segment.basalRate
                    break
                }
            }
            
            rates[hour] = activeRate
        }
        
        self.hourlyRates = rates
    }
    
    /// Total daily basal insulin in units
    public var totalDailyBasal: Double {
        hourlyRates.reduce(0, +)
    }
    
    /// Get basal rate for a specific hour (0-23)
    public func rate(forHour hour: Int) -> Double {
        guard hour >= 0 && hour < 24 else { return 0.0 }
        return hourlyRates[hour]
    }
    
    /// Get basal rate for current time
    public func currentRate() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        return rate(forHour: hour)
    }
    
    /// Demo basal schedule for testing (flat 0.8 U/hr)
    public static let demo = TandemBasalSchedule(
        idpId: 1,
        profileName: "Demo",
        segments: [
            TandemIDPSegment(
                idpId: 1,
                segmentIndex: 0,
                startTimeMinutes: 0,
                basalRateMilliunits: 800,
                carbRatioEncoded: 10000,
                targetBG: 100,
                isf: 50,
                statusFlags: .all
            )
        ]
    )
}
