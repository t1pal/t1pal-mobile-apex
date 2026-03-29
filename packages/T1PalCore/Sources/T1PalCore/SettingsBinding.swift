// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SettingsBinding.swift - SwiftUI @AppStorage bindings for SettingsStore
// Part of T1PalCore
// Trace: PROD-PERSIST-002

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Settings Keys

/// Centralized settings keys for UserDefaults persistence
public enum SettingsKey: String, CaseIterable, Sendable {
    // Data Source
    case activeDataSourceID = "settings.dataSource.activeID"
    case nightscoutURL = "settings.dataSource.nightscoutURL"
    
    // Glucose Display
    case glucoseUnit = "settings.display.glucoseUnit"
    case highGlucoseThreshold = "settings.display.highThreshold"
    case lowGlucoseThreshold = "settings.display.lowThreshold"
    case urgentHighThreshold = "settings.display.urgentHighThreshold"
    case urgentLowThreshold = "settings.display.urgentLowThreshold"
    
    // Chart
    case chartTimeRange = "settings.chart.timeRangeHours"
    case showTargetRange = "settings.chart.showTargetRange"
    case showPrediction = "settings.chart.showPrediction"
    
    // Notifications
    case notificationsEnabled = "settings.notifications.enabled"
    case highAlertEnabled = "settings.notifications.highAlert"
    case lowAlertEnabled = "settings.notifications.lowAlert"
    case urgentAlertEnabled = "settings.notifications.urgentAlert"
    case staleDataAlertEnabled = "settings.notifications.staleAlert"
    case staleDataMinutes = "settings.notifications.staleMinutes"
    
    // Appearance
    case colorScheme = "settings.appearance.colorScheme"
    case useLargeReadings = "settings.appearance.largeReadings"
    
    // Sync timestamps
    case lastDataFetch = "settings.sync.lastFetch"
    case lastWidgetUpdate = "settings.sync.lastWidgetUpdate"
    
    // Algorithm settings (PROD-PERSIST-002)
    case algorithmName = "settings.algorithm.name"
    case algorithmDIA = "settings.algorithm.dia"
    case algorithmISF = "settings.algorithm.isf"
    case algorithmICR = "settings.algorithm.icr"
    case algorithmBasalRate = "settings.algorithm.basalRate"
    case algorithmTargetLow = "settings.algorithm.targetLow"
    case algorithmTargetHigh = "settings.algorithm.targetHigh"
    case algorithmSMBEnabled = "settings.algorithm.smbEnabled"
    case algorithmMaxSMB = "settings.algorithm.maxSMB"
    case algorithmUAMEnabled = "settings.algorithm.uamEnabled"
    case algorithmMaxBasalRate = "settings.algorithm.maxBasalRate"
    case algorithmMaxBolus = "settings.algorithm.maxBolus"
    case algorithmMaxIOB = "settings.algorithm.maxIOB"
    case algorithmSuspendThreshold = "settings.algorithm.suspendThreshold"
    
    // CGM settings (PROD-PERSIST-002)
    case cgmType = "settings.cgm.type"
    case cgmTransmitterId = "settings.cgm.transmitterId"
    case cgmSensorCode = "settings.cgm.sensorCode"
    case cgmConnectionMode = "settings.cgm.connectionMode"
    
    // Pump settings (PROD-PERSIST-002)
    case pumpEnabled = "settings.pump.enabled"
    case pumpType = "settings.pump.type"
    case pumpSerial = "settings.pump.serial"
    case pumpBridgeType = "settings.pump.bridgeType"
    case pumpBridgeId = "settings.pump.bridgeId"
    
    // AID settings (PROD-PERSIST-002)
    case aidEnabled = "settings.aid.enabled"
    case aidClosedLoopAllowed = "settings.aid.closedLoopAllowed"
    case aidLastLoopTime = "settings.aid.lastLoopTime"
    case aidLoopInterval = "settings.aid.loopInterval"
    
    // Onboarding (PROD-PERSIST-002)
    case onboardingComplete = "settings.onboarding.complete"
    case onboardingStep = "settings.onboarding.step"
    case termsAccepted = "settings.onboarding.termsAccepted"
    case trainingComplete = "settings.onboarding.trainingComplete"
}

// MARK: - Settings Defaults

/// Default values for all settings
public struct SettingsDefaults: Sendable {
    // Glucose thresholds (mg/dL)
    public static let highGlucoseThreshold: Double = 180.0
    public static let lowGlucoseThreshold: Double = 70.0
    public static let urgentHighThreshold: Double = 250.0
    public static let urgentLowThreshold: Double = 55.0
    
    // Chart
    public static let chartTimeRangeHours: Int = 3
    public static let showTargetRange: Bool = true
    public static let showPrediction: Bool = true
    
    // Notifications
    public static let notificationsEnabled: Bool = true
    public static let staleDataMinutes: Int = 15
    
    // Appearance
    public static let useLargeReadings: Bool = true
    
    // Algorithm
    public static let algorithmDIA: Double = 5.0
    public static let algorithmISF: Double = 50.0
    public static let algorithmICR: Double = 10.0
    public static let algorithmBasalRate: Double = 1.0
    public static let algorithmTargetLow: Double = 100.0
    public static let algorithmTargetHigh: Double = 120.0
    public static let algorithmMaxSMB: Double = 1.0
    public static let algorithmMaxBasalRate: Double = 5.0
    public static let algorithmMaxBolus: Double = 10.0
    public static let algorithmMaxIOB: Double = 10.0
    public static let algorithmSuspendThreshold: Double = 70.0
    
    // AID
    public static let aidLoopInterval: Int = 300 // 5 minutes
    
    private init() {}
}

// MARK: - Settings Observer

/// Protocol for observing settings changes
public protocol SettingsObserver: AnyObject, Sendable {
    func settingsDidChange(key: SettingsKey, value: Any?)
}

// MARK: - Settings Persistence Manager

/// Manages settings persistence with change notifications
public actor SettingsPersistenceManager {
    /// Shared instance - nonisolated(unsafe) for Swift 6 compatibility
    public nonisolated(unsafe) static let shared = SettingsPersistenceManager()
    
    // UserDefaults is thread-safe but not Sendable. Use nonisolated(unsafe) to satisfy Swift 6.
    nonisolated(unsafe) private let defaults: UserDefaults
    private var observers: [ObjectIdentifier: WeakObserver] = [:]
    
    private struct WeakObserver {
        weak var observer: (any SettingsObserver)?
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Observer Management
    
    /// Add an observer for settings changes
    public func addObserver(_ observer: any SettingsObserver) {
        let id = ObjectIdentifier(observer)
        observers[id] = WeakObserver(observer: observer)
    }
    
    /// Remove an observer
    public func removeObserver(_ observer: any SettingsObserver) {
        let id = ObjectIdentifier(observer)
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers(key: SettingsKey, value: Any?) {
        // Clean up dead observers
        observers = observers.filter { $0.value.observer != nil }
        
        for (_, weakObserver) in observers {
            if let observer = weakObserver.observer {
                Task { @Sendable in
                    observer.settingsDidChange(key: key, value: value)
                }
            }
        }
    }
    
    // MARK: - String Settings
    
    public func getString(_ key: SettingsKey) -> String? {
        defaults.string(forKey: key.rawValue)
    }
    
    public func setString(_ value: String?, forKey key: SettingsKey) {
        if let value = value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Double Settings
    
    public func getDouble(_ key: SettingsKey, default defaultValue: Double) -> Double {
        if defaults.object(forKey: key.rawValue) != nil {
            return defaults.double(forKey: key.rawValue)
        }
        return defaultValue
    }
    
    public func setDouble(_ value: Double, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Int Settings
    
    public func getInt(_ key: SettingsKey, default defaultValue: Int) -> Int {
        if defaults.object(forKey: key.rawValue) != nil {
            return defaults.integer(forKey: key.rawValue)
        }
        return defaultValue
    }
    
    public func setInt(_ value: Int, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Bool Settings
    
    public func getBool(_ key: SettingsKey, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key.rawValue) != nil {
            return defaults.bool(forKey: key.rawValue)
        }
        return defaultValue
    }
    
    public func setBool(_ value: Bool, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Date Settings
    
    public func getDate(_ key: SettingsKey) -> Date? {
        defaults.object(forKey: key.rawValue) as? Date
    }
    
    public func setDate(_ value: Date?, forKey key: SettingsKey) {
        if let value = value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Codable Settings
    
    public func getCodable<T: Codable>(_ type: T.Type, forKey key: SettingsKey) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    public func setCodable<T: Codable>(_ value: T?, forKey key: SettingsKey) {
        if let value = value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        notifyObservers(key: key, value: value)
    }
    
    // MARK: - Bulk Operations
    
    /// Reset all settings to defaults
    public func resetAllSettings() {
        for key in SettingsKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
    
    /// Export all settings as dictionary
    public func exportSettings() -> [String: Any] {
        var result: [String: Any] = [:]
        for key in SettingsKey.allCases {
            if let value = defaults.object(forKey: key.rawValue) {
                result[key.rawValue] = value
            }
        }
        return result
    }
    
    /// Import settings from dictionary
    public func importSettings(_ settings: [String: Any]) {
        for (keyString, value) in settings {
            defaults.set(value, forKey: keyString)
        }
    }
    
    /// Synchronize settings
    public func synchronize() {
        defaults.synchronize()
    }
}

// MARK: - Algorithm Settings Persistence

/// Persisted algorithm settings configuration
public struct PersistedAlgorithmSettings: Codable, Sendable, Equatable {
    public var algorithmName: String
    public var dia: Double
    public var isf: Double
    public var icr: Double
    public var basalRate: Double
    public var targetLow: Double
    public var targetHigh: Double
    public var smbEnabled: Bool
    public var maxSMB: Double
    public var uamEnabled: Bool
    public var maxBasalRate: Double
    public var maxBolus: Double
    public var maxIOB: Double
    public var suspendThreshold: Double
    
    public init(
        algorithmName: String = "oref0",
        dia: Double = SettingsDefaults.algorithmDIA,
        isf: Double = SettingsDefaults.algorithmISF,
        icr: Double = SettingsDefaults.algorithmICR,
        basalRate: Double = SettingsDefaults.algorithmBasalRate,
        targetLow: Double = SettingsDefaults.algorithmTargetLow,
        targetHigh: Double = SettingsDefaults.algorithmTargetHigh,
        smbEnabled: Bool = false,
        maxSMB: Double = SettingsDefaults.algorithmMaxSMB,
        uamEnabled: Bool = false,
        maxBasalRate: Double = SettingsDefaults.algorithmMaxBasalRate,
        maxBolus: Double = SettingsDefaults.algorithmMaxBolus,
        maxIOB: Double = SettingsDefaults.algorithmMaxIOB,
        suspendThreshold: Double = SettingsDefaults.algorithmSuspendThreshold
    ) {
        self.algorithmName = algorithmName
        self.dia = dia
        self.isf = isf
        self.icr = icr
        self.basalRate = basalRate
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.smbEnabled = smbEnabled
        self.maxSMB = maxSMB
        self.uamEnabled = uamEnabled
        self.maxBasalRate = maxBasalRate
        self.maxBolus = maxBolus
        self.maxIOB = maxIOB
        self.suspendThreshold = suspendThreshold
    }
    
    public static let `default` = PersistedAlgorithmSettings()
}

// MARK: - CGM Settings Persistence

/// CGM connection mode
public enum CGMConnectionMode: String, Codable, Sendable, CaseIterable {
    case ble = "ble"
    case cloud = "cloud"
    case demo = "demo"
}

/// Persisted CGM configuration
public struct PersistedCGMSettings: Codable, Sendable, Equatable {
    public var cgmType: String
    public var transmitterId: String?
    public var sensorCode: String?
    public var connectionMode: CGMConnectionMode
    
    public init(
        cgmType: String = "dexcomG6",
        transmitterId: String? = nil,
        sensorCode: String? = nil,
        connectionMode: CGMConnectionMode = .ble
    ) {
        self.cgmType = cgmType
        self.transmitterId = transmitterId
        self.sensorCode = sensorCode
        self.connectionMode = connectionMode
    }
    
    public static let `default` = PersistedCGMSettings()
}

// MARK: - Pump Settings Persistence

/// Persisted pump configuration
public struct PersistedPumpSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var pumpType: String
    public var serial: String?
    public var bridgeType: String?
    public var bridgeId: String?
    
    public init(
        enabled: Bool = false,
        pumpType: String = "medtronic",
        serial: String? = nil,
        bridgeType: String? = nil,
        bridgeId: String? = nil
    ) {
        self.enabled = enabled
        self.pumpType = pumpType
        self.serial = serial
        self.bridgeType = bridgeType
        self.bridgeId = bridgeId
    }
    
    public static let `default` = PersistedPumpSettings()
}

// MARK: - AID Settings Persistence

/// Persisted AID (Automated Insulin Delivery) configuration
public struct PersistedAIDSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var closedLoopAllowed: Bool
    public var lastLoopTime: Date?
    public var loopInterval: Int
    
    public init(
        enabled: Bool = false,
        closedLoopAllowed: Bool = false,
        lastLoopTime: Date? = nil,
        loopInterval: Int = SettingsDefaults.aidLoopInterval
    ) {
        self.enabled = enabled
        self.closedLoopAllowed = closedLoopAllowed
        self.lastLoopTime = lastLoopTime
        self.loopInterval = loopInterval
    }
    
    public static let `default` = PersistedAIDSettings()
}

// MARK: - Onboarding Settings Persistence

/// Persisted onboarding state
public struct PersistedOnboardingSettings: Codable, Sendable, Equatable {
    public var complete: Bool
    public var currentStep: Int
    public var termsAccepted: Bool
    public var trainingComplete: Bool
    
    public init(
        complete: Bool = false,
        currentStep: Int = 0,
        termsAccepted: Bool = false,
        trainingComplete: Bool = false
    ) {
        self.complete = complete
        self.currentStep = currentStep
        self.termsAccepted = termsAccepted
        self.trainingComplete = trainingComplete
    }
    
    public static let `default` = PersistedOnboardingSettings()
}

// MARK: - Settings Store Extension

extension SettingsStore {
    
    // MARK: - Algorithm Settings
    
    /// Algorithm name (oref0, oref1, etc.)
    public var algorithmName: String {
        get { defaults.string(forKey: SettingsKey.algorithmName.rawValue) ?? "oref0" }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmName.rawValue) }
    }
    
    /// Duration of Insulin Action (hours)
    public var algorithmDIA: Double {
        get { defaults.object(forKey: SettingsKey.algorithmDIA.rawValue) as? Double ?? SettingsDefaults.algorithmDIA }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmDIA.rawValue) }
    }
    
    /// Insulin Sensitivity Factor (mg/dL per unit)
    public var algorithmISF: Double {
        get { defaults.object(forKey: SettingsKey.algorithmISF.rawValue) as? Double ?? SettingsDefaults.algorithmISF }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmISF.rawValue) }
    }
    
    /// Insulin-to-Carb Ratio (g per unit)
    public var algorithmICR: Double {
        get { defaults.object(forKey: SettingsKey.algorithmICR.rawValue) as? Double ?? SettingsDefaults.algorithmICR }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmICR.rawValue) }
    }
    
    /// Basal rate (U/hr)
    public var algorithmBasalRate: Double {
        get { defaults.object(forKey: SettingsKey.algorithmBasalRate.rawValue) as? Double ?? SettingsDefaults.algorithmBasalRate }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmBasalRate.rawValue) }
    }
    
    /// Target glucose low (mg/dL)
    public var algorithmTargetLow: Double {
        get { defaults.object(forKey: SettingsKey.algorithmTargetLow.rawValue) as? Double ?? SettingsDefaults.algorithmTargetLow }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmTargetLow.rawValue) }
    }
    
    /// Target glucose high (mg/dL)
    public var algorithmTargetHigh: Double {
        get { defaults.object(forKey: SettingsKey.algorithmTargetHigh.rawValue) as? Double ?? SettingsDefaults.algorithmTargetHigh }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmTargetHigh.rawValue) }
    }
    
    /// SMB enabled
    public var algorithmSMBEnabled: Bool {
        get { defaults.object(forKey: SettingsKey.algorithmSMBEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmSMBEnabled.rawValue) }
    }
    
    /// Max SMB size (units)
    public var algorithmMaxSMB: Double {
        get { defaults.object(forKey: SettingsKey.algorithmMaxSMB.rawValue) as? Double ?? SettingsDefaults.algorithmMaxSMB }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmMaxSMB.rawValue) }
    }
    
    /// UAM enabled
    public var algorithmUAMEnabled: Bool {
        get { defaults.object(forKey: SettingsKey.algorithmUAMEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmUAMEnabled.rawValue) }
    }
    
    /// Max basal rate (U/hr)
    public var algorithmMaxBasalRate: Double {
        get { defaults.object(forKey: SettingsKey.algorithmMaxBasalRate.rawValue) as? Double ?? SettingsDefaults.algorithmMaxBasalRate }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmMaxBasalRate.rawValue) }
    }
    
    /// Max bolus (units)
    public var algorithmMaxBolus: Double {
        get { defaults.object(forKey: SettingsKey.algorithmMaxBolus.rawValue) as? Double ?? SettingsDefaults.algorithmMaxBolus }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmMaxBolus.rawValue) }
    }
    
    /// Max IOB (units)
    public var algorithmMaxIOB: Double {
        get { defaults.object(forKey: SettingsKey.algorithmMaxIOB.rawValue) as? Double ?? SettingsDefaults.algorithmMaxIOB }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmMaxIOB.rawValue) }
    }
    
    /// Suspend threshold (mg/dL)
    public var algorithmSuspendThreshold: Double {
        get { defaults.object(forKey: SettingsKey.algorithmSuspendThreshold.rawValue) as? Double ?? SettingsDefaults.algorithmSuspendThreshold }
        set { defaults.set(newValue, forKey: SettingsKey.algorithmSuspendThreshold.rawValue) }
    }
    
    // MARK: - CGM Settings
    
    /// CGM type (dexcomG6, dexcomG7, libre2, etc.)
    public var cgmType: String {
        get { defaults.string(forKey: SettingsKey.cgmType.rawValue) ?? "dexcomG6" }
        set { defaults.set(newValue, forKey: SettingsKey.cgmType.rawValue) }
    }
    
    /// CGM transmitter ID
    public var cgmTransmitterId: String? {
        get { defaults.string(forKey: SettingsKey.cgmTransmitterId.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.cgmTransmitterId.rawValue) }
    }
    
    /// CGM sensor code
    public var cgmSensorCode: String? {
        get { defaults.string(forKey: SettingsKey.cgmSensorCode.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.cgmSensorCode.rawValue) }
    }
    
    /// CGM connection mode
    public var cgmConnectionMode: CGMConnectionMode {
        get {
            guard let raw = defaults.string(forKey: SettingsKey.cgmConnectionMode.rawValue),
                  let mode = CGMConnectionMode(rawValue: raw) else {
                return .ble
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: SettingsKey.cgmConnectionMode.rawValue) }
    }
    
    // MARK: - Pump Settings
    
    /// Pump enabled
    public var pumpEnabled: Bool {
        get { defaults.object(forKey: SettingsKey.pumpEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.pumpEnabled.rawValue) }
    }
    
    /// Pump type
    public var pumpType: String {
        get { defaults.string(forKey: SettingsKey.pumpType.rawValue) ?? "medtronic" }
        set { defaults.set(newValue, forKey: SettingsKey.pumpType.rawValue) }
    }
    
    /// Pump serial number
    public var pumpSerial: String? {
        get { defaults.string(forKey: SettingsKey.pumpSerial.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.pumpSerial.rawValue) }
    }
    
    /// Pump bridge type (rileyLink, orangeLink, etc.)
    public var pumpBridgeType: String? {
        get { defaults.string(forKey: SettingsKey.pumpBridgeType.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.pumpBridgeType.rawValue) }
    }
    
    /// Pump bridge ID
    public var pumpBridgeId: String? {
        get { defaults.string(forKey: SettingsKey.pumpBridgeId.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.pumpBridgeId.rawValue) }
    }
    
    // MARK: - AID Settings
    
    /// AID enabled
    public var aidEnabled: Bool {
        get { defaults.object(forKey: SettingsKey.aidEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.aidEnabled.rawValue) }
    }
    
    /// Closed loop allowed
    public var aidClosedLoopAllowed: Bool {
        get { defaults.object(forKey: SettingsKey.aidClosedLoopAllowed.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.aidClosedLoopAllowed.rawValue) }
    }
    
    /// Last loop execution time
    public var aidLastLoopTime: Date? {
        get { defaults.object(forKey: SettingsKey.aidLastLoopTime.rawValue) as? Date }
        set { defaults.set(newValue, forKey: SettingsKey.aidLastLoopTime.rawValue) }
    }
    
    /// Loop interval in seconds
    public var aidLoopInterval: Int {
        get { defaults.object(forKey: SettingsKey.aidLoopInterval.rawValue) as? Int ?? SettingsDefaults.aidLoopInterval }
        set { defaults.set(newValue, forKey: SettingsKey.aidLoopInterval.rawValue) }
    }
    
    // MARK: - Onboarding Settings
    
    /// Onboarding complete
    public var onboardingComplete: Bool {
        get { defaults.object(forKey: SettingsKey.onboardingComplete.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.onboardingComplete.rawValue) }
    }
    
    /// Onboarding step
    public var onboardingStep: Int {
        get { defaults.object(forKey: SettingsKey.onboardingStep.rawValue) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: SettingsKey.onboardingStep.rawValue) }
    }
    
    /// Terms accepted
    public var termsAccepted: Bool {
        get { defaults.object(forKey: SettingsKey.termsAccepted.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.termsAccepted.rawValue) }
    }
    
    /// Training complete
    public var trainingComplete: Bool {
        get { defaults.object(forKey: SettingsKey.trainingComplete.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKey.trainingComplete.rawValue) }
    }
    
    // MARK: - Composite Settings
    
    /// Get all algorithm settings as a struct
    public func getAlgorithmSettings() -> PersistedAlgorithmSettings {
        PersistedAlgorithmSettings(
            algorithmName: algorithmName,
            dia: algorithmDIA,
            isf: algorithmISF,
            icr: algorithmICR,
            basalRate: algorithmBasalRate,
            targetLow: algorithmTargetLow,
            targetHigh: algorithmTargetHigh,
            smbEnabled: algorithmSMBEnabled,
            maxSMB: algorithmMaxSMB,
            uamEnabled: algorithmUAMEnabled,
            maxBasalRate: algorithmMaxBasalRate,
            maxBolus: algorithmMaxBolus,
            maxIOB: algorithmMaxIOB,
            suspendThreshold: algorithmSuspendThreshold
        )
    }
    
    /// Save algorithm settings from a struct
    public func saveAlgorithmSettings(_ settings: PersistedAlgorithmSettings) {
        algorithmName = settings.algorithmName
        algorithmDIA = settings.dia
        algorithmISF = settings.isf
        algorithmICR = settings.icr
        algorithmBasalRate = settings.basalRate
        algorithmTargetLow = settings.targetLow
        algorithmTargetHigh = settings.targetHigh
        algorithmSMBEnabled = settings.smbEnabled
        algorithmMaxSMB = settings.maxSMB
        algorithmUAMEnabled = settings.uamEnabled
        algorithmMaxBasalRate = settings.maxBasalRate
        algorithmMaxBolus = settings.maxBolus
        algorithmMaxIOB = settings.maxIOB
        algorithmSuspendThreshold = settings.suspendThreshold
    }
    
    /// Get all CGM settings as a struct
    public func getCGMSettings() -> PersistedCGMSettings {
        PersistedCGMSettings(
            cgmType: cgmType,
            transmitterId: cgmTransmitterId,
            sensorCode: cgmSensorCode,
            connectionMode: cgmConnectionMode
        )
    }
    
    /// Save CGM settings from a struct
    public func saveCGMSettings(_ settings: PersistedCGMSettings) {
        cgmType = settings.cgmType
        cgmTransmitterId = settings.transmitterId
        cgmSensorCode = settings.sensorCode
        cgmConnectionMode = settings.connectionMode
    }
    
    /// Get all pump settings as a struct
    public func getPumpSettings() -> PersistedPumpSettings {
        PersistedPumpSettings(
            enabled: pumpEnabled,
            pumpType: pumpType,
            serial: pumpSerial,
            bridgeType: pumpBridgeType,
            bridgeId: pumpBridgeId
        )
    }
    
    /// Save pump settings from a struct
    public func savePumpSettings(_ settings: PersistedPumpSettings) {
        pumpEnabled = settings.enabled
        pumpType = settings.pumpType
        pumpSerial = settings.serial
        pumpBridgeType = settings.bridgeType
        pumpBridgeId = settings.bridgeId
    }
    
    /// Get all AID settings as a struct
    public func getAIDSettings() -> PersistedAIDSettings {
        PersistedAIDSettings(
            enabled: aidEnabled,
            closedLoopAllowed: aidClosedLoopAllowed,
            lastLoopTime: aidLastLoopTime,
            loopInterval: aidLoopInterval
        )
    }
    
    /// Save AID settings from a struct
    public func saveAIDSettings(_ settings: PersistedAIDSettings) {
        aidEnabled = settings.enabled
        aidClosedLoopAllowed = settings.closedLoopAllowed
        aidLastLoopTime = settings.lastLoopTime
        aidLoopInterval = settings.loopInterval
    }
    
    /// Get onboarding settings as a struct
    public func getOnboardingSettings() -> PersistedOnboardingSettings {
        PersistedOnboardingSettings(
            complete: onboardingComplete,
            currentStep: onboardingStep,
            termsAccepted: termsAccepted,
            trainingComplete: trainingComplete
        )
    }
    
    /// Save onboarding settings from a struct
    public func saveOnboardingSettings(_ settings: PersistedOnboardingSettings) {
        onboardingComplete = settings.complete
        onboardingStep = settings.currentStep
        termsAccepted = settings.termsAccepted
        trainingComplete = settings.trainingComplete
    }
}
