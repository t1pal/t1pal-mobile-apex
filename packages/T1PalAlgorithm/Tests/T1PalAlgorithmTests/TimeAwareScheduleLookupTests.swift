// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TimeAwareScheduleLookupTests.swift
// T1Pal Mobile
//
// Tests for ALG-FIX-T5-003: Time-aware schedule lookup
// Trace: ALG-DIAG-T5-003

import Testing
import Foundation
import T1PalCore
@testable import T1PalAlgorithm

@Suite("Time-Aware Schedule Lookup")
struct TimeAwareScheduleLookupTests {
    
    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
    
    // MARK: - Basal Rate Lookup
    
    @Suite("Basal Rate Lookup")
    struct BasalRateLookup {
        private func makeDate(hour: Int, minute: Int) -> Date {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0
            return Calendar.current.date(from: components)!
        }
        
        @Test("Single entry returns rate")
        func singleEntryReturnsRate() {
            let rates = [BasalRate(startTime: 0, rate: 1.0)]
            let noon = makeDate(hour: 12, minute: 0)
            
            #expect(rates.rateAt(date: noon) == 1.0)
        }
        
        @Test("Multiple entries selects correct rate")
        func multipleEntriesSelectsCorrectRate() {
            // Schedule: 0:00=0.8, 6:00=1.2, 22:00=0.6
            let rates = [
                BasalRate(startTime: 0, rate: 0.8),      // midnight
                BasalRate(startTime: 6 * 3600, rate: 1.2),  // 6 AM
                BasalRate(startTime: 22 * 3600, rate: 0.6)  // 10 PM
            ]
            
            // At 3 AM - should use midnight rate (0.8)
            #expect(rates.rateAt(date: makeDate(hour: 3, minute: 0)) == 0.8)
            
            // At 6 AM exactly - should use 6 AM rate (1.2)
            #expect(rates.rateAt(date: makeDate(hour: 6, minute: 0)) == 1.2)
            
            // At 12 PM - should use 6 AM rate (1.2)
            #expect(rates.rateAt(date: makeDate(hour: 12, minute: 0)) == 1.2)
            
            // At 10 PM - should use 10 PM rate (0.6)
            #expect(rates.rateAt(date: makeDate(hour: 22, minute: 0)) == 0.6)
            
            // At 11:30 PM - should still use 10 PM rate (0.6)
            #expect(rates.rateAt(date: makeDate(hour: 23, minute: 30)) == 0.6)
        }
        
        @Test("Empty array returns nil")
        func emptyArrayReturnsNil() {
            let rates: [BasalRate] = []
            #expect(rates.rateAt(date: Date()) == nil)
        }
        
        @Test("Unsorted array still works")
        func unsortedArrayStillWorks() {
            // Entries out of order - should still work
            let rates = [
                BasalRate(startTime: 22 * 3600, rate: 0.6),
                BasalRate(startTime: 0, rate: 0.8),
                BasalRate(startTime: 6 * 3600, rate: 1.2)
            ]
            
            #expect(rates.rateAt(date: makeDate(hour: 12, minute: 0)) == 1.2)
        }
    }
    
    // MARK: - Sensitivity Factor Lookup
    
    @Suite("Sensitivity Factor Lookup")
    struct SensitivityFactorLookup {
        private func makeDate(hour: Int, minute: Int) -> Date {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0
            return Calendar.current.date(from: components)!
        }
        
        @Test("Multiple entries returns correct factor")
        func multipleEntriesReturnsCorrectFactor() {
            let factors = [
                SensitivityFactor(startTime: 0, factor: 50),
                SensitivityFactor(startTime: 12 * 3600, factor: 40)  // noon
            ]
            
            #expect(factors.factorAt(date: makeDate(hour: 8, minute: 0)) == 50)
            #expect(factors.factorAt(date: makeDate(hour: 14, minute: 0)) == 40)
        }
    }
    
    // MARK: - Carb Ratio Lookup
    
    @Suite("Carb Ratio Lookup")
    struct CarbRatioLookup {
        private func makeDate(hour: Int, minute: Int) -> Date {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            components.second = 0
            return Calendar.current.date(from: components)!
        }
        
        @Test("Multiple entries returns correct ratio")
        func multipleEntriesReturnsCorrectRatio() {
            let ratios = [
                CarbRatio(startTime: 0, ratio: 10),
                CarbRatio(startTime: 7 * 3600, ratio: 8),  // breakfast
                CarbRatio(startTime: 12 * 3600, ratio: 12) // lunch
            ]
            
            #expect(ratios.ratioAt(date: makeDate(hour: 6, minute: 0)) == 10)
            #expect(ratios.ratioAt(date: makeDate(hour: 9, minute: 0)) == 8)
            #expect(ratios.ratioAt(date: makeDate(hour: 15, minute: 0)) == 12)
        }
    }
}
