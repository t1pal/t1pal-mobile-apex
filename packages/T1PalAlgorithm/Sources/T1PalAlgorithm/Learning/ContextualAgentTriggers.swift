// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ContextualAgentTriggers.swift
// T1PalAlgorithm
//
// Platform integration for contextual agent triggers
// Backlog: ALG-LEARN-040, ALG-LEARN-041, ALG-LEARN-042, ALG-LEARN-043, ALG-LEARN-044
// Trace: PRD-028 (ML-Enhanced Dosing)

import Foundation

// MARK: - Trigger Source Protocol

/// Protocol for sources that can trigger agent proposals
public protocol TriggerSource: Actor {
    /// Unique identifier for this source
    nonisolated var sourceId: String { get }
    
    /// Human-readable name
    nonisolated var displayName: String { get }
    
    /// Whether the source is currently active/monitoring
    var isActive: Bool { get async }
    
    /// Start monitoring for triggers
    func startMonitoring() async throws
    
    /// Stop monitoring
    func stopMonitoring() async
    
    /// Set the delegate to receive trigger events
    func setDelegate(_ delegate: TriggerSourceDelegate?) async
}

/// Delegate for receiving trigger events
public protocol TriggerSourceDelegate: AnyObject, Sendable {
    /// Called when a trigger is detected
    func triggerSource(_ source: any TriggerSource, didDetect trigger: ActivityTrigger) async
}

// MARK: - ALG-LEARN-040: HealthKit Workout Trigger

/// Protocol for workout detection (HealthKit on Darwin, mock elsewhere)
public protocol WorkoutTriggerSource: TriggerSource {
    /// Register activity types to watch for
    func registerActivityTypes(_ types: [WorkoutActivityType]) async
    
    /// Currently registered types
    var registeredTypes: [WorkoutActivityType] { get async }
}

/// Workout activity types (maps to HKWorkoutActivityType)
public enum WorkoutActivityType: String, Sendable, CaseIterable, Codable {
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case walking = "walking"
    case hiking = "hiking"
    case yoga = "yoga"
    case tennis = "tennis"
    case basketball = "basketball"
    case soccer = "soccer"
    case golf = "golf"
    case gymnastics = "gymnastics"
    case dance = "dance"
    case crossTraining = "crossTraining"
    case functionalStrengthTraining = "functionalStrengthTraining"
    case traditionalStrengthTraining = "traditionalStrengthTraining"
    case other = "other"
    
    /// Category for grouping
    public var category: WorkoutCategory {
        switch self {
        case .running, .cycling, .swimming, .walking, .hiking:
            return .cardio
        case .functionalStrengthTraining, .traditionalStrengthTraining, .gymnastics:
            return .strength
        case .tennis, .basketball, .soccer, .golf:
            return .sport
        case .yoga, .dance:
            return .flexibility
        case .crossTraining, .other:
            return .mixed
        }
    }
    
    public enum WorkoutCategory: String, Sendable {
        case cardio, strength, sport, flexibility, mixed
    }
}

/// Mock workout trigger source for testing/Linux
public actor MockWorkoutTriggerSource: WorkoutTriggerSource {
    nonisolated public let sourceId = "mock-workout"
    nonisolated public let displayName = "Mock Workout Detector"
    
    private var _isActive = false
    private var _registeredTypes: [WorkoutActivityType] = []
    private weak var delegate: TriggerSourceDelegate?
    
    public var isActive: Bool { _isActive }
    public var registeredTypes: [WorkoutActivityType] { _registeredTypes }
    
    public init() {}
    
    public func startMonitoring() async throws {
        _isActive = true
    }
    
    public func stopMonitoring() async {
        _isActive = false
    }
    
    public func setDelegate(_ delegate: TriggerSourceDelegate?) async {
        self.delegate = delegate
    }
    
    public func registerActivityTypes(_ types: [WorkoutActivityType]) async {
        _registeredTypes = types
    }
    
    /// Simulate a workout start (for testing)
    public func simulateWorkoutStart(type: WorkoutActivityType, activityId: String? = nil) async {
        let trigger = ActivityTrigger(
            type: .workoutStart,
            confidence: 1.0,
            matchedActivityId: activityId,
            context: ActivityTrigger.TriggerContext(workoutType: type.rawValue)
        )
        await delegate?.triggerSource(self, didDetect: trigger)
    }
}

// MARK: - ALG-LEARN-041: Calendar Event Trigger

/// Protocol for calendar event detection
public protocol CalendarTriggerSource: TriggerSource {
    /// Register event patterns to watch for
    func registerEventPatterns(_ patterns: [CalendarEventPattern]) async
    
    /// Currently registered patterns
    var registeredPatterns: [CalendarEventPattern] { get async }
    
    /// Look ahead window for upcoming events
    var lookAheadMinutes: Int { get async }
}

/// Pattern for matching calendar events
public struct CalendarEventPattern: Sendable, Codable, Identifiable {
    public let id: UUID
    
    /// Keywords to match in event title
    public let titleKeywords: [String]
    
    /// Keywords to match in event location
    public let locationKeywords: [String]?
    
    /// Activity ID to trigger when matched
    public let activityId: String
    
    /// Minutes before event to trigger
    public let triggerMinutesBefore: Int
    
    /// Confidence level for matches
    public let confidence: Double
    
    public init(
        id: UUID = UUID(),
        titleKeywords: [String],
        locationKeywords: [String]? = nil,
        activityId: String,
        triggerMinutesBefore: Int = 15,
        confidence: Double = 0.8
    ) {
        self.id = id
        self.titleKeywords = titleKeywords
        self.locationKeywords = locationKeywords
        self.activityId = activityId
        self.triggerMinutesBefore = triggerMinutesBefore
        self.confidence = confidence
    }
    
    /// Check if an event matches this pattern
    public func matches(title: String, location: String?) -> Bool {
        let titleLower = title.lowercased()
        let titleMatch = titleKeywords.contains { titleLower.contains($0.lowercased()) }
        
        if let locKeywords = locationKeywords, let loc = location {
            let locLower = loc.lowercased()
            let locMatch = locKeywords.contains { locLower.contains($0.lowercased()) }
            return titleMatch || locMatch
        }
        
        return titleMatch
    }
}

/// Mock calendar trigger source for testing/Linux
public actor MockCalendarTriggerSource: CalendarTriggerSource {
    nonisolated public let sourceId = "mock-calendar"
    nonisolated public let displayName = "Mock Calendar"
    
    private var _isActive = false
    private var _patterns: [CalendarEventPattern] = []
    private var _lookAheadMinutes = 60
    private weak var delegate: TriggerSourceDelegate?
    
    public var isActive: Bool { _isActive }
    public var registeredPatterns: [CalendarEventPattern] { _patterns }
    public var lookAheadMinutes: Int { _lookAheadMinutes }
    
    public init(lookAheadMinutes: Int = 60) {
        _lookAheadMinutes = lookAheadMinutes
    }
    
    public func startMonitoring() async throws {
        _isActive = true
    }
    
    public func stopMonitoring() async {
        _isActive = false
    }
    
    public func setDelegate(_ delegate: TriggerSourceDelegate?) async {
        self.delegate = delegate
    }
    
    public func registerEventPatterns(_ patterns: [CalendarEventPattern]) async {
        _patterns = patterns
    }
    
    /// Simulate an upcoming calendar event (for testing)
    public func simulateUpcomingEvent(
        title: String,
        location: String?,
        startsIn minutes: Int
    ) async {
        for pattern in _patterns {
            if pattern.matches(title: title, location: location) {
                let trigger = ActivityTrigger(
                    type: .calendarEvent,
                    confidence: pattern.confidence,
                    matchedActivityId: pattern.activityId,
                    context: ActivityTrigger.TriggerContext(eventTitle: title)
                )
                await delegate?.triggerSource(self, didDetect: trigger)
                break
            }
        }
    }
}

// MARK: - ALG-LEARN-042: Location-Based Trigger

/// Protocol for location-based triggers
public protocol LocationTriggerSource: TriggerSource {
    /// Register geofences to monitor
    func registerGeofences(_ geofences: [Geofence]) async
    
    /// Currently registered geofences
    var registeredGeofences: [Geofence] { get async }
}

/// A geofence region
public struct Geofence: Sendable, Codable, Identifiable {
    public let id: UUID
    
    /// Display name for this location
    public let name: String
    
    /// Center latitude
    public let latitude: Double
    
    /// Center longitude
    public let longitude: Double
    
    /// Radius in meters
    public let radiusMeters: Double
    
    /// Activity ID to trigger on entry
    public let activityId: String
    
    /// Confidence level
    public let confidence: Double
    
    /// Whether to trigger on entry, exit, or both
    public let triggerOn: GeofenceTrigger
    
    public enum GeofenceTrigger: String, Sendable, Codable {
        case entry = "entry"
        case exit = "exit"
        case both = "both"
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 100,
        activityId: String,
        confidence: Double = 0.85,
        triggerOn: GeofenceTrigger = .entry
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.activityId = activityId
        self.confidence = confidence
        self.triggerOn = triggerOn
    }
    
    /// Check if a coordinate is within this geofence
    public func contains(latitude: Double, longitude: Double) -> Bool {
        let latDiff = latitude - self.latitude
        let lonDiff = longitude - self.longitude
        // Approximate meters (1 degree ≈ 111km at equator)
        let latMeters = latDiff * 111_000
        let lonMeters = lonDiff * 111_000 * cos(self.latitude * .pi / 180)
        let distance = sqrt(latMeters * latMeters + lonMeters * lonMeters)
        return distance <= radiusMeters
    }
}

/// Mock location trigger source for testing/Linux
public actor MockLocationTriggerSource: LocationTriggerSource {
    nonisolated public let sourceId = "mock-location"
    nonisolated public let displayName = "Mock Location"
    
    private var _isActive = false
    private var _geofences: [Geofence] = []
    private weak var delegate: TriggerSourceDelegate?
    
    public var isActive: Bool { _isActive }
    public var registeredGeofences: [Geofence] { _geofences }
    
    public init() {}
    
    public func startMonitoring() async throws {
        _isActive = true
    }
    
    public func stopMonitoring() async {
        _isActive = false
    }
    
    public func setDelegate(_ delegate: TriggerSourceDelegate?) async {
        self.delegate = delegate
    }
    
    public func registerGeofences(_ geofences: [Geofence]) async {
        _geofences = geofences
    }
    
    /// Simulate entering a location (for testing)
    public func simulateLocationEntry(latitude: Double, longitude: Double) async {
        for geofence in _geofences {
            if geofence.contains(latitude: latitude, longitude: longitude) {
                if geofence.triggerOn == .entry || geofence.triggerOn == .both {
                    let trigger = ActivityTrigger(
                        type: .location,
                        confidence: geofence.confidence,
                        matchedActivityId: geofence.activityId,
                        context: ActivityTrigger.TriggerContext(locationName: geofence.name)
                    )
                    await delegate?.triggerSource(self, didDetect: trigger)
                }
            }
        }
    }
    
    /// Simulate exiting a location (for testing)
    public func simulateLocationExit(geofenceId: UUID) async {
        guard let geofence = _geofences.first(where: { $0.id == geofenceId }) else { return }
        
        if geofence.triggerOn == .exit || geofence.triggerOn == .both {
            let trigger = ActivityTrigger(
                type: .location,
                confidence: geofence.confidence,
                matchedActivityId: geofence.activityId,
                context: ActivityTrigger.TriggerContext(locationName: geofence.name)
            )
            await delegate?.triggerSource(self, didDetect: trigger)
        }
    }
}

// MARK: - ALG-LEARN-043: Time-of-Day Trigger

/// Protocol for scheduled/time-based triggers
public protocol ScheduledTriggerSource: TriggerSource {
    /// Register scheduled triggers
    func registerSchedules(_ schedules: [ScheduledTrigger]) async
    
    /// Currently registered schedules
    var registeredSchedules: [ScheduledTrigger] { get async }
}

/// A scheduled trigger based on time/day
public struct ScheduledTrigger: Sendable, Codable, Identifiable {
    public let id: UUID
    
    /// Display name
    public let name: String
    
    /// Hour to trigger (0-23)
    public let hour: Int
    
    /// Minute to trigger (0-59)
    public let minute: Int
    
    /// Days of week (1=Sunday, 7=Saturday), nil = every day
    public let daysOfWeek: Set<Int>?
    
    /// Activity ID to trigger
    public let activityId: String
    
    /// Confidence level
    public let confidence: Double
    
    /// Whether this schedule is enabled
    public let isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        hour: Int,
        minute: Int = 0,
        daysOfWeek: Set<Int>? = nil,
        activityId: String,
        confidence: Double = 0.9,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hour = hour
        self.minute = minute
        self.daysOfWeek = daysOfWeek
        self.activityId = activityId
        self.confidence = confidence
        self.isEnabled = isEnabled
    }
    
    /// Check if this schedule matches the given time
    public func matches(hour: Int, minute: Int, dayOfWeek: Int) -> Bool {
        guard isEnabled else { return false }
        guard self.hour == hour && self.minute == minute else { return false }
        
        if let days = daysOfWeek {
            return days.contains(dayOfWeek)
        }
        return true
    }
    
    /// Human-readable schedule description
    public var displayDescription: String {
        let timeStr = String(format: "%d:%02d", hour > 12 ? hour - 12 : hour, minute)
        let ampm = hour >= 12 ? "pm" : "am"
        
        if let days = daysOfWeek {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayStrs = days.sorted().compactMap { d in
                d >= 1 && d <= 7 ? dayNames[d - 1] : nil
            }
            return "\(timeStr)\(ampm) on \(dayStrs.joined(separator: ", "))"
        }
        return "\(timeStr)\(ampm) daily"
    }
}

/// Mock scheduled trigger source for testing/Linux
public actor MockScheduledTriggerSource: ScheduledTriggerSource {
    nonisolated public let sourceId = "mock-scheduled"
    nonisolated public let displayName = "Mock Scheduler"
    
    private var _isActive = false
    private var _schedules: [ScheduledTrigger] = []
    private weak var delegate: TriggerSourceDelegate?
    
    public var isActive: Bool { _isActive }
    public var registeredSchedules: [ScheduledTrigger] { _schedules }
    
    public init() {}
    
    public func startMonitoring() async throws {
        _isActive = true
    }
    
    public func stopMonitoring() async {
        _isActive = false
    }
    
    public func setDelegate(_ delegate: TriggerSourceDelegate?) async {
        self.delegate = delegate
    }
    
    public func registerSchedules(_ schedules: [ScheduledTrigger]) async {
        _schedules = schedules
    }
    
    /// Simulate time passing to a specific time (for testing)
    public func simulateTime(hour: Int, minute: Int, dayOfWeek: Int) async {
        for schedule in _schedules {
            if schedule.matches(hour: hour, minute: minute, dayOfWeek: dayOfWeek) {
                let trigger = ActivityTrigger(
                    type: .timeOfDay,
                    confidence: schedule.confidence,
                    matchedActivityId: schedule.activityId,
                    context: ActivityTrigger.TriggerContext(
                        dayOfWeek: dayOfWeek,
                        hour: hour
                    )
                )
                await delegate?.triggerSource(self, didDetect: trigger)
            }
        }
    }
}

// MARK: - ALG-LEARN-044: Siri/Shortcuts Trigger

/// Protocol for voice/shortcut triggers
public protocol VoiceTriggerSource: TriggerSource {
    /// Register voice commands
    func registerCommands(_ commands: [VoiceCommand]) async
    
    /// Currently registered commands
    var registeredCommands: [VoiceCommand] { get async }
    
    /// Donate a shortcut for an activity
    func donateShortcut(for activityId: String, phrase: String) async
}

/// A voice command configuration
public struct VoiceCommand: Sendable, Codable, Identifiable {
    public let id: UUID
    
    /// Trigger phrase (e.g., "Starting tennis")
    public let phrase: String
    
    /// Alternative phrases
    public let alternatives: [String]
    
    /// Activity ID to trigger
    public let activityId: String
    
    /// Confidence level
    public let confidence: Double
    
    public init(
        id: UUID = UUID(),
        phrase: String,
        alternatives: [String] = [],
        activityId: String,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.phrase = phrase
        self.alternatives = alternatives
        self.activityId = activityId
        self.confidence = confidence
    }
    
    /// Check if input matches this command
    public func matches(_ input: String) -> Bool {
        let inputLower = input.lowercased()
        if phrase.lowercased() == inputLower { return true }
        return alternatives.contains { $0.lowercased() == inputLower }
    }
}

/// Mock voice trigger source for testing/Linux
public actor MockVoiceTriggerSource: VoiceTriggerSource {
    nonisolated public let sourceId = "mock-voice"
    nonisolated public let displayName = "Mock Voice Assistant"
    
    private var _isActive = false
    private var _commands: [VoiceCommand] = []
    private var _donatedPhrases: [String: String] = [:] // activityId -> phrase
    private weak var delegate: TriggerSourceDelegate?
    
    public var isActive: Bool { _isActive }
    public var registeredCommands: [VoiceCommand] { _commands }
    
    public init() {}
    
    public func startMonitoring() async throws {
        _isActive = true
    }
    
    public func stopMonitoring() async {
        _isActive = false
    }
    
    public func setDelegate(_ delegate: TriggerSourceDelegate?) async {
        self.delegate = delegate
    }
    
    public func registerCommands(_ commands: [VoiceCommand]) async {
        _commands = commands
    }
    
    public func donateShortcut(for activityId: String, phrase: String) async {
        _donatedPhrases[activityId] = phrase
    }
    
    /// Get donated phrases (for testing)
    public func donatedPhrases() -> [String: String] {
        _donatedPhrases
    }
    
    /// Simulate a voice command (for testing)
    public func simulateVoiceCommand(_ input: String) async {
        for command in _commands {
            if command.matches(input) {
                let trigger = ActivityTrigger(
                    type: .siri,
                    confidence: command.confidence,
                    matchedActivityId: command.activityId,
                    context: ActivityTrigger.TriggerContext()
                )
                await delegate?.triggerSource(self, didDetect: trigger)
                break
            }
        }
    }
}

// MARK: - Trigger Manager

/// Manages all trigger sources and coordinates proposals
public actor TriggerManager: TriggerSourceDelegate {
    
    /// All registered trigger sources
    private var sources: [any TriggerSource] = []
    
    /// Proposal generator
    private let proposalGenerator: ActivityProposalGenerator
    
    /// Callback for proposals
    public var onProposalGenerated: (@Sendable (ActivityProposal) async -> Void)?
    
    public init(proposalGenerator: ActivityProposalGenerator) {
        self.proposalGenerator = proposalGenerator
    }
    
    /// Register a trigger source
    public func registerSource(_ source: any TriggerSource) async {
        sources.append(source)
        await source.setDelegate(self)
    }
    
    /// Start all sources
    public func startAllSources() async throws {
        for source in sources {
            try await source.startMonitoring()
        }
    }
    
    /// Stop all sources
    public func stopAllSources() async {
        for source in sources {
            await source.stopMonitoring()
        }
    }
    
    /// Get all active sources
    public func activeSources() async -> [String] {
        var active: [String] = []
        for source in sources {
            if await source.isActive {
                active.append(source.sourceId)
            }
        }
        return active
    }
    
    // MARK: - TriggerSourceDelegate
    
    nonisolated public func triggerSource(
        _ source: any TriggerSource,
        didDetect trigger: ActivityTrigger
    ) async {
        // Generate proposal from trigger
        if let proposal = await proposalGenerator.generateProposal(from: trigger) {
            await onProposalGenerated?(proposal)
        }
    }
}

// MARK: - Trigger Configuration

/// Configuration for all trigger sources
public struct TriggerConfiguration: Sendable, Codable {
    /// Workout trigger settings
    public var workoutTypes: [WorkoutActivityType]
    
    /// Calendar event patterns
    public var calendarPatterns: [CalendarEventPattern]
    
    /// Geofences
    public var geofences: [Geofence]
    
    /// Scheduled triggers
    public var schedules: [ScheduledTrigger]
    
    /// Voice commands
    public var voiceCommands: [VoiceCommand]
    
    public init(
        workoutTypes: [WorkoutActivityType] = [],
        calendarPatterns: [CalendarEventPattern] = [],
        geofences: [Geofence] = [],
        schedules: [ScheduledTrigger] = [],
        voiceCommands: [VoiceCommand] = []
    ) {
        self.workoutTypes = workoutTypes
        self.calendarPatterns = calendarPatterns
        self.geofences = geofences
        self.schedules = schedules
        self.voiceCommands = voiceCommands
    }
    
    /// Apply configuration to trigger sources
    public func apply(
        to workoutSource: any WorkoutTriggerSource,
        calendarSource: any CalendarTriggerSource,
        locationSource: any LocationTriggerSource,
        scheduledSource: any ScheduledTriggerSource,
        voiceSource: any VoiceTriggerSource
    ) async {
        await workoutSource.registerActivityTypes(workoutTypes)
        await calendarSource.registerEventPatterns(calendarPatterns)
        await locationSource.registerGeofences(geofences)
        await scheduledSource.registerSchedules(schedules)
        await voiceSource.registerCommands(voiceCommands)
    }
}
