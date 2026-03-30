// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Predictions.swift
// T1Pal Mobile
//
// Glucose prediction engine
// Requirements: REQ-AID-005
//
// Based on oref0 prediction curves:
// https://github.com/openaps/oref0/blob/master/lib/determine-basal/determine-basal.js

import Foundation
import T1PalCore

// MARK: - Prediction Types

/// Types of glucose predictions
public enum PredictionType: String, Codable, Sendable, CaseIterable {
    case zt = "ZT"     // Zero Temp: what happens if we stop all insulin
    case iob = "IOB"   // IOB only: effect of insulin on board
    case cob = "COB"   // COB: effect of carbs on board
    case uam = "UAM"   // Unannounced Meal: detect rising BG without announced carbs
}

// MARK: - Prediction Point

/// A single point in a prediction curve
public struct PredictionPoint: Codable, Sendable {
    public let minutesFromNow: Int
    public let glucose: Double
    
    public init(minutesFromNow: Int, glucose: Double) {
        self.minutesFromNow = minutesFromNow
        self.glucose = glucose
    }
}

// MARK: - Prediction Curve

/// A complete prediction curve
public struct PredictionCurve: Codable, Sendable {
    public let type: PredictionType
    public let points: [PredictionPoint]
    public let minValue: Double
    public let maxValue: Double
    public let eventualValue: Double
    
    public init(type: PredictionType, points: [PredictionPoint]) {
        self.type = type
        self.points = points
        self.minValue = points.map(\.glucose).min() ?? 0
        self.maxValue = points.map(\.glucose).max() ?? 0
        self.eventualValue = points.last?.glucose ?? 0
    }
    
    /// Get predicted glucose at a specific time
    public func glucose(atMinutes minutes: Int) -> Double? {
        points.first { $0.minutesFromNow == minutes }?.glucose
    }
}

// MARK: - COB Prediction Parameters

/// Parameters for JS-matching COB prediction curve.
///
/// Computed in DetermineBasal from glucose deltas, insulin effect, and meal data.
/// Passed to PredictionEngine.predictCOB for JS oref0 formula parity.
/// See oref0/lib/determine-basal/determine-basal.js lines 466-548.
public struct COBPredictionParams: Sendable {
    /// Carb impact: observed BG deviation minus insulin effect (mg/dL per 5m).
    /// JS: ci = round(minDelta - bgi, 1)
    public let ci: Double
    /// CI duration in 5-minute periods. How long ci lasts to cover all COB.
    /// JS: cid = min(remainingCATime*60/5/2, max(0, mealCOB*csf/ci))
    public let cid: Double
    /// Peak remaining CI for bilinear unobserved carb absorption (mg/dL per 5m).
    /// JS: remainingCIpeak = remainingCarbs * csf * 5/60 / (remainingCATime/2)
    public let remainingCIpeak: Double
    /// Remaining carb absorption time (hours).
    /// JS: min 3h, adjusted by carb amount and last carb age.
    public let remainingCATime: Double
    
    public init(ci: Double, cid: Double, remainingCIpeak: Double, remainingCATime: Double) {
        self.ci = ci
        self.cid = cid
        self.remainingCIpeak = remainingCIpeak
        self.remainingCATime = remainingCATime
    }
    
    /// Default params when no meal data: ci from observed deviation, everything else zero.
    public static func noCarbs(ci: Double) -> COBPredictionParams {
        COBPredictionParams(ci: ci, cid: 0, remainingCIpeak: 0, remainingCATime: 3.0)
    }
}

// MARK: - Prediction Result

/// Complete prediction results with all curves
public struct PredictionResult: Codable, Sendable {
    public let timestamp: Date
    public let currentGlucose: Double
    public let zt: PredictionCurve
    public let iob: PredictionCurve
    public let cob: PredictionCurve
    public let uam: PredictionCurve
    
    public init(
        timestamp: Date = Date(),
        currentGlucose: Double,
        zt: PredictionCurve,
        iob: PredictionCurve,
        cob: PredictionCurve,
        uam: PredictionCurve
    ) {
        self.timestamp = timestamp
        self.currentGlucose = currentGlucose
        self.zt = zt
        self.iob = iob
        self.cob = cob
        self.uam = uam
    }
    
    /// Minimum predicted BG across all curves
    public var minPredBG: Double {
        min(zt.minValue, iob.minValue, cob.minValue, uam.minValue)
    }
    
    /// Maximum predicted BG across all curves
    public var maxPredBG: Double {
        max(zt.maxValue, iob.maxValue, cob.maxValue, uam.maxValue)
    }
    
    /// Most likely eventual BG (uses IOB curve)
    public var eventualBG: Double {
        iob.eventualValue
    }
}

// MARK: - Prediction Engine

/// Engine for calculating glucose predictions
public struct PredictionEngine: Sendable {
    public let predictionMinutes: Int
    public let intervalMinutes: Int
    
    public init(predictionMinutes: Int = 180, intervalMinutes: Int = 5) {
        self.predictionMinutes = predictionMinutes
        self.intervalMinutes = intervalMinutes
    }
    
    /// Calculate all prediction curves
    public func predict(
        currentGlucose: Double,
        glucoseDelta: Double,
        iob: Double,
        cob: Double,
        profile: AlgorithmProfile,
        insulinModel: InsulinModel,
        carbModel: CarbModel = CarbModel(),
        insulinActivity: Double? = nil,
        iobWithZeroTemp: Double? = nil,
        iobWithZeroTempActivity: Double? = nil,
        cobParams: COBPredictionParams? = nil,
        ci: Double? = nil
    ) -> PredictionResult {
        let sens = profile.currentISF()
        _ = profile.currentTarget()  // target available for future use
        let scheduledBasal = profile.currentBasal()
        
        // Resolve activity: use provided value or fall back to IOB/tau approximation
        let tau = insulinModel.dia * 60.0 / 1.85
        let resolvedActivity = insulinActivity ?? (iob / tau)
        let resolvedZTActivity = iobWithZeroTempActivity ?? insulinActivity ?? (iob / tau)
        let resolvedZTIob = iobWithZeroTemp ?? iob
        
        // Calculate curves
        let ztCurve = predictZT(
            currentGlucose: currentGlucose,
            iobWithZeroTemp: resolvedZTIob,
            activity: resolvedZTActivity,
            sens: sens,
            insulinModel: insulinModel
        )
        
        let iobCurve = predictIOB(
            currentGlucose: currentGlucose,
            iob: iob,
            activity: resolvedActivity,
            sens: sens,
            insulinModel: insulinModel,
            ci: ci
        )
        
        let cobCurve: PredictionCurve
        if let params = cobParams {
            // Use JS-matching COB formula with explicit parameters
            cobCurve = predictCOBOref0(
                currentGlucose: currentGlucose,
                activity: resolvedActivity,
                sens: sens,
                insulinModel: insulinModel,
                cobParams: params
            )
        } else {
            cobCurve = predictCOB(
                currentGlucose: currentGlucose,
                iob: iob,
                activity: resolvedActivity,
                cob: cob,
                sens: sens,
                icr: profile.currentICR(),
                insulinModel: insulinModel,
                carbModel: carbModel
            )
        }
        
        let uamCurve = predictUAM(
            currentGlucose: currentGlucose,
            glucoseDelta: glucoseDelta,
            iob: iob,
            activity: resolvedActivity,
            sens: sens,
            insulinModel: insulinModel
        )
        
        return PredictionResult(
            currentGlucose: currentGlucose,
            zt: ztCurve,
            iob: iobCurve,
            cob: cobCurve,
            uam: uamCurve
        )
    }
    
    // MARK: - Zero Temp Prediction
    
    /// Predict BG if a zero temp basal were set now.
    ///
    /// Matches JS oref0 prediction loop (determine-basal.js:583-585):
    ///   predZTBGI = -iobTick.iobWithZeroTemp.activity * sens * 5
    ///   ZTpredBG = prev + predZTBGI
    ///
    /// Uses iobWithZeroTemp activity (counterfactual: what if temp were cancelled)
    /// decayed with the same exponential model.
    private func predictZT(
        currentGlucose: Double,
        iobWithZeroTemp: Double,
        activity: Double,
        sens: Double,
        insulinModel: InsulinModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        var glucose = currentGlucose
        let intervals = predictionMinutes / intervalMinutes
        let tau = insulinModel.dia * 60.0 / 1.85
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            
            if i == 0 {
                points.append(PredictionPoint(minutesFromNow: 0, glucose: currentGlucose))
                continue
            }
            
            let t = Double(minutes)
            let decay = exp(-t / tau)
            let activityTick = activity * decay
            let predZTBGI = -activityTick * sens * Double(intervalMinutes)
            
            glucose = max(39, min(400, glucose + predZTBGI))
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
        }
        
        return PredictionCurve(type: .zt, points: points)
    }
    
    // MARK: - IOB Prediction
    
    /// Predict based on insulin on board using tick-by-tick accumulation.
    ///
    /// Matches JS oref0 prediction loop (determine-basal.js:574-581):
    ///   predBGI = -iobTick.activity * sens * 5
    ///   predDev = ci * (1 - min(1, tick/12))   // deviation decays over 60 min
    ///   IOBpredBG = prev + predBGI + predDev
    private func predictIOB(
        currentGlucose: Double,
        iob: Double,
        activity: Double,
        sens: Double,
        insulinModel: InsulinModel,
        ci: Double? = nil
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        let tau = insulinModel.dia * 60.0 / 1.85
        
        // Use pre-computed ci from DetermineBasal (minDelta - bgi, rounded & capped)
        // or fall back to zero if not provided
        let resolvedCI = ci ?? 0
        
        var prevGlucose = currentGlucose
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            let t = Double(minutes)
            let decay = exp(-t / tau)
            
            if i == 0 {
                points.append(PredictionPoint(minutesFromNow: 0, glucose: currentGlucose))
                continue
            }
            
            // Activity-based BG impact for this tick
            let activityTick = activity * decay
            let predBGI = (-activityTick * sens * Double(intervalMinutes)).rounded(toPlaces: 2)
            
            // Deviation impact decays linearly from ci to 0 over 60 minutes
            let predDev = resolvedCI * (1.0 - min(1.0, Double(i) / 12.0))
            
            let glucose = max(39, min(400, prevGlucose + predBGI + predDev))
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
            prevGlucose = glucose
        }
        
        return PredictionCurve(type: .iob, points: points)
    }
    
    // MARK: - COB Prediction
    
    /// Predict based on carbs on board
    private func predictCOB(
        currentGlucose: Double,
        iob: Double,
        activity: Double,
        cob: Double,
        sens: Double,
        icr: Double,
        insulinModel: InsulinModel,
        carbModel: CarbModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        let tau = insulinModel.dia * 60.0 / 1.85
        
        // Assume 3-hour absorption for COB prediction
        let absorptionTime = 3.0
        var prevGlucose = currentGlucose
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            let hours = Double(minutes) / 60.0
            
            if i == 0 {
                points.append(PredictionPoint(minutesFromNow: 0, glucose: currentGlucose))
                continue
            }
            
            // IOB effect via activity decay (matching JS predBGI pattern)
            let t = Double(minutes)
            let decay = exp(-t / tau)
            let activityTick = activity * decay
            let predBGI = -activityTick * sens * Double(intervalMinutes)
            
            // COB effect (raises BG)
            let absorbedCarbs = cob * carbModel.absorbed(at: hours, absorptionTime: absorptionTime)
            let prevAbsorbed = cob * carbModel.absorbed(at: Double((i - 1) * intervalMinutes) / 60.0, absorptionTime: absorptionTime)
            let carbImpact = (absorbedCarbs - prevAbsorbed) / icr * sens
            
            let glucose = max(39, min(400, prevGlucose + predBGI + carbImpact))
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
            prevGlucose = glucose
        }
        
        return PredictionCurve(type: .cob, points: points)
    }
    
    // MARK: - COB Prediction (oref0-matching)
    
    /// Predict COB curve using JS oref0 formula for cross-validation parity.
    ///
    /// Matches JS determine-basal.js lines 584-596:
    ///   predCI = max(0, max(0,ci) * (1 - length/max(cid*2,1)))        // linear observed decay
    ///   remainingCI = max(0, intervals/(remainingCATime/2*12) * peak)  // bilinear unobserved
    ///   COBpredBG = prev + predBGI + min(0, predDev) + predCI + remainingCI
    private func predictCOBOref0(
        currentGlucose: Double,
        activity: Double,
        sens: Double,
        insulinModel: InsulinModel,
        cobParams: COBPredictionParams
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let maxTicks = 48  // 4 hours at 5-min intervals, matching JS
        let intervals = min(maxTicks, predictionMinutes / intervalMinutes)
        let tau = insulinModel.dia * 60.0 / 1.85
        let ci = cobParams.ci
        let cid = cobParams.cid
        let remainingCIpeak = cobParams.remainingCIpeak
        let remainingCATime = cobParams.remainingCATime
        
        var prevGlucose = currentGlucose
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            
            if i == 0 {
                points.append(PredictionPoint(minutesFromNow: 0, glucose: currentGlucose))
                continue
            }
            
            // predBGI: insulin effect at this tick
            // JS: predBGI = round(-iobTick.activity * sens * 5, 2)
            let t = Double(minutes)
            let decay = exp(-t / tau)
            let activityTick = activity * decay
            let predBGI = (-activityTick * sens * Double(intervalMinutes)).rounded(toPlaces: 2)
            
            // predDev: deviation impact decays linearly over 60 min (12 ticks)
            // JS: predDev = ci * (1 - min(1, IOBpredBGs.length/(60/5)))
            // At tick i, JS array length = i (bg at [0] plus i-1 computed, about to add i-th)
            let predDev = ci * (1.0 - min(1.0, Double(i) / 12.0))
            
            // predCI: linear decay of observed carb impact from ci down to 0
            // JS: predCI = max(0, max(0,ci) * (1 - COBpredBGs.length/max(cid*2,1)))
            let predCI = max(0.0, max(0.0, ci) * (1.0 - Double(i) / max(cid * 2.0, 1.0)))
            
            // remainingCI: bilinear (/\) unobserved carb absorption
            // JS: intervals = min(COBpredBGs.length, (remainingCATime*12)-COBpredBGs.length)
            //     remainingCI = max(0, intervals/(remainingCATime/2*12) * remainingCIpeak)
            let bilinearPos = min(Double(i), remainingCATime * 12.0 - Double(i))
            let halfPeakTicks = remainingCATime / 2.0 * 12.0
            let remainingCI = halfPeakTicks > 0
                ? max(0.0, bilinearPos / halfPeakTicks * remainingCIpeak)
                : 0.0
            
            // COBpredBG: prev + predBGI + min(0, predDev) + predCI + remainingCI
            // Key: only NEGATIVE deviations included (positive deviations are carb absorption,
            // already accounted for by predCI/remainingCI)
            let glucose = max(39.0, min(400.0,
                prevGlucose + predBGI + min(0.0, predDev) + predCI + remainingCI))
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
            prevGlucose = glucose
        }
        
        return PredictionCurve(type: .cob, points: points)
    }
    
    // MARK: - UAM Prediction
    
    /// Predict unannounced meal effect
    private func predictUAM(
        currentGlucose: Double,
        glucoseDelta: Double,
        iob: Double,
        activity: Double,
        sens: Double,
        insulinModel: InsulinModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        let tau = insulinModel.dia * 60.0 / 1.85
        
        // UAM assumes the current rise will continue but decay
        var prevGlucose = currentGlucose
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            
            if i == 0 {
                points.append(PredictionPoint(minutesFromNow: 0, glucose: currentGlucose))
                continue
            }
            
            // IOB effect via activity decay (matching JS predBGI)
            let t = Double(minutes)
            let decay = exp(-t / tau)
            let activityTick = activity * decay
            let predBGI = -activityTick * sens * Double(intervalMinutes)
            
            // UAM effect: current deviation continues with exponential decay
            let uamDecay = exp(-Double(minutes) / 90.0)  // ~1.5 hour time constant
            let predUCI = glucoseDelta * uamDecay
            
            let glucose = max(39, min(400, prevGlucose + predBGI + predUCI))
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
            prevGlucose = glucose
        }
        
        return PredictionCurve(type: .uam, points: points)
    }
}

// MARK: - Insulin Model Extension

extension InsulinModel {
    /// Calculate remaining IOB fraction at time t (hours)
    ///
    /// Uses the same exponential decay model as the JS oref0 adapter:
    /// `tau = DIA_hours * 60 / 1.85` (in minutes), decay = `exp(-t_min / tau)`
    /// This provides cross-validation parity with the JS adapter's
    /// `generateIobArray()` function.
    public func iobRemaining(at t: Double) -> Double {
        guard t >= 0 else { return 1.0 }
        guard t < dia else { return 0 }
        
        let tMinutes = t * 60.0
        let tau = dia * 60.0 / 1.85
        return exp(-tMinutes / tau)
    }
}

// MARK: - Convert to GlucosePredictions

extension PredictionResult {
    /// Convert to GlucosePredictions for AlgorithmDecision
    public func toGlucosePredictions() -> GlucosePredictions {
        GlucosePredictions(
            iob: iob.points.map(\.glucose),
            cob: cob.points.map(\.glucose),
            uam: uam.points.map(\.glucose),
            zt: zt.points.map(\.glucose)
        )
    }
}

// MARK: - Guard System

/// Safety guard values extracted from prediction curves.
///
/// Matches the guard logic in oref0 determine-basal.js (lines 550-760).
/// Guards track minimum predicted BG per-curve with different wait times
/// before setting minimums, then blend based on COB/UAM state.
public struct GuardSystem: Sendable {

    // Per-curve guards (no wait — used for safety floor)
    public let minIOBGuardBG: Double
    public let minCOBGuardBG: Double
    public let minUAMGuardBG: Double
    public let minZTGuardBG: Double

    // Per-curve prediction minimums (with insulin peak wait)
    public let minIOBPredBG: Double
    public let minCOBPredBG: Double
    public let minUAMPredBG: Double

    // Blended guard (the final safety value used in dosing decisions)
    public let minGuardBG: Double

    // Blended minPredBG (used for rate calculation)
    public let minPredBG: Double

    // Threshold and expectedDelta
    public let threshold: Double
    public let expectedDelta: Double

    /// Extract guard values from prediction curves matching JS oref0 logic.
    public init(
        predictions: PredictionResult,
        bg: Double,
        minBG: Double,
        maxBG: Double,
        targetBG: Double,
        eventualBG: Double,
        bgi: Double,
        hasCOB: Bool = false,
        enableUAM: Bool = false,
        hasCarbs: Bool = false,
        fractionCarbsLeft: Double = 0,
        insulinPeakMinutes: Int = 90,
        intervalMinutes: Int = 5
    ) {
        // threshold: min_bg of 90 → 65, 100 → 70, 110 → 75, 130 → 85
        // Origin: determine-basal.js:329
        self.threshold = minBG - 0.5 * (minBG - 40)

        // expectedDelta: expected BG change per 5m based on BGI + target correction
        // Origin: determine-basal.js:31-35
        let fiveMinBlocks = Double((2 * 60) / intervalMinutes)  // 24
        let targetDelta = targetBG - eventualBG
        self.expectedDelta = (bgi + (targetDelta / fiveMinBlocks)).rounded(toPlaces: 1)

        let peakTicks = insulinPeakMinutes / intervalMinutes  // 18 ticks at 90m

        // Extract per-curve minimums
        // Guards: no wait (track from tick 0) — used for safety floor
        // PredBGs: wait for insulin peak — used for rate decisions
        var iobGuard = 999.0, cobGuard = 999.0, uamGuard = 999.0, ztGuard = 999.0
        var iobPred = 999.0, cobPred = 999.0, uamPred = 999.0

        for (i, point) in predictions.iob.points.enumerated() {
            if point.glucose < iobGuard { iobGuard = point.glucose.rounded() }
            if i > peakTicks && point.glucose < iobPred { iobPred = point.glucose.rounded() }
        }
        for (i, point) in predictions.cob.points.enumerated() {
            if point.glucose < cobGuard { cobGuard = point.glucose.rounded() }
            if hasCOB && i > peakTicks && point.glucose < cobPred { cobPred = point.glucose.rounded() }
        }
        for (i, point) in predictions.uam.points.enumerated() {
            if point.glucose < uamGuard { uamGuard = point.glucose.rounded() }
            // UAM uses 12 ticks (60m) instead of peakTicks (90m)
            if enableUAM && i > 12 && point.glucose < uamPred { uamPred = point.glucose.rounded() }
        }
        for point in predictions.zt.points {
            if point.glucose < ztGuard { ztGuard = point.glucose.rounded() }
        }

        self.minIOBGuardBG = iobGuard
        self.minCOBGuardBG = cobGuard
        self.minUAMGuardBG = uamGuard
        self.minZTGuardBG = ztGuard
        self.minIOBPredBG = iobPred
        self.minCOBPredBG = cobPred
        self.minUAMPredBG = uamPred

        // Blend minGuardBG based on COB/UAM state
        // Origin: determine-basal.js:729-740
        var guard_: Double
        if hasCOB {
            if enableUAM {
                guard_ = fractionCarbsLeft * cobGuard + (1 - fractionCarbsLeft) * uamGuard
            } else {
                guard_ = cobGuard
            }
        } else if enableUAM {
            guard_ = uamGuard
        } else {
            guard_ = iobGuard
        }
        self.minGuardBG = guard_.rounded()

        // minZTUAMPredBG blending
        // Origin: determine-basal.js:744-758
        let threshold_ = self.threshold
        var minZTUAMPredBG: Double
        if ztGuard < threshold_ {
            minZTUAMPredBG = (uamPred + ztGuard) / 2
        } else if ztGuard < targetBG {
            let blendPct = (ztGuard - threshold_) / max(1, targetBG - threshold_)
            let blendedMinZTGuardBG = uamPred * blendPct + ztGuard * (1 - blendPct)
            minZTUAMPredBG = (uamPred + blendedMinZTGuardBG) / 2
        } else if ztGuard > uamPred {
            minZTUAMPredBG = (uamPred + ztGuard) / 2
        } else {
            minZTUAMPredBG = uamPred
        }
        minZTUAMPredBG = minZTUAMPredBG.rounded()

        // Blend minPredBG based on carb/UAM state
        // Origin: determine-basal.js:762-790
        var pred: Double
        if hasCarbs {
            if !enableUAM && cobPred < 999 {
                pred = max(iobPred, cobPred).rounded()
            } else if cobPred < 999 {
                let blendedMinPredBG = fractionCarbsLeft * cobPred + (1 - fractionCarbsLeft) * minZTUAMPredBG
                pred = max(iobPred, cobPred, blendedMinPredBG).rounded()
            } else if enableUAM {
                pred = minZTUAMPredBG
            } else {
                pred = guard_
            }
        } else if enableUAM {
            pred = max(iobPred, minZTUAMPredBG).rounded()
        } else {
            pred = iobPred
        }
        // avgPredBG cap (use ZT guard as proxy)
        pred = min(pred, ztGuard)
        self.minPredBG = pred
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
