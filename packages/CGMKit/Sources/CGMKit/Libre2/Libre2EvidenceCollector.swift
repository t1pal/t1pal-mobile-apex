// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// Libre2EvidenceCollector.swift
// CGMKit - Libre2
//
// Evidence collector for Libre 2 authentication and data collection attempts.
// Tracks phase-by-phase success/failure and generates structured reports.
//
// Trace: UNCERT-L2-004

import Foundation
import BLEKit

// MARK: - Libre 2 Phase Result

/// Result of a single Libre 2 operation phase
public struct Libre2PhaseResult: Sendable, Codable, Equatable {
    public let phase: Libre2Phase
    public let success: Bool
    public let startTime: Date
    public let endTime: Date
    public let errorCode: String?
    public let errorMessage: String?
    public let metadata: [String: String]
    
    public var durationMs: Double {
        endTime.timeIntervalSince(startTime) * 1000.0
    }
    
    public init(
        phase: Libre2Phase,
        success: Bool,
        startTime: Date,
        endTime: Date = Date(),
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.phase = phase
        self.success = success
        self.startTime = startTime
        self.endTime = endTime
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
    
    public static func success(phase: Libre2Phase, startTime: Date, metadata: [String: String] = [:]) -> Libre2PhaseResult {
        Libre2PhaseResult(phase: phase, success: true, startTime: startTime, metadata: metadata)
    }
    
    public static func failure(phase: Libre2Phase, startTime: Date, error: String, code: String? = nil) -> Libre2PhaseResult {
        Libre2PhaseResult(phase: phase, success: false, startTime: startTime, errorCode: code, errorMessage: error)
    }
}

/// Libre 2 operation phases
public enum Libre2Phase: String, Sendable, Codable, CaseIterable {
    case nfcActivation = "nfc_activation"
    case patchInfoRead = "patch_info_read"
    case sensorTypeDetection = "sensor_type_detection"
    case framRead = "fram_read"
    case framDecryption = "fram_decryption"
    case crcValidation = "crc_validation"
    case enableTimeExtraction = "enable_time_extraction"
    case bleUnlock = "ble_unlock"
    case bleStreaming = "ble_streaming"
    case glucoseExtraction = "glucose_extraction"
    case glucoseCalibration = "glucose_calibration"
    
    public var description: String {
        switch self {
        case .nfcActivation: return "NFC Activation"
        case .patchInfoRead: return "Patch Info Read"
        case .sensorTypeDetection: return "Sensor Type Detection"
        case .framRead: return "FRAM Read"
        case .framDecryption: return "FRAM Decryption"
        case .crcValidation: return "CRC Validation"
        case .enableTimeExtraction: return "Enable Time Extraction"
        case .bleUnlock: return "BLE Unlock"
        case .bleStreaming: return "BLE Streaming"
        case .glucoseExtraction: return "Glucose Extraction"
        case .glucoseCalibration: return "Glucose Calibration"
        }
    }
    
    public var order: Int {
        switch self {
        case .nfcActivation: return 1
        case .patchInfoRead: return 2
        case .sensorTypeDetection: return 3
        case .framRead: return 4
        case .framDecryption: return 5
        case .crcValidation: return 6
        case .enableTimeExtraction: return 7
        case .bleUnlock: return 8
        case .bleStreaming: return 9
        case .glucoseExtraction: return 10
        case .glucoseCalibration: return 11
        }
    }
    
    /// Whether this phase is NFC-related
    public var isNFCPhase: Bool {
        switch self {
        case .nfcActivation, .patchInfoRead, .sensorTypeDetection, .framRead, .framDecryption, .crcValidation, .enableTimeExtraction:
            return true
        case .bleUnlock, .bleStreaming, .glucoseExtraction, .glucoseCalibration:
            return false
        }
    }
    
    /// Whether this phase is BLE-related
    public var isBLEPhase: Bool {
        switch self {
        case .bleUnlock, .bleStreaming, .glucoseExtraction, .glucoseCalibration:
            return true
        case .nfcActivation, .patchInfoRead, .sensorTypeDetection, .framRead, .framDecryption, .crcValidation, .enableTimeExtraction:
            return false
        }
    }
}

// MARK: - Libre 2 Attempt Record

/// Complete record of a Libre 2 connection/read attempt
public struct Libre2AttemptRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let sensorUID: Data
    public let sensorType: String?
    public let variant: Libre2VariantSelection
    public let nfcActivation: Libre2PhaseResult?
    public let patchInfoRead: Libre2PhaseResult?
    public let sensorTypeDetection: Libre2PhaseResult?
    public let framRead: Libre2PhaseResult?
    public let framDecryption: Libre2PhaseResult?
    public let crcValidation: Libre2PhaseResult?
    public let enableTimeExtraction: Libre2PhaseResult?
    public let bleUnlock: Libre2PhaseResult?
    public let bleStreaming: Libre2PhaseResult?
    public let glucoseExtraction: Libre2PhaseResult?
    public let glucoseCalibration: Libre2PhaseResult?
    public let success: Bool
    public let failedPhase: Libre2Phase?
    public let errorSummary: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        sensorUID: Data,
        sensorType: String? = nil,
        variant: Libre2VariantSelection,
        nfcActivation: Libre2PhaseResult? = nil,
        patchInfoRead: Libre2PhaseResult? = nil,
        sensorTypeDetection: Libre2PhaseResult? = nil,
        framRead: Libre2PhaseResult? = nil,
        framDecryption: Libre2PhaseResult? = nil,
        crcValidation: Libre2PhaseResult? = nil,
        enableTimeExtraction: Libre2PhaseResult? = nil,
        bleUnlock: Libre2PhaseResult? = nil,
        bleStreaming: Libre2PhaseResult? = nil,
        glucoseExtraction: Libre2PhaseResult? = nil,
        glucoseCalibration: Libre2PhaseResult? = nil,
        success: Bool,
        failedPhase: Libre2Phase? = nil,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sensorUID = sensorUID
        self.sensorType = sensorType
        self.variant = variant
        self.nfcActivation = nfcActivation
        self.patchInfoRead = patchInfoRead
        self.sensorTypeDetection = sensorTypeDetection
        self.framRead = framRead
        self.framDecryption = framDecryption
        self.crcValidation = crcValidation
        self.enableTimeExtraction = enableTimeExtraction
        self.bleUnlock = bleUnlock
        self.bleStreaming = bleStreaming
        self.glucoseExtraction = glucoseExtraction
        self.glucoseCalibration = glucoseCalibration
        self.success = success
        self.failedPhase = failedPhase
        self.errorSummary = errorSummary
    }
    
    /// All phases as an array for iteration
    public var allPhases: [Libre2PhaseResult?] {
        [
            nfcActivation,
            patchInfoRead,
            sensorTypeDetection,
            framRead,
            framDecryption,
            crcValidation,
            enableTimeExtraction,
            bleUnlock,
            bleStreaming,
            glucoseExtraction,
            glucoseCalibration
        ]
    }
    
    /// Completed phases only
    public var completedPhases: [Libre2PhaseResult] {
        allPhases.compactMap { $0 }
    }
    
    /// Total duration of all phases
    public var totalDurationMs: Double {
        completedPhases.reduce(0) { $0 + $1.durationMs }
    }
    
    /// Last successful phase
    public var lastSuccessfulPhase: Libre2Phase? {
        completedPhases.filter { $0.success }.last?.phase
    }
    
    /// Sensor UID as hex string
    public var sensorUIDHex: String {
        sensorUID.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Attempt Builder

/// Builder for Libre 2 attempt records
public final class Libre2AttemptBuilder: @unchecked Sendable {
    private let id: String
    private let timestamp: Date
    private let sensorUID: Data
    private let variant: Libre2VariantSelection
    private var sensorType: String?
    private var nfcActivation: Libre2PhaseResult?
    private var patchInfoRead: Libre2PhaseResult?
    private var sensorTypeDetection: Libre2PhaseResult?
    private var framRead: Libre2PhaseResult?
    private var framDecryption: Libre2PhaseResult?
    private var crcValidation: Libre2PhaseResult?
    private var enableTimeExtraction: Libre2PhaseResult?
    private var bleUnlock: Libre2PhaseResult?
    private var bleStreaming: Libre2PhaseResult?
    private var glucoseExtraction: Libre2PhaseResult?
    private var glucoseCalibration: Libre2PhaseResult?
    private var currentPhaseStart: Date?
    private var currentPhase: Libre2Phase?
    
    public init(sensorUID: Data, variant: Libre2VariantSelection) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.sensorUID = sensorUID
        self.variant = variant
    }
    
    /// Start a phase
    public func startPhase(_ phase: Libre2Phase) {
        currentPhase = phase
        currentPhaseStart = Date()
    }
    
    /// Complete current phase with success
    public func completePhaseSuccess(metadata: [String: String] = [:]) {
        guard let phase = currentPhase, let start = currentPhaseStart else { return }
        let result = Libre2PhaseResult.success(phase: phase, startTime: start, metadata: metadata)
        setPhaseResult(phase, result: result)
        currentPhase = nil
        currentPhaseStart = nil
    }
    
    /// Complete current phase with failure
    public func completePhaseFailure(error: String, code: String? = nil) {
        guard let phase = currentPhase, let start = currentPhaseStart else { return }
        let result = Libre2PhaseResult.failure(phase: phase, startTime: start, error: error, code: code)
        setPhaseResult(phase, result: result)
        currentPhase = nil
        currentPhaseStart = nil
    }
    
    /// Set sensor type
    public func setSensorType(_ type: String) {
        self.sensorType = type
    }
    
    /// Build the final record
    public func build() -> Libre2AttemptRecord {
        // Determine overall success and failed phase
        let allResults: [Libre2PhaseResult?] = [
            nfcActivation, patchInfoRead, sensorTypeDetection,
            framRead, framDecryption, crcValidation, enableTimeExtraction,
            bleUnlock, bleStreaming, glucoseExtraction, glucoseCalibration
        ]
        
        let failedResult = allResults.compactMap { $0 }.first { !$0.success }
        let success = failedResult == nil
        
        return Libre2AttemptRecord(
            id: id,
            timestamp: timestamp,
            sensorUID: sensorUID,
            sensorType: sensorType,
            variant: variant,
            nfcActivation: nfcActivation,
            patchInfoRead: patchInfoRead,
            sensorTypeDetection: sensorTypeDetection,
            framRead: framRead,
            framDecryption: framDecryption,
            crcValidation: crcValidation,
            enableTimeExtraction: enableTimeExtraction,
            bleUnlock: bleUnlock,
            bleStreaming: bleStreaming,
            glucoseExtraction: glucoseExtraction,
            glucoseCalibration: glucoseCalibration,
            success: success,
            failedPhase: failedResult?.phase,
            errorSummary: failedResult?.errorMessage
        )
    }
    
    private func setPhaseResult(_ phase: Libre2Phase, result: Libre2PhaseResult) {
        switch phase {
        case .nfcActivation: nfcActivation = result
        case .patchInfoRead: patchInfoRead = result
        case .sensorTypeDetection: sensorTypeDetection = result
        case .framRead: framRead = result
        case .framDecryption: framDecryption = result
        case .crcValidation: crcValidation = result
        case .enableTimeExtraction: enableTimeExtraction = result
        case .bleUnlock: bleUnlock = result
        case .bleStreaming: bleStreaming = result
        case .glucoseExtraction: glucoseExtraction = result
        case .glucoseCalibration: glucoseCalibration = result
        }
    }
}

// MARK: - Evidence Statistics

/// Statistics about Libre 2 evidence collected
public struct Libre2EvidenceStatistics: Sendable, Codable {
    public let totalAttempts: Int
    public let successCount: Int
    public let failureCount: Int
    public let successRate: Double
    public let failuresByPhase: [Libre2Phase: Int]
    public let avgDurationMs: Double
    public let variantCounts: [String: Int]
    public let sensorTypeCounts: [String: Int]
    public let nfcSuccessRate: Double
    public let bleSuccessRate: Double
    
    public init(
        totalAttempts: Int,
        successCount: Int,
        failureCount: Int,
        failuresByPhase: [Libre2Phase: Int],
        avgDurationMs: Double,
        variantCounts: [String: Int],
        sensorTypeCounts: [String: Int],
        nfcSuccessRate: Double,
        bleSuccessRate: Double
    ) {
        self.totalAttempts = totalAttempts
        self.successCount = successCount
        self.failureCount = failureCount
        self.successRate = totalAttempts > 0 ? Double(successCount) / Double(totalAttempts) * 100.0 : 0
        self.failuresByPhase = failuresByPhase
        self.avgDurationMs = avgDurationMs
        self.variantCounts = variantCounts
        self.sensorTypeCounts = sensorTypeCounts
        self.nfcSuccessRate = nfcSuccessRate
        self.bleSuccessRate = bleSuccessRate
    }
    
    /// Most common failure phase
    public var mostCommonFailurePhase: Libre2Phase? {
        failuresByPhase.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Evidence Collector Actor

/// Actor for thread-safe Libre 2 evidence collection
public actor Libre2EvidenceCollector {
    /// Maximum attempts to keep
    private let maxAttempts: Int
    
    /// All attempt records
    private var attempts: [Libre2AttemptRecord] = []
    
    /// Create a new collector
    public init(maxAttempts: Int = 500) {
        self.maxAttempts = maxAttempts
    }
    
    // MARK: - Recording
    
    /// Record a completed attempt
    public func record(_ attempt: Libre2AttemptRecord) {
        attempts.append(attempt)
        trimIfNeeded()
    }
    
    /// Record multiple attempts
    public func record(_ newAttempts: [Libre2AttemptRecord]) {
        attempts.append(contentsOf: newAttempts)
        trimIfNeeded()
    }
    
    // MARK: - Query
    
    /// Get all attempts
    public func getAllAttempts() -> [Libre2AttemptRecord] {
        attempts
    }
    
    /// Get successful attempts only
    public func successfulAttempts() -> [Libre2AttemptRecord] {
        attempts.filter { $0.success }
    }
    
    /// Get failed attempts only
    public func failedAttempts() -> [Libre2AttemptRecord] {
        attempts.filter { !$0.success }
    }
    
    /// Get attempts for a specific sensor
    public func attempts(forSensorUID uid: Data) -> [Libre2AttemptRecord] {
        attempts.filter { $0.sensorUID == uid }
    }
    
    /// Get attempts with a specific variant
    public func attempts(withVariant variant: Libre2VariantSelection) -> [Libre2AttemptRecord] {
        attempts.filter { $0.variant == variant }
    }
    
    /// Get attempts since a date
    public func attempts(since date: Date) -> [Libre2AttemptRecord] {
        attempts.filter { $0.timestamp >= date }
    }
    
    /// Get attempts that failed at a specific phase
    public func attempts(failedAtPhase phase: Libre2Phase) -> [Libre2AttemptRecord] {
        attempts.filter { $0.failedPhase == phase }
    }
    
    /// Get the last N attempts
    public func lastAttempts(_ count: Int) -> [Libre2AttemptRecord] {
        Array(attempts.suffix(count))
    }
    
    // MARK: - Statistics
    
    /// Compute statistics
    public func computeStatistics() -> Libre2EvidenceStatistics {
        let total = attempts.count
        let successes = attempts.filter { $0.success }.count
        let failures = total - successes
        
        // Count failures by phase
        var failuresByPhase: [Libre2Phase: Int] = [:]
        for attempt in attempts where !attempt.success {
            if let phase = attempt.failedPhase {
                failuresByPhase[phase, default: 0] += 1
            }
        }
        
        // Average duration
        let avgDuration: Double
        if total > 0 {
            avgDuration = attempts.reduce(0.0) { $0 + $1.totalDurationMs } / Double(total)
        } else {
            avgDuration = 0
        }
        
        // Variant counts
        var variantCounts: [String: Int] = [:]
        for attempt in attempts {
            variantCounts[attempt.variant.id, default: 0] += 1
        }
        
        // Sensor type counts
        var sensorTypeCounts: [String: Int] = [:]
        for attempt in attempts {
            if let type = attempt.sensorType {
                sensorTypeCounts[type, default: 0] += 1
            }
        }
        
        // NFC success rate (attempts that got past NFC phases)
        let nfcAttempts = attempts.filter { $0.nfcActivation != nil }
        let nfcSuccesses = nfcAttempts.filter { attempt in
            guard let nfc = attempt.nfcActivation, let fram = attempt.framRead else { return false }
            return nfc.success && fram.success
        }
        let nfcSuccessRate = nfcAttempts.isEmpty ? 0 : Double(nfcSuccesses.count) / Double(nfcAttempts.count) * 100.0
        
        // BLE success rate
        let bleAttempts = attempts.filter { $0.bleUnlock != nil }
        let bleSuccesses = bleAttempts.filter { attempt in
            guard let unlock = attempt.bleUnlock else { return false }
            return unlock.success
        }
        let bleSuccessRate = bleAttempts.isEmpty ? 0 : Double(bleSuccesses.count) / Double(bleAttempts.count) * 100.0
        
        return Libre2EvidenceStatistics(
            totalAttempts: total,
            successCount: successes,
            failureCount: failures,
            failuresByPhase: failuresByPhase,
            avgDurationMs: avgDuration,
            variantCounts: variantCounts,
            sensorTypeCounts: sensorTypeCounts,
            nfcSuccessRate: nfcSuccessRate,
            bleSuccessRate: bleSuccessRate
        )
    }
    
    // MARK: - Export
    
    /// Export all attempts as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(attempts)
    }
    
    /// Generate an evidence report
    public func generateReport() -> Libre2EvidenceReport {
        let stats = computeStatistics()
        
        // Find best performing variants
        let successfulByVariant = Dictionary(grouping: attempts.filter { $0.success }) { $0.variant.id }
        let bestVariants = successfulByVariant.sorted { $0.value.count > $1.value.count }.prefix(3).map { $0.key }
        
        // Phase timing analysis
        var phaseTiming: [Libre2Phase: (avg: Double, min: Double, max: Double)] = [:]
        for phase in Libre2Phase.allCases {
            let durations = attempts.compactMap { attempt -> Double? in
                switch phase {
                case .nfcActivation: return attempt.nfcActivation?.durationMs
                case .patchInfoRead: return attempt.patchInfoRead?.durationMs
                case .sensorTypeDetection: return attempt.sensorTypeDetection?.durationMs
                case .framRead: return attempt.framRead?.durationMs
                case .framDecryption: return attempt.framDecryption?.durationMs
                case .crcValidation: return attempt.crcValidation?.durationMs
                case .enableTimeExtraction: return attempt.enableTimeExtraction?.durationMs
                case .bleUnlock: return attempt.bleUnlock?.durationMs
                case .bleStreaming: return attempt.bleStreaming?.durationMs
                case .glucoseExtraction: return attempt.glucoseExtraction?.durationMs
                case .glucoseCalibration: return attempt.glucoseCalibration?.durationMs
                }
            }
            if !durations.isEmpty {
                let avg = durations.reduce(0, +) / Double(durations.count)
                phaseTiming[phase] = (avg: avg, min: durations.min() ?? 0, max: durations.max() ?? 0)
            }
        }
        
        return Libre2EvidenceReport(
            generatedAt: Date(),
            statistics: stats,
            bestPerformingVariants: bestVariants,
            phaseTiming: phaseTiming,
            recentFailures: failedAttempts().suffix(5).map { $0 }
        )
    }
    
    // MARK: - Maintenance
    
    /// Clear all attempts
    public func clear() {
        attempts.removeAll()
    }
    
    /// Clear attempts older than date
    public func clearBefore(_ date: Date) {
        attempts.removeAll { $0.timestamp < date }
    }
    
    private func trimIfNeeded() {
        if attempts.count > maxAttempts {
            attempts.removeFirst(attempts.count - maxAttempts)
        }
    }
}

// MARK: - Evidence Report

/// Structured evidence report for Libre 2
public struct Libre2EvidenceReport: Sendable, Codable {
    public let generatedAt: Date
    public let statistics: Libre2EvidenceStatistics
    public let bestPerformingVariants: [String]
    public let phaseTiming: [Libre2Phase: PhaseTiming]
    public let recentFailures: [Libre2AttemptRecord]
    
    public struct PhaseTiming: Sendable, Codable {
        public let avg: Double
        public let min: Double
        public let max: Double
    }
    
    public init(
        generatedAt: Date,
        statistics: Libre2EvidenceStatistics,
        bestPerformingVariants: [String],
        phaseTiming: [Libre2Phase: (avg: Double, min: Double, max: Double)],
        recentFailures: [Libre2AttemptRecord]
    ) {
        self.generatedAt = generatedAt
        self.statistics = statistics
        self.bestPerformingVariants = bestPerformingVariants
        self.phaseTiming = phaseTiming.mapValues { PhaseTiming(avg: $0.avg, min: $0.min, max: $0.max) }
        self.recentFailures = recentFailures
    }
}
