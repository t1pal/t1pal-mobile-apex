// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutLogger.swift
// NightscoutKit
//
// Unified logging for Nightscout API operations using os.Logger.
// Provides structured diagnostics for API calls, sync, and upload events.
// Trace: LOGGING-001, PRD-005

import Foundation

#if canImport(os)
import os

// MARK: - Nightscout Logging Categories

/// Logger instances for Nightscout API subsystem diagnostics
public struct NightscoutLogger {
    /// Subsystem identifier for NightscoutKit
    private static let subsystem = "com.t1pal.nightscoutkit"
    
    /// General API operations (config, status)
    public static let general = Logger(subsystem: subsystem, category: "nightscout")
    
    /// Entry operations (fetch, upload, delete)
    public static let entries = Logger(subsystem: subsystem, category: "nightscout.entries")
    
    /// Treatment operations (bolus, carbs, temp basal)
    public static let treatments = Logger(subsystem: subsystem, category: "nightscout.treatments")
    
    /// Device status operations
    public static let deviceStatus = Logger(subsystem: subsystem, category: "nightscout.devicestatus")
    
    /// Profile operations
    public static let profile = Logger(subsystem: subsystem, category: "nightscout.profile")
    
    /// Sync/push operations
    public static let sync = Logger(subsystem: subsystem, category: "nightscout.sync")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log API request start
    func apiRequest(method: String, endpoint: String) {
        self.info("API \(method, privacy: .public) \(endpoint, privacy: .public)")
    }
    
    /// Log API response
    func apiResponse(status: Int, endpoint: String, duration: TimeInterval) {
        let ms = Int(duration * 1000)
        self.info("Response: status=\(status) endpoint=\(endpoint, privacy: .public) duration=\(ms)ms")
    }
    
    /// Log API error
    func apiError(endpoint: String, error: String) {
        self.error("API error: endpoint=\(endpoint, privacy: .public) error=\(error, privacy: .public)")
    }
    
    /// Log entries fetch
    func entriesFetched(count: Int, oldest: Date?, newest: Date?) {
        let range = formatDateRange(oldest, newest)
        self.info("Fetched \(count) entries: \(range, privacy: .public)")
    }
    
    /// Log entries upload
    func entriesUploaded(count: Int) {
        self.info("Uploaded \(count) entries")
    }
    
    /// Log treatment created
    func treatmentCreated(type: String, id: String?) {
        let treatmentId = id ?? "new"
        self.info("Treatment created: type=\(type, privacy: .public) id=\(treatmentId, privacy: .public)")
    }
    
    /// Log sync started
    func syncStarted(direction: String) {
        self.info("Sync started: direction=\(direction, privacy: .public)")
    }
    
    /// Log sync completed
    func syncCompleted(entriesUp: Int, entriesDown: Int, treatmentsUp: Int) {
        self.info("Sync complete: up=\(entriesUp) entries, \(treatmentsUp) treatments; down=\(entriesDown) entries")
    }
    
    private func formatDateRange(_ oldest: Date?, _ newest: Date?) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let oldStr = oldest.map { formatter.string(from: $0) } ?? "nil"
        let newStr = newest.map { formatter.string(from: $0) } ?? "nil"
        return "\(oldStr) to \(newStr)"
    }
}

#else

// MARK: - Fallback for non-Darwin platforms

/// Fallback logger for Linux/other platforms using print
public struct NightscoutLogger: Sendable {
    public static let general = NightscoutFallbackLogger(category: "nightscout")
    public static let entries = NightscoutFallbackLogger(category: "nightscout.entries")
    public static let treatments = NightscoutFallbackLogger(category: "nightscout.treatments")
    public static let deviceStatus = NightscoutFallbackLogger(category: "nightscout.devicestatus")
    public static let profile = NightscoutFallbackLogger(category: "nightscout.profile")
    public static let sync = NightscoutFallbackLogger(category: "nightscout.sync")
}

/// Simple fallback logger for non-Darwin platforms
public struct NightscoutFallbackLogger: Sendable {
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
    public func apiRequest(method: String, endpoint: String) {
        info("API \(method) \(endpoint)")
    }
    
    public func apiResponse(status: Int, endpoint: String, duration: TimeInterval) {
        let ms = Int(duration * 1000)
        info("Response: status=\(status) endpoint=\(endpoint) duration=\(ms)ms")
    }
    
    public func apiError(endpoint: String, error: String) {
        self.error("API error: endpoint=\(endpoint) error=\(error)")
    }
    
    public func entriesFetched(count: Int, oldest: Date?, newest: Date?) {
        info("Fetched \(count) entries")
    }
    
    public func entriesUploaded(count: Int) {
        info("Uploaded \(count) entries")
    }
    
    public func treatmentCreated(type: String, id: String?) {
        info("Treatment created: type=\(type)")
    }
    
    public func syncStarted(direction: String) {
        info("Sync started: direction=\(direction)")
    }
    
    public func syncCompleted(entriesUp: Int, entriesDown: Int, treatmentsUp: Int) {
        info("Sync complete: up=\(entriesUp) entries, \(treatmentsUp) treatments; down=\(entriesDown) entries")
    }
}

#endif
