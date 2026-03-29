// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// T1PalIdentityProvider.swift
// T1Pal Mobile
//
// OIDC-based identity provider for T1Pal authentication.
// Enables federated identity across T1Pal services.
//
// Requirements: PRD-014 (Nightscout Interoperability), REQ-ID-001
// Backlog: OIDC-001

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - OIDC Configuration

/// OpenID Connect discovery configuration
public struct OIDCConfiguration: Codable, Sendable {
    /// Authorization endpoint
    public let authorizationEndpoint: URL
    
    /// Token endpoint
    public let tokenEndpoint: URL
    
    /// UserInfo endpoint
    public let userInfoEndpoint: URL
    
    /// End session endpoint (optional)
    public let endSessionEndpoint: URL?
    
    /// JWKS URI for token validation
    public let jwksUri: URL
    
    /// Issuer identifier
    public let issuer: String
    
    /// Supported scopes
    public let scopesSupported: [String]
    
    /// Supported response types
    public let responseTypesSupported: [String]
    
    /// Supported grant types
    public let grantTypesSupported: [String]
    
    /// Create from discovery document
    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        userInfoEndpoint: URL,
        endSessionEndpoint: URL? = nil,
        jwksUri: URL,
        issuer: String,
        scopesSupported: [String] = ["openid", "profile", "email"],
        responseTypesSupported: [String] = ["code", "id_token", "token"],
        grantTypesSupported: [String] = ["authorization_code", "refresh_token"]
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.userInfoEndpoint = userInfoEndpoint
        self.endSessionEndpoint = endSessionEndpoint
        self.jwksUri = jwksUri
        self.issuer = issuer
        self.scopesSupported = scopesSupported
        self.responseTypesSupported = responseTypesSupported
        self.grantTypesSupported = grantTypesSupported
    }
    
    /// Default T1Pal OIDC configuration
    public static let t1pal = OIDCConfiguration(
        authorizationEndpoint: URL(string: "https://auth.t1pal.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.t1pal.com/token")!,
        userInfoEndpoint: URL(string: "https://auth.t1pal.com/userinfo")!,
        endSessionEndpoint: URL(string: "https://auth.t1pal.com/logout")!,
        jwksUri: URL(string: "https://auth.t1pal.com/.well-known/jwks.json")!,
        issuer: "https://auth.t1pal.com",
        scopesSupported: ["openid", "profile", "email", "nightscout", "offline_access"],
        responseTypesSupported: ["code"],
        grantTypesSupported: ["authorization_code", "refresh_token"]
    )
}

/// OIDC client configuration
public struct OIDCClientConfig: Codable, Sendable {
    /// Client ID
    public let clientId: String
    
    /// Client secret (nil for public clients)
    public let clientSecret: String?
    
    /// Redirect URI
    public let redirectUri: URL
    
    /// Requested scopes
    public let scopes: [String]
    
    /// Use PKCE (recommended for mobile)
    public let usePKCE: Bool
    
    public init(
        clientId: String,
        clientSecret: String? = nil,
        redirectUri: URL,
        scopes: [String] = ["openid", "profile", "email", "offline_access"],
        usePKCE: Bool = true
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectUri = redirectUri
        self.scopes = scopes
        self.usePKCE = usePKCE
    }
}

// MARK: - OIDC Token Response

/// Token response from OIDC token endpoint
public struct OIDCTokenResponse: Codable, Sendable {
    /// Access token
    public let accessToken: String
    
    /// Token type (usually "Bearer")
    public let tokenType: String
    
    /// Expires in seconds
    public let expiresIn: Int?
    
    /// Refresh token (if offline_access scope requested)
    public let refreshToken: String?
    
    /// ID token (JWT)
    public let idToken: String?
    
    /// Granted scope
    public let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case scope
    }
}

/// User info from OIDC userinfo endpoint
public struct OIDCUserInfo: Codable, Sendable {
    /// Subject (user ID)
    public let sub: String
    
    /// Display name
    public let name: String?
    
    /// Given name
    public let givenName: String?
    
    /// Family name
    public let familyName: String?
    
    /// Email
    public let email: String?
    
    /// Email verified
    public let emailVerified: Bool?
    
    /// Picture URL
    public let picture: String?
    
    /// Locale
    public let locale: String?
    
    /// Updated at timestamp
    public let updatedAt: Int?
    
    enum CodingKeys: String, CodingKey {
        case sub
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case email
        case emailVerified = "email_verified"
        case picture
        case locale
        case updatedAt = "updated_at"
    }
}

// MARK: - PKCE Support

/// PKCE code verifier and challenge
public struct PKCEPair: Sendable {
    /// Code verifier (random string)
    public let codeVerifier: String
    
    /// Code challenge (SHA256 of verifier, base64url encoded)
    public let codeChallenge: String
    
    /// Challenge method (always S256)
    public let codeChallengeMethod: String = "S256"
    
    /// Generate a new PKCE pair
    public static func generate() -> PKCEPair {
        // Generate 32 random bytes for verifier
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        
        // Base64url encode for verifier
        let verifier = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // SHA256 hash and base64url encode for challenge
        let challenge = sha256Base64URL(verifier)
        
        return PKCEPair(codeVerifier: verifier, codeChallenge: challenge)
    }
    
    private init(codeVerifier: String, codeChallenge: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
    }
}

// SHA256 helper at file scope for cross-platform compatibility
private func sha256Base64URL(_ input: String) -> String {
    let inputData = Data(input.utf8)
    
    #if canImport(CryptoKit)
    let hash = SHA256.hash(data: inputData)
    let hashData = Data(hash)
    #else
    // Fallback: use CommonCrypto or placeholder
    // In production, use a proper SHA256 implementation
    let hashData = inputData  // Placeholder
    #endif
    
    return hashData
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - Authorization State

/// State for pending authorization request
public struct OIDCAuthState: Codable, Sendable {
    /// State parameter (CSRF protection)
    public let state: String
    
    /// Nonce parameter (replay protection)
    public let nonce: String
    
    /// PKCE code verifier (if using PKCE)
    public let codeVerifier: String?
    
    /// Created timestamp
    public let createdAt: Date
    
    /// Check if state is expired (10 minute timeout)
    public var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 600
    }
    
    /// Generate new auth state
    public static func generate(withPKCE: Bool = true) -> (OIDCAuthState, PKCEPair?) {
        let state = generateRandomString(length: 32)
        let nonce = generateRandomString(length: 32)
        
        if withPKCE {
            let pkce = PKCEPair.generate()
            let authState = OIDCAuthState(
                state: state,
                nonce: nonce,
                codeVerifier: pkce.codeVerifier,
                createdAt: Date()
            )
            return (authState, pkce)
        } else {
            let authState = OIDCAuthState(
                state: state,
                nonce: nonce,
                codeVerifier: nil,
                createdAt: Date()
            )
            return (authState, nil)
        }
    }
}

private func generateRandomString(length: Int) -> String {
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<length).map { _ in chars.randomElement()! })
}

// MARK: - T1Pal Identity Provider

/// T1Pal OIDC identity provider
/// Implements the IdentityProvider protocol for T1Pal authentication.
public actor T1PalIdentityProvider: IdentityProvider {
    /// Provider type
    public nonisolated let providerType: IdentityProviderType = .t1pal
    
    /// Display name
    public nonisolated let displayName: String = "T1Pal"
    
    /// Supported auth methods
    public nonisolated let supportedAuthMethods: [AuthMethod] = [.oidc, .oauth2]
    
    /// OIDC configuration
    private let oidcConfig: OIDCConfiguration
    
    /// Client configuration
    private let clientConfig: OIDCClientConfig
    
    /// Current token response
    private var tokenResponse: OIDCTokenResponse?
    
    /// Current user info
    private var userInfo: OIDCUserInfo?
    
    /// Token expiry date
    private var tokenExpiresAt: Date?
    
    /// Pending auth state (for authorization code flow)
    private var pendingAuthState: OIDCAuthState?
    
    /// Credential storage key prefix
    private let storageKeyPrefix = "t1pal.identity"
    
    /// URL session for network requests
    private let session: URLSession
    
    public init(
        oidcConfig: OIDCConfiguration = .t1pal,
        clientConfig: OIDCClientConfig
    ) {
        self.oidcConfig = oidcConfig
        self.clientConfig = clientConfig
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    /// Check if authenticated
    public func isAuthenticated() async -> Bool {
        guard let tokenResponse = tokenResponse else {
            return false
        }
        
        // Check if token is expired
        if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
            // Try to refresh
            if tokenResponse.refreshToken != nil {
                do {
                    _ = try await refreshIfNeeded()
                    return true
                } catch {
                    return false
                }
            }
            return false
        }
        
        return true
    }
    
    /// Get current credential
    public func getCredential() async -> AuthCredential? {
        guard let tokenResponse = tokenResponse else {
            return nil
        }
        
        return AuthCredential(
            tokenType: .access,
            value: tokenResponse.accessToken,
            expiresAt: tokenExpiresAt
        )
    }
    
    /// Authenticate with provider
    public func authenticate(method: AuthMethod, parameters: [String: String]) async throws -> AuthCredential {
        switch method {
        case .oidc, .oauth2:
            // Check for authorization code
            guard let code = parameters["code"] else {
                throw IdentityError.authenticationFailed("Missing authorization code")
            }
            
            guard let state = parameters["state"] else {
                throw IdentityError.authenticationFailed("Missing state parameter")
            }
            
            // Validate state
            guard let pending = pendingAuthState else {
                throw IdentityError.authenticationFailed("No pending authorization")
            }
            
            guard pending.state == state else {
                throw IdentityError.authenticationFailed("State mismatch - possible CSRF attack")
            }
            
            guard !pending.isExpired else {
                throw IdentityError.authenticationFailed("Authorization expired")
            }
            
            // Exchange code for tokens
            let response = try await exchangeCodeForTokens(
                code: code,
                codeVerifier: pending.codeVerifier
            )
            
            self.tokenResponse = response
            self.tokenExpiresAt = response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            self.pendingAuthState = nil
            
            // Fetch user info
            try await fetchUserInfo()
            
            return AuthCredential(
                tokenType: .access,
                value: response.accessToken,
                expiresAt: tokenExpiresAt
            )
            
        default:
            throw IdentityError.unsupportedAuthMethod
        }
    }
    
    /// Refresh credential if needed
    public func refreshIfNeeded() async throws -> AuthCredential? {
        guard let tokenResponse = tokenResponse else {
            return nil
        }
        
        // Check if refresh is needed
        let needsRefresh: Bool
        if let expiresAt = tokenExpiresAt {
            // Refresh 5 minutes before expiry
            needsRefresh = Date().addingTimeInterval(300) >= expiresAt
        } else {
            needsRefresh = false
        }
        
        guard needsRefresh else {
            return AuthCredential(
                tokenType: .access,
                value: tokenResponse.accessToken,
                expiresAt: tokenExpiresAt
            )
        }
        
        guard let refreshToken = tokenResponse.refreshToken else {
            throw IdentityError.refreshFailed("No refresh token available")
        }
        
        let newResponse = try await refreshTokens(refreshToken: refreshToken)
        
        self.tokenResponse = newResponse
        self.tokenExpiresAt = newResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        
        return AuthCredential(
            tokenType: .access,
            value: newResponse.accessToken,
            expiresAt: tokenExpiresAt
        )
    }
    
    /// Sign out
    public func signOut() async {
        tokenResponse = nil
        userInfo = nil
        tokenExpiresAt = nil
        pendingAuthState = nil
    }
    
    // MARK: - Authorization URL
    
    /// Build authorization URL for starting OAuth flow
    /// - Throws: IdentityError.configurationError if URL cannot be constructed
    public func buildAuthorizationURL() throws -> (URL, OIDCAuthState) {
        let (authState, pkce) = OIDCAuthState.generate(withPKCE: clientConfig.usePKCE)
        
        guard var components = URLComponents(url: oidcConfig.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw IdentityError.configurationError("Invalid authorization endpoint URL")
        }
        
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: clientConfig.redirectUri.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: clientConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: authState.state),
            URLQueryItem(name: "nonce", value: authState.nonce),
        ]
        
        if let pkce = pkce {
            queryItems.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod))
        }
        
        components.queryItems = queryItems
        
        guard let authURL = components.url else {
            throw IdentityError.configurationError("Could not construct authorization URL")
        }
        
        // Store pending state
        self.pendingAuthState = authState
        
        return (authURL, authState)
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForTokens(code: String, codeVerifier: String?) async throws -> OIDCTokenResponse {
        var body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": clientConfig.redirectUri.absoluteString,
            "client_id": clientConfig.clientId,
        ]
        
        if let verifier = codeVerifier {
            body["code_verifier"] = verifier
        }
        
        if let secret = clientConfig.clientSecret {
            body["client_secret"] = secret
        }
        
        return try await postTokenRequest(body: body)
    }
    
    private func refreshTokens(refreshToken: String) async throws -> OIDCTokenResponse {
        var body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientConfig.clientId,
        ]
        
        if let secret = clientConfig.clientSecret {
            body["client_secret"] = secret
        }
        
        return try await postTokenRequest(body: body)
    }
    
    private func postTokenRequest(body: [String: String]) async throws -> OIDCTokenResponse {
        var request = URLRequest(url: oidcConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IdentityError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw IdentityError.authenticationFailed("Token request failed: \(httpResponse.statusCode) - \(errorBody)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(OIDCTokenResponse.self, from: data)
    }
    
    // MARK: - User Info
    
    private func fetchUserInfo() async throws {
        guard let accessToken = tokenResponse?.accessToken else {
            return
        }
        
        var request = URLRequest(url: oidcConfig.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return // Non-fatal, user info is optional
        }
        
        let decoder = JSONDecoder()
        self.userInfo = try? decoder.decode(OIDCUserInfo.self, from: data)
    }
    
    /// Get current user identity
    public func getUserIdentity() async -> UserIdentity? {
        guard let info = userInfo else {
            return nil
        }
        
        return UserIdentity(
            id: info.sub,
            provider: .t1pal,
            displayName: info.name,
            email: info.email,
            avatarUrl: info.picture.flatMap { URL(string: $0) },
            createdAt: Date()
        )
    }
    
    /// Get ID token claims (decoded JWT payload)
    public func getIdTokenClaims() async -> [String: Any]? {
        guard let idToken = tokenResponse?.idToken else {
            return nil
        }
        
        // Decode JWT (without validation - just extract claims)
        let parts = idToken.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }
        
        var payload = String(parts[1])
        // Pad base64 if needed
        while payload.count % 4 != 0 {
            payload += "="
        }
        
        // Base64url to base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Mock Provider

/// Mock T1Pal identity provider for testing
public actor MockT1PalIdentityProvider: IdentityProvider {
    public nonisolated let providerType: IdentityProviderType = .t1pal
    public nonisolated let displayName: String = "T1Pal (Mock)"
    public nonisolated let supportedAuthMethods: [AuthMethod] = [.oidc, .oauth2]
    
    private var isLoggedIn = false
    private var mockUserId = "mock-user-123"
    private var mockEmail = "test@t1pal.com"
    private var mockAccessToken = "mock-access-token"
    
    public init() {}
    
    public func isAuthenticated() async -> Bool {
        return isLoggedIn
    }
    
    public func getCredential() async -> AuthCredential? {
        guard isLoggedIn else { return nil }
        return AuthCredential(
            tokenType: .access,
            value: mockAccessToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    public func authenticate(method: AuthMethod, parameters: [String: String]) async throws -> AuthCredential {
        // Simulate authentication delay
        try await Task.sleep(nanoseconds: 100_000_000)
        
        isLoggedIn = true
        
        return AuthCredential(
            tokenType: .access,
            value: mockAccessToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    public func refreshIfNeeded() async throws -> AuthCredential? {
        guard isLoggedIn else { return nil }
        return await getCredential()
    }
    
    public func signOut() async {
        isLoggedIn = false
    }
    
    /// Configure mock user for testing
    public func configureMockUser(userId: String, email: String, accessToken: String) {
        mockUserId = userId
        mockEmail = email
        mockAccessToken = accessToken
    }
    
    /// Get mock user identity
    public func getUserIdentity() async -> UserIdentity? {
        guard isLoggedIn else { return nil }
        return UserIdentity(
            id: mockUserId,
            provider: .t1pal,
            displayName: "Test User",
            email: mockEmail,
            createdAt: Date()
        )
    }
}
