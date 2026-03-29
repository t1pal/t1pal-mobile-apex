// TimeBlockCalculator.swift
// T1PalAlgorithm
//
// Time block calculator for adaptive scheduling
// Source: GlucOS AdaptiveSchedule pattern
// Trace: GLUCOS-IMPL-001, ADR-010

import Foundation

/// Time block calculator for 6-block daily schedules
///
/// GlucOS uses 6 time blocks of 4 hours each:
/// - Block 0: 00:00 - 04:00 (Night)
/// - Block 1: 04:00 - 08:00 (Dawn)
/// - Block 2: 08:00 - 12:00 (Morning)
/// - Block 3: 12:00 - 16:00 (Afternoon)
/// - Block 4: 16:00 - 20:00 (Evening)
/// - Block 5: 20:00 - 24:00 (Late evening)
public struct TimeBlockCalculator: Sendable {
    /// Block duration in seconds (4 hours)
    public static let blockDuration: TimeInterval = 4 * 60 * 60
    
    /// Total number of blocks per day
    public static let blocksPerDay = 6
    
    /// Block names for display
    public static let blockNames = [
        "Night",
        "Dawn",
        "Morning",
        "Afternoon",
        "Evening",
        "Late Evening"
    ]
    
    public init() {}
    
    /// Get time block for a date (0-5)
    public static func timeBlock(for date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        return hour / 4
    }
    
    /// Get time block for a date (instance method)
    public func block(for date: Date) -> Int {
        Self.timeBlock(for: date)
    }
    
    /// Get start of current block
    public static func blockStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let blockStartHour = (hour / 4) * 4
        return calendar.date(
            bySettingHour: blockStartHour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
    }
    
    /// Get end of current block
    public static func blockEnd(for date: Date) -> Date {
        blockStart(for: date).addingTimeInterval(blockDuration)
    }
    
    /// Get time remaining in current block
    public static func timeRemainingInBlock(at date: Date) -> TimeInterval {
        blockEnd(for: date).timeIntervalSince(date)
    }
    
    /// Get block name for a date
    public static func blockName(for date: Date) -> String {
        let block = timeBlock(for: date)
        return blockNames[block]
    }
    
    /// Get all block boundaries for a day
    public static func blockBoundaries(for date: Date) -> [(start: Date, end: Date, block: Int)] {
        let calendar = Calendar.current
        guard let startOfDay = calendar.startOfDay(for: date) as Date? else {
            return []
        }
        
        return (0..<blocksPerDay).map { block in
            let start = startOfDay.addingTimeInterval(Double(block) * blockDuration)
            let end = start.addingTimeInterval(blockDuration)
            return (start: start, end: end, block: block)
        }
    }
}
