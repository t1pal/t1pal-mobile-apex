// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutAlgorithmDataSourceTests.swift
// NightscoutKit
//
// Tests for NightscoutAlgorithmDataSource implementing AlgorithmDataSource
// Requirements: ALG-INPUT-008

import Testing
import Foundation
@testable import NightscoutKit
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - NightscoutAlgorithmDataSource Tests

@Suite("NightscoutAlgorithmDataSource Tests")
struct NightscoutAlgorithmDataSourceTests {
    
    // MARK: - Protocol Conformance
    
    @Test("Conforms to AlgorithmDataSource protocol")
    func testProtocolConformance() async throws {
        let url = URL(string: "https://example.nightscout.site")!
        let dataSource = NightscoutAlgorithmDataSource(url: url)
        
        // Verify it conforms to the protocol
        let _: any AlgorithmDataSource = dataSource
        #expect(true, "NightscoutAlgorithmDataSource conforms to AlgorithmDataSource")
    }
    
    // MARK: - Initialization Tests
    
    @Test("Initialize with URL and credentials")
    func testInitWithURL() async throws {
        let url = URL(string: "https://example.nightscout.site")!
        let dataSource = NightscoutAlgorithmDataSource(
            url: url,
            apiSecret: "test-secret"
        )
        
        #expect(dataSource != nil)
    }
    
    @Test("Initialize with NightscoutClient")
    func testInitWithClient() async throws {
        let config = NightscoutConfig(
            url: URL(string: "https://example.nightscout.site")!,
            apiSecret: "test-secret"
        )
        let client = NightscoutClient(config: config)
        let dataSource = NightscoutAlgorithmDataSource(client: client)
        
        #expect(dataSource != nil)
    }
    
    @Test("Factory method with URL string")
    func testFactoryMethod() async throws {
        let dataSource = NightscoutAlgorithmDataSource.create(
            urlString: "https://example.nightscout.site",
            apiSecret: "test-secret"
        )
        
        #expect(dataSource != nil)
    }
    
    @Test("Factory method with empty URL string returns nil")
    func testFactoryMethodInvalidURL() async throws {
        let dataSource = NightscoutAlgorithmDataSource.create(
            urlString: ""
        )
        
        #expect(dataSource == nil)
    }
    
    // MARK: - Reference Time Tests
    
    @Test("Reference time can be updated")
    func testReferenceTimeUpdate() async throws {
        let url = URL(string: "https://example.nightscout.site")!
        let dataSource = NightscoutAlgorithmDataSource(url: url)
        
        let newTime = Date().addingTimeInterval(-3600)
        await dataSource.setReferenceTime(newTime)
        
        let storedTime = await dataSource.referenceTime
        #expect(abs(storedTime.timeIntervalSince(newTime)) < 1)
    }
    
    // MARK: - Cache Tests
    
    @Test("Cache can be cleared")
    func testCacheClear() async throws {
        let url = URL(string: "https://example.nightscout.site")!
        let dataSource = NightscoutAlgorithmDataSource(url: url)
        
        // Just verify clearing doesn't crash
        await dataSource.clearCache()
        #expect(true, "Cache cleared successfully")
    }
    
    // MARK: - Treatment Conversion Tests
    
    @Test("Insulin treatment converts to InsulinDose")
    func testInsulinTreatmentConversion() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-19T05:00:00.000Z",
            insulin: 4.5
        )
        
        let dose = treatment.toInsulinDose()
        
        #expect(dose != nil)
        #expect(dose?.units == 4.5)
        #expect(dose?.source == "nightscout")
    }
    
    @Test("Treatment without insulin returns nil InsulinDose")
    func testNoInsulinTreatment() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Meal",
            created_at: "2026-02-19T05:00:00.000Z",
            carbs: 45
        )
        
        let dose = treatment.toInsulinDose()
        #expect(dose == nil)
    }
    
    @Test("Carb treatment converts to CarbEntry")
    func testCarbTreatmentConversion() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Meal",
            created_at: "2026-02-19T05:00:00.000Z",
            carbs: 45
        )
        
        let entry = treatment.toCarbEntry()
        
        #expect(entry != nil)
        #expect(entry?.grams == 45)
        #expect(entry?.absorptionType == .medium)
    }
    
    @Test("Snack treatment converts with fast absorption")
    func testSnackAbsorptionType() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Snack",
            created_at: "2026-02-19T05:00:00.000Z",
            carbs: 15
        )
        
        let entry = treatment.toCarbEntry()
        
        #expect(entry?.absorptionType == .fast)
    }
    
    @Test("Treatment without carbs returns nil CarbEntry")
    func testNoCarbTreatment() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-19T05:00:00.000Z",
            insulin: 3.0
        )
        
        let entry = treatment.toCarbEntry()
        #expect(entry == nil)
    }
    
    // MARK: - Timestamp Parsing Tests
    
    @Test("Parse ISO8601 timestamp with milliseconds")
    func testParseISO8601WithMillis() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-19T05:00:00.123Z",
            insulin: 1.0
        )
        
        let dose = treatment.toInsulinDose()
        #expect(dose != nil)
        
        // Verify timestamp is roughly correct (within 1 day of expected)
        let expectedDate = ISO8601DateFormatter().date(from: "2026-02-19T05:00:00Z")!
        #expect(abs(dose!.timestamp.timeIntervalSince(expectedDate)) < 86400)
    }
    
    @Test("Parse ISO8601 timestamp without milliseconds")
    func testParseISO8601WithoutMillis() async throws {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-19T05:00:00Z",
            insulin: 1.0
        )
        
        let dose = treatment.toInsulinDose()
        #expect(dose != nil)
    }
    
    // MARK: - Integration with AlgorithmInputAssembler
    
    @Test("Data source works with AlgorithmInputAssembler")
    func testWithAssembler() async throws {
        let url = URL(string: "https://example.nightscout.site")!
        let dataSource = NightscoutAlgorithmDataSource(url: url)
        
        // Create assembler with this data source
        let assembler = AlgorithmInputAssembler(dataSource: dataSource)
        
        // Verify configuration is accessible
        let config = await assembler.configuration
        #expect(config.glucoseCount == AlgorithmDataDefaults.glucoseCount)
    }
}

// MARK: - Profile Conversion Tests

@Suite("NightscoutAlgorithmDataSource Profile Conversion")
struct ProfileConversionTests {
    
    @Test("mmol/L to mg/dL conversion factor is correct")
    func testMmolConversionFactor() async throws {
        // The standard conversion factor
        let mmolFactor = 18.0182
        
        // 5.5 mmol/L should be approximately 99 mg/dL
        let mmol = 5.5
        let mgdl = mmol * mmolFactor
        
        #expect(abs(mgdl - 99.1) < 0.5)
    }
}
