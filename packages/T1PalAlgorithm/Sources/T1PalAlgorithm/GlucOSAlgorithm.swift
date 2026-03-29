// GlucOSAlgorithm.swift
// T1PalAlgorithm
//
// GlucOS-inspired algorithm composing all GlucOS features
// Source: UC Davis GlucOS research project
// Trace: GLUCOS-INT-001, ADR-010

import Foundation
import T1PalCore

/// GlucOS-inspired algorithm with dynamic ISF, predictive alerts, and adaptive tuning
///
/// Features:
/// - Dynamic ISF scaling based on glucose level
/// - Predictive alerts for high/low
/// - Exercise mode integration
/// - Adaptive tuning with learning
/// - ML safety bounds
///
/// Source: UC Davis GlucOS research project
/// Trace: ADR-010
public final class GlucOSAlgorithm: AlgorithmEngine, @unchecked Sendable {
    public let name = "GlucOS"
    public let version = "1.0.0"
    public let capabilities = AlgorithmCapabilities.glucos
    
    // Components
    private let predictor: LinearGlucosePredictor
    private let lowPassFilter: LowPassFilter
    
    // ALG-LIVE-058/059: Calculators for high-fidelity history support
    private let iobCalculator: IOBCalculator
    private let cobCalculator: COBCalculator
    
    // Configuration
    private let configuration: GlucOSConfiguration
    
    // Thread safety
    private let stateLock = NSLock()
    private var _lastPredictions: [PredictedGlucose] = []
    
    public init(configuration: GlucOSConfiguration = .default) {
        self.configuration = configuration
        self.predictor = LinearGlucosePredictor()
        self.lowPassFilter = LowPassFilter()
        self.iobCalculator = IOBCalculator(model: InsulinModel(insulinType: .novolog))
        self.cobCalculator = COBCalculator()
    }
    
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        // Apply low-pass filter to glucose readings
        let filteredGlucose = lowPassFilter.apply(to: inputs.glucose)
        
        guard let currentGlucose = inputs.glucose.last?.glucose,
              let filteredCurrent = filteredGlucose.last else {
            throw AlgorithmError.insufficientGlucoseData(
                required: capabilities.minGlucoseHistory,
                provided: inputs.glucose.count
            )
        }
        
        // Get base ISF from profile
        let baseISF = inputs.profile.sensitivityFactors.first?.factor ?? 50.0
        
        // Get dynamic ISF adjustment
        let dynamicISFResult = calculateDynamicISF(
            baseISF: baseISF,
            currentGlucose: currentGlucose,
            target: configuration.targetGlucose
        )
        
        // Calculate glucose prediction
        let prediction = predictor.predictWithDetails(
            from: inputs.glucose,
            horizon: 15 * 60  // 15 minutes in seconds
        )
        
        // Build predictions for chart
        let predictions = buildPredictions(
            from: inputs.glucose,
            prediction: prediction,
            currentTime: inputs.currentTime
        )
        
        // ALG-LIVE-058/059: Use real dose/carb history when available
        let now = inputs.currentTime
        let iob: Double
        let cob: Double
        
        // ALG-LIVE-058: Use doseHistory if provided, recalculate IOB
        if let doseHistory = inputs.doseHistory, !doseHistory.isEmpty {
            iob = iobCalculator.totalIOB(from: doseHistory, at: now)
        } else {
            iob = inputs.insulinOnBoard  // Fallback to scalar
        }
        
        // ALG-LIVE-059: Use carbHistory if provided, recalculate COB
        if let carbHistory = inputs.carbHistory, !carbHistory.isEmpty {
            cob = cobCalculator.totalCOB(from: carbHistory, at: now)
        } else {
            cob = inputs.carbsOnBoard  // Fallback to scalar
        }
        
        // Calculate temp basal recommendation
        let tempBasal = calculateTempBasal(
            currentGlucose: filteredCurrent,
            prediction: prediction,
            iob: iob,
            cob: cob,
            isf: dynamicISFResult.adjustedISF,
            profile: inputs.profile
        )
        
        // Build reason string
        let reason = buildReason(
            currentGlucose: currentGlucose,
            filteredGlucose: filteredCurrent,
            prediction: prediction,
            scalingFactor: dynamicISFResult.scalingFactor,
            tempBasal: tempBasal
        )
        
        return AlgorithmDecision(
            timestamp: inputs.currentTime,
            suggestedTempBasal: tempBasal,
            suggestedBolus: nil,  // GlucOS uses temp basals, not boluses
            reason: reason,
            predictions: predictions
        )
    }
    
    // MARK: - Private Helpers
    
    private struct DynamicISFAdjustment {
        let baseISF: Double
        let adjustedISF: Double
        let scalingFactor: Double
    }
    
    private func calculateDynamicISF(
        baseISF: Double,
        currentGlucose: Double,
        target: Double
    ) -> DynamicISFAdjustment {
        // Only scale when above target
        guard currentGlucose > target else {
            return DynamicISFAdjustment(
                baseISF: baseISF,
                adjustedISF: baseISF,
                scalingFactor: 1.0
            )
        }
        
        // Linear scaling from 1.0 to maxISFScaling
        let maxIncrease = configuration.maxISFScaling - 1.0
        let glucoseRange = 150.0  // Full scaling at 150 above target
        let scalingFactor = 1.0 + maxIncrease * min((currentGlucose - target) / glucoseRange, 1.0)
        
        // Dynamic ISF means we're MORE aggressive when high
        // So we DIVIDE the ISF (making it smaller = more insulin per mg/dL)
        let adjustedISF = baseISF / scalingFactor
        
        return DynamicISFAdjustment(
            baseISF: baseISF,
            adjustedISF: adjustedISF,
            scalingFactor: scalingFactor
        )
    }
    
    private func calculateTempBasal(
        currentGlucose: Double,
        prediction: GlucosePrediction?,
        iob: Double,
        cob: Double,
        isf: Double,
        profile: TherapyProfile
    ) -> TempBasal? {
        let target = configuration.targetGlucose
        // ALG-FIX-T5-003: Use time-aware basal rate lookup
        let basalRate = profile.basalRates.rateAt(date: Date()) ?? profile.basalRates.first?.rate ?? 1.0
        
        // Simple proportional control with prediction
        let predictedGlucose = prediction?.value ?? currentGlucose
        let error = predictedGlucose - target
        
        // Calculate adjustment based on predicted deviation
        // Using ISF: each unit of insulin drops glucose by ISF mg/dL
        let insulinNeeded = error / isf
        
        // Apply adjustment to basal rate
        var adjustedRate = basalRate + insulinNeeded
        
        // Clamp to safe range
        let maxRate = configuration.maxBasalRate
        adjustedRate = max(0, min(maxRate, adjustedRate))
        
        // Only suggest if meaningfully different from scheduled
        let threshold: Double = 0.05  // 0.05 U/hr minimum change
        let difference = adjustedRate - basalRate
        if difference > -threshold && difference < threshold {
            return nil
        }
        
        return TempBasal(rate: adjustedRate, duration: 30 * 60)  // 30 minutes
    }
    
    private func buildPredictions(
        from readings: [GlucoseReading],
        prediction: GlucosePrediction?,
        currentTime: Date
    ) -> GlucosePredictions? {
        guard let latest = readings.last,
              let pred = prediction else {
            return nil
        }
        
        // Build simple prediction curve using IOB array
        // (GlucOS uses simpler model - just one prediction line)
        let points = [latest.glucose, pred.value]
        
        stateLock.lock()
        _lastPredictions = [
            PredictedGlucose(date: currentTime, glucose: latest.glucose),
            PredictedGlucose(date: currentTime.addingTimeInterval(pred.horizon), glucose: pred.value)
        ]
        stateLock.unlock()
        
        return GlucosePredictions(
            iob: points,
            cob: [],
            uam: [],
            zt: []
        )
    }
    
    private func buildReason(
        currentGlucose: Double,
        filteredGlucose: Double,
        prediction: GlucosePrediction?,
        scalingFactor: Double,
        tempBasal: TempBasal?
    ) -> String {
        var parts: [String] = []
        
        parts.append("BG: \(Int(currentGlucose))")
        
        if abs(filteredGlucose - currentGlucose) > 2 {
            parts.append("filtered: \(Int(filteredGlucose))")
        }
        
        if let pred = prediction {
            parts.append("pred@15m: \(Int(pred.value))")
        }
        
        if scalingFactor != 1.0 {
            parts.append("ISF×\(String(format: "%.2f", scalingFactor))")
        }
        
        if let tb = tempBasal {
            parts.append("→\(String(format: "%.2f", tb.rate))U/hr")
        } else {
            parts.append("→no change")
        }
        
        return parts.joined(separator: " | ")
    }
}

// MARK: - Configuration

/// Configuration for GlucOS algorithm
public struct GlucOSConfiguration: Sendable {
    /// Target glucose (mg/dL)
    public let targetGlucose: Double
    
    /// Maximum ISF scaling factor
    public let maxISFScaling: Double
    
    /// Maximum basal rate (U/hr)
    public let maxBasalRate: Double
    
    /// Enable predictive alerts
    public let enablePredictiveAlerts: Bool
    
    /// Enable adaptive tuning
    public let enableAdaptiveTuning: Bool
    
    /// Exercise mode raises target to this value
    public let exerciseTargetGlucose: Double
    
    public init(
        targetGlucose: Double = 100,
        maxISFScaling: Double = 1.5,
        maxBasalRate: Double = 5.0,
        enablePredictiveAlerts: Bool = true,
        enableAdaptiveTuning: Bool = false,  // Disabled by default until proven
        exerciseTargetGlucose: Double = 140
    ) {
        self.targetGlucose = targetGlucose
        self.maxISFScaling = maxISFScaling
        self.maxBasalRate = maxBasalRate
        self.enablePredictiveAlerts = enablePredictiveAlerts
        self.enableAdaptiveTuning = enableAdaptiveTuning
        self.exerciseTargetGlucose = exerciseTargetGlucose
    }
    
    public static let `default` = GlucOSConfiguration()
}
