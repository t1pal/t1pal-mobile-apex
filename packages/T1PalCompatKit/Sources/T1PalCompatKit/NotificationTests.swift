// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NotificationTests.swift
// T1PalCompatKit
//
// Notification capability tests for glucose alerts.
// Trace: PRD-006 REQ-COMPAT-003
//
// These tests verify notification capabilities required for CGM alerts.
// On Linux, tests return .unsupported status.

import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

// MARK: - Notification Authorization Test

/// Test notification authorization status
public struct NotificationAuthorizationTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-authorization"
    public let name = "Notification Authorization"
    public let category = CapabilityCategory.notification
    public let priority = 20
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications)
        let startTime = Date()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let duration = Date().timeIntervalSince(startTime)
        
        let details: [String: String] = [
            "authorizationStatus": authStatusDescription(settings.authorizationStatus),
            "alertSetting": settingDescription(settings.alertSetting),
            "badgeSetting": settingDescription(settings.badgeSetting),
            "soundSetting": settingDescription(settings.soundSetting)
        ]
        
        switch settings.authorizationStatus {
        case .authorized:
            return passed("Notifications authorized", details: details, duration: duration)
        case .provisional:
            return passed("Notifications authorized (provisional)", details: details, duration: duration)
        case .ephemeral:
            return passed("Notifications authorized (ephemeral)", details: details, duration: duration)
        case .notDetermined:
            return skipped("Notification authorization not yet requested", details: details)
        case .denied:
            return failed("Notifications denied by user", details: details, duration: duration)
        @unknown default:
            return failed("Unknown authorization status", details: details, duration: duration)
        }
        #else
        return unsupported("UserNotifications not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    private func authStatusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
    
    private func settingDescription(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - Critical Alerts Test

/// Test critical alerts capability (requires entitlement from Apple)
public struct CriticalAlertsTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-critical-alerts"
    public let name = "Critical Alerts"
    public let category = CapabilityCategory.notification
    public let priority = 21
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications) && os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "criticalAlertSetting": criticalSettingDescription(settings.criticalAlertSetting),
            "note": "Requires com.apple.developer.usernotifications.critical-alerts entitlement"
        ]
        
        switch settings.criticalAlertSetting {
        case .enabled:
            return passed("Critical alerts enabled", details: details)
        case .disabled:
            return failed("Critical alerts disabled", details: details)
        case .notSupported:
            return skipped("Critical alerts not supported (missing entitlement)", details: details)
        @unknown default:
            return failed("Unknown critical alert status", details: details)
        }
        #elseif os(macOS)
        return unsupported("Critical alerts are iOS-only")
        #else
        return unsupported("UserNotifications not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    private func criticalSettingDescription(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - Time Sensitive Test

/// Test time sensitive notification capability (iOS 15+)
public struct TimeSensitiveTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-time-sensitive"
    public let name = "Time Sensitive Notifications"
    public let category = CapabilityCategory.notification
    public let priority = 22
    public let minimumIOSVersion: String? = "15.0"
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications) && os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "timeSensitiveSetting": settingDescription(settings.timeSensitiveSetting),
            "note": "iOS 15+ feature for breakthrough Do Not Disturb"
        ]
        
        switch settings.timeSensitiveSetting {
        case .enabled:
            return passed("Time sensitive notifications enabled", details: details)
        case .disabled:
            return failed("Time sensitive notifications disabled", details: details)
        case .notSupported:
            return skipped("Time sensitive not supported", details: details)
        @unknown default:
            return failed("Unknown time sensitive status", details: details)
        }
        #elseif os(macOS)
        return unsupported("Time sensitive notifications are iOS-only")
        #else
        return unsupported("UserNotifications not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    private func settingDescription(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - Sound Settings Test

/// Test notification sound capabilities
public struct NotificationSoundTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-sound"
    public let name = "Notification Sounds"
    public let category = CapabilityCategory.notification
    public let priority = 23
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "soundSetting": settingDescription(settings.soundSetting),
            "alertSetting": settingDescription(settings.alertSetting)
        ]
        
        switch settings.soundSetting {
        case .enabled:
            return passed("Notification sounds enabled", details: details)
        case .disabled:
            return failed("Notification sounds disabled", details: details)
        case .notSupported:
            return skipped("Notification sounds not supported", details: details)
        @unknown default:
            return failed("Unknown sound setting", details: details)
        }
        #else
        return unsupported("UserNotifications not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    private func settingDescription(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }
    #endif
}

// MARK: - Alert Style Test

/// Test notification alert style (banner, alert, none)
public struct AlertStyleTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-alert-style"
    public let name = "Notification Alert Style"
    public let category = CapabilityCategory.notification
    public let priority = 24
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications) && os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "alertStyle": alertStyleDescription(settings.alertStyle),
            "showPreviewsSetting": previewsDescription(settings.showPreviewsSetting)
        ]
        
        switch settings.alertStyle {
        case .alert:
            return passed("Alert style: Full alert", details: details)
        case .banner:
            return passed("Alert style: Banner", details: details)
        case .none:
            return failed("Alert style: None (notifications won't be visible)", details: details)
        @unknown default:
            return failed("Unknown alert style", details: details)
        }
        #elseif os(macOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "alertStyle": macAlertStyleDescription(settings.alertStyle)
        ]
        
        switch settings.alertStyle {
        case .alert, .banner:
            return passed("Notifications visible", details: details)
        case .none:
            return failed("Notifications hidden", details: details)
        @unknown default:
            return failed("Unknown alert style", details: details)
        }
        #else
        return unsupported("Alert style not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    #if os(iOS)
    private func alertStyleDescription(_ style: UNAlertStyle) -> String {
        switch style {
        case .alert: return "alert"
        case .banner: return "banner"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
    
    private func previewsDescription(_ setting: UNShowPreviewsSetting) -> String {
        switch setting {
        case .always: return "always"
        case .whenAuthenticated: return "whenAuthenticated"
        case .never: return "never"
        @unknown default: return "unknown"
        }
    }
    #endif
    
    #if os(macOS)
    private func macAlertStyleDescription(_ style: UNAlertStyle) -> String {
        switch style {
        case .alert: return "alert"
        case .banner: return "banner"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
    #endif
    #endif
}

// MARK: - Scheduled Delivery Test

/// Test scheduled notification delivery capability
public struct ScheduledDeliveryTest: CapabilityTest, @unchecked Sendable {
    public let id = "notif-scheduled-delivery"
    public let name = "Scheduled Delivery"
    public let category = CapabilityCategory.notification
    public let priority = 25
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(UserNotifications) && os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let details: [String: String] = [
            "scheduledDeliverySetting": settingDescription(settings.scheduledDeliverySetting),
            "note": "iOS 15+ Focus mode feature"
        ]
        
        switch settings.scheduledDeliverySetting {
        case .enabled:
            return passed("Scheduled delivery enabled (Focus mode may delay)", details: details)
        case .disabled:
            return passed("Scheduled delivery disabled (immediate delivery)", details: details)
        case .notSupported:
            return passed("Scheduled delivery not applicable", details: details)
        @unknown default:
            return passed("Unknown scheduled delivery status", details: details)
        }
        #elseif os(macOS)
        return unsupported("Scheduled delivery is iOS-only")
        #else
        return unsupported("UserNotifications not available on this platform")
        #endif
    }
    
    #if canImport(UserNotifications)
    private func settingDescription(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }
    #endif
}
