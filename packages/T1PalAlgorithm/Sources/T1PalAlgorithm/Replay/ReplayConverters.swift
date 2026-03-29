// ReplayConverters.swift
// T1PalAlgorithm
//
// ALG-ARCH-011: Converters from Nightscout types to Replay engine types.
// Bridges NightscoutKit types to the LoopReplayEngine input types.

import Foundation

// MARK: - DeviceStatus Conversion

extension DeviceStatusRecord {
    
    /// Convert from NightscoutKit DeviceStatus to Replay DeviceStatusRecord
    public static func from(
        nightscout ds: NightscoutDeviceStatusData,
        identifier: String
    ) -> DeviceStatusRecord? {
        // Parse timestamps
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let createdAt = dateFormatter.date(from: ds.created_at) else {
            return nil
        }
        
        // Extract loop status
        guard let loop = ds.loop,
              let iob = loop.iob,
              let iobTimestamp = dateFormatter.date(from: iob.timestamp),
              let predicted = loop.predicted,
              let predictedStartDate = dateFormatter.date(from: predicted.startDate) else {
            return nil
        }
        
        // Build IOB data
        let iobData = IOBData(iob: iob.iob, timestamp: iobTimestamp)
        
        // Build COB data (optional)
        let cobData = loop.cob.map { COBData(cob: $0.cob) }
        
        // Build predicted data
        let predictedData = PredictedData(
            startDate: predictedStartDate,
            values: predicted.values
        )
        
        // Build automatic dose recommendation (optional)
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
        
        // Build enacted data (optional)
        let enactedData: EnactedData?
        if let enacted = loop.enacted {
            let enactedTimestamp = enacted.timestamp.flatMap { dateFormatter.date(from: $0) } ?? createdAt
            enactedData = EnactedData(
                rate: enacted.rate ?? 0,
                duration: enacted.duration ?? 30,
                timestamp: enactedTimestamp,
                received: enacted.received ?? true
            )
        } else {
            enactedData = nil
        }
        
        // Build loop settings (optional)
        let settingsData: LoopSettingsData?
        if let settings = ds.loopSettings {
            settingsData = LoopSettingsData(
                minimumBGGuard: settings.minimumBGGuard,
                maximumBasalRatePerHour: settings.maximumBasalRatePerHour
            )
        } else {
            settingsData = nil
        }
        
        let loopStatus = LoopStatusData(
            iob: iobData,
            cob: cobData,
            predicted: predictedData,
            automaticDoseRecommendation: autoRec,
            enacted: enactedData
        )
        
        return DeviceStatusRecord(
            identifier: identifier,
            createdAt: createdAt,
            loop: loopStatus,
            loopSettings: settingsData
        )
    }
}

// MARK: - Treatment Conversion

extension TreatmentRecord {
    
    /// Convert from NightscoutKit Treatment to Replay TreatmentRecord
    public static func from(nightscout t: NightscoutTreatmentData) -> TreatmentRecord? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let createdAt = dateFormatter.date(from: t.created_at) else {
            return nil
        }
        
        let timestamp = t.timestamp.flatMap { dateFormatter.date(from: $0) } ?? createdAt
        
        return TreatmentRecord(
            identifier: t.identifier,
            eventType: t.eventType,
            timestamp: timestamp,
            createdAt: createdAt,
            rate: t.rate,
            absolute: t.absolute,
            duration: t.duration,
            insulin: t.insulin,
            carbs: t.carbs
        )
    }
}

// MARK: - Glucose Conversion

extension GlucoseRecord {
    
    /// Convert from NightscoutKit Entry to Replay GlucoseRecord
    public static func from(nightscout entry: NightscoutEntryData) -> GlucoseRecord? {
        guard let sgv = entry.sgv else { return nil }
        
        return GlucoseRecord(
            date: entry.timestamp,
            value: Double(sgv),
            trend: entry.direction.flatMap { directionToTrend($0) }
        )
    }
    
    private static func directionToTrend(_ direction: String) -> Int? {
        switch direction {
        case "DoubleUp": return 1
        case "SingleUp": return 2
        case "FortyFiveUp": return 3
        case "Flat": return 4
        case "FortyFiveDown": return 5
        case "SingleDown": return 6
        case "DoubleDown": return 7
        default: return nil
        }
    }
}

// MARK: - Profile Conversion

extension NightscoutProfileData {
    
    /// Convert from NightscoutKit Profile to Replay NightscoutProfileData
    public static func from(nightscout profile: NightscoutProfileConvertible) -> NightscoutProfileData {
        // Convert basal schedule
        let basalSchedule = profile.basalSchedule.map { entry in
            BasalScheduleEntry(startTime: entry.startTime, rate: entry.rate)
        }
        
        // Convert ISF schedule
        let isfSchedule = profile.isfSchedule.map { entry in
            ScheduleValue(startTime: entry.startTime, value: entry.value)
        }
        
        // Convert CR schedule  
        let crSchedule = profile.crSchedule.map { entry in
            ScheduleValue(startTime: entry.startTime, value: entry.value)
        }
        
        return NightscoutProfileData(
            basalSchedule: basalSchedule,
            isfSchedule: isfSchedule,
            crSchedule: crSchedule,
            targetLow: profile.targetLow,
            targetHigh: profile.targetHigh,
            dia: profile.dia
        )
    }
}

// MARK: - Protocol for Profile Conversion

/// Protocol for types that can be converted to NightscoutProfileData
public protocol NightscoutProfileConvertible {
    var basalSchedule: [(startTime: TimeInterval, rate: Double)] { get }
    var isfSchedule: [(startTime: TimeInterval, value: Double)] { get }
    var crSchedule: [(startTime: TimeInterval, value: Double)] { get }
    var targetLow: Double { get }
    var targetHigh: Double { get }
    var dia: TimeInterval { get }
}

// MARK: - Lightweight NS Data Structures

/// Lightweight structure for NS devicestatus (for CLI/conversion use)
public struct NightscoutDeviceStatusData {
    public let created_at: String
    public let loop: LoopStatusWrapper?
    public let loopSettings: LoopSettingsWrapper?
    
    public init(created_at: String, loop: LoopStatusWrapper?, loopSettings: LoopSettingsWrapper?) {
        self.created_at = created_at
        self.loop = loop
        self.loopSettings = loopSettings
    }
    
    public struct LoopStatusWrapper {
        public let iob: IOBWrapper?
        public let cob: COBWrapper?
        public let predicted: PredictedWrapper?
        public let automaticDoseRecommendation: AutoDoseRecWrapper?
        public let enacted: EnactedWrapper?
        
        public init(iob: IOBWrapper?, cob: COBWrapper?, predicted: PredictedWrapper?,
                    automaticDoseRecommendation: AutoDoseRecWrapper?, enacted: EnactedWrapper?) {
            self.iob = iob
            self.cob = cob
            self.predicted = predicted
            self.automaticDoseRecommendation = automaticDoseRecommendation
            self.enacted = enacted
        }
    }
    
    public struct IOBWrapper {
        public let iob: Double
        public let timestamp: String
        public init(iob: Double, timestamp: String) { self.iob = iob; self.timestamp = timestamp }
    }
    
    public struct COBWrapper {
        public let cob: Double
        public init(cob: Double) { self.cob = cob }
    }
    
    public struct PredictedWrapper {
        public let startDate: String
        public let values: [Int]
        public init(startDate: String, values: [Int]) { self.startDate = startDate; self.values = values }
    }
    
    public struct AutoDoseRecWrapper {
        public let tempBasalAdjustment: TempBasalAdjWrapper?
        public let bolusVolume: Double?
        public init(tempBasalAdjustment: TempBasalAdjWrapper?, bolusVolume: Double?) {
            self.tempBasalAdjustment = tempBasalAdjustment; self.bolusVolume = bolusVolume
        }
    }
    
    public struct TempBasalAdjWrapper {
        public let rate: Double?
        public let duration: Double?
        public init(rate: Double?, duration: Double?) { self.rate = rate; self.duration = duration }
    }
    
    public struct EnactedWrapper {
        public let rate: Double?
        public let duration: Double?
        public let timestamp: String?
        public let received: Bool?
        public init(rate: Double?, duration: Double?, timestamp: String?, received: Bool?) {
            self.rate = rate; self.duration = duration; self.timestamp = timestamp; self.received = received
        }
    }
    
    public struct LoopSettingsWrapper {
        public let minimumBGGuard: Double?
        public let maximumBasalRatePerHour: Double?
        public init(minimumBGGuard: Double?, maximumBasalRatePerHour: Double?) {
            self.minimumBGGuard = minimumBGGuard; self.maximumBasalRatePerHour = maximumBasalRatePerHour
        }
    }
}

/// Lightweight structure for NS treatment (for CLI/conversion use)
public struct NightscoutTreatmentData {
    public let identifier: String
    public let eventType: String
    public let timestamp: String?
    public let created_at: String
    public let rate: Double?
    public let absolute: Double?
    public let duration: Double?
    public let insulin: Double?
    public let carbs: Double?
    
    public init(identifier: String, eventType: String, timestamp: String?, created_at: String,
                rate: Double?, absolute: Double?, duration: Double?, insulin: Double?, carbs: Double?) {
        self.identifier = identifier
        self.eventType = eventType
        self.timestamp = timestamp
        self.created_at = created_at
        self.rate = rate
        self.absolute = absolute
        self.duration = duration
        self.insulin = insulin
        self.carbs = carbs
    }
}

/// Lightweight structure for NS entry (for CLI/conversion use)
public struct NightscoutEntryData {
    public let timestamp: Date
    public let sgv: Int?
    public let direction: String?
    
    public init(timestamp: Date, sgv: Int?, direction: String?) {
        self.timestamp = timestamp
        self.sgv = sgv
        self.direction = direction
    }
}
