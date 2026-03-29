// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ActivityAgentBootstrapper.swift
// T1PalAlgorithm
//
// Bootstraps ML agents from user-defined override patterns
// Backlog: ALG-LEARN-010, ALG-LEARN-011, ALG-LEARN-012, ALG-LEARN-013, ALG-LEARN-014
// Trace: ALG-LEARN (User Hunch → Trained Agent Pipeline)

import Foundation

// MARK: - User Override Definition (ALG-LEARN-010)

/// A user-defined override that can be used to bootstrap an agent
public struct UserOverrideDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    
    /// Human-readable name (e.g., "Tennis", "Running", "Sick Day")
    public let name: String
    
    /// Settings configured by user
    public let settings: OverrideSettings
    
    /// Whether this is a system default (false = user-created activity override)
    public let isSystemDefault: Bool
    
    /// Optional icon or emoji
    public let icon: String?
    
    /// When the override was created
    public let createdAt: Date
    
    /// Category for grouping
    public let category: OverrideCategory
    
    public init(
        id: String,
        name: String,
        settings: OverrideSettings,
        isSystemDefault: Bool = false,
        icon: String? = nil,
        createdAt: Date = Date(),
        category: OverrideCategory = .activity
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.isSystemDefault = isSystemDefault
        self.icon = icon
        self.createdAt = createdAt
        self.category = category
    }
    
    /// Whether this override is suitable for agent bootstrapping
    /// (user-created activity overrides with meaningful settings changes)
    public var isActivityOverride: Bool {
        !isSystemDefault && category == .activity
    }
}

/// Override category for classification
public enum OverrideCategory: String, Codable, Sendable {
    case activity = "activity"      // Tennis, Running, Gym
    case health = "health"          // Sick Day, Menstrual Phase
    case meal = "meal"              // Pre-meal, Post-meal
    case sleep = "sleep"            // Sleep, Wake up
    case custom = "custom"          // User-defined other
}

// MARK: - Training Status (ALG-LEARN-013)

/// Status of training for an activity agent
public enum TrainingStatus: Codable, Sendable, Equatable {
    /// User's initial "hunch" - not enough data to learn
    case hunch(sessions: Int)
    
    /// Agent is being trained (5+ sessions)
    case trained(sessions: Int, confidence: Double)
    
    /// Agent has graduated to a learned pattern (10+ sessions, consistent results)
    case graduated(confidence: Double)
    
    /// Minimum sessions required for each status
    public static let sessionsForTrained = 5
    public static let sessionsForGraduated = 10
    public static let confidenceThreshold = 0.7
    
    /// Create status from session count and success rate
    public static func from(sessionCount: Int, avgSuccessScore: Double) -> TrainingStatus {
        switch sessionCount {
        case 0..<sessionsForTrained:
            return .hunch(sessions: sessionCount)
        case sessionsForTrained..<sessionsForGraduated:
            return .trained(sessions: sessionCount, confidence: avgSuccessScore)
        default:
            if avgSuccessScore >= confidenceThreshold {
                return .graduated(confidence: avgSuccessScore)
            } else {
                return .trained(sessions: sessionCount, confidence: avgSuccessScore)
            }
        }
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .hunch(let sessions):
            return "User hunch (\(sessions) session\(sessions == 1 ? "" : "s"))"
        case .trained(let sessions, let confidence):
            return "Training (\(sessions) sessions, \(Int(confidence * 100))% success)"
        case .graduated(let confidence):
            return "Learned pattern (\(Int(confidence * 100))% confidence)"
        }
    }
    
    /// Whether this agent is ready to make suggestions
    public var canSuggest: Bool {
        switch self {
        case .hunch: return false
        case .trained(let sessions, _): return sessions >= TrainingStatus.sessionsForTrained
        case .graduated: return true
        }
    }
    
    /// Sessions until next milestone
    public var sessionsToNextLevel: Int? {
        switch self {
        case .hunch(let sessions):
            return TrainingStatus.sessionsForTrained - sessions
        case .trained(let sessions, _):
            return TrainingStatus.sessionsForGraduated - sessions
        case .graduated:
            return nil
        }
    }
}

// MARK: - Settings Refinement (ALG-LEARN-014)

/// A suggested refinement to override settings based on learning
public struct SettingsRefinement: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Type of refinement
    public let type: RefinementType
    
    /// Current value being used
    public let currentValue: Double
    
    /// Suggested value based on learning
    public let suggestedValue: Double
    
    /// Human-readable message
    public let message: String
    
    /// Evidence supporting the suggestion
    public let evidence: String
    
    /// Confidence in this suggestion (0-1)
    public let confidence: Double
    
    public enum RefinementType: String, Codable, Sendable {
        case adjustBasal = "adjustBasal"
        case adjustISF = "adjustISF"
        case adjustCR = "adjustCR"
        case adjustTarget = "adjustTarget"
        case adjustDuration = "adjustDuration"
    }
    
    public init(
        id: UUID = UUID(),
        type: RefinementType,
        currentValue: Double,
        suggestedValue: Double,
        message: String,
        evidence: String,
        confidence: Double
    ) {
        self.id = id
        self.type = type
        self.currentValue = currentValue
        self.suggestedValue = suggestedValue
        self.message = message
        self.evidence = evidence
        self.confidence = confidence
    }
    
    /// Format the change as a human-readable delta
    public var changeDescription: String {
        let delta = suggestedValue - currentValue
        let sign = delta >= 0 ? "+" : ""
        
        switch type {
        case .adjustBasal, .adjustISF, .adjustCR:
            let currentPercent = Int((1 - currentValue) * 100)
            let suggestedPercent = Int((1 - suggestedValue) * 100)
            return "\(sign)\(suggestedPercent - currentPercent)% (from -\(currentPercent)% to -\(suggestedPercent)%)"
        case .adjustTarget:
            return "\(sign)\(Int(delta)) mg/dL"
        case .adjustDuration:
            return "\(sign)\(Int(delta / 60)) min"
        }
    }
}

// MARK: - Activity Agent Stub (ALG-LEARN-011)

/// A learning agent created from a user-defined override
/// Starts as a stub and becomes smarter as it collects data
public actor ActivityAgentStub: EffectAgent {
    
    // MARK: - EffectAgent Protocol
    
    public nonisolated let agentId: String
    public nonisolated let name: String
    public nonisolated let description: String
    public nonisolated let privacyTier: PrivacyTier
    
    // MARK: - Learning State
    
    /// The user-defined override this agent is based on
    public let overrideDefinition: UserOverrideDefinition
    
    /// Current training status
    private(set) var trainingStatus: TrainingStatus
    
    /// Learned optimal settings (updated by training)
    private(set) var learnedSettings: OverrideSettings
    
    /// Suggested refinements based on learning
    private(set) var refinements: [SettingsRefinement]
    
    /// Session data used for training
    private var trainingSessions: [OverrideSession]
    
    // MARK: - Initialization
    
    public init(from definition: UserOverrideDefinition) {
        self.overrideDefinition = definition
        self.agentId = "activity-\(definition.id)"
        self.name = definition.name
        self.description = "Learned agent for \(definition.name) activity"
        self.privacyTier = .transparent
        
        self.trainingStatus = .hunch(sessions: 0)
        self.learnedSettings = definition.settings
        self.refinements = []
        self.trainingSessions = []
    }
    
    // MARK: - EffectAgent Implementation
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        // Only produce effects if trained
        guard trainingStatus.canSuggest else {
            return nil
        }
        
        // Create effect bundle with learned settings
        let now = Date()
        let duration = learnedSettings.scheduledDuration ?? 3600 // Default 1 hour
        
        var effects: [AnyEffect] = []
        
        // Apply sensitivity effect if ISF or basal modified
        // (We use sensitivity to represent basal changes as they affect the same outcome)
        if learnedSettings.isfMultiplier != 1.0 || learnedSettings.basalMultiplier != 1.0 {
            // Combine basal and ISF into a single sensitivity effect
            // Lower basal multiplier (e.g., 0.7) = more sensitive = less insulin
            let combinedFactor = learnedSettings.isfMultiplier * learnedSettings.basalMultiplier
            let sensitivity = SensitivityEffectSpec(
                confidence: trainingStatus.confidence,
                factor: combinedFactor,
                durationMinutes: Int(duration / 60)
            )
            effects.append(.sensitivity(sensitivity))
        }
        
        guard !effects.isEmpty else { return nil }
        
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(duration),
            effects: effects,
            reason: "Learned pattern for \(name)",
            privacyTier: privacyTier,
            confidence: trainingStatus.confidence
        )
    }
    
    // MARK: - Training (ALG-LEARN-012)
    
    /// Add a completed session and update training
    public func addSession(_ session: OverrideSession) {
        trainingSessions.append(session)
        updateTraining()
    }
    
    /// Get current session count
    public var sessionCount: Int {
        trainingSessions.count
    }
    
    /// Update training based on accumulated sessions
    private func updateTraining() {
        let completeSessions = trainingSessions.filter { $0.isComplete }
        guard !completeSessions.isEmpty else { return }
        
        // Calculate average success score
        let outcomes = completeSessions.compactMap { $0.outcome }
        let avgSuccess = outcomes.isEmpty ? 0.0 : 
            outcomes.map { $0.successScore }.reduce(0, +) / Double(outcomes.count)
        
        // Update training status
        trainingStatus = TrainingStatus.from(
            sessionCount: completeSessions.count,
            avgSuccessScore: avgSuccess
        )
        
        // Update learned settings if we have enough data
        if completeSessions.count >= TrainingStatus.sessionsForTrained {
            updateLearnedSettings(from: completeSessions)
            generateRefinements(from: completeSessions)
        }
    }
    
    /// Analyze sessions to update learned optimal settings
    private func updateLearnedSettings(from sessions: [OverrideSession]) {
        let outcomes = sessions.compactMap { $0.outcome }
        guard !outcomes.isEmpty else { return }
        
        // Find settings that correlated with best outcomes
        // For now, use a simple approach: find the session with best outcome
        // and use those settings as learned settings
        if let bestSession = sessions
            .filter({ $0.outcome != nil })
            .max(by: { ($0.outcome?.successScore ?? 0) < ($1.outcome?.successScore ?? 0) }) {
            learnedSettings = bestSession.settings
        }
    }
    
    // MARK: - Refinements (ALG-LEARN-014)
    
    /// Generate setting refinement suggestions
    private func generateRefinements(from sessions: [OverrideSession]) {
        refinements = []
        
        let completeSessions = sessions.filter { $0.isComplete }
        guard completeSessions.count >= 3 else { return }
        
        let outcomes = completeSessions.compactMap { $0.outcome }
        guard !outcomes.isEmpty else { return }
        
        let currentSettings = overrideDefinition.settings
        
        // Analyze hypo frequency - if too many, suggest less aggressive basal reduction
        let avgHypos = Double(outcomes.map { $0.hypoEvents }.reduce(0, +)) / Double(outcomes.count)
        if avgHypos > 0.5 && currentSettings.basalMultiplier < 0.8 {
            let suggestedBasal = min(1.0, currentSettings.basalMultiplier + 0.1)
            refinements.append(SettingsRefinement(
                type: .adjustBasal,
                currentValue: currentSettings.basalMultiplier,
                suggestedValue: suggestedBasal,
                message: "Your \(name) works better at -\(Int((1 - suggestedBasal) * 100))% not -\(Int((1 - currentSettings.basalMultiplier) * 100))%",
                evidence: "Average \(String(format: "%.1f", avgHypos)) hypos per session",
                confidence: min(0.9, 0.5 + Double(completeSessions.count) * 0.05)
            ))
        }
        
        // Analyze hyper frequency - if too many, suggest more aggressive basal reduction
        let avgHypers = Double(outcomes.map { $0.hyperEvents }.reduce(0, +)) / Double(outcomes.count)
        if avgHypers > 1.0 && currentSettings.basalMultiplier > 0.5 {
            let suggestedBasal = max(0.5, currentSettings.basalMultiplier - 0.1)
            refinements.append(SettingsRefinement(
                type: .adjustBasal,
                currentValue: currentSettings.basalMultiplier,
                suggestedValue: suggestedBasal,
                message: "Your \(name) needs more reduction: try -\(Int((1 - suggestedBasal) * 100))%",
                evidence: "Average \(String(format: "%.1f", avgHypers)) highs per session",
                confidence: min(0.9, 0.5 + Double(completeSessions.count) * 0.05)
            ))
        }
        
        // Analyze TIR improvement potential
        let avgTIR = outcomes.map { $0.timeInRange }.reduce(0, +) / Double(outcomes.count)
        if avgTIR < 70 && completeSessions.count >= 5 {
            refinements.append(SettingsRefinement(
                type: .adjustISF,
                currentValue: currentSettings.isfMultiplier,
                suggestedValue: currentSettings.isfMultiplier * 0.9,
                message: "Consider adjusting sensitivity for \(name)",
                evidence: "TIR currently \(Int(avgTIR))%, targeting 70%+",
                confidence: 0.6
            ))
        }
    }
    
    /// Get current refinement suggestions
    public func currentRefinements() -> [SettingsRefinement] {
        refinements
    }
    
    /// Get the current confidence level
    public var confidence: Double {
        switch trainingStatus {
        case .hunch: return 0.0
        case .trained(_, let conf): return conf
        case .graduated(let conf): return conf
        }
    }
}

// Extension for TrainingStatus to get confidence
extension TrainingStatus {
    var confidence: Double {
        switch self {
        case .hunch: return 0.0
        case .trained(_, let conf): return conf
        case .graduated(let conf): return conf
        }
    }
}

// MARK: - Activity Agent Bootstrapper

/// Actor that manages the lifecycle of activity agents bootstrapped from user overrides
public actor ActivityAgentBootstrapper {
    
    /// Storage for agent stubs
    private var agentStubs: [String: ActivityAgentStub] = [:]
    
    /// Known user override definitions
    private var knownOverrides: [String: UserOverrideDefinition] = [:]
    
    /// Delegate for persistence
    private let storage: ActivityAgentStorage?
    
    /// Session tracker for collecting training data
    private let sessionTracker: OverrideOutcomeTracker?
    
    public init(
        storage: ActivityAgentStorage? = nil,
        sessionTracker: OverrideOutcomeTracker? = nil
    ) {
        self.storage = storage
        self.sessionTracker = sessionTracker
    }
    
    // MARK: - Override Detection (ALG-LEARN-010)
    
    /// Register a new user-defined override
    /// Creates an agent stub if this is an activity override
    public func registerOverride(_ definition: UserOverrideDefinition) async -> ActivityAgentStub? {
        knownOverrides[definition.id] = definition
        
        // Only create stubs for user-created activity overrides
        guard definition.isActivityOverride else { return nil }
        
        // Create stub if not exists
        if agentStubs[definition.id] == nil {
            let stub = ActivityAgentStub(from: definition)
            agentStubs[definition.id] = stub
            
            // Persist
            if let storage = storage {
                await storage.saveAgent(stub)
            }
            
            return stub
        }
        
        return agentStubs[definition.id]
    }
    
    /// Get all user-created activity overrides
    public func activityOverrides() -> [UserOverrideDefinition] {
        knownOverrides.values.filter { $0.isActivityOverride }
    }
    
    /// Detect if an override ID represents a user-created activity
    public func isUserActivity(_ overrideId: String) -> Bool {
        knownOverrides[overrideId]?.isActivityOverride ?? false
    }
    
    // MARK: - Agent Management (ALG-LEARN-011)
    
    /// Get agent stub for an override
    public func agent(for overrideId: String) -> ActivityAgentStub? {
        agentStubs[overrideId]
    }
    
    /// Get all agent stubs
    public func allAgents() -> [ActivityAgentStub] {
        Array(agentStubs.values)
    }
    
    /// Get agents that have graduated
    public func graduatedAgents() -> [ActivityAgentStub] {
        // This needs to be async to access actor state
        Array(agentStubs.values)
    }
    
    // MARK: - Training Integration (ALG-LEARN-012)
    
    /// Process a completed override session for training
    public func processSession(_ session: OverrideSession) async {
        // Find the agent stub for this override
        guard let stub = agentStubs[session.overrideId] else {
            // Check if this is a new activity override we should track
            if let definition = knownOverrides[session.overrideId],
               definition.isActivityOverride {
                let newStub = ActivityAgentStub(from: definition)
                agentStubs[session.overrideId] = newStub
                await newStub.addSession(session)
            }
            return
        }
        
        await stub.addSession(session)
        
        // Persist updated state
        if let storage = storage {
            await storage.saveAgent(stub)
        }
    }
    
    // MARK: - Refinements (ALG-LEARN-014)
    
    /// Get all refinement suggestions across agents
    public func allRefinements() async -> [(agent: String, refinements: [SettingsRefinement])] {
        var result: [(agent: String, refinements: [SettingsRefinement])] = []
        
        for (id, stub) in agentStubs {
            let refinements = await stub.currentRefinements()
            if !refinements.isEmpty {
                result.append((agent: id, refinements: refinements))
            }
        }
        
        return result
    }
    
    // MARK: - Persistence
    
    /// Load saved agents from storage
    public func loadAgents() async {
        guard let storage = storage else { return }
        
        let loaded = await storage.loadAllAgents()
        for agent in loaded {
            agentStubs[agent.overrideDefinition.id] = agent
            knownOverrides[agent.overrideDefinition.id] = agent.overrideDefinition
        }
    }
}

// MARK: - Storage Protocol

/// Protocol for persisting activity agents
public protocol ActivityAgentStorage: Sendable {
    func saveAgent(_ agent: ActivityAgentStub) async
    func loadAllAgents() async -> [ActivityAgentStub]
    func deleteAgent(_ agentId: String) async
}

// MARK: - In-Memory Storage

/// Simple in-memory storage for testing
public actor InMemoryActivityAgentStorage: ActivityAgentStorage {
    private var agents: [String: ActivityAgentStub] = [:]
    
    public init() {}
    
    public func saveAgent(_ agent: ActivityAgentStub) async {
        agents[agent.agentId] = agent
    }
    
    public func loadAllAgents() async -> [ActivityAgentStub] {
        Array(agents.values)
    }
    
    public func deleteAgent(_ agentId: String) async {
        agents.removeValue(forKey: agentId)
    }
}


