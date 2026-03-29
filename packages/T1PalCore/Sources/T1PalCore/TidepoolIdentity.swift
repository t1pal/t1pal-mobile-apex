// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TidepoolIdentity.swift
// T1PalCore
//
// Tidepool identity provider types and authentication
// Extracted from T1PalCore.swift (CORE-REFACTOR-001)
// Requirements: REQ-ID-004

import Foundation

// MARK: - Tidepool Identity (ID-004)

/// Tidepool environment configuration
/// Requirements: REQ-ID-001
public enum TidepoolEnvironment: String, Codable, Sendable, CaseIterable {
    case production = "production"
    case qa1 = "qa1"
    case qa2 = "qa2"
    case dev = "dev"
    case local = "local"
    
    public var apiUrl: URL {
        switch self {
        case .production:
            return URL(string: "https://api.tidepool.org")!
        case .qa1:
            return URL(string: "https://qa1.development.tidepool.org")!
        case .qa2:
            return URL(string: "https://qa2.development.tidepool.org")!
        case .dev:
            return URL(string: "https://dev.development.tidepool.org")!
        case .local:
            return URL(string: "http://localhost:8009")!
        }
    }
    
    public var uploadUrl: URL {
        switch self {
        case .production:
            return URL(string: "https://uploads.tidepool.org")!
        case .qa1:
            return URL(string: "https://qa1.development.tidepool.org")!
        case .qa2:
            return URL(string: "https://qa2.development.tidepool.org")!
        case .dev:
            return URL(string: "https://dev.development.tidepool.org")!
        case .local:
            return URL(string: "http://localhost:9122")!
        }
    }
    
    public var authUrl: URL {
        apiUrl.appendingPathComponent("auth")
    }
}

/// Tidepool OAuth configuration
/// Requirements: REQ-ID-004
public struct TidepoolConfig: Codable, Sendable {
    public let environment: TidepoolEnvironment
    public let clientId: String
    public let redirectUri: URL
    public let scope: String
    
    public init(
        environment: TidepoolEnvironment = .production,
        clientId: String,
        redirectUri: URL,
        scope: String = "openid profile offline_access"
    ) {
        self.environment = environment
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.scope = scope
    }
    
    /// Convert to generic OAuth2Config
    public func toOAuth2Config() -> OAuth2Config {
        OAuth2Config(
            authorizationEndpoint: environment.authUrl.appendingPathComponent("oauth2/authorize"),
            tokenEndpoint: environment.authUrl.appendingPathComponent("oauth2/token"),
            clientId: clientId,
            redirectUri: redirectUri,
            scope: scope
        )
    }
}

/// Tidepool user session
/// Requirements: REQ-ID-004
public struct TidepoolSession: Codable, Sendable {
    public let userId: String
    public let token: String
    public let serverTime: Date?
    public let expiresIn: Int?
    
    public init(
        userId: String,
        token: String,
        serverTime: Date? = nil,
        expiresIn: Int? = nil
    ) {
        self.userId = userId
        self.token = token
        self.serverTime = serverTime
        self.expiresIn = expiresIn
    }
    
    /// Calculate expiration date
    public var expiresAt: Date? {
        guard let expiresIn = expiresIn else { return nil }
        let base = serverTime ?? Date()
        return base.addingTimeInterval(TimeInterval(expiresIn))
    }
    
    /// Convert to AuthCredential
    public func toCredential() -> AuthCredential {
        AuthCredential(
            tokenType: .access,
            value: token,
            expiresAt: expiresAt
        )
    }
}

/// Tidepool user profile
/// Requirements: REQ-ID-004
public struct TidepoolProfile: Codable, Sendable {
    public let userid: String
    public let username: String?
    public let emails: [String]?
    public let emailVerified: Bool?
    public let termsAccepted: String?
    public let profile: TidepoolProfileData?
    
    public init(
        userid: String,
        username: String? = nil,
        emails: [String]? = nil,
        emailVerified: Bool? = nil,
        termsAccepted: String? = nil,
        profile: TidepoolProfileData? = nil
    ) {
        self.userid = userid
        self.username = username
        self.emails = emails
        self.emailVerified = emailVerified
        self.termsAccepted = termsAccepted
        self.profile = profile
    }
    
    /// Convert to UserIdentity
    public func toUserIdentity() -> UserIdentity {
        UserIdentity(
            id: userid,
            provider: .tidepool,
            displayName: profile?.fullName,
            email: emails?.first
        )
    }
}

/// Tidepool profile details
/// Requirements: REQ-ID-004
public struct TidepoolProfileData: Codable, Sendable {
    public let fullName: String?
    public let patient: TidepoolPatientData?
    
    public init(fullName: String? = nil, patient: TidepoolPatientData? = nil) {
        self.fullName = fullName
        self.patient = patient
    }
}

/// Tidepool patient information
/// Requirements: REQ-ID-004
public struct TidepoolPatientData: Codable, Sendable {
    public let birthday: String?
    public let diagnosisDate: String?
    public let diagnosisType: String?
    public let targetDevices: [String]?
    public let targetTimezone: String?
    
    public init(
        birthday: String? = nil,
        diagnosisDate: String? = nil,
        diagnosisType: String? = nil,
        targetDevices: [String]? = nil,
        targetTimezone: String? = nil
    ) {
        self.birthday = birthday
        self.diagnosisDate = diagnosisDate
        self.diagnosisType = diagnosisType
        self.targetDevices = targetDevices
        self.targetTimezone = targetTimezone
    }
}

/// Tidepool-specific errors
/// Requirements: REQ-ID-004
public enum TidepoolError: Error, Sendable {
    case invalidCredentials
    case sessionExpired
    case networkError(String)
    case rateLimited
    case serverError(Int)
    case userNotFound
    case accessDenied
    case invalidResponse
}

/// Tidepool API helper for basic auth operations
/// Requirements: REQ-ID-004
public actor TidepoolAuth {
    private let config: TidepoolConfig
    private var currentSession: TidepoolSession?
    
    public init(config: TidepoolConfig) {
        self.config = config
    }
    
    /// Get current session if valid
    public func getCurrentSession() -> TidepoolSession? {
        guard let session = currentSession else { return nil }
        if let expiresAt = session.expiresAt, Date() >= expiresAt {
            return nil  // Session expired
        }
        return session
    }
    
    /// Store a session from OAuth callback
    public func setSession(_ session: TidepoolSession) {
        currentSession = session
    }
    
    /// Clear current session
    public func clearSession() {
        currentSession = nil
    }
    
    /// Create credential key for storage
    public func credentialKey(userId: String) -> CredentialKey {
        CredentialKey.oauth2(provider: .tidepool, userId: userId)
    }
    
    /// Get API URL for current environment
    public var apiUrl: URL {
        config.environment.apiUrl
    }
    
    /// Get OAuth2 configuration
    public var oauth2Config: OAuth2Config {
        config.toOAuth2Config()
    }
    
    /// Build authorization URL with state
    public func buildAuthorizationUrl(state: String) -> URL {
        let oauth = config.toOAuth2Config()
        var components = URLComponents(url: oauth.authorizationEndpoint, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: oauth.clientId),
            URLQueryItem(name: "redirect_uri", value: oauth.redirectUri.absoluteString),
            URLQueryItem(name: "scope", value: oauth.scope),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }
}

/// Tidepool data types for API responses
/// Requirements: REQ-ID-004
public struct TidepoolDataSet: Codable, Sendable, Identifiable {
    public let id: String
    public let uploadId: String?
    public let userId: String
    public let client: TidepoolClientInfo?
    public let dataSetType: String?
    public let deviceId: String?
    public let deviceManufacturers: [String]?
    public let deviceModel: String?
    public let deviceSerialNumber: String?
    public let deviceTags: [String]?
    public let time: String?
    public let timezone: String?
    public let createdTime: String?
    public let modifiedTime: String?
    
    public init(
        id: String,
        uploadId: String? = nil,
        userId: String,
        client: TidepoolClientInfo? = nil,
        dataSetType: String? = nil,
        deviceId: String? = nil,
        deviceManufacturers: [String]? = nil,
        deviceModel: String? = nil,
        deviceSerialNumber: String? = nil,
        deviceTags: [String]? = nil,
        time: String? = nil,
        timezone: String? = nil,
        createdTime: String? = nil,
        modifiedTime: String? = nil
    ) {
        self.id = id
        self.uploadId = uploadId
        self.userId = userId
        self.client = client
        self.dataSetType = dataSetType
        self.deviceId = deviceId
        self.deviceManufacturers = deviceManufacturers
        self.deviceModel = deviceModel
        self.deviceSerialNumber = deviceSerialNumber
        self.deviceTags = deviceTags
        self.time = time
        self.timezone = timezone
        self.createdTime = createdTime
        self.modifiedTime = modifiedTime
    }
}

/// Tidepool client info for uploads
/// Requirements: REQ-ID-004
public struct TidepoolClientInfo: Codable, Sendable {
    public let name: String
    public let version: String
    public let platform: String?
    
    public init(name: String, version: String, platform: String? = nil) {
        self.name = name
        self.version = version
        self.platform = platform
    }
    
    /// Default T1Pal client info
    public static var t1pal: TidepoolClientInfo {
        TidepoolClientInfo(
            name: "T1Pal Mobile",
            version: "1.0.0",
            platform: "iOS"
        )
    }
}
