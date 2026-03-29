// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SimultaneousViolationTests.swift
// T1PalAlgorithmTests
//
// Tests for algorithm behavior when multiple safety constraints
// are violated simultaneously.
// Trace: TEST-GAP-001, CRITICAL-PATH-TESTS.md
//
// Scenarios:
// - Low BG + high IOB + carb stacking
// - Low BG + active carbs (carb stacking)
// - BG dropping + high IOB + pending bolus consideration
// - Multiple simultaneous limit violations
// - IOB exactly at maxIOB + BG at threshold
//
// Key safety invariant: When multiple violations occur,
// the algorithm MUST choose the most conservative action
// (suspend > reduce > maintain > increase)

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - Simultaneous Violation Tests

@Suite("Simultaneous Safety Violations")
struct SimultaneousViolationTests {
    
    // MARK: - Test Setup
    
    private func makeProfile(
        basalRate: Double = 1.0,
        carbRatio: Double = 10.0,
        isf: Double = 50.0,
        maxIOB: Double = 10.0,
        maxBasalRate: Double = 4.0,
        suspendThreshold: Double = 70.0
    ) -> TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: basalRate)],
            carbRatios: [CarbRatio(startTime: 0, ratio: carbRatio)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: isf)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: maxIOB,
            maxBolus: 10.0,
            maxBasalRate: maxBasalRate,
            suspendThreshold: suspendThreshold
        )
    }
    
    private func makeGlucoseReadings(current: Double, trend: Double, count: Int = 6) -> [GlucoseReading] {
        let now = Date()
        return (0..<count).map { i in
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 5 * 60))
            let glucose = current - Double(i) * trend
            return GlucoseReading(glucose: glucose, timestamp: timestamp, source: "test")
        }
    }
    
    // MARK: - Low BG + High IOB Tests
    
    @Test("Low BG with high IOB must zero basal (most dangerous combination)")
    func lowBGHighIOBZerosBasal() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            // Critical scenario: BG at suspend threshold with high IOB
            let glucose = makeGlucoseReadings(current: 70, trend: -2)
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 8.0,  // Very high IOB (80% of max)
                carbsOnBoard: 0,
                profile: makeProfile()
            )
            
            let decision = try algo.calculate(inputs)
            
            // Must suspend - this is the most dangerous combination
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate == 0,
                    "\(type(of: algo)): Must zero basal with low BG (70) + high IOB (8U)")
            }
            #expect(decision.suggestedBolus == nil,
                "\(type(of: algo)): Must not suggest bolus with low BG + high IOB")
        }
    }
    
    @Test("Very low BG with IOB at maxIOB must suspend regardless of trend")
    func veryLowBGAtMaxIOBSuspends() throws {
        let algo = Oref1Algorithm()
        
        // Severe hypo (55) with IOB exactly at max
        let glucose = makeGlucoseReadings(current: 55, trend: 0)  // Even stable, must suspend
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 10.0,  // Exactly at maxIOB
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 10.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate == 0,
                "Must zero basal at severe hypo (55) with IOB at max")
        }
        #expect(decision.suggestedBolus == nil,
            "Must never suggest bolus at severe hypoglycemia")
    }
    
    @Test("Low BG + high IOB + falling trend is triple violation")
    func tripleViolationMaxSuspend() throws {
        let algo = LoopAlgorithm()
        
        // Triple threat: Low BG + high IOB + rapidly falling
        let glucose = makeGlucoseReadings(current: 75, trend: -4)  // Falling 20 mg/dL per 5 min
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 7.0,
            carbsOnBoard: 0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // With triple violation, must take most conservative action
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.1,
                "Triple violation (low BG + high IOB + falling) must minimize/zero basal")
        }
    }
    
    // MARK: - Low BG + Carb Stacking Tests
    
    @Test("Low BG with active carbs still requires conservative action")
    func lowBGWithActiveCarbsConservative() throws {
        let algo = Oref1Algorithm()
        
        // Low BG but carbs are active - don't just "wait for carbs"
        let glucose = makeGlucoseReadings(current: 65, trend: -1)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 30.0,  // Active carbs
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Even with carbs, low BG requires zero/minimal basal
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.3,
                "Low BG (65) must zero/minimize basal even with active carbs")
        }
        #expect(decision.suggestedBolus == nil,
            "Must not suggest bolus during hypoglycemia regardless of COB")
    }
    
    @Test("Very low BG with high COB and high IOB is maximum danger")
    func veryLowBGHighCOBHighIOB() throws {
        let algo = LoopAlgorithm()
        
        // Maximum danger: severe hypo + high COB + high IOB
        // This could indicate a meal bolus miscalculation
        let glucose = makeGlucoseReadings(current: 50, trend: -3)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 6.0,
            carbsOnBoard: 60.0,  // High active carbs
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Must suspend - COB does not override severe hypo + high IOB
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate == 0,
                "Severe hypo (50) with high IOB must zero basal regardless of COB")
        }
    }
    
    @Test("Carb stacking with low BG and falling trend")
    func carbStackingLowBGFalling() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            // Carb stacking scenario: multiple recent carb entries
            let glucose = makeGlucoseReadings(current: 68, trend: -2)
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 4.0,
                carbsOnBoard: 80.0,  // Very high COB from stacking
                profile: makeProfile()
            )
            
            let decision = try algo.calculate(inputs)
            
            // Low BG + falling overrides any expected rise from carbs
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate < 0.5,
                    "\(type(of: algo)): Low falling BG must suspend even with high COB (carb stacking)")
            }
        }
    }
    
    // MARK: - Boundary Condition Tests (at exact limits)
    
    @Test("IOB exactly at maxIOB with BG at suspend threshold")
    func iobAtMaxBGAtThreshold() throws {
        let algo = Oref1Algorithm()
        
        // Both limits exactly at boundary
        let glucose = makeGlucoseReadings(current: 70, trend: 0)  // Exactly at threshold
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 10.0,  // Exactly at maxIOB
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 10.0, suspendThreshold: 70.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // At exact boundaries, must be conservative
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.5,
                "At exact boundaries (BG=70, IOB=maxIOB) must minimize basal")
        }
        #expect(decision.suggestedBolus == nil,
            "At IOB limit, must not suggest additional bolus")
    }
    
    @Test("BG one point above threshold with IOB one unit below max")
    func justAboveThresholdJustBelowMaxIOB() throws {
        let algo = LoopAlgorithm()
        
        // Just barely above limits - still needs caution
        let glucose = makeGlucoseReadings(current: 71, trend: -1)  // Just above 70
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 9.0,  // One below maxIOB (10)
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 10.0, suspendThreshold: 70.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // Just above threshold with near-max IOB and falling - be conservative
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 1.0,
                "Near boundaries with falling BG should reduce basal")
        }
    }
    
    // MARK: - Conflicting Signals Tests
    
    @Test("High BG but IOB at max - cannot add more insulin")
    func highBGAtMaxIOB() throws {
        let algo = Oref1Algorithm()
        
        // High BG wants more insulin, but IOB is maxed
        let glucose = makeGlucoseReadings(current: 250, trend: 5)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 10.0,  // At maxIOB
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 10.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // IOB limit should constrain response to high BG
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 1.0,
                "At maxIOB, should not increase basal even with high BG")
        }
        #expect(decision.suggestedBolus == nil || (decision.suggestedBolus ?? 0) < 0.1,
            "At maxIOB, must not suggest significant bolus")
    }
    
    @Test("Rising BG but already high IOB - respect IOB limit")
    func risingBGHighIOB() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            let glucose = makeGlucoseReadings(current: 180, trend: 3)
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 8.0,
                carbsOnBoard: 0,
                profile: makeProfile(maxIOB: 10.0)
            )
            
            let decision = try algo.calculate(inputs)
            
            // Should be conservative - already have significant IOB working
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate <= 2.0,
                    "\(type(of: algo)): With high IOB (8U), should moderate basal increase")
            }
        }
    }
    
    @Test("Low BG with rising trend and high IOB - IOB danger dominates")
    func lowBGRisingTrendHighIOB() throws {
        let algo = Oref1Algorithm()
        
        // BG is low but rising - however high IOB means danger continues
        let glucose = makeGlucoseReadings(current: 68, trend: 2)  // Rising
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 7.0,
            carbsOnBoard: 20.0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Even with rising trend, low BG + high IOB = suspend
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.3,
                "Low BG (68) + high IOB should suspend even with rising trend")
        }
    }
    
    // MARK: - SafetyGuardian Integration Tests
    
    @Test("SafetyGuardian correctly identifies multiple violations")
    func safetyGuardianMultipleViolations() {
        let guardian = SafetyGuardian(limits: .default)
        
        // Check multiple violation scenario
        let glucoseResult = guardian.checkGlucose(65)
        let iobResult = guardian.checkIOB(current: 9.0, additional: 2.0)
        
        #expect(glucoseResult.reason != nil,
            "Low glucose (65) should trigger safety check")
        #expect(iobResult.reason != nil,
            "IOB 9 + 2 exceeding max 10 should be limited")
        
        // Verify suspension recommendation
        #expect(guardian.shouldSuspend(glucose: 65),
            "Guardian should recommend suspend at glucose 65")
    }
    
    @Test("SafetyGuardian denies bolus when IOB at max")
    func safetyGuardianDeniesBolusAtMaxIOB() {
        let guardian = SafetyGuardian(limits: SafetyLimits(maxIOB: 10.0))
        
        // Already at max IOB
        let result = guardian.checkIOB(current: 10.0, additional: 1.0)
        
        switch result {
        case .denied:
            #expect(true, "Correctly denied additional insulin at maxIOB")
        case .allowed:
            Issue.record("Should not allow additional insulin at maxIOB")
        case .limited(_, let limitedValue, _):
            #expect(limitedValue == 0,
                "If limited, should be limited to 0")
        }
    }
    
    @Test("SafetyGuardian predicted low triggers early suspend")
    func safetyGuardianPredictedLow() {
        let guardian = SafetyGuardian(limits: SafetyLimits(suspendThreshold: 70.0))
        
        // Current BG is fine but prediction is low
        #expect(!guardian.shouldSuspend(glucose: 100),
            "Current BG 100 should not trigger suspend")
        #expect(guardian.shouldSuspendForPrediction(minPredBG: 65),
            "Predicted low (65) should trigger suspend")
    }
}

// MARK: - Priority Hierarchy Tests

@Suite("Safety Priority Hierarchy")
struct SafetyPriorityHierarchyTests {
    
    private func makeProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0,
            maxBasalRate: 4.0,
            suspendThreshold: 70.0
        )
    }
    
    private func makeGlucoseReadings(current: Double, trend: Double) -> [GlucoseReading] {
        let now = Date()
        return (0..<6).map { i in
            GlucoseReading(
                glucose: current - Double(i) * trend,
                timestamp: now.addingTimeInterval(TimeInterval(-i * 5 * 60)),
                source: "test"
            )
        }
    }
    
    @Test("Suspend takes priority over correction")
    func suspendPriorityOverCorrection() throws {
        let algo = Oref1Algorithm()
        
        // Previous high BG reading, but now low - must suspend not correct
        let glucose = [
            GlucoseReading(glucose: 60, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: 100, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 150, timestamp: Date().addingTimeInterval(-600), source: "test"),
            GlucoseReading(glucose: 180, timestamp: Date().addingTimeInterval(-900), source: "test"),
            GlucoseReading(glucose: 200, timestamp: Date().addingTimeInterval(-1200), source: "test"),
            GlucoseReading(glucose: 220, timestamp: Date().addingTimeInterval(-1500), source: "test")
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 3.0,
            carbsOnBoard: 0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Despite history of high BG, current low BG must trigger suspend
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.1,
                "Current low BG (60) must suspend regardless of previous high readings")
        }
    }
    
    @Test("IOB limit takes priority over high BG correction")
    func iobLimitPriorityOverCorrection() throws {
        let algo = LoopAlgorithm()
        
        // Very high BG but IOB is at limit
        let glucose = makeGlucoseReadings(current: 300, trend: 5)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 10.0,  // At max
            carbsOnBoard: 0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Cannot add more insulin even with very high BG
        let totalSuggested = (decision.suggestedTempBasal?.rate ?? 0) + (decision.suggestedBolus ?? 0)
        #expect(totalSuggested <= 1.5,
            "At maxIOB, must limit insulin delivery even with very high BG (300)")
    }
    
    @Test("Conservative action when multiple signals conflict")
    func conservativeOnConflict() throws {
        let algo = Oref1Algorithm()
        
        // Conflicting signals: Low BG (suspend) + High COB (expect rise) + High IOB (danger)
        let glucose = makeGlucoseReadings(current: 72, trend: -1)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 6.0,
            carbsOnBoard: 50.0,  // Suggests BG will rise
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // On conflict, safety (low BG + high IOB) should win over optimism (COB)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.5,
                "Conflicting signals should result in conservative (low) basal")
        }
    }
}

// MARK: - Edge Case Combinations

@Suite("Edge Case Combinations")
struct EdgeCaseCombinationTests {
    
    private func makeProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0
        )
    }
    
    @Test("Zero IOB with very low BG still suspends")
    func zeroIOBVeryLowBG() throws {
        let algo = Oref1Algorithm()
        
        // Even with zero IOB, very low BG requires suspension
        let glucose = [
            GlucoseReading(glucose: 50, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: 55, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 60, timestamp: Date().addingTimeInterval(-600), source: "test")
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,  // No IOB
            carbsOnBoard: 0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate == 0,
                "Very low BG (50) must zero basal even with zero IOB")
        }
    }
    
    @Test("Max COB with low BG still suspends")
    func maxCOBLowBG() throws {
        let algo = LoopAlgorithm()
        
        let glucose = [
            GlucoseReading(glucose: 60, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: 65, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 70, timestamp: Date().addingTimeInterval(-600), source: "test")
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 120.0,  // Maximum COB
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Max COB does not override severe hypoglycemia
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate < 0.3,
                "Severe hypo (60) must minimize basal regardless of max COB")
        }
    }
    
    @Test("Rapidly falling from target with no IOB")
    func rapidlyFallingFromTargetNoIOB() throws {
        let algo = Oref1Algorithm()
        
        // Starting at target but falling very fast
        let glucose = [
            GlucoseReading(glucose: 100, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: 115, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 130, timestamp: Date().addingTimeInterval(-600), source: "test"),
            GlucoseReading(glucose: 145, timestamp: Date().addingTimeInterval(-900), source: "test"),
            GlucoseReading(glucose: 160, timestamp: Date().addingTimeInterval(-1200), source: "test"),
            GlucoseReading(glucose: 175, timestamp: Date().addingTimeInterval(-1500), source: "test")
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile()
        )
        
        let decision = try algo.calculate(inputs)
        
        // Rapidly falling should reduce/suspend basal (at most scheduled basal)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 1.0,
                "Rapidly falling from 175→100 should not increase basal")
        }
    }
}
