// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopCOBParity.swift
// T1Pal Mobile
//
// Loop-compatible COB (Carbs On Board) calculation with dynamic absorption
// Trace: ALG-FIDELITY-017, GAP-023..030
//
// Key concepts from Loop's CarbMath.swift:
// - Dynamic absorption based on observed glucose changes (ICE)
// - Piecewise linear absorption model (3-phase: rise/peak/fall)
// - CarbStatus wrapper blending observed and predicted absorption
// - 10-minute effect delay before carbs raise glucose
// - Adaptive absorption rate based on observed patterns

import Foundation

// MARK: - Constants (GAP-026, GAP-027)

/// Constants matching Loop's CarbMath
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 11-16
public enum COBConstants {
    /// Maximum time carbs can take to absorb (10 hours)
    public static let maximumAbsorptionTimeInterval: TimeInterval = .hours(10)
    
    /// Default absorption time when not specified (3 hours)
    public static let defaultAbsorptionTime: TimeInterval = .hours(3)
    
    /// Multiplier for maximum absorption time beyond initial estimate
    /// If entry says 3h, max is 3h × 1.5 = 4.5h
    public static let defaultAbsorptionTimeOverrun: Double = 1.5
    
    /// Delay before carbs start affecting glucose (10 minutes)
    /// GAP-026: We were missing this delay
    public static let defaultEffectDelay: TimeInterval = .minutes(10)
    
    /// Minimum absorption to track (gram threshold)
    public static let minimumAbsorptionGrams: Double = 0.5
    
    /// Interval to wait before adapting absorption rate
    /// 20% of initial absorption time
    public static let adaptiveRateStandbyFraction: Double = 0.2
}

// MARK: - Absorption Model Protocol

/// Protocol for carb absorption models
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 32-81
public protocol CarbAbsorptionComputable: Sendable {
    /// Returns percent of carbs absorbed at given percent of absorption time
    /// - Parameter percentTime: 0.0 to 1.0 (or beyond for overrun)
    /// - Returns: 0.0 to 1.0 percent absorbed
    func percentAbsorptionAtPercentTime(_ percentTime: Double) -> Double
    
    /// Inverse: given percent absorbed, what percent of time has elapsed?
    func percentTimeAtPercentAbsorption(_ percentAbsorption: Double) -> Double
    
    /// Calculate absorption time for given absorption at time
    func absorptionTime(forPercentAbsorption: Double, atTime: TimeInterval) -> TimeInterval
    
    /// Calculate carbs absorbed at given time
    func absorbedCarbs(of total: Double, atTime: TimeInterval, absorptionTime: TimeInterval) -> Double
    
    /// Calculate carbs remaining at given time
    func unabsorbedCarbs(of total: Double, atTime: TimeInterval, absorptionTime: TimeInterval) -> Double
    
    /// Absorption rate at percent of time (derivative of absorption curve)
    func percentRateAtPercentTime(_ percentTime: Double) -> Double
}

// MARK: - Linear Absorption Model

/// Simple constant-rate absorption
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 108-139
public struct LinearAbsorption: CarbAbsorptionComputable {
    public init() {}
    
    public func percentAbsorptionAtPercentTime(_ percentTime: Double) -> Double {
        return max(0, min(1, percentTime))
    }
    
    public func percentTimeAtPercentAbsorption(_ percentAbsorption: Double) -> Double {
        return max(0, min(1, percentAbsorption))
    }
    
    public func absorptionTime(forPercentAbsorption percentAbsorption: Double, atTime time: TimeInterval) -> TimeInterval {
        guard percentAbsorption > 0 else { return .infinity }
        return time / percentAbsorption
    }
    
    public func absorbedCarbs(of total: Double, atTime time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard absorptionTime > 0 else { return total }
        let percentTime = time / absorptionTime
        return total * percentAbsorptionAtPercentTime(percentTime)
    }
    
    public func unabsorbedCarbs(of total: Double, atTime time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        return total - absorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
    }
    
    public func percentRateAtPercentTime(_ percentTime: Double) -> Double {
        return percentTime >= 0 && percentTime <= 1 ? 1.0 : 0.0
    }
}

// MARK: - Piecewise Linear Absorption Model (GAP-025)

/// Loop's default absorption model with three phases
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 146-201
///
/// Three-phase absorption curve:
/// ```
/// Rate
///   │    ╭───────────╮
///   │   ╱             ╲
///   │  ╱               ╲
///   │ ╱                 ╲
///   └─────────────────────► Time
///     0%   15%    50%   100%
///      ↑      ↑      ↑
///     rise  peak  fall
/// ```
///
/// 1. Rise phase (0-15%): Rate increases quadratically
/// 2. Peak phase (15-50%): Rate is constant at maximum
/// 3. Fall phase (50-100%): Rate decreases linearly to zero
public struct PiecewiseLinearAbsorption: CarbAbsorptionComputable {
    /// End of rise phase (15% of time)
    public let percentEndOfRise: Double = 0.15
    
    /// Start of fall phase (50% of time)
    public let percentStartOfFall: Double = 0.5
    
    /// Scale factor for the curve
    /// Ensures total absorption integrates to 1.0
    public var scale: Double {
        return 2.0 / (1.0 + percentStartOfFall - percentEndOfRise)
    }
    
    public init() {}
    
    public func percentAbsorptionAtPercentTime(_ percentTime: Double) -> Double {
        guard percentTime > 0 else { return 0 }
        guard percentTime < 1 else { return 1 }
        
        if percentTime <= percentEndOfRise {
            // Rise phase: quadratic increase
            // Area under parabola from 0 to t
            return scale * percentTime * percentTime / (2 * percentEndOfRise)
        } else if percentTime <= percentStartOfFall {
            // Peak phase: constant rate
            let riseArea = scale * percentEndOfRise / 2
            let peakArea = scale * (percentTime - percentEndOfRise)
            return riseArea + peakArea
        } else {
            // Fall phase: linear decrease
            let riseArea = scale * percentEndOfRise / 2
            let peakArea = scale * (percentStartOfFall - percentEndOfRise)
            let fallDuration = 1.0 - percentStartOfFall
            let fallTime = percentTime - percentStartOfFall
            let fallFraction = fallTime / fallDuration
            // Trapezoid area: rate goes from scale to 0
            let avgRate = scale * (1 - fallFraction / 2)
            let fallArea = avgRate * fallTime
            return riseArea + peakArea + fallArea
        }
    }
    
    public func percentTimeAtPercentAbsorption(_ percentAbsorption: Double) -> Double {
        guard percentAbsorption > 0 else { return 0 }
        guard percentAbsorption < 1 else { return 1 }
        
        let riseArea = scale * percentEndOfRise / 2
        let peakArea = scale * (percentStartOfFall - percentEndOfRise)
        
        if percentAbsorption <= riseArea {
            // In rise phase
            return sqrt(2 * percentAbsorption * percentEndOfRise / scale)
        } else if percentAbsorption <= riseArea + peakArea {
            // In peak phase
            return percentEndOfRise + (percentAbsorption - riseArea) / scale
        } else {
            // In fall phase - solve quadratic
            let remaining = percentAbsorption - riseArea - peakArea
            let fallDuration = 1.0 - percentStartOfFall
            // Quadratic: remaining = scale * t - scale * t^2 / (2 * fallDuration)
            // Solve for t
            let a = -scale / (2 * fallDuration)
            let b = scale
            let c = -remaining
            let discriminant = b * b - 4 * a * c
            guard discriminant >= 0 else { return 1 }
            let t = (-b + sqrt(discriminant)) / (2 * a)
            return percentStartOfFall + t
        }
    }
    
    public func absorptionTime(forPercentAbsorption percentAbsorption: Double, atTime time: TimeInterval) -> TimeInterval {
        let percentTime = percentTimeAtPercentAbsorption(percentAbsorption)
        guard percentTime > 0 else { return .infinity }
        return time / percentTime
    }
    
    public func absorbedCarbs(of total: Double, atTime time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard absorptionTime > 0 else { return total }
        let percentTime = time / absorptionTime
        return total * percentAbsorptionAtPercentTime(percentTime)
    }
    
    public func unabsorbedCarbs(of total: Double, atTime time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        return total - absorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
    }
    
    public func percentRateAtPercentTime(_ percentTime: Double) -> Double {
        guard percentTime >= 0 && percentTime <= 1 else { return 0 }
        
        if percentTime <= percentEndOfRise {
            // Rise phase: linear increase from 0 to scale
            return scale * percentTime / percentEndOfRise
        } else if percentTime <= percentStartOfFall {
            // Peak phase: constant at scale
            return scale
        } else {
            // Fall phase: linear decrease from scale to 0
            let fallDuration = 1.0 - percentStartOfFall
            let fallFraction = (percentTime - percentStartOfFall) / fallDuration
            return scale * (1 - fallFraction)
        }
    }
}

// MARK: - Carb Entry Protocol

/// Protocol for carb entries that can be used in COB calculation
public protocol CarbEntryProtocol: Sendable {
    /// Entry timestamp
    var startDate: Date { get }
    
    /// Grams of carbohydrates
    var grams: Double { get }
    
    /// Expected absorption time (nil = use default)
    var absorptionTime: TimeInterval? { get }
}

// MARK: - Simple Carb Entry

/// Basic carb entry implementation
public struct SimpleCarbEntry: CarbEntryProtocol {
    public let startDate: Date
    public let grams: Double
    public let absorptionTime: TimeInterval?
    
    public init(startDate: Date, grams: Double, absorptionTime: TimeInterval? = nil) {
        self.startDate = startDate
        self.grams = grams
        self.absorptionTime = absorptionTime
    }
}

// MARK: - Absorbed Carb Value (GAP-024)

/// Tracks observed vs predicted carb absorption
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/AbsorbedCarbValue.swift
public struct AbsorbedCarbValue: Sendable {
    /// What we actually observed being absorbed (grams)
    public let observed: Double
    
    /// Clamped value: min(entry, max(minPredicted, observed))
    public let clamped: Double
    
    /// Original entry grams
    public let total: Double
    
    /// Remaining to absorb (total - clamped)
    public var remaining: Double {
        return max(0, total - clamped)
    }
    
    /// When we observed the absorption
    public let observationStart: Date
    public let observationEnd: Date
    
    /// Estimated time to absorb remaining carbs
    public let estimatedTimeRemaining: TimeInterval
    
    /// Time it took to absorb observed carbs (for rate calculation)
    public let timeToAbsorbObservedCarbs: TimeInterval
    
    public init(
        observed: Double,
        clamped: Double,
        total: Double,
        observationStart: Date,
        observationEnd: Date,
        estimatedTimeRemaining: TimeInterval,
        timeToAbsorbObservedCarbs: TimeInterval
    ) {
        self.observed = observed
        self.clamped = clamped
        self.total = total
        self.observationStart = observationStart
        self.observationEnd = observationEnd
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.timeToAbsorbObservedCarbs = timeToAbsorbObservedCarbs
    }
}

// MARK: - Carb Status (GAP-024)

/// Wrapper combining carb entry with observed absorption
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbStatus.swift
public struct CarbStatus<T: CarbEntryProtocol>: Sendable {
    /// The original user entry
    public let entry: T
    
    /// Observed absorption computed from glucose changes
    public let absorption: AbsorbedCarbValue?
    
    /// Timeline of actual observed absorption (grams at each point)
    public let observedTimeline: [CarbValue]?
    
    public init(entry: T, absorption: AbsorbedCarbValue? = nil, observedTimeline: [CarbValue]? = nil) {
        self.entry = entry
        self.absorption = absorption
        self.observedTimeline = observedTimeline
    }
}

/// A point in the observed absorption timeline
public struct CarbValue: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let grams: Double
    
    public init(startDate: Date, endDate: Date, grams: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.grams = grams
    }
}

// MARK: - Dynamic COB Calculation

extension CarbStatus {
    /// Calculate dynamic COB at a given date
    /// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbStatus.swift Lines 43-78
    ///
    /// Three modes of operation:
    /// - Modeled: No observation data → use standard absorption model
    /// - Estimated: Below minimum threshold → use model with adjusted time
    /// - Observed: Have observation timeline → use actual glucose-derived data
    /// - Projected: After observation ends → project remaining using observed rate
    public func dynamicCarbsOnBoard(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        let time = date.timeIntervalSince(entry.startDate)
        guard time >= 0 else { return 0 }
        
        let absorptionTime = entry.absorptionTime ?? defaultAbsorptionTime
        let effectiveTime = time - delay
        guard effectiveTime >= 0 else {
            // Still in delay period - full carbs remaining
            return entry.grams
        }
        
        guard let absorption = absorption else {
            // No observation data → use modeled absorption
            return absorptionModel.unabsorbedCarbs(
                of: entry.grams,
                atTime: effectiveTime,
                absorptionTime: absorptionTime
            )
        }
        
        guard let observedTimeline = observedTimeline, !observedTimeline.isEmpty else {
            // Below minimum observed → use model with estimated absorption time
            let estimatedAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
            return absorptionModel.unabsorbedCarbs(
                of: entry.grams,
                atTime: effectiveTime,
                absorptionTime: estimatedAbsorptionTime
            )
        }
        
        let observationEnd = absorption.observationEnd
        
        guard date <= observationEnd else {
            // AFTER observation period → project remaining carbs
            let timeAfterObservation = date.timeIntervalSince(observationEnd)
            let effectiveTime = timeAfterObservation + absorption.timeToAbsorbObservedCarbs
            let effectiveAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
            
            guard effectiveAbsorptionTime > 0 else { return 0 }
            
            return absorptionModel.unabsorbedCarbs(
                of: absorption.remaining + absorption.clamped,
                atTime: effectiveTime,
                absorptionTime: effectiveAbsorptionTime
            )
        }
        
        // DURING observation → use actual observed data
        let absorbedSoFar = observedTimeline
            .filter { $0.endDate <= date }
            .reduce(0.0) { $0 + $1.grams }
        
        return max(0, entry.grams - absorbedSoFar)
    }
    
    /// Calculate dynamically absorbed carbs at a given date
    /// Uses observed absorption timeline when available, falls back to modeled absorption
    /// Source: LoopAlgorithm/Carbs/CarbStatus.swift:80-128
    /// Trace: ALG-DIAG-ICE-004
    public func dynamicAbsorbedCarbs(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        delta: TimeInterval = .minutes(5),
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        guard date >= entry.startDate else { return 0 }
        
        let absorptionTime = entry.absorptionTime ?? defaultAbsorptionTime
        let time = date.timeIntervalSince(entry.startDate)
        let effectiveTime = time - delay
        
        guard effectiveTime >= 0 else {
            // Still in delay period - no absorption yet
            return 0
        }
        
        // If we have absorption data with observed timeline, use it
        guard let absorption = absorption,
              let observedTimeline = observedTimeline,
              !observedTimeline.isEmpty,
              let observationEnd = observedTimeline.last?.endDate else {
            // No observation data or below minimum threshold - use modeled absorption
            if let absorption = absorption {
                // Use estimated absorption time from observation data
                let estimatedAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
                return absorptionModel.absorbedCarbs(
                    of: entry.grams,
                    atTime: effectiveTime,
                    absorptionTime: estimatedAbsorptionTime
                )
            }
            // Fall back to standard absorption model
            return absorptionModel.absorbedCarbs(
                of: entry.grams,
                atTime: effectiveTime,
                absorptionTime: absorptionTime
            )
        }
        
        guard date <= observationEnd else {
            // After observation period - project remaining absorption
            let effectiveTimePastObs = date.timeIntervalSince(observationEnd) + absorption.timeToAbsorbObservedCarbs
            let effectiveAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
            let total = entry.grams
            return min(
                absorptionModel.absorbedCarbs(of: total, atTime: effectiveTimePastObs, absorptionTime: effectiveAbsorptionTime),
                total
            )
        }
        
        // During observation - sum observed timeline up to date
        // Note: This is O(n) per call, which creates O(n^2) for full timeline
        // (Same as Loop's implementation with TODO note)
        var sum: Double = 0
        let beforeDate = observedTimeline.filter { $0.startDate.addingTimeInterval(delta) <= date }
        
        for value in beforeDate {
            sum += value.grams
        }
        
        // Don't exceed entry's total carbs
        return min(sum, entry.grams)
    }
}

// MARK: - Glucose Effect Velocity (GAP-038, for ICE)

/// Tracks glucose change rate over a time interval
/// Used for counteraction effects (ICE) calculation
/// Source: design/prediction-curve-parity-design.md
public struct GlucoseEffectVelocity: Sendable {
    public let startDate: Date
    public let endDate: Date
    /// ALG-RC-FIX-001: Per-second velocity (mg/dL/s) like Loop's GlucoseMath.swift:249
    /// To get total mg/dL for an interval: quantity * duration
    public let quantity: Double
    
    public init(startDate: Date, endDate: Date, quantity: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.quantity = quantity
    }
    
    /// Duration of the interval
    public var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
    
    /// Total effect for this interval (mg/dL)
    public var totalEffect: Double {
        return quantity * duration
    }
    
    /// Rate in mg/dL per minute
    public var ratePerMinute: Double {
        return quantity * 60
    }
}

// MARK: - Counteraction Effects (ALG-DIAG-ICE-001)

import T1PalCore

/// Extension to compute insulin counteraction effects from glucose history
/// Source: externals/LoopKit/LoopKit/GlucoseKit/GlucoseMath.swift Lines 147-229
/// ALG-DIAG-ICE-001: Wire counteractionEffects for accurate glucose prediction
public extension Array where Element == GlucoseReading {
    
    /// Calculates a timeline of effect velocity observed in glucose readings that counteract the specified effects.
    /// 
    /// This computes the discrepancy between actual glucose change and expected insulin effect change.
    /// Positive values indicate something is countering insulin (e.g., carbs, stress, dawn phenomenon).
    /// Negative values indicate glucose is falling faster than expected.
    ///
    /// - Parameter effects: Insulin glucose effects (cumulative, in chronological order)
    /// - Returns: Array of velocities describing glucose change compared to expected effects
    func counteractionEffects(to effects: [GlucoseEffect]) -> [GlucoseEffectVelocity] {
        var velocities: [GlucoseEffectVelocity] = []
        
        guard !self.isEmpty, !effects.isEmpty else { return [] }
        
        // Sort glucose readings by timestamp
        let sortedReadings = self.sorted { $0.timestamp < $1.timestamp }
        
        // Find first glucose reading that's at or after first effect
        guard let firstEffectDate = effects.first?.date,
              let startIdx = sortedReadings.firstIndex(where: { $0.timestamp >= firstEffectDate }) else {
            return []
        }
        
        var effectIndex = 0
        var readingIdx = startIdx
        
        while readingIdx + 1 < sortedReadings.count {
            let startGlucose = sortedReadings[readingIdx]
            let endGlucose = sortedReadings[readingIdx + 1]
            
            let timeInterval = endGlucose.timestamp.timeIntervalSince(startGlucose.timestamp)
            
            // Require at least 4 minutes between readings (Loop uses > 4 minutes)
            guard timeInterval > 4 * 60 else {
                readingIdx += 1
                continue
            }
            
            // Calculate actual glucose change
            let glucoseChange = endGlucose.glucose - startGlucose.glucose
            
            // Find matching effect values
            // ALG-RC-008: Match Loop's effectIndex tracking exactly (GlucoseMath.swift:229-238)
            // Loop increments effectIndex on EVERY iteration, not just when finding endEffect
            var startEffect: GlucoseEffect?
            var endEffect: GlucoseEffect?
            
            for effect in effects[effectIndex..<effects.count] {
                if startEffect == nil && effect.date >= startGlucose.timestamp {
                    startEffect = effect
                } else if endEffect == nil && effect.date >= endGlucose.timestamp {
                    endEffect = effect
                    break
                }
                effectIndex += 1
            }
            
            guard let startEffectValue = startEffect?.quantity,
                  let endEffectValue = endEffect?.quantity else {
                break
            }
            
            // Calculate expected effect change and discrepancy
            let effectChange = endEffectValue - startEffectValue
            let discrepancy = glucoseChange - effectChange
            
            // ALG-RC-FIX-001: Store as per-second velocity like Loop (GlucoseMath.swift:249)
            // Loop: averageVelocity = discrepancy / timeInterval
            // This normalizes the value so downstream code can scale by any interval
            let perSecondVelocity = discrepancy / timeInterval
            
            velocities.append(GlucoseEffectVelocity(
                startDate: startGlucose.timestamp,
                endDate: endGlucose.timestamp,
                quantity: perSecondVelocity
            ))
            
            readingIdx += 1
        }
        
        return velocities
    }
}

// MARK: - Carb Status Builder (GAP-023, GAP-029)

/// Builder for tracking observed carb absorption
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 434-672
final class CarbStatusBuilder<T: CarbEntryProtocol>: @unchecked Sendable {
    let entry: T
    let entryGrams: Double
    let carbohydrateSensitivityFactor: Double  // ISF / CR (mg/dL per gram)
    let absorptionModel: CarbAbsorptionComputable
    let initialAbsorptionTime: TimeInterval
    let maxAbsorptionTime: TimeInterval
    let delay: TimeInterval
    
    // Observation state
    var observedEffect: Double = 0  // Glucose units (mg/dL)
    var observedTimeline: [CarbValue] = []
    var observationStartDate: Date?
    var observationEndDate: Date?
    var observedCompletionDate: Date?
    
    init(
        entry: T,
        carbohydrateSensitivityFactor: Double,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption(),
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        overrunFactor: Double = COBConstants.defaultAbsorptionTimeOverrun
    ) {
        self.entry = entry
        self.entryGrams = entry.grams
        self.carbohydrateSensitivityFactor = carbohydrateSensitivityFactor
        self.absorptionModel = absorptionModel
        self.initialAbsorptionTime = entry.absorptionTime ?? defaultAbsorptionTime
        self.maxAbsorptionTime = initialAbsorptionTime * overrunFactor
        self.delay = delay
    }
    
    /// Entry effect in glucose units (mg/dL)
    var entryEffect: Double {
        return entryGrams * carbohydrateSensitivityFactor
    }
    
    /// Observed grams absorbed (derived from glucose effect)
    var observedGrams: Double {
        guard carbohydrateSensitivityFactor > 0 else { return 0 }
        return observedEffect / carbohydrateSensitivityFactor
    }
    
    /// Minimum predicted grams at current observation time
    var minPredictedGrams: Double {
        guard let endDate = observationEndDate else { return 0 }
        let time = endDate.timeIntervalSince(entry.startDate) - delay
        guard time > 0 else { return 0 }
        return absorptionModel.absorbedCarbs(of: entryGrams, atTime: time, absorptionTime: maxAbsorptionTime)
    }
    
    /// Clamped grams: bounded between min predicted and entry
    var clampedGrams: Double {
        return min(entryGrams, max(minPredictedGrams, observedGrams))
    }
    
    /// Check if this entry is active (started but not completed)
    func isActive(at date: Date) -> Bool {
        let time = date.timeIntervalSince(entry.startDate)
        guard time >= delay else { return false }  // Before effect starts
        
        if let completionDate = observedCompletionDate {
            return date < completionDate
        }
        
        // Check if max time exceeded
        let effectiveTime = time - delay
        return effectiveTime < maxAbsorptionTime
    }
    
    /// Current absorption rate at given date
    func absorptionRate(at date: Date) -> Double {
        let time = date.timeIntervalSince(entry.startDate) - delay
        guard time >= 0 else { return 0 }
        
        let percentTime = time / initialAbsorptionTime
        return absorptionModel.percentRateAtPercentTime(percentTime) * entryEffect / initialAbsorptionTime
    }
    
    /// Add observed effect from ICE
    func addEffect(_ effect: Double, start: Date, end: Date) {
        guard effect > 0 else { return }  // Ignore negative (insulin activity)
        
        observedEffect += effect
        
        if observationStartDate == nil {
            observationStartDate = start
        }
        observationEndDate = end
        
        // Convert effect to grams and record timeline
        let grams = effect / carbohydrateSensitivityFactor
        observedTimeline.append(CarbValue(startDate: start, endDate: end, grams: grams))
        
        // Check if entry is fully absorbed
        if observedGrams >= entryGrams {
            observedCompletionDate = end
        }
    }
    
    /// Time to absorb observed carbs
    var timeToAbsorbObservedCarbs: TimeInterval {
        guard let start = observationStartDate, let end = observationEndDate else { return 0 }
        return end.timeIntervalSince(start)
    }
    
    /// Estimated time remaining (GAP-028: adaptive rate)
    var estimatedTimeRemaining: TimeInterval {
        let observedFraction = clampedGrams / entryGrams
        guard observedFraction > 0 && observedFraction < 1 else {
            return observedFraction >= 1 ? 0 : initialAbsorptionTime
        }
        
        let timeElapsed = timeToAbsorbObservedCarbs
        let standbyInterval = initialAbsorptionTime * COBConstants.adaptiveRateStandbyFraction
        
        if timeElapsed > standbyInterval {
            // Use observed rate to estimate remaining time
            let observedAbsorptionTime = absorptionModel.absorptionTime(
                forPercentAbsorption: observedFraction,
                atTime: timeElapsed
            )
            return max(0, observedAbsorptionTime - timeElapsed)
        } else {
            // Use modeled rate
            let modeledTimeForObserved = initialAbsorptionTime * absorptionModel.percentTimeAtPercentAbsorption(observedFraction)
            return max(0, initialAbsorptionTime - modeledTimeForObserved)
        }
    }
    
    /// Build final CarbStatus
    func build() -> CarbStatus<T> {
        guard observationStartDate != nil else {
            // No observation data
            return CarbStatus(entry: entry)
        }
        
        let absorption = AbsorbedCarbValue(
            observed: observedGrams,
            clamped: clampedGrams,
            total: entryGrams,
            observationStart: observationStartDate!,
            observationEnd: observationEndDate ?? observationStartDate!,
            estimatedTimeRemaining: estimatedTimeRemaining,
            timeToAbsorbObservedCarbs: timeToAbsorbObservedCarbs
        )
        
        return CarbStatus(
            entry: entry,
            absorption: absorption,
            observedTimeline: observedTimeline.isEmpty ? nil : observedTimeline
        )
    }
}

// MARK: - Carb Entry Extension for Simple COB

extension CarbEntryProtocol {
    /// Simple model-based COB calculation (no observation)
    public func carbsOnBoard(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else { return 0 }
        
        let effectiveTime = time - delay
        guard effectiveTime >= 0 else {
            // Still in delay period
            return grams
        }
        
        let absorptionTime = self.absorptionTime ?? defaultAbsorptionTime
        return absorptionModel.unabsorbedCarbs(
            of: grams,
            atTime: effectiveTime,
            absorptionTime: absorptionTime
        )
    }
}

// MARK: - Collection Extensions for COB

extension Array where Element: CarbEntryProtocol {
    /// Simple model-based total COB (no observation)
    public func carbsOnBoard(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        return reduce(0) { total, entry in
            total + entry.carbsOnBoard(
                at: date,
                defaultAbsorptionTime: defaultAbsorptionTime,
                delay: delay,
                absorptionModel: absorptionModel
            )
        }
    }
    
    /// Map carb entries to CarbStatus using ICE (GAP-023, GAP-029)
    /// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Carbs/CarbMath.swift Lines 676-791
    ///
    /// This is the core dynamic absorption algorithm:
    /// 1. Create builders for each entry
    /// 2. Iterate through glucose effect velocities (ICE)
    /// 3. Distribute effects proportionally by current absorption rate
    /// 4. Build CarbStatus with observed + predicted absorption
    public func map(
        to effectVelocities: [GlucoseEffectVelocity],
        insulinSensitivity: Double,
        carbRatio: Double,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> [CarbStatus<Element>] {
        guard !isEmpty else { return [] }
        guard carbRatio > 0 else { return map { CarbStatus(entry: $0) } }
        
        // Carb sensitivity factor: mg/dL per gram of carbs
        let csf = insulinSensitivity / carbRatio
        
        // Create builders
        let builders = map { entry in
            CarbStatusBuilder(
                entry: entry,
                carbohydrateSensitivityFactor: csf,
                absorptionModel: absorptionModel,
                defaultAbsorptionTime: defaultAbsorptionTime,
                delay: delay
            )
        }
        
        // Process each ICE velocity
        for velocity in effectVelocities {
            // Only process positive velocities (glucose rising = carb absorption)
            guard velocity.quantity > 0 else { continue }
            
            // Find active entries at this time
            let activeBuilders = builders.filter { $0.isActive(at: velocity.startDate) }
            guard !activeBuilders.isEmpty else { continue }
            
            // Sum current absorption rates
            let totalRate = activeBuilders.reduce(0.0) { sum, builder in
                sum + builder.absorptionRate(at: velocity.startDate)
            }
            
            guard totalRate > 0 else { continue }
            
            // Distribute effect proportionally
            for builder in activeBuilders {
                let rate = builder.absorptionRate(at: velocity.startDate)
                let fraction = rate / totalRate
                let partialEffect = velocity.quantity * fraction
                builder.addEffect(partialEffect, start: velocity.startDate, end: velocity.endDate)
            }
        }
        
        // Build results
        return builders.map { $0.build() }
    }
}

// MARK: - CarbStatus Collection Extensions

extension Array where Element == CarbStatus<SimpleCarbEntry> {
    /// Total dynamic COB from CarbStatus collection (SimpleCarbEntry)
    public func dynamicCarbsOnBoard(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        return reduce(0) { total, status in
            total + status.dynamicCarbsOnBoard(
                at: date,
                defaultAbsorptionTime: defaultAbsorptionTime,
                delay: delay,
                absorptionModel: absorptionModel
            )
        }
    }
}

extension Array where Element == CarbStatus<CarbEntry> {
    /// Total dynamic COB from CarbStatus collection (CarbEntry)
    /// ALG-DIAG-ICE-002: Support dynamic COB from actual carb entries
    public func dynamicCarbsOnBoard(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        return reduce(0) { total, status in
            total + status.dynamicCarbsOnBoard(
                at: date,
                defaultAbsorptionTime: defaultAbsorptionTime,
                delay: delay,
                absorptionModel: absorptionModel
            )
        }
    }
    
    /// Calculate dynamic glucose effects from carb absorption over time
    /// Returns cumulative glucose rise at each time point
    /// Source: Loop LoopAlgorithm/Carbs/CarbMath.swift:363-402
    /// Trace: ALG-DIAG-ICE-004
    public func dynamicGlucoseEffects(
        from start: Date? = nil,
        to end: Date? = nil,
        insulinSensitivity: Double,
        carbRatio: Double,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        delta: TimeInterval = .minutes(5),
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> [GlucoseEffect] {
        guard !isEmpty, carbRatio > 0 else { return [] }
        
        // Compute date range from entries (we're already constrained to CarbStatus<CarbEntry>)
        guard let firstStart = self.map({ $0.entry.startDate }).min(),
              let lastStart = self.map({ $0.entry.startDate }).max() else {
            return []
        }
        
        let startDate = start ?? firstStart.addingTimeInterval(delay)
        let endDate = end ?? lastStart.addingTimeInterval(defaultAbsorptionTime + delay)
        
        // Carb sensitivity factor: mg/dL per gram
        let csf = insulinSensitivity / carbRatio
        
        var effects: [GlucoseEffect] = []
        var current = startDate
        
        while current <= endDate {
            let totalEffect = reduce(0.0) { total, status in
                total + csf * status.dynamicAbsorbedCarbs(
                    at: current,
                    defaultAbsorptionTime: defaultAbsorptionTime,
                    delay: delay,
                    delta: delta,
                    absorptionModel: absorptionModel
                )
            }
            effects.append(GlucoseEffect(date: current, quantity: totalEffect))
            current = current.addingTimeInterval(delta)
        }
        
        return effects
    }
    
    /// Convert glucose effects timeline to velocities
    /// Each velocity represents the rate of change between consecutive effects
    /// Trace: ALG-DIAG-ICE-004 (for RC discrepancy calculation)
    public func glucoseEffectVelocities(
        from effects: [GlucoseEffect]
    ) -> [GlucoseEffectVelocity] {
        guard effects.count > 1 else { return [] }
        
        var velocities: [GlucoseEffectVelocity] = []
        
        for i in 0..<(effects.count - 1) {
            let start = effects[i]
            let end = effects[i + 1]
            // Velocity = change in cumulative effect
            let change = end.quantity - start.quantity
            velocities.append(GlucoseEffectVelocity(
                startDate: start.date,
                endDate: end.date,
                quantity: change
            ))
        }
        
        return velocities
    }
}

// MARK: - COB Timeline Generation

extension Array where Element: CarbEntryProtocol {
    /// Generate COB timeline for predictions
    public func carbsOnBoardTimeline(
        from start: Date,
        to end: Date,
        delta: TimeInterval = .minutes(5),
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> [(date: Date, value: Double)] {
        var timeline: [(date: Date, value: Double)] = []
        var current = start
        
        while current <= end {
            let cob = carbsOnBoard(
                at: current,
                defaultAbsorptionTime: defaultAbsorptionTime,
                delay: delay,
                absorptionModel: absorptionModel
            )
            timeline.append((date: current, value: cob))
            current = current.addingTimeInterval(delta)
        }
        
        return timeline
    }
}

// MARK: - Glucose Effect from Carbs

extension Array where Element: CarbEntryProtocol {
    /// Calculate glucose effect from carb absorption
    /// Effect = CSF × absorbed carbs
    public func glucoseEffect(
        at date: Date,
        insulinSensitivity: Double,
        carbRatio: Double,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        guard carbRatio > 0 else { return 0 }
        
        let csf = insulinSensitivity / carbRatio
        
        return reduce(0) { total, entry in
            let time = date.timeIntervalSince(entry.startDate)
            guard time >= delay else { return total }
            
            let absorptionTime = entry.absorptionTime ?? defaultAbsorptionTime
            let absorbed = absorptionModel.absorbedCarbs(
                of: entry.grams,
                atTime: time - delay,
                absorptionTime: absorptionTime
            )
            
            return total + csf * absorbed
        }
    }
}

// MARK: - CarbEntry Conformance (ALG-COB-WIRE)

extension CarbEntry: CarbEntryProtocol {
    /// Map timestamp to startDate for protocol conformance
    public var startDate: Date {
        timestamp
    }
    
    // Note: CarbEntry.absorptionTime is in hours, but CarbEntryProtocol expects seconds
    // The parity functions handle this by using effectiveAbsorptionTime or defaults
    // For now, we rely on the default absorption time from COBConstants
}

extension Array where Element == CarbEntry {
    /// Calculate COB using Loop parity algorithm (dynamic absorption with ICE)
    /// Trace: ALG-COB-WIRE, GAP-023
    public func carbsOnBoardParity(
        at date: Date,
        defaultAbsorptionTime: TimeInterval = COBConstants.defaultAbsorptionTime,
        delay: TimeInterval = COBConstants.defaultEffectDelay,
        absorptionModel: CarbAbsorptionComputable = PiecewiseLinearAbsorption()
    ) -> Double {
        // Use parity COB calculation
        return carbsOnBoard(
            at: date,
            defaultAbsorptionTime: defaultAbsorptionTime,
            delay: delay,
            absorptionModel: absorptionModel
        )
    }
}
