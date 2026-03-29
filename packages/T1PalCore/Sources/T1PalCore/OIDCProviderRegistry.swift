// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// OIDCProviderRegistry.swift
// T1PalCore
//
// Generic OIDC provider support with presets for common enterprise providers.
// Enables clinic SSO, enterprise identity, and federated authentication.
// Trace: ID-ENT-001, PRD-003, REQ-ID-002

import Foundation

// MARK: - OIDC Provider

/// Protocol for OIDC identity providers
public protocol OIDCProvider: Sendable {
    /// Unique provider identifier
    var id: String { get }
    
    /// Display name
    var displayName: String { get }
    
    /// Provider type category
    var category: OIDCProviderCategory { get }
    
    /// Provider base URL (issuer)
    var issuerURL: URL { get }
    
    /// Default scopes for this provider
    var defaultScopes: [String] { get }
    
    /// Whether this provider supports PKCE
    var supportsPKCE: Bool { get }
    
    /// Icon name (SF Symbols or asset)
    var iconName: String { get }
    
    /// Provider-specific notes or requirements
    var notes: String? { get }
}

// MARK: - Provider Category

/// Categories of OIDC providers
public enum OIDCProviderCategory: String, Sendable, Codable, CaseIterable {
    /// Major cloud identity providers (Google, Microsoft, Apple)
    case consumer
    
    /// Enterprise identity platforms (Okta, Auth0, Azure AD)
    case enterprise
    
    /// Healthcare-specific providers (Epic MyChart, Cerner)
    case healthcare
    
    /// Self-hosted identity providers (Keycloak, ORY Hydra)
    case selfHosted
    
    /// Custom/unknown provider
    case custom
    
    public var displayName: String {
        switch self {
        case .consumer: return "Consumer Identity"
        case .enterprise: return "Enterprise SSO"
        case .healthcare: return "Healthcare"
        case .selfHosted: return "Self-Hosted"
        case .custom: return "Custom Provider"
        }
    }
    
    public var description: String {
        switch self {
        case .consumer:
            return "Sign in with your existing account"
        case .enterprise:
            return "Sign in with your organization account"
        case .healthcare:
            return "Sign in with your healthcare provider"
        case .selfHosted:
            return "Sign in with your self-hosted identity server"
        case .custom:
            return "Sign in with a custom OIDC provider"
        }
    }
}

// MARK: - Provider Configuration

/// Complete configuration for an OIDC provider instance
public struct OIDCProviderConfig: Codable, Sendable, Equatable {
    /// Provider identifier
    public let providerId: String
    
    /// Display name
    public let displayName: String
    
    /// Provider category
    public let category: OIDCProviderCategory
    
    /// Issuer URL
    public let issuerURL: URL
    
    /// Client ID (registered with provider)
    public let clientId: String
    
    /// Client secret (nil for public clients)
    public let clientSecret: String?
    
    /// Redirect URI for this app
    public let redirectUri: URL
    
    /// Requested scopes
    public let scopes: [String]
    
    /// Use PKCE (recommended)
    public let usePKCE: Bool
    
    /// Additional parameters for authorization request
    public let additionalParams: [String: String]?
    
    /// When this configuration was created
    public let createdAt: Date
    
    /// Last used timestamp
    public var lastUsedAt: Date?
    
    public init(
        providerId: String,
        displayName: String,
        category: OIDCProviderCategory,
        issuerURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        redirectUri: URL,
        scopes: [String] = ["openid", "profile", "email"],
        usePKCE: Bool = true,
        additionalParams: [String: String]? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.category = category
        self.issuerURL = issuerURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectUri = redirectUri
        self.scopes = scopes
        self.usePKCE = usePKCE
        self.additionalParams = additionalParams
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
    
    /// Create configuration from a known provider preset
    public static func from(
        provider: KnownOIDCProvider,
        clientId: String,
        clientSecret: String? = nil,
        redirectUri: URL,
        additionalScopes: [String] = []
    ) -> OIDCProviderConfig {
        var scopes = provider.defaultScopes
        scopes.append(contentsOf: additionalScopes)
        
        return OIDCProviderConfig(
            providerId: provider.id,
            displayName: provider.displayName,
            category: provider.category,
            issuerURL: provider.issuerURL,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectUri: redirectUri,
            scopes: Array(Set(scopes)), // Deduplicate
            usePKCE: provider.supportsPKCE,
            additionalParams: provider.additionalParams
        )
    }
}

// MARK: - Known OIDC Providers

/// Well-known OIDC providers with pre-configured settings
public enum KnownOIDCProvider: String, Sendable, CaseIterable, OIDCProvider {
    // Consumer providers
    case google
    case apple
    case microsoft
    
    // Enterprise providers
    case okta
    case auth0
    case azureAD
    case oneLogin
    case pingIdentity
    
    // Healthcare providers
    case epicMyChart
    case cerner
    case allscripts
    
    // Self-hosted providers
    case keycloak
    case oryHydra
    case authelia
    
    // T1Pal
    case t1pal
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .apple: return "Apple"
        case .microsoft: return "Microsoft"
        case .okta: return "Okta"
        case .auth0: return "Auth0"
        case .azureAD: return "Azure AD"
        case .oneLogin: return "OneLogin"
        case .pingIdentity: return "Ping Identity"
        case .epicMyChart: return "Epic MyChart"
        case .cerner: return "Cerner"
        case .allscripts: return "Allscripts"
        case .keycloak: return "Keycloak"
        case .oryHydra: return "ORY Hydra"
        case .authelia: return "Authelia"
        case .t1pal: return "T1Pal"
        }
    }
    
    public var category: OIDCProviderCategory {
        switch self {
        case .google, .apple, .microsoft:
            return .consumer
        case .okta, .auth0, .azureAD, .oneLogin, .pingIdentity:
            return .enterprise
        case .epicMyChart, .cerner, .allscripts:
            return .healthcare
        case .keycloak, .oryHydra, .authelia:
            return .selfHosted
        case .t1pal:
            return .custom
        }
    }
    
    public var issuerURL: URL {
        switch self {
        case .google:
            return URL(string: "https://accounts.google.com")!
        case .apple:
            return URL(string: "https://appleid.apple.com")!
        case .microsoft:
            return URL(string: "https://login.microsoftonline.com/common/v2.0")!
        case .azureAD:
            // Azure AD requires tenant-specific URL, this is a placeholder
            return URL(string: "https://login.microsoftonline.com/TENANT/v2.0")!
        case .okta:
            // Okta requires org-specific URL
            return URL(string: "https://ORGANIZATION.okta.com")!
        case .auth0:
            // Auth0 requires tenant-specific URL
            return URL(string: "https://TENANT.auth0.com")!
        case .oneLogin:
            return URL(string: "https://SUBDOMAIN.onelogin.com/oidc/2")!
        case .pingIdentity:
            return URL(string: "https://ENVIRONMENT.pingone.com/TENANT/as")!
        case .epicMyChart:
            // Epic uses FHIR-based OAuth, this is sandbox
            return URL(string: "https://fhir.epic.com/interconnect-fhir-oauth")!
        case .cerner:
            return URL(string: "https://authorization.cerner.com")!
        case .allscripts:
            return URL(string: "https://cloud.allscriptsunity.com")!
        case .keycloak:
            // Self-hosted, requires realm
            return URL(string: "https://HOST/realms/REALM")!
        case .oryHydra:
            return URL(string: "https://HOST")!
        case .authelia:
            return URL(string: "https://HOST")!
        case .t1pal:
            return URL(string: "https://auth.t1pal.com")!
        }
    }
    
    public var defaultScopes: [String] {
        switch self {
        case .google:
            return ["openid", "profile", "email"]
        case .apple:
            return ["openid", "name", "email"]
        case .microsoft, .azureAD:
            return ["openid", "profile", "email", "offline_access"]
        case .okta, .auth0, .oneLogin, .pingIdentity:
            return ["openid", "profile", "email", "offline_access"]
        case .epicMyChart:
            // Epic uses SMART on FHIR scopes
            return ["openid", "fhirUser", "patient/*.read"]
        case .cerner:
            return ["openid", "profile", "fhirUser", "patient/Patient.read"]
        case .allscripts:
            return ["openid", "profile", "email"]
        case .keycloak, .oryHydra, .authelia:
            return ["openid", "profile", "email", "offline_access"]
        case .t1pal:
            return ["openid", "profile", "email", "nightscout", "offline_access"]
        }
    }
    
    public var supportsPKCE: Bool {
        // All modern providers support PKCE
        return true
    }
    
    public var iconName: String {
        switch self {
        case .google: return "g.circle.fill"
        case .apple: return "apple.logo"
        case .microsoft: return "window.badge.person"
        case .okta: return "lock.shield.fill"
        case .auth0: return "lock.circle.fill"
        case .azureAD: return "cloud.fill"
        case .oneLogin: return "person.badge.key.fill"
        case .pingIdentity: return "person.crop.circle.badge.checkmark"
        case .epicMyChart: return "heart.text.square.fill"
        case .cerner: return "cross.circle.fill"
        case .allscripts: return "doc.text.fill"
        case .keycloak: return "key.fill"
        case .oryHydra: return "shield.fill"
        case .authelia: return "lock.fill"
        case .t1pal: return "drop.fill"
        }
    }
    
    public var notes: String? {
        switch self {
        case .google:
            return "Requires Google Cloud Console setup"
        case .apple:
            return "Requires Apple Developer account"
        case .microsoft:
            return "Works with personal and work accounts"
        case .azureAD:
            return "Requires Azure AD tenant configuration"
        case .okta:
            return "Requires Okta organization URL"
        case .auth0:
            return "Requires Auth0 tenant configuration"
        case .epicMyChart:
            return "SMART on FHIR authentication - requires Epic app registration"
        case .cerner:
            return "SMART on FHIR authentication - requires Cerner code console"
        case .keycloak:
            return "Self-hosted - requires realm configuration"
        case .oryHydra:
            return "Self-hosted OAuth2/OIDC server"
        default:
            return nil
        }
    }
    
    /// Additional authorization parameters for this provider
    public var additionalParams: [String: String]? {
        switch self {
        case .google:
            return ["access_type": "offline", "prompt": "consent"]
        case .apple:
            return ["response_mode": "form_post"]
        case .microsoft, .azureAD:
            return ["prompt": "select_account"]
        case .epicMyChart:
            return ["aud": "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4"]
        default:
            return nil
        }
    }
    
    /// Check if this provider requires a custom issuer URL
    public var requiresCustomIssuer: Bool {
        switch self {
        case .okta, .auth0, .azureAD, .oneLogin, .pingIdentity,
             .keycloak, .oryHydra, .authelia:
            return true
        default:
            return false
        }
    }
    
    /// Providers by category
    public static func providers(for category: OIDCProviderCategory) -> [KnownOIDCProvider] {
        allCases.filter { $0.category == category }
    }
}

// MARK: - Provider Registry

/// Registry for managing OIDC provider configurations
public actor OIDCProviderRegistry {
    
    /// Stored provider configurations
    private var configurations: [String: OIDCProviderConfig] = [:]
    
    /// Storage key prefix
    private let storageKey = "com.t1pal.oidc.providers"
    
    public init() {
        Task { await self.loadConfigurationsAsync() }
    }
    
    /// Load configurations asynchronously
    private func loadConfigurationsAsync() {
        loadConfigurations()
    }
    
    // MARK: - Configuration Management
    
    /// Register a provider configuration
    public func register(_ config: OIDCProviderConfig) {
        configurations[config.providerId] = config
        saveConfigurations()
    }
    
    /// Get configuration for a provider
    public func configuration(for providerId: String) -> OIDCProviderConfig? {
        configurations[providerId]
    }
    
    /// Get all registered configurations
    public func allConfigurations() -> [OIDCProviderConfig] {
        Array(configurations.values).sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Get configurations by category
    public func configurations(for category: OIDCProviderCategory) -> [OIDCProviderConfig] {
        configurations.values.filter { $0.category == category }
    }
    
    /// Remove a provider configuration
    public func remove(providerId: String) {
        configurations.removeValue(forKey: providerId)
        saveConfigurations()
    }
    
    /// Update last used timestamp
    public func markUsed(providerId: String) {
        if var config = configurations[providerId] {
            config.lastUsedAt = Date()
            configurations[providerId] = config
            saveConfigurations()
        }
    }
    
    /// Clear all configurations
    public func clearAll() {
        configurations.removeAll()
        saveConfigurations()
    }
    
    // MARK: - Persistence
    
    private func loadConfigurations() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([String: OIDCProviderConfig].self, from: data) else {
            return
        }
        configurations = configs
    }
    
    private func saveConfigurations() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Custom Provider Builder

/// Builder for creating custom OIDC provider configurations
public struct CustomOIDCProviderBuilder {
    private var issuerURL: URL?
    private var clientId: String?
    private var clientSecret: String?
    private var redirectUri: URL?
    private var scopes: [String] = ["openid", "profile", "email"]
    private var displayName: String = "Custom Provider"
    private var usePKCE: Bool = true
    private var additionalParams: [String: String]?
    
    public init() {}
    
    private init(from other: CustomOIDCProviderBuilder) {
        self.issuerURL = other.issuerURL
        self.clientId = other.clientId
        self.clientSecret = other.clientSecret
        self.redirectUri = other.redirectUri
        self.scopes = other.scopes
        self.displayName = other.displayName
        self.usePKCE = other.usePKCE
        self.additionalParams = other.additionalParams
    }
    
    public func issuer(_ url: URL) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.issuerURL = url
        return copy
    }
    
    public func clientId(_ id: String) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.clientId = id
        return copy
    }
    
    public func clientSecret(_ secret: String) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.clientSecret = secret
        return copy
    }
    
    public func redirectUri(_ uri: URL) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.redirectUri = uri
        return copy
    }
    
    public func scopes(_ scopes: [String]) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.scopes = scopes
        return copy
    }
    
    public func displayName(_ name: String) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.displayName = name
        return copy
    }
    
    public func usePKCE(_ use: Bool) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.usePKCE = use
        return copy
    }
    
    public func additionalParams(_ params: [String: String]) -> CustomOIDCProviderBuilder {
        var copy = CustomOIDCProviderBuilder(from: self)
        copy.additionalParams = params
        return copy
    }
    
    /// Build the configuration
    public func build() throws -> OIDCProviderConfig {
        guard let issuerURL = issuerURL else {
            throw OIDCProviderBuilderError.missingIssuer
        }
        guard let clientId = clientId else {
            throw OIDCProviderBuilderError.missingClientId
        }
        guard let redirectUri = redirectUri else {
            throw OIDCProviderBuilderError.missingRedirectUri
        }
        
        return OIDCProviderConfig(
            providerId: "custom.\(UUID().uuidString.prefix(8))",
            displayName: displayName,
            category: .custom,
            issuerURL: issuerURL,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectUri: redirectUri,
            scopes: scopes,
            usePKCE: usePKCE,
            additionalParams: additionalParams
        )
    }
}

/// Errors during provider configuration building
public enum OIDCProviderBuilderError: Error, LocalizedError {
    case missingIssuer
    case missingClientId
    case missingRedirectUri
    
    public var errorDescription: String? {
        switch self {
        case .missingIssuer:
            return "Issuer URL is required"
        case .missingClientId:
            return "Client ID is required"
        case .missingRedirectUri:
            return "Redirect URI is required"
        }
    }
}
