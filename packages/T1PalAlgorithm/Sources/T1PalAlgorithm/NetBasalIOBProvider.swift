// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NetBasalIOBProvider.swift
// T1Pal Mobile
//
// Cross-algorithm protocol for net basal IOB calculation
// Requirements: REQ-ALGO-006
//
// All major AID systems (Loop, oref0, AAPS, Trio) use net basal units for IOB:
// - IOB = delivered insulin - scheduled basal insulin
// - This ensures temp basals and suspends are correctly accounted
//
// This protocol enables any algorithm to adopt Loop-compatible net basal IOB.
//
// Trace: ALG-NET-001, PRD-009

import Foundation
import T1PalCore

// MARK: - Net Basal IOB Provider Protocol

/// Protocol for algorithms that support net basal IOB calculation
///
/// Net basal IOB accounts for the difference between delivered and scheduled
/// basal insulin, which is critical for accurate dosing decisions:
///
/// ```
/// Net IOB = Σ (delivered[t] - scheduled[t]) × remainingEffect(t)
/// ```
///
/// **Why net basal matters:**
/// - A temp basal of 0 U/hr when scheduled is 1 U/hr = -1 U/hr net contribution
/// - A temp basal of 2 U/hr when scheduled is 1 U/hr = +1 U/hr net contribution
/// - Without net basal, algorithms double-count scheduled insulin
///
/// **Adoption:**
/// - Loop: Uses this natively via `BasalRelativeDose`
/// - oref0/oref1: Can adopt for cross-validation with Loop
/// - GlucOS: Can adopt for production parity
///
/// Trace: ALG-NET-001
public protocol NetBasalIOBProvider: Sendable {
    /// Calculate insulin on board using net basal units
    ///
    /// - Parameters:
    ///   - doses: Raw insulin doses (boluses and temp basals)
    ///   - basalSchedule: Scheduled basal rates timeline
    ///   - at: Time to calculate IOB for
    ///   - delta: Integration step size (default 5 minutes)
    /// - Returns: Net IOB in units
    func insulinOnBoardNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double
    
    /// Calculate insulin activity using net basal units
    ///
    /// Activity represents the rate of insulin absorption at a given time.
    /// Used for glucose effect calculations.
    ///
    /// - Parameters:
    ///   - doses: Raw insulin doses
    ///   - basalSchedule: Scheduled basal rates timeline
    ///   - at: Time to calculate activity for
    ///   - delta: Integration step size
    /// - Returns: Net activity in units/hour
    func insulinActivityNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double
}

// MARK: - Default Implementation

public extension NetBasalIOBProvider {
    /// Default delta is 5 minutes (matches Loop)
    func insulinOnBoardNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date
    ) -> Double {
        insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: date,
            delta: IOBConstants.defaultDelta
        )
    }
    
    func insulinActivityNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date
    ) -> Double {
        insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: date,
            delta: IOBConstants.defaultDelta
        )
    }
}

// MARK: - Loop-Compatible Implementation

/// Loop-compatible net basal IOB calculator
///
/// Uses `BasalRelativeDose` annotation to calculate net IOB exactly as Loop does.
/// This is the reference implementation for other algorithms to validate against.
///
/// Trace: ALG-NET-001
public struct LoopNetBasalIOBCalculator: NetBasalIOBProvider {
    public let insulinModel: LoopExponentialInsulinModel
    
    public init(
        insulinModel: LoopExponentialInsulinModel = LoopInsulinModelPreset.rapidActingAdult.model
    ) {
        self.insulinModel = insulinModel
    }
    
    public func insulinOnBoardNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double {
        // Convert to raw doses and annotate with basal schedule
        // ALG-100-RECONCILE: Reconcile overlapping doses before annotation
        let rawDoses = doses.toReconciledRawInsulinDoses(insulinModel: insulinModel)
        let annotatedDoses = rawDoses.annotated(with: basalSchedule)
        return annotatedDoses.insulinOnBoard(at: date, delta: delta)
    }
    
    public func insulinActivityNetBasal(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        at date: Date,
        delta: TimeInterval
    ) -> Double {
        // Convert and annotate
        // ALG-100-RECONCILE: Reconcile overlapping doses before annotation
        let rawDoses = doses.toReconciledRawInsulinDoses(insulinModel: insulinModel)
        let annotatedDoses = rawDoses.annotated(with: basalSchedule)
        
        // Sum activity across all annotated doses
        return annotatedDoses.reduce(0) { total, dose in
            let time = date.timeIntervalSince(dose.startDate)
            guard time >= 0 else { return total }
            return total + dose.netBasalUnits * insulinModel.percentActivity(at: time)
        }
    }
}

// MARK: - IOB Timeline Generation

public extension NetBasalIOBProvider {
    /// Generate an IOB timeline using net basal calculation
    ///
    /// Useful for predictions and chart display.
    ///
    /// - Parameters:
    ///   - doses: Insulin dose history
    ///   - basalSchedule: Scheduled basal rates
    ///   - start: Timeline start (defaults to earliest dose)
    ///   - end: Timeline end (defaults to 6h after last dose)
    ///   - delta: Step size (default 5 minutes)
    /// - Returns: Array of IOB values at each time step
    func iobTimeline(
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = IOBConstants.defaultDelta
    ) -> [InsulinValue] {
        guard !doses.isEmpty else { return [] }
        
        let timelineStart = start ?? doses.map(\.timestamp).min()!
        let timelineEnd = end ?? doses.map(\.timestamp).max()!
            .addingTimeInterval(IOBConstants.defaultInsulinActivityDuration)
        
        var values: [InsulinValue] = []
        var date = timelineStart
        
        while date <= timelineEnd {
            let iob = insulinOnBoardNetBasal(
                doses: doses,
                basalSchedule: basalSchedule,
                at: date,
                delta: delta
            )
            values.append(InsulinValue(startDate: date, value: iob))
            date = date.addingTimeInterval(delta)
        }
        
        return values
    }
}

// MARK: - Absolute vs Net Comparison

/// Result of comparing absolute vs net basal IOB calculations
public struct IOBComparisonResult: Sendable {
    /// IOB using absolute units (ignores basal schedule)
    public let absoluteIOB: Double
    
    /// IOB using net basal units (accounts for scheduled basal)
    public let netBasalIOB: Double
    
    /// Difference: absolute - net
    public var difference: Double { absoluteIOB - netBasalIOB }
    
    /// Percentage difference relative to absolute
    public var percentDifference: Double {
        guard absoluteIOB != 0 else { return 0 }
        return (difference / absoluteIOB) * 100
    }
    
    public init(absoluteIOB: Double, netBasalIOB: Double) {
        self.absoluteIOB = absoluteIOB
        self.netBasalIOB = netBasalIOB
    }
}

/// Compare absolute vs net basal IOB calculations
///
/// Useful for cross-validation and debugging algorithm differences.
///
/// - Parameters:
///   - doses: Insulin dose history
///   - basalSchedule: Scheduled basal rates
///   - at: Time to compare at
///   - absoluteCalculator: Calculator for absolute IOB
///   - netCalculator: Calculator for net basal IOB
/// - Returns: Comparison result showing both values
public func compareIOBCalculations(
    doses: [InsulinDose],
    basalSchedule: [AbsoluteScheduleValue<Double>],
    at date: Date,
    absoluteCalculator: LoopIOBCalculator,
    netCalculator: NetBasalIOBProvider
) -> IOBComparisonResult {
    let absoluteIOB = absoluteCalculator.insulinOnBoard(doses: doses, at: date)
    let netIOB = netCalculator.insulinOnBoardNetBasal(
        doses: doses,
        basalSchedule: basalSchedule,
        at: date,
        delta: IOBConstants.defaultDelta
    )
    return IOBComparisonResult(absoluteIOB: absoluteIOB, netBasalIOB: netIOB)
}
