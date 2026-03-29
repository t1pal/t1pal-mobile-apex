// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicVariant.swift
// PumpKit
//
// Medtronic pump hardware variants with RF frequencies and model-specific features.
// Tracks verification status for each model/region combination.
// Trace: PUMP-MDT-003, PRD-005
//
// Usage:
//   let variant = MedtronicVariant.model722_NA
//   let frequency = variant.rfFrequency  // 916.5 MHz
//   let isVerified = MedtronicVariantRegistry.shared.status(variant)

import Foundation

// MARK: - Medtronic Hardware Generation

/// Medtronic pump hardware generations
public enum MedtronicGeneration: String, Codable, Sendable, CaseIterable {
    case paradigm = "paradigm"           // 5xx/7xx series
    case paradigmRevel = "paradigmRevel" // 523/723, MySentry
    case minimedG = "minimedG"           // 530G/730G, suspend on low
    case minimedX = "minimedX"           // 554/754
    case minimed6xx = "minimed6xx"       // 630G/670G (encrypted)
    case minimed7xx = "minimed7xx"       // 770G/780G (encrypted)
    
    public var displayName: String {
        switch self {
        case .paradigm: return "Paradigm"
        case .paradigmRevel: return "Paradigm Revel"
        case .minimedG: return "MiniMed G-Series"
        case .minimedX: return "MiniMed X-Series"
        case .minimed6xx: return "MiniMed 6xx"
        case .minimed7xx: return "MiniMed 7xx"
        }
    }
    
    /// Whether this generation uses encrypted RF communication
    public var isEncrypted: Bool {
        switch self {
        case .paradigm, .paradigmRevel, .minimedG, .minimedX:
            return false
        case .minimed6xx, .minimed7xx:
            return true
        }
    }
    
    /// Whether this generation is supported for DIY looping
    public var isLoopable: Bool {
        !isEncrypted
    }
}

// MARK: - Medtronic Variant

/// Complete Medtronic pump variant specification
public struct MedtronicVariant: Codable, Sendable, Hashable {
    public let model: MinimedPumpModel
    public let region: MinimedPumpRegion
    public let generation: MedtronicGeneration
    public let reservoirSize: ReservoirSize
    
    /// Unique identifier for this variant
    public var id: String {
        "\(model.rawValue)-\(region.rawValue)"
    }
    
    /// RF frequency for this region
    public var rfFrequency: Double {
        region.rfFrequency
    }
    
    /// Whether this variant supports MySentry CGM integration
    public var supportsMySentry: Bool {
        model.supportsMySentry
    }
    
    /// Reservoir capacity in units
    public var reservoirCapacity: Double {
        model.reservoirCapacity
    }
    
    /// Maximum basal rate (U/hr)
    public var maxBasalRate: Double {
        35.0 // Standard Medtronic max
    }
    
    /// Basal rate increment
    public var basalIncrement: Double {
        0.025 // 0.025 U/hr increments
    }
    
    /// Maximum bolus (units)
    public var maxBolus: Double {
        25.0 // Standard Medtronic max
    }
    
    /// Insulin bit packing scale for reservoir response parsing (RL-WIRE-012)
    /// Reference: Loop's PumpModel.insulinBitPackingScale
    /// Uses MinimedPumpModel.isPre523 to determine scale
    public var insulinBitPackingScale: Int {
        model.insulinBitPackingScale
    }
    
    /// Whether this is a "larger pump" (523/723 or newer) for history parsing
    /// Maps to MinimedHistoryParser's isLargerPump parameter
    /// Reference: Loop MinimedKit PumpModel.swift - generation >= 23
    public var isLargerPump: Bool {
        !model.isPre523
    }
    
    /// Display name
    public var displayName: String {
        "\(model.displayName) (\(region.rawValue))"
    }
    
    /// Whether this variant is supported for looping
    public var isSupported: Bool {
        generation.isLoopable
    }
    
    /// Reservoir size category
    public enum ReservoirSize: String, Codable, Sendable {
        case small = "small"   // 176 units (5xx models)
        case large = "large"   // 300 units (7xx models)
        
        public var capacity: Double {
            switch self {
            case .small: return 176
            case .large: return 300
            }
        }
    }
    
    public init(model: MinimedPumpModel, region: MinimedPumpRegion) {
        self.model = model
        self.region = region
        
        // Determine generation
        // EXT-MDT-005: Updated for new model cases and simpler logic
        switch model {
        case .model508, .model511, .model711, .model512, .model712, .model515, .model715, .model522, .model722:
            self.generation = .paradigm
        case .model523, .model723:
            self.generation = .paradigmRevel
        case .model530, .model730, .model540, .model740:
            self.generation = .minimedG
        case .model551, .model751, .model554, .model754:
            self.generation = .minimedX
        }
        
        // Determine reservoir size using model's computed property
        self.reservoirSize = model.reservoirCapacity > 200 ? .large : .small
    }
    
    // MARK: - Predefined Variants
    
    // Paradigm 522/722 - Most common Loop pumps
    public static let model522_NA = MedtronicVariant(model: .model522, region: .northAmerica)
    public static let model522_WW = MedtronicVariant(model: .model522, region: .worldWide)
    public static let model722_NA = MedtronicVariant(model: .model722, region: .northAmerica)
    public static let model722_WW = MedtronicVariant(model: .model722, region: .worldWide)
    
    // Paradigm Revel 523/723 - MySentry capable
    public static let model523_NA = MedtronicVariant(model: .model523, region: .northAmerica)
    public static let model523_WW = MedtronicVariant(model: .model523, region: .worldWide)
    public static let model723_NA = MedtronicVariant(model: .model723, region: .northAmerica)
    public static let model723_WW = MedtronicVariant(model: .model723, region: .worldWide)
    
    // MiniMed 530G/730G - Suspend on Low
    // EXT-MDT-005: Changed model530G -> model530 to match Loop
    public static let model530_NA = MedtronicVariant(model: .model530, region: .northAmerica)
    public static let model730_NA = MedtronicVariant(model: .model730, region: .northAmerica)
    
    // MiniMed 551/751 - Low suspend feature
    // EXT-MDT-005: Added missing models
    public static let model551_NA = MedtronicVariant(model: .model551, region: .northAmerica)
    public static let model751_NA = MedtronicVariant(model: .model751, region: .northAmerica)
    
    // MiniMed 554/754 - Newer firmware
    public static let model554_NA = MedtronicVariant(model: .model554, region: .northAmerica)
    public static let model754_NA = MedtronicVariant(model: .model754, region: .northAmerica)
    
    /// All predefined variants
    public static let allPredefined: [MedtronicVariant] = [
        .model522_NA, .model522_WW,
        .model722_NA, .model722_WW,
        .model523_NA, .model523_WW,
        .model723_NA, .model723_WW,
        .model530_NA, .model730_NA,
        .model551_NA, .model751_NA,
        .model554_NA, .model754_NA
    ]
}

// MARK: - Medtronic Variant Registry

/// Registry for tracking Medtronic variant verification status
public final class MedtronicVariantRegistry: @unchecked Sendable {
    public static let shared = MedtronicVariantRegistry()
    
    private let lock = NSLock()
    private var statuses: [String: VariantStatus] = [:]
    
    public enum VariantStatus: String, Codable, Sendable {
        case verified = "verified"           // Tested with real hardware
        case partiallyVerified = "partial"   // Some commands tested
        case communityReported = "community" // Reported working by community
        case untested = "untested"           // Not yet tested
        case knownIssues = "issues"          // Known problems
        case unsupported = "unsupported"     // Cannot work (encrypted)
        
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
        // Register default statuses based on Loop community experience
        registerDefaults()
    }
    
    private func registerDefaults() {
        // Most common Loop pumps - well verified
        register(.model522_NA, status: .verified)
        register(.model522_WW, status: .communityReported)
        register(.model722_NA, status: .verified)
        register(.model722_WW, status: .communityReported)
        
        // Revel series - verified
        register(.model523_NA, status: .verified)
        register(.model523_WW, status: .communityReported)
        register(.model723_NA, status: .verified)
        register(.model723_WW, status: .communityReported)
        
        // G-series - partially verified
        register(.model530_NA, status: .partiallyVerified)
        register(.model730_NA, status: .partiallyVerified)
        
        // 551/751 - has low suspend, partially verified
        register(.model551_NA, status: .partiallyVerified)
        register(.model751_NA, status: .partiallyVerified)
        
        // X-series - known issues with some commands
        register(.model554_NA, status: .knownIssues)
        register(.model754_NA, status: .knownIssues)
    }
    
    public func register(_ variant: MedtronicVariant, status: VariantStatus) {
        lock.lock()
        defer { lock.unlock() }
        statuses[variant.id] = status
    }
    
    public func status(_ variant: MedtronicVariant) -> VariantStatus {
        lock.lock()
        defer { lock.unlock() }
        return statuses[variant.id] ?? .untested
    }
    
    public func allStatuses() -> [(MedtronicVariant, VariantStatus)] {
        lock.lock()
        defer { lock.unlock() }
        return MedtronicVariant.allPredefined.map { variant in
            (variant, statuses[variant.id] ?? .untested)
        }
    }
    
    /// All variants in registry
    public var allVariants: [MedtronicVariant] {
        MedtronicVariant.allPredefined
    }
    
    /// Supported variants (isLoopable generation)
    public var supportedVariants: [MedtronicVariant] {
        allVariants.filter { $0.isSupported }
    }
    
    /// Lookup variant by model number string
    public func variant(forModel modelNumber: String) -> MedtronicVariant? {
        // Try to find matching model
        for variant in allVariants {
            if variant.model.rawValue.contains(modelNumber) {
                return variant
            }
        }
        return nil
    }
    
    /// Static accessor for backwards compatibility
    public static var allVariants: [MedtronicVariant] {
        shared.allVariants
    }
    
    /// Static accessor for backwards compatibility
    public static var supportedVariants: [MedtronicVariant] {
        shared.supportedVariants
    }
    
    /// Static lookup for backwards compatibility
    public static func variant(forModel modelNumber: String) -> MedtronicVariant? {
        shared.variant(forModel: modelNumber)
    }
}

// MARK: - RF Frequency Constants

/// RF frequency constants for Medtronic pumps
public struct MedtronicRFConstants {
    /// North America frequency (916.5 MHz)
    public static let frequencyNA: Double = 916.5
    
    /// Worldwide frequency (868.35 MHz)
    public static let frequencyWW: Double = 868.35
    
    /// Frequency tolerance for tuning (±0.3 MHz)
    public static let frequencyTolerance: Double = 0.3
    
    /// Preamble bytes for wake-up
    public static let wakeupPreamble = Data([0xA5, 0x5A, 0xA5, 0x5A, 0xA5])
    
    /// Sync word
    public static let syncWord = Data([0xA9, 0x65])
    
    /// CRC polynomial (0x9B, NOT 0x31 which is CRC-8/MAXIM)
    /// Bug fix: EXT-MDT-004 - was using wrong polynomial 0x31
    /// Source: externals/MinimedKit/MinimedKit/Radio/CRC8.swift:11
    public static let crcPolynomial: UInt8 = 0x9B
    
    /// CRC-8 lookup table (polynomial 0x9B)
    /// Source: externals/MinimedKit/MinimedKit/Radio/CRC8.swift:11
    private static let crcTable: [UInt8] = [
        0x00, 0x9B, 0xAD, 0x36, 0xC1, 0x5A, 0x6C, 0xF7, 0x19, 0x82, 0xB4, 0x2F, 0xD8, 0x43, 0x75, 0xEE,
        0x32, 0xA9, 0x9F, 0x04, 0xF3, 0x68, 0x5E, 0xC5, 0x2B, 0xB0, 0x86, 0x1D, 0xEA, 0x71, 0x47, 0xDC,
        0x64, 0xFF, 0xC9, 0x52, 0xA5, 0x3E, 0x08, 0x93, 0x7D, 0xE6, 0xD0, 0x4B, 0xBC, 0x27, 0x11, 0x8A,
        0x56, 0xCD, 0xFB, 0x60, 0x97, 0x0C, 0x3A, 0xA1, 0x4F, 0xD4, 0xE2, 0x79, 0x8E, 0x15, 0x23, 0xB8,
        0xC8, 0x53, 0x65, 0xFE, 0x09, 0x92, 0xA4, 0x3F, 0xD1, 0x4A, 0x7C, 0xE7, 0x10, 0x8B, 0xBD, 0x26,
        0xFA, 0x61, 0x57, 0xCC, 0x3B, 0xA0, 0x96, 0x0D, 0xE3, 0x78, 0x4E, 0xD5, 0x22, 0xB9, 0x8F, 0x14,
        0xAC, 0x37, 0x01, 0x9A, 0x6D, 0xF6, 0xC0, 0x5B, 0xB5, 0x2E, 0x18, 0x83, 0x74, 0xEF, 0xD9, 0x42,
        0x9E, 0x05, 0x33, 0xA8, 0x5F, 0xC4, 0xF2, 0x69, 0x87, 0x1C, 0x2A, 0xB1, 0x46, 0xDD, 0xEB, 0x70,
        0x0B, 0x90, 0xA6, 0x3D, 0xCA, 0x51, 0x67, 0xFC, 0x12, 0x89, 0xBF, 0x24, 0xD3, 0x48, 0x7E, 0xE5,
        0x39, 0xA2, 0x94, 0x0F, 0xF8, 0x63, 0x55, 0xCE, 0x20, 0xBB, 0x8D, 0x16, 0xE1, 0x7A, 0x4C, 0xD7,
        0x6F, 0xF4, 0xC2, 0x59, 0xAE, 0x35, 0x03, 0x98, 0x76, 0xED, 0xDB, 0x40, 0xB7, 0x2C, 0x1A, 0x81,
        0x5D, 0xC6, 0xF0, 0x6B, 0x9C, 0x07, 0x31, 0xAA, 0x44, 0xDF, 0xE9, 0x72, 0x85, 0x1E, 0x28, 0xB3,
        0xC3, 0x58, 0x6E, 0xF5, 0x02, 0x99, 0xAF, 0x34, 0xDA, 0x41, 0x77, 0xEC, 0x1B, 0x80, 0xB6, 0x2D,
        0xF1, 0x6A, 0x5C, 0xC7, 0x30, 0xAB, 0x9D, 0x06, 0xE8, 0x73, 0x45, 0xDE, 0x29, 0xB2, 0x84, 0x1F,
        0xA7, 0x3C, 0x0A, 0x91, 0x66, 0xFD, 0xCB, 0x50, 0xBE, 0x25, 0x13, 0x88, 0x7F, 0xE4, 0xD2, 0x49,
        0x95, 0x0E, 0x38, 0xA3, 0x54, 0xCF, 0xF9, 0x62, 0x8C, 0x17, 0x21, 0xBA, 0x4D, 0xD6, 0xE0, 0x7B
    ]
}

// MARK: - CRC Calculation

extension MedtronicRFConstants {
    /// Calculate CRC-8 checksum using table lookup (polynomial 0x9B)
    /// Bug fix: EXT-MDT-004 - was using wrong polynomial 0x31, now matches Loop
    /// Source: externals/MinimedKit/MinimedKit/Radio/CRC8.swift:13-22
    public static func crc8(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc = crcTable[Int((crc ^ byte) & 0xFF)]
        }
        return crc
    }
    
    /// Validate CRC-8 checksum
    public static func validateCRC(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let payload = data.dropLast()
        let expectedCRC = data.last!
        return crc8(Data(payload)) == expectedCRC
    }
}
