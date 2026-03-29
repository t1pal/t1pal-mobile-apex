// SPDX-License-Identifier: MIT
//
// AppLogger.swift
// T1PalCore
//
// Unified logging for T1Pal app operations using os.Logger.
// Provides structured diagnostics for UI, navigation, and debug events.
// 
// Moved from T1PalDebugKit in COMPL-ARCH-012 to remove BLE dependency chain
// from apps that only need logging (e.g., Follower).
//
// Trace: LOGGING-003, PRD-015, COMPL-ARCH-012

import Foundation

#if canImport(os)
import os

// MARK: - App Logging Categories

/// Logger instances for T1Pal app diagnostics
public struct AppLogger {
    /// Subsystem identifier for T1Pal
    private static let subsystem = "com.t1pal.core"
    
    /// General app operations (lifecycle, config)
    public static let general = Logger(subsystem: subsystem, category: "app")
    
    /// Navigation and screen events
    public static let navigation = Logger(subsystem: subsystem, category: "app.navigation")
    
    /// User actions (button taps, gestures)
    public static let userAction = Logger(subsystem: subsystem, category: "app.action")
    
    /// Debug/development features
    public static let debug = Logger(subsystem: subsystem, category: "app.debug")
    
    /// Demo mode events
    public static let demo = Logger(subsystem: subsystem, category: "app.demo")
    
    /// Performance metrics
    public static let performance = Logger(subsystem: subsystem, category: "app.performance")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log screen appeared
    public func screenAppeared(id: String, name: String) {
        self.info("Screen appeared: id=\(id, privacy: .public) name=\(name, privacy: .public)")
    }
    
    /// Log screen disappeared
    public func screenDisappeared(id: String, duration: TimeInterval) {
        let seconds = String(format: "%.1f", duration)
        self.info("Screen left: id=\(id, privacy: .public) duration=\(seconds, privacy: .public)s")
    }
    
    /// Log navigation push
    public func navigationPush(from: String, to: String) {
        self.info("Nav push: \(from, privacy: .public) → \(to, privacy: .public)")
    }
    
    /// Log navigation pop
    public func navigationPop(from: String, to: String) {
        self.info("Nav pop: \(from, privacy: .public) ← \(to, privacy: .public)")
    }
    
    /// Log user action
    public func userTapped(element: String, screen: String) {
        self.info("Tap: \(element, privacy: .public) on \(screen, privacy: .public)")
    }
    
    /// Log demo mode change
    public func demoModeChanged(enabled: Bool) {
        self.info("Demo mode: \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
    
    /// Log demo scenario loaded
    public func demoScenarioLoaded(name: String) {
        self.info("Demo scenario: \(name, privacy: .public)")
    }
    
    /// Log app launch
    public func appLaunched(version: String, build: String) {
        self.info("App launched: v\(version, privacy: .public) (\(build, privacy: .public))")
    }
    
    /// Log app became active
    public func appBecameActive() {
        self.info("App became active")
    }
    
    /// Log app entered background
    public func appEnteredBackground() {
        self.info("App entered background")
    }
    
    /// Log performance metric
    public func performanceMetric(name: String, value: Double, unit: String) {
        self.info("Perf: \(name, privacy: .public)=\(value, format: .fixed(precision: 2))\(unit, privacy: .public)")
    }
    
    /// Log debug feature used
    public func debugFeatureUsed(name: String) {
        self.debug("Debug feature: \(name, privacy: .public)")
    }
}

#else

// MARK: - Fallback for non-Darwin platforms

/// Fallback logger for Linux/other platforms using print
public struct AppLogger {
    public static let general = AppFallbackLogger(category: "app")
    public static let navigation = AppFallbackLogger(category: "app.navigation")
    public static let userAction = AppFallbackLogger(category: "app.action")
    public static let debug = AppFallbackLogger(category: "app.debug")
    public static let demo = AppFallbackLogger(category: "app.demo")
    public static let performance = AppFallbackLogger(category: "app.performance")
}

/// Simple fallback logger for non-Darwin platforms
public struct AppFallbackLogger {
    let category: String
    
    public func info(_ message: String) {
        #if DEBUG
        print("[\(category)] INFO: \(message)")
        #endif
    }
    
    public func error(_ message: String) {
        print("[\(category)] ERROR: \(message)")
    }
    
    public func debug(_ message: String) {
        #if DEBUG
        print("[\(category)] DEBUG: \(message)")
        #endif
    }
    
    public func warning(_ message: String) {
        print("[\(category)] WARNING: \(message)")
    }
    
    // Convenience methods for fallback
    public func screenAppeared(id: String, name: String) {
        info("Screen appeared: id=\(id) name=\(name)")
    }
    
    public func screenDisappeared(id: String, duration: TimeInterval) {
        info("Screen left: id=\(id) duration=\(String(format: "%.1f", duration))s")
    }
    
    public func navigationPush(from: String, to: String) {
        info("Nav push: \(from) → \(to)")
    }
    
    public func navigationPop(from: String, to: String) {
        info("Nav pop: \(from) ← \(to)")
    }
    
    public func userTapped(element: String, screen: String) {
        info("Tap: \(element) on \(screen)")
    }
    
    public func demoModeChanged(enabled: Bool) {
        info("Demo mode: \(enabled ? "enabled" : "disabled")")
    }
    
    public func demoScenarioLoaded(name: String) {
        info("Demo scenario: \(name)")
    }
    
    public func appLaunched(version: String, build: String) {
        info("App launched: v\(version) (\(build))")
    }
    
    public func appBecameActive() {
        info("App became active")
    }
    
    public func appEnteredBackground() {
        info("App entered background")
    }
    
    public func performanceMetric(name: String, value: Double, unit: String) {
        info("Perf: \(name)=\(String(format: "%.2f", value))\(unit)")
    }
    
    public func debugFeatureUsed(name: String) {
        debug("Debug feature: \(name)")
    }
}

#endif
