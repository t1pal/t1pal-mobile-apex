// ErrorClassifierTests.swift
// BLEKitTests
//
// Tests for BLE-CONN-002: Error classification retry matrix

import Testing
import Foundation
@testable import BLEKit

@Suite("Error Classification")
struct ErrorClassificationTests {
    
    let classifier = ErrorClassifier()
    
    // MARK: - Transient Errors
    
    @Test("Connection timeout is transient")
    func connectionTimeoutIsTransient() {
        let classification = classifier.classify(.connectionTimeout)
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Disconnected is transient")
    func disconnectedIsTransient() {
        let classification = classifier.classify(.disconnected)
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Read failed is transient")
    func readFailedIsTransient() {
        let classification = classifier.classify(.readFailed("GATT error"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
        #expect(classification.technicalDetails.contains("GATT error"))
    }
    
    @Test("Write failed is transient")
    func writeFailedIsTransient() {
        let classification = classifier.classify(.writeFailed("Queue full"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Notification failed is transient")
    func notificationFailedIsTransient() {
        let classification = classifier.classify(.notificationFailed("CCCD write failed"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Scan failed is transient")
    func scanFailedIsTransient() {
        let classification = classifier.classify(.scanFailed("Busy"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Service not found is transient")
    func serviceNotFoundIsTransient() {
        let classification = classifier.classify(.serviceNotFound(BLEUUID(UUID())))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Characteristic not found is transient")
    func characteristicNotFoundIsTransient() {
        let classification = classifier.classify(.characteristicNotFound(BLEUUID(UUID())))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    // MARK: - Recoverable Errors
    
    @Test("Not powered on is recoverable")
    func notPoweredOnIsRecoverable() {
        let classification = classifier.classify(.notPoweredOn)
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .waitForBluetooth)
        #expect(classification.shouldRetry == false)
        #expect(classification.userMessage.contains("Bluetooth"))
    }
    
    @Test("Unauthorized is recoverable")
    func unauthorizedIsRecoverable() {
        let classification = classifier.classify(.unauthorized)
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .requestAuthorization)
        #expect(classification.shouldRetry == false)
    }
    
    // MARK: - Permanent Errors
    
    @Test("Unsupported is permanent")
    func unsupportedIsPermanent() {
        let classification = classifier.classify(.unsupported)
        
        #expect(classification.category == .permanent)
        #expect(classification.action == .abort)
        #expect(classification.shouldRetry == false)
    }
    
    @Test("Not supported is permanent")
    func notSupportedIsPermanent() {
        let classification = classifier.classify(.notSupported("Linux BLE"))
        
        #expect(classification.category == .permanent)
        #expect(classification.action == .abort)
        #expect(classification.shouldRetry == false)
    }
    
    // MARK: - Connection Failed Analysis
    
    @Test("Connection failed with pairing reason")
    func connectionFailedPairing() {
        let classification = classifier.classify(.connectionFailed("Device requires pairing"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .initiatePairing)
        #expect(classification.shouldRetry == false)
    }
    
    @Test("Connection failed with bonding reason")
    func connectionFailedBonding() {
        let classification = classifier.classify(.connectionFailed("Bond removed"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .initiatePairing)
    }
    
    @Test("Connection failed with RSSI reason")
    func connectionFailedRSSI() {
        let classification = classifier.classify(.connectionFailed("RSSI too low"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .moveCloser)
        #expect(classification.shouldRetry == true)
        #expect(classification.suggestedPolicy == .aggressive)
    }
    
    @Test("Connection failed with range reason")
    func connectionFailedRange() {
        let classification = classifier.classify(.connectionFailed("Out of range"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .moveCloser)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Connection failed with auth reason")
    func connectionFailedAuth() {
        let classification = classifier.classify(.connectionFailed("Authentication timeout"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .initiatePairing)
    }
    
    @Test("Connection failed with encryption reason")
    func connectionFailedEncryption() {
        let classification = classifier.classify(.connectionFailed("Encryption failed"))
        
        #expect(classification.category == .recoverable)
        #expect(classification.action == .initiatePairing)
    }
    
    @Test("Connection failed generic is transient")
    func connectionFailedGeneric() {
        let classification = classifier.classify(.connectionFailed("Unknown error"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    // MARK: - Invalid State Analysis
    
    @Test("Invalid state not connected is transient")
    func invalidStateNotConnected() {
        let classification = classifier.classify(.invalidState("Device not connected"))
        
        #expect(classification.category == .transient)
        #expect(classification.action == .retry)
        #expect(classification.shouldRetry == true)
    }
    
    @Test("Invalid state generic uses conservative")
    func invalidStateGeneric() {
        let classification = classifier.classify(.invalidState("Unknown state"))
        
        #expect(classification.category == .transient)
        #expect(classification.suggestedPolicy == .conservative)
    }
    
    // MARK: - Retry Policy Suggestions
    
    @Test("Transient errors suggest bleDefault policy")
    func transientSuggestsBleDefault() {
        let classification = classifier.classify(.connectionTimeout)
        #expect(classification.suggestedPolicy == .bleDefault)
    }
    
    @Test("Recoverable errors suggest none policy")
    func recoverableSuggestsNone() {
        let classification = classifier.classify(.notPoweredOn)
        #expect(classification.suggestedPolicy == .noRetry)
    }
    
    @Test("Permanent errors suggest none policy")
    func permanentSuggestsNone() {
        let classification = classifier.classify(.unsupported)
        #expect(classification.suggestedPolicy == .noRetry)
    }
    
    // MARK: - Generic Error Classification
    
    @Test("Classify any with BLEError")
    func classifyAnyWithBLEError() {
        let error: Error = BLEError.connectionTimeout
        let classification = classifier.classifyAny(error)
        
        #expect(classification.category == .transient)
    }
    
    @Test("Classify any with unknown error")
    func classifyAnyWithUnknownError() {
        struct CustomError: Error {}
        let error: Error = CustomError()
        let classification = classifier.classifyAny(error)
        
        #expect(classification.category == .unknown)
        #expect(classification.action == .unknown)
        #expect(classification.shouldRetry == true)
        #expect(classification.suggestedPolicy == .conservative)
    }
    
    // MARK: - Retry Integration
    
    @Test("Should retry transient error within attempts")
    func shouldRetryTransientWithinAttempts() {
        let result = classifier.shouldRetry(.connectionTimeout, attemptNumber: 1, maxAttempts: 5)
        #expect(result == true)
    }
    
    @Test("Should not retry transient error at max attempts")
    func shouldNotRetryAtMaxAttempts() {
        let result = classifier.shouldRetry(.connectionTimeout, attemptNumber: 5, maxAttempts: 5)
        #expect(result == false)
    }
    
    @Test("Should not retry permanent error")
    func shouldNotRetryPermanent() {
        let result = classifier.shouldRetry(.unsupported, attemptNumber: 1, maxAttempts: 5)
        #expect(result == false)
    }
    
    @Test("Should not retry recoverable error")
    func shouldNotRetryRecoverable() {
        let result = classifier.shouldRetry(.notPoweredOn, attemptNumber: 1, maxAttempts: 5)
        #expect(result == false)
    }
    
    @Test("Get retry executor for error")
    func getRetryExecutor() async {
        let executor = classifier.retryExecutor(for: .connectionTimeout)
        // Verify it's configured with bleDefault policy
        let classification = classifier.classify(.connectionTimeout)
        #expect(classification.suggestedPolicy == .bleDefault)
    }
}

@Suite("Error Classification Result")
struct ErrorClassificationResultTests {
    
    @Test("Classification is equatable")
    func classificationEquatable() {
        let c1 = ErrorClassification(
            category: .transient,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .bleDefault,
            userMessage: "Test",
            technicalDetails: "Details"
        )
        
        let c2 = ErrorClassification(
            category: .transient,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .bleDefault,
            userMessage: "Test",
            technicalDetails: "Details"
        )
        
        #expect(c1 == c2)
    }
    
    @Test("Classification with different category not equal")
    func classificationDifferentCategory() {
        let c1 = ErrorClassification(
            category: .transient,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .bleDefault,
            userMessage: "Test",
            technicalDetails: "Details"
        )
        
        let c2 = ErrorClassification(
            category: .permanent,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .bleDefault,
            userMessage: "Test",
            technicalDetails: "Details"
        )
        
        #expect(c1 != c2)
    }
}

@Suite("Error Category")
struct ErrorCategoryTests {
    
    @Test("Category has raw value")
    func categoryRawValue() {
        #expect(BLEErrorCategory.transient.rawValue == "transient")
        #expect(BLEErrorCategory.recoverable.rawValue == "recoverable")
        #expect(BLEErrorCategory.permanent.rawValue == "permanent")
        #expect(BLEErrorCategory.unknown.rawValue == "unknown")
    }
    
    @Test("Category is case iterable")
    func categoryCaseIterable() {
        #expect(BLEErrorCategory.allCases.count == 4)
    }
}

@Suite("Recovery Action")
struct RecoveryActionTests {
    
    @Test("Action has raw value")
    func actionRawValue() {
        #expect(RecoveryAction.retry.rawValue == "retry")
        #expect(RecoveryAction.waitForBluetooth.rawValue == "waitForBluetooth")
        #expect(RecoveryAction.requestAuthorization.rawValue == "requestAuthorization")
        #expect(RecoveryAction.initiatePairing.rawValue == "initiatePairing")
        #expect(RecoveryAction.moveCloser.rawValue == "moveCloser")
        #expect(RecoveryAction.abort.rawValue == "abort")
        #expect(RecoveryAction.unknown.rawValue == "unknown")
    }
    
    @Test("Action is case iterable")
    func actionCaseIterable() {
        #expect(RecoveryAction.allCases.count == 7)
    }
}

@Suite("Error Pattern Tracker")
struct ErrorPatternTrackerTests {
    
    @Test("Track errors")
    func trackErrors() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        await tracker.record(.connectionTimeout)
        await tracker.record(.connectionTimeout)
        await tracker.record(.disconnected)
        
        let counts = await tracker.errorCounts()
        #expect(counts[.transient] == 3)
    }
    
    @Test("Track multiple categories")
    func trackMultipleCategories() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        await tracker.record(.connectionTimeout)
        await tracker.record(.unsupported)
        
        let counts = await tracker.errorCounts()
        #expect(counts[.transient] == 1)
        #expect(counts[.permanent] == 1)
    }
    
    @Test("Circuit breaker trips on transient threshold")
    func circuitBreakerTransient() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        // Record 10 transient errors
        for _ in 0..<10 {
            await tracker.record(.connectionTimeout)
        }
        
        let shouldTrip = await tracker.shouldTripCircuitBreaker(transientThreshold: 10)
        #expect(shouldTrip == true)
    }
    
    @Test("Circuit breaker trips on permanent threshold")
    func circuitBreakerPermanent() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        // Record 3 permanent errors
        for _ in 0..<3 {
            await tracker.record(.unsupported)
        }
        
        let shouldTrip = await tracker.shouldTripCircuitBreaker(permanentThreshold: 3)
        #expect(shouldTrip == true)
    }
    
    @Test("Circuit breaker does not trip under threshold")
    func circuitBreakerNoTrip() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        await tracker.record(.connectionTimeout)
        await tracker.record(.unsupported)
        
        let shouldTrip = await tracker.shouldTripCircuitBreaker(
            transientThreshold: 10,
            permanentThreshold: 3
        )
        #expect(shouldTrip == false)
    }
    
    @Test("Reset clears history")
    func resetClearsHistory() async {
        let tracker = ErrorPatternTracker(windowDuration: 60)
        
        await tracker.record(.connectionTimeout)
        await tracker.reset()
        
        let counts = await tracker.errorCounts()
        #expect(counts[.transient] == nil)
    }
}
