// SPDX-License-Identifier: AGPL-3.0-or-later
//
// InsulinModel.swift
// T1Pal Mobile
//
// Insulin activity curves and IOB calculation
// Requirements: REQ-AID-003
//
// Based on oref0 exponential insulin model:
// https://github.com/openaps/oref0/blob/master/lib/iob/calculate.js

import Foundation

// MARK: - Insulin Types

/// Rapid-acting insulin types with their activity curves
public enum InsulinType: String, Codable, Sendable, CaseIterable {
    case fiasp = "fiasp"           // Faster-acting insulin aspart
    case lyumjev = "lyumjev"       // Faster-acting insulin lispro
    case humalog = "humalog"       // Insulin lispro
    case novolog = "novolog"       // Insulin aspart
    case apidra = "apidra"         // Insulin glulisine
    case afrezza = "afrezza"       // Inhaled insulin
    
    /// Duration of insulin action (DIA) in hours
    public var defaultDIA: Double {
        switch self {
        case .fiasp, .lyumjev:
            return 5.0   // Faster insulins
        case .afrezza:
            return 3.0   // Very fast inhaled
        case .humalog, .novolog, .apidra:
            return 6.0   // Standard rapid-acting
        }
    }
    
    /// Peak time in hours
    public var peakTime: Double {
        switch self {
        case .fiasp, .lyumjev:
            return 0.5   // 30 minutes
        case .afrezza:
            return 0.25  // 15 minutes
        case .humalog, .novolog, .apidra:
            return 1.0   // 60 minutes (varies by individual)
        }
    }
    
    public var displayName: String {
        switch self {
        case .fiasp: return "Fiasp"
        case .lyumjev: return "Lyumjev"
        case .humalog: return "Humalog"
        case .novolog: return "Novolog"
        case .apidra: return "Apidra"
        case .afrezza: return "Afrezza"
        }
    }
}

// MARK: - Insulin Dose

/// A record of insulin delivered
public struct InsulinDose: Codable, Sendable, Identifiable {
    public let id: UUID
    public let units: Double
    public let timestamp: Date
    public let type: InsulinType
    public let programmed: Double?  // If different from delivered
    public let source: String       // "pump", "pen", "manual"
    public let endDate: Date?       // ALG-PENDING-001: For temp basals with future delivery
    public let createdAt: Date?     // ALG-ZERO-DIV: When uploaded to NS (for temporal filtering)
    
    public init(
        id: UUID = UUID(),
        units: Double,
        timestamp: Date,
        endDate: Date? = nil,
        type: InsulinType = .novolog,
        programmed: Double? = nil,
        source: String = "manual",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.units = units
        self.timestamp = timestamp
        self.endDate = endDate
        self.type = type
        self.programmed = programmed
        self.source = source
        self.createdAt = createdAt
    }
}

// MARK: - Insulin Model

/// Insulin activity curve model
/// Uses exponential model from oref0/Loop
public struct InsulinModel: Sendable {
    public let insulinType: InsulinType
    public let dia: Double  // Duration of insulin action in hours
    
    public init(insulinType: InsulinType, dia: Double? = nil) {
        self.insulinType = insulinType
        self.dia = dia ?? insulinType.defaultDIA
    }
    
    /// Calculate insulin activity at time t (hours after dose)
    /// Returns fraction of dose that is active at time t
    public func activity(at t: Double) -> Double {
        guard t >= 0 && t <= dia else { return 0 }
        
        // Exponential model parameters
        let peak = insulinType.peakTime
        let tau = peak * (1 - peak / dia) / (1 - 2 * peak / dia)
        let a = 2 * tau / dia
        let s = 1 / (1 - a + (1 + a) * exp(-dia / tau))
        
        // Activity curve
        let activity = (s / pow(tau, 2)) * t * (1 - t / dia) * exp(-t / tau)
        return max(0, activity)
    }
    
    /// Calculate insulin on board (IOB) at time t (hours after dose)
    /// Returns fraction of dose remaining
    public func iob(at t: Double) -> Double {
        guard t >= 0 else { return 1.0 }
        guard t <= dia else { return 0 }
        
        // Integrate activity from t to dia
        // Using numerical approximation (Simpson's rule)
        let steps = 100
        let h = (dia - t) / Double(steps)
        var sum = activity(at: t) + activity(at: dia)
        
        for i in 1..<steps {
            let x = t + Double(i) * h
            let weight: Double = i % 2 == 0 ? 2 : 4
            sum += weight * activity(at: x)
        }
        
        return max(0, min(1, sum * h / 3))
    }
    
    /// Get IOB curve as array of values at 5-minute intervals
    public func iobCurve(intervalMinutes: Int = 5) -> [Double] {
        let intervals = Int(dia * 60 / Double(intervalMinutes))
        return (0...intervals).map { i in
            let hours = Double(i * intervalMinutes) / 60.0
            return iob(at: hours)
        }
    }
}

// MARK: - IOB Calculator

/// Calculates total IOB from multiple doses
public struct IOBCalculator: Sendable {
    public let model: InsulinModel
    
    public init(model: InsulinModel) {
        self.model = model
    }
    
    /// Calculate IOB from a single dose at a given time
    public func iobFromDose(_ dose: InsulinDose, at time: Date) -> Double {
        let hoursAgo = time.timeIntervalSince(dose.timestamp) / 3600
        guard hoursAgo >= 0 else { return dose.units }  // Future dose
        
        let remaining = model.iob(at: hoursAgo)
        return dose.units * remaining
    }
    
    /// Calculate total IOB from multiple doses
    public func totalIOB(from doses: [InsulinDose], at time: Date = Date()) -> Double {
        doses.reduce(0) { total, dose in
            total + iobFromDose(dose, at: time)
        }
    }
    
    /// Calculate IOB activity (insulin currently being absorbed)
    public func activity(from doses: [InsulinDose], at time: Date = Date()) -> Double {
        doses.reduce(0) { total, dose in
            let hoursAgo = time.timeIntervalSince(dose.timestamp) / 3600
            guard hoursAgo >= 0 else { return total }
            return total + dose.units * model.activity(at: hoursAgo)
        }
    }
    
    /// Project IOB over time (for predictions)
    public func projectIOB(from doses: [InsulinDose], 
                           startTime: Date = Date(),
                           durationMinutes: Int = 180,
                           intervalMinutes: Int = 5) -> [Double] {
        let intervals = durationMinutes / intervalMinutes
        return (0...intervals).map { i in
            let futureTime = startTime.addingTimeInterval(Double(i * intervalMinutes * 60))
            return totalIOB(from: doses, at: futureTime)
        }
    }
}
