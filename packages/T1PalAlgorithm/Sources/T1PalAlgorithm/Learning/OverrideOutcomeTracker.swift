// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OverrideOutcomeTracker.swift
// T1PalAlgorithm
//
// Tracks override activations and their glucose outcomes for ML training
// Backlog: ALG-LEARN-001, ALG-LEARN-002, ALG-LEARN-003
// Trace: ALG-LEARN (User Hunch → Trained Agent Pipeline)

import Foundation

// MARK: - Override Session

/// A recorded override session with pre/post outcomes (ALG-LEARN-003)
public struct OverrideSession: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Override identifier (e.g., "Tennis", "Sick Day")
    public let overrideId: String
    
    /// Override display name
    public let overrideName: String
    
    /// When the override was activated
    public let activatedAt: Date
    
    /// When the override ended (nil if still active)
    public var deactivatedAt: Date?
    
    /// Override settings applied
    public let settings: OverrideSettings
    
    /// Pre-override glucose snapshot (ALG-LEARN-001)
    public let preSnapshot: GlucoseSnapshot
    
    /// Post-override glucose snapshot (filled when override ends)
    public var postSnapshot: GlucoseSnapshot?
    
    /// Outcome metrics (calculated from snapshots)
    public var outcome: OverrideOutcome?
    
    /// Context metadata
    public let context: OverrideContext
    
    /// Whether this session is complete (has post data)
    public var isComplete: Bool {
        postSnapshot != nil && outcome != nil
    }
    
    /// Duration of the override
    public var duration: TimeInterval? {
        guard let end = deactivatedAt else { return nil }
        return end.timeIntervalSince(activatedAt)
    }
    
    public init(
        id: UUID = UUID(),
        overrideId: String,
        overrideName: String,
        activatedAt: Date = Date(),
        settings: OverrideSettings,
        preSnapshot: GlucoseSnapshot,
        context: OverrideContext
    ) {
        self.id = id
        self.overrideId = overrideId
        self.overrideName = overrideName
        self.activatedAt = activatedAt
        self.settings = settings
        self.preSnapshot = preSnapshot
        self.context = context
    }
}

// MARK: - Override Settings

/// The settings applied during an override
public struct OverrideSettings: Codable, Sendable, Equatable {
    /// Basal rate multiplier (1.0 = no change, 0.7 = -30%)
    public let basalMultiplier: Double
    
    /// ISF multiplier (1.0 = no change)
    public let isfMultiplier: Double
    
    /// CR multiplier (1.0 = no change)
    public let crMultiplier: Double
    
    /// Target glucose override (nil = use profile)
    public let targetGlucose: Double?
    
    /// Scheduled duration (nil = indefinite)
    public let scheduledDuration: TimeInterval?
    
    public init(
        basalMultiplier: Double = 1.0,
        isfMultiplier: Double = 1.0,
        crMultiplier: Double = 1.0,
        targetGlucose: Double? = nil,
        scheduledDuration: TimeInterval? = nil
    ) {
        self.basalMultiplier = basalMultiplier
        self.isfMultiplier = isfMultiplier
        self.crMultiplier = crMultiplier
        self.targetGlucose = targetGlucose
        self.scheduledDuration = scheduledDuration
    }
}

// MARK: - Glucose Snapshot

/// A snapshot of glucose state at a point in time
public struct GlucoseSnapshot: Codable, Sendable {
    /// Current glucose value (mg/dL)
    public let glucose: Double
    
    /// Glucose trend (mg/dL per 5 min)
    public let trend: Double?
    
    /// Time in range (70-180) over the snapshot window
    public let timeInRange: Double
    
    /// Number of hypoglycemic events (<70 mg/dL)
    public let hypoEvents: Int
    
    /// Number of hyperglycemic events (>180 mg/dL)
    public let hyperEvents: Int
    
    /// Coefficient of variation (glucose variability)
    public let coefficientOfVariation: Double
    
    /// Snapshot window duration (e.g., 1 hour before/after)
    public let windowDuration: TimeInterval
    
    /// Timestamp of the snapshot
    public let timestamp: Date
    
    public init(
        glucose: Double,
        trend: Double? = nil,
        timeInRange: Double,
        hypoEvents: Int = 0,
        hyperEvents: Int = 0,
        coefficientOfVariation: Double = 0,
        windowDuration: TimeInterval = 3600,
        timestamp: Date = Date()
    ) {
        self.glucose = glucose
        self.trend = trend
        self.timeInRange = timeInRange
        self.hypoEvents = hypoEvents
        self.hyperEvents = hyperEvents
        self.coefficientOfVariation = coefficientOfVariation
        self.windowDuration = windowDuration
        self.timestamp = timestamp
    }
}

// MARK: - Override Outcome (ALG-LEARN-002)

/// Calculated outcome metrics for an override session
public struct OverrideOutcome: Codable, Sendable {
    /// Time in range during override + post window
    public let timeInRange: Double
    
    /// Time in range improvement vs pre-override
    public let timeInRangeDelta: Double
    
    /// Number of hypoglycemic events
    public let hypoEvents: Int
    
    /// Number of hyperglycemic events
    public let hyperEvents: Int
    
    /// Average glucose during override
    public let averageGlucose: Double
    
    /// Glucose variability (CV%)
    public let variability: Double
    
    /// Success score (0-1, higher is better)
    public let successScore: Double
    
    /// Comparison to baseline (same override, previous sessions)
    public let vsBaseline: ComparisonResult?
    
    public init(
        timeInRange: Double,
        timeInRangeDelta: Double,
        hypoEvents: Int,
        hyperEvents: Int,
        averageGlucose: Double,
        variability: Double,
        successScore: Double,
        vsBaseline: ComparisonResult? = nil
    ) {
        self.timeInRange = timeInRange
        self.timeInRangeDelta = timeInRangeDelta
        self.hypoEvents = hypoEvents
        self.hyperEvents = hyperEvents
        self.averageGlucose = averageGlucose
        self.variability = variability
        self.successScore = successScore
        self.vsBaseline = vsBaseline
    }
    
    /// Comparison result vs baseline
    public enum ComparisonResult: String, Codable, Sendable {
        case better = "better"
        case similar = "similar"
        case worse = "worse"
    }
}

// MARK: - Override Context

/// Contextual metadata for an override session
public struct OverrideContext: Codable, Sendable {
    /// Time of day category
    public let timeOfDay: TimeOfDay
    
    /// Day of week
    public let dayOfWeek: Int
    
    /// Source of activation (manual, Siri, workout detection, etc.)
    public let activationSource: ActivationSource
    
    /// IOB at activation
    public let iobAtActivation: Double?
    
    /// COB at activation
    public let cobAtActivation: Double?
    
    /// Recent carbs (last 2 hours)
    public let recentCarbs: Double?
    
    /// User notes
    public let notes: String?
    
    public enum TimeOfDay: String, Codable, Sendable {
        case earlyMorning = "earlyMorning"  // 4-8am
        case morning = "morning"             // 8am-12pm
        case afternoon = "afternoon"         // 12-5pm
        case evening = "evening"             // 5-9pm
        case night = "night"                 // 9pm-4am
        
        public static func from(date: Date) -> TimeOfDay {
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 4..<8: return .earlyMorning
            case 8..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }
    
    public enum ActivationSource: String, Codable, Sendable {
        case manual = "manual"
        case siri = "siri"
        case shortcut = "shortcut"
        case workoutDetection = "workoutDetection"
        case scheduled = "scheduled"
        case suggestion = "suggestion"
    }
    
    public init(
        timeOfDay: TimeOfDay? = nil,
        dayOfWeek: Int? = nil,
        activationSource: ActivationSource = .manual,
        iobAtActivation: Double? = nil,
        cobAtActivation: Double? = nil,
        recentCarbs: Double? = nil,
        notes: String? = nil
    ) {
        let now = Date()
        self.timeOfDay = timeOfDay ?? TimeOfDay.from(date: now)
        self.dayOfWeek = dayOfWeek ?? Calendar.current.component(.weekday, from: now)
        self.activationSource = activationSource
        self.iobAtActivation = iobAtActivation
        self.cobAtActivation = cobAtActivation
        self.recentCarbs = recentCarbs
        self.notes = notes
    }
}

// MARK: - Override Outcome Tracker (ALG-LEARN-001)

/// Actor that tracks override sessions and calculates outcomes
public actor OverrideOutcomeTracker {
    /// Active sessions (override currently running)
    private var activeSessions: [String: OverrideSession] = [:]
    
    /// Completed sessions (stored for learning)
    private var completedSessions: [OverrideSession] = []
    
    /// Session storage delegate
    private let storage: OverrideSessionStorage?
    
    /// Post-override observation window (default: 4 hours)
    public let postObservationWindow: TimeInterval
    
    /// Maximum sessions to keep in memory
    public let maxSessionsInMemory: Int
    
    public init(
        storage: OverrideSessionStorage? = nil,
        postObservationWindow: TimeInterval = 4 * 3600,
        maxSessionsInMemory: Int = 100
    ) {
        self.storage = storage
        self.postObservationWindow = postObservationWindow
        self.maxSessionsInMemory = maxSessionsInMemory
    }
    
    // MARK: - Session Lifecycle
    
    /// Start tracking a new override session
    public func startSession(
        overrideId: String,
        overrideName: String,
        settings: OverrideSettings,
        preSnapshot: GlucoseSnapshot,
        context: OverrideContext
    ) -> OverrideSession {
        let session = OverrideSession(
            overrideId: overrideId,
            overrideName: overrideName,
            settings: settings,
            preSnapshot: preSnapshot,
            context: context
        )
        activeSessions[overrideId] = session
        return session
    }
    
    /// End an active override session
    public func endSession(
        overrideId: String,
        postSnapshot: GlucoseSnapshot
    ) async -> OverrideSession? {
        guard var session = activeSessions.removeValue(forKey: overrideId) else {
            return nil
        }
        
        session.deactivatedAt = Date()
        session.postSnapshot = postSnapshot
        session.outcome = calculateOutcome(session: session, postSnapshot: postSnapshot)
        
        // Store completed session
        completedSessions.append(session)
        
        // Trim if needed
        if completedSessions.count > maxSessionsInMemory {
            completedSessions.removeFirst(completedSessions.count - maxSessionsInMemory)
        }
        
        // Persist if storage available
        if let storage = storage {
            await storage.save(session)
        }
        
        return session
    }
    
    /// Get active session for an override
    public func activeSession(for overrideId: String) -> OverrideSession? {
        activeSessions[overrideId]
    }
    
    /// Get all active sessions
    public func allActiveSessions() -> [OverrideSession] {
        Array(activeSessions.values)
    }
    
    // MARK: - Query Sessions
    
    /// Get completed sessions for an override
    public func sessions(for overrideId: String) -> [OverrideSession] {
        completedSessions.filter { $0.overrideId == overrideId }
    }
    
    /// Get session count for an override (ALG-LEARN-005)
    public func sessionCount(for overrideId: String) -> Int {
        sessions(for: overrideId).count
    }
    
    /// Get all completed sessions
    public func allCompletedSessions() -> [OverrideSession] {
        completedSessions
    }
    
    /// Load sessions from storage
    public func loadSessions() async {
        guard let storage = storage else { return }
        let loaded = await storage.loadAll()
        completedSessions = loaded
    }
    
    // MARK: - Outcome Calculation (ALG-LEARN-002)
    
    private func calculateOutcome(
        session: OverrideSession,
        postSnapshot: GlucoseSnapshot
    ) -> OverrideOutcome {
        let pre = session.preSnapshot
        let post = postSnapshot
        
        // Calculate TIR delta
        let tirDelta = post.timeInRange - pre.timeInRange
        
        // Calculate success score
        // Higher TIR, fewer hypos = better
        // Penalize hypos heavily, reward TIR improvement
        var score = post.timeInRange / 100.0  // Base: TIR percentage
        score -= Double(post.hypoEvents) * 0.1  // Penalty per hypo
        score -= Double(post.hyperEvents) * 0.05  // Smaller penalty per hyper
        score += tirDelta * 0.01  // Bonus for improvement
        score = max(0, min(1, score))  // Clamp 0-1
        
        // Compare to baseline (previous sessions with same override)
        let previousSessions = sessions(for: session.overrideId)
        let vsBaseline: OverrideOutcome.ComparisonResult?
        if previousSessions.count >= 3 {
            let avgPreviousTIR = previousSessions
                .compactMap { $0.outcome?.timeInRange }
                .reduce(0, +) / Double(previousSessions.count)
            
            if post.timeInRange > avgPreviousTIR + 5 {
                vsBaseline = .better
            } else if post.timeInRange < avgPreviousTIR - 5 {
                vsBaseline = .worse
            } else {
                vsBaseline = .similar
            }
        } else {
            vsBaseline = nil
        }
        
        return OverrideOutcome(
            timeInRange: post.timeInRange,
            timeInRangeDelta: tirDelta,
            hypoEvents: post.hypoEvents,
            hyperEvents: post.hyperEvents,
            averageGlucose: post.glucose,
            variability: post.coefficientOfVariation,
            successScore: score,
            vsBaseline: vsBaseline
        )
    }
}

// MARK: - Storage Protocol

/// Protocol for persisting override sessions
public protocol OverrideSessionStorage: Sendable {
    func save(_ session: OverrideSession) async
    func loadAll() async -> [OverrideSession]
    func sessions(for overrideId: String) async -> [OverrideSession]
    func deleteOlderThan(_ date: Date) async
}

// MARK: - In-Memory Storage (for testing)

/// Simple in-memory storage for testing
public actor InMemoryOverrideSessionStorage: OverrideSessionStorage {
    private var sessions: [OverrideSession] = []
    
    public init() {}
    
    public func save(_ session: OverrideSession) async {
        sessions.append(session)
    }
    
    public func loadAll() async -> [OverrideSession] {
        sessions
    }
    
    public func sessions(for overrideId: String) async -> [OverrideSession] {
        sessions.filter { $0.overrideId == overrideId }
    }
    
    public func deleteOlderThan(_ date: Date) async {
        sessions.removeAll { $0.activatedAt < date }
    }
}
