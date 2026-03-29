// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7VersionConformanceTests.swift
// CGMKitTests
//
// Conformance tests for Dexcom G7 ExtendedVersionMessage parsing.
// Uses fixture data from fixture_g7_version.json.
// Source: G7SensorKit (Loop/Trio) ExtendedVersionMessageTests.swift
// Task: G7-SYNTH-003

import Testing
import Foundation
@testable import CGMKit

// MARK: - Test Fixture Types

struct G7VersionFixture: Decodable {
    let version_vectors: [G7VersionVector]
}

struct G7VersionVector: Decodable {
    let id: String
    let description: String?
    let source: String?
    let hex: String
    let expected: G7VersionExpected
    let notes: String?
}

struct G7VersionExpected: Decodable {
    let sessionLengthSeconds: UInt32
    let sessionLengthDays: Double
    let warmupDurationSeconds: UInt16
    let warmupDurationMinutes: Double
    let algorithmVersion: UInt32
    let hardwareVersion: UInt8
    let maxLifetimeDays: UInt16
}

// MARK: - Conformance Tests

@Suite("G7 ExtendedVersion Conformance Tests")
struct G7VersionConformanceTests {
    
    // MARK: - Fixture Loading
    
    static func loadFixture() throws -> G7VersionFixture {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_g7_version", withExtension: "json", subdirectory: "Fixtures") else {
            throw VersionFixtureError.notFound("fixture_g7_version.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(G7VersionFixture.self, from: data)
    }
    
    enum VersionFixtureError: Error {
        case notFound(String)
        case invalidHex(String)
    }
    
    // MARK: - Helper
    
    private static func dataFromHex(_ hex: String) -> Data? {
        let cleanHex = hex.lowercased()
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            guard nextIndex != index else { break }
            let byteString = String(cleanHex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
    
    // MARK: - Standard 10-Day Sensor Tests
    
    @Test("Parse 10-day G7 sensor version")
    func parse10DaySensor() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.version_vectors.first(where: { $0.id == "10_day_sensor" }) else {
            Issue.record("Vector '10_day_sensor' not found")
            return
        }
        
        guard let data = Self.dataFromHex(vector.hex) else {
            Issue.record("Invalid hex: \(vector.hex)")
            return
        }
        
        let msg = G7ExtendedVersionMessage(data: data)
        #expect(msg != nil, "Failed to parse: \(vector.description ?? vector.id)")
        
        guard let msg = msg else { return }
        
        // Session length: 10.5 days = 907200 seconds
        #expect(msg.sessionLengthSeconds == 907200)
        #expect(abs(msg.sessionLengthDays - 10.5) < 0.001)
        
        // Warmup: 27 minutes = 1620 seconds
        #expect(msg.warmupDurationSeconds == 1620)
        #expect(abs(msg.warmupDurationMinutes - 27.0) < 0.001)
        
        // Algorithm and hardware versions
        #expect(msg.algorithmVersion == 67371520)
        #expect(msg.hardwareVersion == 255)
        
        // Max lifetime: 12 days
        #expect(msg.maxLifetimeDays == 12)
    }
    
    // MARK: - Extended 15-Day Sensor Tests
    
    @Test("Parse 15-day G7+ sensor version (Stelo)")
    func parse15DaySensor() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.version_vectors.first(where: { $0.id == "15_day_sensor" }) else {
            Issue.record("Vector '15_day_sensor' not found")
            return
        }
        
        guard let data = Self.dataFromHex(vector.hex) else {
            Issue.record("Invalid hex: \(vector.hex)")
            return
        }
        
        let msg = G7ExtendedVersionMessage(data: data)
        #expect(msg != nil, "Failed to parse: \(vector.description ?? vector.id)")
        
        guard let msg = msg else { return }
        
        // Session length: 15.5 days = 1339200 seconds
        #expect(msg.sessionLengthSeconds == 1339200)
        #expect(abs(msg.sessionLengthDays - 15.5) < 0.001)
        
        // Warmup: 62 minutes = 3720 seconds
        #expect(msg.warmupDurationSeconds == 3720)
        #expect(abs(msg.warmupDurationMinutes - 62.0) < 0.001)
        
        // Algorithm and hardware versions
        #expect(msg.algorithmVersion == 67764480)
        #expect(msg.hardwareVersion == 255)
        
        // Max lifetime: 17 days
        #expect(msg.maxLifetimeDays == 17)
    }
    
    // MARK: - All Vectors Test
    
    @Test("Parse all version vectors")
    func parseAllVersionVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.version_vectors {
            guard let data = Self.dataFromHex(vector.hex) else {
                Issue.record("Invalid hex for \(vector.id): \(vector.hex)")
                continue
            }
            
            let msg = G7ExtendedVersionMessage(data: data)
            #expect(msg != nil, "Failed to parse \(vector.id)")
            
            if let msg = msg {
                #expect(msg.sessionLengthSeconds == vector.expected.sessionLengthSeconds, 
                       "\(vector.id): sessionLengthSeconds mismatch")
                #expect(msg.warmupDurationSeconds == vector.expected.warmupDurationSeconds, 
                       "\(vector.id): warmupDurationSeconds mismatch")
                #expect(msg.algorithmVersion == vector.expected.algorithmVersion, 
                       "\(vector.id): algorithmVersion mismatch")
                #expect(msg.hardwareVersion == vector.expected.hardwareVersion, 
                       "\(vector.id): hardwareVersion mismatch")
                #expect(msg.maxLifetimeDays == vector.expected.maxLifetimeDays, 
                       "\(vector.id): maxLifetimeDays mismatch")
            }
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Reject short message")
    func rejectShortMessage() {
        let data = Data([0x52, 0x00, 0x01, 0x02])  // Only 4 bytes, need >= 15
        let msg = G7ExtendedVersionMessage(data: data)
        #expect(msg == nil, "Should reject short message")
    }
    
    @Test("Reject wrong opcode")
    func rejectWrongOpcode() {
        var data = Data([0x4E])  // Wrong opcode (should be 0x52)
        data.append(Data(repeating: 0x00, count: 14))
        
        let msg = G7ExtendedVersionMessage(data: data)
        #expect(msg == nil, "Should reject wrong opcode")
    }
    
    @Test("Accept exact minimum length")
    func acceptMinimumLength() {
        // 10-day sensor vector is exactly 15 bytes
        let hex = "5200c0d70d00540600020404ff0c00"
        guard let data = Self.dataFromHex(hex) else {
            Issue.record("Invalid hex")
            return
        }
        
        #expect(data.count == 15, "Test data should be 15 bytes")
        
        let msg = G7ExtendedVersionMessage(data: data)
        #expect(msg != nil, "Should accept 15-byte message")
    }
    
    // MARK: - TimeInterval Conversion Tests
    
    @Test("SessionLength TimeInterval conversion")
    func sessionLengthTimeInterval() throws {
        let hex = "5200c0d70d00540600020404ff0c00"
        guard let data = Self.dataFromHex(hex),
              let msg = G7ExtendedVersionMessage(data: data) else {
            Issue.record("Failed to parse")
            return
        }
        
        // sessionLength should be TimeInterval (Double seconds)
        #expect(msg.sessionLength == 907200.0)
        
        // Loop-compatible: sessionLength.hours / 24 == 10.5
        let sessionLengthHours = msg.sessionLength / 3600.0
        #expect(abs(sessionLengthHours / 24.0 - 10.5) < 0.001)
    }
    
    @Test("WarmupDuration TimeInterval conversion")
    func warmupDurationTimeInterval() throws {
        let hex = "5200c0d70d00540600020404ff0c00"
        guard let data = Self.dataFromHex(hex),
              let msg = G7ExtendedVersionMessage(data: data) else {
            Issue.record("Failed to parse")
            return
        }
        
        // warmupDuration should be TimeInterval (Double seconds)
        #expect(msg.warmupDuration == 1620.0)
        
        // Loop-compatible: warmupDuration.minutes == 27
        let warmupMinutes = msg.warmupDuration / 60.0
        #expect(abs(warmupMinutes - 27.0) < 0.001)
    }
    
    // MARK: - Sensor Variant Detection Tests
    
    @Test("Detect standard vs extended sensor")
    func detectSensorVariant() throws {
        let fixture = try Self.loadFixture()
        
        // Parse 10-day sensor
        guard let vector10 = fixture.version_vectors.first(where: { $0.id == "10_day_sensor" }),
              let data10 = Self.dataFromHex(vector10.hex),
              let msg10 = G7ExtendedVersionMessage(data: data10) else {
            Issue.record("Failed to parse 10-day sensor")
            return
        }
        
        // Parse 15-day sensor
        guard let vector15 = fixture.version_vectors.first(where: { $0.id == "15_day_sensor" }),
              let data15 = Self.dataFromHex(vector15.hex),
              let msg15 = G7ExtendedVersionMessage(data: data15) else {
            Issue.record("Failed to parse 15-day sensor")
            return
        }
        
        // 10-day sensor has shorter session and warmup
        #expect(msg10.sessionLengthDays < msg15.sessionLengthDays)
        #expect(msg10.warmupDurationMinutes < msg15.warmupDurationMinutes)
        #expect(msg10.maxLifetimeDays < msg15.maxLifetimeDays)
        
        // Different algorithm versions
        #expect(msg10.algorithmVersion != msg15.algorithmVersion)
    }
}
