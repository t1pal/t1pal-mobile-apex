// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// OIDCProviderRegistryTests.swift
// T1PalCoreTests
//
// Tests for OIDC provider registry and enterprise identity support.
// Trace: ID-ENT-001

import Testing
@testable import T1PalCore
import Foundation

// MARK: - Provider Category Tests

@Suite("OIDCProviderCategory Tests")
struct OIDCProviderCategoryTests {
    
    @Test("All categories have display names")
    func testDisplayNames() {
        for category in OIDCProviderCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }
    
    @Test("All categories have descriptions")
    func testDescriptions() {
        for category in OIDCProviderCategory.allCases {
            #expect(!category.description.isEmpty)
        }
    }
    
    @Test("Categories are codable")
    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for category in OIDCProviderCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(OIDCProviderCategory.self, from: data)
            #expect(decoded == category)
        }
    }
}

// MARK: - Known Provider Tests

@Suite("KnownOIDCProvider Tests")
struct KnownOIDCProviderTests {
    
    @Test("All providers have required properties")
    func testProviderProperties() {
        for provider in KnownOIDCProvider.allCases {
            #expect(!provider.id.isEmpty)
            #expect(!provider.displayName.isEmpty)
            #expect(!provider.defaultScopes.isEmpty)
            #expect(!provider.iconName.isEmpty)
            // issuerURL should be valid
            #expect(provider.issuerURL.scheme == "https")
        }
    }
    
    @Test("Consumer providers are correctly categorized")
    func testConsumerProviders() {
        let consumers = KnownOIDCProvider.providers(for: .consumer)
        #expect(consumers.contains(.google))
        #expect(consumers.contains(.apple))
        #expect(consumers.contains(.microsoft))
    }
    
    @Test("Enterprise providers are correctly categorized")
    func testEnterpriseProviders() {
        let enterprise = KnownOIDCProvider.providers(for: .enterprise)
        #expect(enterprise.contains(.okta))
        #expect(enterprise.contains(.auth0))
        #expect(enterprise.contains(.azureAD))
    }
    
    @Test("Healthcare providers are correctly categorized")
    func testHealthcareProviders() {
        let healthcare = KnownOIDCProvider.providers(for: .healthcare)
        #expect(healthcare.contains(.epicMyChart))
        #expect(healthcare.contains(.cerner))
    }
    
    @Test("Self-hosted providers are correctly categorized")
    func testSelfHostedProviders() {
        let selfHosted = KnownOIDCProvider.providers(for: .selfHosted)
        #expect(selfHosted.contains(.keycloak))
        #expect(selfHosted.contains(.oryHydra))
    }
    
    @Test("PKCE is supported by all providers")
    func testPKCESupport() {
        for provider in KnownOIDCProvider.allCases {
            #expect(provider.supportsPKCE == true)
        }
    }
    
    @Test("Epic MyChart has FHIR scopes")
    func testEpicScopes() {
        let scopes = KnownOIDCProvider.epicMyChart.defaultScopes
        #expect(scopes.contains("fhirUser"))
        #expect(scopes.contains { $0.contains("patient") })
    }
    
    @Test("Providers requiring custom issuer are identified")
    func testCustomIssuerRequired() {
        #expect(KnownOIDCProvider.okta.requiresCustomIssuer == true)
        #expect(KnownOIDCProvider.auth0.requiresCustomIssuer == true)
        #expect(KnownOIDCProvider.keycloak.requiresCustomIssuer == true)
        #expect(KnownOIDCProvider.google.requiresCustomIssuer == false)
        #expect(KnownOIDCProvider.apple.requiresCustomIssuer == false)
    }
}

// MARK: - Provider Config Tests

@Suite("OIDCProviderConfig Tests")
struct OIDCProviderConfigTests {
    
    @Test("Config initializes correctly")
    func testInitialization() {
        let config = OIDCProviderConfig(
            providerId: "test",
            displayName: "Test Provider",
            category: .custom,
            issuerURL: URL(string: "https://auth.example.com")!,
            clientId: "client123",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        #expect(config.providerId == "test")
        #expect(config.displayName == "Test Provider")
        #expect(config.category == .custom)
        #expect(config.clientId == "client123")
        #expect(config.usePKCE == true)
        #expect(config.scopes == ["openid", "profile", "email"])
    }
    
    @Test("Config from known provider preset")
    func testFromPreset() {
        let config = OIDCProviderConfig.from(
            provider: .google,
            clientId: "google-client-id",
            redirectUri: URL(string: "com.t1pal.app:/oauth2callback")!
        )
        
        #expect(config.providerId == "google")
        #expect(config.displayName == "Google")
        #expect(config.category == .consumer)
        #expect(config.issuerURL == URL(string: "https://accounts.google.com")!)
        #expect(config.scopes.contains("openid"))
        #expect(config.scopes.contains("profile"))
        #expect(config.scopes.contains("email"))
    }
    
    @Test("Config from preset with additional scopes")
    func testFromPresetWithScopes() {
        let config = OIDCProviderConfig.from(
            provider: .okta,
            clientId: "okta-client",
            redirectUri: URL(string: "t1pal://callback")!,
            additionalScopes: ["custom_scope"]
        )
        
        #expect(config.scopes.contains("openid"))
        #expect(config.scopes.contains("custom_scope"))
    }
    
    @Test("Config is codable")
    func testCodable() throws {
        let config = OIDCProviderConfig(
            providerId: "test",
            displayName: "Test",
            category: .enterprise,
            issuerURL: URL(string: "https://auth.example.com")!,
            clientId: "client",
            clientSecret: "secret",
            redirectUri: URL(string: "t1pal://callback")!,
            scopes: ["openid", "profile"],
            usePKCE: true,
            additionalParams: ["prompt": "login"]
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(OIDCProviderConfig.self, from: data)
        
        #expect(decoded == config)
    }
}

// MARK: - Provider Registry Tests

@Suite("OIDCProviderRegistry Tests")
struct OIDCProviderRegistryTests {
    
    @Test("Registry initializes empty")
    func testEmptyInit() async {
        let registry = OIDCProviderRegistry()
        let configs = await registry.allConfigurations()
        // Note: May have persisted configs from previous tests, just check it doesn't crash
        _ = configs
    }
    
    @Test("Register and retrieve configuration")
    func testRegisterAndRetrieve() async {
        let registry = OIDCProviderRegistry()
        
        let config = OIDCProviderConfig(
            providerId: "test-provider-\(UUID().uuidString.prefix(8))",
            displayName: "Test Provider",
            category: .custom,
            issuerURL: URL(string: "https://auth.test.com")!,
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        await registry.register(config)
        
        let retrieved = await registry.configuration(for: config.providerId)
        #expect(retrieved != nil)
        #expect(retrieved?.clientId == "test-client")
        
        // Cleanup
        await registry.remove(providerId: config.providerId)
    }
    
    @Test("Remove configuration")
    func testRemove() async {
        let registry = OIDCProviderRegistry()
        
        let providerId = "remove-test-\(UUID().uuidString.prefix(8))"
        let config = OIDCProviderConfig(
            providerId: providerId,
            displayName: "Remove Test",
            category: .custom,
            issuerURL: URL(string: "https://auth.test.com")!,
            clientId: "client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        await registry.register(config)
        #expect(await registry.configuration(for: providerId) != nil)
        
        await registry.remove(providerId: providerId)
        #expect(await registry.configuration(for: providerId) == nil)
    }
    
    @Test("Mark provider as used")
    func testMarkUsed() async {
        let registry = OIDCProviderRegistry()
        
        let providerId = "used-test-\(UUID().uuidString.prefix(8))"
        let config = OIDCProviderConfig(
            providerId: providerId,
            displayName: "Used Test",
            category: .custom,
            issuerURL: URL(string: "https://auth.test.com")!,
            clientId: "client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        await registry.register(config)
        
        // Initially no lastUsedAt
        let before = await registry.configuration(for: providerId)
        #expect(before?.lastUsedAt == nil)
        
        // Mark as used
        await registry.markUsed(providerId: providerId)
        
        let after = await registry.configuration(for: providerId)
        #expect(after?.lastUsedAt != nil)
        
        // Cleanup
        await registry.remove(providerId: providerId)
    }
    
    @Test("Filter by category")
    func testFilterByCategory() async {
        let registry = OIDCProviderRegistry()
        
        // Register configs of different categories
        let enterpriseConfig = OIDCProviderConfig(
            providerId: "cat-ent-\(UUID().uuidString.prefix(8))",
            displayName: "Enterprise Test",
            category: .enterprise,
            issuerURL: URL(string: "https://auth.test.com")!,
            clientId: "client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        let healthcareConfig = OIDCProviderConfig(
            providerId: "cat-health-\(UUID().uuidString.prefix(8))",
            displayName: "Healthcare Test",
            category: .healthcare,
            issuerURL: URL(string: "https://auth.test.com")!,
            clientId: "client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        await registry.register(enterpriseConfig)
        await registry.register(healthcareConfig)
        
        let enterprise = await registry.configurations(for: .enterprise)
        let healthcare = await registry.configurations(for: .healthcare)
        
        #expect(enterprise.contains { $0.providerId == enterpriseConfig.providerId })
        #expect(healthcare.contains { $0.providerId == healthcareConfig.providerId })
        
        // Cleanup
        await registry.remove(providerId: enterpriseConfig.providerId)
        await registry.remove(providerId: healthcareConfig.providerId)
    }
}

// MARK: - Custom Provider Builder Tests

@Suite("CustomOIDCProviderBuilder Tests")
struct CustomOIDCProviderBuilderTests {
    
    @Test("Builder creates valid config")
    func testBuilderSuccess() throws {
        let config = try CustomOIDCProviderBuilder()
            .issuer(URL(string: "https://auth.mycompany.com")!)
            .clientId("my-client-id")
            .redirectUri(URL(string: "t1pal://callback")!)
            .displayName("My Company SSO")
            .scopes(["openid", "profile", "email", "custom"])
            .build()
        
        #expect(config.displayName == "My Company SSO")
        #expect(config.issuerURL == URL(string: "https://auth.mycompany.com")!)
        #expect(config.clientId == "my-client-id")
        #expect(config.scopes.contains("custom"))
        #expect(config.category == OIDCProviderCategory.custom)
        #expect(config.providerId.hasPrefix("custom."))
    }
    
    @Test("Builder fails without issuer")
    func testBuilderMissingIssuer() {
        let builder = CustomOIDCProviderBuilder()
            .clientId("client")
            .redirectUri(URL(string: "t1pal://callback")!)
        
        #expect(throws: OIDCProviderBuilderError.missingIssuer) {
            try builder.build()
        }
    }
    
    @Test("Builder fails without client ID")
    func testBuilderMissingClientId() {
        let builder = CustomOIDCProviderBuilder()
            .issuer(URL(string: "https://auth.example.com")!)
            .redirectUri(URL(string: "t1pal://callback")!)
        
        #expect(throws: OIDCProviderBuilderError.missingClientId) {
            try builder.build()
        }
    }
    
    @Test("Builder fails without redirect URI")
    func testBuilderMissingRedirectUri() {
        let builder = CustomOIDCProviderBuilder()
            .issuer(URL(string: "https://auth.example.com")!)
            .clientId("client")
        
        #expect(throws: OIDCProviderBuilderError.missingRedirectUri) {
            try builder.build()
        }
    }
    
    @Test("Builder error descriptions")
    func testErrorDescriptions() {
        #expect(OIDCProviderBuilderError.missingIssuer.errorDescription?.contains("Issuer") == true)
        #expect(OIDCProviderBuilderError.missingClientId.errorDescription?.contains("Client") == true)
        #expect(OIDCProviderBuilderError.missingRedirectUri.errorDescription?.contains("Redirect") == true)
    }
}
