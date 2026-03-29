// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CircadianAgent.swift
// T1PalAlgorithm
//
// Circadian rhythm analysis and dawn phenomenon detection
// ALG-EFF-030..031: Dawn phenomenon timing, sleep/wake pattern training
//
// Trace: PRD-028 (ML-Enhanced Dosing)

import Foundation

// MARK: - ALG-EFF-030: Dawn Phenomenon Analysis

/// Represents a detected dawn phenomenon pattern for a user
public struct DawnPhenomenon: Sendable, Codable, Equatable {
    /// Typical start time (hours since midnight, e.g., 4.5 = 4:30am)
    public let startHour: Double
    
    /// Typical end time (hours since midnight)
    public let endHour: Double
    
    /// Average glucose rise during dawn (mg/dL)
    public let averageRise: Double
    
    /// Peak rise observed (mg/dL)
    public let peakRise: Double
    
    /// Confidence in this pattern (0.0-1.0)
    public let confidence: Double
    
    /// Number of days analyzed to detect this pattern
    public let daysAnalyzed: Int
    
    /// Standard deviation of start time (hours)
    public let startTimeVariability: Double
    
    /// Suggested basal increase percentage during dawn
    public var suggestedBasalIncrease: Double {
        // Rough heuristic: 1% increase per 3 mg/dL average rise
        // Capped at 50% increase for safety
        return min(0.5, averageRise / 300.0)
    }
    
    public init(
        startHour: Double,
        endHour: Double,
        averageRise: Double,
        peakRise: Double,
        confidence: Double,
        daysAnalyzed: Int,
        startTimeVariability: Double
    ) {
        self.startHour = startHour
        self.endHour = endHour
        self.averageRise = averageRise
        self.peakRise = peakRise
        self.confidence = confidence
        self.daysAnalyzed = daysAnalyzed
        self.startTimeVariability = startTimeVariability
    }
    
    /// Duration of dawn phenomenon in hours
    public var durationHours: Double {
        if endHour > startHour {
            return endHour - startHour
        } else {
            // Wraps past midnight
            return (24 - startHour) + endHour
        }
    }
    
    /// Formatted time range string
    public var timeRangeDescription: String {
        let startFormatted = formatHour(startHour)
        let endFormatted = formatHour(endHour)
        return "\(startFormatted) - \(endFormatted)"
    }
    
    private func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        _ = h >= 12 ? "am" : "am"  // period, currently unused
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        if m == 0 {
            return "\(displayH)\(h >= 12 ? "am" : "am")"
        }
        return "\(displayH):\(String(format: "%02d", m))\(h >= 12 ? "am" : "am")"
    }
}

/// Analyzes glucose data to detect dawn phenomenon patterns
public struct DawnPhenomenonAnalyzer: Sendable {
    
    /// Configuration for dawn analysis
    public struct Configuration: Sendable {
        /// Minimum days of data required for analysis
        public let minimumDays: Int
        
        /// Time window to search for dawn (start hour)
        public let searchWindowStart: Double
        
        /// Time window to search for dawn (end hour)
        public let searchWindowEnd: Double
        
        /// Minimum glucose rise to consider significant (mg/dL)
        public let minimumRiseThreshold: Double
        
        /// Minimum confidence to report a pattern
        public let minimumConfidence: Double
        
        public init(
            minimumDays: Int = 7,
            searchWindowStart: Double = 3.0,  // 3am
            searchWindowEnd: Double = 9.0,     // 9am
            minimumRiseThreshold: Double = 20.0,
            minimumConfidence: Double = 0.6
        ) {
            self.minimumDays = minimumDays
            self.searchWindowStart = searchWindowStart
            self.searchWindowEnd = searchWindowEnd
            self.minimumRiseThreshold = minimumRiseThreshold
            self.minimumConfidence = minimumConfidence
        }
        
        public static let `default` = Configuration()
    }
    
    public let configuration: Configuration
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    /// A single glucose reading with timestamp for analysis
    public struct TimestampedGlucose: Sendable {
        public let timestamp: Date
        public let value: Double // mg/dL
        
        public init(timestamp: Date, value: Double) {
            self.timestamp = timestamp
            self.value = value
        }
        
        /// Hour of day (0-24, fractional)
        public var hourOfDay: Double {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: timestamp)
            return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0
        }
    }
    
    /// Analyze glucose history to detect dawn phenomenon
    /// - Parameter readings: Historical glucose readings (at least minimumDays worth)
    /// - Returns: Detected dawn phenomenon pattern, or nil if not found
    public func analyze(readings: [TimestampedGlucose]) -> DawnPhenomenon? {
        // Group readings by day
        let calendar = Calendar.current
        var dayGroups: [Date: [TimestampedGlucose]] = [:]
        
        for reading in readings {
            let dayStart = calendar.startOfDay(for: reading.timestamp)
            dayGroups[dayStart, default: []].append(reading)
        }
        
        guard dayGroups.count >= configuration.minimumDays else {
            return nil
        }
        
        // Analyze each day for dawn rise
        var dawnEvents: [DawnEvent] = []
        
        for (_, dayReadings) in dayGroups {
            if let event = detectDawnRise(in: dayReadings) {
                dawnEvents.append(event)
            }
        }
        
        // Need at least half the days to show dawn pattern
        let minimumEventsRequired = max(3, dayGroups.count / 2)
        guard dawnEvents.count >= minimumEventsRequired else {
            return nil
        }
        
        // Calculate aggregate statistics
        let startHours = dawnEvents.map { $0.startHour }
        let endHours = dawnEvents.map { $0.endHour }
        let rises = dawnEvents.map { $0.glucoseRise }
        
        let avgStartHour = startHours.reduce(0, +) / Double(startHours.count)
        let avgEndHour = endHours.reduce(0, +) / Double(endHours.count)
        let avgRise = rises.reduce(0, +) / Double(rises.count)
        let peakRise = rises.max() ?? avgRise
        
        // Calculate start time variability (standard deviation)
        let startVariance = startHours.map { pow($0 - avgStartHour, 2) }.reduce(0, +) / Double(startHours.count)
        let startStdDev = sqrt(startVariance)
        
        // Confidence based on consistency and sample size
        let consistencyScore = 1.0 - min(1.0, startStdDev / 2.0) // Lower variability = higher confidence
        let sampleSizeScore = min(1.0, Double(dawnEvents.count) / 14.0) // More days = higher confidence
        let riseScore = min(1.0, avgRise / 50.0) // Clearer rise = higher confidence
        
        let confidence = (consistencyScore * 0.4 + sampleSizeScore * 0.3 + riseScore * 0.3)
        
        guard confidence >= configuration.minimumConfidence else {
            return nil
        }
        
        return DawnPhenomenon(
            startHour: avgStartHour,
            endHour: avgEndHour,
            averageRise: avgRise,
            peakRise: peakRise,
            confidence: confidence,
            daysAnalyzed: dayGroups.count,
            startTimeVariability: startStdDev
        )
    }
    
    /// Represents a single dawn rise event
    private struct DawnEvent {
        let startHour: Double
        let endHour: Double
        let glucoseRise: Double
    }
    
    /// Detect dawn rise in a single day's readings
    private func detectDawnRise(in readings: [TimestampedGlucose]) -> DawnEvent? {
        // Filter to dawn window
        let dawnReadings = readings.filter { reading in
            let hour = reading.hourOfDay
            return hour >= configuration.searchWindowStart && hour <= configuration.searchWindowEnd
        }.sorted { $0.timestamp < $1.timestamp }
        
        guard dawnReadings.count >= 3 else { return nil }
        
        // Find lowest point in early window and highest point after
        let earlyWindow = dawnReadings.filter { $0.hourOfDay < (configuration.searchWindowStart + configuration.searchWindowEnd) / 2 }
        let lateWindow = dawnReadings.filter { $0.hourOfDay >= (configuration.searchWindowStart + configuration.searchWindowEnd) / 2 }
        
        guard let lowestEarly = earlyWindow.min(by: { $0.value < $1.value }),
              let highestLate = lateWindow.max(by: { $0.value < $1.value }) else {
            return nil
        }
        
        let rise = highestLate.value - lowestEarly.value
        
        guard rise >= configuration.minimumRiseThreshold else {
            return nil
        }
        
        return DawnEvent(
            startHour: lowestEarly.hourOfDay,
            endHour: highestLate.hourOfDay,
            glucoseRise: rise
        )
    }
}

// MARK: - ALG-EFF-031: Sleep/Wake Pattern Training

/// Represents detected sleep/wake patterns
public struct SleepWakePattern: Sendable, Codable, Equatable {
    /// Typical bedtime (hours since midnight)
    public let typicalBedtime: Double
    
    /// Typical wake time (hours since midnight)
    public let typicalWakeTime: Double
    
    /// Variability in bedtime (std dev in hours)
    public let bedtimeVariability: Double
    
    /// Variability in wake time (std dev in hours)
    public let wakeTimeVariability: Double
    
    /// Days analyzed
    public let daysAnalyzed: Int
    
    /// Confidence in pattern (0.0-1.0)
    public let confidence: Double
    
    /// Weekend pattern differs from weekday?
    public let hasWeekendShift: Bool
    
    /// Weekend bedtime shift (hours later)
    public let weekendBedtimeShift: Double
    
    /// Weekend wake time shift (hours later)
    public let weekendWakeShift: Double
    
    public init(
        typicalBedtime: Double,
        typicalWakeTime: Double,
        bedtimeVariability: Double,
        wakeTimeVariability: Double,
        daysAnalyzed: Int,
        confidence: Double,
        hasWeekendShift: Bool = false,
        weekendBedtimeShift: Double = 0,
        weekendWakeShift: Double = 0
    ) {
        self.typicalBedtime = typicalBedtime
        self.typicalWakeTime = typicalWakeTime
        self.bedtimeVariability = bedtimeVariability
        self.wakeTimeVariability = wakeTimeVariability
        self.daysAnalyzed = daysAnalyzed
        self.confidence = confidence
        self.hasWeekendShift = hasWeekendShift
        self.weekendBedtimeShift = weekendBedtimeShift
        self.weekendWakeShift = weekendWakeShift
    }
    
    /// Typical sleep duration in hours
    public var typicalSleepDuration: Double {
        if typicalWakeTime > typicalBedtime {
            // Unusual: wake after bed in same day (nap?)
            return typicalWakeTime - typicalBedtime
        } else {
            // Normal: bed at night, wake next morning
            return (24 - typicalBedtime) + typicalWakeTime
        }
    }
}

/// Source of sleep data
public enum SleepDataSource: String, Sendable, Codable {
    /// Apple HealthKit sleep analysis
    case healthKit
    
    /// Inferred from CGM activity patterns
    case cgmInferred
    
    /// User-reported schedule
    case userReported
    
    /// Wearable device (Fitbit, Garmin, etc.)
    case wearable
}

/// A single sleep record
public struct SleepRecord: Sendable {
    public let bedtime: Date
    public let wakeTime: Date
    public let source: SleepDataSource
    public let quality: SleepQuality?
    
    public init(
        bedtime: Date,
        wakeTime: Date,
        source: SleepDataSource,
        quality: SleepQuality? = nil
    ) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.source = source
        self.quality = quality
    }
    
    public var duration: TimeInterval {
        wakeTime.timeIntervalSince(bedtime)
    }
    
    public var durationHours: Double {
        duration / 3600.0
    }
}

/// Sleep quality assessment
public enum SleepQuality: String, Sendable, Codable {
    case poor
    case fair
    case good
    case excellent
    
    public var glucoseImpactFactor: Double {
        switch self {
        case .poor: return 1.15      // Poor sleep → higher insulin resistance
        case .fair: return 1.05
        case .good: return 1.0
        case .excellent: return 0.95 // Great sleep → slightly better sensitivity
        }
    }
}

/// Tracks sleep/wake patterns and trains circadian agent
public actor SleepWakePatternTracker {
    
    private var records: [SleepRecord] = []
    private var cachedPattern: SleepWakePattern?
    
    /// Minimum records required for pattern detection
    public let minimumRecords: Int
    
    public init(minimumRecords: Int = 7) {
        self.minimumRecords = minimumRecords
    }
    
    /// Add a sleep record
    public func addRecord(_ record: SleepRecord) {
        records.append(record)
        cachedPattern = nil // Invalidate cache
    }
    
    /// Add multiple records
    public func addRecords(_ newRecords: [SleepRecord]) {
        records.append(contentsOf: newRecords)
        cachedPattern = nil
    }
    
    /// Get current records count
    public func recordCount() -> Int {
        records.count
    }
    
    /// Analyze patterns and return detected sleep/wake schedule
    public func analyzePatterns() -> SleepWakePattern? {
        if let cached = cachedPattern {
            return cached
        }
        
        guard records.count >= minimumRecords else {
            return nil
        }
        
        let calendar = Calendar.current
        
        // Extract bedtime and wake time hours
        var weekdayBedtimes: [Double] = []
        var weekdayWakeTimes: [Double] = []
        var weekendBedtimes: [Double] = []
        var weekendWakeTimes: [Double] = []
        
        for record in records {
            let bedtimeHour = hourOfDay(from: record.bedtime, calendar: calendar)
            let wakeHour = hourOfDay(from: record.wakeTime, calendar: calendar)
            let weekday = calendar.component(.weekday, from: record.bedtime)
            let isWeekend = weekday == 1 || weekday == 7 // Sunday or Saturday
            
            if isWeekend {
                weekendBedtimes.append(bedtimeHour)
                weekendWakeTimes.append(wakeHour)
            } else {
                weekdayBedtimes.append(bedtimeHour)
                weekdayWakeTimes.append(wakeHour)
            }
        }
        
        // Calculate averages (handle hour wraparound for bedtimes)
        let avgBedtime = circularMean(weekdayBedtimes + weekendBedtimes, period: 24)
        let avgWakeTime = circularMean(weekdayWakeTimes + weekendWakeTimes, period: 24)
        
        let bedtimeStdDev = standardDeviation(weekdayBedtimes + weekendBedtimes)
        let wakeStdDev = standardDeviation(weekdayWakeTimes + weekendWakeTimes)
        
        // Check for weekend shift
        var hasWeekendShift = false
        var weekendBedShift = 0.0
        var weekendWakeShift = 0.0
        
        if weekendBedtimes.count >= 2 && weekdayBedtimes.count >= 3 {
            let weekdayAvgBed = circularMean(weekdayBedtimes, period: 24)
            let weekendAvgBed = circularMean(weekendBedtimes, period: 24)
            let weekdayAvgWake = circularMean(weekdayWakeTimes, period: 24)
            let weekendAvgWake = circularMean(weekendWakeTimes, period: 24)
            
            weekendBedShift = circularDifference(weekendAvgBed, weekdayAvgBed, period: 24)
            weekendWakeShift = circularDifference(weekendAvgWake, weekdayAvgWake, period: 24)
            
            // Significant shift if > 30 minutes
            hasWeekendShift = abs(weekendBedShift) > 0.5 || abs(weekendWakeShift) > 0.5
        }
        
        // Calculate confidence
        let sampleScore = min(1.0, Double(records.count) / 14.0)
        let consistencyScore = 1.0 - min(1.0, (bedtimeStdDev + wakeStdDev) / 4.0)
        let confidence = sampleScore * 0.4 + consistencyScore * 0.6
        
        let pattern = SleepWakePattern(
            typicalBedtime: avgBedtime,
            typicalWakeTime: avgWakeTime,
            bedtimeVariability: bedtimeStdDev,
            wakeTimeVariability: wakeStdDev,
            daysAnalyzed: records.count,
            confidence: confidence,
            hasWeekendShift: hasWeekendShift,
            weekendBedtimeShift: weekendBedShift,
            weekendWakeShift: weekendWakeShift
        )
        
        cachedPattern = pattern
        return pattern
    }
    
    /// Infer sleep records from CGM data gaps or low variability periods
    public func inferSleepFromCGM(readings: [DawnPhenomenonAnalyzer.TimestampedGlucose]) -> [SleepRecord] {
        // Group by day
        let calendar = Calendar.current
        var dayGroups: [Date: [DawnPhenomenonAnalyzer.TimestampedGlucose]] = [:]
        
        for reading in readings {
            let dayStart = calendar.startOfDay(for: reading.timestamp)
            dayGroups[dayStart, default: []].append(reading)
        }
        
        var inferredRecords: [SleepRecord] = []
        
        for (_, dayReadings) in dayGroups {
            let sorted = dayReadings.sorted { $0.timestamp < $1.timestamp }
            
            // Find period of lowest activity (likely sleep)
            // Look for readings between 10pm and 8am with low variability
            let nightReadings = sorted.filter { reading in
                let hour = reading.hourOfDay
                return hour >= 22 || hour <= 8
            }
            
            guard nightReadings.count >= 4 else { continue }
            
            // Estimate bedtime as first reading after 10pm with settling pattern
            // Estimate wake as first reading showing activity after 5am
            if let firstNight = nightReadings.first(where: { $0.hourOfDay >= 22 }),
               let lastMorning = nightReadings.last(where: { $0.hourOfDay <= 8 && $0.hourOfDay >= 5 }) {
                
                // Adjust to reasonable sleep times
                let bedtime = firstNight.timestamp
                var wakeTime = lastMorning.timestamp
                
                // If wake is before bed (next day), adjust
                if wakeTime < bedtime {
                    wakeTime = calendar.date(byAdding: .day, value: 1, to: wakeTime) ?? wakeTime
                }
                
                // Sanity check: sleep between 4-12 hours
                let duration = wakeTime.timeIntervalSince(bedtime) / 3600.0
                if duration >= 4 && duration <= 12 {
                    inferredRecords.append(SleepRecord(
                        bedtime: bedtime,
                        wakeTime: wakeTime,
                        source: .cgmInferred
                    ))
                }
            }
        }
        
        return inferredRecords
    }
    
    // MARK: - Math Helpers
    
    private func hourOfDay(from date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0
    }
    
    private func circularMean(_ values: [Double], period: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        
        // Convert to radians, compute mean, convert back
        let angles = values.map { $0 * 2 * .pi / period }
        let sinSum = angles.map { sin($0) }.reduce(0, +)
        let cosSum = angles.map { cos($0) }.reduce(0, +)
        
        var meanAngle = atan2(sinSum, cosSum)
        if meanAngle < 0 { meanAngle += 2 * .pi }
        
        return meanAngle * period / (2 * .pi)
    }
    
    private func circularDifference(_ a: Double, _ b: Double, period: Double) -> Double {
        var diff = a - b
        if diff > period / 2 { diff -= period }
        if diff < -period / 2 { diff += period }
        return diff
    }
    
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - Circadian Effect Modifier

/// Time-based effect modifier for circadian patterns
public struct CircadianEffectModifier: Sendable, Codable {
    /// Hour ranges and their basal adjustments
    public let hourlyAdjustments: [HourlyAdjustment]
    
    /// Source of this modifier (dawn analysis, sleep patterns, etc.)
    public let source: String
    
    /// Confidence in this modifier
    public let confidence: Double
    
    public init(hourlyAdjustments: [HourlyAdjustment], source: String, confidence: Double) {
        self.hourlyAdjustments = hourlyAdjustments
        self.source = source
        self.confidence = confidence
    }
    
    /// A basal adjustment for a specific hour range
    public struct HourlyAdjustment: Sendable, Codable, Equatable {
        public let startHour: Int // 0-23
        public let endHour: Int   // 0-23
        public let basalMultiplier: Double // e.g., 1.2 = +20%
        public let reason: String
        
        public init(startHour: Int, endHour: Int, basalMultiplier: Double, reason: String) {
            self.startHour = startHour
            self.endHour = endHour
            self.basalMultiplier = basalMultiplier
            self.reason = reason
        }
        
        /// Check if this adjustment applies to a given hour
        public func applies(to hour: Int) -> Bool {
            if startHour <= endHour {
                return hour >= startHour && hour < endHour
            } else {
                // Wraps around midnight
                return hour >= startHour || hour < endHour
            }
        }
    }
    
    /// Get the basal multiplier for a specific time
    public func multiplier(for date: Date) -> Double {
        let hour = Calendar.current.component(.hour, from: date)
        
        for adjustment in hourlyAdjustments {
            if adjustment.applies(to: hour) {
                return adjustment.basalMultiplier
            }
        }
        
        return 1.0 // No adjustment
    }
    
    /// Create a modifier from dawn phenomenon analysis
    public static func fromDawnPhenomenon(_ dawn: DawnPhenomenon) -> CircadianEffectModifier {
        let startHour = Int(dawn.startHour)
        let endHour = Int(dawn.endHour)
        let increase = 1.0 + dawn.suggestedBasalIncrease
        
        let adjustment = HourlyAdjustment(
            startHour: startHour,
            endHour: endHour,
            basalMultiplier: increase,
            reason: "Dawn phenomenon compensation"
        )
        
        return CircadianEffectModifier(
            hourlyAdjustments: [adjustment],
            source: "DawnPhenomenonAnalyzer",
            confidence: dawn.confidence
        )
    }
    
    /// Create a modifier from sleep pattern (reduced basal during sleep)
    public static func fromSleepPattern(_ pattern: SleepWakePattern) -> CircadianEffectModifier {
        // During sleep, some people need less basal (others more for dawn)
        // This creates a slight reduction during deep sleep hours
        let sleepStart = Int(pattern.typicalBedtime) + 1 // An hour after bed
        let sleepEnd = Int(pattern.typicalWakeTime) - 1   // An hour before wake
        
        // Only apply if we have a valid sleep window
        guard sleepStart != sleepEnd else {
            return CircadianEffectModifier(hourlyAdjustments: [], source: "SleepPattern", confidence: pattern.confidence)
        }
        
        let adjustment = HourlyAdjustment(
            startHour: sleepStart,
            endHour: sleepEnd,
            basalMultiplier: 0.95, // Slight reduction during deep sleep
            reason: "Sleep period adjustment"
        )
        
        return CircadianEffectModifier(
            hourlyAdjustments: [adjustment],
            source: "SleepWakePatternTracker",
            confidence: pattern.confidence
        )
    }
}

// MARK: - Circadian Agent

/// The main circadian agent that combines dawn phenomenon and sleep/wake analysis
public actor CircadianAgent {
    
    private let dawnAnalyzer: DawnPhenomenonAnalyzer
    private let sleepTracker: SleepWakePatternTracker
    
    private var detectedDawn: DawnPhenomenon?
    private var detectedSleepPattern: SleepWakePattern?
    private var currentModifier: CircadianEffectModifier?
    
    /// Training status
    public private(set) var trainingStatus: TrainingStatus = .hunch(sessions: 0)
    
    public init(
        dawnAnalyzer: DawnPhenomenonAnalyzer = DawnPhenomenonAnalyzer(),
        sleepTracker: SleepWakePatternTracker = SleepWakePatternTracker()
    ) {
        self.dawnAnalyzer = dawnAnalyzer
        self.sleepTracker = sleepTracker
    }
    
    /// Train the agent with glucose and sleep data
    public func train(
        glucoseReadings: [DawnPhenomenonAnalyzer.TimestampedGlucose],
        sleepRecords: [SleepRecord] = []
    ) async {
        let daysOfData = glucoseReadings.count / 288 // ~288 readings per day at 5-min intervals
        
        // Analyze dawn phenomenon
        detectedDawn = dawnAnalyzer.analyze(readings: glucoseReadings)
        
        // Add sleep records (or infer from CGM if none provided)
        if sleepRecords.isEmpty {
            let inferred = await sleepTracker.inferSleepFromCGM(readings: glucoseReadings)
            await sleepTracker.addRecords(inferred)
        } else {
            await sleepTracker.addRecords(sleepRecords)
        }
        
        detectedSleepPattern = await sleepTracker.analyzePatterns()
        
        // Build combined modifier
        currentModifier = buildCombinedModifier()
        
        // Update training status based on data and confidence
        if detectedDawn != nil || detectedSleepPattern != nil {
            let confidence = max(detectedDawn?.confidence ?? 0, detectedSleepPattern?.confidence ?? 0)
            if daysOfData >= 14 && confidence >= 0.8 {
                trainingStatus = .graduated(confidence: confidence)
            } else if daysOfData >= 7 && confidence >= 0.6 {
                trainingStatus = .trained(sessions: daysOfData, confidence: confidence)
            } else {
                trainingStatus = .hunch(sessions: daysOfData)
            }
        } else {
            trainingStatus = .hunch(sessions: 0)
        }
    }
    
    /// Get current effect modifier for a given time
    public func getModifier(for date: Date = Date()) -> CircadianEffectModifier? {
        currentModifier
    }
    
    /// Get detected dawn phenomenon
    public func getDawnPhenomenon() -> DawnPhenomenon? {
        detectedDawn
    }
    
    /// Get detected sleep pattern
    public func getSleepPattern() -> SleepWakePattern? {
        detectedSleepPattern
    }
    
    /// Get basal multiplier for current time
    public func currentBasalMultiplier(at date: Date = Date()) -> Double {
        currentModifier?.multiplier(for: date) ?? 1.0
    }
    
    private func buildCombinedModifier() -> CircadianEffectModifier? {
        var adjustments: [CircadianEffectModifier.HourlyAdjustment] = []
        var totalConfidence = 0.0
        var sourceCount = 0
        
        // Add dawn adjustment if detected
        if let dawn = detectedDawn {
            let dawnModifier = CircadianEffectModifier.fromDawnPhenomenon(dawn)
            adjustments.append(contentsOf: dawnModifier.hourlyAdjustments)
            totalConfidence += dawn.confidence
            sourceCount += 1
        }
        
        // Add sleep adjustment if detected (with high confidence)
        if let sleep = detectedSleepPattern, sleep.confidence >= 0.7 {
            let sleepModifier = CircadianEffectModifier.fromSleepPattern(sleep)
            adjustments.append(contentsOf: sleepModifier.hourlyAdjustments)
            totalConfidence += sleep.confidence
            sourceCount += 1
        }
        
        guard !adjustments.isEmpty else { return nil }
        
        let avgConfidence = totalConfidence / Double(sourceCount)
        
        return CircadianEffectModifier(
            hourlyAdjustments: adjustments,
            source: "CircadianAgent",
            confidence: avgConfidence
        )
    }
}

// MARK: - Training Status (reuse from ActivityAgentBootstrapper)

// Note: TrainingStatus is defined in ActivityAgentBootstrapper.swift
// Import or reference it here
