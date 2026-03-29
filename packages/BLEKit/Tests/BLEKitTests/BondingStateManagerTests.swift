// BondingStateManagerTests.swift
// BLEKitTests
//
// Tests for BLE-CONN-005: Bonding state persistence and recovery

import Testing
import Foundation
@testable import BLEKit

@Suite("Bonding State")
struct BondingStateTests {
    
    @Test("State has raw values")
    func stateRawValues() {
        #expect(BondingState.notBonded.rawValue == "notBonded")
        #expect(BondingState.bonding.rawValue == "bonding")
        #expect(BondingState.bonded.rawValue == "bonded")
        #expect(BondingState.bondLost.rawValue == "bondLost")
        #expect(BondingState.bondFailed.rawValue == "bondFailed")
    }
    
    @Test("State is case iterable")
    func stateCaseIterable() {
        #expect(BondingState.allCases.count == 5)
    }
    
    @Test("State is codable")
    func stateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in BondingState.allCases {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(BondingState.self, from: data)
            #expect(decoded == state)
        }
    }
}

@Suite("Bonding Info")
struct BondingInfoTests {
    
    @Test("Create bonding info")
    func createBondingInfo() {
        let info = BondingInfo(
            deviceId: "device123",
            deviceName: "Test Device",
            state: .bonded,
            bondedAt: Date(),
            deviceType: "CGM"
        )
        
        #expect(info.deviceId == "device123")
        #expect(info.deviceName == "Test Device")
        #expect(info.state == .bonded)
        #expect(info.deviceType == "CGM")
    }
    
    @Test("Default values")
    func defaultValues() {
        let info = BondingInfo(deviceId: "device123")
        
        #expect(info.state == .notBonded)
        #expect(info.bondedAt == nil)
        #expect(info.lastVerifiedAt == nil)
        #expect(info.recoveryCount == 0)
    }
    
    @Test("With state creates new info")
    func withStateCreatesNewInfo() {
        let info = BondingInfo(deviceId: "device123", state: .notBonded)
        let bonded = info.with(state: .bonded)
        
        #expect(bonded.state == .bonded)
        #expect(bonded.deviceId == info.deviceId)
        #expect(bonded.bondedAt != nil)
        #expect(bonded.lastVerifiedAt != nil)
    }
    
    @Test("With state preserves existing bonded date")
    func withStatePreservesBondedDate() {
        let originalDate = Date(timeIntervalSince1970: 1000000)
        let info = BondingInfo(
            deviceId: "device123",
            state: .bonded,
            bondedAt: originalDate
        )
        
        let updated = info.with(state: .bonded)
        
        #expect(updated.bondedAt == originalDate)
    }
    
    @Test("With incremented recovery")
    func withIncrementedRecovery() {
        let info = BondingInfo(deviceId: "device123", recoveryCount: 2)
        let incremented = info.withIncrementedRecovery()
        
        #expect(incremented.recoveryCount == 3)
    }
    
    @Test("With verification updates timestamp")
    func withVerificationUpdatesTimestamp() {
        let info = BondingInfo(deviceId: "device123")
        let verified = info.withVerification()
        
        #expect(verified.lastVerifiedAt != nil)
    }
    
    @Test("Bonding info is codable")
    func bondingInfoCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let info = BondingInfo(
            deviceId: "device123",
            deviceName: "Test",
            state: .bonded,
            bondedAt: Date(),
            lastVerifiedAt: Date(),
            recoveryCount: 1,
            deviceType: "CGM"
        )
        
        let data = try encoder.encode(info)
        let decoded = try decoder.decode(BondingInfo.self, from: data)
        
        #expect(decoded == info)
    }
    
    @Test("Bonding info is equatable")
    func bondingInfoEquatable() {
        let date = Date()
        let i1 = BondingInfo(
            deviceId: "device123",
            state: .bonded,
            bondedAt: date
        )
        let i2 = BondingInfo(
            deviceId: "device123",
            state: .bonded,
            bondedAt: date
        )
        
        #expect(i1 == i2)
    }
}

@Suite("Bonding Event")
struct BondingEventTests {
    
    @Test("State changed event")
    func stateChangedEvent() {
        let event = BondingEvent.stateChanged(
            deviceId: "device123",
            from: .notBonded,
            to: .bonded
        )
        
        if case .stateChanged(let deviceId, let from, let to) = event {
            #expect(deviceId == "device123")
            #expect(from == .notBonded)
            #expect(to == .bonded)
        } else {
            #expect(Bool(false), "Wrong event type")
        }
    }
    
    @Test("Event is equatable")
    func eventEquatable() {
        let e1 = BondingEvent.bondRecovered(deviceId: "device123")
        let e2 = BondingEvent.bondRecovered(deviceId: "device123")
        let e3 = BondingEvent.bondLost(deviceId: "device123")
        
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
}

@Suite("In-Memory Bonding Storage")
struct InMemoryBondingStorageTests {
    
    @Test("Save and load")
    func saveAndLoad() throws {
        let storage = InMemoryBondingStorage()
        let info = BondingInfo(deviceId: "device123", state: .bonded)
        
        try storage.save(info)
        let loaded = storage.load(deviceId: "device123")
        
        #expect(loaded != nil)
        #expect(loaded?.deviceId == "device123")
        #expect(loaded?.state == .bonded)
    }
    
    @Test("Load returns nil for unknown device")
    func loadReturnsNilForUnknown() {
        let storage = InMemoryBondingStorage()
        let loaded = storage.load(deviceId: "unknown")
        
        #expect(loaded == nil)
    }
    
    @Test("Load all")
    func loadAll() throws {
        let storage = InMemoryBondingStorage()
        try storage.save(BondingInfo(deviceId: "device1"))
        try storage.save(BondingInfo(deviceId: "device2"))
        try storage.save(BondingInfo(deviceId: "device3"))
        
        let all = storage.loadAll()
        #expect(all.count == 3)
    }
    
    @Test("Delete")
    func delete() throws {
        let storage = InMemoryBondingStorage()
        try storage.save(BondingInfo(deviceId: "device123"))
        try storage.delete(deviceId: "device123")
        
        let loaded = storage.load(deviceId: "device123")
        #expect(loaded == nil)
    }
    
    @Test("Delete all")
    func deleteAll() throws {
        let storage = InMemoryBondingStorage()
        try storage.save(BondingInfo(deviceId: "device1"))
        try storage.save(BondingInfo(deviceId: "device2"))
        try storage.deleteAll()
        
        let all = storage.loadAll()
        #expect(all.isEmpty)
    }
}

@Suite("UserDefaults Bonding Storage")
struct UserDefaultsBondingStorageTests {
    
    @Test("Save and load")
    func saveAndLoad() throws {
        let defaults = UserDefaults(suiteName: "test.bonding.\(UUID().uuidString)")!
        let storage = UserDefaultsBondingStorage(defaults: defaults)
        let info = BondingInfo(deviceId: "device123", state: .bonded)
        
        try storage.save(info)
        let loaded = storage.load(deviceId: "device123")
        
        #expect(loaded != nil)
        #expect(loaded?.deviceId == "device123")
    }
    
    @Test("Load all")
    func loadAll() throws {
        let defaults = UserDefaults(suiteName: "test.bonding.\(UUID().uuidString)")!
        let storage = UserDefaultsBondingStorage(defaults: defaults)
        
        try storage.save(BondingInfo(deviceId: "device1"))
        try storage.save(BondingInfo(deviceId: "device2"))
        
        let all = storage.loadAll()
        #expect(all.count == 2)
    }
    
    @Test("Delete")
    func delete() throws {
        let defaults = UserDefaults(suiteName: "test.bonding.\(UUID().uuidString)")!
        let storage = UserDefaultsBondingStorage(defaults: defaults)
        
        try storage.save(BondingInfo(deviceId: "device123"))
        try storage.delete(deviceId: "device123")
        
        let loaded = storage.load(deviceId: "device123")
        #expect(loaded == nil)
    }
    
    @Test("Delete all")
    func deleteAll() throws {
        let defaults = UserDefaults(suiteName: "test.bonding.\(UUID().uuidString)")!
        let storage = UserDefaultsBondingStorage(defaults: defaults)
        
        try storage.save(BondingInfo(deviceId: "device1"))
        try storage.save(BondingInfo(deviceId: "device2"))
        try storage.deleteAll()
        
        let all = storage.loadAll()
        #expect(all.isEmpty)
    }
}

@Suite("Bonding State Manager")
struct BondingStateManagerTests {
    
    func createManager() -> BondingStateManager {
        BondingStateManager(storage: InMemoryBondingStorage())
    }
    
    @Test("Record bonding started")
    func recordBondingStarted() async throws {
        let manager = createManager()
        
        try await manager.recordBondingStarted(
            deviceId: "device123",
            deviceName: "Test Device",
            deviceType: "CGM"
        )
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info != nil)
        #expect(info?.state == .bonding)
        #expect(info?.deviceName == "Test Device")
        #expect(info?.deviceType == "CGM")
    }
    
    @Test("Record bonded")
    func recordBonded() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.state == .bonded)
        #expect(info?.bondedAt != nil)
        #expect(info?.lastVerifiedAt != nil)
    }
    
    @Test("Record bond failed")
    func recordBondFailed() async throws {
        let manager = createManager()
        
        try await manager.recordBondingStarted(deviceId: "device123")
        try await manager.recordBondFailed(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.state == .bondFailed)
    }
    
    @Test("Record bond lost")
    func recordBondLost() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        try await manager.recordBondLost(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.state == .bondLost)
    }
    
    @Test("Verify bond")
    func verifyBond() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        
        // Wait a bit then verify
        try await Task.sleep(for: .milliseconds(10))
        try await manager.verifyBond(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.lastVerifiedAt != nil)
    }
    
    @Test("Bonded device IDs")
    func bondedDeviceIds() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device1")
        try await manager.recordBonded(deviceId: "device2")
        try await manager.recordBondingStarted(deviceId: "device3")
        
        let bondedIds = await manager.bondedDeviceIds()
        #expect(bondedIds.count == 2)
        #expect(bondedIds.contains("device1"))
        #expect(bondedIds.contains("device2"))
    }
    
    @Test("Attempt recovery")
    func attemptRecovery() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        try await manager.recordBondLost(deviceId: "device123")
        
        let canRecover = try await manager.attemptRecovery(deviceId: "device123")
        #expect(canRecover == true)
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.state == .bonding)
        #expect(info?.recoveryCount == 1)
    }
    
    @Test("Recovery success")
    func recoverySuccess() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        try await manager.recordBondLost(deviceId: "device123")
        _ = try await manager.attemptRecovery(deviceId: "device123")
        try await manager.recordRecoverySuccess(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info?.state == .bonded)
    }
    
    @Test("Remove device")
    func removeDevice() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device123")
        try await manager.removeDevice(deviceId: "device123")
        
        let info = await manager.bondingInfo(for: "device123")
        #expect(info == nil)
    }
    
    @Test("Remove all devices")
    func removeAllDevices() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device1")
        try await manager.recordBonded(deviceId: "device2")
        try await manager.removeAllDevices()
        
        let all = await manager.allBondingInfo()
        #expect(all.isEmpty)
    }
    
    @Test("Devices needing recovery")
    func devicesNeedingRecovery() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device1")
        try await manager.recordBondLost(deviceId: "device1")
        try await manager.recordBonded(deviceId: "device2")
        try await manager.recordBondFailed(deviceId: "device3")
        
        let needRecovery = await manager.devicesNeedingRecovery()
        #expect(needRecovery.count == 2)
    }
    
    @Test("Statistics")
    func statistics() async throws {
        let manager = createManager()
        
        try await manager.recordBonded(deviceId: "device1")
        try await manager.recordBonded(deviceId: "device2")
        try await manager.recordBondLost(deviceId: "device2")
        try await manager.recordBondFailed(deviceId: "device3")
        
        let stats = await manager.statistics()
        
        #expect(stats.totalDevices == 3)
        #expect(stats.bondedCount == 1)
        #expect(stats.bondLostCount == 1)
        #expect(stats.bondFailedCount == 1)
        #expect(stats.hasDevicesNeedingRecovery == true)
    }
    
    @Test("Load persisted bonds")
    func loadPersistedBonds() async throws {
        let storage = InMemoryBondingStorage()
        try storage.save(BondingInfo(deviceId: "device1", state: .bonded))
        try storage.save(BondingInfo(deviceId: "device2", state: .bonded))
        
        let manager = BondingStateManager(storage: storage)
        let bonds = await manager.loadPersistedBonds()
        
        #expect(bonds.count == 2)
        
        // Should be cached now
        let info = await manager.bondingInfo(for: "device1")
        #expect(info != nil)
    }
}

@Suite("Bonding Event Handler")
struct BondingEventHandlerTests {
    
    @Test("Event handler receives events")
    func eventHandlerReceivesEvents() async throws {
        let manager = BondingStateManager(storage: InMemoryBondingStorage())
        
        actor EventCollector {
            var events: [BondingEvent] = []
            func append(_ event: BondingEvent) { events.append(event) }
            var count: Int { events.count }
        }
        
        let collector = EventCollector()
        await manager.setEventHandler { event in
            Task { await collector.append(event) }
        }
        
        try await manager.recordBonded(deviceId: "device123")
        
        try await Task.sleep(for: .milliseconds(50))
        
        let count = await collector.count
        #expect(count >= 1)
    }
}

@Suite("Bonding Statistics")
struct BondingStatisticsTests {
    
    @Test("Bonded percentage")
    func bondedPercentage() {
        let stats = BondingStatistics(
            totalDevices: 4,
            bondedCount: 3,
            bondLostCount: 1,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        #expect(stats.bondedPercentage == 75)
    }
    
    @Test("Bonded percentage with zero devices")
    func bondedPercentageZeroDevices() {
        let stats = BondingStatistics(
            totalDevices: 0,
            bondedCount: 0,
            bondLostCount: 0,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        #expect(stats.bondedPercentage == 0)
    }
    
    @Test("Has devices needing recovery")
    func hasDevicesNeedingRecovery() {
        let needsRecovery = BondingStatistics(
            totalDevices: 2,
            bondedCount: 1,
            bondLostCount: 1,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        let noRecoveryNeeded = BondingStatistics(
            totalDevices: 2,
            bondedCount: 2,
            bondLostCount: 0,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        #expect(needsRecovery.hasDevicesNeedingRecovery == true)
        #expect(noRecoveryNeeded.hasDevicesNeedingRecovery == false)
    }
    
    @Test("Statistics is equatable")
    func statisticsEquatable() {
        let s1 = BondingStatistics(
            totalDevices: 2,
            bondedCount: 2,
            bondLostCount: 0,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        let s2 = BondingStatistics(
            totalDevices: 2,
            bondedCount: 2,
            bondLostCount: 0,
            bondFailedCount: 0,
            bondingCount: 0,
            notBondedCount: 0,
            totalRecoveryAttempts: 0
        )
        
        #expect(s1 == s2)
    }
}
