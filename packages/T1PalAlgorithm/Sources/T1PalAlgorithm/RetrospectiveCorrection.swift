// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RetrospectiveCorrection.swift
// T1Pal Mobile
//
// Loop-compatible retrospective correction
// Requirements: REQ-ALGO-011
//
// Based on Loop's RetrospectiveCorrection:
// https://github.com/LoopKit/Loop/blob/main/Loop/Models/RetrospectiveCorrection.swift
//
// Retrospective correction compares predicted glucose values with actual
// observed values to generate a correction effect that adjusts future predictions.
//
// Trace: ALG-018, PRD-009

import Foundation
import T1PalCore

// MARK: - Retrospective Correction Types

/// A comparison between predicted and actual glucose at a specific time
public struct GlucoseDiscrepancy: Sendable {
    public let date: Date
    public let predicted: Double   // mg/dL
    public let actual: Double      // mg/dL
    public let discrepancy: Double // actual - predicted (positive = higher than expected)
    
    public init(date: Date, predicted: Double, actual: Double) {
        self.date = date
        self.predicted = predicted
        self.actual = actual
        self.discrepancy = actual - predicted
    }
    
    /// Percentage error relative to predicted
    public var percentageError: Double {
        guard predicted != 0 else { return 0 }
        return (discrepancy / predicted) * 100
    }
}

/// Summary of retrospective correction analysis
public struct RetrospectiveCorrectionResult: Sendable {
    /// Individual discrepancies analyzed
    public let discrepancies: [GlucoseDiscrepancy]
    
    /// Average discrepancy (positive = BG running higher than predicted)
    public let averageDiscrepancy: Double
    
    /// Weighted average giving more weight to recent observations
    public let weightedDiscrepancy: Double
    
    /// Correction effect to apply to predictions
    public let correctionEffect: [GlucoseEffect]
    
    /// Velocity of discrepancy change (mg/dL per hour)
    public let discrepancyVelocity: Double
    
    /// Whether correction is significant enough to apply
    public let isSignificant: Bool
    
    public init(
        discrepancies: [GlucoseDiscrepancy],
        averageDiscrepancy: Double,
        weightedDiscrepancy: Double,
        correctionEffect: [GlucoseEffect],
        discrepancyVelocity: Double,
        isSignificant: Bool
    ) {
        self.discrepancies = discrepancies
        self.averageDiscrepancy = averageDiscrepancy
        self.weightedDiscrepancy = weightedDiscrepancy
        self.correctionEffect = correctionEffect
        self.discrepancyVelocity = discrepancyVelocity
        self.isSignificant = isSignificant
    }
}

// MARK: - Retrospective Correction Engine

/// Loop-compatible retrospective correction engine
public struct RetrospectiveCorrection: Sendable {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Duration of history to analyze for retrospective correction
        public let retrospectiveDuration: TimeInterval
        
        /// Minimum number of discrepancies required
        public let minimumDiscrepancies: Int
        
        /// Minimum average discrepancy to consider significant (mg/dL)
        public let significanceThreshold: Double
        
        /// Duration over which to apply correction effect
        public let correctionDuration: TimeInterval
        
        /// Interval between correction effect points
        public let correctionInterval: TimeInterval
        
        /// Weight decay factor for older observations (per hour)
        public let weightDecayPerHour: Double
        
        /// Maximum correction effect magnitude (mg/dL)
        public let maxCorrectionMagnitude: Double
        
        public init(
            retrospectiveDuration: TimeInterval = 30 * 60,  // 30 minutes
            minimumDiscrepancies: Int = 3,
            significanceThreshold: Double = 10,  // 10 mg/dL
            correctionDuration: TimeInterval = 60 * 60,  // 1 hour
            correctionInterval: TimeInterval = 5 * 60,
            weightDecayPerHour: Double = 0.5,
            maxCorrectionMagnitude: Double = 50
        ) {
            self.retrospectiveDuration = retrospectiveDuration
            self.minimumDiscrepancies = minimumDiscrepancies
            self.significanceThreshold = significanceThreshold
            self.correctionDuration = correctionDuration
            self.correctionInterval = correctionInterval
            self.weightDecayPerHour = weightDecayPerHour
            self.maxCorrectionMagnitude = maxCorrectionMagnitude
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - Properties
    
    public let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Discrepancy Calculation
    
    /// Calculate discrepancies between predicted and actual glucose
    /// - Parameters:
    ///   - predictions: Past predictions (what we thought glucose would be)
    ///   - actuals: Actual glucose readings
    ///   - referenceDate: Current time
    /// - Returns: Array of discrepancies
    public func calculateDiscrepancies(
        predictions: [PredictedGlucose],
        actuals: [GlucoseReading],
        referenceDate: Date = Date()
    ) -> [GlucoseDiscrepancy] {
        let cutoffDate = referenceDate.addingTimeInterval(-configuration.retrospectiveDuration)
        
        // Filter to retrospective window
        let relevantActuals = actuals.filter { $0.timestamp >= cutoffDate && $0.timestamp <= referenceDate }
        
        var discrepancies: [GlucoseDiscrepancy] = []
        
        for actual in relevantActuals {
            // Find closest prediction to this actual reading
            if let closestPrediction = findClosestPrediction(to: actual.timestamp, in: predictions) {
                discrepancies.append(GlucoseDiscrepancy(
                    date: actual.timestamp,
                    predicted: closestPrediction.glucose,
                    actual: actual.glucose
                ))
            }
        }
        
        return discrepancies.sorted { $0.date < $1.date }
    }
    
    /// Find the prediction closest to a given date
    private func findClosestPrediction(to date: Date, in predictions: [PredictedGlucose]) -> PredictedGlucose? {
        predictions.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
    
    // MARK: - Correction Calculation
    
    /// Calculate retrospective correction from discrepancies
    /// - Parameters:
    ///   - discrepancies: Calculated discrepancies
    ///   - referenceDate: Current time for generating correction effects
    /// - Returns: Retrospective correction result
    public func calculateCorrection(
        discrepancies: [GlucoseDiscrepancy],
        referenceDate: Date = Date()
    ) -> RetrospectiveCorrectionResult {
        guard discrepancies.count >= configuration.minimumDiscrepancies else {
            return RetrospectiveCorrectionResult(
                discrepancies: discrepancies,
                averageDiscrepancy: 0,
                weightedDiscrepancy: 0,
                correctionEffect: [],
                discrepancyVelocity: 0,
                isSignificant: false
            )
        }
        
        // Calculate simple average
        let averageDiscrepancy = discrepancies.map(\.discrepancy).reduce(0, +) / Double(discrepancies.count)
        
        // Calculate weighted average (more recent = higher weight)
        let weightedDiscrepancy = calculateWeightedDiscrepancy(discrepancies, referenceDate: referenceDate)
        
        // Calculate velocity of discrepancy change
        let velocity = calculateDiscrepancyVelocity(discrepancies)
        
        // Determine if significant
        let isSignificant = abs(weightedDiscrepancy) >= configuration.significanceThreshold
        
        // Generate correction effect
        let correctionEffect = generateCorrectionEffect(
            weightedDiscrepancy: weightedDiscrepancy,
            velocity: velocity,
            referenceDate: referenceDate,
            isSignificant: isSignificant
        )
        
        return RetrospectiveCorrectionResult(
            discrepancies: discrepancies,
            averageDiscrepancy: averageDiscrepancy,
            weightedDiscrepancy: weightedDiscrepancy,
            correctionEffect: correctionEffect,
            discrepancyVelocity: velocity,
            isSignificant: isSignificant
        )
    }
    
    /// Calculate weighted average discrepancy giving more weight to recent observations
    private func calculateWeightedDiscrepancy(
        _ discrepancies: [GlucoseDiscrepancy],
        referenceDate: Date
    ) -> Double {
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        
        for discrepancy in discrepancies {
            let hoursAgo = referenceDate.timeIntervalSince(discrepancy.date) / 3600
            let weight = pow(1 - configuration.weightDecayPerHour, hoursAgo)
            
            weightedSum += discrepancy.discrepancy * weight
            totalWeight += weight
        }
        
        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }
    
    /// Calculate velocity of discrepancy change (trend)
    private func calculateDiscrepancyVelocity(_ discrepancies: [GlucoseDiscrepancy]) -> Double {
        guard discrepancies.count >= 2 else { return 0 }
        
        let sorted = discrepancies.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        
        let timeDelta = last.date.timeIntervalSince(first.date) / 3600  // Hours
        guard timeDelta > 0 else { return 0 }
        
        let discrepancyDelta = last.discrepancy - first.discrepancy
        return discrepancyDelta / timeDelta
    }
    
    /// Generate correction effect to apply to predictions
    private func generateCorrectionEffect(
        weightedDiscrepancy: Double,
        velocity: Double,
        referenceDate: Date,
        isSignificant: Bool
    ) -> [GlucoseEffect] {
        guard isSignificant else { return [] }
        
        var effects: [GlucoseEffect] = []
        var currentDate = referenceDate
        
        // Apply correction that decays over the correction duration
        while currentDate <= referenceDate.addingTimeInterval(configuration.correctionDuration) {
            let elapsed = currentDate.timeIntervalSince(referenceDate)
            let decayFactor = 1 - (elapsed / configuration.correctionDuration)
            
            // Start with weighted discrepancy, adjust for velocity, apply decay
            var correction = weightedDiscrepancy * decayFactor
            
            // Add velocity component (extrapolate the trend)
            let hoursElapsed = elapsed / 3600
            correction += velocity * hoursElapsed * decayFactor
            
            // Clamp to maximum
            correction = max(-configuration.maxCorrectionMagnitude,
                           min(configuration.maxCorrectionMagnitude, correction))
            
            effects.append(GlucoseEffect(date: currentDate, quantity: correction))
            currentDate = currentDate.addingTimeInterval(configuration.correctionInterval)
        }
        
        return effects
    }
    
    // MARK: - Full Analysis
    
    /// Perform complete retrospective correction analysis
    /// - Parameters:
    ///   - predictions: Past predictions
    ///   - actuals: Actual glucose readings
    ///   - referenceDate: Current time
    /// - Returns: Complete correction result
    public func analyze(
        predictions: [PredictedGlucose],
        actuals: [GlucoseReading],
        referenceDate: Date = Date()
    ) -> RetrospectiveCorrectionResult {
        let discrepancies = calculateDiscrepancies(
            predictions: predictions,
            actuals: actuals,
            referenceDate: referenceDate
        )
        
        return calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: referenceDate
        )
    }
}

// MARK: - Integration with Glucose Prediction

extension LoopGlucosePrediction {
    
    /// Generate prediction with retrospective correction applied
    /// - Parameters:
    ///   - currentGlucose: Current glucose value
    ///   - glucoseHistory: Recent glucose readings
    ///   - doses: Insulin doses
    ///   - carbEntries: Carb entries
    ///   - insulinSensitivity: ISF
    ///   - carbRatio: ICR
    ///   - retrospectiveCorrection: Correction effect to apply
    ///   - startDate: Start time
    /// - Returns: Corrected predictions
    public func predictWithCorrection(
        currentGlucose: Double,
        glucoseHistory: [GlucoseReading] = [],
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        insulinSensitivity: Double,
        carbRatio: Double,
        retrospectiveCorrection: [GlucoseEffect],
        startDate: Date = Date()
    ) -> [PredictedGlucose] {
        // Get base predictions
        var predictions = predict(
            currentGlucose: currentGlucose,
            glucoseHistory: glucoseHistory,
            doses: doses,
            carbEntries: carbEntries,
            insulinSensitivity: insulinSensitivity,
            carbRatio: carbRatio,
            startDate: startDate
        )
        
        // Apply retrospective correction
        predictions = applyCorrection(to: predictions, correction: retrospectiveCorrection)
        
        return predictions
    }
    
    /// Apply correction effect to predictions
    private func applyCorrection(
        to predictions: [PredictedGlucose],
        correction: [GlucoseEffect]
    ) -> [PredictedGlucose] {
        guard !correction.isEmpty else { return predictions }
        
        return predictions.map { prediction in
            // Find closest correction effect
            if let closestCorrection = correction.min(by: {
                abs($0.date.timeIntervalSince(prediction.date)) < abs($1.date.timeIntervalSince(prediction.date))
            }) {
                // Only apply if within half an interval
                let timeDiff = abs(closestCorrection.date.timeIntervalSince(prediction.date))
                if timeDiff < configuration.predictionInterval / 2 {
                    let correctedGlucose = max(39, min(400, prediction.glucose + closestCorrection.quantity))
                    return PredictedGlucose(date: prediction.date, glucose: correctedGlucose)
                }
            }
            return prediction
        }
    }
}

// MARK: - Retrospective Correction Statistics

/// Statistics about retrospective correction performance
public struct RetrospectiveCorrectionStats: Sendable {
    public let totalAnalyses: Int
    public let significantCorrections: Int
    public let averageAbsoluteError: Double
    public let rmse: Double  // Root mean square error
    public let bias: Double  // Average signed error (positive = underestimating)
    
    public init(discrepancies: [[GlucoseDiscrepancy]]) {
        self.totalAnalyses = discrepancies.count
        
        let allDiscrepancies = discrepancies.flatMap { $0 }
        
        self.significantCorrections = discrepancies.filter { discrepancies in
            let avg = discrepancies.map(\.discrepancy).reduce(0, +) / Double(max(1, discrepancies.count))
            return abs(avg) >= 10
        }.count
        
        if allDiscrepancies.isEmpty {
            self.averageAbsoluteError = 0
            self.rmse = 0
            self.bias = 0
        } else {
            self.averageAbsoluteError = allDiscrepancies.map { abs($0.discrepancy) }.reduce(0, +) / Double(allDiscrepancies.count)
            
            let squaredErrors = allDiscrepancies.map { $0.discrepancy * $0.discrepancy }
            self.rmse = sqrt(squaredErrors.reduce(0, +) / Double(allDiscrepancies.count))
            
            self.bias = allDiscrepancies.map(\.discrepancy).reduce(0, +) / Double(allDiscrepancies.count)
        }
    }
    
    /// Percentage of analyses that resulted in significant corrections
    public var correctionRate: Double {
        guard totalAnalyses > 0 else { return 0 }
        return Double(significantCorrections) / Double(totalAnalyses) * 100
    }
}
