/// Loop operating modes for AID system
/// Pattern: Loop ClosedLoopMode + CGM-only support
///
/// Supports graceful degradation when pump unavailable:
/// - cgmOnly: Monitor glucose without pump control
/// - openLoop: CGM + pump connected, no automation
/// - closedLoop: Full automation (temp basal or automated bolus)
///
/// ## Usage
/// ```swift
/// let mode = LoopMode.cgmOnly
/// if mode.requiresPump {
///     guard pumpManager != nil else { return }
/// }
/// ```

import Foundation

// MARK: - LoopMode

/// Operating mode for the AID loop system
public enum LoopMode: String, Sendable, Equatable, Codable, CaseIterable {
    
    /// CGM monitoring only - no pump required
    /// Useful for:
    /// - Users without pump hardware
    /// - Pump disconnected/unavailable scenarios
    /// - Sensor-only monitoring during pump changes
    case cgmOnly = "CGM Only"
    
    /// Open loop - CGM + pump connected, manual control
    /// Algorithm provides recommendations but does not enact
    case openLoop = "Open Loop"
    
    /// Temp basal only - automates basal adjustments
    /// Does not deliver automatic boluses
    case tempBasalOnly = "Temp Basal Only"
    
    /// Full closed loop - temp basal + automated bolus (SMB)
    case closedLoop = "Closed Loop"
    
    // MARK: - Properties
    
    /// Whether this mode requires a connected pump
    public var requiresPump: Bool {
        switch self {
        case .cgmOnly:
            return false
        case .openLoop, .tempBasalOnly, .closedLoop:
            return true
        }
    }
    
    /// Whether this mode requires CGM data
    public var requiresCGM: Bool {
        // All modes require CGM
        true
    }
    
    /// Whether automation is enabled
    public var isAutomationEnabled: Bool {
        switch self {
        case .cgmOnly, .openLoop:
            return false
        case .tempBasalOnly, .closedLoop:
            return true
        }
    }
    
    /// Whether temp basal automation is enabled
    public var tempBasalEnabled: Bool {
        switch self {
        case .cgmOnly, .openLoop:
            return false
        case .tempBasalOnly, .closedLoop:
            return true
        }
    }
    
    /// Whether automated bolus (SMB) is enabled
    public var automatedBolusEnabled: Bool {
        switch self {
        case .cgmOnly, .openLoop, .tempBasalOnly:
            return false
        case .closedLoop:
            return true
        }
    }
    
    /// Short display name
    public var shortName: String {
        switch self {
        case .cgmOnly: return "CGM"
        case .openLoop: return "Open"
        case .tempBasalOnly: return "Temp"
        case .closedLoop: return "Closed"
        }
    }
    
    /// Icon name (SF Symbol)
    public var iconName: String {
        switch self {
        case .cgmOnly: return "drop.fill"
        case .openLoop: return "arrow.left.arrow.right"
        case .tempBasalOnly: return "arrow.up.arrow.down.circle"
        case .closedLoop: return "arrow.triangle.2.circlepath"
        }
    }
    
    /// Description of this mode
    public var modeDescription: String {
        switch self {
        case .cgmOnly:
            return "Monitor glucose readings without pump control. Pump not required."
        case .openLoop:
            return "View algorithm recommendations. Manual pump control only."
        case .tempBasalOnly:
            return "Automatic temp basal adjustments. No automatic boluses."
        case .closedLoop:
            return "Full automation with temp basal and automatic micro-boluses."
        }
    }
    
    /// Convert to DeviceStatusElementState
    public var statusElementState: DeviceStatusElementState {
        switch self {
        case .cgmOnly:
            return .normalCGM
        case .openLoop:
            return .warning  // Not automated
        case .tempBasalOnly, .closedLoop:
            return .normalPump
        }
    }
}

// MARK: - LoopModeTransition

/// Represents a transition between loop modes
public struct LoopModeTransition: Sendable, Equatable {
    
    /// Previous mode
    public let from: LoopMode
    
    /// New mode
    public let to: LoopMode
    
    /// Timestamp of transition
    public let timestamp: Date
    
    /// Reason for transition (optional)
    public let reason: Reason?
    
    /// Initialize
    public init(
        from: LoopMode,
        to: LoopMode,
        timestamp: Date = Date(),
        reason: Reason? = nil
    ) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
        self.reason = reason
    }
    
    /// Whether this transition reduces automation level
    public var isDowngrade: Bool {
        to.automationLevel < from.automationLevel
    }
    
    /// Whether this transition increases automation level
    public var isUpgrade: Bool {
        to.automationLevel > from.automationLevel
    }
    
    /// Transition reasons
    public enum Reason: String, Sendable, Codable {
        case userSelected
        case pumpDisconnected
        case pumpReconnected
        case cgmExpired
        case configurationMissing
        case safetyLimit
        case uncertainDelivery
        case automatic
    }
}

// MARK: - Automation Level

extension LoopMode {
    
    /// Automation level for comparison
    public var automationLevel: Int {
        switch self {
        case .cgmOnly: return 0
        case .openLoop: return 1
        case .tempBasalOnly: return 2
        case .closedLoop: return 3
        }
    }
    
    /// Modes with equal or higher automation
    public var modesAtOrAbove: [LoopMode] {
        LoopMode.allCases.filter { $0.automationLevel >= automationLevel }
    }
    
    /// Modes with lower automation (fallback options)
    public var fallbackModes: [LoopMode] {
        LoopMode.allCases.filter { $0.automationLevel < automationLevel }
    }
    
    /// Best fallback mode when this mode becomes unavailable
    public var bestFallback: LoopMode {
        // Prefer highest automation that doesn't require what we're missing
        switch self {
        case .closedLoop:
            return .tempBasalOnly
        case .tempBasalOnly:
            return .openLoop
        case .openLoop:
            return .cgmOnly
        case .cgmOnly:
            return .cgmOnly  // Already at minimum
        }
    }
}

// MARK: - Mode Validation

extension LoopMode {
    
    /// Check if this mode can run with current state
    public func canActivate(
        hasCGM: Bool,
        hasPump: Bool,
        hasBasalSchedule: Bool = true,
        hasInsulinSensitivity: Bool = true,
        hasCarbRatio: Bool = true,
        hasGlucoseTarget: Bool = true
    ) -> ActivationResult {
        var missingRequirements: [String] = []
        
        // CGM required for all modes
        if !hasCGM {
            missingRequirements.append("CGM")
        }
        
        // Pump required for non-cgmOnly modes
        if requiresPump && !hasPump {
            missingRequirements.append("Pump")
        }
        
        // Configuration required for automation
        if isAutomationEnabled {
            if !hasBasalSchedule {
                missingRequirements.append("Basal Schedule")
            }
            if !hasInsulinSensitivity {
                missingRequirements.append("Insulin Sensitivity")
            }
            if !hasCarbRatio {
                missingRequirements.append("Carb Ratio")
            }
            if !hasGlucoseTarget {
                missingRequirements.append("Glucose Target")
            }
        }
        
        if missingRequirements.isEmpty {
            return .canActivate
        } else {
            return .missingRequirements(missingRequirements)
        }
    }
    
    /// Result of activation check
    public enum ActivationResult: Sendable, Equatable {
        case canActivate
        case missingRequirements([String])
        
        public var canActivate: Bool {
            if case .canActivate = self { return true }
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension LoopMode: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
