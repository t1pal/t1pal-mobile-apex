// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLConfidence.swift
// T1PalAlgorithm
//
// ML confidence levels and display helpers for recommendations.
// Communicates how confident the ML model is in its predictions.
//
// Trace: ALG-SHADOW-032, PRD-028

import Foundation

// MARK: - Confidence Level

/// Confidence level for ML recommendations
/// Based on model confidence score thresholds from CoreML spec
public enum MLConfidenceLevel: String, Codable, Sendable, CaseIterable {
    /// Model is learning, recommendations are tentative
    /// Confidence < 0.3
    case learning
    
    /// Model has moderate confidence
    /// Confidence 0.3-0.7
    case moderate
    
    /// Model is confident in recommendations
    /// Confidence > 0.7
    case confident
    
    /// Create from numeric confidence score
    public init(score: Double) {
        switch score {
        case ..<0.3:
            self = .learning
        case 0.3..<0.7:
            self = .moderate
        default:
            self = .confident
        }
    }
    
    /// Numeric threshold for this level (lower bound)
    public var threshold: Double {
        switch self {
        case .learning: return 0.0
        case .moderate: return 0.3
        case .confident: return 0.7
        }
    }
    
    /// Whether ML adjustments should be applied at this level
    public var shouldApplyMLAdjustment: Bool {
        switch self {
        case .learning: return false
        case .moderate, .confident: return true
        }
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .learning: return "Learning"
        case .moderate: return "Adapting"
        case .confident: return "Confident"
        }
    }
    
    /// Short description for UI
    public var description: String {
        switch self {
        case .learning:
            return "ML model is still learning your patterns"
        case .moderate:
            return "ML model is adapting to your data"
        case .confident:
            return "ML model is confident in predictions"
        }
    }
    
    /// SF Symbol name for display
    public var symbolName: String {
        switch self {
        case .learning: return "brain"
        case .moderate: return "brain.head.profile"
        case .confident: return "checkmark.seal"
        }
    }
    
    /// Suggested color name (semantic)
    public var colorName: String {
        switch self {
        case .learning: return "gray"
        case .moderate: return "yellow"
        case .confident: return "green"
        }
    }
}

// MARK: - Recommendation Confidence

/// Detailed confidence information for a recommendation
public struct MLRecommendationConfidence: Codable, Sendable {
    /// Raw confidence score from model (0-1)
    public let score: Double
    
    /// Confidence level category
    public let level: MLConfidenceLevel
    
    /// Whether this recommendation used ML adjustments
    public let mlApplied: Bool
    
    /// Reason if ML was not applied
    public let notAppliedReason: NotAppliedReason?
    
    /// Model version that made this recommendation
    public let modelVersion: String?
    
    /// Model age in days
    public let modelAgeDays: Int?
    
    /// Data points used in training
    public let trainingDataPoints: Int?
    
    public init(
        score: Double,
        mlApplied: Bool = true,
        notAppliedReason: NotAppliedReason? = nil,
        modelVersion: String? = nil,
        modelAgeDays: Int? = nil,
        trainingDataPoints: Int? = nil
    ) {
        self.score = max(0, min(1, score))  // Clamp to 0-1
        self.level = MLConfidenceLevel(score: score)
        self.mlApplied = mlApplied
        self.notAppliedReason = notAppliedReason
        self.modelVersion = modelVersion
        self.modelAgeDays = modelAgeDays
        self.trainingDataPoints = trainingDataPoints
    }
    
    /// Create for when ML is not applied
    public static func notApplied(reason: NotAppliedReason) -> MLRecommendationConfidence {
        MLRecommendationConfidence(
            score: 0,
            mlApplied: false,
            notAppliedReason: reason
        )
    }
    
    /// Create for confident model
    public static func confident(
        score: Double,
        modelVersion: String,
        modelAgeDays: Int,
        trainingDataPoints: Int
    ) -> MLRecommendationConfidence {
        MLRecommendationConfidence(
            score: score,
            mlApplied: score >= 0.3,
            modelVersion: modelVersion,
            modelAgeDays: modelAgeDays,
            trainingDataPoints: trainingDataPoints
        )
    }
    
    /// Reasons why ML may not be applied
    public enum NotAppliedReason: String, Codable, Sendable {
        case noModel = "No trained model"
        case modelExpired = "Model expired"
        case lowConfidence = "Confidence too low"
        case insufficientData = "Insufficient training data"
        case safetyOverride = "Safety override active"
        case userDisabled = "User disabled ML"
        case belowTarget = "Below glucose target"
        case exerciseMode = "Exercise mode active"
    }
}

// MARK: - Display Helpers

extension MLRecommendationConfidence {
    
    /// Formatted confidence percentage for display
    public var formattedPercentage: String {
        String(format: "%.0f%%", score * 100)
    }
    
    /// Short status text for UI
    public var statusText: String {
        if !mlApplied {
            return notAppliedReason?.rawValue ?? "ML not applied"
        }
        return level.displayName
    }
    
    /// Detailed status for expanded view
    public var detailedStatus: String {
        var lines: [String] = []
        
        lines.append("Confidence: \(formattedPercentage)")
        lines.append("Status: \(level.displayName)")
        
        if let version = modelVersion {
            lines.append("Model: v\(version)")
        }
        
        if let age = modelAgeDays {
            lines.append("Model age: \(age) days")
        }
        
        if let points = trainingDataPoints {
            lines.append("Training data: \(points) points")
        }
        
        if let reason = notAppliedReason {
            lines.append("Note: \(reason.rawValue)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Whether to show ML indicator in UI
    public var showMLIndicator: Bool {
        mlApplied
    }
    
    /// Accessibility description
    public var accessibilityDescription: String {
        if mlApplied {
            return "ML \(level.displayName.lowercased()) at \(formattedPercentage) confidence"
        } else {
            return "ML not applied: \(notAppliedReason?.rawValue ?? "unknown reason")"
        }
    }
}

// MARK: - Enhanced ML Dosing Result

/// Extended ML dosing result with confidence information
public struct MLDosingResultWithConfidence: Sendable {
    /// Base dosing result
    public let result: MLDosingResult
    
    /// Confidence information
    public let confidence: MLRecommendationConfidence
    
    public init(result: MLDosingResult, confidence: MLRecommendationConfidence) {
        self.result = result
        self.confidence = confidence
    }
    
    /// Create from result with automatic confidence based on model state
    public static func from(
        result: MLDosingResult,
        score: Double,
        modelMetadata: MLModelMetadata?
    ) -> MLDosingResultWithConfidence {
        let confidence: MLRecommendationConfidence
        
        if let metadata = modelMetadata {
            confidence = .confident(
                score: score,
                modelVersion: metadata.version,
                modelAgeDays: Calendar.current.dateComponents(
                    [.day],
                    from: metadata.createdAt,
                    to: Date()
                ).day ?? 0,
                trainingDataPoints: metadata.trainingRows
            )
        } else {
            confidence = .notApplied(reason: .noModel)
        }
        
        return MLDosingResultWithConfidence(result: result, confidence: confidence)
    }
}

// MARK: - Confidence Tracking

/// Tracks confidence over time for analytics
public struct MLConfidenceHistory: Codable, Sendable {
    /// Historical confidence entries
    public private(set) var entries: [ConfidenceEntry]
    
    /// Maximum entries to retain
    public let maxEntries: Int
    
    public init(maxEntries: Int = 288) {  // 24 hours at 5-min intervals
        self.entries = []
        self.maxEntries = maxEntries
    }
    
    /// Record a confidence value
    public mutating func record(_ confidence: MLRecommendationConfidence, at date: Date = Date()) {
        let entry = ConfidenceEntry(
            timestamp: date,
            score: confidence.score,
            level: confidence.level,
            mlApplied: confidence.mlApplied
        )
        entries.append(entry)
        
        // Trim old entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    /// Average confidence over history
    public var averageConfidence: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map { $0.score }.reduce(0, +) / Double(entries.count)
    }
    
    /// Percentage of time ML was applied
    public var mlAppliedPercentage: Double {
        guard !entries.isEmpty else { return 0 }
        let appliedCount = entries.filter { $0.mlApplied }.count
        return Double(appliedCount) / Double(entries.count) * 100
    }
    
    /// Most recent confidence level
    public var currentLevel: MLConfidenceLevel? {
        entries.last?.level
    }
    
    /// Single confidence entry
    public struct ConfidenceEntry: Codable, Sendable {
        public let timestamp: Date
        public let score: Double
        public let level: MLConfidenceLevel
        public let mlApplied: Bool
    }
}
