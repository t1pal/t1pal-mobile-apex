// InputReconstructor.swift
// T1PalAlgorithm
//
// ALG-ARCH-008: Reconstructs Loop's exact inputs for a given cycle.
// Design: docs/architecture/ALG-ARCH-002-005-design.md
//
// Key insight: Loop's view of data changes every 5 minutes based on
// what was uploaded to Nightscout. This reconstructor filters data
// to match Loop's exact perspective.

import Foundation

/// Reconstructs Loop's exact inputs for a given cycle.
public struct InputReconstructor: Sendable {
    
    /// All treatments from Nightscout (unfiltered)
    private let allTreatments: [TreatmentRecord]
    
    /// All glucose entries from Nightscout
    private let allGlucose: [GlucoseRecord]
    
    /// User's profile
    private let profile: NightscoutProfileData
    
    // MARK: - Initialization
    
    public init(
        treatments: [TreatmentRecord],
        glucose: [GlucoseRecord],
        profile: NightscoutProfileData
    ) {
        self.allTreatments = treatments.sorted { $0.createdAt < $1.createdAt }
        self.allGlucose = glucose.sorted { $0.date < $1.date }
        self.profile = profile
    }
    
    // MARK: - Dose History
    
    /// Build dose history as Loop saw it at this cycle.
    /// Key: Filter by cgmReadingTime (IOB-TIMING-001), use 30-min nominal for active temp.
    ///
    /// IOB-TIMING Architecture:
    /// - IOB-TIMING-001: Orient to cgmReadingTime (predicted.startDate), NOT uploadedAt
    /// - IOB-TIMING-002: Apply 30-min rule to LAST temp before cgmReadingTime
    /// - IOB-TIMING-003: Exclude this cycle's enacted dose (issued AFTER IOB was computed)
    public func buildDoseHistory(for cycle: LoopCycleState) -> [ReplayInsulinDose] {
        let cgmTime = cycle.cgmReadingTime
        
        // IOB-TIMING-003: Get enacted timestamp to exclude (dose was issued AFTER IOB computed)
        let enactedTimestamp = cycle.loopEnacted?.timestamp
        
        // 1. Filter treatments by timestamp relative to CGM time (IOB-TIMING-001)
        // Treatments visible to Loop are those with timestamp <= cgmReadingTime
        let visibleTreatments = allTreatments.filter { treatment in
            treatment.timestamp <= cgmTime
        }
        
        // 2. Extract temp basals and sort by timestamp for duration inference
        var tempBasalTreatments = visibleTreatments.filter { $0.eventType == "Temp Basal" }
            .sorted { $0.timestamp < $1.timestamp }
        
        // IOB-TIMING-003: Exclude enacted dose from this cycle
        // The enacted dose was issued AFTER IOB was computed, so Loop didn't include it
        if let enacted = enactedTimestamp {
            tempBasalTreatments.removeAll { treatment in
                abs(treatment.timestamp.timeIntervalSince(enacted)) < 1
            }
        }
        
        // 3. Build temp basal doses with inferred durations
        // IOB-TIMING-002: Last temp before CGM time uses 30-min nominal duration
        var tempBasalDoses: [ReplayInsulinDose] = []
        let lastTempIndex = tempBasalTreatments.count - 1
        
        for (index, treatment) in tempBasalTreatments.enumerated() {
            guard let rate = treatment.rate ?? treatment.absolute else { continue }
            
            let endDate: Date
            let isLastTemp = (index == lastTempIndex)
            
            if isLastTemp {
                // IOB-TIMING-002: Last temp (currently running) uses 30-min nominal
                // Medtronic pumps have a minimum temp basal duration of 30 minutes
                endDate = treatment.timestamp.addingTimeInterval(30 * 60)
            } else if let duration = treatment.duration, duration > 0 {
                // Superseded temp - use NS-stored (clipped) duration
                endDate = treatment.timestamp.addingTimeInterval(duration * 60)
            } else if index + 1 < tempBasalTreatments.count {
                // Infer duration from next temp basal start (supersede)
                endDate = tempBasalTreatments[index + 1].timestamp
            } else {
                // Fallback (shouldn't reach here since isLastTemp handles it)
                endDate = treatment.timestamp.addingTimeInterval(30 * 60)
            }
            
            tempBasalDoses.append(ReplayInsulinDose(
                type: .tempBasal,
                startDate: treatment.timestamp,
                endDate: endDate,
                rate: rate,
                units: nil,
                createdAt: treatment.createdAt
            ))
        }
        
        // 4. Convert boluses (also filter by timestamp <= cgmTime)
        let bolusDoses = visibleTreatments.compactMap { treatment -> ReplayInsulinDose? in
            switch treatment.eventType {
            case "Correction Bolus", "Bolus", "SMB":
                guard let insulin = treatment.insulin, insulin > 0 else { return nil }
                return ReplayInsulinDose(
                    type: .bolus,
                    startDate: treatment.timestamp,
                    endDate: treatment.timestamp,
                    rate: nil,
                    units: insulin,
                    createdAt: treatment.createdAt
                )
            default:
                return nil
            }
        }
        
        // 5. Combine and sort
        var doses = tempBasalDoses + bolusDoses
        doses.sort { $0.startDate < $1.startDate }
        
        return doses
    }
    
    // MARK: - Glucose History
    
    /// Build glucose history up to the CGM reading time.
    public func buildGlucoseHistory(
        for cycle: LoopCycleState,
        lookback: TimeInterval = 6 * 3600  // 6 hours
    ) -> [GlucoseRecord] {
        let cutoff = cycle.cgmReadingTime
        let start = cutoff.addingTimeInterval(-lookback)
        
        return allGlucose.filter { entry in
            entry.date >= start && entry.date <= cutoff
        }
    }
    
    // MARK: - IOB Input (includingPendingInsulin: false)
    
    /// Build input for IOB calculation (reported IOB, not prediction IOB).
    /// Key: includingPendingInsulin = false, calculate at iob.timestamp
    public func buildIOBInput(for cycle: LoopCycleState) -> IOBInput {
        let doses = buildDoseHistory(for: cycle)
        
        return IOBInput(
            doses: doses,
            calculationTime: cycle.iobCalculationTime,
            basalSchedule: cycle.settings.basalSchedule,
            insulinModel: cycle.settings.insulinModel,
            dia: cycle.settings.dia,
            includingPendingInsulin: false,  // ALWAYS false for reported IOB
            profileTimezone: profile.timezone  // IOB-TZ-001
        )
    }
    
    // MARK: - Prediction Input (includingPendingInsulin: true)
    
    /// Build input for prediction calculation.
    /// Key: includingPendingInsulin = true
    public func buildPredictionInput(for cycle: LoopCycleState) -> PredictionInput {
        let doses = buildDoseHistory(for: cycle)
        let glucose = buildGlucoseHistory(for: cycle)
        let carbs = buildCarbHistory(for: cycle)
        
        return PredictionInput(
            doses: doses,
            glucose: glucose,
            carbs: carbs,
            predictionStart: cycle.cgmReadingTime,
            basalSchedule: cycle.settings.basalSchedule,
            insulinModel: cycle.settings.insulinModel,
            dia: cycle.settings.dia,
            isf: cycle.settings.insulinSensitivity,
            carbRatio: cycle.settings.carbRatio,
            targetRange: cycle.settings.targetRange,
            suspendThreshold: cycle.settings.suspendThreshold,
            maxBasalRate: cycle.settings.maxBasalRate,
            includingPendingInsulin: true,  // ALWAYS true for prediction
            profileTimezone: profile.timezone  // IOB-TZ-001
        )
    }
    
    // MARK: - Carb History
    
    /// Build carb history up to the upload time.
    public func buildCarbHistory(
        for cycle: LoopCycleState,
        lookback: TimeInterval = 6 * 3600  // 6 hours
    ) -> [CarbRecord] {
        let cutoff = cycle.uploadedAt  // Use upload time for carbs
        let start = cutoff.addingTimeInterval(-lookback)
        
        return allTreatments
            .filter { $0.eventType == "Carb Correction" || ($0.carbs ?? 0) > 0 }
            .filter { $0.createdAt >= start && $0.createdAt <= cutoff }
            .map { CarbRecord(date: $0.timestamp, grams: $0.carbs ?? 0, createdAt: $0.createdAt) }
    }
    
    // MARK: - Profile Lookup
    
    /// Get basal rate at a specific time from profile
    public func basalRate(at date: Date) -> Double {
        let secondsFromMidnight = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        
        // Find the applicable basal entry
        let applicableEntry = profile.basalSchedule
            .filter { $0.startTime <= secondsFromMidnight }
            .max(by: { $0.startTime < $1.startTime })
        
        return applicableEntry?.rate ?? profile.basalSchedule.first?.rate ?? 0
    }
    
    /// Get ISF at a specific time from profile
    public func insulinSensitivity(at date: Date) -> Double {
        let secondsFromMidnight = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        
        let applicableEntry = profile.isfSchedule
            .filter { $0.startTime <= secondsFromMidnight }
            .max(by: { $0.startTime < $1.startTime })
        
        return applicableEntry?.value ?? profile.isfSchedule.first?.value ?? 50
    }
    
    /// Get carb ratio at a specific time from profile
    public func carbRatio(at date: Date) -> Double {
        let secondsFromMidnight = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        
        let applicableEntry = profile.crSchedule
            .filter { $0.startTime <= secondsFromMidnight }
            .max(by: { $0.startTime < $1.startTime })
        
        return applicableEntry?.value ?? profile.crSchedule.first?.value ?? 10
    }
}

// MARK: - Input Types

/// Input for IOB calculation
public struct IOBInput: Sendable {
    public let doses: [ReplayInsulinDose]
    public let calculationTime: Date
    public let basalSchedule: [BasalScheduleEntry]
    public let insulinModel: InsulinModelType
    public let dia: TimeInterval
    public let includingPendingInsulin: Bool
    /// IOB-TZ-001: Profile timezone for interpreting basal schedule times
    public let profileTimezone: TimeZone?
    
    public init(
        doses: [ReplayInsulinDose],
        calculationTime: Date,
        basalSchedule: [BasalScheduleEntry],
        insulinModel: InsulinModelType,
        dia: TimeInterval,
        includingPendingInsulin: Bool,
        profileTimezone: TimeZone? = nil
    ) {
        self.doses = doses
        self.calculationTime = calculationTime
        self.basalSchedule = basalSchedule
        self.insulinModel = insulinModel
        self.dia = dia
        self.includingPendingInsulin = includingPendingInsulin
        self.profileTimezone = profileTimezone
    }
}

/// Input for prediction calculation
public struct PredictionInput: Sendable {
    public let doses: [ReplayInsulinDose]
    public let glucose: [GlucoseRecord]
    public let carbs: [CarbRecord]
    public let predictionStart: Date
    public let basalSchedule: [BasalScheduleEntry]
    public let insulinModel: InsulinModelType
    public let dia: TimeInterval
    public let isf: Double
    public let carbRatio: Double
    public let targetRange: ClosedRange<Double>
    public let suspendThreshold: Double
    public let maxBasalRate: Double
    public let includingPendingInsulin: Bool
    /// IOB-TZ-001: Profile timezone for interpreting basal schedule times
    public let profileTimezone: TimeZone?
    
    public init(
        doses: [ReplayInsulinDose],
        glucose: [GlucoseRecord],
        carbs: [CarbRecord],
        predictionStart: Date,
        basalSchedule: [BasalScheduleEntry],
        insulinModel: InsulinModelType,
        dia: TimeInterval,
        isf: Double,
        carbRatio: Double,
        targetRange: ClosedRange<Double>,
        suspendThreshold: Double,
        maxBasalRate: Double,
        includingPendingInsulin: Bool,
        profileTimezone: TimeZone? = nil
    ) {
        self.doses = doses
        self.glucose = glucose
        self.carbs = carbs
        self.predictionStart = predictionStart
        self.basalSchedule = basalSchedule
        self.insulinModel = insulinModel
        self.dia = dia
        self.isf = isf
        self.carbRatio = carbRatio
        self.targetRange = targetRange
        self.suspendThreshold = suspendThreshold
        self.maxBasalRate = maxBasalRate
        self.includingPendingInsulin = includingPendingInsulin
        self.profileTimezone = profileTimezone
    }
}

// MARK: - Record Types

/// Insulin dose record
public struct ReplayInsulinDose: Sendable, Equatable {
    public enum DoseType: Sendable, Equatable {
        case bolus
        case tempBasal
        case basal
    }
    
    public let type: DoseType
    public let startDate: Date
    public let endDate: Date
    public let rate: Double?  // U/hr for temp basal
    public let units: Double? // U for bolus
    public let createdAt: Date?  // When uploaded to NS
    
    public init(
        type: DoseType,
        startDate: Date,
        endDate: Date,
        rate: Double? = nil,
        units: Double? = nil,
        createdAt: Date? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.rate = rate
        self.units = units
        self.createdAt = createdAt
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    /// Units delivered (for temp basal, calculated from rate * duration)
    public var deliveredUnits: Double {
        switch type {
        case .bolus:
            return units ?? 0
        case .tempBasal, .basal:
            let hours = duration / 3600
            return (rate ?? 0) * hours
        }
    }
}

/// Glucose record
public struct GlucoseRecord: Sendable, Equatable {
    public let date: Date
    public let value: Double  // mg/dL
    public let trend: Int?    // Dexcom trend direction
    
    public init(date: Date, value: Double, trend: Int? = nil) {
        self.date = date
        self.value = value
        self.trend = trend
    }
}

/// Carb record
public struct CarbRecord: Sendable, Equatable {
    public let date: Date
    public let grams: Double
    public let createdAt: Date?
    
    public init(date: Date, grams: Double, createdAt: Date? = nil) {
        self.date = date
        self.grams = grams
        self.createdAt = createdAt
    }
}

/// Treatment record from Nightscout
public struct TreatmentRecord: Sendable {
    public let identifier: String
    public let eventType: String
    public let timestamp: Date
    public let createdAt: Date
    public let rate: Double?         // Temp basal rate
    public let absolute: Double?     // Absolute rate
    public let duration: Double?     // Duration in minutes
    public let insulin: Double?      // Bolus amount
    public let carbs: Double?        // Carb amount
    
    public init(
        identifier: String,
        eventType: String,
        timestamp: Date,
        createdAt: Date,
        rate: Double? = nil,
        absolute: Double? = nil,
        duration: Double? = nil,
        insulin: Double? = nil,
        carbs: Double? = nil
    ) {
        self.identifier = identifier
        self.eventType = eventType
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.rate = rate
        self.absolute = absolute
        self.duration = duration
        self.insulin = insulin
        self.carbs = carbs
    }
}

/// Nightscout profile data
public struct NightscoutProfileData: Sendable {
    public let basalSchedule: [BasalScheduleEntry]
    public let isfSchedule: [ScheduleValue]
    public let crSchedule: [ScheduleValue]
    public let targetLow: Double
    public let targetHigh: Double
    public let dia: TimeInterval
    /// IOB-TZ-001: Profile timezone for interpreting schedule times (e.g., "ETC/GMT+8")
    public let timezone: TimeZone?
    
    public init(
        basalSchedule: [BasalScheduleEntry],
        isfSchedule: [ScheduleValue],
        crSchedule: [ScheduleValue],
        targetLow: Double,
        targetHigh: Double,
        dia: TimeInterval,
        timezone: TimeZone? = nil
    ) {
        self.basalSchedule = basalSchedule
        self.isfSchedule = isfSchedule
        self.crSchedule = crSchedule
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.dia = dia
        self.timezone = timezone
    }
}

/// Schedule value entry (for ISF, CR)
public struct ScheduleValue: Sendable {
    public let startTime: TimeInterval  // Seconds from midnight
    public let value: Double
    
    public init(startTime: TimeInterval, value: Double) {
        self.startTime = startTime
        self.value = value
    }
}
