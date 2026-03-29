// SPDX-License-Identifier: AGPL-3.0-or-later
//
// UserHunchSystem.swift
// T1PalAlgorithm
//
// User Hunch → Custom Agent Pipeline
// Backlog: ALG-HUNCH-001..004
// Trace: PRD-028 Phase 4 (User Hunches)

import Foundation

// MARK: - Hunch Input Types (ALG-HUNCH-001)

/// A user-expressed belief about their diabetes pattern
public struct HunchInput: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    
    /// Natural language description from user
    /// e.g., "I always go low after tennis", "Coffee makes me spike"
    public let rawInput: String
    
    /// Category extracted or specified
    public let category: OverrideCategory
    
    /// The belief being expressed
    public let belief: HunchBelief
    
    /// When the hunch was created
    public let createdAt: Date
    
    /// User confidence in this hunch (0-1)
    public let userConfidence: Double
    
    /// Optional time context
    public let timeContext: HunchTimeContext?
    
    public init(
        id: UUID = UUID(),
        rawInput: String,
        category: OverrideCategory,
        belief: HunchBelief,
        createdAt: Date = Date(),
        userConfidence: Double = 0.8,
        timeContext: HunchTimeContext? = nil
    ) {
        self.id = id
        self.rawInput = rawInput
        self.category = category
        self.belief = belief
        self.createdAt = createdAt
        self.userConfidence = min(max(userConfidence, 0), 1)
        self.timeContext = timeContext
    }
}

/// The core belief being expressed
public enum HunchBelief: Codable, Sendable, Equatable {
    /// Activity causes lows (e.g., "Tennis makes me go low")
    case activityCausesLow(activity: String, severity: HunchSeverity)
    
    /// Activity causes highs (e.g., "Weightlifting spikes me")
    case activityCausesHigh(activity: String, severity: HunchSeverity)
    
    /// Food/drink effect (e.g., "Coffee makes me spike")
    case foodEffect(item: String, direction: GlucoseDirection, severity: HunchSeverity)
    
    /// Time-of-day pattern (e.g., "I'm always high in the morning")
    case timePattern(period: TimePeriod, direction: GlucoseDirection)
    
    /// Stress/emotional effect (e.g., "Stress makes me high")
    case stressEffect(direction: GlucoseDirection, severity: HunchSeverity)
    
    /// Medication interaction (e.g., "Prednisone makes me resistant")
    case medicationEffect(medication: String, effect: MedicationEffect)
    
    /// Sleep pattern (e.g., "I go low if I sleep in")
    case sleepPattern(condition: SleepCondition, direction: GlucoseDirection)
    
    /// Menstrual cycle (e.g., "I need more insulin before my period")
    case menstrualCycle(phase: MenstrualPhase, effect: InsulinSensitivityChange)
    
    /// Weather/temperature (e.g., "Hot weather makes me more sensitive")
    case weatherEffect(condition: WeatherCondition, effect: InsulinSensitivityChange)
    
    /// Custom belief that doesn't fit predefined categories
    case custom(description: String, expectedEffect: ExpectedEffect)
}

/// Severity of the effect
public enum HunchSeverity: String, Codable, Sendable {
    case mild = "mild"           // Minor adjustment needed
    case moderate = "moderate"    // Standard adjustment
    case severe = "severe"        // Major adjustment needed
    
    /// Suggested multiplier for effect magnitude
    public var effectMultiplier: Double {
        switch self {
        case .mild: return 0.10      // ±10%
        case .moderate: return 0.20  // ±20%
        case .severe: return 0.35    // ±35%
        }
    }
}

/// Direction of glucose movement
public enum GlucoseDirection: String, Codable, Sendable {
    case rising = "rising"
    case falling = "falling"
    case stable = "stable"
}

/// Time periods for patterns
public enum TimePeriod: String, Codable, Sendable {
    case earlyMorning = "early_morning"  // 4-7 AM
    case morning = "morning"             // 7-11 AM
    case midday = "midday"               // 11 AM - 2 PM
    case afternoon = "afternoon"         // 2-6 PM
    case evening = "evening"             // 6-9 PM
    case night = "night"                 // 9 PM - 12 AM
    case lateNight = "late_night"        // 12-4 AM
    
    /// Hour range for this period
    public var hourRange: ClosedRange<Int> {
        switch self {
        case .earlyMorning: return 4...6
        case .morning: return 7...10
        case .midday: return 11...13
        case .afternoon: return 14...17
        case .evening: return 18...20
        case .night: return 21...23
        case .lateNight: return 0...3
        }
    }
}

/// Medication effects on insulin sensitivity
public enum MedicationEffect: String, Codable, Sendable {
    case increasedResistance = "increased_resistance"  // Need more insulin
    case increasedSensitivity = "increased_sensitivity"  // Need less insulin
    case delayedAbsorption = "delayed_absorption"
    case unpredictable = "unpredictable"
}

/// Sleep conditions that affect glucose
public enum SleepCondition: String, Codable, Sendable {
    case sleepingIn = "sleeping_in"
    case poorSleep = "poor_sleep"
    case jetLag = "jet_lag"
    case nightShift = "night_shift"
    case nap = "nap"
}

/// Menstrual cycle phases
public enum MenstrualPhase: String, Codable, Sendable {
    case follicular = "follicular"      // Day 1-14
    case ovulation = "ovulation"        // Day 14
    case luteal = "luteal"              // Day 15-28
    case premenstrual = "premenstrual"  // Day 24-28
}

/// Insulin sensitivity changes
public enum InsulinSensitivityChange: String, Codable, Sendable {
    case moreResistant = "more_resistant"   // Need more insulin
    case moreSensitive = "more_sensitive"   // Need less insulin
}

/// Weather conditions
public enum WeatherCondition: String, Codable, Sendable {
    case hot = "hot"
    case cold = "cold"
    case humid = "humid"
    case altitudeChange = "altitude_change"
}

/// Expected effect from custom hunch
public struct ExpectedEffect: Codable, Sendable, Equatable {
    /// Basal rate multiplier (e.g., 0.8 for 80%, 1.2 for 120%)
    public let basalMultiplier: Double?
    
    /// ISF multiplier
    public let isfMultiplier: Double?
    
    /// Target glucose adjustment (mg/dL)
    public let targetAdjustment: Double?
    
    /// Duration in minutes
    public let durationMinutes: Int
    
    public init(
        basalMultiplier: Double? = nil,
        isfMultiplier: Double? = nil,
        targetAdjustment: Double? = nil,
        durationMinutes: Int = 120
    ) {
        self.basalMultiplier = basalMultiplier
        self.isfMultiplier = isfMultiplier
        self.targetAdjustment = targetAdjustment
        self.durationMinutes = durationMinutes
    }
}

/// Time context for when hunch applies
public struct HunchTimeContext: Codable, Sendable, Equatable {
    /// Specific hours when this applies (nil = any time)
    public let hourRange: ClosedRange<Int>?
    
    /// Days of week (nil = any day)
    public let daysOfWeek: Set<Int>?  // 1 = Sunday, 7 = Saturday
    
    /// Duration before/after trigger event (minutes)
    public let offsetMinutes: Int
    
    /// Duration of effect (minutes)
    public let effectDurationMinutes: Int
    
    public init(
        hourRange: ClosedRange<Int>? = nil,
        daysOfWeek: Set<Int>? = nil,
        offsetMinutes: Int = 0,
        effectDurationMinutes: Int = 120
    ) {
        self.hourRange = hourRange
        self.daysOfWeek = daysOfWeek
        self.offsetMinutes = offsetMinutes
        self.effectDurationMinutes = effectDurationMinutes
    }
}

// MARK: - Hunch Parser (ALG-HUNCH-002)

/// Parses natural language hunches into structured HunchInput
public struct HunchParser: Sendable {
    
    /// Keyword patterns for detection
    private static let lowKeywords = ["low", "hypo", "drop", "crash", "falling", "sensitive"]
    private static let highKeywords = ["high", "spike", "rise", "resistant", "climbing"]
    private static let activityKeywords = ["exercise", "workout", "tennis", "running", "swimming", "gym", "walk", "bike", "cycling", "sport", "yoga", "weights", "lifting"]
    private static let foodKeywords = ["eat", "food", "meal", "coffee", "caffeine", "pizza", "pasta", "rice", "carbs", "fat", "protein", "alcohol", "beer", "wine"]
    private static let timeKeywords = ["morning", "afternoon", "evening", "night", "dawn", "breakfast", "lunch", "dinner", "wake", "sleep"]
    private static let stressKeywords = ["stress", "anxious", "nervous", "worried", "exam", "meeting", "deadline"]
    private static let medicationKeywords = ["prednisone", "steroid", "medication", "medicine", "pill", "injection"]
    private static let sleepKeywords = ["sleep", "tired", "nap", "jet lag", "night shift"]
    private static let menstrualKeywords = ["period", "menstrual", "cycle", "ovulation", "pms"]
    private static let weatherKeywords = ["hot", "cold", "weather", "temperature", "humidity", "altitude"]
    
    public init() {}
    
    /// Parse natural language input into structured hunch
    public func parse(_ input: String) -> ParsedHunch {
        let lowercased = input.lowercased()
        
        // Detect direction
        let direction = detectDirection(lowercased)
        
        // Detect category and extract details
        if let activityMatch = detectActivity(lowercased) {
            let severity = detectSeverity(lowercased)
            let belief: HunchBelief = direction == .falling 
                ? .activityCausesLow(activity: activityMatch, severity: severity)
                : .activityCausesHigh(activity: activityMatch, severity: severity)
            return ParsedHunch(
                success: true,
                category: .activity,
                belief: belief,
                confidence: 0.85,
                extractedEntities: ["activity": activityMatch]
            )
        }
        
        if let foodMatch = detectFood(lowercased) {
            let severity = detectSeverity(lowercased)
            return ParsedHunch(
                success: true,
                category: .meal,
                belief: .foodEffect(item: foodMatch, direction: direction, severity: severity),
                confidence: 0.80,
                extractedEntities: ["food": foodMatch]
            )
        }
        
        // Check sleep conditions BEFORE time patterns (more specific)
        if let sleepCondition = detectSleepCondition(lowercased) {
            return ParsedHunch(
                success: true,
                category: .sleep,
                belief: .sleepPattern(condition: sleepCondition, direction: direction),
                confidence: 0.75,
                extractedEntities: ["sleep_condition": sleepCondition.rawValue]
            )
        }
        
        if let timeMatch = detectTimePeriod(lowercased) {
            return ParsedHunch(
                success: true,
                category: .sleep,
                belief: .timePattern(period: timeMatch, direction: direction),
                confidence: 0.75,
                extractedEntities: ["time_period": timeMatch.rawValue]
            )
        }
        
        if containsKeyword(lowercased, in: Self.stressKeywords) {
            let severity = detectSeverity(lowercased)
            return ParsedHunch(
                success: true,
                category: .health,
                belief: .stressEffect(direction: direction, severity: severity),
                confidence: 0.70,
                extractedEntities: [:]
            )
        }
        
        if let medication = detectMedication(lowercased) {
            let effect: MedicationEffect = direction == .rising ? .increasedResistance : .increasedSensitivity
            return ParsedHunch(
                success: true,
                category: .health,
                belief: .medicationEffect(medication: medication, effect: effect),
                confidence: 0.75,
                extractedEntities: ["medication": medication]
            )
        }
        
        if let menstrualPhase = detectMenstrualPhase(lowercased) {
            let effect: InsulinSensitivityChange = direction == .rising ? .moreResistant : .moreSensitive
            return ParsedHunch(
                success: true,
                category: .health,
                belief: .menstrualCycle(phase: menstrualPhase, effect: effect),
                confidence: 0.75,
                extractedEntities: ["menstrual_phase": menstrualPhase.rawValue]
            )
        }
        
        if let weather = detectWeather(lowercased) {
            let effect: InsulinSensitivityChange = direction == .rising ? .moreResistant : .moreSensitive
            return ParsedHunch(
                success: true,
                category: .custom,
                belief: .weatherEffect(condition: weather, effect: effect),
                confidence: 0.65,
                extractedEntities: ["weather": weather.rawValue]
            )
        }
        
        // Fall back to custom belief
        return ParsedHunch(
            success: false,
            category: .custom,
            belief: .custom(
                description: input,
                expectedEffect: ExpectedEffect(
                    basalMultiplier: direction == .rising ? 1.2 : 0.8,
                    durationMinutes: 120
                )
            ),
            confidence: 0.5,
            extractedEntities: [:]
        )
    }
    
    private func detectDirection(_ input: String) -> GlucoseDirection {
        let lowCount = Self.lowKeywords.filter { input.contains($0) }.count
        let highCount = Self.highKeywords.filter { input.contains($0) }.count
        
        if lowCount > highCount { return .falling }
        if highCount > lowCount { return .rising }
        return .stable
    }
    
    private func detectSeverity(_ input: String) -> HunchSeverity {
        if input.contains("always") || input.contains("severe") || input.contains("crash") || input.contains("really") {
            return .severe
        }
        if input.contains("sometimes") || input.contains("mild") || input.contains("slight") {
            return .mild
        }
        return .moderate
    }
    
    private func detectActivity(_ input: String) -> String? {
        for keyword in Self.activityKeywords {
            if input.contains(keyword) {
                return keyword.capitalized
            }
        }
        return nil
    }
    
    private func detectFood(_ input: String) -> String? {
        for keyword in Self.foodKeywords where keyword != "eat" && keyword != "food" && keyword != "meal" {
            if input.contains(keyword) {
                return keyword.capitalized
            }
        }
        return nil
    }
    
    private func detectTimePeriod(_ input: String) -> TimePeriod? {
        if input.contains("dawn") || input.contains("early morning") { return .earlyMorning }
        if input.contains("morning") || input.contains("wake") || input.contains("breakfast") { return .morning }
        if input.contains("lunch") || input.contains("midday") || input.contains("noon") { return .midday }
        if input.contains("afternoon") { return .afternoon }
        if input.contains("evening") || input.contains("dinner") { return .evening }
        if input.contains("night") || input.contains("sleep") { return .night }
        return nil
    }
    
    private func detectMedication(_ input: String) -> String? {
        for keyword in Self.medicationKeywords {
            if input.contains(keyword) && keyword != "medication" && keyword != "medicine" {
                return keyword.capitalized
            }
        }
        if containsKeyword(input, in: ["medication", "medicine"]) {
            return "Medication"
        }
        return nil
    }
    
    private func detectSleepCondition(_ input: String) -> SleepCondition? {
        if input.contains("sleep in") || input.contains("sleeping in") || input.contains("slept in") { return .sleepingIn }
        if input.contains("poor sleep") || input.contains("didn't sleep") || input.contains("tired") { return .poorSleep }
        if input.contains("jet lag") { return .jetLag }
        if input.contains("night shift") { return .nightShift }
        if input.contains("nap") { return .nap }
        return nil
    }
    
    private func detectMenstrualPhase(_ input: String) -> MenstrualPhase? {
        // Check for premenstrual patterns first (most specific)
        if input.contains("pms") || input.contains("premenstrual") { return .premenstrual }
        if input.contains("before") && input.contains("period") { return .premenstrual }
        if input.contains("luteal") || input.contains("after ovulation") { return .luteal }
        if input.contains("ovulation") || input.contains("ovulating") { return .ovulation }
        if input.contains("period") || input.contains("menstrual") { return .follicular }
        return nil
    }
    
    private func detectWeather(_ input: String) -> WeatherCondition? {
        if input.contains("hot") || input.contains("heat") || input.contains("summer") { return .hot }
        if input.contains("cold") || input.contains("winter") { return .cold }
        if input.contains("humid") { return .humid }
        if input.contains("altitude") || input.contains("mountain") { return .altitudeChange }
        return nil
    }
    
    private func containsKeyword(_ input: String, in keywords: [String]) -> Bool {
        keywords.contains { input.contains($0) }
    }
}

/// Result of parsing a hunch
public struct ParsedHunch: Sendable {
    /// Whether parsing was successful
    public let success: Bool
    
    /// Detected category
    public let category: OverrideCategory
    
    /// Structured belief
    public let belief: HunchBelief
    
    /// Parser confidence (0-1)
    public let confidence: Double
    
    /// Entities extracted from input
    public let extractedEntities: [String: String]
}

// MARK: - Hunch Validator (ALG-HUNCH-003)

/// Validates hunches against historical glucose data
public actor HunchValidator {
    
    /// Minimum data points required for validation
    private let minDataPoints: Int
    
    /// Correlation threshold for validation
    private let correlationThreshold: Double
    
    public init(minDataPoints: Int = 10, correlationThreshold: Double = 0.6) {
        self.minDataPoints = minDataPoints
        self.correlationThreshold = correlationThreshold
    }
    
    /// Validate a hunch against historical data
    public func validate(
        hunch: HunchInput,
        glucoseHistory: [GlucosePoint],
        eventHistory: [HunchValidationEvent]
    ) -> HunchValidationResult {
        // Find events matching the hunch
        let relevantEvents = eventHistory.filter { event in
            matchesHunch(event: event, belief: hunch.belief)
        }
        
        guard relevantEvents.count >= minDataPoints else {
            return HunchValidationResult(
                status: .insufficientData,
                supportingEvents: relevantEvents.count,
                contradictingEvents: 0,
                correlation: nil,
                confidence: 0,
                message: "Need \(minDataPoints - relevantEvents.count) more events to validate"
            )
        }
        
        // Analyze glucose response after each event
        var supportingCount = 0
        var contradictingCount = 0
        var correlations: [Double] = []
        
        for event in relevantEvents {
            let analysis = analyzeGlucoseResponse(
                event: event,
                belief: hunch.belief,
                glucoseHistory: glucoseHistory
            )
            
            if analysis.supports {
                supportingCount += 1
            } else if analysis.contradicts {
                contradictingCount += 1
            }
            
            if let correlation = analysis.correlation {
                correlations.append(correlation)
            }
        }
        
        let avgCorrelation = correlations.isEmpty ? nil : correlations.reduce(0, +) / Double(correlations.count)
        let supportRatio = Double(supportingCount) / Double(relevantEvents.count)
        
        // Determine validation status
        let status: HunchValidationStatus
        let confidence: Double
        
        if let corr = avgCorrelation, corr >= correlationThreshold && supportRatio >= 0.7 {
            status = .validated
            confidence = min(corr, supportRatio)
        } else if supportRatio >= 0.5 {
            status = .partiallyValidated
            confidence = supportRatio * 0.8
        } else if supportRatio < 0.3 {
            status = .contradicted
            confidence = 1.0 - supportRatio
        } else {
            status = .inconclusive
            confidence = 0.5
        }
        
        return HunchValidationResult(
            status: status,
            supportingEvents: supportingCount,
            contradictingEvents: contradictingCount,
            correlation: avgCorrelation,
            confidence: confidence,
            message: generateValidationMessage(status: status, supportRatio: supportRatio, correlation: avgCorrelation)
        )
    }
    
    private func matchesHunch(event: HunchValidationEvent, belief: HunchBelief) -> Bool {
        switch (belief, event.eventType) {
        case (.activityCausesLow(let activity, _), .activity(let name)):
            return name.lowercased() == activity.lowercased()
        case (.activityCausesHigh(let activity, _), .activity(let name)):
            return name.lowercased() == activity.lowercased()
        case (.foodEffect(let item, _, _), .food(let name)):
            return name.lowercased() == item.lowercased()
        case (.timePattern(let period, _), .timeOfDay(let hour)):
            return period.hourRange.contains(hour)
        case (.stressEffect, .stress):
            return true
        case (.medicationEffect(let med, _), .medication(let name)):
            return name.lowercased() == med.lowercased()
        case (.sleepPattern(let condition, _), .sleep(let type)):
            return type == condition.rawValue
        case (.menstrualCycle(let phase, _), .menstrual(let p)):
            return p == phase.rawValue
        case (.weatherEffect(let condition, _), .weather(let w)):
            return w == condition.rawValue
        default:
            return false
        }
    }
    
    private func analyzeGlucoseResponse(
        event: HunchValidationEvent,
        belief: HunchBelief,
        glucoseHistory: [GlucosePoint]
    ) -> GlucoseResponseAnalysis {
        // Find glucose readings 30min before to 3hr after event
        let windowStart = event.timestamp.addingTimeInterval(-30 * 60)
        let windowEnd = event.timestamp.addingTimeInterval(3 * 60 * 60)
        
        let relevantReadings = glucoseHistory.filter { point in
            point.date >= windowStart && point.date <= windowEnd
        }.sorted { $0.date < $1.date }
        
        guard relevantReadings.count >= 6 else {
            return GlucoseResponseAnalysis(supports: false, contradicts: false, correlation: nil)
        }
        
        // Calculate glucose change
        let beforeEvent = relevantReadings.filter { $0.date < event.timestamp }
        let afterEvent = relevantReadings.filter { $0.date >= event.timestamp }
        
        guard let avgBefore = average(beforeEvent.map { $0.glucoseValue }),
              let avgAfter = average(afterEvent.map { $0.glucoseValue }) else {
            return GlucoseResponseAnalysis(supports: false, contradicts: false, correlation: nil)
        }
        
        let change = avgAfter - avgBefore
        let expectedDirection = expectedGlucoseChange(belief: belief)
        
        // Check if change matches expected direction
        let supports: Bool
        let contradicts: Bool
        
        switch expectedDirection {
        case .falling:
            supports = change < -10  // Dropped >10 mg/dL
            contradicts = change > 15  // Rose >15 mg/dL
        case .rising:
            supports = change > 10  // Rose >10 mg/dL
            contradicts = change < -15  // Dropped >15 mg/dL
        case .stable:
            supports = abs(change) < 15
            contradicts = abs(change) > 30
        }
        
        // Calculate correlation (simplified: magnitude of expected change)
        let expectedMagnitude: Double = 30  // Expected change in mg/dL
        let actualMagnitude = abs(change)
        let correlation = supports ? min(actualMagnitude / expectedMagnitude, 1.0) : 0.0
        
        return GlucoseResponseAnalysis(
            supports: supports,
            contradicts: contradicts,
            correlation: correlation
        )
    }
    
    private func expectedGlucoseChange(belief: HunchBelief) -> GlucoseDirection {
        switch belief {
        case .activityCausesLow: return .falling
        case .activityCausesHigh: return .rising
        case .foodEffect(_, let direction, _): return direction
        case .timePattern(_, let direction): return direction
        case .stressEffect(let direction, _): return direction
        case .medicationEffect(_, let effect):
            return effect == .increasedResistance ? .rising : .falling
        case .sleepPattern(_, let direction): return direction
        case .menstrualCycle(_, let effect):
            return effect == .moreResistant ? .rising : .falling
        case .weatherEffect(_, let effect):
            return effect == .moreResistant ? .rising : .falling
        case .custom(_, let expected):
            if let mult = expected.basalMultiplier {
                return mult > 1.0 ? .falling : .rising
            }
            return .stable
        }
    }
    
    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func generateValidationMessage(
        status: HunchValidationStatus,
        supportRatio: Double,
        correlation: Double?
    ) -> String {
        switch status {
        case .validated:
            let corrStr = correlation.map { "\(Int($0 * 100))% correlation" } ?? ""
            return "Hunch validated! \(Int(supportRatio * 100))% of events support this pattern. \(corrStr)"
        case .partiallyValidated:
            return "Partial support found. \(Int(supportRatio * 100))% of events match. More data may clarify."
        case .contradicted:
            return "Data suggests the opposite pattern. Only \(Int(supportRatio * 100))% of events support this."
        case .inconclusive:
            return "Results are mixed. Need more consistent events to draw conclusions."
        case .insufficientData:
            return "Not enough matching events in history. Keep tracking!"
        }
    }
}

/// A historical event used for validation
public struct HunchValidationEvent: Sendable {
    public let timestamp: Date
    public let eventType: ValidationEventType
    
    public init(timestamp: Date, eventType: ValidationEventType) {
        self.timestamp = timestamp
        self.eventType = eventType
    }
}

/// Types of events that can be validated
public enum ValidationEventType: Sendable {
    case activity(name: String)
    case food(name: String)
    case timeOfDay(hour: Int)
    case stress
    case medication(name: String)
    case sleep(type: String)
    case menstrual(phase: String)
    case weather(condition: String)
}

/// Result of glucose response analysis
private struct GlucoseResponseAnalysis {
    let supports: Bool
    let contradicts: Bool
    let correlation: Double?
}

/// Glucose point for validation
public struct GlucosePoint: Sendable {
    public let date: Date
    public let glucoseValue: Double
    
    public init(date: Date, glucoseValue: Double) {
        self.date = date
        self.glucoseValue = glucoseValue
    }
}

/// Validation status
public enum HunchValidationStatus: String, Sendable {
    case validated = "validated"
    case partiallyValidated = "partially_validated"
    case contradicted = "contradicted"
    case inconclusive = "inconclusive"
    case insufficientData = "insufficient_data"
}

/// Result of hunch validation
public struct HunchValidationResult: Sendable {
    public let status: HunchValidationStatus
    public let supportingEvents: Int
    public let contradictingEvents: Int
    public let correlation: Double?
    public let confidence: Double
    public let message: String
}

// MARK: - Hunch Agent Factory (ALG-HUNCH-004)

/// Creates custom EffectAgents from validated hunches
public struct HunchAgentFactory: Sendable {
    
    public init() {}
    
    /// Create a custom agent from a validated hunch
    public func createAgent(
        from hunch: HunchInput,
        validationResult: HunchValidationResult
    ) -> CustomHunchAgent? {
        guard validationResult.status == .validated || validationResult.status == .partiallyValidated else {
            return nil
        }
        
        let effect = calculateEffect(from: hunch.belief, confidence: validationResult.confidence)
        let trigger = createTrigger(from: hunch)
        
        return CustomHunchAgent(
            id: hunch.id,
            name: generateAgentName(from: hunch),
            hunch: hunch,
            effect: effect,
            trigger: trigger,
            trainingStatus: .hunch(sessions: validationResult.supportingEvents),
            createdAt: Date()
        )
    }
    
    private func calculateEffect(from belief: HunchBelief, confidence: Double) -> HunchAgentEffect {
        switch belief {
        case .activityCausesLow(_, let severity):
            // Activity causes lows → reduce basal, lower target
            let magnitude = severity.effectMultiplier * confidence
            return HunchAgentEffect(
                basalMultiplier: 1.0 - magnitude,  // e.g., 0.8
                isfMultiplier: 1.0 + (magnitude * 0.5),  // More sensitive
                targetAdjustment: 20 * magnitude,  // Raise target
                durationMinutes: 180
            )
            
        case .activityCausesHigh(_, let severity):
            // Activity causes highs → increase basal
            let magnitude = severity.effectMultiplier * confidence
            return HunchAgentEffect(
                basalMultiplier: 1.0 + magnitude,  // e.g., 1.2
                isfMultiplier: 1.0 - (magnitude * 0.5),  // More resistant
                targetAdjustment: -10 * magnitude,  // Lower target
                durationMinutes: 180
            )
            
        case .foodEffect(_, let direction, let severity):
            let magnitude = severity.effectMultiplier * confidence
            return HunchAgentEffect(
                basalMultiplier: direction == .rising ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: direction == .rising ? 1.0 - magnitude : 1.0 + magnitude,
                targetAdjustment: nil,
                durationMinutes: 240
            )
            
        case .timePattern(_, let direction):
            let magnitude = 0.2 * confidence
            return HunchAgentEffect(
                basalMultiplier: direction == .rising ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: nil,
                targetAdjustment: nil,
                durationMinutes: 180
            )
            
        case .stressEffect(let direction, let severity):
            let magnitude = severity.effectMultiplier * confidence
            return HunchAgentEffect(
                basalMultiplier: direction == .rising ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: nil,
                targetAdjustment: nil,
                durationMinutes: 120
            )
            
        case .medicationEffect(_, let effect):
            let magnitude = 0.3 * confidence
            return HunchAgentEffect(
                basalMultiplier: effect == .increasedResistance ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: effect == .increasedResistance ? 1.0 - (magnitude * 0.5) : 1.0 + (magnitude * 0.5),
                targetAdjustment: nil,
                durationMinutes: 480  // Medications often have longer effects
            )
            
        case .sleepPattern(_, let direction):
            let magnitude = 0.15 * confidence
            return HunchAgentEffect(
                basalMultiplier: direction == .rising ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: nil,
                targetAdjustment: nil,
                durationMinutes: 240
            )
            
        case .menstrualCycle(_, let effect):
            let magnitude = 0.25 * confidence
            return HunchAgentEffect(
                basalMultiplier: effect == .moreResistant ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: effect == .moreResistant ? 1.0 - magnitude : 1.0 + magnitude,
                targetAdjustment: nil,
                durationMinutes: 1440  // Day-long effect
            )
            
        case .weatherEffect(_, let effect):
            let magnitude = 0.15 * confidence
            return HunchAgentEffect(
                basalMultiplier: effect == .moreResistant ? 1.0 + magnitude : 1.0 - magnitude,
                isfMultiplier: nil,
                targetAdjustment: nil,
                durationMinutes: 480
            )
            
        case .custom(_, let expected):
            return HunchAgentEffect(
                basalMultiplier: expected.basalMultiplier,
                isfMultiplier: expected.isfMultiplier,
                targetAdjustment: expected.targetAdjustment,
                durationMinutes: expected.durationMinutes
            )
        }
    }
    
    private func createTrigger(from hunch: HunchInput) -> HunchAgentTrigger {
        switch hunch.belief {
        case .activityCausesLow(let activity, _), .activityCausesHigh(let activity, _):
            return .activity(name: activity)
        case .foodEffect(let item, _, _):
            return .food(item: item)
        case .timePattern(let period, _):
            return .timeOfDay(period: period)
        case .stressEffect:
            return .manual(label: "Feeling Stressed")
        case .medicationEffect(let med, _):
            return .medication(name: med)
        case .sleepPattern(let condition, _):
            return .sleep(condition: condition)
        case .menstrualCycle(let phase, _):
            return .menstrual(phase: phase)
        case .weatherEffect(let condition, _):
            return .weather(condition: condition)
        case .custom(let description, _):
            return .manual(label: String(description.prefix(30)))
        }
    }
    
    private func generateAgentName(from hunch: HunchInput) -> String {
        switch hunch.belief {
        case .activityCausesLow(let activity, _):
            return "\(activity) (Low Prevention)"
        case .activityCausesHigh(let activity, _):
            return "\(activity) (High Prevention)"
        case .foodEffect(let item, let direction, _):
            let effect = direction == .rising ? "Spike" : "Drop"
            return "\(item) \(effect) Handler"
        case .timePattern(let period, let direction):
            let effect = direction == .rising ? "High" : "Low"
            return "\(period.rawValue.capitalized) \(effect) Pattern"
        case .stressEffect(let direction, _):
            let effect = direction == .rising ? "High" : "Low"
            return "Stress \(effect) Handler"
        case .medicationEffect(let med, _):
            return "\(med) Adjustment"
        case .sleepPattern(let condition, _):
            return "\(condition.rawValue.capitalized) Pattern"
        case .menstrualCycle(let phase, _):
            return "\(phase.rawValue.capitalized) Cycle"
        case .weatherEffect(let condition, _):
            return "\(condition.rawValue.capitalized) Weather"
        case .custom(let description, _):
            return String(description.prefix(25))
        }
    }
}

/// A custom agent created from a user hunch
public struct CustomHunchAgent: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Human-readable name
    public let name: String
    
    /// Original hunch input
    public let hunch: HunchInput
    
    /// Calculated effect
    public let effect: HunchAgentEffect
    
    /// What triggers this agent
    public let trigger: HunchAgentTrigger
    
    /// Current training status
    public var trainingStatus: TrainingStatus
    
    /// When agent was created
    public let createdAt: Date
    
    /// Whether agent is enabled
    public var isEnabled: Bool = true
    
    public init(
        id: UUID,
        name: String,
        hunch: HunchInput,
        effect: HunchAgentEffect,
        trigger: HunchAgentTrigger,
        trainingStatus: TrainingStatus,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.hunch = hunch
        self.effect = effect
        self.trigger = trigger
        self.trainingStatus = trainingStatus
        self.createdAt = createdAt
    }
}

/// Effect calculated for a hunch agent
public struct HunchAgentEffect: Codable, Sendable, Equatable {
    public let basalMultiplier: Double?
    public let isfMultiplier: Double?
    public let targetAdjustment: Double?
    public let durationMinutes: Int
    
    public init(
        basalMultiplier: Double?,
        isfMultiplier: Double?,
        targetAdjustment: Double?,
        durationMinutes: Int
    ) {
        self.basalMultiplier = basalMultiplier
        self.isfMultiplier = isfMultiplier
        self.targetAdjustment = targetAdjustment
        self.durationMinutes = durationMinutes
    }
}

/// What triggers a hunch agent
public enum HunchAgentTrigger: Codable, Sendable, Equatable {
    case activity(name: String)
    case food(item: String)
    case timeOfDay(period: TimePeriod)
    case manual(label: String)
    case medication(name: String)
    case sleep(condition: SleepCondition)
    case menstrual(phase: MenstrualPhase)
    case weather(condition: WeatherCondition)
}

// MARK: - Hunch Manager (Orchestration)

/// Manages the full hunch lifecycle: input → parse → validate → create agent
public actor HunchManager {
    private let parser: HunchParser
    private let validator: HunchValidator
    private let factory: HunchAgentFactory
    
    /// All registered hunches
    private var hunches: [UUID: HunchInput] = [:]
    
    /// Created agents from validated hunches
    private var agents: [UUID: CustomHunchAgent] = [:]
    
    /// Validation results
    private var validationResults: [UUID: HunchValidationResult] = [:]
    
    public init(
        parser: HunchParser = HunchParser(),
        validator: HunchValidator = HunchValidator(),
        factory: HunchAgentFactory = HunchAgentFactory()
    ) {
        self.parser = parser
        self.validator = validator
        self.factory = factory
    }
    
    /// Submit a natural language hunch
    public func submitHunch(_ input: String) -> HunchSubmissionResult {
        let parsed = parser.parse(input)
        
        guard parsed.success else {
            // Still create a custom hunch for tracking
            let hunch = HunchInput(
                rawInput: input,
                category: parsed.category,
                belief: parsed.belief,
                userConfidence: 0.5
            )
            hunches[hunch.id] = hunch
            return HunchSubmissionResult(
                hunchId: hunch.id,
                parsed: parsed,
                needsMoreInfo: true,
                suggestions: generateSuggestions(from: input)
            )
        }
        
        let hunch = HunchInput(
            rawInput: input,
            category: parsed.category,
            belief: parsed.belief,
            userConfidence: parsed.confidence
        )
        hunches[hunch.id] = hunch
        
        return HunchSubmissionResult(
            hunchId: hunch.id,
            parsed: parsed,
            needsMoreInfo: false,
            suggestions: []
        )
    }
    
    /// Validate a hunch against historical data
    public func validateHunch(
        id: UUID,
        glucoseHistory: [GlucosePoint],
        eventHistory: [HunchValidationEvent]
    ) async -> HunchValidationResult? {
        guard let hunch = hunches[id] else { return nil }
        
        let result = await validator.validate(
            hunch: hunch,
            glucoseHistory: glucoseHistory,
            eventHistory: eventHistory
        )
        validationResults[id] = result
        
        return result
    }
    
    /// Create agent from validated hunch
    public func createAgentFromHunch(id: UUID) -> CustomHunchAgent? {
        guard let hunch = hunches[id],
              let validation = validationResults[id] else {
            return nil
        }
        
        guard let agent = factory.createAgent(from: hunch, validationResult: validation) else {
            return nil
        }
        
        agents[agent.id] = agent
        return agent
    }
    
    /// Get all active agents
    public func getActiveAgents() -> [CustomHunchAgent] {
        agents.values.filter { $0.isEnabled }.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get hunch by ID
    public func getHunch(id: UUID) -> HunchInput? {
        hunches[id]
    }
    
    /// Get validation result for hunch
    public func getValidationResult(id: UUID) -> HunchValidationResult? {
        validationResults[id]
    }
    
    private func generateSuggestions(from input: String) -> [String] {
        var suggestions: [String] = []
        
        if !input.lowercased().contains("low") && !input.lowercased().contains("high") {
            suggestions.append("Try adding 'makes me go low' or 'makes me spike'")
        }
        
        if !HunchParser().parse(input).success {
            suggestions.append("Be specific about activities, foods, or times (e.g., 'Tennis makes me go low')")
        }
        
        return suggestions
    }
}

/// Result of submitting a hunch
public struct HunchSubmissionResult: Sendable {
    public let hunchId: UUID
    public let parsed: ParsedHunch
    public let needsMoreInfo: Bool
    public let suggestions: [String]
}
