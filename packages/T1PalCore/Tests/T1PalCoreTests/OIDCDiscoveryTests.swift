// SPDX-License-Identifier: MIT
//
// OIDCDiscoveryTests.swift
// T1PalCore Tests
//
// Tests for OIDC discovery client
// Backlog: ID-PROV-001

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import T1PalCore

// MARK: - Discovery Document Tests

@Suite("OIDC Discovery Document")
struct OIDCDiscoveryDocumentTests {
    
    @Test("Create valid mock document")
    func testMockValid() {
        let doc = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        
        #expect(doc.issuer == "https://auth.example.com")
        #expect(doc.authorizationEndpoint.absoluteString == "https://auth.example.com/authorize")
        #expect(doc.tokenEndpoint.absoluteString == "https://auth.example.com/token")
        #expect(doc.userinfoEndpoint?.absoluteString == "https://auth.example.com/userinfo")
        #expect(doc.jwksUri.absoluteString == "https://auth.example.com/.well-known/jwks.json")
    }
    
    @Test("PKCE support detection")
    func testPKCESupport() {
        let withPKCE = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        #expect(withPKCE.supportsPKCE == true)
        
        let withoutPKCE = OIDCDiscoveryDocument.mockNoPKCE(issuer: "https://auth.example.com")
        #expect(withoutPKCE.supportsPKCE == false)
    }
    
    @Test("Refresh token support detection")
    func testRefreshTokenSupport() {
        let doc = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        #expect(doc.supportsRefreshTokens == true)
    }
    
    @Test("Convert to OIDCConfiguration")
    func testToOIDCConfiguration() {
        let doc = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        let config = doc.toOIDCConfiguration()
        
        #expect(config.issuer == doc.issuer)
        #expect(config.authorizationEndpoint == doc.authorizationEndpoint)
        #expect(config.tokenEndpoint == doc.tokenEndpoint)
        #expect(config.jwksUri == doc.jwksUri)
    }
    
    @Test("Document equality")
    func testEquality() {
        let doc1 = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        let doc2 = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        let doc3 = OIDCDiscoveryDocument.mockValid(issuer: "https://other.example.com")
        
        #expect(doc1 == doc2)
        #expect(doc1 != doc3)
    }
    
    @Test("Document is Codable")
    func testCodable() throws {
        let original = OIDCDiscoveryDocument.mockValid(issuer: "https://auth.example.com")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OIDCDiscoveryDocument.self, from: data)
        
        #expect(decoded.issuer == original.issuer)
        #expect(decoded.authorizationEndpoint == original.authorizationEndpoint)
    }
}

// MARK: - Mock Discovery Client Tests

@Suite("Mock OIDC Discovery Client")
struct MockOIDCDiscoveryClientTests {
    
    @Test("Default discovery returns valid document")
    func testDefaultDiscovery() async throws {
        let client = MockOIDCDiscoveryClient()
        let providerURL = URL(string: "https://auth.example.com")!
        
        let document = try await client.discover(providerURL: providerURL)
        
        #expect(document.issuer == providerURL.absoluteString)
        #expect(document.supportsPKCE == true)
    }
    
    @Test("Configured document is returned")
    func testConfiguredDocument() async throws {
        let client = MockOIDCDiscoveryClient()
        let providerURL = URL(string: "https://custom.example.com")!
        let customDoc = OIDCDiscoveryDocument.mockValid(issuer: "https://custom-issuer.com")
        
        await client.configure(providerURL: providerURL, document: customDoc)
        
        let document = try await client.discover(providerURL: providerURL)
        #expect(document.issuer == "https://custom-issuer.com")
    }
    
    @Test("Configured error is thrown")
    func testConfiguredError() async throws {
        let client = MockOIDCDiscoveryClient()
        let providerURL = URL(string: "https://error.example.com")!
        
        await client.configureError(providerURL: providerURL, error: .timeout)
        
        await #expect(throws: OIDCDiscoveryError.self) {
            try await client.discover(providerURL: providerURL)
        }
    }
    
    @Test("Call count is tracked")
    func testCallCount() async throws {
        let client = MockOIDCDiscoveryClient()
        let providerURL = URL(string: "https://auth.example.com")!
        
        _ = try await client.discover(providerURL: providerURL)
        _ = try await client.discover(providerURL: providerURL)
        _ = try await client.discover(providerURL: providerURL)
        
        let count = await client.discoverCallCount
        #expect(count == 3)
    }
    
    @Test("Validation rejects no PKCE")
    func testValidationRejectsNoPKCE() async throws {
        let client = MockOIDCDiscoveryClient()
        let doc = OIDCDiscoveryDocument.mockNoPKCE(issuer: "https://nopkce.example.com")
        
        #expect(throws: OIDCDiscoveryError.self) {
            try client.validate(document: doc)
        }
    }
}

// MARK: - Provider URL Validator Tests

@Suite("Provider URL Validator")
struct ProviderURLValidatorTests {
    
    @Test("Valid HTTPS URL passes")
    func testValidHTTPS() {
        let result = ProviderURLValidator.validate("https://auth.example.com")
        if case .valid = result {
            // Expected
        } else {
            Issue.record("Expected valid")
        }
    }
    
    @Test("HTTP URL fails")
    func testHTTPFails() {
        let result = ProviderURLValidator.validate("http://auth.example.com")
        if case .invalid(let reason) = result {
            #expect(reason.contains("HTTPS"))
        } else {
            Issue.record("Expected invalid")
        }
    }
    
    @Test("Empty URL fails")
    func testEmptyFails() {
        let result = ProviderURLValidator.validate("")
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected invalid")
        }
    }
    
    @Test("Whitespace-only fails")
    func testWhitespaceFails() {
        let result = ProviderURLValidator.validate("   ")
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected invalid")
        }
    }
    
    @Test("Invalid URL format fails")
    func testInvalidFormatFails() {
        let result = ProviderURLValidator.validate("not a url")
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected invalid")
        }
    }
    
    @Test("Parse and validate success")
    func testParseAndValidateSuccess() {
        let result = ProviderURLValidator.parseAndValidate("https://auth.example.com")
        if case .success(let url) = result {
            #expect(url.host == "auth.example.com")
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parse and validate failure")
    func testParseAndValidateFailure() {
        let result = ProviderURLValidator.parseAndValidate("http://insecure.com")
        if case .failure = result {
            // Expected
        } else {
            Issue.record("Expected failure")
        }
    }
}

// MARK: - Custom Provider Registry Tests

@Suite("Custom Provider Registry")
struct CustomProviderRegistryTests {
    
    @Test("Register new provider")
    func testRegisterProvider() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        let providerURL = URL(string: "https://custom.example.com")!
        let provider = try await registry.register(
            providerURL: providerURL,
            displayName: "Custom Provider",
            clientId: "client-123"
        )
        
        #expect(provider.displayName == "Custom Provider")
        #expect(provider.clientId == "client-123")
        #expect(provider.providerURL == providerURL)
    }
    
    @Test("List registered providers")
    func testListProviders() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        _ = try await registry.register(
            providerURL: URL(string: "https://provider1.com")!,
            displayName: "Provider 1",
            clientId: "client-1"
        )
        
        _ = try await registry.register(
            providerURL: URL(string: "https://provider2.com")!,
            displayName: "Provider 2",
            clientId: "client-2"
        )
        
        let providers = await registry.listProviders()
        #expect(providers.count == 2)
    }
    
    @Test("Get provider by ID")
    func testGetProvider() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        let registered = try await registry.register(
            providerURL: URL(string: "https://provider.com")!,
            displayName: "My Provider",
            clientId: "client-abc"
        )
        
        let retrieved = await registry.getProvider(id: registered.id)
        #expect(retrieved?.displayName == "My Provider")
    }
    
    @Test("Remove provider")
    func testRemoveProvider() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        let registered = try await registry.register(
            providerURL: URL(string: "https://provider.com")!,
            displayName: "To Remove",
            clientId: "client-xyz"
        )
        
        await registry.removeProvider(id: registered.id)
        
        let retrieved = await registry.getProvider(id: registered.id)
        #expect(retrieved == nil)
    }
    
    @Test("Check if registered")
    func testIsRegistered() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        let providerURL = URL(string: "https://registered.com")!
        let otherURL = URL(string: "https://notregistered.com")!
        
        _ = try await registry.register(
            providerURL: providerURL,
            displayName: "Registered",
            clientId: "client"
        )
        
        let isRegistered = await registry.isRegistered(providerURL: providerURL)
        let isNotRegistered = await registry.isRegistered(providerURL: otherURL)
        
        #expect(isRegistered == true)
        #expect(isNotRegistered == false)
    }
    
    @Test("Refresh provider document")
    func testRefreshProvider() async throws {
        let mockClient = MockOIDCDiscoveryClient()
        let registry = CustomProviderRegistry(discoveryClient: mockClient)
        
        let providerURL = URL(string: "https://refreshable.com")!
        let registered = try await registry.register(
            providerURL: providerURL,
            displayName: "Refreshable",
            clientId: "client"
        )
        
        // Refresh
        let refreshed = try await registry.refresh(id: registered.id)
        
        #expect(refreshed?.id == registered.id)
        #expect(refreshed?.displayName == registered.displayName)
    }
}

// MARK: - Discovery Error Tests

@Suite("OIDC Discovery Errors")
struct OIDCDiscoveryErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [OIDCDiscoveryError] = [
            .invalidURL("test"),
            .invalidResponse(404),
            .parseError("test"),
            .missingRequiredField("test"),
            .unsupportedProvider("test"),
            .timeout
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Network error wraps underlying")
    func testNetworkError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = OIDCDiscoveryError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network") == true)
    }
}

// MARK: - Live Client URL Building Tests

@Suite("Live Discovery Client")
struct LiveOIDCDiscoveryClientTests {
    
    @Test("Cache can be cleared")
    func testClearCache() async {
        let client = LiveOIDCDiscoveryClient(cacheDuration: 3600)
        await client.clearCache()
        // No error means success
    }
}

// MARK: - Registered Provider Tests

@Suite("Registered Provider")
struct RegisteredProviderTests {
    
    @Test("Provider has unique ID")
    func testUniqueId() {
        let doc = OIDCDiscoveryDocument.mockValid(issuer: "https://test.com")
        
        let provider1 = CustomProviderRegistry.RegisteredProvider(
            displayName: "Provider 1",
            providerURL: URL(string: "https://test.com")!,
            document: doc,
            clientId: "client-1"
        )
        
        let provider2 = CustomProviderRegistry.RegisteredProvider(
            displayName: "Provider 2",
            providerURL: URL(string: "https://test.com")!,
            document: doc,
            clientId: "client-2"
        )
        
        #expect(provider1.id != provider2.id)
    }
    
    @Test("Provider is Codable")
    func testCodable() throws {
        let doc = OIDCDiscoveryDocument.mockValid(issuer: "https://test.com")
        let provider = CustomProviderRegistry.RegisteredProvider(
            id: "test-id",
            displayName: "Test Provider",
            providerURL: URL(string: "https://test.com")!,
            document: doc,
            clientId: "client-123"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(provider)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CustomProviderRegistry.RegisteredProvider.self, from: data)
        
        #expect(decoded.id == provider.id)
        #expect(decoded.displayName == provider.displayName)
        #expect(decoded.clientId == provider.clientId)
    }
}
