// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ActivityModeAgent.swift
// T1PalAlgorithm
//
// ActivityMode agent prototype - exercise glucose drop + post-exercise sensitivity
// Backlog: EFFECT-AGENT-002
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md, AGENT-PRIVACY-GUARANTEES.md

import Foundation

// MARK: - ActivityMode Agent

/// Agent that detects exercise and adjusts for glucose drop + post-exercise sensitivity
///
/// Exercise typically causes:
/// 1. Immediate glucose drop during activity
/// 2. Reduced insulin sensitivity during intense exercise (adrenaline)
/// 3. Increased insulin sensitivity post-exercise (for 2-4 hours)
///
/// This agent:
/// 1. Detects elevated heart rate or accelerometer activity
/// 2. Predicts glucose drop during exercise
/// 3. Adjusts sensitivity for post-exercise period
///
/// Privacy Tier: privacyPreserving (effects sync, HR/activity context stays local)
public actor ActivityModeAgent: EffectAgent {
    
    public nonisolated let agentId = "activityMode"
    public nonisolated let name = "ActivityMode"
    public nonisolated let description = "Exercise detection with glucose and sensitivity adjustments"
    public nonisolated let privacyTier: PrivacyTier = .privacyPreserving
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Minimum heart rate to trigger (if available)
        public let minHeartRate: Int
        
        /// Minimum activity level (arbitrary units, e.g., steps/min)
        public let minActivityLevel: Double
        
        /// Predicted glucose drop during exercise (mg/dL)
        public let exerciseGlucoseDrop: Double
        
        /// Sensitivity factor during exercise (> 1 = less sensitive)
        public let duringExerciseSensitivity: Double
        
        /// Post-exercise sensitivity factor (< 1 = more sensitive)
        public let postExerciseSensitivity: Double
        
        /// Duration of exercise effects (minutes)
        public let exerciseEffectDuration: Int
        
        /// Duration of post-exercise sensitivity (minutes)
        public let postExerciseDuration: Int
        
        /// Confidence score for effects
        public let confidence: Double
        
        public init(
            minHeartRate: Int = 120,
            minActivityLevel: Double = 50,
            exerciseGlucoseDrop: Double = -30,
            duringExerciseSensitivity: Double = 1.2,
            postExerciseSensitivity: Double = 0.7,
            exerciseEffectDuration: Int = 60,
            postExerciseDuration: Int = 120,
            confidence: Double = 0.75
        ) {
            self.minHeartRate = minHeartRate
            self.minActivityLevel = minActivityLevel
            self.exerciseGlucoseDrop = exerciseGlucoseDrop
            self.duringExerciseSensitivity = duringExerciseSensitivity
            self.postExerciseSensitivity = postExerciseSensitivity
            self.exerciseEffectDuration = exerciseEffectDuration
            self.postExerciseDuration = postExerciseDuration
            self.confidence = confidence
        }
        
        public static let `default` = Configuration()
        
        /// More aggressive for intense exercise
        public static let intense = Configuration(
            minHeartRate: 150,
            exerciseGlucoseDrop: -45,
            duringExerciseSensitivity: 1.4,
            postExerciseSensitivity: 0.6,
            exerciseEffectDuration: 90,
            postExerciseDuration: 180,
            confidence: 0.8
        )
        
        /// Conservative for light exercise
        public static let light = Configuration(
            minHeartRate: 100,
            minActivityLevel: 30,
            exerciseGlucoseDrop: -15,
            duringExerciseSensitivity: 1.1,
            postExerciseSensitivity: 0.85,
            exerciseEffectDuration: 45,
            postExerciseDuration: 90,
            confidence: 0.65
        )
    }
    
    private let config: Configuration
    private var lastActivation: Date?
    private var exerciseStartTime: Date?
    private var isCurrentlyExercising: Bool = false
    private let minActivationInterval: TimeInterval = 30 * 60 // 30 minutes
    
    public init(config: Configuration = .default) {
        self.config = config
    }
    
    // MARK: - Evaluation
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        let activityContext = extractActivityContext(from: context)
        
        // Determine if we're starting, continuing, or ending exercise
        let state = determineExerciseState(activityContext: activityContext, agentContext: context)
        
        switch state {
        case .notExercising:
            return nil
            
        case .startingExercise:
            exerciseStartTime = Date()
            isCurrentlyExercising = true
            lastActivation = Date()
            return createExerciseStartBundle()
            
        case .duringExercise:
            // Already active, no new bundle needed unless it's been a while
            if let lastTime = lastActivation,
               Date().timeIntervalSince(lastTime) > 15 * 60 { // Refresh every 15 min
                lastActivation = Date()
                return createExerciseRefreshBundle()
            }
            return nil
            
        case .exerciseEnding:
            isCurrentlyExercising = false
            return createPostExerciseBundle()
        }
    }
    
    // MARK: - Activity Context
    
    private struct ActivityContext {
        let heartRate: Int?
        let activityLevel: Double?
        let isExercising: Bool
    }
    
    private func extractActivityContext(from context: AgentContext) -> ActivityContext {
        // In production, this would read from HealthKit or device sensors
        // For prototype, we use the glucose trend as a proxy (dropping = likely exercising)
        let likelyExercising: Bool
        if let trend = context.glucoseTrend {
            // Rapid drop could indicate exercise
            likelyExercising = trend < -2.0
        } else {
            likelyExercising = false
        }
        
        return ActivityContext(
            heartRate: nil, // Would come from HealthKit
            activityLevel: nil, // Would come from accelerometer
            isExercising: likelyExercising
        )
    }
    
    // MARK: - Exercise State
    
    private enum ExerciseState {
        case notExercising
        case startingExercise
        case duringExercise
        case exerciseEnding
    }
    
    private func determineExerciseState(activityContext: ActivityContext, agentContext: AgentContext) -> ExerciseState {
        // Check heart rate if available
        if let hr = activityContext.heartRate, hr >= config.minHeartRate {
            if !isCurrentlyExercising {
                return .startingExercise
            } else {
                return .duringExercise
            }
        }
        
        // Check activity level if available
        if let activity = activityContext.activityLevel, activity >= config.minActivityLevel {
            if !isCurrentlyExercising {
                return .startingExercise
            } else {
                return .duringExercise
            }
        }
        
        // Check glucose proxy
        if activityContext.isExercising {
            if !isCurrentlyExercising {
                // Avoid activation too frequently
                if let lastTime = lastActivation,
                   Date().timeIntervalSince(lastTime) < minActivationInterval {
                    return .notExercising
                }
                return .startingExercise
            } else {
                return .duringExercise
            }
        }
        
        // No exercise signals
        if isCurrentlyExercising {
            return .exerciseEnding
        }
        
        return .notExercising
    }
    
    // MARK: - Bundle Creation
    
    private func createExerciseStartBundle() -> EffectBundle {
        var effects: [AnyEffect] = []
        
        // Glucose drop prediction
        let glucosePoints: [GlucoseEffectSpec.GlucoseEffectPoint] = [
            .init(minuteOffset: 0, bgDelta: 0),
            .init(minuteOffset: 15, bgDelta: config.exerciseGlucoseDrop * 0.3),
            .init(minuteOffset: 30, bgDelta: config.exerciseGlucoseDrop * 0.6),
            .init(minuteOffset: 45, bgDelta: config.exerciseGlucoseDrop * 0.85),
            .init(minuteOffset: 60, bgDelta: config.exerciseGlucoseDrop)
        ]
        let glucose = GlucoseEffectSpec(
            confidence: config.confidence,
            series: glucosePoints
        )
        effects.append(.glucose(glucose))
        
        // During-exercise sensitivity (less sensitive due to adrenaline)
        let sensitivity = SensitivityEffectSpec(
            confidence: config.confidence,
            factor: config.duringExerciseSensitivity,
            durationMinutes: config.exerciseEffectDuration
        )
        effects.append(.sensitivity(sensitivity))
        
        let now = Date()
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(Double(config.exerciseEffectDuration) * 60),
            effects: effects,
            reason: "Exercise detected",
            privacyTier: privacyTier,
            confidence: config.confidence
        )
    }
    
    private func createExerciseRefreshBundle() -> EffectBundle {
        // Similar to start bundle but for ongoing exercise
        return createExerciseStartBundle()
    }
    
    private func createPostExerciseBundle() -> EffectBundle {
        var effects: [AnyEffect] = []
        
        // Post-exercise sensitivity increase
        let sensitivity = SensitivityEffectSpec(
            confidence: config.confidence * 0.9, // Slightly less confident for post-exercise
            factor: config.postExerciseSensitivity,
            durationMinutes: config.postExerciseDuration
        )
        effects.append(.sensitivity(sensitivity))
        
        // Potential glucose rise as glycogen replenishes (some people experience this)
        let glucosePoints: [GlucoseEffectSpec.GlucoseEffectPoint] = [
            .init(minuteOffset: 0, bgDelta: 0),
            .init(minuteOffset: 30, bgDelta: 5),
            .init(minuteOffset: 60, bgDelta: 10),
            .init(minuteOffset: 90, bgDelta: 5),
            .init(minuteOffset: 120, bgDelta: 0)
        ]
        let glucose = GlucoseEffectSpec(
            confidence: config.confidence * 0.6, // Less confident on post-exercise rise
            series: glucosePoints
        )
        effects.append(.glucose(glucose))
        
        let now = Date()
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(Double(config.postExerciseDuration) * 60),
            effects: effects,
            reason: "Post-exercise recovery",
            privacyTier: privacyTier,
            confidence: config.confidence * 0.85
        )
    }
    
    // MARK: - State Access
    
    public var currentlyExercising: Bool {
        isCurrentlyExercising
    }
    
    public var exerciseDuration: TimeInterval? {
        guard let start = exerciseStartTime, isCurrentlyExercising else { return nil }
        return Date().timeIntervalSince(start)
    }
    
    public func reset() {
        lastActivation = nil
        exerciseStartTime = nil
        isCurrentlyExercising = false
    }
    
    /// Manually trigger exercise mode (for user-initiated exercise)
    public func startExercise() -> EffectBundle {
        exerciseStartTime = Date()
        isCurrentlyExercising = true
        lastActivation = Date()
        return createExerciseStartBundle()
    }
    
    /// Manually end exercise mode
    public func endExercise() -> EffectBundle {
        isCurrentlyExercising = false
        return createPostExerciseBundle()
    }
}

// MARK: - Extended Context

extension AgentContext {
    /// Create context with activity data
    public static func withActivity(
        currentGlucose: Double? = nil,
        glucoseTrend: Double? = nil,
        heartRate: Int? = nil,
        activityLevel: Double? = nil,
        isLoopActive: Bool = true
    ) -> AgentContext {
        AgentContext(
            currentGlucose: currentGlucose,
            glucoseTrend: glucoseTrend,
            timeOfDay: Date(),
            iob: nil,
            cob: nil,
            recentCarbs: [],
            isLoopActive: isLoopActive
        )
    }
}
