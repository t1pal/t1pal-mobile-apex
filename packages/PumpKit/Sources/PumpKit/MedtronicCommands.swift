// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicCommands.swift
// PumpKit
//
// High-level Medtronic pump command implementations.
// Uses RileyLinkManager for RF communication.
// Trace: PUMP-MDT-006, PRD-005
//
// Usage:
//   let commander = MedtronicCommander(rileyLink: manager, pumpId: "123456")
//   let status = try await commander.getStatus()
//   try await commander.setTempBasal(rate: 1.5, duration: 30)

import Foundation

// MARK: - Medtronic Command Opcodes

/// Medtronic pump command opcodes
public enum MedtronicOpcode: UInt8, Sendable {
    // Status commands
    case getModel = 0x8D
    case getBattery = 0x72
    case getRemaining = 0x73
    case getStatus = 0x03
    case getTime = 0x70
    case getFirmwareVersion = 0x74  // MDT-IMPL-003: renamed from getSettings
    case getSettings = 0xC0  // MDT-IMPL-002: pump settings (maxBasal, maxBolus, etc)
    case getBasalProfile = 0x92
    case getHistoryPage = 0x80
    case getTempBasal = 0x98
    case getGlucosePage = 0x9A  // MDT-IMPL-005: CGM glucose history page
    
    // Control commands
    case powerControl = 0x5D
    
    // Basal schedule write commands (MDT-IMPL-006)
    case setBasalProfileA = 0x30        // CMD_SET_A_PROFILE
    case setBasalProfileB = 0x31        // CMD_SET_B_PROFILE
    case setBasalProfileStandard = 0x6F // CMD_SET_STD_PROFILE
    case setTempBasal = 0x4C
    case cancelTempBasal = 0x4F  // Different from suspend
    case setBolus = 0x42
    case suspendResume = 0x4D
    case setTime = 0x40
    
    // Remote commands
    case remoteButton = 0x5B  // Fixed: was 0x5A, Loop uses 0x5B (ButtonPressCarelinkMessageBody)
    case remoteACK = 0x06
    
    public var displayName: String {
        switch self {
        case .getModel: return "Get Model"
        case .getBattery: return "Get Battery"
        case .getRemaining: return "Get Remaining"
        case .getStatus: return "Get Status"
        case .getTime: return "Get Time"
        case .getFirmwareVersion: return "Get Firmware Version"
        case .getSettings: return "Get Settings"
        case .getBasalProfile: return "Get Basal Profile"
        case .getHistoryPage: return "Get History"
        case .getTempBasal: return "Get Temp Basal"
        case .getGlucosePage: return "Get Glucose Page"
        case .powerControl: return "Power Control"
        case .setBasalProfileA: return "Set Basal Profile A"
        case .setBasalProfileB: return "Set Basal Profile B"
        case .setBasalProfileStandard: return "Set Basal Profile Standard"
        case .setTempBasal: return "Set Temp Basal"
        case .cancelTempBasal: return "Cancel Temp Basal"
        case .setBolus: return "Set Bolus"
        case .suspendResume: return "Suspend/Resume"
        case .setTime: return "Set Time"
        case .remoteButton: return "Remote Button"
        case .remoteACK: return "ACK"
        }
    }
    
    public var isWriteCommand: Bool {
        switch self {
        case .setTempBasal, .cancelTempBasal, .setBolus, .suspendResume, .setTime,
             .setBasalProfileA, .setBasalProfileB, .setBasalProfileStandard:
            return true
        default:
            return false
        }
    }
}

// MARK: - Medtronic Status Response

/// Response from status command
public struct MedtronicStatusResponse: Sendable, Equatable {
    public let bolusing: Bool
    public let suspended: Bool
    public let normalBasalRunning: Bool
    public let tempBasalRunning: Bool
    public let reservoirLevel: Double  // Units
    public let batteryPercent: Int
    public let activeInsulin: Double?
    
    public init(
        bolusing: Bool = false,
        suspended: Bool = false,
        normalBasalRunning: Bool = true,
        tempBasalRunning: Bool = false,
        reservoirLevel: Double,
        batteryPercent: Int,
        activeInsulin: Double? = nil
    ) {
        self.bolusing = bolusing
        self.suspended = suspended
        self.normalBasalRunning = normalBasalRunning
        self.tempBasalRunning = tempBasalRunning
        self.reservoirLevel = reservoirLevel
        self.batteryPercent = batteryPercent
        self.activeInsulin = activeInsulin
    }
    
    public var canDeliver: Bool {
        !suspended && !bolusing
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 20.0
    }
    
    public var isLowBattery: Bool {
        batteryPercent < 20
    }
    
    // MARK: - Response Parsing (RL-WIRE-010, RL-PARSE-005)
    
    /// Parse status response from raw Medtronic response bytes
    /// Reference: decocare/commands.py ReadPumpStatus
    /// Format: [0]=status (03=normal), [1]=bolusing, [2]=suspended
    public static func parse(from data: Data) -> MedtronicStatusResponse? {
        guard data.count >= 3 else { return nil }
        
        // RL-PARSE-005: Fix per decocare reference
        // data[0] = status code (03 = normal)
        // data[1] = bolusing flag (1 = bolusing)
        // data[2] = suspended flag (1 = suspended)
        let bolusing = data[1] == 1
        let suspended = data[2] == 1
        
        // Basic status from response - other fields need additional commands
        return MedtronicStatusResponse(
            bolusing: bolusing,
            suspended: suspended,
            normalBasalRunning: !suspended && !bolusing,
            tempBasalRunning: false,  // Requires separate temp basal query
            reservoirLevel: 0,        // Requires getRemaining command
            batteryPercent: 0,        // Requires getBattery command
            activeInsulin: nil        // Not available in basic status
        )
    }
}

// MARK: - Medtronic Battery Response (RL-WIRE-013, RL-PARSE-004)

/// Battery status response parsing
/// Reference: decocare/commands.py ReadBatteryStatus
public struct MedtronicBatteryResponse: Sendable, Equatable {
    public let status: BatteryStatus
    public let volts: Double
    
    public enum BatteryStatus: Sendable, Equatable {
        case normal
        case low
        case unknown(rawValue: UInt8)
        
        init(statusByte: UInt8) {
            switch statusByte {
            case 0: self = .normal
            case 1: self = .low
            default: self = .unknown(rawValue: statusByte)
            }
        }
        
        public var percent: Int {
            switch self {
            case .normal: return 75  // Estimate based on voltage thresholds
            case .low: return 20
            case .unknown: return 50
            }
        }
    }
    
    /// Parse battery response from body bytes after 5-byte header strip
    /// Reference: decocare/commands.py ReadBatteryStatus (line 688)
    /// 
    /// Body format (after header strip):
    /// - body[0] = indicator (0=normal, 1=low)
    /// - body[1..2] = voltage (big-endian, /100)
    /// 
    /// Note: MinimedKit uses rxData[1] because it keeps full 65-byte message;
    /// we strip the 5-byte header first, so body[0] = indicator
    public static func parse(from data: Data) -> MedtronicBatteryResponse? {
        // Body needs at least 3 bytes: [status][volt_hi][volt_lo]
        guard data.count >= 3 else { return nil }
        
        let status = BatteryStatus(statusByte: data[0])
        let volts = Double(Int(data[1]) << 8 + Int(data[2])) / 100.0
        
        return MedtronicBatteryResponse(status: status, volts: volts)
    }
    
    /// Estimated battery percentage based on voltage
    /// Typical range: 1.1V (empty) to 1.55V (full)
    public var estimatedPercent: Int {
        // Voltage-based estimation
        let minVolts = 1.1
        let maxVolts = 1.55
        let percent = (volts - minVolts) / (maxVolts - minVolts) * 100
        return max(0, min(100, Int(percent)))
    }
}

// MARK: - Medtronic Firmware Version Response (MDT-IMPL-003)

/// Firmware version response parsing
/// Reference: MinimedKit GetPumpFirmwareVersionMessageBody.swift
public struct MedtronicFirmwareResponse: Sendable, Equatable {
    public let version: String
    
    /// Parse firmware version from body bytes after 5-byte header strip
    /// Body format: null-terminated ASCII string starting at byte 1
    /// (byte 0 is unused/padding per Loop convention)
    public static func parse(from data: Data) -> MedtronicFirmwareResponse? {
        guard data.count >= 2 else { return nil }
        
        // Find null terminator or use full length
        let stringStart = 1  // Skip byte 0 (unused)
        let stringEnd = data[stringStart...].firstIndex(of: 0) ?? data.endIndex
        
        guard stringEnd > stringStart,
              let version = String(data: data[stringStart..<stringEnd], encoding: .ascii) else {
            return nil
        }
        
        return MedtronicFirmwareResponse(version: version)
    }
}

// MARK: - Medtronic Time Response (MDT-IMPL-001)

/// Pump time response parsing
/// Reference: MinimedKit ReadTimeCarelinkMessageBody.swift
public struct MedtronicTimeResponse: Sendable, Equatable {
    public let dateComponents: DateComponents
    
    /// Parse time from body bytes after 5-byte header strip
    /// Body format (per MinimedKit):
    /// - body[1] = hour
    /// - body[2] = minute
    /// - body[3] = second
    /// - body[4..5] = year (big-endian)
    /// - body[6] = month
    /// - body[7] = day
    public static func parse(from data: Data) -> MedtronicTimeResponse? {
        // Need at least 8 bytes for time fields
        guard data.count >= 8 else { return nil }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: .gregorian)
        dateComponents.hour = Int(data[1])
        dateComponents.minute = Int(data[2])
        dateComponents.second = Int(data[3])
        dateComponents.year = Int(data[4]) << 8 + Int(data[5])
        dateComponents.month = Int(data[6])
        dateComponents.day = Int(data[7])
        
        return MedtronicTimeResponse(dateComponents: dateComponents)
    }
    
    /// Convert to Date using current timezone
    public var date: Date? {
        var components = dateComponents
        components.timeZone = TimeZone.current
        return components.date
    }
}

// MARK: - Medtronic Settings Response (MDT-IMPL-002)

/// Basal profile selection
public enum MedtronicBasalProfile: UInt8, Sendable, Equatable {
    case standard = 0
    case profileA = 1
    case profileB = 2
}

/// Pump settings response parsing
/// Reference: MinimedKit ReadSettingsCarelinkMessageBody.swift
public struct MedtronicSettingsResponse: Sendable, Equatable {
    public let maxBasal: Double
    public let maxBolus: Double
    public let insulinActionCurveHours: Int
    public let selectedBasalProfile: MedtronicBasalProfile
    
    private static let maxBolusMultiplier: Double = 10
    private static let maxBasalMultiplier: Double = 40
    
    /// Parse settings from body bytes after 5-byte header strip
    /// Body format depends on pump version:
    /// - x22 and earlier: maxBolus at [6], maxBasal at [7:9]
    /// - x23+: maxBolus at [7], maxBasal at [8:10]
    /// - selectedBasalProfile at [12], insulinActionCurveHours at [18]
    public static func parse(from data: Data, isNewer: Bool? = nil) -> MedtronicSettingsResponse? {
        // Need at least 19 bytes for all fields
        guard data.count >= 19 else { return nil }
        
        // Detect version from first byte if not specified
        let newer = isNewer ?? (data[0] == 25)  // x23 pumps have 25 as first byte
        
        let maxBolusTicks: UInt8
        let maxBasalTicks: UInt16
        
        if newer {
            maxBolusTicks = data[7]
            maxBasalTicks = UInt16(data[8]) << 8 + UInt16(data[9])
        } else {
            maxBolusTicks = data[6]
            maxBasalTicks = UInt16(data[7]) << 8 + UInt16(data[8])
        }
        
        let maxBolus = Double(maxBolusTicks) / maxBolusMultiplier
        let maxBasal = Double(maxBasalTicks) / maxBasalMultiplier
        
        let rawProfile = data[12]
        let selectedBasalProfile = MedtronicBasalProfile(rawValue: rawProfile) ?? .standard
        
        let insulinActionCurveHours = Int(data[18])
        
        return MedtronicSettingsResponse(
            maxBasal: maxBasal,
            maxBolus: maxBolus,
            insulinActionCurveHours: insulinActionCurveHours,
            selectedBasalProfile: selectedBasalProfile
        )
    }
}

// MARK: - Medtronic Reservoir Response (RL-WIRE-012, RL-PARSE-001)

/// Reservoir level response parsing
/// Reference: decocare/commands.py ReadRemainingInsulin, ReadRemainingInsulin523
public struct MedtronicReservoirResponse: Sendable, Equatable {
    public let unitsRemaining: Double
    
    /// Parse reservoir response from Medtronic message body
    /// 
    /// MDT-DIAG-FIX: Fixed to match MinimedKit byte positions on BODY data only
    /// Body is 65 bytes (no headers - headers already stripped by PumpMessage.init(rxData:))
    /// 
    /// Body offsets (per MinimedKit ReadRemainingInsulinMessageBody.swift):
    /// - x22 and earlier (scale≤10): body[1:3] 
    /// - x23+ (scale>10): body[3:5]
    ///
    /// Reference: MinimedKit rxData.subdata(in: 3..<5) / (1..<3) on message body
    public static func parse(from body: Data, scale: Int = 40) -> MedtronicReservoirResponse? {
        // Body only - no headers. Minimum body length is 5 bytes for x23+ or 3 for older
        let minBodyBytes = scale > 10 ? 5 : 3  // Body indices [3:5] or [1:3]
        guard body.count >= minBodyBytes else { return nil }
        
        let strokes: Int
        if scale > 10 {
            // x23+ pumps: body[3:5] with scale 40
            strokes = Int(body[3]) << 8 + Int(body[4])
        } else {
            // x22 and earlier: body[1:3] with scale 10
            strokes = Int(body[1]) << 8 + Int(body[2])
        }
        
        let units = Double(strokes) / Double(scale)
        return MedtronicReservoirResponse(unitsRemaining: units)
    }
}

// MARK: - Medtronic Temp Basal Response (MDT-SYNTH-003)

/// Response from ReadTempBasal command
/// Reference: MinimedKit ReadTempBasalCarelinkMessageBody
public struct MedtronicTempBasalResponse: Sendable, Equatable {
    public enum RateType: Sendable, Equatable {
        case absolute  // U/hr
        case percent   // %
        
        init?(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .absolute
            case 1: self = .percent
            default: return nil
            }
        }
    }
    
    /// Rate (U/hr for absolute, % for percent)
    public let rate: Double
    /// Rate type (absolute or percent)
    public let rateType: RateType
    /// Time remaining in seconds
    public let timeRemaining: TimeInterval
    
    private static let strokesPerUnit: Double = 40.0
    
    /// Parse temp basal response from raw Medtronic response bytes
    /// Reference: MinimedKit ReadTempBasalCarelinkMessageBody
    /// Format: [0]=?, [1]=rateType, [2]=percentRate, [3..4]=strokes, [5..6]=minutes
    public static func parse(from data: Data) -> MedtronicTempBasalResponse? {
        // Minimum 7 bytes required for full parsing
        guard data.count >= 7 else { return nil }
        
        let rawRateType = data[1]
        guard let rateType = RateType(rawValue: rawRateType) else { return nil }
        
        let rate: Double
        switch rateType {
        case .absolute:
            // strokes = big-endian bytes[3:5], rate = strokes / 40
            let strokes = Int(data[3]) << 8 + Int(data[4])
            rate = Double(strokes) / strokesPerUnit
        case .percent:
            // percent value is directly in byte[2]
            rate = Double(data[2])
        }
        
        // minutes = big-endian bytes[5:7]
        let minutes = Int(data[5]) << 8 + Int(data[6])
        let timeRemaining = TimeInterval(minutes * 60)
        
        return MedtronicTempBasalResponse(
            rate: rate,
            rateType: rateType,
            timeRemaining: timeRemaining
        )
    }
    
    /// Whether temp basal is currently active
    public var isActive: Bool {
        timeRemaining > 0
    }
    
    /// Time remaining in minutes
    public var minutesRemaining: Int {
        Int(timeRemaining / 60)
    }
}

// MARK: - Medtronic Glucose Page Command (MDT-IMPL-005)

/// Glucose page request/response for CGM-enabled pumps
/// Reference: MinimedKit GetGlucosePageMessageBody
public struct MedtronicGlucosePageCommand: Sendable, Equatable {
    /// Page number to fetch
    public let pageNum: UInt32
    
    /// Create glucose page request
    public init(pageNum: UInt32) {
        self.pageNum = pageNum
    }
    
    /// Generate TX data for glucose page request
    /// Format: [0x04][pageNum big-endian 4 bytes]
    public var txData: Data {
        let numArgs: UInt8 = 4
        var data = Data([numArgs])
        // Page number as big-endian 4 bytes
        data.append(UInt8((pageNum >> 24) & 0xFF))
        data.append(UInt8((pageNum >> 16) & 0xFF))
        data.append(UInt8((pageNum >> 8) & 0xFF))
        data.append(UInt8(pageNum & 0xFF))
        return data
    }
}

/// Glucose page response frame
/// Reference: MinimedKit GetGlucosePageMessageBody
public struct MedtronicGlucosePageResponse: Sendable, Equatable {
    /// Frame number (0-indexed)
    public let frameNumber: Int
    /// True if this is the last frame
    public let lastFrame: Bool
    /// Frame data (up to 64 bytes)
    public let frameData: Data
    
    /// Parse glucose page response from RX data
    /// - Parameter data: Raw response body (65 bytes)
    public init?(data: Data) {
        guard data.count >= 1 else { return nil }
        
        // Byte 0: frame number (lower 7 bits) + last frame flag (bit 7)
        frameNumber = Int(data[0]) & 0b01111111
        lastFrame = (data[0] & 0b10000000) != 0
        
        // Bytes 1-64: frame data
        if data.count > 1 {
            frameData = data.subdata(in: 1..<min(65, data.count))
        } else {
            frameData = Data()
        }
    }
}

// MARK: - Medtronic Basal Schedule Command (MDT-IMPL-006)

/// Basal schedule entry for write commands
/// Reference: MinimedKit BasalSchedule.swift
public struct MedtronicBasalScheduleEntry: Sendable, Equatable {
    /// Entry index (0-47 for 30-minute slots)
    public let index: Int
    /// Time offset from midnight in seconds
    public let timeOffset: TimeInterval
    /// Rate in U/hr
    public let rate: Double
    
    public init(index: Int, timeOffset: TimeInterval, rate: Double) {
        self.index = index
        self.timeOffset = timeOffset
        self.rate = rate
    }
    
    /// Raw 3-byte encoding per Loop BasalScheduleEntry.rawValue
    /// Format: [rate_lo][rate_hi][time_slot]
    /// - rate: UInt16 little-endian, value = rate * 40
    /// - time_slot: UInt8, value = timeOffset / 30 minutes
    public var rawValue: Data {
        var buffer = Data(count: 3)
        let strokes = UInt16(clamping: Int(rate * 40))
        buffer[0] = UInt8(strokes & 0xFF)
        buffer[1] = UInt8((strokes >> 8) & 0xFF)
        buffer[2] = UInt8(clamping: Int(timeOffset / 1800))  // 30-minute slots
        return buffer
    }
    
    /// Parse from 3-byte raw value
    public init?(rawValue: Data) {
        guard rawValue.count == 3 else { return nil }
        let strokes = UInt16(rawValue[0]) + UInt16(rawValue[1]) << 8
        let rate = Double(strokes) / 40.0
        let slot = Int(rawValue[2])
        let timeOffset = TimeInterval(slot * 30 * 60)
        guard timeOffset < 86400 else { return nil }  // < 24 hours
        self.init(index: slot, timeOffset: timeOffset, rate: rate)
    }
}

/// Basal schedule for write commands
/// Reference: MinimedKit BasalSchedule.swift, DataFrameMessageBody.swift
public struct MedtronicBasalScheduleCommand: Sendable, Equatable {
    /// Schedule entries (up to 48 for 30-min slots)
    public let entries: [MedtronicBasalScheduleEntry]
    /// Target profile
    public let profile: MedtronicBasalProfile
    
    /// Raw value length (192 bytes per Loop)
    public static let rawValueLength = 192
    /// Frame content size (64 bytes per CarelinkLongMessageBody - 1 for frame header)
    public static let frameContentSize = 64
    
    public init(entries: [MedtronicBasalScheduleEntry], profile: MedtronicBasalProfile = .standard) {
        self.entries = entries
        self.profile = profile
    }
    
    /// Create from rate/time pairs
    public init(rates: [(timeOffset: TimeInterval, rate: Double)], profile: MedtronicBasalProfile = .standard) {
        self.entries = rates.enumerated().map { index, pair in
            MedtronicBasalScheduleEntry(index: index, timeOffset: pair.timeOffset, rate: pair.rate)
        }
        self.profile = profile
    }
    
    /// Get opcode for this profile
    /// Reference: MinimedKit PumpOpsSession.setBasalSchedule
    public var opcode: MedtronicOpcode {
        switch profile {
        case .standard: return .setBasalProfileStandard
        case .profileA: return .setBasalProfileA
        case .profileB: return .setBasalProfileB
        }
    }
    
    /// Raw schedule data (192 bytes)
    public var rawValue: Data {
        var buffer = Data(count: Self.rawValueLength)
        var byteIndex = 0
        
        for entry in entries {
            let rawEntry = entry.rawValue
            buffer.replaceSubrange(byteIndex..<(byteIndex + rawEntry.count), with: rawEntry)
            byteIndex += rawEntry.count
        }
        
        // Empty schedule marker (0x3f in byte 2)
        if entries.isEmpty {
            buffer[2] = 0x3F
        }
        
        return buffer
    }
    
    /// Split raw data into frames for transmission
    /// Reference: MinimedKit DataFrameMessageBody.dataFramesFromContents
    /// Each frame: [frameHeader][contents up to 64 bytes]
    /// Frame header: bit 7 = isLastFrame, bits 0-6 = frameNumber (1-indexed)
    public var frames: [Data] {
        var result: [Data] = []
        let contents = rawValue
        var frameNumber = 1
        var offset = 0
        
        while offset < contents.count {
            let remaining = contents.count - offset
            let chunkSize = min(Self.frameContentSize, remaining)
            let isLast = (offset + chunkSize) >= contents.count
            
            var frame = Data(count: 65)  // CarelinkLongMessageBody.length
            var header = UInt8(frameNumber)
            if isLast {
                header |= 0x80
            }
            frame[0] = header
            frame.replaceSubrange(1..<(1 + chunkSize), with: contents[offset..<(offset + chunkSize)])
            
            result.append(frame)
            frameNumber += 1
            offset += chunkSize
        }
        
        return result
    }
}

// MARK: - Medtronic Bolus Command (MDT-SYNTH-004)

/// Bolus command TX formatting
/// Reference: MinimedKit BolusCarelinkMessageBody
public struct MedtronicBolusCommand: Sendable, Equatable {
    /// Units to deliver
    public let units: Double
    /// Insulin bit packing scale (40 for x54+, 10 for x22)
    public let scale: Int
    /// Calculated strokes
    public let strokes: Int
    /// Body length (2 for scale=40, 1 for scale=10)
    public let bodyLength: Int
    
    /// Create a bolus command
    /// - Parameters:
    ///   - units: Units to deliver
    ///   - scale: Insulin bit packing scale (40 for x54+ pumps, 10 for x22)
    public init(units: Double, scale: Int = 40) {
        self.units = units
        self.scale = scale
        
        if scale >= 40 {
            self.bodyLength = 2
            // Calculate scroll rate based on units
            let scrollRate: Int
            switch units {
            case let u where u > 10: scrollRate = 4
            case let u where u > 1: scrollRate = 2
            default: scrollRate = 1
            }
            // Calculate strokes with scroll rate quantization
            self.strokes = Int(units * Double(scale / scrollRate)) * scrollRate
        } else {
            // Scale 10 for older pumps
            self.bodyLength = 1
            self.strokes = Int(units * Double(scale))
        }
    }
    
    /// Generate TX data for bolus command body
    /// Format: [length][strokes_hi][strokes_lo] (scale=40) or [length][strokes] (scale=10)
    public var txData: Data {
        if bodyLength == 2 {
            // Two-byte strokes for scale=40
            return Data([
                UInt8(bodyLength),
                UInt8((strokes >> 8) & 0xFF),
                UInt8(strokes & 0xFF)
            ])
        } else {
            // One-byte strokes for scale=10
            return Data([
                UInt8(bodyLength),
                UInt8(strokes & 0xFF)
            ])
        }
    }
    
    /// Calculate delivered units from strokes
    public var deliveredUnits: Double {
        Double(strokes) / Double(scale)
    }
    
    /// Parse bolus command body from TX data
    /// - Parameter data: Raw bolus command body bytes
    /// - Returns: Parsed command or nil if invalid
    public static func parse(from data: Data) -> MedtronicBolusCommand? {
        guard data.count >= 2 else { return nil }
        
        let length = Int(data[0])
        if length == 2 {
            guard data.count >= 3 else { return nil }
            let strokes = Int(data[1]) << 8 + Int(data[2])
            let units = Double(strokes) / 40.0
            return MedtronicBolusCommand(units: units, scale: 40)
        } else if length == 1 {
            let strokes = Int(data[1])
            let units = Double(strokes) / 10.0
            return MedtronicBolusCommand(units: units, scale: 10)
        }
        return nil
    }
}

// MARK: - Medtronic Temp Basal Command (MDT-SYNTH-005)

/// Temp basal TX command formatting
/// Reference: MinimedKit ChangeTempBasalCarelinkMessageBody
public struct MedtronicTempBasalCommand: Sendable, Equatable {
    /// Rate in U/hr
    public let rate: Double
    /// Duration in seconds
    public let duration: TimeInterval
    /// Calculated strokes (rate * 40)
    public let strokes: Int
    /// Time segments (duration / 30 minutes)
    public let timeSegments: Int
    
    private static let strokesPerUnit: Double = 40.0
    private static let minutesPerSegment: Int = 30
    
    /// Create a temp basal command
    /// - Parameters:
    ///   - unitsPerHour: Rate in U/hr (0.0 for suspend)
    ///   - duration: Duration in seconds
    public init(unitsPerHour: Double, duration: TimeInterval) {
        self.rate = unitsPerHour
        self.duration = duration
        self.strokes = Int(unitsPerHour * Self.strokesPerUnit)
        self.timeSegments = Int(duration / TimeInterval(Self.minutesPerSegment * 60))
    }
    
    /// Generate TX data for temp basal command body
    /// Format: [0x03][strokes_hi][strokes_lo][time_segments]
    public var txData: Data {
        Data([
            0x03,  // length
            UInt8((strokes >> 8) & 0xFF),
            UInt8(strokes & 0xFF),
            UInt8(timeSegments)
        ])
    }
    
    /// Calculate actual delivered rate from strokes
    public var deliveredRate: Double {
        Double(strokes) / Self.strokesPerUnit
    }
    
    /// Calculate actual duration from segments
    public var deliveredDurationMinutes: Int {
        timeSegments * Self.minutesPerSegment
    }
    
    /// Parse temp basal command body from TX data
    /// - Parameter data: Raw temp basal command body bytes
    /// - Returns: Parsed command or nil if invalid
    public static func parse(from data: Data) -> MedtronicTempBasalCommand? {
        guard data.count >= 4 else { return nil }
        guard data[0] == 0x03 else { return nil }  // length byte
        
        let strokes = Int(data[1]) << 8 + Int(data[2])
        let timeSegments = Int(data[3])
        
        let rate = Double(strokes) / strokesPerUnit
        let duration = TimeInterval(timeSegments * minutesPerSegment * 60)
        
        return MedtronicTempBasalCommand(unitsPerHour: rate, duration: duration)
    }
}

// MARK: - Medtronic Temp Basal

/// Temp basal setting
public struct MedtronicTempBasal: Sendable, Equatable {
    public let rate: Double           // U/hr
    public let duration: TimeInterval // Seconds
    public let startTime: Date
    
    public init(rate: Double, duration: TimeInterval, startTime: Date = Date()) {
        self.rate = rate
        self.duration = duration
        self.startTime = startTime
    }
    
    public var durationMinutes: Int {
        Int(duration / 60)
    }
    
    public var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    public var isExpired: Bool {
        Date() >= endTime
    }
    
    public var remainingDuration: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }
}

// MARK: - Medtronic Commander

/// High-level Medtronic pump command interface
public actor MedtronicCommander {
    // MARK: - Properties
    
    private let rileyLink: RileyLinkManager
    private let pumpId: String
    private let variant: MedtronicVariant
    
    private(set) var lastStatus: MedtronicStatusResponse?
    private(set) var activeTempBasal: MedtronicTempBasal?
    private(set) var isSuspended: Bool = false
    
    // MARK: - Init
    
    public init(
        rileyLink: RileyLinkManager,
        pumpId: String,
        variant: MedtronicVariant = .model554_NA
    ) {
        self.rileyLink = rileyLink
        self.pumpId = pumpId
        self.variant = variant
    }
    
    // MARK: - RF Frequency
    
    private var rfFrequency: Double {
        variant.rfFrequency
    }
    
    // MARK: - Status Commands
    
    /// Get pump status
    /// RL-WIRE-010, RL-WIRE-011: Parse real Medtronic pump response
    /// ARCH-007: Throws if response cannot be parsed (no silent fallback)
    public func getStatus() async throws -> MedtronicStatusResponse {
        PumpLogger.status.info("Reading Medtronic pump status")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getStatus.rawValue,
            frequency: rfFrequency
        )
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let parsed = MedtronicStatusResponse.parse(from: responseData) else {
            PumpLogger.status.error("Failed to parse status response: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        // Get additional data for complete status
        let reservoir = try? await getReservoirLevel()
        let battery = try? await getBatteryLevel()
        
        let status = MedtronicStatusResponse(
            bolusing: parsed.bolusing,
            suspended: parsed.suspended,
            normalBasalRunning: !parsed.suspended && activeTempBasal == nil,
            tempBasalRunning: activeTempBasal != nil && !activeTempBasal!.isExpired,
            reservoirLevel: reservoir ?? 0,
            batteryPercent: battery ?? 0,
            activeInsulin: nil  // Requires IOB calculation
        )
        
        isSuspended = status.suspended
        lastStatus = status
        return status
    }
    
    /// Get pump model
    public func getModel() async throws -> String {
        PumpLogger.general.info("Reading Medtronic pump model")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getModel.rawValue,
            frequency: rfFrequency
        )
        
        // Model response is ASCII string in bytes 1-3 (e.g., "554")
        if responseData.count >= 4 {
            let modelBytes = responseData.subdata(in: 1..<4)
            if let modelString = String(data: modelBytes, encoding: .ascii) {
                return modelString.trimmingCharacters(in: .controlCharacters)
            }
        }
        
        // Fallback to variant model
        return variant.generation.rawValue
    }
    
    /// Get reservoir level
    /// RL-WIRE-012: Parse real Medtronic reservoir response
    /// ARCH-007: Throws if response cannot be parsed (no silent fallback)
    public func getReservoirLevel() async throws -> Double {
        PumpLogger.status.info("Reading reservoir level")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getRemaining.rawValue,
            frequency: rfFrequency
        )
        
        // MDT-DIAG-FIX: Strip 5-byte header to get body only
        // responseData format: [packetType:1][address:3][msgType:1][body:65]
        let headerSize = 5
        guard responseData.count > headerSize else {
            PumpLogger.status.error("Response too short: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        let bodyData = responseData.subdata(in: headerSize..<responseData.count)
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let parsed = MedtronicReservoirResponse.parse(
            from: bodyData,
            scale: variant.insulinBitPackingScale
        ) else {
            PumpLogger.status.error("Failed to parse reservoir response: \(bodyData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        return parsed.unitsRemaining
    }
    
    /// Get battery level
    /// RL-WIRE-013: Parse real Medtronic battery response
    /// ARCH-007: Throws if response cannot be parsed (no silent fallback)
    public func getBatteryLevel() async throws -> Int {
        PumpLogger.status.info("Reading battery level")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getBattery.rawValue,
            frequency: rfFrequency
        )
        
        // MDT-FID-004: Strip 5-byte header to get body only (matches reservoir pattern)
        // responseData format: [packetType:1][address:3][msgType:1][body:N]
        let headerSize = 5
        guard responseData.count > headerSize else {
            PumpLogger.status.error("Response too short: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        let bodyData = responseData.subdata(in: headerSize..<responseData.count)
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let parsed = MedtronicBatteryResponse.parse(from: bodyData) else {
            PumpLogger.status.error("Failed to parse battery response: \(bodyData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        return parsed.estimatedPercent
    }
    
    /// Get firmware version
    /// MDT-IMPL-003: Added firmware version getter
    public func getFirmwareVersion() async throws -> String {
        PumpLogger.status.info("Reading firmware version")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getFirmwareVersion.rawValue,
            frequency: rfFrequency
        )
        
        // Strip 5-byte header to get body only
        let headerSize = 5
        guard responseData.count > headerSize else {
            PumpLogger.status.error("Response too short: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        let bodyData = responseData.subdata(in: headerSize..<responseData.count)
        
        guard let parsed = MedtronicFirmwareResponse.parse(from: bodyData) else {
            PumpLogger.status.error("Failed to parse firmware response: \(bodyData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        return parsed.version
    }
    
    /// Get pump time
    /// MDT-IMPL-001: Added time getter
    public func getTime() async throws -> Date {
        PumpLogger.status.info("Reading pump time")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getTime.rawValue,
            frequency: rfFrequency
        )
        
        // Strip 5-byte header to get body only
        let headerSize = 5
        guard responseData.count > headerSize else {
            PumpLogger.status.error("Response too short: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        let bodyData = responseData.subdata(in: headerSize..<responseData.count)
        
        guard let parsed = MedtronicTimeResponse.parse(from: bodyData),
              let date = parsed.date else {
            PumpLogger.status.error("Failed to parse time response: \(bodyData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        return date
    }
    
    /// Get pump settings (maxBasal, maxBolus, insulinActionCurve, basalProfile)
    /// MDT-IMPL-002: Added settings getter
    public func getSettings() async throws -> MedtronicSettingsResponse {
        PumpLogger.status.info("Reading pump settings")
        
        let responseData = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.getSettings.rawValue,
            frequency: rfFrequency
        )
        
        // Strip 5-byte header to get body only
        let headerSize = 5
        guard responseData.count > headerSize else {
            PumpLogger.status.error("Response too short: \(responseData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        let bodyData = responseData.subdata(in: headerSize..<responseData.count)
        
        guard let parsed = MedtronicSettingsResponse.parse(from: bodyData) else {
            PumpLogger.status.error("Failed to parse settings response: \(bodyData.hexEncodedString())")
            throw MedtronicCommandError.invalidResponse
        }
        
        return parsed
    }
    
    // MARK: - Basal Schedule Commands (MDT-IMPL-006)
    
    /// Set basal schedule for a profile
    /// Reference: MinimedKit PumpOpsSession.setBasalSchedule
    /// Uses multi-frame transmission pattern for 192-byte schedule data
    public func setBasalSchedule(_ command: MedtronicBasalScheduleCommand) async throws {
        let frames = command.frames
        guard let firstFrame = frames.first else {
            PumpLogger.basal.error("Empty basal schedule")
            throw MedtronicCommandError.invalidBasalSchedule
        }
        
        PumpLogger.basal.info("Setting basal schedule for profile \(command.profile.rawValue), \(command.entries.count) entries, \(frames.count) frames")
        
        // Send first frame with runCommandWithArguments pattern
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: command.opcode.rawValue,
            params: firstFrame,
            frequency: rfFrequency
        )
        
        // Send remaining frames
        for frame in frames.dropFirst() {
            _ = try await rileyLink.sendMedtronicCommand(
                pumpId: pumpId,
                opcode: command.opcode.rawValue,
                params: frame,
                frequency: rfFrequency
            )
        }
        
        PumpLogger.basal.info("Basal schedule set successfully")
    }
    
    // MARK: - Temp Basal Commands
    
    /// Set temp basal rate
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard duration >= 30 * 60 && duration <= 24 * 60 * 60 else {
            throw MedtronicCommandError.invalidDuration
        }
        
        guard rate >= 0 && rate <= variant.maxBasalRate else {
            throw MedtronicCommandError.invalidRate
        }
        
        PumpLogger.basal.tempBasalSet(rate: rate, duration: duration)
        
        // Build params: rate (2 bytes), duration in half-hours (1 byte)
        let rateStrokes = UInt16(rate / variant.basalIncrement)
        let halfHours = UInt8(duration / 1800)
        
        var params = Data()
        params.append(UInt8(rateStrokes >> 8))
        params.append(UInt8(rateStrokes & 0xFF))
        params.append(halfHours)
        
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.setTempBasal.rawValue,
            params: params,
            frequency: rfFrequency
        )
        
        activeTempBasal = MedtronicTempBasal(rate: rate, duration: duration)
    }
    
    /// Cancel active temp basal
    public func cancelTempBasal() async throws {
        PumpLogger.basal.tempBasalCancelled()
        
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.cancelTempBasal.rawValue,
            frequency: rfFrequency
        )
        
        activeTempBasal = nil
    }
    
    // MARK: - Bolus Commands
    
    /// Deliver bolus
    public func deliverBolus(units: Double) async throws {
        guard units > 0 && units <= variant.maxBolus else {
            throw MedtronicCommandError.invalidBolusAmount
        }
        
        // Check if pump is ready
        if let status = lastStatus {
            guard status.canDeliver else {
                throw MedtronicCommandError.pumpNotReady
            }
        } else {
            // Refresh status
            let currentStatus = try await getStatus()
            guard currentStatus.canDeliver else {
                throw MedtronicCommandError.pumpNotReady
            }
        }
        
        PumpLogger.bolus.bolusDelivered(units: units)
        
        // Build params: units in strokes (10ths of unit for most pumps)
        let strokes = UInt16(units * 10)
        var params = Data()
        params.append(UInt8(strokes >> 8))
        params.append(UInt8(strokes & 0xFF))
        
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.setBolus.rawValue,
            params: params,
            frequency: rfFrequency
        )
    }
    
    // MARK: - Suspend/Resume
    
    /// Suspend delivery
    public func suspend() async throws {
        guard !isSuspended else { return }
        
        PumpLogger.delivery.deliverySuspended()
        
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.suspendResume.rawValue,
            params: Data([0x01]), // Suspend
            frequency: rfFrequency
        )
        
        isSuspended = true
        activeTempBasal = nil
    }
    
    /// Resume delivery
    public func resume() async throws {
        guard isSuspended else { return }
        
        PumpLogger.delivery.deliveryResumed()
        
        _ = try await rileyLink.sendMedtronicCommand(
            pumpId: pumpId,
            opcode: MedtronicOpcode.suspendResume.rawValue,
            params: Data([0x00]), // Resume
            frequency: rfFrequency
        )
        
        isSuspended = false
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic info
    public func diagnosticInfo() async -> MedtronicCommanderDiagnostics {
        MedtronicCommanderDiagnostics(
            pumpId: pumpId,
            variant: variant,
            isSuspended: isSuspended,
            hasTempBasal: activeTempBasal != nil,
            lastStatus: lastStatus
        )
    }
}

// MARK: - Diagnostics

/// Diagnostic information
public struct MedtronicCommanderDiagnostics: Sendable {
    public let pumpId: String
    public let variant: MedtronicVariant
    public let isSuspended: Bool
    public let hasTempBasal: Bool
    public let lastStatus: MedtronicStatusResponse?
    
    public var description: String {
        var parts: [String] = []
        parts.append("Pump: \(pumpId)")
        parts.append("Variant: \(variant.displayName)")
        parts.append("Suspended: \(isSuspended)")
        parts.append("Temp Basal: \(hasTempBasal)")
        if let status = lastStatus {
            parts.append("Reservoir: \(status.reservoirLevel)U")
            parts.append("Battery: \(status.batteryPercent)%")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Command Errors

/// Medtronic command errors
public enum MedtronicCommandError: Error, Sendable, Equatable {
    case notConnected
    case pumpNotReady
    case invalidDuration
    case invalidRate
    case invalidBolusAmount
    case invalidBasalSchedule
    case invalidResponse
    case commandFailed(String)
    case communicationFailed
    case timeout
}

extension MedtronicCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to pump"
        case .pumpNotReady:
            return "Pump not ready for commands"
        case .invalidDuration:
            return "Invalid duration (must be 30min-24hr)"
        case .invalidRate:
            return "Invalid basal rate"
        case .invalidBolusAmount:
            return "Invalid bolus amount"
        case .invalidBasalSchedule:
            return "Invalid basal schedule (empty or malformed)"
        case .invalidResponse:
            return "Invalid or unparseable response from pump"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        case .communicationFailed:
            return "Communication failed"
        case .timeout:
            return "Command timed out"
        }
    }
}
