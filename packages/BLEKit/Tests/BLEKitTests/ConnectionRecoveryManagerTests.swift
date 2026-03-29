// ConnectionRecoveryManagerTests.swift
// BLEKitTests
//
// Tests for connection recovery after app restart.
// PROD-CGM-003: Connection recovery after app restart

import Testing
import Foundation
@testable import BLEKit

// MARK: - Recovery Strategy Tests

@Suite("Recovery Strategy")
struct RecoveryStrategyTests {
    
    @Test("All strategies are available")
    func allStrategies() {
        let all = RecoveryStrategy.allCases
        #expect(all.count == 4)
        #expect(all.contains(.immediate))
        #expect(all.contains(.exponentialBackoff))
    }
    
    @Test("Strategies are Codable")
    func strategiesAreCodable() throws {
        let strategy = RecoveryStrategy.exponentialBackoff
        let data = try JSONEncoder().encode(strategy)
        let decoded = try JSONDecoder().decode(RecoveryStrategy.self, from: data)
        #expect(decoded == strategy)
    }
}

// MARK: - Recovery Priority Tests

@Suite("Recovery Priority")
struct RecoveryPriorityTests {
    
    @Test("Critical is highest priority")
    func criticalIsHighest() {
        #expect(RecoveryPriority.critical > RecoveryPriority.high)
        #expect(RecoveryPriority.high > RecoveryPriority.normal)
        #expect(RecoveryPriority.normal > RecoveryPriority.low)
    }
    
    @Test("Priorities are Comparable")
    func prioritiesAreComparable() {
        let priorities: [RecoveryPriority] = [.low, .high, .critical, .normal]
        let sorted = priorities.sorted()
        #expect(sorted == [.low, .normal, .high, .critical])
    }
}

// MARK: - Device Record Tests

@Suite("Device Record")
struct DeviceRecordTests {
    
    @Test("Creates device record")
    func createsRecord() {
        let record = DeviceRecord(
            id: "ABC123",
            name: "Dexcom G7",
            deviceType: "cgm",
            priority: .critical
        )
        
        #expect(record.id == "ABC123")
        #expect(record.name == "Dexcom G7")
        #expect(record.priority == .critical)
        #expect(record.connectionCount == 1)
    }
    
    @Test("Updates on connection")
    func updatesOnConnection() {
        let record = DeviceRecord(
            id: "ABC123",
            name: "CGM",
            deviceType: "cgm",
            connectionCount: 5
        )
        
        let updated = record.withConnection()
        
        #expect(updated.connectionCount == 6)
        #expect(updated.lastDisconnected == nil)
    }
    
    @Test("Updates on disconnection")
    func updatesOnDisconnection() {
        let record = DeviceRecord(
            id: "ABC123",
            name: "CGM",
            deviceType: "cgm"
        )
        
        let updated = record.withDisconnection()
        
        #expect(updated.lastDisconnected != nil)
    }
    
    @Test("Updates on failure")
    func updatesOnFailure() {
        let record = DeviceRecord(
            id: "ABC123",
            name: "CGM",
            deviceType: "cgm",
            failureCount: 2
        )
        
        let updated = record.withFailure()
        
        #expect(updated.failureCount == 3)
    }
    
    @Test("Device record is Codable")
    func isCodable() throws {
        let record = DeviceRecord(
            id: "TEST",
            name: "Test Device",
            deviceType: "test",
            priority: .high,
            serviceUUIDs: ["FEBC"]
        )
        
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DeviceRecord.self, from: data)
        
        #expect(decoded.id == record.id)
        #expect(decoded.priority == record.priority)
    }
}

// MARK: - Recovery State Tests

@Suite("Recovery State")
struct RecoveryStateTests {
    
    @Test("Idle is not active")
    func idleNotActive() {
        let state = RecoveryState.idle
        #expect(!state.isActive)
    }
    
    @Test("Checking is active")
    func checkingIsActive() {
        let state = RecoveryState.checking
        #expect(state.isActive)
    }
    
    @Test("Recovering is active")
    func recoveringIsActive() {
        let state = RecoveryState.recovering(current: "device1", remaining: 2)
        #expect(state.isActive)
    }
    
    @Test("Complete is not active")
    func completeNotActive() {
        let state = RecoveryState.complete(recovered: 2, failed: 1)
        #expect(!state.isActive)
    }
    
    @Test("State descriptions")
    func stateDescriptions() {
        #expect(RecoveryState.idle.description == "Ready")
        #expect(RecoveryState.checking.description.contains("Checking"))
        #expect(RecoveryState.cancelled.description == "Cancelled")
    }
}

// MARK: - Recovery Result Tests

@Suite("Recovery Result")
struct RecoveryResultTests {
    
    @Test("Creates success result")
    func createsSuccessResult() {
        let result = RecoveryResult(
            deviceId: "TEST",
            success: true,
            duration: 1.5,
            attempts: 1
        )
        
        #expect(result.success)
        #expect(result.attempts == 1)
        #expect(result.errorMessage == nil)
    }
    
    @Test("Creates failure result")
    func createsFailureResult() {
        let result = RecoveryResult(
            deviceId: "TEST",
            success: false,
            duration: 5.0,
            attempts: 3,
            errorMessage: "Timeout"
        )
        
        #expect(!result.success)
        #expect(result.errorMessage == "Timeout")
    }
    
    @Test("Result is Codable")
    func isCodable() throws {
        let result = RecoveryResult(
            deviceId: "ABC",
            success: true,
            duration: 2.0,
            attempts: 2
        )
        
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RecoveryResult.self, from: data)
        
        #expect(decoded.deviceId == result.deviceId)
        #expect(decoded.success == result.success)
    }
}

// MARK: - Recovery Session Tests

@Suite("Recovery Session")
struct RecoverySessionTests {
    
    @Test("Creates session")
    func createsSession() {
        let session = RecoverySession(trigger: .appLaunch)
        
        #expect(session.trigger == .appLaunch)
        #expect(session.results.isEmpty)
        #expect(session.endTime == nil)
    }
    
    @Test("Adds results")
    func addsResults() {
        let session = RecoverySession(trigger: .userRequest)
        
        let result = RecoveryResult(
            deviceId: "TEST",
            success: true,
            duration: 1.0,
            attempts: 1
        )
        
        let updated = session.with(result: result)
        
        #expect(updated.results.count == 1)
        #expect(updated.totalAttempts == 1)
        #expect(updated.successCount == 1)
    }
    
    @Test("Calculates statistics")
    func calculatesStatistics() {
        var session = RecoverySession(trigger: .appLaunch)
        
        session = session.with(result: RecoveryResult(deviceId: "A", success: true, duration: 1, attempts: 1))
        session = session.with(result: RecoveryResult(deviceId: "B", success: false, duration: 5, attempts: 3))
        session = session.with(result: RecoveryResult(deviceId: "C", success: true, duration: 2, attempts: 2))
        
        #expect(session.totalAttempts == 3)
        #expect(session.successCount == 2)
        #expect(session.failureCount == 1)
    }
    
    @Test("Completes session")
    func completesSession() {
        let session = RecoverySession(trigger: .scheduled)
        let completed = session.completed()
        
        #expect(completed.endTime != nil)
        #expect(completed.duration != nil)
    }
    
    @Test("Session is Codable")
    func isCodable() throws {
        var session = RecoverySession(trigger: .bluetoothReset)
        session = session.with(result: RecoveryResult(deviceId: "X", success: true, duration: 1, attempts: 1))
        session = session.completed()
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RecoverySession.self, from: data)
        
        #expect(decoded.trigger == session.trigger)
        #expect(decoded.results.count == 1)
    }
}

// MARK: - Recovery Trigger Tests

@Suite("Recovery Trigger")
struct RecoveryTriggerTests {
    
    @Test("All triggers have values")
    func allTriggersHaveValues() {
        #expect(!RecoveryTrigger.appLaunch.rawValue.isEmpty)
        #expect(!RecoveryTrigger.backgroundWake.rawValue.isEmpty)
    }
    
    @Test("Trigger is Codable")
    func isCodable() throws {
        let trigger = RecoveryTrigger.userRequest
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(RecoveryTrigger.self, from: data)
        #expect(decoded == trigger)
    }
}

// MARK: - Recovery Config Tests

@Suite("Recovery Config")
struct RecoveryConfigTests {
    
    @Test("Default config")
    func defaultConfig() {
        let config = RecoveryConfig.default
        
        #expect(config.strategy == .exponentialBackoff)
        #expect(config.maxAttempts == 5)
    }
    
    @Test("CGM config")
    func cgmConfig() {
        let config = RecoveryConfig.cgm
        
        #expect(config.strategy == .immediate)
        #expect(config.maxAttempts == 10)
    }
    
    @Test("Exponential backoff delay")
    func exponentialBackoffDelay() {
        let config = RecoveryConfig(
            strategy: .exponentialBackoff,
            baseDelaySeconds: 2.0,
            maxDelaySeconds: 60.0
        )
        
        #expect(config.delayForAttempt(1) == 2.0)
        #expect(config.delayForAttempt(2) == 4.0)
        #expect(config.delayForAttempt(3) == 8.0)
        #expect(config.delayForAttempt(6) == 60.0) // Capped at max
    }
    
    @Test("Immediate strategy has no delay")
    func immediateNoDelay() {
        let config = RecoveryConfig(strategy: .immediate)
        
        #expect(config.delayForAttempt(1) == 0)
        #expect(config.delayForAttempt(5) == 0)
    }
    
    @Test("Config is Codable")
    func isCodable() throws {
        let config = RecoveryConfig(
            strategy: .conditional,
            maxAttempts: 3
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RecoveryConfig.self, from: data)
        
        #expect(decoded.strategy == config.strategy)
        #expect(decoded.maxAttempts == config.maxAttempts)
    }
}

// MARK: - In-Memory Persistence Tests

@Suite("In-Memory Device Persistence")
struct InMemoryDevicePersistenceTests {
    
    @Test("Saves and loads devices")
    func savesAndLoadsDevices() async {
        let persistence = InMemoryDevicePersistence()
        let devices = [
            DeviceRecord(id: "A", name: "Device A", deviceType: "cgm"),
            DeviceRecord(id: "B", name: "Device B", deviceType: "pump")
        ]
        
        await persistence.saveDevices(devices)
        let loaded = await persistence.loadDevices()
        
        #expect(loaded.count == 2)
    }
    
    @Test("Saves and loads sessions")
    func savesAndLoadsSessions() async {
        let persistence = InMemoryDevicePersistence()
        let session = RecoverySession(trigger: .appLaunch).completed()
        
        await persistence.saveSession(session)
        let loaded = await persistence.loadSessions(limit: 10)
        
        #expect(loaded.count == 1)
    }
}

// MARK: - UserDefaults Persistence Tests

@Suite("UserDefaults Device Persistence")
struct UserDefaultsDevicePersistenceTests {
    
    @Test("Saves and loads devices")
    func savesAndLoadsDevices() async {
        let defaults = UserDefaults(suiteName: "test.recovery.\(UUID().uuidString)")!
        let persistence = UserDefaultsDevicePersistence(defaults: defaults)
        
        let devices = [
            DeviceRecord(id: "X", name: "CGM", deviceType: "cgm", priority: .critical)
        ]
        
        await persistence.saveDevices(devices)
        let loaded = await persistence.loadDevices()
        
        #expect(loaded.count == 1)
        #expect(loaded[0].priority == .critical)
    }
    
    @Test("Saves and loads sessions with limit")
    func savesAndLoadsSessions() async {
        let defaults = UserDefaults(suiteName: "test.recovery.\(UUID().uuidString)")!
        let persistence = UserDefaultsDevicePersistence(defaults: defaults)
        
        for i in 0..<5 {
            let session = RecoverySession(
                sessionId: "session-\(i)",
                trigger: .scheduled
            ).completed()
            await persistence.saveSession(session)
        }
        
        let loaded = await persistence.loadSessions(limit: 3)
        #expect(loaded.count == 3)
    }
}

// MARK: - Connection Recovery Manager Tests

@Suite("Connection Recovery Manager")
struct ConnectionRecoveryManagerTests {
    
    @Test("Starts in idle state")
    func startsIdle() async {
        let manager = ConnectionRecoveryManager()
        let state = await manager.state()
        #expect(state == .idle)
    }
    
    @Test("Registers device")
    func registersDevice() async {
        let manager = ConnectionRecoveryManager()
        let device = DeviceRecord(id: "TEST", name: "Test", deviceType: "cgm")
        
        await manager.registerDevice(device)
        let devices = await manager.knownDevices()
        
        #expect(devices.count == 1)
        #expect(devices[0].id == "TEST")
    }
    
    @Test("Devices sorted by priority")
    func devicesSortedByPriority() async {
        let manager = ConnectionRecoveryManager()
        
        await manager.registerDevice(DeviceRecord(id: "A", name: "Low", deviceType: "acc", priority: .low))
        await manager.registerDevice(DeviceRecord(id: "B", name: "Critical", deviceType: "cgm", priority: .critical))
        await manager.registerDevice(DeviceRecord(id: "C", name: "Normal", deviceType: "misc", priority: .normal))
        
        let devices = await manager.knownDevices()
        
        #expect(devices[0].priority == .critical)
        #expect(devices[1].priority == .normal)
        #expect(devices[2].priority == .low)
    }
    
    @Test("Updates on connection")
    func updatesOnConnection() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "TEST", name: "Test", deviceType: "cgm", connectionCount: 1))
        
        await manager.deviceConnected("TEST")
        
        let devices = await manager.knownDevices()
        #expect(devices[0].connectionCount == 2)
    }
    
    @Test("Updates on disconnection")
    func updatesOnDisconnection() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "TEST", name: "Test", deviceType: "cgm"))
        
        await manager.deviceDisconnected("TEST")
        
        let devices = await manager.knownDevices()
        #expect(devices[0].lastDisconnected != nil)
    }
    
    @Test("Starts recovery")
    func startsRecovery() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "A", name: "CGM", deviceType: "cgm", priority: .critical))
        
        let session = await manager.startRecovery(trigger: .appLaunch)
        
        #expect(session.trigger == .appLaunch)
        #expect(session.totalAttempts == 1)
    }
    
    @Test("Empty recovery completes immediately")
    func emptyRecovery() async {
        let manager = ConnectionRecoveryManager()
        
        let session = await manager.startRecovery(trigger: .userRequest)
        
        let state = await manager.state()
        #expect(state == .complete(recovered: 0, failed: 0))
        #expect(session.totalAttempts == 0)
    }
    
    @Test("Removes device")
    func removesDevice() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "REMOVE", name: "Test", deviceType: "cgm"))
        
        await manager.removeDevice("REMOVE")
        
        let devices = await manager.knownDevices()
        #expect(devices.isEmpty)
    }
    
    @Test("Clears all devices")
    func clearsAllDevices() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "A", name: "A", deviceType: "a"))
        await manager.registerDevice(DeviceRecord(id: "B", name: "B", deviceType: "b"))
        
        await manager.clearDevices()
        
        let devices = await manager.knownDevices()
        #expect(devices.isEmpty)
    }
    
    @Test("Devices needing recovery")
    func devicesNeedingRecovery() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "CONN", name: "Connected", deviceType: "cgm"))
        await manager.registerDevice(DeviceRecord(id: "DISC", name: "Disconnected", deviceType: "pump"))
        
        await manager.deviceDisconnected("DISC")
        
        let needing = await manager.devicesNeedingRecovery()
        
        #expect(needing.count == 1)
        #expect(needing[0].id == "DISC")
    }
    
    @Test("Restores from persistence")
    func restoresFromPersistence() async {
        let persistence = InMemoryDevicePersistence()
        await persistence.saveDevices([
            DeviceRecord(id: "SAVED", name: "Saved", deviceType: "cgm")
        ])
        
        let manager = ConnectionRecoveryManager(persistence: persistence)
        await manager.restore()
        
        let devices = await manager.knownDevices()
        #expect(devices.count == 1)
        #expect(devices[0].id == "SAVED")
    }
}

// MARK: - Recovery Statistics Tests

@Suite("Recovery Statistics")
struct RecoveryStatisticsTests {
    
    @Test("Calculates from sessions")
    func calculatesFromSessions() {
        var session1 = RecoverySession(trigger: .appLaunch)
        session1 = session1.with(result: RecoveryResult(deviceId: "A", success: true, duration: 1, attempts: 1))
        session1 = session1.with(result: RecoveryResult(deviceId: "B", success: true, duration: 2, attempts: 2))
        session1 = session1.completed()
        
        var session2 = RecoverySession(trigger: .userRequest)
        session2 = session2.with(result: RecoveryResult(deviceId: "C", success: false, duration: 5, attempts: 3))
        session2 = session2.completed()
        
        let stats = RecoveryStatistics(sessions: [session1, session2])
        
        #expect(stats.totalSessions == 2)
        #expect(stats.totalAttempts == 3)
        #expect(stats.totalSuccesses == 2)
        #expect(stats.totalFailures == 1)
        #expect(stats.successRate > 0.66 && stats.successRate < 0.67)
    }
    
    @Test("Empty sessions")
    func emptySessionStats() {
        let stats = RecoveryStatistics(sessions: [])
        
        #expect(stats.totalSessions == 0)
        #expect(stats.successRate == 0)
    }
}

// MARK: - App Launch Recovery Handler Tests

@Suite("App Launch Recovery Handler")
struct AppLaunchRecoveryHandlerTests {
    
    @Test("Handles app launch")
    func handlesAppLaunch() async {
        let persistence = InMemoryDevicePersistence()
        await persistence.saveDevices([
            DeviceRecord(id: "CGM", name: "CGM", deviceType: "cgm", lastDisconnected: Date())
        ])
        
        let manager = ConnectionRecoveryManager(persistence: persistence)
        let handler = AppLaunchRecoveryHandler(manager: manager)
        
        let session = await handler.handleAppLaunch()
        
        #expect(session != nil)
        #expect(session?.trigger == .appLaunch)
    }
    
    @Test("Only recovers once")
    func onlyRecoversOnce() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "X", name: "X", deviceType: "x"))
        await manager.deviceDisconnected("X") // Mark as needing recovery
        
        let handler = AppLaunchRecoveryHandler(manager: manager)
        
        let first = await handler.handleAppLaunch()
        let second = await handler.handleAppLaunch()
        
        #expect(first != nil)
        #expect(second == nil)
    }
    
    @Test("Reset allows another recovery")
    func resetAllowsRecovery() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "X", name: "X", deviceType: "x"))
        await manager.deviceDisconnected("X") // Mark as needing recovery
        
        let handler = AppLaunchRecoveryHandler(manager: manager)
        
        _ = await handler.handleAppLaunch()
        await handler.reset()
        // Re-mark as disconnected for second recovery
        await manager.deviceDisconnected("X")
        let second = await handler.handleAppLaunch()
        
        #expect(second != nil)
    }
    
    @Test("Handles background wake")
    func handlesBackgroundWake() async {
        let manager = ConnectionRecoveryManager()
        await manager.registerDevice(DeviceRecord(id: "BGM", name: "CGM", deviceType: "cgm"))
        await manager.deviceDisconnected("BGM")
        
        let handler = AppLaunchRecoveryHandler(manager: manager)
        
        let session = await handler.handleBackgroundWake()
        
        #expect(session != nil)
        #expect(session?.trigger == .backgroundWake)
    }
}
