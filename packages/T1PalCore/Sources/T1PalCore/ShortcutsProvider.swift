// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ShortcutsProvider.swift - Siri Shortcuts and App Intents
// Part of T1PalCore
// Trace: SHORTCUT-001

import Foundation

#if canImport(Intents)
import Intents
#endif

#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Shortcut Definitions

/// Available shortcuts that can be added to Siri
public enum T1PalShortcut: String, CaseIterable, Sendable {
    case checkGlucose = "check-glucose"
    case viewStats = "view-stats"
    case snoozeAlerts = "snooze-alerts"
    case logCarbs = "log-carbs"
    case logInsulin = "log-insulin"
    case syncNow = "sync-now"
    
    /// Display name for Siri
    public var displayName: String {
        switch self {
        case .checkGlucose: return "Check Glucose"
        case .viewStats: return "View Statistics"
        case .snoozeAlerts: return "Snooze Alerts"
        case .logCarbs: return "Log Carbs"
        case .logInsulin: return "Log Insulin"
        case .syncNow: return "Sync Now"
        }
    }
    
    /// Suggested phrase for Siri
    public var suggestedPhrase: String {
        switch self {
        case .checkGlucose: return "Check my glucose"
        case .viewStats: return "Show my diabetes stats"
        case .snoozeAlerts: return "Snooze T1Pal alerts"
        case .logCarbs: return "Log carbs"
        case .logInsulin: return "Log insulin"
        case .syncNow: return "Sync T1Pal"
        }
    }
    
    /// Activity type for NSUserActivity
    public var activityType: String {
        "com.t1pal.shortcut.\(rawValue)"
    }
}

// MARK: - Shortcut Manager

/// Manages Siri shortcut donations and suggestions
public final class ShortcutsManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ShortcutsManager()
    
    // MARK: - Configuration
    
    /// Whether shortcuts are enabled
    public var isEnabled: Bool = true
    
    /// Which shortcuts to suggest
    public var enabledShortcuts: Set<T1PalShortcut> = Set(T1PalShortcut.allCases)
    
    // MARK: - Callbacks
    
    /// Called when a shortcut is invoked
    public var onShortcutInvoked: ((T1PalShortcut, [String: Any]?) -> Void)?
    
    // MARK: - State
    
    private let lock = NSLock()
    private var donationHistory: [T1PalShortcut: Date] = [:]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Donation
    
    /// Donate a shortcut to Siri based on user action
    public func donate(_ shortcut: T1PalShortcut) {
        guard isEnabled, enabledShortcuts.contains(shortcut) else { return }
        
        lock.withLock {
            donationHistory[shortcut] = Date()
        }
        
        #if canImport(Intents) && os(iOS)
        donateIntent(shortcut)
        #endif
    }
    
    #if canImport(Intents) && os(iOS)
    private func donateIntent(_ shortcut: T1PalShortcut) {
        // Create user activity
        let activity = NSUserActivity(activityType: shortcut.activityType)
        activity.title = shortcut.displayName
        activity.suggestedInvocationPhrase = shortcut.suggestedPhrase
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        
        // Donate
        activity.becomeCurrent()
    }
    #endif
    
    // MARK: - Suggestions
    
    /// Set up suggested shortcuts
    public func setupSuggestions() {
        #if canImport(Intents) && os(iOS)
        var suggestions: [INShortcut] = []
        
        for shortcut in enabledShortcuts {
            let activity = NSUserActivity(activityType: shortcut.activityType)
            activity.title = shortcut.displayName
            activity.suggestedInvocationPhrase = shortcut.suggestedPhrase
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            
            suggestions.append(INShortcut(userActivity: activity))
        }
        
        INVoiceShortcutCenter.shared.setShortcutSuggestions(suggestions)
        #endif
    }
    
    /// Remove all shortcut suggestions
    public func clearSuggestions() {
        #if canImport(Intents) && os(iOS)
        INVoiceShortcutCenter.shared.setShortcutSuggestions([])
        #endif
    }
    
    // MARK: - Handling
    
    #if canImport(Intents)
    /// Handle user activity from shortcut
    public func handle(_ activity: NSUserActivity) -> Bool {
        guard let shortcut = T1PalShortcut.allCases.first(where: { 
            activity.activityType == $0.activityType 
        }) else {
            return false
        }
        
        onShortcutInvoked?(shortcut, activity.userInfo as? [String: Any])
        return true
    }
    #endif
    
    // MARK: - Stats
    
    /// Get donation count for shortcut
    public func donationCount(for shortcut: T1PalShortcut) -> Int {
        lock.withLock {
            donationHistory[shortcut] != nil ? 1 : 0
        }
    }
    
    /// Get last donation date
    public func lastDonation(for shortcut: T1PalShortcut) -> Date? {
        lock.withLock {
            donationHistory[shortcut]
        }
    }
}

// MARK: - App Intents (iOS 16+)

#if canImport(AppIntents)

/// Check glucose intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct CheckGlucoseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Glucose"
    public static var description = IntentDescription("Get your current glucose reading")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Return a placeholder - actual implementation would read from data source
        return .result(dialog: "Your glucose reading will appear here")
    }
}

/// View stats intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct ViewStatsIntent: AppIntent {
    public static var title: LocalizedStringResource = "View Statistics"
    public static var description = IntentDescription("See your diabetes statistics")
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        ShortcutsManager.shared.onShortcutInvoked?(.viewStats, nil)
        return .result()
    }
}

/// Snooze alerts intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct SnoozeAlertsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Snooze Alerts"
    public static var description = IntentDescription("Snooze glucose alerts temporarily")
    
    @Parameter(title: "Duration (minutes)", default: 30)
    public var duration: Int
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let params = ["duration": duration]
        ShortcutsManager.shared.onShortcutInvoked?(.snoozeAlerts, params)
        return .result(dialog: "Alerts snoozed for \(duration) minutes")
    }
}

/// Log carbs intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct LogCarbsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Carbs"
    public static var description = IntentDescription("Log carbohydrate intake")
    
    @Parameter(title: "Carbs (grams)")
    public var carbs: Int?
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if let carbs = carbs {
            let params = ["carbs": carbs]
            ShortcutsManager.shared.onShortcutInvoked?(.logCarbs, params)
            return .result(dialog: "Logged \(carbs) grams of carbs")
        } else {
            // Open app for input
            ShortcutsManager.shared.onShortcutInvoked?(.logCarbs, nil)
            return .result(dialog: "Opening T1Pal to log carbs")
        }
    }
}

/// Log insulin intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct LogInsulinIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Insulin"
    public static var description = IntentDescription("Log insulin dose")
    
    @Parameter(title: "Units")
    public var units: Double?
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if let units = units {
            let params = ["units": units]
            ShortcutsManager.shared.onShortcutInvoked?(.logInsulin, params)
            return .result(dialog: "Logged \(units) units of insulin")
        } else {
            ShortcutsManager.shared.onShortcutInvoked?(.logInsulin, nil)
            return .result(dialog: "Opening T1Pal to log insulin")
        }
    }
}

/// Sync now intent
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct SyncNowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Sync Now"
    public static var description = IntentDescription("Sync with Nightscout immediately")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        ShortcutsManager.shared.onShortcutInvoked?(.syncNow, nil)
        return .result(dialog: "Syncing with Nightscout")
    }
}

/// App Shortcuts provider
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct T1PalShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckGlucoseIntent(),
            phrases: [
                "Check my glucose with \(.applicationName)",
                "What's my blood sugar in \(.applicationName)",
                "Check \(.applicationName)"
            ],
            shortTitle: "Check Glucose",
            systemImageName: "drop.fill"
        )
        
        AppShortcut(
            intent: SnoozeAlertsIntent(),
            phrases: [
                "Snooze \(.applicationName) alerts",
                "Quiet \(.applicationName)"
            ],
            shortTitle: "Snooze Alerts",
            systemImageName: "bell.slash.fill"
        )
        
        AppShortcut(
            intent: LogCarbsIntent(),
            phrases: [
                "Log carbs in \(.applicationName)",
                "Record carbs with \(.applicationName)"
            ],
            shortTitle: "Log Carbs",
            systemImageName: "fork.knife"
        )
        
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Update \(.applicationName)"
            ],
            shortTitle: "Sync Now",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}

#endif

// MARK: - Shortcut URL Generation

extension T1PalShortcut {
    /// Generate deep link URL for this shortcut
    public var deepLinkURL: URL? {
        switch self {
        case .checkGlucose:
            return URL(string: "t1pal://home")
        case .viewStats:
            return URL(string: "t1pal://stats")
        case .snoozeAlerts:
            return URL(string: "t1pal://snooze")
        case .logCarbs:
            return URL(string: "t1pal://log-carbs")
        case .logInsulin:
            return URL(string: "t1pal://log-insulin")
        case .syncNow:
            return URL(string: "t1pal://refresh")
        }
    }
}
