// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LocalProfileStore.swift
// T1Pal - Open Source AID
//
// Local profile storage using UserDefaults.
// Provides persistent storage for TherapyProfile with JSON serialization.
//
// Trace: CRIT-PROFILE-003

import Foundation

// MARK: - UserDefaults Keys

/// Keys for LocalProfileStore UserDefaults storage
public enum LocalProfileStoreKeys {
    /// Key for the serialized TherapyProfile JSON
    public static let profile = "t1pal.profile.data"
    
    /// Key for tracking if there are unsaved changes
    public static let hasChanges = "t1pal.profile.hasChanges"
    
    /// Key for the last save timestamp
    public static let lastSaved = "t1pal.profile.lastSaved"
}

// MARK: - Local Profile Store

/// Actor-based local profile storage using UserDefaults
/// Conforms to ProfileStore protocol for async CRUD operations
public actor LocalProfileStore: ProfileStore {
    
    // MARK: - Properties
    
    /// UserDefaults instance for storage
    /// nonisolated(unsafe) because UserDefaults is thread-safe but not Sendable
    private nonisolated(unsafe) let defaults: UserDefaults
    
    /// JSON encoder for serialization
    private let encoder = JSONEncoder()
    
    /// JSON decoder for deserialization
    private let decoder = JSONDecoder()
    
    /// Cached profile for fast access
    private var cachedProfile: TherapyProfile?
    
    /// Tracks if there are unsaved changes
    private var _hasUnsavedChanges: Bool = false
    
    // MARK: - Initialization
    
    /// Initialize with custom UserDefaults (for testing)
    /// - Parameter defaults: UserDefaults instance to use
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - ProfileStore Protocol
    
    /// The current active profile
    public var currentProfile: TherapyProfile {
        get async {
            if let cached = cachedProfile {
                return cached
            }
            return (try? await load()) ?? TherapyProfile.default
        }
    }
    
    /// Whether the store has unsaved changes
    public var hasUnsavedChanges: Bool {
        get async {
            _hasUnsavedChanges
        }
    }
    
    /// Load the profile from UserDefaults
    /// - Returns: The stored profile, or default if none exists
    public func load() async throws -> TherapyProfile {
        guard let data = defaults.data(forKey: LocalProfileStoreKeys.profile) else {
            // No stored profile, return default
            let defaultProfile = TherapyProfile.default
            cachedProfile = defaultProfile
            _hasUnsavedChanges = false
            return defaultProfile
        }
        
        do {
            let profile = try decoder.decode(TherapyProfile.self, from: data)
            cachedProfile = profile
            _hasUnsavedChanges = false
            return profile
        } catch {
            throw ProfileStoreError.loadFailed(underlying: error)
        }
    }
    
    /// Save a profile to UserDefaults
    /// - Parameter profile: The profile to save
    public func save(_ profile: TherapyProfile) async throws {
        // Validate before saving
        let validator = ProfileValidator()
        let result = validator.validate(profile)
        
        if !result.isValid {
            throw ProfileStoreError.validationFailed(reason: result.errors.joined(separator: ", "))
        }
        
        do {
            let data = try encoder.encode(profile)
            defaults.set(data, forKey: LocalProfileStoreKeys.profile)
            defaults.set(Date().timeIntervalSince1970, forKey: LocalProfileStoreKeys.lastSaved)
            cachedProfile = profile
            _hasUnsavedChanges = false
        } catch {
            throw ProfileStoreError.saveFailed(underlying: error)
        }
    }
    
    /// Update specific fields of the profile
    /// - Parameter update: Closure that modifies the profile
    public func update(_ update: @Sendable (inout TherapyProfile) -> Void) async throws {
        var profile = await currentProfile
        update(&profile)
        cachedProfile = profile
        _hasUnsavedChanges = true
    }
    
    /// Delete the stored profile and reset to defaults
    public func reset() async throws {
        defaults.removeObject(forKey: LocalProfileStoreKeys.profile)
        defaults.removeObject(forKey: LocalProfileStoreKeys.lastSaved)
        cachedProfile = TherapyProfile.default
        _hasUnsavedChanges = false
    }
    
    /// Discard unsaved changes and reload from storage
    public func discardChanges() async throws {
        _ = try await load()
    }
    
    // MARK: - Additional Methods
    
    /// The timestamp of the last save, if any
    public var lastSavedDate: Date? {
        let timestamp = defaults.double(forKey: LocalProfileStoreKeys.lastSaved)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
    
    /// Check if a profile has been saved before
    public var hasStoredProfile: Bool {
        defaults.data(forKey: LocalProfileStoreKeys.profile) != nil
    }
}

// MARK: - Shared Instance

extension LocalProfileStore {
    /// Shared singleton instance using standard UserDefaults
    public static let shared = LocalProfileStore()
}

// MARK: - Testing Support

extension LocalProfileStore {
    /// Create a test instance with isolated UserDefaults
    /// - Parameter suiteName: Suite name for isolated UserDefaults
    /// - Returns: LocalProfileStore using isolated defaults
    public static func testInstance(suiteName: String = "com.t1pal.test.profileStore") -> LocalProfileStore {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        // Clear any existing test data
        defaults.removePersistentDomain(forName: suiteName)
        return LocalProfileStore(defaults: defaults)
    }
}
