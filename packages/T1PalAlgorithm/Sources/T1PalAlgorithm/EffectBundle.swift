// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EffectBundle.swift
// T1PalAlgorithm
//
// Effect Bundle types for agent-contributed algorithm effects
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md
// Backlog: EFFECT-AGENT-001
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md

import Foundation

// MARK: - Effect Bundle

/// Container for effects contributed by a single agent at a point in time
public struct EffectBundle: Codable, Sendable, Identifiable {
    public let id: UUID
    public let agent: String
    public let timestamp: Date
    public let validFrom: Date
    public let validUntil: Date
    public let effects: [AnyEffect]
    public let reason: String?
    public let privacyTier: PrivacyTier
    public let confidence: Double
    
    public init(
        id: UUID = UUID(),
        agent: String,
        timestamp: Date = Date(),
        validFrom: Date = Date(),
        validUntil: Date,
        effects: [AnyEffect],
        reason: String? = nil,
        privacyTier: PrivacyTier = .privacyPreserving,
        confidence: Double = 0.7
    ) {
        self.id = id
        self.agent = agent
        self.timestamp = timestamp
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.effects = effects
        self.reason = reason
        self.privacyTier = privacyTier
        self.confidence = confidence
    }
    
    /// Check if bundle is currently valid
    public var isValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validUntil
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        validUntil.timeIntervalSince(validFrom)
    }
}

// MARK: - Privacy Tier

/// Privacy tier controlling what data syncs to Nightscout
public enum PrivacyTier: String, Codable, Sendable, CaseIterable {
    /// All data syncs to Nightscout
    case transparent = "transparent"
    
    /// Effects sync, personal context stays local
    case privacyPreserving = "privacyPreserving"
    
    /// User chooses what syncs per field
    case configurable = "configurable"
    
    /// Nothing syncs - on-device only
    case onDeviceOnly = "onDeviceOnly"
    
    /// Whether effects should sync to Nightscout
    public var syncsEffects: Bool {
        switch self {
        case .transparent, .privacyPreserving: return true
        case .configurable: return true // User-configured
        case .onDeviceOnly: return false
        }
    }
    
    /// Whether reason field should sync
    public var syncsReason: Bool {
        switch self {
        case .transparent: return true
        case .privacyPreserving, .configurable, .onDeviceOnly: return false
        }
    }
}

// MARK: - Effect Type

/// Type identifier for effects
public enum EffectType: String, Codable, Sendable, CaseIterable {
    case glucose = "glucose"
    case sensitivity = "sensitivity"
    case absorption = "absorption"
}

// MARK: - Type-Erased Effect

/// Type-erased effect for heterogeneous collections
public enum AnyEffect: Codable, Sendable {
    case glucose(GlucoseEffectSpec)
    case sensitivity(SensitivityEffectSpec)
    case absorption(AbsorptionEffectSpec)
    
    public var type: EffectType {
        switch self {
        case .glucose: return .glucose
        case .sensitivity: return .sensitivity
        case .absorption: return .absorption
        }
    }
    
    public var confidence: Double {
        switch self {
        case .glucose(let e): return e.confidence
        case .sensitivity(let e): return e.confidence
        case .absorption(let e): return e.confidence
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EffectType.self, forKey: .type)
        
        switch type {
        case .glucose:
            let data = try container.decode(GlucoseEffectSpec.self, forKey: .data)
            self = .glucose(data)
        case .sensitivity:
            let data = try container.decode(SensitivityEffectSpec.self, forKey: .data)
            self = .sensitivity(data)
        case .absorption:
            let data = try container.decode(AbsorptionEffectSpec.self, forKey: .data)
            self = .absorption(data)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        switch self {
        case .glucose(let data):
            try container.encode(data, forKey: .data)
        case .sensitivity(let data):
            try container.encode(data, forKey: .data)
        case .absorption(let data):
            try container.encode(data, forKey: .data)
        }
    }
}

// MARK: - Glucose Effect Specification

/// Predicts direct BG changes at future time offsets
public struct GlucoseEffectSpec: Codable, Sendable {
    public let confidence: Double
    public let series: [GlucoseEffectPoint]
    
    public init(confidence: Double, series: [GlucoseEffectPoint]) {
        self.confidence = min(max(confidence, 0), 1)
        self.series = series
    }
    
    public struct GlucoseEffectPoint: Codable, Sendable {
        /// Minutes from now
        public let minuteOffset: Int
        
        /// Expected BG change in mg/dL (bounded ±50)
        public let bgDelta: Double
        
        public init(minuteOffset: Int, bgDelta: Double) {
            self.minuteOffset = minuteOffset
            // Safety bound: ±50 mg/dL
            self.bgDelta = min(max(bgDelta, -50), 50)
        }
    }
}

// MARK: - Sensitivity Effect Specification

/// Modulates insulin sensitivity factor (ISF)
public struct SensitivityEffectSpec: Codable, Sendable {
    public let confidence: Double
    
    /// Multiplier applied to ISF (0.2-2.0)
    /// < 1.0 = more sensitive (less insulin needed)
    /// > 1.0 = less sensitive (more insulin needed)
    public let factor: Double
    
    /// Duration in minutes
    public let durationMinutes: Int
    
    public init(confidence: Double, factor: Double, durationMinutes: Int) {
        self.confidence = min(max(confidence, 0), 1)
        // Safety bound: 0.2-2.0
        self.factor = min(max(factor, 0.2), 2.0)
        self.durationMinutes = durationMinutes
    }
}

// MARK: - Absorption Effect Specification

/// Modifies carbohydrate absorption kinetics
public struct AbsorptionEffectSpec: Codable, Sendable {
    public let confidence: Double
    
    /// Absorption rate multiplier (0.2-3.0)
    /// < 1.0 = slower absorption
    /// > 1.0 = faster absorption
    public let rateMultiplier: Double
    
    /// Duration in minutes
    public let durationMinutes: Int
    
    public init(confidence: Double, rateMultiplier: Double, durationMinutes: Int) {
        self.confidence = min(max(confidence, 0), 1)
        // Safety bound: 0.2-3.0
        self.rateMultiplier = min(max(rateMultiplier, 0.2), 3.0)
        self.durationMinutes = durationMinutes
    }
}

// MARK: - Effect Bundle Validation

extension EffectBundle {
    /// Validate bundle against safety constraints
    public func validate() -> [String] {
        var errors: [String] = []
        
        // Duration check (max 24 hours)
        if duration > 24 * 3600 {
            errors.append("Duration exceeds 24 hours maximum")
        }
        
        // Valid time range
        if validUntil <= validFrom {
            errors.append("validUntil must be after validFrom")
        }
        
        // Confidence check
        if confidence < 0 || confidence > 1 {
            errors.append("Confidence must be between 0 and 1")
        }
        
        // Agent name check
        if agent.isEmpty {
            errors.append("Agent name cannot be empty")
        }
        
        return errors
    }
}

// MARK: - Effect Bundle for Nightscout Sync

extension EffectBundle {
    /// Convert to sync-safe representation respecting privacy tier
    public func toSyncRepresentation() -> EffectBundle? {
        guard privacyTier.syncsEffects else { return nil }
        
        return EffectBundle(
            id: id,
            agent: agent,
            timestamp: timestamp,
            validFrom: validFrom,
            validUntil: validUntil,
            effects: effects,
            reason: privacyTier.syncsReason ? reason : nil,
            privacyTier: privacyTier,
            confidence: confidence
        )
    }
}

// MARK: - Effect Bundle Store (DATA-COHESIVE-002)

/// Protocol for persisting effect bundles from agents.
/// Follows same API patterns as GlucoseStore and TreatmentStore.
public protocol EffectBundleStore: Sendable {
    /// Save an effect bundle.
    func save(_ bundle: EffectBundle) async throws
    
    /// Save multiple effect bundles.
    func save(_ bundles: [EffectBundle]) async throws
    
    /// Fetch bundles in a date range.
    func fetch(from start: Date, to end: Date) async throws -> [EffectBundle]
    
    /// Fetch bundles by agent.
    func fetch(agent: String) async throws -> [EffectBundle]
    
    /// Fetch the most recent N bundles.
    func fetchLatest(_ count: Int) async throws -> [EffectBundle]
    
    /// Fetch the most recent bundle.
    func fetchMostRecent() async throws -> EffectBundle?
    
    /// Fetch currently valid bundles (validFrom <= now <= validUntil).
    func fetchValid() async throws -> [EffectBundle]
    
    /// Delete bundles older than a date.
    func deleteOlderThan(_ date: Date) async throws -> Int
    
    /// Delete all bundles.
    func deleteAll() async throws
    
    /// Count of all bundles.
    func count() async throws -> Int
}

// MARK: - In-Memory Effect Bundle Store

/// In-memory implementation for testing.
public actor InMemoryEffectBundleStore: EffectBundleStore {
    private var bundles: [UUID: EffectBundle] = [:]
    
    public init() {}
    
    public func save(_ bundle: EffectBundle) async throws {
        bundles[bundle.id] = bundle
    }
    
    public func save(_ bundles: [EffectBundle]) async throws {
        for bundle in bundles {
            self.bundles[bundle.id] = bundle
        }
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [EffectBundle] {
        bundles.values
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func fetch(agent: String) async throws -> [EffectBundle] {
        bundles.values
            .filter { $0.agent == agent }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func fetchLatest(_ count: Int) async throws -> [EffectBundle] {
        Array(bundles.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(count))
    }
    
    public func fetchMostRecent() async throws -> EffectBundle? {
        bundles.values.max { $0.timestamp < $1.timestamp }
    }
    
    public func fetchValid() async throws -> [EffectBundle] {
        bundles.values
            .filter { $0.isValid }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let toDelete = bundles.values.filter { $0.timestamp < date }
        for bundle in toDelete {
            bundles.removeValue(forKey: bundle.id)
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        bundles.removeAll()
    }
    
    public func count() async throws -> Int {
        bundles.count
    }
}

// MARK: - Dose Impact (EFFECT-CLARITY-002)

/// Human-readable description of how an effect impacts insulin dosing
public struct DoseImpactSummary: Codable, Sendable, Equatable {
    /// Human-readable description (e.g., "~1.2U less insulin")
    public let description: String
    
    /// Direction of change
    public let direction: DoseDirection
    
    /// Estimated units of insulin change (positive = more, negative = less)
    public let estimatedUnitsChange: Double?
    
    /// Duration in minutes
    public let durationMinutes: Int
    
    /// Source effect type
    public let effectType: EffectType
    
    public init(
        description: String,
        direction: DoseDirection,
        estimatedUnitsChange: Double? = nil,
        durationMinutes: Int,
        effectType: EffectType
    ) {
        self.description = description
        self.direction = direction
        self.estimatedUnitsChange = estimatedUnitsChange
        self.durationMinutes = durationMinutes
        self.effectType = effectType
    }
    
    public enum DoseDirection: String, Codable, Sendable {
        case lessInsulin = "less"
        case moreInsulin = "more"
        case noChange = "unchanged"
    }
}

extension AnyEffect {
    /// Compute human-readable dose impact for this effect
    /// Note: Actual insulin change depends on current basal rate and profile
    public func computeDoseImpact(basalRatePerHour: Double = 1.0) -> DoseImpactSummary {
        switch self {
        case .glucose(let spec):
            return computeGlucoseImpact(spec)
        case .sensitivity(let spec):
            return computeSensitivityImpact(spec, basalRate: basalRatePerHour)
        case .absorption(let spec):
            return computeAbsorptionImpact(spec)
        }
    }
    
    private func computeGlucoseImpact(_ spec: GlucoseEffectSpec) -> DoseImpactSummary {
        // Calculate net glucose delta from the series
        var totalDelta = 0.0
        for point in spec.series {
            totalDelta += point.bgDelta
        }
        let maxDuration = spec.series.map(\.minuteOffset).max() ?? 0
        
        let direction: DoseImpactSummary.DoseDirection
        let description: String
        
        if abs(totalDelta) < 5 {
            direction = .noChange
            description = "Minimal glucose impact"
        } else if totalDelta > 0 {
            direction = .moreInsulin
            description = "Predicted +\(Int(totalDelta)) mg/dL → may need more insulin"
        } else {
            direction = .lessInsulin
            description = "Predicted \(Int(totalDelta)) mg/dL → may need less insulin"
        }
        
        return DoseImpactSummary(
            description: description,
            direction: direction,
            estimatedUnitsChange: nil, // Glucose effects don't directly map to units
            durationMinutes: maxDuration,
            effectType: .glucose
        )
    }
    
    private func computeSensitivityImpact(_ spec: SensitivityEffectSpec, basalRate: Double) -> DoseImpactSummary {
        // factor < 1.0 = more sensitive = less insulin needed
        // factor > 1.0 = less sensitive = more insulin needed
        let percentChange = (spec.factor - 1.0) * 100
        let hours = Double(spec.durationMinutes) / 60.0
        
        // Rough estimate: if 20% more sensitive for 4 hours at 1U/hr basal
        // → ~0.8U less insulin over that period (simplified)
        let estimatedChange = (spec.factor - 1.0) * basalRate * hours
        
        let direction: DoseImpactSummary.DoseDirection
        let description: String
        
        if abs(spec.factor - 1.0) < 0.05 {
            direction = .noChange
            description = "Minimal sensitivity change"
        } else if spec.factor < 1.0 {
            direction = .lessInsulin
            let formatted = String(format: "%.1f", abs(estimatedChange))
            description = "+\(Int(abs(percentChange)))% sensitivity → ~\(formatted)U less insulin"
        } else {
            direction = .moreInsulin
            let formatted = String(format: "%.1f", estimatedChange)
            description = "-\(Int(percentChange))% sensitivity → ~\(formatted)U more insulin"
        }
        
        return DoseImpactSummary(
            description: description,
            direction: direction,
            estimatedUnitsChange: estimatedChange,
            durationMinutes: spec.durationMinutes,
            effectType: .sensitivity
        )
    }
    
    private func computeAbsorptionImpact(_ spec: AbsorptionEffectSpec) -> DoseImpactSummary {
        // Absorption affects timing, not total insulin
        let percentChange = (spec.rateMultiplier - 1.0) * 100
        
        let direction: DoseImpactSummary.DoseDirection
        let description: String
        
        if abs(spec.rateMultiplier - 1.0) < 0.1 {
            direction = .noChange
            description = "Normal carb absorption"
        } else if spec.rateMultiplier > 1.0 {
            // Faster absorption = earlier insulin peak needed
            direction = .moreInsulin // Transiently
            description = "+\(Int(percentChange))% faster absorption → front-load insulin"
        } else {
            // Slower absorption = spread insulin over time
            direction = .lessInsulin // Transiently
            description = "\(Int(percentChange))% slower absorption → spread insulin"
        }
        
        return DoseImpactSummary(
            description: description,
            direction: direction,
            estimatedUnitsChange: nil, // Absorption affects timing, not total
            durationMinutes: spec.durationMinutes,
            effectType: .absorption
        )
    }
}

extension EffectBundle {
    /// Compute dose impact summaries for all effects in this bundle
    public func computeDoseImpacts(basalRatePerHour: Double = 1.0) -> [DoseImpactSummary] {
        effects.map { $0.computeDoseImpact(basalRatePerHour: basalRatePerHour) }
    }
    
    /// Net dose direction from all effects combined
    public var netDoseDirection: DoseImpactSummary.DoseDirection {
        let impacts = computeDoseImpacts()
        let lessCount = impacts.filter { $0.direction == .lessInsulin }.count
        let moreCount = impacts.filter { $0.direction == .moreInsulin }.count
        
        if lessCount > moreCount { return .lessInsulin }
        if moreCount > lessCount { return .moreInsulin }
        return .noChange
    }
    
    /// Human-readable summary of the bundle's overall effect
    public func humanReadableSummary(basalRatePerHour: Double = 1.0) -> String {
        let impacts = computeDoseImpacts(basalRatePerHour: basalRatePerHour)
        
        if impacts.isEmpty {
            return "No active effects"
        }
        
        if impacts.count == 1 {
            return impacts[0].description
        }
        
        // Multiple effects - summarize net direction
        let totalChange = impacts.compactMap(\.estimatedUnitsChange).reduce(0, +)
        let netDirection = netDoseDirection
        
        switch netDirection {
        case .lessInsulin:
            if abs(totalChange) > 0.1 {
                return "Net: ~\(String(format: "%.1f", abs(totalChange)))U less insulin (\(impacts.count) effects)"
            }
            return "Net: Less insulin needed (\(impacts.count) effects)"
        case .moreInsulin:
            if abs(totalChange) > 0.1 {
                return "Net: ~\(String(format: "%.1f", totalChange))U more insulin (\(impacts.count) effects)"
            }
            return "Net: More insulin needed (\(impacts.count) effects)"
        case .noChange:
            return "Effects cancel out (\(impacts.count) effects)"
        }
    }
}
