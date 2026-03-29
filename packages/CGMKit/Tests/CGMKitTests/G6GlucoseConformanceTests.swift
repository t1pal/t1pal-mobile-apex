// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6GlucoseConformanceTests.swift
// CGMKitTests
//
// Conformance tests for Dexcom G6 glucose message parsing.
// Uses fixture data from fixture_g6_glucose.json.

import Testing
import Foundation
@testable import CGMKit

// MARK: - Test Fixture Types

struct G6GlucoseFixture: Decodable {
    let test_vectors: [G6GlucoseVector]
    let glucose_categories: [String: String]
}

struct G6GlucoseVector: Decodable {
    let id: String
    let description: String
    let hex: String
    let expected: G6GlucoseExpected
    let glucose_category: String
}

struct G6GlucoseExpected: Decodable {
    let status: UInt8
    let sequence: UInt32
    let timestamp: UInt32
    let glucoseValue: UInt16
    let glucoseIsDisplayOnly: Bool
    let state: UInt8
    let glucose: Double
    let trend: Int8
    let isValid: Bool
}

// MARK: - Helper Extension

extension Data {
    init?(hexString: String) {
        let hex = hexString.lowercased()
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

@Suite("G6 Glucose Conformance Tests")
struct G6GlucoseConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G6GlucoseFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_g6_glucose", withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.notFound("fixture_g6_glucose.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(G6GlucoseFixture.self, from: data)
    }
    
    enum FixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Basic Parsing Tests
    
    @Test("Parse normal in-range glucose reading")
    func parseNormalReading() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "normal_120" }) else {
            Issue.record("Vector 'normal_120' not found")
            return
        }
        
        guard let data = Data(hexString: vector.hex) else {
            Issue.record("Invalid hex: \(vector.hex)")
            return
        }
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg != nil, "Failed to parse: \(vector.description)")
        #expect(msg?.glucoseValue == vector.expected.glucoseValue)
        #expect(msg?.glucose == vector.expected.glucose)
        #expect(msg?.isValid == vector.expected.isValid)
    }
    
    @Test("Parse all fixture vectors")
    func parseAllVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.test_vectors {
            guard let data = Data(hexString: vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = GlucoseRxMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id): \(vector.description)")
            
            if let msg = msg {
                #expect(msg.status == vector.expected.status, "\(vector.id): status mismatch")
                #expect(msg.sequence == vector.expected.sequence, "\(vector.id): sequence mismatch")
                #expect(msg.timestamp == vector.expected.timestamp, "\(vector.id): timestamp mismatch")
                #expect(msg.glucoseValue == vector.expected.glucoseValue, "\(vector.id): glucoseValue mismatch")
                #expect(msg.glucoseIsDisplayOnly == vector.expected.glucoseIsDisplayOnly, "\(vector.id): glucoseIsDisplayOnly mismatch")
                #expect(msg.state == vector.expected.state, "\(vector.id): state mismatch")
                #expect(msg.glucose == vector.expected.glucose, "\(vector.id): glucose mismatch")
                #expect(msg.trend == vector.expected.trend, "\(vector.id): trend mismatch")
                #expect(msg.isValid == vector.expected.isValid, "\(vector.id): isValid mismatch")
            }
        }
    }
    
    // MARK: - Glucose Range Tests
    
    @Test("Identify urgent low glucose readings")
    func urgentLowReadings() throws {
        let fixture = try Self.loadFixture()
        let urgentLowVectors = fixture.test_vectors.filter { $0.glucose_category == "urgent_low" }
        
        #expect(urgentLowVectors.count >= 2, "Expected at least 2 urgent_low vectors")
        
        for vector in urgentLowVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.glucoseValue < 55, "\(vector.id): urgent low should be < 55 mg/dL")
            #expect(msg.isValid == true, "\(vector.id): urgent low should still be valid")
        }
    }
    
    @Test("Identify low glucose readings")
    func lowReadings() throws {
        let fixture = try Self.loadFixture()
        let lowVectors = fixture.test_vectors.filter { $0.glucose_category == "low" }
        
        #expect(lowVectors.count >= 2, "Expected at least 2 low vectors")
        
        for vector in lowVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.glucoseValue >= 55 && msg.glucoseValue < 70, "\(vector.id): low should be 55-69 mg/dL")
            #expect(msg.isValid == true, "\(vector.id): low should still be valid")
        }
    }
    
    @Test("Identify in-range glucose readings")
    func inRangeReadings() throws {
        let fixture = try Self.loadFixture()
        let inRangeVectors = fixture.test_vectors.filter { $0.glucose_category == "in_range" }
        
        #expect(inRangeVectors.count >= 4, "Expected at least 4 in_range vectors")
        
        for vector in inRangeVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.glucoseValue >= 70 && msg.glucoseValue <= 180, "\(vector.id): in-range should be 70-180 mg/dL")
            #expect(msg.isValid == true, "\(vector.id): in-range should be valid")
        }
    }
    
    @Test("Identify high glucose readings")
    func highReadings() throws {
        let fixture = try Self.loadFixture()
        let highVectors = fixture.test_vectors.filter { $0.glucose_category == "high" }
        
        #expect(highVectors.count >= 2, "Expected at least 2 high vectors")
        
        for vector in highVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.glucoseValue > 180 && msg.glucoseValue <= 250, "\(vector.id): high should be 181-250 mg/dL")
            #expect(msg.isValid == true, "\(vector.id): high should still be valid")
        }
    }
    
    @Test("Identify urgent high glucose readings")
    func urgentHighReadings() throws {
        let fixture = try Self.loadFixture()
        let urgentHighVectors = fixture.test_vectors.filter { $0.glucose_category == "urgent_high" }
        
        #expect(urgentHighVectors.count >= 2, "Expected at least 2 urgent_high vectors")
        
        for vector in urgentHighVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.glucoseValue > 250, "\(vector.id): urgent high should be > 250 mg/dL")
            // 400 mg/dL is still valid (< 500)
            if msg.glucoseValue < 500 {
                #expect(msg.isValid == true, "\(vector.id): urgent high < 500 should be valid")
            }
        }
    }
    
    @Test("Identify invalid glucose readings")
    func invalidReadings() throws {
        let fixture = try Self.loadFixture()
        let invalidVectors = fixture.test_vectors.filter { $0.glucose_category == "invalid" }
        
        #expect(invalidVectors.count >= 2, "Expected at least 2 invalid vectors")
        
        for vector in invalidVectors {
            guard let data = Data(hexString: vector.hex),
                  let msg = GlucoseRxMessage(data: data) else {
                Issue.record("Failed to parse \(vector.id)")
                continue
            }
            
            #expect(msg.isValid == false, "\(vector.id): should be invalid")
            #expect(msg.glucoseValue == 0 || msg.glucoseValue >= 500, "\(vector.id): invalid should be 0 or >= 500")
        }
    }
    
    // MARK: - Trend Tests
    
    @Test("Parse positive trend (rising)")
    func positiveTrend() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "rising_fast" }) else {
            Issue.record("Vector 'rising_fast' not found")
            return
        }
        
        guard let data = Data(hexString: vector.hex),
              let msg = GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse rising_fast")
            return
        }
        
        #expect(msg.trend > 0, "Rising trend should be positive")
        #expect(msg.trend == vector.expected.trend)
    }
    
    @Test("Parse negative trend (falling)")
    func negativeTrend() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.test_vectors.first(where: { $0.id == "falling_fast" }) else {
            Issue.record("Vector 'falling_fast' not found")
            return
        }
        
        guard let data = Data(hexString: vector.hex),
              let msg = GlucoseRxMessage(data: data) else {
            Issue.record("Failed to parse falling_fast")
            return
        }
        
        #expect(msg.trend < 0, "Falling trend should be negative")
        #expect(msg.trend == vector.expected.trend)
    }
    
    // MARK: - Edge Cases
    
    @Test("Reject message with wrong opcode")
    func wrongOpcode() {
        var data = Data([0x30])  // Wrong opcode (should be 0x31)
        data.append(Data(repeating: 0x00, count: 14))
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Reject short message")
    func shortMessage() {
        let data = Data([0x31, 0x00, 0x01, 0x02])  // Only 4 bytes, need >= 14
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg == nil, "Should reject short message")
    }
    
    @Test("Accept exactly 14 bytes (minimum valid)")
    func exactlyFourteenBytes() {
        var data = Data([0x31, 0x00])  // opcode, status
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])  // sequence
        data.append(contentsOf: [0x10, 0x27, 0x00, 0x00])  // timestamp
        data.append(contentsOf: [0x64, 0x00])  // glucose = 100 (no displayOnly)
        data.append(contentsOf: [0x06])  // state = 0x06 (reliable)
        data.append(contentsOf: [0x00])  // trend = 0
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg != nil, "Should accept exactly 14 bytes")
        #expect(msg?.glucoseValue == 100)
        #expect(msg?.state == 0x06)
        #expect(msg?.trend == 0)
    }
    
    @Test("Parse trend as signed Int8")
    func trendAsSigned() {
        var data = Data([0x31, 0x00])  // opcode, status
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])  // sequence
        data.append(contentsOf: [0x10, 0x27, 0x00, 0x00])  // timestamp
        data.append(contentsOf: [0x64, 0x00])  // glucose = 100
        data.append(contentsOf: [0x06])  // state
        data.append(0xF6)  // trend = -10 (signed)
        
        let msg = GlucoseRxMessage(data: data)
        #expect(msg != nil, "Should accept 14 bytes with trend")
        #expect(msg?.trend == -10, "Trend should be parsed as signed Int8")
    }
}
