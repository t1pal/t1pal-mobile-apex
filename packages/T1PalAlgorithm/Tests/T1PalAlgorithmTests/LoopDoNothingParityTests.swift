// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopDoNothingParityTests.swift
// T1Pal Mobile
//
// Tests for "do nothing" recommendation and temp basal continuation
// Trace: ALG-FIDELITY-018

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Loop Do Nothing Parity")
struct LoopDoNothingParityTests {
    
    // MARK: - Test Fixtures
    
    var now: Date { Date() }
    var targetRange: ClosedRange<Double> { 100...120 }
    var suspendThreshold: Double { 70 }
    
    // MARK: - LoopAlgorithmError Tests (GAP-046, GAP-047)
    
    @Test("Missing glucose throws error")
    func loopAlgorithmErrorMissingGlucose() throws {
        #expect(throws: LoopAlgorithmError.missingGlucose) {
            try validateAlgorithmInputs(
                lastGlucoseDate: nil,
                basalScheduleEnd: now.addingTimeInterval(.hours(6)),
                sensitivityScheduleStart: now.addingTimeInterval(.hours(-1)),
                sensitivityScheduleEnd: now.addingTimeInterval(.hours(6)),
                suspendThreshold: 70
            )
        }
    }
    
    @Test("Old glucose throws error")
    func loopAlgorithmErrorGlucoseTooOld() throws {
        let oldGlucoseDate = now.addingTimeInterval(.minutes(-20))
        
        do {
            try validateAlgorithmInputs(
                lastGlucoseDate: oldGlucoseDate,
                basalScheduleEnd: now.addingTimeInterval(.hours(6)),
                sensitivityScheduleStart: now.addingTimeInterval(.hours(-1)),
                sensitivityScheduleEnd: now.addingTimeInterval(.hours(6)),
                suspendThreshold: 70,
                at: now
            )
            Issue.record("Expected glucoseTooOld error")
        } catch let error as LoopAlgorithmError {
            if case .glucoseTooOld(let age) = error {
                #expect(abs(age - .minutes(20)) < 1)
            } else {
                Issue.record("Expected glucoseTooOld error")
            }
        } catch {
            Issue.record("Expected LoopAlgorithmError")
        }
    }
    
    @Test("Missing suspend threshold throws error")
    func loopAlgorithmErrorMissingSuspendThreshold() throws {
        #expect(throws: LoopAlgorithmError.missingSuspendThreshold) {
            try validateAlgorithmInputs(
                lastGlucoseDate: now,
                basalScheduleEnd: now.addingTimeInterval(.hours(6)),
                sensitivityScheduleStart: now.addingTimeInterval(.hours(-1)),
                sensitivityScheduleEnd: now.addingTimeInterval(.hours(6)),
                suspendThreshold: nil,
                at: now
            )
        }
    }
    
    @Test("Valid inputs pass validation")
    func algorithmValidationPassesWithValidInputs() throws {
        // Capture a single reference time to avoid timing drift between date computations
        let referenceTime = Date()
        #expect(throws: Never.self) {
            try validateAlgorithmInputs(
                lastGlucoseDate: referenceTime.addingTimeInterval(.minutes(-5)),
                basalScheduleEnd: referenceTime.addingTimeInterval(.hours(7)),
                sensitivityScheduleStart: referenceTime.addingTimeInterval(.hours(-1)),
                sensitivityScheduleEnd: referenceTime.addingTimeInterval(.hours(7)),
                suspendThreshold: 70,
                at: referenceTime
            )
        }
    }
    
    // MARK: - InsulinCorrection Tests (GAP-048, GAP-049)
    
    @Test("In range correction")
    func insulinCorrectionInRange() {
        let predictions = [110.0, 115.0, 118.0, 115.0, 112.0]  // All in 100-120
        
        let result = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(result == .inRange)
        #expect(result.direction == .neutral)
        #expect(result.isDoNothing)
    }
    
    @Test("Above range correction")
    func insulinCorrectionAboveRange() {
        let predictions = [120.0, 130.0, 140.0, 150.0, 155.0]  // Ending above 120
        
        let result = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        if case .aboveRange(let minGlucose, let eventualGlucose, _) = result {
            #expect(minGlucose == 120.0)
            #expect(eventualGlucose == 155.0)
        } else {
            Issue.record("Expected aboveRange")
        }
        
        #expect(result.direction == .increase)
        #expect(!result.requiresSuspend)
    }
    
    @Test("Below range correction")
    func insulinCorrectionBelowRange() {
        let predictions = [95.0, 90.0, 85.0, 80.0, 75.0]  // Ending below 100
        
        let result = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        if case .entirelyBelowRange(let minGlucose, let eventualGlucose, _) = result {
            #expect(minGlucose == 75.0)
            #expect(eventualGlucose == 75.0)
        } else {
            Issue.record("Expected entirelyBelowRange")
        }
        
        #expect(result.direction == .decrease)
    }
    
    @Test("Suspend on any below threshold")
    func insulinCorrectionSuspendOnAnyBelowThreshold() {
        // GAP-049: ANY prediction below threshold triggers suspend
        let predictions = [100.0, 110.0, 120.0, 65.0, 110.0]  // One point at 65
        
        let result = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        if case .suspend(let minGlucose) = result {
            #expect(minGlucose == 65.0)
        } else {
            Issue.record("Expected suspend, got \(result)")
        }
        
        #expect(result.requiresSuspend)
        #expect(result.isDoNothing)
        #expect(result.direction == .decrease)
    }
    
    @Test("Suspend takes precedence")
    func insulinCorrectionSuspendTakesPrecedence() {
        // Even if eventual glucose is high, suspend if any point is below threshold
        let predictions = [100.0, 60.0, 150.0, 200.0]
        
        let result = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(result.requiresSuspend, "Suspend should take precedence")
    }
    
    // MARK: - DoseDirection Tests (GAP-051)
    
    @Test("Dose direction from correction")
    func doseDirectionFromCorrection() {
        #expect(InsulinCorrection.inRange.direction == .neutral)
        #expect(InsulinCorrection.suspend(minGlucose: 60).direction == .decrease)
        #expect(InsulinCorrection.aboveRange(minGlucose: 100, eventualGlucose: 150, correctionUnits: 1.0).direction == .increase)
        #expect(InsulinCorrection.entirelyBelowRange(minGlucose: 80, eventualGlucose: 85, correctionUnits: -0.5).direction == .decrease)
    }
    
    // MARK: - TempBasal Tests
    
    @Test("Temp basal cancel sentinel")
    func tempBasalCancelSentinel() {
        let cancel = LoopTempBasal.cancel
        
        #expect(cancel.isCancel)
        #expect(cancel.duration == 0)
    }
    
    @Test("Temp basal matches rate")
    func tempBasalMatchesRate() {
        let temp = LoopTempBasal(rate: 1.0, duration: .minutes(30))
        
        #expect(temp.matchesRate(1.0))
        #expect(!temp.matchesRate(1.1))
        #expect(!temp.matchesRate(0.9))
    }
    
    // MARK: - ifNecessary Tests (GAP-053..057)
    
    @Test("No action when temp running with time")
    func ifNecessaryNoActionWhenTempRunningWithTime() {
        let recommended = LoopTempBasal(rate: 1.5, duration: .minutes(30))
        
        let currentState = CurrentDeliveryState(
            currentTempBasal: LoopTempBasal(rate: 1.5, duration: .minutes(30)),
            tempBasalEndTime: now.addingTimeInterval(.minutes(20)),  // 20 min remaining
            scheduledBasalRate: 1.0
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        if case .noAction(let reason) = action {
            #expect(reason == .tempBasalRunningWithSufficientTime)
        } else {
            Issue.record("Expected noAction")
        }
    }
    
    @Test("Reissue when temp expiring soon")
    func ifNecessaryReissueWhenTempExpiringSoon() {
        let recommended = LoopTempBasal(rate: 1.5, duration: .minutes(30))
        
        let currentState = CurrentDeliveryState(
            currentTempBasal: LoopTempBasal(rate: 1.5, duration: .minutes(30)),
            tempBasalEndTime: now.addingTimeInterval(.minutes(5)),  // Only 5 min remaining
            scheduledBasalRate: 1.0
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        if case .setTempBasal(let temp) = action {
            #expect(temp.rate == 1.5)
        } else {
            Issue.record("Expected setTempBasal")
        }
    }
    
    @Test("Cancel when recommended matches scheduled")
    func ifNecessaryCancelWhenRecommendedMatchesScheduled() {
        let recommended = LoopTempBasal(rate: 1.0, duration: .minutes(30))  // Matches scheduled
        
        let currentState = CurrentDeliveryState(
            currentTempBasal: LoopTempBasal(rate: 1.5, duration: .minutes(30)),
            tempBasalEndTime: now.addingTimeInterval(.minutes(20)),
            scheduledBasalRate: 1.0  // Recommended matches this
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        #expect(action == .cancelTempBasal)
    }
    
    @Test("No action when already at scheduled")
    func ifNecessaryNoActionWhenAlreadyAtScheduled() {
        let recommended = LoopTempBasal(rate: 1.0, duration: .minutes(30))  // Matches scheduled
        
        let currentState = CurrentDeliveryState(
            currentTempBasal: nil,  // No temp running
            tempBasalEndTime: nil,
            scheduledBasalRate: 1.0  // Already at scheduled
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        if case .noAction(let reason) = action {
            #expect(reason == .alreadyAtScheduledBasal)
        } else {
            Issue.record("Expected noAction")
        }
    }
    
    @Test("Set temp when different from scheduled")
    func ifNecessarySetTempWhenDifferentFromScheduled() {
        let recommended = LoopTempBasal(rate: 1.5, duration: .minutes(30))  // Different from scheduled
        
        let currentState = CurrentDeliveryState(
            currentTempBasal: nil,
            tempBasalEndTime: nil,
            scheduledBasalRate: 1.0
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        if case .setTempBasal(let temp) = action {
            #expect(temp.rate == 1.5)
        } else {
            Issue.record("Expected setTempBasal")
        }
    }
    
    // MARK: - CurrentDeliveryState Tests
    
    @Test("Has temp running")
    func currentDeliveryStateHasTempRunning() {
        let state = CurrentDeliveryState(
            currentTempBasal: LoopTempBasal(rate: 1.5, duration: .minutes(30)),
            tempBasalEndTime: now.addingTimeInterval(.minutes(15)),
            scheduledBasalRate: 1.0
        )
        
        #expect(state.hasTempBasalRunning(at: now))
        #expect(abs(state.timeRemaining(at: now) - .minutes(15)) < 1)
    }
    
    @Test("No temp running")
    func currentDeliveryStateNoTempRunning() {
        let state = CurrentDeliveryState(
            currentTempBasal: nil,
            tempBasalEndTime: nil,
            scheduledBasalRate: 1.0
        )
        
        #expect(!state.hasTempBasalRunning(at: now))
        #expect(state.timeRemaining(at: now) == 0)
    }
    
    @Test("Expired temp")
    func currentDeliveryStateExpiredTemp() {
        let state = CurrentDeliveryState(
            currentTempBasal: LoopTempBasal(rate: 1.5, duration: .minutes(30)),
            tempBasalEndTime: now.addingTimeInterval(.minutes(-5)),  // Expired 5 min ago
            scheduledBasalRate: 1.0
        )
        
        #expect(!state.hasTempBasalRunning(at: now))
        #expect(state.timeRemaining(at: now) == 0)
    }
    
    // MARK: - BolusRecommendationNotice Tests (GAP-050)
    
    @Test("Bolus notice glucose below suspend")
    func bolusNoticeGlucoseBelowSuspend() {
        let notice = calculateBolusNotice(
            currentGlucose: 60,
            predictions: [60, 70, 80],
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(notice == .glucoseBelowSuspendThreshold)
    }
    
    @Test("Bolus notice current below target")
    func bolusNoticeCurrentBelowTarget() {
        let notice = calculateBolusNotice(
            currentGlucose: 90,  // Below 100
            predictions: [90, 100, 110],
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(notice == .currentGlucoseBelowTarget)
    }
    
    @Test("Bolus notice predicted below target")
    func bolusNoticePredictedBelowTarget() {
        let notice = calculateBolusNotice(
            currentGlucose: 110,
            predictions: [110, 95, 90],  // Dropping below target
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(notice == .predictedGlucoseBelowTarget)
    }
    
    @Test("Bolus notice in range")
    func bolusNoticeInRange() {
        let notice = calculateBolusNotice(
            currentGlucose: 110,
            predictions: [110, 112, 115, 118, 115],  // All in range
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(notice == .predictedGlucoseInRange)
    }
    
    @Test("Bolus notice above range no notice")
    func bolusNoticeAboveRangeNoNotice() {
        let notice = calculateBolusNotice(
            currentGlucose: 150,
            predictions: [150, 160, 170],  // All above range
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(notice == nil, "No notice for above range (correction available)")
    }
    
    // MARK: - LoopDoseRecommendationType Tests
    
    @Test("Loop dose recommendation type values")
    func loopDoseRecommendationTypeValues() {
        #expect(LoopDoseRecommendationType.noAction.rawValue == "no_action")
        #expect(LoopDoseRecommendationType.continueTempBasal.rawValue == "continue_temp_basal")
        #expect(LoopDoseRecommendationType.suspend.rawValue == "suspend")
    }
    
    // MARK: - Integration Test
    
    @Test("Full decision flow integration")
    func integrationFullDecisionFlow() throws {
        // Capture a single reference time to avoid timing drift between date computations
        let referenceTime = Date()
        // Validate inputs
        try validateAlgorithmInputs(
            lastGlucoseDate: referenceTime.addingTimeInterval(.minutes(-3)),
            basalScheduleEnd: referenceTime.addingTimeInterval(.hours(7)),
            sensitivityScheduleStart: referenceTime.addingTimeInterval(.hours(-1)),
            sensitivityScheduleEnd: referenceTime.addingTimeInterval(.hours(7)),
            suspendThreshold: 70,
            at: referenceTime
        )
        
        // Calculate correction
        let predictions = [100.0, 105.0, 110.0, 115.0, 110.0]
        let correction = calculateInsulinCorrection(
            predictions: predictions,
            targetRange: targetRange,
            suspendThreshold: suspendThreshold
        )
        
        #expect(correction == .inRange)
        
        // Generate temp basal recommendation
        let recommended = LoopTempBasal(rate: 1.0, duration: .minutes(30))
        
        // Check if necessary
        let currentState = CurrentDeliveryState(
            currentTempBasal: nil,
            tempBasalEndTime: nil,
            scheduledBasalRate: 1.0
        )
        
        let action = recommended.ifNecessary(currentState: currentState, at: now)
        
        // Should be noAction since we're already at scheduled
        if case .noAction(let reason) = action {
            #expect(reason == .alreadyAtScheduledBasal)
        } else {
            Issue.record("Expected noAction")
        }
    }
}
