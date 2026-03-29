// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// BondingStateManager.swift
// BLEKit
//
// Created for T1Pal - BLE-CONN-005
// Bonding state persistence and recovery across app restarts

import Foundation

// MARK: - Bonding State

/// State of BLE bonding/pairing for a device
public enum BondingState: String, Sendable, Codable, CaseIterable {
    /// Never paired
    case notBonded
    
    /// Pairing in progress
    case bonding
    
    /// Successfully paired/bonded
    case bonded
    
    /// Was bonded but bond was removed/lost
    case bondLost
    
    /// Pairing failed
    case bondFailed
}

// MARK: - Bonding Info

/// Information about a bonded device
public struct BondingInfo: Sendable, Codable, Equatable {
    /// Device identifier (UUID or MAC address)
    public let deviceId: String
    
    /// Device name if known
    public let deviceName: String?
    
    /// Current bonding state
    public let state: BondingState
    
    /// When the bond was established
    public let bondedAt: Date?
    
    /// When the bond was last verified
    public let lastVerifiedAt: Date?
    
    /// Number of times bond has been recovered
    public let recoveryCount: Int
    
    /// Device type (for display purposes)
    public let deviceType: String?
    
    public init(
        deviceId: String,
        deviceName: String? = nil,
        state: BondingState = .notBonded,
        bondedAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        recoveryCount: Int = 0,
        deviceType: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.state = state
        self.bondedAt = bondedAt
        self.lastVerifiedAt = lastVerifiedAt
        self.recoveryCount = recoveryCount
        self.deviceType = deviceType
    }
    
    /// Create updated info with new state
    public func with(state: BondingState) -> BondingInfo {
        BondingInfo(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            bondedAt: state == .bonded && self.bondedAt == nil ? Date() : self.bondedAt,
            lastVerifiedAt: state == .bonded ? Date() : self.lastVerifiedAt,
            recoveryCount: recoveryCount,
            deviceType: deviceType
        )
    }
    
    /// Create updated info with incremented recovery count
    public func withIncrementedRecovery() -> BondingInfo {
        BondingInfo(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            bondedAt: bondedAt,
            lastVerifiedAt: lastVerifiedAt,
            recoveryCount: recoveryCount + 1,
            deviceType: deviceType
        )
    }
    
    /// Create updated info with verified timestamp
    public func withVerification() -> BondingInfo {
        BondingInfo(
            deviceId: deviceId,
            deviceName: deviceName,
            state: state,
            bondedAt: bondedAt,
            lastVerifiedAt: Date(),
            recoveryCount: recoveryCount,
            deviceType: deviceType
        )
    }
}

// MARK: - Bonding Event

/// Events emitted by bonding state manager
public enum BondingEvent: Sendable, Equatable {
    /// Bond state changed
    case stateChanged(deviceId: String, from: BondingState, to: BondingState)
    
    /// Bond was recovered after app restart
    case bondRecovered(deviceId: String)
    
    /// Bond verification succeeded
    case bondVerified(deviceId: String)
    
    /// Bond was lost (e.g., device unpaired externally)
    case bondLost(deviceId: String)
    
    /// Device was removed from storage
    case deviceRemoved(deviceId: String)
}

// MARK: - Storage Protocol

/// Protocol for bonding state storage
public protocol BondingStateStorage: Sendable {
    func save(_ info: BondingInfo) throws
    func load(deviceId: String) -> BondingInfo?
    func loadAll() -> [BondingInfo]
    func delete(deviceId: String) throws
    func deleteAll() throws
}

// MARK: - UserDefaults Storage

/// UserDefaults-based storage for bonding state (cross-platform)
public final class UserDefaultsBondingStorage: BondingStateStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    private let indexKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    
    public init(defaults: UserDefaults = .standard, prefix: String = "com.t1pal.bonding.") {
        self.defaults = defaults
        self.prefix = prefix
        self.indexKey = "\(prefix)device_index"
    }
    
    public func save(_ info: BondingInfo) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let data = try encoder.encode(info)
        defaults.set(data, forKey: key(for: info.deviceId))
        
        // Update index
        var index = deviceIndex()
        if !index.contains(info.deviceId) {
            index.append(info.deviceId)
            defaults.set(index, forKey: indexKey)
        }
    }
    
    public func load(deviceId: String) -> BondingInfo? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = defaults.data(forKey: key(for: deviceId)) else {
            return nil
        }
        return try? decoder.decode(BondingInfo.self, from: data)
    }
    
    public func loadAll() -> [BondingInfo] {
        lock.lock()
        defer { lock.unlock() }
        
        return deviceIndex().compactMap { deviceId in
            guard let data = defaults.data(forKey: key(for: deviceId)) else {
                return nil
            }
            return try? decoder.decode(BondingInfo.self, from: data)
        }
    }
    
    public func delete(deviceId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        defaults.removeObject(forKey: key(for: deviceId))
        
        var index = deviceIndex()
        index.removeAll { $0 == deviceId }
        defaults.set(index, forKey: indexKey)
    }
    
    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        
        for deviceId in deviceIndex() {
            defaults.removeObject(forKey: key(for: deviceId))
        }
        defaults.removeObject(forKey: indexKey)
    }
    
    private func key(for deviceId: String) -> String {
        "\(prefix)\(deviceId)"
    }
    
    private func deviceIndex() -> [String] {
        defaults.stringArray(forKey: indexKey) ?? []
    }
}

// MARK: - In-Memory Storage (Testing)

/// In-memory storage for testing
public final class InMemoryBondingStorage: BondingStateStorage, @unchecked Sendable {
    private var storage: [String: BondingInfo] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func save(_ info: BondingInfo) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[info.deviceId] = info
    }
    
    public func load(deviceId: String) -> BondingInfo? {
        lock.lock()
        defer { lock.unlock() }
        return storage[deviceId]
    }
    
    public func loadAll() -> [BondingInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.values)
    }
    
    public func delete(deviceId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: deviceId)
    }
    
    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - Bonding State Manager

/// Manages bonding state persistence and recovery
public actor BondingStateManager {
    
    // MARK: - Properties
    
    private let storage: BondingStateStorage
    private var cache: [String: BondingInfo] = [:]
    private var eventHandler: (@Sendable (BondingEvent) -> Void)?
    
    // MARK: - Initialization
    
    public init(storage: BondingStateStorage = UserDefaultsBondingStorage()) {
        self.storage = storage
    }
    
    // MARK: - Public API
    
    /// Set event handler for bonding events
    public func setEventHandler(_ handler: @escaping @Sendable (BondingEvent) -> Void) {
        self.eventHandler = handler
    }
    
    /// Load all bonded devices from storage (call on app launch)
    public func loadPersistedBonds() -> [BondingInfo] {
        let bonds = storage.loadAll()
        for bond in bonds {
            cache[bond.deviceId] = bond
        }
        return bonds
    }
    
    /// Get bonding info for a device
    public func bondingInfo(for deviceId: String) -> BondingInfo? {
        if let cached = cache[deviceId] {
            return cached
        }
        if let stored = storage.load(deviceId: deviceId) {
            cache[deviceId] = stored
            return stored
        }
        return nil
    }
    
    /// Get all bonded device IDs
    public func bondedDeviceIds() -> [String] {
        return cache.values
            .filter { $0.state == .bonded }
            .map { $0.deviceId }
    }
    
    /// Get all bonding info
    public func allBondingInfo() -> [BondingInfo] {
        return Array(cache.values)
    }
    
    /// Record that bonding has started
    public func recordBondingStarted(
        deviceId: String,
        deviceName: String? = nil,
        deviceType: String? = nil
    ) throws {
        let existing = bondingInfo(for: deviceId)
        let info = BondingInfo(
            deviceId: deviceId,
            deviceName: deviceName ?? existing?.deviceName,
            state: .bonding,
            bondedAt: existing?.bondedAt,
            lastVerifiedAt: existing?.lastVerifiedAt,
            recoveryCount: existing?.recoveryCount ?? 0,
            deviceType: deviceType ?? existing?.deviceType
        )
        
        try persistAndCache(info)
        
        if let existing = existing {
            emit(.stateChanged(deviceId: deviceId, from: existing.state, to: .bonding))
        }
    }
    
    /// Record successful bond
    public func recordBonded(
        deviceId: String,
        deviceName: String? = nil,
        deviceType: String? = nil
    ) throws {
        let existing = bondingInfo(for: deviceId)
        let info = BondingInfo(
            deviceId: deviceId,
            deviceName: deviceName ?? existing?.deviceName,
            state: .bonded,
            bondedAt: existing?.bondedAt ?? Date(),
            lastVerifiedAt: Date(),
            recoveryCount: existing?.recoveryCount ?? 0,
            deviceType: deviceType ?? existing?.deviceType
        )
        
        try persistAndCache(info)
        
        emit(.stateChanged(
            deviceId: deviceId,
            from: existing?.state ?? .notBonded,
            to: .bonded
        ))
    }
    
    /// Record bond failure
    public func recordBondFailed(deviceId: String) throws {
        let existing = bondingInfo(for: deviceId)
        let info = (existing ?? BondingInfo(deviceId: deviceId)).with(state: .bondFailed)
        
        try persistAndCache(info)
        
        emit(.stateChanged(
            deviceId: deviceId,
            from: existing?.state ?? .notBonded,
            to: .bondFailed
        ))
    }
    
    /// Record bond lost (device unpaired externally)
    public func recordBondLost(deviceId: String) throws {
        guard let existing = bondingInfo(for: deviceId) else { return }
        
        let info = existing.with(state: .bondLost)
        try persistAndCache(info)
        
        emit(.stateChanged(deviceId: deviceId, from: existing.state, to: .bondLost))
        emit(.bondLost(deviceId: deviceId))
    }
    
    /// Verify bond is still valid
    public func verifyBond(deviceId: String) throws {
        guard var info = bondingInfo(for: deviceId), info.state == .bonded else {
            return
        }
        
        info = info.withVerification()
        try persistAndCache(info)
        
        emit(.bondVerified(deviceId: deviceId))
    }
    
    /// Attempt to recover a lost bond
    public func attemptRecovery(deviceId: String) throws -> Bool {
        guard var info = bondingInfo(for: deviceId),
              info.state == .bondLost || info.state == .bondFailed else {
            return false
        }
        
        // Mark as recovering (bonding)
        info = info.withIncrementedRecovery().with(state: .bonding)
        try persistAndCache(info)
        
        return true
    }
    
    /// Record successful recovery
    public func recordRecoverySuccess(deviceId: String) throws {
        guard var info = bondingInfo(for: deviceId) else { return }
        
        info = info.with(state: .bonded)
        try persistAndCache(info)
        
        emit(.bondRecovered(deviceId: deviceId))
        emit(.stateChanged(deviceId: deviceId, from: .bonding, to: .bonded))
    }
    
    /// Remove device from bonding storage
    public func removeDevice(deviceId: String) throws {
        cache.removeValue(forKey: deviceId)
        try storage.delete(deviceId: deviceId)
        
        emit(.deviceRemoved(deviceId: deviceId))
    }
    
    /// Remove all bonding data
    public func removeAllDevices() throws {
        let deviceIds = cache.keys
        cache.removeAll()
        try storage.deleteAll()
        
        for deviceId in deviceIds {
            emit(.deviceRemoved(deviceId: deviceId))
        }
    }
    
    /// Get devices that need recovery (lost or failed bonds)
    public func devicesNeedingRecovery() -> [BondingInfo] {
        return cache.values.filter { 
            $0.state == .bondLost || $0.state == .bondFailed 
        }
    }
    
    /// Get statistics about bonding state
    public func statistics() -> BondingStatistics {
        let all = Array(cache.values)
        return BondingStatistics(
            totalDevices: all.count,
            bondedCount: all.filter { $0.state == .bonded }.count,
            bondLostCount: all.filter { $0.state == .bondLost }.count,
            bondFailedCount: all.filter { $0.state == .bondFailed }.count,
            bondingCount: all.filter { $0.state == .bonding }.count,
            notBondedCount: all.filter { $0.state == .notBonded }.count,
            totalRecoveryAttempts: all.reduce(0) { $0 + $1.recoveryCount }
        )
    }
    
    // MARK: - Private Helpers
    
    private func persistAndCache(_ info: BondingInfo) throws {
        try storage.save(info)
        cache[info.deviceId] = info
    }
    
    private func emit(_ event: BondingEvent) {
        eventHandler?(event)
    }
}

// MARK: - Statistics

/// Statistics about bonding state
public struct BondingStatistics: Sendable, Equatable {
    public let totalDevices: Int
    public let bondedCount: Int
    public let bondLostCount: Int
    public let bondFailedCount: Int
    public let bondingCount: Int
    public let notBondedCount: Int
    public let totalRecoveryAttempts: Int
    
    /// Percentage of devices successfully bonded
    public var bondedPercentage: Double {
        guard totalDevices > 0 else { return 0 }
        return Double(bondedCount) / Double(totalDevices) * 100
    }
    
    /// Whether any devices need recovery
    public var hasDevicesNeedingRecovery: Bool {
        bondLostCount > 0 || bondFailedCount > 0
    }
}
