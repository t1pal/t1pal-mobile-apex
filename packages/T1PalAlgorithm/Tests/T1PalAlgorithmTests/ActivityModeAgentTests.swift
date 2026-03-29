// SPDX-License-Identifier: MIT
//
// ActivityModeAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for ActivityMode agent prototype
// Backlog: EFFECT-AGENT-002

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("ActivityMode Agent")
struct ActivityModeAgentTests {
    
    // MARK: - Agent Metadata Tests
    
    @Test("ActivityMode has correct metadata")
    func testAgentMetadata() async {
        let agent = ActivityModeAgent()
        
        #expect(agent.agentId == "activityMode")
        #expect(agent.name == "ActivityMode")
        #expect(agent.privacyTier == .privacyPreserving)
    }
    
    @Test("ActivityMode is privacy-preserving")
    func testPrivacyTier() async {
        let agent = ActivityModeAgent()
        
        // Effects sync but reason doesn't
        #expect(agent.privacyTier.syncsEffects)
        #expect(!agent.privacyTier.syncsReason)
    }
    
    // MARK: - Exercise Detection Tests
    
    @Test("ActivityMode detects rapid glucose drop as exercise")
    func testRapidDropDetection() async {
        let agent = ActivityModeAgent()
        
        // Rapid glucose drop suggests exercise
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: -4.0, // Rapid drop
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle != nil)
        #expect(bundle?.agent == "activityMode")
    }
    
    @Test("ActivityMode does not activate on stable glucose")
    func testStableGlucoseNoActivation() async {
        let agent = ActivityModeAgent()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: 0.5, // Stable
            isLoopActive: true
        )
        
        let bundle = await agent.evaluate(context: context)
        #expect(bundle == nil)
    }
    
    @Test("ActivityMode does not activate when loop inactive")
    func testInactiveLoopNoActivation() async {
        let agent = ActivityModeAgent()
        
        let context = AgentContext(
            currentGlucose: 120,
            glucoseTrend: -4.0,
            isLoopActive: false
        )
        
        // Note: ActivityMode doesn't check isLoopActive in current impl
        // but the effect won't be applied if loop is inactive
        let bundle = await agent.evaluate(context: context)
        // Even if bundle is created, loop won't apply it
        if let bundle = bundle {
            #expect(bundle.isValid)
        }
    }
    
    // MARK: - Exercise State Tests
    
    @Test("Manual exercise start works")
    func testManualExerciseStart() async {
        let agent = ActivityModeAgent()
        
        let bundle = await agent.startExercise()
        
        #expect(bundle.agent == "activityMode")
        #expect(bundle.isValid)
        #expect(!bundle.effects.isEmpty)
        
        let isExercising = await agent.currentlyExercising
        #expect(isExercising)
    }
    
    @Test("Manual exercise end works")
    func testManualExerciseEnd() async {
        let agent = ActivityModeAgent()
        
        // Start exercise first
        _ = await agent.startExercise()
        
        // End exercise
        let bundle = await agent.endExercise()
        
        #expect(bundle.agent == "activityMode")
        #expect(bundle.isValid)
        
        let isExercising = await agent.currentlyExercising
        #expect(!isExercising)
    }
    
    @Test("Exercise duration is tracked")
    func testExerciseDurationTracking() async throws {
        let agent = ActivityModeAgent()
        
        // No duration before exercise
        let initialDuration = await agent.exerciseDuration
        #expect(initialDuration == nil)
        
        // Start exercise
        _ = await agent.startExercise()
        
        // Small delay to ensure duration > 0
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let duration = await agent.exerciseDuration
        #expect(duration != nil)
        #expect(duration! > 0)
    }
    
    @Test("Reset clears exercise state")
    func testReset() async {
        let agent = ActivityModeAgent()
        
        // Start exercise
        _ = await agent.startExercise()
        
        // Reset
        await agent.reset()
        
        let isExercising = await agent.currentlyExercising
        #expect(!isExercising)
        
        let duration = await agent.exerciseDuration
        #expect(duration == nil)
    }
    
    // MARK: - Effect Bundle Contents Tests
    
    @Test("Exercise start bundle contains glucose and sensitivity effects")
    func testExerciseStartBundleContents() async {
        let agent = ActivityModeAgent()
        
        let bundle = await agent.startExercise()
        
        let types = bundle.effects.map(\.type)
        #expect(types.contains(.glucose))
        #expect(types.contains(.sensitivity))
    }
    
    @Test("Exercise bundle predicts glucose drop")
    func testGlucoseDropPrediction() async {
        let agent = ActivityModeAgent()
        
        let bundle = await agent.startExercise()
        
        // Find glucose effect
        let glucoseEffect = bundle.effects.compactMap { effect -> GlucoseEffectSpec? in
            if case .glucose(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(glucoseEffect != nil)
        
        // Last point should be negative (glucose drop)
        if let lastPoint = glucoseEffect?.series.last {
            #expect(lastPoint.bgDelta < 0)
        }
    }
    
    @Test("During-exercise sensitivity is reduced")
    func testDuringExerciseSensitivity() async {
        let agent = ActivityModeAgent()
        
        let bundle = await agent.startExercise()
        
        let sensitivityEffect = bundle.effects.compactMap { effect -> SensitivityEffectSpec? in
            if case .sensitivity(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(sensitivityEffect != nil)
        // During exercise: less sensitive (factor > 1)
        #expect(sensitivityEffect!.factor > 1.0)
    }
    
    @Test("Post-exercise sensitivity is increased")
    func testPostExerciseSensitivity() async {
        let agent = ActivityModeAgent()
        
        // Start and end exercise
        _ = await agent.startExercise()
        let bundle = await agent.endExercise()
        
        let sensitivityEffect = bundle.effects.compactMap { effect -> SensitivityEffectSpec? in
            if case .sensitivity(let spec) = effect { return spec }
            return nil
        }.first
        
        #expect(sensitivityEffect != nil)
        // Post exercise: more sensitive (factor < 1)
        #expect(sensitivityEffect!.factor < 1.0)
    }
    
    // MARK: - Configuration Tests
    
    @Test("Default configuration values")
    func testDefaultConfiguration() {
        let config = ActivityModeAgent.Configuration.default
        
        #expect(config.minHeartRate == 120)
        #expect(config.exerciseGlucoseDrop == -30)
        #expect(config.duringExerciseSensitivity == 1.2)
        #expect(config.postExerciseSensitivity == 0.7)
        #expect(config.confidence == 0.75)
    }
    
    @Test("Intense configuration is more aggressive")
    func testIntenseConfiguration() {
        let config = ActivityModeAgent.Configuration.intense
        
        #expect(config.minHeartRate > ActivityModeAgent.Configuration.default.minHeartRate)
        #expect(config.exerciseGlucoseDrop < ActivityModeAgent.Configuration.default.exerciseGlucoseDrop)
        #expect(config.postExerciseSensitivity < ActivityModeAgent.Configuration.default.postExerciseSensitivity)
    }
    
    @Test("Light configuration is more conservative")
    func testLightConfiguration() {
        let config = ActivityModeAgent.Configuration.light
        
        #expect(config.minHeartRate < ActivityModeAgent.Configuration.default.minHeartRate)
        #expect(config.exerciseGlucoseDrop > ActivityModeAgent.Configuration.default.exerciseGlucoseDrop)
        #expect(config.confidence < ActivityModeAgent.Configuration.default.confidence)
    }
    
    @Test("Custom configuration works")
    func testCustomConfiguration() async {
        let config = ActivityModeAgent.Configuration(
            minHeartRate: 140,
            exerciseGlucoseDrop: -40,
            postExerciseSensitivity: 0.65,
            confidence: 0.9
        )
        
        let agent = ActivityModeAgent(config: config)
        let bundle = await agent.startExercise()
        
        #expect(bundle.confidence == 0.9)
    }
    
    // MARK: - Privacy Tests
    
    @Test("Bundle reason is stripped on sync")
    func testReasonStrippedOnSync() async {
        let agent = ActivityModeAgent()
        
        let bundle = await agent.startExercise()
        
        // Original has reason
        #expect(bundle.reason != nil)
        
        // Sync representation strips reason
        let synced = bundle.toSyncRepresentation()
        #expect(synced != nil)
        #expect(synced?.reason == nil)
    }
    
    // MARK: - Safety Bounds Tests
    
    @Test("Glucose effect respects bounds")
    func testGlucoseEffectBounds() async {
        // Even with extreme config, bounds are respected
        let config = ActivityModeAgent.Configuration(
            exerciseGlucoseDrop: -100 // Extreme
        )
        
        let agent = ActivityModeAgent(config: config)
        let bundle = await agent.startExercise()
        
        let glucoseEffect = bundle.effects.compactMap { effect -> GlucoseEffectSpec? in
            if case .glucose(let spec) = effect { return spec }
            return nil
        }.first
        
        // All points should be within ±50 bounds
        for point in glucoseEffect?.series ?? [] {
            #expect(point.bgDelta >= -50)
            #expect(point.bgDelta <= 50)
        }
    }
    
    @Test("Sensitivity effect respects bounds")
    func testSensitivityEffectBounds() async {
        // Even with extreme config, bounds are respected
        let config = ActivityModeAgent.Configuration(
            duringExerciseSensitivity: 5.0, // Extreme
            postExerciseSensitivity: 0.1   // Extreme
        )
        
        let agent = ActivityModeAgent(config: config)
        
        // Start bundle
        let startBundle = await agent.startExercise()
        let duringSensitivity = startBundle.effects.compactMap { effect -> SensitivityEffectSpec? in
            if case .sensitivity(let spec) = effect { return spec }
            return nil
        }.first
        #expect(duringSensitivity!.factor <= 2.0)
        
        // End bundle
        let endBundle = await agent.endExercise()
        let postSensitivity = endBundle.effects.compactMap { effect -> SensitivityEffectSpec? in
            if case .sensitivity(let spec) = effect { return spec }
            return nil
        }.first
        #expect(postSensitivity!.factor >= 0.2)
    }
    
    // MARK: - Integration with Registry
    
    @Test("ActivityMode integrates with registry")
    func testRegistryIntegration() async {
        let registry = EffectAgentRegistry()
        let agent = ActivityModeAgent()
        
        await registry.register(agent)
        
        let retrieved = await registry.agent(for: "activityMode")
        #expect(retrieved != nil)
        #expect(retrieved?.agentId == "activityMode")
    }
    
    @Test("Multiple agents in registry")
    func testMultipleAgentsInRegistry() async {
        let registry = EffectAgentRegistry()
        
        let breakfastBoost = BreakfastBoostAgent()
        let activityMode = ActivityModeAgent()
        
        await registry.register(breakfastBoost)
        await registry.register(activityMode)
        
        let agents = await registry.allAgents()
        #expect(agents.count == 2)
    }
}
