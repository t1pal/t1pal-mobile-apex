// SPDX-License-Identifier: MIT
//
// OIDCAuthTests.swift
// T1PalCoreTests
//
// Tests for OIDC/OAuth 2.0 PKCE authentication
// Backlog: ID-AUTH-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - PKCE Tests

@Suite("PKCE Tests")
struct PKCETests {
    
    @Test("PKCE pair generation")
    func pkcePairGeneration() {
        let pkce = PKCEPair.generate()
        
        // Verifier should be base64url encoded from 32 random bytes
        #expect(pkce.codeVerifier.count >= 43)
        
        // Challenge should be base64url encoded SHA256 (43 chars)
        #expect(pkce.codeChallenge.count >= 32)
        
        // Method should be S256
        #expect(pkce.codeChallengeMethod == "S256")
    }
    
    @Test("PKCE pairs are unique")
    func pkcePairsAreUnique() {
        let pkce1 = PKCEPair.generate()
        let pkce2 = PKCEPair.generate()
        
        #expect(pkce1.codeVerifier != pkce2.codeVerifier)
        #expect(pkce1.codeChallenge != pkce2.codeChallenge)
    }
    
    @Test("PKCE verifier is base64URL")
    func pkceVerifierIsBase64URL() {
        let pkce = PKCEPair.generate()
        
        // Base64URL should not contain + / =
        #expect(!pkce.codeVerifier.contains("+"))
        #expect(!pkce.codeVerifier.contains("/"))
        #expect(!pkce.codeVerifier.contains("="))
    }
    
    @Test("PKCE challenge is base64URL")
    func pkceChallengeIsBase64URL() {
        let pkce = PKCEPair.generate()
        
        // Base64URL should not contain + / =
        #expect(!pkce.codeChallenge.contains("+"))
        #expect(!pkce.codeChallenge.contains("/"))
        #expect(!pkce.codeChallenge.contains("="))
    }
    
    @Test("PKCE verifier and challenge are different")
    func pkceVerifierAndChallengeAreDifferent() {
        let pkce = PKCEPair.generate()
        
        // Verifier and challenge should be different (challenge is hash of verifier)
        #expect(pkce.codeVerifier != pkce.codeChallenge)
    }
}

// MARK: - OIDC Auth State Tests

@Suite("OIDC Auth State Tests")
struct OIDCAuthStateTests {
    
    @Test("Auth state generation")
    func authStateGeneration() {
        let (authState, pkce) = OIDCAuthState.generate(withPKCE: true)
        
        #expect(authState.state.count == 32)
        #expect(authState.nonce.count == 32)
        #expect(authState.codeVerifier != nil)
        #expect(pkce != nil)
    }
    
    @Test("Auth state without PKCE")
    func authStateWithoutPKCE() {
        let (authState, pkce) = OIDCAuthState.generate(withPKCE: false)
        
        #expect(authState.state.count == 32)
        #expect(authState.nonce.count == 32)
        #expect(authState.codeVerifier == nil)
        #expect(pkce == nil)
    }
    
    @Test("Auth state not expired immediately")
    func authStateNotExpiredImmediately() {
        let (authState, _) = OIDCAuthState.generate(withPKCE: true)
        
        #expect(!authState.isExpired)
    }
    
    @Test("Auth state unique each time")
    func authStateUniqueEachTime() {
        let (state1, _) = OIDCAuthState.generate(withPKCE: true)
        let (state2, _) = OIDCAuthState.generate(withPKCE: true)
        
        #expect(state1.state != state2.state)
        #expect(state1.nonce != state2.nonce)
    }
}

// MARK: - OIDC Configuration Tests

@Suite("OIDC Configuration Tests")
struct OIDCConfigurationTests {
    
    @Test("T1Pal default configuration")
    func t1PalDefaultConfiguration() {
        let config = OIDCConfiguration.t1pal
        
        #expect(config.issuer == "https://auth.t1pal.com")
        #expect(config.scopesSupported.contains("openid"))
        #expect(config.scopesSupported.contains("nightscout"))
        #expect(config.scopesSupported.contains("offline_access"))
        #expect(config.grantTypesSupported.contains("authorization_code"))
        #expect(config.grantTypesSupported.contains("refresh_token"))
    }
    
    @Test("OIDC configuration endpoints")
    func oidcConfigurationEndpoints() {
        let config = OIDCConfiguration.t1pal
        
        #expect(config.authorizationEndpoint.absoluteString.contains("authorize"))
        #expect(config.tokenEndpoint.absoluteString.contains("token"))
        #expect(config.userInfoEndpoint.absoluteString.contains("userinfo"))
        #expect(config.endSessionEndpoint != nil)
    }
    
    @Test("Custom OIDC configuration")
    func customOIDCConfiguration() {
        let config = OIDCConfiguration(
            authorizationEndpoint: URL(string: "https://custom.example.com/authorize")!,
            tokenEndpoint: URL(string: "https://custom.example.com/token")!,
            userInfoEndpoint: URL(string: "https://custom.example.com/userinfo")!,
            jwksUri: URL(string: "https://custom.example.com/.well-known/jwks.json")!,
            issuer: "https://custom.example.com"
        )
        
        #expect(config.issuer == "https://custom.example.com")
        #expect(config.endSessionEndpoint == nil)
    }
}

// MARK: - OIDC Client Config Tests

@Suite("OIDC Client Config Tests")
struct OIDCClientConfigTests {
    
    @Test("Public client config")
    func publicClientConfig() {
        let config = OIDCClientConfig(
            clientId: "t1pal-mobile",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        #expect(config.clientId == "t1pal-mobile")
        #expect(config.clientSecret == nil)  // Public client
        #expect(config.usePKCE)  // Default true
        #expect(config.scopes.contains("openid"))
        #expect(config.scopes.contains("offline_access"))
    }
    
    @Test("Confidential client config")
    func confidentialClientConfig() {
        let config = OIDCClientConfig(
            clientId: "backend-service",
            clientSecret: "super-secret",
            redirectUri: URL(string: "https://backend.example.com/callback")!,
            usePKCE: false
        )
        
        #expect(config.clientSecret == "super-secret")
        #expect(!config.usePKCE)
    }
    
    @Test("Custom scopes")
    func customScopes() {
        let config = OIDCClientConfig(
            clientId: "custom-app",
            redirectUri: URL(string: "custom://auth")!,
            scopes: ["openid", "profile", "nightscout", "custom:scope"]
        )
        
        #expect(config.scopes.count == 4)
        #expect(config.scopes.contains("custom:scope"))
    }
}

// MARK: - OIDC Token Response Tests

@Suite("OIDC Token Response Tests")
struct OIDCTokenResponseTests {
    
    @Test("Token response decoding")
    func tokenResponseDecoding() throws {
        let json = """
        {
            "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9",
            "token_type": "Bearer",
            "expires_in": 3600,
            "refresh_token": "refresh_token_value",
            "id_token": "id_token_jwt",
            "scope": "openid profile email"
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
        
        #expect(response.accessToken == "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9")
        #expect(response.tokenType == "Bearer")
        #expect(response.expiresIn == 3600)
        #expect(response.refreshToken == "refresh_token_value")
        #expect(response.idToken == "id_token_jwt")
        #expect(response.scope == "openid profile email")
    }
    
    @Test("Minimal token response")
    func minimalTokenResponse() throws {
        let json = """
        {
            "access_token": "token123",
            "token_type": "Bearer"
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
        
        #expect(response.accessToken == "token123")
        #expect(response.expiresIn == nil)
        #expect(response.refreshToken == nil)
        #expect(response.idToken == nil)
    }
}

// MARK: - OIDC User Info Tests

@Suite("OIDC User Info Tests")
struct OIDCUserInfoTests {
    
    @Test("User info decoding")
    func userInfoDecoding() throws {
        let json = """
        {
            "sub": "user-123",
            "name": "John Doe",
            "given_name": "John",
            "family_name": "Doe",
            "email": "john@example.com",
            "email_verified": true,
            "picture": "https://example.com/avatar.jpg",
            "locale": "en-US"
        }
        """
        
        let data = json.data(using: .utf8)!
        let userInfo = try JSONDecoder().decode(OIDCUserInfo.self, from: data)
        
        #expect(userInfo.sub == "user-123")
        #expect(userInfo.name == "John Doe")
        #expect(userInfo.givenName == "John")
        #expect(userInfo.familyName == "Doe")
        #expect(userInfo.email == "john@example.com")
        #expect(userInfo.emailVerified ?? false)
    }
    
    @Test("Minimal user info")
    func minimalUserInfo() throws {
        let json = """
        {
            "sub": "minimal-user"
        }
        """
        
        let data = json.data(using: .utf8)!
        let userInfo = try JSONDecoder().decode(OIDCUserInfo.self, from: data)
        
        #expect(userInfo.sub == "minimal-user")
        #expect(userInfo.name == nil)
        #expect(userInfo.email == nil)
    }
}

// MARK: - T1PalIdentityProvider Tests

@Suite("T1Pal Identity Provider Tests")
struct T1PalIdentityProviderTests {
    
    func createProvider() -> T1PalIdentityProvider {
        let clientConfig = OIDCClientConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        return T1PalIdentityProvider(clientConfig: clientConfig)
    }
    
    @Test("Provider metadata")
    func providerMetadata() async {
        let provider = createProvider()
        #expect(provider.providerType == .t1pal)
        #expect(provider.displayName == "T1Pal")
        #expect(provider.supportedAuthMethods.contains(.oidc))
    }
    
    @Test("Initially not authenticated")
    func initiallyNotAuthenticated() async {
        let provider = createProvider()
        let isAuth = await provider.isAuthenticated()
        #expect(!isAuth)
    }
    
    @Test("No credential when not authenticated")
    func noCredentialWhenNotAuthenticated() async {
        let provider = createProvider()
        let credential = await provider.getCredential()
        #expect(credential == nil)
    }
    
    @Test("Build authorization URL")
    func buildAuthorizationURL() async throws {
        let provider = createProvider()
        let (url, authState) = try await provider.buildAuthorizationURL()
        
        // URL should contain required parameters
        let urlString = url.absoluteString
        #expect(urlString.contains("client_id=test-client"))
        #expect(urlString.contains("redirect_uri="))
        #expect(urlString.contains("response_type=code"))
        #expect(urlString.contains("scope="))
        #expect(urlString.contains("state="))
        #expect(urlString.contains("nonce="))
        #expect(urlString.contains("code_challenge="))
        #expect(urlString.contains("code_challenge_method=S256"))
        
        // Auth state should be valid
        #expect(!authState.isExpired)
        #expect(authState.codeVerifier != nil)
    }
    
    @Test("Sign out")
    func signOut() async {
        let provider = createProvider()
        await provider.signOut()
        
        let isAuth = await provider.isAuthenticated()
        let credential = await provider.getCredential()
        
        #expect(!isAuth)
        #expect(credential == nil)
    }
    
    @Test("Authentication requires code")
    func authenticationRequiresCode() async {
        let provider = createProvider()
        do {
            _ = try await provider.authenticate(method: .oidc, parameters: [:])
            Issue.record("Expected error for missing code")
        } catch {
            #expect(error is IdentityError)
        }
    }
    
    @Test("Authentication requires state")
    func authenticationRequiresState() async {
        let provider = createProvider()
        do {
            _ = try await provider.authenticate(method: .oidc, parameters: ["code": "test"])
            Issue.record("Expected error for missing state")
        } catch {
            #expect(error is IdentityError)
        }
    }
    
    @Test("Authentication requires pending state")
    func authenticationRequiresPendingState() async {
        let provider = createProvider()
        do {
            _ = try await provider.authenticate(method: .oidc, parameters: [
                "code": "test-code",
                "state": "random-state"
            ])
            Issue.record("Expected error for no pending authorization")
        } catch {
            #expect(error is IdentityError)
        }
    }
}
