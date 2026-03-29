// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SyncableCredentialStore.swift
// T1PalCore
//
// iCloud Keychain sync support for credential storage.
// Wraps KeychainCredentialStore with sync configuration.
// Trace: ID-KEYCHAIN-002, PRD-003, REQ-ID-002

import Foundation

#if canImport(Security)
import Security
#endif

// MARK: - Sync Mode

/// Credential synchronization mode
public enum CredentialSyncMode: String, Sendable, Codable, CaseIterable {
    /// Store locally only (default, most secure)
    case local
    
    /// Sync via iCloud Keychain across user's devices
    case iCloudSync
    
    public var displayName: String {
        switch self {
        case .local: return "This Device Only"
        case .iCloudSync: return "iCloud Keychain"
        }
    }
    
    public var description: String {
        switch self {
        case .local:
            return "Credentials are stored only on this device"
        case .iCloudSync:
            return "Credentials sync across your Apple devices via iCloud Keychain"
        }
    }
}

// MARK: - Sync Status

/// iCloud Keychain sync availability status
public enum SyncAvailability: Sendable, Equatable {
    case available
    case unavailable(SyncUnavailableReason)
    
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// Reasons why iCloud sync may be unavailable
public enum SyncUnavailableReason: String, Sendable, Codable {
    case notSignedIn
    case keychainSyncDisabled
    case platformNotSupported
    case restricted
    case unknown
    
    public var localizedDescription: String {
        switch self {
        case .notSignedIn:
            return "Sign in to iCloud to sync credentials"
        case .keychainSyncDisabled:
            return "Enable iCloud Keychain in Settings"
        case .platformNotSupported:
            return "iCloud Keychain is not available on this platform"
        case .restricted:
            return "iCloud Keychain is restricted by device management"
        case .unknown:
            return "iCloud Keychain sync is unavailable"
        }
    }
}

// MARK: - Sync Configuration

/// Configuration for credential synchronization
public struct SyncConfiguration: Sendable, Codable {
    /// Sync mode for credentials
    public var mode: CredentialSyncMode
    
    /// Whether to migrate existing local credentials when enabling sync
    public var migrateOnEnable: Bool
    
    /// Whether to keep local copy when disabling sync
    public var keepLocalOnDisable: Bool
    
    /// Credential types that should sync (nil = all)
    public var syncableTypes: Set<TokenType>?
    
    public init(
        mode: CredentialSyncMode = .local,
        migrateOnEnable: Bool = true,
        keepLocalOnDisable: Bool = true,
        syncableTypes: Set<TokenType>? = nil
    ) {
        self.mode = mode
        self.migrateOnEnable = migrateOnEnable
        self.keepLocalOnDisable = keepLocalOnDisable
        self.syncableTypes = syncableTypes
    }
    
    /// Default configuration (local only)
    public static let `default` = SyncConfiguration()
    
    /// iCloud sync enabled for all credential types
    public static let iCloudAll = SyncConfiguration(mode: .iCloudSync)
    
    /// iCloud sync for OAuth tokens only (most common use case)
    public static let iCloudOAuth = SyncConfiguration(
        mode: .iCloudSync,
        syncableTypes: [.access, .refresh]
    )
}

// MARK: - Syncable Credential Store

/// Credential store with iCloud Keychain sync support.
/// Wraps credential storage with configurable synchronization.
///
/// Trace: ID-KEYCHAIN-002
/// Requirements: REQ-ID-002
public actor SyncableCredentialStore {
    
    /// Configuration for sync behavior
    private var configuration: SyncConfiguration
    
    /// Service prefix for Keychain items
    private let servicePrefix: String
    
    /// Access group for shared Keychain access
    private let accessGroup: String?
    
    /// Encoder for credential serialization
    private let encoder = JSONEncoder()
    
    /// Decoder for credential deserialization
    private let decoder = JSONDecoder()
    
    /// Index of stored keys
    private var keyIndex: Set<String> = []
    
    /// Key for storing the index
    private nonisolated var indexKey: String { "\(servicePrefix).sync.index" }
    
    // MARK: - Initialization
    
    /// Create a syncable credential store
    /// - Parameters:
    ///   - configuration: Sync configuration
    ///   - servicePrefix: Prefix for Keychain service identifiers
    ///   - accessGroup: Keychain access group for app group sharing
    public init(
        configuration: SyncConfiguration = .default,
        servicePrefix: String = "com.t1pal",
        accessGroup: String? = nil
    ) {
        self.configuration = configuration
        self.servicePrefix = servicePrefix
        self.accessGroup = accessGroup
        
        // Load key index synchronously during init
        // Using a local computation to avoid actor isolation issues
        let key = "\(servicePrefix).sync.index"
        var loadedKeys: Set<String> = []
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: servicePrefix,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data,
           let keys = try? JSONDecoder().decode(Set<String>.self, from: data) {
            loadedKeys = keys
        }
        #else
        if let data = UserDefaults.standard.data(forKey: "keychain.fallback.\(key)"),
           let keys = try? JSONDecoder().decode(Set<String>.self, from: data) {
            loadedKeys = keys
        }
        #endif
        
        self.keyIndex = loadedKeys
    }
    
    // MARK: - Sync Status
    
    /// Check if iCloud Keychain sync is available
    public nonisolated func checkSyncAvailability() -> SyncAvailability {
        #if os(iOS) || os(macOS)
        // Check if we can write a synchronizable item
        // This indirectly checks iCloud Keychain availability
        let testKey = "com.t1pal.sync.availability.test"
        let testData = "test".data(using: .utf8)!
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: testKey,
            kSecAttrService as String: "com.t1pal.sync.test",
            kSecValueData as String: testData,
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]
        
        // Try to add
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        
        if addStatus == errSecSuccess {
            // Clean up test item
            query.removeValue(forKey: kSecValueData as String)
            SecItemDelete(query as CFDictionary)
            return .available
        } else if addStatus == errSecDuplicateItem {
            // Item exists, sync is available
            return .available
        } else if addStatus == errSecMissingEntitlement {
            return .unavailable(.keychainSyncDisabled)
        } else if addStatus == errSecNotAvailable {
            return .unavailable(.notSignedIn)
        } else if addStatus == -25308 {  // errSecRestricted
            return .unavailable(.restricted)
        } else {
            return .unavailable(.unknown)
        }
        #else
        return .unavailable(.platformNotSupported)
        #endif
    }
    
    /// Current sync mode
    public var syncMode: CredentialSyncMode {
        configuration.mode
    }
    
    /// Update sync configuration
    public func updateConfiguration(_ newConfig: SyncConfiguration) async throws {
        let oldMode = configuration.mode
        configuration = newConfig
        
        // Handle mode change
        if oldMode != newConfig.mode {
            try await handleModeChange(from: oldMode, to: newConfig.mode)
        }
    }
    
    // MARK: - Credential Operations
    
    /// Store a credential with current sync settings
    public func store(_ credential: AuthCredential, for key: CredentialKey) async throws {
        let shouldSync = shouldSyncCredential(credential)
        let stored = SyncableStoredCredential(credential: credential, key: key)
        
        guard let data = try? encoder.encode(stored) else {
            throw CredentialStoreError.encodingFailed
        }
        
        let account = accountKey(for: key)
        let success = saveToKeychain(data: data, account: account, synchronizable: shouldSync)
        
        guard success else {
            throw CredentialStoreError.storageFailed("Keychain save failed")
        }
        
        // Update index
        keyIndex.insert(account)
        try saveIndex()
    }
    
    /// Retrieve a credential
    public func retrieve(for key: CredentialKey) async throws -> AuthCredential {
        let account = accountKey(for: key)
        
        // Try to load (check both sync and non-sync items)
        guard let data = loadFromKeychain(account: account, synchronizable: nil) else {
            throw CredentialStoreError.notFound
        }
        
        guard let stored = try? decoder.decode(SyncableStoredCredential.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }
        
        return stored.credential
    }
    
    /// Delete a credential
    public func delete(for key: CredentialKey) async throws {
        let account = accountKey(for: key)
        
        // Delete both sync and non-sync versions
        _ = deleteFromKeychain(account: account, synchronizable: true)
        _ = deleteFromKeychain(account: account, synchronizable: false)
        
        // Update index
        keyIndex.remove(account)
        try saveIndex()
    }
    
    /// Check if credential exists
    public func exists(for key: CredentialKey) async -> Bool {
        let account = accountKey(for: key)
        return loadFromKeychain(account: account, synchronizable: nil) != nil
    }
    
    /// Get all stored keys for a service
    public func allKeys(for service: String) async throws -> [CredentialKey] {
        return keyIndex.compactMap { account -> CredentialKey? in
            // Parse account key format: prefix.service.account
            let parts = account.split(separator: ".")
            guard parts.count >= 3 else { return nil }
            
            let keyService = String(parts[parts.count - 2])
            let keyAccount = String(parts[parts.count - 1])
            
            if keyService == service || account.contains(service) {
                return CredentialKey(service: keyService, account: keyAccount)
            }
            return nil
        }
    }
    
    /// Clear all credentials
    public func clearAll() async throws {
        for account in keyIndex {
            _ = deleteFromKeychain(account: account, synchronizable: true)
            _ = deleteFromKeychain(account: account, synchronizable: false)
        }
        keyIndex.removeAll()
        try saveIndex()
    }
    
    /// Get count of stored credentials
    public func count() -> Int {
        keyIndex.count
    }
    
    // MARK: - Private Helpers
    
    private func shouldSyncCredential(_ credential: AuthCredential) -> Bool {
        guard configuration.mode == .iCloudSync else { return false }
        
        if let syncableTypes = configuration.syncableTypes {
            return syncableTypes.contains(credential.tokenType)
        }
        
        return true
    }
    
    private func accountKey(for key: CredentialKey) -> String {
        "\(servicePrefix).\(key.service).\(key.account)"
    }
    
    private func handleModeChange(from oldMode: CredentialSyncMode, to newMode: CredentialSyncMode) async throws {
        switch (oldMode, newMode) {
        case (.local, .iCloudSync):
            // Migrate local credentials to sync if configured
            if configuration.migrateOnEnable {
                try await migrateToSync()
            }
            
        case (.iCloudSync, .local):
            // Keep local copies if configured
            if configuration.keepLocalOnDisable {
                try await migrateToLocal()
            }
            
        default:
            break
        }
    }
    
    private func migrateToSync() async throws {
        // Re-save all credentials with sync enabled
        for account in keyIndex {
            if let data = loadFromKeychain(account: account, synchronizable: false) {
                // Delete non-sync version
                _ = deleteFromKeychain(account: account, synchronizable: false)
                // Save sync version
                _ = saveToKeychain(data: data, account: account, synchronizable: true)
            }
        }
    }
    
    private func migrateToLocal() async throws {
        // Re-save all credentials without sync
        for account in keyIndex {
            if let data = loadFromKeychain(account: account, synchronizable: true) {
                // Save local version first
                _ = saveToKeychain(data: data, account: account, synchronizable: false)
                // Delete sync version
                _ = deleteFromKeychain(account: account, synchronizable: true)
            }
        }
    }
    
    private func saveIndex() throws {
        guard let data = try? JSONEncoder().encode(keyIndex) else {
            throw CredentialStoreError.encodingFailed
        }
        // Index is always stored locally, not synced
        _ = saveToKeychain(data: data, account: indexKey, synchronizable: false)
    }
    
    // MARK: - Keychain Operations
    
    private nonisolated func saveToKeychain(data: Data, account: String, synchronizable: Bool) -> Bool {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix
        ]
        
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        } else {
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        }
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        query[kSecValueData as String] = data
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
        #else
        // Linux fallback - use UserDefaults (no sync support)
        UserDefaults.standard.set(data, forKey: "keychain.fallback.\(account)")
        return true
        #endif
    }
    
    private nonisolated func loadFromKeychain(account: String, synchronizable: Bool?) -> Data? {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let synchronizable = synchronizable {
            query[kSecAttrSynchronizable as String] = synchronizable ? kCFBooleanTrue : kCFBooleanFalse
        } else {
            // Search both sync and non-sync items
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return data
        #else
        // Linux fallback
        return UserDefaults.standard.data(forKey: "keychain.fallback.\(account)")
        #endif
    }
    
    private nonisolated func deleteFromKeychain(account: String, synchronizable: Bool) -> Bool {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        // Linux fallback
        UserDefaults.standard.removeObject(forKey: "keychain.fallback.\(account)")
        return true
        #endif
    }
}

// MARK: - Factory Methods

extension SyncableCredentialStore {
    
    /// Create a local-only credential store (no sync)
    public static var local: SyncableCredentialStore {
        SyncableCredentialStore(configuration: .default)
    }
    
    /// Create an iCloud-synced credential store
    public static var iCloudSynced: SyncableCredentialStore {
        SyncableCredentialStore(configuration: .iCloudAll)
    }
    
    /// Create a store for Nightscout credentials with sync
    public static var nightscoutSynced: SyncableCredentialStore {
        SyncableCredentialStore(
            configuration: .iCloudAll,
            servicePrefix: "com.t1pal.nightscout"
        )
    }
    
    /// Create a store for OAuth tokens with sync
    public static var oauthSynced: SyncableCredentialStore {
        SyncableCredentialStore(
            configuration: .iCloudOAuth,
            servicePrefix: "com.t1pal.oauth2"
        )
    }
}

// MARK: - Syncable Stored Credential (Internal)

/// Internal type for storing credentials with sync metadata
private struct SyncableStoredCredential: Codable {
    let credential: AuthCredential
    let service: String
    let account: String
    let storedAt: Date
    
    init(credential: AuthCredential, key: CredentialKey) {
        self.credential = credential
        self.service = key.service
        self.account = key.account
        self.storedAt = Date()
    }
}
