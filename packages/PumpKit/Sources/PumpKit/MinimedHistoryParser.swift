/// Medtronic pump history page parser
/// Parses history pages from Medtronic pumps into structured events.
/// Based on Loop's MinimedKit HistoryPage.swift and decocare/history.py
///
/// Reference: externals/MinimedKit/MinimedKit/Messages/Models/HistoryPage.swift
///
/// RL-WIRE-016, PROD-AUDIT-MDT-VARIANT

import Foundation

// MARK: - Pump Event Type Opcodes

/// Medtronic history record opcodes
/// Reference: Loop MinimedKit PumpEventType.swift
public enum MinimedHistoryOpcode: UInt8, Sendable {
    case bolusNormal = 0x01
    case prime = 0x03
    case alarmPump = 0x06
    case resultDailyTotal = 0x07
    case changeBasalProfilePattern = 0x08
    case changeBasalProfile = 0x09
    case calBGForPH = 0x0A
    case alarmSensor = 0x0B
    case clearAlarm = 0x0C
    case selectBasalProfile = 0x14
    case tempBasalDuration = 0x16
    case changeTime = 0x17
    case newTime = 0x18
    case journalEntryPumpLowBattery = 0x19
    case battery = 0x1A
    case setAutoOff = 0x1B
    case suspend = 0x1E
    case resume = 0x1F
    case selftest = 0x20
    case rewind = 0x21
    case clearSettings = 0x22
    case changeChildBlockEnable = 0x23
    case changeMaxBolus = 0x24
    case enableDisableRemote = 0x26
    case changeMaxBasal = 0x2C
    case enableBolusWizard = 0x2D
    case changeBGReminderOffset = 0x31
    case changeAlarmClockTime = 0x32
    case tempBasal = 0x33
    case journalEntryPumpLowReservoir = 0x34
    case alarmClockReminder = 0x35
    case changeMeterId = 0x36
    case bgReceived = 0x3F
    case journalEntryMealMarker = 0x40
    case journalEntryExerciseMarker = 0x41
    case journalEntryInsulinMarker = 0x42
    case journalEntryOtherMarker = 0x43
    case bolusWizardSetup = 0x5A
    case bolusWizardBolusEstimate = 0x5B
    case unabsorbedInsulin = 0x5C
    case saveSettings = 0x5D
    case changeVariableBolus = 0x5E
    case changeAudioBolus = 0x5F
    case dailyTotal515 = 0x6C
    case dailyTotal522 = 0x6D
    case dailyTotal523 = 0x6E
    case basalProfileStart = 0x7B
    case changeTimeFormat = 0x64
    case changeReservoirWarningTime = 0x65
    
    /// Get the length of this record type
    /// - Parameter isLargerPump: True for 523/723 and newer pumps
    /// - Returns: Record length in bytes, or nil for variable-length records
    public func length(isLargerPump: Bool) -> Int? {
        switch self {
        case .bolusNormal:
            return isLargerPump ? 13 : 9
        case .prime:
            return 10
        case .alarmPump:
            return 9
        case .resultDailyTotal:
            return 10
        case .changeBasalProfilePattern:
            return 152
        case .changeBasalProfile:
            return 152
        case .calBGForPH:
            return 7
        case .alarmSensor:
            return 8
        case .clearAlarm:
            return 7
        case .selectBasalProfile:
            return 7
        case .tempBasalDuration:
            return 7
        case .changeTime:
            return 14
        case .newTime:
            return 7
        case .journalEntryPumpLowBattery:
            return 7
        case .battery:
            return 7
        case .setAutoOff:
            return 7
        case .suspend:
            return 7
        case .resume:
            return 7
        case .selftest:
            return 7
        case .rewind:
            return 7
        case .clearSettings:
            return 7
        case .changeChildBlockEnable:
            return 7
        case .changeMaxBolus:
            return 7
        case .enableDisableRemote:
            return 21
        case .changeMaxBasal:
            return 7
        case .enableBolusWizard:
            return 7
        case .changeBGReminderOffset:
            return 7
        case .changeAlarmClockTime:
            return 7
        case .tempBasal:
            return 8
        case .journalEntryPumpLowReservoir:
            return 7
        case .alarmClockReminder:
            return 7
        case .changeMeterId:
            return 21
        case .bgReceived:
            return 10
        case .journalEntryMealMarker:
            return 9
        case .journalEntryExerciseMarker:
            return 8
        case .journalEntryInsulinMarker:
            return 8
        case .journalEntryOtherMarker:
            return 7
        case .bolusWizardSetup:
            return isLargerPump ? 144 : 124
        case .bolusWizardBolusEstimate:
            return isLargerPump ? 22 : 20
        case .unabsorbedInsulin:
            return nil  // Variable length, first byte contains length
        case .saveSettings:
            return 7
        case .changeVariableBolus:
            return 7
        case .changeAudioBolus:
            return 7
        case .dailyTotal515:
            return 38
        case .dailyTotal522:
            return 44
        case .dailyTotal523:
            return 52
        case .basalProfileStart:
            return 10
        case .changeTimeFormat:
            return 7
        case .changeReservoirWarningTime:
            return 7
        }
    }
}

// MARK: - History Parser

/// Parser for Medtronic history pages
public struct MinimedHistoryParser: Sendable {
    
    /// The pump variant being parsed (if known)
    public let variant: MedtronicVariant?
    
    /// Whether this is a larger pump (523/723 and newer)
    public let isLargerPump: Bool
    
    /// Insulin bit packing scale (10 for older pumps, 40 for larger)
    public let insulinBitPackingScale: Double
    
    /// Initialize with a MedtronicVariant for full model awareness
    /// - Parameter variant: The pump variant providing model-specific configuration
    public init(variant: MedtronicVariant) {
        self.variant = variant
        self.isLargerPump = variant.isLargerPump
        self.insulinBitPackingScale = Double(variant.insulinBitPackingScale)
    }
    
    /// Initialize with a simple isLargerPump flag (backward compatibility)
    /// - Parameter isLargerPump: True for 523/723 and newer pumps
    public init(isLargerPump: Bool = true) {
        self.variant = nil
        self.isLargerPump = isLargerPump
        self.insulinBitPackingScale = isLargerPump ? 40.0 : 10.0
    }
    
    /// Parse a history page into events
    /// - Parameter data: Raw history page data (1024 bytes typically)
    /// - Returns: Array of parsed history events
    public func parse(_ data: Data) -> [MinimedHistoryEvent] {
        var events: [MinimedHistoryEvent] = []
        var offset = 0
        let length = min(data.count, 1022)  // Exclude CRC bytes
        
        while offset < length {
            // Skip null padding bytes
            if data[offset] == 0x00 {
                offset += 1
                continue
            }
            
            guard let opcode = MinimedHistoryOpcode(rawValue: data[offset]) else {
                // Unknown opcode - skip this byte and continue
                offset += 1
                continue
            }
            
            // Get record length
            let recordLength: Int
            if let fixedLength = opcode.length(isLargerPump: isLargerPump) {
                recordLength = fixedLength
            } else {
                // Variable length record - length in first byte after opcode
                guard offset + 1 < length else { break }
                recordLength = Int(data[offset + 1])
            }
            
            // Check if we have enough data
            guard offset + recordLength <= data.count else { break }
            
            let recordData = data.subdata(in: offset..<(offset + recordLength))
            
            // Parse the record
            if let event = parseRecord(opcode: opcode, data: recordData) {
                events.append(event)
            }
            
            offset += recordLength
        }
        
        return events
    }
    
    /// Parse a single history record
    private func parseRecord(opcode: MinimedHistoryOpcode, data: Data) -> MinimedHistoryEvent? {
        let timestamp = parseTimestamp(data: data, offset: opcodeTimestampOffset(opcode))
        
        switch opcode {
        case .bolusNormal:
            return parseBolusNormal(data: data, timestamp: timestamp)
        case .tempBasal:
            return parseTempBasal(data: data, timestamp: timestamp)
        case .suspend:
            return MinimedHistoryEvent(type: .suspend, timestamp: timestamp, rawData: data)
        case .resume:
            return MinimedHistoryEvent(type: .resume, timestamp: timestamp, rawData: data)
        case .rewind:
            return MinimedHistoryEvent(type: .rewind, timestamp: timestamp, rawData: data)
        case .prime:
            return parsePrime(data: data, timestamp: timestamp)
        case .alarmPump, .alarmSensor:
            return parseAlarm(data: data, timestamp: timestamp)
        case .bgReceived:
            return parseBGReceived(data: data, timestamp: timestamp)
        case .basalProfileStart:
            return parseBasalProfileStart(data: data, timestamp: timestamp)
        default:
            // Return unknown type for records we don't parse yet
            return MinimedHistoryEvent(type: .unknown, timestamp: timestamp, rawData: data)
        }
    }
    
    /// Get timestamp offset for different record types
    private func opcodeTimestampOffset(_ opcode: MinimedHistoryOpcode) -> Int {
        switch opcode {
        case .bolusNormal:
            return isLargerPump ? 8 : 4
        case .tempBasal:
            return 2
        case .suspend, .resume, .rewind, .prime:
            return 2
        case .alarmPump:
            return 4
        case .alarmSensor:
            return 3
        case .bgReceived:
            return 2
        case .basalProfileStart:
            return 2
        default:
            return 2
        }
    }
    
    // MARK: - Timestamp Parsing
    
    /// Parse timestamp from pump event data
    /// Reference: Loop MinimedKit NSDateComponents.swift
    private func parseTimestamp(data: Data, offset: Int) -> Date {
        guard offset + 5 <= data.count else {
            return Date()
        }
        
        let bytes = data.subdata(in: offset..<(offset + 5))
        
        // 5-byte timestamp format
        let second = Int(bytes[0] & 0b00111111)
        let minute = Int(bytes[1] & 0b00111111)
        let hour = Int(bytes[2] & 0b00011111)
        let day = Int(bytes[3] & 0b00011111)
        let month = Int((bytes[0] & 0b11000000) >> 4) + Int((bytes[1] & 0b11000000) >> 6)
        let year = Int(bytes[4] & 0b01111111) + 2000
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.calendar = Calendar(identifier: .gregorian)
        
        return components.date ?? Date()
    }
    
    // MARK: - Record Parsers
    
    /// Parse bolus normal record
    private func parseBolusNormal(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        var details: [String: String] = [:]
        
        if isLargerPump && data.count >= 13 {
            // Larger pump format (523/723+): 13 bytes
            let programmed = Double(Int(data[1]) << 8 | Int(data[2])) / insulinBitPackingScale
            let delivered = Double(Int(data[3]) << 8 | Int(data[4])) / insulinBitPackingScale
            let unabsorbed = Double(Int(data[5]) << 8 | Int(data[6])) / insulinBitPackingScale
            let duration = Int(data[7]) * 30  // Minutes
            
            details["programmed"] = String(format: "%.2f", programmed)
            details["delivered"] = String(format: "%.2f", delivered)
            details["unabsorbed"] = String(format: "%.2f", unabsorbed)
            if duration > 0 {
                details["duration_min"] = "\(duration)"
                details["type"] = "square"
            } else {
                details["type"] = "normal"
            }
        } else if data.count >= 9 {
            // Smaller pump format: 9 bytes
            let programmed = Double(data[1]) / insulinBitPackingScale
            let delivered = Double(data[2]) / insulinBitPackingScale
            let duration = Int(data[3]) * 30
            
            details["programmed"] = String(format: "%.2f", programmed)
            details["delivered"] = String(format: "%.2f", delivered)
            if duration > 0 {
                details["duration_min"] = "\(duration)"
                details["type"] = "square"
            } else {
                details["type"] = "normal"
            }
        }
        
        return MinimedHistoryEvent(type: .bolus, timestamp: timestamp, data: details, rawData: data)
    }
    
    /// Parse temp basal record
    private func parseTempBasal(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        guard data.count >= 8 else {
            return MinimedHistoryEvent(type: .tempBasal, timestamp: timestamp, rawData: data)
        }
        
        var details: [String: String] = [:]
        
        let rateType = (data[7] >> 3) & 1
        if rateType == 0 {
            // Absolute rate in U/hr
            let rate = Double(((Int(data[7]) & 0b111) << 8) + Int(data[1])) / 40.0
            details["rate"] = String(format: "%.3f", rate)
            details["temp"] = "absolute"
        } else {
            // Percentage
            let percent = Int(data[1])
            details["rate"] = "\(percent)"
            details["temp"] = "percent"
        }
        
        return MinimedHistoryEvent(type: .tempBasal, timestamp: timestamp, data: details, rawData: data)
    }
    
    /// Parse prime record
    private func parsePrime(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        guard data.count >= 10 else {
            return MinimedHistoryEvent(type: .prime, timestamp: timestamp, rawData: data)
        }
        
        var details: [String: String] = [:]
        
        let primeType = data[1]
        let amount = Double(Int(data[2]) << 8 | Int(data[3])) / insulinBitPackingScale
        
        details["type"] = primeType == 0 ? "manual" : "fixed"
        details["amount"] = String(format: "%.2f", amount)
        
        return MinimedHistoryEvent(type: .prime, timestamp: timestamp, data: details, rawData: data)
    }
    
    /// Parse alarm record
    private func parseAlarm(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        guard data.count >= 4 else {
            return MinimedHistoryEvent(type: .alarm, timestamp: timestamp, rawData: data)
        }
        
        var details: [String: String] = [:]
        details["alarm_type"] = String(format: "0x%02X", data[1])
        
        return MinimedHistoryEvent(type: .alarm, timestamp: timestamp, data: details, rawData: data)
    }
    
    /// Parse BG received record
    private func parseBGReceived(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        guard data.count >= 10 else {
            return MinimedHistoryEvent(type: .bgReceived, timestamp: timestamp, rawData: data)
        }
        
        var details: [String: String] = [:]
        
        // BG value is in different positions depending on pump model
        let bg = Int(data[1]) << 3 | (Int(data[8]) >> 5)
        details["bg"] = "\(bg)"
        
        return MinimedHistoryEvent(type: .bgReceived, timestamp: timestamp, data: details, rawData: data)
    }
    
    /// Parse basal profile start record
    private func parseBasalProfileStart(data: Data, timestamp: Date) -> MinimedHistoryEvent {
        guard data.count >= 10 else {
            return MinimedHistoryEvent(type: .basalProfileStart, timestamp: timestamp, rawData: data)
        }
        
        var details: [String: String] = [:]
        
        let profileIndex = Int(data[1])
        let rate = Double(Int(data[8]) << 8 | Int(data[7])) / 40.0
        
        details["profile_index"] = "\(profileIndex)"
        details["rate"] = String(format: "%.3f", rate)
        
        return MinimedHistoryEvent(type: .basalProfileStart, timestamp: timestamp, data: details, rawData: data)
    }
}
