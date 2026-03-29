// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ActivityAgentBootstrapperTests.swift
// T1PalAlgorithmTests
//
// Tests for activity agent bootstrapping from user overrides
// Backlog: ALG-LEARN-010, ALG-LEARN-011, ALG-LEARN-012, ALG-LEARN-013, ALG-LEARN-014

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - User Override Definition Tests (ALG-LEARN-010)

@Suite("UserOverrideDefinition")
struct UserOverrideDefinitionTests {
    
    @Test("user-created activity override is detected")
    func userCreatedActivityOverride() {
        let override = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.7),
            isSystemDefault: false,
            category: .activity
        )
        
        #expect(override.isActivityOverride == true)
        #expect(override.isSystemDefault == false)
        #expect(override.category == .activity)
    }
    
    @Test("system default override is not activity override")
    func systemDefaultNotActivity() {
        let override = UserOverrideDefinition(
            id: "sleep",
            name: "Sleep",
            settings: OverrideSettings(basalMultiplier: 0.9),
            isSystemDefault: true,
            category: .sleep
        )
        
        #expect(override.isActivityOverride == false)
        #expect(override.isSystemDefault == true)
    }
    
    @Test("user-created health override is not activity override")
    func healthOverrideNotActivity() {
        let override = UserOverrideDefinition(
            id: "sick",
            name: "Sick Day",
            settings: OverrideSettings(basalMultiplier: 1.2),
            isSystemDefault: false,
            category: .health
        )
        
        #expect(override.isActivityOverride == false)
        #expect(override.category == .health)
    }
    
    @Test("override categories")
    func overrideCategories() {
        #expect(OverrideCategory.activity.rawValue == "activity")
        #expect(OverrideCategory.health.rawValue == "health")
        #expect(OverrideCategory.meal.rawValue == "meal")
        #expect(OverrideCategory.sleep.rawValue == "sleep")
        #expect(OverrideCategory.custom.rawValue == "custom")
    }
}

// MARK: - Training Status Tests (ALG-LEARN-013)

@Suite("TrainingStatus")
struct TrainingStatusTests {
    
    @Test("hunch status for 0 sessions")
    func hunchForZeroSessions() {
        let status = TrainingStatus.from(sessionCount: 0, avgSuccessScore: 0)
        if case .hunch(let sessions) = status {
            #expect(sessions == 0)
        } else {
            Issue.record("Expected hunch status")
        }
    }
    
    @Test("hunch status for 1-4 sessions")
    func hunchForFewSessions() {
        for count in 1..<5 {
            let status = TrainingStatus.from(sessionCount: count, avgSuccessScore: 0.8)
            if case .hunch(let sessions) = status {
                #expect(sessions == count)
            } else {
                Issue.record("Expected hunch status for \(count) sessions")
            }
        }
    }
    
    @Test("trained status for 5-9 sessions")
    func trainedForMidSessions() {
        for count in 5..<10 {
            let status = TrainingStatus.from(sessionCount: count, avgSuccessScore: 0.65)
            if case .trained(let sessions, let confidence) = status {
                #expect(sessions == count)
                #expect(confidence == 0.65)
            } else {
                Issue.record("Expected trained status for \(count) sessions")
            }
        }
    }
    
    @Test("graduated status for 10+ sessions with high confidence")
    func graduatedForManySessions() {
        let status = TrainingStatus.from(sessionCount: 10, avgSuccessScore: 0.8)
        if case .graduated(let confidence) = status {
            #expect(confidence == 0.8)
        } else {
            Issue.record("Expected graduated status")
        }
    }
    
    @Test("trained not graduated if low confidence")
    func trainedNotGraduatedLowConfidence() {
        let status = TrainingStatus.from(sessionCount: 15, avgSuccessScore: 0.5)
        if case .trained(let sessions, let confidence) = status {
            #expect(sessions == 15)
            #expect(confidence == 0.5)
        } else {
            Issue.record("Expected trained status (low confidence)")
        }
    }
    
    @Test("canSuggest property")
    func canSuggestProperty() {
        #expect(TrainingStatus.hunch(sessions: 3).canSuggest == false)
        #expect(TrainingStatus.trained(sessions: 5, confidence: 0.7).canSuggest == true)
        #expect(TrainingStatus.graduated(confidence: 0.9).canSuggest == true)
    }
    
    @Test("sessionsToNextLevel")
    func sessionsToNextLevel() {
        #expect(TrainingStatus.hunch(sessions: 2).sessionsToNextLevel == 3)
        #expect(TrainingStatus.trained(sessions: 7, confidence: 0.7).sessionsToNextLevel == 3)
        #expect(TrainingStatus.graduated(confidence: 0.9).sessionsToNextLevel == nil)
    }
    
    @Test("description text")
    func descriptionText() {
        #expect(TrainingStatus.hunch(sessions: 1).description == "User hunch (1 session)")
        #expect(TrainingStatus.hunch(sessions: 3).description == "User hunch (3 sessions)")
        #expect(TrainingStatus.trained(sessions: 5, confidence: 0.75).description.contains("Training"))
        #expect(TrainingStatus.graduated(confidence: 0.85).description.contains("Learned pattern"))
    }
}

// MARK: - Settings Refinement Tests (ALG-LEARN-014)

@Suite("SettingsRefinement")
struct SettingsRefinementTests {
    
    @Test("refinement types")
    func refinementTypes() {
        #expect(SettingsRefinement.RefinementType.adjustBasal.rawValue == "adjustBasal")
        #expect(SettingsRefinement.RefinementType.adjustISF.rawValue == "adjustISF")
        #expect(SettingsRefinement.RefinementType.adjustCR.rawValue == "adjustCR")
        #expect(SettingsRefinement.RefinementType.adjustTarget.rawValue == "adjustTarget")
        #expect(SettingsRefinement.RefinementType.adjustDuration.rawValue == "adjustDuration")
    }
    
    @Test("change description for basal")
    func changeDescriptionBasal() {
        let refinement = SettingsRefinement(
            type: .adjustBasal,
            currentValue: 0.7,  // -30%
            suggestedValue: 0.6,  // -40%
            message: "Test",
            evidence: "Test",
            confidence: 0.8
        )
        
        let desc = refinement.changeDescription
        #expect(desc.contains("-10%") || desc.contains("30") && desc.contains("40"))
    }
    
    @Test("change description for target")
    func changeDescriptionTarget() {
        let refinement = SettingsRefinement(
            type: .adjustTarget,
            currentValue: 100,
            suggestedValue: 120,
            message: "Raise target",
            evidence: "Hypos",
            confidence: 0.7
        )
        
        #expect(refinement.changeDescription.contains("20"))
        #expect(refinement.changeDescription.contains("mg/dL"))
    }
}

// MARK: - Activity Agent Stub Tests (ALG-LEARN-011)

@Suite("ActivityAgentStub")
struct ActivityAgentStubTests {
    
    @Test("creates agent from override definition")
    func createsAgentFromDefinition() async {
        let definition = UserOverrideDefinition(
            id: "running",
            name: "Running",
            settings: OverrideSettings(basalMultiplier: 0.6, isfMultiplier: 1.2)
        )
        
        let stub = ActivityAgentStub(from: definition)
        
        #expect(stub.agentId == "activity-running")
        #expect(stub.name == "Running")
        #expect(stub.privacyTier == .transparent)
    }
    
    @Test("stub starts as hunch with 0 sessions")
    func stubStartsAsHunch() async {
        let definition = UserOverrideDefinition(
            id: "gym",
            name: "Gym",
            settings: OverrideSettings(basalMultiplier: 0.8)
        )
        
        let stub = ActivityAgentStub(from: definition)
        let status = await stub.trainingStatus
        
        if case .hunch(let sessions) = status {
            #expect(sessions == 0)
        } else {
            Issue.record("Expected hunch status")
        }
    }
    
    @Test("stub does not produce effects until trained")
    func noEffectsUntilTrained() async {
        let definition = UserOverrideDefinition(
            id: "yoga",
            name: "Yoga",
            settings: OverrideSettings(basalMultiplier: 0.9)
        )
        
        let stub = ActivityAgentStub(from: definition)
        let context = AgentContext()
        
        let bundle = await stub.evaluate(context: context)
        #expect(bundle == nil)
    }
    
    @Test("training progresses with sessions")
    func trainingProgressesWithSessions() async {
        let definition = UserOverrideDefinition(
            id: "swimming",
            name: "Swimming",
            settings: OverrideSettings(basalMultiplier: 0.7)
        )
        
        let stub = ActivityAgentStub(from: definition)
        
        // Add 5 complete sessions
        for i in 0..<5 {
            let session = makeCompletedSession(
                overrideId: "swimming",
                settings: definition.settings,
                successScore: 0.8 + Double(i) * 0.02
            )
            await stub.addSession(session)
        }
        
        let status = await stub.trainingStatus
        if case .trained(let sessions, _) = status {
            #expect(sessions == 5)
        } else {
            Issue.record("Expected trained status after 5 sessions")
        }
    }
    
    @Test("produces effects after training")
    func producesEffectsAfterTraining() async {
        let definition = UserOverrideDefinition(
            id: "hiking",
            name: "Hiking",
            settings: OverrideSettings(basalMultiplier: 0.75)
        )
        
        let stub = ActivityAgentStub(from: definition)
        
        // Add 5 sessions to reach trained status
        for _ in 0..<5 {
            let session = makeCompletedSession(
                overrideId: "hiking",
                settings: definition.settings,
                successScore: 0.85
            )
            await stub.addSession(session)
        }
        
        let context = AgentContext()
        let bundle = await stub.evaluate(context: context)
        
        #expect(bundle != nil)
        #expect(bundle?.effects.isEmpty == false)
    }
    
    // MARK: - Helpers
    
    private func makeCompletedSession(
        overrideId: String,
        settings: OverrideSettings,
        successScore: Double
    ) -> OverrideSession {
        var session = OverrideSession(
            overrideId: overrideId,
            overrideName: overrideId.capitalized,
            settings: settings,
            preSnapshot: GlucoseSnapshot(glucose: 120, timeInRange: 75),
            context: OverrideContext()
        )
        session.deactivatedAt = Date()
        session.postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 80)
        session.outcome = OverrideOutcome(
            timeInRange: 80,
            timeInRangeDelta: 5,
            hypoEvents: 0,
            hyperEvents: 0,
            averageGlucose: 118,
            variability: 15,
            successScore: successScore
        )
        return session
    }
}

// MARK: - Activity Agent Bootstrapper Tests (ALG-LEARN-010/011)

@Suite("ActivityAgentBootstrapper")
struct ActivityAgentBootstrapperTests {
    
    @Test("registers user activity override")
    func registersUserActivityOverride() async {
        let bootstrapper = ActivityAgentBootstrapper()
        
        let definition = UserOverrideDefinition(
            id: "cycling",
            name: "Cycling",
            settings: OverrideSettings(basalMultiplier: 0.65),
            isSystemDefault: false,
            category: .activity
        )
        
        let stub = await bootstrapper.registerOverride(definition)
        
        #expect(stub != nil)
        #expect(stub?.agentId == "activity-cycling")
    }
    
    @Test("does not register system default override")
    func doesNotRegisterSystemDefault() async {
        let bootstrapper = ActivityAgentBootstrapper()
        
        let definition = UserOverrideDefinition(
            id: "default-sleep",
            name: "Sleep",
            settings: OverrideSettings(basalMultiplier: 0.9),
            isSystemDefault: true,
            category: .sleep
        )
        
        let stub = await bootstrapper.registerOverride(definition)
        
        #expect(stub == nil)
    }
    
    @Test("detects user activity overrides")
    func detectsUserActivityOverrides() async {
        let bootstrapper = ActivityAgentBootstrapper()
        
        let tennis = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.7),
            isSystemDefault: false,
            category: .activity
        )
        
        let sickDay = UserOverrideDefinition(
            id: "sick",
            name: "Sick Day",
            settings: OverrideSettings(basalMultiplier: 1.3),
            isSystemDefault: false,
            category: .health
        )
        
        _ = await bootstrapper.registerOverride(tennis)
        _ = await bootstrapper.registerOverride(sickDay)
        
        #expect(await bootstrapper.isUserActivity("tennis") == true)
        #expect(await bootstrapper.isUserActivity("sick") == false)
    }
    
    @Test("processes session for training")
    func processesSessionForTraining() async {
        let bootstrapper = ActivityAgentBootstrapper()
        
        let definition = UserOverrideDefinition(
            id: "weights",
            name: "Weight Training",
            settings: OverrideSettings(basalMultiplier: 0.8),
            isSystemDefault: false,
            category: .activity
        )
        
        _ = await bootstrapper.registerOverride(definition)
        
        var session = OverrideSession(
            overrideId: "weights",
            overrideName: "Weight Training",
            settings: definition.settings,
            preSnapshot: GlucoseSnapshot(glucose: 125, timeInRange: 70),
            context: OverrideContext()
        )
        session.deactivatedAt = Date()
        session.postSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 78)
        session.outcome = OverrideOutcome(
            timeInRange: 78,
            timeInRangeDelta: 8,
            hypoEvents: 0,
            hyperEvents: 0,
            averageGlucose: 122,
            variability: 18,
            successScore: 0.82
        )
        
        await bootstrapper.processSession(session)
        
        let agent = await bootstrapper.agent(for: "weights")
        let count = await agent?.sessionCount
        #expect(count == 1)
    }
    
    @Test("generates refinements after training")
    func generatesRefinementsAfterTraining() async {
        let bootstrapper = ActivityAgentBootstrapper()
        
        let definition = UserOverrideDefinition(
            id: "soccer",
            name: "Soccer",
            settings: OverrideSettings(basalMultiplier: 0.6),  // -40% - quite aggressive
            isSystemDefault: false,
            category: .activity
        )
        
        _ = await bootstrapper.registerOverride(definition)
        
        // Add sessions with frequent hypos (suggesting -40% is too aggressive)
        for i in 0..<5 {
            var session = OverrideSession(
                overrideId: "soccer",
                overrideName: "Soccer",
                settings: definition.settings,
                preSnapshot: GlucoseSnapshot(glucose: 130, timeInRange: 72),
                context: OverrideContext()
            )
            session.deactivatedAt = Date()
            session.postSnapshot = GlucoseSnapshot(glucose: 85, timeInRange: 68, hypoEvents: 1)
            session.outcome = OverrideOutcome(
                timeInRange: 68,
                timeInRangeDelta: -4,
                hypoEvents: 1,  // Frequent hypos
                hyperEvents: 0,
                averageGlucose: 95,
                variability: 25,
                successScore: 0.55 + Double(i) * 0.02
            )
            await bootstrapper.processSession(session)
        }
        
        let refinements = await bootstrapper.allRefinements()
        #expect(!refinements.isEmpty)
        
        // Should suggest less aggressive basal reduction
        let soccerRefinements = refinements.first { $0.agent == "soccer" }?.refinements ?? []
        let hasBasalRefinement = soccerRefinements.contains { $0.type == .adjustBasal }
        #expect(hasBasalRefinement == true)
    }
}

// MARK: - Integration Tests

@Suite("ActivityAgentIntegration")
struct ActivityAgentIntegrationTests {
    
    @Test("full lifecycle: hunch to graduated")
    func fullLifecycleHunchToGraduated() async {
        let definition = UserOverrideDefinition(
            id: "basketball",
            name: "Basketball",
            settings: OverrideSettings(basalMultiplier: 0.7)
        )
        
        let stub = ActivityAgentStub(from: definition)
        
        // Phase 1: Hunch (0-4 sessions)
        for i in 0..<4 {
            await stub.addSession(makeSession(
                id: "basketball",
                settings: definition.settings,
                score: 0.75 + Double(i) * 0.02
            ))
        }
        
        var status = await stub.trainingStatus
        if case .hunch = status {
            // Expected
        } else {
            Issue.record("Expected hunch after 4 sessions")
        }
        #expect(await stub.confidence == 0.0)  // No confidence yet
        
        // Phase 2: Trained (5-9 sessions)
        await stub.addSession(makeSession(
            id: "basketball",
            settings: definition.settings,
            score: 0.82
        ))
        
        status = await stub.trainingStatus
        if case .trained = status {
            // Expected
        } else {
            Issue.record("Expected trained after 5 sessions")
        }
        #expect(status.canSuggest == true)
        
        // Phase 3: Graduated (10+ sessions with high confidence)
        for i in 0..<5 {
            await stub.addSession(makeSession(
                id: "basketball",
                settings: definition.settings,
                score: 0.80 + Double(i) * 0.015
            ))
        }
        
        status = await stub.trainingStatus
        if case .graduated(let conf) = status {
            #expect(conf >= 0.7)
        } else {
            Issue.record("Expected graduated after 10 sessions with high scores")
        }
    }
    
    private func makeSession(
        id: String,
        settings: OverrideSettings,
        score: Double
    ) -> OverrideSession {
        var session = OverrideSession(
            overrideId: id,
            overrideName: id.capitalized,
            settings: settings,
            preSnapshot: GlucoseSnapshot(glucose: 120, timeInRange: 75),
            context: OverrideContext()
        )
        session.deactivatedAt = Date()
        session.postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 80)
        session.outcome = OverrideOutcome(
            timeInRange: 80,
            timeInRangeDelta: 5,
            hypoEvents: 0,
            hyperEvents: 0,
            averageGlucose: 118,
            variability: 15,
            successScore: score
        )
        return session
    }
}
