// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DetermineBasal.swift
// T1Pal Mobile
//
// oref0-style determine-basal algorithm
// Requirements: REQ-AID-002
//
// Based on oref0/lib/determine-basal/determine-basal.js
// https://github.com/openaps/oref0

import Foundation
import T1PalCore

// MARK: - Algorithm State

/// Current algorithm state for determine-basal
public struct AlgorithmState: Codable, Sendable {
    public let glucose: Double           // Current BG (mg/dL)
    public let glucoseDelta: Double      // Change from previous reading
    public let shortAvgDelta: Double     // Average delta over last 15 min
    public let longAvgDelta: Double      // Average delta over last 45 min
    public let iob: Double               // Current IOB (U)
    public let cob: Double               // Current COB (g)
    public let eventualBG: Double        // Predicted eventual BG
    public let minPredBG: Double         // Minimum predicted BG
    public let tick: String              // Trend indicator
    
    public init(
        glucose: Double,
        glucoseDelta: Double = 0,
        shortAvgDelta: Double = 0,
        longAvgDelta: Double = 0,
        iob: Double = 0,
        cob: Double = 0,
        eventualBG: Double = 0,
        minPredBG: Double = 0,
        tick: String = ""
    ) {
        self.glucose = glucose
        self.glucoseDelta = glucoseDelta
        self.shortAvgDelta = shortAvgDelta
        self.longAvgDelta = longAvgDelta
        self.iob = iob
        self.cob = cob
        self.eventualBG = eventualBG
        self.minPredBG = minPredBG
        self.tick = tick
    }
}

// MARK: - Determine Basal Output

/// Output from determine-basal calculation
public struct DetermineBasalOutput: Codable, Sendable {
    public let rate: Double?             // Suggested temp basal rate (U/hr)
    public let duration: Int?            // Duration in minutes
    public let reason: String            // Human-readable explanation
    public let eventualBG: Double        // Predicted eventual BG
    public let minPredBG: Double         // Minimum predicted BG
    public let iob: Double               // Current IOB
    public let cob: Double               // Current COB
    public let tick: String              // Trend indicator
    public let deliverAt: Date?          // When to deliver
    public let units: Double?            // SMB units (if applicable)
    
    public init(
        rate: Double? = nil,
        duration: Int? = nil,
        reason: String,
        eventualBG: Double = 0,
        minPredBG: Double = 0,
        iob: Double = 0,
        cob: Double = 0,
        tick: String = "",
        deliverAt: Date? = nil,
        units: Double? = nil
    ) {
        self.rate = rate
        self.duration = duration
        self.reason = reason
        self.eventualBG = eventualBG
        self.minPredBG = minPredBG
        self.iob = iob
        self.cob = cob
        self.tick = tick
        self.deliverAt = deliverAt
        self.units = units
    }
}

// MARK: - Determine Basal Algorithm

/// oref0-style determine-basal implementation
public struct DetermineBasal: Sendable {
    
    public init() {}
    
    /// Run determine-basal calculation
    /// - Parameters:
    ///   - glucose: Array of recent glucose readings (newest first)
    ///   - iob: Current insulin on board
    ///   - cob: Current carbs on board
    ///   - profile: Algorithm profile settings
    ///   - currentTemp: Current temp basal (if any)
    /// - Returns: Algorithm output with suggested action
    public func calculate(
        glucose: [GlucoseReading],
        iob: Double,
        cob: Double,
        profile: AlgorithmProfile,
        currentTemp: TempBasal? = nil
    ) -> DetermineBasalOutput {
        
        // Need at least 2 readings for delta
        guard glucose.count >= 2 else {
            return DetermineBasalOutput(reason: "Not enough glucose data")
        }
        
        let bg = glucose[0].glucose
        let bgTime = glucose[0].timestamp
        let lastBG = glucose[1].glucose
        
        // Calculate deltas
        let delta = bg - lastBG
        let shortAvgDelta = calculateShortAvgDelta(glucose)
        let longAvgDelta = calculateLongAvgDelta(glucose)
        
        // Get profile values
        let target = profile.currentTarget()
        let sens = profile.currentISF()
        let maxBasal = profile.maxBasal
        let maxIOB = profile.maxIOB
        let scheduledBasal = profile.currentBasal()
        
        // Calculate eventual BG
        let eventualBG = bg + (iob * sens * -1)  // IOB lowers BG
        let minPredBG = min(bg, eventualBG)
        
        // Tick indicator
        let tick = formatTick(delta)
        
        // Create state for logging
        _ = AlgorithmState(
            glucose: bg,
            glucoseDelta: delta,
            shortAvgDelta: shortAvgDelta,
            longAvgDelta: longAvgDelta,
            iob: iob,
            cob: cob,
            eventualBG: eventualBG,
            minPredBG: minPredBG,
            tick: tick
        )
        
        // Safety check: low glucose suspend
        if bg < 70 {
            return DetermineBasalOutput(
                rate: 0,
                duration: 30,
                reason: "BG \(Int(bg)) < 70, suspending",
                eventualBG: eventualBG,
                minPredBG: minPredBG,
                iob: iob,
                cob: cob,
                tick: tick,
                deliverAt: bgTime
            )
        }
        
        // Safety check: predicted low
        if minPredBG < 70 {
            return DetermineBasalOutput(
                rate: 0,
                duration: 30,
                reason: "minPredBG \(Int(minPredBG)) < 70, suspending",
                eventualBG: eventualBG,
                minPredBG: minPredBG,
                iob: iob,
                cob: cob,
                tick: tick,
                deliverAt: bgTime
            )
        }
        
        // Check IOB limit
        if iob >= maxIOB {
            return DetermineBasalOutput(
                rate: scheduledBasal,
                duration: 30,
                reason: "IOB \(String(format: "%.2f", iob)) >= maxIOB \(String(format: "%.2f", maxIOB))",
                eventualBG: eventualBG,
                minPredBG: minPredBG,
                iob: iob,
                cob: cob,
                tick: tick,
                deliverAt: bgTime
            )
        }
        
        // Calculate insulin needed
        let targetDiff = eventualBG - target
        let insulinRequired = targetDiff / sens
        
        // Calculate temp basal adjustment
        var suggestedRate: Double
        var reason: String
        
        if eventualBG > target + 10 {
            // Above target - increase basal
            let extraInsulin = insulinRequired - iob
            let extraRate = extraInsulin * 2  // Deliver over 30 min
            suggestedRate = scheduledBasal + extraRate
            suggestedRate = min(suggestedRate, maxBasal)
            suggestedRate = max(suggestedRate, 0)
            
            reason = "eventualBG \(Int(eventualBG)) > \(Int(target)), "
            reason += "insulinReq \(String(format: "%.2f", insulinRequired)), "
            reason += "rate \(String(format: "%.2f", suggestedRate))"
            
        } else if eventualBG < target - 10 {
            // Below target - reduce basal
            let reductionFactor = (target - eventualBG) / sens
            suggestedRate = scheduledBasal - reductionFactor
            suggestedRate = max(suggestedRate, 0)
            
            reason = "eventualBG \(Int(eventualBG)) < \(Int(target)), "
            reason += "reducing to \(String(format: "%.2f", suggestedRate))"
            
        } else {
            // Near target - return to scheduled basal
            suggestedRate = scheduledBasal
            reason = "eventualBG \(Int(eventualBG)) near target \(Int(target)), no change"
        }
        
        // Round rate to pump precision
        suggestedRate = round(suggestedRate * 20) / 20  // 0.05 U/hr precision
        
        return DetermineBasalOutput(
            rate: suggestedRate,
            duration: 30,
            reason: reason,
            eventualBG: eventualBG,
            minPredBG: minPredBG,
            iob: iob,
            cob: cob,
            tick: tick,
            deliverAt: bgTime
        )
    }
    
    // MARK: - Helper Functions
    
    private func calculateShortAvgDelta(_ glucose: [GlucoseReading]) -> Double {
        // Average delta over last 15 min (3 readings)
        guard glucose.count >= 4 else { return 0 }
        let deltas = (0..<3).map { glucose[$0].glucose - glucose[$0 + 1].glucose }
        return deltas.reduce(0, +) / Double(deltas.count)
    }
    
    private func calculateLongAvgDelta(_ glucose: [GlucoseReading]) -> Double {
        // Average delta over last 45 min (9 readings)
        guard glucose.count >= 10 else { return calculateShortAvgDelta(glucose) }
        let deltas = (0..<9).map { glucose[$0].glucose - glucose[$0 + 1].glucose }
        return deltas.reduce(0, +) / Double(deltas.count)
    }
    
    private func formatTick(_ delta: Double) -> String {
        if delta > 4 { return "+\(Int(delta))" }
        if delta > 2 { return "+" }
        if delta < -4 { return "\(Int(delta))" }
        if delta < -2 { return "-" }
        return "~"
    }
}

// MARK: - Algorithm Engine Implementation

/// oref0-compatible algorithm engine
/// Stateless and immutable - inherently Sendable
public struct Oref0Algorithm: AlgorithmEngine, Sendable {
    public let name = "oref0"
    public let version = "0.2.0"
    
    public let capabilities = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: false,  // oref0 doesn't have SMB - that's oref1
        supportsUAM: false,
        supportsDynamicISF: false,
        supportsAutosens: true,
        providesPredictions: true,
        minGlucoseHistory: 3,
        recommendedGlucoseHistory: 36,
        origin: .oref0
    )
    
    private let determineBasal = DetermineBasal()
    private let insulinModel: InsulinModel
    private let iobCalculator: IOBCalculator
    private let cobCalculator: COBCalculator

    /// Continuance policy applied after algorithm calculation.
    /// Determines whether to actually command the pump or keep the current temp.
    /// Use `PassthroughContinuancePolicy()` to disable continuance filtering.
    public let continuancePolicy: any ContinuancePolicy
    
    public init(
        insulinType: InsulinType = .humalog,
        continuancePolicy: (any ContinuancePolicy)? = nil
    ) {
        self.insulinModel = InsulinModel(insulinType: insulinType)
        self.iobCalculator = IOBCalculator(model: insulinModel)
        self.cobCalculator = COBCalculator()
        self.continuancePolicy = continuancePolicy ?? Oref0ContinuancePolicy()
    }
    
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        var profile = createAlgorithmProfile(from: inputs.profile)
        
        // Apply active override if present and not expired (ALG-PARITY-004)
        if let override = inputs.activeOverride,
           override.isActive,
           !override.isExpired(at: inputs.currentTime) {
            profile = applyOverride(override, to: profile)
        }
        
        // Apply effect modifiers (autosens ratio, activity agents, etc.)
        if let modifiers = inputs.effectModifiers, !modifiers.isEmpty {
            let composed = EffectModifier.compose(modifiers)
            profile = applyEffectModifier(composed, to: profile)
        }
        
        // Generate prediction curves using PredictionEngine
        let glucoseDelta: Double
        let shortAvgDelta: Double
        let longAvgDelta: Double
        // Use pre-computed deltas from input when available (from CGM glucose_status).
        // Fall back to computing from glucose history when not provided.
        if let inputDelta = inputs.glucoseDelta {
            glucoseDelta = inputDelta
            shortAvgDelta = inputs.shortAvgDelta ?? inputDelta
            longAvgDelta = inputs.longAvgDelta ?? inputs.shortAvgDelta ?? inputDelta
        } else if inputs.glucose.count >= 2 {
            glucoseDelta = inputs.glucose[0].glucose - inputs.glucose[1].glucose
            // shortAvgDelta: average of last 3 deltas (15 min)
            if inputs.glucose.count >= 4 {
                let deltas = (0..<3).map { inputs.glucose[$0].glucose - inputs.glucose[$0 + 1].glucose }
                shortAvgDelta = deltas.reduce(0, +) / Double(deltas.count)
            } else {
                shortAvgDelta = glucoseDelta
            }
            // longAvgDelta: average of last 9 deltas (45 min)
            if inputs.glucose.count >= 10 {
                let deltas = (0..<9).map { inputs.glucose[$0].glucose - inputs.glucose[$0 + 1].glucose }
                longAvgDelta = deltas.reduce(0, +) / Double(deltas.count)
            } else {
                longAvgDelta = shortAvgDelta
            }
        } else {
            glucoseDelta = 0
            shortAvgDelta = 0
            longAvgDelta = 0
        }
        // minDelta: match JS determine-basal.js:164-165
        // JS: minDelta = min(delta, short_avgdelta); minAvgDelta = min(short_avgdelta, long_avgdelta)
        let minDelta = min(glucoseDelta, shortAvgDelta)
        let minAvgDelta = min(shortAvgDelta, longAvgDelta)
        
        let predictionEngine = PredictionEngine(predictionMinutes: 240, intervalMinutes: 5)
        let predResult = predictionEngine.predict(
            currentGlucose: inputs.glucose.first?.glucose ?? 0,
            glucoseDelta: glucoseDelta,
            iob: inputs.insulinOnBoard,
            cob: inputs.carbsOnBoard,
            profile: profile,
            insulinModel: insulinModel,
            insulinActivity: inputs.insulinActivity,
            iobWithZeroTemp: inputs.iobWithZeroTemp,
            iobWithZeroTempActivity: inputs.iobWithZeroTempActivity
        )
        let predictions = predResult.toGlucosePredictions()
        
        // Derive guards and safety values from prediction curves
        let target = profile.currentTarget()
        // JS rounds sens to 1 decimal when autosens is active (determine-basal.js:340)
        // Even with ratio=1.0, JS does: sens = round(profile.sens / sensitivityRatio, 1)
        let sens = profile.currentISF().rounded(toPlaces: 1)
        let maxBasal = profile.maxBasal
        let maxIOB = profile.maxIOB
        let scheduledBasal = profile.currentBasal()
        let bg = inputs.glucose.first?.glucose ?? 0
        let targetRange = profile.currentTargetRange()
        let minBG = targetRange.low
        let maxBG = targetRange.high
        let tau = insulinModel.dia * 60.0 / 1.85
        let resolvedActivity = inputs.insulinActivity ?? (inputs.insulinOnBoard / tau)
        // bgi rounded to 2 decimals matching JS: round(-activity * sens * 5, 2)
        let bgi = (-resolvedActivity * sens * 5).rounded(toPlaces: 2)
        
        // EventualBG: match JS oref0 formula (determine-basal.js:394-417)
        // naive_eventualBG = round(bg - iob * sens)
        // deviation = round(30/5 * (minDelta - bgi)), cascade to less conservative if negative
        // eventualBG = naive_eventualBG + deviation
        let rawSens = Double(inputs.profile.currentISF)  // pre-modifier ISF
        let naiveEventualBG: Double
        if inputs.insulinOnBoard > 0 {
            naiveEventualBG = (bg - inputs.insulinOnBoard * sens).rounded()
        } else {
            naiveEventualBG = (bg - inputs.insulinOnBoard * min(sens, rawSens)).rounded()
        }
        // JS deviation cascade: minDelta → minAvgDelta → longAvgDelta
        var deviation = (6.0 * (minDelta - bgi)).rounded()
        if deviation < 0 {
            deviation = (6.0 * (minAvgDelta - bgi)).rounded()
            if deviation < 0 {
                deviation = (6.0 * (longAvgDelta - bgi)).rounded()
            }
        }
        let eventualBG = naiveEventualBG + deviation
        
        // Build guard system matching JS oref0 logic
        let guards = GuardSystem(
            predictions: predResult,
            bg: bg,
            minBG: minBG,
            maxBG: maxBG,
            targetBG: target,
            eventualBG: eventualBG,
            bgi: bgi,
            hasCOB: inputs.carbsOnBoard > 0,
            enableUAM: false,  // oref0 doesn't have UAM (that's oref1)
            hasCarbs: inputs.carbsOnBoard > 0,
            fractionCarbsLeft: 1.0
        )
        
        let threshold = guards.threshold
        let expectedDelta = guards.expectedDelta
        let minPredBG = guards.minPredBG
        let minGuardBG = guards.minGuardBG
        
        var suggestedRate: Double
        var reason: String
        var duration: Int = 30  // default 30m duration
        
        // ---- Core dosing logic matching JS determine-basal.js:908-1060 ----
        
        // LGS exception: don't suspend if IOB is very negative and BG rising faster than expected
        // Origin: determine-basal.js:908-910
        if bg < threshold
            && inputs.insulinOnBoard < -scheduledBasal * 20.0 / 60.0
            && minDelta > 0
            && minDelta > expectedDelta {
            suggestedRate = scheduledBasal
            reason = "IOB \(String(format: "%.2f", inputs.insulinOnBoard)) < "
            reason += "\(String(format: "%.2f", -scheduledBasal * 20.0 / 60.0))"
            reason += " and minDelta \(String(format: "%.1f", minDelta)) > expectedDelta \(String(format: "%.1f", expectedDelta))"
        }
        // Predictive low glucose suspend
        // Origin: determine-basal.js:912-920
        else if bg < threshold || minGuardBG < threshold {
            let bgUndershoot = target - minGuardBG
            let worstCaseInsulinReq = bgUndershoot / sens
            var durationReq = Int((60.0 * worstCaseInsulinReq / scheduledBasal).rounded())
            durationReq = (durationReq / 30) * 30  // round to 30m
            durationReq = min(120, max(30, durationReq))
            
            suggestedRate = 0
            duration = durationReq
            reason = "minGuardBG \(Int(minGuardBG)) < threshold \(Int(threshold)), suspending \(durationReq)m"
        }
        // EventualBG below min_bg
        // Origin: determine-basal.js:931+
        else if eventualBG < minBG {
            // If rising faster than expected, just set basal
            if minDelta > expectedDelta && minDelta > 0 {
                suggestedRate = scheduledBasal
                reason = "eventualBG \(Int(eventualBG)) < \(Int(minBG))"
                reason += " but minDelta \(String(format: "%.1f", minDelta)) > expectedDelta \(String(format: "%.1f", expectedDelta))"
                reason += "; setting basal"
            } else {
                // Calculate low temp to bring BG up
                var insulinReq = 2 * min(0, (eventualBG - target) / sens)
                // If barely falling, reduce insulinReq proportionally
                if minDelta < 0 && minDelta > expectedDelta && expectedDelta < 0 {
                    insulinReq = insulinReq * (minDelta / expectedDelta)
                }
                suggestedRate = scheduledBasal + (2 * insulinReq)
                suggestedRate = max(suggestedRate, 0)
                reason = "eventualBG \(Int(eventualBG)) < \(Int(minBG)), insulinReq \(String(format: "%.2f", insulinReq))"
            }
        }
        // Falling faster than expected
        // Origin: determine-basal.js:1006-1023
        else if minDelta < expectedDelta {
            suggestedRate = scheduledBasal
            reason = "eventualBG \(Int(eventualBG)) > \(Int(minBG))"
            reason += " but minDelta \(String(format: "%.1f", minDelta)) < expectedDelta \(String(format: "%.1f", expectedDelta))"
            reason += "; setting basal"
        }
        // In range (eventualBG or minPredBG below max_bg)
        // Origin: determine-basal.js:1025-1037
        else if min(eventualBG, minPredBG) < maxBG {
            suggestedRate = scheduledBasal
            reason = "\(Int(eventualBG))-\(Int(minPredBG)) in range: no temp required"
        }
        // IOB > maxIOB
        // Origin: determine-basal.js:1045-1053
        else if inputs.insulinOnBoard > maxIOB {
            suggestedRate = scheduledBasal
            reason = "IOB \(String(format: "%.2f", inputs.insulinOnBoard)) > maxIOB \(String(format: "%.2f", maxIOB)); setting basal"
        }
        // Above target: calculate high temp
        // Origin: determine-basal.js:1055-1070
        else {
            var insulinReq = (min(minPredBG, eventualBG) - target) / sens
            // Cap at maxIOB
            if insulinReq > maxIOB - inputs.insulinOnBoard {
                insulinReq = maxIOB - inputs.insulinOnBoard
            }
            suggestedRate = scheduledBasal + (2 * insulinReq)
            suggestedRate = min(suggestedRate, maxBasal)
            suggestedRate = max(suggestedRate, 0)
            reason = "eventualBG \(Int(eventualBG)) >= \(Int(maxBG))"
            reason += ", insulinReq \(String(format: "%.2f", insulinReq))"
            reason += ", rate \(String(format: "%.2f", suggestedRate))"
        }
        
        suggestedRate = roundBasal(suggestedRate, profile: BasalRoundingProfile(currentTime: inputs.currentTime))
        
        // Always include eventualBG in reason string (matches JS rT.eventualBG output).
        // The adapter parses this to get the formula-based eventualBG (naive + deviation),
        // which differs from the IOB prediction curve endpoint.
        if !reason.contains("eventualBG") {
            reason = "eventualBG \(Int(eventualBG)), " + reason
        }
        
        return AlgorithmDecision(
            timestamp: inputs.currentTime,
            suggestedTempBasal: TempBasal(rate: suggestedRate, duration: Double(duration) * 60),
            reason: reason,
            predictions: predictions
        )
    }
    
    /// Calculate with continuance filtering applied.
    ///
    /// Returns the raw algorithm decision plus the continuance evaluation.
    /// When continuance returns `.continue`, `suggestedTempBasal` will be nil
    /// in the returned decision (meaning "no pump command needed").
    public func calculateWithContinuance(
        _ inputs: AlgorithmInputs,
        currentTemp: CurrentTempState = .none
    ) throws -> (decision: AlgorithmDecision, continuance: ContinuanceDecision) {
        let rawDecision = try calculate(inputs)
        
        let profile = createAlgorithmProfile(from: inputs.profile)
        let scheduledBasal = profile.currentBasal(at: inputs.currentTime)
        
        let suggested = SuggestedBasal(
            rate: rawDecision.suggestedTempBasal?.rate,
            duration: rawDecision.suggestedTempBasal.map { Int($0.duration / 60) } ?? 30,
            scheduledBasal: scheduledBasal
        )
        
        let roundingProfile = BasalRoundingProfile(
            skipNeutralTemps: false,
            currentTime: inputs.currentTime
        )
        
        let continuance = continuancePolicy.evaluate(
            suggested: suggested,
            current: currentTemp,
            profile: roundingProfile
        )
        
        switch continuance {
        case .continue(let reason):
            return (
                decision: AlgorithmDecision(
                    timestamp: inputs.currentTime,
                    suggestedTempBasal: nil,
                    reason: rawDecision.reason + ", " + reason,
                    predictions: rawDecision.predictions
                ),
                continuance: continuance
            )
        case .cancel(let reason):
            return (
                decision: AlgorithmDecision(
                    timestamp: inputs.currentTime,
                    suggestedTempBasal: TempBasal(rate: 0, duration: 0),
                    reason: rawDecision.reason + ". " + reason,
                    predictions: rawDecision.predictions
                ),
                continuance: continuance
            )
        case .change(let rate, let duration, _):
            return (
                decision: AlgorithmDecision(
                    timestamp: inputs.currentTime,
                    suggestedTempBasal: TempBasal(rate: rate, duration: Double(duration) * 60),
                    reason: rawDecision.reason,
                    predictions: rawDecision.predictions
                ),
                continuance: continuance
            )
        }
    }
    
    /// Apply composed effect modifier (autosens, activity agents, etc.) to profile.
    /// Multiplies ISF, ICR, and basal schedules by the modifier's multipliers.
    private func applyEffectModifier(_ modifier: EffectModifier, to profile: AlgorithmProfile) -> AlgorithmProfile {
        let adjustedBasal = Schedule(entries: profile.basalSchedule.entries.map { entry in
            BasalScheduleEntry(startTime: entry.startTime, rate: entry.rate * modifier.basalMultiplier)
        })
        let adjustedISF = Schedule(entries: profile.isfSchedule.entries.map { entry in
            ISFScheduleEntry(startTime: entry.startTime, sensitivity: entry.sensitivity * modifier.isfMultiplier)
        })
        let adjustedICR = Schedule(entries: profile.icrSchedule.entries.map { entry in
            ICRScheduleEntry(startTime: entry.startTime, ratio: entry.ratio * modifier.crMultiplier)
        })
        return AlgorithmProfile(
            basalSchedule: adjustedBasal,
            isfSchedule: adjustedISF,
            icrSchedule: adjustedICR,
            targetSchedule: profile.targetSchedule,
            maxBasal: profile.maxBasal,
            maxIOB: profile.maxIOB
        )
    }
    
    /// Apply profile override to adjust ISF, CR, and basal rates
    private func applyOverride(_ override: ProfileOverride, to profile: AlgorithmProfile) -> AlgorithmProfile {
        // Adjust basal schedule
        let adjustedBasal: Schedule<BasalScheduleEntry>
        if override.adjustBasal {
            let adjustedEntries = profile.basalSchedule.entries.map { entry in
                BasalScheduleEntry(startTime: entry.startTime, rate: override.adjustedBasal(entry.rate))
            }
            adjustedBasal = Schedule(entries: adjustedEntries)
        } else {
            adjustedBasal = profile.basalSchedule
        }
        
        // Adjust ISF schedule
        let adjustedISF: Schedule<ISFScheduleEntry>
        if override.adjustISF {
            let adjustedEntries = profile.isfSchedule.entries.map { entry in
                ISFScheduleEntry(startTime: entry.startTime, sensitivity: override.adjustedISF(entry.sensitivity))
            }
            adjustedISF = Schedule(entries: adjustedEntries)
        } else {
            adjustedISF = profile.isfSchedule
        }
        
        // Adjust ICR schedule
        let adjustedICR: Schedule<ICRScheduleEntry>
        if override.adjustCR {
            let adjustedEntries = profile.icrSchedule.entries.map { entry in
                ICRScheduleEntry(startTime: entry.startTime, ratio: override.adjustedCR(entry.ratio))
            }
            adjustedICR = Schedule(entries: adjustedEntries)
        } else {
            adjustedICR = profile.icrSchedule
        }
        
        // Override target if specified
        let adjustedTarget: Schedule<TargetScheduleEntry>
        if let targetOverride = override.targetOverride {
            let adjustedEntries = [TargetScheduleEntry(startTime: 0, low: targetOverride, high: targetOverride)]
            adjustedTarget = Schedule(entries: adjustedEntries)
        } else {
            adjustedTarget = profile.targetSchedule
        }
        
        return AlgorithmProfile(
            basalSchedule: adjustedBasal,
            isfSchedule: adjustedISF,
            icrSchedule: adjustedICR,
            targetSchedule: adjustedTarget,
            maxBasal: profile.maxBasal,
            maxIOB: profile.maxIOB
        )
    }
    
    private func createAlgorithmProfile(from therapy: TherapyProfile) -> AlgorithmProfile {
        // Convert TherapyProfile to AlgorithmProfile
        let basalEntries = therapy.basalRates.map { rate in
            BasalScheduleEntry(startTime: rate.startTime, rate: rate.rate)
        }
        
        let isfEntries = therapy.sensitivityFactors.map { sf in
            ISFScheduleEntry(startTime: sf.startTime, sensitivity: sf.factor)
        }
        
        let icrEntries = therapy.carbRatios.map { cr in
            ICRScheduleEntry(startTime: cr.startTime, ratio: cr.ratio)
        }
        
        let targetEntries = [
            TargetScheduleEntry(
                startTime: 0,
                low: therapy.targetGlucose.low,
                high: therapy.targetGlucose.high
            )
        ]
        
        // Use explicit maxBasalRate if provided, otherwise derive from maxIOB
        let maxBasal = therapy.maxBasalRate ?? (therapy.maxIOB > 0 ? therapy.maxIOB / 2 : 2.0)
        
        return AlgorithmProfile(
            basalSchedule: Schedule(entries: basalEntries.isEmpty ? [BasalScheduleEntry(startTime: 0, rate: 1.0)] : basalEntries),
            isfSchedule: Schedule(entries: isfEntries.isEmpty ? [ISFScheduleEntry(startTime: 0, sensitivity: 50)] : isfEntries),
            icrSchedule: Schedule(entries: icrEntries.isEmpty ? [ICRScheduleEntry(startTime: 0, ratio: 10)] : icrEntries),
            targetSchedule: Schedule(entries: targetEntries),
            maxBasal: maxBasal,
            maxIOB: therapy.maxIOB > 0 ? therapy.maxIOB : 8.0
        )
    }
}
