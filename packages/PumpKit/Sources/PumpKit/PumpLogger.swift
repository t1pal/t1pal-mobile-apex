// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpLogger.swift
// PumpKit
//
// Unified logging for pump operations using os.Logger.
// Provides structured diagnostics for pump commands and status.
// Trace: LOGGING-005, PRD-003

import Foundation

#if canImport(os)
import os

// MARK: - Pump Logging Categories

/// Logger instances for Pump subsystem diagnostics
public struct PumpLogger {
    /// Subsystem identifier for PumpKit
    private static let subsystem = "com.t1pal.pumpkit"
    
    /// General pump operations (init, config, status)
    public static let general = Logger(subsystem: subsystem, category: "pump")
    
    /// Bolus delivery operations
    public static let bolus = Logger(subsystem: subsystem, category: "pump.bolus")
    
    /// Basal operations (temp basal, scheduled basal)
    public static let basal = Logger(subsystem: subsystem, category: "pump.basal")
    
    /// Pump status and readings
    public static let status = Logger(subsystem: subsystem, category: "pump.status")
    
    /// BLE communication with pump bridge
    public static let communication = Logger(subsystem: subsystem, category: "pump.communication")
    
    /// Connection management (scanning, pairing)
    public static let connection = Logger(subsystem: subsystem, category: "pump.connection")
    
    /// Protocol operations (commands, responses)
    public static let protocol_ = Logger(subsystem: subsystem, category: "pump.protocol")
    
    /// Suspend/resume operations
    public static let delivery = Logger(subsystem: subsystem, category: "pump.delivery")
    
    /// History operations (MDT-PIPE-001)
    public static let history = Logger(subsystem: subsystem, category: "pump.history")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log bolus delivery
    func bolusDelivered(units: Double) {
        self.info("Bolus delivered: \(String(format: "%.2f", units))U")
    }
    
    /// Log bolus cancelled (RESEARCH-AID-005)
    func bolusCancelled() {
        self.info("Bolus cancelled")
    }
    
    /// Log bolus failed mid-delivery (BOLUS-011)
    func bolusFailed(error: PumpError) {
        self.error("Bolus failed: \(error.localizedDescription)")
    }
    
    /// Log temp basal set
    func tempBasalSet(rate: Double, duration: TimeInterval) {
        let minutes = Int(duration / 60)
        self.info("Temp basal set: \(String(format: "%.3f", rate)) U/hr for \(minutes) min")
    }
    
    /// Log temp basal cancelled
    func tempBasalCancelled() {
        self.info("Temp basal cancelled")
    }
    
    /// Log suspend
    func deliverySuspended() {
        self.info("Delivery suspended")
    }
    
    /// Log resume
    func deliveryResumed() {
        self.info("Delivery resumed")
    }
    
    /// Log reservoir status
    func reservoirStatus(remaining: Double) {
        self.info("Reservoir: \(String(format: "%.1f", remaining))U remaining")
    }
    
    /// Log pump error
    func pumpError(operation: String, error: String) {
        self.error("Pump error in \(operation, privacy: .public): \(error, privacy: .public)")
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
    
    // Convenience methods
    func bolusDelivered(units: Double) {
        info("Bolus delivered: \(String(format: "%.2f", units))U")
    }
    
    func bolusCancelled() {
        info("Bolus cancelled")
    }
    
    func bolusFailed(error: PumpError) {
        self.error("Bolus failed: \(error.localizedDescription)")
    }
    
    func tempBasalSet(rate: Double, duration: TimeInterval) {
        let minutes = Int(duration / 60)
        info("Temp basal set: \(String(format: "%.3f", rate)) U/hr for \(minutes) min")
    }
    
    func tempBasalCancelled() {
        info("Temp basal cancelled")
    }
    
    func deliverySuspended() {
        info("Delivery suspended")
    }
    
    func deliveryResumed() {
        info("Delivery resumed")
    }
    
    func reservoirStatus(remaining: Double) {
        info("Reservoir: \(String(format: "%.1f", remaining))U remaining")
    }
    
    func pumpError(operation: String, error: String) {
        self.error("Pump error in \(operation): \(error)")
    }
}

/// Logger instances for Pump subsystem diagnostics (Linux fallback)
public struct PumpLogger {
    /// General pump operations (init, config, status)
    public static let general = FallbackLogger(category: "pump")
    
    /// Bolus delivery operations
    public static let bolus = FallbackLogger(category: "pump.bolus")
    
    /// Basal operations (temp basal, scheduled basal)
    public static let basal = FallbackLogger(category: "pump.basal")
    
    /// Pump status and readings
    public static let status = FallbackLogger(category: "pump.status")
    
    /// BLE communication with pump bridge
    public static let communication = FallbackLogger(category: "pump.communication")
    
    /// Connection management (scanning, pairing)
    public static let connection = FallbackLogger(category: "pump.connection")
    
    /// Protocol operations (commands, responses)
    public static let protocol_ = FallbackLogger(category: "pump.protocol")
    
    /// Suspend/resume operations
    public static let delivery = FallbackLogger(category: "pump.delivery")
    
    /// History operations (MDT-PIPE-001)
    public static let history = FallbackLogger(category: "pump.history")
}
#endif
