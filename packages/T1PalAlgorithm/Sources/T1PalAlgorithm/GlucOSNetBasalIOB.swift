// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GlucOSNetBasalIOB.swift
// T1Pal Mobile
//
// GlucOS-compatible net basal IOB calculation
// Requirements: REQ-ALGO-006
//
// GlucOS uses a similar insulin model to oref0 but with research-based
// enhancements. This implementation enables cross-validation between
// GlucOS, Loop, and oref0 IOB calculations.
//
// Source: UC Davis GlucOS research project
//
// Trace: ALG-NET-003, PRD-009

import Foundation
import T1PalCore

// MARK: - GlucOS Net Basal IOB Calculator

/// GlucOS-compatible net basal IOB calculator
///
/// Uses the GlucOS insulin model with net basal units for cross-algorithm
/// validation. GlucOS shares the exponential model foundation with oref0
/// but may apply different smoothing or filtering.
///
/// **GlucOS Model Characteristics:**
/// - Exponential decay with configurable DIA
/// - Low-pass filtered glucose inputs (applies to predictions, not IOB)
/// - Dynamic ISF scaling (applies to dosing, not IOB calculation)
/// - Research-validated parameters from UC Davis
///
/// **Net Basal Calculation:**
/// Same methodology as Loop/oref0:
/// - Annotates doses with scheduled basal to compute net contribution
/// - Boluses contribute full volume
/// - Temp basals contribute (delivered - scheduled) volume
///
/// Trace: ALG-NET-003
public struct GlucOSNetBasalIOBCalculator: NetBasalIOBProvider {
    /// The insulin model to use for IOB calculation
    public let insulinModel: InsulinModel
    
    /// Delta for integration (5 minutes, matches GlucOS standard)
    public let delta: TimeInterval
    
    public init(
        insulinType: InsulinType = .novolog,
        dia: Double? = nil,
        delta: TimeInterval = 5 * 60
    ) {
        self.insulinModel = InsulinModel(insulinType: insulinType, dia: dia)
        self.delta = delta
    }
    
    public init(
        insulinModel: InsulinModel,
        delta: TimeInterval = 5 * 60
    ) {
        self.insulinModel = insulinModel
        self.delta = delta
    }
    
    // MARK: - NetBasalIOBProvider Implementation
    
    public func insulinOnBoardNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double {
        let netDoses = annotateWithNetBasal(doses: doses, basalSchedule: basalSchedule)
        
        return netDoses.reduce(0) { total, netDose in
            total + iobFromNetDose(netDose, at: date)
        }
    }
    
    public func insulinActivityNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double {
        let netDoses = annotateWithNetBasal(doses: doses, basalSchedule: basalSchedule)
        
        return netDoses.reduce(0) { total, netDose in
            total + activityFromNetDose(netDose, at: date)
        }
    }
    
    // MARK: - Internal Types
    
    /// A dose annotated with net basal units
    private struct GlucOSNetDose {
        let timestamp: Date
        let netUnits: Double
        let duration: TimeInterval
    }
    
    // MARK: - Dose Annotation
    
    private func annotateWithNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>]
    ) -> [GlucOSNetDose] {
        doses.compactMap { dose -> GlucOSNetDose? in
            if dose.source.contains("temp_basal") || dose.source.contains("basal") {
                return annotateBasalDose(dose, basalSchedule: basalSchedule)
            } else {
                return GlucOSNetDose(
                    timestamp: dose.timestamp,
                    netUnits: dose.units,
                    duration: 0
                )
            }
        }
    }
    
    private func annotateBasalDose(
        _ dose: InsulinDose,
        basalSchedule: [AbsoluteScheduleValue<Double>]
    ) -> GlucOSNetDose {
        let scheduledRate = basalSchedule.first { schedule in
            dose.timestamp >= schedule.startDate && dose.timestamp < schedule.endDate
        }?.value ?? 0
        
        let segmentDuration: TimeInterval = 5 * 60
        let segmentHours = segmentDuration / 3600
        let scheduledUnits = scheduledRate * segmentHours
        let netUnits = dose.units - scheduledUnits
        
        return GlucOSNetDose(
            timestamp: dose.timestamp,
            netUnits: netUnits,
            duration: segmentDuration
        )
    }
    
    // MARK: - IOB Calculation
    
    private func iobFromNetDose(_ dose: GlucOSNetDose, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        guard elapsed >= 0 else { return 0 }
        
        let hoursAgo = elapsed / 3600
        let fractionRemaining = insulinModel.iob(at: hoursAgo)
        
        return dose.netUnits * fractionRemaining
    }
    
    private func activityFromNetDose(_ dose: GlucOSNetDose, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        guard elapsed >= 0 else { return 0 }
        
        let hoursAgo = elapsed / 3600
        let activity = insulinModel.activity(at: hoursAgo)
        
        return dose.netUnits * activity
    }
}

// MARK: - GlucOSAlgorithm Extension

extension GlucOSAlgorithm {
    /// Create a net basal IOB calculator compatible with GlucOS settings
    ///
    /// Enables cross-validation between GlucOS, Loop, and oref0 IOB calculations.
    ///
    /// Usage:
    /// ```swift
    /// let algorithm = GlucOSAlgorithm()
    /// let netCalculator = algorithm.createNetBasalIOBCalculator()
    /// let netIOB = netCalculator.insulinOnBoardNetBasal(
    ///     doses: doseHistory,
    ///     basalSchedule: schedule,
    ///     at: Date()
    /// )
    /// ```
    ///
    /// Trace: ALG-NET-003
    public func createNetBasalIOBCalculator(
        insulinType: InsulinType = .novolog,
        dia: Double? = nil
    ) -> GlucOSNetBasalIOBCalculator {
        GlucOSNetBasalIOBCalculator(insulinType: insulinType, dia: dia)
    }
}

// MARK: - Three-Way Algorithm Comparison

/// Result of comparing all three algorithm IOB calculations
public struct ThreeWayIOBComparison: Sendable {
    /// IOB calculated using Loop model
    public let loopIOB: Double
    
    /// IOB calculated using oref0 model
    public let oref0IOB: Double
    
    /// IOB calculated using GlucOS model
    public let glucosIOB: Double
    
    /// Maximum difference between any two algorithms
    public var maxDifference: Double {
        let diffs = [
            abs(loopIOB - oref0IOB),
            abs(loopIOB - glucosIOB),
            abs(oref0IOB - glucosIOB)
        ]
        return diffs.max() ?? 0
    }
    
    /// Average IOB across all three algorithms
    public var averageIOB: Double {
        (loopIOB + oref0IOB + glucosIOB) / 3
    }
    
    /// Standard deviation of IOB values
    public var standardDeviation: Double {
        let mean = averageIOB
        let variance = [loopIOB, oref0IOB, glucosIOB]
            .map { pow($0 - mean, 2) }
            .reduce(0, +) / 3
        return sqrt(variance)
    }
    
    /// Whether all algorithms agree within tolerance
    public func isAligned(tolerance: Double = 0.05) -> Bool {
        maxDifference <= tolerance
    }
    
    /// Identify which algorithm (if any) is an outlier
    public var outlier: String? {
        let mean = averageIOB
        let threshold = standardDeviation * 2
        
        if abs(loopIOB - mean) > threshold { return "Loop" }
        if abs(oref0IOB - mean) > threshold { return "oref0" }
        if abs(glucosIOB - mean) > threshold { return "GlucOS" }
        return nil
    }
    
    public init(loopIOB: Double, oref0IOB: Double, glucosIOB: Double) {
        self.loopIOB = loopIOB
        self.oref0IOB = oref0IOB
        self.glucosIOB = glucosIOB
    }
}

/// Compare all three algorithm net basal IOB calculations
///
/// Useful for cross-validation to ensure all algorithms are aligned.
///
/// - Parameters:
///   - doses: Insulin dose history
///   - basalSchedule: Scheduled basal rates
///   - at: Time to compare at
///   - loopCalculator: Loop net basal calculator
///   - oref0Calculator: oref0 net basal calculator
///   - glucosCalculator: GlucOS net basal calculator
/// - Returns: Three-way comparison result
public func compareAllAlgorithmsIOB(
    doses: [InsulinDose],
    basalSchedule: [AbsoluteScheduleValue<Double>],
    at date: Date,
    loopCalculator: LoopNetBasalIOBCalculator,
    oref0Calculator: Oref0NetBasalIOBCalculator,
    glucosCalculator: GlucOSNetBasalIOBCalculator
) -> ThreeWayIOBComparison {
    let delta = IOBConstants.defaultDelta
    
    let loopIOB = loopCalculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: delta
    )
    
    let oref0IOB = oref0Calculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: delta
    )
    
    let glucosIOB = glucosCalculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: delta
    )
    
    return ThreeWayIOBComparison(
        loopIOB: loopIOB,
        oref0IOB: oref0IOB,
        glucosIOB: glucosIOB
    )
}
