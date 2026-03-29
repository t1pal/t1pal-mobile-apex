// SPDX-License-Identifier: AGPL-3.0-or-later
//
// T1PalCore.swift
// T1Pal Mobile
//
// Core types and utilities shared across all modules
// Requirements: Multiple PRDs (shared types)

import Foundation

/// Core glucose reading type
/// Requirements: REQ-CGM-002
public struct GlucoseReading: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let glucose: Double  // mg/dL
    public let timestamp: Date
    public let trend: GlucoseTrend
    public let source: String
    /// Sync identifier for deduplication across sources. (DATA-COHESIVE-001)
    public let syncIdentifier: String?
    
    public init(
        id: UUID = UUID(),
        glucose: Double,
        timestamp: Date = Date(),
        trend: GlucoseTrend = .flat,
        source: String = "unknown",
        syncIdentifier: String? = nil
    ) {
        self.id = id
        self.glucose = glucose
        self.timestamp = timestamp
        self.trend = trend
        self.source = source
        self.syncIdentifier = syncIdentifier
    }
    
    /// Glucose in mmol/L
    public var glucoseMmol: Double {
        glucose / 18.0182
    }
}

/// Glucose trend direction
/// Requirements: REQ-CGM-002
public enum GlucoseTrend: String, Codable, Sendable {
    case doubleUp = "DoubleUp"
    case singleUp = "SingleUp"
    case fortyFiveUp = "FortyFiveUp"
    case flat = "Flat"
    case fortyFiveDown = "FortyFiveDown"
    case singleDown = "SingleDown"
    case doubleDown = "DoubleDown"
    case notComputable = "NotComputable"
    case rateOutOfRange = "RateOutOfRange"
    
    /// Arrow symbol for display
    public var arrow: String {
        switch self {
        case .doubleUp: return "↑↑"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "↓↓"
        case .notComputable, .rateOutOfRange: return "?"
        }
    }
    
    /// Whether this trend is displayable (not unknown)
    /// VIS-CGM-001: Check if trend should show fallback
    public var isDisplayable: Bool {
        switch self {
        case .notComputable, .rateOutOfRange: return false
        default: return true
        }
    }
    
    /// VIS-CGM-001: Compute trend from rate of change (mg/dL per minute)
    /// Used as fallback when CGM trend is notComputable
    /// - Parameter rate: Rate of change in mg/dL per minute
    /// - Returns: Computed GlucoseTrend based on rate thresholds
    public static func fromRate(_ rate: Double) -> GlucoseTrend {
        // Standard CGM thresholds (mg/dL per minute)
        // DoubleUp: > 3 mg/dL/min
        // SingleUp: 2-3 mg/dL/min  
        // FortyFiveUp: 1-2 mg/dL/min
        // Flat: -1 to 1 mg/dL/min
        // FortyFiveDown: -2 to -1 mg/dL/min
        // SingleDown: -3 to -2 mg/dL/min
        // DoubleDown: < -3 mg/dL/min
        switch rate {
        case 3...: return .doubleUp
        case 2..<3: return .singleUp
        case 1..<2: return .fortyFiveUp
        case (-1)..<1: return .flat
        case (-2)..<(-1): return .fortyFiveDown
        case (-3)..<(-2): return .singleDown
        default: return .doubleDown  // rate < -3
        }
    }
    
    /// VIS-CGM-001: Get displayable trend, computing from rate if needed
    /// - Parameters:
    ///   - rate: Optional rate of change for fallback computation
    /// - Returns: Arrow string, computed from rate if trend is notComputable
    public func arrowWithFallback(rate: Double?) -> String {
        if isDisplayable {
            return arrow
        }
        guard let rate = rate else {
            return ""  // No arrow if no rate available (better than "?")
        }
        return GlucoseTrend.fromRate(rate).arrow
    }
    
    // A11Y-VO-001: Human-readable trend description for VoiceOver
    public var accessibilityDescription: String {
        switch self {
        case .doubleUp: return "rising rapidly"
        case .singleUp: return "rising"
        case .fortyFiveUp: return "rising slowly"
        case .flat: return "stable"
        case .fortyFiveDown: return "falling slowly"
        case .singleDown: return "falling"
        case .doubleDown: return "falling rapidly"
        case .notComputable, .rateOutOfRange: return "trend unknown"
        }
    }
}

/// Operation mode for foundational features (ARCH-007-006)
///
/// Foundational features must fail explicitly in `.live` mode.
/// Simulation/demo data is only permitted in `.demo` or `.simulation` modes.
///
/// - `.live`: Production mode. No fallbacks. Failures throw explicit errors.
/// - `.demo`: Demo/showcase mode. Uses demo data, clearly indicated to user.
/// - `.simulation`: Testing/development mode. Uses synthetic data for testing.
///
/// Requirements: ARCH-007 (fail-explicit principle)
public enum OperationMode: String, Codable, Sendable, CaseIterable {
    /// Production mode - no fallbacks, explicit failures
    case live
    /// Demo mode - uses demo data, clearly indicated
    case demo
    /// Simulation mode - synthetic data for testing
    case simulation
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .live: return "Live"
        case .demo: return "Demo"
        case .simulation: return "Simulation"
        }
    }
    
    /// Whether this mode permits simulated/demo data
    public var allowsSimulation: Bool {
        self != .live
    }
    
    /// Whether this mode requires real hardware connections
    public var requiresHardware: Bool {
        self == .live
    }
}

/// User profile for AID settings
/// Requirements: REQ-AID-007
public struct TherapyProfile: Codable, Sendable {
    public var basalRates: [BasalRate]
    public var carbRatios: [CarbRatio]
    public var sensitivityFactors: [SensitivityFactor]
    public var targetGlucose: TargetRange
    public var maxIOB: Double
    public var maxBolus: Double
    /// ALG-LIVE-064: Maximum basal rate the algorithm can recommend (U/hr)
    public var maxBasalRate: Double?
    /// ALG-LIVE-064: Suspend threshold - glucose below this suspends delivery (mg/dL)
    public var suspendThreshold: Double?
    /// ALG-LIVE-063: Dosing strategy ("tempBasalOnly" or "automaticBolus")
    public var dosingStrategy: String?
    /// NS-IOB-001b: Insulin model preset for IOB calculations
    /// Values: "rapidActingAdult" (default), "rapidActingChild", "fiasp", "lyumjev", "afrezza"
    public var insulinModel: String?
    
    public init(
        basalRates: [BasalRate] = [],
        carbRatios: [CarbRatio] = [],
        sensitivityFactors: [SensitivityFactor] = [],
        targetGlucose: TargetRange = TargetRange(low: 100, high: 110),
        maxIOB: Double = 0,
        maxBolus: Double = 0,
        maxBasalRate: Double? = nil,
        suspendThreshold: Double? = nil,
        dosingStrategy: String? = nil,
        insulinModel: String? = nil
    ) {
        self.basalRates = basalRates
        self.carbRatios = carbRatios
        self.sensitivityFactors = sensitivityFactors
        self.targetGlucose = targetGlucose
        self.maxIOB = maxIOB
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.suspendThreshold = suspendThreshold
        self.dosingStrategy = dosingStrategy
        self.insulinModel = insulinModel
    }
    
    /// AID-LOOP-001: Default therapy profile for fallback
    public static let `default` = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120),
        maxIOB: 10.0,
        maxBolus: 10.0
    )
    
    /// ALG-LIVE-063: Whether automatic bolus is enabled
    public var isAutomaticBolus: Bool {
        dosingStrategy == "automaticBolus"
    }
    
    /// CRIT-BOLUS-006: Get current carb ratio for the current time of day
    /// Returns the ratio (grams per unit) active at the current time
    public var currentCarbRatio: Double {
        carbRatioAt(Date())
    }
    
    /// CRIT-BOLUS-006: Get carb ratio at a specific time
    public func carbRatioAt(_ date: Date) -> Double {
        let secondsFromMidnight = date.secondsFromMidnight
        let sorted = carbRatios.sorted { $0.startTime < $1.startTime }
        // Find the last entry that starts before or at the current time
        for entry in sorted.reversed() {
            if entry.startTime <= secondsFromMidnight {
                return entry.ratio
            }
        }
        // Fall back to first entry or default
        return sorted.first?.ratio ?? 10.0
    }
    
    /// CRIT-BOLUS-006: Get current ISF (sensitivity factor) for the current time of day
    /// Returns the factor (mg/dL per unit) active at the current time
    public var currentISF: Double {
        isfAt(Date())
    }
    
    /// CRIT-BOLUS-006: Get ISF at a specific time
    public func isfAt(_ date: Date) -> Double {
        let secondsFromMidnight = date.secondsFromMidnight
        let sorted = sensitivityFactors.sorted { $0.startTime < $1.startTime }
        // Find the last entry that starts before or at the current time
        for entry in sorted.reversed() {
            if entry.startTime <= secondsFromMidnight {
                return entry.factor
            }
        }
        // Fall back to first entry or default
        return sorted.first?.factor ?? 50.0
    }
}

/// A scheduled basal insulin rate for a time of day.
/// Used in therapy profiles to define background insulin delivery.
public struct BasalRate: Codable, Sendable {
    /// Start time as seconds from midnight (0-86400)
    public let startTime: TimeInterval
    /// Basal rate in units per hour (U/hr)
    public let rate: Double
    
    public init(startTime: TimeInterval, rate: Double) {
        self.startTime = startTime
        self.rate = rate
    }
}

/// A scheduled carbohydrate ratio for a time of day.
/// Defines how many grams of carbs are covered by one unit of insulin.
public struct CarbRatio: Codable, Sendable {
    /// Start time as seconds from midnight (0-86400)
    public let startTime: TimeInterval
    /// Carb ratio in grams per unit (g/U)
    public let ratio: Double
    
    public init(startTime: TimeInterval, ratio: Double) {
        self.startTime = startTime
        self.ratio = ratio
    }
}

/// A scheduled insulin sensitivity factor for a time of day.
/// Defines how much one unit of insulin lowers blood glucose.
public struct SensitivityFactor: Codable, Sendable {
    /// Start time as seconds from midnight (0-86400)
    public let startTime: TimeInterval
    /// Sensitivity factor in mg/dL per unit
    public let factor: Double
    
    public init(startTime: TimeInterval, factor: Double) {
        self.startTime = startTime
        self.factor = factor
    }
}

/// A target glucose range for therapy decisions.
/// Algorithms aim to keep glucose within this range.
public struct TargetRange: Codable, Sendable, Equatable {
    /// Lower bound of target range in mg/dL
    public let low: Double
    /// Upper bound of target range in mg/dL
    public let high: Double
    
    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }
    
    /// Midpoint of the target range
    public var midpoint: Double {
        (low + high) / 2
    }
}

// MARK: - Identity Provider Abstraction

/// Identity provider type
/// Requirements: REQ-ID-001
public enum IdentityProviderType: String, Codable, Sendable, CaseIterable {
    case nightscout = "nightscout"
    case tidepool = "tidepool"
    case t1pal = "t1pal"
    case custom = "custom"
}

/// Authentication method
/// Requirements: REQ-ID-001
public enum AuthMethod: String, Codable, Sendable {
    case apiSecret = "api_secret"      // Nightscout API secret
    case bearerToken = "bearer_token"  // JWT/OAuth token
    case oauth2 = "oauth2"             // Full OAuth2 flow
    case oidc = "oidc"                 // OpenID Connect
    case none = "none"                 // No auth required
}

/// Token type for authentication
/// Requirements: REQ-ID-002
public enum TokenType: String, Codable, Sendable {
    case access = "access"
    case refresh = "refresh"
    case apiSecret = "api_secret"
    case idToken = "id_token"
}

/// Authentication credential
/// Requirements: REQ-ID-002
public struct AuthCredential: Codable, Sendable {
    public let tokenType: TokenType
    public let value: String
    public let expiresAt: Date?
    public let scope: String?
    public let issuedAt: Date
    
    public init(
        tokenType: TokenType,
        value: String,
        expiresAt: Date? = nil,
        scope: String? = nil,
        issuedAt: Date = Date()
    ) {
        self.tokenType = tokenType
        self.value = value
        self.expiresAt = expiresAt
        self.scope = scope
        self.issuedAt = issuedAt
    }
    
    /// Check if credential is expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    /// Check if credential will expire within given interval
    public func willExpire(within interval: TimeInterval) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date().addingTimeInterval(interval) >= expiresAt
    }
}

/// OAuth2 configuration
/// Requirements: REQ-ID-001
public struct OAuth2Config: Codable, Sendable {
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let clientId: String
    public let redirectUri: URL
    public let scope: String
    public let responseType: String
    
    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientId: String,
        redirectUri: URL,
        scope: String = "openid profile",
        responseType: String = "code"
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.scope = scope
        self.responseType = responseType
    }
}

/// Token response from OAuth2 flow
/// Requirements: REQ-ID-001
public struct TokenResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    public let idToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
    }
    
    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        expiresIn: Int? = nil,
        refreshToken: String? = nil,
        scope: String? = nil,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.idToken = idToken
    }
    
    /// Convert to AuthCredential
    public func toCredential() -> AuthCredential {
        let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        return AuthCredential(
            tokenType: .access,
            value: accessToken,
            expiresAt: expiresAt,
            scope: scope
        )
    }
}

/// Identity provider protocol
/// Requirements: REQ-ID-001
public protocol IdentityProvider: Sendable {
    /// Provider type
    var providerType: IdentityProviderType { get }
    
    /// Provider display name
    var displayName: String { get }
    
    /// Supported authentication methods
    var supportedAuthMethods: [AuthMethod] { get }
    
    /// Check if authenticated
    func isAuthenticated() async -> Bool
    
    /// Get current credential
    func getCredential() async -> AuthCredential?
    
    /// Authenticate with provider
    func authenticate(method: AuthMethod, parameters: [String: String]) async throws -> AuthCredential
    
    /// Refresh credential if needed
    func refreshIfNeeded() async throws -> AuthCredential?
    
    /// Sign out
    func signOut() async
}

/// Identity provider error
/// Requirements: REQ-ID-001
public enum IdentityError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case authenticationFailed(String)
    case tokenExpired
    case refreshFailed(String)
    case unsupportedAuthMethod
    case invalidCredential
    case networkError(String)
    case configurationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .refreshFailed(let reason):
            return "Failed to refresh session: \(reason)"
        case .unsupportedAuthMethod:
            return "This authentication method is not supported."
        case .invalidCredential:
            return "Invalid credentials provided."
        case .networkError(let message):
            return "Network error during authentication: \(message)"
        case .configurationError(let message):
            return "Authentication configuration error: \(message)"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance

extension IdentityError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .auth }
    
    public var code: String {
        switch self {
        case .notAuthenticated: return "ID-AUTH-001"
        case .authenticationFailed: return "ID-AUTH-002"
        case .tokenExpired: return "ID-TOKEN-001"
        case .refreshFailed: return "ID-TOKEN-002"
        case .unsupportedAuthMethod: return "ID-CONFIG-001"
        case .invalidCredential: return "ID-CRED-001"
        case .networkError: return "ID-NET-001"
        case .configurationError: return "ID-CONFIG-002"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .notAuthenticated, .tokenExpired: return .warning
        case .configurationError: return .critical
        default: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .notAuthenticated, .tokenExpired, .authenticationFailed, .invalidCredential:
            return .reauthenticate
        case .refreshFailed:
            return .reauthenticate
        case .unsupportedAuthMethod, .configurationError:
            return .contactSupport
        case .networkError:
            return .checkNetwork
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown identity error"
    }
}

/// User identity information
/// Requirements: REQ-ID-001
public struct UserIdentity: Codable, Sendable, Identifiable {
    public let id: String
    public let provider: IdentityProviderType
    public let displayName: String?
    public let email: String?
    public let avatarUrl: URL?
    public let createdAt: Date
    
    public init(
        id: String,
        provider: IdentityProviderType,
        displayName: String? = nil,
        email: String? = nil,
        avatarUrl: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.email = email
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }
}

/// Nightscout instance configuration
/// Requirements: REQ-ID-003
public struct NightscoutInstance: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let authMethod: AuthMethod
    public let isDefault: Bool
    public let addedAt: Date
    
    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        authMethod: AuthMethod = .apiSecret,
        isDefault: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.authMethod = authMethod
        self.isDefault = isDefault
        self.addedAt = addedAt
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    public static func == (lhs: NightscoutInstance, rhs: NightscoutInstance) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Credential Storage (ID-002)

/// Storage key for credentials
/// Requirements: REQ-ID-002
public struct CredentialKey: Hashable, Sendable {
    public let service: String
    public let account: String
    public let accessGroup: String?
    
    public init(service: String, account: String, accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }
    
    /// Create key for Nightscout API secret
    public static func nightscout(url: URL) -> CredentialKey {
        CredentialKey(
            service: "com.t1pal.nightscout",
            account: url.host ?? url.absoluteString
        )
    }
    
    /// Create key for OAuth2 token
    public static func oauth2(provider: IdentityProviderType, userId: String) -> CredentialKey {
        CredentialKey(
            service: "com.t1pal.\(provider.rawValue)",
            account: userId
        )
    }
}

/// Stored credential with metadata
/// Requirements: REQ-ID-002
public struct StoredCredential: Codable, Sendable {
    public let credential: AuthCredential
    public let key: CredentialKeyData
    public let storedAt: Date
    public let lastAccessedAt: Date?
    
    public init(
        credential: AuthCredential,
        key: CredentialKey,
        storedAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.credential = credential
        self.key = CredentialKeyData(from: key)
        self.storedAt = storedAt
        self.lastAccessedAt = lastAccessedAt
    }
    
    /// Check if credential needs refresh (expires within margin)
    public func needsRefresh(margin: TimeInterval = 300) -> Bool {
        credential.willExpire(within: margin)
    }
}

/// Codable wrapper for CredentialKey
public struct CredentialKeyData: Codable, Sendable, Hashable {
    public let service: String
    public let account: String
    public let accessGroup: String?
    
    public init(from key: CredentialKey) {
        self.service = key.service
        self.account = key.account
        self.accessGroup = key.accessGroup
    }
    
    public func toKey() -> CredentialKey {
        CredentialKey(service: service, account: account, accessGroup: accessGroup)
    }
}

/// Error type for credential storage operations
/// Requirements: REQ-ID-002
public enum CredentialStoreError: Error, Sendable, LocalizedError, Equatable {
    case notFound
    case encodingFailed
    case decodingFailed
    case storageFailed(String)
    case accessDenied
    case itemAlreadyExists
    case unexpectedData
    case interactionNotAllowed
    
    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Credential not found in secure storage."
        case .encodingFailed:
            return "Failed to encode credential for storage."
        case .decodingFailed:
            return "Failed to decode stored credential."
        case .storageFailed(let reason):
            return "Secure storage failed: \(reason)"
        case .accessDenied:
            return "Access denied to secure storage."
        case .itemAlreadyExists:
            return "This credential already exists in storage."
        case .unexpectedData:
            return "Unexpected data format in secure storage."
        case .interactionNotAllowed:
            return "User interaction required to access credentials."
        }
    }
}

/// Protocol for secure credential storage
/// Requirements: REQ-ID-002
public protocol CredentialStoring: Sendable {
    /// Store a credential
    func store(_ credential: AuthCredential, for key: CredentialKey) async throws
    
    /// Retrieve a credential
    func retrieve(for key: CredentialKey) async throws -> AuthCredential
    
    /// Delete a credential
    func delete(for key: CredentialKey) async throws
    
    /// Check if credential exists
    func exists(for key: CredentialKey) async -> Bool
    
    /// List all stored credential keys
    func allKeys(for service: String) async throws -> [CredentialKey]
}

/// In-memory credential store for testing and Linux
/// Requirements: REQ-ID-002
public actor MemoryCredentialStore: CredentialStoring {
    private var storage: [String: StoredCredential] = [:]
    
    public init() {}
    
    private func keyId(_ key: CredentialKey) -> String {
        "\(key.service):\(key.account)"
    }
    
    public func store(_ credential: AuthCredential, for key: CredentialKey) async throws {
        let stored = StoredCredential(credential: credential, key: key)
        storage[keyId(key)] = stored
    }
    
    public func retrieve(for key: CredentialKey) async throws -> AuthCredential {
        guard let stored = storage[keyId(key)] else {
            throw CredentialStoreError.notFound
        }
        return stored.credential
    }
    
    public func delete(for key: CredentialKey) async throws {
        guard storage.removeValue(forKey: keyId(key)) != nil else {
            throw CredentialStoreError.notFound
        }
    }
    
    public func exists(for key: CredentialKey) async -> Bool {
        storage[keyId(key)] != nil
    }
    
    public func allKeys(for service: String) async throws -> [CredentialKey] {
        storage.values
            .filter { $0.key.service == service }
            .map { $0.key.toKey() }
    }
    
    public func clear() async {
        storage.removeAll()
    }
}

/// Token refresh request
/// Requirements: REQ-ID-002
public struct TokenRefreshRequest: Sendable {
    public let refreshToken: String
    public let config: OAuth2Config
    
    public init(refreshToken: String, config: OAuth2Config) {
        self.refreshToken = refreshToken
        self.config = config
    }
}

/// Credential manager with automatic refresh
/// Requirements: REQ-ID-002
public actor CredentialManager {
    private let store: any CredentialStoring
    private let refreshMargin: TimeInterval
    private var refreshTokens: [String: String] = [:]  // account -> refreshToken
    
    public init(store: any CredentialStoring, refreshMargin: TimeInterval = 300) {
        self.store = store
        self.refreshMargin = refreshMargin
    }
    
    /// Get credential, checking if refresh is needed
    public func getCredential(for key: CredentialKey) async throws -> AuthCredential {
        let credential = try await store.retrieve(for: key)
        
        // Check if refresh is needed
        if credential.willExpire(within: refreshMargin) {
            // If we have a refresh token, caller should refresh
            // For now, return existing credential
        }
        
        return credential
    }
    
    /// Store credential with optional refresh token
    public func storeCredential(
        _ credential: AuthCredential,
        for key: CredentialKey,
        refreshToken: String? = nil
    ) async throws {
        try await store.store(credential, for: key)
        if let refreshToken = refreshToken {
            refreshTokens[key.account] = refreshToken
        }
    }
    
    /// Get refresh token if available
    public func getRefreshToken(for key: CredentialKey) async -> String? {
        refreshTokens[key.account]
    }
    
    /// Delete credential and associated refresh token
    public func deleteCredential(for key: CredentialKey) async throws {
        try await store.delete(for: key)
        refreshTokens.removeValue(forKey: key.account)
    }
    
    /// Check if credential exists and is valid
    public func hasValidCredential(for key: CredentialKey) async -> Bool {
        guard await store.exists(for: key) else { return false }
        do {
            let credential = try await store.retrieve(for: key)
            return !credential.isExpired
        } catch {
            return false
        }
    }
    
    /// List all credentials for a service
    public func listCredentials(for service: String) async throws -> [CredentialKey] {
        try await store.allKeys(for: service)
    }
}

/// Credential expiry observer
/// Requirements: REQ-ID-002
public protocol CredentialExpiryObserver: AnyObject, Sendable {
    func credentialWillExpire(key: CredentialKey, in timeInterval: TimeInterval)
    func credentialDidExpire(key: CredentialKey)
}

/// Credential monitor for expiry tracking
/// Requirements: REQ-ID-002
public actor CredentialExpiryMonitor {
    private let store: any CredentialStoring
    private let checkInterval: TimeInterval
    private let warningThreshold: TimeInterval
    private weak var observer: (any CredentialExpiryObserver)?
    private var isMonitoring = false
    
    public init(
        store: any CredentialStoring,
        checkInterval: TimeInterval = 60,
        warningThreshold: TimeInterval = 300
    ) {
        self.store = store
        self.checkInterval = checkInterval
        self.warningThreshold = warningThreshold
    }
    
    public func setObserver(_ observer: any CredentialExpiryObserver) {
        self.observer = observer
    }
    
    /// Check credential expiry status
    public func checkExpiry(for key: CredentialKey) async throws -> CredentialExpiryStatus {
        let credential = try await store.retrieve(for: key)
        
        if credential.isExpired {
            return .expired
        } else if credential.willExpire(within: warningThreshold) {
            let remaining = credential.expiresAt.map { $0.timeIntervalSinceNow } ?? .infinity
            return .expiringSoon(remaining)
        } else {
            return .valid
        }
    }
}

/// Credential expiry status
/// Requirements: REQ-ID-002
public enum CredentialExpiryStatus: Sendable {
    case valid
    case expiringSoon(TimeInterval)
    case expired
    case unknown
}

// TidepoolEnvironment, TidepoolConfig, TidepoolSession, TidepoolProfile, TidepoolProfileData, TidepoolPatientData, TidepoolError, TidepoolAuth, TidepoolDataSet, TidepoolClientInfo moved to TidepoolIdentity.swift (CORE-REFACTOR-001)

// T1PalEnvironment, T1PalConfig, T1PalSession, T1PalProfile, T1PalSubscription, T1PalPlan, T1PalSubscriptionStatus, T1PalInstance, T1PalInstanceStatus, T1PalProvisionRequest, T1PalError, T1PalAuth moved to T1PalHostedIdentity.swift (CORE-REFACTOR-002)

// MARK: - Date Extensions

extension Date {
    /// CRIT-BOLUS-006: Returns seconds from midnight for the current date
    /// Used for time-of-day schedule lookups
    var secondsFromMidnight: TimeInterval {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: self)
        let hours = Double(components.hour ?? 0)
        let minutes = Double(components.minute ?? 0)
        let seconds = Double(components.second ?? 0)
        return hours * 3600 + minutes * 60 + seconds
    }
}
