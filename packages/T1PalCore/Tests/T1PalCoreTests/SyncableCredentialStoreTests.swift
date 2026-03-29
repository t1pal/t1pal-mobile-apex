// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SyncableCredentialStoreTests.swift
// T1PalCoreTests
//
// Tests for SyncableCredentialStore iCloud Keychain sync functionality.
// Trace: ID-KEYCHAIN-002

import Testing
@testable import T1PalCore
import Foundation

// MARK: - Sync Mode Tests

@Suite("CredentialSyncMode Tests")
struct CredentialSyncModeTests {
    
    @Test("Display names are set")
    func testDisplayNames() {
        #expect(CredentialSyncMode.local.displayName == "This Device Only")
        #expect(CredentialSyncMode.iCloudSync.displayName == "iCloud Keychain")
    }
    
    @Test("Descriptions are set")
    func testDescriptions() {
        #expect(CredentialSyncMode.local.description.contains("this device"))
        #expect(CredentialSyncMode.iCloudSync.description.contains("iCloud"))
    }
    
    @Test("Modes are codable")
    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for mode in CredentialSyncMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(CredentialSyncMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - Sync Availability Tests

@Suite("SyncAvailability Tests")
struct SyncAvailabilityTests {
    
    @Test("Available returns isAvailable true")
    func testAvailable() {
        let status = SyncAvailability.available
        #expect(status.isAvailable == true)
    }
    
    @Test("Unavailable returns isAvailable false")
    func testUnavailable() {
        let reasons: [SyncUnavailableReason] = [
            .notSignedIn,
            .keychainSyncDisabled,
            .platformNotSupported,
            .restricted,
            .unknown
        ]
        
        for reason in reasons {
            let status = SyncAvailability.unavailable(reason)
            #expect(status.isAvailable == false)
        }
    }
    
    @Test("Unavailable reason descriptions")
    func testReasonDescriptions() {
        #expect(SyncUnavailableReason.notSignedIn.localizedDescription.contains("iCloud"))
        #expect(SyncUnavailableReason.keychainSyncDisabled.localizedDescription.contains("Enable"))
        #expect(SyncUnavailableReason.platformNotSupported.localizedDescription.contains("not available"))
        #expect(SyncUnavailableReason.restricted.localizedDescription.contains("restricted"))
        #expect(SyncUnavailableReason.unknown.localizedDescription.contains("unavailable"))
    }
}

// MARK: - Sync Configuration Tests

@Suite("SyncConfiguration Tests")
struct SyncConfigurationTests {
    
    @Test("Default configuration is local")
    func testDefaultConfig() {
        let config = SyncConfiguration.default
        
        #expect(config.mode == .local)
        #expect(config.migrateOnEnable == true)
        #expect(config.keepLocalOnDisable == true)
        #expect(config.syncableTypes == nil)
    }
    
    @Test("iCloud all configuration")
    func testICloudAllConfig() {
        let config = SyncConfiguration.iCloudAll
        
        #expect(config.mode == .iCloudSync)
        #expect(config.syncableTypes == nil)
    }
    
    @Test("iCloud OAuth configuration")
    func testICloudOAuthConfig() {
        let config = SyncConfiguration.iCloudOAuth
        
        #expect(config.mode == .iCloudSync)
        #expect(config.syncableTypes?.contains(.access) == true)
        #expect(config.syncableTypes?.contains(.refresh) == true)
    }
    
    @Test("Custom configuration")
    func testCustomConfig() {
        let config = SyncConfiguration(
            mode: .iCloudSync,
            migrateOnEnable: false,
            keepLocalOnDisable: false,
            syncableTypes: [.apiSecret]
        )
        
        #expect(config.mode == .iCloudSync)
        #expect(config.migrateOnEnable == false)
        #expect(config.keepLocalOnDisable == false)
        #expect(config.syncableTypes == [.apiSecret])
    }
    
    @Test("Configuration is codable")
    func testCodable() throws {
        let config = SyncConfiguration(
            mode: .iCloudSync,
            migrateOnEnable: true,
            keepLocalOnDisable: false,
            syncableTypes: [.access, .refresh]
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(SyncConfiguration.self, from: data)
        
        #expect(decoded.mode == config.mode)
        #expect(decoded.migrateOnEnable == config.migrateOnEnable)
        #expect(decoded.keepLocalOnDisable == config.keepLocalOnDisable)
        #expect(decoded.syncableTypes == config.syncableTypes)
    }
}

// MARK: - Syncable Credential Store Tests

@Suite("SyncableCredentialStore Tests")
struct SyncableCredentialStoreTests {
    
    static let testService = "com.t1pal.test.sync.\(ProcessInfo.processInfo.processIdentifier)"
    
    @Test("Store initializes with default configuration")
    func testDefaultInit() async {
        let store = SyncableCredentialStore()
        let mode = await store.syncMode
        #expect(mode == .local)
    }
    
    @Test("Store initializes with custom configuration")
    func testCustomInit() async {
        let store = SyncableCredentialStore(
            configuration: .iCloudAll,
            servicePrefix: Self.testService
        )
        let mode = await store.syncMode
        #expect(mode == .iCloudSync)
    }
    
    @Test("Factory methods create correct stores")
    func testFactoryMethods() async {
        let local = SyncableCredentialStore.local
        let localMode = await local.syncMode
        #expect(localMode == .local)
        
        let synced = SyncableCredentialStore.iCloudSynced
        let syncedMode = await synced.syncMode
        #expect(syncedMode == .iCloudSync)
    }
    
    @Test("Check sync availability on Linux returns not supported")
    func testSyncAvailabilityLinux() {
        #if os(Linux)
        let store = SyncableCredentialStore()
        let availability = store.checkSyncAvailability()
        
        #expect(availability.isAvailable == false)
        if case .unavailable(let reason) = availability {
            #expect(reason == .platformNotSupported)
        }
        #endif
    }
}

// MARK: - Store Operations Tests

@Suite("SyncableCredentialStore Operations")
struct SyncableStoreOperationsTests {
    
    static let testService = "com.t1pal.test.sync.ops.\(ProcessInfo.processInfo.processIdentifier)"
    
    @Test("Store and retrieve credential")
    func testStoreAndRetrieve() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        // Clear first
        try await store.clearAll()
        
        let credential = AuthCredential(
            tokenType: .access,
            value: "sync-test-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let key = CredentialKey(service: "test", account: "sync-user")
        
        // Store
        try await store.store(credential, for: key)
        
        // Retrieve
        let retrieved = try await store.retrieve(for: key)
        #expect(retrieved.value == "sync-test-token")
        #expect(retrieved.tokenType == .access)
        
        // Cleanup
        try await store.clearAll()
    }
    
    @Test("Credential exists check")
    func testExists() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        try await store.clearAll()
        
        let credential = AuthCredential(tokenType: .apiSecret, value: "secret")
        let key = CredentialKey(service: "test", account: "exists-test")
        
        // Should not exist
        let existsBefore = await store.exists(for: key)
        #expect(existsBefore == false)
        
        // Store
        try await store.store(credential, for: key)
        
        // Should exist
        let existsAfter = await store.exists(for: key)
        #expect(existsAfter == true)
        
        // Cleanup
        try await store.clearAll()
    }
    
    @Test("Delete credential")
    func testDelete() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        try await store.clearAll()
        
        let credential = AuthCredential(tokenType: .access, value: "delete-me")
        let key = CredentialKey(service: "test", account: "delete-test")
        
        try await store.store(credential, for: key)
        #expect(await store.exists(for: key) == true)
        
        try await store.delete(for: key)
        #expect(await store.exists(for: key) == false)
    }
    
    @Test("Count credentials")
    func testCount() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        try await store.clearAll()
        
        let initialCount = await store.count()
        #expect(initialCount == 0)
        
        let credential = AuthCredential(tokenType: .access, value: "token")
        try await store.store(credential, for: CredentialKey(service: "test", account: "a"))
        try await store.store(credential, for: CredentialKey(service: "test", account: "b"))
        
        let count = await store.count()
        #expect(count == 2)
        
        try await store.clearAll()
    }
    
    @Test("Clear all credentials")
    func testClearAll() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        // Ensure clean state before test
        try await store.clearAll()
        
        let credential = AuthCredential(tokenType: .access, value: "token")
        try await store.store(credential, for: CredentialKey(service: "test", account: "x"))
        try await store.store(credential, for: CredentialKey(service: "test", account: "y"))
        
        let countBefore = await store.count()
        #expect(countBefore == 2)
        
        try await store.clearAll()
        
        let countAfter = await store.count()
        #expect(countAfter == 0)
    }
    
    @Test("Retrieve non-existent throws not found")
    func testRetrieveNotFound() async {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        let key = CredentialKey(service: "nonexistent", account: "nowhere")
        
        await #expect(throws: CredentialStoreError.notFound) {
            try await store.retrieve(for: key)
        }
    }
}

// MARK: - Configuration Update Tests

@Suite("SyncableCredentialStore Configuration Updates")
struct SyncConfigUpdateTests {
    
    static let testService = "com.t1pal.test.sync.config.\(ProcessInfo.processInfo.processIdentifier)"
    
    @Test("Update sync mode")
    func testUpdateSyncMode() async throws {
        let store = SyncableCredentialStore(
            configuration: .default,
            servicePrefix: Self.testService
        )
        
        var mode = await store.syncMode
        #expect(mode == .local)
        
        try await store.updateConfiguration(.iCloudAll)
        
        mode = await store.syncMode
        #expect(mode == .iCloudSync)
        
        // Reset
        try await store.updateConfiguration(.default)
        mode = await store.syncMode
        #expect(mode == .local)
    }
}
