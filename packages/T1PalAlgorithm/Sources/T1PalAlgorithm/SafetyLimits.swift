// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SafetyLimits.swift
// T1Pal Mobile
//
// Safety limits and guardrails for AID algorithm
// Requirements: REQ-AID-006
//
// Critical safety constraints to prevent dangerous insulin delivery

import Foundation

// MARK: - Safety Limit Types

/// Hard safety limits that cannot be exceeded
public struct SafetyLimits: Codable, Sendable {
    /// Maximum basal rate (U/hr)
    public let maxBasalRate: Double
    
    /// Maximum bolus size (U)
    public let maxBolus: Double
    
    /// Maximum insulin on board (U)
    public let maxIOB: Double
    
    /// Maximum carbs on board for calculations (g)
    public let maxCOB: Double
    
    /// Minimum BG for algorithm operation (mg/dL)
    public let minBG: Double
    
    /// BG threshold for low glucose suspend (mg/dL)
    public let suspendThreshold: Double
    
    /// Minimum time between boluses (seconds)
    public let minBolusInterval: TimeInterval
    
    /// Maximum duration for temp basals (seconds)
    public let maxTempBasalDuration: TimeInterval
    
    public init(
        maxBasalRate: Double = 5.0,
        maxBolus: Double = 10.0,
        maxIOB: Double = 10.0,
        maxCOB: Double = 120.0,
        minBG: Double = 39.0,
        suspendThreshold: Double = 70.0,
        minBolusInterval: TimeInterval = 3 * 60,  // 3 minutes
        maxTempBasalDuration: TimeInterval = 120 * 60  // 2 hours
    ) {
        self.maxBasalRate = maxBasalRate
        self.maxBolus = maxBolus
        self.maxIOB = maxIOB
        self.maxCOB = maxCOB
        self.minBG = minBG
        self.suspendThreshold = suspendThreshold
        self.minBolusInterval = minBolusInterval
        self.maxTempBasalDuration = maxTempBasalDuration
    }
    
    /// Default safety limits
    public static let `default` = SafetyLimits()
    
    /// Conservative limits for new users
    public static let conservative = SafetyLimits(
        maxBasalRate: 2.0,
        maxBolus: 5.0,
        maxIOB: 5.0,
        maxCOB: 60.0,
        suspendThreshold: 80.0
    )
}

// MARK: - Safety Check Result

/// Result of a safety check
public enum SafetyCheckResult: Sendable {
    case allowed
    case limited(originalValue: Double, limitedValue: Double, reason: String)
    case denied(reason: String)
    
    public var isAllowed: Bool {
        switch self {
        case .allowed, .limited: return true
        case .denied: return false
        }
    }
    
    public var reason: String? {
        switch self {
        case .allowed: return nil
        case .limited(_, _, let reason): return reason
        case .denied(let reason): return reason
        }
    }
}

// MARK: - Safety Guardian

/// Enforces safety limits on algorithm decisions
public struct SafetyGuardian: Sendable {
    public let limits: SafetyLimits
    
    public init(limits: SafetyLimits = .default) {
        self.limits = limits
    }
    
    // MARK: - Basal Rate Checks
    
    /// Check and limit a basal rate
    public func checkBasalRate(_ rate: Double) -> SafetyCheckResult {
        guard rate >= 0 else {
            return .denied(reason: "Basal rate cannot be negative")
        }
        
        if rate <= limits.maxBasalRate {
            return .allowed
        }
        
        return .limited(
            originalValue: rate,
            limitedValue: limits.maxBasalRate,
            reason: "Basal rate \(String(format: "%.2f", rate)) exceeds max \(String(format: "%.2f", limits.maxBasalRate))"
        )
    }
    
    /// Apply basal rate limit
    public func limitBasalRate(_ rate: Double) -> Double {
        max(0, min(rate, limits.maxBasalRate))
    }
    
    // MARK: - Bolus Checks
    
    /// Check and limit a bolus amount
    public func checkBolus(_ units: Double) -> SafetyCheckResult {
        guard units >= 0 else {
            return .denied(reason: "Bolus cannot be negative")
        }
        
        if units <= limits.maxBolus {
            return .allowed
        }
        
        return .limited(
            originalValue: units,
            limitedValue: limits.maxBolus,
            reason: "Bolus \(String(format: "%.2f", units))U exceeds max \(String(format: "%.2f", limits.maxBolus))U"
        )
    }
    
    /// Apply bolus limit
    public func limitBolus(_ units: Double) -> Double {
        max(0, min(units, limits.maxBolus))
    }
    
    // MARK: - IOB Checks
    
    /// Check if additional insulin can be delivered given current IOB
    public func checkIOB(current: Double, additional: Double) -> SafetyCheckResult {
        let projected = current + additional
        
        if projected <= limits.maxIOB {
            return .allowed
        }
        
        let allowable = max(0, limits.maxIOB - current)
        
        if allowable <= 0 {
            return .denied(reason: "IOB \(String(format: "%.2f", current))U at or above max \(String(format: "%.2f", limits.maxIOB))U")
        }
        
        return .limited(
            originalValue: additional,
            limitedValue: allowable,
            reason: "Limited to \(String(format: "%.2f", allowable))U to stay within maxIOB"
        )
    }
    
    /// Calculate maximum additional insulin allowed
    public func maxAdditionalIOB(currentIOB: Double) -> Double {
        max(0, limits.maxIOB - currentIOB)
    }
    
    // MARK: - Glucose Checks
    
    /// Check if glucose level requires suspend
    public func checkGlucose(_ glucose: Double) -> SafetyCheckResult {
        if glucose < limits.minBG {
            return .denied(reason: "Glucose \(Int(glucose)) below minimum valid reading")
        }
        
        if glucose <= limits.suspendThreshold {
            return .denied(reason: "Glucose \(Int(glucose)) at or below suspend threshold \(Int(limits.suspendThreshold))")
        }
        
        return .allowed
    }
    
    /// Check if low glucose suspend should be active
    public func shouldSuspend(glucose: Double) -> Bool {
        glucose <= limits.suspendThreshold
    }
    
    /// Check if predicted low should trigger suspend
    public func shouldSuspendForPrediction(minPredBG: Double) -> Bool {
        minPredBG < limits.suspendThreshold
    }
    
    // MARK: - Temp Basal Checks
    
    /// Check temp basal duration
    public func checkTempBasalDuration(_ duration: TimeInterval) -> SafetyCheckResult {
        guard duration > 0 else {
            return .denied(reason: "Duration must be positive")
        }
        
        if duration <= limits.maxTempBasalDuration {
            return .allowed
        }
        
        return .limited(
            originalValue: duration,
            limitedValue: limits.maxTempBasalDuration,
            reason: "Duration limited to \(Int(limits.maxTempBasalDuration / 60)) minutes"
        )
    }
    
    // MARK: - Comprehensive Safety Check
    
    /// Perform comprehensive safety check on algorithm output
    public func validateDecision(
        suggestedRate: Double?,
        suggestedBolus: Double?,
        currentIOB: Double,
        currentGlucose: Double,
        minPredBG: Double
    ) -> (rate: Double?, bolus: Double?, suspended: Bool, reasons: [String]) {
        var reasons: [String] = []
        var rate = suggestedRate
        var bolus = suggestedBolus
        var suspended = false
        
        // Check glucose
        let glucoseCheck = checkGlucose(currentGlucose)
        if case .denied(let reason) = glucoseCheck {
            reasons.append(reason)
            rate = 0
            bolus = nil
            suspended = true
        }
        
        // Check predicted low
        if shouldSuspendForPrediction(minPredBG: minPredBG) {
            reasons.append("Predicted low \(Int(minPredBG)), suspending")
            rate = 0
            suspended = true
        }
        
        // Apply rate limit if not suspended
        if let r = rate, !suspended {
            let rateCheck = checkBasalRate(r)
            if case .limited(_, let limited, let reason) = rateCheck {
                rate = limited
                reasons.append(reason)
            }
        }
        
        // Apply bolus limits
        if let b = bolus {
            let bolusCheck = checkBolus(b)
            switch bolusCheck {
            case .denied(let reason):
                bolus = nil
                reasons.append(reason)
            case .limited(_, let limited, let reason):
                bolus = limited
                reasons.append(reason)
            case .allowed:
                break
            }
            
            // Also check IOB
            if let b = bolus {
                let iobCheck = checkIOB(current: currentIOB, additional: b)
                switch iobCheck {
                case .denied(let reason):
                    bolus = nil
                    reasons.append(reason)
                case .limited(_, let limited, let reason):
                    bolus = limited
                    reasons.append(reason)
                case .allowed:
                    break
                }
            }
        }
        
        return (rate, bolus, suspended, reasons)
    }
}

// MARK: - Safety Audit Log

/// Log entry for safety-related events
public struct SafetyAuditEntry: Codable, Sendable {
    public let timestamp: Date
    public let eventType: String
    public let originalValue: Double?
    public let limitedValue: Double?
    public let reason: String
    
    public init(
        timestamp: Date = Date(),
        eventType: String,
        originalValue: Double? = nil,
        limitedValue: Double? = nil,
        reason: String
    ) {
        self.timestamp = timestamp
        self.eventType = eventType
        self.originalValue = originalValue
        self.limitedValue = limitedValue
        self.reason = reason
    }
}

/// Thread-safe audit log for safety events
public final class SafetyAuditLog: @unchecked Sendable {
    private var entries: [SafetyAuditEntry] = []
    private let lock = NSLock()
    private let maxEntries: Int
    
    public init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }
    
    public func log(_ entry: SafetyAuditEntry) {
        lock.lock()
        defer { lock.unlock() }
        
        entries.append(entry)
        
        // Trim old entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    public func recentEntries(count: Int = 50) -> [SafetyAuditEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(entries.suffix(count))
    }
    
    public func entriesSince(_ date: Date) -> [SafetyAuditEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        return entries.filter { $0.timestamp >= date }
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
