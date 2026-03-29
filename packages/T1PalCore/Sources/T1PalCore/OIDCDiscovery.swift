// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OIDCDiscovery.swift
// T1PalCore
//
// OIDC discovery for custom identity providers
// Backlog: ID-PROV-001
// Spec: https://openid.net/specs/openid-connect-discovery-1_0.html

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Discovery Document

/// OpenID Connect Discovery Document
/// Represents the JSON returned from .well-known/openid-configuration
public struct OIDCDiscoveryDocument: Codable, Sendable, Equatable {
    /// Issuer identifier
    public let issuer: String
    
    /// Authorization endpoint
    public let authorizationEndpoint: URL
    
    /// Token endpoint
    public let tokenEndpoint: URL
    
    /// UserInfo endpoint (optional per spec, required for our use)
    public let userinfoEndpoint: URL?
    
    /// JWKS URI for token validation
    public let jwksUri: URL
    
    /// End session endpoint (optional)
    public let endSessionEndpoint: URL?
    
    /// Registration endpoint (optional)
    public let registrationEndpoint: URL?
    
    /// Revocation endpoint (optional)
    public let revocationEndpoint: URL?
    
    /// Introspection endpoint (optional)
    public let introspectionEndpoint: URL?
    
    /// Supported scopes
    public let scopesSupported: [String]?
    
    /// Supported response types
    public let responseTypesSupported: [String]
    
    /// Supported response modes
    public let responseModesSupported: [String]?
    
    /// Supported grant types
    public let grantTypesSupported: [String]?
    
    /// Supported subject types
    public let subjectTypesSupported: [String]?
    
    /// Supported ID token signing algorithms
    public let idTokenSigningAlgValuesSupported: [String]?
    
    /// Supported token endpoint auth methods
    public let tokenEndpointAuthMethodsSupported: [String]?
    
    /// Supported claims
    public let claimsSupported: [String]?
    
    /// Code challenge methods supported (PKCE)
    public let codeChallengeMethodsSupported: [String]?
    
    /// Coding keys for JSON mapping
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksUri = "jwks_uri"
        case endSessionEndpoint = "end_session_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case responseModesSupported = "response_modes_supported"
        case grantTypesSupported = "grant_types_supported"
        case subjectTypesSupported = "subject_types_supported"
        case idTokenSigningAlgValuesSupported = "id_token_signing_alg_values_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case claimsSupported = "claims_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
    
    /// Check if PKCE is supported
    public var supportsPKCE: Bool {
        guard let methods = codeChallengeMethodsSupported else { return false }
        return methods.contains("S256")
    }
    
    /// Check if refresh tokens are supported
    public var supportsRefreshTokens: Bool {
        guard let grants = grantTypesSupported else { return true } // Assume yes if not specified
        return grants.contains("refresh_token")
    }
    
    /// Convert to OIDCConfiguration for use with T1PalIdentityProvider
    public func toOIDCConfiguration() -> OIDCConfiguration {
        OIDCConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            userInfoEndpoint: userinfoEndpoint ?? tokenEndpoint, // Fallback
            endSessionEndpoint: endSessionEndpoint,
            jwksUri: jwksUri,
            issuer: issuer,
            scopesSupported: scopesSupported ?? ["openid", "profile", "email"],
            responseTypesSupported: responseTypesSupported,
            grantTypesSupported: grantTypesSupported ?? ["authorization_code"]
        )
    }
}

// MARK: - Discovery Errors

/// Errors that can occur during OIDC discovery
public enum OIDCDiscoveryError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case invalidResponse(Int)
    case parseError(String)
    case missingRequiredField(String)
    case unsupportedProvider(String)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid provider URL: \(url)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let status):
            return "Server returned status \(status)"
        case .parseError(let detail):
            return "Failed to parse discovery document: \(detail)"
        case .missingRequiredField(let field):
            return "Discovery document missing required field: \(field)"
        case .unsupportedProvider(let reason):
            return "Provider not supported: \(reason)"
        case .timeout:
            return "Discovery request timed out"
        }
    }
}

// MARK: - Discovery Client Protocol

/// Protocol for OIDC discovery clients
public protocol OIDCDiscoveryClientProtocol: Sendable {
    /// Discover OIDC configuration from provider URL
    func discover(providerURL: URL) async throws -> OIDCDiscoveryDocument
    
    /// Validate that a discovery document meets our requirements
    func validate(document: OIDCDiscoveryDocument) throws
}

// MARK: - Live Discovery Client

/// Live implementation that fetches from network
public actor LiveOIDCDiscoveryClient: OIDCDiscoveryClientProtocol {
    private let session: URLSession
    private let timeout: TimeInterval
    private var cache: [URL: CachedDocument] = [:]
    private let cacheDuration: TimeInterval
    
    /// Cached discovery document
    private struct CachedDocument {
        let document: OIDCDiscoveryDocument
        let fetchedAt: Date
    }
    
    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 30,
        cacheDuration: TimeInterval = 3600 // 1 hour
    ) {
        self.session = session
        self.timeout = timeout
        self.cacheDuration = cacheDuration
    }
    
    public func discover(providerURL: URL) async throws -> OIDCDiscoveryDocument {
        // Build discovery URL
        let discoveryURL = buildDiscoveryURL(from: providerURL)
        
        // Check cache
        if let cached = cache[discoveryURL] {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < cacheDuration {
                return cached.document
            }
        }
        
        // Fetch from network
        var request = URLRequest(url: discoveryURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw OIDCDiscoveryError.timeout
            }
            throw OIDCDiscoveryError.networkError(error)
        }
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OIDCDiscoveryError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OIDCDiscoveryError.invalidResponse(httpResponse.statusCode)
        }
        
        // Parse document
        let document: OIDCDiscoveryDocument
        do {
            let decoder = JSONDecoder()
            document = try decoder.decode(OIDCDiscoveryDocument.self, from: data)
        } catch {
            throw OIDCDiscoveryError.parseError(error.localizedDescription)
        }
        
        // Validate required fields
        try validate(document: document)
        
        // Cache result
        cache[discoveryURL] = CachedDocument(document: document, fetchedAt: Date())
        
        return document
    }
    
    public nonisolated func validate(document: OIDCDiscoveryDocument) throws {
        // Verify PKCE support (required for mobile apps)
        if !document.supportsPKCE {
            throw OIDCDiscoveryError.unsupportedProvider("PKCE (S256) is required but not supported")
        }
        
        // Verify authorization_code grant type
        if let grants = document.grantTypesSupported {
            if !grants.contains("authorization_code") {
                throw OIDCDiscoveryError.unsupportedProvider("authorization_code grant type required")
            }
        }
        
        // Verify userinfo endpoint exists
        if document.userinfoEndpoint == nil {
            throw OIDCDiscoveryError.missingRequiredField("userinfo_endpoint")
        }
    }
    
    /// Build the .well-known URL from a provider base URL
    private func buildDiscoveryURL(from providerURL: URL) -> URL {
        var components = URLComponents(url: providerURL, resolvingAgainstBaseURL: false)!
        
        // Ensure path ends properly
        var path = components.path
        if path.isEmpty || path == "/" {
            path = "/.well-known/openid-configuration"
        } else if !path.hasSuffix("/.well-known/openid-configuration") {
            if path.hasSuffix("/") {
                path += ".well-known/openid-configuration"
            } else {
                path += "/.well-known/openid-configuration"
            }
        }
        
        components.path = path
        components.query = nil
        components.fragment = nil
        
        return components.url!
    }
    
    /// Clear the cache
    public func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Mock Discovery Client

/// Mock implementation for testing
public actor MockOIDCDiscoveryClient: OIDCDiscoveryClientProtocol {
    private var documents: [URL: OIDCDiscoveryDocument] = [:]
    private var errors: [URL: OIDCDiscoveryError] = [:]
    public private(set) var discoverCallCount = 0
    
    public init() {}
    
    /// Configure a mock response for a provider URL
    public func configure(providerURL: URL, document: OIDCDiscoveryDocument) {
        documents[providerURL] = document
        errors.removeValue(forKey: providerURL)
    }
    
    /// Configure an error response for a provider URL
    public func configureError(providerURL: URL, error: OIDCDiscoveryError) {
        errors[providerURL] = error
        documents.removeValue(forKey: providerURL)
    }
    
    public func discover(providerURL: URL) async throws -> OIDCDiscoveryDocument {
        discoverCallCount += 1
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Check for configured error
        if let error = errors[providerURL] {
            throw error
        }
        
        // Check for configured document
        if let document = documents[providerURL] {
            return document
        }
        
        // Default: return a valid mock document
        return .mockValid(issuer: providerURL.absoluteString)
    }
    
    public nonisolated func validate(document: OIDCDiscoveryDocument) throws {
        // Same validation as live client
        if !document.supportsPKCE {
            throw OIDCDiscoveryError.unsupportedProvider("PKCE (S256) is required")
        }
    }
}

// MARK: - Mock Document Factory

extension OIDCDiscoveryDocument {
    /// Create a valid mock document for testing
    public static func mockValid(issuer: String) -> OIDCDiscoveryDocument {
        let baseURL = URL(string: issuer)!
        return OIDCDiscoveryDocument(
            issuer: issuer,
            authorizationEndpoint: baseURL.appendingPathComponent("authorize"),
            tokenEndpoint: baseURL.appendingPathComponent("token"),
            userinfoEndpoint: baseURL.appendingPathComponent("userinfo"),
            jwksUri: baseURL.appendingPathComponent(".well-known/jwks.json"),
            endSessionEndpoint: baseURL.appendingPathComponent("logout"),
            registrationEndpoint: nil,
            revocationEndpoint: baseURL.appendingPathComponent("revoke"),
            introspectionEndpoint: nil,
            scopesSupported: ["openid", "profile", "email", "offline_access"],
            responseTypesSupported: ["code", "id_token", "token"],
            responseModesSupported: ["query", "fragment"],
            grantTypesSupported: ["authorization_code", "refresh_token"],
            subjectTypesSupported: ["public"],
            idTokenSigningAlgValuesSupported: ["RS256"],
            tokenEndpointAuthMethodsSupported: ["client_secret_basic", "client_secret_post"],
            claimsSupported: ["sub", "name", "email", "email_verified"],
            codeChallengeMethodsSupported: ["S256", "plain"]
        )
    }
    
    /// Create a document without PKCE support (for testing validation)
    public static func mockNoPKCE(issuer: String) -> OIDCDiscoveryDocument {
        let doc = mockValid(issuer: issuer)
        return OIDCDiscoveryDocument(
            issuer: doc.issuer,
            authorizationEndpoint: doc.authorizationEndpoint,
            tokenEndpoint: doc.tokenEndpoint,
            userinfoEndpoint: doc.userinfoEndpoint,
            jwksUri: doc.jwksUri,
            endSessionEndpoint: doc.endSessionEndpoint,
            registrationEndpoint: doc.registrationEndpoint,
            revocationEndpoint: doc.revocationEndpoint,
            introspectionEndpoint: doc.introspectionEndpoint,
            scopesSupported: doc.scopesSupported,
            responseTypesSupported: doc.responseTypesSupported,
            responseModesSupported: doc.responseModesSupported,
            grantTypesSupported: doc.grantTypesSupported,
            subjectTypesSupported: doc.subjectTypesSupported,
            idTokenSigningAlgValuesSupported: doc.idTokenSigningAlgValuesSupported,
            tokenEndpointAuthMethodsSupported: doc.tokenEndpointAuthMethodsSupported,
            claimsSupported: doc.claimsSupported,
            codeChallengeMethodsSupported: nil // No PKCE
        )
    }
}

// MARK: - Custom Provider Registry

/// Registry for custom identity providers
public actor CustomProviderRegistry {
    /// A registered custom provider
    public struct RegisteredProvider: Codable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let providerURL: URL
        public let document: OIDCDiscoveryDocument
        public let clientId: String
        public let registeredAt: Date
        
        public init(
            id: String = UUID().uuidString,
            displayName: String,
            providerURL: URL,
            document: OIDCDiscoveryDocument,
            clientId: String,
            registeredAt: Date = Date()
        ) {
            self.id = id
            self.displayName = displayName
            self.providerURL = providerURL
            self.document = document
            self.clientId = clientId
            self.registeredAt = registeredAt
        }
    }
    
    private var providers: [String: RegisteredProvider] = [:]
    private let discoveryClient: OIDCDiscoveryClientProtocol
    
    public init(discoveryClient: OIDCDiscoveryClientProtocol = LiveOIDCDiscoveryClient()) {
        self.discoveryClient = discoveryClient
    }
    
    /// Register a new custom provider
    public func register(
        providerURL: URL,
        displayName: String,
        clientId: String
    ) async throws -> RegisteredProvider {
        // Discover and validate the provider
        let document = try await discoveryClient.discover(providerURL: providerURL)
        
        // Create registered provider
        let provider = RegisteredProvider(
            displayName: displayName,
            providerURL: providerURL,
            document: document,
            clientId: clientId
        )
        
        providers[provider.id] = provider
        return provider
    }
    
    /// Get all registered providers
    public func listProviders() -> [RegisteredProvider] {
        Array(providers.values).sorted { $0.registeredAt < $1.registeredAt }
    }
    
    /// Get a specific provider
    public func getProvider(id: String) -> RegisteredProvider? {
        providers[id]
    }
    
    /// Remove a provider
    public func removeProvider(id: String) {
        providers.removeValue(forKey: id)
    }
    
    /// Check if a provider URL is already registered
    public func isRegistered(providerURL: URL) -> Bool {
        providers.values.contains { $0.providerURL == providerURL }
    }
    
    /// Refresh a provider's discovery document
    public func refresh(id: String) async throws -> RegisteredProvider? {
        guard let existing = providers[id] else { return nil }
        
        let document = try await discoveryClient.discover(providerURL: existing.providerURL)
        
        let updated = RegisteredProvider(
            id: existing.id,
            displayName: existing.displayName,
            providerURL: existing.providerURL,
            document: document,
            clientId: existing.clientId,
            registeredAt: existing.registeredAt
        )
        
        providers[id] = updated
        return updated
    }
}

// MARK: - Provider URL Validation

/// Validates provider URLs before discovery
public struct ProviderURLValidator {
    /// Validation result
    public enum ValidationResult: Sendable {
        case valid
        case invalid(String)
    }
    
    /// Validate a provider URL string
    public static func validate(_ urlString: String) -> ValidationResult {
        // Trim whitespace
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check not empty
        guard !trimmed.isEmpty else {
            return .invalid("URL cannot be empty")
        }
        
        // Parse URL
        guard let url = URL(string: trimmed) else {
            return .invalid("Invalid URL format")
        }
        
        // Must be HTTPS (security requirement)
        guard url.scheme == "https" else {
            return .invalid("HTTPS is required for security")
        }
        
        // Must have a host
        guard let host = url.host, !host.isEmpty else {
            return .invalid("URL must include a host")
        }
        
        // Block localhost/127.0.0.1 in production (allow in debug)
        #if !DEBUG
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") {
            return .invalid("Local addresses not allowed")
        }
        #endif
        
        return .valid
    }
    
    /// Validate and parse a provider URL
    public static func parseAndValidate(_ urlString: String) -> Result<URL, OIDCDiscoveryError> {
        switch validate(urlString) {
        case .valid:
            if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .success(url)
            } else {
                return .failure(.invalidURL(urlString))
            }
        case .invalid(let reason):
            return .failure(.invalidURL(reason))
        }
    }
}
