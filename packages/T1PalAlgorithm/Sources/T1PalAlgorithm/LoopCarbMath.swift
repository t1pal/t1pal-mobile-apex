// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopCarbMath.swift
// T1Pal Mobile
//
// Loop-compatible carbohydrate absorption models
// Requirements: REQ-ALGO-009
//
// Based on Loop's CarbMath:
// https://github.com/LoopKit/LoopKit/blob/main/LoopKit/CarbKit/CarbMath.swift
//
// Trace: ALG-016, PRD-009

import Foundation

// MARK: - Absorption Model Type

/// Loop-compatible carb absorption model types
public enum LoopCarbAbsorptionModel: String, Codable, Sendable, CaseIterable {
    /// Linear absorption (constant rate)
    case linear
    
    /// Parabolic absorption (slower start and end, faster middle)
    case parabolic
    
    /// Piecewise linear (Loop's default model)
    case piecewiseLinear
    
    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .parabolic: return "Parabolic"
        case .piecewiseLinear: return "Piecewise Linear (Loop)"
        }
    }
}

// MARK: - Loop Carb Absorption Protocol

/// Protocol for Loop-compatible carb absorption models
public protocol LoopCarbAbsorption: Sendable {
    /// Calculate fraction absorbed at time t seconds after eating
    func fractionAbsorbed(at time: TimeInterval, absorptionTime: TimeInterval) -> Double
    
    /// Calculate absorption rate (fraction per second) at time t
    func absorptionRate(at time: TimeInterval, absorptionTime: TimeInterval) -> Double
}

extension LoopCarbAbsorption {
    /// Calculate fraction remaining (COB ratio)
    public func fractionRemaining(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        1.0 - fractionAbsorbed(at: time, absorptionTime: absorptionTime)
    }
}

// MARK: - Linear Absorption Model

/// Linear (constant rate) carb absorption
public struct LinearCarbAbsorption: LoopCarbAbsorption, Sendable {
    
    public init() {}
    
    public func fractionAbsorbed(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 else { return 0 }
        guard time < absorptionTime else { return 1.0 }
        return time / absorptionTime
    }
    
    public func absorptionRate(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 && time < absorptionTime else { return 0 }
        return 1.0 / absorptionTime
    }
}

// MARK: - Parabolic Absorption Model

/// Parabolic carb absorption (slower at start and end)
/// Based on the formula: absorbed(t) = 1 - (1 - t/T)^2 for 0 <= t <= T
public struct ParabolicCarbAbsorption: LoopCarbAbsorption, Sendable {
    
    public init() {}
    
    public func fractionAbsorbed(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 else { return 0 }
        guard time < absorptionTime else { return 1.0 }
        
        let t = time / absorptionTime
        // Parabolic: faster in the middle, slower at start/end
        // Uses a smooth S-curve approximation
        return t * (2 - t)  // = 1 - (1-t)^2
    }
    
    public func absorptionRate(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 && time < absorptionTime else { return 0 }
        
        let t = time / absorptionTime
        // Derivative of t*(2-t) = 2 - 2t, scaled by 1/T
        return (2 - 2 * t) / absorptionTime
    }
}

// MARK: - Piecewise Linear Absorption Model

/// Loop's piecewise linear absorption model
/// Uses a delay period followed by linear absorption
/// This matches Loop's default carb model behavior
public struct PiecewiseLinearCarbAbsorption: LoopCarbAbsorption, Sendable {
    
    /// Fraction of absorption time that is delay before absorption starts
    public let delayFraction: Double
    
    public init(delayFraction: Double = 0.167) {  // ~10 minutes for 1-hour absorption
        self.delayFraction = min(max(delayFraction, 0), 0.5)
    }
    
    public func fractionAbsorbed(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 else { return 0 }
        guard time < absorptionTime else { return 1.0 }
        
        let delayTime = absorptionTime * delayFraction
        
        if time < delayTime {
            // During delay, start with slow absorption (10% of normal rate)
            return (time / absorptionTime) * 0.1
        } else {
            // After delay, linear absorption of remaining
            let adjustedTime = time - delayTime
            let adjustedDuration = absorptionTime - delayTime
            let delayAbsorbed = delayFraction * 0.1
            let remainingToAbsorb = 1.0 - delayAbsorbed
            
            return delayAbsorbed + remainingToAbsorb * (adjustedTime / adjustedDuration)
        }
    }
    
    public func absorptionRate(at time: TimeInterval, absorptionTime: TimeInterval) -> Double {
        guard time >= 0 && time < absorptionTime else { return 0 }
        
        let delayTime = absorptionTime * delayFraction
        
        if time < delayTime {
            // Slow rate during delay
            return 0.1 / absorptionTime
        } else {
            // Normal rate after delay
            let adjustedDuration = absorptionTime - delayTime
            let remainingToAbsorb = 1.0 - (delayFraction * 0.1)
            return remainingToAbsorb / adjustedDuration
        }
    }
}

// MARK: - Loop COB Calculator

/// Loop-compatible COB calculator with multiple absorption models
public struct LoopCOBCalculator: Sendable {
    public let absorptionModel: any LoopCarbAbsorption
    
    public init(model: LoopCarbAbsorptionModel = .piecewiseLinear) {
        switch model {
        case .linear:
            self.absorptionModel = LinearCarbAbsorption()
        case .parabolic:
            self.absorptionModel = ParabolicCarbAbsorption()
        case .piecewiseLinear:
            self.absorptionModel = PiecewiseLinearCarbAbsorption()
        }
    }
    
    public init(absorptionModel: any LoopCarbAbsorption) {
        self.absorptionModel = absorptionModel
    }
    
    /// Calculate COB from a single carb entry
    public func carbsOnBoard(
        entry: CarbEntry,
        at date: Date = Date()
    ) -> Double {
        let elapsed = date.timeIntervalSince(entry.timestamp)
        guard elapsed >= 0 else { return entry.grams }
        
        let absorptionTime = entry.effectiveAbsorptionTime * 3600  // Convert to seconds
        let remaining = absorptionModel.fractionRemaining(at: elapsed, absorptionTime: absorptionTime)
        
        return entry.grams * remaining
    }
    
    /// Calculate total COB from multiple entries
    public func carbsOnBoard(
        entries: [CarbEntry],
        at date: Date = Date()
    ) -> Double {
        entries.reduce(0) { total, entry in
            total + carbsOnBoard(entry: entry, at: date)
        }
    }
    
    /// Calculate current carb absorption rate (grams/hour)
    public func absorptionRate(
        entry: CarbEntry,
        at date: Date = Date()
    ) -> Double {
        let elapsed = date.timeIntervalSince(entry.timestamp)
        guard elapsed >= 0 else { return 0 }
        
        let absorptionTime = entry.effectiveAbsorptionTime * 3600
        let ratePerSecond = absorptionModel.absorptionRate(at: elapsed, absorptionTime: absorptionTime)
        
        // Convert to grams per hour
        return entry.grams * ratePerSecond * 3600
    }
    
    /// Calculate total absorption rate from multiple entries
    public func absorptionRate(
        entries: [CarbEntry],
        at date: Date = Date()
    ) -> Double {
        entries.reduce(0) { total, entry in
            total + absorptionRate(entry: entry, at: date)
        }
    }
    
    /// Project COB over time
    public func projectCOB(
        entries: [CarbEntry],
        startDate: Date = Date(),
        duration: TimeInterval = 6 * 3600,
        interval: TimeInterval = 5 * 60
    ) -> [(date: Date, cob: Double)] {
        var results: [(date: Date, cob: Double)] = []
        var currentDate = startDate
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            let cob = carbsOnBoard(entries: entries, at: currentDate)
            results.append((date: currentDate, cob: cob))
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return results
    }
}

// MARK: - Carb Effect Calculator

/// Calculates glucose effect from carb absorption
public struct LoopCarbEffectCalculator: Sendable {
    public let cobCalculator: LoopCOBCalculator
    
    public init(absorptionModel: LoopCarbAbsorptionModel = .piecewiseLinear) {
        self.cobCalculator = LoopCOBCalculator(model: absorptionModel)
    }
    
    public init(cobCalculator: LoopCOBCalculator) {
        self.cobCalculator = cobCalculator
    }
    
    /// Calculate glucose effect from carb absorption
    /// Returns array of (date, bgEffect) tuples
    /// - Parameters:
    ///   - entries: Carb entries to calculate effect from
    ///   - carbRatio: Insulin-to-carb ratio (grams per unit)
    ///   - insulinSensitivity: ISF in mg/dL per unit
    ///   - startDate: Start time for calculation
    ///   - duration: Duration to project
    ///   - interval: Time interval between points
    public func glucoseEffect(
        entries: [CarbEntry],
        carbRatio: Double,
        insulinSensitivity: Double,
        startDate: Date = Date(),
        duration: TimeInterval = 6 * 3600,
        interval: TimeInterval = 5 * 60
    ) -> [(date: Date, effect: Double)] {
        var results: [(date: Date, effect: Double)] = []
        var previousCOB: Double?
        var currentDate = startDate
        var cumulativeEffect: Double = 0
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            let currentCOB = cobCalculator.carbsOnBoard(entries: entries, at: currentDate)
            
            if let prev = previousCOB {
                // Carbs absorbed since last interval
                let carbsAbsorbed = prev - currentCOB
                
                // Convert carbs to equivalent insulin effect
                // carbs / ICR = equivalent insulin units
                // equivalent insulin * ISF = BG rise
                let equivalentInsulin = carbsAbsorbed / carbRatio
                let bgRise = equivalentInsulin * insulinSensitivity
                
                cumulativeEffect += bgRise
            }
            
            results.append((date: currentDate, effect: cumulativeEffect))
            previousCOB = currentCOB
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return results
    }
    
    /// Calculate expected BG rise from a single carb entry
    /// - Parameters:
    ///   - entry: Carb entry
    ///   - carbRatio: ICR in grams per unit
    ///   - insulinSensitivity: ISF in mg/dL per unit
    /// - Returns: Expected total BG rise in mg/dL
    public func expectedBGRise(
        entry: CarbEntry,
        carbRatio: Double,
        insulinSensitivity: Double
    ) -> Double {
        // Total BG rise = (carbs / ICR) * ISF
        let equivalentInsulin = entry.grams / carbRatio
        return equivalentInsulin * insulinSensitivity
    }
    
    /// Calculate expected BG rise from multiple entries
    public func expectedBGRise(
        entries: [CarbEntry],
        carbRatio: Double,
        insulinSensitivity: Double
    ) -> Double {
        entries.reduce(0) { total, entry in
            total + expectedBGRise(entry: entry, carbRatio: carbRatio, insulinSensitivity: insulinSensitivity)
        }
    }
}

// MARK: - Dynamic Carb Absorption

/// Tracks observed vs expected absorption for dynamic adjustment
public struct DynamicCarbAbsorption: Sendable {
    
    /// Calculate observed absorption rate based on BG changes
    /// - Parameters:
    ///   - bgChange: Observed BG change in mg/dL
    ///   - duration: Time period in seconds
    ///   - insulinEffect: Expected insulin effect in mg/dL
    ///   - carbRatio: ICR in grams per unit
    ///   - insulinSensitivity: ISF in mg/dL per unit
    /// - Returns: Observed carb absorption rate in grams per hour
    public static func observedAbsorptionRate(
        bgChange: Double,
        duration: TimeInterval,
        insulinEffect: Double,
        carbRatio: Double,
        insulinSensitivity: Double
    ) -> Double {
        guard duration > 0, insulinSensitivity > 0, carbRatio > 0 else { return 0 }
        
        // Net BG effect from carbs = observed change - insulin effect
        let carbBGEffect = bgChange - insulinEffect
        
        // Convert BG effect to carbs: BG / ISF * ICR = carbs
        let carbsAbsorbed = (carbBGEffect / insulinSensitivity) * carbRatio
        
        // Convert to grams per hour
        let hours = duration / 3600
        return carbsAbsorbed / hours
    }
    
    /// Calculate absorption multiplier (observed / expected)
    public static func absorptionMultiplier(
        observedRate: Double,
        expectedRate: Double
    ) -> Double {
        guard expectedRate > 0 else { return 1.0 }
        return max(0.5, min(2.0, observedRate / expectedRate))  // Clamp to 0.5x - 2x
    }
}

// MARK: - Model Factory

/// Factory for creating carb absorption models
public struct LoopCarbModelFactory {
    
    /// Create an absorption model by type
    public static func model(for type: LoopCarbAbsorptionModel) -> any LoopCarbAbsorption {
        switch type {
        case .linear:
            return LinearCarbAbsorption()
        case .parabolic:
            return ParabolicCarbAbsorption()
        case .piecewiseLinear:
            return PiecewiseLinearCarbAbsorption()
        }
    }
}
