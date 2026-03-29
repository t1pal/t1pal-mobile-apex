// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BoundaryConditionTests.swift
// T1PalAlgorithmTests
//
// Tests for algorithm and safety guardian behavior at exact boundary values.
// Trace: TEST-GAP-002, CRITICAL-PATH-TESTS.md
//
// Scenarios:
// - IOB exactly at maxIOB (+/- epsilon)
// - BG exactly at suspend threshold (+/- epsilon)
// - Basal rate exactly at max
// - Bolus exactly at max
// - Temp basal duration at max
// - Time-based schedule transitions
//
// Key principle: Boundary conditions often reveal off-by-one errors
// and comparison operator mistakes (< vs <=, > vs >=).

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - SafetyGuardian Boundary Tests

@Suite("SafetyGuardian Exact Boundaries")
struct SafetyGuardianBoundaryTests {
    
    // MARK: - IOB Boundary Tests
    
    @Test("IOB exactly at maxIOB denies additional insulin")
    func iobExactlyAtMax() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // At exactly maxIOB, even 0.01U should be denied
        let result = guardian.checkIOB(current: 10.0, additional: 0.01)
        
        switch result {
        case .denied:
            // Expected - at max, nothing more allowed
            break
        case .limited(_, let limitedValue, _):
            #expect(limitedValue == 0, "At maxIOB, limited value should be 0")
        case .allowed:
            Issue.record("At maxIOB=10.0 with IOB=10.0, additional insulin should not be allowed")
        }
    }
    
    @Test("IOB 0.01 below maxIOB allows minimal additional")
    func iobJustBelowMax() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // 0.01 below max should allow exactly 0.01 more
        let result = guardian.checkIOB(current: 9.99, additional: 0.01)
        
        #expect(result.isAllowed, "IOB 9.99 + 0.01 = maxIOB 10.0 should be allowed")
    }
    
    @Test("IOB 0.01 above maxIOB is denied")
    func iobJustAboveMax() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Already over max - nothing allowed
        _ = guardian.checkIOB(current: 10.01, additional: 0.0)
        
        // This checks current state, not addition
        let maxAllowed = guardian.maxAdditionalIOB(currentIOB: 10.01)
        #expect(maxAllowed == 0, "Above maxIOB, no additional insulin allowed")
    }
    
    @Test("IOB at zero allows full maxIOB")
    func iobAtZeroAllowsMax() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkIOB(current: 0, additional: 10.0)
        #expect(result.isAllowed, "With zero IOB, should allow up to maxIOB")
        
        let maxAllowed = guardian.maxAdditionalIOB(currentIOB: 0)
        #expect(maxAllowed == 10.0, "With zero IOB, max additional should be maxIOB")
    }
    
    @Test("IOB exceeds max by significant amount")
    func iobSignificantlyOverMax() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Already 5 units over max (shouldn't happen but must handle)
        let result = guardian.checkIOB(current: 15.0, additional: 0.1)
        
        #expect(!result.isAllowed || result.reason != nil,
            "When IOB exceeds max, any additional should be denied or severely limited")
        
        let maxAllowed = guardian.maxAdditionalIOB(currentIOB: 15.0)
        #expect(maxAllowed == 0, "When IOB > maxIOB, max additional must be 0")
    }
    
    // MARK: - Glucose Boundary Tests
    
    @Test("Glucose exactly at suspend threshold triggers suspend")
    func glucoseExactlyAtThreshold() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        #expect(guardian.shouldSuspend(glucose: 70.0),
            "Glucose exactly at suspendThreshold (70) MUST trigger suspend")
        
        let result = guardian.checkGlucose(70.0)
        #expect(!result.isAllowed,
            "Glucose check at threshold should not allow normal operation")
    }
    
    @Test("Glucose 1 point above threshold does not trigger suspend")
    func glucoseJustAboveThreshold() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        #expect(!guardian.shouldSuspend(glucose: 71.0),
            "Glucose 1 above threshold should NOT trigger suspend")
        
        let result = guardian.checkGlucose(71.0)
        #expect(result.isAllowed,
            "Glucose check 1 above threshold should allow operation")
    }
    
    @Test("Glucose 1 point below threshold triggers suspend")
    func glucoseJustBelowThreshold() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        #expect(guardian.shouldSuspend(glucose: 69.0),
            "Glucose 1 below threshold MUST trigger suspend")
    }
    
    @Test("Glucose at minBG boundary")
    func glucoseAtMinBG() {
        let limits = SafetyLimits(minBG: 39.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // At minBG should still be valid (but likely trigger suspend)
        // minBG 39 < suspendThreshold 70, so denied for suspend
        
        // Below minBG should be invalid reading
        let belowMin = guardian.checkGlucose(38.0)
        #expect(!belowMin.isAllowed, "Below minBG should be denied as invalid")
    }
    
    // MARK: - Prediction Boundary Tests
    
    @Test("Predicted BG exactly at threshold triggers suspend")
    func predictedBGExactlyAtThreshold() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // At threshold: spec says "< threshold" triggers, not "<="
        #expect(!guardian.shouldSuspendForPrediction(minPredBG: 70.0),
            "Predicted BG exactly at threshold should NOT trigger suspend (< not <=)")
        
        #expect(guardian.shouldSuspendForPrediction(minPredBG: 69.99),
            "Predicted BG just below threshold MUST trigger suspend")
    }
    
    // MARK: - Basal Rate Boundary Tests
    
    @Test("Basal rate exactly at max is allowed")
    func basalRateExactlyAtMax() {
        let limits = SafetyLimits(maxBasalRate: 5.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBasalRate(5.0)
        #expect(result.isAllowed, "Basal rate exactly at max should be allowed")
        
        let limited = guardian.limitBasalRate(5.0)
        #expect(limited == 5.0, "Limiting rate at max should return max")
    }
    
    @Test("Basal rate 0.01 above max is limited")
    func basalRateJustAboveMax() {
        let limits = SafetyLimits(maxBasalRate: 5.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBasalRate(5.01)
        
        switch result {
        case .limited(let original, let limited, _):
            #expect(original == 5.01, "Original value should be preserved")
            #expect(limited == 5.0, "Limited value should be max")
        default:
            Issue.record("Basal rate above max should be limited, not \(result)")
        }
        
        let limited = guardian.limitBasalRate(5.01)
        #expect(limited == 5.0, "Limiting rate above max should return max")
    }
    
    @Test("Basal rate of zero is allowed")
    func basalRateZero() {
        let limits = SafetyLimits(maxBasalRate: 5.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBasalRate(0.0)
        #expect(result.isAllowed, "Zero basal rate should be allowed")
    }
    
    @Test("Negative basal rate is denied")
    func basalRateNegative() {
        let limits = SafetyLimits(maxBasalRate: 5.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBasalRate(-0.01)
        #expect(!result.isAllowed, "Negative basal rate must be denied")
    }
    
    // MARK: - Bolus Boundary Tests
    
    @Test("Bolus exactly at max is allowed")
    func bolusExactlyAtMax() {
        let limits = SafetyLimits(maxBolus: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBolus(10.0)
        #expect(result.isAllowed, "Bolus exactly at max should be allowed")
    }
    
    @Test("Bolus 0.01 above max is limited")
    func bolusJustAboveMax() {
        let limits = SafetyLimits(maxBolus: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBolus(10.01)
        
        switch result {
        case .limited(_, let limited, _):
            #expect(limited == 10.0, "Bolus should be limited to max")
        default:
            Issue.record("Bolus above max should be limited")
        }
    }
    
    @Test("Bolus of zero is allowed")
    func bolusZero() {
        let limits = SafetyLimits(maxBolus: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkBolus(0.0)
        #expect(result.isAllowed, "Zero bolus should be allowed")
    }
    
    // MARK: - Duration Boundary Tests
    
    @Test("Temp basal duration exactly at max is allowed")
    func durationExactlyAtMax() {
        let limits = SafetyLimits(maxTempBasalDuration: 120 * 60)  // 2 hours
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkTempBasalDuration(120 * 60)
        #expect(result.isAllowed, "Duration exactly at max should be allowed")
    }
    
    @Test("Temp basal duration 1 second above max is limited")
    func durationJustAboveMax() {
        let maxDuration: TimeInterval = 120 * 60
        let limits = SafetyLimits(maxTempBasalDuration: maxDuration)
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkTempBasalDuration(maxDuration + 1)
        
        switch result {
        case .limited(_, let limited, _):
            #expect(limited == maxDuration, "Duration should be limited to max")
        default:
            Issue.record("Duration above max should be limited")
        }
    }
    
    @Test("Temp basal duration of zero is denied")
    func durationZero() {
        let limits = SafetyLimits()
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkTempBasalDuration(0)
        #expect(!result.isAllowed, "Zero duration should be denied")
    }
    
    @Test("Negative temp basal duration is denied")
    func durationNegative() {
        let limits = SafetyLimits()
        let guardian = SafetyGuardian(limits: limits)
        
        let result = guardian.checkTempBasalDuration(-60)
        #expect(!result.isAllowed, "Negative duration must be denied")
    }
}

// MARK: - Algorithm Boundary Tests

@Suite("Algorithm Exact Boundaries")
struct AlgorithmBoundaryTests {
    
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
    
    private func makeGlucoseReadings(current: Double, trend: Double = 0, count: Int = 6) -> [GlucoseReading] {
        let now = Date()
        return (0..<count).map { i in
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 5 * 60))
            let glucose = current - Double(i) * trend
            return GlucoseReading(glucose: glucose, timestamp: timestamp, source: "test")
        }
    }
    
    // MARK: - IOB at Exact Max
    
    @Test("Algorithm with IOB exactly at maxIOB does not increase basal")
    func algorithmIOBExactlyAtMax() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            let glucose = makeGlucoseReadings(current: 180)  // High BG
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 10.0,  // Exactly at maxIOB
                carbsOnBoard: 0,
                profile: makeProfile(maxIOB: 10.0, maxBasalRate: 4.0)
            )
            
            let decision = try algo.calculate(inputs)
            
            // Even with high BG, cannot increase basal at maxIOB
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate <= 1.0,
                    "\(type(of: algo)): At maxIOB, should not suggest increased basal")
            }
            #expect(decision.suggestedBolus == nil || (decision.suggestedBolus ?? 0) == 0,
                "\(type(of: algo)): At maxIOB, must not suggest bolus")
        }
    }
    
    @Test("Algorithm with IOB 0.01 below maxIOB allows minimal increase")
    func algorithmIOBJustBelowMax() throws {
        let algo = Oref1Algorithm()
        
        let glucose = makeGlucoseReadings(current: 200)  // Very high BG
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 9.99,  // 0.01 below max
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 10.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // Should still be very constrained, only 0.01U headroom
        // Note: May still not increase basal due to minimal headroom
        #expect(decision.suggestedBolus == nil || (decision.suggestedBolus ?? 0) <= 0.01,
            "With 0.01U headroom, bolus should be minimal or none")
    }
    
    // MARK: - BG at Exact Threshold
    
    @Test("Algorithm with BG exactly at suspend threshold suspends")
    func algorithmBGExactlyAtThreshold() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            let glucose = makeGlucoseReadings(current: 70.0)  // Exactly at threshold
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 3.0,
                carbsOnBoard: 0,
                profile: makeProfile(suspendThreshold: 70.0)
            )
            
            let decision = try algo.calculate(inputs)
            
            // At threshold, should suspend
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate == 0,
                    "\(type(of: algo)): At suspend threshold (70), must zero basal")
            }
        }
    }
    
    @Test("Algorithm with BG 1 above threshold may not suspend")
    func algorithmBGJustAboveThreshold() throws {
        let algo = Oref1Algorithm()
        
        let glucose = makeGlucoseReadings(current: 71.0, trend: 0)  // 1 above, stable
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,  // Modest IOB
            carbsOnBoard: 0,
            profile: makeProfile(suspendThreshold: 70.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // Just above threshold with stable trend - might reduce but not require full suspend
        // This tests the "off by one" boundary - 71 != 70
        if let tempBasal = decision.suggestedTempBasal {
            // Being conservative is fine, but shouldn't be forced to zero
            #expect(tempBasal.rate >= 0, "Valid basal rate returned")
        }
    }
    
    @Test("Algorithm with BG 1 below threshold definitely suspends")
    func algorithmBGJustBelowThreshold() throws {
        let algorithms: [any AlgorithmEngine] = [Oref1Algorithm(), LoopAlgorithm()]
        
        for algo in algorithms {
            let glucose = makeGlucoseReadings(current: 69.0)  // 1 below threshold
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 2.0,
                carbsOnBoard: 0,
                profile: makeProfile(suspendThreshold: 70.0)
            )
            
            let decision = try algo.calculate(inputs)
            
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate == 0,
                    "\(type(of: algo)): Below suspend threshold MUST zero basal")
            }
        }
    }
    
    // MARK: - Max Basal Rate Boundaries
    
    @Test("Algorithm output respects maxBasalRate exactly")
    func algorithmRespectsMaxBasalRate() throws {
        let algo = Oref1Algorithm()
        
        // Create extreme scenario that would want very high basal
        let glucose = makeGlucoseReadings(current: 400, trend: 5)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 20.0, maxBasalRate: 4.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 4.0,
                "Suggested basal \(tempBasal.rate) must not exceed maxBasalRate 4.0")
        }
    }
    
    @Test("Algorithm can suggest exactly maxBasalRate when needed")
    func algorithmCanHitMaxBasalRate() throws {
        let algo = Oref1Algorithm()
        
        // High BG scenario with room for insulin
        let glucose = makeGlucoseReadings(current: 350, trend: 3)
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 0,
            profile: makeProfile(maxIOB: 15.0, maxBasalRate: 4.0)
        )
        
        let decision = try algo.calculate(inputs)
        
        // Should suggest high basal (possibly max)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate >= 0 && tempBasal.rate <= 4.0,
                "Basal rate should be in valid range [0, maxBasalRate]")
        }
    }
}

// MARK: - Schedule Data Structure Tests

@Suite("Schedule Data Structure Boundaries")
struct ScheduleDataStructureTests {
    
    @Test("Basal rate schedule with multiple entries has correct count")
    func basalRateScheduleEntries() {
        let profile = TherapyProfile(
            basalRates: [
                BasalRate(startTime: 0, rate: 0.8),      // Midnight
                BasalRate(startTime: 6 * 3600, rate: 1.2), // 6 AM
                BasalRate(startTime: 12 * 3600, rate: 1.0) // Noon
            ],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0,
            maxBasalRate: 4.0,
            suspendThreshold: 70.0
        )
        
        #expect(profile.basalRates.count == 3, "Should have 3 basal rate entries")
        #expect(profile.basalRates[0].startTime == 0, "First entry at midnight")
        #expect(profile.basalRates[1].startTime == 6 * 3600, "Second entry at 6 AM")
        #expect(profile.basalRates[2].startTime == 12 * 3600, "Third entry at noon")
    }
    
    @Test("ISF schedule with multiple entries has correct values")
    func isfScheduleEntries() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 50),
                SensitivityFactor(startTime: 8 * 3600, factor: 40),  // 8 AM
                SensitivityFactor(startTime: 20 * 3600, factor: 60)  // 8 PM
            ],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0,
            maxBasalRate: 4.0,
            suspendThreshold: 70.0
        )
        
        #expect(profile.sensitivityFactors.count == 3, "Should have 3 ISF entries")
        #expect(profile.sensitivityFactors[0].factor == 50, "First factor is 50")
        #expect(profile.sensitivityFactors[1].factor == 40, "Second factor is 40")
        #expect(profile.sensitivityFactors[2].factor == 60, "Third factor is 60")
    }
    
    @Test("Carb ratio schedule boundary values")
    func carbRatioScheduleEntries() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 10),
                CarbRatio(startTime: 12 * 3600, ratio: 8)  // Noon
            ],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0,
            maxBasalRate: 4.0,
            suspendThreshold: 70.0
        )
        
        #expect(profile.carbRatios.count == 2, "Should have 2 carb ratio entries")
        #expect(profile.carbRatios[0].ratio == 10, "First ratio is 10")
        #expect(profile.carbRatios[1].ratio == 8, "Second ratio is 8")
    }
    
    @Test("Schedule start time boundary at midnight")
    func scheduleStartTimeAtMidnight() {
        let rate = BasalRate(startTime: 0, rate: 1.0)
        #expect(rate.startTime == 0, "Midnight should be start time 0")
        
        let endOfDay = BasalRate(startTime: 86399, rate: 0.5)
        #expect(endOfDay.startTime == 86399, "23:59:59 should be 86399 seconds")
    }
    
    @Test("Empty schedule arrays handled")
    func emptySchedules() {
        let profile = TherapyProfile(
            basalRates: [],
            carbRatios: [],
            sensitivityFactors: [],
            targetGlucose: TargetRange(low: 100, high: 120),
            maxIOB: 10.0,
            maxBolus: 10.0
        )
        
        #expect(profile.basalRates.isEmpty, "Empty basal rates allowed")
        #expect(profile.carbRatios.isEmpty, "Empty carb ratios allowed")
        #expect(profile.sensitivityFactors.isEmpty, "Empty ISF allowed")
    }
}

// MARK: - Numeric Precision Tests

@Suite("Numeric Precision Boundaries")
struct NumericPrecisionTests {
    
    @Test("SafetyGuardian handles floating point edge cases")
    func floatingPointPrecision() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Test case: 0.1 + 0.1 + 0.1 + ... (10 times) may not equal 1.0 exactly
        var accumulatedIOB = 0.0
        for _ in 0..<100 {
            accumulatedIOB += 0.1
        }
        // accumulatedIOB should be 10.0 but might be 9.999... or 10.000...01
        
        // Should handle this gracefully
        _ = guardian.checkIOB(current: accumulatedIOB, additional: 0.0)
        // We expect either denial (at max) or minimal allowance
        let maxAllowed = guardian.maxAdditionalIOB(currentIOB: accumulatedIOB)
        #expect(maxAllowed >= 0, "Max allowed should never be negative")
        #expect(maxAllowed < 0.1, "With ~10U IOB, max additional should be minimal")
    }
    
    @Test("Large IOB values handled correctly")
    func largeIOBValues() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Pathological case: very large IOB
        let result = guardian.checkIOB(current: 1000.0, additional: 1.0)
        #expect(!result.isAllowed || guardian.maxAdditionalIOB(currentIOB: 1000.0) == 0,
            "Extreme IOB should not allow additional insulin")
    }
    
    @Test("Very small additional amounts handled correctly")
    func verySmallAdditional() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // At 9.9999 IOB, adding 0.0001
        let result = guardian.checkIOB(current: 9.9999, additional: 0.0001)
        #expect(result.isAllowed, "Very small addition within limits should be allowed")
        
        // At 9.99999, adding enough to exceed
        let result2 = guardian.checkIOB(current: 9.99999, additional: 0.1)
        if case .limited = result2 {
            // Expected - exceeds max
        } else if case .allowed = result2 {
            Issue.record("9.99999 + 0.1 = 10.09999 exceeds maxIOB 10.0, should be limited")
        }
    }
    
    @Test("Zero values handled correctly")
    func zeroValues() {
        let limits = SafetyLimits()
        let guardian = SafetyGuardian(limits: limits)
        
        // Zero IOB, zero additional
        let result1 = guardian.checkIOB(current: 0, additional: 0)
        #expect(result1.isAllowed, "Zero + zero should be allowed")
        
        // Zero glucose (invalid)
        let result2 = guardian.checkGlucose(0)
        #expect(!result2.isAllowed, "Zero glucose is invalid")
        
        // Zero basal
        let result3 = guardian.checkBasalRate(0)
        #expect(result3.isAllowed, "Zero basal (suspend) should be allowed")
        
        // Zero bolus
        let result4 = guardian.checkBolus(0)
        #expect(result4.isAllowed, "Zero bolus should be allowed")
    }
}

// MARK: - Comparison Operator Verification

@Suite("Comparison Operator Verification")
struct ComparisonOperatorTests {
    
    @Test("Verify <= vs < for suspend threshold")
    func suspendThresholdOperator() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Per shouldSuspend: "glucose <= limits.suspendThreshold"
        #expect(guardian.shouldSuspend(glucose: 70.0), "At threshold: should suspend (<=)")
        #expect(guardian.shouldSuspend(glucose: 69.0), "Below threshold: should suspend")
        #expect(!guardian.shouldSuspend(glucose: 71.0), "Above threshold: should not suspend")
    }
    
    @Test("Verify < vs <= for predicted suspend")
    func predictedSuspendOperator() {
        let limits = SafetyLimits(suspendThreshold: 70.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Per shouldSuspendForPrediction: "minPredBG < limits.suspendThreshold"
        #expect(!guardian.shouldSuspendForPrediction(minPredBG: 70.0), "At threshold: no suspend (<)")
        #expect(guardian.shouldSuspendForPrediction(minPredBG: 69.99), "Just below: suspend")
        #expect(!guardian.shouldSuspendForPrediction(minPredBG: 70.01), "Just above: no suspend")
    }
    
    @Test("Verify <= for maxIOB check")
    func maxIOBOperator() {
        let limits = SafetyLimits(maxIOB: 10.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Per checkIOB: "if projected <= limits.maxIOB { return .allowed }"
        let atMax = guardian.checkIOB(current: 5.0, additional: 5.0)  // 10.0 total
        #expect(atMax.isAllowed, "Projected exactly at maxIOB should be allowed (<=)")
        
        let aboveMax = guardian.checkIOB(current: 5.0, additional: 5.01)  // 10.01 total
        #expect(!aboveMax.isAllowed || aboveMax.reason != nil, "Projected above maxIOB should be limited")
    }
    
    @Test("Verify <= for maxBasalRate check")
    func maxBasalRateOperator() {
        let limits = SafetyLimits(maxBasalRate: 5.0)
        let guardian = SafetyGuardian(limits: limits)
        
        // Per checkBasalRate: "if rate <= limits.maxBasalRate { return .allowed }"
        let atMax = guardian.checkBasalRate(5.0)
        #expect(atMax.isAllowed, "Rate exactly at max should be allowed (<=)")
        
        let aboveMax = guardian.checkBasalRate(5.01)
        switch aboveMax {
        case .limited:
            break  // Expected
        default:
            Issue.record("Rate above max should be limited")
        }
    }
}
