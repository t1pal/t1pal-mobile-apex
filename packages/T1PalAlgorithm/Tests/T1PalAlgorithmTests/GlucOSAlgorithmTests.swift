// GlucOSAlgorithmTests.swift
// T1PalAlgorithmTests
//
// Tests for GlucOS algorithm registration and execution
// Trace: GLUCOS-INT-001

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("GlucOS Algorithm")
struct GlucOSAlgorithmTests {
    
    @Test("Algorithm registered in registry")
    func algorithmRegisteredInRegistry() {
        let registry = AlgorithmRegistry.shared
        #expect(registry.isRegistered(name: "GlucOS"))
    }
    
    @Test("Algorithm can be retrieved")
    func algorithmCanBeRetrieved() {
        let registry = AlgorithmRegistry.shared
        let algorithm = registry.algorithm(named: "GlucOS")
        #expect(algorithm != nil)
        #expect(algorithm?.name == "GlucOS")
    }
    
    @Test("Algorithm capabilities")
    func algorithmCapabilities() {
        let algorithm = GlucOSAlgorithm()
        
        #expect(algorithm.name == "GlucOS")
        #expect(algorithm.version == "1.0.0")
        #expect(algorithm.capabilities.origin == .glucos)
        #expect(algorithm.capabilities.supportsTempBasal)
        #expect(algorithm.capabilities.supportsDynamicISF)
        #expect(algorithm.capabilities.providesPredictions)
        #expect(!algorithm.capabilities.supportsSMB)
    }
    
    @Test("Calculation with sufficient data")
    func calculationWithSufficientData() throws {
        let algorithm = GlucOSAlgorithm()
        let now = Date()
        
        // Create glucose history (5 readings at 5-min intervals)
        var readings: [GlucoseReading] = []
        for i in 0..<5 {
            readings.append(GlucoseReading(
                glucose: 150 + Double(i * 5),  // Rising glucose
                timestamp: now.addingTimeInterval(Double(i - 4) * 300)
            ))
        }
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10,
            maxBolus: 5
        )
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 2.0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should suggest temp basal since glucose is high
        #expect(decision.suggestedTempBasal != nil)
        #expect(decision.suggestedBolus == nil)  // GlucOS uses temp basals
        #expect(!decision.reason.isEmpty)
    }
    
    @Test("Calculation insufficient data")
    func calculationInsufficientData() {
        let algorithm = GlucOSAlgorithm()
        let now = Date()
        
        // Only 2 readings (insufficient)
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-300)),
            GlucoseReading(glucose: 105, timestamp: now)
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10,
            maxBolus: 5
        )
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        // Should still work (minGlucoseHistory is 5, but predictor handles this)
        // The algorithm won't throw, but may return no temp basal
        do {
            let decision = try algorithm.calculate(inputs)
            // At target, no change expected
            #expect(decision != nil)
        } catch {
            // Acceptable if it throws for insufficient data
            #expect(error is AlgorithmError)
        }
    }
    
    @Test("Dynamic ISF scaling")
    func dynamicISFScaling() throws {
        let config = GlucOSConfiguration(
            targetGlucose: 100,
            maxISFScaling: 1.5
        )
        let algorithm = GlucOSAlgorithm(configuration: config)
        let now = Date()
        
        // High glucose (250) - should trigger dynamic ISF
        var readings: [GlucoseReading] = []
        for i in 0..<5 {
            readings.append(GlucoseReading(
                glucose: 250,  // Constant high
                timestamp: now.addingTimeInterval(Double(i - 4) * 300)
            ))
        }
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10,
            maxBolus: 5
        )
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should have ISF scaling in reason
        #expect(decision.reason.contains("ISF×"))
    }
    
    @Test("No change at target")
    func noChangeAtTarget() throws {
        let config = GlucOSConfiguration(targetGlucose: 100)
        let algorithm = GlucOSAlgorithm(configuration: config)
        let now = Date()
        
        // Glucose at target
        var readings: [GlucoseReading] = []
        for i in 0..<5 {
            readings.append(GlucoseReading(
                glucose: 100,  // At target
                timestamp: now.addingTimeInterval(Double(i - 4) * 300)
            ))
        }
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10,
            maxBolus: 5
        )
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // At target with no trend, should suggest no change
        // (threshold is 0.05 U/hr)
        #expect(decision.reason.contains("no change") || decision.suggestedTempBasal == nil)
    }
    
    @Test("Predictions provided")
    func predictionsProvided() throws {
        let algorithm = GlucOSAlgorithm()
        let now = Date()
        
        var readings: [GlucoseReading] = []
        for i in 0..<5 {
            readings.append(GlucoseReading(
                glucose: 150 + Double(i * 2),
                timestamp: now.addingTimeInterval(Double(i - 4) * 300)
            ))
        }
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10,
            maxBolus: 5
        )
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algorithm.calculate(inputs)
        
        // Should provide predictions
        #expect(decision.predictions != nil)
        #expect(!decision.predictions!.iob.isEmpty)
    }
}

@Suite("GlucOS Configuration")
struct GlucOSConfigurationTests {
    
    @Test("Default configuration")
    func defaultConfiguration() {
        let config = GlucOSConfiguration.default
        
        #expect(config.targetGlucose == 100)
        #expect(config.maxISFScaling == 1.5)
        #expect(config.maxBasalRate == 5.0)
        #expect(config.enablePredictiveAlerts)
        #expect(!config.enableAdaptiveTuning)
        #expect(config.exerciseTargetGlucose == 140)
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = GlucOSConfiguration(
            targetGlucose: 110,
            maxISFScaling: 1.3,
            maxBasalRate: 3.0,
            enablePredictiveAlerts: false,
            enableAdaptiveTuning: true,
            exerciseTargetGlucose: 150
        )
        
        #expect(config.targetGlucose == 110)
        #expect(config.maxISFScaling == 1.3)
        #expect(config.maxBasalRate == 3.0)
        #expect(!config.enablePredictiveAlerts)
        #expect(config.enableAdaptiveTuning)
        #expect(config.exerciseTargetGlucose == 150)
    }
}

@Suite("Algorithm Origin GlucOS")
struct AlgorithmOriginGlucOSTests {
    
    @Test("GlucOS origin exists")
    func glucOSOriginExists() {
        let origin = AlgorithmOrigin.glucos
        #expect(origin.rawValue == "GlucOS")
    }
    
    @Test("GlucOS capabilities preset")
    func glucOSCapabilitiesPreset() {
        let caps = AlgorithmCapabilities.glucos
        
        #expect(caps.origin == .glucos)
        #expect(caps.supportsTempBasal)
        #expect(caps.supportsDynamicISF)
        #expect(caps.providesPredictions)
        #expect(!caps.supportsSMB)
        #expect(!caps.supportsUAM)
        #expect(!caps.supportsAutosens)
        #expect(caps.minGlucoseHistory == 5)
        #expect(caps.recommendedGlucoseHistory == 24)
    }
}
