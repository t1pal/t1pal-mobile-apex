// SPDX-License-Identifier: MIT
//
// NightscoutCredentialVaultTests.swift
// T1Pal Mobile
//
// Tests for Nightscout credential vault
// Requirements: PROD-KEYCHAIN-001

import Foundation
import Testing
@testable import NightscoutKit
@testable import T1PalCore

private func makeValidToken() -> String {
    let now = Int(Date().timeIntervalSince1970)
    let exp = now + 3600 // 1 hour from now
    return makeToken(iat: now, exp: exp)
}

private func makeExpiredToken() -> String {
    let now = Int(Date().timeIntervalSince1970)
    let exp = now - 3600 // 1 hour ago
    return makeToken(iat: now - 7200, exp: exp)
}

private func makeToken(iat: Int, exp: Int) -> String {
    let header = base64URLEncode(#"{"alg":"HS256","typ":"JWT"}"#)
    let payload = base64URLEncode(#"{"iat":\#(iat),"exp":\#(exp),"sub":"api:read"}"#)
    let signature = "test_signature"
    return "\(header).\(payload).\(signature)"
}

private func base64URLEncode(_ string: String) -> String {
    let data = Data(string.utf8)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@Suite("NightscoutCredentialVault - API Secret", .serialized)
struct CredentialVaultAPISecretTests {
    
    let vault = NightscoutCredentialVault()
    let testURL = URL(string: "https://apisecret-test-ns.herokuapp.com")!
    let testURL2 = URL(string: "https://apisecret-another-ns.example.com")!
    
    init() async throws {
        // Clean up any existing credentials
        _ = await vault.deleteAllCredentials(for: testURL)
        _ = await vault.deleteAllCredentials(for: testURL2)
    }
    
    @Test("store and retrieve API secret")
    func storeAndRetrieveAPISecret() async {
        let secret = "my-test-secret-12345"
        
        let stored = await vault.storeAPISecret(secret, for: testURL)
        #expect(stored)
        
        let retrieved = await vault.getAPISecret(for: testURL)
        #expect(retrieved == secret)
        
        // Cleanup
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("delete API secret")
    func deleteAPISecret() async {
        let secret = "secret-to-delete"
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        
        let deleted = await vault.deleteAPISecret(for: testURL)
        #expect(deleted)
        
        let retrieved = await vault.getAPISecret(for: testURL)
        #expect(retrieved == nil)
    }
    
    @Test("API secret isolation between servers")
    func apiSecretIsolation() async {
        let secret1 = "secret-for-server-1"
        let secret2 = "secret-for-server-2"
        
        _ = await vault.storeAPISecret(secret1, for: testURL)
        _ = await vault.storeAPISecret(secret2, for: testURL2)
        
        let retrieved1 = await vault.getAPISecret(for: testURL)
        let retrieved2 = await vault.getAPISecret(for: testURL2)
        
        #expect(retrieved1 == secret1)
        #expect(retrieved2 == secret2)
        
        // Cleanup
        _ = await vault.deleteAllCredentials(for: testURL)
        _ = await vault.deleteAllCredentials(for: testURL2)
    }
}

@Suite("NightscoutCredentialVault - JWT Token", .serialized)
struct CredentialVaultJWTTests {
    
    let vault = NightscoutCredentialVault()
    let testURL = URL(string: "https://jwt-test-ns.herokuapp.com")!
    
    init() async throws {
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("store and retrieve JWT token")
    func storeAndRetrieveJWTToken() async {
        let token = makeValidToken()
        
        let stored = await vault.storeJWTToken(token, for: testURL)
        #expect(stored)
        
        let retrieved = await vault.getJWTToken(for: testURL)
        #expect(retrieved == token)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("expired token returns nil")
    func expiredTokenReturnsNil() async {
        let expiredToken = makeExpiredToken()
        
        _ = await vault.storeJWTToken(expiredToken, for: testURL)
        
        let retrieved = await vault.getJWTToken(for: testURL)
        #expect(retrieved == nil)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("delete JWT token")
    func deleteJWTToken() async {
        let token = makeValidToken()
        
        _ = await vault.storeJWTToken(token, for: testURL)
        
        let deleted = await vault.deleteJWTToken(for: testURL)
        #expect(deleted)
        
        let retrieved = await vault.getJWTToken(for: testURL)
        #expect(retrieved == nil)
    }
}

@Suite("NightscoutCredentialVault - Unified Credentials", .serialized)
struct CredentialVaultUnifiedTests {
    
    let vault = NightscoutCredentialVault()
    let testURL = URL(string: "https://unified-test-ns.herokuapp.com")!
    
    init() async throws {
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("get credentials combines secret and token")
    func getCredentials() async {
        let secret = "api-secret-123"
        let token = makeValidToken()
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        _ = await vault.storeJWTToken(token, for: testURL)
        
        let credentials = await vault.getCredentials(for: testURL)
        
        #expect(credentials.url == testURL)
        #expect(credentials.apiSecret == secret)
        #expect(credentials.jwtToken == token)
        #expect(credentials.hasCredentials)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("preferred auth mode with both credentials")
    func preferredAuthModeWithBoth() async {
        let secret = "api-secret"
        let token = makeValidToken()
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        _ = await vault.storeJWTToken(token, for: testURL)
        
        let credentials = await vault.getCredentials(for: testURL)
        
        #expect(credentials.preferredAuthMode == .jwtToken)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("preferred auth mode with only secret")
    func preferredAuthModeWithOnlySecret() async {
        let secret = "api-secret"
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        
        let credentials = await vault.getCredentials(for: testURL)
        
        #expect(credentials.preferredAuthMode == .apiSecret)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("preferred auth mode with expired token")
    func preferredAuthModeWithExpiredToken() async {
        let secret = "api-secret"
        let expiredToken = makeExpiredToken()
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        _ = await vault.storeJWTToken(expiredToken, for: testURL)
        
        let credentials = await vault.getCredentials(for: testURL)
        
        #expect(credentials.preferredAuthMode == .apiSecret)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("delete all credentials")
    func deleteAllCredentials() async {
        let secret = "api-secret"
        let token = makeValidToken()
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        _ = await vault.storeJWTToken(token, for: testURL)
        
        let deleted = await vault.deleteAllCredentials(for: testURL)
        #expect(deleted)
        
        let credentials = await vault.getCredentials(for: testURL)
        #expect(!credentials.hasCredentials)
        #expect(credentials.apiSecret == nil)
        #expect(credentials.jwtToken == nil)
    }
    
    @Test("clear cache still loads from keychain")
    func clearCache() async {
        let secret = "api-secret"
        
        _ = await vault.storeAPISecret(secret, for: testURL)
        
        // Load into cache
        _ = await vault.getCredentials(for: testURL)
        
        // Clear cache
        await vault.clearCache()
        
        // Should still load from keychain
        let retrieved = await vault.getAPISecret(for: testURL)
        #expect(retrieved == secret)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
    
    @Test("empty credentials")
    func emptyCredentials() async {
        let credentials = await vault.getCredentials(for: testURL)
        
        #expect(!credentials.hasCredentials)
        #expect(credentials.apiSecret == nil)
        #expect(credentials.jwtToken == nil)
        #expect(credentials.preferredAuthMode == .none)
    }
    
    @Test("URL normalization")
    func urlNormalization() async {
        let secret = "normalized-secret"
        
        // Store with path
        let urlWithPath = URL(string: "https://unified-test-ns.herokuapp.com/api/v1/entries")!
        _ = await vault.storeAPISecret(secret, for: urlWithPath)
        
        // Retrieve with base URL
        let retrieved = await vault.getAPISecret(for: testURL)
        #expect(retrieved == secret)
        
        _ = await vault.deleteAllCredentials(for: testURL)
    }
}
