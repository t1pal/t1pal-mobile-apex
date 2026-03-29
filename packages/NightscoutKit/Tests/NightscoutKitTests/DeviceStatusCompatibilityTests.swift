// DeviceStatusCompatibilityTests.swift - Test devicestatus endpoint compatibility
// Part of NightscoutKitTests
// Trace: NS-COMPAT-005

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

// MARK: - Device Status Fixture Data

/// Real devicestatus data fixtures from various AID systems
enum DeviceStatusFixtures {
    
    /// Loop devicestatus with predictions
    static let loopDeviceStatusJSON = """
    {
        "device": "iPhone",
        "created_at": "2026-02-05T08:00:00.000Z",
        "loop": {
            "iob": {
                "iob": 2.45,
                "basaliob": 1.2
            },
            "cob": {
                "cob": 25
            },
            "enacted": {
                "timestamp": "2026-02-05T07:59:30.000Z",
                "rate": 0.8,
                "duration": 30.0
            },
            "predicted": {
                "startDate": "2026-02-05T08:00:00.000Z",
                "values": [150, 155, 160, 162, 160, 155, 150, 145, 140, 135, 130, 125, 120]
            },
            "recommendedBolus": 0
        },
        "pump": {
            "reservoir": 125.5
        }
    }
    """
    
    /// Trio/OpenAPS devicestatus
    static let trioDeviceStatusJSON = """
    {
        "device": "Trio",
        "created_at": "2026-02-05T08:05:00.000Z",
        "openaps": {
            "suggested": {
                "timestamp": "2026-02-05T08:05:00.000Z",
                "bg": 145,
                "eventualBG": 120,
                "COB": 15,
                "IOB": 1.8,
                "rate": 0.6,
                "duration": 30.0
            },
            "enacted": {
                "timestamp": "2026-02-05T08:04:30.000Z",
                "rate": 0.6,
                "duration": 30.0
            },
            "iob": {
                "iob": 1.8,
                "basaliob": 0.9
            }
        },
        "pump": {
            "reservoir": 89.2
        }
    }
    """
}

// MARK: - Tests

@Suite("DeviceStatus Compatibility")
struct DeviceStatusCompatibilityTests {
    
    @Test("Parse Loop devicestatus")
    func parseLoopDeviceStatus() throws {
        let data = DeviceStatusFixtures.loopDeviceStatusJSON.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        #expect(status.device == "iPhone")
        
        // Loop-specific
        #expect(status.loop?.iob?.iob == 2.45)
        #expect(status.loop?.cob?.cob == 25)
        #expect(status.loop?.enacted?.rate == 0.8)
        #expect(status.loop?.predicted?.values?.count == 13)
    }
    
    @Test("Parse Trio devicestatus")
    func parseTrioDeviceStatus() throws {
        let data = DeviceStatusFixtures.trioDeviceStatusJSON.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        #expect(status.device == "Trio")
        
        // OpenAPS-specific
        #expect(status.openaps?.suggested?.bg == 145)
        #expect(status.openaps?.suggested?.eventualBG == 120)
        #expect(status.openaps?.suggested?.IOB == 1.8)
        #expect(status.openaps?.suggested?.COB == 15)
        #expect(status.openaps?.enacted?.rate == 0.6)
    }
    
    @Test("Extract IOB from different sources")
    func extractIOB() throws {
        // Loop format
        let loopData = DeviceStatusFixtures.loopDeviceStatusJSON.data(using: .utf8)!
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopData)
        let loopIOB = loopStatus.loop?.iob?.iob ?? loopStatus.openaps?.iob?.iob
        #expect(loopIOB == 2.45)
        
        // Trio format
        let trioData = DeviceStatusFixtures.trioDeviceStatusJSON.data(using: .utf8)!
        let trioStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: trioData)
        let trioIOB = trioStatus.loop?.iob?.iob ?? trioStatus.openaps?.iob?.iob
        #expect(trioIOB == 1.8)
    }
    
    @Test("Extract pump reservoir from different sources")
    func extractReservoir() throws {
        let loopData = DeviceStatusFixtures.loopDeviceStatusJSON.data(using: .utf8)!
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopData)
        #expect(loopStatus.pump?.reservoir == 125.5)
        
        let trioData = DeviceStatusFixtures.trioDeviceStatusJSON.data(using: .utf8)!
        let trioStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: trioData)
        #expect(trioStatus.pump?.reservoir == 89.2)
    }
    
    // MARK: - Algorithm Field Tests (ALG-AB-002)
    
    @Test("OpenAPSStatus includes algorithm field")
    func openAPSStatusIncludesAlgorithm() throws {
        // Create status with algorithm field
        let status = NightscoutDeviceStatus.OpenAPSStatus(
            iob: .init(iob: 1.5),
            suggested: nil,
            enacted: nil,
            reason: "Test",
            timestamp: "2026-02-05T08:00:00.000Z",
            algorithm: "oref1"
        )
        
        #expect(status.algorithm == "oref1")
    }
    
    @Test("OpenAPSStatus algorithm field is optional")
    func openAPSStatusAlgorithmOptional() throws {
        // Status without algorithm field (backwards compatible)
        let status = NightscoutDeviceStatus.OpenAPSStatus(
            iob: .init(iob: 2.0),
            reason: "Test without algorithm"
        )
        
        #expect(status.algorithm == nil)
    }
    
    @Test("Parse devicestatus with algorithm field")
    func parseDeviceStatusWithAlgorithm() throws {
        let json = """
        {
            "device": "T1Pal",
            "created_at": "2026-02-05T08:00:00.000Z",
            "openaps": {
                "iob": { "iob": 2.0 },
                "algorithm": "oref1",
                "reason": "A/B test group B"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        #expect(status.openaps?.algorithm == "oref1")
        #expect(status.openaps?.reason == "A/B test group B")
    }
    
    // NS-ALGO-010: Verify computed iob/cob properties work correctly
    @Test("Computed iob property returns Loop IOB")
    func computedIobPropertyLoop() throws {
        let data = DeviceStatusFixtures.loopDeviceStatusJSON.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // Use computed property (same as PredictionDivergenceView)
        #expect(status.iob == 2.45)
        #expect(status.cob == 25)
    }
    
    // NS-ALGO-010: Verify live T1Pal Loop devicestatus format
    @Test("Parse T1Pal Loop devicestatus from live capture")
    func parseT1PalLoopDeviceStatus() throws {
        // Real data captured from t1pal.com via NS-ALGO-001
        let json = """
        {
            "_id": "69961ca8eea0a072352697b3",
            "device": "loop://iPhone",
            "created_at": "2026-02-18T20:10:15.000Z",
            "mills": 1771445415000,
            "loop": {
                "timestamp": "2026-02-18T20:10:15Z",
                "iob": {
                    "iob": 1.5034077199057236,
                    "timestamp": "2026-02-18T20:15:00Z"
                },
                "cob": {
                    "cob": 0,
                    "timestamp": "2026-02-18T20:09:58Z"
                },
                "recommendedBolus": 0,
                "name": "T1Pal Loop",
                "version": "3.8.1.2026010900"
            },
            "pump": {
                "reservoir": 78.8,
                "battery": {"percent": 59}
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // Verify computed properties work (NS-ALGO-010 fix)
        #expect(status.iob != nil, "IOB should be extracted from deviceStatus")
        #expect(abs(status.iob! - 1.5034) < 0.001, "IOB should match Loop value")
        #expect(status.cob == 0, "COB should be 0")
        
        // Verify device identification
        #expect(status.device.contains("loop"))
        #expect(status.isLoopStatus)
        #expect(!status.isOpenAPSStatus)
    }
    
    // NS-ALGO-000: Parse live fixture with automaticDoseRecommendation
    @Test("Parse live fixture with automaticDoseRecommendation and decimal predicted values")
    func parseLiveFixtureWithAutomaticDoseRecommendation() throws {
        // This fixture contains:
        // - name field (new in recent Loop versions)
        // - automaticDoseRecommendation with tempBasalAdjustment
        // - predicted.values as decimals (not integers)
        let json = """
        {
            "_id": "6996298deea0a0b2062697be",
            "device": "loop://iPhone",
            "created_at": "2026-02-18T21:05:16.000Z",
            "mills": 1771448716000,
            "loop": {
                "enacted": {
                    "duration": 30,
                    "bolusVolume": 0,
                    "timestamp": "2026-02-18T21:05:14Z",
                    "received": true,
                    "rate": 1.15
                },
                "name": "T1Pal Loop",
                "version": "3.8.1.2026010900",
                "predicted": {
                    "startDate": "2026-02-18T21:04:29Z",
                    "values": [129, 128.75, 126.15, 122.75]
                },
                "iob": {
                    "iob": 0.549347848557205,
                    "timestamp": "2026-02-18T21:05:00Z"
                },
                "cob": {
                    "timestamp": "2026-02-18T21:05:01Z",
                    "cob": 0
                },
                "recommendedBolus": 0,
                "timestamp": "2026-02-18T21:05:16Z",
                "automaticDoseRecommendation": {
                    "tempBasalAdjustment": {
                        "duration": 30,
                        "rate": 1.1
                    },
                    "timestamp": "2026-02-18T21:05:16Z",
                    "bolusVolume": 0
                }
            },
            "pump": {
                "reservoir": 77.7,
                "battery": {"percent": 59}
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // NS-ALGO-000d: Verify IOB is extracted correctly (not 0.0)
        #expect(status.iob != nil, "IOB should be extracted")
        #expect(abs(status.iob! - 0.549) < 0.001, "IOB should be ~0.549, not 0.0")
        
        // NS-ALGO-000b: Verify new fields are parsed
        #expect(status.loop?.name == "T1Pal Loop")
        #expect(status.loop?.automaticDoseRecommendation != nil)
        #expect(status.loop?.automaticDoseRecommendation?.tempBasalAdjustment?.rate == 1.1)
        #expect(status.loop?.automaticDoseRecommendation?.tempBasalAdjustment?.duration == 30)
        
        // Verify predicted values as decimals work
        #expect(status.loop?.predicted?.values?.count == 4)
        #expect(status.loop?.predicted?.values?[1] == 128.75, "Decimal predicted values should parse")
        
        // Verify enacted data
        #expect(status.loop?.enacted?.rate == 1.15)
        #expect(status.loop?.enacted?.duration == 30)
    }
    
    // NS-ALGO-000: Load and parse the actual live fixture file
    @Test("Parse fixture_devicestatus_loop_live.json file")
    func parseFixtureFile() throws {
        // NS-ALGO-000: Load from actual fixture file (not inline JSON)
        // This ensures the real captured data parses correctly
        guard let fixtureURL = Bundle.module.url(
            forResource: "fixture_devicestatus_loop_live",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw TestError("fixture_devicestatus_loop_live.json not found in test bundle")
        }
        
        let data = try Data(contentsOf: fixtureURL)
        let statuses = try JSONDecoder().decode([NightscoutDeviceStatus].self, from: data)
        
        #expect(statuses.count == 1, "Fixture should contain 1 deviceStatus")
        
        let status = statuses[0]
        
        // NS-ALGO-000d: Verify IOB correctly extracted from live capture
        #expect(status.iob != nil, "IOB should be extracted from real capture")
        #expect(abs(status.iob! - 0.549) < 0.001, "IOB should match captured value ~0.549")
        
        // Verify pump data
        #expect(status.pump?.reservoir == 77.7)
        
        // Verify all Loop fields parse
        #expect(status.loop?.name == "T1Pal Loop")
        #expect(status.loop?.version == "3.8.1.2026010900")
        #expect(status.loop?.automaticDoseRecommendation != nil)
        #expect(status.loop?.predicted?.values?.count == 83, "Should have 83 predicted values")
    }
    
    // NS-ALGO-003: Test OpenAPS deviceStatus format parsing
    @Test("Parse OpenAPS deviceStatus with predBGs curves")
    func parseOpenAPSDeviceStatus() throws {
        let json = """
        {
          "device": "openaps://phone-AAPS",
          "created_at": "2026-02-18T21:05:00.000Z",
          "mills": 1771538700000,
          "openaps": {
            "iob": {
              "iob": 2.996,
              "basaliob": 0.944,
              "bolussnooze": 0.672,
              "activity": 0.0273,
              "timestamp": "2026-02-18T21:05:00Z"
            },
            "suggested": {
              "bg": 218,
              "temp": "absolute",
              "rate": 1.1,
              "duration": 30,
              "reason": "Eventual BG 92 < 106",
              "eventualBG": 92,
              "snoozeBG": 137,
              "minPredBG": 85,
              "predBGs": {
                "IOB": [218, 210, 195, 175, 155, 135, 120, 108, 100, 95, 92],
                "COB": [218, 215, 210, 200, 185, 165, 145, 125, 110, 100, 95],
                "UAM": [218, 212, 200, 185, 165, 145, 125, 110, 100, 95, 90],
                "ZT": [218, 208, 192, 170, 148, 128, 112, 100, 92, 87, 85]
              },
              "COB": 25,
              "IOB": 2.996,
              "sensitivityRatio": 1.0,
              "timestamp": "2026-02-18T21:05:00Z"
            },
            "enacted": {
              "bg": 218,
              "temp": "absolute",
              "rate": 1.1,
              "duration": 30,
              "reason": "Eventual BG 92 < 106",
              "received": true,
              "timestamp": "2026-02-18T21:05:01Z"
            },
            "reason": "COB: 25, Dev: 0, BGI: -2.1",
            "timestamp": "2026-02-18T21:05:00Z"
          },
          "pump": { "reservoir": 85.5 }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: data)
        
        // Verify OpenAPS structure
        #expect(status.openaps != nil)
        #expect(status.loop == nil)
        
        // IOB extraction (via computed property)
        #expect(status.iob == 2.996)
        
        // OpenAPS-specific: basaliob
        #expect(status.openaps?.iob?.basaliob == 0.944)
        #expect(status.openaps?.iob?.bolussnooze == 0.672)
        #expect(status.openaps?.iob?.activity == 0.0273)
        
        // COB from suggested (different location than Loop)
        #expect(status.cob == 25)
        #expect(status.openaps?.suggested?.COB == 25)
        
        // predBGs - 4 separate curves
        let predBGs = status.openaps?.suggested?.predBGs
        #expect(predBGs?.IOB?.count == 11)
        #expect(predBGs?.COB?.count == 11)
        #expect(predBGs?.UAM?.count == 11)
        #expect(predBGs?.ZT?.count == 11)
        #expect(predBGs?.IOB?.first == 218)
        #expect(predBGs?.ZT?.last == 85)
        
        // Enacted
        #expect(status.openaps?.enacted?.rate == 1.1)
        #expect(status.openaps?.enacted?.duration == 30)
        #expect(status.openaps?.enacted?.received == true)
        
        // Suggested extras
        #expect(status.openaps?.suggested?.eventualBG == 92)
        #expect(status.openaps?.suggested?.snoozeBG == 137)
        #expect(status.openaps?.suggested?.minPredBG == 85)
        #expect(status.openaps?.suggested?.sensitivityRatio == 1.0)
    }
    
    // NS-MS-002: Test AID system detection from device field
    @Test("Detect Loop from device string")
    func detectLoopSystem() {
        #expect(AIDSystem.detect(from: "loop://iPhone") == .loop)
        #expect(AIDSystem.detect(from: "Loop") == .loop)
        #expect(AIDSystem.detect(from: "loop://iPhone12,1") == .loop)
    }
    
    @Test("Detect AndroidAPS from device string")
    func detectAAPSSystem() {
        #expect(AIDSystem.detect(from: "openaps://phone-AAPS") == .aaps)
        #expect(AIDSystem.detect(from: "AndroidAPS") == .aaps)
        #expect(AIDSystem.detect(from: "AAPS 3.2.0") == .aaps)
    }
    
    @Test("Detect Trio from device string")
    func detectTrioSystem() {
        #expect(AIDSystem.detect(from: "Trio") == .trio)
        #expect(AIDSystem.detect(from: "trio://iPhone") == .trio)
    }
    
    @Test("Detect OpenAPS from device string")
    func detectOpenAPSSystem() {
        #expect(AIDSystem.detect(from: "openaps://edison") == .openaps)
        #expect(AIDSystem.detect(from: "OpenAPS") == .openaps)
    }
    
    @Test("Unknown system detection")
    func detectUnknownSystem() {
        #expect(AIDSystem.detect(from: nil) == .unknown)
        #expect(AIDSystem.detect(from: "") == .unknown)
        #expect(AIDSystem.detect(from: "xDrip+") == .unknown)
    }
    
    @Test("AIDSystem usesOpenAPSFormat property")
    func aidSystemFormat() {
        #expect(AIDSystem.loop.usesOpenAPSFormat == false)
        #expect(AIDSystem.aaps.usesOpenAPSFormat == true)
        #expect(AIDSystem.trio.usesOpenAPSFormat == true)
        #expect(AIDSystem.openaps.usesOpenAPSFormat == true)
    }
    
    @Test("deviceStatus detectedSystem property")
    func deviceStatusDetectedSystem() throws {
        // Loop status
        let loopJSON = """
        {"device": "loop://iPhone", "created_at": "2026-02-18T21:00:00Z", "loop": {"iob": {"iob": 1.5}}}
        """
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopJSON.data(using: .utf8)!)
        #expect(loopStatus.detectedSystem == .loop)
        
        // AAPS status
        let aapsJSON = """
        {"device": "AndroidAPS", "created_at": "2026-02-18T21:00:00Z", "openaps": {"iob": {"iob": 2.0}}}
        """
        let aapsStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: aapsJSON.data(using: .utf8)!)
        #expect(aapsStatus.detectedSystem == .aaps)
    }
    
    // NS-MS-010: Test UnifiedAlgorithmStatus extraction from Loop
    @Test("Extract unified status from Loop deviceStatus")
    func unifiedStatusFromLoop() throws {
        let json = """
        {
            "device": "loop://iPhone",
            "created_at": "2026-02-18T21:05:00Z",
            "mills": 1771538700000,
            "loop": {
                "iob": {"iob": 2.5, "timestamp": "2026-02-18T21:05:00Z"},
                "cob": {"cob": 25, "timestamp": "2026-02-18T21:05:00Z"},
                "enacted": {
                    "rate": 1.2,
                    "duration": 30,
                    "bolusVolume": 0.1,
                    "received": true,
                    "timestamp": "2026-02-18T21:05:00Z"
                },
                "predicted": {
                    "startDate": "2026-02-18T21:05:00Z",
                    "values": [150, 145, 140, 135, 130]
                }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        let unified = status.unifiedStatus
        
        #expect(unified.system == .loop)
        #expect(unified.iob == 2.5)
        #expect(unified.cob == 25)
        #expect(unified.enactedRate == 1.2)
        #expect(unified.enactedDuration == 30)
        #expect(unified.enactedBolus == 0.1)
        #expect(unified.enactedReceived == true)
        #expect(unified.predictions?.count == 5)
        #expect(unified.predictions?.first == 150)
        #expect(unified.predBGs == nil)  // Loop uses single array
    }
    
    // NS-MS-010: Test UnifiedAlgorithmStatus extraction from OpenAPS
    @Test("Extract unified status from OpenAPS deviceStatus")
    func unifiedStatusFromOpenAPS() throws {
        let json = """
        {
            "device": "AndroidAPS",
            "created_at": "2026-02-18T21:05:00Z",
            "mills": 1771538700000,
            "openaps": {
                "iob": {"iob": 3.0, "basaliob": 1.2},
                "suggested": {
                    "bg": 180,
                    "eventualBG": 120,
                    "COB": 30,
                    "reason": "COB: 30, Dev: 0",
                    "predBGs": {
                        "IOB": [180, 170, 160, 150, 140],
                        "COB": [180, 175, 170, 165, 160],
                        "UAM": [180, 172, 165, 158, 150],
                        "ZT": [180, 168, 155, 142, 130]
                    }
                },
                "enacted": {
                    "rate": 0.8,
                    "duration": 30,
                    "received": true,
                    "reason": "Lowering"
                }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        let unified = status.unifiedStatus
        
        #expect(unified.system == .aaps)
        #expect(unified.iob == 3.0)
        #expect(unified.basalIOB == 1.2)  // OpenAPS-specific
        #expect(unified.cob == 30)
        #expect(unified.enactedRate == 0.8)
        #expect(unified.enactedDuration == 30)
        #expect(unified.eventualBG == 120)
        #expect(unified.reason == "Lowering")
        
        // predBGs available
        #expect(unified.predBGs != nil)
        #expect(unified.predBGs?.iob?.count == 5)
        #expect(unified.predBGs?.cob?.count == 5)
        #expect(unified.predBGs?.uam?.count == 5)
        #expect(unified.predBGs?.zt?.count == 5)
        #expect(unified.predBGs?.primary?.first == 180)
        
        // predictions is primary curve as Double
        #expect(unified.predictions?.count == 5)
    }
    
    // NS-MS-010: Test unified status from empty deviceStatus
    @Test("Unified status from empty deviceStatus")
    func unifiedStatusEmpty() throws {
        let json = """
        {"device": "unknown", "created_at": "2026-02-18T21:00:00Z"}
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        let unified = status.unifiedStatus
        
        #expect(unified.system == .unknown)
        #expect(unified.iob == nil)
        #expect(unified.cob == nil)
        #expect(unified.predictions == nil)
    }
    
    // MARK: - Hybrid Setup Detection (NS-MS-003)
    
    @Test("CGMUploader detection from device string")
    func cgmUploaderDetection() {
        #expect(CGMUploader.detect(from: "xDrip-DexcomG6") == .xdrip)
        #expect(CGMUploader.detect(from: "xdrip4ios") == .xdrip)
        #expect(CGMUploader.detect(from: "Spike") == .spike)
        #expect(CGMUploader.detect(from: "Spike 3.0.1") == .spike)
        #expect(CGMUploader.detect(from: "Glimp") == .glimp)
        #expect(CGMUploader.detect(from: "Diabox") == .diabox)
        #expect(CGMUploader.detect(from: "Loop") == nil)  // AID, not CGM uploader
        #expect(CGMUploader.detect(from: "AndroidAPS") == nil)
        #expect(CGMUploader.detect(from: nil) == nil)
    }
    
    @Test("DeviceSetup from Loop deviceStatus")
    func deviceSetupLoop() throws {
        let json = """
        {
            "device": "loop://iPhone",
            "created_at": "2026-02-18T21:00:00Z",
            "loop": {"iob": {"iob": 2.5}},
            "uploader": {"name": "iPhone", "battery": 80}
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        let setup = status.deviceSetup
        
        #expect(setup.aidSystem == .loop)
        #expect(setup.cgmUploader == nil)
        #expect(setup.isHybrid == false)
        #expect(setup.uploaderName == "iPhone")
        #expect(setup.description == "Loop")
    }
    
    @Test("DeviceSetup from hybrid xDrip + AAPS")
    func deviceSetupHybrid() throws {
        // In a hybrid setup, xDrip uploads CGM data and has its own deviceStatus entries
        // The AID system (AAPS) has separate entries with loop/openaps data
        let xdripJSON = """
        {
            "device": "xDrip-DexcomG6",
            "created_at": "2026-02-18T21:00:00Z"
        }
        """
        
        let xdripStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: xdripJSON.data(using: .utf8)!)
        let xdripSetup = xdripStatus.deviceSetup
        
        #expect(xdripSetup.aidSystem == .unknown)  // xDrip isn't an AID
        #expect(xdripSetup.cgmUploader == .xdrip)
        #expect(xdripSetup.isHybrid == true)  // CGM uploader detected
        #expect(xdripSetup.description == "Unknown + xDrip+")
    }
    
    @Test("DeviceSetup uploader name extraction")
    func deviceSetupUploaderName() throws {
        let json = """
        {
            "device": "Trio",
            "created_at": "2026-02-18T21:00:00Z",
            "openaps": {"iob": {"iob": 1.5}},
            "uploader": {"name": "iPad Pro", "battery": 95}
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        let setup = status.deviceSetup
        
        #expect(setup.aidSystem == .trio)
        #expect(setup.cgmUploader == nil)
        #expect(setup.uploaderName == "iPad Pro")
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
