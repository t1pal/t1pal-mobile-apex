// SPDX-License-Identifier: MIT
// ControlPlaneTests.swift
// NightscoutKitTests
//
// Tests for control plane events and agent proposals
// Trace: RESEARCH-001

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Event Source Tests

@Suite("EventSource")
struct EventSourceTests {
    
    @Test("All sources are codable")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for source in [EventSource.user, .app, .agent, .caregiver, .system] {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(EventSource.self, from: data)
            #expect(decoded == source)
        }
    }
}

// MARK: - Profile Selection Event Tests

@Suite("ProfileSelectionEvent")
struct ProfileSelectionEventTests {
    
    @Test("Create profile selection event")
    func create() {
        let event = ProfileSelectionEvent(
            profileName: "Exercise",
            previousProfileName: "Default",
            reason: "Going for a run"
        )
        
        #expect(event.profileName == "Exercise")
        #expect(event.previousProfileName == "Default")
        #expect(event.source == .user)
        #expect(ProfileSelectionEvent.eventType == "profileSelection")
    }
    
    @Test("Event is codable")
    func codable() throws {
        let event = ProfileSelectionEvent(
            source: .caregiver,
            profileName: "Low Carb"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(ProfileSelectionEvent.self, from: data)
        
        #expect(decoded.id == event.id)
        #expect(decoded.profileName == event.profileName)
        #expect(decoded.source == .caregiver)
    }
}

// MARK: - Override Instance Event Tests

@Suite("OverrideInstanceEvent")
struct OverrideInstanceEventTests {
    
    @Test("Create override with all parameters")
    func createFull() {
        let event = OverrideInstanceEvent(
            source: .agent,
            overrideName: "Exercise",
            duration: 3600,
            targetRange: 140...160,
            insulinSensitivityMultiplier: 1.5,
            carbRatioMultiplier: 1.0,
            basalMultiplier: 0.5,
            reason: "Detected exercise pattern"
        )
        
        #expect(event.overrideName == "Exercise")
        #expect(event.duration == 3600)
        #expect(event.targetRange == 140...160)
        #expect(event.insulinSensitivityMultiplier == 1.5)
        #expect(event.basalMultiplier == 0.5)
        #expect(event.source == .agent)
    }
    
    @Test("Event type is correct")
    func eventType() {
        #expect(OverrideInstanceEvent.eventType == "overrideInstance")
    }
}

// MARK: - Override Cancel Event Tests

@Suite("OverrideCancelEvent")
struct OverrideCancelEventTests {
    
    @Test("Create cancel event")
    func create() {
        let overrideId = UUID()
        let event = OverrideCancelEvent(
            overrideInstanceId: overrideId,
            reason: "User requested cancellation"
        )
        
        #expect(event.overrideInstanceId == overrideId)
        #expect(event.source == .user)
        #expect(OverrideCancelEvent.eventType == "overrideCancel")
    }
}

// MARK: - Delivery Event Tests

@Suite("DeliveryEvent")
struct DeliveryEventTests {
    
    @Test("Create bolus delivery")
    func bolus() {
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 2.5,
            reason: "Meal bolus"
        )
        
        #expect(event.deliveryType == .bolus)
        #expect(event.units == 2.5)
        #expect(event.source == .app)
    }
    
    @Test("Create temp basal delivery")
    func tempBasal() {
        let event = DeliveryEvent(
            deliveryType: .tempBasal,
            units: 0.75,
            duration: 1800,
            rate: 1.5,
            reason: "Algorithm adjustment"
        )
        
        #expect(event.deliveryType == .tempBasal)
        #expect(event.duration == 1800)
        #expect(event.rate == 1.5)
    }
    
    @Test("Create SMB delivery")
    func smb() {
        let event = DeliveryEvent(
            deliveryType: .smb,
            units: 0.3,
            reason: "Predicted high"
        )
        
        #expect(event.deliveryType == .smb)
        #expect(event.units == 0.3)
    }
    
    @Test("All delivery types")
    func allTypes() {
        let types: [DeliveryType] = [.bolus, .correctionBolus, .smb, .tempBasal, .scheduledBasal, .suspend, .resume]
        #expect(types.count == 7)
    }
}

// MARK: - Agent Proposal Tests

@Suite("AgentProposal")
struct AgentProposalTests {
    
    @Test("Create proposal with override")
    func createWithOverride() {
        let proposal = AgentProposal(
            agentId: "agent-001",
            agentName: "Exercise Agent",
            proposalType: .override,
            description: "Enable exercise mode",
            rationale: "Detected increased activity via HealthKit",
            expiresAt: Date().addingTimeInterval(300),
            proposedOverride: ProposedOverride(
                name: "Exercise",
                duration: 3600,
                targetRange: 140...160,
                basalMultiplier: 0.5
            )
        )
        
        #expect(proposal.agentId == "agent-001")
        #expect(proposal.proposalType == .override)
        #expect(proposal.status == .pending)
        #expect(proposal.proposedOverride?.name == "Exercise")
        #expect(proposal.isActionable == true)
    }
    
    @Test("Create proposal with temp target")
    func createWithTempTarget() {
        let proposal = AgentProposal(
            agentId: "agent-002",
            agentName: "Meal Agent",
            proposalType: .tempTarget,
            description: "Pre-bolus temp target",
            rationale: "Meal announced in 30 minutes",
            expiresAt: Date().addingTimeInterval(600),
            proposedTempTarget: ProposedTempTarget(
                targetRange: 80...90,
                duration: 1800,
                reason: "Pre-meal"
            )
        )
        
        #expect(proposal.proposalType == .tempTarget)
        #expect(proposal.proposedTempTarget?.targetRange == 80...90)
    }
    
    @Test("Proposal expiration")
    func expiration() {
        let expiredProposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(-60) // Already expired
        )
        
        #expect(expiredProposal.isExpired == true)
        #expect(expiredProposal.isActionable == false)
    }
    
    @Test("Approve proposal")
    func approve() {
        var proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        )
        
        proposal.approve(by: "user@example.com", note: "Looks good")
        
        #expect(proposal.status == .approved)
        #expect(proposal.reviewedBy == "user@example.com")
        #expect(proposal.reviewedAt != nil)
        #expect(proposal.reviewNote == "Looks good")
    }
    
    @Test("Reject proposal")
    func reject() {
        var proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .suspendDelivery,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        )
        
        proposal.reject(by: "admin", note: "Not appropriate")
        
        #expect(proposal.status == .rejected)
        #expect(proposal.isActionable == false)
    }
    
    @Test("Proposal is codable")
    func codable() throws {
        let proposal = AgentProposal(
            agentId: "agent-001",
            agentName: "Test Agent",
            proposalType: .tempTarget,
            description: "Test",
            rationale: "Testing",
            expiresAt: Date().addingTimeInterval(300),
            proposedTempTarget: ProposedTempTarget(
                targetRange: 100...120,
                duration: 1800,
                reason: "Test"
            )
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(proposal)
        let decoded = try decoder.decode(AgentProposal.self, from: data)
        
        #expect(decoded.id == proposal.id)
        #expect(decoded.agentId == proposal.agentId)
        #expect(decoded.proposalType == proposal.proposalType)
    }
}

// MARK: - Control Plane Event Bus Tests

@Suite("ControlPlaneEventBus")
struct ControlPlaneEventBusTests {
    
    @Test("Bus starts empty")
    func startsEmpty() async {
        let bus = ControlPlaneEventBus()
        
        let events = await bus.allEvents()
        #expect(events.isEmpty)
        #expect(await bus.eventCount == 0)
    }
    
    @Test("Record event")
    func recordEvent() async {
        let bus = ControlPlaneEventBus()
        
        let event = ProfileSelectionEvent(profileName: "Test")
        await bus.record(event)
        
        #expect(await bus.eventCount == 1)
    }
    
    @Test("Record multiple events")
    func recordMultiple() async {
        let bus = ControlPlaneEventBus()
        
        await bus.record(ProfileSelectionEvent(profileName: "A"))
        await bus.record(ProfileSelectionEvent(profileName: "B"))
        await bus.record(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        
        #expect(await bus.eventCount == 3)
    }
    
    @Test("Get events by type")
    func eventsByType() async {
        let bus = ControlPlaneEventBus()
        
        await bus.record(ProfileSelectionEvent(profileName: "A"))
        await bus.record(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        await bus.record(DeliveryEvent(deliveryType: .smb, units: 0.5))
        
        let deliveryEvents = await bus.events(ofType: DeliveryEvent.self)
        #expect(deliveryEvents.count == 2)
        
        let profileEvents = await bus.events(ofType: ProfileSelectionEvent.self)
        #expect(profileEvents.count == 1)
    }
    
    @Test("Submit and get proposals")
    func proposals() async {
        let bus = ControlPlaneEventBus()
        
        let proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        )
        
        await bus.submitProposal(proposal)
        
        let pending = await bus.pendingProposals()
        #expect(pending.count == 1)
        #expect(pending[0].id == proposal.id)
    }
    
    @Test("Approve proposal via bus")
    func approveViaBus() async {
        let bus = ControlPlaneEventBus()
        
        let proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        )
        
        await bus.submitProposal(proposal)
        let result = await bus.approveProposal(id: proposal.id, by: "reviewer")
        
        #expect(result == true)
        
        let pending = await bus.pendingProposals()
        #expect(pending.isEmpty)
        
        let all = await bus.allProposals()
        #expect(all[0].status == .approved)
    }
    
    @Test("Reject proposal via bus")
    func rejectViaBus() async {
        let bus = ControlPlaneEventBus()
        
        let proposal = AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .tempTarget,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        )
        
        await bus.submitProposal(proposal)
        let result = await bus.rejectProposal(id: proposal.id, by: "reviewer", note: "Denied")
        
        #expect(result == true)
        
        let all = await bus.allProposals()
        #expect(all[0].status == .rejected)
        #expect(all[0].reviewNote == "Denied")
    }
    
    @Test("Clear bus")
    func clear() async {
        let bus = ControlPlaneEventBus()
        
        await bus.record(ProfileSelectionEvent(profileName: "A"))
        await bus.submitProposal(AgentProposal(
            agentId: "test",
            agentName: "Test",
            proposalType: .override,
            description: "Test",
            rationale: "Test",
            expiresAt: Date().addingTimeInterval(300)
        ))
        
        await bus.clear()
        
        #expect(await bus.eventCount == 0)
        #expect(await bus.allProposals().isEmpty)
    }
    
    @Test("Export events as JSON")
    func exportJSON() async throws {
        let bus = ControlPlaneEventBus()
        
        await bus.record(ProfileSelectionEvent(profileName: "Default"))
        await bus.record(DeliveryEvent(deliveryType: .bolus, units: 2.0))
        
        let data = try await bus.exportEventsJSON()
        #expect(data.count > 0)
        
        // Verify valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        #expect(json is [String: Any])
    }
}

// MARK: - Proposed Override Tests

@Suite("ProposedOverride")
struct ProposedOverrideTests {
    
    @Test("Create override with all fields")
    func createFull() {
        let override = ProposedOverride(
            name: "Exercise",
            duration: 3600,
            targetRange: 140...160,
            insulinSensitivityMultiplier: 1.5,
            carbRatioMultiplier: 1.2,
            basalMultiplier: 0.5
        )
        
        #expect(override.name == "Exercise")
        #expect(override.duration == 3600)
        #expect(override.targetRange == 140...160)
        #expect(override.insulinSensitivityMultiplier == 1.5)
        #expect(override.basalMultiplier == 0.5)
    }
    
    @Test("Override is codable")
    func codable() throws {
        let override = ProposedOverride(
            name: "Test",
            duration: 1800,
            targetRange: 100...120
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(override)
        let decoded = try decoder.decode(ProposedOverride.self, from: data)
        
        #expect(decoded.name == override.name)
        #expect(decoded.duration == override.duration)
    }
}

// MARK: - Proposed Temp Target Tests

@Suite("ProposedTempTarget")
struct ProposedTempTargetTests {
    
    @Test("Create temp target")
    func create() {
        let target = ProposedTempTarget(
            targetRange: 80...90,
            duration: 1800,
            reason: "Pre-meal"
        )
        
        #expect(target.targetRange == 80...90)
        #expect(target.duration == 1800)
        #expect(target.reason == "Pre-meal")
    }
    
    @Test("Temp target is codable")
    func codable() throws {
        let target = ProposedTempTarget(
            targetRange: 110...130,
            duration: 3600,
            reason: "Sleep"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(target)
        let decoded = try decoder.decode(ProposedTempTarget.self, from: data)
        
        #expect(decoded.reason == target.reason)
    }
}
