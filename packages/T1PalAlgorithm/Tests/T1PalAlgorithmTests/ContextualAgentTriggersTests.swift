// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ContextualAgentTriggersTests.swift
// T1PalAlgorithmTests
//
// Tests for ALG-LEARN-040..044: Contextual Agent Triggers

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Contextual Agent Triggers")
struct ContextualAgentTriggersTests {
    
    // MARK: - ALG-LEARN-040: HealthKit Workout Tests
    
    @Test("Workout activity type category")
    func workoutActivityTypeCategory() {
        #expect(WorkoutActivityType.running.category == .cardio)
        #expect(WorkoutActivityType.cycling.category == .cardio)
        #expect(WorkoutActivityType.tennis.category == .sport)
        #expect(WorkoutActivityType.yoga.category == .flexibility)
        #expect(WorkoutActivityType.traditionalStrengthTraining.category == .strength)
    }
    
    @Test("Mock workout trigger source initialization")
    func mockWorkoutTriggerSourceInitialization() async {
        let source = MockWorkoutTriggerSource()
        
        let isActive = await source.isActive
        #expect(!isActive)
        
        let types = await source.registeredTypes
        #expect(types.isEmpty)
    }
    
    @Test("Mock workout trigger source monitoring")
    func mockWorkoutTriggerSourceMonitoring() async throws {
        let source = MockWorkoutTriggerSource()
        
        try await source.startMonitoring()
        let isActive = await source.isActive
        #expect(isActive)
        
        await source.stopMonitoring()
        let isActiveAfter = await source.isActive
        #expect(!isActiveAfter)
    }
    
    @Test("Mock workout trigger source registration")
    func mockWorkoutTriggerSourceRegistration() async {
        let source = MockWorkoutTriggerSource()
        
        await source.registerActivityTypes([.running, .tennis, .cycling])
        
        let types = await source.registeredTypes
        #expect(types.count == 3)
        #expect(types.contains(.tennis))
    }
    
    @Test("Mock workout trigger source simulation")
    func mockWorkoutTriggerSourceSimulation() async throws {
        let source = MockWorkoutTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        try await source.startMonitoring()
        
        await source.simulateWorkoutStart(type: .tennis, activityId: "tennis-activity")
        
        // Give async a moment
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .workoutStart)
        #expect(triggers.first?.matchedActivityId == "tennis-activity")
    }
    
    // MARK: - ALG-LEARN-041: Calendar Event Tests
    
    @Test("Calendar event pattern matching")
    func calendarEventPatternMatching() {
        let pattern = CalendarEventPattern(
            titleKeywords: ["tennis", "racquet"],
            locationKeywords: ["court", "club"],
            activityId: "tennis"
        )
        
        #expect(pattern.matches(title: "Tennis with Mike", location: nil))
        #expect(pattern.matches(title: "Meeting", location: "Tennis Court"))
        #expect(!pattern.matches(title: "Dentist", location: "Office"))
    }
    
    @Test("Mock calendar trigger source registration")
    func mockCalendarTriggerSourceRegistration() async {
        let source = MockCalendarTriggerSource()
        
        let pattern = CalendarEventPattern(
            titleKeywords: ["gym"],
            activityId: "gym-session"
        )
        
        await source.registerEventPatterns([pattern])
        
        let patterns = await source.registeredPatterns
        #expect(patterns.count == 1)
    }
    
    @Test("Mock calendar trigger source simulation")
    func mockCalendarTriggerSourceSimulation() async throws {
        let source = MockCalendarTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        
        let pattern = CalendarEventPattern(
            titleKeywords: ["gym", "workout"],
            activityId: "gym-session",
            confidence: 0.85
        )
        await source.registerEventPatterns([pattern])
        
        try await source.startMonitoring()
        
        await source.simulateUpcomingEvent(
            title: "Morning Gym Session",
            location: "24 Hour Fitness",
            startsIn: 15
        )
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .calendarEvent)
        #expect(triggers.first?.matchedActivityId == "gym-session")
        #expect(triggers.first?.confidence == 0.85)
    }
    
    // MARK: - ALG-LEARN-042: Location Trigger Tests
    
    @Test("Geofence contains")
    func geofenceContains() {
        let geofence = Geofence(
            name: "Gym",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 100,
            activityId: "gym"
        )
        
        // Same location
        #expect(geofence.contains(latitude: 37.7749, longitude: -122.4194))
        
        // Very close (within 100m)
        #expect(geofence.contains(latitude: 37.7750, longitude: -122.4194))
        
        // Far away
        #expect(!geofence.contains(latitude: 37.8, longitude: -122.4))
    }
    
    @Test("Mock location trigger source registration")
    func mockLocationTriggerSourceRegistration() async {
        let source = MockLocationTriggerSource()
        
        let geofence = Geofence(
            name: "Tennis Club",
            latitude: 37.0,
            longitude: -122.0,
            activityId: "tennis"
        )
        
        await source.registerGeofences([geofence])
        
        let fences = await source.registeredGeofences
        #expect(fences.count == 1)
        #expect(fences.first?.name == "Tennis Club")
    }
    
    @Test("Mock location trigger source entry simulation")
    func mockLocationTriggerSourceEntrySimulation() async throws {
        let source = MockLocationTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        
        let geofence = Geofence(
            name: "Gym",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 100,
            activityId: "gym-workout",
            triggerOn: .entry
        )
        await source.registerGeofences([geofence])
        
        try await source.startMonitoring()
        
        // Enter the geofence
        await source.simulateLocationEntry(latitude: 37.7749, longitude: -122.4194)
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .location)
        #expect(triggers.first?.matchedActivityId == "gym-workout")
    }
    
    @Test("Mock location trigger source exit simulation")
    func mockLocationTriggerSourceExitSimulation() async throws {
        let source = MockLocationTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        
        let geofence = Geofence(
            id: UUID(),
            name: "Gym",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 100,
            activityId: "gym-workout",
            triggerOn: .exit
        )
        await source.registerGeofences([geofence])
        
        try await source.startMonitoring()
        
        // Exit the geofence
        await source.simulateLocationExit(geofenceId: geofence.id)
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .location)
    }
    
    // MARK: - ALG-LEARN-043: Scheduled Trigger Tests
    
    @Test("Scheduled trigger matching")
    func scheduledTriggerMatching() {
        // Every day at 6:30am
        let daily = ScheduledTrigger(
            name: "Morning Run",
            hour: 6,
            minute: 30,
            activityId: "morning-run"
        )
        
        #expect(daily.matches(hour: 6, minute: 30, dayOfWeek: 2))
        #expect(daily.matches(hour: 6, minute: 30, dayOfWeek: 7))
        #expect(!daily.matches(hour: 7, minute: 30, dayOfWeek: 2))
        
        // Only on weekends
        let weekend = ScheduledTrigger(
            name: "Weekend Tennis",
            hour: 10,
            minute: 0,
            daysOfWeek: [1, 7], // Sunday, Saturday
            activityId: "tennis"
        )
        
        #expect(weekend.matches(hour: 10, minute: 0, dayOfWeek: 1))
        #expect(weekend.matches(hour: 10, minute: 0, dayOfWeek: 7))
        #expect(!weekend.matches(hour: 10, minute: 0, dayOfWeek: 3))
    }
    
    @Test("Scheduled trigger display description")
    func scheduledTriggerDisplayDescription() {
        let daily = ScheduledTrigger(
            name: "Morning",
            hour: 6,
            minute: 30,
            activityId: "morning"
        )
        #expect(daily.displayDescription == "6:30am daily")
        
        let weekend = ScheduledTrigger(
            name: "Weekend",
            hour: 14,
            minute: 0,
            daysOfWeek: [1, 7],
            activityId: "weekend"
        )
        #expect(weekend.displayDescription.contains("2:00pm"))
        #expect(weekend.displayDescription.contains("Sun"))
    }
    
    @Test("Mock scheduled trigger source simulation")
    func mockScheduledTriggerSourceSimulation() async throws {
        let source = MockScheduledTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        
        let schedule = ScheduledTrigger(
            name: "Tuesday Evening Tennis",
            hour: 18,
            minute: 0,
            daysOfWeek: [3], // Tuesday
            activityId: "tennis",
            confidence: 0.95
        )
        await source.registerSchedules([schedule])
        
        try await source.startMonitoring()
        
        // Simulate Tuesday at 6pm
        await source.simulateTime(hour: 18, minute: 0, dayOfWeek: 3)
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .timeOfDay)
        #expect(triggers.first?.matchedActivityId == "tennis")
        #expect(triggers.first?.confidence == 0.95)
    }
    
    @Test("Scheduled trigger disabled")
    func scheduledTriggerDisabled() {
        let disabled = ScheduledTrigger(
            name: "Disabled",
            hour: 10,
            minute: 0,
            activityId: "test",
            isEnabled: false
        )
        
        #expect(!disabled.matches(hour: 10, minute: 0, dayOfWeek: 1))
    }
    
    // MARK: - ALG-LEARN-044: Voice/Siri Trigger Tests
    
    @Test("Voice command matching")
    func voiceCommandMatching() {
        let command = VoiceCommand(
            phrase: "Starting tennis",
            alternatives: ["Begin tennis", "Tennis time"],
            activityId: "tennis"
        )
        
        #expect(command.matches("Starting tennis"))
        #expect(command.matches("starting tennis")) // Case insensitive
        #expect(command.matches("Begin tennis"))
        #expect(command.matches("Tennis time"))
        #expect(!command.matches("Going to play tennis"))
    }
    
    @Test("Mock voice trigger source registration")
    func mockVoiceTriggerSourceRegistration() async {
        let source = MockVoiceTriggerSource()
        
        let command = VoiceCommand(
            phrase: "Starting run",
            activityId: "running"
        )
        
        await source.registerCommands([command])
        
        let commands = await source.registeredCommands
        #expect(commands.count == 1)
    }
    
    @Test("Mock voice trigger source simulation")
    func mockVoiceTriggerSourceSimulation() async throws {
        let source = MockVoiceTriggerSource()
        let delegate = MockTriggerDelegate()
        
        await source.setDelegate(delegate)
        
        let command = VoiceCommand(
            phrase: "Starting tennis",
            alternatives: ["Tennis time"],
            activityId: "tennis",
            confidence: 1.0
        )
        await source.registerCommands([command])
        
        try await source.startMonitoring()
        
        await source.simulateVoiceCommand("Tennis time")
        
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let triggers = await delegate.receivedTriggers
        #expect(triggers.count == 1)
        #expect(triggers.first?.type == .siri)
        #expect(triggers.first?.matchedActivityId == "tennis")
    }
    
    @Test("Mock voice trigger source donation")
    func mockVoiceTriggerSourceDonation() async {
        let source = MockVoiceTriggerSource()
        
        await source.donateShortcut(for: "tennis", phrase: "Starting tennis")
        await source.donateShortcut(for: "running", phrase: "Going for a run")
        
        let donated = await source.donatedPhrases()
        #expect(donated.count == 2)
        #expect(donated["tennis"] == "Starting tennis")
    }
    
    // MARK: - Trigger Manager Tests
    
    @Test("Trigger manager registration")
    func triggerManagerRegistration() async {
        let bootstrapper = ActivityAgentBootstrapper()
        let proposalGenerator = ActivityProposalGenerator(bootstrapper: bootstrapper)
        let manager = TriggerManager(proposalGenerator: proposalGenerator)
        
        let workoutSource = MockWorkoutTriggerSource()
        let calendarSource = MockCalendarTriggerSource()
        
        await manager.registerSource(workoutSource)
        await manager.registerSource(calendarSource)
        
        try? await manager.startAllSources()
        
        let active = await manager.activeSources()
        #expect(active.count == 2)
        #expect(active.contains("mock-workout"))
        #expect(active.contains("mock-calendar"))
    }
    
    @Test("Trigger manager stops all sources")
    func triggerManagerStopsAllSources() async throws {
        let bootstrapper = ActivityAgentBootstrapper()
        let proposalGenerator = ActivityProposalGenerator(bootstrapper: bootstrapper)
        let manager = TriggerManager(proposalGenerator: proposalGenerator)
        
        let source = MockWorkoutTriggerSource()
        await manager.registerSource(source)
        
        try await manager.startAllSources()
        var active = await manager.activeSources()
        #expect(active.count == 1)
        
        await manager.stopAllSources()
        active = await manager.activeSources()
        #expect(active.count == 0)
    }
    
    // MARK: - Trigger Configuration Tests
    
    @Test("Trigger configuration application")
    func triggerConfigurationApplication() async {
        let config = TriggerConfiguration(
            workoutTypes: [.running, .cycling],
            calendarPatterns: [
                CalendarEventPattern(titleKeywords: ["gym"], activityId: "gym")
            ],
            geofences: [
                Geofence(name: "Home", latitude: 37.0, longitude: -122.0, activityId: "home")
            ],
            schedules: [
                ScheduledTrigger(name: "Morning", hour: 6, activityId: "morning")
            ],
            voiceCommands: [
                VoiceCommand(phrase: "Start workout", activityId: "workout")
            ]
        )
        
        let workout = MockWorkoutTriggerSource()
        let calendar = MockCalendarTriggerSource()
        let location = MockLocationTriggerSource()
        let scheduled = MockScheduledTriggerSource()
        let voice = MockVoiceTriggerSource()
        
        await config.apply(
            to: workout,
            calendarSource: calendar,
            locationSource: location,
            scheduledSource: scheduled,
            voiceSource: voice
        )
        
        let workoutTypes = await workout.registeredTypes
        #expect(workoutTypes.count == 2)
        
        let patterns = await calendar.registeredPatterns
        #expect(patterns.count == 1)
        
        let fences = await location.registeredGeofences
        #expect(fences.count == 1)
        
        let schedules = await scheduled.registeredSchedules
        #expect(schedules.count == 1)
        
        let commands = await voice.registeredCommands
        #expect(commands.count == 1)
    }
}

// MARK: - Test Helpers

actor MockTriggerDelegate: TriggerSourceDelegate {
    var receivedTriggers: [ActivityTrigger] = []
    
    nonisolated func triggerSource(
        _ source: any TriggerSource,
        didDetect trigger: ActivityTrigger
    ) async {
        await addTrigger(trigger)
    }
    
    func addTrigger(_ trigger: ActivityTrigger) {
        receivedTriggers.append(trigger)
    }
}
