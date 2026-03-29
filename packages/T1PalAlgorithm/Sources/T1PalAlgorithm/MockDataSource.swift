// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MockDataSource.swift
// T1Pal Mobile
//
// Mock implementation of AlgorithmDataSource for testing and demo
// Requirements: ALG-INPUT-009

import Foundation
import T1PalCore

// MARK: - MockDataSource

/// Mock data source for testing and demo purposes.
///
/// Provides configurable glucose patterns, dose history, and profiles
/// for algorithm validation and demo mode.
///
/// Usage:
/// ```swift
/// let mock = MockDataSource(scenario: .stable120)
/// let inputs = try await assembler.assembleInputs(using: mock)
/// ```
public final class MockDataSource: AlgorithmDataSource, @unchecked Sendable {
    
    /// Predefined glucose scenarios
    public enum GlucoseScenario: String, CaseIterable, Sendable {
        /// Stable glucose around 120 mg/dL
        case stable120
        /// Stable glucose around 100 mg/dL (in-range)
        case stable100
        /// Rising glucose (post-meal pattern)
        case rising
        /// Falling glucose (post-correction)
        case falling
        /// Low glucose (hypoglycemia)
        case hypo
        /// High glucose (hyperglycemia)
        case hyper
        /// Glucose climbing rapidly (urgent high)
        case urgentHigh
        /// Glucose dropping rapidly (urgent low)
        case urgentLow
        /// Variable glucose (poor control pattern)
        case variable
    }
    
    // MARK: - Configuration
    
    /// The glucose scenario to generate
    public var scenario: GlucoseScenario
    
    /// Custom profile (uses default if nil)
    public var customProfile: TherapyProfile?
    
    /// Custom loop settings (uses default if nil)
    public var customLoopSettings: LoopSettings?
    
    /// Number of glucose readings to generate
    public var glucoseCount: Int
    
    /// Hours of dose history to generate
    public var doseHours: Int
    
    /// Hours of carb history to generate
    public var carbHours: Int
    
    /// Whether to include IOB from recent doses
    public var includeRecentDoses: Bool
    
    /// Whether to include COB from recent carbs
    public var includeRecentCarbs: Bool
    
    /// Base timestamp for data generation (defaults to now)
    public var baseTime: Date
    
    // MARK: - Initialization
    
    public init(
        scenario: GlucoseScenario = .stable120,
        customProfile: TherapyProfile? = nil,
        customLoopSettings: LoopSettings? = nil,
        glucoseCount: Int = AlgorithmDataDefaults.glucoseCount,
        doseHours: Int = AlgorithmDataDefaults.doseHistoryHours,
        carbHours: Int = AlgorithmDataDefaults.carbHistoryHours,
        includeRecentDoses: Bool = true,
        includeRecentCarbs: Bool = true,
        baseTime: Date = Date()
    ) {
        self.scenario = scenario
        self.customProfile = customProfile
        self.customLoopSettings = customLoopSettings
        self.glucoseCount = glucoseCount
        self.doseHours = doseHours
        self.carbHours = carbHours
        self.includeRecentDoses = includeRecentDoses
        self.includeRecentCarbs = includeRecentCarbs
        self.baseTime = baseTime
    }
    
    // MARK: - AlgorithmDataSource Protocol
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        let actualCount = min(count, glucoseCount)
        return generateGlucose(count: actualCount, scenario: scenario)
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        guard includeRecentDoses else { return [] }
        return generateDoses(hours: min(hours, doseHours), scenario: scenario)
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        guard includeRecentCarbs else { return [] }
        return generateCarbs(hours: min(hours, carbHours), scenario: scenario)
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        return customProfile ?? .default
    }
    
    public func loopSettings() async throws -> LoopSettings? {
        return customLoopSettings ?? LoopSettings(
            maximumBasalRatePerHour: 4.0,
            maximumBolus: 10.0,
            minimumBGGuard: 70,
            dosingStrategy: "tempBasalOnly",
            dosingEnabled: true
        )
    }
    
    // MARK: - Data Generation
    
    private func generateGlucose(count: Int, scenario: GlucoseScenario) -> [GlucoseReading] {
        let config = scenarioConfig(scenario)
        var readings: [GlucoseReading] = []
        
        for i in 0..<count {
            let minutesAgo = i * 5
            let timestamp = baseTime.addingTimeInterval(TimeInterval(-minutesAgo * 60))
            
            // Calculate glucose value based on scenario
            let baseValue = config.baseGlucose
            let variation = config.variation * sin(Double(i) * 0.3)
            let trend = config.trendPerReading * Double(i)
            let glucose = max(40, min(400, baseValue + variation - trend))
            
            readings.append(GlucoseReading(
                glucose: glucose,
                timestamp: timestamp,
                trend: config.trend
            ))
        }
        
        return readings
    }
    
    private func generateDoses(hours: Int, scenario: GlucoseScenario) -> [InsulinDose] {
        var doses: [InsulinDose] = []
        
        // Generate hourly basal segments
        for h in 0..<hours {
            let timestamp = baseTime.addingTimeInterval(TimeInterval(-h * 3600 - 1800))
            doses.append(InsulinDose(
                units: 0.5,  // Half hour of basal at 1.0 U/hr
                timestamp: timestamp,
                type: .novolog,
                source: "mock"
            ))
        }
        
        // Add scenario-specific boluses
        switch scenario {
        case .rising, .hyper:
            // Recent meal bolus
            doses.append(InsulinDose(
                units: 4.0,
                timestamp: baseTime.addingTimeInterval(-1800),
                type: .novolog,
                source: "mock"
            ))
        case .falling:
            // Correction bolus
            doses.append(InsulinDose(
                units: 2.0,
                timestamp: baseTime.addingTimeInterval(-3600),
                type: .novolog,
                source: "mock"
            ))
        default:
            break
        }
        
        return doses.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func generateCarbs(hours: Int, scenario: GlucoseScenario) -> [CarbEntry] {
        var carbs: [CarbEntry] = []
        
        switch scenario {
        case .rising, .hyper:
            // Recent meal
            carbs.append(CarbEntry(
                grams: 45,
                timestamp: baseTime.addingTimeInterval(-1800),
                absorptionType: .medium,
                source: "mock"
            ))
        case .variable:
            // Multiple meals
            carbs.append(CarbEntry(
                grams: 30,
                timestamp: baseTime.addingTimeInterval(-7200),
                absorptionType: .fast,
                source: "mock"
            ))
            carbs.append(CarbEntry(
                grams: 60,
                timestamp: baseTime.addingTimeInterval(-14400),
                absorptionType: .slow,
                source: "mock"
            ))
        default:
            break
        }
        
        return carbs.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Scenario Configuration
    
    private struct ScenarioConfig {
        let baseGlucose: Double
        let variation: Double
        let trendPerReading: Double
        let trend: GlucoseTrend
    }
    
    private func scenarioConfig(_ scenario: GlucoseScenario) -> ScenarioConfig {
        switch scenario {
        case .stable120:
            return ScenarioConfig(baseGlucose: 120, variation: 5, trendPerReading: 0, trend: .flat)
        case .stable100:
            return ScenarioConfig(baseGlucose: 100, variation: 3, trendPerReading: 0, trend: .flat)
        case .rising:
            return ScenarioConfig(baseGlucose: 140, variation: 5, trendPerReading: -2, trend: .singleUp)
        case .falling:
            return ScenarioConfig(baseGlucose: 110, variation: 5, trendPerReading: 2, trend: .singleDown)
        case .hypo:
            return ScenarioConfig(baseGlucose: 65, variation: 3, trendPerReading: 0, trend: .flat)
        case .hyper:
            return ScenarioConfig(baseGlucose: 250, variation: 10, trendPerReading: 0, trend: .flat)
        case .urgentHigh:
            return ScenarioConfig(baseGlucose: 280, variation: 5, trendPerReading: -3, trend: .doubleUp)
        case .urgentLow:
            return ScenarioConfig(baseGlucose: 60, variation: 3, trendPerReading: 2, trend: .doubleDown)
        case .variable:
            return ScenarioConfig(baseGlucose: 150, variation: 30, trendPerReading: 0, trend: .flat)
        }
    }
}

// MARK: - Convenience Initializers

public extension MockDataSource {
    
    /// Create a mock for stable in-range glucose
    static func inRange() -> MockDataSource {
        MockDataSource(scenario: .stable100)
    }
    
    /// Create a mock for hypoglycemia testing
    static func hypoglycemia() -> MockDataSource {
        MockDataSource(scenario: .hypo)
    }
    
    /// Create a mock for hyperglycemia testing
    static func hyperglycemia() -> MockDataSource {
        MockDataSource(scenario: .hyper)
    }
    
    /// Create a mock for post-meal rise
    static func postMeal() -> MockDataSource {
        MockDataSource(scenario: .rising)
    }
    
    /// Create a mock with custom profile
    static func withProfile(_ profile: TherapyProfile) -> MockDataSource {
        MockDataSource(customProfile: profile)
    }
}
