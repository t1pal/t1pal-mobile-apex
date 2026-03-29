// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutWebSocket.swift
// NightscoutKit
//
// WebSocket real-time connection for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-008)
// Requirements: REQ-NS-007

import Foundation

// MARK: - WebSocket Event Types

/// Event types received from Nightscout WebSocket
public enum NightscoutSocketEvent: String, Codable, Sendable {
    case connect = "connect"
    case disconnect = "disconnect"
    case sgv = "sgv"
    case mbg = "mbg"
    case cal = "cal"
    case treatment = "treatment"
    case devicestatus = "devicestatus"
    case profileSwitch = "profileSwitch"
    case announcement = "announcement"
    case alarm = "alarm"
    case urgentAlarm = "urgent_alarm"
    case clearAlarm = "clear_alarm"
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = NightscoutSocketEvent(rawValue: value) ?? .unknown
    }
}

// MARK: - WebSocket Message

/// Message received from Nightscout WebSocket
public struct NightscoutSocketMessage: Sendable {
    public let event: NightscoutSocketEvent
    public let data: Data?
    public let timestamp: Date
    
    public init(event: NightscoutSocketEvent, data: Data? = nil, timestamp: Date = Date()) {
        self.event = event
        self.data = data
        self.timestamp = timestamp
    }
    
    /// Parse SGV entries from message data
    public func parseEntries() throws -> [NightscoutEntry]? {
        guard let data = data, event == .sgv else { return nil }
        return try JSONDecoder().decode([NightscoutEntry].self, from: data)
    }
    
    /// Parse treatments from message data
    public func parseTreatments() throws -> [NightscoutTreatment]? {
        guard let data = data, event == .treatment else { return nil }
        return try JSONDecoder().decode([NightscoutTreatment].self, from: data)
    }
    
    /// Parse device status from message data
    public func parseDeviceStatus() throws -> [NightscoutDeviceStatus]? {
        guard let data = data, event == .devicestatus else { return nil }
        return try JSONDecoder().decode([NightscoutDeviceStatus].self, from: data)
    }
}

// MARK: - WebSocket State

/// Connection state for WebSocket
public enum NightscoutSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

extension NightscoutSocketState {
    public var isFailedOrReconnecting: Bool {
        switch self {
        case .failed, .reconnecting:
            return true
        default:
            return false
        }
    }
}

// MARK: - WebSocket Delegate

/// Delegate protocol for WebSocket events
public protocol NightscoutSocketDelegate: AnyObject, Sendable {
    func socketDidConnect()
    func socketDidDisconnect(error: Error?)
    func socketDidReceive(message: NightscoutSocketMessage)
    func socketStateDidChange(to state: NightscoutSocketState)
}

// MARK: - WebSocket Actor (Darwin)

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

/// Real-time WebSocket connection to Nightscout
/// Requirements: REQ-NS-007
public actor NightscoutSocket {
    private let config: NightscoutConfig
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var state: NightscoutSocketState = .disconnected
    private var reconnectAttempt = 0
    private var maxReconnectAttempts = 10
    private var baseReconnectDelay: TimeInterval = 1.0
    private var maxReconnectDelay: TimeInterval = 60.0
    private var isListening = false
    private var messageHandlers: [(NightscoutSocketMessage) async -> Void] = []
    private var stateHandlers: [(NightscoutSocketState) async -> Void] = []
    
    public init(config: NightscoutConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }
    
    /// Current connection state
    public func getState() -> NightscoutSocketState {
        state
    }
    
    /// Add a message handler
    public func onMessage(_ handler: @escaping (NightscoutSocketMessage) async -> Void) {
        messageHandlers.append(handler)
    }
    
    /// Add a state change handler
    public func onStateChange(_ handler: @escaping (NightscoutSocketState) async -> Void) {
        stateHandlers.append(handler)
    }
    
    /// Connect to Nightscout WebSocket
    public func connect() async throws {
        guard state == .disconnected || state.isFailedOrReconnecting else {
            return
        }
        
        await setState(.connecting)
        
        // Build WebSocket URL
        var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false)!
        components.scheme = config.url.scheme == "https" ? "wss" : "ws"
        components.path = "/socket.io/"
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        
        if let token = config.token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            await setState(.failed(reason: "Invalid WebSocket URL"))
            throw NightscoutError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        if let hash = config.apiSecretHash {
            request.setValue(hash, forHTTPHeaderField: "api-secret")
        }
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        reconnectAttempt = 0
        await setState(.connected)
        
        // Start listening for messages
        if !isListening {
            isListening = true
            Task { await receiveMessages() }
        }
    }
    
    /// Disconnect from WebSocket
    public func disconnect() async {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isListening = false
        await setState(.disconnected)
    }
    
    /// Send a ping to keep connection alive
    public func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask?.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func receiveMessages() async {
        guard let task = webSocketTask else { return }
        
        do {
            while isListening {
                let message = try await task.receive()
                await handleMessage(message)
            }
        } catch {
            if isListening {
                await handleDisconnect(error: error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await parseSocketIOMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                await parseSocketIOMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseSocketIOMessage(_ text: String) async {
        // Socket.IO protocol: first char is message type
        // 0 = open, 1 = close, 2 = ping, 3 = pong, 4 = message
        guard !text.isEmpty else { return }
        
        let typeChar = text.first!
        let payload = String(text.dropFirst())
        
        switch typeChar {
        case "0":
            // Connection opened - Socket.IO handshake
            break
        case "2":
            // Ping - respond with pong
            try? await webSocketTask?.send(.string("3"))
        case "4":
            // Message - parse event
            await parseEventMessage(payload)
        default:
            break
        }
    }
    
    private func parseEventMessage(_ payload: String) async {
        // Socket.IO message format: [eventType, data]
        // First two chars are often "2[" for event array
        var jsonPayload = payload
        if payload.hasPrefix("2") {
            jsonPayload = String(payload.dropFirst())
        }
        
        guard let data = jsonPayload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let eventName = json.first as? String else {
            return
        }
        
        let event = NightscoutSocketEvent(rawValue: eventName) ?? .unknown
        var eventData: Data?
        
        if json.count > 1 {
            eventData = try? JSONSerialization.data(withJSONObject: json[1])
        }
        
        let socketMessage = NightscoutSocketMessage(event: event, data: eventData)
        
        for handler in messageHandlers {
            await handler(socketMessage)
        }
    }
    
    private func handleDisconnect(error: Error?) async {
        webSocketTask = nil
        
        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            await setState(.reconnecting(attempt: reconnectAttempt))
            
            // Exponential backoff
            let delay = min(baseReconnectDelay * pow(2, Double(reconnectAttempt - 1)), maxReconnectDelay)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            if isListening {
                try? await connect()
            }
        } else {
            isListening = false
            await setState(.failed(reason: error?.localizedDescription ?? "Max reconnect attempts reached"))
        }
    }
    
    private func setState(_ newState: NightscoutSocketState) async {
        state = newState
        for handler in stateHandlers {
            await handler(newState)
        }
    }
}

#else

// MARK: - WebSocket Actor (Linux Stub)

/// Linux-compatible WebSocket stub (full implementation requires additional dependencies)
/// Requirements: REQ-NS-007
public actor NightscoutSocket {
    private let config: NightscoutConfig
    private var state: NightscoutSocketState = .disconnected
    private var messageHandlers: [(NightscoutSocketMessage) async -> Void] = []
    private var stateHandlers: [(NightscoutSocketState) async -> Void] = []
    
    public init(config: NightscoutConfig) {
        self.config = config
    }
    
    /// Current connection state
    public func getState() -> NightscoutSocketState {
        state
    }
    
    /// Add a message handler
    public func onMessage(_ handler: @escaping (NightscoutSocketMessage) async -> Void) {
        messageHandlers.append(handler)
    }
    
    /// Add a state change handler
    public func onStateChange(_ handler: @escaping (NightscoutSocketState) async -> Void) {
        stateHandlers.append(handler)
    }
    
    /// Connect to Nightscout WebSocket (Linux stub - uses polling fallback)
    public func connect() async throws {
        // Linux: WebSocket not available in URLSession, use polling fallback
        await setState(.failed(reason: "WebSocket not available on Linux - use polling"))
    }
    
    /// Disconnect from WebSocket
    public func disconnect() async {
        await setState(.disconnected)
    }
    
    /// Send a ping
    public func ping() async throws {
        // No-op on Linux
    }
    
    private func setState(_ newState: NightscoutSocketState) async {
        state = newState
        for handler in stateHandlers {
            await handler(newState)
        }
    }
}

#endif

// MARK: - Real-time Sync Coordinator

/// Coordinates real-time updates with sync managers
/// Requirements: REQ-NS-007
public actor NightscoutRealtimeCoordinator {
    private let socket: NightscoutSocket
    private let entriesSyncManager: EntriesSyncManager?
    private let treatmentsSyncManager: TreatmentsSyncManager?
    private let deviceStatusSyncManager: DeviceStatusSyncManager?
    private var isRunning = false
    
    public init(
        socket: NightscoutSocket,
        entriesSyncManager: EntriesSyncManager? = nil,
        treatmentsSyncManager: TreatmentsSyncManager? = nil,
        deviceStatusSyncManager: DeviceStatusSyncManager? = nil
    ) {
        self.socket = socket
        self.entriesSyncManager = entriesSyncManager
        self.treatmentsSyncManager = treatmentsSyncManager
        self.deviceStatusSyncManager = deviceStatusSyncManager
    }
    
    /// Start real-time sync
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        await socket.onMessage { [weak self] message in
            await self?.handleMessage(message)
        }
        
        try await socket.connect()
    }
    
    /// Stop real-time sync
    public func stop() async {
        isRunning = false
        await socket.disconnect()
    }
    
    /// Check if coordinator is running
    public func getIsRunning() -> Bool {
        isRunning
    }
    
    private func handleMessage(_ message: NightscoutSocketMessage) async {
        switch message.event {
        case .sgv:
            if let entries = try? message.parseEntries() {
                for entry in entries {
                    await entriesSyncManager?.queueDownload(entry)
                }
            }
        case .treatment:
            if let treatments = try? message.parseTreatments() {
                for treatment in treatments {
                    await treatmentsSyncManager?.queueDownload(treatment)
                }
            }
        case .devicestatus:
            if let statuses = try? message.parseDeviceStatus() {
                for status in statuses {
                    await deviceStatusSyncManager?.queueDownload(status)
                }
            }
        default:
            break
        }
    }
}
