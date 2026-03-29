// SPDX-License-Identifier: MIT
//
// ReplayCGMTests.swift
// T1Pal Mobile

import Testing
import Foundation
@testable import CGMKit
import T1PalCore

/// Test fixture path - use workspace-relative path
let glucoseFixturePath = "/home/bewest/src/t1pal-mobile-workspace/packages/T1PalNightscout/Tests/Fixtures/glucose.json"

@Suite("Replay CGM")
struct ReplayCGMTests {
    
    @Test("Config defaults")
    func configDefaults() {
        let config = ReplayCGMConfig(filePath: "/tmp/test.json")
        #expect(config.filePath == "/tmp/test.json")
        #expect(config.timeCompression == 1.0)
        #expect(config.loopPlayback == false)
    }
    
    @Test("Config time compression minimum")
    func configTimeCompressionMinimum() {
        let config = ReplayCGMConfig(filePath: "/tmp/test.json", timeCompression: 0.5)
        #expect(config.timeCompression == 1.0) // Should clamp to minimum
    }
    
    @Test("Config custom values")
    func configCustomValues() {
        let config = ReplayCGMConfig(
            filePath: "/data/glucose.json",
            timeCompression: 60.0,
            loopPlayback: true
        )
        #expect(config.filePath == "/data/glucose.json")
        #expect(config.timeCompression == 60.0)
        #expect(config.loopPlayback == true)
    }
    
    @Test("Load readings from fixture")
    func loadReadingsFromFixture() async throws {
        let replay = ReplayCGM(filePath: glucoseFixturePath)
        
        let count = try await replay.loadReadings()
        #expect(count > 0)
        #expect(await replay.readingCount == count)
        
        // Check first reading is accessible
        let first = await replay.reading(at: 0)
        #expect(first != nil)
        #expect(first!.glucose > 0)
    }
    
    @Test("Readings sorted by timestamp")
    func readingsSortedByTimestamp() async throws {
        let replay = ReplayCGM(filePath: glucoseFixturePath)
        
        _ = try await replay.loadReadings()
        
        let count = await replay.readingCount
        guard count >= 2 else {
            Issue.record("Need at least 2 readings for sort test")
            return
        }
        
        let first = await replay.reading(at: 0)!
        let second = await replay.reading(at: 1)!
        
        #expect(first.timestamp <= second.timestamp)
    }
    
    @Test("Next reading advances position")
    func nextReadingAdvancesPosition() async throws {
        let replay = ReplayCGM(filePath: glucoseFixturePath)
        
        _ = try await replay.loadReadings()
        
        let pos0 = await replay.currentPosition
        #expect(pos0 == 0)
        
        _ = await replay.nextReading()
        let pos1 = await replay.currentPosition
        #expect(pos1 == 1)
    }
    
    @Test("Start scanning loads and activates")
    func startScanningLoadsAndActivates() async throws {
        let replay = ReplayCGM(filePath: glucoseFixturePath)
        
        try await replay.startScanning()
        
        let state = await replay.sensorState
        #expect(state == .active)
        #expect(await replay.readingCount > 0)
    }
    
    @Test("Invalid file throws error")
    func invalidFileThrowsError() async {
        let replay = ReplayCGM(filePath: "/nonexistent/file.json")
        
        do {
            _ = try await replay.loadReadings()
            Issue.record("Should have thrown error")
        } catch {
            #expect(error is CGMError)
        }
    }
    
    @Test("CGMManagerProtocol conformance")
    func cgmManagerProtocolConformance() async {
        let replay = ReplayCGM(filePath: "/tmp/test.json")
        
        let name = await replay.displayName
        let type = await replay.cgmType
        
        #expect(name == "Replay CGM")
        #expect(type == .simulation)
    }
    
    @Test("Disconnect stops replay")
    func disconnectStopsReplay() async throws {
        let replay = ReplayCGM(filePath: glucoseFixturePath)
        
        try await replay.startScanning()
        await replay.disconnect()
        
        let state = await replay.sensorState
        #expect(state == .stopped)
    }
}
