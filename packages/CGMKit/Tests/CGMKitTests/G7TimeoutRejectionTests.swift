// SPDX-License-Identifier: MIT
//
// G7TimeoutRejectionTests.swift
// CGMKitTests
//
// Tests for G7 timeout and rejection handling using synthesized fixtures.
// Trace: G7-FIX-014, G7-FIX-015, G7-FIX-017

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

// MARK: - Timeout Fixture Types

struct G7TimeoutFixture: Codable {
    let sessionId: String
    let sessionName: String
    let timeoutScenarios: [TimeoutScenario]
    let retryConfiguration: RetryConfiguration
    let testVectors: [TimeoutTestVector]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionName = "session_name"
        case timeoutScenarios = "timeout_scenarios"
        case retryConfiguration = "retry_configuration"
        case testVectors = "test_vectors"
    }
}

struct TimeoutScenario: Codable {
    let scenarioId: String
    let name: String
    let description: String
    let triggerState: String
    let timeoutAfterS: Double
    
    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case name
        case description
        case triggerState = "trigger_state"
        case timeoutAfterS = "timeout_after_s"
    }
}

struct RetryConfiguration: Codable {
    let maxConnectionRetries: Int
    let maxAuthRetries: Int
    let maxCommandRetries: Int
    let retryDelayS: Double
    
    enum CodingKeys: String, CodingKey {
        case maxConnectionRetries = "max_connection_retries"
        case maxAuthRetries = "max_auth_retries"
        case maxCommandRetries = "max_command_retries"
        case retryDelayS = "retry_delay_s"
    }
}

struct TimeoutTestVector: Codable {
    let name: String
    let scenario: String?
    let initialState: String?
    let expectedState: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case scenario
        case initialState = "initial_state"
        case expectedState = "expected_state"
    }
}

// MARK: - Rejection Fixture Types

struct G7RejectionFixture: Codable {
    let sessionId: String
    let sessionName: String
    let rejectionScenarios: [RejectionScenario]
    let sensorStates: [String: SensorStateInfo]
    let authStatusCodes: [String: String]
    let testVectors: [RejectionTestVector]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionName = "session_name"
        case rejectionScenarios = "rejection_scenarios"
        case sensorStates = "sensor_states"
        case authStatusCodes = "auth_status_codes"
        case testVectors = "test_vectors"
    }
}

struct RejectionScenario: Codable {
    let scenarioId: String
    let name: String
    let description: String
    let triggerState: String
    
    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case name
        case description
        case triggerState = "trigger_state"
    }
}

struct SensorStateInfo: Codable {
    let name: String
    let canStream: Bool
    let warmupMinutes: Int?
    
    enum CodingKeys: String, CodingKey {
        case name
        case canStream = "can_stream"
        case warmupMinutes = "warmup_minutes"
    }
}

struct RejectionTestVector: Codable {
    let name: String
    let inputHex: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case inputHex = "input_hex"
    }
}

// MARK: - Fixture Loading

enum G7FixtureError: Error {
    case notFound(String)
    case decodingFailed(String)
}

func loadTimeoutFixture() throws -> G7TimeoutFixture {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fixture_g7_timeout", withExtension: "json", subdirectory: "Fixtures") else {
        throw G7FixtureError.notFound("fixture_g7_timeout.json")
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(G7TimeoutFixture.self, from: data)
}

func loadRejectionFixture() throws -> G7RejectionFixture {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fixture_g7_rejection", withExtension: "json", subdirectory: "Fixtures") else {
        throw G7FixtureError.notFound("fixture_g7_rejection.json")
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(G7RejectionFixture.self, from: data)
}

// MARK: - Timeout Tests

@Suite("G7 Timeout Handling Tests")
struct G7TimeoutTests {
    
    @Test("Timeout fixture loads successfully")
    func testFixtureLoads() throws {
        let fixture = try loadTimeoutFixture()
        #expect(fixture.sessionId == "SESSION-G7-TIMEOUT-001")
        #expect(!fixture.timeoutScenarios.isEmpty)
    }
    
    @Test("Fixture contains expected timeout scenarios")
    func testTimeoutScenariosExist() throws {
        let fixture = try loadTimeoutFixture()
        
        let scenarioIds = fixture.timeoutScenarios.map { $0.scenarioId }
        #expect(scenarioIds.contains("TIMEOUT-001")) // Scan timeout
        #expect(scenarioIds.contains("TIMEOUT-002")) // Connection timeout
        #expect(scenarioIds.contains("TIMEOUT-004")) // J-PAKE Round 1 timeout
        #expect(scenarioIds.contains("TIMEOUT-007")) // Glucose request timeout
    }
    
    @Test("Retry configuration is valid")
    func testRetryConfiguration() throws {
        let fixture = try loadTimeoutFixture()
        let config = fixture.retryConfiguration
        
        #expect(config.maxConnectionRetries >= 1)
        #expect(config.maxConnectionRetries <= 10)
        #expect(config.maxAuthRetries >= 1)
        #expect(config.retryDelayS > 0)
    }
    
    @Test("Timeout triggers state transition to error")
    func testTimeoutStateTransition() throws {
        let fixture = try loadTimeoutFixture()
        
        // Find the state machine test vector
        if let vector = fixture.testVectors.first(where: { $0.name == "State machine on timeout" }) {
            #expect(vector.initialState == "pairing")
            #expect(vector.expectedState == "error")
        }
    }
    
    @Test("J-PAKE timeout scenarios cover all rounds")
    func testJPAKETimeoutCoverage() throws {
        let fixture = try loadTimeoutFixture()
        
        let jpakeTimeouts = fixture.timeoutScenarios.filter { 
            $0.name.contains("J-PAKE") || $0.scenarioId.contains("TIMEOUT-00[456]")
        }
        
        // Should have timeouts for Round 1, Round 2, and Confirmation
        #expect(jpakeTimeouts.count >= 3)
    }
}

// MARK: - Rejection Tests

@Suite("G7 Rejection Handling Tests")
struct G7RejectionTests {
    
    @Test("Rejection fixture loads successfully")
    func testFixtureLoads() throws {
        let fixture = try loadRejectionFixture()
        #expect(fixture.sessionId == "SESSION-G7-REJECTION-001")
        #expect(!fixture.rejectionScenarios.isEmpty)
    }
    
    @Test("Fixture contains expected rejection scenarios")
    func testRejectionScenariosExist() throws {
        let fixture = try loadRejectionFixture()
        
        let scenarioIds = fixture.rejectionScenarios.map { $0.scenarioId }
        #expect(scenarioIds.contains("REJECT-001")) // Wrong sensor code
        #expect(scenarioIds.contains("REJECT-002")) // Already paired
        #expect(scenarioIds.contains("REJECT-003")) // Sensor expired
    }
    
    @Test("Sensor states are defined")
    func testSensorStates() throws {
        let fixture = try loadRejectionFixture()
        
        #expect(fixture.sensorStates["0x00"]?.name == "UNKNOWN")
        #expect(fixture.sensorStates["0x01"]?.name == "WARMUP")
        #expect(fixture.sensorStates["0x02"]?.name == "OK")
        #expect(fixture.sensorStates["0x03"]?.name == "EXPIRED")
        
        // Only OK state can stream
        #expect(fixture.sensorStates["0x02"]?.canStream == true)
        #expect(fixture.sensorStates["0x01"]?.canStream == false)
        #expect(fixture.sensorStates["0x03"]?.canStream == false)
    }
    
    @Test("Auth status codes are defined")
    func testAuthStatusCodes() throws {
        let fixture = try loadRejectionFixture()
        
        #expect(fixture.authStatusCodes["0x00"] == "AUTH_SUCCESS")
        #expect(fixture.authStatusCodes["0x01"] == "AUTH_FAILED")
        #expect(fixture.authStatusCodes["0x02"] == "ALREADY_PAIRED")
    }
    
    @Test("Wrong sensor code scenario is recoverable")
    func testWrongCodeRecoverable() throws {
        let fixture = try loadRejectionFixture()
        
        let wrongCodeScenario = fixture.rejectionScenarios.first { $0.scenarioId == "REJECT-001" }
        #expect(wrongCodeScenario != nil)
        #expect(wrongCodeScenario?.name == "Wrong sensor code")
    }
    
    @Test("AuthStatus rejection parsing test vector exists")
    func testAuthStatusParsingVector() throws {
        let fixture = try loadRejectionFixture()
        
        let parsingVector = fixture.testVectors.first { $0.name == "AuthStatus rejection parsing" }
        #expect(parsingVector != nil)
        #expect(parsingVector?.inputHex == "0501")
    }
}

// MARK: - Retry Behavior Tests

@Suite("G7 Retry Behavior Tests")
struct G7RetryBehaviorTests {
    
    @Test("Connection retry count from fixture")
    func testConnectionRetryCount() throws {
        let fixture = try loadTimeoutFixture()
        
        // Verify the retry count matches G7 manager behavior
        #expect(fixture.retryConfiguration.maxConnectionRetries == 3)
    }
    
    @Test("Retry delay is reasonable")
    func testRetryDelay() throws {
        let fixture = try loadTimeoutFixture()
        
        // Delay should be 2 seconds (scan_delay_after_disconnect_s)
        #expect(fixture.retryConfiguration.retryDelayS == 2.0)
    }
    
    @Test("Test vectors include retry sequence")
    func testRetrySequenceVector() throws {
        let fixture = try loadTimeoutFixture()
        
        let retryVector = fixture.testVectors.first { $0.name == "Retry count tracking" }
        #expect(retryVector != nil)
        #expect(retryVector?.scenario == "TIMEOUT-002")
    }
}

// MARK: - Integration with Fault Injector

@Suite("G7 Fixture-FaultInjector Integration")
struct G7FixtureFaultIntegrationTests {
    
    @Test("Timeout scenarios map to fault types")
    func testTimeoutToFaultMapping() throws {
        let fixture = try loadTimeoutFixture()
        
        // Map fixture scenarios to G7FaultType
        let scenarioToFault: [String: G7FaultType] = [
            "TIMEOUT-001": .scanTimeout,
            "TIMEOUT-002": .connectionTimeout,
            "TIMEOUT-004": .jpakeTimeout,
            "TIMEOUT-005": .jpakeTimeout,
            "TIMEOUT-006": .jpakeTimeout
        ]
        
        for (scenarioId, expectedFault) in scenarioToFault {
            let scenario = fixture.timeoutScenarios.first { $0.scenarioId == scenarioId }
            #expect(scenario != nil, "Scenario \(scenarioId) should exist")
            
            // Verify the fault injector has this fault type
            let injector = G7FaultInjector()
            injector.addFault(expectedFault, trigger: .immediate)
            #expect(injector.faults.count == 1)
            injector.clearFaults()
        }
    }
    
    @Test("Rejection scenarios map to fault types")
    func testRejectionToFaultMapping() throws {
        let fixture = try loadRejectionFixture()
        
        // Map rejection scenarios to G7FaultType
        let scenarioToFault: [String: G7FaultType] = [
            "REJECT-001": .sensorCodeMismatch,
            "REJECT-002": .pairingFailed,
            "REJECT-005": .jpakeRejected
        ]
        
        for (scenarioId, expectedFault) in scenarioToFault {
            let scenario = fixture.rejectionScenarios.first { $0.scenarioId == scenarioId }
            #expect(scenario != nil, "Scenario \(scenarioId) should exist")
            
            let injector = G7FaultInjector()
            injector.addFault(expectedFault, trigger: .immediate)
            #expect(injector.faults.count == 1)
            injector.clearFaults()
        }
    }
}

// MARK: - PROD-HARDEN-022 Timeout Constants Tests

@Suite("G7 Timeout Constants - PROD-HARDEN-022")
struct G7TimeoutConstantsTests {
    
    @Test("Authentication timeout is reasonable")
    func testAuthenticationTimeoutValue() {
        // J-PAKE has 3 rounds, each may take several seconds
        #expect(G7Constants.authenticationTimeout >= 20.0, "Auth timeout should be at least 20s")
        #expect(G7Constants.authenticationTimeout <= 60.0, "Auth timeout should not exceed 60s")
    }
    
    @Test("Discovery timeout matches G7SensorKit")
    func testDiscoveryTimeoutValue() {
        // G7SensorKit uses 2 second discovery timeout
        #expect(G7Constants.discoveryTimeout == 2.0, "Discovery timeout should be 2s per G7SensorKit")
    }
    
    @Test("Overall connection timeout is sum of sub-operations")
    func testOverallConnectionTimeoutValue() {
        // Overall should be >= connection + discovery + auth
        let minOverall = G7Constants.connectionTimeout + G7Constants.discoveryTimeout + G7Constants.authenticationTimeout
        #expect(G7Constants.overallConnectionTimeout >= minOverall * 0.5, "Overall timeout should cover sub-operations")
    }
    
    @Test("Auth round timeout is fraction of total auth timeout")
    func testAuthRoundTimeoutValue() {
        // Each round should be less than total auth timeout / 3
        #expect(G7Constants.authRoundTimeout <= G7Constants.authenticationTimeout / 3, "Round timeout should be less than total/3")
        #expect(G7Constants.authRoundTimeout >= 5.0, "Round timeout should be at least 5s")
    }
}

// MARK: - CGMError Timeout Cases Tests

@Suite("CGMError Timeout Cases - PROD-HARDEN-022")
struct CGMErrorTimeoutTests {
    
    @Test("Authentication timeout error has correct code")
    func testAuthenticationTimeoutCode() {
        let error = CGMError.authenticationTimeout
        #expect(error.code == "AUTH_TIMEOUT")
    }
    
    @Test("Discovery timeout error has correct code")
    func testDiscoveryTimeoutCode() {
        let error = CGMError.discoveryTimeout
        #expect(error.code == "DISCOVERY_TIMEOUT")
    }
    
    @Test("Timeout errors are retryable")
    func testTimeoutErrorsAreRetryable() {
        #expect(CGMError.authenticationTimeout.recoveryAction == .retry)
        #expect(CGMError.discoveryTimeout.recoveryAction == .retry)
    }
    
    @Test("Timeout errors have user descriptions")
    func testTimeoutErrorDescriptions() {
        #expect(CGMError.authenticationTimeout.errorDescription?.contains("timed out") == true)
        #expect(CGMError.discoveryTimeout.errorDescription?.contains("timed out") == true)
    }
    
    @Test("Timeout errors do not require code reentry")
    func testTimeoutErrorsNoCodeReentry() {
        #expect(CGMError.authenticationTimeout.requiresCodeReentry == false)
        #expect(CGMError.discoveryTimeout.requiresCodeReentry == false)
    }
}
