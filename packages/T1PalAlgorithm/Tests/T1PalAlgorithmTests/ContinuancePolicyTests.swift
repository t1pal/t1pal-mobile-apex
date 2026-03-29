// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ContinuancePolicyTests.swift
// T1PalAlgorithmTests
//
// Tests for ContinuancePolicy protocol, Oref0ContinuancePolicy (8 rules),
// PassthroughContinuancePolicy, and roundBasal pump-model rounding.
// Trace: GAP-ALG-001 (continuance rule divergence)

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Helpers

/// Extract the associated reason string from any ContinuanceDecision variant.
private func reason(of decision: ContinuanceDecision) -> String {
    switch decision {
    case .continue(let r): return r
    case .change(_, _, let r): return r
    case .cancel(let r): return r
    }
}

/// Assert that a decision is `.continue`.
private func expectContinue(
    _ decision: ContinuanceDecision,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .continue = decision { return }
    Issue.record("Expected .continue, got \(decision)", sourceLocation: sourceLocation)
}

/// Assert that a decision is `.change`.
private func expectChange(
    _ decision: ContinuanceDecision,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .change = decision { return }
    Issue.record("Expected .change, got \(decision)", sourceLocation: sourceLocation)
}

/// Assert that a decision is `.cancel`.
private func expectCancel(
    _ decision: ContinuanceDecision,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .cancel = decision { return }
    Issue.record("Expected .cancel, got \(decision)", sourceLocation: sourceLocation)
}

// MARK: - Passthrough Policy

@Suite("PassthroughContinuancePolicy")
struct PassthroughContinuancePolicyTests {

    let policy = PassthroughContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Always returns .change when rate is provided")
    func alwaysChange() {
        let suggested = SuggestedBasal(rate: 1.5, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 1.5, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }

    @Test("Returns .continue when rate is nil")
    func nilRateContinues() {
        let suggested = SuggestedBasal(rate: nil, scheduledBasal: 1.0)
        let decision = policy.evaluate(suggested: suggested, current: .none, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains("no rate"))
    }

    @Test("Clamps negative rate to zero")
    func clampsNegativeRate() {
        let suggested = SuggestedBasal(rate: -0.5, duration: 30, scheduledBasal: 1.0)
        let decision = policy.evaluate(suggested: suggested, current: .none, profile: profile)
        if case .change(let rate, _, _) = decision {
            #expect(rate == 0.0)
        } else {
            Issue.record("Expected .change")
        }
    }
}

// MARK: - Oref0 ±20% Tolerance Rule

@Suite("Oref0 ±20% Tolerance Rule")
struct PlusMinus20PercentTests {

    let policy = Oref0ContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Continue when suggested within +20% of current and enough duration remaining")
    func withinUpperBound() {
        // current = 1.0, suggested = 1.15 (within 1.0*1.2 = 1.2)
        // remaining 25 > duration-10 = 20, and <= 120
        let suggested = SuggestedBasal(rate: 1.15, duration: 30, scheduledBasal: 2.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains("no temp required"))
    }

    @Test("Continue when suggested within -20% of current")
    func withinLowerBound() {
        // current = 1.0, suggested = 0.85 (>= 1.0*0.8 = 0.8)
        let suggested = SuggestedBasal(rate: 0.85, duration: 30, scheduledBasal: 2.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectContinue(decision)
    }

    @Test("Change when suggested exceeds +20% of current")
    func exceedsUpperBound() {
        // current = 1.0, suggested = 1.5 (> 1.0*1.2 = 1.2), basal = 1.0
        // Low-tolerance won't fire (suggested >= basal).
        // High-tolerance won't fire (round(1.5) > round(1.0)).
        let suggested = SuggestedBasal(rate: 1.5, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }

    @Test("Change when remaining minutes too low")
    func insufficientDuration() {
        // Rate is within ±20% but remaining 15 is NOT > duration-10=20.
        // basal = 1.0, suggested = 1.0: not low-temp, not high-temp.
        // skipNeutralTemps = false so skip-neutral rule won't fire.
        let suggested = SuggestedBasal(rate: 1.0, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 15)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }
}

// MARK: - Oref0 Neutral Near Basal Rule

@Suite("Oref0 Neutral Near Basal Rule")
struct NeutralNearBasalTests {

    let policy = Oref0ContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Continue when current ≈ basal AND suggested ≈ basal AND remaining > 15")
    func neutralContinuance() {
        let basal = 1.0
        // Both current and suggested round to basal
        let suggested = SuggestedBasal(rate: 1.02, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 20)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains("~ req"))
    }

    @Test("Change when remaining ≤ 15 minutes")
    func insufficientDuration() {
        let basal = 1.0
        let suggested = SuggestedBasal(rate: 1.0, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        // remaining 10 is not > 15, so neutral rule won't fire
        // Falls through — may hit skip-neutral or change
        let r = reason(of: decision)
        #expect(!r.contains("temp 1.00 ~ req"))
    }

    @Test("Change when suggested differs from basal")
    func suggestedDiffersFromBasal() {
        let basal = 1.0
        let suggested = SuggestedBasal(rate: 2.0, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 20)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }
}

// MARK: - Oref0 Low Tolerance Rule

@Suite("Oref0 Low Tolerance Rule")
struct LowToleranceTests {

    let policy = Oref0ContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Continue when suggested is low temp within 80% of current")
    func lowTempApproximate() {
        let basal = 1.0
        // suggested 0.45 < basal 1.0, suggested >= current*0.8 = 0.4, remaining > 5
        let suggested = SuggestedBasal(rate: 0.45, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 0.5, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains("~<"))
    }

    @Test("Change when suggested is below 80% of current")
    func belowThreshold() {
        let basal = 1.0
        // suggested 0.3 < current*0.8 = 0.4
        let suggested = SuggestedBasal(rate: 0.3, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 0.5, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }

    @Test("Does not fire when suggested >= basal")
    func notLowTemp() {
        let basal = 1.0
        // suggested 1.5 is NOT < basal, so low-temp rule won't fire
        let suggested = SuggestedBasal(rate: 1.5, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 1.5, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        // May match high-tolerance or ±20%, but not low-tolerance
        let r = reason(of: decision)
        #expect(!r.contains("~<"))
    }
}

// MARK: - Oref0 High Tolerance Rule

@Suite("Oref0 High Tolerance Rule")
struct HighToleranceTests {

    let policy = Oref0ContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Continue when rounded suggested ≤ rounded current for high temp")
    func highTempApproximate() {
        let basal = 1.0
        // suggested 2.5 > basal, roundBasal(2.5)=2.5, current=2.6, roundBasal(2.6)=2.6
        // 2.5 <= 2.6 → continue
        let suggested = SuggestedBasal(rate: 2.5, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 2.6, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains(">~"))
    }

    @Test("Change when rounded suggested > rounded current for high temp")
    func suggestedExceedsCurrent() {
        let basal = 1.0
        // suggested 3.0 > basal, current 2.0 → round(3.0)=3.0 > round(2.0)=2.0
        let suggested = SuggestedBasal(rate: 3.0, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 2.0, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }

    @Test("Does not fire when suggested <= basal")
    func notHighTemp() {
        let basal = 2.0
        let suggested = SuggestedBasal(rate: 1.5, duration: 30, scheduledBasal: basal)
        let current = CurrentTempState(rate: 1.8, remainingMinutes: 10)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        let r = reason(of: decision)
        #expect(!r.contains(">~"))
    }
}

// MARK: - Oref0 Skip at :55 Rule

@Suite("Oref0 Skip at :55 Rule")
struct SkipAt55Tests {

    let policy = Oref0ContinuancePolicy()

    /// Create a Date with a specific minute component.
    private func dateWithMinute(_ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 7
        components.day = 11
        components.hour = 14
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    @Test("Cancel when minute >= 55 and skipNeutralTemps is true")
    func cancelAtMinute55() {
        let profile = BasalRoundingProfile(
            skipNeutralTemps: true,
            currentTime: dateWithMinute(55)
        )
        let suggested = SuggestedBasal(rate: 1.0, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 20)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectCancel(decision)
        #expect(reason(of: decision).contains("55"))
    }

    @Test("Cancel at minute 59")
    func cancelAtMinute59() {
        let profile = BasalRoundingProfile(
            skipNeutralTemps: true,
            currentTime: dateWithMinute(59)
        )
        let suggested = SuggestedBasal(rate: 2.0, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 1.0, remainingMinutes: 20)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectCancel(decision)
    }

    @Test("No cancel at minute 54 even with skipNeutralTemps")
    func noCancelAt54() {
        let profile = BasalRoundingProfile(
            skipNeutralTemps: true,
            currentTime: dateWithMinute(54)
        )
        let suggested = SuggestedBasal(rate: 2.0, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 2.0, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        let r = reason(of: decision)
        #expect(!r.contains("Canceling temp"))
    }

    @Test("No cancel when skipNeutralTemps is false")
    func skipDisabled() {
        let profile = BasalRoundingProfile(
            skipNeutralTemps: false,
            currentTime: dateWithMinute(57)
        )
        let suggested = SuggestedBasal(rate: 2.0, duration: 30, scheduledBasal: 1.0)
        let current = CurrentTempState(rate: 2.0, remainingMinutes: 25)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        let r = reason(of: decision)
        #expect(!r.contains("Canceling temp"))
    }
}

// MARK: - Oref0 No Temp Active Rule

@Suite("Oref0 No Temp Active Rule")
struct NoTempActiveTests {

    let policy = Oref0ContinuancePolicy()
    let profile = BasalRoundingProfile()

    @Test("Change when no temp is running")
    func noTempAlwaysChanges() {
        let suggested = SuggestedBasal(rate: 1.5, duration: 30, scheduledBasal: 1.0)
        let decision = policy.evaluate(suggested: suggested, current: .none, profile: profile)
        expectChange(decision)
    }

    @Test("Change when current rate is nil")
    func nilRateAlwaysChanges() {
        let current = CurrentTempState(rate: nil, remainingMinutes: 0)
        let suggested = SuggestedBasal(rate: 0.5, duration: 30, scheduledBasal: 1.0)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectChange(decision)
    }

    @Test("Continue returned for nil suggested rate even with no temp")
    func nilSuggestedRate() {
        let suggested = SuggestedBasal(rate: nil, scheduledBasal: 1.0)
        let decision = policy.evaluate(suggested: suggested, current: .none, profile: profile)
        expectContinue(decision)
    }
}

// MARK: - Oref0 Skip Neutral Temp Rule

@Suite("Oref0 Skip Neutral Temp Rule")
struct SkipNeutralTempTests {

    let policy = Oref0ContinuancePolicy()

    @Test("Cancel when suggested equals basal, temp active, skipNeutralTemps on")
    func cancelNeutralTemp() {
        let profile = BasalRoundingProfile(skipNeutralTemps: true)
        let basal = 1.0
        let suggested = SuggestedBasal(rate: basal, duration: 30, scheduledBasal: basal)
        // Use remaining 5 so earlier rules don't fire (neutral requires >15)
        let current = CurrentTempState(rate: 0.5, remainingMinutes: 5)
        let decision = policy.evaluate(suggested: suggested, current: current, profile: profile)
        expectCancel(decision)
        #expect(reason(of: decision).contains("same as profile rate"))
    }

    @Test("Continue doing nothing when suggested equals basal, no temp active, skipNeutralTemps on")
    func continueNeutralNoTemp() {
        let profile = BasalRoundingProfile(skipNeutralTemps: true)
        let basal = 1.0
        let suggested = SuggestedBasal(rate: basal, duration: 30, scheduledBasal: basal)
        let decision = policy.evaluate(suggested: suggested, current: .none, profile: profile)
        expectContinue(decision)
        #expect(reason(of: decision).contains("doing nothing"))
    }
}

// MARK: - roundBasal Pump-Model Rounding

@Suite("roundBasal Pump-Model Rounding")
struct RoundBasalTests {

    @Test("Standard pump rounds rates < 1 to 0.05 increments")
    func standardPumpLowRate() {
        let profile = BasalRoundingProfile()
        // 0.123 * 20 = 2.46, rounded = 2, / 20 = 0.10
        #expect(roundBasal(0.123, profile: profile) == 0.10)
        // 0.075 * 20 = 1.5, rounded = 2, / 20 = 0.10
        #expect(roundBasal(0.075, profile: profile) == 0.10)
        // 0.025 * 20 = 0.5, rounded = 1 (away from zero), / 20 = 0.05
        #expect(roundBasal(0.025, profile: profile) == 0.05)
    }

    @Test("x54 pump rounds rates < 1 to 0.025 increments")
    func x54PumpLowRate() {
        let profile = BasalRoundingProfile(pumpModel: "554")
        // 0.123 * 40 = 4.92, rounded = 5, / 40 = 0.125
        #expect(roundBasal(0.123, profile: profile) == 0.125)
        // 0.0125 * 40 = 0.5, rounded = 1 (away from zero), / 40 = 0.025
        #expect(roundBasal(0.0125, profile: profile) == 0.025)
    }

    @Test("x23 pump also gets 0.025 precision")
    func x23PumpLowRate() {
        let profile = BasalRoundingProfile(pumpModel: "723")
        #expect(roundBasal(0.123, profile: profile) == 0.125)
    }

    @Test("Rates 1-10 round to 0.05 for all pumps")
    func midRangeRounding() {
        let standard = BasalRoundingProfile()
        let x54 = BasalRoundingProfile(pumpModel: "554")
        // 1.123 * 20 = 22.46, rounded = 22, / 20 = 1.10
        #expect(roundBasal(1.123, profile: standard) == 1.10)
        #expect(roundBasal(1.123, profile: x54) == 1.10)
        // 5.025 * 20 = 100.5, rounded = 101 (away from zero), / 20 = 5.05
        #expect(roundBasal(5.025, profile: standard) == 5.05)
    }

    @Test("Rates > 10 round to 0.1 for all pumps")
    func highRateRounding() {
        let profile = BasalRoundingProfile()
        // 10.55 * 10 = 105.5, rounded = 106 (banker's rounds up here), / 10 = 10.6
        #expect(roundBasal(10.55, profile: profile) == 10.6)
        // 15.04 * 10 = 150.4, rounded = 150, / 10 = 15.0
        #expect(roundBasal(15.04, profile: profile) == 15.0)
    }

    @Test("Zero rate remains zero")
    func zeroRate() {
        let profile = BasalRoundingProfile()
        #expect(roundBasal(0.0, profile: profile) == 0.0)
    }
}
