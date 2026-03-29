// SPDX-License-Identifier: AGPL-3.0-or-later
// ControlPlaneEventStream.swift
// NightscoutKit
//
// Real-time control plane event subscription via Server-Sent Events
// Trace: CONTROL-005, agent-control-plane-integration.md

import Foundation

// MARK: - Event Stream Configuration

/// Configuration for control plane event stream
public struct EventStreamConfig: Sendable {
    /// Control plane base URL
    public let baseURL: URL
    
    /// Authentication token
    public let authToken: String
    
    /// Event types to subscribe to (nil = all)
    public let eventFilters: Set<ControlPlaneEventType>?
    
    /// Reconnection policy
    public let reconnectPolicy: ReconnectPolicy
    
    /// Heartbeat interval for connection health
    public let heartbeatInterval: TimeInterval
    
    public init(
        baseURL: URL,
        authToken: String,
        eventFilters: Set<ControlPlaneEventType>? = nil,
        reconnectPolicy: ReconnectPolicy = .exponentialBackoff,
        heartbeatInterval: TimeInterval = 30.0
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.eventFilters = eventFilters
        self.reconnectPolicy = reconnectPolicy
        self.heartbeatInterval = heartbeatInterval
    }
    
    /// Default configuration for testing
    public static var mock: EventStreamConfig {
        EventStreamConfig(
            baseURL: URL(string: "https://mock.nightscout.local")!,
            authToken: "mock-token",
            eventFilters: nil,
            reconnectPolicy: .noReconnect,
            heartbeatInterval: 30.0
        )
    }
}

/// Reconnection policy for event stream
public enum ReconnectPolicy: Sendable, Equatable {
    /// No automatic reconnection
    case noReconnect
    
    /// Fixed interval reconnection
    case fixedInterval(TimeInterval)
    
    /// Exponential backoff (default: 1s initial, 60s max, 2x factor)
    case exponentialBackoff
    
    /// Custom exponential backoff
    case customBackoff(initial: TimeInterval, maximum: TimeInterval, factor: Double)
    
    /// Calculate delay for attempt number (0-indexed)
    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        switch self {
        case .noReconnect:
            return nil
        case .fixedInterval(let interval):
            return interval
        case .exponentialBackoff:
            let initial = 1.0
            let maximum = 60.0
            let factor = 2.0
            let delay = min(initial * pow(factor, Double(attempt)), maximum)
            return delay
        case .customBackoff(let initial, let maximum, let factor):
            let delay = min(initial * pow(factor, Double(attempt)), maximum)
            return delay
        }
    }
}

/// Event types for filtering subscriptions
public enum ControlPlaneEventType: String, Sendable, Codable, CaseIterable {
    case profileSelection = "profileSelection"
    case overrideInstance = "overrideInstance"
    case overrideCancel = "overrideCancel"
    case delivery = "delivery"
    case agentProposal = "agentProposal"
    case tempTarget = "tempTarget"
    case carbEntry = "carbEntry"
    case bolusEntry = "bolusEntry"
    case annotation = "annotation"
    case heartbeat = "heartbeat"
}

// MARK: - Event Stream State

/// State of the event stream connection
public enum EventStreamState: Sendable, Equatable {
    /// Not connected
    case disconnected
    
    /// Currently connecting
    case connecting
    
    /// Connected and receiving events
    case connected(since: Date)
    
    /// Reconnecting after disconnection
    case reconnecting(attempt: Int, nextAttempt: Date)
    
    /// Connection failed permanently
    case failed(EventStreamError)
    
    /// Gracefully closed
    case closed
    
    public static func == (lhs: EventStreamState, rhs: EventStreamState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected(let a), .connected(let b)): return a == b
        case (.reconnecting(let a1, let a2), .reconnecting(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.failed(let a), .failed(let b)): return a.localizedDescription == b.localizedDescription
        case (.closed, .closed): return true
        default: return false
        }
    }
}

/// Errors that can occur during event stream operation
public enum EventStreamError: Error, Sendable {
    case invalidURL
    case authenticationFailed
    case connectionTimeout
    case networkError(String)
    case serverError(statusCode: Int)
    case parseError(String)
    case maxReconnectAttemptsExceeded
}

// MARK: - Parsed Event

/// A parsed control plane event from the stream
public enum ParsedControlPlaneEvent: Sendable {
    case profileSelection(ProfileSelectionEvent)
    case overrideInstance(OverrideInstanceEvent)
    case overrideCancel(OverrideCancelEvent)
    case delivery(DeliveryEvent)
    case heartbeat(HeartbeatEvent)
    case unknown(type: String, data: Data)
}

/// Heartbeat event for connection health
public struct HeartbeatEvent: Sendable, Codable {
    public let timestamp: Date
    public let serverTime: Date
    public let sequence: Int
    
    public init(timestamp: Date = Date(), serverTime: Date = Date(), sequence: Int = 0) {
        self.timestamp = timestamp
        self.serverTime = serverTime
        self.sequence = sequence
    }
}

// MARK: - Event Parser

/// Parser for Server-Sent Events
public struct SSEParser: Sendable {
    public init() {}
    
    /// Parse a single SSE line into event components
    public func parseLine(_ line: String) -> SSEComponent? {
        guard !line.isEmpty else { return .empty }
        
        if line.hasPrefix(":") {
            // Comment line
            return .comment(String(line.dropFirst()))
        }
        
        if let colonIndex = line.firstIndex(of: ":") {
            let field = String(line[..<colonIndex])
            var value = String(line[line.index(after: colonIndex)...])
            if value.hasPrefix(" ") {
                value = String(value.dropFirst())
            }
            return .field(name: field, value: value)
        }
        
        // Field with no value
        return .field(name: line, value: "")
    }
    
    /// Parse raw event data into a control plane event
    public func parseEvent(type: String, data: String) -> ParsedControlPlaneEvent? {
        guard let jsonData = data.data(using: .utf8) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            switch type {
            case ControlPlaneEventType.profileSelection.rawValue:
                let event = try decoder.decode(ProfileSelectionEvent.self, from: jsonData)
                return .profileSelection(event)
                
            case ControlPlaneEventType.overrideInstance.rawValue:
                let event = try decoder.decode(OverrideInstanceEvent.self, from: jsonData)
                return .overrideInstance(event)
                
            case ControlPlaneEventType.overrideCancel.rawValue:
                let event = try decoder.decode(OverrideCancelEvent.self, from: jsonData)
                return .overrideCancel(event)
                
            case ControlPlaneEventType.delivery.rawValue:
                let event = try decoder.decode(DeliveryEvent.self, from: jsonData)
                return .delivery(event)
                
            case ControlPlaneEventType.heartbeat.rawValue:
                let event = try decoder.decode(HeartbeatEvent.self, from: jsonData)
                return .heartbeat(event)
                
            default:
                return .unknown(type: type, data: jsonData)
            }
        } catch {
            return .unknown(type: type, data: jsonData)
        }
    }
}

/// Component of a Server-Sent Event message
public enum SSEComponent: Sendable, Equatable {
    case empty
    case comment(String)
    case field(name: String, value: String)
}

// MARK: - Event Stream Delegate

/// Delegate for receiving event stream notifications
public protocol EventStreamDelegate: AnyObject, Sendable {
    /// Called when an event is received
    func eventStream(_ stream: ControlPlaneEventStream, didReceive event: ParsedControlPlaneEvent)
    
    /// Called when connection state changes
    func eventStream(_ stream: ControlPlaneEventStream, didChangeState state: EventStreamState)
    
    /// Called when an error occurs
    func eventStream(_ stream: ControlPlaneEventStream, didEncounter error: EventStreamError)
}

// MARK: - Control Plane Event Stream

/// Actor for managing real-time control plane event subscriptions
public actor ControlPlaneEventStream {
    /// Current configuration
    public let config: EventStreamConfig
    
    /// Current connection state
    public private(set) var state: EventStreamState = .disconnected
    
    /// Delegate for event notifications
    public weak var delegate: (any EventStreamDelegate)?
    
    /// Event buffer for offline/reconnection
    private var eventBuffer: [ParsedControlPlaneEvent] = []
    private let maxBufferSize: Int = 1000
    
    /// Reconnection state
    private var reconnectAttempt: Int = 0
    private var lastEventId: String?
    
    /// Parser for SSE messages
    private let parser = SSEParser()
    
    /// Event handlers (alternative to delegate)
    private var eventHandlers: [(ParsedControlPlaneEvent) async -> Void] = []
    private var stateHandlers: [(EventStreamState) async -> Void] = []
    
    /// Last heartbeat received
    public private(set) var lastHeartbeat: Date?
    
    /// Event statistics
    public private(set) var statistics: EventStreamStatistics = EventStreamStatistics()
    
    public init(config: EventStreamConfig) {
        self.config = config
    }
    
    // MARK: - Connection Management
    
    /// Connect to the event stream
    public func connect() async throws {
        switch state {
        case .disconnected, .failed:
            break
        default:
            return
        }
        
        await transitionTo(.connecting)
        
        // In production, this would open actual SSE connection
        // For now, simulate successful connection
        reconnectAttempt = 0
        await transitionTo(.connected(since: Date()))
    }
    
    /// Disconnect from the event stream
    public func disconnect() async {
        await transitionTo(.closed)
        reconnectAttempt = 0
    }
    
    /// Force reconnection
    public func reconnect() async throws {
        await transitionTo(.disconnected)
        try await connect()
    }
    
    // MARK: - Event Handling
    
    /// Add an event handler
    public func onEvent(_ handler: @escaping (ParsedControlPlaneEvent) async -> Void) {
        eventHandlers.append(handler)
    }
    
    /// Add a state change handler
    public func onStateChange(_ handler: @escaping (EventStreamState) async -> Void) {
        stateHandlers.append(handler)
    }
    
    /// Process incoming raw data (for testing and actual SSE processing)
    public func processData(_ data: Data) async {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Parse SSE messages
        let lines = string.components(separatedBy: "\n")
        var eventType: String = "message"
        var eventData: String = ""
        
        for line in lines {
            guard let component = parser.parseLine(line) else { continue }
            
            switch component {
            case .empty:
                // Empty line = dispatch event
                if !eventData.isEmpty {
                    if let event = parser.parseEvent(type: eventType, data: eventData) {
                        await handleEvent(event)
                    }
                    eventType = "message"
                    eventData = ""
                }
                
            case .comment:
                // Ignore comments
                break
                
            case .field(let name, let value):
                switch name {
                case "event":
                    eventType = value
                case "data":
                    if eventData.isEmpty {
                        eventData = value
                    } else {
                        eventData += "\n" + value
                    }
                case "id":
                    lastEventId = value
                default:
                    break
                }
            }
        }
    }
    
    /// Handle a parsed event
    private func handleEvent(_ event: ParsedControlPlaneEvent) async {
        // Update statistics
        statistics = statistics.withEvent()
        
        // Handle heartbeat specially
        if case .heartbeat = event {
            lastHeartbeat = Date()
        }
        
        // Check filter
        if let filters = config.eventFilters {
            let eventType = eventTypeFor(event)
            guard filters.contains(eventType) else { return }
        }
        
        // Buffer event
        eventBuffer.append(event)
        if eventBuffer.count > maxBufferSize {
            eventBuffer.removeFirst()
        }
        
        // Notify delegate
        if let delegate = delegate {
            delegate.eventStream(self, didReceive: event)
        }
        
        // Notify handlers
        for handler in eventHandlers {
            await handler(event)
        }
    }
    
    /// Get event type for a parsed event
    private func eventTypeFor(_ event: ParsedControlPlaneEvent) -> ControlPlaneEventType {
        switch event {
        case .profileSelection: return .profileSelection
        case .overrideInstance: return .overrideInstance
        case .overrideCancel: return .overrideCancel
        case .delivery: return .delivery
        case .heartbeat: return .heartbeat
        case .unknown: return .annotation // fallback
        }
    }
    
    // MARK: - State Transitions
    
    private func transitionTo(_ newState: EventStreamState) async {
        let oldState = state
        state = newState
        
        // Update statistics for connections
        if case .connected = newState {
            statistics = statistics.withConnection()
        }
        
        // Notify delegate
        if let delegate = delegate {
            delegate.eventStream(self, didChangeState: newState)
        }
        
        // Notify handlers
        for handler in stateHandlers {
            await handler(newState)
        }
        
        // Handle reconnection
        if case .failed = oldState,
           case .disconnected = newState {
            // Reset reconnect counter on explicit disconnect
            reconnectAttempt = 0
        }
    }
    
    /// Simulate connection loss (for testing)
    public func simulateDisconnect() async {
        statistics = statistics.withDisconnection()
        
        guard let delay = config.reconnectPolicy.delay(forAttempt: reconnectAttempt) else {
            await transitionTo(.failed(.networkError("Connection lost")))
            return
        }
        
        let nextAttempt = Date().addingTimeInterval(delay)
        await transitionTo(.reconnecting(attempt: reconnectAttempt, nextAttempt: nextAttempt))
        reconnectAttempt += 1
    }
    
    /// Simulate successful reconnection (for testing)
    public func simulateReconnect() async {
        reconnectAttempt = 0
        await transitionTo(.connected(since: Date()))
    }
    
    // MARK: - Buffer Access
    
    /// Get buffered events since a given date
    public func bufferedEvents(since date: Date) -> [ParsedControlPlaneEvent] {
        // In practice, would filter by event timestamp
        return eventBuffer
    }
    
    /// Clear event buffer
    public func clearBuffer() {
        eventBuffer.removeAll()
    }
    
    /// Current buffer count
    public var bufferCount: Int {
        eventBuffer.count
    }
}

// MARK: - Statistics

/// Statistics for event stream monitoring
public struct EventStreamStatistics: Sendable {
    public let totalEvents: Int
    public let connectionCount: Int
    public let disconnectionCount: Int
    public let lastConnectionTime: Date?
    public let lastDisconnectionTime: Date?
    
    public init(
        totalEvents: Int = 0,
        connectionCount: Int = 0,
        disconnectionCount: Int = 0,
        lastConnectionTime: Date? = nil,
        lastDisconnectionTime: Date? = nil
    ) {
        self.totalEvents = totalEvents
        self.connectionCount = connectionCount
        self.disconnectionCount = disconnectionCount
        self.lastConnectionTime = lastConnectionTime
        self.lastDisconnectionTime = lastDisconnectionTime
    }
    
    func withEvent() -> EventStreamStatistics {
        EventStreamStatistics(
            totalEvents: totalEvents + 1,
            connectionCount: connectionCount,
            disconnectionCount: disconnectionCount,
            lastConnectionTime: lastConnectionTime,
            lastDisconnectionTime: lastDisconnectionTime
        )
    }
    
    func withConnection() -> EventStreamStatistics {
        EventStreamStatistics(
            totalEvents: totalEvents,
            connectionCount: connectionCount + 1,
            disconnectionCount: disconnectionCount,
            lastConnectionTime: Date(),
            lastDisconnectionTime: lastDisconnectionTime
        )
    }
    
    func withDisconnection() -> EventStreamStatistics {
        EventStreamStatistics(
            totalEvents: totalEvents,
            connectionCount: connectionCount,
            disconnectionCount: disconnectionCount + 1,
            lastConnectionTime: lastConnectionTime,
            lastDisconnectionTime: Date()
        )
    }
}

// MARK: - Event Stream Logic

/// Logic for event stream operations
public enum EventStreamLogic {
    /// Check if connection is healthy based on heartbeat
    public static func isConnectionHealthy(
        lastHeartbeat: Date?,
        expectedInterval: TimeInterval
    ) -> Bool {
        guard let lastHeartbeat = lastHeartbeat else { return false }
        let elapsed = Date().timeIntervalSince(lastHeartbeat)
        // Allow 2x interval before considering unhealthy
        return elapsed < (expectedInterval * 2)
    }
    
    /// Calculate reconnection delay
    public static func reconnectDelay(
        policy: ReconnectPolicy,
        attempt: Int
    ) -> TimeInterval? {
        policy.delay(forAttempt: attempt)
    }
    
    /// Check if event passes filter
    public static func eventPassesFilter(
        event: ParsedControlPlaneEvent,
        filters: Set<ControlPlaneEventType>?
    ) -> Bool {
        guard let filters = filters else { return true }
        
        let eventType: ControlPlaneEventType
        switch event {
        case .profileSelection: eventType = .profileSelection
        case .overrideInstance: eventType = .overrideInstance
        case .overrideCancel: eventType = .overrideCancel
        case .delivery: eventType = .delivery
        case .heartbeat: eventType = .heartbeat
        case .unknown: return false
        }
        
        return filters.contains(eventType)
    }
    
    /// Build SSE endpoint URL with filters
    public static func buildEndpointURL(
        baseURL: URL,
        filters: Set<ControlPlaneEventType>?,
        lastEventId: String?
    ) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        if let filters = filters {
            let filterString = filters.map { $0.rawValue }.sorted().joined(separator: ",")
            queryItems.append(URLQueryItem(name: "types", value: filterString))
        }
        
        if let lastEventId = lastEventId {
            queryItems.append(URLQueryItem(name: "last_event_id", value: lastEventId))
        }
        
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        return components.url!
    }
}
