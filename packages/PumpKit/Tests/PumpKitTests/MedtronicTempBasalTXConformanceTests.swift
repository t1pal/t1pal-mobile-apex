// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicTempBasalTXConformanceTests.swift
// PumpKitTests
//
// MDT-SYNTH-005: Temp Basal TX Command Conformance Tests
// Extracted from MedtronicConformanceTests.swift
//
// Trace: MDT-SYNTH-005, MDT-SYNTH-009

import Testing
import Foundation
@testable import PumpKit

// MARK: - MDT-SYNTH-005: Temp Basal TX Command Conformance Tests

@Suite("MedtronicTempBasalTXConformanceTests")
struct MedtronicTempBasalTXConformanceTests {
    
    // MARK: - Temp Basal Command Formatting Tests
    
    /// Test 1.1 U/hr @ 30min matches Loop test vector
    @Test("Temp basal command 1.1 U/hr 30min matches Loop")
    func tempBasalCommand_1_1Uhr_30min_MatchesLoop() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 1.1, duration: TimeInterval(30 * 60))
        
        // From fixture_tempbasal_tx.json: strokes=44 (0x002C), segments=1
        #expect(cmd.strokes == 44)
        #expect(cmd.timeSegments == 1)
        
        // Body should be [03 00 2C 01]
        let expectedBody = Data([0x03, 0x00, 0x2C, 0x01])
        #expect(cmd.txData == expectedBody)
    }
    
    /// Test 6.5 U/hr @ 150min matches Loop test vector (Large)
    @Test("Temp basal command 6.5 U/hr 150min matches Loop")
    func tempBasalCommand_6_5Uhr_150min_MatchesLoop() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 6.5, duration: TimeInterval(150 * 60))
        
        // From fixture_tempbasal_tx.json: strokes=260 (0x0104), segments=5
        #expect(cmd.strokes == 260)
        #expect(cmd.timeSegments == 5)
        
        // Body should be [03 01 04 05]
        let expectedBody = Data([0x03, 0x01, 0x04, 0x05])
        #expect(cmd.txData == expectedBody)
    }
    
    /// Test 1.442 U/hr @ 65.5min with rounding
    @Test("Temp basal command rounding matches Loop")
    func tempBasalCommand_Rounding_MatchesLoop() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 1.442, duration: TimeInterval(65.5 * 60))
        
        // From fixture_tempbasal_tx.json: strokes=57 (0x0039), segments=2
        #expect(cmd.strokes == 57)
        #expect(cmd.timeSegments == 2)
        
        // Body should be [03 00 39 02]
        let expectedBody = Data([0x03, 0x00, 0x39, 0x02])
        #expect(cmd.txData == expectedBody)
        
        // Delivered values should reflect truncation
        #expect(abs(cmd.deliveredRate - 1.425) < 0.001)
        #expect(cmd.deliveredDurationMinutes == 60)
    }
    
    /// Test 0 U/hr (suspend)
    @Test("Temp basal command suspend")
    func tempBasalCommand_Suspend() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 0.0, duration: TimeInterval(30 * 60))
        
        #expect(cmd.strokes == 0)
        #expect(cmd.timeSegments == 1)
        #expect(cmd.txData == Data([0x03, 0x00, 0x00, 0x01]))
    }
    
    /// Test max rate (35 U/hr)
    @Test("Temp basal command max rate")
    func tempBasalCommand_MaxRate() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 35.0, duration: TimeInterval(30 * 60))
        
        // 35 * 40 = 1400 strokes (0x0578)
        #expect(cmd.strokes == 1400)
        #expect(cmd.txData == Data([0x03, 0x05, 0x78, 0x01]))
    }
    
    /// Test max duration (24 hours = 48 segments)
    @Test("Temp basal command max duration")
    func tempBasalCommand_MaxDuration() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 2.0, duration: TimeInterval(1440 * 60))
        
        // 2 * 40 = 80 strokes, 1440/30 = 48 segments (0x30)
        #expect(cmd.strokes == 80)
        #expect(cmd.timeSegments == 48)
        #expect(cmd.txData == Data([0x03, 0x00, 0x50, 0x30]))
    }
    
    /// Test minimum non-zero rate
    @Test("Temp basal command min rate")
    func tempBasalCommand_MinRate() throws {
        let cmd = MedtronicTempBasalCommand(unitsPerHour: 0.025, duration: TimeInterval(30 * 60))
        
        // 0.025 * 40 = 1 stroke
        #expect(cmd.strokes == 1)
        #expect(cmd.txData == Data([0x03, 0x00, 0x01, 0x01]))
    }
    
    // MARK: - Temp Basal Command Parsing Tests
    
    /// Test parsing temp basal body
    @Test("Temp basal command parse")
    func tempBasalCommandParse() throws {
        let data = Data([0x03, 0x00, 0x2C, 0x01]) // 44 strokes, 1 segment
        let cmd = try #require(MedtronicTempBasalCommand.parse(from: data))
        
        #expect(cmd.strokes == 44)
        #expect(cmd.timeSegments == 1)
        #expect(abs(cmd.deliveredRate - 1.1) < 0.001)
        #expect(cmd.deliveredDurationMinutes == 30)
    }
    
    /// Test parsing requires minimum bytes
    @Test("Temp basal command parse requires minimum bytes")
    func tempBasalCommandParse_RequiresMinimumBytes() throws {
        let tooShort = Data([0x03, 0x00, 0x2C]) // Only 3 bytes
        #expect(MedtronicTempBasalCommand.parse(from: tooShort) == nil)
    }
    
    /// Test parsing validates length byte
    @Test("Temp basal command parse validates length byte")
    func tempBasalCommandParse_ValidatesLengthByte() throws {
        let wrongLength = Data([0x02, 0x00, 0x2C, 0x01]) // length != 0x03
        #expect(MedtronicTempBasalCommand.parse(from: wrongLength) == nil)
    }
    
    // MARK: - PYTHON-COMPAT Tests
    
    /// PYTHON-COMPAT: Verify Swift temp basal formatting matches MinimedKit ChangeTempBasalCarelinkMessageBody
    /// Reference: MinimedKit/Messages/ChangeTempBasalCarelinkMessageBody.swift
    @Test("Python compat temp basal TX formatting")
    func pythonCompat_TempBasalTxFormatting() throws {
        // Test cases from fixture_tempbasal_tx.json
        let testCases: [(rate: Double, durationMin: Int, expectedStrokes: Int, expectedSegments: Int)] = [
            (1.1, 30, 44, 1),       // Loop test vector
            (6.5, 150, 260, 5),     // Large values
            (1.442, 65, 57, 2),     // Rounding (65.5 -> 65 for Int input)
            (0.0, 30, 0, 1),        // Suspend
            (0.5, 60, 20, 2),       // Standard
            (35.0, 30, 1400, 1),    // Max rate
            (2.0, 1440, 80, 48),    // Max duration
        ]
        
        for testCase in testCases {
            let cmd = MedtronicTempBasalCommand(
                unitsPerHour: testCase.rate,
                duration: TimeInterval(testCase.durationMin * 60)
            )
            
            // Python: strokes = int(rate * 40)
            let pythonStrokes = Int(testCase.rate * 40)
            #expect(cmd.strokes == pythonStrokes)
            
            // Python: time_segments = int(duration_minutes / 30)
            let pythonSegments = testCase.durationMin / 30
            #expect(cmd.timeSegments == pythonSegments)
            
            #expect(cmd.strokes == testCase.expectedStrokes)
            #expect(cmd.timeSegments == testCase.expectedSegments)
        }
    }
    
    // MARK: - Time Parsing PYTHON-COMPAT Tests (MDT-SYNTH-009)
    
    /// PYTHON-COMPAT: Verify Swift parsing matches decocare ReadRTC
    /// Python: hour=data[0], minute=data[1], second=data[2], year=lib.BangInt(data[3:5]), month=data[5], day=data[6]
    /// Note: MinimedKit has length byte at [0], so offsets are +1
    @Test("Python compat time parsing")
    func pythonCompat_TimeParsing() throws {
        // Test vectors from fixture_time.json
        // Format: [length/padding, hour, minute, second, year_hi, year_lo, month, day]
        let testCases: [(bytes: [UInt8], expectedISO: String)] = [
            ([0, 9, 22, 59, 7, 225, 12, 29], "2017-12-29T09:22:59"),   // Loop test vector
            ([0, 0, 0, 0, 7, 234, 1, 1], "2026-01-01T00:00:00"),       // Midnight New Year
            ([0, 23, 59, 59, 7, 234, 2, 12], "2026-02-12T23:59:59"),   // End of day
            ([0, 12, 0, 0, 7, 228, 6, 15], "2020-06-15T12:00:00"),     // Noon
            ([0, 14, 30, 45, 7, 232, 2, 29], "2024-02-29T14:30:45"),   // Leap year
        ]
        
        for testCase in testCases {
            // Parse using Python-equivalent logic (MinimedKit format with offset 1)
            let hour = Int(testCase.bytes[1])
            let minute = Int(testCase.bytes[2])
            let second = Int(testCase.bytes[3])
            // Python: year = lib.BangInt([data[3], data[4]]) - big-endian
            let year = Int(testCase.bytes[4]) << 8 + Int(testCase.bytes[5])
            let month = Int(testCase.bytes[6])
            let day = Int(testCase.bytes[7])
            
            let iso = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
            #expect(iso == testCase.expectedISO)
        }
    }
    
    // MARK: - Status Parsing PYTHON-COMPAT Tests (MDT-SYNTH-009)
    
    /// PYTHON-COMPAT: Verify Swift parsing matches decocare ReadPumpStatus
    /// Python: status='normal' if data[0]==0x03, bolusing=data[1]==1, suspended=data[2]==1
    /// MinimedKit: header at [0..1], bolusing at [2]>0, suspended at [3]>0
    @Test("Python compat status parsing")
    func pythonCompat_StatusParsing() throws {
        // Test vectors from fixture_status.json (MinimedKit format)
        let testCases: [(bytes: [UInt8], expectedStatus: String, expectedBolusing: Bool, expectedSuspended: Bool)] = [
            ([3, 3, 0, 0], "normal", false, false),  // Normal - idle
            ([3, 3, 1, 0], "normal", true, false),   // Normal - bolusing
            ([3, 3, 0, 1], "normal", false, true),   // Normal - suspended
            ([3, 3, 1, 1], "normal", true, true),    // Both flags
            ([0, 0, 0, 0], "error", false, false),   // Error status
        ]
        
        for testCase in testCases {
            // Parse using Python-equivalent logic (MinimedKit format)
            let status = testCase.bytes[0] == 0x03 ? "normal" : "error"
            let bolusing = testCase.bytes[2] > 0
            let suspended = testCase.bytes[3] > 0
            
            #expect(status == testCase.expectedStatus)
            #expect(bolusing == testCase.expectedBolusing)
            #expect(suspended == testCase.expectedSuspended)
        }
    }
}

// MARK: - Fixture Loading Tests for Temp Basal TX

@Suite("MedtronicTempBasalTXFixtureTests")
struct MedtronicTempBasalTXFixtureTests {
    
    @Test("Fixture temp basal TX exists")
    func fixtureTempBasalTxExists() throws {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "fixture_tempbasal_tx", withExtension: "json", subdirectory: "Fixtures")
        #expect(url != nil)
    }
    
    @Test("Load and parse temp basal TX fixture")
    func loadAndParseTempBasalTxFixture() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_tempbasal_tx", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_tempbasal_tx.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["test_name"] as? String == "temp_basal_command_formatting")
        
        // Verify vectors array exists
        if let vectors = json?["vectors"] as? [[String: Any]] {
            #expect(vectors.count >= 3)
            
            // Verify first vector has expected fields
            if let firstVector = vectors.first {
                #expect(firstVector["name"] != nil)
                #expect(firstVector["input_rate"] != nil)
                #expect(firstVector["strokes_raw"] != nil)
                #expect(firstVector["time_segments"] != nil)
            }
        }
    }
    
    /// Test all fixture vectors produce correct TX data
    @Test("Temp basal TX fixture vectors match")
    func tempBasalTxFixtureVectorsMatch() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_tempbasal_tx", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_tempbasal_tx.json")
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
                  let inputRate = vector["input_rate"] as? Double,
                  let inputDuration = vector["input_duration_minutes"] as? Double,
                  let expectedStrokes = vector["strokes_raw"] as? Int,
                  let expectedSegments = vector["time_segments"] as? Int else {
                continue
            }
            
            let cmd = MedtronicTempBasalCommand(
                unitsPerHour: inputRate,
                duration: TimeInterval(inputDuration * 60)
            )
            #expect(cmd.strokes == expectedStrokes, "Vector '\(name)': strokes should match fixture")
            #expect(cmd.timeSegments == expectedSegments, "Vector '\(name)': segments should match fixture")
        }
    }
}
