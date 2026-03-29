// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeliveryLimits.swift
// T1Pal Mobile
//
// Max delivery limits for pump safety
// Requirements: REQ-AID-006
//
// Prevents dangerous insulin over-delivery with per-bolus
// and per-hour limits.

import Foundation

// MARK: - Delivery Limits Configuration

/// Configuration for maximum delivery limits
/// Requirements: REQ-AID-006
public struct DeliveryLimits: Sendable, Equatable, Codable {
    /// Maximum single bolus (units)
    public let maxBolus: Double
    /// Maximum hourly delivery (units)
    public let maxHourlyDelivery: Double
    /// Maximum daily delivery (units)
    public let maxDailyDelivery: Double
    /// Maximum temp basal rate (U/hr)
    public let maxTempBasalRate: Double
    /// Maximum temp basal duration (seconds)
    public let maxTempBasalDuration: TimeInterval
    
    /// Default safety limits based on typical AID systems
    public static let `default` = DeliveryLimits(
        maxBolus: 10.0,
        maxHourlyDelivery: 15.0,
        maxDailyDelivery: 100.0,
        maxTempBasalRate: 10.0,
        maxTempBasalDuration: 7200  // 2 hours
    )
    
    /// Conservative limits for new users
    public static let conservative = DeliveryLimits(
        maxBolus: 5.0,
        maxHourlyDelivery: 8.0,
        maxDailyDelivery: 50.0,
        maxTempBasalRate: 5.0,
        maxTempBasalDuration: 3600  // 1 hour
    )
    
    /// Relaxed limits for experienced users
    public static let relaxed = DeliveryLimits(
        maxBolus: 25.0,
        maxHourlyDelivery: 30.0,
        maxDailyDelivery: 150.0,
        maxTempBasalRate: 15.0,
        maxTempBasalDuration: 14400  // 4 hours
    )
    
    public init(
        maxBolus: Double = 10.0,
        maxHourlyDelivery: Double = 15.0,
        maxDailyDelivery: Double = 100.0,
        maxTempBasalRate: Double = 10.0,
        maxTempBasalDuration: TimeInterval = 7200
    ) {
        self.maxBolus = maxBolus
        self.maxHourlyDelivery = maxHourlyDelivery
        self.maxDailyDelivery = maxDailyDelivery
        self.maxTempBasalRate = maxTempBasalRate
        self.maxTempBasalDuration = maxTempBasalDuration
    }
}

// MARK: - Delivery Limit Errors

/// Errors related to delivery limit violations
public enum DeliveryLimitError: Error, Sendable, Equatable {
    /// Bolus exceeds maximum single bolus limit
    case bolusExceedsMax(requested: Double, limit: Double)
    /// Delivery would exceed hourly limit
    case hourlyLimitExceeded(projected: Double, limit: Double, remaining: Double)
    /// Delivery would exceed daily limit
    case dailyLimitExceeded(projected: Double, limit: Double, remaining: Double)
    /// Temp basal rate exceeds maximum
    case tempBasalRateExceedsMax(requested: Double, limit: Double)
    /// Temp basal duration exceeds maximum
    case tempBasalDurationExceedsMax(requested: TimeInterval, limit: TimeInterval)
}

// MARK: - Delivery Record

/// Record of insulin delivery for tracking
public struct DeliveryRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let units: Double
    public let type: DeliveryType
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        units: Double,
        type: DeliveryType,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.units = units
        self.type = type
        self.timestamp = timestamp
    }
}

/// Type of insulin delivery
public enum DeliveryType: String, Sendable, Codable {
    case bolus
    case basal
    case tempBasal
    case correction
}

// MARK: - Delivery Tracker

/// Tracks insulin delivery over time for limit enforcement
/// Requirements: REQ-AID-006
public actor DeliveryTracker {
    private var records: [DeliveryRecord] = []
    private let limits: DeliveryLimits
    
    /// Time window for hourly calculation
    private let hourlyWindow: TimeInterval = 3600
    /// Time window for daily calculation
    private let dailyWindow: TimeInterval = 86400
    
    public init(limits: DeliveryLimits = .default) {
        self.limits = limits
    }
    
    // MARK: - Recording Delivery
    
    /// Record a delivery
    public func record(_ delivery: DeliveryRecord) {
        records.append(delivery)
        pruneOldRecords()
    }
    
    /// Record a bolus delivery
    public func recordBolus(units: Double) {
        let record = DeliveryRecord(units: units, type: .bolus)
        records.append(record)
        pruneOldRecords()
    }
    
    /// Record basal delivery
    public func recordBasal(units: Double) {
        let record = DeliveryRecord(units: units, type: .basal)
        records.append(record)
        pruneOldRecords()
    }
    
    /// Record temp basal delivery
    public func recordTempBasal(units: Double) {
        let record = DeliveryRecord(units: units, type: .tempBasal)
        records.append(record)
        pruneOldRecords()
    }
    
    // MARK: - Querying Delivery
    
    /// Get total delivery in the last hour
    public func hourlyDelivery() -> Double {
        let cutoff = Date().addingTimeInterval(-hourlyWindow)
        return records
            .filter { $0.timestamp >= cutoff }
            .reduce(0) { $0 + $1.units }
    }
    
    /// Get total delivery in the last 24 hours
    public func dailyDelivery() -> Double {
        let cutoff = Date().addingTimeInterval(-dailyWindow)
        return records
            .filter { $0.timestamp >= cutoff }
            .reduce(0) { $0 + $1.units }
    }
    
    /// Get remaining allowance for the hour
    public func remainingHourlyAllowance() -> Double {
        max(0, limits.maxHourlyDelivery - hourlyDelivery())
    }
    
    /// Get remaining allowance for the day
    public func remainingDailyAllowance() -> Double {
        max(0, limits.maxDailyDelivery - dailyDelivery())
    }
    
    /// Get all records (for debugging/export)
    public func allRecords() -> [DeliveryRecord] {
        records
    }
    
    /// Get record count
    public func recordCount() -> Int {
        records.count
    }
    
    // MARK: - Limit Validation
    
    /// Check if a bolus can be delivered
    public func canDeliverBolus(units: Double) -> Result<Void, DeliveryLimitError> {
        // Check single bolus limit
        if units > limits.maxBolus {
            return .failure(.bolusExceedsMax(requested: units, limit: limits.maxBolus))
        }
        
        // Check hourly limit
        let projectedHourly = hourlyDelivery() + units
        if projectedHourly > limits.maxHourlyDelivery {
            return .failure(.hourlyLimitExceeded(
                projected: projectedHourly,
                limit: limits.maxHourlyDelivery,
                remaining: remainingHourlyAllowance()
            ))
        }
        
        // Check daily limit
        let projectedDaily = dailyDelivery() + units
        if projectedDaily > limits.maxDailyDelivery {
            return .failure(.dailyLimitExceeded(
                projected: projectedDaily,
                limit: limits.maxDailyDelivery,
                remaining: remainingDailyAllowance()
            ))
        }
        
        return .success(())
    }
    
    /// Check if a temp basal can be set
    public func canSetTempBasal(rate: Double, duration: TimeInterval) -> Result<Void, DeliveryLimitError> {
        // Check rate limit
        if rate > limits.maxTempBasalRate {
            return .failure(.tempBasalRateExceedsMax(requested: rate, limit: limits.maxTempBasalRate))
        }
        
        // Check duration limit
        if duration > limits.maxTempBasalDuration {
            return .failure(.tempBasalDurationExceedsMax(
                requested: duration,
                limit: limits.maxTempBasalDuration
            ))
        }
        
        // Calculate projected delivery from temp basal
        let projectedDelivery = rate * (duration / 3600)
        
        // Check hourly limit (consider worst case: all delivered in one hour)
        let projectedHourly = hourlyDelivery() + min(rate, projectedDelivery)
        if projectedHourly > limits.maxHourlyDelivery {
            return .failure(.hourlyLimitExceeded(
                projected: projectedHourly,
                limit: limits.maxHourlyDelivery,
                remaining: remainingHourlyAllowance()
            ))
        }
        
        return .success(())
    }
    
    // MARK: - Maintenance
    
    /// Remove records older than daily window
    private func pruneOldRecords() {
        let cutoff = Date().addingTimeInterval(-dailyWindow)
        records.removeAll { $0.timestamp < cutoff }
    }
    
    /// Clear all records (for testing)
    public func clearRecords() {
        records.removeAll()
    }
    
    /// Get current limits
    public func currentLimits() -> DeliveryLimits {
        limits
    }
}

// MARK: - Limit Validator

/// Validates delivery commands against limits
/// Requirements: REQ-AID-006
public struct LimitValidator: Sendable {
    private let limits: DeliveryLimits
    
    public init(limits: DeliveryLimits = .default) {
        self.limits = limits
    }
    
    /// Validate a bolus command
    public func validateBolus(_ command: BolusCommand) -> Result<Void, DeliveryLimitError> {
        if command.units > limits.maxBolus {
            return .failure(.bolusExceedsMax(requested: command.units, limit: limits.maxBolus))
        }
        return .success(())
    }
    
    /// Validate a temp basal command
    public func validateTempBasal(_ command: TempBasalCommand) -> Result<Void, DeliveryLimitError> {
        if command.rate > limits.maxTempBasalRate {
            return .failure(.tempBasalRateExceedsMax(
                requested: command.rate,
                limit: limits.maxTempBasalRate
            ))
        }
        
        if command.duration > limits.maxTempBasalDuration {
            return .failure(.tempBasalDurationExceedsMax(
                requested: command.duration,
                limit: limits.maxTempBasalDuration
            ))
        }
        
        return .success(())
    }
    
    /// Get the current limits
    public func currentLimits() -> DeliveryLimits {
        limits
    }
}

// MARK: - Summary Statistics

/// Summary of delivery statistics
public struct DeliverySummary: Sendable {
    public let hourlyDelivery: Double
    public let dailyDelivery: Double
    public let remainingHourly: Double
    public let remainingDaily: Double
    public let limits: DeliveryLimits
    
    public var hourlyPercentUsed: Double {
        limits.maxHourlyDelivery > 0 ? hourlyDelivery / limits.maxHourlyDelivery : 0
    }
    
    public var dailyPercentUsed: Double {
        limits.maxDailyDelivery > 0 ? dailyDelivery / limits.maxDailyDelivery : 0
    }
}

extension DeliveryTracker {
    /// Get current delivery summary
    public func summary() -> DeliverySummary {
        DeliverySummary(
            hourlyDelivery: hourlyDelivery(),
            dailyDelivery: dailyDelivery(),
            remainingHourly: remainingHourlyAllowance(),
            remainingDaily: remainingDailyAllowance(),
            limits: limits
        )
    }
}
