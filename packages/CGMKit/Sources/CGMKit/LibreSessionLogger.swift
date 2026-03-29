// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LibreSessionLogger.swift
// CGMKit
//
// Libre-specific session logging with NFC/BLE state tracking.
// Mirrors Python libre-*.py verbose logging for cross-platform debugging.
//
// Trace: LIBRE-DIAG-001, LIBRE-DIAG-003, PRD-003
//
// Usage:
//   let logger = LibreSessionLogger(sensorId: "E007...")
//   logger.logStateTransition(from: .idle, to: .nfcScanning)
//   logger.logNFCRead(block: 0, data: [...])
//   logger.logBLENotification(characteristic: "F001", data: [...])

import Foundation

// MARK: - Libre Session State (LIBRE-DIAG-003)

/// Libre session state machine states
public enum LibreSessionState: String, Codable, Sendable {
    case idle = "IDLE"
    case nfcScanning = "NFC_SCANNING"
    case nfcReading = "NFC_READING"
    case nfcDecrypting = "NFC_DECRYPTING"
    case nfcComplete = "NFC_COMPLETE"
    case bleConnecting = "BLE_CONNECTING"
    case bleDiscovering = "BLE_DISCOVERING"
    case bleUnlocking = "BLE_UNLOCKING"
    case bleStreaming = "BLE_STREAMING"
    case bleDisconnected = "BLE_DISCONNECTED"
    case sensorWarmup = "SENSOR_WARMUP"
    case sensorActive = "SENSOR_ACTIVE"
    case sensorExpired = "SENSOR_EXPIRED"
    case error = "ERROR"
}

// MARK: - NFC Read Entry (LIBRE-DIAG-002)

/// Log entry for NFC FRAM block reads
public struct LibreNFCRead: Codable, Sendable {
    public let timestamp: Date
    public let blockNumber: Int
    public let blockData: String  // hex
    public let blockLen: Int
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] NFC READ block[\(blockNumber)]: \(blockData)"
    }
}

// MARK: - BLE Notification Entry

/// Log entry for BLE characteristic notifications
public struct LibreBLENotification: Codable, Sendable {
    public let timestamp: Date
    public let characteristic: String
    public let dataHex: String
    public let dataLen: Int
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        let truncated = dataHex.prefix(32)
        return "[\(ms)ms] BLE ← \(characteristic) [\(dataLen) bytes]: \(truncated)..."
    }
}

// MARK: - State Transition Entry

/// Log entry for state transitions
public struct LibreStateTransition: Codable, Sendable {
    public let timestamp: Date
    public let fromState: LibreSessionState
    public let toState: LibreSessionState
    public let reason: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] STATE: \(fromState.rawValue) → \(toState.rawValue) // \(reason)"
    }
}

// MARK: - Crypto Step Entry

/// Log entry for cryptographic operations
public struct LibreCryptoStep: Codable, Sendable {
    public let timestamp: Date
    public let operation: String  // e.g., "DecryptFRAM", "DecryptBLE", "StreamingUnlock"
    public let inputHex: String
    public let outputHex: String
    public let notes: String
    public let elapsedMs: Double
    
    public var formatted: String {
        let ms = String(format: "%8.2f", elapsedMs)
        return "[\(ms)ms] CRYPTO \(operation): \(inputHex.prefix(24))... → \(outputHex.prefix(24))... // \(notes)"
    }
}

// MARK: - Libre Session Logger

/// Libre-specific session logger with NFC/BLE state tracking (LIBRE-DIAG-003)
public final class LibreSessionLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let startTime: Date
    private let sensorId: String
    
    /// State transitions
    private var stateTransitions: [LibreStateTransition] = []
    
    /// NFC reads
    private var nfcReads: [LibreNFCRead] = []
    
    /// BLE notifications
    private var bleNotifications: [LibreBLENotification] = []
    
    /// Crypto steps
    private var cryptoSteps: [LibreCryptoStep] = []
    
    /// Current state
    private var currentState: LibreSessionState = .idle
    
    /// Whether logging is enabled
    public var isEnabled: Bool = true
    
    /// Whether verbose console output is enabled
    public var verboseConsole: Bool
    
    /// Initialize with sensor ID
    public init(sensorId: String, verbose: Bool = false) {
        self.sensorId = sensorId
        self.startTime = Date()
        self.verboseConsole = verbose
    }
    
    // MARK: - State Tracking
    
    /// Log a state transition
    public func logStateTransition(
        from: LibreSessionState,
        to: LibreSessionState,
        reason: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let transition = LibreStateTransition(
            timestamp: Date(),
            fromState: from,
            toState: to,
            reason: reason,
            elapsedMs: elapsed
        )
        
        stateTransitions.append(transition)
        currentState = to
        
        if verboseConsole {
            print("[LibreSession] \(transition.formatted)")
        }
    }
    
    /// Convenience: transition to new state
    public func transitionTo(_ newState: LibreSessionState, reason: String = "") {
        let oldState = currentState
        logStateTransition(from: oldState, to: newState, reason: reason)
    }
    
    /// Get current state
    public func getCurrentState() -> LibreSessionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }
    
    // MARK: - NFC Logging (LIBRE-DIAG-002)
    
    /// Log an NFC block read
    public func logNFCRead(block: Int, data: Data) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = LibreNFCRead(
            timestamp: Date(),
            blockNumber: block,
            blockData: data.hexEncodedString(),
            blockLen: data.count,
            elapsedMs: elapsed
        )
        
        nfcReads.append(entry)
        
        if verboseConsole {
            print("[LibreSession] \(entry.formatted)")
        }
    }
    
    /// Log a complete FRAM read (all 43 blocks)
    public func logFRAMRead(fram: Data) {
        guard isEnabled else { return }
        
        let blockSize = 8
        let blockCount = fram.count / blockSize
        
        for i in 0..<blockCount {
            let start = i * blockSize
            let end = min(start + blockSize, fram.count)
            let blockData = fram[start..<end]
            logNFCRead(block: i, data: Data(blockData))
        }
    }
    
    // MARK: - BLE Logging
    
    /// Log a BLE notification
    public func logBLENotification(characteristic: String, data: Data) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = LibreBLENotification(
            timestamp: Date(),
            characteristic: characteristic,
            dataHex: data.hexEncodedString(),
            dataLen: data.count,
            elapsedMs: elapsed
        )
        
        bleNotifications.append(entry)
        
        if verboseConsole {
            print("[LibreSession] \(entry.formatted)")
        }
    }
    
    /// Log BLE write
    public func logBLEWrite(characteristic: String, data: Data) {
        guard isEnabled else { return }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        if verboseConsole {
            let ms = String(format: "%8.2f", elapsed)
            print("[LibreSession] [\(ms)ms] BLE → \(characteristic) [\(data.count) bytes]: \(data.hexEncodedString().prefix(32))...")
        }
    }
    
    // MARK: - Crypto Logging
    
    /// Log a cryptographic operation
    public func logCryptoStep(
        operation: String,
        input: Data,
        output: Data,
        notes: String = ""
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        
        let entry = LibreCryptoStep(
            timestamp: Date(),
            operation: operation,
            inputHex: input.hexEncodedString(),
            outputHex: output.hexEncodedString(),
            notes: notes,
            elapsedMs: elapsed
        )
        
        cryptoSteps.append(entry)
        
        if verboseConsole {
            print("[LibreSession] \(entry.formatted)")
        }
    }
    
    /// Log FRAM decryption
    public func logFRAMDecrypt(encrypted: Data, decrypted: Data) {
        logCryptoStep(
            operation: "DecryptFRAM",
            input: encrypted,
            output: decrypted,
            notes: "libre2 FRAM"
        )
    }
    
    /// Log BLE glucose decryption
    public func logBLEDecrypt(encrypted: Data, decrypted: Data) {
        logCryptoStep(
            operation: "DecryptBLE",
            input: encrypted,
            output: decrypted,
            notes: "glucose notification"
        )
    }
    
    /// Log streaming unlock generation
    public func logUnlockPayload(sensorUid: Data, payload: Data) {
        logCryptoStep(
            operation: "StreamingUnlock",
            input: sensorUid,
            output: payload,
            notes: "write to F002"
        )
    }
    
    // MARK: - Export
    
    /// Export complete session for analysis
    public func exportSession() -> LibreSessionExport {
        lock.lock()
        defer { lock.unlock() }
        
        return LibreSessionExport(
            sensorId: sensorId,
            startTime: startTime,
            endTime: Date(),
            stateTransitions: stateTransitions,
            nfcReads: nfcReads,
            bleNotifications: bleNotifications,
            cryptoSteps: cryptoSteps
        )
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        stateTransitions.removeAll()
        nfcReads.removeAll()
        bleNotifications.removeAll()
        cryptoSteps.removeAll()
    }
}

// MARK: - Session Export (LIBRE-DIAG-004)

/// Complete Libre session export
public struct LibreSessionExport: Codable, Sendable {
    public let sensorId: String
    public let startTime: Date
    public let endTime: Date
    public let stateTransitions: [LibreStateTransition]
    public let nfcReads: [LibreNFCRead]
    public let bleNotifications: [LibreBLENotification]
    public let cryptoSteps: [LibreCryptoStep]
    
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
        lines.append("=== Libre Session Export ===")
        lines.append("Sensor ID: \(sensorId)")
        lines.append("Started: \(ISO8601DateFormatter().string(from: startTime))")
        lines.append("Ended: \(ISO8601DateFormatter().string(from: endTime))")
        lines.append("")
        
        lines.append("--- State Transitions (\(stateTransitions.count)) ---")
        for t in stateTransitions {
            lines.append(t.formatted)
        }
        lines.append("")
        
        lines.append("--- NFC Reads (\(nfcReads.count)) ---")
        for nfc in nfcReads {
            lines.append(nfc.formatted)
        }
        lines.append("")
        
        lines.append("--- BLE Notifications (\(bleNotifications.count)) ---")
        for ble in bleNotifications {
            lines.append(ble.formatted)
        }
        lines.append("")
        
        lines.append("--- Crypto Steps (\(cryptoSteps.count)) ---")
        for c in cryptoSteps {
            lines.append(c.formatted)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Internal Data Extension

fileprivate extension Data {
    /// Convert data to hex string (internal to this file)
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
