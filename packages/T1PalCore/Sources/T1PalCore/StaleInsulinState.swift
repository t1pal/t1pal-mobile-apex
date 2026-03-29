/// Stale insulin data handling for IOB display
/// AID-PARTIAL-004: IOB→0 when doses > 6h old, show "stale"
///
/// When insulin data is stale (older than DIA), IOB should:
/// - Display as 0.00 U
/// - Show "stale" indicator instead of error
/// - Not prevent algorithm from running (degraded mode)
///
/// ## Usage
/// ```swift
/// let state = StaleInsulinState.evaluate(
///     lastDoseTime: pump.lastDoseDate,
///     dia: .standard
/// )
/// 
/// iobLabel.text = state.displayIOB(calculatedIOB: 2.5)
/// // Returns "0.00 U" if stale, "2.50 U" if fresh
/// ```

import Foundation

// MARK: - StaleInsulinState

/// Represents the staleness state of insulin data
public struct StaleInsulinState: Sendable, Equatable, Codable {
    
    /// Whether insulin data is stale (older than DIA)
    public let isStale: Bool
    
    /// Last dose timestamp (nil if no data)
    public let lastDoseTime: Date?
    
    /// Duration of insulin action
    public let diaSeconds: TimeInterval
    
    /// When this state was evaluated
    public let evaluatedAt: Date
    
    /// Time since last dose (nil if no data)
    public var timeSinceLastDose: TimeInterval? {
        guard let lastDoseTime else { return nil }
        return evaluatedAt.timeIntervalSince(lastDoseTime)
    }
    
    /// Time since last dose as Duration
    public var durationSinceLastDose: Duration? {
        guard let seconds = timeSinceLastDose else { return nil }
        return .seconds(seconds)
    }
    
    /// Percentage of DIA elapsed (0-100+)
    public var diaElapsedPercent: Double {
        guard let age = timeSinceLastDose else { return 100 }
        return min(100, (age / diaSeconds) * 100)
    }
    
    /// Initialize with explicit values
    public init(
        isStale: Bool,
        lastDoseTime: Date?,
        diaSeconds: TimeInterval,
        evaluatedAt: Date = Date()
    ) {
        self.isStale = isStale
        self.lastDoseTime = lastDoseTime
        self.diaSeconds = diaSeconds
        self.evaluatedAt = evaluatedAt
    }
    
    // MARK: - Factory Methods
    
    /// Evaluate staleness from dose timestamp
    public static func evaluate(
        lastDoseTime: Date?,
        diaSeconds: TimeInterval = 21600,  // 6 hours default
        evaluatedAt: Date = Date()
    ) -> StaleInsulinState {
        let isStale: Bool
        
        if let lastDoseTime {
            let age = evaluatedAt.timeIntervalSince(lastDoseTime)
            isStale = age > diaSeconds
        } else {
            // No dose data = stale
            isStale = true
        }
        
        return StaleInsulinState(
            isStale: isStale,
            lastDoseTime: lastDoseTime,
            diaSeconds: diaSeconds,
            evaluatedAt: evaluatedAt
        )
    }
    
    /// Evaluate with standard DIA preset
    public static func evaluate(
        lastDoseTime: Date?,
        dia: InsulinFreshness.StandardDIA,
        evaluatedAt: Date = Date()
    ) -> StaleInsulinState {
        evaluate(
            lastDoseTime: lastDoseTime,
            diaSeconds: dia.rawValue,
            evaluatedAt: evaluatedAt
        )
    }
    
    /// Create from InsulinFreshness
    public static func from(_ freshness: InsulinFreshness) -> StaleInsulinState {
        StaleInsulinState(
            isStale: freshness.iobIsZero,
            lastDoseTime: freshness.lastDoseDate,
            diaSeconds: freshness.diaSeconds,
            evaluatedAt: freshness.checkDate
        )
    }
    
    // MARK: - IOB Display
    
    /// Get display IOB value (0 if stale, actual value if fresh)
    public func displayIOB(calculatedIOB: Double) -> Double {
        isStale ? 0.0 : calculatedIOB
    }
    
    /// Format IOB for display with staleness handling
    public func formatIOB(calculatedIOB: Double, unit: String = "U") -> String {
        let value = displayIOB(calculatedIOB: calculatedIOB)
        return String(format: "%.2f %@", value, unit)
    }
    
    /// Status text for IOB display
    public var iobStatusText: String {
        if isStale {
            return "stale"
        }
        return "active"
    }
    
    /// Detailed status message
    public var statusMessage: String {
        if lastDoseTime == nil {
            return "No insulin data available"
        }
        
        if isStale {
            let hoursAgo = (timeSinceLastDose ?? 0) / 3600
            return String(format: "Insulin data stale (%.1f hours old)", hoursAgo)
        }
        
        let remaining = diaSeconds - (timeSinceLastDose ?? 0)
        let minutesRemaining = remaining / 60
        return String(format: "Active insulin (%.0f min remaining)", minutesRemaining)
    }
    
    // MARK: - UI Integration
    
    /// Convert to DeviceStatusElementState
    public var elementState: DeviceStatusElementState {
        if isStale {
            return .warning  // Stale is warning, not error
        }
        return .normalPump
    }
    
    /// Whether to show stale indicator badge
    public var showStaleIndicator: Bool {
        isStale
    }
    
    /// SF Symbol for current state
    public var iconName: String {
        if isStale {
            return "clock.badge.exclamationmark"
        }
        return "drop.fill"
    }
}

// MARK: - IOBDisplayValue

/// Wrapper for IOB value with staleness context
public struct IOBDisplayValue: Sendable, Equatable {
    
    /// Calculated IOB value (from algorithm)
    public let calculatedIOB: Double
    
    /// Staleness state
    public let staleState: StaleInsulinState
    
    /// Initialize
    public init(calculatedIOB: Double, staleState: StaleInsulinState) {
        self.calculatedIOB = calculatedIOB
        self.staleState = staleState
    }
    
    /// Create from dose data
    public init(
        calculatedIOB: Double,
        lastDoseTime: Date?,
        diaSeconds: TimeInterval = 21600
    ) {
        self.calculatedIOB = calculatedIOB
        self.staleState = StaleInsulinState.evaluate(
            lastDoseTime: lastDoseTime,
            diaSeconds: diaSeconds
        )
    }
    
    /// Display value (0 if stale)
    public var displayValue: Double {
        staleState.displayIOB(calculatedIOB: calculatedIOB)
    }
    
    /// Formatted string
    public var formatted: String {
        staleState.formatIOB(calculatedIOB: calculatedIOB)
    }
    
    /// Whether data is stale
    public var isStale: Bool {
        staleState.isStale
    }
    
    /// Element state for UI
    public var elementState: DeviceStatusElementState {
        staleState.elementState
    }
}

// MARK: - InsulinFreshness Extension

extension InsulinFreshness {
    
    /// Convert to StaleInsulinState
    public var staleState: StaleInsulinState {
        StaleInsulinState.from(self)
    }
    
    /// Create IOB display value
    public func iobDisplay(calculatedIOB: Double) -> IOBDisplayValue {
        IOBDisplayValue(calculatedIOB: calculatedIOB, staleState: staleState)
    }
}

// MARK: - CustomStringConvertible

extension StaleInsulinState: CustomStringConvertible {
    public var description: String {
        if isStale {
            return "StaleInsulinState(stale, \(iobStatusText))"
        }
        return "StaleInsulinState(active, \(Int(diaElapsedPercent))% elapsed)"
    }
}
