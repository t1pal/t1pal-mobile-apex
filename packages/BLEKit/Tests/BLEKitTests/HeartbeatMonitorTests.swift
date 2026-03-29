// HeartbeatMonitorTests.swift
// BLEKitTests
//
// Tests for BLE-CONN-004: Async keepalive heartbeat

import Testing
import Foundation
@testable import BLEKit

@Suite("Heartbeat Config")
struct HeartbeatConfigTests {
    
    @Test("Default config values")
    func defaultConfig() {
        let config = HeartbeatConfig()
        
        #expect(config.interval == 30)
        #expect(config.missedThreshold == 3)
        #expect(config.responseTimeout == 10)
        #expect(config.autoRestart == true)
    }
    
    @Test("BLE default preset")
    func bleDefaultPreset() {
        let config = HeartbeatConfig.bleDefault
        
        #expect(config.interval == 30)
        #expect(config.missedThreshold == 3)
        #expect(config.responseTimeout == 10)
    }
    
    @Test("Aggressive preset")
    func aggressivePreset() {
        let config = HeartbeatConfig.aggressive
        
        #expect(config.interval == 10)
        #expect(config.missedThreshold == 2)
        #expect(config.responseTimeout == 5)
    }
    
    @Test("Conservative preset")
    func conservativePreset() {
        let config = HeartbeatConfig.conservative
        
        #expect(config.interval == 60)
        #expect(config.missedThreshold == 5)
        #expect(config.responseTimeout == 15)
    }
    
    @Test("Testing preset")
    func testingPreset() {
        let config = HeartbeatConfig.testing
        
        #expect(config.interval == 0.1)
        #expect(config.missedThreshold == 2)
        #expect(config.autoRestart == false)
    }
    
    @Test("Config enforces minimum values")
    func configMinimumValues() {
        let config = HeartbeatConfig(
            interval: 0,
            missedThreshold: 0,
            responseTimeout: 0,
            autoRestart: false
        )
        
        #expect(config.interval == 0.01)
        #expect(config.missedThreshold == 1)
        #expect(config.responseTimeout == 0.01)
    }
    
    @Test("Config is equatable")
    func configEquatable() {
        let c1 = HeartbeatConfig.bleDefault
        let c2 = HeartbeatConfig.bleDefault
        let c3 = HeartbeatConfig.aggressive
        
        #expect(c1 == c2)
        #expect(c1 != c3)
    }
}

@Suite("Heartbeat State")
struct HeartbeatStateTests {
    
    @Test("State has raw values")
    func stateRawValues() {
        #expect(HeartbeatState.stopped.rawValue == "stopped")
        #expect(HeartbeatState.healthy.rawValue == "healthy")
        #expect(HeartbeatState.degraded.rawValue == "degraded")
        #expect(HeartbeatState.disconnected.rawValue == "disconnected")
    }
    
    @Test("State is case iterable")
    func stateCaseIterable() {
        #expect(HeartbeatState.allCases.count == 4)
    }
}

@Suite("Heartbeat Result")
struct HeartbeatResultTests {
    
    @Test("Success result")
    func successResult() {
        let result = HeartbeatResult.success(latency: 0.5)
        
        #expect(result.success == true)
        #expect(result.latency == 0.5)
        #expect(result.error == nil)
    }
    
    @Test("Failure result")
    func failureResult() {
        let result = HeartbeatResult.failure(error: "Timeout")
        
        #expect(result.success == false)
        #expect(result.latency == nil)
        #expect(result.error == "Timeout")
    }
    
    @Test("Result has timestamp")
    func resultHasTimestamp() {
        let before = Date()
        let result = HeartbeatResult.success(latency: 0.1)
        let after = Date()
        
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }
    
    @Test("Result is equatable")
    func resultEquatable() {
        let r1 = HeartbeatResult(success: true, latency: 0.5)
        let r2 = HeartbeatResult(success: true, latency: 0.5)
        
        // Note: timestamps will differ, so not equal
        #expect(r1.success == r2.success)
        #expect(r1.latency == r2.latency)
    }
}

@Suite("Heartbeat Monitor Core")
struct HeartbeatMonitorCoreTests {
    
    @Test("Initial state is stopped")
    func initialStateStopped() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        let state = await monitor.currentState
        
        #expect(state == .stopped)
    }
    
    @Test("Start transitions to healthy")
    func startTransitionsToHealthy() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        await monitor.start()
        let state = await monitor.currentState
        
        #expect(state == .healthy)
        
        await monitor.stop()
    }
    
    @Test("Stop transitions to stopped")
    func stopTransitionsToStopped() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        await monitor.start()
        await monitor.stop()
        
        let state = await monitor.currentState
        #expect(state == .stopped)
    }
    
    @Test("Is running after start")
    func isRunningAfterStart() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        await monitor.start()
        let isRunning = await monitor.isRunning
        
        #expect(isRunning == true)
        
        await monitor.stop()
    }
    
    @Test("Not running after stop")
    func notRunningAfterStop() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        await monitor.start()
        await monitor.stop()
        
        let isRunning = await monitor.isRunning
        #expect(isRunning == false)
    }
    
    @Test("Check now with no checker succeeds")
    func checkNowNoCheckerSucceeds() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        let result = await monitor.checkNow()
        
        #expect(result.success == true)
    }
    
    @Test("Check now with successful checker")
    func checkNowWithSuccessfulChecker() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        let checker = MockHeartbeatChecker(shouldSucceed: true)
        await monitor.setHeartbeatChecker(checker)
        
        let result = await monitor.checkNow()
        
        #expect(result.success == true)
        #expect(result.latency != nil)
    }
    
    @Test("Check now with failing checker")
    func checkNowWithFailingChecker() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor.setHeartbeatChecker(checker)
        
        let result = await monitor.checkNow()
        
        #expect(result.success == false)
    }
    
    @Test("Report heartbeat resets miss count")
    func reportHeartbeatResetsMissCount() async {
        let config = HeartbeatConfig(
            interval: 10,
            missedThreshold: 3,
            responseTimeout: 1,
            autoRestart: false
        )
        let monitor = HeartbeatMonitor(deviceId: "test", config: config)
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor.setHeartbeatChecker(checker)
        
        await monitor.start()
        _ = await monitor.checkNow() // Miss 1
        _ = await monitor.checkNow() // Miss 2
        
        // Report external heartbeat
        await monitor.reportHeartbeat()
        
        let stats = await monitor.statistics()
        #expect(stats.consecutiveMisses == 0)
        
        await monitor.stop()
    }
    
    @Test("Statistics track heartbeats")
    func statisticsTrackHeartbeats() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        _ = await monitor.checkNow()
        _ = await monitor.checkNow()
        _ = await monitor.checkNow()
        
        let stats = await monitor.statistics()
        
        #expect(stats.totalHeartbeats == 3)
        #expect(stats.successfulHeartbeats == 3)
        #expect(stats.successRate == 1.0)
    }
    
    @Test("Reset statistics clears counts")
    func resetStatisticsClearsCounts() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        _ = await monitor.checkNow()
        _ = await monitor.checkNow()
        
        await monitor.resetStatistics()
        
        let stats = await monitor.statistics()
        #expect(stats.totalHeartbeats == 0)
    }
}

@Suite("Heartbeat Disconnect Detection")
struct HeartbeatDisconnectTests {
    
    @Test("Missed heartbeats transition to degraded")
    func missedHeartbeatsTransitionToDegraded() async {
        let config = HeartbeatConfig(
            interval: 10,
            missedThreshold: 3,
            responseTimeout: 1,
            autoRestart: false
        )
        let monitor = HeartbeatMonitor(deviceId: "test", config: config)
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor.setHeartbeatChecker(checker)
        
        await monitor.start()
        #expect(await monitor.currentState == .healthy)
        
        _ = await monitor.checkNow() // First miss
        
        #expect(await monitor.currentState == .degraded)
        
        await monitor.stop()
    }
    
    @Test("Threshold misses transition to disconnected")
    func thresholdMissesTransitionToDisconnected() async {
        let config = HeartbeatConfig(
            interval: 10,
            missedThreshold: 2,
            responseTimeout: 1,
            autoRestart: false
        )
        let monitor = HeartbeatMonitor(deviceId: "test", config: config)
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor.setHeartbeatChecker(checker)
        
        await monitor.start()
        
        _ = await monitor.checkNow() // Miss 1 - degraded
        _ = await monitor.checkNow() // Miss 2 - disconnected
        
        #expect(await monitor.currentState == .disconnected)
        
        await monitor.stop()
    }
    
    @Test("Success after miss recovers to healthy")
    func successAfterMissRecoversToHealthy() async {
        let config = HeartbeatConfig(
            interval: 10,
            missedThreshold: 3,
            responseTimeout: 1,
            autoRestart: false
        )
        let monitor = HeartbeatMonitor(deviceId: "test", config: config)
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor.setHeartbeatChecker(checker)
        
        await monitor.start()
        _ = await monitor.checkNow() // Miss
        
        #expect(await monitor.currentState == .degraded)
        
        // Now succeed
        checker.setShouldSucceed(true)
        _ = await monitor.checkNow()
        
        #expect(await monitor.currentState == .healthy)
        
        await monitor.stop()
    }
}

@Suite("Heartbeat Events")
struct HeartbeatEventTests {
    
    @Test("Event handler receives events")
    func eventHandlerReceivesEvents() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        
        actor EventCollector {
            var events: [HeartbeatEvent] = []
            func append(_ event: HeartbeatEvent) { events.append(event) }
            var count: Int { events.count }
        }
        
        let collector = EventCollector()
        await monitor.setEventHandler { event in
            Task { await collector.append(event) }
        }
        
        await monitor.start()
        try? await Task.sleep(for: .milliseconds(50))
        
        let count = await collector.count
        #expect(count >= 1) // At least started event
        
        await monitor.stop()
    }
    
    @Test("Event is equatable")
    func eventEquatable() {
        let e1 = HeartbeatEvent.heartbeatSuccess(latency: 0.5)
        let e2 = HeartbeatEvent.heartbeatSuccess(latency: 0.5)
        let e3 = HeartbeatEvent.stopped
        
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
    
    @Test("State changed event")
    func stateChangedEvent() {
        let event = HeartbeatEvent.stateChanged(from: .healthy, to: .degraded)
        
        if case .stateChanged(let from, let to) = event {
            #expect(from == .healthy)
            #expect(to == .degraded)
        } else {
            #expect(Bool(false), "Wrong event type")
        }
    }
    
    @Test("Heartbeat missed event")
    func heartbeatMissedEvent() {
        let event = HeartbeatEvent.heartbeatMissed(consecutiveMisses: 2, threshold: 3)
        
        if case .heartbeatMissed(let misses, let threshold) = event {
            #expect(misses == 2)
            #expect(threshold == 3)
        } else {
            #expect(Bool(false), "Wrong event type")
        }
    }
}

@Suite("Heartbeat Statistics")
struct HeartbeatStatisticsTests {
    
    @Test("Statistics reflect state")
    func statisticsReflectState() async {
        let monitor = HeartbeatMonitor(deviceId: "device123", config: .testing)
        
        await monitor.start()
        _ = await monitor.checkNow()
        
        let stats = await monitor.statistics()
        
        #expect(stats.deviceId == "device123")
        #expect(stats.state == .healthy)
        #expect(stats.isHealthy == true)
        
        await monitor.stop()
    }
    
    @Test("Success rate calculation")
    func successRateCalculation() async {
        let monitor = HeartbeatMonitor(deviceId: "test", config: .testing)
        let checker = MockHeartbeatChecker(shouldSucceed: true)
        await monitor.setHeartbeatChecker(checker)
        
        _ = await monitor.checkNow() // Success
        _ = await monitor.checkNow() // Success
        
        checker.setShouldSucceed(false)
        _ = await monitor.checkNow() // Fail
        
        let stats = await monitor.statistics()
        
        #expect(stats.totalHeartbeats == 3)
        #expect(stats.successfulHeartbeats == 2)
        // 2/3 = 0.666...
        #expect(stats.successRate > 0.66)
        #expect(stats.successRate < 0.67)
    }
    
    @Test("Is healthy property")
    func isHealthyProperty() {
        let healthyStats = HeartbeatStatistics(
            state: .healthy,
            deviceId: "test",
            consecutiveMisses: 0,
            missedThreshold: 3,
            totalHeartbeats: 10,
            successfulHeartbeats: 10,
            lastSuccessfulHeartbeat: Date(),
            successRate: 1.0
        )
        
        let degradedStats = HeartbeatStatistics(
            state: .degraded,
            deviceId: "test",
            consecutiveMisses: 1,
            missedThreshold: 3,
            totalHeartbeats: 10,
            successfulHeartbeats: 9,
            lastSuccessfulHeartbeat: Date(),
            successRate: 0.9
        )
        
        #expect(healthyStats.isHealthy == true)
        #expect(degradedStats.isHealthy == false)
    }
    
    @Test("Statistics is equatable")
    func statisticsEquatable() {
        let date = Date()
        
        let s1 = HeartbeatStatistics(
            state: .healthy,
            deviceId: "test",
            consecutiveMisses: 0,
            missedThreshold: 3,
            totalHeartbeats: 10,
            successfulHeartbeats: 10,
            lastSuccessfulHeartbeat: date,
            successRate: 1.0
        )
        
        let s2 = HeartbeatStatistics(
            state: .healthy,
            deviceId: "test",
            consecutiveMisses: 0,
            missedThreshold: 3,
            totalHeartbeats: 10,
            successfulHeartbeats: 10,
            lastSuccessfulHeartbeat: date,
            successRate: 1.0
        )
        
        #expect(s1 == s2)
    }
}

@Suite("Heartbeat Manager")
struct HeartbeatManagerTests {
    
    @Test("Manager creates monitors for devices")
    func managerCreatesMonitors() async {
        let manager = HeartbeatManager(config: .testing)
        
        let monitor1 = await manager.monitor(for: "device1")
        let monitor2 = await manager.monitor(for: "device2")
        
        let state1 = await monitor1.currentState
        let state2 = await monitor2.currentState
        
        #expect(state1 == .stopped)
        #expect(state2 == .stopped)
    }
    
    @Test("Manager returns same monitor for same device")
    func managerReturnsSameMonitor() async {
        let manager = HeartbeatManager(config: .testing)
        
        let monitor1 = await manager.monitor(for: "device1")
        await monitor1.start()
        
        let monitor2 = await manager.monitor(for: "device1")
        let isRunning = await monitor2.isRunning
        
        #expect(isRunning == true)
        
        await monitor1.stop()
    }
    
    @Test("Start monitoring device")
    func startMonitoringDevice() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        
        let state = await manager.state(for: "device1")
        #expect(state == .healthy)
        
        await manager.stopMonitoring(deviceId: "device1")
    }
    
    @Test("Stop monitoring device")
    func stopMonitoringDevice() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        await manager.stopMonitoring(deviceId: "device1")
        
        let state = await manager.state(for: "device1")
        #expect(state == .stopped)
    }
    
    @Test("Stop all monitors")
    func stopAllMonitors() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        await manager.startMonitoring(deviceId: "device2")
        await manager.stopAll()
        
        let states = await manager.allStates()
        #expect(states["device1"] == .stopped)
        #expect(states["device2"] == .stopped)
    }
    
    @Test("Get all states")
    func getAllStates() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        _ = await manager.monitor(for: "device2") // Just create, don't start
        
        let states = await manager.allStates()
        
        #expect(states["device1"] == .healthy)
        #expect(states["device2"] == .stopped)
        
        await manager.stopAll()
    }
    
    @Test("Disconnected count")
    func disconnectedCount() async {
        let config = HeartbeatConfig(
            interval: 10,
            missedThreshold: 1,
            responseTimeout: 1,
            autoRestart: false
        )
        let manager = HeartbeatManager(config: config)
        
        await manager.startMonitoring(deviceId: "device1")
        await manager.startMonitoring(deviceId: "device2")
        
        // Force disconnect on device1
        let monitor1 = await manager.monitor(for: "device1")
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        await monitor1.setHeartbeatChecker(checker)
        _ = await monitor1.checkNow()
        
        let count = await manager.disconnectedCount()
        #expect(count == 1)
        
        await manager.stopAll()
    }
    
    @Test("Remove device")
    func removeDevice() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        await manager.remove(deviceId: "device1")
        
        let states = await manager.allStates()
        #expect(states["device1"] == nil)
    }
    
    @Test("Report heartbeat for device")
    func reportHeartbeatForDevice() async {
        let manager = HeartbeatManager(config: .testing)
        
        await manager.startMonitoring(deviceId: "device1")
        await manager.reportHeartbeat(for: "device1")
        
        let monitor = await manager.monitor(for: "device1")
        let stats = await monitor.statistics()
        
        #expect(stats.lastSuccessfulHeartbeat != nil)
        
        await manager.stopAll()
    }
}

@Suite("Mock Heartbeat Checker")
struct MockHeartbeatCheckerTests {
    
    @Test("Mock checker succeeds when configured")
    func mockCheckerSucceeds() async throws {
        let checker = MockHeartbeatChecker(shouldSucceed: true)
        
        let result = try await checker.performHeartbeat()
        #expect(result == true)
    }
    
    @Test("Mock checker fails when configured")
    func mockCheckerFails() async throws {
        let checker = MockHeartbeatChecker(shouldSucceed: false)
        
        let result = try await checker.performHeartbeat()
        #expect(result == false)
    }
    
    @Test("Mock checker can change success state")
    func mockCheckerChangeState() async throws {
        let checker = MockHeartbeatChecker(shouldSucceed: true)
        
        var result = try await checker.performHeartbeat()
        #expect(result == true)
        
        checker.setShouldSucceed(false)
        
        result = try await checker.performHeartbeat()
        #expect(result == false)
    }
    
    @Test("Mock checker applies delay")
    func mockCheckerAppliesDelay() async throws {
        let checker = MockHeartbeatChecker(shouldSucceed: true, delay: 0.1)
        
        let start = Date()
        _ = try await checker.performHeartbeat()
        let elapsed = Date().timeIntervalSince(start)
        
        #expect(elapsed >= 0.09)
    }
}
