// SPDX-License-Identifier: MIT
//
// BreakfastBoostAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for BreakfastBoost agent prototype
// Backlog: EFFECT-AGENT-001

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("BreakfastBoost Agent")
struct BreakfastBoostAgentTests {
    
    // MARK: - EffectBundle Tests
    
    @Test("EffectBundle validates correctly")
    func testBundleValidation() {
        let now = Date()
        let bundle = EffectBundle(
            agent: "test",
            validFrom: now,
            validUntil: now.addingTimeInterval(3600),
            effects: [],
            confidence: 0.8
        )
        
        #expect(bundle.validate().isEmpty)
        #expect(bundle.isValid)
        #expect(bundle.duration == 3600)
    }
    
    @Test("EffectBundle rejects invalid duration")
    func testBundleRejectsLongDuration() {
        let now = Date()
        let bundle = EffectBundle(
            agent: "test",
            validFrom: now,
            validUntil: now.addingTimeInterval(25 * 3600), // 25 hours
            effects: [],
            confidence: 0.8
        )
        
        let errors = bundle.validate()
        #expect(errors.contains { $0.contains("24 hours") })
    }
    
    @Test("EffectBundle rejects empty agent name")
    func testBundleRejectsEmptyAgent() {
        let now = Date()
        let bundle = EffectBundle(
            agent: "",
            validFrom: now,
            validUntil: now.addingTimeInterval(3600),
            effects: [],
            confidence: 0.8
        )
        
        let errors = bundle.validate()
        #expect(errors.contains { $0.contains("empty") })
    }
    
    // MARK: - Privacy Tier Tests
    
    @Test("Transparent tier syncs everything")
    func testTransparentTier() {
        #expect(PrivacyTier.transparent.syncsEffects)
        #expect(PrivacyTier.transparent.syncsReason)
    }
    
    @Test("PrivacyPreserving tier syncs effects only")
    func testPrivacyPreservingTier() {
        #expect(PrivacyTier.privacyPreserving.syncsEffects)
        #expect(!PrivacyTier.privacyPreserving.syncsReason)
    }
    
    @Test("OnDeviceOnly tier syncs nothing")
    func testOnDeviceOnlyTier() {
        #expect(!PrivacyTier.onDeviceOnly.syncsEffects)
        #expect(!PrivacyTier.onDeviceOnly.syncsReason)
    }
    
    @Test("toSyncRepresentation respects privacy tier")
    func testSyncRepresentation() {
        let now = Date()
        let bundle = EffectBundle(
            agent: "test",
            validFrom: now,
            validUntil: now.addingTimeInterval(3600),
            effects: [],
            reason: "Secret reason",
            privacyTier: .privacyPreserving,
            confidence: 0.8
        )
        
        let synced = bundle.toSyncRepresentation()
        #expect(synced != nil)
        #expect(synced?.reason == nil) // Reason stripped
    }
    
    @Test("OnDeviceOnly returns nil sync representation")
    func testOnDeviceOnlyNoSync() {
        let now = Date()
        let bundle = EffectBundle(
            agent: "test",
            validFrom: now,
            validUntil: now.addingTimeInterval(3600),
            effects: [],
            privacyTier: .onDeviceOnly,
            confidence: 0.8
        )
        
        #expect(bundle.toSyncRepresentation() == nil)
    }
    
    // MARK: - Safety Bounds Tests
    
    @Test("GlucoseEffectSpec bounds delta to ±50")
    func testGlucoseEffectBounds() {
        let point1 = GlucoseEffectSpec.GlucoseEffectPoint(minuteOffset: 0, bgDelta: 100)
        let point2 = GlucoseEffectSpec.GlucoseEffectPoint(minuteOffset: 0, bgDelta: -100)
        
        #expect(point1.bgDelta == 50)  // Capped at 50
        #expect(point2.bgDelta == -50) // Capped at -50
    }
    
    @Test("SensitivityEffectSpec bounds factor to 0.2-2.0")
    func testSensitivityEffectBounds() {
        let low = SensitivityEffectSpec(confidence: 0.8, factor: 0.1, durationMinutes: 60)
        let high = SensitivityEffectSpec(confidence: 0.8, factor: 5.0, durationMinutes: 60)
        
        #expect(low.factor == 0.2)  // Capped at 0.2
        #expect(high.factor == 2.0) // Capped at 2.0
    }
    
    @Test("AbsorptionEffectSpec bounds multiplier to 0.2-3.0")
    func testAbsorptionEffectBounds() {
        let low = AbsorptionEffectSpec(confidence: 0.8, rateMultiplier: 0.1, durationMinutes: 60)
        let high = AbsorptionEffectSpec(confidence: 0.8, rateMultiplier: 5.0, durationMinutes: 60)
        
        #expect(low.rateMultiplier == 0.2)  // Capped at 0.2
        #expect(high.rateMultiplier == 3.0) // Capped at 3.0
    }
    
    @Test("Confidence bounds to 0-1")
    func testConfidenceBounds() {
        let effect = SensitivityEffectSpec(confidence: 1.5, factor: 1.0, durationMinutes: 60)
        #expect(effect.confidence == 1.0)
    }
    
    // MARK: - BreakfastBoost Agent Tests
    
    @Test("BreakfastBoost has correct metadata")
    func testAgentMetadata() async {
        let agent = BreakfastBoostAgent()
        
        #expect(agent.agentId == "breakfastBoost")
        #expect(agent.name == "BreakfastBoost")
        #expect(agent.privacyTier == .transparent)
    }
    
    @Test("BreakfastBoost activates in morning with rising glucose")
    func testMorningActivation() async {
        let agent = BreakfastBoostAgent()
        
        // Create morning context (8 AM) with rising glucose
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0, // Rising
            timeOfDay: morningTime,
            iob: 1.0,
            cob: 30,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle != nil)
        #expect(bundle?.agent == "breakfastBoost")
        #expect(bundle?.effects.count == 3) // sensitivity, absorption, glucose
    }
    
    @Test("BreakfastBoost does not activate in afternoon")
    func testAfternoonNoActivation() async {
        let agent = BreakfastBoostAgent()
        
        // Create afternoon context (2 PM)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        let afternoonTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: afternoonTime,
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle == nil)
    }
    
    @Test("BreakfastBoost does not activate when loop inactive")
    func testInactiveLoopNoActivation() async {
        let agent = BreakfastBoostAgent()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            isLoopActive: false
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle == nil)
    }
    
    @Test("BreakfastBoost respects cooldown period")
    func testCooldownPeriod() async {
        let agent = BreakfastBoostAgent()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        // First activation should succeed
        let bundle1 = await agent.evaluate(context: context)
        #expect(bundle1 != nil)
        
        // Second immediate activation should fail (cooldown)
        let bundle2 = await agent.evaluate(context: context)
        #expect(bundle2 == nil)
        
        // Verify was recently active
        let wasActive = await agent.wasRecentlyActive
        #expect(wasActive)
    }
    
    @Test("BreakfastBoost reset clears cooldown")
    func testReset() async {
        let agent = BreakfastBoostAgent()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        // Activate
        _ = await agent.evaluate(context: context)
        
        // Reset
        await agent.reset()
        
        // Should activate again
        let bundle = await agent.evaluate(context: context)
        #expect(bundle != nil)
    }
    
    // MARK: - Effect Bundle Contents Tests
    
    @Test("BreakfastBoost produces valid effect types")
    func testEffectTypes() async {
        let agent = BreakfastBoostAgent()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle != nil)
        
        let types = bundle?.effects.map(\.type) ?? []
        #expect(types.contains(.sensitivity))
        #expect(types.contains(.absorption))
        #expect(types.contains(.glucose))
    }
    
    @Test("BreakfastBoost sensitivity factor is aggressive")
    func testSensitivityFactor() async {
        let agent = BreakfastBoostAgent()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        
        // Find sensitivity effect
        let sensitivityEffect = bundle?.effects.compactMap { effect -> SensitivityEffectSpec? in
            if case .sensitivity(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(sensitivityEffect != nil)
        #expect(sensitivityEffect!.factor < 1.0) // More aggressive dosing
        #expect(sensitivityEffect!.factor == 0.85) // Default config
    }
    
    // MARK: - Agent Registry Tests
    
    @Test("Agent registry registers and retrieves agents")
    func testRegistry() async {
        let registry = EffectAgentRegistry()
        let agent = BreakfastBoostAgent()
        
        await registry.register(agent)
        
        let retrieved = await registry.agent(for: "breakfastBoost")
        #expect(retrieved != nil)
        #expect(retrieved?.agentId == "breakfastBoost")
    }
    
    @Test("Agent registry evaluates all agents")
    func testRegistryEvaluateAll() async {
        let registry = EffectAgentRegistry()
        await registry.registerDefaults()
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        let morningTime = calendar.date(from: components) ?? Date()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 3.0,
            timeOfDay: morningTime,
            recentCarbs: [AgentCarbEntry(date: Date(), grams: 40)],
            isLoopActive: true
        )
        
        let bundles = await registry.evaluateAll(context: context)
        #expect(!bundles.isEmpty)
    }
    
    // MARK: - Encoding/Decoding Tests
    
    @Test("EffectBundle encodes and decodes")
    func testBundleCoding() throws {
        let now = Date()
        let sensitivity = SensitivityEffectSpec(
            confidence: 0.8,
            factor: 0.85,
            durationMinutes: 90
        )
        
        let bundle = EffectBundle(
            agent: "breakfastBoost",
            validFrom: now,
            validUntil: now.addingTimeInterval(3600),
            effects: [.sensitivity(sensitivity)],
            reason: "Test",
            confidence: 0.8
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EffectBundle.self, from: data)
        
        #expect(decoded.agent == "breakfastBoost")
        #expect(decoded.effects.count == 1)
        #expect(decoded.confidence == 0.8)
    }
    
    @Test("AnyEffect encodes with type discriminator")
    func testAnyEffectCoding() throws {
        let sensitivity = SensitivityEffectSpec(
            confidence: 0.8,
            factor: 0.85,
            durationMinutes: 90
        )
        
        let anyEffect = AnyEffect.sensitivity(sensitivity)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(anyEffect)
        let json = String(data: data, encoding: .utf8)!
        
        #expect(json.contains("sensitivity"))
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyEffect.self, from: data)
        
        #expect(decoded.type == .sensitivity)
    }
}
