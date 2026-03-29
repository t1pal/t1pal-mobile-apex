// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SettingsStore.swift - UserDefaults-backed settings persistence
// Part of T1PalCore
// Trace: PERSIST-001

import Foundation

// MARK: - Settings Store

/// Observable settings store backed by UserDefaults
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// - UserDefaults is thread-safe (Apple docs)
/// - All reads/writes go through UserDefaults APIs
/// Trace: TECH-001, PROD-READY-012
public final class SettingsStore: @unchecked Sendable {
    
    // MARK: - App Group
    
    /// App Group identifier for sharing settings between app and extensions
    public static let appGroupIdentifier = "group.com.t1pal.mobile"
    
    // MARK: - Singleton
    
    /// Shared settings store using standard UserDefaults
    public static let shared = SettingsStore(userDefaults: .standard)
    
    /// App Group settings store for sharing with widgets
    public static let appGroup = SettingsStore(
        userDefaults: UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    )
    
    // MARK: - Properties
    
    /// UserDefaults instance (internal for extension access)
    internal let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }
    
    // MARK: - Keys
    
    private enum Key: String, CaseIterable {
        // Data Source
        case activeDataSourceID = "settings.dataSource.activeID"
        case nightscoutURL = "settings.dataSource.nightscoutURL"
        case nightscoutToken = "settings.dataSource.nightscoutToken"
        
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
        
        // Last sync
        case lastDataFetch = "settings.sync.lastFetch"
        case lastWidgetUpdate = "settings.sync.lastWidgetUpdate"
    }
    
    // MARK: - Data Source Settings
    
    /// Currently active data source identifier
    public var activeDataSourceID: String? {
        get { defaults.string(forKey: Key.activeDataSourceID.rawValue) }
        set { defaults.set(newValue, forKey: Key.activeDataSourceID.rawValue) }
    }
    
    /// Nightscout server URL
    public var nightscoutURL: String? {
        get { defaults.string(forKey: Key.nightscoutURL.rawValue) }
        set { defaults.set(newValue, forKey: Key.nightscoutURL.rawValue) }
    }
    
    /// Nightscout API token (stored securely in Keychain)
    /// NS-SEC-001: Migrated from UserDefaults to Keychain for security
    public var nightscoutToken: String? {
        get {
            // Try Keychain first, fall back to legacy UserDefaults
            if let url = nightscoutURL {
                if let token = KeychainHelper.shared.loadNightscoutToken(forURL: url) {
                    return token
                }
            }
            // Legacy fallback for migration
            return defaults.string(forKey: Key.nightscoutToken.rawValue)
        }
        set {
            if let url = nightscoutURL {
                if let token = newValue {
                    _ = KeychainHelper.shared.saveNightscoutToken(token, forURL: url)
                } else {
                    _ = KeychainHelper.shared.deleteNightscoutToken(forURL: url)
                }
            }
            // Clear legacy storage on any update
            defaults.removeObject(forKey: Key.nightscoutToken.rawValue)
        }
    }
    
    /// Nightscout API secret (stored securely in Keychain)
    /// NS-SEC-001: API secrets must never be stored in plaintext
    public var nightscoutAPISecret: String? {
        get {
            guard let url = nightscoutURL else { return nil }
            return KeychainHelper.shared.loadNightscoutSecret(forURL: url)
        }
        set {
            guard let url = nightscoutURL else { return }
            if let secret = newValue {
                _ = KeychainHelper.shared.saveNightscoutSecret(secret, forURL: url)
            } else {
                _ = KeychainHelper.shared.deleteNightscoutSecret(forURL: url)
            }
        }
    }
    
    // MARK: - Glucose Display Settings
    
    /// Glucose unit preference (mg/dL or mmol/L)
    public var glucoseUnit: GlucoseUnit {
        get {
            guard let raw = defaults.string(forKey: Key.glucoseUnit.rawValue),
                  let unit = GlucoseUnit(rawValue: raw) else {
                return .mgdL
            }
            return unit
        }
        set { defaults.set(newValue.rawValue, forKey: Key.glucoseUnit.rawValue) }
    }
    
    /// High glucose threshold (mg/dL)
    public var highGlucoseThreshold: Double {
        get { defaults.object(forKey: Key.highGlucoseThreshold.rawValue) as? Double ?? 180.0 }
        set { defaults.set(newValue, forKey: Key.highGlucoseThreshold.rawValue) }
    }
    
    /// Low glucose threshold (mg/dL)
    public var lowGlucoseThreshold: Double {
        get { defaults.object(forKey: Key.lowGlucoseThreshold.rawValue) as? Double ?? 70.0 }
        set { defaults.set(newValue, forKey: Key.lowGlucoseThreshold.rawValue) }
    }
    
    /// Urgent high threshold (mg/dL)
    public var urgentHighThreshold: Double {
        get { defaults.object(forKey: Key.urgentHighThreshold.rawValue) as? Double ?? 250.0 }
        set { defaults.set(newValue, forKey: Key.urgentHighThreshold.rawValue) }
    }
    
    /// Urgent low threshold (mg/dL)
    public var urgentLowThreshold: Double {
        get { defaults.object(forKey: Key.urgentLowThreshold.rawValue) as? Double ?? 55.0 }
        set { defaults.set(newValue, forKey: Key.urgentLowThreshold.rawValue) }
    }
    
    // MARK: - Chart Settings
    
    /// Chart time range in hours
    public var chartTimeRangeHours: Int {
        get { defaults.object(forKey: Key.chartTimeRange.rawValue) as? Int ?? 3 }
        set { defaults.set(newValue, forKey: Key.chartTimeRange.rawValue) }
    }
    
    /// Show target glucose range on chart
    public var showTargetRange: Bool {
        get { defaults.object(forKey: Key.showTargetRange.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showTargetRange.rawValue) }
    }
    
    /// Show glucose prediction on chart
    public var showPrediction: Bool {
        get { defaults.object(forKey: Key.showPrediction.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showPrediction.rawValue) }
    }
    
    // MARK: - Notification Settings
    
    /// Master toggle for notifications
    public var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled.rawValue) }
    }
    
    /// High glucose alerts
    public var highAlertEnabled: Bool {
        get { defaults.object(forKey: Key.highAlertEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.highAlertEnabled.rawValue) }
    }
    
    /// Low glucose alerts
    public var lowAlertEnabled: Bool {
        get { defaults.object(forKey: Key.lowAlertEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.lowAlertEnabled.rawValue) }
    }
    
    /// Urgent glucose alerts
    public var urgentAlertEnabled: Bool {
        get { defaults.object(forKey: Key.urgentAlertEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.urgentAlertEnabled.rawValue) }
    }
    
    /// Stale data alerts
    public var staleDataAlertEnabled: Bool {
        get { defaults.object(forKey: Key.staleDataAlertEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.staleDataAlertEnabled.rawValue) }
    }
    
    /// Stale data threshold in minutes
    public var staleDataMinutes: Int {
        get { defaults.object(forKey: Key.staleDataMinutes.rawValue) as? Int ?? 15 }
        set { defaults.set(newValue, forKey: Key.staleDataMinutes.rawValue) }
    }
    
    // MARK: - Appearance Settings
    
    /// Color scheme preference
    public var colorScheme: ColorSchemePreference {
        get {
            guard let raw = defaults.string(forKey: Key.colorScheme.rawValue),
                  let pref = ColorSchemePreference(rawValue: raw) else {
                return .system
            }
            return pref
        }
        set { defaults.set(newValue.rawValue, forKey: Key.colorScheme.rawValue) }
    }
    
    /// Use large glucose readings
    public var useLargeReadings: Bool {
        get { defaults.object(forKey: Key.useLargeReadings.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.useLargeReadings.rawValue) }
    }
    
    // MARK: - Sync Timestamps
    
    /// Last data fetch time
    public var lastDataFetch: Date? {
        get { defaults.object(forKey: Key.lastDataFetch.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.lastDataFetch.rawValue) }
    }
    
    /// Last widget update time
    public var lastWidgetUpdate: Date? {
        get { defaults.object(forKey: Key.lastWidgetUpdate.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.lastWidgetUpdate.rawValue) }
    }
    
    // MARK: - Codable Storage
    
    /// Store any Codable value
    public func set<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
    
    /// Retrieve a Codable value
    public func get<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
    
    // MARK: - Reset
    
    /// Reset all settings to defaults
    public func resetToDefaults() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
    
    /// Synchronize settings
    public func synchronize() {
        defaults.synchronize()
    }
}

// MARK: - Supporting Types

/// Glucose unit preference
public enum GlucoseUnit: String, Codable, Sendable, CaseIterable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
    
    /// Convert mg/dL to display unit
    public func convert(_ mgdL: Double) -> Double {
        switch self {
        case .mgdL: return mgdL
        case .mmolL: return mgdL / 18.0182
        }
    }
    
    /// Format glucose value for display
    public func format(_ mgdL: Double) -> String {
        switch self {
        case .mgdL: return String(format: "%.0f", mgdL)
        case .mmolL: return String(format: "%.1f", convert(mgdL))
        }
    }
    
    /// Unit suffix
    public var suffix: String { rawValue }
}

/// Color scheme preference
public enum ColorSchemePreference: String, Codable, Sendable, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

// MARK: - Settings Snapshot

/// Immutable snapshot of current settings
public struct SettingsSnapshot: Sendable {
    public let glucoseUnit: GlucoseUnit
    public let highThreshold: Double
    public let lowThreshold: Double
    public let urgentHighThreshold: Double
    public let urgentLowThreshold: Double
    public let chartTimeRangeHours: Int
    public let showTargetRange: Bool
    public let showPrediction: Bool
    public let notificationsEnabled: Bool
    public let colorScheme: ColorSchemePreference
    
    public init(from store: SettingsStore = .shared) {
        self.glucoseUnit = store.glucoseUnit
        self.highThreshold = store.highGlucoseThreshold
        self.lowThreshold = store.lowGlucoseThreshold
        self.urgentHighThreshold = store.urgentHighThreshold
        self.urgentLowThreshold = store.urgentLowThreshold
        self.chartTimeRangeHours = store.chartTimeRangeHours
        self.showTargetRange = store.showTargetRange
        self.showPrediction = store.showPrediction
        self.notificationsEnabled = store.notificationsEnabled
        self.colorScheme = store.colorScheme
    }
}
