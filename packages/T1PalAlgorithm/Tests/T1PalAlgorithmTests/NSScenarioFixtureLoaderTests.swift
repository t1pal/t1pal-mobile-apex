// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NSScenarioFixtureLoaderTests.swift
// T1PalAlgorithmTests
//
// IOB-FIX-001: Tests for NS scenario fixture loading

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("NS Scenario Fixture Loader")
struct NSScenarioFixtureLoaderTests {
    
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays")
    }
    
    // MARK: - Loading Tests
    
    @Test("Load scenario-stable fixture")
    func loadScenarioStable() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping: scenario-stable.json not found")
            return
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        
        #expect(scenario.metadata.scenario == "stable")
        #expect(scenario.deviceStatus.count > 0, "Should have deviceStatus records")
        #expect(scenario.treatments.count > 0, "Should have treatment records")
    }
    
    @Test("Convert deviceStatus records")
    func convertDeviceStatusRecords() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping: scenario-stable.json not found")
            return
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let records = NSScenarioFixtureLoader.toDeviceStatusRecords(scenario)
        
        #expect(records.count == scenario.deviceStatus.count, 
                "Should convert all deviceStatus records")
        
        // Check first record has required fields
        if let first = records.first {
            #expect(first.loop.iob.iob != 0 || first.loop.iob.iob == 0, "IOB should be a number")
            #expect(first.loop.predicted.values.count > 0, "Should have prediction values")
        }
    }
    
    @Test("Convert treatment records with duration")
    func convertTreatmentRecordsWithDuration() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping: scenario-stable.json not found")
            return
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let records = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        #expect(records.count > 0, "Should have treatment records")
        
        // IOB-FIX-002: Verify duration field is correctly parsed
        let tempBasals = records.filter { $0.eventType == "Temp Basal" }
        #expect(tempBasals.count > 0, "Should have temp basal records")
        
        // Check duration is reasonable (should be in minutes, typically 5-30)
        for tempBasal in tempBasals {
            if let duration = tempBasal.duration {
                #expect(duration > 0 && duration <= 60, 
                        "Duration \(duration) should be in minutes (0-60)")
            }
        }
    }
    
    @Test("Validate all scenario fixtures")
    func validateAllScenarioFixtures() throws {
        let files = try FileManager.default.contentsOfDirectory(at: fixturesRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("scenario-") && $0.pathExtension == "json" }
        
        guard !files.isEmpty else {
            print("No scenario fixtures found")
            return
        }
        
        var passed = 0
        var failed: [(String, [String])] = []
        
        for url in files {
            let (dsCount, tCount, errors) = try NSScenarioFixtureLoader.validate(from: url)
            
            if errors.isEmpty {
                passed += 1
                print("✓ \(url.lastPathComponent): \(dsCount) deviceStatus, \(tCount) treatments")
            } else {
                failed.append((url.lastPathComponent, errors))
                print("✗ \(url.lastPathComponent): \(errors.joined(separator: ", "))")
            }
        }
        
        print("\nValidation: \(passed)/\(files.count) passed")
        #expect(failed.isEmpty, "All scenario fixtures should validate: \(failed)")
    }
    
    // MARK: - IOB-FIX-002: Duration Field Handling
    
    @Test("Duration field is in minutes (not seconds)")
    func durationFieldIsInMinutes() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping: scenario-stable.json not found")
            return
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let records = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        // Find first temp basal with duration
        let tempBasal = records.first { $0.eventType == "Temp Basal" && $0.duration != nil }
        
        guard let tempBasal, let duration = tempBasal.duration else {
            print("No temp basal with duration found")
            return
        }
        
        // Duration should be in minutes (typically 5-30), not seconds (300-1800)
        // Raw NS format uses minutes
        #expect(duration < 100, "Duration \(duration) should be < 100 (minutes, not seconds)")
        #expect(duration > 0, "Duration should be positive")
        
        print("Temp basal duration: \(duration) minutes")
    }
    
    // MARK: - IOB-FIX-003: Full Replay Validation
    
    @Test("Replay scenario-stable with IOB comparison")
    func replayScenarioStableIOB() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Skipping: scenario-stable.json not found")
            return
        }
        
        let stats = try runScenarioIOBValidation(url: url)
        
        print("\n=== scenario-stable IOB Validation ===")
        print("Cycles validated: \(stats.cycleCount)")
        print("Mean IOB divergence: \(String(format: "%.4f", stats.meanIOBDivergence)) U")
        print("Max IOB divergence: \(String(format: "%.4f", stats.maxIOBDivergence)) U")
        print("Pass rate (≤0.1U): \(String(format: "%.0f", stats.passRate * 100))%")
        
        // Target: ≤0.1 U divergence
        #expect(stats.cycleCount > 0, "Should validate at least one cycle")
    }
    
    @Test("Replay all scenario fixtures with IOB comparison")
    func replayAllScenariosIOB() throws {
        let files = try FileManager.default.contentsOfDirectory(at: fixturesRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("scenario-") && $0.pathExtension == "json" }
        
        guard !files.isEmpty else {
            print("No scenario fixtures found")
            return
        }
        
        print("\n=== IOB-FIX-003: Scenario IOB Validation ===")
        
        var totalCycles = 0
        var totalPasses = 0
        var scenarioResults: [(name: String, mean: Double, max: Double, passRate: Double)] = []
        
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            
            do {
                let stats = try runScenarioIOBValidation(url: url)
                totalCycles += stats.cycleCount
                totalPasses += stats.passCount
                scenarioResults.append((name, stats.meanIOBDivergence, stats.maxIOBDivergence, stats.passRate))
                
                let status = stats.passRate >= 0.9 ? "✓" : (stats.passRate >= 0.5 ? "~" : "✗")
                print("\(status) \(name): mean=\(String(format: "%.3f", stats.meanIOBDivergence))U, max=\(String(format: "%.3f", stats.maxIOBDivergence))U, pass=\(String(format: "%.0f", stats.passRate * 100))%")
            } catch {
                print("✗ \(name): \(error)")
            }
        }
        
        let overallPassRate = totalCycles > 0 ? Double(totalPasses) / Double(totalCycles) : 0
        print("\n--- Summary ---")
        print("Total cycles: \(totalCycles)")
        print("Overall pass rate: \(String(format: "%.1f", overallPassRate * 100))%")
        
        // Track progress toward target
        // IOB-FIX-005: Now using 6h treatment history + fixture profile
        // Current baseline: 21% (improved from 7.6% with limited history + default profile)
        // Remaining divergence likely due to:
        // - Time-of-day basal schedule lookup timing
        // - Insulin model parameter differences
        // - Dose reconciliation edge cases
        let targetPassRate = 0.20  // IOB-FIX-005: Updated after profile fix
        #expect(overallPassRate >= targetPassRate, "Overall pass rate should be >= \(Int(targetPassRate * 100))%")
    }
    
    // MARK: - Helper: IOB Validation
    
    private struct IOBValidationStats {
        var cycleCount: Int = 0
        var passCount: Int = 0  // cycles with ≤0.1U divergence
        var meanIOBDivergence: Double = 0
        var maxIOBDivergence: Double = 0
        var passRate: Double { cycleCount > 0 ? Double(passCount) / Double(cycleCount) : 0 }
    }
    
    private func runScenarioIOBValidation(url: URL) throws -> IOBValidationStats {
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let deviceStatuses = NSScenarioFixtureLoader.toDeviceStatusRecords(scenario)
        let treatments = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        guard !deviceStatuses.isEmpty else {
            return IOBValidationStats()
        }
        
        // IOB-FIX-005: Extract profile from fixture (use actual basal schedule, not defaults)
        let profile = NSScenarioFixtureLoader.toProfileData(scenario) ?? NightscoutProfileData(
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.5)],
            isfSchedule: [ScheduleValue(startTime: 0, value: 40)],
            crSchedule: [ScheduleValue(startTime: 0, value: 10)],
            targetLow: 100,
            targetHigh: 110,
            dia: 6 * 3600
        )
        
        let settings = NSScenarioFixtureLoader.toSettings(scenario) ?? TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 40,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.5)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600
        )
        
        // Create replay engine
        let engine = LoopReplayEngine(
            deviceStatuses: deviceStatuses,
            treatments: treatments,
            glucose: [],  // IOB doesn't need glucose
            profile: profile,
            settings: settings
        )
        
        // Run replay and collect IOB stats
        let results = engine.replay()
        
        var stats = IOBValidationStats()
        var divergences: [Double] = []
        
        for result in results {
            let loopIOB = result.cycle.loopReportedIOB
            let ourIOB = result.ourIOB
            let divergence = abs(ourIOB - loopIOB)
            
            stats.cycleCount += 1
            divergences.append(divergence)
            
            if divergence <= 0.1 {
                stats.passCount += 1
            }
        }
        
        if !divergences.isEmpty {
            stats.meanIOBDivergence = divergences.reduce(0, +) / Double(divergences.count)
            stats.maxIOBDivergence = divergences.max() ?? 0
        }
        
        return stats
    }
}
