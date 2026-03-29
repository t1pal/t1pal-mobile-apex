// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ActivityAgentProposalBridge.swift
// T1PalAlgorithm
//
// Bridges ActivityAgentStub to the AgentProposal system (PRD-026)
// Backlog: ALG-LEARN-020, ALG-LEARN-021, ALG-LEARN-022, ALG-LEARN-023, ALG-LEARN-024
// Trace: ALG-LEARN (User Hunch → Trained Agent Pipeline), PRD-026

import Foundation

// MARK: - Proposal Template (ALG-LEARN-021)

/// Template for generating activity-based proposals
public struct ActivityProposalTemplate: Codable, Sendable, Identifiable {
    public let id: String
    
    /// Display name for the proposal
    public let name: String
    
    /// Activity agent this template is for
    public let activityAgentId: String
    
    /// Proposal description template (supports {activity} placeholder)
    public let descriptionTemplate: String
    
    /// Rationale template (supports {confidence}, {sessions} placeholders)
    public let rationaleTemplate: String
    
    /// Default duration for the override
    public let defaultDuration: TimeInterval
    
    /// Expiry time for the proposal
    public let proposalExpiryMinutes: Int
    
    public init(
        id: String,
        name: String,
        activityAgentId: String,
        descriptionTemplate: String = "Starting {activity}?",
        rationaleTemplate: String = "Based on {sessions} sessions with {confidence}% success",
        defaultDuration: TimeInterval = 3600,
        proposalExpiryMinutes: Int = 15
    ) {
        self.id = id
        self.name = name
        self.activityAgentId = activityAgentId
        self.descriptionTemplate = descriptionTemplate
        self.rationaleTemplate = rationaleTemplate
        self.defaultDuration = defaultDuration
        self.proposalExpiryMinutes = proposalExpiryMinutes
    }
    
    /// Generate description with placeholders filled
    public func generateDescription(activityName: String) -> String {
        descriptionTemplate.replacingOccurrences(of: "{activity}", with: activityName)
    }
    
    /// Generate rationale with placeholders filled
    public func generateRationale(sessions: Int, confidence: Double) -> String {
        rationaleTemplate
            .replacingOccurrences(of: "{sessions}", with: "\(sessions)")
            .replacingOccurrences(of: "{confidence}", with: "\(Int(confidence * 100))")
    }
}

// MARK: - Activity Trigger (ALG-LEARN-022)

/// Detected trigger that may initiate an activity
public struct ActivityTrigger: Sendable {
    public let type: TriggerType
    public let timestamp: Date
    public let confidence: Double
    public let matchedActivityId: String?
    public let context: TriggerContext
    
    public enum TriggerType: String, Sendable {
        case workoutStart = "workoutStart"
        case timeOfDay = "timeOfDay"
        case location = "location"
        case calendarEvent = "calendarEvent"
        case manual = "manual"
        case siri = "siri"
    }
    
    public struct TriggerContext: Sendable {
        public let workoutType: String?
        public let locationName: String?
        public let eventTitle: String?
        public let dayOfWeek: Int
        public let hour: Int
        
        public init(
            workoutType: String? = nil,
            locationName: String? = nil,
            eventTitle: String? = nil,
            dayOfWeek: Int? = nil,
            hour: Int? = nil
        ) {
            let now = Date()
            self.workoutType = workoutType
            self.locationName = locationName
            self.eventTitle = eventTitle
            self.dayOfWeek = dayOfWeek ?? Calendar.current.component(.weekday, from: now)
            self.hour = hour ?? Calendar.current.component(.hour, from: now)
        }
    }
    
    public init(
        type: TriggerType,
        timestamp: Date = Date(),
        confidence: Double = 1.0,
        matchedActivityId: String? = nil,
        context: TriggerContext = TriggerContext()
    ) {
        self.type = type
        self.timestamp = timestamp
        self.confidence = confidence
        self.matchedActivityId = matchedActivityId
        self.context = context
    }
}

/// Detector for activity triggers
public actor ActivityTriggerDetector {
    
    /// Known activity patterns (activityId -> trigger patterns)
    private var patterns: [String: [TriggerPattern]] = [:]
    
    /// Activity definitions for matching
    private var activities: [String: UserOverrideDefinition] = [:]
    
    public init() {}
    
    /// Register an activity for trigger detection
    public func registerActivity(_ activity: UserOverrideDefinition) {
        activities[activity.id] = activity
    }
    
    /// Add a trigger pattern for an activity
    public func addPattern(activityId: String, pattern: TriggerPattern) {
        var existing = patterns[activityId] ?? []
        existing.append(pattern)
        patterns[activityId] = existing
    }
    
    /// Detect triggers based on current context
    public func detectTriggers(context: ActivityTrigger.TriggerContext) -> [ActivityTrigger] {
        var triggers: [ActivityTrigger] = []
        
        for (activityId, activityPatterns) in patterns {
            for pattern in activityPatterns {
                if let trigger = pattern.matches(context: context, activityId: activityId) {
                    triggers.append(trigger)
                }
            }
        }
        
        return triggers.sorted { $0.confidence > $1.confidence }
    }
    
    /// Match workout type to activity
    public func matchWorkout(type: String) -> ActivityTrigger? {
        // Simple keyword matching for common workout types
        let workoutLower = type.lowercased()
        
        for (activityId, activity) in activities {
            let activityLower = activity.name.lowercased()
            
            // Check for direct match or common synonyms
            if workoutLower.contains(activityLower) || activityLower.contains(workoutLower) {
                return ActivityTrigger(
                    type: .workoutStart,
                    confidence: 0.9,
                    matchedActivityId: activityId,
                    context: ActivityTrigger.TriggerContext(workoutType: type)
                )
            }
            
            // Check for category matches
            if let match = matchWorkoutCategory(workout: workoutLower, activity: activityLower) {
                return ActivityTrigger(
                    type: .workoutStart,
                    confidence: match,
                    matchedActivityId: activityId,
                    context: ActivityTrigger.TriggerContext(workoutType: type)
                )
            }
        }
        
        return nil
    }
    
    private func matchWorkoutCategory(workout: String, activity: String) -> Double? {
        let cardioKeywords = ["running", "jogging", "cycling", "swimming", "walking", "cardio", "aerobic"]
        let strengthKeywords = ["weight", "strength", "gym", "lifting", "resistance"]
        let sportsKeywords = ["tennis", "basketball", "soccer", "football", "volleyball", "golf"]
        
        let workoutIsCardio = cardioKeywords.contains { workout.contains($0) }
        let activityIsCardio = cardioKeywords.contains { activity.contains($0) }
        if workoutIsCardio && activityIsCardio { return 0.7 }
        
        let workoutIsStrength = strengthKeywords.contains { workout.contains($0) }
        let activityIsStrength = strengthKeywords.contains { activity.contains($0) }
        if workoutIsStrength && activityIsStrength { return 0.7 }
        
        let workoutIsSport = sportsKeywords.contains { workout.contains($0) }
        let activityIsSport = sportsKeywords.contains { activity.contains($0) }
        if workoutIsSport && activityIsSport { return 0.5 }
        
        return nil
    }
}

/// Pattern for matching triggers to activities
public struct TriggerPattern: Sendable {
    public let type: ActivityTrigger.TriggerType
    public let conditions: PatternConditions
    public let confidence: Double
    
    public struct PatternConditions: Sendable {
        public let timeOfDayRange: ClosedRange<Int>?
        public let daysOfWeek: Set<Int>?
        public let workoutTypeKeywords: [String]?
        public let locationKeywords: [String]?
        
        public init(
            timeOfDayRange: ClosedRange<Int>? = nil,
            daysOfWeek: Set<Int>? = nil,
            workoutTypeKeywords: [String]? = nil,
            locationKeywords: [String]? = nil
        ) {
            self.timeOfDayRange = timeOfDayRange
            self.daysOfWeek = daysOfWeek
            self.workoutTypeKeywords = workoutTypeKeywords
            self.locationKeywords = locationKeywords
        }
    }
    
    public init(
        type: ActivityTrigger.TriggerType,
        conditions: PatternConditions,
        confidence: Double = 0.8
    ) {
        self.type = type
        self.conditions = conditions
        self.confidence = confidence
    }
    
    /// Check if context matches this pattern
    public func matches(context: ActivityTrigger.TriggerContext, activityId: String) -> ActivityTrigger? {
        var matchScore = 0
        var totalConditions = 0
        
        // Check time of day
        if let range = conditions.timeOfDayRange {
            totalConditions += 1
            if range.contains(context.hour) {
                matchScore += 1
            }
        }
        
        // Check day of week
        if let days = conditions.daysOfWeek {
            totalConditions += 1
            if days.contains(context.dayOfWeek) {
                matchScore += 1
            }
        }
        
        // Check workout type keywords
        if let keywords = conditions.workoutTypeKeywords, let workout = context.workoutType {
            totalConditions += 1
            let workoutLower = workout.lowercased()
            if keywords.contains(where: { workoutLower.contains($0.lowercased()) }) {
                matchScore += 1
            }
        }
        
        // Check location keywords
        if let keywords = conditions.locationKeywords, let location = context.locationName {
            totalConditions += 1
            let locationLower = location.lowercased()
            if keywords.contains(where: { locationLower.contains($0.lowercased()) }) {
                matchScore += 1
            }
        }
        
        // Require at least half conditions met
        guard totalConditions > 0, matchScore >= (totalConditions + 1) / 2 else {
            return nil
        }
        
        let adjustedConfidence = confidence * Double(matchScore) / Double(totalConditions)
        
        return ActivityTrigger(
            type: type,
            confidence: adjustedConfidence,
            matchedActivityId: activityId,
            context: context
        )
    }
}

// MARK: - Activity Proposal Generator (ALG-LEARN-023)

/// Generates proposals for activity-based overrides
public actor ActivityProposalGenerator {
    
    /// Agent bootstrapper for accessing trained agents
    private let bootstrapper: ActivityAgentBootstrapper
    
    /// Trigger detector
    private let triggerDetector: ActivityTriggerDetector
    
    /// Templates for each activity
    private var templates: [String: ActivityProposalTemplate] = [:]
    
    /// Minimum confidence to generate proposal
    public let minConfidenceForProposal: Double
    
    /// Minimum training sessions to generate proposal
    public let minSessionsForProposal: Int
    
    public init(
        bootstrapper: ActivityAgentBootstrapper,
        triggerDetector: ActivityTriggerDetector = ActivityTriggerDetector(),
        minConfidenceForProposal: Double = 0.5,
        minSessionsForProposal: Int = 3
    ) {
        self.bootstrapper = bootstrapper
        self.triggerDetector = triggerDetector
        self.minConfidenceForProposal = minConfidenceForProposal
        self.minSessionsForProposal = minSessionsForProposal
    }
    
    /// Register a template for an activity
    public func registerTemplate(_ template: ActivityProposalTemplate) {
        templates[template.activityAgentId] = template
    }
    
    /// Generate a proposal from a trigger
    public func generateProposal(from trigger: ActivityTrigger) async -> ActivityProposal? {
        guard let activityId = trigger.matchedActivityId else { return nil }
        
        // Get the agent stub
        guard let stub = await bootstrapper.agent(for: activityId) else { return nil }
        
        // Check if agent is trained enough
        let status = await stub.trainingStatus
        guard status.canSuggest else { return nil }
        
        let sessionCount = await stub.sessionCount
        guard sessionCount >= minSessionsForProposal else { return nil }
        
        let confidence = await stub.confidence
        guard confidence >= minConfidenceForProposal else { return nil }
        
        // Get learned settings
        let learnedSettings = await stub.learnedSettings
        let definition = stub.overrideDefinition  // let property of Sendable type is nonisolated
        
        // Get or create template
        let template = templates[activityId] ?? createDefaultTemplate(for: definition)
        
        // Build the proposal
        let description = template.generateDescription(activityName: definition.name)
        let rationale = template.generateRationale(sessions: sessionCount, confidence: confidence)
        
        return ActivityProposal(
            id: UUID(),
            activityId: activityId,
            activityName: definition.name,
            trigger: trigger,
            description: description,
            rationale: rationale,
            suggestedSettings: learnedSettings,
            duration: template.defaultDuration,
            confidence: confidence,
            sessionCount: sessionCount,
            expiresAt: Date().addingTimeInterval(Double(template.proposalExpiryMinutes) * 60)
        )
    }
    
    /// Generate proposals from detected triggers
    public func generateProposals(context: ActivityTrigger.TriggerContext) async -> [ActivityProposal] {
        let triggers = await triggerDetector.detectTriggers(context: context)
        
        var proposals: [ActivityProposal] = []
        for trigger in triggers {
            if let proposal = await generateProposal(from: trigger) {
                proposals.append(proposal)
            }
        }
        
        return proposals
    }
    
    /// Generate proposal from workout detection
    public func generateProposalForWorkout(type: String) async -> ActivityProposal? {
        guard let trigger = await triggerDetector.matchWorkout(type: type) else { return nil }
        return await generateProposal(from: trigger)
    }
    
    private func createDefaultTemplate(for definition: UserOverrideDefinition) -> ActivityProposalTemplate {
        ActivityProposalTemplate(
            id: "default-\(definition.id)",
            name: definition.name,
            activityAgentId: definition.id,
            descriptionTemplate: "Starting \(definition.name)?",
            rationaleTemplate: "Learned from {sessions} sessions ({confidence}% success rate)"
        )
    }
}

/// Activity-specific proposal (before conversion to AgentProposal)
public struct ActivityProposal: Sendable, Identifiable {
    public let id: UUID
    public let activityId: String
    public let activityName: String
    public let trigger: ActivityTrigger
    public let description: String
    public let rationale: String
    public let suggestedSettings: OverrideSettings
    public let duration: TimeInterval
    public let confidence: Double
    public let sessionCount: Int
    public let expiresAt: Date
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        activityId: String,
        activityName: String,
        trigger: ActivityTrigger,
        description: String,
        rationale: String,
        suggestedSettings: OverrideSettings,
        duration: TimeInterval,
        confidence: Double,
        sessionCount: Int,
        expiresAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.activityId = activityId
        self.activityName = activityName
        self.trigger = trigger
        self.description = description
        self.rationale = rationale
        self.suggestedSettings = suggestedSettings
        self.duration = duration
        self.confidence = confidence
        self.sessionCount = sessionCount
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
    
    /// Human-readable settings summary
    public var settingsSummary: String {
        var parts: [String] = []
        
        if suggestedSettings.basalMultiplier != 1.0 {
            let percent = Int((1 - suggestedSettings.basalMultiplier) * 100)
            parts.append("\(percent > 0 ? "-" : "+")\(abs(percent))% basal")
        }
        
        if suggestedSettings.isfMultiplier != 1.0 {
            let percent = Int((suggestedSettings.isfMultiplier - 1) * 100)
            parts.append("\(percent > 0 ? "+" : "")\(percent)% ISF")
        }
        
        if let target = suggestedSettings.targetGlucose {
            parts.append("target \(Int(target))")
        }
        
        let durationMins = Int(duration / 60)
        parts.append("for \(durationMins) min")
        
        return parts.joined(separator: ", ")
    }
}

// MARK: - Proposal Outcome Tracker (ALG-LEARN-024)

/// Tracks proposal acceptance/rejection to feed back into agent training
public actor ProposalOutcomeTracker {
    
    /// Agent bootstrapper for updating training
    private let bootstrapper: ActivityAgentBootstrapper
    
    /// Tracked proposals awaiting outcome
    private var pendingProposals: [UUID: ActivityProposal] = [:]
    
    /// Outcome history
    private var outcomes: [ProposalOutcome] = []
    
    /// Maximum outcomes to keep
    private let maxOutcomes: Int
    
    public init(
        bootstrapper: ActivityAgentBootstrapper,
        maxOutcomes: Int = 500
    ) {
        self.bootstrapper = bootstrapper
        self.maxOutcomes = maxOutcomes
    }
    
    /// Record a proposal that's pending user action
    public func trackProposal(_ proposal: ActivityProposal) {
        pendingProposals[proposal.id] = proposal
    }
    
    /// Record acceptance of a proposal
    public func recordAcceptance(proposalId: UUID, modifications: SettingsModification? = nil) async {
        guard let proposal = pendingProposals.removeValue(forKey: proposalId) else { return }
        
        let outcome = ProposalOutcome(
            proposalId: proposalId,
            activityId: proposal.activityId,
            action: .accepted,
            modifications: modifications,
            timestamp: Date()
        )
        outcomes.append(outcome)
        trimOutcomes()
        
        // If user modified settings, that's a training signal
        if let mods = modifications {
            await updateAgentFromFeedback(
                activityId: proposal.activityId,
                originalSettings: proposal.suggestedSettings,
                modifications: mods
            )
        }
    }
    
    /// Record rejection of a proposal
    public func recordRejection(proposalId: UUID, reason: RejectionReason) async {
        guard let proposal = pendingProposals.removeValue(forKey: proposalId) else { return }
        
        let outcome = ProposalOutcome(
            proposalId: proposalId,
            activityId: proposal.activityId,
            action: .rejected(reason: reason),
            modifications: nil,
            timestamp: Date()
        )
        outcomes.append(outcome)
        trimOutcomes()
        
        // Rejection is also a training signal
        await recordRejectionFeedback(
            activityId: proposal.activityId,
            reason: reason
        )
    }
    
    /// Record that proposal expired without action
    public func recordExpiry(proposalId: UUID) {
        guard let proposal = pendingProposals.removeValue(forKey: proposalId) else { return }
        
        let outcome = ProposalOutcome(
            proposalId: proposalId,
            activityId: proposal.activityId,
            action: .expired,
            modifications: nil,
            timestamp: Date()
        )
        outcomes.append(outcome)
        trimOutcomes()
    }
    
    /// Get acceptance rate for an activity
    public func acceptanceRate(for activityId: String) -> Double? {
        let activityOutcomes = outcomes.filter { $0.activityId == activityId }
        guard activityOutcomes.count >= 3 else { return nil }
        
        let accepted = activityOutcomes.filter {
            if case .accepted = $0.action { return true }
            return false
        }.count
        
        return Double(accepted) / Double(activityOutcomes.count)
    }
    
    /// Get recent outcomes
    public func recentOutcomes(limit: Int = 20) -> [ProposalOutcome] {
        Array(outcomes.suffix(limit))
    }
    
    private func trimOutcomes() {
        if outcomes.count > maxOutcomes {
            outcomes.removeFirst(outcomes.count - maxOutcomes)
        }
    }
    
    private func updateAgentFromFeedback(
        activityId: String,
        originalSettings: OverrideSettings,
        modifications: SettingsModification
    ) async {
        // User modified the suggested settings - this tells us the learned settings
        // weren't quite right. We could use this to nudge the agent's learned parameters.
        // For now, just log the feedback. Full implementation would adjust learned settings.
    }
    
    private func recordRejectionFeedback(
        activityId: String,
        reason: RejectionReason
    ) async {
        // Rejection feedback can inform the agent:
        // - wrongTiming: trigger detection needs adjustment
        // - wrongActivity: workout matching is off
        // - dontNeedIt: maybe this activity doesn't need an override
        // - settingsWrong: learned settings need adjustment
    }
}

/// Outcome of a proposal
public struct ProposalOutcome: Sendable {
    public let proposalId: UUID
    public let activityId: String
    public let action: ProposalAction
    public let modifications: SettingsModification?
    public let timestamp: Date
    
    public enum ProposalAction: Sendable {
        case accepted
        case rejected(reason: RejectionReason)
        case expired
    }
}

/// Reason for rejecting a proposal
public enum RejectionReason: String, Sendable, CaseIterable {
    case wrongTiming = "wrongTiming"
    case wrongActivity = "wrongActivity"
    case dontNeedIt = "dontNeedIt"
    case settingsWrong = "settingsWrong"
    case other = "other"
    
    public var displayText: String {
        switch self {
        case .wrongTiming: return "Not the right time"
        case .wrongActivity: return "Wrong activity detected"
        case .dontNeedIt: return "Don't need override for this"
        case .settingsWrong: return "Settings don't work for me"
        case .other: return "Other reason"
        }
    }
}

/// User modifications to suggested settings
public struct SettingsModification: Sendable {
    public let basalMultiplierDelta: Double?
    public let isfMultiplierDelta: Double?
    public let durationDelta: TimeInterval?
    
    public init(
        basalMultiplierDelta: Double? = nil,
        isfMultiplierDelta: Double? = nil,
        durationDelta: TimeInterval? = nil
    ) {
        self.basalMultiplierDelta = basalMultiplierDelta
        self.isfMultiplierDelta = isfMultiplierDelta
        self.durationDelta = durationDelta
    }
    
    /// Whether any modifications were made
    public var hasModifications: Bool {
        basalMultiplierDelta != nil || isfMultiplierDelta != nil || durationDelta != nil
    }
}

// MARK: - AgentProposal Bridge (ALG-LEARN-020)

/// Bridges ActivityProposal to the NightscoutKit AgentProposal system
public struct ActivityProposalBridge {
    
    /// Agent ID prefix for activity agents
    public static let agentIdPrefix = "activity-agent"
    
    /// Create a RegisteredAgent for an activity agent stub
    public static func createRegisteredAgent(
        from stub: ActivityAgentStub,
        definition: UserOverrideDefinition
    ) -> RegisteredAgentInfo {
        RegisteredAgentInfo(
            agentId: "\(agentIdPrefix)-\(definition.id)",
            name: "\(definition.name) Agent",
            description: "Learned activity agent for \(definition.name)",
            version: "1.0",
            capabilities: [.proposeOverride, .proposeTempTarget]
        )
    }
    
    /// Convert ActivityProposal to AgentProposal-compatible data
    public static func convertToProposalData(_ proposal: ActivityProposal) -> ActivityProposalData {
        ActivityProposalData(
            agentId: "\(agentIdPrefix)-\(proposal.activityId)",
            agentName: "\(proposal.activityName) Agent",
            proposalType: .override,
            description: proposal.description,
            rationale: proposal.rationale,
            expiresAt: proposal.expiresAt,
            overrideName: proposal.activityName,
            overrideDuration: proposal.duration,
            basalMultiplier: proposal.suggestedSettings.basalMultiplier,
            isfMultiplier: proposal.suggestedSettings.isfMultiplier,
            crMultiplier: proposal.suggestedSettings.crMultiplier,
            targetGlucose: proposal.suggestedSettings.targetGlucose
        )
    }
}

/// Information needed to register an agent
public struct RegisteredAgentInfo: Sendable {
    public let agentId: String
    public let name: String
    public let description: String
    public let version: String
    public let capabilities: Set<AgentCapabilityType>
    
    public enum AgentCapabilityType: String, Sendable {
        case proposeOverride
        case proposeTempTarget
        case proposeCarbs
        case viewGlucose
    }
}

/// Proposal data for bridge to AgentProposal
public struct ActivityProposalData: Sendable {
    public let agentId: String
    public let agentName: String
    public let proposalType: ProposalTypeEnum
    public let description: String
    public let rationale: String
    public let expiresAt: Date
    
    // Override-specific
    public let overrideName: String?
    public let overrideDuration: TimeInterval?
    public let basalMultiplier: Double?
    public let isfMultiplier: Double?
    public let crMultiplier: Double?
    public let targetGlucose: Double?
    
    public enum ProposalTypeEnum: String, Sendable {
        case override
        case tempTarget
    }
}
