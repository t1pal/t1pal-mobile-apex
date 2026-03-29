// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ShadowAlgorithmRunnerTests.swift
// T1PalAlgorithmTests
//
// Tests for ShadowAlgorithmRunner
// Task: ALG-SHADOW-001, ALG-SHADOW-002

import Foundation
import Testing
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Shadow Algorithm Runner")
struct ShadowAlgorithmRunnerTests {
    
    // MARK: - Configuration Tests
    
    @Test("Configure with algorithm IDs")
    func testConfigure() async {
        let runner = ShadowAlgorithmRunner()
        
        await runner.configure(algorithms: ["oref0", "Loop", "GlucOS"], primary: "oref0")
        
        let ids = await runner.algorithmIds
        #expect(ids == ["oref0", "Loop", "GlucOS"])
        #expect(await runner.enabled)
    }
    
    @Test("Disabled by default")
    func testDisabledByDefault() async {
        let runner = ShadowAlgorithmRunner()
        #expect(await runner.enabled == false)
    }
    
    @Test("Enable and disable shadow mode")
    func testEnableDisable() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0"])
        
        #expect(await runner.enabled)
        
        await runner.setEnabled(false)
        #expect(await runner.enabled == false)
        
        await runner.setEnabled(true)
        #expect(await runner.enabled)
    }
    
    // MARK: - Execution Tests
    
    @Test("Run returns empty when disabled")
    func testRunWhenDisabled() async {
        let runner = ShadowAlgorithmRunner()
        // Not configured, so disabled
        
        let inputs = createTestInputs()
        let result = await runner.run(inputs: inputs)
        
        #expect(result.recommendations.isEmpty)
    }
    
    @Test("Run executes configured algorithms")
    func testRunExecutesAlgorithms() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0", "Loop"], primary: "oref0")
        
        let inputs = createTestInputs()
        let result = await runner.run(inputs: inputs)
        
        #expect(result.recommendations.count == 2)
        #expect(result.recommendations.contains { $0.algorithmId == "oref0" })
        #expect(result.recommendations.contains { $0.algorithmId == "Loop" })
    }
    
    @Test("Run captures input values")
    func testRunCapturesInputs() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0"])
        
        let inputs = createTestInputs(glucose: 150, iob: 2.5, cob: 30)
        let result = await runner.run(inputs: inputs)
        
        #expect(result.inputGlucose == 150)
        #expect(result.inputIOB == 2.5)
        #expect(result.inputCOB == 30)
    }
    
    @Test("Run handles missing algorithm gracefully")
    func testRunMissingAlgorithm() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["nonexistent_algorithm"])
        
        let inputs = createTestInputs()
        let result = await runner.run(inputs: inputs)
        
        #expect(result.recommendations.count == 1)
        let rec = result.recommendations[0]
        #expect(rec.success == false)
        #expect(rec.error != nil)
    }
    
    // MARK: - History Tests
    
    @Test("Stores results in history")
    func testStoresHistory() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0"])
        
        let inputs = createTestInputs()
        _ = await runner.run(inputs: inputs)
        _ = await runner.run(inputs: inputs)
        _ = await runner.run(inputs: inputs)
        
        let history = await runner.recentHistory(count: 10)
        #expect(history.count == 3)
    }
    
    @Test("History respects max size")
    func testHistoryMaxSize() async {
        let runner = ShadowAlgorithmRunner(maxHistorySize: 5)
        await runner.configure(algorithms: ["oref0"])
        
        let inputs = createTestInputs()
        for _ in 0..<10 {
            _ = await runner.run(inputs: inputs)
        }
        
        let history = await runner.recentHistory(count: 100)
        #expect(history.count == 5)
    }
    
    @Test("Clear history")
    func testClearHistory() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0"])
        
        let inputs = createTestInputs()
        _ = await runner.run(inputs: inputs)
        
        await runner.clearHistory()
        
        let history = await runner.recentHistory()
        #expect(history.isEmpty)
    }
    
    // MARK: - Divergence Detection Tests
    
    @Test("Detects unanimous results")
    func testUnanimousDetection() async {
        // When all algorithms suggest similar rates, isUnanimous should be true
        let result = ShadowRunResult(
            inputGlucose: 120,
            inputIOB: 1.0,
            inputCOB: 0,
            recommendations: [
                ShadowRecommendation(algorithmId: "a", algorithmName: "A", suggestedTempBasalRate: 1.0),
                ShadowRecommendation(algorithmId: "b", algorithmName: "B", suggestedTempBasalRate: 1.05)
            ]
        )
        
        #expect(result.isUnanimous)
    }
    
    @Test("Detects divergent results")
    func testDivergentDetection() async {
        // When algorithms suggest very different rates, isUnanimous should be false
        let result = ShadowRunResult(
            inputGlucose: 120,
            inputIOB: 1.0,
            inputCOB: 0,
            recommendations: [
                ShadowRecommendation(algorithmId: "a", algorithmName: "A", suggestedTempBasalRate: 0.5),
                ShadowRecommendation(algorithmId: "b", algorithmName: "B", suggestedTempBasalRate: 2.0)
            ]
        )
        
        #expect(!result.isUnanimous)
    }
    
    @Test("Divergence stats calculated correctly")
    func testDivergenceStats() async {
        let runner = ShadowAlgorithmRunner()
        await runner.configure(algorithms: ["oref0", "Loop"])
        
        // Run a few times
        let inputs = createTestInputs()
        for _ in 0..<5 {
            _ = await runner.run(inputs: inputs)
        }
        
        let stats = await runner.divergenceStats()
        #expect(stats.totalRuns == 5)
        #expect(stats.unanimousRuns + stats.divergentRuns == stats.totalRuns)
    }
    
    // MARK: - Helpers
    
    private func createTestInputs(glucose: Double = 120, iob: Double = 1.0, cob: Double = 0) -> AlgorithmInputs {
        let reading = GlucoseReading(glucose: glucose, timestamp: Date(), trend: .flat)
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110),
            maxIOB: 8.0,
            maxBolus: 10.0
        )
        
        return AlgorithmInputs(
            glucose: [reading],
            insulinOnBoard: iob,
            carbsOnBoard: cob,
            profile: profile
        )
    }
}
