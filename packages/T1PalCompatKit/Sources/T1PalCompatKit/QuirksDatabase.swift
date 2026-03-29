// SPDX-License-Identifier: AGPL-3.0-or-later
//
// QuirksDatabase.swift
// T1PalCompatKit
//
// Known iOS platform quirks database from ecosystem analysis.
// Trace: PRD-006 REQ-COMPAT-005
//
// Source: docs/reference/ios-platform-quirks.md
// Data: Loop, Trio, DiaBLE, xDrip4iOS GitHub issues

import Foundation

// MARK: - Quirk Category

/// Categories of platform quirks
public enum QuirkCategory: String, Codable, Sendable, CaseIterable {
    case bluetooth = "bluetooth"
    case notification = "notification"
    case healthkit = "healthkit"
    case watch = "watch"
    case widget = "widget"
    case nfc = "nfc"
    case general = "general"
    
    public var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .notification: return "Notifications"
        case .healthkit: return "HealthKit"
        case .watch: return "Apple Watch"
        case .widget: return "Widgets"
        case .nfc: return "NFC"
        case .general: return "General iOS"
        }
    }
}

// MARK: - iOS Version Range

/// Represents a range of iOS versions affected by a quirk
public struct IOSVersionRange: Codable, Sendable {
    public let minVersion: String?
    public let maxVersion: String?
    
    public init(min: String? = nil, max: String? = nil) {
        self.minVersion = min
        self.maxVersion = max
    }
    
    /// Check if a version string falls within this range
    public func contains(_ version: String) -> Bool {
        let current = parseVersion(version)
        
        if let min = minVersion {
            let minParsed = parseVersion(min)
            if compareVersions(current, minParsed) < 0 { return false }
        }
        
        if let max = maxVersion {
            let maxParsed = parseVersion(max)
            if compareVersions(current, maxParsed) > 0 { return false }
        }
        
        return true
    }
    
    private func parseVersion(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
    
    /// Compare two version arrays. Returns -1, 0, or 1.
    private func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
        let maxLen = max(a.count, b.count)
        for i in 0..<maxLen {
            let aVal = i < a.count ? a[i] : 0
            let bVal = i < b.count ? b[i] : 0
            if aVal < bVal { return -1 }
            if aVal > bVal { return 1 }
        }
        return 0
    }
    
    public var description: String {
        switch (minVersion, maxVersion) {
        case (nil, nil): return "All versions"
        case (let min?, nil): return "\(min)+"
        case (nil, let max?): return "Up to \(max)"
        case (let min?, let max?): return "\(min) - \(max)"
        }
    }
    
    // Common ranges
    public static let all = IOSVersionRange()
    public static let ios15 = IOSVersionRange(min: "15.0", max: "15.99")
    public static let ios16 = IOSVersionRange(min: "16.0", max: "16.99")
    public static let ios17 = IOSVersionRange(min: "17.0", max: "17.99")
    public static let ios15Plus = IOSVersionRange(min: "15.0")
    public static let ios16Plus = IOSVersionRange(min: "16.0")
    public static let ios17Plus = IOSVersionRange(min: "17.0")
}

// MARK: - Quirk Severity

/// How severe is the quirk's impact
public enum QuirkSeverity: String, Codable, Sendable {
    case critical = "critical"   // Can cause safety issues
    case high = "high"           // Significantly degrades experience
    case medium = "medium"       // Noticeable but manageable
    case low = "low"             // Minor inconvenience
}

// MARK: - Quirk

/// A known platform quirk
public struct Quirk: Codable, Sendable, Identifiable {
    public let id: String
    public let category: QuirkCategory
    public let title: String
    public let description: String
    public let affectedVersions: IOSVersionRange
    public let severity: QuirkSeverity
    public let symptoms: [String]
    public let workarounds: [String]
    public let sourceReferences: [String]
    
    public init(
        id: String,
        category: QuirkCategory,
        title: String,
        description: String,
        affectedVersions: IOSVersionRange = .all,
        severity: QuirkSeverity = .medium,
        symptoms: [String] = [],
        workarounds: [String] = [],
        sourceReferences: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.description = description
        self.affectedVersions = affectedVersions
        self.severity = severity
        self.symptoms = symptoms
        self.workarounds = workarounds
        self.sourceReferences = sourceReferences
    }
    
    /// Check if this quirk applies to the given iOS version
    public func applies(toVersion version: String) -> Bool {
        affectedVersions.contains(version)
    }
}

// MARK: - Quirks Registry

/// Registry of all known platform quirks
public struct QuirksRegistry: Sendable {
    /// All registered quirks
    public let quirks: [Quirk]
    
    /// Shared instance with all built-in quirks
    public static let shared = QuirksRegistry(quirks: allQuirks)
    
    public init(quirks: [Quirk]) {
        self.quirks = quirks
    }
    
    /// Get quirks by category
    public func quirks(in category: QuirkCategory) -> [Quirk] {
        quirks.filter { $0.category == category }
    }
    
    /// Get quirks that apply to a specific iOS version
    public func quirks(forVersion version: String) -> [Quirk] {
        quirks.filter { $0.applies(toVersion: version) }
    }
    
    /// Get quirks by severity
    public func quirks(severity: QuirkSeverity) -> [Quirk] {
        quirks.filter { $0.severity == severity }
    }
    
    /// Get a specific quirk by ID
    public func quirk(id: String) -> Quirk? {
        quirks.first { $0.id == id }
    }
    
    /// Count of quirks by category
    public var countByCategory: [QuirkCategory: Int] {
        Dictionary(grouping: quirks, by: { $0.category })
            .mapValues { $0.count }
    }
}

// MARK: - Built-in Quirks Database

/// All known quirks from ecosystem analysis
private let allQuirks: [Quirk] = [
    // MARK: Bluetooth Quirks
    Quirk(
        id: "QUIRK-BLE-001",
        category: .bluetooth,
        title: "Background Scan Delay",
        description: "Background BLE scan callbacks delayed up to 30 seconds vs ~10 seconds in iOS 16.",
        affectedVersions: IOSVersionRange(min: "17.0", max: "17.1"),
        severity: .high,
        symptoms: ["Delayed glucose readings when app is backgrounded"],
        workarounds: [
            "Extend scan timeout to 45+ seconds",
            "Use CBCentralManagerOptionRestoreIdentifierKey for state restoration",
            "Request processing background task during scans"
        ],
        sourceReferences: ["Loop #2145", "Trio #892"]
    ),
    Quirk(
        id: "QUIRK-BLE-002",
        category: .bluetooth,
        title: "Bond Loss After iOS Update",
        description: "Bluetooth bonds occasionally lost during iOS upgrade, requiring re-pairing.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["CGM connection fails after iOS update", "Pairing failed errors"],
        workarounds: [
            "Detect bond state on connection",
            "Guide user through re-pairing flow",
            "Store transmitter ID separately from bond state"
        ],
        sourceReferences: ["xDrip4iOS #234", "Loop #1876"]
    ),
    Quirk(
        id: "QUIRK-BLE-003",
        category: .bluetooth,
        title: "Multiple App BLE Conflicts",
        description: "Only one app can maintain BLE connection to a Dexcom transmitter.",
        affectedVersions: .all,
        severity: .critical,
        symptoms: ["Connection fails when another CGM app is active"],
        workarounds: [
            "Detect if connection is refused (error code 7)",
            "Guide user to close other CGM apps",
            "Implement graceful handoff where possible"
        ],
        sourceReferences: ["DiaBLE #89", "Loop #1234"]
    ),
    Quirk(
        id: "QUIRK-BLE-004",
        category: .bluetooth,
        title: "Low Power Mode BLE Throttling",
        description: "BLE scan intervals increased, callbacks delayed in Low Power Mode.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Increased latency in glucose readings"],
        workarounds: [
            "Detect Low Power Mode state",
            "Show warning to user",
            "Increase scan/connection timeouts"
        ],
        sourceReferences: ["Trio #567"]
    ),
    Quirk(
        id: "QUIRK-BLE-005",
        category: .bluetooth,
        title: "Central Manager State Restoration Failure",
        description: "willRestoreState not called after app termination in some cases.",
        affectedVersions: IOSVersionRange(min: "15.0", max: "15.4"),
        severity: .high,
        symptoms: ["BLE connection not restored after app killed by system"],
        workarounds: [
            "Always attempt fresh scan if restoration fails",
            "Implement connection watchdog timer",
            "Re-scan periodically even when connected"
        ],
        sourceReferences: ["Loop #2034"]
    ),
    
    // MARK: Notification Quirks
    Quirk(
        id: "QUIRK-NOTIF-001",
        category: .notification,
        title: "Critical Alert Entitlement Approval Delay",
        description: "Apple approval for critical alerts can take 2-4 weeks.",
        affectedVersions: .all,
        severity: .high,
        symptoms: ["App cannot bypass DND for urgent glucose alerts"],
        workarounds: [
            "Apply for entitlement early in development",
            "Use time sensitive notifications as fallback",
            "Implement in-app alarm with audio session"
        ],
        sourceReferences: ["Loop App Store submission experience"]
    ),
    Quirk(
        id: "QUIRK-NOTIF-002",
        category: .notification,
        title: "Custom Sound Duration Limit",
        description: "Custom notification sounds limited to 30 seconds max.",
        affectedVersions: .all,
        severity: .low,
        symptoms: ["Long alert sounds truncated"],
        workarounds: [
            "Keep sounds under 30 seconds",
            "Use repeating notifications for extended alerts",
            "Use audio session for longer alarms"
        ],
        sourceReferences: ["Apple documentation"]
    ),
    Quirk(
        id: "QUIRK-NOTIF-003",
        category: .notification,
        title: "Focus Mode Suppression",
        description: "Focus modes can suppress non-critical notifications.",
        affectedVersions: .ios15Plus,
        severity: .high,
        symptoms: ["Glucose alerts not delivered during Focus/DND"],
        workarounds: [
            "Use critical alerts (requires entitlement)",
            "Use time sensitive interruption level",
            "Educate users about Focus mode exceptions"
        ],
        sourceReferences: ["Loop #2156"]
    ),
    
    // MARK: HealthKit Quirks
    Quirk(
        id: "QUIRK-HK-001",
        category: .healthkit,
        title: "Authorization Dialog Changes",
        description: "HealthKit authorization dialog UI changed, confusing some users.",
        affectedVersions: .ios17Plus,
        severity: .low,
        symptoms: ["Users not granting proper permissions"],
        workarounds: [
            "Update onboarding screenshots",
            "Pre-explain what permissions are needed",
            "Verify permissions after authorization flow"
        ],
        sourceReferences: ["Multiple apps"]
    ),
    Quirk(
        id: "QUIRK-HK-002",
        category: .healthkit,
        title: "Background Delivery Unreliable",
        description: "enableBackgroundDelivery callbacks not guaranteed.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Missed glucose readings from other apps"],
        workarounds: [
            "Don't rely solely on background delivery",
            "Implement periodic polling as backup",
            "Use HKObserverQuery with HKAnchoredObjectQuery"
        ],
        sourceReferences: ["Loop #1567", "HealthKit documentation"]
    ),
    Quirk(
        id: "QUIRK-HK-003",
        category: .healthkit,
        title: "Duplicate Writes from Multiple Apps",
        description: "Multiple apps writing same glucose values create duplicates.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Inflated glucose counts", "Confused statistics"],
        workarounds: [
            "Check HKSource before writing",
            "Use deterministic UUIDs based on timestamp",
            "Query before write to detect duplicates"
        ],
        sourceReferences: ["HealthKit integration audit"]
    ),
    Quirk(
        id: "QUIRK-HK-004",
        category: .healthkit,
        title: "Workout Session Conflicts",
        description: "Only one app can have active workout session on Watch.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["CGM Watch app loses elevated heart rate permissions"],
        workarounds: [
            "Detect workout session state",
            "Gracefully handle session loss",
            "Prompt user if workout started by other app"
        ],
        sourceReferences: ["Loop Watch app #789"]
    ),
    
    // MARK: Watch Quirks
    Quirk(
        id: "QUIRK-WATCH-001",
        category: .watch,
        title: "Complication Update Budget",
        description: "Complication updates throttled to ~4 per hour.",
        affectedVersions: IOSVersionRange(min: "16.4"),
        severity: .high,
        symptoms: ["Stale glucose values on watch face"],
        workarounds: [
            "Batch updates efficiently",
            "Use CLKComplicationServer.sharedInstance().reloadComplication()",
            "Prioritize updates after significant changes"
        ],
        sourceReferences: ["Apple WWDC 2023", "Loop #2345"]
    ),
    Quirk(
        id: "QUIRK-WATCH-002",
        category: .watch,
        title: "WCSession Message Queue Limit",
        description: "Message queue limited; old messages dropped if not consumed.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Missed glucose updates on Watch"],
        workarounds: [
            "Use transferUserInfo for guaranteed delivery",
            "Implement message acknowledgment",
            "Send only latest value, not history"
        ],
        sourceReferences: ["Trio Watch implementation"]
    ),
    Quirk(
        id: "QUIRK-WATCH-003",
        category: .watch,
        title: "Watch App Background Termination",
        description: "Watch app terminated more aggressively in background.",
        affectedVersions: IOSVersionRange(min: "9.0"),  // watchOS 9+
        severity: .medium,
        symptoms: ["Watch app not receiving updates"],
        workarounds: [
            "Use complications as primary data display",
            "Implement WKExtendedRuntimeSession for critical operations",
            "Accept that Watch app may not be continuously running"
        ],
        sourceReferences: ["Loop Watch #456"]
    ),
    
    // MARK: Widget Quirks
    Quirk(
        id: "QUIRK-WIDGET-001",
        category: .widget,
        title: "Widget Timeline Refresh Limits",
        description: "System controls widget refresh frequency.",
        affectedVersions: IOSVersionRange(min: "14.0"),
        severity: .medium,
        symptoms: ["Widgets may show stale data (up to 15 min old)"],
        workarounds: [
            "Request timeline refresh after data changes",
            "Use short timeline entries (5 min)",
            "Accept that widgets are eventually consistent"
        ],
        sourceReferences: ["WidgetKit documentation", "Loop #2234"]
    ),
    Quirk(
        id: "QUIRK-WIDGET-002",
        category: .widget,
        title: "Lock Screen Widget Color Limitations",
        description: "Lock screen widgets render in monochrome only.",
        affectedVersions: .ios16Plus,
        severity: .low,
        symptoms: ["No color-coded glucose ranges on lock screen"],
        workarounds: [
            "Use symbols/icons instead of colors",
            "Use text labels for range indication",
            "Design for monochrome first"
        ],
        sourceReferences: ["Loop #2567"]
    ),
    
    // MARK: NFC Quirks
    Quirk(
        id: "QUIRK-NFC-001",
        category: .nfc,
        title: "iPhone SE NFC Range Reduction",
        description: "NFC antenna position requires closer proximity.",
        affectedVersions: .all,
        severity: .low,
        symptoms: ["Libre sensor reads fail on first attempt"],
        workarounds: [
            "Add device-specific instructions",
            "Guide user to hold phone at top of sensor",
            "Implement retry with guidance"
        ],
        sourceReferences: ["DiaBLE #123"]
    ),
    Quirk(
        id: "QUIRK-NFC-002",
        category: .nfc,
        title: "NFC Session Timeout",
        description: "NFC session auto-terminates after 60 seconds.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Long Libre reads fail near end"],
        workarounds: [
            "Optimize read sequence for speed",
            "Start new session if timeout imminent",
            "Pre-calculate required read time"
        ],
        sourceReferences: ["DiaBLE implementation"]
    ),
    Quirk(
        id: "QUIRK-NFC-003",
        category: .nfc,
        title: "Background NFC Not Supported",
        description: "NFC reads require active foreground session.",
        affectedVersions: .all,
        severity: .high,
        symptoms: ["Cannot auto-scan Libre sensors in background"],
        workarounds: [
            "Use Libre 2/3 BLE for continuous data",
            "Prompt user to scan for Libre 1",
            "Use scheduled reminders for scan times"
        ],
        sourceReferences: ["Apple NFC documentation"]
    ),
    
    // MARK: General iOS Quirks
    Quirk(
        id: "QUIRK-IOS-001",
        category: .general,
        title: "Background App Refresh Disabled by User",
        description: "Users may disable background refresh for battery.",
        affectedVersions: .all,
        severity: .high,
        symptoms: ["Cloud-based CGM data not fetched in background"],
        workarounds: [
            "Detect background refresh state",
            "Prompt user to enable if disabled",
            "Show warning about degraded experience"
        ],
        sourceReferences: ["Common user support issue"]
    ),
    Quirk(
        id: "QUIRK-IOS-002",
        category: .general,
        title: "Battery Optimization Kills Background Apps",
        description: "System aggressively terminates background apps under memory pressure.",
        affectedVersions: .ios15Plus,
        severity: .high,
        symptoms: ["App terminated", "CGM connection lost"],
        workarounds: [
            "Minimize memory usage",
            "Implement state restoration",
            "Use BLE restoration identifiers",
            "Guide users to disable Background App Refresh restrictions"
        ],
        sourceReferences: ["Loop #1890"]
    ),
    Quirk(
        id: "QUIRK-IOS-003",
        category: .general,
        title: "VPN Interferes with Nightscout Connection",
        description: "Some VPNs block or slow Nightscout API calls.",
        affectedVersions: .all,
        severity: .medium,
        symptoms: ["Data upload/download failures"],
        workarounds: [
            "Detect VPN state if possible",
            "Implement robust retry logic",
            "Cache data locally during outages",
            "Document known VPN issues"
        ],
        sourceReferences: ["Nightscout support"]
    ),
]
