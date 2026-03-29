// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// TreatmentFactory.swift - Factory for creating Nightscout treatments
// Part of NightscoutKit
// Trace: NS-UPLOAD-002, PRD-014 REQ-COMPAT-005

import Foundation

// MARK: - Treatment Factory

/// Factory for creating properly formatted Nightscout treatments
/// Ensures correct syncIdentifier pattern for Loop/Trio compatibility
public enum TreatmentFactory {
    
    // MARK: - Insulin Treatments
    
    /// Create a bolus treatment
    public static func bolus(
        units: Double,
        deviceId: String,
        timestamp: Date = Date(),
        notes: String? = nil
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):bolus:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Bolus",
            created_at: iso(timestamp),
            insulin: units,
            enteredBy: "T1Pal",
            notes: notes,
            identifier: syncId
        )
    }
    
    /// Create a correction bolus treatment
    public static func correctionBolus(
        units: Double,
        deviceId: String,
        timestamp: Date = Date(),
        glucose: Double? = nil,
        notes: String? = nil
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):correction-bolus:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: iso(timestamp),
            insulin: units,
            glucose: glucose,
            enteredBy: "T1Pal",
            notes: notes,
            identifier: syncId
        )
    }
    
    /// Create a meal bolus treatment (insulin + carbs)
    public static func mealBolus(
        units: Double,
        carbs: Double,
        deviceId: String,
        timestamp: Date = Date(),
        notes: String? = nil
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):meal-bolus:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Meal Bolus",
            created_at: iso(timestamp),
            insulin: units,
            carbs: carbs,
            enteredBy: "T1Pal",
            notes: notes,
            identifier: syncId
        )
    }
    
    // MARK: - Carb Treatments
    
    /// Create a carb correction treatment
    public static func carbs(
        grams: Double,
        deviceId: String,
        timestamp: Date = Date(),
        notes: String? = nil
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):carb-correction:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Carb Correction",
            created_at: iso(timestamp),
            carbs: grams,
            enteredBy: "T1Pal",
            notes: notes,
            identifier: syncId
        )
    }
    
    /// Create a meal treatment
    public static func meal(
        carbs: Double,
        deviceId: String,
        timestamp: Date = Date(),
        notes: String? = nil
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):meal:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Meal",
            created_at: iso(timestamp),
            carbs: carbs,
            enteredBy: "T1Pal",
            notes: notes,
            identifier: syncId
        )
    }
    
    // MARK: - Temp Basal Treatments
    
    /// Create a temp basal treatment
    public static func tempBasal(
        rate: Double,
        durationMinutes: Double,
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):temp-basal:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Temp Basal",
            created_at: iso(timestamp),
            duration: durationMinutes,
            rate: rate,
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    /// Create a temp basal with absolute rate
    public static func tempBasalAbsolute(
        absoluteRate: Double,
        durationMinutes: Double,
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):temp-basal:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Temp Basal",
            created_at: iso(timestamp),
            duration: durationMinutes,
            absolute: absoluteRate,
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    /// Create a temp basal cancellation
    public static func tempBasalCancel(
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):temp-basal-cancel:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Temp Basal",
            created_at: iso(timestamp),
            duration: 0,
            rate: 0,
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    // MARK: - Profile Treatments
    
    /// Create a profile switch treatment
    public static func profileSwitch(
        profileName: String,
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):profile-switch:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Profile Switch",
            created_at: iso(timestamp),
            profile: profileName,
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    /// Create a temporary target treatment
    public static func tempTarget(
        targetLow: Double,
        targetHigh: Double,
        durationMinutes: Double,
        reason: String? = nil,
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):temporary-target:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Temporary Target",
            created_at: iso(timestamp),
            duration: durationMinutes,
            targetTop: targetHigh,
            targetBottom: targetLow,
            enteredBy: "T1Pal",
            reason: reason,
            identifier: syncId
        )
    }
    
    /// Cancel a temporary target
    public static func tempTargetCancel(
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):temp-target-cancel:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Temporary Target",
            created_at: iso(timestamp),
            duration: 0,
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    // MARK: - Suspend/Resume
    
    /// Create a suspend pump treatment
    public static func suspend(
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):suspend:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Suspend Pump",
            created_at: iso(timestamp),
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    /// Create a resume pump treatment
    public static func resume(
        deviceId: String,
        timestamp: Date = Date()
    ) -> NightscoutTreatment {
        let syncId = "\(deviceId):resume:\(Int(timestamp.timeIntervalSince1970))"
        return NightscoutTreatment(
            eventType: "Resume Pump",
            created_at: iso(timestamp),
            enteredBy: "T1Pal",
            identifier: syncId
        )
    }
    
    // MARK: - Helpers
    
    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
