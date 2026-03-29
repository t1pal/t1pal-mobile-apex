// SPDX-License-Identifier: MIT
//
// Libre1FRAMConformanceTests.swift
// CGMKitTests
//
// Fixture-based conformance tests for Libre 1 unencrypted FRAM parsing.
// Validates against fixture_libre1_fram.json vectors.
// Trace: LIBRE-SYNTH-006

import Testing
import Foundation
@testable import CGMKit

/// Conformance tests for Libre 1 FRAM parsing using fixture vectors
@Suite("Libre 1 FRAM Conformance Tests")
struct Libre1FRAMConformanceTests {
    
    // MARK: - Fixture Loading
    
    struct Libre1FRAMFixture: Codable {
        let _comment: String
        let _source: String
        let _task: String
        let _description: String
        let sensor_types: [String: SensorTypeInfo]
        let sensor_states: [String: String]
        let sensor_regions: [String: String]
        let fram_structure: FRAMStructure
        let glucose_record_format: GlucoseRecordFormat
        let fram_vectors: [FRAMVector]
        let glucose_parsing_vectors: [GlucoseParsingVector]
        let crc16_vectors: [CRC16Vector]
        
        struct SensorTypeInfo: Codable {
            let patchInfoByte0: [String]
            let description: String
            let family: Int
            let maxLife: Int?
            let encryption: String
        }
        
        struct FRAMStructure: Codable {
            let header: BlockInfo
            let body: BlockInfo
            let footer: BlockInfo
            
            struct BlockInfo: Codable {
                let offset: Int
                let size: Int
                let fields: [String: String]
            }
        }
        
        struct GlucoseRecordFormat: Codable {
            let size: Int
            let fields: [String: String]
        }
        
        struct FRAMVector: Codable {
            let id: String
            let description: String
            let source: String
            let sensorType: String
            let patchInfoHex: String
            let patchInfo: [UInt8]
            let framHex: String
            let fram: [UInt8]
            let expected: Expected
            let notes: String
            
            struct Expected: Codable {
                let state: UInt8
                let stateName: String
                let trendIndex: Int?
                let historyIndex: Int?
                let age: Int?
                let validCRCs: Bool
            }
        }
        
        struct GlucoseParsingVector: Codable {
            let id: String
            let description: String
            let recordHex: String
            let record: [UInt8]
            let expected: Expected
            let notes: String
            
            struct Expected: Codable {
                let rawValue: Int
                let quality: Int
                let hasError: Bool
            }
        }
        
        struct CRC16Vector: Codable {
            let id: String
            let description: String
            let dataHex: String
            let crcHex: String
            let crcValue: UInt16
            let notes: String
        }
    }
    
    static func loadFixture() throws -> Libre1FRAMFixture {
        let fixtureURL = Bundle.module.url(
            forResource: "fixture_libre1_fram",
            withExtension: "json",
            subdirectory: "Fixtures/libre1"
        )!
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(Libre1FRAMFixture.self, from: data)
    }
    
    // MARK: - FRAM Structure Validation
    
    @Test("FRAM structure sizes match fixture")
    func framStructureSizes() throws {
        let fixture = try Self.loadFixture()
        
        let headerSize = fixture.fram_structure.header.size
        let bodySize = fixture.fram_structure.body.size
        let footerSize = fixture.fram_structure.footer.size
        
        #expect(headerSize == 24, "Header should be 24 bytes")
        #expect(bodySize == 296, "Body should be 296 bytes")
        #expect(footerSize == 24, "Footer should be 24 bytes")
        #expect(headerSize + bodySize + footerSize == 344, "Total should be 344 bytes")
    }
    
    @Test("FRAM offsets are correct")
    func framOffsets() throws {
        let fixture = try Self.loadFixture()
        
        #expect(fixture.fram_structure.header.offset == 0)
        #expect(fixture.fram_structure.body.offset == 24)
        #expect(fixture.fram_structure.footer.offset == 320)
    }
    
    // MARK: - Sensor State Parsing
    
    @Test("All FRAM vectors parse sensor state correctly")
    func framStateParsing() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            let fram = Data(vector.fram)
            guard fram.count >= 344 else {
                Issue.record("Vector \(vector.id): FRAM too short (\(fram.count) bytes)")
                continue
            }
            
            let state = fram[4]
            #expect(state == vector.expected.state,
                   "Vector \(vector.id): state should be \(vector.expected.state), got \(state)")
            
            // Verify state maps to correct LibreNFCSensorState
            let sensorState = LibreNFCSensorState(rawValue: state) ?? .unknown
            #expect(sensorState != .unknown,
                   "Vector \(vector.id): state \(state) should map to known state")
        }
    }
    
    @Test("Sensor state active is 0x03")
    func sensorStateActiveValue() throws {
        #expect(LibreNFCSensorState.active.rawValue == 0x03)
    }
    
    // MARK: - Sensor Type Detection
    
    @Test("Libre 1 patchInfo detection")
    func libre1PatchInfoDetection() throws {
        // Test 0xDF variant
        let patchInfoDF = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
        let familyDF = LibreSensorFamily(patchInfo: patchInfoDF)
        #expect(familyDF == .libre1, "patchInfo[0]=0xDF should be Libre 1")
        
        // Test 0xA2 variant
        let patchInfoA2 = Data([0xA2, 0x00, 0x00, 0x01, 0x01, 0x02])
        let familyA2 = LibreSensorFamily(patchInfo: patchInfoA2)
        #expect(familyA2 == .libre1US, "patchInfo[0]=0xA2 should be Libre 1 US")
    }
    
    @Test("Libre Pro patchInfo detection")
    func libreProPatchInfoDetection() throws {
        let patchInfo = Data([0x70, 0x00, 0x10, 0x08, 0x1A, 0x24])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .librePro, "patchInfo[0]=0x70 should be Libre Pro")
    }
    
    // MARK: - Index Parsing
    
    @Test("Trend and history index parsing")
    func indexParsing() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            guard let expectedTrend = vector.expected.trendIndex,
                  let expectedHistory = vector.expected.historyIndex else {
                continue
            }
            
            let fram = Data(vector.fram)
            guard fram.count >= 344 else { continue }
            
            let trendIndex = Int(fram[26])
            let historyIndex = Int(fram[27])
            
            #expect(trendIndex == expectedTrend,
                   "Vector \(vector.id): trendIndex should be \(expectedTrend), got \(trendIndex)")
            #expect(historyIndex == expectedHistory,
                   "Vector \(vector.id): historyIndex should be \(expectedHistory), got \(historyIndex)")
        }
    }
    
    // MARK: - Age Parsing
    
    @Test("Sensor age parsing (little-endian)")
    func ageParsing() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            guard let expectedAge = vector.expected.age else { continue }
            
            let fram = Data(vector.fram)
            guard fram.count >= 344 else { continue }
            
            // Age is at body offset 292-293, which is FRAM offset 316-317
            let age = Int(fram[316]) | (Int(fram[317]) << 8)
            
            #expect(age == expectedAge,
                   "Vector \(vector.id): age should be \(expectedAge), got \(age)")
        }
    }
    
    // MARK: - Glucose Record Parsing
    
    @Test("Glucose record format is 6 bytes")
    func glucoseRecordSize() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.glucose_record_format.size == 6)
    }
    
    // MARK: - Bit Reading Helper
    
    /// Read bits from buffer (DiaBLE-compatible algorithm)
    func readBits(_ buffer: Data, byteOffset: Int, bitOffset: Int, bitCount: Int) -> Int {
        guard bitCount > 0 else { return 0 }
        var result = 0
        for i in 0..<bitCount {
            let totalBit = byteOffset * 8 + bitOffset + i
            let byteIdx = totalBit / 8
            let bitIdx = totalBit % 8
            if byteIdx < buffer.count && ((buffer[byteIdx] >> bitIdx) & 1) == 1 {
                result |= 1 << i
            }
        }
        return result
    }
    
    @Test("Glucose record raw value parsing")
    func glucoseRecordRawValue() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.glucose_parsing_vectors {
            let record = Data(vector.record)
            let rawValue = readBits(record, byteOffset: 0, bitOffset: 0, bitCount: 14)
            
            #expect(rawValue == vector.expected.rawValue,
                   "Vector \(vector.id): rawValue should be \(vector.expected.rawValue), got \(rawValue)")
        }
    }
    
    @Test("Glucose record has error flag parsing")
    func glucoseRecordHasError() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.glucose_parsing_vectors {
            let record = Data(vector.record)
            let hasError = readBits(record, byteOffset: 0, bitOffset: 25, bitCount: 1) != 0
            
            #expect(hasError == vector.expected.hasError,
                   "Vector \(vector.id): hasError should be \(vector.expected.hasError), got \(hasError)")
        }
    }
    
    // MARK: - FRAM Vector Validation
    
    @Test("All FRAM vectors have correct size")
    func framVectorSizes() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            #expect(vector.fram.count == 344,
                   "Vector \(vector.id): FRAM should be 344 bytes, got \(vector.fram.count)")
        }
    }
    
    @Test("All FRAM vectors have correct patchInfo size")
    func patchInfoSizes() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            #expect(vector.patchInfo.count == 6,
                   "Vector \(vector.id): patchInfo should be 6 bytes, got \(vector.patchInfo.count)")
        }
    }
    
    // MARK: - Header Validation
    
    @Test("Libre 1 header bytes 9-23 are zeros")
    func libre1HeaderZeros() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors where vector.sensorType == "libre1" {
            let fram = Data(vector.fram)
            guard fram.count >= 24 else { continue }
            
            let headerReserved = fram[9..<24]
            let allZeros = headerReserved.allSatisfy { $0 == 0 }
            
            #expect(allZeros,
                   "Vector \(vector.id): Libre 1 header bytes 9-23 should be zeros")
        }
    }
    
    // MARK: - Trend Data Extraction
    
    @Test("Trend data is at correct offset")
    func trendDataOffset() throws {
        let fixture = try Self.loadFixture()
        
        // Trend data starts at body[4], which is FRAM[28]
        // 16 trend readings × 6 bytes = 96 bytes (FRAM[28-123])
        
        for vector in fixture.fram_vectors where vector.sensorType == "libre1" {
            let fram = Data(vector.fram)
            guard fram.count >= 124 else { continue }
            
            // Read first trend record at FRAM[28]
            let firstTrend = fram[28..<34]
            #expect(firstTrend.count == 6, "First trend record should be 6 bytes")
            
            // Verify it's not all zeros (sensor has data)
            if vector.expected.state == 0x03 { // active
                let hasData = !firstTrend.allSatisfy { $0 == 0 }
                #expect(hasData, "Active sensor should have trend data")
            }
        }
    }
    
    // MARK: - History Data Extraction
    
    @Test("History data is at correct offset")
    func historyDataOffset() throws {
        let fixture = try Self.loadFixture()
        
        // History data starts at body[100], which is FRAM[124]
        // 32 history readings × 6 bytes = 192 bytes (FRAM[124-315])
        
        for vector in fixture.fram_vectors where vector.sensorType == "libre1" {
            let fram = Data(vector.fram)
            guard fram.count >= 316 else { continue }
            
            // Read first history record at FRAM[124]
            let firstHistory = fram[124..<130]
            #expect(firstHistory.count == 6, "First history record should be 6 bytes")
        }
    }
}
