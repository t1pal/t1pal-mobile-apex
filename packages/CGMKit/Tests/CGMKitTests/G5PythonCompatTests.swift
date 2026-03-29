// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G5PythonCompatTests.swift
// CGMKitTests
//
// G6-SYNTH-007: PYTHON-COMPAT conformance tests for Dexcom G5 glucose parsing.
// Verifies Swift parsing matches Python g6_parsers.py parse_g5_glucose() output.
//
// These tests validate the G5GlucoseRxMessage parser against real G5 test vectors
// from CGMBLEKit GlucoseRxMessageTests.swift.

import Testing
import Foundation
@testable import CGMKit

// MARK: - G5 Glucose PYTHON-COMPAT Tests (G6-SYNTH-007)

@Suite("G5 Glucose PYTHON-COMPAT (G6-SYNTH-007)")
struct G5GlucosePythonCompatTests {
    
    /// PYTHON-COMPAT: Verify Swift parsing matches g6_parsers.py parse_g5_glucose()
    /// Python format:
    ///   status = data[1]
    ///   sequence = struct.unpack('<I', data[2:6])[0]
    ///   timestamp = struct.unpack('<I', data[6:10])[0]
    ///   glucose_bytes = struct.unpack('<H', data[10:12])[0]
    ///   display_only = (glucose_bytes & 0xF000) > 0
    ///   glucose = glucose_bytes & 0x0FFF
    ///   state = data[12]
    ///   trend = struct.unpack('b', bytes([data[13]]))[0]
    @Test("Parse G5 glucose vectors from CGMBLEKit")
    func parseG5GlucoseVectors() throws {
        // Test vectors from fixture_g5_glucose.json (sourced from CGMBLEKitTests)
        let testCases: [(
            id: String,
            hex: String,
            status: UInt8,
            sequence: UInt32,
            timestamp: UInt32,
            displayOnly: Bool,
            glucose: UInt16,
            state: UInt8,
            trend: Int8
        )] = [
            // g5_normal_204: CGMBLEKitTests testMessageData()
            (
                id: "g5_normal_204",
                hex: "3100680a00008a715700cc0006ffc42a",
                status: 0,
                sequence: 2664,
                timestamp: 5730698,
                displayOnly: false,
                glucose: 204,
                state: 6,
                trend: -1
            ),
            // g5_negative_trend: CGMBLEKitTests testNegativeTrend()
            (
                id: "g5_negative_trend",
                hex: "31006f0a0000be7957007a0006e4818d",
                status: 0,
                sequence: 2671,
                timestamp: 5732798,
                displayOnly: false,
                glucose: 122,
                state: 6,
                trend: -28
            ),
            // g5_display_only: CGMBLEKitTests testDisplayOnly()
            (
                id: "g5_display_only",
                hex: "3100700a0000f17a5700584006e3cee9",
                status: 0,
                sequence: 2672,
                timestamp: 5733105,
                displayOnly: true,
                glucose: 88,
                state: 6,
                trend: -29
            ),
            // g5_old_transmitter: CGMBLEKitTests testOldTransmitter()
            (
                id: "g5_old_transmitter",
                hex: "3100aa00000095a078008b00060a8b34",
                status: 0,
                sequence: 170,
                timestamp: 7905429,
                displayOnly: false,
                glucose: 139,
                state: 6,
                trend: 10
            ),
            // g5_zero_sequence: CGMBLEKitTests testZeroSequence()
            (
                id: "g5_zero_sequence",
                hex: "3100000000008eb14d00820006f6a038",
                status: 0,
                sequence: 0,
                timestamp: 5091726,
                displayOnly: false,
                glucose: 130,
                state: 6,
                trend: -10
            ),
        ]
        
        for testCase in testCases {
            let data = Data(hexString: testCase.hex)!
            let msg = G5GlucoseRxMessage(data: data)
            
            #expect(msg != nil, "\(testCase.id): Failed to parse hex")
            
            guard let msg = msg else { continue }
            
            #expect(msg.status == testCase.status,
                   "\(testCase.id): status mismatch - expected \(testCase.status), got \(msg.status)")
            #expect(msg.sequence == testCase.sequence,
                   "\(testCase.id): sequence mismatch - expected \(testCase.sequence), got \(msg.sequence)")
            #expect(msg.timestamp == testCase.timestamp,
                   "\(testCase.id): timestamp mismatch - expected \(testCase.timestamp), got \(msg.timestamp)")
            #expect(msg.glucoseIsDisplayOnly == testCase.displayOnly,
                   "\(testCase.id): displayOnly mismatch - expected \(testCase.displayOnly), got \(msg.glucoseIsDisplayOnly)")
            #expect(msg.glucose == testCase.glucose,
                   "\(testCase.id): glucose mismatch - expected \(testCase.glucose), got \(msg.glucose)")
            #expect(msg.state == testCase.state,
                   "\(testCase.id): state mismatch - expected \(testCase.state), got \(msg.state)")
            #expect(msg.trend == testCase.trend,
                   "\(testCase.id): trend mismatch - expected \(testCase.trend), got \(msg.trend)")
        }
    }
    
    /// PYTHON-COMPAT: Verify displayOnly flag extraction
    /// Python: display_only = (glucose_bytes & 0xF000) > 0
    @Test("DisplayOnly flag extraction matches Python")
    func displayOnlyExtraction() {
        // Test vector with displayOnly=true: 0x4058 & 0xF000 = 0x4000 > 0
        let data = Data(hexString: "3100700a0000f17a5700584006e3cee9")!
        let msg = G5GlucoseRxMessage(data: data)!
        
        #expect(msg.glucoseIsDisplayOnly == true,
               "0x4058 should have displayOnly=true (0x4058 & 0xF000 = 0x4000)")
        #expect(msg.glucose == 88,
               "0x4058 & 0x0FFF should = 88")
    }
    
    /// PYTHON-COMPAT: Verify signed trend byte parsing
    /// Python: trend = struct.unpack('b', bytes([data[13]]))[0]
    @Test("Signed trend parsing matches Python struct.unpack('b')")
    func signedTrendParsing() {
        // Negative trend: 0xE4 = -28 as signed Int8
        let data1 = Data(hexString: "31006f0a0000be7957007a0006e4818d")!
        let msg1 = G5GlucoseRxMessage(data: data1)!
        #expect(msg1.trend == -28, "0xE4 should parse as -28")
        
        // Positive trend: 0x0A = 10 as signed Int8
        let data2 = Data(hexString: "3100aa00000095a078008b00060a8b34")!
        let msg2 = G5GlucoseRxMessage(data: data2)!
        #expect(msg2.trend == 10, "0x0A should parse as 10")
        
        // Slight negative trend: 0xFF = -1 as signed Int8
        let data3 = Data(hexString: "3100680a00008a715700cc0006ffc42a")!
        let msg3 = G5GlucoseRxMessage(data: data3)!
        #expect(msg3.trend == -1, "0xFF should parse as -1")
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        // Change opcode from 0x31 to 0x30
        let data = Data(hexString: "3000680a00008a715700cc0006ffc42a")!
        let msg = G5GlucoseRxMessage(data: data)
        #expect(msg == nil, "Should reject opcode 0x30")
    }
    
    @Test("Reject short message")
    func rejectShortMessage() {
        // Only 12 bytes, needs at least 14
        let data = Data(hexString: "3100680a00008a715700cc00")!
        let msg = G5GlucoseRxMessage(data: data)
        #expect(msg == nil, "Should reject message shorter than 14 bytes")
    }
    
    @Test("State 6 indicates OK")
    func stateOK() {
        // All test vectors have state=6 which means "OK"
        let data = Data(hexString: "3100680a00008a715700cc0006ffc42a")!
        let msg = G5GlucoseRxMessage(data: data)!
        #expect(msg.state == 6, "State 6 = OK")
        #expect(msg.isValid == true, "State 6 with valid glucose should be valid")
    }
}
