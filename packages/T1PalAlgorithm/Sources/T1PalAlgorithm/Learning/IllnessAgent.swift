// SPDX-License-Identifier: AGPL-3.0-or-later
//
// IllnessAgent.swift
// T1PalAlgorithm
//
// Illness pattern detection and sick day recommendations
// ALG-EFF-032..034: Illness detection, recommendations, quick actions
//
// Trace: PRD-028 (ML-Enhanced Dosing)

import Foundation

// MARK: - ALG-EFF-032: Illness Pattern Detection

/// Signs of illness detected in glucose data
public struct IllnessIndicators: Sendable, Codable, Equatable {
    /// Average glucose elevation above baseline (mg/dL)
    public let glucoseElevation: Double
    
    /// Increase in glucose variability (coefficient of variation ratio)
    public let variabilityIncrease: Double
    
    /// Decrease in time in range (percentage points)
    public let tirDecrease: Double
    
    /// Increased insulin resistance factor
    public let resistanceFactor: Double
    
    /// Confidence in illness detection (0.0-1.0)
    public let confidence: Double
    
    /// Hours of data analyzed
    public let hoursAnalyzed: Double
    
    /// Onset time (when indicators first appeared)
    public let onsetTime: Date?
    
    public init(
        glucoseElevation: Double,
        variabilityIncrease: Double,
        tirDecrease: Double,
        resistanceFactor: Double,
        confidence: Double,
        hoursAnalyzed: Double,
        onsetTime: Date? = nil
    ) {
        self.glucoseElevation = glucoseElevation
        self.variabilityIncrease = variabilityIncrease
        self.tirDecrease = tirDecrease
        self.resistanceFactor = resistanceFactor
        self.confidence = confidence
        self.hoursAnalyzed = hoursAnalyzed
        self.onsetTime = onsetTime
    }
    
    /// Whether these indicators suggest illness
    public var suggestsIllness: Bool {
        // Illness suggested if multiple indicators present
        var indicatorCount = 0
        if glucoseElevation >= 20 { indicatorCount += 1 }
        if variabilityIncrease >= 0.15 { indicatorCount += 1 }
        if tirDecrease >= 10 { indicatorCount += 1 }
        if resistanceFactor >= 1.15 { indicatorCount += 1 }
        
        return indicatorCount >= 2 && confidence >= 0.5
    }
    
    /// Severity level
    public var severity: IllnessSeverity {
        let score = (glucoseElevation / 50.0) + (variabilityIncrease * 2) + (tirDecrease / 20.0)
        
        if score >= 2.5 { return .severe }
        if score >= 1.5 { return .moderate }
        if score >= 0.5 { return .mild }
        return .none
    }
}

/// Severity levels for illness impact on glucose
public enum IllnessSeverity: String, Sendable, Codable, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    
    /// Suggested basal increase percentage
    public var suggestedBasalIncrease: Double {
        switch self {
        case .none: return 0.0
        case .mild: return 0.10     // +10%
        case .moderate: return 0.20 // +20%
        case .severe: return 0.30   // +30%
        }
    }
    
    /// Suggested target adjustment (mg/dL lower)
    public var suggestedTargetDecrease: Double {
        switch self {
        case .none: return 0
        case .mild: return 5
        case .moderate: return 10
        case .severe: return 10 // Cap at 10 for safety
        }
    }
}

/// Detects illness patterns in glucose data
public struct IllnessPatternDetector: Sendable {
    
    /// Configuration for illness detection
    public struct Configuration: Sendable {
        /// Minimum hours of data needed
        public let minimumHours: Double
        
        /// Baseline period to compare against (days)
        public let baselineDays: Int
        
        /// Minimum glucose elevation to flag (mg/dL)
        public let elevationThreshold: Double
        
        /// Minimum variability increase to flag (ratio)
        public let variabilityThreshold: Double
        
        /// Minimum TIR decrease to flag (percentage points)
        public let tirThreshold: Double
        
        public init(
            minimumHours: Double = 12,
            baselineDays: Int = 14,
            elevationThreshold: Double = 15,
            variabilityThreshold: Double = 0.10,
            tirThreshold: Double = 8
        ) {
            self.minimumHours = minimumHours
            self.baselineDays = baselineDays
            self.elevationThreshold = elevationThreshold
            self.variabilityThreshold = variabilityThreshold
            self.tirThreshold = tirThreshold
        }
        
        public static let `default` = Configuration()
    }
    
    public let configuration: Configuration
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    /// A timestamped glucose reading for analysis
    public struct GlucoseReading: Sendable {
        public let timestamp: Date
        public let value: Double // mg/dL
        
        public init(timestamp: Date, value: Double) {
            self.timestamp = timestamp
            self.value = value
        }
    }
    
    /// Analyze recent glucose against baseline to detect illness
    /// - Parameters:
    ///   - recent: Recent readings (last 12-48 hours)
    ///   - baseline: Baseline readings (previous 14+ days)
    /// - Returns: Illness indicators if detected
    public func analyze(
        recent: [GlucoseReading],
        baseline: [GlucoseReading]
    ) -> IllnessIndicators? {
        // Validate data
        let recentHours = hoursSpanned(recent)
        guard recentHours >= configuration.minimumHours else { return nil }
        
        let baselineDays = daysSpanned(baseline)
        guard baselineDays >= 7 else { return nil } // Need at least a week
        
        // Calculate baseline statistics
        let baselineValues = baseline.map { $0.value }
        let baselineMean = mean(baselineValues)
        let baselineStdDev = standardDeviation(baselineValues)
        let baselineCV = baselineStdDev / baselineMean
        let baselineTIR = timeInRange(baseline)
        
        // Calculate recent statistics
        let recentValues = recent.map { $0.value }
        let recentMean = mean(recentValues)
        let recentStdDev = standardDeviation(recentValues)
        let recentCV = recentStdDev / recentMean
        let recentTIR = timeInRange(recent)
        
        // Calculate deltas
        let glucoseElevation = recentMean - baselineMean
        let variabilityIncrease = recentCV - baselineCV
        let tirDecrease = baselineTIR - recentTIR
        
        // Calculate resistance factor (how much more insulin-resistant)
        let resistanceFactor = recentMean / baselineMean
        
        // Calculate confidence based on data quality and signal strength
        let dataQualityScore = min(1.0, recentHours / 24.0) * min(1.0, Double(baselineDays) / 14.0)
        let signalStrength = min(1.0, (glucoseElevation / 50.0 + variabilityIncrease * 3 + tirDecrease / 30.0) / 3.0)
        let confidence = dataQualityScore * 0.4 + signalStrength * 0.6
        
        // Find onset time (when elevation started)
        let onsetTime = findOnsetTime(recent: recent, baselineMean: baselineMean)
        
        let indicators = IllnessIndicators(
            glucoseElevation: glucoseElevation,
            variabilityIncrease: variabilityIncrease,
            tirDecrease: tirDecrease,
            resistanceFactor: resistanceFactor,
            confidence: confidence,
            hoursAnalyzed: recentHours,
            onsetTime: onsetTime
        )
        
        // Only return if there's something to report
        guard indicators.suggestsIllness || 
              glucoseElevation >= configuration.elevationThreshold ||
              variabilityIncrease >= configuration.variabilityThreshold ||
              tirDecrease >= configuration.tirThreshold else {
            return nil
        }
        
        return indicators
    }
    
    // MARK: - Helpers
    
    private func hoursSpanned(_ readings: [GlucoseReading]) -> Double {
        guard let first = readings.min(by: { $0.timestamp < $1.timestamp }),
              let last = readings.max(by: { $0.timestamp < $1.timestamp }) else {
            return 0
        }
        return last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
    }
    
    private func daysSpanned(_ readings: [GlucoseReading]) -> Int {
        return Int(hoursSpanned(readings) / 24.0)
    }
    
    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = mean(values)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
    
    private func timeInRange(_ readings: [GlucoseReading], low: Double = 70, high: Double = 180) -> Double {
        guard !readings.isEmpty else { return 0 }
        let inRange = readings.filter { $0.value >= low && $0.value <= high }.count
        return Double(inRange) / Double(readings.count) * 100
    }
    
    private func findOnsetTime(recent: [GlucoseReading], baselineMean: Double) -> Date? {
        let sorted = recent.sorted { $0.timestamp < $1.timestamp }
        let threshold = baselineMean + 25 // 25 mg/dL above baseline
        
        // Find first reading that's elevated
        for reading in sorted {
            if reading.value >= threshold {
                return reading.timestamp
            }
        }
        
        return nil
    }
}

// MARK: - ALG-EFF-033: Illness Agent

/// Recommendations for managing glucose during illness
public struct IllnessRecommendation: Sendable, Codable {
    /// Recommended basal increase (e.g., 1.2 = +20%)
    public let basalMultiplier: Double
    
    /// Recommended target glucose adjustment (negative = lower target)
    public let targetAdjustment: Double
    
    /// Recommended correction factor adjustment (e.g., 0.9 = more aggressive)
    public let correctionFactorMultiplier: Double
    
    /// Alert threshold for ketone checking (mg/dL)
    public let ketoneCheckThreshold: Double
    
    /// Human-readable rationale
    public let rationale: String
    
    /// Confidence in recommendation
    public let confidence: Double
    
    /// Duration to apply recommendation (hours)
    public let suggestedDurationHours: Double
    
    public init(
        basalMultiplier: Double,
        targetAdjustment: Double,
        correctionFactorMultiplier: Double,
        ketoneCheckThreshold: Double,
        rationale: String,
        confidence: Double,
        suggestedDurationHours: Double
    ) {
        self.basalMultiplier = basalMultiplier
        self.targetAdjustment = targetAdjustment
        self.correctionFactorMultiplier = correctionFactorMultiplier
        self.ketoneCheckThreshold = ketoneCheckThreshold
        self.rationale = rationale
        self.confidence = confidence
        self.suggestedDurationHours = suggestedDurationHours
    }
    
    /// Create recommendation from illness indicators
    public static func from(indicators: IllnessIndicators) -> IllnessRecommendation {
        let severity = indicators.severity
        
        let basalIncrease = severity.suggestedBasalIncrease
        let targetDecrease = severity.suggestedTargetDecrease
        
        // More aggressive corrections during illness
        let correctionMultiplier: Double = {
            switch severity {
            case .none: return 1.0
            case .mild: return 0.95
            case .moderate: return 0.9
            case .severe: return 0.85
            }
        }()
        
        let rationale = buildRationale(indicators: indicators, severity: severity)
        
        return IllnessRecommendation(
            basalMultiplier: 1.0 + basalIncrease,
            targetAdjustment: -targetDecrease,
            correctionFactorMultiplier: correctionMultiplier,
            ketoneCheckThreshold: severity == .severe ? 250 : 300,
            rationale: rationale,
            confidence: indicators.confidence,
            suggestedDurationHours: 24 // Re-evaluate after 24 hours
        )
    }
    
    private static func buildRationale(indicators: IllnessIndicators, severity: IllnessSeverity) -> String {
        var parts: [String] = []
        
        parts.append("Illness pattern detected (\(severity.rawValue.lowercased()) severity)")
        
        if indicators.glucoseElevation >= 20 {
            parts.append("glucose elevated \(Int(indicators.glucoseElevation)) mg/dL above baseline")
        }
        
        if indicators.tirDecrease >= 10 {
            parts.append("time in range decreased \(Int(indicators.tirDecrease))%")
        }
        
        if indicators.variabilityIncrease >= 0.15 {
            parts.append("increased glucose variability")
        }
        
        return parts.joined(separator: "; ")
    }
}

/// The illness agent that monitors and recommends adjustments
public actor IllnessAgent {
    
    private let detector: IllnessPatternDetector
    
    private var currentIndicators: IllnessIndicators?
    private var currentRecommendation: IllnessRecommendation?
    private var manualActivation: Date? // User manually said "feeling unwell"
    private var manualSeverity: IllnessSeverity?
    
    public init(detector: IllnessPatternDetector = IllnessPatternDetector()) {
        self.detector = detector
    }
    
    /// Analyze glucose data for illness patterns
    public func analyze(
        recent: [IllnessPatternDetector.GlucoseReading],
        baseline: [IllnessPatternDetector.GlucoseReading]
    ) {
        currentIndicators = detector.analyze(recent: recent, baseline: baseline)
        
        if let indicators = currentIndicators {
            currentRecommendation = IllnessRecommendation.from(indicators: indicators)
        }
    }
    
    /// Get current illness indicators
    public func getIndicators() -> IllnessIndicators? {
        currentIndicators
    }
    
    /// Get current recommendation
    public func getRecommendation() -> IllnessRecommendation? {
        // If manually activated, create recommendation from manual severity
        if let activation = manualActivation, 
           let severity = manualSeverity,
           activation.timeIntervalSinceNow > -86400 { // Within last 24 hours
            return createManualRecommendation(severity: severity)
        }
        
        return currentRecommendation
    }
    
    /// Whether illness mode is active (detected or manual)
    public func isIllnessModeActive() -> Bool {
        if let activation = manualActivation,
           activation.timeIntervalSinceNow > -86400 {
            return true
        }
        
        return currentIndicators?.suggestsIllness ?? false
    }
    
    /// Get current severity
    public func getSeverity() -> IllnessSeverity {
        // Manual takes precedence
        if let activation = manualActivation,
           let severity = manualSeverity,
           activation.timeIntervalSinceNow > -86400 {
            return severity
        }
        
        return currentIndicators?.severity ?? .none
    }
    
    // MARK: - ALG-EFF-034: Quick Action
    
    /// Activate illness mode manually ("feeling unwell")
    public func activateManually(severity: IllnessSeverity = .moderate) {
        manualActivation = Date()
        manualSeverity = severity
    }
    
    /// Deactivate manual illness mode
    public func deactivateManually() {
        manualActivation = nil
        manualSeverity = nil
    }
    
    /// Whether manual illness mode is active
    public func isManuallyActivated() -> Bool {
        guard let activation = manualActivation else { return false }
        return activation.timeIntervalSinceNow > -86400
    }
    
    private func createManualRecommendation(severity: IllnessSeverity) -> IllnessRecommendation {
        IllnessRecommendation(
            basalMultiplier: 1.0 + severity.suggestedBasalIncrease,
            targetAdjustment: -severity.suggestedTargetDecrease,
            correctionFactorMultiplier: severity == .severe ? 0.85 : 0.9,
            ketoneCheckThreshold: 250,
            rationale: "Manually activated illness mode (\(severity.rawValue.lowercased()))",
            confidence: 1.0, // User-reported is high confidence
            suggestedDurationHours: 24
        )
    }
}

// MARK: - Quick Actions

/// Quick action types for illness management
public enum IllnessQuickAction: String, Sendable, Codable, CaseIterable {
    case feelingUnwell = "Feeling Unwell"
    case startingCold = "Starting a Cold"
    case recovering = "Recovering"
    case backToNormal = "Back to Normal"
    
    /// Associated severity
    public var severity: IllnessSeverity {
        switch self {
        case .feelingUnwell: return .moderate
        case .startingCold: return .mild
        case .recovering: return .mild
        case .backToNormal: return .none
        }
    }
    
    /// Icon for UI
    public var icon: String {
        switch self {
        case .feelingUnwell: return "🤒"
        case .startingCold: return "🤧"
        case .recovering: return "😌"
        case .backToNormal: return "😊"
        }
    }
    
    /// Short description
    public var shortDescription: String {
        switch self {
        case .feelingUnwell:
            return "Increase basal +20%, tighter targets"
        case .startingCold:
            return "Increase basal +10%, monitor closely"
        case .recovering:
            return "Keep slight increase, watch for lows"
        case .backToNormal:
            return "Return to normal settings"
        }
    }
}

/// Manager for illness quick actions
public actor IllnessQuickActionManager {
    
    private let agent: IllnessAgent
    private var actionHistory: [QuickActionEvent] = []
    
    public init(agent: IllnessAgent) {
        self.agent = agent
    }
    
    /// Record of a quick action activation
    public struct QuickActionEvent: Sendable {
        public let action: IllnessQuickAction
        public let timestamp: Date
        public let notes: String?
        
        public init(action: IllnessQuickAction, timestamp: Date = Date(), notes: String? = nil) {
            self.action = action
            self.timestamp = timestamp
            self.notes = notes
        }
    }
    
    /// Activate a quick action
    public func activate(_ action: IllnessQuickAction, notes: String? = nil) async {
        actionHistory.append(QuickActionEvent(action: action, timestamp: Date(), notes: notes))
        
        if action == .backToNormal {
            await agent.deactivateManually()
        } else {
            await agent.activateManually(severity: action.severity)
        }
    }
    
    /// Get action history
    public func getHistory() -> [QuickActionEvent] {
        actionHistory
    }
    
    /// Get current active action (most recent)
    public func currentAction() -> IllnessQuickAction? {
        guard let recent = actionHistory.last,
              recent.timestamp.timeIntervalSinceNow > -86400 else {
            return nil
        }
        return recent.action
    }
    
    /// Clear history (for testing)
    public func clearHistory() {
        actionHistory.removeAll()
    }
}

// MARK: - Combined Effect for Algorithm

/// Combined circadian and illness effect for algorithm integration
public struct CircadianIllnessEffect: Sendable {
    /// Basal multiplier (combined)
    public let basalMultiplier: Double
    
    /// Target glucose adjustment (mg/dL)
    public let targetAdjustment: Double
    
    /// Correction factor multiplier
    public let correctionFactorMultiplier: Double
    
    /// Source description
    public let source: String
    
    /// Overall confidence
    public let confidence: Double
    
    public init(
        basalMultiplier: Double,
        targetAdjustment: Double,
        correctionFactorMultiplier: Double,
        source: String,
        confidence: Double
    ) {
        self.basalMultiplier = basalMultiplier
        self.targetAdjustment = targetAdjustment
        self.correctionFactorMultiplier = correctionFactorMultiplier
        self.source = source
        self.confidence = confidence
    }
    
    /// Combine circadian and illness effects
    public static func combine(
        circadian: CircadianEffectModifier?,
        illness: IllnessRecommendation?,
        at date: Date = Date()
    ) -> CircadianIllnessEffect {
        var basalMultiplier = 1.0
        var targetAdjustment = 0.0
        var correctionMultiplier = 1.0
        var sources: [String] = []
        var confidences: [Double] = []
        
        // Apply circadian effect
        if let c = circadian {
            let mult = c.multiplier(for: date)
            if mult != 1.0 {
                basalMultiplier *= mult
                sources.append("Circadian")
                confidences.append(c.confidence)
            }
        }
        
        // Apply illness effect (stacks with circadian)
        if let i = illness {
            basalMultiplier *= i.basalMultiplier
            targetAdjustment += i.targetAdjustment
            correctionMultiplier *= i.correctionFactorMultiplier
            sources.append("Illness")
            confidences.append(i.confidence)
        }
        
        let avgConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        let sourceStr = sources.isEmpty ? "None" : sources.joined(separator: "+")
        
        return CircadianIllnessEffect(
            basalMultiplier: basalMultiplier,
            targetAdjustment: targetAdjustment,
            correctionFactorMultiplier: correctionMultiplier,
            source: sourceStr,
            confidence: avgConfidence
        )
    }
}
