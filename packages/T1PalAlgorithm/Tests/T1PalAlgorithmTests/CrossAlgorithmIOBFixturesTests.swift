// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CrossAlgorithmIOBFixturesTests.swift
// T1Pal Mobile
//
// Tests for cross-algorithm IOB validation fixtures
// Requirements: REQ-ALGO-006
//
// Trace: ALG-NET-004, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

@Suite("Cross-Algorithm IOB Fixture Tests")
struct CrossAlgorithmIOBFixturesTests {
    
    // MARK: - Fixture Generator Tests
    
    @Test("Generator creates bolus scenarios")
    func testGeneratorCreatesBolus() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateBolusScenarios()
        
        #expect(fixtures.count >= 5, "Should generate multiple bolus scenarios")
        #expect(fixtures.allSatisfy { $0.metadata.category == "bolus" })
        #expect(fixtures.first?.id == "BOLUS-001")
    }
    
    @Test("Generator creates temp basal scenarios")
    func testGeneratorCreatesTempBasal() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateTempBasalScenarios()
        
        #expect(fixtures.count >= 3, "Should generate multiple temp basal scenarios")
        #expect(fixtures.allSatisfy { $0.metadata.category == "tempBasal" })
    }
    
    @Test("Generator creates mixed scenarios")
    func testGeneratorCreatesMixed() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateMixedScenarios()
        
        #expect(fixtures.count >= 2, "Should generate multiple mixed scenarios")
        #expect(fixtures.allSatisfy { $0.metadata.category == "mixed" })
    }
    
    @Test("Generator creates edge case scenarios")
    func testGeneratorCreatesEdgeCases() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateEdgeCaseScenarios()
        
        #expect(fixtures.count >= 3, "Should generate multiple edge case scenarios")
        #expect(fixtures.allSatisfy { $0.metadata.category == "edgeCase" })
    }
    
    @Test("Generator creates all standard scenarios")
    func testGeneratorCreatesAllScenarios() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        #expect(fixtures.count >= 15, "Should generate comprehensive scenario set")
        
        let categories = Set(fixtures.map { $0.metadata.category })
        #expect(categories.contains("bolus"))
        #expect(categories.contains("tempBasal"))
        #expect(categories.contains("mixed"))
        #expect(categories.contains("edgeCase"))
    }
    
    // MARK: - Fixture Format Tests
    
    @Test("Fixtures have required fields")
    func testFixtureStructure() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        for fixture in fixtures {
            // Required fields present
            #expect(!fixture.id.isEmpty, "Fixture must have ID")
            #expect(!fixture.description.isEmpty, "Fixture must have description")
            
            // Inputs valid
            #expect(!fixture.inputs.evaluationTime.isEmpty)
            #expect(!fixture.inputs.referenceTime.isEmpty)
            #expect(fixture.inputs.dia > 0)
            
            // Expected outputs valid
            #expect(fixture.expected.tolerance > 0)
            
            // Metadata valid
            #expect(!fixture.metadata.version.isEmpty)
            #expect(!fixture.metadata.category.isEmpty)
        }
    }
    
    @Test("Fixture IDs are unique")
    func testFixtureIDsUnique() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        let ids = fixtures.map { $0.id }
        let uniqueIds = Set(ids)
        
        #expect(ids.count == uniqueIds.count, "All fixture IDs should be unique")
    }
    
    // MARK: - JSON Serialization Tests
    
    @Test("Fixtures serialize to valid JSON")
    func testJSONSerialization() throws {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        let json = try generator.exportAsJSON(fixtures)
        #expect(json.count > 0, "JSON should not be empty")
        
        // Verify it can be parsed back
        let decoded = try JSONDecoder().decode([IOBScenarioFixture].self, from: json)
        #expect(decoded.count == fixtures.count)
    }
    
    @Test("JSON round-trip preserves data")
    func testJSONRoundTrip() throws {
        let generator = IOBFixtureGenerator()
        let original = generator.generateBolusScenarios()
        
        let json = try generator.exportAsJSON(original)
        let decoded = try JSONDecoder().decode([IOBScenarioFixture].self, from: json)
        
        #expect(decoded.count == original.count)
        
        for (orig, dec) in zip(original, decoded) {
            #expect(orig.id == dec.id)
            #expect(orig.description == dec.description)
            #expect(abs(orig.expected.loop.iob - dec.expected.loop.iob) < 0.0001)
            #expect(abs(orig.expected.oref0.iob - dec.expected.oref0.iob) < 0.0001)
            #expect(abs(orig.expected.glucos.iob - dec.expected.glucos.iob) < 0.0001)
        }
    }
    
    // MARK: - Validator Tests
    
    @Test("Validator passes freshly generated fixtures")
    func testValidatorPassesGeneratedFixtures() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        let validator = IOBFixtureValidator()
        
        let results = validator.validateAll(fixtures)
        
        let passCount = results.filter { $0.passed }.count
        #expect(passCount == results.count, "All freshly generated fixtures should pass validation")
    }
    
    @Test("Validator detects IOB differences")
    func testValidatorDetectsDifferences() {
        let generator = IOBFixtureGenerator()
        var fixtures = generator.generateBolusScenarios()
        
        // Corrupt one fixture's expected value
        if !fixtures.isEmpty {
            let original = fixtures[0]
            let corruptedExpected = IOBExpectedOutputs(
                loop: IOBAlgorithmOutput(iob: original.expected.loop.iob + 10, activity: 0),
                oref0: original.expected.oref0,
                glucos: original.expected.glucos,
                tolerance: 0.1
            )
            fixtures[0] = IOBScenarioFixture(
                id: original.id,
                description: original.description,
                inputs: original.inputs,
                expected: corruptedExpected,
                metadata: original.metadata
            )
        }
        
        let validator = IOBFixtureValidator()
        let results = validator.validateAll(fixtures)
        
        let failCount = results.filter { !$0.passed }.count
        #expect(failCount >= 1, "Should detect corrupted fixture")
    }
    
    // MARK: - Algorithm Agreement Tests
    
    @Test("Loop and oref0 agree within 20% for bolus at t=0")
    func testLoopOref0AgreementAtT0() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateBolusScenarios()
        
        // Find BOLUS-001 (immediate check)
        guard let bolus001 = fixtures.first(where: { $0.id == "BOLUS-001" }) else {
            Issue.record("BOLUS-001 fixture not found")
            return
        }
        
        let loopIOB = bolus001.expected.loop.iob
        let oref0IOB = bolus001.expected.oref0.iob
        
        // At t=0, both should show full IOB
        #expect(loopIOB > 4.5, "Loop should show ~5U IOB immediately")
        #expect(oref0IOB > 4.5, "oref0 should show ~5U IOB immediately")
        
        let percentDiff = abs(loopIOB - oref0IOB) / max(loopIOB, oref0IOB) * 100
        #expect(percentDiff < 20, "Loop and oref0 should agree within 20%")
    }
    
    @Test("oref0 and GlucOS match exactly")
    func testOref0GlucOSMatch() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        for fixture in fixtures {
            let oref0IOB = fixture.expected.oref0.iob
            let glucosIOB = fixture.expected.glucos.iob
            
            // oref0 and GlucOS use the same underlying model
            #expect(abs(oref0IOB - glucosIOB) < 0.001,
                    "oref0 and GlucOS should match exactly (same model): \(fixture.id)")
        }
    }
    
    @Test("All algorithms agree on zero IOB for empty doses")
    func testZeroIOBForEmptyDoses() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateEdgeCaseScenarios()
        
        guard let edge001 = fixtures.first(where: { $0.id == "EDGE-001" }) else {
            Issue.record("EDGE-001 fixture not found")
            return
        }
        
        #expect(edge001.expected.loop.iob == 0)
        #expect(edge001.expected.oref0.iob == 0)
        #expect(edge001.expected.glucos.iob == 0)
    }
    
    @Test("All algorithms agree on zero IOB for expired doses")
    func testZeroIOBForExpiredDoses() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateEdgeCaseScenarios()
        
        guard let edge002 = fixtures.first(where: { $0.id == "EDGE-002" }) else {
            Issue.record("EDGE-002 fixture not found")
            return
        }
        
        #expect(abs(edge002.expected.loop.iob) < 0.01)
        #expect(abs(edge002.expected.oref0.iob) < 0.01)
        #expect(abs(edge002.expected.glucos.iob) < 0.01)
    }
    
    // MARK: - Net Basal Specific Tests
    
    @Test("Temp at scheduled rate has residual IOB")
    func testTempAtScheduledRateHasResidualIOB() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateTempBasalScenarios()
        
        guard let tb003 = fixtures.first(where: { $0.id == "TEMPBASAL-003" }) else {
            Issue.record("TEMPBASAL-003 fixture not found")
            return
        }
        
        // When temp equals scheduled (1 U/hr for 1h = 1U delivered),
        // there's still residual IOB from the delivered insulin.
        // The "net" in net basal refers to (delivered - scheduled) contribution,
        // but total IOB still reflects delivered amount.
        // At t=1h after 1U delivery, we expect roughly 60-80% IOB remaining.
        #expect(tb003.expected.loop.iob > 0.5, "Loop should have residual IOB from temp")
        #expect(tb003.expected.oref0.iob > 0.5, "oref0 should have residual IOB from temp")
        #expect(tb003.expected.glucos.iob > 0.5, "GlucOS should have residual IOB from temp")
    }
    
    @Test("Suspend produces negative net IOB")
    func testNegativeIOBForSuspend() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateTempBasalScenarios()
        
        guard let tb002 = fixtures.first(where: { $0.id == "TEMPBASAL-002" }) else {
            Issue.record("TEMPBASAL-002 fixture not found")
            return
        }
        
        // Suspend should produce negative net IOB
        #expect(tb002.expected.loop.iob < 0, "Loop should show negative net IOB for suspend")
        #expect(tb002.expected.oref0.iob < 0, "oref0 should show negative net IOB for suspend")
        #expect(tb002.expected.glucos.iob < 0, "GlucOS should show negative net IOB for suspend")
    }
    
    @Test("High temp produces positive net IOB")
    func testPositiveIOBForHighTemp() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateTempBasalScenarios()
        
        guard let tb001 = fixtures.first(where: { $0.id == "TEMPBASAL-001" }) else {
            Issue.record("TEMPBASAL-001 fixture not found")
            return
        }
        
        // High temp (2 U/hr when scheduled is 1 U/hr) should produce positive net IOB
        #expect(tb001.expected.loop.iob > 0, "Loop should show positive net IOB for high temp")
        #expect(tb001.expected.oref0.iob > 0, "oref0 should show positive net IOB for high temp")
        #expect(tb001.expected.glucos.iob > 0, "GlucOS should show positive net IOB for high temp")
    }
    
    // MARK: - Decay Curve Tests
    
    @Test("IOB decreases over time")
    func testIOBDecreases() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateBolusScenarios()
        
        let bolus001 = fixtures.first { $0.id == "BOLUS-001" }
        let bolus002 = fixtures.first { $0.id == "BOLUS-002" }
        let bolus003 = fixtures.first { $0.id == "BOLUS-003" }
        let bolus004 = fixtures.first { $0.id == "BOLUS-004" }
        
        guard let b1 = bolus001, let b2 = bolus002, let b3 = bolus003, let b4 = bolus004 else {
            Issue.record("Missing bolus fixtures")
            return
        }
        
        // Loop IOB should decrease: t=0 > t=1h > t=2h > t=4h
        #expect(b1.expected.loop.iob > b2.expected.loop.iob)
        #expect(b2.expected.loop.iob > b3.expected.loop.iob)
        #expect(b3.expected.loop.iob > b4.expected.loop.iob)
        
        // Same for oref0
        #expect(b1.expected.oref0.iob > b2.expected.oref0.iob)
        #expect(b2.expected.oref0.iob > b3.expected.oref0.iob)
        #expect(b3.expected.oref0.iob > b4.expected.oref0.iob)
    }
    
    @Test("IOB near zero at DIA")
    func testIOBNearZeroAtDIA() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateBolusScenarios()
        
        guard let bolus005 = fixtures.first(where: { $0.id == "BOLUS-005" }) else {
            Issue.record("BOLUS-005 fixture not found")
            return
        }
        
        // At DIA (6h), IOB should be very low
        #expect(bolus005.expected.loop.iob < 0.1, "Loop IOB should be near zero at DIA")
        #expect(bolus005.expected.oref0.iob < 0.1, "oref0 IOB should be near zero at DIA")
        #expect(bolus005.expected.glucos.iob < 0.1, "GlucOS IOB should be near zero at DIA")
    }
    
    // MARK: - Metadata Tests
    
    @Test("Fixtures have correct tags")
    func testFixtureTags() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        // Check bolus scenarios have appropriate tags
        let bolusFixtures = fixtures.filter { $0.metadata.category == "bolus" }
        let hasSimpletag = bolusFixtures.contains { $0.metadata.tags.contains("simple") }
        #expect(hasSimpletag, "Bolus scenarios should have 'simple' tag")
        
        // Check edge cases have appropriate tags
        let edgeFixtures = fixtures.filter { $0.metadata.category == "edgeCase" }
        let hasEmptyTag = edgeFixtures.contains { $0.metadata.tags.contains("empty") }
        #expect(hasEmptyTag, "Edge cases should have 'empty' tag")
    }
    
    @Test("Metadata version is set")
    func testMetadataVersion() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateStandardScenarios()
        
        for fixture in fixtures {
            #expect(fixture.metadata.version == "1.0")
        }
    }
    
    // MARK: - Stacked Dose Tests
    
    @Test("Stacked boluses accumulate IOB")
    func testStackedBolusesAccumulate() {
        let generator = IOBFixtureGenerator()
        let fixtures = generator.generateBolusScenarios()
        
        let single = fixtures.first { $0.id == "BOLUS-002" }  // 5U at t=0, check at 1h
        let stacked = fixtures.first { $0.id == "BOLUS-006" } // 3U+2U, check at 1h
        
        guard let singleFixture = single, let stackedFixture = stacked else {
            Issue.record("Missing fixtures")
            return
        }
        
        // Stacked boluses (5U total) should have similar IOB to single 5U bolus
        // with some timing differences due to the 30m offset
        let loopDiff = abs(singleFixture.expected.loop.iob - stackedFixture.expected.loop.iob)
        #expect(loopDiff < 1.0, "Stacked and single should be within 1U")
    }
}
