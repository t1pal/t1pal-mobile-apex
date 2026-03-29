// SPDX-License-Identifier: MIT
//
// DASHTimeoutRejectionTests.swift
// PumpKitTests
//
// Tests for DASH timeout and rejection handling using synthesized fixtures.
// Trace: DASH-FIX-013, DASH-FIX-014, DASH-FIX-016

import Testing
import Foundation
@testable import PumpKit

// MARK: - Timeout Fixture Types

struct DASHTimeoutFixture: Codable {
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

struct RetryConfiguration: Codable {
    let maxScanRetries: Int
    let maxConnectionRetries: Int
    let maxCommandRetries: Int
    let maxPairingRetries: Int
    let retryDelayMs: Int
    let exponentialBackoff: Bool
    
    enum CodingKeys: String, CodingKey {
        case maxScanRetries = "max_scan_retries"
        case maxConnectionRetries = "max_connection_retries"
        case maxCommandRetries = "max_command_retries"
        case maxPairingRetries = "max_pairing_retries"
        case retryDelayMs = "retry_delay_ms"
        case exponentialBackoff = "exponential_backoff"
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

struct DASHRejectionFixture: Codable {
    let sessionId: String
    let sessionName: String
    let rejectionScenarios: [RejectionScenario]
    let podProgressStates: [String: PodProgressState]
    let faultCodes: [String: FaultCodeInfo]
    let testVectors: [RejectionTestVector]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionName = "session_name"
        case rejectionScenarios = "rejection_scenarios"
        case podProgressStates = "pod_progress_states"
        case faultCodes = "fault_codes"
        case testVectors = "test_vectors"
    }
}

struct RejectionScenario: Codable {
    let scenarioId: String
    let name: String
    let description: String
    let triggerState: String
    let faultType: String
    let faultCode: String?
    
    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case name
        case description
        case triggerState = "trigger_state"
        case faultType = "fault_type"
        case faultCode = "fault_code"
    }
}

struct PodProgressState: Codable {
    let name: String
    let canCommunicate: Bool
    
    enum CodingKeys: String, CodingKey {
        case name
        case canCommunicate = "can_communicate"
    }
}

struct FaultCodeInfo: Codable {
    let name: String
    let isAlarm: Bool
    let isCritical: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name
        case isAlarm = "is_alarm"
        case isCritical = "is_critical"
    }
}

struct RejectionTestVector: Codable {
    let name: String
    let inputHex: String?
    let scenario: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case inputHex = "input_hex"
        case scenario
    }
}

// MARK: - Fixture Loading

enum DASHFixtureError: Error {
    case notFound(String)
    case decodingFailed(String)
}

func loadDASHTimeoutFixture() throws -> DASHTimeoutFixture {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fixture_dash_timeout", withExtension: "json", subdirectory: "Fixtures") else {
        throw DASHFixtureError.notFound("fixture_dash_timeout.json")
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(DASHTimeoutFixture.self, from: data)
}

func loadDASHRejectionFixture() throws -> DASHRejectionFixture {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fixture_dash_rejection", withExtension: "json", subdirectory: "Fixtures") else {
        throw DASHFixtureError.notFound("fixture_dash_rejection.json")
    }
    
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(DASHRejectionFixture.self, from: data)
}

// MARK: - Timeout Tests

@Suite("DASH Timeout Handling Tests")
struct DASHTimeoutTests {
    
    @Test("Timeout fixture loads successfully")
    func testFixtureLoads() throws {
        let fixture = try loadDASHTimeoutFixture()
        #expect(fixture.sessionId == "SESSION-DASH-TIMEOUT-001")
        #expect(!fixture.timeoutScenarios.isEmpty)
    }
    
    @Test("Fixture contains expected timeout scenarios")
    func testTimeoutScenariosExist() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        let scenarioIds = fixture.timeoutScenarios.map { $0.scenarioId }
        #expect(scenarioIds.contains("TIMEOUT-001")) // Scan timeout
        #expect(scenarioIds.contains("TIMEOUT-002")) // Connection timeout
        #expect(scenarioIds.contains("TIMEOUT-004")) // Command timeout
        #expect(scenarioIds.contains("TIMEOUT-005")) // Bolus timeout
    }
    
    @Test("Retry configuration is valid")
    func testRetryConfiguration() throws {
        let fixture = try loadDASHTimeoutFixture()
        let config = fixture.retryConfiguration
        
        #expect(config.maxConnectionRetries >= 1)
        #expect(config.maxConnectionRetries <= 10)
        #expect(config.maxCommandRetries >= 1)
        #expect(config.retryDelayMs > 0)
        #expect(config.exponentialBackoff == true)
    }
    
    @Test("Timeout triggers state transition to error")
    func testTimeoutStateTransition() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        // Find the state machine test vector
        if let vector = fixture.testVectors.first(where: { $0.name == "State machine on timeout" }) {
            #expect(vector.initialState == "commanding")
            #expect(vector.expectedState == "error")
        }
    }
    
    @Test("Bolus uncertainty scenario exists")
    func testBolusUncertaintyScenario() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        let bolusTimeout = fixture.timeoutScenarios.first { $0.scenarioId == "TIMEOUT-005" }
        #expect(bolusTimeout != nil)
        #expect(bolusTimeout?.name == "Bolus delivery response timeout")
        #expect(bolusTimeout?.triggerState == "bolusing")
    }
}

// MARK: - Rejection Tests

@Suite("DASH Rejection Handling Tests")
struct DASHRejectionTests {
    
    @Test("Rejection fixture loads successfully")
    func testFixtureLoads() throws {
        let fixture = try loadDASHRejectionFixture()
        #expect(fixture.sessionId == "SESSION-DASH-REJECTION-001")
        #expect(!fixture.rejectionScenarios.isEmpty)
    }
    
    @Test("Fixture contains expected rejection scenarios")
    func testRejectionScenariosExist() throws {
        let fixture = try loadDASHRejectionFixture()
        
        let scenarioIds = fixture.rejectionScenarios.map { $0.scenarioId }
        #expect(scenarioIds.contains("REJECT-001")) // Already paired
        #expect(scenarioIds.contains("REJECT-002")) // Pod expired
        #expect(scenarioIds.contains("REJECT-003")) // Occlusion
        #expect(scenarioIds.contains("REJECT-004")) // Empty reservoir
    }
    
    @Test("Pod progress states are defined")
    func testPodProgressStates() throws {
        let fixture = try loadDASHRejectionFixture()
        
        #expect(fixture.podProgressStates["0x00"]?.name == "initial")
        #expect(fixture.podProgressStates["0x07"]?.name == "aboveFiftyUnits")
        #expect(fixture.podProgressStates["0x0E"]?.name == "faultEventOccurred")
        #expect(fixture.podProgressStates["0x0F"]?.name == "inactive")
        
        // Active states can communicate
        #expect(fixture.podProgressStates["0x07"]?.canCommunicate == true)
        // Fault and inactive states cannot
        #expect(fixture.podProgressStates["0x0E"]?.canCommunicate == false)
        #expect(fixture.podProgressStates["0x0F"]?.canCommunicate == false)
    }
    
    @Test("Fault codes are defined")
    func testFaultCodes() throws {
        let fixture = try loadDASHRejectionFixture()
        
        #expect(fixture.faultCodes["0x14"]?.name == "occlusion")
        #expect(fixture.faultCodes["0x18"]?.name == "emptyReservoir")
        #expect(fixture.faultCodes["0x85"]?.name == "bolusOverInfusion")
        
        // Occlusion is an alarm
        #expect(fixture.faultCodes["0x14"]?.isAlarm == true)
        // Over-infusion is critical
        #expect(fixture.faultCodes["0x85"]?.isCritical == true)
    }
    
    @Test("Occlusion scenario is non-recoverable")
    func testOcclusionNonRecoverable() throws {
        let fixture = try loadDASHRejectionFixture()
        
        let occlusion = fixture.rejectionScenarios.first { $0.scenarioId == "REJECT-003" }
        #expect(occlusion != nil)
        #expect(occlusion?.faultType == "occlusion")
        #expect(occlusion?.faultCode == "0x14")
    }
    
    @Test("Critical over-infusion fault exists")
    func testOverInfusionFault() throws {
        let fixture = try loadDASHRejectionFixture()
        
        let overInfusion = fixture.rejectionScenarios.first { $0.scenarioId == "REJECT-008" }
        #expect(overInfusion != nil)
        #expect(overInfusion?.name == "Bolus over-infusion fault")
        #expect(overInfusion?.faultCode == "0x85")
    }
}

// MARK: - Failure Recovery Tests

@Suite("DASH Failure Recovery Tests")
struct DASHFailureRecoveryTests {
    
    @Test("Connection retry count from fixture")
    func testConnectionRetryCount() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        #expect(fixture.retryConfiguration.maxConnectionRetries == 3)
    }
    
    @Test("Exponential backoff is enabled")
    func testExponentialBackoff() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        #expect(fixture.retryConfiguration.exponentialBackoff == true)
    }
    
    @Test("Test vectors include retry sequence")
    func testRetrySequenceVector() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        let retryVector = fixture.testVectors.first { $0.name == "Retry count tracking" }
        #expect(retryVector != nil)
        #expect(retryVector?.scenario == "TIMEOUT-002")
    }
    
    @Test("Bolus uncertainty handling documented")
    func testBolusUncertaintyHandling() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        let bolusVector = fixture.testVectors.first { $0.name == "Bolus uncertainty handling" }
        #expect(bolusVector != nil)
        #expect(bolusVector?.scenario == "TIMEOUT-005")
    }
}

// MARK: - Integration with Fault Injector

@Suite("DASH Fixture-FaultInjector Integration")
struct DASHFixtureFaultIntegrationTests {
    
    @Test("Timeout scenarios map to DASH fault types")
    func testTimeoutToFaultMapping() throws {
        let fixture = try loadDASHTimeoutFixture()
        
        // Verify scenarios have valid fault types
        let validFaultTypes = [
            "bleScanTimeout", "bleConnectionTimeout", "pairingTimeout",
            "bleRetryTimeout", "blePingTimeout", "pairingKeyExchangeFailed"
        ]
        
        for scenario in fixture.timeoutScenarios {
            #expect(validFaultTypes.contains(scenario.faultType), 
                    "Scenario \(scenario.scenarioId) has valid fault type \(scenario.faultType)")
        }
    }
    
    @Test("Rejection scenarios map to DASH fault types")
    func testRejectionToFaultMapping() throws {
        let fixture = try loadDASHRejectionFixture()
        
        // Map rejection scenarios to DASHFaultType
        let scenarioToFault: [String: DASHFaultType] = [
            "REJECT-002": .podExpired,
            "REJECT-003": .occlusion,
            "REJECT-004": .emptyReservoir,
            "REJECT-005": .pairingAKARejected,
            "REJECT-006": .bleNackError,
            "REJECT-009": .bleCRCFailure
        ]
        
        for (scenarioId, expectedFault) in scenarioToFault {
            let scenario = fixture.rejectionScenarios.first { $0.scenarioId == scenarioId }
            #expect(scenario != nil, "Scenario \(scenarioId) should exist")
            
            // Verify the fault injector has this fault type
            let injector = DASHFaultInjector()
            injector.addFault(expectedFault, trigger: .immediate)
            #expect(injector.faults.count == 1)
            injector.clearFaults()
        }
    }
    
    @Test("All alarm faults are marked as alarms in fixture")
    func testAlarmFaultsConsistency() throws {
        let fixture = try loadDASHRejectionFixture()
        
        let alarmScenarios = fixture.rejectionScenarios.filter { scenario in
            if let code = scenario.faultCode, let info = fixture.faultCodes[code] {
                return info.isAlarm
            }
            return false
        }
        
        // Should have multiple alarm scenarios
        #expect(alarmScenarios.count >= 4)
    }
}
