// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodVariant.swift
// PumpKit
//
// Omnipod pump hardware variants (Eros vs DASH) with protocol differences.
// Tracks verification status for each variant and communication method.
// Trace: PUMP-OMNI-003, PRD-005
//
// Usage:
//   let variant = OmnipodVariant.dash
//   let requiresBridge = variant.requiresRFBridge  // false for DASH
//   let status = OmnipodVariantRegistry.shared.status(variant)

import Foundation

// MARK: - Omnipod Hardware Generation

/// Omnipod pump hardware generations
public enum OmnipodGeneration: String, Codable, Sendable, CaseIterable {
    case eros = "eros"       // Classic Omnipod (RF, needs RileyLink)
    case dash = "dash"       // Omnipod DASH (Bluetooth LE)
    case five = "five"       // Omnipod 5 (closed-loop with Dexcom)
    
    public var displayName: String {
        switch self {
        case .eros: return "Omnipod (Eros)"
        case .dash: return "Omnipod DASH"
        case .five: return "Omnipod 5"
        }
    }
    
    /// Whether this generation requires an RF bridge device
    public var requiresRFBridge: Bool {
        switch self {
        case .eros: return true
        case .dash, .five: return false
        }
    }
    
    /// Communication method
    public var communicationType: OmnipodCommunicationType {
        switch self {
        case .eros: return .rf433
        case .dash, .five: return .bluetoothLE
        }
    }
    
    /// Whether this generation is supported for DIY looping
    public var isLoopable: Bool {
        switch self {
        case .eros, .dash: return true
        case .five: return false // Closed system
        }
    }
}

// MARK: - DASH BLE Constants

/// Omnipod DASH BLE service and characteristic UUIDs
/// Source: DASH-AUDIT-001, externals/OmniBLE
public enum DASHBLEConstants {
    /// Advertisement service UUID (scan filter)
    public static let advertisementUUID = "00004024-0000-1000-8000-00805f9b34fb"
    /// Short advertisement UUID
    public static let advertisementShortUUID = "4024"
    
    /// Main GATT service UUID
    public static let serviceUUID = "1A7E4024-E3ED-4464-8B7E-751E03D0DC5F"
    
    /// Command characteristic - flow control (RTS/CTS/SUCCESS/etc.)
    public static let commandCharacteristicUUID = "1A7E2441-E3ED-4464-8B7E-751E03D0DC5F"
    
    /// Data characteristic - message payload packets
    public static let dataCharacteristicUUID = "1A7E2442-E3ED-4464-8B7E-751E03D0DC5F"
}

/// DASH flow control commands
public enum DASHFlowCommand: UInt8, Sendable {
    case rts = 0x00      // Request to send
    case cts = 0x01      // Clear to send
    case nack = 0x02     // Negative acknowledgment
    case abort = 0x03    // Abort transfer
    case success = 0x04  // Transfer complete
    case fail = 0x05     // Transfer failed
    case hello = 0x06    // Initial handshake
    case incorrect = 0x09 // Incorrect sequence
    
    public var displayName: String {
        switch self {
        case .rts: return "RTS"
        case .cts: return "CTS"
        case .nack: return "NACK"
        case .abort: return "ABORT"
        case .success: return "SUCCESS"
        case .fail: return "FAIL"
        case .hello: return "HELLO"
        case .incorrect: return "INCORRECT"
        }
    }
}

// MARK: - Communication Type

/// Omnipod communication methods
public enum OmnipodCommunicationType: String, Codable, Sendable {
    case rf433 = "RF433"        // 433 MHz radio (via RileyLink)
    case bluetoothLE = "BLE"    // Bluetooth Low Energy (direct)
    
    public var icon: String {
        switch self {
        case .rf433: return "antenna.radiowaves.left.and.right"
        case .bluetoothLE: return "antenna.radiowaves.left.and.right.circle"
        }
    }
}

// MARK: - Omnipod Variant

/// Complete Omnipod pump variant specification
public struct OmnipodVariant: Codable, Sendable, Hashable {
    public let generation: OmnipodGeneration
    public let region: OmnipodRegion
    
    /// Unique identifier for this variant
    public var id: String {
        "\(generation.rawValue)-\(region.rawValue)"
    }
    
    /// Display name
    public var displayName: String {
        "\(generation.displayName) (\(region.displayName))"
    }
    
    /// Whether this variant requires an RF bridge
    public var requiresRFBridge: Bool {
        generation.requiresRFBridge
    }
    
    /// Communication type for this variant
    public var communicationType: OmnipodCommunicationType {
        generation.communicationType
    }
    
    /// Whether this variant is supported for looping
    public var isSupported: Bool {
        generation.isLoopable
    }
    
    /// RF frequency (only for Eros)
    public var rfFrequency: Double? {
        guard generation == .eros else { return nil }
        return OmnipodRFConstants.frequency
    }
    
    /// Pod lifetime in hours
    public var podLifetimeHours: Double {
        72.0 // All variants have 72-hour nominal lifetime
    }
    
    /// Pod expiration warning (hours before expiration)
    public var expirationWarningHours: Double {
        8.0 // 8-hour warning = 80-hour total
    }
    
    /// Reservoir capacity in units
    public var reservoirCapacity: Double {
        200.0 // All variants have 200U reservoir
    }
    
    /// Minimum bolus increment
    public var bolusIncrement: Double {
        0.05 // All variants: 0.05U increments
    }
    
    /// Minimum basal rate increment
    public var basalIncrement: Double {
        0.05 // All variants: 0.05U/hr increments
    }
    
    public init(generation: OmnipodGeneration, region: OmnipodRegion = .usa) {
        self.generation = generation
        self.region = region
    }
    
    // MARK: - Predefined Variants
    
    // Eros (Classic)
    public static let eros_USA = OmnipodVariant(generation: .eros, region: .usa)
    public static let eros_EU = OmnipodVariant(generation: .eros, region: .europe)
    public static let eros_CA = OmnipodVariant(generation: .eros, region: .canada)
    
    // DASH
    public static let dash_USA = OmnipodVariant(generation: .dash, region: .usa)
    public static let dash_EU = OmnipodVariant(generation: .dash, region: .europe)
    public static let dash_CA = OmnipodVariant(generation: .dash, region: .canada)
    
    // Omnipod 5 (not loopable, but tracked for completeness)
    public static let five_USA = OmnipodVariant(generation: .five, region: .usa)
    
    /// Convenience aliases
    public static let eros = eros_USA
    public static let dash = dash_USA
    
    /// All predefined variants
    public static let allPredefined: [OmnipodVariant] = [
        .eros_USA, .eros_EU, .eros_CA,
        .dash_USA, .dash_EU, .dash_CA,
        .five_USA
    ]
    
    /// Loopable variants only
    public static let loopableVariants: [OmnipodVariant] = allPredefined.filter { $0.isSupported }
}

// MARK: - Omnipod Region

/// Regional variants of Omnipod pods
public enum OmnipodRegion: String, Codable, Sendable, CaseIterable {
    case usa = "USA"
    case europe = "EU"
    case canada = "CA"
    case australia = "AU"
    
    public var displayName: String {
        switch self {
        case .usa: return "United States"
        case .europe: return "Europe"
        case .canada: return "Canada"
        case .australia: return "Australia"
        }
    }
}

// MARK: - Omnipod Variant Registry

/// Registry for tracking Omnipod variant verification status
public final class OmnipodVariantRegistry: @unchecked Sendable {
    public static let shared = OmnipodVariantRegistry()
    
    private let lock = NSLock()
    private var statuses: [String: VariantStatus] = [:]
    
    public enum VariantStatus: String, Codable, Sendable {
        case verified = "verified"           // Tested with real hardware
        case partiallyVerified = "partial"   // Some commands tested
        case communityReported = "community" // Reported working by community
        case untested = "untested"           // Not yet tested
        case knownIssues = "issues"          // Known problems
        case unsupported = "unsupported"     // Cannot work (closed system)
        
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
        // Eros - well verified in Loop community
        register(.eros_USA, status: .verified)
        register(.eros_EU, status: .communityReported)
        register(.eros_CA, status: .communityReported)
        
        // DASH - verified in Loop community
        register(.dash_USA, status: .verified)
        register(.dash_EU, status: .communityReported)
        register(.dash_CA, status: .communityReported)
        
        // Omnipod 5 - closed system, not loopable
        register(.five_USA, status: .unsupported)
    }
    
    public func register(_ variant: OmnipodVariant, status: VariantStatus) {
        lock.lock()
        defer { lock.unlock() }
        statuses[variant.id] = status
    }
    
    public func status(_ variant: OmnipodVariant) -> VariantStatus {
        lock.lock()
        defer { lock.unlock() }
        return statuses[variant.id] ?? .untested
    }
    
    public func allStatuses() -> [(OmnipodVariant, VariantStatus)] {
        lock.lock()
        defer { lock.unlock() }
        return OmnipodVariant.allPredefined.map { variant in
            (variant, statuses[variant.id] ?? .untested)
        }
    }
    
    /// All variants in registry
    public var allVariants: [OmnipodVariant] {
        OmnipodVariant.allPredefined
    }
    
    /// Supported variants (loopable)
    public var supportedVariants: [OmnipodVariant] {
        allVariants.filter { $0.isSupported }
    }
    
    /// Static accessors for backwards compatibility
    public static var allVariants: [OmnipodVariant] {
        shared.allVariants
    }
    
    public static var supportedVariants: [OmnipodVariant] {
        shared.supportedVariants
    }
}

// MARK: - RF Constants (Eros)

/// RF constants for Omnipod Eros communication
public struct OmnipodRFConstants {
    /// Eros RF frequency (433.91 MHz worldwide)
    public static let frequency: Double = 433.91
    
    /// Frequency tolerance for tuning
    public static let frequencyTolerance: Double = 0.05
    
    /// Packet timeout in milliseconds
    public static let packetTimeoutMs: Int = 30
    
    /// Command retry count
    public static let maxRetries: Int = 3
    
    /// Pod response window in milliseconds
    public static let responseWindowMs: Int = 300
    
    /// Preamble bytes
    public static let preamble = Data([0xAA, 0xAA, 0xAA])
    
    /// Sync word for packet framing
    public static let syncWord = Data([0x54, 0xC3])
}

// MARK: - BLE Constants (DASH)

/// BLE constants for Omnipod DASH communication
/// Source: externals/OmniBLE/OmniBLE/Bluetooth/BluetoothServices.swift
public struct OmnipodBLEConstants {
    // MARK: - Session IDs
    // Source: externals/OmniBLE/OmniBLE/Bluetooth/Ids.swift
    
    /// Fixed controller ID used by AAPS/OmniBLE
    /// Source: Ids.swift:11
    public static let controllerId: UInt32 = 0x1092  // 4242 decimal
    
    /// Sentinel value for pod ID when not yet activated
    /// Source: Ids.swift:12
    public static let podIdNotActivated: UInt32 = 0xFFFFFFFE
    
    // MARK: - BLE UUIDs
    
    /// DASH advertisement UUID (for scanning/filtering)
    /// Source: BluetoothServices.swift:30
    public static let advertisementUUID = "00004024-0000-1000-8000-00805F9B34FB"
    
    /// DASH service UUID (primary GATT service)
    /// Source: BluetoothServices.swift:31
    public static let serviceUUID = "1A7E4024-E3ED-4464-8B7E-751E03D0DC5F"
    
    /// Command characteristic UUID (write/notify for commands)
    /// Source: BluetoothServices.swift:35
    public static let commandCharacteristicUUID = "1A7E2441-E3ED-4464-8B7E-751E03D0DC5F"
    
    /// Data characteristic UUID (write/notify for data)
    /// Source: BluetoothServices.swift:36
    public static let dataCharacteristicUUID = "1A7E2442-E3ED-4464-8B7E-751E03D0DC5F"
    
    /// Connection timeout in seconds
    public static let connectionTimeoutSeconds: TimeInterval = 10.0
    
    /// Command timeout in seconds
    public static let commandTimeoutSeconds: TimeInterval = 5.0
    
    /// Session idle timeout in seconds
    public static let sessionIdleTimeoutSeconds: TimeInterval = 30.0
    
    /// Pod ID prefix in advertisement name
    public static let advertisementPrefix = "TWI BOARD"
    
    // MARK: - BLE Command Opcodes (Layer 2)
    
    /// Pod BLE-layer command opcodes
    /// Source: BluetoothServices.swift:18-27
    public enum PodBLECommand: UInt8 {
        case RTS = 0x00       // Request to Send
        case CTS = 0x01       // Clear to Send
        case NACK = 0x02      // Negative Acknowledgment
        case ABORT = 0x03     // Abort
        case SUCCESS = 0x04   // Success
        case FAIL = 0x05      // Failure
        case HELLO = 0x06     // Hello/Handshake
        case INCORRECT = 0x09 // Incorrect
    }
}

// MARK: - Pod Fault Codes

/// Omnipod pod fault codes (shared between Eros and DASH)
public enum OmnipodFaultCode: UInt8, Codable, Sendable, CaseIterable {
    case none = 0x00
    case podExpired = 0x10
    case occlusionDetected = 0x14
    case maxDeliveryExceeded = 0x18
    case podFault = 0x1C
    case internalError = 0x28
    case faultedInUse = 0x34
    
    public var displayName: String {
        switch self {
        case .none: return "No Fault"
        case .podExpired: return "Pod Expired"
        case .occlusionDetected: return "Occlusion Detected"
        case .maxDeliveryExceeded: return "Max Delivery Exceeded"
        case .podFault: return "Pod Fault"
        case .internalError: return "Internal Error"
        case .faultedInUse: return "Faulted In Use"
        }
    }
    
    public var requiresDeactivation: Bool {
        self != .none
    }
    
    public var icon: String {
        switch self {
        case .none: return "checkmark.circle"
        case .podExpired: return "clock.badge.exclamationmark"
        case .occlusionDetected: return "exclamationmark.octagon"
        case .maxDeliveryExceeded: return "drop.triangle"
        case .podFault, .internalError, .faultedInUse: return "xmark.octagon"
        }
    }
}
