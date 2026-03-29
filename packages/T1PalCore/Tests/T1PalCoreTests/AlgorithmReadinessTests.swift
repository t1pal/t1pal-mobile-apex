import XCTest
@testable import T1PalCore

final class AlgorithmReadinessTests: XCTestCase {
    
    // MARK: - State Tests
    
    func testReadyState() {
        let readiness = AlgorithmReadiness.ready()
        
        XCTAssertEqual(readiness.state, .ready)
        XCTAssertTrue(readiness.state.canExecute)
        XCTAssertTrue(readiness.state.isFullyReady)
        XCTAssertEqual(readiness.state.elementState, .normalCGM)
        XCTAssertTrue(readiness.allowsAutomaticDosing)
        XCTAssertEqual(readiness.summaryMessage, "Algorithm ready")
    }
    
    func testDegradedState() {
        let readiness = AlgorithmReadiness.degraded([.glucoseStale, .insulinDataAging])
        
        if case .degraded(let reasons) = readiness.state {
            XCTAssertEqual(reasons.count, 2)
            XCTAssertTrue(reasons.contains(.glucoseStale))
            XCTAssertTrue(reasons.contains(.insulinDataAging))
        } else {
            XCTFail("Expected degraded state")
        }
        
        XCTAssertTrue(readiness.state.canExecute)
        XCTAssertFalse(readiness.state.isFullyReady)
        XCTAssertEqual(readiness.state.elementState, .warning)
        XCTAssertTrue(readiness.allowsAutomaticDosing)
    }
    
    func testCannotRunState() {
        let readiness = AlgorithmReadiness.cannotRun([.noGlucoseData, .noPumpConfigured])
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertEqual(reasons.count, 2)
            XCTAssertTrue(reasons.contains(.noGlucoseData))
            XCTAssertTrue(reasons.contains(.noPumpConfigured))
        } else {
            XCTFail("Expected cannotRun state")
        }
        
        XCTAssertFalse(readiness.state.canExecute)
        XCTAssertFalse(readiness.state.isFullyReady)
        XCTAssertEqual(readiness.state.elementState, .critical)
        XCTAssertFalse(readiness.allowsAutomaticDosing)
    }
    
    // MARK: - Evaluate Tests
    
    func testEvaluateAllReady() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        let insulinFreshness = InsulinFreshness(lastDoseDate: Date())
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            insulinFreshness: insulinFreshness,
            hasPump: true,
            pumpSuspended: false
        )
        
        XCTAssertEqual(readiness.state, .ready)
        XCTAssertTrue(readiness.components.allReady)
    }
    
    func testEvaluateStaleGlucose() {
        // 8 minutes old - stale but not expired
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date().addingTimeInterval(-480))
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true
        )
        
        if case .degraded(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.glucoseStale))
        } else {
            XCTFail("Expected degraded state")
        }
        XCTAssertTrue(readiness.state.canExecute)
    }
    
    func testEvaluateExpiredGlucose() {
        // 15 minutes old - expired
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date().addingTimeInterval(-900))
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.glucoseExpired))
        } else {
            XCTFail("Expected cannotRun state")
        }
        XCTAssertFalse(readiness.state.canExecute)
    }
    
    func testEvaluateNoGlucoseData() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: nil)
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.noGlucoseData))
        } else {
            XCTFail("Expected cannotRun state")
        }
    }
    
    func testEvaluateNoPump() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: false
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.noPumpConfigured))
        } else {
            XCTFail("Expected cannotRun state")
        }
        XCTAssertFalse(readiness.components.pumpReady)
    }
    
    func testEvaluatePumpSuspended() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true,
            pumpSuspended: true
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.pumpSuspended))
        } else {
            XCTFail("Expected cannotRun state")
        }
    }
    
    func testEvaluateMissingConfiguration() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true,
            hasBasalSchedule: false,
            hasInsulinSensitivity: false
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.missingBasalSchedule))
            XCTAssertTrue(reasons.contains(.missingInsulinSensitivity))
        } else {
            XCTFail("Expected cannotRun state")
        }
        XCTAssertFalse(readiness.components.configurationReady)
    }
    
    func testEvaluateAgingInsulin() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        // 8 hours old - past 6h DIA
        let insulinFreshness = InsulinFreshness(lastDoseDate: Date().addingTimeInterval(-28800))
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            insulinFreshness: insulinFreshness,
            hasPump: true
        )
        
        if case .degraded(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.insulinDataAging))
        } else {
            XCTFail("Expected degraded state due to aging insulin")
        }
    }
    
    func testEvaluateCGMSensorFailed() {
        let glucoseFreshness = DataFreshness.glucose(lastReading: Date())
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: glucoseFreshness,
            hasPump: true,
            cgmSensorFailed: true
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.cgmSensorFailed))
        } else {
            XCTFail("Expected cannotRun state")
        }
    }
    
    // MARK: - Components Tests
    
    func testComponentsAllReady() {
        let components = AlgorithmReadiness.Components()
        XCTAssertTrue(components.allReady)
    }
    
    func testComponentsNotAllReady() {
        let components = AlgorithmReadiness.Components(glucoseReady: false)
        XCTAssertFalse(components.allReady)
    }
    
    // MARK: - Reason Descriptions
    
    func testDegradedReasonDescriptions() {
        for reason in AlgorithmReadiness.DegradedReason.allCases {
            XCTAssertFalse(reason.localizedDescription.isEmpty)
        }
    }
    
    func testCannotRunReasonDescriptions() {
        for reason in AlgorithmReadiness.CannotRunReason.allCases {
            XCTAssertFalse(reason.localizedDescription.isEmpty)
            XCTAssertFalse(reason.symbolName.isEmpty)
        }
    }
    
    // MARK: - Detailed Reasons
    
    func testDetailedReasonsReady() {
        let readiness = AlgorithmReadiness.ready()
        XCTAssertTrue(readiness.detailedReasons.isEmpty)
    }
    
    func testDetailedReasonsDegraded() {
        let readiness = AlgorithmReadiness.degraded([.glucoseStale, .insulinDataAging])
        XCTAssertEqual(readiness.detailedReasons.count, 2)
    }
    
    func testDetailedReasonsCannotRun() {
        let readiness = AlgorithmReadiness.cannotRun([.noGlucoseData])
        XCTAssertEqual(readiness.detailedReasons.count, 1)
        XCTAssertTrue(readiness.detailedReasons[0].contains("glucose"))
    }
    
    // MARK: - Summary Messages
    
    func testSummaryMessageSingleReason() {
        let readiness = AlgorithmReadiness.cannotRun([.pumpSuspended])
        XCTAssertEqual(readiness.summaryMessage, "Pump is suspended")
    }
    
    func testSummaryMessageMultipleReasons() {
        let readiness = AlgorithmReadiness.cannotRun([.pumpSuspended, .noGlucoseData])
        XCTAssertEqual(readiness.summaryMessage, "Algorithm cannot run")
    }
    
    // MARK: - Codable Tests
    
    func testCodableReady() throws {
        let original = AlgorithmReadiness.ready()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlgorithmReadiness.self, from: encoded)
        
        XCTAssertEqual(original.state, decoded.state)
    }
    
    func testCodableDegraded() throws {
        let original = AlgorithmReadiness.degraded([.glucoseStale])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlgorithmReadiness.self, from: encoded)
        
        if case .degraded(let reasons) = decoded.state {
            XCTAssertTrue(reasons.contains(.glucoseStale))
        } else {
            XCTFail("Expected degraded state after decode")
        }
    }
    
    func testCodableCannotRun() throws {
        let original = AlgorithmReadiness.cannotRun([.noPumpConfigured, .missingBasalSchedule])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlgorithmReadiness.self, from: encoded)
        
        if case .cannotRun(let reasons) = decoded.state {
            XCTAssertEqual(reasons.count, 2)
        } else {
            XCTFail("Expected cannotRun state after decode")
        }
    }
    
    // MARK: - Description
    
    func testDescription() {
        let ready = AlgorithmReadiness.ready()
        XCTAssertTrue(ready.description.contains("ready"))
        
        let degraded = AlgorithmReadiness.degraded([.glucoseStale])
        XCTAssertTrue(degraded.description.contains("degraded"))
        XCTAssertTrue(degraded.description.contains("glucoseStale"))
        
        let cannotRun = AlgorithmReadiness.cannotRun([.noPumpConfigured])
        XCTAssertTrue(cannotRun.description.contains("cannotRun"))
    }
    
    // MARK: - Sendable Conformance
    
    func testSendableConformance() async {
        let readiness = AlgorithmReadiness.ready()
        
        let result = await Task.detached {
            return readiness.state.canExecute
        }.value
        
        XCTAssertTrue(result)
    }
    
    // MARK: - Mode-Aware Evaluation Tests (AID-PARTIAL-003)
    
    func testCGMOnlyModeNoPumpDoesNotError() {
        // CGM-only mode should NOT error when pump is missing
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .cgmOnly,
            glucoseFreshness: freshGlucose,
            hasPump: false
        )
        
        // Should NOT be cannotRun - should be degraded or ready
        XCTAssertTrue(readiness.state.canExecute, "CGM-only mode should execute without pump")
        XCTAssertNotEqual(readiness.state.elementState, .critical)
    }
    
    func testClosedLoopNoPumpErrors() {
        // Closed-loop SHOULD error when pump is missing
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .closedLoop,
            glucoseFreshness: freshGlucose,
            hasPump: false
        )
        
        // Should be cannotRun
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.noPumpConfigured))
        } else {
            XCTFail("Closed-loop without pump should be cannotRun")
        }
    }
    
    func testOpenLoopNoPumpErrors() {
        // Open-loop SHOULD error when pump is missing
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .openLoop,
            glucoseFreshness: freshGlucose,
            hasPump: false
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.noPumpConfigured))
        } else {
            XCTFail("Open-loop without pump should be cannotRun")
        }
    }
    
    func testCGMOnlyModeStillRequiresCGM() {
        // Even CGM-only mode requires CGM data
        let noGlucose = DataFreshness(
            lastDataDate: nil,
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .cgmOnly,
            glucoseFreshness: noGlucose,
            hasPump: false
        )
        
        // Should be cannotRun due to no glucose
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.noGlucoseData))
        } else {
            XCTFail("CGM-only mode without glucose should be cannotRun")
        }
    }
    
    func testCGMOnlyModeSkipsConfigurationChecks() {
        // CGM-only mode shouldn't require basal schedule etc.
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .cgmOnly,
            glucoseFreshness: freshGlucose,
            hasPump: false,
            hasBasalSchedule: false,
            hasInsulinSensitivity: false,
            hasCarbRatio: false,
            hasGlucoseTarget: false
        )
        
        // Should still execute - config not required for cgmOnly
        XCTAssertTrue(readiness.state.canExecute)
    }
    
    func testClosedLoopRequiresConfiguration() {
        // Closed-loop DOES require configuration
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .closedLoop,
            glucoseFreshness: freshGlucose,
            hasPump: true,
            hasBasalSchedule: false
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.missingBasalSchedule))
        } else {
            XCTFail("Closed-loop without basal schedule should be cannotRun")
        }
    }
    
    func testFullyConfiguredClosedLoop() {
        // Fully configured closed-loop should be ready
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        let freshInsulin = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-3600),
            dia: .standard
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .closedLoop,
            glucoseFreshness: freshGlucose,
            insulinFreshness: freshInsulin,
            hasPump: true,
            hasBasalSchedule: true,
            hasInsulinSensitivity: true,
            hasCarbRatio: true,
            hasGlucoseTarget: true
        )
        
        XCTAssertEqual(readiness.state, .ready)
        XCTAssertTrue(readiness.components.allReady)
    }
    
    func testPumpSuspendedInClosedLoop() {
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .closedLoop,
            glucoseFreshness: freshGlucose,
            hasPump: true,
            pumpSuspended: true
        )
        
        if case .cannotRun(let reasons) = readiness.state {
            XCTAssertTrue(reasons.contains(.pumpSuspended))
        } else {
            XCTFail("Pump suspended should be cannotRun")
        }
    }
    
    func testCGMOnlyComponentsReady() {
        let freshGlucose = DataFreshness(
            lastDataDate: Date().addingTimeInterval(-60),
            thresholds: .glucose
        )
        
        let readiness = AlgorithmReadiness.evaluateForMode(
            loopMode: .cgmOnly,
            glucoseFreshness: freshGlucose,
            hasPump: false
        )
        
        // Glucose should be ready, pump/config marked as ready (not required)
        XCTAssertTrue(readiness.components.glucoseReady)
        XCTAssertTrue(readiness.components.pumpReady, "Pump ready should be true when not required")
        XCTAssertTrue(readiness.components.configurationReady, "Config ready should be true when not required")
    }
}
