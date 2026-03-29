// SPDX-License-Identifier: MIT
//
// G7FaultInjectionTests.swift
// CGMKitTests
//
// Tests for G7 fault injection framework.
// Validates error path handling in DexcomG7Manager.
// Trace: G7-FIX-016, SIM-FAULT-001, synthesized-device-testing.md

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

@Suite("G7 FaultInjector Tests")
struct G7FaultInjectorTests {
    
    // MARK: - Basic Initialization
    
    @Test("Initializes with empty faults")
    func testEmptyInitialization() {
        let injector = G7FaultInjector()
        #expect(injector.faults.isEmpty)
        #expect(injector.operationCount == 0)
        #expect(injector.readingCount == 0)
        #expect(injector.jpakeRound == 0)
    }
    
    @Test("Initializes with provided faults")
    func testInitializationWithFaults() {
        let config = G7FaultConfiguration(
            fault: .jpakeTimeout,
            trigger: .immediate,
            description: "Test J-PAKE timeout"
        )
        let injector = G7FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .jpakeTimeout)
    }
    
    // MARK: - Fault Management
    
    @Test("Adds fault configuration")
    func testAddFault() {
        let injector = G7FaultInjector()
        injector.addFault(.jpakeTimeout, trigger: .immediate)
        #expect(injector.faults.count == 1)
    }
    
    @Test("Removes fault by ID")
    func testRemoveFault() {
        let config = G7FaultConfiguration(id: "test-fault", fault: .jpakeTimeout)
        let injector = G7FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        
        injector.removeFault(id: "test-fault")
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Clears all faults")
    func testClearFaults() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(fault: .jpakeTimeout),
            G7FaultConfiguration(fault: .sensorExpired)
        ])
        #expect(injector.faults.count == 2)
        
        injector.clearFaults()
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Reset clears all counters")
    func testReset() {
        let injector = G7FaultInjector()
        injector.recordOperation()
        injector.recordOperation()
        injector.recordReading()
        injector.recordJPAKERound(2)
        #expect(injector.operationCount == 2)
        #expect(injector.readingCount == 1)
        #expect(injector.jpakeRound == 2)
        
        injector.reset()
        #expect(injector.operationCount == 0)
        #expect(injector.readingCount == 0)
        #expect(injector.jpakeRound == 0)
    }
    
    // MARK: - Immediate Trigger
    
    @Test("Immediate trigger injects on first check")
    func testImmediateTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .jpakeTimeout,
                trigger: .immediate
            )
        ])
        
        let result = injector.shouldInject(for: "authenticate")
        if case .injected(let fault) = result {
            #expect(fault == .jpakeTimeout)
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Operation-Based Trigger
    
    @Test("onOperation trigger matches specific operation")
    func testOnOperationTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .sensorCodeMismatch,
                trigger: .onOperation("authenticate")
            )
        ])
        
        // Different operation should not trigger
        let result1 = injector.shouldInject(for: "readGlucose")
        #expect(result1 == .noFault)
        
        // Matching operation should trigger
        let result2 = injector.shouldInject(for: "authenticate")
        if case .injected(let fault) = result2 {
            #expect(fault == .sensorCodeMismatch)
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Count-Based Trigger
    
    @Test("afterOperations trigger waits for operation count")
    func testAfterOperationsTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .connectionDrop,
                trigger: .afterOperations(3)
            )
        ])
        
        // Before reaching count
        #expect(injector.shouldInject() == .noFault)
        injector.recordOperation()
        #expect(injector.shouldInject() == .noFault)
        injector.recordOperation()
        #expect(injector.shouldInject() == .noFault)
        injector.recordOperation()
        
        // After reaching count
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .connectionDrop)
        } else {
            Issue.record("Expected fault injection after 3 operations")
        }
    }
    
    @Test("afterReadings trigger waits for reading count")
    func testAfterReadingsTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .sensorExpired,
                trigger: .afterReadings(2)
            )
        ])
        
        // Before reaching count
        #expect(injector.shouldInject() == .noFault)
        injector.recordReading()
        #expect(injector.shouldInject() == .noFault)
        injector.recordReading()
        
        // After reaching count
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .sensorExpired)
        } else {
            Issue.record("Expected fault injection after 2 readings")
        }
    }
    
    // MARK: - J-PAKE Round Trigger
    
    @Test("onJPAKERound trigger fires on specific round")
    func testOnJPAKERoundTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .jpakeTimeout,
                trigger: .onJPAKERound(2)
            )
        ])
        
        // Round 1 should not trigger
        injector.recordJPAKERound(1)
        #expect(injector.shouldInject() == .noFault)
        
        // Round 2 should trigger
        injector.recordJPAKERound(2)
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .jpakeTimeout)
        } else {
            Issue.record("Expected fault injection on Round 2")
        }
    }
    
    // MARK: - Once Trigger
    
    @Test("once trigger fires only once")
    func testOnceTrigger() {
        let injector = G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .bondLost,
                trigger: .once
            )
        ])
        
        // First check should inject
        let result1 = injector.shouldInject()
        if case .injected(let fault) = result1 {
            #expect(fault == .bondLost)
        } else {
            Issue.record("Expected fault injection on first check")
        }
        
        // Subsequent checks should not inject
        let result2 = injector.shouldInject()
        #expect(result2 == .noFault)
    }
    
    // MARK: - Fault Categories
    
    @Test("Authentication faults have correct category")
    func testAuthFaultCategory() {
        #expect(G7FaultType.jpakeTimeout.category == .authentication)
        #expect(G7FaultType.jpakeRejected.category == .authentication)
        #expect(G7FaultType.sensorCodeMismatch.category == .authentication)
        #expect(G7FaultType.pairingFailed.category == .authentication)
        #expect(G7FaultType.bondLost.category == .authentication)
        #expect(G7FaultType.sessionKeyDerivationFailed.category == .authentication)
    }
    
    @Test("Connection faults have correct category")
    func testConnectionFaultCategory() {
        #expect(G7FaultType.connectionDrop.category == .connection)
        #expect(G7FaultType.connectionTimeout.category == .connection)
        #expect(G7FaultType.scanTimeout.category == .connection)
        #expect(G7FaultType.advertisementMissing.category == .connection)
    }
    
    @Test("Sensor faults have correct category")
    func testSensorFaultCategory() {
        #expect(G7FaultType.sensorExpired.category == .sensor)
        #expect(G7FaultType.sensorWarmup.category == .sensor)
        #expect(G7FaultType.sensorFailed(code: 0x01).category == .sensor)
        #expect(G7FaultType.noSignal.category == .sensor)
        #expect(G7FaultType.algorithmUnreliable.category == .sensor)
    }
    
    @Test("Lifecycle faults have correct category")
    func testLifecycleFaultCategory() {
        #expect(G7FaultType.gracePeriodExpired.category == .lifecycle)
        #expect(G7FaultType.sensorNotStarted.category == .lifecycle)
        #expect(G7FaultType.firmwareMismatch.category == .lifecycle)
    }
    
    // MARK: - Streaming Impact
    
    @Test("Auth faults stop streaming")
    func testAuthFaultsStopStreaming() {
        #expect(G7FaultType.jpakeTimeout.stopsStreaming == true)
        #expect(G7FaultType.jpakeRejected.stopsStreaming == true)
        #expect(G7FaultType.sensorCodeMismatch.stopsStreaming == true)
        #expect(G7FaultType.pairingFailed.stopsStreaming == true)
        #expect(G7FaultType.bondLost.stopsStreaming == true)
    }
    
    @Test("Warmup doesn't stop streaming")
    func testWarmupDoesntStopStreaming() {
        #expect(G7FaultType.sensorWarmup.stopsStreaming == false)
    }
    
    // MARK: - Code Retry
    
    @Test("Code mismatch allows retry")
    func testCodeMismatchAllowsRetry() {
        #expect(G7FaultType.sensorCodeMismatch.allowsCodeRetry == true)
        #expect(G7FaultType.jpakeRejected.allowsCodeRetry == true)
    }
    
    @Test("Other faults don't allow code retry")
    func testOtherFaultsDontAllowRetry() {
        #expect(G7FaultType.jpakeTimeout.allowsCodeRetry == false)
        #expect(G7FaultType.connectionDrop.allowsCodeRetry == false)
        #expect(G7FaultType.sensorExpired.allowsCodeRetry == false)
    }
    
    // MARK: - Presets
    
    @Test("jpakeTimeout preset configures correctly")
    func testJpakeTimeoutPreset() {
        let injector = G7FaultInjector.jpakeTimeout
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .jpakeTimeout)
    }
    
    @Test("jpakeRejected preset configures correctly")
    func testJpakeRejectedPreset() {
        let injector = G7FaultInjector.jpakeRejected
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .jpakeRejected)
    }
    
    @Test("sensorCodeMismatch preset configures correctly")
    func testSensorCodeMismatchPreset() {
        let injector = G7FaultInjector.sensorCodeMismatch
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .sensorCodeMismatch)
    }
    
    @Test("jpakeRound2Timeout preset configures correctly")
    func testJpakeRound2TimeoutPreset() {
        let injector = G7FaultInjector.jpakeRound2Timeout
        #expect(injector.faults.count == 1)
        if case .onJPAKERound(let round) = injector.faults.first?.trigger {
            #expect(round == 2)
        } else {
            Issue.record("Expected onJPAKERound trigger")
        }
    }
    
    @Test("unreliableConnection preset has multiple faults")
    func testUnreliableConnectionPreset() {
        let injector = G7FaultInjector.unreliableConnection
        #expect(injector.faults.count == 3)
    }
    
    @Test("stressTest preset has multiple faults")
    func testStressTestPreset() {
        let injector = G7FaultInjector.stressTest
        #expect(injector.faults.count == 4)
    }
    
    // MARK: - Statistics
    
    @Test("Statistics tracks injected faults")
    func testStatisticsTracking() {
        var stats = G7FaultInjectionStats()
        
        stats.record(.injected(.jpakeTimeout))
        #expect(stats.faultsInjected == 1)
        #expect(stats.faultsByCategory[.authentication] == 1)
        #expect(stats.streamingInterruptions == 1)  // jpakeTimeout stops streaming
        #expect(stats.codeRetryOpportunities == 0)
        
        stats.record(.injected(.sensorCodeMismatch))
        #expect(stats.faultsInjected == 2)
        #expect(stats.faultsByCategory[.authentication] == 2)
        #expect(stats.streamingInterruptions == 2)
        #expect(stats.codeRetryOpportunities == 1)  // sensorCodeMismatch allows retry
        
        stats.record(.injected(.sensorWarmup))
        #expect(stats.faultsInjected == 3)
        #expect(stats.faultsByCategory[.sensor] == 1)
        #expect(stats.streamingInterruptions == 2)  // warmup doesn't add
        
        stats.record(.skipped(.connectionDrop))
        #expect(stats.faultsSkipped == 1)
        #expect(stats.faultsInjected == 3)  // Unchanged
    }
}

// MARK: - G7Manager Fault Injection Integration Tests

@Suite("G7Manager FaultInjection Tests", .serialized)
struct G7ManagerFaultInjectionTests {
    
    @Test("Manager accepts fault injector in constructor")
    func testManagerWithInjector() async throws {
        let central = MockBLECentral()
        let injector = G7FaultInjector.jpakeTimeout
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABCD123456",
            sensorCode: "1234",
            central: central,
            faultInjector: injector
        )
        
        let currentInjector = await manager.currentFaultInjector
        #expect(currentInjector != nil)
        #expect(currentInjector?.faults.count == 1)
    }
    
    @Test("Manager without injector has nil")
    func testManagerWithoutInjector() async throws {
        let central = MockBLECentral()
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABCD123456",
            sensorCode: "1234",
            central: central
        )
        
        let currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
    }
    
    @Test("setFaultInjector changes injector")
    func testSetFaultInjector() async throws {
        let central = MockBLECentral()
        
        let manager = try DexcomG7Manager(
            sensorSerial: "ABCD123456",
            sensorCode: "1234",
            central: central
        )
        
        // Initially nil
        var currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
        
        // Set injector
        let injector = G7FaultInjector.sensorExpired
        await manager.setFaultInjector(injector)
        
        currentInjector = await manager.currentFaultInjector
        #expect(currentInjector != nil)
        #expect(currentInjector?.faults.first?.fault == .sensorExpired)
        
        // Clear injector
        await manager.setFaultInjector(nil)
        currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
    }
    
    @Test("Config constructor accepts fault injector")
    func testConfigConstructorWithInjector() async throws {
        let central = MockBLECentral()
        let config = DexcomG7ManagerConfig(
            sensorSerial: "ABCD123456",
            sensorCode: "1234"
        )
        let injector = G7FaultInjector.sensorCodeMismatch
        
        let manager = try DexcomG7Manager(
            config: config,
            central: central,
            faultInjector: injector
        )
        
        let currentInjector = await manager.currentFaultInjector
        #expect(currentInjector != nil)
        #expect(currentInjector?.faults.first?.fault == .sensorCodeMismatch)
    }
}

// MARK: - Equality Extensions

extension G7FaultInjectionResult: Equatable {
    public static func == (lhs: G7FaultInjectionResult, rhs: G7FaultInjectionResult) -> Bool {
        switch (lhs, rhs) {
        case (.noFault, .noFault):
            return true
        case (.injected(let l), .injected(let r)):
            return l == r
        case (.skipped(let l), .skipped(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}
