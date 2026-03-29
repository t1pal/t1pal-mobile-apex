// MultiSystemComparisonTests.swift - Cross-system deviceStatus comparison
// Part of NightscoutKitTests
// Trace: NS-MS-021, NS-MS-022, NS-MS-023

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

/// Tests for NS-MULTI-SYSTEM Phase 3: Cross-System Comparison
/// Verifies that UnifiedAlgorithmStatus correctly extracts data from all AID systems
@Suite("Multi-System Comparison")
struct MultiSystemComparisonTests {
    
    // MARK: - Fixture Loading Helpers
    
    /// Load deviceStatus fixture from test bundle
    func loadFixture(_ name: String) throws -> [NightscoutDeviceStatus] {
        // Check test bundle first
        if let fixtureURL = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/devicestatus"
        ) {
            let data = try Data(contentsOf: fixtureURL)
            return try JSONDecoder().decode([NightscoutDeviceStatus].self, from: data)
        }
        
        // Fallback to inline fixtures
        throw TestError("Fixture \(name) not found in test bundle")
    }
    
    // MARK: - NS-MS-021: AAPS Comparison
    
    @Test("Parse AAPS deviceStatus fixture")
    func parseAAPSFixture() throws {
        // AAPS deviceStatus with full OpenAPS fields
        // Note: AAPS device string contains "AndroidAPS" or "AAPS"
        let json = """
        {
            "device": "AndroidAPS-samsung-SM-G998B",
            "created_at": "2026-02-19T12:00:00.000Z",
            "openaps": {
                "iob": {
                    "iob": 2.996,
                    "basaliob": 0.944,
                    "bolussnooze": 0.672,
                    "activity": 0.0273
                },
                "suggested": {
                    "bg": 218,
                    "eventualBG": 92,
                    "minPredBG": 85,
                    "COB": 25,
                    "IOB": 2.996,
                    "rate": 1.1,
                    "duration": 30,
                    "sensitivityRatio": 0.95,
                    "predBGs": {
                        "IOB": [218, 210, 200, 185, 170, 155, 140, 125, 110, 100, 95, 92],
                        "COB": [218, 215, 210, 200, 185, 165, 145, 125, 105, 95],
                        "UAM": [218, 212, 205, 195, 180, 160, 140, 120, 100, 90],
                        "ZT": [218, 200, 180, 160, 140, 120, 100, 88, 82]
                    }
                },
                "enacted": {
                    "received": true,
                    "rate": 1.1,
                    "duration": 30
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // System detection
        #expect(status.detectedSystem == .aaps)
        
        // UnifiedStatus extraction
        let unified = status.unifiedStatus
        #expect(unified.system == .aaps)
        #expect(unified.iob == 2.996)
        #expect(unified.basalIOB == 0.944)
        #expect(unified.cob == 25)
        #expect(unified.enactedRate == 1.1)
        #expect(unified.enactedDuration == 30)
        #expect(unified.eventualBG == 92)
        
        // AAPS-specific: predBGs available
        #expect(unified.predBGs != nil)
        #expect(unified.predBGs?.iob?.count == 12)
        #expect(unified.predBGs?.cob?.count == 10)
        #expect(unified.predBGs?.uam?.count == 10)
        #expect(unified.predBGs?.zt?.count == 9)
    }
    
    @Test("AAPS sensitivityRatio extraction")
    func aapsSensitivityRatio() throws {
        // AAPS uses Autosens which provides sensitivityRatio
        let json = """
        {
            "device": "AndroidAPS",
            "created_at": "2026-02-19T12:00:00Z",
            "openaps": {
                "iob": {"iob": 1.5},
                "suggested": {
                    "bg": 150,
                    "sensitivityRatio": 0.85,
                    "eventualBG": 100
                }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.openaps?.suggested?.sensitivityRatio == 0.85)
        #expect(status.unifiedStatus.eventualBG == 100)
    }
    
    @Test("AAPS uploader nested in uploader object")
    func aapsUploaderBattery() throws {
        // AAPS may put uploader battery in nested object
        let json = """
        {
            "device": "AndroidAPS",
            "created_at": "2026-02-19T12:00:00Z",
            "uploader": {"battery": 85},
            "openaps": {"iob": {"iob": 1.5}}
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.uploader?.battery == 85)
    }
    
    // MARK: - NS-MS-022: Trio Comparison
    
    @Test("Parse Trio deviceStatus fixture")
    func parseTrioFixture() throws {
        // Trio format with recommendedBolus and IOB breakdown
        let json = """
        {
            "device": "Trio",
            "created_at": "2026-02-19T12:00:00.000Z",
            "openaps": {
                "iob": {
                    "iob": 2.15,
                    "basaliob": 0.85,
                    "bolusiob": 1.30,
                    "netbasalinsulin": 0.75,
                    "iobWithZeroTemp": 1.85
                },
                "suggested": {
                    "timestamp": "2026-02-19T12:00:00Z",
                    "reason": "COB: 25g, Dev: -15, BGI: -3.2",
                    "IOB": 2.15,
                    "COB": 25,
                    "eventualBG": 110,
                    "predBGs": {
                        "IOB": [145, 140, 135, 130, 125, 120, 115, 110],
                        "COB": [145, 148, 150, 148, 145, 140, 135, 130],
                        "UAM": [145, 142, 138, 132, 125, 118, 112, 108],
                        "ZT": [145, 138, 130, 122, 115, 110, 108, 106]
                    }
                },
                "enacted": {
                    "rate": 1.5,
                    "duration": 30,
                    "received": true
                },
                "recommendedBolus": 0.5,
                "version": "0.4.1"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // System detection - Trio uses "Trio" device string
        #expect(status.detectedSystem == .trio)
        
        // UnifiedStatus extraction
        let unified = status.unifiedStatus
        #expect(unified.system == .trio)
        #expect(unified.iob == 2.15)
        #expect(unified.basalIOB == 0.85)
        #expect(unified.cob == 25)
        #expect(unified.enactedRate == 1.5)
        #expect(unified.enactedDuration == 30)
        #expect(unified.eventualBG == 110)
        
        // Trio-specific fields - recommendedBolus/version not in current model
        // These fields exist in Trio uploads but we verify the core data extraction
        #expect(status.openaps?.iob?.basaliob == 0.85)
        #expect(status.openaps?.iob?.iob == 2.15)
    }
    
    @Test("Trio reason string parsing")
    func trioReasonParsing() throws {
        let json = """
        {
            "device": "Trio",
            "created_at": "2026-02-19T12:00:00Z",
            "openaps": {
                "iob": {"iob": 1.0},
                "enacted": {
                    "reason": "COB: 20g, Dev: -10, BGI: -2.5, ISF: 50, CR: 10, Target: 100, minPredBG 92, IOB: 1.0",
                    "rate": 0.8,
                    "duration": 30
                }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.unifiedStatus.reason?.contains("COB: 20g") == true)
        #expect(status.unifiedStatus.reason?.contains("ISF: 50") == true)
    }
    
    // MARK: - NS-MS-022b: oref0 Comparison
    
    @Test("Parse oref0 deviceStatus fixture")
    func parseOref0Fixture() throws {
        // oref0 format with hostname-based device string
        let json = """
        {
            "device": "openaps://edison",
            "created_at": "2026-02-19T12:00:00.000Z",
            "openaps": {
                "iob": {
                    "iob": 1.85,
                    "activity": 0.018,
                    "basaliob": 0.65,
                    "timestamp": "2026-02-19T12:00:00Z"
                },
                "suggested": {
                    "bg": 145,
                    "temp": "absolute",
                    "rate": 1.2,
                    "duration": 30,
                    "reason": "Eventual BG 92, Delta -3, minPredBG 85",
                    "eventualBG": 92,
                    "minPredBG": 85,
                    "COB": 15,
                    "IOB": 1.85,
                    "predBGs": {
                        "IOB": [145, 140, 135, 130, 125, 120, 115, 110, 105, 100, 95, 92],
                        "COB": [145, 148, 150, 147, 142, 135, 125, 115, 105, 95, 90],
                        "UAM": [145, 142, 138, 132, 125, 115, 105, 95, 88],
                        "ZT": [145, 135, 125, 115, 105, 95, 88, 85]
                    },
                    "mills": 1771495200000
                },
                "enacted": {
                    "bg": 145,
                    "rate": 1.2,
                    "duration": 30,
                    "received": true,
                    "mills": 1771495202000
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // System detection - openaps://hostname pattern
        #expect(status.detectedSystem == .openaps)
        
        // UnifiedStatus extraction
        let unified = status.unifiedStatus
        #expect(unified.system == .openaps)
        #expect(unified.iob == 1.85)
        #expect(unified.basalIOB == 0.65)
        #expect(unified.cob == 15)
        #expect(unified.enactedRate == 1.2)
        #expect(unified.eventualBG == 92)
        
        // oref0-specific: temp type field
        #expect(status.openaps?.suggested?.temp == "absolute")
        
        // oref0-specific: minPredBG
        #expect(status.openaps?.suggested?.minPredBG == 85)
    }
    
    // MARK: - NS-MS-023: Cross-System Unified Comparison
    
    @Test("All systems produce compatible UnifiedAlgorithmStatus")
    func crossSystemUnifiedStatus() throws {
        // Create fixtures for each system
        let systems: [(String, AIDSystem, Double, Double, Double)] = [
            // (json, expectedSystem, expectedIOB, expectedCOB, expectedRate)
            ("""
            {"device": "loop://iPhone", "created_at": "2026-02-19T12:00:00Z",
             "loop": {"iob": {"iob": 2.5}, "cob": {"cob": 20}, "enacted": {"rate": 1.0, "duration": 30}}}
            """, .loop, 2.5, 20, 1.0),
            
            ("""
            {"device": "AndroidAPS", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"iob": {"iob": 2.5}, "suggested": {"COB": 20}, "enacted": {"rate": 1.0, "duration": 30}}}
            """, .aaps, 2.5, 20, 1.0),
            
            ("""
            {"device": "Trio", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"iob": {"iob": 2.5}, "suggested": {"COB": 20}, "enacted": {"rate": 1.0, "duration": 30}}}
            """, .trio, 2.5, 20, 1.0),
            
            ("""
            {"device": "openaps://edison", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"iob": {"iob": 2.5}, "suggested": {"COB": 20}, "enacted": {"rate": 1.0, "duration": 30}}}
            """, .openaps, 2.5, 20, 1.0),
        ]
        
        for (json, expectedSystem, expectedIOB, expectedCOB, expectedRate) in systems {
            let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
            let unified = status.unifiedStatus
            
            #expect(unified.system == expectedSystem, "System detection failed for \(expectedSystem)")
            #expect(unified.iob == expectedIOB, "IOB extraction failed for \(expectedSystem)")
            #expect(unified.cob == expectedCOB, "COB extraction failed for \(expectedSystem)")
            #expect(unified.enactedRate == expectedRate, "Enacted rate extraction failed for \(expectedSystem)")
        }
    }
    
    @Test("predBGs structure differs between Loop and OpenAPS systems")
    func predBGsStructureDifference() throws {
        // Loop uses single array in loop.predicted.values
        let loopJSON = """
        {"device": "loop://iPhone", "created_at": "2026-02-19T12:00:00Z",
         "loop": {"predicted": {"startDate": "2026-02-19T12:00:00Z", "values": [150, 145, 140, 135, 130]}}}
        """
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopJSON.data(using: .utf8)!)
        let loopUnified = loopStatus.unifiedStatus
        
        // Loop: predictions from single array, no predBGs
        #expect(loopUnified.predictions?.count == 5)
        #expect(loopUnified.predBGs == nil)
        
        // OpenAPS uses 4 separate curves in openaps.suggested.predBGs
        let openapsJSON = """
        {"device": "openaps://rig", "created_at": "2026-02-19T12:00:00Z",
         "openaps": {"suggested": {"predBGs": {
           "IOB": [150, 145, 140], "COB": [150, 148, 146], "UAM": [150, 147, 144], "ZT": [150, 142, 135]
         }}}}
        """
        let openapsStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: openapsJSON.data(using: .utf8)!)
        let openapsUnified = openapsStatus.unifiedStatus
        
        // OpenAPS: predBGs available with 4 curves
        #expect(openapsUnified.predBGs != nil)
        #expect(openapsUnified.predBGs?.iob?.count == 3)
        #expect(openapsUnified.predBGs?.cob?.count == 3)
        #expect(openapsUnified.predBGs?.uam?.count == 3)
        #expect(openapsUnified.predBGs?.zt?.count == 3)
        
        // OpenAPS: predictions comes from primary curve (IOB)
        #expect(openapsUnified.predictions?.count == 3)
    }
    
    @Test("Extract enacted from different systems")
    func extractEnactedComparison() throws {
        // Test that enacted extraction works uniformly across systems
        let fixtures: [(String, Double?, Int?, Bool?)] = [
            // Loop enacted
            ("""
            {"device": "loop://iPhone", "created_at": "2026-02-19T12:00:00Z",
             "loop": {"enacted": {"rate": 1.5, "duration": 30, "received": true}}}
            """, 1.5, 30, true),
            
            // AAPS enacted (minimal)
            ("""
            {"device": "AndroidAPS", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"enacted": {"rate": 0.8, "duration": 30, "received": true}}}
            """, 0.8, 30, true),
            
            // Trio enacted
            ("""
            {"device": "Trio", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"enacted": {"rate": 1.2, "duration": 30}}}
            """, 1.2, 30, nil),  // received may be missing in Trio
            
            // oref0 enacted
            ("""
            {"device": "openaps://edison", "created_at": "2026-02-19T12:00:00Z",
             "openaps": {"enacted": {"rate": 0.5, "duration": 30, "received": true}}}
            """, 0.5, 30, true),
        ]
        
        for (json, expectedRate, expectedDuration, expectedReceived) in fixtures {
            let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
            let unified = status.unifiedStatus
            
            #expect(unified.enactedRate == expectedRate)
            #expect(unified.enactedDuration == expectedDuration)
            if let expected = expectedReceived {
                #expect(unified.enactedReceived == expected)
            }
        }
    }
    
    // MARK: - Algorithm Difference Documentation (NS-MS-023)
    
    @Test("Document SMB availability by system")
    func documentSMBAvailability() {
        // Document which systems support SMB (Super Micro Bolus)
        // This is informational - SMB presence varies by configuration
        
        let smbCapability: [AIDSystem: Bool] = [
            .loop: true,    // Loop supports SMB via automaticBolus strategy
            .aaps: true,    // AAPS supports SMB via OpenAPS SMB
            .trio: true,    // Trio (based on oref1) supports SMB
            .openaps: true, // OpenAPS oref1 supports SMB
            .freeaps: true, // FreeAPS X supported SMB
            .unknown: false,
        ]
        
        // Just verify our understanding is encoded
        #expect(smbCapability[.loop] == true)
        #expect(smbCapability[.aaps] == true)
        #expect(smbCapability[.trio] == true)
    }
    
    @Test("Document prediction curve availability")
    func documentPredictionCurves() {
        // Loop provides single prediction array
        // OpenAPS-based systems provide 4 curves: IOB, COB, UAM, ZT
        
        let predCurves: [AIDSystem: [String]] = [
            .loop: ["predicted"],  // Single array
            .aaps: ["IOB", "COB", "UAM", "ZT"],
            .trio: ["IOB", "COB", "UAM", "ZT"],
            .openaps: ["IOB", "COB", "UAM", "ZT"],
            .freeaps: ["IOB", "COB", "UAM", "ZT"],
            .unknown: [],
        ]
        
        #expect(predCurves[.loop]?.count == 1)
        #expect(predCurves[.aaps]?.count == 4)
    }
}

// Test helper
private enum TestError: Error, CustomStringConvertible {
    case message(String)
    
    init(_ message: String) { self = .message(message) }
    
    var description: String {
        switch self { case .message(let msg): return msg }
    }
}
