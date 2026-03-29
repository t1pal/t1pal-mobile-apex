// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MealAbsorptionAgent.swift
// T1PalAlgorithm
//
// MealAbsorption agent prototype - fat/protein slow absorption effects
// Backlog: EFFECT-AGENT-003
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md, AGENT-PRIVACY-GUARANTEES.md

import Foundation

// MARK: - MealAbsorption Agent

/// Agent that adjusts carb absorption based on meal composition
///
/// High-fat and high-protein meals slow carbohydrate absorption:
/// 1. Fat delays gastric emptying → slower glucose rise
/// 2. Protein converts to glucose over 3-5 hours (gluconeogenesis)
/// 3. Complex carbs absorb slower than simple sugars
///
/// This agent:
/// 1. Analyzes meal composition (fat, protein, fiber, GI)
/// 2. Adjusts absorption rate multiplier
/// 3. Extends absorption duration for protein conversion
/// 4. Predicts delayed glucose rise
///
/// Privacy Tier: configurable (user chooses what syncs)
public actor MealAbsorptionAgent: EffectAgent {
    
    public nonisolated let agentId = "mealAbsorption"
    public nonisolated let name = "MealAbsorption"
    public nonisolated let description = "Meal composition-based absorption adjustment"
    public nonisolated let privacyTier: PrivacyTier = .configurable
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Minimum fat grams to trigger slow absorption
        public let minFatGrams: Double
        
        /// Minimum protein grams to trigger extended absorption
        public let minProteinGrams: Double
        
        /// Base absorption slowdown per gram of fat
        public let fatSlowdownPerGram: Double
        
        /// Protein-to-glucose conversion rate (% of protein as carbs)
        public let proteinConversionRate: Double
        
        /// Hours over which protein converts to glucose
        public let proteinConversionHours: Double
        
        /// Maximum absorption slowdown (minimum multiplier)
        public let maxSlowdown: Double
        
        /// Confidence score for effects
        public let confidence: Double
        
        public init(
            minFatGrams: Double = 10,
            minProteinGrams: Double = 20,
            fatSlowdownPerGram: Double = 0.02,
            proteinConversionRate: Double = 0.5,
            proteinConversionHours: Double = 4,
            maxSlowdown: Double = 0.3,
            confidence: Double = 0.7
        ) {
            self.minFatGrams = minFatGrams
            self.minProteinGrams = minProteinGrams
            self.fatSlowdownPerGram = fatSlowdownPerGram
            self.proteinConversionRate = proteinConversionRate
            self.proteinConversionHours = proteinConversionHours
            self.maxSlowdown = maxSlowdown
            self.confidence = confidence
        }
        
        public static let `default` = Configuration()
        
        /// For high-fat meals (pizza, burgers)
        public static let highFat = Configuration(
            minFatGrams: 5,
            fatSlowdownPerGram: 0.025,
            maxSlowdown: 0.25,
            confidence: 0.75
        )
        
        /// For high-protein meals (steak, chicken)
        public static let highProtein = Configuration(
            minProteinGrams: 15,
            proteinConversionRate: 0.55,
            proteinConversionHours: 5,
            confidence: 0.7
        )
    }
    
    private let config: Configuration
    private var lastMealTime: Date?
    private var activeMealEffects: [UUID: MealEffectInfo] = [:]
    
    public init(config: Configuration = .default) {
        self.config = config
    }
    
    // MARK: - Meal Info Tracking
    
    private struct MealEffectInfo: Sendable {
        let mealTime: Date
        let carbGrams: Double
        let fatGrams: Double
        let proteinGrams: Double
        let bundleId: UUID
    }
    
    // MARK: - Evaluation
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        // Check for recent carb entry that might indicate a meal
        guard let recentMeal = findRecentMeal(in: context) else {
            return nil
        }
        
        // Only process new meals (not already tracked)
        let mealKey = recentMeal.date.timeIntervalSince1970
        let existingMeal = activeMealEffects.values.first { 
            abs($0.mealTime.timeIntervalSince1970 - mealKey) < 300 // Within 5 min
        }
        if existingMeal != nil {
            return nil
        }
        
        // Analyze meal composition
        let composition = analyzeMealComposition(carbs: recentMeal.grams)
        
        // Check if meal warrants adjustment
        guard shouldAdjustAbsorption(composition: composition) else {
            return nil
        }
        
        // Create effect bundle
        let bundle = createMealBundle(composition: composition)
        
        // Track this meal
        activeMealEffects[bundle.id] = MealEffectInfo(
            mealTime: recentMeal.date,
            carbGrams: composition.carbs,
            fatGrams: composition.fat,
            proteinGrams: composition.protein,
            bundleId: bundle.id
        )
        lastMealTime = recentMeal.date
        
        // Clean up old meal effects
        cleanupOldMeals()
        
        return bundle
    }
    
    private func findRecentMeal(in context: AgentContext) -> AgentCarbEntry? {
        // Find carb entry in last 15 minutes that's substantial enough to be a meal
        let fifteenMinutesAgo = Date().addingTimeInterval(-15 * 60)
        
        return context.recentCarbs.first { entry in
            entry.date > fifteenMinutesAgo && entry.grams >= 15
        }
    }
    
    // MARK: - Meal Composition Analysis
    
    /// Estimated meal composition (in practice would come from food database)
    public struct MealComposition: Sendable {
        public let carbs: Double
        public let fat: Double
        public let protein: Double
        public let fiber: Double
        public let glycemicIndex: GlycemicCategory
        
        public init(
            carbs: Double,
            fat: Double = 0,
            protein: Double = 0,
            fiber: Double = 0,
            glycemicIndex: GlycemicCategory = .medium
        ) {
            self.carbs = carbs
            self.fat = fat
            self.protein = protein
            self.fiber = fiber
            self.glycemicIndex = glycemicIndex
        }
    }
    
    public enum GlycemicCategory: String, Sendable, Codable {
        case low = "low"         // < 55 GI
        case medium = "medium"   // 55-69 GI
        case high = "high"       // >= 70 GI
        
        public var absorptionMultiplier: Double {
            switch self {
            case .low: return 0.7
            case .medium: return 1.0
            case .high: return 1.3
            }
        }
    }
    
    private func analyzeMealComposition(carbs: Double) -> MealComposition {
        // In production, this would query a food database or use ML
        // For prototype, estimate based on typical meal ratios
        
        // Assume typical mixed meal has ~30% fat, ~25% protein by calories
        // Carbs = 4 cal/g, Fat = 9 cal/g, Protein = 4 cal/g
        let carbCalories = carbs * 4
        let estimatedTotalCalories = carbCalories / 0.45  // Carbs ~45% of calories
        
        let fatCalories = estimatedTotalCalories * 0.30
        let proteinCalories = estimatedTotalCalories * 0.25
        
        let estimatedFat = fatCalories / 9
        let estimatedProtein = proteinCalories / 4
        let estimatedFiber = carbs * 0.1  // ~10% of carbs as fiber
        
        return MealComposition(
            carbs: carbs,
            fat: estimatedFat,
            protein: estimatedProtein,
            fiber: estimatedFiber,
            glycemicIndex: .medium
        )
    }
    
    private func shouldAdjustAbsorption(composition: MealComposition) -> Bool {
        return composition.fat >= config.minFatGrams ||
               composition.protein >= config.minProteinGrams
    }
    
    // MARK: - Bundle Creation
    
    private func createMealBundle(composition: MealComposition) -> EffectBundle {
        var effects: [AnyEffect] = []
        
        // Calculate absorption slowdown based on fat content
        let fatSlowdown = min(
            composition.fat * config.fatSlowdownPerGram,
            1.0 - config.maxSlowdown
        )
        let absorptionMultiplier = max(1.0 - fatSlowdown, config.maxSlowdown)
        
        // Adjust for glycemic index
        let finalMultiplier = absorptionMultiplier * composition.glycemicIndex.absorptionMultiplier
        
        // Absorption effect - slower carb absorption
        let absorptionDuration = Int(90 + (composition.fat * 2)) // Base 90 min + 2 min per gram fat
        let absorption = AbsorptionEffectSpec(
            confidence: config.confidence,
            rateMultiplier: finalMultiplier,
            durationMinutes: min(absorptionDuration, 240) // Cap at 4 hours
        )
        effects.append(.absorption(absorption))
        
        // If significant protein, add delayed glucose rise
        if composition.protein >= config.minProteinGrams {
            let proteinGlucose = createProteinGlucoseEffect(composition: composition)
            effects.append(.glucose(proteinGlucose))
        }
        
        // Sensitivity might decrease slightly with large meals
        if composition.carbs >= 60 {
            let sensitivity = SensitivityEffectSpec(
                confidence: config.confidence * 0.7,
                factor: 1.1, // Slightly less sensitive after large meal
                durationMinutes: 120
            )
            effects.append(.sensitivity(sensitivity))
        }
        
        let now = Date()
        let duration = max(absorptionDuration, Int(config.proteinConversionHours * 60))
        
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(Double(duration) * 60),
            effects: effects,
            reason: "Meal with \(Int(composition.fat))g fat, \(Int(composition.protein))g protein",
            privacyTier: privacyTier,
            confidence: config.confidence
        )
    }
    
    private func createProteinGlucoseEffect(composition: MealComposition) -> GlucoseEffectSpec {
        // Protein converts to glucose over several hours
        // ~50% of protein (in grams) becomes glucose equivalent
        let glucoseFromProtein = composition.protein * config.proteinConversionRate
        let conversionMinutes = Int(config.proteinConversionHours * 60)
        
        // Spread glucose rise over conversion period, peaking at 60%
        var series: [GlucoseEffectSpec.GlucoseEffectPoint] = []
        let steps = 6
        let stepMinutes = conversionMinutes / steps
        
        for i in 0...steps {
            let offset = i * stepMinutes
            let progress = Double(i) / Double(steps)
            
            // Bell curve: peaks around 60% of duration
            let peakProgress = 0.6
            let normalizedProgress = abs(progress - peakProgress) / peakProgress
            let factor = 1.0 - (normalizedProgress * normalizedProgress)
            
            // Convert to mg/dL (rough: 1g glucose ≈ 4 mg/dL rise for average person)
            let bgDelta = glucoseFromProtein * 4 * factor * 0.3 // Dampen effect
            
            series.append(.init(minuteOffset: offset, bgDelta: bgDelta))
        }
        
        return GlucoseEffectSpec(
            confidence: config.confidence * 0.6, // Less confident about protein conversion
            series: series
        )
    }
    
    private func cleanupOldMeals() {
        let cutoff = Date().addingTimeInterval(-6 * 3600) // 6 hours
        activeMealEffects = activeMealEffects.filter { _, info in
            info.mealTime > cutoff
        }
    }
    
    // MARK: - Manual Meal Entry
    
    /// Manually enter meal composition for more accurate effects
    public func recordMeal(composition: MealComposition) -> EffectBundle? {
        guard shouldAdjustAbsorption(composition: composition) else {
            return nil
        }
        
        let bundle = createMealBundle(composition: composition)
        
        activeMealEffects[bundle.id] = MealEffectInfo(
            mealTime: Date(),
            carbGrams: composition.carbs,
            fatGrams: composition.fat,
            proteinGrams: composition.protein,
            bundleId: bundle.id
        )
        lastMealTime = Date()
        
        return bundle
    }
    
    // MARK: - State Access
    
    public var activeMealCount: Int {
        activeMealEffects.count
    }
    
    public var lastMeal: Date? {
        lastMealTime
    }
    
    public func reset() {
        activeMealEffects.removeAll()
        lastMealTime = nil
    }
}

// MARK: - Meal Type Presets

extension MealAbsorptionAgent.MealComposition {
    /// Quick pizza preset (high fat, medium carbs)
    public static func pizza(slices: Int) -> Self {
        Self(
            carbs: Double(slices) * 30,
            fat: Double(slices) * 12,
            protein: Double(slices) * 12,
            glycemicIndex: .medium
        )
    }
    
    /// Quick burger preset (high fat, high protein)
    public static func burger(withFries: Bool) -> Self {
        let baseCarbs: Double = withFries ? 70 : 30
        return Self(
            carbs: baseCarbs,
            fat: 35,
            protein: 30,
            glycemicIndex: withFries ? .high : .medium
        )
    }
    
    /// Quick pasta preset (medium fat, high carbs)
    public static func pasta(cups: Double) -> Self {
        Self(
            carbs: cups * 45,
            fat: cups * 8,
            protein: cups * 8,
            fiber: cups * 3,
            glycemicIndex: .medium
        )
    }
    
    /// Quick steak dinner preset (high protein, low carbs)
    public static func steakDinner(ozSteak: Double, withPotato: Bool) -> Self {
        let baseCarbs: Double = withPotato ? 40 : 5
        return Self(
            carbs: baseCarbs,
            fat: ozSteak * 3,
            protein: ozSteak * 7,
            glycemicIndex: withPotato ? .high : .low
        )
    }
    
    /// Simple carbs only (juice, candy)
    public static func simpleCarbs(grams: Double) -> Self {
        Self(
            carbs: grams,
            fat: 0,
            protein: 0,
            glycemicIndex: .high
        )
    }
}
