// AdaptiveTuningProvider.swift
// T1PalAlgorithm
//
// Protocol and types for adaptive parameter tuning
// Source: GlucOS AdaptiveSchedule pattern
// Trace: GLUCOS-IMPL-001, ADR-010

import Foundation

/// Adaptive parameter tuning over multiple timescales
/// Source: GlucOS AdaptiveSchedule pattern
/// Trace: GLUCOS-DES-002
public protocol AdaptiveTuningProvider: Sendable {
    /// Get adjusted ISF for current time based on learning
    func adjustedISF(
        baseISF: Double,
        at date: Date
    ) async -> AdaptedParameter
    
    /// Get adjusted carb ratio for current time
    func adjustedCarbRatio(
        baseRatio: Double,
        at date: Date
    ) async -> AdaptedParameter
    
    /// Record outcome for learning
    func recordOutcome(
        _ outcome: TuningOutcome
    ) async
    
    /// Whether tuning data is available
    var hasLearnedData: Bool { get async }
}

/// Result of adaptive parameter adjustment
public struct AdaptedParameter: Sendable, Equatable {
    /// Original value from profile
    public let baseValue: Double
    /// Adjusted value after tuning
    public let adjustedValue: Double
    /// Confidence in adjustment (0.0 - 1.0)
    public let confidence: Double
    /// Source of adjustment
    public let source: AdaptationSource
    
    public init(
        baseValue: Double,
        adjustedValue: Double,
        confidence: Double,
        source: AdaptationSource
    ) {
        self.baseValue = baseValue
        self.adjustedValue = adjustedValue
        self.confidence = confidence
        self.source = source
    }
    
    public enum AdaptationSource: String, Sendable, Equatable {
        case profile      // Using base profile value
        case learned      // Using learned adjustment
        case temporary    // Using temporary override
    }
    
    /// Create a pass-through parameter (no adjustment)
    public static func passThrough(_ value: Double) -> AdaptedParameter {
        AdaptedParameter(
            baseValue: value,
            adjustedValue: value,
            confidence: 1.0,
            source: .profile
        )
    }
}

/// Outcome data for adaptive learning
public struct TuningOutcome: Sendable, Codable {
    public let timestamp: Date
    public let timeBlock: Int  // 0-5 for 6-block schedule
    public let predictedGlucose: Double
    public let actualGlucose: Double
    public let insulinDelivered: Double
    public let carbsConsumed: Double
    
    public init(
        timestamp: Date,
        timeBlock: Int,
        predictedGlucose: Double,
        actualGlucose: Double,
        insulinDelivered: Double,
        carbsConsumed: Double
    ) {
        self.timestamp = timestamp
        self.timeBlock = timeBlock
        self.predictedGlucose = predictedGlucose
        self.actualGlucose = actualGlucose
        self.insulinDelivered = insulinDelivered
        self.carbsConsumed = carbsConsumed
    }
    
    /// Prediction error (actual - predicted)
    public var predictionError: Double {
        actualGlucose - predictedGlucose
    }
}
