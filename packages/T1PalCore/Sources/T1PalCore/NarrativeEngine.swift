// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NarrativeEngine.swift - Narrative UX engine protocol
// Part of T1PalCore
// Trace: NARRATIVE-001, NARRATIVE-ENGINE-001

import Foundation

// MARK: - Narrative Localization Keys (ENGINE-001)

/// Localization keys for narrative strings
/// Trace: NARRATIVE-ENGINE-001
public enum NarrativeL10n {
    
    // MARK: - Greetings
    
    public enum Greeting {
        public static let morning = "narrative.greeting.morning"
        public static let afternoon = "narrative.greeting.afternoon"
        public static let evening = "narrative.greeting.evening"
        public static let night = "narrative.greeting.night"
    }
    
    // MARK: - Summary Templates
    
    public enum Summary {
        public static let urgentLow = "narrative.summary.urgentLow"
        public static let low = "narrative.summary.low"
        public static let inRange = "narrative.summary.inRange"
        public static let high = "narrative.summary.high"
        public static let veryHigh = "narrative.summary.veryHigh"
    }
    
    // MARK: - Detail Templates
    
    public enum Detail {
        public static let risingQuickly = "narrative.detail.risingQuickly"
        public static let rising = "narrative.detail.rising"
        public static let fallingQuickly = "narrative.detail.fallingQuickly"
        public static let falling = "narrative.detail.falling"
        public static let insulinActive = "narrative.detail.insulinActive"
        public static let carbsAbsorbing = "narrative.detail.carbsAbsorbing"
    }
    
    // MARK: - Suggestions
    
    public enum Suggestion {
        public static let urgentLowPatient = "narrative.suggestion.urgentLow.patient"
        public static let urgentLowCaregiver = "narrative.suggestion.urgentLow.caregiver"
        public static let low = "narrative.suggestion.low"
        public static let waitForInsulin = "narrative.suggestion.waitForInsulin"
        public static let checkKetones = "narrative.suggestion.checkKetones"
    }
    
    // MARK: - Acknowledgments
    
    public enum Acknowledgment {
        public static let urgentLowPatient = "narrative.ack.urgentLow.patient"
        public static let urgentLowCaregiver = "narrative.ack.urgentLow.caregiver"
        public static let lowRecovering = "narrative.ack.low.recovering"
        public static let lowRecoveringCaregiver = "narrative.ack.low.recovering.caregiver"
        public static let lowTough = "narrative.ack.low.tough"
        public static let lowToughCaregiver = "narrative.ack.low.tough.caregiver"
        public static let inRangeStable = "narrative.ack.inRange.stable"
        public static let inRangeStableCaregiver = "narrative.ack.inRange.stable.caregiver"
        public static let inRangeMealCoverage = "narrative.ack.inRange.mealCoverage"
        public static let inRangeMealCoverageCaregiver = "narrative.ack.inRange.mealCoverage.caregiver"
        public static let highComingDown = "narrative.ack.high.comingDown"
        public static let highComingDownCaregiver = "narrative.ack.high.comingDown.caregiver"
        public static let highInsulinWorking = "narrative.ack.high.insulinWorking"
        public static let veryHighPatient = "narrative.ack.veryHigh.patient"
        public static let veryHighCaregiver = "narrative.ack.veryHigh.caregiver"
    }
    
    // MARK: - Predictions
    
    public enum Prediction {
        public static let riseTo = "narrative.prediction.riseTo"
        public static let fallTo = "narrative.prediction.fallTo"
        public static let unable = "narrative.prediction.unable"
    }
    
    // MARK: - Choices
    
    public enum Choice {
        public static let noActionsNeeded = "narrative.choice.noActionsNeeded"
        public static let couldDo = "narrative.choice.couldDo"
    }
}

/// Default narrative strings (English) when localization bundle not available
/// Trace: NARRATIVE-ENGINE-001
public struct NarrativeStrings {
    
    // MARK: - Greetings
    
    public static func greeting(for timeOfDay: MetabolicContext.TimeOfDay) -> String {
        switch timeOfDay {
        case .morning: return NarrativeL10n.Greeting.morning.localized(fallback: "Good morning.")
        case .afternoon: return NarrativeL10n.Greeting.afternoon.localized(fallback: "Good afternoon.")
        case .evening: return NarrativeL10n.Greeting.evening.localized(fallback: "Good evening.")
        case .night: return ""
        }
    }
    
    // MARK: - Summary Generation
    
    public static func summary(
        for assessment: MetabolicContext.Assessment,
        glucose: Int,
        timeOfDay: MetabolicContext.TimeOfDay,
        perspective: NarrativePerspective
    ) -> String {
        let subject = perspective.subjectPronoun
        let greeting = greeting(for: timeOfDay)
        
        switch assessment {
        case .urgentLow:
            let template = NarrativeL10n.Summary.urgentLow.localized(
                fallback: "%@ glucose is very low at %d. Take action now."
            )
            return String(format: template, subject, glucose)
        case .low:
            let template = NarrativeL10n.Summary.low.localized(
                fallback: "%@ glucose is low at %d. Consider having a snack."
            )
            return String(format: template, subject, glucose)
        case .inRange:
            let target = perspective == .patient ? "you want it" : "it should be"
            let template = NarrativeL10n.Summary.inRange.localized(
                fallback: "%@ %@ glucose is %d, right where %@."
            )
            return String(format: template, greeting, subject, glucose, target)
        case .high:
            let template = NarrativeL10n.Summary.high.localized(
                fallback: "%@ glucose is %d, a bit higher than target."
            )
            return String(format: template, subject, glucose)
        case .veryHigh:
            let template = NarrativeL10n.Summary.veryHigh.localized(
                fallback: "%@ glucose is high at %d. Consider a correction."
            )
            return String(format: template, subject, glucose)
        }
    }
    
    // MARK: - Suggestion Generation
    
    public static func suggestion(
        for assessment: MetabolicContext.Assessment,
        perspective: NarrativePerspective,
        iob: Double?
    ) -> String? {
        let object = perspective.objectPronoun
        
        switch assessment {
        case .urgentLow:
            if perspective == .patient {
                return NarrativeL10n.Suggestion.urgentLowPatient.localized(
                    fallback: "Have 15-20g of fast-acting carbs immediately"
                )
            } else {
                let template = NarrativeL10n.Suggestion.urgentLowCaregiver.localized(
                    fallback: "Give %@ 15-20g of fast-acting carbs immediately"
                )
                return String(format: template, object)
            }
        case .low:
            return NarrativeL10n.Suggestion.low.localized(
                fallback: "A small snack of 10-15g carbs would help"
            )
        case .inRange:
            return nil
        case .high:
            if let iob = iob, iob > 2 {
                return NarrativeL10n.Suggestion.waitForInsulin.localized(
                    fallback: "Wait for the current insulin to work"
                )
            }
            return nil
        case .veryHigh:
            return NarrativeL10n.Suggestion.checkKetones.localized(
                fallback: "Check for ketones if this persists"
            )
        }
    }
    
    // MARK: - Acknowledgment Generation
    
    public static func acknowledgment(
        for assessment: MetabolicContext.Assessment,
        perspective: NarrativePerspective,
        rateOfChange: Double?,
        iob: Double?,
        cob: Double?
    ) -> String? {
        let isPatient = perspective == .patient
        
        switch assessment {
        case .urgentLow:
            if isPatient {
                return NarrativeL10n.Acknowledgment.urgentLowPatient.localized(
                    fallback: "I know this is stressful. You've got this."
                )
            } else {
                return NarrativeL10n.Acknowledgment.urgentLowCaregiver.localized(
                    fallback: "Stay calm. Help is on the way."
                )
            }
        case .low:
            if let rate = rateOfChange, rate > 0.5 {
                if isPatient {
                    return NarrativeL10n.Acknowledgment.lowRecovering.localized(
                        fallback: "Great job treating that low. You're on the way up."
                    )
                } else {
                    return NarrativeL10n.Acknowledgment.lowRecoveringCaregiver.localized(
                        fallback: "Good work! Numbers are coming up."
                    )
                }
            }
            if isPatient {
                return NarrativeL10n.Acknowledgment.lowTough.localized(
                    fallback: "Lows are tough. Take care of yourself."
                )
            } else {
                return NarrativeL10n.Acknowledgment.lowToughCaregiver.localized(
                    fallback: "Lows are tough. Be there for them."
                )
            }
        case .inRange:
            if let rate = rateOfChange, abs(rate) < 0.5 {
                if isPatient {
                    return NarrativeL10n.Acknowledgment.inRangeStable.localized(
                        fallback: "Nicely done! Stable and in range."
                    )
                } else {
                    return NarrativeL10n.Acknowledgment.inRangeStableCaregiver.localized(
                        fallback: "Looking great! Stable and in range."
                    )
                }
            }
            if let iob = iob, let cob = cob, iob > 0.3 && cob > 5 {
                if isPatient {
                    return NarrativeL10n.Acknowledgment.inRangeMealCoverage.localized(
                        fallback: "Looking good with your meal coverage."
                    )
                } else {
                    return NarrativeL10n.Acknowledgment.inRangeMealCoverageCaregiver.localized(
                        fallback: "Good meal coverage."
                    )
                }
            }
            return nil
        case .high:
            if let rate = rateOfChange, rate < -0.5 {
                if isPatient {
                    return NarrativeL10n.Acknowledgment.highComingDown.localized(
                        fallback: "You're heading in the right direction."
                    )
                } else {
                    return NarrativeL10n.Acknowledgment.highComingDownCaregiver.localized(
                        fallback: "Trending in the right direction."
                    )
                }
            }
            if let iob = iob, iob > 2 {
                return NarrativeL10n.Acknowledgment.highInsulinWorking.localized(
                    fallback: "The insulin is working. Give it time."
                )
            }
            return nil
        case .veryHigh:
            if isPatient {
                return NarrativeL10n.Acknowledgment.veryHighPatient.localized(
                    fallback: "I know high numbers are frustrating. You're doing your best."
                )
            } else {
                return NarrativeL10n.Acknowledgment.veryHighCaregiver.localized(
                    fallback: "High numbers happen. Stay supportive."
                )
            }
        }
    }
}

// MARK: - String Localization Helper

extension String {
    /// Get localized version with fallback
    /// Trace: NARRATIVE-ENGINE-001, LIFE-NOTIFY-002
    public func localized(fallback: String) -> String {
        let result = LocalizationManager.shared.string(self)
        // If key returned unchanged, use fallback
        return result == self ? fallback : result
    }
}

// MARK: - Metabolic Context

/// Snapshot of current metabolic state for narrative generation
public struct MetabolicContext: Sendable {
    /// Current glucose in mg/dL
    public let glucose: Double
    
    /// Glucose trend/rate of change (mg/dL per minute)
    public let rateOfChange: Double?
    
    /// Insulin on board in units
    public let iob: Double?
    
    /// Carbs on board in grams
    public let cob: Double?
    
    /// Time since last reading
    public let readingAge: TimeInterval
    
    /// Recent glucose values (last 30 min)
    public let recentGlucose: [Double]
    
    /// Target range
    public let targetRange: ClosedRange<Double>
    
    /// Time of day
    public let timeOfDay: TimeOfDay
    
    public enum TimeOfDay: String, Sendable {
        case morning    // 5am - 12pm
        case afternoon  // 12pm - 5pm
        case evening    // 5pm - 9pm
        case night      // 9pm - 5am
        
        public static func from(date: Date) -> TimeOfDay {
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }
    
    public init(
        glucose: Double,
        rateOfChange: Double? = nil,
        iob: Double? = nil,
        cob: Double? = nil,
        readingAge: TimeInterval = 0,
        recentGlucose: [Double] = [],
        targetRange: ClosedRange<Double> = 70...180,
        timeOfDay: TimeOfDay = .from(date: Date())
    ) {
        self.glucose = glucose
        self.rateOfChange = rateOfChange
        self.iob = iob
        self.cob = cob
        self.readingAge = readingAge
        self.recentGlucose = recentGlucose
        self.targetRange = targetRange
        self.timeOfDay = timeOfDay
    }
    
    /// Overall assessment of metabolic state
    public var assessment: Assessment {
        if glucose < 54 { return .urgentLow }
        if glucose < 70 { return .low }
        if glucose > 250 { return .veryHigh }
        if glucose > 180 { return .high }
        return .inRange
    }
    
    public enum Assessment: String, Sendable {
        case urgentLow
        case low
        case inRange
        case high
        case veryHigh
    }
}

// MARK: - Narrative Output

/// Generated narrative about metabolic state
public struct Narrative: Sendable {
    /// Main summary sentence
    public let summary: String
    
    /// Detailed explanation (optional)
    public let detail: String?
    
    /// Suggested action (optional)
    public let suggestion: String?
    
    /// Emotional acknowledgment (optional) — empathetic message
    public let acknowledgment: String?
    
    /// Emotional tone/urgency
    public let tone: Tone
    
    /// Confidence level (0-1)
    public let confidence: Double
    
    public enum Tone: String, Sendable {
        case calm       // Everything normal
        case positive   // Improving situation
        case cautious   // Watch this
        case concerned  // Attention needed
        case urgent     // Act now
    }
    
    public init(
        summary: String,
        detail: String? = nil,
        suggestion: String? = nil,
        acknowledgment: String? = nil,
        tone: Tone = .calm,
        confidence: Double = 1.0
    ) {
        self.summary = summary
        self.detail = detail
        self.suggestion = suggestion
        self.acknowledgment = acknowledgment
        self.tone = tone
        self.confidence = confidence
    }
}

// MARK: - Narrative Engine Protocol

/// Perspective for narrative generation (ADAPT-003)
public enum NarrativePerspective: String, Sendable, CaseIterable, Codable {
    /// First person: "Your glucose is..."
    case patient
    /// Third person: "Their glucose is..." (for caregivers)
    case caregiver
    /// Clinical: "Glucose reading is..." (neutral/professional)
    case clinical
    
    public var subjectPronoun: String {
        switch self {
        case .patient: return "Your"
        case .caregiver: return "Their"
        case .clinical: return "The"
        }
    }
    
    public var objectPronoun: String {
        switch self {
        case .patient: return "you"
        case .caregiver: return "them"
        case .clinical: return "the patient"
        }
    }
    
    public var possessivePronoun: String {
        switch self {
        case .patient: return "your"
        case .caregiver: return "their"
        case .clinical: return "the patient's"
        }
    }
    
    public var displayName: String {
        switch self {
        case .patient: return "Patient View"
        case .caregiver: return "Caregiver View"
        case .clinical: return "Clinical View"
        }
    }
}

/// Protocol for generating human-readable narratives from metabolic data
/// Trace: NARRATIVE-001
public protocol NarrativeEngine: Sendable {
    /// Generate a narrative from the current metabolic context
    func generateNarrative(from context: MetabolicContext) -> Narrative
    
    /// Generate a narrative with perspective
    func generateNarrative(from context: MetabolicContext, perspective: NarrativePerspective) -> Narrative
    
    /// Generate a brief status update (for widgets, complications)
    func generateBriefStatus(from context: MetabolicContext) -> String
    
    /// Generate a prediction narrative
    func generatePrediction(from context: MetabolicContext, predictedGlucose: [Double]) -> Narrative
    
    /// Generate a choice/decision narrative
    func generateChoiceNarrative(from context: MetabolicContext, choices: [Choice]) -> Narrative
}

/// Represents a choice the user could make
public struct Choice: Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let consequence: String  // What will happen
    
    public init(id: String, title: String, description: String, consequence: String) {
        self.id = id
        self.title = title
        self.description = description
        self.consequence = consequence
    }
}

// MARK: - Default Narrative Engine

/// Default implementation of NarrativeEngine
public struct DefaultNarrativeEngine: NarrativeEngine {
    
    public init() {}
    
    public func generateNarrative(from context: MetabolicContext) -> Narrative {
        generateNarrative(from: context, perspective: .patient)
    }
    
    public func generateNarrative(from context: MetabolicContext, perspective: NarrativePerspective) -> Narrative {
        let summary = generateSummary(from: context, perspective: perspective)
        let detail = generateDetail(from: context, perspective: perspective)
        let suggestion = generateSuggestion(from: context, perspective: perspective)
        let acknowledgment = generateAcknowledgment(from: context, perspective: perspective)
        let tone = determineTone(from: context)
        
        return Narrative(
            summary: summary,
            detail: detail,
            suggestion: suggestion,
            acknowledgment: acknowledgment,
            tone: tone
        )
    }
    
    public func generateBriefStatus(from context: MetabolicContext) -> String {
        let value = Int(context.glucose)
        let trend = trendArrow(for: context.rateOfChange)
        return "\(value)\(trend)"
    }
    
    public func generatePrediction(from context: MetabolicContext, predictedGlucose: [Double]) -> Narrative {
        generatePrediction(from: context, predictedGlucose: predictedGlucose, perspective: .patient)
    }
    
    public func generatePrediction(from context: MetabolicContext, predictedGlucose: [Double], perspective: NarrativePerspective) -> Narrative {
        guard let future = predictedGlucose.last else {
            let unableText = NarrativeL10n.Prediction.unable.localized(fallback: "Unable to predict")
            return Narrative(summary: unableText, tone: .cautious, confidence: 0)
        }
        
        let current = Int(context.glucose)
        let predicted = Int(future)
        let isRising = predicted > current
        
        let directionKey = isRising ? NarrativeL10n.Prediction.riseTo : NarrativeL10n.Prediction.fallTo
        let directionFallback = isRising ? "rise to" : "fall to"
        let direction = directionKey.localized(fallback: directionFallback)
        
        let summary = "\(perspective.subjectPronoun) glucose is predicted to \(direction) \(predicted) mg/dL"
        let tone: Narrative.Tone = predicted < 70 ? .concerned : (predicted > 180 ? .cautious : .calm)
        
        return Narrative(summary: summary, tone: tone, confidence: 0.7)
    }
    
    public func generateChoiceNarrative(from context: MetabolicContext, choices: [Choice]) -> Narrative {
        guard !choices.isEmpty else {
            let noActionsText = NarrativeL10n.Choice.noActionsNeeded.localized(fallback: "No actions needed right now")
            return Narrative(summary: noActionsText, tone: .calm)
        }
        
        let choiceList = choices.map { $0.title }.joined(separator: " or ")
        let template = NarrativeL10n.Choice.couldDo.localized(fallback: "You could %@")
        let summary = String(format: template, choiceList)
        
        return Narrative(summary: summary, tone: .calm)
    }
    
    // MARK: - Private Helpers
    
    private func generateSummary(from context: MetabolicContext, perspective: NarrativePerspective = .patient) -> String {
        // Use localized NarrativeStrings (ENGINE-001)
        return NarrativeStrings.summary(
            for: context.assessment,
            glucose: Int(context.glucose),
            timeOfDay: context.timeOfDay,
            perspective: perspective
        )
    }
    
    private func generateDetail(from context: MetabolicContext, perspective: NarrativePerspective = .patient) -> String? {
        var parts: [String] = []
        let isVerbose = DisplayModeManager.shared.verboseNarratives
        
        // Trend description (always included if significant)
        if let rate = context.rateOfChange {
            if abs(rate) > 2 {
                let key = rate > 0 ? NarrativeL10n.Detail.risingQuickly : NarrativeL10n.Detail.fallingQuickly
                let fallback = rate > 0 ? "It's rising quickly" : "It's falling quickly"
                parts.append(key.localized(fallback: fallback))
            } else if abs(rate) > 1 {
                let key = rate > 0 ? NarrativeL10n.Detail.rising : NarrativeL10n.Detail.falling
                let fallback = rate > 0 ? "It's rising" : "It's falling"
                parts.append(key.localized(fallback: fallback))
            }
            
            // Verbose: include exact rate (NARRATIVE-UX-002)
            if isVerbose && abs(rate) > 0.5 {
                let direction = rate > 0 ? "+" : ""
                parts.append(String(format: "(%@%.1f mg/dL per minute)", direction, rate))
            }
        }
        
        // IOB detail
        if let iob = context.iob, iob > 0.5 {
            let pronoun = perspective == .patient ? "You have" : (perspective == .caregiver ? "They have" : "There is")
            // Use %.2f to match Loop/Nightscout precision (0.96 U not 1.0 U)
            let template = NarrativeL10n.Detail.insulinActive.localized(fallback: "%@ %.2f units of insulin active")
            parts.append(String(format: template, pronoun, iob))
        }
        
        // COB detail
        if let cob = context.cob, cob > 10 {
            let template = NarrativeL10n.Detail.carbsAbsorbing.localized(fallback: "About %dg of carbs are still absorbing")
            parts.append(String(format: template, Int(cob)))
        }
        
        // Verbose: reading age (NARRATIVE-UX-002)
        if isVerbose && context.readingAge > 60 {
            let minutes = Int(context.readingAge / 60)
            if minutes == 1 {
                parts.append("Reading is 1 minute old")
            } else {
                parts.append(String(format: "Reading is %d minutes old", minutes))
            }
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
    }
    
    private func generateSuggestion(from context: MetabolicContext, perspective: NarrativePerspective = .patient) -> String? {
        // Use localized NarrativeStrings (ENGINE-001)
        return NarrativeStrings.suggestion(
            for: context.assessment,
            perspective: perspective,
            iob: context.iob
        )
    }
    
    private func generateAcknowledgment(from context: MetabolicContext, perspective: NarrativePerspective = .patient) -> String? {
        // Use localized NarrativeStrings (ENGINE-001)
        return NarrativeStrings.acknowledgment(
            for: context.assessment,
            perspective: perspective,
            rateOfChange: context.rateOfChange,
            iob: context.iob,
            cob: context.cob
        )
    }
    
    private func determineTone(from context: MetabolicContext) -> Narrative.Tone {
        switch context.assessment {
        case .urgentLow: return .urgent
        case .low: return .concerned
        case .inRange:
            if let rate = context.rateOfChange, abs(rate) > 2 {
                return .cautious
            }
            return .calm
        case .high: return .cautious
        case .veryHigh: return .concerned
        }
    }
    
    private func greeting(for timeOfDay: MetabolicContext.TimeOfDay) -> String {
        // Use localized NarrativeStrings (ENGINE-001)
        return NarrativeStrings.greeting(for: timeOfDay)
    }
    
    private func trendArrow(for rate: Double?) -> String {
        guard let rate = rate else { return "" }
        switch rate {
        case ..<(-2): return "⇊"
        case ..<(-1): return "↓"
        case (-1)...1: return "→"
        case 1..<2: return "↑"
        default: return "⇈"
        }
    }
}

// MARK: - Display Mode (NARRATIVE-WIRE-005)

/// Display mode for glucose information
public enum NarrativeMode: String, CaseIterable, Sendable, Codable {
    case standard = "standard"
    case narrative = "narrative"
    case minimal = "minimal"
    
    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .narrative: return "Narrative"
        case .minimal: return "Minimal"
        }
    }
    
    public var description: String {
        switch self {
        case .standard: return "Traditional numbers and graphs"
        case .narrative: return "Conversational summaries and suggestions"
        case .minimal: return "Just the essentials"
        }
    }
    
    public var icon: String {
        switch self {
        case .standard: return "chart.line.uptrend.xyaxis"
        case .narrative: return "text.bubble"
        case .minimal: return "number"
        }
    }
}

// MARK: - Chart Time Range (DATA-ACCUM-006)

/// Time range options for glucose chart display
/// Trace: DATA-ACCUM-006
public enum ChartTimeRange: String, CaseIterable, Sendable, Codable {
    case hours3 = "3h"
    case hours8 = "8h"
    case hours24 = "24h"
    case hours48 = "48h"
    
    /// Time range in seconds
    public var seconds: TimeInterval {
        switch self {
        case .hours3: return 3 * 60 * 60
        case .hours8: return 8 * 60 * 60
        case .hours24: return 24 * 60 * 60
        case .hours48: return 48 * 60 * 60
        }
    }
    
    /// Display label for UI
    public var displayName: String {
        switch self {
        case .hours3: return "3h"
        case .hours8: return "8h"
        case .hours24: return "24h"
        case .hours48: return "48h"
        }
    }
}

// MARK: - Display Mode Preferences (NARRATIVE-UX-005)

/// User preferences for display mode
///
/// These settings control how glucose information is presented in narrative mode:
///
/// - `mode`: Display style (standard/narrative/minimal)
/// - `showConsequences`: Show consequence text on Choice cards (requires Choice system)
/// - `verboseNarratives`: Include additional detail in narrative summaries
/// - `perspective`: First-person (patient) or third-person (caregiver) language
///
/// ## verboseNarratives
/// When enabled, narrative detail includes:
/// - Exact trend rate (e.g., "+1.5 mg/dL per minute")
/// - Reading age when > 1 minute (e.g., "Reading is 3 minutes old")
///
/// Default: false (concise narratives)
///
/// ## showConsequences
/// Controls visibility of `consequence` field on `ChoiceCardView`.
/// Currently hidden in Settings UI because the Choice system is not
/// implemented for Follower app (scaffolded for AID decision support).
///
/// Default: true
///
/// ## chartTimeRange
/// Default chart time range for glucose history display.
/// User can select 3h/8h/24h/48h via UI picker.
///
/// Default: .hours8
///
/// Trace: NARRATIVE-WIRE-005, NARRATIVE-ADAPT-003, NARRATIVE-UX-005, DATA-ACCUM-006
public struct DisplayModePreferences: Sendable, Codable {
    public var mode: NarrativeMode
    public var showConsequences: Bool
    public var verboseNarratives: Bool
    public var perspective: NarrativePerspective
    public var chartTimeRange: ChartTimeRange
    
    public init(
        mode: NarrativeMode = .standard,
        showConsequences: Bool = true,
        verboseNarratives: Bool = false,
        perspective: NarrativePerspective = .patient,
        chartTimeRange: ChartTimeRange = .hours8
    ) {
        self.mode = mode
        self.showConsequences = showConsequences
        self.verboseNarratives = verboseNarratives
        self.perspective = perspective
        self.chartTimeRange = chartTimeRange
    }
    
    public static let `default` = DisplayModePreferences()
}

/// Manager for persisting display mode preferences
/// Trace: NARRATIVE-WIRE-005
public final class DisplayModeManager: @unchecked Sendable {
    
    public static let shared = DisplayModeManager()
    
    private let defaults: UserDefaults
    private let key = "t1pal_display_mode_preferences"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// Load preferences from UserDefaults
    public func load() -> DisplayModePreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(DisplayModePreferences.self, from: data) else {
            return .default
        }
        return preferences
    }
    
    /// Save preferences to UserDefaults
    public func save(_ preferences: DisplayModePreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
    
    /// Current display mode (convenience accessor)
    public var currentMode: NarrativeMode {
        get { load().mode }
        set {
            var prefs = load()
            prefs.mode = newValue
            save(prefs)
        }
    }
    
    /// Show consequences setting
    public var showConsequences: Bool {
        get { load().showConsequences }
        set {
            var prefs = load()
            prefs.showConsequences = newValue
            save(prefs)
        }
    }
    
    /// Verbose narratives setting
    public var verboseNarratives: Bool {
        get { load().verboseNarratives }
        set {
            var prefs = load()
            prefs.verboseNarratives = newValue
            save(prefs)
        }
    }
    
    /// Narrative perspective (patient/caregiver/clinical)
    public var perspective: NarrativePerspective {
        get { load().perspective }
        set {
            var prefs = load()
            prefs.perspective = newValue
            save(prefs)
        }
    }
    
    /// Chart time range (DATA-ACCUM-006)
    public var chartTimeRange: ChartTimeRange {
        get { load().chartTimeRange }
        set {
            var prefs = load()
            prefs.chartTimeRange = newValue
            save(prefs)
        }
    }
    
    // MARK: - Update Methods (BUILD-FIX-001)
    
    /// Update display mode
    public func updateMode(_ mode: NarrativeMode) {
        self.currentMode = mode
    }
    
    /// Update show consequences setting
    public func updateShowConsequences(_ show: Bool) {
        self.showConsequences = show
    }
    
    /// Update verbose narratives setting
    public func updateVerboseNarratives(_ verbose: Bool) {
        self.verboseNarratives = verbose
    }
    
    /// Update perspective
    public func updatePerspective(_ perspective: NarrativePerspective) {
        self.perspective = perspective
    }
    
    /// Update chart time range (DATA-ACCUM-006)
    public func updateChartTimeRange(_ timeRange: ChartTimeRange) {
        self.chartTimeRange = timeRange
    }
}
