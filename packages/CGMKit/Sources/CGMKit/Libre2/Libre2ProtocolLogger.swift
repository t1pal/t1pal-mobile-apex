// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// Libre2ProtocolLogger.swift
// CGMKit - Libre2
//
// Protocol logger for Libre 2 authentication instrumentation.
// Captures byte-level traces for debugging and evidence collection.
//
// Trace: UNCERT-L2-003

import Foundation
import BLEKit

// MARK: - Libre 2 Protocol Events

/// Events specific to Libre 2 authentication and data handling
public enum Libre2ProtocolEvent: String, Sendable, Codable, CaseIterable {
    // Sensor lifecycle
    case sensorDiscovered = "sensor.discovered"
    case sensorConnected = "sensor.connected"
    case sensorDisconnected = "sensor.disconnected"
    case sensorTypeDetected = "sensor.type_detected"
    
    // NFC operations
    case nfcSessionStarted = "nfc.session_started"
    case nfcSessionEnded = "nfc.session_ended"
    case nfcPatchInfoRead = "nfc.patch_info_read"
    case nfcFRAMReadStarted = "nfc.fram_read_started"
    case nfcFRAMReadCompleted = "nfc.fram_read_completed"
    case nfcFRAMReadFailed = "nfc.fram_read_failed"
    case nfcCommandSent = "nfc.command_sent"
    case nfcResponseReceived = "nfc.response_received"
    
    // BLE unlock
    case bleUnlockPayloadComputed = "ble.unlock_payload_computed"
    case bleUnlockSent = "ble.unlock_sent"
    case bleUnlockSuccess = "ble.unlock_success"
    case bleUnlockFailed = "ble.unlock_failed"
    
    // FRAM decryption
    case framDecryptionStarted = "fram.decrypt_started"
    case framDecryptionCompleted = "fram.decrypt_completed"
    case framDecryptionFailed = "fram.decrypt_failed"
    case framBlockDecrypted = "fram.block_decrypted"
    
    // Crypto operations
    case keyStreamGenerated = "crypto.keystream_generated"
    case xorApplied = "crypto.xor_applied"
    case crcValidated = "crypto.crc_validated"
    case crcFailed = "crypto.crc_failed"
    
    // BLE data streaming
    case bleDataReceived = "ble.data_received"
    case bleDataDecrypted = "ble.data_decrypted"
    case bleDataParsed = "ble.data_parsed"
    
    // Glucose processing
    case glucoseValueExtracted = "glucose.extracted"
    case glucoseValueCalibrated = "glucose.calibrated"
    case glucoseTrendCalculated = "glucose.trend_calculated"
    
    // Enable time / counter
    case enableTimeExtracted = "time.enable_extracted"
    case unlockCounterIncremented = "time.counter_incremented"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .sensorDiscovered: return "Sensor discovered"
        case .sensorConnected: return "Sensor connected"
        case .sensorDisconnected: return "Sensor disconnected"
        case .sensorTypeDetected: return "Sensor type detected"
        case .nfcSessionStarted: return "NFC session started"
        case .nfcSessionEnded: return "NFC session ended"
        case .nfcPatchInfoRead: return "Patch info read via NFC"
        case .nfcFRAMReadStarted: return "FRAM read started"
        case .nfcFRAMReadCompleted: return "FRAM read completed (344 bytes)"
        case .nfcFRAMReadFailed: return "FRAM read failed"
        case .nfcCommandSent: return "NFC command sent"
        case .nfcResponseReceived: return "NFC response received"
        case .bleUnlockPayloadComputed: return "Unlock payload computed"
        case .bleUnlockSent: return "Unlock command sent"
        case .bleUnlockSuccess: return "Unlock successful - streaming enabled"
        case .bleUnlockFailed: return "Unlock failed"
        case .framDecryptionStarted: return "FRAM decryption started"
        case .framDecryptionCompleted: return "FRAM decryption completed"
        case .framDecryptionFailed: return "FRAM decryption failed"
        case .framBlockDecrypted: return "FRAM block decrypted"
        case .keyStreamGenerated: return "Keystream generated (64 bytes)"
        case .xorApplied: return "XOR cipher applied"
        case .crcValidated: return "CRC16 validated"
        case .crcFailed: return "CRC16 validation failed"
        case .bleDataReceived: return "BLE data packet received"
        case .bleDataDecrypted: return "BLE data decrypted"
        case .bleDataParsed: return "BLE data parsed"
        case .glucoseValueExtracted: return "Raw glucose extracted"
        case .glucoseValueCalibrated: return "Glucose calibrated (÷8.5)"
        case .glucoseTrendCalculated: return "Trend calculated"
        case .enableTimeExtracted: return "Enable time extracted from FRAM"
        case .unlockCounterIncremented: return "Unlock counter incremented"
        }
    }
    
    /// Category for grouping events
    public var category: Libre2EventCategory {
        switch self {
        case .sensorDiscovered, .sensorConnected, .sensorDisconnected, .sensorTypeDetected:
            return .lifecycle
        case .nfcSessionStarted, .nfcSessionEnded, .nfcPatchInfoRead,
             .nfcFRAMReadStarted, .nfcFRAMReadCompleted, .nfcFRAMReadFailed,
             .nfcCommandSent, .nfcResponseReceived:
            return .nfc
        case .bleUnlockPayloadComputed, .bleUnlockSent, .bleUnlockSuccess, .bleUnlockFailed:
            return .bleUnlock
        case .framDecryptionStarted, .framDecryptionCompleted, .framDecryptionFailed, .framBlockDecrypted:
            return .framDecryption
        case .keyStreamGenerated, .xorApplied, .crcValidated, .crcFailed:
            return .crypto
        case .bleDataReceived, .bleDataDecrypted, .bleDataParsed:
            return .bleData
        case .glucoseValueExtracted, .glucoseValueCalibrated, .glucoseTrendCalculated:
            return .glucose
        case .enableTimeExtracted, .unlockCounterIncremented:
            return .timing
        }
    }
}

/// Categories for Libre 2 protocol events
public enum Libre2EventCategory: String, Sendable, Codable, CaseIterable {
    case lifecycle = "lifecycle"
    case nfc = "nfc"
    case bleUnlock = "ble_unlock"
    case framDecryption = "fram_decryption"
    case crypto = "crypto"
    case bleData = "ble_data"
    case glucose = "glucose"
    case timing = "timing"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .lifecycle: return "Sensor Lifecycle"
        case .nfc: return "NFC Operations"
        case .bleUnlock: return "BLE Unlock"
        case .framDecryption: return "FRAM Decryption"
        case .crypto: return "Crypto Operations"
        case .bleData: return "BLE Data Streaming"
        case .glucose: return "Glucose Processing"
        case .timing: return "Timing / Counter"
        }
    }
}

// MARK: - Log Entry

/// A single log entry for Libre 2 protocol events
public struct Libre2ProtocolLogEntry: Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let event: Libre2ProtocolEvent
    public let sensorUID: Data?
    public let variantSelection: Libre2VariantSelection?
    public let rawBytes: Data?
    public let computedBytes: Data?
    public let expectedBytes: Data?
    public let message: String?
    public let error: String?
    public let metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        event: Libre2ProtocolEvent,
        sensorUID: Data? = nil,
        variantSelection: Libre2VariantSelection? = nil,
        rawBytes: Data? = nil,
        computedBytes: Data? = nil,
        expectedBytes: Data? = nil,
        message: String? = nil,
        error: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.sensorUID = sensorUID
        self.variantSelection = variantSelection
        self.rawBytes = rawBytes
        self.computedBytes = computedBytes
        self.expectedBytes = expectedBytes
        self.message = message
        self.error = error
        self.metadata = metadata
    }
    
    /// Category for this entry
    public var category: Libre2EventCategory {
        event.category
    }
    
    /// Whether this entry indicates a failure
    public var isFailure: Bool {
        event.rawValue.hasSuffix("failed") || error != nil
    }
    
    /// Whether this entry indicates success
    public var isSuccess: Bool {
        event.rawValue.hasSuffix("completed") ||
        event.rawValue.hasSuffix("success") ||
        event.rawValue.hasSuffix("validated")
    }
    
    /// Format for display
    public var formattedMessage: String {
        var parts: [String] = [event.description]
        if let msg = message {
            parts.append(msg)
        }
        if let err = error {
            parts.append("Error: \(err)")
        }
        return parts.joined(separator: " - ")
    }
}

// MARK: - Protocol Logger Actor

/// Actor for thread-safe Libre 2 protocol logging
public actor Libre2ProtocolLogger {
    /// Maximum entries to keep
    private let maxEntries: Int
    
    /// Log entries
    private var entries: [Libre2ProtocolLogEntry] = []
    
    /// Current sensor UID for context
    private var currentSensorUID: Data?
    
    /// Current variant selection
    private var currentVariant: Libre2VariantSelection?
    
    /// Enable logging
    public var isEnabled: Bool = true
    
    /// Create a new logger
    public init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }
    
    // MARK: - Configuration
    
    /// Set the current sensor UID for subsequent logs
    public func setSensorUID(_ uid: Data) {
        self.currentSensorUID = uid
    }
    
    /// Set the current variant selection
    public func setVariant(_ variant: Libre2VariantSelection) {
        self.currentVariant = variant
    }
    
    /// Clear the current context
    public func clearContext() {
        self.currentSensorUID = nil
        self.currentVariant = nil
    }
    
    // MARK: - Logging
    
    /// Log a protocol event
    public func log(
        _ event: Libre2ProtocolEvent,
        rawBytes: Data? = nil,
        computedBytes: Data? = nil,
        expectedBytes: Data? = nil,
        message: String? = nil,
        error: String? = nil,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        
        let entry = Libre2ProtocolLogEntry(
            event: event,
            sensorUID: currentSensorUID,
            variantSelection: currentVariant,
            rawBytes: rawBytes,
            computedBytes: computedBytes,
            expectedBytes: expectedBytes,
            message: message,
            error: error,
            metadata: metadata
        )
        
        entries.append(entry)
        trimIfNeeded()
    }
    
    /// Log a sensor lifecycle event
    public func logSensorLifecycle(
        _ event: Libre2ProtocolEvent,
        sensorUID: Data? = nil,
        sensorType: String? = nil
    ) {
        var metadata: [String: String] = [:]
        if let type = sensorType {
            metadata["sensorType"] = type
        }
        if let uid = sensorUID {
            metadata["sensorUID"] = uid.hexString
            setSensorUID(uid)
        }
        log(event, metadata: metadata)
    }
    
    /// Log NFC operation
    public func logNFC(
        _ event: Libre2ProtocolEvent,
        command: Data? = nil,
        response: Data? = nil,
        message: String? = nil,
        error: String? = nil
    ) {
        log(
            event,
            rawBytes: command,
            computedBytes: response,
            message: message,
            error: error
        )
    }
    
    /// Log FRAM decryption
    public func logFRAMDecryption(
        encryptedFRAM: Data? = nil,
        decryptedFRAM: Data? = nil,
        blockIndex: Int? = nil,
        xorConstant: UInt8? = nil,
        success: Bool,
        error: String? = nil
    ) {
        var metadata: [String: String] = [:]
        if let block = blockIndex {
            metadata["blockIndex"] = String(block)
        }
        if let xor = xorConstant {
            metadata["xorConstant"] = String(format: "0x%02X", xor)
        }
        
        log(
            success ? .framBlockDecrypted : .framDecryptionFailed,
            rawBytes: encryptedFRAM,
            computedBytes: decryptedFRAM,
            error: error,
            metadata: metadata
        )
    }
    
    /// Log BLE unlock attempt
    public func logUnlock(
        enableTime: UInt32,
        unlockCount: Int,
        payload: Data,
        success: Bool,
        error: String? = nil
    ) {
        let metadata: [String: String] = [
            "enableTime": String(enableTime),
            "unlockCount": String(unlockCount)
        ]
        
        log(
            success ? .bleUnlockSuccess : .bleUnlockFailed,
            computedBytes: payload,
            error: error,
            metadata: metadata
        )
    }
    
    /// Log crypto keystream generation
    public func logKeystream(
        sensorUID: Data,
        keystream: Data,
        variant: Libre2CryptoConstantVariant
    ) {
        let metadata: [String: String] = [
            "variant": variant.rawValue,
            "keystreamLength": String(keystream.count)
        ]
        log(
            .keyStreamGenerated,
            rawBytes: sensorUID,
            computedBytes: keystream,
            metadata: metadata
        )
    }
    
    /// Log CRC validation
    public func logCRC(
        data: Data,
        computedCRC: UInt16,
        expectedCRC: UInt16,
        success: Bool
    ) {
        let metadata: [String: String] = [
            "computedCRC": String(format: "0x%04X", computedCRC),
            "expectedCRC": String(format: "0x%04X", expectedCRC)
        ]
        log(
            success ? .crcValidated : .crcFailed,
            rawBytes: data,
            metadata: metadata
        )
    }
    
    /// Log glucose value extraction and calibration
    public func logGlucose(
        rawValue: UInt16,
        calibratedValue: Double,
        calibrationFactor: Double,
        trend: String? = nil
    ) {
        let metadata: [String: String] = [
            "rawValue": String(rawValue),
            "calibratedValue": String(format: "%.1f", calibratedValue),
            "calibrationFactor": String(calibrationFactor)
        ]
        log(
            .glucoseValueCalibrated,
            message: trend.map { "Trend: \($0)" },
            metadata: metadata
        )
    }
    
    /// Log enable time extraction
    public func logEnableTime(
        enableTime: UInt32,
        framOffset: Int,
        unlockCount: Int
    ) {
        let metadata: [String: String] = [
            "enableTime": String(enableTime),
            "framOffset": String(framOffset),
            "unlockCount": String(unlockCount)
        ]
        log(.enableTimeExtracted, metadata: metadata)
    }
    
    // MARK: - Query
    
    /// Get all entries
    public func getAllEntries() -> [Libre2ProtocolLogEntry] {
        entries
    }
    
    /// Get entries for a specific event
    public func entries(for event: Libre2ProtocolEvent) -> [Libre2ProtocolLogEntry] {
        entries.filter { $0.event == event }
    }
    
    /// Get entries for a category
    public func entries(forCategory category: Libre2EventCategory) -> [Libre2ProtocolLogEntry] {
        entries.filter { $0.category == category }
    }
    
    /// Get failure entries
    public func failures() -> [Libre2ProtocolLogEntry] {
        entries.filter { $0.isFailure }
    }
    
    /// Get success entries
    public func successes() -> [Libre2ProtocolLogEntry] {
        entries.filter { $0.isSuccess }
    }
    
    /// Get entries since a date
    public func entries(since date: Date) -> [Libre2ProtocolLogEntry] {
        entries.filter { $0.timestamp >= date }
    }
    
    /// Get the last N entries
    public func lastEntries(_ count: Int) -> [Libre2ProtocolLogEntry] {
        Array(entries.suffix(count))
    }
    
    /// Count entries by event
    public func countByEvent() -> [Libre2ProtocolEvent: Int] {
        var counts: [Libre2ProtocolEvent: Int] = [:]
        for entry in entries {
            counts[entry.event, default: 0] += 1
        }
        return counts
    }
    
    /// Count entries by category
    public func countByCategory() -> [Libre2EventCategory: Int] {
        var counts: [Libre2EventCategory: Int] = [:]
        for entry in entries {
            counts[entry.category, default: 0] += 1
        }
        return counts
    }
    
    /// Clear all entries
    public func clear() {
        entries.removeAll()
    }
    
    // MARK: - Export
    
    /// Export entries as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
    
    /// Export a summary report
    public func exportSummary() -> Libre2LoggerSummary {
        Libre2LoggerSummary(
            totalEntries: entries.count,
            failureCount: entries.filter { $0.isFailure }.count,
            successCount: entries.filter { $0.isSuccess }.count,
            firstEntry: entries.first?.timestamp,
            lastEntry: entries.last?.timestamp,
            countByCategory: countByCategory(),
            countByEvent: countByEvent(),
            currentSensorUID: currentSensorUID?.hexString,
            currentVariant: currentVariant?.id
        )
    }
    
    // MARK: - Private
    
    private func trimIfNeeded() {
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

// MARK: - Summary

/// Summary of Libre 2 protocol logs
public struct Libre2LoggerSummary: Sendable, Codable {
    public let totalEntries: Int
    public let failureCount: Int
    public let successCount: Int
    public let firstEntry: Date?
    public let lastEntry: Date?
    public let countByCategory: [Libre2EventCategory: Int]
    public let countByEvent: [Libre2ProtocolEvent: Int]
    public let currentSensorUID: String?
    public let currentVariant: String?
    
    /// Success rate as a percentage
    public var successRate: Double {
        let total = successCount + failureCount
        guard total > 0 else { return 0 }
        return Double(successCount) / Double(total) * 100.0
    }
}

// MARK: - Data Extension

extension Data {
    /// Hex string representation
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
