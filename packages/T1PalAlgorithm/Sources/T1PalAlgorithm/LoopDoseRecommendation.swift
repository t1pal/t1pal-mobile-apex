// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopDoseRecommendation.swift
// T1Pal Mobile
//
// Loop-compatible dose recommendation engine
// Requirements: REQ-ALGO-012
//
// Based on Loop's LoopDataManager dose calculations:
// https://github.com/LoopKit/Loop/blob/main/Loop/Managers/LoopDataManager.swift
//
// Combines predictions, safety limits, and retrospective correction
// to generate temp basal and bolus recommendations.
//
// Trace: ALG-019, PRD-009

import Foundation
import T1PalCore

// MARK: - Dose Recommendation Types

/// Type of dose recommendation
public enum DoseRecommendationType: String, Codable, Sendable {
    case tempBasal = "temp_basal"
    case bolus = "bolus"
    case suspend = "suspend"
    case resume = "resume"
}

/// A recommended dose action
public struct DoseRecommendation: Sendable {
    public let type: DoseRecommendationType
    public let rate: Double?          // U/hr for temp basal
    public let units: Double?         // Units for bolus
    public let duration: TimeInterval? // Duration for temp basal
    public let reason: String
    public let timestamp: Date
    
    public init(
        type: DoseRecommendationType,
        rate: Double? = nil,
        units: Double? = nil,
        duration: TimeInterval? = nil,
        reason: String,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.rate = rate
        self.units = units
        self.duration = duration
        self.reason = reason
        self.timestamp = timestamp
    }
    
    /// Create a temp basal recommendation
    public static func tempBasal(
        rate: Double,
        duration: TimeInterval = 30 * 60,
        reason: String
    ) -> DoseRecommendation {
        DoseRecommendation(
            type: .tempBasal,
            rate: rate,
            duration: duration,
            reason: reason
        )
    }
    
    /// Create a bolus recommendation
    public static func bolus(units: Double, reason: String) -> DoseRecommendation {
        DoseRecommendation(type: .bolus, units: units, reason: reason)
    }
    
    /// Create a suspend recommendation
    public static func suspend(reason: String) -> DoseRecommendation {
        DoseRecommendation(type: .suspend, rate: 0, reason: reason)
    }
}

/// Complete recommendation result with predictions and reasoning
public struct LoopRecommendationResult: Sendable {
    public let recommendation: DoseRecommendation
    public let predictions: [PredictedGlucose]
    public let predictedMin: Double
    public let predictedEventual: Double
    public let currentGlucose: Double
    public let currentIOB: Double
    public let currentCOB: Double
    public let targetGlucose: Double
    public let insulinRequired: Double  // Total insulin needed to reach target
    public let safetyLimited: Bool
    public let timestamp: Date
    
    public init(
        recommendation: DoseRecommendation,
        predictions: [PredictedGlucose],
        predictedMin: Double,
        predictedEventual: Double,
        currentGlucose: Double,
        currentIOB: Double,
        currentCOB: Double,
        targetGlucose: Double,
        insulinRequired: Double,
        safetyLimited: Bool,
        timestamp: Date = Date()
    ) {
        self.recommendation = recommendation
        self.predictions = predictions
        self.predictedMin = predictedMin
        self.predictedEventual = predictedEventual
        self.currentGlucose = currentGlucose
        self.currentIOB = currentIOB
        self.currentCOB = currentCOB
        self.targetGlucose = targetGlucose
        self.insulinRequired = insulinRequired
        self.safetyLimited = safetyLimited
        self.timestamp = timestamp
    }
}

// MARK: - Loop Dose Calculator

/// Loop-compatible dose recommendation calculator
public struct LoopDoseCalculator: Sendable {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Maximum temp basal rate (U/hr)
        public let maxBasalRate: Double
        
        /// Maximum bolus (U)
        public let maxBolus: Double
        
        /// Suspend threshold (mg/dL)
        public let suspendThreshold: Double
        
        /// Duration for temp basal recommendations
        public let tempBasalDuration: TimeInterval
        
        /// Minimum BG to recommend insulin
        public let minimumBGGuard: Double
        
        /// Whether to allow negative temp basals (zero out)
        public let allowZeroTemp: Bool
        
        public init(
            maxBasalRate: Double = 5.0,
            maxBolus: Double = 10.0,
            suspendThreshold: Double = 70,
            tempBasalDuration: TimeInterval = 30 * 60,
            minimumBGGuard: Double = 80,
            allowZeroTemp: Bool = true
        ) {
            self.maxBasalRate = maxBasalRate
            self.maxBolus = maxBolus
            self.suspendThreshold = suspendThreshold
            self.tempBasalDuration = tempBasalDuration
            self.minimumBGGuard = minimumBGGuard
            self.allowZeroTemp = allowZeroTemp
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - Properties
    
    public let configuration: Configuration
    public let predictor: LoopGlucosePrediction
    public let iobCalculator: LoopIOBCalculator
    public let cobCalculator: LoopCOBCalculator
    
    // MARK: - Initialization
    
    public init(
        configuration: Configuration = .default,
        insulinModel: LoopInsulinModelType = .rapidActingAdult,
        carbModel: LoopCarbAbsorptionModel = .piecewiseLinear
    ) {
        self.configuration = configuration
        self.predictor = LoopGlucosePrediction(insulinModel: insulinModel, carbModel: carbModel)
        self.iobCalculator = LoopIOBCalculator(modelType: insulinModel)
        self.cobCalculator = LoopCOBCalculator(model: carbModel)
    }
    
    // MARK: - Temp Basal Recommendation
    
    /// Calculate temp basal recommendation
    /// - Parameters:
    ///   - currentGlucose: Current glucose value
    ///   - glucoseHistory: Recent glucose readings
    ///   - doses: Recent insulin doses
    ///   - carbEntries: Recent carb entries
    ///   - scheduledBasalRate: Current scheduled basal rate
    ///   - insulinSensitivity: ISF in mg/dL per unit (scalar fallback)
    ///   - carbRatio: ICR in grams per unit
    ///   - targetGlucose: Target glucose (scalar fallback)
    ///   - basalSchedule: Scheduled basal rates for net insulin effects (ALG-DIAG-GEFF-005)
    ///   - insulinSensitivitySchedule: ISF timeline for parity calculation (ALG-DIAG-024)
    ///   - correctionRangeSchedule: Target range timeline for parity calculation (ALG-DIAG-024)
    ///   - insulinModel: Insulin model for effect calculations (ALG-DIAG-024)
    /// - Returns: Recommendation result
    public func recommendTempBasal(
        currentGlucose: Double,
        glucoseHistory: [GlucoseReading] = [],
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        scheduledBasalRate: Double,
        insulinSensitivity: Double,
        carbRatio: Double,
        targetGlucose: Double,
        basalSchedule: [AbsoluteScheduleValue<Double>]? = nil,
        insulinSensitivitySchedule: [AbsoluteScheduleValue<Double>]? = nil,
        correctionRangeSchedule: [AbsoluteScheduleValue<ClosedRange<Double>>]? = nil,
        insulinModel: LoopExponentialInsulinModel? = nil,
        retrospectiveCorrectionEffects: [GlucoseEffect]? = nil  // ALG-PRED-001: Pass RC effects
    ) -> LoopRecommendationResult {
        let now = Date()
        
        // Calculate current IOB and COB
        let currentIOB = iobCalculator.insulinOnBoard(doses: doses, at: now)
        let currentCOB = cobCalculator.carbsOnBoard(entries: carbEntries, at: now)
        
        // Generate predictions
        // ALG-DIAG-GEFF-005: Start predictions from CGM reading time for momentum alignment
        let predictionStartDate = glucoseHistory.sorted(by: { $0.timestamp > $1.timestamp }).first?.timestamp ?? now
        let predictions = predictor.predict(
            currentGlucose: currentGlucose,
            glucoseHistory: glucoseHistory,
            doses: doses,
            carbEntries: carbEntries,
            insulinSensitivity: insulinSensitivity,
            carbRatio: carbRatio,
            startDate: predictionStartDate,
            basalSchedule: basalSchedule,
            retrospectiveCorrectionEffects: retrospectiveCorrectionEffects  // ALG-PRED-001
        )
        
        let summary = PredictionSummary(predictions: predictions)
        
        // ALG-DIAG-024: Use parity insulin correction when schedules are available
        if let isfSchedule = insulinSensitivitySchedule,
           let targetSchedule = correctionRangeSchedule,
           !isfSchedule.isEmpty,
           !targetSchedule.isEmpty {
            
            let model = insulinModel ?? LoopInsulinModelPreset.rapidActingAdult.model
            
            let correctionParams = InsulinCorrectionParameters(
                predictions: predictions,
                correctionRange: targetSchedule,
                doseDate: predictionStartDate,
                suspendThreshold: configuration.suspendThreshold,
                insulinSensitivity: isfSchedule,
                insulinModel: model
            )
            
            let correction = insulinCorrectionParity(parameters: correctionParams)
            
            // Convert correction to temp basal
            let tempBasal = correction.asTempBasal(
                neutralBasalRate: scheduledBasalRate,
                maxBasalRate: configuration.maxBasalRate,
                duration: configuration.tempBasalDuration
            )
            
            let insulinRequired: Double
            var safetyLimited = false
            
            switch correction {
            case .suspend(let minGlucose):
                return LoopRecommendationResult(
                    recommendation: .suspend(reason: "Predicted low: \(Int(minGlucose)) mg/dL"),
                    predictions: predictions,
                    predictedMin: summary.minGlucose,
                    predictedEventual: summary.eventualGlucose,
                    currentGlucose: currentGlucose,
                    currentIOB: currentIOB,
                    currentCOB: currentCOB,
                    targetGlucose: targetGlucose,
                    insulinRequired: 0,
                    safetyLimited: true
                )
                
            case .aboveRange(_, _, let units):
                insulinRequired = units
                
            case .entirelyBelowRange(_, _, let units):
                insulinRequired = units  // Will be negative
                safetyLimited = true
                
            case .inRange:
                insulinRequired = 0
            }
            
            // Check if rate was clamped
            if tempBasal.rate >= configuration.maxBasalRate || tempBasal.rate <= 0 {
                safetyLimited = true
            }
            
            let reason = buildTempBasalReason(
                tempRate: tempBasal.rate,
                scheduledRate: scheduledBasalRate,
                eventualBG: summary.eventualGlucose,
                targetBG: targetGlucose
            )
            
            return LoopRecommendationResult(
                recommendation: .tempBasal(
                    rate: tempBasal.rate,
                    duration: tempBasal.duration,
                    reason: reason
                ),
                predictions: predictions,
                predictedMin: summary.minGlucose,
                predictedEventual: summary.eventualGlucose,
                currentGlucose: currentGlucose,
                currentIOB: currentIOB,
                currentCOB: currentCOB,
                targetGlucose: targetGlucose,
                insulinRequired: insulinRequired,
                safetyLimited: safetyLimited
            )
        }
        
        // Legacy path: simple formula when schedules not available
        
        // Check for low glucose suspend
        if summary.minGlucose < configuration.suspendThreshold {
            return LoopRecommendationResult(
                recommendation: .suspend(reason: "Predicted low: \(Int(summary.minGlucose)) mg/dL"),
                predictions: predictions,
                predictedMin: summary.minGlucose,
                predictedEventual: summary.eventualGlucose,
                currentGlucose: currentGlucose,
                currentIOB: currentIOB,
                currentCOB: currentCOB,
                targetGlucose: targetGlucose,
                insulinRequired: 0,
                safetyLimited: true
            )
        }
        
        // Calculate insulin required to bring eventual BG to target
        let bgDifference = summary.eventualGlucose - targetGlucose
        let insulinRequired = bgDifference / insulinSensitivity
        
        // Calculate temp basal adjustment
        let (tempRate, safetyLimited) = calculateTempBasalRate(
            insulinRequired: insulinRequired,
            scheduledBasalRate: scheduledBasalRate,
            currentGlucose: currentGlucose,
            predictedMin: summary.minGlucose
        )
        
        let reason = buildTempBasalReason(
            tempRate: tempRate,
            scheduledRate: scheduledBasalRate,
            eventualBG: summary.eventualGlucose,
            targetBG: targetGlucose
        )
        
        return LoopRecommendationResult(
            recommendation: .tempBasal(
                rate: tempRate,
                duration: configuration.tempBasalDuration,
                reason: reason
            ),
            predictions: predictions,
            predictedMin: summary.minGlucose,
            predictedEventual: summary.eventualGlucose,
            currentGlucose: currentGlucose,
            currentIOB: currentIOB,
            currentCOB: currentCOB,
            targetGlucose: targetGlucose,
            insulinRequired: insulinRequired,
            safetyLimited: safetyLimited
        )
    }
    
    /// Calculate temp basal rate from insulin requirement
    private func calculateTempBasalRate(
        insulinRequired: Double,
        scheduledBasalRate: Double,
        currentGlucose: Double,
        predictedMin: Double
    ) -> (rate: Double, safetyLimited: Bool) {
        var safetyLimited = false
        
        // Convert insulin required over prediction duration to hourly rate adjustment
        // Assuming 30-minute temp basal, adjust rate to deliver required insulin
        let rateAdjustment = insulinRequired * 2  // Double for 30-min rate
        
        var tempRate = scheduledBasalRate + rateAdjustment
        
        // Safety checks
        if currentGlucose < configuration.minimumBGGuard {
            tempRate = 0
            safetyLimited = true
        }
        
        // Clamp to limits
        if tempRate > configuration.maxBasalRate {
            tempRate = configuration.maxBasalRate
            safetyLimited = true
        }
        
        if tempRate < 0 {
            tempRate = configuration.allowZeroTemp ? 0 : scheduledBasalRate
            safetyLimited = !configuration.allowZeroTemp
        }
        
        return (tempRate, safetyLimited)
    }
    
    /// Build human-readable reason for temp basal
    private func buildTempBasalReason(
        tempRate: Double,
        scheduledRate: Double,
        eventualBG: Double,
        targetBG: Double
    ) -> String {
        if tempRate == 0 {
            return "Zero temp: eventual BG \(Int(eventualBG)) approaching target \(Int(targetBG))"
        } else if tempRate > scheduledRate {
            return "High temp \(String(format: "%.2f", tempRate)) U/hr: eventual BG \(Int(eventualBG)) > target \(Int(targetBG))"
        } else if tempRate < scheduledRate {
            return "Low temp \(String(format: "%.2f", tempRate)) U/hr: eventual BG \(Int(eventualBG)) < target \(Int(targetBG))"
        } else {
            return "Scheduled rate: eventual BG \(Int(eventualBG)) ≈ target \(Int(targetBG))"
        }
    }
    
    // MARK: - Bolus Recommendation
    
    /// Calculate bolus recommendation for a meal or correction
    /// - Parameters:
    ///   - currentGlucose: Current glucose value
    ///   - carbsToEat: Carbs being eaten (grams)
    ///   - doses: Recent insulin doses
    ///   - carbEntries: Recent carb entries (not including carbsToEat)
    ///   - insulinSensitivity: ISF
    ///   - carbRatio: ICR
    ///   - targetGlucose: Target glucose
    /// - Returns: Bolus recommendation result
    public func recommendBolus(
        currentGlucose: Double,
        carbsToEat: Double,
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        insulinSensitivity: Double,
        carbRatio: Double,
        targetGlucose: Double
    ) -> LoopRecommendationResult {
        let now = Date()
        
        // Calculate current IOB and COB
        let currentIOB = iobCalculator.insulinOnBoard(doses: doses, at: now)
        let currentCOB = cobCalculator.carbsOnBoard(entries: carbEntries, at: now)
        
        // Calculate carb bolus
        let carbBolus = carbsToEat / carbRatio
        
        // Calculate correction bolus
        let bgDifference = currentGlucose - targetGlucose
        var correctionBolus = bgDifference / insulinSensitivity
        
        // Subtract IOB from correction (don't double-dose)
        correctionBolus = max(0, correctionBolus - currentIOB)
        
        // Total recommended bolus
        var totalBolus = carbBolus + correctionBolus
        var safetyLimited = false
        
        // Safety checks
        if currentGlucose < configuration.minimumBGGuard {
            // Don't recommend correction if BG is low
            correctionBolus = 0
            totalBolus = carbBolus
            safetyLimited = true
        }
        
        if totalBolus > configuration.maxBolus {
            totalBolus = configuration.maxBolus
            safetyLimited = true
        }
        
        if totalBolus < 0 {
            totalBolus = 0
        }
        
        let reason = buildBolusReason(
            carbBolus: carbBolus,
            correctionBolus: correctionBolus,
            totalBolus: totalBolus,
            carbsToEat: carbsToEat,
            currentGlucose: currentGlucose,
            targetGlucose: targetGlucose
        )
        
        // Generate predictions with the new carbs
        let futureCarbEntry = CarbEntry(grams: carbsToEat, timestamp: now)
        let allCarbs = carbEntries + [futureCarbEntry]
        
        let predictions = predictor.predict(
            currentGlucose: currentGlucose,
            doses: doses,
            carbEntries: allCarbs,
            insulinSensitivity: insulinSensitivity,
            carbRatio: carbRatio
        )
        
        let summary = PredictionSummary(predictions: predictions)
        
        return LoopRecommendationResult(
            recommendation: .bolus(units: totalBolus, reason: reason),
            predictions: predictions,
            predictedMin: summary.minGlucose,
            predictedEventual: summary.eventualGlucose,
            currentGlucose: currentGlucose,
            currentIOB: currentIOB,
            currentCOB: currentCOB + carbsToEat,
            targetGlucose: targetGlucose,
            insulinRequired: totalBolus,
            safetyLimited: safetyLimited
        )
    }
    
    /// Build human-readable reason for bolus
    private func buildBolusReason(
        carbBolus: Double,
        correctionBolus: Double,
        totalBolus: Double,
        carbsToEat: Double,
        currentGlucose: Double,
        targetGlucose: Double
    ) -> String {
        var parts: [String] = []
        
        if carbBolus > 0.05 {
            parts.append(String(format: "%.1fU for %dg carbs", carbBolus, Int(carbsToEat)))
        }
        
        if correctionBolus > 0.05 {
            parts.append(String(format: "%.1fU correction (%d → %d)", correctionBolus, Int(currentGlucose), Int(targetGlucose)))
        }
        
        if parts.isEmpty {
            return "No bolus needed"
        }
        
        return parts.joined(separator: " + ")
    }
    
    // MARK: - Correction Bolus Only
    
    /// Calculate correction-only bolus (no meal)
    public func recommendCorrectionBolus(
        currentGlucose: Double,
        doses: [InsulinDose] = [],
        insulinSensitivity: Double,
        targetGlucose: Double
    ) -> LoopRecommendationResult {
        recommendBolus(
            currentGlucose: currentGlucose,
            carbsToEat: 0,
            doses: doses,
            carbEntries: [],
            insulinSensitivity: insulinSensitivity,
            carbRatio: 10,  // Doesn't matter for correction only
            targetGlucose: targetGlucose
        )
    }
}

// MARK: - Dose Recommendation with Retrospective Correction

extension LoopDoseCalculator {
    
    /// Calculate temp basal with retrospective correction applied
    public func recommendTempBasalWithCorrection(
        currentGlucose: Double,
        glucoseHistory: [GlucoseReading] = [],
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        pastPredictions: [PredictedGlucose] = [],
        scheduledBasalRate: Double,
        insulinSensitivity: Double,
        carbRatio: Double,
        targetGlucose: Double,
        retrospectiveCorrection: RetrospectiveCorrection = RetrospectiveCorrection()
    ) -> LoopRecommendationResult {
        let now = Date()
        
        // Calculate retrospective correction
        let correctionResult = retrospectiveCorrection.analyze(
            predictions: pastPredictions,
            actuals: glucoseHistory,
            referenceDate: now
        )
        
        // Generate corrected predictions
        let predictions = predictor.predictWithCorrection(
            currentGlucose: currentGlucose,
            glucoseHistory: glucoseHistory,
            doses: doses,
            carbEntries: carbEntries,
            insulinSensitivity: insulinSensitivity,
            carbRatio: carbRatio,
            retrospectiveCorrection: correctionResult.correctionEffect
        )
        
        let summary = PredictionSummary(predictions: predictions)
        
        // Calculate IOB and COB
        let currentIOB = iobCalculator.insulinOnBoard(doses: doses, at: now)
        let currentCOB = cobCalculator.carbsOnBoard(entries: carbEntries, at: now)
        
        // Check for low glucose suspend
        if summary.minGlucose < configuration.suspendThreshold {
            return LoopRecommendationResult(
                recommendation: .suspend(reason: "Predicted low (corrected): \(Int(summary.minGlucose)) mg/dL"),
                predictions: predictions,
                predictedMin: summary.minGlucose,
                predictedEventual: summary.eventualGlucose,
                currentGlucose: currentGlucose,
                currentIOB: currentIOB,
                currentCOB: currentCOB,
                targetGlucose: targetGlucose,
                insulinRequired: 0,
                safetyLimited: true
            )
        }
        
        // Calculate insulin required
        let bgDifference = summary.eventualGlucose - targetGlucose
        let insulinRequired = bgDifference / insulinSensitivity
        
        // Calculate temp basal
        let (tempRate, safetyLimited) = calculateTempBasalRate(
            insulinRequired: insulinRequired,
            scheduledBasalRate: scheduledBasalRate,
            currentGlucose: currentGlucose,
            predictedMin: summary.minGlucose
        )
        
        var reason = buildTempBasalReason(
            tempRate: tempRate,
            scheduledRate: scheduledBasalRate,
            eventualBG: summary.eventualGlucose,
            targetBG: targetGlucose
        )
        
        if correctionResult.isSignificant {
            reason += " (retro adj: \(Int(correctionResult.weightedDiscrepancy)))"
        }
        
        return LoopRecommendationResult(
            recommendation: .tempBasal(
                rate: tempRate,
                duration: configuration.tempBasalDuration,
                reason: reason
            ),
            predictions: predictions,
            predictedMin: summary.minGlucose,
            predictedEventual: summary.eventualGlucose,
            currentGlucose: currentGlucose,
            currentIOB: currentIOB,
            currentCOB: currentCOB,
            targetGlucose: targetGlucose,
            insulinRequired: insulinRequired,
            safetyLimited: safetyLimited
        )
    }
}
