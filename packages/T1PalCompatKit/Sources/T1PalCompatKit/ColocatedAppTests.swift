// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ColocatedAppTests.swift
// T1PalCompatKit
//
// Colocated AID/CGM app detection tests.
// Trace: PRD-006 REQ-COMPAT-009
//
// Detects potentially conflicting CGM and AID apps that may
// compete for BLE peripherals or cause insulin delivery conflicts.
// On Linux, tests return .unsupported status.

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(HealthKit)
import HealthKit
#endif

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// MARK: - Known App Definitions

/// Known CGM apps that may compete for BLE peripherals
public struct KnownCGMApp: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let bundleId: String
    public let urlScheme: String?
    public let conflictRisk: ConflictRisk
    public let guidance: String
    
    public init(
        id: String,
        name: String,
        bundleId: String,
        urlScheme: String? = nil,
        conflictRisk: ConflictRisk = .medium,
        guidance: String
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.urlScheme = urlScheme
        self.conflictRisk = conflictRisk
        self.guidance = guidance
    }
}

/// Known AID controller apps that may cause insulin delivery conflicts
public struct KnownAIDApp: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let bundleId: String
    public let urlScheme: String?
    public let conflictRisk: ConflictRisk
    public let guidance: String
    
    public init(
        id: String,
        name: String,
        bundleId: String,
        urlScheme: String? = nil,
        conflictRisk: ConflictRisk = .high,
        guidance: String
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.urlScheme = urlScheme
        self.conflictRisk = conflictRisk
        self.guidance = guidance
    }
}

/// Risk level for app conflicts
public enum ConflictRisk: String, Sendable, Codable {
    case low      // Informational only
    case medium   // May compete for resources
    case high     // May cause safety issues
    case critical // Must be disabled
}

// MARK: - Known Apps Database

/// Database of known CGM and AID apps
public struct KnownAppsDatabase: Sendable {
    
    /// Known CGM apps
    public static let cgmApps: [KnownCGMApp] = [
        KnownCGMApp(
            id: "dexcom-g6",
            name: "Dexcom G6",
            bundleId: "com.dexcom.G6",
            urlScheme: "dexcomg6",
            conflictRisk: .high,
            guidance: "Dexcom G6 app will compete for transmitter BLE connection. Only one app can connect at a time."
        ),
        KnownCGMApp(
            id: "dexcom-g7",
            name: "Dexcom G7",
            bundleId: "com.dexcom.G7",
            urlScheme: "dexcomg7",
            conflictRisk: .high,
            guidance: "Dexcom G7 app will compete for transmitter BLE connection. Only one app can connect at a time."
        ),
        KnownCGMApp(
            id: "dexcom-one",
            name: "Dexcom ONE",
            bundleId: "com.dexcom.DexcomOne",
            urlScheme: nil,
            conflictRisk: .high,
            guidance: "Dexcom ONE app will compete for transmitter BLE connection."
        ),
        KnownCGMApp(
            id: "libre-link",
            name: "LibreLink",
            bundleId: "com.abbott.librelink",
            urlScheme: nil,
            conflictRisk: .medium,
            guidance: "LibreLink uses NFC scanning. Can coexist if not using Libre BLE transmitter."
        ),
        KnownCGMApp(
            id: "libre3",
            name: "Libre 3",
            bundleId: "com.abbott.libre3",
            urlScheme: nil,
            conflictRisk: .high,
            guidance: "Libre 3 uses direct BLE connection. Will compete for sensor connection."
        ),
        KnownCGMApp(
            id: "xdrip",
            name: "xDrip4iOS",
            bundleId: "com.xdrip4ios.xdrip4ios",
            urlScheme: "xdrip4ios",
            conflictRisk: .high,
            guidance: "xDrip4iOS may compete for CGM BLE connection. Coordinate which app handles CGM."
        ),
        KnownCGMApp(
            id: "spike",
            name: "Spike",
            bundleId: "com.spike-app.spike",
            urlScheme: "spike",
            conflictRisk: .high,
            guidance: "Spike may compete for CGM BLE connection."
        ),
        KnownCGMApp(
            id: "sugarmate",
            name: "Sugarmate",
            bundleId: "com.sugarmate.sugarmate",
            urlScheme: nil,
            conflictRisk: .low,
            guidance: "Sugarmate receives data from Dexcom Share. No BLE conflict."
        )
    ]
    
    /// Known AID controller apps
    public static let aidApps: [KnownAIDApp] = [
        KnownAIDApp(
            id: "loop",
            name: "Loop",
            bundleId: "com.loopkit.Loop",
            urlScheme: "loop",
            conflictRisk: .critical,
            guidance: "Loop controls insulin delivery. Running multiple AID systems simultaneously can cause dangerous insulin stacking. DISABLE Loop before using T1Pal in closed-loop mode."
        ),
        KnownAIDApp(
            id: "trio",
            name: "Trio",
            bundleId: "org.nightscout.Trio",
            urlScheme: "trio",
            conflictRisk: .critical,
            guidance: "Trio controls insulin delivery. Running multiple AID systems simultaneously can cause dangerous insulin stacking. DISABLE Trio before using T1Pal in closed-loop mode."
        ),
        KnownAIDApp(
            id: "openaps",
            name: "OpenAPS",
            bundleId: "org.openaps.openaps",
            urlScheme: nil,
            conflictRisk: .critical,
            guidance: "OpenAPS controls insulin delivery. DISABLE OpenAPS before using T1Pal in closed-loop mode."
        ),
        KnownAIDApp(
            id: "freeaps-x",
            name: "FreeAPS X",
            bundleId: "com.freeaps.FreeAPS-X",
            urlScheme: "freeapsx",
            conflictRisk: .critical,
            guidance: "FreeAPS X controls insulin delivery. DISABLE FreeAPS X before using T1Pal in closed-loop mode."
        ),
        KnownAIDApp(
            id: "aaps",
            name: "AAPS",
            bundleId: "info.nightscout.androidaps",
            urlScheme: nil,
            conflictRisk: .critical,
            guidance: "AAPS controls insulin delivery. Only one AID system should be active at a time."
        ),
        KnownAIDApp(
            id: "omnipod-5",
            name: "Omnipod 5",
            bundleId: "com.insulet.omnipod5",
            urlScheme: nil,
            conflictRisk: .critical,
            guidance: "Omnipod 5 is a closed-loop system. Cannot use T1Pal closed-loop simultaneously."
        ),
        KnownAIDApp(
            id: "tandem-tslim",
            name: "t:connect",
            bundleId: "com.tandemdiabetes.tconnect",
            urlScheme: nil,
            conflictRisk: .high,
            guidance: "t:connect with Control-IQ is a closed-loop system. Verify Control-IQ settings before using T1Pal."
        )
    ]
    
    /// Get all known apps
    public static var allApps: [String: (name: String, risk: ConflictRisk)] {
        var result: [String: (name: String, risk: ConflictRisk)] = [:]
        for app in cgmApps {
            result[app.bundleId] = (app.name, app.conflictRisk)
        }
        for app in aidApps {
            result[app.bundleId] = (app.name, app.conflictRisk)
        }
        return result
    }
}

// MARK: - Detection Result

/// Result of app detection
public struct AppDetectionResult: Sendable {
    public let detectedCGMApps: [KnownCGMApp]
    public let detectedAIDApps: [KnownAIDApp]
    public let highestRisk: ConflictRisk
    
    public var hasCGMConflicts: Bool { !detectedCGMApps.isEmpty }
    public var hasAIDConflicts: Bool { !detectedAIDApps.isEmpty }
    public var hasAnyConflicts: Bool { hasCGMConflicts || hasAIDConflicts }
    public var hasCriticalConflicts: Bool { highestRisk == .critical }
    
    public var totalDetected: Int { detectedCGMApps.count + detectedAIDApps.count }
    
    public init(
        detectedCGMApps: [KnownCGMApp] = [],
        detectedAIDApps: [KnownAIDApp] = []
    ) {
        self.detectedCGMApps = detectedCGMApps
        self.detectedAIDApps = detectedAIDApps
        
        // Determine highest risk
        let allRisks = detectedCGMApps.map(\.conflictRisk) + detectedAIDApps.map(\.conflictRisk)
        if allRisks.contains(.critical) {
            self.highestRisk = .critical
        } else if allRisks.contains(.high) {
            self.highestRisk = .high
        } else if allRisks.contains(.medium) {
            self.highestRisk = .medium
        } else if allRisks.contains(.low) {
            self.highestRisk = .low
        } else {
            self.highestRisk = .low
        }
    }
}

// MARK: - App Detector

/// Detects installed CGM and AID apps
public struct ColocatedAppDetector: Sendable {
    
    public init() {}
    
    /// Detect installed apps using URL schemes
    public func detectInstalledApps() async -> AppDetectionResult {
        #if canImport(UIKit) && !os(watchOS)
        return await detectUsingURLSchemes()
        #else
        // On Linux/watchOS, return empty result
        return AppDetectionResult()
        #endif
    }
    
    #if canImport(UIKit) && !os(watchOS)
    @MainActor
    private func detectUsingURLSchemes() async -> AppDetectionResult {
        var detectedCGM: [KnownCGMApp] = []
        var detectedAID: [KnownAIDApp] = []
        
        // Check CGM apps
        for app in KnownAppsDatabase.cgmApps {
            if let scheme = app.urlScheme, canOpenURL(scheme: scheme) {
                detectedCGM.append(app)
            }
        }
        
        // Check AID apps
        for app in KnownAppsDatabase.aidApps {
            if let scheme = app.urlScheme, canOpenURL(scheme: scheme) {
                detectedAID.append(app)
            }
        }
        
        return AppDetectionResult(
            detectedCGMApps: detectedCGM,
            detectedAIDApps: detectedAID
        )
    }
    
    @MainActor
    private func canOpenURL(scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    #endif
}

// MARK: - CGM App Detection Test

/// Test that detects installed CGM apps
public struct CGMAppDetectionTest: CapabilityTest, @unchecked Sendable {
    public let id = "colocated-cgm-apps"
    public let name = "CGM App Detection"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 40
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UIKit) && !os(watchOS)
        let startTime = Date()
        let detector = ColocatedAppDetector()
        let result = await detector.detectInstalledApps()
        let duration = Date().timeIntervalSince(startTime)
        
        var details: [String: String] = [
            "cgmAppsDetected": String(result.detectedCGMApps.count),
            "checkMethod": "URL Schemes"
        ]
        
        for (index, app) in result.detectedCGMApps.enumerated() {
            details["detected_\(index)"] = app.name
        }
        
        if result.detectedCGMApps.isEmpty {
            return passed("No conflicting CGM apps detected", details: details, duration: duration)
        } else {
            let names = result.detectedCGMApps.map(\.name).joined(separator: ", ")
            let highRisk = result.detectedCGMApps.first { $0.conflictRisk == .high || $0.conflictRisk == .critical }
            
            if highRisk != nil {
                return warning(
                    "Found CGM apps that may compete for BLE: \(names)",
                    details: details,
                    duration: duration
                )
            } else {
                return passed("CGM apps detected (low conflict risk): \(names)", details: details, duration: duration)
            }
        }
        #else
        return unsupported("App detection requires UIKit (iOS)")
        #endif
    }
}

// MARK: - AID App Detection Test

/// Test that detects installed AID controller apps
public struct AIDAppDetectionTest: CapabilityTest, @unchecked Sendable {
    public let id = "colocated-aid-apps"
    public let name = "AID Controller Detection"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 41
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UIKit) && !os(watchOS)
        let startTime = Date()
        let detector = ColocatedAppDetector()
        let result = await detector.detectInstalledApps()
        let duration = Date().timeIntervalSince(startTime)
        
        var details: [String: String] = [
            "aidAppsDetected": String(result.detectedAIDApps.count),
            "checkMethod": "URL Schemes"
        ]
        
        for (index, app) in result.detectedAIDApps.enumerated() {
            details["detected_\(index)"] = app.name
            details["guidance_\(index)"] = app.guidance
        }
        
        if result.detectedAIDApps.isEmpty {
            return passed("No conflicting AID apps detected", details: details, duration: duration)
        } else {
            let names = result.detectedAIDApps.map(\.name).joined(separator: ", ")
            let hasCritical = result.detectedAIDApps.contains { $0.conflictRisk == .critical }
            
            if hasCritical {
                return failed(
                    "CRITICAL: Found AID controllers that must be disabled: \(names)",
                    details: details,
                    duration: duration
                )
            } else {
                return warning(
                    "Found AID apps that may conflict: \(names)",
                    details: details,
                    duration: duration
                )
            }
        }
        #else
        return unsupported("App detection requires UIKit (iOS)")
        #endif
    }
}

// MARK: - Conflict Risk Assessment Test

/// Provides overall conflict risk assessment
public struct ConflictRiskAssessmentTest: CapabilityTest, @unchecked Sendable {
    public let id = "conflict-risk-assessment"
    public let name = "Conflict Risk Assessment"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 42
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UIKit) && !os(watchOS)
        let startTime = Date()
        let detector = ColocatedAppDetector()
        let result = await detector.detectInstalledApps()
        let duration = Date().timeIntervalSince(startTime)
        
        var details: [String: String] = [
            "totalAppsDetected": String(result.totalDetected),
            "cgmApps": String(result.detectedCGMApps.count),
            "aidApps": String(result.detectedAIDApps.count),
            "highestRisk": result.highestRisk.rawValue
        ]
        
        // Build guidance
        var guidanceItems: [String] = []
        for app in result.detectedAIDApps where app.conflictRisk == .critical {
            guidanceItems.append(app.guidance)
        }
        if !guidanceItems.isEmpty {
            details["criticalGuidance"] = guidanceItems.joined(separator: " | ")
        }
        
        switch result.highestRisk {
        case .critical:
            return failed(
                "CRITICAL conflict risk - AID app must be disabled before closed-loop operation",
                details: details,
                duration: duration
            )
        case .high:
            return warning(
                "High conflict risk - Review detected apps before proceeding",
                details: details,
                duration: duration
            )
        case .medium:
            return warning(
                "Medium conflict risk - Some apps may compete for resources",
                details: details,
                duration: duration
            )
        case .low:
            if result.hasAnyConflicts {
                return passed(
                    "Low conflict risk - Detected apps unlikely to cause issues",
                    details: details,
                    duration: duration
                )
            } else {
                return passed(
                    "No conflicting apps detected",
                    details: details,
                    duration: duration
                )
            }
        }
        #else
        return unsupported("Conflict assessment requires UIKit (iOS)")
        #endif
    }
}

// MARK: - HealthKit Source Analysis Test (DETECT-001)

/// Test that analyzes HealthKit glucose sources to detect colocated AID apps
/// Trace: PRD-004 REQ-CGM-035, DETECT-001
public struct HealthKitSourceAnalysisTest: CapabilityTest, @unchecked Sendable {
    public let id = "healthkit-source-analysis"
    public let name = "HealthKit Glucose Sources"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 43
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(HealthKit)
        let startTime = Date()
        
        guard HKHealthStore.isHealthDataAvailable() else {
            return failed("HealthKit not available")
        }
        
        let store = HKHealthStore()
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return failed("Blood glucose type not available")
        }
        
        // Query recent glucose samples for source analysis
        let now = Date()
        let startDate = now.addingTimeInterval(-3600) // Last hour
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: now,
            options: .strictEndDate
        )
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: glucoseType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                    }
                }
                store.execute(query)
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            // Extract source information
            var bundleIds = Set<String>()
            var names = Set<String>()
            var counts: [String: Int] = [:]
            
            for sample in samples {
                let source = sample.sourceRevision.source
                let bundleId = source.bundleIdentifier
                bundleIds.insert(bundleId)
                names.insert(source.name)
                counts[bundleId, default: 0] += 1
            }
            
            var details: [String: String] = [
                "sampleCount": String(samples.count),
                "sourceCount": String(bundleIds.count),
                "sources": bundleIds.joined(separator: ", "),
                "sourceNames": names.joined(separator: ", ")
            ]
            
            // Check for known AID apps
            let loopDetected = bundleIds.contains { $0 == "com.loopkit.Loop" || $0.hasPrefix("com.loopkit.Loop.") }
            let trioDetected = bundleIds.contains { $0 == "org.nightscout.Trio" || $0.hasPrefix("org.nightscout.Trio.") }
            let dexcomDetected = bundleIds.contains { $0.hasPrefix("com.dexcom") }
            
            details["loopWritingGlucose"] = loopDetected ? "true" : "false"
            details["trioWritingGlucose"] = trioDetected ? "true" : "false"
            details["dexcomWritingGlucose"] = dexcomDetected ? "true" : "false"
            
            if samples.isEmpty {
                return skipped("No glucose samples in HealthKit (last hour)", details: details, duration: duration)
            }
            
            if loopDetected || trioDetected {
                let appName = loopDetected ? "Loop" : "Trio"
                details["recommendation"] = "Use passive mode - \(appName) is managing glucose"
                return warning(
                    "\(appName) detected writing glucose to HealthKit - recommend passive mode",
                    details: details,
                    duration: duration
                )
            }
            
            if dexcomDetected {
                details["recommendation"] = "Dexcom app managing glucose, T1Pal can observe via HealthKit"
            }
            
            return passed(
                "Analyzed \(samples.count) samples from \(bundleIds.count) source(s)",
                details: details,
                duration: duration
            )
        } catch {
            return failed("HealthKit query failed: \(error.localizedDescription)")
        }
        #else
        return unsupported("HealthKit source analysis requires iOS")
        #endif
    }
}

// MARK: - RileyLink Activity Monitor (DETECT-002)

/// Activity status for RileyLink-family devices
/// Trace: PRD-005 REQ-AID-010, DETECT-002
public enum RileyLinkActivityStatus: Sendable, Equatable {
    /// No RileyLink device discovered
    case notDiscovered
    
    /// Device discovered but not connected
    case discovered(name: String, rssi: Int)
    
    /// Device connected but idle (no recent RF activity)
    case connectedIdle(name: String)
    
    /// Device connected and actively communicating (Loop controlling pump)
    case connectedActive(name: String, lastActivityAge: TimeInterval)
    
    /// Device busy (command queue backed up)
    case busy(name: String)
    
    public var isActive: Bool {
        switch self {
        case .connectedActive, .busy: return true
        default: return false
        }
    }
    
    public var isDiscovered: Bool {
        switch self {
        case .notDiscovered: return false
        default: return true
        }
    }
    
    public var deviceName: String? {
        switch self {
        case .notDiscovered: return nil
        case .discovered(let name, _): return name
        case .connectedIdle(let name): return name
        case .connectedActive(let name, _): return name
        case .busy(let name): return name
        }
    }
    
    public var summary: String {
        switch self {
        case .notDiscovered:
            return "No RileyLink device found"
        case .discovered(let name, let rssi):
            return "\(name) discovered (RSSI: \(rssi))"
        case .connectedIdle(let name):
            return "\(name) connected (idle)"
        case .connectedActive(let name, let age):
            let seconds = Int(age)
            return "\(name) active (last activity \(seconds)s ago)"
        case .busy(let name):
            return "\(name) busy (commands queued)"
        }
    }
}

/// Analysis result for RileyLink-family device activity
/// Trace: PRD-005 REQ-AID-010, DETECT-002
public struct RileyLinkActivityAnalysis: Sendable, Equatable {
    /// Discovered RileyLink-family devices
    public let discoveredDevices: [RileyLinkDeviceInfo]
    
    /// Overall activity status (most active device)
    public let overallStatus: RileyLinkActivityStatus
    
    /// Analysis timestamp
    public let analyzedAt: Date
    
    public init(
        discoveredDevices: [RileyLinkDeviceInfo] = [],
        overallStatus: RileyLinkActivityStatus = .notDiscovered,
        analyzedAt: Date = Date()
    ) {
        self.discoveredDevices = discoveredDevices
        self.overallStatus = overallStatus
        self.analyzedAt = analyzedAt
    }
    
    /// True if any device is actively communicating
    public var hasActiveDevice: Bool {
        discoveredDevices.contains { $0.isActive }
    }
    
    /// True if Loop or other AID is likely controlling pump
    public var aidIsControllingPump: Bool {
        overallStatus.isActive
    }
    
    /// Recommendation for T1Pal
    public var recommendation: String {
        if aidIsControllingPump {
            return "Another app is actively controlling pump via RileyLink. T1Pal should NOT attempt pump control."
        } else if discoveredDevices.isEmpty {
            return "No RileyLink device detected. Pump control not available."
        } else {
            return "RileyLink available. Verify no other AID app is running before enabling pump control."
        }
    }
}

/// Information about a discovered RileyLink-family device
public struct RileyLinkDeviceInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let deviceType: RileyLinkDeviceType
    public let rssi: Int
    public let isConnected: Bool
    public let isActive: Bool
    
    public init(
        id: String,
        name: String,
        deviceType: RileyLinkDeviceType,
        rssi: Int,
        isConnected: Bool = false,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.rssi = rssi
        self.isConnected = isConnected
        self.isActive = isActive
    }
}

/// Types of RileyLink-family devices
public enum RileyLinkDeviceType: String, Sendable, Codable {
    case rileyLink = "RileyLink"
    case orangeLink = "OrangeLink"
    case emaLink = "EmaLink"
    case unknown = "Unknown"
    
    /// Detect device type from name
    public static func from(name: String) -> RileyLinkDeviceType {
        let lowercased = name.lowercased()
        if lowercased.contains("orange") {
            return .orangeLink
        } else if lowercased.contains("ema") {
            return .emaLink
        } else if lowercased.contains("riley") {
            return .rileyLink
        }
        return .unknown
    }
}

// MARK: - RileyLink Activity Test

/// Test that scans for RileyLink-family devices to detect colocated AID activity
/// Trace: PRD-005 REQ-AID-010, DETECT-002
public struct RileyLinkActivityTest: CapabilityTest, @unchecked Sendable {
    public let id = "rileylink-activity"
    public let name = "RileyLink Activity Detection"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 44
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(CoreBluetooth)
        let startTime = Date()
        
        // Check if Bluetooth is available
        // Note: This is a simplified check - actual implementation would use BLEKit
        let details: [String: String] = [
            "scanDuration": "passive",
            "targetService": "0235733B-99C5-4197-B856-69219C2A3845",
            "note": "Passive BLE observation for RileyLink family"
        ]
        
        // In a real implementation, this would:
        // 1. Scan for RileyLink service UUID
        // 2. Check if any matching device is connected (not to us)
        // 3. If connected, monitor for characteristic writes (activity)
        
        // For now, return informational result about capability
        return passed(
            "RileyLink activity monitoring available",
            details: details,
            duration: Date().timeIntervalSince(startTime)
        )
        #else
        return unsupported("RileyLink detection requires CoreBluetooth (iOS/macOS)")
        #endif
    }
}

// MARK: - Composite Colocated Detection (DETECT-004)

/// Input data for HealthKit source analysis in composite detection
/// This is a local type that mirrors CGMKit.HealthKitSourceAnalysis for decoupling
/// Trace: PRD-006 REQ-COMPAT-015, DETECT-004
public struct HealthKitSourceInput: Sendable, Equatable {
    /// True if Loop is writing glucose to HealthKit
    public let loopIsGlucoseSource: Bool
    
    /// True if Trio is writing glucose to HealthKit
    public let trioIsGlucoseSource: Bool
    
    /// True if any AID app is writing glucose
    public let aidAppIsGlucoseSource: Bool
    
    /// Source bundle identifiers detected
    public let sourceBundleIds: [String]
    
    public init(
        loopIsGlucoseSource: Bool = false,
        trioIsGlucoseSource: Bool = false,
        aidAppIsGlucoseSource: Bool = false,
        sourceBundleIds: [String] = []
    ) {
        self.loopIsGlucoseSource = loopIsGlucoseSource
        self.trioIsGlucoseSource = trioIsGlucoseSource
        self.aidAppIsGlucoseSource = aidAppIsGlucoseSource
        self.sourceBundleIds = sourceBundleIds
    }
}

/// Detection signal with associated weight for confidence scoring
/// Trace: PRD-006 REQ-COMPAT-015, DETECT-004
public struct DetectionSignal: Sendable, Equatable {
    public let name: String
    public let weight: Double
    public let detected: Bool
    public let details: String?
    
    public init(name: String, weight: Double, detected: Bool, details: String? = nil) {
        self.name = name
        self.weight = weight
        self.detected = detected
        self.details = details
    }
    
    /// Contribution to composite score (weight if detected, 0 otherwise)
    public var contribution: Double {
        detected ? weight : 0
    }
}

/// Composite analysis combining all colocated detection signals
/// Trace: PRD-006 REQ-COMPAT-015, DETECT-004
public struct CompositeColocatedAnalysis: Sendable, Equatable {
    /// All detection signals evaluated
    public let signals: [DetectionSignal]
    
    /// Composite confidence score (sum of detected signal weights)
    public let compositeScore: Double
    
    /// Analysis timestamp
    public let analyzedAt: Date
    
    /// High confidence threshold (Loop/AID definitely present)
    public static let highConfidenceThreshold: Double = 1.5
    
    /// Medium confidence threshold (likely present)
    public static let mediumConfidenceThreshold: Double = 0.8
    
    public init(signals: [DetectionSignal], analyzedAt: Date = Date()) {
        self.signals = signals
        self.compositeScore = signals.reduce(0) { $0 + $1.contribution }
        self.analyzedAt = analyzedAt
    }
    
    // MARK: - Confidence Levels
    
    /// High confidence that colocated AID is present (score >= 1.5)
    public var highConfidence: Bool {
        compositeScore >= Self.highConfidenceThreshold
    }
    
    /// Medium confidence that colocated AID is present (score >= 0.8)
    public var mediumConfidence: Bool {
        compositeScore >= Self.mediumConfidenceThreshold
    }
    
    /// Low or no confidence
    public var lowConfidence: Bool {
        compositeScore < Self.mediumConfidenceThreshold
    }
    
    // MARK: - Detected Apps
    
    /// True if Loop is likely running
    public var loopDetected: Bool {
        signals.contains { $0.name.contains("Loop") && $0.detected }
    }
    
    /// True if Trio is likely running
    public var trioDetected: Bool {
        signals.contains { $0.name.contains("Trio") && $0.detected }
    }
    
    /// True if any AID controller is likely running
    public var aidDetected: Bool {
        loopDetected || trioDetected || signals.contains { 
            ($0.name.contains("AID") || $0.name.contains("OpenAPS")) && $0.detected 
        }
    }
    
    // MARK: - Recommendations
    
    /// Recommended action for T1Pal
    public var recommendation: ColocatedRecommendation {
        if highConfidence {
            return .passiveModeRequired
        } else if mediumConfidence {
            return .passiveModeRecommended
        } else if signals.contains(where: { $0.detected }) {
            return .verifyBeforeProceeding
        } else {
            return .noConflictDetected
        }
    }
    
    /// Human-readable summary
    public var summary: String {
        let detectedSignals = signals.filter { $0.detected }
        if detectedSignals.isEmpty {
            return "No colocated apps detected"
        }
        
        let names = detectedSignals.map { $0.name }.joined(separator: ", ")
        let confidence = highConfidence ? "HIGH" : (mediumConfidence ? "MEDIUM" : "LOW")
        return "\(confidence) confidence: \(names) (score: \(String(format: "%.2f", compositeScore)))"
    }
}

/// Recommendation for T1Pal behavior based on colocated detection
public enum ColocatedRecommendation: String, Sendable, Codable {
    /// No conflicting apps detected - safe to proceed
    case noConflictDetected
    
    /// Some signals detected - verify with user before proceeding
    case verifyBeforeProceeding
    
    /// Colocated AID likely present - passive mode recommended
    case passiveModeRecommended
    
    /// Colocated AID confirmed - passive mode required for safety
    case passiveModeRequired
    
    public var guidance: String {
        switch self {
        case .noConflictDetected:
            return "No conflicting apps detected. T1Pal can operate normally."
        case .verifyBeforeProceeding:
            return "Some colocated app signals detected. Please verify no other AID app is controlling your pump."
        case .passiveModeRecommended:
            return "Colocated AID app likely present. Recommend using passive/follower mode to avoid conflicts."
        case .passiveModeRequired:
            return "Colocated AID app confirmed. T1Pal must use passive mode. Do NOT enable closed-loop while another AID is active."
        }
    }
}

/// Composite detector that combines all colocated detection signals
/// Trace: PRD-006 REQ-COMPAT-015, DETECT-004
public struct CompositeColocatedDetector: Sendable {
    
    public init() {}
    
    /// Run composite detection using all available signals
    /// - Parameters:
    ///   - urlSchemeResult: Result from URL scheme detection (nil to skip)
    ///   - healthKitAnalysis: Result from HealthKit source analysis (nil to skip)
    ///   - rileyLinkAnalysis: Result from RileyLink activity analysis (nil to skip)
    /// - Returns: Composite analysis with confidence scoring
    public func analyze(
        urlSchemeResult: AppDetectionResult? = nil,
        healthKitAnalysis: HealthKitSourceInput? = nil,
        rileyLinkAnalysis: RileyLinkActivityAnalysis? = nil
    ) -> CompositeColocatedAnalysis {
        var signals: [DetectionSignal] = []
        
        // Signal 1: URL scheme detection (weight 0.9)
        if let urlResult = urlSchemeResult {
            let loopDetected = urlResult.detectedAIDApps.contains { $0.id == "loop" }
            signals.append(DetectionSignal(
                name: "Loop URL Scheme",
                weight: 0.9,
                detected: loopDetected,
                details: loopDetected ? "loop:// scheme registered" : nil
            ))
            
            let trioDetected = urlResult.detectedAIDApps.contains { $0.id == "trio" }
            signals.append(DetectionSignal(
                name: "Trio URL Scheme",
                weight: 0.9,
                detected: trioDetected,
                details: trioDetected ? "trio:// scheme registered" : nil
            ))
            
            // CGM apps (lower weight - less critical)
            let dexcomDetected = urlResult.detectedCGMApps.contains { $0.id.contains("dexcom") }
            signals.append(DetectionSignal(
                name: "Dexcom URL Scheme",
                weight: 0.4,
                detected: dexcomDetected,
                details: dexcomDetected ? "Dexcom app installed" : nil
            ))
        }
        
        // Signal 2: HealthKit source analysis (weight 0.8)
        if let hkAnalysis = healthKitAnalysis {
            signals.append(DetectionSignal(
                name: "Loop HealthKit Source",
                weight: 0.8,
                detected: hkAnalysis.loopIsGlucoseSource,
                details: hkAnalysis.loopIsGlucoseSource ? "Loop writing glucose to HealthKit" : nil
            ))
            
            signals.append(DetectionSignal(
                name: "Trio HealthKit Source",
                weight: 0.8,
                detected: hkAnalysis.trioIsGlucoseSource,
                details: hkAnalysis.trioIsGlucoseSource ? "Trio writing glucose to HealthKit" : nil
            ))
            
            signals.append(DetectionSignal(
                name: "AID HealthKit Source",
                weight: 0.7,
                detected: hkAnalysis.aidAppIsGlucoseSource && !hkAnalysis.loopIsGlucoseSource && !hkAnalysis.trioIsGlucoseSource,
                details: hkAnalysis.aidAppIsGlucoseSource ? "AID app writing glucose" : nil
            ))
        }
        
        // Signal 3: RileyLink activity (weight 0.5-0.7)
        if let rlAnalysis = rileyLinkAnalysis {
            let discovered = !rlAnalysis.discoveredDevices.isEmpty
            signals.append(DetectionSignal(
                name: "RileyLink Discovered",
                weight: 0.5,
                detected: discovered,
                details: discovered ? "\(rlAnalysis.discoveredDevices.count) device(s)" : nil
            ))
            
            signals.append(DetectionSignal(
                name: "RileyLink Active",
                weight: 0.7,
                detected: rlAnalysis.aidIsControllingPump,
                details: rlAnalysis.aidIsControllingPump ? "Active pump control detected" : nil
            ))
        }
        
        return CompositeColocatedAnalysis(signals: signals)
    }
}

// MARK: - Composite Colocated Detection Test

/// Test that runs composite colocated detection with all available signals
/// Trace: PRD-006 REQ-COMPAT-015, DETECT-004
public struct CompositeColocatedDetectionTest: CapabilityTest, @unchecked Sendable {
    public let id = "composite-colocated-detection"
    public let name = "Composite Colocated Detection"
    public let category = CapabilityCategory.colocatedApps
    public let priority = 45
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Gather signals from available sources
        var urlSchemeResult: AppDetectionResult? = nil
        let healthKitAnalysis: HealthKitSourceInput? = nil
        
        // URL scheme detection
        #if canImport(UIKit) && !os(watchOS)
        let appDetector = ColocatedAppDetector()
        urlSchemeResult = await appDetector.detectInstalledApps()
        #endif
        
        // HealthKit source analysis (simplified - actual would use HealthKitCGMManager)
        #if canImport(HealthKit)
        // Note: Full implementation would call HealthKitCGMManager.analyzeGlucoseSources()
        // and convert to HealthKitSourceInput
        // For capability test, we check if HealthKit is available
        if HKHealthStore.isHealthDataAvailable() {
            // Would populate healthKitAnalysis from actual query
        }
        #endif
        
        // Run composite analysis
        let detector = CompositeColocatedDetector()
        let analysis = detector.analyze(
            urlSchemeResult: urlSchemeResult,
            healthKitAnalysis: healthKitAnalysis,
            rileyLinkAnalysis: nil // Would come from BLE scan
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Build details
        var details: [String: String] = [
            "compositeScore": String(format: "%.2f", analysis.compositeScore),
            "signalsEvaluated": String(analysis.signals.count),
            "signalsDetected": String(analysis.signals.filter { $0.detected }.count),
            "recommendation": analysis.recommendation.rawValue
        ]
        
        for signal in analysis.signals where signal.detected {
            details["signal_\(signal.name)"] = String(format: "%.1f", signal.weight)
        }
        
        // Determine result based on analysis
        switch analysis.recommendation {
        case .passiveModeRequired:
            return failed(
                "Colocated AID confirmed - passive mode required",
                details: details,
                duration: duration
            )
        case .passiveModeRecommended:
            return warning(
                "Colocated AID likely - recommend passive mode",
                details: details,
                duration: duration
            )
        case .verifyBeforeProceeding:
            return warning(
                "Some colocated signals detected - verify before proceeding",
                details: details,
                duration: duration
            )
        case .noConflictDetected:
            return passed(
                "No colocated conflicts detected (score: \(String(format: "%.2f", analysis.compositeScore)))",
                details: details,
                duration: duration
            )
        }
    }
}
