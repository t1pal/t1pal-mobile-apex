// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// MultiNightscoutConfig.swift - Configuration for multiple Nightscout instances
// Part of NightscoutKit
// Trace: NS-MULTI-001, NS-MULTI-003

import Foundation

// MARK: - Instance Priority

/// Priority level for a Nightscout instance
public enum NightscoutInstancePriority: Int, Codable, Sendable, Comparable {
    case primary = 0
    case secondary = 1
    case tertiary = 2
    case backup = 3
    
    public static func < (lhs: NightscoutInstancePriority, rhs: NightscoutInstancePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .tertiary: return "Tertiary"
        case .backup: return "Backup"
        }
    }
}

/// Role of a Nightscout instance in multi-instance setup
public enum NightscoutInstanceRole: String, Codable, Sendable {
    /// Read and write data
    case readWrite = "readWrite"
    
    /// Read only (e.g., clinic access)
    case readOnly = "readOnly"
    
    /// Write only (e.g., backup upload)
    case writeOnly = "writeOnly"
    
    /// Follower mode (read from this instance)
    case follower = "follower"
    
    public var canRead: Bool {
        self == .readWrite || self == .readOnly || self == .follower
    }
    
    public var canWrite: Bool {
        self == .readWrite || self == .writeOnly
    }
}

// MARK: - Instance Configuration

/// Configuration for a single Nightscout instance in a multi-instance setup
public struct NightscoutInstance: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    
    /// Display label for this instance
    public let label: String
    
    /// Base configuration (URL, credentials)
    public let config: NightscoutConfig
    
    /// Priority for failover ordering
    public let priority: NightscoutInstancePriority
    
    /// Role of this instance
    public let role: NightscoutInstanceRole
    
    /// Whether this instance is currently enabled
    public var isEnabled: Bool
    
    /// Optional notes (e.g., "Clinic NS", "Personal backup")
    public let notes: String?
    
    /// Last successful sync time
    public var lastSyncTime: Date?
    
    /// Last error encountered
    public var lastError: String?
    
    /// Consecutive failure count (for failover logic)
    public var failureCount: Int
    
    public init(
        id: UUID = UUID(),
        label: String,
        config: NightscoutConfig,
        priority: NightscoutInstancePriority = .primary,
        role: NightscoutInstanceRole = .readWrite,
        isEnabled: Bool = true,
        notes: String? = nil,
        lastSyncTime: Date? = nil,
        lastError: String? = nil,
        failureCount: Int = 0
    ) {
        self.id = id
        self.label = label
        self.config = config
        self.priority = priority
        self.role = role
        self.isEnabled = isEnabled
        self.notes = notes
        self.lastSyncTime = lastSyncTime
        self.lastError = lastError
        self.failureCount = failureCount
    }
    
    /// Create a client for this instance
    public func createClient() -> NightscoutClient {
        NightscoutClient(config: config)
    }
    
    /// Create a v3 client for this instance (if credentials available)
    public func createV3Client() -> NightscoutV3Client? {
        NightscoutV3Client.from(config: config)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: NightscoutInstance, rhs: NightscoutInstance) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Multi-Instance Configuration

/// Configuration for multiple Nightscout instances
public struct MultiNightscoutConfig: Codable, Sendable {
    /// All configured instances
    public var instances: [NightscoutInstance]
    
    /// Failover settings
    public var failoverSettings: FailoverSettings
    
    /// Sync settings
    public var syncSettings: MultiSyncSettings
    
    /// When this configuration was last modified
    public var lastModified: Date
    
    public init(
        instances: [NightscoutInstance] = [],
        failoverSettings: FailoverSettings = FailoverSettings(),
        syncSettings: MultiSyncSettings = MultiSyncSettings(),
        lastModified: Date = Date()
    ) {
        self.instances = instances
        self.failoverSettings = failoverSettings
        self.syncSettings = syncSettings
        self.lastModified = lastModified
    }
    
    // MARK: - Convenience Accessors
    
    /// Primary instance (highest priority, enabled)
    public var primaryInstance: NightscoutInstance? {
        enabledInstances.first
    }
    
    /// All enabled instances, sorted by priority
    public var enabledInstances: [NightscoutInstance] {
        instances
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
    }
    
    /// Instances that can be read from
    public var readableInstances: [NightscoutInstance] {
        enabledInstances.filter { $0.role.canRead }
    }
    
    /// Instances that can be written to
    public var writableInstances: [NightscoutInstance] {
        enabledInstances.filter { $0.role.canWrite }
    }
    
    /// Get instance by ID
    public func instance(withId id: UUID) -> NightscoutInstance? {
        instances.first { $0.id == id }
    }
    
    /// Get instance by label
    public func instance(withLabel label: String) -> NightscoutInstance? {
        instances.first { $0.label == label }
    }
    
    // MARK: - Mutation Helpers
    
    /// Add a new instance
    public mutating func addInstance(_ instance: NightscoutInstance) {
        instances.append(instance)
        lastModified = Date()
    }
    
    /// Remove an instance by ID
    public mutating func removeInstance(withId id: UUID) {
        instances.removeAll { $0.id == id }
        lastModified = Date()
    }
    
    /// Update an instance
    public mutating func updateInstance(_ instance: NightscoutInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
            lastModified = Date()
        }
    }
    
    /// Enable/disable an instance
    public mutating func setEnabled(_ enabled: Bool, forInstanceId id: UUID) {
        if let index = instances.firstIndex(where: { $0.id == id }) {
            instances[index].isEnabled = enabled
            lastModified = Date()
        }
    }
    
    /// Record a successful sync for an instance
    public mutating func recordSuccess(forInstanceId id: UUID) {
        if let index = instances.firstIndex(where: { $0.id == id }) {
            instances[index].lastSyncTime = Date()
            instances[index].lastError = nil
            instances[index].failureCount = 0
        }
    }
    
    /// Record a failure for an instance
    public mutating func recordFailure(forInstanceId id: UUID, error: String) {
        if let index = instances.firstIndex(where: { $0.id == id }) {
            instances[index].lastError = error
            instances[index].failureCount += 1
        }
    }
}

// MARK: - Failover Settings

/// Settings for automatic failover behavior
public struct FailoverSettings: Codable, Sendable {
    /// Whether automatic failover is enabled
    public var isEnabled: Bool
    
    /// Number of consecutive failures before failover
    public var failureThreshold: Int
    
    /// Time to wait before trying failed instance again (seconds)
    public var retryDelay: TimeInterval
    
    /// Whether to automatically restore primary when healthy
    public var autoRestore: Bool
    
    /// Delay before auto-restore check (seconds)
    public var autoRestoreDelay: TimeInterval
    
    public init(
        isEnabled: Bool = true,
        failureThreshold: Int = 3,
        retryDelay: TimeInterval = 60,
        autoRestore: Bool = true,
        autoRestoreDelay: TimeInterval = 300
    ) {
        self.isEnabled = isEnabled
        self.failureThreshold = failureThreshold
        self.retryDelay = retryDelay
        self.autoRestore = autoRestore
        self.autoRestoreDelay = autoRestoreDelay
    }
}

// MARK: - Multi-Sync Settings

/// Settings for syncing across multiple instances
public struct MultiSyncSettings: Codable, Sendable {
    /// Sync mode for reading data
    public var readMode: MultiReadMode
    
    /// Sync mode for writing data
    public var writeMode: MultiWriteMode
    
    /// Whether to deduplicate entries across instances
    public var deduplicateAcrossInstances: Bool
    
    /// Conflict resolution strategy
    public var conflictResolution: ConflictResolution
    
    public init(
        readMode: MultiReadMode = .primaryOnly,
        writeMode: MultiWriteMode = .primaryOnly,
        deduplicateAcrossInstances: Bool = true,
        conflictResolution: ConflictResolution = .newerWins
    ) {
        self.readMode = readMode
        self.writeMode = writeMode
        self.deduplicateAcrossInstances = deduplicateAcrossInstances
        self.conflictResolution = conflictResolution
    }
}

/// Mode for reading from multiple instances
public enum MultiReadMode: String, Codable, Sendable {
    /// Read only from primary instance
    case primaryOnly = "primaryOnly"
    
    /// Read from primary, fallback to secondary on failure
    case primaryWithFallback = "primaryWithFallback"
    
    /// Read from all instances and merge
    case mergeAll = "mergeAll"
    
    /// Read from fastest responding instance
    case fastest = "fastest"
}

/// Mode for writing to multiple instances
public enum MultiWriteMode: String, Codable, Sendable {
    /// Write only to primary instance
    case primaryOnly = "primaryOnly"
    
    /// Write to all writable instances
    case writeAll = "writeAll"
    
    /// Write to primary, async mirror to others
    case primaryWithMirror = "primaryWithMirror"
}

/// Strategy for resolving conflicts between instances
public enum ConflictResolution: String, Codable, Sendable {
    /// Newer timestamp wins
    case newerWins = "newerWins"
    
    /// Primary instance wins
    case primaryWins = "primaryWins"
    
    /// Keep both (may create duplicates)
    case keepBoth = "keepBoth"
    
    /// Manual resolution required
    case manual = "manual"
}

// MARK: - Factory Methods

extension MultiNightscoutConfig {
    
    /// Create a single-instance configuration
    public static func single(config: NightscoutConfig, label: String = "Primary") -> MultiNightscoutConfig {
        let instance = NightscoutInstance(
            label: label,
            config: config,
            priority: .primary,
            role: .readWrite
        )
        return MultiNightscoutConfig(instances: [instance])
    }
    
    /// Create a primary + backup configuration
    public static func withBackup(
        primary: NightscoutConfig,
        backup: NightscoutConfig,
        primaryLabel: String = "Primary",
        backupLabel: String = "Backup"
    ) -> MultiNightscoutConfig {
        let primaryInstance = NightscoutInstance(
            label: primaryLabel,
            config: primary,
            priority: .primary,
            role: .readWrite
        )
        let backupInstance = NightscoutInstance(
            label: backupLabel,
            config: backup,
            priority: .backup,
            role: .writeOnly
        )
        return MultiNightscoutConfig(instances: [primaryInstance, backupInstance])
    }
    
    /// Create a primary + follower configuration
    public static func withFollower(
        primary: NightscoutConfig,
        follower: NightscoutConfig,
        primaryLabel: String = "Primary",
        followerLabel: String = "Follower"
    ) -> MultiNightscoutConfig {
        let primaryInstance = NightscoutInstance(
            label: primaryLabel,
            config: primary,
            priority: .primary,
            role: .readWrite
        )
        let followerInstance = NightscoutInstance(
            label: followerLabel,
            config: follower,
            priority: .secondary,
            role: .follower
        )
        return MultiNightscoutConfig(
            instances: [primaryInstance, followerInstance],
            syncSettings: MultiSyncSettings(readMode: .primaryWithFallback)
        )
    }
}
