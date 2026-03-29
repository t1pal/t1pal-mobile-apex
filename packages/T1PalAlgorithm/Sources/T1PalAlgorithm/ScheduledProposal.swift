// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ScheduledProposal.swift
// T1PalAlgorithm
//
// Scheduled effect proposals for composing diabetes workflows in advance
// Architecture: docs/architecture/REMOTE-AGENT-EFFECT-PROPOSALS.md
// Backlog: SCHED-001
//

import Foundation

// MARK: - Scheduled Proposal

/// A proposal scheduled to activate at a future time
public struct ScheduledProposal: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let effectBundle: EffectBundle
    public let startTime: Date
    public let recurrence: RecurrenceRule?
    public let createdAt: Date
    public var isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        effectBundle: EffectBundle,
        startTime: Date,
        recurrence: RecurrenceRule? = nil,
        createdAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.effectBundle = effectBundle
        self.startTime = startTime
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }
    
    /// Check if proposal should activate now
    public func shouldActivate(at time: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        return time >= startTime && time <= startTime.addingTimeInterval(60) // 1 minute window
    }
    
    /// Get next occurrence based on recurrence rule
    public func nextOccurrence(after date: Date = Date()) -> Date? {
        guard let recurrence = recurrence else {
            // One-time: return startTime if in future
            return startTime > date ? startTime : nil
        }
        return recurrence.nextOccurrence(after: date, from: startTime)
    }
    
    /// Check if this is a one-time proposal
    public var isOneTime: Bool {
        recurrence == nil
    }
    
    /// Human-readable schedule description
    public var scheduleDescription: String {
        if let recurrence = recurrence {
            return recurrence.description
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Once at \(formatter.string(from: startTime))"
        }
    }
}

// MARK: - Recurrence Rule

/// Rule for recurring scheduled proposals (inspired by iCalendar RRULE)
public struct RecurrenceRule: Codable, Sendable {
    public enum Frequency: String, Codable, Sendable {
        case daily
        case weekly
        case monthly
    }
    
    public enum Weekday: Int, Codable, Sendable, CaseIterable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7
        
        public var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
    }
    
    public let frequency: Frequency
    public let interval: Int  // Every N days/weeks/months
    public let daysOfWeek: [Weekday]?  // For weekly: which days
    public let until: Date?  // End date (nil = forever)
    public let count: Int?  // Max occurrences (nil = unlimited)
    
    public init(
        frequency: Frequency,
        interval: Int = 1,
        daysOfWeek: [Weekday]? = nil,
        until: Date? = nil,
        count: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.daysOfWeek = daysOfWeek
        self.until = until
        self.count = count
    }
    
    /// Calculate next occurrence after a given date
    public func nextOccurrence(after date: Date, from originalStart: Date) -> Date? {
        let calendar = Calendar.current
        
        // Extract time components from original start
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: originalStart)
        
        switch frequency {
        case .daily:
            // Next day at same time
            var candidate = calendar.startOfDay(for: date)
            candidate = calendar.date(byAdding: .day, value: interval, to: candidate) ?? candidate
            candidate = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                      minute: timeComponents.minute ?? 0,
                                      second: 0, of: candidate) ?? candidate
            return checkBounds(candidate)
            
        case .weekly:
            guard let days = daysOfWeek, !days.isEmpty else {
                // Default: same day of week as original
                let weekday = calendar.component(.weekday, from: originalStart)
                return nextWeekday(weekday, after: date, time: timeComponents)
            }
            
            // Find next matching weekday
            var candidates: [Date] = []
            for day in days {
                if let next = nextWeekday(day.rawValue, after: date, time: timeComponents) {
                    candidates.append(next)
                }
            }
            return candidates.min().flatMap(checkBounds)
            
        case .monthly:
            // Same day of month
            let dayOfMonth = calendar.component(.day, from: originalStart)
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = dayOfMonth
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            guard var candidate = calendar.date(from: components) else { return nil }
            if candidate <= date {
                candidate = calendar.date(byAdding: .month, value: interval, to: candidate) ?? candidate
            }
            return checkBounds(candidate)
        }
    }
    
    private func nextWeekday(_ weekday: Int, after date: Date, time: DateComponents) -> Date? {
        let calendar = Calendar.current
        var candidate = calendar.startOfDay(for: date)
        
        // Find next occurrence of this weekday
        while calendar.component(.weekday, from: candidate) != weekday || candidate <= date {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        
        // Set time
        candidate = calendar.date(bySettingHour: time.hour ?? 0,
                                  minute: time.minute ?? 0,
                                  second: 0, of: candidate) ?? candidate
        return candidate
    }
    
    private func checkBounds(_ date: Date) -> Date? {
        if let until = until, date > until {
            return nil
        }
        return date
    }
    
    public var description: String {
        var parts: [String] = []
        
        switch frequency {
        case .daily:
            parts.append(interval == 1 ? "Daily" : "Every \(interval) days")
        case .weekly:
            if let days = daysOfWeek, !days.isEmpty {
                let dayNames = days.map(\.shortName).joined(separator: ", ")
                parts.append(interval == 1 ? "Weekly on \(dayNames)" : "Every \(interval) weeks on \(dayNames)")
            } else {
                parts.append(interval == 1 ? "Weekly" : "Every \(interval) weeks")
            }
        case .monthly:
            parts.append(interval == 1 ? "Monthly" : "Every \(interval) months")
        }
        
        if let until = until {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            parts.append("until \(formatter.string(from: until))")
        }
        
        return parts.joined(separator: " ")
    }
}

// MARK: - Preset Factories

extension ScheduledProposal {
    
    /// Create a pre-meal scheduling preset
    public static func preMeal(
        name: String = "Pre-meal",
        activateIn minutes: Int,
        sensitivityFactor: Double = 0.9,
        durationMinutes: Int = 120
    ) -> ScheduledProposal {
        let startTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let validUntil = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        
        let effect = AnyEffect.sensitivity(SensitivityEffectSpec(
            confidence: 0.8,
            factor: sensitivityFactor,
            durationMinutes: durationMinutes
        ))
        
        let bundle = EffectBundle(
            agent: "scheduled.preMeal",
            validFrom: startTime,
            validUntil: validUntil,
            effects: [effect],
            reason: "Scheduled pre-meal adjustment"
        )
        
        return ScheduledProposal(
            name: name,
            effectBundle: bundle,
            startTime: startTime
        )
    }
    
    /// Create a daily sleep mode preset
    public static func sleepMode(
        name: String = "Sleep Mode",
        hour: Int,
        minute: Int = 0,
        durationHours: Int = 8,
        targetGlucose: Double = 110
    ) -> ScheduledProposal {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        
        var startTime = calendar.date(from: components) ?? Date()
        if startTime < Date() {
            startTime = calendar.date(byAdding: .day, value: 1, to: startTime) ?? startTime
        }
        
        let validUntil = startTime.addingTimeInterval(TimeInterval(durationHours * 3600))
        
        // Sleep mode uses sensitivity adjustment (typically more sensitive at night)
        let effect = AnyEffect.sensitivity(SensitivityEffectSpec(
            confidence: 0.7,
            factor: 0.9,  // More sensitive at night
            durationMinutes: durationHours * 60
        ))
        
        let bundle = EffectBundle(
            agent: "scheduled.sleepMode",
            validFrom: startTime,
            validUntil: validUntil,
            effects: [effect],
            reason: "Scheduled sleep mode (target: \(Int(targetGlucose)) mg/dL)"
        )
        
        let recurrence = RecurrenceRule(frequency: .daily)
        
        return ScheduledProposal(
            name: name,
            effectBundle: bundle,
            startTime: startTime,
            recurrence: recurrence
        )
    }
    
    /// Create a recurring exercise preset
    public static func exercise(
        name: String = "Exercise",
        daysOfWeek: [RecurrenceRule.Weekday],
        hour: Int,
        minute: Int = 0,
        durationMinutes: Int = 90,
        sensitivityFactor: Double = 1.3
    ) -> ScheduledProposal {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        
        var startTime = calendar.date(from: components) ?? Date()
        if startTime < Date() {
            startTime = calendar.date(byAdding: .day, value: 1, to: startTime) ?? startTime
        }
        
        let validUntil = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        
        let effect = AnyEffect.sensitivity(SensitivityEffectSpec(
            confidence: 0.8,
            factor: sensitivityFactor,
            durationMinutes: durationMinutes
        ))
        
        let bundle = EffectBundle(
            agent: "scheduled.exercise",
            validFrom: startTime,
            validUntil: validUntil,
            effects: [effect],
            reason: "Scheduled exercise adjustment"
        )
        
        let recurrence = RecurrenceRule(frequency: .weekly, daysOfWeek: daysOfWeek)
        
        return ScheduledProposal(
            name: name,
            effectBundle: bundle,
            startTime: startTime,
            recurrence: recurrence
        )
    }
}
