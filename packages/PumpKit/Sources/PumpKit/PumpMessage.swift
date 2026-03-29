// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpMessage.swift
// PumpKit
//
// Medtronic pump message framing with address, type, and body.
// Ported from Loop MinimedKit/Messages/ (LoopKit Authors).
// Trace: RL-PROTO-003
//
// Usage:
//   let msg = PumpMessage(packetType: .carelink, address: "A71234",
//                         messageType: .readRemainingInsulin, body: Data())
//   let packet = MinimedPacket(outgoingData: msg.txData)

import Foundation

// MARK: - Packet Type

/// Medtronic RF packet types
public enum PacketType: UInt8, Sendable, CaseIterable {
    case mySentry  = 0xA2  // MySentry CGM link
    case meter     = 0xA5  // Meter link (Contour Next Link)
    case carelink  = 0xA7  // Standard pump commands
    case sensor    = 0xA8  // Sensor glucose
    
    public var displayName: String {
        switch self {
        case .mySentry: return "MySentry"
        case .meter: return "Meter"
        case .carelink: return "Carelink"
        case .sensor: return "Sensor"
        }
    }
}

// MARK: - Message Type

/// Medtronic pump message types (opcodes)
/// Reference: Loop MinimedKit/Messages/MessageType.swift
public enum MessageType: UInt8, Sendable, CaseIterable {
    // Status/Query commands
    case deviceTest              = 0x03
    case pumpAck                 = 0x06
    case findDevice              = 0x09
    case deviceLink              = 0x0A
    case errorResponse           = 0x15
    
    // Configuration commands
    case changeTime              = 0x40
    case setMaxBolus             = 0x41
    case bolus                   = 0x42
    case selectBasalProfile      = 0x4A
    case changeTempBasal         = 0x4C
    case suspendResume           = 0x4D
    case buttonPress             = 0x5B
    case powerOn                 = 0x5D
    case setMaxBasalRate         = 0x6E
    case setBasalProfileSTD      = 0x6F  // CRIT-PROFILE-012: Write standard basal profile
    
    // Read commands
    case readTime                = 0x70
    case getBattery              = 0x72
    case readRemainingInsulin    = 0x73
    case readFirmwareVersion     = 0x74
    case readErrorStatus         = 0x75
    case readRemoteControlIDs    = 0x76
    case getHistoryPage          = 0x80
    case getPumpModel            = 0x8D
    case readProfileSTD512       = 0x92
    case readProfileA512         = 0x93
    case readProfileB512         = 0x94
    case readTempBasal           = 0x98
    case getGlucosePage          = 0x9A
    case readCurrentPageNumber   = 0x9D
    case readSettings            = 0xC0
    case readCurrentGlucosePage  = 0xCD
    case readPumpStatus          = 0xCE
    case readOtherDevicesIDs     = 0xF0
    case readOtherDevicesStatus  = 0xF3
    
    // Write profile commands (CRIT-PROFILE-012)
    case setBasalProfileA        = 0x30  // Write profile A
    case setBasalProfileB        = 0x31  // Write profile B
    
    // Unknown/reserved
    case unknown                 = 0xFF
    
    public var displayName: String {
        switch self {
        case .deviceTest: return "Device Test"
        case .pumpAck: return "ACK"
        case .findDevice: return "Find Device"
        case .deviceLink: return "Device Link"
        case .errorResponse: return "Error"
        case .changeTime: return "Change Time"
        case .setMaxBolus: return "Set Max Bolus"
        case .bolus: return "Bolus"
        case .selectBasalProfile: return "Select Basal Profile"
        case .changeTempBasal: return "Change Temp Basal"
        case .suspendResume: return "Suspend/Resume"
        case .buttonPress: return "Button Press"
        case .powerOn: return "Power On"
        case .setMaxBasalRate: return "Set Max Basal Rate"
        case .setBasalProfileSTD: return "Set Profile STD"
        case .setBasalProfileA: return "Set Profile A"
        case .setBasalProfileB: return "Set Profile B"
        case .readTime: return "Read Time"
        case .getBattery: return "Get Battery"
        case .readRemainingInsulin: return "Read Remaining Insulin"
        case .readFirmwareVersion: return "Read Firmware"
        case .readErrorStatus: return "Read Error Status"
        case .readRemoteControlIDs: return "Read Remote IDs"
        case .getHistoryPage: return "Get History Page"
        case .getPumpModel: return "Get Pump Model"
        case .readProfileSTD512: return "Read Profile STD"
        case .readProfileA512: return "Read Profile A"
        case .readProfileB512: return "Read Profile B"
        case .readTempBasal: return "Read Temp Basal"
        case .getGlucosePage: return "Get Glucose Page"
        case .readCurrentPageNumber: return "Read Current Page"
        case .readSettings: return "Read Settings"
        case .readCurrentGlucosePage: return "Read Current Glucose"
        case .readPumpStatus: return "Read Pump Status"
        case .readOtherDevicesIDs: return "Read Other Devices"
        case .readOtherDevicesStatus: return "Read Devices Status"
        case .unknown: return "Unknown"
        }
    }
    
    /// Expected response length for this message type
    /// Returns nil if response length is variable or unknown
    public var expectedResponseLength: Int? {
        switch self {
        case .getBattery: return 4  // RL-PROTO-004
        case .readRemainingInsulin: return 65  // RL-PROTO-004
        case .readPumpStatus: return 3
        case .getPumpModel: return 4
        case .pumpAck: return 1
        default: return nil  // Variable length
        }
    }
}

// MARK: - Message Body Protocol

/// Protocol for message body content
public protocol MessageBody: Sendable {
    /// Expected body length in bytes
    static var length: Int { get }
    
    /// Body data for transmission
    var txData: Data { get }
}

/// Protocol for decodable response bodies
public protocol DecodableMessageBody: MessageBody {
    init?(rxData: Data)
}

// MARK: - Empty Message Body

/// Empty message body for commands with no parameters
public struct EmptyMessageBody: MessageBody, Sendable {
    public static let length = 0
    public var txData: Data { Data() }
    
    public init() {}
}

// MARK: - Raw Message Body

/// Raw data message body
public struct RawMessageBody: MessageBody, DecodableMessageBody, Sendable {
    public static let length = 0  // Variable
    public let data: Data
    
    public var txData: Data { data }
    
    public init(data: Data) {
        self.data = data
    }
    
    public init?(rxData: Data) {
        self.data = rxData
    }
}

// MARK: - Generic Message Body (MDT-HIST-031)

/// Generic message body for arbitrary data payloads
/// Used when no specific message body type exists for a command
public struct GenericMessageBody: MessageBody, Sendable {
    public static let length = 0  // Variable length
    public let data: Data
    
    public var txData: Data { data }
    
    public init(data: Data) {
        self.data = data
    }
}

// MARK: - CRC16 for Medtronic History Pages (MDT-HIST-031)

/// CRC16 computation for Medtronic pump history pages
/// Uses CRC-CCITT polynomial with initial value 0xFFFF
/// Matches MinimedKit/Messages/Models/CRC16.swift exactly
public enum CRC16 {
    /// CRC16 lookup table - exact copy from MinimedKit
    private static let table: [UInt16] = [
        0, 4129, 8258, 12387, 16516, 20645, 24774, 28903, 33032, 37161, 41290, 45419, 49548, 53677, 57806, 61935,
        4657, 528, 12915, 8786, 21173, 17044, 29431, 25302, 37689, 33560, 45947, 41818, 54205, 50076, 62463, 58334,
        9314, 13379, 1056, 5121, 25830, 29895, 17572, 21637, 42346, 46411, 34088, 38153, 58862, 62927, 50604, 54669,
        13907, 9842, 5649, 1584, 30423, 26358, 22165, 18100, 46939, 42874, 38681, 34616, 63455, 59390, 55197, 51132,
        18628, 22757, 26758, 30887, 2112, 6241, 10242, 14371, 51660, 55789, 59790, 63919, 35144, 39273, 43274, 47403,
        23285, 19156, 31415, 27286, 6769, 2640, 14899, 10770, 56317, 52188, 64447, 60318, 39801, 35672, 47931, 43802,
        27814, 31879, 19684, 23749, 11298, 15363, 3168, 7233, 60846, 64911, 52716, 56781, 44330, 48395, 36200, 40265,
        32407, 28342, 24277, 20212, 15891, 11826, 7761, 3696, 65439, 61374, 57309, 53244, 48923, 44858, 40793, 36728,
        37256, 33193, 45514, 41451, 53516, 49453, 61774, 57711, 4224, 161, 12482, 8419, 20484, 16421, 28742, 24679,
        33721, 37784, 41979, 46042, 49981, 54044, 58239, 62302, 689, 4752, 8947, 13010, 16949, 21012, 25207, 29270,
        46570, 42443, 38312, 34185, 62830, 58703, 54572, 50445, 13538, 9411, 5280, 1153, 29798, 25671, 21540, 17413,
        42971, 47098, 34713, 38840, 59231, 63358, 50973, 55100, 9939, 14066, 1681, 5808, 26199, 30326, 17941, 22068,
        55628, 51565, 63758, 59695, 39368, 35305, 47498, 43435, 22596, 18533, 30726, 26663, 6336, 2273, 14466, 10403,
        52093, 56156, 60223, 64286, 35833, 39896, 43963, 48026, 19061, 23124, 27191, 31254, 2801, 6864, 10931, 14994,
        64814, 60687, 56684, 52557, 48554, 44427, 40424, 36297, 31782, 27655, 23652, 19525, 15522, 11395, 7392, 3265,
        61215, 65342, 53085, 57212, 44955, 49082, 36825, 40952, 28183, 32310, 20053, 24180, 11923, 16050, 3793, 7920
    ]
    
    /// Compute CRC16 for data using Medtronic polynomial
    /// - Parameter data: Input data bytes
    /// - Returns: CRC16 value
    public static func compute(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            let index = Int(((crc >> 8) ^ UInt16(byte)) & 0xFF)
            crc = ((crc << 8) ^ table[index]) & 0xFFFF
        }
        return crc
    }
    
    /// Verify CRC16 appended to data (big-endian)
    /// - Parameter data: Data with 2-byte CRC appended
    /// - Returns: True if CRC matches
    public static func verify(_ data: Data) -> Bool {
        guard data.count > 2 else { return false }
        let dataBytes = data.subdata(in: 0..<data.count - 2)
        let hiByte = data[data.count - 2]
        let loByte = data[data.count - 1]
        let expected = (UInt16(hiByte) << 8) | UInt16(loByte)
        return compute(dataBytes) == expected
    }
}

// MARK: - Carelink Short Message Body (SWIFT-RL-002)

/// Short message body with single 0x00 byte for read commands.
/// Matches Loop's CarelinkShortMessageBody in MinimedKit/Messages/CarelinkMessageBody.swift:44
/// Required for getPumpModel (0x8D) and other read commands.
public struct CarelinkShortMessageBody: MessageBody, Sendable {
    public static let length = 1
    public var txData: Data { Data([0x00]) }
    
    public init() {}
}

// MARK: - PowerOn Message Body (SWIFT-RL-005)

/// PowerOn message body for wakeup command (0x5D).
/// Format: [numArgs=02][on=01][durationMinutes] + 62 zero-byte padding = 65 bytes total
/// Matches Loop's PowerOnCarelinkMessageBody in MinimedKit/Messages/PowerOnCarelinkMessageBody.swift
public struct PowerOnCarelinkMessageBody: MessageBody, Sendable {
    public static let length = 65
    public let durationMinutes: UInt8
    
    public var txData: Data {
        // Format: 02 01 <minutes> + 62 zeros
        var data = Data([0x02, 0x01, durationMinutes])
        data.append(Data(repeating: 0, count: 62))
        return data
    }
    
    /// Create PowerOn body with duration in minutes
    public init(durationMinutes: UInt8) {
        self.durationMinutes = durationMinutes
    }
    
    /// Create PowerOn body from duration TimeInterval (rounded up to minutes)
    public init(duration: TimeInterval) {
        self.durationMinutes = UInt8(min(255, max(1, Int(ceil(duration / 60.0)))))
    }
}

// MARK: - Pump Message

/// Medtronic pump message with packet type, address, message type, and body
public struct PumpMessage: Sendable, CustomStringConvertible {
    public let packetType: PacketType
    public let address: Data  // 3 bytes
    public let messageType: MessageType
    public let body: Data
    
    // MARK: - Init for Outgoing Messages
    
    /// Create message with hex string address
    public init(
        packetType: PacketType = .carelink,
        address: String,
        messageType: MessageType,
        body: Data = Data()
    ) {
        self.packetType = packetType
        self.address = Self.parseAddress(address)
        self.messageType = messageType
        self.body = body
    }
    
    /// Create message with raw address bytes
    public init(
        packetType: PacketType = .carelink,
        addressBytes: Data,
        messageType: MessageType,
        body: Data = Data()
    ) {
        self.packetType = packetType
        self.address = addressBytes.prefix(3)
        self.messageType = messageType
        self.body = body
    }
    
    /// Convenience initializer with MessageBody protocol
    /// This matches Loop's pattern in PumpMessage+PumpOpsSession.swift
    public init(
        packetType: PacketType = .carelink,
        address: String,
        messageType: MessageType,
        messageBody: MessageBody
    ) {
        self.init(packetType: packetType, address: address, messageType: messageType, body: messageBody.txData)
    }
    
    /// Convenience initializer for read commands with default 0x00 body byte
    /// Matches Loop's default of CarelinkShortMessageBody() for getPumpModel etc.
    public static func readCommand(
        address: String,
        messageType: MessageType
    ) -> PumpMessage {
        PumpMessage(address: address, messageType: messageType, messageBody: CarelinkShortMessageBody())
    }
    
    /// Convenience initializer for PowerOn wakeup command
    public static func powerOn(
        address: String,
        durationMinutes: UInt8 = 1
    ) -> PumpMessage {
        PumpMessage(address: address, messageType: .powerOn, messageBody: PowerOnCarelinkMessageBody(durationMinutes: durationMinutes))
    }
    
    // MARK: - Init for Incoming Messages
    
    /// Parse message from received data
    /// Format: [packetType 1B][address 3B][messageType 1B][body...]
    public init?(rxData: Data) {
        guard rxData.count >= 5 else { return nil }
        
        guard let pType = PacketType(rawValue: rxData[0]),
              pType != .meter  // Meter packets have different format
        else { return nil }
        
        guard let mType = MessageType(rawValue: rxData[4]) else {
            // Unknown message type - still parse with .unknown
            self.packetType = pType
            self.address = rxData.subdata(in: 1..<4)
            self.messageType = .unknown
            self.body = rxData.count > 5 ? rxData.subdata(in: 5..<rxData.count) : Data()
            return
        }
        
        self.packetType = pType
        self.address = rxData.subdata(in: 1..<4)
        self.messageType = mType
        self.body = rxData.count > 5 ? rxData.subdata(in: 5..<rxData.count) : Data()
    }
    
    // MARK: - Transmission Data
    
    /// Raw bytes for transmission (before 4b6b encoding)
    public var txData: Data {
        var buffer = Data()
        buffer.append(packetType.rawValue)
        buffer.append(contentsOf: address.prefix(3))
        buffer.append(messageType.rawValue)
        buffer.append(body)
        return buffer
    }
    
    // MARK: - Helpers
    
    /// Parse 6-character hex string to 3 bytes
    private static func parseAddress(_ hex: String) -> Data {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[idx..<nextIdx], radix: 16) {
                data.append(byte)
            }
            idx = nextIdx
        }
        return data.prefix(3)
    }
    
    /// Address as hex string
    public var addressHex: String {
        address.map { String(format: "%02X", $0) }.joined()
    }
    
    public var description: String {
        "PumpMessage(\(packetType.displayName), \(messageType.displayName), addr=\(addressHex), body=\(body.count)B)"
    }
}

// MARK: - Equatable

extension PumpMessage: Equatable {
    public static func == (lhs: PumpMessage, rhs: PumpMessage) -> Bool {
        lhs.packetType == rhs.packetType &&
        lhs.address == rhs.address &&
        lhs.messageType == rhs.messageType &&
        lhs.body == rhs.body
    }
}
