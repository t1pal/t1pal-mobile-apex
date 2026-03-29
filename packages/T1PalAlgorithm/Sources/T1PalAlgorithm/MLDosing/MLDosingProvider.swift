// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLDosingProvider.swift
// T1Pal Mobile
//
// ML-based dosing enhancement provider (placeholder)
// Source: GlucOS AIDosing, DNNDosing
// Trace: GLUCOS-IMPL-005, ADR-010

import Foundation
import T1PalCore

// MARK: - ML Dosing Result

/// Result of ML dosing adjustment
public struct MLDosingResult: Sendable {
    /// Adjusted temp basal rate (U/hr)
    public let tempBasalRate: Double
    
    /// Scaling factor applied (1.0-1.5 for dynamic ISF)
    public let scalingFactor: Double
    
    /// ML insulin delivered in last 3 hours (units)
    public let mlInsulinLast3Hours: Double
    
    /// Was the result clamped by safety bounds?
    public let wasClamped: Bool
    
    /// Reason for adjustment
    public let reason: String
    
    public init(
        tempBasalRate: Double,
        scalingFactor: Double = 1.0,
        mlInsulinLast3Hours: Double = 0,
        wasClamped: Bool = false,
        reason: String = ""
    ) {
        self.tempBasalRate = tempBasalRate
        self.scalingFactor = scalingFactor
        self.mlInsulinLast3Hours = mlInsulinLast3Hours
        self.wasClamped = wasClamped
        self.reason = reason
    }
}

// MARK: - Protocol

/// Machine learning dosing enhancement provider
/// Trace: GLUCOS-IMPL-005, ADR-010
public protocol MLDosingProvider: Sendable {
    /// Adjust baseline temp basal with ML insights
    /// Returns nil if ML should not be applied (below target, exercising, etc.)
    func adjustedTempBasal(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult?
    
    /// Check if ML dosing is available and enabled
    var isEnabled: Bool { get }
}

// MARK: - Dynamic ISF Provider

/// Simple dynamic ISF - increases dose linearly when above target
/// Source: GlucOS AIDosing
public struct DynamicISFProvider: MLDosingProvider, Sendable {
    
    /// Maximum scaling increase (default: 0.5 = +50%)
    public let maxScalingIncrease: Double
    
    /// Glucose range for full scaling (mg/dL above target)
    public let glucoseRangeForScaling: Double
    
    /// Whether provider is enabled
    public let isEnabled: Bool
    
    public init(
        maxScalingIncrease: Double = 0.5,
        glucoseRangeForScaling: Double = 150.0,
        isEnabled: Bool = true
    ) {
        self.maxScalingIncrease = maxScalingIncrease
        self.glucoseRangeForScaling = glucoseRangeForScaling
        self.isEnabled = isEnabled
    }
    
    public func adjustedTempBasal(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult? {
        guard isEnabled else { return nil }
        guard let currentGlucose = inputs.glucose.last?.glucose else { return nil }
        
        // Only apply when above target
        guard currentGlucose > target else {
            return MLDosingResult(
                tempBasalRate: baseline.rate,
                scalingFactor: 1.0,
                reason: "Below target - no scaling"
            )
        }
        
        // Linear scaling from 1.0 to 1.0+maxScalingIncrease
        let scalingFactor = 1 + maxScalingIncrease *
            min((currentGlucose - target) / glucoseRangeForScaling, 1.0)
        
        return MLDosingResult(
            tempBasalRate: baseline.rate * scalingFactor,
            scalingFactor: scalingFactor,
            reason: String(format: "Dynamic ISF: %.2fx at %.0f mg/dL", scalingFactor, currentGlucose)
        )
    }
}

// MARK: - ML Algorithm Placeholder

/// Placeholder for future DNN-based dosing
/// Source: GlucOS DNNDosing (weights not included)
public struct DNNDosingProvider: MLDosingProvider, Sendable {
    
    public let isEnabled: Bool = false
    
    public init() {}
    
    public func adjustedTempBasal(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult? {
        // Placeholder - DNN weights not available
        // Would load CoreML model and run inference
        return nil
    }
}

// MARK: - Composite Provider

/// Combines multiple ML providers with fallback
public struct CompositeMLDosingProvider: MLDosingProvider, Sendable {
    
    private let providers: [any MLDosingProvider]
    
    public var isEnabled: Bool {
        providers.contains { $0.isEnabled }
    }
    
    public init(providers: [any MLDosingProvider]) {
        self.providers = providers
    }
    
    public func adjustedTempBasal(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult? {
        // Try each provider in order, return first valid result
        for provider in providers {
            if let result = await provider.adjustedTempBasal(
                baseline: baseline,
                inputs: inputs,
                target: target
            ) {
                return result
            }
        }
        return nil
    }
}
