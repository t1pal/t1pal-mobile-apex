// SPDX-License-Identifier: AGPL-3.0-or-later
// ControlPlane.swift
// NightscoutKit
//
// Nightscout control plane event types for agent integration
// Trace: RESEARCH-001, agent-control-plane-integration.md

import Foundation

// MARK: - Control Plane Event Protocol

/// Protocol for all control plane events
/// Events are append-only and form an auditable log
public protocol ControlPlaneEvent: Sendable, Codable, Identifiable {
    /// Unique event identifier
    var id: UUID { get }
    
    /// Timestamp when event occurred
    var timestamp: Date { get }
    
    /// Source of the event (app, agent, user)
    var source: EventSource { get }
    
    /// Event type name for serialization
    static var eventType: String { get }
}

/// Source of a control plane event
public enum EventSource: String, Sendable, Codable {
    case user = "user"              // Direct user action
    case app = "app"                // App-initiated (e.g., algorithm)
    case agent = "agent"            // External agent proposal
    case caregiver = "caregiver"    // Remote caregiver action
    case system = "system"          // System-generated
}

// MARK: - Profile Events

/// Profile selection event - user or system selects a profile
public struct ProfileSelectionEvent: ControlPlaneEvent {
    public static let eventType = "profileSelection"
    
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let profileName: String
    public let previousProfileName: String?
    public let reason: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: EventSource = .user,
        profileName: String,
        previousProfileName: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.profileName = profileName
        self.previousProfileName = previousProfileName
        self.reason = reason
    }
}

// MARK: - Override Events

/// Override activation event
public struct OverrideInstanceEvent: ControlPlaneEvent {
    public static let eventType = "overrideInstance"
    
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let overrideName: String
    public let duration: TimeInterval?
    public let targetRange: ClosedRange<Double>?
    public let insulinSensitivityMultiplier: Double?
    public let carbRatioMultiplier: Double?
    public let basalMultiplier: Double?
    public let reason: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: EventSource = .user,
        overrideName: String,
        duration: TimeInterval? = nil,
        targetRange: ClosedRange<Double>? = nil,
        insulinSensitivityMultiplier: Double? = nil,
        carbRatioMultiplier: Double? = nil,
        basalMultiplier: Double? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.overrideName = overrideName
        self.duration = duration
        self.targetRange = targetRange
        self.insulinSensitivityMultiplier = insulinSensitivityMultiplier
        self.carbRatioMultiplier = carbRatioMultiplier
        self.basalMultiplier = basalMultiplier
        self.reason = reason
    }
}

/// Override cancellation event
public struct OverrideCancelEvent: ControlPlaneEvent {
    public static let eventType = "overrideCancel"
    
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let overrideInstanceId: UUID
    public let reason: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: EventSource = .user,
        overrideInstanceId: UUID,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.overrideInstanceId = overrideInstanceId
        self.reason = reason
    }
}

// MARK: - Delivery Events

/// Insulin delivery event (basal, bolus, temp basal)
public struct DeliveryEvent: ControlPlaneEvent {
    public static let eventType = "delivery"
    
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let deliveryType: DeliveryType
    public let units: Double
    public let duration: TimeInterval?
    public let rate: Double?
    public let reason: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: EventSource = .app,
        deliveryType: DeliveryType,
        units: Double,
        duration: TimeInterval? = nil,
        rate: Double? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.deliveryType = deliveryType
        self.units = units
        self.duration = duration
        self.rate = rate
        self.reason = reason
    }
}

/// Type of insulin delivery
public enum DeliveryType: String, Sendable, Codable {
    case bolus = "bolus"
    case correctionBolus = "correctionBolus"
    case smb = "smb"                    // Super Micro Bolus
    case tempBasal = "tempBasal"
    case scheduledBasal = "scheduledBasal"
    case suspend = "suspend"
    case resume = "resume"
}

// MARK: - Agent Proposals

/// Proposal status
public enum ProposalStatus: String, Sendable, Codable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case expired = "expired"
    case executed = "executed"
}

/// Agent proposal for an action (override, temp target, etc.)
public struct AgentProposal: Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let agentId: String
    public let agentName: String
    public let proposalType: ProposalType
    public let description: String
    public let rationale: String
    public let expiresAt: Date
    public var status: ProposalStatus
    public var reviewedBy: String?
    public var reviewedAt: Date?
    public var reviewNote: String?
    
    /// Proposed override details (if proposalType is .override)
    public let proposedOverride: ProposedOverride?
    
    /// Proposed temp target details (if proposalType is .tempTarget)
    public let proposedTempTarget: ProposedTempTarget?
    
    /// Proposed carbs grams (if proposalType is .carbs)
    public let proposedCarbs: Double?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentId: String,
        agentName: String,
        proposalType: ProposalType,
        description: String,
        rationale: String,
        expiresAt: Date,
        status: ProposalStatus = .pending,
        proposedOverride: ProposedOverride? = nil,
        proposedTempTarget: ProposedTempTarget? = nil,
        proposedCarbs: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentId = agentId
        self.agentName = agentName
        self.proposalType = proposalType
        self.description = description
        self.rationale = rationale
        self.expiresAt = expiresAt
        self.status = status
        self.proposedOverride = proposedOverride
        self.proposedTempTarget = proposedTempTarget
        self.proposedCarbs = proposedCarbs
    }
    
    /// Check if proposal has expired
    public var isExpired: Bool {
        Date() > expiresAt
    }
    
    /// Check if proposal can be acted upon
    public var isActionable: Bool {
        status == .pending && !isExpired
    }
    
    /// Approve the proposal
    public mutating func approve(by reviewer: String, note: String? = nil) {
        status = .approved
        reviewedBy = reviewer
        reviewedAt = Date()
        reviewNote = note
    }
    
    /// Reject the proposal
    public mutating func reject(by reviewer: String, note: String? = nil) {
        status = .rejected
        reviewedBy = reviewer
        reviewedAt = Date()
        reviewNote = note
    }
}

/// Type of agent proposal
public enum ProposalType: String, Sendable, Codable, CaseIterable {
    case override = "override"
    case tempTarget = "tempTarget"
    case suspendDelivery = "suspendDelivery"
    case resumeDelivery = "resumeDelivery"
    case profile = "profile"
    case carbs = "carbs"
    case annotation = "annotation"
}

/// Proposed override details
public struct ProposedOverride: Sendable, Codable {
    public let name: String
    public let duration: TimeInterval
    public let targetRange: ClosedRange<Double>?
    public let insulinSensitivityMultiplier: Double?
    public let carbRatioMultiplier: Double?
    public let basalMultiplier: Double?
    
    public init(
        name: String,
        duration: TimeInterval,
        targetRange: ClosedRange<Double>? = nil,
        insulinSensitivityMultiplier: Double? = nil,
        carbRatioMultiplier: Double? = nil,
        basalMultiplier: Double? = nil
    ) {
        self.name = name
        self.duration = duration
        self.targetRange = targetRange
        self.insulinSensitivityMultiplier = insulinSensitivityMultiplier
        self.carbRatioMultiplier = carbRatioMultiplier
        self.basalMultiplier = basalMultiplier
    }
}

/// Proposed temporary target
public struct ProposedTempTarget: Sendable, Codable {
    public let targetRange: ClosedRange<Double>
    public let duration: TimeInterval
    public let reason: String
    
    public init(targetRange: ClosedRange<Double>, duration: TimeInterval, reason: String) {
        self.targetRange = targetRange
        self.duration = duration
        self.reason = reason
    }
}

// MARK: - Control Plane Event Bus

/// Actor for managing control plane events
/// Provides append-only event log with subscription support
public actor ControlPlaneEventBus {
    
    /// All recorded events
    private var events: [any ControlPlaneEvent] = []
    
    /// Pending agent proposals
    private var proposals: [AgentProposal] = []
    
    /// Event handlers
    private var handlers: [UUID: @Sendable (any ControlPlaneEvent) async -> Void] = [:]
    
    public init() {}
    
    // MARK: - Event Recording
    
    /// Record an event to the log
    public func record<E: ControlPlaneEvent>(_ event: E) async {
        events.append(event)
        
        // Notify handlers
        for handler in handlers.values {
            await handler(event)
        }
    }
    
    /// Get all events
    public func allEvents() -> [any ControlPlaneEvent] {
        events
    }
    
    /// Get events since a timestamp
    public func events(since timestamp: Date) -> [any ControlPlaneEvent] {
        events.filter { $0.timestamp >= timestamp }
    }
    
    /// Get events of a specific type
    public func events<E: ControlPlaneEvent>(ofType type: E.Type) -> [E] {
        events.compactMap { $0 as? E }
    }
    
    /// Count of events
    public var eventCount: Int {
        events.count
    }
    
    // MARK: - Proposals
    
    /// Submit an agent proposal
    public func submitProposal(_ proposal: AgentProposal) {
        proposals.append(proposal)
    }
    
    /// Get pending proposals
    public func pendingProposals() -> [AgentProposal] {
        proposals.filter { $0.status == .pending && !$0.isExpired }
    }
    
    /// Get all proposals
    public func allProposals() -> [AgentProposal] {
        proposals
    }
    
    /// Approve a proposal
    public func approveProposal(id: UUID, by reviewer: String, note: String? = nil) -> Bool {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else {
            return false
        }
        
        proposals[index].approve(by: reviewer, note: note)
        return true
    }
    
    /// Reject a proposal
    public func rejectProposal(id: UUID, by reviewer: String, note: String? = nil) -> Bool {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else {
            return false
        }
        
        proposals[index].reject(by: reviewer, note: note)
        return true
    }
    
    /// Expire old pending proposals
    public func expireOldProposals() {
        for i in proposals.indices {
            if proposals[i].status == .pending && proposals[i].isExpired {
                proposals[i].status = .expired
            }
        }
    }
    
    // MARK: - Subscriptions
    
    /// Subscribe to events
    /// Returns subscription ID for unsubscribing
    public func subscribe(_ handler: @escaping @Sendable (any ControlPlaneEvent) async -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }
    
    /// Unsubscribe from events
    public func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }
    
    // MARK: - Export
    
    /// Export events as JSON
    public func exportEventsJSON() throws -> Data {
        // We need to wrap events for encoding
        let wrapper = EventsWrapper(events: events.map { AnyControlPlaneEvent($0) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wrapper)
    }
    
    /// Clear all events (for testing)
    public func clear() {
        events.removeAll()
        proposals.removeAll()
    }
}

// MARK: - Event Wrapper for Encoding

/// Type-erased wrapper for encoding events
private struct AnyControlPlaneEvent: Encodable {
    let id: UUID
    let timestamp: Date
    let source: EventSource
    let eventType: String
    
    init(_ event: any ControlPlaneEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.source = event.source
        self.eventType = type(of: event).eventType
    }
}

private struct EventsWrapper: Encodable {
    let events: [AnyControlPlaneEvent]
}
