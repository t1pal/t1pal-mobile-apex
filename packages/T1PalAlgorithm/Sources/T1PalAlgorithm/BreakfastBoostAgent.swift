// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BreakfastBoostAgent.swift
// T1PalAlgorithm
//
// BreakfastBoost agent prototype - morning sensitivity + glucose rise
// Backlog: EFFECT-AGENT-001
// Architecture: docs/architecture/AGENT-REGISTRY-PATTERN.md
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md, AGENT-PRIVACY-GUARANTEES.md

import Foundation

// MARK: - Effect Agent Protocol

/// Protocol for agents that produce EffectBundles
public protocol EffectAgent: Sendable {
    /// Unique agent identifier
    var agentId: String { get }
    
    /// Human-readable name
    var name: String { get }
    
    /// Agent description
    var description: String { get }
    
    /// Privacy tier for this agent
    var privacyTier: PrivacyTier { get }
    
    /// Evaluate current context and optionally produce an effect bundle
    func evaluate(context: AgentContext) async -> EffectBundle?
}

// MARK: - Agent Context

/// Context provided to agents for decision making
public struct AgentContext: Sendable {
    /// Current glucose value in mg/dL
    public let currentGlucose: Double?
    
    /// Recent glucose trend (mg/dL per 5 min)
    public let glucoseTrend: Double?
    
    /// Current time of day
    public let timeOfDay: Date
    
    /// Current IOB in units
    public let iob: Double?
    
    /// Current COB in grams
    public let cob: Double?
    
    /// Recent carb entries in last hour
    public let recentCarbs: [AgentCarbEntry]
    
    /// Whether loop is currently active
    public let isLoopActive: Bool
    
    public init(
        currentGlucose: Double? = nil,
        glucoseTrend: Double? = nil,
        timeOfDay: Date = Date(),
        iob: Double? = nil,
        cob: Double? = nil,
        recentCarbs: [AgentCarbEntry] = [],
        isLoopActive: Bool = true
    ) {
        self.currentGlucose = currentGlucose
        self.glucoseTrend = glucoseTrend
        self.timeOfDay = timeOfDay
        self.iob = iob
        self.cob = cob
        self.recentCarbs = recentCarbs
        self.isLoopActive = isLoopActive
    }
    
    /// Hour of day (0-23)
    public var hour: Int {
        Calendar.current.component(.hour, from: timeOfDay)
    }
    
    /// Whether it's morning (5-10 AM)
    public var isMorning: Bool {
        hour >= 5 && hour < 10
    }
}

/// Simple carb entry for agent context (distinct from CarbModel.CarbEntry)
public struct AgentCarbEntry: Sendable {
    public let date: Date
    public let grams: Double
    
    public init(date: Date, grams: Double) {
        self.date = date
        self.grams = grams
    }
}

// MARK: - BreakfastBoost Agent

/// Agent that detects breakfast patterns and adjusts sensitivity
/// 
/// Dawn phenomenon and breakfast often require increased insulin sensitivity.
/// This agent:
/// 1. Detects morning time window (5-10 AM)
/// 2. Detects rising glucose trend
/// 3. Detects recent carb entry
/// 4. Produces sensitivity and absorption effects
///
/// Privacy Tier: transparent (all effects sync)
public actor BreakfastBoostAgent: EffectAgent {
    
    public nonisolated let agentId = "breakfastBoost"
    public nonisolated let name = "BreakfastBoost"
    public nonisolated let description = "Morning sensitivity adjustment for breakfast"
    public nonisolated let privacyTier: PrivacyTier = .transparent
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Morning window start hour
        public let morningStartHour: Int
        
        /// Morning window end hour
        public let morningEndHour: Int
        
        /// Minimum glucose rise rate to trigger (mg/dL per 5 min)
        public let minRiseRate: Double
        
        /// Sensitivity factor (< 1 = more sensitive, needs more insulin)
        public let sensitivityFactor: Double
        
        /// Absorption rate multiplier (> 1 = faster)
        public let absorptionMultiplier: Double
        
        /// Effect duration in minutes
        public let durationMinutes: Int
        
        /// Confidence score for effects
        public let confidence: Double
        
        public init(
            morningStartHour: Int = 5,
            morningEndHour: Int = 10,
            minRiseRate: Double = 2.0,
            sensitivityFactor: Double = 0.85,
            absorptionMultiplier: Double = 1.3,
            durationMinutes: Int = 90,
            confidence: Double = 0.75
        ) {
            self.morningStartHour = morningStartHour
            self.morningEndHour = morningEndHour
            self.minRiseRate = minRiseRate
            self.sensitivityFactor = sensitivityFactor
            self.absorptionMultiplier = absorptionMultiplier
            self.durationMinutes = durationMinutes
            self.confidence = confidence
        }
        
        public static let `default` = Configuration()
    }
    
    private let config: Configuration
    private var lastActivation: Date?
    private let minActivationInterval: TimeInterval = 60 * 60 // 1 hour
    
    public init(config: Configuration = .default) {
        self.config = config
    }
    
    // MARK: - Evaluation
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        // Check conditions
        guard shouldActivate(context: context) else {
            return nil
        }
        
        // Create effects
        let effects = createEffects()
        
        // Record activation
        lastActivation = Date()
        
        // Build bundle
        let now = Date()
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(Double(config.durationMinutes) * 60),
            effects: effects,
            reason: "Morning breakfast detected",
            privacyTier: privacyTier,
            confidence: config.confidence
        )
    }
    
    private func shouldActivate(context: AgentContext) -> Bool {
        // 1. Must be morning window
        let hour = context.hour
        guard hour >= config.morningStartHour && hour < config.morningEndHour else {
            return false
        }
        
        // 2. Check for rising glucose
        if let trend = context.glucoseTrend, trend < config.minRiseRate {
            // Not rising fast enough, check for recent carbs
            if context.recentCarbs.isEmpty {
                return false
            }
        }
        
        // 3. Avoid re-activation too soon
        if let lastTime = lastActivation,
           Date().timeIntervalSince(lastTime) < minActivationInterval {
            return false
        }
        
        // 4. Loop must be active
        guard context.isLoopActive else {
            return false
        }
        
        return true
    }
    
    private func createEffects() -> [AnyEffect] {
        var effects: [AnyEffect] = []
        
        // Sensitivity effect - more aggressive dosing for breakfast
        let sensitivity = SensitivityEffectSpec(
            confidence: config.confidence,
            factor: config.sensitivityFactor,
            durationMinutes: config.durationMinutes
        )
        effects.append(.sensitivity(sensitivity))
        
        // Absorption effect - faster carb absorption for breakfast
        let absorption = AbsorptionEffectSpec(
            confidence: config.confidence,
            rateMultiplier: config.absorptionMultiplier,
            durationMinutes: config.durationMinutes
        )
        effects.append(.absorption(absorption))
        
        // Glucose effect - predict rise pattern
        let glucosePoints: [GlucoseEffectSpec.GlucoseEffectPoint] = [
            .init(minuteOffset: 0, bgDelta: 0),
            .init(minuteOffset: 15, bgDelta: 10),
            .init(minuteOffset: 30, bgDelta: 20),
            .init(minuteOffset: 45, bgDelta: 25),
            .init(minuteOffset: 60, bgDelta: 20),
            .init(minuteOffset: 90, bgDelta: 10)
        ]
        let glucose = GlucoseEffectSpec(
            confidence: config.confidence * 0.8, // Slightly less confident on exact curve
            series: glucosePoints
        )
        effects.append(.glucose(glucose))
        
        return effects
    }
    
    // MARK: - State Access
    
    public var wasRecentlyActive: Bool {
        guard let lastTime = lastActivation else { return false }
        return Date().timeIntervalSince(lastTime) < minActivationInterval
    }
    
    public func reset() {
        lastActivation = nil
    }
}

// MARK: - Agent Registry Extension

/// Registry for managing effect agents
public actor EffectAgentRegistry {
    private var agents: [String: any EffectAgent] = [:]
    
    public init() {}
    
    /// Register an agent
    public func register(_ agent: any EffectAgent) {
        agents[agent.agentId] = agent
    }
    
    /// Unregister an agent
    public func unregister(_ agentId: String) {
        agents.removeValue(forKey: agentId)
    }
    
    /// Get agent by ID
    public func agent(for id: String) -> (any EffectAgent)? {
        agents[id]
    }
    
    /// Get all registered agents
    public func allAgents() -> [any EffectAgent] {
        Array(agents.values)
    }
    
    /// Evaluate all agents and collect effect bundles
    public func evaluateAll(context: AgentContext) async -> [EffectBundle] {
        var bundles: [EffectBundle] = []
        
        for agent in agents.values {
            if let bundle = await agent.evaluate(context: context) {
                bundles.append(bundle)
            }
        }
        
        return bundles
    }
    
    /// Register default agents
    public func registerDefaults() async {
        let breakfastBoost = BreakfastBoostAgent()
        register(breakfastBoost)
    }
}
