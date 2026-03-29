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
        carbModel: CarbModel = CarbModel()
    ) -> PredictionResult {
        let sens = profile.currentISF()
        _ = profile.currentTarget()  // target available for future use
        let scheduledBasal = profile.currentBasal()
        
        // Calculate curves
        let ztCurve = predictZT(
            currentGlucose: currentGlucose,
            glucoseDelta: glucoseDelta,
            scheduledBasal: scheduledBasal,
            sens: sens
        )
        
        let iobCurve = predictIOB(
            currentGlucose: currentGlucose,
            iob: iob,
            sens: sens,
            insulinModel: insulinModel
        )
        
        let cobCurve = predictCOB(
            currentGlucose: currentGlucose,
            iob: iob,
            cob: cob,
            sens: sens,
            icr: profile.currentICR(),
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        let uamCurve = predictUAM(
            currentGlucose: currentGlucose,
            glucoseDelta: glucoseDelta,
            iob: iob,
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
    
    /// Predict what happens if we deliver zero insulin
    private func predictZT(
        currentGlucose: Double,
        glucoseDelta: Double,
        scheduledBasal: Double,
        sens: Double
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        var glucose = currentGlucose
        
        // Without basal, BG will rise based on current trend
        // plus the effect of missing basal insulin
        let intervals = predictionMinutes / intervalMinutes
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            
            // Missing basal insulin effect (accumulates over time)
            let hoursElapsed = Double(minutes) / 60.0
            let missingInsulin = scheduledBasal * hoursElapsed
            let bgRiseFromMissingBasal = missingInsulin * sens
            
            // Current trend continues (decaying)
            let trendDecay = exp(-Double(minutes) / 60.0)  // Decay over 1 hour
            let trendEffect = glucoseDelta * Double(minutes / 5) * trendDecay
            
            glucose = currentGlucose + bgRiseFromMissingBasal + trendEffect
            glucose = max(39, min(400, glucose))  // Clamp to valid range
            
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
        }
        
        return PredictionCurve(type: .zt, points: points)
    }
    
    // MARK: - IOB Prediction
    
    /// Predict based on insulin on board
    private func predictIOB(
        currentGlucose: Double,
        iob: Double,
        sens: Double,
        insulinModel: InsulinModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            let hours = Double(minutes) / 60.0
            
            // Calculate remaining IOB at this time
            let remainingIOB = iob * insulinModel.iobRemaining(at: hours)
            let absorbedIOB = iob - remainingIOB
            
            // Effect of absorbed insulin
            let bgDrop = absorbedIOB * sens
            let glucose = max(39, min(400, currentGlucose - bgDrop))
            
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
        }
        
        return PredictionCurve(type: .iob, points: points)
    }
    
    // MARK: - COB Prediction
    
    /// Predict based on carbs on board
    private func predictCOB(
        currentGlucose: Double,
        iob: Double,
        cob: Double,
        sens: Double,
        icr: Double,
        insulinModel: InsulinModel,
        carbModel: CarbModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        
        // Assume 3-hour absorption for COB prediction
        let absorptionTime = 3.0
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            let hours = Double(minutes) / 60.0
            
            // IOB effect (lowers BG)
            let remainingIOB = iob * insulinModel.iobRemaining(at: hours)
            let absorbedIOB = iob - remainingIOB
            let iobEffect = absorbedIOB * sens
            
            // COB effect (raises BG)
            let absorbedCarbs = cob * carbModel.absorbed(at: hours, absorptionTime: absorptionTime)
            let carbEffect = absorbedCarbs / icr * sens  // Convert carbs to insulin equivalent
            
            let glucose = max(39, min(400, currentGlucose - iobEffect + carbEffect))
            
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
        }
        
        return PredictionCurve(type: .cob, points: points)
    }
    
    // MARK: - UAM Prediction
    
    /// Predict unannounced meal effect
    private func predictUAM(
        currentGlucose: Double,
        glucoseDelta: Double,
        iob: Double,
        sens: Double,
        insulinModel: InsulinModel
    ) -> PredictionCurve {
        var points: [PredictionPoint] = []
        let intervals = predictionMinutes / intervalMinutes
        
        // UAM assumes the current rise will continue but decay
        // Used when BG is rising faster than IOB can explain
        
        for i in 0...intervals {
            let minutes = i * intervalMinutes
            let hours = Double(minutes) / 60.0
            
            // IOB effect
            let remainingIOB = iob * insulinModel.iobRemaining(at: hours)
            let absorbedIOB = iob - remainingIOB
            let iobEffect = absorbedIOB * sens
            
            // UAM effect: current delta continues with exponential decay
            // Assumes unannounced carbs are being absorbed
            let uamDecay = exp(-hours / 1.5)  // 1.5 hour half-life
            let uamEffect = glucoseDelta * Double(minutes / 5) * uamDecay
            
            let glucose = max(39, min(400, currentGlucose - iobEffect + uamEffect))
            
            points.append(PredictionPoint(minutesFromNow: minutes, glucose: glucose))
        }
        
        return PredictionCurve(type: .uam, points: points)
    }
}

// MARK: - Insulin Model Extension

extension InsulinModel {
    /// Calculate remaining IOB fraction at time t (hours)
    public func iobRemaining(at t: Double) -> Double {
        // Use the integral of activity curve
        // For simplicity, use exponential decay based on DIA
        guard t >= 0 else { return 1.0 }
        guard t < dia else { return 0 }
        
        // Exponential decay with time constant based on peak
        let tau = insulinType.peakTime / 1.5
        let decay = exp(-t / tau)
        
        // Blend with linear decay near end of DIA
        let linearDecay = max(0, 1 - t / dia)
        
        return (decay + linearDecay) / 2
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
