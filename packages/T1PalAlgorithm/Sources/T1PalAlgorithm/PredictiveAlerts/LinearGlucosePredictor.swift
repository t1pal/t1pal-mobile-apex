// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LinearGlucosePredictor.swift
// T1Pal Mobile
//
// Linear regression glucose prediction
// Source: GlucOS PhysiologicalModels.predictGlucoseIn15Minutes
// Trace: GLUCOS-IMPL-002, ADR-010

import Foundation
import T1PalCore

/// Linear regression glucose predictor using least squares fit
/// Source: GlucOS PhysiologicalModels
public struct LinearGlucosePredictor: Sendable {
    
    /// Number of readings to use for regression (default: 5 = 25 minutes at 5-min intervals)
    public let windowSize: Int
    
    /// Default prediction horizon (15 minutes)
    public static let defaultHorizon: TimeInterval = 15 * 60
    
    public init(windowSize: Int = 5) {
        self.windowSize = max(2, windowSize)
    }
    
    /// Predict glucose at future time using linear regression
    /// - Parameters:
    ///   - readings: Recent glucose readings (sorted by timestamp ascending)
    ///   - horizon: Time in seconds to predict ahead (default: 15 minutes)
    /// - Returns: Predicted glucose value, or nil if insufficient data
    public func predict(
        from readings: [GlucoseReading],
        horizon: TimeInterval = defaultHorizon
    ) -> Double? {
        // Need at least 2 readings for regression
        guard readings.count >= 2 else { return nil }
        
        // Use last windowSize readings
        let recent = Array(readings.suffix(windowSize))
        guard let last = recent.last else { return nil }
        
        let now = last.timestamp
        
        // Convert to x (time offset from now) and y (glucose) arrays
        let x = recent.map { $0.timestamp.timeIntervalSince(now) }
        let y = recent.map { $0.glucose }
        
        // Least squares fit
        guard let (slope, intercept) = leastSquaresFit(x: x, y: y) else {
            return nil
        }
        
        // Predict at horizon
        let predicted = horizon * slope + intercept
        
        // Clamp to reasonable range (20-600 mg/dL)
        return max(20, min(600, predicted))
    }
    
    /// Calculate rate of change in mg/dL per minute
    /// - Parameter readings: Recent glucose readings
    /// - Returns: Rate of change, or nil if insufficient data
    public func rateOfChange(from readings: [GlucoseReading]) -> Double? {
        guard readings.count >= 2 else { return nil }
        
        let recent = Array(readings.suffix(windowSize))
        guard let last = recent.last else { return nil }
        
        let now = last.timestamp
        let x = recent.map { $0.timestamp.timeIntervalSince(now) / 60 } // Convert to minutes
        let y = recent.map { $0.glucose }
        
        guard let (slope, _) = leastSquaresFit(x: x, y: y) else {
            return nil
        }
        
        return slope // mg/dL per minute
    }
    
    // MARK: - Private
    
    /// Least squares linear regression
    /// Returns (slope, intercept) for y = slope * x + intercept
    private func leastSquaresFit(x: [Double], y: [Double]) -> (slope: Double, intercept: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)
        
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > .ulpOfOne else { return nil }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        
        guard !slope.isNaN && !intercept.isNaN else { return nil }
        return (slope, intercept)
    }
}

// MARK: - Prediction Result

/// Result of glucose prediction with confidence information
public struct GlucosePrediction: Sendable {
    /// Predicted glucose value (mg/dL)
    public let value: Double
    
    /// Prediction horizon (seconds from now)
    public let horizon: TimeInterval
    
    /// Rate of change used (mg/dL per minute)
    public let rateOfChange: Double
    
    /// Number of readings used for prediction
    public let readingsUsed: Int
    
    /// Timestamp of prediction
    public let timestamp: Date
    
    public init(
        value: Double,
        horizon: TimeInterval,
        rateOfChange: Double,
        readingsUsed: Int,
        timestamp: Date = Date()
    ) {
        self.value = value
        self.horizon = horizon
        self.rateOfChange = rateOfChange
        self.readingsUsed = readingsUsed
        self.timestamp = timestamp
    }
}

extension LinearGlucosePredictor {
    /// Predict with full result information
    public func predictWithDetails(
        from readings: [GlucoseReading],
        horizon: TimeInterval = defaultHorizon
    ) -> GlucosePrediction? {
        guard let predicted = predict(from: readings, horizon: horizon),
              let rate = rateOfChange(from: readings) else {
            return nil
        }
        
        return GlucosePrediction(
            value: predicted,
            horizon: horizon,
            rateOfChange: rate,
            readingsUsed: min(readings.count, windowSize)
        )
    }
}
