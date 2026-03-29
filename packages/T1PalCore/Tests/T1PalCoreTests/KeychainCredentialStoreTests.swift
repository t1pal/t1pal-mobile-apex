// SPDX-License-Identifier: AGPL-3.0-or-later
//
// KeychainCredentialStoreTests.swift
// T1PalCoreTests
//
// Tests for KeychainCredentialStore implementation.
// Trace: ID-KEYCHAIN-001, PRD-003

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Keychain Credential Store Tests

@Suite("Keychain Credential Store")
struct KeychainCredentialStoreTests {
    
    // Use unique service to avoid test interference
    let testService = "com.t1pal.test.\(UUID().uuidString.prefix(8))"
    
    @Test("Store and retrieve credential")
    func storeAndRetrieveCredential() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let credential = AuthCredential(
            tokenType: .apiSecret,
            value: "test-secret-123",
            expiresAt: nil,
            scope: nil
        )
        
        let key = CredentialKey(service: "nightscout", account: "test.example.com")
        
        // Store
        try await store.store(credential, for: key)
        
        // Retrieve
        let retrieved = try await store.retrieve(for: key)
        
        #expect(retrieved.value == "test-secret-123")
        #expect(retrieved.tokenType == .apiSecret)
        
        // Cleanup
        try await store.delete(for: key)
    }
    
    @Test("Credential exists check")
    func credentialExistsCheck() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let credential = AuthCredential(
            tokenType: .access,
            value: "test-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let key = CredentialKey(service: "oauth2", account: "user@example.com")
        
        // Should not exist initially
        let existsBefore = await store.exists(for: key)
        #expect(existsBefore == false)
        
        // Store
        try await store.store(credential, for: key)
        
        // Should exist after store
        let existsAfter = await store.exists(for: key)
        #expect(existsAfter == true)
        
        // Cleanup
        try await store.delete(for: key)
        
        // Should not exist after delete
        let existsAfterDelete = await store.exists(for: key)
        #expect(existsAfterDelete == false)
    }
    
    @Test("Delete credential")
    func deleteCredential() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let credential = AuthCredential(tokenType: .apiSecret, value: "delete-me")
        let key = CredentialKey(service: "test", account: "delete-test")
        
        try await store.store(credential, for: key)
        #expect(await store.exists(for: key) == true)
        
        try await store.delete(for: key)
        #expect(await store.exists(for: key) == false)
    }
    
    @Test("Retrieve non-existent credential throws")
    func retrieveNonExistentThrows() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        let key = CredentialKey(service: "nonexistent", account: "nowhere")
        
        await #expect(throws: CredentialStoreError.notFound) {
            try await store.retrieve(for: key)
        }
    }
    
    @Test("All keys for service")
    func allKeysForService() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let service = "multi-key-test"
        let keys = [
            CredentialKey(service: service, account: "account1"),
            CredentialKey(service: service, account: "account2"),
            CredentialKey(service: service, account: "account3")
        ]
        
        // Store multiple credentials
        for key in keys {
            let credential = AuthCredential(tokenType: .apiSecret, value: "secret-\(key.account)")
            try await store.store(credential, for: key)
        }
        
        // Get all keys
        let retrievedKeys = try await store.allKeys(for: service)
        #expect(retrievedKeys.count == 3)
        
        let accounts = Set(retrievedKeys.map { $0.account })
        #expect(accounts.contains("account1"))
        #expect(accounts.contains("account2"))
        #expect(accounts.contains("account3"))
        
        // Cleanup
        for key in keys {
            try await store.delete(for: key)
        }
    }
    
    @Test("Clear service removes all credentials")
    func clearServiceRemovesAll() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        let service = "clear-test"
        
        // Store multiple
        for i in 1...3 {
            let key = CredentialKey(service: service, account: "account\(i)")
            let credential = AuthCredential(tokenType: .apiSecret, value: "value\(i)")
            try await store.store(credential, for: key)
        }
        
        // Verify stored
        let keysBefore = try await store.allKeys(for: service)
        #expect(keysBefore.count == 3)
        
        // Clear service
        try await store.clearService(service)
        
        // Verify cleared
        let keysAfter = try await store.allKeys(for: service)
        #expect(keysAfter.count == 0)
    }
    
    @Test("Count returns correct number")
    func countReturnsCorrect() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let initialCount = await store.count()
        
        let key = CredentialKey(service: "count-test", account: "test")
        let credential = AuthCredential(tokenType: .apiSecret, value: "test")
        
        try await store.store(credential, for: key)
        
        let countAfterStore = await store.count()
        #expect(countAfterStore == initialCount + 1)
        
        try await store.delete(for: key)
        
        let countAfterDelete = await store.count()
        #expect(countAfterDelete == initialCount)
    }
    
    @Test("Stored credential includes metadata")
    func storedCredentialIncludesMetadata() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let credential = AuthCredential(
            tokenType: .access,
            value: "metadata-test",
            expiresAt: Date().addingTimeInterval(7200),
            scope: "read write"
        )
        
        let key = CredentialKey(service: "metadata-test", account: "user")
        try await store.store(credential, for: key)
        
        let stored = try await store.retrieveStored(for: key)
        
        #expect(stored.credential.value == "metadata-test")
        #expect(stored.credential.scope == "read write")
        #expect(stored.key.service == "metadata-test")
        #expect(stored.key.account == "user")
        #expect(stored.storedAt <= Date())
        
        try await store.delete(for: key)
    }
    
    @Test("Update existing credential")
    func updateExistingCredential() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let key = CredentialKey(service: "update-test", account: "user")
        
        // Store initial
        let initial = AuthCredential(tokenType: .apiSecret, value: "initial-value")
        try await store.store(initial, for: key)
        
        // Update
        let updated = AuthCredential(tokenType: .access, value: "updated-value")
        try await store.store(updated, for: key)
        
        // Retrieve should return updated
        let retrieved = try await store.retrieve(for: key)
        #expect(retrieved.value == "updated-value")
        #expect(retrieved.tokenType == .access)
        
        try await store.delete(for: key)
    }
    
    @Test("All services returns distinct services")
    func allServicesReturnsDistinct() async throws {
        let store = KeychainCredentialStore(servicePrefix: testService)
        
        let services = ["service-a", "service-b", "service-c"]
        
        for service in services {
            let key = CredentialKey(service: service, account: "account")
            let credential = AuthCredential(tokenType: .apiSecret, value: "value")
            try await store.store(credential, for: key)
        }
        
        let allServices = await store.allServices()
        
        for service in services {
            #expect(allServices.contains(service))
        }
        
        // Cleanup
        for service in services {
            let key = CredentialKey(service: service, account: "account")
            try await store.delete(for: key)
        }
    }
}

// MARK: - Factory Method Tests

@Suite("Keychain Credential Store Factories")
struct KeychainCredentialStoreFactoryTests {
    
    @Test("Nightscout factory creates store")
    func nightscoutFactoryCreatesStore() async {
        let store = KeychainCredentialStore.nightscout
        let count = await store.count()
        #expect(count >= 0) // Just verify it works
    }
    
    @Test("OAuth2 factory creates store")
    func oauth2FactoryCreatesStore() async {
        let store = KeychainCredentialStore.oauth2
        let count = await store.count()
        #expect(count >= 0)
    }
    
    @Test("BLE devices factory creates store")
    func bleDevicesFactoryCreatesStore() async {
        let store = KeychainCredentialStore.bleDevices
        let count = await store.count()
        #expect(count >= 0)
    }
    
    @Test("Shared factory creates store with access group")
    func sharedFactoryCreatesStoreWithAccessGroup() async {
        let store = KeychainCredentialStore.shared(accessGroup: "group.com.t1pal.test")
        let count = await store.count()
        #expect(count >= 0)
    }
}

// MARK: - Credential Key Tests

@Suite("Credential Key Factory Methods")
struct CredentialKeyFactoryTests {
    
    @Test("Nightscout key factory")
    func nightscoutKeyFactory() {
        let url = URL(string: "https://mysite.herokuapp.com")!
        let key = CredentialKey.nightscout(url: url)
        
        #expect(key.service == "com.t1pal.nightscout")
        #expect(key.account == "mysite.herokuapp.com")
    }
    
    @Test("OAuth2 key factory")
    func oauth2KeyFactory() {
        let key = CredentialKey.oauth2(provider: .t1pal, userId: "user123")
        
        #expect(key.service == "com.t1pal.t1pal")
        #expect(key.account == "user123")
    }
}
