// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicBolusConformanceTests.swift
// PumpKitTests
//
// MDT-SYNTH-004: Bolus Command Conformance Tests
// Extracted from MedtronicConformanceTests.swift
//
// Trace: MDT-SYNTH-004

import Testing
import Foundation
@testable import PumpKit

// MARK: - MDT-SYNTH-004: Bolus Command Conformance Tests

@Suite("MedtronicBolusConformanceTests")
struct MedtronicBolusConformanceTests {
    
    // MARK: - Bolus Command Formatting Tests
    
    /// Test 1.1U bolus at scale=40 matches Loop test vector
    @Test("Bolus command 1.1U scale=40 matches Loop")
    func bolusCommand_1_1U_Scale40_MatchesLoop() throws {
        let cmd = MedtronicBolusCommand(units: 1.1, scale: 40)
        
        // From fixture_bolus_tx.json: strokes=44 (0x2C), scrollRate=2
        #expect(cmd.strokes == 44)
        #expect(cmd.bodyLength == 2)
        
        // Body should be [02 00 2C]
        let expectedBody = Data([0x02, 0x00, 0x2C])
        #expect(cmd.txData == expectedBody)
    }
    
    /// Test 1.1U bolus at scale=10 matches Loop test vector (522 pump)
    @Test("Bolus command 1.1U scale=10 matches Loop")
    func bolusCommand_1_1U_Scale10_MatchesLoop() throws {
        let cmd = MedtronicBolusCommand(units: 1.1, scale: 10)
        
        // From fixture_bolus_tx.json: strokes=11 (0x0B)
        #expect(cmd.strokes == 11)
        #expect(cmd.bodyLength == 1)
        
        // Body should be [01 0B]
        let expectedBody = Data([0x01, 0x0B])
        #expect(cmd.txData == expectedBody)
    }
    
    /// Test 1.475U with rounding at scale=40
    @Test("Bolus command rounding matches Loop")
    func bolusCommand_Rounding_MatchesLoop() throws {
        let cmd = MedtronicBolusCommand(units: 1.475, scale: 40)
        
        // From fixture_bolus_tx.json: strokes=58 (0x3A), scrollRate=2
        #expect(cmd.strokes == 58)
        #expect(cmd.txData == Data([0x02, 0x00, 0x3A]))
        
        // Delivered should be 1.45U (58/40)
        #expect(abs(cmd.deliveredUnits - 1.45) < 0.001)
    }
    
    /// Test 7.9U bolus (two-byte value)
    @Test("Bolus command 7.9U two-byte matches Loop")
    func bolusCommand_7_9U_TwoByte_MatchesLoop() throws {
        let cmd = MedtronicBolusCommand(units: 7.9, scale: 40)
        
        // From fixture_bolus_tx.json: strokes=316 (0x013C), scrollRate=2
        #expect(cmd.strokes == 316)
        #expect(cmd.txData == Data([0x02, 0x01, 0x3C]))
    }
    
    /// Test 10.25U bolus (greater than 10, scrollRate=4)
    @Test("Bolus command 10.25U matches Loop")
    func bolusCommand_10_25U_MatchesLoop() throws {
        let cmd = MedtronicBolusCommand(units: 10.25, scale: 40)
        
        // From fixture_bolus_tx.json: strokes=408 (0x0198), scrollRate=4
        #expect(cmd.strokes == 408)
        #expect(cmd.txData == Data([0x02, 0x01, 0x98]))
        
        // Delivered should be 10.2U (408/40)
        #expect(abs(cmd.deliveredUnits - 10.2) < 0.001)
    }
    
    /// Test small bolus (0.5U, scrollRate=1)
    @Test("Bolus command small bolus")
    func bolusCommand_SmallBolus() throws {
        let cmd = MedtronicBolusCommand(units: 0.5, scale: 40)
        
        // For units <= 1, scrollRate=1: 0.5 * 40 = 20 strokes
        #expect(cmd.strokes == 20)
        #expect(cmd.txData == Data([0x02, 0x00, 0x14]))
    }
    
    /// Test minimum bolus (0.025U)
    @Test("Bolus command minimum bolus")
    func bolusCommand_MinimumBolus() throws {
        let cmd = MedtronicBolusCommand(units: 0.025, scale: 40)
        
        // Minimum: 0.025 * 40 = 1 stroke
        #expect(cmd.strokes == 1)
        #expect(cmd.txData == Data([0x02, 0x00, 0x01]))
    }
    
    /// Test large bolus (25U)
    @Test("Bolus command max bolus")
    func bolusCommand_MaxBolus() throws {
        let cmd = MedtronicBolusCommand(units: 25.0, scale: 40)
        
        // For units > 10, scrollRate=4: 25 * 40/4 * 4 = 1000 strokes (0x03E8)
        #expect(cmd.strokes == 1000)
        #expect(cmd.txData == Data([0x02, 0x03, 0xE8]))
    }
    
    // MARK: - Bolus Command Parsing Tests
    
    /// Test parsing scale=40 bolus body
    @Test("Bolus command parse scale=40")
    func bolusCommandParse_Scale40() throws {
        let data = Data([0x02, 0x00, 0x2C]) // 44 strokes
        let cmd = try #require(MedtronicBolusCommand.parse(from: data))
        
        #expect(cmd.strokes == 44)
        #expect(cmd.scale == 40)
        #expect(abs(cmd.deliveredUnits - 1.1) < 0.001)
    }
    
    /// Test parsing scale=10 bolus body
    @Test("Bolus command parse scale=10")
    func bolusCommandParse_Scale10() throws {
        let data = Data([0x01, 0x0B]) // 11 strokes
        let cmd = try #require(MedtronicBolusCommand.parse(from: data))
        
        #expect(cmd.strokes == 11)
        #expect(cmd.scale == 10)
        #expect(abs(cmd.deliveredUnits - 1.1) < 0.001)
    }
    
    /// Test parsing requires minimum bytes
    @Test("Bolus command parse requires minimum bytes")
    func bolusCommandParse_RequiresMinimumBytes() throws {
        let tooShort = Data([0x02]) // Only 1 byte
        #expect(MedtronicBolusCommand.parse(from: tooShort) == nil)
    }
    
    // MARK: - PYTHON-COMPAT Tests
    
    /// PYTHON-COMPAT: Verify Swift bolus formatting matches MinimedKit BolusCarelinkMessageBody
    /// Reference: MinimedKit/Messages/BolusCarelinkMessageBody.swift
    @Test("Python compat bolus formatting")
    func pythonCompat_BolusFormatting() throws {
        // Test cases from fixture_bolus_tx.json
        let testCases: [(units: Double, scale: Int, expectedStrokes: Int)] = [
            (1.1, 40, 44),     // scrollRate=2: 1.1 * 40/2 * 2 = 44
            (1.1, 10, 11),     // scale=10: 1.1 * 10 = 11
            (1.475, 40, 58),   // scrollRate=2: 1.475 * 40/2 = 29.5 -> 29 * 2 = 58
            (7.9, 40, 316),    // scrollRate=2: 7.9 * 40/2 * 2 = 316
            (10.25, 40, 408),  // scrollRate=4: 10.25 * 40/4 = 102.5 -> 102 * 4 = 408
            (0.5, 40, 20),     // scrollRate=1: 0.5 * 40 = 20
            (25.0, 40, 1000),  // scrollRate=4: 25 * 40/4 * 4 = 1000
        ]
        
        for testCase in testCases {
            let cmd = MedtronicBolusCommand(units: testCase.units, scale: testCase.scale)
            #expect(cmd.strokes == testCase.expectedStrokes)
            
            // Verify Python-equivalent calculation
            if testCase.scale >= 40 {
                // Python: scroll_rate = 4 if units > 10 else (2 if units > 1 else 1)
                // Python: strokes = int(units * (40 / scroll_rate)) * scroll_rate
                let pythonScrollRate: Int
                if testCase.units > 10 { pythonScrollRate = 4 }
                else if testCase.units > 1 { pythonScrollRate = 2 }
                else { pythonScrollRate = 1 }
                let pythonStrokes = Int(testCase.units * Double(40 / pythonScrollRate)) * pythonScrollRate
                #expect(cmd.strokes == pythonStrokes)
            } else {
                // Python: strokes = int(units * 10)
                let pythonStrokes = Int(testCase.units * 10)
                #expect(cmd.strokes == pythonStrokes)
            }
        }
    }
}

// MARK: - Fixture Loading Tests for Bolus TX

@Suite("MedtronicBolusFixtureTests")
struct MedtronicBolusFixtureTests {
    
    @Test("Fixture bolus exists")
    func fixtureBolusExists() throws {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "fixture_bolus_tx", withExtension: "json", subdirectory: "Fixtures")
        #expect(url != nil)
    }
    
    @Test("Load and parse bolus TX fixture")
    func loadAndParseBolusTxFixture() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_bolus_tx", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_bolus_tx.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["test_name"] as? String == "bolus_command_formatting")
        
        // Verify vectors array exists
        if let vectors = json?["vectors"] as? [[String: Any]] {
            #expect(vectors.count >= 5)
            
            // Verify first vector has expected fields
            if let firstVector = vectors.first {
                #expect(firstVector["name"] != nil)
                #expect(firstVector["input_units"] != nil)
                #expect(firstVector["strokes_raw"] != nil)
                #expect(firstVector["body_hex"] != nil)
            }
        }
    }
    
    /// Test all fixture vectors produce correct TX data
    @Test("Bolus TX fixture vectors match")
    func bolusTxFixtureVectorsMatch() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_bolus_tx", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_bolus_tx.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let vectors = json?["vectors"] as? [[String: Any]] else {
            Issue.record("No vectors in fixture")
            return
        }
        
        for vector in vectors {
            guard let name = vector["name"] as? String,
                  let inputUnits = vector["input_units"] as? Double,
                  let scale = vector["insulin_bit_packing_scale"] as? Int,
                  let expectedStrokes = vector["strokes_raw"] as? Int else {
                continue
            }
            
            let cmd = MedtronicBolusCommand(units: inputUnits, scale: scale)
            #expect(cmd.strokes == expectedStrokes, "Vector '\(name)': strokes should match fixture")
        }
    }
}
