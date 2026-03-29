// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OverrideLearningReport.swift
// T1PalAlgorithm
//
// Generates learning reports from override session data
// Backlog: ALG-LEARN-004
// Trace: ALG-LEARN (User Hunch → Trained Agent Pipeline)

import Foundation

// MARK: - Override Learning Report (ALG-LEARN-004)

/// Report summarizing what the system has learned about an override
public struct OverrideLearningReport: Codable, Sendable {
    /// Override identifier
    public let overrideId: String
    
    /// Override display name
    public let overrideName: String
    
    /// Total sessions tracked
    public let totalSessions: Int
    
    /// Sessions with complete data
    public let completeSessions: Int
    
    /// Learning status
    public let status: LearningStatus
    
    /// Average outcome metrics
    public let averageOutcome: AverageOutcome?
    
    /// Settings insights (what works best)
    public let settingsInsights: SettingsInsights?
    
    /// Context insights (when works best)
    public let contextInsights: ContextInsights?
    
    /// Recommendations for improvement
    public let recommendations: [Recommendation]
    
    /// Last updated
    public let generatedAt: Date
    
    public init(
        overrideId: String,
        overrideName: String,
        totalSessions: Int,
        completeSessions: Int,
        status: LearningStatus,
        averageOutcome: AverageOutcome? = nil,
        settingsInsights: SettingsInsights? = nil,
        contextInsights: ContextInsights? = nil,
        recommendations: [Recommendation] = [],
        generatedAt: Date = Date()
    ) {
        self.overrideId = overrideId
        self.overrideName = overrideName
        self.totalSessions = totalSessions
        self.completeSessions = completeSessions
        self.status = status
        self.averageOutcome = averageOutcome
        self.settingsInsights = settingsInsights
        self.contextInsights = contextInsights
        self.recommendations = recommendations
        self.generatedAt = generatedAt
    }
}

// MARK: - Learning Status

/// Status of learning for an override
public enum LearningStatus: String, Codable, Sendable {
    /// Just started - not enough data
    case initial = "initial"  // < 3 sessions
    
    /// Learning - gathering data
    case learning = "learning"  // 3-5 sessions
    
    /// Trained - have enough data for patterns
    case trained = "trained"  // 5+ sessions
    
    /// Confident - high confidence patterns
    case confident = "confident"  // 10+ sessions with consistent results
    
    /// Text description
    public var description: String {
        switch self {
        case .initial: return "Just getting started"
        case .learning: return "Learning your patterns"
        case .trained: return "Ready to suggest"
        case .confident: return "Confident patterns"
        }
    }
    
    /// Sessions needed for next level
    public var sessionsForNextLevel: Int {
        switch self {
        case .initial: return 3
        case .learning: return 5
        case .trained: return 10
        case .confident: return 0  // Already at max
        }
    }
    
    /// Create status from session count
    public static func from(sessionCount: Int) -> LearningStatus {
        switch sessionCount {
        case 0..<3: return .initial
        case 3..<5: return .learning
        case 5..<10: return .trained
        default: return .confident
        }
    }
}

// MARK: - Average Outcome

/// Aggregated outcome metrics across sessions
public struct AverageOutcome: Codable, Sendable {
    /// Average time in range
    public let timeInRange: Double
    
    /// Standard deviation of TIR
    public let timeInRangeStdDev: Double
    
    /// Average hypo events per session
    public let hypoEventsPerSession: Double
    
    /// Average hyper events per session
    public let hyperEventsPerSession: Double
    
    /// Average success score
    public let successScore: Double
    
    /// Trend direction (improving, stable, declining)
    public let trend: Trend
    
    public enum Trend: String, Codable, Sendable {
        case improving = "improving"
        case stable = "stable"
        case declining = "declining"
        case unknown = "unknown"
    }
    
    public init(
        timeInRange: Double,
        timeInRangeStdDev: Double,
        hypoEventsPerSession: Double,
        hyperEventsPerSession: Double,
        successScore: Double,
        trend: Trend
    ) {
        self.timeInRange = timeInRange
        self.timeInRangeStdDev = timeInRangeStdDev
        self.hypoEventsPerSession = hypoEventsPerSession
        self.hyperEventsPerSession = hyperEventsPerSession
        self.successScore = successScore
        self.trend = trend
    }
}

// MARK: - Settings Insights

/// Insights about override settings effectiveness
public struct SettingsInsights: Codable, Sendable {
    /// Current settings being used
    public let currentSettings: OverrideSettings
    
    /// Optimal basal multiplier (learned)
    public let optimalBasalMultiplier: Double?
    
    /// Optimal ISF multiplier (learned)
    public let optimalISFMultiplier: Double?
    
    /// Whether current settings are optimal
    public let settingsOptimal: Bool
    
    /// Suggested adjustments
    public let suggestedAdjustments: [String]
    
    public init(
        currentSettings: OverrideSettings,
        optimalBasalMultiplier: Double? = nil,
        optimalISFMultiplier: Double? = nil,
        settingsOptimal: Bool = true,
        suggestedAdjustments: [String] = []
    ) {
        self.currentSettings = currentSettings
        self.optimalBasalMultiplier = optimalBasalMultiplier
        self.optimalISFMultiplier = optimalISFMultiplier
        self.settingsOptimal = settingsOptimal
        self.suggestedAdjustments = suggestedAdjustments
    }
}

// MARK: - Context Insights

/// Insights about when the override works best
public struct ContextInsights: Codable, Sendable {
    /// Best time of day for this override
    public let bestTimeOfDay: OverrideContext.TimeOfDay?
    
    /// Best days of week (1=Sunday, 7=Saturday)
    public let bestDaysOfWeek: [Int]
    
    /// Average duration that works best
    public let optimalDuration: TimeInterval?
    
    /// Pre-conditions that correlate with good outcomes
    public let goodPreconditions: [String]
    
    /// Pre-conditions that correlate with poor outcomes
    public let badPreconditions: [String]
    
    public init(
        bestTimeOfDay: OverrideContext.TimeOfDay? = nil,
        bestDaysOfWeek: [Int] = [],
        optimalDuration: TimeInterval? = nil,
        goodPreconditions: [String] = [],
        badPreconditions: [String] = []
    ) {
        self.bestTimeOfDay = bestTimeOfDay
        self.bestDaysOfWeek = bestDaysOfWeek
        self.optimalDuration = optimalDuration
        self.goodPreconditions = goodPreconditions
        self.badPreconditions = badPreconditions
    }
}

// MARK: - Recommendation

/// A specific recommendation based on learning
public struct Recommendation: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Recommendation type
    public let type: RecommendationType
    
    /// Human-readable message
    public let message: String
    
    /// Confidence level (0-1)
    public let confidence: Double
    
    /// Evidence supporting this recommendation
    public let evidence: String?
    
    public enum RecommendationType: String, Codable, Sendable {
        case adjustBasal = "adjustBasal"
        case adjustISF = "adjustISF"
        case adjustCR = "adjustCR"
        case adjustDuration = "adjustDuration"
        case adjustTiming = "adjustTiming"
        case keepSettings = "keepSettings"
        case needMoreData = "needMoreData"
    }
    
    public init(
        id: UUID = UUID(),
        type: RecommendationType,
        message: String,
        confidence: Double,
        evidence: String? = nil
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.confidence = confidence
        self.evidence = evidence
    }
}

// MARK: - Report Generator

/// Generates learning reports from override sessions
public struct OverrideLearningReportGenerator {
    
    public init() {}
    
    /// Generate a report for an override
    public func generateReport(
        overrideId: String,
        overrideName: String,
        sessions: [OverrideSession]
    ) -> OverrideLearningReport {
        let completeSessions = sessions.filter { $0.isComplete }
        let status = LearningStatus.from(sessionCount: completeSessions.count)
        
        // Calculate averages if we have enough data
        let averageOutcome: AverageOutcome?
        let settingsInsights: SettingsInsights?
        let contextInsights: ContextInsights?
        var recommendations: [Recommendation] = []
        
        if completeSessions.count >= 3 {
            averageOutcome = calculateAverageOutcome(from: completeSessions)
            settingsInsights = analyzeSettings(from: completeSessions)
            contextInsights = analyzeContext(from: completeSessions)
            recommendations = generateRecommendations(
                sessions: completeSessions,
                averageOutcome: averageOutcome,
                settingsInsights: settingsInsights
            )
        } else {
            averageOutcome = nil
            settingsInsights = nil
            contextInsights = nil
            recommendations = [
                Recommendation(
                    type: .needMoreData,
                    message: "Track \(3 - completeSessions.count) more sessions to start learning",
                    confidence: 1.0
                )
            ]
        }
        
        return OverrideLearningReport(
            overrideId: overrideId,
            overrideName: overrideName,
            totalSessions: sessions.count,
            completeSessions: completeSessions.count,
            status: status,
            averageOutcome: averageOutcome,
            settingsInsights: settingsInsights,
            contextInsights: contextInsights,
            recommendations: recommendations
        )
    }
    
    // MARK: - Private Helpers
    
    private func calculateAverageOutcome(from sessions: [OverrideSession]) -> AverageOutcome {
        let outcomes = sessions.compactMap { $0.outcome }
        guard !outcomes.isEmpty else {
            return AverageOutcome(
                timeInRange: 0,
                timeInRangeStdDev: 0,
                hypoEventsPerSession: 0,
                hyperEventsPerSession: 0,
                successScore: 0,
                trend: .unknown
            )
        }
        
        let tirValues = outcomes.map { $0.timeInRange }
        let avgTIR = tirValues.reduce(0, +) / Double(tirValues.count)
        
        // Calculate standard deviation
        let variance = tirValues.map { pow($0 - avgTIR, 2) }.reduce(0, +) / Double(tirValues.count)
        let stdDev = sqrt(variance)
        
        let avgHypos = Double(outcomes.map { $0.hypoEvents }.reduce(0, +)) / Double(outcomes.count)
        let avgHypers = Double(outcomes.map { $0.hyperEvents }.reduce(0, +)) / Double(outcomes.count)
        let avgScore = outcomes.map { $0.successScore }.reduce(0, +) / Double(outcomes.count)
        
        // Calculate trend (compare recent vs older)
        let trend: AverageOutcome.Trend
        if outcomes.count >= 5 {
            let recent = outcomes.suffix(3).map { $0.successScore }.reduce(0, +) / 3.0
            let older = outcomes.prefix(3).map { $0.successScore }.reduce(0, +) / 3.0
            if recent > older + 0.05 {
                trend = .improving
            } else if recent < older - 0.05 {
                trend = .declining
            } else {
                trend = .stable
            }
        } else {
            trend = .unknown
        }
        
        return AverageOutcome(
            timeInRange: avgTIR,
            timeInRangeStdDev: stdDev,
            hypoEventsPerSession: avgHypos,
            hyperEventsPerSession: avgHypers,
            successScore: avgScore,
            trend: trend
        )
    }
    
    private func analyzeSettings(from sessions: [OverrideSession]) -> SettingsInsights? {
        guard let firstSession = sessions.first else { return nil }
        
        let settings = firstSession.settings
        let outcomes = sessions.compactMap { $0.outcome }
        
        // Group by basal multiplier and find best performing
        var adjustments: [String] = []
        
        // Check if current settings are working well
        let avgSuccess = outcomes.map { $0.successScore }.reduce(0, +) / Double(outcomes.count)
        let settingsOptimal = avgSuccess >= 0.7
        
        // Generate suggestions
        let avgHypos = Double(outcomes.map { $0.hypoEvents }.reduce(0, +)) / Double(outcomes.count)
        if avgHypos > 0.5 && settings.basalMultiplier < 0.9 {
            adjustments.append("Consider reducing basal reduction (current: \(Int((1 - settings.basalMultiplier) * 100))%)")
        }
        
        let avgHypers = Double(outcomes.map { $0.hyperEvents }.reduce(0, +)) / Double(outcomes.count)
        if avgHypers > 1.0 && settings.basalMultiplier > 0.5 {
            adjustments.append("Consider increasing basal reduction")
        }
        
        return SettingsInsights(
            currentSettings: settings,
            optimalBasalMultiplier: settingsOptimal ? settings.basalMultiplier : nil,
            optimalISFMultiplier: settingsOptimal ? settings.isfMultiplier : nil,
            settingsOptimal: settingsOptimal,
            suggestedAdjustments: adjustments
        )
    }
    
    private func analyzeContext(from sessions: [OverrideSession]) -> ContextInsights {
        // Group sessions by time of day and find best performing
        var timeOfDayScores: [OverrideContext.TimeOfDay: [Double]] = [:]
        var dayOfWeekScores: [Int: [Double]] = [:]
        var durations: [TimeInterval] = []
        
        for session in sessions {
            guard let outcome = session.outcome else { continue }
            
            timeOfDayScores[session.context.timeOfDay, default: []].append(outcome.successScore)
            dayOfWeekScores[session.context.dayOfWeek, default: []].append(outcome.successScore)
            
            if let duration = session.duration {
                durations.append(duration)
            }
        }
        
        // Find best time of day
        let bestTimeOfDay = timeOfDayScores
            .filter { $0.value.count >= 2 }
            .max { $0.value.reduce(0, +) / Double($0.value.count) < $1.value.reduce(0, +) / Double($1.value.count) }?
            .key
        
        // Find best days
        let bestDays = dayOfWeekScores
            .filter { $0.value.count >= 2 }
            .filter { $0.value.reduce(0, +) / Double($0.value.count) >= 0.7 }
            .map { $0.key }
            .sorted()
        
        // Calculate optimal duration
        let optimalDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        
        return ContextInsights(
            bestTimeOfDay: bestTimeOfDay,
            bestDaysOfWeek: bestDays,
            optimalDuration: optimalDuration
        )
    }
    
    private func generateRecommendations(
        sessions: [OverrideSession],
        averageOutcome: AverageOutcome?,
        settingsInsights: SettingsInsights?
    ) -> [Recommendation] {
        var recommendations: [Recommendation] = []
        
        guard let outcome = averageOutcome, let settings = settingsInsights else {
            return recommendations
        }
        
        // Check if settings are working well
        if settings.settingsOptimal && outcome.successScore >= 0.75 {
            recommendations.append(Recommendation(
                type: .keepSettings,
                message: "Your current settings are working well!",
                confidence: min(0.95, outcome.successScore),
                evidence: "TIR: \(Int(outcome.timeInRange))%, Success: \(Int(outcome.successScore * 100))%"
            ))
        } else {
            // Add adjustment recommendations
            for adjustment in settings.suggestedAdjustments {
                recommendations.append(Recommendation(
                    type: .adjustBasal,
                    message: adjustment,
                    confidence: 0.7
                ))
            }
        }
        
        // Trend-based recommendations
        switch outcome.trend {
        case .improving:
            recommendations.append(Recommendation(
                type: .keepSettings,
                message: "Results are improving - keep going!",
                confidence: 0.8
            ))
        case .declining:
            recommendations.append(Recommendation(
                type: .needMoreData,
                message: "Results are declining - consider reviewing recent sessions",
                confidence: 0.7
            ))
        default:
            break
        }
        
        return recommendations
    }
}
