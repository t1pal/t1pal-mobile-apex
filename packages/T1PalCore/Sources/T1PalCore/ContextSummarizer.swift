// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ContextSummarizer.swift - Summarizes metabolic context to text
// Part of T1PalCore
// Trace: NARRATIVE-002

import Foundation

// MARK: - Context Summarizer Protocol

/// Protocol for summarizing metabolic context into human-readable text
/// Trace: NARRATIVE-002
public protocol ContextSummarizer: Sendable {
    /// Generate a one-line summary
    func summarize(_ context: MetabolicContext) -> String
    
    /// Generate a detailed multi-line summary
    func detailedSummary(_ context: MetabolicContext) -> [String]
    
    /// Generate an accessibility-friendly summary
    func accessibilitySummary(_ context: MetabolicContext) -> String
}

// MARK: - Default Context Summarizer

/// Default implementation of ContextSummarizer
public struct DefaultContextSummarizer: ContextSummarizer {
    
    public init() {}
    
    public func summarize(_ context: MetabolicContext) -> String {
        let value = Int(context.glucose)
        let trend = trendDescription(for: context.rateOfChange)
        let assessment = assessmentWord(for: context.assessment)
        
        if let trend = trend {
            return "\(value) mg/dL, \(trend), \(assessment)"
        } else {
            return "\(value) mg/dL, \(assessment)"
        }
    }
    
    public func detailedSummary(_ context: MetabolicContext) -> [String] {
        var lines: [String] = []
        
        // Line 1: Glucose value and trend
        let value = Int(context.glucose)
        let trendArrow = self.trendArrow(for: context.rateOfChange)
        lines.append("Glucose: \(value) \(trendArrow)")
        
        // Line 2: IOB if present
        if let iob = context.iob {
            lines.append(String(format: "Insulin on board: %.1f U", iob))
        }
        
        // Line 3: COB if present
        if let cob = context.cob {
            lines.append(String(format: "Carbs on board: %.0f g", cob))
        }
        
        // Line 4: Data age
        if context.readingAge > 60 {
            let minutes = Int(context.readingAge / 60)
            lines.append("Last reading: \(minutes) min ago")
        }
        
        // Line 5: Assessment
        lines.append("Status: \(context.assessment.rawValue.capitalized)")
        
        return lines
    }
    
    public func accessibilitySummary(_ context: MetabolicContext) -> String {
        let value = Int(context.glucose)
        let trend = accessibleTrend(for: context.rateOfChange)
        let assessment = accessibleAssessment(for: context.assessment)
        
        var summary = "Glucose is \(value) milligrams per deciliter"
        
        if let trend = trend {
            summary += ", \(trend)"
        }
        
        summary += ". \(assessment)"
        
        if let iob = context.iob, iob > 0.1 {
            summary += String(format: " You have %.1f units of insulin on board.", iob)
        }
        
        if let cob = context.cob, cob > 5 {
            summary += " About \(Int(cob)) grams of carbs are being absorbed."
        }
        
        return summary
    }
    
    // MARK: - Private Helpers
    
    private func trendDescription(for rate: Double?) -> String? {
        guard let rate = rate else { return nil }
        switch rate {
        case ..<(-2): return "falling fast"
        case ..<(-1): return "falling"
        case (-1)...1: return "steady"
        case 1..<2: return "rising"
        default: return "rising fast"
        }
    }
    
    private func trendArrow(for rate: Double?) -> String {
        guard let rate = rate else { return "→" }
        switch rate {
        case ..<(-2): return "⇊"
        case ..<(-1): return "↓"
        case (-1)...1: return "→"
        case 1..<2: return "↑"
        default: return "⇈"
        }
    }
    
    private func accessibleTrend(for rate: Double?) -> String? {
        guard let rate = rate else { return nil }
        switch rate {
        case ..<(-2): return "and falling rapidly"
        case ..<(-1): return "and falling"
        case (-1)...1: return "and stable"
        case 1..<2: return "and rising"
        default: return "and rising rapidly"
        }
    }
    
    private func assessmentWord(for assessment: MetabolicContext.Assessment) -> String {
        switch assessment {
        case .urgentLow: return "very low"
        case .low: return "low"
        case .inRange: return "in range"
        case .high: return "high"
        case .veryHigh: return "very high"
        }
    }
    
    private func accessibleAssessment(for assessment: MetabolicContext.Assessment) -> String {
        switch assessment {
        case .urgentLow: return "This is very low and needs immediate attention."
        case .low: return "This is low. Consider having a snack."
        case .inRange: return "This is in your target range."
        case .high: return "This is above your target range."
        case .veryHigh: return "This is very high. Consider a correction."
        }
    }
}

// MARK: - Convenience Extensions

extension MetabolicContext {
    /// Get a quick summary using the default summarizer
    public var summary: String {
        DefaultContextSummarizer().summarize(self)
    }
    
    /// Get an accessibility summary using the default summarizer
    public var accessibleDescription: String {
        DefaultContextSummarizer().accessibilitySummary(self)
    }
}
