// ComparisonConfig.swift
// T1PalAlgorithm
//
// ALG-REFACTOR-004: Extract comparison configuration with sensible defaults.
// Centralizes tolerance thresholds for algorithm comparison.

import Foundation

/// Configuration for algorithm comparison tolerances.
///
/// Default values are calibrated for Loop algorithm parity:
/// - IOB tolerance: ±0.01 U (insulin units)
/// - Prediction MAE tolerance: 2.0 mg/dL
/// - Dosing tolerance: 0.01 U/hr for temp basals, 0.001 U for boluses
/// - Gap tolerance: 360 seconds (6 minutes between Loop cycles)
public struct ComparisonConfig: Sendable {
    
    // MARK: - IOB Comparison
    
    /// Maximum acceptable IOB delta in Units (default: 0.01 U)
    public var iobTolerance: Double
    
    // MARK: - Prediction Comparison
    
    /// Maximum acceptable MAE in mg/dL (default: 2.0)
    public var maeTolerance: Double
    
    /// Maximum acceptable eventual glucose delta in mg/dL (default: 10.0)
    public var eventualGlucoseTolerance: Double
    
    // MARK: - Dosing Comparison
    
    /// Maximum acceptable temp basal rate delta in U/hr (default: 0.01)
    public var tempBasalTolerance: Double
    
    /// Maximum acceptable bolus delta in U (default: 0.001)
    public var bolusTolerance: Double
    
    // MARK: - Gap Detection
    
    /// Maximum acceptable gap between Loop cycles in seconds (default: 360 = 6 min)
    public var gapTolerance: TimeInterval
    
    // MARK: - Significance Classification
    
    /// MAE threshold for "minor" significance (default: 3.0 mg/dL)
    public var minorMAEThreshold: Double
    
    /// MAE threshold for "moderate" significance (default: 5.0 mg/dL)
    public var moderateMAEThreshold: Double
    
    /// MAE threshold for "major" significance (default: 10.0 mg/dL)
    public var majorMAEThreshold: Double
    
    // MARK: - Initialization
    
    /// Create a comparison config with custom tolerances.
    public init(
        iobTolerance: Double = 0.01,
        maeTolerance: Double = 2.0,
        eventualGlucoseTolerance: Double = 10.0,
        tempBasalTolerance: Double = 0.01,
        bolusTolerance: Double = 0.001,
        gapTolerance: TimeInterval = 360,
        minorMAEThreshold: Double = 3.0,
        moderateMAEThreshold: Double = 5.0,
        majorMAEThreshold: Double = 10.0
    ) {
        self.iobTolerance = iobTolerance
        self.maeTolerance = maeTolerance
        self.eventualGlucoseTolerance = eventualGlucoseTolerance
        self.tempBasalTolerance = tempBasalTolerance
        self.bolusTolerance = bolusTolerance
        self.gapTolerance = gapTolerance
        self.minorMAEThreshold = minorMAEThreshold
        self.moderateMAEThreshold = moderateMAEThreshold
        self.majorMAEThreshold = majorMAEThreshold
    }
    
    /// Default configuration with Loop-parity tolerances.
    public static let `default` = ComparisonConfig()
    
    /// Strict configuration for zero-divergence validation.
    public static let strict = ComparisonConfig(
        iobTolerance: 0.001,
        maeTolerance: 1.0,
        eventualGlucoseTolerance: 5.0,
        tempBasalTolerance: 0.001,
        bolusTolerance: 0.0001
    )
    
    /// Relaxed configuration for exploratory comparison.
    public static let relaxed = ComparisonConfig(
        iobTolerance: 0.1,
        maeTolerance: 5.0,
        eventualGlucoseTolerance: 20.0,
        tempBasalTolerance: 0.1,
        bolusTolerance: 0.01
    )
}

// MARK: - Codable Support

extension ComparisonConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case iobTolerance
        case maeTolerance
        case eventualGlucoseTolerance
        case tempBasalTolerance
        case bolusTolerance
        case gapTolerance
        case minorMAEThreshold
        case moderateMAEThreshold
        case majorMAEThreshold
    }
}

// MARK: - Equatable Support

extension ComparisonConfig: Equatable {}
