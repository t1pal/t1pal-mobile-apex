// SPDX-License-Identifier: MIT
// ConnectionModeRecommenderTests.swift
// CGMKit Tests
//
// Tests for CGM connection mode recommendation logic.
// Trace: CGM-027, REQ-CGM-009

import Testing
@testable import CGMKit
@testable import BLEKit
@testable import T1PalCompatKit

@Suite("Connection Mode Recommender")
struct ConnectionModeRecommenderTests {
    
    // MARK: - Dexcom G6 Recommendations
    
    @Test("G6 with no vendor app recommends direct")
    func g6NoVendorRecommendsDirect() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .dexcomG6, with: emptyDetection)
        
        #expect(result.primary.mode == .direct)
        #expect(result.primary.isStrong == false)
        #expect(result.vendorDetected == false)
    }
    
    @Test("G6 with Dexcom app recommends passive BLE")
    func g6WithDexcomAppRecommendsPassive() async {
        let recommender = ConnectionModeRecommender()
        let dexcomG6App = KnownCGMApp(
            id: "dexcom-g6",
            name: "Dexcom G6",
            bundleId: "com.dexcom.G6",
            urlScheme: "dexcomg6",
            conflictRisk: .high,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [dexcomG6App])
        
        let result = await recommender.recommend(for: .dexcomG6, with: detection)
        
        #expect(result.primary.mode == .passiveBLE)
        #expect(result.primary.isStrong == true)
        #expect(result.primary.warning != nil)
        #expect(result.vendorDetected == true)
    }
    
    // MARK: - Dexcom G7 Recommendations
    
    @Test("G7 with no vendor app recommends direct")
    func g7NoVendorRecommendsDirect() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .dexcomG7, with: emptyDetection)
        
        #expect(result.primary.mode == .direct)
    }
    
    @Test("G7 with Dexcom G7 app recommends passive BLE")
    func g7WithDexcomAppRecommendsPassive() async {
        let recommender = ConnectionModeRecommender()
        let dexcomG7App = KnownCGMApp(
            id: "dexcom-g7",
            name: "Dexcom G7",
            bundleId: "com.dexcom.G7",
            urlScheme: "dexcomg7",
            conflictRisk: .high,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [dexcomG7App])
        
        let result = await recommender.recommend(for: .dexcomG7, with: detection)
        
        #expect(result.primary.mode == .passiveBLE)
        #expect(result.primary.isStrong == true)
    }
    
    // MARK: - Libre Recommendations
    
    @Test("Libre 3 always recommends HealthKit")
    func libre3RecommendsHealthKit() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .libre3, with: emptyDetection)
        
        #expect(result.primary.mode == .healthKitObserver)
        #expect(result.primary.isStrong == true)
        #expect(result.primary.reason.contains("encrypted"))
    }
    
    @Test("Libre 2 with LibreLink recommends HealthKit")
    func libre2WithLibreLinkRecommendsHealthKit() async {
        let recommender = ConnectionModeRecommender()
        let libreLinkApp = KnownCGMApp(
            id: "libre-link",
            name: "LibreLink",
            bundleId: "com.abbott.librelink",
            urlScheme: nil,
            conflictRisk: .medium,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [libreLinkApp])
        
        let result = await recommender.recommend(for: .libre2, with: detection)
        
        #expect(result.primary.mode == .healthKitObserver)
        #expect(result.primary.isStrong == true)
    }
    
    @Test("Libre 2 alone recommends direct")
    func libre2AloneRecommendsDirect() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .libre2, with: emptyDetection)
        
        #expect(result.primary.mode == .direct)
    }
    
    // MARK: - Third-Party Transmitters
    
    @Test("MiaoMiao with no conflicts recommends direct")
    func miaomiaoAloneRecommendsDirect() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .miaomiao, with: emptyDetection)
        
        #expect(result.primary.mode == .direct)
    }
    
    @Test("MiaoMiao with xDrip recommends passive")
    func miaomiaoWithXdripRecommendsPassive() async {
        let recommender = ConnectionModeRecommender()
        let xdripApp = KnownCGMApp(
            id: "xdrip",
            name: "xDrip4iOS",
            bundleId: "com.xdrip4ios.xdrip4ios",
            urlScheme: "xdrip4ios",
            conflictRisk: .high,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [xdripApp])
        
        let result = await recommender.recommend(for: .miaomiao, with: detection)
        
        #expect(result.primary.mode == .passiveBLE)
        #expect(result.primary.isStrong == true)
    }
    
    // MARK: - AID Conflict Detection
    
    @Test("AID app detected sets hasAIDConflict flag")
    func aidConflictDetected() async {
        let recommender = ConnectionModeRecommender()
        let loopApp = KnownAIDApp(
            id: "loop",
            name: "Loop",
            bundleId: "com.loopkit.Loop",
            urlScheme: "loop",
            conflictRisk: .critical,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(
            detectedCGMApps: [],
            detectedAIDApps: [loopApp]
        )
        
        let result = await recommender.recommend(for: .dexcomG6, with: detection)
        
        #expect(result.hasAIDConflict == true)
        #expect(result.detectedAIDApps.count == 1)
    }
    
    // MARK: - Alternatives
    
    @Test("Recommendations include alternatives")
    func recommendationIncludesAlternatives() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .dexcomG6, with: emptyDetection)
        
        #expect(!result.primary.alternatives.isEmpty)
    }
    
    // MARK: - CGM-MODE-WIRE-001: Coexistence Alternatives
    
    @Test("G6 direct mode includes coexistence as alternative")
    func g6DirectIncludesCoexistenceAlternative() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .dexcomG6, with: emptyDetection)
        
        #expect(result.primary.mode == .direct)
        #expect(result.primary.alternatives.contains(.coexistence))
    }
    
    @Test("G7 with vendor app includes coexistence as alternative")
    func g7WithVendorIncludesCoexistenceAlternative() async {
        let recommender = ConnectionModeRecommender()
        let dexcomG7App = KnownCGMApp(
            id: "dexcom-g7",
            name: "Dexcom G7",
            bundleId: "com.dexcom.G7",
            urlScheme: "dexcomg7",
            conflictRisk: .high,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [dexcomG7App])
        
        let result = await recommender.recommend(for: .dexcomG7, with: detection)
        
        #expect(result.primary.mode == .passiveBLE)
        #expect(result.primary.alternatives.contains(.coexistence))
        // Coexistence should be first alternative for G7 (vendor handles auth)
        #expect(result.primary.alternatives.first == .coexistence)
    }
    
    @Test("G6 with vendor app includes coexistence as alternative")
    func g6WithVendorIncludesCoexistenceAlternative() async {
        let recommender = ConnectionModeRecommender()
        let dexcomG6App = KnownCGMApp(
            id: "dexcom-g6",
            name: "Dexcom G6",
            bundleId: "com.dexcom.G6",
            urlScheme: "dexcomg6",
            conflictRisk: .high,
            guidance: "Test guidance"
        )
        let detection = AppDetectionResult(detectedCGMApps: [dexcomG6App])
        
        let result = await recommender.recommend(for: .dexcomG6, with: detection)
        
        #expect(result.primary.mode == .passiveBLE)
        #expect(result.primary.alternatives.contains(.coexistence))
    }
    
    // MARK: - Unknown Device
    
    @Test("Unknown device defaults to HealthKit")
    func unknownDeviceDefaultsToHealthKit() async {
        let recommender = ConnectionModeRecommender()
        let emptyDetection = AppDetectionResult()
        
        let result = await recommender.recommend(for: .unknown, with: emptyDetection)
        
        #expect(result.primary.mode == .healthKitObserver)
    }
}
