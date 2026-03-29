// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SmartOverrideSuggestions.swift
// T1PalAlgorithm
//
// Detects patterns and suggests override creation without explicit user setup
// Backlog: ALG-LEARN-030, ALG-LEARN-031, ALG-LEARN-032, ALG-LEARN-033
// Trace: PRD-028 (ML-Enhanced Dosing)

import Foundation

// MARK: - Recurring Pattern Detection (ALG-LEARN-030)

/// A detected recurring glucose pattern that may benefit from an override
public struct RecurringPattern: Sendable, Identifiable, Codable {
    public let id: UUID
    
    /// Type of pattern detected
    public let patternType: PatternType
    
    /// When this pattern typically occurs
    public let timing: PatternTiming
    
    /// How confident we are in this pattern
    public let confidence: Double
    
    /// Number of occurrences observed
    public let occurrenceCount: Int
    
    /// Average glucose impact (positive = high, negative = low)
    public let averageGlucoseImpact: Double
    
    /// Suggested settings to address the pattern
    public let suggestedSettings: OverrideSettings
    
    /// Human-readable description
    public let description: String
    
    /// When pattern was first detected
    public let firstDetected: Date
    
    /// Most recent occurrence
    public let lastOccurrence: Date
    
    public init(
        id: UUID = UUID(),
        patternType: PatternType,
        timing: PatternTiming,
        confidence: Double,
        occurrenceCount: Int,
        averageGlucoseImpact: Double,
        suggestedSettings: OverrideSettings,
        description: String,
        firstDetected: Date = Date(),
        lastOccurrence: Date = Date()
    ) {
        self.id = id
        self.patternType = patternType
        self.timing = timing
        self.confidence = confidence
        self.occurrenceCount = occurrenceCount
        self.averageGlucoseImpact = averageGlucoseImpact
        self.suggestedSettings = suggestedSettings
        self.description = description
        self.firstDetected = firstDetected
        self.lastOccurrence = lastOccurrence
    }
    
    public enum PatternType: String, Codable, Sendable {
        case timeOfDay = "timeOfDay"
        case dayOfWeek = "dayOfWeek"
        case postMeal = "postMeal"
        case preMeal = "preMeal"
        case exercise = "exercise"
        case sleep = "sleep"
        case dawn = "dawn"  // Dawn phenomenon
        case stress = "stress"
        case menstrualCycle = "menstrualCycle"
    }
}

/// When a pattern occurs
public struct PatternTiming: Sendable, Codable {
    /// Days of week (1=Sunday, 7=Saturday)
    public let daysOfWeek: Set<Int>?
    
    /// Hour range (0-23)
    public let hourRange: ClosedRange<Int>?
    
    /// Specific time of day category
    public let timeOfDay: OverrideContext.TimeOfDay?
    
    /// Relative to meals (minutes before/after)
    public let mealRelativeMinutes: Int?
    
    public init(
        daysOfWeek: Set<Int>? = nil,
        hourRange: ClosedRange<Int>? = nil,
        timeOfDay: OverrideContext.TimeOfDay? = nil,
        mealRelativeMinutes: Int? = nil
    ) {
        self.daysOfWeek = daysOfWeek
        self.hourRange = hourRange
        self.timeOfDay = timeOfDay
        self.mealRelativeMinutes = mealRelativeMinutes
    }
    
    /// Human-readable timing description
    public var displayDescription: String {
        var parts: [String] = []
        
        if let days = daysOfWeek {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayStrs = days.sorted().compactMap { d in
                d >= 1 && d <= 7 ? dayNames[d - 1] : nil
            }
            if dayStrs.count == 7 {
                parts.append("every day")
            } else if dayStrs.count == 5 && !days.contains(1) && !days.contains(7) {
                parts.append("weekdays")
            } else if dayStrs.count == 2 && days.contains(1) && days.contains(7) {
                parts.append("weekends")
            } else {
                parts.append(dayStrs.joined(separator: ", "))
            }
        }
        
        if let range = hourRange {
            let startHour = range.lowerBound
            let endHour = range.upperBound
            parts.append("\(formatHour(startHour))-\(formatHour(endHour))")
        } else if let tod = timeOfDay {
            parts.append(tod.rawValue)
        }
        
        return parts.isEmpty ? "recurring" : parts.joined(separator: " ")
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour == 12 { return "12pm" }
        if hour < 12 { return "\(hour)am" }
        return "\(hour - 12)pm"
    }
}

/// Detects recurring glucose patterns from historical data
public actor PatternDetector {
    
    /// Minimum occurrences to consider a pattern valid
    public let minOccurrences: Int
    
    /// Minimum confidence to report a pattern
    public let minConfidence: Double
    
    /// Historical glucose data window (days)
    public let analysisWindowDays: Int
    
    /// Glucose readings for analysis
    private var glucoseHistory: [PatternGlucoseReading] = []
    
    /// Detected patterns
    private var detectedPatterns: [RecurringPattern] = []
    
    /// Last analysis timestamp
    private var lastAnalysis: Date?
    
    public init(
        minOccurrences: Int = 3,
        minConfidence: Double = 0.6,
        analysisWindowDays: Int = 14
    ) {
        self.minOccurrences = minOccurrences
        self.minConfidence = minConfidence
        self.analysisWindowDays = analysisWindowDays
    }
    
    /// Add glucose readings for analysis
    public func addReadings(_ readings: [PatternGlucoseReading]) {
        glucoseHistory.append(contentsOf: readings)
        trimOldReadings()
    }
    
    /// Run pattern detection
    public func analyzePatterns() -> [RecurringPattern] {
        lastAnalysis = Date()
        
        var patterns: [RecurringPattern] = []
        
        // Detect time-of-day patterns
        patterns.append(contentsOf: detectTimeOfDayPatterns())
        
        // Detect day-of-week patterns
        patterns.append(contentsOf: detectDayOfWeekPatterns())
        
        // Detect dawn phenomenon
        if let dawn = detectDawnPhenomenon() {
            patterns.append(dawn)
        }
        
        // Filter by confidence and occurrences
        detectedPatterns = patterns.filter {
            $0.confidence >= minConfidence && $0.occurrenceCount >= minOccurrences
        }
        
        return detectedPatterns
    }
    
    /// Get current detected patterns
    public func patterns() -> [RecurringPattern] {
        detectedPatterns
    }
    
    // MARK: - Pattern Detection Algorithms
    
    private func detectTimeOfDayPatterns() -> [RecurringPattern] {
        var patterns: [RecurringPattern] = []
        
        // Group readings by hour
        var hourlyReadings: [Int: [PatternGlucoseReading]] = [:]
        for reading in glucoseHistory {
            let hour = Calendar.current.component(.hour, from: reading.timestamp)
            hourlyReadings[hour, default: []].append(reading)
        }
        
        // Find hours with consistently high/low glucose
        for (hour, readings) in hourlyReadings where readings.count >= minOccurrences {
            let avgGlucose = readings.map(\.value).reduce(0, +) / Double(readings.count)
            let highCount = readings.filter { $0.value > 180 }.count
            let lowCount = readings.filter { $0.value < 70 }.count
            
            let highRatio = Double(highCount) / Double(readings.count)
            let lowRatio = Double(lowCount) / Double(readings.count)
            
            // High pattern detected
            if highRatio > 0.4 {
                let impact = avgGlucose - 120  // Deviation from target
                let suggestedBasal = max(0.8, 1.0 + (impact / 200)) // More insulin needed
                
                patterns.append(RecurringPattern(
                    patternType: .timeOfDay,
                    timing: PatternTiming(hourRange: hour...hour),
                    confidence: highRatio,
                    occurrenceCount: highCount,
                    averageGlucoseImpact: impact,
                    suggestedSettings: OverrideSettings(
                        basalMultiplier: suggestedBasal,
                        isfMultiplier: 1.0 / suggestedBasal
                    ),
                    description: "High glucose often around \(formatHour(hour))"
                ))
            }
            
            // Low pattern detected
            if lowRatio > 0.3 {
                let impact = avgGlucose - 120
                let suggestedBasal = min(0.5, 1.0 + (impact / 200)) // Less insulin needed
                
                patterns.append(RecurringPattern(
                    patternType: .timeOfDay,
                    timing: PatternTiming(hourRange: hour...hour),
                    confidence: lowRatio,
                    occurrenceCount: lowCount,
                    averageGlucoseImpact: impact,
                    suggestedSettings: OverrideSettings(
                        basalMultiplier: suggestedBasal,
                        isfMultiplier: 1.0 / suggestedBasal
                    ),
                    description: "Low glucose often around \(formatHour(hour))"
                ))
            }
        }
        
        return patterns
    }
    
    private func detectDayOfWeekPatterns() -> [RecurringPattern] {
        var patterns: [RecurringPattern] = []
        
        // Group readings by day of week
        var dailyReadings: [Int: [PatternGlucoseReading]] = [:]
        for reading in glucoseHistory {
            let dow = Calendar.current.component(.weekday, from: reading.timestamp)
            dailyReadings[dow, default: []].append(reading)
        }
        
        // Find days with different patterns
        let overallAvg = glucoseHistory.isEmpty ? 120.0 :
            glucoseHistory.map(\.value).reduce(0, +) / Double(glucoseHistory.count)
        
        for (dow, readings) in dailyReadings where readings.count >= minOccurrences * 10 {
            let dayAvg = readings.map(\.value).reduce(0, +) / Double(readings.count)
            let deviation = dayAvg - overallAvg
            
            // Significant deviation from average
            if abs(deviation) > 15 {
                let confidence = min(1.0, abs(deviation) / 30)
                let suggestedBasal = 1.0 + (deviation / 100)
                
                patterns.append(RecurringPattern(
                    patternType: .dayOfWeek,
                    timing: PatternTiming(daysOfWeek: [dow]),
                    confidence: confidence,
                    occurrenceCount: readings.count / 24, // Approximate day count
                    averageGlucoseImpact: deviation,
                    suggestedSettings: OverrideSettings(
                        basalMultiplier: suggestedBasal
                    ),
                    description: "\(dayName(dow)) tends to run \(deviation > 0 ? "higher" : "lower")"
                ))
            }
        }
        
        return patterns
    }
    
    private func detectDawnPhenomenon() -> RecurringPattern? {
        // Dawn phenomenon: glucose rises between 3am-8am
        let dawnReadings = glucoseHistory.filter { reading in
            let hour = Calendar.current.component(.hour, from: reading.timestamp)
            return hour >= 3 && hour <= 8
        }
        
        guard dawnReadings.count >= minOccurrences * 5 else { return nil }
        
        // Group by day and check for rising pattern
        var risingDays = 0
        var totalDays = 0
        
        let groupedByDay = Dictionary(grouping: dawnReadings) { reading in
            Calendar.current.startOfDay(for: reading.timestamp)
        }
        
        for (_, dayReadings) in groupedByDay {
            let sorted = dayReadings.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 3 else { continue }
            
            totalDays += 1
            let first = sorted.prefix(sorted.count / 3).map(\.value).reduce(0, +) / Double(sorted.count / 3)
            let last = sorted.suffix(sorted.count / 3).map(\.value).reduce(0, +) / Double(sorted.count / 3)
            
            if last - first > 20 {
                risingDays += 1
            }
        }
        
        guard totalDays >= minOccurrences else { return nil }
        
        let confidence = Double(risingDays) / Double(totalDays)
        guard confidence >= minConfidence else { return nil }
        
        return RecurringPattern(
            patternType: .dawn,
            timing: PatternTiming(hourRange: 3...8),
            confidence: confidence,
            occurrenceCount: risingDays,
            averageGlucoseImpact: 30, // Typical rise
            suggestedSettings: OverrideSettings(
                basalMultiplier: 1.3, // Increase basal for dawn
                scheduledDuration: 5 * 3600 // 5 hours
            ),
            description: "Dawn phenomenon: glucose rises 3am-8am"
        )
    }
    
    private func trimOldReadings() {
        let cutoff = Date().addingTimeInterval(-Double(analysisWindowDays) * 86400)
        glucoseHistory.removeAll { $0.timestamp < cutoff }
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour == 12 { return "12pm" }
        if hour < 12 { return "\(hour)am" }
        return "\(hour - 12)pm"
    }
    
    private func dayName(_ dow: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return dow >= 1 && dow <= 7 ? names[dow - 1] : "Unknown"
    }
}

/// A glucose reading for pattern analysis
public struct PatternGlucoseReading: Sendable, Codable {
    public let value: Double
    public let timestamp: Date
    public let trend: Double?
    
    public init(value: Double, timestamp: Date, trend: Double? = nil) {
        self.value = value
        self.timestamp = timestamp
        self.trend = trend
    }
}

// MARK: - Override Suggestion Engine (ALG-LEARN-031)

/// Generates override suggestions from detected patterns
public actor OverrideSuggestionEngine {
    
    /// Pattern detector
    private let patternDetector: PatternDetector
    
    /// Minimum confidence to suggest override creation
    public let minConfidenceForSuggestion: Double
    
    /// Minimum occurrences to suggest override
    public let minOccurrencesForSuggestion: Int
    
    /// Generated suggestions
    private var suggestions: [OverrideSuggestion] = []
    
    /// Dismissed suggestion IDs
    private var dismissedIds: Set<UUID> = []
    
    public init(
        patternDetector: PatternDetector,
        minConfidenceForSuggestion: Double = 0.7,
        minOccurrencesForSuggestion: Int = 5
    ) {
        self.patternDetector = patternDetector
        self.minConfidenceForSuggestion = minConfidenceForSuggestion
        self.minOccurrencesForSuggestion = minOccurrencesForSuggestion
    }
    
    /// Generate suggestions from detected patterns
    public func generateSuggestions() async -> [OverrideSuggestion] {
        let patterns = await patternDetector.analyzePatterns()
        
        suggestions = patterns
            .filter { $0.confidence >= minConfidenceForSuggestion }
            .filter { $0.occurrenceCount >= minOccurrencesForSuggestion }
            .filter { !dismissedIds.contains($0.id) }
            .map { pattern in
                OverrideSuggestion(
                    id: UUID(),
                    patternId: pattern.id,
                    suggestedName: generateOverrideName(for: pattern),
                    suggestedSettings: pattern.suggestedSettings,
                    timing: pattern.timing,
                    rationale: generateRationale(for: pattern),
                    confidence: pattern.confidence,
                    occurrenceCount: pattern.occurrenceCount,
                    createdAt: Date()
                )
            }
        
        return suggestions
    }
    
    /// Get pending suggestions
    public func pendingSuggestions() -> [OverrideSuggestion] {
        suggestions.filter { !dismissedIds.contains($0.patternId) }
    }
    
    /// Accept a suggestion (user wants to create the override)
    public func acceptSuggestion(_ suggestion: OverrideSuggestion) -> UserOverrideDefinition {
        UserOverrideDefinition(
            id: UUID().uuidString,
            name: suggestion.suggestedName,
            settings: suggestion.suggestedSettings,
            isSystemDefault: false,
            category: categorize(suggestion.timing)
        )
    }
    
    /// Dismiss a suggestion (user doesn't want it)
    public func dismissSuggestion(_ suggestionId: UUID, patternId: UUID) {
        dismissedIds.insert(patternId)
        suggestions.removeAll { $0.id == suggestionId }
    }
    
    private func generateOverrideName(for pattern: RecurringPattern) -> String {
        switch pattern.patternType {
        case .dawn:
            return "Dawn Correction"
        case .timeOfDay:
            if let hour = pattern.timing.hourRange?.lowerBound {
                let period = hour < 12 ? "Morning" : (hour < 17 ? "Afternoon" : "Evening")
                return "\(period) Adjustment"
            }
            return "Time-Based Adjustment"
        case .dayOfWeek:
            if let days = pattern.timing.daysOfWeek, days.count == 1, let day = days.first {
                return "\(dayName(day)) Pattern"
            }
            return "Weekly Pattern"
        case .exercise:
            return "Exercise Mode"
        case .postMeal:
            return "Post-Meal Boost"
        case .preMeal:
            return "Pre-Meal Prep"
        case .sleep:
            return "Sleep Mode"
        case .stress:
            return "Stress Response"
        case .menstrualCycle:
            return "Cycle Adjustment"
        }
    }
    
    private func generateRationale(for pattern: RecurringPattern) -> String {
        let timing = pattern.timing.displayDescription
        let impact = pattern.averageGlucoseImpact > 0 ? "running high" : "going low"
        let percent = abs(Int((1 - pattern.suggestedSettings.basalMultiplier) * 100))
        let direction = pattern.suggestedSettings.basalMultiplier > 1 ? "increase" : "decrease"
        
        return "Over the past 2 weeks, you've been \(impact) \(timing) about \(pattern.occurrenceCount) times. " +
               "A \(percent)% \(direction) in basal could help."
    }
    
    private func categorize(_ timing: PatternTiming) -> OverrideCategory {
        if timing.hourRange?.contains(6) == true || timing.hourRange?.contains(7) == true {
            return .custom // Dawn/morning
        }
        return .custom
    }
    
    private func dayName(_ dow: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return dow >= 1 && dow <= 7 ? names[dow - 1] : "Unknown"
    }
}

/// A suggestion to create a new override
public struct OverrideSuggestion: Sendable, Identifiable {
    public let id: UUID
    public let patternId: UUID
    public let suggestedName: String
    public let suggestedSettings: OverrideSettings
    public let timing: PatternTiming
    public let rationale: String
    public let confidence: Double
    public let occurrenceCount: Int
    public let createdAt: Date
}

// MARK: - Override History Importer (ALG-LEARN-032)

/// Imports override history from Loop/Trio for training bootstrap
public actor OverrideHistoryImporter {
    
    /// Import source type
    public enum ImportSource: String, Sendable {
        case loop = "loop"
        case trio = "trio"
        case nightscout = "nightscout"
        case healthKit = "healthKit"
    }
    
    /// Imported sessions
    private var importedSessions: [OverrideSession] = []
    
    /// Import statistics
    private var importStats: ImportStatistics?
    
    public init() {}
    
    /// Import from Nightscout treatment records
    public func importFromNightscout(
        overrideTreatments: [NightscoutOverrideTreatment],
        glucoseData: [PatternGlucoseReading]
    ) async -> ImportResult {
        var sessions: [OverrideSession] = []
        var errors: [ImportError] = []
        
        for treatment in overrideTreatments {
            do {
                let session = try createSession(from: treatment, glucoseData: glucoseData)
                sessions.append(session)
            } catch let error as ImportError {
                errors.append(error)
            } catch {
                errors.append(.unknown(error.localizedDescription))
            }
        }
        
        importedSessions.append(contentsOf: sessions)
        
        let stats = ImportStatistics(
            source: .nightscout,
            totalRecords: overrideTreatments.count,
            successfulImports: sessions.count,
            failedImports: errors.count,
            importedAt: Date()
        )
        importStats = stats
        
        return ImportResult(
            sessions: sessions,
            errors: errors,
            statistics: stats
        )
    }
    
    /// Import from Loop Health records
    public func importFromLoop(
        overrideEvents: [LoopOverrideEvent],
        glucoseData: [PatternGlucoseReading]
    ) async -> ImportResult {
        var sessions: [OverrideSession] = []
        var errors: [ImportError] = []
        
        for event in overrideEvents {
            do {
                let session = try createSession(from: event, glucoseData: glucoseData)
                sessions.append(session)
            } catch let error as ImportError {
                errors.append(error)
            } catch {
                errors.append(.unknown(error.localizedDescription))
            }
        }
        
        importedSessions.append(contentsOf: sessions)
        
        let stats = ImportStatistics(
            source: .loop,
            totalRecords: overrideEvents.count,
            successfulImports: sessions.count,
            failedImports: errors.count,
            importedAt: Date()
        )
        importStats = stats
        
        return ImportResult(
            sessions: sessions,
            errors: errors,
            statistics: stats
        )
    }
    
    /// Get imported sessions
    public func sessions() -> [OverrideSession] {
        importedSessions
    }
    
    /// Get import statistics
    public func statistics() -> ImportStatistics? {
        importStats
    }
    
    /// Clear imported data
    public func clear() {
        importedSessions.removeAll()
        importStats = nil
    }
    
    private func createSession(
        from treatment: NightscoutOverrideTreatment,
        glucoseData: [PatternGlucoseReading]
    ) throws -> OverrideSession {
        guard let endDate = treatment.endDate else {
            throw ImportError.incompleteData("Missing end date")
        }
        
        let preGlucose = findClosestGlucose(to: treatment.startDate, in: glucoseData)
        let postGlucose = findClosestGlucose(to: endDate, in: glucoseData)
        
        guard let pre = preGlucose else {
            throw ImportError.missingGlucoseData("No glucose data near start")
        }
        
        let settings = OverrideSettings(
            basalMultiplier: treatment.basalMultiplier ?? 1.0,
            isfMultiplier: treatment.isfMultiplier ?? 1.0,
            crMultiplier: 1.0,
            targetGlucose: treatment.targetRange?.lowerBound,
            scheduledDuration: endDate.timeIntervalSince(treatment.startDate)
        )
        
        var session = OverrideSession(
            overrideId: treatment.overrideName ?? "imported",
            overrideName: treatment.overrideName ?? "Imported Override",
            activatedAt: treatment.startDate,
            settings: settings,
            preSnapshot: pre,
            context: OverrideContext(activationSource: .manual)
        )
        
        session.deactivatedAt = endDate
        session.postSnapshot = postGlucose
        
        // Calculate outcome if we have post glucose
        if let post = postGlucose {
            session.outcome = calculateOutcome(pre: pre, post: post)
        }
        
        return session
    }
    
    private func createSession(
        from event: LoopOverrideEvent,
        glucoseData: [PatternGlucoseReading]
    ) throws -> OverrideSession {
        guard let endDate = event.endDate else {
            throw ImportError.incompleteData("Missing end date")
        }
        
        let preGlucose = findClosestGlucose(to: event.startDate, in: glucoseData)
        let postGlucose = findClosestGlucose(to: endDate, in: glucoseData)
        
        guard let pre = preGlucose else {
            throw ImportError.missingGlucoseData("No glucose data near start")
        }
        
        let settings = OverrideSettings(
            basalMultiplier: event.basalRateMultiplier,
            isfMultiplier: event.insulinSensitivityMultiplier,
            crMultiplier: 1.0,
            targetGlucose: event.targetRangeLow,
            scheduledDuration: event.duration
        )
        
        var session = OverrideSession(
            overrideId: event.presetName ?? "imported",
            overrideName: event.presetName ?? "Imported Override",
            activatedAt: event.startDate,
            settings: settings,
            preSnapshot: pre,
            context: OverrideContext(activationSource: .manual)
        )
        
        session.deactivatedAt = endDate
        session.postSnapshot = postGlucose
        
        if let post = postGlucose {
            session.outcome = calculateOutcome(pre: pre, post: post)
        }
        
        return session
    }
    
    private func findClosestGlucose(to date: Date, in readings: [PatternGlucoseReading]) -> GlucoseSnapshot? {
        let window: TimeInterval = 30 * 60 // 30 minutes
        let nearbyReadings = readings.filter {
            abs($0.timestamp.timeIntervalSince(date)) <= window
        }
        
        guard let closest = nearbyReadings.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else {
            return nil
        }
        
        // Simple snapshot - in real impl would calculate TIR from window
        return GlucoseSnapshot(
            glucose: closest.value,
            trend: closest.trend,
            timeInRange: closest.value >= 70 && closest.value <= 180 ? 1.0 : 0.0,
            timestamp: closest.timestamp
        )
    }
    
    private func calculateOutcome(pre: GlucoseSnapshot, post: GlucoseSnapshot) -> OverrideOutcome {
        let tirDelta = post.timeInRange - pre.timeInRange
        let avgGlucose = (pre.glucose + post.glucose) / 2
        let successScore = post.timeInRange
        
        return OverrideOutcome(
            timeInRange: post.timeInRange,
            timeInRangeDelta: tirDelta,
            hypoEvents: post.hypoEvents,
            hyperEvents: post.hyperEvents,
            averageGlucose: avgGlucose,
            variability: post.coefficientOfVariation,
            successScore: successScore
        )
    }
}

/// Nightscout override treatment record
public struct NightscoutOverrideTreatment: Sendable {
    public let startDate: Date
    public let endDate: Date?
    public let overrideName: String?
    public let basalMultiplier: Double?
    public let isfMultiplier: Double?
    public let targetRange: ClosedRange<Double>?
    
    public init(
        startDate: Date,
        endDate: Date? = nil,
        overrideName: String? = nil,
        basalMultiplier: Double? = nil,
        isfMultiplier: Double? = nil,
        targetRange: ClosedRange<Double>? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.overrideName = overrideName
        self.basalMultiplier = basalMultiplier
        self.isfMultiplier = isfMultiplier
        self.targetRange = targetRange
    }
}

/// Loop override event
public struct LoopOverrideEvent: Sendable {
    public let startDate: Date
    public let endDate: Date?
    public let duration: TimeInterval
    public let presetName: String?
    public let basalRateMultiplier: Double
    public let insulinSensitivityMultiplier: Double
    public let targetRangeLow: Double?
    public let targetRangeHigh: Double?
    
    public init(
        startDate: Date,
        endDate: Date? = nil,
        duration: TimeInterval,
        presetName: String? = nil,
        basalRateMultiplier: Double = 1.0,
        insulinSensitivityMultiplier: Double = 1.0,
        targetRangeLow: Double? = nil,
        targetRangeHigh: Double? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.presetName = presetName
        self.basalRateMultiplier = basalRateMultiplier
        self.insulinSensitivityMultiplier = insulinSensitivityMultiplier
        self.targetRangeLow = targetRangeLow
        self.targetRangeHigh = targetRangeHigh
    }
}

/// Import result
public struct ImportResult: Sendable {
    public let sessions: [OverrideSession]
    public let errors: [ImportError]
    public let statistics: ImportStatistics
}

/// Import error types
public enum ImportError: Error, Sendable {
    case incompleteData(String)
    case missingGlucoseData(String)
    case invalidFormat(String)
    case unknown(String)
}

/// Import statistics
public struct ImportStatistics: Sendable {
    public let source: OverrideHistoryImporter.ImportSource
    public let totalRecords: Int
    public let successfulImports: Int
    public let failedImports: Int
    public let importedAt: Date
    
    public var successRate: Double {
        totalRecords > 0 ? Double(successfulImports) / Double(totalRecords) : 0
    }
}

// MARK: - Community Template Sharing (ALG-LEARN-033 - Stub)

/// Template for community sharing (stub implementation)
public struct CommunityOverrideTemplate: Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let category: OverrideCategory
    public let settings: OverrideSettings
    public let description: String
    public let tags: [String]
    public let usageCount: Int
    public let averageRating: Double
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        category: OverrideCategory,
        settings: OverrideSettings,
        description: String,
        tags: [String] = [],
        usageCount: Int = 0,
        averageRating: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.settings = settings
        self.description = description
        self.tags = tags
        self.usageCount = usageCount
        self.averageRating = averageRating
        self.createdAt = createdAt
    }
}

/// Community template manager (stub - full implementation deferred)
public actor CommunityTemplateManager {
    
    /// Whether sharing is enabled
    public private(set) var sharingEnabled: Bool = false
    
    /// Local templates (not yet synced)
    private var localTemplates: [CommunityOverrideTemplate] = []
    
    public init() {}
    
    /// Enable community sharing (requires user consent)
    public func enableSharing(userConsent: Bool) {
        sharingEnabled = userConsent
    }
    
    /// Create a template from user's override (anonymized)
    public func createTemplate(
        from definition: UserOverrideDefinition,
        description: String,
        tags: [String]
    ) -> CommunityOverrideTemplate? {
        guard sharingEnabled else { return nil }
        
        let template = CommunityOverrideTemplate(
            name: definition.name,
            category: definition.category,
            settings: definition.settings,
            description: description,
            tags: tags
        )
        
        localTemplates.append(template)
        return template
    }
    
    /// Get local templates pending upload
    public func pendingTemplates() -> [CommunityOverrideTemplate] {
        localTemplates
    }
    
    /// Search community templates (stub - would query remote)
    public func searchTemplates(query: String, category: OverrideCategory?) async -> [CommunityOverrideTemplate] {
        // Stub: would query community backend
        return []
    }
}
