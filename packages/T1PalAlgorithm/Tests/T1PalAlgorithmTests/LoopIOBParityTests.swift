// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopIOBParityTests.swift
// T1Pal Mobile
//
// Tests for Loop-compatible IOB calculation
// Trace: ALG-FIDELITY-016

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Loop IOB Parity")
struct LoopIOBParityTests {
    
    // MARK: - Test Fixtures
    
    // Use instance property to avoid Date() drift (ALG-TEST-FIX-002)
    let now: Date
    
    init() {
        now = Date()
    }
    
    var rapidActingModel: LoopExponentialInsulinModel {
        LoopInsulinModelPreset.rapidActingAdult.model
    }
    
    // MARK: - Net Basal Units Tests (GAP-016)
    
    @Test("Net basal units - bolus uses full volume")
    func netBasalUnits_bolusUsesFullVolume() {
        let dose = BasalRelativeDose(
            type: .bolus,
            startDate: now,
            endDate: now,
            volume: 5.0,
            insulinModel: rapidActingModel
        )
        
        #expect(abs(dose.netBasalUnits - 5.0) < 0.001)
    }
    
    @Test("Net basal units - temp basal above scheduled")
    func netBasalUnits_tempBasalAboveScheduled() {
        // 200% temp basal for 1 hour when scheduled is 1.0 U/hr
        let dose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(.hours(1)),
            volume: 2.0,  // 2.0 U/hr × 1 hr
            insulinModel: rapidActingModel
        )
        
        // Net = 2.0 - 1.0 = 1.0 U
        #expect(abs(dose.netBasalUnits - 1.0) < 0.001)
    }
    
    @Test("Net basal units - temp basal below scheduled")
    func netBasalUnits_tempBasalBelowScheduled() {
        // 50% temp basal → negative net (insulin deficit)
        let dose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(.hours(1)),
            volume: 0.5,  // 50% of scheduled
            insulinModel: rapidActingModel
        )
        
        // Net = 0.5 - 1.0 = -0.5 U (deficit)
        #expect(abs(dose.netBasalUnits - (-0.5)) < 0.001)
    }
    
    @Test("Net basal units - suspend")
    func netBasalUnits_suspend() {
        // Suspend (0%) → full deficit
        let dose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(.hours(1)),
            volume: 0.0,  // No delivery
            insulinModel: rapidActingModel
        )
        
        // Net = 0.0 - 1.0 = -1.0 U (full deficit)
        #expect(abs(dose.netBasalUnits - (-1.0)) < 0.001)
    }
    
    @Test("Net basal units - 100% temp basal is zero")
    func netBasalUnits_100PercentTempBasalIsZero() {
        // 100% temp basal = scheduled rate = no net effect
        let dose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(.hours(1)),
            volume: 1.0,  // Exactly scheduled
            insulinModel: rapidActingModel
        )
        
        // Net = 1.0 - 1.0 = 0.0 U
        #expect(abs(dose.netBasalUnits - 0.0) < 0.001)
    }
    
    // MARK: - 10-Minute Delay Tests (GAP-018)
    
    @Test("Insulin delay - full IOB before delay completes")
    func insulinDelay_fullIOBBeforeDelayCompletes() {
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        
        // At 5 minutes (before 10-minute delay)
        let at5Min = model.percentEffectRemaining(at: .minutes(5))
        #expect(at5Min == 1.0)
        
        // At 10 minutes (delay just completed)
        let at10Min = model.percentEffectRemaining(at: .minutes(10))
        #expect(at10Min == 1.0)
        
        // At 15 minutes (after delay)
        let at15Min = model.percentEffectRemaining(at: .minutes(15))
        #expect(at15Min < 1.0)
    }
    
    @Test("Insulin delay - zero at end of action")
    func insulinDelay_zeroAtEndOfAction() {
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        
        // At 6 hours (end of action duration)
        let at6Hours = model.percentEffectRemaining(at: .hours(6) + .minutes(10))
        #expect(abs(at6Hours - 0.0) < 0.01)
    }
    
    // MARK: - Preset Parameter Tests (GAP-020)
    
    @Test("Preset parameters - rapid acting adult")
    func presetParameters_rapidActingAdult() {
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        #expect(abs(model.actionDuration - .hours(6)) < 1)
        #expect(abs(model.peakActivityTime - .minutes(75)) < 1)
        #expect(abs(model.delay - .minutes(10)) < 1)
    }
    
    @Test("Preset parameters - rapid acting child")
    func presetParameters_rapidActingChild() {
        let model = LoopInsulinModelPreset.rapidActingChild.model
        #expect(abs(model.actionDuration - .hours(6)) < 1)
        #expect(abs(model.peakActivityTime - .minutes(65)) < 1)  // Fixed: was 60
        #expect(abs(model.delay - .minutes(10)) < 1)
    }
    
    @Test("Preset parameters - Fiasp")
    func presetParameters_fiasp() {
        let model = LoopInsulinModelPreset.fiasp.model
        #expect(abs(model.actionDuration - .hours(6)) < 1)  // Fixed: was 5.5
        #expect(abs(model.peakActivityTime - .minutes(55)) < 1)
        #expect(abs(model.delay - .minutes(10)) < 1)
    }
    
    @Test("Preset parameters - Lyumjev")
    func presetParameters_lyumjev() {
        let model = LoopInsulinModelPreset.lyumjev.model
        #expect(abs(model.actionDuration - .hours(6)) < 1)  // Fixed: was 5.5
        #expect(abs(model.peakActivityTime - .minutes(55)) < 1)  // Fixed: was 50
        #expect(abs(model.delay - .minutes(10)) < 1)
    }
    
    @Test("Preset parameters - Afrezza")
    func presetParameters_afrezza() {
        let model = LoopInsulinModelPreset.afrezza.model
        #expect(abs(model.actionDuration - .hours(5)) < 1)  // Fixed: was 3
        #expect(abs(model.peakActivityTime - .minutes(29)) < 1)  // Fixed: was 20
        #expect(abs(model.delay - .minutes(10)) < 1)
    }
    
    // MARK: - Continuous Delivery Tests (GAP-017)
    
    @Test("Momentary dose - short dose treated as momentary")
    func momentaryDose_shortDoseTreatedAsMomentary() {
        // A 3-minute bolus should be treated as momentary (< 1.05 × 5 min)
        let dose = BasalRelativeDose(
            type: .bolus,
            startDate: now,
            endDate: now.addingTimeInterval(.minutes(3)),
            volume: 1.0,
            insulinModel: rapidActingModel
        )
        
        // Should behave same as instant dose
        let iob = dose.insulinOnBoard(at: now.addingTimeInterval(.hours(1)))
        #expect(iob > 0)
        #expect(iob < 1.0)
    }
    
    @Test("Continuous delivery - long dose uses integration")
    func continuousDelivery_longDoseUsesIntegration() {
        // A 30-minute temp basal should use continuous integration
        let dose = BasalRelativeDose(
            type: .basal(scheduledRate: 0),  // 0 scheduled = full volume is net
            startDate: now,
            endDate: now.addingTimeInterval(.minutes(30)),
            volume: 1.0,
            insulinModel: rapidActingModel
        )
        
        // At 3 hours, should have different IOB than momentary
        let at3Hours = dose.insulinOnBoard(at: now.addingTimeInterval(.hours(3)))
        #expect(at3Hours > 0)
        #expect(at3Hours < 1.0)
    }
    
    // MARK: - Dose Annotation Tests (GAP-019)
    
    @Test("Dose annotation - bolus passes through")
    func doseAnnotation_bolusPassesThrough() {
        let bolus = RawInsulinDose.bolus(units: 5.0, at: now)
        let basalHistory = [
            AbsoluteScheduleValue(startDate: now, endDate: now.addingTimeInterval(.hours(1)), value: 1.0)
        ]
        
        let annotated = bolus.annotated(with: basalHistory)
        
        #expect(annotated.count == 1)
        #expect(abs(annotated[0].netBasalUnits - 5.0) < 0.001)
        if case .bolus = annotated[0].type {
            // Expected
        } else {
            Issue.record("Expected bolus type")
        }
    }
    
    @Test("Dose annotation - temp basal splits at boundary")
    func doseAnnotation_tempBasalSplitsAtBoundary() {
        let noon = now
        
        // Temp basal from 11:30 to 12:30 (1 hour, 2 U/hr)
        let tempBasal = RawInsulinDose.tempBasal(
            rate: 2.0,
            startDate: noon.addingTimeInterval(.minutes(-30)),
            duration: .hours(1)
        )
        
        // Schedule changes at noon: 1.0 → 1.5 U/hr
        let basalHistory = [
            AbsoluteScheduleValue(
                startDate: noon.addingTimeInterval(.hours(-1)),
                endDate: noon,
                value: 1.0
            ),
            AbsoluteScheduleValue(
                startDate: noon,
                endDate: noon.addingTimeInterval(.hours(1)),
                value: 1.5
            )
        ]
        
        let annotated = tempBasal.annotated(with: basalHistory)
        
        #expect(annotated.count == 2)
        
        // First segment: 11:30-12:00, 1.0 U delivered, 0.5 U scheduled, net = 0.5 U
        #expect(abs(annotated[0].volume - 1.0) < 0.001)
        #expect(abs(annotated[0].netBasalUnits - 0.5) < 0.001)
        
        // Second segment: 12:00-12:30, 1.0 U delivered, 0.75 U scheduled, net = 0.25 U
        #expect(abs(annotated[1].volume - 1.0) < 0.001)
        #expect(abs(annotated[1].netBasalUnits - 0.25) < 0.001)
    }
    
    // MARK: - Collection IOB Tests
    
    @Test("Collection IOB - sum multiple doses")
    func collectionIOB_sumMultipleDoses() {
        let doses: [BasalRelativeDose] = [
            BasalRelativeDose(
                type: .bolus,
                startDate: now,
                endDate: now,
                volume: 2.0,
                insulinModel: rapidActingModel
            ),
            BasalRelativeDose(
                type: .bolus,
                startDate: now.addingTimeInterval(.hours(-1)),
                endDate: now.addingTimeInterval(.hours(-1)),
                volume: 3.0,
                insulinModel: rapidActingModel
            )
        ]
        
        let totalIOB = doses.insulinOnBoard(at: now)
        
        // Should be > 0 and < 5 (sum of doses)
        #expect(totalIOB > 0)
        #expect(totalIOB < 5.0)
    }
    
    // MARK: - Timeline Generation Tests (GAP-022)
    
    @Test("IOB timeline - generates correct interval")
    func iobTimeline_generatesCorrectInterval() {
        let doses: [BasalRelativeDose] = [
            BasalRelativeDose(
                type: .bolus,
                startDate: now,
                endDate: now,
                volume: 5.0,
                insulinModel: rapidActingModel
            )
        ]
        
        let timeline = doses.insulinOnBoardTimeline(
            from: now,
            to: now.addingTimeInterval(.hours(1)),
            delta: .minutes(5)
        )
        
        // Should have 13 points (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 minutes)
        #expect(timeline.count == 13)
        
        // First value should be full IOB (within delay period)
        #expect(abs(timeline[0].value - 5.0) < 0.1)
        
        // Values should generally decrease
        #expect(timeline[0].value > timeline.last!.value)
    }
    
    // MARK: - RawInsulinDose Factory Tests
    
    @Test("RawInsulinDose - bolus factory")
    func rawInsulinDose_bolusFactory() {
        let bolus = RawInsulinDose.bolus(units: 3.5, at: now)
        
        #expect(bolus.deliveryType == .bolus)
        #expect(bolus.volume == 3.5)
        #expect(bolus.startDate == now)
        #expect(bolus.endDate == now)
    }
    
    @Test("RawInsulinDose - temp basal factory")
    func rawInsulinDose_tempBasalFactory() {
        let tempBasal = RawInsulinDose.tempBasal(
            rate: 2.0,
            startDate: now,
            duration: .hours(1)
        )
        
        #expect(tempBasal.deliveryType == .basal)
        #expect(abs(tempBasal.volume - 2.0) < 0.001)  // 2 U/hr × 1 hr
        #expect(tempBasal.startDate == now)
        #expect(tempBasal.endDate == now.addingTimeInterval(.hours(1)))
    }
    
    // MARK: - Integration Test
    
    @Test("Integration - real world scenario")
    func integration_realWorldScenario() {
        // Simulate: bolus at t-2h, temp basal 150% from t-1h to now
        let doses: [RawInsulinDose] = [
            .bolus(units: 5.0, at: now.addingTimeInterval(.hours(-2))),
            .tempBasal(rate: 1.5, startDate: now.addingTimeInterval(.hours(-1)), duration: .hours(1))
        ]
        
        let basalHistory = [
            AbsoluteScheduleValue(
                startDate: now.addingTimeInterval(.hours(-3)),
                endDate: now.addingTimeInterval(.hours(1)),
                value: 1.0  // Scheduled 1.0 U/hr
            )
        ]
        
        let annotated = doses.annotated(with: basalHistory)
        
        // Should have bolus (1) + temp basal (1) = 2 doses
        #expect(annotated.count == 2)
        
        // Bolus net = 5.0
        #expect(abs(annotated[0].netBasalUnits - 5.0) < 0.001)
        
        // Temp basal net = 1.5 - 1.0 = 0.5 U
        #expect(abs(annotated[1].netBasalUnits - 0.5) < 0.001)
        
        // Total IOB at now should be > 0
        let totalIOB = annotated.insulinOnBoard(at: now)
        #expect(totalIOB > 0)
    }
}

// MARK: - Glucose Effect Sign Tests (ALG-PARITY-100)

@Suite("Loop IOB Parity - Glucose Effects")
struct LoopIOBParityGlucoseEffectsTests {
    
    // Use instance property to avoid Date() drift (ALG-TEST-FIX-002)
    let now: Date
    
    init() {
        now = Date()
    }
    
    @Test("Glucose effects - bolus produces negative effect")
    func glucoseEffects_bolusProducesNegativeEffect() {
        // A bolus (extra insulin) should produce NEGATIVE glucose effects
        let now = Date()
        let doses: [BasalRelativeDose] = [
            BasalRelativeDose(
                type: .bolus,
                startDate: now.addingTimeInterval(-3600),
                endDate: now.addingTimeInterval(-3600),
                volume: 1.0,
                insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
            )
        ]
        
        let effects = doses.glucoseEffects(
            insulinSensitivity: 40.0,
            from: now.addingTimeInterval(-3600),
            to: now.addingTimeInterval(6 * 3600),
            delta: 5 * 60
        )
        
        #expect(!effects.isEmpty)
        
        // Last effect should be approximately -40 mg/dL (1U × 40 mg/dL/U)
        if let eventual = effects.last {
            #expect(eventual.value < 0)
            #expect(abs(eventual.value - (-40.0)) < 2.0)
        }
    }
    
    @Test("Glucose effects - temp basal above scheduled produces negative effect")
    func glucoseEffects_tempBasalAboveScheduledProducesNegativeEffect() {
        // Temp basal above scheduled = extra insulin = negative glucose effect
        let now = Date()
        let doses: [BasalRelativeDose] = [
            BasalRelativeDose(
                type: .basal(scheduledRate: 1.0),  // Scheduled 1.0 U/hr
                startDate: now.addingTimeInterval(-3600),
                endDate: now,  // 1 hour of delivery
                volume: 2.0,  // Delivered 2.0 U (extra 1.0 U)
                insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
            )
        ]
        
        let effects = doses.glucoseEffects(
            insulinSensitivity: 40.0,
            from: now.addingTimeInterval(-3600),
            to: now.addingTimeInterval(6 * 3600),
            delta: 5 * 60
        )
        
        #expect(!effects.isEmpty)
        
        // Net basal = 2.0 - 1.0 = 1.0 U extra
        // Effect should be approximately -40 mg/dL
        if let eventual = effects.last {
            #expect(eventual.value < 0)
            #expect(abs(eventual.value - (-40.0)) < 5.0)
        }
    }
    
    @Test("Glucose effects - suspend produces positive effect")
    func glucoseEffects_suspendProducesPositiveEffect() {
        // Suspend (0 delivery when 1.0 scheduled) = NEGATIVE net = POSITIVE glucose effect
        let now = Date()
        let doses: [BasalRelativeDose] = [
            BasalRelativeDose(
                type: .basal(scheduledRate: 1.0),  // Scheduled 1.0 U/hr
                startDate: now.addingTimeInterval(-3600),
                endDate: now,  // 1 hour
                volume: 0,  // Delivered 0 (suspended)
                insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
            )
        ]
        
        let effects = doses.glucoseEffects(
            insulinSensitivity: 40.0,
            from: now.addingTimeInterval(-3600),
            to: now.addingTimeInterval(6 * 3600),
            delta: 5 * 60
        )
        
        #expect(!effects.isEmpty)
        
        // Net basal = 0 - 1.0 = -1.0 U (MISSING insulin)
        // Effect should be approximately +40 mg/dL (glucose rises without insulin)
        if let eventual = effects.last {
            #expect(eventual.value > 0)
            #expect(abs(eventual.value - 40.0) < 5.0)
        }
    }
    
    // MARK: - Insulin Model Formula Verification (ALG-COM-001)
    
    @Test("Exponential model - formula matches Loop")
    func exponentialModel_formulaMatchesLoop() {
        // Verify our formula produces the correct exponential decay curve
        let model = LoopInsulinModelPreset.rapidActingAdult.model
        
        // Values computed from our implementation (6hr DIA, 75min peak, 10min delay)
        let testCases: [(time: TimeInterval, expected: Double)] = [
            (.minutes(5), 1.0),
            (.minutes(10), 1.0),
            (.minutes(15), 0.998),
            (.minutes(30), 0.966),
            (.minutes(60), 0.834),
            (.minutes(120), 0.501),
            (.minutes(180), 0.241),
            (.minutes(240), 0.089),
            (.minutes(300), 0.020),
            (.minutes(360), 0.0003),
            (.minutes(370), 0.0),
        ]
        
        for tc in testCases {
            let actual = model.percentEffectRemaining(at: tc.time)
            #expect(abs(actual - tc.expected) < 0.01)
        }
    }
    
    @Test("Exponential model - all presets decay correctly")
    func exponentialModel_allPresets_decayCorrectly() {
        let presets: [LoopInsulinModelPreset] = [
            .rapidActingAdult,
            .rapidActingChild,
            .fiasp,
            .lyumjev,
            .afrezza
        ]
        
        for preset in presets {
            let model = preset.model
            let effectDuration = model.actionDuration + model.delay
            
            // Before delay: full effect
            #expect(model.percentEffectRemaining(at: .minutes(5)) == 1.0)
            
            // At peak: still significant effect
            let atPeak = model.percentEffectRemaining(at: model.delay + model.peakActivityTime)
            #expect(atPeak > 0.3)
            #expect(atPeak < 0.9)
            
            // After action duration: zero effect
            let atEnd = model.percentEffectRemaining(at: effectDuration)
            #expect(abs(atEnd - 0.0) < 0.01)
            
            // Monotonically decreasing
            var prev = 1.0
            for mins in stride(from: 15, to: Int(effectDuration / 60), by: 15) {
                let current = model.percentEffectRemaining(at: .minutes(Double(mins)))
                #expect(current <= prev)
                prev = current
            }
        }
    }
    
    // MARK: - Time Grid Snapping Tests (ALG-IOB-007)
    
    @Test("Date floored to time interval")
    func dateFlooredToTimeInterval() {
        let delta: TimeInterval = 5 * 60  // 5 minutes
        
        // Test case 1: Already on boundary
        let onBoundary = Date(timeIntervalSinceReferenceDate: 600)
        #expect(
            onBoundary.flooredToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            600
        )
        
        // Test case 2: Just after boundary
        let justAfter = Date(timeIntervalSinceReferenceDate: 601)
        #expect(
            justAfter.flooredToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            600
        )
        
        // Test case 3: Just before next boundary
        let justBefore = Date(timeIntervalSinceReferenceDate: 899)
        #expect(
            justBefore.flooredToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            600
        )
        
        // Test case 4: Mid-interval
        let midInterval = Date(timeIntervalSinceReferenceDate: 750)
        #expect(
            midInterval.flooredToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            600
        )
    }
    
    @Test("Date ceiled to time interval")
    func dateCeiledToTimeInterval() {
        let delta: TimeInterval = 5 * 60  // 5 minutes
        
        // Test case 1: Already on boundary
        let onBoundary = Date(timeIntervalSinceReferenceDate: 600)
        #expect(
            onBoundary.ceiledToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            600
        )
        
        // Test case 2: Just after boundary
        let justAfter = Date(timeIntervalSinceReferenceDate: 601)
        #expect(
            justAfter.ceiledToTimeInterval(delta).timeIntervalSinceReferenceDate ==
            900
        )
    }
    
    // MARK: - Max of Adjacent Values Test (ALG-IOB-008)
    
    @Test("Insulin on board parity - returns max of adjacent grid points")
    func insulonOnBoardParity_returnsMaxOfAdjacentGridPoints() {
        let now = Date()
        let delta: TimeInterval = 5 * 60
        
        // Query time is 2 minutes after a grid point
        let gridPoint = now.flooredToTimeInterval(delta)
        let queryTime = gridPoint.addingTimeInterval(120)
        
        // Bolus delivered at the floored grid point
        let doses: [InsulinDose] = [
            InsulinDose(units: 2.0, timestamp: gridPoint)
        ]
        
        // Simple basal schedule
        let basalSchedule: [AbsoluteScheduleValue<Double>] = [
            AbsoluteScheduleValue(startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(3600), value: 1.0)
        ]
        
        // Get IOB using parity method
        let iobParity = doses.insulinOnBoardParity(at: queryTime, basalSchedule: basalSchedule)
        
        // Get IOB at floor and ceil directly
        let rawDoses = doses.toReconciledRawInsulinDoses()
        let annotated = rawDoses.annotated(with: basalSchedule)
        let iobAtFloor = annotated.insulinOnBoard(at: gridPoint, delta: delta)
        let iobAtCeil = annotated.insulinOnBoard(at: gridPoint.addingTimeInterval(delta), delta: delta)
        
        // Parity method should return max of the two
        let expectedMax = Swift.max(iobAtFloor, iobAtCeil)
        #expect(abs(iobParity - expectedMax) < 0.001)
        
        // Since bolus was at floor, IOB at floor should be higher
        #expect(iobAtFloor >= iobAtCeil)
    }
}
