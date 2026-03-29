// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ContinuancePolicy.swift
// T1PalAlgorithm
//
// Factors out "continuance rules" from dosing algorithms. These rules decide
// whether to actually command the pump or keep the current temp basal running,
// optimizing for battery, RF transmissions, and reduced beeping/vibration.
//
// Ported from oref0/lib/determine-basal/determine-basal.js (7 rules) and
// oref0/lib/basal-set-temp.js (1 rule). The algorithm calculates what rate
// it *wants*; ContinuancePolicy decides if we *bother telling the pump*.
//
// Architecture: docs/architecture/algorithm-convergence-backlog.md
// Trace: GAP-ALG-001 (continuance rule divergence)

import Foundation

// MARK: - Protocol

/// Decides whether a suggested temp basal change is worth commanding
/// the pump, or whether the current temp is "close enough."
///
/// This separates algorithm *intent* (what rate it computed) from
/// *operational* decisions (RF cost, battery, beeping).
public protocol ContinuancePolicy: Sendable {
    func evaluate(
        suggested: SuggestedBasal,
        current: CurrentTempState,
        profile: BasalRoundingProfile
    ) -> ContinuanceDecision
}

// MARK: - Input Types

/// What the algorithm wants to set.
public struct SuggestedBasal: Sendable {
    /// Desired rate in U/hr (nil means algorithm has no opinion)
    public let rate: Double?
    /// Desired duration in minutes
    public let duration: Int
    /// The scheduled (profile) basal rate
    public let scheduledBasal: Double

    public init(rate: Double?, duration: Int = 30, scheduledBasal: Double) {
        self.rate = rate
        self.duration = duration
        self.scheduledBasal = scheduledBasal
    }
}

/// What the pump is currently doing.
public struct CurrentTempState: Sendable {
    /// Current temp basal rate in U/hr (nil if no temp active)
    public let rate: Double?
    /// Remaining duration in minutes (0 if no temp active)
    public let remainingMinutes: Double

    public init(rate: Double?, remainingMinutes: Double) {
        self.rate = rate
        self.remainingMinutes = remainingMinutes
    }

    /// No temp basal is active.
    public static let none = CurrentTempState(rate: nil, remainingMinutes: 0)

    /// Whether a temp basal is currently active.
    public var isActive: Bool {
        rate != nil && remainingMinutes > 0
    }
}

/// Pump-specific rounding parameters for basal rate comparison.
public struct BasalRoundingProfile: Sendable {
    /// Pump model identifier (e.g., "554" for x54 pumps with finer resolution)
    public let pumpModel: String?
    /// Whether to skip neutral temps (cancel instead of re-issue)
    public let skipNeutralTemps: Bool
    /// Current time (for skip-at-55-minutes logic)
    public let currentTime: Date?

    public init(
        pumpModel: String? = nil,
        skipNeutralTemps: Bool = false,
        currentTime: Date? = nil
    ) {
        self.pumpModel = pumpModel
        self.skipNeutralTemps = skipNeutralTemps
        self.currentTime = currentTime
    }
}

// MARK: - Decision

/// The result of evaluating continuance rules.
public enum ContinuanceDecision: Sendable {
    /// Keep the current temp running — no pump command needed.
    case `continue`(reason: String)
    /// Issue a new temp basal command.
    case change(rate: Double, duration: Int, reason: String)
    /// Cancel the current temp (set rate=0, duration=0).
    case cancel(reason: String)
}

// MARK: - Basal Rounding (ported from oref0/lib/round-basal.js)

/// Round a basal rate to pump-deliverable precision.
///
/// Matches oref0 `round_basal(value, profile)`:
/// - x23/x54 pumps: 0.025 U/hr for rates < 1, 0.05 for 1-10, 0.1 for >10
/// - Other pumps: 0.05 U/hr for rates < 1, 0.05 for 1-10, 0.1 for >10
public func roundBasal(_ rate: Double, profile: BasalRoundingProfile) -> Double {
    let lowestRateScale: Double
    if let model = profile.pumpModel,
       model.hasSuffix("54") || model.hasSuffix("23") {
        lowestRateScale = 40  // 0.025 U/hr precision
    } else {
        lowestRateScale = 20  // 0.05 U/hr precision
    }

    if rate < 1 {
        return (rate * lowestRateScale).rounded() / lowestRateScale
    } else if rate < 10 {
        return (rate * 20).rounded() / 20
    } else {
        return (rate * 10).rounded() / 10
    }
}

// MARK: - oref0 Continuance Policy

/// Implements the 8 continuance rules from oref0 determine-basal + setTempBasal.
///
/// These rules exist to reduce unnecessary pump commands when the current
/// temp is "close enough" to what the algorithm wants. Each rule is
/// documented with its origin line number in determine-basal.js.
public struct Oref0ContinuancePolicy: ContinuancePolicy, Sendable {

    public init() {}

    public func evaluate(
        suggested: SuggestedBasal,
        current: CurrentTempState,
        profile: BasalRoundingProfile
    ) -> ContinuanceDecision {

        guard let suggestedRate = suggested.rate else {
            // Algorithm returned no rate — no action needed
            return .continue(reason: "no rate suggested")
        }

        let basal = suggested.scheduledBasal

        // --- Skip neutral temps near top of hour ---
        // Origin: determine-basal.js:925
        // "reduce beeping/vibration" near the hour boundary
        if profile.skipNeutralTemps,
           let time = profile.currentTime {
            let minute = Calendar.current.component(.minute, from: time)
            if minute >= 55 {
                return .cancel(reason: "Canceling temp at \(minute)m past the hour")
            }
        }

        // --- setTempBasal ±20% rule ---
        // Origin: basal-set-temp.js:32-35
        // "Xm left and X ~ req Y U/hr: no temp required"
        //
        // If the suggested rate is within ±20% of the current rate AND the
        // current temp has enough duration remaining, keep the current temp.
        if let currentRate = current.rate,
           current.remainingMinutes > Double(suggested.duration - 10),
           current.remainingMinutes <= 120 {
            let roundedSuggested = roundBasal(suggestedRate, profile: profile)
            if roundedSuggested <= currentRate * 1.2,
               roundedSuggested >= currentRate * 0.8,
               suggested.duration > 0 {
                let reason = "\(Int(current.remainingMinutes))m left and "
                    + "\(formatRate(currentRate)) ~ req \(formatRate(roundedSuggested))U/hr: no temp required"
                return .continue(reason: reason)
            }
        }

        // --- Neutral temp continuance (duration > 15, rate ≈ basal) ---
        // Origin: determine-basal.js lines 946, 1018, 1032, 1049
        // Pattern: "temp X ~ req Y U/hr"
        //
        // When the algorithm wants approximately the scheduled basal AND
        // the pump is already running approximately the scheduled basal
        // with >15 min remaining, don't bother changing.
        let roundedBasal = roundBasal(basal, profile: profile)
        let roundedSuggested = roundBasal(suggestedRate, profile: profile)

        if current.remainingMinutes > 15,
           let currentRate = current.rate,
           roundBasal(currentRate, profile: profile) == roundedBasal,
           roundedSuggested == roundedBasal {
            let reason = "temp \(formatRate(currentRate)) ~ req \(formatRate(basal))U/hr"
            return .continue(reason: reason)
        }

        // --- Low-temp approximate continuance ---
        // Origin: determine-basal.js:979-981
        // Pattern: "temp X ~< req Y U/hr"
        //
        // When the algorithm wants a low temp and the current temp is
        // within 80% of the suggested rate with >5 min remaining.
        if let currentRate = current.rate,
           current.remainingMinutes > 5,
           suggestedRate < basal,
           suggestedRate >= currentRate * 0.8 {
            let reason = "temp \(formatRate(currentRate)) ~< req \(formatRate(suggestedRate))U/hr"
            return .continue(reason: reason)
        }

        // --- High-temp approximate continuance ---
        // Origin: determine-basal.js:1180-1182
        // Pattern: "temp X >~ req Y U/hr"
        //
        // When the algorithm wants a high temp and the current temp is
        // already delivering at least as much, with >5 min remaining.
        if let currentRate = current.rate,
           current.remainingMinutes > 5,
           suggestedRate > basal,
           roundedSuggested <= roundBasal(currentRate, profile: profile) {
            let reason = "temp \(formatRate(currentRate)) >~ req \(formatRate(suggestedRate))U/hr"
            return .continue(reason: reason)
        }

        // --- Skip neutral temp when already at profile basal ---
        // Origin: basal-set-temp.js:37-47
        if roundedSuggested == roundedBasal, profile.skipNeutralTemps {
            if current.isActive {
                return .cancel(reason: "Suggested rate is same as profile rate, canceling current temp")
            } else {
                return .continue(reason: "Suggested rate is same as profile rate, no temp active, doing nothing")
            }
        }

        // --- No continuance rule matched: issue the command ---
        let clampedRate = max(0, suggestedRate)
        let roundedRate = roundBasal(clampedRate, profile: profile)
        return .change(
            rate: roundedRate,
            duration: suggested.duration,
            reason: "setting \(formatRate(roundedRate))U/hr for \(suggested.duration)m"
        )
    }

    private func formatRate(_ rate: Double) -> String {
        String(format: "%.2f", rate)
    }
}

// MARK: - Passthrough Policy

/// A no-op policy that always issues the pump command.
/// Useful for testing the algorithm's raw output without continuance filtering.
public struct PassthroughContinuancePolicy: ContinuancePolicy, Sendable {
    public init() {}

    public func evaluate(
        suggested: SuggestedBasal,
        current: CurrentTempState,
        profile: BasalRoundingProfile
    ) -> ContinuanceDecision {
        guard let rate = suggested.rate else {
            return .continue(reason: "no rate suggested")
        }
        return .change(
            rate: max(0, rate),
            duration: suggested.duration,
            reason: "passthrough: \(String(format: "%.2f", rate))U/hr"
        )
    }
}
