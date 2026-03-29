// SPDX-License-Identifier: MIT
//
// LibreTimeoutTests.swift
// CGMKitTests
//
// Tests for Libre timeout handling using synthesized fixtures.
// Trace: LIBRE-FIX-014

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

// MARK: - Libre Timeout Fixture Types

struct LibreTimeoutFixture: Codable {
    let sessionId: String
    let sessionName: String
    let timeoutScenarios: [LibreTimeoutScenario]
    let retryConfiguration: LibreRetryConfiguration
    let testVectors: [LibreTimeoutTestVector]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionName = "session_name"
        case timeoutScenarios = "timeout_scenarios"
        case retryConfiguration = "retry_configuration"
        case testVectors = "test_vectors"
    }
}

struct LibreTimeoutScenario: Codable {
    let scenarioId: String
    let name: String
    let description: String
    let triggerState: String
    let timeoutAfterS: Double
    let faultType: String
    
    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case name
        case description
        case triggerState = "trigger_state"
        case timeoutAfterS = "timeout_after_s"
        case faultType = "fault_type"
    }
}

struct LibreRetryConfiguration: Codable {
    let maxConnectionRetries: Int
    let maxUnlockRetries: Int
    let maxCommandRetries: Int
    let retryDelayS: Double
    let exponentialBackoff: Bool
    
    enum CodingKeys: String, CodingKey {
        case maxConnectionRetries = "max_connection_retries"
        case maxUnlockRetries = "max_unlock_retries"
        case maxCommandRetries = "max_command_retries"
        case retryDelayS = "retry_delay_s"
        case exponentialBackoff = "exponential_backoff"
    }
}

struct LibreTimeoutTestVector: Codable {
    let name: String
    let scenario: String?
    let initialState: String?
    let expectedState: String?
    let expectedFaultType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case scenario
        case initialState = "initial_state"
        case expectedState = "expected_state"
        case expectedFaultType = "expected_fault_type"
    }
}

// MARK: - Fixture Loading

enum LibreFixtureError: Error {
    case notFound(String)
    case decodingFailed(String)
}

func loadLibreTimeoutFixture() throws -> LibreTimeoutFixture {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fixture_libre_timeout", withExtension: "json", subdirectory: "Fixtures") else {
        throw LibreFixtureError.notFound("fixture_libre_timeout.json")
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(LibreTimeoutFixture.self, from: data)
}

// MARK: - Timeout Tests

@Suite("Libre Timeout Handling Tests")
struct LibreTimeoutTests {
    
    @Test("Timeout fixture loads successfully")
    func testFixtureLoads() throws {
        let fixture = try loadLibreTimeoutFixture()
        #expect(fixture.sessionId == "SESSION-LIBRE-TIMEOUT-001")
        #expect(!fixture.timeoutScenarios.isEmpty)
    }
    
    @Test("Fixture contains expected timeout scenarios")
    func testTimeoutScenariosExist() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        let scenarioIds = fixture.timeoutScenarios.map { $0.scenarioId }
        #expect(scenarioIds.contains("TIMEOUT-001")) // Scan timeout
        #expect(scenarioIds.contains("TIMEOUT-002")) // Connection timeout
        #expect(scenarioIds.contains("TIMEOUT-004")) // Unlock timeout
        #expect(scenarioIds.contains("TIMEOUT-005")) // Glucose request timeout
    }
    
    @Test("Retry configuration is valid")
    func testRetryConfiguration() throws {
        let fixture = try loadLibreTimeoutFixture()
        let config = fixture.retryConfiguration
        
        #expect(config.maxConnectionRetries >= 1)
        #expect(config.maxConnectionRetries <= 10)
        #expect(config.maxUnlockRetries >= 1)
        #expect(config.retryDelayS > 0)
    }
    
    @Test("Exponential backoff is enabled")
    func testExponentialBackoff() throws {
        let fixture = try loadLibreTimeoutFixture()
        #expect(fixture.retryConfiguration.exponentialBackoff == true)
    }
    
    @Test("Timeout triggers state transition to error")
    func testTimeoutStateTransition() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        // Find the state machine test vector
        if let vector = fixture.testVectors.first(where: { $0.name == "State machine on timeout" }) {
            #expect(vector.initialState == "unlocking")
            #expect(vector.expectedState == "error")
        }
    }
    
    @Test("Unlock timeout scenario has correct fault type")
    func testUnlockTimeoutFaultType() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        let unlockScenario = fixture.timeoutScenarios.first { $0.scenarioId == "TIMEOUT-004" }
        #expect(unlockScenario != nil)
        #expect(unlockScenario?.faultType == "unlockTimeout")
        #expect(unlockScenario?.triggerState == "unlocking")
    }
    
    @Test("NFC required scenario exists")
    func testNFCRequiredScenario() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        let nfcScenario = fixture.timeoutScenarios.first { $0.scenarioId == "TIMEOUT-007" }
        #expect(nfcScenario != nil)
        #expect(nfcScenario?.faultType == "nfcRequired")
        #expect(nfcScenario?.name.contains("NFC") == true)
    }
}

// MARK: - Retry Behavior Tests

@Suite("Libre Retry Behavior Tests")
struct LibreRetryBehaviorTests {
    
    @Test("Connection retry count from fixture")
    func testConnectionRetryCount() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        // Verify the retry count matches Libre manager behavior
        #expect(fixture.retryConfiguration.maxConnectionRetries == 3)
    }
    
    @Test("Unlock retry count from fixture")
    func testUnlockRetryCount() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        #expect(fixture.retryConfiguration.maxUnlockRetries == 2)
    }
    
    @Test("Retry delay is reasonable")
    func testRetryDelay() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        // Delay should be 2 seconds
        #expect(fixture.retryConfiguration.retryDelayS == 2.0)
    }
    
    @Test("Test vectors include retry sequence")
    func testRetrySequenceVector() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        let retryVector = fixture.testVectors.first { $0.name == "Retry count tracking" }
        #expect(retryVector != nil)
        #expect(retryVector?.scenario == "TIMEOUT-002")
    }
}

// MARK: - Integration with Fault Injector

@Suite("Libre Fixture-FaultInjector Integration")
struct LibreFixtureFaultIntegrationTests {
    
    @Test("Timeout scenarios map to fault types")
    func testTimeoutToFaultMapping() throws {
        let fixture = try loadLibreTimeoutFixture()
        
        // Map fixture scenarios to LibreFaultType
        let scenarioToFault: [String: LibreFaultType] = [
            "TIMEOUT-001": .scanTimeout,
            "TIMEOUT-002": .connectionTimeout,
            "TIMEOUT-003": .connectionTimeout,
            "TIMEOUT-004": .unlockTimeout,
            "TIMEOUT-005": .connectionTimeout,
            "TIMEOUT-006": .connectionTimeout,
            "TIMEOUT-007": .nfcRequired
        ]
        
        for scenario in fixture.timeoutScenarios {
            if let expectedFault = scenarioToFault[scenario.scenarioId] {
                // Verify the fault type string matches
                #expect(scenario.faultType == faultTypeString(expectedFault))
            }
        }
    }
    
    @Test("Fault injector has preset for unlock timeout")
    func testUnlockTimeoutPreset() {
        let injector = LibreFaultInjector.unlockTimeout
        
        #expect(!injector.faults.isEmpty)
        #expect(injector.faults.first?.fault == .unlockTimeout)
    }
    
    @Test("Fault injector has preset for NFC required")
    func testNFCRequiredPreset() {
        let injector = LibreFaultInjector.nfcRequired
        
        #expect(!injector.faults.isEmpty)
        #expect(injector.faults.first?.fault == .nfcRequired)
    }
    
    @Test("Fault types have stopsStreaming property")
    func testFaultStopsStreaming() {
        // These faults stop streaming (critical authentication/connection failures)
        #expect(LibreFaultType.unlockTimeout.stopsStreaming == true)
        #expect(LibreFaultType.connectionTimeout.stopsStreaming == true)
        
        // These faults don't stop streaming (recoverable states)
        #expect(LibreFaultType.scanTimeout.stopsStreaming == false)
        #expect(LibreFaultType.nfcRequired.stopsStreaming == false)
    }
    
    @Test("Fault types have correct category")
    func testFaultCategories() {
        #expect(LibreFaultType.unlockTimeout.category == .authentication)
        #expect(LibreFaultType.connectionTimeout.category == .connection)
        #expect(LibreFaultType.scanTimeout.category == .connection)
        #expect(LibreFaultType.nfcRequired.category == .connection)
    }
}

// MARK: - Helper

private func faultTypeString(_ fault: LibreFaultType) -> String {
    switch fault {
    case .unlockTimeout: return "unlockTimeout"
    case .unlockRejected: return "unlockRejected"
    case .cryptoFailed: return "cryptoFailed"
    case .unlockCountMismatch: return "unlockCountMismatch"
    case .connectionDrop: return "connectionDrop"
    case .connectionTimeout: return "connectionTimeout"
    case .scanTimeout: return "scanTimeout"
    case .nfcRequired: return "nfcRequired"
    case .sensorExpired: return "sensorExpired"
    case .sensorWarmup: return "sensorWarmup"
    case .sensorFailed: return "sensorFailed"
    case .sensorNotActivated: return "sensorNotActivated"
    case .sensorReplaced: return "sensorReplaced"
    case .packetCorruption: return "packetCorruption"
    case .responseDelay: return "responseDelay"
    case .characteristicNotFound: return "characteristicNotFound"
    case .invalidDataFrame: return "invalidDataFrame"
    case .regionLocked: return "regionLocked"
    case .firmwareUnsupported: return "firmwareUnsupported"
    case .patchInfoMismatch: return "patchInfoMismatch"
    }
}
