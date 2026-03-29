// SPDX-License-Identifier: MIT
//
// AGPProfileTests.swift
// T1PalCoreTests
//
// Tests for AGPProfile computation
// Trace: DATA-AGP-001

import Foundation
import Testing
@testable import T1PalCore

@Suite("AGP Profile")
struct AGPProfileTests {
    
    // MARK: - Basic Computation
    
    @Test("Compute AGP from glucose readings")
    func computeFromReadings() {
        // Create readings spread across the day
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())
        
        var readings: [(timestamp: Date, glucose: Double)] = []
        for hour in 0..<24 {
            let timestamp = calendar.date(byAdding: .hour, value: hour, to: baseDate)!
            // Simulate typical glucose pattern: higher in morning, lower at night
            let glucose = 100.0 + Double(hour) * 2 + Double.random(in: -10...10)
            readings.append((timestamp, glucose))
        }
        
        let profile = AGPProfile.compute(from: readings, days: 1)
        
        #expect(profile.slots.count == 48)
        #expect(profile.daysAnalyzed == 1)
        #expect(profile.avgGlucose > 0)
        #expect(profile.timeInRange >= 0 && profile.timeInRange <= 1)
    }
    
    @Test("Empty profile has default values")
    func emptyProfile() {
        let empty = AGPProfile.empty
        
        #expect(empty.slots.count == 48)
        #expect(empty.daysAnalyzed == 0)
        #expect(empty.avgGlucose == 120)
        #expect(empty.timeInRange == 0.7)
    }
    
    // MARK: - Time Slot
    
    @Test("Time slot index calculation")
    func timeSlotIndex() {
        let slot0 = AGPTimeSlot(hour: 0, minute: 0, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(slot0.slotIndex == 0)
        
        let slot1 = AGPTimeSlot(hour: 0, minute: 30, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(slot1.slotIndex == 1)
        
        let slot23 = AGPTimeSlot(hour: 11, minute: 30, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(slot23.slotIndex == 23)
        
        let slot47 = AGPTimeSlot(hour: 23, minute: 30, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(slot47.slotIndex == 47)
    }
    
    @Test("Time string formatting")
    func timeStringFormatting() {
        let slot = AGPTimeSlot(hour: 8, minute: 30, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(slot.timeString == "08:30")
        
        let midnight = AGPTimeSlot(hour: 0, minute: 0, p10: 80, p25: 90, p50: 100, p75: 110, p90: 120)
        #expect(midnight.timeString == "00:00")
    }
    
    // MARK: - GMI Calculation
    
    @Test("GMI calculation from average glucose")
    func gmiCalculation() {
        // GMI formula: (avg glucose in mg/dL * 0.0347) + 2.59
        let readings: [(timestamp: Date, glucose: Double)] = [
            (Date(), 120),
            (Date(), 120),
            (Date(), 120)
        ]
        
        let profile = AGPProfile.compute(from: readings, days: 1)
        
        // Expected GMI = (120 * 0.0347) + 2.59 = 6.754
        #expect(abs(profile.gmi - 6.754) < 0.1)
    }
    
    @Test("GMI category classification")
    func gmiCategory() {
        // Test various GMI values
        let normalProfile = AGPProfile(
            slots: [], daysAnalyzed: 1, timeInRange: 0.9, avgGlucose: 90, gmi: 5.0, cv: 25
        )
        #expect(normalProfile.gmiCategory == "Normal")
        
        let wellControlled = AGPProfile(
            slots: [], daysAnalyzed: 1, timeInRange: 0.8, avgGlucose: 130, gmi: 6.8, cv: 30
        )
        #expect(wellControlled.gmiCategory == "Well controlled")
        
        let high = AGPProfile(
            slots: [], daysAnalyzed: 1, timeInRange: 0.4, avgGlucose: 200, gmi: 9.5, cv: 45
        )
        #expect(high.gmiCategory == "High")
    }
    
    // MARK: - Time in Range
    
    @Test("Time in range calculation")
    func timeInRangeCalculation() {
        // 8 readings: 6 in range (70-180), 2 out of range
        let readings: [(timestamp: Date, glucose: Double)] = [
            (Date(), 100),  // in range
            (Date(), 150),  // in range
            (Date(), 180),  // in range
            (Date(), 70),   // in range
            (Date(), 120),  // in range
            (Date(), 90),   // in range
            (Date(), 60),   // below range
            (Date(), 200)   // above range
        ]
        
        let profile = AGPProfile.compute(from: readings, days: 1)
        
        #expect(profile.timeInRange == 0.75) // 6/8 = 0.75
        #expect(profile.timeInRangePercent == 75)
    }
    
    // MARK: - CV Calculation
    
    @Test("CV in target detection")
    func cvInTarget() {
        let goodCV = AGPProfile(
            slots: [], daysAnalyzed: 1, timeInRange: 0.8, avgGlucose: 120, gmi: 6.76, cv: 30
        )
        #expect(goodCV.cvInTarget == true)
        
        let highCV = AGPProfile(
            slots: [], daysAnalyzed: 1, timeInRange: 0.6, avgGlucose: 140, gmi: 7.45, cv: 45
        )
        #expect(highCV.cvInTarget == false)
    }
    
    // MARK: - GlucoseReading Integration
    
    @Test("Compute from GlucoseReading array")
    func computeFromGlucoseReadings() {
        let readings = [
            GlucoseReading(glucose: 100, timestamp: Date(), trend: .flat, source: "demo"),
            GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat, source: "demo"),
            GlucoseReading(glucose: 140, timestamp: Date(), trend: .flat, source: "demo")
        ]
        
        let profile = AGPProfile.compute(from: readings, days: 1)
        
        #expect(profile.avgGlucose == 120)
        #expect(profile.timeInRange == 1.0) // All readings in range
    }
}
