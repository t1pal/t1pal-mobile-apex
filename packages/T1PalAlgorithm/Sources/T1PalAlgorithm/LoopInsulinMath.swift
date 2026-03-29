// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopInsulinMath.swift
// T1Pal Mobile
//
// Loop-compatible insulin activity curves
// Requirements: REQ-ALGO-006
//
// Based on Loop's InsulinMath:
// https://github.com/LoopKit/LoopKit/blob/main/LoopKit/InsulinKit/InsulinMath.swift
//
// Trace: ALG-015, PRD-009

import Foundation

// MARK: - Insulin Model Type

/// Loop-compatible insulin model types
public enum LoopInsulinModelType: String, Codable, Sendable, CaseIterable {
    /// Walsh model - traditional rapid-acting curve
    case walsh
    
    /// Exponential model for Humalog/Novolog (rapid-acting)
    case rapidActingAdult
    
    /// Exponential model for children (faster absorption)
    case rapidActingChild
    
    /// Fiasp - ultra-rapid acting
    case fiasp
    
    /// Lyumjev - ultra-rapid acting lispro
    case lyumjev
    
    /// Afrezza - inhaled insulin
    case afrezza
    
    public var displayName: String {
        switch self {
        case .walsh: return "Walsh"
        case .rapidActingAdult: return "Rapid-Acting Adult"
        case .rapidActingChild: return "Rapid-Acting Child"
        case .fiasp: return "Fiasp"
        case .lyumjev: return "Lyumjev"
        case .afrezza: return "Afrezza"
        }
    }
    
    /// Default action duration in hours (matching Loop presets)
    public var defaultActionDuration: Double {
        switch self {
        case .walsh: return 6.0
        case .rapidActingAdult: return 6.0
        case .rapidActingChild: return 6.0
        case .fiasp: return 6.0          // T6-001: Fixed to match Loop (was 5.5)
        case .lyumjev: return 6.0        // T6-001: Fixed to match Loop (was 5.5)
        case .afrezza: return 5.0        // T6-001: Fixed to match Loop (was 3.0)
        }
    }
    
    /// Peak activity time in hours (matching Loop presets)
    public var peakActivityTime: Double {
        switch self {
        case .walsh: return 1.5
        case .rapidActingAdult: return 1.25       // 75 minutes
        case .rapidActingChild: return 65.0/60.0  // 65 minutes (T6-001 fix)
        case .fiasp: return 55.0/60.0             // 55 minutes
        case .lyumjev: return 55.0/60.0           // 55 minutes (T6-001 fix, was 50)
        case .afrezza: return 29.0/60.0           // 29 minutes (T6-001 fix, was 20)
        }
    }
}

// MARK: - Loop Insulin Model Protocol

/// Protocol for Loop-compatible insulin models
public protocol LoopInsulinModel: Sendable {
    /// Action duration in seconds
    var actionDuration: TimeInterval { get }
    
    /// Peak activity time in seconds
    var peakActivityTime: TimeInterval { get }
    
    /// Calculate percent of insulin remaining (IOB) at time t seconds after dose
    func percentEffectRemaining(at time: TimeInterval) -> Double
    
    /// Calculate insulin activity at time t seconds after dose
    func percentActivity(at time: TimeInterval) -> Double
}

// MARK: - Walsh Insulin Model

/// Walsh insulin model using bilinear activity curve
/// Based on the original insulin timing model
public struct WalshInsulinModel: LoopInsulinModel, Sendable {
    public let actionDuration: TimeInterval
    public let peakActivityTime: TimeInterval
    
    public init(actionDuration: TimeInterval = 6 * 3600) {
        self.actionDuration = actionDuration
        self.peakActivityTime = actionDuration / 4  // Peak at 25% of DIA
    }
    
    public func percentEffectRemaining(at time: TimeInterval) -> Double {
        guard time >= 0 else { return 1.0 }
        guard time < actionDuration else { return 0.0 }
        
        let hours = time / 3600
        let diaHours = actionDuration / 3600
        
        // Walsh curve - piecewise linear
        if hours <= 1.0 {
            return 1.0 - hours * 0.1
        } else if hours <= 2.0 {
            return 0.9 - (hours - 1.0) * 0.2
        } else if hours <= 3.0 {
            return 0.7 - (hours - 2.0) * 0.25
        } else if hours <= diaHours {
            return 0.45 * (1 - (hours - 3.0) / (diaHours - 3.0))
        }
        return 0.0
    }
    
    public func percentActivity(at time: TimeInterval) -> Double {
        guard time >= 0 && time < actionDuration else { return 0.0 }
        
        // Derivative of effect remaining (numerical approximation)
        let delta: TimeInterval = 60  // 1 minute
        let before = percentEffectRemaining(at: max(0, time - delta/2))
        let after = percentEffectRemaining(at: min(actionDuration, time + delta/2))
        
        return max(0, (before - after) / delta * 3600)  // Per hour
    }
}

// MARK: - Exponential Insulin Model

/// Exponential insulin model used by Loop
/// Based on the Birnbaum-Saunders distribution
public struct ExponentialInsulinModel: LoopInsulinModel, Sendable {
    public let actionDuration: TimeInterval
    public let peakActivityTime: TimeInterval
    public let delay: TimeInterval  // T6-001: Added delay (10 min default like Loop)
    
    public init(
        actionDuration: TimeInterval = 6 * 3600,
        peakActivityTime: TimeInterval = 75 * 60,
        delay: TimeInterval = 10 * 60  // 10 minutes default, matching Loop
    ) {
        self.actionDuration = actionDuration
        self.peakActivityTime = peakActivityTime
        self.delay = delay
    }
    
    /// Total effect duration including delay
    public var effectDuration: TimeInterval {
        return actionDuration + delay
    }
    
    public func percentEffectRemaining(at time: TimeInterval) -> Double {
        // T6-001: Apply delay like Loop does
        let timeAfterDelay = time - delay
        
        // Before delay completes, full effect remains
        guard timeAfterDelay > 0 else { return 1.0 }
        // After action duration, no effect remains
        guard timeAfterDelay < actionDuration else { return 0.0 }
        
        // Loop's exact ExponentialInsulinModel formula
        // Reference: externals/LoopAlgorithm/Sources/LoopAlgorithm/Insulin/ExponentialInsulinModel.swift
        
        let t = timeAfterDelay  // Use time after delay
        let tp = peakActivityTime
        let td = actionDuration
        
        // Calculate tau, a, S coefficients (Loop formula)
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let S = 1 / (1 - a + (1 + a) * exp(-td / tau))
        
        // percentEffectRemaining formula from Loop
        let exponent = exp(-t / tau)
        let inner = ((t * t) / (tau * td * (1 - a)) - t / tau - 1) * exponent + 1
        let result = 1 - S * (1 - a) * inner
        
        return max(0, min(1, result))
    }
    
    public func percentActivity(at time: TimeInterval) -> Double {
        // T6-001: Apply delay like Loop does
        let timeAfterDelay = time - delay
        
        guard timeAfterDelay >= 0 && timeAfterDelay < actionDuration else { return 0.0 }
        
        let t = timeAfterDelay / 3600  // Convert to hours
        let tp = peakActivityTime / 3600
        let td = actionDuration / 3600
        
        // Calculate tau from peak time
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let tNorm = t / tau
        let tdNorm = td / tau
        
        // Activity = (t/tau^2) * exp(-t/tau), normalized to integrate to 1 over DIA
        let integralToEnd = 1 - (1 + tdNorm) * exp(-tdNorm)
        let activity = (tNorm / pow(tau, 2)) * exp(-tNorm) / integralToEnd
        
        return max(0, activity)
    }
}

// MARK: - Preset Models

extension ExponentialInsulinModel {
    /// Rapid-acting adult model (Humalog/Novolog)
    public static let rapidActingAdult = ExponentialInsulinModel(
        actionDuration: 6 * 3600,      // 6 hours
        peakActivityTime: 75 * 60      // 75 minutes
    )
    
    /// Rapid-acting child model (faster absorption)
    public static let rapidActingChild = ExponentialInsulinModel(
        actionDuration: 6 * 3600,      // 6 hours (360 min)
        peakActivityTime: 65 * 60      // 65 minutes (Loop preset)
    )
    
    /// Fiasp model (ultra-rapid)
    public static let fiasp = ExponentialInsulinModel(
        actionDuration: 6 * 3600,      // 6 hours (360 min, matching Loop)
        peakActivityTime: 55 * 60      // 55 minutes
    )
    
    /// Lyumjev model (ultra-rapid lispro)
    public static let lyumjev = ExponentialInsulinModel(
        actionDuration: 6 * 3600,      // 6 hours (360 min, matching Loop)
        peakActivityTime: 55 * 60      // 55 minutes (matching Loop)
    )
    
    /// Afrezza model (inhaled)
    public static let afrezza = ExponentialInsulinModel(
        actionDuration: 5 * 3600,      // 5 hours (300 min, matching Loop)
        peakActivityTime: 29 * 60      // 29 minutes (matching Loop)
    )
}

// MARK: - Loop IOB Calculator

/// Loop-compatible IOB calculator
public struct LoopIOBCalculator: Sendable {
    public let model: any LoopInsulinModel
    
    public init(model: any LoopInsulinModel) {
        self.model = model
    }
    
    public init(modelType: LoopInsulinModelType, actionDuration: TimeInterval? = nil) {
        let duration = actionDuration ?? modelType.defaultActionDuration * 3600
        let peak = modelType.peakActivityTime * 3600
        
        switch modelType {
        case .walsh:
            self.model = WalshInsulinModel(actionDuration: duration)
        default:
            self.model = ExponentialInsulinModel(
                actionDuration: duration,
                peakActivityTime: peak
            )
        }
    }
    
    /// Calculate IOB from a single dose
    public func insulinOnBoard(
        dose: InsulinDose,
        at date: Date = Date()
    ) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        guard elapsed >= 0 else { return dose.units }
        
        let remaining = model.percentEffectRemaining(at: elapsed)
        return dose.units * remaining
    }
    
    /// Calculate total IOB from multiple doses
    public func insulinOnBoard(
        doses: [InsulinDose],
        at date: Date = Date()
    ) -> Double {
        doses.reduce(0) { total, dose in
            total + insulinOnBoard(dose: dose, at: date)
        }
    }
    
    /// Calculate current insulin activity
    public func insulinActivity(
        dose: InsulinDose,
        at date: Date = Date()
    ) -> Double {
        let elapsed = date.timeIntervalSince(dose.timestamp)
        guard elapsed >= 0 else { return 0 }
        
        return dose.units * model.percentActivity(at: elapsed)
    }
    
    /// Calculate total insulin activity from multiple doses
    public func insulinActivity(
        doses: [InsulinDose],
        at date: Date = Date()
    ) -> Double {
        doses.reduce(0) { total, dose in
            total + insulinActivity(dose: dose, at: date)
        }
    }
    
    /// Project IOB over time
    public func projectIOB(
        doses: [InsulinDose],
        startDate: Date = Date(),
        duration: TimeInterval = 6 * 3600,
        interval: TimeInterval = 5 * 60
    ) -> [(date: Date, iob: Double)] {
        var results: [(date: Date, iob: Double)] = []
        var currentDate = startDate
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            let iob = insulinOnBoard(doses: doses, at: currentDate)
            results.append((date: currentDate, iob: iob))
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return results
    }
    
    /// Calculate insulin effect (BG drop) from IOB decay
    /// Returns array of (date, bgEffect) tuples
    public func insulinEffect(
        doses: [InsulinDose],
        insulinSensitivity: Double,  // mg/dL per unit
        startDate: Date = Date(),
        duration: TimeInterval = 6 * 3600,
        interval: TimeInterval = 5 * 60
    ) -> [(date: Date, effect: Double)] {
        var results: [(date: Date, effect: Double)] = []
        var previousIOB: Double?
        var currentDate = startDate
        var cumulativeEffect: Double = 0
        
        while currentDate <= startDate.addingTimeInterval(duration) {
            let currentIOB = insulinOnBoard(doses: doses, at: currentDate)
            
            if let prev = previousIOB {
                let iobDecay = prev - currentIOB
                let bgDrop = iobDecay * insulinSensitivity
                cumulativeEffect += bgDrop
            }
            
            results.append((date: currentDate, effect: cumulativeEffect))
            previousIOB = currentIOB
            currentDate = currentDate.addingTimeInterval(interval)
        }
        
        return results
    }
}

// MARK: - Model Factory

/// Factory for creating insulin models
public struct LoopInsulinModelFactory {
    
    /// Create a model from type
    public static func model(
        for type: LoopInsulinModelType,
        actionDuration: TimeInterval? = nil
    ) -> any LoopInsulinModel {
        let duration = actionDuration ?? type.defaultActionDuration * 3600
        
        switch type {
        case .walsh:
            return WalshInsulinModel(actionDuration: duration)
        case .rapidActingAdult:
            return ExponentialInsulinModel.rapidActingAdult
        case .rapidActingChild:
            return ExponentialInsulinModel.rapidActingChild
        case .fiasp:
            return ExponentialInsulinModel.fiasp
        case .lyumjev:
            return ExponentialInsulinModel.lyumjev
        case .afrezza:
            return ExponentialInsulinModel.afrezza
        }
    }
}
