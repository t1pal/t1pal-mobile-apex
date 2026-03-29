// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EffectProvider.swift
// T1PalAlgorithm
//
// Effect Provider protocol and EffectBundleComposer for multi-agent composition
// Backlog: ALG-EFF-061..063
// Trace: PRD-026 Effect Bundle Architecture, PRD-028 Phase 2

import Foundation

// MARK: - Effect Provider Protocol (ALG-EFF-061)

/// Protocol for agents that produce effect bundles
public protocol EffectProvider: Sendable {
    /// Unique identifier for this provider
    var providerId: String { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Current enabled state
    var isEnabled: Bool { get }
    
    /// Generate effect bundle based on current context
    func generateEffects(context: EffectContext) async -> EffectBundle?
}

/// Context provided to effect providers
public struct EffectContext: Sendable {
    /// Current glucose value (mg/dL)
    public let currentGlucose: Double?
    
    /// Recent glucose trend
    public let trend: EffectGlucoseTrend?
    
    /// Current time
    public let timestamp: Date
    
    /// Active overrides
    public let activeOverrides: [String]
    
    /// Recent activities (from HealthKit, etc.)
    public let recentActivities: [String]
    
    /// User preferences
    public let preferences: EffectPreferences
    
    public init(
        currentGlucose: Double? = nil,
        trend: EffectGlucoseTrend? = nil,
        timestamp: Date = Date(),
        activeOverrides: [String] = [],
        recentActivities: [String] = [],
        preferences: EffectPreferences = EffectPreferences()
    ) {
        self.currentGlucose = currentGlucose
        self.trend = trend
        self.timestamp = timestamp
        self.activeOverrides = activeOverrides
        self.recentActivities = recentActivities
        self.preferences = preferences
    }
}

/// Glucose trend for context
public enum EffectGlucoseTrend: String, Codable, Sendable {
    case risingFast = "rising_fast"
    case rising = "rising"
    case stable = "stable"
    case falling = "falling"
    case fallingFast = "falling_fast"
}

/// User preferences for effect generation
public struct EffectPreferences: Sendable {
    /// Maximum sensitivity multiplier allowed
    public let maxSensitivityMultiplier: Double
    
    /// Maximum basal multiplier allowed
    public let maxBasalMultiplier: Double
    
    /// Whether to generate glucose predictions
    public let enableGlucosePredictions: Bool
    
    /// Privacy tier preference
    public let privacyTier: PrivacyTier
    
    public init(
        maxSensitivityMultiplier: Double = 2.0,
        maxBasalMultiplier: Double = 2.0,
        enableGlucosePredictions: Bool = true,
        privacyTier: PrivacyTier = .privacyPreserving
    ) {
        self.maxSensitivityMultiplier = maxSensitivityMultiplier
        self.maxBasalMultiplier = maxBasalMultiplier
        self.enableGlucosePredictions = enableGlucosePredictions
        self.privacyTier = privacyTier
    }
}

// MARK: - Effect Bundle Composer (ALG-EFF-063)

/// Composes multiple effect bundles with conflict resolution
public actor EffectBundleComposer {
    
    /// Registered effect providers
    private var providers: [String: any EffectProvider] = [:]
    
    /// Active effect bundles
    private var activeBundles: [UUID: EffectBundle] = [:]
    
    /// Conflict resolution strategy
    private let strategy: ConflictResolutionStrategy
    
    public init(strategy: ConflictResolutionStrategy = .confidenceWeighted) {
        self.strategy = strategy
    }
    
    /// Register an effect provider
    public func register(provider: some EffectProvider) {
        providers[provider.providerId] = provider
    }
    
    /// Unregister a provider
    public func unregister(providerId: String) {
        providers.removeValue(forKey: providerId)
    }
    
    /// Get all registered providers
    public func getProviders() -> [String] {
        Array(providers.keys)
    }
    
    /// Generate effects from all enabled providers
    public func generateAllEffects(context: EffectContext) async -> [EffectBundle] {
        var bundles: [EffectBundle] = []
        
        for (_, provider) in providers where provider.isEnabled {
            if let bundle = await provider.generateEffects(context: context) {
                bundles.append(bundle)
                activeBundles[bundle.id] = bundle
            }
        }
        
        // Prune expired bundles
        pruneExpiredBundles()
        
        return bundles
    }
    
    /// Compose all active bundles into a single modifier
    public func compose() -> ComposedEffect {
        pruneExpiredBundles()
        
        let validBundles = activeBundles.values.filter { $0.isValid }
        
        guard !validBundles.isEmpty else {
            return ComposedEffect(
                modifier: .identity,
                contributingAgents: [],
                conflicts: []
            )
        }
        
        return composeWithStrategy(bundles: Array(validBundles))
    }
    
    /// Add a bundle directly (for testing or manual injection)
    public func addBundle(_ bundle: EffectBundle) {
        activeBundles[bundle.id] = bundle
    }
    
    /// Remove a bundle
    public func removeBundle(id: UUID) {
        activeBundles.removeValue(forKey: id)
    }
    
    /// Get active bundles
    public func getActiveBundles() -> [EffectBundle] {
        pruneExpiredBundles()
        return Array(activeBundles.values)
    }
    
    private func pruneExpiredBundles() {
        activeBundles = activeBundles.filter { $0.value.isValid }
    }
    
    private func composeWithStrategy(bundles: [EffectBundle]) -> ComposedEffect {
        var conflicts: [EffectConflict] = []
        
        switch strategy {
        case .confidenceWeighted:
            return composeConfidenceWeighted(bundles: bundles, conflicts: &conflicts)
        case .mostRecent:
            return composeMostRecent(bundles: bundles, conflicts: &conflicts)
        case .mostConservative:
            return composeMostConservative(bundles: bundles, conflicts: &conflicts)
        }
    }
    
    private func composeConfidenceWeighted(
        bundles: [EffectBundle],
        conflicts: inout [EffectConflict]
    ) -> ComposedEffect {
        var weightedISF = 0.0
        var weightedBasal = 0.0
        var totalWeight = 0.0
        
        for bundle in bundles {
            let weight = bundle.confidence
            totalWeight += weight
            
            // Extract ISF and basal factors from effects
            var isfFactor = 1.0
            for effect in bundle.effects {
                if case .sensitivity(let spec) = effect {
                    isfFactor = spec.factor
                }
            }
            
            weightedISF += isfFactor * weight
            weightedBasal += 1.0 * weight  // No basal in current effect types
        }
        
        guard totalWeight > 0 else {
            return ComposedEffect(
                modifier: .identity,
                contributingAgents: [],
                conflicts: []
            )
        }
        
        // Detect conflicts
        detectConflicts(bundles: bundles, conflicts: &conflicts)
        
        let finalModifier = EffectModifier(
            isfMultiplier: weightedISF / totalWeight,
            basalMultiplier: weightedBasal / totalWeight,
            source: "composed",
            confidence: totalWeight / Double(bundles.count),
            reason: "Composed from \(bundles.count) agent(s)"
        )
        
        return ComposedEffect(
            modifier: finalModifier,
            contributingAgents: bundles.map { $0.agent },
            conflicts: conflicts
        )
    }
    
    private func composeMostRecent(
        bundles: [EffectBundle],
        conflicts: inout [EffectConflict]
    ) -> ComposedEffect {
        guard let mostRecent = bundles.max(by: { $0.timestamp < $1.timestamp }) else {
            return ComposedEffect(modifier: .identity, contributingAgents: [], conflicts: [])
        }
        
        detectConflicts(bundles: bundles, conflicts: &conflicts)
        
        // Convert bundle to modifier
        var isfFactor = 1.0
        for effect in mostRecent.effects {
            if case .sensitivity(let spec) = effect {
                isfFactor = spec.factor
            }
        }
        
        let modifier = EffectModifier(
            isfMultiplier: isfFactor,
            source: mostRecent.agent,
            confidence: mostRecent.confidence,
            reason: mostRecent.reason
        )
        
        return ComposedEffect(
            modifier: modifier,
            contributingAgents: [mostRecent.agent],
            conflicts: conflicts
        )
    }
    
    private func composeMostConservative(
        bundles: [EffectBundle],
        conflicts: inout [EffectConflict]
    ) -> ComposedEffect {
        // Most conservative = closest to identity (1.0)
        var isfClosestTo1 = 1.0
        
        for bundle in bundles {
            for effect in bundle.effects {
                if case .sensitivity(let spec) = effect {
                    if abs(spec.factor - 1.0) < abs(isfClosestTo1 - 1.0) {
                        isfClosestTo1 = spec.factor
                    }
                }
            }
        }
        
        detectConflicts(bundles: bundles, conflicts: &conflicts)
        
        let finalModifier = EffectModifier(
            isfMultiplier: isfClosestTo1,
            source: "composed.conservative",
            confidence: 0.9,
            reason: "Most conservative composition"
        )
        
        return ComposedEffect(
            modifier: finalModifier,
            contributingAgents: bundles.map { $0.agent },
            conflicts: conflicts
        )
    }
    
    private func detectConflicts(bundles: [EffectBundle], conflicts: inout [EffectConflict]) {
        // Check for opposing sensitivity directions
        var sensitivityDirections: [(agent: String, direction: Double)] = []
        
        for bundle in bundles {
            for effect in bundle.effects {
                if case .sensitivity(let spec) = effect {
                    if abs(spec.factor - 1.0) > 0.05 {
                        sensitivityDirections.append((bundle.agent, spec.factor - 1.0))
                    }
                }
            }
        }
        
        // Find conflicting pairs
        for i in 0..<sensitivityDirections.count {
            for j in (i+1)..<sensitivityDirections.count {
                let a = sensitivityDirections[i]
                let b = sensitivityDirections[j]
                
                // Opposite signs = conflict
                if a.direction * b.direction < 0 {
                    conflicts.append(EffectConflict(
                        agent1: a.agent,
                        agent2: b.agent,
                        effectType: .sensitivity,
                        description: "\(a.agent) wants \(a.direction > 0 ? "less" : "more") sensitivity, \(b.agent) wants opposite"
                    ))
                }
            }
        }
    }
}

/// Conflict resolution strategy
public enum ConflictResolutionStrategy: String, Sendable {
    /// Weight by confidence scores
    case confidenceWeighted = "confidence_weighted"
    
    /// Use most recent bundle only
    case mostRecent = "most_recent"
    
    /// Use most conservative (closest to identity)
    case mostConservative = "most_conservative"
}

/// Result of composing multiple effect bundles
public struct ComposedEffect: Sendable {
    /// Final composed modifier
    public let modifier: EffectModifier
    
    /// Agents that contributed
    public let contributingAgents: [String]
    
    /// Detected conflicts
    public let conflicts: [EffectConflict]
    
    /// Whether there are unresolved conflicts
    public var hasConflicts: Bool {
        !conflicts.isEmpty
    }
}

/// Detected conflict between agents
public struct EffectConflict: Sendable {
    public let agent1: String
    public let agent2: String
    public let effectType: EffectType
    public let description: String
}

// MARK: - Learning Agent Adapters (ALG-EFF-062)

/// Adapter for Activity agents to produce EffectBundles
public struct ActivityEffectAdapter: EffectProvider {
    public let providerId: String
    public let displayName: String
    public let isEnabled: Bool
    
    private let activityType: String
    private let sensitivityFactor: Double
    private let durationMinutes: Int
    private let confidence: Double
    
    public init(
        activityType: String,
        sensitivityFactor: Double,
        durationMinutes: Int,
        confidence: Double,
        isEnabled: Bool = true
    ) {
        self.providerId = "activity.\(activityType.lowercased())"
        self.displayName = "\(activityType) Agent"
        self.activityType = activityType
        self.sensitivityFactor = sensitivityFactor
        self.durationMinutes = durationMinutes
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    public func generateEffects(context: EffectContext) async -> EffectBundle? {
        // Only generate if activity is in context
        guard context.recentActivities.contains(where: { $0.lowercased().contains(activityType.lowercased()) }) else {
            return nil
        }
        
        let now = context.timestamp
        let validUntil = now.addingTimeInterval(Double(durationMinutes * 60))
        
        let effects: [AnyEffect] = [
            .sensitivity(SensitivityEffectSpec(
                confidence: confidence,
                factor: sensitivityFactor,
                durationMinutes: durationMinutes
            ))
        ]
        
        return EffectBundle(
            agent: providerId,
            timestamp: now,
            validFrom: now,
            validUntil: validUntil,
            effects: effects,
            reason: "\(activityType) detected",
            privacyTier: context.preferences.privacyTier,
            confidence: confidence
        )
    }
}

/// Adapter for Circadian agents to produce EffectBundles
public struct CircadianEffectAdapter: EffectProvider {
    public let providerId = "circadian"
    public let displayName = "Circadian Agent"
    public var isEnabled: Bool = true
    
    private let hourlySensitivityFactors: [Int: Double]  // Hour -> factor
    private let confidence: Double
    
    public init(
        hourlySensitivityFactors: [Int: Double],
        confidence: Double = 0.7,
        isEnabled: Bool = true
    ) {
        self.hourlySensitivityFactors = hourlySensitivityFactors
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    public func generateEffects(context: EffectContext) async -> EffectBundle? {
        let hour = Calendar.current.component(.hour, from: context.timestamp)
        
        guard let factor = hourlySensitivityFactors[hour], abs(factor - 1.0) > 0.01 else {
            return nil
        }
        
        let now = context.timestamp
        let validUntil = now.addingTimeInterval(3600)  // 1 hour
        
        let effects: [AnyEffect] = [
            .sensitivity(SensitivityEffectSpec(
                confidence: confidence,
                factor: factor,
                durationMinutes: 60
            ))
        ]
        
        return EffectBundle(
            agent: providerId,
            timestamp: now,
            validFrom: now,
            validUntil: validUntil,
            effects: effects,
            reason: "Circadian adjustment for \(hour):00",
            privacyTier: .onDeviceOnly,
            confidence: confidence
        )
    }
}

/// Adapter for Illness agents to produce EffectBundles
public struct IllnessEffectAdapter: EffectProvider {
    public let providerId = "illness"
    public let displayName = "Illness Agent"
    public var isEnabled: Bool = true
    
    private let sensitivityFactor: Double
    private let severity: String
    private let confidence: Double
    
    public init(
        severity: String,
        sensitivityFactor: Double,
        confidence: Double = 0.75,
        isEnabled: Bool = true
    ) {
        self.severity = severity
        self.sensitivityFactor = sensitivityFactor
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    public func generateEffects(context: EffectContext) async -> EffectBundle? {
        // Only generate if illness override is active
        guard context.activeOverrides.contains(where: { 
            $0.lowercased().contains("illness") || $0.lowercased().contains("sick") 
        }) else {
            return nil
        }
        
        let now = context.timestamp
        let validUntil = now.addingTimeInterval(8 * 3600)  // 8 hours
        
        let effects: [AnyEffect] = [
            .sensitivity(SensitivityEffectSpec(
                confidence: confidence,
                factor: sensitivityFactor,
                durationMinutes: 480
            ))
        ]
        
        return EffectBundle(
            agent: providerId,
            timestamp: now,
            validFrom: now,
            validUntil: validUntil,
            effects: effects,
            reason: "Illness mode (\(severity))",
            privacyTier: .onDeviceOnly,
            confidence: confidence
        )
    }
}

/// Adapter for Meal Pattern agents to produce EffectBundles
public struct MealEffectAdapter: EffectProvider {
    public let providerId: String
    public let displayName: String
    public var isEnabled: Bool = true
    
    private let mealType: String
    private let absorptionMultiplier: Double
    private let confidence: Double
    
    public init(
        mealType: String,
        absorptionMultiplier: Double,
        confidence: Double = 0.7,
        isEnabled: Bool = true
    ) {
        self.providerId = "meal.\(mealType.lowercased())"
        self.displayName = "\(mealType) Meal Agent"
        self.mealType = mealType
        self.absorptionMultiplier = absorptionMultiplier
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    public func generateEffects(context: EffectContext) async -> EffectBundle? {
        // Check if it's typical meal time
        let hour = Calendar.current.component(.hour, from: context.timestamp)
        
        let isMealTime: Bool
        switch mealType.lowercased() {
        case "breakfast": isMealTime = (6...10).contains(hour)
        case "lunch": isMealTime = (11...14).contains(hour)
        case "dinner": isMealTime = (17...21).contains(hour)
        default: isMealTime = false
        }
        
        guard isMealTime else { return nil }
        
        let now = context.timestamp
        let validUntil = now.addingTimeInterval(4 * 3600)  // 4 hours
        
        let effects: [AnyEffect] = [
            .absorption(AbsorptionEffectSpec(
                confidence: confidence,
                rateMultiplier: absorptionMultiplier,
                durationMinutes: 240
            ))
        ]
        
        return EffectBundle(
            agent: providerId,
            timestamp: now,
            validFrom: now,
            validUntil: validUntil,
            effects: effects,
            reason: "Approaching typical \(mealType.lowercased()) time",
            privacyTier: .onDeviceOnly,
            confidence: confidence
        )
    }
}

/// Adapter for Custom Hunch agents to produce EffectBundles
public struct HunchEffectAdapter: EffectProvider {
    public let providerId: String
    public let displayName: String
    public var isEnabled: Bool = true
    
    private let sensitivityFactor: Double?
    private let durationMinutes: Int
    private let triggerKeyword: String
    private let confidence: Double
    
    public init(
        name: String,
        triggerKeyword: String,
        sensitivityFactor: Double?,
        durationMinutes: Int,
        confidence: Double,
        isEnabled: Bool = true
    ) {
        self.providerId = "hunch.\(name.lowercased().replacingOccurrences(of: " ", with: "_"))"
        self.displayName = name
        self.triggerKeyword = triggerKeyword
        self.sensitivityFactor = sensitivityFactor
        self.durationMinutes = durationMinutes
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    public func generateEffects(context: EffectContext) async -> EffectBundle? {
        // Check if trigger matches any active override or activity
        let triggered = context.activeOverrides.contains(where: { 
            $0.lowercased().contains(triggerKeyword.lowercased()) 
        }) || context.recentActivities.contains(where: { 
            $0.lowercased().contains(triggerKeyword.lowercased()) 
        })
        
        guard triggered else { return nil }
        
        var effects: [AnyEffect] = []
        
        if let factor = sensitivityFactor, abs(factor - 1.0) > 0.01 {
            effects.append(.sensitivity(SensitivityEffectSpec(
                confidence: confidence,
                factor: factor,
                durationMinutes: durationMinutes
            )))
        }
        
        guard !effects.isEmpty else { return nil }
        
        let now = context.timestamp
        let validUntil = now.addingTimeInterval(Double(durationMinutes * 60))
        
        return EffectBundle(
            agent: providerId,
            timestamp: now,
            validFrom: now,
            validUntil: validUntil,
            effects: effects,
            reason: "\(displayName) activated",
            privacyTier: context.preferences.privacyTier,
            confidence: confidence
        )
    }
}
