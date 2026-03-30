// SPDX-License-Identifier: AGPL-3.0-or-later
//
// IOBArrayGenerator.swift
// T1Pal Mobile
//
// Generates 48-element IOB projection arrays matching oref0 determine-basal.
// Supports two modes:
//   1. Snapshot decay: exponential decay from a single IOB snapshot (matches JS adapter)
//   2. Dose history: full pharmacokinetic calculation from dose history (Option B, full fidelity)
//
// Based on:
//   oref0/lib/iob/calculate.js  — per-dose exponential insulin model
//   oref0/lib/iob/total.js      — aggregate across active doses
//   oref0-js adapter generateIobArray() — snapshot decay approximation

import Foundation

// MARK: - IOB Array Tick

/// A single tick in the IOB projection array, matching JS oref0 structure.
///
/// JS determine-basal iterates `iobArray.forEach(function(iobTick) { ... })`
/// where each tick has `{iob, activity, iobWithZeroTemp: {iob, activity}}`.
public struct IOBArrayTick: Sendable {
    /// Total IOB remaining at this tick (units)
    public let iob: Double
    /// Basal IOB portion (units)
    public let basalIob: Double
    /// Insulin activity at this tick (units/min — determines BG impact)
    public let activity: Double
    /// Counterfactual IOB if zero temp were set now
    public let zeroTempIob: Double
    /// Counterfactual activity if zero temp were set now
    public let zeroTempActivity: Double

    public init(
        iob: Double,
        basalIob: Double = 0,
        activity: Double,
        zeroTempIob: Double,
        zeroTempActivity: Double
    ) {
        self.iob = iob
        self.basalIob = basalIob
        self.activity = activity
        self.zeroTempIob = zeroTempIob
        self.zeroTempActivity = zeroTempActivity
    }
}

// MARK: - IOB Array Generator

/// Generates IOB projection arrays for oref0 prediction curves.
///
/// Two generation modes:
///   - `fromSnapshot`: Exponential decay from IOB snapshot (matches JS adapter behavior)
///   - `fromDoseHistory`: Full pharmacokinetic calculation per dose (Option B, full fidelity)
public struct IOBArrayGenerator: Sendable {

    /// Number of 5-minute ticks to generate (48 = 4 hours)
    public static let defaultTicks = 48
    /// Minutes per tick
    public static let tickMinutes = 5

    // MARK: - Snapshot Mode (matches JS adapter)

    /// Generate IOB array from a single IOB snapshot using exponential decay.
    ///
    /// Matches the JS adapter's `generateIobArray()`:
    ///   tau = DIA_minutes / 1.85
    ///   decay(t) = exp(-t / tau)
    ///   activity[i] = activity0 * decay(i * 5)
    ///
    /// - Parameters:
    ///   - iob: Current total IOB (units)
    ///   - basalIob: Basal portion of IOB (units)
    ///   - activity: Current insulin activity (units/min)
    ///   - zeroTempIob: IOB if zero temp were set now (units)
    ///   - zeroTempActivity: Activity if zero temp were set now (units/min)
    ///   - dia: Duration of insulin action (hours)
    ///   - ticks: Number of 5-minute ticks (default 48)
    public static func fromSnapshot(
        iob: Double,
        basalIob: Double = 0,
        activity: Double,
        zeroTempIob: Double? = nil,
        zeroTempActivity: Double? = nil,
        dia: Double = 5.0,
        ticks: Int = defaultTicks
    ) -> [IOBArrayTick] {
        let diaMinutes = dia * 60.0
        let tau = diaMinutes / 1.85
        let ztIob = zeroTempIob ?? iob
        let ztActivity = zeroTempActivity ?? activity

        return (0..<ticks).map { i in
            let t = Double(i * tickMinutes)
            let decay = exp(-t / tau)
            return IOBArrayTick(
                iob: (iob * decay).rounded(toPlaces: 4),
                basalIob: (basalIob * decay).rounded(toPlaces: 4),
                activity: (activity * decay).rounded(toPlaces: 6),
                zeroTempIob: (ztIob * decay).rounded(toPlaces: 4),
                zeroTempActivity: (ztActivity * decay).rounded(toPlaces: 6)
            )
        }
    }

    // MARK: - Dose History Mode (Option B — full fidelity)

    /// Generate IOB array from dose history using the oref0 exponential insulin model.
    ///
    /// Ports oref0/lib/iob/calculate.js `iobCalcExponential` and oref0/lib/iob/total.js.
    /// For each tick t, sums contributions from all active doses using:
    ///   tau = peak * (1 - peak/end) / (1 - 2*peak/end)
    ///   a = 2 * tau / end
    ///   S = 1 / (1 - a + (1+a) * exp(-end/tau))
    ///   activity(t) = insulin * (S/tau²) * t * (1-t/end) * exp(-t/tau)
    ///   iob(t) = insulin * (1 - S*(1-a) * ((t²/(tau*end*(1-a)) - t/tau - 1) * exp(-t/tau) + 1))
    ///
    /// - Parameters:
    ///   - doses: Active insulin doses (with timestamps and units)
    ///   - currentTime: Reference time for projection
    ///   - profile: Insulin profile (curve type, DIA, peak)
    ///   - currentTemp: Current temp basal (for zeroTemp counterfactual)
    ///   - ticks: Number of 5-minute ticks (default 48)
    public static func fromDoseHistory(
        doses: [InsulinDose],
        currentTime: Date,
        dia: Double = 5.0,
        peak: Double = 75.0,
        curve: InsulinCurveType = .rapidActing,
        ticks: Int = defaultTicks
    ) -> [IOBArrayTick] {
        let end = dia * 60.0  // DIA in minutes
        let resolvedPeak = curve.resolvedPeak(userPeak: peak)

        // Pre-compute exponential model constants (shared across all ticks)
        let tau = resolvedPeak * (1.0 - resolvedPeak / end) / (1.0 - 2.0 * resolvedPeak / end)
        let a = 2.0 * tau / end
        let S = 1.0 / (1.0 - a + (1.0 + a) * exp(-end / tau))

        return (0..<ticks).map { tickIndex in
            let tickTime = currentTime.addingTimeInterval(Double(tickIndex * tickMinutes) * 60.0)
            var totalIob = 0.0
            var totalActivity = 0.0
            var totalBasalIob = 0.0

            for dose in doses {
                let minsAgo = tickTime.timeIntervalSince(dose.timestamp) / 60.0
                guard minsAgo >= 0 && minsAgo < end else { continue }

                let contrib = exponentialContrib(
                    insulin: dose.units,
                    minsAgo: minsAgo,
                    end: end,
                    tau: tau,
                    a: a,
                    S: S
                )
                totalIob += contrib.iob
                totalActivity += contrib.activity
                if dose.units < 0.1 { totalBasalIob += contrib.iob }
            }

            return IOBArrayTick(
                iob: (totalIob * 1000).rounded() / 1000,
                basalIob: (totalBasalIob * 1000).rounded() / 1000,
                activity: (totalActivity * 10000).rounded() / 10000,
                zeroTempIob: (totalIob * 1000).rounded() / 1000,
                zeroTempActivity: (totalActivity * 10000).rounded() / 10000
            )
        }
    }

    // MARK: - Exponential Insulin Model

    /// Per-dose IOB/activity contribution using the oref0 exponential model.
    ///
    /// Direct port of oref0/lib/iob/calculate.js `iobCalcExponential`.
    /// Formula source: https://github.com/LoopKit/Loop/issues/388#issuecomment-317938473
    ///
    /// - Parameters:
    ///   - insulin: Dose amount (units)
    ///   - minsAgo: Minutes since dose was given
    ///   - end: DIA in minutes
    ///   - tau: Time constant of exponential decay
    ///   - a: Rise time factor (2*tau/end)
    ///   - S: Auxiliary scale factor
    /// - Returns: (iob, activity) contribution from this dose
    public static func exponentialContrib(
        insulin: Double,
        minsAgo: Double,
        end: Double,
        tau: Double,
        a: Double,
        S: Double
    ) -> (iob: Double, activity: Double) {
        guard minsAgo >= 0 && minsAgo < end else { return (0, 0) }

        let activity = insulin * (S / pow(tau, 2)) * minsAgo * (1.0 - minsAgo / end) * exp(-minsAgo / tau)
        let iob = insulin * (1.0 - S * (1.0 - a) * (
            (pow(minsAgo, 2) / (tau * end * (1.0 - a)) - minsAgo / tau - 1.0)
            * exp(-minsAgo / tau) + 1.0
        ))

        return (iob: max(0, iob), activity: max(0, activity))
    }
}

// MARK: - Insulin Curve Type

/// oref0 insulin curve type, matching profile.curve in JS.
public enum InsulinCurveType: String, Sendable {
    case bilinear
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"

    /// Resolve peak time in minutes, applying oref0's min/max constraints.
    ///
    /// JS calculate.js:
    ///   rapid-acting: peak 50-120, default 75
    ///   ultra-rapid: peak 35-100, default 55
    func resolvedPeak(userPeak: Double? = nil) -> Double {
        switch self {
        case .bilinear:
            return 75.0
        case .rapidActing:
            guard let p = userPeak else { return 75.0 }
            return min(120, max(50, p))
        case .ultraRapid:
            guard let p = userPeak else { return 55.0 }
            return min(100, max(35, p))
        }
    }
}
