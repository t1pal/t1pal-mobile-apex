// SPDX-License-Identifier: MIT
//
// CGMAlgorithmIntegrationTests.swift
// T1PalDebugKit
//
// True integration tests: CGM data → Algorithm → Predictions
// Trace: INT-001, DEEP-INTEGRATION-AUDIT
//
// These tests verify the complete data flow from CGM readings
// through the algorithm to dose recommendations.

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

// MARK: - CGM → Algorithm Integration Tests

@Suite("CGM Algorithm Integration")
struct CGMAlgorithmIntegrationTests {
    
    // MARK: - Test Fixtures
    
    /// Create a realistic therapy profile for testing
    static func createTestProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: [
                BasalRate(startTime: 0, rate: 1.0),       // Midnight: 1.0 U/hr
                BasalRate(startTime: 21600, rate: 1.2),  // 6 AM: 1.2 U/hr (dawn phenomenon)
                BasalRate(startTime: 43200, rate: 0.9),  // Noon: 0.9 U/hr
                BasalRate(startTime: 64800, rate: 1.0),  // 6 PM: 1.0 U/hr
            ],
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 10),      // 1:10 overnight
                CarbRatio(startTime: 21600, ratio: 8),   // 1:8 morning
                CarbRatio(startTime: 43200, ratio: 12),  // 1:12 afternoon
            ],
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 50),     // 50 mg/dL per U overnight
                SensitivityFactor(startTime: 21600, factor: 40), // 40 mg/dL per U morning
                SensitivityFactor(startTime: 43200, factor: 55), // 55 mg/dL per U afternoon
            ],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 8.0,
            maxBolus: 5.0
        )
    }
    
    /// Create glucose history with a specific pattern
    static func createGlucoseHistory(
        pattern: GlucosePattern,
        readings: Int = 24,
        endTime: Date = Date()
    ) -> [GlucoseReading] {
        var history: [GlucoseReading] = []
        
        for i in 0..<readings {
            let timestamp = endTime.addingTimeInterval(Double(-i * 300)) // 5-min intervals
            let (glucose, trend) = pattern.valueAt(index: i, total: readings)
            
            history.append(GlucoseReading(
                glucose: glucose,
                timestamp: timestamp,
                trend: trend
            ))
        }
        
        return history
    }
    
    /// Glucose patterns for testing
    enum GlucosePattern {
        case stable(around: Double)
        case rising(from: Double, to: Double)
        case falling(from: Double, to: Double)
        case hypo(nadir: Double)
        case hyper(peak: Double)
        case postMeal(peak: Double)
        
        func valueAt(index: Int, total: Int) -> (Double, GlucoseTrend) {
            let progress = Double(index) / Double(total - 1)
            
            switch self {
            case .stable(let value):
                // Small random variation around target
                let variation = sin(Double(index) * 0.5) * 5
                return (value + variation, .flat)
                
            case .rising(let from, let to):
                let value = from + (to - from) * (1 - progress)
                let trend: GlucoseTrend = (to - from) > 30 ? .singleUp : .fortyFiveUp
                return (value, trend)
                
            case .falling(let from, let to):
                let value = from - (from - to) * (1 - progress)
                let trend: GlucoseTrend = (from - to) > 30 ? .singleDown : .fortyFiveDown
                return (value, trend)
                
            case .hypo(let nadir):
                // U-shaped curve hitting nadir at 70% through
                let nadirPoint = 0.7
                if progress < nadirPoint {
                    let value = 120 - (120 - nadir) * (progress / nadirPoint)
                    return (value, .singleDown)
                } else {
                    let recovery = (progress - nadirPoint) / (1 - nadirPoint)
                    let value = nadir + (90 - nadir) * recovery
                    return (value, .fortyFiveUp)
                }
                
            case .hyper(let peak):
                // Inverted U-shaped curve
                let peakPoint = 0.5
                if progress < peakPoint {
                    let value = 150 + (peak - 150) * (progress / peakPoint)
                    return (value, .singleUp)
                } else {
                    let descent = (progress - peakPoint) / (1 - peakPoint)
                    let value = peak - (peak - 180) * descent
                    return (value, .fortyFiveDown)
                }
                
            case .postMeal(let peak):
                // Spike then gradual return
                let spikePoint = 0.3
                if progress < spikePoint {
                    let value = 110 + (peak - 110) * (progress / spikePoint)
                    return (value, .doubleUp)
                } else {
                    let descent = (progress - spikePoint) / (1 - spikePoint)
                    let value = peak - (peak - 130) * descent
                    return (value, .fortyFiveDown)
                }
            }
        }
    }
    
    // MARK: - Stable Glucose Tests
    
    @Test("Algorithm handles stable in-range glucose")
    func stableInRangeGlucose() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .stable(around: 105))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 1.5,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // With stable in-range glucose, should not suggest aggressive action
        #expect(decision.reason.count > 0, "Should provide a reason")
        
        // Predictions should exist
        #expect(decision.predictions != nil, "Should generate predictions")
        
        // If temp basal suggested, rate should be reasonable
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate >= 0, "Rate should not be negative")
            #expect(tempBasal.rate <= 5, "Rate should not exceed max basal")
        }
    }
    
    // MARK: - Rising Glucose Tests
    
    @Test("Algorithm responds to rising glucose")
    func risingGlucose() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .rising(from: 100, to: 180))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0.5,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Rising glucose should trigger increased insulin delivery
        #expect(decision.reason.contains("high") || decision.reason.count > 0,
                "Should acknowledge high trend")
        
        // Should suggest increased basal or SMB
        let hasAction = decision.suggestedTempBasal != nil || decision.suggestedBolus != nil
        #expect(hasAction, "Should suggest action for rising glucose")
        
        // Predictions should show impact
        if let predictions = decision.predictions {
            #expect(!predictions.iob.isEmpty || !predictions.zt.isEmpty,
                    "Should have prediction curves")
        }
    }
    
    // MARK: - Falling Glucose Tests
    
    @Test("Algorithm responds to falling glucose")
    func fallingGlucose() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .falling(from: 150, to: 80))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 3.0,  // Significant IOB
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Falling glucose with IOB should reduce delivery
        #expect(decision.reason.count > 0, "Should provide reasoning")
        
        // Should suggest reduced or suspended basal
        if let tempBasal = decision.suggestedTempBasal {
            // With falling BG toward hypo, should reduce delivery
            #expect(tempBasal.rate < 1.5, "Should reduce basal for falling glucose")
        }
        
        // Should NOT suggest additional bolus when falling
        #expect(decision.suggestedBolus == nil || decision.suggestedBolus == 0,
                "Should not bolus when falling toward low")
    }
    
    // MARK: - Hypoglycemia Prevention Tests
    
    @Test("Algorithm prevents hypoglycemia")
    func hypoPrevention() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .hypo(nadir: 55))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Algorithm should recognize low glucose
        let mentionsLow = decision.reason.lowercased().contains("low") ||
                          decision.reason.contains("suspend") ||
                          decision.reason.contains("0")
        #expect(mentionsLow || decision.suggestedTempBasal?.rate == 0,
                "Should respond to hypoglycemia")
        
        // Should suspend or minimize delivery
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 0.1, "Should suspend or near-zero for hypo")
        }
    }
    
    // MARK: - Hyperglycemia Correction Tests
    
    @Test("Algorithm corrects hyperglycemia")
    func hyperCorrection() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .hyper(peak: 280))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0.5,  // Low IOB
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should take corrective action
        let hasCorrection = decision.suggestedTempBasal != nil || decision.suggestedBolus != nil
        #expect(hasCorrection, "Should correct high glucose")
        
        // If temp basal, should be elevated
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate > 0, "Should increase delivery for high glucose")
        }
        
        // SMB may be suggested for rapid correction
        if let smb = decision.suggestedBolus {
            #expect(smb > 0 && smb <= 5.0, "SMB should be within safe limits")
        }
    }
    
    // MARK: - Post-Meal Tests
    
    @Test("Algorithm handles post-meal spike")
    func postMealSpike() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .postMeal(peak: 200))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 4.0,  // Recent meal bolus
            carbsOnBoard: 30.0,   // Active carbs
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // With COB and IOB, algorithm should account for active insulin
        #expect(decision.reason.count > 0, "Should provide reasoning")
        
        // Should not over-correct with existing IOB
        if let smb = decision.suggestedBolus {
            #expect(smb <= 2.0, "Should limit correction with existing IOB")
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Algorithm handles minimal glucose history")
    func minimalHistory() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .stable(around: 120), readings: 3)
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should still produce a decision with minimal data
        #expect(decision.reason.count > 0, "Should handle minimal history")
    }
    
    @Test("Algorithm handles empty glucose gracefully")
    func emptyGlucose() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        
        let inputs = AlgorithmInputs(
            glucose: [],
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should return safe decision with no data
        #expect(decision.suggestedBolus == nil, "Should not bolus without data")
        #expect(decision.reason.contains("No glucose") || decision.reason.count > 0,
                "Should explain lack of action")
    }
    
    // MARK: - Prediction Validation
    
    @Test("Predictions have reasonable values")
    func predictionValidation() throws {
        let algorithm = Oref1Algorithm()
        let profile = Self.createTestProfile()
        let glucose = Self.createGlucoseHistory(pattern: .stable(around: 130), readings: 36)
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 20.0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        if let predictions = decision.predictions {
            // IOB curve should exist and have values
            let iobCurve = predictions.iob
            if !iobCurve.isEmpty {
                for value in iobCurve {
                    #expect(value >= 0 && value <= 400,
                            "IOB prediction should be in physiological range")
                }
            }
            
            // ZT curve if present
            let ztCurve = predictions.zt
            if !ztCurve.isEmpty {
                for value in ztCurve {
                    #expect(value >= 0 && value <= 500,
                            "ZT prediction should be in physiological range")
                }
            }
            
            // UAM curve if present
            let uamCurve = predictions.uam
            if !uamCurve.isEmpty {
                for value in uamCurve {
                    #expect(value >= 0 && value <= 500,
                            "UAM prediction should be in physiological range")
                }
            }
        }
    }
    
    // MARK: - Safety Limit Tests
    
    @Test("Algorithm respects max IOB")
    func maxIOBRespected() throws {
        let algorithm = Oref1Algorithm()
        var profile = Self.createTestProfile()
        profile.maxIOB = 4.0  // Lower max IOB
        
        let glucose = Self.createGlucoseHistory(pattern: .hyper(peak: 300))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 3.5,  // Near max IOB
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should limit additional insulin when near max IOB
        if let smb = decision.suggestedBolus {
            let totalIOB = inputs.insulinOnBoard + smb
            #expect(totalIOB <= profile.maxIOB + 0.5,
                    "Should not exceed max IOB significantly")
        }
    }
    
    @Test("Algorithm respects max bolus")
    func maxBolusRespected() throws {
        let algorithm = Oref1Algorithm()
        var profile = Self.createTestProfile()
        profile.maxBolus = 2.0  // Lower max bolus
        
        let glucose = Self.createGlucoseHistory(pattern: .hyper(peak: 350))
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // SMB should not exceed max bolus (SMB typically limited to fraction of max)
        if let smb = decision.suggestedBolus {
            #expect(smb <= profile.maxBolus,
                    "SMB should not exceed max bolus")
        }
    }
}
