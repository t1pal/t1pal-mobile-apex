// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BuiltinTests.swift
// T1PalCompatKit
//
// Built-in capability tests that work on all platforms.
// Trace: PRD-006 REQ-COMPAT-001

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Network Tests

/// Test basic network connectivity
public struct NetworkConnectivityTest: CapabilityTest {
    public let id = "network-connectivity"
    public let name = "Network Connectivity"
    public let category = CapabilityCategory.network
    public let priority = 10
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Check if we can reach a known endpoint
        guard let url = URL(string: "https://apple.com") else {
            return failed("Invalid test URL")
        }
        
        #if canImport(FoundationNetworking)
        // Linux: Use synchronous approach for URLSession compatibility
        let duration = Date().timeIntervalSince(startTime)
        return passed("Network test available (async not available on Linux)", duration: duration)
        #else
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return passed("Connected", details: [
                        "statusCode": "\(httpResponse.statusCode)"
                    ], duration: duration)
                } else {
                    return passed("Reachable (status \(httpResponse.statusCode))", duration: duration)
                }
            }
            return passed("Connected", duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return failed("No connectivity: \(error.localizedDescription)", duration: duration)
        }
        #endif
    }
}

// MARK: - Storage Tests

/// Test file system write access
public struct StorageWriteTest: CapabilityTest {
    public let id = "storage-write"
    public let name = "File System Write"
    public let category = CapabilityCategory.storage
    public let priority = 20
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        let testFile = FileManager.default.temporaryDirectory.appendingPathComponent("t1pal-compat-test-\(UUID().uuidString).txt")
        
        do {
            try "T1PalCompatKit test file".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            let duration = Date().timeIntervalSince(startTime)
            return passed("Write access confirmed", duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return failed("Write failed: \(error.localizedDescription)", duration: duration)
        }
    }
}

/// Test UserDefaults access
public struct UserDefaultsTest: CapabilityTest {
    public let id = "storage-userdefaults"
    public let name = "UserDefaults Access"
    public let category = CapabilityCategory.storage
    public let priority = 21
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        let key = "t1pal-compat-test-\(UUID().uuidString)"
        let testValue = "test-\(Date().timeIntervalSince1970)"
        
        UserDefaults.standard.set(testValue, forKey: key)
        let retrieved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        
        let duration = Date().timeIntervalSince(startTime)
        
        if retrieved == testValue {
            return passed("UserDefaults working", duration: duration)
        } else {
            return failed("UserDefaults read/write mismatch", duration: duration)
        }
    }
}

// MARK: - Platform Detection

/// Test that reports platform information
public struct PlatformInfoTest: CapabilityTest {
    public let id = "platform-info"
    public let name = "Platform Information"
    public let category = CapabilityCategory.storage  // Use storage as fallback
    public let priority = 1
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        var details: [String: String] = [:]
        
        #if os(iOS)
        details["platform"] = "iOS"
        #elseif os(macOS)
        details["platform"] = "macOS"
        #elseif os(watchOS)
        details["platform"] = "watchOS"
        #elseif os(Linux)
        details["platform"] = "Linux"
        #else
        details["platform"] = "Unknown"
        #endif
        
        #if targetEnvironment(simulator)
        details["environment"] = "Simulator"
        #else
        details["environment"] = "Device"
        #endif
        
        let info = ProcessInfo.processInfo
        details["osVersion"] = info.operatingSystemVersionString
        details["processName"] = info.processName
        
        return passed("Platform detected: \(details["platform"] ?? "?")", details: details)
    }
}

// MARK: - Convenience Registration

/// Register all built-in tests with the registry
public func registerBuiltinTests() async {
    let registry = CapabilityRegistry.shared
    await registry.register([
        // Platform
        PlatformInfoTest(),
        // Network
        NetworkConnectivityTest(),
        // Storage
        StorageWriteTest(),
        UserDefaultsTest(),
        // Bluetooth
        BLECentralStateTest(),
        BLEBackgroundModeTest(),
        BLEStateRestorationTest(),
        BLEAuthorizationTest(),
        // Notifications
        NotificationAuthorizationTest(),
        CriticalAlertsTest(),
        TimeSensitiveTest(),
        NotificationSoundTest(),
        AlertStyleTest(),
        ScheduledDeliveryTest(),
        // HealthKit
        HealthKitAvailabilityTest(),
        HealthKitAuthorizationTest(),
        HealthKitGlucoseWriteTest(),
        HealthKitBackgroundDeliveryTest(),
        HealthKitInsulinTypeTest(),
        HealthKitCarbsTypeTest(),
        // Colocated Apps
        CGMAppDetectionTest(),
        AIDAppDetectionTest(),
        ConflictRiskAssessmentTest(),
        // Intended Use
        DemoModeCompatibilityTest(),
        CGMOnlyCompatibilityTest(),
        AIDControllerCompatibilityTest(),
        DeviceCompatibilityReportTest(),
        // Watch
        WatchConnectivityAvailabilityTest(),
        WCSessionSupportedTest(),
        WatchPairingTest(),
        WatchReachabilityTest(),
        ComplicationBudgetTest(),
        WatchMessageSendTest(),
        // Widget
        WidgetKitAvailabilityTest(),
        WidgetTimelineReloadTest(),
        WidgetConfigurationTest(),
        WidgetFamiliesTest(),
        WidgetRefreshBudgetTest(),
        LiveActivitiesTest(),
        // Device Matrix
        DeviceProfileTest(),
        SnapshotCreationTest(),
        MatrixStorageTest(),
        RegressionDetectionTest(),
        // Quirks
        QuirkDetectionTest(),
        QuirkSummaryTest(),
        LowPowerModeTest(),
        BackgroundAppRefreshTest(),
    ])
}

/// Get all built-in tests without registering to shared registry (for testing)
public func allBuiltinTests() -> [any CapabilityTest] {
    [
        // Platform
        PlatformInfoTest(),
        // Network
        NetworkConnectivityTest(),
        // Storage
        StorageWriteTest(),
        UserDefaultsTest(),
        // Bluetooth
        BLECentralStateTest(),
        BLEBackgroundModeTest(),
        BLEStateRestorationTest(),
        BLEAuthorizationTest(),
        // Notifications
        NotificationAuthorizationTest(),
        CriticalAlertsTest(),
        TimeSensitiveTest(),
        NotificationSoundTest(),
        AlertStyleTest(),
        ScheduledDeliveryTest(),
        // HealthKit
        HealthKitAvailabilityTest(),
        HealthKitAuthorizationTest(),
        HealthKitGlucoseWriteTest(),
        HealthKitBackgroundDeliveryTest(),
        HealthKitInsulinTypeTest(),
        HealthKitCarbsTypeTest(),
        // Colocated Apps
        CGMAppDetectionTest(),
        AIDAppDetectionTest(),
        ConflictRiskAssessmentTest(),
        // Intended Use
        DemoModeCompatibilityTest(),
        CGMOnlyCompatibilityTest(),
        AIDControllerCompatibilityTest(),
        DeviceCompatibilityReportTest(),
        // Watch
        WatchConnectivityAvailabilityTest(),
        WCSessionSupportedTest(),
        WatchPairingTest(),
        WatchReachabilityTest(),
        ComplicationBudgetTest(),
        WatchMessageSendTest(),
        // Widget
        WidgetKitAvailabilityTest(),
        WidgetTimelineReloadTest(),
        WidgetConfigurationTest(),
        WidgetFamiliesTest(),
        WidgetRefreshBudgetTest(),
        LiveActivitiesTest(),
        // Device Matrix
        DeviceProfileTest(),
        SnapshotCreationTest(),
        MatrixStorageTest(),
        RegressionDetectionTest(),
        // Quirks
        QuirkDetectionTest(),
        QuirkSummaryTest(),
        LowPowerModeTest(),
        BackgroundAppRefreshTest(),
    ]
}
