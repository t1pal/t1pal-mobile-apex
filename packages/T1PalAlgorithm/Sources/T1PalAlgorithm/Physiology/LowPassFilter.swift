// LowPassFilter.swift
// T1PalAlgorithm
//
// Exponential low-pass filter for glucose smoothing
// Source: GlucOS PhysiologicalModels
// Trace: GLUCOS-IMPL-003, ADR-010

import Foundation
import T1PalCore

/// Exponential low-pass filter for glucose smoothing
/// Source: GlucOS PhysiologicalModels
///
/// The filter uses exponential smoothing with time constant τ:
/// - α = 1 - exp(-dt / τ)
/// - filtered = α × current + (1 - α) × previous
public struct LowPassFilter: Sendable {
    /// Time constant in seconds
    public let tau: TimeInterval
    
    /// Default time constant (11.3 minutes from GlucOS)
    public static let defaultTau: TimeInterval = 11.3 * 60
    
    public init(tau: TimeInterval = defaultTau) {
        self.tau = tau
    }
    
    /// Apply filter to glucose readings
    public func apply(to readings: [GlucoseReading]) -> [Double] {
        guard !readings.isEmpty else { return [] }
        
        // Sort by timestamp
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        
        var filtered: [Double] = []
        var lastFiltered = sorted[0].glucose
        var lastTime = sorted[0].timestamp
        
        for reading in sorted {
            let dt = reading.timestamp.timeIntervalSince(lastTime)
            
            // For first reading or same timestamp, use raw value
            if dt <= 0 {
                filtered.append(reading.glucose)
                continue
            }
            
            // Calculate smoothing factor
            let alpha = 1 - exp(-dt / tau)
            
            // Apply exponential filter
            lastFiltered = alpha * reading.glucose + (1 - alpha) * lastFiltered
            filtered.append(lastFiltered)
            lastTime = reading.timestamp
        }
        
        return filtered
    }
    
    /// Apply filter to raw values with timestamps
    public func apply(values: [Double], timestamps: [Date]) -> [Double] {
        guard values.count == timestamps.count, !values.isEmpty else { return [] }
        
        var filtered: [Double] = []
        var lastFiltered = values[0]
        var lastTime = timestamps[0]
        
        for i in 0..<values.count {
            let dt = timestamps[i].timeIntervalSince(lastTime)
            
            if dt <= 0 {
                filtered.append(values[i])
                continue
            }
            
            let alpha = 1 - exp(-dt / tau)
            lastFiltered = alpha * values[i] + (1 - alpha) * lastFiltered
            filtered.append(lastFiltered)
            lastTime = timestamps[i]
        }
        
        return filtered
    }
    
    /// Apply single step filter
    public func step(
        previous: Double,
        current: Double,
        dt: TimeInterval
    ) -> Double {
        guard dt > 0 else { return current }
        let alpha = 1 - exp(-dt / tau)
        return alpha * current + (1 - alpha) * previous
    }
}

/// Glucose rate of change calculator
/// Source: GlucOS PhysiologicalModels
public struct DeltaGlucoseCalculator: Sendable {
    /// Minimum readings needed for calculation
    public let minimumReadings: Int
    
    /// Maximum time span for calculation (seconds)
    public let maxTimeSpan: TimeInterval
    
    public init(
        minimumReadings: Int = 3,
        maxTimeSpan: TimeInterval = 30 * 60  // 30 minutes
    ) {
        self.minimumReadings = minimumReadings
        self.maxTimeSpan = maxTimeSpan
    }
    
    /// Calculate glucose rate of change (mg/dL per hour)
    public func calculate(from readings: [GlucoseReading]) -> Double? {
        guard readings.count >= minimumReadings else { return nil }
        
        // Sort by timestamp, most recent last
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        
        // Take recent readings within time span
        let cutoff = sorted.last!.timestamp.addingTimeInterval(-maxTimeSpan)
        let recent = sorted.filter { $0.timestamp >= cutoff }
        
        guard recent.count >= minimumReadings else { return nil }
        
        // Linear regression for slope
        let n = Double(recent.count)
        let baseTime = recent.first!.timestamp
        
        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0
        
        for reading in recent {
            let x = reading.timestamp.timeIntervalSince(baseTime) / 3600  // hours
            let y = reading.glucose
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return nil }
        
        // Slope in mg/dL per hour
        let slope = (n * sumXY - sumX * sumY) / denominator
        
        return slope
    }
    
    /// Calculate expected glucose delta given ISF and insulin
    public func expectedDelta(
        insulinOnBoard: Double,
        insulinSensitivity: Double,
        basalRate: Double,
        hours: Double = 1.0
    ) -> Double {
        // Expected glucose change = -ISF × (IOB - basal × hours)
        let netInsulin = insulinOnBoard - (basalRate * hours)
        return -insulinSensitivity * netInsulin
    }
    
    /// Calculate delta glucose error (actual - expected)
    public func deltaError(
        readings: [GlucoseReading],
        insulinOnBoard: Double,
        insulinSensitivity: Double,
        basalRate: Double
    ) -> Double? {
        guard let actualDelta = calculate(from: readings) else { return nil }
        let expected = expectedDelta(
            insulinOnBoard: insulinOnBoard,
            insulinSensitivity: insulinSensitivity,
            basalRate: basalRate
        )
        return actualDelta - expected
    }
}
