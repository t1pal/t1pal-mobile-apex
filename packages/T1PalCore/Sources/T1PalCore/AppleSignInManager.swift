// SPDX-License-Identifier: AGPL-3.0-or-later
// AppleSignInManager.swift
// T1PalCore
//
// Sign in with Apple authentication flow for account linking
// Trace: FOLLOW-IAP-006, PRD-028-apple-iap-integration, REQ-IAP-006

#if canImport(AuthenticationServices)
import Foundation
import AuthenticationServices

// MARK: - Apple Sign In Result

/// Result of Sign in with Apple authentication
public struct AppleSignInResult: Sendable {
    /// Apple's stable user identifier (sub claim)
    public let userIdentifier: String
    
    /// User's full name (only provided on first authorization)
    public let fullName: PersonNameComponents?
    
    /// User's email (only provided on first authorization)
    public let email: String?
    
    /// Identity token (JWT) for backend verification
    public let identityToken: Data?
    
    /// Authorization code for backend token exchange
    public let authorizationCode: Data?
    
    public init(
        userIdentifier: String,
        fullName: PersonNameComponents? = nil,
        email: String? = nil,
        identityToken: Data? = nil,
        authorizationCode: Data? = nil
    ) {
        self.userIdentifier = userIdentifier
        self.fullName = fullName
        self.email = email
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }
    
    /// Identity token as string for API calls
    public var identityTokenString: String? {
        guard let data = identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Authorization code as string for API calls
    public var authorizationCodeString: String? {
        guard let data = authorizationCode else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Apple Sign In Error

/// Errors from Sign in with Apple flow
public enum AppleSignInError: Error, Sendable, LocalizedError {
    case cancelled
    case failed(String)
    case invalidResponse
    case missingCredential
    case notAvailable
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled."
        case .failed(let reason):
            return "Sign in failed: \(reason)"
        case .invalidResponse:
            return "Invalid response from Apple."
        case .missingCredential:
            return "Missing Apple credential."
        case .notAvailable:
            return "Sign in with Apple is not available."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

// MARK: - Apple Sign In Credential State

/// Current state of Apple credential
public enum AppleCredentialState: Sendable {
    case authorized
    case revoked
    case notFound
    case transferred
    case unknown
}

// MARK: - Apple Sign In Manager

/// Manages Sign in with Apple authentication flow
/// Trace: FOLLOW-IAP-006
public actor AppleSignInManager {
    
    /// Shared instance for convenience
    public static let shared = AppleSignInManager()
    
    /// Storage key for user identifier
    private static let userIdKey = "apple_user_identifier"
    
    /// Stored user identifier (persisted across sessions)
    public var storedUserIdentifier: String? {
        get { UserDefaults.standard.string(forKey: Self.userIdKey) }
    }
    
    private init() {}
    
    // MARK: - Credential State
    
    /// Check current credential state for a stored user
    public func getCredentialState() async -> AppleCredentialState {
        guard let userId = storedUserIdentifier else {
            return .notFound
        }
        return await getCredentialState(for: userId)
    }
    
    /// Check credential state for a specific user identifier
    public func getCredentialState(for userIdentifier: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: userIdentifier) { state, _ in
                let result: AppleCredentialState
                switch state {
                case .authorized:
                    result = .authorized
                case .revoked:
                    result = .revoked
                case .notFound:
                    result = .notFound
                case .transferred:
                    result = .transferred
                @unknown default:
                    result = .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Sign In
    
    /// Perform Sign in with Apple
    /// - Parameter requestedScopes: Scopes to request (fullName, email)
    /// - Returns: Sign in result with user info and tokens
    @MainActor
    public func signIn(
        requestedScopes: [ASAuthorization.Scope] = [.fullName, .email]
    ) async throws -> AppleSignInResult {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = requestedScopes
        
        let delegate = SignInDelegate()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        
        // Find a presentation anchor
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first {
            let contextProvider = PresentationContextProvider(window: window)
            controller.presentationContextProvider = contextProvider
        }
        #endif
        
        controller.performRequests()
        
        let result = try await delegate.result()
        
        // Store user identifier for future credential state checks
        await storeUserIdentifier(result.userIdentifier)
        
        return result
    }
    
    // MARK: - Sign Out
    
    /// Clear stored Apple credential
    public func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
    }
    
    // MARK: - Private
    
    private func storeUserIdentifier(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: Self.userIdKey)
    }
}

// MARK: - Sign In Delegate

private final class SignInDelegate: NSObject, ASAuthorizationControllerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    
    func result() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.invalidResponse)
            return
        }
        
        let result = AppleSignInResult(
            userIdentifier: credential.user,
            fullName: credential.fullName,
            email: credential.email,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode
        )
        
        continuation?.resume(returning: result)
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let authError = error as? ASAuthorizationError
        
        switch authError?.code {
        case .canceled:
            continuation?.resume(throwing: AppleSignInError.cancelled)
        case .failed:
            continuation?.resume(throwing: AppleSignInError.failed(error.localizedDescription))
        case .invalidResponse:
            continuation?.resume(throwing: AppleSignInError.invalidResponse)
        case .notHandled:
            continuation?.resume(throwing: AppleSignInError.failed("Request not handled"))
        case .notInteractive:
            continuation?.resume(throwing: AppleSignInError.failed("Non-interactive authorization"))
        case .unknown:
            continuation?.resume(throwing: AppleSignInError.unknown)
        default:
            continuation?.resume(throwing: AppleSignInError.failed(error.localizedDescription))
        }
    }
}

// MARK: - Presentation Context Provider

#if os(iOS)
private final class PresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    private let window: UIWindow
    
    init(window: UIWindow) {
        self.window = window
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }
}
#endif

// MARK: - T1PalErrorProtocol Conformance

extension AppleSignInError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .auth }
    
    public var code: String {
        switch self {
        case .cancelled: return "APPLE-CANCELLED"
        case .failed: return "APPLE-FAILED"
        case .invalidResponse: return "APPLE-RESPONSE-001"
        case .missingCredential: return "APPLE-CRED-001"
        case .notAvailable: return "APPLE-UNAVAIL-001"
        case .unknown: return "APPLE-UNKNOWN"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .cancelled: return .info
        case .failed: return .error
        case .invalidResponse, .missingCredential: return .error
        case .notAvailable: return .warning
        case .unknown: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .cancelled: return .none
        case .failed, .invalidResponse, .unknown: return .retry
        case .missingCredential: return .reauthenticate
        case .notAvailable: return .none
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown Apple Sign In error"
    }
}

#endif // canImport(AuthenticationServices)
