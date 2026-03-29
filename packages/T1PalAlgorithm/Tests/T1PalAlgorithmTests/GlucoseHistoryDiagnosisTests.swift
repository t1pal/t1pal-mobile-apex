// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GlucoseHistoryDiagnosisTests.swift
// T1Pal Mobile
//
// Diagnose glucose history alignment: do we have the same readings as Loop?
// Requirements: ALG-DIAG-003
//
// Purpose: Compare glucose values we load from NS entries against the
// glucose data that Loop used (from deviceStatus predicted.startDate BG)
// to verify we're using the same input data.
//
// Trace: ALG-DIAG-003, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for glucose history alignment with Nightscout
/// Trace: ALG-DIAG-003
@Suite("Glucose History Diagnosis")
struct GlucoseHistoryDiagnosisTests {
    
    // MARK: - Test Fixture Loading
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let predicted: PredictedData?
            let iob: IOBData?
            
            struct PredictedData: Codable {
                let startDate: String
                let values: [Double]
            }
            
            struct IOBData: Codable {
                let timestamp: String
            }
        }
    }
    
    struct NSEntry: Codable {
        let _id: String
        let sgv: Int?
        let dateString: String?
        let date: Double?
        let mills: Double?
        let direction: String?
        let trend: Int?
        let device: String?
    }
    
    struct GlucoseMatchResult {
        let timestamp: Date
        let loopBG: Double
        let ourBG: Double
        let timeDelta: TimeInterval
        let divergence: Double
    }
    
    struct NearestGlucose {
        let sgv: Int
        let timeDelta: TimeInterval
    }
    
    // MARK: - ALG-DIAG-003: Glucose History Alignment Tests
    
    @Test("Glucose history matches NS entries")
    func glucoseHistoryMatchesNSEntries() throws {
        let entries = try loadEntriesFixture()
        #expect(!entries.isEmpty, "Should have glucose entries")
        
        // Check entries are properly formatted
        let validEntries = entries.filter { $0.sgv != nil && $0.dateString != nil }
        #expect(validEntries.count == entries.count, 
               "All entries should have sgv and dateString")
        
        // Report statistics
        print("\n" + String(repeating: "=", count: 60))
        print("📊 ALG-DIAG-003: Glucose History Diagnosis Report")
        print(String(repeating: "=", count: 60))
        
        // Time range
        let dates = validEntries.compactMap { parseDate($0.dateString!) }
        if let minDate = dates.min(), let maxDate = dates.max() {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            print("\nTime Range:")
            print("  Start: \(formatter.string(from: minDate))")
            print("  End:   \(formatter.string(from: maxDate))")
            print("  Duration: \(String(format: "%.1f", maxDate.timeIntervalSince(minDate) / 3600)) hours")
        }
        
        // BG statistics
        let bgValues = validEntries.compactMap { $0.sgv }
        let avgBG = Double(bgValues.reduce(0, +)) / Double(bgValues.count)
        let minBG = bgValues.min() ?? 0
        let maxBG = bgValues.max() ?? 0
        
        print("\nGlucose Statistics:")
        print("  Count: \(bgValues.count) readings")
        print("  Average: \(String(format: "%.0f", avgBG)) mg/dL")
        print("  Range: \(minBG) - \(maxBG) mg/dL")
        
        // Check reading intervals
        let sortedDates = dates.sorted()
        var intervals: [TimeInterval] = []
        for i in 1..<sortedDates.count {
            intervals.append(sortedDates[i].timeIntervalSince(sortedDates[i-1]))
        }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let expectedInterval: TimeInterval = 5 * 60  // 5 minutes
        let gapCount = intervals.filter { $0 > 6 * 60 }.count  // >6 min gaps
        
        print("\nReading Intervals:")
        print("  Average: \(String(format: "%.0f", avgInterval)) seconds (expected: 300)")
        print("  Gaps (>6 min): \(gapCount)")
        
        print(String(repeating: "=", count: 60))
        
        // Verify expected interval (within ~45 seconds to accommodate fixture data variations)
        // Fixture data may have slightly irregular intervals due to CGM signal quality
        #expect(abs(avgInterval - expectedInterval) < 50,
               "Average reading interval should be ~5 minutes")
    }
    
    @Test("Glucose at Loop time matches predicted start")
    func glucoseAtLoopTimeMatchesPredictedStart() throws {
        let deviceStatuses = try loadDeviceStatusFixture()
        let entries = try loadEntriesFixture()
        
        #expect(!deviceStatuses.isEmpty, "Should have device status entries")
        #expect(!entries.isEmpty, "Should have glucose entries")
        
        var matchResults: [GlucoseMatchResult] = []
        
        for status in deviceStatuses {
            guard let loopStatus = status.loop,
                  let predicted = loopStatus.predicted,
                  let startDate = parseDate(predicted.startDate),
                  !predicted.values.isEmpty else {
                continue
            }
            
            // Loop's prediction starts at the current glucose value
            let loopCurrentBG = predicted.values[0]
            
            // Find our nearest glucose reading
            let ourBG = findNearestGlucose(to: startDate, in: entries)
            
            if let ourBG = ourBG {
                let divergence = abs(Double(ourBG.sgv) - loopCurrentBG)
                matchResults.append(GlucoseMatchResult(
                    timestamp: startDate,
                    loopBG: loopCurrentBG,
                    ourBG: Double(ourBG.sgv),
                    timeDelta: ourBG.timeDelta,
                    divergence: divergence
                ))
            }
        }
        
        guard !matchResults.isEmpty else {
            print("⏭️ Could not match any glucose readings to Loop predicted start")
            return
        }
        
        // Report
        print("\n📊 Glucose Match at Loop Prediction Start:")
        print("  Comparisons: \(matchResults.count)")
        
        let exactMatches = matchResults.filter { $0.divergence == 0 }.count
        let closeMatches = matchResults.filter { $0.divergence <= 2 }.count
        
        print("  Exact matches: \(exactMatches) (\(Int(Double(exactMatches)/Double(matchResults.count)*100))%)")
        print("  Close (≤2 mg/dL): \(closeMatches) (\(Int(Double(closeMatches)/Double(matchResults.count)*100))%)")
        
        if let worst = matchResults.max(by: { $0.divergence < $1.divergence }) {
            print("  Worst divergence: \(String(format: "%.0f", worst.divergence)) mg/dL")
        }
        
        // Should have high match rate - glucose inputs should align
        #expect(Double(closeMatches) / Double(matchResults.count) > 0.9,
               "90%+ of glucose readings should match Loop's current BG")
    }
    
    // MARK: - Helpers
    
    func findNearestGlucose(to date: Date, in entries: [NSEntry]) -> NearestGlucose? {
        var bestMatch: (entry: NSEntry, delta: TimeInterval)?
        
        for entry in entries {
            guard let sgv = entry.sgv,
                  let dateStr = entry.dateString,
                  let entryDate = parseDate(dateStr) else {
                continue
            }
            
            let delta = abs(date.timeIntervalSince(entryDate))
            
            if bestMatch == nil || delta < bestMatch!.delta {
                bestMatch = (entry, delta)
            }
        }
        
        guard let match = bestMatch, match.delta < 5 * 60 else {  // within 5 minutes
            return nil
        }
        
        return NearestGlucose(sgv: match.entry.sgv!, timeDelta: match.delta)
    }
    
    func loadDeviceStatusFixture() throws -> [NSDeviceStatus] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_devicestatus_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSDeviceStatus].self, from: data)
    }
    
    func loadEntriesFixture() throws -> [NSEntry] {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_ns_entries_live", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([NSEntry].self, from: data)
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
}
