// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// FixtureRegressionTests.swift
// T1PalAlgorithmTests
//
// Regression tests using captured NS fixtures.
// ALG-FIX-006: Add fixture replay to test suite

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Fixture Regression Tests")
struct FixtureRegressionTests {
    
    // Root fixtures directory (workspace level, not package level)
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FixtureRegressionTests.swift
            .deletingLastPathComponent() // T1PalAlgorithmTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // T1PalAlgorithm
            .deletingLastPathComponent() // packages
            .appendingPathComponent("fixtures")
    }
    
    // MARK: - Regression Fixtures
    
    @Test("Replay regression fixtures")
    func replayRegressionFixtures() throws {
        let regressionDir = fixturesRoot.appendingPathComponent("regression")
        
        guard FileManager.default.fileExists(atPath: regressionDir.path) else {
            // Skip if no regression fixtures
            return
        }
        
        let fixtures = try loadFixtures(from: regressionDir)
        guard !fixtures.isEmpty else { return } // Skip if no fixtures
        
        for (name, fixture) in fixtures {
            let result = try runAlgorithmReplay(fixture)
            // Regression: algorithm should complete and divergence tracked
            #expect(result.success, "Regression \(name): algorithm should complete")
        }
    }
    
    // MARK: - Edge Case Fixtures
    
    @Test("Replay edge case fixtures - high IOB")
    func replayHighIOBFixture() throws {
        let fixture = try loadFixtureNamed("high-iob", in: "edge-cases")
        guard let fixture else { return } // Skip if not present
        
        let result = try runAlgorithmReplay(fixture)
        
        // High IOB should complete without error
        #expect(result.success, "High IOB scenario should complete")
    }
    
    @Test("Replay edge case fixtures - negative IOB")
    func replayNegativeIOBFixture() throws {
        let fixture = try loadFixtureNamed("negative-iob", in: "edge-cases")
        guard let fixture else { return }
        
        let result = try runAlgorithmReplay(fixture)
        
        // Negative IOB should complete without error
        #expect(result.success, "Negative IOB scenario should complete")
    }
    
    // MARK: - Momentum Fixtures
    
    @Test("Replay momentum fixtures - rapid rise")
    func replayRapidRiseFixture() throws {
        let fixture = try loadFixtureNamed("rapid-rise", in: "momentum")
        guard let fixture else { return }
        
        let result = try runAlgorithmReplay(fixture)
        
        // Rapid rise should complete without error
        #expect(result.success, "Rapid rise scenario should complete")
    }
    
    @Test("Replay momentum fixtures - rapid fall")
    func replayRapidFallFixture() throws {
        let fixture = try loadFixtureNamed("rapid-fall", in: "momentum")
        guard let fixture else { return }
        
        let result = try runAlgorithmReplay(fixture)
        
        // Rapid fall should complete without error
        #expect(result.success, "Rapid fall scenario should complete")
    }
    
    // MARK: - Helpers
    
    /// Load first fixture matching name prefix in subdirectory.
    private func loadFixtureNamed(_ prefix: String, in subdir: String) throws -> ReplayFixture? {
        let dir = fixturesRoot.appendingPathComponent(subdir)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return nil
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix(prefix) }
        
        guard let url = files.first else { return nil }
        return try ReplayFixtureLoader.load(from: url)
    }
    
    private func loadFixtures(from directory: URL) throws -> [(String, ReplayFixture)] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, 
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        
        return try files.compactMap { url in
            let fixture = try ReplayFixtureLoader.load(from: url)
            return (url.lastPathComponent, fixture)
        }
    }
    
    private func runAlgorithmReplay(_ fixture: ReplayFixture) throws -> ReplayResult {
        // Convert fixture to algorithm inputs
        let readings = ReplayFixtureLoader.toGlucoseReadings(fixture)
        let profile = ReplayFixtureLoader.toTherapyProfile(fixture)
        let doses = ReplayFixtureLoader.toInsulinDoses(fixture)
        let carbs = ReplayFixtureLoader.toCarbEntries(fixture)
        
        // Get Loop's actual recommendation for comparison
        let (loopBasal, _) = ReplayFixtureLoader.getEnacted(fixture)
        let loopIOB = ReplayFixtureLoader.getLoopIOB(fixture) ?? 0.0
        let loopCOB = ReplayFixtureLoader.getLoopCOB(fixture) ?? 0.0
        
        // Build algorithm inputs
        guard !readings.isEmpty else {
            return ReplayResult(success: false, recommendedBasal: 0, loopBasal: loopBasal, divergencePercent: 0)
        }
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: loopIOB,
            carbsOnBoard: loopCOB,
            profile: profile,
            currentTime: fixture.metadata.capturedAt,
            doseHistory: doses,
            carbHistory: carbs
        )
        
        // Run our algorithm
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Extract recommended basal
        let ourBasal = decision.suggestedTempBasal?.rate ?? profile.basalRates.first?.rate ?? 1.0
        
        // Calculate divergence
        let divergence: Double
        if let loopBasal {
            divergence = abs(ourBasal - loopBasal) / max(loopBasal, 0.1) * 100
        } else {
            divergence = 0
        }
        
        return ReplayResult(
            success: true,
            recommendedBasal: ourBasal,
            loopBasal: loopBasal,
            divergencePercent: divergence
        )
    }
}

// MARK: - Result Type

private struct ReplayResult {
    let success: Bool
    let recommendedBasal: Double
    let loopBasal: Double?
    let divergencePercent: Double
}

// MARK: - Multi-File Fixture Replay Tests

@Suite("Algorithm Replay Fixtures")
struct AlgorithmReplayFixtureTests {
    
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays")
    }
    
    @Test("Replay stable-high BG fixture")
    func replayStableHighFixture() throws {
        let fixtureDir = fixturesRoot.appendingPathComponent("20260223-0830-stable-high")
        
        guard FileManager.default.fileExists(atPath: fixtureDir.path) else {
            return // Skip if not present
        }
        
        let fixture = try ReplayFixtureLoader.loadDirectory(from: fixtureDir)
        
        // Validate fixture has expected data
        #expect(fixture.entries.count > 100, "Should have CGM history")
        #expect(fixture.treatments.count > 50, "Should have treatment history")
        #expect(!fixture.deviceStatus.isEmpty, "Should have Loop devicestatus")
        
        // Run replay validation
        let stats = try runReplayValidation(fixture)
        
        // Report stats (informational, not strict assertions)
        print("Stable-high fixture replay:")
        print("  IOB divergence: \(String(format: "%.3f", stats.iobDivergence)) U")
        print("  Basal MAE: \(String(format: "%.2f", stats.basalMAE)) U/hr")
        print("  Prediction MAE: \(String(format: "%.1f", stats.predictionMAE)) mg/dL")
        
        // Algorithm should complete without error
        #expect(stats.completedCount > 0, "Should complete at least one replay")
    }
    
    @Test("Replay rising BG fixture")
    func replayRisingFixture() throws {
        let fixtureDir = fixturesRoot.appendingPathComponent("20260223-0805-rising-stable")
        
        guard FileManager.default.fileExists(atPath: fixtureDir.path) else {
            return // Skip if not present
        }
        
        let fixture = try ReplayFixtureLoader.loadDirectory(from: fixtureDir)
        
        #expect(fixture.entries.count > 100, "Should have CGM history")
        
        let stats = try runReplayValidation(fixture)
        
        print("Rising fixture replay:")
        print("  IOB divergence: \(String(format: "%.3f", stats.iobDivergence)) U")
        print("  Basal MAE: \(String(format: "%.2f", stats.basalMAE)) U/hr")
        print("  Prediction MAE: \(String(format: "%.1f", stats.predictionMAE)) mg/dL")
        
        #expect(stats.completedCount > 0, "Should complete at least one replay")
    }
    
    // MARK: - Replay Validation
    
    private struct ReplayStats {
        var completedCount: Int = 0
        var iobDivergence: Double = 0
        var basalMAE: Double = 0
        var predictionMAE: Double = 0
    }
    
    private func runReplayValidation(_ fixture: ReplayFixture) throws -> ReplayStats {
        var stats = ReplayStats()
        
        // Sort devicestatus by timestamp (newest first)
        let sortedStatus = fixture.deviceStatus.sorted { $0.timestamp > $1.timestamp }
        
        // Use first devicestatus as reference point
        guard let refStatus = sortedStatus.first else {
            return stats
        }
        
        // Get readings up to reference time
        let readings = ReplayFixtureLoader.toGlucoseReadings(fixture)
            .filter { $0.timestamp <= refStatus.timestamp }
            .prefix(288)  // ~24 hours
        
        guard readings.count >= 12 else { return stats }  // Need at least 1 hour
        
        let profile = ReplayFixtureLoader.toTherapyProfile(fixture)
        let doses = ReplayFixtureLoader.toInsulinDoses(fixture)
            .filter { $0.timestamp <= refStatus.timestamp }
        let carbs = ReplayFixtureLoader.toCarbEntries(fixture)
            .filter { $0.timestamp <= refStatus.timestamp }
        
        // Get Loop's values for comparison
        let loopIOB = refStatus.loopIOB ?? 0
        let loopCOB = refStatus.loopCOB ?? 0
        let loopBasal = refStatus.enactedTempBasalRate
        let loopPredictions = refStatus.loopPredicted ?? []
        
        // Build inputs and run algorithm
        let inputs = AlgorithmInputs(
            glucose: Array(readings),
            insulinOnBoard: loopIOB,
            carbsOnBoard: loopCOB,
            profile: profile,
            currentTime: refStatus.timestamp,
            doseHistory: doses,
            carbHistory: carbs
        )
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Calculate divergence metrics
        stats.completedCount = 1
        
        // IOB divergence: we use Loop's IOB as input, so this is 0 (no comparison available)
        stats.iobDivergence = 0
        
        // Basal divergence
        if let loopBasal {
            let ourBasal = decision.suggestedTempBasal?.rate ?? profile.basalRates.first?.rate ?? 1.0
            stats.basalMAE = abs(ourBasal - loopBasal)
        }
        
        // Prediction divergence (compare at 30min mark)
        if loopPredictions.count > 6 {
            let loopPred30 = loopPredictions[6]  // Index 6 = 30 min (5-min intervals)
            if let predictions = decision.predictions {
                // Use IOB predictions as baseline
                if predictions.iob.count > 6 {
                    let ourPred30 = predictions.iob[6]
                    stats.predictionMAE = abs(ourPred30 - loopPred30)
                }
            }
        }
        
        return stats
    }
}

// MARK: - Scenario Fixture Regression Tests (IOB-FIX-004)

@Suite("Scenario Fixture Regression")
struct ScenarioFixtureRegressionTests {
    
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays")
    }
    
    /// IOB-FIX-004: Regression test for all scenario fixtures
    /// Ensures IOB parity doesn't regress below baseline threshold
    @Test("Scenario IOB regression baseline")
    func scenarioIOBRegression() throws {
        let files = try FileManager.default.contentsOfDirectory(at: fixturesRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("scenario-") && $0.pathExtension == "json" }
        
        guard !files.isEmpty else {
            print("No scenario fixtures found, skipping")
            return
        }
        
        var totalCycles = 0
        var totalPasses = 0
        var results: [(name: String, passRate: Double)] = []
        
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            
            do {
                let stats = try runScenarioValidation(url: url)
                totalCycles += stats.cycleCount
                totalPasses += stats.passCount
                results.append((name, stats.passRate))
            } catch {
                print("Error validating \(name): \(error)")
            }
        }
        
        let overallPassRate = totalCycles > 0 ? Double(totalPasses) / Double(totalCycles) : 0
        
        print("\n=== Scenario IOB Regression ===")
        for (name, rate) in results {
            let status = rate >= 0.3 ? "✓" : "✗"
            print("\(status) \(name): \(String(format: "%.0f", rate * 100))%")
        }
        print("Overall: \(totalCycles) cycles, \(String(format: "%.1f", overallPassRate * 100))% pass")
        
        // Regression threshold: maintain at least 15% pass rate (below current 21.3%)
        // This catches significant regressions without failing on minor fluctuations
        let regressionThreshold = 0.15
        #expect(overallPassRate >= regressionThreshold,
            "IOB pass rate (\(String(format: "%.1f", overallPassRate * 100))%) should not regress below \(Int(regressionThreshold * 100))%")
        
        #expect(totalCycles >= 100, "Should validate at least 100 cycles (found \(totalCycles))")
    }
    
    // MARK: - Individual Scenario Tests
    
    @Test("Scenario: stable glucose")
    func scenarioStable() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        let stats = try runScenarioValidation(url: url)
        
        // scenario-stable should have highest pass rate (~40%)
        #expect(stats.passRate >= 0.25, "scenario-stable should maintain >= 25% pass rate")
        print("scenario-stable: \(String(format: "%.0f", stats.passRate * 100))% pass, mean Δ=\(String(format: "%.2f", stats.meanDivergence))U")
    }
    
    @Test("Scenario: rising glucose")
    func scenarioRising() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-rising-glucose.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        let stats = try runScenarioValidation(url: url)
        
        #expect(stats.passRate >= 0.20, "scenario-rising-glucose should maintain >= 20% pass rate")
        print("scenario-rising-glucose: \(String(format: "%.0f", stats.passRate * 100))% pass")
    }
    
    // MARK: - Helper
    
    private struct ScenarioStats {
        var cycleCount: Int = 0
        var passCount: Int = 0
        var meanDivergence: Double = 0
        var passRate: Double { cycleCount > 0 ? Double(passCount) / Double(cycleCount) : 0 }
    }
    
    private func runScenarioValidation(url: URL) throws -> ScenarioStats {
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let deviceStatuses = NSScenarioFixtureLoader.toDeviceStatusRecords(scenario)
        let treatments = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        guard !deviceStatuses.isEmpty else {
            return ScenarioStats()
        }
        
        // Extract profile from fixture
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
        
        let engine = LoopReplayEngine(
            deviceStatuses: deviceStatuses,
            treatments: treatments,
            glucose: [],
            profile: profile,
            settings: settings
        )
        
        let results = engine.replay()
        
        var stats = ScenarioStats()
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
            stats.meanDivergence = divergences.reduce(0, +) / Double(divergences.count)
        }
        
        return stats
    }
}
