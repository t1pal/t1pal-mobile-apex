// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopIOBParity.swift
// T1Pal Mobile
//
// Loop-compatible IOB calculation with net basal units and continuous delivery
// Requirements: REQ-ALGO-006
//
// Implementation of ALG-FIDELITY-016 design (docs/design/iob-calculation-parity-design.md)
// Addresses: GAP-016, GAP-017, GAP-018, GAP-019, GAP-020, GAP-021, GAP-022
//            ALG-IOB-007 (time grid snapping), ALG-IOB-008 (max of adjacent values)
//
// Trace: ALG-FIDELITY-016, PRD-009

import Foundation

// MARK: - Date Extension for Time Grid Snapping (ALG-IOB-007)

/// Loop snaps IOB computation times to 5-minute grid boundaries.
/// Reference: LoopKit/Extensions/Date.swift:13-27
extension Date {
    /// Floor date to nearest interval boundary
    /// Loop uses this for IOB timeline start dates
    func flooredToTimeInterval(_ interval: TimeInterval) -> Date {
        guard interval > 0 else { return self }
        return Date(timeIntervalSinceReferenceDate: 
            floor(timeIntervalSinceReferenceDate / interval) * interval)
    }
    
    /// Ceil date to nearest interval boundary
    /// Loop uses this for IOB timeline end dates
    func ceiledToTimeInterval(_ interval: TimeInterval) -> Date {
        guard interval > 0 else { return self }
        return Date(timeIntervalSinceReferenceDate: 
            ceil(timeIntervalSinceReferenceDate / interval) * interval)
    }
}

// MARK: - Constants

/// Loop-compatible IOB calculation constants
/// Trace: GAP-018, GAP-022
public enum IOBConstants {
    /// Default delta for IOB timeline (5 minutes)
    public static let defaultDelta: TimeInterval = 5 * 60
    
    /// Default insulin activity duration (6h 10min)
    public static let defaultInsulinActivityDuration: TimeInterval = 6 * 3600 + 10 * 60
    
    /// Insulin delay before effect starts (10 minutes)
    public static let insulinDelay: TimeInterval = 10 * 60
    
    /// Threshold for treating dose as momentary (1.05 × delta)
    public static let momentaryThresholdMultiplier: Double = 1.05
}

// MARK: - Insulin Delivery Type

/// Type of insulin delivery (bolus vs basal)
/// Trace: GAP-016
public enum InsulinDeliveryType: String, Codable, Sendable {
    /// Discrete bolus dose delivered instantly
    case bolus
    
    /// Basal delivery over a time period
    case basal
}

// MARK: - Basal Relative Dose Type

/// Type of basal-relative dose
/// Trace: GAP-016
public enum BasalRelativeDoseType: Sendable, Equatable {
    /// Discrete bolus (full volume counts toward IOB)
    case bolus
    
    /// Basal delivery with scheduled rate context
    /// - Parameter scheduledRate: The scheduled basal rate in U/hr
    case basal(scheduledRate: Double)
}

extension BasalRelativeDoseType: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case scheduledRate
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "bolus":
            self = .bolus
        case "basal":
            let rate = try container.decode(Double.self, forKey: .scheduledRate)
            self = .basal(scheduledRate: rate)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bolus:
            try container.encode("bolus", forKey: .type)
        case .basal(let scheduledRate):
            try container.encode("basal", forKey: .type)
            try container.encode(scheduledRate, forKey: .scheduledRate)
        }
    }
}

// MARK: - Loop Exponential Insulin Model (with delay)

/// Loop-compatible exponential insulin model with 10-minute delay
/// Trace: GAP-018, GAP-020
public struct LoopExponentialInsulinModel: Sendable {
    public let actionDuration: TimeInterval
    public let peakActivityTime: TimeInterval
    public let delay: TimeInterval
    
    // Pre-computed terms for efficiency
    private let τ: Double
    private let a: Double
    private let S: Double
    
    public init(
        actionDuration: TimeInterval,
        peakActivityTime: TimeInterval,
        delay: TimeInterval = IOBConstants.insulinDelay
    ) {
        self.actionDuration = actionDuration
        self.peakActivityTime = peakActivityTime
        self.delay = delay
        
        // Pre-compute model parameters (matches Loop exactly)
        let τ = peakActivityTime * (1 - peakActivityTime / actionDuration) /
                (1 - 2 * peakActivityTime / actionDuration)
        self.τ = τ
        self.a = 2 * τ / actionDuration
        self.S = 1 / (1 - a + (1 + a) * exp(-actionDuration / τ))
    }
    
    /// Calculate percent of insulin effect remaining at time t
    /// Returns 1.0 before delay, then decays according to exponential model
    public func percentEffectRemaining(at time: TimeInterval) -> Double {
        let timeAfterDelay = time - delay
        
        if timeAfterDelay <= 0 {
            return 1.0  // Before delay completes, full IOB
        }
        
        if timeAfterDelay >= actionDuration {
            return 0.0  // After action duration, zero IOB
        }
        
        let t = timeAfterDelay
        return 1 - S * (1 - a) *
            ((pow(t, 2) / (τ * actionDuration * (1 - a)) - t / τ - 1) * exp(-t / τ) + 1)
    }
    
    /// Calculate insulin activity at time t (rate of absorption)
    public func percentActivity(at time: TimeInterval) -> Double {
        let timeAfterDelay = time - delay
        
        guard timeAfterDelay > 0 && timeAfterDelay < actionDuration else {
            return 0.0
        }
        
        let t = timeAfterDelay
        let tNorm = t / τ
        
        // Activity = derivative of (1 - IOB)
        return S * (1 - a) / τ *
            ((2 * t / (τ * actionDuration * (1 - a)) - 1 / τ) * exp(-tNorm) +
             (pow(t, 2) / (τ * actionDuration * (1 - a)) - t / τ - 1) * (-1 / τ) * exp(-tNorm))
    }
}

// MARK: - Loop Insulin Model Preset

/// Loop-compatible insulin model presets with corrected parameters
/// Trace: GAP-020 (preset parameter alignment)
public enum LoopInsulinModelPreset: String, CaseIterable, Sendable, Codable {
    case rapidActingAdult
    case rapidActingChild
    case fiasp
    case lyumjev
    case afrezza
    
    public var model: LoopExponentialInsulinModel {
        switch self {
        case .rapidActingAdult:
            return LoopExponentialInsulinModel(
                actionDuration: 6 * 3600,       // 6 hours
                peakActivityTime: 75 * 60,      // 75 minutes
                delay: 10 * 60                  // 10 minutes
            )
        case .rapidActingChild:
            return LoopExponentialInsulinModel(
                actionDuration: 6 * 3600,       // 6 hours
                peakActivityTime: 65 * 60,      // 65 minutes (Fixed: was 60)
                delay: 10 * 60
            )
        case .fiasp:
            return LoopExponentialInsulinModel(
                actionDuration: 6 * 3600,       // 6 hours (Fixed: was 5.5)
                peakActivityTime: 55 * 60,      // 55 minutes
                delay: 10 * 60
            )
        case .lyumjev:
            return LoopExponentialInsulinModel(
                actionDuration: 6 * 3600,       // 6 hours (Fixed: was 5.5)
                peakActivityTime: 55 * 60,      // 55 minutes (Fixed: was 50)
                delay: 10 * 60
            )
        case .afrezza:
            return LoopExponentialInsulinModel(
                actionDuration: 5 * 3600,       // 5 hours (Fixed: was 3)
                peakActivityTime: 29 * 60,      // 29 minutes (Fixed: was 20)
                delay: 10 * 60
            )
        }
    }
    
    public var displayName: String {
        switch self {
        case .rapidActingAdult: return "Rapid-Acting Adult"
        case .rapidActingChild: return "Rapid-Acting Child"
        case .fiasp: return "Fiasp"
        case .lyumjev: return "Lyumjev"
        case .afrezza: return "Afrezza"
        }
    }
    
    /// NS-IOB-001c: Get LoopInsulinModel-conforming model for algorithm configuration
    public var loopModel: ExponentialInsulinModel {
        switch self {
        case .rapidActingAdult: return .rapidActingAdult
        case .rapidActingChild: return .rapidActingChild
        case .fiasp: return .fiasp
        case .lyumjev: return .lyumjev
        case .afrezza: return .afrezza
        }
    }
    
    /// NS-IOB-001b: Create preset from profile's insulinModel string
    /// Returns default (rapidActingAdult) if string is nil or invalid
    public static func fromProfileString(_ string: String?) -> LoopInsulinModelPreset {
        guard let string = string else { return .rapidActingAdult }
        return LoopInsulinModelPreset(rawValue: string) ?? .rapidActingAdult
    }
}

// MARK: - Basal Relative Dose

/// A dose annotated with scheduled basal context
/// This is the core type for Loop-compatible IOB calculation
/// Trace: GAP-016, GAP-019
public struct BasalRelativeDose: Sendable {
    /// Type of dose (bolus or basal with scheduled rate)
    public let type: BasalRelativeDoseType
    
    /// Start of delivery
    public let startDate: Date
    
    /// End of delivery
    public let endDate: Date
    
    /// Volume delivered in units
    public let volume: Double
    
    /// Insulin model for this dose
    public let insulinModel: LoopExponentialInsulinModel
    
    /// Duration of delivery
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    /// Net basal units: volume minus what would have been delivered anyway
    /// For boluses: full volume
    /// For basals: delivered - scheduled
    /// Trace: GAP-016 (critical gap)
    public var netBasalUnits: Double {
        switch type {
        case .bolus:
            return volume
        case .basal(let scheduledRate):
            let hours = duration / 3600
            guard hours > 0 else { return 0 }
            let scheduledUnits = scheduledRate * hours
            let net = volume - scheduledUnits  // DELTA from scheduled
            #if DEBUG
            // Debug: track net computation
            struct DebugCounter {
                static var printed = 0
                static var totalHours = 0.0
            }
            DebugCounter.totalHours += hours
            if DebugCounter.printed < 3 {
                print("🔢 netBasalUnits: vol=\(String(format: "%.3f", volume)) sched=\(String(format: "%.3f", scheduledUnits)) (rate=\(scheduledRate) × \(String(format: "%.3f", hours))h) → net=\(String(format: "%+.3f", net))")
                DebugCounter.printed += 1
            }
            if DebugCounter.printed == 3 {
                print("📐 Total hours so far: \(String(format: "%.2f", DebugCounter.totalHours))h (should be ~6h)")
                DebugCounter.printed += 1
            }
            #endif
            return net
        }
    }
    
    public init(
        type: BasalRelativeDoseType,
        startDate: Date,
        endDate: Date,
        volume: Double,
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.volume = volume
        self.insulinModel = insulinModel
    }
    
    // MARK: - IOB Calculation
    
    /// Calculate IOB contribution at a specific time
    /// Trace: GAP-017 (continuous delivery integration)
    public func insulinOnBoard(at date: Date, delta: TimeInterval = IOBConstants.defaultDelta) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else { return 0 }
        
        // Short doses (< 1.05 × delta) treated as momentary
        if duration <= IOBConstants.momentaryThresholdMultiplier * delta {
            return netBasalUnits * insulinModel.percentEffectRemaining(at: time)
        } else {
            // Long doses require continuous integration
            return netBasalUnits * continuousDeliveryInsulinOnBoard(at: date, delta: delta)
        }
    }
    
    /// Integrate IOB across delivery duration
    /// Loop integrates in delta-sized steps to model continuous delivery
    private func continuousDeliveryInsulinOnBoard(at date: Date, delta: TimeInterval) -> Double {
        let doseDuration = duration
        let time = date.timeIntervalSince(startDate)
        var iob: Double = 0
        var doseDate: TimeInterval = 0
        
        repeat {
            // Fraction of dose delivered in this segment
            let segment: Double
            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }
            
            // Add weighted IOB contribution
            let effectTime = time - doseDate
            let pct = insulinModel.percentEffectRemaining(at: effectTime)
            iob += segment * pct
            doseDate += delta
        } while doseDate <= min(floor((time + insulinModel.delay) / delta) * delta, doseDuration)
        
        return iob
    }
    
    /// Calculate glucose effect at a specific time
    public func glucoseEffect(at date: Date, insulinSensitivity: Double, delta: TimeInterval = IOBConstants.defaultDelta) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else { return 0 }
        
        // Consider doses within the delta time window as momentary
        if duration <= IOBConstants.momentaryThresholdMultiplier * delta {
            return netBasalUnits * -insulinSensitivity * (1.0 - insulinModel.percentEffectRemaining(at: time))
        } else {
            return netBasalUnits * -insulinSensitivity * continuousDeliveryPercentEffect(at: date, delta: delta)
        }
    }
    
    private func continuousDeliveryPercentEffect(at date: Date, delta: TimeInterval) -> Double {
        let doseDuration = duration
        let time = date.timeIntervalSince(startDate)
        var value: Double = 0
        var doseDate: TimeInterval = 0
        
        repeat {
            let segment: Double
            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }
            
            value += segment * (1.0 - insulinModel.percentEffectRemaining(at: time - doseDate))
            doseDate += delta
        } while doseDate <= min(floor((time + insulinModel.delay) / delta) * delta, doseDuration)
        
        return value
    }
}

// MARK: - Absolute Schedule Value

/// A scheduled value over a time range
public struct AbsoluteScheduleValue<T>: Sendable where T: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let value: T
    
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    public init(startDate: Date, endDate: Date, value: T) {
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
    }
}

// MARK: - Raw Insulin Dose

/// A raw insulin dose before basal annotation
public struct RawInsulinDose: Sendable {
    public let deliveryType: InsulinDeliveryType
    public let startDate: Date
    public let endDate: Date
    public let volume: Double
    public let insulinModel: LoopExponentialInsulinModel
    
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    public init(
        deliveryType: InsulinDeliveryType,
        startDate: Date,
        endDate: Date,
        volume: Double,
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) {
        self.deliveryType = deliveryType
        self.startDate = startDate
        self.endDate = endDate
        self.volume = volume
        self.insulinModel = insulinModel
    }
    
    /// Trim dose to a time range, adjusting volume proportionally
    /// Matches Loop's DoseEntry.trimmed(from:to:) in InsulinMath.swift:108-143
    /// ALG-COM-012: Required for parity with Loop's dose filtering
    public func trimmed(from start: Date? = nil, to end: Date? = nil) -> RawInsulinDose {
        let originalDuration = duration
        
        let newStartDate = max(start ?? .distantPast, self.startDate)
        let newEndDate = max(newStartDate, min(end ?? .distantFuture, self.endDate))
        
        var trimmedVolume = volume
        
        // Proportionally adjust volume if dose was trimmed
        if originalDuration > .ulpOfOne && (newStartDate > self.startDate || newEndDate < self.endDate) {
            let newDuration = newEndDate.timeIntervalSince(newStartDate)
            trimmedVolume = volume * (newDuration / originalDuration)
        }
        
        return RawInsulinDose(
            deliveryType: deliveryType,
            startDate: newStartDate,
            endDate: newEndDate,
            volume: trimmedVolume,
            insulinModel: insulinModel
        )
    }
    
    /// Create a bolus dose
    public static func bolus(
        units: Double,
        at date: Date,
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) -> RawInsulinDose {
        RawInsulinDose(
            deliveryType: .bolus,
            startDate: date,
            endDate: date,
            volume: units,
            insulinModel: insulinModel
        )
    }
    
    /// Create a temp basal dose
    public static func tempBasal(
        rate: Double,
        startDate: Date,
        duration: TimeInterval,
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) -> RawInsulinDose {
        let volume = rate * (duration / 3600)  // rate in U/hr, duration in seconds
        return RawInsulinDose(
            deliveryType: .basal,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            volume: volume,
            insulinModel: insulinModel
        )
    }
}

// MARK: - Dose Annotation

extension RawInsulinDose {
    /// Annotate a dose with basal schedule, splitting at schedule boundaries
    /// Trace: GAP-019 (dose splitting at boundaries)
    public func annotated(with basalHistory: [AbsoluteScheduleValue<Double>]) -> [BasalRelativeDose] {
        guard deliveryType == .basal else {
            // Boluses pass through unchanged
            return [BasalRelativeDose(
                type: .bolus,
                startDate: startDate,
                endDate: endDate,
                volume: volume,
                insulinModel: insulinModel
            )]
        }
        
        // ALG-100-IOB: Handle case where no basal schedule covers this dose
        // Use nearest basal rate or default to 1.0 U/hr
        if basalHistory.isEmpty {
            let fallbackRate = 1.0  // Default if no schedule available
            #if DEBUG
            print("⚠️ FALLBACK: Dose \(startDate) - \(endDate) has NO basal coverage, using \(fallbackRate) U/hr")
            #endif
            return [BasalRelativeDose(
                type: .basal(scheduledRate: fallbackRate),
                startDate: startDate,
                endDate: endDate,
                volume: volume,
                insulinModel: insulinModel
            )]
        }
        
        var doses: [BasalRelativeDose] = []
        
        for (index, basalItem) in basalHistory.enumerated() {
            // Determine segment boundaries
            let segmentStart: Date
            let segmentEnd: Date
            
            if index == 0 {
                segmentStart = startDate
            } else {
                segmentStart = basalItem.startDate
            }
            
            if index == basalHistory.count - 1 {
                segmentEnd = endDate
            } else {
                segmentEnd = basalHistory[index + 1].startDate
            }
            
            let clampedStart = max(segmentStart, startDate)
            let clampedEnd = max(segmentStart, min(segmentEnd, endDate))
            let segmentDuration = clampedEnd.timeIntervalSince(clampedStart)
            
            guard segmentDuration > 0 else { continue }
            
            // Prorate volume based on duration
            let segmentVolume: Double
            if duration > 0 {
                segmentVolume = volume * (segmentDuration / duration)
            } else {
                segmentVolume = 0
            }
            
            doses.append(BasalRelativeDose(
                type: .basal(scheduledRate: basalItem.value),
                startDate: clampedStart,
                endDate: clampedEnd,
                volume: segmentVolume,
                insulinModel: insulinModel
            ))
        }
        
        return doses
    }
}

// MARK: - Dose Reconciliation (ALG-100-RECONCILE)
// Matches Loop's InsulinMath.reconciled() behavior for overlapping doses

extension Array where Element == RawInsulinDose {
    /// Reconcile overlapping doses by clipping earlier doses to start of later doses
    /// This matches Loop's behavior where a new temp basal interrupts the previous one
    /// Trace: ALG-100-RECONCILE, GAP-001
    public func reconciled() -> [RawInsulinDose] {
        guard count > 1 else { return self }
        
        #if DEBUG
        let originalVolume = reduce(0.0) { $0 + $1.volume }
        #endif
        
        // Sort by start date
        let sorted = self.sorted { $0.startDate < $1.startDate }
        var reconciled: [RawInsulinDose] = []
        
        for (index, dose) in sorted.enumerated() {
            if dose.deliveryType == .bolus {
                // Boluses are always kept as-is
                reconciled.append(dose)
            } else {
                // For basals, check if there's a subsequent basal that interrupts this one
                var effectiveEndDate = dose.endDate
                
                // Look for any subsequent basal that starts before our end
                for nextIndex in (index + 1)..<sorted.count {
                    let nextDose = sorted[nextIndex]
                    if nextDose.deliveryType == .basal && nextDose.startDate < effectiveEndDate {
                        effectiveEndDate = nextDose.startDate
                        break  // First interrupting dose wins
                    }
                }
                
                // Only include if there's positive duration
                if effectiveEndDate > dose.startDate {
                    if effectiveEndDate != dose.endDate {
                        // Clip the dose
                        let originalDuration = dose.duration
                        let newDuration = effectiveEndDate.timeIntervalSince(dose.startDate)
                        // Prorate volume based on clipped duration
                        let clippedVolume = originalDuration > 0 ? dose.volume * (newDuration / originalDuration) : 0
                        
                        reconciled.append(RawInsulinDose(
                            deliveryType: dose.deliveryType,
                            startDate: dose.startDate,
                            endDate: effectiveEndDate,
                            volume: clippedVolume,
                            insulinModel: dose.insulinModel
                        ))
                    } else {
                        // No clipping needed
                        reconciled.append(dose)
                    }
                }
                // If effectiveEndDate <= startDate, the dose is completely overlapped and dropped
            }
        }
        
        #if DEBUG
        let reconciledVolume = reconciled.reduce(0.0) { $0 + $1.volume }
        print("📦 RECONCILE: \(self.count) → \(reconciled.count) doses, volume \(String(format: "%.3f", originalVolume))U → \(String(format: "%.3f", reconciledVolume))U")
        #endif
        
        return reconciled
    }
}

// MARK: - Collection Extensions

extension Array where Element == RawInsulinDose {
    /// Annotate all doses with basal schedule
    /// Trace: GAP-019
    public func annotated(with basalHistory: [AbsoluteScheduleValue<Double>]) -> [BasalRelativeDose] {
        var result: [BasalRelativeDose] = []
        
        for dose in self {
            if dose.deliveryType == .bolus {
                result.append(BasalRelativeDose(
                    type: .bolus,
                    startDate: dose.startDate,
                    endDate: dose.endDate,
                    volume: dose.volume,
                    insulinModel: dose.insulinModel
                ))
            } else {
                // Filter basal history to relevant range
                let relevantBasals = basalHistory.filter { basal in
                    basal.endDate > dose.startDate && basal.startDate < dose.endDate
                }
                let annotated = dose.annotated(with: relevantBasals)
                // Zero-duration or out-of-schedule doses are silently dropped
                result += annotated
            }
        }
        
        return result
    }
    
    /// Trim all doses to a time range
    /// ALG-COM-012: Matches Loop's dose trimming behavior
    public func trimmed(from start: Date? = nil, to end: Date? = nil) -> [RawInsulinDose] {
        compactMap { dose -> RawInsulinDose? in
            let trimmed = dose.trimmed(from: start, to: end)
            // Filter out doses with zero or negative duration after trimming
            guard trimmed.duration > 0 || trimmed.deliveryType == .bolus else {
                return nil
            }
            // Filter out doses with zero volume
            guard trimmed.volume > 0 else {
                return nil
            }
            return trimmed
        }
    }
    
    /// Filter doses to date range (start exclusive, end inclusive)
    /// ALG-COM-014: Matches Loop's filterDateRange behavior
    public func filterDateRange(_ start: Date?, _ end: Date?) -> [RawInsulinDose] {
        filter { dose in
            let afterStart = start == nil || dose.endDate > start!
            let beforeEnd = end == nil || dose.startDate <= end!
            return afterStart && beforeEnd
        }
    }
}

extension Array where Element == BasalRelativeDose {
    /// Calculate total IOB at a specific time
    /// Trace: GAP-016, GAP-017
    public func insulinOnBoard(at date: Date, delta: TimeInterval = IOBConstants.defaultDelta) -> Double {
        return reduce(0.0) { total, dose in
            total + dose.insulinOnBoard(at: date, delta: delta)
        }
    }
    
    /// Generate IOB timeline for prediction display
    /// Trace: GAP-022
    public func insulinOnBoardTimeline(
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = IOBConstants.defaultDelta
    ) -> [InsulinValue] {
        guard !isEmpty else { return [] }
        
        let timelineStart = start ?? self.map(\.startDate).min()!
        let timelineEnd = end ?? self.map(\.endDate).max()!.addingTimeInterval(IOBConstants.defaultInsulinActivityDuration)
        
        var date = timelineStart
        var values: [InsulinValue] = []
        
        repeat {
            let iob = insulinOnBoard(at: date, delta: delta)
            values.append(InsulinValue(startDate: date, value: iob))
            date = date.addingTimeInterval(delta)
        } while date <= timelineEnd
        
        return values
    }
    
    /// Calculate glucose effects timeline
    public func glucoseEffects(
        insulinSensitivity: Double,
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = IOBConstants.defaultDelta
    ) -> [GlucoseEffectValue] {
        guard !isEmpty else { return [] }
        
        let timelineStart = start ?? self.map(\.startDate).min()!
        let timelineEnd = end ?? self.map(\.endDate).max()!.addingTimeInterval(IOBConstants.defaultInsulinActivityDuration)
        
        var date = timelineStart
        var values: [GlucoseEffectValue] = []
        
        repeat {
            let effect = reduce(0.0) { total, dose in
                total + dose.glucoseEffect(at: date, insulinSensitivity: insulinSensitivity, delta: delta)
            }
            values.append(GlucoseEffectValue(startDate: date, value: effect))
            date = date.addingTimeInterval(delta)
        } while date <= timelineEnd
        
        return values
    }
}

// MARK: - Supporting Types

/// Insulin value at a point in time
public struct InsulinValue: Sendable {
    public let startDate: Date
    public let value: Double  // Units
    
    public init(startDate: Date, value: Double) {
        self.startDate = startDate
        self.value = value
    }
}

/// Glucose effect value at a point in time
public struct GlucoseEffectValue: Sendable {
    public let startDate: Date
    public let value: Double  // mg/dL
    
    public init(startDate: Date, value: Double) {
        self.startDate = startDate
        self.value = value
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Create time interval from hours
    public static func hours(_ hours: Double) -> TimeInterval {
        hours * 3600
    }
    
    /// Create time interval from minutes
    public static func minutes(_ minutes: Double) -> TimeInterval {
        minutes * 60
    }
    
    /// Convert to hours
    public var hours: Double {
        self / 3600
    }
}

// MARK: - InsulinDose Conversion (ALG-WIRE-002)

extension InsulinDose {
    /// Convert an InsulinDose to RawInsulinDose for parity calculation
    /// Trace: ALG-WIRE-002, GAP-016
    public func toRawInsulinDose(
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) -> RawInsulinDose {
        // Determine delivery type from source field
        let deliveryType: InsulinDeliveryType = source.contains("temp_basal") ? .basal : .bolus
        
        // For boluses: start = end = timestamp
        // For temp basals: use explicit endDate if provided, otherwise parse from source
        let computedEndDate: Date
        if deliveryType == .basal {
            // ALG-PENDING-001: Use explicit endDate if provided (for pending insulin)
            if let explicitEndDate = endDate {
                computedEndDate = explicitEndDate
            } else {
                // T6-004: Parse actual duration from source field if present
                var durationMinutes: Double = 5  // Default 5-minute segment
                if let range = source.range(of: "temp_basal_") {
                    let suffix = source[range.upperBound...]
                    if let minRange = suffix.range(of: "min") {
                        let durStr = suffix[..<minRange.lowerBound]
                        if let parsed = Double(durStr) {
                            durationMinutes = parsed
                        }
                    }
                }
                computedEndDate = timestamp.addingTimeInterval(durationMinutes * 60)
            }
        } else {
            computedEndDate = timestamp  // Bolus is instantaneous
        }
        
        return RawInsulinDose(
            deliveryType: deliveryType,
            startDate: timestamp,
            endDate: computedEndDate,
            volume: units,
            insulinModel: insulinModel
        )
    }
}

extension Array where Element == InsulinDose {
    /// Convert array of InsulinDose to RawInsulinDose for parity calculation
    /// NOTE: Does NOT reconcile - call .reconciled() on result if needed
    /// Trace: ALG-WIRE-002
    public func toRawInsulinDoses(
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) -> [RawInsulinDose] {
        map { $0.toRawInsulinDose(insulinModel: insulinModel) }
    }
    
    /// Convert to RawInsulinDose and reconcile overlapping doses
    /// This matches Loop's behavior where new temp basals interrupt previous ones
    /// Trace: ALG-WIRE-002, ALG-100-RECONCILE
    public func toReconciledRawInsulinDoses(
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) -> [RawInsulinDose] {
        toRawInsulinDoses(insulinModel: insulinModel).reconciled()
    }
    
    /// Calculate IOB using Loop parity algorithm (net basal units)
    /// Requires basal schedule for accurate calculation
    /// 
    /// ALG-IOB-007: Snaps computation time to 5-minute grid boundaries
    /// ALG-IOB-008: Returns MAX of adjacent grid point values (matches DoseStore.swift:1294-1304)
    /// 
    /// Trace: ALG-WIRE-003, GAP-016, ALG-IOB-007, ALG-IOB-008
    public func insulinOnBoardParity(
        at date: Date,
        basalSchedule: [AbsoluteScheduleValue<Double>],
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model,
        delta: TimeInterval = IOBConstants.defaultDelta
    ) -> Double {
        // ALG-100-RECONCILE: Reconcile doses before annotation
        let rawDoses = toReconciledRawInsulinDoses(insulinModel: insulinModel)
        let annotatedDoses = rawDoses.annotated(with: basalSchedule)
        
        // ALG-IOB-007: Snap to 5-minute grid boundaries (matches Loop's dateFlooredToTimeInterval)
        let flooredDate = date.flooredToTimeInterval(delta)
        let ceiledDate = flooredDate.addingTimeInterval(delta)
        
        // ALG-IOB-008: Compute IOB at both adjacent grid points and return MAX
        // This matches Loop's DoseStore.insulinOnBoard() behavior which:
        // 1. Gets IOB values from date-5min to date+5min
        // 2. Finds values adjacent to query time
        // 3. Returns the LARGER value (to capture recent bolus delivery)
        let iobAtFloor = annotatedDoses.insulinOnBoard(at: flooredDate, delta: delta)
        let iobAtCeil = annotatedDoses.insulinOnBoard(at: ceiledDate, delta: delta)
        
        return Swift.max(iobAtFloor, iobAtCeil)
    }
}

// MARK: - Basal Schedule Builder (ALG-WIRE-004)

import T1PalCore

extension Array where Element == BasalRate {
    /// Build an AbsoluteScheduleValue timeline from a relative basal schedule
    /// Expands the daily schedule to cover a time range
    /// 
    /// ALG-ZERO-DIV-TZ: Uses specified timezone (or system default) to interpret
    /// basal schedule times. NS profile times are in user's local timezone.
    /// The timezone should match the user's Loop settings (e.g., from pump.secondsFromGMT).
    /// 
    /// Trace: ALG-WIRE-004, ALG-ZERO-DIV-TZ
    public func toAbsoluteSchedule(
        from startDate: Date,
        to endDate: Date,
        timeZone: TimeZone? = nil
    ) -> [AbsoluteScheduleValue<Double>] {
        guard !isEmpty else { return [] }
        
        // ALG-ZERO-DIV-TZ: Use specified timezone or system default
        // NS profile basal times are in user's local timezone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? TimeZone.current
        
        var result: [AbsoluteScheduleValue<Double>] = []
        
        // Sort by start time
        let sorted = sorted { $0.startTime < $1.startTime }
        
        // Get the start of day for the start date (in specified timezone)
        var currentDate = calendar.startOfDay(for: startDate)
        
        // Iterate through each day in the range
        while currentDate <= endDate {
            for (index, rate) in sorted.enumerated() {
                // Calculate this segment's absolute start time
                let segmentStart = currentDate.addingTimeInterval(rate.startTime)
                
                // Calculate segment end time (next segment's start or end of day)
                let segmentEnd: Date
                if index + 1 < sorted.count {
                    segmentEnd = currentDate.addingTimeInterval(sorted[index + 1].startTime)
                } else {
                    // Last segment of the day - ends at midnight
                    segmentEnd = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                }
                
                // Only include if this segment overlaps our range
                if segmentEnd > startDate && segmentStart < endDate {
                    let clampedStart = segmentStart > startDate ? segmentStart : startDate
                    let clampedEnd = segmentEnd < endDate ? segmentEnd : endDate
                    
                    if clampedStart < clampedEnd {
                        result.append(AbsoluteScheduleValue(
                            startDate: clampedStart,
                            endDate: clampedEnd,
                            value: rate.rate
                        ))
                    }
                }
            }
            
            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return result
    }
}

// MARK: - ISF Schedule Builder (ALG-DOSE-002)

extension Array where Element == SensitivityFactor {
    /// Build an AbsoluteScheduleValue timeline from a relative ISF schedule
    /// Expands the daily schedule to cover a time range
    /// Trace: ALG-DOSE-002, GAP-010
    public func toAbsoluteSchedule(
        from startDate: Date,
        to endDate: Date
    ) -> [AbsoluteScheduleValue<Double>] {
        guard !isEmpty else { return [] }
        
        let calendar = Calendar.current
        var result: [AbsoluteScheduleValue<Double>] = []
        
        // Sort by start time
        let sorted = sorted { $0.startTime < $1.startTime }
        
        // Get the start of day for the start date
        var currentDate = calendar.startOfDay(for: startDate)
        
        // Iterate through each day in the range
        while currentDate <= endDate {
            for (index, factor) in sorted.enumerated() {
                // Calculate this segment's absolute start time
                let segmentStart = currentDate.addingTimeInterval(factor.startTime)
                
                // Calculate segment end time (next segment's start or end of day)
                let segmentEnd: Date
                if index + 1 < sorted.count {
                    segmentEnd = currentDate.addingTimeInterval(sorted[index + 1].startTime)
                } else {
                    // Last segment of the day - ends at midnight
                    segmentEnd = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                }
                
                // Only include if this segment overlaps our range
                if segmentEnd > startDate && segmentStart < endDate {
                    let clampedStart = segmentStart > startDate ? segmentStart : startDate
                    let clampedEnd = segmentEnd < endDate ? segmentEnd : endDate
                    
                    if clampedStart < clampedEnd {
                        result.append(AbsoluteScheduleValue(
                            startDate: clampedStart,
                            endDate: clampedEnd,
                            value: factor.factor
                        ))
                    }
                }
            }
            
            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return result
    }
}

// MARK: - Correction Range Schedule Builder (ALG-DOSE-002)

extension TargetRange {
    /// Convert to a ClosedRange for use in correction calculations
    /// Trace: ALG-DOSE-002, GAP-009
    public var asClosedRange: ClosedRange<Double> {
        low...high
    }
    
    /// Build a single AbsoluteScheduleValue covering the specified time range
    /// Note: This assumes a constant target range. For time-varying targets,
    /// a schedule would need to be built from multiple TargetRange values.
    public func toAbsoluteSchedule(
        from startDate: Date,
        to endDate: Date
    ) -> [AbsoluteScheduleValue<ClosedRange<Double>>] {
        [AbsoluteScheduleValue(startDate: startDate, endDate: endDate, value: asClosedRange)]
    }
}
