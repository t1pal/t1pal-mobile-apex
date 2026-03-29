// FailureClassifierTests.swift - Tests for failure mode classification
// Part of BLEKit
// Trace: EVID-005

import Foundation
import Testing
@testable import BLEKit

// MARK: - Failure Mode Tests

@Suite("Failure Mode")
struct FailureModeTests {
    
    @Test("All failure modes exist")
    func allModes() {
        #expect(FailureMode.allCases.count == 34)
    }
    
    @Test("Each mode has a category")
    func modesHaveCategories() {
        for mode in FailureMode.allCases {
            let category = mode.category
            #expect(ErrorCategory.allCases.contains(category))
        }
    }
    
    @Test("Each mode has a display name")
    func modesHaveDisplayNames() {
        for mode in FailureMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }
    
    @Test("Each mode has remediation")
    func modesHaveRemediation() {
        for mode in FailureMode.allCases {
            #expect(!mode.remediation.isEmpty)
        }
    }
    
    @Test("Severity is 1-5")
    func severityRange() {
        for mode in FailureMode.allCases {
            #expect(mode.severity >= 1 && mode.severity <= 5)
        }
    }
    
    @Test("Connection modes map to connection category")
    func connectionCategory() {
        #expect(FailureMode.connectionTimeout.category == .connection)
        #expect(FailureMode.connectionRefused.category == .connection)
        #expect(FailureMode.connectionDropped.category == .connection)
        #expect(FailureMode.deviceNotFound.category == .connection)
    }
    
    @Test("Auth modes map to authentication category")
    func authCategory() {
        #expect(FailureMode.authenticationFailed.category == .authentication)
        #expect(FailureMode.invalidCredentials.category == .authentication)
        #expect(FailureMode.pairingFailed.category == .authentication)
    }
    
    @Test("Protocol modes map to protocol category")
    func protocolCategory() {
        #expect(FailureMode.protocolMismatch.category == .protocol_)
        #expect(FailureMode.invalidResponse.category == .protocol_)
        #expect(FailureMode.checksumError.category == .protocol_)
    }
    
    @Test("Timeout modes map to timeout category")
    func timeoutCategory() {
        #expect(FailureMode.writeTimeout.category == .timeout)
        #expect(FailureMode.readTimeout.category == .timeout)
        #expect(FailureMode.notifyTimeout.category == .timeout)
    }
}

// MARK: - Classified Failure Tests

@Suite("Classified Failure")
struct ClassifiedFailureTests {
    
    @Test("Create classified failure")
    func create() {
        let failure = ClassifiedFailure(
            mode: .connectionTimeout,
            message: "Connection timed out"
        )
        
        #expect(failure.mode == .connectionTimeout)
        #expect(failure.message == "Connection timed out")
        #expect(failure.confidence == 1.0)
    }
    
    @Test("Confidence is clamped")
    func confidenceClamped() {
        let tooHigh = ClassifiedFailure(mode: .unknown, confidence: 1.5)
        let tooLow = ClassifiedFailure(mode: .unknown, confidence: -0.5)
        
        #expect(tooHigh.confidence == 1.0)
        #expect(tooLow.confidence == 0.0)
    }
    
    @Test("Failure is Codable")
    func codable() throws {
        let failure = ClassifiedFailure(
            mode: .authenticationFailed,
            message: "Auth failed",
            code: 42,
            context: ["device": "G7"]
        )
        
        let encoded = try JSONEncoder().encode(failure)
        let decoded = try JSONDecoder().decode(ClassifiedFailure.self, from: encoded)
        
        #expect(decoded.mode == failure.mode)
        #expect(decoded.message == failure.message)
        #expect(decoded.code == failure.code)
    }
    
    @Test("Failure is Equatable")
    func equatable() {
        let failure1 = ClassifiedFailure(mode: .connectionTimeout)
        let failure2 = ClassifiedFailure(mode: .connectionTimeout)
        let failure3 = ClassifiedFailure(mode: .authenticationFailed)
        
        #expect(failure1.mode == failure2.mode)
        #expect(failure1.mode != failure3.mode)
    }
}

// MARK: - Pattern Classification Tests

@Suite("Pattern Classification")
struct PatternClassificationTests {
    
    @Test("Classify connection timeout")
    func classifyConnectionTimeout() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Operation timed out")
        
        #expect(result.mode == .connectionTimeout)
        #expect(result.confidence > 0.8)
    }
    
    @Test("Classify connection refused")
    func classifyConnectionRefused() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Connection refused by peer")
        
        #expect(result.mode == .connectionRefused)
    }
    
    @Test("Classify connection dropped")
    func classifyConnectionDropped() {
        let classifier = FailureClassifier()
        
        let result1 = classifier.classify("Device disconnected unexpectedly")
        let result2 = classifier.classify("Connection lost")
        
        #expect(result1.mode == .connectionDropped)
        #expect(result2.mode == .connectionDropped)
    }
    
    @Test("Classify device not found")
    func classifyDeviceNotFound() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Device not found in scan")
        
        #expect(result.mode == .deviceNotFound)
    }
    
    @Test("Classify bluetooth disabled")
    func classifyBluetoothDisabled() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Bluetooth is disabled")
        
        #expect(result.mode == .bluetoothDisabled)
    }
    
    @Test("Classify authentication failed")
    func classifyAuthFailed() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Authentication failed: wrong code")
        
        #expect(result.mode == .authenticationFailed)
    }
    
    @Test("Classify invalid credentials")
    func classifyInvalidCredentials() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Invalid password entered")
        
        #expect(result.mode == .invalidCredentials)
    }
    
    @Test("Classify pairing failed")
    func classifyPairingFailed() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Pairing failed with device")
        
        #expect(result.mode == .pairingFailed)
    }
    
    @Test("Classify protocol mismatch")
    func classifyProtocolMismatch() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Unsupported protocol version")
        
        #expect(result.mode == .protocolMismatch)
    }
    
    @Test("Classify checksum error")
    func classifyChecksumError() {
        let classifier = FailureClassifier()
        
        let result1 = classifier.classify("Checksum mismatch in packet")
        let result2 = classifier.classify("CRC error detected")
        
        #expect(result1.mode == .checksumError)
        #expect(result2.mode == .checksumError)
    }
    
    @Test("Classify sensor expired")
    func classifySensorExpired() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Sensor expired - session ended")
        
        #expect(result.mode == .sensorExpired)
    }
    
    @Test("Classify battery low")
    func classifyBatteryLow() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Battery low warning")
        
        #expect(result.mode == .batteryLow)
    }
    
    @Test("Unknown message returns unknown mode")
    func classifyUnknown() {
        let classifier = FailureClassifier()
        
        let result = classifier.classify("Some random unrecognized error")
        
        #expect(result.mode == .unknown)
        #expect(result.confidence < 1.0)
    }
    
    @Test("Case insensitive matching")
    func caseInsensitive() {
        let classifier = FailureClassifier()
        
        let result1 = classifier.classify("TIMEOUT ERROR")
        let result2 = classifier.classify("Timeout Error")
        let result3 = classifier.classify("timeout error")
        
        #expect(result1.mode == .connectionTimeout)
        #expect(result2.mode == .connectionTimeout)
        #expect(result3.mode == .connectionTimeout)
    }
}

// MARK: - Code Classification Tests

@Suite("Code Classification")
struct CodeClassificationTests {
    
    @Test("Classify common BLE error codes")
    func classifyErrorCodes() {
        let classifier = FailureClassifier()
        
        #expect(classifier.classifyCode(6).mode == .connectionTimeout)
        #expect(classifier.classifyCode(7).mode == .connectionDropped)
        #expect(classifier.classifyCode(10).mode == .connectionRefused)
        #expect(classifier.classifyCode(12).mode == .deviceNotFound)
        #expect(classifier.classifyCode(14).mode == .pairingFailed)
        #expect(classifier.classifyCode(15).mode == .authenticationTimeout)
    }
    
    @Test("Unknown code returns unknown mode")
    func unknownCode() {
        let classifier = FailureClassifier()
        
        let result = classifier.classifyCode(999)
        
        #expect(result.mode == .unknown)
        #expect(result.confidence < 0.5)
    }
    
    @Test("Code is preserved in result")
    func codePreserved() {
        let classifier = FailureClassifier()
        
        let result = classifier.classifyCode(42)
        
        #expect(result.code == 42)
    }
}

// MARK: - Batch Classification Tests

@Suite("Batch Classification")
struct BatchClassificationTests {
    
    @Test("Classify multiple messages")
    func classifyAll() {
        let classifier = FailureClassifier()
        let messages = [
            "Connection timed out",
            "Authentication failed",
            "Sensor expired"
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.totalClassified == 3)
        #expect(result.failures.count == 3)
    }
    
    @Test("Mode breakdown computed")
    func modeBreakdown() {
        let classifier = FailureClassifier()
        let messages = [
            "Timeout error",
            "Timeout again",
            "Auth failed"
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.modeBreakdown["connectionTimeout"] == 2)
        #expect(result.modeBreakdown["authenticationFailed"] == 1)
    }
    
    @Test("Category breakdown computed")
    func categoryBreakdown() {
        let classifier = FailureClassifier()
        let messages = [
            "Read timeout occurred",   // writeTimeout pattern -> timeout category
            "Auth failed",
            "Pairing failed"
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.categoryBreakdown["timeout"] == 1)
        #expect(result.categoryBreakdown["authentication"] == 2)
    }
    
    @Test("Severity breakdown computed")
    func severityBreakdown() {
        let classifier = FailureClassifier()
        let messages = [
            "Connection timeout",  // Severity 2
            "Bluetooth disabled"   // Severity 5
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.severityBreakdown[2] == 1)
        #expect(result.severityBreakdown[5] == 1)
    }
    
    @Test("Most common mode identified")
    func mostCommonMode() {
        let classifier = FailureClassifier()
        let messages = [
            "Timeout",
            "Timeout",
            "Timeout",
            "Auth failed"
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.mostCommonMode == .connectionTimeout)
    }
    
    @Test("Top remediation provided")
    func topRemediation() {
        let classifier = FailureClassifier()
        let messages = ["Bluetooth is disabled"]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.topRemediation != nil)
        #expect(result.topRemediation!.contains("Enable Bluetooth"))
    }
    
    @Test("Average severity computed")
    func averageSeverity() {
        let classifier = FailureClassifier()
        let messages = [
            "Device busy",     // Severity 1
            "Timeout"          // Severity 2
        ]
        
        let result = classifier.classifyAll(messages)
        
        #expect(result.averageSeverity == 1.5)
    }
    
    @Test("Empty input returns empty result")
    func emptyInput() {
        let classifier = FailureClassifier()
        
        let result = classifier.classifyAll([])
        
        #expect(result == .empty)
    }
}

// MARK: - Classification Result Tests

@Suite("Classification Result")
struct ClassificationResultTests {
    
    @Test("Empty result")
    func emptyResult() {
        let result = ClassificationResult.empty
        
        #expect(result.totalClassified == 0)
        #expect(result.mostCommonMode == nil)
        #expect(result.failures.isEmpty)
    }
    
    @Test("Result is Codable")
    func codable() throws {
        let classifier = FailureClassifier()
        let result = classifier.classifyAll(["Timeout", "Auth failed"])
        
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ClassificationResult.self, from: encoded)
        
        #expect(decoded.totalClassified == result.totalClassified)
    }
}

// MARK: - Trend Analysis Tests

@Suite("Trend Analysis")
struct TrendAnalysisTests {
    
    @Test("Analyze failure trends")
    func analyzeTrends() {
        let classifier = FailureClassifier()
        let now = Date()
        
        let failures = [
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now.addingTimeInterval(-3600)),
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now.addingTimeInterval(-1800)),
            ClassifiedFailure(mode: .authenticationFailed, timestamp: now)
        ]
        
        let analysis = classifier.analyzeTrends(failures)
        
        #expect(analysis.totalFailures == 3)
        #expect(analysis.failuresPerHour > 0)
    }
    
    @Test("Peak hour identified")
    func peakHour() {
        let classifier = FailureClassifier()
        // Use a fixed date in the middle of an hour to avoid boundary issues
        let baseDate = Date(timeIntervalSince1970: 1000000 + 1800) // Middle of hour
        
        let failures = [
            ClassifiedFailure(mode: .connectionTimeout, timestamp: baseDate),
            ClassifiedFailure(mode: .connectionTimeout, timestamp: baseDate.addingTimeInterval(60)),
            ClassifiedFailure(mode: .connectionTimeout, timestamp: baseDate.addingTimeInterval(120)),
            ClassifiedFailure(mode: .authenticationFailed, timestamp: baseDate.addingTimeInterval(-7200))
        ]
        
        let analysis = classifier.analyzeTrends(failures)
        
        #expect(analysis.peakHour != nil)
        #expect(analysis.peakHourCount >= 3)
    }
    
    @Test("Empty failures returns empty analysis")
    func emptyFailures() {
        let classifier = FailureClassifier()
        
        let analysis = classifier.analyzeTrends([])
        
        #expect(analysis.totalFailures == 0)
    }
}

// MARK: - Correlation Tests

@Suite("Failure Correlation")
struct FailureCorrelationTests {
    
    @Test("Find correlated failures")
    func findCorrelations() {
        let classifier = FailureClassifier()
        let now = Date()
        
        let failures = [
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now),
            ClassifiedFailure(mode: .authenticationFailed, timestamp: now.addingTimeInterval(5)),
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now.addingTimeInterval(100)),
            ClassifiedFailure(mode: .authenticationFailed, timestamp: now.addingTimeInterval(105))
        ]
        
        let correlations = classifier.findCorrelations(failures)
        
        #expect(!correlations.isEmpty)
    }
    
    @Test("Correlation has count")
    func correlationCount() {
        let classifier = FailureClassifier()
        let now = Date()
        
        // Same pair occurs twice
        let failures = [
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now),
            ClassifiedFailure(mode: .connectionDropped, timestamp: now.addingTimeInterval(2)),
            ClassifiedFailure(mode: .connectionTimeout, timestamp: now.addingTimeInterval(100)),
            ClassifiedFailure(mode: .connectionDropped, timestamp: now.addingTimeInterval(102))
        ]
        
        let correlations = classifier.findCorrelations(failures)
        let pair = correlations.first { 
            ($0.mode1 == .connectionTimeout || $0.mode2 == .connectionTimeout) &&
            ($0.mode1 == .connectionDropped || $0.mode2 == .connectionDropped)
        }
        
        #expect(pair != nil)
        #expect(pair!.cooccurrenceCount >= 2)
    }
    
    @Test("Potentially causal detection")
    func potentiallyCausal() {
        let correlation = FailureCorrelation(
            mode1: .connectionTimeout,
            mode2: .connectionDropped,
            cooccurrenceCount: 5,
            averageTimeDelta: 2.0
        )
        
        #expect(correlation.potentiallyCausal == true)
    }
    
    @Test("Not causal if time delta too large")
    func notCausalLargeDelta() {
        let correlation = FailureCorrelation(
            mode1: .connectionTimeout,
            mode2: .connectionDropped,
            cooccurrenceCount: 5,
            averageTimeDelta: 30.0
        )
        
        #expect(correlation.potentiallyCausal == false)
    }
    
    @Test("No correlations for single failure")
    func singleFailure() {
        let classifier = FailureClassifier()
        let failures = [ClassifiedFailure(mode: .connectionTimeout)]
        
        let correlations = classifier.findCorrelations(failures)
        
        #expect(correlations.isEmpty)
    }
}

// MARK: - Custom Pattern Tests

@Suite("Custom Patterns")
struct CustomPatternTests {
    
    @Test("Add custom patterns")
    func customPatterns() {
        let customPattern = FailurePattern(
            name: "custom_error",
            pattern: "CUSTOM_ERR_\\d+",
            mode: .firmwareError
        )
        
        let classifier = FailureClassifier.withAdditionalPatterns([customPattern])
        let result = classifier.classify("CUSTOM_ERR_42")
        
        #expect(result.mode == .firmwareError)
    }
    
    @Test("Custom patterns don't override defaults")
    func customWithDefaults() {
        let customPattern = FailurePattern(
            name: "custom",
            pattern: "MY_CUSTOM_ERROR",
            mode: .unknown
        )
        
        let classifier = FailureClassifier.withAdditionalPatterns([customPattern])
        
        // Default patterns still work
        let result = classifier.classify("Connection timeout")
        #expect(result.mode == .connectionTimeout)
    }
}
