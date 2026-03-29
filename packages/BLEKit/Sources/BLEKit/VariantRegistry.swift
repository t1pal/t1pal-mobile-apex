// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// VariantRegistry.swift
// BLEKit
//
// Protocol variant registry for managing different protocol implementations.
// Supports registration, lookup, and selection of protocol variants.
//
// INSTR-002: VariantRegistry protocol definition

import Foundation

// MARK: - Variant Capability

/// Capability that a protocol variant may support.
public enum VariantCapability: String, Sendable, Codable, CaseIterable {
    case authentication
    case encryption
    case backfill
    case calibration
    case sensorStart
    case sensorStop
    case glucoseReading
    case rawReading
    case prediction
    case alerts
    case firmwareUpdate
    case factoryReset
    case diagnostics
    case bonding
    case pairing
    case broadcasting
    case notifications
    case indications
    case writeWithResponse
    case writeWithoutResponse
}

/// Set of capabilities for a variant.
public struct CapabilitySet: Sendable, Equatable, Codable {
    public private(set) var capabilities: Set<VariantCapability>
    
    public init(_ capabilities: Set<VariantCapability> = []) {
        self.capabilities = capabilities
    }
    
    public init(_ capabilities: [VariantCapability]) {
        self.capabilities = Set(capabilities)
    }
    
    public func contains(_ capability: VariantCapability) -> Bool {
        capabilities.contains(capability)
    }
    
    public func containsAll(_ required: [VariantCapability]) -> Bool {
        required.allSatisfy { capabilities.contains($0) }
    }
    
    public func containsAny(_ required: [VariantCapability]) -> Bool {
        required.contains { capabilities.contains($0) }
    }
    
    public mutating func insert(_ capability: VariantCapability) {
        capabilities.insert(capability)
    }
    
    public mutating func remove(_ capability: VariantCapability) {
        capabilities.remove(capability)
    }
    
    public func union(_ other: CapabilitySet) -> CapabilitySet {
        CapabilitySet(capabilities.union(other.capabilities))
    }
    
    public func intersection(_ other: CapabilitySet) -> CapabilitySet {
        CapabilitySet(capabilities.intersection(other.capabilities))
    }
    
    public var count: Int { capabilities.count }
    public var isEmpty: Bool { capabilities.isEmpty }
    
    // Preset capability sets
    public static let empty = CapabilitySet([])
    
    public static let basicCGM = CapabilitySet([
        .glucoseReading, .notifications, .bonding
    ])
    
    public static let advancedCGM = CapabilitySet([
        .glucoseReading, .notifications, .bonding,
        .authentication, .encryption, .backfill, .calibration
    ])
    
    public static let fullCGM = CapabilitySet([
        .glucoseReading, .rawReading, .notifications, .bonding,
        .authentication, .encryption, .backfill, .calibration,
        .sensorStart, .sensorStop, .alerts, .prediction
    ])
    
    public static let basicPump = CapabilitySet([
        .bonding, .writeWithResponse, .notifications
    ])
    
    public static let advancedPump = CapabilitySet([
        .bonding, .writeWithResponse, .notifications,
        .authentication, .encryption
    ])
}

// MARK: - Protocol Variant

/// Protocol family identifier.
public enum ProtocolFamily: String, Sendable, Codable, CaseIterable {
    case dexcom
    case libre
    case medtronic
    case omnipod
    case tandem
    case dana
    case unknown
}

/// Protocol variant identifier with metadata.
public struct ProtocolVariant: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let family: ProtocolFamily
    public let name: String
    public let version: String
    public let capabilities: CapabilitySet
    public let minFirmware: String?
    public let maxFirmware: String?
    public let deprecated: Bool
    public let experimental: Bool
    public let metadata: [String: String]
    
    public init(
        id: String,
        family: ProtocolFamily,
        name: String,
        version: String,
        capabilities: CapabilitySet = .empty,
        minFirmware: String? = nil,
        maxFirmware: String? = nil,
        deprecated: Bool = false,
        experimental: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.family = family
        self.name = name
        self.version = version
        self.capabilities = capabilities
        self.minFirmware = minFirmware
        self.maxFirmware = maxFirmware
        self.deprecated = deprecated
        self.experimental = experimental
        self.metadata = metadata
    }
    
    public func hasCapability(_ capability: VariantCapability) -> Bool {
        capabilities.contains(capability)
    }
    
    public func meetsRequirements(_ required: [VariantCapability]) -> Bool {
        capabilities.containsAll(required)
    }
    
    public func supportsFirmware(_ firmware: String) -> Bool {
        if let min = minFirmware, firmware < min { return false }
        if let max = maxFirmware, firmware > max { return false }
        return true
    }
    
    // Well-known variants
    public static let dexcomG6 = ProtocolVariant(
        id: "dexcom.g6",
        family: .dexcom,
        name: "Dexcom G6",
        version: "1.0",
        capabilities: .advancedCGM,
        minFirmware: "1.0.0"
    )
    
    public static let dexcomG7 = ProtocolVariant(
        id: "dexcom.g7",
        family: .dexcom,
        name: "Dexcom G7",
        version: "1.0",
        capabilities: .fullCGM,
        minFirmware: "1.0.0"
    )
    
    public static let libre2 = ProtocolVariant(
        id: "libre.2",
        family: .libre,
        name: "Libre 2",
        version: "1.0",
        capabilities: .advancedCGM,
        minFirmware: "2.0.0"
    )
    
    public static let libre3 = ProtocolVariant(
        id: "libre.3",
        family: .libre,
        name: "Libre 3",
        version: "1.0",
        capabilities: .fullCGM,
        minFirmware: "3.0.0"
    )
    
    public static let unknown = ProtocolVariant(
        id: "unknown",
        family: .unknown,
        name: "Unknown",
        version: "0.0",
        capabilities: .empty
    )
}

// MARK: - Variant Match

/// Result of matching a device to a variant.
public struct VariantMatch: Sendable, Equatable {
    public let variant: ProtocolVariant
    public let confidence: Double
    public let matchReason: String
    public let warnings: [String]
    
    public init(
        variant: ProtocolVariant,
        confidence: Double,
        matchReason: String,
        warnings: [String] = []
    ) {
        self.variant = variant
        self.confidence = min(1.0, max(0.0, confidence))
        self.matchReason = matchReason
        self.warnings = warnings
    }
    
    public var isHighConfidence: Bool { confidence >= 0.9 }
    public var isMediumConfidence: Bool { confidence >= 0.7 && confidence < 0.9 }
    public var isLowConfidence: Bool { confidence < 0.7 }
    
    public static func exact(_ variant: ProtocolVariant, reason: String) -> VariantMatch {
        VariantMatch(variant: variant, confidence: 1.0, matchReason: reason)
    }
    
    public static func probable(_ variant: ProtocolVariant, confidence: Double, reason: String) -> VariantMatch {
        VariantMatch(variant: variant, confidence: confidence, matchReason: reason)
    }
    
    public static func uncertain(_ variant: ProtocolVariant, reason: String, warnings: [String]) -> VariantMatch {
        VariantMatch(variant: variant, confidence: 0.5, matchReason: reason, warnings: warnings)
    }
}

// MARK: - Device Context

/// Context for variant selection based on device information.
public struct DeviceContext: Sendable, Equatable {
    public let deviceId: String
    public let name: String?
    public let manufacturer: String?
    public let model: String?
    public let firmware: String?
    public let serviceUUIDs: [String]
    public let advertisementData: [String: String]
    
    public init(
        deviceId: String,
        name: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        firmware: String? = nil,
        serviceUUIDs: [String] = [],
        advertisementData: [String: String] = [:]
    ) {
        self.deviceId = deviceId
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.firmware = firmware
        self.serviceUUIDs = serviceUUIDs
        self.advertisementData = advertisementData
    }
    
    public func hasService(_ uuid: String) -> Bool {
        serviceUUIDs.contains(uuid.uppercased()) || serviceUUIDs.contains(uuid.lowercased())
    }
    
    public func nameContains(_ substring: String) -> Bool {
        name?.lowercased().contains(substring.lowercased()) ?? false
    }
    
    public func manufacturerIs(_ expected: String) -> Bool {
        manufacturer?.lowercased() == expected.lowercased()
    }
}

// MARK: - Variant Matcher

/// Protocol for matching devices to variants.
public protocol VariantMatcher: Sendable {
    /// Unique identifier for this matcher.
    var matcherId: String { get }
    
    /// Protocol family this matcher handles.
    var family: ProtocolFamily { get }
    
    /// Attempt to match a device context to a variant.
    func match(context: DeviceContext) -> VariantMatch?
    
    /// Check if this matcher can handle the given context.
    func canHandle(context: DeviceContext) -> Bool
}

/// Matcher for Dexcom devices.
public struct DexcomMatcher: VariantMatcher, Sendable {
    public let matcherId = "dexcom"
    public let family = ProtocolFamily.dexcom
    
    // G6 and G7 use the same service UUID - verified against G7SensorKit/BluetoothServices.swift
    // PROTO-XREF-011: Verified 2026-02-17
    private let dexcomServiceUUID = "F8083532-849E-531C-C594-30F1F86A4EA5"
    
    public init() {}
    
    public func canHandle(context: DeviceContext) -> Bool {
        context.nameContains("Dexcom") ||
        context.manufacturerIs("Dexcom") ||
        context.hasService(dexcomServiceUUID)
    }
    
    public func match(context: DeviceContext) -> VariantMatch? {
        guard canHandle(context: context) else { return nil }
        
        // G7 and G6 use the same service UUID, differentiate by name
        if context.nameContains("G7") {
            return .exact(.dexcomG7, reason: "G7 name match")
        }
        
        // Check for G6 by name or service
        if context.nameContains("G6") || context.hasService(dexcomServiceUUID) {
            return .exact(.dexcomG6, reason: "G6 name or service UUID match")
        }
        
        // Generic Dexcom - assume G6 with lower confidence
        return .probable(.dexcomG6, confidence: 0.7, reason: "Dexcom device, assuming G6")
    }
}

/// Matcher for Libre devices.
public struct LibreMatcher: VariantMatcher, Sendable {
    public let matcherId = "libre"
    public let family = ProtocolFamily.libre
    
    public init() {}
    
    public func canHandle(context: DeviceContext) -> Bool {
        context.nameContains("Libre") ||
        context.nameContains("FSL") ||
        context.manufacturerIs("Abbott")
    }
    
    public func match(context: DeviceContext) -> VariantMatch? {
        guard canHandle(context: context) else { return nil }
        
        // Check for Libre 3
        if context.nameContains("Libre 3") || context.nameContains("FSL3") {
            return .exact(.libre3, reason: "Libre 3 name match")
        }
        
        // Check for Libre 2
        if context.nameContains("Libre 2") || context.nameContains("FSL2") {
            return .exact(.libre2, reason: "Libre 2 name match")
        }
        
        // Generic Libre - need more info
        return .uncertain(.libre2, reason: "Libre device, version unknown", 
                          warnings: ["Could not determine Libre version"])
    }
}

// MARK: - Variant Configuration

/// Configuration for a specific variant instance.
public struct VariantConfiguration: Sendable, Equatable, Codable {
    public let variantId: String
    public let enabled: Bool
    public let priority: Int
    public let settings: [String: String]
    public let overrides: [String: String]
    
    public init(
        variantId: String,
        enabled: Bool = true,
        priority: Int = 0,
        settings: [String: String] = [:],
        overrides: [String: String] = [:]
    ) {
        self.variantId = variantId
        self.enabled = enabled
        self.priority = priority
        self.settings = settings
        self.overrides = overrides
    }
    
    public func setting(_ key: String) -> String? {
        overrides[key] ?? settings[key]
    }
    
    public func withOverride(_ key: String, value: String) -> VariantConfiguration {
        var newOverrides = overrides
        newOverrides[key] = value
        return VariantConfiguration(
            variantId: variantId,
            enabled: enabled,
            priority: priority,
            settings: settings,
            overrides: newOverrides
        )
    }
    
    public func withEnabled(_ enabled: Bool) -> VariantConfiguration {
        VariantConfiguration(
            variantId: variantId,
            enabled: enabled,
            priority: priority,
            settings: settings,
            overrides: overrides
        )
    }
    
    public func withPriority(_ priority: Int) -> VariantConfiguration {
        VariantConfiguration(
            variantId: variantId,
            enabled: enabled,
            priority: priority,
            settings: settings,
            overrides: overrides
        )
    }
    
    public static func `default`(for variantId: String) -> VariantConfiguration {
        VariantConfiguration(variantId: variantId)
    }
}

// G7, G6, Libre2 VariantConfiguration extensions moved to VariantConfigurationExtensions.swift (BLE-REFACTOR-003)

// MARK: - Registry Statistics

/// Statistics about the variant registry.
public struct RegistryStatistics: Sendable, Equatable {
    public let totalVariants: Int
    public let enabledVariants: Int
    public let deprecatedVariants: Int
    public let experimentalVariants: Int
    public let variantsByFamily: [ProtocolFamily: Int]
    public let matcherCount: Int
    
    public init(
        totalVariants: Int,
        enabledVariants: Int,
        deprecatedVariants: Int,
        experimentalVariants: Int,
        variantsByFamily: [ProtocolFamily: Int],
        matcherCount: Int
    ) {
        self.totalVariants = totalVariants
        self.enabledVariants = enabledVariants
        self.deprecatedVariants = deprecatedVariants
        self.experimentalVariants = experimentalVariants
        self.variantsByFamily = variantsByFamily
        self.matcherCount = matcherCount
    }
}

// MARK: - Variant Registry Protocol

/// Protocol for variant registries.
public protocol VariantRegistry: Sendable {
    /// Register a variant.
    func register(_ variant: ProtocolVariant) async
    
    /// Register a variant with configuration.
    func register(_ variant: ProtocolVariant, configuration: VariantConfiguration) async
    
    /// Unregister a variant by ID.
    func unregister(variantId: String) async -> Bool
    
    /// Get a variant by ID.
    func variant(id: String) async -> ProtocolVariant?
    
    /// Get configuration for a variant.
    func configuration(for variantId: String) async -> VariantConfiguration?
    
    /// Update configuration for a variant.
    func updateConfiguration(_ configuration: VariantConfiguration) async
    
    /// Get all registered variants.
    func allVariants() async -> [ProtocolVariant]
    
    /// Get variants by family.
    func variants(family: ProtocolFamily) async -> [ProtocolVariant]
    
    /// Get variants with specific capability.
    func variants(withCapability: VariantCapability) async -> [ProtocolVariant]
    
    /// Get enabled variants only.
    func enabledVariants() async -> [ProtocolVariant]
    
    /// Check if a variant is registered.
    func isRegistered(variantId: String) async -> Bool
    
    /// Register a matcher.
    func registerMatcher(_ matcher: VariantMatcher) async
    
    /// Match a device context to a variant.
    func match(context: DeviceContext) async -> VariantMatch?
    
    /// Get all matches for a device context, sorted by confidence.
    func allMatches(context: DeviceContext) async -> [VariantMatch]
    
    /// Get registry statistics.
    func statistics() async -> RegistryStatistics
    
    /// Clear all registrations.
    func clear() async
}

// StandardVariantRegistry, CompositeVariantRegistry, ReadOnlyVariantRegistry moved to VariantRegistryImplementations.swift (BLE-REFACTOR-003)

// MARK: - Variant Selection Strategy

/// Strategy for selecting among multiple variant matches.
public enum VariantSelectionStrategy: Sendable {
    case highestConfidence
    case preferStable
    case preferExperimental
    case byFamily(ProtocolFamily)
    case custom(@Sendable (VariantMatch, VariantMatch) -> Bool)
    
    public func select(from matches: [VariantMatch]) -> VariantMatch? {
        guard !matches.isEmpty else { return nil }
        
        switch self {
        case .highestConfidence:
            return matches.max { $0.confidence < $1.confidence }
            
        case .preferStable:
            let stable = matches.filter { !$0.variant.experimental && !$0.variant.deprecated }
            return stable.max { $0.confidence < $1.confidence } ?? matches.first
            
        case .preferExperimental:
            let experimental = matches.filter { $0.variant.experimental }
            return experimental.max { $0.confidence < $1.confidence } ?? matches.first
            
        case .byFamily(let family):
            let familyMatches = matches.filter { $0.variant.family == family }
            return familyMatches.max { $0.confidence < $1.confidence } ?? matches.first
            
        case .custom(let comparator):
            return matches.sorted(by: comparator).first
        }
    }
}

// MARK: - Variant Builder

/// Fluent builder for creating protocol variants.
public struct VariantBuilder: Sendable {
    private var id: String
    private var family: ProtocolFamily = .unknown
    private var name: String = ""
    private var version: String = "1.0"
    private var capabilities: CapabilitySet = .empty
    private var minFirmware: String?
    private var maxFirmware: String?
    private var deprecated: Bool = false
    private var experimental: Bool = false
    private var metadata: [String: String] = [:]
    
    public init(id: String) {
        self.id = id
    }
    
    public func family(_ family: ProtocolFamily) -> VariantBuilder {
        var builder = self
        builder.family = family
        return builder
    }
    
    public func name(_ name: String) -> VariantBuilder {
        var builder = self
        builder.name = name
        return builder
    }
    
    public func version(_ version: String) -> VariantBuilder {
        var builder = self
        builder.version = version
        return builder
    }
    
    public func capabilities(_ capabilities: CapabilitySet) -> VariantBuilder {
        var builder = self
        builder.capabilities = capabilities
        return builder
    }
    
    public func capability(_ capability: VariantCapability) -> VariantBuilder {
        var builder = self
        builder.capabilities.insert(capability)
        return builder
    }
    
    public func minFirmware(_ firmware: String) -> VariantBuilder {
        var builder = self
        builder.minFirmware = firmware
        return builder
    }
    
    public func maxFirmware(_ firmware: String) -> VariantBuilder {
        var builder = self
        builder.maxFirmware = firmware
        return builder
    }
    
    public func deprecated(_ deprecated: Bool = true) -> VariantBuilder {
        var builder = self
        builder.deprecated = deprecated
        return builder
    }
    
    public func experimental(_ experimental: Bool = true) -> VariantBuilder {
        var builder = self
        builder.experimental = experimental
        return builder
    }
    
    public func metadata(_ key: String, _ value: String) -> VariantBuilder {
        var builder = self
        builder.metadata[key] = value
        return builder
    }
    
    public func build() -> ProtocolVariant {
        ProtocolVariant(
            id: id,
            family: family,
            name: name.isEmpty ? id : name,
            version: version,
            capabilities: capabilities,
            minFirmware: minFirmware,
            maxFirmware: maxFirmware,
            deprecated: deprecated,
            experimental: experimental,
            metadata: metadata
        )
    }
}
