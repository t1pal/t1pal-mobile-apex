// SPDX-License-Identifier: AGPL-3.0-or-later
//
// QuirkTests.swift
// T1PalCompatKit
//
// Capability tests for detecting applicable platform quirks.
// Trace: PRD-006 REQ-COMPAT-005

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Quirk Detection Test

/// Test that detects applicable quirks for the current device/OS
public struct QuirkDetectionTest: CapabilityTest {
    public let id = "quirk-detection"
    public let name = "Platform Quirks Detection"
    public let category = CapabilityCategory.storage  // General category
    public let priority = 50
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let registry = QuirksRegistry.shared
        let osVersion = currentIOSVersion()
        
        let applicableQuirks = registry.quirks(forVersion: osVersion)
        let criticalQuirks = applicableQuirks.filter { $0.severity == .critical }
        let highQuirks = applicableQuirks.filter { $0.severity == .high }
        
        var details: [String: String] = [
            "osVersion": osVersion,
            "totalQuirks": "\(registry.quirks.count)",
            "applicableQuirks": "\(applicableQuirks.count)",
            "criticalCount": "\(criticalQuirks.count)",
            "highCount": "\(highQuirks.count)"
        ]
        
        // Add quirk IDs
        if !applicableQuirks.isEmpty {
            let quirkIds = applicableQuirks.prefix(10).map { $0.id }.joined(separator: ", ")
            details["quirks"] = quirkIds
        }
        
        let message: String
        if criticalQuirks.isEmpty && highQuirks.isEmpty {
            message = "\(applicableQuirks.count) quirks apply (none critical)"
        } else if !criticalQuirks.isEmpty {
            message = "\(applicableQuirks.count) quirks apply (\(criticalQuirks.count) critical!)"
        } else {
            message = "\(applicableQuirks.count) quirks apply (\(highQuirks.count) high severity)"
        }
        
        // Always pass - this is informational
        return passed(message, details: details)
    }
    
    private func currentIOSVersion() -> String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        // Linux or other - return a version that matches "all"
        return "0.0.0"
        #endif
    }
}

// MARK: - Quirk Summary Test

/// Test that provides a summary of quirks by category
public struct QuirkSummaryTest: CapabilityTest {
    public let id = "quirk-summary"
    public let name = "Quirks Database Summary"
    public let category = CapabilityCategory.storage
    public let priority = 51
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let registry = QuirksRegistry.shared
        let byCategory = registry.countByCategory
        
        var details: [String: String] = [
            "totalQuirks": "\(registry.quirks.count)"
        ]
        
        for (category, count) in byCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            details[category.rawValue] = "\(count)"
        }
        
        let criticalCount = registry.quirks(severity: .critical).count
        let highCount = registry.quirks(severity: .high).count
        details["criticalSeverity"] = "\(criticalCount)"
        details["highSeverity"] = "\(highCount)"
        
        return passed(
            "\(registry.quirks.count) quirks documented across \(byCategory.count) categories",
            details: details
        )
    }
}

// MARK: - Low Power Mode Detection Test

/// Test that detects if Low Power Mode is enabled (affects BLE)
public struct LowPowerModeTest: CapabilityTest {
    public let id = "low-power-mode"
    public let name = "Low Power Mode Detection"
    public let category = CapabilityCategory.bluetooth
    public let priority = 20
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if os(iOS)
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        if isLowPowerMode {
            return passed("Low Power Mode enabled", details: [
                "lowPowerMode": "true",
                "impact": "BLE scan intervals may be increased",
                "relatedQuirk": "QUIRK-BLE-004"
            ])
        } else {
            return passed("Low Power Mode disabled", details: [
                "lowPowerMode": "false"
            ])
        }
        #elseif os(macOS)
        // macOS: Check for Low Power Mode on Apple Silicon MacBooks
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        return passed("Low Power Mode: \(isLowPowerMode ? "enabled" : "disabled")", details: [
            "lowPowerMode": "\(isLowPowerMode)"
        ])
        #else
        return unsupported("Low Power Mode not applicable on this platform")
        #endif
    }
}

// MARK: - Background App Refresh Test

/// Test that checks Background App Refresh status
public struct BackgroundAppRefreshTest: CapabilityTest {
    public let id = "background-app-refresh"
    public let name = "Background App Refresh"
    public let category = CapabilityCategory.background
    public let priority = 30
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if os(iOS)
        // Note: UIApplication.shared.backgroundRefreshStatus requires main thread
        // For now, we just check if background modes are configured
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            let modes = backgroundModes.joined(separator: ", ")
            return passed("Background modes configured", details: [
                "modes": modes,
                "count": "\(backgroundModes.count)"
            ])
        } else {
            return failed("No background modes configured", details: [
                "relatedQuirk": "QUIRK-IOS-001"
            ])
        }
        #elseif os(macOS)
        return passed("macOS: Background execution available")
        #else
        return unsupported("Background App Refresh not applicable on this platform")
        #endif
    }
}
