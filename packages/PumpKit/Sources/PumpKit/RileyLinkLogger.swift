// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RileyLinkLogger.swift
// PumpKit
//
// Unified logging for RileyLink RF layer operations.
// Provides structured diagnostics for RF communication with pumps.
// Trace: LOG-ADOPT-007, LOGGING-006

import Foundation

#if canImport(os)
import os

// MARK: - RileyLink Logging Categories

/// Logger instances for RileyLink RF layer diagnostics
public struct RileyLinkLogger {
    /// Subsystem identifier for RileyLink
    private static let subsystem = "com.t1pal.rileylink"
    
    /// General RF operations (init, config)
    public static let general = Logger(subsystem: subsystem, category: "rileylink")
    
    /// BLE connection to RileyLink device
    public static let connection = Logger(subsystem: subsystem, category: "rileylink.connection")
    
    /// RF packet transmission
    public static let tx = Logger(subsystem: subsystem, category: "rileylink.tx")
    
    /// RF packet reception
    public static let rx = Logger(subsystem: subsystem, category: "rileylink.rx")
    
    /// Signal strength and RF tuning
    public static let signal = Logger(subsystem: subsystem, category: "rileylink.signal")
    
    /// Pump communication protocol
    public static let protocol_ = Logger(subsystem: subsystem, category: "rileylink.protocol")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log RileyLink connection
    func rileyLinkConnected(name: String, rssi: Int) {
        self.info("RileyLink connected: \(name, privacy: .public) (RSSI: \(rssi))")
    }
    
    /// Log RileyLink disconnection
    func rileyLinkDisconnected(name: String) {
        self.info("RileyLink disconnected: \(name, privacy: .public)")
    }
    
    /// Log RF packet sent
    func packetSent(bytes: Int, frequency: Double) {
        self.debug("TX: \(bytes) bytes @ \(String(format: "%.2f", frequency)) MHz")
    }
    
    /// Log RF packet received
    func packetReceived(bytes: Int, rssi: Int) {
        self.debug("RX: \(bytes) bytes (RSSI: \(rssi))")
    }
    
    /// Log frequency tuning
    func frequencyTuned(frequency: Double, rssi: Int) {
        self.info("Tuned to \(String(format: "%.2f", frequency)) MHz (RSSI: \(rssi))")
    }
    
    /// Log RF communication error
    func rfError(operation: String, error: String) {
        self.error("RF error in \(operation, privacy: .public): \(error, privacy: .public)")
    }
    
    /// Log pump response timeout
    func pumpTimeout(command: String) {
        self.warning("Pump timeout: \(command, privacy: .public)")
    }
}

#else
// MARK: - Linux Fallback Logger

/// Fallback logger for Linux (no os.Logger available)
public struct RileyLinkFallbackLogger: Sendable {
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
    func rileyLinkConnected(name: String, rssi: Int) {
        info("RileyLink connected: \(name) (RSSI: \(rssi))")
    }
    
    func rileyLinkDisconnected(name: String) {
        info("RileyLink disconnected: \(name)")
    }
    
    func packetSent(bytes: Int, frequency: Double) {
        debug("TX: \(bytes) bytes @ \(String(format: "%.2f", frequency)) MHz")
    }
    
    func packetReceived(bytes: Int, rssi: Int) {
        debug("RX: \(bytes) bytes (RSSI: \(rssi))")
    }
    
    func frequencyTuned(frequency: Double, rssi: Int) {
        info("Tuned to \(String(format: "%.2f", frequency)) MHz (RSSI: \(rssi))")
    }
    
    func rfError(operation: String, error: String) {
        self.error("RF error in \(operation): \(error)")
    }
    
    func pumpTimeout(command: String) {
        warning("Pump timeout: \(command)")
    }
}

/// Logger instances for RileyLink RF layer diagnostics (Linux fallback)
public struct RileyLinkLogger {
    /// General RF operations (init, config)
    public static let general = RileyLinkFallbackLogger(category: "rileylink")
    
    /// BLE connection to RileyLink device
    public static let connection = RileyLinkFallbackLogger(category: "rileylink.connection")
    
    /// RF packet transmission
    public static let tx = RileyLinkFallbackLogger(category: "rileylink.tx")
    
    /// RF packet reception
    public static let rx = RileyLinkFallbackLogger(category: "rileylink.rx")
    
    /// Signal strength and RF tuning
    public static let signal = RileyLinkFallbackLogger(category: "rileylink.signal")
    
    /// Pump communication protocol
    public static let protocol_ = RileyLinkFallbackLogger(category: "rileylink.protocol")
}
#endif
