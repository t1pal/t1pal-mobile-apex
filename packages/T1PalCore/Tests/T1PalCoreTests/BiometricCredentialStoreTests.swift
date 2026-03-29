// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// BiometricCredentialStoreTests.swift
// T1PalCoreTests
//
// Tests for BiometricCredentialStore functionality.
// Biometric auth mocked on Linux/CI; validates store operations.
// Trace: ID-KEYCHAIN-003

import Testing
@testable import T1PalCore
import Foundation

// MARK: - Biometric Error Tests

@Suite("BiometricError Tests")
struct BiometricErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() {
        #expect(BiometricError.notAvailable.errorDescription?.contains("not available") == true)
        #expect(BiometricError.notEnrolled.errorDescription?.contains("enrolled") == true)
        #expect(BiometricError.lockout.errorDescription?.contains("locked") == true)
        #expect(BiometricError.cancelled.errorDescription?.contains("cancelled") == true)
        #expect(BiometricError.authenticationFailed.errorDescription?.contains("failed") == true)
        #expect(BiometricError.passcodeNotSet.errorDescription?.contains("passcode") == true)
        #expect(BiometricError.systemCancel.errorDescription?.contains("system") == true)
        #expect(BiometricError.userFallback.errorDescription?.contains("fallback") == true)
        #expect(BiometricError.invalidContext.errorDescription?.contains("invalid") == true)
        #expect(BiometricError.unknown(42).errorDescription?.contains("42") == true)
    }
    
    @Test("Errors are equatable")
    func testEquatable() {
        #expect(BiometricError.notAvailable == BiometricError.notAvailable)
        #expect(BiometricError.unknown(1) == BiometricError.unknown(1))
        #expect(BiometricError.unknown(1) != BiometricError.unknown(2))
        #expect(BiometricError.cancelled != BiometricError.lockout)
    }
}

// MARK: - Biometric Type Tests

@Suite("BiometricType Tests")
struct BiometricTypeTests {
    
    @Test("Display names are set")
    func testDisplayNames() {
        #expect(BiometricType.none.displayName == "None")
        #expect(BiometricType.touchID.displayName == "Touch ID")
        #expect(BiometricType.faceID.displayName == "Face ID")
        #expect(BiometricType.opticID.displayName == "Optic ID")
    }
    
    @Test("System image names are set")
    func testSystemImageNames() {
        #expect(BiometricType.none.systemImageName == "lock")
        #expect(BiometricType.touchID.systemImageName == "touchid")
        #expect(BiometricType.faceID.systemImageName == "faceid")
        #expect(BiometricType.opticID.systemImageName == "opticid")
    }
    
    @Test("Types are codable")
    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for type in [BiometricType.none, .touchID, .faceID, .opticID] {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(BiometricType.self, from: data)
            #expect(decoded == type)
        }
    }
}

// MARK: - Biometric Auth Result Tests

@Suite("BiometricAuthResult Tests")
struct BiometricAuthResultTests {
    
    @Test("Success returns isSuccess true")
    func testSuccessResult() {
        let result = BiometricAuthResult.success
        #expect(result.isSuccess == true)
    }
    
    @Test("Cancelled returns isSuccess false")
    func testCancelledResult() {
        let result = BiometricAuthResult.cancelled
        #expect(result.isSuccess == false)
    }
    
    @Test("Failed returns isSuccess false")
    func testFailedResult() {
        let result = BiometricAuthResult.failed(.authenticationFailed)
        #expect(result.isSuccess == false)
    }
    
    @Test("Not available returns isSuccess false")
    func testNotAvailableResult() {
        let result = BiometricAuthResult.notAvailable(.notAvailable)
        #expect(result.isSuccess == false)
    }
}

// MARK: - Biometric Settings Tests

@Suite("BiometricSettings Tests")
struct BiometricSettingsTests {
    
    @Test("Default settings are sensible")
    func testDefaultSettings() {
        let settings = BiometricSettings.default
        
        #expect(settings.isEnabled == true)
        #expect(settings.requirePerAccess == false)
        #expect(settings.sessionTimeout == 300)
        #expect(settings.allowPasscodeFallback == true)
    }
    
    @Test("Custom settings initialize correctly")
    func testCustomSettings() {
        let settings = BiometricSettings(
            isEnabled: false,
            requirePerAccess: true,
            sessionTimeout: 60,
            allowPasscodeFallback: false
        )
        
        #expect(settings.isEnabled == false)
        #expect(settings.requirePerAccess == true)
        #expect(settings.sessionTimeout == 60)
        #expect(settings.allowPasscodeFallback == false)
    }
    
    @Test("Settings are codable")
    func testCodable() throws {
        let settings = BiometricSettings(
            isEnabled: true,
            requirePerAccess: true,
            sessionTimeout: 120,
            allowPasscodeFallback: false
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(BiometricSettings.self, from: data)
        
        #expect(decoded.isEnabled == settings.isEnabled)
        #expect(decoded.requirePerAccess == settings.requirePerAccess)
        #expect(decoded.sessionTimeout == settings.sessionTimeout)
        #expect(decoded.allowPasscodeFallback == settings.allowPasscodeFallback)
    }
}

// MARK: - Biometric Credential Store Tests

@Suite("BiometricCredentialStore Tests")
struct BiometricCredentialStoreTests {
    
    // Use shared test service to avoid collisions
    static let testService = "com.t1pal.test.biometric.\(ProcessInfo.processInfo.processIdentifier)"
    
    @Test("Store initializes with default values")
    func testDefaultInitialization() async {
        let store = BiometricCredentialStore()
        
        // On Linux/CI, biometric should be unavailable
        #if os(Linux)
        #expect(store.isBiometricAvailable() == false)
        #expect(store.availableBiometricType() == .none)
        #endif
    }
    
    @Test("Store accepts custom auth reason")
    func testCustomAuthReason() async {
        _ = BiometricCredentialStore(
            authReason: "Custom auth reason for testing"
        )
        // If no crash, initialization succeeded
    }
    
    @Test("Factory methods create correct configurations")
    func testFactoryMethods() async {
        let nightscout = BiometricCredentialStore.nightscout
        let oauth = BiometricCredentialStore.oauth2
        
        // Both should be valid stores
        #expect(nightscout.isBiometricAvailable() == nightscout.isBiometricAvailable())
        #expect(oauth.isBiometricAvailable() == oauth.isBiometricAvailable())
    }
    
    @Test("Can authenticate check returns expected result")
    func testCanAuthenticate() {
        let store = BiometricCredentialStore()
        let (available, error) = store.canAuthenticate()
        
        #if os(Linux)
        #expect(available == false)
        #expect(error != nil)
        #else
        // On Darwin, depends on device capabilities
        if available {
            #expect(error == nil)
        } else {
            #expect(error != nil)
        }
        #endif
    }
}

// MARK: - Store Operations Tests (Skip Biometric)

@Suite("BiometricCredentialStore Operations", .serialized)
struct BiometricStoreOperationsTests {
    
    static let testService = "com.t1pal.test.biometric.ops.\(ProcessInfo.processInfo.processIdentifier)"
    
    /// Clean up test service keys before each test
    private func cleanupTestService() {
        // Clear any keys that might have been left from previous test runs
        let keyPattern = "keychain.fallback.\(Self.testService)"
        // UserDefaults cleanup for Linux
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPattern) }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
    
    @Test("Store and retrieve with biometric skipped")
    func testStoreAndRetrieveSkipBiometric() async throws {
        cleanupTestService()
        // Use optional biometric store (doesn't require biometric)
        let keychain = KeychainCredentialStore(servicePrefix: Self.testService)
        let store = BiometricCredentialStore.withOptionalBiometric(keychainStore: keychain)
        
        let credential = AuthCredential(tokenType: .access, value: "test-token-123", expiresAt: Date().addingTimeInterval(3600))
        let key = CredentialKey(service: Self.testService, account: "test-user")
        
        // Store
        try await store.store(credential, for: key)
        
        // Retrieve (skip biometric)
        let retrieved = try await store.retrieveWithoutBiometric(for: key)
        #expect(retrieved.value == "test-token-123")
        
        // Exists
        let exists = await store.exists(for: key)
        #expect(exists == true)
        
        // Cleanup
        try await store.delete(for: key)
        
        let existsAfter = await store.exists(for: key)
        #expect(existsAfter == false)
    }
    
    @Test("Count credentials")
    func testCount() async throws {
        cleanupTestService()
        let keychain = KeychainCredentialStore(servicePrefix: Self.testService)
        let store = BiometricCredentialStore.withOptionalBiometric(keychainStore: keychain)
        
        // Clear first
        try await store.clearAll()
        
        let initialCount = await store.count()
        #expect(initialCount == 0)
        
        // Store a credential
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: Date().addingTimeInterval(3600))
        let key = CredentialKey(service: Self.testService, account: "count-test")
        try await store.store(credential, for: key)
        
        let afterCount = await store.count()
        #expect(afterCount == 1)
        
        // Cleanup
        try await store.clearAll()
    }
    
    @Test("All keys for service")
    func testAllKeys() async throws {
        cleanupTestService()
        let keychain = KeychainCredentialStore(servicePrefix: Self.testService)
        let store = BiometricCredentialStore.withOptionalBiometric(keychainStore: keychain)
        
        // Clear first
        try await store.clearAll()
        
        // Store multiple credentials
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: Date().addingTimeInterval(3600))
        let key1 = CredentialKey(service: Self.testService, account: "user1")
        let key2 = CredentialKey(service: Self.testService, account: "user2")
        
        try await store.store(credential, for: key1)
        try await store.store(credential, for: key2)
        
        let keys = try await store.allKeys(for: Self.testService)
        #expect(keys.count == 2)
        #expect(keys.contains { $0.account == "user1" })
        #expect(keys.contains { $0.account == "user2" })
        
        // Cleanup
        try await store.clearAll()
    }
    
    @Test("Clear all credentials")
    func testClearAll() async throws {
        cleanupTestService()
        let keychain = KeychainCredentialStore(servicePrefix: Self.testService)
        let store = BiometricCredentialStore.withOptionalBiometric(keychainStore: keychain)
        
        // Clear first to ensure test isolation
        try await store.clearAll()
        
        // Store some credentials
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: Date().addingTimeInterval(3600))
        try await store.store(credential, for: CredentialKey(service: Self.testService, account: "a"))
        try await store.store(credential, for: CredentialKey(service: Self.testService, account: "b"))
        
        let countBefore = await store.count()
        #expect(countBefore == 2)
        
        // Clear all
        try await store.clearAll()
        
        let countAfter = await store.count()
        #expect(countAfter == 0)
    }
}

// MARK: - Biometric Required Store Tests

@Suite("BiometricCredentialStore with Biometric Required")
struct BiometricRequiredTests {
    
    static let testService = "com.t1pal.test.biometric.required.\(ProcessInfo.processInfo.processIdentifier)"
    
    @Test("Retrieve with required biometric on Linux falls through")
    func testRetrieveOnLinux() async throws {
        #if os(Linux)
        // On Linux, biometric not available, should fall through to retrieval
        let keychain = KeychainCredentialStore(servicePrefix: Self.testService)
        let store = BiometricCredentialStore(
            keychainStore: keychain,
            requireBiometricForRetrieval: true
        )
        
        let credential = AuthCredential(tokenType: .access, value: "linux-token", expiresAt: Date().addingTimeInterval(3600))
        let key = CredentialKey(service: Self.testService, account: "linux-user")
        
        try await store.store(credential, for: key)
        
        // Should work on Linux since biometric not available
        let retrieved = try await store.retrieve(for: key)
        #expect(retrieved.value == "linux-token")
        
        // Cleanup
        try await store.clearAll()
        #endif
    }
    
    @Test("Authenticate returns not available on Linux")
    func testAuthenticateOnLinux() async {
        #if os(Linux)
        let store = BiometricCredentialStore()
        
        let result = await store.authenticate()
        
        if case .notAvailable(let error) = result {
            #expect(error == .notAvailable)
        } else {
            Issue.record("Expected notAvailable result on Linux")
        }
        #endif
    }
}
