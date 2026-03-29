// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopGlucosePrediction.swift
// T1Pal Mobile
//
// Loop-compatible glucose prediction engine
// Requirements: REQ-ALGO-010
//
// Based on Loop's GlucoseStore+LoopKit.swift:
// https://github.com/LoopKit/Loop/blob/main/Loop/Managers/LoopDataManager.swift
//
// Trace: ALG-017, PRD-009

import Foundation
import T1PalCore

// MARK: - Prediction Effect Types

/// Individual effects that contribute to glucose prediction
public struct GlucoseEffect: Sendable {
    public let date: Date
    public let quantity: Double  // mg/dL change from baseline
    
    public init(date: Date, quantity: Double) {
        self.date = date
        self.quantity = quantity
    }
}

/// A predicted glucose value at a specific time
public struct PredictedGlucose: Sendable {
    public let date: Date
    public let glucose: Double  // mg/dL
    
    public init(date: Date, glucose: Double) {
        self.date = date
        self.glucose = glucose
    }
}

// MARK: - Loop Glucose Prediction

/// Loop-compatible glucose prediction combining multiple effects
public struct LoopGlucosePrediction: Sendable {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Duration to predict ahead
        public let predictionDuration: TimeInterval
        
        /// Interval between prediction points
        public let predictionInterval: TimeInterval
        
        /// Duration to use for momentum effect
        public let momentumDuration: TimeInterval
        
        /// Whether to include momentum effect
        public let includeMomentum: Bool
        
        /// Whether to include carb effect
        public let includeCarbEffect: Bool
        
        /// Whether to include insulin effect
        public let includeInsulinEffect: Bool
        
        public init(
            predictionDuration: TimeInterval = 6 * 3600,
            predictionInterval: TimeInterval = 5 * 60,
            momentumDuration: TimeInterval = 15 * 60,  // ALG-DIAG-T6-007: Match Loop's 15-min momentum (GlucoseMath.swift:13)
            includeMomentum: Bool = true,
            includeCarbEffect: Bool = true,
            includeInsulinEffect: Bool = true
        ) {
            self.predictionDuration = predictionDuration
            self.predictionInterval = predictionInterval
            self.momentumDuration = momentumDuration
            self.includeMomentum = includeMomentum
            self.includeCarbEffect = includeCarbEffect
            self.includeInsulinEffect = includeInsulinEffect
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - Properties
    
    public let configuration: Configuration
    public let insulinCalculator: LoopIOBCalculator
    public let carbCalculator: LoopCarbEffectCalculator
    
    // MARK: - Initialization
    
    public init(
        configuration: Configuration = .default,
        insulinModel: LoopInsulinModelType = .rapidActingAdult,
        carbModel: LoopCarbAbsorptionModel = .piecewiseLinear
    ) {
        self.configuration = configuration
        self.insulinCalculator = LoopIOBCalculator(modelType: insulinModel)
        self.carbCalculator = LoopCarbEffectCalculator(absorptionModel: carbModel)
    }
    
    public init(
        configuration: Configuration = .default,
        insulinCalculator: LoopIOBCalculator,
        carbCalculator: LoopCarbEffectCalculator
    ) {
        self.configuration = configuration
        self.insulinCalculator = insulinCalculator
        self.carbCalculator = carbCalculator
    }
    
    // MARK: - Momentum Effect
    
    /// Calculate momentum effect from recent glucose trend using linear regression
    /// - Parameters:
    ///   - glucoseHistory: Recent glucose readings (newest last)
    ///   - startDate: Start time for prediction
    /// - Returns: Array of glucose effects from momentum (cumulative values, not deltas)
    ///
    /// ALG-DIAG-GEFF-005: Match Loop's linearMomentumEffect from GlucoseMath.swift
    /// Uses linear regression instead of simple delta, caps velocity at 4 mg/dL/min
    public func momentumEffect(
        glucoseHistory: [GlucoseReading],
        startDate: Date = Date()
    ) -> [GlucoseEffect] {
        guard configuration.includeMomentum else { return [] }
        // Loop requires 3+ entries for linear regression
        guard glucoseHistory.count >= 3 else { return [] }
        
        // Sort and filter to last 15 minutes (Loop's momentumDataInterval)
        // ALG-DIAG-GEFF-005: Match Loop's 15-minute momentum window
        // ALG-DIAG-T6-008: Filter both bounds - start-15min to start (not future readings)
        let sortedHistory = glucoseHistory.sorted { $0.timestamp < $1.timestamp }
        let momentumCutoff = startDate.addingTimeInterval(-15 * 60)  // 15 minutes before start
        let recent = sortedHistory.filter { $0.timestamp >= momentumCutoff && $0.timestamp <= startDate }
        
        guard recent.count >= 3 else { return [] }
        guard let first = recent.first, let last = recent.last else { return [] }
        
        // GAP-031: Validate data quality before momentum calculation
        // 4 checks: continuity, gradual transitions, calibration, provenance
        // Convert to SimpleGlucoseReading for protocol-compliant validation
        let validationReadings = recent.map { reading in
            SimpleGlucoseReading(
                timestamp: reading.timestamp,
                glucose: reading.glucose,
                sourceIdentifier: reading.source,
                isCalibration: false  // Standard readings are not calibrations
            )
        }
        let validator = DataQualityValidator()
        let quality = validator.assessQuality(validationReadings)
        guard quality.isValidForMomentum else { return [] }
        
        // Linear regression to calculate slope (mg/dL per second)
        let xValues = recent.map { $0.timestamp.timeIntervalSince(first.timestamp) }
        let yValues = recent.map { $0.glucose }
        
        let n = Double(recent.count)
        let sumX = xValues.reduce(0, +)
        let sumY = yValues.reduce(0, +)
        let sumXY = zip(xValues, yValues).map(*).reduce(0, +)
        let sumX2 = xValues.map { $0 * $0 }.reduce(0, +)
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return [] }
        
        var slope = (n * sumXY - sumX * sumY) / denominator  // mg/dL per second
        guard slope.isFinite else { return [] }
        
        // Cap velocity at 4 mg/dL/min = 4/60 mg/dL/sec (Loop's default max)
        let maxSlopePerSecond = 4.0 / 60.0
        slope = min(slope, maxSlopePerSecond)
        
        // ALG-DIAG-T6-003: Generate effects from last glucose reading forward (matching Loop)
        // Loop starts momentum from lastSample.startDate, floored to delta intervals
        // See GlucoseMath.swift:124 - simulationDateRangeForSamples([lastSample], ...)
        var effects: [GlucoseEffect] = []
        
        // Floor to delta interval (matching Loop's dateFlooredToTimeInterval)
        let delta = configuration.predictionInterval
        let flooredStart = Date(timeIntervalSinceReferenceDate: 
            floor(last.timestamp.timeIntervalSinceReferenceDate / delta) * delta)
        let momentumEnd = flooredStart.addingTimeInterval(configuration.momentumDuration)
        
        var currentDate = flooredStart
        
        // Loop: value = max(0, date.timeIntervalSince(lastSample.startDate)) * limitedSlope
        while currentDate <= momentumEnd {
            let timeSinceLast = max(0, currentDate.timeIntervalSince(last.timestamp))
            let value = timeSinceLast * slope  // Cumulative effect (not delta)
            effects.append(GlucoseEffect(date: currentDate, quantity: value))
            currentDate = currentDate.addingTimeInterval(delta)
        }
        
        return effects
    }
    
    // MARK: - Insulin Effect
    
    /// Calculate glucose effect from insulin
    /// - Parameters:
    ///   - doses: Insulin doses
    ///   - insulinSensitivity: ISF in mg/dL per unit
    ///   - startDate: Start time for prediction
    /// - Returns: Array of glucose effects from insulin
    public func insulinEffect(
        doses: [InsulinDose],
        insulinSensitivity: Double,
        startDate: Date = Date()
    ) -> [GlucoseEffect] {
        guard configuration.includeInsulinEffect else { return [] }
        
        let effects = insulinCalculator.insulinEffect(
            doses: doses,
            insulinSensitivity: insulinSensitivity,
            startDate: startDate,
            duration: configuration.predictionDuration,
            interval: configuration.predictionInterval
        )
        
        // Insulin lowers glucose, so effect is negative
        return effects.map { GlucoseEffect(date: $0.date, quantity: -$0.effect) }
    }
    
    // MARK: - Carb Effect
    
    /// Calculate glucose effect from carbs
    /// - Parameters:
    ///   - entries: Carb entries
    ///   - carbRatio: ICR in grams per unit
    ///   - insulinSensitivity: ISF in mg/dL per unit
    ///   - startDate: Start time for prediction
    /// - Returns: Array of glucose effects from carbs
    public func carbEffect(
        entries: [CarbEntry],
        carbRatio: Double,
        insulinSensitivity: Double,
        startDate: Date = Date()
    ) -> [GlucoseEffect] {
        guard configuration.includeCarbEffect else { return [] }
        
        let effects = carbCalculator.glucoseEffect(
            entries: entries,
            carbRatio: carbRatio,
            insulinSensitivity: insulinSensitivity,
            startDate: startDate,
            duration: configuration.predictionDuration,
            interval: configuration.predictionInterval
        )
        
        return effects.map { GlucoseEffect(date: $0.date, quantity: $0.effect) }
    }
    
    // MARK: - Combined Prediction
    
    /// Combine multiple effects into a single prediction curve with momentum blending
    /// - Parameters:
    ///   - startingGlucose: Current glucose reading
    ///   - momentum: Momentum effect array (blended separately per Loop's algorithm)
    ///   - effects: Array of other effect arrays to combine
    ///   - startDate: Starting glucose date for blending
    /// - Returns: Array of predicted glucose values
    ///
    /// ALG-DIAG-GEFF-005: Match Loop's predictGlucose momentum blending from LoopMath.swift
    /// Momentum is blended linearly with other effects: starts at 100% momentum, ends at 0%
    public func combinedPrediction(
        startingGlucose: Double,
        momentum: [GlucoseEffect] = [],
        effects: [[GlucoseEffect]],
        startDate: Date = Date()
    ) -> [PredictedGlucose] {
        // Step 1: Compute delta effects for non-momentum effects
        var effectDeltasByDate: [Date: Double] = [:]
        
        for effectArray in effects {
            var previousValue = effectArray.first?.quantity ?? 0
            for effect in effectArray {
                let delta = effect.quantity - previousValue
                effectDeltasByDate[effect.date, default: 0] += delta
                previousValue = effect.quantity
            }
        }
        
        // Step 2: Blend momentum effect (Loop's algorithm from LoopMath.swift:132-160)
        if momentum.count > 1 {
            var previousMomentumValue = momentum[0].quantity
            let blendCount = max(1, momentum.count - 2)
            let timeDelta = momentum[1].date.timeIntervalSince(momentum[0].date)
            let momentumOffset = startDate.timeIntervalSince(momentum[0].date)
            
            let blendSlope = 1.0 / Double(blendCount)
            let blendOffset = (timeDelta > 0) ? (momentumOffset / timeDelta * blendSlope) : 0
            
            for (index, effect) in momentum.enumerated() {
                let momentumDelta = effect.quantity - previousMomentumValue
                
                // split starts at 1.0 (full momentum) and decreases to 0.0 (no momentum)
                let split = min(1.0, max(0.0, Double(momentum.count - index) / Double(blendCount) - blendSlope + blendOffset))
                
                // Blend: momentum * split + other_effects * (1 - split)
                let otherEffectValue = effectDeltasByDate[effect.date] ?? 0
                let effectBlend = (1.0 - split) * otherEffectValue
                let momentumBlend = split * momentumDelta
                
                effectDeltasByDate[effect.date] = effectBlend + momentumBlend
                previousMomentumValue = effect.quantity
            }
        }
        
        // Step 3: Accumulate deltas to get cumulative effects, then add to starting glucose
        let sortedDates = effectDeltasByDate.keys.sorted()
        var predictions: [PredictedGlucose] = []
        var cumulativeEffect = 0.0
        
        // Add starting point
        predictions.append(PredictedGlucose(date: startDate, glucose: startingGlucose))
        
        for date in sortedDates where date > startDate {
            cumulativeEffect += effectDeltasByDate[date] ?? 0
            let predictedGlucose = max(39, min(400, startingGlucose + cumulativeEffect))
            predictions.append(PredictedGlucose(date: date, glucose: predictedGlucose))
        }
        
        return predictions
    }
    
    /// Legacy combined prediction (for backwards compatibility)
    public func combinedPrediction(
        startingGlucose: Double,
        effects: [[GlucoseEffect]]
    ) -> [PredictedGlucose] {
        // Legacy path: no momentum blending
        var effectsByDate: [Date: Double] = [:]
        
        for effectArray in effects {
            for effect in effectArray {
                effectsByDate[effect.date, default: 0] += effect.quantity
            }
        }
        
        let sortedDates = effectsByDate.keys.sorted()
        
        return sortedDates.map { date in
            let totalEffect = effectsByDate[date] ?? 0
            let predictedGlucose = max(39, min(400, startingGlucose + totalEffect))
            return PredictedGlucose(date: date, glucose: predictedGlucose)
        }
    }
    
    // MARK: - Full Prediction
    
    /// Generate complete glucose prediction
    /// - Parameters:
    ///   - currentGlucose: Current glucose value
    ///   - glucoseHistory: Recent glucose readings for momentum
    ///   - doses: Insulin doses for insulin effect
    ///   - carbEntries: Carb entries for carb effect
    ///   - insulinSensitivity: ISF in mg/dL per unit
    ///   - carbRatio: ICR in grams per unit
    ///   - startDate: Start time for prediction
    ///   - basalSchedule: Scheduled basal rates for net insulin effect (ALG-DIAG-GEFF-001)
    ///   - retrospectiveCorrectionEffects: RC effects from ICE-based calculation (ALG-DIAG-ICE-003)
    /// - Returns: Predicted glucose values
    ///
    /// ALG-DIAG-GEFF-005: Separate momentum for blending per Loop's algorithm
    public func predict(
        currentGlucose: Double,
        glucoseHistory: [GlucoseReading] = [],
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        insulinSensitivity: Double,
        carbRatio: Double,
        startDate: Date = Date(),
        basalSchedule: [AbsoluteScheduleValue<Double>]? = nil,
        retrospectiveCorrectionEffects: [GlucoseEffect]? = nil
    ) -> [PredictedGlucose] {
        var otherEffects: [[GlucoseEffect]] = []
        
        // Momentum effect (kept separate for blending)
        var momentum: [GlucoseEffect] = []
        if configuration.includeMomentum && !glucoseHistory.isEmpty {
            momentum = momentumEffect(
                glucoseHistory: glucoseHistory,
                startDate: startDate
            )
        }
        
        // Insulin effect
        // ALG-DIAG-GEFF-002/003: Use parity glucose effects when basalSchedule available
        if configuration.includeInsulinEffect && !doses.isEmpty {
            if let basalSchedule = basalSchedule, !basalSchedule.isEmpty {
                // Parity path: convert to RawInsulinDose, annotate with scheduled basal, use net effects
                // ALG-100-RECONCILE: Reconcile overlapping doses before annotation
                let rawDoses = doses.toReconciledRawInsulinDoses()
                
                // NOTE: ALG-COM-012 dose trimming is implemented but disabled pending investigation
                // The trimming logic made divergence worse (46 mg/dL vs 23 mg/dL), suggesting
                // either incorrect boundaries or Loop doesn't trim at this point in the pipeline.
                // TODO: Audit Loop's exact trimming location in DoseStore vs LoopAlgorithm
                
                let annotatedDoses = rawDoses.annotated(with: basalSchedule)
                let parityEffects = annotatedDoses.glucoseEffects(
                    insulinSensitivity: insulinSensitivity,
                    from: startDate,
                    to: startDate.addingTimeInterval(configuration.predictionDuration),
                    delta: configuration.predictionInterval
                )
                // Convert GlucoseEffectValue to GlucoseEffect (value is already negative for insulin)
                otherEffects.append(parityEffects.map { GlucoseEffect(date: $0.startDate, quantity: $0.value) })
            } else {
                // Legacy path: absolute units (fallback when no basal schedule)
                otherEffects.append(insulinEffect(
                    doses: doses,
                    insulinSensitivity: insulinSensitivity,
                    startDate: startDate
                ))
            }
        }
        
        // Carb effect
        if configuration.includeCarbEffect && !carbEntries.isEmpty {
            otherEffects.append(carbEffect(
                entries: carbEntries,
                carbRatio: carbRatio,
                insulinSensitivity: insulinSensitivity,
                startDate: startDate
            ))
        }
        
        // ALG-DIAG-ICE-003: Retrospective correction effect
        // RC adjusts predictions based on observed vs expected glucose changes
        if let rcEffects = retrospectiveCorrectionEffects, !rcEffects.isEmpty {
            otherEffects.append(rcEffects)
        }
        
        // If no effects at all, generate flat prediction
        if otherEffects.isEmpty && momentum.isEmpty {
            return generateFlatPrediction(
                glucose: currentGlucose,
                startDate: startDate
            )
        }
        
        // Use blended prediction with separate momentum
        return combinedPrediction(
            startingGlucose: currentGlucose,
            momentum: momentum,
            effects: otherEffects,
            startDate: startDate
        )
    }
    
    // MARK: - Helpers
    
    private func generateFlatPrediction(
        glucose: Double,
        startDate: Date
    ) -> [PredictedGlucose] {
        var predictions: [PredictedGlucose] = []
        var currentDate = startDate
        
        while currentDate <= startDate.addingTimeInterval(configuration.predictionDuration) {
            predictions.append(PredictedGlucose(date: currentDate, glucose: glucose))
            currentDate = currentDate.addingTimeInterval(configuration.predictionInterval)
        }
        
        return predictions
    }
}

// MARK: - Prediction Summary

/// Summary statistics for a prediction
public struct PredictionSummary: Sendable {
    public let minGlucose: Double
    public let maxGlucose: Double
    public let eventualGlucose: Double
    public let timeToMin: TimeInterval
    public let timeToMax: TimeInterval
    
    public init(predictions: [PredictedGlucose]) {
        guard !predictions.isEmpty else {
            self.minGlucose = 0
            self.maxGlucose = 0
            self.eventualGlucose = 0
            self.timeToMin = 0
            self.timeToMax = 0
            return
        }
        
        let startDate = predictions.first!.date
        
        var minGlucose = Double.infinity
        var maxGlucose = -Double.infinity
        var timeToMin: TimeInterval = 0
        var timeToMax: TimeInterval = 0
        
        for prediction in predictions {
            if prediction.glucose < minGlucose {
                minGlucose = prediction.glucose
                timeToMin = prediction.date.timeIntervalSince(startDate)
            }
            if prediction.glucose > maxGlucose {
                maxGlucose = prediction.glucose
                timeToMax = prediction.date.timeIntervalSince(startDate)
            }
        }
        
        self.minGlucose = minGlucose
        self.maxGlucose = maxGlucose
        self.eventualGlucose = predictions.last?.glucose ?? 0
        self.timeToMin = timeToMin
        self.timeToMax = timeToMax
    }
    
    /// Time to minimum in minutes
    public var timeToMinMinutes: Int {
        Int(timeToMin / 60)
    }
    
    /// Time to maximum in minutes
    public var timeToMaxMinutes: Int {
        Int(timeToMax / 60)
    }
}

// MARK: - Effect Combiner

/// Utility for combining multiple effect types
public struct EffectCombiner: Sendable {
    
    /// Combine effects at aligned time intervals
    public static func combine(
        effects: [[GlucoseEffect]],
        startDate: Date,
        duration: TimeInterval,
        interval: TimeInterval
    ) -> [GlucoseEffect] {
        var result: [GlucoseEffect] = []
        var currentDate = startDate
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            var totalEffect: Double = 0
            
            for effectArray in effects {
                // Find the effect closest to this time
                if let closest = effectArray.min(by: {
                    abs($0.date.timeIntervalSince(currentDate)) < abs($1.date.timeIntervalSince(currentDate))
                }) {
                    // Only use if within half an interval
                    if abs(closest.date.timeIntervalSince(currentDate)) < interval / 2 {
                        totalEffect += closest.quantity
                    }
                }
            }
            
            result.append(GlucoseEffect(date: currentDate, quantity: totalEffect))
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return result
    }
    
    /// Interpolate effects to regular intervals
    public static func interpolate(
        effects: [GlucoseEffect],
        startDate: Date,
        duration: TimeInterval,
        interval: TimeInterval
    ) -> [GlucoseEffect] {
        guard effects.count >= 2 else { return effects }
        
        let sortedEffects = effects.sorted { $0.date < $1.date }
        var result: [GlucoseEffect] = []
        var currentDate = startDate
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            // Find surrounding points for interpolation
            let before = sortedEffects.last { $0.date <= currentDate }
            let after = sortedEffects.first { $0.date > currentDate }
            
            let effect: Double
            if let b = before, let a = after {
                // Linear interpolation
                let totalTime = a.date.timeIntervalSince(b.date)
                let elapsed = currentDate.timeIntervalSince(b.date)
                let fraction = totalTime > 0 ? elapsed / totalTime : 0
                effect = b.quantity + (a.quantity - b.quantity) * fraction
            } else if let b = before {
                effect = b.quantity
            } else if let a = after {
                effect = a.quantity
            } else {
                effect = 0
            }
            
            result.append(GlucoseEffect(date: currentDate, quantity: effect))
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return result
    }
}
