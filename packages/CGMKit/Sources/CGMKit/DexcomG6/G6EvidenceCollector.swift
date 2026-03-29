// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G6EvidenceCollector.swift
// CGMKit - DexcomG6
//
// Evidence collector for G6 authentication attempts.
// Tracks phase-by-phase success/failure and generates structured reports.
//
// Trace: UNCERT-G6-004

import Foundation
import BLEKit

// MARK: - G6 Phase Result

/// Result of a single G6 authentication phase
public struct G6PhaseResult: Sendable, Codable, Equatable {
    public let phase: G6AuthPhase
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
        phase: G6AuthPhase,
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
    
    public static func success(phase: G6AuthPhase, startTime: Date, metadata: [String: String] = [:]) -> G6PhaseResult {
        G6PhaseResult(phase: phase, success: true, startTime: startTime, metadata: metadata)
    }
    
    public static func failure(phase: G6AuthPhase, startTime: Date, error: String, code: String? = nil) -> G6PhaseResult {
        G6PhaseResult(phase: phase, success: false, startTime: startTime, errorCode: code, errorMessage: error)
    }
}

/// G6 authentication phases
public enum G6AuthPhase: String, Sendable, Codable, CaseIterable {
    case keyDerivation = "key_derivation"
    case tokenSend = "token_send"
    case tokenVerify = "token_verify"
    case challengeResponse = "challenge_response"
    case statusCheck = "status_check"
    
    public var description: String {
        switch self {
        case .keyDerivation: return "Key Derivation"
        case .tokenSend: return "Token Send"
        case .tokenVerify: return "Token Verify"
        case .challengeResponse: return "Challenge Response"
        case .statusCheck: return "Status Check"
        }
    }
    
    public var order: Int {
        switch self {
        case .keyDerivation: return 1
        case .tokenSend: return 2
        case .tokenVerify: return 3
        case .challengeResponse: return 4
        case .statusCheck: return 5
        }
    }
}

// MARK: - G6 Attempt Record

/// Complete record of a G6 authentication attempt
public struct G6AttemptRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let transmitterId: String
    public let variant: G6VariantSelection
    public let keyDerivation: G6PhaseResult?
    public let tokenSend: G6PhaseResult?
    public let tokenVerify: G6PhaseResult?
    public let challengeResponse: G6PhaseResult?
    public let statusCheck: G6PhaseResult?
    public let success: Bool
    public let totalDurationMs: Double?
    public let failurePhase: G6AuthPhase?
    public let errorSummary: String?
    public let isFirefly: Bool
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        transmitterId: String,
        variant: G6VariantSelection,
        keyDerivation: G6PhaseResult? = nil,
        tokenSend: G6PhaseResult? = nil,
        tokenVerify: G6PhaseResult? = nil,
        challengeResponse: G6PhaseResult? = nil,
        statusCheck: G6PhaseResult? = nil,
        success: Bool = false,
        totalDurationMs: Double? = nil,
        failurePhase: G6AuthPhase? = nil,
        errorSummary: String? = nil,
        isFirefly: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transmitterId = transmitterId
        self.variant = variant
        self.keyDerivation = keyDerivation
        self.tokenSend = tokenSend
        self.tokenVerify = tokenVerify
        self.challengeResponse = challengeResponse
        self.statusCheck = statusCheck
        self.success = success
        self.totalDurationMs = totalDurationMs
        self.failurePhase = failurePhase
        self.errorSummary = errorSummary
        self.isFirefly = isFirefly
        self.metadata = metadata
    }
    
    /// Get all phases that were attempted
    public var attemptedPhases: [G6PhaseResult] {
        [keyDerivation, tokenSend, tokenVerify, challengeResponse, statusCheck].compactMap { $0 }
    }
    
    /// Get first failed phase
    public var firstFailedPhase: G6PhaseResult? {
        attemptedPhases.first { !$0.success }
    }
    
    /// Check if all phases succeeded
    public var allPhasesSucceeded: Bool {
        attemptedPhases.allSatisfy { $0.success }
    }
}

// MARK: - G6 Evidence Report

/// Aggregate report of G6 authentication evidence
public struct G6EvidenceReport: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let generatedAt: Date
    public let attempts: [G6AttemptRecord]
    public let statistics: G6EvidenceStatistics
    public let platform: ReportPlatformInfo
    public let recommendations: [String]
    
    public init(
        id: String = UUID().uuidString,
        generatedAt: Date = Date(),
        attempts: [G6AttemptRecord],
        statistics: G6EvidenceStatistics,
        platform: ReportPlatformInfo,
        recommendations: [String] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.attempts = attempts
        self.statistics = statistics
        self.platform = platform
        self.recommendations = recommendations
    }
}

// Note: ReportPlatformInfo is imported from BLEKit

// MARK: - G6 Evidence Statistics

/// Statistics about G6 authentication attempts
public struct G6EvidenceStatistics: Sendable, Codable, Equatable {
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let successRate: Double
    public let avgDurationMs: Double?
    public let failuresByPhase: [G6AuthPhase: Int]
    public let failuresByVariant: [String: Int]
    public let mostSuccessfulVariant: String?
    
    public init(
        totalAttempts: Int,
        successfulAttempts: Int,
        failedAttempts: Int,
        successRate: Double,
        avgDurationMs: Double?,
        failuresByPhase: [G6AuthPhase: Int],
        failuresByVariant: [String: Int],
        mostSuccessfulVariant: String?
    ) {
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.failedAttempts = failedAttempts
        self.successRate = successRate
        self.avgDurationMs = avgDurationMs
        self.failuresByPhase = failuresByPhase
        self.failuresByVariant = failuresByVariant
        self.mostSuccessfulVariant = mostSuccessfulVariant
    }
    
    public static func empty() -> G6EvidenceStatistics {
        G6EvidenceStatistics(
            totalAttempts: 0,
            successfulAttempts: 0,
            failedAttempts: 0,
            successRate: 0,
            avgDurationMs: nil,
            failuresByPhase: [:],
            failuresByVariant: [:],
            mostSuccessfulVariant: nil
        )
    }
}

// MARK: - G6 Evidence Collector

/// Thread-safe evidence collector for G6 authentication
public actor G6EvidenceCollector {
    private var attempts: [G6AttemptRecord] = []
    private var currentAttempt: AttemptBuilder?
    private let maxAttempts: Int
    
    public init(maxAttempts: Int = 500) {
        self.maxAttempts = maxAttempts
    }
    
    // MARK: - Attempt Tracking
    
    /// Start tracking a new authentication attempt
    public func startAttempt(
        transmitterId: String,
        variant: G6VariantSelection,
        isFirefly: Bool = false
    ) -> String {
        let id = UUID().uuidString
        currentAttempt = AttemptBuilder(
            id: id,
            transmitterId: transmitterId,
            variant: variant,
            isFirefly: isFirefly
        )
        return id
    }
    
    /// Record a phase result
    public func recordPhase(_ result: G6PhaseResult) {
        currentAttempt?.addPhase(result)
    }
    
    /// Record phase start (returns phase ID for timing)
    public func startPhase(_ phase: G6AuthPhase, metadata: [String: String] = [:]) -> Date {
        let startTime = Date()
        currentAttempt?.startPhase(phase, at: startTime, metadata: metadata)
        return startTime
    }
    
    /// Record phase completion
    public func completePhase(
        _ phase: G6AuthPhase,
        startTime: Date,
        success: Bool,
        error: String? = nil,
        errorCode: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let result: G6PhaseResult
        if success {
            result = .success(phase: phase, startTime: startTime, metadata: metadata)
        } else {
            result = .failure(phase: phase, startTime: startTime, error: error ?? "Unknown error", code: errorCode)
        }
        currentAttempt?.addPhase(result)
    }
    
    /// Complete the current attempt
    public func completeAttempt(success: Bool, error: String? = nil) {
        guard let builder = currentAttempt else { return }
        
        let record = builder.build(success: success, errorSummary: error)
        attempts.append(record)
        currentAttempt = nil
        
        // Trim if over limit
        if attempts.count > maxAttempts {
            attempts.removeFirst(attempts.count - maxAttempts)
        }
    }
    
    // MARK: - Query
    
    /// Get all attempts
    public func getAttempts() -> [G6AttemptRecord] {
        attempts
    }
    
    /// Get successful attempts
    public func getSuccessfulAttempts() -> [G6AttemptRecord] {
        attempts.filter { $0.success }
    }
    
    /// Get failed attempts
    public func getFailedAttempts() -> [G6AttemptRecord] {
        attempts.filter { !$0.success }
    }
    
    /// Get attempts for a specific variant
    public func getAttempts(variant: G6VariantSelection) -> [G6AttemptRecord] {
        attempts.filter { $0.variant == variant }
    }
    
    /// Get attempts for a specific transmitter
    public func getAttempts(transmitterId: String) -> [G6AttemptRecord] {
        attempts.filter { $0.transmitterId == transmitterId }
    }
    
    // MARK: - Statistics
    
    /// Generate statistics from collected attempts
    public func generateStatistics() -> G6EvidenceStatistics {
        guard !attempts.isEmpty else {
            return .empty()
        }
        
        let successfulAttempts = attempts.filter { $0.success }
        let failedAttempts = attempts.filter { !$0.success }
        
        // Calculate failure distribution by phase
        var failuresByPhase: [G6AuthPhase: Int] = [:]
        for attempt in failedAttempts {
            if let phase = attempt.failurePhase {
                failuresByPhase[phase, default: 0] += 1
            }
        }
        
        // Calculate failure distribution by variant
        var failuresByVariant: [String: Int] = [:]
        for attempt in failedAttempts {
            failuresByVariant[attempt.variant.id, default: 0] += 1
        }
        
        // Find most successful variant
        var variantSuccesses: [String: Int] = [:]
        for attempt in successfulAttempts {
            variantSuccesses[attempt.variant.id, default: 0] += 1
        }
        let mostSuccessfulVariant = variantSuccesses.max { $0.value < $1.value }?.key
        
        // Calculate average duration
        let durations = successfulAttempts.compactMap { $0.totalDurationMs }
        let avgDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        
        return G6EvidenceStatistics(
            totalAttempts: attempts.count,
            successfulAttempts: successfulAttempts.count,
            failedAttempts: failedAttempts.count,
            successRate: Double(successfulAttempts.count) / Double(attempts.count),
            avgDurationMs: avgDuration,
            failuresByPhase: failuresByPhase,
            failuresByVariant: failuresByVariant,
            mostSuccessfulVariant: mostSuccessfulVariant
        )
    }
    
    // MARK: - Report Generation
    
    /// Generate a full evidence report
    public func generateReport() -> G6EvidenceReport {
        let stats = generateStatistics()
        
        var recommendations: [String] = []
        
        // Analyze failure patterns
        if let (phase, count) = stats.failuresByPhase.max(by: { $0.value < $1.value }), count > 0 {
            recommendations.append("Most failures occur at \(phase.description) (\(count) failures)")
        }
        
        if let best = stats.mostSuccessfulVariant {
            recommendations.append("Most successful variant: \(best)")
        }
        
        if stats.successRate < 0.5 && stats.totalAttempts > 5 {
            recommendations.append("Low success rate (\(Int(stats.successRate * 100))%) - consider variant testing")
        }
        
        return G6EvidenceReport(
            attempts: attempts,
            statistics: stats,
            platform: platformInfo(),
            recommendations: recommendations
        )
    }
    
    /// Get platform info
    private func platformInfo() -> ReportPlatformInfo {
        #if os(iOS)
        return ReportPlatformInfo(
            os: "iOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
        #elseif os(macOS)
        return ReportPlatformInfo(
            os: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
        #else
        return ReportPlatformInfo(
            os: "Linux",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: "1.0.0",
            appBuild: "1"
        )
        #endif
    }
    
    // MARK: - Export
    
    /// Export attempts as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(attempts)
    }
    
    /// Export report as JSON
    public func exportReportJSON() throws -> Data {
        let report = generateReport()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    
    /// Clear all attempts
    public func clear() {
        attempts.removeAll()
        currentAttempt = nil
    }
    
    /// Get count
    public var attemptCount: Int {
        attempts.count
    }
}

// MARK: - Attempt Builder

/// Builder for constructing G6 attempt records
private struct AttemptBuilder {
    let id: String
    let timestamp: Date
    let transmitterId: String
    let variant: G6VariantSelection
    let isFirefly: Bool
    
    var keyDerivation: G6PhaseResult?
    var tokenSend: G6PhaseResult?
    var tokenVerify: G6PhaseResult?
    var challengeResponse: G6PhaseResult?
    var statusCheck: G6PhaseResult?
    
    var currentPhase: G6AuthPhase?
    var phaseStartTime: Date?
    var phaseMetadata: [String: String] = [:]
    
    init(id: String, transmitterId: String, variant: G6VariantSelection, isFirefly: Bool) {
        self.id = id
        self.timestamp = Date()
        self.transmitterId = transmitterId
        self.variant = variant
        self.isFirefly = isFirefly
    }
    
    mutating func startPhase(_ phase: G6AuthPhase, at time: Date, metadata: [String: String]) {
        currentPhase = phase
        phaseStartTime = time
        phaseMetadata = metadata
    }
    
    mutating func addPhase(_ result: G6PhaseResult) {
        switch result.phase {
        case .keyDerivation: keyDerivation = result
        case .tokenSend: tokenSend = result
        case .tokenVerify: tokenVerify = result
        case .challengeResponse: challengeResponse = result
        case .statusCheck: statusCheck = result
        }
    }
    
    func build(success: Bool, errorSummary: String?) -> G6AttemptRecord {
        let phases: [G6PhaseResult?] = [keyDerivation, tokenSend, tokenVerify, challengeResponse, statusCheck]
        let totalDuration = phases.compactMap { $0 }.reduce(0) { $0 + $1.durationMs }
        
        let failurePhase = phases.compactMap { $0 }.first { !$0.success }?.phase
        
        return G6AttemptRecord(
            id: id,
            timestamp: timestamp,
            transmitterId: transmitterId,
            variant: variant,
            keyDerivation: keyDerivation,
            tokenSend: tokenSend,
            tokenVerify: tokenVerify,
            challengeResponse: challengeResponse,
            statusCheck: statusCheck,
            success: success,
            totalDurationMs: totalDuration > 0 ? totalDuration : nil,
            failurePhase: failurePhase,
            errorSummary: errorSummary,
            isFirefly: isFirefly
        )
    }
}
