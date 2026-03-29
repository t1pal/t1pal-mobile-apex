// SPDX-License-Identifier: MIT
// ControlPlaneEventStreamTests.swift
// NightscoutKitTests
//
// Tests for control plane event stream subscription
// Trace: CONTROL-005

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Event Stream Config Tests

@Suite("Event Stream Config")
struct EventStreamConfigTests {
    @Test("Default config has expected values")
    func defaultConfig() {
        let config = EventStreamConfig.mock
        
        #expect(config.baseURL.absoluteString == "https://mock.nightscout.local")
        #expect(config.authToken == "mock-token")
        #expect(config.eventFilters == nil)
        #expect(config.reconnectPolicy == .noReconnect)
        #expect(config.heartbeatInterval == 30.0)
    }
    
    @Test("Config with filters")
    func configWithFilters() {
        let config = EventStreamConfig(
            baseURL: URL(string: "https://test.nightscout.local")!,
            authToken: "test-token",
            eventFilters: [.overrideInstance, .overrideCancel],
            reconnectPolicy: .exponentialBackoff,
            heartbeatInterval: 60.0
        )
        
        #expect(config.eventFilters?.count == 2)
        #expect(config.eventFilters?.contains(.overrideInstance) == true)
        #expect(config.heartbeatInterval == 60.0)
    }
}

// MARK: - Reconnect Policy Tests

@Suite("Reconnect Policy")
struct ReconnectPolicyTests {
    @Test("No reconnect returns nil")
    func noReconnect() {
        let policy = ReconnectPolicy.noReconnect
        #expect(policy.delay(forAttempt: 0) == nil)
        #expect(policy.delay(forAttempt: 5) == nil)
    }
    
    @Test("Fixed interval returns constant delay")
    func fixedInterval() {
        let policy = ReconnectPolicy.fixedInterval(5.0)
        
        #expect(policy.delay(forAttempt: 0) == 5.0)
        #expect(policy.delay(forAttempt: 1) == 5.0)
        #expect(policy.delay(forAttempt: 10) == 5.0)
    }
    
    @Test("Exponential backoff increases")
    func exponentialBackoff() {
        let policy = ReconnectPolicy.exponentialBackoff
        
        let delay0 = policy.delay(forAttempt: 0)!
        let delay1 = policy.delay(forAttempt: 1)!
        let delay2 = policy.delay(forAttempt: 2)!
        
        #expect(delay0 == 1.0)
        #expect(delay1 == 2.0)
        #expect(delay2 == 4.0)
    }
    
    @Test("Exponential backoff has maximum")
    func exponentialBackoffMax() {
        let policy = ReconnectPolicy.exponentialBackoff
        
        // After many attempts, should cap at 60
        let delay10 = policy.delay(forAttempt: 10)!
        #expect(delay10 == 60.0)
    }
    
    @Test("Custom backoff uses provided values")
    func customBackoff() {
        let policy = ReconnectPolicy.customBackoff(initial: 2.0, maximum: 30.0, factor: 3.0)
        
        let delay0 = policy.delay(forAttempt: 0)!
        let delay1 = policy.delay(forAttempt: 1)!
        let delay2 = policy.delay(forAttempt: 2)!
        
        #expect(delay0 == 2.0)
        #expect(delay1 == 6.0)
        #expect(delay2 == 18.0)
        
        // Check max
        let delay10 = policy.delay(forAttempt: 10)!
        #expect(delay10 == 30.0)
    }
}

// MARK: - Event Stream State Tests

@Suite("Event Stream State")
struct EventStreamStateTests {
    @Test("States are equatable")
    func stateEquality() {
        let now = Date()
        
        #expect(EventStreamState.disconnected == EventStreamState.disconnected)
        #expect(EventStreamState.connecting == EventStreamState.connecting)
        #expect(EventStreamState.connected(since: now) == EventStreamState.connected(since: now))
        #expect(EventStreamState.closed == EventStreamState.closed)
        
        #expect(EventStreamState.reconnecting(attempt: 2, nextAttempt: now) == 
               EventStreamState.reconnecting(attempt: 2, nextAttempt: now))
    }
    
    @Test("Different states are not equal")
    func stateInequality() {
        #expect(EventStreamState.disconnected != EventStreamState.connecting)
        #expect(EventStreamState.connected(since: Date()) != EventStreamState.closed)
    }
}

// MARK: - SSE Parser Tests

@Suite("SSE Parser")
struct SSEParserTests {
    let parser = SSEParser()
    
    @Test("Parse empty line")
    func parseEmpty() {
        let result = parser.parseLine("")
        #expect(result == .empty)
    }
    
    @Test("Parse comment line")
    func parseComment() {
        let result = parser.parseLine(": this is a comment")
        #expect(result == .comment(" this is a comment"))
    }
    
    @Test("Parse field with value")
    func parseField() {
        let result = parser.parseLine("event: overrideInstance")
        #expect(result == .field(name: "event", value: "overrideInstance"))
    }
    
    @Test("Parse field with space after colon")
    func parseFieldWithSpace() {
        let result = parser.parseLine("data: {\"id\":\"123\"}")
        #expect(result == .field(name: "data", value: "{\"id\":\"123\"}"))
    }
    
    @Test("Parse field without value")
    func parseFieldNoValue() {
        let result = parser.parseLine("retry")
        #expect(result == .field(name: "retry", value: ""))
    }
    
    @Test("Parse override instance event")
    func parseOverrideInstance() {
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440000","timestamp":"2024-01-15T10:30:00Z","source":"user","overrideName":"Exercise"}
        """
        
        let result = parser.parseEvent(type: "overrideInstance", data: json)
        
        if case .overrideInstance(let event) = result {
            #expect(event.overrideName == "Exercise")
            #expect(event.source == .user)
        } else {
            #expect(Bool(false), "Expected override instance event")
        }
    }
    
    @Test("Parse heartbeat event")
    func parseHeartbeat() {
        let json = """
        {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":42}
        """
        
        let result = parser.parseEvent(type: "heartbeat", data: json)
        
        if case .heartbeat(let event) = result {
            #expect(event.sequence == 42)
        } else {
            #expect(Bool(false), "Expected heartbeat event")
        }
    }
    
    @Test("Parse unknown event type")
    func parseUnknown() {
        let json = """
        {"custom":"data"}
        """
        
        let result = parser.parseEvent(type: "customEvent", data: json)
        
        if case .unknown(let type, _) = result {
            #expect(type == "customEvent")
        } else {
            #expect(Bool(false), "Expected unknown event")
        }
    }
}

// MARK: - Control Plane Event Stream Tests

@Suite("Control Plane Event Stream")
struct ControlPlaneEventStreamTests {
    @Test("Initial state is disconnected")
    func initialState() async {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        let state = await stream.state
        #expect(state == .disconnected)
    }
    
    @Test("Connect changes state to connected")
    func connect() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        let state = await stream.state
        if case .connected = state {
            // Expected
        } else {
            #expect(Bool(false), "Expected connected state")
        }
    }
    
    @Test("Disconnect changes state to closed")
    func disconnect() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        await stream.disconnect()
        
        let state = await stream.state
        #expect(state == .closed)
    }
    
    @Test("Process data adds to buffer")
    func processData() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        let sseData = """
        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":1}

        """.data(using: .utf8)!
        
        await stream.processData(sseData)
        
        let bufferCount = await stream.bufferCount
        #expect(bufferCount == 1)
    }
    
    @Test("Events are buffered")
    func eventBuffering() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        let sseData = """
        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":1}

        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:01Z","serverTime":"2024-01-15T10:30:01Z","sequence":2}

        """.data(using: .utf8)!
        
        await stream.processData(sseData)
        
        let bufferCount = await stream.bufferCount
        #expect(bufferCount == 2)
    }
    
    @Test("Clear buffer removes events")
    func clearBuffer() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        let sseData = """
        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":1}

        """.data(using: .utf8)!
        
        await stream.processData(sseData)
        
        var bufferCount = await stream.bufferCount
        #expect(bufferCount == 1)
        
        await stream.clearBuffer()
        
        bufferCount = await stream.bufferCount
        #expect(bufferCount == 0)
    }
    
    @Test("Heartbeat updates last heartbeat time")
    func heartbeatUpdatesTime() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        var lastHeartbeat = await stream.lastHeartbeat
        #expect(lastHeartbeat == nil)
        
        let sseData = """
        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":1}

        """.data(using: .utf8)!
        
        await stream.processData(sseData)
        
        lastHeartbeat = await stream.lastHeartbeat
        #expect(lastHeartbeat != nil)
    }
    
    @Test("Statistics track events")
    func statisticsTrackEvents() async throws {
        let config = EventStreamConfig.mock
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        
        let sseData = """
        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:00Z","serverTime":"2024-01-15T10:30:00Z","sequence":1}

        event: heartbeat
        data: {"timestamp":"2024-01-15T10:30:01Z","serverTime":"2024-01-15T10:30:01Z","sequence":2}

        """.data(using: .utf8)!
        
        await stream.processData(sseData)
        
        let stats = await stream.statistics
        #expect(stats.totalEvents == 2)
        #expect(stats.connectionCount == 1)
    }
    
    @Test("Simulate disconnect triggers reconnecting state")
    func simulateDisconnect() async throws {
        let config = EventStreamConfig(
            baseURL: URL(string: "https://test.local")!,
            authToken: "token",
            eventFilters: nil,
            reconnectPolicy: .exponentialBackoff,
            heartbeatInterval: 30.0
        )
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        await stream.simulateDisconnect()
        
        let state = await stream.state
        if case .reconnecting(let attempt, _) = state {
            #expect(attempt == 0)
        } else {
            #expect(Bool(false), "Expected reconnecting state")
        }
    }
    
    @Test("Simulate reconnect returns to connected")
    func simulateReconnect() async throws {
        let config = EventStreamConfig(
            baseURL: URL(string: "https://test.local")!,
            authToken: "token",
            eventFilters: nil,
            reconnectPolicy: .exponentialBackoff,
            heartbeatInterval: 30.0
        )
        let stream = ControlPlaneEventStream(config: config)
        
        try await stream.connect()
        await stream.simulateDisconnect()
        await stream.simulateReconnect()
        
        let state = await stream.state
        if case .connected = state {
            // Expected
        } else {
            #expect(Bool(false), "Expected connected state")
        }
    }
}

// MARK: - Event Stream Logic Tests

@Suite("Event Stream Logic")
struct EventStreamLogicTests {
    @Test("Connection healthy within interval")
    func connectionHealthyWithin() {
        let lastHeartbeat = Date()
        let result = EventStreamLogic.isConnectionHealthy(
            lastHeartbeat: lastHeartbeat,
            expectedInterval: 30.0
        )
        #expect(result == true)
    }
    
    @Test("Connection unhealthy with nil heartbeat")
    func connectionUnhealthyNil() {
        let result = EventStreamLogic.isConnectionHealthy(
            lastHeartbeat: nil,
            expectedInterval: 30.0
        )
        #expect(result == false)
    }
    
    @Test("Connection unhealthy after timeout")
    func connectionUnhealthyTimeout() {
        let lastHeartbeat = Date().addingTimeInterval(-120)
        let result = EventStreamLogic.isConnectionHealthy(
            lastHeartbeat: lastHeartbeat,
            expectedInterval: 30.0
        )
        #expect(result == false)
    }
    
    @Test("Event passes filter when included")
    func eventPassesFilterIncluded() {
        let event = ParsedControlPlaneEvent.heartbeat(HeartbeatEvent())
        let filters: Set<ControlPlaneEventType> = [.heartbeat, .overrideInstance]
        
        let result = EventStreamLogic.eventPassesFilter(event: event, filters: filters)
        #expect(result == true)
    }
    
    @Test("Event fails filter when excluded")
    func eventFailsFilterExcluded() {
        let event = ParsedControlPlaneEvent.heartbeat(HeartbeatEvent())
        let filters: Set<ControlPlaneEventType> = [.overrideInstance]
        
        let result = EventStreamLogic.eventPassesFilter(event: event, filters: filters)
        #expect(result == false)
    }
    
    @Test("Event passes nil filter")
    func eventPassesNilFilter() {
        let event = ParsedControlPlaneEvent.heartbeat(HeartbeatEvent())
        
        let result = EventStreamLogic.eventPassesFilter(event: event, filters: nil)
        #expect(result == true)
    }
    
    @Test("Build endpoint URL without filters")
    func buildURLWithoutFilters() {
        let baseURL = URL(string: "https://ns.local")!
        let url = EventStreamLogic.buildEndpointURL(
            baseURL: baseURL,
            filters: nil,
            lastEventId: nil
        )
        
        #expect(url.absoluteString == "https://ns.local/v1/events")
    }
    
    @Test("Build endpoint URL with filters")
    func buildURLWithFilters() {
        let baseURL = URL(string: "https://ns.local")!
        let filters: Set<ControlPlaneEventType> = [.overrideInstance, .overrideCancel]
        let url = EventStreamLogic.buildEndpointURL(
            baseURL: baseURL,
            filters: filters,
            lastEventId: nil
        )
        
        #expect(url.absoluteString.contains("types="))
        #expect(url.absoluteString.contains("overrideCancel"))
        #expect(url.absoluteString.contains("overrideInstance"))
    }
    
    @Test("Build endpoint URL with last event ID")
    func buildURLWithLastEventId() {
        let baseURL = URL(string: "https://ns.local")!
        let url = EventStreamLogic.buildEndpointURL(
            baseURL: baseURL,
            filters: nil,
            lastEventId: "event-123"
        )
        
        #expect(url.absoluteString.contains("last_event_id=event-123"))
    }
}

// MARK: - Event Type Tests

@Suite("Control Plane Event Types")
struct ControlPlaneEventTypeTests {
    @Test("All event types have raw values")
    func allEventTypesHaveRawValues() {
        for eventType in ControlPlaneEventType.allCases {
            #expect(!eventType.rawValue.isEmpty)
        }
    }
    
    @Test("Event types are distinct")
    func eventTypesDistinct() {
        let allRawValues = ControlPlaneEventType.allCases.map { $0.rawValue }
        let uniqueValues = Set(allRawValues)
        #expect(allRawValues.count == uniqueValues.count)
    }
}

// MARK: - Statistics Tests

@Suite("Event Stream Statistics")
struct EventStreamStatisticsTests {
    @Test("Initial statistics are zero")
    func initialStats() {
        let stats = EventStreamStatistics()
        
        #expect(stats.totalEvents == 0)
        #expect(stats.connectionCount == 0)
        #expect(stats.disconnectionCount == 0)
        #expect(stats.lastConnectionTime == nil)
        #expect(stats.lastDisconnectionTime == nil)
    }
    
    @Test("With event increments count")
    func withEvent() {
        let stats = EventStreamStatistics()
        let updated = stats.withEvent().withEvent().withEvent()
        
        #expect(updated.totalEvents == 3)
    }
    
    @Test("With connection increments and sets time")
    func withConnection() {
        let stats = EventStreamStatistics()
        let updated = stats.withConnection()
        
        #expect(updated.connectionCount == 1)
        #expect(updated.lastConnectionTime != nil)
    }
    
    @Test("With disconnection increments and sets time")
    func withDisconnection() {
        let stats = EventStreamStatistics()
        let updated = stats.withDisconnection()
        
        #expect(updated.disconnectionCount == 1)
        #expect(updated.lastDisconnectionTime != nil)
    }
}

// MARK: - Heartbeat Event Tests

@Suite("Heartbeat Event")
struct HeartbeatEventTests {
    @Test("Default initializer")
    func defaultInit() {
        let event = HeartbeatEvent()
        
        #expect(event.sequence == 0)
    }
    
    @Test("Custom initializer")
    func customInit() {
        let now = Date()
        let event = HeartbeatEvent(
            timestamp: now,
            serverTime: now.addingTimeInterval(-1),
            sequence: 42
        )
        
        #expect(event.sequence == 42)
        #expect(event.timestamp == now)
    }
    
    @Test("Heartbeat encodes and decodes")
    func codable() throws {
        let event = HeartbeatEvent(sequence: 100)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeartbeatEvent.self, from: data)
        
        #expect(decoded.sequence == 100)
    }
}
