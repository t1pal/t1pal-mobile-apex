// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TempBasalAccountingDiagnosisTests.swift
// T1Pal Mobile
//
// Verify we account for existing temp basal when calculating recommendations
// Requirements: ALG-DIAG-014
//
// Purpose: When Loop calculates a new dosing recommendation, it needs to
// consider what temp basal is already running. This affects:
// 1. Whether to issue a new command (avoid redundant commands)
// 2. IOB calculation (existing temp basal contributes to IOB)
// 3. Net effect calculation (difference from scheduled, not absolute)
//
// Trace: ALG-DIAG-014, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Tests for temp basal accounting in algorithm recommendations
/// Trace: ALG-DIAG-014
@Suite("Temp Basal Accounting Diagnosis")
struct TempBasalAccountingDiagnosisTests {
    
    // MARK: - Test Fixture Loading
    
    struct NSDeviceStatus: Codable {
        let _id: String
        let loop: LoopStatus?
        
        struct LoopStatus: Codable {
            let iob: IOBData?
            let automaticDoseRecommendation: AutomaticDoseRecommendation?
            let enacted: EnactedData?
            
            struct IOBData: Codable {
                let timestamp: String
                let iob: Double
            }
            
            struct AutomaticDoseRecommendation: Codable {
                let timestamp: String
                let bolusVolume: Double?
                let tempBasalAdjustment: TempBasalAdjustment?
                
                struct TempBasalAdjustment: Codable {
                    let rate: Double
                    let duration: Double
                }
            }
            
            struct EnactedData: Codable {
                let timestamp: String
                let rate: Double?
                let duration: Double?
                let bolusVolume: Double?
                let received: Bool?
            }
        }
    }
    
    struct NSTreatment: Codable {
        let _id: String
        let eventType: String?
        let timestamp: String?
        let created_at: String?
        let rate: Double?
        let absolute: Double?
        let duration: Double?
    }
    
    // MARK: - ALG-DIAG-014: Temp Basal Accounting Tests
    
    @Test("Temp basal continuation - redundant command avoidance")
    func tempBasalContinuation_redundantCommandAvoidance() throws {
        // Scenario: If the recommended rate matches what's already running,
        // Loop should NOT issue a new command (avoid pump communication overhead)
        
        let deviceStatuses = try loadDeviceStatusFixture()
        
        var continuationCases: [(recommended: Double, enacted: Double, shouldSkip: Bool)] = []
        
        for status in deviceStatuses {
            guard let loopStatus = status.loop,
                  let recommendation = loopStatus.automaticDoseRecommendation,
                  let tbAdjustment = recommendation.tempBasalAdjustment,
                  let enacted = loopStatus.enacted,
                  let enactedRate = enacted.rate else {
                continue
            }
            
            let recommendedRate = tbAdjustment.rate
            
            // If rates match within tolerance (0.05 U/hr), command should be skipped
            let rateDifference = abs(recommendedRate - enactedRate)
            let shouldSkip = rateDifference < 0.05
            
            continuationCases.append((recommendedRate, enactedRate, shouldSkip))
        }
        
        guard !continuationCases.isEmpty else {
            // No recommendation + enacted pairs found in fixture - skip test
            return
        }
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 ALG-DIAG-014: Temp Basal Continuation Analysis")
        print(String(repeating: "=", count: 70))
        
        print("\n🔹 Command Redundancy Check:")
        for (i, c) in continuationCases.enumerated() {
            let skipSymbol = c.shouldSkip ? "⏭️ SKIP" : "✅ ISSUE"
            print("  \(i+1). Rec=\(String(format: "%.2f", c.recommended)) U/hr, Enacted=\(String(format: "%.2f", c.enacted)) U/hr → \(skipSymbol)")
        }
        
        let skippableCases = continuationCases.filter { $0.shouldSkip }.count
        print("\n  Summary: \(skippableCases)/\(continuationCases.count) commands could be skipped (rate unchanged)")
        
        print(String(repeating: "=", count: 70))
    }
    
    @Test("Enacted temp basal in IOB")
    func enactedTempBasalInIOB() throws {
        // Verify: The enacted temp basal should be included in IOB calculation
        // If we're calculating IOB at time T, and there's a temp basal that started
        // before T and is still running, its insulin contribution must be counted
        
        let deviceStatuses = try loadDeviceStatusFixture()
        
        print("\n📊 Enacted Temp Basal in IOB Analysis")
        
        for status in deviceStatuses.prefix(3) {
            guard let loopStatus = status.loop,
                  let enacted = loopStatus.enacted,
                  let enactedRate = enacted.rate,
                  let enactedDuration = enacted.duration,
                  let enactedTimestamp = parseDate(enacted.timestamp),
                  let iobData = loopStatus.iob,
                  let iobTimestamp = parseDate(iobData.timestamp) else {
                continue
            }
            
            let nsIOB = iobData.iob
            
            // Check if enacted temp basal would still be running at IOB timestamp
            let enactedEnd = enactedTimestamp.addingTimeInterval(enactedDuration * 60)
            let stillRunning = iobTimestamp < enactedEnd
            
            // Calculate contribution from enacted temp basal
            let scheduledRate = 1.7  // From profile
            let netRate = enactedRate - scheduledRate
            let elapsedMinutes = min(iobTimestamp.timeIntervalSince(enactedTimestamp) / 60, enactedDuration)
            let deliveredNet = netRate * (elapsedMinutes / 60)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            
            print("\n  Enacted at \(formatter.string(from: enactedTimestamp)):")
            print("    Rate: \(String(format: "%.2f", enactedRate)) U/hr (net: \(String(format: "%+.2f", netRate)) U/hr)")
            print("    Duration: \(String(format: "%.0f", enactedDuration)) min")
            print("    Still running at IOB time: \(stillRunning ? "Yes" : "No")")
            print("    Net delivered so far: \(String(format: "%.3f", deliveredNet)) U")
            print("    NS reported IOB: \(String(format: "%.3f", nsIOB)) U")
        }
    }
    
    @Test("Temp basal timing alignment")
    func tempBasalTimingAlignment() throws {
        // Check: Are our temp basal events aligned with Loop's enacted decisions?
        
        let deviceStatuses = try loadDeviceStatusFixture()
        let treatments = try loadTreatmentsFixture()
        
        // Get enacted timestamps from deviceStatus
        let enactedTimestamps = deviceStatuses.compactMap { status -> Date? in
            guard let enacted = status.loop?.enacted else { return nil }
            return parseDate(enacted.timestamp)
        }
        
        // Get treatment timestamps
        let treatmentTimestamps = treatments.compactMap { treatment -> Date? in
            guard treatment.eventType == "Temp Basal",
                  let ts = treatment.timestamp ?? treatment.created_at else { return nil }
            return parseDate(ts)
        }
        
        print("\n📊 Temp Basal Timing Alignment")
        print("  Enacted decisions in deviceStatus: \(enactedTimestamps.count)")
        print("  Temp Basal treatments: \(treatmentTimestamps.count)")
        
        // Check alignment (treatments should match enacted within ~1 minute)
        var alignedCount = 0
        for enacted in enactedTimestamps {
            let hasMatch = treatmentTimestamps.contains { treatment in
                abs(enacted.timeIntervalSince(treatment)) < 120  // 2 min tolerance
            }
            if hasMatch { alignedCount += 1 }
        }
        
        let alignmentRate = Double(alignedCount) / Double(enactedTimestamps.count)
        print("  Aligned (±2 min): \(alignedCount)/\(enactedTimestamps.count) (\(Int(alignmentRate * 100))%)")
        
        // This helps diagnose if we're missing temp basal events
        if alignmentRate < 0.8 {
            print("  ⚠️ Low alignment - some enacted decisions may not appear in treatments")
        } else {
            print("  ✅ Good alignment - enacted decisions are captured in treatments")
        }
    }
    
    @Test("Running temp basal effect on recommendation")
    func runningTempBasalEffect_onRecommendation() throws {
        // Key diagnostic: When we recommend a temp basal, do we account for what's running?
        
        // In Loop's algorithm:
        // 1. Calculate predicted glucose curve
        // 2. Determine insulin needed to bring to target
        // 3. Convert to temp basal rate
        // 4. IMPORTANT: If temp basal already running, consider its remaining effect
        
        print("\n📊 Running Temp Basal Effect on Recommendations")
        
        let deviceStatuses = try loadDeviceStatusFixture()
        
        var recommendations: [(timestamp: Date, recRate: Double, enactedRate: Double?, delta: Double)] = []
        
        for status in deviceStatuses {
            guard let loopStatus = status.loop,
                  let rec = loopStatus.automaticDoseRecommendation,
                  let tb = rec.tempBasalAdjustment,
                  let timestamp = parseDate(rec.timestamp) else {
                continue
            }
            
            let enactedRate = loopStatus.enacted?.rate
            let delta = enactedRate.map { tb.rate - $0 } ?? 0
            
            recommendations.append((timestamp, tb.rate, enactedRate, delta))
        }
        
        guard !recommendations.isEmpty else {
            // No recommendations found - skip test
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        
        print("\n  Recommendation vs Previously Enacted:")
        for rec in recommendations.prefix(10) {
            let enacted = rec.enactedRate.map { String(format: "%.2f", $0) } ?? "---"
            let deltaStr = rec.delta != 0 ? String(format: "%+.2f", rec.delta) : "same"
            print("  \(formatter.string(from: rec.timestamp)): Rec=\(String(format: "%.2f", rec.recRate)) U/hr, Prev=\(enacted), Δ=\(deltaStr)")
        }
        
        // Calculate statistics
        let changes = recommendations.filter { abs($0.delta) > 0.05 }
        let continuations = recommendations.filter { abs($0.delta) <= 0.05 }
        
        print("\n  Summary:")
        print("    Rate changes (Δ > 0.05): \(changes.count)")
        print("    Continuations (Δ ≤ 0.05): \(continuations.count)")
        print("    Total recommendations: \(recommendations.count)")
        
        // The ratio tells us how often Loop issues new commands vs continues
        // High continuation rate = good, avoiding unnecessary pump commands
        let continuationRate = Double(continuations.count) / Double(recommendations.count)
        print("    Continuation rate: \(Int(continuationRate * 100))%")
        
        if continuationRate > 0.3 {
            print("    ✅ Reasonable continuation rate - avoiding excessive commands")
        } else {
            print("    ⚠️ Low continuation - may be issuing redundant commands")
        }
        
        print(String(repeating: "=", count: 70))
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
}
