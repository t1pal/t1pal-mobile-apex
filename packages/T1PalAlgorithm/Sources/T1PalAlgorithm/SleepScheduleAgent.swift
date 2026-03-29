// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SleepScheduleAgent.swift
// T1PalAlgorithm
//
// SleepSchedule agent - overnight sensitivity and target adjustments
// Backlog: EFFECT-AGENT-003
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md, AGENT-PRIVACY-GUARANTEES.md
//
// Sleep typically involves:
// 1. Dawn phenomenon: rising BG in early morning hours
// 2. Different sensitivity patterns during sleep
// 3. Safety considerations for overnight lows

import Foundation

// MARK: - Sleep Phase

/// Sleep phases with associated metabolic patterns
public enum SleepPhase: String, Codable, Sendable, CaseIterable {
    /// First half of night - often stable or slightly dropping BG
    case earlyNight = "earlyNight"
    
    /// Early morning hours - dawn phenomenon often starts
    case dawnPhenomenon = "dawnPhenomenon"
    
    /// Waking period - transition to active state
    case waking = "waking"
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .earlyNight: return "Early Night"
        case .dawnPhenomenon: return "Dawn Phenomenon"
        case .waking: return "Waking"
        }
    }
}

// MARK: - Sleep Schedule Agent

/// Agent that adjusts for overnight glucose patterns and sleep
///
/// Handles:
/// 1. Dawn phenomenon - increased insulin needs in early morning
/// 2. Overnight safety - conservative targets to prevent lows
/// 3. Waking transition - gradually returns to daytime settings
///
/// Privacy Tier: privacyPreserving (sleep times stay local, effects sync)
public actor SleepScheduleAgent: EffectAgent {
    
    public nonisolated let agentId = "sleepSchedule"
    public nonisolated let name = "Sleep Schedule"
    public nonisolated let description = "Overnight adjustments for dawn phenomenon and sleep safety"
    public nonisolated let privacyTier: PrivacyTier = .privacyPreserving
    
    // MARK: - Configuration
    
    public struct Configuration: Codable, Sendable {
        /// Typical bedtime (hour, 0-23)
        public let bedtimeHour: Int
        
        /// Typical wake time (hour, 0-23)
        public let wakeHour: Int
        
        /// Hour when dawn phenomenon typically starts
        public let dawnStartHour: Int
        
        /// Sensitivity adjustment during early night (< 1 = more sensitive)
        public let earlyNightSensitivity: Double
        
        /// Sensitivity adjustment during dawn phenomenon (> 1 = less sensitive)
        public let dawnSensitivity: Double
        
        /// Target glucose during sleep (mg/dL) - slightly higher for safety
        public let sleepTarget: Double
        
        /// Duration of waking transition (minutes)
        public let wakingTransitionMinutes: Int
        
        /// Confidence score for effects
        public let confidence: Double
        
        public init(
            bedtimeHour: Int = 22,      // 10 PM
            wakeHour: Int = 7,          // 7 AM
            dawnStartHour: Int = 4,     // 4 AM
            earlyNightSensitivity: Double = 0.9,
            dawnSensitivity: Double = 1.3,
            sleepTarget: Double = 120,
            wakingTransitionMinutes: Int = 60,
            confidence: Double = 0.7
        ) {
            self.bedtimeHour = bedtimeHour
            self.wakeHour = wakeHour
            self.dawnStartHour = dawnStartHour
            self.earlyNightSensitivity = earlyNightSensitivity
            self.dawnSensitivity = dawnSensitivity
            self.sleepTarget = sleepTarget
            self.wakingTransitionMinutes = wakingTransitionMinutes
            self.confidence = confidence
        }
    }
    
    // MARK: - State
    
    private var configuration: Configuration
    private var isEnabled: Bool = true
    private var lastEvaluation: Date?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - EffectAgent Protocol
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        guard isEnabled else { return nil }
        
        let now = context.timeOfDay
        let hour = context.hour
        
        // Determine current sleep phase
        guard let phase = determineSleepPhase(hour: hour) else {
            // Not in sleep window
            return nil
        }
        
        lastEvaluation = now
        
        return createEffectBundle(for: phase, at: now)
    }
    
    public func configure(_ settings: [String: Any]) async {
        if let bedtime = settings["bedtimeHour"] as? Int {
            configuration = Configuration(
                bedtimeHour: bedtime,
                wakeHour: configuration.wakeHour,
                dawnStartHour: configuration.dawnStartHour,
                earlyNightSensitivity: configuration.earlyNightSensitivity,
                dawnSensitivity: configuration.dawnSensitivity,
                sleepTarget: configuration.sleepTarget,
                wakingTransitionMinutes: configuration.wakingTransitionMinutes,
                confidence: configuration.confidence
            )
        }
        
        if let wake = settings["wakeHour"] as? Int {
            configuration = Configuration(
                bedtimeHour: configuration.bedtimeHour,
                wakeHour: wake,
                dawnStartHour: configuration.dawnStartHour,
                earlyNightSensitivity: configuration.earlyNightSensitivity,
                dawnSensitivity: configuration.dawnSensitivity,
                sleepTarget: configuration.sleepTarget,
                wakingTransitionMinutes: configuration.wakingTransitionMinutes,
                confidence: configuration.confidence
            )
        }
    }
    
    public func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
    }
    
    // MARK: - Private Methods
    
    private func determineSleepPhase(hour: Int) -> SleepPhase? {
        let bedtime = configuration.bedtimeHour
        let wake = configuration.wakeHour
        let dawnStart = configuration.dawnStartHour
        
        // Handle overnight wrap-around
        let isInSleepWindow: Bool
        if bedtime > wake {
            // e.g., 22:00 - 07:00
            isInSleepWindow = hour >= bedtime || hour < wake
        } else {
            // e.g., 23:00 - 06:00 (unusual but supported)
            isInSleepWindow = hour >= bedtime && hour < wake
        }
        
        guard isInSleepWindow else { return nil }
        
        // Determine phase within sleep window
        if hour >= dawnStart && hour < wake {
            return .dawnPhenomenon
        } else if hour >= bedtime || hour < dawnStart {
            return .earlyNight
        } else {
            return .waking
        }
    }
    
    private func createEffectBundle(for phase: SleepPhase, at timestamp: Date) -> EffectBundle {
        let effects: [AnyEffect]
        let reason: String
        let validUntil: Date
        
        switch phase {
        case .earlyNight:
            // Slightly more sensitive, higher target for safety
            effects = [
                .sensitivity(SensitivityEffectSpec(
                    confidence: configuration.confidence,
                    factor: configuration.earlyNightSensitivity,
                    durationMinutes: 120
                ))
            ]
            reason = "Early night: slight sensitivity increase for overnight stability"
            validUntil = timestamp.addingTimeInterval(2 * 3600)
            
        case .dawnPhenomenon:
            // Less sensitive to counteract dawn phenomenon
            effects = [
                .sensitivity(SensitivityEffectSpec(
                    confidence: configuration.confidence,
                    factor: configuration.dawnSensitivity,
                    durationMinutes: 180
                ))
            ]
            reason = "Dawn phenomenon: reduced sensitivity for rising morning glucose"
            validUntil = timestamp.addingTimeInterval(3 * 3600)
            
        case .waking:
            // Transition back to normal
            effects = [
                .sensitivity(SensitivityEffectSpec(
                    confidence: configuration.confidence * 0.8,
                    factor: 1.0 + (configuration.dawnSensitivity - 1.0) * 0.5,
                    durationMinutes: configuration.wakingTransitionMinutes
                ))
            ]
            reason = "Waking: transitioning from sleep to daytime settings"
            validUntil = timestamp.addingTimeInterval(Double(configuration.wakingTransitionMinutes) * 60)
        }
        
        return EffectBundle(
            agent: agentId,
            timestamp: timestamp,
            validFrom: timestamp,
            validUntil: validUntil,
            effects: effects,
            reason: reason,
            privacyTier: privacyTier,
            confidence: configuration.confidence
        )
    }
}
