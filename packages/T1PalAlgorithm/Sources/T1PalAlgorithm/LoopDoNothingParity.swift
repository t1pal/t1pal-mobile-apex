// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopDoNothingParity.swift
// T1Pal Mobile
//
// Loop-compatible "do nothing" recommendation and temp basal continuation
// Trace: ALG-FIDELITY-018, GAP-046..057
//
// Key concepts from Loop:
// - AlgorithmError for validation failures
// - InsulinCorrection state machine (inRange, aboveRange, belowRange, suspend)
// - Per-prediction suspend check (ANY point below threshold = suspend)
// - TempBasal.ifNecessary() to minimize pump commands

import Foundation

// MARK: - Algorithm Errors (GAP-046, GAP-047, GAP-052)

/// Loop-compatible algorithm validation errors
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/LoopAlgorithm.swift lines 10-18
public enum LoopAlgorithmError: Error, Sendable, Equatable {
    /// No glucose data available
    case missingGlucose
    
    /// Most recent glucose is too old
    case glucoseTooOld(age: TimeInterval)
    
    /// Basal schedule doesn't cover prediction interval
    case basalTimelineIncomplete
    
    /// No suspend threshold configured
    case missingSuspendThreshold
    
    /// ISF schedule starts after current time
    case sensitivityTimelineStartsTooLate
    
    /// ISF schedule ends before prediction horizon
    case sensitivityTimelineEndsTooEarly
    
    /// Cannot set future basal in automated mode
    case futureBasalNotAllowed
}

extension LoopAlgorithmError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingGlucose:
            return "No glucose data available"
        case .glucoseTooOld(let age):
            let minutes = Int(age / 60)
            return "Glucose data is \(minutes) minutes old"
        case .basalTimelineIncomplete:
            return "Basal schedule doesn't cover prediction interval"
        case .missingSuspendThreshold:
            return "No suspend threshold configured"
        case .sensitivityTimelineStartsTooLate:
            return "Insulin sensitivity schedule starts too late"
        case .sensitivityTimelineEndsTooEarly:
            return "Insulin sensitivity schedule ends too early"
        case .futureBasalNotAllowed:
            return "Cannot set future basal in automated mode"
        }
    }
}

// MARK: - Insulin Correction State (GAP-048, GAP-049)

/// State machine for insulin correction decision
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/Dose/DoseMath.swift
public enum InsulinCorrection: Sendable, Equatable {
    /// No correction needed — glucose in target range
    case inRange
    
    /// Need to add insulin — glucose above target
    case aboveRange(
        minGlucose: Double,      // Lowest predicted glucose
        eventualGlucose: Double, // Final predicted glucose
        correctionUnits: Double  // Positive insulin to add
    )
    
    /// Need to reduce insulin — glucose below target but not critical
    case entirelyBelowRange(
        minGlucose: Double,
        eventualGlucose: Double,
        correctionUnits: Double  // Negative (reduction amount)
    )
    
    /// Emergency suspend — ANY prediction below threshold
    /// GAP-049: Per-prediction suspend check
    case suspend(minGlucose: Double)
    
    /// Whether this state requires suspending insulin delivery
    public var requiresSuspend: Bool {
        if case .suspend = self { return true }
        return false
    }
    
    /// Whether this state is a "do nothing" state
    public var isDoNothing: Bool {
        switch self {
        case .inRange, .suspend:
            return true
        case .entirelyBelowRange(_, _, let correction):
            return correction >= 0  // No reduction needed
        case .aboveRange(_, _, let correction):
            return correction <= 0  // No addition needed
        }
    }
}

// MARK: - Dose Direction (GAP-051)

/// Direction of dose adjustment for telemetry/UI
public enum DoseDirection: String, Codable, Sendable {
    /// Reducing insulin (suspend or below range)
    case decrease
    
    /// Maintaining current insulin (in range)
    case neutral
    
    /// Adding insulin (above range)
    case increase
}

extension InsulinCorrection {
    /// Get dose direction for telemetry
    public var direction: DoseDirection {
        switch self {
        case .inRange:
            return .neutral
        case .suspend, .entirelyBelowRange:
            return .decrease
        case .aboveRange:
            return .increase
        }
    }
}

// MARK: - Bolus Recommendation Notice (GAP-050)

/// User-facing explanation for bolus recommendations
public enum BolusRecommendationNotice: String, Codable, Sendable {
    /// Current glucose is below suspend threshold
    case glucoseBelowSuspendThreshold
    
    /// Current glucose is below target (no correction)
    case currentGlucoseBelowTarget
    
    /// Some prediction is below target (safety limit)
    case predictedGlucoseBelowTarget
    
    /// All predictions within range (no correction needed)
    case predictedGlucoseInRange
    
    /// All predictions below target (suspend mode)
    case allGlucoseBelowTarget
}

// MARK: - Extended Dose Recommendation Type

/// Extended recommendation types including "do nothing" states
public enum LoopDoseRecommendationType: String, Codable, Sendable {
    case tempBasal = "temp_basal"
    case bolus = "bolus"
    case suspend = "suspend"
    case resume = "resume"
    case noAction = "no_action"
    case continueTempBasal = "continue_temp_basal"
}

// MARK: - Temp Basal Action (GAP-053..057)

/// Action to take with temp basal recommendation
/// Returned by ifNecessary() filtering
public enum TempBasalAction: Sendable, Equatable {
    /// Do nothing — current state is correct
    case noAction(reason: NoActionReason)
    
    /// Issue the temp basal command to pump
    case setTempBasal(LoopTempBasal)
    
    /// Cancel current temp basal, return to scheduled
    case cancelTempBasal
}

/// Reasons for noAction (for telemetry/debugging)
public enum NoActionReason: String, Codable, Sendable {
    /// Current temp matches and has sufficient time remaining
    case tempBasalRunningWithSufficientTime
    
    /// Recommended rate matches scheduled basal (no temp needed)
    case matchesScheduledBasal
    
    /// Already at scheduled basal with no temp
    case alreadyAtScheduledBasal
}

// MARK: - Temp Basal Type

/// Temp basal recommendation
public struct LoopTempBasal: Sendable, Equatable {
    /// Rate in U/hr
    public let rate: Double
    
    /// Duration in seconds
    public let duration: TimeInterval
    
    public init(rate: Double, duration: TimeInterval) {
        self.rate = rate
        self.duration = duration
    }
    
    /// Cancel sentinel — duration 0 signals "cancel existing temp"
    public static var cancel: LoopTempBasal {
        LoopTempBasal(rate: 0, duration: 0)
    }
    
    /// Check if this is a cancel sentinel
    public var isCancel: Bool {
        duration == 0
    }
    
    /// Check if rate matches another (with ULP precision)
    public func matchesRate(_ otherRate: Double) -> Bool {
        abs(rate - otherRate) < .ulpOfOne
    }
}

// MARK: - Temp Basal Continuation Config

/// Temp basal continuation configuration
public struct TempBasalContinuationConfig: Sendable {
    /// Minimum time remaining to avoid re-issue (default: 11 min)
    /// Loop: ~11 min gives buffer for next 5-min loop iteration
    public let continuationInterval: TimeInterval
    
    /// Whether pump's scheduled basal matches our profile
    public let scheduledBasalMatchesPump: Bool
    
    public init(
        continuationInterval: TimeInterval = .minutes(11),
        scheduledBasalMatchesPump: Bool = true
    ) {
        self.continuationInterval = continuationInterval
        self.scheduledBasalMatchesPump = scheduledBasalMatchesPump
    }
    
    public static let `default` = TempBasalContinuationConfig()
}

// MARK: - Current Delivery State

/// Current pump delivery state for continuation decisions
public struct CurrentDeliveryState: Sendable {
    /// Currently running temp basal (nil if none)
    public let currentTempBasal: LoopTempBasal?
    
    /// When current temp ends (nil if no temp)
    public let tempBasalEndTime: Date?
    
    /// Scheduled basal rate for current time
    public let scheduledBasalRate: Double
    
    public init(
        currentTempBasal: LoopTempBasal? = nil,
        tempBasalEndTime: Date? = nil,
        scheduledBasalRate: Double
    ) {
        self.currentTempBasal = currentTempBasal
        self.tempBasalEndTime = tempBasalEndTime
        self.scheduledBasalRate = scheduledBasalRate
    }
    
    /// Whether a temp basal is currently active
    public func hasTempBasalRunning(at date: Date = Date()) -> Bool {
        guard let endTime = tempBasalEndTime else { return false }
        return endTime > date
    }
    
    /// Time remaining on current temp (0 if none)
    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        guard let endTime = tempBasalEndTime else { return 0 }
        return max(0, endTime.timeIntervalSince(date))
    }
}

// MARK: - ifNecessary Extension

extension LoopTempBasal {
    /// Determine if this temp basal command is necessary given current state
    /// Returns the appropriate action to minimize pump commands
    ///
    /// Decision matrix:
    /// | Current State | Recommended | Action |
    /// |---------------|-------------|--------|
    /// | Temp running, same rate, >11min | Same rate | noAction |
    /// | Temp running, any rate | Scheduled | cancelTempBasal |
    /// | Temp running, same rate, <11min | Same rate | setTempBasal |
    /// | Temp running, different rate | Different | setTempBasal |
    /// | No temp, scheduled | Scheduled | noAction |
    /// | No temp, scheduled | Different | setTempBasal |
    ///
    /// - Parameters:
    ///   - currentState: Current pump delivery state
    ///   - config: Continuation configuration
    ///   - at: Reference time for calculations
    /// - Returns: TempBasalAction indicating what to do
    public func ifNecessary(
        currentState: CurrentDeliveryState,
        config: TempBasalContinuationConfig = .default,
        at date: Date = Date()
    ) -> TempBasalAction {
        
        // Case 1: Currently running a temp basal
        if currentState.hasTempBasalRunning(at: date),
           let currentTemp = currentState.currentTempBasal {
            
            let timeRemaining = currentState.timeRemaining(at: date)
            
            // Case 1a: Same rate AND enough time remaining → do nothing
            if matchesRate(currentTemp.rate),
               timeRemaining > config.continuationInterval {
                return .noAction(reason: .tempBasalRunningWithSufficientTime)
            }
            
            // Case 1b: Recommended matches scheduled rate → cancel current temp
            if matchesRate(currentState.scheduledBasalRate),
               config.scheduledBasalMatchesPump {
                return .cancelTempBasal
            }
            
            // Case 1c: Different rate OR expiring soon → issue new temp
            return .setTempBasal(self)
        }
        
        // Case 2: No temp basal running
        else {
            // Case 2a: Matches scheduled rate → do nothing
            if matchesRate(currentState.scheduledBasalRate),
               config.scheduledBasalMatchesPump {
                return .noAction(reason: .alreadyAtScheduledBasal)
            }
            
            // Case 2b: Different from scheduled → issue temp
            return .setTempBasal(self)
        }
    }
}

// MARK: - Insulin Correction Calculation

/// Calculate insulin correction state from predictions
/// GAP-049: Per-prediction suspend check — ANY point below threshold = suspend
public func calculateInsulinCorrection(
    predictions: [Double],
    targetRange: ClosedRange<Double>,
    suspendThreshold: Double
) -> InsulinCorrection {
    guard !predictions.isEmpty else {
        return .inRange
    }
    
    // Find min and eventual glucose
    let minGlucose = predictions.min()!
    let eventualGlucose = predictions.last!
    
    // GAP-049: Per-prediction suspend check
    // If ANY prediction is below suspend threshold, immediately return suspend
    for prediction in predictions {
        if prediction < suspendThreshold {
            return .suspend(minGlucose: minGlucose)
        }
    }
    
    // Check if eventual glucose is in range
    if targetRange.contains(eventualGlucose) {
        return .inRange
    }
    
    // Check if we need to add insulin (above range)
    if eventualGlucose > targetRange.upperBound {
        // Simplified: correction = (eventual - target) / ISF
        // Real implementation would use ISF schedule
        let correctionUnits = 0.0  // Placeholder - actual calc uses ISF
        return .aboveRange(
            minGlucose: minGlucose,
            eventualGlucose: eventualGlucose,
            correctionUnits: correctionUnits
        )
    }
    
    // Below range
    return .entirelyBelowRange(
        minGlucose: minGlucose,
        eventualGlucose: eventualGlucose,
        correctionUnits: 0.0  // Placeholder
    )
}

// MARK: - Algorithm Input Validation

/// Validation constants
public enum AlgorithmValidationConstants {
    /// Maximum age of glucose data (15 minutes)
    public static let maxGlucoseAge: TimeInterval = .minutes(15)
    
    /// Prediction horizon (6 hours)
    public static let predictionHorizon: TimeInterval = .hours(6)
}

/// Validate algorithm inputs before running
/// Throws AlgorithmError if validation fails
public func validateAlgorithmInputs(
    lastGlucoseDate: Date?,
    basalScheduleEnd: Date?,
    sensitivityScheduleStart: Date?,
    sensitivityScheduleEnd: Date?,
    suspendThreshold: Double?,
    isAutomated: Bool = true,
    at date: Date = Date()
) throws {
    // Check glucose exists
    guard let glucoseDate = lastGlucoseDate else {
        throw LoopAlgorithmError.missingGlucose
    }
    
    // Check glucose age
    let age = date.timeIntervalSince(glucoseDate)
    if age > AlgorithmValidationConstants.maxGlucoseAge {
        throw LoopAlgorithmError.glucoseTooOld(age: age)
    }
    
    // Check suspend threshold
    guard suspendThreshold != nil else {
        throw LoopAlgorithmError.missingSuspendThreshold
    }
    
    // Check sensitivity timeline
    if let start = sensitivityScheduleStart, start > date {
        throw LoopAlgorithmError.sensitivityTimelineStartsTooLate
    }
    
    let predictionEnd = date.addingTimeInterval(AlgorithmValidationConstants.predictionHorizon)
    
    if let end = sensitivityScheduleEnd, end < predictionEnd {
        throw LoopAlgorithmError.sensitivityTimelineEndsTooEarly
    }
    
    // Check basal timeline
    if let basalEnd = basalScheduleEnd, basalEnd < predictionEnd {
        throw LoopAlgorithmError.basalTimelineIncomplete
    }
}

// MARK: - Bolus Recommendation Notice Calculation

/// Determine appropriate notice for bolus recommendation
public func calculateBolusNotice(
    currentGlucose: Double,
    predictions: [Double],
    targetRange: ClosedRange<Double>,
    suspendThreshold: Double
) -> BolusRecommendationNotice? {
    // Check if current glucose is below suspend threshold
    if currentGlucose < suspendThreshold {
        return .glucoseBelowSuspendThreshold
    }
    
    // Check if current glucose is below target
    if currentGlucose < targetRange.lowerBound {
        return .currentGlucoseBelowTarget
    }
    
    // Check predictions
    let minPrediction = predictions.min() ?? currentGlucose
    
    if minPrediction < suspendThreshold {
        return .allGlucoseBelowTarget
    }
    
    if minPrediction < targetRange.lowerBound {
        return .predictedGlucoseBelowTarget
    }
    
    let maxPrediction = predictions.max() ?? currentGlucose
    
    if maxPrediction <= targetRange.upperBound {
        return .predictedGlucoseInRange
    }
    
    // Above range - no special notice
    return nil
}

// MARK: - AbsoluteScheduleValue Extensions (ALG-DIAG-024)

extension Array where Element == AbsoluteScheduleValue<Double> {
    /// Find the schedule value active at or just before the given date
    /// Matches Loop's closestPrior() semantics from LoopAlgorithm
    public func closestPrior(to date: Date) -> Element? {
        // Sort by startDate descending and find first that starts before or at date
        for item in self.sorted(by: { $0.startDate > $1.startDate }) {
            if item.startDate <= date {
                return item
            }
        }
        // If no item starts before date, return the earliest item
        return self.sorted(by: { $0.startDate < $1.startDate }).first
    }
    
    /// Filter to schedule values overlapping the given date range
    /// Matches Loop's filterDateRange() semantics
    public func filterDateRange(_ start: Date, _ end: Date) -> [Element] {
        return self.filter { item in
            // Item overlaps [start, end] if item.start < end AND item.end > start
            item.startDate < end && item.endDate > start
        }
    }
}

extension Array where Element == AbsoluteScheduleValue<ClosedRange<Double>> {
    /// Find the schedule value active at or just before the given date
    public func closestPrior(to date: Date) -> Element? {
        for item in self.sorted(by: { $0.startDate > $1.startDate }) {
            if item.startDate <= date {
                return item
            }
        }
        return self.sorted(by: { $0.startDate < $1.startDate }).first
    }
}

extension ClosedRange where Bound == Double {
    /// Midpoint of the range
    public var averageValue: Double {
        (lowerBound + upperBound) / 2.0
    }
}

// MARK: - Insulin Correction Parity (ALG-DIAG-024)

/// Parameters for insulin correction calculation
public struct InsulinCorrectionParameters: Sendable {
    /// Predicted glucose values over time
    public let predictions: [PredictedGlucose]
    
    /// Correction range timeline (target range over time)
    public let correctionRange: [AbsoluteScheduleValue<ClosedRange<Double>>]
    
    /// Date of insulin delivery (dose start time)
    public let doseDate: Date
    
    /// Suspend threshold in mg/dL
    public let suspendThreshold: Double
    
    /// ISF timeline in mg/dL per unit
    public let insulinSensitivity: [AbsoluteScheduleValue<Double>]
    
    /// Insulin model for effect calculations
    public let insulinModel: LoopExponentialInsulinModel
    
    public init(
        predictions: [PredictedGlucose],
        correctionRange: [AbsoluteScheduleValue<ClosedRange<Double>>],
        doseDate: Date,
        suspendThreshold: Double,
        insulinSensitivity: [AbsoluteScheduleValue<Double>],
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) {
        self.predictions = predictions
        self.correctionRange = correctionRange
        self.doseDate = doseDate
        self.suspendThreshold = suspendThreshold
        self.insulinSensitivity = insulinSensitivity
        self.insulinModel = insulinModel
    }
}

/// Calculate insulin correction with ISF integration matching Loop's DoseMath.swift
/// 
/// This implements the full Loop algorithm:
/// 1. Iterate over each prediction point
/// 2. Calculate effectedSensitivity by integrating ISF × percentEffected
/// 3. Use time-varying target (blend from suspend threshold to correction range midpoint)
/// 4. Take minimum correction needed across all predictions above target
///
/// Reference: externals/LoopAlgorithm/Sources/LoopAlgorithm/Insulin/DoseMath.swift:166-295
public func insulinCorrectionParity(
    parameters: InsulinCorrectionParameters
) -> InsulinCorrection {
    let predictions = parameters.predictions
    let correctionRange = parameters.correctionRange
    let doseDate = parameters.doseDate
    let suspendThreshold = parameters.suspendThreshold
    let insulinSensitivity = parameters.insulinSensitivity
    let model = parameters.insulinModel
    
    guard !predictions.isEmpty else {
        return .inRange
    }
    
    var minGlucose: PredictedGlucose?
    var eventualGlucose: PredictedGlucose?
    var minCorrectionUnits: Double?
    var effectedSensitivityAtMinGlucose: Double?
    
    let endOfAbsorption = doseDate.addingTimeInterval(model.actionDuration)
    
    // Get correction range for dose time
    guard let correctionRangeItem = correctionRange.closestPrior(to: doseDate) else {
        // Fallback: use first range or return inRange
        return .inRange
    }
    
    // For each prediction, determine correction needed
    for prediction in predictions {
        guard prediction.date >= doseDate else {
            continue
        }
        
        // GAP-049: Per-prediction suspend check
        // If ANY prediction is below suspend threshold, immediately return suspend
        if prediction.glucose < suspendThreshold {
            return .suspend(minGlucose: predictions.map { $0.glucose }.min() ?? prediction.glucose)
        }
        
        eventualGlucose = prediction
        
        let predictedGlucoseValue = prediction.glucose
        let time = prediction.date.timeIntervalSince(doseDate)
        
        // Loop's time-varying target: blend from suspend threshold to correction range midpoint
        // At 0-50% of effect duration: use suspend threshold
        // At 50-100%: linearly blend to correction range midpoint
        let percentEffectDuration = time / model.actionDuration
        let targetValue = targetGlucoseValue(
            percentEffectDuration: percentEffectDuration,
            minValue: suspendThreshold,
            maxValue: correctionRangeItem.value.averageValue
        )
        
        // Calculate effected sensitivity by integrating ISF over the prediction interval
        // Formula: effectedSensitivity = Σ(percentEffected × ISF)
        // where percentEffected = percentEffectRemaining(start) - percentEffectRemaining(end)
        let isfSegments = insulinSensitivity.filterDateRange(doseDate, prediction.date)
        
        var effectedSensitivity = 0.0
        
        if isfSegments.isEmpty {
            // Fallback: use first ISF value
            if let firstISF = insulinSensitivity.first {
                let percentEffected = 1.0 - model.percentEffectRemaining(at: time)
                effectedSensitivity = percentEffected * firstISF.value
            }
        } else {
            for segment in isfSegments {
                let segmentStart = max(doseDate, segment.startDate)
                let segmentEnd = min(prediction.date, segment.endDate)
                
                let startTime = segmentStart.timeIntervalSince(doseDate)
                let endTime = segmentEnd.timeIntervalSince(doseDate)
                
                let percentEffected = model.percentEffectRemaining(at: startTime) - model.percentEffectRemaining(at: endTime)
                effectedSensitivity += percentEffected * segment.value
            }
        }
        
        // Track minimum glucose
        if minGlucose == nil || prediction.glucose < minGlucose!.glucose {
            minGlucose = prediction
            effectedSensitivityAtMinGlucose = effectedSensitivity
        }
        
        // Calculate correction units needed to bring this prediction to target
        // dose = (Glucose Δ) / effectedSensitivity
        guard effectedSensitivity > .ulpOfOne else {
            continue
        }
        
        let correctionUnits = (predictedGlucoseValue - targetValue) / effectedSensitivity
        
        // Track minimum positive correction (minimum insulin needed above target)
        if correctionUnits > 0 && (minCorrectionUnits == nil || correctionUnits < minCorrectionUnits!) {
            minCorrectionUnits = correctionUnits
        }
        
        // Stop at end of insulin absorption
        if prediction.date >= endOfAbsorption {
            break
        }
    }
    
    guard let minGlucose = minGlucose, let eventualGlucose = eventualGlucose else {
        return .inRange
    }
    
    // Get target ranges for min and eventual glucose times
    let minGlucoseRange = correctionRange.closestPrior(to: minGlucose.date)?.value ?? correctionRangeItem.value
    let eventualGlucoseRange = correctionRange.closestPrior(to: eventualGlucose.date)?.value ?? correctionRangeItem.value
    
    // Decision: Check if both min and eventual are below range → entirelyBelowRange
    if minGlucose.glucose < minGlucoseRange.lowerBound &&
        eventualGlucose.glucose < eventualGlucoseRange.lowerBound {
        
        // Calculate reduction needed using min glucose
        let effected = effectedSensitivityAtMinGlucose ?? 1.0
        let units = (minGlucose.glucose - minGlucoseRange.averageValue) / max(.ulpOfOne, effected)
        
        return .entirelyBelowRange(
            minGlucose: minGlucose.glucose,
            eventualGlucose: eventualGlucose.glucose,
            correctionUnits: units  // Negative for reduction
        )
    }
    
    // Decision: Check if eventual is above range → aboveRange
    if eventualGlucose.glucose > eventualGlucoseRange.upperBound,
       let minCorrectionUnits = minCorrectionUnits {
        return .aboveRange(
            minGlucose: minGlucose.glucose,
            eventualGlucose: eventualGlucose.glucose,
            correctionUnits: minCorrectionUnits
        )
    }
    
    // Otherwise: in range
    return .inRange
}

/// Calculate time-varying target for correction
/// Loop blends from suspend threshold to correction range midpoint over effect duration
/// Source: DoseMath.swift:136-150
private func targetGlucoseValue(
    percentEffectDuration: Double,
    minValue: Double,
    maxValue: Double
) -> Double {
    // Inflection point: before 50% use minValue, after linearly blend to maxValue
    let useMinValueUntilPercent = 0.5
    
    guard percentEffectDuration > useMinValueUntilPercent else {
        return minValue
    }
    
    guard percentEffectDuration < 1 else {
        return maxValue
    }
    
    let slope = (maxValue - minValue) / (1 - useMinValueUntilPercent)
    return minValue + slope * (percentEffectDuration - useMinValueUntilPercent)
}

// MARK: - InsulinCorrection to TempBasal Conversion (ALG-DIAG-024)

extension InsulinCorrection {
    /// Convert insulin correction to temp basal recommendation
    /// Matches Loop's DoseMath.swift:39-61 asTempBasal()
    public func asTempBasal(
        neutralBasalRate: Double,
        maxBasalRate: Double,
        duration: TimeInterval = 30 * 60,  // 30 minutes default
        rateRounder: ((Double) -> Double)? = nil
    ) -> LoopTempBasal {
        let units: Double
        switch self {
        case .aboveRange(_, _, let correctionUnits):
            units = correctionUnits
        case .entirelyBelowRange(_, _, let correctionUnits):
            units = correctionUnits  // Will be negative
        case .inRange:
            units = 0
        case .suspend:
            // Suspend returns zero rate regardless of neutral
            return LoopTempBasal(rate: 0, duration: duration)
        }
        
        // Convert units to rate: rate = units / (duration in hours) + neutralBasalRate
        var rate = units / (duration / 3600.0) + neutralBasalRate
        
        // Clamp to [0, maxBasalRate]
        rate = Swift.min(maxBasalRate, Swift.max(0, rate))
        
        // Apply rounding if provided
        if let rounder = rateRounder {
            rate = rounder(rate)
        }
        
        return LoopTempBasal(rate: rate, duration: duration)
    }
}
