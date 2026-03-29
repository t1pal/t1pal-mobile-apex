// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpConnectionVariantRegistry.swift
// PumpKit
//
// Registry of pump connection variants and hardware configurations.
// Tracks different hardware paths (BLE direct, RileyLink, OrangeLink, etc.)
// Trace: PUMP-INFRA-002, PRD-005
//
// This enables systematic tracking of which hardware combinations work
// for pump communication, supporting protocol uncertainty documentation.

import Foundation

// MARK: - Connection Medium

/// Physical connection medium to pump
public enum PumpConnectionMedium: String, Codable, Sendable, CaseIterable {
    case bleDirect = "ble_direct"           // Direct BLE to pump (Omnipod DASH, Dana)
    case rileyLink = "rileylink"             // RileyLink RF bridge (916.5/868.35 MHz)
    case orangeLink = "orangelink"           // OrangeLink RF bridge
    case emaLink = "emalink"                 // EmaLink RF bridge
    case simulation = "simulation"           // Software simulation
    
    public var displayName: String {
        switch self {
        case .bleDirect: return "BLE Direct"
        case .rileyLink: return "RileyLink"
        case .orangeLink: return "OrangeLink"
        case .emaLink: return "EmaLink"
        case .simulation: return "Simulation"
        }
    }
    
    /// Whether this medium requires an external RF bridge device
    public var requiresBridge: Bool {
        switch self {
        case .bleDirect, .simulation: return false
        case .rileyLink, .orangeLink, .emaLink: return true
        }
    }
}

// MARK: - Protocol Variant

/// Communication protocol variant
public enum PumpProtocolVariant: String, Codable, Sendable {
    case minimedRF = "minimed_rf"            // Medtronic RF protocol
    case omnipodErosBLE = "omnipod_eros"     // Eros via RileyLink
    case omnipodDashBLE = "omnipod_dash"     // DASH direct BLE
    case danaBLE = "dana_ble"                // Dana RS/i BLE
    case dexcomG6BLE = "dexcom_g6"           // For reference (CGM, not pump)
    
    public var displayName: String {
        switch self {
        case .minimedRF: return "Medtronic RF"
        case .omnipodErosBLE: return "Omnipod Eros"
        case .omnipodDashBLE: return "Omnipod DASH"
        case .danaBLE: return "Dana BLE"
        case .dexcomG6BLE: return "Dexcom G6"
        }
    }
}

// MARK: - Connection Variant

/// Complete connection variant specification
public struct PumpConnectionVariant: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let pumpType: String
    public let pumpModel: String?
    public let medium: PumpConnectionMedium
    public let protocol_: PumpProtocolVariant
    public let firmwareRange: String?
    public let notes: String
    public let verified: Bool
    public let lastVerified: Date?
    
    public init(
        pumpType: String,
        pumpModel: String? = nil,
        medium: PumpConnectionMedium,
        protocol_: PumpProtocolVariant,
        firmwareRange: String? = nil,
        notes: String = "",
        verified: Bool = false,
        lastVerified: Date? = nil
    ) {
        self.id = "\(pumpType)_\(pumpModel ?? "any")_\(medium.rawValue)"
        self.pumpType = pumpType
        self.pumpModel = pumpModel
        self.medium = medium
        self.protocol_ = protocol_
        self.firmwareRange = firmwareRange
        self.notes = notes
        self.verified = verified
        self.lastVerified = lastVerified
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: PumpConnectionVariant, rhs: PumpConnectionVariant) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Verification Status

/// Status of variant verification
public enum VariantVerificationStatus: String, Codable, Sendable {
    case verified = "verified"
    case partiallyVerified = "partial"
    case unverified = "unverified"
    case knownBroken = "broken"
    case deprecated = "deprecated"
    
    public var emoji: String {
        switch self {
        case .verified: return "✅"
        case .partiallyVerified: return "🟡"
        case .unverified: return "❓"
        case .knownBroken: return "❌"
        case .deprecated: return "⚠️"
        }
    }
}

// MARK: - Registry

/// Registry of known pump connection variants
public final class PumpConnectionVariantRegistry: @unchecked Sendable {
    public static let shared = PumpConnectionVariantRegistry()
    
    private let lock = NSLock()
    private var variants: [String: PumpConnectionVariant] = [:]
    private var verificationStatus: [String: VariantVerificationStatus] = [:]
    
    private init() {
        registerBuiltinVariants()
    }
    
    // MARK: - Registration
    
    /// Register a connection variant
    public func register(_ variant: PumpConnectionVariant, status: VariantVerificationStatus = .unverified) {
        lock.lock()
        defer { lock.unlock() }
        variants[variant.id] = variant
        verificationStatus[variant.id] = status
    }
    
    /// Get variant by ID
    public func variant(for id: String) -> PumpConnectionVariant? {
        lock.lock()
        defer { lock.unlock() }
        return variants[id]
    }
    
    /// Get all variants for a pump type
    public func variants(forPumpType pumpType: String) -> [PumpConnectionVariant] {
        lock.lock()
        defer { lock.unlock() }
        return variants.values.filter { $0.pumpType == pumpType }
    }
    
    /// Get verification status
    public func status(for variantId: String) -> VariantVerificationStatus {
        lock.lock()
        defer { lock.unlock() }
        return verificationStatus[variantId] ?? .unverified
    }
    
    /// Update verification status
    public func updateStatus(_ variantId: String, status: VariantVerificationStatus) {
        lock.lock()
        defer { lock.unlock() }
        verificationStatus[variantId] = status
    }
    
    /// Get all variants
    public func allVariants() -> [PumpConnectionVariant] {
        lock.lock()
        defer { lock.unlock() }
        return Array(variants.values)
    }
    
    /// Export registry as JSON
    public func exportJSON() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        let export = RegistryExport(
            variants: Array(variants.values),
            verificationStatus: verificationStatus,
            exportDate: Date()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }
    
    // MARK: - Built-in Variants
    
    private func registerBuiltinVariants() {
        // Medtronic pumps via RileyLink
        register(PumpConnectionVariant(
            pumpType: "medtronic",
            pumpModel: "522/722",
            medium: .rileyLink,
            protocol_: .minimedRF,
            firmwareRange: "*",
            notes: "Classic Paradigm pumps, well-tested",
            verified: true,
            lastVerified: Date()
        ), status: .verified)
        
        register(PumpConnectionVariant(
            pumpType: "medtronic",
            pumpModel: "523/723",
            medium: .rileyLink,
            protocol_: .minimedRF,
            firmwareRange: "*",
            notes: "Paradigm Revel, MySentry support",
            verified: true,
            lastVerified: Date()
        ), status: .verified)
        
        register(PumpConnectionVariant(
            pumpType: "medtronic",
            pumpModel: "554/754",
            medium: .rileyLink,
            protocol_: .minimedRF,
            firmwareRange: "< 2.4A",
            notes: "Newer models, firmware restrictions may apply",
            verified: false
        ), status: .partiallyVerified)
        
        // Omnipod DASH (direct BLE)
        register(PumpConnectionVariant(
            pumpType: "omnipod_dash",
            medium: .bleDirect,
            protocol_: .omnipodDashBLE,
            notes: "Direct BLE connection, no bridge needed",
            verified: true,
            lastVerified: Date()
        ), status: .verified)
        
        // Omnipod Eros via RileyLink
        register(PumpConnectionVariant(
            pumpType: "omnipod_eros",
            medium: .rileyLink,
            protocol_: .omnipodErosBLE,
            notes: "Requires RileyLink-compatible device",
            verified: true,
            lastVerified: Date()
        ), status: .verified)
        
        // Dana RS/i
        register(PumpConnectionVariant(
            pumpType: "dana_rs",
            medium: .bleDirect,
            protocol_: .danaBLE,
            notes: "Direct BLE, pairing required",
            verified: false
        ), status: .unverified)
        
        register(PumpConnectionVariant(
            pumpType: "dana_i",
            medium: .bleDirect,
            protocol_: .danaBLE,
            notes: "Direct BLE, pairing required",
            verified: false
        ), status: .unverified)
        
        // Simulation
        register(PumpConnectionVariant(
            pumpType: "simulation",
            medium: .simulation,
            protocol_: .minimedRF,  // Simulates Medtronic-like behavior
            notes: "Software simulation for testing",
            verified: true,
            lastVerified: Date()
        ), status: .verified)
    }
}

// MARK: - Export Structure

private struct RegistryExport: Codable {
    let variants: [PumpConnectionVariant]
    let verificationStatus: [String: VariantVerificationStatus]
    let exportDate: Date
}
