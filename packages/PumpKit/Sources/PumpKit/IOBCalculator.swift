// SPDX-License-Identifier: AGPL-3.0-or-later
//
// IOBCalculator.swift
// PumpKit
//
// Insulin on board calculation for pump managers
// Requirements: REQ-AID-003, PUMP-INT-001
//
// Uses exponential insulin decay model compatible with oref0/Loop

import Foundation

// MARK: - Delivery Record

/// Record of insulin delivery for IOB tracking
public struct InsulinDeliveryRecord: Sendable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let units: Double
    public let type: DeliveryType
    
    public enum DeliveryType: String, Sendable, Codable {
        case bolus
        case tempBasal
        case scheduledBasal
    }
    
    public init(
        id: UUID = UUID(),
        timestamp: Date,
        units: Double,
        type: DeliveryType
    ) {
        self.id = id
        self.timestamp = timestamp
        self.units = units
        self.type = type
    }
}

// MARK: - IOB Calculator

/// Calculates insulin on board from delivery history
/// Uses exponential decay model with configurable DIA
public struct PumpIOBCalculator: Sendable {
    /// Duration of insulin action in hours (default: 5 hours)
    public let dia: Double
    
    /// Peak activity time in hours (default: 1.0 hour for rapid-acting)
    public let peakTime: Double
    
    public init(dia: Double = 5.0, peakTime: Double = 1.0) {
        self.dia = max(3.0, min(8.0, dia))  // Clamp to safe range
        self.peakTime = max(0.25, min(2.0, peakTime))
    }
    
    /// Calculate IOB fraction remaining at time t (hours after dose)
    /// Based on oref0 exponential model using numerical integration
    public func iobFraction(at t: Double) -> Double {
        guard t >= 0 else { return 1.0 }  // Future dose: full IOB
        guard t <= dia else { return 0.0 } // Past DIA: no IOB
        
        // Exponential model parameters (oref0 formula)
        let tau = peakTime * (1 - peakTime / dia) / (1 - 2 * peakTime / dia)
        let a = 2 * tau / dia
        let s = 1 / (1 - a + (1 + a) * exp(-dia / tau))
        
        // Activity function at time x
        func activity(_ x: Double) -> Double {
            guard x >= 0 && x <= dia else { return 0 }
            return (s / pow(tau, 2)) * x * (1 - x / dia) * exp(-x / tau)
        }
        
        // IOB = integral of activity from t to DIA (Simpson's rule)
        let steps = 100
        let h = (dia - t) / Double(steps)
        var sum = activity(t) + activity(dia)
        
        for i in 1..<steps {
            let x = t + Double(i) * h
            let weight: Double = i % 2 == 0 ? 2 : 4
            sum += weight * activity(x)
        }
        
        return max(0, min(1, sum * h / 3))
    }
    
    /// Calculate IOB from a single delivery record
    public func iobFromDelivery(_ record: InsulinDeliveryRecord, at time: Date) -> Double {
        let hoursAgo = time.timeIntervalSince(record.timestamp) / 3600.0
        return record.units * iobFraction(at: hoursAgo)
    }
    
    /// Calculate total IOB from delivery history
    public func totalIOB(from deliveries: [InsulinDeliveryRecord], at time: Date = Date()) -> Double {
        // Filter to deliveries within DIA window
        let cutoff = time.addingTimeInterval(-dia * 3600)
        let relevantDeliveries = deliveries.filter { $0.timestamp >= cutoff }
        
        return relevantDeliveries.reduce(0.0) { total, record in
            total + iobFromDelivery(record, at: time)
        }
    }
    
    /// Prune old deliveries (older than DIA + buffer)
    public func pruneDeliveries(_ deliveries: [InsulinDeliveryRecord], at time: Date = Date()) -> [InsulinDeliveryRecord] {
        let cutoff = time.addingTimeInterval(-(dia + 1) * 3600)  // DIA + 1 hour buffer
        return deliveries.filter { $0.timestamp >= cutoff }
    }
}

// MARK: - IOB Tracker

/// Tracks insulin deliveries for IOB calculation
/// Thread-safe actor for use in pump managers
public actor IOBTracker {
    private var deliveries: [InsulinDeliveryRecord] = []
    private let calculator: PumpIOBCalculator
    
    public init(dia: Double = 5.0, peakTime: Double = 1.0) {
        self.calculator = PumpIOBCalculator(dia: dia, peakTime: peakTime)
    }
    
    /// Record a bolus delivery
    public func recordBolus(units: Double, at time: Date = Date()) {
        let record = InsulinDeliveryRecord(
            timestamp: time,
            units: units,
            type: .bolus
        )
        deliveries.append(record)
        pruneOldDeliveries()
    }
    
    /// Record temp basal delivery (amount delivered, not rate)
    public func recordTempBasal(units: Double, at time: Date = Date()) {
        let record = InsulinDeliveryRecord(
            timestamp: time,
            units: units,
            type: .tempBasal
        )
        deliveries.append(record)
        pruneOldDeliveries()
    }
    
    /// Record scheduled basal delivery
    public func recordScheduledBasal(units: Double, at time: Date = Date()) {
        let record = InsulinDeliveryRecord(
            timestamp: time,
            units: units,
            type: .scheduledBasal
        )
        deliveries.append(record)
        pruneOldDeliveries()
    }
    
    /// Get current IOB
    public func currentIOB() -> Double {
        calculator.totalIOB(from: deliveries)
    }
    
    /// Get IOB at specific time
    public func iob(at time: Date) -> Double {
        calculator.totalIOB(from: deliveries, at: time)
    }
    
    /// Get all delivery records (for debugging/logging)
    public func allDeliveries() -> [InsulinDeliveryRecord] {
        deliveries
    }
    
    /// Clear all delivery history
    public func clearHistory() {
        deliveries = []
    }
    
    /// Prune deliveries older than DIA
    private func pruneOldDeliveries() {
        deliveries = calculator.pruneDeliveries(deliveries)
    }
}
