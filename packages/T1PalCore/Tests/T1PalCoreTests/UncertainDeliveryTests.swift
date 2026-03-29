/// Tests for UncertainDelivery handling
/// BEHAV-004 verification - Critical safety feature

import XCTest
@testable import T1PalCore

final class UncertainDeliveryTests: XCTestCase {
    
    // MARK: - State Tests
    
    func testCertainStateDefault() {
        let state = UncertainDeliveryState()
        
        XCTAssertFalse(state.isUncertain)
        XCTAssertNil(state.uncertainDeliveryType)
        XCTAssertNil(state.detectedAt)
        XCTAssertNil(state.causingError)
        XCTAssertNil(state.expectedUnits)
        XCTAssertEqual(state.recoveryAttempts, 0)
        XCTAssertTrue(state.canRunAutomation)
    }
    
    func testCertainStaticConstant() {
        let state = UncertainDeliveryState.certain
        
        XCTAssertFalse(state.isUncertain)
        XCTAssertTrue(state.canRunAutomation)
    }
    
    func testUncertainStateCreation() {
        let state = UncertainDeliveryState(
            type: .bolus,
            expectedUnits: 2.5
        )
        
        XCTAssertTrue(state.isUncertain)
        XCTAssertEqual(state.uncertainDeliveryType, .bolus)
        XCTAssertNotNil(state.detectedAt)
        XCTAssertEqual(state.expectedUnits, 2.5)
        XCTAssertFalse(state.canRunAutomation)
    }
    
    func testUncertainStateFromPumpManagerError() {
        let error = PumpManagerError.deliveryUncertain(.deliveryInterrupted)
        let state = UncertainDeliveryState.from(error: error, expectedUnits: 1.0)
        
        XCTAssertTrue(state.isUncertain)
        XCTAssertNotNil(state.causingError)
    }
    
    func testCertainStateFromNonUncertainError() {
        let error = PumpManagerError.communication(.commandFailed)
        let state = UncertainDeliveryState.from(error: error)
        
        XCTAssertFalse(state.isUncertain)
        XCTAssertTrue(state.canRunAutomation)
    }
    
    // MARK: - Automation Blocking Tests (Critical Safety)
    
    func testUncertainStateBlocksAutomation() {
        let state = UncertainDeliveryState(type: .bolus)
        
        // CRITICAL: Uncertain delivery MUST block automation
        XCTAssertFalse(state.canRunAutomation, "Uncertain delivery MUST block automation")
    }
    
    func testCertainStateAllowsAutomation() {
        let state = UncertainDeliveryState.certain
        
        XCTAssertTrue(state.canRunAutomation)
    }
    
    // MARK: - Recovery Attempt Tests
    
    func testRecoveryAttemptIncrement() {
        var state = UncertainDeliveryState(type: .tempBasal)
        XCTAssertEqual(state.recoveryAttempts, 0)
        
        state = state.withRecoveryAttempt()
        XCTAssertEqual(state.recoveryAttempts, 1)
        XCTAssertFalse(state.recoveryExhausted)
        
        state = state.withRecoveryAttempt()
        XCTAssertEqual(state.recoveryAttempts, 2)
        XCTAssertFalse(state.recoveryExhausted)
        
        state = state.withRecoveryAttempt()
        XCTAssertEqual(state.recoveryAttempts, 3)
        XCTAssertTrue(state.recoveryExhausted)
    }
    
    func testRecoveryAttemptPreservesState() {
        let state = UncertainDeliveryState(
            type: .bolus,
            causingError: "Test error",
            expectedUnits: 3.0
        )
        
        let newState = state.withRecoveryAttempt()
        
        XCTAssertEqual(newState.uncertainDeliveryType, .bolus)
        XCTAssertEqual(newState.causingError, "Test error")
        XCTAssertEqual(newState.expectedUnits, 3.0)
        XCTAssertEqual(newState.recoveryAttempts, 1)
    }
    
    func testRecoveryAttemptOnCertainStateNoOp() {
        let state = UncertainDeliveryState.certain
        let newState = state.withRecoveryAttempt()
        
        XCTAssertFalse(newState.isUncertain)
        XCTAssertEqual(newState.recoveryAttempts, 0)
    }
    
    // MARK: - Delivery Type Tests
    
    func testDeliveryTypeDescriptions() {
        XCTAssertEqual(UncertainDeliveryState.DeliveryType.bolus.localizedDescription, "bolus")
        XCTAssertEqual(UncertainDeliveryState.DeliveryType.tempBasal.localizedDescription, "temp basal")
        XCTAssertEqual(UncertainDeliveryState.DeliveryType.basalResume.localizedDescription, "basal resume")
        XCTAssertEqual(UncertainDeliveryState.DeliveryType.suspend.localizedDescription, "suspend")
        XCTAssertEqual(UncertainDeliveryState.DeliveryType.unknown.localizedDescription, "insulin delivery")
    }
    
    func testAllDeliveryTypesCovered() {
        let allTypes = UncertainDeliveryState.DeliveryType.allCases
        XCTAssertEqual(allTypes.count, 5)
    }
    
    // MARK: - Alert Tests
    
    func testAlertCreation() {
        let state = UncertainDeliveryState(type: .bolus, expectedUnits: 2.5)
        let alert = UncertainDeliveryAlert(state: state)
        
        XCTAssertEqual(alert.title, "Unable To Reach Pump")
        XCTAssertTrue(alert.message.contains("bolus"))
        XCTAssertTrue(alert.message.contains("2.50 U"))
        XCTAssertFalse(alert.recoveryInstructions.isEmpty)
        XCTAssertEqual(alert.monitoringDurationHours, 6)
    }
    
    func testAlertWithoutUnits() {
        let state = UncertainDeliveryState(type: .tempBasal)
        let alert = UncertainDeliveryAlert(state: state)
        
        XCTAssertTrue(alert.message.contains("temp basal"))
        XCTAssertFalse(alert.message.contains(" U"))
    }
    
    func testAlertReplacementNeeded() {
        var state = UncertainDeliveryState(type: .bolus)
        
        // Exhaust recovery attempts
        state = state.withRecoveryAttempt()
        state = state.withRecoveryAttempt()
        state = state.withRecoveryAttempt()
        
        let alert = UncertainDeliveryAlert(state: state)
        XCTAssertTrue(alert.mayRequireReplacement)
    }
    
    func testMonitoringWarning() {
        let state = UncertainDeliveryState(type: .bolus)
        let alert = UncertainDeliveryAlert(state: state)
        
        XCTAssertTrue(alert.monitoringWarning.contains("6 hours"))
        XCTAssertTrue(alert.monitoringWarning.contains("Monitor your glucose"))
    }
    
    // MARK: - Handler Tests
    
    func testHandlerInitialState() {
        let handler = UncertainDeliveryHandler()
        
        XCTAssertFalse(handler.state.isUncertain)
        XCTAssertTrue(handler.state.canRunAutomation)
    }
    
    func testHandlerReportUncertainDelivery() {
        var handler = UncertainDeliveryHandler()
        // Just test that the state changes - callbacks are tested separately
        handler.reportUncertainDelivery(type: .bolus, expectedUnits: 2.0)
        
        XCTAssertTrue(handler.state.isUncertain)
        XCTAssertEqual(handler.state.uncertainDeliveryType, .bolus)
        XCTAssertEqual(handler.state.expectedUnits, 2.0)
    }
    
    func testHandlerReportError() {
        var handler = UncertainDeliveryHandler()
        
        let error = PumpManagerError.deliveryUncertain(.bolusCancelled)
        handler.reportError(error, expectedUnits: 1.5)
        
        XCTAssertTrue(handler.state.isUncertain)
        XCTAssertEqual(handler.state.uncertainDeliveryType, .bolus)
    }
    
    func testHandlerReportNonUncertainError() {
        var handler = UncertainDeliveryHandler()
        
        let error = PumpManagerError.connection(.noRileyLink)
        handler.reportError(error)
        
        XCTAssertFalse(handler.state.isUncertain)
    }
    
    func testHandlerAttemptRecovery() {
        var handler = UncertainDeliveryHandler()
        handler.reportUncertainDelivery(type: .tempBasal)
        
        let result1 = handler.attemptRecovery()
        XCTAssertEqual(result1, .attempting(attempt: 1))
        
        let result2 = handler.attemptRecovery()
        XCTAssertEqual(result2, .attempting(attempt: 2))
        
        let result3 = handler.attemptRecovery()
        XCTAssertEqual(result3, .exhausted)
    }
    
    func testHandlerRecoveryNotNeeded() {
        var handler = UncertainDeliveryHandler()
        
        let result = handler.attemptRecovery()
        XCTAssertEqual(result, .notNeeded)
    }
    
    func testHandlerConfirmDelivery() {
        var handler = UncertainDeliveryHandler()
        handler.reportUncertainDelivery(type: .bolus)
        XCTAssertTrue(handler.state.isUncertain)
        
        handler.confirmDelivery()
        
        XCTAssertFalse(handler.state.isUncertain)
        XCTAssertTrue(handler.state.canRunAutomation)
    }
    
    func testHandlerConfirmDeliveryFailed() {
        var handler = UncertainDeliveryHandler()
        handler.reportUncertainDelivery(type: .bolus)
        
        handler.confirmDeliveryFailed()
        
        XCTAssertFalse(handler.state.isUncertain)
        XCTAssertTrue(handler.state.canRunAutomation)
    }
    
    func testHandlerDeviceReplaced() {
        var handler = UncertainDeliveryHandler()
        handler.reportUncertainDelivery(type: .bolus)
        
        handler.deviceReplaced()
        
        XCTAssertFalse(handler.state.isUncertain)
    }
    
    func testHandlerUserAcknowledged() {
        var handler = UncertainDeliveryHandler()
        
        handler.reportUncertainDelivery(type: .bolus)
        handler.userAcknowledged()
        
        // State should remain uncertain after acknowledgment
        XCTAssertTrue(handler.state.isUncertain)
    }
    
    // MARK: - Safety Log Tests
    
    func testSafetyLogEventsViaStateTransitions() {
        var handler = UncertainDeliveryHandler()
        
        // Test that transitions work correctly
        handler.reportUncertainDelivery(type: .bolus)
        XCTAssertTrue(handler.state.isUncertain)
        
        _ = handler.attemptRecovery()
        XCTAssertEqual(handler.state.recoveryAttempts, 1)
        
        handler.confirmDelivery()
        XCTAssertFalse(handler.state.isUncertain)
    }
    
    // MARK: - AlgorithmReadiness Integration Tests
    
    func testAlgorithmCannotRunWithUncertainDelivery() {
        let freshGlucose = DataFreshness(
            lastDataDate: Date(),
            thresholds: .glucose
        )
        let freshInsulin = InsulinFreshness(
            lastDoseDate: Date(),
            dia: .standard
        )
        let uncertainState = UncertainDeliveryState(type: .bolus)
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: freshGlucose,
            insulinFreshness: freshInsulin,
            hasPump: true,
            deliveryState: uncertainState
        )
        
        XCTAssertEqual(readiness.state, .cannotRun([.uncertainDelivery]))
        XCTAssertFalse(readiness.state.canExecute)
    }
    
    func testAlgorithmCanRunWithCertainDelivery() {
        let freshGlucose = DataFreshness(
            lastDataDate: Date(),
            thresholds: .glucose
        )
        let freshInsulin = InsulinFreshness(
            lastDoseDate: Date(),
            dia: .standard
        )
        
        let readiness = AlgorithmReadiness.evaluate(
            glucoseFreshness: freshGlucose,
            insulinFreshness: freshInsulin,
            hasPump: true,
            deliveryState: .certain
        )
        
        XCTAssertEqual(readiness.state, .ready)
        XCTAssertTrue(readiness.state.canExecute)
    }
    
    // MARK: - Codable Tests
    
    func testStateCodable() throws {
        let state = UncertainDeliveryState(
            type: .bolus,
            causingError: "Test error",
            expectedUnits: 2.5,
            recoveryAttempts: 1
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UncertainDeliveryState.self, from: data)
        
        XCTAssertEqual(decoded.isUncertain, true)
        XCTAssertEqual(decoded.uncertainDeliveryType, .bolus)
        XCTAssertEqual(decoded.causingError, "Test error")
        XCTAssertEqual(decoded.expectedUnits, 2.5)
        XCTAssertEqual(decoded.recoveryAttempts, 1)
    }
    
    // MARK: - Description Tests
    
    func testUncertainDescription() {
        let state = UncertainDeliveryState(type: .bolus)
        XCTAssertTrue(state.description.contains("UncertainDelivery"))
        XCTAssertTrue(state.description.contains("bolus"))
    }
    
    func testCertainDescription() {
        let state = UncertainDeliveryState.certain
        XCTAssertEqual(state.description, "CertainDelivery")
    }
}
