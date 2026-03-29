// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLSafetyService.swift
// T1Pal Mobile
//
// Safety bounds for ML-based dosing
// Source: GlucOS SafetyService
// Trace: GLUCOS-IMPL-005, ADR-010

import Foundation

// MARK: - Bounded Result

/// Result of safety bounding calculation
public struct BoundedResult: Sendable {
    /// Final temp basal rate after bounding (U/hr)
    public let tempBasal: Double
    
    /// ML insulin delta in last 3 hours (units)
    public let mlInsulinLast3Hours: Double
    
    /// Upper bound remaining (units)
    public let upperBoundRemaining: Double
    
    /// Lower bound remaining (units)
    public let lowerBoundRemaining: Double
    
    /// Was the result clamped by safety bounds?
    public let wasClamped: Bool
    
    public init(
        tempBasal: Double,
        mlInsulinLast3Hours: Double,
        upperBoundRemaining: Double,
        lowerBoundRemaining: Double,
        wasClamped: Bool
    ) {
        self.tempBasal = tempBasal
        self.mlInsulinLast3Hours = mlInsulinLast3Hours
        self.upperBoundRemaining = upperBoundRemaining
        self.lowerBoundRemaining = lowerBoundRemaining
        self.wasClamped = wasClamped
    }
}

// MARK: - Delivery Record

/// Record of ML insulin delivery for tracking
public struct MLDeliveryRecord: Codable, Sendable {
    public let timestamp: Date
    public let mlDelta: Double  // Units delivered above/below baseline
    public let duration: TimeInterval
    
    public init(timestamp: Date, mlDelta: Double, duration: TimeInterval) {
        self.timestamp = timestamp
        self.mlDelta = mlDelta
        self.duration = duration
    }
}

// MARK: - Protocol

/// Safety bounds for ML-based dosing
/// Limits ML insulin delta to ±(maxBasal × timeHorizon) over rolling window
/// Source: GlucOS SafetyService
public protocol MLSafetyBoundsProtocol: Sendable {
    /// Bound ML recommendation within safety limits
    func bound(
        mlRecommendation: Double,
        physiologicalBaseline: Double,
        duration: TimeInterval,
        maxBasalRate: Double,
        at date: Date
    ) async -> BoundedResult
    
    /// Record actual insulin delivered for tracking
    func recordDelivery(
        at date: Date,
        programmedTempBasal: Double,
        safetyBaseline: Double,
        mlRecommendation: Double,
        duration: TimeInterval
    ) async
}

// MARK: - Implementation

/// 3-hour rolling window ML safety bounds
/// Source: GlucOS SafetyService
public actor MLSafetyService: MLSafetyBoundsProtocol {
    
    // MARK: - Configuration
    
    /// Rolling window for tracking (default: 3 hours)
    public let timeHorizon: TimeInterval
    
    /// Maximum records to keep
    private let maxRecords = 500
    
    // MARK: - State
    
    private var deliveryHistory: [MLDeliveryRecord] = []
    
    // MARK: - Init
    
    public init(timeHorizon: TimeInterval = 3 * 60 * 60) {
        self.timeHorizon = timeHorizon
    }
    
    // MARK: - Public
    
    public func bound(
        mlRecommendation: Double,
        physiologicalBaseline: Double,
        duration: TimeInterval,
        maxBasalRate: Double,
        at date: Date
    ) -> BoundedResult {
        // Calculate historical ML insulin delta
        let start = date.addingTimeInterval(-timeHorizon)
        let historicalMLInsulin = deliveryHistory
            .filter { $0.timestamp >= start && $0.timestamp < date }
            .reduce(0) { $0 + $1.mlDelta }
        
        // Calculate bounds based on max basal rate
        // Bound = maxBasalRate (U/hr) × timeHorizon (hours) = total units
        let safetyBoundsUnits = maxBasalRate * (timeHorizon / 3600)
        
        // Upper bound: cannot exceed safetyBounds - historical
        // But upper bound can't go below 0 (can always give less insulin)
        let upperBound = max(safetyBoundsUnits - historicalMLInsulin, 0)
        
        // Lower bound: cannot go below -safetyBounds - historical
        // But lower bound can't go above 0 (can always give more insulin)
        let lowerBound = min(-safetyBoundsUnits - historicalMLInsulin, 0)
        
        // Convert recommendations to units for this delivery
        let mlUnits = mlRecommendation * duration / 3600
        let baselineUnits = physiologicalBaseline * duration / 3600
        let deltaUnits = mlUnits - baselineUnits
        
        // Clamp delta within bounds
        let clampedDelta = max(lowerBound, min(upperBound, deltaUnits))
        let wasClamped = abs(clampedDelta - deltaUnits) > 0.001
        
        // Convert back to temp basal rate
        let clampedTempBasal = physiologicalBaseline + (clampedDelta * 3600 / duration)
        
        return BoundedResult(
            tempBasal: max(0, clampedTempBasal),  // Never negative
            mlInsulinLast3Hours: historicalMLInsulin,
            upperBoundRemaining: upperBound - clampedDelta,
            lowerBoundRemaining: lowerBound - clampedDelta,
            wasClamped: wasClamped
        )
    }
    
    public func recordDelivery(
        at date: Date,
        programmedTempBasal: Double,
        safetyBaseline: Double,
        mlRecommendation: Double,
        duration: TimeInterval
    ) {
        // Calculate actual ML delta that was delivered
        let programmedUnits = programmedTempBasal * duration / 3600
        let baselineUnits = safetyBaseline * duration / 3600
        let mlDelta = programmedUnits - baselineUnits
        
        let record = MLDeliveryRecord(
            timestamp: date,
            mlDelta: mlDelta,
            duration: duration
        )
        
        deliveryHistory.append(record)
        pruneHistory(before: date.addingTimeInterval(-timeHorizon))
    }
    
    // MARK: - Private
    
    private func pruneHistory(before date: Date) {
        deliveryHistory.removeAll { $0.timestamp < date }
        
        // Also enforce max records
        if deliveryHistory.count > maxRecords {
            deliveryHistory = Array(deliveryHistory.suffix(maxRecords))
        }
    }
    
    // MARK: - Testing
    
    /// Clear history (for testing)
    public func clearHistory() {
        deliveryHistory.removeAll()
    }
    
    /// Get current history count (for testing)
    public var historyCount: Int {
        deliveryHistory.count
    }
}

// MARK: - Biological Invariant

/// Monitors for unexpected glucose drops indicating external factors
/// Source: GlucOS PhysiologicalModels.deltaGlucoseError
public struct BiologicalInvariantMonitor: Sendable {
    
    /// Threshold for violation (mg/dL/hr) - triggers emergency shutoff
    public let violationThreshold: Double
    
    /// Threshold for digestion (mg/dL/hr) - ignore high errors during meals
    public let digestionThreshold: Double
    
    public init(
        violationThreshold: Double = -35.0,
        digestionThreshold: Double = 40.0
    ) {
        self.violationThreshold = violationThreshold
        self.digestionThreshold = digestionThreshold
    }
    
    /// Calculate glucose change error (actual - expected)
    /// Returns nil if insufficient data or during digestion
    public func deltaGlucoseError(
        readings: [GlucoseReading],
        insulinOnBoard: Double,
        insulinSensitivity: Double
    ) -> Double? {
        // Need at least 5 readings (25 minutes at 5-min intervals)
        guard readings.count >= 5 else { return nil }
        
        let recent = Array(readings.suffix(5))
        guard let first = recent.first, let last = recent.last else { return nil }
        
        // Calculate actual glucose change rate (mg/dL per hour)
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        guard duration > 0 else { return nil }
        
        let actualDeltaPerHour = (last.glucose - first.glucose) * 3600 / duration
        
        // Calculate theoretical glucose change from IOB
        // Simplified model: glucose change = -IOB × ISF per hour
        let theoreticalDeltaPerHour = -insulinOnBoard * insulinSensitivity
        
        let error = actualDeltaPerHour - theoreticalDeltaPerHour
        
        // Ignore during digestion (rapidly rising glucose)
        guard error < digestionThreshold else { return nil }
        
        return error
    }
    
    /// Check if biological invariant is violated
    public func isViolated(_ error: Double) -> Bool {
        return error < violationThreshold
    }
    
    /// Get emergency decision if invariant is violated
    public func emergencyDecision(
        error: Double,
        currentTime: Date
    ) -> AlgorithmDecision? {
        guard isViolated(error) else { return nil }
        
        return AlgorithmDecision(
            timestamp: currentTime,
            suggestedTempBasal: TempBasal(rate: 0, duration: 30 * 60),
            suggestedBolus: nil,
            reason: String(format: "Biological invariant violated (%.0f mg/dL/hr) - insulin suspended", error)
        )
    }
}

// MARK: - Import for GlucoseReading

import T1PalCore
