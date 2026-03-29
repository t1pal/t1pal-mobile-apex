// SPDX-License-Identifier: AGPL-3.0-or-later
// ConnectionModeRecommender.swift
// CGMKit
//
// Recommends CGM connection mode based on detected colocated apps.
// Trace: PRD-004 REQ-CGM-009, CGM-027, BLE-QUIRK-002

import Foundation
import BLEKit
import T1PalCompatKit

// MARK: - BLE Coexistence Detection (BLE-QUIRK-002)

/// Detects nearby Dexcom G6 and G7 devices for coexistence warnings.
/// G6 uses 0xFEBC and G7 uses 0xFE59 - different UUIDs but user may have both.
/// Trace: BLE-QUIRK-002
public struct DexcomCoexistenceResult: Sendable {
    public let g6Detected: Bool
    public let g7Detected: Bool
    public let g6TransmitterId: String?
    public let g7SensorSerial: String?
    
    /// Whether both G6 and G7 are nearby
    public var hasBothNearby: Bool { g6Detected && g7Detected }
    
    /// Warning message if coexistence detected
    public var coexistenceWarning: String? {
        guard hasBothNearby else { return nil }
        return "Both Dexcom G6 and G7 detected nearby. Only one can be used at a time. Select the active sensor to connect."
    }
    
    public static let none = DexcomCoexistenceResult(g6Detected: false, g7Detected: false, g6TransmitterId: nil, g7SensorSerial: nil)
}

/// BLE scanner for detecting G6/G7 coexistence.
/// Trace: BLE-QUIRK-002
public actor DexcomCoexistenceDetector {
    private let central: any BLECentralProtocol
    
    public init(central: any BLECentralProtocol) {
        self.central = central
    }
    
    /// Scan for nearby Dexcom devices (short scan for detection only).
    public func detectNearbyDexcom(timeoutSeconds: Double = 3.0) async -> DexcomCoexistenceResult {
        var g6Found = false
        var g7Found = false
        var g6Id: String?
        var g7Serial: String?
        
        // Scan for both G6 and G7 advertisements
        let scanStream = central.scan(for: [.dexcomAdvertisement, .dexcomG7Advertisement])
        
        let task = Task {
            for try await result in scanStream {
                if let name = result.advertisement.localName {
                    // G6 transmitters: DexcomXX (6 char transmitter ID)
                    if name.hasPrefix("Dexcom") && name.count <= 12 {
                        g6Found = true
                        g6Id = String(name.dropFirst(6))
                    }
                    // G7 sensors: longer serial, advertises FE59
                    if result.advertisement.serviceUUIDs.contains(.dexcomG7Advertisement) {
                        g7Found = true
                        g7Serial = name
                    }
                }
                
                // Also check service UUIDs
                let services = result.advertisement.serviceUUIDs
                if services.contains(.dexcomAdvertisement) && !g6Found {
                    g6Found = true
                }
                if services.contains(.dexcomG7Advertisement) && !g7Found {
                    g7Found = true
                }
            }
        }
        
        // Run for timeout then cancel
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        task.cancel()
        await central.stopScan()
        
        return DexcomCoexistenceResult(
            g6Detected: g6Found,
            g7Detected: g7Found,
            g6TransmitterId: g6Id,
            g7SensorSerial: g7Serial
        )
    }
}

// MARK: - Recommendation Result

/// A recommended connection mode with reasoning
public struct ConnectionModeRecommendation: Sendable, Equatable {
    /// The recommended connection mode
    public let mode: CGMConnectionMode
    
    /// Human-readable reason for recommendation
    public let reason: String
    
    /// Whether this is a strong recommendation (vs informational)
    public let isStrong: Bool
    
    /// Warning message if applicable
    public let warning: String?
    
    /// Alternative modes the user could consider
    public let alternatives: [CGMConnectionMode]
    
    public init(
        mode: CGMConnectionMode,
        reason: String,
        isStrong: Bool = false,
        warning: String? = nil,
        alternatives: [CGMConnectionMode] = []
    ) {
        self.mode = mode
        self.reason = reason
        self.isStrong = isStrong
        self.warning = warning
        self.alternatives = alternatives
    }
}

/// Full recommendation result with context
public struct RecommendationResult: Sendable {
    /// Primary recommendation
    public let primary: ConnectionModeRecommendation
    
    /// Detected CGM apps that influenced the recommendation
    public let detectedCGMApps: [KnownCGMApp]
    
    /// Detected AID apps (for safety warnings)
    public let detectedAIDApps: [KnownAIDApp]
    
    /// Device type this recommendation is for
    public let deviceType: CGMDeviceType
    
    /// Whether vendor app coexistence is detected
    public var vendorDetected: Bool { !detectedCGMApps.isEmpty }
    
    /// Whether AID controller conflict exists
    public var hasAIDConflict: Bool { !detectedAIDApps.isEmpty }
    
    public init(
        primary: ConnectionModeRecommendation,
        detectedCGMApps: [KnownCGMApp] = [],
        detectedAIDApps: [KnownAIDApp] = [],
        deviceType: CGMDeviceType
    ) {
        self.primary = primary
        self.detectedCGMApps = detectedCGMApps
        self.detectedAIDApps = detectedAIDApps
        self.deviceType = deviceType
    }
}

// MARK: - Recommender

/// Recommends optimal CGM connection mode based on environment
public actor ConnectionModeRecommender {
    private let detector: ColocatedAppDetector
    
    public init(detector: ColocatedAppDetector = ColocatedAppDetector()) {
        self.detector = detector
    }
    
    /// Generate recommendation for a device type
    public func recommend(for deviceType: CGMDeviceType) async -> RecommendationResult {
        let detection = await detector.detectInstalledApps()
        return generateRecommendation(
            deviceType: deviceType,
            cgmApps: detection.detectedCGMApps,
            aidApps: detection.detectedAIDApps
        )
    }
    
    /// Generate recommendation with pre-fetched detection result
    public func recommend(
        for deviceType: CGMDeviceType,
        with detection: AppDetectionResult
    ) -> RecommendationResult {
        return generateRecommendation(
            deviceType: deviceType,
            cgmApps: detection.detectedCGMApps,
            aidApps: detection.detectedAIDApps
        )
    }
    
    private func generateRecommendation(
        deviceType: CGMDeviceType,
        cgmApps: [KnownCGMApp],
        aidApps: [KnownAIDApp]
    ) -> RecommendationResult {
        // Check for vendor app matching device type
        let matchingVendorApp = cgmApps.first { app in
            matchesDeviceType(app: app, deviceType: deviceType)
        }
        
        // Determine recommendation based on device and environment
        let recommendation: ConnectionModeRecommendation
        
        switch deviceType {
        case .dexcomG6, .dexcomG6Plus, .dexcomG7:
            recommendation = recommendForDexcom(
                deviceType: deviceType,
                vendorApp: matchingVendorApp,
                allCGMApps: cgmApps
            )
            
        case .libre2:
            recommendation = recommendForLibre2(
                vendorApp: matchingVendorApp,
                allCGMApps: cgmApps
            )
            
        case .libre3:
            recommendation = recommendForLibre3(
                vendorApp: matchingVendorApp,
                allCGMApps: cgmApps
            )
            
        case .miaomiao, .bubble:
            recommendation = recommendForTransmitter(
                deviceType: deviceType,
                allCGMApps: cgmApps
            )
            
        case .unknown:
            recommendation = ConnectionModeRecommendation(
                mode: .healthKitObserver,
                reason: "Unknown device type. HealthKit is the safest default.",
                isStrong: false,
                alternatives: [.cloudFollower, .nightscoutFollower]
            )
        }
        
        return RecommendationResult(
            primary: recommendation,
            detectedCGMApps: cgmApps,
            detectedAIDApps: aidApps,
            deviceType: deviceType
        )
    }
    
    // MARK: - Device-Specific Recommendations
    
    private func recommendForDexcom(
        deviceType: CGMDeviceType,
        vendorApp: KnownCGMApp?,
        allCGMApps: [KnownCGMApp]
    ) -> ConnectionModeRecommendation {
        if let vendor = vendorApp {
            // Vendor app detected - recommend passive BLE
            // CGM-MODE-WIRE-001: Include coexistence as alternative for G7
            let alternatives: [CGMConnectionMode]
            if deviceType == .dexcomG7 {
                // G7 coexistence lets vendor app handle auth while T1Pal receives data
                alternatives = [.coexistence, .healthKitObserver, .cloudFollower]
            } else {
                // G6: coexistence also works but passive BLE is simpler
                alternatives = [.coexistence, .healthKitObserver, .cloudFollower]
            }
            return ConnectionModeRecommendation(
                mode: .passiveBLE,
                reason: "\(vendor.name) detected. Passive BLE lets both apps receive glucose data without conflict.",
                isStrong: true,
                warning: "Direct mode would compete with \(vendor.name) for the transmitter connection.",
                alternatives: alternatives
            )
        } else {
            // No vendor app - direct is fine, but coexistence available if vendor app added later
            return ConnectionModeRecommendation(
                mode: .direct,
                reason: "No vendor app detected. Direct connection provides lowest latency.",
                isStrong: false,
                alternatives: [.coexistence, .passiveBLE, .healthKitObserver]
            )
        }
    }
    
    private func recommendForLibre2(
        vendorApp: KnownCGMApp?,
        allCGMApps: [KnownCGMApp]
    ) -> ConnectionModeRecommendation {
        if vendorApp != nil {
            // LibreLink uses NFC primarily, but Libre 2 has BLE
            return ConnectionModeRecommendation(
                mode: .healthKitObserver,
                reason: "LibreLink detected. HealthKit provides reliable glucose with minimal conflict.",
                isStrong: true,
                warning: "Libre 2 BLE connection may conflict with LibreLink. HealthKit is safer.",
                alternatives: [.passiveBLE, .cloudFollower]
            )
        } else {
            return ConnectionModeRecommendation(
                mode: .direct,
                reason: "No vendor app. Direct BLE to Libre 2 provides real-time data.",
                isStrong: false,
                alternatives: [.healthKitObserver]
            )
        }
    }
    
    private func recommendForLibre3(
        vendorApp: KnownCGMApp?,
        allCGMApps: [KnownCGMApp]
    ) -> ConnectionModeRecommendation {
        // Libre 3 uses encrypted BLE - passive observation not practical
        return ConnectionModeRecommendation(
            mode: .healthKitObserver,
            reason: "Libre 3 uses encrypted BLE. HealthKit is the recommended data source.",
            isStrong: true,
            warning: vendorApp != nil ? "Libre 3 app controls sensor encryption. Use HealthKit for glucose." : nil,
            alternatives: [.cloudFollower, .nightscoutFollower]
        )
    }
    
    private func recommendForTransmitter(
        deviceType: CGMDeviceType,
        allCGMApps: [KnownCGMApp]
    ) -> ConnectionModeRecommendation {
        // MiaoMiao, Bubble - third-party transmitters
        let hasOtherCGMApp = allCGMApps.contains { $0.conflictRisk == .high }
        
        if hasOtherCGMApp {
            return ConnectionModeRecommendation(
                mode: .passiveBLE,
                reason: "Other CGM app detected. Passive mode avoids transmitter conflicts.",
                isStrong: true,
                alternatives: [.direct, .healthKitObserver]
            )
        } else {
            return ConnectionModeRecommendation(
                mode: .direct,
                reason: "No conflicting apps. Direct connection to \(deviceType.displayName).",
                isStrong: false,
                alternatives: [.healthKitObserver]
            )
        }
    }
    
    // MARK: - Helpers
    
    private func matchesDeviceType(app: KnownCGMApp, deviceType: CGMDeviceType) -> Bool {
        switch deviceType {
        case .dexcomG6, .dexcomG6Plus:
            return app.id == "dexcom-g6" || app.id == "dexcom-one"
        case .dexcomG7:
            return app.id == "dexcom-g7"
        case .libre2:
            return app.id == "libre-link"
        case .libre3:
            return app.id == "libre3"
        case .miaomiao, .bubble:
            // Third-party transmitters - check for xDrip or Spike
            return app.id == "xdrip" || app.id == "spike"
        case .unknown:
            return false
        }
    }
}

// MARK: - CGMDeviceType Extension

extension CGMDeviceType {
    public var displayName: String {
        switch self {
        case .dexcomG6: return "Dexcom G6"
        case .dexcomG6Plus: return "Dexcom G6+"
        case .dexcomG7: return "Dexcom G7"
        case .libre2: return "Libre 2"
        case .libre3: return "Libre 3"
        case .miaomiao: return "MiaoMiao"
        case .bubble: return "Bubble"
        case .unknown: return "Unknown"
        }
    }
}
