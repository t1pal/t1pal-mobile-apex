// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopDataStalenessParityTests.swift
// T1Pal Mobile
//
// Tests for data staleness checks and graceful degradation
// Trace: ALG-FIDELITY-019

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Loop Data Staleness Parity")
struct LoopDataStalenessParityTests {
    
    // MARK: - Test Fixtures
    
    var now: Date { Date() }
    let validator = DataQualityValidator()
    let gapFiller = DoseGapFiller()
    let degradation = GracefulDegradation()
    
    func makeReadings(
        count: Int,
        interval: TimeInterval = .minutes(5),
        startGlucose: Double = 100,
        glucoseStep: Double = 2,
        startDate: Date? = nil,
        sourceIdentifier: String? = "G6",
        isCalibration: Bool = false
    ) -> [SimpleGlucoseReading] {
        let now = Date()
        let start = startDate ?? now.addingTimeInterval(-interval * Double(count - 1))
        return (0..<count).map { i in
            SimpleGlucoseReading(
                timestamp: start.addingTimeInterval(interval * Double(i)),
                glucose: startGlucose + glucoseStep * Double(i),
                sourceIdentifier: sourceIdentifier,
                isCalibration: isCalibration
            )
        }
    }
    
    // MARK: - Constants Tests
    
    @Test("Constants match Loop")
    func constants_matchLoop() {
        #expect(DataQualityConstants.continuityInterval == .minutes(5))
        #expect(DataQualityConstants.maxGlucoseAge == .minutes(15))
        #expect(DataQualityConstants.gradualTransitionThreshold == 40.0)
        #expect(DataQualityConstants.minimumReadingsForMomentum == 3)
    }
    
    // MARK: - Continuity Tests (GAP-058)
    
    @Test("Continuity passes with 5 min intervals")
    func continuity_passesWith5MinIntervals() {
        let readings = makeReadings(count: 4, interval: .minutes(5))
        
        #expect(validator.isContinuous(readings))
    }
    
    @Test("Continuity fails with gap")
    func continuity_failsWithGap() {
        let now = Date()
        // Create readings with a 10-minute gap
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-15)), glucose: 100),
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-10)), glucose: 102),
            // Gap here - missing reading at -5 min
            SimpleGlucoseReading(timestamp: now, glucose: 106)
        ]
        
        #expect(!validator.isContinuous(readings))
    }
    
    @Test("Continuity single reading is valid")
    func continuity_singleReadingIsValid() {
        let readings = [SimpleGlucoseReading(timestamp: now, glucose: 100)]
        
        #expect(validator.isContinuous(readings))
    }
    
    @Test("Continuity empty array is false")
    func continuity_emptyArrayIsFalse() {
        let readings: [SimpleGlucoseReading] = []
        
        #expect(!validator.isContinuous(readings))
    }
    
    // MARK: - Gradual Transition Tests (GAP-059)
    
    @Test("Gradual transitions passes with 2mg per reading")
    func gradualTransitions_passesWith2mgPerReading() {
        let readings = makeReadings(count: 4, glucoseStep: 2)
        
        #expect(validator.hasGradualTransitions(readings))
    }
    
    @Test("Gradual transitions fails with large jump")
    func gradualTransitions_failsWithLargeJump() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-10)), glucose: 100),
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 150),  // 50 mg/dL jump!
            SimpleGlucoseReading(timestamp: now, glucose: 155)
        ]
        
        #expect(!validator.hasGradualTransitions(readings))
    }
    
    @Test("Gradual transitions exact threshold passes")
    func gradualTransitions_exactThresholdPasses() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 100),
            SimpleGlucoseReading(timestamp: now, glucose: 140)  // Exactly 40 mg/dL
        ]
        
        #expect(validator.hasGradualTransitions(readings))
    }
    
    @Test("Gradual transitions just over threshold fails")
    func gradualTransitions_justOverThresholdFails() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 100),
            SimpleGlucoseReading(timestamp: now, glucose: 141)  // 41 mg/dL - over threshold
        ]
        
        #expect(!validator.hasGradualTransitions(readings))
    }
    
    // MARK: - Provenance Tests
    
    @Test("Provenance single source passes")
    func provenance_singleSourcePasses() {
        let readings = makeReadings(count: 3, sourceIdentifier: "G6")
        
        #expect(validator.hasSingleProvenance(readings))
    }
    
    @Test("Provenance multiple sources fails")
    func provenance_multipleSourcesFails() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-10)), glucose: 100, sourceIdentifier: "G6"),
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 102, sourceIdentifier: "Libre"),
            SimpleGlucoseReading(timestamp: now, glucose: 104, sourceIdentifier: "G6")
        ]
        
        #expect(!validator.hasSingleProvenance(readings))
    }
    
    @Test("Provenance nil sources pass")
    func provenance_nilSourcesPass() {
        let readings = makeReadings(count: 3, sourceIdentifier: nil)
        
        #expect(validator.hasSingleProvenance(readings))
    }
    
    // MARK: - Calibration Tests
    
    @Test("Calibration no calibrations passes")
    func calibration_noCalibrationsPasses() {
        let readings = makeReadings(count: 3, isCalibration: false)
        
        #expect(!validator.containsCalibrations(readings))
    }
    
    @Test("Calibration with calibration fails")
    func calibration_withCalibrationFails() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-10)), glucose: 100, isCalibration: false),
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 102, isCalibration: true),
            SimpleGlucoseReading(timestamp: now, glucose: 104, isCalibration: false)
        ]
        
        #expect(validator.containsCalibrations(readings))
    }
    
    // MARK: - Full Quality Assessment Tests
    
    @Test("Quality assessment valid data")
    func qualityAssessment_validData() {
        let readings = makeReadings(count: 4)
        
        let quality = validator.assessQuality(readings)
        
        #expect(quality.isValidForMomentum)
        #expect(quality.momentumDisabledReasons.isEmpty)
    }
    
    @Test("Quality assessment insufficient data")
    func qualityAssessment_insufficientData() {
        let readings = makeReadings(count: 2)  // Less than 3 required
        
        let quality = validator.assessQuality(readings)
        
        #expect(!quality.isContinuous)  // Fails continuity due to count
    }
    
    @Test("Quality assessment multiple issues")
    func qualityAssessment_multipleIssues() {
        let now = Date()
        let readings = [
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-15)), glucose: 100, sourceIdentifier: "G6"),
            // Gap at -10 min
            SimpleGlucoseReading(timestamp: now.addingTimeInterval(.minutes(-5)), glucose: 160, sourceIdentifier: "Libre"),  // 60 mg/dL jump, different source
            SimpleGlucoseReading(timestamp: now, glucose: 165, isCalibration: true)
        ]
        
        let quality = validator.assessQuality(readings)
        
        #expect(!quality.isValidForMomentum)
        #expect(!quality.isContinuous)
        #expect(!quality.hasGradualTransitions)
        #expect(!quality.hasSingleProvenance)
        #expect(quality.containsCalibrations)
        
        let reasons = quality.momentumDisabledReasons
        #expect(reasons.contains(.discontinuous))
        #expect(reasons.contains(.largeJumps))
        #expect(reasons.contains(.multipleProvenance))
        #expect(reasons.contains(.calibrationPresent))
    }
    
    // MARK: - Recency Tests
    
    @Test("Recency recent data passes")
    func recency_recentDataPasses() throws {
        let now = Date()
        let recentTimestamp = now.addingTimeInterval(.minutes(-5))
        
        #expect(throws: Never.self) {
            try validator.checkRecency(latestTimestamp: recentTimestamp, at: now)
        }
        #expect(validator.isRecent(latestTimestamp: recentTimestamp, at: now))
    }
    
    @Test("Recency stale data throws")
    func recency_staleDataThrows() {
        let now = Date()
        let staleTimestamp = now.addingTimeInterval(.minutes(-20))
        
        #expect(throws: LoopAlgorithmError.self) {
            try validator.checkRecency(latestTimestamp: staleTimestamp, at: now)
        }
        #expect(!validator.isRecent(latestTimestamp: staleTimestamp, at: now))
    }
    
    @Test("Recency exact threshold passes")
    func recency_exactThresholdPasses() throws {
        let now = Date()
        let exactTimestamp = now.addingTimeInterval(.minutes(-15))
        
        #expect(throws: Never.self) {
            try validator.checkRecency(latestTimestamp: exactTimestamp, at: now)
        }
    }
    
    // MARK: - Dose Gap Filler Tests (GAP-060)
    
    @Test("Gap filler no gaps no fill")
    func gapFiller_noGapsNoFill() {
        let now = Date()
        let doses = [
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.hours(-1)),
                endDate: now,
                volume: 1.0
            )
        ]
        
        let schedule = [
            DoseGapFiller.BasalScheduleEntry(
                startDate: now.addingTimeInterval(.hours(-2)),
                endDate: now.addingTimeInterval(.hours(1)),
                rate: 1.0
            )
        ]
        
        let filled = gapFiller.fillGaps(
            doses: doses,
            basalSchedule: schedule,
            start: now.addingTimeInterval(.hours(-1)),
            end: now
        )
        
        // Should have just the original dose
        #expect(filled.count == 1)
        #expect(!filled[0].isSynthetic)
    }
    
    @Test("Gap filler fills leading gap")
    func gapFiller_fillsLeadingGap() {
        let now = Date()
        let doses = [
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.minutes(-30)),
                endDate: now,
                volume: 0.5
            )
        ]
        
        let schedule = [
            DoseGapFiller.BasalScheduleEntry(
                startDate: now.addingTimeInterval(.hours(-2)),
                endDate: now.addingTimeInterval(.hours(1)),
                rate: 1.0
            )
        ]
        
        let filled = gapFiller.fillGaps(
            doses: doses,
            basalSchedule: schedule,
            start: now.addingTimeInterval(.hours(-1)),
            end: now
        )
        
        // Should have synthetic fill + original dose
        #expect(filled.count == 2)
        #expect(filled[0].isSynthetic)
        #expect(!filled[1].isSynthetic)
    }
    
    @Test("Gap filler fills trailing gap")
    func gapFiller_fillsTrailingGap() {
        let now = Date()
        let doses = [
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.hours(-1)),
                endDate: now.addingTimeInterval(.minutes(-30)),
                volume: 0.5
            )
        ]
        
        let schedule = [
            DoseGapFiller.BasalScheduleEntry(
                startDate: now.addingTimeInterval(.hours(-2)),
                endDate: now.addingTimeInterval(.hours(1)),
                rate: 1.0
            )
        ]
        
        let filled = gapFiller.fillGaps(
            doses: doses,
            basalSchedule: schedule,
            start: now.addingTimeInterval(.hours(-1)),
            end: now
        )
        
        // Should have original dose + synthetic fill
        #expect(filled.count == 2)
        #expect(!filled[0].isSynthetic)
        #expect(filled[1].isSynthetic)
    }
    
    @Test("Gap filler empty doses fills all")
    func gapFiller_emptyDosesFillsAll() {
        let now = Date()
        let doses: [DoseGapFiller.SourceDose] = []
        
        let schedule = [
            DoseGapFiller.BasalScheduleEntry(
                startDate: now.addingTimeInterval(.hours(-2)),
                endDate: now.addingTimeInterval(.hours(1)),
                rate: 1.0
            )
        ]
        
        let filled = gapFiller.fillGaps(
            doses: doses,
            basalSchedule: schedule,
            start: now.addingTimeInterval(.hours(-1)),
            end: now
        )
        
        // Should have synthetic fill for entire range
        #expect(filled.count == 1)
        #expect(filled[0].isSynthetic)
        #expect(abs(filled[0].volume - 1.0) < 0.01)  // 1 U/hr × 1 hr
    }
    
    // MARK: - Gap Detection Tests
    
    @Test("Gap detection no gaps")
    func gapDetection_noGaps() {
        let now = Date()
        let doses = [
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.hours(-1)),
                endDate: now,
                volume: 1.0
            )
        ]
        
        let gaps = gapFiller.detectGaps(
            in: doses,
            start: now.addingTimeInterval(.hours(-1)),
            end: now
        )
        
        #expect(gaps.isEmpty)
    }
    
    @Test("Gap detection detects large gap")
    func gapDetection_detectsLargeGap() {
        let now = Date()
        let doses = [
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.hours(-2)),
                endDate: now.addingTimeInterval(.hours(-1.5)),
                volume: 0.5
            ),
            // 1-hour gap here
            DoseGapFiller.SourceDose(
                startDate: now.addingTimeInterval(.minutes(-30)),
                endDate: now,
                volume: 0.5
            )
        ]
        
        let gaps = gapFiller.detectGaps(
            in: doses,
            start: now.addingTimeInterval(.hours(-2)),
            end: now
        )
        
        #expect(gaps.count == 1)
        #expect(abs(gaps[0].start.timeIntervalSince(now.addingTimeInterval(.hours(-1.5)))) < 1)
    }
    
    // MARK: - Graceful Degradation Tests (GAP-061)
    
    @Test("Degradation full when all good")
    func degradation_fullWhenAllGood() {
        let level = degradation.degradationLevel(
            glucoseQuality: .valid,
            hasGlucose: true,
            isGlucoseRecent: true,
            hasDoseGaps: false
        )
        
        #expect(level == .full)
    }
    
    @Test("Degradation none when no glucose")
    func degradation_noneWhenNoGlucose() {
        let level = degradation.degradationLevel(
            glucoseQuality: .valid,
            hasGlucose: false,
            isGlucoseRecent: true,
            hasDoseGaps: false
        )
        
        #expect(level == .none)
    }
    
    @Test("Degradation none when glucose stale")
    func degradation_noneWhenGlucoseStale() {
        let level = degradation.degradationLevel(
            glucoseQuality: .valid,
            hasGlucose: true,
            isGlucoseRecent: false,
            hasDoseGaps: false
        )
        
        #expect(level == .none)
    }
    
    @Test("Degradation no momentum when quality bad")
    func degradation_noMomentumWhenQualityBad() {
        let level = degradation.degradationLevel(
            glucoseQuality: .invalid,
            hasGlucose: true,
            isGlucoseRecent: true,
            hasDoseGaps: false
        )
        
        #expect(level == .noMomentum)
    }
    
    @Test("Degradation conservative when dose gaps")
    func degradation_conservativeWhenDoseGaps() {
        let level = degradation.degradationLevel(
            glucoseQuality: .valid,
            hasGlucose: true,
            isGlucoseRecent: true,
            hasDoseGaps: true
        )
        
        #expect(level == .conservative)
    }
    
    @Test("Degradation minimal when multiple issues")
    func degradation_minimalWhenMultipleIssues() {
        let level = degradation.degradationLevel(
            glucoseQuality: .invalid,
            hasGlucose: true,
            isGlucoseRecent: true,
            hasDoseGaps: true
        )
        
        #expect(level == .minimal)
    }
    
    // MARK: - Integration Test
    
    @Test("Integration full validation")
    func integration_fullValidation() throws {
        let now = Date()
        // Good data
        let readings = makeReadings(count: 4)
        
        // Check quality
        let quality = validator.assessQuality(readings)
        #expect(quality.isValidForMomentum)
        
        // Check recency
        let latestTimestamp = readings.last!.timestamp
        #expect(throws: Never.self) {
            try validator.checkRecency(latestTimestamp: latestTimestamp, at: now)
        }
        
        // Determine degradation level
        let level = degradation.degradationLevel(
            glucoseQuality: quality,
            hasGlucose: true,
            isGlucoseRecent: true,
            hasDoseGaps: false
        )
        #expect(level == .full)
    }
}
