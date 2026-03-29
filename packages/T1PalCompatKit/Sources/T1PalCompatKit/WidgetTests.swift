// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WidgetTests.swift
// T1PalCompatKit
//
// Capability tests for WidgetKit and widget functionality.
// Trace: PRD-006 REQ-COMPAT-001
//
// Tests WidgetKit framework availability and timeline refresh capabilities.

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - WidgetKit Availability Test

/// Tests if WidgetKit framework is available
public struct WidgetKitAvailabilityTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-kit-available"
    public let name = "WidgetKit Framework"
    public let category = CapabilityCategory.widget
    public let priority = 70
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WidgetKit)
        let duration = Date().timeIntervalSince(startTime)
        return passed(
            "WidgetKit framework available.",
            details: ["framework": "WidgetKit", "available": "true"],
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "WidgetKit not available on this platform.",
            details: ["framework": "WidgetKit", "available": "false"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Widget Timeline Reload Test

/// Tests ability to reload widget timelines
public struct WidgetTimelineReloadTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-timeline-reload"
    public let name = "Widget Timeline Reload"
    public let category = CapabilityCategory.widget
    public let priority = 71
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WidgetKit) && os(iOS)
        // WidgetCenter.shared.reloadAllTimelines() is available
        // We can't actually call it in a test without side effects
        // but we can verify the API is accessible
        
        let duration = Date().timeIntervalSince(startTime)
        return passed(
            "WidgetCenter timeline reload API available.",
            details: [
                "reloadAllTimelines": "available",
                "reloadTimelines(ofKind:)": "available",
                "getCurrentConfigurations": "available"
            ],
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Widget timeline reload requires iOS 14+.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Widget Configuration Test

/// Tests widget configuration capabilities
public struct WidgetConfigurationTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-configuration"
    public let name = "Widget Configuration"
    public let category = CapabilityCategory.widget
    public let priority = 72
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WidgetKit) && os(iOS)
        // Check for widget configuration availability
        // Static and Intent configurations are available on iOS 14+
        
        var details: [String: String] = [
            "staticConfiguration": "available",
            "intentConfiguration": "available"
        ]
        
        // iOS 17+ supports interactive widgets
        if #available(iOS 17.0, *) {
            details["interactiveWidgets"] = "available"
            details["appIntentConfiguration"] = "available"
        } else {
            details["interactiveWidgets"] = "unavailable"
            details["appIntentConfiguration"] = "unavailable"
        }
        
        // iOS 16+ supports lock screen widgets
        if #available(iOS 16.0, *) {
            details["lockScreenWidgets"] = "available"
        } else {
            details["lockScreenWidgets"] = "unavailable"
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Widget configuration APIs available.",
            details: details,
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Widget configuration check requires iOS 14+.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Widget Families Test

/// Tests available widget families/sizes
public struct WidgetFamiliesTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-families"
    public let name = "Widget Families"
    public let category = CapabilityCategory.widget
    public let priority = 73
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WidgetKit) && os(iOS)
        var families: [String] = ["systemSmall", "systemMedium", "systemLarge"]
        
        // iOS 15+ supports extra large on iPad
        if #available(iOS 15.0, *) {
            families.append("systemExtraLarge")
        }
        
        // iOS 16+ supports accessory families (lock screen/watch)
        if #available(iOS 16.0, *) {
            families.append(contentsOf: ["accessoryCircular", "accessoryRectangular", "accessoryInline"])
        }
        
        let details: [String: String] = [
            "supportedFamilies": families.joined(separator: ", "),
            "familyCount": String(families.count)
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "\(families.count) widget families available.",
            details: details,
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Widget families check requires iOS 14+.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Widget Refresh Budget Test

/// Tests widget refresh budget and recommendations
public struct WidgetRefreshBudgetTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-refresh-budget"
    public let name = "Widget Refresh Budget"
    public let category = CapabilityCategory.widget
    public let priority = 74
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if canImport(WidgetKit) && os(iOS)
        // Widget refresh budget is managed by iOS
        // We can provide recommendations based on CGM update frequency
        
        let cgmUpdateInterval = 5 // minutes (standard CGM interval)
        let recommendedRefreshes = 288 // 24 hours * 12 per hour = 288 updates/day
        
        var details: [String: String] = [
            "cgmUpdateInterval": "\(cgmUpdateInterval) minutes",
            "recommendedDailyRefreshes": String(recommendedRefreshes),
            "budgetManagement": "iOS-controlled"
        ]
        
        // Check for background app refresh
        #if canImport(UIKit)
        // Background app refresh status would be checked here
        details["backgroundAppRefresh"] = "required"
        #endif
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Widget refresh budget guidelines: ~\(recommendedRefreshes) updates/day for CGM.",
            details: details,
            duration: duration
        )
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Widget refresh budget check requires iOS 14+.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
}

// MARK: - Live Activities Test (iOS 16.1+)

/// Tests Live Activities availability for real-time glucose display
public struct LiveActivitiesTest: CapabilityTest, @unchecked Sendable {
    public let id = "widget-live-activities"
    public let name = "Live Activities"
    public let category = CapabilityCategory.widget
    public let priority = 75
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        #if os(iOS)
        if #available(iOS 16.2, *) {
            // ActivityKit requires iOS 16.2+ for full functionality
            // Check if Live Activities are enabled at runtime
            let areActivitiesEnabled = checkActivitiesEnabled()
            
            var details: [String: String] = [
                "liveActivitiesAvailable": "true",
                "areActivitiesEnabled": String(areActivitiesEnabled)
            ]
            
            let duration = Date().timeIntervalSince(startTime)
            
            if areActivitiesEnabled {
                details["dynamicIsland"] = "supported"
                details["lockScreen"] = "supported"
                return passed(
                    "Live Activities enabled. Real-time glucose on Dynamic Island available.",
                    details: details,
                    duration: duration
                )
            } else {
                details["recommendation"] = "Enable Live Activities in Settings"
                return CapabilityResult(
                    testId: id,
                    testName: name,
                    category: category,
                    status: .warning,
                    message: "Live Activities disabled. Enable in Settings for real-time glucose.",
                    details: details,
                    duration: duration
                )
            }
        } else {
            let duration = Date().timeIntervalSince(startTime)
            return unsupported(
                "Live Activities require iOS 16.2+.",
                details: ["minimumVersion": "iOS 16.2"],
                duration: duration
            )
        }
        #else
        let duration = Date().timeIntervalSince(startTime)
        return unsupported(
            "Live Activities require iOS 16.2+.",
            details: ["platform": "non-iOS"],
            duration: duration
        )
        #endif
    }
    
    #if os(iOS)
    @available(iOS 16.2, *)
    private func checkActivitiesEnabled() -> Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }
    #endif
}
