// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Oref0NetBasalIOB.swift
// T1Pal Mobile
//
// oref0-compatible net basal IOB calculation
// Requirements: REQ-ALGO-006
//
// oref0/oref1 traditionally uses absolute IOB, but the underlying math
// supports net basal calculation. This implementation enables cross-validation
// between oref0 and Loop IOB calculations.
//
// Reference: https://github.com/openaps/oref0/blob/master/lib/iob/calculate.js
//
// Trace: ALG-NET-002, PRD-009

import Foundation
import T1PalCore

// MARK: - oref0 Net Basal IOB Calculator

/// oref0-compatible net basal IOB calculator
///
/// Uses the oref0 exponential insulin model with net basal units.
/// This enables cross-validation between oref0 and Loop IOB calculations.
///
/// **oref0 Model Characteristics:**
/// - Exponential decay with configurable DIA (default 6h for rapid-acting)
/// - Peak time based on insulin type (typically 1h for Humalog/Novolog)
/// - No explicit delay (absorbed into curve shape)
/// - Uses Simpson's rule integration for IOB calculation
///
/// **Net Basal Adaptation:**
/// - Annotates doses with scheduled basal to compute net contribution
/// - Boluses contribute full volume
/// - Temp basals contribute (delivered - scheduled) volume
///
/// Trace: ALG-NET-002
public struct Oref0NetBasalIOBCalculator: NetBasalIOBProvider {
    /// The insulin model to use for IOB calculation
    public let insulinModel: InsulinModel
    
    /// Delta for integration (5 minutes, matches oref0)
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
        // Convert doses to net basal contributions
        let netDoses = annotateWithNetBasal(doses: doses, basalSchedule: basalSchedule)
        
        // Sum IOB contributions using oref0 model
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
    private struct Oref0NetDose {
        let timestamp: Date
        let netUnits: Double  // Net contribution (can be negative for suspended basal)
        let duration: TimeInterval  // 0 for bolus, positive for basal segments
    }
    
    // MARK: - Dose Annotation
    
    /// Annotate doses with scheduled basal to compute net contribution
    private func annotateWithNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>]
    ) -> [Oref0NetDose] {
        doses.compactMap { dose -> Oref0NetDose? in
            if dose.source.contains("temp_basal") || dose.source.contains("basal") {
                // Temp basal: compute net = delivered - scheduled
                return annotateBasalDose(dose, basalSchedule: basalSchedule)
            } else {
                // Bolus: full volume counts
                return Oref0NetDose(
                    timestamp: dose.timestamp,
                    netUnits: dose.units,
                    duration: 0
                )
            }
        }
    }
    
    /// Annotate a basal dose with scheduled rate to get net contribution
    private func annotateBasalDose(
        _ dose: InsulinDose,
        basalSchedule: [AbsoluteScheduleValue<Double>]
    ) -> Oref0NetDose {
        // Find the scheduled basal rate at this time
        let scheduledRate = basalSchedule.first { schedule in
            dose.timestamp >= schedule.startDate && dose.timestamp < schedule.endDate
        }?.value ?? 0
        
        // Assume 5-minute basal segments (standard for oref0)
        let segmentDuration: TimeInterval = 5 * 60
        let segmentHours = segmentDuration / 3600
        
        // Scheduled units for this segment
        let scheduledUnits = scheduledRate * segmentHours
        
        // Net = delivered - scheduled
        let netUnits = dose.units - scheduledUnits
        
        return Oref0NetDose(
            timestamp: dose.timestamp,
            netUnits: netUnits,
            duration: segmentDuration
        )
    }
    
    // MARK: - IOB Calculation
    
    /// Calculate IOB contribution from a single net dose using oref0 model
    private func iobFromNetDose(_ dose: Oref0NetDose, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        
        // Future doses don't contribute
        guard elapsed >= 0 else { return 0 }
        
        // Convert to hours for oref0 model
        let hoursAgo = elapsed / 3600
        
        // Get fraction remaining using oref0 exponential model
        let fractionRemaining = insulinModel.iob(at: hoursAgo)
        
        return dose.netUnits * fractionRemaining
    }
    
    /// Calculate activity contribution from a single net dose
    private func activityFromNetDose(_ dose: Oref0NetDose, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        
        guard elapsed >= 0 else { return 0 }
        
        let hoursAgo = elapsed / 3600
        let activity = insulinModel.activity(at: hoursAgo)
        
        return dose.netUnits * activity
    }
}

// MARK: - Oref1Algorithm Extension

extension Oref1Algorithm {
    /// Create a net basal IOB calculator compatible with this algorithm's insulin type
    ///
    /// Enables cross-validation between oref1 and Loop IOB calculations.
    /// Uses the same insulin type as configured in the algorithm.
    ///
    /// Usage:
    /// ```swift
    /// let algorithm = Oref1Algorithm(insulinType: .humalog)
    /// let netCalculator = algorithm.createNetBasalIOBCalculator()
    /// let netIOB = netCalculator.insulinOnBoardNetBasal(
    ///     doses: doseHistory,
    ///     basalSchedule: schedule,
    ///     at: Date()
    /// )
    /// ```
    ///
    /// Trace: ALG-NET-002
    public func createNetBasalIOBCalculator(
        insulinType: InsulinType = .novolog,
        dia: Double? = nil
    ) -> Oref0NetBasalIOBCalculator {
        Oref0NetBasalIOBCalculator(insulinType: insulinType, dia: dia)
    }
}

// MARK: - Cross-Algorithm Comparison

/// Result of comparing oref0 vs Loop net basal IOB calculations
public struct Oref0LoopIOBComparison: Sendable {
    /// IOB calculated using oref0 model
    public let oref0IOB: Double
    
    /// IOB calculated using Loop model
    public let loopIOB: Double
    
    /// Absolute difference: |oref0 - loop|
    public var absoluteDifference: Double { abs(oref0IOB - loopIOB) }
    
    /// Relative difference as percentage of average
    public var relativeDifference: Double {
        let average = (oref0IOB + loopIOB) / 2
        guard average != 0 else { return 0 }
        return (absoluteDifference / abs(average)) * 100
    }
    
    /// Whether the calculations are within acceptable tolerance
    /// Default tolerance: 0.05 U (matches ALG-XVAL target)
    public func isWithinTolerance(_ tolerance: Double = 0.05) -> Bool {
        absoluteDifference <= tolerance
    }
    
    public init(oref0IOB: Double, loopIOB: Double) {
        self.oref0IOB = oref0IOB
        self.loopIOB = loopIOB
    }
}

/// Compare oref0 vs Loop net basal IOB calculations
///
/// Useful for cross-validation to ensure algorithm alignment.
///
/// - Parameters:
///   - doses: Insulin dose history
///   - basalSchedule: Scheduled basal rates
///   - at: Time to compare at
///   - oref0Calculator: oref0 net basal calculator
///   - loopCalculator: Loop net basal calculator
/// - Returns: Comparison result showing both values and difference
public func compareOref0LoopIOB(
    doses: [InsulinDose],
    basalSchedule: [AbsoluteScheduleValue<Double>],
    at date: Date,
    oref0Calculator: Oref0NetBasalIOBCalculator,
    loopCalculator: LoopNetBasalIOBCalculator
) -> Oref0LoopIOBComparison {
    let oref0IOB = oref0Calculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: IOBConstants.defaultDelta
    )
    
    let loopIOB = loopCalculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: IOBConstants.defaultDelta
    )
    
    return Oref0LoopIOBComparison(oref0IOB: oref0IOB, loopIOB: loopIOB)
}
