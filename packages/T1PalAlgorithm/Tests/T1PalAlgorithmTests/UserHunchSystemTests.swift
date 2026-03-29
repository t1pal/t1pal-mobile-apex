// SPDX-License-Identifier: AGPL-3.0-or-later
//
// UserHunchSystemTests.swift
// T1PalAlgorithmTests
//
// Tests for User Hunch → Custom Agent Pipeline
// Backlog: ALG-HUNCH-001..004
// Trace: PRD-028 Phase 4 (User Hunches)

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("User Hunch System")
struct UserHunchSystemTests {
    
    // MARK: - HunchInput Tests (ALG-HUNCH-001)
    
    @Test("Hunch input creation")
    func hunchInputCreation() {
        let hunch = HunchInput(
            rawInput: "Tennis always makes me go low",
            category: .activity,
            belief: .activityCausesLow(activity: "Tennis", severity: .moderate),
            userConfidence: 0.9
        )
        
        #expect(hunch.category == .activity)
        #expect(hunch.userConfidence == 0.9)
        #expect(hunch.rawInput == "Tennis always makes me go low")
    }
    
    @Test("Hunch input clamps confidence")
    func hunchInputClampsConfidence() {
        let hunch = HunchInput(
            rawInput: "Test",
            category: .custom,
            belief: .custom(description: "Test", expectedEffect: ExpectedEffect()),
            userConfidence: 1.5  // Should be clamped to 1.0
        )
        
        #expect(hunch.userConfidence == 1.0)
    }
    
    @Test("Hunch belief activity low")
    func hunchBeliefActivityLow() {
        let belief = HunchBelief.activityCausesLow(activity: "Running", severity: .severe)
        
        if case .activityCausesLow(let activity, let severity) = belief {
            #expect(activity == "Running")
            #expect(severity == .severe)
            #expect(severity.effectMultiplier == 0.35)
        } else {
            Issue.record("Expected activityCausesLow")
        }
    }
    
    @Test("Hunch belief food effect")
    func hunchBeliefFoodEffect() {
        let belief = HunchBelief.foodEffect(item: "Coffee", direction: .rising, severity: .moderate)
        
        if case .foodEffect(let item, let direction, let severity) = belief {
            #expect(item == "Coffee")
            #expect(direction == .rising)
            #expect(severity.effectMultiplier == 0.20)
        } else {
            Issue.record("Expected foodEffect")
        }
    }
    
    @Test("Time period hour ranges")
    func timePeriodHourRanges() {
        #expect(TimePeriod.earlyMorning.hourRange == 4...6)
        #expect(TimePeriod.morning.hourRange == 7...10)
        #expect(TimePeriod.midday.hourRange == 11...13)
        #expect(TimePeriod.afternoon.hourRange == 14...17)
        #expect(TimePeriod.evening.hourRange == 18...20)
        #expect(TimePeriod.night.hourRange == 21...23)
        #expect(TimePeriod.lateNight.hourRange == 0...3)
    }
    
    @Test("Expected effect values")
    func expectedEffect() {
        let effect = ExpectedEffect(
            basalMultiplier: 0.8,
            isfMultiplier: 1.1,
            targetAdjustment: 20,
            durationMinutes: 180
        )
        
        #expect(effect.basalMultiplier == 0.8)
        #expect(effect.isfMultiplier == 1.1)
        #expect(effect.targetAdjustment == 20)
        #expect(effect.durationMinutes == 180)
    }
    
    // MARK: - HunchParser Tests (ALG-HUNCH-002)
    
    @Test("Parser detects activity low")
    func parserDetectsActivityLow() {
        let parser = HunchParser()
        let result = parser.parse("Tennis always makes me go low")
        
        #expect(result.success)
        #expect(result.category == .activity)
        #expect(result.extractedEntities["activity"] == "Tennis")
        
        if case .activityCausesLow(let activity, _) = result.belief {
            #expect(activity == "Tennis")
        } else {
            Issue.record("Expected activityCausesLow belief")
        }
    }
    
    @Test("Parser detects activity high")
    func parserDetectsActivityHigh() {
        let parser = HunchParser()
        let result = parser.parse("Weightlifting makes me spike")
        
        #expect(result.success)
        #expect(result.category == .activity)
        
        if case .activityCausesHigh(let activity, _) = result.belief {
            #expect(activity == "Lifting")  // Extracted keyword
        } else {
            Issue.record("Expected activityCausesHigh belief")
        }
    }
    
    @Test("Parser detects food effect")
    func parserDetectsFoodEffect() {
        let parser = HunchParser()
        let result = parser.parse("Coffee makes me spike every morning")
        
        #expect(result.success)
        #expect(result.category == .meal)
        #expect(result.extractedEntities["food"] == "Coffee")
        
        if case .foodEffect(let item, let direction, _) = result.belief {
            #expect(item == "Coffee")
            #expect(direction == .rising)
        } else {
            Issue.record("Expected foodEffect belief")
        }
    }
    
    @Test("Parser detects time pattern")
    func parserDetectsTimePattern() {
        let parser = HunchParser()
        let result = parser.parse("I always go high in the morning")
        
        #expect(result.success)
        
        if case .timePattern(let period, let direction) = result.belief {
            #expect(period == .morning)
            #expect(direction == .rising)
        } else {
            Issue.record("Expected timePattern belief")
        }
    }
    
    @Test("Parser detects stress")
    func parserDetectsStress() {
        let parser = HunchParser()
        let result = parser.parse("Stress makes me go high")
        
        #expect(result.success)
        #expect(result.category == .health)
        
        if case .stressEffect(let direction, _) = result.belief {
            #expect(direction == .rising)
        } else {
            Issue.record("Expected stressEffect belief")
        }
    }
    
    @Test("Parser detects medication")
    func parserDetectsMedication() {
        let parser = HunchParser()
        let result = parser.parse("Prednisone makes me really resistant")
        
        #expect(result.success)
        #expect(result.category == .health)
        
        if case .medicationEffect(let med, let effect) = result.belief {
            #expect(med == "Prednisone")
            #expect(effect == .increasedResistance)
        } else {
            Issue.record("Expected medicationEffect belief")
        }
    }
    
    @Test("Parser detects sleep pattern")
    func parserDetectsSleepPattern() {
        let parser = HunchParser()
        // Use "sleeping in" which the parser checks for
        let result = parser.parse("I go low after sleeping in on weekends")
        
        #expect(result.success)
        
        if case .sleepPattern(let condition, let direction) = result.belief {
            #expect(condition == .sleepingIn)
            #expect(direction == .falling)
        } else {
            Issue.record("Expected sleepPattern belief, got \(result.belief)")
        }
    }
    
    @Test("Parser detects menstrual cycle")
    func parserDetectsMenstrualCycle() {
        let parser = HunchParser()
        // "before period" should trigger premenstrual, "resistant" for direction
        let result = parser.parse("I get resistant before my period starts")
        
        #expect(result.success)
        #expect(result.category == .health)
        
        if case .menstrualCycle(let phase, let effect) = result.belief {
            #expect(phase == .premenstrual)
            #expect(effect == .moreResistant)
        } else {
            Issue.record("Expected menstrualCycle belief, got \(result.belief)")
        }
    }
    
    @Test("Parser detects weather")
    func parserDetectsWeather() {
        let parser = HunchParser()
        let result = parser.parse("Hot weather makes me more sensitive")
        
        #expect(result.success)
        
        if case .weatherEffect(let condition, let effect) = result.belief {
            #expect(condition == .hot)
            #expect(effect == .moreSensitive)
        } else {
            Issue.record("Expected weatherEffect belief")
        }
    }
    
    @Test("Parser detects severity")
    func parserDetectsSeverity() {
        let parser = HunchParser()
        
        // Severe
        let severe = parser.parse("Tennis always makes me crash")
        if case .activityCausesLow(_, let severity) = severe.belief {
            #expect(severity == .severe)
        }
        
        // Mild
        let mild = parser.parse("Running sometimes makes me go slightly low")
        if case .activityCausesLow(_, let severity) = mild.belief {
            #expect(severity == .mild)
        }
    }
    
    @Test("Parser fallback to custom")
    func parserFallbackToCustom() {
        let parser = HunchParser()
        let result = parser.parse("Something weird happens on Tuesdays")
        
        #expect(!result.success)
        #expect(result.category == .custom)
        #expect(result.confidence <= 0.5)
    }
    
    // MARK: - HunchValidator Tests (ALG-HUNCH-003)
    
    @Test("Validator insufficient data")
    func validatorInsufficientData() async {
        let validator = HunchValidator(minDataPoints: 10)
        
        let hunch = HunchInput(
            rawInput: "Tennis makes me go low",
            category: .activity,
            belief: .activityCausesLow(activity: "Tennis", severity: .moderate)
        )
        
        // Only 3 events (need 10)
        let events = (0..<3).map { i in
            HunchValidationEvent(
                timestamp: Date().addingTimeInterval(Double(-i) * 86400),
                eventType: .activity(name: "Tennis")
            )
        }
        
        let result = await validator.validate(hunch: hunch, glucoseHistory: [], eventHistory: events)
        
        #expect(result.status == .insufficientData)
        #expect(result.supportingEvents == 3)
    }
    
    @Test("Validator validates pattern")
    func validatorValidatesPattern() async {
        let validator = HunchValidator(minDataPoints: 5, correlationThreshold: 0.5)
        
        let hunch = HunchInput(
            rawInput: "Tennis makes me go low",
            category: .activity,
            belief: .activityCausesLow(activity: "Tennis", severity: .moderate)
        )
        
        let now = Date()
        var events: [HunchValidationEvent] = []
        var glucoseHistory: [GlucosePoint] = []
        
        // Create 10 tennis events with consistent low response
        for i in 0..<10 {
            let eventTime = now.addingTimeInterval(Double(-i) * 86400)
            events.append(HunchValidationEvent(
                timestamp: eventTime,
                eventType: .activity(name: "Tennis")
            ))
            
            // Add glucose readings: high before, low after
            for m in stride(from: -30, through: 180, by: 15) {
                let readingTime = eventTime.addingTimeInterval(Double(m) * 60)
                let value: Double = m < 0 ? 140 : 100  // Drop from 140 to 100
                glucoseHistory.append(GlucosePoint(date: readingTime, glucoseValue: value))
            }
        }
        
        let result = await validator.validate(hunch: hunch, glucoseHistory: glucoseHistory, eventHistory: events)
        
        #expect(result.status == .validated || result.status == .partiallyValidated)
        #expect(result.supportingEvents > 0)
        #expect(result.confidence > 0.5)
    }
    
    @Test("Validator detects contradiction")
    func validatorDetectsContradiction() async {
        let validator = HunchValidator(minDataPoints: 5, correlationThreshold: 0.5)
        
        // User thinks tennis causes lows
        let hunch = HunchInput(
            rawInput: "Tennis makes me go low",
            category: .activity,
            belief: .activityCausesLow(activity: "Tennis", severity: .moderate)
        )
        
        let now = Date()
        var events: [HunchValidationEvent] = []
        var glucoseHistory: [GlucosePoint] = []
        
        // But data shows tennis causes highs!
        for i in 0..<10 {
            let eventTime = now.addingTimeInterval(Double(-i) * 86400)
            events.append(HunchValidationEvent(
                timestamp: eventTime,
                eventType: .activity(name: "Tennis")
            ))
            
            // Glucose goes UP after tennis (opposite of hunch)
            for m in stride(from: -30, through: 180, by: 15) {
                let readingTime = eventTime.addingTimeInterval(Double(m) * 60)
                let value: Double = m < 0 ? 100 : 160  // Rise from 100 to 160
                glucoseHistory.append(GlucosePoint(date: readingTime, glucoseValue: value))
            }
        }
        
        let result = await validator.validate(hunch: hunch, glucoseHistory: glucoseHistory, eventHistory: events)
        
        #expect(result.status == .contradicted)
        #expect(result.supportingEvents == 0)
    }
    
    // MARK: - HunchAgentFactory Tests (ALG-HUNCH-004)
    
    @Test("Factory creates agent from validated hunch")
    func factoryCreatesAgentFromValidatedHunch() {
        let factory = HunchAgentFactory()
        
        let hunch = HunchInput(
            rawInput: "Tennis makes me go low",
            category: .activity,
            belief: .activityCausesLow(activity: "Tennis", severity: .moderate)
        )
        
        let validationResult = HunchValidationResult(
            status: .validated,
            supportingEvents: 15,
            contradictingEvents: 2,
            correlation: 0.8,
            confidence: 0.85,
            message: "Pattern validated"
        )
        
        let agent = factory.createAgent(from: hunch, validationResult: validationResult)
        
        #expect(agent != nil)
        #expect(agent?.name == "Tennis (Low Prevention)")
        
        // Effect should reduce basal (activity causes lows)
        if let effect = agent?.effect {
            #expect(effect.basalMultiplier != nil)
            #expect(effect.basalMultiplier! < 1.0)  // Reduced basal
        }
        
        // Trigger should be activity
        if case .activity(let name) = agent?.trigger {
            #expect(name == "Tennis")
        } else {
            Issue.record("Expected activity trigger")
        }
    }
    
    @Test("Factory rejects unvalidated hunch")
    func factoryRejectsUnvalidatedHunch() {
        let factory = HunchAgentFactory()
        
        let hunch = HunchInput(
            rawInput: "Test",
            category: .custom,
            belief: .custom(description: "Test", expectedEffect: ExpectedEffect())
        )
        
        let validationResult = HunchValidationResult(
            status: .insufficientData,
            supportingEvents: 2,
            contradictingEvents: 0,
            correlation: nil,
            confidence: 0.3,
            message: "Need more data"
        )
        
        let agent = factory.createAgent(from: hunch, validationResult: validationResult)
        
        #expect(agent == nil)
    }
    
    @Test("Factory calculates effect for activity high")
    func factoryCalculatesEffectForActivityHigh() {
        let factory = HunchAgentFactory()
        
        let hunch = HunchInput(
            rawInput: "Weights make me spike",
            category: .activity,
            belief: .activityCausesHigh(activity: "Weights", severity: .moderate)
        )
        
        let validationResult = HunchValidationResult(
            status: .validated,
            supportingEvents: 10,
            contradictingEvents: 1,
            correlation: 0.75,
            confidence: 0.8,
            message: "Validated"
        )
        
        let agent = factory.createAgent(from: hunch, validationResult: validationResult)
        
        #expect(agent != nil)
        
        // Effect should increase basal (activity causes highs)
        if let effect = agent?.effect {
            #expect(effect.basalMultiplier != nil)
            #expect(effect.basalMultiplier! > 1.0)  // Increased basal
        }
    }
    
    @Test("Factory calculates effect for medication")
    func factoryCalculatesEffectForMedication() {
        let factory = HunchAgentFactory()
        
        let hunch = HunchInput(
            rawInput: "Prednisone makes me resistant",
            category: .health,
            belief: .medicationEffect(medication: "Prednisone", effect: .increasedResistance)
        )
        
        let validationResult = HunchValidationResult(
            status: .validated,
            supportingEvents: 8,
            contradictingEvents: 0,
            correlation: 0.9,
            confidence: 0.9,
            message: "Validated"
        )
        
        let agent = factory.createAgent(from: hunch, validationResult: validationResult)
        
        #expect(agent != nil)
        #expect(agent?.name == "Prednisone Adjustment")
        
        // Effect should be longer duration for medications
        if let effect = agent?.effect {
            #expect(effect.durationMinutes >= 480)
        }
    }
    
    // MARK: - HunchManager Integration Tests
    
    @Test("Hunch manager submit and parse")
    func hunchManagerSubmitAndParse() async {
        let manager = HunchManager()
        
        let result = await manager.submitHunch("Running makes me go low")
        
        #expect(!result.needsMoreInfo)
        #expect(result.parsed.success)
        #expect(result.parsed.category == .activity)
        
        // Hunch should be stored
        let stored = await manager.getHunch(id: result.hunchId)
        #expect(stored != nil)
        #expect(stored?.rawInput == "Running makes me go low")
    }
    
    @Test("Hunch manager full pipeline")
    func hunchManagerFullPipeline() async {
        let manager = HunchManager()
        
        // Step 1: Submit hunch
        let submission = await manager.submitHunch("Tennis makes me go low")
        #expect(submission.parsed.success)
        
        // Step 2: Validate (with mock data showing pattern)
        let now = Date()
        var events: [HunchValidationEvent] = []
        var glucose: [GlucosePoint] = []
        
        for i in 0..<10 {
            let eventTime = now.addingTimeInterval(Double(-i) * 86400)
            events.append(HunchValidationEvent(
                timestamp: eventTime,
                eventType: .activity(name: "Tennis")
            ))
            
            for m in stride(from: -30, through: 180, by: 15) {
                let readingTime = eventTime.addingTimeInterval(Double(m) * 60)
                let value: Double = m < 0 ? 130 : 95
                glucose.append(GlucosePoint(date: readingTime, glucoseValue: value))
            }
        }
        
        let validation = await manager.validateHunch(
            id: submission.hunchId,
            glucoseHistory: glucose,
            eventHistory: events
        )
        
        #expect(validation != nil)
        #expect(validation!.status == .validated || validation!.status == .partiallyValidated)
        
        // Step 3: Create agent
        let agent = await manager.createAgentFromHunch(id: submission.hunchId)
        
        #expect(agent != nil)
        #expect(agent?.name == "Tennis (Low Prevention)")
        
        // Step 4: Verify agent is active
        let activeAgents = await manager.getActiveAgents()
        #expect(activeAgents.count == 1)
    }
    
    @Test("Hunch manager suggestions for ambiguous input")
    func hunchManagerSuggestionsForAmbiguousInput() async {
        let manager = HunchManager()
        
        let result = await manager.submitHunch("Something happens")
        
        #expect(result.needsMoreInfo)
        #expect(!result.suggestions.isEmpty)
    }
}
