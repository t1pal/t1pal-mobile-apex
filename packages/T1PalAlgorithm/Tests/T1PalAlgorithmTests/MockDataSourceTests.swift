// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MockDataSourceTests.swift
// T1Pal Mobile
//
// Tests for MockDataSource
// Requirements: ALG-INPUT-009

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("MockDataSource")
struct MockDataSourceTests {
    
    // MARK: - Scenario Tests
    
    @Suite("Scenarios")
    struct Scenarios {
        @Test("Stable 120 scenario")
        func stable120Scenario() async throws {
            let mock = MockDataSource(scenario: .stable120)
            let glucose = try await mock.glucoseHistory(count: 12)
            
            #expect(glucose.count == 12)
            
            // Should be around 120 with small variation
            let values = glucose.map { $0.glucose }
            let avg = values.reduce(0, +) / Double(values.count)
            #expect(abs(avg - 120) < 10)
            
            // Trend should be flat
            #expect(glucose.first?.trend == .flat)
        }
        
        @Test("Hypo scenario")
        func hypoScenario() async throws {
            let mock = MockDataSource(scenario: .hypo)
            let glucose = try await mock.glucoseHistory(count: 6)
            
            // Should be low
            let values = glucose.map { $0.glucose }
            #expect(values.allSatisfy { $0 < 80 })
        }
        
        @Test("Hyper scenario")
        func hyperScenario() async throws {
            let mock = MockDataSource(scenario: .hyper)
            let glucose = try await mock.glucoseHistory(count: 6)
            
            // Should be high
            let values = glucose.map { $0.glucose }
            #expect(values.allSatisfy { $0 > 200 })
        }
        
        @Test("Rising scenario")
        func risingScenario() async throws {
            let mock = MockDataSource(scenario: .rising)
            let glucose = try await mock.glucoseHistory(count: 6)
            
            // Trend should be up
            #expect(glucose.first?.trend == .singleUp)
            
            // Should include meal carbs
            let carbs = try await mock.carbHistory(hours: 2)
            #expect(!carbs.isEmpty)
        }
        
        @Test("Falling scenario")
        func fallingScenario() async throws {
            let mock = MockDataSource(scenario: .falling)
            let glucose = try await mock.glucoseHistory(count: 6)
            
            // Trend should be down
            #expect(glucose.first?.trend == .singleDown)
        }
    }
    
    // MARK: - Configuration Tests
    
    @Suite("Configuration")
    struct Configuration {
        @Test("Custom profile")
        func customProfile() async throws {
            let customProfile = TherapyProfile(
                basalRates: [BasalRate(startTime: 0, rate: 2.0)],
                carbRatios: [CarbRatio(startTime: 0, ratio: 8)],
                sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 40)],
                targetGlucose: TargetRange(low: 90, high: 100)
            )
            
            let mock = MockDataSource(customProfile: customProfile)
            let profile = try await mock.currentProfile()
            
            #expect(profile.basalRates.first?.rate == 2.0)
            #expect(profile.carbRatios.first?.ratio == 8)
        }
        
        @Test("Custom Loop settings")
        func customLoopSettings() async throws {
            let settings = LoopSettings(
                maximumBasalRatePerHour: 6.0,
                maximumBolus: 15.0,
                dosingStrategy: "automaticBolus"
            )
            
            let mock = MockDataSource(customLoopSettings: settings)
            let loopSettings = try await mock.loopSettings()
            
            #expect(loopSettings?.maximumBasalRatePerHour == 6.0)
            #expect(loopSettings?.dosingStrategy == "automaticBolus")
        }
        
        @Test("Disable doses")
        func disableDoses() async throws {
            let mock = MockDataSource(includeRecentDoses: false)
            let doses = try await mock.doseHistory(hours: 6)
            
            #expect(doses.isEmpty)
        }
        
        @Test("Disable carbs")
        func disableCarbs() async throws {
            let mock = MockDataSource(scenario: .rising, includeRecentCarbs: false)
            let carbs = try await mock.carbHistory(hours: 6)
            
            #expect(carbs.isEmpty)
        }
    }
    
    // MARK: - Convenience Initializer Tests
    
    @Suite("Convenience Initializers")
    struct ConvenienceInitializers {
        @Test("In range convenience")
        func inRangeConvenience() async throws {
            let mock = MockDataSource.inRange()
            let glucose = try await mock.glucoseHistory(count: 6)
            
            let avg = glucose.map { $0.glucose }.reduce(0, +) / 6.0
            #expect(abs(avg - 100) < 10)
        }
        
        @Test("Hypoglycemia convenience")
        func hypoglycemiaConvenience() async throws {
            let mock = MockDataSource.hypoglycemia()
            let glucose = try await mock.glucoseHistory(count: 6)
            
            #expect(glucose.allSatisfy { $0.glucose < 80 })
        }
        
        @Test("Post meal convenience")
        func postMealConvenience() async throws {
            let mock = MockDataSource.postMeal()
            let glucose = try await mock.glucoseHistory(count: 6)
            
            #expect(glucose.first?.trend == .singleUp)
        }
    }
    
    // MARK: - All Scenarios Test
    
    @Test("All scenarios generate data", arguments: MockDataSource.GlucoseScenario.allCases)
    func allScenariosGenerateData(scenario: MockDataSource.GlucoseScenario) async throws {
        let mock = MockDataSource(scenario: scenario)
        
        let glucose = try await mock.glucoseHistory(count: 12)
        #expect(glucose.count == 12, "Scenario \(scenario) should generate 12 readings")
        
        let profile = try await mock.currentProfile()
        #expect(!profile.basalRates.isEmpty, "Scenario \(scenario) should have profile")
    }
}
