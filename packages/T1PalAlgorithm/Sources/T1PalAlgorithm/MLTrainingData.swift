// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLTrainingData.swift
// T1PalAlgorithm
//
// ML training data schema for collecting algorithm inputs and outcomes.
// Used for on-device fine-tuning and personalized model training.
//
// Trace: ALG-SHADOW-020

import Foundation
import T1PalCore

// MARK: - MLTrainingDataRow

/// A single row of training data capturing algorithm inputs and actual outcomes.
/// Used to train personalized ML models for dosing recommendations.
///
/// Schema designed for:
/// - On-device collection (privacy-preserving)
/// - CoreML model training (CreateML compatible)
/// - CSV/Parquet export for research
public struct MLTrainingDataRow: Codable, Sendable, Identifiable {
    public let id: UUID
    
    // MARK: - Timestamp
    
    /// When this data point was captured
    public let timestamp: Date
    
    // MARK: - Glucose State (Inputs)
    
    /// Current glucose value (mg/dL)
    public let glucose: Double
    
    /// Glucose delta over last 5 minutes (mg/dL)
    public let glucoseDelta5min: Double?
    
    /// Glucose delta over last 15 minutes (mg/dL)
    public let glucoseDelta15min: Double?
    
    /// Glucose trend (encoded as Int: -3 to +3)
    public let trendCode: Int
    
    /// Recent glucose values for pattern detection (last 6 readings = 30 min)
    public let recentGlucose: [Double]
    
    // MARK: - Metabolic State (Inputs)
    
    /// Insulin on board (U)
    public let iob: Double
    
    /// Carbs on board (g)
    public let cob: Double
    
    /// Hours since last bolus
    public let hoursSinceLastBolus: Double?
    
    /// Hours since last carb entry
    public let hoursSinceLastCarbs: Double?
    
    // MARK: - Profile (Inputs)
    
    /// Current basal rate (U/hr)
    public let basalRate: Double
    
    /// Current insulin sensitivity factor (mg/dL per U)
    public let isf: Double
    
    /// Current carb ratio (g per U)
    public let carbRatio: Double
    
    /// Target glucose (mg/dL)
    public let targetGlucose: Double
    
    // MARK: - Context (Inputs)
    
    /// Time of day (0-23)
    public let hourOfDay: Int
    
    /// Day of week (1-7, Sunday = 1)
    public let dayOfWeek: Int
    
    /// Minutes since midnight (for finer granularity)
    public let minutesSinceMidnight: Int
    
    /// Is weekend (Saturday or Sunday)
    public let isWeekend: Bool
    
    // MARK: - Algorithm Recommendation (What algorithm suggested)
    
    /// Algorithm ID that made the recommendation
    public let algorithmId: String
    
    /// Recommended temp basal rate (U/hr), nil if no change
    public let recommendedTempBasal: Double?
    
    /// Recommended temp basal duration (seconds)
    public let recommendedTempBasalDuration: TimeInterval?
    
    /// Recommended bolus/SMB (U)
    public let recommendedBolus: Double?
    
    // MARK: - Enacted Action (What actually happened)
    
    /// Actual temp basal that was enacted (U/hr)
    public let enactedTempBasal: Double?
    
    /// Actual bolus that was delivered (U)
    public let enactedBolus: Double?
    
    /// Whether the recommendation was enacted
    public let wasEnacted: Bool
    
    // MARK: - Outcome (What happened afterward)
    
    /// Glucose 30 minutes later (mg/dL)
    public let glucose30min: Double?
    
    /// Glucose 60 minutes later (mg/dL)
    public let glucose60min: Double?
    
    /// Glucose 90 minutes later (mg/dL)
    public let glucose90min: Double?
    
    /// Glucose 120 minutes later (mg/dL)
    public let glucose120min: Double?
    
    /// Whether glucose remained in range (70-180) for the next 2 hours
    public let remainedInRange: Bool?
    
    /// Time in range percentage over next 2 hours (0-1)
    public let timeInRange2hr: Double?
    
    /// Minimum glucose over next 2 hours
    public let minGlucose2hr: Double?
    
    /// Maximum glucose over next 2 hours
    public let maxGlucose2hr: Double?
    
    // MARK: - Quality Flags
    
    /// Whether this row has complete outcome data
    public var hasCompleteOutcomes: Bool {
        glucose30min != nil && glucose60min != nil && glucose90min != nil
    }
    
    /// Whether this row is suitable for training (complete data, no anomalies)
    public var isTrainingReady: Bool {
        hasCompleteOutcomes && wasEnacted && !hasDataGaps
    }
    
    /// Whether there were data gaps during collection
    public let hasDataGaps: Bool
    
    /// Data quality score (0-1, higher is better)
    public let qualityScore: Double
    
    // MARK: - Initialization
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        glucose: Double,
        glucoseDelta5min: Double? = nil,
        glucoseDelta15min: Double? = nil,
        trendCode: Int = 0,
        recentGlucose: [Double] = [],
        iob: Double,
        cob: Double,
        hoursSinceLastBolus: Double? = nil,
        hoursSinceLastCarbs: Double? = nil,
        basalRate: Double,
        isf: Double,
        carbRatio: Double,
        targetGlucose: Double,
        hourOfDay: Int,
        dayOfWeek: Int,
        minutesSinceMidnight: Int,
        isWeekend: Bool,
        algorithmId: String,
        recommendedTempBasal: Double? = nil,
        recommendedTempBasalDuration: TimeInterval? = nil,
        recommendedBolus: Double? = nil,
        enactedTempBasal: Double? = nil,
        enactedBolus: Double? = nil,
        wasEnacted: Bool = false,
        glucose30min: Double? = nil,
        glucose60min: Double? = nil,
        glucose90min: Double? = nil,
        glucose120min: Double? = nil,
        remainedInRange: Bool? = nil,
        timeInRange2hr: Double? = nil,
        minGlucose2hr: Double? = nil,
        maxGlucose2hr: Double? = nil,
        hasDataGaps: Bool = false,
        qualityScore: Double = 1.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.glucose = glucose
        self.glucoseDelta5min = glucoseDelta5min
        self.glucoseDelta15min = glucoseDelta15min
        self.trendCode = trendCode
        self.recentGlucose = recentGlucose
        self.iob = iob
        self.cob = cob
        self.hoursSinceLastBolus = hoursSinceLastBolus
        self.hoursSinceLastCarbs = hoursSinceLastCarbs
        self.basalRate = basalRate
        self.isf = isf
        self.carbRatio = carbRatio
        self.targetGlucose = targetGlucose
        self.hourOfDay = hourOfDay
        self.dayOfWeek = dayOfWeek
        self.minutesSinceMidnight = minutesSinceMidnight
        self.isWeekend = isWeekend
        self.algorithmId = algorithmId
        self.recommendedTempBasal = recommendedTempBasal
        self.recommendedTempBasalDuration = recommendedTempBasalDuration
        self.recommendedBolus = recommendedBolus
        self.enactedTempBasal = enactedTempBasal
        self.enactedBolus = enactedBolus
        self.wasEnacted = wasEnacted
        self.glucose30min = glucose30min
        self.glucose60min = glucose60min
        self.glucose90min = glucose90min
        self.glucose120min = glucose120min
        self.remainedInRange = remainedInRange
        self.timeInRange2hr = timeInRange2hr
        self.minGlucose2hr = minGlucose2hr
        self.maxGlucose2hr = maxGlucose2hr
        self.hasDataGaps = hasDataGaps
        self.qualityScore = qualityScore
    }
}

// MARK: - MLTrainingDataRow Factory

public extension MLTrainingDataRow {
    
    /// Create a training row from algorithm inputs and decision.
    /// Outcomes are initially nil and filled in later.
    static func from(
        inputs: AlgorithmInputs,
        decision: AlgorithmDecision,
        algorithmId: String,
        wasEnacted: Bool
    ) -> MLTrainingDataRow {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        
        // Calculate glucose deltas
        var delta5min: Double? = nil
        var delta15min: Double? = nil
        if inputs.glucose.count >= 2 {
            delta5min = inputs.glucose[0].glucose - inputs.glucose[1].glucose
        }
        if inputs.glucose.count >= 4 {
            delta15min = inputs.glucose[0].glucose - inputs.glucose[3].glucose
        }
        
        // Extract recent glucose values
        let recentGlucose = inputs.glucose.prefix(6).map { $0.glucose }
        
        // Encode trend
        let trendCode = inputs.glucose.first.map { encodeTrend($0.trend) } ?? 0
        
        // ALG-FIX-T5-003: Use time-aware lookups for profile values
        return MLTrainingDataRow(
            timestamp: now,
            glucose: inputs.glucose.first?.glucose ?? 0,
            glucoseDelta5min: delta5min,
            glucoseDelta15min: delta15min,
            trendCode: trendCode,
            recentGlucose: Array(recentGlucose),
            iob: inputs.insulinOnBoard,
            cob: inputs.carbsOnBoard,
            basalRate: inputs.profile.basalRates.rateAt(date: now) ?? inputs.profile.basalRates.first?.rate ?? 0,
            isf: inputs.profile.sensitivityFactors.factorAt(date: now) ?? inputs.profile.sensitivityFactors.first?.factor ?? 0,
            carbRatio: inputs.profile.carbRatios.ratioAt(date: now) ?? inputs.profile.carbRatios.first?.ratio ?? 0,
            targetGlucose: (inputs.profile.targetGlucose.low + inputs.profile.targetGlucose.high) / 2,
            hourOfDay: components.hour ?? 0,
            dayOfWeek: components.weekday ?? 1,
            minutesSinceMidnight: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            isWeekend: [1, 7].contains(components.weekday ?? 0),
            algorithmId: algorithmId,
            recommendedTempBasal: decision.suggestedTempBasal?.rate,
            recommendedTempBasalDuration: decision.suggestedTempBasal?.duration,
            recommendedBolus: decision.suggestedBolus,
            wasEnacted: wasEnacted
        )
    }
    
    /// Encode GlucoseTrend to integer code (-3 to +3)
    private static func encodeTrend(_ trend: GlucoseTrend) -> Int {
        switch trend {
        case .doubleDown: return -3
        case .singleDown: return -2
        case .fortyFiveDown: return -1
        case .flat: return 0
        case .fortyFiveUp: return 1
        case .singleUp: return 2
        case .doubleUp: return 3
        case .notComputable, .rateOutOfRange: return 0
        }
    }
    
    /// Update this row with outcome data
    func withOutcomes(
        glucose30min: Double?,
        glucose60min: Double?,
        glucose90min: Double?,
        glucose120min: Double?,
        glucoseHistory: [Double]
    ) -> MLTrainingDataRow {
        // Calculate time in range and min/max
        let inRangeReadings = glucoseHistory.filter { $0 >= 70 && $0 <= 180 }
        let timeInRange = glucoseHistory.isEmpty ? nil : Double(inRangeReadings.count) / Double(glucoseHistory.count)
        let allInRange = glucoseHistory.allSatisfy { $0 >= 70 && $0 <= 180 }
        
        return MLTrainingDataRow(
            id: self.id,
            timestamp: self.timestamp,
            glucose: self.glucose,
            glucoseDelta5min: self.glucoseDelta5min,
            glucoseDelta15min: self.glucoseDelta15min,
            trendCode: self.trendCode,
            recentGlucose: self.recentGlucose,
            iob: self.iob,
            cob: self.cob,
            hoursSinceLastBolus: self.hoursSinceLastBolus,
            hoursSinceLastCarbs: self.hoursSinceLastCarbs,
            basalRate: self.basalRate,
            isf: self.isf,
            carbRatio: self.carbRatio,
            targetGlucose: self.targetGlucose,
            hourOfDay: self.hourOfDay,
            dayOfWeek: self.dayOfWeek,
            minutesSinceMidnight: self.minutesSinceMidnight,
            isWeekend: self.isWeekend,
            algorithmId: self.algorithmId,
            recommendedTempBasal: self.recommendedTempBasal,
            recommendedTempBasalDuration: self.recommendedTempBasalDuration,
            recommendedBolus: self.recommendedBolus,
            enactedTempBasal: self.enactedTempBasal,
            enactedBolus: self.enactedBolus,
            wasEnacted: self.wasEnacted,
            glucose30min: glucose30min,
            glucose60min: glucose60min,
            glucose90min: glucose90min,
            glucose120min: glucose120min,
            remainedInRange: glucoseHistory.isEmpty ? nil : allInRange,
            timeInRange2hr: timeInRange,
            minGlucose2hr: glucoseHistory.min(),
            maxGlucose2hr: glucoseHistory.max(),
            hasDataGaps: self.hasDataGaps,
            qualityScore: self.qualityScore
        )
    }
}

// MARK: - CSV Export Support

public extension MLTrainingDataRow {
    
    /// CSV header row
    static var csvHeader: String {
        [
            "id", "timestamp", "glucose", "glucoseDelta5min", "glucoseDelta15min",
            "trendCode", "iob", "cob", "hoursSinceLastBolus", "hoursSinceLastCarbs",
            "basalRate", "isf", "carbRatio", "targetGlucose",
            "hourOfDay", "dayOfWeek", "minutesSinceMidnight", "isWeekend",
            "algorithmId", "recommendedTempBasal", "recommendedTempBasalDuration",
            "recommendedBolus", "enactedTempBasal", "enactedBolus", "wasEnacted",
            "glucose30min", "glucose60min", "glucose90min", "glucose120min",
            "remainedInRange", "timeInRange2hr", "minGlucose2hr", "maxGlucose2hr",
            "hasDataGaps", "qualityScore"
        ].joined(separator: ",")
    }
    
    /// Convert to CSV row
    var csvRow: String {
        let iso8601 = ISO8601DateFormatter()
        var parts: [String] = []
        parts.append(id.uuidString)
        parts.append(iso8601.string(from: timestamp))
        parts.append(String(glucose))
        parts.append(glucoseDelta5min.map { String($0) } ?? "")
        parts.append(glucoseDelta15min.map { String($0) } ?? "")
        parts.append(String(trendCode))
        parts.append(String(iob))
        parts.append(String(cob))
        parts.append(hoursSinceLastBolus.map { String($0) } ?? "")
        parts.append(hoursSinceLastCarbs.map { String($0) } ?? "")
        parts.append(String(basalRate))
        parts.append(String(isf))
        parts.append(String(carbRatio))
        parts.append(String(targetGlucose))
        parts.append(String(hourOfDay))
        parts.append(String(dayOfWeek))
        parts.append(String(minutesSinceMidnight))
        parts.append(String(isWeekend))
        parts.append(algorithmId)
        parts.append(recommendedTempBasal.map { String($0) } ?? "")
        parts.append(recommendedTempBasalDuration.map { String($0) } ?? "")
        parts.append(recommendedBolus.map { String($0) } ?? "")
        parts.append(enactedTempBasal.map { String($0) } ?? "")
        parts.append(enactedBolus.map { String($0) } ?? "")
        parts.append(String(wasEnacted))
        parts.append(glucose30min.map { String($0) } ?? "")
        parts.append(glucose60min.map { String($0) } ?? "")
        parts.append(glucose90min.map { String($0) } ?? "")
        parts.append(glucose120min.map { String($0) } ?? "")
        parts.append(remainedInRange.map { String($0) } ?? "")
        parts.append(timeInRange2hr.map { String($0) } ?? "")
        parts.append(minGlucose2hr.map { String($0) } ?? "")
        parts.append(maxGlucose2hr.map { String($0) } ?? "")
        parts.append(String(hasDataGaps))
        parts.append(String(qualityScore))
        return parts.joined(separator: ",")
    }
}

// MARK: - Training Dataset

/// A collection of training data rows ready for ML training.
public struct MLTrainingDataset: Codable, Sendable {
    public let rows: [MLTrainingDataRow]
    public let createdAt: Date
    public let algorithmId: String
    public let version: String
    
    /// Number of training-ready rows
    public var trainingReadyCount: Int {
        rows.filter(\.isTrainingReady).count
    }
    
    /// Filter to only training-ready rows
    public var trainingReadyRows: [MLTrainingDataRow] {
        rows.filter(\.isTrainingReady)
    }
    
    public init(rows: [MLTrainingDataRow], algorithmId: String, version: String = "1.0") {
        self.rows = rows
        self.createdAt = Date()
        self.algorithmId = algorithmId
        self.version = version
    }
    
    /// Export to CSV
    public func toCSV() -> String {
        var csv = MLTrainingDataRow.csvHeader + "\n"
        for row in rows {
            csv += row.csvRow + "\n"
        }
        return csv
    }
    
    /// Export training-ready rows only to CSV
    public func toTrainingCSV() -> String {
        var csv = MLTrainingDataRow.csvHeader + "\n"
        for row in trainingReadyRows {
            csv += row.csvRow + "\n"
        }
        return csv
    }
}
