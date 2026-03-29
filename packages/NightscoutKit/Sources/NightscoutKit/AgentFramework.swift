// SPDX-License-Identifier: AGPL-3.0-or-later
// AgentFramework.swift
// NightscoutKit
//
// Agent framework for L9 autonomous proposals
// Trace: CONTROL-007, CONTROL-008, CONTROL-009, CONTROL-010, agent-control-plane-integration.md

import Foundation

// MARK: - Agent Registration

/// Registered agent that can submit proposals
public struct RegisteredAgent: Sendable, Identifiable, Codable {
    public let id: UUID
    public let agentId: String
    public let name: String
    public let description: String
    public let version: String
    public let capabilities: Set<AgentCapability>
    public let registeredAt: Date
    public var lastSeenAt: Date
    public var status: AgentStatus
    public var trustLevel: AgentTrustLevel
    public let metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        agentId: String,
        name: String,
        description: String = "",
        version: String = "1.0",
        capabilities: Set<AgentCapability> = [],
        registeredAt: Date = Date(),
        lastSeenAt: Date = Date(),
        status: AgentStatus = .active,
        trustLevel: AgentTrustLevel = .untrusted,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.agentId = agentId
        self.name = name
        self.description = description
        self.version = version
        self.capabilities = capabilities
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
        self.status = status
        self.trustLevel = trustLevel
        self.metadata = metadata
    }
}

/// Capabilities an agent can have
public enum AgentCapability: String, Sendable, Codable, CaseIterable {
    case proposeOverride = "proposeOverride"
    case proposeTempTarget = "proposeTempTarget"
    case proposeCarbs = "proposeCarbs"
    case proposeProfile = "proposeProfile"
    case viewGlucose = "viewGlucose"
    case viewIOB = "viewIOB"
    case viewCOB = "viewCOB"
    case viewPredictions = "viewPredictions"
    case viewTreatments = "viewTreatments"
    case receiveAlerts = "receiveAlerts"
}

/// Status of an agent
public enum AgentStatus: String, Sendable, Codable {
    case pending = "pending"
    case active = "active"
    case suspended = "suspended"
    case revoked = "revoked"
}

/// Trust level for agents
public enum AgentTrustLevel: String, Sendable, Codable, Comparable, CaseIterable {
    case untrusted = "untrusted"
    case limited = "limited"
    case standard = "standard"
    case trusted = "trusted"
    
    public static func < (lhs: AgentTrustLevel, rhs: AgentTrustLevel) -> Bool {
        let order: [AgentTrustLevel] = [.untrusted, .limited, .standard, .trusted]
        guard let l = order.firstIndex(of: lhs),
              let r = order.firstIndex(of: rhs) else { return false }
        return l < r
    }
    
    /// Maximum proposal types this trust level can submit
    public var allowedProposalTypes: Set<ProposalType> {
        switch self {
        case .untrusted:
            return []
        case .limited:
            return [.tempTarget, .annotation]
        case .standard:
            return [.override, .tempTarget, .carbs, .annotation]
        case .trusted:
            return Set(ProposalType.allCases)
        }
    }
}

// MARK: - Delegation Grants

/// A delegation grant allows an agent to act on user's behalf
public struct DelegationGrant: Sendable, Identifiable, Codable {
    public let id: UUID
    public let agentId: String
    public let grantedBy: String
    public let grantedAt: Date
    public var expiresAt: Date?
    public let allowedCapabilities: Set<AgentCapability>
    public let restrictions: DelegationRestrictions
    public var status: DelegationStatus
    public var revokedAt: Date?
    public var revokedBy: String?
    public var revokeReason: String?
    
    public init(
        id: UUID = UUID(),
        agentId: String,
        grantedBy: String,
        grantedAt: Date = Date(),
        expiresAt: Date? = nil,
        allowedCapabilities: Set<AgentCapability>,
        restrictions: DelegationRestrictions = .default,
        status: DelegationStatus = .active
    ) {
        self.id = id
        self.agentId = agentId
        self.grantedBy = grantedBy
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.allowedCapabilities = allowedCapabilities
        self.restrictions = restrictions
        self.status = status
    }
    
    /// Check if grant is currently valid
    public var isValid: Bool {
        guard status == .active else { return false }
        if let expiresAt = expiresAt, Date() > expiresAt { return false }
        return true
    }
}

/// Restrictions on delegated capabilities
public struct DelegationRestrictions: Sendable, Codable, Equatable {
    /// Maximum proposals per hour
    public let maxProposalsPerHour: Int
    
    /// Maximum override duration allowed (seconds)
    public let maxOverrideDuration: TimeInterval
    
    /// Time window when agent is active (nil = always)
    public let activeTimeWindow: TimeWindow?
    
    /// Require user confirmation for proposals
    public let requireConfirmation: Bool
    
    /// Proposal types that auto-approve
    public let autoApproveTypes: Set<ProposalType>
    
    public init(
        maxProposalsPerHour: Int = 10,
        maxOverrideDuration: TimeInterval = 7200,
        activeTimeWindow: TimeWindow? = nil,
        requireConfirmation: Bool = true,
        autoApproveTypes: Set<ProposalType> = []
    ) {
        self.maxProposalsPerHour = maxProposalsPerHour
        self.maxOverrideDuration = maxOverrideDuration
        self.activeTimeWindow = activeTimeWindow
        self.requireConfirmation = requireConfirmation
        self.autoApproveTypes = autoApproveTypes
    }
    
    public static var `default`: DelegationRestrictions {
        DelegationRestrictions()
    }
    
    public static var strict: DelegationRestrictions {
        DelegationRestrictions(
            maxProposalsPerHour: 5,
            maxOverrideDuration: 3600,
            activeTimeWindow: nil,
            requireConfirmation: true,
            autoApproveTypes: []
        )
    }
    
    public static var permissive: DelegationRestrictions {
        DelegationRestrictions(
            maxProposalsPerHour: 50,
            maxOverrideDuration: 14400,
            activeTimeWindow: nil,
            requireConfirmation: false,
            autoApproveTypes: [.tempTarget, .annotation]
        )
    }
}

/// Time window for restrictions
public struct TimeWindow: Sendable, Codable, Equatable {
    public let startHour: Int
    public let endHour: Int
    public let timeZone: String
    
    public init(startHour: Int, endHour: Int, timeZone: String = "UTC") {
        self.startHour = startHour
        self.endHour = endHour
        self.timeZone = timeZone
    }
    
    /// Check if current time is within window
    public func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // Spans midnight
            return hour >= startHour || hour < endHour
        }
    }
}

/// Status of a delegation grant
public enum DelegationStatus: String, Sendable, Codable {
    case pending = "pending"
    case active = "active"
    case expired = "expired"
    case revoked = "revoked"
}

// MARK: - Proposal Ingestion

/// Result of proposal ingestion
public enum ProposalIngestionResult: Sendable, Equatable {
    case accepted(proposalId: UUID)
    case rejected(reason: ProposalRejectionReason)
    case pendingReview(proposalId: UUID)
}

/// Reasons for proposal rejection
public enum ProposalRejectionReason: String, Sendable, Codable, Equatable {
    case agentNotRegistered = "agentNotRegistered"
    case agentSuspended = "agentSuspended"
    case insufficientTrust = "insufficientTrust"
    case noActiveDelegation = "noActiveDelegation"
    case capabilityNotGranted = "capabilityNotGranted"
    case rateLimitExceeded = "rateLimitExceeded"
    case proposalExpired = "proposalExpired"
    case invalidParameters = "invalidParameters"
    case restrictionViolation = "restrictionViolation"
    case duplicateProposal = "duplicateProposal"
}

/// Ingested proposal awaiting review
public struct IngestedProposal: Sendable, Identifiable {
    public let id: UUID
    public let proposal: AgentProposal
    public let ingestedAt: Date
    public var reviewStatus: ProposalReviewStatus
    public var reviewedAt: Date?
    public var reviewedBy: String?
    public var reviewNote: String?
    public var executedAt: Date?
    public var executionResult: String?
    
    public init(proposal: AgentProposal) {
        self.id = proposal.id
        self.proposal = proposal
        self.ingestedAt = Date()
        self.reviewStatus = .pending
    }
}

/// Review status for ingested proposals
public enum ProposalReviewStatus: String, Sendable, Codable {
    case pending = "pending"
    case autoApproved = "autoApproved"
    case approved = "approved"
    case rejected = "rejected"
    case expired = "expired"
    case executed = "executed"
    case failed = "failed"
}

// MARK: - Audit Trail

/// Audit entry for agent actions
public struct AgentAuditEntry: Sendable, Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let agentId: String
    public let action: AgentAuditAction
    public let details: [String: String]
    public let outcome: AuditOutcome
    public let userId: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentId: String,
        action: AgentAuditAction,
        details: [String: String] = [:],
        outcome: AuditOutcome,
        userId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentId = agentId
        self.action = action
        self.details = details
        self.outcome = outcome
        self.userId = userId
    }
}

/// Types of auditable agent actions
public enum AgentAuditAction: String, Sendable, Codable {
    case registered = "registered"
    case activated = "activated"
    case suspended = "suspended"
    case revoked = "revoked"
    case delegationGranted = "delegationGranted"
    case delegationRevoked = "delegationRevoked"
    case proposalSubmitted = "proposalSubmitted"
    case proposalAutoApproved = "proposalAutoApproved"
    case proposalApproved = "proposalApproved"
    case proposalRejected = "proposalRejected"
    case proposalExpired = "proposalExpired"
    case proposalExecuted = "proposalExecuted"
    case rateLimitTriggered = "rateLimitTriggered"
    case securityAlert = "securityAlert"
}

/// Outcome of audited action
public enum AuditOutcome: String, Sendable, Codable {
    case success = "success"
    case failure = "failure"
    case warning = "warning"
}

// MARK: - Agent Manager Actor

/// Actor for managing agents, delegations, and proposals
public actor AgentManager {
    /// Registered agents
    private var agents: [String: RegisteredAgent] = [:]
    
    /// Active delegation grants
    private var grants: [UUID: DelegationGrant] = [:]
    
    /// Ingested proposals
    private var proposals: [UUID: IngestedProposal] = [:]
    
    /// Proposal counts for rate limiting (agentId -> timestamps)
    private var proposalCounts: [String: [Date]] = [:]
    
    /// Audit trail
    private var auditTrail: [AgentAuditEntry] = []
    private let maxAuditEntries: Int = 10000
    
    public init() {}
    
    // MARK: - Agent Registration
    
    /// Register a new agent
    public func registerAgent(_ agent: RegisteredAgent) -> Bool {
        guard agents[agent.agentId] == nil else {
            auditLog(agentId: agent.agentId, action: .registered, outcome: .failure,
                    details: ["reason": "already_registered"])
            return false
        }
        
        agents[agent.agentId] = agent
        auditLog(agentId: agent.agentId, action: .registered, outcome: .success,
                details: ["name": agent.name, "version": agent.version])
        return true
    }
    
    /// Get agent by ID
    public func getAgent(_ agentId: String) -> RegisteredAgent? {
        agents[agentId]
    }
    
    /// Update agent status
    public func setAgentStatus(_ agentId: String, status: AgentStatus) {
        guard var agent = agents[agentId] else { return }
        
        let oldStatus = agent.status
        agent.status = status
        agents[agentId] = agent
        
        let action: AgentAuditAction
        switch status {
        case .active: action = .activated
        case .suspended: action = .suspended
        case .revoked: action = .revoked
        case .pending: action = .registered
        }
        
        auditLog(agentId: agentId, action: action, outcome: .success,
                details: ["oldStatus": oldStatus.rawValue, "newStatus": status.rawValue])
    }
    
    /// Update agent trust level
    public func setTrustLevel(_ agentId: String, level: AgentTrustLevel) {
        guard var agent = agents[agentId] else { return }
        agent.trustLevel = level
        agents[agentId] = agent
    }
    
    /// Get all registered agents
    public func allAgents() -> [RegisteredAgent] {
        Array(agents.values)
    }
    
    // MARK: - Delegation Management
    
    /// Create a delegation grant
    public func createGrant(_ grant: DelegationGrant) -> Bool {
        // Verify agent exists
        guard let agent = agents[grant.agentId], agent.status == .active else {
            return false
        }
        
        grants[grant.id] = grant
        auditLog(agentId: grant.agentId, action: .delegationGranted, outcome: .success,
                details: ["grantId": grant.id.uuidString, "grantedBy": grant.grantedBy])
        return true
    }
    
    /// Revoke a delegation grant
    public func revokeGrant(_ grantId: UUID, revokedBy: String, reason: String) {
        guard var grant = grants[grantId] else { return }
        
        grant.status = .revoked
        grant.revokedAt = Date()
        grant.revokedBy = revokedBy
        grant.revokeReason = reason
        grants[grantId] = grant
        
        auditLog(agentId: grant.agentId, action: .delegationRevoked, outcome: .success,
                details: ["grantId": grantId.uuidString, "revokedBy": revokedBy, "reason": reason])
    }
    
    /// Get active grants for an agent
    public func grantsForAgent(_ agentId: String) -> [DelegationGrant] {
        grants.values.filter { $0.agentId == agentId && $0.isValid }
    }
    
    /// Get grant by ID
    public func getGrant(_ id: UUID) -> DelegationGrant? {
        grants[id]
    }
    
    // MARK: - Proposal Ingestion
    
    /// Ingest a proposal from an agent
    public func ingestProposal(_ proposal: AgentProposal) -> ProposalIngestionResult {
        // Validate agent
        guard let agent = agents[proposal.agentId] else {
            return .rejected(reason: .agentNotRegistered)
        }
        
        guard agent.status == .active else {
            return .rejected(reason: .agentSuspended)
        }
        
        // Check trust level allows this proposal type
        guard agent.trustLevel.allowedProposalTypes.contains(proposal.proposalType) else {
            auditLog(agentId: proposal.agentId, action: .proposalSubmitted, outcome: .failure,
                    details: ["reason": "insufficientTrust", "type": proposal.proposalType.rawValue])
            return .rejected(reason: .insufficientTrust)
        }
        
        // Find active delegation
        let activeGrants = grantsForAgentSync(proposal.agentId)
        guard !activeGrants.isEmpty else {
            return .rejected(reason: .noActiveDelegation)
        }
        
        // Check capability granted
        let requiredCapability = capabilityFor(proposal.proposalType)
        let hasCapability = activeGrants.contains { $0.allowedCapabilities.contains(requiredCapability) }
        guard hasCapability else {
            return .rejected(reason: .capabilityNotGranted)
        }
        
        // Check rate limit
        let grant = activeGrants.first!
        if !checkRateLimit(agentId: proposal.agentId, limit: grant.restrictions.maxProposalsPerHour) {
            auditLog(agentId: proposal.agentId, action: .rateLimitTriggered, outcome: .warning,
                    details: ["type": proposal.proposalType.rawValue])
            return .rejected(reason: .rateLimitExceeded)
        }
        
        // Check proposal not expired
        if proposal.isExpired {
            return .rejected(reason: .proposalExpired)
        }
        
        // Accept proposal
        var ingested = IngestedProposal(proposal: proposal)
        
        // Check for auto-approve
        if grant.restrictions.autoApproveTypes.contains(proposal.proposalType) && 
           !grant.restrictions.requireConfirmation {
            ingested.reviewStatus = .autoApproved
            auditLog(agentId: proposal.agentId, action: .proposalAutoApproved, outcome: .success,
                    details: ["proposalId": proposal.id.uuidString, "type": proposal.proposalType.rawValue])
        } else {
            auditLog(agentId: proposal.agentId, action: .proposalSubmitted, outcome: .success,
                    details: ["proposalId": proposal.id.uuidString, "type": proposal.proposalType.rawValue])
        }
        
        proposals[proposal.id] = ingested
        recordProposal(agentId: proposal.agentId)
        
        if ingested.reviewStatus == .autoApproved {
            return .accepted(proposalId: proposal.id)
        } else {
            return .pendingReview(proposalId: proposal.id)
        }
    }
    
    /// Helper for sync grant lookup
    private func grantsForAgentSync(_ agentId: String) -> [DelegationGrant] {
        grants.values.filter { $0.agentId == agentId && $0.isValid }
    }
    
    /// Get capability required for proposal type
    private func capabilityFor(_ type: ProposalType) -> AgentCapability {
        switch type {
        case .override: return .proposeOverride
        case .tempTarget: return .proposeTempTarget
        case .carbs: return .proposeCarbs
        case .profile: return .proposeProfile
        case .annotation: return .receiveAlerts
        case .suspendDelivery, .resumeDelivery: return .proposeOverride
        }
    }
    
    // MARK: - Proposal Review
    
    /// Approve a proposal
    public func approveProposal(_ id: UUID, by reviewer: String, note: String? = nil) {
        guard var ingested = proposals[id] else { return }
        
        ingested.reviewStatus = .approved
        ingested.reviewedAt = Date()
        ingested.reviewedBy = reviewer
        ingested.reviewNote = note
        proposals[id] = ingested
        
        auditLog(agentId: ingested.proposal.agentId, action: .proposalApproved, outcome: .success,
                details: ["proposalId": id.uuidString, "reviewer": reviewer])
    }
    
    /// Reject a proposal
    public func rejectProposal(_ id: UUID, by reviewer: String, note: String) {
        guard var ingested = proposals[id] else { return }
        
        ingested.reviewStatus = .rejected
        ingested.reviewedAt = Date()
        ingested.reviewedBy = reviewer
        ingested.reviewNote = note
        proposals[id] = ingested
        
        auditLog(agentId: ingested.proposal.agentId, action: .proposalRejected, outcome: .success,
                details: ["proposalId": id.uuidString, "reviewer": reviewer, "reason": note])
    }
    
    /// Mark proposal as executed
    public func markExecuted(_ id: UUID, result: String) {
        guard var ingested = proposals[id] else { return }
        
        ingested.reviewStatus = .executed
        ingested.executedAt = Date()
        ingested.executionResult = result
        proposals[id] = ingested
        
        auditLog(agentId: ingested.proposal.agentId, action: .proposalExecuted, outcome: .success,
                details: ["proposalId": id.uuidString, "result": result])
    }
    
    /// Get pending proposals for review
    public func pendingProposals() -> [IngestedProposal] {
        proposals.values.filter { $0.reviewStatus == .pending }
    }
    
    /// Get approved proposals ready for execution
    public func approvedProposals() -> [IngestedProposal] {
        proposals.values.filter { 
            $0.reviewStatus == .approved || $0.reviewStatus == .autoApproved 
        }
    }
    
    /// Get proposal by ID
    public func getProposal(_ id: UUID) -> IngestedProposal? {
        proposals[id]
    }
    
    // MARK: - Rate Limiting
    
    private func checkRateLimit(agentId: String, limit: Int) -> Bool {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Clean old entries
        var counts = proposalCounts[agentId] ?? []
        counts = counts.filter { $0 > oneHourAgo }
        proposalCounts[agentId] = counts
        
        return counts.count < limit
    }
    
    private func recordProposal(agentId: String) {
        var counts = proposalCounts[agentId] ?? []
        counts.append(Date())
        proposalCounts[agentId] = counts
    }
    
    // MARK: - Audit Trail
    
    private func auditLog(
        agentId: String,
        action: AgentAuditAction,
        outcome: AuditOutcome,
        details: [String: String] = [:],
        userId: String? = nil
    ) {
        let entry = AgentAuditEntry(
            agentId: agentId,
            action: action,
            details: details,
            outcome: outcome,
            userId: userId
        )
        
        auditTrail.append(entry)
        
        // Trim if needed
        if auditTrail.count > maxAuditEntries {
            auditTrail.removeFirst(auditTrail.count - maxAuditEntries)
        }
    }
    
    /// Get audit entries for an agent
    public func auditEntriesForAgent(_ agentId: String, limit: Int = 100) -> [AgentAuditEntry] {
        auditTrail.filter { $0.agentId == agentId }.suffix(limit).reversed()
    }
    
    /// Get recent audit entries
    public func recentAuditEntries(limit: Int = 100) -> [AgentAuditEntry] {
        Array(auditTrail.suffix(limit).reversed())
    }
    
    /// Get audit entries by action
    public func auditEntriesByAction(_ action: AgentAuditAction, limit: Int = 100) -> [AgentAuditEntry] {
        auditTrail.filter { $0.action == action }.suffix(limit).reversed()
    }
    
    // MARK: - Statistics
    
    public var agentCount: Int { agents.count }
    public var activeAgentCount: Int { agents.values.filter { $0.status == .active }.count }
    public var grantCount: Int { grants.count }
    public var activeGrantCount: Int { grants.values.filter { $0.isValid }.count }
    public var pendingProposalCount: Int { proposals.values.filter { $0.reviewStatus == .pending }.count }
    public var auditEntryCount: Int { auditTrail.count }
}

// MARK: - Agent Logic

/// Logic for agent framework operations
public enum AgentLogic {
    /// Check if agent can submit proposal type
    public static func canSubmit(
        agent: RegisteredAgent,
        proposalType: ProposalType,
        grants: [DelegationGrant]
    ) -> Bool {
        guard agent.status == .active else { return false }
        guard agent.trustLevel.allowedProposalTypes.contains(proposalType) else { return false }
        
        let required = requiredCapability(for: proposalType)
        return grants.contains { $0.isValid && $0.allowedCapabilities.contains(required) }
    }
    
    /// Get required capability for proposal type
    public static func requiredCapability(for type: ProposalType) -> AgentCapability {
        switch type {
        case .override: return .proposeOverride
        case .tempTarget: return .proposeTempTarget
        case .carbs: return .proposeCarbs
        case .profile: return .proposeProfile
        case .annotation: return .receiveAlerts
        case .suspendDelivery, .resumeDelivery: return .proposeOverride
        }
    }
    
    /// Validate proposal parameters
    public static func validateProposal(
        _ proposal: AgentProposal,
        restrictions: DelegationRestrictions
    ) -> [String] {
        var errors: [String] = []
        
        // Check duration for overrides
        if proposal.proposalType == .override,
           let override = proposal.proposedOverride {
            let duration = override.duration
            if duration > restrictions.maxOverrideDuration {
                errors.append("Duration exceeds maximum allowed (\(Int(restrictions.maxOverrideDuration / 60)) minutes)")
            }
        }
        
        // Check time window
        if let window = restrictions.activeTimeWindow,
           !window.contains(Date()) {
            errors.append("Current time outside allowed window")
        }
        
        return errors
    }
    
    /// Calculate expiration for proposal based on type
    public static func defaultExpiration(for type: ProposalType) -> Date {
        let minutes: Double
        switch type {
        case .override: minutes = 30
        case .tempTarget: minutes = 30
        case .carbs: minutes = 15
        case .profile: minutes = 60
        case .annotation: minutes = 60
        case .suspendDelivery, .resumeDelivery: minutes = 15
        }
        return Date().addingTimeInterval(minutes * 60)
    }
}
