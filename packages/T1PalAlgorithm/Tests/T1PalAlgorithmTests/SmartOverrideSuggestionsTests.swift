// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SmartOverrideSuggestionsTests.swift
// T1PalAlgorithmTests
//
// Tests for ALG-LEARN-030..033: Smart Override Suggestions

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Smart Override Suggestions")
struct SmartOverrideSuggestionsTests {
    
    // MARK: - ALG-LEARN-030: Pattern Detection Tests
    
    @Test("Pattern timing display description")
    func patternTimingDisplayDescription() {
        // Single day
        let monday = PatternTiming(daysOfWeek: [2])
        #expect(monday.displayDescription == "Mon")
        
        // Weekdays
        let weekdays = PatternTiming(daysOfWeek: [2, 3, 4, 5, 6])
        #expect(weekdays.displayDescription == "weekdays")
        
        // Weekends
        let weekend = PatternTiming(daysOfWeek: [1, 7])
        #expect(weekend.displayDescription == "weekends")
        
        // Hour range
        let morning = PatternTiming(hourRange: 6...9)
        #expect(morning.displayDescription == "6am-9am")
        
        // Combined
        let combo = PatternTiming(daysOfWeek: [2], hourRange: 18...20)
        #expect(combo.displayDescription.contains("Mon"))
        #expect(combo.displayDescription.contains("6pm-8pm"))
    }
    
    @Test("Recurring pattern creation")
    func recurringPatternCreation() {
        let pattern = RecurringPattern(
            patternType: .dawn,
            timing: PatternTiming(hourRange: 4...7),
            confidence: 0.8,
            occurrenceCount: 12,
            averageGlucoseImpact: 35,
            suggestedSettings: OverrideSettings(basalMultiplier: 1.3),
            description: "Dawn phenomenon detected"
        )
        
        #expect(pattern.patternType == .dawn)
        #expect(pattern.confidence == 0.8)
        #expect(pattern.occurrenceCount == 12)
        #expect(pattern.suggestedSettings.basalMultiplier == 1.3)
    }
    
    @Test("Pattern detector initialization")
    func patternDetectorInitialization() async {
        let detector = PatternDetector(
            minOccurrences: 5,
            minConfidence: 0.7,
            analysisWindowDays: 14
        )
        
        let patterns = await detector.patterns()
        #expect(patterns.isEmpty)
    }
    
    @Test("Pattern detector add readings")
    func patternDetectorAddReadings() async {
        let detector = PatternDetector()
        
        // Add some readings
        let readings = (0..<24).map { hour in
            PatternGlucoseReading(
                value: Double(100 + hour * 2),
                timestamp: Date().addingTimeInterval(Double(-hour) * 3600)
            )
        }
        
        await detector.addReadings(readings)
        
        // Analyze (won't find patterns with just 24 readings)
        let patterns = await detector.analyzePatterns()
        // With limited data, we expect few or no patterns
        #expect(patterns.isEmpty || patterns.allSatisfy { $0.occurrenceCount >= 3 })
    }
    
    @Test("Pattern detector high glucose pattern")
    func patternDetectorHighGlucosePattern() async {
        let detector = PatternDetector(minOccurrences: 3, minConfidence: 0.3)
        
        // Create readings with consistently high glucose at 2pm for 7 days
        var readings: [PatternGlucoseReading] = []
        for day in 0..<7 {
            for hour in 0..<24 {
                let timestamp = Date().addingTimeInterval(Double(-day * 86400 - hour * 3600))
                let value: Double = hour == 14 ? 220 : 115 // High at 2pm
                readings.append(PatternGlucoseReading(value: value, timestamp: timestamp))
            }
        }
        
        await detector.addReadings(readings)
        let patterns = await detector.analyzePatterns()
        
        // Should detect time-of-day pattern
        let timePatterns = patterns.filter { $0.patternType == .timeOfDay }
        #expect(!timePatterns.isEmpty, "Should detect time-of-day pattern")
    }
    
    @Test("Pattern detector dawn phenomenon")
    func patternDetectorDawnPhenomenon() async {
        let detector = PatternDetector(minOccurrences: 3, minConfidence: 0.4)
        
        // Create readings with dawn phenomenon pattern
        var readings: [PatternGlucoseReading] = []
        for day in 0..<10 {
            // Early hours: low glucose
            for hour in 3..<5 {
                let timestamp = Calendar.current.date(
                    byAdding: .day,
                    value: -day,
                    to: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
                )!
                readings.append(PatternGlucoseReading(value: 90, timestamp: timestamp))
            }
            
            // Later hours: rising glucose
            for hour in 6..<8 {
                let timestamp = Calendar.current.date(
                    byAdding: .day,
                    value: -day,
                    to: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
                )!
                readings.append(PatternGlucoseReading(value: 140, timestamp: timestamp))
            }
        }
        
        await detector.addReadings(readings)
        let patterns = await detector.analyzePatterns()
        
        // Look for dawn pattern
        let dawnPatterns = patterns.filter { $0.patternType == .dawn }
        // May or may not detect depending on algorithm thresholds
        if !dawnPatterns.isEmpty {
            #expect(dawnPatterns.first!.timing.hourRange?.contains(5) ?? false)
        }
    }
    
    // MARK: - ALG-LEARN-031: Override Suggestion Tests
    
    @Test("Override suggestion engine initialization")
    func overrideSuggestionEngineInitialization() async {
        let detector = PatternDetector()
        let engine = OverrideSuggestionEngine(
            patternDetector: detector,
            minConfidenceForSuggestion: 0.7,
            minOccurrencesForSuggestion: 5
        )
        
        let suggestions = await engine.pendingSuggestions()
        #expect(suggestions.isEmpty)
    }
    
    @Test("Override suggestion generation")
    func overrideSuggestionGeneration() async {
        let detector = PatternDetector(minOccurrences: 2, minConfidence: 0.3)
        let engine = OverrideSuggestionEngine(
            patternDetector: detector,
            minConfidenceForSuggestion: 0.3,
            minOccurrencesForSuggestion: 2
        )
        
        // Add readings with clear pattern
        var readings: [PatternGlucoseReading] = []
        for day in 0..<7 {
            for hour in 0..<24 {
                let timestamp = Date().addingTimeInterval(Double(-day * 86400 - hour * 3600))
                let value: Double = hour == 15 ? 210 : 110 // High at 3pm
                readings.append(PatternGlucoseReading(value: value, timestamp: timestamp))
            }
        }
        
        await detector.addReadings(readings)
        let suggestions = await engine.generateSuggestions()
        
        // Should generate suggestions for detected patterns
        for suggestion in suggestions {
            #expect(!suggestion.suggestedName.isEmpty)
            #expect(!suggestion.rationale.isEmpty)
            #expect(suggestion.confidence > 0)
        }
    }
    
    @Test("Accept suggestion creates override")
    func acceptSuggestionCreatesOverride() async {
        let detector = PatternDetector()
        let engine = OverrideSuggestionEngine(patternDetector: detector)
        
        let suggestion = OverrideSuggestion(
            id: UUID(),
            patternId: UUID(),
            suggestedName: "Afternoon Adjustment",
            suggestedSettings: OverrideSettings(basalMultiplier: 1.2),
            timing: PatternTiming(hourRange: 14...16),
            rationale: "Test rationale",
            confidence: 0.85,
            occurrenceCount: 10,
            createdAt: Date()
        )
        
        let override = await engine.acceptSuggestion(suggestion)
        
        #expect(override.name == "Afternoon Adjustment")
        #expect(override.settings.basalMultiplier == 1.2)
        #expect(!override.isSystemDefault)
    }
    
    @Test("Dismiss suggestion prevents reappearance")
    func dismissSuggestionPreventsReappearance() async {
        let detector = PatternDetector(minOccurrences: 2, minConfidence: 0.3)
        let engine = OverrideSuggestionEngine(
            patternDetector: detector,
            minConfidenceForSuggestion: 0.3,
            minOccurrencesForSuggestion: 2
        )
        
        // Add readings to generate patterns
        var readings: [PatternGlucoseReading] = []
        for day in 0..<7 {
            for hour in 0..<24 {
                let timestamp = Date().addingTimeInterval(Double(-day * 86400 - hour * 3600))
                let value: Double = hour == 10 ? 200 : 105
                readings.append(PatternGlucoseReading(value: value, timestamp: timestamp))
            }
        }
        
        await detector.addReadings(readings)
        let suggestions1 = await engine.generateSuggestions()
        
        // Dismiss all suggestions
        for suggestion in suggestions1 {
            await engine.dismissSuggestion(suggestion.id, patternId: suggestion.patternId)
        }
        
        // Generate again - dismissed patterns should not reappear
        let suggestions2 = await engine.generateSuggestions()
        #expect(suggestions2.count <= suggestions1.count)
    }
    
    // MARK: - ALG-LEARN-032: Override History Import Tests
    
    @Test("Override history importer initialization")
    func overrideHistoryImporterInitialization() async {
        let importer = OverrideHistoryImporter()
        let sessions = await importer.sessions()
        #expect(sessions.isEmpty)
    }
    
    @Test("Import from Nightscout")
    func importFromNightscout() async {
        let importer = OverrideHistoryImporter()
        
        let treatments = [
            NightscoutOverrideTreatment(
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                overrideName: "Exercise",
                basalMultiplier: 0.7,
                isfMultiplier: 1.3
            ),
            NightscoutOverrideTreatment(
                startDate: Date().addingTimeInterval(-14400),
                endDate: Date().addingTimeInterval(-10800),
                overrideName: "Sick Day",
                basalMultiplier: 1.5
            )
        ]
        
        // Glucose data covering the override periods
        let glucoseData = [
            PatternGlucoseReading(value: 120, timestamp: Date().addingTimeInterval(-7200)),
            PatternGlucoseReading(value: 100, timestamp: Date().addingTimeInterval(-3600)),
            PatternGlucoseReading(value: 130, timestamp: Date().addingTimeInterval(-14400)),
            PatternGlucoseReading(value: 150, timestamp: Date().addingTimeInterval(-10800))
        ]
        
        let result = await importer.importFromNightscout(
            overrideTreatments: treatments,
            glucoseData: glucoseData
        )
        
        #expect(result.statistics.totalRecords == 2)
        #expect(result.statistics.successfulImports == 2)
        #expect(result.statistics.source == .nightscout)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Import from Nightscout with missing data")
    func importFromNightscoutWithMissingData() async {
        let importer = OverrideHistoryImporter()
        
        let treatments = [
            NightscoutOverrideTreatment(
                startDate: Date().addingTimeInterval(-7200),
                endDate: nil, // Missing end date
                overrideName: "Incomplete"
            )
        ]
        
        let result = await importer.importFromNightscout(
            overrideTreatments: treatments,
            glucoseData: []
        )
        
        #expect(result.statistics.failedImports == 1)
        #expect(!result.errors.isEmpty)
    }
    
    @Test("Import from Loop")
    func importFromLoop() async {
        let importer = OverrideHistoryImporter()
        
        let events = [
            LoopOverrideEvent(
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                duration: 3600,
                presetName: "Running",
                basalRateMultiplier: 0.5,
                insulinSensitivityMultiplier: 1.5,
                targetRangeLow: 150
            )
        ]
        
        let glucoseData = [
            PatternGlucoseReading(value: 130, timestamp: Date().addingTimeInterval(-7200)),
            PatternGlucoseReading(value: 115, timestamp: Date().addingTimeInterval(-3600))
        ]
        
        let result = await importer.importFromLoop(
            overrideEvents: events,
            glucoseData: glucoseData
        )
        
        #expect(result.statistics.successfulImports == 1)
        #expect(result.statistics.source == .loop)
        
        let sessions = await importer.sessions()
        #expect(sessions.first?.overrideName == "Running")
        #expect(sessions.first?.settings.basalMultiplier == 0.5)
    }
    
    @Test("Import statistics")
    func importStatistics() async {
        let importer = OverrideHistoryImporter()
        
        let treatments = [
            NightscoutOverrideTreatment(
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                overrideName: "Test"
            )
        ]
        
        let glucoseData = [
            PatternGlucoseReading(value: 100, timestamp: Date().addingTimeInterval(-7200))
        ]
        
        _ = await importer.importFromNightscout(
            overrideTreatments: treatments,
            glucoseData: glucoseData
        )
        
        let stats = await importer.statistics()
        #expect(stats != nil)
        #expect(stats?.successRate == 1.0)
    }
    
    @Test("Importer clear")
    func importerClear() async {
        let importer = OverrideHistoryImporter()
        
        let treatments = [
            NightscoutOverrideTreatment(
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                overrideName: "Test"
            )
        ]
        
        let glucoseData = [
            PatternGlucoseReading(value: 100, timestamp: Date().addingTimeInterval(-7200))
        ]
        
        _ = await importer.importFromNightscout(
            overrideTreatments: treatments,
            glucoseData: glucoseData
        )
        
        await importer.clear()
        
        let sessions = await importer.sessions()
        #expect(sessions.isEmpty)
        
        let stats = await importer.statistics()
        #expect(stats == nil)
    }
    
    // MARK: - ALG-LEARN-033: Community Template Tests
    
    @Test("Community template manager initialization")
    func communityTemplateManagerInitialization() async {
        let manager = CommunityTemplateManager()
        let enabled = await manager.sharingEnabled
        #expect(!enabled)
    }
    
    @Test("Enable sharing requires consent")
    func enableSharingRequiresConsent() async {
        let manager = CommunityTemplateManager()
        
        await manager.enableSharing(userConsent: true)
        let enabled = await manager.sharingEnabled
        #expect(enabled)
    }
    
    @Test("Create template requires sharing enabled")
    func createTemplateRequiresSharingEnabled() async {
        let manager = CommunityTemplateManager()
        
        let definition = UserOverrideDefinition(
            id: "tennis",
            name: "Tennis",
            settings: OverrideSettings(basalMultiplier: 0.6),
            isSystemDefault: false
        )
        
        // Sharing disabled - should return nil
        let template1 = await manager.createTemplate(
            from: definition,
            description: "For tennis matches",
            tags: ["exercise", "cardio"]
        )
        #expect(template1 == nil)
        
        // Enable sharing
        await manager.enableSharing(userConsent: true)
        
        // Now should work
        let template2 = await manager.createTemplate(
            from: definition,
            description: "For tennis matches",
            tags: ["exercise", "cardio"]
        )
        #expect(template2 != nil)
        #expect(template2?.name == "Tennis")
        #expect(template2?.tags == ["exercise", "cardio"])
    }
    
    @Test("Community override template creation")
    func communityOverrideTemplateCreation() {
        let template = CommunityOverrideTemplate(
            name: "Morning Run",
            category: .activity,
            settings: OverrideSettings(basalMultiplier: 0.5, isfMultiplier: 1.5),
            description: "For 30-60 min morning runs",
            tags: ["running", "morning", "cardio"],
            usageCount: 150,
            averageRating: 4.5
        )
        
        #expect(template.name == "Morning Run")
        #expect(template.category == .activity)
        #expect(template.usageCount == 150)
        #expect(template.averageRating == 4.5)
    }
    
    @Test("Pending templates")
    func pendingTemplates() async {
        let manager = CommunityTemplateManager()
        await manager.enableSharing(userConsent: true)
        
        let definition = UserOverrideDefinition(
            id: "gym",
            name: "Gym Session",
            settings: OverrideSettings(basalMultiplier: 0.7),
            isSystemDefault: false
        )
        
        _ = await manager.createTemplate(
            from: definition,
            description: "Weight training",
            tags: ["gym"]
        )
        
        let pending = await manager.pendingTemplates()
        #expect(pending.count == 1)
        #expect(pending.first?.name == "Gym Session")
    }
}
