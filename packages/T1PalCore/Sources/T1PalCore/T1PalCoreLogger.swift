// SPDX-License-Identifier: AGPL-3.0-or-later
//
// T1PalCoreLogger.swift
// T1PalCore
//
// Unified logging for T1PalCore using os.Logger.
// Provides structured diagnostics for core operations.
// Trace: CODE-002, LOGGING-006

import Foundation

#if canImport(os)
import os

// MARK: - T1PalCore Logging Categories

/// Logger instances for T1PalCore subsystem diagnostics
public struct T1PalCoreLogger {
    /// Subsystem identifier for T1PalCore
    private static let subsystem = "com.t1pal.core"
    
    /// General core operations
    public static let general = Logger(subsystem: subsystem, category: "core")
    
    /// Metrics and observability
    public static let metrics = Logger(subsystem: subsystem, category: "core.metrics")
    
    /// Tracing operations
    public static let traces = Logger(subsystem: subsystem, category: "core.traces")
    
    /// Settings and configuration
    public static let settings = Logger(subsystem: subsystem, category: "core.settings")
    
    /// Identity and authentication
    public static let identity = Logger(subsystem: subsystem, category: "core.identity")
    
    /// Data persistence
    public static let persistence = Logger(subsystem: subsystem, category: "core.persistence")
}

#else

// MARK: - Fallback for non-Darwin platforms

/// Fallback logger for Linux/other platforms using print
public struct T1PalCoreLogger: Sendable {
    public static let general = T1PalCoreFallbackLogger(category: "core")
    public static let metrics = T1PalCoreFallbackLogger(category: "core.metrics")
    public static let traces = T1PalCoreFallbackLogger(category: "core.traces")
    public static let settings = T1PalCoreFallbackLogger(category: "core.settings")
    public static let identity = T1PalCoreFallbackLogger(category: "core.identity")
    public static let persistence = T1PalCoreFallbackLogger(category: "core.persistence")
}

/// Simple fallback logger for non-Darwin platforms
public struct T1PalCoreFallbackLogger: Sendable {
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
        #if DEBUG
        print("[\(category)] WARNING: \(message)")
        #endif
    }
}

#endif
