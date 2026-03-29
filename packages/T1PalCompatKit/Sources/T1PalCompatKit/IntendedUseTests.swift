// SPDX-License-Identifier: AGPL-3.0-or-later
//
// IntendedUseTests.swift
// T1PalCompatKit
//
// Capability tests for intended use verification.
// Trace: PRD-006 REQ-COMPAT-003
//
// These tests verify device compatibility for each operational mode.

import Foundation

// MARK: - Demo Mode Compatibility Test

/// Verifies device compatibility for demo mode
public struct DemoModeCompatibilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "intended-use-demo"
    public let name = "Demo Mode Compatibility"
    public let category = CapabilityCategory.intendedUse
    public let priority = 50
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Demo mode has no hardware requirements
        // Just verify the app can run
        let details: [String: String] = [
            "testId": id,
            "mode": IntendedUseMode.demo.rawValue,
            "riskLevel": IntendedUseMode.demo.riskLevel.rawValue,
            "requirements": "None - simulated data only"
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Device compatible with Demo Mode. No hardware required.",
            details: details,
            duration: duration
        )
    }
}

// MARK: - CGM-Only Mode Compatibility Test

/// Verifies device compatibility for CGM-only mode
public struct CGMOnlyCompatibilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "intended-use-cgm-only"
    public let name = "CGM-Only Mode Compatibility"
    public let category = CapabilityCategory.intendedUse
    public let priority = 51
    
    private let registry: CapabilityRegistry
    
    public init(registry: CapabilityRegistry = .shared) {
        self.registry = registry
    }
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Check Bluetooth capability
        let bleTests = await registry.tests(in: .bluetooth)
        
        var details: [String: String] = [
            "testId": id,
            "mode": IntendedUseMode.cgmOnly.rawValue,
            "riskLevel": IntendedUseMode.cgmOnly.riskLevel.rawValue,
            "bleTestsAvailable": String(bleTests.count)
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Check platform support for Bluetooth
        #if canImport(CoreBluetooth)
        details["bleFrameworkAvailable"] = "true"
        return passed(
            "Device compatible with CGM-Only Mode. Bluetooth available.",
            details: details,
            duration: duration
        )
        #else
        details["bleFrameworkAvailable"] = "false"
        return failed(
            "CGM-Only mode requires Bluetooth. CoreBluetooth not available.",
            details: details,
            duration: duration
        )
        #endif
    }
}

// MARK: - AID Controller Mode Compatibility Test

/// Verifies device compatibility for AID controller mode
public struct AIDControllerCompatibilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "intended-use-aid-controller"
    public let name = "AID Controller Mode Compatibility"
    public let category = CapabilityCategory.intendedUse
    public let priority = 52
    
    private let registry: CapabilityRegistry
    
    public init(registry: CapabilityRegistry = .shared) {
        self.registry = registry
    }
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        var details: [String: String] = [
            "testId": id,
            "mode": IntendedUseMode.aidController.rawValue,
            "riskLevel": IntendedUseMode.aidController.riskLevel.rawValue
        ]
        
        var issues: [String] = []
        
        // Check Bluetooth
        #if canImport(CoreBluetooth)
        details["bluetooth"] = "available"
        #else
        details["bluetooth"] = "unavailable"
        issues.append("CoreBluetooth not available")
        #endif
        
        // Check Notifications
        #if canImport(UserNotifications)
        details["notifications"] = "available"
        #else
        details["notifications"] = "unavailable"
        issues.append("UserNotifications not available")
        #endif
        
        // Check HealthKit
        #if canImport(HealthKit)
        details["healthkit"] = "available"
        #else
        details["healthkit"] = "unavailable"
        // HealthKit is recommended but not required
        #endif
        
        let duration = Date().timeIntervalSince(startTime)
        
        if !issues.isEmpty {
            details["issues"] = issues.joined(separator: "; ")
            return failed(
                "AID Controller mode requires Bluetooth and Notifications. Missing: \(issues.joined(separator: ", "))",
                details: details,
                duration: duration
            )
        }
        
        // On platforms where we can't check, return unsupported
        #if !canImport(CoreBluetooth) || !canImport(UserNotifications)
        return unsupported("AID Controller compatibility check requires iOS platform")
        #else
        return passed(
            "Device compatible with AID Controller Mode. All required frameworks available.",
            details: details,
            duration: duration
        )
        #endif
    }
}

// MARK: - Device Report Generation Test

/// Generates a device compatibility report
public struct DeviceCompatibilityReportTest: CapabilityTest, @unchecked Sendable {
    public let id = "device-compatibility-report"
    public let name = "Device Compatibility Report"
    public let category = CapabilityCategory.intendedUse
    public let priority = 53
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Collect device info
        let deviceInfo = DeviceReportInfo.current
        
        var details: [String: String] = [
            "testId": id,
            "deviceModel": deviceInfo.model,
            "osVersion": deviceInfo.osVersion,
            "appVersion": deviceInfo.appVersion
        ]
        
        // Count compatible modes
        var compatibleModes: [String] = []
        
        // Demo is always compatible
        compatibleModes.append(IntendedUseMode.demo.displayName)
        
        #if canImport(CoreBluetooth)
        compatibleModes.append(IntendedUseMode.cgmOnly.displayName)
        #endif
        
        #if canImport(CoreBluetooth) && canImport(UserNotifications)
        compatibleModes.append(IntendedUseMode.aidController.displayName)
        #endif
        
        details["compatibleModes"] = compatibleModes.joined(separator: ", ")
        details["compatibleModeCount"] = String(compatibleModes.count)
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Device report generated. Compatible with \(compatibleModes.count) mode(s).",
            details: details,
            duration: duration
        )
    }
}
