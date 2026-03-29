// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ReplayFixtureLoaderTests.swift
// T1PalAlgorithmTests
//
// Tests for loading and replaying captured session fixtures.
// ALG-VAL-002: Create replay fixtures from real sessions

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Replay Fixture Loader")
struct ReplayFixtureLoaderTests {
    
    // MARK: - Fixture Loading
    
    @Test("Load fixture from conformance directory")
    func loadFixtureFromConformance() throws {
        // Load the captured fixture
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("conformance/algorithm/replay/fixture_loop_session_001.json")
        
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            // Skip if fixture not present (CI may not have it)
            return
        }
        
        let fixture = try ReplayFixtureLoader.load(from: fixtureURL)
        
        #expect(fixture.metadata.fixtureVersion == "1.0")
        #expect(fixture.metadata.sourceType == "nightscout")
        #expect(fixture.metadata.highFidelity == true)
        #expect(!fixture.entries.isEmpty)
        #expect(!fixture.deviceStatus.isEmpty)
    }
    
    @Test("Convert entries to glucose readings")
    func convertEntriesToGlucoseReadings() throws {
        let fixture = try makeMinimalFixture()
        
        let readings = ReplayFixtureLoader.toGlucoseReadings(fixture)
        
        #expect(readings.count == 3)
        // Should be sorted newest first
        #expect(readings[0].timestamp > readings[1].timestamp)
        #expect(readings[0].glucose == 120)
    }
    
    @Test("Convert treatments to insulin doses")
    func convertTreatmentsToInsulinDoses() throws {
        let fixture = try makeMinimalFixture()
        
        let doses = ReplayFixtureLoader.toInsulinDoses(fixture)
        
        #expect(doses.count == 1)
        #expect(doses[0].units == 2.5)
        #expect(doses[0].source == "replay_bolus")
    }
    
    @Test("Convert treatments to carb entries")
    func convertTreatmentsToCarbEntries() throws {
        let fixture = try makeMinimalFixture()
        
        let carbs = ReplayFixtureLoader.toCarbEntries(fixture)
        
        #expect(carbs.count == 1)
        #expect(carbs[0].grams == 30)
    }
    
    @Test("Convert profile to TherapyProfile")
    func convertProfileToTherapyProfile() throws {
        let fixture = try makeMinimalFixture()
        
        let profile = ReplayFixtureLoader.toTherapyProfile(fixture)
        
        #expect(profile.basalRates.count == 1)
        #expect(profile.basalRates[0].rate == 1.5)
        #expect(profile.sensitivityFactors[0].factor == 40)
        #expect(profile.carbRatios[0].ratio == 10)
    }
    
    @Test("Get Loop IOB from deviceStatus")
    func getLoopIOBFromDeviceStatus() throws {
        let fixture = try makeMinimalFixture()
        
        let iob = ReplayFixtureLoader.getLoopIOB(fixture)
        
        #expect(iob == 1.5)
    }
    
    @Test("Get enacted decision from comparison")
    func getEnactedDecision() throws {
        let fixture = try makeMinimalFixture()
        
        let (tempBasal, smb) = ReplayFixtureLoader.getEnacted(fixture)
        
        #expect(tempBasal == 0.0)
        #expect(smb == nil)
    }
    
    @Test("Get recommendation for algorithm")
    func getRecommendation() throws {
        let fixture = try makeMinimalFixture()
        
        let rec = ReplayFixtureLoader.getRecommendation(fixture, algorithm: "Loop")
        
        #expect(rec?.tempBasalRate == 0.0)
    }
    
    // MARK: - Helpers
    
    private func makeMinimalFixture() throws -> ReplayFixture {
        let now = Date()
        
        let metadata = ReplayMetadata(
            fixtureVersion: "1.0",
            capturedAt: now,
            toolVersion: "test",
            sourceType: "test",
            sourceURLHash: nil,
            sinceTime: nil,
            highFidelity: true
        )
        
        let deviceStatus = [
            ReplayDeviceStatus(
                timestamp: now,
                device: "test",
                loopIOB: 1.5,
                loopCOB: 20,
                loopPredicted: [120, 115, 110],
                loopPredictedStart: now,
                enactedTempBasalRate: 0.0,
                enactedTempBasalDuration: 30,
                enactedSMB: nil,
                aapsIOB: nil,
                aapsCOB: nil,
                aapsTempBasal: nil,
                reservoir: 100,
                batteryPercent: 80
            )
        ]
        
        let entries = [
            ReplayEntry(timestamp: now, sgv: 120, direction: "Flat", delta: 0),
            ReplayEntry(timestamp: now.addingTimeInterval(-300), sgv: 118, direction: "Flat", delta: -2),
            ReplayEntry(timestamp: now.addingTimeInterval(-600), sgv: 115, direction: "FortyFiveUp", delta: 3)
        ]
        
        let treatments = [
            ReplayTreatment(timestamp: now.addingTimeInterval(-1800), eventType: "Bolus", insulin: 2.5, rate: nil, durationMinutes: nil, carbs: nil, absorptionTime: nil),
            ReplayTreatment(timestamp: now.addingTimeInterval(-3600), eventType: "Carbs", insulin: nil, rate: nil, durationMinutes: nil, carbs: 30, absorptionTime: 3)
        ]
        
        let profile = ReplayProfile(
            name: "Default",
            basalSchedule: [ReplayScheduleEntry(startSeconds: 0, value: 1.5)],
            isfSchedule: [ReplayScheduleEntry(startSeconds: 0, value: 40)],
            crSchedule: [ReplayScheduleEntry(startSeconds: 0, value: 10)],
            targetLow: 100,
            targetHigh: 110,
            maxBasalRate: 6.0,
            maxBolus: 10.0,
            suspendThreshold: 70,
            dosingStrategy: "tempBasalOnly"
        )
        
        let comparison = ReplayComparison(
            algorithms: ["Loop"],
            recommendations: [
                ReplayRecommendation(algorithm: "Loop", tempBasalRate: 0.0, tempBasalDuration: 30, smb: nil)
            ],
            enacted: ReplayEnacted(source: "Loop", tempBasalRate: 0.0, tempBasalDuration: 30, smb: nil)
        )
        
        return ReplayFixture(
            metadata: metadata,
            deviceStatus: deviceStatus,
            entries: entries,
            treatments: treatments,
            profile: profile,
            comparison: comparison
        )
    }
}

// MARK: - Multi-File Fixture Tests

@Suite("Multi-File Fixture Loader")
struct MultiFileFixtureLoaderTests {
    
    @Test("Load multi-file fixture from directory")
    func loadMultiFileFixture() throws {
        // Path to captured fixture directory
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays/20260223-0830-stable-high")
        
        guard FileManager.default.fileExists(atPath: fixtureDir.path) else {
            return // Skip if fixture not present
        }
        
        let fixture = try ReplayFixtureLoader.loadDirectory(from: fixtureDir)
        
        #expect(fixture.metadata.fixtureVersion == "2.0-multifile")
        #expect(fixture.metadata.toolVersion == "ns-fixture-capture")
        #expect(!fixture.entries.isEmpty, "Should have CGM entries")
        #expect(!fixture.treatments.isEmpty, "Should have treatments")
        #expect(!fixture.deviceStatus.isEmpty, "Should have devicestatus")
        #expect(fixture.profile != nil, "Should have profile")
    }
    
    @Test("Multi-file fixture has valid glucose readings")
    func multiFileFixtureHasValidGlucose() throws {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays/20260223-0830-stable-high")
        
        guard FileManager.default.fileExists(atPath: fixtureDir.path) else {
            return
        }
        
        let fixture = try ReplayFixtureLoader.loadDirectory(from: fixtureDir)
        let readings = ReplayFixtureLoader.toGlucoseReadings(fixture)
        
        #expect(readings.count > 100, "Should have multiple hours of readings")
        #expect(readings.allSatisfy { $0.glucose > 40 && $0.glucose < 400 }, "All readings should be in valid range")
    }
    
    @Test("Multi-file fixture has Loop devicestatus")
    func multiFileFixtureHasLoopData() throws {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays/20260223-0830-stable-high")
        
        guard FileManager.default.fileExists(atPath: fixtureDir.path) else {
            return
        }
        
        let fixture = try ReplayFixtureLoader.loadDirectory(from: fixtureDir)
        
        // Should have Loop predictions
        let withPredictions = fixture.deviceStatus.filter { $0.loopPredicted != nil }
        #expect(!withPredictions.isEmpty, "Should have devicestatus with predictions")
        
        // Should have Loop IOB
        let withIOB = fixture.deviceStatus.filter { $0.loopIOB != nil }
        #expect(!withIOB.isEmpty, "Should have devicestatus with IOB")
    }
}
