// SPDX-License-Identifier: MIT
//
// G6FaultInjectionTests.swift
// CGMKitTests
//
// Tests for G6 fault injection framework.
// Validates error path handling in DexcomG6Manager.
// Trace: G6-FIX-016, SIM-FAULT-001, synthesized-device-testing.md

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

@Suite("G6 FaultInjector Tests")
struct G6FaultInjectorTests {
    
    // MARK: - Basic Initialization
    
    @Test("Initializes with empty faults")
    func testEmptyInitialization() {
        let injector = G6FaultInjector()
        #expect(injector.faults.isEmpty)
        #expect(injector.operationCount == 0)
        #expect(injector.readingCount == 0)
    }
    
    @Test("Initializes with provided faults")
    func testInitializationWithFaults() {
        let config = G6FaultConfiguration(
            fault: .authTimeout,
            trigger: .immediate,
            description: "Test auth timeout"
        )
        let injector = G6FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .authTimeout)
    }
    
    // MARK: - Fault Management
    
    @Test("Adds fault configuration")
    func testAddFault() {
        let injector = G6FaultInjector()
        injector.addFault(.authTimeout, trigger: .immediate)
        #expect(injector.faults.count == 1)
    }
    
    @Test("Removes fault by ID")
    func testRemoveFault() {
        let config = G6FaultConfiguration(id: "test-fault", fault: .authTimeout)
        let injector = G6FaultInjector(faults: [config])
        #expect(injector.faults.count == 1)
        
        injector.removeFault(id: "test-fault")
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Clears all faults")
    func testClearFaults() {
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(fault: .authTimeout),
            G6FaultConfiguration(fault: .sensorExpired)
        ])
        #expect(injector.faults.count == 2)
        
        injector.clearFaults()
        #expect(injector.faults.isEmpty)
    }
    
    @Test("Reset clears operation and reading counts")
    func testReset() {
        let injector = G6FaultInjector()
        injector.recordOperation()
        injector.recordOperation()
        injector.recordReading()
        #expect(injector.operationCount == 2)
        #expect(injector.readingCount == 1)
        
        injector.reset()
        #expect(injector.operationCount == 0)
        #expect(injector.readingCount == 0)
    }
    
    // MARK: - Immediate Trigger
    
    @Test("Immediate trigger injects on first check")
    func testImmediateTrigger() {
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .authTimeout,
                trigger: .immediate
            )
        ])
        
        let result = injector.shouldInject(for: "authenticate")
        if case .injected(let fault) = result {
            #expect(fault == .authTimeout)
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Operation-Based Trigger
    
    @Test("onOperation trigger matches specific operation")
    func testOnOperationTrigger() {
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .authRejected(code: 0x01),
                trigger: .onOperation("authenticate")
            )
        ])
        
        // Different operation should not trigger
        let result1 = injector.shouldInject(for: "readGlucose")
        #expect(result1 == .noFault)
        
        // Matching operation should trigger
        let result2 = injector.shouldInject(for: "authenticate")
        if case .injected(let fault) = result2 {
            #expect(fault == .authRejected(code: 0x01))
        } else {
            Issue.record("Expected fault injection")
        }
    }
    
    // MARK: - Count-Based Trigger
    
    @Test("afterOperations trigger waits for operation count")
    func testAfterOperationsTrigger() {
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(
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
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(
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
    
    // MARK: - Once Trigger
    
    @Test("once trigger fires only once")
    func testOnceTrigger() {
        let injector = G6FaultInjector(faults: [
            G6FaultConfiguration(
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
        #expect(G6FaultType.authTimeout.category == .authentication)
        #expect(G6FaultType.authRejected(code: 0x01).category == .authentication)
        #expect(G6FaultType.bondLost.category == .authentication)
        #expect(G6FaultType.challengeFailed.category == .authentication)
    }
    
    @Test("Connection faults have correct category")
    func testConnectionFaultCategory() {
        #expect(G6FaultType.connectionDrop.category == .connection)
        #expect(G6FaultType.connectionTimeout.category == .connection)
        #expect(G6FaultType.scanTimeout.category == .connection)
    }
    
    @Test("Sensor faults have correct category")
    func testSensorFaultCategory() {
        #expect(G6FaultType.sensorExpired.category == .sensor)
        #expect(G6FaultType.sensorWarmup.category == .sensor)
        #expect(G6FaultType.sensorFailed(code: 0x01).category == .sensor)
        #expect(G6FaultType.noSignal.category == .sensor)
    }
    
    // MARK: - Streaming Impact
    
    @Test("Auth faults stop streaming")
    func testAuthFaultsStopStreaming() {
        #expect(G6FaultType.authTimeout.stopsStreaming == true)
        #expect(G6FaultType.authRejected(code: 0x01).stopsStreaming == true)
        #expect(G6FaultType.bondLost.stopsStreaming == true)
    }
    
    @Test("Warmup doesn't stop streaming")
    func testWarmupDoesntStopStreaming() {
        #expect(G6FaultType.sensorWarmup.stopsStreaming == false)
    }
    
    // MARK: - Presets
    
    @Test("authTimeout preset configures correctly")
    func testAuthTimeoutPreset() {
        let injector = G6FaultInjector.authTimeout
        #expect(injector.faults.count == 1)
        #expect(injector.faults.first?.fault == .authTimeout)
    }
    
    @Test("authRejected preset configures correctly")
    func testAuthRejectedPreset() {
        let injector = G6FaultInjector.authRejected
        #expect(injector.faults.count == 1)
        if case .authRejected(let code) = injector.faults.first?.fault {
            #expect(code == 0x01)
        } else {
            Issue.record("Expected authRejected fault type")
        }
    }
    
    @Test("unreliableConnection preset has multiple faults")
    func testUnreliableConnectionPreset() {
        let injector = G6FaultInjector.unreliableConnection
        #expect(injector.faults.count == 3)
    }
    
    @Test("stressTest preset has multiple faults")
    func testStressTestPreset() {
        let injector = G6FaultInjector.stressTest
        #expect(injector.faults.count == 3)
    }
    
    // MARK: - Statistics
    
    @Test("Statistics tracks injected faults")
    func testStatisticsTracking() {
        var stats = G6FaultInjectionStats()
        
        stats.record(.injected(.authTimeout))
        #expect(stats.faultsInjected == 1)
        #expect(stats.faultsByCategory[.authentication] == 1)
        #expect(stats.streamingInterruptions == 1)  // authTimeout stops streaming
        
        stats.record(.injected(.sensorWarmup))
        #expect(stats.faultsInjected == 2)
        #expect(stats.faultsByCategory[.sensor] == 1)
        #expect(stats.streamingInterruptions == 1)  // warmup doesn't add
        
        stats.record(.skipped(.connectionDrop))
        #expect(stats.faultsSkipped == 1)
        #expect(stats.faultsInjected == 2)  // Unchanged
    }
}

// MARK: - G6Manager Fault Injection Integration Tests

@Suite("G6Manager FaultInjection Tests", .serialized)
struct G6ManagerFaultInjectionTests {
    
    @Test("Manager accepts fault injector in constructor")
    func testManagerWithInjector() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let injector = G6FaultInjector.authTimeout
        
        let manager = DexcomG6Manager(
            transmitterId: tx,
            central: central,
            faultInjector: injector
        )
        
        let currentInjector = await manager.currentFaultInjector
        #expect(currentInjector != nil)
        #expect(currentInjector?.faults.count == 1)
    }
    
    @Test("Manager without injector has nil")
    func testManagerWithoutInjector() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        let manager = DexcomG6Manager(transmitterId: tx, central: central)
        
        let currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
    }
    
    @Test("setFaultInjector changes injector")
    func testSetFaultInjector() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        let manager = DexcomG6Manager(transmitterId: tx, central: central)
        
        // Initially nil
        var currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
        
        // Set injector
        let injector = G6FaultInjector.sensorExpired
        await manager.setFaultInjector(injector)
        
        currentInjector = await manager.currentFaultInjector
        #expect(currentInjector != nil)
        #expect(currentInjector?.faults.first?.fault == .sensorExpired)
        
        // Clear injector
        await manager.setFaultInjector(nil)
        currentInjector = await manager.currentFaultInjector
        #expect(currentInjector == nil)
    }
}

// MARK: - Auth Retry Behavior Tests

@Suite("G6 Auth Retry Behavior Tests")
struct G6AuthRetryBehaviorTests {
    
    // MARK: - Backoff Calculation Tests
    
    @Test("Backoff delay uses exponential growth")
    func testBackoffExponentialGrowth() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            reconnectDelay: 2.0,
            maxReconnectAttempts: 5,
            backoffMultiplier: 2.0,
            maxReconnectDelay: 60.0
        )
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Verify exponential backoff: 2, 4, 8, 16, 32
        let delay1 = await manager.backoffDelayForAttempt(1)
        let delay2 = await manager.backoffDelayForAttempt(2)
        let delay3 = await manager.backoffDelayForAttempt(3)
        let delay4 = await manager.backoffDelayForAttempt(4)
        let delay5 = await manager.backoffDelayForAttempt(5)
        
        #expect(delay1 == 2.0)   // 2 * 2^0 = 2
        #expect(delay2 == 4.0)   // 2 * 2^1 = 4
        #expect(delay3 == 8.0)   // 2 * 2^2 = 8
        #expect(delay4 == 16.0)  // 2 * 2^3 = 16
        #expect(delay5 == 32.0)  // 2 * 2^4 = 32
    }
    
    @Test("Backoff delay capped at max")
    func testBackoffCappedAtMax() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            reconnectDelay: 2.0,
            maxReconnectAttempts: 10,
            backoffMultiplier: 2.0,
            maxReconnectDelay: 30.0  // Cap at 30s
        )
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Attempt 5: 2 * 2^4 = 32 -> capped to 30
        let delay5 = await manager.backoffDelayForAttempt(5)
        #expect(delay5 == 30.0)
        
        // Attempt 10: 2 * 2^9 = 1024 -> capped to 30
        let delay10 = await manager.backoffDelayForAttempt(10)
        #expect(delay10 == 30.0)
    }
    
    @Test("Fixed delay when multiplier is 1.0")
    func testFixedDelayWithMultiplierOne() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            reconnectDelay: 5.0,
            maxReconnectAttempts: 5,
            backoffMultiplier: 1.0,  // No exponential growth
            maxReconnectDelay: 60.0
        )
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        // All delays should be 5.0 (fixed)
        for attempt in 1...5 {
            let delay = await manager.backoffDelayForAttempt(attempt)
            #expect(delay == 5.0)
        }
    }
    
    @Test("Backoff handles edge cases")
    func testBackoffEdgeCases() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            reconnectDelay: 2.0,
            maxReconnectAttempts: 5,
            backoffMultiplier: 2.0,
            maxReconnectDelay: 60.0
        )
        
        let manager = DexcomG6Manager(config: config, central: central)
        
        // Attempt 0 should be treated as attempt 1 (base delay)
        let delay0 = await manager.backoffDelayForAttempt(0)
        #expect(delay0 == 2.0)
        
        // Negative attempt should be treated as attempt 1
        let delayNeg = await manager.backoffDelayForAttempt(-1)
        #expect(delayNeg == 2.0)
    }
    
    // MARK: - Reconnect Attempt Counter Tests
    
    @Test("Reconnect attempts initially zero")
    func testReconnectAttemptsInitiallyZero() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        let manager = DexcomG6Manager(transmitterId: tx, central: central)
        
        let attempts = await manager.currentReconnectAttempts
        #expect(attempts == 0)
    }
    
    @Test("Reset reconnect attempts clears counter")
    func testResetReconnectAttempts() async {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        
        let manager = DexcomG6Manager(transmitterId: tx, central: central)
        
        // Manually test reset functionality
        await manager.resetReconnectAttempts()
        let attempts = await manager.currentReconnectAttempts
        #expect(attempts == 0)
    }
    
    // MARK: - Config Defaults Tests
    
    @Test("Default config has sensible backoff defaults")
    func testDefaultBackoffConfig() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(transmitterId: tx)
        
        #expect(config.reconnectDelay == 2.0)
        #expect(config.backoffMultiplier == 2.0)
        #expect(config.maxReconnectDelay == 60.0)
        #expect(config.maxReconnectAttempts == 0)  // Unlimited by default
        #expect(config.autoReconnect == true)
    }
    
    @Test("Custom backoff config is preserved")
    func testCustomBackoffConfig() {
        let tx = TransmitterID("80AB12")!
        let config = DexcomG6ManagerConfig(
            transmitterId: tx,
            reconnectDelay: 1.0,
            maxReconnectAttempts: 3,
            backoffMultiplier: 1.5,
            maxReconnectDelay: 10.0
        )
        
        #expect(config.reconnectDelay == 1.0)
        #expect(config.maxReconnectAttempts == 3)
        #expect(config.backoffMultiplier == 1.5)
        #expect(config.maxReconnectDelay == 10.0)
    }
}

// MARK: - Equality Extensions

extension G6FaultInjectionResult: Equatable {
    public static func == (lhs: G6FaultInjectionResult, rhs: G6FaultInjectionResult) -> Bool {
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
