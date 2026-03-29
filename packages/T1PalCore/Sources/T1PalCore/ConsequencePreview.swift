// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ConsequencePreview.swift - Predicted outcomes engine
// Part of T1PalCore
// Trace: NARRATIVE-005

import Foundation

// MARK: - Consequence Types

/// Represents a predicted consequence of an action
public struct Consequence: Sendable, Identifiable {
    public let id: String
    
    /// The action that leads to this consequence
    public let action: String
    
    /// Predicted glucose trajectory (mg/dL values over time)
    public let predictedGlucose: [GlucosePrediction]
    
    /// Expected time in range (percentage)
    public let timeInRange: Double
    
    /// Risk assessment
    public let risk: RiskLevel
    
    /// Human-readable summary of the outcome
    public let summary: String
    
    /// Confidence in the prediction (0-1)
    public let confidence: Double
    
    public struct GlucosePrediction: Sendable {
        /// Minutes from now
        public let minutesAhead: Int
        /// Predicted glucose in mg/dL
        public let glucose: Double
        
        public init(minutesAhead: Int, glucose: Double) {
            self.minutesAhead = minutesAhead
            self.glucose = glucose
        }
    }
    
    public enum RiskLevel: String, Sendable, Comparable {
        case low = "low"
        case moderate = "moderate"
        case high = "high"
        case veryHigh = "veryHigh"
        
        public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
            let order: [RiskLevel] = [.low, .moderate, .high, .veryHigh]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }
    
    public init(
        id: String = UUID().uuidString,
        action: String,
        predictedGlucose: [GlucosePrediction],
        timeInRange: Double,
        risk: RiskLevel,
        summary: String,
        confidence: Double = 0.7
    ) {
        self.id = id
        self.action = action
        self.predictedGlucose = predictedGlucose
        self.timeInRange = timeInRange
        self.risk = risk
        self.summary = summary
        self.confidence = confidence
    }
}

// MARK: - Consequence Previewer Protocol

/// Protocol for generating consequence previews
/// Trace: NARRATIVE-005
public protocol ConsequencePreviewer: Sendable {
    /// Preview the consequence of eating carbs
    func previewCarbIntake(grams: Int, context: MetabolicContext) -> Consequence
    
    /// Preview the consequence of taking a bolus
    func previewBolus(units: Double, context: MetabolicContext) -> Consequence
    
    /// Preview the consequence of doing nothing
    func previewNoAction(context: MetabolicContext) -> Consequence
    
    /// Preview the consequence of setting a temp target
    func previewTempTarget(target: Double, duration: TimeInterval, context: MetabolicContext) -> Consequence
    
    /// Compare multiple consequences
    func compareConsequences(_ consequences: [Consequence]) -> ConsequenceComparison
}

// MARK: - Consequence Comparison

/// Comparison of multiple consequences
public struct ConsequenceComparison: Sendable {
    /// The recommended action based on analysis
    public let recommended: Consequence?
    
    /// All consequences ranked by risk (lowest first)
    public let ranked: [Consequence]
    
    /// Human-readable explanation of the recommendation
    public let explanation: String
    
    public init(recommended: Consequence?, ranked: [Consequence], explanation: String) {
        self.recommended = recommended
        self.ranked = ranked
        self.explanation = explanation
    }
}

// MARK: - Default Consequence Previewer

/// Default implementation of ConsequencePreviewer using simple heuristics
public struct DefaultConsequencePreviewer: ConsequencePreviewer {
    
    /// Insulin sensitivity factor (mg/dL drop per unit)
    private let isf: Double
    
    /// Carb ratio (grams per unit)
    private let carbRatio: Double
    
    /// Target glucose
    private let target: Double
    
    public init(isf: Double = 50, carbRatio: Double = 10, target: Double = 110) {
        self.isf = isf
        self.carbRatio = carbRatio
        self.target = target
    }
    
    public func previewCarbIntake(grams: Int, context: MetabolicContext) -> Consequence {
        let currentGlucose = context.glucose
        
        // Simple model: carbs raise glucose ~4 mg/dL per gram (varies widely)
        let carbEffect = Double(grams) * 4.0
        
        // Account for existing IOB
        let iobEffect = (context.iob ?? 0) * isf
        
        let predictions = generatePredictions(
            start: currentGlucose,
            carbEffect: carbEffect,
            insulinEffect: iobEffect,
            baseRate: context.rateOfChange ?? 0
        )
        
        let peakGlucose = predictions.map(\.glucose).max() ?? currentGlucose
        let risk = assessRisk(predictions: predictions)
        let tir = calculateTimeInRange(predictions: predictions, range: context.targetRange)
        
        let summary: String
        if peakGlucose > 180 {
            summary = "\(grams)g carbs may push you to \(Int(peakGlucose)) mg/dL in about 45 minutes"
        } else if peakGlucose < 70 {
            summary = "\(grams)g carbs should help, but may not be enough"
        } else {
            summary = "\(grams)g carbs should keep you in range"
        }
        
        return Consequence(
            action: "Eat \(grams)g carbs",
            predictedGlucose: predictions,
            timeInRange: tir,
            risk: risk,
            summary: summary
        )
    }
    
    public func previewBolus(units: Double, context: MetabolicContext) -> Consequence {
        let currentGlucose = context.glucose
        
        // Insulin effect over time
        let insulinEffect = units * isf
        
        // Account for existing IOB
        let totalInsulinEffect = insulinEffect + (context.iob ?? 0) * isf
        
        // Account for COB (roughly 4 mg/dL per gram)
        let cobEffect = (context.cob ?? 0) * 4.0
        
        let predictions = generatePredictions(
            start: currentGlucose,
            carbEffect: cobEffect,
            insulinEffect: totalInsulinEffect,
            baseRate: context.rateOfChange ?? 0
        )
        
        let minGlucose = predictions.map(\.glucose).min() ?? currentGlucose
        let risk = assessRisk(predictions: predictions)
        let tir = calculateTimeInRange(predictions: predictions, range: context.targetRange)
        
        let summary: String
        if minGlucose < 54 {
            summary = String(format: "%.1fU may cause a severe low (predicted: %d mg/dL)", units, Int(minGlucose))
        } else if minGlucose < 70 {
            summary = String(format: "%.1fU may cause a low (predicted: %d mg/dL)", units, Int(minGlucose))
        } else {
            summary = String(format: "%.1fU should bring you to about %d mg/dL", units, Int(minGlucose))
        }
        
        return Consequence(
            action: String(format: "Bolus %.1fU", units),
            predictedGlucose: predictions,
            timeInRange: tir,
            risk: risk,
            summary: summary
        )
    }
    
    public func previewNoAction(context: MetabolicContext) -> Consequence {
        let currentGlucose = context.glucose
        
        // Just IOB and COB effects
        let iobEffect = (context.iob ?? 0) * isf
        let cobEffect = (context.cob ?? 0) * 4.0
        
        let predictions = generatePredictions(
            start: currentGlucose,
            carbEffect: cobEffect,
            insulinEffect: iobEffect,
            baseRate: context.rateOfChange ?? 0
        )
        
        let finalGlucose = predictions.last?.glucose ?? currentGlucose
        let risk = assessRisk(predictions: predictions)
        let tir = calculateTimeInRange(predictions: predictions, range: context.targetRange)
        
        let summary: String
        if finalGlucose < 70 {
            summary = "Without action, you may go low to \(Int(finalGlucose)) mg/dL"
        } else if finalGlucose > 180 {
            summary = "Without action, you may stay high around \(Int(finalGlucose)) mg/dL"
        } else {
            summary = "Your glucose should naturally settle around \(Int(finalGlucose)) mg/dL"
        }
        
        return Consequence(
            action: "No action",
            predictedGlucose: predictions,
            timeInRange: tir,
            risk: risk,
            summary: summary
        )
    }
    
    public func previewTempTarget(target: Double, duration: TimeInterval, context: MetabolicContext) -> Consequence {
        // Temp targets mainly affect algorithm behavior
        // For now, just describe what will happen
        let durationMinutes = Int(duration / 60)
        
        let predictions = generatePredictions(
            start: context.glucose,
            carbEffect: (context.cob ?? 0) * 4.0,
            insulinEffect: (context.iob ?? 0) * isf,
            baseRate: context.rateOfChange ?? 0
        )
        
        let summary: String
        if target > 150 {
            summary = "Exercise target of \(Int(target)) for \(durationMinutes) min will reduce insulin delivery"
        } else if target < 100 {
            summary = "Lower target of \(Int(target)) for \(durationMinutes) min will increase insulin delivery"
        } else {
            summary = "Target of \(Int(target)) for \(durationMinutes) min set"
        }
        
        return Consequence(
            action: "Set temp target \(Int(target))",
            predictedGlucose: predictions,
            timeInRange: 0.7,
            risk: .low,
            summary: summary
        )
    }
    
    public func compareConsequences(_ consequences: [Consequence]) -> ConsequenceComparison {
        guard !consequences.isEmpty else {
            return ConsequenceComparison(recommended: nil, ranked: [], explanation: "No options to compare")
        }
        
        // Rank by risk level (lowest first), then by time in range (highest first)
        let ranked = consequences.sorted { a, b in
            if a.risk != b.risk {
                return a.risk < b.risk
            }
            return a.timeInRange > b.timeInRange
        }
        
        let recommended = ranked.first
        
        let explanation: String
        if let rec = recommended {
            if rec.risk == .low {
                explanation = "\"\(rec.action)\" is the safest option with \(Int(rec.timeInRange * 100))% time in range"
            } else {
                explanation = "\"\(rec.action)\" has the lowest risk, but monitor closely"
            }
        } else {
            explanation = "Unable to make a recommendation"
        }
        
        return ConsequenceComparison(recommended: recommended, ranked: ranked, explanation: explanation)
    }
    
    // MARK: - Private Helpers
    
    private func generatePredictions(
        start: Double,
        carbEffect: Double,
        insulinEffect: Double,
        baseRate: Double
    ) -> [Consequence.GlucosePrediction] {
        var predictions: [Consequence.GlucosePrediction] = []
        
        // Generate predictions at 15, 30, 45, 60, 90, 120 minutes
        let times = [15, 30, 45, 60, 90, 120]
        
        for minutes in times {
            let t = Double(minutes)
            
            // Simple pharmacokinetic model
            // Carbs peak at ~45 min, insulin peaks at ~75 min
            let carbFactor = carbCurve(minutesAhead: t)
            let insulinFactor = insulinCurve(minutesAhead: t)
            
            let glucose = start + (carbEffect * carbFactor) - (insulinEffect * insulinFactor) + (baseRate * t)
            
            predictions.append(.init(minutesAhead: minutes, glucose: max(40, glucose)))
        }
        
        return predictions
    }
    
    private func carbCurve(minutesAhead t: Double) -> Double {
        // Simplified carb absorption curve (peaks ~45 min)
        if t <= 45 {
            return t / 45.0
        } else if t <= 120 {
            return 1.0 - ((t - 45) / 150.0)
        }
        return 0.5
    }
    
    private func insulinCurve(minutesAhead t: Double) -> Double {
        // Simplified insulin action curve (peaks ~75 min)
        if t <= 75 {
            return (t / 75.0) * 0.8
        } else if t <= 180 {
            return 0.8 + ((t - 75) / 525.0) * 0.2
        }
        return 1.0
    }
    
    private func assessRisk(predictions: [Consequence.GlucosePrediction]) -> Consequence.RiskLevel {
        let values = predictions.map(\.glucose)
        let min = values.min() ?? 100
        let max = values.max() ?? 100
        
        if min < 54 { return .veryHigh }
        if min < 70 || max > 300 { return .high }
        if min < 80 || max > 250 { return .moderate }
        return .low
    }
    
    private func calculateTimeInRange(predictions: [Consequence.GlucosePrediction], range: ClosedRange<Double>) -> Double {
        let inRange = predictions.filter { range.contains($0.glucose) }.count
        return Double(inRange) / Double(max(1, predictions.count))
    }
}
