// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MealPatternAgent.swift
// T1PalAlgorithm
//
// Meal pattern detection, carb estimation, and timing optimization
// ALG-EFF-050..054: Meal timing, carb estimation, pre-bolus, CR/ISF, alerts
//
// Trace: PRD-028 (ML-Enhanced Dosing)

import Foundation

// MARK: - ALG-EFF-050: Meal Timing Pattern Detection

/// Represents a detected meal pattern
public struct MealPattern: Sendable, Codable, Equatable {
    /// Type of meal
    public let mealType: MealType
    
    /// Typical time of day (hours since midnight)
    public let typicalHour: Double
    
    /// Standard deviation in timing (hours)
    public let timingVariability: Double
    
    /// Days this pattern occurs (empty = every day)
    public let daysOfWeek: Set<Int> // 1=Sunday, 7=Saturday
    
    /// Number of occurrences detected
    public let occurrences: Int
    
    /// Confidence in this pattern (0.0-1.0)
    public let confidence: Double
    
    public init(
        mealType: MealType,
        typicalHour: Double,
        timingVariability: Double,
        daysOfWeek: Set<Int> = [],
        occurrences: Int,
        confidence: Double
    ) {
        self.mealType = mealType
        self.typicalHour = typicalHour
        self.timingVariability = timingVariability
        self.daysOfWeek = daysOfWeek
        self.occurrences = occurrences
        self.confidence = confidence
    }
    
    /// Formatted typical time string
    public var typicalTimeString: String {
        let hour = Int(typicalHour)
        let minute = Int((typicalHour - Double(hour)) * 60)
        let period = hour >= 12 ? "pm" : "am"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):\(String(format: "%02d", minute))\(period)"
    }
    
    /// Check if a given time matches this pattern
    public func matches(hour: Double, dayOfWeek: Int, toleranceHours: Double = 1.5) -> Bool {
        // Check day of week if specified
        if !daysOfWeek.isEmpty && !daysOfWeek.contains(dayOfWeek) {
            return false
        }
        
        // Check time within tolerance
        let diff = abs(hour - typicalHour)
        return diff <= toleranceHours || diff >= (24 - toleranceHours)
    }
}

/// Types of meals
public enum MealType: String, Sendable, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    case lateNight = "Late Night"
    
    /// Typical hour range for this meal type
    public var typicalHourRange: ClosedRange<Double> {
        switch self {
        case .breakfast: return 5.0...10.0
        case .lunch: return 11.0...14.0
        case .dinner: return 17.0...21.0
        case .snack: return 14.0...17.0
        case .lateNight: return 21.0...24.0
        }
    }
    
    /// Classify a carb entry by time of day
    public static func classify(hour: Double) -> MealType {
        if hour >= 5 && hour < 10 { return .breakfast }
        if hour >= 10 && hour < 14 { return .lunch }
        if hour >= 14 && hour < 17 { return .snack }
        if hour >= 17 && hour < 21 { return .dinner }
        return .lateNight
    }
}

/// A carb entry for analysis
public struct MealCarbEntry: Sendable {
    public let timestamp: Date
    public let carbs: Double // grams
    public let bolusTimestamp: Date? // When bolus was given (for pre-bolus analysis)
    public let bolusAmount: Double? // Units
    
    public init(
        timestamp: Date,
        carbs: Double,
        bolusTimestamp: Date? = nil,
        bolusAmount: Double? = nil
    ) {
        self.timestamp = timestamp
        self.carbs = carbs
        self.bolusTimestamp = bolusTimestamp
        self.bolusAmount = bolusAmount
    }
    
    /// Hour of day (0-24)
    public var hourOfDay: Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: timestamp)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0
    }
    
    /// Day of week (1=Sunday, 7=Saturday)
    public var dayOfWeek: Int {
        Calendar.current.component(.weekday, from: timestamp)
    }
    
    /// Pre-bolus time in minutes (negative = bolused before carbs, positive = after)
    public var preBolusMinutes: Double? {
        guard let bolusTime = bolusTimestamp else { return nil }
        return timestamp.timeIntervalSince(bolusTime) / 60.0
    }
}

/// Analyzes carb entry history to detect meal patterns
public struct MealPatternAnalyzer: Sendable {
    
    /// Configuration
    public struct Configuration: Sendable {
        /// Minimum entries to detect a pattern
        public let minimumEntries: Int
        
        /// Minimum confidence to report
        public let minimumConfidence: Double
        
        /// Time window for clustering meals (hours)
        public let clusteringWindow: Double
        
        public init(
            minimumEntries: Int = 5,
            minimumConfidence: Double = 0.5,
            clusteringWindow: Double = 2.0
        ) {
            self.minimumEntries = minimumEntries
            self.minimumConfidence = minimumConfidence
            self.clusteringWindow = clusteringWindow
        }
        
        public static let `default` = Configuration()
    }
    
    public let configuration: Configuration
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    /// Analyze carb entries to detect meal patterns
    public func analyzePatterns(entries: [MealCarbEntry]) -> [MealPattern] {
        // Group entries by meal type based on time
        var mealGroups: [MealType: [MealCarbEntry]] = [:]
        
        for entry in entries {
            // Only consider significant carb entries (>= 10g)
            guard entry.carbs >= 10 else { continue }
            
            let mealType = MealType.classify(hour: entry.hourOfDay)
            mealGroups[mealType, default: []].append(entry)
        }
        
        // Analyze each meal type
        var patterns: [MealPattern] = []
        
        for (mealType, mealEntries) in mealGroups {
            guard mealEntries.count >= configuration.minimumEntries else { continue }
            
            if let pattern = analyzeGroup(entries: mealEntries, mealType: mealType) {
                if pattern.confidence >= configuration.minimumConfidence {
                    patterns.append(pattern)
                }
            }
        }
        
        return patterns.sorted { $0.typicalHour < $1.typicalHour }
    }
    
    private func analyzeGroup(entries: [MealCarbEntry], mealType: MealType) -> MealPattern? {
        guard !entries.isEmpty else { return nil }
        
        let hours = entries.map { $0.hourOfDay }
        let avgHour = circularMean(hours, period: 24)
        let stdDev = standardDeviation(hours)
        
        // Check for day-of-week patterns
        var dayFrequency: [Int: Int] = [:]
        for entry in entries {
            dayFrequency[entry.dayOfWeek, default: 0] += 1
        }
        
        // If some days have significantly more entries, this is a day-specific pattern
        let avgDayFreq = Double(entries.count) / 7.0
        let specificDays = dayFrequency.filter { Double($0.value) >= avgDayFreq * 1.5 }
            .map { $0.key }
        
        // Calculate confidence
        let sampleScore = min(1.0, Double(entries.count) / 14.0)
        let consistencyScore = 1.0 - min(1.0, stdDev / 2.0)
        let confidence = sampleScore * 0.5 + consistencyScore * 0.5
        
        return MealPattern(
            mealType: mealType,
            typicalHour: avgHour,
            timingVariability: stdDev,
            daysOfWeek: Set(specificDays),
            occurrences: entries.count,
            confidence: confidence
        )
    }
    
    private func circularMean(_ values: [Double], period: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let angles = values.map { $0 * 2 * .pi / period }
        let sinSum = angles.map { sin($0) }.reduce(0, +)
        let cosSum = angles.map { cos($0) }.reduce(0, +)
        var meanAngle = atan2(sinSum, cosSum)
        if meanAngle < 0 { meanAngle += 2 * .pi }
        return meanAngle * period / (2 * .pi)
    }
    
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - ALG-EFF-051: Typical Carb Estimation

/// Typical carb amounts for a meal type
public struct MealCarbEstimate: Sendable, Codable, Equatable {
    /// Meal type
    public let mealType: MealType
    
    /// Average carbs for this meal
    public let averageCarbs: Double
    
    /// Standard deviation
    public let carbVariability: Double
    
    /// Minimum observed
    public let minCarbs: Double
    
    /// Maximum observed
    public let maxCarbs: Double
    
    /// Number of samples
    public let sampleCount: Int
    
    /// Confidence
    public let confidence: Double
    
    public init(
        mealType: MealType,
        averageCarbs: Double,
        carbVariability: Double,
        minCarbs: Double,
        maxCarbs: Double,
        sampleCount: Int,
        confidence: Double
    ) {
        self.mealType = mealType
        self.averageCarbs = averageCarbs
        self.carbVariability = carbVariability
        self.minCarbs = minCarbs
        self.maxCarbs = maxCarbs
        self.sampleCount = sampleCount
        self.confidence = confidence
    }
    
    /// Suggested carb range for entry UI
    public var suggestedRange: ClosedRange<Double> {
        let low = max(0, averageCarbs - carbVariability)
        let high = averageCarbs + carbVariability
        return low...high
    }
}

/// Estimates typical carb amounts from history
public struct MealCarbEstimator: Sendable {
    
    public init() {}
    
    /// Analyze carb entries to estimate typical amounts per meal
    public func estimateCarbs(entries: [MealCarbEntry]) -> [MealCarbEstimate] {
        var mealGroups: [MealType: [Double]] = [:]
        
        for entry in entries {
            guard entry.carbs >= 5 else { continue } // Minimum threshold
            let mealType = MealType.classify(hour: entry.hourOfDay)
            mealGroups[mealType, default: []].append(entry.carbs)
        }
        
        var estimates: [MealCarbEstimate] = []
        
        for (mealType, carbs) in mealGroups {
            guard carbs.count >= 3 else { continue }
            
            let avg = carbs.reduce(0, +) / Double(carbs.count)
            let stdDev = standardDeviation(carbs)
            let minC = carbs.min() ?? 0
            let maxC = carbs.max() ?? 0
            
            let confidence = min(1.0, Double(carbs.count) / 14.0)
            
            estimates.append(MealCarbEstimate(
                mealType: mealType,
                averageCarbs: avg,
                carbVariability: stdDev,
                minCarbs: minC,
                maxCarbs: maxC,
                sampleCount: carbs.count,
                confidence: confidence
            ))
        }
        
        return estimates.sorted { $0.mealType.typicalHourRange.lowerBound < $1.mealType.typicalHourRange.lowerBound }
    }
    
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - ALG-EFF-052: Pre-Bolus Timing Analysis

/// Analysis of pre-bolus timing habits
public struct PreBolusAnalysis: Sendable, Codable, Equatable {
    /// Meal type
    public let mealType: MealType
    
    /// Average pre-bolus time (minutes before carbs)
    public let averagePreBolusMinutes: Double
    
    /// Variability
    public let preBolusVariability: Double
    
    /// Percentage of meals with adequate pre-bolus (>= 10 min)
    public let adequatePreBolusRate: Double
    
    /// Suggested improvement
    public let suggestedPreBolusMinutes: Double
    
    /// Sample count
    public let sampleCount: Int
    
    public init(
        mealType: MealType,
        averagePreBolusMinutes: Double,
        preBolusVariability: Double,
        adequatePreBolusRate: Double,
        suggestedPreBolusMinutes: Double,
        sampleCount: Int
    ) {
        self.mealType = mealType
        self.averagePreBolusMinutes = averagePreBolusMinutes
        self.preBolusVariability = preBolusVariability
        self.adequatePreBolusRate = adequatePreBolusRate
        self.suggestedPreBolusMinutes = suggestedPreBolusMinutes
        self.sampleCount = sampleCount
    }
    
    /// Recommendation text
    public var recommendation: String {
        if averagePreBolusMinutes >= 10 {
            return "Good pre-bolus timing! Keep it up."
        } else if averagePreBolusMinutes >= 5 {
            return "Try bolusing \(Int(suggestedPreBolusMinutes - averagePreBolusMinutes)) minutes earlier for better post-meal control."
        } else if averagePreBolusMinutes >= 0 {
            return "Consider pre-bolusing 10-15 minutes before meals to reduce post-meal spikes."
        } else {
            return "You often bolus after eating. Try bolusing before or at meal start."
        }
    }
    
    /// Quality rating
    public var qualityRating: PreBolusQuality {
        if averagePreBolusMinutes >= 15 { return .excellent }
        if averagePreBolusMinutes >= 10 { return .good }
        if averagePreBolusMinutes >= 5 { return .fair }
        if averagePreBolusMinutes >= 0 { return .needsImprovement }
        return .poor
    }
}

/// Pre-bolus quality rating
public enum PreBolusQuality: String, Sendable, Codable, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case needsImprovement = "Needs Improvement"
    case poor = "Poor"
    
    public var icon: String {
        switch self {
        case .excellent: return "⭐️"
        case .good: return "✅"
        case .fair: return "🔶"
        case .needsImprovement: return "⚠️"
        case .poor: return "❌"
        }
    }
}

/// Analyzes pre-bolus timing habits
public struct PreBolusAnalyzer: Sendable {
    
    /// Minimum pre-bolus time considered adequate (minutes)
    public let adequateThreshold: Double
    
    /// Suggested pre-bolus time based on insulin type (minutes)
    public let suggestedPreBolus: Double
    
    public init(adequateThreshold: Double = 10, suggestedPreBolus: Double = 15) {
        self.adequateThreshold = adequateThreshold
        self.suggestedPreBolus = suggestedPreBolus
    }
    
    /// Analyze pre-bolus timing from carb entries with bolus data
    public func analyze(entries: [MealCarbEntry]) -> [PreBolusAnalysis] {
        // Filter to entries with bolus timing data
        let entriesWithBolus = entries.filter { $0.preBolusMinutes != nil }
        
        // Group by meal type
        var mealGroups: [MealType: [Double]] = [:]
        
        for entry in entriesWithBolus {
            guard let preBolus = entry.preBolusMinutes else { continue }
            let mealType = MealType.classify(hour: entry.hourOfDay)
            mealGroups[mealType, default: []].append(preBolus)
        }
        
        var analyses: [PreBolusAnalysis] = []
        
        for (mealType, preBolusTimes) in mealGroups {
            guard preBolusTimes.count >= 3 else { continue }
            
            let avg = preBolusTimes.reduce(0, +) / Double(preBolusTimes.count)
            let stdDev = standardDeviation(preBolusTimes)
            let adequateCount = preBolusTimes.filter { $0 >= adequateThreshold }.count
            let adequateRate = Double(adequateCount) / Double(preBolusTimes.count)
            
            analyses.append(PreBolusAnalysis(
                mealType: mealType,
                averagePreBolusMinutes: avg,
                preBolusVariability: stdDev,
                adequatePreBolusRate: adequateRate,
                suggestedPreBolusMinutes: suggestedPreBolus,
                sampleCount: preBolusTimes.count
            ))
        }
        
        return analyses
    }
    
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - ALG-EFF-053: Meal-Specific CR/ISF

/// Meal-specific carb ratio and ISF adjustments
public struct MealSettingsModifier: Sendable, Codable, Equatable {
    /// Meal type
    public let mealType: MealType
    
    /// Carb ratio multiplier (e.g., 1.2 = need 20% more insulin for this meal)
    public let carbRatioMultiplier: Double
    
    /// ISF multiplier (e.g., 0.9 = 10% more insulin-sensitive at this time)
    public let isfMultiplier: Double
    
    /// Confidence in these adjustments
    public let confidence: Double
    
    /// Rationale
    public let rationale: String
    
    public init(
        mealType: MealType,
        carbRatioMultiplier: Double,
        isfMultiplier: Double,
        confidence: Double,
        rationale: String
    ) {
        self.mealType = mealType
        self.carbRatioMultiplier = carbRatioMultiplier
        self.isfMultiplier = isfMultiplier
        self.confidence = confidence
        self.rationale = rationale
    }
    
    /// Whether this modifier suggests more insulin than baseline
    public var needsMoreInsulin: Bool {
        carbRatioMultiplier > 1.0
    }
    
    /// Human-readable adjustment description
    public var adjustmentDescription: String {
        var parts: [String] = []
        
        if abs(carbRatioMultiplier - 1.0) >= 0.05 {
            let pct = Int((carbRatioMultiplier - 1.0) * 100)
            let direction = pct > 0 ? "more" : "less"
            parts.append("\(abs(pct))% \(direction) insulin for carbs")
        }
        
        if abs(isfMultiplier - 1.0) >= 0.05 {
            let pct = Int((1.0 - isfMultiplier) * 100)
            let direction = pct > 0 ? "more" : "less"
            parts.append("\(abs(pct))% \(direction) sensitive")
        }
        
        return parts.isEmpty ? "No adjustment" : parts.joined(separator: ", ")
    }
}

/// Analyzes post-meal glucose to suggest CR/ISF adjustments
public struct MealSettingsAnalyzer: Sendable {
    
    /// A meal with outcome data
    public struct MealOutcome: Sendable {
        public let entry: MealCarbEntry
        public let preGlucose: Double  // mg/dL before meal
        public let peakGlucose: Double // Peak after meal
        public let postGlucose: Double // 3-4 hours after meal
        
        public init(entry: MealCarbEntry, preGlucose: Double, peakGlucose: Double, postGlucose: Double) {
            self.entry = entry
            self.preGlucose = preGlucose
            self.peakGlucose = peakGlucose
            self.postGlucose = postGlucose
        }
        
        /// Peak rise from pre-meal (mg/dL)
        public var peakRise: Double {
            peakGlucose - preGlucose
        }
        
        /// Net change from pre to post (mg/dL)
        public var netChange: Double {
            postGlucose - preGlucose
        }
        
        /// Whether outcome was good (ended near starting point, peak < 180)
        public var isGoodOutcome: Bool {
            abs(netChange) <= 30 && peakGlucose <= 180
        }
    }
    
    public init() {}
    
    /// Analyze meal outcomes to suggest CR/ISF adjustments
    public func analyze(outcomes: [MealOutcome]) -> [MealSettingsModifier] {
        // Group by meal type
        var mealGroups: [MealType: [MealOutcome]] = [:]
        
        for outcome in outcomes {
            let mealType = MealType.classify(hour: outcome.entry.hourOfDay)
            mealGroups[mealType, default: []].append(outcome)
        }
        
        var modifiers: [MealSettingsModifier] = []
        
        for (mealType, mealOutcomes) in mealGroups {
            guard mealOutcomes.count >= 5 else { continue }
            
            let avgPeakRise = mealOutcomes.map { $0.peakRise }.reduce(0, +) / Double(mealOutcomes.count)
            let avgNetChange = mealOutcomes.map { $0.netChange }.reduce(0, +) / Double(mealOutcomes.count)
            let goodRate = Double(mealOutcomes.filter { $0.isGoodOutcome }.count) / Double(mealOutcomes.count)
            
            // Calculate CR multiplier: if ending high, need more insulin
            var crMultiplier = 1.0
            if avgNetChange > 30 {
                // Ending high - need more insulin
                crMultiplier = 1.0 + min(0.3, avgNetChange / 200.0)
            } else if avgNetChange < -30 {
                // Ending low - need less insulin
                crMultiplier = 1.0 - min(0.2, abs(avgNetChange) / 200.0)
            }
            
            // ISF adjustment based on peak rise
            var isfMultiplier = 1.0
            if avgPeakRise > 60 {
                // High peaks - may be more resistant at this time
                isfMultiplier = 1.0 + min(0.2, (avgPeakRise - 60) / 200.0)
            }
            
            // Build rationale
            var rationale = "Based on \(mealOutcomes.count) \(mealType.rawValue.lowercased()) meals: "
            if avgNetChange > 20 {
                rationale += "average +\(Int(avgNetChange)) mg/dL after 3-4 hours"
            } else if avgNetChange < -20 {
                rationale += "average \(Int(avgNetChange)) mg/dL after 3-4 hours"
            } else {
                rationale += "good post-meal return to baseline"
            }
            
            // Only include if there's an adjustment to suggest
            if abs(crMultiplier - 1.0) >= 0.05 || abs(isfMultiplier - 1.0) >= 0.05 {
                let confidence = min(1.0, Double(mealOutcomes.count) / 14.0) * (1.0 - goodRate * 0.5)
                
                modifiers.append(MealSettingsModifier(
                    mealType: mealType,
                    carbRatioMultiplier: crMultiplier,
                    isfMultiplier: isfMultiplier,
                    confidence: confidence,
                    rationale: rationale
                ))
            }
        }
        
        return modifiers
    }
}

// MARK: - ALG-EFF-054: Meal Prediction Alerts

/// Alert when approaching typical meal time
public struct MealPredictionAlert: Sendable, Codable {
    /// Expected meal type
    public let mealType: MealType
    
    /// Expected time
    public let expectedTime: Date
    
    /// Confidence
    public let confidence: Double
    
    /// Minutes until expected meal
    public let minutesUntil: Double
    
    /// Suggested carbs based on history
    public let suggestedCarbs: Double?
    
    public init(
        mealType: MealType,
        expectedTime: Date,
        confidence: Double,
        minutesUntil: Double,
        suggestedCarbs: Double?
    ) {
        self.mealType = mealType
        self.expectedTime = expectedTime
        self.confidence = confidence
        self.minutesUntil = minutesUntil
        self.suggestedCarbs = suggestedCarbs
    }
    
    /// Alert message
    public var message: String {
        let timeStr = formatTime(expectedTime)
        var msg = "\(mealType.rawValue) typically at \(timeStr)"
        if let carbs = suggestedCarbs {
            msg += " (~\(Int(carbs))g)"
        }
        return msg
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// Generates meal prediction alerts based on patterns
public actor MealPredictionManager {
    
    private var patterns: [MealPattern] = []
    private var carbEstimates: [MealCarbEstimate] = []
    private var lastAlertedMeals: [MealType: Date] = [:]
    
    /// Alert threshold (minutes before expected meal)
    public let alertThresholdMinutes: Double
    
    /// Minimum confidence for alerts
    public let minimumConfidence: Double
    
    public init(
        alertThresholdMinutes: Double = 30,
        minimumConfidence: Double = 0.6
    ) {
        self.alertThresholdMinutes = alertThresholdMinutes
        self.minimumConfidence = minimumConfidence
    }
    
    /// Update patterns and estimates from analysis
    public func updatePatterns(_ patterns: [MealPattern], estimates: [MealCarbEstimate]) {
        self.patterns = patterns
        self.carbEstimates = estimates
    }
    
    /// Check for pending alerts
    public func checkForAlerts(at date: Date = Date()) -> [MealPredictionAlert] {
        let calendar = Calendar.current
        let currentHour = Double(calendar.component(.hour, from: date)) + 
                          Double(calendar.component(.minute, from: date)) / 60.0
        let dayOfWeek = calendar.component(.weekday, from: date)
        
        var alerts: [MealPredictionAlert] = []
        
        for pattern in patterns {
            guard pattern.confidence >= minimumConfidence else { continue }
            
            // Check if pattern applies today
            if !pattern.daysOfWeek.isEmpty && !pattern.daysOfWeek.contains(dayOfWeek) {
                continue
            }
            
            // Check if we already alerted for this meal today
            if let lastAlert = lastAlertedMeals[pattern.mealType],
               calendar.isDate(lastAlert, inSameDayAs: date) {
                continue
            }
            
            // Calculate minutes until expected meal
            var hourDiff = pattern.typicalHour - currentHour
            if hourDiff < 0 { hourDiff += 24 } // Wrap to next day
            let minutesUntil = hourDiff * 60
            
            // Only alert if within threshold
            if minutesUntil <= alertThresholdMinutes && minutesUntil >= 0 {
                let expectedTime = date.addingTimeInterval(minutesUntil * 60)
                let suggestedCarbs = carbEstimates.first { $0.mealType == pattern.mealType }?.averageCarbs
                
                alerts.append(MealPredictionAlert(
                    mealType: pattern.mealType,
                    expectedTime: expectedTime,
                    confidence: pattern.confidence,
                    minutesUntil: minutesUntil,
                    suggestedCarbs: suggestedCarbs
                ))
                
                // Mark as alerted
                lastAlertedMeals[pattern.mealType] = date
            }
        }
        
        return alerts
    }
    
    /// Clear alert history (for new day)
    public func clearAlertHistory() {
        lastAlertedMeals.removeAll()
    }
    
    /// Get current patterns
    public func getPatterns() -> [MealPattern] {
        patterns
    }
}

// MARK: - Meal Pattern Agent

/// The main meal pattern agent combining all analysis
public actor MealPatternAgent {
    
    private let patternAnalyzer: MealPatternAnalyzer
    private let carbEstimator: MealCarbEstimator
    private let preBolusAnalyzer: PreBolusAnalyzer
    private let settingsAnalyzer: MealSettingsAnalyzer
    private let predictionManager: MealPredictionManager
    
    private var detectedPatterns: [MealPattern] = []
    private var carbEstimates: [MealCarbEstimate] = []
    private var preBolusAnalyses: [PreBolusAnalysis] = []
    private var settingsModifiers: [MealSettingsModifier] = []
    
    /// Training status
    public private(set) var trainingStatus: TrainingStatus = .hunch(sessions: 0)
    
    public init(
        patternAnalyzer: MealPatternAnalyzer = MealPatternAnalyzer(),
        carbEstimator: MealCarbEstimator = MealCarbEstimator(),
        preBolusAnalyzer: PreBolusAnalyzer = PreBolusAnalyzer(),
        settingsAnalyzer: MealSettingsAnalyzer = MealSettingsAnalyzer(),
        predictionManager: MealPredictionManager = MealPredictionManager()
    ) {
        self.patternAnalyzer = patternAnalyzer
        self.carbEstimator = carbEstimator
        self.preBolusAnalyzer = preBolusAnalyzer
        self.settingsAnalyzer = settingsAnalyzer
        self.predictionManager = predictionManager
    }
    
    /// Train the agent with carb entry history and meal outcomes
    public func train(
        entries: [MealCarbEntry],
        outcomes: [MealSettingsAnalyzer.MealOutcome] = []
    ) async {
        // Analyze patterns
        detectedPatterns = patternAnalyzer.analyzePatterns(entries: entries)
        
        // Estimate carbs
        carbEstimates = carbEstimator.estimateCarbs(entries: entries)
        
        // Analyze pre-bolus timing
        preBolusAnalyses = preBolusAnalyzer.analyze(entries: entries)
        
        // Analyze settings if outcomes available
        if !outcomes.isEmpty {
            settingsModifiers = settingsAnalyzer.analyze(outcomes: outcomes)
        }
        
        // Update prediction manager
        await predictionManager.updatePatterns(detectedPatterns, estimates: carbEstimates)
        
        // Update training status
        let totalSamples = entries.count
        let avgConfidence = detectedPatterns.isEmpty ? 0 :
            detectedPatterns.map { $0.confidence }.reduce(0, +) / Double(detectedPatterns.count)
        
        if totalSamples >= 30 && avgConfidence >= 0.8 {
            trainingStatus = .graduated(confidence: avgConfidence)
        } else if totalSamples >= 14 && avgConfidence >= 0.6 {
            trainingStatus = .trained(sessions: totalSamples, confidence: avgConfidence)
        } else {
            trainingStatus = .hunch(sessions: totalSamples)
        }
    }
    
    /// Get detected meal patterns
    public func getPatterns() -> [MealPattern] {
        detectedPatterns
    }
    
    /// Get carb estimates
    public func getCarbEstimates() -> [MealCarbEstimate] {
        carbEstimates
    }
    
    /// Get pre-bolus analyses
    public func getPreBolusAnalyses() -> [PreBolusAnalysis] {
        preBolusAnalyses
    }
    
    /// Get settings modifiers
    public func getSettingsModifiers() -> [MealSettingsModifier] {
        settingsModifiers
    }
    
    /// Check for meal prediction alerts
    public func checkForAlerts(at date: Date = Date()) async -> [MealPredictionAlert] {
        await predictionManager.checkForAlerts(at: date)
    }
    
    /// Get modifier for a specific meal type
    public func getModifier(for mealType: MealType) -> MealSettingsModifier? {
        settingsModifiers.first { $0.mealType == mealType }
    }
    
    /// Get carb estimate for a specific meal type
    public func getCarbEstimate(for mealType: MealType) -> MealCarbEstimate? {
        carbEstimates.first { $0.mealType == mealType }
    }
}
