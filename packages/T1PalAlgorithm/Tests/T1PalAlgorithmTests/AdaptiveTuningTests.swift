// AdaptiveTuningTests.swift
// T1PalAlgorithmTests
//
// Tests for adaptive tuning components
// Trace: GLUCOS-IMPL-001

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Time Block Calculator")
struct TimeBlockCalculatorTests {
    @Test("Time block for midnight")
    func timeBlockForMidnight() {
        let calendar = Calendar.current
        let midnight = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 0, minute: 0)
        )!
        
        #expect(TimeBlockCalculator.timeBlock(for: midnight) == 0)
    }
    
    @Test("Time block for 3AM")
    func timeBlockFor3AM() {
        let calendar = Calendar.current
        let threeAM = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 3, minute: 59)
        )!
        
        #expect(TimeBlockCalculator.timeBlock(for: threeAM) == 0)
    }
    
    @Test("Time block for 4AM")
    func timeBlockFor4AM() {
        let calendar = Calendar.current
        let fourAM = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 4, minute: 0)
        )!
        
        #expect(TimeBlockCalculator.timeBlock(for: fourAM) == 1)
    }
    
    @Test("Time block for noon")
    func timeBlockForNoon() {
        let calendar = Calendar.current
        let noon = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 30)
        )!
        
        #expect(TimeBlockCalculator.timeBlock(for: noon) == 3)
    }
    
    @Test("Time block for 11PM")
    func timeBlockFor11PM() {
        let calendar = Calendar.current
        let elevenPM = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 23, minute: 59)
        )!
        
        #expect(TimeBlockCalculator.timeBlock(for: elevenPM) == 5)
    }
    
    @Test("Block start calculation")
    func blockStartCalculation() {
        let calendar = Calendar.current
        let midBlock = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 10, minute: 45)
        )!
        
        let blockStart = TimeBlockCalculator.blockStart(for: midBlock)
        let hour = calendar.component(.hour, from: blockStart)
        let minute = calendar.component(.minute, from: blockStart)
        
        #expect(hour == 8)
        #expect(minute == 0)
    }
    
    @Test("Block duration")
    func blockDuration() {
        #expect(TimeBlockCalculator.blockDuration == 4 * 60 * 60)
    }
    
    @Test("Block names")
    func blockNames() {
        #expect(TimeBlockCalculator.blockNames.count == 6)
        #expect(TimeBlockCalculator.blockNames[0] == "Night")
        #expect(TimeBlockCalculator.blockNames[1] == "Dawn")
    }
    
    @Test("Block boundaries")
    func blockBoundaries() {
        let calendar = Calendar.current
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 0)
        )!
        
        let boundaries = TimeBlockCalculator.blockBoundaries(for: date)
        #expect(boundaries.count == 6)
        
        for (_, boundary) in boundaries.enumerated() {
            #expect(boundary.end.timeIntervalSince(boundary.start) == TimeBlockCalculator.blockDuration)
        }
    }
}

@Suite("ISF Learner")
struct ISFLearnerTests {
    @Test("Initial state has no learned data")
    func initialStateHasNoLearnedData() async {
        let learner = ISFLearner()
        let hasData = await learner.hasLearnedData
        #expect(!hasData)
    }
    
    @Test("Pass through with no data")
    func passThroughWithNoData() async {
        let learner = ISFLearner()
        let result = await learner.adjustedISF(baseISF: 50.0, at: Date())
        
        #expect(result.baseValue == 50.0)
        #expect(result.adjustedValue == 50.0)
        #expect(result.source == .profile)
    }
    
    @Test("Recording outcomes")
    func recordingOutcomes() async {
        let learner = ISFLearner(minOutcomesPerBlock: 3)
        
        // Use date within the 7-day learning window
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let baseDate = calendar.date(byAdding: .day, value: -1, to: today)!
            .addingTimeInterval(9 * 60 * 60)  // 09:00 yesterday
        
        // Record 3 outcomes in block 2 (08:00-12:00)
        for i in 0..<3 {
            let outcome = TuningOutcome(
                timestamp: baseDate.addingTimeInterval(Double(i) * 300),
                timeBlock: 2,
                predictedGlucose: 120,
                actualGlucose: 130,  // Consistently 10 higher than predicted
                insulinDelivered: 0.5,
                carbsConsumed: 0
            )
            await learner.recordOutcome(outcome)
        }
        
        let count = await learner.outcomeCount
        #expect(count == 3)
        
        let hasData = await learner.hasLearnedData
        #expect(hasData)
    }
    
    @Test("Learning adjusts ISF")
    func learningAdjustsISF() async {
        let learner = ISFLearner(minOutcomesPerBlock: 3)
        
        // Use date within the 7-day learning window
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let baseDate = calendar.date(byAdding: .day, value: -1, to: today)!
            .addingTimeInterval(9 * 60 * 60)  // 09:00 yesterday
        
        // Record outcomes with consistent positive error (actual > predicted)
        // This should decrease ISF (more aggressive dosing)
        for i in 0..<5 {
            let outcome = TuningOutcome(
                timestamp: baseDate.addingTimeInterval(Double(i) * 300),
                timeBlock: 2,
                predictedGlucose: 100,
                actualGlucose: 120,  // 20 mg/dL higher than predicted
                insulinDelivered: 0.5,
                carbsConsumed: 0
            )
            await learner.recordOutcome(outcome)
        }
        
        // Get adjusted ISF during the same block
        let result = await learner.adjustedISF(baseISF: 50.0, at: baseDate)
        
        #expect(result.source == .learned)
        #expect(result.adjustedValue < 50.0)  // Should decrease ISF
    }
    
    @Test("Carb outcomes filtered")
    func carbOutcomesFiltered() async {
        let learner = ISFLearner(minOutcomesPerBlock: 3)
        
        // Use date within the 7-day learning window
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let baseDate = calendar.date(byAdding: .day, value: -1, to: today)!
            .addingTimeInterval(9 * 60 * 60)  // 09:00 yesterday
        
        // Record outcomes with carbs (should be filtered)
        for i in 0..<5 {
            let outcome = TuningOutcome(
                timestamp: baseDate.addingTimeInterval(Double(i) * 300),
                timeBlock: 2,
                predictedGlucose: 100,
                actualGlucose: 200,  // High error but during meal
                insulinDelivered: 0.5,
                carbsConsumed: 30  // Meal carbs
            )
            await learner.recordOutcome(outcome)
        }
        
        // Should not learn from high-carb outcomes
        let hasData = await learner.hasLearnedData
        #expect(!hasData)
    }
    
    @Test("Reset")
    func reset() async {
        let learner = ISFLearner(minOutcomesPerBlock: 3)
        
        // Add some data
        for i in 0..<5 {
            let outcome = TuningOutcome(
                timestamp: Date().addingTimeInterval(Double(i) * 300),
                timeBlock: 2,
                predictedGlucose: 100,
                actualGlucose: 120,
                insulinDelivered: 0.5,
                carbsConsumed: 0
            )
            await learner.recordOutcome(outcome)
        }
        
        await learner.reset()
        
        let hasData = await learner.hasLearnedData
        let count = await learner.outcomeCount
        #expect(!hasData)
        #expect(count == 0)
    }
}

@Suite("Delta Glucose Integrator")
struct DeltaGlucoseIntegratorTests {
    @Test("Initial Ki is zero")
    func initialKiIsZero() async {
        let integrator = DeltaGlucoseIntegrator()
        let ki = await integrator.currentKi
        #expect(ki == 0)
    }
    
    @Test("Update accumulates error")
    func updateAccumulatesError() async {
        let integrator = DeltaGlucoseIntegrator()
        
        _ = await integrator.update(deltaError: 10, at: Date())
        let ki = await integrator.currentKi
        
        #expect(ki > 0)
    }
    
    @Test("Decay reduces Ki")
    func decayReducesKi() async {
        let integrator = DeltaGlucoseIntegrator()
        
        // Add error
        _ = await integrator.update(deltaError: 10, at: Date())
        let ki1 = await integrator.currentKi
        
        // Update with zero error (just decay)
        _ = await integrator.update(deltaError: 0, at: Date())
        let ki2 = await integrator.currentKi
        
        #expect(ki2 < ki1)
    }
    
    @Test("Clamp prevents windup")
    func clampPreventsWindup() async {
        let integrator = DeltaGlucoseIntegrator(maxKi: 2.0)
        
        // Add many large errors
        for _ in 0..<100 {
            _ = await integrator.update(deltaError: 100, at: Date())
        }
        
        let ki = await integrator.currentKi
        #expect(ki <= 2.0)
    }
    
    @Test("Reset")
    func integratorReset() async {
        let integrator = DeltaGlucoseIntegrator()
        
        _ = await integrator.update(deltaError: 10, at: Date())
        await integrator.reset()
        
        let ki = await integrator.currentKi
        #expect(ki == 0)
    }
}

@Suite("Tuning Outcome")
struct TuningOutcomeTests {
    @Test("Prediction error")
    func predictionError() {
        let outcome = TuningOutcome(
            timestamp: Date(),
            timeBlock: 2,
            predictedGlucose: 100,
            actualGlucose: 120,
            insulinDelivered: 0.5,
            carbsConsumed: 0
        )
        
        #expect(outcome.predictionError == 20)
    }
    
    @Test("Negative prediction error")
    func negativePredictionError() {
        let outcome = TuningOutcome(
            timestamp: Date(),
            timeBlock: 2,
            predictedGlucose: 150,
            actualGlucose: 130,
            insulinDelivered: 0.5,
            carbsConsumed: 0
        )
        
        #expect(outcome.predictionError == -20)
    }
}
