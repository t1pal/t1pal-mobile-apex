// SPDX-License-Identifier: MIT
//
// MealAbsorptionAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for MealAbsorption agent prototype
// Backlog: EFFECT-AGENT-003

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("MealAbsorption Agent")
struct MealAbsorptionAgentTests {
    
    // MARK: - Agent Metadata Tests
    
    @Test("MealAbsorption has correct metadata")
    func testAgentMetadata() async {
        let agent = MealAbsorptionAgent()
        
        #expect(agent.agentId == "mealAbsorption")
        #expect(agent.name == "MealAbsorption")
        #expect(agent.privacyTier == .configurable)
    }
    
    @Test("MealAbsorption is configurable privacy tier")
    func testPrivacyTier() async {
        let agent = MealAbsorptionAgent()
        
        // Configurable tier syncs effects by default
        #expect(agent.privacyTier.syncsEffects)
        // But not reason by default
        #expect(!agent.privacyTier.syncsReason)
    }
    
    // MARK: - Manual Meal Recording Tests
    
    @Test("Record high-fat meal creates absorption effect")
    func testHighFatMeal() async {
        let agent = MealAbsorptionAgent()
        
        let composition = MealAbsorptionAgent.MealComposition(
            carbs: 60,
            fat: 25,
            protein: 20
        )
        
        let bundle = await agent.recordMeal(composition: composition)
        
        #expect(bundle != nil)
        #expect(bundle?.agent == "mealAbsorption")
        
        let types = bundle?.effects.map(\.type) ?? []
        #expect(types.contains(.absorption))
    }
    
    @Test("Record high-protein meal creates glucose effect")
    func testHighProteinMeal() async {
        let agent = MealAbsorptionAgent()
        
        let composition = MealAbsorptionAgent.MealComposition(
            carbs: 40,
            fat: 15,
            protein: 40
        )
        
        let bundle = await agent.recordMeal(composition: composition)
        
        #expect(bundle != nil)
        
        let types = bundle?.effects.map(\.type) ?? []
        #expect(types.contains(.absorption))
        #expect(types.contains(.glucose)) // Protein glucose conversion
    }
    
    @Test("Simple carbs meal returns nil")
    func testSimpleCarbsNoEffect() async {
        let agent = MealAbsorptionAgent()
        
        // Low fat, low protein - no adjustment needed
        let composition = MealAbsorptionAgent.MealComposition.simpleCarbs(grams: 30)
        
        let bundle = await agent.recordMeal(composition: composition)
        
        #expect(bundle == nil)
    }
    
    @Test("Large meal adds sensitivity effect")
    func testLargeMealSensitivity() async {
        let agent = MealAbsorptionAgent()
        
        // Large meal (>= 60g carbs)
        let composition = MealAbsorptionAgent.MealComposition(
            carbs: 80,
            fat: 20,
            protein: 25
        )
        
        let bundle = await agent.recordMeal(composition: composition)
        
        #expect(bundle != nil)
        
        let types = bundle?.effects.map(\.type) ?? []
        #expect(types.contains(.sensitivity))
    }
    
    // MARK: - Meal Preset Tests
    
    @Test("Pizza preset creates correct composition")
    func testPizzaPreset() {
        let pizza = MealAbsorptionAgent.MealComposition.pizza(slices: 2)
        
        #expect(pizza.carbs == 60)
        #expect(pizza.fat == 24)
        #expect(pizza.protein == 24)
        #expect(pizza.glycemicIndex == .medium)
    }
    
    @Test("Burger with fries has high GI")
    func testBurgerPreset() {
        let burger = MealAbsorptionAgent.MealComposition.burger(withFries: true)
        
        #expect(burger.carbs == 70)
        #expect(burger.glycemicIndex == .high)
    }
    
    @Test("Steak dinner without potato has low GI")
    func testSteakPreset() {
        let steak = MealAbsorptionAgent.MealComposition.steakDinner(ozSteak: 8, withPotato: false)
        
        #expect(steak.carbs == 5)
        #expect(steak.protein == 56)
        #expect(steak.glycemicIndex == .low)
    }
    
    @Test("Pasta preset scales with cups")
    func testPastaPreset() {
        let pasta = MealAbsorptionAgent.MealComposition.pasta(cups: 2)
        
        #expect(pasta.carbs == 90)
        #expect(pasta.fiber == 6)
    }
    
    // MARK: - Absorption Effect Tests
    
    @Test("Fat slows absorption")
    func testFatSlowsAbsorption() async {
        let agent = MealAbsorptionAgent()
        
        let highFatMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 40,
            protein: 20
        )
        
        let bundle = await agent.recordMeal(composition: highFatMeal)
        
        let absorptionEffect = bundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(absorptionEffect != nil)
        // High fat should slow absorption (multiplier < 1)
        #expect(absorptionEffect!.rateMultiplier < 1.0)
    }
    
    @Test("Absorption respects minimum bound")
    func testAbsorptionMinimumBound() async {
        let agent = MealAbsorptionAgent()
        
        // Extremely high fat meal
        let extremeFatMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 100, // Very high
            protein: 20
        )
        
        let bundle = await agent.recordMeal(composition: extremeFatMeal)
        
        let absorptionEffect = bundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(absorptionEffect != nil)
        // Should be bounded at minimum 0.2
        #expect(absorptionEffect!.rateMultiplier >= 0.2)
    }
    
    @Test("High GI increases absorption rate")
    func testHighGIFasterAbsorption() async {
        let agent = MealAbsorptionAgent()
        
        // Same fat but high GI
        let highGIMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 15,
            protein: 10,
            glycemicIndex: .high
        )
        
        let lowGIMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 15,
            protein: 10,
            glycemicIndex: .low
        )
        
        let highGIBundle = await agent.recordMeal(composition: highGIMeal)
        await agent.reset()
        let lowGIBundle = await agent.recordMeal(composition: lowGIMeal)
        
        let highGIAbsorption = highGIBundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        let lowGIAbsorption = lowGIBundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(highGIAbsorption != nil)
        #expect(lowGIAbsorption != nil)
        // High GI should have faster absorption
        #expect(highGIAbsorption!.rateMultiplier > lowGIAbsorption!.rateMultiplier)
    }
    
    // MARK: - Protein Conversion Tests
    
    @Test("Protein creates delayed glucose effect")
    func testProteinGlucoseConversion() async {
        let agent = MealAbsorptionAgent()
        
        let highProteinMeal = MealAbsorptionAgent.MealComposition(
            carbs: 30,
            fat: 15,
            protein: 50
        )
        
        let bundle = await agent.recordMeal(composition: highProteinMeal)
        
        let glucoseEffect = bundle?.effects.compactMap { effect -> GlucoseEffectSpec? in
            if case .glucose(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(glucoseEffect != nil)
        #expect(glucoseEffect!.series.count > 1)
        
        // Should have delayed peak (not at start)
        let firstDelta = glucoseEffect!.series.first?.bgDelta ?? 0
        let middleDelta = glucoseEffect!.series[glucoseEffect!.series.count / 2].bgDelta
        #expect(middleDelta > firstDelta)
    }
    
    // MARK: - Configuration Tests
    
    @Test("Default configuration values")
    func testDefaultConfiguration() {
        let config = MealAbsorptionAgent.Configuration.default
        
        #expect(config.minFatGrams == 10)
        #expect(config.minProteinGrams == 20)
        #expect(config.proteinConversionRate == 0.5)
        #expect(config.confidence == 0.7)
    }
    
    @Test("High fat configuration is more sensitive to fat")
    func testHighFatConfiguration() {
        let config = MealAbsorptionAgent.Configuration.highFat
        
        #expect(config.minFatGrams < MealAbsorptionAgent.Configuration.default.minFatGrams)
        #expect(config.fatSlowdownPerGram > MealAbsorptionAgent.Configuration.default.fatSlowdownPerGram)
    }
    
    @Test("High protein configuration extends conversion time")
    func testHighProteinConfiguration() {
        let config = MealAbsorptionAgent.Configuration.highProtein
        
        #expect(config.proteinConversionHours > MealAbsorptionAgent.Configuration.default.proteinConversionHours)
    }
    
    // MARK: - State Management Tests
    
    @Test("Active meal count tracks meals")
    func testActiveMealCount() async {
        let agent = MealAbsorptionAgent()
        
        let initialCount = await agent.activeMealCount
        #expect(initialCount == 0)
        
        let pizza = MealAbsorptionAgent.MealComposition.pizza(slices: 2)
        _ = await agent.recordMeal(composition: pizza)
        
        let afterMealCount = await agent.activeMealCount
        #expect(afterMealCount == 1)
    }
    
    @Test("Last meal time is tracked")
    func testLastMealTime() async {
        let agent = MealAbsorptionAgent()
        
        let initialTime = await agent.lastMeal
        #expect(initialTime == nil)
        
        let pizza = MealAbsorptionAgent.MealComposition.pizza(slices: 2)
        _ = await agent.recordMeal(composition: pizza)
        
        let afterMealTime = await agent.lastMeal
        #expect(afterMealTime != nil)
    }
    
    @Test("Reset clears state")
    func testReset() async {
        let agent = MealAbsorptionAgent()
        
        let pizza = MealAbsorptionAgent.MealComposition.pizza(slices: 2)
        _ = await agent.recordMeal(composition: pizza)
        
        await agent.reset()
        
        let count = await agent.activeMealCount
        let lastMeal = await agent.lastMeal
        
        #expect(count == 0)
        #expect(lastMeal == nil)
    }
    
    // MARK: - Glycemic Index Tests
    
    @Test("GI categories have correct multipliers")
    func testGIMultipliers() {
        #expect(MealAbsorptionAgent.GlycemicCategory.low.absorptionMultiplier == 0.7)
        #expect(MealAbsorptionAgent.GlycemicCategory.medium.absorptionMultiplier == 1.0)
        #expect(MealAbsorptionAgent.GlycemicCategory.high.absorptionMultiplier == 1.3)
    }
    
    // MARK: - Integration Tests
    
    @Test("MealAbsorption integrates with registry")
    func testRegistryIntegration() async {
        let registry = EffectAgentRegistry()
        let agent = MealAbsorptionAgent()
        
        await registry.register(agent)
        
        let retrieved = await registry.agent(for: "mealAbsorption")
        #expect(retrieved != nil)
        #expect(retrieved?.agentId == "mealAbsorption")
    }
    
    @Test("All three agents in registry")
    func testAllAgentsInRegistry() async {
        let registry = EffectAgentRegistry()
        
        await registry.register(BreakfastBoostAgent())
        await registry.register(ActivityModeAgent())
        await registry.register(MealAbsorptionAgent())
        
        let agents = await registry.allAgents()
        #expect(agents.count == 3)
    }
    
    // MARK: - Bundle Validity Tests
    
    @Test("Bundle has valid time window")
    func testBundleTimeWindow() async {
        let agent = MealAbsorptionAgent()
        
        let pizza = MealAbsorptionAgent.MealComposition.pizza(slices: 2)
        let bundle = await agent.recordMeal(composition: pizza)
        
        #expect(bundle != nil)
        #expect(bundle!.isValid)
        #expect(bundle!.validUntil > bundle!.validFrom)
        #expect(bundle!.duration > 0)
    }
    
    @Test("Bundle duration extends for high fat")
    func testDurationExtendsWithFat() async {
        let agent = MealAbsorptionAgent()
        
        let lowFatMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 12, // Just above min threshold
            protein: 10
        )
        
        let moderateFatMeal = MealAbsorptionAgent.MealComposition(
            carbs: 50,
            fat: 30, // More fat = longer duration
            protein: 10
        )
        
        let lowFatBundle = await agent.recordMeal(composition: lowFatMeal)
        await agent.reset()
        let moderateFatBundle = await agent.recordMeal(composition: moderateFatMeal)
        
        #expect(lowFatBundle != nil)
        #expect(moderateFatBundle != nil)
        
        // Both should have valid durations
        #expect(lowFatBundle!.duration > 0)
        #expect(moderateFatBundle!.duration > 0)
        
        // Get absorption effects to compare duration
        let lowFatAbsorption = lowFatBundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        let moderateFatAbsorption = moderateFatBundle?.effects.compactMap { effect -> AbsorptionEffectSpec? in
            if case .absorption(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(lowFatAbsorption != nil)
        #expect(moderateFatAbsorption != nil)
        // More fat = longer absorption duration
        #expect(moderateFatAbsorption!.durationMinutes > lowFatAbsorption!.durationMinutes)
    }
}
