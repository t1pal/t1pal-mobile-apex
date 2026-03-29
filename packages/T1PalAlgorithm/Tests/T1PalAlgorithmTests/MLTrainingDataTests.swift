// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLTrainingDataTests.swift
// T1PalAlgorithmTests
//
// Tests for ML training data schema.
// Trace: ALG-SHADOW-020

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("ML Training Data Schema")
struct MLTrainingDataTests {
    
    @Test("MLTrainingDataRow is Codable")
    func trainingRowIsCodable() throws {
        let row = MLTrainingDataRow(
            glucose: 120,
            iob: 1.5,
            cob: 25,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: 100,
            hourOfDay: 14,
            dayOfWeek: 3,
            minutesSinceMidnight: 840,
            isWeekend: false,
            algorithmId: "SimpleProportional"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(row)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MLTrainingDataRow.self, from: data)
        
        #expect(decoded.glucose == 120)
        #expect(decoded.iob == 1.5)
        #expect(decoded.algorithmId == "SimpleProportional")
    }
    
    @Test("MLTrainingDataRow CSV export")
    func trainingRowCSVExport() {
        let row = MLTrainingDataRow(
            glucose: 150,
            iob: 2.0,
            cob: 30,
            basalRate: 1.2,
            isf: 45,
            carbRatio: 12,
            targetGlucose: 100,
            hourOfDay: 10,
            dayOfWeek: 2,
            minutesSinceMidnight: 600,
            isWeekend: false,
            algorithmId: "LoopAlgorithm"
        )
        
        let csv = row.csvRow
        #expect(csv.contains("150"))
        #expect(csv.contains("2.0"))
        #expect(csv.contains("LoopAlgorithm"))
    }
    
    @Test("MLTrainingDataRow factory creates from inputs")
    func factoryCreatesFromInputs() {
        let glucose = GlucoseReading(
            glucose: 130,
            timestamp: Date(),
            trend: .fortyFiveUp,
            source: "test"
        )
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.1)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let inputs = AlgorithmInputs(
            glucose: [glucose],
            insulinOnBoard: 1.0,
            carbsOnBoard: 20,
            profile: profile
        )
        
        let decision = AlgorithmDecision(
            suggestedTempBasal: TempBasal(rate: 0.5, duration: 1800),
            reason: "Test"
        )
        
        let row = MLTrainingDataRow.from(
            inputs: inputs,
            decision: decision,
            algorithmId: "test-algo",
            wasEnacted: true
        )
        
        #expect(row.glucose == 130)
        #expect(row.iob == 1.0)
        #expect(row.cob == 20)
        #expect(row.recommendedTempBasal == 0.5)
        #expect(row.wasEnacted == true)
        #expect(row.trendCode == 1) // fortyFiveUp = 1
    }
    
    @Test("MLTrainingDataRow outcome update")
    func outcomeUpdate() {
        let row = MLTrainingDataRow(
            glucose: 120,
            iob: 1.0,
            cob: 0,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: 100,
            hourOfDay: 12,
            dayOfWeek: 4,
            minutesSinceMidnight: 720,
            isWeekend: false,
            algorithmId: "test",
            wasEnacted: true
        )
        
        let updated = row.withOutcomes(
            glucose30min: 115,
            glucose60min: 110,
            glucose90min: 105,
            glucose120min: 100,
            glucoseHistory: [120, 118, 115, 112, 110, 108, 105, 102, 100]
        )
        
        #expect(updated.glucose30min == 115)
        #expect(updated.glucose60min == 110)
        #expect(updated.hasCompleteOutcomes == true)
        #expect(updated.isTrainingReady == true)
        #expect(updated.remainedInRange == true)
    }
    
    @Test("MLTrainingDataset CSV export")
    func datasetCSVExport() {
        let rows = [
            MLTrainingDataRow(
                glucose: 100,
                iob: 1.0,
                cob: 0,
                basalRate: 1.0,
                isf: 50,
                carbRatio: 10,
                targetGlucose: 100,
                hourOfDay: 8,
                dayOfWeek: 1,
                minutesSinceMidnight: 480,
                isWeekend: true,
                algorithmId: "test"
            ),
            MLTrainingDataRow(
                glucose: 120,
                iob: 0.5,
                cob: 10,
                basalRate: 1.0,
                isf: 50,
                carbRatio: 10,
                targetGlucose: 100,
                hourOfDay: 12,
                dayOfWeek: 1,
                minutesSinceMidnight: 720,
                isWeekend: true,
                algorithmId: "test"
            )
        ]
        
        let dataset = MLTrainingDataset(rows: rows, algorithmId: "test", version: "1.0")
        let csv = dataset.toCSV()
        
        #expect(csv.contains("id,timestamp,glucose"))
        #expect(csv.contains("100"))
        #expect(csv.contains("120"))
    }
    
    @Test("Training ready filtering")
    func trainingReadyFiltering() {
        let readyRow = MLTrainingDataRow(
            glucose: 100,
            iob: 1.0,
            cob: 0,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: 100,
            hourOfDay: 8,
            dayOfWeek: 1,
            minutesSinceMidnight: 480,
            isWeekend: true,
            algorithmId: "test",
            wasEnacted: true,
            glucose30min: 100,
            glucose60min: 100,
            glucose90min: 100,
            hasDataGaps: false
        )
        
        let notReadyRow = MLTrainingDataRow(
            glucose: 120,
            iob: 0.5,
            cob: 10,
            basalRate: 1.0,
            isf: 50,
            carbRatio: 10,
            targetGlucose: 100,
            hourOfDay: 12,
            dayOfWeek: 1,
            minutesSinceMidnight: 720,
            isWeekend: true,
            algorithmId: "test",
            wasEnacted: false // Not enacted
        )
        
        let dataset = MLTrainingDataset(rows: [readyRow, notReadyRow], algorithmId: "test")
        
        #expect(dataset.trainingReadyCount == 1)
        #expect(dataset.trainingReadyRows.count == 1)
        #expect(dataset.trainingReadyRows[0].glucose == 100)
    }
}
