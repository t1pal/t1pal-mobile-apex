// ISFLearner.swift
// T1PalAlgorithm
//
// ISF learner with outcome-based adaptive adjustment
// Source: GlucOS AdaptiveSchedule pattern
// Trace: GLUCOS-IMPL-001, ADR-010

import Foundation

/// Simple ISF learner based on outcomes
/// Source: GlucOS adaptive schedule pattern
public actor ISFLearner: AdaptiveTuningProvider {
    /// Learned adjustments per time block (multiplier)
    private var blockAdjustments: [Int: Double] = [:]
    
    /// Outcome history for learning
    private var outcomes: [TuningOutcome] = []
    
    /// Minimum outcomes needed per block before learning
    private let minOutcomesPerBlock: Int
    
    /// Maximum age of outcomes to consider (seconds)
    private let maxOutcomeAge: TimeInterval
    
    /// Safe adjustment range (0.7x to 1.3x)
    private let minAdjustment: Double = 0.7
    private let maxAdjustment: Double = 1.3
    
    public init(
        minOutcomesPerBlock: Int = 7,
        maxOutcomeAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    ) {
        self.minOutcomesPerBlock = minOutcomesPerBlock
        self.maxOutcomeAge = maxOutcomeAge
    }
    
    public var hasLearnedData: Bool {
        !blockAdjustments.isEmpty
    }
    
    /// Get number of outcomes stored
    public var outcomeCount: Int {
        outcomes.count
    }
    
    /// Get current adjustments for testing
    public var currentAdjustments: [Int: Double] {
        blockAdjustments
    }
    
    public func adjustedISF(baseISF: Double, at date: Date) async -> AdaptedParameter {
        let block = TimeBlockCalculator.timeBlock(for: date)
        
        if let adjustment = blockAdjustments[block] {
            return AdaptedParameter(
                baseValue: baseISF,
                adjustedValue: baseISF * adjustment,
                confidence: confidenceForBlock(block),
                source: .learned
            )
        }
        
        return AdaptedParameter.passThrough(baseISF)
    }
    
    public func adjustedCarbRatio(baseRatio: Double, at date: Date) async -> AdaptedParameter {
        // CR learning follows same pattern but not implemented yet
        AdaptedParameter.passThrough(baseRatio)
    }
    
    public func recordOutcome(_ outcome: TuningOutcome) async {
        outcomes.append(outcome)
        pruneOldOutcomes()
        updateLearning()
    }
    
    /// Reset all learned data
    public func reset() {
        blockAdjustments.removeAll()
        outcomes.removeAll()
    }
    
    private func pruneOldOutcomes() {
        let cutoff = Date().addingTimeInterval(-maxOutcomeAge)
        outcomes.removeAll { $0.timestamp < cutoff }
    }
    
    private func updateLearning() {
        // Group by time block
        var blockOutcomes: [Int: [TuningOutcome]] = [:]
        for outcome in outcomes {
            let block = outcome.timeBlock
            blockOutcomes[block, default: []].append(outcome)
        }
        
        // Calculate adjustment for each block with sufficient data
        for (block, blockData) in blockOutcomes {
            guard blockData.count >= minOutcomesPerBlock else { continue }
            
            // Filter out meal times (carbs > 5g may skew learning)
            let cleanOutcomes = blockData.filter { $0.carbsConsumed < 5 }
            guard cleanOutcomes.count >= minOutcomesPerBlock / 2 else { continue }
            
            // Calculate average prediction error
            let avgError = cleanOutcomes.reduce(0.0) { $0 + $1.predictionError } / Double(cleanOutcomes.count)
            
            // Convert error to ISF adjustment
            // Positive error (actual > predicted) → decrease ISF (more aggressive)
            // Negative error (actual < predicted) → increase ISF (less aggressive)
            let adjustment = 1.0 - (avgError / 100.0)  // 100 mg/dL error = 100% adjustment
            
            // Clamp adjustment to safe range
            blockAdjustments[block] = max(minAdjustment, min(maxAdjustment, adjustment))
        }
    }
    
    private func confidenceForBlock(_ block: Int) -> Double {
        let blockData = outcomes.filter { TimeBlockCalculator.timeBlock(for: $0.timestamp) == block }
        let count = blockData.count
        
        // Scale confidence based on data volume
        // 7 outcomes = 0.5, 14+ outcomes = 0.9
        let baseConfidence = 0.5
        let maxConfidence = 0.9
        let scale = min(1.0, Double(count - minOutcomesPerBlock) / Double(minOutcomesPerBlock))
        
        return baseConfidence + (maxConfidence - baseConfidence) * scale
    }
}

/// PID integrator tracking glucose delta errors
/// Source: GlucOS PhysiologicalModels
public actor DeltaGlucoseIntegrator {
    /// Integration constant (accumulated error)
    private var ki: Double = 0
    
    /// Maximum integration magnitude
    private let maxKi: Double
    
    /// Decay factor per iteration (prevents windup)
    private let decayFactor: Double
    
    public init(
        maxKi: Double = 2.0,
        decayFactor: Double = 0.95
    ) {
        self.maxKi = maxKi
        self.decayFactor = decayFactor
    }
    
    /// Update integrator with new glucose delta error
    public func update(deltaError: Double, at date: Date) -> Double {
        // Decay existing value
        ki *= decayFactor
        
        // Add new error contribution
        ki += deltaError * 0.1  // Scaled integration
        
        // Clamp to prevent windup
        ki = max(-maxKi, min(maxKi, ki))
        
        return ki
    }
    
    /// Get current integration value
    public var currentKi: Double {
        ki
    }
    
    /// Reset integrator (e.g., after meal)
    public func reset() {
        ki = 0
    }
}
