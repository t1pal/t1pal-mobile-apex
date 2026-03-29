// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaVariant.swift
// PumpKit
//
// Dana pump hardware variants (Dana-R, Dana-RS, Dana-i) with protocol differences.
// Tracks encryption types, hardware models, and verification status.
// Trace: PUMP-DANA-002, PRD-005
//
// Usage:
//   let variant = DanaVariant.danaI
//   let encryption = variant.encryptionType  // .ble5
//   let status = DanaVariantRegistry.shared.status(variant)

import Foundation

// MARK: - Dana Hardware Generation

/// Dana pump hardware generations
public enum DanaGeneration: String, Codable, Sendable, CaseIterable {
    case danaR = "danaR"       // Original, Bluetooth Classic
    case danaRS = "danaRS"     // BLE, RSv3 encryption
    case danaI = "danaI"       // BLE 5.0, enhanced encryption
    
    public var displayName: String {
        switch self {
        case .danaR: return "Dana-R"
        case .danaRS: return "Dana-RS"
        case .danaI: return "Dana-i"
        }
    }
    
    /// Communication type
    public var communicationType: DanaCommunicationType {
        switch self {
        case .danaR: return .bluetoothClassic
        case .danaRS, .danaI: return .bluetoothLE
        }
    }
    
    /// Encryption type used
    public var encryptionType: DanaEncryptionType {
        switch self {
        case .danaR: return .legacy
        case .danaRS: return .rsv3
        case .danaI: return .ble5
        }
    }
    
    /// Whether this generation is supported for DIY looping
    public var isLoopable: Bool {
        true // All Dana variants can be looped
    }
    
    /// Minimum hardware model for 24-hour profiles
    public var supports24HourProfiles: Bool {
        // hwModel >= 7 supports 24-hour profiles
        switch self {
        case .danaR: return false
        case .danaRS, .danaI: return true
        }
    }
}

// MARK: - Communication Type

/// Dana communication methods
public enum DanaCommunicationType: String, Codable, Sendable {
    case bluetoothClassic = "BT"    // Classic Bluetooth (Dana-R)
    case bluetoothLE = "BLE"        // Bluetooth Low Energy
    
    public var icon: String {
        switch self {
        case .bluetoothClassic: return "dot.radiowaves.left.and.right"
        case .bluetoothLE: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Encryption Type

/// Dana encryption types
public enum DanaEncryptionType: String, Codable, Sendable {
    case legacy = "ENCRYPTION_DEFAULT"   // Dana-R legacy
    case rsv3 = "ENCRYPTION_RSv3"        // Dana-RS v3
    case ble5 = "ENCRYPTION_BLE5"        // Dana-i BLE 5.0
    
    public var displayName: String {
        switch self {
        case .legacy: return "Legacy"
        case .rsv3: return "RS v3"
        case .ble5: return "BLE 5.0"
        }
    }
}

// MARK: - Dana Variant

/// Complete Dana pump variant specification
public struct DanaVariant: Codable, Sendable, Hashable {
    public let generation: DanaGeneration
    public let region: DanaRegion
    public let hardwareModel: Int?
    
    /// Unique identifier for this variant
    public var id: String {
        "\(generation.rawValue)-\(region.rawValue)"
    }
    
    /// Display name
    public var displayName: String {
        "\(generation.displayName) (\(region.displayName))"
    }
    
    /// Communication type
    public var communicationType: DanaCommunicationType {
        generation.communicationType
    }
    
    /// Encryption type
    public var encryptionType: DanaEncryptionType {
        generation.encryptionType
    }
    
    /// Whether this variant is supported for looping
    public var isSupported: Bool {
        generation.isLoopable
    }
    
    /// Whether 24-hour profiles are supported
    public var supports24HourProfiles: Bool {
        if let hwModel = hardwareModel {
            return hwModel >= 7
        }
        return generation.supports24HourProfiles
    }
    
    /// Whether UTC time is used
    public var usesUTC: Bool {
        supports24HourProfiles
    }
    
    /// Reservoir capacity in units
    public var reservoirCapacity: Double {
        300.0 // All Dana variants have 300U reservoir
    }
    
    /// Minimum bolus increment
    public var bolusIncrement: Double {
        0.05 // 0.05U increments
    }
    
    /// Minimum basal rate increment
    public var basalIncrement: Double {
        0.01 // 0.01U/hr increments
    }
    
    /// Temp basal style (percent-based)
    public var tempBasalStyle: DanaTempBasalStyle {
        .percent // Dana uses percent-based temp basal (0-200%)
    }
    
    /// Maximum temp basal percent
    public var maxTempBasalPercent: Int {
        200
    }
    
    public init(generation: DanaGeneration, region: DanaRegion = .korea, hardwareModel: Int? = nil) {
        self.generation = generation
        self.region = region
        self.hardwareModel = hardwareModel
    }
    
    // MARK: - Predefined Variants
    
    // Dana-R (legacy)
    public static let danaR_KR = DanaVariant(generation: .danaR, region: .korea)
    public static let danaR_INT = DanaVariant(generation: .danaR, region: .international)
    
    // Dana-RS
    public static let danaRS_KR = DanaVariant(generation: .danaRS, region: .korea)
    public static let danaRS_INT = DanaVariant(generation: .danaRS, region: .international)
    
    // Dana-i
    public static let danaI_KR = DanaVariant(generation: .danaI, region: .korea)
    public static let danaI_INT = DanaVariant(generation: .danaI, region: .international)
    
    /// Convenience aliases
    public static let danaR = danaR_INT
    public static let danaRS = danaRS_INT
    public static let danaI = danaI_INT
    
    /// All predefined variants
    public static let allPredefined: [DanaVariant] = [
        .danaR_KR, .danaR_INT,
        .danaRS_KR, .danaRS_INT,
        .danaI_KR, .danaI_INT
    ]
}

// MARK: - Dana Region

/// Regional variants of Dana pumps
public enum DanaRegion: String, Codable, Sendable, CaseIterable {
    case korea = "KR"
    case international = "INT"
    
    public var displayName: String {
        switch self {
        case .korea: return "Korea"
        case .international: return "International"
        }
    }
}

// MARK: - Temp Basal Style

/// Dana temp basal style
public enum DanaTempBasalStyle: String, Codable, Sendable {
    case percent = "percent"  // 0-200% of scheduled basal
    case absolute = "absolute" // Absolute rate (not used by Dana)
}

// MARK: - Dana Variant Registry

/// Registry for tracking Dana variant verification status
public final class DanaVariantRegistry: @unchecked Sendable {
    public static let shared = DanaVariantRegistry()
    
    private let lock = NSLock()
    private var statuses: [String: VariantStatus] = [:]
    
    public enum VariantStatus: String, Codable, Sendable {
        case verified = "verified"           // Tested with real hardware
        case partiallyVerified = "partial"   // Some commands tested
        case communityReported = "community" // Reported working by community
        case untested = "untested"           // Not yet tested
        case knownIssues = "issues"          // Known problems
        case unsupported = "unsupported"     // Cannot work
        
        public var emoji: String {
            switch self {
            case .verified: return "✅"
            case .partiallyVerified: return "🟡"
            case .communityReported: return "🔵"
            case .untested: return "❓"
            case .knownIssues: return "⚠️"
            case .unsupported: return "❌"
            }
        }
    }
    
    private init() {
        registerDefaults()
    }
    
    private func registerDefaults() {
        // Dana-R - older, less tested in Loop community
        register(.danaR_KR, status: .communityReported)
        register(.danaR_INT, status: .partiallyVerified)
        
        // Dana-RS - well tested in AAPS
        register(.danaRS_KR, status: .verified)
        register(.danaRS_INT, status: .verified)
        
        // Dana-i - newer, AAPS verified
        register(.danaI_KR, status: .verified)
        register(.danaI_INT, status: .verified)
    }
    
    public func register(_ variant: DanaVariant, status: VariantStatus) {
        lock.lock()
        defer { lock.unlock() }
        statuses[variant.id] = status
    }
    
    public func status(_ variant: DanaVariant) -> VariantStatus {
        lock.lock()
        defer { lock.unlock() }
        return statuses[variant.id] ?? .untested
    }
    
    public func allStatuses() -> [(DanaVariant, VariantStatus)] {
        lock.lock()
        defer { lock.unlock() }
        return DanaVariant.allPredefined.map { variant in
            (variant, statuses[variant.id] ?? .untested)
        }
    }
    
    /// All variants in registry
    public var allVariants: [DanaVariant] {
        DanaVariant.allPredefined
    }
    
    /// Supported variants
    public var supportedVariants: [DanaVariant] {
        allVariants.filter { $0.isSupported }
    }
    
    /// Static accessors
    public static var allVariants: [DanaVariant] {
        shared.allVariants
    }
    
    public static var supportedVariants: [DanaVariant] {
        shared.supportedVariants
    }
}

// MARK: - BLE Constants

/// BLE constants for Dana-RS/i communication
/// Source: Trio/DanaKit/PumpManager/PeripheralManager.swift:24-27
public struct DanaBLEConstants {
    /// Dana service UUID
    public static let serviceUUID = "0000FFF0-0000-1000-8000-00805F9B34FB"
    
    /// Write characteristic UUID (FFF2 per DanaKit WRITE_CHAR_UUID)
    public static let writeCharacteristicUUID = "0000FFF2-0000-1000-8000-00805F9B34FB"
    
    /// Notify/Read characteristic UUID (FFF1 per DanaKit READ_CHAR_UUID)
    public static let notifyCharacteristicUUID = "0000FFF1-0000-1000-8000-00805F9B34FB"
    
    /// Connection timeout in seconds
    public static let connectionTimeoutSeconds: TimeInterval = 10.0
    
    /// Command timeout in seconds
    public static let commandTimeoutSeconds: TimeInterval = 5.0
    
    /// Packet start bytes
    public static let packetStart = Data([0xA5, 0xA5])
    
    /// Packet end bytes
    public static let packetEnd = Data([0x5A, 0x5A])
}

// MARK: - Message Types

/// Dana message type categories
public enum DanaMessageType: UInt8, Codable, Sendable {
    case encryption = 0xA0    // Encryption/pairing
    case general = 0x01       // General status
    case basal = 0x02         // Basal operations
    case bolus = 0x03         // Bolus operations
    case option = 0x04        // Settings/options
    case etc = 0x05           // ETC (suspend/resume, history)
    case notify = 0x0F        // Notifications
    
    public var displayName: String {
        switch self {
        case .encryption: return "Encryption"
        case .general: return "General"
        case .basal: return "Basal"
        case .bolus: return "Bolus"
        case .option: return "Option"
        case .etc: return "ETC"
        case .notify: return "Notify"
        }
    }
}

// MARK: - Packet Types

/// Dana packet type identifiers for BLE framing.
/// Source: Trio/DanaKit/Packets/DanaPacketType.swift:10-14
public enum DanaPacketType: UInt8, Codable, Sendable {
    case encryptionRequest = 0x01   // TYPE_ENCRYPTION_REQUEST
    case encryptionResponse = 0x02  // TYPE_ENCRYPTION_RESPONSE
    case command = 0xA1             // TYPE_COMMAND
    case response = 0xB2            // TYPE_RESPONSE
    case notify = 0xC3              // TYPE_NOTIFY
    
    public var displayName: String {
        switch self {
        case .encryptionRequest: return "Encryption Request"
        case .encryptionResponse: return "Encryption Response"
        case .command: return "Command"
        case .response: return "Response"
        case .notify: return "Notify"
        }
    }
}

// MARK: - Error States

/// Dana pump error states
public enum DanaErrorState: String, Codable, Sendable, CaseIterable {
    case none = "NONE"
    case suspended = "SUSPENDED"
    case dailyMax = "DAILY_MAX"
    case bolusBlock = "BOLUS_BLOCK"
    case orderDelivering = "ORDER_DELIVERING"
    case noPrime = "NO_PRIME"
    
    public var displayName: String {
        switch self {
        case .none: return "No Error"
        case .suspended: return "Suspended"
        case .dailyMax: return "Daily Max Reached"
        case .bolusBlock: return "Bolus Blocked"
        case .orderDelivering: return "Order Delivering"
        case .noPrime: return "Not Primed"
        }
    }
    
    public var canDeliver: Bool {
        self == .none
    }
    
    public var icon: String {
        switch self {
        case .none: return "checkmark.circle"
        case .suspended: return "pause.circle"
        case .dailyMax: return "exclamationmark.triangle"
        case .bolusBlock: return "xmark.octagon"
        case .orderDelivering: return "arrow.clockwise"
        case .noPrime: return "drop.triangle"
        }
    }
}
