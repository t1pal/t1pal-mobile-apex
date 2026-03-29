/// Tests for PumpManagerError stratification
/// BEHAV-003 verification

import XCTest
@testable import T1PalCore

final class PumpManagerErrorTests: XCTestCase {
    
    // MARK: - Category Tests
    
    func testConfigurationErrorCategories() {
        let errors: [PumpManagerError.ConfigurationError] = [
            .noPumpConfigured,
            .insulinTypeNotConfigured,
            .basalScheduleNotConfigured,
            .invalidSettings,
            .missingParameter,
            .unsupportedPumpModel
        ]
        
        XCTAssertEqual(errors.count, 6)
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.recoverySuggestion.isEmpty)
        }
    }
    
    func testConnectionErrorCategories() {
        let errors: [PumpManagerError.ConnectionError] = [
            .noRileyLink,
            .bluetoothDisabled,
            .bluetoothUnauthorized,
            .pumpNotFound,
            .connectionTimeout,
            .rssiTooLow,
            .noPodPaired
        ]
        
        XCTAssertEqual(errors.count, 7)
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.recoverySuggestion.isEmpty)
        }
    }
    
    func testCommunicationErrorCategories() {
        let errors: [PumpManagerError.CommunicationError] = [
            .commandFailed,
            .responseTimeout,
            .invalidResponse,
            .checksumError,
            .radioInterference,
            .commandRejected,
            .pumpBusy
        ]
        
        XCTAssertEqual(errors.count, 7)
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.recoverySuggestion.isEmpty)
        }
    }
    
    func testDeviceStateErrorCategories() {
        let errors: [PumpManagerError.DeviceStateError] = [
            .suspended,
            .faulted,
            .podExpired,
            .reservoirEmpty,
            .batteryDead,
            .bolusInProgress,
            .tempBasalInProgress,
            .timeSyncNeeded
        ]
        
        XCTAssertEqual(errors.count, 8)
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.recoverySuggestion.isEmpty)
        }
    }
    
    func testDeliveryFailureReasons() {
        let reasons: [PumpManagerError.DeliveryFailureReason] = [
            .occlusion,
            .reservoirEmpty,
            .maxBolusExceeded,
            .maxBasalExceeded,
            .maxIOBExceeded,
            .bolusCancelled,
            .tempBasalCancelled,
            .deliveryInterrupted
        ]
        
        XCTAssertEqual(reasons.count, 8)
        
        for reason in reasons {
            XCTAssertFalse(reason.localizedDescription.isEmpty)
        }
    }
    
    func testInternalErrorCategories() {
        let errors: [PumpManagerError.InternalError] = [
            .unexpected,
            .assertionFailure,
            .invalidState,
            .notImplemented
        ]
        
        XCTAssertEqual(errors.count, 4)
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
    
    // MARK: - Factory Method Tests
    
    func testConfigurationFactoryMethod() {
        let error = PumpManagerError.configuration(.noPumpConfigured)
        
        XCTAssertEqual(error.category.name, "configuration")
        XCTAssertTrue(error.isRecoverable)
        XCTAssertNotNil(error.underlyingDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testConnectionFactoryMethod() {
        let error = PumpManagerError.connection(.noRileyLink)
        
        XCTAssertEqual(error.category.name, "connection")
        XCTAssertTrue(error.isRecoverable)
    }
    
    func testCommunicationFactoryMethod() {
        let error = PumpManagerError.communication(.commandFailed)
        
        XCTAssertEqual(error.category.name, "communication")
        XCTAssertTrue(error.isRecoverable)
    }
    
    func testDeviceStateFactoryMethod() {
        // Recoverable states
        let suspended = PumpManagerError.deviceState(.suspended)
        XCTAssertTrue(suspended.isRecoverable)
        
        let bolusInProgress = PumpManagerError.deviceState(.bolusInProgress)
        XCTAssertTrue(bolusInProgress.isRecoverable)
        
        // Non-recoverable states
        let faulted = PumpManagerError.deviceState(.faulted)
        XCTAssertFalse(faulted.isRecoverable)
        
        let podExpired = PumpManagerError.deviceState(.podExpired)
        XCTAssertFalse(podExpired.isRecoverable)
        
        let batteryDead = PumpManagerError.deviceState(.batteryDead)
        XCTAssertFalse(batteryDead.isRecoverable)
    }
    
    func testDeliveryCertainFactoryMethod() {
        let error = PumpManagerError.deliveryCertain(.occlusion)
        
        XCTAssertEqual(error.category.name, "delivery")
        XCTAssertTrue(error.isRecoverable)
        
        // Verify not uncertain
        if case .delivery(let delivery) = error.category {
            XCTAssertFalse(delivery.isUncertain)
            XCTAssertEqual(delivery.reason, .occlusion)
        } else {
            XCTFail("Expected delivery category")
        }
    }
    
    func testDeliveryUncertainFactoryMethod() {
        let error = PumpManagerError.deliveryUncertain(.deliveryInterrupted)
        
        XCTAssertEqual(error.category.name, "delivery")
        XCTAssertFalse(error.isRecoverable)  // Requires user verification
        
        // Verify uncertain
        if case .delivery(let delivery) = error.category {
            XCTAssertTrue(delivery.isUncertain)
            XCTAssertEqual(delivery.reason, .deliveryInterrupted)
        } else {
            XCTFail("Expected delivery category")
        }
    }
    
    func testInternalFactoryMethod() {
        let error = PumpManagerError.internal(.unexpected)
        
        XCTAssertEqual(error.category.name, "internal")
        XCTAssertFalse(error.isRecoverable)
    }
    
    // MARK: - Element State Tests
    
    func testConfigurationElementState() {
        let category = PumpManagerError.Category.configuration(.invalidSettings)
        XCTAssertEqual(category.elementState, .warning)
    }
    
    func testConnectionElementState() {
        let category = PumpManagerError.Category.connection(.noRileyLink)
        XCTAssertEqual(category.elementState, .warning)
    }
    
    func testCommunicationElementState() {
        let category = PumpManagerError.Category.communication(.commandFailed)
        XCTAssertEqual(category.elementState, .warning)
    }
    
    func testDeviceStateElementState() {
        let category = PumpManagerError.Category.deviceState(.faulted)
        XCTAssertEqual(category.elementState, .critical)
    }
    
    func testCertainDeliveryElementState() {
        let category = PumpManagerError.Category.delivery(.certain(.occlusion))
        XCTAssertEqual(category.elementState, .warning)
    }
    
    func testUncertainDeliveryElementState() {
        let category = PumpManagerError.Category.delivery(.uncertain(.deliveryInterrupted))
        XCTAssertEqual(category.elementState, .critical)  // Uncertain = critical
    }
    
    func testInternalElementState() {
        let category = PumpManagerError.Category.internal(.unexpected)
        XCTAssertEqual(category.elementState, .critical)
    }
    
    // MARK: - Classification Tests
    
    func testClassifyPumpManagerError() {
        let original = PumpManagerError.connection(.noRileyLink)
        let classified = PumpManagerError.classify(original)
        
        // Should return same error
        XCTAssertEqual(classified.category.name, "connection")
    }
    
    func testClassifyBluetoothError() {
        struct BluetoothError: Error {
            var localizedDescription: String { "Bluetooth is disabled" }
        }
        
        let classified = PumpManagerError.classify(BluetoothError())
        XCTAssertEqual(classified.category.name, "connection")
    }
    
    func testClassifyTimeoutError() {
        struct TimeoutError: Error {
            var localizedDescription: String { "Request timeout" }
        }
        
        let classified = PumpManagerError.classify(TimeoutError())
        XCTAssertEqual(classified.category.name, "communication")
    }
    
    func testClassifyUnknownError() {
        struct UnknownError: Error {
            var localizedDescription: String { "Some random error" }
        }
        
        let classified = PumpManagerError.classify(UnknownError())
        XCTAssertEqual(classified.category.name, "internal")
    }
    
    // MARK: - Localized Error Tests
    
    func testLocalizedErrorDescription() {
        let error = PumpManagerError.configuration(.noPumpConfigured)
        XCTAssertEqual(error.errorDescription, "No pump configured")
    }
    
    func testLocalizedRecoverySuggestion() {
        let error = PumpManagerError.configuration(.noPumpConfigured)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testUncertainDeliveryDescription() {
        let error = PumpManagerError.deliveryUncertain(.deliveryInterrupted)
        XCTAssertTrue(error.errorDescription?.contains("uncertain") ?? false)
    }
    
    // MARK: - Codable Tests
    
    func testConfigurationErrorCodable() throws {
        let error = PumpManagerError.configuration(.noPumpConfigured)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PumpManagerError.self, from: data)
        
        XCTAssertEqual(decoded.category.name, "configuration")
    }
    
    func testDeliveryErrorCodable() throws {
        let error = PumpManagerError.deliveryUncertain(.occlusion)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PumpManagerError.self, from: data)
        
        if case .delivery(let delivery) = decoded.category {
            XCTAssertTrue(delivery.isUncertain)
            XCTAssertEqual(delivery.reason, .occlusion)
        } else {
            XCTFail("Expected delivery category")
        }
    }
    
    // MARK: - Equatable Tests
    
    func testEquatable() {
        let error1 = PumpManagerError.connection(.noRileyLink)
        let error2 = PumpManagerError.connection(.noRileyLink)
        let error3 = PumpManagerError.connection(.bluetoothDisabled)
        
        // Same category and similar timestamp should be equal
        // Note: timestamps differ, so we check category equality separately
        XCTAssertEqual(error1.category, error2.category)
        XCTAssertNotEqual(error1.category, error3.category)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let error = PumpManagerError.connection(.noRileyLink)
        let description = error.description
        
        XCTAssertTrue(description.contains("PumpManagerError"))
        XCTAssertTrue(description.contains("connection"))
    }
    
    // MARK: - Issue ID Tests
    
    func testIssueIdForDosingDecision() {
        // Each category has an issue ID for dosing decision tracking (matches Loop)
        XCTAssertEqual(PumpManagerError.Category.configuration(.noPumpConfigured).issueId, "configuration")
        XCTAssertEqual(PumpManagerError.Category.connection(.noRileyLink).issueId, "connection")
        XCTAssertEqual(PumpManagerError.Category.communication(.commandFailed).issueId, "communication")
        XCTAssertEqual(PumpManagerError.Category.deviceState(.suspended).issueId, "deviceState")
        XCTAssertEqual(PumpManagerError.Category.delivery(.uncertain(.occlusion)).issueId, "delivery")
        XCTAssertEqual(PumpManagerError.Category.internal(.unexpected).issueId, "internal")
    }
}
