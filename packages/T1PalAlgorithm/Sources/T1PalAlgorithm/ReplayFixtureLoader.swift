// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ReplayFixtureLoader.swift
// T1PalAlgorithm
//
// Loads and replays captured session fixtures for algorithm validation.
// Created by ALG-VAL-002.
//
// Usage:
//   let fixture = try ReplayFixtureLoader.load(from: url)
//   let inputs = ReplayFixtureLoader.toAlgorithmInputs(fixture)
//   let result = algorithm.calculate(inputs: inputs)

import Foundation
import T1PalCore

// MARK: - Replay Fixture Types (must match CLI capture format)

/// Complete algorithm context captured from a live session.
public struct ReplayFixture: Codable, Sendable {
    public let metadata: ReplayMetadata
    public let deviceStatus: [ReplayDeviceStatus]
    public let entries: [ReplayEntry]
    public let treatments: [ReplayTreatment]
    public let profile: ReplayProfile?
    public let comparison: ReplayComparison?
}

public struct ReplayMetadata: Codable, Sendable {
    public let fixtureVersion: String
    public let capturedAt: Date
    public let toolVersion: String
    public let sourceType: String
    public let sourceURLHash: String?
    public let sinceTime: Date?
    public let highFidelity: Bool
}

public struct ReplayDeviceStatus: Codable, Sendable {
    public let timestamp: Date
    public let device: String?
    public let loopIOB: Double?
    public let loopCOB: Double?
    public let loopPredicted: [Double]?
    public let loopPredictedStart: Date?
    public let enactedTempBasalRate: Double?
    public let enactedTempBasalDuration: Double?
    public let enactedSMB: Double?
    public let aapsIOB: Double?
    public let aapsCOB: Double?
    public let aapsTempBasal: Double?
    public let reservoir: Double?
    public let batteryPercent: Int?
}

public struct ReplayEntry: Codable, Sendable {
    public let timestamp: Date
    public let sgv: Double
    public let direction: String?
    public let delta: Double?
}

public struct ReplayTreatment: Codable, Sendable {
    public let timestamp: Date
    public let eventType: String
    public let insulin: Double?
    public let rate: Double?
    public let durationMinutes: Double?
    public let carbs: Double?
    public let absorptionTime: Double?
}

public struct ReplayProfile: Codable, Sendable {
    public let name: String?
    public let basalSchedule: [ReplayScheduleEntry]
    public let isfSchedule: [ReplayScheduleEntry]
    public let crSchedule: [ReplayScheduleEntry]
    public let targetLow: Double?
    public let targetHigh: Double?
    public let maxBasalRate: Double?
    public let maxBolus: Double?
    public let suspendThreshold: Double?
    public let dosingStrategy: String?
}

public struct ReplayScheduleEntry: Codable, Sendable {
    public let startSeconds: Int
    public let value: Double
}

public struct ReplayComparison: Codable, Sendable {
    public let algorithms: [String]
    public let recommendations: [ReplayRecommendation]
    public let enacted: ReplayEnacted?
}

public struct ReplayRecommendation: Codable, Sendable {
    public let algorithm: String
    public let tempBasalRate: Double?
    public let tempBasalDuration: Double?
    public let smb: Double?
}

public struct ReplayEnacted: Codable, Sendable {
    public let source: String
    public let tempBasalRate: Double?
    public let tempBasalDuration: Double?
    public let smb: Double?
}

// MARK: - Fixture Loader

/// Loads replay fixtures and converts them to algorithm inputs.
public enum ReplayFixtureLoader {
    
    /// Load fixture from a URL.
    public static func load(from url: URL) throws -> ReplayFixture {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReplayFixture.self, from: data)
    }
    
    /// Load fixture from JSON data.
    public static func load(from data: Data) throws -> ReplayFixture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReplayFixture.self, from: data)
    }
    
    /// Load fixture from a directory containing separate JSON files.
    /// Expected files: manifest.json, entries.json, treatments.json, devicestatus.json, profile.json
    public static func loadDirectory(from directoryURL: URL) throws -> ReplayFixture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Try ISO8601 string first
            if let dateString = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) { return date }
            }
            // Try milliseconds timestamp
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp / 1000.0)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date")
        }
        
        // Load manifest
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(NSFixtureManifest.self, from: manifestData)
        
        // Load entries
        let entriesURL = directoryURL.appendingPathComponent("entries.json")
        let entriesData = try Data(contentsOf: entriesURL)
        let nsEntries = try decoder.decode([NSEntry].self, from: entriesData)
        
        // Load treatments
        let treatmentsURL = directoryURL.appendingPathComponent("treatments.json")
        let treatmentsData = try Data(contentsOf: treatmentsURL)
        let nsTreatments = try decoder.decode([NSTreatment].self, from: treatmentsData)
        
        // Load devicestatus (optional)
        var nsDeviceStatus: [NSDeviceStatus] = []
        let deviceStatusURL = directoryURL.appendingPathComponent("devicestatus.json")
        if let deviceStatusData = try? Data(contentsOf: deviceStatusURL) {
            nsDeviceStatus = (try? decoder.decode([NSDeviceStatus].self, from: deviceStatusData)) ?? []
        }
        
        // Load profile (optional)
        var nsProfiles: [NSProfile] = []
        let profileURL = directoryURL.appendingPathComponent("profile.json")
        if let profileData = try? Data(contentsOf: profileURL) {
            nsProfiles = (try? decoder.decode([NSProfile].self, from: profileData)) ?? []
        }
        
        // Convert to ReplayFixture format
        return convertToReplayFixture(
            manifest: manifest,
            entries: nsEntries,
            treatments: nsTreatments,
            deviceStatus: nsDeviceStatus,
            profiles: nsProfiles
        )
    }
    
    // MARK: - NS Format Types (for multi-file loading)
    
    private struct NSFixtureManifest: Codable {
        let capturedAt: String
        let source: String?
        let anonymized: Bool?
        let entryCount: Int?
        let treatmentCount: Int?
        let profileCount: Int?
    }
    
    private struct NSEntry: Codable {
        let sgv: Double?
        let dateString: String?
        let date: Double?
        let direction: String?
        let device: String?
    }
    
    private struct NSTreatment: Codable {
        let eventType: String?
        let created_at: String?
        let timestamp: String?
        let insulin: Double?
        let rate: Double?
        let absolute: Double?
        let duration: Double?
        let carbs: Double?
        let absorptionTime: Double?
    }
    
    private struct NSDeviceStatus: Codable {
        let created_at: String?
        let device: String?
        let loop: NSLoopStatus?
        let pump: NSPumpStatus?
    }
    
    private struct NSLoopStatus: Codable {
        let iob: NSIOBStatus?
        let cob: NSCOBStatus?
        let predicted: NSPredicted?
        let enacted: NSEnacted?
    }
    
    private struct NSIOBStatus: Codable {
        let iob: Double?
    }
    
    private struct NSCOBStatus: Codable {
        let cob: Double?
    }
    
    private struct NSPredicted: Codable {
        let values: [Double]?
        let startDate: String?
    }
    
    private struct NSEnacted: Codable {
        let rate: Double?
        let duration: Double?
        let bolusVolume: Double?
    }
    
    private struct NSPumpStatus: Codable {
        let reservoir: Double?
        let battery: NSBattery?
    }
    
    private struct NSBattery: Codable {
        let percent: Int?
    }
    
    private struct NSProfile: Codable {
        let defaultProfile: String?
        let store: [String: NSProfileStore]?
    }
    
    private struct NSProfileStore: Codable {
        let basal: [NSScheduleEntry]?
        let carbratio: [NSScheduleEntry]?
        let sens: [NSScheduleEntry]?
        let target_low: [NSScheduleEntry]?
        let target_high: [NSScheduleEntry]?
    }
    
    private struct NSScheduleEntry: Codable {
        let time: String?
        let timeAsSeconds: Int?
        let value: Double?
    }
    
    private static func convertToReplayFixture(
        manifest: NSFixtureManifest,
        entries: [NSEntry],
        treatments: [NSTreatment],
        deviceStatus: [NSDeviceStatus],
        profiles: [NSProfile]
    ) -> ReplayFixture {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let capturedAt = isoFormatter.date(from: manifest.capturedAt) ?? Date()
        
        // Convert entries
        let replayEntries = entries.compactMap { entry -> ReplayEntry? in
            guard let sgv = entry.sgv else { return nil }
            var timestamp: Date?
            if let dateString = entry.dateString {
                timestamp = isoFormatter.date(from: dateString)
            }
            if timestamp == nil, let date = entry.date {
                timestamp = Date(timeIntervalSince1970: date / 1000.0)
            }
            guard let ts = timestamp else { return nil }
            return ReplayEntry(timestamp: ts, sgv: sgv, direction: entry.direction, delta: nil)
        }
        
        // Convert treatments
        let replayTreatments = treatments.compactMap { t -> ReplayTreatment? in
            var timestamp: Date?
            if let createdAt = t.created_at {
                timestamp = isoFormatter.date(from: createdAt)
            }
            if timestamp == nil, let ts = t.timestamp {
                timestamp = isoFormatter.date(from: ts)
            }
            guard let ts = timestamp else { return nil }
            
            let rate = t.rate ?? t.absolute
            return ReplayTreatment(
                timestamp: ts,
                eventType: t.eventType ?? "Unknown",
                insulin: t.insulin,
                rate: rate,
                durationMinutes: t.duration,
                carbs: t.carbs,
                absorptionTime: t.absorptionTime
            )
        }
        
        // Convert devicestatus
        let replayDeviceStatus = deviceStatus.compactMap { ds -> ReplayDeviceStatus? in
            guard let createdAt = ds.created_at,
                  let timestamp = isoFormatter.date(from: createdAt) else { return nil }
            return ReplayDeviceStatus(
                timestamp: timestamp,
                device: ds.device,
                loopIOB: ds.loop?.iob?.iob,
                loopCOB: ds.loop?.cob?.cob,
                loopPredicted: ds.loop?.predicted?.values,
                loopPredictedStart: ds.loop?.predicted?.startDate.flatMap { isoFormatter.date(from: $0) },
                enactedTempBasalRate: ds.loop?.enacted?.rate,
                enactedTempBasalDuration: ds.loop?.enacted?.duration,
                enactedSMB: ds.loop?.enacted?.bolusVolume,
                aapsIOB: nil,
                aapsCOB: nil,
                aapsTempBasal: nil,
                reservoir: ds.pump?.reservoir,
                batteryPercent: ds.pump?.battery?.percent
            )
        }
        
        // Convert profile (use first profile's default store)
        var replayProfile: ReplayProfile?
        if let firstProfile = profiles.first,
           let defaultName = firstProfile.defaultProfile,
           let store = firstProfile.store?[defaultName] {
            let basalSchedule = (store.basal ?? []).compactMap { entry -> ReplayScheduleEntry? in
                guard let seconds = entry.timeAsSeconds, let value = entry.value else { return nil }
                return ReplayScheduleEntry(startSeconds: seconds, value: value)
            }
            let crSchedule = (store.carbratio ?? []).compactMap { entry -> ReplayScheduleEntry? in
                guard let seconds = entry.timeAsSeconds, let value = entry.value else { return nil }
                return ReplayScheduleEntry(startSeconds: seconds, value: value)
            }
            let isfSchedule = (store.sens ?? []).compactMap { entry -> ReplayScheduleEntry? in
                guard let seconds = entry.timeAsSeconds, let value = entry.value else { return nil }
                return ReplayScheduleEntry(startSeconds: seconds, value: value)
            }
            let targetLow = store.target_low?.first?.value
            let targetHigh = store.target_high?.first?.value
            
            replayProfile = ReplayProfile(
                name: defaultName,
                basalSchedule: basalSchedule,
                isfSchedule: isfSchedule,
                crSchedule: crSchedule,
                targetLow: targetLow,
                targetHigh: targetHigh,
                maxBasalRate: nil,
                maxBolus: nil,
                suspendThreshold: nil,
                dosingStrategy: nil
            )
        }
        
        return ReplayFixture(
            metadata: ReplayMetadata(
                fixtureVersion: "2.0-multifile",
                capturedAt: capturedAt,
                toolVersion: "ns-fixture-capture",
                sourceType: "nightscout",
                sourceURLHash: nil,
                sinceTime: nil,
                highFidelity: true
            ),
            deviceStatus: replayDeviceStatus,
            entries: replayEntries,
            treatments: replayTreatments,
            profile: replayProfile,
            comparison: nil
        )
    }
    
    /// Convert fixture entries to GlucoseReading array.
    public static func toGlucoseReadings(_ fixture: ReplayFixture) -> [GlucoseReading] {
        fixture.entries.map { entry in
            GlucoseReading(
                glucose: entry.sgv,
                timestamp: entry.timestamp,
                trend: mapDirection(entry.direction)
            )
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Convert fixture treatments to InsulinDose array.
    public static func toInsulinDoses(_ fixture: ReplayFixture, scheduledBasalRate: Double = 1.0) -> [InsulinDose] {
        fixture.treatments.compactMap { treatment -> InsulinDose? in
            // Bolus
            if let insulin = treatment.insulin, insulin > 0 {
                return InsulinDose(
                    units: insulin,
                    timestamp: treatment.timestamp,
                    source: "replay_bolus"
                )
            }
            // Temp basal - convert to equivalent bolus units
            if let rate = treatment.rate, let duration = treatment.durationMinutes {
                let netUnits = (rate - scheduledBasalRate) * (duration / 60.0)
                guard abs(netUnits) > 0.001 else { return nil }
                return InsulinDose(
                    units: netUnits,
                    timestamp: treatment.timestamp,
                    source: "replay_temp_basal"
                )
            }
            return nil
        }
    }
    
    /// Convert fixture treatments to CarbEntry array.
    public static func toCarbEntries(_ fixture: ReplayFixture) -> [CarbEntry] {
        fixture.treatments.compactMap { treatment -> CarbEntry? in
            guard let carbs = treatment.carbs, carbs > 0 else { return nil }
            return CarbEntry(
                grams: carbs,
                timestamp: treatment.timestamp,
                absorptionTime: treatment.absorptionTime.map { $0 * 3600 },
                source: "replay"
            )
        }
    }
    
    /// Convert fixture profile to TherapyProfile.
    public static func toTherapyProfile(_ fixture: ReplayFixture) -> TherapyProfile {
        guard let profile = fixture.profile else {
            return .default
        }
        
        let basalRates = profile.basalSchedule.map { entry in
            BasalRate(startTime: TimeInterval(entry.startSeconds), rate: entry.value)
        }
        let carbRatios = profile.crSchedule.map { entry in
            CarbRatio(startTime: TimeInterval(entry.startSeconds), ratio: entry.value)
        }
        let sensitivityFactors = profile.isfSchedule.map { entry in
            SensitivityFactor(startTime: TimeInterval(entry.startSeconds), factor: entry.value)
        }
        
        let targetRange = TargetRange(
            low: profile.targetLow ?? 100,
            high: profile.targetHigh ?? 110
        )
        
        return TherapyProfile(
            basalRates: basalRates.isEmpty ? [BasalRate(startTime: 0, rate: 1.0)] : basalRates,
            carbRatios: carbRatios.isEmpty ? [CarbRatio(startTime: 0, ratio: 10)] : carbRatios,
            sensitivityFactors: sensitivityFactors.isEmpty ? [SensitivityFactor(startTime: 0, factor: 50)] : sensitivityFactors,
            targetGlucose: targetRange
        )
    }
    
    /// Get IOB from deviceStatus (Loop's calculated value).
    public static func getLoopIOB(_ fixture: ReplayFixture) -> Double? {
        fixture.deviceStatus.first?.loopIOB
    }
    
    /// Get COB from deviceStatus (Loop's calculated value).
    public static func getLoopCOB(_ fixture: ReplayFixture) -> Double? {
        fixture.deviceStatus.first?.loopCOB
    }
    
    /// Get enacted decision from fixture.
    public static func getEnacted(_ fixture: ReplayFixture) -> (tempBasalRate: Double?, smb: Double?) {
        let enacted = fixture.comparison?.enacted
        return (enacted?.tempBasalRate, enacted?.smb)
    }
    
    /// Get expected recommendation from fixture.
    public static func getRecommendation(_ fixture: ReplayFixture, algorithm: String) -> (tempBasalRate: Double?, smb: Double?)? {
        guard let rec = fixture.comparison?.recommendations.first(where: { $0.algorithm == algorithm }) else {
            return nil
        }
        return (rec.tempBasalRate, rec.smb)
    }
    
    // MARK: - Helpers
    
    private static func mapDirection(_ direction: String?) -> GlucoseTrend {
        switch direction {
        case "DoubleUp": return .doubleUp
        case "SingleUp": return .singleUp
        case "FortyFiveUp": return .fortyFiveUp
        case "Flat": return .flat
        case "FortyFiveDown": return .fortyFiveDown
        case "SingleDown": return .singleDown
        case "DoubleDown": return .doubleDown
        default: return .flat
        }
    }
}
