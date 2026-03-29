// CircuitBreakerTests.swift
// BLEKitTests
//
// Tests for BLE-CONN-003: Circuit breaker pattern

import Testing
import Foundation
@testable import BLEKit

@Suite("Circuit Breaker State")
struct CircuitBreakerStateTests {
    
    @Test("State has raw values")
    func stateRawValues() {
        #expect(CircuitBreakerState.closed.rawValue == "closed")
        #expect(CircuitBreakerState.open.rawValue == "open")
        #expect(CircuitBreakerState.halfOpen.rawValue == "halfOpen")
    }
    
    @Test("State is case iterable")
    func stateCaseIterable() {
        #expect(CircuitBreakerState.allCases.count == 3)
    }
}

@Suite("Circuit Breaker Config")
struct CircuitBreakerConfigTests {
    
    @Test("Default config values")
    func defaultConfig() {
        let config = CircuitBreakerConfig()
        
        #expect(config.failureThreshold == 5)
        #expect(config.successThreshold == 2)
        #expect(config.resetTimeout == 30)
        #expect(config.failureWindow == 60)
        #expect(config.halfOpenRequests == 3)
    }
    
    @Test("BLE default preset")
    func bleDefaultPreset() {
        let config = CircuitBreakerConfig.bleDefault
        
        #expect(config.failureThreshold == 5)
        #expect(config.successThreshold == 2)
        #expect(config.resetTimeout == 30)
    }
    
    @Test("Aggressive preset")
    func aggressivePreset() {
        let config = CircuitBreakerConfig.aggressive
        
        #expect(config.failureThreshold == 3)
        #expect(config.successThreshold == 3)
        #expect(config.resetTimeout == 60)
    }
    
    @Test("Conservative preset")
    func conservativePreset() {
        let config = CircuitBreakerConfig.conservative
        
        #expect(config.failureThreshold == 10)
        #expect(config.successThreshold == 1)
        #expect(config.resetTimeout == 15)
    }
    
    @Test("Testing preset")
    func testingPreset() {
        let config = CircuitBreakerConfig.testing
        
        #expect(config.failureThreshold == 2)
        #expect(config.resetTimeout == 1)
    }
    
    @Test("Config enforces minimum values")
    func configMinimumValues() {
        let config = CircuitBreakerConfig(
            failureThreshold: 0,
            successThreshold: 0,
            resetTimeout: 0,
            failureWindow: 0,
            halfOpenRequests: 0
        )
        
        #expect(config.failureThreshold == 1)
        #expect(config.successThreshold == 1)
        #expect(config.resetTimeout == 0.01)
        #expect(config.failureWindow == 0.01)
        #expect(config.halfOpenRequests == 1)
    }
    
    @Test("Config is equatable")
    func configEquatable() {
        let c1 = CircuitBreakerConfig.bleDefault
        let c2 = CircuitBreakerConfig.bleDefault
        let c3 = CircuitBreakerConfig.aggressive
        
        #expect(c1 == c2)
        #expect(c1 != c3)
    }
}

@Suite("Circuit Breaker Core")
struct CircuitBreakerCoreTests {
    
    @Test("Initial state is closed")
    func initialStateClosed() async {
        let breaker = CircuitBreaker(config: .testing)
        let state = await breaker.currentState
        
        #expect(state == .closed)
    }
    
    @Test("Closed state allows execution")
    func closedAllowsExecution() async throws {
        let breaker = CircuitBreaker(config: .testing)
        let canExecute = try await breaker.canExecute()
        
        #expect(canExecute == true)
    }
    
    @Test("Failures trip circuit to open")
    func failuresTripCircuit() async {
        let config = CircuitBreakerConfig(failureThreshold: 2, resetTimeout: 60)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        #expect(await breaker.currentState == .closed)
        
        await breaker.recordFailure()
        #expect(await breaker.currentState == .open)
    }
    
    @Test("Open state rejects execution")
    func openRejectsExecution() async throws {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        
        do {
            _ = try await breaker.canExecute()
            #expect(Bool(false), "Should have thrown")
        } catch let error as CircuitBreakerError {
            if case .circuitOpen(let retryAfter) = error {
                #expect(retryAfter > 0)
                #expect(retryAfter <= 60)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    }
    
    @Test("Open transitions to half-open after timeout")
    func openTransitionsToHalfOpen() async throws {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 0.1)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        #expect(await breaker.currentState == .open)
        
        // Wait for timeout
        try await Task.sleep(for: .milliseconds(200))
        
        // Should now allow and transition to half-open
        let canExecute = try await breaker.canExecute()
        #expect(canExecute == true)
        #expect(await breaker.currentState == .halfOpen)
    }
    
    @Test("Half-open success resets to closed")
    func halfOpenSuccessResets() async throws {
        let config = CircuitBreakerConfig(
            failureThreshold: 1,
            successThreshold: 1,
            resetTimeout: 0.1
        )
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        try await Task.sleep(for: .milliseconds(200))
        _ = try await breaker.canExecute()
        
        #expect(await breaker.currentState == .halfOpen)
        
        await breaker.recordSuccess()
        #expect(await breaker.currentState == .closed)
    }
    
    @Test("Half-open failure returns to open")
    func halfOpenFailureReturnsToOpen() async throws {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 0.1)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        try await Task.sleep(for: .milliseconds(200))
        _ = try await breaker.canExecute()
        
        #expect(await breaker.currentState == .halfOpen)
        
        await breaker.recordFailure()
        #expect(await breaker.currentState == .open)
    }
    
    @Test("Half-open limits requests")
    func halfOpenLimitsRequests() async throws {
        let config = CircuitBreakerConfig(
            failureThreshold: 1,
            resetTimeout: 0.1,
            halfOpenRequests: 2
        )
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        try await Task.sleep(for: .milliseconds(200))
        
        // First request transitions to half-open
        _ = try await breaker.canExecute()
        #expect(await breaker.currentState == .halfOpen)
        
        // Second request allowed
        _ = try await breaker.canExecute()
        
        // Third request rejected
        do {
            _ = try await breaker.canExecute()
            #expect(Bool(false), "Should have thrown")
        } catch is CircuitBreakerError {
            // Expected
        }
    }
    
    @Test("Reset clears state")
    func resetClearsState() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        #expect(await breaker.currentState == .open)
        
        await breaker.reset()
        #expect(await breaker.currentState == .closed)
    }
    
    @Test("Failure count tracks within window")
    func failureCountTracksWithinWindow() async {
        let config = CircuitBreakerConfig(failureThreshold: 10, failureWindow: 60)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        let count = await breaker.failureCount()
        #expect(count == 3)
    }
    
    @Test("Old failures expire from window")
    func oldFailuresExpire() async throws {
        let config = CircuitBreakerConfig(failureThreshold: 10, failureWindow: 0.1)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        try await Task.sleep(for: .milliseconds(200))
        
        let count = await breaker.failureCount()
        #expect(count == 0)
    }
    
    @Test("Time until retry returns value when open")
    func timeUntilRetryWhenOpen() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 30)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        
        let time = await breaker.timeUntilRetry()
        #expect(time != nil)
        #expect(time! > 0)
        #expect(time! <= 30)
    }
    
    @Test("Time until retry nil when closed")
    func timeUntilRetryWhenClosed() async {
        let breaker = CircuitBreaker(config: .testing)
        
        let time = await breaker.timeUntilRetry()
        #expect(time == nil)
    }
}

@Suite("Circuit Breaker Events")
struct CircuitBreakerEventTests {
    
    @Test("Event handler receives state changes")
    func eventHandlerReceivesStateChanges() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let breaker = CircuitBreaker(config: config)
        
        actor EventCollector {
            var events: [CircuitBreakerEvent] = []
            func append(_ event: CircuitBreakerEvent) {
                events.append(event)
            }
            var count: Int { events.count }
        }
        
        let collector = EventCollector()
        await breaker.setEventHandler { event in
            Task { await collector.append(event) }
        }
        
        await breaker.recordFailure()
        
        // Give time for async event handling
        try? await Task.sleep(for: .milliseconds(50))
        
        // Should have failure recorded + state change
        let count = await collector.count
        #expect(count >= 1)
    }
    
    @Test("Event is equatable")
    func eventEquatable() {
        let e1 = CircuitBreakerEvent.stateChanged(from: .closed, to: .open)
        let e2 = CircuitBreakerEvent.stateChanged(from: .closed, to: .open)
        let e3 = CircuitBreakerEvent.requestRejected
        
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
}

@Suite("Circuit Breaker Statistics")
struct CircuitBreakerStatisticsTests {
    
    @Test("Statistics reflect current state")
    func statisticsReflectState() async {
        let config = CircuitBreakerConfig(failureThreshold: 5)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        let stats = await breaker.statistics()
        
        #expect(stats.state == .closed)
        #expect(stats.failureCount == 2)
        #expect(stats.failureThreshold == 5)
        #expect(stats.isAllowingRequests == true)
    }
    
    @Test("Failure percentage calculation")
    func failurePercentageCalculation() async {
        let config = CircuitBreakerConfig(failureThreshold: 4)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        let stats = await breaker.statistics()
        #expect(stats.failurePercentage == 50)
    }
    
    @Test("Is allowing requests false when open")
    func isAllowingRequestsFalseWhenOpen() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let breaker = CircuitBreaker(config: config)
        
        await breaker.recordFailure()
        
        let stats = await breaker.statistics()
        #expect(stats.isAllowingRequests == false)
    }
    
    @Test("Statistics is equatable")
    func statisticsEquatable() {
        let s1 = CircuitBreakerStatistics(
            state: .closed,
            failureCount: 1,
            failureThreshold: 5,
            halfOpenSuccesses: 0,
            successThreshold: 2,
            timeSinceStateChange: 10,
            timeUntilRetry: nil
        )
        
        let s2 = CircuitBreakerStatistics(
            state: .closed,
            failureCount: 1,
            failureThreshold: 5,
            halfOpenSuccesses: 0,
            successThreshold: 2,
            timeSinceStateChange: 10,
            timeUntilRetry: nil
        )
        
        #expect(s1 == s2)
    }
}

@Suite("Circuit Breaker Executor")
struct CircuitBreakerExecutorTests {
    
    @Test("Executor runs successful operation")
    func executorRunsSuccessful() async throws {
        let executor = CircuitBreakerExecutor(config: .testing)
        
        let result = try await executor.execute {
            return 42
        }
        
        #expect(result == 42)
    }
    
    @Test("Executor records success")
    func executorRecordsSuccess() async throws {
        let executor = CircuitBreakerExecutor(config: .testing)
        
        _ = try await executor.execute { return 1 }
        
        let stats = await executor.statistics()
        #expect(stats.state == .closed)
    }
    
    @Test("Executor records failure")
    func executorRecordsFailure() async {
        struct TestError: Error {}
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let executor = CircuitBreakerExecutor(config: config)
        
        do {
            _ = try await executor.execute {
                throw TestError()
            }
        } catch {
            // Expected
        }
        
        let state = await executor.state
        #expect(state == .open)
    }
    
    @Test("Executor rejects when open")
    func executorRejectsWhenOpen() async throws {
        struct TestError: Error {}
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let executor = CircuitBreakerExecutor(config: config)
        
        // Trip the circuit
        do {
            _ = try await executor.execute { throw TestError() }
        } catch {}
        
        // Try again - should be rejected
        do {
            _ = try await executor.execute { return 1 }
            #expect(Bool(false), "Should have thrown")
        } catch is CircuitBreakerError {
            // Expected
        }
    }
    
    @Test("Executor reset works")
    func executorResetWorks() async throws {
        struct TestError: Error {}
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let executor = CircuitBreakerExecutor(config: config)
        
        do {
            _ = try await executor.execute { throw TestError() }
        } catch {}
        
        await executor.reset()
        
        let state = await executor.state
        #expect(state == .closed)
    }
}

@Suite("Device Circuit Breaker Manager")
struct DeviceCircuitBreakerManagerTests {
    
    @Test("Manager creates breakers for devices")
    func managerCreatesBreakers() async {
        let manager = DeviceCircuitBreakerManager(config: .testing)
        
        let breaker1 = await manager.breaker(for: "device1")
        let breaker2 = await manager.breaker(for: "device2")
        
        // Different devices get different breakers
        let state1 = await breaker1.currentState
        let state2 = await breaker2.currentState
        
        #expect(state1 == .closed)
        #expect(state2 == .closed)
    }
    
    @Test("Manager returns same breaker for same device")
    func managerReturnsSameBreaker() async {
        let manager = DeviceCircuitBreakerManager(config: .testing)
        
        let breaker1 = await manager.breaker(for: "device1")
        await breaker1.recordFailure()
        
        let breaker2 = await manager.breaker(for: "device1")
        let count = await breaker2.failureCount()
        
        #expect(count == 1)
    }
    
    @Test("Manager tracks device states")
    func managerTracksDeviceStates() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        await manager.recordFailure(for: "device1")
        
        let state1 = await manager.state(for: "device1")
        let state2 = await manager.state(for: "device2")
        
        #expect(state1 == .open)
        #expect(state2 == .closed)
    }
    
    @Test("Manager gets all states")
    func managerGetsAllStates() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        _ = await manager.breaker(for: "device1")
        await manager.recordFailure(for: "device2")
        
        let states = await manager.allStates()
        
        #expect(states["device1"] == .closed)
        #expect(states["device2"] == .open)
    }
    
    @Test("Manager counts open circuits")
    func managerCountsOpenCircuits() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        await manager.recordFailure(for: "device1")
        await manager.recordFailure(for: "device2")
        _ = await manager.breaker(for: "device3")
        
        let count = await manager.openCircuitCount()
        #expect(count == 2)
    }
    
    @Test("Manager resets single device")
    func managerResetsSingleDevice() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        await manager.recordFailure(for: "device1")
        await manager.recordFailure(for: "device2")
        
        await manager.reset(for: "device1")
        
        let state1 = await manager.state(for: "device1")
        let state2 = await manager.state(for: "device2")
        
        #expect(state1 == .closed)
        #expect(state2 == .open)
    }
    
    @Test("Manager resets all devices")
    func managerResetsAllDevices() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        await manager.recordFailure(for: "device1")
        await manager.recordFailure(for: "device2")
        
        await manager.resetAll()
        
        let count = await manager.openCircuitCount()
        #expect(count == 0)
    }
    
    @Test("Manager removes device")
    func managerRemovesDevice() async {
        let manager = DeviceCircuitBreakerManager(config: .testing)
        
        _ = await manager.breaker(for: "device1")
        await manager.remove(deviceId: "device1")
        
        let states = await manager.allStates()
        #expect(states["device1"] == nil)
    }
    
    @Test("Can connect checks circuit")
    func canConnectChecksCircuit() async throws {
        let config = CircuitBreakerConfig(failureThreshold: 1, resetTimeout: 60)
        let manager = DeviceCircuitBreakerManager(config: config)
        
        let canConnect1 = try await manager.canConnect(to: "device1")
        #expect(canConnect1 == true)
        
        await manager.recordFailure(for: "device1")
        
        do {
            _ = try await manager.canConnect(to: "device1")
            #expect(Bool(false), "Should have thrown")
        } catch is CircuitBreakerError {
            // Expected
        }
    }
}

@Suite("Circuit Breaker Error")
struct CircuitBreakerErrorTests {
    
    @Test("Error descriptions")
    func errorDescriptions() {
        let openError = CircuitBreakerError.circuitOpen(retryAfter: 30)
        #expect(openError.errorDescription?.contains("30") == true)
        
        let limitError = CircuitBreakerError.halfOpenLimitExceeded
        #expect(limitError.errorDescription?.contains("half-open") == true)
    }
}
