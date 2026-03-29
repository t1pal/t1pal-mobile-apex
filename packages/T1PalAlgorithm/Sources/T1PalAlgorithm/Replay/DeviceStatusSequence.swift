// DeviceStatusSequence.swift
// T1PalAlgorithm
//
// ALG-ARCH-007: Ordered sequence of devicestatus records with cross-record linking.
// Design: docs/architecture/ALG-ARCH-002-005-design.md

import Foundation

/// Ordered sequence of devicestatus records with cross-record linking.
/// Provides gap detection and iteration over LoopCycleState.
public final class DeviceStatusSequence: Sendable {
    
    /// Linked cycle states (computed once on init)
    public let cycles: [LoopCycleState]
    
    /// Gaps detected in the sequence (>6 min between records)
    public let gaps: [SequenceGap]
    
    /// Default settings to use when devicestatus lacks settings
    private let defaultSettings: TherapySettingsSnapshot
    
    // MARK: - Initialization
    
    /// Create from raw Nightscout devicestatus records
    public init(
        records: [DeviceStatusRecord],
        defaultSettings: TherapySettingsSnapshot
    ) {
        self.defaultSettings = defaultSettings
        // ALG-ZERO-DIV-009: Sort and deduplicate by createdAt
        let sorted = records.sorted { $0.createdAt < $1.createdAt }
        let deduplicated = Self.deduplicateByTimestamp(sorted)
        (self.cycles, self.gaps) = Self.linkRecords(deduplicated, defaultSettings: defaultSettings)
    }
    
    /// Deduplicate records by createdAt (keep first occurrence)
    /// ALG-ZERO-DIV-009: Prevents duplicate devicestatus from affecting IOB stats
    private static func deduplicateByTimestamp(_ records: [DeviceStatusRecord]) -> [DeviceStatusRecord] {
        var seen = Set<Date>()
        return records.filter { record in
            if seen.contains(record.createdAt) {
                return false
            }
            seen.insert(record.createdAt)
            return true
        }
    }
    
    // MARK: - Collection Interface
    
    /// Number of cycles
    public var count: Int { cycles.count }
    
    /// True if no cycles
    public var isEmpty: Bool { cycles.isEmpty }
    
    /// Access by index
    public subscript(index: Int) -> LoopCycleState {
        cycles[index]
    }
    
    /// First cycle (if any)
    public var first: LoopCycleState? { cycles.first }
    
    /// Last cycle (if any)
    public var last: LoopCycleState? { cycles.last }
    
    // MARK: - Gap Analysis
    
    /// True if any gaps > 6 minutes exist
    public var hasGaps: Bool { !gaps.isEmpty }
    
    /// Total gap duration in minutes
    public var totalGapMinutes: Double {
        gaps.reduce(0) { $0 + $1.durationMinutes }
    }
    
    /// Cycles that follow a gap (may have unreliable cross-record state)
    public var cyclesAfterGap: [LoopCycleState] {
        cycles.filter { $0.hasGapFromPrevious }
    }
    
    // MARK: - Private Linking Logic
    
    private static func linkRecords(
        _ records: [DeviceStatusRecord],
        defaultSettings: TherapySettingsSnapshot
    ) -> ([LoopCycleState], [SequenceGap]) {
        var cycles: [LoopCycleState] = []
        var gaps: [SequenceGap] = []
        
        for (index, record) in records.enumerated() {
            // Get previous record (if exists)
            let previous: DeviceStatusRecord? = index > 0 ? records[index - 1] : nil
            
            // Detect gap (>6 min from previous)
            let hasGap: Bool
            if let prev = previous {
                let delta = record.createdAt.timeIntervalSince(prev.createdAt)
                hasGap = delta > 360  // 6 minutes
                if hasGap {
                    gaps.append(SequenceGap(
                        afterCycleIndex: index - 1,
                        duration: delta,
                        previousCreatedAt: prev.createdAt,
                        nextCreatedAt: record.createdAt
                    ))
                }
            } else {
                hasGap = false  // First record has no gap
            }
            
            // Extract previous enacted (with 30-min nominal for active)
            let previousEnacted: EnactedDose? = previous?.loop.enacted.map { enacted in
                EnactedDose(
                    rate: enacted.rate,
                    duration: 30,  // Always 30-min nominal for active
                    timestamp: enacted.timestamp,
                    received: enacted.received
                )
            }
            
            // Extract settings from devicestatus or use defaults
            let settings = record.loopSettings.map { loopSettings in
                TherapySettingsSnapshot(
                    suspendThreshold: loopSettings.minimumBGGuard ?? defaultSettings.suspendThreshold,
                    maxBasalRate: loopSettings.maximumBasalRatePerHour ?? defaultSettings.maxBasalRate,
                    insulinSensitivity: defaultSettings.insulinSensitivity,  // NS devicestatus lacks ISF
                    carbRatio: defaultSettings.carbRatio,
                    targetLow: defaultSettings.targetLow,
                    targetHigh: defaultSettings.targetHigh,
                    basalSchedule: defaultSettings.basalSchedule,
                    insulinModel: defaultSettings.insulinModel,
                    dia: defaultSettings.dia
                )
            } ?? defaultSettings
            
            // Build cycle state
            let cycle = LoopCycleState(
                deviceStatusID: record.identifier,
                cycleIndex: index,
                uploadedAt: record.createdAt,
                cgmReadingTime: record.loop.predicted.startDate,
                iobCalculationTime: record.loop.iob.timestamp,
                loopReportedIOB: record.loop.iob.iob,
                loopReportedCOB: record.loop.cob?.cob ?? 0,
                loopPrediction: record.loop.predicted.values,
                loopRecommendation: record.loop.automaticDoseRecommendation.map {
                    ReplayDoseRecommendation(
                        tempBasalRate: $0.tempBasalRate,
                        tempBasalDuration: $0.tempBasalDuration,
                        bolusVolume: $0.bolusVolume
                    )
                },
                loopEnacted: record.loop.enacted.map {
                    EnactedDose(
                        rate: $0.rate,
                        duration: $0.duration,
                        timestamp: $0.timestamp,
                        received: $0.received
                    )
                },
                previousEnacted: previousEnacted,
                hasGapFromPrevious: hasGap,
                settings: settings
            )
            
            cycles.append(cycle)
        }
        
        return (cycles, gaps)
    }
}

// MARK: - Sequence Conformance

extension DeviceStatusSequence: Sequence {
    public func makeIterator() -> IndexingIterator<[LoopCycleState]> {
        cycles.makeIterator()
    }
}

// MARK: - Collection Conformance

extension DeviceStatusSequence: Collection {
    public var startIndex: Int { cycles.startIndex }
    public var endIndex: Int { cycles.endIndex }
    
    public func index(after i: Int) -> Int {
        cycles.index(after: i)
    }
}

// MARK: - Sequence Gap

/// Represents a gap in the devicestatus sequence
public struct SequenceGap: Sendable {
    /// Index of cycle before the gap
    public let afterCycleIndex: Int
    /// Duration of gap in seconds
    public let duration: TimeInterval
    /// Timestamp of record before gap
    public let previousCreatedAt: Date
    /// Timestamp of record after gap
    public let nextCreatedAt: Date
    
    public var durationMinutes: Double {
        duration / 60.0
    }
    
    /// True if gap is extended (>15 min, cross-record state unreliable)
    public var isExtended: Bool {
        duration > 900  // 15 minutes
    }
}

// MARK: - Raw DeviceStatus Record

/// Raw devicestatus record from Nightscout (before linking)
public struct DeviceStatusRecord: Sendable {
    public let identifier: String
    public let createdAt: Date
    public let loop: LoopStatusData
    public let loopSettings: LoopSettingsData?
    
    public init(
        identifier: String,
        createdAt: Date,
        loop: LoopStatusData,
        loopSettings: LoopSettingsData? = nil
    ) {
        self.identifier = identifier
        self.createdAt = createdAt
        self.loop = loop
        self.loopSettings = loopSettings
    }
}

/// Loop status data from devicestatus.loop
public struct LoopStatusData: Sendable {
    public let iob: IOBData
    public let cob: COBData?
    public let predicted: PredictedData
    public let automaticDoseRecommendation: AutomaticDoseRecommendationData?
    public let enacted: EnactedData?
    
    public init(
        iob: IOBData,
        cob: COBData? = nil,
        predicted: PredictedData,
        automaticDoseRecommendation: AutomaticDoseRecommendationData? = nil,
        enacted: EnactedData? = nil
    ) {
        self.iob = iob
        self.cob = cob
        self.predicted = predicted
        self.automaticDoseRecommendation = automaticDoseRecommendation
        self.enacted = enacted
    }
}

/// IOB data from devicestatus.loop.iob
public struct IOBData: Sendable {
    public let iob: Double
    public let timestamp: Date
    
    public init(iob: Double, timestamp: Date) {
        self.iob = iob
        self.timestamp = timestamp
    }
}

/// COB data from devicestatus.loop.cob
public struct COBData: Sendable {
    public let cob: Double
    
    public init(cob: Double) {
        self.cob = cob
    }
}

/// Predicted data from devicestatus.loop.predicted
public struct PredictedData: Sendable {
    public let startDate: Date
    public let values: [Int]
    
    public init(startDate: Date, values: [Int]) {
        self.startDate = startDate
        self.values = values
    }
}

/// Automatic dose recommendation data
public struct AutomaticDoseRecommendationData: Sendable {
    public let tempBasalRate: Double?
    public let tempBasalDuration: Double?
    public let bolusVolume: Double?
    
    public init(
        tempBasalRate: Double? = nil,
        tempBasalDuration: Double? = nil,
        bolusVolume: Double? = nil
    ) {
        self.tempBasalRate = tempBasalRate
        self.tempBasalDuration = tempBasalDuration
        self.bolusVolume = bolusVolume
    }
}

/// Enacted data from devicestatus.loop.enacted
public struct EnactedData: Sendable {
    public let rate: Double
    public let duration: Double
    public let timestamp: Date
    public let received: Bool
    
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
}

/// Loop settings from devicestatus.loopSettings
public struct LoopSettingsData: Sendable {
    public let minimumBGGuard: Double?
    public let maximumBasalRatePerHour: Double?
    
    public init(
        minimumBGGuard: Double? = nil,
        maximumBasalRatePerHour: Double? = nil
    ) {
        self.minimumBGGuard = minimumBGGuard
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
    }
}
