// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMLogger.swift
// CGMKit
//
// Unified logging for CGM operations using os.Logger.
// Provides structured diagnostics for glucose readings, calibrations, and sensor events.
// Trace: LOGGING-002, PRD-003

import Foundation

#if canImport(os)
import os

// MARK: - CGM Logging Categories

/// Logger instances for CGM subsystem diagnostics
public struct CGMLogger {
    /// Subsystem identifier for CGMKit
    private static let subsystem = "com.t1pal.cgmkit"
    
    /// General CGM operations (manager lifecycle)
    public static let general = Logger(subsystem: subsystem, category: "cgm")
    
    /// Glucose reading events
    public static let readings = Logger(subsystem: subsystem, category: "cgm.readings")
    
    /// Calibration events
    public static let calibration = Logger(subsystem: subsystem, category: "cgm.calibration")
    
    /// Sensor lifecycle (start, stop, warmup, expire)
    public static let sensor = Logger(subsystem: subsystem, category: "cgm.sensor")
    
    /// Transmitter events (pairing, battery)
    public static let transmitter = Logger(subsystem: subsystem, category: "cgm.transmitter")
    
    /// Algorithm/prediction events
    public static let algorithm = Logger(subsystem: subsystem, category: "cgm.algorithm")
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
    func diagnostic(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log glucose reading received (notice level for syslog visibility)
    func glucoseReading(value: Double, trend: String, timestamp: Date) {
        let formatter = ISO8601DateFormatter()
        let timeStr = formatter.string(from: timestamp)
        self.notice("Glucose: \(value, format: .fixed(precision: 0)) mg/dL trend=\(trend, privacy: .public) at=\(timeStr, privacy: .public)")
    }
    
    /// Log glucose batch received (notice level for syslog visibility)
    func glucoseBatch(count: Int, source: String, newest: Date?) {
        let formatter = ISO8601DateFormatter()
        let newestStr = newest.map { formatter.string(from: $0) } ?? "nil"
        self.notice("Batch: \(count) readings from=\(source, privacy: .public) newest=\(newestStr, privacy: .public)")
    }
    
    /// Log calibration entered
    func calibrationEntered(value: Double, timestamp: Date) {
        self.notice("Calibration: \(value, format: .fixed(precision: 0)) mg/dL")
    }
    
    /// Log sensor started (notice level for syslog visibility)
    func sensorStarted(serialNumber: String?, insertionDate: Date) {
        let serial = serialNumber ?? "unknown"
        self.notice("Sensor started: serial=\(serial, privacy: .public)")
    }
    
    /// Log sensor expired (notice level for syslog visibility)
    func sensorExpired(serialNumber: String?, duration: TimeInterval) {
        let serial = serialNumber ?? "unknown"
        let days = Int(duration / 86400)
        self.notice("Sensor expired: serial=\(serial, privacy: .public) after \(days) days")
    }
    
    /// Log sensor warmup
    func sensorWarmup(remaining: TimeInterval) {
        let minutes = Int(remaining / 60)
        self.info("Sensor warmup: \(minutes) minutes remaining")
    }
    
    /// Log transmitter paired (notice level for syslog visibility)
    func transmitterPaired(id: String, model: String?) {
        let modelStr = model ?? "unknown"
        self.notice("Transmitter paired: id=\(id, privacy: .public) model=\(modelStr, privacy: .public)")
    }
    
    /// Log transmitter battery
    func transmitterBattery(id: String, level: Int?, voltage: Double?) {
        if let level = level {
            self.info("Transmitter battery: id=\(id, privacy: .public) level=\(level)%")
        } else if let voltage = voltage {
            self.info("Transmitter battery: id=\(id, privacy: .public) voltage=\(voltage, format: .fixed(precision: 2))V")
        }
    }
    
    /// Log CGM source change (notice level for syslog visibility)
    func sourceChanged(from oldSource: String, to newSource: String) {
        self.notice("CGM source: \(oldSource, privacy: .public) → \(newSource, privacy: .public)")
    }
}

#else

// MARK: - Fallback for non-Darwin platforms

/// Fallback logger for Linux/other platforms using print
public struct CGMLogger {
    public static let general = CGMFallbackLogger(category: "cgm")
    public static let readings = CGMFallbackLogger(category: "cgm.readings")
    public static let calibration = CGMFallbackLogger(category: "cgm.calibration")
    public static let sensor = CGMFallbackLogger(category: "cgm.sensor")
    public static let transmitter = CGMFallbackLogger(category: "cgm.transmitter")
    public static let algorithm = CGMFallbackLogger(category: "cgm.algorithm")
}

/// Simple fallback logger for non-Darwin platforms
public struct CGMFallbackLogger: Sendable {
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
    public func glucoseReading(value: Double, trend: String, timestamp: Date) {
        info("Glucose: \(Int(value)) mg/dL trend=\(trend)")
    }
    
    public func glucoseBatch(count: Int, source: String, newest: Date?) {
        info("Batch: \(count) readings from=\(source)")
    }
    
    public func calibrationEntered(value: Double, timestamp: Date) {
        info("Calibration: \(Int(value)) mg/dL")
    }
    
    public func sensorStarted(serialNumber: String?, insertionDate: Date) {
        info("Sensor started: serial=\(serialNumber ?? "unknown")")
    }
    
    public func sensorExpired(serialNumber: String?, duration: TimeInterval) {
        info("Sensor expired: serial=\(serialNumber ?? "unknown")")
    }
    
    public func sensorWarmup(remaining: TimeInterval) {
        info("Sensor warmup: \(Int(remaining / 60)) minutes remaining")
    }
    
    public func transmitterPaired(id: String, model: String?) {
        info("Transmitter paired: id=\(id)")
    }
    
    public func transmitterBattery(id: String, level: Int?, voltage: Double?) {
        info("Transmitter battery: id=\(id)")
    }
    
    public func sourceChanged(from oldSource: String, to newSource: String) {
        info("CGM source: \(oldSource) → \(newSource)")
    }
}

#endif
