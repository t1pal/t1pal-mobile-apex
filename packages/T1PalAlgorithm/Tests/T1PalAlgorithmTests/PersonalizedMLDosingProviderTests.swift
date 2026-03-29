// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PersonalizedMLDosingProviderTests.swift
// T1PalAlgorithmTests
//
// Tests for PersonalizedMLDosingProvider
// Trace: ALG-SHADOW-033

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Personalized ML Dosing Provider")
struct PersonalizedMLDosingProviderTests {
    
    // MARK: - Helper Methods
    
    func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ml-provider-test-\(UUID().uuidString)")
        return tempDir
    }
    
    func createStorageAndProvider(tempDir: URL) async throws -> (MLModelStorage, PersonalizedMLDosingProvider) {
        let config = MLModelStorageConfig(
            baseDirectory: tempDir,
            maxVersions: 5,
            compressModels: false,
            autoCleanup: true
        )
        
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let provider = PersonalizedMLDosingProvider(
            storage: storage,
            baseProvider: nil,
            config: .default
        )
        
        return (storage, provider)
    }
    
    func cleanupTempDir(_ tempDir: URL) {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    func createTestBundle(
        trainingRows: Int = 2000,
        accuracy: Double = 0.85,
        daysOld: Int = 5
    ) -> MLModelBundle {
        let createdAt = Calendar.current.date(
            byAdding: .day,
            value: -daysOld,
            to: Date()
        )!
        
        let metadata = MLModelMetadata(
            modelId: UUID().uuidString,
            version: "1.0.0",
            createdAt: createdAt,
            trainingDataStart: createdAt.addingTimeInterval(-86400 * 14),
            trainingDataEnd: createdAt,
            trainingRows: trainingRows,
            validationAccuracy: accuracy,
            algorithmId: "personalized-test",
            expiresAt: createdAt.addingTimeInterval(86400 * 90)  // 90 days
        )
        
        let normalizer = FeatureNormalizer(
            means: ["glucose": 120.0, "iob": 2.0],
            stds: ["glucose": 30.0, "iob": 1.5],
            mins: ["glucose": 40.0, "iob": 0.0],
            maxs: ["glucose": 400.0, "iob": 20.0]
        )
        
        return MLModelBundle(
            metadata: metadata,
            normalizer: normalizer,
            modelData: nil
        )
    }
    
    func createTestInputs(currentGlucose: Double) -> AlgorithmInputs {
        let now = Date()
        let glucose = [
            GlucoseReading(
                glucose: currentGlucose,
                timestamp: now,
                source: "test"
            )
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 8.0
        )
        
        return AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
    }
    
    func createTrainingResult(rows: Int = 2000, accuracy: Double = 0.85) -> MLTrainingResult {
        MLTrainingResult.success(
            modelId: UUID().uuidString,
            modelVersion: "1.0.0",
            trainingRows: rows,
            validationRows: rows / 5,
            validationAccuracy: accuracy,
            metrics: TrainingMetrics(
                scalingFactorMAE: 0.05,
                scalingFactorRMSE: 0.08,
                within20Percent: accuracy,
                trainingDuration: 5.0,
                iterationsCompleted: 100
            )
        )
    }
    
    // MARK: - Basic Provider Tests
    
    @Test("Provider is enabled")
    func providerIsEnabled() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        #expect(provider.isEnabled)
    }
    
    @Test("No model returns nil")
    func noModelReturnsNil() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 150)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result == nil)
    }
    
    @Test("Has usable model returns false when no model")
    func hasUsableModelReturnsFalseWhenNoModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let hasModel = await provider.hasUsableModel()
        #expect(!hasModel)
    }
    
    @Test("Active model metadata returns nil when no model")
    func activeModelMetadataReturnsNilWhenNoModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let metadata = await provider.activeModelMetadata()
        #expect(metadata == nil)
    }
    
    // MARK: - With Model Tests
    
    @Test("With model returns result")
    func withModelReturnsResult() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        // Save a model first
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        // Reload
        _ = await provider.reloadModel()
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 180)
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result!.scalingFactor > 1.0)
    }
    
    @Test("Below target no scaling")
    func belowTargetNoScaling() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 90)  // Below target
        
        let result = await provider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result!.scalingFactor == 1.0)
        #expect(result!.reason.contains("Below target"))
    }
    
    @Test("Has usable model returns true with valid model")
    func hasUsableModelReturnsTrueWithValidModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let hasModel = await provider.hasUsableModel()
        #expect(hasModel)
    }
    
    @Test("Active model metadata returns metadata")
    func activeModelMetadataReturnsMetadata() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let metadata = await provider.activeModelMetadata()
        #expect(metadata != nil)
        #expect(metadata?.algorithmId == "personalized-test")
    }
    
    // MARK: - Insufficient Data Tests
    
    @Test("Insufficient training data skips model")
    func insufficientTrainingDataSkipsModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        // Model with too few rows
        let bundle = createTestBundle(trainingRows: 500)  // Below 1000 default minimum
        let trainingResult = createTrainingResult(rows: 500)
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let hasModel = await provider.hasUsableModel()
        #expect(!hasModel)
    }
    
    @Test("Custom min training data points")
    func customMinTrainingDataPoints() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        
        let config = MLModelStorageConfig(
            baseDirectory: tempDir,
            maxVersions: 5,
            compressModels: false,
            autoCleanup: true
        )
        
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        // Create provider with lower threshold
        let customConfig = PersonalizedMLDosingProvider.Config(
            minTrainingDataPoints: 100
        )
        let customProvider = PersonalizedMLDosingProvider(
            storage: storage,
            baseProvider: nil,
            config: customConfig
        )
        
        let bundle = createTestBundle(trainingRows: 500)
        let trainingResult = createTrainingResult(rows: 500)
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await customProvider.reloadModel()
        
        let hasModel = await customProvider.hasUsableModel()
        #expect(hasModel)
    }
    
    // MARK: - Expired Model Tests
    
    @Test("Expired model not usable")
    func expiredModelNotUsable() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        // Create expired model
        let expiredDate = Date().addingTimeInterval(-86400)  // Yesterday
        let metadata = MLModelMetadata(
            modelId: UUID().uuidString,
            version: "1.0.0",
            createdAt: Date().addingTimeInterval(-86400 * 100),
            trainingDataStart: Date().addingTimeInterval(-86400 * 114),
            trainingDataEnd: Date().addingTimeInterval(-86400 * 100),
            trainingRows: 2000,
            validationAccuracy: 0.9,
            algorithmId: "expired-test",
            expiresAt: expiredDate  // Already expired
        )
        
        let bundle = MLModelBundle(
            metadata: metadata,
            normalizer: FeatureNormalizer(
                means: ["glucose": 120.0],
                stds: ["glucose": 30.0],
                mins: ["glucose": 40.0],
                maxs: ["glucose": 400.0]
            ),
            modelData: nil
        )
        
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let hasModel = await provider.hasUsableModel()
        #expect(!hasModel)
    }
    
    // MARK: - Confidence Tests
    
    @Test("Confidence when no model")
    func confidenceWhenNoModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let confidence = await provider.currentConfidence()
        
        #expect(!confidence.mlApplied)
        #expect(confidence.notAppliedReason == .noModel)
    }
    
    @Test("Confidence with valid model")
    func confidenceWithValidModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle(accuracy: 0.85)
        let trainingResult = createTrainingResult(accuracy: 0.85)
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let confidence = await provider.currentConfidence()
        
        #expect(confidence.mlApplied)
        #expect(confidence.modelVersion != nil)
        #expect(confidence.modelAgeDays != nil)
        #expect(confidence.level == .confident)
    }
    
    @Test("Confidence degrade with age")
    func confidenceDegradeWithAge() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        // Model that's 30 days old
        let bundle = createTestBundle(accuracy: 0.85, daysOld: 30)
        let trainingResult = createTrainingResult(accuracy: 0.85)
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let confidence = await provider.currentConfidence()
        
        // 0.85 - (30 * 0.005) = 0.70, still confident threshold
        #expect(confidence.score < 0.85)
        #expect(confidence.score >= 0.7)
    }
    
    @Test("Expired model confidence")
    func expiredModelConfidence() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let expiredDate = Date().addingTimeInterval(-86400)
        let metadata = MLModelMetadata(
            modelId: UUID().uuidString,
            version: "1.0.0",
            createdAt: Date().addingTimeInterval(-86400 * 100),
            trainingDataStart: Date().addingTimeInterval(-86400 * 114),
            trainingDataEnd: Date().addingTimeInterval(-86400 * 100),
            trainingRows: 2000,
            validationAccuracy: 0.9,
            algorithmId: "expired-test",
            expiresAt: expiredDate
        )
        
        let bundle = MLModelBundle(
            metadata: metadata,
            normalizer: FeatureNormalizer(
                means: ["glucose": 120.0],
                stds: ["glucose": 30.0],
                mins: ["glucose": 40.0],
                maxs: ["glucose": 400.0]
            ),
            modelData: nil
        )
        
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let confidence = await provider.currentConfidence()
        
        #expect(!confidence.mlApplied)
        #expect(confidence.notAppliedReason == .modelExpired)
    }
    
    // MARK: - Result With Confidence Tests
    
    @Test("Result with confidence")
    func resultWithConfidence() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await provider.reloadModel()
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 180)
        
        let result = await provider.adjustedTempBasalWithConfidence(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result?.result != nil)
        #expect(result?.confidence != nil)
        #expect(result!.confidence.mlApplied)
    }
    
    // MARK: - Fallback Provider Tests
    
    @Test("Fallback to base provider")
    func fallbackToBaseProvider() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        
        let config = MLModelStorageConfig(
            baseDirectory: tempDir,
            maxVersions: 5,
            compressModels: false,
            autoCleanup: true
        )
        
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let baseProvider = DynamicISFProvider(maxScalingIncrease: 0.3)
        
        let providerWithFallback = PersonalizedMLDosingProvider(
            storage: storage,
            baseProvider: baseProvider,
            config: PersonalizedMLDosingProvider.Config(fallbackToBaseProvider: true)
        )
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 180)
        
        // No personalized model, should use base
        let result = await providerWithFallback.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result!.reason.contains("Dynamic ISF"))
    }
    
    @Test("No fallback when disabled")
    func noFallbackWhenDisabled() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        
        let config = MLModelStorageConfig(
            baseDirectory: tempDir,
            maxVersions: 5,
            compressModels: false,
            autoCleanup: true
        )
        
        let storage = MLModelStorage(config: config)
        try await storage.initialize()
        
        let baseProvider = DynamicISFProvider(maxScalingIncrease: 0.3)
        
        let providerNoFallback = PersonalizedMLDosingProvider(
            storage: storage,
            baseProvider: baseProvider,
            config: PersonalizedMLDosingProvider.Config(fallbackToBaseProvider: false)
        )
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 180)
        
        let result = await providerNoFallback.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result == nil)
    }
    
    // MARK: - Scaling Bounds Tests
    
    @Test("Scaling clamped to max")
    func scalingClampedToMax() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        
        let storageConfig = MLModelStorageConfig(
            baseDirectory: tempDir,
            maxVersions: 5,
            compressModels: false,
            autoCleanup: true
        )
        
        let storage = MLModelStorage(config: storageConfig)
        try await storage.initialize()
        
        // Create provider with low max scaling
        let config = PersonalizedMLDosingProvider.Config(
            maxScalingFactor: 1.2,
            minTrainingDataPoints: 100
        )
        let limitedProvider = PersonalizedMLDosingProvider(
            storage: storage,
            config: config
        )
        
        let bundle = createTestBundle(trainingRows: 500)
        let trainingResult = createTrainingResult(rows: 500)
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        _ = await limitedProvider.reloadModel()
        
        let baseline = TempBasal(rate: 1.0, duration: 1800)
        let inputs = createTestInputs(currentGlucose: 300)  // Very high
        
        let result = await limitedProvider.adjustedTempBasal(
            baseline: baseline,
            inputs: inputs,
            target: 100
        )
        
        #expect(result != nil)
        #expect(result!.scalingFactor <= 1.2)
    }
    
    // MARK: - Model Reload Tests
    
    @Test("Reload model returns success")
    func reloadModelReturnsSuccess() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        let success = await provider.reloadModel()
        #expect(success)
    }
    
    @Test("Reload model returns false when no model")
    func reloadModelReturnsFalseWhenNoModel() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (_, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        let success = await provider.reloadModel()
        #expect(!success)
    }
    
    @Test("On new model trained triggers reload")
    func onNewModelTrainedTriggersReload() async throws {
        let tempDir = try createTempDir()
        defer { cleanupTempDir(tempDir) }
        let (storage, provider) = try await createStorageAndProvider(tempDir: tempDir)
        
        // Initially no model
        var hasModel = await provider.hasUsableModel()
        #expect(!hasModel)
        
        // Save a model
        let bundle = createTestBundle()
        let trainingResult = createTrainingResult()
        _ = try await storage.save(bundle: bundle, trainingResult: trainingResult)
        
        // Notify provider
        await provider.onNewModelTrained()
        
        // Now should have model
        hasModel = await provider.hasUsableModel()
        #expect(hasModel)
    }
}
