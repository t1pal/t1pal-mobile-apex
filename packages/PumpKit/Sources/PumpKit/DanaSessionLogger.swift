// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaSessionLogger.swift
// PumpKit
//
// Dana RS/i-specific session logging with BLE state tracking.
// Mirrors Python dana-parse.py verbose logging for cross-platform debugging.
//
// Trace: DANA-DIAG-002, DANA-DIAG-003, PRD-005
//
// Usage:
//   let logger = DanaSessionLogger(pumpSerial: "ABC123")
//   logger.logStateTransition(from: .idle, to: .connecting)
//   logger.logBLEExchange(direction: .write, data: [...])

import Foundation

// MARK: - Dana Session State (DANA-DIAG-002)

/// Dana session state machine states
public enum DanaSessionState: String, Codable, Sendable {
    case idle = "IDLE"
    case scanning = "SCANNING"
    case connecting = "CONNECTING"
    case discoveringServices = "DISCOVERING_SERVICES"
    case pairingRequest = "PAIRING_REQUEST"
    case pairingChallenge = "PAIRING_CHALLENGE"
    case pairingComplete = "PAIRING_COMPLETE"
    case keyExchange = "KEY_EXCHANGE"
    case sessionEstablished = "SESSION_ESTABLISHED"
    case readingStatus = "READING_STATUS"
    case commandPending = "COMMAND_PENDING"
    case commandComplete = "COMMAND_COMPLETE"
    case bolusing = "BOLUSING"
    case disconnecting = "DISCONNECTING"
    case error = "ERROR"
}

// MARK: - State Transition Entry

/// Log entry for state transitions (DANA-DIAG-002)
public struct DanaStateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: DanaSessionState
    public let toState: DanaSessionState
    public let reason: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] STATE: \(fromState.rawValue) → \(toState.rawValue) // \(reason)"
    }
}

// MARK: - BLE Exchange Entry

/// Log entry for BLE characteristic exchanges
public struct DanaBLEExchange: Codable, Sendable {
    public enum Direction: String, Codable, Sendable {
        case read = "READ"
        case write = "WRITE"
        case notify = "NOTIFY"
    }
    
    public let timestamp: Date
    public let direction: Direction
    public let dataHex: String
    public let packetType: String?
    public let messageType: String?
    public let opcode: UInt8?
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let opcodeStr = opcode.map { String(format: "0x%02x", $0) } ?? "---"
        let dataPreview = dataHex.count > 32 ? String(dataHex.prefix(32)) + "..." : dataHex
        return "[\(ms)ms] BLE \(direction.rawValue): opcode=\(opcodeStr) \(dataPreview)"
    }
}

// MARK: - Encryption Step Entry

/// Log entry for encryption/pairing steps
public struct DanaEncryptionStep: Codable, Sendable {
    public let timestamp: Date
    public let step: String
    public let encryptionType: String
    public let inputHex: String?
    public let outputHex: String?
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] CRYPTO: \(step) (\(encryptionType))"
    }
}

// MARK: - Session Export (DANA-DIAG-004)

/// Complete session export for fixture capture
public struct DanaSessionExport: Codable, Sendable {
    public let pumpSerial: String
    public let pumpModel: String?
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date?
    public let finalState: DanaSessionState
    public let encryptionType: String?
    public let transitions: [DanaStateTransition]
    public let bleExchanges: [DanaBLEExchange]
    public let encryptionSteps: [DanaEncryptionStep]
    public let errorMessage: String?
    
    public func asJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    public func asText() -> String {
        var lines: [String] = []
        lines.append("Dana Session Log")
        lines.append("================")
        lines.append("Pump Serial: \(pumpSerial)")
        if let model = pumpModel {
            lines.append("Pump Model: \(model)")
        }
        lines.append("Session ID: \(sessionId)")
        lines.append("Started: \(startTime)")
        if let endTime = endTime {
            lines.append("Ended: \(endTime)")
        }
        lines.append("Final State: \(finalState.rawValue)")
        if let encryption = encryptionType {
            lines.append("Encryption: \(encryption)")
        }
        
        if !transitions.isEmpty {
            lines.append("\n--- State Transitions ---")
            transitions.forEach { lines.append($0.formatted) }
        }
        
        if !bleExchanges.isEmpty {
            lines.append("\n--- BLE Exchanges ---")
            bleExchanges.forEach { lines.append($0.formatted) }
        }
        
        if !encryptionSteps.isEmpty {
            lines.append("\n--- Encryption Steps ---")
            encryptionSteps.forEach { lines.append($0.formatted) }
        }
        
        if let error = errorMessage {
            lines.append("\n--- Error ---")
            lines.append(error)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Dana Session Logger (DANA-DIAG-003)

/// Thread-safe session logger for Dana protocol debugging
public final class DanaSessionLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let pumpSerial: String
    private var pumpModel: String?
    private let sessionId: String
    private let startTime: Date
    private var currentState: DanaSessionState = .idle
    private var encryptionType: String?
    private var transitions: [DanaStateTransition] = []
    private var bleExchanges: [DanaBLEExchange] = []
    private var encryptionSteps: [DanaEncryptionStep] = []
    private var errorMessage: String?
    
    /// Create a new Dana session logger
    /// - Parameter pumpSerial: Pump serial number for identification
    public init(pumpSerial: String = "unknown") {
        self.pumpSerial = pumpSerial
        self.sessionId = UUID().uuidString.prefix(8).lowercased()
        self.startTime = Date()
    }
    
    /// Current session state
    public var state: DanaSessionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    /// Set pump model after discovery
    public func setPumpModel(_ model: String) {
        lock.lock()
        defer { lock.unlock() }
        self.pumpModel = model
    }
    
    /// Set encryption type after negotiation
    public func setEncryptionType(_ type: String) {
        lock.lock()
        defer { lock.unlock() }
        self.encryptionType = type
    }
    
    /// Log a state transition (DANA-DIAG-002)
    public func logStateTransition(from: DanaSessionState, to: DanaSessionState, reason: String = "") {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let entry = DanaStateTransition(
            timestamp: Date(),
            fromState: from,
            toState: to,
            reason: reason,
            elapsedMs: elapsed
        )
        transitions.append(entry)
        currentState = to
        
        #if DEBUG
        print("[Dana] \(entry.formatted)")
        #endif
    }
    
    /// Log a BLE exchange
    public func logBLEExchange(direction: DanaBLEExchange.Direction, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        // Parse packet header if present
        var packetType: String? = nil
        var messageType: String? = nil
        var opcode: UInt8? = nil
        
        if data.count >= 6 {
            // Check for Dana packet markers
            if data[0] == 0xA5 && data[1] == 0xA5 {
                packetType = packetTypeName(data[3])
                messageType = messageTypeName(data[4])
                opcode = data[5]
            }
        }
        
        let entry = DanaBLEExchange(
            timestamp: Date(),
            direction: direction,
            dataHex: data.map { String(format: "%02x", $0) }.joined(),
            packetType: packetType,
            messageType: messageType,
            opcode: opcode,
            elapsedMs: elapsed
        )
        bleExchanges.append(entry)
        
        #if DEBUG
        print("[Dana] \(entry.formatted)")
        #endif
    }
    
    /// Log an encryption step
    public func logEncryptionStep(step: String, encryptionType: String, input: Data? = nil, output: Data? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let entry = DanaEncryptionStep(
            timestamp: Date(),
            step: step,
            encryptionType: encryptionType,
            inputHex: input?.map { String(format: "%02x", $0) }.joined(),
            outputHex: output?.map { String(format: "%02x", $0) }.joined(),
            elapsedMs: elapsed
        )
        encryptionSteps.append(entry)
        
        #if DEBUG
        print("[Dana] \(entry.formatted)")
        #endif
    }
    
    /// Log an error condition
    public func logError(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        
        errorMessage = message
        currentState = .error
        
        #if DEBUG
        print("[Dana] ERROR: \(message)")
        #endif
    }
    
    // MARK: - Convenience Methods (PROTO-DANA-DIAG)
    
    /// Convenience: transition to new state
    public func transitionTo(_ newState: DanaSessionState, reason: String = "") {
        logStateTransition(from: currentState, to: newState, reason: reason)
    }
    
    /// Log command sent
    public func logCommandSent(opcode: UInt8, description: String, data: Data) {
        lock.lock()
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        lock.unlock()
        
        logBLEExchange(direction: .write, data: data)
        
        #if DEBUG
        print("[Dana] [\(String(format: "%8.2f", elapsed))ms] CMD TX: \(description) opcode=0x\(String(format: "%02x", opcode))")
        #endif
    }
    
    /// Log command response
    public func logCommandResponse(opcode: UInt8, success: Bool, data: Data) {
        lock.lock()
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        lock.unlock()
        
        logBLEExchange(direction: .notify, data: data)
        
        #if DEBUG
        let status = success ? "✓" : "✗"
        print("[Dana] [\(String(format: "%8.2f", elapsed))ms] CMD RX: opcode=0x\(String(format: "%02x", opcode)) \(status)")
        #endif
    }
    
    /// Log temp basal event
    public func logTempBasal(rate: Double, duration: TimeInterval, isSet: Bool) {
        lock.lock()
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        lock.unlock()
        
        #if DEBUG
        let action = isSet ? "SET" : "CANCEL"
        print("[Dana] [\(String(format: "%8.2f", elapsed))ms] TEMP_BASAL \(action): \(String(format: "%.2f", rate))U/h for \(String(format: "%.0f", duration / 60))min")
        #endif
    }
    
    /// Log bolus delivery
    public func logBolusDelivery(units: Double, success: Bool) {
        lock.lock()
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        lock.unlock()
        
        #if DEBUG
        let status = success ? "✓" : "✗"
        print("[Dana] [\(String(format: "%8.2f", elapsed))ms] BOLUS: \(String(format: "%.2f", units))U \(status)")
        #endif
    }
    
    /// Export the complete session (DANA-DIAG-004)
    public func export() -> DanaSessionExport {
        lock.lock()
        defer { lock.unlock() }
        
        return DanaSessionExport(
            pumpSerial: pumpSerial,
            pumpModel: pumpModel,
            sessionId: sessionId,
            startTime: startTime,
            endTime: Date(),
            finalState: currentState,
            encryptionType: encryptionType,
            transitions: transitions,
            bleExchanges: bleExchanges,
            encryptionSteps: encryptionSteps,
            errorMessage: errorMessage
        )
    }
    
    /// Export session as JSON string (DANA-DIAG-004)
    public func exportJSON() -> String {
        return export().asJSON()
    }
    
    /// Export session as human-readable text
    public func exportText() -> String {
        return export().asText()
    }
    
    /// Clear the session log for reuse
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        transitions.removeAll()
        bleExchanges.removeAll()
        encryptionSteps.removeAll()
        errorMessage = nil
        currentState = .idle
        pumpModel = nil
        encryptionType = nil
    }
    
    // MARK: - Private Helpers
    
    private func packetTypeName(_ value: UInt8) -> String {
        switch value {
        case 0x01: return "EncryptionRequest"
        case 0x02: return "EncryptionResponse"
        case 0xA1: return "Command"
        case 0xB2: return "Response"
        case 0xC3: return "Notify"
        default: return String(format: "0x%02x", value)
        }
    }
    
    private func messageTypeName(_ value: UInt8) -> String {
        switch value {
        case 0xA0: return "Encryption"
        case 0x01: return "General"
        case 0x02: return "Basal"
        case 0x03: return "Bolus"
        case 0x04: return "Option"
        case 0x05: return "ETC"
        case 0x0F: return "Notify"
        default: return String(format: "0x%02x", value)
        }
    }
}
