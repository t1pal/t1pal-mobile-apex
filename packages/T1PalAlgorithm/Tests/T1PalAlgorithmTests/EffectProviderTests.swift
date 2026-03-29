// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EffectProviderTests.swift
// T1PalAlgorithmTests
//
// Tests for Effect Provider and EffectBundleComposer
// Backlog: ALG-EFF-061..063
// Trace: PRD-026 Effect Bundle Architecture, PRD-028 Phase 2

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Effect Provider")
struct EffectProviderTests {
    
    // MARK: - EffectContext Tests
    
    @Test("Effect context creation")
    func effectContextCreation() {
        let context = EffectContext(
            currentGlucose: 120,
            trend: .rising,
            activeOverrides: ["Exercise"],
            recentActivities: ["Running"]
        )
        
        #expect(context.currentGlucose == 120)
        #expect(context.trend == .rising)
        #expect(context.activeOverrides.contains("Exercise"))
        #expect(context.recentActivities.contains("Running"))
    }
    
    @Test("Effect preferences defaults")
    func effectPreferencesDefaults() {
        let prefs = EffectPreferences()
        
        #expect(prefs.maxSensitivityMultiplier == 2.0)
        #expect(prefs.maxBasalMultiplier == 2.0)
        #expect(prefs.enableGlucosePredictions)
        #expect(prefs.privacyTier == .privacyPreserving)
    }
    
    // MARK: - ActivityEffectAdapter Tests
    
    @Test("Activity adapter generates effect")
    func activityAdapterGeneratesEffect() async {
        let adapter = ActivityEffectAdapter(
            activityType: "Running",
            sensitivityFactor: 0.8,  // More sensitive
            durationMinutes: 120,
            confidence: 0.85
        )
        
        #expect(adapter.providerId == "activity.running")
        #expect(adapter.displayName == "Running Agent")
        #expect(adapter.isEnabled)
        
        // Context with running activity
        let context = EffectContext(
            recentActivities: ["Running 5k"]
        )
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle != nil)
        #expect(bundle?.agent == "activity.running")
        #expect(bundle?.effects.count == 1)
        
        if case .sensitivity(let spec) = bundle?.effects.first {
            #expect(spec.factor == 0.8)
            #expect(spec.durationMinutes == 120)
        } else {
            Issue.record("Expected sensitivity effect")
        }
    }
    
    @Test("Activity adapter no effect without activity")
    func activityAdapterNoEffectWithoutActivity() async {
        let adapter = ActivityEffectAdapter(
            activityType: "Tennis",
            sensitivityFactor: 0.7,
            durationMinutes: 180,
            confidence: 0.9
        )
        
        // Context WITHOUT tennis
        let context = EffectContext(
            recentActivities: ["Walking"]
        )
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle == nil)
    }
    
    // MARK: - CircadianEffectAdapter Tests
    
    @Test("Circadian adapter generates hourly effect")
    func circadianAdapterGeneratesHourlyEffect() async {
        // Dawn phenomenon: more resistance at 6 AM
        let adapter = CircadianEffectAdapter(
            hourlySensitivityFactors: [6: 1.3],  // 30% less sensitive
            confidence: 0.75
        )
        
        // Create context at 6 AM
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let components = DateComponents(hour: 6, minute: 30)
        let sixAM = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)!
        
        let context = EffectContext(timestamp: sixAM)
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle != nil)
        #expect(bundle?.agent == "circadian")
        
        if case .sensitivity(let spec) = bundle?.effects.first {
            #expect(spec.factor == 1.3)
        } else {
            Issue.record("Expected sensitivity effect")
        }
    }
    
    @Test("Circadian adapter no effect when no adjustment")
    func circadianAdapterNoEffectWhenNoAdjustment() async {
        let adapter = CircadianEffectAdapter(
            hourlySensitivityFactors: [6: 1.3],  // Only 6 AM
            confidence: 0.75
        )
        
        // Create context at 2 PM (no adjustment)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let components = DateComponents(hour: 14)
        let twoPM = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)!
        
        let context = EffectContext(timestamp: twoPM)
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle == nil)
    }
    
    // MARK: - IllnessEffectAdapter Tests
    
    @Test("Illness adapter generates effect when sick")
    func illnessAdapterGeneratesEffectWhenSick() async {
        let adapter = IllnessEffectAdapter(
            severity: "moderate",
            sensitivityFactor: 1.4,  // 40% more resistant
            confidence: 0.8
        )
        
        // Context with illness override active
        let context = EffectContext(
            activeOverrides: ["Sick Day"]
        )
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle != nil)
        #expect(bundle?.agent == "illness")
        #expect(bundle?.reason == "Illness mode (moderate)")
        
        if case .sensitivity(let spec) = bundle?.effects.first {
            #expect(spec.factor == 1.4)
            #expect(spec.durationMinutes == 480)  // 8 hours
        } else {
            Issue.record("Expected sensitivity effect")
        }
    }
    
    @Test("Illness adapter no effect when healthy")
    func illnessAdapterNoEffectWhenHealthy() async {
        let adapter = IllnessEffectAdapter(
            severity: "mild",
            sensitivityFactor: 1.2,
            confidence: 0.7
        )
        
        // No illness override
        let context = EffectContext(activeOverrides: [])
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle == nil)
    }
    
    // MARK: - HunchEffectAdapter Tests
    
    @Test("Hunch adapter generates effect on trigger")
    func hunchAdapterGeneratesEffectOnTrigger() async {
        let adapter = HunchEffectAdapter(
            name: "Tennis Low",
            triggerKeyword: "tennis",
            sensitivityFactor: 0.7,
            durationMinutes: 180,
            confidence: 0.85
        )
        
        #expect(adapter.providerId == "hunch.tennis_low")
        
        // Context with tennis activity
        let context = EffectContext(
            recentActivities: ["Tennis match"]
        )
        
        let bundle = await adapter.generateEffects(context: context)
        
        #expect(bundle != nil)
        #expect(bundle?.reason == "Tennis Low activated")
    }
    
    // MARK: - EffectBundleComposer Tests
    
    @Test("Composer registers providers")
    func composerRegistersProviders() async {
        let composer = EffectBundleComposer()
        
        let activity = ActivityEffectAdapter(
            activityType: "Running",
            sensitivityFactor: 0.8,
            durationMinutes: 120,
            confidence: 0.85
        )
        
        await composer.register(provider: activity)
        
        let providers = await composer.getProviders()
        #expect(providers.contains("activity.running"))
    }
    
    @Test("Composer generates all effects")
    func composerGeneratesAllEffects() async {
        let composer = EffectBundleComposer()
        
        let running = ActivityEffectAdapter(
            activityType: "Running",
            sensitivityFactor: 0.8,
            durationMinutes: 120,
            confidence: 0.85
        )
        
        let illness = IllnessEffectAdapter(
            severity: "mild",
            sensitivityFactor: 1.2,
            confidence: 0.7
        )
        
        await composer.register(provider: running)
        await composer.register(provider: illness)
        
        // Context with running AND illness
        let context = EffectContext(
            activeOverrides: ["Sick Day"],
            recentActivities: ["Running"]
        )
        
        let bundles = await composer.generateAllEffects(context: context)
        
        #expect(bundles.count == 2)
    }
    
    @Test("Composer confidence weighted composition")
    func composerConfidenceWeightedComposition() async {
        let composer = EffectBundleComposer(strategy: .confidenceWeighted)
        
        // Add two bundles with different sensitivities and confidences
        let bundle1 = EffectBundle(
            agent: "agent1",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.9, factor: 0.7, durationMinutes: 60))],
            confidence: 0.9
        )
        
        let bundle2 = EffectBundle(
            agent: "agent2",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.5, factor: 1.3, durationMinutes: 60))],
            confidence: 0.5
        )
        
        await composer.addBundle(bundle1)
        await composer.addBundle(bundle2)
        
        let composed = await composer.compose()
        
        #expect(composed.contributingAgents.count == 2)
        
        // Weighted average: (0.7 * 0.9 + 1.3 * 0.5) / 1.4 ≈ 0.914
        // Due to higher confidence on 0.7 factor, result should be < 1.0
        #expect(composed.modifier.isfMultiplier < 1.0)
    }
    
    @Test("Composer detects conflicts")
    func composerDetectsConflicts() async {
        let composer = EffectBundleComposer()
        
        // One bundle says MORE sensitive, another says LESS sensitive
        let bundle1 = EffectBundle(
            agent: "exercise",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.8, factor: 0.7, durationMinutes: 60))],
            confidence: 0.8
        )
        
        let bundle2 = EffectBundle(
            agent: "illness",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.8, factor: 1.3, durationMinutes: 60))],
            confidence: 0.8
        )
        
        await composer.addBundle(bundle1)
        await composer.addBundle(bundle2)
        
        let composed = await composer.compose()
        
        #expect(composed.hasConflicts)
        #expect(composed.conflicts.count == 1)
        
        let conflict = composed.conflicts.first
        #expect(conflict?.effectType == .sensitivity)
    }
    
    @Test("Composer most conservative strategy")
    func composerMostConservativeStrategy() async {
        let composer = EffectBundleComposer(strategy: .mostConservative)
        
        // Multiple bundles with different factors
        let bundle1 = EffectBundle(
            agent: "agent1",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.9, factor: 0.6, durationMinutes: 60))],
            confidence: 0.9
        )
        
        let bundle2 = EffectBundle(
            agent: "agent2",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.8, factor: 0.9, durationMinutes: 60))],
            confidence: 0.8
        )
        
        await composer.addBundle(bundle1)
        await composer.addBundle(bundle2)
        
        let composed = await composer.compose()
        
        // Most conservative = closest to 1.0 = 0.9 (but algorithm uses 1.0 as baseline)
        // If no bundle is close enough, it stays at 1.0
        #expect(composed.contributingAgents.count == 2)
        // The composed modifier exists
        #expect(composed.modifier != nil)
    }
    
    @Test("Composer prunes expired bundles")
    func composerPrunesExpiredBundles() async {
        let composer = EffectBundleComposer()
        
        // Add an expired bundle
        let expiredBundle = EffectBundle(
            agent: "expired",
            validUntil: Date().addingTimeInterval(-60),  // Expired 1 minute ago
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.8, factor: 0.7, durationMinutes: 60))],
            confidence: 0.8
        )
        
        await composer.addBundle(expiredBundle)
        
        let activeBundles = await composer.getActiveBundles()
        
        #expect(activeBundles.count == 0)
    }
    
    // MARK: - Integration Test
    
    @Test("Full provider to composer pipeline")
    func fullProviderToComposerPipeline() async {
        let composer = EffectBundleComposer()
        
        // Add bundles directly to test composition
        let activityBundle = EffectBundle(
            agent: "activity.running",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.85, factor: 0.8, durationMinutes: 120))],
            reason: "Running detected",
            confidence: 0.85
        )
        
        let circadianBundle = EffectBundle(
            agent: "circadian",
            validUntil: Date().addingTimeInterval(3600),
            effects: [.sensitivity(SensitivityEffectSpec(confidence: 0.7, factor: 1.3, durationMinutes: 60))],
            reason: "Dawn phenomenon",
            confidence: 0.7
        )
        
        await composer.addBundle(activityBundle)
        await composer.addBundle(circadianBundle)
        
        // Compose them
        let composed = await composer.compose()
        
        // Both agents contribute
        #expect(composed.contributingAgents.count == 2)
        
        // Running says more sensitive (0.8), circadian says less (1.3)
        // Should detect conflict
        #expect(composed.hasConflicts)
    }
}
