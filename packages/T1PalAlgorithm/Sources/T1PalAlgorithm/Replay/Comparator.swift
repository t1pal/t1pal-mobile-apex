// Comparator.swift
// T1PalAlgorithm
//
// ALG-ARCH-009: Compares our calculations against Loop's reported values.
// ALG-REFACTOR-004: Uses ComparisonConfig for configurable tolerances.
// Design: docs/architecture/ALG-ARCH-002-005-design.md

import Foundation

/// Compares our calculations against Loop's reported values.
public enum Comparator {
    
    // MARK: - IOB Comparison
    
    /// Compare our IOB against Loop's reported IOB
    public static func compareIOB(
        ours: Double,
        loops: Double,
        config: ComparisonConfig = .default
    ) -> IOBComparison {
        let delta = ours - loops
        let percentError = loops != 0 ? abs(delta / loops) * 100 : (ours == 0 ? 0 : 100)
        
        return IOBComparison(
            ourIOB: ours,
            loopIOB: loops,
            delta: delta,
            percentError: percentError,
            withinTolerance: abs(delta) <= config.iobTolerance
        )
    }
    
    // MARK: - Prediction Comparison
    
    /// Compare our prediction array against Loop's
    public static func comparePrediction(
        ours: [Double],
        loops: [Int],
        config: ComparisonConfig = .default
    ) -> PredictionComparison {
        let loopsDouble = loops.map(Double.init)
        
        // Ensure same length
        let minCount = min(ours.count, loopsDouble.count)
        guard minCount > 0 else {
            return PredictionComparison(
                ourPrediction: ours,
                loopPrediction: loopsDouble,
                pointDeltas: [],
                mae: 0,
                maxDelta: 0,
                eventualDelta: 0,
                significance: .none,
                withinTolerance: true
            )
        }
        
        let oursTrimmed = Array(ours.prefix(minCount))
        let loopsTrimmed = Array(loopsDouble.prefix(minCount))
        
        // Point-by-point deltas
        let deltas = zip(oursTrimmed, loopsTrimmed).map { $0 - $1 }
        
        // Statistics
        let mae = deltas.map(abs).reduce(0, +) / Double(deltas.count)
        let maxDelta = deltas.map(abs).max() ?? 0
        let eventualDelta = deltas.last ?? 0
        
        // Significance classification
        let significance = classifySignificance(mae: mae, eventualDelta: eventualDelta, config: config)
        
        return PredictionComparison(
            ourPrediction: oursTrimmed,
            loopPrediction: loopsTrimmed,
            pointDeltas: deltas,
            mae: mae,
            maxDelta: maxDelta,
            eventualDelta: eventualDelta,
            significance: significance,
            withinTolerance: mae <= config.maeTolerance
        )
    }
    
    // MARK: - Dosing Comparison
    
    /// Compare our recommendation against Loop's
    public static func compareDosing(
        ours: ReplayDoseRecommendation?,
        loops: ReplayDoseRecommendation?,
        config: ComparisonConfig = .default
    ) -> DosingComparison {
        guard let ours = ours, let loops = loops else {
            return DosingComparison(
                ourRecommendation: ours,
                loopRecommendation: loops,
                tempBasalDelta: nil,
                bolusDelta: nil,
                matches: ours == nil && loops == nil
            )
        }
        
        let tempDelta = (ours.tempBasalRate ?? 0) - (loops.tempBasalRate ?? 0)
        let bolusDelta = (ours.bolusVolume ?? 0) - (loops.bolusVolume ?? 0)
        
        let matches = abs(tempDelta) < config.tempBasalTolerance && abs(bolusDelta) < config.bolusTolerance
        
        return DosingComparison(
            ourRecommendation: ours,
            loopRecommendation: loops,
            tempBasalDelta: tempDelta,
            bolusDelta: bolusDelta,
            matches: matches
        )
    }
    
    // MARK: - Enacted Comparison
    
    /// Compare what would be enacted after ifNecessary() filter
    public static func compareEnacted(
        ours: EnactedDose?,
        loops: EnactedDose?,
        config: ComparisonConfig = .default
    ) -> EnactedComparison {
        guard let ours = ours, let loops = loops else {
            return EnactedComparison(
                ourEnacted: ours,
                loopEnacted: loops,
                rateDelta: nil,
                matches: ours == nil && loops == nil
            )
        }
        
        let rateDelta = ours.rate - loops.rate
        let matches = abs(rateDelta) < config.tempBasalTolerance
        
        return EnactedComparison(
            ourEnacted: ours,
            loopEnacted: loops,
            rateDelta: rateDelta,
            matches: matches
        )
    }
    
    // MARK: - Cycle Comparison (All-in-one)
    
    /// Compare all aspects of a cycle
    public static func compareCycle(
        ourIOB: Double,
        ourPrediction: [Double],
        ourRecommendation: ReplayDoseRecommendation?,
        ourEnacted: EnactedDose?,
        cycle: LoopCycleState,
        config: ComparisonConfig = .default
    ) -> CycleComparison {
        let iob = compareIOB(ours: ourIOB, loops: cycle.loopReportedIOB, config: config)
        let prediction = comparePrediction(ours: ourPrediction, loops: cycle.loopPrediction, config: config)
        let dosing = compareDosing(ours: ourRecommendation, loops: cycle.loopRecommendation, config: config)
        let enacted = compareEnacted(ours: ourEnacted, loops: cycle.loopEnacted, config: config)
        
        return CycleComparison(
            cycleIndex: cycle.cycleIndex,
            timestamp: cycle.cgmReadingTime,
            iob: iob,
            prediction: prediction,
            dosing: dosing,
            enacted: enacted,
            overallSignificance: prediction.significance
        )
    }
    
    // MARK: - Aggregate Statistics
    
    /// Compute aggregate statistics over multiple cycle comparisons
    public static func aggregateStatistics(
        _ comparisons: [CycleComparison]
    ) -> AggregateStatistics {
        guard !comparisons.isEmpty else {
            return AggregateStatistics(
                cycleCount: 0,
                iobMeanDelta: 0,
                iobMaxDelta: 0,
                predictionMeanMAE: 0,
                predictionMaxMAE: 0,
                eventualMeanDelta: 0,
                eventualMaxDelta: 0,
                significanceCounts: [:],
                passRate: 1.0
            )
        }
        
        let iobDeltas = comparisons.map { abs($0.iob.delta) }
        let maes = comparisons.map { $0.prediction.mae }
        let eventualDeltas = comparisons.map { abs($0.prediction.eventualDelta) }
        
        var sigCounts: [Significance: Int] = [:]
        for comp in comparisons {
            sigCounts[comp.overallSignificance, default: 0] += 1
        }
        
        let passCount = sigCounts[.none, default: 0]
        
        // ALG-ZERO-DIV-011: Compute dosing statistics
        let dosingWithBoth = comparisons.filter { $0.dosing.ourRecommendation != nil && $0.dosing.loopRecommendation != nil }
        let dosingComparisons = dosingWithBoth.count
        var dosingMatchRate = 0.0
        var dosingMeanTempDelta = 0.0
        
        if dosingComparisons > 0 {
            let matchCount = dosingWithBoth.filter { $0.dosing.matches }.count
            dosingMatchRate = Double(matchCount) / Double(dosingComparisons)
            
            let tempDeltas = dosingWithBoth.compactMap { $0.dosing.tempBasalDelta }.map { abs($0) }
            if !tempDeltas.isEmpty {
                dosingMeanTempDelta = tempDeltas.reduce(0, +) / Double(tempDeltas.count)
            }
        }
        
        // ALG-ZERO-DIV-012: Compute enacted statistics
        let enactedWithBoth = comparisons.filter { $0.enacted.ourEnacted != nil && $0.enacted.loopEnacted != nil }
        let enactedComparisons = enactedWithBoth.count
        var enactedMatchRate = 0.0
        var enactedMeanRateDelta = 0.0
        
        if enactedComparisons > 0 {
            let matchCount = enactedWithBoth.filter { $0.enacted.matches }.count
            enactedMatchRate = Double(matchCount) / Double(enactedComparisons)
            
            let rateDeltas = enactedWithBoth.compactMap { $0.enacted.rateDelta }.map { abs($0) }
            if !rateDeltas.isEmpty {
                enactedMeanRateDelta = rateDeltas.reduce(0, +) / Double(rateDeltas.count)
            }
        }
        
        return AggregateStatistics(
            cycleCount: comparisons.count,
            iobMeanDelta: iobDeltas.reduce(0, +) / Double(comparisons.count),
            iobMaxDelta: iobDeltas.max() ?? 0,
            predictionMeanMAE: maes.reduce(0, +) / Double(comparisons.count),
            predictionMaxMAE: maes.max() ?? 0,
            eventualMeanDelta: eventualDeltas.reduce(0, +) / Double(comparisons.count),
            eventualMaxDelta: eventualDeltas.max() ?? 0,
            significanceCounts: sigCounts,
            passRate: Double(passCount) / Double(comparisons.count),
            dosingMatchRate: dosingMatchRate,
            dosingMeanTempDelta: dosingMeanTempDelta,
            dosingComparisons: dosingComparisons,
            enactedMatchRate: enactedMatchRate,
            enactedMeanRateDelta: enactedMeanRateDelta,
            enactedComparisons: enactedComparisons
        )
    }
    
    // MARK: - Private Helpers
    
    private static func classifySignificance(
        mae: Double,
        eventualDelta: Double,
        config: ComparisonConfig = .default
    ) -> Significance {
        let absEventual = abs(eventualDelta)
        
        // Use config thresholds for classification
        if mae <= config.maeTolerance && absEventual <= config.eventualGlucoseTolerance / 2 {
            return .none
        } else if mae <= config.minorMAEThreshold && absEventual <= config.eventualGlucoseTolerance {
            return .minor
        } else if mae <= config.moderateMAEThreshold && absEventual <= config.eventualGlucoseTolerance * 2 {
            return .moderate
        } else {
            return .major
        }
    }
}

// MARK: - Comparison Results

/// IOB comparison result
public struct IOBComparison: Sendable {
    public let ourIOB: Double
    public let loopIOB: Double
    public let delta: Double
    public let percentError: Double
    public let withinTolerance: Bool
    
    public init(
        ourIOB: Double,
        loopIOB: Double,
        delta: Double,
        percentError: Double,
        withinTolerance: Bool
    ) {
        self.ourIOB = ourIOB
        self.loopIOB = loopIOB
        self.delta = delta
        self.percentError = percentError
        self.withinTolerance = withinTolerance
    }
}

/// Prediction comparison result
public struct PredictionComparison: Sendable {
    public let ourPrediction: [Double]
    public let loopPrediction: [Double]
    public let pointDeltas: [Double]
    public let mae: Double
    public let maxDelta: Double
    public let eventualDelta: Double
    public let significance: Significance
    public let withinTolerance: Bool
    
    public init(
        ourPrediction: [Double],
        loopPrediction: [Double],
        pointDeltas: [Double],
        mae: Double,
        maxDelta: Double,
        eventualDelta: Double,
        significance: Significance,
        withinTolerance: Bool
    ) {
        self.ourPrediction = ourPrediction
        self.loopPrediction = loopPrediction
        self.pointDeltas = pointDeltas
        self.mae = mae
        self.maxDelta = maxDelta
        self.eventualDelta = eventualDelta
        self.significance = significance
        self.withinTolerance = withinTolerance
    }
}

/// Significance levels for divergence
public enum Significance: String, Sendable, CaseIterable {
    case none = "None"          // ✅ Perfect match
    case minor = "Minor"        // 🟡 Small drift
    case moderate = "Moderate"  // ⚠️ Notable difference
    case major = "Major"        // 🔴 Significant divergence
    
    /// Symbol for display
    public var symbol: String {
        switch self {
        case .none: return "✅"
        case .minor: return "🟡"
        case .moderate: return "⚠️"
        case .major: return "🔴"
        }
    }
    
    /// True if this significance level passes validation
    public var passes: Bool {
        self == .none
    }
}

/// Dosing comparison result
public struct DosingComparison: Sendable {
    public let ourRecommendation: ReplayDoseRecommendation?
    public let loopRecommendation: ReplayDoseRecommendation?
    public let tempBasalDelta: Double?
    public let bolusDelta: Double?
    public let matches: Bool
    
    public init(
        ourRecommendation: ReplayDoseRecommendation?,
        loopRecommendation: ReplayDoseRecommendation?,
        tempBasalDelta: Double?,
        bolusDelta: Double?,
        matches: Bool
    ) {
        self.ourRecommendation = ourRecommendation
        self.loopRecommendation = loopRecommendation
        self.tempBasalDelta = tempBasalDelta
        self.bolusDelta = bolusDelta
        self.matches = matches
    }
}

/// Enacted dose comparison result
public struct EnactedComparison: Sendable {
    public let ourEnacted: EnactedDose?
    public let loopEnacted: EnactedDose?
    public let rateDelta: Double?
    public let matches: Bool
    
    public init(
        ourEnacted: EnactedDose?,
        loopEnacted: EnactedDose?,
        rateDelta: Double?,
        matches: Bool
    ) {
        self.ourEnacted = ourEnacted
        self.loopEnacted = loopEnacted
        self.rateDelta = rateDelta
        self.matches = matches
    }
}

/// Full cycle comparison result
public struct CycleComparison: Sendable, Identifiable {
    public var id: Int { cycleIndex }
    
    public let cycleIndex: Int
    public let timestamp: Date
    public let iob: IOBComparison
    public let prediction: PredictionComparison
    public let dosing: DosingComparison
    public let enacted: EnactedComparison  // ALG-ZERO-DIV-012
    public let overallSignificance: Significance
    
    public init(
        cycleIndex: Int,
        timestamp: Date,
        iob: IOBComparison,
        prediction: PredictionComparison,
        dosing: DosingComparison,
        enacted: EnactedComparison = EnactedComparison(ourEnacted: nil, loopEnacted: nil, rateDelta: nil, matches: true),
        overallSignificance: Significance
    ) {
        self.cycleIndex = cycleIndex
        self.timestamp = timestamp
        self.iob = iob
        self.prediction = prediction
        self.dosing = dosing
        self.enacted = enacted
        self.overallSignificance = overallSignificance
    }
}

/// Aggregate statistics over multiple cycles
public struct AggregateStatistics: Sendable {
    public let cycleCount: Int
    
    // IOB statistics
    public let iobMeanDelta: Double
    public let iobMaxDelta: Double
    
    // Prediction statistics
    public let predictionMeanMAE: Double
    public let predictionMaxMAE: Double
    public let eventualMeanDelta: Double
    public let eventualMaxDelta: Double
    
    // Dosing statistics (ALG-ZERO-DIV-011)
    public let dosingMatchRate: Double
    public let dosingMeanTempDelta: Double
    public let dosingComparisons: Int
    
    // Enacted statistics (ALG-ZERO-DIV-012)
    public let enactedMatchRate: Double
    public let enactedMeanRateDelta: Double
    public let enactedComparisons: Int
    
    // Significance breakdown
    public let significanceCounts: [Significance: Int]
    
    /// Percentage of cycles that pass (significance = None)
    public let passRate: Double
    
    public init(
        cycleCount: Int,
        iobMeanDelta: Double,
        iobMaxDelta: Double,
        predictionMeanMAE: Double,
        predictionMaxMAE: Double,
        eventualMeanDelta: Double,
        eventualMaxDelta: Double,
        significanceCounts: [Significance: Int],
        passRate: Double,
        dosingMatchRate: Double = 0,
        dosingMeanTempDelta: Double = 0,
        dosingComparisons: Int = 0,
        enactedMatchRate: Double = 0,
        enactedMeanRateDelta: Double = 0,
        enactedComparisons: Int = 0
    ) {
        self.cycleCount = cycleCount
        self.iobMeanDelta = iobMeanDelta
        self.iobMaxDelta = iobMaxDelta
        self.predictionMeanMAE = predictionMeanMAE
        self.predictionMaxMAE = predictionMaxMAE
        self.eventualMeanDelta = eventualMeanDelta
        self.eventualMaxDelta = eventualMaxDelta
        self.significanceCounts = significanceCounts
        self.passRate = passRate
        self.dosingMatchRate = dosingMatchRate
        self.dosingMeanTempDelta = dosingMeanTempDelta
        self.dosingComparisons = dosingComparisons
        self.enactedMatchRate = enactedMatchRate
        self.enactedMeanRateDelta = enactedMeanRateDelta
        self.enactedComparisons = enactedComparisons
    }
    
    /// Summary string for logging
    public var summary: String {
        let noneCount = significanceCounts[.none] ?? 0
        let minorCount = significanceCounts[.minor] ?? 0
        let moderateCount = significanceCounts[.moderate] ?? 0
        let majorCount = significanceCounts[.major] ?? 0
        
        var result = """
        Cycles: \(cycleCount) | Pass Rate: \(String(format: "%.1f", passRate * 100))%
        IOB: mean Δ=\(String(format: "%.3f", iobMeanDelta))U, max Δ=\(String(format: "%.3f", iobMaxDelta))U
        Prediction: mean MAE=\(String(format: "%.1f", predictionMeanMAE)) mg/dL, max MAE=\(String(format: "%.1f", predictionMaxMAE)) mg/dL
        Eventual: mean Δ=\(String(format: "%.1f", eventualMeanDelta)) mg/dL, max Δ=\(String(format: "%.1f", eventualMaxDelta)) mg/dL
        Significance: ✅\(noneCount) 🟡\(minorCount) ⚠️\(moderateCount) 🔴\(majorCount)
        """
        
        // Add dosing stats if we have comparisons
        if dosingComparisons > 0 {
            result += "\nDosing: match rate=\(String(format: "%.1f", dosingMatchRate * 100))%, mean Δ=\(String(format: "%.2f", dosingMeanTempDelta)) U/hr (\(dosingComparisons) cycles)"
        }
        
        // Add enacted stats if we have comparisons
        if enactedComparisons > 0 {
            result += "\nEnacted: match rate=\(String(format: "%.1f", enactedMatchRate * 100))%, mean Δ=\(String(format: "%.2f", enactedMeanRateDelta)) U/hr (\(enactedComparisons) cycles)"
        }
        
        return result
    }
}
