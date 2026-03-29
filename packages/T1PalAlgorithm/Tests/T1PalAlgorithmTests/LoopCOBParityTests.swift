// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopCOBParityTests.swift
// T1Pal Mobile
//
// Tests for Loop-compatible COB calculation
// Trace: ALG-FIDELITY-017

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Loop COB Parity")
struct LoopCOBParityTests {
    
    // MARK: - Test Fixtures
    
    var now: Date { Date() }
    var defaultISF: Double { 50.0 }  // mg/dL per unit
    var defaultCR: Double { 10.0 }   // grams per unit
    
    // MARK: - Piecewise Linear Absorption Tests (GAP-025)
    
    @Test("Piecewise linear - zero at start")
    func piecewiseLinearZeroAtStart() {
        let model = PiecewiseLinearAbsorption()
        #expect(abs(model.percentAbsorptionAtPercentTime(0) - 0) < 0.001)
    }
    
    @Test("Piecewise linear - full at end")
    func piecewiseLinearFullAtEnd() {
        let model = PiecewiseLinearAbsorption()
        #expect(abs(model.percentAbsorptionAtPercentTime(1) - 1) < 0.001)
    }
    
    @Test("Piecewise linear - rise phase")
    func piecewiseLinearRisePhase() {
        let model = PiecewiseLinearAbsorption()
        
        // At 7.5% (middle of rise phase)
        let at7_5 = model.percentAbsorptionAtPercentTime(0.075)
        // At 15% (end of rise phase)
        let at15 = model.percentAbsorptionAtPercentTime(0.15)
        
        // Should be non-linear (quadratic) in rise phase
        #expect(at7_5 < at15 / 2, "Rise phase should be quadratic, not linear")
        #expect(at15 > 0.1, "Should have absorbed >10% by end of rise")
    }
    
    @Test("Piecewise linear - peak phase")
    func piecewiseLinearPeakPhase() {
        let model = PiecewiseLinearAbsorption()
        
        // In peak phase (15-50%), rate should be constant
        let rate_at_20 = model.percentRateAtPercentTime(0.2)
        let rate_at_30 = model.percentRateAtPercentTime(0.3)
        let rate_at_40 = model.percentRateAtPercentTime(0.4)
        
        #expect(abs(rate_at_20 - rate_at_30) < 0.001)
        #expect(abs(rate_at_30 - rate_at_40) < 0.001)
    }
    
    @Test("Piecewise linear - fall phase")
    func piecewiseLinearFallPhase() {
        let model = PiecewiseLinearAbsorption()
        
        // In fall phase (50-100%), rate should decrease
        let rate_at_60 = model.percentRateAtPercentTime(0.6)
        let rate_at_80 = model.percentRateAtPercentTime(0.8)
        let rate_at_100 = model.percentRateAtPercentTime(1.0)
        
        #expect(rate_at_60 > rate_at_80)
        #expect(rate_at_80 > rate_at_100)
        #expect(abs(rate_at_100 - 0) < 0.001)
    }
    
    @Test("Piecewise linear - inverse consistency")
    func piecewiseLinearInverseConsistency() {
        let model = PiecewiseLinearAbsorption()
        
        // Test that inverse function is consistent
        for percentTime in stride(from: 0.1, through: 0.9, by: 0.1) {
            let absorbed = model.percentAbsorptionAtPercentTime(percentTime)
            let recoveredTime = model.percentTimeAtPercentAbsorption(absorbed)
            #expect(abs(recoveredTime - percentTime) < 0.01,
                   "Inverse should recover original at \(percentTime)")
        }
    }
    
    // MARK: - 10-Minute Delay Tests (GAP-026)
    
    @Test("Effect delay - full COB before delay completes")
    func effectDelayFullCOBBeforeDelayCompletes() {
        let entry = SimpleCarbEntry(startDate: now, grams: 50)
        
        // At 5 minutes (before 10-minute delay)
        let cob_at_5min = entry.carbsOnBoard(at: now.addingTimeInterval(.minutes(5)))
        #expect(abs(cob_at_5min - 50) < 0.001, "Full COB before delay")
        
        // At 10 minutes (delay just completed, absorption just starting)
        let cob_at_10min = entry.carbsOnBoard(at: now.addingTimeInterval(.minutes(10)))
        #expect(abs(cob_at_10min - 50) < 0.5, "~Full COB at delay boundary")
    }
    
    @Test("Effect delay - absorption starts after delay")
    func effectDelayAbsorptionStartsAfterDelay() {
        let entry = SimpleCarbEntry(startDate: now, grams: 50)
        
        // At 30 minutes (20 min after delay)
        let cob_at_30min = entry.carbsOnBoard(at: now.addingTimeInterval(.minutes(30)))
        #expect(cob_at_30min < 50, "COB should decrease after delay")
        #expect(cob_at_30min > 0, "Some COB should remain")
    }
    
    // MARK: - Simple COB Tests
    
    @Test("Simple COB - zero before entry")
    func simpleCOBZeroBeforeEntry() {
        let entry = SimpleCarbEntry(
            startDate: now.addingTimeInterval(.hours(1)),
            grams: 50
        )
        
        let cob = entry.carbsOnBoard(at: now)
        #expect(cob == 0, "No COB before entry time")
    }
    
    @Test("Simple COB - zero after full absorption")
    func simpleCOBZeroAfterFullAbsorption() {
        let entry = SimpleCarbEntry(
            startDate: now,
            grams: 50,
            absorptionTime: .hours(3)
        )
        
        // At 4 hours (well past 3h absorption + 10min delay)
        let cob = entry.carbsOnBoard(at: now.addingTimeInterval(.hours(4)))
        #expect(abs(cob - 0) < 0.1, "Zero COB after full absorption")
    }
    
    @Test("Simple COB - custom absorption time")
    func simpleCOBCustomAbsorptionTime() {
        let fastEntry = SimpleCarbEntry(startDate: now, grams: 50, absorptionTime: .hours(1))
        let slowEntry = SimpleCarbEntry(startDate: now, grams: 50, absorptionTime: .hours(5))
        
        // At 1 hour after delay (1h 10min total)
        let fastCOB = fastEntry.carbsOnBoard(at: now.addingTimeInterval(.hours(1) + .minutes(10)))
        let slowCOB = slowEntry.carbsOnBoard(at: now.addingTimeInterval(.hours(1) + .minutes(10)))
        
        #expect(fastCOB < slowCOB, "Fast carbs absorb faster")
    }
    
    // MARK: - Collection COB Tests
    
    @Test("Collection COB - sum multiple entries")
    func collectionCOBSumMultipleEntries() {
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 30),
            SimpleCarbEntry(startDate: now.addingTimeInterval(.hours(-1)), grams: 20)
        ]
        
        let totalCOB = entries.carbsOnBoard(at: now)
        
        // Should be > 0 and < 50 (some absorbed from earlier entry)
        #expect(totalCOB > 0)
        #expect(totalCOB < 50)
    }
    
    // MARK: - CarbStatus Tests (GAP-024)
    
    @Test("Carb status - without observation")
    func carbStatusWithoutObservation() {
        let entry = SimpleCarbEntry(startDate: now, grams: 50)
        let status = CarbStatus(entry: entry)
        
        #expect(status.absorption == nil)
        #expect(status.observedTimeline == nil)
        
        // Dynamic COB should fall back to model
        let cob = status.dynamicCarbsOnBoard(at: now.addingTimeInterval(.hours(1)))
        #expect(cob > 0)
        #expect(cob < 50)
    }
    
    @Test("Carb status - with observation")
    func carbStatusWithObservation() {
        let entry = SimpleCarbEntry(startDate: now, grams: 50)
        let absorption = AbsorbedCarbValue(
            observed: 20,
            clamped: 20,
            total: 50,
            observationStart: now.addingTimeInterval(.minutes(10)),
            observationEnd: now.addingTimeInterval(.hours(1)),
            estimatedTimeRemaining: .hours(1.5),
            timeToAbsorbObservedCarbs: .minutes(50)
        )
        let timeline = [
            CarbValue(startDate: now.addingTimeInterval(.minutes(10)),
                     endDate: now.addingTimeInterval(.minutes(30)),
                     grams: 10),
            CarbValue(startDate: now.addingTimeInterval(.minutes(30)),
                     endDate: now.addingTimeInterval(.hours(1)),
                     grams: 10)
        ]
        
        let status = CarbStatus(entry: entry, absorption: absorption, observedTimeline: timeline)
        
        #expect(status.absorption != nil)
        #expect(abs(status.absorption!.remaining - 30) < 0.001)
    }
    
    // MARK: - ICE Mapping Tests (GAP-023, GAP-029)
    
    @Test("Map - single entry positive velocity")
    func mapSingleEntryPositiveVelocity() {
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 50)
        ]
        
        // ICE: glucose rising 10 mg/dL over 30 min (after delay)
        let velocities = [
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(15)),
                endDate: now.addingTimeInterval(.minutes(45)),
                quantity: 10
            )
        ]
        
        let statuses = entries.map(
            to: velocities,
            insulinSensitivity: defaultISF,
            carbRatio: defaultCR
        )
        
        #expect(statuses.count == 1)
        #expect(statuses[0].absorption != nil)
        #expect((statuses[0].absorption?.observed ?? 0) > 0)
    }
    
    @Test("Map - ignores negative velocity")
    func mapIgnoresNegativeVelocity() {
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 50)
        ]
        
        // Negative velocity (glucose dropping - insulin activity)
        let velocities = [
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(15)),
                endDate: now.addingTimeInterval(.minutes(45)),
                quantity: -10
            )
        ]
        
        let statuses = entries.map(
            to: velocities,
            insulinSensitivity: defaultISF,
            carbRatio: defaultCR
        )
        
        #expect(statuses.count == 1)
        // Should have no observed absorption (negative ignored)
        #expect(statuses[0].absorption == nil)
    }
    
    @Test("Map - distributes effect proportionally")
    func mapDistributesEffectProportionally() {
        // Two entries with same absorption time, started at same time
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 30),  // 60% of total
            SimpleCarbEntry(startDate: now, grams: 20)   // 40% of total
        ]
        
        let velocities = [
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(15)),
                endDate: now.addingTimeInterval(.minutes(45)),
                quantity: 25  // 25 mg/dL rise
            )
        ]
        
        let statuses = entries.map(
            to: velocities,
            insulinSensitivity: defaultISF,
            carbRatio: defaultCR
        )
        
        #expect(statuses.count == 2)
        
        // Both should have absorption
        let obs1 = statuses[0].absorption?.observed ?? 0
        let obs2 = statuses[1].absorption?.observed ?? 0
        
        #expect(obs1 > 0)
        #expect(obs2 > 0)
        
        // First entry should absorb more (proportional to grams/rate)
        // Since they have same absorption time, ratio should be ~60:40
        let ratio = obs1 / (obs1 + obs2)
        #expect(abs(ratio - 0.6) < 0.1, "Should distribute ~60:40")
    }
    
    // MARK: - Linear Absorption Tests
    
    @Test("Linear absorption - uniform rate")
    func linearAbsorptionUniformRate() {
        let model = LinearAbsorption()
        
        let rate_25 = model.percentRateAtPercentTime(0.25)
        let rate_50 = model.percentRateAtPercentTime(0.50)
        let rate_75 = model.percentRateAtPercentTime(0.75)
        
        #expect(rate_25 == 1.0)
        #expect(rate_50 == 1.0)
        #expect(rate_75 == 1.0)
    }
    
    @Test("Linear absorption - linear progress")
    func linearAbsorptionLinearProgress() {
        let model = LinearAbsorption()
        
        #expect(abs(model.percentAbsorptionAtPercentTime(0.25) - 0.25) < 0.001)
        #expect(abs(model.percentAbsorptionAtPercentTime(0.50) - 0.50) < 0.001)
        #expect(abs(model.percentAbsorptionAtPercentTime(0.75) - 0.75) < 0.001)
    }
    
    // MARK: - Constants Tests
    
    @Test("Constants - default values")
    func constantsDefaultValues() {
        #expect(COBConstants.maximumAbsorptionTimeInterval == .hours(10))
        #expect(COBConstants.defaultAbsorptionTime == .hours(3))
        #expect(COBConstants.defaultAbsorptionTimeOverrun == 1.5)
        #expect(COBConstants.defaultEffectDelay == .minutes(10))
    }
    
    // MARK: - Timeline Generation Tests
    
    @Test("COB timeline - generates correct interval")
    func cobTimelineGeneratesCorrectInterval() {
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 50)
        ]
        
        let timeline = entries.carbsOnBoardTimeline(
            from: now,
            to: now.addingTimeInterval(.hours(1)),
            delta: .minutes(5)
        )
        
        // Should have 13 points (0, 5, 10, ..., 60 minutes)
        #expect(timeline.count == 13)
        
        // First value should be full COB (in delay period)
        #expect(abs(timeline[0].value - 50) < 0.1)
        
        // Values should generally decrease after delay
        #expect(timeline[2].value > timeline.last!.value)
    }
    
    // MARK: - Glucose Effect Tests
    
    @Test("Glucose effect - calculation")
    func glucoseEffectCalculation() {
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now, grams: 50)
        ]
        
        // At 3+ hours after delay, all carbs absorbed
        let effect = entries.glucoseEffect(
            at: now.addingTimeInterval(.hours(4)),
            insulinSensitivity: defaultISF,
            carbRatio: defaultCR
        )
        
        // CSF = 50 / 10 = 5 mg/dL per gram
        // Full absorption of 50g = 250 mg/dL effect
        #expect(abs(effect - 250) < 5)
    }
    
    // MARK: - Integration Test
    
    @Test("Integration - real world scenario")
    func integrationRealWorldScenario() {
        // Meal: 60g carbs at t-1h, 30g snack at t-30min
        let entries: [SimpleCarbEntry] = [
            SimpleCarbEntry(startDate: now.addingTimeInterval(.hours(-1)), grams: 60),
            SimpleCarbEntry(startDate: now.addingTimeInterval(.minutes(-30)), grams: 30)
        ]
        
        // ICE showing glucose rising
        let velocities = [
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(-50)),
                endDate: now.addingTimeInterval(.minutes(-30)),
                quantity: 30
            ),
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(-30)),
                endDate: now.addingTimeInterval(.minutes(-10)),
                quantity: 25
            ),
            GlucoseEffectVelocity(
                startDate: now.addingTimeInterval(.minutes(-10)),
                endDate: now,
                quantity: 15
            )
        ]
        
        let statuses = entries.map(
            to: velocities,
            insulinSensitivity: defaultISF,
            carbRatio: defaultCR
        )
        
        #expect(statuses.count == 2)
        
        // First entry (earlier) should have more observed absorption
        let obs1 = statuses[0].absorption?.observed ?? 0
        let obs2 = statuses[1].absorption?.observed ?? 0
        
        // Both should have some observation
        #expect(obs1 > 0)
        #expect(obs2 >= 0)  // May be 0 if still in delay for some velocities
    }
    
    // MARK: - ICE Counteraction Effects Tests (ALG-COM-008)
    
    @Test("Counteraction effects - matches Loop algorithm")
    func counteractionEffectsMatchesLoopAlgorithm() {
        // Test setup: glucose readings and insulin effects
        // This matches Loop's GlucoseMath.swift counteractionEffects algorithm
        
        let readings: [GlucoseReading] = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(.minutes(-20))),
            GlucoseReading(glucose: 105, timestamp: now.addingTimeInterval(.minutes(-15))),
            GlucoseReading(glucose: 112, timestamp: now.addingTimeInterval(.minutes(-10))),
            GlucoseReading(glucose: 118, timestamp: now.addingTimeInterval(.minutes(-5))),
            GlucoseReading(glucose: 122, timestamp: now)
        ]
        
        // Insulin effects (cumulative) - insulin pulling glucose down
        let insulinEffects: [GlucoseEffect] = [
            GlucoseEffect(date: now.addingTimeInterval(.minutes(-20)), quantity: 0),
            GlucoseEffect(date: now.addingTimeInterval(.minutes(-15)), quantity: -2),
            GlucoseEffect(date: now.addingTimeInterval(.minutes(-10)), quantity: -5),
            GlucoseEffect(date: now.addingTimeInterval(.minutes(-5)), quantity: -8),
            GlucoseEffect(date: now, quantity: -10)
        ]
        
        let ice = readings.counteractionEffects(to: insulinEffects)
        
        // Should produce ICE entries for valid 5-min intervals (> 4 min required)
        #expect(ice.count > 0, "Should generate ICE entries")
        
        // Each ICE entry should be velocity (mg/dL per second)
        for entry in ice {
            // Glucose is rising, insulin is pulling down
            // ICE = glucoseChange - effectChange
            // glucoseChange is positive (rising), effectChange is negative (more negative)
            // So ICE should be positive (glucose rising more than insulin predicts)
            let duration = entry.endDate.timeIntervalSince(entry.startDate)
            #expect(duration > 4 * 60, "Duration should be > 4 minutes")
            
            // Velocity should be reasonable (not huge)
            let totalEffect = entry.quantity * duration
            #expect(abs(totalEffect) < 50, "Total effect should be reasonable")
        }
    }
    
    @Test("Counteraction effects - empty inputs returns empty")
    func counteractionEffectsEmptyInputsReturnsEmpty() {
        let emptyReadings: [GlucoseReading] = []
        let effects: [GlucoseEffect] = [
            GlucoseEffect(date: now, quantity: 0)
        ]
        
        let ice = emptyReadings.counteractionEffects(to: effects)
        #expect(ice.isEmpty, "Empty glucose readings should return empty ICE")
        
        let readings: [GlucoseReading] = [
            GlucoseReading(glucose: 100, timestamp: now)
        ]
        let emptyEffects: [GlucoseEffect] = []
        
        let ice2 = readings.counteractionEffects(to: emptyEffects)
        #expect(ice2.isEmpty, "Empty effects should return empty ICE")
    }
    
    @Test("Counteraction effects - velocity is per second")
    func counteractionEffectsVelocityIsPerSecond() {
        // Capture a single reference time to avoid timing drift
        let referenceTime = Date()
        
        // 10 minute interval, glucose rises 30 mg/dL, insulin effect -10 mg/dL
        let readings: [GlucoseReading] = [
            GlucoseReading(glucose: 100, timestamp: referenceTime.addingTimeInterval(.minutes(-10))),
            GlucoseReading(glucose: 130, timestamp: referenceTime)
        ]
        
        let effects: [GlucoseEffect] = [
            GlucoseEffect(date: referenceTime.addingTimeInterval(.minutes(-10)), quantity: 0),
            GlucoseEffect(date: referenceTime, quantity: -10)
        ]
        
        let ice = readings.counteractionEffects(to: effects)
        
        // Guard against empty result before accessing first element
        guard ice.count == 1 else {
            Issue.record("Expected 1 ICE entry but got \(ice.count)")
            return
        }
        
        // glucoseChange = 130 - 100 = 30
        // effectChange = -10 - 0 = -10
        // discrepancy = 30 - (-10) = 40
        // timeInterval = 10 * 60 = 600 seconds
        // velocity = 40 / 600 = 0.0667 mg/dL/s
        let expectedVelocity = 40.0 / 600.0
        #expect(abs(ice[0].quantity - expectedVelocity) < 0.001,
               "Velocity should be discrepancy / timeInterval")
    }
}
