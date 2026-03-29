// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// Localization.swift - Localization infrastructure
// Part of T1PalCore
// Trace: LOCALE-001

import Foundation

// MARK: - Localization Manager

/// Manages app localization and string lookups
public final class LocalizationManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = LocalizationManager()
    
    // MARK: - Properties
    
    /// Current language code (e.g., "en", "es", "de")
    public private(set) var currentLanguage: String
    
    /// Current locale
    public private(set) var currentLocale: Locale
    
    /// Available languages
    public let supportedLanguages: [LanguageInfo] = [
        LanguageInfo(code: "en", name: "English", nativeName: "English"),
        LanguageInfo(code: "es", name: "Spanish", nativeName: "Español"),
        LanguageInfo(code: "de", name: "German", nativeName: "Deutsch"),
        LanguageInfo(code: "fr", name: "French", nativeName: "Français"),
        LanguageInfo(code: "it", name: "Italian", nativeName: "Italiano"),
        LanguageInfo(code: "pt", name: "Portuguese", nativeName: "Português"),
        LanguageInfo(code: "nl", name: "Dutch", nativeName: "Nederlands"),
        LanguageInfo(code: "pl", name: "Polish", nativeName: "Polski"),
        LanguageInfo(code: "ru", name: "Russian", nativeName: "Русский"),
        LanguageInfo(code: "ja", name: "Japanese", nativeName: "日本語"),
        LanguageInfo(code: "zh", name: "Chinese", nativeName: "中文"),
        LanguageInfo(code: "ko", name: "Korean", nativeName: "한국어"),
    ]
    
    // MARK: - Initialization
    
    private init() {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        let languageCode = String(preferredLanguage.prefix(2))
        self.currentLanguage = languageCode
        self.currentLocale = Locale(identifier: preferredLanguage)
    }
    
    // MARK: - Language Selection
    
    /// Set the current language
    public func setLanguage(_ code: String) {
        guard supportedLanguages.contains(where: { $0.code == code }) else { return }
        currentLanguage = code
        currentLocale = Locale(identifier: code)
        
        // Store preference
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Notify observers
        NotificationCenter.default.post(
            name: .languageDidChange,
            object: nil,
            userInfo: ["language": code]
        )
    }
    
    /// Reset to system language
    public func resetToSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        currentLanguage = String(preferredLanguage.prefix(2))
        currentLocale = Locale(identifier: preferredLanguage)
        
        NotificationCenter.default.post(
            name: .languageDidChange,
            object: nil,
            userInfo: ["language": currentLanguage]
        )
    }
    
    // MARK: - String Lookup
    
    /// Get localized string for key
    public func string(_ key: String, table: String? = nil) -> String {
        // First try the app bundle
        let value = Bundle.main.localizedString(forKey: key, value: nil, table: table)
        if value != key { return value }
        
        // Fall back to English
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: table)
        }
        
        return key
    }
    
    /// Get localized string with format arguments
    public func string(_ key: String, _ arguments: CVarArg..., table: String? = nil) -> String {
        let format = string(key, table: table)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - Language Info

/// Information about a supported language
public struct LanguageInfo: Identifiable, Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let nativeName: String
    
    public init(code: String, name: String, nativeName: String) {
        self.id = code
        self.code = code
        self.name = name
        self.nativeName = nativeName
    }
}

// MARK: - Notification Names

extension Notification.Name {
    public static let languageDidChange = Notification.Name("com.t1pal.languageDidChange")
}

// MARK: - Localizable Keys

/// Centralized localization keys for type-safe access
public enum L10n {
    
    // MARK: - Common
    
    public enum Common {
        public static let ok = "common.ok"
        public static let cancel = "common.cancel"
        public static let save = "common.save"
        public static let delete = "common.delete"
        public static let edit = "common.edit"
        public static let done = "common.done"
        public static let retry = "common.retry"
        public static let loading = "common.loading"
        public static let error = "common.error"
        public static let success = "common.success"
    }
    
    // MARK: - Glucose
    
    public enum Glucose {
        public static let current = "glucose.current"
        public static let trend = "glucose.trend"
        public static let high = "glucose.high"
        public static let low = "glucose.low"
        public static let inRange = "glucose.inRange"
        public static let urgentHigh = "glucose.urgentHigh"
        public static let urgentLow = "glucose.urgentLow"
        public static let stale = "glucose.stale"
        public static let mgdL = "glucose.unit.mgdL"
        public static let mmolL = "glucose.unit.mmolL"
    }
    
    // MARK: - Trends
    
    public enum Trend {
        public static let risingRapidly = "trend.risingRapidly"
        public static let rising = "trend.rising"
        public static let risingSlowly = "trend.risingSlowly"
        public static let flat = "trend.flat"
        public static let fallingSlowly = "trend.fallingSlowly"
        public static let falling = "trend.falling"
        public static let fallingRapidly = "trend.fallingRapidly"
    }
    
    // MARK: - Alerts
    
    public enum Alert {
        public static let highTitle = "alert.high.title"
        public static let highBody = "alert.high.body"
        public static let lowTitle = "alert.low.title"
        public static let lowBody = "alert.low.body"
        public static let urgentHighTitle = "alert.urgentHigh.title"
        public static let urgentHighBody = "alert.urgentHigh.body"
        public static let urgentLowTitle = "alert.urgentLow.title"
        public static let urgentLowBody = "alert.urgentLow.body"
        public static let staleTitle = "alert.stale.title"
        public static let staleBody = "alert.stale.body"
    }
    
    // MARK: - Settings
    
    public enum Settings {
        public static let title = "settings.title"
        public static let glucoseUnit = "settings.glucoseUnit"
        public static let highThreshold = "settings.highThreshold"
        public static let lowThreshold = "settings.lowThreshold"
        public static let notifications = "settings.notifications"
        public static let dataSource = "settings.dataSource"
        public static let appearance = "settings.appearance"
        public static let language = "settings.language"
    }
    
    // MARK: - Data Sources
    
    public enum DataSource {
        public static let nightscout = "dataSource.nightscout"
        public static let dexcomShare = "dataSource.dexcomShare"
        public static let demo = "dataSource.demo"
        public static let connected = "dataSource.connected"
        public static let connecting = "dataSource.connecting"
        public static let disconnected = "dataSource.disconnected"
        public static let error = "dataSource.error"
    }
    
    // MARK: - Statistics
    
    public enum Stats {
        public static let timeInRange = "stats.timeInRange"
        public static let averageGlucose = "stats.averageGlucose"
        public static let estimatedA1C = "stats.estimatedA1C"
        public static let standardDeviation = "stats.standardDeviation"
        public static let coefficientOfVariation = "stats.coefficientOfVariation"
    }
    
    // MARK: - Accessibility
    
    public enum A11y {
        public static let glucoseReading = "a11y.glucoseReading"
        public static let trendArrow = "a11y.trendArrow"
        public static let chart = "a11y.chart"
        public static let refreshButton = "a11y.refreshButton"
    }
}

// MARK: - Lifecycle Localization Keys (LIFE-NOTIFY-002)

/// Localization keys for lifecycle notification strings
/// Trace: LIFE-NOTIFY-002
public enum LifecycleL10n {
    
    // MARK: - Sensor Expiration
    
    public enum Sensor {
        public static let expires24hTitle = "lifecycle.sensor.expires24h.title"
        public static let expires24hBody = "lifecycle.sensor.expires24h.body"
        public static let expires6hTitle = "lifecycle.sensor.expires6h.title"
        public static let expires6hBody = "lifecycle.sensor.expires6h.body"
        public static let expires1hTitle = "lifecycle.sensor.expires1h.title"
        public static let expires1hBody = "lifecycle.sensor.expires1h.body"
        public static let expiredTitle = "lifecycle.sensor.expired.title"
        public static let expiredBody = "lifecycle.sensor.expired.body"
        public static let expiresMessage24h = "lifecycle.sensor.expires.message.24h"
        public static let expiresMessage6h = "lifecycle.sensor.expires.message.6h"
        public static let expiresMessage1h = "lifecycle.sensor.expires.message.1h"
        public static let expiredMessage = "lifecycle.sensor.expired.message"
        // Progress display
        public static let remainingExpired = "lifecycle.sensor.remaining.expired"
        public static let remainingMinutes = "lifecycle.sensor.remaining.minutes"
        public static let remainingHours = "lifecycle.sensor.remaining.hours"
        public static let remainingDays = "lifecycle.sensor.remaining.days"
    }
    
    // MARK: - Transmitter Expiration
    
    public enum Transmitter {
        public static let expires14dTitle = "lifecycle.transmitter.expires14d.title"
        public static let expires14dMessage = "lifecycle.transmitter.expires14d.message"
        public static let expires7dTitle = "lifecycle.transmitter.expires7d.title"
        public static let expires7dMessage = "lifecycle.transmitter.expires7d.message"
        public static let expires3dTitle = "lifecycle.transmitter.expires3d.title"
        public static let expires3dMessage = "lifecycle.transmitter.expires3d.message"
        public static let expires1dTitle = "lifecycle.transmitter.expires1d.title"
        public static let expires1dMessage = "lifecycle.transmitter.expires1d.message"
        public static let expiredTitle = "lifecycle.transmitter.expired.title"
        public static let expiredMessage = "lifecycle.transmitter.expired.message"
        public static let batteryLowTitle = "lifecycle.transmitter.batteryLow.title"
        public static let batteryLowMessage = "lifecycle.transmitter.batteryLow.message"
    }
    
    // MARK: - Pod Expiration
    
    public enum Pod {
        public static let expires8hTitle = "lifecycle.pod.expires8h.title"
        public static let expires8hMessage = "lifecycle.pod.expires8h.message"
        public static let expires4hTitle = "lifecycle.pod.expires4h.title"
        public static let expires4hMessage = "lifecycle.pod.expires4h.message"
        public static let expires1hTitle = "lifecycle.pod.expires1h.title"
        public static let expires1hMessage = "lifecycle.pod.expires1h.message"
        public static let expiredTitle = "lifecycle.pod.expired.title"
        public static let expiredMessage = "lifecycle.pod.expired.message"
        public static let gracePeriodTitle = "lifecycle.pod.gracePeriod.title"
        public static let gracePeriodMessage = "lifecycle.pod.gracePeriod.message"
        public static let hardStopTitle = "lifecycle.pod.hardStop.title"
        public static let hardStopMessage = "lifecycle.pod.hardStop.message"
    }
    
    // MARK: - Reservoir
    
    public enum Reservoir {
        public static let low50Title = "lifecycle.reservoir.low50.title"
        public static let low50Message = "lifecycle.reservoir.low50.message"
        public static let low20Title = "lifecycle.reservoir.low20.title"
        public static let low20Message = "lifecycle.reservoir.low20.message"
        public static let low10Title = "lifecycle.reservoir.low10.title"
        public static let low10Message = "lifecycle.reservoir.low10.message"
        public static let emptyTitle = "lifecycle.reservoir.empty.title"
        public static let emptyMessage = "lifecycle.reservoir.empty.message"
    }
    
    // MARK: - Pump Battery
    
    public enum PumpBattery {
        public static let lowTitle = "lifecycle.pumpBattery.low.title"
        public static let lowMessage = "lifecycle.pumpBattery.low.message"
        public static let criticalTitle = "lifecycle.pumpBattery.critical.title"
        public static let criticalMessage = "lifecycle.pumpBattery.critical.message"
        public static let emptyTitle = "lifecycle.pumpBattery.empty.title"
        public static let emptyMessage = "lifecycle.pumpBattery.empty.message"
    }
}

// MARK: - String Extension

extension String {
    /// Get localized version of this string key
    public var localized: String {
        LocalizationManager.shared.string(self)
    }
    
    /// Get localized string with format arguments
    public func localized(_ arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.string(self)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - Glucose Formatters

/// Locale-aware formatters for glucose values
public struct GlucoseFormatters {
    
    /// Format glucose value with unit
    public static func format(_ value: Double, unit: GlucoseUnit, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        
        switch unit {
        case .mgdL:
            formatter.maximumFractionDigits = 0
            let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
            return "\(formatted) \(unit.suffix)"
        case .mmolL:
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
            let converted = unit.convert(value)
            let formatted = formatter.string(from: NSNumber(value: converted)) ?? String(format: "%.1f", converted)
            return "\(formatted) \(unit.suffix)"
        }
    }
    
    /// Format time ago (e.g., "5 min ago")
    public static func formatTimeAgo(_ date: Date, locale: Locale = .current) -> String {
        let elapsed = Date().timeIntervalSince(date)
        
        if elapsed < 60 {
            return "Just now".localized
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return String(format: "%d min ago".localized, minutes)
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return String(format: "%d hour%@ ago".localized, hours, hours == 1 ? "" : "s")
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    /// Format glucose range (e.g., "70-180 mg/dL")
    public static func formatRange(low: Double, high: Double, unit: GlucoseUnit) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = unit == .mgdL ? 0 : 1
        
        let lowConverted = unit == .mmolL ? unit.convert(low) : low
        let highConverted = unit == .mmolL ? unit.convert(high) : high
        
        let lowStr = formatter.string(from: NSNumber(value: lowConverted)) ?? "\(lowConverted)"
        let highStr = formatter.string(from: NSNumber(value: highConverted)) ?? "\(highConverted)"
        
        return "\(lowStr)-\(highStr) \(unit.suffix)"
    }
}
