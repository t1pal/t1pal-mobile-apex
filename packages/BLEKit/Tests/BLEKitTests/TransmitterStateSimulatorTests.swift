// SPDX-License-Identifier: MIT
//
// TransmitterStateSimulatorTests.swift
// BLEKit Tests
//
// Tests for transmitter session lifecycle simulation.
// Trace: PRD-007 REQ-SIM-007

import Testing
import Foundation
@testable import BLEKit

// MARK: - State Transition Tests

@Suite("StateTransition Tests")
struct StateTransitionTests {
    
    @Test("Transition captures all properties")
    func transitionProperties() {
        let transition = StateTransition(
            from: .inactive,
            to: .warmup,
            timestamp: Date(),
            reason: .sensorStarted
        )
        
        #expect(transition.from == .inactive)
        #expect(transition.to == .warmup)
        #expect(transition.reason == .sensorStarted)
    }
    
    @Test("Transitions are equatable")
    func transitionEquatable() {
        let now = Date()
        let t1 = StateTransition(from: .warmup, to: .active, timestamp: now, reason: .warmupComplete)
        let t2 = StateTransition(from: .warmup, to: .active, timestamp: now, reason: .warmupComplete)
        
        #expect(t1 == t2)
    }
}

// MARK: - Configuration Tests

@Suite("StateSimulatorConfig Tests")
struct StateSimulatorConfigTests {
    
    @Test("G6 config has correct durations")
    func g6Config() {
        let config = StateSimulatorConfig.g6
        
        #expect(config.warmupDuration == 2 * 60 * 60)  // 2 hours
        #expect(config.maxSessionDuration == 10 * 24 * 60 * 60)  // 10 days
        #expect(config.autoTransitionWarmup == true)
        #expect(config.autoTransitionExpiry == true)
    }
    
    @Test("G7 config has correct durations")
    func g7Config() {
        let config = StateSimulatorConfig.g7
        
        #expect(config.warmupDuration == 30 * 60)  // 30 minutes
        #expect(config.maxSessionDuration == 10.5 * 24 * 60 * 60)  // 10.5 days
    }
    
    @Test("Fast config for testing")
    func fastConfig() {
        let config = StateSimulatorConfig.fast
        
        #expect(config.warmupDuration == 10)  // 10 seconds
        #expect(config.maxSessionDuration == 60)  // 60 seconds
    }
    
    @Test("Instant config skips warmup")
    func instantConfig() {
        let config = StateSimulatorConfig.instant
        
        #expect(config.warmupDuration == 0)
    }
    
    @Test("Time acceleration is clamped")
    func timeAccelerationClamped() {
        let config = StateSimulatorConfig(timeAcceleration: -10)
        
        #expect(config.timeAcceleration > 0)
    }
}

// MARK: - Basic Simulator Tests

@Suite("TransmitterStateSimulator Basic Tests")
struct TransmitterStateSimulatorBasicTests {
    
    @Test("Simulator starts inactive")
    func startsInactive() {
        let simulator = TransmitterStateSimulator()
        
        #expect(simulator.state == .inactive)
        #expect(simulator.sessionStartTime == nil)
    }
    
    @Test("Starting sensor enters warmup")
    func startSensorEntersWarmup() {
        let simulator = TransmitterStateSimulator(config: .g6)
        
        simulator.startSensor()
        
        #expect(simulator.state == .warmup)
        #expect(simulator.sessionStartTime != nil)
        #expect(simulator.warmupEndTime != nil)
        #expect(simulator.sessionEndTime != nil)
    }
    
    @Test("Starting sensor with instant config goes to active")
    func instantStartGoesActive() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        simulator.startSensor()
        
        #expect(simulator.state == .active)
    }
    
    @Test("Stopping sensor goes to inactive")
    func stopSensorGoesInactive() {
        let simulator = TransmitterStateSimulator(config: .instant)
        simulator.startSensor()
        #expect(simulator.state == .active)
        
        simulator.stopSensor()
        
        #expect(simulator.state == .inactive)
        #expect(simulator.sessionStartTime == nil)
    }
    
    @Test("Reset clears all state")
    func resetClearsState() {
        let simulator = TransmitterStateSimulator(config: .instant)
        simulator.startSensor()
        #expect(simulator.transitionHistory.count >= 1)
        
        simulator.reset()
        
        #expect(simulator.state == .inactive)
        // Reset adds a transition from current state to inactive
        #expect(simulator.transitionHistory.count >= 1)
    }
}

// MARK: - Manual Transition Tests

@Suite("Manual Transition Tests")
struct ManualTransitionTests {
    
    @Test("Manual transition changes state")
    func manualTransitionChangesState() {
        let simulator = TransmitterStateSimulator()
        
        simulator.transitionTo(.warmup, reason: .sensorStarted)
        #expect(simulator.state == .warmup)
        
        simulator.transitionTo(.active, reason: .warmupComplete)
        #expect(simulator.state == .active)
        
        simulator.transitionTo(.expired, reason: .sessionExpired)
        #expect(simulator.state == .expired)
    }
    
    @Test("Same state transition is ignored")
    func sameStateIgnored() {
        let simulator = TransmitterStateSimulator()
        simulator.transitionTo(.warmup, reason: .sensorStarted)
        let count = simulator.transitionHistory.count
        
        simulator.transitionTo(.warmup, reason: .sensorStarted)
        
        #expect(simulator.transitionHistory.count == count)
    }
    
    @Test("Simulate failure transitions to error")
    func simulateFailure() {
        let simulator = TransmitterStateSimulator(config: .instant)
        simulator.startSensor()
        
        simulator.simulateFailure()
        
        #expect(simulator.state == .error)
    }
    
    @Test("Simulate low battery")
    func simulateLowBattery() {
        let simulator = TransmitterStateSimulator(config: .instant)
        simulator.startSensor()
        
        simulator.simulateLowBattery()
        
        #expect(simulator.state == .lowBattery)
    }
}

// MARK: - Time Calculation Tests

@Suite("Time Calculation Tests")
struct TimeCalculationTests {
    
    @Test("Session elapsed is zero when inactive")
    func elapsedZeroWhenInactive() {
        let simulator = TransmitterStateSimulator()
        
        #expect(simulator.sessionElapsed == 0)
    }
    
    @Test("Warmup time remaining is zero when not in warmup")
    func warmupRemainingZeroWhenNotWarmup() {
        let simulator = TransmitterStateSimulator(config: .instant)
        simulator.startSensor()
        
        #expect(simulator.warmupTimeRemaining == 0)
    }
    
    @Test("Warmup progress is 1.0 when instant")
    func warmupProgressInstant() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        #expect(simulator.warmupProgress == 1.0)
    }
    
    @Test("Session progress starts at zero")
    func sessionProgressStartsZero() {
        let simulator = TransmitterStateSimulator(config: .g6)
        simulator.startSensor()
        
        // Just started, should be very close to 0
        #expect(simulator.sessionProgress < 0.001)
    }
    
    @Test("Session is valid during warmup and active")
    func sessionValidStates() {
        let simulator = TransmitterStateSimulator(config: .g6)
        
        #expect(!simulator.isSessionValid)
        
        simulator.startSensor()
        #expect(simulator.isSessionValid)
        
        simulator.transitionTo(.active, reason: .warmupComplete)
        #expect(simulator.isSessionValid)
        
        simulator.transitionTo(.expired, reason: .sessionExpired)
        #expect(!simulator.isSessionValid)
    }
}

// MARK: - Transition History Tests

@Suite("Transition History Tests")
struct TransitionHistoryTests {
    
    @Test("Transitions are recorded")
    func transitionsRecorded() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        simulator.startSensor()
        simulator.stopSensor()
        
        #expect(simulator.transitionHistory.count == 2)
        #expect(simulator.transitionHistory[0].from == .inactive)
        #expect(simulator.transitionHistory[0].to == .active)
        #expect(simulator.transitionHistory[1].from == .active)
        #expect(simulator.transitionHistory[1].to == .inactive)
    }
    
    @Test("Transition reasons are captured")
    func transitionReasons() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        simulator.startSensor()
        #expect(simulator.transitionHistory.last?.reason == .warmupComplete)
        
        simulator.simulateFailure()
        #expect(simulator.transitionHistory.last?.reason == .sensorFailed)
        
        simulator.reset()
        #expect(simulator.transitionHistory.last?.reason == .reset)
    }
}

// MARK: - Manual Update Tests

@Suite("Manual Update Tests")
struct ManualUpdateTests {
    
    @Test("Update transitions warmup to active when complete")
    func updateTransitionsWarmup() {
        // Use very short warmup for test
        let config = StateSimulatorConfig(
            warmupDuration: 0.01,  // 10ms
            maxSessionDuration: 3600,
            autoTransitionWarmup: false,
            autoTransitionExpiry: false
        )
        let simulator = TransmitterStateSimulator(config: config)
        
        simulator.startSensor()
        #expect(simulator.state == .warmup)
        
        // Wait for warmup
        Thread.sleep(forTimeInterval: 0.02)
        
        simulator.update()
        #expect(simulator.state == .active)
    }
    
    @Test("Update transitions to expired when session ends")
    func updateTransitionsExpiry() {
        let config = StateSimulatorConfig(
            warmupDuration: 0,
            maxSessionDuration: 0.01,  // 10ms
            autoTransitionWarmup: false,
            autoTransitionExpiry: false
        )
        let simulator = TransmitterStateSimulator(config: config)
        
        simulator.startSensor()
        #expect(simulator.state == .active)
        
        // Wait for expiry
        Thread.sleep(forTimeInterval: 0.02)
        
        simulator.update()
        #expect(simulator.state == .expired)
    }
}

// MARK: - Session Snapshot Tests

@Suite("SessionSnapshot Tests")
struct SessionSnapshotTests {
    
    @Test("Snapshot captures all properties")
    func snapshotCaptures() {
        let simulator = TransmitterStateSimulator(config: .g6)
        simulator.startSensor()
        
        let snapshot = simulator.snapshot
        
        #expect(snapshot.state == .warmup)
        #expect(snapshot.sessionStartTime != nil)
        #expect(snapshot.warmupProgress >= 0)
        #expect(snapshot.sessionProgress >= 0)
        #expect(snapshot.isValid == true)
    }
    
    @Test("Snapshot shows invalid for inactive")
    func snapshotInvalid() {
        let simulator = TransmitterStateSimulator()
        
        let snapshot = simulator.snapshot
        
        #expect(snapshot.state == .inactive)
        #expect(snapshot.isValid == false)
    }
}

// MARK: - Observer Tests

@Suite("Observer Tests")
struct ObserverTests {
    
    final class MockObserver: TransmitterStateObserver, @unchecked Sendable {
        var transitions: [StateTransition] = []
        private let lock = NSLock()
        
        func stateDidChange(_ transition: StateTransition) {
            lock.lock()
            defer { lock.unlock() }
            transitions.append(transition)
        }
        
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return transitions.count
        }
    }
    
    @Test("Observer receives state changes")
    func observerReceivesChanges() {
        let simulator = TransmitterStateSimulator(config: .instant)
        let observer = MockObserver()
        
        simulator.addObserver(observer)
        simulator.startSensor()
        
        #expect(observer.count >= 1)
    }
    
    @Test("Removed observer stops receiving")
    func removedObserverStops() {
        let simulator = TransmitterStateSimulator(config: .instant)
        let observer = MockObserver()
        
        simulator.addObserver(observer)
        simulator.startSensor()
        let countAfterStart = observer.count
        
        simulator.removeObserver(observer)
        simulator.stopSensor()
        
        #expect(observer.count == countAfterStart)
    }
}

// MARK: - Integration Tests

@Suite("State Simulator Integration Tests")
struct StateSimulatorIntegrationTests {
    
    @Test("Full session lifecycle")
    func fullLifecycle() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        // Start
        #expect(simulator.state == .inactive)
        
        // Activate
        simulator.startSensor()
        #expect(simulator.state == .active)
        
        // Expire
        simulator.transitionTo(.expired, reason: .sessionExpired)
        #expect(simulator.state == .expired)
        #expect(!simulator.isSessionValid)
        
        // Stop
        simulator.stopSensor()
        #expect(simulator.state == .inactive)
        
        // Verify history
        #expect(simulator.transitionHistory.count == 3)
    }
    
    @Test("Warmup to active lifecycle")
    func warmupLifecycle() {
        let config = StateSimulatorConfig(
            warmupDuration: 0.01,
            maxSessionDuration: 3600,
            autoTransitionWarmup: false,
            autoTransitionExpiry: false
        )
        let simulator = TransmitterStateSimulator(config: config)
        
        simulator.startSensor()
        #expect(simulator.state == .warmup)
        #expect(simulator.warmupProgress < 1.0)
        
        // Wait and update
        Thread.sleep(forTimeInterval: 0.02)
        simulator.update()
        
        #expect(simulator.state == .active)
        #expect(simulator.warmupProgress >= 1.0)
    }
    
    @Test("Session with time acceleration")
    func timeAcceleration() {
        let config = StateSimulatorConfig(
            warmupDuration: 60,  // 60 seconds
            maxSessionDuration: 3600,
            timeAcceleration: 60.0  // 60x speed
        )
        let simulator = TransmitterStateSimulator(config: config)
        
        simulator.startSensor()
        
        // With 60x acceleration, 1 real second = 60 simulated seconds
        // So warmup should complete faster
        Thread.sleep(forTimeInterval: 0.1)
        
        // Elapsed should be ~6 seconds (0.1 * 60)
        let elapsed = simulator.sessionElapsed
        #expect(elapsed > 5)
        #expect(elapsed < 10)
    }
    
    @Test("Multiple start/stop cycles")
    func multipleStartStopCycles() {
        let simulator = TransmitterStateSimulator(config: .instant)
        
        for _ in 0..<5 {
            simulator.startSensor()
            #expect(simulator.state == .active)
            simulator.stopSensor()
            #expect(simulator.state == .inactive)
        }
        
        #expect(simulator.transitionHistory.count == 10)  // 5 starts + 5 stops
    }
}
