// SPDX-License-Identifier: MIT
//
// HealthKitWriterTests.swift
// CGMKitTests
//
// Tests for HealthKit glucose writing functionality.
// Trace: APP-CGM-003, REQ-HK-001

import Testing
import Foundation
@testable import CGMKit
@testable import T1PalCore

// MARK: - Configuration Tests

@Suite("HealthKit Write Config")
struct HealthKitWriteConfigTests {
    
    @Test("Default config has sensible values")
    func defaultConfigValues() {
        let config = HealthKitWriteConfig.default
        
        #expect(config.enableDuplicateDetection == true)
        #expect(config.duplicateWindowSeconds == 120)
        #expect(config.sourceIdentifier == "T1Pal")
        #expect(config.maxBatchSize == 100)
    }
    
    @Test("Custom config preserves values")
    func customConfigValues() {
        let config = HealthKitWriteConfig(
            enableDuplicateDetection: false,
            duplicateWindowSeconds: 60,
            sourceIdentifier: "TestApp",
            maxBatchSize: 50
        )
        
        #expect(config.enableDuplicateDetection == false)
        #expect(config.duplicateWindowSeconds == 60)
        #expect(config.sourceIdentifier == "TestApp")
        #expect(config.maxBatchSize == 50)
    }
    
    @Test("Config is Codable")
    func configIsCodable() throws {
        let original = HealthKitWriteConfig(
            enableDuplicateDetection: true,
            duplicateWindowSeconds: 90,
            sourceIdentifier: "CodableTest",
            maxBatchSize: 25
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthKitWriteConfig.self, from: data)
        
        #expect(decoded.enableDuplicateDetection == original.enableDuplicateDetection)
        #expect(decoded.duplicateWindowSeconds == original.duplicateWindowSeconds)
        #expect(decoded.sourceIdentifier == original.sourceIdentifier)
        #expect(decoded.maxBatchSize == original.maxBatchSize)
    }
}

// MARK: - Write Result Tests

@Suite("HealthKit Write Result")
struct HealthKitWriteResultTests {
    
    @Test("Success result is successful")
    func successResult() {
        let timestamp = Date()
        let result = HealthKitWriteResult.success(timestamp: timestamp, glucose: 120)
        
        #expect(result.wasSuccessful == true)
        #expect(result.description.contains("120"))
    }
    
    @Test("Duplicate result is not successful")
    func duplicateResult() {
        let timestamp = Date()
        let result = HealthKitWriteResult.skippedDuplicate(existingTimestamp: timestamp)
        
        #expect(result.wasSuccessful == false)
        #expect(result.description.contains("duplicate"))
    }
    
    @Test("Unauthorized result is not successful")
    func unauthorizedResult() {
        let result = HealthKitWriteResult.failedUnauthorized
        
        #expect(result.wasSuccessful == false)
        #expect(result.description.contains("not authorized"))
    }
    
    @Test("Unavailable result is not successful")
    func unavailableResult() {
        let result = HealthKitWriteResult.failedUnavailable
        
        #expect(result.wasSuccessful == false)
        #expect(result.description.contains("unavailable"))
    }
    
    @Test("Error result is not successful")
    func errorResult() {
        let result = HealthKitWriteResult.failedError("Test error")
        
        #expect(result.wasSuccessful == false)
        #expect(result.description.contains("Test error"))
    }
    
    @Test("Results are Equatable")
    func resultsAreEquatable() {
        let timestamp = Date()
        
        let success1 = HealthKitWriteResult.success(timestamp: timestamp, glucose: 120)
        let success2 = HealthKitWriteResult.success(timestamp: timestamp, glucose: 120)
        let different = HealthKitWriteResult.success(timestamp: timestamp, glucose: 100)
        
        #expect(success1 == success2)
        #expect(success1 != different)
    }
}

// MARK: - Batch Write Result Tests

@Suite("HealthKit Batch Write Result")
struct HealthKitBatchWriteResultTests {
    
    @Test("Empty batch has zero counts")
    func emptyBatch() {
        let result = HealthKitBatchWriteResult(results: [])
        
        #expect(result.written == 0)
        #expect(result.skipped == 0)
        #expect(result.failed == 0)
    }
    
    @Test("Batch counts success correctly")
    func batchCountsSuccess() {
        let timestamp = Date()
        let results: [HealthKitWriteResult] = [
            .success(timestamp: timestamp, glucose: 100),
            .success(timestamp: timestamp.addingTimeInterval(300), glucose: 110),
            .success(timestamp: timestamp.addingTimeInterval(600), glucose: 120)
        ]
        
        let batch = HealthKitBatchWriteResult(results: results)
        
        #expect(batch.written == 3)
        #expect(batch.skipped == 0)
        #expect(batch.failed == 0)
    }
    
    @Test("Batch counts mixed results correctly")
    func batchCountsMixed() {
        let timestamp = Date()
        let results: [HealthKitWriteResult] = [
            .success(timestamp: timestamp, glucose: 100),
            .skippedDuplicate(existingTimestamp: timestamp),
            .failedUnauthorized,
            .success(timestamp: timestamp.addingTimeInterval(300), glucose: 110),
            .failedError("Test error")
        ]
        
        let batch = HealthKitBatchWriteResult(results: results)
        
        #expect(batch.written == 2)
        #expect(batch.skipped == 1)
        #expect(batch.failed == 2)
    }
    
    @Test("Batch summary is descriptive")
    func batchSummary() {
        let timestamp = Date()
        let results: [HealthKitWriteResult] = [
            .success(timestamp: timestamp, glucose: 100),
            .skippedDuplicate(existingTimestamp: timestamp),
            .failedUnauthorized
        ]
        
        let batch = HealthKitBatchWriteResult(results: results)
        
        #expect(batch.summary.contains("Written: 1"))
        #expect(batch.summary.contains("Skipped: 1"))
        #expect(batch.summary.contains("Failed: 1"))
    }
}

// MARK: - Authorization Status Tests

@Suite("HealthKit Write Auth Status")
struct HealthKitWriteAuthStatusTests {
    
    @Test("All status cases exist")
    func allStatusCases() {
        let statuses: [HealthKitWriteAuthStatus] = [
            .notDetermined,
            .authorized,
            .denied,
            .unavailable
        ]
        
        #expect(statuses.count == 4)
    }
}

// MARK: - Writer Tests (Non-HealthKit)

@Suite("HealthKit Writer")
struct HealthKitWriterTests {
    
    @Test("Writer initializes with default config")
    func writerInitializesWithDefault() async {
        let writer = HealthKitWriter()
        
        // On Linux, HealthKit is unavailable
        #if !canImport(HealthKit)
        let status = await writer.checkAuthorizationStatus()
        #expect(status == .unavailable)
        #endif
    }
    
    @Test("Writer initializes with custom config")
    func writerInitializesWithCustom() async {
        let config = HealthKitWriteConfig(
            enableDuplicateDetection: false,
            duplicateWindowSeconds: 30,
            sourceIdentifier: "CustomTest",
            maxBatchSize: 10
        )
        
        let writer = HealthKitWriter(config: config)
        
        // On Linux, HealthKit is unavailable
        #if !canImport(HealthKit)
        let status = await writer.checkAuthorizationStatus()
        #expect(status == .unavailable)
        #endif
    }
    
    @Test("Write returns unavailable on Linux")
    func writeReturnsUnavailableOnLinux() async {
        #if !canImport(HealthKit)
        let writer = HealthKitWriter()
        let reading = GlucoseReading(
            glucose: 120,
            timestamp: Date(),
            trend: .flat,
            source: "Test"
        )
        
        let result = await writer.write(reading: reading)
        #expect(result == .failedUnavailable)
        #endif
    }
    
    @Test("Batch write returns empty on Linux")
    func batchWriteReturnsEmptyOnLinux() async {
        #if !canImport(HealthKit)
        let writer = HealthKitWriter()
        let readings = [
            GlucoseReading(glucose: 100, timestamp: Date(), trend: .flat, source: "Test"),
            GlucoseReading(glucose: 110, timestamp: Date().addingTimeInterval(300), trend: .singleUp, source: "Test")
        ]
        
        let result = await writer.writeBatch(readings: readings)
        
        // Each write should fail with unavailable
        #expect(result.written == 0)
        #expect(result.failed == 2)
        #endif
    }
    
    @Test("Empty batch write succeeds")
    func emptyBatchWriteSucceeds() async {
        let writer = HealthKitWriter()
        let result = await writer.writeBatch(readings: [])
        
        #expect(result.written == 0)
        #expect(result.skipped == 0)
        #expect(result.failed == 0)
        #expect(result.results.isEmpty)
    }
}

// MARK: - GlucoseReading Extension Tests

@Suite("GlucoseReading HealthKit Extension")
struct GlucoseReadingHealthKitExtensionTests {
    
    @Test("Reading can use writeToHealthKit convenience")
    func readingCanWriteToHealthKit() async {
        let writer = HealthKitWriter()
        let reading = GlucoseReading(
            glucose: 120,
            timestamp: Date(),
            trend: .flat,
            source: "Test"
        )
        
        // On Linux, this should return unavailable
        let result = await reading.writeToHealthKit(using: writer)
        
        #if !canImport(HealthKit)
        #expect(result == .failedUnavailable)
        #endif
    }
}

// MARK: - Protocol Tests

@Suite("HealthKitWritingCGM Protocol")
struct HealthKitWritingCGMProtocolTests {
    
    @Test("Protocol exists and is usable")
    func protocolExists() {
        // Just verify the protocol compiles
        struct MockCGM: HealthKitWritingCGM {
            var isHealthKitWritingEnabled: Bool { true }
            
            func writeToHealthKit() async -> HealthKitWriteResult {
                return .success(timestamp: Date(), glucose: 100)
            }
        }
        
        let mock = MockCGM()
        #expect(mock.isHealthKitWritingEnabled == true)
    }
}
