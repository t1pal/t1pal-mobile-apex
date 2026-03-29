// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EffectModifier.swift
// T1PalAlgorithm
//
// Unified modifier for ISF, CR, and basal rate adjustments
// Backlog: ALG-EFF-002
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md

import Foundation

// MARK: - Effect Modifier

/// Unified modifier struct for physiological effect adjustments
///
/// Effect modifiers adjust algorithm inputs (ISF, CR, basal) rather than outputs.
/// This ensures base algorithm safety logic always applies.
///
/// Safety bounds:
/// - ISF: 0.5-2.0 (50% to 200% of baseline)
/// - CR: 0.7-1.5 (70% to 150% of baseline)
/// - Basal: 0.5-2.0 (50% to 200% of baseline)
///
/// Example usage:
/// ```swift
/// let exerciseModifier = EffectModifier(
///     isfMultiplier: 0.8,    // 20% more sensitive
///     crMultiplier: 0.9,     // 10% more responsive to carbs
///     basalMultiplier: 0.7,  // 30% less basal
///     source: "exercise",
///     confidence: 0.75
/// )
/// ```
public struct EffectModifier: Codable, Sendable, Equatable {
    
    // MARK: - Safety Bounds
    
    /// Minimum ISF multiplier (more sensitive)
    public static let minISFMultiplier: Double = 0.5
    /// Maximum ISF multiplier (less sensitive)
    public static let maxISFMultiplier: Double = 2.0
    
    /// Minimum CR multiplier
    public static let minCRMultiplier: Double = 0.7
    /// Maximum CR multiplier
    public static let maxCRMultiplier: Double = 1.5
    
    /// Minimum basal multiplier
    public static let minBasalMultiplier: Double = 0.5
    /// Maximum basal multiplier
    public static let maxBasalMultiplier: Double = 2.0
    
    // MARK: - Properties
    
    /// Insulin Sensitivity Factor multiplier
    /// < 1.0 = more sensitive (less insulin needed per mg/dL correction)
    /// > 1.0 = less sensitive (more insulin needed per mg/dL correction)
    public let isfMultiplier: Double
    
    /// Carb Ratio multiplier
    /// < 1.0 = more responsive to carbs (less insulin per gram)
    /// > 1.0 = less responsive to carbs (more insulin per gram)
    public let crMultiplier: Double
    
    /// Basal rate multiplier
    /// < 1.0 = less basal insulin
    /// > 1.0 = more basal insulin
    public let basalMultiplier: Double
    
    /// Agent or source that produced this modifier
    public let source: String
    
    /// Confidence in this modifier (0.0-1.0)
    public let confidence: Double
    
    /// When this modifier was created
    public let timestamp: Date
    
    /// How long this modifier remains valid
    public let validUntil: Date
    
    /// Optional human-readable reason
    public let reason: String?
    
    // MARK: - Initialization
    
    public init(
        isfMultiplier: Double = 1.0,
        crMultiplier: Double = 1.0,
        basalMultiplier: Double = 1.0,
        source: String,
        confidence: Double = 0.7,
        timestamp: Date = Date(),
        validUntil: Date? = nil,
        reason: String? = nil
    ) {
        // Apply safety bounds
        self.isfMultiplier = min(max(isfMultiplier, Self.minISFMultiplier), Self.maxISFMultiplier)
        self.crMultiplier = min(max(crMultiplier, Self.minCRMultiplier), Self.maxCRMultiplier)
        self.basalMultiplier = min(max(basalMultiplier, Self.minBasalMultiplier), Self.maxBasalMultiplier)
        
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.timestamp = timestamp
        self.validUntil = validUntil ?? timestamp.addingTimeInterval(5 * 60) // Default 5 min
        self.reason = reason
    }
    
    // MARK: - Computed Properties
    
    /// Whether this modifier is currently valid
    public var isValid: Bool {
        Date() <= validUntil
    }
    
    /// Whether this modifier represents no change (all multipliers ~1.0)
    public var isIdentity: Bool {
        abs(isfMultiplier - 1.0) < 0.01 &&
        abs(crMultiplier - 1.0) < 0.01 &&
        abs(basalMultiplier - 1.0) < 0.01
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        validUntil.timeIntervalSince(timestamp)
    }
    
    // MARK: - Presets
    
    /// Identity modifier (no change)
    public static let identity = EffectModifier(source: "identity", confidence: 1.0)
    
    /// Exercise preset: increased sensitivity
    public static func exercise(intensity: ExerciseIntensity = .moderate) -> EffectModifier {
        switch intensity {
        case .light:
            return EffectModifier(
                isfMultiplier: 0.9,
                crMultiplier: 0.95,
                basalMultiplier: 0.85,
                source: "exercise.light",
                confidence: 0.7,
                reason: "Light exercise: mild sensitivity increase"
            )
        case .moderate:
            return EffectModifier(
                isfMultiplier: 0.75,
                crMultiplier: 0.85,
                basalMultiplier: 0.7,
                source: "exercise.moderate",
                confidence: 0.75,
                reason: "Moderate exercise: sensitivity increase"
            )
        case .intense:
            return EffectModifier(
                isfMultiplier: 0.6,
                crMultiplier: 0.7,
                basalMultiplier: 0.5,
                source: "exercise.intense",
                confidence: 0.8,
                reason: "Intense exercise: significant sensitivity increase"
            )
        }
    }
    
    /// Illness preset: decreased sensitivity
    public static let illness = EffectModifier(
        isfMultiplier: 1.3,
        crMultiplier: 1.2,
        basalMultiplier: 1.3,
        source: "illness",
        confidence: 0.6,
        reason: "Illness: reduced sensitivity"
    )
    
    /// Menstrual cycle presets
    public static func menstrualPhase(_ phase: MenstrualPhase) -> EffectModifier {
        switch phase {
        case .follicular:
            return EffectModifier(
                isfMultiplier: 0.9,
                source: "cycle.follicular",
                confidence: 0.6,
                reason: "Follicular phase: higher sensitivity"
            )
        case .ovulation:
            return EffectModifier(
                source: "cycle.ovulation",
                confidence: 0.5,
                reason: "Ovulation: variable sensitivity"
            )
        case .luteal:
            return EffectModifier(
                isfMultiplier: 1.15,
                basalMultiplier: 1.1,
                source: "cycle.luteal",
                confidence: 0.65,
                reason: "Luteal phase: reduced sensitivity"
            )
        case .menstrual:
            return EffectModifier(
                source: "cycle.menstrual",
                confidence: 0.7,
                reason: "Menstrual: baseline sensitivity"
            )
        }
    }
    
    // MARK: - Supporting Types
    
    public enum ExerciseIntensity: String, Codable, Sendable {
        case light
        case moderate
        case intense
    }
    
    public enum MenstrualPhase: String, Codable, Sendable {
        case follicular
        case ovulation
        case luteal
        case menstrual
    }
}

// MARK: - Effect Modifier Composition

extension EffectModifier {
    /// Compose two modifiers by multiplying their factors
    ///
    /// When multiple effects are active, their multipliers combine multiplicatively.
    /// Safety bounds are enforced on the combined result.
    ///
    /// - Parameter other: Another modifier to combine with
    /// - Returns: Combined modifier with multiplied factors
    public func combined(with other: EffectModifier) -> EffectModifier {
        EffectModifier(
            isfMultiplier: isfMultiplier * other.isfMultiplier,
            crMultiplier: crMultiplier * other.crMultiplier,
            basalMultiplier: basalMultiplier * other.basalMultiplier,
            source: "\(source)+\(other.source)",
            confidence: min(confidence, other.confidence), // Use lower confidence
            timestamp: max(timestamp, other.timestamp),
            validUntil: min(validUntil, other.validUntil),
            reason: composeReasons(reason, other.reason)
        )
    }
    
    /// Compose multiple modifiers
    public static func compose(_ modifiers: [EffectModifier]) -> EffectModifier {
        guard !modifiers.isEmpty else { return .identity }
        
        var result = modifiers[0]
        for modifier in modifiers.dropFirst() {
            result = result.combined(with: modifier)
        }
        return result
    }
    
    private func composeReasons(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let r?, nil): return r
        case (nil, let r?): return r
        case (let r1?, let r2?): return "\(r1); \(r2)"
        }
    }
}

// MARK: - Effect Modifier Validation

extension EffectModifier {
    /// Validate modifier against safety constraints
    public func validate() -> [String] {
        var errors: [String] = []
        
        if isfMultiplier < Self.minISFMultiplier || isfMultiplier > Self.maxISFMultiplier {
            errors.append("ISF multiplier \(isfMultiplier) outside bounds [\(Self.minISFMultiplier), \(Self.maxISFMultiplier)]")
        }
        
        if crMultiplier < Self.minCRMultiplier || crMultiplier > Self.maxCRMultiplier {
            errors.append("CR multiplier \(crMultiplier) outside bounds [\(Self.minCRMultiplier), \(Self.maxCRMultiplier)]")
        }
        
        if basalMultiplier < Self.minBasalMultiplier || basalMultiplier > Self.maxBasalMultiplier {
            errors.append("Basal multiplier \(basalMultiplier) outside bounds [\(Self.minBasalMultiplier), \(Self.maxBasalMultiplier)]")
        }
        
        if validUntil <= timestamp {
            errors.append("validUntil must be after timestamp")
        }
        
        if source.isEmpty {
            errors.append("Source cannot be empty")
        }
        
        return errors
    }
}

// MARK: - Effect Modifier Summary

extension EffectModifier {
    /// Human-readable summary of this modifier's effect
    public var summary: String {
        var parts: [String] = []
        
        if isfMultiplier < 0.95 {
            let pct = Int((1.0 - isfMultiplier) * 100)
            parts.append("+\(pct)% sensitivity")
        } else if isfMultiplier > 1.05 {
            let pct = Int((isfMultiplier - 1.0) * 100)
            parts.append("-\(pct)% sensitivity")
        }
        
        if basalMultiplier < 0.95 {
            let pct = Int((1.0 - basalMultiplier) * 100)
            parts.append("-\(pct)% basal")
        } else if basalMultiplier > 1.05 {
            let pct = Int((basalMultiplier - 1.0) * 100)
            parts.append("+\(pct)% basal")
        }
        
        if crMultiplier < 0.95 {
            let pct = Int((1.0 - crMultiplier) * 100)
            parts.append("-\(pct)% CR")
        } else if crMultiplier > 1.05 {
            let pct = Int((crMultiplier - 1.0) * 100)
            parts.append("+\(pct)% CR")
        }
        
        if parts.isEmpty {
            return "No adjustment"
        }
        
        return parts.joined(separator: ", ")
    }
    
    /// Net dose direction
    public var netDoseDirection: DoseDirection {
        // Lower ISF = more sensitive = less insulin
        // Lower basal = less insulin
        let netEffect = (isfMultiplier + basalMultiplier) / 2.0
        
        if netEffect < 0.95 {
            return .lessInsulin
        } else if netEffect > 1.05 {
            return .moreInsulin
        }
        return .noChange
    }
    
    public enum DoseDirection: String, Codable, Sendable {
        case lessInsulin = "less"
        case moreInsulin = "more"
        case noChange = "unchanged"
    }
}

// MARK: - Conversion from EffectBundle

extension EffectModifier {
    /// Create an EffectModifier from a SensitivityEffectSpec
    public init(from spec: SensitivityEffectSpec, source: String, timestamp: Date = Date()) {
        self.init(
            isfMultiplier: spec.factor,
            source: source,
            confidence: spec.confidence,
            timestamp: timestamp,
            validUntil: timestamp.addingTimeInterval(Double(spec.durationMinutes) * 60)
        )
    }
    
    /// Create from an EffectBundle by extracting sensitivity effects
    public init?(from bundle: EffectBundle) {
        // Find sensitivity effect
        var isfFactor = 1.0
        var confidence = bundle.confidence
        
        for effect in bundle.effects {
            switch effect {
            case .sensitivity(let spec):
                isfFactor = spec.factor
                confidence = min(confidence, spec.confidence)
            case .glucose, .absorption:
                continue
            }
        }
        
        // Only create if there's actually a sensitivity change
        guard abs(isfFactor - 1.0) > 0.01 else { return nil }
        
        self.init(
            isfMultiplier: isfFactor,
            source: bundle.agent,
            confidence: confidence,
            timestamp: bundle.timestamp,
            validUntil: bundle.validUntil,
            reason: bundle.reason
        )
    }
}
