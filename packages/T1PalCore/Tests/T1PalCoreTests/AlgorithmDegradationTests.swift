/// Tests for AlgorithmDegradation
/// AID-PARTIAL-005 verification: Run if CGM exists, show limited predictions

import XCTest
@testable import T1PalCore

final class AlgorithmDegradationTests: XCTestCase {
    
    // MARK: - Core Principle Tests
    
    func testAlgorithmRunsWithCGMOnly() {
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .cgmOnly,
            cgmConnected: true,
            pumpConnected: false,
            insulinFreshness: nil
        )
        
        // CGM-only should work
        XCTAssertTrue(degradation.canShowGlucose, "Glucose must be available in CGM-only mode")
        XCTAssertEqual(degradation.level, .cgmOnly)
        XCTAssertEqual(degradation.reason, .userSelectedCGMOnly)
    }
    
    func testCGMDisconnectedIsOffline() {
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .closedLoop,
            cgmConnected: false,
            pumpConnected: true,
            insulinFreshness: nil
        )
        
        XCTAssertEqual(degradation.level, .offline)
        XCTAssertFalse(degradation.canShowGlucose)
        XCTAssertEqual(degradation.reason, .cgmDisconnected)
    }
    
    func testFullFunctionalityWhenAllConnected() {
        let freshInsulin = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-3600),  // 1 hour ago
            dia: .standard
        )
        
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .closedLoop,
            cgmConnected: true,
            pumpConnected: true,
            insulinFreshness: freshInsulin
        )
        
        XCTAssertEqual(degradation.level, .full)
        XCTAssertTrue(degradation.canShowPredictions)
        XCTAssertTrue(degradation.canShowIOB)
        XCTAssertTrue(degradation.canEnact)
        XCTAssertNil(degradation.reason)
    }
    
    // MARK: - Pump Disconnected Tests
    
    func testPumpDisconnectedDegrades() {
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .closedLoop,
            cgmConnected: true,
            pumpConnected: false,
            insulinFreshness: nil
        )
        
        // Should degrade to CGM-only since closedLoop requires pump
        XCTAssertEqual(degradation.level, .cgmOnly)
        XCTAssertEqual(degradation.reason, .pumpDisconnected)
        XCTAssertTrue(degradation.canShowGlucose)
        XCTAssertFalse(degradation.canShowPredictions)
        XCTAssertFalse(degradation.canEnact)
    }
    
    func testOpenLoopPumpDisconnectedDegrades() {
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .openLoop,
            cgmConnected: true,
            pumpConnected: false,
            insulinFreshness: nil
        )
        
        // openLoop requires pump too
        XCTAssertEqual(degradation.level, .cgmOnly)
        XCTAssertEqual(degradation.reason, .pumpDisconnected)
    }
    
    // MARK: - Stale Insulin Tests
    
    func testStaleInsulinShowsLimitedPredictions() {
        let staleInsulin = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-25200),  // 7 hours ago
            dia: .extended  // 6 hours
        )
        
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .closedLoop,
            cgmConnected: true,
            pumpConnected: true,
            insulinFreshness: staleInsulin
        )
        
        XCTAssertEqual(degradation.level, .limitedPredictions)
        XCTAssertEqual(degradation.reason, .insulinDataStale)
        XCTAssertTrue(degradation.canShowGlucose)
        XCTAssertFalse(degradation.canShowIOB, "IOB should not be shown when stale")
        XCTAssertTrue(degradation.canShowLimitedPredictions, "Limited predictions should be available")
        XCTAssertFalse(degradation.canShowPredictions, "Full predictions should not be available")
    }
    
    // MARK: - Capabilities Tests
    
    func testFullCapabilities() {
        let caps = AlgorithmDegradation.Capabilities.full
        
        XCTAssertTrue(caps.canShowGlucose)
        XCTAssertTrue(caps.canShowTrend)
        XCTAssertTrue(caps.canShowIOB)
        XCTAssertTrue(caps.canShowPredictions)
        XCTAssertTrue(caps.canShowLimitedPredictions)
        XCTAssertTrue(caps.canEnactTempBasal)
        XCTAssertTrue(caps.canDeliverSMB)
        XCTAssertTrue(caps.canUploadToNightscout)
    }
    
    func testCGMOnlyCapabilities() {
        let caps = AlgorithmDegradation.Capabilities.cgmOnly
        
        XCTAssertTrue(caps.canShowGlucose)
        XCTAssertTrue(caps.canShowTrend)
        XCTAssertFalse(caps.canShowIOB)
        XCTAssertFalse(caps.canShowPredictions)
        XCTAssertFalse(caps.canShowLimitedPredictions)
        XCTAssertFalse(caps.canEnactTempBasal)
        XCTAssertFalse(caps.canDeliverSMB)
        XCTAssertTrue(caps.canUploadToNightscout, "CGM always uploads")
    }
    
    func testLimitedPredictionsCapabilities() {
        let caps = AlgorithmDegradation.Capabilities.limitedPredictions
        
        XCTAssertTrue(caps.canShowGlucose)
        XCTAssertTrue(caps.canShowTrend)
        XCTAssertFalse(caps.canShowIOB, "IOB is stale")
        XCTAssertFalse(caps.canShowPredictions)
        XCTAssertTrue(caps.canShowLimitedPredictions, "Momentum predictions available")
        XCTAssertFalse(caps.canEnactTempBasal)
        XCTAssertFalse(caps.canDeliverSMB)
        XCTAssertTrue(caps.canUploadToNightscout)
    }
    
    func testOfflineCapabilities() {
        let caps = AlgorithmDegradation.Capabilities.offline
        
        XCTAssertFalse(caps.canShowGlucose)
        XCTAssertFalse(caps.canShowTrend)
        XCTAssertFalse(caps.canShowIOB)
        XCTAssertFalse(caps.canShowPredictions)
        XCTAssertFalse(caps.canUploadToNightscout)
    }
    
    // MARK: - NS Upload Always Available Tests
    
    func testCGMAlwaysUploadsToNS() {
        // All levels except offline should upload CGM
        let levels: [(AlgorithmDegradation.DegradationLevel, Bool)] = [
            (.full, true),
            (.limitedPredictions, true),
            (.cgmOnly, true),
            (.offline, false)
        ]
        
        for (level, expectedUpload) in levels {
            let caps: AlgorithmDegradation.Capabilities
            switch level {
            case .full: caps = .full
            case .limitedPredictions: caps = .limitedPredictions
            case .cgmOnly: caps = .cgmOnly
            case .offline: caps = .offline
            }
            
            XCTAssertEqual(
                caps.canUploadToNightscout,
                expectedUpload,
                "\(level) should \(expectedUpload ? "" : "not ")upload to NS"
            )
        }
    }
    
    // MARK: - LimitedPrediction Tests
    
    func testLimitedPredictionFromMomentum() {
        let prediction = LimitedPrediction.fromMomentum(
            currentGlucose: 120,
            trend: 2.0,  // +2 mg/dL per minute
            minutes: 30
        )
        
        XCTAssertEqual(prediction.currentGlucose, 120)
        XCTAssertEqual(prediction.trend, 2.0)
        XCTAssertFalse(prediction.momentumPrediction.isEmpty)
        XCTAssertTrue(prediction.limitation.contains("momentum"))
    }
    
    func testLimitedPredictionPointsClamped() {
        // Very high trend that would exceed 400
        let prediction = LimitedPrediction.fromMomentum(
            currentGlucose: 350,
            trend: 5.0,  // Very steep rise
            minutes: 30
        )
        
        // All points should be clamped to 400 max
        for point in prediction.momentumPrediction {
            XCTAssertLessThanOrEqual(point.value, 400)
            XCTAssertGreaterThanOrEqual(point.value, 40)
        }
    }
    
    func testLimitedPredictionNoTrend() {
        let prediction = LimitedPrediction.fromMomentum(
            currentGlucose: 120,
            trend: nil,
            minutes: 30
        )
        
        XCTAssertNil(prediction.trend)
        XCTAssertTrue(prediction.momentumPrediction.isEmpty, "No trend = no momentum prediction")
    }
    
    // MARK: - Degradation Level Tests
    
    func testDegradationLevelHasData() {
        XCTAssertTrue(AlgorithmDegradation.DegradationLevel.full.hasData)
        XCTAssertTrue(AlgorithmDegradation.DegradationLevel.limitedPredictions.hasData)
        XCTAssertTrue(AlgorithmDegradation.DegradationLevel.cgmOnly.hasData)
        XCTAssertFalse(AlgorithmDegradation.DegradationLevel.offline.hasData)
    }
    
    func testDegradationLevelHasPredictions() {
        XCTAssertTrue(AlgorithmDegradation.DegradationLevel.full.hasPredictions)
        XCTAssertFalse(AlgorithmDegradation.DegradationLevel.limitedPredictions.hasPredictions)
        XCTAssertFalse(AlgorithmDegradation.DegradationLevel.cgmOnly.hasPredictions)
        XCTAssertFalse(AlgorithmDegradation.DegradationLevel.offline.hasPredictions)
    }
    
    // MARK: - Element State Tests
    
    func testElementStateMapping() {
        XCTAssertEqual(
            AlgorithmDegradation.full().elementState,
            .normalCGM
        )
        
        XCTAssertEqual(
            AlgorithmDegradation.cgmOnly(reason: .pumpDisconnected).elementState,
            .warning
        )
        
        XCTAssertEqual(
            AlgorithmDegradation.offline().elementState,
            .critical
        )
    }
    
    // MARK: - Factory Methods Tests
    
    func testFullFactory() {
        let degradation = AlgorithmDegradation.full()
        
        XCTAssertEqual(degradation.level, .full)
        XCTAssertNil(degradation.reason)
    }
    
    func testCGMOnlyFactory() {
        let degradation = AlgorithmDegradation.cgmOnly(reason: .pumpDisconnected)
        
        XCTAssertEqual(degradation.level, .cgmOnly)
        XCTAssertEqual(degradation.reason, .pumpDisconnected)
    }
    
    func testOfflineFactory() {
        let degradation = AlgorithmDegradation.offline()
        
        XCTAssertEqual(degradation.level, .offline)
        XCTAssertEqual(degradation.reason, .cgmDisconnected)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let degradation = AlgorithmDegradation.cgmOnly(reason: .pumpDisconnected)
        
        XCTAssertTrue(degradation.description.contains("cgmOnly"))
        XCTAssertTrue(degradation.description.contains("pumpDisconnected"))
    }
    
    func testCapabilitiesDescription() {
        let caps = AlgorithmDegradation.Capabilities.full
        let description = caps.description
        
        XCTAssertTrue(description.contains("glucose"))
        XCTAssertTrue(description.contains("IOB"))
        XCTAssertTrue(description.contains("predictions"))
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let degradation = AlgorithmDegradation.evaluate(
            loopMode: .cgmOnly,
            cgmConnected: true,
            pumpConnected: false,
            insulinFreshness: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(degradation)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AlgorithmDegradation.self, from: data)
        
        XCTAssertEqual(decoded.level, degradation.level)
        XCTAssertEqual(decoded.reason, degradation.reason)
    }
    
    // MARK: - isDegraded Tests
    
    func testIsDegraded() {
        XCTAssertFalse(AlgorithmDegradation.full().isDegraded)
        XCTAssertTrue(AlgorithmDegradation.cgmOnly(reason: .pumpDisconnected).isDegraded)
        XCTAssertTrue(AlgorithmDegradation.offline().isDegraded)
    }
}
