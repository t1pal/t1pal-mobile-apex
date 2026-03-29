// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopRetrospectiveCorrectionParity.swift
// T1Pal Mobile
//
// Loop-compatible Retrospective Correction (RC) calculation
// Trace: ALG-FIDELITY-020, GAP-039..045
//
// Key concepts from Loop's RetrospectiveCorrection:
// - Two algorithms: Standard RC (Proportional) and Integral RC (PID)
// - Input: Pre-computed discrepancies from ICE, NOT predictions vs actuals
// - Decay effect: Linear decay projection of correction
// - Recency check: Discards data if last discrepancy is stale
// - Integral RC: Accumulates with time constant, adds differential component
//
// Sources:
// - externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/RetrospectiveCorrection.swift
// - externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/StandardRetrospectiveCorrection.swift
// - externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/IntegralRetrospectiveCorrection.swift
// - externals/LoopAlgorithm/Sources/LoopAlgorithm/LoopMath.swift (decayEffect)

import Foundation

// MARK: - Internal TimeInterval Extension

/// Internal extension to convert TimeInterval to minutes
/// Using internal scope to avoid conflicts with other module extensions
private extension TimeInterval {
    /// Convert TimeInterval (seconds) to minutes
    var asMinutes: Double {
        self / 60.0
    }
}

// MARK: - Constants

/// Constants for retrospective correction
/// Matches Loop's RetrospectiveCorrection constants
public enum RetrospectiveCorrectionConstants {
    /// Retrospection interval for STANDARD RC (30 minutes)
    /// From StandardRetrospectiveCorrection.swift: "retrospectionInterval = TimeInterval(minutes: 30)"
    public static let standardRetrospectionInterval: TimeInterval = .minutes(30)
    
    /// Retrospection interval for integral RC (3 hours)
    public static let integralRetrospectionInterval: TimeInterval = .minutes(180)
    
    /// Standard effect duration (1 hour)
    public static let standardEffectDuration: TimeInterval = .minutes(60)
    
    /// Maximum correction effect duration (3 hours)
    public static let maximumCorrectionEffectDuration: TimeInterval = .minutes(180)
    
    /// Grouping interval for discrepancies (30 minutes)
    public static let groupingInterval: TimeInterval = .minutes(30)
    
    /// Recency interval - how recent data must be
    public static let recencyInterval: TimeInterval = .minutes(15)
    
    /// Delta for effect sampling (5 minutes)
    public static let delta: TimeInterval = .minutes(5)
    
    // MARK: - PID Controller Gains (Integral RC)
    
    /// Gain for current discrepancy (proportional response)
    public static let currentDiscrepancyGain: Double = 1.0
    
    /// Gain for persistent discrepancies (higher for long-term errors)
    public static let persistentDiscrepancyGain: Double = 2.0
    
    /// Time constant for integral accumulation
    public static let correctionTimeConstant: TimeInterval = .minutes(60)
    
    /// Differential gain (rate of change response)
    public static let differentialGain: Double = 2.0
    
    /// Exponential forget factor: exp(-delta/timeConstant)
    public static var integralForget: Double {
        exp(-delta.asMinutes / correctionTimeConstant.asMinutes)
    }
    
    /// Integral gain derived from forget factor
    public static var integralGain: Double {
        ((1 - integralForget) / integralForget) * (persistentDiscrepancyGain - currentDiscrepancyGain)
    }
    
    /// Proportional gain derived from other gains
    public static var proportionalGain: Double {
        currentDiscrepancyGain - integralGain
    }
    
    /// Minimum discrepancy value to include (mg/dL)
    public static let minimumDiscrepancy: Double = 0.1
}

// MARK: - GlucoseChange Type

/// Represents a change in glucose over an interval
/// Matches Loop's GlucoseChange struct
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Glucose/GlucoseChange.swift
public struct LoopGlucoseChange: Sendable, Equatable {
    /// Start of the interval
    public let startDate: Date
    
    /// End of the interval
    public let endDate: Date
    
    /// Magnitude of change in mg/dL
    public let quantity: Double
    
    public init(startDate: Date, endDate: Date, quantity: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.quantity = quantity
    }
    
    /// Duration of this change
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    /// Sign of the change (+1 for rising, -1 for falling, 0 for neutral)
    public var sign: FloatingPointSign {
        quantity.sign
    }
}

// MARK: - GlucoseEffect Type (for RC output)

/// A glucose effect at a point in time
/// Matches Loop's GlucoseEffect used in decayEffect output
public struct LoopGlucoseEffect: Sendable, Equatable {
    /// Time point
    public let startDate: Date
    
    /// Effect magnitude in mg/dL (cumulative from start)
    public let quantity: Double
    
    public init(startDate: Date, quantity: Double) {
        self.startDate = startDate
        self.quantity = quantity
    }
}

// MARK: - Glucose Value Protocol

/// Protocol for glucose values that can be used as RC starting point
public protocol LoopGlucoseValueProtocol: Sendable {
    /// Time of the glucose reading
    var startDate: Date { get }
    
    /// Glucose value in mg/dL
    var quantity: Double { get }
}

/// Simple implementation of glucose value
public struct SimpleGlucoseValue: LoopGlucoseValueProtocol, Sendable {
    public let startDate: Date
    public let quantity: Double
    
    public init(startDate: Date, quantity: Double) {
        self.startDate = startDate
        self.quantity = quantity
    }
}

// MARK: - Retrospective Correction Protocol

/// Protocol for retrospective correction algorithms
/// Matches Loop's RetrospectiveCorrection protocol
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/RetrospectiveCorrection.swift
public protocol LoopRetrospectiveCorrection: Sendable {
    /// Overall retrospective correction effect
    var totalGlucoseCorrectionEffect: Double? { get }
    
    /// Calculates overall correction effect based on timeline of discrepancies
    /// - Parameters:
    ///   - startingGlucose: Current glucose reading
    ///   - discrepancies: Pre-computed discrepancies from ICE (summed)
    ///   - recencyInterval: How recent last discrepancy must be
    ///   - groupingInterval: Duration of discrepancy measurements
    /// - Returns: Array of glucose effects for prediction
    mutating func computeEffect(
        startingAt startingGlucose: LoopGlucoseValueProtocol,
        retrospectiveGlucoseDiscrepanciesSummed discrepancies: [LoopGlucoseChange]?,
        recencyInterval: TimeInterval,
        retrospectiveCorrectionGroupingInterval groupingInterval: TimeInterval
    ) -> [LoopGlucoseEffect]
}

// MARK: - Standard Retrospective Correction

/// Standard (Proportional) Retrospective Correction
/// Acts as a proportional (P) controller for modeling errors
///
/// Algorithm:
/// 1. Get last discrepancy from timeline
/// 2. Check recency (discard if stale)
/// 3. velocity = discrepancy / time
/// 4. effect = decayEffect(velocity, duration=1h)
///
/// Trace: GAP-039 (input source), GAP-045 (no significance threshold)
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/StandardRetrospectiveCorrection.swift
public struct StandardRetrospectiveCorrection: LoopRetrospectiveCorrection, Sendable {
    /// Effect duration (default 1 hour)
    public let effectDuration: TimeInterval
    
    /// Overall correction effect (stored after compute)
    public private(set) var totalGlucoseCorrectionEffect: Double?
    
    // MARK: - Diagnostic State (ALG-RC-008)
    
    /// Input discrepancy count
    public private(set) var discrepancyCount: Int = 0
    
    /// Last discrepancy value used for RC
    public private(set) var lastDiscrepancyValue: Double?
    
    /// Duration used for velocity calculation
    public private(set) var discrepancyDuration: TimeInterval?
    
    /// Velocity (mg/dL per second) used for decay effect
    public private(set) var velocityPerSecond: Double?
    
    /// Was RC skipped due to recency check?
    public private(set) var skippedDueToRecency: Bool = false
    
    public init(effectDuration: TimeInterval = RetrospectiveCorrectionConstants.standardEffectDuration) {
        self.effectDuration = effectDuration
        self.totalGlucoseCorrectionEffect = nil
    }
    
    public mutating func computeEffect(
        startingAt startingGlucose: LoopGlucoseValueProtocol,
        retrospectiveGlucoseDiscrepanciesSummed discrepancies: [LoopGlucoseChange]?,
        recencyInterval: TimeInterval,
        retrospectiveCorrectionGroupingInterval groupingInterval: TimeInterval
    ) -> [LoopGlucoseEffect] {
        let glucoseDate = startingGlucose.startDate
        discrepancyCount = discrepancies?.count ?? 0
        
        // Last discrepancy must be recent
        guard let currentDiscrepancy = discrepancies?.last,
              glucoseDate.timeIntervalSince(currentDiscrepancy.endDate) <= recencyInterval
        else {
            totalGlucoseCorrectionEffect = nil
            skippedDueToRecency = true
            return []
        }
        
        skippedDueToRecency = false
        
        // Store total effect
        let currentDiscrepancyValue = currentDiscrepancy.quantity
        totalGlucoseCorrectionEffect = currentDiscrepancyValue
        lastDiscrepancyValue = currentDiscrepancyValue
        
        // Calculate velocity (mg/dL per second)
        let retrospectionTimeInterval = currentDiscrepancy.duration
        let discrepancyTime = max(retrospectionTimeInterval, groupingInterval)
        discrepancyDuration = discrepancyTime
        let velocity = currentDiscrepancyValue / discrepancyTime
        velocityPerSecond = velocity
        
        // Generate decaying effect timeline
        return decayEffect(
            startingGlucose: startingGlucose,
            velocityPerSecond: velocity,
            duration: effectDuration
        )
    }
}

// MARK: - Integral Retrospective Correction

/// Integral (PID) Retrospective Correction
/// Acts as a proportional-integral-differential (PID) controller
///
/// Algorithm:
/// 1. Get contiguous same-sign discrepancies (up to 3h)
/// 2. Check recency
/// 3. P = proportionalGain × currentDiscrepancy
/// 4. I = Σ(integralForget^i × integralGain × discrepancy[i])
/// 5. D = differentialGain × (current - previous) [only if negative]
/// 6. total = P + I + D
/// 7. effectDuration = base + 10min × count (max 3h)
/// 8. effect = decayEffect(scaled_total, effectDuration)
///
/// Trace: GAP-040 (Integral RC), GAP-041 (same-sign filtering), GAP-042 (exponential forget),
///        GAP-043 (differential component), GAP-044 (effect duration extension)
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/RetrospectiveCorrection/IntegralRetrospectiveCorrection.swift
public struct IntegralRetrospectiveCorrection: LoopRetrospectiveCorrection, Sendable {
    /// Base effect duration
    public let effectDuration: TimeInterval
    
    /// Overall correction effect
    public private(set) var totalGlucoseCorrectionEffect: Double?
    
    // MARK: - Diagnostic State
    
    /// Recent discrepancy values used in calculation
    public private(set) var recentDiscrepancyValues: [Double] = []
    
    /// Calculated correction effect duration
    public private(set) var integralCorrectionEffectDuration: TimeInterval?
    
    /// Proportional component of correction
    public private(set) var proportionalCorrection: Double = 0.0
    
    /// Integral component of correction
    public private(set) var integralCorrection: Double = 0.0
    
    /// Differential component of correction
    public private(set) var differentialCorrection: Double = 0.0
    
    public init(effectDuration: TimeInterval = RetrospectiveCorrectionConstants.standardEffectDuration) {
        self.effectDuration = effectDuration
        self.totalGlucoseCorrectionEffect = nil
    }
    
    public mutating func computeEffect(
        startingAt startingGlucose: LoopGlucoseValueProtocol,
        retrospectiveGlucoseDiscrepanciesSummed discrepancies: [LoopGlucoseChange]?,
        recencyInterval: TimeInterval,
        retrospectiveCorrectionGroupingInterval groupingInterval: TimeInterval
    ) -> [LoopGlucoseEffect] {
        let glucoseDate = startingGlucose.startDate
        
        // Last discrepancy must be recent
        guard let currentDiscrepancy = discrepancies?.last,
              glucoseDate.timeIntervalSince(currentDiscrepancy.endDate) <= recencyInterval
        else {
            totalGlucoseCorrectionEffect = nil
            return []
        }
        
        // Default values
        let currentDiscrepancyValue = currentDiscrepancy.quantity
        var scaledCorrection = currentDiscrepancyValue
        totalGlucoseCorrectionEffect = currentDiscrepancyValue
        integralCorrectionEffectDuration = effectDuration
        
        // Calculate integral RC if past discrepancies available
        let retrospectionStart = glucoseDate.addingTimeInterval(-RetrospectiveCorrectionConstants.integralRetrospectionInterval)
        if let pastDiscrepancies = discrepancies?.filter({ $0.endDate >= retrospectionStart && $0.endDate <= glucoseDate }) {
            
            // Build array of recent contiguous same-sign discrepancies
            // GAP-041: Same-sign filtering to reduce response delay
            recentDiscrepancyValues = []
            var nextDiscrepancy = currentDiscrepancy
            let currentDiscrepancySign = currentDiscrepancy.sign
            
            for pastDiscrepancy in pastDiscrepancies.reversed() {
                let pastDiscrepancyValue = pastDiscrepancy.quantity
                
                // Check: same sign, recent, and significant
                if pastDiscrepancyValue.sign == currentDiscrepancySign &&
                   nextDiscrepancy.endDate.timeIntervalSince(pastDiscrepancy.endDate) <= recencyInterval &&
                   abs(pastDiscrepancyValue) >= RetrospectiveCorrectionConstants.minimumDiscrepancy
                {
                    recentDiscrepancyValues.append(pastDiscrepancyValue)
                    nextDiscrepancy = pastDiscrepancy
                } else {
                    break  // Stop at sign change, gap, or insignificant value
                }
            }
            recentDiscrepancyValues = recentDiscrepancyValues.reversed()
            
            // GAP-042: Integral effect with exponential forget
            integralCorrection = 0.0
            var integralCorrectionEffectMinutes = effectDuration.asMinutes - 2.0 * RetrospectiveCorrectionConstants.delta.asMinutes
            
            for discrepancy in recentDiscrepancyValues {
                integralCorrection =
                    RetrospectiveCorrectionConstants.integralForget * integralCorrection +
                    RetrospectiveCorrectionConstants.integralGain * discrepancy
                
                // GAP-044: Effect duration extends with each discrepancy
                integralCorrectionEffectMinutes += 2.0 * RetrospectiveCorrectionConstants.delta.asMinutes
            }
            
            // Limit effect duration
            integralCorrectionEffectMinutes = min(
                integralCorrectionEffectMinutes,
                RetrospectiveCorrectionConstants.maximumCorrectionEffectDuration.asMinutes
            )
            
            // GAP-043: Differential effect (only when negative)
            var differentialDiscrepancy: Double = 0.0
            if recentDiscrepancyValues.count > 1 {
                let previousDiscrepancyValue = recentDiscrepancyValues[recentDiscrepancyValues.count - 2]
                differentialDiscrepancy = currentDiscrepancyValue - previousDiscrepancyValue
            }
            
            // Proportional component
            proportionalCorrection = RetrospectiveCorrectionConstants.proportionalGain * currentDiscrepancyValue
            
            // Differential added only when negative (avoids stacking with momentum when rising)
            if differentialDiscrepancy < 0.0 {
                differentialCorrection = RetrospectiveCorrectionConstants.differentialGain * differentialDiscrepancy
            } else {
                differentialCorrection = 0.0
            }
            
            // Total = P + I + D
            let totalCorrection = proportionalCorrection + integralCorrection + differentialCorrection
            totalGlucoseCorrectionEffect = totalCorrection
            integralCorrectionEffectDuration = .minutes(integralCorrectionEffectMinutes)
            
            // Scale correction to account for extended duration
            scaledCorrection = totalCorrection * effectDuration.asMinutes / integralCorrectionEffectMinutes
        }
        
        // Calculate velocity for decay effect
        let retrospectionTimeInterval = currentDiscrepancy.duration
        let discrepancyTime = max(retrospectionTimeInterval, groupingInterval)
        let velocityPerSecond = scaledCorrection / discrepancyTime
        
        // Generate decaying effect timeline
        return decayEffect(
            startingGlucose: startingGlucose,
            velocityPerSecond: velocityPerSecond,
            duration: integralCorrectionEffectDuration ?? effectDuration
        )
    }
}

// MARK: - Decay Effect Function

/// Generates a decaying glucose effect timeline
/// Matches Loop's GlucoseValue.decayEffect(atRate:for:withDelta:)
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/LoopMath.swift Lines 177-213
///
/// Linear decay from initial rate to zero over duration
/// - Parameters:
///   - startingGlucose: Starting glucose value
///   - velocityPerSecond: Initial rate of change (mg/dL per second)
///   - duration: How long the effect should last
///   - delta: Time step for output (default 5 minutes)
/// - Returns: Array of cumulative glucose effects
public func decayEffect(
    startingGlucose: LoopGlucoseValueProtocol,
    velocityPerSecond: Double,
    duration: TimeInterval,
    delta: TimeInterval = RetrospectiveCorrectionConstants.delta
) -> [LoopGlucoseEffect] {
    
    guard duration > delta else {
        return [LoopGlucoseEffect(startDate: startingGlucose.startDate, quantity: startingGlucose.quantity)]
    }
    
    let startDate = startingGlucose.startDate
    let endDate = startDate.addingTimeInterval(duration)
    
    // Starting rate, which decays to 0 over duration
    let intercept = velocityPerSecond  // mg/dL/s
    let decayStartDate = startDate.addingTimeInterval(delta)
    let slope = -intercept / (duration - delta)  // mg/dL/s/s
    
    var values: [LoopGlucoseEffect] = [
        LoopGlucoseEffect(startDate: startDate, quantity: startingGlucose.quantity)
    ]
    
    var date = decayStartDate
    var lastValue = startingGlucose.quantity
    
    while date < endDate {
        let elapsed = date.timeIntervalSince(decayStartDate)
        let currentRate = intercept + slope * elapsed
        let value = lastValue + currentRate * delta
        
        values.append(LoopGlucoseEffect(startDate: date, quantity: value))
        lastValue = value
        date = date.addingTimeInterval(delta)
    }
    
    return values
}

// MARK: - RC Algorithm Selection

/// Type of retrospective correction algorithm
public enum RetrospectiveCorrectionType: String, Sendable, CaseIterable {
    /// Standard (Proportional only) - faster response, less memory
    case standard
    
    /// Integral (PID) - accumulates persistent errors, slower but smoother
    case integral
}

/// Factory for creating retrospective correction instances
public enum RetrospectiveCorrectionFactory {
    /// Create a retrospective correction algorithm
    /// - Parameters:
    ///   - type: Algorithm type (standard or integral)
    ///   - effectDuration: Base effect duration
    /// - Returns: Configured RC algorithm
    public static func create(
        type: RetrospectiveCorrectionType,
        effectDuration: TimeInterval = RetrospectiveCorrectionConstants.standardEffectDuration
    ) -> any LoopRetrospectiveCorrection {
        switch type {
        case .standard:
            return StandardRetrospectiveCorrection(effectDuration: effectDuration)
        case .integral:
            return IntegralRetrospectiveCorrection(effectDuration: effectDuration)
        }
    }
}

// MARK: - Discrepancy Calculation

/// Calculates discrepancies from ICE (Insulin Counteraction Effects)
/// GAP-039: Loop uses ICE-derived discrepancies, not predictions vs actuals
///
/// Discrepancy = (actual glucose change) - (expected change from insulin + carbs)
/// Positive discrepancy: glucose higher than expected (more carbs? less insulin sensitivity?)
/// Negative discrepancy: glucose lower than expected (exercise? more insulin sensitivity?)
public struct DiscrepancyCalculator: Sendable {
    
    /// Calculate discrepancies from counteraction effects using Loop's combinedSums approach
    /// This creates overlapping windows where each starts 5 min after the previous
    ///
    /// ALG-RC-008: Refactored to use sequential matching like Loop's subtracting()
    ///
    /// - Parameters:
    ///   - insulinCounteractionEffects: ICE values (actual - expected_from_insulin)
    ///   - carbEffects: Expected carb effects (velocities/deltas)
    ///   - groupingInterval: Duration of each summed window (default 30 min)
    /// - Returns: Summed discrepancies ready for RC input
    public static func calculateDiscrepancies(
        insulinCounteractionEffects: [GlucoseEffectVelocity],
        carbEffects: [GlucoseEffectVelocity],
        groupingInterval: TimeInterval = RetrospectiveCorrectionConstants.groupingInterval
    ) -> [LoopGlucoseChange] {
        
        guard !insulinCounteractionEffects.isEmpty else {
            return []
        }
        
        // Step 1: Compute per-interval discrepancies (ICE - carbEffects)
        // These are at 5-min granularity
        // ALG-RC-008: Use sequential matching like Loop's subtracting() at LoopMath.swift:269-324
        var perIntervalDiscrepancies: [LoopGlucoseChange] = []
        
        // Sort both arrays by endDate to enable sequential matching
        let sortedICE = insulinCounteractionEffects.sorted { $0.endDate < $1.endDate }
        let sortedCarbs = carbEffects.sorted { $0.endDate < $1.endDate }
        
        var carbIndex = 0
        
        for ice in sortedICE {
            // Advance carb index to find matching or closest carb effect
            // Loop's approach: advance carbIndex until carb.endDate >= ice.endDate
            while carbIndex < sortedCarbs.count &&
                  sortedCarbs[carbIndex].endDate < ice.endDate.addingTimeInterval(-60) {
                carbIndex += 1
            }
            
            // Find carb effect that matches this ICE interval
            var carbEffectValue: Double = 0
            if carbIndex < sortedCarbs.count {
                let carb = sortedCarbs[carbIndex]
                // Check if timestamps roughly align
                if abs(carb.endDate.timeIntervalSince(ice.endDate)) < 60 {
                    carbEffectValue = carb.quantity
                }
            }
            
            // ALG-RC-FIX-001: Scale ICE from per-second to total mg/dL
            // ICE is now stored as per-second velocity (like Loop's GlucoseMath.swift:249)
            // Loop's subtracting (LoopMath.swift:298): effectValue * effectInterval
            // Carb effects are already in mg/dL (total change per interval)
            let iceScaled = ice.quantity * ice.duration
            let discrepancyAmount = iceScaled - carbEffectValue
            
            perIntervalDiscrepancies.append(LoopGlucoseChange(
                startDate: ice.startDate,
                endDate: ice.endDate,
                quantity: discrepancyAmount
            ))
        }
        
        // Step 2: Apply combinedSums algorithm to create overlapping windows
        // This matches Loop's approach in LoopMath.swift
        // Each output element sums discrepancies within a duration window starting at its endDate
        
        // Use 1.01x factor like Loop to handle edge cases
        let windowDuration = groupingInterval * 1.01
        
        var sums: [LoopGlucoseChange] = []
        sums.reserveCapacity(perIntervalDiscrepancies.count)
        var lastValidIndex = 0
        
        // Process in reverse chronological order
        for discrepancy in perIntervalDiscrepancies.reversed() {
            // Add new sum element for this timestamp
            sums.append(LoopGlucoseChange(
                startDate: discrepancy.startDate,
                endDate: discrepancy.endDate,
                quantity: discrepancy.quantity
            ))
            
            // Accumulate this discrepancy into earlier sums that are within the window
            for sumIndex in lastValidIndex..<(sums.count - 1) {
                // Check if this sum's endDate is within windowDuration of current discrepancy
                guard sums[sumIndex].endDate <= discrepancy.endDate.addingTimeInterval(windowDuration) else {
                    // This sum is too old, skip it in future iterations
                    lastValidIndex += 1
                    continue
                }
                
                // Accumulate: extend startDate back, keep endDate, add quantity
                sums[sumIndex] = LoopGlucoseChange(
                    startDate: discrepancy.startDate,
                    endDate: sums[sumIndex].endDate,
                    quantity: sums[sumIndex].quantity + discrepancy.quantity
                )
            }
        }
        
        // Return in chronological order
        return sums.reversed()
    }
}

// MARK: - Integration Helper

/// Helper to integrate retrospective correction into prediction
/// This shows how RC effects are combined with other model effects
public struct RetrospectiveCorrectionIntegration: Sendable {
    
    /// Combine all effects for glucose prediction
    /// RC is added as another effect timeline alongside insulin and carbs
    ///
    /// - Parameters:
    ///   - startingGlucose: Current glucose
    ///   - insulinEffects: Expected insulin effects
    ///   - carbEffects: Expected carb effects
    ///   - rcEffects: Retrospective correction effects
    ///   - momentumEffects: Momentum (trend) effects
    /// - Returns: Combined effects timeline
    public static func combinePredictionEffects(
        startingGlucose: SimpleGlucoseValue,
        insulinEffects: [LoopGlucoseEffect],
        carbEffects: [LoopGlucoseEffect],
        rcEffects: [LoopGlucoseEffect],
        momentumEffects: [LoopGlucoseEffect] = []
    ) -> [LoopGlucoseEffect] {
        
        // Gather all unique timestamps
        var timestamps: Set<Date> = [startingGlucose.startDate]
        for effect in insulinEffects + carbEffects + rcEffects + momentumEffects {
            timestamps.insert(effect.startDate)
        }
        
        let sortedDates = timestamps.sorted()
        
        // For each timestamp, sum effects relative to starting glucose
        return sortedDates.map { date in
            let insulinEffect = insulinEffects.last { $0.startDate <= date }?.quantity ?? startingGlucose.quantity
            let carbEffect = carbEffects.last { $0.startDate <= date }?.quantity ?? startingGlucose.quantity
            let rcEffect = rcEffects.last { $0.startDate <= date }?.quantity ?? startingGlucose.quantity
            let momentumEffect = momentumEffects.last { $0.startDate <= date }?.quantity ?? startingGlucose.quantity
            
            // Sum effects relative to baseline
            let baseline = startingGlucose.quantity
            let combinedEffect = baseline +
                (insulinEffect - baseline) +
                (carbEffect - baseline) +
                (rcEffect - baseline) +
                (momentumEffect - baseline)
            
            return LoopGlucoseEffect(startDate: date, quantity: combinedEffect)
        }
    }
}
