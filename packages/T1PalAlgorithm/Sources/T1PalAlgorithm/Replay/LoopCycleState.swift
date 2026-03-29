// LoopCycleState.swift
// T1PalAlgorithm
//
// ALG-ARCH-006: Immutable snapshot of Loop's state at a single 5-minute cycle.
// Design: docs/architecture/ALG-ARCH-002-005-design.md

import Foundation

/// Represents Loop's state at a single 5-minute cycle.
/// All fields are immutable - this is a snapshot of what Loop knew.
public struct LoopCycleState: Sendable, Identifiable {
    
    // MARK: - Identity
    
    /// Unique identifier for this cycle
    public var id: String { deviceStatusID }
    
    /// The devicestatus record this cycle represents
    public let deviceStatusID: String
    
    /// Index in the sequence (0-based)
    public let cycleIndex: Int
    
    // MARK: - Three Key Timestamps
    
    /// When the devicestatus was uploaded to Nightscout
    /// Used for: filtering treatments (created_at <= this)
    public let uploadedAt: Date  // devicestatus.created_at
    
    /// When the CGM reading was received (triggers the cycle)
    /// Used for: prediction start, glucose history cutoff
    public let cgmReadingTime: Date  // loop.predicted.startDate
    
    /// Grid-snapped time for IOB calculation (ceil to 5-min)
    /// Used for: IOB comparison point
    public let iobCalculationTime: Date  // loop.iob.timestamp
    
    // MARK: - Loop's Reported Values (for comparison)
    
    /// Loop's reported IOB (includingPendingInsulin: false)
    public let loopReportedIOB: Double  // loop.iob.iob
    
    /// Loop's reported COB
    public let loopReportedCOB: Double  // loop.cob.cob
    
    /// Loop's prediction array (mg/dL values, 5-min intervals)
    public let loopPrediction: [Int]  // loop.predicted.values
    
    /// Loop's raw algorithm output (before ifNecessary filter)
    public let loopRecommendation: ReplayDoseRecommendation?  // loop.automaticDoseRecommendation
    
    /// What Loop actually sent to the pump
    public let loopEnacted: EnactedDose?  // loop.enacted
    
    // MARK: - Cross-Record State (from N-1)
    
    /// The enacted dose from the PREVIOUS cycle
    /// This is the "active temp basal" that affects this cycle's IOB
    public let previousEnacted: EnactedDose?
    
    /// Gap flag: true if >6 minutes since previous devicestatus
    public let hasGapFromPrevious: Bool
    
    // MARK: - Settings Snapshot
    
    /// User's therapy settings at this cycle
    public let settings: TherapySettingsSnapshot
    
    // MARK: - Initialization
    
    public init(
        deviceStatusID: String,
        cycleIndex: Int,
        uploadedAt: Date,
        cgmReadingTime: Date,
        iobCalculationTime: Date,
        loopReportedIOB: Double,
        loopReportedCOB: Double,
        loopPrediction: [Int],
        loopRecommendation: ReplayDoseRecommendation?,
        loopEnacted: EnactedDose?,
        previousEnacted: EnactedDose?,
        hasGapFromPrevious: Bool,
        settings: TherapySettingsSnapshot
    ) {
        self.deviceStatusID = deviceStatusID
        self.cycleIndex = cycleIndex
        self.uploadedAt = uploadedAt
        self.cgmReadingTime = cgmReadingTime
        self.iobCalculationTime = iobCalculationTime
        self.loopReportedIOB = loopReportedIOB
        self.loopReportedCOB = loopReportedCOB
        self.loopPrediction = loopPrediction
        self.loopRecommendation = loopRecommendation
        self.loopEnacted = loopEnacted
        self.previousEnacted = previousEnacted
        self.hasGapFromPrevious = hasGapFromPrevious
        self.settings = settings
    }
}

// MARK: - Replay Dose Recommendation

/// Dose recommendation from automaticDoseRecommendation (replay-specific)
public struct ReplayDoseRecommendation: Sendable, Equatable {
    public let tempBasalRate: Double?      // tempBasalAdjustment.rate (U/hr)
    public let tempBasalDuration: Double?  // tempBasalAdjustment.duration (minutes)
    public let bolusVolume: Double?        // bolusVolume (U)
    
    public init(
        tempBasalRate: Double? = nil,
        tempBasalDuration: Double? = nil,
        bolusVolume: Double? = nil
    ) {
        self.tempBasalRate = tempBasalRate
        self.tempBasalDuration = tempBasalDuration
        self.bolusVolume = bolusVolume
    }
    
    /// True if this recommends a temp basal adjustment
    public var hasTempBasal: Bool {
        tempBasalRate != nil
    }
    
    /// True if this recommends a bolus (SMB)
    public var hasBolus: Bool {
        (bolusVolume ?? 0) > 0
    }
}

// MARK: - Enacted Dose

/// Enacted dose (what was sent to pump)
public struct EnactedDose: Sendable, Equatable {
    public let rate: Double       // U/hr
    public let duration: Double   // minutes (nominal 30, actual varies)
    public let timestamp: Date    // when enacted
    public let received: Bool     // pump acknowledged
    
    public init(
        rate: Double,
        duration: Double,
        timestamp: Date,
        received: Bool = true
    ) {
        self.rate = rate
        self.duration = duration
        self.timestamp = timestamp
        self.received = received
    }
    
    /// The nominal 30-minute version for active temp calculation
    public var withNominalDuration: EnactedDose {
        EnactedDose(
            rate: rate,
            duration: 30,  // Always 30-min nominal for active
            timestamp: timestamp,
            received: received
        )
    }
    
    /// End time based on duration
    public var endTime: Date {
        timestamp.addingTimeInterval(duration * 60)
    }
}

// MARK: - Therapy Settings Snapshot

/// Therapy settings snapshot at a specific time
public struct TherapySettingsSnapshot: Sendable {
    public let suspendThreshold: Double        // minimumBGGuard (mg/dL)
    public let maxBasalRate: Double            // maximumBasalRatePerHour (U/hr)
    public let insulinSensitivity: Double      // ISF at cycle time (mg/dL per U)
    public let carbRatio: Double               // CR at cycle time (g per U)
    public let targetLow: Double               // target_low (mg/dL)
    public let targetHigh: Double              // target_high (mg/dL)
    public let basalSchedule: [BasalScheduleEntry]
    public let insulinModel: InsulinModelType
    public let dia: TimeInterval               // Duration of insulin action (seconds)
    
    public init(
        suspendThreshold: Double,
        maxBasalRate: Double,
        insulinSensitivity: Double,
        carbRatio: Double,
        targetLow: Double,
        targetHigh: Double,
        basalSchedule: [BasalScheduleEntry],
        insulinModel: InsulinModelType = .rapidActingAdult,
        dia: TimeInterval = 6 * 3600  // 6 hours default
    ) {
        self.suspendThreshold = suspendThreshold
        self.maxBasalRate = maxBasalRate
        self.insulinSensitivity = insulinSensitivity
        self.carbRatio = carbRatio
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.basalSchedule = basalSchedule
        self.insulinModel = insulinModel
        self.dia = dia
    }
    
    /// Target range as ClosedRange
    public var targetRange: ClosedRange<Double> {
        targetLow...targetHigh
    }
}

/// Insulin model types (matching Loop's presets)
public enum InsulinModelType: String, Sendable, CaseIterable {
    case rapidActingAdult = "rapidActingAdult"
    case rapidActingChild = "rapidActingChild"
    case fiasp = "fiasp"
    case lyumjev = "lyumjev"
    case afrezza = "afrezza"
    
    /// Peak time in minutes
    public var peakMinutes: Double {
        switch self {
        case .rapidActingAdult: return 75
        case .rapidActingChild: return 65
        case .fiasp: return 55
        case .lyumjev: return 55
        case .afrezza: return 29
        }
    }
    
    /// Delay in minutes
    public var delayMinutes: Double {
        switch self {
        case .afrezza: return 0
        default: return 10
        }
    }
}
