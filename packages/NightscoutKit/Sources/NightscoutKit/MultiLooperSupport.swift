// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MultiLooperSupport.swift
// NightscoutKit
//
// Multi-instance looper profile management
// Extracted from NightscoutClient.swift (NS-REFACTOR-013)
// Requirements: REQ-ID-007

import Foundation
import T1PalCore

// MARK: - Multi-Looper Support (ID-007)

/// Looper profile for multi-instance management
/// Requirements: REQ-ID-007
public struct LooperProfile: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let nightscoutUrl: URL
    public let color: String?
    public let emoji: String?
    public let isActive: Bool
    public let createdAt: Date
    public let lastAccessedAt: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        nightscoutUrl: URL,
        color: String? = nil,
        emoji: String? = nil,
        isActive: Bool = false,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.nightscoutUrl = nightscoutUrl
        self.color = color
        self.emoji = emoji
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
    
    /// Create updated profile with new access time
    public func withAccessTime(_ date: Date = Date()) -> LooperProfile {
        LooperProfile(
            id: id,
            name: name,
            nightscoutUrl: nightscoutUrl,
            color: color,
            emoji: emoji,
            isActive: isActive,
            createdAt: createdAt,
            lastAccessedAt: date
        )
    }
    
    /// Create updated profile with active status
    public func withActiveStatus(_ active: Bool) -> LooperProfile {
        LooperProfile(
            id: id,
            name: name,
            nightscoutUrl: nightscoutUrl,
            color: color,
            emoji: emoji,
            isActive: active,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: LooperProfile, rhs: LooperProfile) -> Bool {
        lhs.id == rhs.id
    }
}

/// Instance registry change event
/// Requirements: REQ-ID-007
public enum InstanceRegistryEvent: Sendable {
    case added(LooperProfile)
    case removed(UUID)
    case updated(LooperProfile)
    case activeChanged(LooperProfile?)
}

/// Observer protocol for registry changes
/// Requirements: REQ-ID-007
public protocol InstanceRegistryObserver: AnyObject, Sendable {
    func registryDidChange(_ event: InstanceRegistryEvent)
}

/// Multi-instance registry for managing looper profiles
/// Requirements: REQ-ID-007
public actor InstanceRegistry {
    private var profiles: [UUID: LooperProfile] = [:]
    private var activeProfileId: UUID?
    private let credentialStore: any CredentialStoring
    private let auth: NightscoutAuth
    private weak var observer: (any InstanceRegistryObserver)?
    
    public init(
        credentialStore: any CredentialStoring = MemoryCredentialStore(),
        auth: NightscoutAuth? = nil
    ) {
        self.credentialStore = credentialStore
        self.auth = auth ?? NightscoutAuth(credentialStore: credentialStore)
    }
    
    /// Set observer for registry changes
    public func setObserver(_ observer: any InstanceRegistryObserver) {
        self.observer = observer
    }
    
    /// Add a new looper profile
    public func addProfile(_ profile: LooperProfile) async {
        var newProfile = profile
        
        // If this is the first profile, make it active
        if profiles.isEmpty {
            newProfile = profile.withActiveStatus(true)
            activeProfileId = profile.id
        }
        
        profiles[profile.id] = newProfile
        observer?.registryDidChange(.added(newProfile))
        
        if newProfile.isActive {
            observer?.registryDidChange(.activeChanged(newProfile))
        }
    }
    
    /// Add profile with authentication
    public func addProfile(
        name: String,
        url: URL,
        apiSecret: String,
        color: String? = nil,
        emoji: String? = nil
    ) async throws -> LooperProfile {
        // Authenticate first
        let authState = try await auth.authenticateWithSecret(url: url, apiSecret: apiSecret)
        
        guard authState.isAuthenticated else {
            throw NightscoutDiscoveryError.authenticationFailed
        }
        
        let profile = LooperProfile(
            name: name.isEmpty ? (authState.serverName ?? url.host ?? "Nightscout") : name,
            nightscoutUrl: url,
            color: color,
            emoji: emoji
        )
        
        await addProfile(profile)
        return profile
    }
    
    /// Remove a looper profile
    public func removeProfile(_ id: UUID) async throws {
        guard let profile = profiles.removeValue(forKey: id) else {
            throw InstanceRegistryError.profileNotFound
        }
        
        // Remove associated credentials
        let key = CredentialKey.nightscout(url: profile.nightscoutUrl)
        try? await credentialStore.delete(for: key)
        
        // If removing active profile, clear active or switch
        if id == activeProfileId {
            activeProfileId = profiles.values.first?.id
            if let newActive = activeProfileId {
                profiles[newActive] = profiles[newActive]?.withActiveStatus(true)
                observer?.registryDidChange(.activeChanged(profiles[newActive]))
            } else {
                observer?.registryDidChange(.activeChanged(nil))
            }
        }
        
        observer?.registryDidChange(.removed(id))
    }
    
    /// Update a looper profile
    public func updateProfile(_ profile: LooperProfile) async throws {
        guard profiles[profile.id] != nil else {
            throw InstanceRegistryError.profileNotFound
        }
        
        profiles[profile.id] = profile
        observer?.registryDidChange(.updated(profile))
    }
    
    /// Get all profiles
    public func getAllProfiles() -> [LooperProfile] {
        Array(profiles.values).sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Get profile by ID
    public func getProfile(_ id: UUID) -> LooperProfile? {
        profiles[id]
    }
    
    /// Get profile by URL
    public func getProfile(for url: URL) -> LooperProfile? {
        profiles.values.first { $0.nightscoutUrl == url }
    }
    
    /// Get active profile
    public func getActiveProfile() -> LooperProfile? {
        guard let id = activeProfileId else { return nil }
        return profiles[id]
    }
    
    /// Switch active profile
    public func setActiveProfile(_ id: UUID) async throws {
        guard var profile = profiles[id] else {
            throw InstanceRegistryError.profileNotFound
        }
        
        // Deactivate current
        if let currentId = activeProfileId, let current = profiles[currentId] {
            profiles[currentId] = current.withActiveStatus(false)
        }
        
        // Activate new
        profile = profile.withActiveStatus(true).withAccessTime()
        profiles[id] = profile
        activeProfileId = id
        
        observer?.registryDidChange(.activeChanged(profile))
    }
    
    /// Get client for active profile
    public func getActiveClient() async throws -> NightscoutClient {
        guard let profile = getActiveProfile() else {
            throw InstanceRegistryError.noActiveProfile
        }
        
        return try await getClient(for: profile.id)
    }
    
    /// Get client for specific profile
    public func getClient(for profileId: UUID) async throws -> NightscoutClient {
        guard let profile = profiles[profileId] else {
            throw InstanceRegistryError.profileNotFound
        }
        
        // Get stored credential
        let key = CredentialKey.nightscout(url: profile.nightscoutUrl)
        let credential = try await credentialStore.retrieve(for: key)
        
        let config: NightscoutConfig
        switch credential.tokenType {
        case .apiSecret:
            config = NightscoutConfig(url: profile.nightscoutUrl, apiSecret: credential.value)
        case .access:
            config = NightscoutConfig(url: profile.nightscoutUrl, token: credential.value)
        default:
            config = NightscoutConfig(url: profile.nightscoutUrl)
        }
        
        // Update access time
        profiles[profileId] = profile.withAccessTime()
        
        return NightscoutClient(config: config)
    }
    
    /// Get profile count
    public func getProfileCount() -> Int {
        profiles.count
    }
    
    /// Check if any profiles exist
    public var isEmpty: Bool {
        profiles.isEmpty
    }
    
    /// Export profiles for persistence
    public func exportProfiles() -> [LooperProfile] {
        getAllProfiles()
    }
    
    /// Import profiles from persistence
    public func importProfiles(_ profiles: [LooperProfile]) async {
        for profile in profiles {
            self.profiles[profile.id] = profile
            if profile.isActive {
                activeProfileId = profile.id
            }
        }
    }
    
    /// Clear all profiles
    public func clear() async {
        for profile in profiles.values {
            let key = CredentialKey.nightscout(url: profile.nightscoutUrl)
            try? await credentialStore.delete(for: key)
        }
        profiles.removeAll()
        activeProfileId = nil
        observer?.registryDidChange(.activeChanged(nil))
    }
}

/// Instance registry errors
/// Requirements: REQ-ID-007
public enum InstanceRegistryError: Error, Sendable {
    case profileNotFound
    case noActiveProfile
    case duplicateUrl
    case authenticationRequired
    case credentialNotFound
}

/// Quick switcher for active instances
/// Requirements: REQ-ID-007
public actor InstanceSwitcher {
    private let registry: InstanceRegistry
    private var recentOrder: [UUID] = []
    private let maxRecent: Int
    
    public init(registry: InstanceRegistry, maxRecent: Int = 5) {
        self.registry = registry
        self.maxRecent = maxRecent
    }
    
    /// Switch to profile and update recent order
    public func switchTo(_ id: UUID) async throws {
        try await registry.setActiveProfile(id)
        
        // Update recent order
        recentOrder.removeAll { $0 == id }
        recentOrder.insert(id, at: 0)
        
        // Trim to max
        if recentOrder.count > maxRecent {
            recentOrder = Array(recentOrder.prefix(maxRecent))
        }
    }
    
    /// Get recently used profiles in order
    public func getRecentProfiles() async -> [LooperProfile] {
        var result: [LooperProfile] = []
        for id in recentOrder {
            if let profile = await registry.getProfile(id) {
                result.append(profile)
            }
        }
        return result
    }
    
    /// Switch to next profile in order
    public func switchToNext() async throws {
        let profiles = await registry.getAllProfiles()
        guard profiles.count > 1 else { return }
        
        let active = await registry.getActiveProfile()
        guard let currentIndex = profiles.firstIndex(where: { $0.id == active?.id }) else {
            throw InstanceRegistryError.noActiveProfile
        }
        
        let nextIndex = (currentIndex + 1) % profiles.count
        try await switchTo(profiles[nextIndex].id)
    }
    
    /// Switch to previous profile in order
    public func switchToPrevious() async throws {
        let profiles = await registry.getAllProfiles()
        guard profiles.count > 1 else { return }
        
        let active = await registry.getActiveProfile()
        guard let currentIndex = profiles.firstIndex(where: { $0.id == active?.id }) else {
            throw InstanceRegistryError.noActiveProfile
        }
        
        let prevIndex = currentIndex == 0 ? profiles.count - 1 : currentIndex - 1
        try await switchTo(profiles[prevIndex].id)
    }
}

/// Aggregate data from multiple instances
/// Requirements: REQ-ID-007
public actor MultiInstanceAggregator {
    private let registry: InstanceRegistry
    
    public init(registry: InstanceRegistry) {
        self.registry = registry
    }
    
    /// Fetch latest entry from all instances
    public func fetchLatestFromAll() async -> [UUID: NightscoutEntry?] {
        var results: [UUID: NightscoutEntry?] = [:]
        let profiles = await registry.getAllProfiles()
        
        for profile in profiles {
            do {
                let client = try await registry.getClient(for: profile.id)
                let entries = try await client.fetchEntries(count: 1)
                results[profile.id] = entries.first
            } catch {
                results[profile.id] = nil
            }
        }
        
        return results
    }
    
    /// Get quick status for all instances
    public func getQuickStatus() async -> [LooperQuickStatus] {
        var results: [LooperQuickStatus] = []
        let profiles = await registry.getAllProfiles()
        
        for profile in profiles {
            var status = LooperQuickStatus(profile: profile)
            
            do {
                let client = try await registry.getClient(for: profile.id)
                let entries = try await client.fetchEntries(count: 1)
                if let latest = entries.first {
                    status.latestGlucose = latest.sgv
                    status.glucoseDate = Date(timeIntervalSince1970: TimeInterval(latest.date) / 1000)
                    status.direction = latest.direction
                    status.isReachable = true
                }
            } catch {
                status.isReachable = false
                status.error = error.localizedDescription
            }
            
            results.append(status)
        }
        
        return results
    }
}

/// Quick status for a looper
/// Requirements: REQ-ID-007
public struct LooperQuickStatus: Sendable {
    public let profile: LooperProfile
    public var latestGlucose: Int?
    public var glucoseDate: Date?
    public var direction: String?
    public var isReachable: Bool
    public var error: String?
    
    public init(
        profile: LooperProfile,
        latestGlucose: Int? = nil,
        glucoseDate: Date? = nil,
        direction: String? = nil,
        isReachable: Bool = false,
        error: String? = nil
    ) {
        self.profile = profile
        self.latestGlucose = latestGlucose
        self.glucoseDate = glucoseDate
        self.direction = direction
        self.isReachable = isReachable
        self.error = error
    }
    
    /// Data age in seconds
    public var dataAge: TimeInterval? {
        glucoseDate?.timeIntervalSinceNow.magnitude
    }
    
    /// Check if data is stale (> 10 minutes)
    public var isStale: Bool {
        guard let age = dataAge else { return true }
        return age > 600
    }
}
