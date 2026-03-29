// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G7EvidenceCollector.swift
// CGMKit - DexcomG7
//
// Evidence collector for G7 J-PAKE authentication attempts.
// Tracks per-round success/failure and generates structured reports.
//
// Trace: UNCERT-G7-004

import Foundation
import BLEKit

// MARK: - G7 Round Result

/// Result of a single J-PAKE round
public struct G7RoundResult: Sendable, Codable, Equatable {
    public let round: Int
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
        round: Int,
        success: Bool,
        startTime: Date,
        endTime: Date = Date(),
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.round = round
        self.success = success
        self.startTime = startTime
        self.endTime = endTime
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
    
    public static func success(round: Int, startTime: Date, metadata: [String: String] = [:]) -> G7RoundResult {
        G7RoundResult(round: round, success: true, startTime: startTime, metadata: metadata)
    }
    
    public static func failure(round: Int, startTime: Date, error: String, code: String? = nil) -> G7RoundResult {
        G7RoundResult(round: round, success: false, startTime: startTime, errorCode: code, errorMessage: error)
    }
}

// MARK: - G7 Attempt Record

/// Complete record of a G7 authentication attempt
public struct G7AttemptRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let variant: G7VariantSelection
    public let round1: G7RoundResult?
    public let round2: G7RoundResult?
    public let keyConfirmation: G7RoundResult?
    public let success: Bool
    public let totalDurationMs: Double?
    public let failureRound: Int?
    public let errorSummary: String?
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        variant: G7VariantSelection,
        round1: G7RoundResult? = nil,
        round2: G7RoundResult? = nil,
        keyConfirmation: G7RoundResult? = nil,
        success: Bool,
        totalDurationMs: Double? = nil,
        failureRound: Int? = nil,
        errorSummary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.variant = variant
        self.round1 = round1
        self.round2 = round2
        self.keyConfirmation = keyConfirmation
        self.success = success
        self.totalDurationMs = totalDurationMs
        self.failureRound = failureRound
        self.errorSummary = errorSummary
        self.metadata = metadata
    }
    
    /// Which round failed (if any)
    public var failedAt: String? {
        if let round = failureRound {
            switch round {
            case 1: return "Round 1"
            case 2: return "Round 2"
            case 3: return "Key Confirmation"
            default: return "Round \(round)"
            }
        }
        return nil
    }
}

// MARK: - G7 Evidence Report

/// Complete evidence report for G7 J-PAKE authentication
public struct G7EvidenceReport: Sendable, Codable, Equatable, Identifiable {
    public static let schemaVersion = "1.0.0"
    
    public let id: String
    public let schemaVersion: String
    public let createdAt: Date
    public let sessionId: String
    public let sensorId: String?  // Hashed for privacy
    public let attempts: [G7AttemptRecord]
    public let workingVariant: G7VariantSelection?
    public let statistics: G7EvidenceStatistics
    public let platformInfo: ReportPlatformInfo?
    public let notes: String?
    public let tags: [String]
    
    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        sessionId: String,
        sensorId: String? = nil,
        attempts: [G7AttemptRecord] = [],
        workingVariant: G7VariantSelection? = nil,
        platformInfo: ReportPlatformInfo? = nil,
        notes: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.schemaVersion = Self.schemaVersion
        self.createdAt = createdAt
        self.sessionId = sessionId
        self.sensorId = sensorId
        self.attempts = attempts
        self.workingVariant = workingVariant
        self.statistics = G7EvidenceStatistics.calculate(from: attempts)
        self.platformInfo = platformInfo
        self.notes = notes
        self.tags = tags
    }
    
    /// Export as JSON data
    public func toJSON(prettyPrint: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Create from JSON data
    public static func fromJSON(_ data: Data) throws -> G7EvidenceReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(G7EvidenceReport.self, from: data)
    }
    
    /// Redact sensitive information
    public func redacted() -> G7EvidenceReport {
        G7EvidenceReport(
            id: id,
            createdAt: createdAt,
            sessionId: String(sessionId.prefix(8)) + "...",
            sensorId: sensorId.map { _ in "[REDACTED]" },
            attempts: attempts,
            workingVariant: workingVariant,
            platformInfo: platformInfo,
            notes: notes,
            tags: tags
        )
    }
}

// MARK: - G7 Evidence Statistics

/// Statistics calculated from G7 authentication attempts
public struct G7EvidenceStatistics: Sendable, Codable, Equatable {
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let successRate: Double
    public let avgDurationMs: Double?
    public let round1SuccessRate: Double
    public let round2SuccessRate: Double
    public let keyConfirmSuccessRate: Double
    public let mostCommonFailureRound: Int?
    public let variantsTried: Int
    public let uniqueErrors: [String]
    
    public init(
        totalAttempts: Int,
        successfulAttempts: Int,
        failedAttempts: Int,
        successRate: Double,
        avgDurationMs: Double?,
        round1SuccessRate: Double,
        round2SuccessRate: Double,
        keyConfirmSuccessRate: Double,
        mostCommonFailureRound: Int?,
        variantsTried: Int,
        uniqueErrors: [String]
    ) {
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.failedAttempts = failedAttempts
        self.successRate = successRate
        self.avgDurationMs = avgDurationMs
        self.round1SuccessRate = round1SuccessRate
        self.round2SuccessRate = round2SuccessRate
        self.keyConfirmSuccessRate = keyConfirmSuccessRate
        self.mostCommonFailureRound = mostCommonFailureRound
        self.variantsTried = variantsTried
        self.uniqueErrors = uniqueErrors
    }
    
    /// Calculate statistics from attempt records
    public static func calculate(from attempts: [G7AttemptRecord]) -> G7EvidenceStatistics {
        let total = attempts.count
        let successful = attempts.filter { $0.success }.count
        let failed = total - successful
        let successRate = total > 0 ? Double(successful) / Double(total) : 0
        
        // Average duration of successful attempts
        let durations = attempts.compactMap { $0.totalDurationMs }
        let avgDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        
        // Round success rates
        let round1Attempts = attempts.compactMap { $0.round1 }
        let round1Success = round1Attempts.isEmpty ? 0 : Double(round1Attempts.filter { $0.success }.count) / Double(round1Attempts.count)
        
        let round2Attempts = attempts.compactMap { $0.round2 }
        let round2Success = round2Attempts.isEmpty ? 0 : Double(round2Attempts.filter { $0.success }.count) / Double(round2Attempts.count)
        
        let keyConfirmAttempts = attempts.compactMap { $0.keyConfirmation }
        let keyConfirmSuccess = keyConfirmAttempts.isEmpty ? 0 : Double(keyConfirmAttempts.filter { $0.success }.count) / Double(keyConfirmAttempts.count)
        
        // Most common failure round
        let failureRounds = attempts.compactMap { $0.failureRound }
        let failureRoundCounts = Dictionary(grouping: failureRounds, by: { $0 }).mapValues { $0.count }
        let mostCommonFailure = failureRoundCounts.max(by: { $0.value < $1.value })?.key
        
        // Unique variants tried
        let variants = Set(attempts.map { $0.variant.id })
        
        // Unique errors
        let errors = Set(attempts.compactMap { $0.errorSummary })
        
        return G7EvidenceStatistics(
            totalAttempts: total,
            successfulAttempts: successful,
            failedAttempts: failed,
            successRate: successRate,
            avgDurationMs: avgDuration,
            round1SuccessRate: round1Success,
            round2SuccessRate: round2Success,
            keyConfirmSuccessRate: keyConfirmSuccess,
            mostCommonFailureRound: mostCommonFailure,
            variantsTried: variants.count,
            uniqueErrors: Array(errors).sorted()
        )
    }
}

// MARK: - G7 Evidence Collector Actor

/// Actor for collecting G7 authentication evidence
/// Trace: UNCERT-G7-004
public actor G7EvidenceCollector {
    
    // MARK: - Properties
    
    private let sessionId: String
    private var attempts: [G7AttemptRecord] = []
    private var currentAttempt: AttemptBuilder?
    private var workingVariant: G7VariantSelection?
    private let sensorId: String?
    
    // MARK: - Initialization
    
    public init(sessionId: String = UUID().uuidString, sensorId: String? = nil) {
        self.sessionId = sessionId
        self.sensorId = sensorId.map { Self.hashSensorId($0) }
    }
    
    // MARK: - Attempt Lifecycle
    
    /// Start a new authentication attempt
    public func startAttempt(variant: G7VariantSelection) {
        currentAttempt = AttemptBuilder(variant: variant)
    }
    
    /// Record round 1 result
    public func recordRound1(success: Bool, error: String? = nil, metadata: [String: String] = [:]) {
        guard let builder = currentAttempt else { return }
        
        if success {
            currentAttempt?.round1 = .success(round: 1, startTime: builder.startTime, metadata: metadata)
        } else {
            currentAttempt?.round1 = .failure(round: 1, startTime: builder.startTime, error: error ?? "Unknown error")
            if currentAttempt?.failureRound == nil {
                currentAttempt?.failureRound = 1
            }
        }
    }
    
    /// Record round 2 result
    public func recordRound2(success: Bool, error: String? = nil, metadata: [String: String] = [:]) {
        guard let builder = currentAttempt else { return }
        let startTime = builder.round1?.endTime ?? builder.startTime
        
        if success {
            currentAttempt?.round2 = .success(round: 2, startTime: startTime, metadata: metadata)
        } else {
            currentAttempt?.round2 = .failure(round: 2, startTime: startTime, error: error ?? "Unknown error")
            if currentAttempt?.failureRound == nil {
                currentAttempt?.failureRound = 2
            }
        }
    }
    
    /// Record key confirmation result
    public func recordKeyConfirmation(success: Bool, error: String? = nil, metadata: [String: String] = [:]) {
        guard let builder = currentAttempt else { return }
        let startTime = builder.round2?.endTime ?? builder.startTime
        
        if success {
            currentAttempt?.keyConfirmation = .success(round: 3, startTime: startTime, metadata: metadata)
        } else {
            currentAttempt?.keyConfirmation = .failure(round: 3, startTime: startTime, error: error ?? "Unknown error")
            if currentAttempt?.failureRound == nil {
                currentAttempt?.failureRound = 3
            }
        }
    }
    
    /// Complete the current attempt
    public func completeAttempt(success: Bool, error: String? = nil) {
        guard let builder = currentAttempt else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(builder.startTime) * 1000.0
        
        let record = G7AttemptRecord(
            variant: builder.variant,
            round1: builder.round1,
            round2: builder.round2,
            keyConfirmation: builder.keyConfirmation,
            success: success,
            totalDurationMs: duration,
            failureRound: builder.failureRound,
            errorSummary: error,
            metadata: builder.metadata
        )
        
        attempts.append(record)
        
        // Track working variant
        if success && workingVariant == nil {
            workingVariant = builder.variant
        }
        
        currentAttempt = nil
    }
    
    /// Cancel the current attempt
    public func cancelAttempt() {
        currentAttempt = nil
    }
    
    // MARK: - Query
    
    /// Get all recorded attempts
    public func allAttempts() -> [G7AttemptRecord] {
        attempts
    }
    
    /// Get successful attempts
    public func successfulAttempts() -> [G7AttemptRecord] {
        attempts.filter { $0.success }
    }
    
    /// Get failed attempts
    public func failedAttempts() -> [G7AttemptRecord] {
        attempts.filter { !$0.success }
    }
    
    /// Get the working variant (if found)
    public func getWorkingVariant() -> G7VariantSelection? {
        workingVariant
    }
    
    /// Get current statistics
    public func statistics() -> G7EvidenceStatistics {
        G7EvidenceStatistics.calculate(from: attempts)
    }
    
    // MARK: - Report Generation
    
    /// Generate evidence report
    public func generateReport(notes: String? = nil, tags: [String] = []) -> G7EvidenceReport {
        G7EvidenceReport(
            sessionId: sessionId,
            sensorId: sensorId,
            attempts: attempts,
            workingVariant: workingVariant,
            platformInfo: Self.currentPlatformInfo(),
            notes: notes,
            tags: tags
        )
    }
    
    /// Export report as JSON
    public func exportJSON(prettyPrint: Bool = true) throws -> Data {
        let report = generateReport()
        return try report.toJSON(prettyPrint: prettyPrint)
    }
    
    /// Clear all evidence
    public func clear() {
        attempts.removeAll()
        currentAttempt = nil
        workingVariant = nil
    }
    
    // MARK: - Private Helpers
    
    /// Hash sensor ID for privacy
    private static func hashSensorId(_ id: String) -> String {
        // Simple hash - first 8 chars of SHA256
        let data = Data(id.utf8)
        // Use a simple hash for demo - in production use CryptoKit
        let hash = data.reduce(0) { ($0 &* 31) &+ Int($1) }
        return String(format: "%08x", abs(hash))
    }
    
    /// Get current platform info
    private static func currentPlatformInfo() -> ReportPlatformInfo {
        #if os(iOS)
        let osName = "iOS"
        #elseif os(macOS)
        let osName = "macOS"
        #elseif os(Linux)
        let osName = "Linux"
        #else
        let osName = "Unknown"
        #endif
        
        return ReportPlatformInfo(
            os: osName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: "1.0.0",
            appBuild: "1",
            deviceModel: nil,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
    
    // MARK: - Attempt Builder
    
    private struct AttemptBuilder {
        let variant: G7VariantSelection
        let startTime: Date
        var round1: G7RoundResult?
        var round2: G7RoundResult?
        var keyConfirmation: G7RoundResult?
        var failureRound: Int?
        var metadata: [String: String] = [:]
        
        init(variant: G7VariantSelection) {
            self.variant = variant
            self.startTime = Date()
        }
    }
}

// MARK: - Shared Collector Instance

/// Shared G7 evidence collector for global access
public actor G7EvidenceManager {
    public static let shared = G7EvidenceManager()
    
    private var collector: G7EvidenceCollector?
    
    private init() {}
    
    /// Get or create collector for current session
    public func getCollector(sensorId: String? = nil) -> G7EvidenceCollector {
        if let existing = collector {
            return existing
        }
        let newCollector = G7EvidenceCollector(sensorId: sensorId)
        collector = newCollector
        return newCollector
    }
    
    /// Reset collector for new session
    public func resetCollector(sensorId: String? = nil) -> G7EvidenceCollector {
        let newCollector = G7EvidenceCollector(sensorId: sensorId)
        collector = newCollector
        return newCollector
    }
    
    /// Get current collector (if exists)
    public func currentCollector() -> G7EvidenceCollector? {
        collector
    }
    
    /// Generate report from current collector
    public func generateReport(notes: String? = nil, tags: [String] = []) async -> G7EvidenceReport? {
        guard let collector = collector else { return nil }
        return await collector.generateReport(notes: notes, tags: tags)
    }
}
