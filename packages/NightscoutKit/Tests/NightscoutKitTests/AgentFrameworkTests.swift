// SPDX-License-Identifier: MIT
// AgentFrameworkTests.swift
// NightscoutKitTests
//
// Tests for agent framework (L9 autonomous proposals)
// Trace: CONTROL-007, CONTROL-008, CONTROL-009, CONTROL-010

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Registered Agent Tests

@Suite("Registered Agent")
struct RegisteredAgentTests {
    @Test("Default agent properties")
    func defaultProperties() {
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test Agent"
        )
        
        #expect(agent.agentId == "test-agent")
        #expect(agent.name == "Test Agent")
        #expect(agent.status == .active)
        #expect(agent.trustLevel == .untrusted)
        #expect(agent.capabilities.isEmpty)
    }
    
    @Test("Agent with capabilities")
    func withCapabilities() {
        let agent = RegisteredAgent(
            agentId: "capable-agent",
            name: "Capable Agent",
            capabilities: [.proposeOverride, .viewGlucose]
        )
        
        #expect(agent.capabilities.count == 2)
        #expect(agent.capabilities.contains(.proposeOverride))
    }
}

// MARK: - Agent Capability Tests

@Suite("Agent Capability")
struct AgentCapabilityTests {
    @Test("All capabilities have raw values")
    func rawValues() {
        for cap in AgentCapability.allCases {
            #expect(!cap.rawValue.isEmpty)
        }
    }
    
    @Test("Capability count")
    func count() {
        #expect(AgentCapability.allCases.count == 10)
    }
}

// MARK: - Agent Trust Level Tests

@Suite("Agent Trust Level")
struct AgentTrustLevelTests {
    @Test("Trust levels are comparable")
    func comparable() {
        #expect(AgentTrustLevel.untrusted < AgentTrustLevel.limited)
        #expect(AgentTrustLevel.limited < AgentTrustLevel.standard)
        #expect(AgentTrustLevel.standard < AgentTrustLevel.trusted)
    }
    
    @Test("Untrusted has no allowed proposals")
    func untrustedNoProposals() {
        #expect(AgentTrustLevel.untrusted.allowedProposalTypes.isEmpty)
    }
    
    @Test("Trusted has all proposal types")
    func trustedAllProposals() {
        let allowed = AgentTrustLevel.trusted.allowedProposalTypes
        #expect(allowed.count == ProposalType.allCases.count)
    }
    
    @Test("Limited allows temp target")
    func limitedAllowsTempTarget() {
        let allowed = AgentTrustLevel.limited.allowedProposalTypes
        #expect(allowed.contains(.tempTarget))
        #expect(!allowed.contains(.override))
    }
}

// MARK: - Delegation Grant Tests

@Suite("Delegation Grant")
struct DelegationGrantTests {
    @Test("Grant is valid when active")
    func validWhenActive() {
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        
        #expect(grant.isValid == true)
    }
    
    @Test("Grant is invalid when revoked")
    func invalidWhenRevoked() {
        var grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        grant.status = .revoked
        
        #expect(grant.isValid == false)
    }
    
    @Test("Grant is invalid when expired")
    func invalidWhenExpired() {
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            expiresAt: Date().addingTimeInterval(-3600),
            allowedCapabilities: [.proposeOverride]
        )
        
        #expect(grant.isValid == false)
    }
}

// MARK: - Delegation Restrictions Tests

@Suite("Delegation Restrictions")
struct DelegationRestrictionsTests {
    @Test("Default restrictions")
    func defaultRestrictions() {
        let restrictions = DelegationRestrictions.default
        
        #expect(restrictions.maxProposalsPerHour == 10)
        #expect(restrictions.maxOverrideDuration == 7200)
        #expect(restrictions.requireConfirmation == true)
    }
    
    @Test("Strict restrictions")
    func strictRestrictions() {
        let restrictions = DelegationRestrictions.strict
        
        #expect(restrictions.maxProposalsPerHour == 5)
        #expect(restrictions.maxOverrideDuration == 3600)
    }
    
    @Test("Permissive restrictions")
    func permissiveRestrictions() {
        let restrictions = DelegationRestrictions.permissive
        
        #expect(restrictions.requireConfirmation == false)
        #expect(restrictions.autoApproveTypes.contains(.tempTarget))
    }
}

// MARK: - Time Window Tests

@Suite("Time Window")
struct TimeWindowTests {
    @Test("Contains hour within range")
    func containsWithinRange() {
        let window = TimeWindow(startHour: 9, endHour: 17)
        
        // Create a date at 12:00
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        
        #expect(window.contains(noon) == true)
    }
    
    @Test("Does not contain hour outside range")
    func notContainsOutsideRange() {
        let window = TimeWindow(startHour: 9, endHour: 17)
        
        // Create a date at 20:00
        let evening = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        
        #expect(window.contains(evening) == false)
    }
}

// MARK: - Proposal Ingestion Result Tests

@Suite("Proposal Ingestion Result")
struct ProposalIngestionResultTests {
    @Test("Accepted result")
    func accepted() {
        let id = UUID()
        let result = ProposalIngestionResult.accepted(proposalId: id)
        
        if case .accepted(let resultId) = result {
            #expect(resultId == id)
        } else {
            #expect(Bool(false), "Expected accepted")
        }
    }
    
    @Test("Rejected result")
    func rejected() {
        let result = ProposalIngestionResult.rejected(reason: .agentNotRegistered)
        
        if case .rejected(let reason) = result {
            #expect(reason == .agentNotRegistered)
        } else {
            #expect(Bool(false), "Expected rejected")
        }
    }
}

// MARK: - Agent Audit Entry Tests

@Suite("Agent Audit Entry")
struct AgentAuditEntryTests {
    @Test("Audit entry creation")
    func creation() {
        let entry = AgentAuditEntry(
            agentId: "test-agent",
            action: .proposalSubmitted,
            details: ["type": "override"],
            outcome: .success
        )
        
        #expect(entry.agentId == "test-agent")
        #expect(entry.action == .proposalSubmitted)
        #expect(entry.outcome == .success)
        #expect(entry.details["type"] == "override")
    }
}

// MARK: - Agent Audit Action Tests

@Suite("Agent Audit Action")
struct AgentAuditActionTests {
    @Test("All actions have raw values")
    func rawValues() {
        let actions: [AgentAuditAction] = [
            .registered, .activated, .suspended, .revoked,
            .delegationGranted, .delegationRevoked,
            .proposalSubmitted, .proposalAutoApproved, .proposalApproved,
            .proposalRejected, .proposalExpired, .proposalExecuted,
            .rateLimitTriggered, .securityAlert
        ]
        
        for action in actions {
            #expect(!action.rawValue.isEmpty)
        }
    }
}

// MARK: - Agent Manager Tests

@Suite("Agent Manager")
struct AgentManagerTests {
    @Test("Register agent succeeds")
    func registerAgent() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        
        let result = await manager.registerAgent(agent)
        
        #expect(result == true)
        let count = await manager.agentCount
        #expect(count == 1)
    }
    
    @Test("Register duplicate fails")
    func registerDuplicate() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        
        _ = await manager.registerAgent(agent)
        let result = await manager.registerAgent(agent)
        
        #expect(result == false)
    }
    
    @Test("Get agent by ID")
    func getAgent() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test Agent")
        
        _ = await manager.registerAgent(agent)
        let retrieved = await manager.getAgent("test-agent")
        
        #expect(retrieved?.name == "Test Agent")
    }
    
    @Test("Set agent status")
    func setAgentStatus() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        
        _ = await manager.registerAgent(agent)
        await manager.setAgentStatus("test-agent", status: .suspended)
        
        let retrieved = await manager.getAgent("test-agent")
        #expect(retrieved?.status == .suspended)
    }
    
    @Test("Create delegation grant")
    func createGrant() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        
        let result = await manager.createGrant(grant)
        #expect(result == true)
        
        let grantCount = await manager.activeGrantCount
        #expect(grantCount == 1)
    }
    
    @Test("Revoke delegation grant")
    func revokeGrant() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        _ = await manager.createGrant(grant)
        
        await manager.revokeGrant(grant.id, revokedBy: "admin", reason: "testing")
        
        let retrieved = await manager.getGrant(grant.id)
        #expect(retrieved?.status == .revoked)
    }
    
    @Test("Ingest proposal from unknown agent fails")
    func ingestFromUnknownAgent() async {
        let manager = AgentManager()
        
        let proposal = AgentProposal(
            agentId: "unknown-agent",
            agentName: "Unknown",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let result = await manager.ingestProposal(proposal)
        
        if case .rejected(let reason) = result {
            #expect(reason == .agentNotRegistered)
        } else {
            #expect(Bool(false), "Expected rejection")
        }
    }
    
    @Test("Ingest proposal without delegation fails")
    func ingestWithoutDelegation() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test",
            trustLevel: .trusted
        )
        _ = await manager.registerAgent(agent)
        
        let proposal = AgentProposal(
            agentId: "test-agent",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let result = await manager.ingestProposal(proposal)
        
        if case .rejected(let reason) = result {
            #expect(reason == .noActiveDelegation)
        } else {
            #expect(Bool(false), "Expected rejection")
        }
    }
    
    @Test("Ingest valid proposal succeeds")
    func ingestValidProposal() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test",
            trustLevel: .trusted
        )
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        _ = await manager.createGrant(grant)
        
        let proposal = AgentProposal(
            agentId: "test-agent",
            agentName: "Test",
            proposalType: .override,
            description: "Test override",
            rationale: "Testing",
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let result = await manager.ingestProposal(proposal)
        
        if case .pendingReview(let id) = result {
            #expect(id == proposal.id)
        } else {
            #expect(Bool(false), "Expected pending review")
        }
    }
    
    @Test("Approve proposal")
    func approveProposal() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test", trustLevel: .trusted)
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        _ = await manager.createGrant(grant)
        
        let proposal = AgentProposal(
            agentId: "test-agent",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        _ = await manager.ingestProposal(proposal)
        
        await manager.approveProposal(proposal.id, by: "reviewer")
        
        let ingested = await manager.getProposal(proposal.id)
        #expect(ingested?.reviewStatus == .approved)
    }
    
    @Test("Reject proposal")
    func rejectProposal() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test", trustLevel: .trusted)
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        _ = await manager.createGrant(grant)
        
        let proposal = AgentProposal(
            agentId: "test-agent",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        _ = await manager.ingestProposal(proposal)
        
        await manager.rejectProposal(proposal.id, by: "reviewer", note: "Not allowed")
        
        let ingested = await manager.getProposal(proposal.id)
        #expect(ingested?.reviewStatus == .rejected)
    }
    
    @Test("Audit trail records actions")
    func auditTrail() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test")
        
        _ = await manager.registerAgent(agent)
        await manager.setAgentStatus("test-agent", status: .suspended)
        
        let entries = await manager.auditEntriesForAgent("test-agent")
        #expect(entries.count >= 2)
    }
    
    @Test("Get pending proposals")
    func pendingProposals() async {
        let manager = AgentManager()
        let agent = RegisteredAgent(agentId: "test-agent", name: "Test", trustLevel: .trusted)
        _ = await manager.registerAgent(agent)
        
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user@example.com",
            allowedCapabilities: [.proposeOverride]
        )
        _ = await manager.createGrant(grant)
        
        let proposal = AgentProposal(
            agentId: "test-agent",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        _ = await manager.ingestProposal(proposal)
        
        let pending = await manager.pendingProposals()
        #expect(pending.count == 1)
    }
}

// MARK: - Agent Logic Tests

@Suite("Agent Logic")
struct AgentLogicTests {
    @Test("Can submit with valid setup")
    func canSubmitValid() {
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test",
            trustLevel: .trusted
        )
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user",
            allowedCapabilities: [.proposeOverride]
        )
        
        let result = AgentLogic.canSubmit(
            agent: agent,
            proposalType: .override,
            grants: [grant]
        )
        
        #expect(result == true)
    }
    
    @Test("Cannot submit without capability")
    func cannotSubmitWithoutCapability() {
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test",
            trustLevel: .trusted
        )
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user",
            allowedCapabilities: [.viewGlucose] // No proposal capability
        )
        
        let result = AgentLogic.canSubmit(
            agent: agent,
            proposalType: .override,
            grants: [grant]
        )
        
        #expect(result == false)
    }
    
    @Test("Cannot submit with insufficient trust")
    func cannotSubmitInsufficientTrust() {
        let agent = RegisteredAgent(
            agentId: "test-agent",
            name: "Test",
            trustLevel: .untrusted
        )
        let grant = DelegationGrant(
            agentId: "test-agent",
            grantedBy: "user",
            allowedCapabilities: [.proposeOverride]
        )
        
        let result = AgentLogic.canSubmit(
            agent: agent,
            proposalType: .override,
            grants: [grant]
        )
        
        #expect(result == false)
    }
    
    @Test("Required capability for proposal types")
    func requiredCapability() {
        #expect(AgentLogic.requiredCapability(for: .override) == .proposeOverride)
        #expect(AgentLogic.requiredCapability(for: .tempTarget) == .proposeTempTarget)
        #expect(AgentLogic.requiredCapability(for: .carbs) == .proposeCarbs)
    }
    
    @Test("Validate proposal duration")
    func validateDuration() {
        let override = ProposedOverride(
            name: "Test",
            duration: 10800 // 3 hours
        )
        let proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600),
            proposedOverride: override
        )
        
        let restrictions = DelegationRestrictions(maxOverrideDuration: 7200) // 2 hours
        let errors = AgentLogic.validateProposal(proposal, restrictions: restrictions)
        
        #expect(errors.count == 1)
        #expect(errors.first?.contains("Duration") == true)
    }
    
    @Test("Default expiration varies by type")
    func defaultExpiration() {
        let overrideExp = AgentLogic.defaultExpiration(for: .override)
        let carbsExp = AgentLogic.defaultExpiration(for: .carbs)
        
        // Carbs should expire sooner than override
        #expect(carbsExp < overrideExp)
    }
}

// MARK: - Proposal Review Status Tests

@Suite("Proposal Review Status")
struct ProposalReviewStatusTests {
    @Test("All statuses have raw values")
    func rawValues() {
        let statuses: [ProposalReviewStatus] = [
            .pending, .autoApproved, .approved, .rejected,
            .expired, .executed, .failed
        ]
        
        for status in statuses {
            #expect(!status.rawValue.isEmpty)
        }
    }
}

// MARK: - Ingested Proposal Tests

@Suite("Ingested Proposal")
struct IngestedProposalTests {
    @Test("Creation from proposal")
    func creation() {
        let proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let ingested = IngestedProposal(proposal: proposal)
        
        #expect(ingested.id == proposal.id)
        #expect(ingested.reviewStatus == .pending)
        #expect(ingested.ingestedAt != nil)
    }
}
