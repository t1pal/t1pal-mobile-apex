// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosSessionLogger.swift
// PumpKit
//
// Eros-specific session logging with RileyLink RF state tracking.
// Mirrors Python eros-pair.py/eros-scan.py verbose logging for cross-platform debugging.
//
// Trace: EROS-DIAG-002, EROS-DIAG-003, PRD-005
//
// Usage:
//   let logger = ErosSessionLogger(podAddress: 0x1f00ee87)
//   logger.logStateTransition(from: .idle, to: .scanning)
//   logger.logRFExchange(direction: .tx, packet: [...], context: "AssignAddress")

import Foundation

// MARK: - Eros Session State (EROS-DIAG-003)

/// Eros session state machine states (mirrors OmniKit PodCommsSession)
public enum ErosSessionState: String, Codable, Sendable {
    case idle = "IDLE"
    case scanning = "SCANNING"
    case discovered = "DISCOVERED"
    case assigning = "ASSIGNING"
    case assigned = "ASSIGNED"
    case setupPending = "SETUP_PENDING"
    case setupComplete = "SETUP_COMPLETE"
    case priming = "PRIMING"
    case primed = "PRIMED"
    case basalProgrammed = "BASAL_PROGRAMMED"
    case running = "RUNNING"
    case bolusing = "BOLUSING"
    case tempBasal = "TEMP_BASAL"
    case faulted = "FAULTED"
    case deactivating = "DEACTIVATING"
    case error = "ERROR"
}

// MARK: - RF Direction

/// RF packet direction for logging
public enum ErosRFDirection: String, Codable, Sendable {
    case tx = "TX"
    case rx = "RX"
}

// MARK: - State Transition Entry

/// Log entry for state transitions (EROS-DIAG-003)
public struct ErosStateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: ErosSessionState
    public let toState: ErosSessionState
    public let reason: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] STATE: \(fromState.rawValue) → \(toState.rawValue) // \(reason)"
    }
}

// MARK: - RF Exchange Entry (EROS-DIAG-002)

/// Log entry for RF packet exchanges (RileyLink tracing)
public struct ErosRFExchange: Codable, Sendable {
    public let timestamp: Date
    public let direction: ErosRFDirection
    public let packetHex: String
    public let packetLen: Int
    public let context: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let prefix = direction == .tx ? "→" : "←"
        let truncated = packetHex.prefix(48)
        return "[\(ms)ms] RF \(prefix) [\(packetLen) bytes] \(truncated)... // \(context)"
    }
}

// MARK: - Message Block Entry

/// Log entry for parsed message blocks
public struct ErosMessageBlock: Codable, Sendable {
    public let timestamp: Date
    public let blockType: UInt8
    public let blockName: String
    public let payloadHex: String
    public let parsed: [String: String]
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] BLOCK: \(blockName) (0x\(String(format: "%02x", blockType))) = \(parsed)"
    }
}

// MARK: - Eros Session Logger

/// Eros-specific session logger with RF state tracking (EROS-DIAG-003)
public final class ErosSessionLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let startTime: Date
    private let podAddress: UInt32
    
    /// Protocol-level logger (inherited from PumpProtocolLogger)
    public let protocolLogger: PumpProtocolLogger
    
    /// State transitions
    private var stateTransitions: [ErosStateTransition] = []
    
    /// RF exchanges (EROS-DIAG-002)
    private var rfExchanges: [ErosRFExchange] = []
    
    /// Message blocks
    private var messageBlocks: [ErosMessageBlock] = []
    
    /// Current state
    private var currentState: ErosSessionState = .idle
    
    /// Whether logging is enabled
    public var isEnabled: Bool = true
    
    /// Whether verbose console output is enabled
    public var verboseConsole: Bool
    
    /// Initialize with pod address
    public init(podAddress: UInt32, verbose: Bool = false) {
        self.podAddress = podAddress
        self.startTime = Date()
        self.verboseConsole = verbose
        self.protocolLogger = PumpProtocolLogger(
            pumpType: "OmnipodEros",
            pumpId: String(format: "0x%08x", podAddress)
        )
    }
    
    // MARK: - State Tracking (EROS-DIAG-003)
    
    /// Log a state transition
    public func logStateTransition(
        from: ErosSessionState,
        to: ErosSessionState,
        reason: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let transition = ErosStateTransition(
            timestamp: Date(),
            fromState: from,
            toState: to,
            reason: reason,
            elapsedMs: elapsed
        )
        
        stateTransitions.append(transition)
        currentState = to
        
        if verboseConsole {
            print("[ErosSession] \(transition.formatted)")
        }
    }
    
    /// Convenience: transition to new state
    public func transitionTo(_ newState: ErosSessionState, reason: String = "") {
        let oldState = currentState
        logStateTransition(from: oldState, to: newState, reason: reason)
    }
    
    /// Get current state
    public func getCurrentState() -> ErosSessionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    // MARK: - RF Logging (EROS-DIAG-002)
    
    /// Log an RF packet exchange
    public func logRFExchange(
        direction: ErosRFDirection,
        packet: Data,
        context: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = ErosRFExchange(
            timestamp: Date(),
            direction: direction,
            packetHex: packet.hexEncodedString(),
            packetLen: packet.count,
            context: context,
            elapsedMs: elapsed
        )
        
        rfExchanges.append(entry)
        
        if verboseConsole {
            print("[ErosSession] \(entry.formatted)")
        }
        
        // Also log to protocol logger
        if direction == .tx {
            protocolLogger.tx(packet, context: context)
        } else {
            protocolLogger.rx(packet, context: context)
        }
    }
    
    /// Log TX packet
    public func tx(_ packet: Data, context: String = "") {
        logRFExchange(direction: .tx, packet: packet, context: context)
    }
    
    /// Log RX packet
    public func rx(_ packet: Data, context: String = "") {
        logRFExchange(direction: .rx, packet: packet, context: context)
    }
    
    // MARK: - Message Block Logging
    
    /// Log a parsed message block
    public func logMessageBlock(
        blockType: UInt8,
        blockName: String,
        payload: Data,
        parsed: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = ErosMessageBlock(
            timestamp: Date(),
            blockType: blockType,
            blockName: blockName,
            payloadHex: payload.hexEncodedString(),
            parsed: parsed,
            elapsedMs: elapsed
        )
        
        messageBlocks.append(entry)
        
        if verboseConsole {
            print("[ErosSession] \(entry.formatted)")
        }
    }
    
    // MARK: - Convenience Methods for Common Blocks
    
    /// Log AssignAddress command (0x07)
    public func logAssignAddress(newAddress: UInt32, payload: Data) {
        logMessageBlock(
            blockType: 0x07,
            blockName: "AssignAddress",
            payload: payload,
            parsed: ["newAddress": String(format: "0x%08x", newAddress)]
        )
    }
    
    /// Log SetupPod command (0x03)
    public func logSetupPod(address: UInt32, lot: UInt32, tid: UInt32, payload: Data) {
        logMessageBlock(
            blockType: 0x03,
            blockName: "SetupPod",
            payload: payload,
            parsed: [
                "address": String(format: "0x%08x", address),
                "lot": String(lot),
                "tid": String(tid)
            ]
        )
    }
    
    /// Log VersionResponse (0x01)
    public func logVersionResponse(lot: UInt32, tid: UInt32, firmwareVersion: String, payload: Data) {
        logMessageBlock(
            blockType: 0x01,
            blockName: "VersionResponse",
            payload: payload,
            parsed: [
                "lot": String(lot),
                "tid": String(tid),
                "firmwareVersion": firmwareVersion
            ]
        )
    }
    
    // MARK: - Command Logging (PROTO-EROS-DIAG)
    
    /// Log bolus command (0x1a)
    public func logBolusCommand(
        units: Double,
        duration: TimeInterval,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x1a,
            blockName: "Bolus",
            payload: payload,
            parsed: [
                "units": String(format: "%.2f", units),
                "durationSec": String(format: "%.0f", duration)
            ]
        )
        
        if verboseConsole {
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            print("[ErosSession] [\(String(format: "%8.2f", elapsed))ms] BOLUS: \(String(format: "%.2f", units))U over \(String(format: "%.0f", duration))s")
        }
    }
    
    /// Log temp basal command (0x1a with temp flag)
    public func logTempBasalCommand(
        rate: Double,
        duration: TimeInterval,
        isSet: Bool,
        payload: Data
    ) {
        let action = isSet ? "SetTempBasal" : "CancelTempBasal"
        logMessageBlock(
            blockType: 0x1a,
            blockName: action,
            payload: payload,
            parsed: [
                "rate": String(format: "%.2f", rate),
                "durationMin": String(format: "%.0f", duration / 60)
            ]
        )
        
        if verboseConsole {
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            print("[ErosSession] [\(String(format: "%8.2f", elapsed))ms] TEMP_BASAL \(isSet ? "SET" : "CANCEL"): \(String(format: "%.2f", rate))U/h for \(String(format: "%.0f", duration / 60))min")
        }
    }
    
    /// Log cancel delivery command (0x1f)
    public func logCancelDelivery(
        beepType: UInt8,
        deliveryTypes: UInt8,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x1f,
            blockName: "CancelDelivery",
            payload: payload,
            parsed: [
                "beepType": String(format: "0x%02x", beepType),
                "deliveryTypes": String(format: "0x%02x", deliveryTypes)
            ]
        )
    }
    
    /// Log acknowledge alerts command (0x11)
    public func logAcknowledgeAlerts(
        alertMask: UInt8,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x11,
            blockName: "AcknowledgeAlerts",
            payload: payload,
            parsed: ["alertMask": String(format: "0x%02x", alertMask)]
        )
    }
    
    /// Log get status command (0x0e)
    public func logGetStatus(
        statusType: UInt8,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x0e,
            blockName: "GetStatus",
            payload: payload,
            parsed: ["statusType": String(format: "0x%02x", statusType)]
        )
    }
    
    /// Log status response (0x1d)
    public func logStatusResponse(
        deliveryStatus: UInt8,
        reservoir: Double,
        unackedAlerts: UInt8,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x1d,
            blockName: "StatusResponse",
            payload: payload,
            parsed: [
                "deliveryStatus": String(format: "0x%02x", deliveryStatus),
                "reservoir": String(format: "%.1f", reservoir),
                "unackedAlerts": String(format: "0x%02x", unackedAlerts)
            ]
        )
    }
    
    /// Log deactivate pod command (0x1c)
    public func logDeactivatePod(payload: Data) {
        logMessageBlock(
            blockType: 0x1c,
            blockName: "DeactivatePod",
            payload: payload,
            parsed: [:]
        )
    }
    
    /// Log basal schedule command (0x13)
    public func logBasalSchedule(
        scheduleEntries: Int,
        payload: Data
    ) {
        logMessageBlock(
            blockType: 0x13,
            blockName: "BasalSchedule",
            payload: payload,
            parsed: ["entries": String(scheduleEntries)]
        )
    }
    
    // MARK: - Export
    
    /// Export complete session for analysis
    public func exportSession() -> ErosSessionExport {
        lock.lock()
        defer { lock.unlock() }
        
        return ErosSessionExport(
            podAddress: String(format: "0x%08x", podAddress),
            startTime: startTime,
            endTime: Date(),
            stateTransitions: stateTransitions,
            rfExchanges: rfExchanges,
            messageBlocks: messageBlocks,
            protocolEntries: protocolLogger.getEntries()
        )
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        stateTransitions.removeAll()
        rfExchanges.removeAll()
        messageBlocks.removeAll()
        protocolLogger.clear()
    }
}

// MARK: - Session Export

/// Complete Eros session export (EROS-DIAG-004)
public struct ErosSessionExport: Codable, Sendable {
    public let podAddress: String
    public let startTime: Date
    public let endTime: Date
    public let stateTransitions: [ErosStateTransition]
    public let rfExchanges: [ErosRFExchange]
    public let messageBlocks: [ErosMessageBlock]
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
        lines.append("=== Eros Session Export ===")
        lines.append("Pod Address: \(podAddress)")
        lines.append("Started: \(ISO8601DateFormatter().string(from: startTime))")
        lines.append("Ended: \(ISO8601DateFormatter().string(from: endTime))")
        lines.append("")
        
        lines.append("--- State Transitions (\(stateTransitions.count)) ---")
        for t in stateTransitions {
            lines.append(t.formatted)
        }
        lines.append("")
        
        lines.append("--- RF Exchanges (\(rfExchanges.count)) ---")
        for rf in rfExchanges {
            lines.append(rf.formatted)
        }
        lines.append("")
        
        lines.append("--- Message Blocks (\(messageBlocks.count)) ---")
        for mb in messageBlocks {
            lines.append(mb.formatted)
        }
        lines.append("")
        
        lines.append("--- Protocol Log (\(protocolEntries.count)) ---")
        for p in protocolEntries {
            lines.append("\(p.direction.rawValue): \(p.hexString)")
        }
        
        return lines.joined(separator: "\n")
    }
}
