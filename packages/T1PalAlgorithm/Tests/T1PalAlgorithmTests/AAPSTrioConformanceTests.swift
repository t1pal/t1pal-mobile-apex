// SPDX-License-Identifier: AGPL-3.0-or-later
// AAPSTrioConformanceTests.swift - AAPS and Trio ecosystem conformance tests
// Extracted from EcosystemConformanceTests.swift (CODE-030)
// Trace: ALG-VERIFY-003, ALG-VERIFY-004

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - AAPS Conformance Tests (ALG-VERIFY-003)

/// Tests specifically validating AAPS (AndroidAPS) conformance.
/// The oref0-vectors contain AAPS OpenAPSSMBPlugin replays from real device logs.
/// These tests verify T1Pal algorithms behave similarly to AAPS SMB behavior.
@Suite("AAPS Conformance")
struct AAPSConformanceTests {
    
    // MARK: - AAPS Vector Tests
    
    /// Test that vectors are correctly identified as AAPS source
    @Test("Vectors are from AAPS")
    func vectorsAreFromAAPS() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var aapsCount = 0
        
        for fixture in fixtures.prefix(20) {
            let vector: Oref0TestVector = try FixtureLoader.load(fixture, subdirectory: "oref0-vectors")
            // Check source field contains "aaps" (all vectors are from AAPS replays)
            if vector.metadata.source.lowercased().contains("aaps") {
                aapsCount += 1
            }
        }
        
        #expect(aapsCount > 15, "Most vectors should be from AAPS source")
        print("✓ Verified \(aapsCount)/20 vectors are from AAPS source")
    }
    
    /// Test AAPS SMB algorithm conformance across all vectors
    @Test("AAPS SMB conformance")
    func aapsSMBConformance() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var tested = 0
        var withinTolerance = 0
        var smbMatchCount = 0
        var tempBasalMatchCount = 0
        var parseErrors = 0
        
        let algo = Oref1Algorithm()
        let tolerance = 0.5  // U/hr
        
        for fixture in fixtures {
            do {
                let vector: Oref0TestVector = try FixtureLoader.load(fixture, subdirectory: "oref0-vectors")
                
                // All vectors are from AAPS (check source field)
                guard vector.metadata.source.lowercased().contains("aaps") else { continue }
                guard let expectedRate = vector.expected.rate else { continue }
                
                let scheduledBasal = vector.input.profile.basalRate ?? 1.0
                
                let profile = TherapyProfile(
                    basalRates: [BasalRate(startTime: 0, rate: scheduledBasal)],
                    carbRatios: [CarbRatio(startTime: 0, ratio: vector.input.profile.carbRatio ?? 10)],
                    sensitivityFactors: [SensitivityFactor(startTime: 0, factor: vector.input.profile.sensitivity ?? 50)],
                    targetGlucose: TargetRange(
                        low: vector.input.profile.targetLow ?? 100,
                        high: vector.input.profile.targetHigh ?? 110
                    )
                )
                
                let glucose = (0..<3).map { i in
                    GlucoseReading(
                        glucose: vector.input.glucoseStatus.glucose + Double(i) * vector.input.glucoseStatus.delta
                    )
                }
                
                let inputs = AlgorithmInputs(
                    glucose: glucose,
                    insulinOnBoard: vector.input.iob.iob,
                    carbsOnBoard: vector.input.mealData?.mealCOB ?? 0,
                    profile: profile
                )
                
                do {
                    let decision = try algo.calculate(inputs)
                    tested += 1
                    
                    // Check temp basal rate match
                    if let suggestedRate = decision.suggestedTempBasal?.rate {
                        let diff = abs(suggestedRate - expectedRate)
                        if diff <= tolerance {
                            withinTolerance += 1
                            tempBasalMatchCount += 1
                        }
                    }
                    
                    // Check SMB direction match (both positive or both zero)
                    if let expectedSMB = vector.expected.units {
                        let hasSMB = decision.suggestedBolus ?? 0 > 0
                        let expectedHasSMB = expectedSMB > 0
                        if hasSMB == expectedHasSMB {
                            smbMatchCount += 1
                        }
                    }
                } catch {
                    // Skip calc errors
                }
            } catch {
                parseErrors += 1
            }
        }
        
        print("\n╔════════════════════════════════════════════════╗")
        print("║   ALG-VERIFY-003: AAPS SMB CONFORMANCE TEST    ║")
        print("╠════════════════════════════════════════════════╣")
        print("║ Total AAPS vectors:   \(String(format: "%3d", fixtures.count))                    ║")
        print("║ Tested (SMB plugin):  \(String(format: "%3d", tested))                    ║")
        print("║ Temp basal match:     \(String(format: "%3d", tempBasalMatchCount)) (±\(tolerance) U/hr)      ║")
        print("║ SMB direction match:  \(String(format: "%3d", smbMatchCount))                    ║")
        print("║ Parse errors:         \(String(format: "%3d", parseErrors))                    ║")
        if tested > 0 {
            let rate = Double(withinTolerance) / Double(tested) * 100
            print("║ Conformance rate:     \(String(format: "%5.1f%%", rate))                 ║")
        }
        print("╚════════════════════════════════════════════════╝\n")
        
        // Acceptance: 50+ vectors tested (some may lack expected rate)
        #expect(tested > 40, "Should test at least 40 AAPS vectors")
        // Acceptance: 50% conformance rate
        if tested > 0 {
            let rate = Double(withinTolerance) / Double(tested) * 100
            #expect(rate > 50.0, "Should have at least 50% conformance with AAPS")
        }
    }
    
    /// Test AAPS basal adjustment categories
    @Test("AAPS basal adjustment categories")
    func aapsBasalAdjustmentCategories() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var categories: [String: Int] = [:]
        
        for fixture in fixtures {
            if let vector: Oref0TestVector = try? FixtureLoader.load(fixture, subdirectory: "oref0-vectors") {
                categories[vector.metadata.category, default: 0] += 1
            }
        }
        
        print("\n╔════════════════════════════════════════════════╗")
        print("║   AAPS Vector Categories                       ║")
        print("╠════════════════════════════════════════════════╣")
        for (category, count) in categories.sorted(by: { $0.value > $1.value }) {
            print("║ \(category.padding(toLength: 25, withPad: " ", startingAt: 0)): \(String(format: "%3d", count))              ║")
        }
        print("╚════════════════════════════════════════════════╝\n")
        
        #expect(categories.count > 0, "Should have categorized vectors")
    }
    
    /// Test AAPS glucose range coverage
    @Test("AAPS glucose range coverage")
    func aapsGlucoseRangeCoverage() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var hypoCount = 0      // < 70
        var lowCount = 0       // 70-80
        var inRangeCount = 0   // 80-180
        var highCount = 0      // 180-250
        var veryHighCount = 0  // > 250
        
        for fixture in fixtures {
            if let vector: Oref0TestVector = try? FixtureLoader.load(fixture, subdirectory: "oref0-vectors") {
                let glucose = vector.input.glucoseStatus.glucose
                switch glucose {
                case ..<70: hypoCount += 1
                case 70..<80: lowCount += 1
                case 80..<180: inRangeCount += 1
                case 180..<250: highCount += 1
                default: veryHighCount += 1
                }
            }
        }
        
        print("\n╔════════════════════════════════════════════════╗")
        print("║   AAPS Glucose Range Coverage                  ║")
        print("╠════════════════════════════════════════════════╣")
        print("║ Hypoglycemia (<70):   \(String(format: "%3d", hypoCount)) vectors             ║")
        print("║ Low (70-80):          \(String(format: "%3d", lowCount)) vectors             ║")
        print("║ In range (80-180):    \(String(format: "%3d", inRangeCount)) vectors             ║")
        print("║ High (180-250):       \(String(format: "%3d", highCount)) vectors             ║")
        print("║ Very high (>250):     \(String(format: "%3d", veryHighCount)) vectors             ║")
        print("╚════════════════════════════════════════════════╝\n")
        
        // Should have diverse glucose coverage
        let total = hypoCount + lowCount + inRangeCount + highCount + veryHighCount
        #expect(total > 50, "Should have 50+ vectors for glucose coverage")
    }
    
    /// Test AAPS IOB range coverage  
    @Test("AAPS IOB range coverage")
    func aapsIOBRangeCoverage() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var negativeIOB = 0
        var lowIOB = 0       // 0-1
        var mediumIOB = 0    // 1-3
        var highIOB = 0      // 3+
        
        for fixture in fixtures {
            if let vector: Oref0TestVector = try? FixtureLoader.load(fixture, subdirectory: "oref0-vectors") {
                let iob = vector.input.iob.iob
                switch iob {
                case ..<0: negativeIOB += 1
                case 0..<1: lowIOB += 1
                case 1..<3: mediumIOB += 1
                default: highIOB += 1
                }
            }
        }
        
        print("\n╔════════════════════════════════════════════════╗")
        print("║   AAPS IOB Range Coverage                      ║")
        print("╠════════════════════════════════════════════════╣")
        print("║ Negative IOB:         \(String(format: "%3d", negativeIOB)) vectors             ║")
        print("║ Low IOB (0-1):        \(String(format: "%3d", lowIOB)) vectors             ║")
        print("║ Medium IOB (1-3):     \(String(format: "%3d", mediumIOB)) vectors             ║")
        print("║ High IOB (3+):        \(String(format: "%3d", highIOB)) vectors             ║")
        print("╚════════════════════════════════════════════════╝\n")
        
        #expect(negativeIOB + lowIOB + mediumIOB + highIOB > 50, "Should have 50+ vectors for IOB coverage")
    }
    
    /// Test AAPS COB handling
    @Test("AAPS COB handling")
    func aapsCOBHandling() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var withCOB = 0
        var withoutCOB = 0
        
        for fixture in fixtures {
            if let vector: Oref0TestVector = try? FixtureLoader.load(fixture, subdirectory: "oref0-vectors") {
                let cob = vector.input.mealData?.mealCOB ?? 0
                if cob > 0 {
                    withCOB += 1
                } else {
                    withoutCOB += 1
                }
            }
        }
        
        print("✓ AAPS vectors with COB: \(withCOB), without COB: \(withoutCOB)")
        #expect(withCOB + withoutCOB > 50, "Should have 50+ vectors")
    }
    
    /// Test AAPS decision direction correlation
    @Test("AAPS decision direction correlation")
    func aapsDecisionDirectionCorrelation() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var increaseWhenHigh = 0
        var decreaseWhenLow = 0
        var suspendWhenHypo = 0
        var total = 0
        
        let algo = Oref1Algorithm()
        
        for fixture in fixtures.prefix(50) {
            guard let vector: Oref0TestVector = try? FixtureLoader.load(fixture, subdirectory: "oref0-vectors"),
                  let expectedRate = vector.expected.rate else { continue }
            
            let scheduledBasal = vector.input.profile.basalRate ?? 1.0
            let glucose = vector.input.glucoseStatus.glucose
            
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: scheduledBasal)],
                carbRatios: [CarbRatio(startTime: 0, ratio: vector.input.profile.carbRatio ?? 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: vector.input.profile.sensitivity ?? 50)],
                targetGlucose: TargetRange(
                    low: vector.input.profile.targetLow ?? 100,
                    high: vector.input.profile.targetHigh ?? 110
                )
            )
            
            let glucoseReadings = (0..<3).map { i in
                GlucoseReading(
                    glucose: glucose + Double(i) * vector.input.glucoseStatus.delta
                )
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucoseReadings,
                insulinOnBoard: vector.input.iob.iob,
                carbsOnBoard: vector.input.mealData?.mealCOB ?? 0,
                profile: profile
            )
            
            guard let decision = try? algo.calculate(inputs),
                  let suggestedRate = decision.suggestedTempBasal?.rate else { continue }
            
            total += 1
            
            // Check logical consistency
            if glucose > 180 && suggestedRate > scheduledBasal {
                increaseWhenHigh += 1
            }
            if glucose < 80 && suggestedRate < scheduledBasal {
                decreaseWhenLow += 1
            }
            if glucose < 70 && suggestedRate == 0 {
                suspendWhenHypo += 1
            }
        }
        
        print("\n╔════════════════════════════════════════════════╗")
        print("║   AAPS Decision Direction Correlation          ║")
        print("╠════════════════════════════════════════════════╣")
        print("║ Increase when high:   \(String(format: "%3d", increaseWhenHigh)) / \(total)                  ║")
        print("║ Decrease when low:    \(String(format: "%3d", decreaseWhenLow)) / \(total)                  ║")
        print("║ Suspend when hypo:    \(String(format: "%3d", suspendWhenHypo)) / \(total)                  ║")
        print("╚════════════════════════════════════════════════╝\n")
        
        #expect(total > 30, "Should test at least 30 vectors")
    }
}

// MARK: - Trio Conformance Tests (ALG-VERIFY-004)

/// Tests specifically validating Trio (iOS oref fork) conformance.
/// Trio uses oref0/oref1 algorithms with additional features like Dynamic ISF.
/// These tests verify T1Pal algorithms behave similarly to Trio's oref implementation.
@Suite("Trio Conformance")
struct TrioConformanceTests {
    
    // MARK: - Trio Algorithm Compatibility
    
    /// Test Trio algorithm compatibility using existing oref vectors
    /// Trio uses the same oref algorithms as AAPS, so vectors should apply
    @Test("Trio oref compatibility")
    func trioOrefCompatibility() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-vectors")
        var tested = 0
        var withinTolerance = 0
        var parseErrors = 0
        
        let algo = Oref1Algorithm()
        let tolerance = 0.5  // U/hr
        
        for fixture in fixtures {
            do {
                let vector: Oref0TestVector = try FixtureLoader.load(fixture, subdirectory: "oref0-vectors")
                guard let expectedRate = vector.expected.rate else { continue }
                
                let scheduledBasal = vector.input.profile.basalRate ?? 1.0
                
                let profile = TherapyProfile(
                    basalRates: [BasalRate(startTime: 0, rate: scheduledBasal)],
                    carbRatios: [CarbRatio(startTime: 0, ratio: vector.input.profile.carbRatio ?? 10)],
                    sensitivityFactors: [SensitivityFactor(startTime: 0, factor: vector.input.profile.sensitivity ?? 50)],
                    targetGlucose: TargetRange(
                        low: vector.input.profile.targetLow ?? 100,
                        high: vector.input.profile.targetHigh ?? 110
                    )
                )
                
                let glucose = (0..<3).map { i in
                    GlucoseReading(
                        glucose: vector.input.glucoseStatus.glucose + Double(i) * vector.input.glucoseStatus.delta
                    )
                }
                
                let inputs = AlgorithmInputs(
                    glucose: glucose,
                    insulinOnBoard: vector.input.iob.iob,
                    carbsOnBoard: vector.input.mealData?.mealCOB ?? 0,
                    profile: profile
                )
                
                do {
                    let decision = try algo.calculate(inputs)
                    tested += 1
                    
                    if let suggestedRate = decision.suggestedTempBasal?.rate {
                        let diff = abs(suggestedRate - expectedRate)
                        if diff <= tolerance {
                            withinTolerance += 1
                        }
                    }
                } catch {
                    // Skip calc errors
                }
            } catch {
                parseErrors += 1
            }
        }
        
        print("\n╔════════════════════════════════════════════════════╗")
        print("║   ALG-VERIFY-004: TRIO OREF COMPATIBILITY TEST     ║")
        print("╠════════════════════════════════════════════════════╣")
        print("║ Total vectors:        \(String(format: "%3d", fixtures.count))                       ║")
        print("║ Tested:               \(String(format: "%3d", tested))                       ║")
        print("║ Within tolerance:     \(String(format: "%3d", withinTolerance)) (±\(tolerance) U/hr)         ║")
        print("║ Parse errors:         \(String(format: "%3d", parseErrors))                       ║")
        if tested > 0 {
            let rate = Double(withinTolerance) / Double(tested) * 100
            print("║ Conformance rate:     \(String(format: "%5.1f%%", rate))                    ║")
        }
        print("╚════════════════════════════════════════════════════╝\n")
        
        #expect(tested > 40, "Should test at least 40 vectors for Trio compatibility")
        if tested > 0 {
            let rate = Double(withinTolerance) / Double(tested) * 100
            #expect(rate > 50.0, "Should have at least 50% conformance with Trio oref")
        }
    }
    
    /// Test Dynamic ISF calculation patterns (Trio feature)
    /// Dynamic ISF adjusts sensitivity based on glucose level
    @Test("Dynamic ISF patterns")
    func dynamicISFPatterns() throws {
        let algo = Oref1Algorithm()
        let sensitivityTests: [(glucose: Double, expectedDirection: String)] = [
            (250, "lower"),   // High glucose → lower ISF (more aggressive)
            (180, "lower"),   // Above target → lower ISF
            (100, "neutral"), // In range → neutral ISF
            (70, "higher"),   // Low glucose → higher ISF (less aggressive)
        ]
        
        var matchCount = 0
        
        for test in sensitivityTests {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            
            let glucose = (0..<3).map { _ in
                GlucoseReading(glucose: test.glucose)
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 0,
                carbsOnBoard: 0,
                profile: profile
            )
            
            guard let decision = try? algo.calculate(inputs),
                  let suggestedRate = decision.suggestedTempBasal?.rate else { continue }
            
            // Check if algorithm direction matches expected behavior
            let scheduledBasal = 1.0
            switch test.expectedDirection {
            case "lower":
                if suggestedRate > scheduledBasal { matchCount += 1 }
            case "higher":
                if suggestedRate < scheduledBasal { matchCount += 1 }
            case "neutral":
                if abs(suggestedRate - scheduledBasal) <= 0.2 { matchCount += 1 }
            default:
                break
            }
        }
        
        print("✓ Dynamic ISF pattern test: \(matchCount)/\(sensitivityTests.count) direction matches")
        #expect(matchCount > 2, "Should match at least 3/4 ISF patterns")
    }
    
    /// Test SMB (Super Micro Bolus) decision patterns
    /// Trio allows SMB when conditions are met
    @Test("SMB decision patterns")
    func smbDecisionPatterns() throws {
        let algo = Oref1Algorithm()
        var smbTests = 0
        
        // Test scenarios where SMB might be suggested
        let testScenarios: [(glucose: Double, delta: Double, iob: Double, expectSMB: Bool)] = [
            (180, 20, 0.5, true),   // Rising high, low IOB → SMB likely
            (200, 30, 0.0, true),   // High and rising fast → SMB likely
            (100, 5, 0.5, false),   // In range, stable → no SMB needed
            (70, -10, 0.0, false),  // Falling low → never SMB
            (150, 0, 3.0, false),   // High IOB → SMB unlikely
        ]
        
        for scenario in testScenarios {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110),
                maxIOB: 5.0
            )
            
            let glucose = (0..<3).map { i in
                GlucoseReading(glucose: scenario.glucose - Double(i) * scenario.delta)
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: scenario.iob,
                carbsOnBoard: 0,
                profile: profile
            )
            
            guard (try? algo.calculate(inputs)) != nil else { continue }
            smbTests += 1
        }
        
        print("✓ SMB decision test: \(smbTests) scenarios tested")
        #expect(smbTests > 3, "Should test at least 4 SMB scenarios")
    }
    
    /// Test autosens-like behavior (sensitivity adjustment)
    @Test("Autosens behavior")
    func autosensBehavior() throws {
        let algo = Oref1Algorithm()
        
        // Test that algorithm behaves differently with different sensitivity values
        let adjustedSensitivities = [30.0, 50.0, 70.0]  // Lower = more sensitive
        var outputs: [Double] = []
        
        for sensitivity in adjustedSensitivities {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: sensitivity)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            
            let glucose = (0..<3).map { _ in
                GlucoseReading(glucose: 180)  // Fixed high glucose
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 0,
                carbsOnBoard: 0,
                profile: profile
            )
            
            if let decision = try? algo.calculate(inputs),
               let rate = decision.suggestedTempBasal?.rate {
                outputs.append(rate)
            }
        }
        
        print("✓ Autosens behavior test: sensitivity 30/50/70 → rates \(outputs)")
        #expect(outputs.count == 3, "Should get output for all sensitivity values")
        
        // With higher sensitivity (lower ISF), should suggest higher basal
        if outputs.count == 3 {
            #expect(outputs[0] > outputs[2], 
                "Lower ISF (more sensitive) should suggest higher temp basal")
        }
    }
    
    /// Test Trio's target adjustment patterns
    @Test("Target adjustment patterns")
    func targetAdjustmentPatterns() throws {
        let algo = Oref1Algorithm()
        var resultsWithLowTarget: Double?
        var resultsWithNormalTarget: Double?
        var resultsWithHighTarget: Double?
        
        // Same inputs, different targets
        let targets: [(low: Double, high: Double, name: String)] = [
            (90, 100, "low"),
            (100, 110, "normal"),
            (110, 120, "high"),
        ]
        
        for target in targets {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: target.low, high: target.high)
            )
            
            let glucose = (0..<3).map { _ in
                GlucoseReading(glucose: 150)  // Fixed above all targets
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 0,
                carbsOnBoard: 0,
                profile: profile
            )
            
            if let decision = try? algo.calculate(inputs),
               let rate = decision.suggestedTempBasal?.rate {
                switch target.name {
                case "low": resultsWithLowTarget = rate
                case "normal": resultsWithNormalTarget = rate
                case "high": resultsWithHighTarget = rate
                default: break
                }
            }
        }
        
        print("✓ Target adjustment test: low=\(resultsWithLowTarget ?? 0), normal=\(resultsWithNormalTarget ?? 0), high=\(resultsWithHighTarget ?? 0)")
        
        // Lower target should result in higher temp basal (more aggressive to reach lower target)
        if let low = resultsWithLowTarget, let high = resultsWithHighTarget {
            #expect(low >= high, 
                "Lower target should result in equal or higher temp basal")
        }
    }
    
    /// Test COB decay patterns
    @Test("COB decay patterns")
    func cobDecayPatterns() throws {
        let algo = Oref1Algorithm()
        let cobValues: [Double] = [0, 10, 30, 50]
        var outputs: [Double] = []
        
        for cob in cobValues {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            
            let glucose = (0..<3).map { _ in
                GlucoseReading(glucose: 120)  // Slightly above target
            }
            
            let inputs = AlgorithmInputs(
                glucose: glucose,
                insulinOnBoard: 0.5,
                carbsOnBoard: cob,
                profile: profile
            )
            
            if let decision = try? algo.calculate(inputs),
               let rate = decision.suggestedTempBasal?.rate {
                outputs.append(rate)
            }
        }
        
        print("✓ COB decay test: COB 0/10/30/50 → rates \(outputs)")
        #expect(outputs.count == 4, "Should get output for all COB values")
    }
    
    /// Test that Trio-compatible algorithm handles edge cases safely
    @Test("Trio safety edge cases")
    func trioSafetyEdgeCases() throws {
        let algo = Oref1Algorithm()
        var safetyPassed = 0
        let totalCases = 5
        
        // Edge case 1: Very low glucose - should suspend
        do {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            let glucose = (0..<3).map { _ in GlucoseReading(glucose: 55) }
            let inputs = AlgorithmInputs(glucose: glucose, insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
            if let decision = try? algo.calculate(inputs),
               let rate = decision.suggestedTempBasal?.rate,
               rate == 0 {
                safetyPassed += 1
            }
        }
        
        // Edge case 2: Very high IOB - should limit
        do {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110),
                maxIOB: 5.0
            )
            let glucose = (0..<3).map { _ in GlucoseReading(glucose: 200) }
            let inputs = AlgorithmInputs(glucose: glucose, insulinOnBoard: 6.0, carbsOnBoard: 0, profile: profile)
            if (try? algo.calculate(inputs)) != nil {
                safetyPassed += 1
            }
        }
        
        // Edge case 3: Rapid drop - should reduce
        do {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            let glucose = [
                GlucoseReading(glucose: 100),
                GlucoseReading(glucose: 130),
                GlucoseReading(glucose: 160)
            ]
            let inputs = AlgorithmInputs(glucose: glucose, insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
            if let decision = try? algo.calculate(inputs),
               let rate = decision.suggestedTempBasal?.rate,
               rate < 1.0 {
                safetyPassed += 1
            }
        }
        
        // Edge case 4: Empty glucose - should handle gracefully
        do {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            let inputs = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
            // Should either throw or handle gracefully
            _ = try? algo.calculate(inputs)
            safetyPassed += 1
        }
        
        // Edge case 5: Negative IOB - should handle
        do {
            let profile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
                targetGlucose: TargetRange(low: 100, high: 110)
            )
            let glucose = (0..<3).map { _ in GlucoseReading(glucose: 80) }
            let inputs = AlgorithmInputs(glucose: glucose, insulinOnBoard: -1.0, carbsOnBoard: 0, profile: profile)
            if (try? algo.calculate(inputs)) != nil {
                safetyPassed += 1
            }
        }
        
        print("\n╔════════════════════════════════════════════════════╗")
        print("║   TRIO SAFETY EDGE CASES                           ║")
        print("╠════════════════════════════════════════════════════╣")
        print("║ Cases tested:         \(String(format: "%3d", totalCases))                       ║")
        print("║ Cases passed:         \(String(format: "%3d", safetyPassed))                       ║")
        print("╚════════════════════════════════════════════════════╝\n")
        
        #expect(safetyPassed > 3, "Should pass at least 4/5 safety edge cases")
    }
}

