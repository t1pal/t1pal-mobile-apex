// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PersonalizedMLDosingProvider.swift
// T1PalAlgorithm
//
// ML dosing provider that uses personalized models from MLModelStorage.
// Falls back to base provider when no personalized model is available.
//
// Trace: ALG-SHADOW-033, PRD-028

import Foundation
import T1PalCore

// MARK: - Personalized ML Dosing Provider

/// ML dosing provider that loads and uses personalized trained models
public actor PersonalizedMLDosingProvider: MLDosingProvider {
    
    // MARK: - Configuration
    
    /// Configuration for personalized dosing
    public struct Config: Sendable {
        /// Minimum confidence to apply ML adjustments
        public let minConfidenceToApply: Double
        
        /// Maximum scaling factor allowed
        public let maxScalingFactor: Double
        
        /// Whether to use base provider when personalized unavailable
        public let fallbackToBaseProvider: Bool
        
        /// Minimum training data points required
        public let minTrainingDataPoints: Int
        
        public init(
            minConfidenceToApply: Double = 0.3,
            maxScalingFactor: Double = 1.5,
            fallbackToBaseProvider: Bool = true,
            minTrainingDataPoints: Int = 1000
        ) {
            self.minConfidenceToApply = minConfidenceToApply
            self.maxScalingFactor = maxScalingFactor
            self.fallbackToBaseProvider = fallbackToBaseProvider
            self.minTrainingDataPoints = minTrainingDataPoints
        }
        
        public static let `default` = Config()
    }
    
    // MARK: - State
    
    private let storage: MLModelStorage
    private let baseProvider: (any MLDosingProvider)?
    private let config: Config
    
    /// Cached active model bundle
    private var activeBundle: MLModelBundle?
    
    /// Last load attempt
    private var lastLoadAttempt: Date?
    
    /// Reload interval for checking new models
    private let reloadInterval: TimeInterval = 300  // 5 minutes
    
    /// Whether provider is enabled
    public nonisolated var isEnabled: Bool { true }
    
    // MARK: - Initialization
    
    /// Create with storage and optional base provider fallback
    public init(
        storage: MLModelStorage,
        baseProvider: (any MLDosingProvider)? = nil,
        config: Config = .default
    ) {
        self.storage = storage
        self.baseProvider = baseProvider
        self.config = config
    }
    
    // MARK: - MLDosingProvider Protocol
    
    public func adjustedTempBasal(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult? {
        // Try to use personalized model
        if let result = await personalizedAdjustment(
            baseline: baseline,
            inputs: inputs,
            target: target
        ) {
            return result
        }
        
        // Fallback to base provider if configured
        if config.fallbackToBaseProvider, let base = baseProvider {
            return await base.adjustedTempBasal(
                baseline: baseline,
                inputs: inputs,
                target: target
            )
        }
        
        return nil
    }
    
    // MARK: - Personalized Adjustment
    
    /// Compute adjustment using personalized model
    private func personalizedAdjustment(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResult? {
        // Load or refresh model
        await refreshModelIfNeeded()
        
        guard let bundle = activeBundle else {
            return nil  // No personalized model available
        }
        
        // Check if model is expired
        if bundle.metadata.expiresAt < Date() {
            return nil  // Model expired
        }
        
        // Check minimum training data
        if bundle.metadata.trainingRows < config.minTrainingDataPoints {
            return nil  // Insufficient data
        }
        
        // Get current glucose
        guard let currentGlucose = inputs.glucose.last?.glucose else {
            return nil
        }
        
        // Only apply when above target
        guard currentGlucose > target else {
            return MLDosingResult(
                tempBasalRate: baseline.rate,
                scalingFactor: 1.0,
                reason: "Below target - personalized ML not applied"
            )
        }
        
        // Compute personalized scaling factor
        let scalingFactor = computeScalingFactor(
            currentGlucose: currentGlucose,
            target: target,
            bundle: bundle
        )
        
        // Clamp scaling factor
        let clampedFactor = min(scalingFactor, config.maxScalingFactor)
        let wasClamped = scalingFactor != clampedFactor
        
        let adjustedRate = baseline.rate * clampedFactor
        
        return MLDosingResult(
            tempBasalRate: adjustedRate,
            scalingFactor: clampedFactor,
            mlInsulinLast3Hours: 0,  // Would be tracked separately
            wasClamped: wasClamped,
            reason: String(format: "Personalized ML: %.2fx (v%@)", 
                          clampedFactor, 
                          bundle.metadata.version)
        )
    }
    
    /// Compute scaling factor using trained model
    private func computeScalingFactor(
        currentGlucose: Double,
        target: Double,
        bundle: MLModelBundle
    ) -> Double {
        // Simple glucose-based scaling using stored normalizer stats
        // In production, this would run CoreML inference with normalized features
        
        // Get normalization stats for glucose if available
        _ = bundle.normalizer.means["glucose"] ?? 120.0  // glucoseMean for reference
        let glucoseStd = max(bundle.normalizer.stds["glucose"] ?? 30.0, 1.0)
        
        // Normalize the glucose delta
        let delta = currentGlucose - target
        let normalizedDelta = delta / glucoseStd
        
        // Model accuracy influences scaling aggressiveness
        let accuracyFactor = bundle.metadata.validationAccuracy
        
        // Learned linear scaling (placeholder for CoreML)
        // More confident models apply more aggressive scaling
        let baselineScale = 1.0
        let slopeScale = 0.2 * accuracyFactor  // Scale by model confidence
        
        return baselineScale + (normalizedDelta * slopeScale)
    }
    
    // MARK: - Model Loading
    
    /// Refresh model from storage if needed
    private func refreshModelIfNeeded() async {
        let now = Date()
        
        // Check if we need to reload
        if let lastAttempt = lastLoadAttempt,
           now.timeIntervalSince(lastAttempt) < reloadInterval,
           activeBundle != nil {
            return  // Recently loaded and have a model
        }
        
        lastLoadAttempt = now
        
        do {
            activeBundle = try await storage.loadActive()
        } catch {
            // No active model or load failed
            activeBundle = nil
        }
    }
    
    /// Force reload model from storage
    public func reloadModel() async -> Bool {
        lastLoadAttempt = nil
        await refreshModelIfNeeded()
        return activeBundle != nil
    }
    
    // MARK: - Model Status
    
    /// Get current model metadata
    public func activeModelMetadata() async -> MLModelMetadata? {
        await refreshModelIfNeeded()
        return activeBundle?.metadata
    }
    
    /// Get confidence for current model
    public func currentConfidence() async -> MLRecommendationConfidence {
        await refreshModelIfNeeded()
        
        guard let bundle = activeBundle else {
            return .notApplied(reason: .noModel)
        }
        
        if bundle.metadata.expiresAt < Date() {
            return .notApplied(reason: .modelExpired)
        }
        
        if bundle.metadata.trainingRows < config.minTrainingDataPoints {
            return .notApplied(reason: .insufficientData)
        }
        
        // Calculate model age
        let ageInDays = Calendar.current.dateComponents(
            [.day],
            from: bundle.metadata.createdAt,
            to: Date()
        ).day ?? 0
        
        // Confidence degrades slightly with age
        let baseConfidence = bundle.metadata.validationAccuracy
        let agePenalty = Double(ageInDays) * 0.005  // -0.5% per day
        let adjustedConfidence = max(0.3, baseConfidence - agePenalty)
        
        return .confident(
            score: adjustedConfidence,
            modelVersion: bundle.metadata.version,
            modelAgeDays: ageInDays,
            trainingDataPoints: bundle.metadata.trainingRows
        )
    }
    
    /// Check if personalized model is available and usable
    public func hasUsableModel() async -> Bool {
        await refreshModelIfNeeded()
        
        guard let bundle = activeBundle else { return false }
        
        // Check not expired
        if bundle.metadata.expiresAt < Date() { return false }
        
        // Check sufficient data
        if bundle.metadata.trainingRows < config.minTrainingDataPoints { return false }
        
        return true
    }
}

// MARK: - Enhanced Result with Confidence

extension PersonalizedMLDosingProvider {
    
    /// Get dosing result with full confidence information
    public func adjustedTempBasalWithConfidence(
        baseline: TempBasal,
        inputs: AlgorithmInputs,
        target: Double
    ) async -> MLDosingResultWithConfidence? {
        await refreshModelIfNeeded()
        
        // Get the base result
        guard let result = await adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: target
        ) else {
            return nil
        }
        
        // Add confidence information
        let confidence = await currentConfidence()
        
        return MLDosingResultWithConfidence(
            result: result,
            confidence: confidence
        )
    }
}

// MARK: - Storage Integration

extension PersonalizedMLDosingProvider {
    
    /// Create provider with default storage configuration
    public static func withDefaultStorage(
        baseProvider: (any MLDosingProvider)? = nil,
        config: Config = .default
    ) async throws -> PersonalizedMLDosingProvider? {
        guard let storageConfig = MLModelStorageConfig.defaultConfig() else {
            return nil
        }
        
        let storage = MLModelStorage(config: storageConfig)
        try await storage.initialize()
        
        return PersonalizedMLDosingProvider(
            storage: storage,
            baseProvider: baseProvider,
            config: config
        )
    }
}

// MARK: - Training Pipeline Integration

extension PersonalizedMLDosingProvider {
    
    /// Notify that a new model was trained and saved
    /// This triggers a reload of the active model
    public func onNewModelTrained() async {
        lastLoadAttempt = nil
        await refreshModelIfNeeded()
    }
}
