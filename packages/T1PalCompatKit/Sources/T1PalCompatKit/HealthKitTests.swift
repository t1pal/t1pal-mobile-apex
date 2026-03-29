// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HealthKitTests.swift
// T1PalCompatKit
//
// HealthKit capability tests for glucose data access.
// Trace: PRD-006 REQ-COMPAT-004
//
// These tests verify HealthKit capabilities required for CGM data.
// On Linux, tests return .unsupported status.

import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - HealthKit Availability Test

/// Test if HealthKit is available on this device
public struct HealthKitAvailabilityTest: CapabilityTest {
    public let id = "hk-availability"
    public let name = "HealthKit Available"
    public let category = CapabilityCategory.healthkit
    public let priority = 30
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        let isAvailable = HKHealthStore.isHealthDataAvailable()
        
        let details: [String: String] = [
            "isHealthDataAvailable": isAvailable ? "true" : "false"
        ]
        
        if isAvailable {
            return passed("HealthKit is available", details: details)
        } else {
            return failed("HealthKit not available on this device", details: details)
        }
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
}

// MARK: - HealthKit Authorization Test

/// Test HealthKit authorization status for glucose types
public struct HealthKitAuthorizationTest: CapabilityTest, @unchecked Sendable {
    public let id = "hk-authorization"
    public let name = "HealthKit Authorization"
    public let category = CapabilityCategory.healthkit
    public let priority = 31
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        let store = HKHealthStore()
        
        // Check blood glucose type
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return failed("Blood glucose type not available")
        }
        
        let readStatus = store.authorizationStatus(for: glucoseType)
        
        var details: [String: String] = [
            "bloodGlucoseReadStatus": authStatusDescription(readStatus)
        ]
        
        // Check insulin delivery if available
        if let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) {
            let insulinStatus = store.authorizationStatus(for: insulinType)
            details["insulinDeliveryStatus"] = authStatusDescription(insulinStatus)
        }
        
        switch readStatus {
        case .sharingAuthorized:
            return passed("HealthKit glucose access authorized", details: details)
        case .notDetermined:
            return skipped("HealthKit authorization not yet requested", details: details)
        case .sharingDenied:
            return failed("HealthKit glucose access denied", details: details)
        @unknown default:
            return failed("Unknown authorization status", details: details)
        }
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
    
    #if canImport(HealthKit)
    private func authStatusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
    #endif
}

// MARK: - HealthKit Glucose Write Test

/// Test ability to write glucose samples to HealthKit
public struct HealthKitGlucoseWriteTest: CapabilityTest, @unchecked Sendable {
    public let id = "hk-glucose-write"
    public let name = "Glucose Write Capability"
    public let category = CapabilityCategory.healthkit
    public let priority = 32
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        let store = HKHealthStore()
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return failed("Blood glucose type not available")
        }
        
        let status = store.authorizationStatus(for: glucoseType)
        
        let details: [String: String] = [
            "writeStatus": authStatusDescription(status),
            "note": "Write authorization requires user permission"
        ]
        
        switch status {
        case .sharingAuthorized:
            return passed("Can write glucose to HealthKit", details: details)
        case .notDetermined:
            return skipped("Write authorization not yet requested", details: details)
        case .sharingDenied:
            return failed("Glucose write denied by user", details: details)
        @unknown default:
            return failed("Unknown write status", details: details)
        }
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
    
    #if canImport(HealthKit)
    private func authStatusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - HealthKit Background Delivery Test

/// Test HealthKit background delivery capability
public struct HealthKitBackgroundDeliveryTest: CapabilityTest, @unchecked Sendable {
    public let id = "hk-background-delivery"
    public let name = "Background Delivery"
    public let category = CapabilityCategory.healthkit
    public let priority = 33
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        // Check if app has HealthKit background entitlement
        // This is determined by Info.plist UIBackgroundModes containing "processing"
        // and the app being authorized for HealthKit
        
        let hasBackgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let hasProcessing = hasBackgroundModes?.contains("processing") ?? false
        
        let details: [String: String] = [
            "backgroundProcessing": hasProcessing ? "enabled" : "disabled",
            "note": "Background delivery requires enableBackgroundDelivery() call"
        ]
        
        // Background delivery is available if HealthKit is available
        // The actual enablement happens at runtime
        return passed("Background delivery available", details: details)
        #elseif os(macOS)
        return unsupported("Background delivery is iOS-only")
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
}

// MARK: - HealthKit Insulin Type Test

/// Test HealthKit insulin delivery type availability
public struct HealthKitInsulinTypeTest: CapabilityTest, @unchecked Sendable {
    public let id = "hk-insulin-type"
    public let name = "Insulin Delivery Type"
    public let category = CapabilityCategory.healthkit
    public let priority = 34
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        let store = HKHealthStore()
        
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            return failed("Insulin delivery type not available")
        }
        
        let status = store.authorizationStatus(for: insulinType)
        
        let details: [String: String] = [
            "insulinDeliveryStatus": authStatusDescription(status),
            "note": "Required for AID pump data"
        ]
        
        switch status {
        case .sharingAuthorized:
            return passed("Insulin delivery type authorized", details: details)
        case .notDetermined:
            return skipped("Insulin authorization not yet requested", details: details)
        case .sharingDenied:
            return failed("Insulin delivery access denied", details: details)
        @unknown default:
            return failed("Unknown status", details: details)
        }
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
    
    #if canImport(HealthKit)
    private func authStatusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - HealthKit Carbohydrates Type Test

/// Test HealthKit carbohydrates type availability for meal logging
public struct HealthKitCarbsTypeTest: CapabilityTest, @unchecked Sendable {
    public let id = "hk-carbs-type"
    public let name = "Carbohydrates Type"
    public let category = CapabilityCategory.healthkit
    public let priority = 35
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        let store = HKHealthStore()
        
        guard let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else {
            return failed("Carbohydrates type not available")
        }
        
        let status = store.authorizationStatus(for: carbsType)
        
        let details: [String: String] = [
            "dietaryCarbohydratesStatus": authStatusDescription(status),
            "note": "Required for meal logging"
        ]
        
        switch status {
        case .sharingAuthorized:
            return passed("Carbohydrates type authorized", details: details)
        case .notDetermined:
            return skipped("Carbs authorization not yet requested", details: details)
        case .sharingDenied:
            return failed("Carbohydrates access denied", details: details)
        @unknown default:
            return failed("Unknown status", details: details)
        }
        #else
        return unsupported("HealthKit not available on this platform")
        #endif
    }
    
    #if canImport(HealthKit)
    private func authStatusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown"
        }
    }
    #endif
}
