// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OverrideOutcomeTrackerTests.swift
// T1PalAlgorithmTests
//
// Tests for override outcome tracking infrastructure
// Backlog: ALG-LEARN-001..005

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Override Outcome Tracker")
struct OverrideOutcomeTrackerTests {
    
    // MARK: - Override Session Tests
    
    @Test("Override session creation")
    func overrideSessionCreation() {
        let settings = OverrideSettings(
            basalMultiplier: 0.7,
            isfMultiplier: 1.0,
            crMultiplier: 1.0,
            targetGlucose: 150,
            scheduledDuration: 7200
        )
        
        let preSnapshot = GlucoseSnapshot(
            glucose: 120,
            trend: -2,
            timeInRange: 75,
            hypoEvents: 0,
            hyperEvents: 1
        )
        
        let context = OverrideContext(
            activationSource: .manual,
            iobAtActivation: 2.5,
            cobAtActivation: 30
        )
        
        let session = OverrideSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        
        #expect(session.overrideId == "tennis")
        #expect(session.overrideName == "Tennis")
        #expect(session.settings.basalMultiplier == 0.7)
        #expect(session.preSnapshot.glucose == 120)
        #expect(!session.isComplete)
        #expect(session.duration == nil)
    }
    
    @Test("Glucose snapshot creation")
    func glucoseSnapshotCreation() {
        let snapshot = GlucoseSnapshot(
            glucose: 145,
            trend: 3,
            timeInRange: 82,
            hypoEvents: 1,
            hyperEvents: 2,
            coefficientOfVariation: 25,
            windowDuration: 3600
        )
        
        #expect(snapshot.glucose == 145)
        #expect(snapshot.trend == 3)
        #expect(snapshot.timeInRange == 82)
        #expect(snapshot.hypoEvents == 1)
        #expect(snapshot.hyperEvents == 2)
        #expect(snapshot.coefficientOfVariation == 25)
    }
    
    @Test("Override settings equality")
    func overrideSettingsEquality() {
        let settings1 = OverrideSettings(basalMultiplier: 0.7)
        let settings2 = OverrideSettings(basalMultiplier: 0.7)
        let settings3 = OverrideSettings(basalMultiplier: 0.8)
        
        #expect(settings1 == settings2)
        #expect(settings1 != settings3)
    }
    
    @Test("Override context time of day")
    func overrideContextTimeOfDay() {
        // Test morning
        let morningDate = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        #expect(OverrideContext.TimeOfDay.from(date: morningDate) == .morning)
        
        // Test afternoon
        let afternoonDate = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        #expect(OverrideContext.TimeOfDay.from(date: afternoonDate) == .afternoon)
        
        // Test evening
        let eveningDate = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        #expect(OverrideContext.TimeOfDay.from(date: eveningDate) == .evening)
        
        // Test night
        let nightDate = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        #expect(OverrideContext.TimeOfDay.from(date: nightDate) == .night)
        
        // Test early morning
        let earlyMorningDate = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!
        #expect(OverrideContext.TimeOfDay.from(date: earlyMorningDate) == .earlyMorning)
    }
    
    // MARK: - Tracker Tests
    
    @Test("Start session")
    func startSession() async {
        let tracker = OverrideOutcomeTracker()
        
        let settings = OverrideSettings(basalMultiplier: 0.7)
        let preSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 75)
        let context = OverrideContext()
        
        let session = await tracker.startSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        
        #expect(session.overrideId == "tennis")
        
        // Verify active session exists
        let activeSession = await tracker.activeSession(for: "tennis")
        #expect(activeSession != nil)
        #expect(activeSession?.id == session.id)
    }
    
    @Test("End session")
    func endSession() async {
        let tracker = OverrideOutcomeTracker()
        
        let settings = OverrideSettings(basalMultiplier: 0.7)
        let preSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 75)
        let context = OverrideContext()
        
        _ = await tracker.startSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        
        // End the session
        let postSnapshot = GlucoseSnapshot(glucose: 130, timeInRange: 85, hypoEvents: 0, hyperEvents: 1)
        let endedSession = await tracker.endSession(overrideId: "tennis", postSnapshot: postSnapshot)
        
        #expect(endedSession != nil)
        #expect(endedSession!.isComplete)
        #expect(endedSession!.outcome != nil)
        #expect(endedSession!.deactivatedAt != nil)
        
        // Verify no longer active
        let activeSession = await tracker.activeSession(for: "tennis")
        #expect(activeSession == nil)
        
        // Verify in completed list
        let completed = await tracker.allCompletedSessions()
        #expect(completed.count == 1)
    }
    
    @Test("Outcome calculation")
    func outcomeCalculation() async {
        let tracker = OverrideOutcomeTracker()
        
        let settings = OverrideSettings(basalMultiplier: 0.7)
        let preSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 70, hypoEvents: 1, hyperEvents: 2)
        let context = OverrideContext()
        
        _ = await tracker.startSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        
        // End with improved TIR
        let postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 85, hypoEvents: 0, hyperEvents: 1)
        let endedSession = await tracker.endSession(overrideId: "tennis", postSnapshot: postSnapshot)
        
        let outcome = endedSession!.outcome!
        #expect(outcome.timeInRange == 85)
        #expect(outcome.timeInRangeDelta == 15)  // 85 - 70
        #expect(outcome.hypoEvents == 0)
        #expect(outcome.hyperEvents == 1)
        #expect(outcome.successScore > 0.5)
    }
    
    @Test("Session count")
    func sessionCount() async {
        let tracker = OverrideOutcomeTracker()
        
        // Create 3 sessions for tennis
        for i in 1...3 {
            let settings = OverrideSettings(basalMultiplier: 0.7)
            let preSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 70)
            let context = OverrideContext()
            
            _ = await tracker.startSession(
                overrideId: "tennis",
                overrideName: "Tennis \(i)",
                settings: settings,
                preSnapshot: preSnapshot,
                context: context
            )
            
            let postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 80)
            _ = await tracker.endSession(overrideId: "tennis", postSnapshot: postSnapshot)
        }
        
        let count = await tracker.sessionCount(for: "tennis")
        #expect(count == 3)
    }
    
    // MARK: - Learning Report Tests
    
    @Test("Learning status from session count")
    func learningStatusFromSessionCount() {
        #expect(LearningStatus.from(sessionCount: 0) == .initial)
        #expect(LearningStatus.from(sessionCount: 2) == .initial)
        #expect(LearningStatus.from(sessionCount: 3) == .learning)
        #expect(LearningStatus.from(sessionCount: 4) == .learning)
        #expect(LearningStatus.from(sessionCount: 5) == .trained)
        #expect(LearningStatus.from(sessionCount: 9) == .trained)
        #expect(LearningStatus.from(sessionCount: 10) == .confident)
        #expect(LearningStatus.from(sessionCount: 100) == .confident)
    }
    
    @Test("Report generator with no sessions")
    func reportGeneratorWithNoSessions() {
        let generator = OverrideLearningReportGenerator()
        let report = generator.generateReport(
            overrideId: "tennis",
            overrideName: "Tennis",
            sessions: []
        )
        
        #expect(report.overrideId == "tennis")
        #expect(report.totalSessions == 0)
        #expect(report.status == .initial)
        #expect(report.averageOutcome == nil)
        #expect(report.recommendations.count == 1)
        #expect(report.recommendations.first?.type == .needMoreData)
    }
    
    @Test("Report generator with enough sessions")
    func reportGeneratorWithEnoughSessions() {
        let generator = OverrideLearningReportGenerator()
        
        // Create 5 complete sessions
        var sessions: [OverrideSession] = []
        for i in 1...5 {
            var session = OverrideSession(
                overrideId: "tennis",
                overrideName: "Tennis",
                settings: OverrideSettings(basalMultiplier: 0.7),
                preSnapshot: GlucoseSnapshot(glucose: 120, timeInRange: 70),
                context: OverrideContext()
            )
            session.deactivatedAt = Date()
            session.postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 80 + Double(i))
            session.outcome = OverrideOutcome(
                timeInRange: 80 + Double(i),
                timeInRangeDelta: 10 + Double(i),
                hypoEvents: 0,
                hyperEvents: 1,
                averageGlucose: 115,
                variability: 20,
                successScore: 0.75 + Double(i) * 0.01
            )
            sessions.append(session)
        }
        
        let report = generator.generateReport(
            overrideId: "tennis",
            overrideName: "Tennis",
            sessions: sessions
        )
        
        #expect(report.totalSessions == 5)
        #expect(report.completeSessions == 5)
        #expect(report.status == .trained)
        #expect(report.averageOutcome != nil)
        #expect(report.settingsInsights != nil)
        #expect(report.contextInsights != nil)
        #expect(report.recommendations.count > 0)
    }
    
    // MARK: - Storage Tests
    
    @Test("In-memory storage")
    func inMemoryStorage() async {
        let storage = InMemoryOverrideSessionStorage()
        
        var session = OverrideSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.7),
            preSnapshot: GlucoseSnapshot(glucose: 120, timeInRange: 70),
            context: OverrideContext()
        )
        session.deactivatedAt = Date()
        
        await storage.save(session)
        
        let loaded = await storage.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.overrideId == "tennis")
        
        let forTennis = await storage.sessions(for: "tennis")
        #expect(forTennis.count == 1)
        
        let forOther = await storage.sessions(for: "running")
        #expect(forOther.count == 0)
    }
    
    @Test("Tracker with storage")
    func trackerWithStorage() async {
        let storage = InMemoryOverrideSessionStorage()
        let tracker = OverrideOutcomeTracker(storage: storage)
        
        let settings = OverrideSettings(basalMultiplier: 0.7)
        let preSnapshot = GlucoseSnapshot(glucose: 120, timeInRange: 70)
        let context = OverrideContext()
        
        _ = await tracker.startSession(
            overrideId: "tennis",
            overrideName: "Tennis",
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        
        let postSnapshot = GlucoseSnapshot(glucose: 115, timeInRange: 80)
        _ = await tracker.endSession(overrideId: "tennis", postSnapshot: postSnapshot)
        
        // Verify persisted to storage
        let stored = await storage.loadAll()
        #expect(stored.count == 1)
    }
}
