// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopDataStalenessParity.swift
// T1Pal Mobile
//
// Loop-compatible data staleness checks and graceful degradation
// Trace: ALG-FIDELITY-019, GAP-058..061
//
// Key concepts from Loop:
// - Glucose recency check (15 min max age)
// - Continuity validation (no gaps > 5 min)
// - Gradual transition check (no jumps > 40 mg/dL)
// - Graceful degradation (return empty vs throw error)

import Foundation

// MARK: - Data Quality Constants

/// Constants for data quality validation matching Loop's thresholds
/// Source: externals/LoopAlgorithm/Sources/LoopAlgorithm/
public enum DataQualityConstants {
    /// Maximum time between readings to be "continuous"
    /// Source: 5-minute CGM interval
    public static let continuityInterval: TimeInterval = .minutes(5)
    
    /// Maximum acceptable gap (slightly more than one reading)
    /// 1.05 × 5 min = ~5 min 15 sec buffer
    public static let maxGapFactor: Double = 1.05
    
    /// Maximum glucose jump between consecutive readings
    /// Source: Loop's momentum validation
    public static let gradualTransitionThreshold: Double = 40.0  // mg/dL
    
    /// Maximum age of most recent glucose (hard failure)
    /// Source: inputDataRecencyInterval = 15 minutes
    public static let maxGlucoseAge: TimeInterval = .minutes(15)
    
    /// Minimum readings for momentum calculation (linear regression)
    /// Source: Loop requires count > 2 (needs 3+)
    public static let minimumReadingsForMomentum: Int = 3
    
    /// Maximum dose history gap before gap filling (30 minutes)
    public static let maxDoseHistoryGap: TimeInterval = .minutes(30)
}

// MARK: - Glucose Reading Protocol

/// Protocol for glucose readings used in validation
public protocol GlucoseReadingProtocol: Sendable {
    var timestamp: Date { get }
    var glucose: Double { get }
    var sourceIdentifier: String? { get }
    var isCalibration: Bool { get }
}

// MARK: - Simple Glucose Reading

/// Simple implementation of glucose reading for validation
public struct SimpleGlucoseReading: GlucoseReadingProtocol, Sendable {
    public let timestamp: Date
    public let glucose: Double
    public let sourceIdentifier: String?
    public let isCalibration: Bool
    
    public init(
        timestamp: Date,
        glucose: Double,
        sourceIdentifier: String? = nil,
        isCalibration: Bool = false
    ) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.sourceIdentifier = sourceIdentifier
        self.isCalibration = isCalibration
    }
}

// MARK: - Momentum Disabled Reason (GAP-058)

/// Reasons momentum calculation is disabled
public enum MomentumDisabledReason: String, Codable, Sendable {
    /// Gap detected in CGM data
    case discontinuous = "discontinuous"
    
    /// Jump > 40 mg/dL between readings
    case largeJumps = "large_jumps"
    
    /// Calibration reading in data
    case calibrationPresent = "calibration_present"
    
    /// Multiple CGM sources in data
    case multipleProvenance = "multiple_provenance"
    
    /// Not enough readings for regression
    case insufficientData = "insufficient_data"
}

// MARK: - Glucose Data Quality (GAP-058, GAP-059)

/// Result of CGM data quality validation
public struct GlucoseDataQuality: Sendable, Equatable {
    /// Whether data is continuous (no gaps > interval × factor)
    public let isContinuous: Bool
    
    /// Whether data has gradual transitions (no jumps > threshold)
    public let hasGradualTransitions: Bool
    
    /// Whether data is from single source
    public let hasSingleProvenance: Bool
    
    /// Whether data contains calibration readings
    public let containsCalibrations: Bool
    
    public init(
        isContinuous: Bool,
        hasGradualTransitions: Bool,
        hasSingleProvenance: Bool,
        containsCalibrations: Bool
    ) {
        self.isContinuous = isContinuous
        self.hasGradualTransitions = hasGradualTransitions
        self.hasSingleProvenance = hasSingleProvenance
        self.containsCalibrations = containsCalibrations
    }
    
    /// Overall quality suitable for momentum calculation
    public var isValidForMomentum: Bool {
        isContinuous && hasGradualTransitions && !containsCalibrations && hasSingleProvenance
    }
    
    /// Reasons momentum is disabled (for telemetry)
    public var momentumDisabledReasons: [MomentumDisabledReason] {
        var reasons: [MomentumDisabledReason] = []
        if !isContinuous { reasons.append(.discontinuous) }
        if !hasGradualTransitions { reasons.append(.largeJumps) }
        if containsCalibrations { reasons.append(.calibrationPresent) }
        if !hasSingleProvenance { reasons.append(.multipleProvenance) }
        return reasons
    }
    
    /// Valid data quality (all checks pass)
    public static let valid = GlucoseDataQuality(
        isContinuous: true,
        hasGradualTransitions: true,
        hasSingleProvenance: true,
        containsCalibrations: false
    )
    
    /// Invalid data quality (all checks fail)
    public static let invalid = GlucoseDataQuality(
        isContinuous: false,
        hasGradualTransitions: false,
        hasSingleProvenance: false,
        containsCalibrations: true
    )
}

// MARK: - Data Quality Validator

/// Validates glucose data quality for algorithm use
public struct DataQualityValidator: Sendable {
    
    public init() {}
    
    // MARK: - Continuity Check (GAP-058)
    
    /// Check if glucose readings are continuous (no gaps)
    /// - Parameters:
    ///   - readings: Glucose readings (should be time-ordered)
    ///   - interval: Expected interval between readings
    ///   - maxGapFactor: Multiplier for acceptable gap (1.05 = 5% buffer)
    /// - Returns: true if readings are continuous
    public func isContinuous<T: GlucoseReadingProtocol>(
        _ readings: [T],
        interval: TimeInterval = DataQualityConstants.continuityInterval,
        maxGapFactor: Double = DataQualityConstants.maxGapFactor
    ) -> Bool {
        guard readings.count > 1 else {
            return readings.count == 1  // Single reading is "continuous"
        }
        
        let maxGap = interval * maxGapFactor
        
        for i in 0..<(readings.count - 1) {
            let gap = abs(readings[i + 1].timestamp.timeIntervalSince(readings[i].timestamp))
            if gap > maxGap {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Gradual Transition Check (GAP-059)
    
    /// Check if glucose readings have gradual transitions (no large jumps)
    /// - Parameters:
    ///   - readings: Glucose readings
    ///   - threshold: Maximum acceptable jump (mg/dL)
    /// - Returns: true if all transitions are gradual
    public func hasGradualTransitions<T: GlucoseReadingProtocol>(
        _ readings: [T],
        threshold: Double = DataQualityConstants.gradualTransitionThreshold
    ) -> Bool {
        guard readings.count > 1 else {
            return true  // Single reading can't have jumps
        }
        
        for i in 0..<(readings.count - 1) {
            let difference = abs(readings[i + 1].glucose - readings[i].glucose)
            if difference > threshold {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Provenance Check
    
    /// Check if glucose readings are from single source
    /// - Parameter readings: Glucose readings
    /// - Returns: true if all from same source (or source is nil)
    public func hasSingleProvenance<T: GlucoseReadingProtocol>(_ readings: [T]) -> Bool {
        guard let firstSource = readings.first?.sourceIdentifier else {
            return true  // No source info = assume single source
        }
        
        return readings.allSatisfy { $0.sourceIdentifier == firstSource || $0.sourceIdentifier == nil }
    }
    
    // MARK: - Calibration Check
    
    /// Check if glucose readings contain calibration entries
    /// - Parameter readings: Glucose readings
    /// - Returns: true if any reading is a calibration
    public func containsCalibrations<T: GlucoseReadingProtocol>(_ readings: [T]) -> Bool {
        readings.contains { $0.isCalibration }
    }
    
    // MARK: - Full Quality Assessment
    
    /// Full quality assessment for momentum calculation
    /// - Parameter readings: Glucose readings
    /// - Returns: GlucoseDataQuality with all checks
    public func assessQuality<T: GlucoseReadingProtocol>(_ readings: [T]) -> GlucoseDataQuality {
        guard readings.count >= DataQualityConstants.minimumReadingsForMomentum else {
            // Insufficient data
            return GlucoseDataQuality(
                isContinuous: false,
                hasGradualTransitions: true,
                hasSingleProvenance: true,
                containsCalibrations: false
            )
        }
        
        return GlucoseDataQuality(
            isContinuous: isContinuous(readings),
            hasGradualTransitions: hasGradualTransitions(readings),
            hasSingleProvenance: hasSingleProvenance(readings),
            containsCalibrations: containsCalibrations(readings)
        )
    }
    
    // MARK: - Recency Check (Hard Failure)
    
    /// Check glucose recency (throws on failure)
    /// - Parameters:
    ///   - latestTimestamp: Timestamp of most recent glucose
    ///   - at: Reference time for comparison
    ///   - maxAge: Maximum acceptable age
    /// - Throws: LoopAlgorithmError.glucoseTooOld if data is stale
    public func checkRecency(
        latestTimestamp: Date,
        at date: Date = Date(),
        maxAge: TimeInterval = DataQualityConstants.maxGlucoseAge
    ) throws {
        let age = date.timeIntervalSince(latestTimestamp)
        if age > maxAge {
            throw LoopAlgorithmError.glucoseTooOld(age: age)
        }
    }
    
    /// Check glucose recency (returns result)
    /// - Parameters:
    ///   - latestTimestamp: Timestamp of most recent glucose
    ///   - at: Reference time for comparison
    ///   - maxAge: Maximum acceptable age
    /// - Returns: true if data is recent enough
    public func isRecent(
        latestTimestamp: Date,
        at date: Date = Date(),
        maxAge: TimeInterval = DataQualityConstants.maxGlucoseAge
    ) -> Bool {
        let age = date.timeIntervalSince(latestTimestamp)
        return age <= maxAge
    }
}

// MARK: - Dose Gap Filler (GAP-060)

/// Fills gaps in dose history with scheduled basal
public struct DoseGapFiller: Sendable {
    
    public init() {}
    
    /// Basal schedule entry
    public struct BasalScheduleEntry: Sendable {
        public let startDate: Date
        public let endDate: Date
        public let rate: Double  // U/hr
        
        public init(startDate: Date, endDate: Date, rate: Double) {
            self.startDate = startDate
            self.endDate = endDate
            self.rate = rate
        }
    }
    
    /// Filled dose entry
    public struct FilledDose: Sendable {
        public let startDate: Date
        public let endDate: Date
        public let volume: Double  // Units
        public let isSynthetic: Bool
        
        public init(startDate: Date, endDate: Date, volume: Double, isSynthetic: Bool) {
            self.startDate = startDate
            self.endDate = endDate
            self.volume = volume
            self.isSynthetic = isSynthetic
        }
    }
    
    /// Source dose for gap filling
    public struct SourceDose: Sendable {
        public let startDate: Date
        public let endDate: Date
        public let volume: Double
        
        public init(startDate: Date, endDate: Date, volume: Double) {
            self.startDate = startDate
            self.endDate = endDate
            self.volume = volume
        }
    }
    
    /// Fill gaps in dose history with scheduled basal
    /// - Parameters:
    ///   - doses: Known insulin doses
    ///   - basalSchedule: Scheduled basal rates
    ///   - start: Start of range to fill
    ///   - end: End of range to fill
    /// - Returns: Doses with gaps filled by scheduled basal
    public func fillGaps(
        doses: [SourceDose],
        basalSchedule: [BasalScheduleEntry],
        start: Date,
        end: Date
    ) -> [FilledDose] {
        guard !doses.isEmpty else {
            // No doses — fill entire range with scheduled basal
            return basalSegments(from: basalSchedule, start: start, end: end)
        }
        
        var result: [FilledDose] = []
        var currentDate = start
        
        let sortedDoses = doses.sorted { $0.startDate < $1.startDate }
        
        for dose in sortedDoses {
            // Fill gap before this dose
            if dose.startDate > currentDate {
                let gapFill = basalSegments(
                    from: basalSchedule,
                    start: currentDate,
                    end: dose.startDate
                )
                result.append(contentsOf: gapFill)
            }
            
            // Add the actual dose
            result.append(FilledDose(
                startDate: dose.startDate,
                endDate: dose.endDate,
                volume: dose.volume,
                isSynthetic: false
            ))
            
            // Update current position
            currentDate = max(currentDate, dose.endDate)
        }
        
        // Fill any trailing gap
        if currentDate < end {
            let trailingFill = basalSegments(
                from: basalSchedule,
                start: currentDate,
                end: end
            )
            result.append(contentsOf: trailingFill)
        }
        
        return result
    }
    
    /// Create basal dose segments from schedule
    private func basalSegments(
        from schedule: [BasalScheduleEntry],
        start: Date,
        end: Date
    ) -> [FilledDose] {
        schedule.compactMap { entry -> FilledDose? in
            let segmentStart = max(start, entry.startDate)
            let segmentEnd = min(end, entry.endDate)
            
            guard segmentStart < segmentEnd else { return nil }
            
            let duration = segmentEnd.timeIntervalSince(segmentStart)
            let units = entry.rate * (duration / 3600)  // U/hr → U
            
            return FilledDose(
                startDate: segmentStart,
                endDate: segmentEnd,
                volume: units,
                isSynthetic: true
            )
        }
    }
    
    /// Detect gaps in dose history
    /// - Parameters:
    ///   - doses: Known insulin doses
    ///   - start: Start of expected range
    ///   - end: End of expected range
    ///   - maxGap: Maximum acceptable gap
    /// - Returns: Array of gap intervals
    public func detectGaps(
        in doses: [SourceDose],
        start: Date,
        end: Date,
        maxGap: TimeInterval = DataQualityConstants.maxDoseHistoryGap
    ) -> [(start: Date, end: Date)] {
        var gaps: [(start: Date, end: Date)] = []
        var currentDate = start
        
        let sortedDoses = doses.sorted { $0.startDate < $1.startDate }
        
        for dose in sortedDoses {
            if dose.startDate > currentDate {
                let gapDuration = dose.startDate.timeIntervalSince(currentDate)
                if gapDuration > maxGap {
                    gaps.append((start: currentDate, end: dose.startDate))
                }
            }
            currentDate = max(currentDate, dose.endDate)
        }
        
        // Check trailing gap
        if end > currentDate {
            let gapDuration = end.timeIntervalSince(currentDate)
            if gapDuration > maxGap {
                gaps.append((start: currentDate, end: end))
            }
        }
        
        return gaps
    }
}

// MARK: - Graceful Degradation Helper (GAP-061)

/// Helper for graceful degradation decisions
public struct GracefulDegradation: Sendable {
    
    public init() {}
    
    /// Degradation level for algorithm features
    public enum DegradationLevel: String, Codable, Sendable {
        /// Full functionality
        case full
        
        /// Momentum disabled, model-only predictions
        case noMomentum
        
        /// Conservative estimates (gap-filled data)
        case conservative
        
        /// Minimal functionality (basic safety only)
        case minimal
        
        /// No functionality (hard failure)
        case none
    }
    
    /// Determine degradation level based on data quality
    public func degradationLevel(
        glucoseQuality: GlucoseDataQuality,
        hasGlucose: Bool,
        isGlucoseRecent: Bool,
        hasDoseGaps: Bool
    ) -> DegradationLevel {
        // Hard failures
        guard hasGlucose else { return .none }
        guard isGlucoseRecent else { return .none }
        
        // Soft degradations
        if !glucoseQuality.isValidForMomentum && hasDoseGaps {
            return .minimal
        }
        
        if !glucoseQuality.isValidForMomentum {
            return .noMomentum
        }
        
        if hasDoseGaps {
            return .conservative
        }
        
        return .full
    }
    
    /// Description of current degradation state
    public func degradationDescription(_ level: DegradationLevel) -> String {
        switch level {
        case .full:
            return "Full algorithm functionality"
        case .noMomentum:
            return "Momentum disabled due to CGM data quality"
        case .conservative:
            return "Using conservative estimates due to dose history gaps"
        case .minimal:
            return "Minimal functionality due to data quality issues"
        case .none:
            return "Algorithm cannot run due to missing or stale data"
        }
    }
}
