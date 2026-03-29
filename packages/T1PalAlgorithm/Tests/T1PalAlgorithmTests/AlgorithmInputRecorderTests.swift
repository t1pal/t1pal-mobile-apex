// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmInputRecorderTests.swift
// T1PalAlgorithmTests
//
// Tests for AlgorithmInputRecorder
// Task: ALG-SHADOW-010

import Foundation
import Testing
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Algorithm Input Recorder")
struct AlgorithmInputRecorderTests {
    
    // MARK: - Configuration Tests
    
    @Test("Disabled by default")
    func testDisabledByDefault() async {
        let recorder = AlgorithmInputRecorder()
        #expect(await recorder.enabled == false)
    }
    
    @Test("Enable and disable recording")
    func testEnableDisable() async {
        let recorder = AlgorithmInputRecorder()
        
        await recorder.setEnabled(true)
        #expect(await recorder.enabled)
        
        await recorder.setEnabled(false)
        #expect(await recorder.enabled == false)
    }
    
    // MARK: - Recording Tests
    
    @Test("Recording when disabled does nothing")
    func testRecordingWhenDisabled() async {
        let recorder = AlgorithmInputRecorder()
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "test", reason: "Test")
        
        await recorder.record(inputs: inputs, outputs: [output])
        
        let count = await recorder.sessionCount
        #expect(count == 0)
    }
    
    @Test("Recording when enabled stores session")
    func testRecordingWhenEnabled() async {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "oref0", tempBasalRate: 1.5, reason: "Test")
        
        await recorder.record(inputs: inputs, outputs: [output])
        
        let count = await recorder.sessionCount
        #expect(count == 1)
        
        let sessions = await recorder.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].outputs[0].algorithmId == "oref0")
        #expect(sessions[0].outputs[0].tempBasalRate == 1.5)
    }
    
    @Test("Records single algorithm run")
    func testRecordSingle() async {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let decision = AlgorithmDecision(
            suggestedTempBasal: TempBasal(rate: 2.0, duration: 1800),
            reason: "Test decision"
        )
        
        await recorder.recordSingle(
            inputs: inputs,
            algorithmId: "Loop",
            decision: decision,
            executionTimeMs: 5.0
        )
        
        let sessions = await recorder.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].outputs[0].algorithmId == "Loop")
        #expect(sessions[0].outputs[0].tempBasalRate == 2.0)
        #expect(sessions[0].outputs[0].executionTimeMs == 5.0)
    }
    
    @Test("Records errors")
    func testRecordError() async {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test error" }
        }
        
        await recorder.recordError(
            inputs: inputs,
            algorithmId: "GlucOS",
            error: TestError(),
            executionTimeMs: 1.0
        )
        
        let sessions = await recorder.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].outputs[0].success == false)
        #expect(sessions[0].outputs[0].error != nil)
    }
    
    // MARK: - History Tests
    
    @Test("Respects max session limit")
    func testMaxSessions() async {
        let recorder = AlgorithmInputRecorder(maxSessions: 5)
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        for i in 0..<10 {
            let output = RecordedOutput(algorithmId: "test\(i)", reason: "Test \(i)")
            await recorder.record(inputs: inputs, outputs: [output])
        }
        
        let count = await recorder.sessionCount
        #expect(count == 5)
    }
    
    @Test("Recent sessions returns subset")
    func testRecentSessions() async {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        for i in 0..<10 {
            let output = RecordedOutput(algorithmId: "test\(i)", reason: "Test \(i)")
            await recorder.record(inputs: inputs, outputs: [output])
        }
        
        let recent = await recorder.recentSessions(count: 3)
        #expect(recent.count == 3)
    }
    
    @Test("Clear removes all sessions")
    func testClear() async {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "test", reason: "Test")
        await recorder.record(inputs: inputs, outputs: [output])
        
        await recorder.clear()
        
        let count = await recorder.sessionCount
        #expect(count == 0)
    }
    
    // MARK: - Export/Import Tests
    
    @Test("Export and import JSON roundtrip")
    func testExportImportRoundtrip() async throws {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "oref0", tempBasalRate: 1.5, reason: "Test")
        await recorder.record(inputs: inputs, outputs: [output])
        
        // Export
        let json = try await recorder.exportJSON()
        #expect(!json.isEmpty)
        
        // Create new recorder and import
        let newRecorder = AlgorithmInputRecorder()
        let imported = try await newRecorder.importJSON(json)
        #expect(imported == 1)
        
        let sessions = await newRecorder.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].outputs[0].algorithmId == "oref0")
    }
    
    // MARK: - Input Conversion Tests
    
    @Test("RecordedInputs roundtrip conversion")
    func testInputsRoundtrip() {
        let inputs = createTestInputs()
        let recorded = RecordedInputs(from: inputs)
        let restored = recorded.toAlgorithmInputs()
        
        #expect(restored.glucose.count == inputs.glucose.count)
        #expect(restored.insulinOnBoard == inputs.insulinOnBoard)
        #expect(restored.carbsOnBoard == inputs.carbsOnBoard)
    }
    
    // MARK: - Fixture Export Tests (ALG-SHADOW-011)
    
    @Test("Export single session as fixture")
    func testExportSingleFixture() async throws {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "oref0", tempBasalRate: 1.5, reason: "Test fixture")
        await recorder.record(inputs: inputs, outputs: [output])
        
        let sessions = await recorder.allSessions()
        let fixtureData = try await recorder.exportFixture(sessions[0])
        
        // Verify it's valid JSON and can be decoded
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordedSession.self, from: fixtureData)
        
        #expect(decoded.outputs[0].algorithmId == "oref0")
        #expect(decoded.outputs[0].tempBasalRate == 1.5)
    }
    
    @Test("Export fixture with generated filename")
    func testExportFixtureWithName() async throws {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        let output = RecordedOutput(algorithmId: "oref0", reason: "Test")
        await recorder.record(inputs: inputs, outputs: [output])
        
        let sessions = await recorder.allSessions()
        let (filename, data) = try await recorder.exportFixtureWithName(sessions[0])
        
        #expect(filename.hasPrefix("algorithm_fixture_"))
        #expect(filename.hasSuffix(".json"))
        #expect(filename.contains("oref0"))
        #expect(data.count > 0)
    }
    
    @Test("Export all fixtures")
    func testExportAllFixtures() async throws {
        let recorder = AlgorithmInputRecorder()
        await recorder.setEnabled(true)
        
        let inputs = createTestInputs()
        await recorder.record(inputs: inputs, outputs: [RecordedOutput(algorithmId: "test1")])
        await recorder.record(inputs: inputs, outputs: [RecordedOutput(algorithmId: "test2")])
        await recorder.record(inputs: inputs, outputs: [RecordedOutput(algorithmId: "test3")])
        
        let fixtures = try await recorder.exportAllFixtures()
        
        #expect(fixtures.count == 3)
        #expect(fixtures.allSatisfy { $0.filename.hasSuffix(".json") })
    }
    
    @Test("Create sample fixture")
    func testCreateSampleFixture() {
        let fixture = AlgorithmInputRecorder.createSampleFixture(
            glucose: 150,
            iob: 2.0,
            cob: 15,
            algorithmResults: [("oref0", 1.5, "Test result")]
        )
        
        #expect(fixture.inputs.glucose[0].value == 150)
        #expect(fixture.inputs.insulinOnBoard == 2.0)
        #expect(fixture.inputs.carbsOnBoard == 15)
        #expect(fixture.outputs.count == 1)
        #expect(fixture.outputs[0].algorithmId == "oref0")
        #expect(fixture.outputs[0].tempBasalRate == 1.5)
    }
    
    @Test("Generate test fixture suite")
    func testGenerateTestFixtures() {
        let fixtures = AlgorithmInputRecorder.generateTestFixtures()
        
        #expect(fixtures.count == 4)
        
        // Verify different scenarios
        let glucoseValues = fixtures.map { $0.inputs.glucose[0].value }
        #expect(glucoseValues.contains(65))   // Low
        #expect(glucoseValues.contains(110))  // In-range
        #expect(glucoseValues.contains(200))  // High
        #expect(glucoseValues.contains(140))  // With carbs
        
        // Verify carbs scenario
        let withCarbs = fixtures.first { $0.inputs.carbsOnBoard > 0 }
        #expect(withCarbs != nil)
        #expect(withCarbs?.inputs.carbsOnBoard == 30)
    }
    
    @Test("Sample fixture is valid and encodable")
    func testSampleFixtureEncodable() throws {
        let fixture = AlgorithmInputRecorder.createSampleFixture()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fixture)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordedSession.self, from: data)
        
        #expect(decoded.inputs.glucose.count == fixture.inputs.glucose.count)
        #expect(decoded.outputs.count == fixture.outputs.count)
    }
    
    // MARK: - Helpers
    
    private func createTestInputs() -> AlgorithmInputs {
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat)
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
            insulinOnBoard: 1.0,
            carbsOnBoard: 0,
            profile: profile
        )
    }
}
