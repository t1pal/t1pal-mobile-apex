// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosBLEManager.swift
// PumpKit
//
// BLE connection manager for Omnipod Eros via RileyLink/OrangeLink bridge.
// Wraps RileyLinkManager for RF communication at 433.91 MHz.
// Trace: EROS-IMPL-002, PUMP-OMNI-003, PRD-005
//
// Protocol: Eros uses 433.91 MHz RF via RileyLink bridge
// Message format: ErosPacket (CRC8) containing ErosMessage (CRC16)
//
// Usage:
//   let manager = ErosBLEManager()
//   try await manager.connect(to: rileyLinkDevice)
//   let status = try await manager.getPodStatus()

import Foundation
import BLEKit

// MARK: - Eros BLE Error

/// Errors specific to Eros pod communication via RileyLink
public enum ErosBLEError: Error, Sendable, Equatable {
    case notConnected
    case rileyLinkNotReady
    case podNotPaired
    case rfCommunicationError(String)
    case packetError(ErosPacketError)
    case messageError(String)
    case noPodResponse
    case podFaulted(code: UInt8)
    case invalidResponse(String)
    case sessionInvalid
    case timeout
    case cancelled
}

// MARK: - Eros Connection State

/// Connection state for Eros pod via RileyLink bridge
public enum ErosConnectionState: String, Sendable, Codable {
    case disconnected
    case connectingToBridge  // Connecting to RileyLink
    case bridgeConnected     // RileyLink connected, tuning RF
    case tuning              // Finding optimal RF frequency
    case searchingForPod     // Looking for pod beacon
    case paired              // Pod communication established
    case ready               // Ready for commands
    case error
    
    public var isConnected: Bool {
        switch self {
        case .paired, .ready:
            return true
        default:
            return false
        }
    }
    
    public var canSendCommands: Bool {
        self == .ready
    }
    
    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connectingToBridge: return "Connecting to Bridge..."
        case .bridgeConnected: return "Bridge Connected"
        case .tuning: return "Tuning RF..."
        case .searchingForPod: return "Searching for Pod..."
        case .paired: return "Paired"
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension ErosConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .connectingToBridge, .bridgeConnected, .tuning, .searchingForPod: return .connecting
        case .paired, .ready: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Eros Session

/// Eros pod communication session state
public struct ErosSession: Sendable {
    public let podAddress: UInt32
    public var packetSequence: Int
    public var messageSequence: Int
    public var nonceValue: UInt32         // PUMP-PG-001: Nonce for command security
    public let establishedAt: Date
    public var lastActivity: Date
    
    /// Whether session is still valid (not timed out)
    public var isValid: Bool {
        Date().timeIntervalSince(lastActivity) < 300  // 5 minute timeout
    }
    
    /// Current nonce value for commands
    public var currentNonce: UInt32 {
        nonceValue
    }
    
    public init(podAddress: UInt32) {
        self.podAddress = podAddress
        self.packetSequence = 0
        self.messageSequence = 0
        self.nonceValue = UInt32.random(in: 0...UInt32.max)  // Random initial nonce
        self.establishedAt = Date()
        self.lastActivity = Date()
    }
    
    public mutating func incrementPacketSequence() {
        packetSequence = (packetSequence + 1) & 0x1F
        lastActivity = Date()
    }
    
    public mutating func incrementMessageSequence() {
        messageSequence = (messageSequence + 1) & 0x0F
        lastActivity = Date()
    }
    
    /// Increment nonce after successful command
    public mutating func incrementNonce() {
        nonceValue = nonceValue &+ 1
        lastActivity = Date()
    }
}

// MARK: - Eros Pod Info

/// Information about a paired Eros pod
public struct ErosPodInfo: Sendable, Equatable {
    public let address: UInt32
    public let lot: UInt32
    public let tid: UInt32
    public let pmVersion: String
    public let piVersion: String
    public let reservoirLevel: Double?  // Units remaining (nil if > 50U)
    public let podProgressStatus: UInt8
    public let deliveryStatus: UInt8    // PUMP-PG-001: Current delivery state
    public let faultCode: UInt8?
    public let minutesSinceActivation: UInt16
    
    public var addressHex: String {
        String(format: "0x%08X", address)
    }
    
    public var isActive: Bool {
        podProgressStatus >= 8 && podProgressStatus <= 10
    }
    
    public var isFaulted: Bool {
        faultCode != nil && faultCode != 0
    }
    
    /// True if pod is currently delivering a bolus
    public var isBolusing: Bool {
        // Delivery status bit 2 indicates bolus in progress
        // But not if suspended (0x0F)
        !isSuspended && (deliveryStatus & 0x04) != 0
    }
    
    /// True if temp basal is active
    public var isTempBasalActive: Bool {
        // Delivery status bit 1 indicates temp basal
        // But not if suspended
        !isSuspended && (deliveryStatus & 0x02) != 0
    }
    
    /// True if basal is suspended
    public var isSuspended: Bool {
        // Delivery status 0x0F indicates suspended
        deliveryStatus == 0x0F
    }
    
    /// Convenience initializer with default delivery status
    public init(
        address: UInt32,
        lot: UInt32,
        tid: UInt32,
        pmVersion: String,
        piVersion: String,
        reservoirLevel: Double?,
        podProgressStatus: UInt8,
        deliveryStatus: UInt8 = 0x01,  // Default: normal basal delivery
        faultCode: UInt8?,
        minutesSinceActivation: UInt16
    ) {
        self.address = address
        self.lot = lot
        self.tid = tid
        self.pmVersion = pmVersion
        self.piVersion = piVersion
        self.reservoirLevel = reservoirLevel
        self.podProgressStatus = podProgressStatus
        self.deliveryStatus = deliveryStatus
        self.faultCode = faultCode
        self.minutesSinceActivation = minutesSinceActivation
    }
}

// MARK: - Eros BLE Constants

/// Constants for Eros RF communication
public enum ErosBLEConstants {
    /// RF frequency for Eros pods (MHz)
    public static let rfFrequency: Double = 433.91
    
    /// Frequency bands to scan for tuning
    public static let frequencyBands: [Double] = [
        433.91, 433.92, 433.93, 433.89, 433.88
    ]
    
    /// RF preamble bytes
    public static let preamble: [UInt8] = [0xAA, 0xAA, 0xAA, 0xAA]
    
    /// Timeout for pod response (ms)
    public static let podResponseTimeoutMs: UInt32 = 2000
    
    /// Maximum retries for RF communication
    public static let maxRetries: Int = 3
    
    /// Default PDM address (for unpaired communication)
    public static let defaultPDMAddress: UInt32 = 0xFFFFFFFF
}

// MARK: - Setup Pod Command (EROS-IMPL-007)

/// SetupPodCommand encoder for Eros pod pairing
/// Format: 03 13 AAAAAAAA 14 TT MM DD YY HH MM LLLLLLLL TTTTTTTT
/// - Bytes 0-1: Block type (0x03) and length (19)
/// - Bytes 2-5: Pod address (big-endian)
/// - Byte 6: Unknown (always 0x14)
/// - Byte 7: Packet timeout limit (typically 4)
/// - Bytes 8-12: Date/time (month, day, year-2000, hour, minute)
/// - Bytes 13-16: Lot number (big-endian)
/// - Bytes 17-20: TID/serial number (big-endian)
///
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/SetupPodCommand.swift
public struct ErosSetupPodCommand: Sendable, Equatable {
    /// Message block type for SetupPod
    public static let blockType: UInt8 = 0x03
    
    /// Pod address to assign
    public let address: UInt32
    
    /// Pod lot number (from label)
    public let lot: UInt32
    
    /// Pod TID/serial number (from label)
    public let tid: UInt32
    
    /// Activation date/time components
    public let month: UInt8
    public let day: UInt8
    public let year: UInt8  // Year - 2000
    public let hour: UInt8
    public let minute: UInt8
    
    /// Packet timeout limit (default: 4)
    public let packetTimeoutLimit: UInt8
    
    /// Create SetupPodCommand with current time
    public init(
        address: UInt32,
        lot: UInt32,
        tid: UInt32,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        packetTimeoutLimit: UInt8 = 4
    ) {
        self.address = address
        self.lot = lot
        self.tid = tid
        self.packetTimeoutLimit = packetTimeoutLimit
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.month, .day, .year, .hour, .minute], from: date)
        
        self.month = UInt8(components.month ?? 1)
        self.day = UInt8(components.day ?? 1)
        self.year = UInt8((components.year ?? 2000) - 2000)
        self.hour = UInt8(components.hour ?? 0)
        self.minute = UInt8(components.minute ?? 0)
    }
    
    /// Create SetupPodCommand with explicit date components
    public init(
        address: UInt32,
        lot: UInt32,
        tid: UInt32,
        month: UInt8,
        day: UInt8,
        year: UInt8,
        hour: UInt8,
        minute: UInt8,
        packetTimeoutLimit: UInt8 = 4
    ) {
        self.address = address
        self.lot = lot
        self.tid = tid
        self.month = month
        self.day = day
        self.year = year
        self.hour = hour
        self.minute = minute
        self.packetTimeoutLimit = packetTimeoutLimit
    }
    
    /// Encode command to 21-byte data
    /// Format: 03 13 AAAAAAAA 14 TT MM DD YY HH MM LLLLLLLL TTTTTTTT
    public var data: Data {
        var data = Data()
        
        // Block type and length
        data.append(Self.blockType)
        data.append(19) // Length = 19 bytes
        
        // Pod address (big-endian)
        data.append(UInt8((address >> 24) & 0xFF))
        data.append(UInt8((address >> 16) & 0xFF))
        data.append(UInt8((address >> 8) & 0xFF))
        data.append(UInt8(address & 0xFF))
        
        // Unknown byte (always 0x14)
        data.append(0x14)
        
        // Packet timeout limit
        data.append(packetTimeoutLimit)
        
        // Date/time: month, day, year, hour, minute
        data.append(month)
        data.append(day)
        data.append(year)
        data.append(hour)
        data.append(minute)
        
        // Lot number (big-endian)
        data.append(UInt8((lot >> 24) & 0xFF))
        data.append(UInt8((lot >> 16) & 0xFF))
        data.append(UInt8((lot >> 8) & 0xFF))
        data.append(UInt8(lot & 0xFF))
        
        // TID/serial (big-endian)
        data.append(UInt8((tid >> 24) & 0xFF))
        data.append(UInt8((tid >> 16) & 0xFF))
        data.append(UInt8((tid >> 8) & 0xFF))
        data.append(UInt8(tid & 0xFF))
        
        return data
    }
    
    /// Decode SetupPodCommand from data
    public init(encodedData: Data) throws {
        guard encodedData.count >= 21 else {
            throw ErosBLEError.invalidResponse("SetupPodCommand requires 21 bytes, got \(encodedData.count)")
        }
        
        guard encodedData[0] == Self.blockType else {
            throw ErosBLEError.invalidResponse("Invalid block type: expected 0x03, got \(encodedData[0])")
        }
        
        // Decode address (bytes 2-5)
        self.address = UInt32(encodedData[2]) << 24 |
                       UInt32(encodedData[3]) << 16 |
                       UInt32(encodedData[4]) << 8 |
                       UInt32(encodedData[5])
        
        // Packet timeout (byte 7)
        self.packetTimeoutLimit = encodedData[7]
        
        // Date/time (bytes 8-12)
        self.month = encodedData[8]
        self.day = encodedData[9]
        self.year = encodedData[10]
        self.hour = encodedData[11]
        self.minute = encodedData[12]
        
        // Lot number (bytes 13-16)
        self.lot = UInt32(encodedData[13]) << 24 |
                   UInt32(encodedData[14]) << 16 |
                   UInt32(encodedData[15]) << 8 |
                   UInt32(encodedData[16])
        
        // TID (bytes 17-20)
        self.tid = UInt32(encodedData[17]) << 24 |
                   UInt32(encodedData[18]) << 16 |
                   UInt32(encodedData[19]) << 8 |
                   UInt32(encodedData[20])
    }
    
    /// Activation date from components
    public var activationDate: Date? {
        var components = DateComponents()
        components.month = Int(month)
        components.day = Int(day)
        components.year = Int(year) + 2000
        components.hour = Int(hour)
        components.minute = Int(minute)
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

extension ErosSetupPodCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "SetupPodCommand(address: 0x\(String(address, radix: 16, uppercase: true)), lot: \(lot), tid: \(tid), date: \(month)/\(day)/\(Int(year) + 2000) \(hour):\(String(format: "%02d", minute)))"
    }
}

// MARK: - Assign Address Command (EROS-IMPL-009)

/// AssignAddressCommand encoder for Eros pod pairing
/// Format: 07 04 AAAAAAAA
/// - Bytes 0-1: Block type (0x07) and length (4)
/// - Bytes 2-5: Pod address to assign (big-endian)
///
/// This is the first command in the pairing sequence. The pod responds with
/// a VersionResponse (0x15, 23 bytes) containing firmware versions and lot/tid.
///
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/AssignAddressCommand.swift
public struct ErosAssignAddressCommand: Sendable, Equatable {
    /// Message block type for AssignAddress
    public static let blockType: UInt8 = 0x07
    
    /// Pod address to assign
    public let address: UInt32
    
    /// Create AssignAddressCommand
    public init(address: UInt32) {
        self.address = address
    }
    
    /// Encode command to data (6 bytes)
    public var data: Data {
        var data = Data()
        
        // Block type and length
        data.append(Self.blockType)
        data.append(0x04)  // Length: 4 bytes of address data
        
        // Address (big-endian)
        data.append(UInt8((address >> 24) & 0xFF))
        data.append(UInt8((address >> 16) & 0xFF))
        data.append(UInt8((address >> 8) & 0xFF))
        data.append(UInt8(address & 0xFF))
        
        return data
    }
    
    /// Decode AssignAddressCommand from data
    public init(encodedData: Data) throws {
        guard encodedData.count >= 6 else {
            throw ErosBLEError.invalidResponse("AssignAddressCommand requires 6 bytes, got \(encodedData.count)")
        }
        
        guard encodedData[0] == Self.blockType else {
            throw ErosBLEError.invalidResponse("Invalid block type: expected 0x07, got \(encodedData[0])")
        }
        
        // Decode address (bytes 2-5)
        self.address = UInt32(encodedData[2]) << 24 |
                       UInt32(encodedData[3]) << 16 |
                       UInt32(encodedData[4]) << 8 |
                       UInt32(encodedData[5])
    }
}

extension ErosAssignAddressCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "AssignAddressCommand(address: 0x\(String(address, radix: 16, uppercase: true)))"
    }
}

// MARK: - Version Response (EROS-IMPL-008)

/// Firmware version triplet (major.minor.patch)
public struct ErosFirmwareVersion: Sendable, Equatable, CustomStringConvertible {
    public let major: UInt8
    public let minor: UInt8
    public let patch: UInt8
    
    public init(major: UInt8, minor: UInt8, patch: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    public init(encodedData: Data) {
        self.major = encodedData[0]
        self.minor = encodedData[1]
        self.patch = encodedData[2]
    }
    
    public var description: String {
        return "\(major).\(minor).\(patch)"
    }
}

/// Pod progress status during pairing/activation
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/PodProgressStatus.swift
public enum ErosPodProgressStatus: UInt8, Sendable, CaseIterable {
    case initialized = 0x00
    case memoryInitialized = 0x01
    case reminderInitialized = 0x02
    case pairingCompleted = 0x03
    case priming = 0x04
    case primingCompleted = 0x05
    case basalInitialized = 0x06
    case insertingCannula = 0x07
    case aboveFiftyUnits = 0x08
    case fiftyOrLessUnits = 0x09
    case oneNotDelivered = 0x0A
    case twoNotDelivered = 0x0B
    case threeNotDelivered = 0x0C
    case errorEventLogged = 0x0D
    case delayedPrime = 0x0E
    case inactive = 0x0F
    
    public var displayName: String {
        switch self {
        case .initialized: return "Initialized"
        case .memoryInitialized: return "Memory Initialized"
        case .reminderInitialized: return "Reminder Initialized"
        case .pairingCompleted: return "Pairing Completed"
        case .priming: return "Priming"
        case .primingCompleted: return "Priming Completed"
        case .basalInitialized: return "Basal Initialized"
        case .insertingCannula: return "Inserting Cannula"
        case .aboveFiftyUnits: return "Above 50 Units"
        case .fiftyOrLessUnits: return "50 or Less Units"
        case .oneNotDelivered: return "1 Pulse Not Delivered"
        case .twoNotDelivered: return "2 Pulses Not Delivered"
        case .threeNotDelivered: return "3 Pulses Not Delivered"
        case .errorEventLogged: return "Error Event Logged"
        case .delayedPrime: return "Delayed Prime"
        case .inactive: return "Inactive"
        }
    }
    
    public var isActive: Bool {
        switch self {
        case .aboveFiftyUnits, .fiftyOrLessUnits, .oneNotDelivered, .twoNotDelivered, .threeNotDelivered:
            return true
        default:
            return false
        }
    }
}

/// VersionResponse parser for Eros pod responses
/// Supports both AssignAddress (0x15) and SetupPod (0x1B) response formats
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/VersionResponse.swift
public struct ErosVersionResponse: Sendable, Equatable {
    /// Response block type
    public static let blockType: UInt8 = 0x01
    
    /// AssignAddress response length (0x15 = 21 bytes)
    public static let assignAddressLength: UInt8 = 0x15
    
    /// SetupPod response length (0x1B = 27 bytes)
    public static let setupPodLength: UInt8 = 0x1B
    
    // Common fields
    public let firmwareVersion: ErosFirmwareVersion    // PM version (Eros: 2.x.y)
    public let iFirmwareVersion: ErosFirmwareVersion   // PI version
    public let productId: UInt8                        // 02 = Eros, 04 = Dash
    public let lot: UInt32
    public let tid: UInt32
    public let address: UInt32
    public let podProgressStatus: ErosPodProgressStatus
    
    // AssignAddress only (0x15)
    public let gain: UInt8?    // 2-bit value
    public let rssi: UInt8?    // 6-bit value
    
    // SetupPod only (0x1B)
    public let pulseSize: Double?              // VVVV / 100,000 (0.05U)
    public let secondsPerBolusPulse: Double?   // BR / 8 (2 seconds)
    public let secondsPerPrimePulse: Double?   // PR / 8 (1 second)
    public let primeUnits: Double?             // PP / 20 (2.6U)
    public let cannulaInsertionUnits: Double?  // CP / 20 (0.5U)
    public let serviceDuration: TimeInterval?  // PL hours (80 hours)
    
    /// Raw response data
    public let data: Data
    
    /// True if this is an AssignAddress response (0x15)
    public var isAssignAddressResponse: Bool {
        data.count == Int(Self.assignAddressLength) + 2
    }
    
    /// True if this is a SetupPod response (0x1B)
    public var isSetupPodResponse: Bool {
        data.count == Int(Self.setupPodLength) + 2
    }
    
    /// Decode VersionResponse from raw data
    public init(encodedData: Data) throws {
        guard encodedData.count >= 2 else {
            throw ErosBLEError.invalidResponse("VersionResponse too short: \(encodedData.count) bytes")
        }
        
        guard encodedData[0] == Self.blockType else {
            throw ErosBLEError.invalidResponse("Invalid block type: expected 0x01, got \(encodedData[0])")
        }
        
        let responseLength = encodedData[1]
        
        switch responseLength {
        case Self.assignAddressLength:
            // 0x15 response for AssignAddress command
            // 01 15 MXMYMZ IXIYIZ ID 0J LLLLLLLL TTTTTTTT GS IIIIIIII
            guard encodedData.count >= 23 else {
                throw ErosBLEError.invalidResponse("AssignAddress response needs 23 bytes, got \(encodedData.count)")
            }
            
            self.data = Data(encodedData.prefix(23))
            self.firmwareVersion = ErosFirmwareVersion(encodedData: encodedData.subdata(in: 2..<5))
            self.iFirmwareVersion = ErosFirmwareVersion(encodedData: encodedData.subdata(in: 5..<8))
            self.productId = encodedData[8]
            
            guard let progress = ErosPodProgressStatus(rawValue: encodedData[9]) else {
                throw ErosBLEError.invalidResponse("Invalid pod progress status: \(encodedData[9])")
            }
            self.podProgressStatus = progress
            
            self.lot = UInt32(encodedData[10]) << 24 |
                       UInt32(encodedData[11]) << 16 |
                       UInt32(encodedData[12]) << 8 |
                       UInt32(encodedData[13])
            
            self.tid = UInt32(encodedData[14]) << 24 |
                       UInt32(encodedData[15]) << 16 |
                       UInt32(encodedData[16]) << 8 |
                       UInt32(encodedData[17])
            
            self.gain = (encodedData[18] & 0xC0) >> 6
            self.rssi = encodedData[18] & 0x3F
            
            self.address = UInt32(encodedData[19]) << 24 |
                           UInt32(encodedData[20]) << 16 |
                           UInt32(encodedData[21]) << 8 |
                           UInt32(encodedData[22])
            
            // SetupPod-only fields are nil
            self.pulseSize = nil
            self.secondsPerBolusPulse = nil
            self.secondsPerPrimePulse = nil
            self.primeUnits = nil
            self.cannulaInsertionUnits = nil
            self.serviceDuration = nil
            
        case Self.setupPodLength:
            // 0x1B response for SetupPod command
            // 01 1B VVVV BR PR PP CP PL MXMYMZ IXIYIZ ID 0J LLLLLLLL TTTTTTTT IIIIIIII
            guard encodedData.count >= 29 else {
                throw ErosBLEError.invalidResponse("SetupPod response needs 29 bytes, got \(encodedData.count)")
            }
            
            self.data = Data(encodedData.prefix(29))
            
            // Pulse/timing parameters
            let pulseVolumeRaw = UInt16(encodedData[2]) << 8 | UInt16(encodedData[3])
            self.pulseSize = Double(pulseVolumeRaw) / 100_000
            self.secondsPerBolusPulse = Double(encodedData[4]) / 8
            self.secondsPerPrimePulse = Double(encodedData[5]) / 8
            self.primeUnits = Double(encodedData[6]) / 20.0  // pulsesPerUnit = 20
            self.cannulaInsertionUnits = Double(encodedData[7]) / 20.0
            self.serviceDuration = TimeInterval(encodedData[8]) * 3600  // hours to seconds
            
            self.firmwareVersion = ErosFirmwareVersion(encodedData: encodedData.subdata(in: 9..<12))
            self.iFirmwareVersion = ErosFirmwareVersion(encodedData: encodedData.subdata(in: 12..<15))
            self.productId = encodedData[15]
            
            guard let progress = ErosPodProgressStatus(rawValue: encodedData[16]) else {
                throw ErosBLEError.invalidResponse("Invalid pod progress status: \(encodedData[16])")
            }
            self.podProgressStatus = progress
            
            self.lot = UInt32(encodedData[17]) << 24 |
                       UInt32(encodedData[18]) << 16 |
                       UInt32(encodedData[19]) << 8 |
                       UInt32(encodedData[20])
            
            self.tid = UInt32(encodedData[21]) << 24 |
                       UInt32(encodedData[22]) << 16 |
                       UInt32(encodedData[23]) << 8 |
                       UInt32(encodedData[24])
            
            self.address = UInt32(encodedData[25]) << 24 |
                           UInt32(encodedData[26]) << 16 |
                           UInt32(encodedData[27]) << 8 |
                           UInt32(encodedData[28])
            
            // AssignAddress-only fields are nil
            self.gain = nil
            self.rssi = nil
            
        default:
            throw ErosBLEError.invalidResponse("Invalid response length: \(responseLength)")
        }
    }
}

extension ErosVersionResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        if isSetupPodResponse {
            return "VersionResponse(SetupPod, lot: \(lot), tid: \(tid), address: 0x\(String(address, radix: 16, uppercase: true)), fw: \(firmwareVersion), progress: \(podProgressStatus.displayName), pulseSize: \(pulseSize ?? 0)U)"
        } else {
            return "VersionResponse(AssignAddress, lot: \(lot), tid: \(tid), address: 0x\(String(address, radix: 16, uppercase: true)), fw: \(firmwareVersion), progress: \(podProgressStatus.displayName), rssi: \(rssi ?? 0))"
        }
    }
}

// MARK: - Eros Pod Constants (PUMP-PG-001)

/// Constants for Eros pod insulin delivery
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/Pod.swift
public enum ErosPodConstants {
    /// Volume of U100 insulin per pulse (0.05 U)
    public static let pulseSize: Double = 0.05
    
    /// Pulses per unit of insulin
    public static let pulsesPerUnit: Double = 1.0 / pulseSize
    
    /// Seconds between pulses for bolus delivery
    public static let secondsPerBolusPulse: Double = 2.0
    
    /// Bolus delivery rate in U/second
    public static let bolusDeliveryRate: Double = pulseSize / secondsPerBolusPulse
    
    /// Maximum immediate bolus (30 U)
    public static let maxBolus: Double = 30.0
    
    /// Maximum reservoir reading
    public static let maximumReservoirReading: Double = 50.0
    
    /// Maximum time between pulses (5 hours) - used for zero and low temp basal rates
    public static let maxTimeBetweenPulses: TimeInterval = 5.0 * 3600.0
    
    /// Maximum temp basal rate (30 U/hr)
    public static let maxTempBasalRate: Double = 30.0
    
    /// Maximum temp basal duration (12 hours = 720 minutes)
    public static let maxTempBasalDuration: TimeInterval = 12.0 * 3600.0
    
    /// Minimum temp basal duration (30 minutes)
    public static let minTempBasalDuration: TimeInterval = 30.0 * 60.0
}

// MARK: - Bolus Delivery Table (PUMP-PG-001)

/// Insulin table entry for bolus/basal delivery
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/InsulinTableEntry.swift
public struct ErosInsulinTableEntry: Sendable, Equatable {
    /// Number of 30-minute segments
    public let segments: Int
    
    /// Number of pulses
    public let pulses: Int
    
    /// Whether to use alternating pulse counts
    public let alternateSegmentPulse: Bool
    
    public init(segments: Int, pulses: Int, alternateSegmentPulse: Bool = false) {
        self.segments = segments
        self.pulses = pulses
        self.alternateSegmentPulse = alternateSegmentPulse
    }
    
    /// Encode entry to data (2 bytes)
    /// Format: $ABBB where A=segments-1, BBB=pulses (alternateSegmentPulse sets high bit of A)
    public var data: Data {
        let segmentByte = UInt8((segments - 1) | (alternateSegmentPulse ? 0x80 : 0x00))
        return Data([
            segmentByte,
            UInt8(pulses >> 8),
            UInt8(pulses & 0xFF)
        ]).prefix(2)  // Only 2 bytes for simple bolus
    }
    
    /// Checksum for validation
    public func checksum() -> UInt16 {
        return UInt16(segments) + UInt16(pulses)
    }
}

/// Bolus delivery table for Eros pods
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/BolusDeliveryTable.swift
public struct ErosBolusDeliveryTable: Sendable, Equatable {
    public let entries: [ErosInsulinTableEntry]
    
    public init(entries: [ErosInsulinTableEntry]) {
        self.entries = entries
    }
    
    /// Create simple immediate bolus table
    public init(units: Double) {
        let pulses = Int(round(units / ErosPodConstants.pulseSize))
        let entry = ErosInsulinTableEntry(segments: 1, pulses: pulses, alternateSegmentPulse: false)
        self.entries = [entry]
    }
    
    /// Number of segments in this table
    public func numSegments() -> Int {
        return entries.reduce(0) { $0 + $1.segments }
    }
}

// MARK: - SetInsulinSchedule Command (PUMP-PG-001)

/// SetInsulinScheduleCommand encoder for bolus/temp basal delivery
/// Format: 1a LL NNNNNNNN HH CCCC PPPP [TT PPPP]...
/// - Block type: 0x1A
/// - Length: variable
/// - Nonce: 4 bytes
/// - Schedule type: 1 byte (0=basal, 1=temp, 2=bolus)
/// - Checksum: 2 bytes
/// - Pulses/timings: variable
///
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/SetInsulinScheduleCommand.swift
public struct ErosSetInsulinScheduleCommand: Sendable, Equatable {
    /// Message block type for SetInsulinSchedule
    public static let blockType: UInt8 = 0x1A
    
    /// Schedule types
    public enum ScheduleType: UInt8, Sendable {
        case basal = 0
        case tempBasal = 1
        case bolus = 2
    }
    
    /// Nonce for security validation
    public let nonce: UInt32
    
    /// Schedule type
    public let scheduleType: ScheduleType
    
    /// Insulin units (for bolus)
    public let units: Double
    
    /// Time between pulses (for bolus)
    public let timeBetweenPulses: TimeInterval
    
    /// Delivery table
    public let table: ErosBolusDeliveryTable
    
    /// Create bolus command
    public init(nonce: UInt32, units: Double, timeBetweenPulses: TimeInterval = ErosPodConstants.secondsPerBolusPulse) {
        self.nonce = nonce
        self.scheduleType = .bolus
        self.units = units
        self.timeBetweenPulses = timeBetweenPulses
        self.table = ErosBolusDeliveryTable(units: units)
    }
    
    /// Encode command to data
    public var data: Data {
        let pulses = UInt16(round(units / ErosPodConstants.pulseSize))
        let multiplier = UInt16(round(timeBetweenPulses * 8))
        let fieldA = pulses * multiplier
        
        var scheduleData = Data([UInt8(table.numSegments())])
        scheduleData.append(UInt8(fieldA >> 8))
        scheduleData.append(UInt8(fieldA & 0xFF))
        scheduleData.append(UInt8(pulses >> 8))
        scheduleData.append(UInt8(pulses & 0xFF))
        
        // Table entries (simplified for immediate bolus)
        for entry in table.entries {
            scheduleData.append(contentsOf: entry.data)
        }
        
        // Calculate checksum
        let checksum = scheduleData[0..<5].reduce(0) { $0 + UInt16($1) } +
            table.entries.reduce(0) { $0 + $1.checksum() }
        
        // Build full command
        var command = Data([Self.blockType])
        let length = 8 + scheduleData.count
        command.append(UInt8(length))
        
        // Nonce (big-endian)
        command.append(UInt8(nonce >> 24))
        command.append(UInt8((nonce >> 16) & 0xFF))
        command.append(UInt8((nonce >> 8) & 0xFF))
        command.append(UInt8(nonce & 0xFF))
        
        // Schedule type
        command.append(scheduleType.rawValue)
        
        // Checksum
        command.append(UInt8(checksum >> 8))
        command.append(UInt8(checksum & 0xFF))
        
        // Schedule data
        command.append(scheduleData)
        
        return command
    }
}

// MARK: - BolusExtra Command (PUMP-PG-001)

/// BolusExtraCommand encoder for bolus configuration
/// Format: 17 0d BEEP PPPP TTTTTTTT EEEE EEEEEEEE
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/BolusExtraCommand.swift
public struct ErosBolusExtraCommand: Sendable, Equatable {
    /// Message block type
    public static let blockType: UInt8 = 0x17
    
    /// Acknowledgement beep when bolus starts
    public let acknowledgementBeep: Bool
    
    /// Completion beep when bolus finishes
    public let completionBeep: Bool
    
    /// Reminder interval (minutes)
    public let programReminderInterval: TimeInterval
    
    /// Units for immediate bolus
    public let units: Double
    
    /// Time between pulses
    public let timeBetweenPulses: TimeInterval
    
    /// Units for extended portion
    public let extendedUnits: Double
    
    /// Duration for extended bolus
    public let extendedDuration: TimeInterval
    
    public init(
        units: Double,
        timeBetweenPulses: TimeInterval = ErosPodConstants.secondsPerBolusPulse,
        extendedUnits: Double = 0,
        extendedDuration: TimeInterval = 0,
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = false,
        programReminderInterval: TimeInterval = 0
    ) {
        self.units = units
        self.timeBetweenPulses = timeBetweenPulses > 0 ? timeBetweenPulses : ErosPodConstants.secondsPerBolusPulse
        self.extendedUnits = extendedUnits
        self.extendedDuration = extendedDuration
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
    }
    
    /// Encode command to data
    public var data: Data {
        let reminderMinutes = UInt8(min(programReminderInterval / 60, 63))
        let beepOptions = reminderMinutes |
            (completionBeep ? 0x40 : 0) |
            (acknowledgementBeep ? 0x80 : 0)
        
        var data = Data([Self.blockType, 0x0D, beepOptions])
        
        // Immediate pulses × 10 (big-endian)
        let pulsesX10 = UInt16(round(units * ErosPodConstants.pulsesPerUnit * 10))
        data.append(UInt8(pulsesX10 >> 8))
        data.append(UInt8(pulsesX10 & 0xFF))
        
        // Time between pulses in 1/100ths of ms (big-endian UInt32)
        let delayHundredthsMs = UInt32(timeBetweenPulses * 100_000)
        data.append(UInt8(delayHundredthsMs >> 24))
        data.append(UInt8((delayHundredthsMs >> 16) & 0xFF))
        data.append(UInt8((delayHundredthsMs >> 8) & 0xFF))
        data.append(UInt8(delayHundredthsMs & 0xFF))
        
        // Extended pulses × 10
        let extPulsesX10 = UInt16(round(extendedUnits * ErosPodConstants.pulsesPerUnit * 10))
        data.append(UInt8(extPulsesX10 >> 8))
        data.append(UInt8(extPulsesX10 & 0xFF))
        
        // Extended time between pulses
        let extTimeBetween: UInt32
        if extPulsesX10 > 0 {
            extTimeBetween = UInt32(extendedDuration / (Double(extPulsesX10) / 10) * 100_000)
        } else {
            extTimeBetween = 0
        }
        data.append(UInt8(extTimeBetween >> 24))
        data.append(UInt8((extTimeBetween >> 16) & 0xFF))
        data.append(UInt8((extTimeBetween >> 8) & 0xFF))
        data.append(UInt8(extTimeBetween & 0xFF))
        
        return data
    }
}

// MARK: - CancelDelivery Command (PUMP-PG-001)

/// CancelDeliveryCommand for stopping bolus/temp basal
/// Format: 1f 05 NNNNNNNN BB
/// Source: externals/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/CancelDeliveryCommand.swift
public struct ErosCancelDeliveryCommand: Sendable, Equatable {
    /// Message block type
    public static let blockType: UInt8 = 0x1F
    
    /// Delivery types to cancel
    public struct CancelType: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        
        public static let basal = CancelType(rawValue: 1 << 0)
        public static let tempBasal = CancelType(rawValue: 1 << 1)
        public static let bolus = CancelType(rawValue: 1 << 2)
        public static let all: CancelType = [.basal, .tempBasal, .bolus]
    }
    
    /// Nonce for security
    public let nonce: UInt32
    
    /// What to cancel
    public let cancelType: CancelType
    
    /// Beep configuration
    public let beepType: UInt8
    
    public init(nonce: UInt32, cancelType: CancelType, beepType: UInt8 = 0) {
        self.nonce = nonce
        self.cancelType = cancelType
        self.beepType = beepType
    }
    
    /// Encode command to data
    public var data: Data {
        var data = Data([Self.blockType, 0x05])
        
        // Nonce (big-endian)
        data.append(UInt8(nonce >> 24))
        data.append(UInt8((nonce >> 16) & 0xFF))
        data.append(UInt8((nonce >> 8) & 0xFF))
        data.append(UInt8(nonce & 0xFF))
        
        // Cancel type + beep
        data.append(beepType | cancelType.rawValue)
        
        return data
    }
}

// MARK: - Temp Basal Types (PUMP-PG-002)

/// Rate entry for temp basal delivery timing
/// Source: externals/Trio/OmniKit/OmniKit/OmnipodCommon/BasalDeliveryTable.swift
public struct ErosRateEntry: Sendable, Equatable {
    /// Total pulses in this entry
    public let totalPulses: Double
    
    /// Time between pulses
    public let delayBetweenPulses: TimeInterval
    
    public init(totalPulses: Double, delayBetweenPulses: TimeInterval) {
        self.totalPulses = totalPulses
        self.delayBetweenPulses = delayBetweenPulses
    }
    
    /// Calculate rate from this entry (U/hr)
    public var rate: Double {
        if totalPulses == 0 {
            return 0
        }
        return round((3600.0 / delayBetweenPulses / ErosPodConstants.pulsesPerUnit) * 100) / 100.0
    }
    
    /// Calculate duration from this entry
    public var duration: TimeInterval {
        if totalPulses == 0 {
            return 30.0 * 60.0  // Fixed 30 min for zero rate
        }
        return round(delayBetweenPulses * totalPulses)
    }
    
    /// Encode to 6 bytes for TempBasalExtraCommand
    /// Format: PPPP (2) TTTTTTTT (4) - pulses×10, delay in 100ths of ms
    public var data: Data {
        let pulsesX10 = UInt16(round(totalPulses * 10))
        let delayHundredths = UInt32(delayBetweenPulses * 100_000)  // seconds to 100ths of ms
        
        var data = Data()
        data.append(UInt8(pulsesX10 >> 8))
        data.append(UInt8(pulsesX10 & 0xFF))
        data.append(UInt8(delayHundredths >> 24))
        data.append(UInt8((delayHundredths >> 16) & 0xFF))
        data.append(UInt8((delayHundredths >> 8) & 0xFF))
        data.append(UInt8(delayHundredths & 0xFF))
        return data
    }
    
    /// Create rate entries for temp basal
    /// Source: externals/Trio/OmniKit/OmniKit/OmnipodCommon/BasalDeliveryTable.swift
    public static func makeEntries(rate: Double, duration: TimeInterval) -> [ErosRateEntry] {
        let maxPulsesPerEntry: Double = 6553.5  // max 0xFFFF/10 pulses
        var entries = [ErosRateEntry]()
        let numHalfHours = max(Int(round(duration / (30.0 * 60.0))), 1)
        
        var remainingSegments = numHalfHours
        let pulsesPerSegment = round(rate / ErosPodConstants.pulseSize) / 2
        let maxSegmentsPerEntry = pulsesPerSegment > 0 ? Int(maxPulsesPerEntry / pulsesPerSegment) : 1
        var remainingPulses = rate * Double(numHalfHours) / 2 / ErosPodConstants.pulseSize
        
        while remainingSegments > 0 {
            let entry: ErosRateEntry
            if rate == 0 {
                // Zero rate: one entry per segment with no pulses
                entry = ErosRateEntry(totalPulses: 0, delayBetweenPulses: ErosPodConstants.maxTimeBetweenPulses)
                remainingSegments -= 1
            } else {
                let numSegments = min(maxSegmentsPerEntry, Int(round(remainingPulses / pulsesPerSegment)))
                remainingSegments -= numSegments
                let pulseCount = pulsesPerSegment * Double(numSegments)
                let delayBetweenPulses = 3600.0 / rate * ErosPodConstants.pulseSize
                entry = ErosRateEntry(totalPulses: pulseCount, delayBetweenPulses: delayBetweenPulses)
                remainingPulses -= pulseCount
            }
            entries.append(entry)
        }
        return entries
    }
}

/// TempBasalExtraCommand encoder for temp basal configuration
/// Format: 16 LL BEEP 00 PPPP TTTTTTTT [PPPP TTTTTTTT]...
/// - Block type: 0x16
/// - Length: 8 + 6*N bytes (N = number of rate entries)
/// - Beep: 1 byte (bit 7=ack, bit 6=complete, bits 0-5=reminder minutes)
/// - Reserved: 0x00
/// - First entry pulses×10: 2 bytes big-endian
/// - First entry delay: 4 bytes big-endian (100ths of ms)
/// - Additional entries...
///
/// Source: externals/Trio/OmniKit/OmniKit/OmnipodCommon/MessageBlocks/TempBasalExtraCommand.swift
public struct ErosTempBasalExtraCommand: Sendable, Equatable {
    /// Message block type
    public static let blockType: UInt8 = 0x16
    
    /// Acknowledgement beep when temp basal starts
    public let acknowledgementBeep: Bool
    
    /// Completion beep when temp basal finishes
    public let completionBeep: Bool
    
    /// Program reminder interval (minutes, max 63)
    public let programReminderInterval: TimeInterval
    
    /// Remaining pulses for first entry
    public let remainingPulses: Double
    
    /// Delay until first pulse
    public let delayUntilFirstPulse: TimeInterval
    
    /// Rate entries
    public let rateEntries: [ErosRateEntry]
    
    /// Create temp basal extra command
    public init(rate: Double, duration: TimeInterval,
                acknowledgementBeep: Bool = false,
                completionBeep: Bool = false,
                programReminderInterval: TimeInterval = 0) {
        self.rateEntries = ErosRateEntry.makeEntries(rate: rate, duration: duration)
        self.remainingPulses = rateEntries.first?.totalPulses ?? 0
        self.delayUntilFirstPulse = rateEntries.first?.delayBetweenPulses ?? ErosPodConstants.maxTimeBetweenPulses
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
    }
    
    /// Encode command to data
    public var data: Data {
        let reminderMinutes = UInt8(min(63, Int(programReminderInterval / 60.0)))
        let beepByte = reminderMinutes |
            (completionBeep ? 0x40 : 0x00) |
            (acknowledgementBeep ? 0x80 : 0x00)
        
        var data = Data([
            Self.blockType,
            UInt8(8 + rateEntries.count * 6),  // Length
            beepByte,
            0x00  // Reserved
        ])
        
        // Remaining pulses × 10
        let pulsesX10 = UInt16(round(remainingPulses * 10))
        data.append(UInt8(pulsesX10 >> 8))
        data.append(UInt8(pulsesX10 & 0xFF))
        
        // Delay until first pulse (100ths of ms)
        let delayHundredths = UInt32(delayUntilFirstPulse * 100_000)
        data.append(UInt8(delayHundredths >> 24))
        data.append(UInt8((delayHundredths >> 16) & 0xFF))
        data.append(UInt8((delayHundredths >> 8) & 0xFF))
        data.append(UInt8(delayHundredths & 0xFF))
        
        // Additional rate entries
        for entry in rateEntries {
            data.append(entry.data)
        }
        
        return data
    }
}

/// Temp basal delivery table for SetInsulinScheduleCommand
/// Source: externals/Trio/OmniKit/OmniKit/OmnipodCommon/BasalDeliveryTable.swift
public struct ErosTempBasalDeliveryTable: Sendable, Equatable {
    public let entries: [ErosInsulinTableEntry]
    
    public init(entries: [ErosInsulinTableEntry]) {
        self.entries = entries
    }
    
    /// Create temp basal table for given rate and duration
    public init(rate: Double, duration: TimeInterval) {
        let numSegments = max(1, Int(round(duration / (30.0 * 60.0))))
        let pulsesPerSegment = Int(round(rate / ErosPodConstants.pulseSize / 2))
        
        // Single entry for flat temp basal
        self.entries = [ErosInsulinTableEntry(
            segments: numSegments,
            pulses: pulsesPerSegment,
            alternateSegmentPulse: false
        )]
    }
    
    /// Number of segments in this table
    public func numSegments() -> Int {
        return entries.reduce(0) { $0 + $1.segments }
    }
    
    /// First segment pulses
    public var firstSegmentPulses: Int {
        return entries.first?.pulses ?? 0
    }
}

/// Extended SetInsulinScheduleCommand for temp basal (PUMP-PG-002)
/// Adds temp basal encoding to existing command structure
public struct ErosTempBasalScheduleCommand: Sendable, Equatable {
    /// Message block type for SetInsulinSchedule
    public static let blockType: UInt8 = 0x1A
    
    /// Nonce for security validation
    public let nonce: UInt32
    
    /// Rate in U/hr
    public let rate: Double
    
    /// Duration in seconds
    public let duration: TimeInterval
    
    /// Delivery table
    public let table: ErosTempBasalDeliveryTable
    
    public init(nonce: UInt32, rate: Double, duration: TimeInterval) {
        self.nonce = nonce
        self.rate = rate
        self.duration = duration
        self.table = ErosTempBasalDeliveryTable(rate: rate, duration: duration)
    }
    
    /// Encode command to data
    /// Format: 1a LL NNNNNNNN 01 CCCC SS RRRR PPPP [TT PPPP]...
    public var data: Data {
        let numSegments = table.numSegments()
        let pulsesPerSegment = table.firstSegmentPulses
        let secondsRemaining = UInt16(duration)
        
        // Schedule data: segments, seconds<<3, firstPulses, table entries
        var scheduleData = Data([UInt8(numSegments)])
        
        // Seconds remaining shifted left 3 bits (big-endian)
        let secondsField = secondsRemaining << 3
        scheduleData.append(UInt8(secondsField >> 8))
        scheduleData.append(UInt8(secondsField & 0xFF))
        
        // First segment pulses (big-endian)
        scheduleData.append(UInt8(pulsesPerSegment >> 8))
        scheduleData.append(UInt8(pulsesPerSegment & 0xFF))
        
        // Table entries
        for entry in table.entries {
            // For temp basal: segment count (1 byte) + pulses (2 bytes)
            let segmentByte = UInt8((entry.segments - 1) | (entry.alternateSegmentPulse ? 0x80 : 0x00))
            scheduleData.append(segmentByte)
            scheduleData.append(UInt8(entry.pulses >> 8))
            scheduleData.append(UInt8(entry.pulses & 0xFF))
        }
        
        // Calculate checksum
        let checksum = scheduleData.reduce(UInt16(0)) { $0 + UInt16($1) }
        
        // Build full command
        var command = Data([Self.blockType])
        let length = 8 + scheduleData.count
        command.append(UInt8(length))
        
        // Nonce (big-endian)
        command.append(UInt8(nonce >> 24))
        command.append(UInt8((nonce >> 16) & 0xFF))
        command.append(UInt8((nonce >> 8) & 0xFF))
        command.append(UInt8(nonce & 0xFF))
        
        // Schedule type: 1 = temp basal
        command.append(0x01)
        
        // Checksum
        command.append(UInt8(checksum >> 8))
        command.append(UInt8(checksum & 0xFF))
        
        // Schedule data
        command.append(scheduleData)
        
        return command
    }
}

// MARK: - Eros BLE Manager

/// Manages Eros pod communication via RileyLink/OrangeLink bridge
public actor ErosBLEManager {
    
    // MARK: - State
    
    /// Current connection state
    public private(set) var state: ErosConnectionState = .disconnected
    
    /// RileyLink manager for BLE-to-RF communication
    private let rileyLinkManager: RileyLinkManager
    
    /// Current pod session (if paired)
    public private(set) var currentSession: ErosSession?
    
    /// Current pod info (if known)
    public private(set) var podInfo: ErosPodInfo?
    
    /// Current RF frequency (after tuning)
    public private(set) var currentFrequency: Double?
    
    /// Last error encountered
    public private(set) var lastError: ErosBLEError?
    
    /// Simulation mode for testing
    public private(set) var simulationMode: SimulationMode = .live
    
    // MARK: - Configuration
    
    /// Timeout for RF commands
    public var commandTimeout: TimeInterval = 2.0
    
    /// Number of retries for failed commands
    public var retryCount: Int = ErosBLEConstants.maxRetries
    
    // MARK: - Private State
    
    private var observers: [UUID: (ErosConnectionState) -> Void] = [:]
    
    // MARK: - Initialization
    
    public init(rileyLinkManager: RileyLinkManager = .shared) {
        self.rileyLinkManager = rileyLinkManager
    }
    
    /// Initialize with explicit simulation mode (for testing)
    public init(simulationMode: SimulationMode) {
        self.rileyLinkManager = .shared
        self.simulationMode = simulationMode
    }
    
    // MARK: - Connection
    
    /// Connect to pod via RileyLink device
    public func connect(to rileyLinkDevice: RileyLinkDevice) async throws {
        guard state == .disconnected || state == .error else {
            throw ErosBLEError.rfCommunicationError("Already connecting or connected")
        }
        
        state = .connectingToBridge
        notifyObservers()
        
        do {
            // Connect to RileyLink first
            try await rileyLinkManager.connect(to: rileyLinkDevice)
            
            state = .bridgeConnected
            notifyObservers()
            
            // Tune RF frequency
            try await tuneFrequency()
            
            state = .ready
            notifyObservers()
            
        } catch {
            state = .error
            lastError = .rfCommunicationError(error.localizedDescription)
            notifyObservers()
            throw ErosBLEError.rfCommunicationError(error.localizedDescription)
        }
    }
    
    /// Disconnect from pod and RileyLink
    public func disconnect() async {
        currentSession = nil
        podInfo = nil
        currentFrequency = nil
        state = .disconnected
        notifyObservers()
        
        await rileyLinkManager.disconnect()
    }
    
    // MARK: - RF Tuning
    
    /// Tune to optimal RF frequency for pod communication
    private func tuneFrequency() async throws {
        state = .tuning
        notifyObservers()
        
        // For now, use default frequency
        // Real implementation would scan bands and measure RSSI
        currentFrequency = ErosBLEConstants.rfFrequency
        
        // Simulate tuning delay
        if simulationMode != .test {
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    // MARK: - Pod Pairing
    
    /// Pairing result containing pod information from VersionResponses
    public struct ErosPairingResult: Sendable {
        /// Pod firmware version (from VersionResponse)
        public let firmwareVersion: ErosFirmwareVersion
        
        /// Pod lot number
        public let lot: UInt32
        
        /// Pod TID/serial number
        public let tid: UInt32
        
        /// Pod progress status after pairing
        public let progressStatus: ErosPodProgressStatus
        
        /// Pulse size in units (from SetupPod response)
        public let pulseSize: Double?
        
        /// Service duration in seconds (from SetupPod response)
        public let serviceDuration: TimeInterval?
    }
    
    /// Pair with a new Eros pod
    ///
    /// The pairing sequence is:
    /// 1. Send AssignAddress command (0x07) to broadcast address
    /// 2. Receive VersionResponse (0x15) with lot/tid
    /// 3. Send SetupPod command (0x03) with lot/tid
    /// 4. Receive VersionResponse (0x1B) with pod configuration
    ///
    /// - Parameters:
    ///   - address: Pod address to assign
    ///   - timeZone: Time zone for pod activation timestamp
    /// - Returns: Pairing result with pod information
    /// - Throws: ErosBLEError on communication failure
    @discardableResult
    public func pairPod(address: UInt32, timeZone: TimeZone = .current) async throws -> ErosPairingResult {
        guard state == .ready || state == .searchingForPod else {
            throw ErosBLEError.rileyLinkNotReady
        }
        
        state = .searchingForPod
        notifyObservers()
        
        // Create initial session for pairing (broadcast address)
        var session = ErosSession(podAddress: ErosBLEConstants.defaultPDMAddress)
        
        // Step 1: Send AssignAddress to broadcast address
        let assignAddress = ErosAssignAddressCommand(address: address)
        let assignPacket = buildPacket(
            type: .pdm,
            data: assignAddress.data,
            session: session
        )
        
        let assignResponse = try await sendPacketWithRetry(assignPacket, retries: retryCount)
        
        // Parse AssignAddress VersionResponse (0x15)
        let assignVersionResponse = try ErosVersionResponse(encodedData: assignResponse.data)
        guard assignVersionResponse.isAssignAddressResponse else {
            throw ErosBLEError.invalidResponse("Expected AssignAddress VersionResponse (0x15)")
        }
        
        // Update session with received pod info
        session.packetSequence += 1
        session.messageSequence += 1
        
        // Step 2: Send SetupPod with lot/tid from VersionResponse
        let setupPod = ErosSetupPodCommand(
            address: address,
            lot: assignVersionResponse.lot,
            tid: assignVersionResponse.tid,
            timeZone: timeZone
        )
        
        let setupPacket = buildPacket(
            type: .pdm,
            data: setupPod.data,
            session: session
        )
        
        let setupResponse = try await sendPacketWithRetry(setupPacket, retries: retryCount)
        
        // Parse SetupPod VersionResponse (0x1B)
        let setupVersionResponse = try ErosVersionResponse(encodedData: setupResponse.data)
        guard setupVersionResponse.isSetupPodResponse else {
            throw ErosBLEError.invalidResponse("Expected SetupPod VersionResponse (0x1B)")
        }
        
        // Verify pod is now in pairing completed state
        guard setupVersionResponse.podProgressStatus == ErosPodProgressStatus.pairingCompleted else {
            throw ErosBLEError.invalidResponse("Pod not in pairing completed state: \(setupVersionResponse.podProgressStatus)")
        }
        
        // Update session to use assigned pod address
        currentSession = ErosSession(podAddress: address)
        currentSession?.packetSequence = session.packetSequence + 1
        currentSession?.messageSequence = session.messageSequence + 1
        
        state = .paired
        notifyObservers()
        
        return ErosPairingResult(
            firmwareVersion: setupVersionResponse.firmwareVersion,
            lot: setupVersionResponse.lot,
            tid: setupVersionResponse.tid,
            progressStatus: setupVersionResponse.podProgressStatus,
            pulseSize: setupVersionResponse.pulseSize,
            serviceDuration: setupVersionResponse.serviceDuration
        )
    }
    
    /// Resume session with known pod
    public func resumeSession(podAddress: UInt32, packetSequence: Int, messageSequence: Int) {
        var session = ErosSession(podAddress: podAddress)
        session.packetSequence = packetSequence
        session.messageSequence = messageSequence
        currentSession = session
        
        if state == .ready || state == .bridgeConnected {
            state = .paired
            notifyObservers()
        }
    }
    
    // MARK: - Pod Commands
    
    /// Get current pod status
    public func getPodStatus() async throws -> ErosPodInfo {
        guard let session = currentSession else {
            throw ErosBLEError.podNotPaired
        }
        
        guard state.canSendCommands || state == .paired else {
            throw ErosBLEError.notConnected
        }
        
        // Build status request packet
        let statusCommand: [UInt8] = [0x0E, 0x00]  // GetStatus type 0
        let packet = buildPacket(
            type: .pdm,
            data: Data(statusCommand),
            session: session
        )
        
        // Send and receive response
        let response = try await sendPacketWithRetry(packet, retries: retryCount)
        
        // Parse response
        let podInfo = try parseStatusResponse(response)
        self.podInfo = podInfo
        
        return podInfo
    }
    
    /// Send a bolus command
    /// - Parameters:
    ///   - units: Insulin units to deliver
    ///   - extendedDuration: Duration for extended bolus (nil for normal)
    /// Trace: PUMP-PG-001
    public func deliverBolus(units: Double, extendedDuration: TimeInterval? = nil) async throws {
        guard let session = currentSession else {
            throw ErosBLEError.podNotPaired
        }
        
        guard state.canSendCommands else {
            throw ErosBLEError.notConnected
        }
        
        // Validate bolus amount
        guard units > 0 else {
            throw ErosBLEError.messageError("Bolus amount must be positive")
        }
        
        guard units <= ErosPodConstants.maxBolus else {
            throw ErosBLEError.messageError("Bolus exceeds maximum of \(ErosPodConstants.maxBolus) U")
        }
        
        // Round to pulse size
        let roundedUnits = round(units / ErosPodConstants.pulseSize) * ErosPodConstants.pulseSize
        
        PumpLogger.protocol_.info("Eros: Delivering bolus of \(String(format: "%.2f", roundedUnits)) U")
        
        // Build SetInsulinScheduleCommand for bolus (0x1A)
        let scheduleCommand = ErosSetInsulinScheduleCommand(
            nonce: session.currentNonce,
            units: roundedUnits,
            timeBetweenPulses: ErosPodConstants.secondsPerBolusPulse
        )
        
        // Build BolusExtraCommand (0x17)
        let extraCommand = ErosBolusExtraCommand(
            units: roundedUnits,
            timeBetweenPulses: ErosPodConstants.secondsPerBolusPulse,
            acknowledgementBeep: true,
            completionBeep: true
        )
        
        // Combine commands into message
        var messageData = scheduleCommand.data
        messageData.append(extraCommand.data)
        
        // Build packet
        let packet = buildPacket(
            type: .pdm,
            data: messageData,
            session: session
        )
        
        // Send command and wait for response
        let response = try await sendPacketWithRetry(packet, retries: retryCount)
        
        // Parse status response to confirm bolus started
        let podInfo = try parseStatusResponse(response)
        self.podInfo = podInfo
        
        // Verify bolus is in progress
        guard podInfo.isBolusing else {
            throw ErosBLEError.messageError("Bolus command sent but pod not bolusing")
        }
        
        PumpLogger.protocol_.info("Eros: Bolus delivery started, \(String(format: "%.2f", roundedUnits)) U in progress")
    }
    
    /// Set temporary basal rate
    /// - Parameters:
    ///   - rate: Basal rate in U/hr
    ///   - duration: Duration in seconds
    /// Trace: PUMP-PG-002
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard let session = currentSession else {
            throw ErosBLEError.podNotPaired
        }
        
        guard state.canSendCommands else {
            throw ErosBLEError.notConnected
        }
        
        // Validate rate
        guard rate >= 0 else {
            throw ErosBLEError.messageError("Temp basal rate cannot be negative")
        }
        
        guard rate <= ErosPodConstants.maxTempBasalRate else {
            throw ErosBLEError.messageError("Temp basal rate exceeds maximum of \(ErosPodConstants.maxTempBasalRate) U/hr")
        }
        
        // Validate duration
        guard duration >= ErosPodConstants.minTempBasalDuration else {
            throw ErosBLEError.messageError("Temp basal duration must be at least \(Int(ErosPodConstants.minTempBasalDuration / 60)) minutes")
        }
        
        guard duration <= ErosPodConstants.maxTempBasalDuration else {
            throw ErosBLEError.messageError("Temp basal duration exceeds maximum of \(Int(ErosPodConstants.maxTempBasalDuration / 3600)) hours")
        }
        
        // Round duration to 30-minute increments
        let roundedDuration = round(duration / 1800) * 1800
        
        // Round rate to pulse size
        let roundedRate = round(rate / ErosPodConstants.pulseSize) * ErosPodConstants.pulseSize
        
        PumpLogger.protocol_.info("Eros: Setting temp basal \(String(format: "%.2f", roundedRate)) U/hr for \(Int(roundedDuration / 60)) minutes")
        
        // Build SetInsulinScheduleCommand for temp basal (0x1A with type=1)
        let scheduleCommand = ErosTempBasalScheduleCommand(
            nonce: session.currentNonce,
            rate: roundedRate,
            duration: roundedDuration
        )
        
        // Build TempBasalExtraCommand (0x16)
        let extraCommand = ErosTempBasalExtraCommand(
            rate: roundedRate,
            duration: roundedDuration,
            acknowledgementBeep: true,
            completionBeep: false
        )
        
        // Combine commands into message
        var messageData = scheduleCommand.data
        messageData.append(extraCommand.data)
        
        // Build packet
        let packet = buildPacket(
            type: .pdm,
            data: messageData,
            session: session
        )
        
        // Send command and wait for response
        let response = try await sendPacketWithRetry(packet, retries: retryCount)
        
        // Parse status response to confirm temp basal started
        let podInfo = try parseStatusResponse(response)
        self.podInfo = podInfo
        
        // Verify temp basal is active
        guard podInfo.isTempBasalActive else {
            throw ErosBLEError.messageError("Temp basal command sent but not active")
        }
        
        PumpLogger.protocol_.info("Eros: Temp basal started, \(String(format: "%.2f", roundedRate)) U/hr")
    }
    
    /// Cancel temporary basal rate
    /// Trace: PUMP-PG-002
    public func cancelTempBasal() async throws {
        guard let session = currentSession else {
            throw ErosBLEError.podNotPaired
        }
        
        guard state.canSendCommands else {
            throw ErosBLEError.notConnected
        }
        
        PumpLogger.protocol_.info("Eros: Cancelling temp basal")
        
        let cancelCommand = ErosCancelDeliveryCommand(
            nonce: session.currentNonce,
            cancelType: .tempBasal,
            beepType: 0x04  // Beep on cancel
        )
        
        let packet = buildPacket(
            type: .pdm,
            data: cancelCommand.data,
            session: session
        )
        
        let response = try await sendPacketWithRetry(packet, retries: retryCount)
        let podInfo = try parseStatusResponse(response)
        self.podInfo = podInfo
        
        // Verify temp basal is cancelled
        if podInfo.isTempBasalActive {
            PumpLogger.protocol_.warning("Eros: Temp basal cancel sent but still active")
        }
        
        PumpLogger.protocol_.info("Eros: Temp basal cancelled")
    }
    
    /// Cancel current bolus or temp basal
    public func cancelDelivery() async throws {
        guard let session = currentSession else {
            throw ErosBLEError.podNotPaired
        }
        
        guard state.canSendCommands else {
            throw ErosBLEError.notConnected
        }
        
        PumpLogger.protocol_.info("Eros: Cancelling all delivery")
        
        let cancelCommand = ErosCancelDeliveryCommand(
            nonce: session.currentNonce,
            cancelType: .all,
            beepType: 0x04
        )
        
        let packet = buildPacket(
            type: .pdm,
            data: cancelCommand.data,
            session: session
        )
        
        let response = try await sendPacketWithRetry(packet, retries: retryCount)
        let podInfo = try parseStatusResponse(response)
        self.podInfo = podInfo
        
        PumpLogger.protocol_.info("Eros: All delivery cancelled")
    }
    
    /// Deactivate pod (for pod replacement)
    public func deactivatePod() async throws {
        guard currentSession != nil else {
            throw ErosBLEError.podNotPaired
        }
        
        // TODO: Implement deactivation
        throw ErosBLEError.messageError("Pod deactivation not yet implemented")
    }
    
    // MARK: - Packet Building
    
    /// Build an Eros packet for transmission
    private func buildPacket(
        type: ErosPacketType,
        data: Data,
        session: ErosSession
    ) -> ErosPacket {
        return ErosPacket(
            address: session.podAddress,
            packetType: type,
            sequenceNum: session.packetSequence,
            data: data
        )
    }
    
    // MARK: - RF Communication
    
    /// Send packet and receive response with retry logic
    private func sendPacketWithRetry(
        _ packet: ErosPacket,
        retries: Int
    ) async throws -> ErosPacket {
        var lastError: Error?
        
        for attempt in 0..<retries {
            do {
                let response = try await sendPacket(packet)
                
                // Update session sequence on success
                currentSession?.incrementPacketSequence()
                
                return response
            } catch {
                lastError = error
                
                // Wait before retry (exponential backoff)
                if attempt < retries - 1 && simulationMode != .test {
                    let delay = UInt64(100_000_000 * (attempt + 1))
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        throw lastError ?? ErosBLEError.noPodResponse
    }
    
    /// Send single packet via RileyLink
    private func sendPacket(_ packet: ErosPacket) async throws -> ErosPacket {
        guard let frequency = currentFrequency else {
            throw ErosBLEError.rileyLinkNotReady
        }
        
        // Encode packet for transmission
        let encodedPacket = packet.encoded()
        
        // In simulation mode, return mock response
        if simulationMode.isSimulated {
            return try simulatePodResponse(to: packet)
        }
        
        // Send via RileyLink
        let responseData = try await rileyLinkManager.sendAndListen(
            encodedPacket,
            timeout: commandTimeout,
            frequency: frequency
        )
        
        // Check for empty response
        guard !responseData.isEmpty else {
            throw ErosBLEError.noPodResponse
        }
        
        // Decode response packet
        do {
            return try ErosPacket(encodedData: responseData)
        } catch let error as ErosPacketError {
            throw ErosBLEError.packetError(error)
        }
    }
    
    // MARK: - Response Parsing
    
    /// Parse status response from pod
    private func parseStatusResponse(_ packet: ErosPacket) throws -> ErosPodInfo {
        guard packet.packetType == .pod else {
            throw ErosBLEError.invalidResponse("Expected POD packet, got \(packet.packetType)")
        }
        
        let data = packet.data
        guard data.count >= 10 else {
            throw ErosBLEError.invalidResponse("Status response too short")
        }
        
        // Parse status fields
        // Byte 0: block type + delivery status (high nibble)
        let deliveryStatus = (data[0] >> 4) & 0x0F
        let progressStatus = data[1] & 0x0F
        let faultCode: UInt8? = (data[2] != 0) ? data[2] : nil
        
        // Parse reservoir (bytes 3-4)
        let reservoirRaw = UInt16(data[3]) << 8 | UInt16(data[4])
        let reservoirLevel: Double? = reservoirRaw < 1023 ? Double(reservoirRaw) * 0.05 : nil
        
        return ErosPodInfo(
            address: packet.address,
            lot: 0,  // Would be from pairing
            tid: 0,
            pmVersion: "2.x",
            piVersion: "2.x",
            reservoirLevel: reservoirLevel,
            podProgressStatus: progressStatus,
            deliveryStatus: deliveryStatus,
            faultCode: faultCode,
            minutesSinceActivation: 0
        )
    }
    
    // MARK: - Simulation
    
    /// Simulate pod response for testing
    private func simulatePodResponse(to packet: ErosPacket) throws -> ErosPacket {
        // Create mock response based on request type
        var responseData = Data()
        
        // Check command type in data
        // 0x1A = SetInsulinSchedule (bolus/temp basal depending on schedule type byte)
        // 0x1F = CancelDelivery
        var deliveryStatus: UInt8 = 0x01  // Normal basal running
        
        if packet.data.count > 0 {
            let blockType = packet.data[0]
            
            if blockType == ErosSetInsulinScheduleCommand.blockType && packet.data.count > 6 {
                // SetInsulinScheduleCommand - check schedule type byte at index 6
                // Format: 0x1A (0), length (1), nonce (2-5), schedule type (6)
                let scheduleType = packet.data[6]
                switch scheduleType {
                case 0x01:  // Temp basal
                    deliveryStatus = 0x02  // Temp basal active
                case 0x02:  // Bolus
                    deliveryStatus = 0x04  // Bolusing
                default:
                    deliveryStatus = 0x01  // Normal
                }
            } else if blockType == ErosCancelDeliveryCommand.blockType {
                // Cancel command - return to normal delivery
                deliveryStatus = 0x01
            }
        }
        
        // Mock status response
        responseData.append(0x1D | (deliveryStatus << 4))  // Response type + delivery status
        responseData.append(0x09)  // Progress status = running
        responseData.append(0x00)  // No fault
        responseData.append(0x01)  // Reservoir high byte
        responseData.append(0x90)  // Reservoir low byte (~20U)
        responseData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00])  // Padding
        
        return ErosPacket(
            address: packet.address,
            packetType: .pod,
            sequenceNum: (packet.sequenceNum + 1) & 0x1F,
            data: responseData
        )
    }
    
    // MARK: - Observers
    
    /// Add state change observer
    public func addObserver(_ id: UUID, handler: @escaping (ErosConnectionState) -> Void) {
        observers[id] = handler
    }
    
    /// Remove state change observer
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers() {
        let currentState = state
        for handler in observers.values {
            handler(currentState)
        }
    }
}

// MARK: - ErosBLEManager + Testing

extension ErosBLEManager {
    /// Create manager in test mode (instant responses)
    public static func forTesting() -> ErosBLEManager {
        ErosBLEManager(simulationMode: .test)
    }
    
    /// Create manager in demo mode (simulated with delays)
    public static func forDemo() -> ErosBLEManager {
        ErosBLEManager(simulationMode: .demo)
    }
    
    /// Set state directly for testing (PUMP-PG-001)
    public func setTestState(_ newState: ErosConnectionState) {
        state = newState
    }
    
    /// Set frequency for testing (PUMP-PG-002)
    public func setTestFrequency(_ frequency: Double) {
        currentFrequency = frequency
    }
}
