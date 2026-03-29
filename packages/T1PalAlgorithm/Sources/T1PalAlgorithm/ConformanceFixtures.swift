// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ConformanceFixtures.swift
// T1Pal Mobile
//
// Pre-built RecordedDeviceState fixtures for conformance testing
// Requirements: ALG-INPUT-019l
//
// Provides realistic scenarios for validating that CLI and AID paths
// produce identical algorithm inputs.

import Foundation
import T1PalCore

// MARK: - Conformance Fixture Collection (ALG-INPUT-019l)

/// Collection of pre-built RecordedDeviceState fixtures for conformance testing.
///
/// Each fixture represents a realistic diabetes management scenario with
/// complete device state (glucose, doses, carbs, profile, settings).
///
/// Usage:
/// ```swift
/// let fixture = ConformanceFixtures.stableOvernight
/// let cliAdapter = RecordedStateDataSource(state: fixture)
/// let aidAdapter = RecordedStateDirectDataSource(state: fixture)
/// // Compare inputs from both paths
/// ```
public enum ConformanceFixtures {
    
    // MARK: - Standard Therapy Profile
    
    /// Standard therapy profile used across fixtures
    public static let standardProfile = TherapyProfile(
        basalRates: [
            BasalRate(startTime: 0, rate: 0.8),        // Midnight
            BasalRate(startTime: 21600, rate: 1.0),   // 6 AM
            BasalRate(startTime: 43200, rate: 0.9),   // Noon
            BasalRate(startTime: 64800, rate: 0.85)   // 6 PM
        ],
        carbRatios: [
            CarbRatio(startTime: 0, ratio: 12),       // Midnight
            CarbRatio(startTime: 21600, ratio: 10),   // 6 AM (breakfast)
            CarbRatio(startTime: 43200, ratio: 12),   // Noon
            CarbRatio(startTime: 64800, ratio: 14)    // 6 PM
        ],
        sensitivityFactors: [
            SensitivityFactor(startTime: 0, factor: 50),    // Midnight
            SensitivityFactor(startTime: 21600, factor: 45), // 6 AM
            SensitivityFactor(startTime: 43200, factor: 50), // Noon
            SensitivityFactor(startTime: 64800, factor: 55)  // 6 PM
        ],
        targetGlucose: TargetRange(low: 100, high: 110)
    )
    
    /// Standard Loop settings
    public static let standardSettings = LoopSettings(
        maximumBasalRatePerHour: 4.0,
        maximumBolus: 10.0,
        minimumBGGuard: 70.0,
        dosingStrategy: "automaticBolus",
        dosingEnabled: true
    )
    
    // MARK: - Fixture 1: Stable Overnight
    
    /// Stable glucose overnight with minimal insulin activity.
    ///
    /// Scenario: Patient sleeping, glucose stable around 110 mg/dL,
    /// basal delivery only, no carbs or boluses in last 6 hours.
    ///
    /// Expected: Low IOB (~0.5U from basal), zero COB
    public static var stableOvernight: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 3, minute: 0) // 3 AM
        
        // 3 hours of stable glucose readings (every 5 min = 36 readings)
        let glucose = (0..<36).map { i in
            GlucoseReading(
                glucose: 108 + Double.random(in: -3...3),
                timestamp: baseTime.addingTimeInterval(Double(-i * 300)),
                trend: .flat
            )
        }
        
        // Only basal temp basals (representing scheduled basal)
        let doses = (0..<6).map { i in
            InsulinDose(
                units: 0.4, // 30-min scheduled basal at 0.8 U/hr
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            )
        }
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "stable_overnight",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: [],
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 0.5,
            expectedCOB: 0.0
        )
    }
    
    // MARK: - Fixture 2: Post-Meal Rise
    
    /// Post-breakfast glucose rise with meal bolus.
    ///
    /// Scenario: 45g carb breakfast at 7:30 AM, 4.5U bolus,
    /// glucose rising from 95 to 145 mg/dL over 90 minutes.
    ///
    /// Expected: Active IOB (~3.5U), active COB (~25g)
    public static var postMealRise: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 9, minute: 0) // 9 AM
        let mealTime = baseTime.addingTimeInterval(-5400) // 7:30 AM (90 min ago)
        
        // Glucose rising pattern
        let glucose = (0..<36).map { i -> GlucoseReading in
            let minutesAgo = i * 5
            let glucoseValue: Double
            if minutesAgo < 90 {
                // Rising after meal
                glucoseValue = 145 - Double(minutesAgo) * 0.5 + Double.random(in: -2...2)
            } else {
                // Before meal
                glucoseValue = 95 + Double.random(in: -2...2)
            }
            return GlucoseReading(
                glucose: max(80, min(180, glucoseValue)),
                timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
                trend: minutesAgo < 30 ? .singleUp : (minutesAgo < 60 ? .fortyFiveUp : .flat)
            )
        }
        
        // Meal bolus + basal
        var doses: [InsulinDose] = []
        doses.append(InsulinDose(
            units: 4.5,
            timestamp: mealTime,
            type: .novolog,
            source: "bolus"
        ))
        // Basal segments
        for i in 0..<6 {
            doses.append(InsulinDose(
                units: 0.5,
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            ))
        }
        
        // Breakfast carbs
        let carbs = [
            CarbEntry(grams: 45, timestamp: mealTime, absorptionTime: 10800) // 3hr absorption
        ]
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "post_meal_rise",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: carbs,
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 3.5,
            expectedCOB: 25.0
        )
    }
    
    // MARK: - Fixture 3: Exercise-Induced Low
    
    /// Glucose dropping during/after exercise.
    ///
    /// Scenario: Morning run at 6:30 AM, glucose dropping from 120 to 75 mg/dL,
    /// temp basal reduced to 0, no recent boluses.
    ///
    /// Expected: Very low IOB (<0.3U), zero COB
    public static var exerciseLow: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 7, minute: 30) // 7:30 AM
        
        // Glucose dropping pattern
        let glucose = (0..<24).map { i -> GlucoseReading in
            let minutesAgo = i * 5
            let glucoseValue: Double
            if minutesAgo < 60 {
                // Dropping during exercise
                glucoseValue = 75 + Double(minutesAgo) * 0.75
            } else {
                // Before exercise
                glucoseValue = 120 + Double.random(in: -3...3)
            }
            return GlucoseReading(
                glucose: max(70, glucoseValue),
                timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
                trend: minutesAgo < 30 ? .singleDown : (minutesAgo < 45 ? .fortyFiveDown : .flat)
            )
        }
        
        // Zero temp basal during exercise, minimal basal before
        var doses: [InsulinDose] = []
        // Zero temp for last hour
        doses.append(InsulinDose(
            units: 0.0,
            timestamp: baseTime.addingTimeInterval(-3600),
            type: .novolog,
            source: "tempBasal"
        ))
        // Normal basal before that
        for i in 2..<6 {
            doses.append(InsulinDose(
                units: 0.5,
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            ))
        }
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "exercise_low",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: [],
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 0.2,
            expectedCOB: 0.0
        )
    }
    
    // MARK: - Fixture 4: Missed Bolus (High Glucose)
    
    /// High glucose from forgotten meal bolus.
    ///
    /// Scenario: Ate lunch (60g carbs) but forgot bolus, glucose rising
    /// from 110 to 220 mg/dL over 2 hours.
    ///
    /// Expected: Low IOB (basal only), high COB (~40g)
    public static var missedBolus: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 14, minute: 0) // 2 PM
        let mealTime = baseTime.addingTimeInterval(-7200) // Noon (2 hours ago)
        
        // High and rising glucose
        let glucose = (0..<36).map { i -> GlucoseReading in
            let minutesAgo = i * 5
            let glucoseValue: Double
            if minutesAgo < 120 {
                // Rising after unbolused meal
                glucoseValue = 220 - Double(minutesAgo) * 0.9
            } else {
                // Before meal
                glucoseValue = 110 + Double.random(in: -3...3)
            }
            return GlucoseReading(
                glucose: min(250, max(100, glucoseValue)),
                timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
                trend: minutesAgo < 45 ? .doubleUp : (minutesAgo < 90 ? .singleUp : .flat)
            )
        }
        
        // Only basal, no bolus
        let doses = (0..<8).map { i in
            InsulinDose(
                units: 0.45,
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            )
        }
        
        // Unbolused meal
        let carbs = [
            CarbEntry(grams: 60, timestamp: mealTime, absorptionTime: 10800)
        ]
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "missed_bolus",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: carbs,
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 0.8,
            expectedCOB: 40.0
        )
    }
    
    // MARK: - Fixture 5: Stacking Boluses
    
    /// Multiple correction boluses stacking, risk of low.
    ///
    /// Scenario: Patient corrected high twice within 90 minutes,
    /// now has significant IOB and glucose is dropping fast.
    ///
    /// Expected: High IOB (~5U), moderate COB
    public static var stackingBoluses: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 16, minute: 0) // 4 PM
        
        // Glucose now dropping after stacked corrections
        let glucose = (0..<24).map { i -> GlucoseReading in
            let minutesAgo = i * 5
            let glucoseValue: Double
            switch minutesAgo {
            case 0..<30:
                glucoseValue = 130 + Double(minutesAgo) * 2 // Dropping
            case 30..<60:
                glucoseValue = 190 + Double.random(in: -3...3) // Plateau
            case 60..<90:
                glucoseValue = 210 - Double(minutesAgo - 60) * 0.5 // After 2nd correction
            default:
                glucoseValue = 200 + Double.random(in: -5...5)
            }
            return GlucoseReading(
                glucose: max(100, min(250, glucoseValue)),
                timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
                trend: minutesAgo < 20 ? .doubleDown : (minutesAgo < 45 ? .singleDown : .flat)
            )
        }
        
        // Two stacked correction boluses
        var doses: [InsulinDose] = []
        // Correction 1 (30 min ago)
        doses.append(InsulinDose(
            units: 2.5,
            timestamp: baseTime.addingTimeInterval(-1800),
            type: .novolog,
            source: "bolus"
        ))
        // Correction 2 (90 min ago)
        doses.append(InsulinDose(
            units: 3.0,
            timestamp: baseTime.addingTimeInterval(-5400),
            type: .novolog,
            source: "bolus"
        ))
        // Basal
        for i in 0..<6 {
            doses.append(InsulinDose(
                units: 0.45,
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            ))
        }
        
        // Small snack eaten with first correction
        let carbs = [
            CarbEntry(grams: 15, timestamp: baseTime.addingTimeInterval(-5400), absorptionTime: 7200)
        ]
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "stacking_boluses",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: carbs,
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 5.0,
            expectedCOB: 8.0
        )
    }
    
    // MARK: - Fixture 6: Dawn Phenomenon
    
    /// Early morning glucose rise (dawn phenomenon).
    ///
    /// Scenario: Glucose rising from 100 to 140 between 4-6 AM,
    /// no food, insulin sensitivity decreased.
    ///
    /// Expected: Moderate IOB from increased basal, zero COB
    public static var dawnPhenomenon: RecordedDeviceState {
        let baseTime = createBaseTime(hour: 6, minute: 0) // 6 AM
        
        // Rising glucose pattern typical of dawn phenomenon
        let glucose = (0..<36).map { i -> GlucoseReading in
            let minutesAgo = i * 5
            let glucoseValue: Double
            if minutesAgo < 120 {
                // Rising (dawn phenomenon)
                glucoseValue = 140 - Double(minutesAgo) * 0.33
            } else {
                // Stable overnight before
                glucoseValue = 100 + Double.random(in: -3...3)
            }
            return GlucoseReading(
                glucose: glucoseValue,
                timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
                trend: minutesAgo < 60 ? .fortyFiveUp : .flat
            )
        }
        
        // Increased temp basals in response
        var doses: [InsulinDose] = []
        // Recent high temp basals
        for i in 0..<4 {
            doses.append(InsulinDose(
                units: 0.75, // 1.5 U/hr
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "tempBasal"
            ))
        }
        // Earlier normal basal
        for i in 4..<8 {
            doses.append(InsulinDose(
                units: 0.4,
                timestamp: baseTime.addingTimeInterval(Double(-i * 1800)),
                type: .novolog,
                source: "basal"
            ))
        }
        
        return RecordedDeviceState(
            timestamp: baseTime,
            scenario: "dawn_phenomenon",
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: [],
            profile: standardProfile,
            loopSettings: standardSettings,
            expectedIOB: 1.2,
            expectedCOB: 0.0
        )
    }
    
    // MARK: - All Fixtures
    
    /// All available conformance fixtures
    public static var all: [RecordedDeviceState] {
        [
            stableOvernight,
            postMealRise,
            exerciseLow,
            missedBolus,
            stackingBoluses,
            dawnPhenomenon
        ]
    }
    
    /// Get fixture by scenario name
    public static func fixture(named scenario: String) -> RecordedDeviceState? {
        all.first { $0.scenario == scenario }
    }
    
    // MARK: - Helpers
    
    /// Create a base time at a specific hour/minute today
    private static func createBaseTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Fixture Validation

public extension ConformanceFixtures {
    
    /// Validate that a fixture has all required data
    static func validate(_ fixture: RecordedDeviceState) -> [String] {
        var issues: [String] = []
        
        if fixture.glucoseReadings.isEmpty {
            issues.append("No glucose readings")
        }
        if fixture.glucoseReadings.count < 12 {
            issues.append("Fewer than 12 glucose readings (need 1 hour minimum)")
        }
        if fixture.profile.basalRates.isEmpty {
            issues.append("No basal rates in profile")
        }
        if fixture.profile.carbRatios.isEmpty {
            issues.append("No carb ratios in profile")
        }
        if fixture.profile.sensitivityFactors.isEmpty {
            issues.append("No sensitivity factors in profile")
        }
        
        return issues
    }
    
    /// Validate all fixtures
    static func validateAll() -> [(String, [String])] {
        all.map { ($0.scenario, validate($0)) }
    }
}
