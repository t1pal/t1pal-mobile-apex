// SPDX-License-Identifier: AGPL-3.0-or-later
//
// X2SessionLogger.swift
// PumpKit
//
// Tandem t:slim X2-specific session logging with BLE state tracking.
// Mirrors Python x2-parse.py verbose logging for cross-platform debugging.
//
// Trace: X2-DIAG-002, X2-DIAG-003, PRD-005
//
// Usage:
//   let logger = X2SessionLogger(pumpSerial: "12345678")
//   logger.logStateTransition(from: .idle, to: .connecting)
//   logger.logBLEExchange(characteristic: .control, direction: .write, data: [...])

import Foundation

// MARK: - X2 Session State (X2-DIAG-002)

/// X2 session state machine states
public enum X2SessionState: String, Codable, Sendable {
    case idle = "IDLE"
    case scanning = "SCANNING"
    case connecting = "CONNECTING"
    case discoveringServices = "DISCOVERING_SERVICES"
    case authorizing = "AUTHORIZING"
    case authorized = "AUTHORIZED"
    case readingStatus = "READING_STATUS"
    case commandPending = "COMMAND_PENDING"
    case commandComplete = "COMMAND_COMPLETE"
    case readingHistory = "READING_HISTORY"
    case tempBasalActive = "TEMP_BASAL_ACTIVE"
    case bolusActive = "BOLUS_ACTIVE"
    case disconnecting = "DISCONNECTING"
    case error = "ERROR"
}

// MARK: - X2 Characteristic

/// BLE characteristic identifiers for X2 protocol
public enum X2Characteristic: String, Codable, Sendable {
    case currentStatus = "CURRENT_STATUS"
    case authorization = "AUTHORIZATION"
    case control = "CONTROL"
    case controlStream = "CONTROL_STREAM"
    case historyLog = "HISTORY_LOG"
    
    /// Full UUID for the characteristic
    public var uuid: String {
        switch self {
        case .currentStatus:
            return "00001818-0000-1000-8000-00805F9B34FB"
        case .authorization:
            return "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
        case .control:
            return "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9"
        case .controlStream:
            return "7B83FFF7-9F77-4E5C-8064-AAE2C24838B9"
        case .historyLog:
            return "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9"
        }
    }
}

// MARK: - State Transition Entry

/// Log entry for state transitions (X2-DIAG-002)
public struct X2StateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: X2SessionState
    public let toState: X2SessionState
    public let reason: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] STATE: \(fromState.rawValue) → \(toState.rawValue) // \(reason)"
    }
}

// MARK: - BLE Exchange Entry

/// Log entry for BLE characteristic exchanges
public struct X2BLEExchange: Codable, Sendable {
    public enum Direction: String, Codable, Sendable {
        case read = "READ"
        case write = "WRITE"
        case notify = "NOTIFY"
    }
    
    public let timestamp: Date
    public let characteristic: X2Characteristic
    public let direction: Direction
    public let dataHex: String
    public let opcode: UInt8?
    public let cargoLen: Int?
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let opcodeStr = opcode.map { String(format: "0x%02x", $0) } ?? "---"
        let dataPreview = dataHex.count > 32 ? String(dataHex.prefix(32)) + "..." : dataHex
        return "[\(ms)ms] BLE \(direction.rawValue): \(characteristic.rawValue) opcode=\(opcodeStr) \(dataPreview)"
    }
}

// MARK: - Message Parse Entry

/// Log entry for parsed X2 messages
public struct X2MessageLog: Codable, Sendable {
    public let timestamp: Date
    public let opcode: UInt8
    public let cargoLen: Int
    public let cargoHex: String
    public let crcValid: Bool
    public let signed: Bool
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let signedStr = signed ? " [SIGNED]" : ""
        let crcStr = crcValid ? "✓" : "✗"
        return "[\(ms)ms] MSG: opcode=0x\(String(format: "%02x", opcode)) cargo=\(cargoLen)b crc=\(crcStr)\(signedStr)"
    }
}

// MARK: - Session Export (X2-DIAG-004)

/// Complete session export for fixture capture
public struct X2SessionExport: Codable, Sendable {
    public let pumpSerial: String
    public let sessionId: String
    public let startTime: Date
    public let endTime: Date?
    public let finalState: X2SessionState
    public let transitions: [X2StateTransition]
    public let bleExchanges: [X2BLEExchange]
    public let messages: [X2MessageLog]
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
        lines.append("X2 Session Log")
        lines.append("==============")
        lines.append("Pump Serial: \(pumpSerial)")
        lines.append("Session ID: \(sessionId)")
        lines.append("Started: \(startTime)")
        if let endTime = endTime {
            lines.append("Ended: \(endTime)")
        }
        lines.append("Final State: \(finalState.rawValue)")
        
        if !transitions.isEmpty {
            lines.append("\n--- State Transitions ---")
            transitions.forEach { lines.append($0.formatted) }
        }
        
        if !bleExchanges.isEmpty {
            lines.append("\n--- BLE Exchanges ---")
            bleExchanges.forEach { lines.append($0.formatted) }
        }
        
        if !messages.isEmpty {
            lines.append("\n--- Messages ---")
            messages.forEach { lines.append($0.formatted) }
        }
        
        if let error = errorMessage {
            lines.append("\n--- Error ---")
            lines.append(error)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - X2 Session Logger (X2-DIAG-003)

/// Thread-safe session logger for X2 protocol debugging
public final class X2SessionLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let pumpSerial: String
    private let sessionId: String
    private let startTime: Date
    private var currentState: X2SessionState = .idle
    private var transitions: [X2StateTransition] = []
    private var bleExchanges: [X2BLEExchange] = []
    private var messages: [X2MessageLog] = []
    private var errorMessage: String?
    
    /// Create a new X2 session logger
    /// - Parameter pumpSerial: Pump serial number for identification
    public init(pumpSerial: String = "unknown") {
        self.pumpSerial = pumpSerial
        self.sessionId = UUID().uuidString.prefix(8).lowercased()
        self.startTime = Date()
    }
    
    /// Current session state
    public var state: X2SessionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    /// Log a state transition (X2-DIAG-002)
    /// - Parameters:
    ///   - from: Previous state
    ///   - to: New state
    ///   - reason: Human-readable reason for transition
    public func logStateTransition(from: X2SessionState, to: X2SessionState, reason: String = "") {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let entry = X2StateTransition(
            timestamp: Date(),
            fromState: from,
            toState: to,
            reason: reason,
            elapsedMs: elapsed
        )
        transitions.append(entry)
        currentState = to
        
        #if DEBUG
        print("[X2] \(entry.formatted)")
        #endif
    }
    
    /// Log a BLE characteristic exchange
    /// - Parameters:
    ///   - characteristic: The BLE characteristic
    ///   - direction: Read/Write/Notify
    ///   - data: Raw data bytes
    public func logBLEExchange(characteristic: X2Characteristic, direction: X2BLEExchange.Direction, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        // Parse opcode and cargo length if data has enough bytes
        var opcode: UInt8? = nil
        var cargoLen: Int? = nil
        if data.count >= 3 {
            opcode = data[0]
            cargoLen = Int(data[1]) | (Int(data[2]) << 8)
        }
        
        let entry = X2BLEExchange(
            timestamp: Date(),
            characteristic: characteristic,
            direction: direction,
            dataHex: data.map { String(format: "%02x", $0) }.joined(),
            opcode: opcode,
            cargoLen: cargoLen,
            elapsedMs: elapsed
        )
        bleExchanges.append(entry)
        
        #if DEBUG
        print("[X2] \(entry.formatted)")
        #endif
    }
    
    /// Log a parsed X2 message
    /// - Parameters:
    ///   - opcode: Message opcode
    ///   - cargo: Cargo data
    ///   - crcValid: Whether CRC validated
    ///   - signed: Whether message is signed
    public func logMessage(opcode: UInt8, cargo: Data, crcValid: Bool, signed: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let entry = X2MessageLog(
            timestamp: Date(),
            opcode: opcode,
            cargoLen: cargo.count,
            cargoHex: cargo.map { String(format: "%02x", $0) }.joined(),
            crcValid: crcValid,
            signed: signed,
            elapsedMs: elapsed
        )
        messages.append(entry)
        
        #if DEBUG
        print("[X2] \(entry.formatted)")
        #endif
    }
    
    /// Log an error condition
    /// - Parameter message: Error description
    public func logError(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        
        errorMessage = message
        currentState = .error
        
        #if DEBUG
        print("[X2] ERROR: \(message)")
        #endif
    }
    
    /// Export the complete session (X2-DIAG-004)
    /// - Returns: Session export for JSON serialization
    public func export() -> X2SessionExport {
        lock.lock()
        defer { lock.unlock() }
        
        return X2SessionExport(
            pumpSerial: pumpSerial,
            sessionId: sessionId,
            startTime: startTime,
            endTime: Date(),
            finalState: currentState,
            transitions: transitions,
            bleExchanges: bleExchanges,
            messages: messages,
            errorMessage: errorMessage
        )
    }
    
    /// Export session as JSON string (X2-DIAG-004)
    /// - Returns: JSON-formatted session data
    public func exportJSON() -> String {
        return export().asJSON()
    }
    
    /// Export session as human-readable text
    /// - Returns: Text-formatted session log
    public func exportText() -> String {
        return export().asText()
    }
    
    /// Clear the session log for reuse
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        transitions.removeAll()
        bleExchanges.removeAll()
        messages.removeAll()
        errorMessage = nil
        currentState = .idle
    }
}
