/// Pump status badge types for UI status indicators
/// Pattern: LoopKit DeviceStatusBadge, OmniKit status badges
///
/// Provides compact status indicators for pump state display.
/// Integrates with DeviceStatusElementState for visual presentation.

import Foundation

// MARK: - PumpStatusBadge

/// Represents a pump status badge for compact UI display.
///
/// Badges provide quick visual indicators of pump state without
/// detailed messages. Used in HUD displays and status bars.
///
/// ## Usage
/// ```swift
/// let badges = PumpStatusBadgeSet.evaluate(
///     suspended: pump.isSuspended,
///     reservoirUnits: pump.reservoirLevel,
///     batteryPercent: pump.batteryLevel,
///     lastSync: pump.lastCommunication
/// )
///
/// for badge in badges.active {
///     showBadge(badge.symbolName, state: badge.state)
/// }
/// ```
public struct PumpStatusBadge: Sendable, Equatable, Codable, Identifiable {
    
    /// Unique identifier for this badge
    public let id: BadgeType
    
    /// Badge type
    public let type: BadgeType
    
    /// Visual state for coloring
    public let state: DeviceStatusElementState
    
    /// SF Symbol name
    public var symbolName: String {
        type.symbolName
    }
    
    /// Localized description
    public var localizedDescription: String {
        type.localizedDescription
    }
    
    /// Initialize with type and state
    public init(type: BadgeType, state: DeviceStatusElementState) {
        self.id = type
        self.type = type
        self.state = state
    }
    
    // MARK: - Badge Type
    
    /// Types of pump status badges
    public enum BadgeType: String, Sendable, Codable, CaseIterable {
        /// Pump clock needs sync with phone
        case timeSyncNeeded
        
        /// Pump delivery is suspended
        case suspended
        
        /// Reservoir level is low
        case lowReservoir
        
        /// Reservoir is empty
        case emptyReservoir
        
        /// Battery level is low
        case lowBattery
        
        /// Battery is critically low
        case criticalBattery
        
        /// Pod is expiring soon (Omnipod)
        case podExpiring
        
        /// Pod has expired (Omnipod)
        case podExpired
        
        /// Pump communication lost
        case communicationLost
        
        /// Pump needs attention (generic)
        case needsAttention
        
        /// Pump setup incomplete
        case setupIncomplete
        
        /// Occlusion detected
        case occlusion
        
        /// SF Symbol for this badge type
        public var symbolName: String {
            switch self {
            case .timeSyncNeeded:
                return "clock.badge.exclamationmark"
            case .suspended:
                return "pause.circle.fill"
            case .lowReservoir:
                return "drop.fill"
            case .emptyReservoir:
                return "drop.triangle.fill"
            case .lowBattery:
                return "battery.25"
            case .criticalBattery:
                return "battery.0"
            case .podExpiring:
                return "timer"
            case .podExpired:
                return "xmark.circle.fill"
            case .communicationLost:
                return "antenna.radiowaves.left.and.right.slash"
            case .needsAttention:
                return "exclamationmark.triangle.fill"
            case .setupIncomplete:
                return "gearshape.fill"
            case .occlusion:
                return "xmark.octagon.fill"
            }
        }
        
        /// Localized description
        public var localizedDescription: String {
            switch self {
            case .timeSyncNeeded:
                return "Time sync needed"
            case .suspended:
                return "Delivery suspended"
            case .lowReservoir:
                return "Low reservoir"
            case .emptyReservoir:
                return "Reservoir empty"
            case .lowBattery:
                return "Low battery"
            case .criticalBattery:
                return "Battery critical"
            case .podExpiring:
                return "Pod expiring soon"
            case .podExpired:
                return "Pod expired"
            case .communicationLost:
                return "Communication lost"
            case .needsAttention:
                return "Needs attention"
            case .setupIncomplete:
                return "Setup incomplete"
            case .occlusion:
                return "Occlusion detected"
            }
        }
        
        /// Default state for this badge type
        public var defaultState: DeviceStatusElementState {
            switch self {
            case .timeSyncNeeded, .lowReservoir, .lowBattery, .podExpiring, .needsAttention, .setupIncomplete:
                return .warning
            case .suspended, .emptyReservoir, .criticalBattery, .podExpired, .communicationLost, .occlusion:
                return .critical
            }
        }
    }
}

// MARK: - PumpStatusBadgeSet

/// A set of active pump status badges.
///
/// Evaluates pump state and generates appropriate badges.
public struct PumpStatusBadgeSet: Sendable, Equatable, Codable {
    
    /// All active badges
    public let badges: [PumpStatusBadge]
    
    /// Timestamp when badges were evaluated
    public let evaluatedAt: Date
    
    /// Initialize with badges
    public init(badges: [PumpStatusBadge] = [], evaluatedAt: Date = Date()) {
        self.badges = badges
        self.evaluatedAt = evaluatedAt
    }
    
    // MARK: - Convenience Properties
    
    /// Whether any badges are active
    public var hasBadges: Bool {
        !badges.isEmpty
    }
    
    /// Number of active badges
    public var count: Int {
        badges.count
    }
    
    /// Badges filtered by state
    public func badges(withState state: DeviceStatusElementState) -> [PumpStatusBadge] {
        badges.filter { $0.state == state }
    }
    
    /// All critical badges
    public var criticalBadges: [PumpStatusBadge] {
        badges(withState: .critical)
    }
    
    /// All warning badges
    public var warningBadges: [PumpStatusBadge] {
        badges(withState: .warning)
    }
    
    /// Whether any critical badges exist
    public var hasCritical: Bool {
        badges.contains { $0.state == .critical }
    }
    
    /// Whether any warning badges exist
    public var hasWarning: Bool {
        badges.contains { $0.state == .warning }
    }
    
    /// Most severe state across all badges
    public var mostSevereState: DeviceStatusElementState {
        if hasCritical { return .critical }
        if hasWarning { return .warning }
        return .normalPump
    }
    
    /// Check if a specific badge type is present
    public func contains(_ type: PumpStatusBadge.BadgeType) -> Bool {
        badges.contains { $0.type == type }
    }
}

// MARK: - Factory Methods

extension PumpStatusBadgeSet {
    
    /// Evaluate pump state and generate badges
    public static func evaluate(
        suspended: Bool = false,
        reservoirUnits: Double? = nil,
        lowReservoirThreshold: Double = 20.0,
        emptyReservoirThreshold: Double = 0.0,
        batteryPercent: Double? = nil,
        lowBatteryThreshold: Double = 20.0,
        criticalBatteryThreshold: Double = 5.0,
        timeSyncNeeded: Bool = false,
        communicationLost: Bool = false,
        setupIncomplete: Bool = false,
        occlusionDetected: Bool = false,
        podHoursRemaining: Double? = nil,
        podExpiringThreshold: Double = 8.0,
        evaluatedAt: Date = Date()
    ) -> PumpStatusBadgeSet {
        
        var badges: [PumpStatusBadge] = []
        
        // Critical conditions first
        if suspended {
            badges.append(PumpStatusBadge(type: .suspended, state: .critical))
        }
        
        if communicationLost {
            badges.append(PumpStatusBadge(type: .communicationLost, state: .critical))
        }
        
        if occlusionDetected {
            badges.append(PumpStatusBadge(type: .occlusion, state: .critical))
        }
        
        // Reservoir state
        if let units = reservoirUnits {
            if units <= emptyReservoirThreshold {
                badges.append(PumpStatusBadge(type: .emptyReservoir, state: .critical))
            } else if units <= lowReservoirThreshold {
                badges.append(PumpStatusBadge(type: .lowReservoir, state: .warning))
            }
        }
        
        // Battery state
        if let percent = batteryPercent {
            if percent <= criticalBatteryThreshold {
                badges.append(PumpStatusBadge(type: .criticalBattery, state: .critical))
            } else if percent <= lowBatteryThreshold {
                badges.append(PumpStatusBadge(type: .lowBattery, state: .warning))
            }
        }
        
        // Pod lifecycle (Omnipod)
        if let hoursRemaining = podHoursRemaining {
            if hoursRemaining <= 0 {
                badges.append(PumpStatusBadge(type: .podExpired, state: .critical))
            } else if hoursRemaining <= podExpiringThreshold {
                badges.append(PumpStatusBadge(type: .podExpiring, state: .warning))
            }
        }
        
        // Warning conditions
        if timeSyncNeeded {
            badges.append(PumpStatusBadge(type: .timeSyncNeeded, state: .warning))
        }
        
        if setupIncomplete {
            badges.append(PumpStatusBadge(type: .setupIncomplete, state: .warning))
        }
        
        return PumpStatusBadgeSet(badges: badges, evaluatedAt: evaluatedAt)
    }
    
    /// Create empty badge set
    public static func empty(evaluatedAt: Date = Date()) -> PumpStatusBadgeSet {
        PumpStatusBadgeSet(badges: [], evaluatedAt: evaluatedAt)
    }
    
    /// Create with single badge
    public static func single(_ type: PumpStatusBadge.BadgeType, state: DeviceStatusElementState? = nil) -> PumpStatusBadgeSet {
        let badge = PumpStatusBadge(type: type, state: state ?? type.defaultState)
        return PumpStatusBadgeSet(badges: [badge])
    }
}

// MARK: - Reservoir Alert State

/// Reservoir level alert state
public enum ReservoirAlertState: String, Sendable, Codable, CaseIterable {
    case ok
    case low
    case empty
    
    /// Evaluate from units remaining
    public static func evaluate(
        units: Double?,
        lowThreshold: Double = 20.0,
        emptyThreshold: Double = 0.0
    ) -> ReservoirAlertState {
        guard let units else { return .ok }
        if units <= emptyThreshold { return .empty }
        if units <= lowThreshold { return .low }
        return .ok
    }
    
    /// Convert to element state
    public var elementState: DeviceStatusElementState {
        switch self {
        case .ok: return .normalPump
        case .low: return .warning
        case .empty: return .critical
        }
    }
}

// MARK: - Battery Alert State

/// Battery level alert state
public enum BatteryAlertState: String, Sendable, Codable, CaseIterable {
    case ok
    case low
    case critical
    
    /// Evaluate from percentage
    public static func evaluate(
        percent: Double?,
        lowThreshold: Double = 20.0,
        criticalThreshold: Double = 5.0
    ) -> BatteryAlertState {
        guard let percent else { return .ok }
        if percent <= criticalThreshold { return .critical }
        if percent <= lowThreshold { return .low }
        return .ok
    }
    
    /// Convert to element state
    public var elementState: DeviceStatusElementState {
        switch self {
        case .ok: return .normalPump
        case .low: return .warning
        case .critical: return .critical
        }
    }
}

// MARK: - Pod Lifecycle State

/// Omnipod lifecycle state
public enum PodLifecycleState: Sendable, Equatable, Codable {
    case active(hoursRemaining: Double)
    case expiringSoon(hoursRemaining: Double)
    case expired
    case deactivated
    case notConfigured
    
    /// Standard expiration warning threshold (8 hours)
    public static let defaultExpiringThreshold: Double = 8.0
    
    /// Evaluate from hours remaining
    public static func evaluate(
        hoursRemaining: Double?,
        expiringThreshold: Double = defaultExpiringThreshold,
        isDeactivated: Bool = false
    ) -> PodLifecycleState {
        if isDeactivated { return .deactivated }
        guard let hours = hoursRemaining else { return .notConfigured }
        if hours <= 0 { return .expired }
        if hours <= expiringThreshold { return .expiringSoon(hoursRemaining: hours) }
        return .active(hoursRemaining: hours)
    }
    
    /// Convert to element state
    public var elementState: DeviceStatusElementState {
        switch self {
        case .active:
            return .normalPump
        case .expiringSoon:
            return .warning
        case .expired:
            return .critical
        case .deactivated, .notConfigured:
            return .warning
        }
    }
    
    /// Whether pod can deliver insulin
    public var canDeliver: Bool {
        switch self {
        case .active, .expiringSoon:
            return true
        case .expired, .deactivated, .notConfigured:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension PumpStatusBadgeSet: CustomStringConvertible {
    public var description: String {
        if badges.isEmpty {
            return "PumpStatusBadgeSet(empty)"
        }
        let types = badges.map { $0.type.rawValue }.joined(separator: ", ")
        return "PumpStatusBadgeSet(\(badges.count): \(types))"
    }
}
