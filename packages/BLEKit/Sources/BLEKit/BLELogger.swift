// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLELogger.swift
// BLEKit
//
// Unified logging for BLE operations using os.Logger.
// Provides structured diagnostics for scan, connection, and discovery events.
// Trace: BLE-DIAG-001, PRD-008

import Foundation

#if canImport(os)
import os

// MARK: - BLE Logging Categories

/// Logger instances for BLE subsystem diagnostics
public struct BLELogger {
    /// Subsystem identifier for BLEKit
    private static let subsystem = "com.t1pal.blekit"
    
    /// General BLE operations (state changes, scan start/stop)
    public static let general = Logger(subsystem: subsystem, category: "ble")
    
    /// Device discovery events
    public static let discovery = Logger(subsystem: subsystem, category: "ble.discovery")
    
    /// Connection events (connect, disconnect, errors)
    public static let connection = Logger(subsystem: subsystem, category: "ble.connection")
    
    /// Service/characteristic discovery
    public static let services = Logger(subsystem: subsystem, category: "ble.services")
    
    /// Data transfer (read, write, notify)
    public static let data = Logger(subsystem: subsystem, category: "ble.data")
}

// MARK: - Syslog-Visible Logging
//
// iOS unified logging filters .info() and .debug() from syslog by default.
// Use .notice() for messages that MUST appear in pymobiledevice3 syslog captures.
// See: docs/backlogs/cgm.md "os.Logger not appearing" issue

extension Logger {
    /// Log at notice level - visible in syslog captures (pymobiledevice3, idevicesyslog)
    /// Use for key diagnostic events that need field debugging visibility
    @inlinable
    func bleDiagnostic(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log scan start with service filter info (notice level for syslog visibility)
    func scanStarted(services: [BLEUUID]?) {
        let serviceList = services?.map { $0.description }.joined(separator: ", ") ?? "all"
        self.notice("Scan started: services=[\(serviceList, privacy: .public)]")
    }
    
    /// Log scan stopped
    func scanStopped() {
        self.notice("Scan stopped")
    }
    
    /// Log device discovery (notice level for syslog visibility)
    func deviceDiscovered(name: String?, uuid: String, rssi: Int, services: [String]) {
        let deviceName = name ?? "unknown"
        let serviceList = services.isEmpty ? "none" : services.joined(separator: ", ")
        self.notice("Discovered: name=\(deviceName, privacy: .public) uuid=\(uuid, privacy: .public) rssi=\(rssi) services=[\(serviceList, privacy: .public)]")
    }
    
    /// Log BLE state change (notice level for syslog visibility)
    func stateChanged(from oldState: String, to newState: String) {
        self.notice("BLE state: \(oldState, privacy: .public) → \(newState, privacy: .public)")
    }
    
    /// Log connection attempt (notice level for syslog visibility)
    func connectingTo(name: String?, uuid: String) {
        let deviceName = name ?? "unknown"
        self.notice("Connecting to: name=\(deviceName, privacy: .public) uuid=\(uuid, privacy: .public)")
    }
    
    /// Log connection success (notice level for syslog visibility)
    func connected(name: String?, uuid: String) {
        let deviceName = name ?? "unknown"
        self.notice("Connected: name=\(deviceName, privacy: .public) uuid=\(uuid, privacy: .public)")
    }
    
    /// Log disconnection (notice level for syslog visibility)
    func disconnected(name: String?, uuid: String, reason: String?) {
        let deviceName = name ?? "unknown"
        let reasonStr = reason ?? "normal"
        self.notice("Disconnected: name=\(deviceName, privacy: .public) uuid=\(uuid, privacy: .public) reason=\(reasonStr, privacy: .public)")
    }
    
    /// Log connection error (error level - always visible)
    func connectionError(name: String?, uuid: String, error: String) {
        let deviceName = name ?? "unknown"
        self.error("Connection failed: name=\(deviceName, privacy: .public) uuid=\(uuid, privacy: .public) error=\(error, privacy: .public)")
    }
}

#else

// MARK: - Fallback for non-Darwin platforms

/// Fallback logger for Linux/other platforms using print
public struct BLELogger: Sendable {
    public static let general = FallbackLogger(category: "ble")
    public static let discovery = FallbackLogger(category: "ble.discovery")
    public static let connection = FallbackLogger(category: "ble.connection")
    public static let services = FallbackLogger(category: "ble.services")
    public static let data = FallbackLogger(category: "ble.data")
}

/// Simple fallback logger for non-Darwin platforms
public struct FallbackLogger: Sendable {
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
    
    func scanStarted(services: [BLEUUID]?) {
        let serviceList = services?.map { $0.description }.joined(separator: ", ") ?? "all"
        info("Scan started: services=[\(serviceList)]")
    }
    
    func scanStopped() {
        info("Scan stopped")
    }
    
    func deviceDiscovered(name: String?, uuid: String, rssi: Int, services: [String]) {
        let deviceName = name ?? "unknown"
        info("Discovered: name=\(deviceName) uuid=\(uuid) rssi=\(rssi)")
    }
    
    func stateChanged(from oldState: String, to newState: String) {
        info("BLE state: \(oldState) → \(newState)")
    }
    
    func connectingTo(name: String?, uuid: String) {
        info("Connecting to: name=\(name ?? "unknown") uuid=\(uuid)")
    }
    
    func connected(name: String?, uuid: String) {
        info("Connected: name=\(name ?? "unknown") uuid=\(uuid)")
    }
    
    func disconnected(name: String?, uuid: String, reason: String?) {
        info("Disconnected: name=\(name ?? "unknown") uuid=\(uuid)")
    }
    
    func connectionError(name: String?, uuid: String, error: String) {
        self.error("Connection failed: name=\(name ?? "unknown") error=\(error)")
    }
}

#endif
