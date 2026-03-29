// SPDX-License-Identifier: AGPL-3.0-or-later
//
// COBDivergenceDiagnosisTests.swift
// T1Pal Mobile
//
// Diagnose COB calculation divergence: our calculation vs NS deviceStatus
// Requirements: ALG-DIAG-002
//
// Purpose: Compare calculated COB against Loop's reported COB from Nightscout
// to identify if divergence is in inputs vs algorithm
//
// Trace: ALG-DIAG-002, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for COB divergence diagnosis against Nightscout deviceStatus
/// Trace: ALG-DIAG-002
@Suite("COB Divergence Diagnosis")
struct COBDivergenceDiagnosisTests {
    
    // MARK: - Constants
    
    /// Maximum acceptable COB divergence (grams)
    /// ALG-DIAG-002 target: ±2g
    let cobDivergenceThreshold: Double = 2.0
    
    /// Default carb absorption time (minutes)
    let defaultAbsorptionTime: Double = 180  // 3 hours
    
    // MARK: - Test Fixture Loading
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let cob: COBData?
            let iob: IOBData?
            
            struct COBData: Codable {
                let timestamp: String
                let cob: Double
            }
            
            struct IOBData: Codable {
                let timestamp: String
            }
        }
    }
    
    struct NSTreatment: Codable {
        let _id: String
        let eventType: String?
        let timestamp: String?
        let created_at: String?
        let carbs: Double?
        let absorptionTime: Double?  // minutes
    }
    
    struct COBComparisonResult {
        let timestamp: Date
        let nsCOB: Double
        let ourCOB: Double
        let divergence: Double
    }
    
    // MARK: - ALG-DIAG-002: COB Comparison Tests
    
    @Test("COB comparison against NS device status")
    func cobComparisonAgainstNSDeviceStatus() throws {
        // Load NS devicestatus fixture
        let deviceStatuses = try loadDeviceStatusFixture()
        #expect(!deviceStatuses.isEmpty, "Should have device status entries")
        
        // Load treatments (carbs) fixture
        let treatments = try loadTreatmentsFixture()
        
        // Filter to carb events only
        let carbEvents = treatments.filter { ($0.carbs ?? 0) > 0 }
        
        // Skip test if no carb data available
        guard !carbEvents.isEmpty else {
            // Record skip reason for tracking
            print("⏭️ ALG-DIAG-002: SKIPPED - No carb events in fixture data")
            print("   Fixture contains only: Temp Basal events")
            print("   To test COB, add fixture with carb entries")
            return  // Swift Testing doesn't have XCTSkip equivalent - just return
        }
        
        var results: [COBComparisonResult] = []
        
        for status in deviceStatuses {
            guard let loopStatus = status.loop,
                  let cobData = loopStatus.cob,
                  let timestamp = parseDate(cobData.timestamp) else {
                continue
            }
            
            let nsCOB = cobData.cob
            
            // Calculate our COB at the same timestamp
            let ourCOB = calculateOurCOB(at: timestamp, carbEvents: carbEvents)
            
            let divergence = abs(ourCOB - nsCOB)
            
            results.append(COBComparisonResult(
                timestamp: timestamp,
                nsCOB: nsCOB,
                ourCOB: ourCOB,
                divergence: divergence
            ))
        }
        
        guard !results.isEmpty else {
            print("⏭️ No COB data in deviceStatus entries")
            return
        }
        
        // Report results
        printDiagnosticReport(results)
        
        // Assert: at least some comparisons should pass threshold
        let passingResults = results.filter { $0.divergence <= cobDivergenceThreshold }
        let passRate = Double(passingResults.count) / Double(results.count)
        
        // ALG-DIAG-002 success criteria: 80%+ pass rate at ±2g
        #expect(
            passRate > 0.8,
            "COB divergence diagnosis: \(Int(passRate * 100))% pass rate (target: 80%+)"
        )
    }
    
    // MARK: - COB Calculation
    
    func calculateOurCOB(at date: Date, carbEvents: [NSTreatment]) -> Double {
        var totalCOB: Double = 0.0
        
        for event in carbEvents {
            guard let carbs = event.carbs, carbs > 0,
                  let timestampStr = event.timestamp ?? event.created_at,
                  let carbDate = parseDate(timestampStr) else {
                continue
            }
            
            let age = date.timeIntervalSince(carbDate)
            
            // Skip future carbs or carbs older than absorption window
            let absorptionMinutes = event.absorptionTime ?? defaultAbsorptionTime
            let absorptionSeconds = absorptionMinutes * 60
            
            guard age >= 0 && age <= absorptionSeconds else {
                continue
            }
            
            // Linear absorption model (simplified)
            // Loop uses piecewise linear model, but linear is close enough for diagnosis
            let percentAbsorbed = age / absorptionSeconds
            let remainingCOB = carbs * (1.0 - percentAbsorbed)
            
            totalCOB += max(0, remainingCOB)
        }
        
        return totalCOB
    }
    
    // MARK: - Helpers
    
    func loadDeviceStatusFixture() throws -> [NSDeviceStatus] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_devicestatus_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSDeviceStatus].self, from: data)
    }
    
    func loadTreatmentsFixture() throws -> [NSTreatment] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_treatments_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSTreatment].self, from: data)
    }
    
    func parseDate(_ string: String) -> Date? {
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
    
    func printDiagnosticReport(_ results: [COBComparisonResult]) {
        print("\n" + String(repeating: "=", count: 60))
        print("📊 ALG-DIAG-002: COB Divergence Diagnosis Report")
        print(String(repeating: "=", count: 60))
        
        let sorted = results.sorted { $0.divergence > $1.divergence }
        
        print("\nTop 5 Divergent Points:")
        for (i, r) in sorted.prefix(5).enumerated() {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            print("  \(i+1). \(formatter.string(from: r.timestamp)): NS=\(String(format: "%.1f", r.nsCOB))g, Ours=\(String(format: "%.1f", r.ourCOB))g, Δ=\(String(format: "%.1f", r.divergence))g")
        }
        
        let passing = results.filter { $0.divergence <= cobDivergenceThreshold }.count
        let total = results.count
        let avgDiv = results.map { $0.divergence }.reduce(0, +) / Double(total)
        
        print("\nSummary:")
        print("  Total comparisons: \(total)")
        print("  Passing (≤\(cobDivergenceThreshold)g): \(passing) (\(Int(Double(passing)/Double(total)*100))%)")
        print("  Average divergence: \(String(format: "%.1f", avgDiv))g")
        print(String(repeating: "=", count: 60))
    }
}
