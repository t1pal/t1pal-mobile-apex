// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ShadowAlgorithmRunner.swift
// T1Pal Mobile
//
// Shadow mode: runs multiple algorithms in parallel without enacting.
// Compares what each algorithm would recommend for live operation.
//
// Task: ALG-SHADOW-001, ALG-SHADOW-002
// Requirements: ADR-010 (GlucOS Research)

import Foundation
import T1PalCore

// MARK: - Shadow Recommendation

/// A recommendation from a shadow algorithm (not enacted)
public struct ShadowRecommendation: Sendable, Codable, Equatable {
    /// Algorithm that produced this recommendation
    public let algorithmId: String
    
    /// Algorithm display name
    public let algorithmName: String
    
    /// Timestamp when recommendation was calculated
    public let timestamp: Date
    
    /// Suggested temp basal rate (U/hr), nil if no change
    public let suggestedTempBasalRate: Double?
    
    /// Suggested temp basal duration (seconds)
    public let suggestedTempBasalDuration: TimeInterval?
    
    /// Suggested bolus (U), nil if none
    public let suggestedBolus: Double?
    
    /// Algorithm's reasoning
    public let reason: String
    
    /// Predicted eventual BG (mg/dL)
    public let eventualBG: Double?
    
    /// Execution time in milliseconds
    public let executionTimeMs: Double
    
    /// Whether calculation succeeded
    public let success: Bool
    
    /// Error message if failed
    public let error: String?
    
    public init(
        algorithmId: String,
        algorithmName: String,
        timestamp: Date = Date(),
        suggestedTempBasalRate: Double? = nil,
        suggestedTempBasalDuration: TimeInterval? = nil,
        suggestedBolus: Double? = nil,
        reason: String = "",
        eventualBG: Double? = nil,
        executionTimeMs: Double = 0,
        success: Bool = true,
        error: String? = nil
    ) {
        self.algorithmId = algorithmId
        self.algorithmName = algorithmName
        self.timestamp = timestamp
        self.suggestedTempBasalRate = suggestedTempBasalRate
        self.suggestedTempBasalDuration = suggestedTempBasalDuration
        self.suggestedBolus = suggestedBolus
        self.reason = reason
        self.eventualBG = eventualBG
        self.executionTimeMs = executionTimeMs
        self.success = success
        self.error = error
    }
}

// MARK: - Shadow Run Result

/// Results from a single shadow run across all configured algorithms
public struct ShadowRunResult: Sendable, Codable {
    /// Timestamp of this shadow run
    public let timestamp: Date
    
    /// Input glucose at time of run
    public let inputGlucose: Double
    
    /// Input IOB at time of run
    public let inputIOB: Double
    
    /// Input COB at time of run
    public let inputCOB: Double
    
    /// Recommendations from each algorithm
    public let recommendations: [ShadowRecommendation]
    
    /// Primary algorithm ID (the one actually being used for dosing)
    public let primaryAlgorithmId: String?
    
    public init(
        timestamp: Date = Date(),
        inputGlucose: Double,
        inputIOB: Double,
        inputCOB: Double,
        recommendations: [ShadowRecommendation],
        primaryAlgorithmId: String? = nil
    ) {
        self.timestamp = timestamp
        self.inputGlucose = inputGlucose
        self.inputIOB = inputIOB
        self.inputCOB = inputCOB
        self.recommendations = recommendations
        self.primaryAlgorithmId = primaryAlgorithmId
    }
    
    /// Check if all algorithms agree on the action
    public var isUnanimous: Bool {
        guard recommendations.count >= 2 else { return true }
        let successfulRecs = recommendations.filter { $0.success }
        guard successfulRecs.count >= 2 else { return true }
        
        // Check if all suggest similar temp basal (within 0.1 U/hr)
        let rates = successfulRecs.compactMap { $0.suggestedTempBasalRate }
        if rates.count >= 2 {
            let minRate = rates.min() ?? 0
            let maxRate = rates.max() ?? 0
            if maxRate - minRate > 0.1 {
                return false
            }
        }
        
        return true
    }
    
    /// Get the recommendation from the primary algorithm
    public var primaryRecommendation: ShadowRecommendation? {
        guard let primaryId = primaryAlgorithmId else { return recommendations.first }
        return recommendations.first { $0.algorithmId == primaryId }
    }
    
    /// Get recommendations that diverge from the primary
    public var divergingRecommendations: [ShadowRecommendation] {
        guard let primary = primaryRecommendation else { return [] }
        return recommendations.filter { rec in
            guard rec.algorithmId != primary.algorithmId, rec.success else { return false }
            
            // Check for rate divergence (>0.1 U/hr difference)
            if let primaryRate = primary.suggestedTempBasalRate,
               let recRate = rec.suggestedTempBasalRate {
                if abs(primaryRate - recRate) > 0.1 {
                    return true
                }
            }
            
            // Check for bolus divergence
            if let primaryBolus = primary.suggestedBolus,
               let recBolus = rec.suggestedBolus {
                if abs(primaryBolus - recBolus) > 0.05 {
                    return true
                }
            }
            
            return false
        }
    }
}

// MARK: - Shadow Algorithm Runner

/// Runs multiple algorithms in shadow mode for comparison.
/// Shadow recommendations are stored but never enacted.
///
/// Usage:
/// ```swift
/// let runner = ShadowAlgorithmRunner()
/// await runner.configure(algorithms: ["oref0", "Loop", "GlucOS"], primary: "oref0")
/// let result = await runner.run(inputs: algorithmInputs)
/// ```
public actor ShadowAlgorithmRunner {
    
    // MARK: - Properties
    
    /// Algorithm IDs to run in shadow mode
    private var shadowAlgorithmIds: [String] = []
    
    /// Primary algorithm ID (the one used for actual dosing)
    private var primaryAlgorithmId: String?
    
    /// History of shadow runs (circular buffer)
    private var runHistory: [ShadowRunResult] = []
    
    /// Maximum history size
    private let maxHistorySize: Int
    
    /// Whether shadow mode is enabled
    private var isEnabled: Bool = false
    
    // MARK: - Initialization
    
    public init(maxHistorySize: Int = 288) {  // 24 hours at 5-min intervals
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Configuration
    
    /// Configure which algorithms to run in shadow mode.
    /// - Parameters:
    ///   - algorithms: Algorithm IDs to run
    ///   - primary: Primary algorithm ID (for comparison baseline)
    public func configure(algorithms: [String], primary: String? = nil) {
        self.shadowAlgorithmIds = algorithms
        self.primaryAlgorithmId = primary ?? algorithms.first
        self.isEnabled = !algorithms.isEmpty
    }
    
    /// Enable or disable shadow mode
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    /// Check if shadow mode is enabled
    public var enabled: Bool {
        isEnabled && !shadowAlgorithmIds.isEmpty
    }
    
    /// Get configured algorithm IDs
    public var algorithmIds: [String] {
        shadowAlgorithmIds
    }
    
    // MARK: - Execution (ALG-SHADOW-002)
    
    /// Run all shadow algorithms on the given inputs.
    /// Results are stored in history but never enacted.
    /// - Parameter inputs: Algorithm inputs
    /// - Returns: Shadow run result with all recommendations
    public func run(inputs: AlgorithmInputs) async -> ShadowRunResult {
        guard isEnabled else {
            return ShadowRunResult(
                inputGlucose: inputs.glucose.first?.glucose ?? 0,
                inputIOB: inputs.insulinOnBoard,
                inputCOB: inputs.carbsOnBoard,
                recommendations: [],
                primaryAlgorithmId: primaryAlgorithmId
            )
        }
        
        let registry = AlgorithmRegistry.shared
        var recommendations: [ShadowRecommendation] = []
        
        // Run each algorithm
        for algorithmId in shadowAlgorithmIds {
            let recommendation = await runSingleAlgorithm(
                algorithmId: algorithmId,
                inputs: inputs,
                registry: registry
            )
            recommendations.append(recommendation)
        }
        
        let result = ShadowRunResult(
            inputGlucose: inputs.glucose.first?.glucose ?? 0,
            inputIOB: inputs.insulinOnBoard,
            inputCOB: inputs.carbsOnBoard,
            recommendations: recommendations,
            primaryAlgorithmId: primaryAlgorithmId
        )
        
        // Store in history
        storeResult(result)
        
        return result
    }
    
    /// Run a single algorithm and return its recommendation
    private func runSingleAlgorithm(
        algorithmId: String,
        inputs: AlgorithmInputs,
        registry: AlgorithmRegistry
    ) async -> ShadowRecommendation {
        guard let algorithm = registry.algorithm(named: algorithmId) else {
            return ShadowRecommendation(
                algorithmId: algorithmId,
                algorithmName: algorithmId,
                reason: "Algorithm not found in registry",
                success: false,
                error: "Algorithm '\(algorithmId)' not registered"
            )
        }
        
        let startTime = DispatchTime.now()
        
        do {
            let decision = try algorithm.calculate(inputs)
            
            let endTime = DispatchTime.now()
            let timeMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            // Extract eventual BG from predictions
            let eventualBG: Double?
            if let predictions = decision.predictions, !predictions.iob.isEmpty {
                eventualBG = predictions.iob.last
            } else {
                eventualBG = nil
            }
            
            return ShadowRecommendation(
                algorithmId: algorithmId,
                algorithmName: algorithm.name,
                suggestedTempBasalRate: decision.suggestedTempBasal?.rate,
                suggestedTempBasalDuration: decision.suggestedTempBasal?.duration,
                suggestedBolus: decision.suggestedBolus,
                reason: decision.reason,
                eventualBG: eventualBG,
                executionTimeMs: timeMs
            )
        } catch {
            let endTime = DispatchTime.now()
            let timeMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            return ShadowRecommendation(
                algorithmId: algorithmId,
                algorithmName: algorithm.name,
                reason: error.localizedDescription,
                executionTimeMs: timeMs,
                success: false,
                error: "\(error)"
            )
        }
    }
    
    // MARK: - History (ALG-SHADOW-003)
    
    /// Store a shadow run result in history
    private func storeResult(_ result: ShadowRunResult) {
        runHistory.append(result)
        
        // Trim to max size
        if runHistory.count > maxHistorySize {
            runHistory.removeFirst(runHistory.count - maxHistorySize)
        }
    }
    
    /// Get recent shadow run history
    /// - Parameter count: Number of recent results to return
    /// - Returns: Recent shadow run results (newest first)
    public func recentHistory(count: Int = 12) -> [ShadowRunResult] {
        let results = Array(runHistory.suffix(count))
        return results.reversed()
    }
    
    /// Clear shadow run history
    public func clearHistory() {
        runHistory.removeAll()
    }
    
    /// Get divergence statistics from history
    public func divergenceStats() -> DivergenceStats {
        let total = runHistory.count
        let unanimous = runHistory.filter { $0.isUnanimous }.count
        let divergent = total - unanimous
        
        return DivergenceStats(
            totalRuns: total,
            unanimousRuns: unanimous,
            divergentRuns: divergent,
            divergenceRate: total > 0 ? Double(divergent) / Double(total) : 0
        )
    }
}

// MARK: - Divergence Stats

/// Statistics about algorithm divergence
public struct DivergenceStats: Sendable, Codable {
    public let totalRuns: Int
    public let unanimousRuns: Int
    public let divergentRuns: Int
    public let divergenceRate: Double
    
    public init(totalRuns: Int, unanimousRuns: Int, divergentRuns: Int, divergenceRate: Double) {
        self.totalRuns = totalRuns
        self.unanimousRuns = unanimousRuns
        self.divergentRuns = divergentRuns
        self.divergenceRate = divergenceRate
    }
}
