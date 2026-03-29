// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WatchTests.swift
// T1PalCompatKit
//
// Capability tests for Apple Watch connectivity.
// Trace: PRD-006 REQ-COMPAT-001
//
// Tests WatchConnectivity framework availability and session state.

import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - WatchConnectivity Availability Test

/// Tests if WatchConnectivity framework is available
public struct WatchConnectivityAvailabilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-connectivity-available"
    public let name = "WatchConnectivity Framework"
    public let category = CapabilityCategory.watch
    public let priority = 60
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        let duration = Date().timeIntervalSince(startTime)
        return passed(
            "WatchConnectivity framework available.",
            details: ["framework": "WatchConnectivity", "available": "true"],
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "WatchConnectivity not available on this platform.",
            details: ["framework": "WatchConnectivity", "available": "false"],
            duration: duration
        )
        #endif
    }
}

// MARK: - WCSession Supported Test

/// Tests if WCSession is supported on this device
public struct WCSessionSupportedTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-session-supported"
    public let name = "WCSession Support"
    public let category = CapabilityCategory.watch
    public let priority = 61
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        let isSupported = WCSession.isSupported()
        let duration = Date().timeIntervalSince(startTime)
        
        if isSupported {
            return passed(
                "WCSession is supported. Watch pairing possible.",
                details: ["isSupported": "true"],
                duration: duration
            )
        } else {
            return failed(
                "WCSession not supported. No paired Apple Watch available.",
                details: ["isSupported": "false"],
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "WCSession check requires iOS platform.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Watch Pairing Test

/// Tests if an Apple Watch is paired with the device
public struct WatchPairingTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-pairing-status"
    public let name = "Apple Watch Pairing"
    public let category = CapabilityCategory.watch
    public let priority = 62
    public let requiresHardware = true
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "WCSession not supported on this device.",
                details: ["isSupported": "false"],
                duration: duration
            )
        }
        
        let session = WCSession.default
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        
        var details: [String: String] = [
            "isPaired": String(isPaired),
            "isWatchAppInstalled": String(isWatchAppInstalled)
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        if isPaired {
            if isWatchAppInstalled {
                return passed(
                    "Apple Watch paired and T1Pal Watch app installed.",
                    details: details,
                    duration: duration
                )
            } else {
                details["recommendation"] = "Install T1Pal Watch app for glucose on wrist"
                return CapabilityResult(
                    testId: id,
                    testName: name,
                    category: category,
                    status: .warning,
                    message: "Apple Watch paired but T1Pal Watch app not installed.",
                    details: details,
                    duration: duration
                )
            }
        } else {
            return failed(
                "No Apple Watch paired. Watch features unavailable.",
                details: details,
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Watch pairing check requires iOS platform.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Watch Reachability Test

/// Tests if the paired Apple Watch is currently reachable
public struct WatchReachabilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-reachability"
    public let name = "Watch Reachability"
    public let category = CapabilityCategory.watch
    public let priority = 63
    public let requiresHardware = true
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "WCSession not supported.",
                details: ["isSupported": "false"],
                duration: duration
            )
        }
        
        let session = WCSession.default
        
        guard session.isPaired else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "No Apple Watch paired.",
                details: ["isPaired": "false"],
                duration: duration
            )
        }
        
        let isReachable = session.isReachable
        let duration = Date().timeIntervalSince(startTime)
        
        if isReachable {
            return passed(
                "Apple Watch is reachable. Real-time messaging available.",
                details: ["isReachable": "true"],
                duration: duration
            )
        } else {
            return CapabilityResult(
                testId: id,
                testName: name,
                category: category,
                status: .warning,
                message: "Apple Watch not currently reachable. Background transfer still works.",
                details: ["isReachable": "false", "backgroundTransfer": "available"],
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Watch reachability check requires iOS platform.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Complication Update Budget Test

/// Tests complication update budget availability
public struct ComplicationBudgetTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-complication-budget"
    public let name = "Complication Update Budget"
    public let category = CapabilityCategory.watch
    public let priority = 64
    public let requiresHardware = true
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "WCSession not supported.",
                details: ["isSupported": "false"],
                duration: duration
            )
        }
        
        let session = WCSession.default
        
        guard session.isPaired && session.isWatchAppInstalled else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "Watch app not installed. Cannot check complication budget.",
                details: ["isPaired": String(session.isPaired), "isWatchAppInstalled": String(session.isWatchAppInstalled)],
                duration: duration
            )
        }
        
        #if os(iOS)
        let remainingTransfers = session.remainingComplicationUserInfoTransfers
        let duration = Date().timeIntervalSince(startTime)
        
        var details: [String: String] = [
            "remainingTransfers": String(remainingTransfers)
        ]
        
        // Apple allows ~50 complication updates per day
        if remainingTransfers >= 40 {
            details["budgetStatus"] = "good"
            return passed(
                "Complication budget healthy: \(remainingTransfers) transfers remaining.",
                details: details,
                duration: duration
            )
        } else if remainingTransfers >= 10 {
            details["budgetStatus"] = "moderate"
            return CapabilityResult(
                testId: id,
                testName: name,
                category: category,
                status: .warning,
                message: "Complication budget moderate: \(remainingTransfers) transfers remaining.",
                details: details,
                duration: duration
            )
        } else {
            details["budgetStatus"] = "low"
            details["recommendation"] = "Reduce complication update frequency"
            return failed(
                "Complication budget low: \(remainingTransfers) transfers remaining.",
                details: details,
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Complication budget check requires iOS.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Complication budget check requires iOS platform.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Message Send Reliability Test

/// Tests ability to send messages to Apple Watch
public struct WatchMessageSendTest: CapabilityTest, @unchecked Sendable {
    public let id = "watch-message-send"
    public let name = "Watch Message Send"
    public let category = CapabilityCategory.watch
    public let priority = 65
    public let requiresHardware = true
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "WCSession not supported.",
                details: ["isSupported": "false"],
                duration: duration
            )
        }
        
        let session = WCSession.default
        
        guard session.isPaired else {
            let duration = Date().timeIntervalSince(startTime)
            return failed(
                "No Apple Watch paired.",
                details: ["isPaired": "false"],
                duration: duration
            )
        }
        
        var details: [String: String] = [
            "isPaired": "true",
            "isReachable": String(session.isReachable)
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        if session.isReachable {
            details["messageSupport"] = "realtime"
            return passed(
                "Real-time messaging available. Watch is reachable.",
                details: details,
                duration: duration
            )
        } else {
            details["messageSupport"] = "background-only"
            details["note"] = "Use transferUserInfo for background delivery"
            return CapabilityResult(
                testId: id,
                testName: name,
                category: category,
                status: .warning,
                message: "Background transfer only. Watch not currently reachable.",
                details: details,
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Watch message test requires iOS platform.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}
