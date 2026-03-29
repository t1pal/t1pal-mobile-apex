// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DataContext.swift - Unified data context model
// Part of T1PalCore
//
// Single source of truth for data configuration across the app.
// See PRD-021 REQ-DCA-001 for requirements.
// Trace: OBS-005 for faultConfig integration

import Foundation

// MARK: - DataSourceType

/// Represents the type of data source for glucose readings
public enum DataSourceType: String, Codable, Sendable, CaseIterable {
    /// Simulated demo patterns (CGMPattern)
    case demo = "demo"
    
    /// Recorded fixture replay
    case fixture = "fixture"
    
    /// Live Nightscout site
    case liveNS = "liveNS"
    
    /// HealthKit glucose readings
    case healthKit = "healthKit"
    
    /// Direct BLE CGM connection
    case ble = "ble"
    
    /// Passive BLE observation (vendor app controls sensor)
    case blePassive = "blePassive"
    
    /// Read from shared app group (Loop/Trio/xDrip4iOS)
    case appGroup = "appGroup"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .demo: return "Demo Mode"
        case .fixture: return "Fixture Replay"
        case .liveNS: return "Live Nightscout"
        case .healthKit: return "HealthKit"
        case .ble: return "BLE CGM"
        case .blePassive: return "BLE Passive"
        case .appGroup: return "App Group"
        }
    }
    
    /// System image name for the source type
    public var systemImage: String {
        switch self {
        case .demo: return "waveform.path"
        case .fixture: return "doc.text"
        case .liveNS: return "globe"
        case .healthKit: return "heart.fill"
        case .ble: return "antenna.radiowaves.left.and.right"
        case .blePassive: return "eye"
        case .appGroup: return "square.grid.2x2"
        }
    }
    
    /// Emoji indicator for compact display
    public var emoji: String {
        switch self {
        case .demo: return "🔬"
        case .fixture: return "📁"
        case .liveNS: return "🌐"
        case .healthKit: return "❤️"
        case .ble: return "📡"
        case .blePassive: return "👁️"
        case .appGroup: return "🔗"
        }
    }
}

// MARK: - DataContext

/// Unified data context representing the current data configuration
///
/// This is the single source of truth for data configuration.
/// All data-consuming views should read from this context.
///
/// Example usage:
/// ```swift
/// let context = DataContext.demo(pattern: .mealSpike)
/// let context = DataContext.liveNS(url: URL(string: "https://demo.ns.10be.de")!)
/// ```
public struct DataContext: Codable, Sendable, Equatable, Hashable {
    // MARK: - Properties
    
    /// The type of data source
    public let sourceType: DataSourceType
    
    /// Nightscout configuration (if sourceType == .liveNS)
    public let nightscoutURL: URL?
    
    /// Nightscout API token (optional, for authenticated access)
    public let nightscoutToken: String?
    
    /// Simulation pattern name (if sourceType == .demo)
    /// Uses String to avoid T1PalDemoKit dependency
    public let simulationPattern: String?
    
    /// Fixture name (if sourceType == .fixture)
    public let fixtureName: String?
    
    /// Whether this is a preview/sandbox context (not production)
    public let isPreview: Bool
    
    /// Optional display label for the context
    public let label: String?
    
    /// Timestamp when this context was created/configured
    public let configuredAt: Date
    
    #if DEBUG
    /// Fault injection configuration (DEBUG builds only) - OBS-005
    /// See FaultTypes.swift for available fault types
    public var faultConfig: FaultConfiguration?
    #endif
    
    /// BLE CGM device configuration - BLE-CTX-003
    /// See BLEDeviceConfig.swift for available device types
    public let bleConfig: BLEDeviceConfig?
    
    /// Pump device configuration - BLE-CTX-004
    /// See BLEDeviceConfig.swift for available pump types
    public let pumpConfig: PumpDeviceConfig?
    
    // MARK: - Initializers
    
    /// Full initializer
    public init(
        sourceType: DataSourceType,
        nightscoutURL: URL? = nil,
        nightscoutToken: String? = nil,
        simulationPattern: String? = nil,
        fixtureName: String? = nil,
        isPreview: Bool = false,
        label: String? = nil,
        configuredAt: Date = Date(),
        faultConfig: FaultConfiguration? = nil,
        bleConfig: BLEDeviceConfig? = nil,
        pumpConfig: PumpDeviceConfig? = nil
    ) {
        self.sourceType = sourceType
        self.nightscoutURL = nightscoutURL
        self.nightscoutToken = nightscoutToken
        self.simulationPattern = simulationPattern
        self.fixtureName = fixtureName
        self.isPreview = isPreview
        self.label = label
        self.configuredAt = configuredAt
        self.bleConfig = bleConfig
        self.pumpConfig = pumpConfig
        #if DEBUG
        self.faultConfig = faultConfig
        #endif
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Create a demo context with a specific pattern
    public static func demo(pattern: String, isPreview: Bool = false) -> DataContext {
        DataContext(
            sourceType: .demo,
            simulationPattern: pattern,
            isPreview: isPreview,
            label: "Demo: \(pattern)"
        )
    }
    
    /// Create a fixture replay context
    public static func fixture(name: String, isPreview: Bool = true) -> DataContext {
        DataContext(
            sourceType: .fixture,
            fixtureName: name,
            isPreview: isPreview,
            label: "Fixture: \(name)"
        )
    }
    
    /// Create a live Nightscout context
    public static func liveNS(url: URL, token: String? = nil, label: String? = nil) -> DataContext {
        DataContext(
            sourceType: .liveNS,
            nightscoutURL: url,
            nightscoutToken: token,
            isPreview: false,
            label: label ?? url.host ?? "Nightscout"
        )
    }
    
    /// Create a HealthKit context
    public static func healthKit() -> DataContext {
        DataContext(
            sourceType: .healthKit,
            isPreview: false,
            label: "HealthKit"
        )
    }
    
    /// Create a BLE CGM context
    public static func ble(deviceName: String? = nil) -> DataContext {
        DataContext(
            sourceType: .ble,
            isPreview: false,
            label: deviceName ?? "BLE CGM"
        )
    }
    
    /// Create a BLE CGM context with full device configuration - BLE-CTX-005
    public static func ble(config: BLEDeviceConfig, pumpConfig: PumpDeviceConfig? = nil) -> DataContext {
        DataContext(
            sourceType: .ble,
            isPreview: false,
            label: config.displayName,
            bleConfig: config,
            pumpConfig: pumpConfig
        )
    }
    
    // MARK: - Computed Properties
    
    /// Human-readable description of the context
    public var displayDescription: String {
        if let label = label, !label.isEmpty {
            return label
        }
        
        switch sourceType {
        case .demo:
            return simulationPattern.map { "Demo: \($0)" } ?? "Demo Mode"
        case .fixture:
            return fixtureName.map { "Fixture: \($0)" } ?? "Fixture Replay"
        case .liveNS:
            return nightscoutURL?.host ?? "Nightscout"
        case .healthKit:
            return "HealthKit"
        case .ble:
            return "BLE CGM"
        case .blePassive:
            return "BLE Passive"
        case .appGroup:
            return "Loop/Trio"
        }
    }
    
    /// Compact indicator string (emoji + short label)
    public var indicator: String {
        "\(sourceType.emoji) \(displayDescription)"
    }
    
    /// Whether this context represents live/production data
    public var isLiveData: Bool {
        !isPreview && (sourceType == .liveNS || sourceType == .healthKit || sourceType == .ble || sourceType == .blePassive || sourceType == .appGroup)
    }
    
    /// Whether this context is fully configured and ready to use
    public var isConfigured: Bool {
        switch sourceType {
        case .demo:
            return true // Demo always works
        case .fixture:
            return fixtureName != nil
        case .liveNS:
            return nightscoutURL != nil
        case .healthKit:
            return true // Will check permissions at runtime
        case .ble, .blePassive, .appGroup:
            return true // Will scan for devices at runtime
        }
    }
}

// MARK: - Default Context

extension DataContext {
    /// Default context for app launch (demo mode)
    public static let `default` = DataContext.demo(pattern: "flat")
    
    /// Preview context for SwiftUI previews
    public static let preview = DataContext(
        sourceType: .demo,
        simulationPattern: "flat",
        isPreview: true,
        label: "Preview"
    )
}

// MARK: - Fault Injection (OBS-005)

#if DEBUG
extension DataContext {
    /// Create a copy with fault configuration applied
    public func withFaults(_ faults: FaultConfiguration) -> DataContext {
        DataContext(
            sourceType: sourceType,
            nightscoutURL: nightscoutURL,
            nightscoutToken: nightscoutToken,
            simulationPattern: simulationPattern,
            fixtureName: fixtureName,
            isPreview: isPreview,
            label: label,
            configuredAt: configuredAt,
            faultConfig: faults,
            bleConfig: bleConfig,
            pumpConfig: pumpConfig
        )
    }
    
    /// Create a copy with a fault preset applied
    public func withPreset(_ preset: FaultPreset) -> DataContext {
        withFaults(preset.configuration)
    }
}
#endif

// MARK: - Fault Status (Available in all builds for UI display)

extension DataContext {
    /// Check if this context has active faults
    public var hasFaults: Bool {
        #if DEBUG
        return faultConfig?.isEnabled == true && faultConfig?.hasFaults == true
        #else
        return false
        #endif
    }
    
    /// Get active data faults (empty if none or in Release builds)
    public var activeDataFaults: [DataFaultType] {
        #if DEBUG
        guard hasFaults else { return [] }
        return faultConfig?.dataFaults ?? []
        #else
        return []
        #endif
    }
    
    /// Get active network faults (empty if none or in Release builds)
    public var activeNetworkFaults: [NetworkFaultType] {
        #if DEBUG
        guard hasFaults else { return [] }
        return faultConfig?.networkFaults ?? []
        #else
        return []
        #endif
    }
}

// MARK: - BLE Device Configuration (BLE-CTX-003, BLE-CTX-004)

extension DataContext {
    /// Create a copy with BLE CGM configuration applied
    public func withBLE(_ config: BLEDeviceConfig) -> DataContext {
        DataContext(
            sourceType: sourceType,
            nightscoutURL: nightscoutURL,
            nightscoutToken: nightscoutToken,
            simulationPattern: simulationPattern,
            fixtureName: fixtureName,
            isPreview: isPreview,
            label: label,
            configuredAt: configuredAt,
            bleConfig: config,
            pumpConfig: pumpConfig
        )
    }
    
    /// Create a copy with pump configuration applied
    public func withPump(_ config: PumpDeviceConfig) -> DataContext {
        DataContext(
            sourceType: sourceType,
            nightscoutURL: nightscoutURL,
            nightscoutToken: nightscoutToken,
            simulationPattern: simulationPattern,
            fixtureName: fixtureName,
            isPreview: isPreview,
            label: label,
            configuredAt: configuredAt,
            bleConfig: bleConfig,
            pumpConfig: config
        )
    }
    
    /// Check if BLE CGM is configured
    public var hasBLEConfig: Bool {
        bleConfig != nil
    }
    
    /// Check if pump is configured
    public var hasPumpConfig: Bool {
        pumpConfig != nil
    }
    
    /// Check if full AID configuration (CGM + pump) is present
    public var hasFullAIDConfig: Bool {
        hasBLEConfig && hasPumpConfig
    }
}

// MARK: - Codable Key for Persistence

extension DataContext {
    /// UserDefaults key for persisting the active context
    public static let persistenceKey = "com.t1pal.dataContext"
}
