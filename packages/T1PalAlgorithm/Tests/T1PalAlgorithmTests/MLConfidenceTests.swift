// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLConfidenceTests.swift
// T1PalAlgorithm
//
// Tests for ML confidence display types.
//
// Trace: ALG-SHADOW-032

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("ML Confidence")
struct MLConfidenceTests {
    
    // MARK: - Confidence Level Tests
    
    @Suite("Confidence Level")
    struct ConfidenceLevel {
        @Test("From score - learning")
        func fromScoreLearning() {
            #expect(MLConfidenceLevel(score: 0.0) == .learning)
            #expect(MLConfidenceLevel(score: 0.1) == .learning)
            #expect(MLConfidenceLevel(score: 0.29) == .learning)
        }
        
        @Test("From score - moderate")
        func fromScoreModerate() {
            #expect(MLConfidenceLevel(score: 0.3) == .moderate)
            #expect(MLConfidenceLevel(score: 0.5) == .moderate)
            #expect(MLConfidenceLevel(score: 0.69) == .moderate)
        }
        
        @Test("From score - confident")
        func fromScoreConfident() {
            #expect(MLConfidenceLevel(score: 0.7) == .confident)
            #expect(MLConfidenceLevel(score: 0.85) == .confident)
            #expect(MLConfidenceLevel(score: 1.0) == .confident)
        }
        
        @Test("Thresholds")
        func thresholds() {
            #expect(MLConfidenceLevel.learning.threshold == 0.0)
            #expect(MLConfidenceLevel.moderate.threshold == 0.3)
            #expect(MLConfidenceLevel.confident.threshold == 0.7)
        }
        
        @Test("Should apply ML adjustment")
        func shouldApplyMLAdjustment() {
            #expect(!MLConfidenceLevel.learning.shouldApplyMLAdjustment)
            #expect(MLConfidenceLevel.moderate.shouldApplyMLAdjustment)
            #expect(MLConfidenceLevel.confident.shouldApplyMLAdjustment)
        }
        
        @Test("Display names")
        func displayNames() {
            #expect(MLConfidenceLevel.learning.displayName == "Learning")
            #expect(MLConfidenceLevel.moderate.displayName == "Adapting")
            #expect(MLConfidenceLevel.confident.displayName == "Confident")
        }
        
        @Test("Symbols")
        func symbols() {
            #expect(MLConfidenceLevel.learning.symbolName == "brain")
            #expect(MLConfidenceLevel.moderate.symbolName == "brain.head.profile")
            #expect(MLConfidenceLevel.confident.symbolName == "checkmark.seal")
        }
        
        @Test("Colors")
        func colors() {
            #expect(MLConfidenceLevel.learning.colorName == "gray")
            #expect(MLConfidenceLevel.moderate.colorName == "yellow")
            #expect(MLConfidenceLevel.confident.colorName == "green")
        }
    }
    
    // MARK: - Recommendation Confidence Tests
    
    @Suite("Recommendation Confidence")
    struct RecommendationConfidence {
        @Test("Init")
        func initTest() {
            let confidence = MLRecommendationConfidence(score: 0.85)
            
            #expect(confidence.score == 0.85)
            #expect(confidence.level == .confident)
            #expect(confidence.mlApplied)
            #expect(confidence.notAppliedReason == nil)
        }
        
        @Test("Clamp")
        func clamp() {
            // Test clamping to 0-1 range
            let low = MLRecommendationConfidence(score: -0.5)
            #expect(low.score == 0.0)
            
            let high = MLRecommendationConfidence(score: 1.5)
            #expect(high.score == 1.0)
        }
        
        @Test("Not applied")
        func notApplied() {
            let confidence = MLRecommendationConfidence.notApplied(reason: .noModel)
            
            #expect(confidence.score == 0)
            #expect(confidence.level == .learning)
            #expect(!confidence.mlApplied)
            #expect(confidence.notAppliedReason == .noModel)
        }
        
        @Test("Confident factory")
        func confidentFactory() {
            let confidence = MLRecommendationConfidence.confident(
                score: 0.9,
                modelVersion: "1.0.5",
                modelAgeDays: 14,
                trainingDataPoints: 4032
            )
            
            #expect(confidence.score == 0.9)
            #expect(confidence.level == .confident)
            #expect(confidence.mlApplied)
            #expect(confidence.modelVersion == "1.0.5")
            #expect(confidence.modelAgeDays == 14)
            #expect(confidence.trainingDataPoints == 4032)
        }
    }
    
    // MARK: - Display Helper Tests
    
    @Suite("Display Helpers")
    struct DisplayHelpers {
        @Test("Formatted percentage")
        func formattedPercentage() {
            let confidence = MLRecommendationConfidence(score: 0.856)
            #expect(confidence.formattedPercentage == "86%")
        }
        
        @Test("Status text ML applied")
        func statusTextMLApplied() {
            let confidence = MLRecommendationConfidence(score: 0.75)
            #expect(confidence.statusText == "Confident")
        }
        
        @Test("Status text not applied")
        func statusTextNotApplied() {
            let confidence = MLRecommendationConfidence.notApplied(reason: .modelExpired)
            #expect(confidence.statusText == "Model expired")
        }
        
        @Test("Show ML indicator")
        func showMLIndicator() {
            let applied = MLRecommendationConfidence(score: 0.5)
            #expect(applied.showMLIndicator)
            
            let notApplied = MLRecommendationConfidence.notApplied(reason: .lowConfidence)
            #expect(!notApplied.showMLIndicator)
        }
        
        @Test("Accessibility description")
        func accessibilityDescription() {
            let confident = MLRecommendationConfidence(score: 0.8)
            #expect(confident.accessibilityDescription.contains("confident"))
            #expect(confident.accessibilityDescription.contains("80%"))
            
            let notApplied = MLRecommendationConfidence.notApplied(reason: .exerciseMode)
            #expect(notApplied.accessibilityDescription.contains("Exercise mode"))
        }
    }
    
    // MARK: - Not Applied Reason Tests
    
    @Suite("Not Applied Reasons")
    struct NotAppliedReasons {
        @Test("Raw values")
        func rawValues() {
            #expect(MLRecommendationConfidence.NotAppliedReason.noModel.rawValue == "No trained model")
            #expect(MLRecommendationConfidence.NotAppliedReason.modelExpired.rawValue == "Model expired")
            #expect(MLRecommendationConfidence.NotAppliedReason.lowConfidence.rawValue == "Confidence too low")
            #expect(MLRecommendationConfidence.NotAppliedReason.insufficientData.rawValue == "Insufficient training data")
            #expect(MLRecommendationConfidence.NotAppliedReason.safetyOverride.rawValue == "Safety override active")
            #expect(MLRecommendationConfidence.NotAppliedReason.userDisabled.rawValue == "User disabled ML")
            #expect(MLRecommendationConfidence.NotAppliedReason.belowTarget.rawValue == "Below glucose target")
            #expect(MLRecommendationConfidence.NotAppliedReason.exerciseMode.rawValue == "Exercise mode active")
        }
    }
    
    // MARK: - Confidence History Tests
    
    @Suite("Confidence History")
    struct ConfidenceHistoryTests {
        @Test("Record")
        func record() {
            var history = MLConfidenceHistory()
            
            history.record(MLRecommendationConfidence(score: 0.5))
            history.record(MLRecommendationConfidence(score: 0.7))
            history.record(MLRecommendationConfidence(score: 0.9))
            
            #expect(history.entries.count == 3)
        }
        
        @Test("Max entries")
        func maxEntries() {
            var history = MLConfidenceHistory(maxEntries: 5)
            
            for i in 0..<10 {
                history.record(MLRecommendationConfidence(score: Double(i) / 10))
            }
            
            #expect(history.entries.count == 5)
            // Should have the last 5 entries
            #expect(abs(history.entries.first!.score - 0.5) < 0.01)
        }
        
        @Test("Average confidence")
        func averageConfidence() {
            var history = MLConfidenceHistory()
            
            history.record(MLRecommendationConfidence(score: 0.5))
            history.record(MLRecommendationConfidence(score: 0.7))
            history.record(MLRecommendationConfidence(score: 0.8))
            
            #expect(abs(history.averageConfidence - 0.666) < 0.01)
        }
        
        @Test("ML applied percentage")
        func mlAppliedPercentage() {
            var history = MLConfidenceHistory()
            
            // 3 applied (>= 0.3), 1 not applied (< 0.3)
            history.record(MLRecommendationConfidence(score: 0.2, mlApplied: false))
            history.record(MLRecommendationConfidence(score: 0.5, mlApplied: true))
            history.record(MLRecommendationConfidence(score: 0.7, mlApplied: true))
            history.record(MLRecommendationConfidence(score: 0.9, mlApplied: true))
            
            #expect(abs(history.mlAppliedPercentage - 75.0) < 0.1)
        }
        
        @Test("Current level")
        func currentLevel() {
            var history = MLConfidenceHistory()
            
            #expect(history.currentLevel == nil)
            
            history.record(MLRecommendationConfidence(score: 0.85))
            #expect(history.currentLevel == .confident)
        }
    }
    
    // MARK: - Enhanced Result Tests
    
    @Suite("Enhanced Results")
    struct EnhancedResults {
        @Test("ML dosing result with confidence")
        func mlDosingResultWithConfidence() {
            let result = MLDosingResult(
                tempBasalRate: 1.5,
                scalingFactor: 1.2,
                reason: "Dynamic ISF"
            )
            let confidence = MLRecommendationConfidence(score: 0.8)
            
            let enhanced = MLDosingResultWithConfidence(result: result, confidence: confidence)
            
            #expect(enhanced.result.tempBasalRate == 1.5)
            #expect(enhanced.confidence.score == 0.8)
        }
    }
}
