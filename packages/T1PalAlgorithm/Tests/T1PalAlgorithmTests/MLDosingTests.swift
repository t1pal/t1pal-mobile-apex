// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLDosingTests.swift
// T1Pal Mobile
//
// Tests for ML dosing providers and safety service
// Trace: GLUCOS-IMPL-005

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Dynamic ISF Provider")
struct DynamicISFProviderTests {
    
    // MARK: - Basic Scaling
    
    @Test("No scaling below target")
    func noScalingBelowTarget() async {
        let provider = DynamicISFProvider()
        let inputs = makeInputs(currentGlucose: 90)
        let baseline = TempBasal(rate: 1.0, duration: 30 * 60)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result?.scalingFactor == 1.0)
        #expect(result?.tempBasalRate == 1.0)
    }
    
    @Test("Linear scaling above target")
    func linearScalingAboveTarget() async {
        let provider = DynamicISFProvider(
            maxScalingIncrease: 0.5,
            glucoseRangeForScaling: 150
        )
        let inputs = makeInputs(currentGlucose: 175)  // 75 above target
        let baseline = TempBasal(rate: 1.0, duration: 30 * 60)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        // 75/150 = 0.5, so scaling = 1 + 0.5 * 0.5 = 1.25
        #expect(abs((result?.scalingFactor ?? 0) - 1.25) < 0.01)
        #expect(abs((result?.tempBasalRate ?? 0) - 1.25) < 0.01)
    }
    
    @Test("Max scaling at high glucose")
    func maxScalingAtHighGlucose() async {
        let provider = DynamicISFProvider(
            maxScalingIncrease: 0.5,
            glucoseRangeForScaling: 150
        )
        let inputs = makeInputs(currentGlucose: 300)  // Well above range
        let baseline = TempBasal(rate: 1.0, duration: 30 * 60)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        // Should cap at 1.5x
        #expect(abs((result?.scalingFactor ?? 0) - 1.5) < 0.01)
    }
    
    @Test("Disabled provider returns nil")
    func disabledProvider() async {
        let provider = DynamicISFProvider(isEnabled: false)
        let inputs = makeInputs(currentGlucose: 200)
        let baseline = TempBasal(rate: 1.0, duration: 30 * 60)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result == nil)
    }
    
    // MARK: - Helpers
    
    private func makeInputs(currentGlucose: Double) -> AlgorithmInputs {
        let reading = GlucoseReading(
            glucose: currentGlucose,
            timestamp: Date(),
            trend: .flat
        )
        return AlgorithmInputs(
            glucose: [reading],
            profile: TestHelpers.createTestProfile()
        )
    }
}

// MARK: - Test Helpers

private enum TestHelpers {
    static func createTestProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 8.0,
            maxBolus: 5.0
        )
    }
}

// MARK: - Safety Service Tests

@Suite("ML Safety Service")
struct MLSafetyServiceTests {
    
    @Test("Bound within limits")
    func boundWithinLimits() async {
        let service = MLSafetyService(timeHorizon: 3 * 60 * 60)
        
        let result = await service.bound(
            mlRecommendation: 1.5,
            physiologicalBaseline: 1.0,
            duration: 30 * 60,
            maxBasalRate: 2.0,
            at: Date()
        )
        
        // 1.5 U/hr for 30 min = 0.75 units
        // Baseline = 0.5 units, delta = 0.25 units
        // Max bound = 2.0 U/hr × 3 hr = 6 units
        // Should not be clamped
        #expect(!result.wasClamped)
        #expect(abs(result.tempBasal - 1.5) < 0.01)
    }
    
    @Test("Bound clamps high")
    func boundClampsHigh() async {
        let service = MLSafetyService(timeHorizon: 1 * 60 * 60)  // 1 hour for testing
        
        // First, record some history that uses up the bound
        let pastDate = Date().addingTimeInterval(-30 * 60)
        await service.recordDelivery(
            at: pastDate,
            programmedTempBasal: 3.0,  // 1.5 units in 30 min
            safetyBaseline: 1.0,       // 0.5 units baseline
            mlRecommendation: 3.0,     // delta = 1.0 units
            duration: 30 * 60
        )
        
        // Now try to deliver more
        let result = await service.bound(
            mlRecommendation: 5.0,  // Very high
            physiologicalBaseline: 1.0,
            duration: 30 * 60,
            maxBasalRate: 2.0,  // Bound = 2 units for 1 hour
            at: Date()
        )
        
        // Should be clamped because we already used some of the bound
        #expect(result.wasClamped)
    }
    
    @Test("Never negative")
    func neverNegative() async {
        let service = MLSafetyService()
        
        let result = await service.bound(
            mlRecommendation: -1.0,  // Negative (nonsensical)
            physiologicalBaseline: 0.5,
            duration: 30 * 60,
            maxBasalRate: 2.0,
            at: Date()
        )
        
        #expect(result.tempBasal >= 0)
    }
    
    @Test("History pruning")
    func historyPruning() async {
        let service = MLSafetyService(timeHorizon: 60)  // 1 minute for testing
        
        // Record old delivery
        let oldDate = Date().addingTimeInterval(-120)  // 2 minutes ago
        await service.recordDelivery(
            at: oldDate,
            programmedTempBasal: 2.0,
            safetyBaseline: 1.0,
            mlRecommendation: 2.0,
            duration: 30 * 60
        )
        
        // Record a new delivery to trigger pruning
        await service.recordDelivery(
            at: Date(),
            programmedTempBasal: 1.0,
            safetyBaseline: 1.0,
            mlRecommendation: 1.0,
            duration: 30 * 60
        )
        
        // Old record should be pruned, only new one remains
        let count = await service.historyCount
        #expect(count == 1)
    }
}

// MARK: - Biological Invariant Tests

@Suite("Biological Invariant Monitor")
struct BiologicalInvariantTests {
    
    var monitor: BiologicalInvariantMonitor { BiologicalInvariantMonitor() }
    
    @Test("Normal glucose change")
    func normalGlucoseChange() {
        // Normal IOB-driven glucose drop: -24 mg/dL/hr actual
        // With IOB=0.5, ISF=50: theoretical = -25 mg/dL/hr
        // Error = -24 - (-25) = +1 (small positive, not violated)
        let readings = makeReadings([120, 118, 116, 114, 112])  // -8 in 20 min = -24/hr
        
        let error = monitor.deltaGlucoseError(
            readings: readings,
            insulinOnBoard: 0.5,
            insulinSensitivity: 50  // Expected: -0.5 × 50 = -25 mg/dL/hr
        )
        
        #expect(error != nil)
        #expect(!monitor.isViolated(error!))
    }
    
    @Test("Violation detected")
    func violation() {
        // Unexpected rapid drop
        let readings = makeReadings([150, 140, 130, 120, 110])  // -10 per 5 min = -120/hr
        
        let error = monitor.deltaGlucoseError(
            readings: readings,
            insulinOnBoard: 1.0,
            insulinSensitivity: 50  // Expected only -50 mg/dL/hr
        )
        
        // Actual: -120/hr, Expected: -50/hr, Error: -70 mg/dL/hr
        #expect(error != nil)
        #expect(monitor.isViolated(error!))  // < -35 threshold
    }
    
    @Test("Ignores during digestion")
    func ignoresDuringDigestion() {
        // Rapidly rising glucose (meal)
        let readings = makeReadings([100, 120, 140, 160, 180])  // +20 per 5 min
        
        let error = monitor.deltaGlucoseError(
            readings: readings,
            insulinOnBoard: 1.0,
            insulinSensitivity: 50
        )
        
        // Should return nil because digestion threshold exceeded
        #expect(error == nil)
    }
    
    @Test("Emergency decision")
    func emergencyDecision() {
        let decision = monitor.emergencyDecision(
            error: -50,  // Violates threshold
            currentTime: Date()
        )
        
        #expect(decision != nil)
        #expect(decision?.suggestedTempBasal?.rate == 0)  // Suspended
        #expect(decision?.reason.contains("violated") ?? false)
    }
    
    @Test("No emergency when safe")
    func noEmergencyWhenSafe() {
        let decision = monitor.emergencyDecision(
            error: -20,  // Within threshold
            currentTime: Date()
        )
        
        #expect(decision == nil)
    }
    
    @Test("Insufficient readings")
    func insufficientReadings() {
        let readings = makeReadings([100, 105])  // Only 2 readings
        
        let error = monitor.deltaGlucoseError(
            readings: readings,
            insulinOnBoard: 1.0,
            insulinSensitivity: 50
        )
        
        #expect(error == nil)
    }
    
    // MARK: - Helpers
    
    private func makeReadings(_ values: [Double]) -> [GlucoseReading] {
        let now = Date()
        return values.enumerated().map { index, glucose in
            GlucoseReading(
                glucose: glucose,
                timestamp: now.addingTimeInterval(TimeInterval(index - values.count + 1) * 5 * 60),
                trend: .flat
            )
        }
    }
}
