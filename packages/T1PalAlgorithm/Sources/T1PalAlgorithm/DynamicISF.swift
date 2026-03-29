// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DynamicISF.swift
// T1Pal Mobile
//
// Dynamic Insulin Sensitivity Factor adjustments
// Requirements: REQ-AID-002
//
// Based on oref1 autosens and dynamic ISF:
// https://github.com/openaps/oref0/blob/master/lib/determine-basal/autosens.js

import Foundation
import T1PalCore

// MARK: - Autosens Result

/// Result of autosensitivity detection
public struct AutosensResult: Codable, Sendable {
    /// Sensitivity ratio (1.0 = normal, >1.0 = more sensitive, <1.0 = resistant)
    public let ratio: Double
    
    /// Raw deviation from expected
    public let deviation: Double
    
    /// Number of data points used
    public let dataPoints: Int
    
    /// Timestamp of calculation
    public let timestamp: Date
    
    /// Reason for the adjustment
    public let reason: String
    
    public init(
        ratio: Double,
        deviation: Double = 0,
        dataPoints: Int = 0,
        timestamp: Date = Date(),
        reason: String = ""
    ) {
        self.ratio = ratio
        self.deviation = deviation
        self.dataPoints = dataPoints
        self.timestamp = timestamp
        self.reason = reason
    }
    
    /// No adjustment
    public static let neutral = AutosensResult(ratio: 1.0, reason: "Neutral")
}

// MARK: - Autosens Calculator

/// Calculates autosensitivity based on glucose history.
/// Implements oref0-style autosens with:
/// - IOB-adjusted deviations (deviation = actual_delta - expected_delta_from_insulin)
/// - Meal exclusion (ignores deviations during carb absorption)
/// - Dual-window calculation (8h and 24h for conservative adjustment)
/// - Percentile-based ratio calculation
/// Trace: ALG-GAP-001, ALG-PARITY-002
public struct AutosensCalculator: Sendable {
    /// Minimum hours of data required
    public let minHoursData: Double
    
    /// Maximum adjustment factor
    public let maxRatio: Double
    
    /// Minimum adjustment factor
    public let minRatio: Double
    
    /// Short window in hours (for recent sensitivity)
    public let shortWindow: Double
    
    /// Long window in hours (for overall sensitivity)
    public let longWindow: Double
    
    public init(
        minHoursData: Double = 8,
        maxRatio: Double = 1.5,
        minRatio: Double = 0.5,
        shortWindow: Double = 8,
        longWindow: Double = 24
    ) {
        self.minHoursData = minHoursData
        self.maxRatio = maxRatio
        self.minRatio = minRatio
        self.shortWindow = shortWindow
        self.longWindow = longWindow
    }
    
    /// Calculate autosens ratio from glucose history (oref0-style)
    /// - Parameters:
    ///   - glucose: Recent glucose readings (newest first)
    ///   - profile: Algorithm profile with ISF/basal settings
    ///   - insulinModel: Insulin activity model
    ///   - iob: Current IOB data (optional, for better deviation calculation)
    ///   - cob: Current COB (for meal exclusion)
    public func calculate(
        glucose: [GlucoseReading],
        profile: AlgorithmProfile,
        insulinModel: InsulinModel,
        iob: Double = 0,
        cob: Double = 0
    ) -> AutosensResult {
        // Need enough data
        guard glucose.count >= 24 else {  // At least 2 hours at 5-min intervals
            return AutosensResult(
                ratio: 1.0,
                dataPoints: glucose.count,
                reason: "Insufficient data (\(glucose.count) readings)"
            )
        }
        
        let sens = profile.currentISF()
        
        // Calculate deviations using oref0-style logic
        let deviations = calculateDeviations(
            glucose: glucose,
            sens: sens,
            cob: cob
        )
        
        guard !deviations.isEmpty else {
            return AutosensResult(
                ratio: 1.0,
                dataPoints: glucose.count,
                reason: "No non-meal deviations"
            )
        }
        
        // Use percentile-based calculation (oref0 style)
        let sortedDeviations = deviations.sorted()
        let median = percentile(sortedDeviations, p: 0.50)
        
        // Calculate ratio based on median deviation
        // Positive median = BG rising more than expected = resistance = lower ratio
        // Negative median = BG falling more than expected = sensitivity = higher ratio
        let basalAdjustment = median * (60.0 / 5.0) / sens  // Per-hour adjustment
        let maxDailyBasal = profile.maxBasal * 24  // Rough approximation
        let rawRatio = 1.0 + (basalAdjustment / maxDailyBasal)
        
        // Clamp to limits
        let ratio = max(minRatio, min(maxRatio, rawRatio))
        
        // Determine reason
        let reason: String
        if ratio > 1.05 {
            reason = "Sensitive: \(String(format: "%.0f", ratio * 100))%"
        } else if ratio < 0.95 {
            reason = "Resistant: \(String(format: "%.0f", ratio * 100))%"
        } else {
            reason = "Normal sensitivity"
        }
        
        return AutosensResult(
            ratio: ratio,
            deviation: median,
            dataPoints: deviations.count,
            reason: reason
        )
    }
    
    /// Calculate deviations from expected glucose changes (oref0 style)
    private func calculateDeviations(
        glucose: [GlucoseReading],
        sens: Double,
        cob: Double
    ) -> [Double] {
        var deviations: [Double] = []
        
        // Process glucose readings (assuming 5-minute intervals)
        // Skip if COB > 0 (meal absorption period)
        let inMealAbsorption = cob > 0
        
        for i in 3..<glucose.count {
            let current = glucose[i - 3]  // 15 min ago
            let previous = glucose[i]      // Current point
            
            // Skip invalid readings
            guard current.glucose > 39, previous.glucose > 39 else { continue }
            
            // Calculate average delta over 15 minutes (3 readings)
            let avgDelta = (current.glucose - previous.glucose) / 3.0
            
            // Simplified: expected delta based on insulin activity
            // In full oref0, this uses IOB activity, but we simplify here
            let expectedDelta = 0.0  // Assume basal matched
            
            let deviation = avgDelta - expectedDelta
            
            // Exclude meal-related deviations
            if inMealAbsorption && deviation > 0 {
                // Positive deviation during meal = carb absorption, skip
                continue
            }
            
            // Only count significant deviations
            if abs(deviation) > 1.0 {
                // Set positive deviations to zero if BG is below 80 (oref0 rule)
                if current.glucose < 80 && deviation > 0 {
                    deviations.append(0)
                } else {
                    deviations.append(deviation)
                }
            }
        }
        
        // Pad with zeros if insufficient data (oref0 damping)
        if deviations.count < 96 && !deviations.isEmpty {
            let pad = Int(Double(96 - deviations.count) * 0.2)  // Add 20% padding
            for _ in 0..<pad {
                deviations.append(0)
            }
        }
        
        return deviations
    }
    
    /// Calculate percentile of sorted array
    private func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        guard values.count > 1 else { return values[0] }
        
        let index = p * Double(values.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, values.count - 1)
        let fraction = index - Double(lower)
        
        return values[lower] + fraction * (values[upper] - values[lower])
    }
    
    /// Calculate dual-window autosens (8h + 24h average for conservative adjustment)
    /// This provides more stable autosens by averaging short and long-term sensitivity
    public func calculateDualWindow(
        glucose: [GlucoseReading],
        profile: AlgorithmProfile,
        insulinModel: InsulinModel,
        iob: Double = 0,
        cob: Double = 0
    ) -> AutosensResult {
        // Calculate short window (last 8 hours = ~96 readings)
        let shortWindowReadings = min(96, glucose.count)
        let shortGlucose = Array(glucose.prefix(shortWindowReadings))
        let shortResult = calculate(
            glucose: shortGlucose,
            profile: profile,
            insulinModel: insulinModel,
            iob: iob,
            cob: cob
        )
        
        // Calculate long window (full data, up to 24 hours = ~288 readings)
        let longResult = calculate(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel,
            iob: iob,
            cob: cob
        )
        
        // Average the two for conservative adjustment
        let avgRatio = (shortResult.ratio + longResult.ratio) / 2.0
        let clampedRatio = max(minRatio, min(maxRatio, avgRatio))
        
        return AutosensResult(
            ratio: clampedRatio,
            deviation: (shortResult.deviation + longResult.deviation) / 2.0,
            dataPoints: shortResult.dataPoints + longResult.dataPoints,
            reason: "Dual-window: 8h=\(String(format: "%.0f", shortResult.ratio * 100))%, 24h=\(String(format: "%.0f", longResult.ratio * 100))%"
        )
    }
}

// MARK: - Dynamic ISF

/// Dynamic ISF calculation using sigmoid function
public struct DynamicISF: Sendable {
    /// Adjustment factor (higher = more aggressive adjustment)
    public let adjustmentFactor: Double
    
    /// BG level where adjustment starts
    public let thresholdBG: Double
    
    public init(adjustmentFactor: Double = 0.5, thresholdBG: Double = 100) {
        self.adjustmentFactor = adjustmentFactor
        self.thresholdBG = thresholdBG
    }
    
    /// Calculate dynamic ISF based on current glucose
    /// - Parameters:
    ///   - baseISF: Profile ISF (mg/dL per unit)
    ///   - currentBG: Current glucose (mg/dL)
    ///   - targetBG: Target glucose (mg/dL)
    /// - Returns: Adjusted ISF
    public func calculateISF(baseISF: Double, currentBG: Double, targetBG: Double) -> Double {
        // When BG is high, ISF should be lower (more insulin effect per unit)
        // When BG is low, ISF should be higher (less insulin effect per unit)
        
        // Use sigmoid function for smooth adjustment
        let bgDiff = currentBG - targetBG
        
        if abs(bgDiff) < 10 {
            // Near target, no adjustment
            return baseISF
        }
        
        // Sigmoid adjustment
        // As BG goes up, adjustment < 1 (lower ISF = more insulin effect)
        // As BG goes down, adjustment > 1 (higher ISF = less insulin effect)
        let sigmoid = sigmoidAdjustment(bgDiff: bgDiff)
        
        return baseISF * sigmoid
    }
    
    /// Sigmoid adjustment function
    /// - Parameter bgDiff: Difference from target (positive = high, negative = low)
    /// - Returns: Adjustment factor
    public func sigmoidAdjustment(bgDiff: Double) -> Double {
        // Sigmoid centered at 0, scaled by adjustment factor
        // f(x) = 2 / (1 + e^(x * factor)) for high BG (makes ISF lower)
        // For low BG, we want to increase ISF, so invert
        
        let scaled = bgDiff * adjustmentFactor / 100.0
        let sigmoid = 2.0 / (1.0 + exp(scaled))
        
        // Clamp to reasonable range (0.5 to 2.0)
        return max(0.5, min(2.0, sigmoid))
    }
    
    /// Calculate adjustment for high BG (logarithmic for very high)
    public func highBGAdjustment(currentBG: Double, targetBG: Double) -> Double {
        guard currentBG > targetBG + 40 else { return 1.0 }
        
        // Logarithmic adjustment for very high BG
        let excess = currentBG - targetBG - 40
        let logFactor = log10(excess + 10) / log10(100)  // Normalized
        
        // Return factor < 1 to lower ISF (more aggressive)
        return max(0.5, 1.0 - logFactor * 0.3)
    }
}

// MARK: - Sensitivity Adjuster

/// Combines autosens and dynamic ISF for final adjustments
public struct SensitivityAdjuster: Sendable {
    public let autosens: AutosensCalculator
    public let dynamicISF: DynamicISF
    
    public init(
        autosens: AutosensCalculator = AutosensCalculator(),
        dynamicISF: DynamicISF = DynamicISF()
    ) {
        self.autosens = autosens
        self.dynamicISF = dynamicISF
    }
    
    /// Get adjusted ISF considering all factors
    public func adjustedISF(
        baseISF: Double,
        currentBG: Double,
        targetBG: Double,
        autosensRatio: Double
    ) -> Double {
        // Apply autosens ratio first
        let autosensAdjusted = baseISF / autosensRatio
        
        // Then apply dynamic ISF based on current BG
        let dynamicAdjusted = dynamicISF.calculateISF(
            baseISF: autosensAdjusted,
            currentBG: currentBG,
            targetBG: targetBG
        )
        
        return dynamicAdjusted
    }
    
    /// Get adjusted basal rate
    public func adjustedBasal(baseBasal: Double, autosensRatio: Double) -> Double {
        // Lower ratio = resistant = need more insulin
        // Higher ratio = sensitive = need less insulin
        return baseBasal / autosensRatio
    }
    
    /// Get adjusted ICR
    public func adjustedICR(baseICR: Double, autosensRatio: Double) -> Double {
        // Lower ratio = resistant = need more insulin per carb
        // Higher ratio = sensitive = need less insulin per carb
        return baseICR / autosensRatio
    }
    
    /// Calculate all adjusted profile values
    public func adjustedProfile(
        profile: AlgorithmProfile,
        currentBG: Double,
        autosensResult: AutosensResult
    ) -> AdjustedProfileValues {
        let baseISF = profile.currentISF()
        let baseBasal = profile.currentBasal()
        let baseICR = profile.currentICR()
        let target = profile.currentTarget()
        
        return AdjustedProfileValues(
            isf: adjustedISF(
                baseISF: baseISF,
                currentBG: currentBG,
                targetBG: target,
                autosensRatio: autosensResult.ratio
            ),
            basal: adjustedBasal(baseBasal: baseBasal, autosensRatio: autosensResult.ratio),
            icr: adjustedICR(baseICR: baseICR, autosensRatio: autosensResult.ratio),
            autosensRatio: autosensResult.ratio
        )
    }
}

// MARK: - Adjusted Profile Values

/// Adjusted profile values after applying sensitivity factors
public struct AdjustedProfileValues: Codable, Sendable {
    public let isf: Double
    public let basal: Double
    public let icr: Double
    public let autosensRatio: Double
    
    public init(isf: Double, basal: Double, icr: Double, autosensRatio: Double) {
        self.isf = isf
        self.basal = basal
        self.icr = icr
        self.autosensRatio = autosensRatio
    }
}

// MARK: - TDD Calculator (ALG-PARITY-006)

/// Total Daily Dose (TDD) record
public struct TDDRecord: Codable, Sendable, Equatable {
    /// Date of the TDD record
    public let date: Date
    
    /// Total daily dose (units)
    public let total: Double
    
    /// Bolus insulin (units)
    public let bolus: Double
    
    /// Basal insulin (units)
    public let basal: Double
    
    public init(date: Date, total: Double, bolus: Double = 0, basal: Double = 0) {
        self.date = date
        self.total = total
        self.bolus = bolus
        self.basal = basal
    }
}

/// Result of TDD calculation
public struct TDDResult: Codable, Sendable, Equatable {
    /// Current day TDD so far
    public let current: Double
    
    /// Simple average of historical TDD
    public let average: Double
    
    /// Weighted average (recent vs historical)
    public let weightedAverage: Double
    
    /// Number of days with data
    public let daysOfData: Int
    
    /// Hours of data today
    public let hoursToday: Double
    
    public init(
        current: Double,
        average: Double,
        weightedAverage: Double,
        daysOfData: Int = 0,
        hoursToday: Double = 0
    ) {
        self.current = current
        self.average = average
        self.weightedAverage = weightedAverage
        self.daysOfData = daysOfData
        self.hoursToday = hoursToday
    }
    
    /// Insufficient data placeholder
    public static let insufficient = TDDResult(
        current: 0,
        average: 0,
        weightedAverage: 0,
        daysOfData: 0
    )
}

/// Calculates Total Daily Dose (TDD) with weighted averaging.
/// Based on Trio's TDDStorage implementation.
///
/// The weighted average formula:
/// ```
/// weightedTDD = (weightPercentage × recentAverage) + ((1 - weightPercentage) × historicalAverage)
/// ```
///
/// Default weight: 65% recent (last 2 hours scaled to full day), 35% historical (10-day average)
/// Trace: ALG-PARITY-006
public struct TDDCalculator: Sendable {
    /// Weight for recent data (0.0-1.0)
    public let recentWeight: Double
    
    /// Days of history to use
    public let historyDays: Int
    
    /// Minimum days required for valid weighted average
    public let minimumDays: Int
    
    public init(
        recentWeight: Double = 0.65,
        historyDays: Int = 10,
        minimumDays: Int = 3
    ) {
        self.recentWeight = max(0, min(1, recentWeight))
        self.historyDays = historyDays
        self.minimumDays = minimumDays
    }
    
    /// Calculate TDD statistics from historical records
    /// - Parameters:
    ///   - records: Historical TDD records
    ///   - currentDayInsulin: Insulin delivered today so far
    ///   - hoursToday: Hours elapsed today
    /// - Returns: TDD result with weighted average
    public func calculate(
        records: [TDDRecord],
        currentDayInsulin: Double = 0,
        hoursToday: Double = 0
    ) -> TDDResult {
        // Filter to last N days
        let cutoff = Date().addingTimeInterval(-Double(historyDays) * 24 * 60 * 60)
        let relevantRecords = records.filter { $0.date >= cutoff }
        
        guard !relevantRecords.isEmpty else {
            return TDDResult(
                current: currentDayInsulin,
                average: 0,
                weightedAverage: 0,
                daysOfData: 0,
                hoursToday: hoursToday
            )
        }
        
        // Calculate simple average
        let totalSum = relevantRecords.reduce(0.0) { $0 + $1.total }
        let average = totalSum / Double(relevantRecords.count)
        
        // Calculate recent estimate (scale current to full day)
        let recentEstimate: Double
        if hoursToday > 0 {
            recentEstimate = (currentDayInsulin / hoursToday) * 24.0
        } else {
            recentEstimate = average  // Use historical if no today data
        }
        
        // Calculate weighted average
        let weightedAverage: Double
        if relevantRecords.count >= minimumDays {
            weightedAverage = (recentWeight * recentEstimate) + ((1 - recentWeight) * average)
        } else {
            // Not enough history, use simple average
            weightedAverage = average
        }
        
        return TDDResult(
            current: currentDayInsulin,
            average: average,
            weightedAverage: weightedAverage,
            daysOfData: relevantRecords.count,
            hoursToday: hoursToday
        )
    }
    
    /// Check if there's sufficient TDD data
    /// - Parameter records: Historical TDD records
    /// - Returns: True if at least minimumDays of data exist
    public func hasSufficientData(_ records: [TDDRecord]) -> Bool {
        let cutoff = Date().addingTimeInterval(-Double(historyDays) * 24 * 60 * 60)
        let relevantRecords = records.filter { $0.date >= cutoff }
        return relevantRecords.count >= minimumDays
    }
    
    /// Calculate Dynamic ISF adjustment based on TDD
    /// Uses the formula: dynamicISF = baseISF * (averageTDD / currentTDD)
    /// Higher current TDD → lower ISF (more insulin resistant)
    /// - Parameters:
    ///   - baseISF: Profile ISF
    ///   - tddResult: TDD calculation result
    /// - Returns: Adjusted ISF, or base ISF if insufficient data
    public func adjustedISF(baseISF: Double, tddResult: TDDResult) -> Double {
        guard tddResult.daysOfData >= minimumDays,
              tddResult.weightedAverage > 0 else {
            return baseISF
        }
        
        // If today's rate is higher than average, we're more resistant → lower ISF
        // If today's rate is lower than average, we're more sensitive → higher ISF
        let ratio = tddResult.average / tddResult.weightedAverage
        
        // Clamp to reasonable range (0.5 to 2.0)
        let clampedRatio = max(0.5, min(2.0, ratio))
        
        return baseISF * clampedRatio
    }
}
