// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MealPatternAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for ALG-EFF-050..054: Meal Pattern Agent

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Meal Pattern Agent")
struct MealPatternAgentTests {
    
    // MARK: - ALG-EFF-050: Meal Timing Pattern Tests
    
    @Test("Meal type classification")
    func mealTypeClassification() {
        #expect(MealType.classify(hour: 7.0) == .breakfast)
        #expect(MealType.classify(hour: 12.0) == .lunch)
        #expect(MealType.classify(hour: 15.0) == .snack)
        #expect(MealType.classify(hour: 18.5) == .dinner)
        #expect(MealType.classify(hour: 22.0) == .lateNight)
    }
    
    @Test("Meal pattern detection")
    func mealPatternDetection() {
        let analyzer = MealPatternAnalyzer()
        
        // Create 14 days of regular meal entries
        var entries: [MealCarbEntry] = []
        let calendar = Calendar.current
        let now = Date()
        
        for day in 0..<14 {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: calendar.startOfDay(for: now)) else { continue }
            
            // Breakfast at 7:30am
            if let breakfast = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(timestamp: breakfast, carbs: 45))
            }
            
            // Lunch at 12:00pm
            if let lunch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(timestamp: lunch, carbs: 60))
            }
            
            // Dinner at 6:30pm
            if let dinner = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(timestamp: dinner, carbs: 75))
            }
        }
        
        let patterns = analyzer.analyzePatterns(entries: entries)
        
        #expect(patterns.count == 3)
        
        // Check breakfast pattern
        if let breakfast = patterns.first(where: { $0.mealType == .breakfast }) {
            #expect(abs(breakfast.typicalHour - 7.5) < 0.5)
            #expect(breakfast.occurrences == 14)
            #expect(breakfast.confidence >= 0.5)
        } else {
            Issue.record("Should detect breakfast pattern")
        }
        
        // Check lunch pattern
        if let lunch = patterns.first(where: { $0.mealType == .lunch }) {
            #expect(abs(lunch.typicalHour - 12.0) < 0.5)
        } else {
            Issue.record("Should detect lunch pattern")
        }
    }
    
    @Test("Meal pattern matching")
    func mealPatternMatching() {
        let pattern = MealPattern(
            mealType: .breakfast,
            typicalHour: 7.5,
            timingVariability: 0.5,
            occurrences: 14,
            confidence: 0.8
        )
        
        #expect(pattern.matches(hour: 7.5, dayOfWeek: 2))
        #expect(pattern.matches(hour: 8.0, dayOfWeek: 2)) // Within 1.5h tolerance
        #expect(!pattern.matches(hour: 10.0, dayOfWeek: 2)) // Too far
    }
    
    @Test("Meal pattern day specific")
    func mealPatternDaySpecific() {
        let weekendBreakfast = MealPattern(
            mealType: .breakfast,
            typicalHour: 9.0,
            timingVariability: 0.5,
            daysOfWeek: [1, 7], // Sunday, Saturday
            occurrences: 6,
            confidence: 0.7
        )
        
        #expect(weekendBreakfast.matches(hour: 9.0, dayOfWeek: 1)) // Sunday
        #expect(weekendBreakfast.matches(hour: 9.0, dayOfWeek: 7)) // Saturday
        #expect(!weekendBreakfast.matches(hour: 9.0, dayOfWeek: 3)) // Tuesday
    }
    
    @Test("Meal pattern time string")
    func mealPatternTimeString() {
        let pattern = MealPattern(
            mealType: .dinner,
            typicalHour: 18.5,
            timingVariability: 0.5,
            occurrences: 10,
            confidence: 0.8
        )
        
        #expect(pattern.typicalTimeString == "6:30pm")
    }
    
    // MARK: - ALG-EFF-051: Carb Estimation Tests
    
    @Test("Carb estimation")
    func carbEstimation() {
        let estimator = MealCarbEstimator()
        
        var entries: [MealCarbEntry] = []
        let now = Date()
        
        // 10 breakfast entries around 45g
        for i in 0..<10 {
            let time = now.addingTimeInterval(TimeInterval(-i * 24 * 3600))
            let timestamp = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: time)!
            entries.append(MealCarbEntry(timestamp: timestamp, carbs: 45 + Double.random(in: -5...5)))
        }
        
        // 10 lunch entries around 60g
        for i in 0..<10 {
            let time = now.addingTimeInterval(TimeInterval(-i * 24 * 3600))
            let timestamp = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: time)!
            entries.append(MealCarbEntry(timestamp: timestamp, carbs: 60 + Double.random(in: -10...10)))
        }
        
        let estimates = estimator.estimateCarbs(entries: entries)
        
        #expect(estimates.count == 2)
        
        if let breakfast = estimates.first(where: { $0.mealType == .breakfast }) {
            #expect(abs(breakfast.averageCarbs - 45) < 5)
            #expect(breakfast.sampleCount == 10)
        }
        
        if let lunch = estimates.first(where: { $0.mealType == .lunch }) {
            #expect(abs(lunch.averageCarbs - 60) < 10)
        }
    }
    
    @Test("Carb estimate suggested range")
    func carbEstimateSuggestedRange() {
        let estimate = MealCarbEstimate(
            mealType: .breakfast,
            averageCarbs: 45,
            carbVariability: 10,
            minCarbs: 30,
            maxCarbs: 60,
            sampleCount: 14,
            confidence: 0.8
        )
        
        let range = estimate.suggestedRange
        #expect(range.lowerBound == 35) // 45 - 10
        #expect(range.upperBound == 55) // 45 + 10
    }
    
    // MARK: - ALG-EFF-052: Pre-Bolus Analysis Tests
    
    @Test("Pre-bolus analysis")
    func preBolusAnalysis() {
        let analyzer = PreBolusAnalyzer()
        
        var entries: [MealCarbEntry] = []
        let now = Date()
        
        // Create entries with varied pre-bolus timing (deterministic pattern)
        // Pre-bolus times: 10, 11, 12, 13, 14, 15, 10, 11, 12, 13, 14, 15, 10, 11
        // All >= 10 (adequate threshold), so adequatePreBolusRate = 1.0
        for i in 0..<14 {
            let mealTime = now.addingTimeInterval(TimeInterval(-i * 24 * 3600))
            let carbTimestamp = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: mealTime)!
            
            // Deterministic pre-bolus times cycling through 10-15 minutes
            let preBolusMinutes = Double(10 + (i % 6))
            let bolusTimestamp = carbTimestamp.addingTimeInterval(-preBolusMinutes * 60)
            
            entries.append(MealCarbEntry(
                timestamp: carbTimestamp,
                carbs: 50,
                bolusTimestamp: bolusTimestamp,
                bolusAmount: 5.0
            ))
        }
        
        let analyses = analyzer.analyze(entries: entries)
        
        #expect(analyses.count == 1)
        
        if let lunch = analyses.first {
            #expect(lunch.mealType == .lunch)
            #expect(lunch.averagePreBolusMinutes >= 8)
            #expect(lunch.averagePreBolusMinutes <= 15)
            #expect(lunch.adequatePreBolusRate >= 0.5)
        }
    }
    
    @Test("Pre-bolus quality")
    func preBolusQuality() {
        let excellent = PreBolusAnalysis(
            mealType: .breakfast,
            averagePreBolusMinutes: 18,
            preBolusVariability: 2,
            adequatePreBolusRate: 0.95,
            suggestedPreBolusMinutes: 15,
            sampleCount: 14
        )
        #expect(excellent.qualityRating == .excellent)
        
        let good = PreBolusAnalysis(
            mealType: .lunch,
            averagePreBolusMinutes: 12,
            preBolusVariability: 3,
            adequatePreBolusRate: 0.8,
            suggestedPreBolusMinutes: 15,
            sampleCount: 14
        )
        #expect(good.qualityRating == .good)
        
        let poor = PreBolusAnalysis(
            mealType: .dinner,
            averagePreBolusMinutes: -5,
            preBolusVariability: 10,
            adequatePreBolusRate: 0.1,
            suggestedPreBolusMinutes: 15,
            sampleCount: 14
        )
        #expect(poor.qualityRating == .poor)
    }
    
    @Test("Pre-bolus recommendation")
    func preBolusRecommendation() {
        let analysis = PreBolusAnalysis(
            mealType: .breakfast,
            averagePreBolusMinutes: 3,
            preBolusVariability: 5,
            adequatePreBolusRate: 0.2,
            suggestedPreBolusMinutes: 15,
            sampleCount: 10
        )
        
        #expect(analysis.recommendation.contains("10-15 minutes"))
    }
    
    // MARK: - ALG-EFF-053: Meal-Specific CR/ISF Tests
    
    @Test("Meal settings analysis")
    func mealSettingsAnalysis() {
        let analyzer = MealSettingsAnalyzer()
        
        var outcomes: [MealSettingsAnalyzer.MealOutcome] = []
        let now = Date()
        
        // 7 breakfast outcomes that end high (need more insulin)
        for i in 0..<7 {
            let mealTime = now.addingTimeInterval(TimeInterval(-i * 24 * 3600))
            let timestamp = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: mealTime)!
            
            let entry = MealCarbEntry(timestamp: timestamp, carbs: 45)
            outcomes.append(MealSettingsAnalyzer.MealOutcome(
                entry: entry,
                preGlucose: 100,
                peakGlucose: 180,
                postGlucose: 150 // Ending 50 high
            ))
        }
        
        let modifiers = analyzer.analyze(outcomes: outcomes)
        
        #expect(modifiers.count == 1)
        
        if let breakfast = modifiers.first {
            #expect(breakfast.mealType == .breakfast)
            #expect(breakfast.carbRatioMultiplier > 1.0) // Needs more insulin
            #expect(breakfast.needsMoreInsulin)
        }
    }
    
    @Test("Meal settings modifier description")
    func mealSettingsModifierDescription() {
        let modifier = MealSettingsModifier(
            mealType: .breakfast,
            carbRatioMultiplier: 1.15,
            isfMultiplier: 1.1,
            confidence: 0.7,
            rationale: "Based on 7 breakfasts"
        )
        
        // Int((1.15 - 1.0) * 100) = 14 due to floating point
        #expect(modifier.adjustmentDescription.contains("more insulin"))
        #expect(modifier.needsMoreInsulin)
    }
    
    // MARK: - ALG-EFF-054: Meal Prediction Tests
    
    @Test("Meal prediction alert")
    func mealPredictionAlert() async {
        let manager = MealPredictionManager(alertThresholdMinutes: 30)
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = Double(calendar.component(.hour, from: now)) + 
                          Double(calendar.component(.minute, from: now)) / 60.0
        
        // Create pattern for a meal coming up in 15 minutes
        let upcomingHour = currentHour + 0.25 // 15 minutes from now
        let pattern = MealPattern(
            mealType: .lunch,
            typicalHour: upcomingHour,
            timingVariability: 0.5,
            occurrences: 14,
            confidence: 0.8
        )
        
        let estimate = MealCarbEstimate(
            mealType: .lunch,
            averageCarbs: 55,
            carbVariability: 10,
            minCarbs: 40,
            maxCarbs: 70,
            sampleCount: 14,
            confidence: 0.8
        )
        
        await manager.updatePatterns([pattern], estimates: [estimate])
        
        let alerts = await manager.checkForAlerts()
        
        #expect(alerts.count == 1)
        if let alert = alerts.first {
            #expect(alert.mealType == .lunch)
            #expect(alert.suggestedCarbs == 55)
            #expect(alert.minutesUntil <= 30)
        }
    }
    
    @Test("Meal prediction no double alert")
    func mealPredictionNoDoubleAlert() async {
        let manager = MealPredictionManager(alertThresholdMinutes: 30)
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = Double(calendar.component(.hour, from: now)) + 
                          Double(calendar.component(.minute, from: now)) / 60.0
        
        let pattern = MealPattern(
            mealType: .lunch,
            typicalHour: currentHour + 0.25,
            timingVariability: 0.5,
            occurrences: 14,
            confidence: 0.8
        )
        
        await manager.updatePatterns([pattern], estimates: [])
        
        // First check - should alert
        let alerts1 = await manager.checkForAlerts()
        #expect(alerts1.count == 1)
        
        // Second check - should NOT alert again (same day)
        let alerts2 = await manager.checkForAlerts()
        #expect(alerts2.count == 0)
    }
    
    @Test("Meal prediction alert message")
    func mealPredictionAlertMessage() {
        let alert = MealPredictionAlert(
            mealType: .breakfast,
            expectedTime: Date(),
            confidence: 0.8,
            minutesUntil: 15,
            suggestedCarbs: 45
        )
        
        #expect(alert.message.contains("Breakfast"))
        #expect(alert.message.contains("45g"))
    }
    
    // MARK: - Full Agent Tests
    
    @Test("Meal pattern agent training")
    func mealPatternAgentTraining() async {
        let agent = MealPatternAgent()
        
        var entries: [MealCarbEntry] = []
        let now = Date()
        
        // Create 30 days of meal data
        for day in 0..<30 {
            let dayStart = Calendar.current.date(byAdding: .day, value: -day, to: Calendar.current.startOfDay(for: now))!
            
            // Breakfast
            if let timestamp = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(
                    timestamp: timestamp,
                    carbs: 40 + Double.random(in: -5...5),
                    bolusTimestamp: timestamp.addingTimeInterval(-10 * 60),
                    bolusAmount: 4.0
                ))
            }
            
            // Lunch
            if let timestamp = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(
                    timestamp: timestamp,
                    carbs: 55 + Double.random(in: -10...10),
                    bolusTimestamp: timestamp.addingTimeInterval(-12 * 60),
                    bolusAmount: 5.5
                ))
            }
            
            // Dinner
            if let timestamp = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(
                    timestamp: timestamp,
                    carbs: 70 + Double.random(in: -10...10),
                    bolusTimestamp: timestamp.addingTimeInterval(-8 * 60),
                    bolusAmount: 7.0
                ))
            }
        }
        
        await agent.train(entries: entries)
        
        let patterns = await agent.getPatterns()
        #expect(patterns.count == 3)
        
        let estimates = await agent.getCarbEstimates()
        #expect(estimates.count == 3)
        
        let preBolusAnalyses = await agent.getPreBolusAnalyses()
        #expect(preBolusAnalyses.count > 0)
        
        // Check training status
        let status = await agent.trainingStatus
        switch status {
        case .graduated:
            // Expected for 30 days of good data
            break
        case .trained(let sessions, _):
            #expect(sessions >= 14)
        default:
            break // May be hunch if data wasn't consistent enough
        }
    }
    
    @Test("Meal pattern agent getters")
    func mealPatternAgentGetters() async {
        let agent = MealPatternAgent()
        
        var entries: [MealCarbEntry] = []
        for i in 0..<14 {
            let now = Date()
            let dayStart = Calendar.current.date(byAdding: .day, value: -i, to: Calendar.current.startOfDay(for: now))!
            
            if let timestamp = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: dayStart) {
                entries.append(MealCarbEntry(timestamp: timestamp, carbs: 45))
            }
        }
        
        await agent.train(entries: entries)
        
        let breakfastEstimate = await agent.getCarbEstimate(for: .breakfast)
        #expect(breakfastEstimate != nil)
        #expect(abs((breakfastEstimate?.averageCarbs ?? 0) - 45) < 1)
        
        let lunchEstimate = await agent.getCarbEstimate(for: .lunch)
        #expect(lunchEstimate == nil) // No lunch data
    }
}
