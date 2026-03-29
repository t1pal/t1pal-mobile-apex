// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CapabilityTest.swift
// T1PalCompatKit
//
// Core protocol and result types for capability testing.
// Trace: PRD-006 REQ-COMPAT-001
//
// Usage:
//   struct MyTest: CapabilityTest { ... }
//   let result = await MyTest().run()

import Foundation

// MARK: - Capability Categories

/// Categories of capabilities that can be tested
public enum CapabilityCategory: String, Codable, Sendable, CaseIterable {
    case bluetooth = "bluetooth"
    case notification = "notification"
    case healthkit = "healthkit"
    case watch = "watch"
    case widget = "widget"
    case background = "background"
    case network = "network"
    case storage = "storage"
    case colocatedApps = "colocated-apps"
    case intendedUse = "intended-use"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .notification: return "Notifications"
        case .healthkit: return "HealthKit"
        case .watch: return "Apple Watch"
        case .widget: return "Widgets"
        case .background: return "Background Execution"
        case .network: return "Network"
        case .storage: return "Storage"
        case .colocatedApps: return "Colocated Apps"
        case .intendedUse: return "Intended Use"
        }
    }
}

// MARK: - Test Status

/// The outcome of a capability test
public enum CapabilityStatus: String, Codable, Sendable {
    case passed = "passed"
    case failed = "failed"
    case warning = "warning"
    case skipped = "skipped"
    case unsupported = "unsupported"
    
    /// Emoji indicator for CLI output
    public var indicator: String {
        switch self {
        case .passed: return "✓"
        case .failed: return "✗"
        case .warning: return "⚠"
        case .skipped: return "○"
        case .unsupported: return "−"
        }
    }
    
    /// ANSI color code for terminal output
    public var colorCode: String {
        switch self {
        case .passed: return "\u{001B}[32m"     // Green
        case .failed: return "\u{001B}[31m"     // Red
        case .warning: return "\u{001B}[33m"    // Yellow
        case .skipped: return "\u{001B}[90m"    // Gray
        case .unsupported: return "\u{001B}[90m" // Gray
        }
    }
    
    /// Reset ANSI code
    public static let resetCode = "\u{001B}[0m"
}

// MARK: - Test Result

/// Result of running a capability test
public struct CapabilityResult: Codable, Sendable {
    /// Unique test identifier
    public let testId: String
    
    /// Human-readable test name
    public let testName: String
    
    /// Category this test belongs to
    public let category: CapabilityCategory
    
    /// Test outcome
    public let status: CapabilityStatus
    
    /// Human-readable message explaining the result
    public let message: String
    
    /// Optional diagnostic details
    public let details: [String: String]?
    
    /// Duration in seconds
    public let duration: TimeInterval
    
    /// When the test was run
    public let timestamp: Date
    
    public init(
        testId: String,
        testName: String,
        category: CapabilityCategory,
        status: CapabilityStatus,
        message: String,
        details: [String: String]? = nil,
        duration: TimeInterval = 0,
        timestamp: Date = Date()
    ) {
        self.testId = testId
        self.testName = testName
        self.category = category
        self.status = status
        self.message = message
        self.details = details
        self.duration = duration
        self.timestamp = timestamp
    }
    
    /// Format for CLI display
    public func formatted(useColor: Bool = true) -> String {
        let status = useColor 
            ? "\(self.status.colorCode)\(self.status.indicator)\(CapabilityStatus.resetCode)"
            : self.status.indicator
        return "\(status) [\(category.displayName)] \(testName): \(message)"
    }
}

// MARK: - Capability Test Protocol

/// Protocol for implementing capability tests
public protocol CapabilityTest: Sendable {
    /// Unique identifier for this test (e.g., "ble-central-state")
    var id: String { get }
    
    /// Human-readable name
    var name: String { get }
    
    /// Category this test belongs to
    var category: CapabilityCategory { get }
    
    /// Priority level (lower = higher priority)
    var priority: Int { get }
    
    /// Whether this test requires device hardware
    var requiresHardware: Bool { get }
    
    /// Minimum iOS version required (nil = all supported)
    var minimumIOSVersion: String? { get }
    
    /// Run the test and return result
    func run() async -> CapabilityResult
}

// MARK: - Default Implementations

public extension CapabilityTest {
    var priority: Int { 100 }
    var requiresHardware: Bool { false }
    var minimumIOSVersion: String? { nil }
    
    /// Create a passed result
    func passed(_ message: String, details: [String: String]? = nil, duration: TimeInterval = 0) -> CapabilityResult {
        CapabilityResult(
            testId: id,
            testName: name,
            category: category,
            status: .passed,
            message: message,
            details: details,
            duration: duration
        )
    }
    
    /// Create a warning result
    func warning(_ message: String, details: [String: String]? = nil, duration: TimeInterval = 0) -> CapabilityResult {
        CapabilityResult(
            testId: id,
            testName: name,
            category: category,
            status: .warning,
            message: message,
            details: details,
            duration: duration
        )
    }
    
    /// Create a failed result
    func failed(_ message: String, details: [String: String]? = nil, duration: TimeInterval = 0) -> CapabilityResult {
        CapabilityResult(
            testId: id,
            testName: name,
            category: category,
            status: .failed,
            message: message,
            details: details,
            duration: duration
        )
    }
    
    /// Create a skipped result
    func skipped(_ message: String, details: [String: String]? = nil, duration: TimeInterval = 0) -> CapabilityResult {
        CapabilityResult(
            testId: id,
            testName: name,
            category: category,
            status: .skipped,
            message: message,
            details: details,
            duration: duration
        )
    }
    
    /// Create an unsupported result
    func unsupported(_ message: String, details: [String: String]? = nil, duration: TimeInterval = 0) -> CapabilityResult {
        CapabilityResult(
            testId: id,
            testName: name,
            category: category,
            status: .unsupported,
            message: message,
            details: details,
            duration: duration
        )
    }
}
