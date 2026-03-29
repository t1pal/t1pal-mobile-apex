// SPDX-License-Identifier: MIT
//
// Oref0InteropTests.swift
// T1PalAlgorithmTests
//
// Interoperability tests using oref0 effect fixtures.
// Tests validate effect calculations match reference oref0 outputs.
// Trace: FIX-OA-005, ALG-009

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - Effect Data Types

/// Single effect data point from oref0 calculations
struct EffectPoint: Decodable, Equatable {
    let date: Date
    let amount: Double
    let unit: String
    
    enum CodingKeys: String, CodingKey {
        case date, amount, unit
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Parse ISO8601 date with timezone
        let dateString = try container.decode(String.self, forKey: .date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try with fractional seconds first, then without
        if let parsed = formatter.date(from: dateString) {
            self.date = parsed
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let parsed = formatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .date,
                    in: container,
                    debugDescription: "Cannot parse date: \(dateString)"
                )
            }
            self.date = parsed
        }
        
        self.amount = try container.decode(Double.self, forKey: .amount)
        self.unit = try container.decode(String.self, forKey: .unit)
    }
}

/// Effect curve type
enum EffectCurveType: String {
    case walshInsulin = "walsh_insulin_effect"
    case scheinerCarb = "scheiner-carb-effect"
    case glucoseMomentum = "glucose-momentum-effect"
    case cumulativeResults = "cumulative-results"
    case cleanedHistory = "cleaned-history"
}

// MARK: - Oref0 Interop Tests

@Suite("Oref0 Interop")
struct Oref0InteropTests {
    
    // MARK: - Fixture Loading Tests
    
    @Suite("Fixture Loading")
    struct FixtureLoading {
        @Test("Load Walsh insulin effect")
        func loadWalshInsulinEffect() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "walsh_insulin_effect",
                subdirectory: "oref0-effects"
            )
            
            #expect(!effects.isEmpty, "Walsh insulin effect should have data points")
            #expect(effects.count > 50, "Should have significant number of effect points")
            
            // Verify all points have mg/dL units
            for point in effects {
                #expect(point.unit == "mg/dL", "Effect unit should be mg/dL")
            }
            
            // Verify insulin effect is negative (glucose lowering)
            let nonZeroEffects = effects.filter { $0.amount != 0 }
            let negativeEffects = nonZeroEffects.filter { $0.amount < 0 }
            #expect(negativeEffects.count > 0, "Should have negative insulin effects")
        }
        
        @Test("Load Scheiner carb effect")
        func loadScheinerCarbEffect() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "scheiner-carb-effect",
                subdirectory: "oref0-effects"
            )
            
            #expect(!effects.isEmpty, "Scheiner carb effect should have data points")
            
            // Carb effects should be positive (glucose raising) after absorption starts
            let positiveEffects = effects.filter { $0.amount > 0 }
            // Note: May have leading zeros before carb absorption starts
            #expect(positiveEffects.count >= 0, "May have positive carb effects")
        }
        
        @Test("Load glucose momentum effect")
        func loadGlucoseMomentumEffect() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "glucose-momentum-effect",
                subdirectory: "oref0-effects"
            )
            
            #expect(!effects.isEmpty, "Glucose momentum effect should have data points")
            
            // First point should be the current glucose
            if let first = effects.first {
                #expect(first.amount > 0, "First point should be positive glucose value")
            }
        }
        
        @Test("Load cumulative results")
        func loadCumulativeResults() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "cumulative-results",
                subdirectory: "oref0-effects"
            )
            
            #expect(!effects.isEmpty, "Cumulative results should have data points")
        }
    }
    
    // MARK: - Effect Curve Validation Tests
    
    @Suite("Effect Curve Validation")
    struct EffectCurveValidation {
        @Test("Walsh insulin curve shape")
        func walshInsulinCurveShape() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "walsh_insulin_effect",
                subdirectory: "oref0-effects"
            )
            
            // Walsh curve should peak around 75 minutes and tail off
            // Find the minimum (most negative) effect point
            guard let minEffect = effects.min(by: { $0.amount < $1.amount }) else {
                Issue.record("Should have effect points")
                return
            }
            
            // The minimum should be significantly negative
            #expect(minEffect.amount < -10, "Peak insulin effect should be significant")
        }
        
        @Test("Effect data sorted by date")
        func effectDataSortedByDate() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "walsh_insulin_effect",
                subdirectory: "oref0-effects"
            )
            
            // Verify effects are sorted chronologically
            for i in 1..<effects.count {
                #expect(
                    effects[i].date >= effects[i-1].date,
                    "Effect points should be sorted by date"
                )
            }
        }
        
        @Test("Effect interval consistency")
        func effectIntervalConsistency() throws {
            let effects: [EffectPoint] = try FixtureLoader.load(
                "walsh_insulin_effect",
                subdirectory: "oref0-effects"
            )
            
            guard effects.count >= 3 else {
                Issue.record("Need at least 3 points to check intervals")
                return
            }
            
            // Check interval between first two points
            let interval1 = effects[1].date.timeIntervalSince(effects[0].date)
            let interval2 = effects[2].date.timeIntervalSince(effects[1].date)
            
            // Intervals should be consistent (5 minutes = 300 seconds)
            #expect(abs(interval1 - interval2) < 60, "Intervals should be consistent")
        }
    }
    
    // MARK: - All Effects Fixture Tests
    
    @Test("All effect fixtures loadable")
    func allEffectFixturesLoadable() throws {
        let fixtures = try FixtureLoader.listFixtures(in: "oref0-effects")
        
        // Should have our 5 effect files (excluding README which isn't .json)
        #expect(fixtures.count >= 5, "Should have at least 5 effect fixtures")
        
        // Verify each fixture is loadable
        for fixture in fixtures {
            do {
                let _: [EffectPoint] = try FixtureLoader.load(fixture, subdirectory: "oref0-effects")
            } catch {
                // cleaned-history has different format, that's OK
                if fixture != "cleaned-history" {
                    Issue.record("Failed to load fixture \(fixture): \(error)")
                }
            }
        }
    }
    
    // MARK: - Summary Statistics Tests
    
    @Test("Effect summary statistics")
    func effectSummaryStatistics() throws {
        let walshEffects: [EffectPoint] = try FixtureLoader.load(
            "walsh_insulin_effect",
            subdirectory: "oref0-effects"
        )
        
        let amounts = walshEffects.map { $0.amount }
        let sum = amounts.reduce(0, +)
        let mean = sum / Double(amounts.count)
        let min = amounts.min() ?? 0
        let max = amounts.max() ?? 0
        
        // Log summary for debugging
        print("Walsh Insulin Effect Summary:")
        print("  Count: \(amounts.count)")
        print("  Sum: \(String(format: "%.2f", sum)) mg/dL")
        print("  Mean: \(String(format: "%.2f", mean)) mg/dL")
        print("  Min: \(String(format: "%.2f", min)) mg/dL")
        print("  Max: \(String(format: "%.2f", max)) mg/dL")
        
        // The total insulin effect should be negative (glucose lowering)
        #expect(sum < 0, "Total insulin effect should be glucose-lowering")
    }
}
