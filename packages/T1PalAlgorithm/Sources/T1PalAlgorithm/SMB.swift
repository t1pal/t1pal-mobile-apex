// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SMB.swift
// T1Pal Mobile
//
// Super Micro Bolus (SMB) implementation
// Requirements: REQ-AID-002
//
// Based on oref1 SMB:
// https://github.com/openaps/oref0/blob/master/lib/determine-basal/determine-basal.js

import Foundation

// MARK: - SMB Schedule (ALG-TRIO-003)

/// Time window for SMB scheduling
/// Used to enable/disable SMB during specific hours
public struct SMBScheduleWindow: Codable, Sendable, Equatable {
    /// Start hour (0-23)
    public let startHour: Int
    
    /// End hour (0-23)
    public let endHour: Int
    
    /// Whether SMB is disabled during this window
    public let smbDisabled: Bool
    
    public init(startHour: Int, endHour: Int, smbDisabled: Bool = true) {
        self.startHour = max(0, min(23, startHour))
        self.endHour = max(0, min(23, endHour))
        self.smbDisabled = smbDisabled
    }
    
    /// Check if a given hour falls within this window
    public func contains(hour: Int) -> Bool {
        if startHour <= endHour {
            // Normal range (e.g., 22-6 means 22, 23, 0, 1, 2, 3, 4, 5, 6)
            return hour >= startHour && hour <= endHour
        } else {
            // Overnight range (e.g., 22-6)
            return hour >= startHour || hour <= endHour
        }
    }
    
    /// Overnight window (10 PM - 6 AM) - common sleep schedule
    public static let overnight = SMBScheduleWindow(startHour: 22, endHour: 6, smbDisabled: true)
    
    /// Morning window (5 AM - 9 AM) - breakfast period
    public static let morning = SMBScheduleWindow(startHour: 5, endHour: 9, smbDisabled: false)
}

// MARK: - SMB Settings

/// Configuration for SMB delivery
public struct SMBSettings: Codable, Sendable {
    /// Whether SMB is enabled
    public let enabled: Bool
    
    /// Maximum SMB size (units)
    public let maxSMB: Double
    
    /// Minimum time between SMBs (seconds)
    public let minInterval: TimeInterval
    
    /// Enable SMB with COB (carbs on board)
    public let enableWithCOB: Bool
    
    /// Enable SMB with temp target
    public let enableWithTempTarget: Bool
    
    /// Enable SMB after carbs (for unannounced meals)
    public let enableAfterCarbs: Bool
    
    /// Enable SMB always (most aggressive)
    public let enableAlways: Bool
    
    /// Maximum IOB for SMB to be allowed
    public let maxIOBForSMB: Double
    
    /// Minimum BG for SMB delivery
    public let minBGForSMB: Double
    
    // MARK: - SMB Scheduling (ALG-TRIO-003)
    
    /// Whether schedule-based SMB control is enabled
    public let scheduleEnabled: Bool
    
    /// Schedule windows for SMB enable/disable
    public let scheduleWindows: [SMBScheduleWindow]
    
    public init(
        enabled: Bool = false,
        maxSMB: Double = 1.0,
        minInterval: TimeInterval = 3 * 60,  // 3 minutes
        enableWithCOB: Bool = true,
        enableWithTempTarget: Bool = true,
        enableAfterCarbs: Bool = true,
        enableAlways: Bool = false,
        maxIOBForSMB: Double = 5.0,
        minBGForSMB: Double = 80.0,
        scheduleEnabled: Bool = false,
        scheduleWindows: [SMBScheduleWindow] = []
    ) {
        self.enabled = enabled
        self.maxSMB = maxSMB
        self.minInterval = minInterval
        self.enableWithCOB = enableWithCOB
        self.enableWithTempTarget = enableWithTempTarget
        self.enableAfterCarbs = enableAfterCarbs
        self.enableAlways = enableAlways
        self.maxIOBForSMB = maxIOBForSMB
        self.minBGForSMB = minBGForSMB
        self.scheduleEnabled = scheduleEnabled
        self.scheduleWindows = scheduleWindows
    }
    
    /// Check if SMB is scheduled off at the given time
    /// Returns true if SMB should be disabled based on schedule
    public func isScheduledOff(at date: Date = Date()) -> Bool {
        guard scheduleEnabled, !scheduleWindows.isEmpty else { return false }
        
        let hour = Calendar.current.component(.hour, from: date)
        
        for window in scheduleWindows {
            if window.contains(hour: hour) && window.smbDisabled {
                return true
            }
        }
        
        return false
    }
    
    /// Default (conservative) SMB settings
    public static let `default` = SMBSettings()
    
    /// Aggressive SMB settings (for experienced users)
    public static let aggressive = SMBSettings(
        enabled: true,
        maxSMB: 2.0,
        enableWithCOB: true,
        enableWithTempTarget: true,
        enableAfterCarbs: true,
        enableAlways: true,
        maxIOBForSMB: 8.0,
        minBGForSMB: 70.0
    )
}

// MARK: - SMB Result

/// Result of SMB calculation
public struct SMBResult: Codable, Sendable {
    /// Whether SMB should be delivered
    public let shouldDeliver: Bool
    
    /// SMB units to deliver
    public let units: Double
    
    /// Reason for the decision
    public let reason: String
    
    /// Predicted eventual BG with SMB
    public let eventualBGWithSMB: Double
    
    /// Timestamp
    public let timestamp: Date
    
    public init(
        shouldDeliver: Bool,
        units: Double = 0,
        reason: String,
        eventualBGWithSMB: Double = 0,
        timestamp: Date = Date()
    ) {
        self.shouldDeliver = shouldDeliver
        self.units = units
        self.reason = reason
        self.eventualBGWithSMB = eventualBGWithSMB
        self.timestamp = timestamp
    }
    
    /// No SMB result
    public static func noSMB(reason: String) -> SMBResult {
        SMBResult(shouldDeliver: false, reason: reason)
    }
}

// MARK: - SMB Calculator

/// Calculates SMB based on current state
public struct SMBCalculator: Sendable {
    public let settings: SMBSettings
    
    public init(settings: SMBSettings = .default) {
        self.settings = settings
    }
    
    /// Calculate SMB based on current state
    public func calculate(
        currentBG: Double,
        eventualBG: Double,
        minPredBG: Double,
        targetBG: Double,
        iob: Double,
        cob: Double,
        sens: Double,
        maxBasal: Double,
        lastSMBTime: Date?,
        hasTempTarget: Bool = false,
        currentTime: Date = Date()
    ) -> SMBResult {
        
        // Check if SMB is enabled
        guard settings.enabled else {
            return .noSMB(reason: "SMB disabled")
        }
        
        // Check schedule-based disable (ALG-TRIO-003)
        if settings.isScheduledOff(at: currentTime) {
            let hour = Calendar.current.component(.hour, from: currentTime)
            return .noSMB(reason: "SMB scheduled off at hour \(hour)")
        }
        
        // Check minimum BG
        guard currentBG >= settings.minBGForSMB else {
            return .noSMB(reason: "BG \(Int(currentBG)) below minimum \(Int(settings.minBGForSMB))")
        }
        
        // Check predicted low
        guard minPredBG >= 70 else {
            return .noSMB(reason: "Predicted low \(Int(minPredBG)), no SMB")
        }
        
        // Check IOB limit
        guard iob < settings.maxIOBForSMB else {
            return .noSMB(reason: "IOB \(String(format: "%.2f", iob)) >= maxIOB \(String(format: "%.2f", settings.maxIOBForSMB))")
        }
        
        // Check minimum interval
        if let lastTime = lastSMBTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < settings.minInterval {
                let remaining = Int((settings.minInterval - elapsed) / 60)
                return .noSMB(reason: "SMB interval: \(remaining) min remaining")
            }
        }
        
        // Check enable conditions
        let enabledForCondition = checkEnableConditions(
            cob: cob,
            hasTempTarget: hasTempTarget
        )
        guard enabledForCondition else {
            return .noSMB(reason: "SMB not enabled for current conditions")
        }
        
        // Check if BG is high enough to warrant SMB
        guard eventualBG > targetBG + 10 else {
            return .noSMB(reason: "eventualBG \(Int(eventualBG)) near target, no SMB needed")
        }
        
        // Calculate SMB amount
        let smbUnits = calculateSMBAmount(
            eventualBG: eventualBG,
            targetBG: targetBG,
            iob: iob,
            sens: sens,
            maxBasal: maxBasal
        )
        
        if smbUnits <= 0.05 {  // Less than 0.05U not worth delivering
            return .noSMB(reason: "Calculated SMB too small")
        }
        
        // Calculate eventual BG with SMB
        let eventualBGWithSMB = eventualBG - (smbUnits * sens)
        
        return SMBResult(
            shouldDeliver: true,
            units: smbUnits,
            reason: "SMB \(String(format: "%.2f", smbUnits))U to bring eventualBG \(Int(eventualBG)) toward \(Int(targetBG))",
            eventualBGWithSMB: eventualBGWithSMB
        )
    }
    
    // MARK: - Private Methods
    
    private func checkEnableConditions(cob: Double, hasTempTarget: Bool) -> Bool {
        if settings.enableAlways {
            return true
        }
        
        if settings.enableWithCOB && cob > 0 {
            return true
        }
        
        if settings.enableWithTempTarget && hasTempTarget {
            return true
        }
        
        if settings.enableAfterCarbs && cob > 0 {
            return true
        }
        
        return false
    }
    
    private func calculateSMBAmount(
        eventualBG: Double,
        targetBG: Double,
        iob: Double,
        sens: Double,
        maxBasal: Double
    ) -> Double {
        // Calculate insulin needed to bring eventual BG to target
        let bgAboveTarget = eventualBG - targetBG
        let insulinNeeded = bgAboveTarget / sens
        
        // Subtract existing IOB
        let additionalInsulin = max(0, insulinNeeded - iob)
        
        // Limit to 30 minutes of maxBasal equivalent
        let maxByBasal = maxBasal * 0.5  // 30 min
        
        // Apply SMB-specific limit
        var smb = min(additionalInsulin, maxByBasal)
        smb = min(smb, settings.maxSMB)
        
        // Round to 0.05U precision
        smb = round(smb * 20) / 20
        
        return smb
    }
}

// MARK: - SMB History

/// Track SMB delivery history
public struct SMBDelivery: Codable, Sendable {
    public let timestamp: Date
    public let units: Double
    public let reason: String
    public let bgAtDelivery: Double
    
    public init(timestamp: Date = Date(), units: Double, reason: String, bgAtDelivery: Double) {
        self.timestamp = timestamp
        self.units = units
        self.reason = reason
        self.bgAtDelivery = bgAtDelivery
    }
}

/// Thread-safe SMB history tracker
public final class SMBHistory: @unchecked Sendable {
    private var deliveries: [SMBDelivery] = []
    private let lock = NSLock()
    private let maxEntries: Int
    
    public init(maxEntries: Int = 100) {
        self.maxEntries = maxEntries
    }
    
    public func record(_ delivery: SMBDelivery) {
        lock.lock()
        defer { lock.unlock() }
        
        deliveries.append(delivery)
        if deliveries.count > maxEntries {
            deliveries.removeFirst(deliveries.count - maxEntries)
        }
    }
    
    public var lastDeliveryTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return deliveries.last?.timestamp
    }
    
    public func deliveriesSince(_ date: Date) -> [SMBDelivery] {
        lock.lock()
        defer { lock.unlock() }
        return deliveries.filter { $0.timestamp >= date }
    }
    
    public func totalUnitsSince(_ date: Date) -> Double {
        deliveriesSince(date).reduce(0) { $0 + $1.units }
    }
    
    public var recentDeliveries: [SMBDelivery] {
        lock.lock()
        defer { lock.unlock() }
        return Array(deliveries.suffix(10))
    }
}

// MARK: - Integration with DetermineBasal

extension DetermineBasalOutput {
    /// Create output with SMB
    public static func withSMB(
        rate: Double,
        duration: Int = 30,
        smbUnits: Double,
        reason: String,
        eventualBG: Double,
        minPredBG: Double,
        iob: Double,
        cob: Double
    ) -> DetermineBasalOutput {
        DetermineBasalOutput(
            rate: rate,
            duration: duration,
            reason: reason,
            eventualBG: eventualBG,
            minPredBG: minPredBG,
            iob: iob,
            cob: cob,
            tick: "",
            units: smbUnits
        )
    }
}

// MARK: - B30 Boost 30 Minutes (ALG-TRIO-002)

/// Boost 30 (B30) - Trio-style 30-minute enhanced insulin delivery after carbs
///
/// B30 provides temporary increased insulin sensitivity for 30 minutes after
/// carb entry to counteract post-meal glucose spikes. Common for breakfast
/// where dawn phenomenon combines with carb absorption.
///
/// Based on Trio's B30 implementation.
public struct Boost30Settings: Codable, Sendable, Equatable {
    /// Whether B30 is enabled
    public let enabled: Bool
    
    /// Duration of boost in minutes (default 30)
    public let durationMinutes: Double
    
    /// ISF reduction factor (e.g., 0.8 = 20% more aggressive)
    /// Applied: adjustedISF = baseISF * factor
    public let isfFactor: Double
    
    /// CR reduction factor (e.g., 0.9 = 10% more aggressive carb ratio)
    /// Applied: adjustedCR = baseCR * factor
    public let crFactor: Double
    
    /// Whether to increase SMB max during boost
    public let boostSMB: Bool
    
    /// SMB max multiplier during boost (e.g., 1.5 = 50% larger SMBs allowed)
    public let smbMaxMultiplier: Double
    
    /// Minimum carbs to trigger boost (grams)
    public let minCarbsToTrigger: Double
    
    /// Whether to only activate during morning hours
    public let morningOnly: Bool
    
    /// Morning start hour (only used if morningOnly = true)
    public let morningStartHour: Int
    
    /// Morning end hour (only used if morningOnly = true)
    public let morningEndHour: Int
    
    public init(
        enabled: Bool = false,
        durationMinutes: Double = 30,
        isfFactor: Double = 0.8,
        crFactor: Double = 0.9,
        boostSMB: Bool = true,
        smbMaxMultiplier: Double = 1.5,
        minCarbsToTrigger: Double = 10,
        morningOnly: Bool = false,
        morningStartHour: Int = 5,
        morningEndHour: Int = 10
    ) {
        self.enabled = enabled
        self.durationMinutes = durationMinutes
        self.isfFactor = max(0.5, min(1.0, isfFactor))
        self.crFactor = max(0.5, min(1.0, crFactor))
        self.boostSMB = boostSMB
        self.smbMaxMultiplier = max(1.0, min(3.0, smbMaxMultiplier))
        self.minCarbsToTrigger = minCarbsToTrigger
        self.morningOnly = morningOnly
        self.morningStartHour = morningStartHour
        self.morningEndHour = morningEndHour
    }
    
    /// Default B30 settings (disabled)
    public static let `default` = Boost30Settings()
    
    /// Standard B30 preset (Trio-like)
    public static let standard = Boost30Settings(
        enabled: true,
        durationMinutes: 30,
        isfFactor: 0.8,
        crFactor: 0.9,
        boostSMB: true,
        smbMaxMultiplier: 1.5,
        minCarbsToTrigger: 10
    )
    
    /// Morning-only B30 preset
    public static let morningBoost = Boost30Settings(
        enabled: true,
        durationMinutes: 30,
        isfFactor: 0.75,
        crFactor: 0.85,
        boostSMB: true,
        smbMaxMultiplier: 1.5,
        minCarbsToTrigger: 15,
        morningOnly: true,
        morningStartHour: 5,
        morningEndHour: 10
    )
}

/// Result of B30 evaluation
public struct Boost30Result: Sendable {
    /// Whether B30 is currently active
    public let isActive: Bool
    
    /// Adjusted ISF factor (1.0 if not active)
    public let isfFactor: Double
    
    /// Adjusted CR factor (1.0 if not active)
    public let crFactor: Double
    
    /// Adjusted SMB max multiplier (1.0 if not active)
    public let smbMaxMultiplier: Double
    
    /// Time remaining in boost (nil if not active)
    public let remainingMinutes: Double?
    
    /// Reason for the decision
    public let reason: String
    
    /// Carb entry that triggered boost (if active)
    public let triggeringCarbGrams: Double?
    
    public static let inactive = Boost30Result(
        isActive: false,
        isfFactor: 1.0,
        crFactor: 1.0,
        smbMaxMultiplier: 1.0,
        remainingMinutes: nil,
        reason: "B30 not active",
        triggeringCarbGrams: nil
    )
}

/// Calculator for B30 boost
public struct Boost30Calculator: Sendable {
    public let settings: Boost30Settings
    
    public init(settings: Boost30Settings = .default) {
        self.settings = settings
    }
    
    /// Evaluate B30 based on recent carb entries
    public func evaluate(
        recentCarbs: [(timestamp: Date, grams: Double)],
        currentTime: Date = Date()
    ) -> Boost30Result {
        guard settings.enabled else {
            return Boost30Result(
                isActive: false,
                isfFactor: 1.0,
                crFactor: 1.0,
                smbMaxMultiplier: 1.0,
                remainingMinutes: nil,
                reason: "B30 disabled",
                triggeringCarbGrams: nil
            )
        }
        
        // Check morning restriction if enabled
        if settings.morningOnly {
            let hour = Calendar.current.component(.hour, from: currentTime)
            let inMorningWindow: Bool
            if settings.morningStartHour <= settings.morningEndHour {
                inMorningWindow = hour >= settings.morningStartHour && hour < settings.morningEndHour
            } else {
                inMorningWindow = hour >= settings.morningStartHour || hour < settings.morningEndHour
            }
            
            guard inMorningWindow else {
                return Boost30Result(
                    isActive: false,
                    isfFactor: 1.0,
                    crFactor: 1.0,
                    smbMaxMultiplier: 1.0,
                    remainingMinutes: nil,
                    reason: "B30 morning-only, current hour \(hour) outside window",
                    triggeringCarbGrams: nil
                )
            }
        }
        
        // Find qualifying carb entry in boost window
        let boostWindowSeconds = settings.durationMinutes * 60
        
        for carb in recentCarbs.sorted(by: { $0.timestamp > $1.timestamp }) {
            let elapsed = currentTime.timeIntervalSince(carb.timestamp)
            
            // Check if within boost window
            guard elapsed >= 0 && elapsed < boostWindowSeconds else { continue }
            
            // Check minimum carbs
            guard carb.grams >= settings.minCarbsToTrigger else { continue }
            
            // B30 is active!
            let remainingSeconds = boostWindowSeconds - elapsed
            let remainingMinutes = remainingSeconds / 60
            
            return Boost30Result(
                isActive: true,
                isfFactor: settings.isfFactor,
                crFactor: settings.crFactor,
                smbMaxMultiplier: settings.boostSMB ? settings.smbMaxMultiplier : 1.0,
                remainingMinutes: remainingMinutes,
                reason: "B30 active: \(Int(carb.grams))g carbs \(Int(elapsed / 60))min ago, \(Int(remainingMinutes))min remaining",
                triggeringCarbGrams: carb.grams
            )
        }
        
        return Boost30Result(
            isActive: false,
            isfFactor: 1.0,
            crFactor: 1.0,
            smbMaxMultiplier: 1.0,
            remainingMinutes: nil,
            reason: "No qualifying carb entry in B30 window",
            triggeringCarbGrams: nil
        )
    }
}
