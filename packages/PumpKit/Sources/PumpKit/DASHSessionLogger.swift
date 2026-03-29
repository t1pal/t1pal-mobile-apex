// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DASHSessionLogger.swift
// PumpKit
//
// DASH-specific session logging with EAP-AKA' state tracking.
// Mirrors Python dash-pair.py verbose logging for cross-platform debugging.
//
// Trace: DASH-DIAG-002, DASH-DIAG-003, PRD-005
//
// Usage:
//   let logger = DASHSessionLogger(podId: "123456")
//   logger.logStateTransition(from: .idle, to: .keyExchange)
//   logger.logKeyExchangeStep(step: "computeSharedSecret", input: [...], output: [...])
//   logger.logMilenageStep(function: "f2", input: [...], output: [...])

import Foundation

// MARK: - DASH Session State (DASH-DIAG-002)

/// DASH session state machine states
public enum DASHSessionState: String, Codable, Sendable {
    case idle = "IDLE"
    case scanning = "SCANNING"
    case connecting = "CONNECTING"
    case keyExchange = "KEY_EXCHANGE"
    case eapAkaChallenge = "EAP_AKA_CHALLENGE"
    case eapAkaResponse = "EAP_AKA_RESPONSE"
    case sessionEstablished = "SESSION_ESTABLISHED"
    case commandPending = "COMMAND_PENDING"
    case commandComplete = "COMMAND_COMPLETE"
    case disconnecting = "DISCONNECTING"
    case error = "ERROR"
}

// MARK: - State Transition Entry

/// Log entry for state transitions (DASH-DIAG-002)
public struct DASHStateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: DASHSessionState
    public let toState: DASHSessionState
    public let reason: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] STATE: \(fromState.rawValue) → \(toState.rawValue) // \(reason)"
    }
}

// MARK: - Crypto Step Entry

/// Log entry for cryptographic operations (DASH-DIAG-003, DASH-DIAG-005)
public struct DASHCryptoStep: Codable, Sendable {
    public let timestamp: Date
    public let operation: String  // e.g., "KeyExchange", "Milenage"
    public let step: String       // e.g., "f2", "computeSharedSecret"
    public let inputHex: String
    public let outputHex: String
    public let notes: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] CRYPTO \(operation).\(step): \(inputHex.prefix(32))... → \(outputHex.prefix(32))... // \(notes)"
    }
}

// MARK: - DASH Session Logger

/// DASH-specific session logger with state tracking (DASH-DIAG-003)
public final class DASHSessionLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let startTime: Date
    private let podId: String
    
    /// Protocol-level logger (inherited from PumpProtocolLogger)
    public let protocolLogger: PumpProtocolLogger
    
    /// State transitions
    private var stateTransitions: [DASHStateTransition] = []
    
    /// Crypto steps (key exchange, Milenage)
    private var cryptoSteps: [DASHCryptoStep] = []
    
    /// Current state
    private var currentState: DASHSessionState = .idle
    
    /// Whether logging is enabled
    public var isEnabled: Bool = true
    
    /// Whether verbose console output is enabled
    public var verboseConsole: Bool
    
    /// Initialize with pod ID
    public init(podId: String, verbose: Bool = false) {
        self.podId = podId
        self.startTime = Date()
        self.verboseConsole = verbose
        self.protocolLogger = PumpProtocolLogger(
            pumpType: "OmnipodDASH",
            pumpId: podId
        )
    }
    
    // MARK: - State Tracking (DASH-DIAG-002)
    
    /// Log a state transition
    public func logStateTransition(
        from: DASHSessionState,
        to: DASHSessionState,
        reason: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let transition = DASHStateTransition(
            timestamp: Date(),
            fromState: from,
            toState: to,
            reason: reason,
            elapsedMs: elapsed
        )
        
        stateTransitions.append(transition)
        currentState = to
        
        if verboseConsole {
            print("[DASHSession] \(transition.formatted)")
        }
    }
    
    /// Convenience: transition to new state
    public func transitionTo(_ newState: DASHSessionState, reason: String = "") {
        let oldState = currentState
        logStateTransition(from: oldState, to: newState, reason: reason)
    }
    
    /// Get current state
    public func getCurrentState() -> DASHSessionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    // MARK: - Crypto Logging (DASH-DIAG-005)
    
    /// Log a cryptographic operation step
    public func logCryptoStep(
        operation: String,
        step: String,
        input: Data,
        output: Data,
        notes: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = DASHCryptoStep(
            timestamp: Date(),
            operation: operation,
            step: step,
            inputHex: input.hexEncodedString(),
            outputHex: output.hexEncodedString(),
            notes: notes,
            elapsedMs: elapsed
        )
        
        cryptoSteps.append(entry)
        
        if verboseConsole {
            print("[DASHSession] \(entry.formatted)")
        }
    }
    
    /// Log key exchange step
    public func logKeyExchangeStep(step: String, input: Data, output: Data, notes: String = "") {
        logCryptoStep(operation: "KeyExchange", step: step, input: input, output: output, notes: notes)
    }
    
    /// Log Milenage function (f1, f2, f3, f5, f5*)
    public func logMilenageStep(function: String, input: Data, output: Data, notes: String = "") {
        logCryptoStep(operation: "Milenage", step: function, input: input, output: output, notes: notes)
    }
    
    // MARK: - Protocol Logging (Delegates to PumpProtocolLogger)
    
    /// Log TX bytes
    public func tx(_ bytes: Data, context: String = "") {
        protocolLogger.tx(bytes, context: context)
    }
    
    /// Log RX bytes
    public func rx(_ bytes: Data, context: String = "") {
        protocolLogger.rx(bytes, context: context)
    }
    
    // MARK: - Command Logging (PROTO-DASH-DIAG)
    
    /// Log pod command sent
    public func logCommandSent(
        command: String,
        payload: Data? = nil,
        notes: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let payloadHex = payload?.hexEncodedString() ?? ""
        
        if verboseConsole {
            print("[DASHSession] [\(String(format: "%8.2f", elapsed))ms] CMD TX: \(command) \(payloadHex.isEmpty ? "" : "[\(payloadHex.prefix(32))...]") // \(notes)")
        }
        
        // Also log via protocol logger for TX/RX trace
        if let payload = payload {
            protocolLogger.tx(payload, context: "CMD:\(command)")
        }
    }
    
    /// Log pod command response
    public func logCommandResponse(
        command: String,
        response: Data? = nil,
        success: Bool,
        notes: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let responseHex = response?.hexEncodedString() ?? ""
        let statusIcon = success ? "✓" : "✗"
        
        if verboseConsole {
            print("[DASHSession] [\(String(format: "%8.2f", elapsed))ms] CMD RX: \(command) \(statusIcon) \(responseHex.isEmpty ? "" : "[\(responseHex.prefix(32))...]") // \(notes)")
        }
        
        // Also log via protocol logger for TX/RX trace
        if let response = response {
            protocolLogger.rx(response, context: "RSP:\(command):\(success ? "OK" : "ERR")")
        }
    }
    
    /// Log bolus delivery event
    public func logBolusDelivery(
        units: Double,
        duration: TimeInterval,
        success: Bool
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let statusIcon = success ? "✓" : "✗"
        
        if verboseConsole {
            print("[DASHSession] [\(String(format: "%8.2f", elapsed))ms] BOLUS: \(String(format: "%.2f", units))U over \(String(format: "%.0f", duration))s \(statusIcon)")
        }
    }
    
    /// Log temp basal event
    public func logTempBasal(
        rate: Double,
        duration: TimeInterval,
        isSet: Bool
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let action = isSet ? "SET" : "CANCEL"
        
        if verboseConsole {
            print("[DASHSession] [\(String(format: "%8.2f", elapsed))ms] TEMP_BASAL \(action): \(String(format: "%.2f", rate))U/h for \(String(format: "%.0f", duration / 60))min")
        }
    }
    
    /// Log delivery state change
    public func logDeliveryStateChange(
        from: String,
        to: String,
        reason: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        if verboseConsole {
            print("[DASHSession] [\(String(format: "%8.2f", elapsed))ms] DELIVERY: \(from) → \(to) // \(reason)")
        }
    }
    
    // MARK: - Export
    
    /// Export complete session for analysis
    public func exportSession() -> DASHSessionExport {
        lock.lock()
        defer { lock.unlock() }
        
        return DASHSessionExport(
            podId: podId,
            startTime: startTime,
            endTime: Date(),
            stateTransitions: stateTransitions,
            cryptoSteps: cryptoSteps,
            protocolEntries: protocolLogger.getEntries()
        )
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        stateTransitions.removeAll()
        cryptoSteps.removeAll()
        protocolLogger.clear()
    }
}

// MARK: - Session Export

/// Complete DASH session export
public struct DASHSessionExport: Codable, Sendable {
    public let podId: String
    public let startTime: Date
    public let endTime: Date
    public let stateTransitions: [DASHStateTransition]
    public let cryptoSteps: [DASHCryptoStep]
    public let protocolEntries: [ProtocolLogEntry]
    
    /// Export as JSON
    public func asJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Export as formatted text
    public func asText() -> String {
        var lines: [String] = []
        lines.append("=== DASH Session Export ===")
        lines.append("Pod ID: \(podId)")
        lines.append("Started: \(ISO8601DateFormatter().string(from: startTime))")
        lines.append("Ended: \(ISO8601DateFormatter().string(from: endTime))")
        lines.append("")
        
        lines.append("--- State Transitions (\(stateTransitions.count)) ---")
        for t in stateTransitions {
            lines.append(t.formatted)
        }
        lines.append("")
        
        lines.append("--- Crypto Steps (\(cryptoSteps.count)) ---")
        for c in cryptoSteps {
            lines.append(c.formatted)
        }
        lines.append("")
        
        lines.append("--- Protocol Entries (\(protocolEntries.count)) ---")
        for p in protocolEntries {
            lines.append(p.formatted)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Data Extension

extension Data {
    /// Hex string representation
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
