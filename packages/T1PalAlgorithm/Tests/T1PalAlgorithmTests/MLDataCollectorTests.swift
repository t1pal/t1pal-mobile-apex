// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLDataCollectorTests.swift
// T1PalAlgorithmTests
//
// Tests for MLDataCollector actor.
// Trace: ALG-SHADOW-021

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("ML Data Collector")
struct MLDataCollectorTests {
    
    // MARK: - Test Helpers
    
    func makeTestInputs(glucose: Double = 120, iob: Double = 1.5, cob: Double = 25) -> AlgorithmInputs {
        AlgorithmInputs(
            glucose: [
                GlucoseReading(glucose: glucose, timestamp: Date(), trend: .flat),
                GlucoseReading(glucose: glucose - 5, timestamp: Date().addingTimeInterval(-300), trend: .flat),
                GlucoseReading(glucose: glucose - 10, timestamp: Date().addingTimeInterval(-600), trend: .flat),
                GlucoseReading(glucose: glucose - 8, timestamp: Date().addingTimeInterval(-900), trend: .flat)
            ],
            insulinOnBoard: iob,
            carbsOnBoard: cob,
            profile: TherapyProfile.default
        )
    }
    
    func makeTestDecision(tempBasal: Double? = nil, bolus: Double? = nil) -> AlgorithmDecision {
        AlgorithmDecision(
            suggestedTempBasal: tempBasal.map { TempBasal(rate: $0, duration: 1800) },
            suggestedBolus: bolus,
            reason: "Test decision"
        )
    }
    
    // MARK: - Basic Recording Tests
    
    @Test("Collector records algorithm decision")
    func recordsDecision() async {
        let collector = MLDataCollector()
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision(tempBasal: 1.5)
        
        let row = await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "TestAlgorithm",
            wasEnacted: true
        )
        
        #expect(row != nil)
        #expect(row?.glucose == 120)
        #expect(row?.algorithmId == "TestAlgorithm")
        #expect(row?.wasEnacted == true)
        
        let stats = await collector.statistics()
        #expect(stats.pendingCount == 1)
        #expect(stats.totalCollected == 1)
    }
    
    @Test("Collector respects enabled flag")
    func respectsEnabledFlag() async {
        let config = MLDataCollectorConfig(isEnabled: false)
        let collector = MLDataCollector(config: config)
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision()
        
        let row = await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "TestAlgorithm",
            wasEnacted: true
        )
        
        #expect(row == nil)
        
        let stats = await collector.statistics()
        #expect(stats.pendingCount == 0)
    }
    
    @Test("Collector skips shadow mode when disabled")
    func skipsShadowModeWhenDisabled() async {
        let config = MLDataCollectorConfig(collectShadowMode: false)
        let collector = MLDataCollector(config: config)
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision()
        
        // Non-enacted should be skipped
        let row = await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "TestAlgorithm",
            wasEnacted: false
        )
        
        #expect(row == nil)
        
        // Enacted should be recorded
        let row2 = await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "TestAlgorithm",
            wasEnacted: true
        )
        
        #expect(row2 != nil)
    }
    
    // MARK: - Outcome Tracking Tests
    
    @Test("Collector updates outcomes with glucose data")
    func updatesOutcomes() async {
        let collector = MLDataCollector()
        
        let now = Date()
        let inputs = makeTestInputs()
        let decision = makeTestDecision(tempBasal: 1.2)
        
        // Record a decision
        await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "TestAlgorithm",
            wasEnacted: true
        )
        
        // Simulate glucose readings at outcome times
        let glucoseHistory: [(date: Date, glucose: Double)] = [
            (now.addingTimeInterval(30 * 60), 115),   // 30 min
            (now.addingTimeInterval(60 * 60), 105),   // 60 min
            (now.addingTimeInterval(90 * 60), 100),   // 90 min
            (now.addingTimeInterval(120 * 60), 95)    // 120 min
        ]
        
        await collector.updateOutcomes(glucoseHistory: glucoseHistory)
        
        let stats = await collector.statistics()
        #expect(stats.pendingCount == 0)
        #expect(stats.completedCount == 1)
        #expect(stats.trainingReadyCount == 1)
    }
    
    // MARK: - Export Tests
    
    @Test("Exports training dataset")
    func exportsDataset() async {
        let collector = MLDataCollector()
        
        let now = Date()
        let inputs = makeTestInputs()
        let decision = makeTestDecision(tempBasal: 1.0)
        
        // Record and complete a row
        await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "Loop",
            wasEnacted: true
        )
        
        let glucoseHistory: [(date: Date, glucose: Double)] = [
            (now.addingTimeInterval(30 * 60), 110),
            (now.addingTimeInterval(60 * 60), 105),
            (now.addingTimeInterval(90 * 60), 100),
            (now.addingTimeInterval(120 * 60), 98)
        ]
        
        await collector.updateOutcomes(glucoseHistory: glucoseHistory)
        
        let dataset = await collector.exportDataset(algorithmId: "Loop")
        #expect(dataset.rows.count == 1)
        #expect(dataset.algorithmId == "Loop")
    }
    
    @Test("Exports CSV format")
    func exportsCSV() async {
        let collector = MLDataCollector()
        
        let now = Date()
        let inputs = makeTestInputs()
        let decision = makeTestDecision(tempBasal: 1.0)
        
        await collector.record(
            inputs: inputs,
            decision: decision,
            algorithmId: "Loop",
            wasEnacted: true
        )
        
        let glucoseHistory: [(date: Date, glucose: Double)] = [
            (now.addingTimeInterval(30 * 60), 110),
            (now.addingTimeInterval(60 * 60), 105),
            (now.addingTimeInterval(90 * 60), 100),
            (now.addingTimeInterval(120 * 60), 98)
        ]
        
        await collector.updateOutcomes(glucoseHistory: glucoseHistory)
        
        let csv = await collector.exportCSV()
        #expect(csv.contains("glucose"))  // Header
        #expect(csv.contains("Loop"))     // Algorithm ID
    }
    
    // MARK: - Statistics Tests
    
    @Test("Statistics tracks collection metrics")
    func tracksStatistics() async {
        let collector = MLDataCollector()
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision()
        
        // Record multiple decisions
        for i in 0..<5 {
            await collector.record(
                inputs: inputs,
                decision: decision,
                algorithmId: "Test\(i)",
                wasEnacted: true
            )
        }
        
        let stats = await collector.statistics()
        #expect(stats.totalCollected == 5)
        #expect(stats.pendingCount == 5)
        #expect(stats.collectionStarted != nil)
        #expect(stats.lastCollected != nil)
    }
    
    // MARK: - Management Tests
    
    @Test("Clear all removes all data")
    func clearAllRemovesData() async {
        let collector = MLDataCollector()
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision()
        
        await collector.record(inputs: inputs, decision: decision, algorithmId: "Test", wasEnacted: true)
        
        var stats = await collector.statistics()
        #expect(stats.pendingCount == 1)
        
        await collector.clearAll()
        
        stats = await collector.statistics()
        #expect(stats.pendingCount == 0)
        #expect(stats.completedCount == 0)
        #expect(stats.totalCollected == 0)
    }
    
    @Test("Training ready count requires minimum data")
    func trainingReadyCountRequiresMinimum() async {
        let collector = MLDataCollector()
        
        let hasMinimum = await collector.hasMinimumTrainingData
        #expect(hasMinimum == false)  // No data yet
        
        let count = await collector.trainingReadyCount
        #expect(count == 0)
    }
    
    // MARK: - Trim Tests
    
    @Test("Trims pending rows when over limit")
    func trimsPendingRows() async {
        let config = MLDataCollectorConfig(maxPendingRows: 3)
        let collector = MLDataCollector(config: config)
        
        let inputs = makeTestInputs()
        let decision = makeTestDecision()
        
        // Add more than limit
        for i in 0..<5 {
            await collector.record(
                inputs: inputs,
                decision: decision,
                algorithmId: "Test\(i)",
                wasEnacted: true
            )
        }
        
        let stats = await collector.statistics()
        #expect(stats.pendingCount <= 3)
    }
}
