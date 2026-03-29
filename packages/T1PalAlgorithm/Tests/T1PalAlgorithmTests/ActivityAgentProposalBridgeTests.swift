// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ActivityAgentProposalBridgeTests.swift
// T1PalAlgorithmTests
//
// Tests for ALG-LEARN-020..024: Agent Proposal Integration

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Activity Agent Proposal Bridge")
struct ActivityAgentProposalBridgeTests {
    
    // MARK: - ALG-LEARN-020: Bridge Tests
    
    @Test("Registered agent info creation")
    func registeredAgentInfoCreation() async throws {
        let definition = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.6, isfMultiplier: 1.3),
            isSystemDefault: false
        )
        
        let bootstrapper = ActivityAgentBootstrapper()
        let _ = await bootstrapper.registerOverride(definition)
        
        guard let stub = await bootstrapper.agent(for: "tennis") else {
            Issue.record("Expected agent stub")
            return
        }
        
        let agentInfo = ActivityProposalBridge.createRegisteredAgent(from: stub, definition: definition)
        
        #expect(agentInfo.agentId == "activity-agent-tennis")
        #expect(agentInfo.name == "Tennis Agent")
        #expect(agentInfo.capabilities.contains(.proposeOverride))
    }
    
    @Test("Activity proposal data conversion")
    func activityProposalDataConversion() {
        let trigger = ActivityTrigger(
            type: .workoutStart,
            confidence: 0.9,
            matchedActivityId: "running"
        )
        
        let proposal = ActivityProposal(
            activityId: "running",
            activityName: "Morning Run",
            trigger: trigger,
            description: "Starting Morning Run?",
            rationale: "Learned from 8 sessions (75% success)",
            suggestedSettings: OverrideSettings(basalMultiplier: 0.5, isfMultiplier: 1.5),
            duration: 3600,
            confidence: 0.75,
            sessionCount: 8,
            expiresAt: Date().addingTimeInterval(900)
        )
        
        let data = ActivityProposalBridge.convertToProposalData(proposal)
        
        #expect(data.agentId == "activity-agent-running")
        #expect(data.agentName == "Morning Run Agent")
        #expect(data.proposalType == .override)
        #expect(data.basalMultiplier == 0.5)
        #expect(data.isfMultiplier == 1.5)
        #expect(data.overrideDuration == 3600)
    }
    
    // MARK: - ALG-LEARN-021: Proposal Template Tests
    
    @Test("Proposal template description generation")
    func proposalTemplateDescriptionGeneration() {
        let template = ActivityProposalTemplate(
            id: "tennis-template",
            name: "Tennis",
            activityAgentId: "tennis",
            descriptionTemplate: "Starting {activity}?",
            rationaleTemplate: "Based on {sessions} sessions with {confidence}% success"
        )
        
        let description = template.generateDescription(activityName: "Tennis Practice")
        #expect(description == "Starting Tennis Practice?")
        
        let rationale = template.generateRationale(sessions: 10, confidence: 0.85)
        #expect(rationale == "Based on 10 sessions with 85% success")
    }
    
    @Test("Proposal template defaults")
    func proposalTemplateDefaults() {
        let template = ActivityProposalTemplate(
            id: "test",
            name: "Test Activity",
            activityAgentId: "test-activity"
        )
        
        #expect(template.defaultDuration == 3600)
        #expect(template.proposalExpiryMinutes == 15)
    }
    
    // MARK: - ALG-LEARN-022: Trigger Detection Tests
    
    @Test("Activity trigger creation")
    func activityTriggerCreation() {
        let trigger = ActivityTrigger(
            type: .workoutStart,
            confidence: 0.9,
            matchedActivityId: "tennis"
        )
        
        #expect(trigger.type == .workoutStart)
        #expect(trigger.confidence == 0.9)
        #expect(trigger.matchedActivityId == "tennis")
    }
    
    @Test("Trigger context defaults")
    func triggerContextDefaults() {
        let context = ActivityTrigger.TriggerContext()
        
        // Should use current time
        let calendar = Calendar.current
        let now = Date()
        #expect(context.dayOfWeek == calendar.component(.weekday, from: now))
        #expect(context.hour == calendar.component(.hour, from: now))
        #expect(context.workoutType == nil)
        #expect(context.locationName == nil)
    }
    
    @Test("Trigger detector registration")
    func triggerDetectorRegistration() async {
        let detector = ActivityTriggerDetector()
        
        let definition = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.6),
            isSystemDefault: false
        )
        
        await detector.registerActivity(definition)
        
        // Test direct workout match
        let trigger = await detector.matchWorkout(type: "Tennis")
        #expect(trigger != nil)
        #expect(trigger?.matchedActivityId == "tennis")
        #expect(trigger?.type == .workoutStart)
    }
    
    @Test("Trigger detector partial match")
    func triggerDetectorPartialMatch() async {
        let detector = ActivityTriggerDetector()
        
        let definition = UserOverrideDefinition(
            id: "morning-run",
            name: "Running",
            settings: OverrideSettings(basalMultiplier: 0.5),
            isSystemDefault: false
        )
        
        await detector.registerActivity(definition)
        
        // Should match "Indoor Running" to "Running"
        let trigger = await detector.matchWorkout(type: "Indoor Running")
        #expect(trigger != nil)
        #expect(trigger?.matchedActivityId == "morning-run")
        #expect((trigger?.confidence ?? 0) > 0.8)
    }
    
    @Test("Trigger detector category match")
    func triggerDetectorCategoryMatch() async {
        let detector = ActivityTriggerDetector()
        
        // User has a generic "Cardio" activity
        let definition = UserOverrideDefinition(
            id: "cardio",
            name: "Cardio Workout",
            settings: OverrideSettings(basalMultiplier: 0.5),
            isSystemDefault: false
        )
        
        await detector.registerActivity(definition)
        
        // Should match "Cycling" to "Cardio" via category
        let trigger = await detector.matchWorkout(type: "Cycling")
        #expect(trigger != nil)
        #expect(trigger?.matchedActivityId == "cardio")
        #expect(trigger?.confidence == 0.7) // Category match is lower confidence
    }
    
    @Test("Trigger pattern matching")
    func triggerPatternMatching() async {
        let detector = ActivityTriggerDetector()
        
        // Pattern: Tennis on Saturdays at 10am
        let pattern = TriggerPattern(
            type: .timeOfDay,
            conditions: TriggerPattern.PatternConditions(
                timeOfDayRange: 9...11,
                daysOfWeek: [7] // Saturday
            ),
            confidence: 0.8
        )
        
        await detector.addPattern(activityId: "tennis", pattern: pattern)
        
        // Saturday at 10am context
        let context = ActivityTrigger.TriggerContext(
            dayOfWeek: 7,
            hour: 10
        )
        
        let triggers = await detector.detectTriggers(context: context)
        #expect(!triggers.isEmpty)
        #expect(triggers.first?.matchedActivityId == "tennis")
    }
    
    @Test("Trigger pattern no match")
    func triggerPatternNoMatch() async {
        let detector = ActivityTriggerDetector()
        
        // Pattern: Tennis on Saturdays at 10am
        let pattern = TriggerPattern(
            type: .timeOfDay,
            conditions: TriggerPattern.PatternConditions(
                timeOfDayRange: 9...11,
                daysOfWeek: [7] // Saturday
            ),
            confidence: 0.8
        )
        
        await detector.addPattern(activityId: "tennis", pattern: pattern)
        
        // Monday at 3pm context - should not match
        let context = ActivityTrigger.TriggerContext(
            dayOfWeek: 2,
            hour: 15
        )
        
        let triggers = await detector.detectTriggers(context: context)
        #expect(triggers.isEmpty)
    }
    
    // MARK: - ALG-LEARN-023: Proposal Generator Tests
    
    @Test("Proposal generator requires training")
    func proposalGeneratorRequiresTraining() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let generator = ActivityProposalGenerator(
            bootstrapper: bootstrapper,
            minConfidenceForProposal: 0.5,
            minSessionsForProposal: 3
        )
        
        // Create agent with no sessions
        let definition = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.6),
            isSystemDefault: false
        )
        let _ = await bootstrapper.registerOverride(definition)
        
        let trigger = ActivityTrigger(
            type: .workoutStart,
            confidence: 0.9,
            matchedActivityId: "tennis"
        )
        
        // Should not generate proposal - not enough training
        let proposal = await generator.generateProposal(from: trigger)
        #expect(proposal == nil)
    }
    
    @Test("Proposal generator with trained agent")
    func proposalGeneratorWithTrainedAgent() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let generator = ActivityProposalGenerator(
            bootstrapper: bootstrapper,
            minConfidenceForProposal: 0.3,
            minSessionsForProposal: 3
        )
        
        // Create agent and add sessions
        let definition = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.6, isfMultiplier: 1.3),
            isSystemDefault: false
        )
        let _ = await bootstrapper.registerOverride(definition)
        
        guard let stub = await bootstrapper.agent(for: "tennis") else {
            Issue.record("Expected stub")
            return
        }
        
        // Add 5 sessions
        for i in 0..<5 {
            let session = createTestSession(
                overrideId: "tennis",
                overrideName: "Tennis",
                settings: definition.settings,
                startOffset: TimeInterval(-7200 - (i * 86400)),
                duration: 3600,
                timeInRange: 0.8,
                successScore: 0.75
            )
            await stub.addSession(session)
        }
        
        let trigger = ActivityTrigger(
            type: .workoutStart,
            confidence: 0.9,
            matchedActivityId: "tennis"
        )
        
        // Should generate proposal - agent is trained
        let proposal = await generator.generateProposal(from: trigger)
        #expect(proposal != nil)
        #expect(proposal?.activityId == "tennis")
        #expect(proposal?.activityName == "Tennis")
        #expect(proposal?.description.contains("Tennis") ?? false)
    }
    
    @Test("Activity proposal settings summary")
    func activityProposalSettingsSummary() {
        let proposal = ActivityProposal(
            activityId: "tennis",
            activityName: "Tennis",
            trigger: ActivityTrigger(type: .manual),
            description: "Starting Tennis?",
            rationale: "Learned",
            suggestedSettings: OverrideSettings(basalMultiplier: 0.6, isfMultiplier: 1.25),
            duration: 3600,
            confidence: 0.8,
            sessionCount: 10,
            expiresAt: Date().addingTimeInterval(900)
        )
        
        let summary = proposal.settingsSummary
        #expect(summary.contains("-40% basal"))
        #expect(summary.contains("ISF"))
        #expect(summary.contains("60 min"))
    }
    
    // MARK: - ALG-LEARN-024: Outcome Tracking Tests
    
    @Test("Proposal outcome tracker acceptance")
    func proposalOutcomeTrackerAcceptance() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let tracker = ProposalOutcomeTracker(bootstrapper: bootstrapper)
        
        let proposal = ActivityProposal(
            activityId: "tennis",
            activityName: "Tennis",
            trigger: ActivityTrigger(type: .manual),
            description: "Starting Tennis?",
            rationale: "Learned",
            suggestedSettings: OverrideSettings(basalMultiplier: 0.6),
            duration: 3600,
            confidence: 0.8,
            sessionCount: 10,
            expiresAt: Date().addingTimeInterval(900)
        )
        
        await tracker.trackProposal(proposal)
        await tracker.recordAcceptance(proposalId: proposal.id)
        
        let outcomes = await tracker.recentOutcomes()
        #expect(outcomes.count == 1)
        
        if case .accepted = outcomes.first?.action {
            // Expected
        } else {
            Issue.record("Expected accepted action")
        }
    }
    
    @Test("Proposal outcome tracker rejection")
    func proposalOutcomeTrackerRejection() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let tracker = ProposalOutcomeTracker(bootstrapper: bootstrapper)
        
        let proposal = ActivityProposal(
            activityId: "tennis",
            activityName: "Tennis",
            trigger: ActivityTrigger(type: .manual),
            description: "Starting Tennis?",
            rationale: "Learned",
            suggestedSettings: OverrideSettings(basalMultiplier: 0.6),
            duration: 3600,
            confidence: 0.8,
            sessionCount: 10,
            expiresAt: Date().addingTimeInterval(900)
        )
        
        await tracker.trackProposal(proposal)
        await tracker.recordRejection(proposalId: proposal.id, reason: .wrongTiming)
        
        let outcomes = await tracker.recentOutcomes()
        #expect(outcomes.count == 1)
        
        if case .rejected(let reason) = outcomes.first?.action {
            #expect(reason == .wrongTiming)
        } else {
            Issue.record("Expected rejected action")
        }
    }
    
    @Test("Proposal outcome tracker expiry")
    func proposalOutcomeTrackerExpiry() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let tracker = ProposalOutcomeTracker(bootstrapper: bootstrapper)
        
        let proposal = ActivityProposal(
            activityId: "tennis",
            activityName: "Tennis",
            trigger: ActivityTrigger(type: .manual),
            description: "Starting Tennis?",
            rationale: "Learned",
            suggestedSettings: OverrideSettings(basalMultiplier: 0.6),
            duration: 3600,
            confidence: 0.8,
            sessionCount: 10,
            expiresAt: Date().addingTimeInterval(-60) // Already expired
        )
        
        await tracker.trackProposal(proposal)
        await tracker.recordExpiry(proposalId: proposal.id)
        
        let outcomes = await tracker.recentOutcomes()
        #expect(outcomes.count == 1)
        
        if case .expired = outcomes.first?.action {
            // Expected
        } else {
            Issue.record("Expected expired action")
        }
    }
    
    @Test("Acceptance rate calculation")
    func acceptanceRateCalculation() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let tracker = ProposalOutcomeTracker(bootstrapper: bootstrapper)
        
        // Create 4 proposals - 3 accepted, 1 rejected
        for i in 0..<4 {
            let proposal = ActivityProposal(
                activityId: "tennis",
                activityName: "Tennis",
                trigger: ActivityTrigger(type: .manual),
                description: "Test",
                rationale: "Test",
                suggestedSettings: OverrideSettings(basalMultiplier: 0.6),
                duration: 3600,
                confidence: 0.8,
                sessionCount: 10,
                expiresAt: Date().addingTimeInterval(900)
            )
            
            await tracker.trackProposal(proposal)
            
            if i < 3 {
                await tracker.recordAcceptance(proposalId: proposal.id)
            } else {
                await tracker.recordRejection(proposalId: proposal.id, reason: .other)
            }
        }
        
        let rate = await tracker.acceptanceRate(for: "tennis")
        #expect(rate != nil)
        #expect(abs((rate ?? 0) - 0.75) < 0.01)
    }
    
    @Test("Acceptance rate requires min samples")
    func acceptanceRateRequiresMinSamples() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let tracker = ProposalOutcomeTracker(bootstrapper: bootstrapper)
        
        // Only 2 proposals - not enough for rate
        for _ in 0..<2 {
            let proposal = ActivityProposal(
                activityId: "tennis",
                activityName: "Tennis",
                trigger: ActivityTrigger(type: .manual),
                description: "Test",
                rationale: "Test",
                suggestedSettings: OverrideSettings(basalMultiplier: 0.6),
                duration: 3600,
                confidence: 0.8,
                sessionCount: 10,
                expiresAt: Date().addingTimeInterval(900)
            )
            
            await tracker.trackProposal(proposal)
            await tracker.recordAcceptance(proposalId: proposal.id)
        }
        
        let rate = await tracker.acceptanceRate(for: "tennis")
        #expect(rate == nil) // Not enough samples
    }
    
    @Test("Settings modification")
    func settingsModification() {
        let modification = SettingsModification(
            basalMultiplierDelta: -0.1,
            isfMultiplierDelta: 0.05
        )
        
        #expect(modification.hasModifications)
        #expect(modification.basalMultiplierDelta == -0.1)
        #expect(modification.isfMultiplierDelta == 0.05)
        #expect(modification.durationDelta == nil)
    }
    
    @Test("Rejection reason display text")
    func rejectionReasonDisplayText() {
        #expect(RejectionReason.wrongTiming.displayText == "Not the right time")
        #expect(RejectionReason.wrongActivity.displayText == "Wrong activity detected")
        #expect(RejectionReason.dontNeedIt.displayText == "Don't need override for this")
        #expect(RejectionReason.settingsWrong.displayText == "Settings don't work for me")
    }
    
    // MARK: - Test Helpers
    
    private func createTestSession(
        overrideId: String,
        overrideName: String,
        settings: OverrideSettings,
        startOffset: TimeInterval,
        duration: TimeInterval,
        timeInRange: Double,
        successScore: Double
    ) -> OverrideSession {
        let activatedAt = Date().addingTimeInterval(startOffset)
        let preSnapshot = GlucoseSnapshot(
            glucose: 120,
            trend: 0,
            timeInRange: 0.7,
            timestamp: activatedAt
        )
        
        var session = OverrideSession(
            overrideId: overrideId,
            overrideName: overrideName,
            activatedAt: activatedAt,
            settings: settings,
            preSnapshot: preSnapshot,
            context: OverrideContext(activationSource: .manual)
        )
        
        // Complete the session
        session.deactivatedAt = activatedAt.addingTimeInterval(duration)
        session.postSnapshot = GlucoseSnapshot(
            glucose: 110,
            trend: 0,
            timeInRange: timeInRange,
            timestamp: activatedAt.addingTimeInterval(duration)
        )
        session.outcome = OverrideOutcome(
            timeInRange: timeInRange,
            timeInRangeDelta: 0.1,
            hypoEvents: 0,
            hyperEvents: 1,
            averageGlucose: 115,
            variability: 15,
            successScore: successScore
        )
        
        return session
    }
}
