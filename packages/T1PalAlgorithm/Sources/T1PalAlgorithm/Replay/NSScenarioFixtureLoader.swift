// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NSScenarioFixtureLoader.swift
// T1PalAlgorithm
//
// IOB-FIX-001: Loads raw NS scenario fixtures for LoopReplayEngine.
// Scenario fixtures have raw NS format with deviceStatus, treatments arrays.
//
// Usage:
//   let scenario = try NSScenarioFixtureLoader.load(from: url)
//   let engine = scenario.toReplayEngine()
//   let results = engine.replay()

import Foundation

// MARK: - NS Scenario Fixture Types

/// Root structure for scenario fixture files
public struct NSScenarioFixture: Codable, Sendable {
    public let metadata: NSScenarioMetadata
    public let deviceStatus: [NSRawDeviceStatus]
    public let treatments: [NSRawTreatment]
    public let profile: [NSRawProfile]?  // IOB-FIX-005: Include profile for accurate basal schedule
    
    enum CodingKeys: String, CodingKey {
        case metadata
        case deviceStatus
        case treatments
        case profile
    }
}

/// Scenario metadata
public struct NSScenarioMetadata: Codable, Sendable {
    public let scenario: String
    public let created: String
    public let start: String
    public let end: String
    public let deviceStatus_count: Int
    public let source: String
}

/// Raw NS devicestatus from API
public struct NSRawDeviceStatus: Codable, Sendable {
    public let _id: String
    public let device: String?
    public let created_at: String
    public let utcOffset: Int?
    public let pump: NSRawPumpStatus?
    public let override: NSRawOverride?
    public let uploader: NSRawUploader?
    public let loop: NSRawLoopStatus?
}

public struct NSRawPumpStatus: Codable, Sendable {
    public let model: String?
    public let reservoir: Double?
    public let pumpID: String?
    public let battery: NSRawBattery?
    public let manufacturer: String?
    public let clock: String?
    public let secondsFromGMT: Int?
    public let bolusing: Bool?
    public let suspended: Bool?
}

public struct NSRawBattery: Codable, Sendable {
    public let percent: Int?
}

public struct NSRawOverride: Codable, Sendable {
    public let timestamp: String?
    public let active: Bool?
}

public struct NSRawUploader: Codable, Sendable {
    public let timestamp: String?
    public let name: String?
    public let battery: Int?
}

public struct NSRawLoopStatus: Codable, Sendable {
    public let recommendedBolus: Double?
    public let timestamp: String?
    public let enacted: NSRawEnacted?
    public let version: String?
    public let automaticDoseRecommendation: NSRawAutoDoseRec?
    public let cob: NSRawCOB?
    public let name: String?
    public let predicted: NSRawPredicted?
    public let iob: NSRawIOB?
}

public struct NSRawEnacted: Codable, Sendable {
    public let received: Bool?
    public let timestamp: String?
    public let duration: Double?
    public let rate: Double?
    public let bolusVolume: Double?
}

public struct NSRawAutoDoseRec: Codable, Sendable {
    public let timestamp: String?
    public let bolusVolume: Double?
    public let tempBasalAdjustment: NSRawTempBasalAdj?
}

public struct NSRawTempBasalAdj: Codable, Sendable {
    public let rate: Double?
    public let duration: Double?
}

public struct NSRawCOB: Codable, Sendable {
    public let timestamp: String?
    public let cob: Double?
}

public struct NSRawPredicted: Codable, Sendable {
    public let startDate: String?
    public let values: [Double]?
}

public struct NSRawIOB: Codable, Sendable {
    public let iob: Double?
    public let timestamp: String?
}

/// Raw NS treatment from API
public struct NSRawTreatment: Codable, Sendable {
    public let _id: String?
    public let syncIdentifier: String?
    public let created_at: String
    public let timestamp: String?
    public let eventType: String?
    public let temp: String?
    public let absolute: Double?
    public let automatic: Bool?
    public let insulinType: String?
    public let amount: Double?
    public let rate: Double?
    public let enteredBy: String?
    public let duration: Double?  // IOB-FIX-002: This is in MINUTES (raw NS format)
    public let utcOffset: Int?
    public let carbs: Double?
    public let insulin: Double?
}

// MARK: - Raw Profile Types (IOB-FIX-005)

/// Raw NS profile from API
public struct NSRawProfile: Codable, Sendable {
    public let _id: String?
    public let enteredBy: String?
    public let store: [String: NSRawProfileStore]?
}

/// Profile store (e.g., "Default")
public struct NSRawProfileStore: Codable, Sendable {
    public let basal: [NSRawScheduleEntry]?
    public let carbratio: [NSRawScheduleEntry]?
    public let sens: [NSRawScheduleEntry]?
    public let target_low: [NSRawScheduleEntry]?
    public let target_high: [NSRawScheduleEntry]?
    public let timezone: String?
    public let units: String?
    public let dia: Double?
}

/// Schedule entry with time and value
public struct NSRawScheduleEntry: Codable, Sendable {
    public let time: String?
    public let timeAsSeconds: Int?
    public let value: Double
}

// MARK: - Scenario Fixture Loader

/// Loads raw NS scenario fixtures and converts to LoopReplayEngine types.
public enum NSScenarioFixtureLoader {
    
    /// Load scenario fixture from URL
    public static func load(from url: URL) throws -> NSScenarioFixture {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }
    
    /// Load scenario fixture from data
    public static func load(from data: Data) throws -> NSScenarioFixture {
        let decoder = JSONDecoder()
        return try decoder.decode(NSScenarioFixture.self, from: data)
    }
    
    /// Convert scenario to DeviceStatusRecord array for LoopReplayEngine
    public static func toDeviceStatusRecords(_ scenario: NSScenarioFixture) -> [DeviceStatusRecord] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]
        
        func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            return formatter.date(from: string) ?? formatterNoFrac.date(from: string)
        }
        
        return scenario.deviceStatus.compactMap { ds -> DeviceStatusRecord? in
            guard let createdAt = parseDate(ds.created_at) else { return nil }
            guard let loop = ds.loop else { return nil }
            guard let iobTimestamp = parseDate(loop.iob?.timestamp) else { return nil }
            guard let predictedStartDate = parseDate(loop.predicted?.startDate) else { return nil }
            
            let iobData = IOBData(
                iob: loop.iob?.iob ?? 0,
                timestamp: iobTimestamp
            )
            
            let cobData = loop.cob.map { COBData(cob: $0.cob ?? 0) }
            
            let predictedData = PredictedData(
                startDate: predictedStartDate,
                values: (loop.predicted?.values ?? []).map { Int($0) }
            )
            
            let autoRec: AutomaticDoseRecommendationData?
            if let adr = loop.automaticDoseRecommendation {
                autoRec = AutomaticDoseRecommendationData(
                    tempBasalRate: adr.tempBasalAdjustment?.rate,
                    tempBasalDuration: adr.tempBasalAdjustment?.duration,
                    bolusVolume: adr.bolusVolume
                )
            } else {
                autoRec = nil
            }
            
            let enactedData: EnactedData?
            if let enacted = loop.enacted {
                let enactedTimestamp = parseDate(enacted.timestamp) ?? createdAt
                enactedData = EnactedData(
                    rate: enacted.rate ?? 0,
                    duration: enacted.duration ?? 30,
                    timestamp: enactedTimestamp,
                    received: enacted.received ?? true
                )
            } else {
                enactedData = nil
            }
            
            let loopStatus = LoopStatusData(
                iob: iobData,
                cob: cobData,
                predicted: predictedData,
                automaticDoseRecommendation: autoRec,
                enacted: enactedData
            )
            
            return DeviceStatusRecord(
                identifier: ds._id,
                createdAt: createdAt,
                loop: loopStatus,
                loopSettings: nil
            )
        }
    }
    
    /// Convert scenario treatments to TreatmentRecord array for LoopReplayEngine
    /// IOB-FIX-002: Correctly handles `duration` field (in minutes) from raw NS format
    public static func toTreatmentRecords(_ scenario: NSScenarioFixture) -> [TreatmentRecord] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]
        
        func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            return formatter.date(from: string) ?? formatterNoFrac.date(from: string)
        }
        
        return scenario.treatments.compactMap { t -> TreatmentRecord? in
            guard let createdAt = parseDate(t.created_at) else { return nil }
            let timestamp = parseDate(t.timestamp) ?? createdAt
            
            return TreatmentRecord(
                identifier: t._id ?? t.syncIdentifier ?? UUID().uuidString,
                eventType: t.eventType ?? "Unknown",
                timestamp: timestamp,
                createdAt: createdAt,
                rate: t.rate,
                absolute: t.absolute,
                duration: t.duration,  // Already in minutes from NS
                insulin: t.insulin,
                carbs: t.carbs
            )
        }
    }
    
    /// Convert scenario to LoopReplayEngine
    /// Requires glucose entries and profile (can load from separate files or use defaults)
    public static func toReplayEngine(
        _ scenario: NSScenarioFixture,
        glucose: [GlucoseRecord] = [],
        profile: NightscoutProfileData,
        settings: TherapySettingsSnapshot
    ) -> LoopReplayEngine {
        let deviceStatuses = toDeviceStatusRecords(scenario)
        let treatments = toTreatmentRecords(scenario)
        
        return LoopReplayEngine(
            deviceStatuses: deviceStatuses,
            treatments: treatments,
            glucose: glucose,
            profile: profile,
            settings: settings
        )
    }
    
    /// Quick validation: load and check scenario has expected data
    public static func validate(from url: URL) throws -> (deviceStatusCount: Int, treatmentCount: Int, errors: [String]) {
        let scenario = try load(from: url)
        var errors: [String] = []
        
        let deviceStatuses = toDeviceStatusRecords(scenario)
        let treatments = toTreatmentRecords(scenario)
        
        if deviceStatuses.isEmpty {
            errors.append("No valid devicestatus records converted")
        }
        
        if treatments.isEmpty {
            errors.append("No valid treatment records converted")
        }
        
        // Check treatment duration parsing
        let tempBasals = scenario.treatments.filter { $0.eventType == "Temp Basal" }
        let tempBasalsWithDuration = tempBasals.filter { $0.duration != nil }
        if tempBasals.count > 0 && tempBasalsWithDuration.count == 0 {
            errors.append("Temp basals found but no duration values")
        }
        
        return (deviceStatuses.count, treatments.count, errors)
    }
    
    // MARK: - Profile Conversion (IOB-FIX-005)
    
    /// Extract profile data from scenario fixture
    public static func toProfileData(_ scenario: NSScenarioFixture) -> NightscoutProfileData? {
        guard let profiles = scenario.profile,
              let firstProfile = profiles.first,
              let store = firstProfile.store,
              let defaultStore = store["Default"] else {
            return nil
        }
        
        // Convert basal schedule
        let basalSchedule = (defaultStore.basal ?? []).compactMap { entry -> BasalScheduleEntry? in
            guard let timeAsSeconds = entry.timeAsSeconds else { return nil }
            return BasalScheduleEntry(startTime: TimeInterval(timeAsSeconds), rate: entry.value)
        }.sorted { $0.startTime < $1.startTime }
        
        // Convert ISF schedule
        let isfSchedule = (defaultStore.sens ?? []).compactMap { entry -> ScheduleValue? in
            guard let timeAsSeconds = entry.timeAsSeconds else { return nil }
            return ScheduleValue(startTime: TimeInterval(timeAsSeconds), value: entry.value)
        }.sorted { $0.startTime < $1.startTime }
        
        // Convert CR schedule
        let crSchedule = (defaultStore.carbratio ?? []).compactMap { entry -> ScheduleValue? in
            guard let timeAsSeconds = entry.timeAsSeconds else { return nil }
            return ScheduleValue(startTime: TimeInterval(timeAsSeconds), value: entry.value)
        }.sorted { $0.startTime < $1.startTime }
        
        // Get targets
        let targetLow = defaultStore.target_low?.first?.value ?? 100
        let targetHigh = defaultStore.target_high?.first?.value ?? 110
        
        // DIA defaults to 6 hours (21600 seconds)
        let dia = (defaultStore.dia ?? 6) * 3600
        
        return NightscoutProfileData(
            basalSchedule: basalSchedule.isEmpty ? [BasalScheduleEntry(startTime: 0, rate: 1.0)] : basalSchedule,
            isfSchedule: isfSchedule.isEmpty ? [ScheduleValue(startTime: 0, value: 40)] : isfSchedule,
            crSchedule: crSchedule.isEmpty ? [ScheduleValue(startTime: 0, value: 10)] : crSchedule,
            targetLow: targetLow,
            targetHigh: targetHigh,
            dia: dia
        )
    }
    
    /// Extract TherapySettingsSnapshot from profile
    public static func toSettings(_ scenario: NSScenarioFixture) -> TherapySettingsSnapshot? {
        guard let profile = toProfileData(scenario) else { return nil }
        
        return TherapySettingsSnapshot(
            suspendThreshold: 70,  // Default, not in profile
            maxBasalRate: 4.0,     // Default, not in profile
            insulinSensitivity: profile.isfSchedule.first?.value ?? 40,
            carbRatio: profile.crSchedule.first?.value ?? 10,
            targetLow: profile.targetLow,
            targetHigh: profile.targetHigh,
            basalSchedule: profile.basalSchedule,
            insulinModel: .rapidActingAdult,  // Default
            dia: profile.dia
        )
    }
}
