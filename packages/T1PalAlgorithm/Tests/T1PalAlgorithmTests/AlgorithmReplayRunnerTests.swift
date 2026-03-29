// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmReplayRunnerTests.swift
// T1PalAlgorithmTests
//
// Tests for AlgorithmReplayRunner
// Task: ALG-SHADOW-012

import Foundation
import Testing
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Algorithm Replay Runner")
struct AlgorithmReplayRunnerTests {
    
    // MARK: - Configuration Tests
    
    @Test("Default algorithms from registry")
    func testDefaultAlgorithms() async {
        let runner = AlgorithmReplayRunner()
        let algorithms = await runner.getAlgorithms()
        
        // Should include registered algorithms
        #expect(algorithms.count > 0)
    }
    
    @Test("Set custom algorithms")
    func testSetAlgorithms() async {
        let runner = AlgorithmReplayRunner()
        await runner.setAlgorithms(["oref0", "Loop"])
        
        let algorithms = await runner.getAlgorithms()
        #expect(algorithms == ["oref0", "Loop"])
    }
    
    // MARK: - Replay Tests
    
    @Test("Replay single session")
    func testReplaySingleSession() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.replay(session: session)
        
        #expect(report.session.id == session.id)
        #expect(report.results.count == 1)
        #expect(report.results[0].algorithmId == "GlucOS")
    }
    
    @Test("Replay records in history")
    func testReplayRecordsHistory() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        _ = await runner.replay(session: session)
        
        let history = await runner.allHistory()
        #expect(history.count == 1)
    }
    
    @Test("Clear history")
    func testClearHistory() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        _ = await runner.replay(session: session)
        await runner.clearHistory()
        
        let history = await runner.allHistory()
        #expect(history.count == 0)
    }
    
    // MARK: - Divergence Tests
    
    @Test("Divergence level none for identical results")
    func testDivergenceNone() {
        let level = AlgorithmDivergence.DivergenceLevel.none
        #expect(level.rawValue == "none")
    }
    
    @Test("Divergence levels exist")
    func testDivergenceLevels() {
        let levels: [AlgorithmDivergence.DivergenceLevel] = [.none, .minor, .moderate, .significant, .opposite]
        #expect(levels.count == 5)
    }
    
    // MARK: - Summary Tests
    
    @Test("Summary calculates agreement ratio")
    func testSummaryAgreementRatio() {
        let summary = AlgorithmReplaySummary(
            totalAlgorithms: 10,
            equivalentCount: 6,
            minorDivergenceCount: 2,
            moderateDivergenceCount: 1,
            significantDivergenceCount: 1,
            oppositeDivergenceCount: 0,
            averageExecutionTimeMs: 5.0
        )
        
        // Agreement = (equivalent + minor) / total = 8/10 = 0.8
        #expect(summary.agreementRatio == 0.8)
    }
    
    @Test("Summary detects significant divergence")
    func testSummarySignificantDivergence() {
        let withSignificant = AlgorithmReplaySummary(
            totalAlgorithms: 5,
            equivalentCount: 4,
            minorDivergenceCount: 0,
            moderateDivergenceCount: 0,
            significantDivergenceCount: 1,
            oppositeDivergenceCount: 0,
            averageExecutionTimeMs: 5.0
        )
        
        let withoutSignificant = AlgorithmReplaySummary(
            totalAlgorithms: 5,
            equivalentCount: 4,
            minorDivergenceCount: 1,
            moderateDivergenceCount: 0,
            significantDivergenceCount: 0,
            oppositeDivergenceCount: 0,
            averageExecutionTimeMs: 5.0
        )
        
        #expect(withSignificant.hasSignificantDivergence)
        #expect(!withoutSignificant.hasSignificantDivergence)
    }
    
    // MARK: - Batch Replay Tests
    
    @Test("Batch replay multiple sessions")
    func testBatchReplay() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession(), createTestSession(), createTestSession()]
        
        let report = await runner.replayBatch(sessions: sessions)
        
        #expect(report.sessionReports.count == 3)
        #expect(report.batchSummary.totalSessions == 3)
    }
    
    @Test("Batch summary calculates overall agreement")
    func testBatchSummaryAgreement() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession(), createTestSession()]
        
        let report = await runner.replayBatch(sessions: sessions)
        
        // Agreement should be between 0 and 1
        #expect(report.batchSummary.overallAgreementRatio >= 0)
        #expect(report.batchSummary.overallAgreementRatio <= 1)
    }
    
    // MARK: - Export Tests
    
    @Test("Export session report as JSON")
    func testExportSessionReport() async throws {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.replay(session: session)
        let json = try await runner.exportSessionReport(report)
        
        #expect(json.count > 0)
        
        // Verify valid JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AlgorithmReplayReport.self, from: json)
        #expect(decoded.id == report.id)
    }
    
    @Test("Export batch report as JSON")
    func testExportBatchReport() async throws {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession(), createTestSession()]
        
        let report = await runner.replayBatch(sessions: sessions)
        let json = try await runner.exportReport(report)
        
        #expect(json.count > 0)
    }
    
    // MARK: - What-If Report Tests (ALG-SHADOW-014)
    
    @Test("Generate what-if report from session")
    func testGenerateWhatIfReport() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.generateWhatIfReport(session: session, title: "Test What-If")
        
        #expect(report.title == "Test What-If")
        #expect(report.scenarios.count == 1)
        #expect(report.inputSummary.glucose == 120)
    }
    
    @Test("What-if report has correct summary")
    func testWhatIfReportSummary() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.generateWhatIfReport(session: session)
        
        #expect(report.summary.totalAlgorithms == 1)
        #expect(report.summary.agreementCount + report.summary.divergentCount == 1)
    }
    
    @Test("Format what-if report as markdown")
    func testFormatWhatIfAsMarkdown() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.generateWhatIfReport(session: session, title: "Markdown Test")
        let markdown = await runner.formatAsMarkdown(report)
        
        #expect(markdown.contains("# Markdown Test"))
        #expect(markdown.contains("## Input State"))
        #expect(markdown.contains("## Algorithm Recommendations"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("120 mg/dL"))
    }
    
    @Test("Generate batch what-if report")
    func testGenerateBatchWhatIfReport() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession(), createTestSession()]
        
        let report = await runner.generateBatchWhatIfReport(sessions: sessions, title: "Batch Test")
        
        #expect(report.title == "Batch Test")
        #expect(report.reports.count == 2)
        #expect(report.batchSummary.totalSessions == 2)
    }
    
    @Test("Batch what-if report calculates agreement ratio")
    func testBatchWhatIfAgreementRatio() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession(), createTestSession()]
        
        let report = await runner.generateBatchWhatIfReport(sessions: sessions)
        
        #expect(report.batchSummary.overallAgreementRatio >= 0)
        #expect(report.batchSummary.overallAgreementRatio <= 1)
    }
    
    @Test("Format batch what-if report as markdown")
    func testFormatBatchWhatIfAsMarkdown() async {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession()]
        
        let report = await runner.generateBatchWhatIfReport(sessions: sessions)
        let markdown = await runner.formatBatchAsMarkdown(report)
        
        #expect(markdown.contains("## Overall Summary"))
        #expect(markdown.contains("Sessions analyzed"))
    }
    
    @Test("Export what-if report as JSON")
    func testExportWhatIfReport() async throws {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let session = createTestSession()
        
        let report = await runner.generateWhatIfReport(session: session)
        let json = try await runner.exportWhatIfReport(report)
        
        #expect(json.count > 0)
        
        // Verify roundtrip
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WhatIfReport.self, from: json)
        #expect(decoded.id == report.id)
    }
    
    @Test("Export batch what-if report as JSON")
    func testExportBatchWhatIfReport() async throws {
        let runner = AlgorithmReplayRunner(algorithmIds: ["GlucOS"])
        let sessions = [createTestSession()]
        
        let report = await runner.generateBatchWhatIfReport(sessions: sessions)
        let json = try await runner.exportBatchWhatIfReport(report)
        
        #expect(json.count > 0)
    }
    
    // MARK: - Helpers
    
    private func createTestSession() -> RecordedSession {
        let inputs = RecordedInputs(
            glucose: [RecordedGlucose(value: 120, timestamp: Date(), trend: "flat")],
            insulinOnBoard: 1.0,
            carbsOnBoard: 0,
            profile: RecordedProfile(
                basalRates: [RecordedBasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [RecordedCarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [RecordedSensitivityFactor(startTime: 0, factor: 50)],
                targetLow: 90,
                targetHigh: 110
            ),
            currentTime: Date()
        )
        
        let output = RecordedOutput(
            algorithmId: "GlucOS",
            tempBasalRate: 1.0,
            reason: "Test output"
        )
        
        return RecordedSession(
            inputs: inputs,
            outputs: [output]
        )
    }
}
