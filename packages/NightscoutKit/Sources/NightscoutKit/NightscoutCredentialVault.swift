// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutCredentialVault.swift
// T1Pal Mobile
//
// Secure credential storage for Nightscout authentication
// Requirements: PROD-KEYCHAIN-001, REQ-AUTH-001, REQ-AUTH-002

import Foundation
import T1PalCore

// MARK: - Credential Types

/// Nightscout credential type
public enum NightscoutCredentialType: String, Codable, Sendable {
    case apiSecret = "api_secret"
    case jwtToken = "jwt_token"
}

/// Stored Nightscout credentials for a server
public struct NightscoutCredentials: Codable, Sendable {
    public let url: URL
    public var apiSecret: String?
    public var jwtToken: String?
    public var tokenExpiresAt: Date?
    public var lastUpdated: Date
    
    public init(
        url: URL,
        apiSecret: String? = nil,
        jwtToken: String? = nil,
        tokenExpiresAt: Date? = nil,
        lastUpdated: Date = Date()
    ) {
        self.url = url
        self.apiSecret = apiSecret
        self.jwtToken = jwtToken
        self.tokenExpiresAt = tokenExpiresAt
        self.lastUpdated = lastUpdated
    }
    
    /// Check if any credentials are available
    public var hasCredentials: Bool {
        apiSecret != nil || jwtToken != nil
    }
    
    /// Check if JWT token is expired
    public var isTokenExpired: Bool {
        guard let expires = tokenExpiresAt else { return jwtToken == nil }
        return Date() >= expires
    }
    
    /// Preferred auth mode based on available credentials
    public var preferredAuthMode: NightscoutAuthMode {
        if jwtToken != nil && !isTokenExpired {
            return .jwtToken
        } else if apiSecret != nil {
            return .apiSecret
        }
        return .none
    }
}

// MARK: - Credential Vault

/// Secure credential vault for Nightscout servers
/// Requirements: PROD-KEYCHAIN-001
public actor NightscoutCredentialVault {
    
    /// Keychain helper instance
    private let keychain: KeychainHelper
    
    /// In-memory credential cache
    private var credentialCache: [String: NightscoutCredentials] = [:]
    
    /// JWT token managers per server
    private var tokenManagers: [String: JWTTokenManager] = [:]
    
    /// Initialize vault with keychain helper
    /// - Parameter keychain: Keychain helper (defaults to shared instance)
    public init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
    }
    
    // MARK: - API Secret Management
    
    /// Store API secret for a Nightscout server
    /// - Parameters:
    ///   - secret: The API secret
    ///   - url: Nightscout server URL
    /// - Returns: True if stored successfully
    @discardableResult
    public func storeAPISecret(_ secret: String, for url: URL) -> Bool {
        let urlKey = urlToKey(url)
        let success = keychain.saveNightscoutSecret(secret, forURL: urlKey)
        
        if success {
            updateCache(for: url) { creds in
                creds.apiSecret = secret
                creds.lastUpdated = Date()
            }
        }
        
        return success
    }
    
    /// Retrieve API secret for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: Stored API secret or nil
    public func getAPISecret(for url: URL) -> String? {
        let urlKey = urlToKey(url)
        
        // Check cache first
        if let cached = credentialCache[urlKey]?.apiSecret {
            return cached
        }
        
        // Load from keychain
        if let secret = keychain.loadNightscoutSecret(forURL: urlKey) {
            updateCache(for: url) { creds in
                creds.apiSecret = secret
            }
            return secret
        }
        
        return nil
    }
    
    /// Delete API secret for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: True if deleted successfully
    @discardableResult
    public func deleteAPISecret(for url: URL) -> Bool {
        let urlKey = urlToKey(url)
        let success = keychain.deleteNightscoutSecret(forURL: urlKey)
        
        if success {
            updateCache(for: url) { creds in
                creds.apiSecret = nil
                creds.lastUpdated = Date()
            }
        }
        
        return success
    }
    
    // MARK: - JWT Token Management
    
    /// Store JWT token for a Nightscout server
    /// - Parameters:
    ///   - token: The JWT token
    ///   - url: Nightscout server URL
    /// - Returns: True if stored successfully
    @discardableResult
    public func storeJWTToken(_ token: String, for url: URL) -> Bool {
        let urlKey = urlToKey(url)
        let success = keychain.saveNightscoutToken(token, forURL: urlKey)
        
        if success {
            // Decode token to get expiry
            var expiresAt: Date?
            if let claims = try? JWTDecoder.decode(token) {
                expiresAt = claims.expiresAt
            }
            
            updateCache(for: url) { creds in
                creds.jwtToken = token
                creds.tokenExpiresAt = expiresAt
                creds.lastUpdated = Date()
            }
            
            // Update token manager if exists
            if let manager = tokenManagers[urlKey] {
                Task {
                    try? await manager.setToken(token)
                }
            }
        }
        
        return success
    }
    
    /// Retrieve JWT token for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: Stored JWT token or nil (returns nil if expired)
    public func getJWTToken(for url: URL) -> String? {
        let urlKey = urlToKey(url)
        
        // Check cache first
        if let cached = credentialCache[urlKey],
           let token = cached.jwtToken,
           !cached.isTokenExpired {
            return token
        }
        
        // Load from keychain
        if let token = keychain.loadNightscoutToken(forURL: urlKey) {
            // Verify not expired
            if let claims = try? JWTDecoder.decode(token), !claims.isExpired {
                updateCache(for: url) { creds in
                    creds.jwtToken = token
                    creds.tokenExpiresAt = claims.expiresAt
                }
                return token
            } else {
                // Token expired, delete it
                _ = keychain.deleteNightscoutToken(forURL: urlKey)
            }
        }
        
        return nil
    }
    
    /// Delete JWT token for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: True if deleted successfully
    @discardableResult
    public func deleteJWTToken(for url: URL) -> Bool {
        let urlKey = urlToKey(url)
        let success = keychain.deleteNightscoutToken(forURL: urlKey)
        
        if success {
            updateCache(for: url) { creds in
                creds.jwtToken = nil
                creds.tokenExpiresAt = nil
                creds.lastUpdated = Date()
            }
            
            // Clear token manager
            if let manager = tokenManagers[urlKey] {
                Task { await manager.clear() }
            }
        }
        
        return success
    }
    
    // MARK: - Unified Credential Access
    
    /// Get credentials for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: Stored credentials (may be empty)
    public func getCredentials(for url: URL) -> NightscoutCredentials {
        let urlKey = urlToKey(url)
        
        // Return cached if available
        if let cached = credentialCache[urlKey] {
            return cached
        }
        
        // Load from keychain
        let apiSecret = keychain.loadNightscoutSecret(forURL: urlKey)
        let jwtToken = keychain.loadNightscoutToken(forURL: urlKey)
        
        var tokenExpiresAt: Date?
        if let token = jwtToken, let claims = try? JWTDecoder.decode(token) {
            tokenExpiresAt = claims.expiresAt
        }
        
        let credentials = NightscoutCredentials(
            url: url,
            apiSecret: apiSecret,
            jwtToken: jwtToken,
            tokenExpiresAt: tokenExpiresAt
        )
        
        credentialCache[urlKey] = credentials
        return credentials
    }
    
    /// Delete all credentials for a Nightscout server
    /// - Parameter url: Nightscout server URL
    /// - Returns: True if any credentials were deleted
    @discardableResult
    public func deleteAllCredentials(for url: URL) -> Bool {
        let urlKey = urlToKey(url)
        
        let deletedSecret = keychain.deleteNightscoutSecret(forURL: urlKey)
        let deletedToken = keychain.deleteNightscoutToken(forURL: urlKey)
        
        credentialCache.removeValue(forKey: urlKey)
        tokenManagers.removeValue(forKey: urlKey)
        
        return deletedSecret || deletedToken
    }
    
    /// List all stored Nightscout URLs
    /// - Returns: Array of URLs with stored credentials
    public func listStoredServers() -> [URL] {
        // Note: This is limited by keychain enumeration capabilities
        // In practice, maintain a separate list in UserDefaults
        credentialCache.values.map { $0.url }
    }
    
    /// Clear in-memory cache (credentials remain in keychain)
    public func clearCache() {
        credentialCache.removeAll()
        tokenManagers.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func urlToKey(_ url: URL) -> String {
        // Normalize URL for consistent key
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return (components?.string ?? url.absoluteString).lowercased()
    }
    
    private func updateCache(for url: URL, update: (inout NightscoutCredentials) -> Void) {
        let urlKey = urlToKey(url)
        var credentials = credentialCache[urlKey] ?? NightscoutCredentials(url: url)
        update(&credentials)
        credentialCache[urlKey] = credentials
    }
}
