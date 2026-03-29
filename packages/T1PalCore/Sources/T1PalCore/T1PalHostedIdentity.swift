// SPDX-License-Identifier: AGPL-3.0-or-later
// T1PalHostedIdentity.swift - T1Pal Hosted Identity types
// Extracted from T1PalCore.swift (CORE-REFACTOR-002)
// Requirements: REQ-ID-001, REQ-ID-006

import Foundation

// MARK: - T1Pal Hosted Identity (ID-006)

/// T1Pal environment configuration
/// Requirements: REQ-ID-001, REQ-ID-006
public enum T1PalEnvironment: String, Codable, Sendable, CaseIterable {
    case production = "production"
    case staging = "staging"
    case development = "development"
    case local = "local"
    
    public var apiUrl: URL {
        switch self {
        case .production:
            return URL(string: "https://api.t1pal.com")!
        case .staging:
            return URL(string: "https://staging-api.t1pal.com")!
        case .development:
            return URL(string: "https://dev-api.t1pal.com")!
        case .local:
            return URL(string: "http://localhost:3000")!
        }
    }
    
    public var authUrl: URL {
        apiUrl.appendingPathComponent("auth")
    }
    
    public var nightscoutUrl: URL {
        switch self {
        case .production:
            return URL(string: "https://ns.t1pal.com")!
        case .staging:
            return URL(string: "https://staging-ns.t1pal.com")!
        case .development:
            return URL(string: "https://dev-ns.t1pal.com")!
        case .local:
            return URL(string: "http://localhost:1337")!
        }
    }
}

/// T1Pal OAuth configuration
/// Requirements: REQ-ID-006
public struct T1PalConfig: Codable, Sendable {
    public let environment: T1PalEnvironment
    public let clientId: String
    public let redirectUri: URL
    public let scope: String
    
    public init(
        environment: T1PalEnvironment = .production,
        clientId: String,
        redirectUri: URL,
        scope: String = "openid profile nightscout offline_access"
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

/// T1Pal user session
/// Requirements: REQ-ID-006
public struct T1PalSession: Codable, Sendable {
    public let userId: String
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let issuedAt: Date
    
    public init(
        userId: String,
        accessToken: String,
        refreshToken: String? = nil,
        expiresIn: Int? = nil,
        issuedAt: Date = Date()
    ) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.issuedAt = issuedAt
    }
    
    /// Calculate expiration date
    public var expiresAt: Date? {
        guard let expiresIn = expiresIn else { return nil }
        return issuedAt.addingTimeInterval(TimeInterval(expiresIn))
    }
    
    /// Check if session is expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    /// Check if session can be refreshed
    public var canRefresh: Bool {
        refreshToken != nil
    }
    
    /// Convert to AuthCredential
    public func toCredential() -> AuthCredential {
        AuthCredential(
            tokenType: .access,
            value: accessToken,
            expiresAt: expiresAt
        )
    }
}

/// T1Pal user profile
/// Requirements: REQ-ID-006
public struct T1PalProfile: Codable, Sendable {
    public let userId: String
    public let email: String
    public let displayName: String?
    public let verified: Bool
    public let createdAt: Date?
    public let subscription: T1PalSubscription?
    
    public init(
        userId: String,
        email: String,
        displayName: String? = nil,
        verified: Bool = false,
        createdAt: Date? = nil,
        subscription: T1PalSubscription? = nil
    ) {
        self.userId = userId
        self.email = email
        self.displayName = displayName
        self.verified = verified
        self.createdAt = createdAt
        self.subscription = subscription
    }
    
    /// Convert to UserIdentity
    public func toUserIdentity() -> UserIdentity {
        UserIdentity(
            id: userId,
            provider: .t1pal,
            displayName: displayName,
            email: email
        )
    }
}

/// T1Pal subscription status
/// Requirements: REQ-ID-006
public struct T1PalSubscription: Codable, Sendable {
    public let plan: T1PalPlan
    public let status: T1PalSubscriptionStatus
    public let expiresAt: Date?
    public let nightscoutLimit: Int
    
    public init(
        plan: T1PalPlan,
        status: T1PalSubscriptionStatus,
        expiresAt: Date? = nil,
        nightscoutLimit: Int = 1
    ) {
        self.plan = plan
        self.status = status
        self.expiresAt = expiresAt
        self.nightscoutLimit = nightscoutLimit
    }
    
    /// Check if subscription is active
    public var isActive: Bool {
        switch status {
        case .active, .trialing:
            return true
        case .canceled, .expired, .pastDue:
            return false
        }
    }
}

/// T1Pal subscription plans
/// Requirements: REQ-ID-006
public enum T1PalPlan: String, Codable, Sendable, CaseIterable {
    case free = "free"
    case basic = "basic"
    case family = "family"
    case clinic = "clinic"
    
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .family: return "Family"
        case .clinic: return "Clinic"
        }
    }
    
    public var nightscoutLimit: Int {
        switch self {
        case .free: return 1
        case .basic: return 1
        case .family: return 5
        case .clinic: return 50
        }
    }
}

/// T1Pal subscription status
/// Requirements: REQ-ID-006
public enum T1PalSubscriptionStatus: String, Codable, Sendable {
    case active = "active"
    case trialing = "trialing"
    case pastDue = "past_due"
    case canceled = "canceled"
    case expired = "expired"
}

/// T1Pal Nightscout instance information
/// Requirements: REQ-ID-006
public struct T1PalInstance: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String
    public let subdomain: String
    public let displayName: String?
    public let status: T1PalInstanceStatus
    public let createdAt: Date
    public let apiSecret: String?
    
    public init(
        id: String,
        userId: String,
        subdomain: String,
        displayName: String? = nil,
        status: T1PalInstanceStatus = .provisioning,
        createdAt: Date = Date(),
        apiSecret: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.subdomain = subdomain
        self.displayName = displayName
        self.status = status
        self.createdAt = createdAt
        self.apiSecret = apiSecret
    }
    
    /// Full Nightscout URL for this instance
    public func nightscoutUrl(environment: T1PalEnvironment = .production) -> URL {
        switch environment {
        case .production:
            return URL(string: "https://\(subdomain).ns.t1pal.com")!
        case .staging:
            return URL(string: "https://\(subdomain).staging-ns.t1pal.com")!
        case .development:
            return URL(string: "https://\(subdomain).dev-ns.t1pal.com")!
        case .local:
            return URL(string: "http://\(subdomain).localhost:1337")!
        }
    }
    
    /// Convert to NightscoutInstance
    public func toNightscoutInstance(environment: T1PalEnvironment = .production) -> NightscoutInstance {
        NightscoutInstance(
            url: nightscoutUrl(environment: environment),
            name: displayName ?? subdomain,
            authMethod: apiSecret != nil ? .apiSecret : .bearerToken
        )
    }
}

/// T1Pal instance provisioning status
/// Requirements: REQ-ID-006
public enum T1PalInstanceStatus: String, Codable, Sendable {
    case provisioning = "provisioning"
    case active = "active"
    case suspended = "suspended"
    case deleted = "deleted"
    
    public var isUsable: Bool {
        self == .active
    }
}

/// T1Pal instance provisioning request
/// Requirements: REQ-ID-006
public struct T1PalProvisionRequest: Codable, Sendable {
    public let subdomain: String
    public let displayName: String?
    public let units: String?
    public let timezone: String?
    
    public init(
        subdomain: String,
        displayName: String? = nil,
        units: String? = "mg/dl",
        timezone: String? = nil
    ) {
        self.subdomain = subdomain
        self.displayName = displayName
        self.units = units
        self.timezone = timezone
    }
    
    /// Validate subdomain format
    public var isValidSubdomain: Bool {
        let pattern = "^[a-z][a-z0-9-]{2,29}$"
        return subdomain.range(of: pattern, options: .regularExpression) != nil
    }
}

/// T1Pal-specific errors
/// Requirements: REQ-ID-006
public enum T1PalError: Error, Sendable, LocalizedError {
    case invalidCredentials
    case sessionExpired
    case refreshFailed
    case networkError(String)
    case rateLimited
    case serverError(Int)
    case subscriptionRequired
    case instanceLimitReached
    case subdomainTaken
    case subdomainInvalid
    case instanceNotFound
    case provisioningFailed(String)
    case accessDenied
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials"
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .refreshFailed:
            return "Failed to refresh session"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .serverError(let code):
            return "Server error (code \(code))"
        case .subscriptionRequired:
            return "A subscription is required to use this feature"
        case .instanceLimitReached:
            return "Maximum number of Nightscout instances reached"
        case .subdomainTaken:
            return "This subdomain is already taken"
        case .subdomainInvalid:
            return "Invalid subdomain format"
        case .instanceNotFound:
            return "Nightscout instance not found"
        case .provisioningFailed(let reason):
            return "Failed to create instance: \(reason)"
        case .accessDenied:
            return "Access denied"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

/// T1Pal API helper for auth and instance operations
/// Requirements: REQ-ID-006
public actor T1PalAuth {
    private let config: T1PalConfig
    private var currentSession: T1PalSession?
    private var cachedProfile: T1PalProfile?
    private var cachedInstances: [T1PalInstance] = []
    
    public init(config: T1PalConfig) {
        self.config = config
    }
    
    /// Get current session if valid
    public func getCurrentSession() -> T1PalSession? {
        guard let session = currentSession else { return nil }
        if session.isExpired {
            return nil  // Session expired
        }
        return session
    }
    
    /// Check if we have a valid session
    public var isAuthenticated: Bool {
        getCurrentSession() != nil
    }
    
    /// Store a session from OAuth callback
    public func setSession(_ session: T1PalSession) {
        currentSession = session
    }
    
    /// Clear current session
    public func clearSession() {
        currentSession = nil
        cachedProfile = nil
        cachedInstances = []
    }
    
    /// Get cached profile
    public func getProfile() -> T1PalProfile? {
        cachedProfile
    }
    
    /// Set profile from API response
    public func setProfile(_ profile: T1PalProfile) {
        cachedProfile = profile
    }
    
    /// Get cached instances
    public func getInstances() -> [T1PalInstance] {
        cachedInstances
    }
    
    /// Set instances from API response
    public func setInstances(_ instances: [T1PalInstance]) {
        cachedInstances = instances
    }
    
    /// Add a newly provisioned instance
    public func addInstance(_ instance: T1PalInstance) {
        cachedInstances.append(instance)
    }
    
    /// Remove an instance
    public func removeInstance(id: String) {
        cachedInstances.removeAll { $0.id == id }
    }
    
    /// Create credential key for storage
    public func credentialKey(userId: String) -> CredentialKey {
        CredentialKey.oauth2(provider: .t1pal, userId: userId)
    }
    
    /// Get API URL for current environment
    public var apiUrl: URL {
        config.environment.apiUrl
    }
    
    /// Get OAuth2 configuration
    public var oauth2Config: OAuth2Config {
        config.toOAuth2Config()
    }
    
    /// Get environment
    public var environment: T1PalEnvironment {
        config.environment
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
    
    /// Check if user can provision more instances
    public func canProvisionInstance() -> Bool {
        guard let profile = cachedProfile,
              let subscription = profile.subscription else {
            return false
        }
        return subscription.isActive && cachedInstances.count < subscription.nightscoutLimit
    }
    
    /// Get active instances only
    public func getActiveInstances() -> [T1PalInstance] {
        cachedInstances.filter { $0.status.isUsable }
    }
}
