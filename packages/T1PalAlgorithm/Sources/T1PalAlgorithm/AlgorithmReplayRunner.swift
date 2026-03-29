// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmReplayRunner.swift
// T1PalAlgorithm
//
// Replays recorded sessions through algorithms for comparison and analysis.
// Task: ALG-SHADOW-012

import Foundation
import T1PalCore

// MARK: - Replay Result

/// Result of replaying a single session through an algorithm
public struct AlgorithmReplayResult: Sendable, Codable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let algorithmId: String
    public let originalOutput: RecordedOutput?
    public let replayOutput: RecordedOutput
    public let divergence: AlgorithmDivergence
    public let replayedAt: Date
    
    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        algorithmId: String,
        originalOutput: RecordedOutput?,
        replayOutput: RecordedOutput,
        divergence: AlgorithmDivergence,
        replayedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.algorithmId = algorithmId
        self.originalOutput = originalOutput
        self.replayOutput = replayOutput
        self.divergence = divergence
        self.replayedAt = replayedAt
    }
}

/// Divergence analysis between original and replayed result
public struct AlgorithmDivergence: Sendable, Codable {
    /// Whether results are considered equivalent
    public let isEquivalent: Bool
    
    /// Difference in temp basal rate (U/hr)
    public let tempBasalRateDiff: Double?
    
    /// Difference in suggested bolus (U)
    public let bolusDiff: Double?
    
    /// Categorical divergence level
    public let level: DivergenceLevel
    
    /// Human-readable summary
    public let summary: String
    
    public init(
        isEquivalent: Bool,
        tempBasalRateDiff: Double? = nil,
        bolusDiff: Double? = nil,
        level: DivergenceLevel = .none,
        summary: String = ""
    ) {
        self.isEquivalent = isEquivalent
        self.tempBasalRateDiff = tempBasalRateDiff
        self.bolusDiff = bolusDiff
        self.level = level
        self.summary = summary
    }
    
    public enum DivergenceLevel: String, Codable, Sendable {
        case none = "none"
        case minor = "minor"       // < 0.1 U/hr difference
        case moderate = "moderate" // 0.1-0.5 U/hr difference
        case significant = "significant" // > 0.5 U/hr difference
        case opposite = "opposite" // opposite direction (increase vs decrease)
    }
}

// MARK: - Session Replay Report

/// Complete report of replaying a session through multiple algorithms
public struct AlgorithmReplayReport: Sendable, Codable, Identifiable {
    public let id: UUID
    public let session: RecordedSession
    public let results: [AlgorithmReplayResult]
    public let summary: AlgorithmReplaySummary
    public let generatedAt: Date
    
    public init(
        id: UUID = UUID(),
        session: RecordedSession,
        results: [AlgorithmReplayResult],
        summary: AlgorithmReplaySummary,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.results = results
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

/// Summary of session replay results
public struct AlgorithmReplaySummary: Sendable, Codable {
    public let totalAlgorithms: Int
    public let equivalentCount: Int
    public let minorDivergenceCount: Int
    public let moderateDivergenceCount: Int
    public let significantDivergenceCount: Int
    public let oppositeDivergenceCount: Int
    public let averageExecutionTimeMs: Double
    
    public init(
        totalAlgorithms: Int,
        equivalentCount: Int,
        minorDivergenceCount: Int,
        moderateDivergenceCount: Int,
        significantDivergenceCount: Int,
        oppositeDivergenceCount: Int,
        averageExecutionTimeMs: Double
    ) {
        self.totalAlgorithms = totalAlgorithms
        self.equivalentCount = equivalentCount
        self.minorDivergenceCount = minorDivergenceCount
        self.moderateDivergenceCount = moderateDivergenceCount
        self.significantDivergenceCount = significantDivergenceCount
        self.oppositeDivergenceCount = oppositeDivergenceCount
        self.averageExecutionTimeMs = averageExecutionTimeMs
    }
    
    /// Overall agreement ratio (0-1)
    public var agreementRatio: Double {
        guard totalAlgorithms > 0 else { return 0 }
        return Double(equivalentCount + minorDivergenceCount) / Double(totalAlgorithms)
    }
    
    /// Whether there are any significant divergences
    public var hasSignificantDivergence: Bool {
        significantDivergenceCount > 0 || oppositeDivergenceCount > 0
    }
}

// MARK: - Batch Replay Report

/// Report for replaying multiple sessions
public struct BatchAlgorithmReplayReport: Sendable, Codable, Identifiable {
    public let id: UUID
    public let sessionReports: [AlgorithmReplayReport]
    public let batchSummary: BatchAlgorithmReplaySummary
    public let generatedAt: Date
    
    public init(
        id: UUID = UUID(),
        sessionReports: [AlgorithmReplayReport],
        batchSummary: BatchAlgorithmReplaySummary,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionReports = sessionReports
        self.batchSummary = batchSummary
        self.generatedAt = generatedAt
    }
}

/// Summary for batch replay
public struct BatchAlgorithmReplaySummary: Sendable, Codable {
    public let totalSessions: Int
    public let totalAlgorithmReplayResults: Int
    public let overallAgreementRatio: Double
    public let sessionsWithSignificantDivergence: Int
    public let algorithmStats: [String: AlgorithmReplayStat]
    
    public init(
        totalSessions: Int,
        totalAlgorithmReplayResults: Int,
        overallAgreementRatio: Double,
        sessionsWithSignificantDivergence: Int,
        algorithmStats: [String: AlgorithmReplayStat]
    ) {
        self.totalSessions = totalSessions
        self.totalAlgorithmReplayResults = totalAlgorithmReplayResults
        self.overallAgreementRatio = overallAgreementRatio
        self.sessionsWithSignificantDivergence = sessionsWithSignificantDivergence
        self.algorithmStats = algorithmStats
    }
}

/// Per-algorithm statistics
public struct AlgorithmReplayStat: Sendable, Codable {
    public let algorithmId: String
    public let totalReplays: Int
    public let equivalentCount: Int
    public let averageExecutionTimeMs: Double
    public let errorCount: Int
    
    public init(
        algorithmId: String,
        totalReplays: Int,
        equivalentCount: Int,
        averageExecutionTimeMs: Double,
        errorCount: Int
    ) {
        self.algorithmId = algorithmId
        self.totalReplays = totalReplays
        self.equivalentCount = equivalentCount
        self.averageExecutionTimeMs = averageExecutionTimeMs
        self.errorCount = errorCount
    }
}

// MARK: - What-If Report Types (ALG-SHADOW-014)

/// A what-if comparison report
public struct WhatIfReport: Sendable, Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let generatedAt: Date
    public let inputSummary: WhatIfInputSummary
    public let scenarios: [WhatIfScenario]
    public let summary: WhatIfSummary
    
    public init(
        id: UUID = UUID(),
        title: String,
        generatedAt: Date,
        inputSummary: WhatIfInputSummary,
        scenarios: [WhatIfScenario],
        summary: WhatIfSummary
    ) {
        self.id = id
        self.title = title
        self.generatedAt = generatedAt
        self.inputSummary = inputSummary
        self.scenarios = scenarios
        self.summary = summary
    }
}

/// Input state summary for what-if report
public struct WhatIfInputSummary: Sendable, Codable {
    public let glucose: Double
    public let iob: Double
    public let cob: Double
    public let timestamp: Date
    
    public init(glucose: Double, iob: Double, cob: Double, timestamp: Date) {
        self.glucose = glucose
        self.iob = iob
        self.cob = cob
        self.timestamp = timestamp
    }
}

/// A single algorithm scenario in what-if report
public struct WhatIfScenario: Sendable, Codable, Identifiable {
    public let id: UUID
    public let algorithmId: String
    public let suggestedRate: Double?
    public let suggestedBolus: Double?
    public let reason: String
    public let divergenceLevel: String
    public let isEquivalent: Bool
    
    public init(
        id: UUID = UUID(),
        algorithmId: String,
        suggestedRate: Double?,
        suggestedBolus: Double?,
        reason: String,
        divergenceLevel: String,
        isEquivalent: Bool
    ) {
        self.id = id
        self.algorithmId = algorithmId
        self.suggestedRate = suggestedRate
        self.suggestedBolus = suggestedBolus
        self.reason = reason
        self.divergenceLevel = divergenceLevel
        self.isEquivalent = isEquivalent
    }
}

/// Summary for what-if report
public struct WhatIfSummary: Sendable, Codable {
    public let totalAlgorithms: Int
    public let agreementCount: Int
    public let divergentCount: Int
    public let hasSignificantDivergence: Bool
    
    public init(totalAlgorithms: Int, agreementCount: Int, divergentCount: Int, hasSignificantDivergence: Bool) {
        self.totalAlgorithms = totalAlgorithms
        self.agreementCount = agreementCount
        self.divergentCount = divergentCount
        self.hasSignificantDivergence = hasSignificantDivergence
    }
}

/// Batch what-if report for multiple sessions
public struct BatchWhatIfReport: Sendable, Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let generatedAt: Date
    public let reports: [WhatIfReport]
    public let batchSummary: BatchWhatIfSummary
    
    public init(
        id: UUID = UUID(),
        title: String,
        generatedAt: Date,
        reports: [WhatIfReport],
        batchSummary: BatchWhatIfSummary
    ) {
        self.id = id
        self.title = title
        self.generatedAt = generatedAt
        self.reports = reports
        self.batchSummary = batchSummary
    }
}

/// Summary for batch what-if report
public struct BatchWhatIfSummary: Sendable, Codable {
    public let totalSessions: Int
    public let totalComparisons: Int
    public let overallAgreementRatio: Double
    public let sessionsWithDivergence: Int
    
    public init(totalSessions: Int, totalComparisons: Int, overallAgreementRatio: Double, sessionsWithDivergence: Int) {
        self.totalSessions = totalSessions
        self.totalComparisons = totalComparisons
        self.overallAgreementRatio = overallAgreementRatio
        self.sessionsWithDivergence = sessionsWithDivergence
    }
}

// MARK: - Algorithm Replay Runner

/// Actor for replaying recorded sessions through algorithms
public actor AlgorithmReplayRunner {
    
    // MARK: - Configuration
    
    /// Threshold for minor divergence (U/hr)
    public var minorThreshold: Double = 0.1
    
    /// Threshold for moderate divergence (U/hr)
    public var moderateThreshold: Double = 0.5
    
    /// Algorithms to use for replay
    private var algorithmIds: [String]
    
    // MARK: - State
    
    /// Replay history
    private var history: [AlgorithmReplayReport] = []
    
    /// Maximum history size
    private let maxHistory: Int
    
    // MARK: - Initialization
    
    public init(
        algorithmIds: [String] = [],
        maxHistory: Int = 1000
    ) {
        self.algorithmIds = algorithmIds.isEmpty ? AlgorithmRegistry.shared.registeredNames : algorithmIds
        self.maxHistory = maxHistory
    }
    
    // MARK: - Configuration
    
    /// Set algorithms to use for replay
    public func setAlgorithms(_ ids: [String]) {
        algorithmIds = ids
    }
    
    /// Get configured algorithms
    public func getAlgorithms() -> [String] {
        algorithmIds
    }
    
    // MARK: - Single Session Replay
    
    /// Replay a single recorded session through all configured algorithms
    public func replay(session: RecordedSession) async -> AlgorithmReplayReport {
        let inputs = session.inputs.toAlgorithmInputs()
        var results: [AlgorithmReplayResult] = []
        
        for algorithmId in algorithmIds {
            let result = await replayWithAlgorithm(
                session: session,
                inputs: inputs,
                algorithmId: algorithmId
            )
            results.append(result)
        }
        
        let summary = generateSummary(results: results)
        let report = AlgorithmReplayReport(
            session: session,
            results: results,
            summary: summary
        )
        
        // Store in history
        history.append(report)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        
        return report
    }
    
    /// Replay session with a specific algorithm
    private func replayWithAlgorithm(
        session: RecordedSession,
        inputs: AlgorithmInputs,
        algorithmId: String
    ) async -> AlgorithmReplayResult {
        let startTime = Date()
        
        guard let engine = AlgorithmRegistry.shared.algorithm(named: algorithmId) else {
            let output = RecordedOutput(
                algorithmId: algorithmId,
                reason: "Algorithm not found",
                success: false,
                error: "Algorithm '\(algorithmId)' not registered"
            )
            return AlgorithmReplayResult(
                sessionId: session.id,
                algorithmId: algorithmId,
                originalOutput: findOriginalOutput(session: session, algorithmId: algorithmId),
                replayOutput: output,
                divergence: AlgorithmDivergence(isEquivalent: false, level: .significant, summary: "Algorithm not found")
            )
        }
        
        do {
            let decision = try engine.calculate(inputs)
            let executionTimeMs = Date().timeIntervalSince(startTime) * 1000
            
            let output = RecordedOutput(
                algorithmId: algorithmId,
                tempBasalRate: decision.suggestedTempBasal?.rate,
                tempBasalDuration: decision.suggestedTempBasal?.duration,
                suggestedBolus: decision.suggestedBolus,
                reason: decision.reason,
                executionTimeMs: executionTimeMs,
                success: true
            )
            
            let originalOutput = findOriginalOutput(session: session, algorithmId: algorithmId)
            let divergence = calculateDivergence(original: originalOutput, replay: output)
            
            return AlgorithmReplayResult(
                sessionId: session.id,
                algorithmId: algorithmId,
                originalOutput: originalOutput,
                replayOutput: output,
                divergence: divergence
            )
        } catch {
            let executionTimeMs = Date().timeIntervalSince(startTime) * 1000
            let output = RecordedOutput(
                algorithmId: algorithmId,
                reason: error.localizedDescription,
                executionTimeMs: executionTimeMs,
                success: false,
                error: error.localizedDescription
            )
            return AlgorithmReplayResult(
                sessionId: session.id,
                algorithmId: algorithmId,
                originalOutput: findOriginalOutput(session: session, algorithmId: algorithmId),
                replayOutput: output,
                divergence: AlgorithmDivergence(isEquivalent: false, level: .significant, summary: "Replay error: \(error.localizedDescription)")
            )
        }
    }
    
    /// Find original output for algorithm in session
    private func findOriginalOutput(session: RecordedSession, algorithmId: String) -> RecordedOutput? {
        session.outputs.first { $0.algorithmId == algorithmId }
    }
    
    /// Calculate divergence between original and replay outputs
    private func calculateDivergence(original: RecordedOutput?, replay: RecordedOutput) -> AlgorithmDivergence {
        guard let original = original else {
            return AlgorithmDivergence(
                isEquivalent: false,
                level: .none,
                summary: "No original output for comparison"
            )
        }
        
        let originalRate = original.tempBasalRate ?? 0
        let replayRate = replay.tempBasalRate ?? 0
        let rateDiff = Swift.abs(replayRate - originalRate)
        
        let originalBolus = original.suggestedBolus ?? 0
        let replayBolus = replay.suggestedBolus ?? 0
        let bolusDiff = Swift.abs(replayBolus - originalBolus)
        
        // Check for opposite direction
        let originalDirection = sign(originalRate - 1.0) // > 1.0 = increase, < 1.0 = decrease
        let replayDirection = sign(replayRate - 1.0)
        let oppositeDirection = originalDirection != 0 && replayDirection != 0 && originalDirection != replayDirection
        
        let level: AlgorithmDivergence.DivergenceLevel
        let summary: String
        
        if oppositeDirection && rateDiff > minorThreshold {
            level = .opposite
            summary = "Opposite direction: original \(String(format: "%.2f", originalRate)) vs replay \(String(format: "%.2f", replayRate)) U/hr"
        } else if rateDiff > moderateThreshold || bolusDiff > 0.5 {
            level = .significant
            summary = "Significant divergence: \(String(format: "%.2f", rateDiff)) U/hr difference"
        } else if rateDiff > minorThreshold || bolusDiff > 0.1 {
            level = .moderate
            summary = "Moderate divergence: \(String(format: "%.2f", rateDiff)) U/hr difference"
        } else if rateDiff > 0.01 || bolusDiff > 0.01 {
            level = .minor
            summary = "Minor divergence: \(String(format: "%.3f", rateDiff)) U/hr difference"
        } else {
            level = .none
            summary = "Equivalent results"
        }
        
        return AlgorithmDivergence(
            isEquivalent: level == .none || level == .minor,
            tempBasalRateDiff: rateDiff,
            bolusDiff: bolusDiff,
            level: level,
            summary: summary
        )
    }
    
    /// Generate summary from replay results
    private func generateSummary(results: [AlgorithmReplayResult]) -> AlgorithmReplaySummary {
        var equivalentCount = 0
        var minorCount = 0
        var moderateCount = 0
        var significantCount = 0
        var oppositeCount = 0
        var totalExecutionTime: Double = 0
        
        for result in results {
            switch result.divergence.level {
            case .none:
                equivalentCount += 1
            case .minor:
                minorCount += 1
            case .moderate:
                moderateCount += 1
            case .significant:
                significantCount += 1
            case .opposite:
                oppositeCount += 1
            }
            totalExecutionTime += result.replayOutput.executionTimeMs
        }
        
        let avgTime = results.isEmpty ? 0 : totalExecutionTime / Double(results.count)
        
        return AlgorithmReplaySummary(
            totalAlgorithms: results.count,
            equivalentCount: equivalentCount,
            minorDivergenceCount: minorCount,
            moderateDivergenceCount: moderateCount,
            significantDivergenceCount: significantCount,
            oppositeDivergenceCount: oppositeCount,
            averageExecutionTimeMs: avgTime
        )
    }
    
    // MARK: - Batch Replay
    
    /// Replay multiple sessions
    public func replayBatch(sessions: [RecordedSession]) async -> BatchAlgorithmReplayReport {
        var sessionReports: [AlgorithmReplayReport] = []
        
        for session in sessions {
            let report = await replay(session: session)
            sessionReports.append(report)
        }
        
        let batchSummary = generateBatchSummary(reports: sessionReports)
        
        return BatchAlgorithmReplayReport(
            sessionReports: sessionReports,
            batchSummary: batchSummary
        )
    }
    
    /// Generate batch summary
    private func generateBatchSummary(reports: [AlgorithmReplayReport]) -> BatchAlgorithmReplaySummary {
        var totalResults = 0
        var totalEquivalent = 0
        var sessionsWithSignificant = 0
        var algorithmStats: [String: (total: Int, equivalent: Int, time: Double, errors: Int)] = [:]
        
        for report in reports {
            if report.summary.hasSignificantDivergence {
                sessionsWithSignificant += 1
            }
            
            for result in report.results {
                totalResults += 1
                if result.divergence.isEquivalent {
                    totalEquivalent += 1
                }
                
                var stat = algorithmStats[result.algorithmId] ?? (0, 0, 0, 0)
                stat.total += 1
                if result.divergence.isEquivalent {
                    stat.equivalent += 1
                }
                stat.time += result.replayOutput.executionTimeMs
                if !result.replayOutput.success {
                    stat.errors += 1
                }
                algorithmStats[result.algorithmId] = stat
            }
        }
        
        let agreementRatio = totalResults > 0 ? Double(totalEquivalent) / Double(totalResults) : 0
        
        let stats = algorithmStats.mapValues { stat in
            AlgorithmReplayStat(
                algorithmId: "",  // Will be set by key
                totalReplays: stat.total,
                equivalentCount: stat.equivalent,
                averageExecutionTimeMs: stat.total > 0 ? stat.time / Double(stat.total) : 0,
                errorCount: stat.errors
            )
        }
        
        // Fix algorithm IDs
        var fixedStats: [String: AlgorithmReplayStat] = [:]
        for (id, stat) in stats {
            fixedStats[id] = AlgorithmReplayStat(
                algorithmId: id,
                totalReplays: stat.totalReplays,
                equivalentCount: stat.equivalentCount,
                averageExecutionTimeMs: stat.averageExecutionTimeMs,
                errorCount: stat.errorCount
            )
        }
        
        return BatchAlgorithmReplaySummary(
            totalSessions: reports.count,
            totalAlgorithmReplayResults: totalResults,
            overallAgreementRatio: agreementRatio,
            sessionsWithSignificantDivergence: sessionsWithSignificant,
            algorithmStats: fixedStats
        )
    }
    
    // MARK: - History Access
    
    /// Get all replay history
    public func allHistory() -> [AlgorithmReplayReport] {
        history
    }
    
    /// Get recent replay history
    public func recentHistory(count: Int = 100) -> [AlgorithmReplayReport] {
        Array(history.suffix(count))
    }
    
    /// Clear history
    public func clearHistory() {
        history.removeAll()
    }
    
    // MARK: - Export
    
    /// Export batch report as JSON
    public func exportReport(_ report: BatchAlgorithmReplayReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    
    /// Export session report as JSON
    public func exportSessionReport(_ report: AlgorithmReplayReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    
    // MARK: - What-If Reports (ALG-SHADOW-014)
    
    /// Generate a what-if comparison report in markdown format
    public func generateWhatIfReport(
        session: RecordedSession,
        title: String = "What-If Algorithm Comparison"
    ) async -> WhatIfReport {
        let replayReport = await replay(session: session)
        
        let scenarios = replayReport.results.map { result in
            WhatIfScenario(
                algorithmId: result.algorithmId,
                suggestedRate: result.replayOutput.tempBasalRate,
                suggestedBolus: result.replayOutput.suggestedBolus,
                reason: result.replayOutput.reason,
                divergenceLevel: result.divergence.level.rawValue,
                isEquivalent: result.divergence.isEquivalent
            )
        }
        
        return WhatIfReport(
            title: title,
            generatedAt: Date(),
            inputSummary: WhatIfInputSummary(
                glucose: session.inputs.glucose.first?.value ?? 0,
                iob: session.inputs.insulinOnBoard,
                cob: session.inputs.carbsOnBoard,
                timestamp: session.timestamp
            ),
            scenarios: scenarios,
            summary: WhatIfSummary(
                totalAlgorithms: scenarios.count,
                agreementCount: scenarios.filter { $0.isEquivalent }.count,
                divergentCount: scenarios.filter { !$0.isEquivalent }.count,
                hasSignificantDivergence: replayReport.summary.hasSignificantDivergence
            )
        )
    }
    
    /// Generate markdown output from what-if report
    public func formatAsMarkdown(_ report: WhatIfReport) -> String {
        var md = "# \(report.title)\n\n"
        md += "Generated: \(formatDate(report.generatedAt))\n\n"
        
        // Input summary
        md += "## Input State\n\n"
        md += "| Parameter | Value |\n"
        md += "|-----------|-------|\n"
        md += "| Glucose | \(String(format: "%.0f", report.inputSummary.glucose)) mg/dL |\n"
        md += "| IOB | \(String(format: "%.2f", report.inputSummary.iob)) U |\n"
        md += "| COB | \(String(format: "%.0f", report.inputSummary.cob)) g |\n\n"
        
        // Algorithm comparison
        md += "## Algorithm Recommendations\n\n"
        md += "| Algorithm | Temp Basal | Bolus | Divergence | Reason |\n"
        md += "|-----------|------------|-------|------------|--------|\n"
        
        for scenario in report.scenarios {
            let rate = scenario.suggestedRate.map { String(format: "%.2f U/hr", $0) } ?? "No change"
            let bolus = scenario.suggestedBolus.map { String(format: "%.2f U", $0) } ?? "-"
            let divergence = scenario.isEquivalent ? "✅ \(scenario.divergenceLevel)" : "⚠️ \(scenario.divergenceLevel)"
            let reason = String(scenario.reason.prefix(40)) + (scenario.reason.count > 40 ? "..." : "")
            md += "| \(scenario.algorithmId) | \(rate) | \(bolus) | \(divergence) | \(reason) |\n"
        }
        md += "\n"
        
        // Summary
        md += "## Summary\n\n"
        md += "- **Algorithms compared**: \(report.summary.totalAlgorithms)\n"
        md += "- **Agreement**: \(report.summary.agreementCount)/\(report.summary.totalAlgorithms)\n"
        md += "- **Divergent**: \(report.summary.divergentCount)\n"
        
        if report.summary.hasSignificantDivergence {
            md += "\n⚠️ **Significant divergence detected** - algorithms disagree substantially\n"
        } else {
            md += "\n✅ **Algorithms mostly agree** on treatment approach\n"
        }
        
        return md
    }
    
    /// Generate batch what-if report from multiple sessions
    public func generateBatchWhatIfReport(
        sessions: [RecordedSession],
        title: String = "Batch What-If Analysis"
    ) async -> BatchWhatIfReport {
        var reports: [WhatIfReport] = []
        
        for (index, session) in sessions.enumerated() {
            let report = await generateWhatIfReport(
                session: session,
                title: "Scenario \(index + 1)"
            )
            reports.append(report)
        }
        
        let totalScenarios = reports.flatMap { $0.scenarios }.count
        let agreementCount = reports.flatMap { $0.scenarios }.filter { $0.isEquivalent }.count
        
        return BatchWhatIfReport(
            title: title,
            generatedAt: Date(),
            reports: reports,
            batchSummary: BatchWhatIfSummary(
                totalSessions: sessions.count,
                totalComparisons: totalScenarios,
                overallAgreementRatio: totalScenarios > 0 ? Double(agreementCount) / Double(totalScenarios) : 0,
                sessionsWithDivergence: reports.filter { $0.summary.hasSignificantDivergence }.count
            )
        )
    }
    
    /// Format batch report as markdown
    public func formatBatchAsMarkdown(_ report: BatchWhatIfReport) -> String {
        var md = "# \(report.title)\n\n"
        md += "Generated: \(formatDate(report.generatedAt))\n\n"
        
        // Batch summary
        md += "## Overall Summary\n\n"
        md += "- **Sessions analyzed**: \(report.batchSummary.totalSessions)\n"
        md += "- **Total comparisons**: \(report.batchSummary.totalComparisons)\n"
        md += "- **Agreement ratio**: \(String(format: "%.1f%%", report.batchSummary.overallAgreementRatio * 100))\n"
        md += "- **Sessions with divergence**: \(report.batchSummary.sessionsWithDivergence)\n\n"
        
        // Individual reports
        for (index, subReport) in report.reports.enumerated() {
            md += "---\n\n"
            md += "## Session \(index + 1): BG \(String(format: "%.0f", subReport.inputSummary.glucose)) mg/dL\n\n"
            
            md += "| Algorithm | Temp Basal | Divergence |\n"
            md += "|-----------|------------|------------|\n"
            
            for scenario in subReport.scenarios {
                let rate = scenario.suggestedRate.map { String(format: "%.2f U/hr", $0) } ?? "No change"
                let status = scenario.isEquivalent ? "✅" : "⚠️"
                md += "| \(scenario.algorithmId) | \(rate) | \(status) \(scenario.divergenceLevel) |\n"
            }
            md += "\n"
        }
        
        return md
    }
    
    /// Export what-if report as JSON
    public func exportWhatIfReport(_ report: WhatIfReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    
    /// Export batch what-if report as JSON
    public func exportBatchWhatIfReport(_ report: BatchWhatIfReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }
}

// MARK: - Helper

private func sign(_ value: Double) -> Int {
    if value > 0 { return 1 }
    if value < 0 { return -1 }
    return 0
}
