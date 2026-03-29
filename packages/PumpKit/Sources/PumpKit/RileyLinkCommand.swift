//
//  RileyLinkCommand.swift
//  PumpKit
//
//  RileyLink BLE command protocol layer
//  Reference: externals/rileylink_ios/RileyLinkBLEKit/Command.swift
//

import Foundation

// MARK: - Command Codes

/// RileyLink firmware command opcodes
public enum RileyLinkCommandCode: UInt8, Sendable {
    case getState         = 0x01
    case getVersion       = 0x02
    case getPacket        = 0x03
    case sendPacket       = 0x04
    case sendAndListen    = 0x05
    case updateRegister   = 0x06
    case reset            = 0x07
    case setLEDMode       = 0x08
    case readRegister     = 0x09
    case setModeRegisters = 0x0A
    case setSWEncoding    = 0x0B
    case setPreamble      = 0x0C
    case resetRadioConfig = 0x0D
    case getStatistics    = 0x0E
}

/// Software encoding types for RF
public enum SoftwareEncodingType: UInt8, Sendable {
    case none       = 0x00
    case manchester = 0x01
    case fourbsixb  = 0x02
}

// MARK: - Response Codes

/// RileyLink response status codes
public enum RileyLinkResponseCode: UInt8, Sendable {
    case rxTimeout          = 0xAA
    case commandInterrupted = 0xBB
    case zeroData           = 0xCC
    case success            = 0xDD
    case invalidParam       = 0x11
    case unknownCommand     = 0x22
}

// MARK: - Radio Firmware Version

/// Represents the RileyLink radio firmware version
/// Supports multiple firmware string formats:
/// - "subg_rfspy X.Y" - standard RileyLink radio firmware
/// - "ble_rfspy X.Y" - BLE firmware (EmaLink, some OrangeLink)
/// - Any numeric "X.Y.Z" format - fallback for unknown devices
public struct RadioFirmwareVersion: Sendable, Equatable, CustomStringConvertible {
    private static let subgPrefix = "subg_rfspy "
    private static let blePrefix = "ble_rfspy "
    
    public let components: [Int]
    public let versionString: String
    
    /// Parse firmware version from device response
    /// Handles multiple formats: "subg_rfspy X.Y", "ble_rfspy X.Y", or raw "X.Y.Z"
    public init?(versionString: String) {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try "subg_rfspy X.Y" format
        if trimmed.hasPrefix(RadioFirmwareVersion.subgPrefix),
           let idx = trimmed.index(trimmed.startIndex, offsetBy: RadioFirmwareVersion.subgPrefix.count, limitedBy: trimmed.endIndex) {
            self.components = trimmed[idx...]
                .split(separator: ".")
                .compactMap { Int($0) }
            self.versionString = trimmed
            return
        }
        
        // Try "ble_rfspy X.Y" format (EmaLink, OrangeLink BLE layer)
        if trimmed.hasPrefix(RadioFirmwareVersion.blePrefix),
           let idx = trimmed.index(trimmed.startIndex, offsetBy: RadioFirmwareVersion.blePrefix.count, limitedBy: trimmed.endIndex) {
            self.components = trimmed[idx...]
                .split(separator: ".")
                .compactMap { Int($0) }
            self.versionString = trimmed
            return
        }
        
        // Fallback: Try to find "X.Y" version pattern using regex-like approach
        // Scan for pattern like "1.0", "2.2", etc. anywhere in the string
        let dotIndex = trimmed.firstIndex(of: ".")
        if let dotIdx = dotIndex {
            // Get the number before the dot
            var beforeStart = dotIdx
            while beforeStart > trimmed.startIndex {
                let prevIdx = trimmed.index(before: beforeStart)
                if trimmed[prevIdx].isNumber {
                    beforeStart = prevIdx
                } else {
                    break
                }
            }
            
            // Get the number after the dot
            var afterEnd = trimmed.index(after: dotIdx)
            while afterEnd < trimmed.endIndex && trimmed[afterEnd].isNumber {
                afterEnd = trimmed.index(after: afterEnd)
            }
            
            let majorStr = String(trimmed[beforeStart..<dotIdx])
            let minorStr = String(trimmed[trimmed.index(after: dotIdx)..<afterEnd])
            
            if let major = Int(majorStr), !majorStr.isEmpty,
               let minor = Int(minorStr), !minorStr.isEmpty {
                self.components = [major, minor]
                self.versionString = trimmed
                return
            }
        }
        
        return nil
    }
    
    private init(components: [Int], versionString: String) {
        self.components = components
        self.versionString = versionString
    }
    
    public static var unknown: RadioFirmwareVersion {
        return RadioFirmwareVersion(components: [0], versionString: "Unknown")
    }
    
    /// SWIFT-RL-006: Assume v2+ firmware when detection fails
    /// All modern RileyLink/OrangeLink devices are v2+
    public static var assumeV2: RadioFirmwareVersion {
        return RadioFirmwareVersion(components: [2, 2], versionString: "assumed v2.2")
    }
    
    public var isUnknown: Bool {
        return self == RadioFirmwareVersion.unknown
    }
    
    public var description: String {
        return versionString
    }
    
    // Version capability checks
    private var atLeastV2: Bool {
        guard let major = components.first, major >= 2 else { return false }
        return true
    }
    
    private var atLeastV2_2: Bool {
        guard components.count >= 2 else { return false }
        let major = components[0]
        let minor = components[1]
        return major > 2 || (major == 2 && minor >= 2)
    }
    
    public var supportsPreambleExtension: Bool { atLeastV2 }
    public var supportsSoftwareEncoding: Bool { atLeastV2 }
    public var supportsResetRadioConfig: Bool { atLeastV2 }
    public var supports16BitPacketDelay: Bool { atLeastV2 }
    public var supportsCustomPreamble: Bool { atLeastV2 }
    public var supportsReadRegister: Bool { atLeastV2 }
    public var supportsRileyLinkStatistics: Bool { atLeastV2_2 }
    
    public var needsExtraByteForUpdateRegisterCommand: Bool { !atLeastV2 }
    
    public var needsExtraByteForReadRegisterCommand: Bool {
        guard components.count >= 2 else { return true }
        let major = components[0]
        let minor = components[1]
        return major < 2 || (major == 2 && minor <= 2)
    }
}

// MARK: - CC1110 Registers

/// CC1110 radio chip registers for frequency configuration
public enum CC111XRegister: UInt8, Sendable {
    case sync1    = 0x00
    case sync0    = 0x01
    case pktlen   = 0x02
    case pktctrl1 = 0x03
    case pktctrl0 = 0x04
    case fsctrl1  = 0x07
    case freq2    = 0x09
    case freq1    = 0x0A
    case freq0    = 0x0B
    case mdmcfg4  = 0x0C
    case mdmcfg3  = 0x0D
    case mdmcfg2  = 0x0E
    case mdmcfg1  = 0x0F
    case mdmcfg0  = 0x10
    case deviatn  = 0x11
    case mcsm0    = 0x14
    case foccfg   = 0x15
    case agcctrl2 = 0x17
    case agcctrl1 = 0x18
    case agcctrl0 = 0x19
    case frend1   = 0x1A
    case frend0   = 0x1B
    case fscal3   = 0x1C
    case fscal2   = 0x1D
    case fscal1   = 0x1E
    case fscal0   = 0x1F
    case test1    = 0x24
    case test0    = 0x25
    case paTable0 = 0x2E
}

// MARK: - Command Protocol

/// Protocol for RileyLink commands that serialize to Data
public protocol RileyLinkCommand: Sendable {
    var data: Data { get }
}

// MARK: - GetVersion Command

/// Get firmware version from RileyLink
public struct GetVersionCommand: RileyLinkCommand {
    public init() {}
    
    public var data: Data {
        Data([RileyLinkCommandCode.getVersion.rawValue])
    }
}

// MARK: - SendAndListen Command

/// Send RF packet and listen for response - the primary command for pump communication
///
/// ## Channel Semantics (RL-CHAN-006)
///
/// The RileyLink firmware supports multiple RF channels for different devices:
///
/// | Channel | Device Type | Notes |
/// |---------|-------------|-------|
/// | 0 | Medtronic pumps, meters, CGMs | **Use this for all Medtronic!** |
/// | 2 | Legacy/unused | Was incorrectly used, caused rxTimeout |
///
/// **IMPORTANT**: Loop uses channel 0 for ALL Medtronic pump communication.
/// The comment in Loop's Command.swift says "0 = meter, cgm. 2 = pump" but
/// their actual code uses channel 0 for pumps too. Using channel 2 causes
/// the pump to never respond (rxTimeout 0xAA).
///
/// Reference: `externals/rileylink_ios/RileyLinkBLEKit/Command.swift:75-76`
/// Fixed in: RL-CHAN-001, RL-CHAN-002
public struct SendAndListenCommand: RileyLinkCommand {
    public let outgoing: Data
    public let sendChannel: UInt8
    public let repeatCount: UInt8
    public let delayBetweenPacketsMS: UInt16
    public let listenChannel: UInt8
    public let timeoutMS: UInt32
    public let retryCount: UInt8
    public let preambleExtensionMS: UInt16
    public let firmwareVersion: RadioFirmwareVersion
    
    /// Create a SendAndListen command
    /// - Parameters:
    ///   - outgoing: RF packet data to send (already 4b6b encoded)
    ///   - sendChannel: Channel to send on (use 0 for Medtronic!)
    ///   - repeatCount: Number of times to repeat packet (0 = send once)
    ///   - delayBetweenPacketsMS: Delay between repeated packets
    ///   - listenChannel: Channel to listen on for response (use 0 for Medtronic!)
    ///   - timeoutMS: How long to listen for response
    ///   - retryCount: Number of send/listen cycles to attempt
    ///   - preambleExtensionMS: Extra preamble time (v2+ firmware)
    ///   - firmwareVersion: RileyLink firmware version for format selection
    public init(
        outgoing: Data,
        sendChannel: UInt8 = 0,  // RL-CHAN-001: Default to 0 for Medtronic
        repeatCount: UInt8 = 0,
        delayBetweenPacketsMS: UInt16 = 0,
        listenChannel: UInt8 = 0,  // RL-CHAN-002: Default to 0 for Medtronic
        timeoutMS: UInt32 = 500,
        retryCount: UInt8 = 3,
        preambleExtensionMS: UInt16 = 0,
        firmwareVersion: RadioFirmwareVersion = .unknown
    ) {
        self.outgoing = outgoing
        self.sendChannel = sendChannel
        self.repeatCount = repeatCount
        self.delayBetweenPacketsMS = delayBetweenPacketsMS
        self.listenChannel = listenChannel
        self.timeoutMS = timeoutMS
        self.retryCount = retryCount
        self.preambleExtensionMS = preambleExtensionMS
        self.firmwareVersion = firmwareVersion
    }
    
    public var data: Data {
        var result = Data([
            RileyLinkCommandCode.sendAndListen.rawValue,
            sendChannel,
            repeatCount
        ])
        
        // Firmware v2+ uses 16-bit delay, v1 uses 8-bit
        if firmwareVersion.supports16BitPacketDelay {
            result.append(contentsOf: delayBetweenPacketsMS.bigEndianBytes)
        } else {
            result.append(UInt8(clamping: Int(delayBetweenPacketsMS)))
        }
        
        result.append(listenChannel)
        result.append(contentsOf: timeoutMS.bigEndianBytes)
        result.append(retryCount)
        
        if firmwareVersion.supportsPreambleExtension {
            result.append(contentsOf: preambleExtensionMS.bigEndianBytes)
        }
        
        result.append(outgoing)
        
        return result
    }
}

// MARK: - UpdateRegister Command

/// Update a CC1110 radio register (for frequency tuning)
public struct UpdateRegisterCommand: RileyLinkCommand {
    public let register: CC111XRegister
    public let value: UInt8
    public let firmwareVersion: RadioFirmwareVersion
    
    public init(_ register: CC111XRegister, value: UInt8, firmwareVersion: RadioFirmwareVersion = .unknown) {
        self.register = register
        self.value = value
        self.firmwareVersion = firmwareVersion
    }
    
    public var data: Data {
        var result = Data([
            RileyLinkCommandCode.updateRegister.rawValue,
            register.rawValue,
            value
        ])
        
        if firmwareVersion.needsExtraByteForUpdateRegisterCommand {
            result.append(0)
        }
        
        return result
    }
}

// MARK: - SetSoftwareEncoding Command

/// Configure software encoding mode (4b6b for Medtronic)
public struct SetSoftwareEncodingCommand: RileyLinkCommand {
    public let encodingType: SoftwareEncodingType
    
    public init(_ encodingType: SoftwareEncodingType) {
        self.encodingType = encodingType
    }
    
    public var data: Data {
        Data([
            RileyLinkCommandCode.setSWEncoding.rawValue,
            encodingType.rawValue
        ])
    }
}

// MARK: - SetLEDMode Command

/// Set LED mode on RileyLink
public struct SetLEDModeCommand: RileyLinkCommand {
    public let led: RileyLinkLEDType
    public let mode: RileyLinkLEDMode
    
    public init(_ led: RileyLinkLEDType, mode: RileyLinkLEDMode) {
        self.led = led
        self.mode = mode
    }
    
    public var data: Data {
        Data([
            RileyLinkCommandCode.setLEDMode.rawValue,
            led.rawValue,
            mode.rawValue
        ])
    }
}

// MARK: - GetPacket Command

/// Listen for incoming RF packet (receive only, no transmit)
public struct GetPacketCommand: RileyLinkCommand {
    public let listenChannel: UInt8
    public let timeoutMS: UInt32
    
    public init(listenChannel: UInt8 = 2, timeoutMS: UInt32 = 500) {
        self.listenChannel = listenChannel
        self.timeoutMS = timeoutMS
    }
    
    public var data: Data {
        var result = Data([
            RileyLinkCommandCode.getPacket.rawValue,
            listenChannel
        ])
        result.append(contentsOf: timeoutMS.bigEndianBytes)
        return result
    }
}

// MARK: - ResetRadioConfig Command

/// Reset radio configuration to defaults
public struct ResetRadioConfigCommand: RileyLinkCommand {
    public init() {}
    
    public var data: Data {
        Data([RileyLinkCommandCode.resetRadioConfig.rawValue])
    }
}

// MARK: - Byte Helpers

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

// MARK: - Frequency Calculation

/// Calculate CC1110 frequency register values for a given MHz frequency
/// Reference: CC1110 datasheet, FREQ registers
public struct FrequencyRegisters: Sendable {
    public let freq2: UInt8
    public let freq1: UInt8
    public let freq0: UInt8
    
    /// Initialize from a frequency in MHz
    /// - Parameter mhz: Frequency in MHz (e.g., 916.5 for Medtronic US)
    public init(mhz: Double) {
        // CC1110 formula: freq = (FREQ[23:0] * 24MHz) / 2^16
        // So FREQ = (targetFreq * 2^16) / 24
        let freqValue = UInt32((mhz * Double(1 << 16)) / 24.0)
        
        self.freq2 = UInt8((freqValue >> 16) & 0xFF)
        self.freq1 = UInt8((freqValue >> 8) & 0xFF)
        self.freq0 = UInt8(freqValue & 0xFF)
    }
    
    /// Commands to set this frequency on RileyLink
    public func updateCommands(firmwareVersion: RadioFirmwareVersion = .unknown) -> [UpdateRegisterCommand] {
        [
            UpdateRegisterCommand(.freq2, value: freq2, firmwareVersion: firmwareVersion),
            UpdateRegisterCommand(.freq1, value: freq1, firmwareVersion: firmwareVersion),
            UpdateRegisterCommand(.freq0, value: freq0, firmwareVersion: firmwareVersion)
        ]
    }
}
