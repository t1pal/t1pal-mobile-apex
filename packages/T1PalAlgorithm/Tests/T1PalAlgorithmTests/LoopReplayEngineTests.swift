// LoopReplayEngineTests.swift
// T1PalAlgorithmTests
//
// ALG-ARCH-012: Verify zero-divergence with new architecture

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Loop Replay Engine Tests")
struct LoopReplayEngineTests {
    
    // MARK: - DeviceStatusSequence Tests
    
    @Test("DeviceStatusSequence creation works correctly")
    func deviceStatusSequenceCreation() {
        // Create minimal devicestatus records
        let now = Date()
        let records = createTestDeviceStatusRecords(count: 3, startTime: now.addingTimeInterval(-600))
        
        let settings = createTestSettings()
        let sequence = DeviceStatusSequence(records: records, defaultSettings: settings)
        
        #expect(sequence.cycles.count == 3)
        #expect(!sequence.hasGaps)
    }
    
    @Test("DeviceStatusSequence detects gaps")
    func deviceStatusSequenceDetectsGaps() {
        let now = Date()
        
        // Create records with a 15-minute gap
        let record1 = createDeviceStatusRecord(at: now.addingTimeInterval(-900), index: 0)  // -15 min
        let record2 = createDeviceStatusRecord(at: now.addingTimeInterval(-300), index: 1)  // -5 min (10-min gap)
        let record3 = createDeviceStatusRecord(at: now, index: 2)  // now
        
        let settings = createTestSettings()
        let sequence = DeviceStatusSequence(records: [record1, record2, record3], defaultSettings: settings)
        
        #expect(sequence.cycles.count == 3)
        #expect(sequence.hasGaps)
        #expect(sequence.gaps.count == 1)
        #expect(sequence.gaps[0].duration > 360) // > 6 min
    }
    
    // MARK: - InputReconstructor Tests
    
    @Test("InputReconstructor builds dose history")
    func inputReconstructorBuildsDoseHistory() {
        let now = Date()
        
        // Create test treatments
        let treatments = [
            TreatmentRecord(
                identifier: "t1",
                eventType: "Temp Basal",
                timestamp: now.addingTimeInterval(-3600),  // 1 hour ago
                createdAt: now.addingTimeInterval(-3600),
                rate: 0.5,
                duration: 30
            ),
            TreatmentRecord(
                identifier: "t2",
                eventType: "Bolus",
                timestamp: now.addingTimeInterval(-1800),  // 30 min ago
                createdAt: now.addingTimeInterval(-1800),
                insulin: 2.0
            )
        ]
        
        let glucose = [
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 120),
            GlucoseRecord(date: now, value: 125)
        ]
        
        let profile = createTestProfile()
        
        let reconstructor = InputReconstructor(
            treatments: treatments,
            glucose: glucose,
            profile: profile
        )
        
        // Create a cycle and build input
        let cycle = createTestCycle(at: now, index: 0)
        let iobInput = reconstructor.buildIOBInput(for: cycle)
        
        #expect(!iobInput.doses.isEmpty)
    }
    
    /// ALG-REFACTOR-009: Verify InputReconstructor always uses correct includingPendingInsulin values
    @Test("InputReconstructor uses correct pending insulin flag")
    func inputReconstructorUsesCorrectPendingInsulinFlag() {
        let now = Date()
        
        // Create minimal test data
        let treatments = [
            TreatmentRecord(
                identifier: "temp1",
                eventType: "Temp Basal",
                timestamp: now.addingTimeInterval(-1800),
                createdAt: now.addingTimeInterval(-1800),
                rate: 0.8,
                duration: 60
            )
        ]
        
        let glucose = [
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 110),
            GlucoseRecord(date: now, value: 115)
        ]
        
        let profile = createTestProfile()
        
        let reconstructor = InputReconstructor(
            treatments: treatments,
            glucose: glucose,
            profile: profile
        )
        
        let cycle = createTestCycle(at: now, index: 0)
        
        // IOB input MUST have includingPendingInsulin = false (delivered insulin only)
        let iobInput = reconstructor.buildIOBInput(for: cycle)
        #expect(!iobInput.includingPendingInsulin,
            "IOB calculation must use includingPendingInsulin=false to match Loop's reported IOB")
        
        // Prediction input MUST have includingPendingInsulin = true (include future delivery)
        let predictionInput = reconstructor.buildPredictionInput(for: cycle)
        #expect(predictionInput.includingPendingInsulin,
            "Prediction calculation must use includingPendingInsulin=true to include scheduled delivery")
    }
    
    // MARK: - Comparator Tests
    
    @Test("Comparator IOB comparison works")
    func comparatorIOBComparison() {
        let comparison = Comparator.compareIOB(ours: 1.5, loops: 1.505)
        
        #expect(abs(comparison.delta - (-0.005)) < 0.001)
        #expect(comparison.withinTolerance) // Within ±0.01 U tolerance
    }
    
    @Test("Comparator prediction comparison works")
    func comparatorPredictionComparison() {
        let ourPrediction: [Double] = [120.0, 125.0, 130.0, 135.0, 140.0]
        let loopPrediction: [Int] = [120, 126, 132, 137, 142]
        
        let comparison = Comparator.comparePrediction(
            ours: ourPrediction,
            loops: loopPrediction
        )
        
        #expect(abs(comparison.mae - 1.4) < 0.1) // Average delta
        #expect(abs(comparison.eventualDelta - (-2.0)) < 0.1)
        #expect(comparison.significance == Significance.none) // Within tolerance
    }
    
    /// ALG-REFACTOR-004: Verify ComparisonConfig provides configurable tolerances
    @Test("ComparisonConfig affects tolerances")
    func comparisonConfigAffectsTolerances() {
        // Default config: IOB tolerance = 0.01 U
        let defaultResult = Comparator.compareIOB(ours: 1.5, loops: 1.52, config: .default)
        #expect(!defaultResult.withinTolerance, "0.02 U delta should exceed default 0.01 tolerance")
        
        // Relaxed config: IOB tolerance = 0.1 U
        let relaxedResult = Comparator.compareIOB(ours: 1.5, loops: 1.52, config: .relaxed)
        #expect(relaxedResult.withinTolerance, "0.02 U delta should be within relaxed 0.1 tolerance")
        
        // Strict config: IOB tolerance = 0.001 U
        let strictResult = Comparator.compareIOB(ours: 1.5, loops: 1.505, config: .strict)
        #expect(!strictResult.withinTolerance, "0.005 U delta should exceed strict 0.001 tolerance")
    }
    
    @Test("ComparisonConfig defaults are correct")
    func comparisonConfigDefaults() {
        let config = ComparisonConfig.default
        
        #expect(config.iobTolerance == 0.01)
        #expect(config.maeTolerance == 2.0)
        #expect(config.tempBasalTolerance == 0.01)
        #expect(config.gapTolerance == 360)
    }
    
    // MARK: - LoopReplayEngine Tests
    
    @Test("LoopReplayEngine replay works")
    func loopReplayEngineReplay() {
        let now = Date()
        
        // Create minimal test data
        let records = createTestDeviceStatusRecords(count: 2, startTime: now.addingTimeInterval(-300))
        let treatments: [TreatmentRecord] = []
        let glucose = [
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 120),
            GlucoseRecord(date: now, value: 125)
        ]
        let profile = createTestProfile()
        let settings = createTestSettings()
        
        let engine = LoopReplayEngine(
            deviceStatuses: records,
            treatments: treatments,
            glucose: glucose,
            profile: profile,
            settings: settings
        )
        
        #expect(engine.sequence.cycles.count == 2)
        
        let results = engine.replay()
        #expect(results.count == 2)
    }
    
    @Test("LoopReplayEngine statistics work")
    func loopReplayEngineStatistics() {
        let now = Date()
        
        let records = createTestDeviceStatusRecords(count: 3, startTime: now.addingTimeInterval(-600))
        let treatments: [TreatmentRecord] = []
        let glucose = createTestGlucoseRecords(count: 5, startTime: now.addingTimeInterval(-1200))
        let profile = createTestProfile()
        let settings = createTestSettings()
        
        let engine = LoopReplayEngine(
            deviceStatuses: records,
            treatments: treatments,
            glucose: glucose,
            profile: profile,
            settings: settings
        )
        
        let (results, statistics) = engine.replayWithStatistics()
        
        #expect(results.count == 3)
        #expect(statistics.cycleCount == 3)
        // Statistics should have valid values
        #expect(!statistics.iobMeanDelta.isNaN)
        #expect(!statistics.predictionMeanMAE.isNaN)
    }
    
    // MARK: - Test Helpers
    
    private func createTestSettings() -> TherapySettingsSnapshot {
        TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)]
        )
    }
    
    private func createTestProfile() -> NightscoutProfileData {
        NightscoutProfileData(
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            isfSchedule: [ScheduleValue(startTime: 0, value: 50)],
            crSchedule: [ScheduleValue(startTime: 0, value: 10)],
            targetLow: 100,
            targetHigh: 110,
            dia: 6 * 3600
        )
    }
    
    private func createTestDeviceStatusRecords(count: Int, startTime: Date) -> [DeviceStatusRecord] {
        (0..<count).map { index in
            createDeviceStatusRecord(
                at: startTime.addingTimeInterval(Double(index) * 300),
                index: index
            )
        }
    }
    
    private func createDeviceStatusRecord(at time: Date, index: Int) -> DeviceStatusRecord {
        let iobData = IOBData(iob: 1.5 + Double(index) * 0.1, timestamp: time)
        let predictedData = PredictedData(
            startDate: time,
            values: (0..<37).map { 120 + $0 }  // 37 points, 3 hours
        )
        let loopStatus = LoopStatusData(
            iob: iobData,
            cob: COBData(cob: 0),
            predicted: predictedData,
            automaticDoseRecommendation: nil,
            enacted: nil
        )
        
        return DeviceStatusRecord(
            identifier: "ds-\(index)",
            createdAt: time,
            loop: loopStatus,
            loopSettings: nil
        )
    }
    
    private func createTestCycle(at time: Date, index: Int) -> LoopCycleState {
        LoopCycleState(
            deviceStatusID: "ds-\(index)",
            cycleIndex: index,
            uploadedAt: time,
            cgmReadingTime: time,
            iobCalculationTime: time,
            loopReportedIOB: 1.5,
            loopReportedCOB: 0,
            loopPrediction: (0..<37).map { 120 + $0 },
            loopRecommendation: nil,
            loopEnacted: nil,
            previousEnacted: nil,
            hasGapFromPrevious: false,
            settings: createTestSettings()
        )
    }
    
    private func createTestGlucoseRecords(count: Int, startTime: Date) -> [GlucoseRecord] {
        (0..<count).map { index in
            GlucoseRecord(
                date: startTime.addingTimeInterval(Double(index) * 300),
                value: 120 + Double(index) * 2
            )
        }
    }
    
    // MARK: - ALG-IOB-SUSPEND: Negative IOB Test
    
    @Test("Calculate IOB with suspended basal")
    func calculateIOBWithSuspendedBasal() {
        // Test that suspended basal (0 U/hr) produces negative IOB
        let now = Date()
        
        // Create settings with 1.8 U/hr scheduled basal
        let settings = TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.8)],
            dia: 6 * 3600
        )
        
        // Create a suspended temp basal treatment (0 U/hr)
        // Starting 30 min ago, lasting until 5 min ago
        let treatments = [
            TreatmentRecord(
                identifier: "suspend1",
                eventType: "Temp Basal",
                timestamp: now.addingTimeInterval(-30 * 60),
                createdAt: now.addingTimeInterval(-30 * 60),
                rate: 0.0,  // SUSPENDED
                duration: 25  // 25 minutes
            )
        ]
        
        // Create the runner
        let runner = DefaultAlgorithmRunner()
        
        // Build IOBInput manually
        let doses = [ReplayInsulinDose(
            type: .tempBasal,
            startDate: now.addingTimeInterval(-30 * 60),
            endDate: now.addingTimeInterval(-5 * 60),
            rate: 0.0,
            units: nil,
            createdAt: now.addingTimeInterval(-30 * 60)
        )]
        
        let input = IOBInput(
            doses: doses,
            calculationTime: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.8)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            includingPendingInsulin: false
        )
        
        let iob = runner.calculateIOB(input)
        
        // With 25 min at 0 U/hr vs scheduled 1.8 U/hr:
        // Net = -1.8 * (25/60) = -0.75 U (before decay)
        // Actual should be negative due to "missing" insulin
        print("Calculated IOB: \(iob)")
        
        // The IOB should be negative (or at most close to zero)
        #expect(iob < 0.1, "IOB should be negative or near zero for suspended basal")
    }
    
    // MARK: - ALG-PENDING-001: Pending Insulin Tests
    
    @Test("Calculate IOB with includingPendingInsulin false trims future doses")
    func calculateIOB_includingPendingInsulinFalse_trimsFutureDoses() {
        // ALG-PENDING-001: When includingPendingInsulin: false, ongoing temp basals
        // should be trimmed to calculationTime
        let now = Date()
        
        // Create a temp basal that started 10 min ago and extends 20 min into the future
        let doses = [ReplayInsulinDose(
            type: .tempBasal,
            startDate: now.addingTimeInterval(-10 * 60),  // Started 10 min ago
            endDate: now.addingTimeInterval(20 * 60),     // Ends 20 min from now (30 min total)
            rate: 2.0,  // 2 U/hr
            units: nil,
            createdAt: now.addingTimeInterval(-10 * 60)
        )]
        
        let runner = DefaultAlgorithmRunner()
        
        // With includingPendingInsulin: FALSE - should only count past 10 min
        let inputWithoutPending = IOBInput(
            doses: doses,
            calculationTime: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],  // 1 U/hr scheduled
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            includingPendingInsulin: false
        )
        
        // With includingPendingInsulin: TRUE - should count full 30 min
        let inputWithPending = IOBInput(
            doses: doses,
            calculationTime: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            includingPendingInsulin: true
        )
        
        let iobWithoutPending = runner.calculateIOB(inputWithoutPending)
        let iobWithPending = runner.calculateIOB(inputWithPending)
        
        print("IOB without pending (trimmed to 10 min): \(iobWithoutPending)")
        print("IOB with pending (full 30 min): \(iobWithPending)")
        
        // IOB with pending should be HIGHER because it includes future delivery
        // Net rate = 2.0 - 1.0 = 1.0 U/hr above scheduled
        // Without pending: 10 min = 0.167 U net
        // With pending: 30 min = 0.5 U net (before IOB decay)
        #expect(iobWithPending > iobWithoutPending,
            "IOB with pending insulin should be higher than without")
        
        // The difference should be approximately the future delivery effect
        // (This validates that trimming is working)
        let difference = iobWithPending - iobWithoutPending
        #expect(difference > 0.1, "Pending insulin should add significant IOB")
    }
    
    @Test("Calculate IOB with future dose excluded when not pending")
    func calculateIOB_futureDoseExcludedWhenNotPending() {
        // ALG-PENDING-001: The effect of ONGOING temp basals that extend into the future
        // should be different based on includingPendingInsulin flag
        // 
        // Note: A dose that starts in the future has no current effect regardless of flag.
        // The flag affects whether we include the SCHEDULED future delivery of ongoing temps.
        let now = Date()
        
        // Create an ongoing temp that started 5 min ago and extends 25 min into future
        let ongoingTemp = ReplayInsulinDose(
            type: .tempBasal,
            startDate: now.addingTimeInterval(-5 * 60),   // Started 5 min ago
            endDate: now.addingTimeInterval(25 * 60),     // Ends 25 min from now (30 min total)
            rate: 3.0,  // 3 U/hr (significantly above baseline)
            units: nil,
            createdAt: now.addingTimeInterval(-5 * 60)
        )
        
        let runner = DefaultAlgorithmRunner()
        
        // Without pending: only count past 5 min of delivery
        let inputWithoutPending = IOBInput(
            doses: [ongoingTemp],
            calculationTime: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            includingPendingInsulin: false
        )
        
        // With pending: count full 30 min of scheduled delivery
        let inputWithPending = IOBInput(
            doses: [ongoingTemp],
            calculationTime: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            includingPendingInsulin: true
        )
        
        let iobWithoutPending = runner.calculateIOB(inputWithoutPending)
        let iobWithPending = runner.calculateIOB(inputWithPending)
        
        print("IOB without pending (trimmed to 5 min past): \(iobWithoutPending)")
        print("IOB with pending (full 30 min scheduled): \(iobWithPending)")
        
        // Net rate = 3.0 - 1.0 = 2.0 U/hr above scheduled
        // Without pending: 5 min past = 2.0 * (5/60) = 0.167 U (before decay, at 100%)
        // With pending: 30 min = 2.0 * (30/60) = 1.0 U (but future portion hasn't decayed yet)
        
        // The IOB with pending should be HIGHER due to future scheduled delivery
        #expect(iobWithPending > iobWithoutPending,
            "IOB with pending insulin should include future scheduled delivery")
        
        // Verify significant difference (at least 0.1 U)
        let difference = iobWithPending - iobWithoutPending
        #expect(difference > 0.1, 
            "Pending insulin should add significant IOB for ongoing temps")
    }

    @Test("BuildDoseHistory infers duration")
    func buildDoseHistoryInfersDuration() {
        // Test that buildDoseHistory correctly infers duration when nil
        let now = Date()
        
        // Create treatments WITHOUT explicit duration
        let treatments = [
            TreatmentRecord(
                identifier: "t1",
                eventType: "Temp Basal",
                timestamp: now.addingTimeInterval(-30 * 60),
                createdAt: now.addingTimeInterval(-30 * 60),
                rate: 0.0,
                duration: nil  // NO DURATION
            ),
            TreatmentRecord(
                identifier: "t2",
                eventType: "Temp Basal",
                timestamp: now.addingTimeInterval(-25 * 60),  // 5 min after t1
                createdAt: now.addingTimeInterval(-25 * 60),
                rate: 1.5,
                duration: nil
            )
        ]
        
        let profile = createTestProfile()
        let reconstructor = InputReconstructor(
            treatments: treatments,
            glucose: [],
            profile: profile
        )
        
        // Create a cycle that sees both treatments
        let cycle = LoopCycleState(
            deviceStatusID: "test",
            cycleIndex: 0,
            uploadedAt: now,
            cgmReadingTime: now,
            iobCalculationTime: now,
            loopReportedIOB: 0,
            loopReportedCOB: 0,
            loopPrediction: [],
            loopRecommendation: nil,
            loopEnacted: nil,
            previousEnacted: nil,
            hasGapFromPrevious: false,
            settings: createTestSettings()
        )
        
        let doses = reconstructor.buildDoseHistory(for: cycle)
        
        // Should have 2 temp basal doses
        #expect(doses.filter { $0.type == .tempBasal }.count == 2)
        
        // First dose should have inferred duration (5 min to next temp basal)
        let firstDose = doses.first { $0.type == .tempBasal && $0.rate == 0.0 }
        #expect(firstDose != nil)
        
        let expectedEndDate = now.addingTimeInterval(-25 * 60)  // When next temp starts
        #expect(abs(firstDose!.endDate.timeIntervalSince1970 - expectedEndDate.timeIntervalSince1970) < 1)
        
        print("First dose duration: \(firstDose!.endDate.timeIntervalSince(firstDose!.startDate) / 60) min")
    }
    
    // MARK: - ALG-ZERO-DIV-009: Deduplication Tests
    
    @Test("DeviceStatusSequence deduplicates records")
    func deviceStatusSequenceDeduplicates() {
        let now = Date()
        
        // Create records with duplicates (same createdAt)
        let record1 = createDeviceStatusRecord(at: now.addingTimeInterval(-600), index: 0)
        let record2 = createDeviceStatusRecord(at: now.addingTimeInterval(-300), index: 1)
        let record3 = createDeviceStatusRecord(at: now.addingTimeInterval(-300), index: 2)  // Duplicate of record2
        let record4 = createDeviceStatusRecord(at: now, index: 3)
        
        let settings = createTestSettings()
        let sequence = DeviceStatusSequence(
            records: [record1, record2, record3, record4],
            defaultSettings: settings
        )
        
        // Should have 3 cycles, not 4 (duplicate removed)
        #expect(sequence.cycles.count == 3, "Duplicate devicestatus should be removed")
    }
    
    // MARK: - ALG-ZERO-DIV-011: Dosing Recommendation Test
    
    @Test("Calculate recommendation produces temp basal")
    func calculateRecommendationProducesTempBasal() {
        // Test that calculateRecommendation produces a temp basal recommendation
        let now = Date()
        
        // Create settings - high glucose should trigger high temp basal
        let settings = TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600
        )
        
        // Create prediction input with high glucose (should recommend high temp basal)
        let glucoseRecords = [
            GlucoseRecord(date: now.addingTimeInterval(-600), value: 160),
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 165),
            GlucoseRecord(date: now, value: 170)
        ]
        
        let predictionInput = PredictionInput(
            doses: [],  // No recent insulin
            glucose: glucoseRecords,
            carbs: [],
            predictionStart: now,
            basalSchedule: settings.basalSchedule,
            insulinModel: settings.insulinModel,
            dia: settings.dia,
            isf: settings.insulinSensitivity,
            carbRatio: settings.carbRatio,
            targetRange: Double(settings.targetLow)...Double(settings.targetHigh),
            suspendThreshold: Double(settings.suspendThreshold),
            maxBasalRate: settings.maxBasalRate,
            includingPendingInsulin: true
        )
        
        let runner = DefaultAlgorithmRunner()
        let recommendation = runner.calculateRecommendation(predictionInput)
        
        // Should produce a temp basal recommendation
        #expect(recommendation != nil, "Should produce a recommendation for high glucose")
        
        if let rec = recommendation {
            // High glucose should trigger above-neutral basal
            if let rate = rec.tempBasalRate {
                #expect(rate > 1.0, "High glucose should trigger high temp basal (rate > scheduled)")
                #expect(rate <= settings.maxBasalRate, "Rate should not exceed max basal")
            }
            // Should have 30-minute duration
            if let duration = rec.tempBasalDuration {
                #expect(abs(duration - 30) < 0.1, "Temp basal should be 30 minutes")
            }
        }
    }
    
    @Test("Calculate recommendation with low glucose suspends")
    func calculateRecommendationWithLowGlucoseSuspends() {
        // Test that low glucose triggers suspension
        let now = Date()
        
        let settings = TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600
        )
        
        // Create prediction input with low glucose
        let glucoseRecords = [
            GlucoseRecord(date: now.addingTimeInterval(-600), value: 85),
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 80),
            GlucoseRecord(date: now, value: 75)
        ]
        
        let predictionInput = PredictionInput(
            doses: [],
            glucose: glucoseRecords,
            carbs: [],
            predictionStart: now,
            basalSchedule: settings.basalSchedule,
            insulinModel: settings.insulinModel,
            dia: settings.dia,
            isf: settings.insulinSensitivity,
            carbRatio: settings.carbRatio,
            targetRange: Double(settings.targetLow)...Double(settings.targetHigh),
            suspendThreshold: Double(settings.suspendThreshold),
            maxBasalRate: settings.maxBasalRate,
            includingPendingInsulin: true
        )
        
        let runner = DefaultAlgorithmRunner()
        let recommendation = runner.calculateRecommendation(predictionInput)
        
        // Should recommend zero temp basal (suspend)
        #expect(recommendation != nil, "Should produce a recommendation for low glucose")
        
        if let rec = recommendation {
            // Low glucose should trigger zero basal
            if let rate = rec.tempBasalRate {
                #expect(abs(rate) < 0.01, "Low glucose should trigger suspend (0 rate)")
            }
        }
    }
    
    // MARK: - ALG-ZERO-DIV-012: Enacted Comparison Test
    
    @Test("Calculate enacted with ifNecessary filter")
    func calculateEnactedWithIfNecessaryFilter() {
        // Test that calculateEnacted applies ifNecessary filter correctly
        let now = Date()
        
        let runner = DefaultAlgorithmRunner()
        
        // Case 1: New recommendation with no previous enacted → should enact
        let recommendation = ReplayDoseRecommendation(
            tempBasalRate: 2.5,
            tempBasalDuration: 30,
            bolusVolume: 0
        )
        
        let enacted1 = runner.calculateEnacted(
            recommendation: recommendation,
            previousEnacted: nil,
            scheduledBasalRate: 1.0,
            at: now
        )
        
        #expect(enacted1 != nil, "New recommendation should produce enacted dose")
        if let enacted = enacted1 {
            #expect(abs(enacted.rate - 2.5) < 0.01, "Enacted rate should match recommendation")
            #expect(abs(enacted.duration - 30) < 0.1, "Enacted duration should be 30 min")
        }
    }
    
    @Test("Calculate enacted continues running temp")
    func calculateEnactedContinuesRunningTemp() {
        // Test that ifNecessary filter returns nil when temp is already running
        let now = Date()
        
        let runner = DefaultAlgorithmRunner()
        
        // Previous temp basal started recently, same rate
        let previousEnacted = EnactedDose(
            rate: 2.5,
            duration: 30,
            timestamp: now.addingTimeInterval(-5 * 60),  // Started 5 min ago
            received: true
        )
        
        // Same rate recommendation
        let recommendation = ReplayDoseRecommendation(
            tempBasalRate: 2.5,
            tempBasalDuration: 30,
            bolusVolume: 0
        )
        
        let enacted = runner.calculateEnacted(
            recommendation: recommendation,
            previousEnacted: previousEnacted,
            scheduledBasalRate: 1.0,
            at: now
        )
        
        // Should return nil because temp is already running with sufficient time
        #expect(enacted == nil, "Same rate with sufficient time remaining should not re-enact")
    }
    
    @Test("Calculate enacted changes rate")
    func calculateEnactedChangesRate() {
        // Test that different rate produces new enacted
        let now = Date()
        
        let runner = DefaultAlgorithmRunner()
        
        // Previous temp basal at different rate
        let previousEnacted = EnactedDose(
            rate: 1.5,
            duration: 30,
            timestamp: now.addingTimeInterval(-5 * 60),
            received: true
        )
        
        // Different rate recommendation
        let recommendation = ReplayDoseRecommendation(
            tempBasalRate: 3.0,
            tempBasalDuration: 30,
            bolusVolume: 0
        )
        
        let enacted = runner.calculateEnacted(
            recommendation: recommendation,
            previousEnacted: previousEnacted,
            scheduledBasalRate: 1.0,
            at: now
        )
        
        // Should produce new enacted because rate is different
        #expect(enacted != nil, "Different rate should produce new enacted dose")
        if let result = enacted {
            #expect(abs(result.rate - 3.0) < 0.01, "Enacted rate should match new recommendation")
        }
    }
    
    // MARK: - Retrospective Correction Tests (ALG-ZERO-DIV-010 RC)
    
    @Test("Calculate prediction with positive RC")
    func calculatePredictionWithRC() {
        // ALG-ZERO-DIV-010 RC: Verify RC is calculated and applied to predictions
        let runner = DefaultAlgorithmRunner()
        let now = Date()
        
        // Create glucose history showing glucose higher than expected (positive discrepancy)
        // This should cause RC to add a positive correction to predictions
        let glucoseHistory = [
            GlucoseRecord(date: now.addingTimeInterval(-1800), value: 150),  // 30 min ago
            GlucoseRecord(date: now.addingTimeInterval(-1500), value: 155),  // 25 min ago (+5)
            GlucoseRecord(date: now.addingTimeInterval(-1200), value: 160),  // 20 min ago (+5)
            GlucoseRecord(date: now.addingTimeInterval(-900), value: 167),   // 15 min ago (+7)
            GlucoseRecord(date: now.addingTimeInterval(-600), value: 175),   // 10 min ago (+8)
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 180),   // 5 min ago (+5)
            GlucoseRecord(date: now, value: 185),                            // now (+5)
        ]
        
        // No insulin doses - so all glucose rise is "unexplained" (positive ICE)
        let doses: [ReplayInsulinDose] = []
        
        // No carbs either - so discrepancy = ICE (positive = glucose rising more than expected)
        let carbs: [CarbRecord] = []
        
        let input = PredictionInput(
            doses: doses,
            glucose: glucoseHistory,
            carbs: carbs,
            predictionStart: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            isf: 50,
            carbRatio: 10,
            targetRange: 100...110,
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            includingPendingInsulin: true
        )
        
        let prediction = runner.calculatePrediction(input)
        
        // With rising glucose trend (positive discrepancy), RC should add positive correction
        // Predictions should be higher than just current glucose + momentum
        #expect(!prediction.isEmpty, "Should produce predictions")
        
        // First prediction should be close to current glucose
        if !prediction.isEmpty {
            #expect(abs(prediction[0] - 185) < 10, "First prediction near current glucose")
        }
        
        // Check prediction shape - with positive RC and no insulin, should trend up or flat
        if prediction.count > 12 {
            // At 1 hour, with positive RC the prediction should not drop below starting
            #expect(prediction[12] >= 170, "With positive RC, 1h prediction should stay elevated")
        }
    }
    
    @Test("Calculate prediction with negative RC")
    func calculatePredictionWithNegativeRC() {
        // ALG-ZERO-DIV-010 RC: Verify negative RC (glucose lower than expected)
        let runner = DefaultAlgorithmRunner()
        let now = Date()
        
        // Glucose falling faster than expected (negative discrepancy scenario)
        // With no insulin to explain the drop, this shows up as negative ICE
        let glucoseHistory = [
            GlucoseRecord(date: now.addingTimeInterval(-1800), value: 200),  // 30 min ago
            GlucoseRecord(date: now.addingTimeInterval(-1500), value: 190),  // 25 min ago (-10)
            GlucoseRecord(date: now.addingTimeInterval(-1200), value: 180),  // 20 min ago (-10)
            GlucoseRecord(date: now.addingTimeInterval(-900), value: 170),   // 15 min ago (-10)
            GlucoseRecord(date: now.addingTimeInterval(-600), value: 160),   // 10 min ago (-10)
            GlucoseRecord(date: now.addingTimeInterval(-300), value: 150),   // 5 min ago (-10)
            GlucoseRecord(date: now, value: 140),                            // now (-10)
        ]
        
        // No insulin - so the drop is "unexplained" (negative ICE = exercise, etc.)
        let doses: [ReplayInsulinDose] = []
        let carbs: [CarbRecord] = []
        
        let input = PredictionInput(
            doses: doses,
            glucose: glucoseHistory,
            carbs: carbs,
            predictionStart: now,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.0)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600,
            isf: 50,
            carbRatio: 10,
            targetRange: 100...110,
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            includingPendingInsulin: true
        )
        
        let prediction = runner.calculatePrediction(input)
        
        // With falling glucose (negative discrepancy), RC should add negative correction
        // Predictions should continue to trend down
        #expect(!prediction.isEmpty, "Should produce predictions")
        
        // With negative RC and momentum, predictions should trend lower
        if prediction.count > 12 {
            // At 1 hour, with negative RC and falling momentum, should be well below starting
            #expect(prediction[12] < 140, "With negative RC, 1h prediction should be lower")
        }
    }
}
