// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EffectModifierTests.swift
// T1PalAlgorithmTests
//
// Tests for EffectModifier struct
// Backlog: ALG-EFF-002

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("EffectModifier")
struct EffectModifierTests {
    
    // MARK: - Initialization Tests
    
    @Test("Default initialization")
    func defaultInitialization() {
        let modifier = EffectModifier(source: "test")
        
        #expect(modifier.isfMultiplier == 1.0)
        #expect(modifier.crMultiplier == 1.0)
        #expect(modifier.basalMultiplier == 1.0)
        #expect(modifier.source == "test")
        #expect(modifier.confidence == 0.7)
        #expect(modifier.isIdentity)
    }
    
    @Test("Custom initialization")
    func customInitialization() {
        let modifier = EffectModifier(
            isfMultiplier: 0.8,
            crMultiplier: 0.9,
            basalMultiplier: 0.7,
            source: "exercise",
            confidence: 0.85,
            reason: "Post-workout"
        )
        
        #expect(modifier.isfMultiplier == 0.8)
        #expect(modifier.crMultiplier == 0.9)
        #expect(modifier.basalMultiplier == 0.7)
        #expect(modifier.source == "exercise")
        #expect(modifier.confidence == 0.85)
        #expect(modifier.reason == "Post-workout")
        #expect(!modifier.isIdentity)
    }
    
    // MARK: - Safety Bounds Tests
    
    @Test("ISF bounds enforced")
    func isfBoundsEnforced() {
        // Below minimum
        let tooLow = EffectModifier(isfMultiplier: 0.2, source: "test")
        #expect(tooLow.isfMultiplier == EffectModifier.minISFMultiplier)
        
        // Above maximum
        let tooHigh = EffectModifier(isfMultiplier: 3.0, source: "test")
        #expect(tooHigh.isfMultiplier == EffectModifier.maxISFMultiplier)
        
        // Within bounds
        let valid = EffectModifier(isfMultiplier: 1.5, source: "test")
        #expect(valid.isfMultiplier == 1.5)
    }
    
    @Test("CR bounds enforced")
    func crBoundsEnforced() {
        let tooLow = EffectModifier(crMultiplier: 0.3, source: "test")
        #expect(tooLow.crMultiplier == EffectModifier.minCRMultiplier)
        
        let tooHigh = EffectModifier(crMultiplier: 2.5, source: "test")
        #expect(tooHigh.crMultiplier == EffectModifier.maxCRMultiplier)
    }
    
    @Test("Basal bounds enforced")
    func basalBoundsEnforced() {
        let tooLow = EffectModifier(basalMultiplier: 0.1, source: "test")
        #expect(tooLow.basalMultiplier == EffectModifier.minBasalMultiplier)
        
        let tooHigh = EffectModifier(basalMultiplier: 5.0, source: "test")
        #expect(tooHigh.basalMultiplier == EffectModifier.maxBasalMultiplier)
    }
    
    @Test("Confidence bounds enforced")
    func confidenceBoundsEnforced() {
        let negative = EffectModifier(source: "test", confidence: -0.5)
        #expect(negative.confidence == 0.0)
        
        let overOne = EffectModifier(source: "test", confidence: 1.5)
        #expect(overOne.confidence == 1.0)
    }
    
    // MARK: - Composition Tests
    
    @Test("Combine two modifiers")
    func combineTwoModifiers() {
        let exercise = EffectModifier(
            isfMultiplier: 0.8,
            basalMultiplier: 0.7,
            source: "exercise",
            confidence: 0.8
        )
        
        let luteal = EffectModifier(
            isfMultiplier: 1.15,
            basalMultiplier: 1.1,
            source: "cycle.luteal",
            confidence: 0.6
        )
        
        let combined = exercise.combined(with: luteal)
        
        // 0.8 * 1.15 = 0.92
        #expect(abs(combined.isfMultiplier - 0.92) < 0.01)
        // 0.7 * 1.1 = 0.77
        #expect(abs(combined.basalMultiplier - 0.77) < 0.01)
        // Use lower confidence
        #expect(combined.confidence == 0.6)
        // Combined source
        #expect(combined.source.contains("exercise"))
        #expect(combined.source.contains("cycle.luteal"))
    }
    
    @Test("Compose multiple modifiers")
    func composeMultipleModifiers() {
        let modifiers = [
            EffectModifier(isfMultiplier: 0.9, source: "a"),
            EffectModifier(isfMultiplier: 0.9, source: "b"),
            EffectModifier(isfMultiplier: 0.9, source: "c")
        ]
        
        let composed = EffectModifier.compose(modifiers)
        
        // 0.9 * 0.9 * 0.9 = 0.729, but bounded to 0.5
        // Actually 0.729 is within bounds, so should be exact
        #expect(abs(composed.isfMultiplier - 0.729) < 0.001)
    }
    
    @Test("Compose empty array")
    func composeEmptyArray() {
        let composed = EffectModifier.compose([])
        #expect(composed.isIdentity)
    }
    
    @Test("Composition enforces safety bounds")
    func compositionEnforcesSafetyBounds() {
        // Multiple extreme modifiers that would exceed bounds
        let extreme1 = EffectModifier(isfMultiplier: 0.5, source: "a")
        let extreme2 = EffectModifier(isfMultiplier: 0.5, source: "b")
        
        let combined = extreme1.combined(with: extreme2)
        
        // 0.5 * 0.5 = 0.25, but bounded to 0.5
        #expect(combined.isfMultiplier == EffectModifier.minISFMultiplier)
    }
    
    // MARK: - Preset Tests
    
    @Test("Exercise presets")
    func exercisePresets() {
        let light = EffectModifier.exercise(intensity: .light)
        #expect(light.isfMultiplier < 1.0)
        #expect(light.basalMultiplier < 1.0)
        
        let moderate = EffectModifier.exercise(intensity: .moderate)
        #expect(moderate.isfMultiplier < light.isfMultiplier)
        
        let intense = EffectModifier.exercise(intensity: .intense)
        #expect(intense.isfMultiplier < moderate.isfMultiplier)
    }
    
    @Test("Menstrual phase presets")
    func menstrualPhasePresets() {
        let follicular = EffectModifier.menstrualPhase(.follicular)
        #expect(follicular.isfMultiplier < 1.0) // More sensitive
        
        let luteal = EffectModifier.menstrualPhase(.luteal)
        #expect(luteal.isfMultiplier > 1.0) // Less sensitive
        
        let menstrual = EffectModifier.menstrualPhase(.menstrual)
        #expect(menstrual.isfMultiplier == 1.0) // Baseline
    }
    
    @Test("Illness preset")
    func illnessPreset() {
        let illness = EffectModifier.illness
        #expect(illness.isfMultiplier > 1.0) // Less sensitive
        #expect(illness.basalMultiplier > 1.0) // More basal
    }
    
    // MARK: - Validity Tests
    
    @Test("Validity checking")
    func validityChecking() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)
        
        let valid = EffectModifier(
            source: "test",
            timestamp: Date(),
            validUntil: future
        )
        #expect(valid.isValid)
        
        let expired = EffectModifier(
            source: "test",
            timestamp: past,
            validUntil: past.addingTimeInterval(60)
        )
        #expect(!expired.isValid)
    }
    
    // MARK: - Summary Tests
    
    @Test("Summary generation")
    func summaryGeneration() {
        let modifier = EffectModifier(
            isfMultiplier: 0.8,
            basalMultiplier: 0.7,
            source: "exercise"
        )
        
        let summary = modifier.summary
        #expect(summary.contains("sensitivity"))
        #expect(summary.contains("basal"))
    }
    
    @Test("Identity modifier summary")
    func identityModifierSummary() {
        let identity = EffectModifier.identity
        #expect(identity.summary == "No adjustment")
    }
    
    // MARK: - Dose Direction Tests
    
    @Test("Dose direction less insulin")
    func doseDirectionLessInsulin() {
        let modifier = EffectModifier(
            isfMultiplier: 0.7,
            basalMultiplier: 0.8,
            source: "exercise"
        )
        #expect(modifier.netDoseDirection == .lessInsulin)
    }
    
    @Test("Dose direction more insulin")
    func doseDirectionMoreInsulin() {
        let modifier = EffectModifier(
            isfMultiplier: 1.3,
            basalMultiplier: 1.2,
            source: "illness"
        )
        #expect(modifier.netDoseDirection == .moreInsulin)
    }
    
    @Test("Dose direction no change")
    func doseDirectionNoChange() {
        let modifier = EffectModifier.identity
        #expect(modifier.netDoseDirection == .noChange)
    }
    
    // MARK: - Validation Tests
    
    @Test("Validation passes")
    func validationPasses() {
        let valid = EffectModifier(
            isfMultiplier: 1.2,
            crMultiplier: 1.1,
            basalMultiplier: 0.9,
            source: "test",
            validUntil: Date().addingTimeInterval(300)
        )
        
        #expect(valid.validate().isEmpty)
    }
    
    @Test("Validation fails empty source")
    func validationFailsEmptySource() {
        let invalid = EffectModifier(
            source: "",
            validUntil: Date().addingTimeInterval(300)
        )
        
        let errors = invalid.validate()
        #expect(errors.contains { $0.contains("Source") })
    }
    
    // MARK: - Conversion Tests
    
    @Test("Conversion from SensitivitySpec")
    func conversionFromSensitivitySpec() {
        let spec = SensitivityEffectSpec(
            confidence: 0.8,
            factor: 0.85,
            durationMinutes: 60
        )
        
        let modifier = EffectModifier(from: spec, source: "test")
        
        #expect(modifier.isfMultiplier == 0.85)
        #expect(modifier.confidence == 0.8)
        #expect(modifier.crMultiplier == 1.0)
        #expect(modifier.basalMultiplier == 1.0)
    }
    
    @Test("Conversion from EffectBundle")
    func conversionFromEffectBundle() {
        let bundle = EffectBundle(
            agent: "activityMode",
            validUntil: Date().addingTimeInterval(3600),
            effects: [
                .sensitivity(SensitivityEffectSpec(confidence: 0.75, factor: 0.8, durationMinutes: 30))
            ],
            confidence: 0.8
        )
        
        let modifier = EffectModifier(from: bundle)
        
        #expect(modifier != nil)
        #expect(modifier?.isfMultiplier == 0.8)
        #expect(modifier?.source == "activityMode")
    }
    
    @Test("Conversion from bundle without sensitivity returns nil")
    func conversionFromBundleWithoutSensitivityReturnsNil() {
        let bundle = EffectBundle(
            agent: "test",
            validUntil: Date().addingTimeInterval(3600),
            effects: [
                .glucose(GlucoseEffectSpec(confidence: 0.7, series: []))
            ],
            confidence: 0.7
        )
        
        let modifier = EffectModifier(from: bundle)
        #expect(modifier == nil) // No sensitivity effect, so identity would be returned
    }
}
