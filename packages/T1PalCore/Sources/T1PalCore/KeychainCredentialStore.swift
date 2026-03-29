// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// KeychainCredentialStore.swift
// T1PalCore
//
// Keychain-backed implementation of CredentialStoring protocol.
// Uses KeychainHelper for low-level operations.
// Trace: ID-KEYCHAIN-001, PRD-003, REQ-ID-002

import Foundation

#if canImport(Security)
import Security
#endif

// MARK: - Keychain Credential Store

/// Keychain-backed credential store implementing CredentialStoring protocol.
/// Uses iOS Keychain for secure, persistent storage of AuthCredentials.
/// Falls back to UserDefaults on Linux (via KeychainHelper).
///
/// Trace: ID-KEYCHAIN-001
/// Requirements: REQ-ID-002
public actor KeychainCredentialStore: CredentialStoring {
    
    /// Service prefix for credential storage
    private let servicePrefix: String
    
    /// Access group for shared Keychain access (nil = no sharing)
    private let accessGroup: String?
    
    /// Encoder for credential serialization
    private let encoder = JSONEncoder()
    
    /// Decoder for credential deserialization
    private let decoder = JSONDecoder()
    
    /// Index of stored keys (persisted separately for allKeys lookup)
    private var keyIndex: Set<String> = []
    
    /// Key for storing the index
    private let indexKey = "com.t1pal.credential.index"
    
    // MARK: - Initialization
    
    /// Create a Keychain credential store
    /// - Parameters:
    ///   - servicePrefix: Prefix for Keychain service identifiers (default: "com.t1pal")
    ///   - accessGroup: Keychain access group for app group sharing (nil = no sharing)
    public init(servicePrefix: String = "com.t1pal", accessGroup: String? = nil) {
        self.servicePrefix = servicePrefix
        self.accessGroup = accessGroup
        
        // Load key index on init
        if let indexData = KeychainHelper.shared.load(forAccount: indexKey),
           let keys = try? JSONDecoder().decode(Set<String>.self, from: Data(indexData.utf8)) {
            self.keyIndex = keys
        }
    }
    
    // MARK: - CredentialStoring Implementation
    
    /// Store a credential securely in Keychain
    public func store(_ credential: AuthCredential, for key: CredentialKey) async throws {
        let stored = StoredCredential(credential: credential, key: key)
        
        guard let data = try? encoder.encode(stored),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }
        
        let account = accountKey(for: key)
        let success = KeychainHelper.shared.save(jsonString, forAccount: account)
        
        guard success else {
            throw CredentialStoreError.storageFailed("Keychain save failed")
        }
        
        // Update index
        keyIndex.insert(indexEntry(for: key))
        try saveIndex()
    }
    
    /// Retrieve a credential from Keychain
    public func retrieve(for key: CredentialKey) async throws -> AuthCredential {
        let account = accountKey(for: key)
        
        guard let jsonString = KeychainHelper.shared.load(forAccount: account),
              let data = jsonString.data(using: .utf8) else {
            throw CredentialStoreError.notFound
        }
        
        guard let stored = try? decoder.decode(StoredCredential.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }
        
        return stored.credential
    }
    
    /// Delete a credential from Keychain
    public func delete(for key: CredentialKey) async throws {
        let account = accountKey(for: key)
        let success = KeychainHelper.shared.delete(forAccount: account)
        
        guard success else {
            throw CredentialStoreError.notFound
        }
        
        // Update index
        keyIndex.remove(indexEntry(for: key))
        try saveIndex()
    }
    
    /// Check if credential exists in Keychain
    public func exists(for key: CredentialKey) async -> Bool {
        let account = accountKey(for: key)
        return KeychainHelper.shared.exists(forAccount: account)
    }
    
    /// List all stored credential keys for a service
    public func allKeys(for service: String) async throws -> [CredentialKey] {
        keyIndex
            .filter { $0.hasPrefix(service + ":") }
            .compactMap { parseIndexEntry($0) }
    }
    
    // MARK: - Additional Methods
    
    /// Retrieve the full stored credential with metadata
    public func retrieveStored(for key: CredentialKey) async throws -> StoredCredential {
        let account = accountKey(for: key)
        
        guard let jsonString = KeychainHelper.shared.load(forAccount: account),
              let data = jsonString.data(using: .utf8) else {
            throw CredentialStoreError.notFound
        }
        
        guard let stored = try? decoder.decode(StoredCredential.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }
        
        return stored
    }
    
    /// Clear all credentials for a service
    public func clearService(_ service: String) async throws {
        let keys = try await allKeys(for: service)
        for key in keys {
            try await delete(for: key)
        }
    }
    
    /// Clear all stored credentials
    public func clearAll() async throws {
        for entry in keyIndex {
            if let key = parseIndexEntry(entry) {
                let account = accountKey(for: key)
                KeychainHelper.shared.delete(forAccount: account)
            }
        }
        keyIndex.removeAll()
        try saveIndex()
    }
    
    /// Get count of stored credentials
    public func count() async -> Int {
        keyIndex.count
    }
    
    /// Get all stored services
    public func allServices() async -> Set<String> {
        Set(keyIndex.compactMap { entry -> String? in
            let parts = entry.split(separator: ":")
            return parts.first.map(String.init)
        })
    }
    
    // MARK: - Private Helpers
    
    private func accountKey(for key: CredentialKey) -> String {
        if let group = key.accessGroup ?? accessGroup {
            return "\(servicePrefix).\(key.service).\(key.account).\(group)"
        }
        return "\(servicePrefix).\(key.service).\(key.account)"
    }
    
    private func indexEntry(for key: CredentialKey) -> String {
        "\(key.service):\(key.account)"
    }
    
    private func parseIndexEntry(_ entry: String) -> CredentialKey? {
        let parts = entry.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return CredentialKey(
            service: String(parts[0]),
            account: String(parts[1]),
            accessGroup: accessGroup
        )
    }
    
    private func saveIndex() throws {
        guard let data = try? JSONEncoder().encode(keyIndex),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }
        KeychainHelper.shared.save(jsonString, forAccount: indexKey)
    }
}

// MARK: - Factory Methods

extension KeychainCredentialStore {
    
    /// Create a credential store for Nightscout credentials
    public static var nightscout: KeychainCredentialStore {
        KeychainCredentialStore(servicePrefix: "com.t1pal.nightscout")
    }
    
    /// Create a credential store for OAuth2 tokens
    public static var oauth2: KeychainCredentialStore {
        KeychainCredentialStore(servicePrefix: "com.t1pal.oauth2")
    }
    
    /// Create a credential store for BLE device credentials
    public static var bleDevices: KeychainCredentialStore {
        KeychainCredentialStore(servicePrefix: "com.t1pal.ble")
    }
    
    /// Create a shared credential store for app group
    public static func shared(accessGroup: String) -> KeychainCredentialStore {
        KeychainCredentialStore(servicePrefix: "com.t1pal", accessGroup: accessGroup)
    }
}

// MARK: - Credential Store Adapter

/// Adapter to use KeychainCredentialStore where a non-actor CredentialStoring is needed
public final class KeychainCredentialStoreAdapter: @unchecked Sendable {
    
    private let store: KeychainCredentialStore
    
    public init(store: KeychainCredentialStore = KeychainCredentialStore()) {
        self.store = store
    }
    
    /// Store credential (blocking)
    public func storeSync(_ credential: AuthCredential, for key: CredentialKey) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        Task {
            do {
                try await store.store(credential, for: key)
            } catch {
                resultError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        if let error = resultError {
            throw error
        }
    }
    
    /// Retrieve credential (blocking)
    public func retrieveSync(for key: CredentialKey) throws -> AuthCredential {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<AuthCredential, Error>!
        
        Task {
            do {
                let credential = try await store.retrieve(for: key)
                result = .success(credential)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return try result.get()
    }
    
    /// Check if credential exists (blocking)
    public func existsSync(for key: CredentialKey) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var exists = false
        
        Task {
            exists = await store.exists(for: key)
            semaphore.signal()
        }
        
        semaphore.wait()
        return exists
    }
}
