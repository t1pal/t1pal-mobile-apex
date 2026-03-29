/// Device status types for UI state representation
/// Pattern: LoopKit/DeviceManager/DeviceStatusHighlight.swift
///
/// Provides state representation for device status UI elements
/// including CGM, pump, and general device status.

import Foundation

// MARK: - DeviceStatusElementState

/// Represents the visual state of a device status element.
///
/// Used to determine colors, icons, and urgency of device status displays.
/// Follows LoopKit behavioral parity for UI consistency.
///
/// - `critical`: Device in error state, requires immediate attention (red)
/// - `warning`: Device degraded, may need attention soon (yellow)
/// - `normalCGM`: CGM operating normally (green)
/// - `normalPump`: Pump operating normally (green)
public enum DeviceStatusElementState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case critical
    case warning
    case normalCGM
    case normalPump
    
    /// Convenience check for any normal state
    public var isNormal: Bool {
        switch self {
        case .normalCGM, .normalPump:
            return true
        case .critical, .warning:
            return false
        }
    }
    
    /// Convenience check for error states requiring attention
    public var needsAttention: Bool {
        switch self {
        case .critical, .warning:
            return true
        case .normalCGM, .normalPump:
            return false
        }
    }
    
    /// Sort priority for UI ordering (critical first, then warning, then normal)
    public var sortPriority: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .normalCGM, .normalPump: return 2
        }
    }
}

// MARK: - DeviceStatusHighlight Protocol

/// Protocol for device status messages with visual state.
///
/// Provides localized message text, an icon name, and the current state.
/// Used for prominent device status displays (e.g., "Low Battery").
public protocol DeviceStatusHighlight: Codable, Sendable {
    /// Localized message describing the status
    var localizedMessage: String { get }
    
    /// SF Symbol name for the status icon
    var imageName: String { get }
    
    /// Current visual state
    var state: DeviceStatusElementState { get }
}

// MARK: - DeviceStatusBadge Protocol

/// Protocol for device status badges (compact status indicators).
///
/// Provides an image and state for badge-style status display.
/// Used for compact indicators (e.g., pump status badges).
public protocol DeviceStatusBadge: Sendable {
    /// Badge image data (optional for cross-platform compatibility)
    var imageData: Data? { get }
    
    /// SF Symbol name for cross-platform rendering
    var symbolName: String? { get }
    
    /// Current visual state
    var state: DeviceStatusElementState { get }
}

// MARK: - DeviceLifecycleProgressState

/// Progress state for device lifecycle indicators (sensors, reservoirs, etc.).
///
/// Extends DeviceStatusElementState with `dimmed` for inactive/background states.
public enum DeviceLifecycleProgressState: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case critical
    case dimmed
    case normalCGM
    case normalPump
    case warning
    
    /// Convert to base DeviceStatusElementState (dimmed → normalCGM)
    public var elementState: DeviceStatusElementState {
        switch self {
        case .critical: return .critical
        case .warning: return .warning
        case .normalCGM, .dimmed: return .normalCGM
        case .normalPump: return .normalPump
        }
    }
    
    /// Check if state represents active progress
    public var isActive: Bool {
        self != .dimmed
    }
}

// MARK: - DeviceLifecycleProgress Protocol

/// Protocol for tracking device lifecycle progress (sensor warmup, reservoir level, etc.).
public protocol DeviceLifecycleProgress: Sendable {
    /// Progress percentage (0.0 - 1.0)
    var percentComplete: Double { get }
    
    /// Current progress state
    var progressState: DeviceLifecycleProgressState { get }
}
