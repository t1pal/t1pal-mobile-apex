// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLTrainingPipelineTests.swift
// T1PalAlgorithm
//
// Tests for on-device ML training pipeline.
//
// Trace: ALG-SHADOW-024

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("ML Training Pipeline Configuration")
struct MLTrainingPipelineConfigTests {
    
    @Test("Default config values")
    func defaultConfig() {
        let config = MLTrainingPipelineConfig.default
        
        #expect(config.minTrainingRows == 4032)
        #expect(config.validationSplit == 0.2)
        #expect(config.requiredValidationAccuracy == 0.70)
        #expect(config.maxModelAgeDays == 90)
        #expect(config.maxIterations == 100)
    }
    
    @Test("Custom config values")
    func customConfig() {
        let config = MLTrainingPipelineConfig(
            minTrainingRows: 1000,
            validationSplit: 0.3,
            requiredValidationAccuracy: 0.8,
            maxModelAgeDays: 60,
            maxIterations: 50
        )
        
        #expect(config.minTrainingRows == 1000)
        #expect(config.validationSplit == 0.3)
        #expect(config.requiredValidationAccuracy == 0.8)
        #expect(config.maxModelAgeDays == 60)
    }
}

@Suite("ML Training Pipeline State")
struct MLTrainingPipelineStateTests {
    
    @Test("Initial state")
    func initialState() async {
        let pipeline = MLTrainingPipeline()
        
        let state = await pipeline.currentState
        #expect(state == .inactive)
        
        let model = await pipeline.activeModel
        #expect(model == nil)
    }
}

@Suite("Feature Normalizer")
struct FeatureNormalizerTests {
    
    @Test("Feature normalizer fit")
    func featureNormalizerFit() {
        // Create test rows
        let rows = (0..<100).map { i in
            createTestRow(
                glucose: 100 + Double(i % 50),  // 100-150 range
                iob: Double(i % 10) / 2,        // 0-5 range
                cob: Double(i % 20) * 5         // 0-100 range
            )
        }
        
        let normalizer = FeatureNormalizer.fit(rows: rows)
        
        // Check that statistics were computed
        #expect(normalizer.means["glucose"] != nil)
        #expect(normalizer.stds["glucose"] != nil)
        #expect(normalizer.means["iob"] != nil)
        #expect(normalizer.means["cob"] != nil)
        
        // Mean should be around 125 for glucose (100-150 range)
        #expect(abs(normalizer.means["glucose"]! - 124.5) < 5)
    }
    
    @Test("Feature normalizer output")
    func featureNormalizerOutput() {
        let rows = [
            createTestRow(glucose: 100, iob: 2, cob: 50),
            createTestRow(glucose: 150, iob: 4, cob: 100),
            createTestRow(glucose: 200, iob: 6, cob: 150)
        ]
        
        let normalizer = FeatureNormalizer.fit(rows: rows)
        
        // Normalize a row
        let features = normalizer.normalize(rows[0])
        
        // Should have 22 features
        #expect(features.count == 22)
        
        // First feature (glucose) should be negative for below-mean value
        // Mean is 150, row[0] is 100
        #expect(features[0] < 0)
    }
    
    // MARK: - Helpers
    
    private func createTestRow(
        glucose: Double,
        iob: Double = 2.0,
        cob: Double = 30
    ) -> MLTrainingDataRow {
        MLTrainingDataRow(
            timestamp: Date(),
            glucose: glucose,
            glucoseDelta5min: -2,
            glucoseDelta15min: -5,
            trendCode: -1,
            recentGlucose: [glucose, glucose + 2, glucose + 4, glucose + 6, glucose + 8, glucose + 10],
            iob: iob,
            cob: cob,
            hoursSinceLastBolus: 1.5,
            hoursSinceLastCarbs: 2.0,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: 110,
            hourOfDay: 12,
            dayOfWeek: 3,
            minutesSinceMidnight: 720,
            isWeekend: false,
            algorithmId: "test",
            recommendedTempBasal: 1.2,
            recommendedTempBasalDuration: 1800,
            recommendedBolus: nil,
            enactedTempBasal: 1.2,
            enactedBolus: nil,
            wasEnacted: true,
            glucose30min: nil,
            glucose60min: nil,
            glucose90min: nil,
            glucose120min: nil,
            remainedInRange: nil,
            timeInRange2hr: nil,
            minGlucose2hr: nil,
            maxGlucose2hr: nil,
            hasDataGaps: false,
            qualityScore: 0.9
        )
    }
}

@Suite("Training Target Calculator")
struct TrainingTargetCalculatorTests {
    
    @Test("Good outcome calculation")
    func targetCalculatorGoodOutcome() {
        let calculator = TrainingTargetCalculator()
        
        // Row with good outcome (in range, near target)
        let row = createTestRowWithOutcome(
            glucose: 120,
            targetGlucose: 110,
            glucose30min: 115,
            glucose60min: 112,
            glucose90min: 110,
            timeInRange2hr: 1.0,
            minGlucose2hr: 100
        )
        
        let target = calculator.calculateTarget(row)
        
        #expect(target != nil)
        // Good outcome should have scaling near 1.0
        #expect(abs(target!.scalingFactor - 1.0) < 0.2)
        #expect(target!.outcomeScore > 0.8)
    }
    
    @Test("High outcome calculation")
    func targetCalculatorHighOutcome() {
        let calculator = TrainingTargetCalculator()
        
        // Row where glucose went high (needs more insulin)
        let row = createTestRowWithOutcome(
            glucose: 120,
            targetGlucose: 110,
            glucose30min: 150,
            glucose60min: 180,
            glucose90min: 200,
            timeInRange2hr: 0.3,
            minGlucose2hr: 120
        )
        
        let target = calculator.calculateTarget(row)
        
        #expect(target != nil)
        // High outcome should suggest higher scaling
        #expect(target!.scalingFactor > 1.0)
        #expect(target!.outcomeScore < 0.7)
    }
    
    @Test("Low outcome calculation")
    func targetCalculatorLowOutcome() {
        let calculator = TrainingTargetCalculator()
        
        // Row where glucose went low (needs less insulin)
        let row = createTestRowWithOutcome(
            glucose: 100,
            targetGlucose: 110,
            glucose30min: 85,
            glucose60min: 65,
            glucose90min: 70,
            timeInRange2hr: 0.4,
            minGlucose2hr: 60
        )
        
        let target = calculator.calculateTarget(row)
        
        #expect(target != nil)
        // Low outcome should suggest lower scaling
        #expect(target!.scalingFactor < 1.0)
    }
    
    // MARK: - Helpers
    
    private func createTestRowWithOutcome(
        glucose: Double,
        targetGlucose: Double,
        glucose30min: Double,
        glucose60min: Double,
        glucose90min: Double,
        timeInRange2hr: Double,
        minGlucose2hr: Double
    ) -> MLTrainingDataRow {
        MLTrainingDataRow(
            timestamp: Date(),
            glucose: glucose,
            glucoseDelta5min: -2,
            glucoseDelta15min: -5,
            trendCode: -1,
            recentGlucose: [glucose, glucose + 2, glucose + 4, glucose + 6, glucose + 8, glucose + 10],
            iob: 2.0,
            cob: 30,
            hoursSinceLastBolus: 1.5,
            hoursSinceLastCarbs: 2.0,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: targetGlucose,
            hourOfDay: 12,
            dayOfWeek: 3,
            minutesSinceMidnight: 720,
            isWeekend: false,
            algorithmId: "test",
            recommendedTempBasal: 1.2,
            recommendedTempBasalDuration: 1800,
            recommendedBolus: nil,
            enactedTempBasal: 1.2,
            enactedBolus: nil,
            wasEnacted: true,
            glucose30min: glucose30min,
            glucose60min: glucose60min,
            glucose90min: glucose90min,
            glucose120min: glucose90min + 5,
            remainedInRange: timeInRange2hr > 0.9,
            timeInRange2hr: timeInRange2hr,
            minGlucose2hr: minGlucose2hr,
            maxGlucose2hr: max(glucose30min, glucose60min, glucose90min),
            hasDataGaps: false,
            qualityScore: 0.9
        )
    }
}

@Suite("Training Readiness")
struct TrainingReadinessTests {
    
    @Test("Insufficient data")
    func readinessInsufficientData() async {
        let config = MLTrainingPipelineConfig(minTrainingRows: 1000)
        let pipeline = MLTrainingPipeline(config: config)
        let collector = MLDataCollector()
        
        let readiness = await pipeline.checkReadiness(collector: collector)
        
        #expect(!readiness.hasEnoughData)
        #expect(readiness.currentRows == 0)
        #expect(readiness.requiredRows == 1000)
        #expect(readiness.needsRetraining)
        #expect(readiness.progressPercent == 0)
    }
}

@Suite("ML Training Pipeline")
struct MLTrainingPipelineExecutionTests {
    
    @Test("Train with insufficient data")
    func trainInsufficientData() async {
        let config = MLTrainingPipelineConfig(minTrainingRows: 100)
        let pipeline = MLTrainingPipeline(config: config)
        
        // Prepare minimal data (not enough)
        let preparedData = PreparedTrainingData(
            trainingFeatures: [[1, 2, 3]],
            trainingTargets: [TrainingTarget(scalingFactor: 1.0, tempBasalAdjust: 0, confidence: 1, outcomeScore: 0.8)],
            validationFeatures: [[1, 2, 3]],
            validationTargets: [TrainingTarget(scalingFactor: 1.0, tempBasalAdjust: 0, confidence: 1, outcomeScore: 0.8)],
            normalizer: FeatureNormalizer(means: [:], stds: [:], mins: [:], maxs: [:]),
            dataRange: (start: Date(), end: Date())
        )
        
        let result = await pipeline.train(preparedData: preparedData, algorithmId: "test")
        
        #expect(!result.success)
        #expect(result.errorMessage != nil)
        #expect(result.errorMessage!.contains("Insufficient"))
        
        let state = await pipeline.currentState
        #expect(state == .failed)
    }
    
    @Test("Train success")
    func trainSuccess() async {
        let config = MLTrainingPipelineConfig(
            minTrainingRows: 50,  // Lower for testing
            validationSplit: 0.2,
            requiredValidationAccuracy: 0.5  // Lower threshold for test
        )
        let pipeline = MLTrainingPipeline(config: config)
        
        // Create enough prepared data
        let rows = (0..<100).map { i in
            createTestRowWithOutcome(
                glucose: 100 + Double(i % 80),
                targetGlucose: 110,
                glucose30min: 110 + Double(i % 20),
                glucose60min: 115,
                glucose90min: 112,
                timeInRange2hr: 0.85,
                minGlucose2hr: 90
            )
        }
        
        let normalizer = FeatureNormalizer.fit(rows: rows)
        let targetCalc = TrainingTargetCalculator()
        
        let features = rows.map { normalizer.normalize($0) }
        let targets = rows.compactMap { targetCalc.calculateTarget($0) }
        
        let splitIndex = 80
        let preparedData = PreparedTrainingData(
            trainingFeatures: Array(features[..<splitIndex]),
            trainingTargets: Array(targets[..<splitIndex]),
            validationFeatures: Array(features[splitIndex...]),
            validationTargets: Array(targets[splitIndex...]),
            normalizer: normalizer,
            dataRange: (start: Date().addingTimeInterval(-86400 * 14), end: Date())
        )
        
        let result = await pipeline.train(preparedData: preparedData, algorithmId: "parity-loop")
        
        #expect(result.success)
        #expect(result.modelId != nil)
        #expect(result.modelVersion != nil)
        #expect(result.validationAccuracy != nil)
        #expect(result.trainingRows == 80)
        #expect(result.validationRows == 20)
        
        let state = await pipeline.currentState
        #expect(state == .active)
        
        let model = await pipeline.activeModel
        #expect(model != nil)
        #expect(model?.algorithmId == "parity-loop")
        #expect(!(model?.isExpired ?? true))
    }
    
    // MARK: - Helpers
    
    private func createTestRowWithOutcome(
        glucose: Double,
        targetGlucose: Double,
        glucose30min: Double,
        glucose60min: Double,
        glucose90min: Double,
        timeInRange2hr: Double,
        minGlucose2hr: Double
    ) -> MLTrainingDataRow {
        MLTrainingDataRow(
            timestamp: Date(),
            glucose: glucose,
            glucoseDelta5min: -2,
            glucoseDelta15min: -5,
            trendCode: -1,
            recentGlucose: [glucose, glucose + 2, glucose + 4, glucose + 6, glucose + 8, glucose + 10],
            iob: 2.0,
            cob: 30,
            hoursSinceLastBolus: 1.5,
            hoursSinceLastCarbs: 2.0,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: targetGlucose,
            hourOfDay: 12,
            dayOfWeek: 3,
            minutesSinceMidnight: 720,
            isWeekend: false,
            algorithmId: "test",
            recommendedTempBasal: 1.2,
            recommendedTempBasalDuration: 1800,
            recommendedBolus: nil,
            enactedTempBasal: 1.2,
            enactedBolus: nil,
            wasEnacted: true,
            glucose30min: glucose30min,
            glucose60min: glucose60min,
            glucose90min: glucose90min,
            glucose120min: glucose90min + 5,
            remainedInRange: timeInRange2hr > 0.9,
            timeInRange2hr: timeInRange2hr,
            minGlucose2hr: minGlucose2hr,
            maxGlucose2hr: max(glucose30min, glucose60min, glucose90min),
            hasDataGaps: false,
            qualityScore: 0.9
        )
    }
}

@Suite("Model Metadata")
struct MLModelMetadataTests {
    
    @Test("Model not expired")
    func modelMetadataExpiration() {
        let metadata = MLModelMetadata(
            modelId: "test-123",
            version: "1.0",
            createdAt: Date(),
            trainingDataStart: Date().addingTimeInterval(-86400 * 14),
            trainingDataEnd: Date(),
            trainingRows: 4032,
            validationAccuracy: 0.85,
            algorithmId: "test",
            expiresAt: Date().addingTimeInterval(86400 * 90)  // 90 days from now
        )
        
        #expect(!metadata.isExpired)
        #expect(metadata.daysUntilExpiration > 85)
    }
    
    @Test("Model expired")
    func modelMetadataExpired() {
        let metadata = MLModelMetadata(
            modelId: "test-123",
            version: "1.0",
            createdAt: Date().addingTimeInterval(-86400 * 100),  // 100 days ago
            trainingDataStart: Date().addingTimeInterval(-86400 * 114),
            trainingDataEnd: Date().addingTimeInterval(-86400 * 100),
            trainingRows: 4032,
            validationAccuracy: 0.85,
            algorithmId: "test",
            expiresAt: Date().addingTimeInterval(-86400)  // Yesterday
        )
        
        #expect(metadata.isExpired)
    }
}

@Suite("Training Result")
struct MLTrainingResultTests {
    
    @Test("Success result")
    func trainingResultSuccess() {
        let metrics = TrainingMetrics(
            scalingFactorMAE: 0.08,
            scalingFactorRMSE: 0.12,
            within20Percent: 0.85,
            trainingDuration: 2.5,
            iterationsCompleted: 100
        )
        
        let result = MLTrainingResult.success(
            modelId: "model-123",
            modelVersion: "1.0.1",
            trainingRows: 4000,
            validationRows: 800,
            validationAccuracy: 0.85,
            metrics: metrics
        )
        
        #expect(result.success)
        #expect(result.modelId == "model-123")
        #expect(result.trainingRows == 4000)
        #expect(result.errorMessage == nil)
    }
    
    @Test("Failure result")
    func trainingResultFailure() {
        let result = MLTrainingResult.failure("Validation failed")
        
        #expect(!result.success)
        #expect(result.modelId == nil)
        #expect(result.errorMessage == "Validation failed")
    }
}
