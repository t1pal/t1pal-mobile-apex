// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7GlucoseConformanceTests.swift
// CGMKitTests
//
// Conformance tests for Dexcom G7 glucose message parsing.
// Uses fixture data from fixture_g7_glucose.json.
// Source: G7SensorKit (Loop/Trio) G7GlucoseMessageTests.swift
// Task: G7-SYNTH-001

import Testing
import Foundation
@testable import CGMKit

// MARK: - Test Fixture Types

struct G7GlucoseFixture: Decodable {
    let glucose_vectors: [G7GlucoseVector]
    let lifecycle_vectors: [G7LifecycleVector]
    let backfill_vectors: [G7BackfillVector]
}

struct G7GlucoseVector: Decodable {
    let id: String
    let description: String?
    let source: String?
    let hex: String
    let expected: G7GlucoseExpected
}

struct G7GlucoseExpected: Decodable {
    let glucose: Int?
    let glucoseTimestamp: UInt32?
    let glucoseIsDisplayOnly: Bool?
    let sequence: UInt16?
    let age: UInt16?
    let predicted: UInt16?
    let trend: Double?
    let algorithmState: String?
    let messageTimestamp: UInt32?
}

struct G7LifecycleVector: Decodable {
    let id: String
    let description: String?
    let hex: String
    let expected: G7GlucoseExpected
}

struct G7BackfillVector: Decodable {
    let id: String
    let description: String?
    let source: String?
    let hex: String
    let expected: G7BackfillExpected
}

struct G7BackfillExpected: Decodable {
    let timestamp: UInt32?
    let glucose: Int?
    let algorithmState: String?
    let condition: Int?
    let glucoseIsDisplayOnly: Bool?
    let hasReliableGlucose: Bool?
}

// MARK: - Helper Extension

extension Data {
    init?(g7HexString: String) {
        let hex = g7HexString.lowercased()
        var data = Data()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard nextIndex != index else { break }
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - Conformance Tests

@Suite("G7 Glucose Conformance Tests")
struct G7GlucoseConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G7GlucoseFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_g7_glucose", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_g7_glucose.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(G7GlucoseFixture.self, from: data)
    }
    
    enum FixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Basic Glucose Message Tests
    
    @Test("Parse basic glucose reading (138 mg/dL)")
    func parseBasicReading() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "basic_reading" }) else {
            Issue.record("Vector 'basic_reading' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex) else {
            Issue.record("Invalid hex: \(vector.hex)")
            return
        }
        
        let msg = G7GlucoseMessage(data: data)
        #expect(msg != nil, "Failed to parse: \(vector.description ?? vector.id)")
        #expect(msg?.glucose == 138)
        #expect(msg?.glucoseTimestamp == 87485)
        #expect(msg?.glucoseIsDisplayOnly == false)
    }
    
    @Test("Parse calibration/display-only reading")
    func parseCalibrationReading() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "calibration_display_only" }) else {
            Issue.record("Vector 'calibration_display_only' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse calibration vector")
            return
        }
        
        #expect(msg.glucose == 104)
        #expect(msg.glucoseTimestamp == 901390)
        #expect(msg.glucoseIsDisplayOnly == true)
    }
    
    @Test("Parse detailed reading with all fields")
    func parseDetailedReading() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "detailed_reading" }) else {
            Issue.record("Vector 'detailed_reading' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse detailed vector")
            return
        }
        
        #expect(msg.glucose == 141)
        #expect(msg.glucoseTimestamp == 40100)
        #expect(msg.sequence == 136)
        #expect(msg.age == 4)
        #expect(msg.predicted == 138)
        #expect(msg.trend == 0.3)
        #expect(msg.algorithmState == .known(.ok))
    }
    
    @Test("Parse negative trend rate")
    func parseNegativeTrend() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "negative_trend" }) else {
            Issue.record("Vector 'negative_trend' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse negative_trend vector")
            return
        }
        
        #expect(msg.trend == -0.2)
    }
    
    @Test("Parse missing trend (0x7F)")
    func parseMissingTrend() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "missing_trend" }) else {
            Issue.record("Vector 'missing_trend' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse missing_trend vector")
            return
        }
        
        #expect(msg.trend == nil)
    }
    
    @Test("Parse two-byte age field")
    func parseTwoByteAge() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.glucose_vectors.first(where: { $0.id == "two_byte_age" }) else {
            Issue.record("Vector 'two_byte_age' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse two_byte_age vector")
            return
        }
        
        #expect(msg.age == 298)
        #expect(msg.messageTimestamp == 154105)
        #expect(msg.glucoseTimestamp == 153807)
    }
    
    // MARK: - Lifecycle State Tests
    
    @Test("Parse all lifecycle vectors")
    func parseAllLifecycleVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.lifecycle_vectors {
            guard let data = Data(g7HexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7GlucoseMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id)")
            
            if let msg = msg {
                // Check sequence if expected
                if let expectedSeq = vector.expected.sequence {
                    #expect(msg.sequence == expectedSeq, "\(vector.id): sequence mismatch")
                }
                
                // Check glucose timestamp if expected
                if let expectedTimestamp = vector.expected.glucoseTimestamp {
                    #expect(msg.glucoseTimestamp == expectedTimestamp, "\(vector.id): glucoseTimestamp mismatch")
                }
                
                // Check glucose value if expected
                if let expectedGlucose = vector.expected.glucose {
                    #expect(msg.glucose == UInt16(expectedGlucose), "\(vector.id): glucose mismatch")
                } else if vector.expected.glucose == nil && vector.id.contains("stopped") || vector.id.contains("warmup") {
                    // For warmup states without glucose, glucose may be nil
                }
                
                // Check algorithm state if expected
                if let expectedState = vector.expected.algorithmState {
                    switch expectedState {
                    case "stopped":
                        #expect(msg.algorithmState == .known(.stopped), "\(vector.id): algorithmState should be stopped")
                    case "warmup":
                        #expect(msg.algorithmState == .known(.warmup), "\(vector.id): algorithmState should be warmup")
                    case "ok":
                        #expect(msg.algorithmState == .known(.ok), "\(vector.id): algorithmState should be ok")
                    case "expired":
                        #expect(msg.algorithmState == .known(.expired), "\(vector.id): algorithmState should be expired")
                    default:
                        break
                    }
                }
            }
        }
    }
    
    @Test("Stopped state has no glucose")
    func stoppedStateNoGlucose() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_vectors.first(where: { $0.id == "lifecycle_0_stopped" }) else {
            Issue.record("Vector 'lifecycle_0_stopped' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_0_stopped vector")
            return
        }
        
        #expect(msg.glucose == nil)
        #expect(msg.algorithmState == .known(.stopped))
    }
    
    @Test("Warmup state transitions to OK")
    func warmupTransitionsToOK() throws {
        let fixture = try Self.loadFixture()
        
        // Find warmup and ok vectors
        let warmupVectors = fixture.lifecycle_vectors.filter { 
            $0.expected.algorithmState == "warmup" 
        }
        let okVectors = fixture.lifecycle_vectors.filter { 
            $0.expected.algorithmState == "ok" 
        }
        
        #expect(warmupVectors.count >= 5, "Expected at least 5 warmup vectors")
        #expect(okVectors.count >= 2, "Expected at least 2 ok vectors")
        
        // Verify warmup comes before ok (by sequence)
        if let lastWarmup = warmupVectors.last,
           let firstOk = okVectors.first,
           let warmupSeq = lastWarmup.expected.sequence,
           let okSeq = firstOk.expected.sequence {
            #expect(warmupSeq < okSeq, "Warmup should transition to OK")
        }
    }
    
    @Test("Expired sensor state")
    func expiredSensorState() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.lifecycle_vectors.first(where: { $0.id == "lifecycle_8_expired" }) else {
            Issue.record("Vector 'lifecycle_8_expired' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7GlucoseMessage(data: data) else {
            Issue.record("Failed to parse lifecycle_8_expired vector")
            return
        }
        
        #expect(msg.algorithmState == .known(.expired))
        #expect(msg.sequence == 3028)
        #expect(msg.glucoseTimestamp == 907385)
    }
    
    // MARK: - Backfill Message Tests
    
    @Test("Parse basic backfill reading")
    func parseBackfillBasic() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.backfill_vectors.first(where: { $0.id == "backfill_basic" }) else {
            Issue.record("Vector 'backfill_basic' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex) else {
            Issue.record("Invalid hex: \(vector.hex)")
            return
        }
        
        let msg = G7BackfillMessage(data: data)
        #expect(msg != nil, "Failed to parse backfill")
        #expect(msg?.timestamp == 153807)
        #expect(msg?.glucose == 143)
        #expect(msg?.algorithmState == .known(.ok))
        #expect(msg?.glucoseIsDisplayOnly == false)
        #expect(msg?.hasReliableGlucose == true)
    }
    
    @Test("Parse backfill with high timestamp byte")
    func parseBackfillHighTimestamp() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.backfill_vectors.first(where: { $0.id == "backfill_high_timestamp" }) else {
            Issue.record("Vector 'backfill_high_timestamp' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7BackfillMessage(data: data) else {
            Issue.record("Failed to parse backfill_high_timestamp vector")
            return
        }
        
        #expect(msg.timestamp == 855794)
    }
    
    @Test("Parse backfill calibration/display-only")
    func parseBackfillCalibration() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.backfill_vectors.first(where: { $0.id == "backfill_calibration" }) else {
            Issue.record("Vector 'backfill_calibration' not found")
            return
        }
        
        guard let data = Data(g7HexString: vector.hex),
              let msg = G7BackfillMessage(data: data) else {
            Issue.record("Failed to parse backfill_calibration vector")
            return
        }
        
        #expect(msg.glucoseIsDisplayOnly == true)
    }
    
    @Test("Parse all backfill vectors")
    func parseAllBackfillVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.backfill_vectors {
            guard let data = Data(g7HexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7BackfillMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id)")
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Reject short message")
    func rejectShortMessage() {
        let data = Data([0x4E, 0x00, 0x01, 0x02])  // Only 4 bytes, need >= 19
        let msg = G7GlucoseMessage(data: data)
        #expect(msg == nil, "Should reject short message")
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        var data = Data([0x4F])  // Wrong opcode (should be 0x4E for G7GlucoseMessage)
        data.append(Data(repeating: 0x00, count: 18))
        
        let msg = G7GlucoseMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short backfill message")
    func rejectShortBackfill() {
        let data = Data([0xCF, 0x58, 0x02])  // Only 3 bytes, need >= 9
        let msg = G7BackfillMessage(data: data)
        #expect(msg == nil, "Should reject short backfill message")
    }
}
