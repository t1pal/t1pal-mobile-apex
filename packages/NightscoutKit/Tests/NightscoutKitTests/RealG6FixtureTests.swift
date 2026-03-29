// RealG6FixtureTests.swift
// Tests using real Dexcom G6 data from T1Pal Nightscout instance
// Captured: 2026-02-05
// Trace: LIVE-BACKLOG fixture integration

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

// MARK: - Real G6 Entry Fixtures

/// Real Nightscout entries from Dexcom G6 8QTPWY transmitter
/// Captured 2026-02-05 from T1Pal Nightscout instance
enum RealG6Fixtures {
    
    /// JSON fixture for 50 real CGM entries (most recent first)
    static let entriesJSON = """
    [
        {"_id":"698451509b496fca85a1f02e","date":1770279229491,"sgv":198,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:13:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984501e9b496fca859c9240","date":1770278929221,"sgv":198,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:08:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844ef29b496fca85973df7","date":1770278629096,"sgv":200,"trend":4,"trendRate":0.2,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:03:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844dc79b496fca85920485","date":1770278329283,"sgv":200,"trend":4,"trendRate":0.3,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:58:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844c9a9b496fca858cc7a7","date":1770278029267,"sgv":200,"trend":4,"trendRate":0.6,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:53:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844b6f9b496fca8587ab96","date":1770277729471,"sgv":201,"trend":4,"trendRate":0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:48:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844a449b496fca85826c8a","date":1770277429197,"sgv":198,"trend":4,"trendRate":0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:43:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698449169b496fca857d3a80","date":1770277129487,"sgv":191,"trend":4,"trendRate":0.4,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:38:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698447ef9b496fca85781eb7","date":1770276829674,"sgv":183,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:33:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698446be9b496fca8572b7ac","date":1770276529650,"sgv":181,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:28:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698445939b496fca856d8534","date":1770276229299,"sgv":183,"trend":4,"trendRate":0.2,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:23:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984446a9b496fca856845e8","date":1770275929081,"sgv":185,"trend":4,"trendRate":0.6,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:18:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984433a9b496fca8562e925","date":1770275629424,"sgv":186,"trend":4,"trendRate":0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:13:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698442109b496fca855d9f58","date":1770275328829,"sgv":184,"trend":4,"trendRate":0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:08:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"698440e29b496fca855834fa","date":1770275029417,"sgv":178,"trend":4,"trendRate":0.6,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:03:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69843fb69b496fca8552e519","date":1770274728936,"sgv":171,"trend":4,"trendRate":0.4,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:58:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69843e8a9b496fca854d9f92","date":1770274429001,"sgv":168,"trend":4,"trendRate":0.3,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:53:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69843d5f9b496fca85487094","date":1770274128747,"sgv":167,"trend":4,"trendRate":0.3,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:48:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69843c359b496fca85432e4d","date":1770273829543,"sgv":166,"trend":4,"trendRate":0.5,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:43:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69843b079b496fca853dd958","date":1770273529105,"sgv":166,"trend":4,"trendRate":0.7,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:38:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698439e59b496fca8538bfb3","date":1770273229335,"sgv":165,"trend":3,"trendRate":1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:33:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698438ae9b496fca85334d9a","date":1770272929477,"sgv":164,"trend":3,"trendRate":1.3,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:28:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698437859b496fca852e2c06","date":1770272629290,"sgv":158,"trend":3,"trendRate":1.1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:23:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698436599b496fca852909df","date":1770272329015,"sgv":148,"trend":4,"trendRate":0.7,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:18:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984352c9b496fca8523c356","date":1770272029554,"sgv":139,"trend":4,"trendRate":0.5,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:13:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698433ff9b496fca851e60b1","date":1770271729632,"sgv":140,"trend":4,"trendRate":0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:08:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698432d39b496fca8518e918","date":1770271429574,"sgv":140,"trend":3,"trendRate":1.2,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:03:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698431a59b496fca8513aeb7","date":1770271129300,"sgv":136,"trend":3,"trendRate":1.3,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:58:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984307a9b496fca850e6a71","date":1770270828755,"sgv":130,"trend":3,"trendRate":1.3,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:53:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842f4f9b496fca850925df","date":1770270528873,"sgv":122,"trend":3,"trendRate":1.1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:48:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842e229b496fca8503d47f","date":1770270229124,"sgv":114,"trend":4,"trendRate":0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:43:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842cf59b496fca85fe7a92","date":1770269929134,"sgv":106,"trend":4,"trendRate":0.5,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:38:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842bcb9b496fca85f947c6","date":1770269629219,"sgv":103,"trend":4,"trendRate":0.5,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:33:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842a9e9b496fca85f402fa","date":1770269329466,"sgv":100,"trend":4,"trendRate":0.6,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:28:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698429729b496fca85eee061","date":1770269028939,"sgv":97,"trend":4,"trendRate":0.5,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:23:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698428459b496fca85e99f84","date":1770268729146,"sgv":92,"trend":4,"trendRate":0.2,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:18:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698427199b496fca85e457a9","date":1770268428854,"sgv":86,"trend":4,"trendRate":-0.1,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:13:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698425ed9b496fca85df16b2","date":1770268128956,"sgv":81,"trend":4,"trendRate":-0.4,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:08:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698424c19b496fca85d9c855","date":1770267829089,"sgv":77,"trend":4,"trendRate":-0.6,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:03:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"698423959b496fca85d48c65","date":1770267528750,"sgv":72,"trend":4,"trendRate":-0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:58:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698422679b496fca85cf3c6c","date":1770267229135,"sgv":69,"trend":4,"trendRate":-0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:53:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984213c9b496fca85c9f1fb","date":1770266929096,"sgv":66,"trend":4,"trendRate":-0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:48:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698420129b496fca85c4a261","date":1770266628872,"sgv":64,"trend":4,"trendRate":-0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:43:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69841ee69b496fca85bf62e6","date":1770266329357,"sgv":68,"trend":4,"trendRate":-0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:38:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69841dba9b496fca85ba2718","date":1770266029079,"sgv":72,"trend":4,"trendRate":-0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:33:49.000Z","type":"sgv","isCalibration":false}
    ]
    """
    
    /// Low glucose event scenario (64-77 mg/dL range)
    static let lowGlucoseJSON = """
    [
        {"_id":"698420129b496fca85c4a261","date":1770266628872,"sgv":64,"trend":4,"trendRate":-0.8,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:43:48.000Z","type":"sgv","isCalibration":false},
        {"_id":"69841ee69b496fca85bf62e6","date":1770266329357,"sgv":68,"trend":4,"trendRate":-0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:38:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69841dba9b496fca85ba2718","date":1770266029079,"sgv":72,"trend":4,"trendRate":-0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T04:33:49.000Z","type":"sgv","isCalibration":false}
    ]
    """
    
    /// Rising glucose scenario (122-165 mg/dL with FortyFiveUp trend)
    static let risingGlucoseJSON = """
    [
        {"_id":"698439e59b496fca8538bfb3","date":1770273229335,"sgv":165,"trend":3,"trendRate":1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:33:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698438ae9b496fca85334d9a","date":1770272929477,"sgv":164,"trend":3,"trendRate":1.3,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:28:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"698437859b496fca852e2c06","date":1770272629290,"sgv":158,"trend":3,"trendRate":1.1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T06:23:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69842f4f9b496fca850925df","date":1770270528873,"sgv":122,"trend":3,"trendRate":1.1,"direction":"FortyFiveUp","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T05:48:48.000Z","type":"sgv","isCalibration":false}
    ]
    """
    
    /// High glucose stable scenario (198-201 mg/dL)
    static let highStableJSON = """
    [
        {"_id":"698451509b496fca85a1f02e","date":1770279229491,"sgv":198,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:13:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"6984501e9b496fca859c9240","date":1770278929221,"sgv":198,"trend":4,"trendRate":0,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:08:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844ef29b496fca85973df7","date":1770278629096,"sgv":200,"trend":4,"trendRate":0.2,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T08:03:49.000Z","type":"sgv","isCalibration":false},
        {"_id":"69844b6f9b496fca8587ab96","date":1770277729471,"sgv":201,"trend":4,"trendRate":0.9,"direction":"Flat","device":"Dexcom G6 8QTPWY","dateString":"2026-02-05T07:48:49.000Z","type":"sgv","isCalibration":false}
    ]
    """
}

// MARK: - Tests

@Suite("Real G6 Fixture Decoding")
struct RealG6FixtureDecodingTests {
    
    @Test("Decode 45 real G6 entries from fixture")
    func decodeAllEntries() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        #expect(entries.count == 45)
        
        // Verify first entry
        let first = entries[0]
        #expect(first.sgv == 198)
        #expect(first.direction == "Flat")
        #expect(first.device == "Dexcom G6 8QTPWY")
        
        // Verify last entry
        let last = entries[entries.count - 1]
        #expect(last.sgv == 72)
    }
    
    @Test("Decode low glucose scenario")
    func decodeLowGlucose() throws {
        let data = RealG6Fixtures.lowGlucoseJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.sgv! < 80 })
        #expect(entries[0].sgv == 64) // Lowest
    }
    
    @Test("Decode rising glucose scenario")
    func decodeRisingGlucose() throws {
        let data = RealG6Fixtures.risingGlucoseJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.direction == "FortyFiveUp" })
    }
    
    @Test("Decode high stable scenario")
    func decodeHighStable() throws {
        let data = RealG6Fixtures.highStableJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.sgv! >= 198 })
        #expect(entries.allSatisfy { $0.direction == "Flat" })
    }
    
    @Test("Convert entries to GlucoseReading")
    func convertToGlucoseReadings() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        let readings = entries.compactMap { $0.toGlucoseReading() }
        
        #expect(readings.count == 45)
        #expect(readings.allSatisfy { $0.source == "Dexcom G6 8QTPWY" })
    }
    
    @Test("Verify direction values")
    func verifyDirections() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        // Find entries with Flat direction
        let flat = entries.filter { $0.direction == "Flat" }
        #expect(!flat.isEmpty)
        
        // Find entries with FortyFiveUp direction
        let rising = entries.filter { $0.direction == "FortyFiveUp" }
        #expect(!rising.isEmpty)
    }
    
    @Test("Verify 5-minute intervals")
    func verifyIntervals() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        // Check consecutive entries are ~5 minutes apart
        for i in 0..<(entries.count - 1) {
            let diff = entries[i].date - entries[i + 1].date
            // Should be approximately 300000ms (5 minutes) ± 60 seconds tolerance
            #expect(abs(diff - 300000) < 60000, "Interval between entries should be ~5 minutes")
        }
    }
}

@Suite("Real G6 Glucose Range Analysis")
struct RealG6RangeAnalysisTests {
    
    @Test("Calculate time in range")
    func calculateTimeInRange() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        let total = entries.count
        let inRange = entries.filter { ($0.sgv ?? 0) >= 70 && ($0.sgv ?? 0) <= 180 }.count
        let low = entries.filter { ($0.sgv ?? 0) < 70 }.count
        let high = entries.filter { ($0.sgv ?? 0) > 180 }.count
        
        let tirPercent = Double(inRange) / Double(total) * 100
        
        #expect(low > 0, "Fixture should contain low glucose values")
        #expect(high > 0, "Fixture should contain high glucose values")
        #expect(tirPercent > 0 && tirPercent < 100, "TIR should be between 0 and 100%")
    }
    
    @Test("Identify glucose extremes")
    func identifyExtremes() throws {
        let data = RealG6Fixtures.entriesJSON.data(using: .utf8)!
        let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
        
        let values = entries.compactMap { $0.sgv }
        let min = values.min()!
        let max = values.max()!
        
        #expect(min == 64, "Minimum should be 64 mg/dL")
        #expect(max == 201, "Maximum should be 201 mg/dL")
    }
}
