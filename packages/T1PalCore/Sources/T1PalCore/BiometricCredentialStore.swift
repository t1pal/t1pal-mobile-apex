// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// BiometricCredentialStore.swift
// T1PalCore
//
// Biometric-protected credential storage using Face ID/Touch ID.
// Wraps KeychainCredentialStore with LAContext authentication.
// Trace: ID-KEYCHAIN-003, PRD-003, REQ-ID-002

import Foundation

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - Biometric Auth Result

/// Result of biometric authentication attempt
public enum BiometricAuthResult: Sendable {
    case success
    case cancelled
    case failed(BiometricError)
    case notAvailable(BiometricError)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Biometric authentication errors
public enum BiometricError: Error, Sendable, LocalizedError, Equatable {
    case notAvailable
    case notEnrolled
    case lockout
    case cancelled
    case authenticationFailed
    case passcodeNotSet
    case systemCancel
    case userFallback
    case invalidContext
    case unknown(Int)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return "No biometric credentials are enrolled."
        case .lockout:
            return "Biometric authentication is locked due to too many failed attempts."
        case .cancelled:
            return "Authentication was cancelled by the user."
        case .authenticationFailed:
            return "Biometric authentication failed."
        case .passcodeNotSet:
            return "Device passcode is not set."
        case .systemCancel:
            return "Authentication was cancelled by the system."
        case .userFallback:
            return "User chose to use fallback authentication."
        case .invalidContext:
            return "Authentication context is invalid."
        case .unknown(let code):
            return "Unknown authentication error (code: \(code))."
        }
    }
    
    #if canImport(LocalAuthentication)
    /// Create from LAError
    public static func from(_ error: LAError) -> BiometricError {
        switch error.code {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockout
        case .userCancel:
            return .cancelled
        case .authenticationFailed:
            return .authenticationFailed
        case .passcodeNotSet:
            return .passcodeNotSet
        case .systemCancel:
            return .systemCancel
        case .userFallback:
            return .userFallback
        case .invalidContext:
            return .invalidContext
        default:
            return .unknown(error.code.rawValue)
        }
    }
    #endif
}

/// Biometric type available on device
public enum BiometricType: String, Sendable, Codable {
    case none
    case touchID
    case faceID
    case opticID  // Vision Pro
    
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
    
    public var systemImageName: String {
        switch self {
        case .none: return "lock"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

// MARK: - Biometric Credential Store

/// Credential store with biometric authentication for sensitive operations.
/// Wraps KeychainCredentialStore and requires Face ID/Touch ID for retrieval.
///
/// Trace: ID-KEYCHAIN-003
/// Requirements: REQ-ID-002
public actor BiometricCredentialStore {
    
    /// Underlying Keychain store
    private let keychainStore: KeychainCredentialStore
    
    /// Reason shown in biometric prompt
    private let authReason: String
    
    /// Whether biometric is required for all retrievals
    private let requireBiometricForRetrieval: Bool
    
    // MARK: - Initialization
    
    /// Create a biometric credential store
    /// - Parameters:
    ///   - keychainStore: Underlying Keychain store
    ///   - authReason: Reason shown in biometric prompt
    ///   - requireBiometricForRetrieval: Whether to require biometric for all retrievals
    public init(
        keychainStore: KeychainCredentialStore = KeychainCredentialStore(),
        authReason: String = "Authenticate to access your credentials",
        requireBiometricForRetrieval: Bool = true
    ) {
        self.keychainStore = keychainStore
        self.authReason = authReason
        self.requireBiometricForRetrieval = requireBiometricForRetrieval
    }
    
    // MARK: - Biometric Status
    
    /// Check what biometric type is available
    public nonisolated func availableBiometricType() -> BiometricType {
        #if canImport(LocalAuthentication) && !os(Linux)
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
        #else
        return .none
        #endif
    }
    
    /// Check if biometric authentication is available
    public nonisolated func isBiometricAvailable() -> Bool {
        availableBiometricType() != .none
    }
    
    /// Check if biometric can be evaluated (not locked out)
    public nonisolated func canAuthenticate() -> (available: Bool, error: BiometricError?) {
        #if canImport(LocalAuthentication) && !os(Linux)
        let context = LAContext()
        var error: NSError?
        
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if canEvaluate {
            return (true, nil)
        }
        
        if let laError = error as? LAError {
            return (false, BiometricError.from(laError))
        }
        
        return (false, .notAvailable)
        #else
        return (false, .notAvailable)
        #endif
    }
    
    // MARK: - Authentication
    
    /// Authenticate with biometrics
    /// - Returns: Authentication result
    public func authenticate() async -> BiometricAuthResult {
        #if canImport(LocalAuthentication) && !os(Linux)
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError {
                return .notAvailable(BiometricError.from(laError))
            }
            return .notAvailable(.notAvailable)
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: authReason
            )
            
            return success ? .success : .failed(.authenticationFailed)
        } catch let error as LAError {
            if error.code == .userCancel {
                return .cancelled
            }
            return .failed(BiometricError.from(error))
        } catch {
            return .failed(.unknown(-1))
        }
        #else
        // Linux/non-Darwin: biometric not available
        return .notAvailable(.notAvailable)
        #endif
    }
    
    // MARK: - Credential Operations
    
    /// Store a credential (no biometric required for store)
    public func store(_ credential: AuthCredential, for key: CredentialKey) async throws {
        try await keychainStore.store(credential, for: key)
    }
    
    /// Retrieve a credential with optional biometric authentication
    /// - Parameters:
    ///   - key: Credential key
    ///   - skipBiometric: Skip biometric check (for non-sensitive operations)
    /// - Returns: The credential
    public func retrieve(for key: CredentialKey, skipBiometric: Bool = false) async throws -> AuthCredential {
        // Check if biometric is required
        if requireBiometricForRetrieval && !skipBiometric && isBiometricAvailable() {
            let authResult = await authenticate()
            
            switch authResult {
            case .success:
                break // Continue to retrieve
            case .cancelled:
                throw CredentialStoreError.accessDenied
            case .failed(let error):
                throw CredentialStoreError.storageFailed("Biometric failed: \(error.localizedDescription)")
            case .notAvailable:
                // Fall through to retrieval if biometric not available
                break
            }
        }
        
        return try await keychainStore.retrieve(for: key)
    }
    
    /// Retrieve credential without biometric check
    public func retrieveWithoutBiometric(for key: CredentialKey) async throws -> AuthCredential {
        try await retrieve(for: key, skipBiometric: true)
    }
    
    /// Delete a credential (no biometric required)
    public func delete(for key: CredentialKey) async throws {
        try await keychainStore.delete(for: key)
    }
    
    /// Check if credential exists
    public func exists(for key: CredentialKey) async -> Bool {
        await keychainStore.exists(for: key)
    }
    
    /// List all keys for a service
    public func allKeys(for service: String) async throws -> [CredentialKey] {
        try await keychainStore.allKeys(for: service)
    }
    
    /// Clear all credentials
    public func clearAll() async throws {
        try await keychainStore.clearAll()
    }
    
    /// Get count of stored credentials
    public func count() async -> Int {
        await keychainStore.count()
    }
}

// MARK: - Factory Methods

extension BiometricCredentialStore {
    
    /// Create a biometric store for Nightscout credentials
    public static var nightscout: BiometricCredentialStore {
        BiometricCredentialStore(
            keychainStore: .nightscout,
            authReason: "Authenticate to access your Nightscout credentials"
        )
    }
    
    /// Create a biometric store for OAuth2 tokens
    public static var oauth2: BiometricCredentialStore {
        BiometricCredentialStore(
            keychainStore: .oauth2,
            authReason: "Authenticate to access your account"
        )
    }
    
    /// Create a biometric store that doesn't require biometric for retrieval
    public static func withOptionalBiometric(
        keychainStore: KeychainCredentialStore = KeychainCredentialStore()
    ) -> BiometricCredentialStore {
        BiometricCredentialStore(
            keychainStore: keychainStore,
            requireBiometricForRetrieval: false
        )
    }
}

// MARK: - Biometric Settings

/// User preferences for biometric authentication
public struct BiometricSettings: Codable, Sendable {
    /// Whether biometric is enabled for credential access
    public var isEnabled: Bool
    
    /// Whether to require biometric for each access vs session-based
    public var requirePerAccess: Bool
    
    /// Timeout for session-based authentication (seconds)
    public var sessionTimeout: TimeInterval
    
    /// Whether to allow passcode fallback
    public var allowPasscodeFallback: Bool
    
    public init(
        isEnabled: Bool = true,
        requirePerAccess: Bool = false,
        sessionTimeout: TimeInterval = 300,  // 5 minutes
        allowPasscodeFallback: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.requirePerAccess = requirePerAccess
        self.sessionTimeout = sessionTimeout
        self.allowPasscodeFallback = allowPasscodeFallback
    }
    
    public static let `default` = BiometricSettings()
}
