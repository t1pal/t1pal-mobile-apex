// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Profile.swift
// T1Pal Mobile
//
// Algorithm profile schema for AID calculations
// Requirements: REQ-AID-007
//
// Compatible with Nightscout profile format:
// https://nightscout.github.io/nightscout/profile_editor/

import Foundation
import T1PalCore

// MARK: - Profile Override (ALG-PARITY-004)

/// Temporary profile override that scales ISF, CR, and basal by a percentage.
/// Based on Trio's override implementation.
///
/// Usage:
/// - 100% = normal (no change)
/// - 80% = more sensitive (less insulin) - e.g., exercise
/// - 120% = more resistant (more insulin) - e.g., illness
///
/// The percentage scales values as: adjustedValue = baseValue / (percentage / 100)
/// So 80% makes ISF larger (less insulin per mg/dL drop)
public struct ProfileOverride: Codable, Sendable, Equatable {
    /// Override identifier
    public let id: String
    
    /// Display name for the override
    public let name: String
    
    /// Whether the override is currently active
    public var isActive: Bool
    
    /// Override percentage (100 = normal, 80 = less insulin, 120 = more insulin)
    public let percentage: Double
    
    /// Duration in minutes (0 = indefinite)
    public let durationMinutes: Double
    
    /// Whether this is an indefinite override
    public var isIndefinite: Bool { durationMinutes <= 0 }
    
    /// Optional target glucose override (mg/dL)
    public let targetOverride: Double?
    
    /// Whether to disable SMB during override
    public let disableSMB: Bool
    
    /// When the override was started
    public var startDate: Date?
    
    /// Whether to apply override to ISF
    public let adjustISF: Bool
    
    /// Whether to apply override to CR
    public let adjustCR: Bool
    
    /// Whether to apply override to basal
    public let adjustBasal: Bool
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        isActive: Bool = false,
        percentage: Double = 100,
        durationMinutes: Double = 0,
        targetOverride: Double? = nil,
        disableSMB: Bool = false,
        startDate: Date? = nil,
        adjustISF: Bool = true,
        adjustCR: Bool = true,
        adjustBasal: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.percentage = max(10, min(200, percentage))  // Clamp 10-200%
        self.durationMinutes = durationMinutes
        self.targetOverride = targetOverride
        self.disableSMB = disableSMB
        self.startDate = startDate
        self.adjustISF = adjustISF
        self.adjustCR = adjustCR
        self.adjustBasal = adjustBasal
    }
    
    /// The override factor (percentage / 100)
    public var factor: Double {
        percentage / 100.0
    }
    
    /// Calculate adjusted ISF (base / factor)
    public func adjustedISF(_ baseISF: Double) -> Double {
        guard adjustISF, factor > 0 else { return baseISF }
        return baseISF / factor
    }
    
    /// Calculate adjusted CR (base / factor)
    public func adjustedCR(_ baseCR: Double) -> Double {
        guard adjustCR, factor > 0 else { return baseCR }
        return baseCR / factor
    }
    
    /// Calculate adjusted basal (base * factor)
    public func adjustedBasal(_ baseBasal: Double) -> Double {
        guard adjustBasal else { return baseBasal }
        return baseBasal * factor
    }
    
    /// Check if override has expired
    public func isExpired(at date: Date = Date()) -> Bool {
        guard !isIndefinite, let start = startDate else { return false }
        let elapsed = date.timeIntervalSince(start)
        return elapsed >= durationMinutes * 60
    }
    
    /// Remaining duration in minutes (nil if indefinite or expired)
    public func remainingMinutes(at date: Date = Date()) -> Double? {
        guard !isIndefinite, let start = startDate else { return nil }
        let elapsed = date.timeIntervalSince(start) / 60
        let remaining = durationMinutes - elapsed
        return remaining > 0 ? remaining : 0
    }
    
    // MARK: - Preset Overrides
    
    /// Exercise mode: 80% (less insulin)
    public static let exercise = ProfileOverride(
        name: "Exercise",
        percentage: 80,
        durationMinutes: 60,
        disableSMB: false
    )
    
    /// High activity: 70% (much less insulin)
    public static let highActivity = ProfileOverride(
        name: "High Activity",
        percentage: 70,
        durationMinutes: 120,
        disableSMB: true
    )
    
    /// Illness/stress: 120% (more insulin)
    public static let illness = ProfileOverride(
        name: "Illness",
        percentage: 120,
        durationMinutes: 0  // Indefinite
    )
    
    /// Pre-meal: 110% (slightly more aggressive)
    public static let preMeal = ProfileOverride(
        name: "Pre-Meal",
        percentage: 110,
        durationMinutes: 60,
        targetOverride: 80
    )
}

// MARK: - Schedule Entry Protocol

/// A time-based schedule entry
public protocol ScheduleEntry: Codable, Sendable {
    /// Seconds from midnight (00:00)
    var startTime: TimeInterval { get }
}

// MARK: - Schedule

/// A schedule of time-based values (like basal rates, ISF, ICR)
public struct Schedule<T: ScheduleEntry>: Codable, Sendable where T: Equatable {
    public private(set) var entries: [T]
    
    public init(entries: [T]) {
        // Sort by start time and remove duplicates
        self.entries = entries.sorted { $0.startTime < $1.startTime }
    }
    
    /// Get the active entry for a given time of day
    public func entry(at secondsFromMidnight: TimeInterval) -> T? {
        guard !entries.isEmpty else { return nil }
        
        // Find the last entry that starts at or before the given time
        var result = entries.first
        for entry in entries {
            if entry.startTime <= secondsFromMidnight {
                result = entry
            } else {
                break
            }
        }
        return result
    }
    
    /// Get the active entry for a given date
    public func entry(at date: Date) -> T? {
        let seconds = secondsFromMidnight(date)
        return entry(at: seconds)
    }
    
    /// Calculate seconds from midnight for a date
    private func secondsFromMidnight(_ date: Date) -> TimeInterval {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}

// MARK: - Algorithm Profile

/// Complete profile for algorithm calculations
/// Extends T1PalCore.TherapyProfile with algorithm-specific features
public struct AlgorithmProfile: Codable, Sendable {
    public let name: String
    public let timezone: String
    public let dia: Double  // Duration of insulin action (hours)
    
    // Schedules
    public let basalSchedule: Schedule<BasalScheduleEntry>
    public let isfSchedule: Schedule<ISFScheduleEntry>
    public let icrSchedule: Schedule<ICRScheduleEntry>
    public let targetSchedule: Schedule<TargetScheduleEntry>
    
    // Safety limits
    public let maxBasal: Double     // U/hr
    public let maxBolus: Double     // U
    public let maxIOB: Double       // U
    public let maxCOB: Double       // g
    
    // Algorithm settings
    public let autosensMax: Double  // Max autosens adjustment (e.g., 1.2)
    public let autosensMin: Double  // Min autosens adjustment (e.g., 0.8)
    
    public init(
        name: String = "Default",
        timezone: String = "UTC",
        dia: Double = 6.0,
        basalSchedule: Schedule<BasalScheduleEntry>,
        isfSchedule: Schedule<ISFScheduleEntry>,
        icrSchedule: Schedule<ICRScheduleEntry>,
        targetSchedule: Schedule<TargetScheduleEntry>,
        maxBasal: Double = 2.0,
        maxBolus: Double = 10.0,
        maxIOB: Double = 8.0,
        maxCOB: Double = 120.0,
        autosensMax: Double = 1.2,
        autosensMin: Double = 0.8
    ) {
        self.name = name
        self.timezone = timezone
        self.dia = dia
        self.basalSchedule = basalSchedule
        self.isfSchedule = isfSchedule
        self.icrSchedule = icrSchedule
        self.targetSchedule = targetSchedule
        self.maxBasal = maxBasal
        self.maxBolus = maxBolus
        self.maxIOB = maxIOB
        self.maxCOB = maxCOB
        self.autosensMax = autosensMax
        self.autosensMin = autosensMin
    }
    
    // MARK: - Convenience Lookups
    
    /// Get current basal rate
    public func currentBasal(at date: Date = Date()) -> Double {
        basalSchedule.entry(at: date)?.rate ?? 0
    }
    
    /// Get current ISF (mg/dL per U)
    public func currentISF(at date: Date = Date()) -> Double {
        isfSchedule.entry(at: date)?.sensitivity ?? 50
    }
    
    /// Get current ICR (g/U)
    public func currentICR(at date: Date = Date()) -> Double {
        icrSchedule.entry(at: date)?.ratio ?? 10
    }
    
    /// Get current target (midpoint)
    public func currentTarget(at date: Date = Date()) -> Double {
        guard let entry = targetSchedule.entry(at: date) else { return 100 }
        return (entry.low + entry.high) / 2
    }
    
    /// Get current target range
    public func currentTargetRange(at date: Date = Date()) -> (low: Double, high: Double) {
        guard let entry = targetSchedule.entry(at: date) else { return (100, 110) }
        return (entry.low, entry.high)
    }
}

// MARK: - Schedule Entry Types

/// Basal rate schedule entry
public struct BasalScheduleEntry: ScheduleEntry, Equatable {
    public let startTime: TimeInterval
    public let rate: Double  // U/hr
    
    public init(startTime: TimeInterval, rate: Double) {
        self.startTime = startTime
        self.rate = rate
    }
    
    /// Create from hour:minute string (e.g., "08:30")
    public init?(time: String, rate: Double) {
        guard let seconds = Self.parseTime(time) else { return nil }
        self.startTime = seconds
        self.rate = rate
    }
    
    private static func parseTime(_ time: String) -> TimeInterval? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60)
    }
}

/// Insulin Sensitivity Factor schedule entry
public struct ISFScheduleEntry: ScheduleEntry, Equatable {
    public let startTime: TimeInterval
    public let sensitivity: Double  // mg/dL per U
    
    public init(startTime: TimeInterval, sensitivity: Double) {
        self.startTime = startTime
        self.sensitivity = sensitivity
    }
    
    public init?(time: String, sensitivity: Double) {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        self.startTime = TimeInterval(hours * 3600 + minutes * 60)
        self.sensitivity = sensitivity
    }
}

/// Insulin-to-Carb Ratio schedule entry
public struct ICRScheduleEntry: ScheduleEntry, Equatable {
    public let startTime: TimeInterval
    public let ratio: Double  // grams per U
    
    public init(startTime: TimeInterval, ratio: Double) {
        self.startTime = startTime
        self.ratio = ratio
    }
    
    public init?(time: String, ratio: Double) {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        self.startTime = TimeInterval(hours * 3600 + minutes * 60)
        self.ratio = ratio
    }
}

/// Target glucose range schedule entry
public struct TargetScheduleEntry: ScheduleEntry, Equatable {
    public let startTime: TimeInterval
    public let low: Double   // mg/dL
    public let high: Double  // mg/dL
    
    public init(startTime: TimeInterval, low: Double, high: Double) {
        self.startTime = startTime
        self.low = low
        self.high = high
    }
    
    public init?(time: String, low: Double, high: Double) {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        self.startTime = TimeInterval(hours * 3600 + minutes * 60)
        self.low = low
        self.high = high
    }
    
    public var midpoint: Double {
        (low + high) / 2
    }
}

// MARK: - Profile Validation

public struct ProfileValidationError: Error, CustomStringConvertible {
    public let message: String
    
    public var description: String { message }
    
    public init(_ message: String) {
        self.message = message
    }
}

extension AlgorithmProfile {
    /// Validate profile settings
    public func validate() throws {
        // Check schedules have entries
        guard !basalSchedule.entries.isEmpty else {
            throw ProfileValidationError("Basal schedule is empty")
        }
        guard !isfSchedule.entries.isEmpty else {
            throw ProfileValidationError("ISF schedule is empty")
        }
        guard !icrSchedule.entries.isEmpty else {
            throw ProfileValidationError("ICR schedule is empty")
        }
        guard !targetSchedule.entries.isEmpty else {
            throw ProfileValidationError("Target schedule is empty")
        }
        
        // Check DIA
        guard dia >= 3 && dia <= 8 else {
            throw ProfileValidationError("DIA must be between 3 and 8 hours")
        }
        
        // Check safety limits
        guard maxBasal > 0 && maxBasal <= 10 else {
            throw ProfileValidationError("Max basal must be between 0 and 10 U/hr")
        }
        guard maxIOB > 0 && maxIOB <= 20 else {
            throw ProfileValidationError("Max IOB must be between 0 and 20 U")
        }
        
        // Check autosens range
        guard autosensMin >= 0.5 && autosensMin <= 1.0 else {
            throw ProfileValidationError("Autosens min must be between 0.5 and 1.0")
        }
        guard autosensMax >= 1.0 && autosensMax <= 2.0 else {
            throw ProfileValidationError("Autosens max must be between 1.0 and 2.0")
        }
        
        // Check individual entries
        for entry in basalSchedule.entries {
            guard entry.rate >= 0 && entry.rate <= maxBasal else {
                throw ProfileValidationError("Basal rate \(entry.rate) exceeds max basal \(maxBasal)")
            }
        }
        
        for entry in isfSchedule.entries {
            guard entry.sensitivity >= 10 && entry.sensitivity <= 500 else {
                throw ProfileValidationError("ISF \(entry.sensitivity) is out of range (10-500)")
            }
        }
        
        for entry in icrSchedule.entries {
            guard entry.ratio >= 1 && entry.ratio <= 100 else {
                throw ProfileValidationError("ICR \(entry.ratio) is out of range (1-100)")
            }
        }
        
        for entry in targetSchedule.entries {
            guard entry.low >= 70 && entry.high <= 180 else {
                throw ProfileValidationError("Target range \(entry.low)-\(entry.high) is out of bounds")
            }
            guard entry.low <= entry.high else {
                throw ProfileValidationError("Target low must be <= high")
            }
        }
    }
}

// MARK: - Profile Builder

/// Convenience builder for creating profiles
public struct ProfileBuilder {
    private var name: String = "Default"
    private var timezone: String = "UTC"
    private var dia: Double = 6.0
    private var basalEntries: [BasalScheduleEntry] = []
    private var isfEntries: [ISFScheduleEntry] = []
    private var icrEntries: [ICRScheduleEntry] = []
    private var targetEntries: [TargetScheduleEntry] = []
    private var maxBasal: Double = 2.0
    private var maxBolus: Double = 10.0
    private var maxIOB: Double = 8.0
    private var maxCOB: Double = 120.0
    private var autosensMax: Double = 1.2
    private var autosensMin: Double = 0.8
    
    public init() {}
    
    public func withName(_ name: String) -> ProfileBuilder {
        var copy = self
        copy.name = name
        return copy
    }
    
    public func withDIA(_ dia: Double) -> ProfileBuilder {
        var copy = self
        copy.dia = dia
        return copy
    }
    
    public func withBasal(at time: String, rate: Double) -> ProfileBuilder {
        var copy = self
        if let entry = BasalScheduleEntry(time: time, rate: rate) {
            copy.basalEntries.append(entry)
        }
        return copy
    }
    
    public func withISF(at time: String, sensitivity: Double) -> ProfileBuilder {
        var copy = self
        if let entry = ISFScheduleEntry(time: time, sensitivity: sensitivity) {
            copy.isfEntries.append(entry)
        }
        return copy
    }
    
    public func withICR(at time: String, ratio: Double) -> ProfileBuilder {
        var copy = self
        if let entry = ICRScheduleEntry(time: time, ratio: ratio) {
            copy.icrEntries.append(entry)
        }
        return copy
    }
    
    public func withTarget(at time: String, low: Double, high: Double) -> ProfileBuilder {
        var copy = self
        if let entry = TargetScheduleEntry(time: time, low: low, high: high) {
            copy.targetEntries.append(entry)
        }
        return copy
    }
    
    public func withMaxBasal(_ maxBasal: Double) -> ProfileBuilder {
        var copy = self
        copy.maxBasal = maxBasal
        return copy
    }
    
    public func withMaxIOB(_ maxIOB: Double) -> ProfileBuilder {
        var copy = self
        copy.maxIOB = maxIOB
        return copy
    }
    
    public func build() -> AlgorithmProfile {
        AlgorithmProfile(
            name: name,
            timezone: timezone,
            dia: dia,
            basalSchedule: Schedule(entries: basalEntries),
            isfSchedule: Schedule(entries: isfEntries),
            icrSchedule: Schedule(entries: icrEntries),
            targetSchedule: Schedule(entries: targetEntries),
            maxBasal: maxBasal,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            autosensMax: autosensMax,
            autosensMin: autosensMin
        )
    }
}

// MARK: - Sample Profiles

extension AlgorithmProfile {
    /// A sample profile for testing
    public static var sample: AlgorithmProfile {
        ProfileBuilder()
            .withName("Sample Profile")
            .withDIA(6.0)
            .withBasal(at: "00:00", rate: 0.8)
            .withBasal(at: "06:00", rate: 1.2)  // Dawn phenomenon
            .withBasal(at: "09:00", rate: 0.9)
            .withBasal(at: "22:00", rate: 0.7)
            .withISF(at: "00:00", sensitivity: 50)
            .withISF(at: "06:00", sensitivity: 40)  // Less sensitive in morning
            .withISF(at: "12:00", sensitivity: 50)
            .withICR(at: "00:00", ratio: 12)
            .withICR(at: "07:00", ratio: 10)   // More insulin for breakfast
            .withICR(at: "12:00", ratio: 12)
            .withICR(at: "18:00", ratio: 11)
            .withTarget(at: "00:00", low: 100, high: 110)
            .withTarget(at: "06:00", low: 90, high: 100)   // Tighter during day
            .withTarget(at: "22:00", low: 110, high: 120)  // Higher at night
            .withMaxBasal(3.0)
            .withMaxIOB(8.0)
            .build()
    }
}
