// SPDX-License-Identifier: AGPL-3.0-or-later
//
// JWTTokenManager.swift
// NightscoutKit
//
// JWT token handling and Nightscout authentication management
// Extracted from NightscoutClient.swift (NS-REFACTOR-012)
// Requirements: REQ-ID-005, REQ-AUTH-002

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Nightscout Auth Mode

/// Nightscout authentication mode
/// Requirements: REQ-ID-005
public enum NightscoutAuthMode: String, Codable, Sendable {
    case apiSecret = "api_secret"   // Hashed API secret
    case jwtToken = "jwt"           // Bearer token (JWT)
    case none = "none"              // No auth (read-only if server allows)
}

// MARK: - JWT Claims

/// Nightscout JWT token claims
/// Requirements: REQ-ID-005
public struct NightscoutJWTClaims: Codable, Sendable {
    public let accessToken: String?
    public let iat: Int?  // Issued at (Unix timestamp)
    public let exp: Int?  // Expiration (Unix timestamp)
    public let sub: String?  // Subject (usually permissions)
    
    public init(
        accessToken: String? = nil,
        iat: Int? = nil,
        exp: Int? = nil,
        sub: String? = nil
    ) {
        self.accessToken = accessToken
        self.iat = iat
        self.exp = exp
        self.sub = sub
    }
    
    /// Check if token is expired
    public var isExpired: Bool {
        guard let exp = exp else { return false }
        return Date().timeIntervalSince1970 >= Double(exp)
    }
    
    /// Get expiration date
    public var expiresAt: Date? {
        guard let exp = exp else { return nil }
        return Date(timeIntervalSince1970: Double(exp))
    }
}

// MARK: - JWT Decoder

/// JWT token decoder for Nightscout tokens
/// Requirements: REQ-AUTH-002
public enum JWTDecoder {
    
    /// JWT decoding errors
    public enum JWTError: Error, Sendable {
        case invalidFormat
        case invalidBase64
        case invalidPayload
        case decodingFailed
    }
    
    /// Decode a JWT token and extract claims
    /// - Parameter token: The JWT token string (format: header.payload.signature)
    /// - Returns: Decoded JWT claims
    public static func decode(_ token: String) throws -> NightscoutJWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw JWTError.invalidFormat
        }
        
        let payloadBase64 = String(parts[1])
        guard let payloadData = base64URLDecode(payloadBase64) else {
            throw JWTError.invalidBase64
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(NightscoutJWTClaims.self, from: payloadData)
        } catch {
            throw JWTError.decodingFailed
        }
    }
    
    /// Decode base64URL encoded string (JWT uses URL-safe base64)
    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
}

// MARK: - JWT Token Manager

/// Manages JWT token lifecycle with automatic refresh
/// Requirements: REQ-AUTH-002
public actor JWTTokenManager {
    
    /// Token refresh callback type
    public typealias RefreshCallback = @Sendable () async throws -> String
    
    /// Current token
    private var token: String?
    
    /// Decoded claims from current token
    private var claims: NightscoutJWTClaims?
    
    /// Callback to refresh the token
    private let refreshCallback: RefreshCallback?
    
    /// Refresh margin in seconds (refresh before expiry)
    private let refreshMargin: TimeInterval
    
    /// Last refresh attempt timestamp
    private var lastRefreshAttempt: Date?
    
    /// Minimum interval between refresh attempts (backoff)
    private let minRefreshInterval: TimeInterval = 30
    
    /// Initialize token manager
    /// - Parameters:
    ///   - token: Initial JWT token (optional)
    ///   - refreshMargin: Seconds before expiry to trigger refresh (default: 300 = 5 min)
    ///   - refreshCallback: Async callback to obtain a new token
    public init(
        token: String? = nil,
        refreshMargin: TimeInterval = 300,
        refreshCallback: RefreshCallback? = nil
    ) {
        self.refreshMargin = refreshMargin
        self.refreshCallback = refreshCallback
        if let token = token {
            // Decode token directly in init to avoid actor isolation issue
            if let decoded = try? JWTDecoder.decode(token) {
                self.token = token
                self.claims = decoded
            }
        }
    }
    
    /// Set a new token
    /// - Parameter token: JWT token string
    /// - Returns: Decoded claims
    @discardableResult
    public func setToken(_ token: String) throws -> NightscoutJWTClaims {
        let decoded = try JWTDecoder.decode(token)
        self.token = token
        self.claims = decoded
        return decoded
    }
    
    /// Get the current valid token, refreshing if needed
    /// - Returns: Valid JWT token or nil if unavailable
    public func getValidToken() async -> String? {
        // No token set
        guard let currentToken = token, let claims = claims else {
            return nil
        }
        
        // Check if refresh is needed
        if shouldRefresh(claims: claims) {
            // Attempt refresh if callback available
            if let refreshCallback = refreshCallback {
                // Backoff check
                if let lastAttempt = lastRefreshAttempt,
                   Date().timeIntervalSince(lastAttempt) < minRefreshInterval {
                    // Too soon, return current token if not expired
                    return claims.isExpired ? nil : currentToken
                }
                
                lastRefreshAttempt = Date()
                
                do {
                    let newToken = try await refreshCallback()
                    try setToken(newToken)
                    return self.token
                } catch {
                    // Refresh failed, return current if not expired
                    return claims.isExpired ? nil : currentToken
                }
            }
        }
        
        // Return current token if not expired
        return claims.isExpired ? nil : currentToken
    }
    
    /// Check if token needs refresh
    public func needsRefresh() -> Bool {
        guard let claims = claims else { return true }
        return shouldRefresh(claims: claims)
    }
    
    /// Check if token is expired
    public func isExpired() -> Bool {
        claims?.isExpired ?? true
    }
    
    /// Get current claims
    public func getClaims() -> NightscoutJWTClaims? {
        claims
    }
    
    /// Get expiration date
    public func expiresAt() -> Date? {
        claims?.expiresAt
    }
    
    /// Clear token
    public func clear() {
        token = nil
        claims = nil
        lastRefreshAttempt = nil
    }
    
    /// Check if token should be refreshed based on expiry margin
    private func shouldRefresh(claims: NightscoutJWTClaims) -> Bool {
        guard let exp = claims.exp else { return false }
        let expiryDate = Date(timeIntervalSince1970: Double(exp))
        let refreshThreshold = expiryDate.addingTimeInterval(-refreshMargin)
        return Date() >= refreshThreshold
    }
}

// MARK: - Nightscout Permissions

/// Nightscout permission set
/// Requirements: REQ-ID-005
public struct NightscoutPermissions: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let readable = NightscoutPermissions(rawValue: 1 << 0)
    public static let apiRead = NightscoutPermissions(rawValue: 1 << 1)
    public static let apiCreate = NightscoutPermissions(rawValue: 1 << 2)
    public static let apiUpdate = NightscoutPermissions(rawValue: 1 << 3)
    public static let apiDelete = NightscoutPermissions(rawValue: 1 << 4)
    public static let careportal = NightscoutPermissions(rawValue: 1 << 5)
    public static let admin = NightscoutPermissions(rawValue: 1 << 6)
    
    public static let all: NightscoutPermissions = [.readable, .apiRead, .apiCreate, .apiUpdate, .apiDelete, .careportal, .admin]
    public static let readOnly: NightscoutPermissions = [.readable, .apiRead]
    public static let readWrite: NightscoutPermissions = [.readable, .apiRead, .apiCreate, .apiUpdate]
    
    /// Parse from permission strings
    public static func from(strings: [String]) -> NightscoutPermissions {
        var permissions: NightscoutPermissions = []
        
        for perm in strings {
            switch perm.lowercased() {
            case "*", "admin":
                permissions.insert(.admin)
                permissions.insert(.all)
            case "readable":
                permissions.insert(.readable)
            case "api:*:read":
                permissions.insert(.apiRead)
            case "api:*:create":
                permissions.insert(.apiCreate)
            case "api:*:update":
                permissions.insert(.apiUpdate)
            case "api:*:delete":
                permissions.insert(.apiDelete)
            case "careportal":
                permissions.insert(.careportal)
            default:
                if perm.contains("read") {
                    permissions.insert(.apiRead)
                }
                if perm.contains("create") || perm.contains("write") {
                    permissions.insert(.apiCreate)
                }
            }
        }
        
        return permissions
    }
}

// MARK: - Nightscout Auth State

/// Nightscout authentication result
/// Requirements: REQ-ID-005
public struct NightscoutAuthState: Sendable {
    public let url: URL
    public let mode: NightscoutAuthMode
    public let isAuthenticated: Bool
    public let permissions: NightscoutPermissions
    public let serverName: String?
    public let expiresAt: Date?
    public let authenticatedAt: Date
    
    public init(
        url: URL,
        mode: NightscoutAuthMode,
        isAuthenticated: Bool = false,
        permissions: NightscoutPermissions = [],
        serverName: String? = nil,
        expiresAt: Date? = nil,
        authenticatedAt: Date = Date()
    ) {
        self.url = url
        self.mode = mode
        self.isAuthenticated = isAuthenticated
        self.permissions = permissions
        self.serverName = serverName
        self.expiresAt = expiresAt
        self.authenticatedAt = authenticatedAt
    }
    
    /// Check if auth is still valid
    public var isValid: Bool {
        guard isAuthenticated else { return false }
        if let expiresAt = expiresAt, Date() >= expiresAt {
            return false
        }
        return true
    }
    
    /// Can read data
    public var canRead: Bool {
        isValid && permissions.contains(.apiRead)
    }
    
    /// Can write data
    public var canWrite: Bool {
        isValid && permissions.contains(.apiCreate)
    }
}

// Note: NightscoutAuth actor and NightscoutClient.getStatusWithAuth() extension
// remain in NightscoutClient.swift due to dependencies on CredentialStoring (T1PalCore)
// and private NightscoutClient config access

