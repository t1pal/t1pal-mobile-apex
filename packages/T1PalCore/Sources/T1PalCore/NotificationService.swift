// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NotificationService.swift - Glucose notification scheduling
// Part of T1PalCore
// Trace: NOTIF-001

import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

// MARK: - Notification Types

/// Types of glucose notifications
public enum GlucoseNotificationType: String, CaseIterable, Sendable {
    case urgentLow = "glucose.urgentLow"
    case low = "glucose.low"
    case high = "glucose.high"
    case urgentHigh = "glucose.urgentHigh"
    case rising = "glucose.rising"
    case falling = "glucose.falling"
    case staleData = "glucose.stale"
    case pumpAlert = "pump.alert"
    case sensorExpiring = "sensor.expiring"
    case transmitterExpiring = "transmitter.expiring"
    case transmitterBatteryLow = "transmitter.batteryLow"
    case podExpiring = "pod.expiring"
    case podExpired = "pod.expired"
    case reservoirLow = "reservoir.low"
    case pumpBatteryLow = "pump.batteryLow"
    case sensorWarmup = "sensor.warmup"
    case warmupComplete = "sensor.warmupComplete"
    case orderSupplies = "supplies.order"  // LIFE-UI-005
    case connected = "connection.connected"
    case disconnected = "connection.disconnected"
    
    /// Notification category identifier
    public var categoryIdentifier: String {
        "com.t1pal.notification.\(rawValue)"
    }
    
    /// Default sound name
    public var soundName: String? {
        switch self {
        case .urgentLow, .urgentHigh:
            return "urgent_alert.wav"
        case .low, .high:
            return "alert.wav"
        case .rising, .falling:
            return "trend.wav"
        default:
            return nil
        }
    }
    
    /// Whether notification is critical (bypasses Do Not Disturb)
    public var isCritical: Bool {
        switch self {
        case .urgentLow, .urgentHigh:
            return true
        default:
            return false
        }
    }
    
    /// Whether this notification type can be snoozed (LIFE-NOTIFY-005)
    /// Critical alerts that indicate immediate action required cannot be snoozed
    public var isSnoozeable: Bool {
        switch self {
        case .urgentLow, .urgentHigh, .podExpired:
            // Critical glucose and expired pod cannot be snoozed
            return false
        case .podExpiring, .reservoirLow, .pumpBatteryLow, .sensorExpiring, .transmitterExpiring, .transmitterBatteryLow:
            // Lifecycle warnings can be snoozed
            return true
        case .low, .high, .rising, .falling:
            // Standard glucose alerts can be snoozed
            return true
        case .staleData, .pumpAlert, .connected, .disconnected, .sensorWarmup, .warmupComplete, .orderSupplies:
            // Informational alerts can be snoozed
            return true
        }
    }
    
    /// Interruption level
    public var interruptionLevel: NotificationInterruptionLevel {
        switch self {
        case .urgentLow, .urgentHigh, .podExpired:
            return .critical
        case .low, .high, .rising, .falling, .podExpiring, .reservoirLow:
            return .timeSensitive
        case .staleData, .pumpAlert, .sensorExpiring, .transmitterExpiring, .transmitterBatteryLow, .pumpBatteryLow, .orderSupplies:
            return .active
        default:
            return .passive
        }
    }
}

/// Notification interruption level
public enum NotificationInterruptionLevel: String, Sendable {
    case passive
    case active
    case timeSensitive
    case critical
}

// MARK: - Notification Content

/// Content for a glucose notification
public struct GlucoseNotificationContent: Sendable {
    public let type: GlucoseNotificationType
    public let title: String
    public let body: String
    public let glucoseValue: Double?
    public let trend: String?
    public let timestamp: Date
    public let userInfo: [String: String]
    
    public init(
        type: GlucoseNotificationType,
        title: String,
        body: String,
        glucoseValue: Double? = nil,
        trend: String? = nil,
        timestamp: Date = Date(),
        userInfo: [String: String] = [:]
    ) {
        self.type = type
        self.title = title
        self.body = body
        self.glucoseValue = glucoseValue
        self.trend = trend
        self.timestamp = timestamp
        self.userInfo = userInfo
    }
}

// MARK: - Notification Settings

/// User notification preferences
public struct NotificationSettings: Codable, Sendable {
    public var enabled: Bool
    public var urgentLowEnabled: Bool
    public var lowEnabled: Bool
    public var highEnabled: Bool
    public var urgentHighEnabled: Bool
    public var risingEnabled: Bool
    public var fallingEnabled: Bool
    public var staleDataEnabled: Bool
    
    /// Snooze duration in minutes
    public var snoozeDuration: Int
    
    /// Repeat interval in minutes (0 = no repeat)
    public var repeatInterval: Int
    
    /// Quiet hours start (nil = disabled)
    public var quietHoursStart: Int?
    
    /// Quiet hours end
    public var quietHoursEnd: Int?
    
    public init(
        enabled: Bool = true,
        urgentLowEnabled: Bool = true,
        lowEnabled: Bool = true,
        highEnabled: Bool = true,
        urgentHighEnabled: Bool = true,
        risingEnabled: Bool = true,
        fallingEnabled: Bool = true,
        staleDataEnabled: Bool = true,
        snoozeDuration: Int = 30,
        repeatInterval: Int = 5,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil
    ) {
        self.enabled = enabled
        self.urgentLowEnabled = urgentLowEnabled
        self.lowEnabled = lowEnabled
        self.highEnabled = highEnabled
        self.urgentHighEnabled = urgentHighEnabled
        self.risingEnabled = risingEnabled
        self.fallingEnabled = fallingEnabled
        self.staleDataEnabled = staleDataEnabled
        self.snoozeDuration = snoozeDuration
        self.repeatInterval = repeatInterval
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
    }
    
    public static let `default` = NotificationSettings()
    
    /// Check if a notification type is enabled
    public func isEnabled(for type: GlucoseNotificationType) -> Bool {
        guard enabled else { return false }
        
        switch type {
        case .urgentLow: return urgentLowEnabled
        case .low: return lowEnabled
        case .high: return highEnabled
        case .urgentHigh: return urgentHighEnabled
        case .rising: return risingEnabled
        case .falling: return fallingEnabled
        case .staleData: return staleDataEnabled
        default: return true
        }
    }
    
    /// Check if currently in quiet hours
    public func isInQuietHours() -> Bool {
        guard let start = quietHoursStart, let end = quietHoursEnd else {
            return false
        }
        
        let calendar = Calendar.current
        let now = calendar.component(.hour, from: Date())
        
        if start <= end {
            return now >= start && now < end
        } else {
            // Wraps midnight
            return now >= start || now < end
        }
    }
}

// MARK: - Notification Service

/// Service for scheduling and managing glucose notifications
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// 1. Singleton pattern requires class semantics (shared state)
/// 2. All mutable state protected by NSLock
/// 3. UNUserNotificationCenter is thread-safe (Apple docs)
/// Trace: TECH-001, PROD-READY-012
public final class NotificationService: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = NotificationService()
    
    // MARK: - Properties
    
    public var settings: NotificationSettings = .default
    private var snoozedTypes: [GlucoseNotificationType: Date] = [:]
    private var lastNotificationTime: [GlucoseNotificationType: Date] = [:]
    private let lock = NSLock()
    
    #if canImport(UserNotifications)
    /// UNUserNotificationCenter.current() is thread-safe and returns a process-wide singleton.
    /// Trace: THREAD-005 (verified safe)
    private let notificationCenter = UNUserNotificationCenter.current()
    #endif
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Authorization
    
    /// Request notification authorization
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert]
            let granted = try await notificationCenter.requestAuthorization(options: options)
            return granted
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Check current authorization status
    public func checkAuthorization() async -> NotificationAuthorizationStatus {
        #if canImport(UserNotifications)
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
        #else
        return .unavailable
        #endif
    }
    
    // MARK: - Schedule Notifications
    
    /// Schedule a glucose notification
    public func scheduleNotification(_ content: GlucoseNotificationContent) async {
        guard settings.isEnabled(for: content.type) else { return }
        guard !isSnoozed(content.type) else { return }
        guard !settings.isInQuietHours() || content.type.isCritical else { return }
        
        // Check rate limiting
        if let last = lastNotificationTime[content.type] {
            let minInterval = TimeInterval(settings.repeatInterval * 60)
            guard Date().timeIntervalSince(last) >= minInterval else { return }
        }
        
        #if canImport(UserNotifications)
        let request = createNotificationRequest(from: content)
        
        do {
            try await notificationCenter.add(request)
            lock.withLock {
                lastNotificationTime[content.type] = Date()
            }
        } catch {
            // Log error silently
        }
        #endif
    }
    
    /// Schedule a notification for a specific time
    public func scheduleNotification(_ content: GlucoseNotificationContent, at date: Date) async {
        #if canImport(UserNotifications)
        let request = createNotificationRequest(from: content, triggerDate: date)
        
        do {
            try await notificationCenter.add(request)
        } catch {
            // Log error silently
        }
        #endif
    }
    
    // MARK: - Cancel Notifications
    
    /// Cancel all pending notifications
    public func cancelAllPending() {
        #if canImport(UserNotifications)
        notificationCenter.removeAllPendingNotificationRequests()
        #endif
    }
    
    /// Cancel notifications of a specific type
    public func cancelNotifications(of type: GlucoseNotificationType) {
        #if canImport(UserNotifications)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [type.rawValue])
        #endif
    }
    
    // MARK: - Snooze
    
    /// Snooze a notification type
    public func snooze(_ type: GlucoseNotificationType, duration: Int? = nil) {
        let minutes = duration ?? settings.snoozeDuration
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        
        lock.withLock {
            snoozedTypes[type] = until
        }
        
        cancelNotifications(of: type)
    }
    
    /// Unsnooze a notification type
    public func unsnooze(_ type: GlucoseNotificationType) {
        _ = lock.withLock {
            snoozedTypes.removeValue(forKey: type)
        }
    }
    
    /// Check if a type is currently snoozed
    public func isSnoozed(_ type: GlucoseNotificationType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let until = snoozedTypes[type] else { return false }
        if Date() >= until {
            snoozedTypes.removeValue(forKey: type)
            return false
        }
        return true
    }
    
    /// Get remaining snooze time in seconds
    public func snoozeRemaining(_ type: GlucoseNotificationType) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let until = snoozedTypes[type] else { return nil }
        let remaining = until.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
    
    // MARK: - Private Helpers
    
    #if canImport(UserNotifications)
    private func createNotificationRequest(
        from content: GlucoseNotificationContent,
        triggerDate: Date? = nil
    ) -> UNNotificationRequest {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.categoryIdentifier = content.type.categoryIdentifier
        
        // Add user info
        var userInfo = content.userInfo
        userInfo["type"] = content.type.rawValue
        if let glucose = content.glucoseValue {
            userInfo["glucose"] = String(glucose)
        }
        if let trend = content.trend {
            userInfo["trend"] = trend
        }
        notificationContent.userInfo = userInfo
        
        // LIFE-NOTIFY-003: Use AlertSoundManager for custom sound configuration
        if let alertSoundType = AlertSoundType.from(notificationType: content.type) {
            let config = AlertSoundManager.shared.configuration(for: alertSoundType)
            
            if config.isEnabled {
                if let customSoundName = config.customSoundName, !config.useSystemSound {
                    // Use custom sound
                    let soundName = UNNotificationSoundName(customSoundName)
                    if content.type.isCritical {
                        notificationContent.sound = .criticalSoundNamed(soundName)
                    } else {
                        notificationContent.sound = .init(named: soundName)
                    }
                } else if let defaultSound = content.type.soundName {
                    // Use type-specific default sound
                    if content.type.isCritical {
                        notificationContent.sound = .criticalSoundNamed(UNNotificationSoundName(defaultSound))
                    } else {
                        notificationContent.sound = .init(named: UNNotificationSoundName(defaultSound))
                    }
                } else {
                    notificationContent.sound = .default
                }
            }
            // If not enabled, no sound is set
        } else if let soundName = content.type.soundName {
            // Fallback: Use type's default sound
            if content.type.isCritical {
                notificationContent.sound = .criticalSoundNamed(UNNotificationSoundName(soundName))
            } else {
                notificationContent.sound = .init(named: UNNotificationSoundName(soundName))
            }
        } else {
            notificationContent.sound = .default
        }
        
        // Set interruption level (iOS 15+)
        if #available(iOS 15.0, *) {
            switch content.type.interruptionLevel {
            case .passive:
                notificationContent.interruptionLevel = .passive
            case .active:
                notificationContent.interruptionLevel = .active
            case .timeSensitive:
                notificationContent.interruptionLevel = .timeSensitive
            case .critical:
                notificationContent.interruptionLevel = .critical
            }
        }
        
        // Create trigger
        var trigger: UNNotificationTrigger?
        if let date = triggerDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        
        return UNNotificationRequest(
            identifier: "\(content.type.rawValue).\(UUID().uuidString)",
            content: notificationContent,
            trigger: trigger
        )
    }
    #endif
}

// MARK: - Authorization Status

/// Notification authorization status
public enum NotificationAuthorizationStatus: Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unavailable
}

// MARK: - Glucose Notification Helpers

extension NotificationService {
    
    /// Create notification for low glucose
    public func notifyLowGlucose(value: Double, isUrgent: Bool) async {
        let type: GlucoseNotificationType = isUrgent ? .urgentLow : .low
        let title = isUrgent ? "⚠️ Urgent Low" : "Low Glucose"
        let body = String(format: "%.0f mg/dL - Take action", value)
        
        let content = GlucoseNotificationContent(
            type: type,
            title: title,
            body: body,
            glucoseValue: value
        )
        
        await scheduleNotification(content)
    }
    
    /// Create notification for high glucose
    public func notifyHighGlucose(value: Double, isUrgent: Bool) async {
        let type: GlucoseNotificationType = isUrgent ? .urgentHigh : .high
        let title = isUrgent ? "⚠️ Urgent High" : "High Glucose"
        let body = String(format: "%.0f mg/dL", value)
        
        let content = GlucoseNotificationContent(
            type: type,
            title: title,
            body: body,
            glucoseValue: value
        )
        
        await scheduleNotification(content)
    }
    
    /// Create notification for stale data
    public func notifyStaleData(lastReading: Date) async {
        let minutes = Int(Date().timeIntervalSince(lastReading) / 60)
        let title = "No Recent Data"
        let body = "Last reading was \(minutes) minutes ago"
        
        let content = GlucoseNotificationContent(
            type: .staleData,
            title: title,
            body: body,
            timestamp: lastReading
        )
        
        await scheduleNotification(content)
    }
}

// MARK: - Pump Type Enumeration (LIFE-NOTIFY-001)

/// Supported pump types for lifecycle notifications
public enum PumpType: String, CaseIterable, Sendable {
    case omnipodDash = "Omnipod DASH"
    case omnipodEros = "Omnipod Eros"
    case medtronicMini = "Medtronic"
    case tandem = "Tandem t:slim"
    case dana = "Dana"
    case generic = "Pump"
    
    /// User-friendly device name for notifications
    public var deviceName: String {
        rawValue
    }
    
    /// Consumable name (pod/cartridge/reservoir)
    public var consumableName: String {
        switch self {
        case .omnipodDash, .omnipodEros:
            return "pod"
        case .medtronicMini, .dana:
            return "reservoir"
        case .tandem:
            return "cartridge"
        case .generic:
            return "consumable"
        }
    }
    
    /// Action verb for replacement
    public var changeVerb: String {
        switch self {
        case .omnipodDash, .omnipodEros:
            return "change"
        case .medtronicMini, .dana, .tandem:
            return "refill"
        case .generic:
            return "replace"
        }
    }
}

// MARK: - Lifecycle Notification Content (LIFE-NOTIFY-001)

/// Content for lifecycle-related notifications with idiomatic text
public struct LifecycleNotificationContent: Sendable {
    public let type: GlucoseNotificationType
    public let pumpType: PumpType
    public let title: String
    public let body: String
    public let hoursRemaining: Double?
    public let unitsRemaining: Double?
    public let batteryPercent: Double?
    public let scheduledTime: Date?
    
    public init(
        type: GlucoseNotificationType,
        pumpType: PumpType,
        title: String,
        body: String,
        hoursRemaining: Double? = nil,
        unitsRemaining: Double? = nil,
        batteryPercent: Double? = nil,
        scheduledTime: Date? = nil
    ) {
        self.type = type
        self.pumpType = pumpType
        self.title = title
        self.body = body
        self.hoursRemaining = hoursRemaining
        self.unitsRemaining = unitsRemaining
        self.batteryPercent = batteryPercent
        self.scheduledTime = scheduledTime
    }
    
    /// Convert to GlucoseNotificationContent for scheduling
    public func toGlucoseNotificationContent() -> GlucoseNotificationContent {
        var userInfo: [String: String] = ["pumpType": pumpType.rawValue]
        if let hours = hoursRemaining {
            userInfo["hoursRemaining"] = String(format: "%.1f", hours)
        }
        if let units = unitsRemaining {
            userInfo["unitsRemaining"] = String(format: "%.1f", units)
        }
        if let battery = batteryPercent {
            userInfo["batteryPercent"] = String(format: "%.0f", battery * 100)
        }
        
        return GlucoseNotificationContent(
            type: type,
            title: title,
            body: body,
            userInfo: userInfo
        )
    }
}

// MARK: - Lifecycle Notification Factory (LIFE-NOTIFY-001)

/// Factory for creating idiomatic lifecycle notification content
public enum LifecycleNotificationFactory {
    
    // MARK: - Pod Expiration Notifications
    
    /// Create pod expiring notification with idiomatic text
    public static func podExpiring(
        pumpType: PumpType,
        hoursRemaining: Double,
        isGracePeriod: Bool = false
    ) -> LifecycleNotificationContent {
        let consumable = pumpType.consumableName.capitalized
        let title: String
        let body: String
        
        if isGracePeriod {
            title = "⚠️ \(consumable) Grace Period"
            body = "Your \(pumpType.deviceName) \(pumpType.consumableName) has expired. You have \(formatHours(hoursRemaining)) remaining in grace period. \(pumpType.changeVerb.capitalized) your \(pumpType.consumableName) soon."
        } else if hoursRemaining <= 1 {
            title = "🔴 \(consumable) Expiring Soon"
            body = "Your \(pumpType.deviceName) \(pumpType.consumableName) expires in less than 1 hour. Prepare to \(pumpType.changeVerb) your \(pumpType.consumableName)."
        } else if hoursRemaining <= 4 {
            title = "🟠 \(consumable) Expiring"
            body = "Your \(pumpType.deviceName) \(pumpType.consumableName) expires in \(formatHours(hoursRemaining)). Plan to \(pumpType.changeVerb) your \(pumpType.consumableName) soon."
        } else if hoursRemaining <= 8 {
            title = "🟡 \(consumable) Reminder"
            body = "Your \(pumpType.deviceName) \(pumpType.consumableName) expires in \(formatHours(hoursRemaining)). Consider having a new \(pumpType.consumableName) ready."
        } else {
            title = "\(consumable) Update"
            body = "Your \(pumpType.deviceName) \(pumpType.consumableName) has \(formatHours(hoursRemaining)) remaining."
        }
        
        return LifecycleNotificationContent(
            type: .podExpiring,
            pumpType: pumpType,
            title: title,
            body: body,
            hoursRemaining: hoursRemaining
        )
    }
    
    /// Create pod expired notification
    public static func podExpired(pumpType: PumpType) -> LifecycleNotificationContent {
        let consumable = pumpType.consumableName.capitalized
        
        return LifecycleNotificationContent(
            type: .podExpired,
            pumpType: pumpType,
            title: "🛑 \(consumable) Expired",
            body: "Your \(pumpType.deviceName) \(pumpType.consumableName) has expired. Insulin delivery has stopped. \(pumpType.changeVerb.capitalized) your \(pumpType.consumableName) immediately."
        )
    }
    
    // MARK: - Reservoir Notifications
    
    /// Create reservoir low notification with idiomatic text
    public static func reservoirLow(
        pumpType: PumpType,
        unitsRemaining: Double
    ) -> LifecycleNotificationContent {
        let consumable = pumpType.consumableName.capitalized
        let title: String
        let body: String
        
        if unitsRemaining <= 10 {
            title = "🔴 \(consumable) Very Low"
            body = "Your \(pumpType.deviceName) has only \(formatUnits(unitsRemaining)) remaining. \(pumpType.changeVerb.capitalized) your \(pumpType.consumableName) soon to avoid interruption."
        } else if unitsRemaining <= 20 {
            title = "🟠 \(consumable) Low"
            body = "Your \(pumpType.deviceName) has \(formatUnits(unitsRemaining)) remaining. Prepare to \(pumpType.changeVerb) your \(pumpType.consumableName)."
        } else {
            title = "🟡 \(consumable) Reminder"
            body = "Your \(pumpType.deviceName) has \(formatUnits(unitsRemaining)) remaining. Consider having supplies ready."
        }
        
        return LifecycleNotificationContent(
            type: .reservoirLow,
            pumpType: pumpType,
            title: title,
            body: body,
            unitsRemaining: unitsRemaining
        )
    }
    
    /// Create reservoir empty notification
    public static func reservoirEmpty(pumpType: PumpType) -> LifecycleNotificationContent {
        let consumable = pumpType.consumableName.capitalized
        
        return LifecycleNotificationContent(
            type: .reservoirLow,
            pumpType: pumpType,
            title: "🛑 \(consumable) Empty",
            body: "Your \(pumpType.deviceName) \(pumpType.consumableName) is empty. Insulin delivery has stopped. \(pumpType.changeVerb.capitalized) immediately."
        )
    }
    
    // MARK: - Battery Notifications
    
    /// Create pump battery low notification with idiomatic text
    public static func batteryLow(
        pumpType: PumpType,
        batteryPercent: Double
    ) -> LifecycleNotificationContent {
        let title: String
        let body: String
        let percentText = String(format: "%.0f%%", batteryPercent * 100)
        
        if batteryPercent <= 0.05 {
            title = "🔴 Battery Critical"
            body = "Your \(pumpType.deviceName) battery is critically low (\(percentText)). Charge or replace immediately to avoid delivery interruption."
        } else if batteryPercent <= 0.10 {
            title = "🟠 Battery Very Low"
            body = "Your \(pumpType.deviceName) battery is very low (\(percentText)). Charge or replace soon."
        } else {
            title = "🟡 Battery Low"
            body = "Your \(pumpType.deviceName) battery is at \(percentText). Consider charging or replacing soon."
        }
        
        return LifecycleNotificationContent(
            type: .pumpBatteryLow,
            pumpType: pumpType,
            title: title,
            body: body,
            batteryPercent: batteryPercent
        )
    }
    
    // MARK: - Helpers
    
    private static func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            let minutes = Int(hours * 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if hours < 24 {
            let h = Int(hours)
            return "\(h) hour\(h == 1 ? "" : "s")"
        } else {
            let days = hours / 24
            if days < 2 {
                let h = Int(hours)
                return "\(h) hours"
            } else {
                let d = Int(days)
                return "\(d) day\(d == 1 ? "" : "s")"
            }
        }
    }
    
    private static func formatUnits(_ units: Double) -> String {
        if units < 10 {
            return String(format: "%.1f units", units)
        } else {
            return String(format: "%.0f units", units)
        }
    }
}

// MARK: - Lifecycle Notification Scheduling (LIFE-NOTIFY-004)

/// Advance warning times for lifecycle notifications
public struct LifecycleWarningSchedule: Sendable {
    /// Warning times before expiration (in hours)
    public let advanceWarnings: [Double]
    /// Whether to send final warning at expiration
    public let notifyAtExpiration: Bool
    /// Whether to send grace period reminders
    public let gracePeriodReminders: Bool
    
    public init(
        advanceWarnings: [Double] = [24, 8, 4, 1],
        notifyAtExpiration: Bool = true,
        gracePeriodReminders: Bool = true
    ) {
        self.advanceWarnings = advanceWarnings
        self.notifyAtExpiration = notifyAtExpiration
        self.gracePeriodReminders = gracePeriodReminders
    }
    
    /// Default schedule for pod lifecycle (80h active + 8h grace)
    public static let pod = LifecycleWarningSchedule(
        advanceWarnings: [24, 8, 4, 1],
        notifyAtExpiration: true,
        gracePeriodReminders: true
    )
    
    /// Schedule for reservoir monitoring
    public static let reservoir = LifecycleWarningSchedule(
        advanceWarnings: [], // Reservoir uses unit thresholds, not time
        notifyAtExpiration: false,
        gracePeriodReminders: false
    )
}

// MARK: - Lifecycle Notification Scheduler (LIFE-NOTIFY-004)

/// Scheduler for advance lifecycle notifications
public actor LifecycleNotificationScheduler {
    private let notificationService: NotificationService
    private var scheduledNotifications: [String: Date] = [:]
    
    public init(notificationService: NotificationService = .shared) {
        self.notificationService = notificationService
    }
    
    /// Schedule advance warnings for pod expiration
    public func schedulePodExpirationWarnings(
        pumpType: PumpType,
        expirationDate: Date,
        schedule: LifecycleWarningSchedule = .pod
    ) async {
        let now = Date()
        
        // Cancel any existing scheduled notifications for this pump type
        await cancelScheduledNotifications(for: pumpType)
        
        // Schedule advance warnings
        for hoursBeforeExpiration in schedule.advanceWarnings {
            let warningDate = expirationDate.addingTimeInterval(-hoursBeforeExpiration * 3600)
            
            // Only schedule if warning time is in the future
            guard warningDate > now else { continue }
            
            let hoursRemaining = hoursBeforeExpiration
            let content = LifecycleNotificationFactory.podExpiring(
                pumpType: pumpType,
                hoursRemaining: hoursRemaining
            )
            
            await scheduleLifecycleNotification(content, at: warningDate)
            
            let key = "\(pumpType.rawValue).podExpiring.\(Int(hoursBeforeExpiration))"
            scheduledNotifications[key] = warningDate
        }
        
        // Schedule expiration notification
        if schedule.notifyAtExpiration && expirationDate > now {
            let content = LifecycleNotificationFactory.podExpired(pumpType: pumpType)
            await scheduleLifecycleNotification(content, at: expirationDate)
            
            let key = "\(pumpType.rawValue).podExpired"
            scheduledNotifications[key] = expirationDate
        }
    }
    
    /// Schedule a single lifecycle notification at a specific time
    public func scheduleLifecycleNotification(
        _ content: LifecycleNotificationContent,
        at date: Date
    ) async {
        let glucoseContent = content.toGlucoseNotificationContent()
        await notificationService.scheduleNotification(glucoseContent, at: date)
    }
    
    /// Cancel all scheduled notifications for a pump type
    public func cancelScheduledNotifications(for pumpType: PumpType) async {
        // Remove all notifications with this pump type prefix
        let keysToRemove = scheduledNotifications.keys.filter { $0.hasPrefix(pumpType.rawValue) }
        for key in keysToRemove {
            scheduledNotifications.removeValue(forKey: key)
        }
        
        // Cancel from notification center
        #if canImport(UserNotifications)
        let identifiersToCancel = [
            "\(pumpType.rawValue).podExpiring",
            "\(pumpType.rawValue).podExpired"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        #endif
    }
    
    /// Get scheduled notification times for a pump type
    public func getScheduledTimes(for pumpType: PumpType) -> [String: Date] {
        scheduledNotifications.filter { $0.key.hasPrefix(pumpType.rawValue) }
    }
    
    /// Update schedule when pod is activated
    public func onPodActivated(
        pumpType: PumpType,
        activationDate: Date,
        lifetimeHours: Double = 80
    ) async {
        let expirationDate = activationDate.addingTimeInterval(lifetimeHours * 3600)
        await schedulePodExpirationWarnings(pumpType: pumpType, expirationDate: expirationDate)
    }
    
    /// Clear all schedules when pod is deactivated
    public func onPodDeactivated(pumpType: PumpType) async {
        await cancelScheduledNotifications(for: pumpType)
    }
}

// MARK: - NotificationService Lifecycle Extension (LIFE-NOTIFY-001, LIFE-NOTIFY-004)

extension NotificationService {
    
    /// Send pod expiring notification immediately
    public func notifyPodExpiring(pumpType: PumpType, hoursRemaining: Double, isGracePeriod: Bool = false) async {
        let content = LifecycleNotificationFactory.podExpiring(
            pumpType: pumpType,
            hoursRemaining: hoursRemaining,
            isGracePeriod: isGracePeriod
        )
        await scheduleNotification(content.toGlucoseNotificationContent())
    }
    
    /// Send pod expired notification immediately
    public func notifyPodExpired(pumpType: PumpType) async {
        let content = LifecycleNotificationFactory.podExpired(pumpType: pumpType)
        await scheduleNotification(content.toGlucoseNotificationContent())
    }
    
    /// Send reservoir low notification immediately
    public func notifyReservoirLow(pumpType: PumpType, unitsRemaining: Double) async {
        let content = LifecycleNotificationFactory.reservoirLow(
            pumpType: pumpType,
            unitsRemaining: unitsRemaining
        )
        await scheduleNotification(content.toGlucoseNotificationContent())
    }
    
    /// Send reservoir empty notification immediately
    public func notifyReservoirEmpty(pumpType: PumpType) async {
        let content = LifecycleNotificationFactory.reservoirEmpty(pumpType: pumpType)
        await scheduleNotification(content.toGlucoseNotificationContent())
    }
    
    /// Send battery low notification immediately
    public func notifyBatteryLow(pumpType: PumpType, batteryPercent: Double) async {
        let content = LifecycleNotificationFactory.batteryLow(
            pumpType: pumpType,
            batteryPercent: batteryPercent
        )
        await scheduleNotification(content.toGlucoseNotificationContent())
    }
}

// MARK: - Snooze Duration Options (LIFE-NOTIFY-005)

/// Available snooze duration options for lifecycle notifications
public enum SnoozeDuration: Int, CaseIterable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240
    
    /// Human-readable display text
    public var displayText: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        }
    }
    
    /// Short display text for buttons
    public var shortText: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        }
    }
    
    /// Duration in seconds
    public var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
    
    /// Default snooze durations for lifecycle alerts
    public static let lifecycleDefaults: [SnoozeDuration] = [.fifteenMinutes, .thirtyMinutes, .oneHour, .fourHours]
}

// MARK: - Lifecycle Snooze State (LIFE-NOTIFY-005)

/// Tracks snooze state for lifecycle notifications
public actor LifecycleSnoozeManager {
    private var snoozedAlerts: [String: Date] = [:]
    private let notificationService: NotificationService
    
    public init(notificationService: NotificationService = .shared) {
        self.notificationService = notificationService
    }
    
    /// Snooze a lifecycle notification type for a specific pump
    /// Returns false if the notification type cannot be snoozed (critical)
    public func snooze(
        type: GlucoseNotificationType,
        pumpType: PumpType,
        duration: SnoozeDuration
    ) -> Bool {
        // Critical notifications cannot be snoozed
        guard type.isSnoozeable else {
            return false
        }
        
        let key = makeKey(type: type, pumpType: pumpType)
        let until = Date().addingTimeInterval(duration.seconds)
        snoozedAlerts[key] = until
        
        // Also snooze in the notification service
        notificationService.snooze(type, duration: duration.rawValue)
        
        return true
    }
    
    /// Unsnooze a lifecycle notification
    public func unsnooze(type: GlucoseNotificationType, pumpType: PumpType) {
        let key = makeKey(type: type, pumpType: pumpType)
        snoozedAlerts.removeValue(forKey: key)
        notificationService.unsnooze(type)
    }
    
    /// Check if a lifecycle notification is snoozed
    public func isSnoozed(type: GlucoseNotificationType, pumpType: PumpType) -> Bool {
        let key = makeKey(type: type, pumpType: pumpType)
        guard let until = snoozedAlerts[key] else { return false }
        
        if Date() >= until {
            snoozedAlerts.removeValue(forKey: key)
            return false
        }
        return true
    }
    
    /// Get remaining snooze time
    public func snoozeRemaining(type: GlucoseNotificationType, pumpType: PumpType) -> TimeInterval? {
        let key = makeKey(type: type, pumpType: pumpType)
        guard let until = snoozedAlerts[key] else { return nil }
        
        let remaining = until.timeIntervalSinceNow
        if remaining <= 0 {
            snoozedAlerts.removeValue(forKey: key)
            return nil
        }
        return remaining
    }
    
    /// Get all currently snoozed alerts
    public func snoozedAlertKeys() -> [String] {
        // Clean up expired snoozes first
        let now = Date()
        snoozedAlerts = snoozedAlerts.filter { $0.value > now }
        return Array(snoozedAlerts.keys)
    }
    
    /// Clear all snoozes
    public func clearAllSnoozes() {
        snoozedAlerts.removeAll()
    }
    
    private func makeKey(type: GlucoseNotificationType, pumpType: PumpType) -> String {
        "\(pumpType.rawValue).\(type.rawValue)"
    }
}

// MARK: - NotificationService Snooze Extension (LIFE-NOTIFY-005)

extension NotificationService {
    
    /// Snooze a lifecycle notification with a specific duration
    /// Returns false if notification type cannot be snoozed
    public func snoozeLifecycleAlert(
        type: GlucoseNotificationType,
        duration: SnoozeDuration
    ) -> Bool {
        guard type.isSnoozeable else {
            return false
        }
        
        snooze(type, duration: duration.rawValue)
        return true
    }
    
    /// Check if a notification can be snoozed
    public func canSnooze(_ type: GlucoseNotificationType) -> Bool {
        type.isSnoozeable
    }
    
    /// Get available snooze options for a notification type
    public func snoozeOptions(for type: GlucoseNotificationType) -> [SnoozeDuration] {
        guard type.isSnoozeable else {
            return []
        }
        return SnoozeDuration.lifecycleDefaults
    }
}

// MARK: - Notification Action Identifiers (LIFE-NOTIFY-005)

/// Action identifiers for notification interactions
public enum LifecycleNotificationAction: String, Sendable {
    case snooze15 = "SNOOZE_15"
    case snooze30 = "SNOOZE_30"
    case snooze60 = "SNOOZE_60"
    case snooze240 = "SNOOZE_240"
    case acknowledge = "ACKNOWLEDGE"
    case openApp = "OPEN_APP"
    
    /// Convert to SnoozeDuration if applicable
    public var snoozeDuration: SnoozeDuration? {
        switch self {
        case .snooze15: return .fifteenMinutes
        case .snooze30: return .thirtyMinutes
        case .snooze60: return .oneHour
        case .snooze240: return .fourHours
        case .acknowledge, .openApp: return nil
        }
    }
    
    /// Display title for the action button
    public var title: String {
        switch self {
        case .snooze15: return "Snooze 15m"
        case .snooze30: return "Snooze 30m"
        case .snooze60: return "Snooze 1h"
        case .snooze240: return "Snooze 4h"
        case .acknowledge: return "OK"
        case .openApp: return "Open App"
        }
    }
}

/// Category identifiers for notification categories with actions
public enum LifecycleNotificationCategory: String, Sendable {
    case lifecycleSnoozeable = "LIFECYCLE_SNOOZEABLE"
    case lifecycleCritical = "LIFECYCLE_CRITICAL"
    
    /// Get category for a notification type
    public static func category(for type: GlucoseNotificationType) -> LifecycleNotificationCategory {
        type.isSnoozeable ? .lifecycleSnoozeable : .lifecycleCritical
    }
}

#if canImport(UserNotifications)
@preconcurrency import UserNotifications

extension NotificationService {
    
    /// Register notification categories with snooze actions (LIFE-NOTIFY-005)
    /// Call this during app initialization
    public func registerLifecycleNotificationCategories() {
        let snooze15 = UNNotificationAction(
            identifier: LifecycleNotificationAction.snooze15.rawValue,
            title: LifecycleNotificationAction.snooze15.title,
            options: []
        )
        let snooze30 = UNNotificationAction(
            identifier: LifecycleNotificationAction.snooze30.rawValue,
            title: LifecycleNotificationAction.snooze30.title,
            options: []
        )
        let snooze60 = UNNotificationAction(
            identifier: LifecycleNotificationAction.snooze60.rawValue,
            title: LifecycleNotificationAction.snooze60.title,
            options: []
        )
        let snooze240 = UNNotificationAction(
            identifier: LifecycleNotificationAction.snooze240.rawValue,
            title: LifecycleNotificationAction.snooze240.title,
            options: []
        )
        let acknowledge = UNNotificationAction(
            identifier: LifecycleNotificationAction.acknowledge.rawValue,
            title: LifecycleNotificationAction.acknowledge.title,
            options: .authenticationRequired
        )
        let openApp = UNNotificationAction(
            identifier: LifecycleNotificationAction.openApp.rawValue,
            title: LifecycleNotificationAction.openApp.title,
            options: .foreground
        )
        
        // Snoozeable category with snooze options
        let snoozeableCategory = UNNotificationCategory(
            identifier: LifecycleNotificationCategory.lifecycleSnoozeable.rawValue,
            actions: [snooze15, snooze30, snooze60, snooze240, openApp],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Critical category without snooze (only acknowledge)
        let criticalCategory = UNNotificationCategory(
            identifier: LifecycleNotificationCategory.lifecycleCritical.rawValue,
            actions: [acknowledge, openApp],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            snoozeableCategory,
            criticalCategory
        ])
    }
    
    /// Handle a notification action response
    /// Returns the snooze duration if a snooze action was selected
    public func handleNotificationAction(
        _ actionIdentifier: String,
        for notificationType: GlucoseNotificationType
    ) -> SnoozeDuration? {
        guard let action = LifecycleNotificationAction(rawValue: actionIdentifier),
              let duration = action.snoozeDuration else {
            return nil
        }
        
        // Apply the snooze
        _ = snoozeLifecycleAlert(type: notificationType, duration: duration)
        return duration
    }
}
#endif
