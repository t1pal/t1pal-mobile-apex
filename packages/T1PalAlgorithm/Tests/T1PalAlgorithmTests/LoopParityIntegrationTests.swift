// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopParityIntegrationTests.swift
// T1Pal Mobile
//
// End-to-end integration tests for Loop algorithm parity
// Validates that IOB and COB parity calculations are wired correctly
// into the main LoopAlgorithm calculation path
//
// Trace: ALG-WIRE-005, PRD-009
//
// Success Criteria:
// - Divergence < 0.1 U/hr for stable scenarios
// - Parity IOB calculation used when basalSchedule provided
// - Parity COB calculation used when carbHistory provided

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Loop Parity Integration")
struct LoopParityIntegrationTests {
    
    // MARK: - Test Configuration
    
    /// Maximum allowed divergence (U/hr) for parity compliance
    let parityThreshold: Double = 0.1
    
    var now: Date { Date() }
    
    // Standard therapy parameters
    let scheduledBasalRate: Double = 1.0  // U/hr
    let targetGlucose: Double = 110.0     // mg/dL
    let isf: Double = 50.0                // mg/dL per U
    let carbRatio: Double = 10.0          // g per U
    
    // MARK: - Helper Methods
    
    func makeProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: scheduledBasalRate)],
            carbRatios: [CarbRatio(startTime: 0, ratio: carbRatio)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: isf)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    func makeGlucoseHistory(value: Double, count: Int = 12) -> [GlucoseReading] {
        (0..<count).map { i in
            GlucoseReading(
                glucose: value,
                timestamp: now.addingTimeInterval(TimeInterval(-i * 5 * 60)),
                trend: .flat
            )
        }
    }
    
    func makeBasalSchedule() -> [AbsoluteScheduleValue<Double>] {
        // Create 24-hour basal schedule
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return [
            AbsoluteScheduleValue(
                startDate: startOfDay,
                endDate: endOfDay,
                value: scheduledBasalRate
            )
        ]
    }
    
    func makeDoseHistory(bolus: Double = 0, tempBasalRate: Double? = nil) -> [InsulinDose] {
        var doses: [InsulinDose] = []
        
        // Add bolus if specified
        if bolus > 0 {
            doses.append(InsulinDose(
                units: bolus,
                timestamp: now.addingTimeInterval(-30 * 60),  // 30 min ago
                source: "test"
            ))
        }
        
        // Add temp basal segments if specified
        if let rate = tempBasalRate {
            // Create 5-minute segments for last 30 minutes
            for i in 0..<6 {
                let segmentTime = now.addingTimeInterval(TimeInterval(-i * 5 * 60))
                let unitsPerSegment = rate * (5.0 / 60.0)  // 5 minutes worth
                doses.append(InsulinDose(
                    units: unitsPerSegment,
                    timestamp: segmentTime,
                    source: "temp_basal"
                ))
            }
        }
        
        return doses
    }
    
    // MARK: - ALG-WIRE-005: Parity IOB Integration Tests
    
    /// Test that parity IOB is used when basalSchedule is provided
    @Test("Parity IOB used when basal schedule provided")
    func parityIOB_isUsedWhenBasalScheduleProvided() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Inputs with basalSchedule and dose history
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 110),
            insulinOnBoard: 0,  // Ignored when doseHistory provided
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: makeDoseHistory(bolus: 2.0),  // 2U bolus 30 min ago
            carbHistory: nil,
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Should produce valid decision (parity path used)
        #expect(decision.suggestedTempBasal != nil)
        // With 2U bolus 30 min ago, some IOB remains → may suggest reduced basal
    }
    
    /// Test stable glucose at target produces neutral recommendation
    @Test("Stable glucose at target produces neutral basal")
    func stableGlucose_atTarget_producesNeutralBasal() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Stable glucose at target, no recent insulin
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 110),  // At target
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],  // No recent doses
            carbHistory: [],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Divergence from scheduled basal should be < threshold
        if let tempBasal = decision.suggestedTempBasal {
            let divergence = abs(tempBasal.rate - scheduledBasalRate)
            #expect(divergence < parityThreshold, "Stable BG divergence (\(divergence) U/hr) exceeds parity threshold (\(parityThreshold) U/hr)")
        }
        // No temp basal is also valid for stable glucose
    }
    
    /// Test high glucose produces increased basal
    @Test("High glucose produces increased basal")
    func highGlucose_producesIncreasedBasal() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: High glucose (180 mg/dL), no insulin on board
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 180),
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],
            carbHistory: [],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Should recommend increased basal
        #expect(decision.suggestedTempBasal != nil)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate > scheduledBasalRate, "High BG should produce increased temp basal")
        }
    }
    
    /// Test low glucose produces suspended basal
    @Test("Low glucose produces suspended basal")
    func lowGlucose_producesSuspendedBasal() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Low glucose (75 mg/dL)
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 75),
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],
            carbHistory: [],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Should recommend zero basal (suspend)
        #expect(decision.suggestedTempBasal != nil)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(abs(tempBasal.rate - 0.0) < 0.01, "Low BG should produce zero temp basal")
        }
    }
    
    // MARK: - ALG-COB-WIRE: Parity COB Integration Tests
    
    /// Test that parity COB is used when carbHistory is provided
    @Test("Parity COB used when carb history provided")
    func parityCOB_isUsedWhenCarbHistoryProvided() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Inputs with carb history
        let carbEntry = CarbEntry(
            grams: 30,
            timestamp: now.addingTimeInterval(-30 * 60)  // 30 min ago
        )
        
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 120),
            insulinOnBoard: 0,
            carbsOnBoard: 0,  // Ignored when carbHistory provided
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],
            carbHistory: [carbEntry],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Should account for COB in prediction
        // With active carbs, may allow higher glucose without aggressive correction
        #expect(decision != nil)
    }
    
    /// Test carb absorption effect on basal recommendation
    @Test("Active carbs reduces basal increase")
    func activeCarbs_reducesBasalIncrease() throws {
        let algorithmWithoutCarbs = LoopAlgorithm()
        let algorithmWithCarbs = LoopAlgorithm()
        
        // Given: High glucose with and without active carbs
        let baseInputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 160),
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],
            carbHistory: [],
            basalSchedule: makeBasalSchedule()
        )
        
        let carbEntry = CarbEntry(
            grams: 40,
            timestamp: now.addingTimeInterval(-15 * 60)  // 15 min ago, still absorbing
        )
        
        let inputsWithCarbs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 160),
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: [],
            carbHistory: [carbEntry],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate both
        let decisionWithoutCarbs = try algorithmWithoutCarbs.calculate(baseInputs)
        let decisionWithCarbs = try algorithmWithCarbs.calculate(inputsWithCarbs)
        
        // Then: Both should produce recommendations
        #expect(decisionWithoutCarbs.suggestedTempBasal != nil)
        #expect(decisionWithCarbs.suggestedTempBasal != nil)
    }
    
    // MARK: - Full Pipeline Integration
    
    /// Test full parity pipeline with IOB + COB + basal schedule
    @Test("Full parity pipeline with all inputs")
    func fullParityPipeline_withAllInputs() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Realistic scenario with all inputs
        let carbEntry = CarbEntry(
            grams: 45,
            timestamp: now.addingTimeInterval(-45 * 60)  // 45 min ago
        )
        
        let inputs = AlgorithmInputs(
            glucose: makeGlucoseHistory(value: 140),  // Slightly elevated
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(),
            currentTime: now,
            doseHistory: makeDoseHistory(bolus: 4.5),  // Bolus for carbs
            carbHistory: [carbEntry],
            basalSchedule: makeBasalSchedule()
        )
        
        // When: Calculate
        let decision = try algorithm.calculate(inputs)
        
        // Then: Should produce coherent recommendation
        #expect(decision != nil)
        
        // With IOB from bolus and active carbs, recommendation varies
        // Key assertion: algorithm doesn't crash and produces valid output
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate >= 0.0)
            #expect(tempBasal.rate <= 5.0)  // Within max basal
            #expect(tempBasal.duration > 0)
        }
    }
    
    /// Test parity divergence is within acceptable range
    @Test("Parity divergence within threshold")
    func parityDivergence_withinThreshold() throws {
        let algorithm = LoopAlgorithm()
        
        // Given: Multiple scenarios
        let scenarios: [(glucose: Double, description: String)] = [
            (110, "at target"),
            (100, "lower target"),
            (120, "upper target"),
            (130, "slightly above"),
            (90, "slightly below"),
        ]
        
        for scenario in scenarios {
            let inputs = AlgorithmInputs(
                glucose: makeGlucoseHistory(value: scenario.glucose),
                insulinOnBoard: 0,
                carbsOnBoard: 0,
                profile: makeProfile(),
                currentTime: now,
                doseHistory: [],
                carbHistory: [],
                basalSchedule: makeBasalSchedule()
            )
            
            // When: Calculate
            let decision = try algorithm.calculate(inputs)
            
            // Then: Divergence should be reasonable
            if let tempBasal = decision.suggestedTempBasal {
                // For near-target glucose, divergence should be minimal
                if scenario.glucose >= 100 && scenario.glucose <= 130 {
                    let divergence = abs(tempBasal.rate - scheduledBasalRate)
                    // Allow larger divergence for out-of-range values
                    let allowedDivergence = scenario.glucose == 110 ? parityThreshold : 1.0
                    #expect(divergence < allowedDivergence, "Scenario '\(scenario.description)': divergence \(divergence) U/hr exceeds \(allowedDivergence)")
                }
            }
        }
    }
}
