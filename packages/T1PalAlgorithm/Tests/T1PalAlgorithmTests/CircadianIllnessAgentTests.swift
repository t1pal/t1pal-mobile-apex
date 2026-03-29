// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CircadianIllnessAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for ALG-EFF-030..034: Circadian & Illness Agents

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Circadian & Illness Agents")
struct CircadianIllnessAgentTests {
    
    // MARK: - ALG-EFF-030: Dawn Phenomenon Tests
    
    @Test("Dawn phenomenon detection")
    func dawnPhenomenonDetection() {
        let analyzer = DawnPhenomenonAnalyzer()
        
        // Create 14 days of readings with clear dawn phenomenon
        var readings: [DawnPhenomenonAnalyzer.TimestampedGlucose] = []
        let calendar = Calendar.current
        let now = Date()
        
        for day in 0..<14 {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: calendar.startOfDay(for: now)) else { continue }
            
            // Generate readings every 15 minutes for key hours (3am-9am)
            for hour in 3..<10 {
                for minute in stride(from: 0, to: 60, by: 15) {
                    guard let timestamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) else { continue }
                    
                    let hourFrac = Double(hour) + Double(minute) / 60.0
                    
                    // Simulate dawn phenomenon: low at 4am, rise to peak at 7am
                    var value: Double
                    if hourFrac < 4.5 {
                        value = 90 // Low before dawn
                    } else if hourFrac >= 4.5 && hourFrac <= 7.0 {
                        // Rise during dawn
                        let progress = (hourFrac - 4.5) / 2.5
                        value = 90 + (progress * 50) // Rise from 90 to 140
                    } else {
                        value = 130 // Settling after dawn
                    }
                    
                    // Minimal noise for cleaner detection
                    value += Double.random(in: -3...3)
                    
                    readings.append(DawnPhenomenonAnalyzer.TimestampedGlucose(
                        timestamp: timestamp,
                        value: value
                    ))
                }
            }
        }
        
        let result = analyzer.analyze(readings: readings)
        
        #expect(result != nil, "Should detect dawn phenomenon with 14 days of clear data")
        if let dawn = result {
            #expect(dawn.startHour >= 3.0)
            #expect(dawn.startHour <= 6.0)
            #expect(dawn.averageRise >= 20.0)
            #expect(dawn.confidence >= 0.5)
            #expect(dawn.daysAnalyzed == 14)
        }
    }
    
    @Test("Dawn phenomenon suggested increase")
    func dawnPhenomenonSuggestedIncrease() {
        let dawn = DawnPhenomenon(
            startHour: 4.5,
            endHour: 7.0,
            averageRise: 45, // 45 mg/dL rise
            peakRise: 60,
            confidence: 0.8,
            daysAnalyzed: 14,
            startTimeVariability: 0.5
        )
        
        // 45 mg/dL / 300 = 0.15 = 15% increase
        #expect(abs(dawn.suggestedBasalIncrease - 0.15) < 0.01)
        #expect(abs(dawn.durationHours - 2.5) < 0.01)
    }
    
    @Test("Dawn phenomenon insufficient data")
    func dawnPhenomenonInsufficientData() {
        let analyzer = DawnPhenomenonAnalyzer(configuration: .init(minimumDays: 7))
        
        // Only 3 days of data
        var readings: [DawnPhenomenonAnalyzer.TimestampedGlucose] = []
        for hour in 0..<72 { // 3 days
            readings.append(DawnPhenomenonAnalyzer.TimestampedGlucose(
                timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
                value: 120
            ))
        }
        
        let result = analyzer.analyze(readings: readings)
        #expect(result == nil)
    }
    
    // MARK: - ALG-EFF-031: Sleep/Wake Pattern Tests
    
    @Test("Sleep wake pattern tracking")
    func sleepWakePatternTracking() async {
        let tracker = SleepWakePatternTracker(minimumRecords: 5)
        
        // Add 7 nights of sleep data
        let calendar = Calendar.current
        let now = Date()
        
        for day in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: now),
                  let bedtime = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: dayStart),
                  let wakeTime = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: 
                      calendar.date(byAdding: .day, value: 1, to: dayStart)!) else { continue }
            
            let record = SleepRecord(
                bedtime: bedtime,
                wakeTime: wakeTime,
                source: .healthKit
            )
            await tracker.addRecord(record)
        }
        
        let count = await tracker.recordCount()
        #expect(count == 7)
        
        let pattern = await tracker.analyzePatterns()
        #expect(pattern != nil)
        
        if let p = pattern {
            // Bedtime around 22.5 (10:30pm)
            #expect(abs(p.typicalBedtime - 22.5) < 0.5)
            // Wake around 6.5 (6:30am)
            #expect(abs(p.typicalWakeTime - 6.5) < 0.5)
            // Sleep duration ~8 hours
            #expect(abs(p.typicalSleepDuration - 8.0) < 0.5)
        }
    }
    
    @Test("Sleep quality impact")
    func sleepQualityImpact() {
        #expect(SleepQuality.poor.glucoseImpactFactor == 1.15)
        #expect(SleepQuality.good.glucoseImpactFactor == 1.0)
        #expect(SleepQuality.excellent.glucoseImpactFactor == 0.95)
    }
    
    @Test("Sleep record duration")
    func sleepRecordDuration() {
        let bedtime = Date()
        let wakeTime = bedtime.addingTimeInterval(8 * 3600) // 8 hours later
        
        let record = SleepRecord(
            bedtime: bedtime,
            wakeTime: wakeTime,
            source: .cgmInferred
        )
        
        #expect(abs(record.durationHours - 8.0) < 0.01)
    }
    
    // MARK: - Circadian Effect Modifier Tests
    
    @Test("Circadian effect modifier from dawn")
    func circadianEffectModifierFromDawn() {
        let dawn = DawnPhenomenon(
            startHour: 5.0,
            endHour: 8.0,
            averageRise: 30,
            peakRise: 45,
            confidence: 0.75,
            daysAnalyzed: 10,
            startTimeVariability: 0.5
        )
        
        let modifier = CircadianEffectModifier.fromDawnPhenomenon(dawn)
        
        #expect(modifier.hourlyAdjustments.count == 1)
        #expect(modifier.confidence == 0.75)
        
        // Check multiplier at different times
        let calendar = Calendar.current
        let today = Date()
        
        if let at6am = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today) {
            let mult = modifier.multiplier(for: at6am)
            #expect(mult > 1.0) // Should increase during dawn
        }
        
        if let at12pm = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today) {
            let mult = modifier.multiplier(for: at12pm)
            #expect(mult == 1.0) // No change at noon
        }
    }
    
    @Test("Hourly adjustment applies")
    func hourlyAdjustmentApplies() {
        let adjustment = CircadianEffectModifier.HourlyAdjustment(
            startHour: 5,
            endHour: 8,
            basalMultiplier: 1.2,
            reason: "Dawn"
        )
        
        #expect(adjustment.applies(to: 5))
        #expect(adjustment.applies(to: 6))
        #expect(adjustment.applies(to: 7))
        #expect(!adjustment.applies(to: 8)) // End hour not included
        #expect(!adjustment.applies(to: 4))
        #expect(!adjustment.applies(to: 12))
    }
    
    @Test("Hourly adjustment wraps around midnight")
    func hourlyAdjustmentWrapsAroundMidnight() {
        let adjustment = CircadianEffectModifier.HourlyAdjustment(
            startHour: 22,
            endHour: 6,
            basalMultiplier: 0.9,
            reason: "Night"
        )
        
        #expect(adjustment.applies(to: 22))
        #expect(adjustment.applies(to: 23))
        #expect(adjustment.applies(to: 0))
        #expect(adjustment.applies(to: 3))
        #expect(adjustment.applies(to: 5))
        #expect(!adjustment.applies(to: 6))
        #expect(!adjustment.applies(to: 12))
    }
    
    // MARK: - Circadian Agent Tests
    
    @Test("Circadian agent training")
    func circadianAgentTraining() async {
        let agent = CircadianAgent()
        
        // Create training data
        var readings: [DawnPhenomenonAnalyzer.TimestampedGlucose] = []
        let calendar = Calendar.current
        let now = Date()
        
        for day in 0..<14 {
            for hour in 0..<24 {
                guard let dayStart = calendar.date(byAdding: .day, value: -day, to: now),
                      let timestamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { continue }
                
                var value = 110.0
                if hour >= 5 && hour <= 7 {
                    value = 130.0 // Dawn rise
                }
                
                readings.append(DawnPhenomenonAnalyzer.TimestampedGlucose(
                    timestamp: timestamp,
                    value: value
                ))
            }
        }
        
        await agent.train(glucoseReadings: readings)
        
        let dawn = await agent.getDawnPhenomenon()
        // May or may not detect depending on data quality
        
        let modifier = await agent.getModifier()
        // Modifier may be nil if insufficient pattern
    }
    
    // MARK: - ALG-EFF-032: Illness Pattern Detection Tests
    
    @Test("Illness pattern detection")
    func illnessPatternDetection() {
        let detector = IllnessPatternDetector()
        
        // Create baseline (14 days of good control)
        var baseline: [IllnessPatternDetector.GlucoseReading] = []
        for hour in 0..<(14 * 24) {
            baseline.append(IllnessPatternDetector.GlucoseReading(
                timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
                value: 120 + Double.random(in: -15...15)
            ))
        }
        
        // Create recent "sick" data (elevated, variable)
        var recent: [IllnessPatternDetector.GlucoseReading] = []
        for hour in 0..<24 {
            recent.append(IllnessPatternDetector.GlucoseReading(
                timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
                value: 180 + Double.random(in: -30...30) // Much higher and more variable
            ))
        }
        
        let indicators = detector.analyze(recent: recent, baseline: baseline)
        
        #expect(indicators != nil)
        if let i = indicators {
            #expect(i.glucoseElevation > 40)
            #expect(i.suggestsIllness)
            #expect(i.severity != .none)
        }
    }
    
    @Test("Illness severity levels")
    func illnessSeverityLevels() {
        #expect(IllnessSeverity.none.suggestedBasalIncrease == 0.0)
        #expect(IllnessSeverity.mild.suggestedBasalIncrease == 0.10)
        #expect(IllnessSeverity.moderate.suggestedBasalIncrease == 0.20)
        #expect(IllnessSeverity.severe.suggestedBasalIncrease == 0.30)
    }
    
    @Test("Illness indicators severity")
    func illnessIndicatorsSeverity() {
        let mild = IllnessIndicators(
            glucoseElevation: 25,
            variabilityIncrease: 0.05,
            tirDecrease: 5,
            resistanceFactor: 1.1,
            confidence: 0.6,
            hoursAnalyzed: 24
        )
        #expect(mild.severity == .mild)
        
        let moderate = IllnessIndicators(
            glucoseElevation: 40,
            variabilityIncrease: 0.20,
            tirDecrease: 15,
            resistanceFactor: 1.25,
            confidence: 0.7,
            hoursAnalyzed: 24
        )
        #expect(moderate.severity == .moderate)
        
        let severe = IllnessIndicators(
            glucoseElevation: 70,
            variabilityIncrease: 0.30,
            tirDecrease: 30,
            resistanceFactor: 1.5,
            confidence: 0.8,
            hoursAnalyzed: 24
        )
        #expect(severe.severity == .severe)
    }
    
    // MARK: - ALG-EFF-033: Illness Agent Tests
    
    @Test("Illness agent recommendation")
    func illnessAgentRecommendation() async {
        let agent = IllnessAgent()
        
        var baseline: [IllnessPatternDetector.GlucoseReading] = []
        for hour in 0..<(14 * 24) {
            baseline.append(IllnessPatternDetector.GlucoseReading(
                timestamp: Date().addingTimeInterval(TimeInterval(-(hour + 24) * 3600)),
                value: 110
            ))
        }
        
        var recent: [IllnessPatternDetector.GlucoseReading] = []
        for hour in 0..<24 {
            recent.append(IllnessPatternDetector.GlucoseReading(
                timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
                value: 160 // Elevated
            ))
        }
        
        await agent.analyze(recent: recent, baseline: baseline)
        
        let recommendation = await agent.getRecommendation()
        #expect(recommendation != nil)
        
        if let rec = recommendation {
            #expect(rec.basalMultiplier > 1.0)
            #expect(rec.targetAdjustment <= 0) // Lower target
        }
    }
    
    @Test("Illness recommendation from indicators")
    func illnessRecommendationFromIndicators() {
        let indicators = IllnessIndicators(
            glucoseElevation: 50,
            variabilityIncrease: 0.20,
            tirDecrease: 20,
            resistanceFactor: 1.3,
            confidence: 0.75,
            hoursAnalyzed: 24
        )
        
        let recommendation = IllnessRecommendation.from(indicators: indicators)
        
        #expect(recommendation.basalMultiplier > 1.0)
        #expect(recommendation.correctionFactorMultiplier < 1.0)
        #expect(!recommendation.rationale.isEmpty)
    }
    
    // MARK: - ALG-EFF-034: Quick Action Tests
    
    @Test("Illness quick action activation")
    func illnessQuickActionActivation() async {
        let agent = IllnessAgent()
        
        var isActive = await agent.isManuallyActivated()
        #expect(!isActive)
        
        await agent.activateManually(severity: .moderate)
        
        isActive = await agent.isManuallyActivated()
        #expect(isActive)
        
        let severity = await agent.getSeverity()
        #expect(severity == .moderate)
        
        await agent.deactivateManually()
        
        isActive = await agent.isManuallyActivated()
        #expect(!isActive)
    }
    
    @Test("Quick action manager")
    func quickActionManager() async {
        let agent = IllnessAgent()
        let manager = IllnessQuickActionManager(agent: agent)
        
        await manager.activate(.feelingUnwell, notes: "Headache and fatigue")
        
        let current = await manager.currentAction()
        #expect(current == .feelingUnwell)
        
        let history = await manager.getHistory()
        #expect(history.count == 1)
        #expect(history.first?.notes == "Headache and fatigue")
        
        let isActive = await agent.isManuallyActivated()
        #expect(isActive)
    }
    
    @Test("Quick action severities")
    func quickActionSeverities() {
        #expect(IllnessQuickAction.feelingUnwell.severity == .moderate)
        #expect(IllnessQuickAction.startingCold.severity == .mild)
        #expect(IllnessQuickAction.recovering.severity == .mild)
        #expect(IllnessQuickAction.backToNormal.severity == .none)
    }
    
    @Test("Quick action icons")
    func quickActionIcons() {
        #expect(IllnessQuickAction.feelingUnwell.icon == "🤒")
        #expect(IllnessQuickAction.backToNormal.icon == "😊")
    }
    
    // MARK: - Combined Effect Tests
    
    @Test("Combined circadian illness effect")
    func combinedCircadianIllnessEffect() {
        let circadian = CircadianEffectModifier(
            hourlyAdjustments: [
                CircadianEffectModifier.HourlyAdjustment(
                    startHour: 5,
                    endHour: 8,
                    basalMultiplier: 1.2,
                    reason: "Dawn"
                )
            ],
            source: "Test",
            confidence: 0.8
        )
        
        let illness = IllnessRecommendation(
            basalMultiplier: 1.15,
            targetAdjustment: -10,
            correctionFactorMultiplier: 0.9,
            ketoneCheckThreshold: 250,
            rationale: "Test illness",
            confidence: 0.7,
            suggestedDurationHours: 24
        )
        
        let calendar = Calendar.current
        let today = Date()
        
        // At 6am (during dawn) with illness
        if let at6am = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today) {
            let combined = CircadianIllnessEffect.combine(
                circadian: circadian,
                illness: illness,
                at: at6am
            )
            
            // 1.2 * 1.15 = 1.38
            #expect(abs(combined.basalMultiplier - 1.38) < 0.01)
            #expect(combined.targetAdjustment == -10)
            #expect(combined.correctionFactorMultiplier == 0.9)
            #expect(combined.source == "Circadian+Illness")
        }
        
        // At noon (no dawn) with illness
        if let at12pm = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today) {
            let combined = CircadianIllnessEffect.combine(
                circadian: circadian,
                illness: illness,
                at: at12pm
            )
            
            // Just illness: 1.15
            #expect(abs(combined.basalMultiplier - 1.15) < 0.01)
            #expect(combined.source == "Illness")
        }
    }
    
    @Test("Combined effect no modifiers")
    func combinedEffectNoModifiers() {
        let combined = CircadianIllnessEffect.combine(
            circadian: nil,
            illness: nil
        )
        
        #expect(combined.basalMultiplier == 1.0)
        #expect(combined.targetAdjustment == 0)
        #expect(combined.source == "None")
    }
}
