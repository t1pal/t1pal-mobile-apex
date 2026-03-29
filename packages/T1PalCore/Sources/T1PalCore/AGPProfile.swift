// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AGPProfile.swift
// T1PalCore
//
// Ambulatory Glucose Profile (AGP) calculation
// Extracted from SonificationEngine for reuse across apps
//
// Trace: DATA-AGP-001, SON-SRC-005

import Foundation

// MARK: - AGP Time Slot

/// A single time slot in the AGP, representing glucose percentiles at a specific time of day
public struct AGPTimeSlot: Sendable, Codable, Equatable {
    /// Hour of day (0-23)
    public let hour: Int
    /// Minute within hour (typically 0 or 30)
    public let minute: Int
    /// 10th percentile glucose value
    public let p10: Double
    /// 25th percentile glucose value
    public let p25: Double
    /// 50th percentile (median) glucose value
    public let p50: Double
    /// 75th percentile glucose value
    public let p75: Double
    /// 90th percentile glucose value
    public let p90: Double
    
    public init(hour: Int, minute: Int, p10: Double, p25: Double, p50: Double, p75: Double, p90: Double) {
        self.hour = hour
        self.minute = minute
        self.p10 = p10
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
        self.p90 = p90
    }
    
    /// Time string for display (e.g., "08:30")
    public var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }
    
    /// Slot index (0-47 for 30-minute intervals)
    public var slotIndex: Int {
        (hour * 2) + (minute >= 30 ? 1 : 0)
    }
}

// MARK: - AGP Profile

/// Ambulatory Glucose Profile with percentile bands across 24 hours
///
/// AGP is a standardized way to visualize glucose patterns over multiple days.
/// It shows the typical glucose range at each time of day using percentile bands.
///
/// Usage:
/// ```swift
/// let readings = glucoseHistory.map { ($0.timestamp, $0.glucose) }
/// let agp = AGPProfile.compute(from: readings, days: 14)
/// print("Time in range: \(agp.timeInRange * 100)%")
/// print("GMI: \(agp.gmi)%")
/// ```
public struct AGPProfile: Sendable, Codable, Equatable {
    /// Time slots (48 slots for 30-minute intervals across 24 hours)
    public let slots: [AGPTimeSlot]
    
    /// Number of days of data analyzed
    public let daysAnalyzed: Int
    
    /// Time in range (70-180 mg/dL) as a fraction (0.0 to 1.0)
    public let timeInRange: Double
    
    /// Average glucose in mg/dL
    public let avgGlucose: Double
    
    /// Glucose Management Indicator (estimated A1C percentage)
    public let gmi: Double
    
    /// Coefficient of variation (glucose variability, target <36%)
    public let cv: Double
    
    public init(
        slots: [AGPTimeSlot],
        daysAnalyzed: Int,
        timeInRange: Double,
        avgGlucose: Double,
        gmi: Double,
        cv: Double
    ) {
        self.slots = slots
        self.daysAnalyzed = daysAnalyzed
        self.timeInRange = timeInRange
        self.avgGlucose = avgGlucose
        self.gmi = gmi
        self.cv = cv
    }
    
    // MARK: - Computed Properties
    
    /// Time in range as a percentage (0-100)
    public var timeInRangePercent: Double {
        timeInRange * 100
    }
    
    /// Time below range (<70 mg/dL) - requires readings to calculate
    public var timeBelowRange: Double? {
        nil  // Would need original readings
    }
    
    /// Time above range (>180 mg/dL) - requires readings to calculate
    public var timeAboveRange: Double? {
        nil  // Would need original readings
    }
    
    /// Whether CV is in target range (<36%)
    public var cvInTarget: Bool {
        cv < 36
    }
    
    /// GMI category description
    public var gmiCategory: String {
        switch gmi {
        case ..<5.7: return "Normal"
        case 5.7..<6.5: return "Pre-diabetes"
        case 6.5..<7.0: return "Well controlled"
        case 7.0..<8.0: return "Moderate"
        case 8.0..<9.0: return "Needs improvement"
        default: return "High"
        }
    }
    
    // MARK: - Factory Methods
    
    /// Generate AGP from multiple days of glucose data
    ///
    /// - Parameters:
    ///   - readings: Array of (timestamp, glucose) tuples
    ///   - days: Number of days the readings span
    /// - Returns: Computed AGP profile
    public static func compute(from readings: [(timestamp: Date, glucose: Double)], days: Int) -> AGPProfile {
        let calendar = Calendar.current
        
        // Group readings by time of day (30-min slots)
        var slotReadings: [[Double]] = Array(repeating: [], count: 48)
        
        for reading in readings {
            let hour = calendar.component(.hour, from: reading.timestamp)
            let minute = calendar.component(.minute, from: reading.timestamp)
            let slotIndex = (hour * 2) + (minute >= 30 ? 1 : 0)
            guard slotIndex < 48 else { continue }
            slotReadings[slotIndex].append(reading.glucose)
        }
        
        // Compute percentiles for each slot
        var slots: [AGPTimeSlot] = []
        for i in 0..<48 {
            let values = slotReadings[i].sorted()
            let hour = i / 2
            let minute = (i % 2) * 30
            
            if values.isEmpty {
                // No data for this slot, interpolate with 100
                slots.append(AGPTimeSlot(hour: hour, minute: minute, p10: 100, p25: 110, p50: 120, p75: 130, p90: 140))
            } else {
                slots.append(AGPTimeSlot(
                    hour: hour,
                    minute: minute,
                    p10: percentile(values, 0.10),
                    p25: percentile(values, 0.25),
                    p50: percentile(values, 0.50),
                    p75: percentile(values, 0.75),
                    p90: percentile(values, 0.90)
                ))
            }
        }
        
        // Compute summary stats
        let allGlucose = readings.map { $0.glucose }
        let avg = allGlucose.isEmpty ? 120 : allGlucose.reduce(0, +) / Double(allGlucose.count)
        let inRange = allGlucose.filter { $0 >= 70 && $0 <= 180 }.count
        let tir = allGlucose.isEmpty ? 0.7 : Double(inRange) / Double(allGlucose.count)
        
        // GMI formula: (avg glucose in mg/dL * 0.0347) + 2.59
        let gmi = (avg * 0.0347) + 2.59
        
        // CV = (standard deviation / mean) * 100
        let variance = allGlucose.isEmpty ? 0 : allGlucose.map { pow($0 - avg, 2) }.reduce(0, +) / Double(allGlucose.count)
        let stdDev = sqrt(variance)
        let cv = avg > 0 ? (stdDev / avg) * 100 : 0
        
        return AGPProfile(slots: slots, daysAnalyzed: days, timeInRange: tir, avgGlucose: avg, gmi: gmi, cv: cv)
    }
    
    /// Compute AGP from GlucoseReading array
    public static func compute(from readings: [GlucoseReading], days: Int) -> AGPProfile {
        let tuples = readings.map { ($0.timestamp, $0.glucose) }
        return compute(from: tuples, days: days)
    }
    
    // MARK: - Private Helpers
    
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = (Double(sorted.count - 1)) * p
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }
    
    // MARK: - Empty Profile
    
    /// An empty AGP profile with default values
    public static let empty = AGPProfile(
        slots: (0..<48).map { i in
            AGPTimeSlot(hour: i / 2, minute: (i % 2) * 30, p10: 100, p25: 110, p50: 120, p75: 130, p90: 140)
        },
        daysAnalyzed: 0,
        timeInRange: 0.7,
        avgGlucose: 120,
        gmi: 6.76,
        cv: 30
    )
}
