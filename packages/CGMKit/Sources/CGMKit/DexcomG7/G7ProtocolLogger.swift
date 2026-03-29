// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G7ProtocolLogger.swift
// CGMKit - DexcomG7
//
// Protocol logger for G7 J-PAKE authentication instrumentation.
// Captures round-by-round traces for debugging and evidence collection.
//
// Trace: UNCERT-G7-003

import Foundation
import BLEKit

// MARK: - G7 Protocol Events

/// Events specific to G7 J-PAKE authentication
public enum G7ProtocolEvent: String, Sendable, Codable, CaseIterable {
    // Authentication lifecycle
    case authenticationStarted = "auth.started"
    case authenticationCompleted = "auth.completed"
    case authenticationFailed = "auth.failed"
    
    // Round 1
    case round1Started = "round1.started"
    case round1LocalGenerated = "round1.local_generated"
    case round1RemoteReceived = "round1.remote_received"
    case round1Completed = "round1.completed"
    case round1Failed = "round1.failed"
    
    // Round 2
    case round2Started = "round2.started"
    case round2LocalComputed = "round2.local_computed"
    case round2RemoteReceived = "round2.remote_received"
    case round2Completed = "round2.completed"
    case round2Failed = "round2.failed"
    
    // Key confirmation
    case keyConfirmationStarted = "key_confirm.started"
    case keyConfirmationSent = "key_confirm.sent"
    case keyConfirmationReceived = "key_confirm.received"
    case keyConfirmationCompleted = "key_confirm.completed"
    case keyConfirmationFailed = "key_confirm.failed"
    
    // Zero-knowledge proofs
    case zkProofGenerated = "zkp.generated"
    case zkProofVerified = "zkp.verified"
    case zkProofFailed = "zkp.failed"
    
    // EC operations
    case ecPointComputed = "ec.point_computed"
    case ecKeyDerived = "ec.key_derived"
    case ecOperationFailed = "ec.failed"
    
    // Session
    case sessionKeyDerived = "session.key_derived"
    case sessionEstablished = "session.established"
    
    // Glucose data (PROTO-G7-DIAG)
    case glucoseReceived = "glucose.received"
    case glucoseInvalid = "glucose.invalid"
    case egvReceived = "egv.received"
    case egvInvalid = "egv.invalid"
    case sensorStateChanged = "sensor.state_changed"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .authenticationStarted: return "Authentication started"
        case .authenticationCompleted: return "Authentication completed successfully"
        case .authenticationFailed: return "Authentication failed"
        case .round1Started: return "Round 1 started"
        case .round1LocalGenerated: return "Round 1 local data generated"
        case .round1RemoteReceived: return "Round 1 remote data received"
        case .round1Completed: return "Round 1 completed"
        case .round1Failed: return "Round 1 failed"
        case .round2Started: return "Round 2 started"
        case .round2LocalComputed: return "Round 2 local computation done"
        case .round2RemoteReceived: return "Round 2 remote data received"
        case .round2Completed: return "Round 2 completed"
        case .round2Failed: return "Round 2 failed"
        case .keyConfirmationStarted: return "Key confirmation started"
        case .keyConfirmationSent: return "Key confirmation sent"
        case .keyConfirmationReceived: return "Key confirmation received"
        case .keyConfirmationCompleted: return "Key confirmation completed"
        case .keyConfirmationFailed: return "Key confirmation failed"
        case .zkProofGenerated: return "ZK proof generated"
        case .zkProofVerified: return "ZK proof verified"
        case .zkProofFailed: return "ZK proof verification failed"
        case .ecPointComputed: return "EC point computed"
        case .ecKeyDerived: return "EC key derived"
        case .ecOperationFailed: return "EC operation failed"
        case .sessionKeyDerived: return "Session key derived"
        case .sessionEstablished: return "Session established"
        // Glucose events (PROTO-G7-DIAG)
        case .glucoseReceived: return "Glucose reading received"
        case .glucoseInvalid: return "Invalid glucose reading"
        case .egvReceived: return "EGV reading received"
        case .egvInvalid: return "Invalid EGV reading"
        case .sensorStateChanged: return "Sensor state changed"
        }
    }
    
    /// Log level for this event
    public var logLevel: LogLevel {
        switch self {
        case .authenticationFailed, .round1Failed, .round2Failed,
             .keyConfirmationFailed, .zkProofFailed, .ecOperationFailed,
             .glucoseInvalid, .egvInvalid:
            return .error
        case .authenticationCompleted, .sessionEstablished,
             .glucoseReceived, .egvReceived:
            return .info
        case .round1Completed, .round2Completed, .keyConfirmationCompleted,
             .sensorStateChanged:
            return .info
        default:
            return .debug
        }
    }
}

// MARK: - Session State Machine (G7-DIAG-003)

/// J-PAKE session states for protocol tracing
/// Mirrors Python g7-jpake.py SessionState enum exactly
/// Trace: G7-DIAG-003
public enum G7SessionState: String, Sendable, Codable, CaseIterable {
    case initial = "INIT"
    case round1Generated = "ROUND1_GENERATED"
    case round1Sent = "ROUND1_SENT"
    case round1Received = "ROUND1_RECEIVED"
    case round1Verified = "ROUND1_VERIFIED"
    case round2Generated = "ROUND2_GENERATED"
    case round2Sent = "ROUND2_SENT"
    case round2Received = "ROUND2_RECEIVED"
    case round2Verified = "ROUND2_VERIFIED"
    case keyDerived = "KEY_DERIVED"
    case confirmGenerated = "CONFIRM_GENERATED"
    case confirmSent = "CONFIRM_SENT"
    case confirmReceived = "CONFIRM_RECEIVED"
    case confirmVerified = "CONFIRM_VERIFIED"
    case authenticated = "AUTHENTICATED"
    case failed = "FAILED"
    
    /// Valid transitions from this state
    public var validTransitions: [G7SessionState] {
        switch self {
        case .initial:
            return [.round1Generated, .round1Received]
        case .round1Generated:
            return [.round1Sent]
        case .round1Sent:
            return [.round1Received]
        case .round1Received:
            return [.round1Verified, .failed]
        case .round1Verified:
            return [.round2Generated]
        case .round2Generated:
            return [.round2Sent]
        case .round2Sent:
            return [.round2Received]
        case .round2Received:
            return [.round2Verified, .failed]
        case .round2Verified:
            return [.keyDerived]
        case .keyDerived:
            return [.confirmGenerated, .confirmReceived]
        case .confirmGenerated:
            return [.confirmSent]
        case .confirmSent:
            return [.confirmReceived]
        case .confirmReceived:
            return [.confirmVerified, .failed]
        case .confirmVerified:
            return [.authenticated]
        case .authenticated, .failed:
            return []
        }
    }
    
    /// Check if transition to target state is valid
    public func canTransition(to target: G7SessionState) -> Bool {
        validTransitions.contains(target)
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .initial: return "Initial state"
        case .round1Generated: return "Round 1 message generated"
        case .round1Sent: return "Round 1 message sent"
        case .round1Received: return "Round 1 message received"
        case .round1Verified: return "Round 1 ZKPs verified"
        case .round2Generated: return "Round 2 message generated"
        case .round2Sent: return "Round 2 message sent"
        case .round2Received: return "Round 2 message received"
        case .round2Verified: return "Round 2 ZKP verified"
        case .keyDerived: return "Session key derived"
        case .confirmGenerated: return "Confirmation hash generated"
        case .confirmSent: return "Confirmation hash sent"
        case .confirmReceived: return "Confirmation hash received"
        case .confirmVerified: return "Confirmation verified"
        case .authenticated: return "Session authenticated"
        case .failed: return "Authentication failed"
        }
    }
}

// MARK: - Message Direction

/// Direction indicator for TX/RX logging
/// Trace: G7-DIAG-003
public enum MessageDirection: String, Sendable, Codable {
    case tx = "TX"  // Transmitted (outgoing)
    case rx = "RX"  // Received (incoming)
    
    /// Display prefix with arrow
    public var prefix: String {
        switch self {
        case .tx: return "[TX →]"
        case .rx: return "[← RX]"
        }
    }
    
    /// Emoji indicator
    public var emoji: String {
        switch self {
        case .tx: return "📤"
        case .rx: return "📥"
        }
    }
}

// MARK: - Session Transition Record

/// Record of a state transition
public struct G7SessionTransition: Sendable, Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let fromState: G7SessionState
    public let toState: G7SessionState
    public let context: String
    public let valid: Bool
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        fromState: G7SessionState,
        toState: G7SessionState,
        context: String = "",
        valid: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromState = fromState
        self.toState = toState
        self.context = context
        self.valid = valid
    }
    
    /// Format for display
    public var formatted: String {
        let arrow = valid ? "→" : "⛔"
        let contextStr = context.isEmpty ? "" : " (\(context))"
        return "\(fromState.rawValue) \(arrow) \(toState.rawValue)\(contextStr)"
    }
}

// MARK: - Session Context

/// Session context with state tracking and transition validation
/// Mirrors Python SessionContext class
/// Trace: G7-DIAG-003
public actor G7SessionContext {
    
    // MARK: - Properties
    
    /// Current session state
    public private(set) var state: G7SessionState = .initial
    
    /// All state transitions
    public private(set) var transitions: [G7SessionTransition] = []
    
    /// Error context if session failed
    public private(set) var errorContext: String?
    
    /// Session start time
    public let startTime: Date
    
    /// Session ID for correlation
    public let sessionId: String
    
    // MARK: - Cryptographic State (for debugging)
    
    /// Password scalar (derived from sensor code)
    public private(set) var passwordScalar: Data?
    
    /// Our Round 1 public keys
    public private(set) var ourGx1: Data?
    public private(set) var ourGx2: Data?
    
    /// Peer's Round 1 public keys
    public private(set) var peerGx3: Data?
    public private(set) var peerGx4: Data?
    
    /// Our Round 2 value
    public private(set) var ourA: Data?
    
    /// Peer's Round 2 value
    public private(set) var peerB: Data?
    
    /// Derived session key
    public private(set) var sharedKey: Data?
    
    // MARK: - Initialization
    
    public init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
        self.startTime = Date()
    }
    
    // MARK: - State Transitions
    
    /// Attempt to transition to a new state
    /// - Parameters:
    ///   - newState: Target state
    ///   - context: Optional context string
    /// - Returns: Whether transition was valid
    @discardableResult
    public func transition(to newState: G7SessionState, context: String = "") -> Bool {
        let valid = state.canTransition(to: newState)
        
        let record = G7SessionTransition(
            fromState: state,
            toState: newState,
            context: context,
            valid: valid
        )
        transitions.append(record)
        
        if valid {
            state = newState
        } else {
            // Invalid transition - move to failed state
            errorContext = "Invalid transition from \(state.rawValue) to \(newState.rawValue)"
            state = .failed
        }
        
        return valid
    }
    
    /// Mark session as failed with reason
    public func fail(reason: String) {
        errorContext = reason
        state = .failed
    }
    
    // MARK: - Cryptographic State Updates
    
    public func setPasswordScalar(_ data: Data) {
        passwordScalar = data
    }
    
    public func setOurRound1(gx1: Data, gx2: Data) {
        ourGx1 = gx1
        ourGx2 = gx2
    }
    
    public func setPeerRound1(gx3: Data, gx4: Data) {
        peerGx3 = gx3
        peerGx4 = gx4
    }
    
    public func setOurRound2(A: Data) {
        ourA = A
    }
    
    public func setPeerRound2(B: Data) {
        peerB = B
    }
    
    public func setSharedKey(_ key: Data) {
        sharedKey = key
    }
    
    // MARK: - Query
    
    /// Duration since session start
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Duration in milliseconds
    public var elapsedMs: Double {
        elapsed * 1000.0
    }
    
    /// Check if session completed successfully
    public var isAuthenticated: Bool {
        state == .authenticated
    }
    
    /// Check if session failed
    public var isFailed: Bool {
        state == .failed
    }
    
    /// Get all valid transitions
    public var validTransitions: [G7SessionTransition] {
        transitions.filter { $0.valid }
    }
    
    /// Get invalid transitions (for debugging)
    public var invalidTransitions: [G7SessionTransition] {
        transitions.filter { !$0.valid }
    }
    
    // MARK: - Export
    
    /// Export session state as dictionary for JSON
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": sessionId,
            "state": state.rawValue,
            "elapsedMs": elapsedMs,
            "transitionCount": transitions.count
        ]
        
        if let error = errorContext {
            dict["errorContext"] = error
        }
        
        // Include crypto state if present (truncated for display)
        if let key = sharedKey {
            dict["sharedKeyPrefix"] = key.prefix(8).hexEncodedString()
        }
        
        return dict
    }
    
    /// Export as JSON data
    public func exportJSON() throws -> Data {
        let exportable = SessionExport(
            sessionId: sessionId,
            state: state,
            elapsedMs: elapsedMs,
            errorContext: errorContext,
            transitions: transitions,
            cryptoState: CryptoStateExport(
                passwordScalar: passwordScalar?.hexEncodedString(),
                ourGx1: ourGx1?.hexEncodedString(),
                ourGx2: ourGx2?.hexEncodedString(),
                peerGx3: peerGx3?.hexEncodedString(),
                peerGx4: peerGx4?.hexEncodedString(),
                ourA: ourA?.hexEncodedString(),
                peerB: peerB?.hexEncodedString(),
                sharedKey: sharedKey?.hexEncodedString()
            )
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportable)
    }
}

// MARK: - Export Structures

private struct SessionExport: Codable {
    let sessionId: String
    let state: G7SessionState
    let elapsedMs: Double
    let errorContext: String?
    let transitions: [G7SessionTransition]
    let cryptoState: CryptoStateExport
}

private struct CryptoStateExport: Codable {
    let passwordScalar: String?
    let ourGx1: String?
    let ourGx2: String?
    let peerGx3: String?
    let peerGx4: String?
    let ourA: String?
    let peerB: String?
    let sharedKey: String?
}

// MARK: - Data Extension for Hex

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - G7 Protocol Log Entry

/// Detailed log entry for G7 J-PAKE events
public struct G7ProtocolLogEntry: Sendable, Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let event: G7ProtocolEvent
    public let message: String
    public let variant: G7VariantSelection?
    public let metadata: [String: String]
    public let roundNumber: Int?
    public let durationMs: Double?
    public let success: Bool
    public let direction: MessageDirection?  // G7-DIAG-003: TX/RX direction
    public let sessionState: G7SessionState?  // G7-DIAG-003: Current session state
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        event: G7ProtocolEvent,
        message: String,
        variant: G7VariantSelection? = nil,
        metadata: [String: String] = [:],
        roundNumber: Int? = nil,
        durationMs: Double? = nil,
        success: Bool = true,
        direction: MessageDirection? = nil,
        sessionState: G7SessionState? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.message = message
        self.variant = variant
        self.metadata = metadata
        self.roundNumber = roundNumber
        self.durationMs = durationMs
        self.success = success
        self.direction = direction
        self.sessionState = sessionState
    }
    
    /// Format for display
    public var formatted: String {
        let timeStr = ISO8601DateFormatter().string(from: timestamp)
        let statusIcon = success ? "✓" : "✗"
        let directionStr = direction.map { " \($0.prefix)" } ?? ""
        let stateStr = sessionState.map { " [\($0.rawValue)]" } ?? ""
        var result = "\(timeStr)\(directionStr) [\(event.rawValue)] \(statusIcon) \(message)\(stateStr)"
        if let round = roundNumber {
            result += " (round \(round))"
        }
        if let duration = durationMs {
            result += " [\(String(format: "%.1f", duration))ms]"
        }
        return result
    }
}

// MARK: - G7 Protocol Logger

/// Actor for thread-safe G7 protocol logging
/// Trace: UNCERT-G7-003, G7-DIAG-003
public actor G7ProtocolLogger {
    
    // MARK: - Properties
    
    public let minimumLevel: LogLevel
    public let sessionId: String?
    
    private var entries: [G7ProtocolLogEntry] = []
    private var startTimes: [String: Date] = [:]
    private let maxEntries: Int
    private let currentVariant: G7VariantSelection?
    
    /// Session context for state tracking (G7-DIAG-003)
    private var sessionContext: G7SessionContext?
    
    // MARK: - Initialization
    
    public init(
        minimumLevel: LogLevel = .debug,
        sessionId: String? = UUID().uuidString,
        maxEntries: Int = 1000,
        variant: G7VariantSelection? = nil
    ) {
        self.minimumLevel = minimumLevel
        self.sessionId = sessionId
        self.maxEntries = maxEntries
        self.currentVariant = variant
    }
    
    // MARK: - Session Context (G7-DIAG-003)
    
    /// Create or get the session context
    public func getOrCreateSessionContext() -> G7SessionContext {
        if let existing = sessionContext {
            return existing
        }
        let context = G7SessionContext(sessionId: sessionId ?? UUID().uuidString)
        sessionContext = context
        return context
    }
    
    /// Get current session context (if exists)
    public func getSessionContext() -> G7SessionContext? {
        sessionContext
    }
    
    /// Reset session context for new session
    public func resetSessionContext() -> G7SessionContext {
        let context = G7SessionContext(sessionId: sessionId ?? UUID().uuidString)
        sessionContext = context
        return context
    }
    
    /// Get current session state
    public func currentSessionState() async -> G7SessionState? {
        await sessionContext?.state
    }
    
    // MARK: - Generic Logging
    
    /// Log a generic LogEntry (for compatibility)
    public func log(_ entry: LogEntry) {
        let g7Entry = G7ProtocolLogEntry(
            timestamp: entry.timestamp,
            event: .authenticationStarted,
            message: entry.message,
            variant: currentVariant,
            metadata: entry.metadata,
            success: entry.level != .error && entry.level != .critical
        )
        appendEntry(g7Entry)
    }
    
    // MARK: - G7-Specific Logging
    
    /// Log a G7 protocol event
    public func logEvent(
        _ event: G7ProtocolEvent,
        message: String = "",
        metadata: [String: String] = [:],
        roundNumber: Int? = nil,
        success: Bool = true,
        direction: MessageDirection? = nil
    ) async {
        let finalMessage = message.isEmpty ? event.description : message
        let duration = stopTimer(for: event.rawValue)
        let currentState = await sessionContext?.state
        
        let entry = G7ProtocolLogEntry(
            event: event,
            message: finalMessage,
            variant: currentVariant,
            metadata: metadata,
            roundNumber: roundNumber,
            durationMs: duration,
            success: success,
            direction: direction,
            sessionState: currentState
        )
        appendEntry(entry)
    }
    
    // MARK: - TX/RX Logging (G7-DIAG-003)
    
    /// Log transmitted (outgoing) message
    public func logTx(_ message: String, data: Data? = nil, event: G7ProtocolEvent = .authenticationStarted) async {
        var metadata: [String: String] = [:]
        if let data = data {
            metadata["dataSize"] = "\(data.count)"
            metadata["dataPrefix"] = data.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        await logEvent(event, message: message, metadata: metadata, direction: .tx)
    }
    
    /// Log received (incoming) message
    public func logRx(_ message: String, data: Data? = nil, event: G7ProtocolEvent = .authenticationStarted) async {
        var metadata: [String: String] = [:]
        if let data = data {
            metadata["dataSize"] = "\(data.count)"
            metadata["dataPrefix"] = data.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        await logEvent(event, message: message, metadata: metadata, direction: .rx)
    }
    
    // MARK: - State Transition Logging (G7-DIAG-003)
    
    /// Log and perform a state transition
    @discardableResult
    public func transitionState(to newState: G7SessionState, context: String = "") async -> Bool {
        guard let session = sessionContext else {
            // Create session context if needed
            let session = getOrCreateSessionContext()
            return await session.transition(to: newState, context: context)
        }
        let valid = await session.transition(to: newState, context: context)
        
        // Log the transition
        let logMessage = valid 
            ? "State: \(await session.state.rawValue)"
            : "Invalid transition to \(newState.rawValue)"
        await logEvent(
            valid ? .authenticationStarted : .authenticationFailed,
            message: logMessage,
            metadata: ["fromState": context, "toState": newState.rawValue],
            success: valid
        )
        
        return valid
    }
    
    // MARK: - Round Logging
    
    /// Log round 1 start
    public func logRound1Start() async {
        startTimer(for: "round1")
        await transitionState(to: .round1Generated, context: "Round 1 start")
        await logEvent(.round1Started, roundNumber: 1)
    }
    
    /// Log round 1 local generation
    public func logRound1LocalGenerated(publicKeySize: Int) async {
        await logEvent(
            .round1LocalGenerated,
            message: "Generated local key pair",
            metadata: ["publicKeySize": "\(publicKeySize)"],
            roundNumber: 1,
            direction: .tx
        )
    }
    
    /// Log round 1 remote received
    public func logRound1RemoteReceived(dataSize: Int) async {
        await transitionState(to: .round1Received, context: "Remote Round 1 data")
        await logEvent(
            .round1RemoteReceived,
            message: "Received remote round 1 data",
            metadata: ["dataSize": "\(dataSize)"],
            roundNumber: 1,
            direction: .rx
        )
    }
    
    /// Log round 1 completion
    public func logRound1Completed() async {
        let duration = stopTimer(for: "round1")
        await transitionState(to: .round1Verified, context: "ZKPs verified")
        await logEvent(
            .round1Completed,
            metadata: duration.map { ["durationMs": String(format: "%.1f", $0)] } ?? [:],
            roundNumber: 1
        )
    }
    
    /// Log round 1 failure
    public func logRound1Failed(error: String) async {
        _ = stopTimer(for: "round1")
        await sessionContext?.fail(reason: error)
        await logEvent(.round1Failed, message: error, roundNumber: 1, success: false)
    }
    
    /// Log round 2 start
    public func logRound2Start() async {
        startTimer(for: "round2")
        await transitionState(to: .round2Generated, context: "Round 2 start")
        await logEvent(.round2Started, roundNumber: 2)
    }
    
    /// Log round 2 remote received
    public func logRound2RemoteReceived(dataSize: Int) async {
        await transitionState(to: .round2Received, context: "Remote Round 2 data")
        await logEvent(
            .round2RemoteReceived,
            message: "Received remote round 2 data",
            metadata: ["dataSize": "\(dataSize)"],
            roundNumber: 2,
            direction: .rx
        )
    }
    
    /// Log round 2 completion
    public func logRound2Completed() async {
        let duration = stopTimer(for: "round2")
        await transitionState(to: .round2Verified, context: "ZKP verified")
        await transitionState(to: .keyDerived, context: "Session key computed")
        await logEvent(
            .round2Completed,
            metadata: duration.map { ["durationMs": String(format: "%.1f", $0)] } ?? [:],
            roundNumber: 2
        )
    }
    
    /// Log round 2 failure
    public func logRound2Failed(error: String) async {
        _ = stopTimer(for: "round2")
        await sessionContext?.fail(reason: error)
        await logEvent(.round2Failed, message: error, roundNumber: 2, success: false)
    }
    
    /// Log key confirmation start
    public func logKeyConfirmationStart() async {
        startTimer(for: "keyConfirm")
        await transitionState(to: .confirmGenerated, context: "Confirmation hash generated")
        await logEvent(.keyConfirmationStarted)
    }
    
    /// Log key confirmation sent
    public func logKeyConfirmationSent() async {
        await transitionState(to: .confirmSent, context: "Confirmation sent")
        await logEvent(.keyConfirmationSent, direction: .tx)
    }
    
    /// Log key confirmation received
    public func logKeyConfirmationReceived(dataSize: Int) async {
        await transitionState(to: .confirmReceived, context: "Confirmation received")
        await logEvent(
            .keyConfirmationReceived,
            metadata: ["dataSize": "\(dataSize)"],
            direction: .rx
        )
    }
    
    /// Log key confirmation completion
    public func logKeyConfirmationCompleted() async {
        let duration = stopTimer(for: "keyConfirm")
        await transitionState(to: .confirmVerified, context: "Confirmation verified")
        await logEvent(
            .keyConfirmationCompleted,
            metadata: duration.map { ["durationMs": String(format: "%.1f", $0)] } ?? [:]
        )
    }
    
    /// Log key confirmation failure
    public func logKeyConfirmationFailed(error: String) async {
        _ = stopTimer(for: "keyConfirm")
        await sessionContext?.fail(reason: error)
        await logEvent(.keyConfirmationFailed, message: error, success: false)
    }
    
    /// Log authentication completion
    public func logAuthenticationCompleted(totalDurationMs: Double) async {
        await transitionState(to: .authenticated, context: "Session established")
        await logEvent(
            .authenticationCompleted,
            metadata: ["totalDurationMs": String(format: "%.1f", totalDurationMs)]
        )
        await logEvent(.sessionEstablished)
    }
    
    /// Log authentication failure
    public func logAuthenticationFailed(error: String, atRound: Int?) async {
        await sessionContext?.fail(reason: error)
        await logEvent(
            .authenticationFailed,
            message: error,
            roundNumber: atRound,
            success: false
        )
    }
    
    /// Log ZK proof event
    public func logZKProof(generated: Bool, verified: Bool? = nil, proofSize: Int? = nil) async {
        if generated {
            await logEvent(
                .zkProofGenerated,
                metadata: proofSize.map { ["proofSize": "\($0)"] } ?? [:]
            )
        }
        if let verified = verified {
            await logEvent(verified ? .zkProofVerified : .zkProofFailed, success: verified)
        }
    }
    
    // MARK: - Glucose Logging (PROTO-G7-DIAG)
    
    /// Log glucose reading received with raw data
    /// Trace: PROTO-G7-DIAG
    public func logGlucoseReceived(
        glucose: Int,
        trend: Int,
        algorithmState: Int,
        rawData: Data
    ) async {
        var metadata: [String: String] = [
            "glucose": "\(glucose)",
            "trend": "\(trend)",
            "algorithmState": "\(algorithmState)",
            "dataSize": "\(rawData.count)"
        ]
        // Include hex prefix for debugging
        let hexPrefix = rawData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        metadata["hexPrefix"] = hexPrefix
        
        await logEvent(
            .glucoseReceived,
            message: "Glucose \(glucose) mg/dL trend=\(trend)",
            metadata: metadata,
            direction: .rx
        )
    }
    
    /// Log invalid glucose reading
    /// Trace: PROTO-G7-DIAG
    public func logGlucoseInvalid(algorithmState: Int, rawData: Data, reason: String) async {
        var metadata: [String: String] = [
            "algorithmState": "\(algorithmState)",
            "dataSize": "\(rawData.count)",
            "reason": reason
        ]
        let hexPrefix = rawData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        metadata["hexPrefix"] = hexPrefix
        
        await logEvent(
            .glucoseInvalid,
            message: "Invalid glucose: \(reason)",
            metadata: metadata,
            success: false,
            direction: .rx
        )
    }
    
    /// Log EGV reading received with raw data
    /// Trace: PROTO-G7-DIAG
    public func logEGVReceived(
        glucose: Int,
        trend: Int,
        timestamp: Int,
        rawData: Data
    ) async {
        var metadata: [String: String] = [
            "glucose": "\(glucose)",
            "trend": "\(trend)",
            "timestamp": "\(timestamp)",
            "dataSize": "\(rawData.count)"
        ]
        let hexPrefix = rawData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        metadata["hexPrefix"] = hexPrefix
        
        await logEvent(
            .egvReceived,
            message: "EGV \(glucose) mg/dL trend=\(trend)",
            metadata: metadata,
            direction: .rx
        )
    }
    
    /// Log invalid EGV reading
    /// Trace: PROTO-G7-DIAG
    public func logEGVInvalid(rawData: Data, reason: String) async {
        var metadata: [String: String] = [
            "dataSize": "\(rawData.count)",
            "reason": reason
        ]
        let hexPrefix = rawData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        metadata["hexPrefix"] = hexPrefix
        
        await logEvent(
            .egvInvalid,
            message: "Invalid EGV: \(reason)",
            metadata: metadata,
            success: false,
            direction: .rx
        )
    }
    
    /// Log sensor state change
    /// Trace: PROTO-G7-DIAG
    public func logSensorStateChanged(from: String?, to: String, reason: String? = nil) async {
        var metadata: [String: String] = [
            "newState": to
        ]
        if let from = from {
            metadata["previousState"] = from
        }
        if let reason = reason {
            metadata["reason"] = reason
        }
        
        await logEvent(
            .sensorStateChanged,
            message: "Sensor state → \(to)",
            metadata: metadata
        )
    }
    
    // MARK: - Timer Management
    
    private func startTimer(for key: String) {
        startTimes[key] = Date()
    }
    
    private func stopTimer(for key: String) -> Double? {
        guard let start = startTimes.removeValue(forKey: key) else { return nil }
        return Date().timeIntervalSince(start) * 1000.0
    }
    
    // MARK: - Entry Management
    
    private func appendEntry(_ entry: G7ProtocolLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    // MARK: - Query
    
    /// Get all entries
    public func allEntries() -> [G7ProtocolLogEntry] {
        entries
    }
    
    /// Get entries for a specific round
    public func entries(forRound round: Int) -> [G7ProtocolLogEntry] {
        entries.filter { $0.roundNumber == round }
    }
    
    /// Get failure entries only
    public func failures() -> [G7ProtocolLogEntry] {
        entries.filter { !$0.success }
    }
    
    /// Get summary statistics
    public func statistics() -> G7LoggerStatistics {
        let totalCount = entries.count
        let successCount = entries.filter { $0.success }.count
        let failureCount = totalCount - successCount
        
        let round1Entries = entries(forRound: 1)
        let round2Entries = entries(forRound: 2)
        
        return G7LoggerStatistics(
            totalEvents: totalCount,
            successEvents: successCount,
            failureEvents: failureCount,
            round1Events: round1Entries.count,
            round2Events: round2Entries.count,
            currentVariant: currentVariant
        )
    }
    
    /// Clear all entries
    public func clear() {
        entries.removeAll()
        startTimes.removeAll()
    }
    
    /// Export as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }
}

// MARK: - Logger Statistics

/// Statistics from G7 protocol logger
public struct G7LoggerStatistics: Sendable, Codable {
    public let totalEvents: Int
    public let successEvents: Int
    public let failureEvents: Int
    public let round1Events: Int
    public let round2Events: Int
    public let currentVariant: G7VariantSelection?
    
    public var successRate: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(successEvents) / Double(totalEvents)
    }
}

// MARK: - Shared Logger Instance

/// Shared G7 protocol logger for global access
public actor G7LoggerManager {
    public static let shared = G7LoggerManager()
    
    private var logger: G7ProtocolLogger?
    
    private init() {}
    
    /// Get or create logger for current session
    public func getLogger(variant: G7VariantSelection? = nil) -> G7ProtocolLogger {
        if let existing = logger {
            return existing
        }
        let newLogger = G7ProtocolLogger(variant: variant)
        logger = newLogger
        return newLogger
    }
    
    /// Reset logger for new session
    public func resetLogger(variant: G7VariantSelection? = nil) -> G7ProtocolLogger {
        let newLogger = G7ProtocolLogger(variant: variant)
        logger = newLogger
        return newLogger
    }
    
    /// Get current logger (if exists)
    public func currentLogger() -> G7ProtocolLogger? {
        logger
    }
}

// MARK: - Fixture Capture Mode (G7-DIAG-005)

/// Protocol for fixture formats matching proto_common schema
/// Trace: G7-DIAG-005
public enum G7FixtureProtocol: String, Sendable, Codable {
    case dexcomG7 = "dexcom_g7"
}

/// Source traceability for a fixture vector
/// Matches proto_common/fixture_schema.py FixtureSource
public struct G7FixtureSource: Sendable, Codable {
    public let source: String
    public let sourceLine: Int?
    public let sourceAssertion: String?
    public let sourceProject: String
    
    public init(
        source: String,
        sourceLine: Int? = nil,
        sourceAssertion: String? = nil,
        sourceProject: String = "T1Pal"
    ) {
        self.source = source
        self.sourceLine = sourceLine
        self.sourceAssertion = sourceAssertion
        self.sourceProject = sourceProject
    }
    
    enum CodingKeys: String, CodingKey {
        case source
        case sourceLine = "source_line"
        case sourceAssertion = "source_assertion"
        case sourceProject = "source_project"
    }
}

/// A single captured protocol message vector
/// Matches proto_common/fixture_schema.py FixtureVector
public struct G7FixtureVector: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let source: String
    public let sourceLine: Int?
    public let sourceProject: String
    public let direction: MessageDirection
    public let inputHex: String?
    public let inputBytes: [UInt8]?
    public let roundNumber: Int?
    public let sessionState: String?
    public let event: String
    public let timestamp: Date
    public let elapsedMs: Double
    public let notes: String?
    public let variant: String?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        source: String = "live_capture",
        sourceLine: Int? = nil,
        sourceProject: String = "T1Pal",
        direction: MessageDirection,
        data: Data? = nil,
        roundNumber: Int? = nil,
        sessionState: G7SessionState? = nil,
        event: G7ProtocolEvent,
        timestamp: Date = Date(),
        elapsedMs: Double = 0,
        notes: String? = nil,
        variant: G7VariantSelection? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.sourceLine = sourceLine
        self.sourceProject = sourceProject
        self.direction = direction
        self.inputHex = data?.map { String(format: "%02x", $0) }.joined()
        self.inputBytes = data.map { [UInt8]($0) }
        self.roundNumber = roundNumber
        self.sessionState = sessionState?.rawValue
        self.event = event.rawValue
        self.timestamp = timestamp
        self.elapsedMs = elapsedMs
        self.notes = notes
        self.variant = variant?.id
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, source, direction, event, timestamp, notes, variant
        case sourceLine = "source_line"
        case sourceProject = "source_project"
        case inputHex = "input_hex"
        case inputBytes = "input_bytes"
        case roundNumber = "round_number"
        case sessionState = "session_state"
        case elapsedMs = "elapsed_ms"
    }
}

/// Complete fixture file for captured session
/// Matches proto_common/fixture_schema.py FixtureFile
public struct G7FixtureFile: Sendable, Codable {
    public let testName: String
    public let description: String
    public let protocolType: String
    public let reference: String
    public let captureTimestamp: Date
    public let sessionId: String
    public let variant: String?
    public let vectors: [G7FixtureVector]
    
    public init(
        testName: String,
        description: String,
        reference: String = "live_capture",
        captureTimestamp: Date = Date(),
        sessionId: String,
        variant: G7VariantSelection? = nil,
        vectors: [G7FixtureVector]
    ) {
        self.testName = testName
        self.description = description
        self.protocolType = G7FixtureProtocol.dexcomG7.rawValue
        self.reference = reference
        self.captureTimestamp = captureTimestamp
        self.sessionId = sessionId
        self.variant = variant?.id
        self.vectors = vectors
    }
    
    enum CodingKeys: String, CodingKey {
        case testName = "test_name"
        case description
        case protocolType = "protocol"
        case reference
        case captureTimestamp = "capture_timestamp"
        case sessionId = "session_id"
        case variant
        case vectors
    }
    
    /// Export as JSON data
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Export as JSON string
    public func exportJSONString() throws -> String {
        let data = try exportJSON()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Fixture capture session for collecting protocol messages
/// Trace: G7-DIAG-005
public actor G7FixtureCaptureSession {
    
    // MARK: - Properties
    
    public let sessionId: String
    public let startTime: Date
    public private(set) var isCapturing: Bool = false
    public private(set) var vectors: [G7FixtureVector] = []
    
    private let maxVectors: Int
    private var variant: G7VariantSelection?
    private var sessionState: G7SessionState = .initial
    
    // MARK: - Initialization
    
    public init(
        sessionId: String = UUID().uuidString,
        variant: G7VariantSelection? = nil,
        maxVectors: Int = 1000
    ) {
        self.sessionId = sessionId
        self.startTime = Date()
        self.variant = variant
        self.maxVectors = maxVectors
    }
    
    // MARK: - Capture Control
    
    /// Start capturing protocol messages
    public func startCapture() {
        isCapturing = true
        vectors.removeAll()
    }
    
    /// Stop capturing
    public func stopCapture() {
        isCapturing = false
    }
    
    /// Clear captured vectors
    public func clear() {
        vectors.removeAll()
    }
    
    /// Set variant for capture
    public func setVariant(_ variant: G7VariantSelection?) {
        self.variant = variant
    }
    
    /// Update session state
    public func setSessionState(_ state: G7SessionState) {
        self.sessionState = state
    }
    
    // MARK: - Message Capture
    
    /// Capture a transmitted message
    public func captureTx(
        name: String,
        data: Data,
        event: G7ProtocolEvent,
        roundNumber: Int? = nil,
        notes: String? = nil
    ) {
        guard isCapturing else { return }
        
        let vector = G7FixtureVector(
            name: name,
            direction: .tx,
            data: data,
            roundNumber: roundNumber,
            sessionState: sessionState,
            event: event,
            elapsedMs: elapsedMs,
            notes: notes,
            variant: variant
        )
        appendVector(vector)
    }
    
    /// Capture a received message
    public func captureRx(
        name: String,
        data: Data,
        event: G7ProtocolEvent,
        roundNumber: Int? = nil,
        notes: String? = nil
    ) {
        guard isCapturing else { return }
        
        let vector = G7FixtureVector(
            name: name,
            direction: .rx,
            data: data,
            roundNumber: roundNumber,
            sessionState: sessionState,
            event: event,
            elapsedMs: elapsedMs,
            notes: notes,
            variant: variant
        )
        appendVector(vector)
    }
    
    /// Capture a generic protocol event (no data)
    public func captureEvent(
        name: String,
        event: G7ProtocolEvent,
        direction: MessageDirection = .tx,
        roundNumber: Int? = nil,
        notes: String? = nil
    ) {
        guard isCapturing else { return }
        
        let vector = G7FixtureVector(
            name: name,
            direction: direction,
            roundNumber: roundNumber,
            sessionState: sessionState,
            event: event,
            elapsedMs: elapsedMs,
            notes: notes,
            variant: variant
        )
        appendVector(vector)
    }
    
    // MARK: - Export
    
    /// Export captured session as fixture file
    public func exportFixture(
        testName: String? = nil,
        description: String? = nil
    ) -> G7FixtureFile {
        let name = testName ?? "g7_jpake_capture_\(sessionId.prefix(8))"
        let desc = description ?? "Live capture from G7 J-PAKE session"
        
        return G7FixtureFile(
            testName: name,
            description: desc,
            reference: "live_capture",
            captureTimestamp: startTime,
            sessionId: sessionId,
            variant: variant,
            vectors: vectors
        )
    }
    
    /// Export as JSON data
    public func exportJSON(
        testName: String? = nil,
        description: String? = nil
    ) throws -> Data {
        try exportFixture(testName: testName, description: description).exportJSON()
    }
    
    /// Get vector count
    public var vectorCount: Int {
        vectors.count
    }
    
    /// Get elapsed time in ms
    public var elapsedMs: Double {
        Date().timeIntervalSince(startTime) * 1000.0
    }
    
    // MARK: - Private
    
    private func appendVector(_ vector: G7FixtureVector) {
        vectors.append(vector)
        if vectors.count > maxVectors {
            vectors.removeFirst(vectors.count - maxVectors)
        }
    }
}

// MARK: - G7ProtocolLogger Fixture Capture Extension

extension G7ProtocolLogger {
    
    /// Create fixture capture session integrated with this logger
    /// Trace: G7-DIAG-005
    public func createFixtureCaptureSession(variant: G7VariantSelection? = nil) -> G7FixtureCaptureSession {
        G7FixtureCaptureSession(
            sessionId: sessionId ?? UUID().uuidString,
            variant: variant
        )
    }
    
    /// Export all entries as fixture file format
    /// Trace: G7-DIAG-005
    public func exportAsFixtureFile(
        testName: String? = nil,
        description: String? = nil
    ) -> G7FixtureFile {
        let vectors = entries.enumerated().map { index, entry in
            G7FixtureVector(
                name: "\(entry.event.rawValue)_\(index)",
                direction: entry.direction ?? .tx,
                roundNumber: entry.roundNumber,
                sessionState: entry.sessionState,
                event: entry.event,
                timestamp: entry.timestamp,
                elapsedMs: entry.durationMs ?? 0,
                notes: entry.message.isEmpty ? nil : entry.message,
                variant: currentVariant
            )
        }
        
        let name = testName ?? "g7_log_export_\(sessionId?.prefix(8) ?? "unknown")"
        let desc = description ?? "Export from G7ProtocolLogger"
        
        return G7FixtureFile(
            testName: name,
            description: desc,
            reference: "logger_export",
            sessionId: sessionId ?? "unknown",
            variant: currentVariant,
            vectors: vectors
        )
    }
    
    /// Export as fixture JSON
    /// Trace: G7-DIAG-005
    public func exportFixtureJSON(
        testName: String? = nil,
        description: String? = nil
    ) throws -> Data {
        try exportAsFixtureFile(testName: testName, description: description).exportJSON()
    }
}
