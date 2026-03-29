// SPDX-License-Identifier: MIT
//
// GlucosePatternsTests.swift
// BLEKitTests
//
// Tests for glucose pattern generators.

import Testing
import Foundation
@testable import BLEKit

// MARK: - Flat Pattern Tests

@Suite("Flat Glucose Pattern")
struct FlatGlucosePatternTests {
    
    @Test("Returns configured base glucose")
    func returnsConfiguredBaseGlucose() {
        let pattern = FlatGlucosePattern(baseGlucose: 120)
        #expect(pattern.currentGlucose() == 120)
    }
    
    @Test("Default base glucose is 100")
    func defaultBaseGlucoseIs100() {
        let pattern = FlatGlucosePattern()
        #expect(pattern.baseGlucose == 100)
    }
    
    @Test("Trend is always zero")
    func trendIsAlwaysZero() {
        let pattern = FlatGlucosePattern(baseGlucose: 150)
        #expect(pattern.currentTrend() == 0)
    }
    
    @Test("Glucose at any time equals base")
    func glucoseAtAnyTimeEqualsBase() {
        let pattern = FlatGlucosePattern(baseGlucose: 100)
        let future = Date().addingTimeInterval(3600)
        #expect(pattern.glucose(at: future) == 100)
    }
    
    @Test("Noise adds variation")
    func noiseAddsVariation() {
        let pattern = FlatGlucosePattern(baseGlucose: 100, noise: 5)
        let glucose1 = pattern.glucose(at: Date())
        let glucose2 = pattern.glucose(at: Date().addingTimeInterval(1))
        // Values should be within noise range
        #expect(glucose1 >= 95 && glucose1 <= 105)
        #expect(glucose2 >= 95 && glucose2 <= 105)
    }
    
    @Test("Conforms to GlucoseProvider")
    func conformsToGlucoseProvider() {
        let pattern = FlatGlucosePattern(baseGlucose: 120)
        let provider: any GlucoseProvider = pattern
        #expect(provider.currentGlucose() == 120)
    }
}

// MARK: - Sine Wave Pattern Tests

@Suite("Sine Wave Pattern")
struct SineWavePatternTests {
    
    @Test("Default values are reasonable")
    func defaultValuesAreReasonable() {
        let pattern = SineWavePattern()
        #expect(pattern.baseGlucose == 120)
        #expect(pattern.amplitude == 30)
        #expect(pattern.periodMinutes == 180)
    }
    
    @Test("Glucose stays within amplitude bounds")
    func glucoseStaysWithinAmplitudeBounds() {
        let pattern = SineWavePattern(baseGlucose: 120, amplitude: 30)
        
        // Sample at various points
        for minutes in stride(from: 0, to: 180, by: 15) {
            let time = Date().addingTimeInterval(Double(minutes) * 60)
            let glucose = pattern.glucose(at: time)
            #expect(glucose >= 90 && glucose <= 150)
        }
    }
    
    @Test("Glucose oscillates over period")
    func glucoseOscillatesOverPeriod() {
        var pattern = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60)
        pattern.startTime = Date()
        
        let start = pattern.glucose(at: pattern.startTime)
        let quarter = pattern.glucose(at: pattern.startTime.addingTimeInterval(15 * 60))
        let half = pattern.glucose(at: pattern.startTime.addingTimeInterval(30 * 60))
        
        // At start (phase 0), sin(0) = 0, so glucose = base
        #expect(start == 120)
        
        // At quarter period (phase π/2), sin = 1, glucose = base + amplitude
        #expect(quarter == 150)
        
        // At half period (phase π), sin = 0, glucose = base
        #expect(half == 120)
    }
    
    @Test("Trend reflects rate of change")
    func trendReflectsRateOfChange() {
        var pattern = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60)
        pattern.startTime = Date()
        
        // At start, cos(0) = 1, positive trend (rising)
        let trendAtStart = pattern.trend(at: pattern.startTime)
        #expect(trendAtStart > 0)
        
        // At quarter period, cos(π/2) = 0, no trend (peak)
        let trendAtQuarter = pattern.trend(at: pattern.startTime.addingTimeInterval(15 * 60))
        #expect(trendAtQuarter == 0)
        
        // At half period, cos(π) = -1, negative trend (falling)
        let trendAtHalf = pattern.trend(at: pattern.startTime.addingTimeInterval(30 * 60))
        #expect(trendAtHalf < 0)
    }
    
    @Test("Phase offset shifts the wave")
    func phaseOffsetShiftsWave() {
        var pattern1 = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60, phaseMinutes: 0)
        var pattern2 = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60, phaseMinutes: 15)
        pattern1.startTime = Date()
        pattern2.startTime = Date()
        
        // Pattern 2 should be at quarter point at start (shifted by 15 min = π/2)
        let glucose1 = pattern1.glucose(at: pattern1.startTime)
        let glucose2 = pattern2.glucose(at: pattern2.startTime)
        
        #expect(glucose1 == 120)  // sin(0) = 0
        #expect(glucose2 == 150)  // sin(π/2) = 1
    }
}

// MARK: - Meal Response Pattern Tests

@Suite("Meal Response Pattern")
struct MealResponsePatternTests {
    
    @Test("Default values are reasonable")
    func defaultValuesAreReasonable() {
        let pattern = MealResponsePattern()
        #expect(pattern.baseGlucose == 100)
        #expect(pattern.peakGlucose == 180)
        #expect(pattern.riseMinutes == 45)
        #expect(pattern.peakMinutes == 15)
        #expect(pattern.decayMinutes == 120)
    }
    
    @Test("Total duration is sum of phases")
    func totalDurationIsSumOfPhases() {
        let pattern = MealResponsePattern(
            riseMinutes: 45,
            peakMinutes: 15,
            decayMinutes: 120
        )
        #expect(pattern.totalDuration == 180)
    }
    
    @Test("Starts at base glucose")
    func startsAtBaseGlucose() {
        var pattern = MealResponsePattern(baseGlucose: 100, peakGlucose: 180)
        pattern.startTime = Date()
        let glucose = pattern.glucose(at: pattern.startTime)
        #expect(glucose == 100)
    }
    
    @Test("Reaches peak during peak phase")
    func reachesPeakDuringPeakPhase() {
        var pattern = MealResponsePattern(
            baseGlucose: 100,
            peakGlucose: 180,
            riseMinutes: 45,
            peakMinutes: 15
        )
        pattern.startTime = Date()
        
        // At start of peak phase
        let atPeak = pattern.glucose(at: pattern.startTime.addingTimeInterval(50 * 60))
        #expect(atPeak == 180)
    }
    
    @Test("Returns to baseline after decay")
    func returnsToBaselineAfterDecay() {
        var pattern = MealResponsePattern(
            baseGlucose: 100,
            peakGlucose: 180,
            riseMinutes: 45,
            peakMinutes: 15,
            decayMinutes: 120
        )
        pattern.startTime = Date()
        
        // After total duration
        let afterMeal = pattern.glucose(at: pattern.startTime.addingTimeInterval(200 * 60))
        #expect(afterMeal == 100)
    }
    
    @Test("Rise phase has positive trend")
    func risePhaseHasPositiveTrend() {
        var pattern = MealResponsePattern()
        pattern.startTime = Date()
        
        let trend = pattern.trend(at: pattern.startTime.addingTimeInterval(20 * 60))
        #expect(trend > 0)
    }
    
    @Test("Peak phase has zero trend")
    func peakPhaseHasZeroTrend() {
        var pattern = MealResponsePattern(riseMinutes: 45, peakMinutes: 15)
        pattern.startTime = Date()
        
        let trend = pattern.trend(at: pattern.startTime.addingTimeInterval(50 * 60))
        #expect(trend == 0)
    }
    
    @Test("Decay phase has negative trend")
    func decayPhaseHasNegativeTrend() {
        var pattern = MealResponsePattern(riseMinutes: 45, peakMinutes: 15, decayMinutes: 120)
        pattern.startTime = Date()
        
        let trend = pattern.trend(at: pattern.startTime.addingTimeInterval(70 * 60))
        #expect(trend < 0)
    }
    
    @Test("Start meal resets timing")
    func startMealResetsTiming() {
        var pattern = MealResponsePattern(baseGlucose: 100, peakGlucose: 180)
        
        // Simulate some time passing
        pattern.startTime = Date().addingTimeInterval(-200 * 60)
        
        // Start new meal
        pattern.startMeal()
        
        // Should be at base glucose again
        let glucose = pattern.glucose(at: Date())
        #expect(glucose == 100)
    }
}

// MARK: - Random Walk Pattern Tests

@Suite("Random Walk Pattern")
struct RandomWalkPatternTests {
    
    @Test("Default values are reasonable")
    func defaultValuesAreReasonable() {
        let pattern = RandomWalkPattern()
        #expect(pattern.baseGlucose == 120)
        #expect(pattern.volatility == 1.0)
        #expect(pattern.minGlucose == 70)
        #expect(pattern.maxGlucose == 250)
    }
    
    @Test("Starts at base glucose")
    func startsAtBaseGlucose() {
        var pattern = RandomWalkPattern(baseGlucose: 120)
        pattern.startTime = Date()
        let glucose = pattern.glucose(at: pattern.startTime)
        #expect(glucose == 120)
    }
    
    @Test("Stays within bounds")
    func staysWithinBounds() {
        var pattern = RandomWalkPattern(
            baseGlucose: 120,
            volatility: 5.0,
            minGlucose: 70,
            maxGlucose: 250
        )
        pattern.startTime = Date()
        
        // Sample many points
        for minutes in stride(from: 0, to: 120, by: 5) {
            let time = pattern.startTime.addingTimeInterval(Double(minutes) * 60)
            let glucose = pattern.glucose(at: time)
            #expect(glucose >= 70 && glucose <= 250)
        }
    }
    
    @Test("Same seed produces same sequence")
    func sameSeedProducesSameSequence() {
        let seed: UInt64 = 12345
        var pattern1 = RandomWalkPattern(baseGlucose: 120, seed: seed)
        var pattern2 = RandomWalkPattern(baseGlucose: 120, seed: seed)
        pattern1.startTime = Date()
        pattern2.startTime = pattern1.startTime
        
        for minutes in stride(from: 0, to: 60, by: 5) {
            let time = pattern1.startTime.addingTimeInterval(Double(minutes) * 60)
            let glucose1 = pattern1.glucose(at: time)
            let glucose2 = pattern2.glucose(at: time)
            #expect(glucose1 == glucose2)
        }
    }
    
    @Test("Different seeds produce different sequences")
    func differentSeedsProduceDifferentSequences() {
        var pattern1 = RandomWalkPattern(baseGlucose: 120, seed: 12345)
        var pattern2 = RandomWalkPattern(baseGlucose: 120, seed: 67890)
        pattern1.startTime = Date()
        pattern2.startTime = pattern1.startTime
        
        // At 60 minutes, should be different
        let time = pattern1.startTime.addingTimeInterval(60 * 60)
        let glucose1 = pattern1.glucose(at: time)
        let glucose2 = pattern2.glucose(at: time)
        #expect(glucose1 != glucose2)
    }
    
    @Test("Higher volatility causes more variation")
    func higherVolatilityCausesMoreVariation() {
        let lowVol = RandomWalkPattern(baseGlucose: 120, volatility: 0.5, seed: 12345)
        let highVol = RandomWalkPattern(baseGlucose: 120, volatility: 3.0, seed: 12345)
        
        // Check range of values over time
        var lowRange: (min: UInt16, max: UInt16) = (120, 120)
        var highRange: (min: UInt16, max: UInt16) = (120, 120)
        
        for minutes in stride(from: 0, to: 120, by: 5) {
            let time = Date().addingTimeInterval(Double(minutes) * 60)
            let lowGlucose = lowVol.glucose(at: time)
            let highGlucose = highVol.glucose(at: time)
            
            lowRange = (min(lowRange.min, lowGlucose), max(lowRange.max, lowGlucose))
            highRange = (min(highRange.min, highGlucose), max(highRange.max, highGlucose))
        }
        
        let lowSpread = lowRange.max - lowRange.min
        let highSpread = highRange.max - highRange.min
        
        #expect(highSpread >= lowSpread)
    }
}

// MARK: - Replay Pattern Tests

@Suite("Replay Pattern")
struct ReplayPatternTests {
    
    @Test("Empty readings returns 100")
    func emptyReadingsReturns100() {
        let pattern = ReplayPattern(readings: [])
        #expect(pattern.currentGlucose() == 100)
    }
    
    @Test("Single reading returns that value")
    func singleReadingReturnsThatValue() {
        var pattern = ReplayPattern(readings: [(0, 150)])
        pattern.startTime = Date()
        #expect(pattern.glucose(at: pattern.startTime) == 150)
    }
    
    @Test("Interpolates between readings")
    func interpolatesBetweenReadings() {
        var pattern = ReplayPattern(readings: [
            (0, 100),
            (10, 200)
        ])
        pattern.startTime = Date()
        
        // At 5 minutes, should be halfway = 150
        let glucose = pattern.glucose(at: pattern.startTime.addingTimeInterval(5 * 60))
        #expect(glucose == 150)
    }
    
    @Test("Loop repeats pattern")
    func loopRepeatsPattern() {
        var pattern = ReplayPattern(
            readings: [
                (0, 100),
                (10, 200)
            ],
            loop: true
        )
        pattern.startTime = Date()
        
        // At 5 minutes (middle of first cycle)
        let atMid = pattern.glucose(at: pattern.startTime.addingTimeInterval(5 * 60))
        #expect(atMid == 150)  // Interpolated
        
        // At 15 minutes (middle of second cycle = 15 % 10 = 5)
        let atSecondCycle = pattern.glucose(at: pattern.startTime.addingTimeInterval(15 * 60))
        #expect(atSecondCycle == 150)  // Same as 5 minutes
    }
    
    @Test("Duration is last reading offset")
    func durationIsLastReadingOffset() {
        let pattern = ReplayPattern(readings: [
            (0, 100),
            (30, 150),
            (60, 120)
        ])
        #expect(pattern.duration == 60)
    }
    
    @Test("Readings are sorted by offset")
    func readingsAreSortedByOffset() {
        // Create with out-of-order readings
        var pattern = ReplayPattern(readings: [
            (30, 150),
            (0, 100),
            (60, 120)
        ])
        pattern.startTime = Date()
        
        // Should still work correctly
        let at0 = pattern.glucose(at: pattern.startTime)
        let at30 = pattern.glucose(at: pattern.startTime.addingTimeInterval(30 * 60))
        let at60 = pattern.glucose(at: pattern.startTime.addingTimeInterval(60 * 60))
        
        #expect(at0 == 100)
        #expect(at30 == 150)
        #expect(at60 == 120)
    }
}

// MARK: - Composite Pattern Tests

@Suite("Composite Pattern")
struct CompositePatternTests {
    
    @Test("Single pattern returns its value")
    func singlePatternReturnsItsValue() {
        let flat = FlatGlucosePattern(baseGlucose: 100)
        let composite = CompositePattern(patterns: [flat])
        #expect(composite.currentGlucose() == 100)
    }
    
    @Test("Equal weights average values")
    func equalWeightsAverageValues() {
        let flat1 = FlatGlucosePattern(baseGlucose: 100)
        let flat2 = FlatGlucosePattern(baseGlucose: 200)
        let composite = CompositePattern(patterns: [flat1, flat2])
        #expect(composite.currentGlucose() == 150)
    }
    
    @Test("Custom weights apply correctly")
    func customWeightsApplyCorrectly() {
        let flat1 = FlatGlucosePattern(baseGlucose: 100)
        let flat2 = FlatGlucosePattern(baseGlucose: 200)
        // 75% weight on first pattern
        let composite = CompositePattern(patterns: [flat1, flat2], weights: [3, 1])
        // Expected: 100 * 0.75 + 200 * 0.25 = 75 + 50 = 125
        #expect(composite.currentGlucose() == 125)
    }
    
    @Test("Empty patterns returns 100")
    func emptyPatternsReturns100() {
        let composite = CompositePattern(patterns: [])
        #expect(composite.currentGlucose() == 100)
    }
    
    @Test("Trends are averaged")
    func trendsAreAveraged() {
        var sine1 = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60)
        var sine2 = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60)
        sine1.startTime = Date()
        sine2.startTime = Date()
        
        let composite = CompositePattern(patterns: [sine1, sine2])
        
        // Both have same trend, so composite should match
        let singleTrend = sine1.currentTrend()
        let compositeTrend = composite.currentTrend()
        #expect(singleTrend == compositeTrend)
    }
}

// MARK: - Protocol Conformance Tests

@Suite("Glucose Pattern Protocol")
struct GlucosePatternProtocolTests {
    
    @Test("All patterns conform to GlucoseProvider")
    func allPatternsConformToGlucoseProvider() {
        let patterns: [any GlucoseProvider] = [
            FlatGlucosePattern(),
            SineWavePattern(),
            MealResponsePattern(),
            RandomWalkPattern(),
            ReplayPattern(readings: [(0, 100)]),
            CompositePattern(patterns: [FlatGlucosePattern()])
        ]
        
        for pattern in patterns {
            let glucose = pattern.currentGlucose()
            #expect(glucose > 0)
        }
    }
    
    @Test("Predicted glucose uses trend")
    func predictedGlucoseUsesTrend() {
        var pattern = SineWavePattern(baseGlucose: 120, amplitude: 30, periodMinutes: 60)
        pattern.startTime = Date()
        
        let current = pattern.currentGlucose()
        let predicted = pattern.predictedGlucose()
        let trend = pattern.currentTrend()
        
        // Predicted should be current + trend * 15 minutes (clamped)
        let expected = Int(current) + Int(trend) * 15
        let expectedClamped = UInt16(clamping: max(40, min(400, expected)))
        #expect(predicted == expectedClamped)
    }
    
    @Test("Reset restarts pattern")
    func resetRestartsPattern() {
        var pattern = MealResponsePattern(baseGlucose: 100, peakGlucose: 180)
        
        // Advance into meal
        pattern.startTime = Date().addingTimeInterval(-50 * 60)
        let duringMeal = pattern.currentGlucose()
        #expect(duringMeal > 100)
        
        // Reset
        pattern.reset()
        
        // Should be back at start
        let afterReset = pattern.currentGlucose()
        #expect(afterReset == 100)
    }
}
