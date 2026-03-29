// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ClinicOnboarding.swift
// T1PalCore
//
// Clinic/enterprise onboarding flow for healthcare organization SSO.
// Supports QR code scan, OIDC provider selection, and profile sync.
// Trace: ID-ENT-002, PRD-003, REQ-ID-003

import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Clinic Onboarding Step

/// Steps in the clinic onboarding flow
public enum ClinicOnboardingStepType: String, Sendable, CaseIterable {
    /// Welcome and explanation
    case welcome
    
    /// Scan clinic QR code (contains OIDC config)
    case scanQRCode
    
    /// Select provider from list (if no QR)
    case selectProvider
    
    /// Authenticate with provider
    case authenticate
    
    /// Review profile from provider
    case reviewProfile
    
    /// Discover Nightscout instances
    case discoverInstances
    
    /// Select or create Nightscout instance
    case selectInstance
    
    /// Sync settings from clinic
    case syncSettings
    
    /// Completion
    case complete
}

/// A step in the clinic onboarding process
public struct ClinicOnboardingStep: OnboardingStep, Sendable {
    public let id: String
    public let type: ClinicOnboardingStepType
    public let title: String
    public let subtitle: String?
    public let iconName: String
    public let isSkippable: Bool
    public var isComplete: Bool
    
    public init(
        type: ClinicOnboardingStepType,
        title: String,
        subtitle: String? = nil,
        iconName: String,
        isSkippable: Bool = false,
        isComplete: Bool = false
    ) {
        self.id = type.rawValue
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.isSkippable = isSkippable
        self.isComplete = isComplete
    }
    
    public func validate() async -> OnboardingValidationResult {
        // Validation is handled by the coordinator based on state
        return .valid
    }
}

// MARK: - Clinic QR Payload

/// Payload from clinic QR code containing OIDC configuration
public struct ClinicQRPayload: Codable, Sendable, Equatable {
    /// Clinic identifier
    public let clinicId: String
    
    /// Clinic display name
    public let clinicName: String
    
    /// OIDC issuer URL
    public let issuerURL: URL
    
    /// Pre-configured client ID (optional)
    public let clientId: String?
    
    /// Redirect URI override (optional)
    public let redirectUri: URL?
    
    /// Required scopes beyond standard OIDC
    public let additionalScopes: [String]?
    
    /// Profile sync endpoint (optional)
    public let profileSyncURL: URL?
    
    /// Settings sync endpoint (optional)
    public let settingsSyncURL: URL?
    
    /// Expiration timestamp (optional)
    public let expiresAt: Date?
    
    public init(
        clinicId: String,
        clinicName: String,
        issuerURL: URL,
        clientId: String? = nil,
        redirectUri: URL? = nil,
        additionalScopes: [String]? = nil,
        profileSyncURL: URL? = nil,
        settingsSyncURL: URL? = nil,
        expiresAt: Date? = nil
    ) {
        self.clinicId = clinicId
        self.clinicName = clinicName
        self.issuerURL = issuerURL
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.additionalScopes = additionalScopes
        self.profileSyncURL = profileSyncURL
        self.settingsSyncURL = settingsSyncURL
        self.expiresAt = expiresAt
    }
    
    /// Parse from QR code JSON string
    public static func parse(from jsonString: String) throws -> ClinicQRPayload {
        guard let data = jsonString.data(using: .utf8) else {
            throw ClinicOnboardingError.invalidQRCode("Invalid UTF-8 encoding")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(ClinicQRPayload.self, from: data)
        } catch {
            throw ClinicOnboardingError.invalidQRCode("Invalid JSON format: \(error.localizedDescription)")
        }
    }
    
    /// Check if payload has expired
    public var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return Date() > expiry
    }
}

// MARK: - Clinic Profile

/// User profile from clinic OIDC provider
public struct ClinicUserProfile: Codable, Sendable, Equatable {
    /// Unique user identifier from provider
    public let subject: String
    
    /// Display name
    public let name: String?
    
    /// Email address
    public let email: String?
    
    /// Whether email is verified
    public let emailVerified: Bool?
    
    /// Clinic/organization name
    public let organizationName: String?
    
    /// User role within organization
    public let role: String?
    
    /// Provider-specific claims
    public let additionalClaims: [String: String]?
    
    public init(
        subject: String,
        name: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        organizationName: String? = nil,
        role: String? = nil,
        additionalClaims: [String: String]? = nil
    ) {
        self.subject = subject
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.organizationName = organizationName
        self.role = role
        self.additionalClaims = additionalClaims
    }
}

// MARK: - Clinic Onboarding State

/// Current state of clinic onboarding
public struct ClinicOnboardingState: Sendable {
    /// Scanned or selected provider configuration
    public var providerConfig: OIDCProviderConfig?
    
    /// Parsed QR payload (if from QR scan)
    public var qrPayload: ClinicQRPayload?
    
    /// User profile after authentication
    public var userProfile: ClinicUserProfile?
    
    /// Access token (stored securely, not persisted here)
    public var hasAccessToken: Bool = false
    
    /// Access token value for API calls (transient, not persisted)
    internal var accessToken: String?
    
    /// Refresh token available
    public var hasRefreshToken: Bool = false
    
    /// Discovered Nightscout instances (REQ-ID-004)
    public var discoveredInstances: [NSInstanceBinding] = []
    
    /// Whether instance discovery is in progress
    public var isDiscoveringInstances: Bool = false
    
    /// Selected Nightscout instance
    public var selectedInstance: NSInstanceBinding?
    
    /// Settings synced from clinic
    public var settingsSynced: Bool = false
    
    /// Managed settings payload (if provider supports it)
    public var managedSettings: ManagedSettingsPayload?
    
    /// Current error, if any
    public var error: ClinicOnboardingError?
    
    public init() {}
    
    /// Reset to initial state
    public mutating func reset() {
        providerConfig = nil
        qrPayload = nil
        userProfile = nil
        hasAccessToken = false
        accessToken = nil
        hasRefreshToken = false
        discoveredInstances = []
        isDiscoveringInstances = false
        selectedInstance = nil
        settingsSynced = false
        managedSettings = nil
        error = nil
    }
}

// MARK: - Errors

/// Errors during clinic onboarding
public enum ClinicOnboardingError: Error, LocalizedError, Sendable {
    case invalidQRCode(String)
    case qrCodeExpired
    case providerNotFound
    case discoveryFailed(String)
    case authenticationFailed(String)
    case authenticationCancelled
    case profileFetchFailed(String)
    case instanceDiscoveryFailed(String)
    case instanceValidationFailed(String)
    case noInstanceSelected
    case settingsSyncFailed(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidQRCode(let detail):
            return "Invalid QR code: \(detail)"
        case .qrCodeExpired:
            return "This QR code has expired. Please request a new one from your clinic."
        case .providerNotFound:
            return "Could not find the identity provider configuration."
        case .discoveryFailed(let detail):
            return "Could not connect to identity provider: \(detail)"
        case .authenticationFailed(let detail):
            return "Authentication failed: \(detail)"
        case .authenticationCancelled:
            return "Authentication was cancelled."
        case .profileFetchFailed(let detail):
            return "Could not fetch your profile: \(detail)"
        case .instanceDiscoveryFailed(let detail):
            return "Could not discover Nightscout instances: \(detail)"
        case .instanceValidationFailed(let detail):
            return "Nightscout instance validation failed: \(detail)"
        case .noInstanceSelected:
            return "Please select a Nightscout instance to continue."
        case .settingsSyncFailed(let detail):
            return "Could not sync settings: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - Clinic Onboarding Manager

/// Manages the clinic onboarding flow
#if canImport(Observation)
@available(iOS 17.0, macOS 14.0, *)
@Observable
public final class ClinicOnboardingManager: @unchecked Sendable {
    
    /// Current onboarding state
    public var state = ClinicOnboardingState()
    
    /// Current step in the flow
    public var currentStep: ClinicOnboardingStepType = .welcome
    
    /// Whether authentication is in progress
    public var isAuthenticating = false
    
    /// Whether settings sync is in progress
    public var isSyncing = false
    
    /// OIDC discovery service
    private let discovery = LiveOIDCDiscoveryClient()
    
    /// Provider registry
    private let providerRegistry: OIDCProviderRegistry
    
    /// NS instance discovery client (injected, optional)
    private var instanceDiscoveryClient: (any NSInstanceDiscoveryProtocol)?
    
    public init(providerRegistry: OIDCProviderRegistry = OIDCProviderRegistry()) {
        self.providerRegistry = providerRegistry
    }
    
    /// Configure the NS instance discovery client
    /// Call this to wire NightscoutKit's LiveDiscoveryClient
    public func setInstanceDiscoveryClient(_ client: any NSInstanceDiscoveryProtocol) {
        self.instanceDiscoveryClient = client
    }
    
    // MARK: - QR Code Handling
    
    /// Process a scanned QR code
    public func processQRCode(_ jsonString: String) async throws {
        let payload = try ClinicQRPayload.parse(from: jsonString)
        
        // Check expiration
        if payload.isExpired {
            throw ClinicOnboardingError.qrCodeExpired
        }
        
        state.qrPayload = payload
        
        // Build provider config from QR payload
        let config = OIDCProviderConfig(
            providerId: "clinic.\(payload.clinicId)",
            displayName: payload.clinicName,
            category: .healthcare,
            issuerURL: payload.issuerURL,
            clientId: payload.clientId ?? "t1pal-mobile",
            redirectUri: payload.redirectUri ?? URL(string: "t1pal://oidc/callback")!,
            scopes: ["openid", "profile", "email"] + (payload.additionalScopes ?? []),
            usePKCE: true
        )
        
        // Validate provider via discovery
        do {
            _ = try await discovery.discover(providerURL: payload.issuerURL)
        } catch let error as OIDCDiscoveryError {
            throw ClinicOnboardingError.discoveryFailed(error.localizedDescription)
        }
        
        state.providerConfig = config
        
        // Register in provider registry
        await providerRegistry.register(config)
        
        // Move to authentication step
        currentStep = .authenticate
    }
    
    /// Select a known provider from the list
    public func selectProvider(_ provider: KnownOIDCProvider, clientId: String) async throws {
        // Build config from known provider
        let config = OIDCProviderConfig.from(
            provider: provider,
            clientId: clientId,
            redirectUri: URL(string: "t1pal://oidc/callback")!
        )
        
        // Validate via discovery (skip for providers with placeholder URLs)
        if !provider.requiresCustomIssuer {
            do {
                _ = try await discovery.discover(providerURL: provider.issuerURL)
            } catch let error as OIDCDiscoveryError {
                throw ClinicOnboardingError.discoveryFailed(error.localizedDescription)
            }
        }
        
        state.providerConfig = config
        await providerRegistry.register(config)
        
        currentStep = .authenticate
    }
    
    // MARK: - Authentication
    
    /// Simulate authentication success (actual auth handled by ASWebAuthenticationSession)
    public func completeAuthentication(accessToken: String, refreshToken: String?) {
        state.hasAccessToken = true
        state.accessToken = accessToken
        state.hasRefreshToken = refreshToken != nil
        currentStep = .reviewProfile
    }
    
    /// Handle authentication error
    public func handleAuthenticationError(_ error: Error) {
        if (error as NSError).code == 1 { // ASWebAuthenticationSession cancelled
            state.error = .authenticationCancelled
        } else {
            state.error = .authenticationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Profile
    
    /// Set the user profile from OIDC claims
    public func setUserProfile(_ profile: ClinicUserProfile) {
        state.userProfile = profile
        // After profile, discover instances if client is configured
        if instanceDiscoveryClient != nil {
            currentStep = .discoverInstances
        } else {
            currentStep = .syncSettings
        }
    }
    
    // MARK: - Instance Discovery (REQ-ID-004)
    
    /// Discover Nightscout instances associated with the authenticated user
    public func discoverInstances() async throws {
        guard let client = instanceDiscoveryClient else {
            // No client configured, skip to settings
            currentStep = .syncSettings
            return
        }
        
        guard let accessToken = state.accessToken else {
            throw ClinicOnboardingError.authenticationFailed("No access token available")
        }
        
        state.isDiscoveringInstances = true
        defer { state.isDiscoveringInstances = false }
        
        // Set the access token on the client
        await client.setAccessToken(accessToken)
        
        do {
            let response = try await client.discoverInstances()
            state.discoveredInstances = response.instances
            
            // If exactly one instance, auto-select it
            if response.instances.count == 1 {
                state.selectedInstance = response.instances[0]
                currentStep = .syncSettings
            } else {
                currentStep = .selectInstance
            }
        } catch {
            throw ClinicOnboardingError.instanceDiscoveryFailed(error.localizedDescription)
        }
    }
    
    /// Select a discovered instance
    public func selectInstance(_ instance: NSInstanceBinding) {
        state.selectedInstance = instance
        currentStep = .syncSettings
    }
    
    /// Skip instance selection (user will configure manually later)
    public func skipInstanceSelection() {
        currentStep = .syncSettings
    }
    
    // MARK: - Settings Sync
    
    /// Sync settings from clinic
    public func syncSettings() async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // If no sync URL, skip
        guard let syncURL = state.qrPayload?.settingsSyncURL else {
            state.settingsSynced = true
            currentStep = .complete
            return
        }
        
        // Need access token for API call
        guard let accessToken = state.accessToken else {
            state.settingsSynced = true
            currentStep = .complete
            return
        }
        
        // Fetch managed settings from provider
        do {
            let manager = ManagedSettingsManager()
            let payload = try await manager.fetchSettings(from: syncURL, accessToken: accessToken)
            try await manager.apply(payload)
            state.managedSettings = payload
            state.settingsSynced = true
            currentStep = .complete
        } catch {
            throw ClinicOnboardingError.settingsSyncFailed(error.localizedDescription)
        }
    }
    
    /// Skip settings sync
    public func skipSettingsSync() {
        currentStep = .complete
    }
    
    // MARK: - Navigation
    
    /// Move to next step
    public func nextStep() {
        switch currentStep {
        case .welcome:
            currentStep = .scanQRCode
        case .scanQRCode:
            if state.providerConfig != nil {
                currentStep = .authenticate
            } else {
                currentStep = .selectProvider
            }
        case .selectProvider:
            if state.providerConfig != nil {
                currentStep = .authenticate
            }
        case .authenticate:
            if state.hasAccessToken {
                currentStep = .reviewProfile
            }
        case .reviewProfile:
            if instanceDiscoveryClient != nil {
                currentStep = .discoverInstances
            } else {
                currentStep = .syncSettings
            }
        case .discoverInstances:
            currentStep = .selectInstance
        case .selectInstance:
            if state.selectedInstance != nil {
                currentStep = .syncSettings
            }
        case .syncSettings:
            currentStep = .complete
        case .complete:
            break
        }
    }
    
    /// Move to previous step
    public func previousStep() {
        switch currentStep {
        case .welcome:
            break
        case .scanQRCode:
            currentStep = .welcome
        case .selectProvider:
            currentStep = .scanQRCode
        case .authenticate:
            currentStep = state.qrPayload != nil ? .scanQRCode : .selectProvider
        case .reviewProfile:
            currentStep = .authenticate
        case .discoverInstances:
            currentStep = .reviewProfile
        case .selectInstance:
            currentStep = .discoverInstances
        case .syncSettings:
            if state.discoveredInstances.isEmpty {
                currentStep = .reviewProfile
            } else {
                currentStep = .selectInstance
            }
        case .complete:
            currentStep = .syncSettings
        }
    }
    
    /// Reset the flow
    public func reset() {
        state.reset()
        currentStep = .welcome
    }
    
    /// Check if current step can proceed
    public var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .scanQRCode:
            return state.providerConfig != nil || true // Can skip to manual selection
        case .selectProvider:
            return state.providerConfig != nil
        case .authenticate:
            return state.hasAccessToken
        case .reviewProfile:
            return state.userProfile != nil
        case .discoverInstances:
            return !state.isDiscoveringInstances
        case .selectInstance:
            return state.selectedInstance != nil || true // Can skip
        case .syncSettings:
            return true
        case .complete:
            return true
        }
    }
}
#endif

// MARK: - Default Steps

extension ClinicOnboardingStep {
    /// Default steps for clinic onboarding
    public static let defaultSteps: [ClinicOnboardingStep] = [
        ClinicOnboardingStep(
            type: .welcome,
            title: "Connect to Your Clinic",
            subtitle: "Sign in with your healthcare organization to sync your therapy settings",
            iconName: "building.2.fill"
        ),
        ClinicOnboardingStep(
            type: .scanQRCode,
            title: "Scan Clinic QR Code",
            subtitle: "Scan the QR code provided by your clinic or care team",
            iconName: "qrcode.viewfinder",
            isSkippable: true
        ),
        ClinicOnboardingStep(
            type: .selectProvider,
            title: "Select Your Provider",
            subtitle: "Choose your healthcare organization's identity provider",
            iconName: "person.badge.key.fill",
            isSkippable: true
        ),
        ClinicOnboardingStep(
            type: .authenticate,
            title: "Sign In",
            subtitle: "Sign in with your organization credentials",
            iconName: "lock.shield.fill"
        ),
        ClinicOnboardingStep(
            type: .reviewProfile,
            title: "Review Your Profile",
            subtitle: "Confirm your information from your healthcare provider",
            iconName: "person.crop.circle.badge.checkmark"
        ),
        ClinicOnboardingStep(
            type: .discoverInstances,
            title: "Finding Your Nightscout",
            subtitle: "Discovering Nightscout instances linked to your account",
            iconName: "magnifyingglass.circle"
        ),
        ClinicOnboardingStep(
            type: .selectInstance,
            title: "Select Nightscout Instance",
            subtitle: "Choose which Nightscout site to connect",
            iconName: "server.rack",
            isSkippable: true
        ),
        ClinicOnboardingStep(
            type: .syncSettings,
            title: "Sync Settings",
            subtitle: "Import your therapy settings from your clinic",
            iconName: "arrow.triangle.2.circlepath",
            isSkippable: true
        ),
        ClinicOnboardingStep(
            type: .complete,
            title: "All Set!",
            subtitle: "You're connected to your healthcare organization",
            iconName: "checkmark.circle.fill"
        )
    ]
}
