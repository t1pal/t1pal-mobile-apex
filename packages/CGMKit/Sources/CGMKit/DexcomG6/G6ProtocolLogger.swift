// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G6ProtocolLogger.swift
// CGMKit - DexcomG6
//
// Protocol logger for G6 authentication instrumentation.
// Captures byte-level traces for debugging and evidence collection.
//
// Trace: UNCERT-G6-003

import Foundation
import BLEKit

// MARK: - G6 Protocol Events

/// Events specific to G6 authentication
public enum G6ProtocolEvent: String, Sendable, Codable, CaseIterable {
    // Authentication lifecycle
    case authenticationStarted = "auth.started"
    case authenticationCompleted = "auth.completed"
    case authenticationFailed = "auth.failed"
    
    // Key derivation
    case keyDerivationStarted = "key.derivation_started"
    case keyDerivationCompleted = "key.derivation_completed"
    case keyDerivationFailed = "key.derivation_failed"
    
    // Token exchange
    case tokenGenerated = "token.generated"
    case tokenSent = "token.sent"
    case tokenHashReceived = "token.hash_received"
    case tokenHashVerified = "token.hash_verified"
    case tokenHashFailed = "token.hash_failed"
    
    // Challenge-response
    case challengeReceived = "challenge.received"
    case challengeResponseComputed = "challenge.response_computed"
    case challengeResponseSent = "challenge.response_sent"
    
    // AES operations
    case aesEncryptStarted = "aes.encrypt_started"
    case aesEncryptCompleted = "aes.encrypt_completed"
    case aesEncryptFailed = "aes.encrypt_failed"
    
    // Auth status
    case authStatusReceived = "status.received"
    case authStatusPaired = "status.paired"
    case authStatusBonded = "status.bonded"
    
    // Keep-alive
    case keepAliveSent = "keepalive.sent"
    case keepAliveExpired = "keepalive.expired"
    
    // Transmitter info
    case transmitterTypeDetected = "tx.type_detected"
    case firmwareVersionReceived = "tx.firmware_received"
    case batteryStatusReceived = "tx.battery_received"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .authenticationStarted: return "Authentication started"
        case .authenticationCompleted: return "Authentication completed"
        case .authenticationFailed: return "Authentication failed"
        case .keyDerivationStarted: return "Key derivation started"
        case .keyDerivationCompleted: return "Key derivation completed"
        case .keyDerivationFailed: return "Key derivation failed"
        case .tokenGenerated: return "Random token generated"
        case .tokenSent: return "Auth request with token sent"
        case .tokenHashReceived: return "Token hash received from transmitter"
        case .tokenHashVerified: return "Token hash verified"
        case .tokenHashFailed: return "Token hash verification failed"
        case .challengeReceived: return "Challenge received from transmitter"
        case .challengeResponseComputed: return "Challenge response computed"
        case .challengeResponseSent: return "Challenge response sent"
        case .aesEncryptStarted: return "AES-ECB encryption started"
        case .aesEncryptCompleted: return "AES-ECB encryption completed"
        case .aesEncryptFailed: return "AES-ECB encryption failed"
        case .authStatusReceived: return "Auth status received"
        case .authStatusPaired: return "Transmitter paired"
        case .authStatusBonded: return "Transmitter bonded"
        case .keepAliveSent: return "Keep-alive sent"
        case .keepAliveExpired: return "Keep-alive expired"
        case .transmitterTypeDetected: return "Transmitter type detected"
        case .firmwareVersionReceived: return "Firmware version received"
        case .batteryStatusReceived: return "Battery status received"
        }
    }
    
    /// Category for grouping events
    public var category: G6EventCategory {
        switch self {
        case .authenticationStarted, .authenticationCompleted, .authenticationFailed:
            return .lifecycle
        case .keyDerivationStarted, .keyDerivationCompleted, .keyDerivationFailed:
            return .keyDerivation
        case .tokenGenerated, .tokenSent, .tokenHashReceived, .tokenHashVerified, .tokenHashFailed:
            return .tokenExchange
        case .challengeReceived, .challengeResponseComputed, .challengeResponseSent:
            return .challenge
        case .aesEncryptStarted, .aesEncryptCompleted, .aesEncryptFailed:
            return .crypto
        case .authStatusReceived, .authStatusPaired, .authStatusBonded:
            return .status
        case .keepAliveSent, .keepAliveExpired:
            return .keepAlive
        case .transmitterTypeDetected, .firmwareVersionReceived, .batteryStatusReceived:
            return .transmitterInfo
        }
    }
}

/// Event categories for filtering
public enum G6EventCategory: String, Sendable, Codable, CaseIterable {
    case lifecycle = "lifecycle"
    case keyDerivation = "key_derivation"
    case tokenExchange = "token_exchange"
    case challenge = "challenge"
    case crypto = "crypto"
    case status = "status"
    case keepAlive = "keep_alive"
    case transmitterInfo = "transmitter_info"
}

// MARK: - G6 Protocol Log Entry

/// A single log entry capturing a G6 protocol event
public struct G6ProtocolLogEntry: Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let event: G6ProtocolEvent
    public let transmitterId: String
    public let variantSelection: G6VariantSelection
    public let details: [String: String]
    public let rawBytes: [UInt8]?
    public let isSuccess: Bool
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        event: G6ProtocolEvent,
        transmitterId: String,
        variantSelection: G6VariantSelection,
        details: [String: String] = [:],
        rawBytes: [UInt8]? = nil,
        isSuccess: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.transmitterId = transmitterId
        self.variantSelection = variantSelection
        self.details = details
        self.rawBytes = rawBytes
        self.isSuccess = isSuccess
    }
    
    /// Formatted hex string of raw bytes
    public var rawBytesHex: String? {
        rawBytes?.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Single-line summary
    public var summary: String {
        var s = "[\(event.category.rawValue)] \(event.description)"
        if let hex = rawBytesHex {
            s += " [\(hex.prefix(32))...]"
        }
        return s
    }
}

// MARK: - G6 Protocol Logger

/// Thread-safe protocol logger for G6 authentication
public actor G6ProtocolLogger {
    private var entries: [G6ProtocolLogEntry] = []
    private var currentTransmitterId: String = ""
    private var currentVariant: G6VariantSelection = .loopDefault
    private let maxEntries: Int
    private var sessionId: UUID = UUID()
    
    public init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }
    
    // MARK: - Session Management
    
    /// Start a new logging session for a transmitter
    public func startSession(
        transmitterId: String,
        variant: G6VariantSelection = .loopDefault
    ) {
        sessionId = UUID()
        currentTransmitterId = transmitterId
        currentVariant = variant
        entries.removeAll()
        
        log(
            event: .authenticationStarted,
            details: [
                "sessionId": sessionId.uuidString,
                "keyDerivation": variant.keyDerivation.rawValue,
                "tokenHash": variant.tokenHash.rawValue,
                "authOpcode": variant.authOpcode.rawValue
            ]
        )
    }
    
    /// End the current session
    public func endSession(success: Bool) {
        log(
            event: success ? .authenticationCompleted : .authenticationFailed,
            details: [
                "sessionId": sessionId.uuidString,
                "totalEvents": String(entries.count)
            ],
            isSuccess: success
        )
    }
    
    // MARK: - Event Logging
    
    /// Log a protocol event
    public func log(
        event: G6ProtocolEvent,
        details: [String: String] = [:],
        rawBytes: [UInt8]? = nil,
        isSuccess: Bool = true
    ) {
        let entry = G6ProtocolLogEntry(
            event: event,
            transmitterId: currentTransmitterId,
            variantSelection: currentVariant,
            details: details,
            rawBytes: rawBytes,
            isSuccess: isSuccess
        )
        
        entries.append(entry)
        
        // Trim if over limit
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    /// Log key derivation event
    public func logKeyDerivation(
        transmitterId: String,
        keyBytes: [UInt8],
        variant: G6KeyDerivationVariant
    ) {
        log(
            event: .keyDerivationCompleted,
            details: [
                "transmitterId": transmitterId,
                "keyLength": String(keyBytes.count),
                "variant": variant.rawValue
            ],
            rawBytes: Array(keyBytes.prefix(4)) // Only log first 4 bytes for security
        )
    }
    
    /// Log token generation
    public func logTokenGeneration(token: [UInt8]) {
        log(
            event: .tokenGenerated,
            details: ["tokenLength": String(token.count)],
            rawBytes: token
        )
    }
    
    /// Log token hash verification
    public func logTokenHashVerification(
        expectedHash: [UInt8],
        receivedHash: [UInt8],
        matched: Bool
    ) {
        log(
            event: matched ? .tokenHashVerified : .tokenHashFailed,
            details: [
                "expectedFirst4": expectedHash.prefix(4).map { String(format: "%02X", $0) }.joined(),
                "receivedFirst4": receivedHash.prefix(4).map { String(format: "%02X", $0) }.joined(),
                "matched": String(matched)
            ],
            rawBytes: receivedHash,
            isSuccess: matched
        )
    }
    
    /// Log challenge-response
    public func logChallengeResponse(
        challenge: [UInt8],
        response: [UInt8]
    ) {
        log(
            event: .challengeReceived,
            details: ["challengeLength": String(challenge.count)],
            rawBytes: challenge
        )
        log(
            event: .challengeResponseComputed,
            details: ["responseLength": String(response.count)],
            rawBytes: response
        )
    }
    
    /// Log AES operation
    public func logAESOperation(
        input: [UInt8],
        output: [UInt8]?,
        success: Bool
    ) {
        log(
            event: success ? .aesEncryptCompleted : .aesEncryptFailed,
            details: [
                "inputLength": String(input.count),
                "outputLength": output.map { String($0.count) } ?? "nil"
            ],
            rawBytes: output,
            isSuccess: success
        )
    }
    
    /// Log auth status
    public func logAuthStatus(
        authenticated: Bool,
        bonded: Bool
    ) {
        log(
            event: .authStatusReceived,
            details: [
                "authenticated": String(authenticated),
                "bonded": String(bonded)
            ]
        )
        
        if authenticated {
            log(event: .authStatusPaired)
        }
        if bonded {
            log(event: .authStatusBonded)
        }
    }
    
    /// Log transmitter type detection
    public func logTransmitterType(
        transmitterId: String,
        isFirefly: Bool
    ) {
        log(
            event: .transmitterTypeDetected,
            details: [
                "transmitterId": transmitterId,
                "type": isFirefly ? "G6+ (Firefly)" : "G6 Standard",
                "expectedOpcode": isFirefly ? "0x02" : "0x01"
            ]
        )
    }
    
    // MARK: - Query
    
    /// Get all entries
    public func getEntries() -> [G6ProtocolLogEntry] {
        entries
    }
    
    /// Get entries for a specific category
    public func getEntries(category: G6EventCategory) -> [G6ProtocolLogEntry] {
        entries.filter { $0.event.category == category }
    }
    
    /// Get entries for a specific event
    public func getEntries(event: G6ProtocolEvent) -> [G6ProtocolLogEntry] {
        entries.filter { $0.event == event }
    }
    
    /// Get failed events
    public func getFailedEvents() -> [G6ProtocolLogEntry] {
        entries.filter { !$0.isSuccess }
    }
    
    /// Get current session ID
    public func getCurrentSessionId() -> UUID {
        sessionId
    }
    
    /// Get event count
    public var eventCount: Int {
        entries.count
    }
    
    /// Check if there are any failures
    public var hasFailures: Bool {
        entries.contains { !$0.isSuccess }
    }
    
    /// Clear all entries
    public func clear() {
        entries.removeAll()
    }
    
    // MARK: - Export
    
    /// Export entries as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }
    
    /// Generate text report
    public func generateReport() -> String {
        var lines: [String] = []
        lines.append("=== G6 Protocol Log Report ===")
        lines.append("Session: \(sessionId)")
        lines.append("Transmitter: \(currentTransmitterId)")
        lines.append("Variant: \(currentVariant.id)")
        lines.append("Total Events: \(entries.count)")
        lines.append("Failures: \(entries.filter { !$0.isSuccess }.count)")
        lines.append("")
        lines.append("--- Events ---")
        
        for entry in entries {
            let time = ISO8601DateFormatter().string(from: entry.timestamp)
            let status = entry.isSuccess ? "✓" : "✗"
            lines.append("\(time) \(status) \(entry.summary)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - G6 Authentication Trace

/// Complete trace of a G6 authentication attempt
public struct G6AuthenticationTrace: Sendable, Codable, Identifiable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public let transmitterId: String
    public let variantSelection: G6VariantSelection
    public var events: [G6ProtocolLogEntry]
    public var success: Bool?
    public var errorMessage: String?
    
    public init(
        transmitterId: String,
        variantSelection: G6VariantSelection
    ) {
        self.id = UUID()
        self.startTime = Date()
        self.transmitterId = transmitterId
        self.variantSelection = variantSelection
        self.events = []
    }
    
    /// Duration in seconds
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Add an event to the trace
    public mutating func addEvent(_ entry: G6ProtocolLogEntry) {
        events.append(entry)
    }
    
    /// Complete the trace
    public mutating func complete(success: Bool, error: String? = nil) {
        endTime = Date()
        self.success = success
        errorMessage = error
    }
}
