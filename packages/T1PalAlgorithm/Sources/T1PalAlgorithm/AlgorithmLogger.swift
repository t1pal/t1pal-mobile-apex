// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmLogger.swift
// T1PalAlgorithm
//
// Unified logging for algorithm operations using os.Logger.
// Provides structured diagnostics for predictions, dosing, and safety checks.
// Trace: LOGGING-004, PRD-003

import Foundation

#if canImport(os)
import os

// MARK: - Algorithm Logging Categories

/// Logger instances for Algorithm subsystem diagnostics
public struct AlgorithmLogger {
    /// Subsystem identifier for T1PalAlgorithm
    private static let subsystem = "com.t1pal.algorithm"
    
    /// General algorithm operations (init, config, loop cycles)
    public static let general = Logger(subsystem: subsystem, category: "algorithm")
    
    /// Glucose prediction calculations
    public static let predictions = Logger(subsystem: subsystem, category: "algorithm.predictions")
    
    /// Dose recommendations (temp basal, SMB, bolus)
    public static let dosing = Logger(subsystem: subsystem, category: "algorithm.dosing")
    
    /// Insulin calculations (IOB, insulin on board)
    public static let insulin = Logger(subsystem: subsystem, category: "algorithm.insulin")
    
    /// Carb calculations (COB, carbs on board)
    public static let carbs = Logger(subsystem: subsystem, category: "algorithm.carbs")
    
    /// Safety limits and guardrails
    public static let safety = Logger(subsystem: subsystem, category: "algorithm.safety")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log algorithm loop start
    func loopStart(iteration: Int) {
        self.info("Loop iteration \(iteration) starting")
    }
    
    /// Log algorithm loop completion
    func loopComplete(iteration: Int, duration: TimeInterval) {
        let ms = Int(duration * 1000)
        self.info("Loop iteration \(iteration) complete in \(ms)ms")
    }
    
    /// Log glucose prediction
    func prediction(eventualBG: Double, minBG: Double, maxBG: Double) {
        self.info("Prediction: eventual=\(String(format: "%.1f", eventualBG)) min=\(String(format: "%.1f", minBG)) max=\(String(format: "%.1f", maxBG))")
    }
    
    /// Log dose recommendation
    func doseRecommendation(type: String, rate: Double, duration: Double?) {
        if let dur = duration {
            self.info("Dose: \(type, privacy: .public) rate=\(String(format: "%.3f", rate)) duration=\(String(format: "%.0f", dur))min")
        } else {
            self.info("Dose: \(type, privacy: .public) rate=\(String(format: "%.3f", rate))")
        }
    }
    
    /// Log SMB recommendation
    func smbRecommendation(units: Double, reason: String) {
        self.info("SMB: \(String(format: "%.2f", units))U - \(reason, privacy: .public)")
    }
    
    /// Log insulin on board
    func iob(value: Double, basalIOB: Double, bolusIOB: Double) {
        self.info("IOB: total=\(String(format: "%.2f", value))U basal=\(String(format: "%.2f", basalIOB))U bolus=\(String(format: "%.2f", bolusIOB))U")
    }
    
    /// Log carbs on board
    func cob(value: Double, absorbed: Double, remaining: Double) {
        self.info("COB: total=\(String(format: "%.1f", value))g absorbed=\(String(format: "%.1f", absorbed))g remaining=\(String(format: "%.1f", remaining))g")
    }
    
    /// Log safety limit enforcement
    func safetyLimit(type: String, original: Double, limited: Double, reason: String) {
        self.warning("Safety limit: \(type, privacy: .public) \(String(format: "%.3f", original)) → \(String(format: "%.3f", limited)) - \(reason, privacy: .public)")
    }
    
    /// Log safety check passed
    func safetyCheck(check: String, passed: Bool) {
        if passed {
            self.debug("Safety check passed: \(check, privacy: .public)")
        } else {
            self.warning("Safety check failed: \(check, privacy: .public)")
        }
    }
    
    /// Log algorithm error
    func algorithmError(phase: String, error: String) {
        self.error("Algorithm error in \(phase, privacy: .public): \(error, privacy: .public)")
    }
}

#else
// MARK: - Linux Fallback Logger

/// Fallback logger for Linux (no os.Logger available)
public struct FallbackLogger: Sendable {
    private let category: String
    
    init(category: String) {
        self.category = category
    }
    
    public func info(_ message: String) {
        print("[\(category)] INFO: \(message)")
    }
    
    public func debug(_ message: String) {
        #if DEBUG
        print("[\(category)] DEBUG: \(message)")
        #endif
    }
    
    public func warning(_ message: String) {
        print("[\(category)] WARNING: \(message)")
    }
    
    public func error(_ message: String) {
        print("[\(category)] ERROR: \(message)")
    }
    
    // Convenience methods matching Logger extensions
    func loopStart(iteration: Int) {
        info("Loop iteration \(iteration) starting")
    }
    
    func loopComplete(iteration: Int, duration: TimeInterval) {
        let ms = Int(duration * 1000)
        info("Loop iteration \(iteration) complete in \(ms)ms")
    }
    
    func prediction(eventualBG: Double, minBG: Double, maxBG: Double) {
        info("Prediction: eventual=\(String(format: "%.1f", eventualBG)) min=\(String(format: "%.1f", minBG)) max=\(String(format: "%.1f", maxBG))")
    }
    
    func doseRecommendation(type: String, rate: Double, duration: Double?) {
        if let dur = duration {
            info("Dose: \(type) rate=\(String(format: "%.3f", rate)) duration=\(String(format: "%.0f", dur))min")
        } else {
            info("Dose: \(type) rate=\(String(format: "%.3f", rate))")
        }
    }
    
    func smbRecommendation(units: Double, reason: String) {
        info("SMB: \(String(format: "%.2f", units))U - \(reason)")
    }
    
    func iob(value: Double, basalIOB: Double, bolusIOB: Double) {
        info("IOB: total=\(String(format: "%.2f", value))U basal=\(String(format: "%.2f", basalIOB))U bolus=\(String(format: "%.2f", bolusIOB))U")
    }
    
    func cob(value: Double, absorbed: Double, remaining: Double) {
        info("COB: total=\(String(format: "%.1f", value))g absorbed=\(String(format: "%.1f", absorbed))g remaining=\(String(format: "%.1f", remaining))g")
    }
    
    func safetyLimit(type: String, original: Double, limited: Double, reason: String) {
        warning("Safety limit: \(type) \(String(format: "%.3f", original)) → \(String(format: "%.3f", limited)) - \(reason)")
    }
    
    func safetyCheck(check: String, passed: Bool) {
        if passed {
            debug("Safety check passed: \(check)")
        } else {
            warning("Safety check failed: \(check)")
        }
    }
    
    func algorithmError(phase: String, error: String) {
        self.error("Algorithm error in \(phase): \(error)")
    }
}

/// Logger instances for Algorithm subsystem diagnostics (Linux fallback)
public struct AlgorithmLogger {
    /// General algorithm operations (init, config, loop cycles)
    public static let general = FallbackLogger(category: "algorithm")
    
    /// Glucose prediction calculations
    public static let predictions = FallbackLogger(category: "algorithm.predictions")
    
    /// Dose recommendations (temp basal, SMB, bolus)
    public static let dosing = FallbackLogger(category: "algorithm.dosing")
    
    /// Insulin calculations (IOB, insulin on board)
    public static let insulin = FallbackLogger(category: "algorithm.insulin")
    
    /// Carb calculations (COB, carbs on board)
    public static let carbs = FallbackLogger(category: "algorithm.carbs")
    
    /// Safety limits and guardrails
    public static let safety = FallbackLogger(category: "algorithm.safety")
}
#endif
