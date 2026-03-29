// SPDX-License-Identifier: MIT
//
// TrioFeatureParityTests.swift
// T1PalAlgorithmTests
//
// Tests for Trio feature parity: SMB scheduling, B30, override percentage
// Trace: ALG-TRIO-001, ALG-TRIO-002, ALG-TRIO-003

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - ALG-TRIO-003: SMB Scheduling Tests

@Suite("SMB Schedule Window")
struct SMBScheduleWindowTests {
    
    @Test("Normal range contains hour")
    func normalRangeContainsHour() {
        // 8 AM to 10 AM window
        let window = SMBScheduleWindow(startHour: 8, endHour: 10, smbDisabled: true)
        
        #expect(!window.contains(hour: 7))
        #expect(window.contains(hour: 8))
        #expect(window.contains(hour: 9))
        #expect(window.contains(hour: 10))
        #expect(!window.contains(hour: 11))
    }
    
    @Test("Overnight range contains hour")
    func overnightRangeContainsHour() {
        // 10 PM to 6 AM window (overnight)
        let window = SMBScheduleWindow(startHour: 22, endHour: 6, smbDisabled: true)
        
        #expect(window.contains(hour: 22))
        #expect(window.contains(hour: 23))
        #expect(window.contains(hour: 0))
        #expect(window.contains(hour: 3))
        #expect(window.contains(hour: 6))
        #expect(!window.contains(hour: 7))
        #expect(!window.contains(hour: 12))
        #expect(!window.contains(hour: 21))
    }
    
    @Test("Overnight preset")
    func overnightPreset() {
        let window = SMBScheduleWindow.overnight
        #expect(window.startHour == 22)
        #expect(window.endHour == 6)
        #expect(window.smbDisabled)
    }
    
    @Test("Morning preset")
    func morningPreset() {
        let window = SMBScheduleWindow.morning
        #expect(window.startHour == 5)
        #expect(window.endHour == 9)
        #expect(!window.smbDisabled)
    }
}

@Suite("SMB Scheduling")
struct SMBSchedulingTests {
    
    @Test("Schedule disabled by default")
    func scheduleDisabledByDefault() {
        let settings = SMBSettings()
        #expect(!settings.scheduleEnabled)
        #expect(settings.scheduleWindows.isEmpty)
    }
    
    @Test("Is scheduled off when disabled")
    func isScheduledOffWhenDisabled() {
        let settings = SMBSettings(scheduleEnabled: false)
        #expect(!settings.isScheduledOff())
    }
    
    @Test("Is scheduled off with no windows")
    func isScheduledOffWithNoWindows() {
        let settings = SMBSettings(scheduleEnabled: true, scheduleWindows: [])
        #expect(!settings.isScheduledOff())
    }
    
    @Test("Is scheduled off in window")
    func isScheduledOffInWindow() {
        let window = SMBScheduleWindow(startHour: 22, endHour: 6, smbDisabled: true)
        let settings = SMBSettings(
            enabled: true,
            scheduleEnabled: true,
            scheduleWindows: [window]
        )
        
        // Create date at 11 PM (23:00)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 23
        components.minute = 0
        let nightTime = Calendar.current.date(from: components)!
        
        #expect(settings.isScheduledOff(at: nightTime))
        
        // Create date at 2 PM (14:00) - should NOT be scheduled off
        components.hour = 14
        let dayTime = Calendar.current.date(from: components)!
        
        #expect(!settings.isScheduledOff(at: dayTime))
    }
    
    @Test("SMB calculator respects schedule")
    func smbCalculatorRespectsSchedule() {
        let window = SMBScheduleWindow(startHour: 22, endHour: 6, smbDisabled: true)
        let settings = SMBSettings(
            enabled: true,
            maxSMB: 1.0,
            scheduleEnabled: true,
            scheduleWindows: [window]
        )
        
        let calculator = SMBCalculator(settings: settings)
        
        // Create date at 3 AM (in scheduled-off window)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        let nightTime = Calendar.current.date(from: components)!
        
        let result = calculator.calculate(
            currentBG: 180,
            eventualBG: 200,
            minPredBG: 120,
            targetBG: 100,
            iob: 1.0,
            cob: 20,
            sens: 50,
            maxBasal: 2.0,
            lastSMBTime: nil,
            hasTempTarget: false,
            currentTime: nightTime
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("scheduled off"))
    }
    
    @Test("SMB calculator allows outside schedule")
    func smbCalculatorAllowsOutsideSchedule() {
        let window = SMBScheduleWindow(startHour: 22, endHour: 6, smbDisabled: true)
        let settings = SMBSettings(
            enabled: true,
            maxSMB: 1.0,
            enableAlways: true,
            maxIOBForSMB: 10.0,
            scheduleEnabled: true,
            scheduleWindows: [window]
        )
        
        let calculator = SMBCalculator(settings: settings)
        
        // Create date at 2 PM (outside scheduled-off window)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        components.minute = 0
        let dayTime = Calendar.current.date(from: components)!
        
        let result = calculator.calculate(
            currentBG: 180,
            eventualBG: 200,
            minPredBG: 120,
            targetBG: 100,
            iob: 1.0,
            cob: 20,
            sens: 50,
            maxBasal: 2.0,
            lastSMBTime: nil,
            hasTempTarget: false,
            currentTime: dayTime
        )
        
        // Should be allowed (not blocked by schedule)
        #expect(!result.reason.contains("scheduled off"))
    }
}

// MARK: - ALG-TRIO-002: B30 Boost 30 Minutes Tests

@Suite("Boost30 Settings")
struct Boost30SettingsTests {
    
    @Test("Default settings disabled")
    func defaultSettingsDisabled() {
        let settings = Boost30Settings.default
        #expect(!settings.enabled)
    }
    
    @Test("Standard preset")
    func standardPreset() {
        let settings = Boost30Settings.standard
        #expect(settings.enabled)
        #expect(settings.durationMinutes == 30)
        #expect(settings.isfFactor == 0.8)
        #expect(settings.crFactor == 0.9)
        #expect(settings.boostSMB)
        #expect(settings.smbMaxMultiplier == 1.5)
        #expect(settings.minCarbsToTrigger == 10)
        #expect(!settings.morningOnly)
    }
    
    @Test("Morning boost preset")
    func morningBoostPreset() {
        let settings = Boost30Settings.morningBoost
        #expect(settings.enabled)
        #expect(settings.morningOnly)
        #expect(settings.morningStartHour == 5)
        #expect(settings.morningEndHour == 10)
    }
    
    @Test("Factor clamping")
    func factorClamping() {
        // ISF factor should be clamped to 0.5-1.0
        let settings = Boost30Settings(enabled: true, isfFactor: 0.3, crFactor: 1.5)
        #expect(settings.isfFactor == 0.5)  // Clamped to min
        #expect(settings.crFactor == 1.0)   // Clamped to max
    }
    
    @Test("SMB multiplier clamping")
    func smbMultiplierClamping() {
        let settings = Boost30Settings(enabled: true, smbMaxMultiplier: 5.0)
        #expect(settings.smbMaxMultiplier == 3.0)  // Clamped to max
    }
}

@Suite("Boost30 Calculator")
struct Boost30CalculatorTests {
    
    @Test("Disabled returns inactive")
    func disabledReturnsInactive() {
        let calculator = Boost30Calculator(settings: .default)
        let result = calculator.evaluate(recentCarbs: [(Date(), 50)])
        
        #expect(!result.isActive)
        #expect(result.isfFactor == 1.0)
        #expect(result.crFactor == 1.0)
        #expect(result.reason.contains("disabled"))
    }
    
    @Test("Activates with recent carbs")
    func activatesWithRecentCarbs() {
        let settings = Boost30Settings.standard
        let calculator = Boost30Calculator(settings: settings)
        
        // Carbs 10 minutes ago
        let carbTime = Date().addingTimeInterval(-10 * 60)
        let result = calculator.evaluate(recentCarbs: [(carbTime, 30)])
        
        #expect(result.isActive)
        #expect(result.isfFactor == 0.8)
        #expect(result.crFactor == 0.9)
        #expect(result.smbMaxMultiplier == 1.5)
        #expect(result.remainingMinutes != nil)
        #expect(result.triggeringCarbGrams == 30)
    }
    
    @Test("Does not activate after window")
    func doesNotActivateAfterWindow() {
        let settings = Boost30Settings.standard
        let calculator = Boost30Calculator(settings: settings)
        
        // Carbs 45 minutes ago (outside 30-min window)
        let carbTime = Date().addingTimeInterval(-45 * 60)
        let result = calculator.evaluate(recentCarbs: [(carbTime, 30)])
        
        #expect(!result.isActive)
        #expect(result.isfFactor == 1.0)
    }
    
    @Test("Does not activate with small carbs")
    func doesNotActivateWithSmallCarbs() {
        let settings = Boost30Settings(enabled: true, minCarbsToTrigger: 20)
        let calculator = Boost30Calculator(settings: settings)
        
        // Only 10g carbs (below 20g threshold)
        let carbTime = Date().addingTimeInterval(-5 * 60)
        let result = calculator.evaluate(recentCarbs: [(carbTime, 10)])
        
        #expect(!result.isActive)
        #expect(result.reason.contains("No qualifying"))
    }
    
    @Test("Morning only restriction")
    func morningOnlyRestriction() {
        let settings = Boost30Settings.morningBoost  // Morning only: 5 AM - 10 AM
        let calculator = Boost30Calculator(settings: settings)
        
        // Create date at 2 PM (outside morning window)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        components.minute = 0
        let afternoonTime = Calendar.current.date(from: components)!
        
        // Carbs 5 minutes ago from 2 PM
        let carbTime = afternoonTime.addingTimeInterval(-5 * 60)
        let result = calculator.evaluate(
            recentCarbs: [(carbTime, 30)],
            currentTime: afternoonTime
        )
        
        #expect(!result.isActive)
        #expect(result.reason.contains("morning-only"))
    }
    
    @Test("Morning only allows in window")
    func morningOnlyAllowsInWindow() {
        let settings = Boost30Settings.morningBoost  // Morning only: 5 AM - 10 AM
        let calculator = Boost30Calculator(settings: settings)
        
        // Create date at 7 AM (inside morning window)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        let morningTime = Calendar.current.date(from: components)!
        
        // Carbs 5 minutes ago from 7 AM
        let carbTime = morningTime.addingTimeInterval(-5 * 60)
        let result = calculator.evaluate(
            recentCarbs: [(carbTime, 30)],
            currentTime: morningTime
        )
        
        #expect(result.isActive)
    }
    
    @Test("Remaining minutes calculation")
    func remainingMinutesCalculation() {
        let settings = Boost30Settings.standard  // 30 minute duration
        let calculator = Boost30Calculator(settings: settings)
        
        // Carbs 10 minutes ago -> 20 minutes remaining
        let carbTime = Date().addingTimeInterval(-10 * 60)
        let result = calculator.evaluate(recentCarbs: [(carbTime, 30)])
        
        #expect(result.isActive)
        #expect(result.remainingMinutes != nil)
        // Allow some tolerance for test execution time
        #expect(result.remainingMinutes! >= 19 && result.remainingMinutes! <= 21)
    }
    
    @Test("Selects most recent qualifying carb")
    func selectsMostRecentQualifyingCarb() {
        let settings = Boost30Settings.standard
        let calculator = Boost30Calculator(settings: settings)
        
        let now = Date()
        let recentCarbs: [(timestamp: Date, grams: Double)] = [
            (now.addingTimeInterval(-25 * 60), 20),  // 25 min ago, still in window
            (now.addingTimeInterval(-5 * 60), 15),   // 5 min ago, most recent
            (now.addingTimeInterval(-40 * 60), 30)   // 40 min ago, outside window
        ]
        
        let result = calculator.evaluate(recentCarbs: recentCarbs)
        
        #expect(result.isActive)
        #expect(result.triggeringCarbGrams == 15)  // Should use most recent
    }
    
    @Test("SMB boost disabled")
    func smbBoostDisabled() {
        let settings = Boost30Settings(
            enabled: true,
            boostSMB: false,
            smbMaxMultiplier: 2.0
        )
        let calculator = Boost30Calculator(settings: settings)
        
        let carbTime = Date().addingTimeInterval(-5 * 60)
        let result = calculator.evaluate(recentCarbs: [(carbTime, 30)])
        
        #expect(result.isActive)
        #expect(result.smbMaxMultiplier == 1.0)  // No boost even though multiplier set
    }
}

// MARK: - ALG-TRIO-001: Profile Override Tests (Already Implemented)

@Suite("Profile Override Integration")
struct ProfileOverrideIntegrationTests {
    
    @Test("Exercise preset")
    func exercisePreset() {
        let override = ProfileOverride.exercise
        #expect(override.percentage == 80)
        #expect(override.durationMinutes == 60)
        #expect(!override.disableSMB)
    }
    
    @Test("Illness preset")
    func illnessPreset() {
        let override = ProfileOverride.illness
        #expect(override.percentage == 120)
        #expect(override.isIndefinite)
    }
    
    @Test("Override factor calculation")
    func overrideFactorCalculation() {
        let override = ProfileOverride(name: "Test", percentage: 80)
        #expect(override.factor == 0.8)
        
        // 80% means less insulin sensitivity (ISF goes up)
        // baseISF 50 / 0.8 = 62.5 (larger ISF = less insulin per mg/dL drop)
        #expect(override.adjustedISF(50) == 62.5)
    }
    
    @Test("Pre-meal preset")
    func preMealPreset() {
        let override = ProfileOverride.preMeal
        #expect(override.percentage == 110)
        #expect(override.durationMinutes == 60)
        #expect(override.targetOverride == 80)
    }
}
