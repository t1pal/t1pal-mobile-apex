// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutConfigurationValidator.swift
// T1Pal Mobile
//
// Validates Nightscout URL and credentials before marking "configured"
// Requirements: APP-STATES-009

import Foundation

// MARK: - Validation Result

/// Result of Nightscout configuration validation
public struct NightscoutValidationResult: Sendable {
    /// Whether the configuration is valid
    public let isValid: Bool
    
    /// Validation errors (empty if valid)
    public let errors: [NightscoutValidationError]
    
    /// Server information if validation succeeded
    public let serverInfo: ServerInfo?
    
    public struct ServerInfo: Sendable {
        public let version: String?
        public let serverName: String?
        public let apiVersion: String?
        public let enabledPlugins: [String]
        
        public init(
            version: String? = nil,
            serverName: String? = nil,
            apiVersion: String? = nil,
            enabledPlugins: [String] = []
        ) {
            self.version = version
            self.serverName = serverName
            self.apiVersion = apiVersion
            self.enabledPlugins = enabledPlugins
        }
    }
    
    public init(isValid: Bool, errors: [NightscoutValidationError] = [], serverInfo: ServerInfo? = nil) {
        self.isValid = isValid
        self.errors = errors
        self.serverInfo = serverInfo
    }
    
    /// Create a successful result
    public static func success(serverInfo: ServerInfo) -> NightscoutValidationResult {
        NightscoutValidationResult(isValid: true, errors: [], serverInfo: serverInfo)
    }
    
    /// Create a failed result with errors
    public static func failure(_ errors: [NightscoutValidationError]) -> NightscoutValidationResult {
        NightscoutValidationResult(isValid: false, errors: errors, serverInfo: nil)
    }
    
    /// Create a failed result with a single error
    public static func failure(_ error: NightscoutValidationError) -> NightscoutValidationResult {
        failure([error])
    }
}

// MARK: - Validation Errors

/// Specific validation errors for Nightscout configuration
public enum NightscoutValidationError: Error, Sendable, Equatable {
    /// URL is empty or nil
    case urlEmpty
    
    /// URL format is invalid
    case urlInvalidFormat(String)
    
    /// URL must use HTTPS (HTTP not allowed for production)
    case urlNotHTTPS
    
    /// URL contains path components that may indicate incorrect entry
    case urlContainsPath(String)
    
    /// API secret is empty when required
    case apiSecretEmpty
    
    /// API secret format is invalid (should be hashed or specific length)
    case apiSecretInvalidFormat
    
    /// Server validation failed (could not connect)
    case serverUnreachable(String)
    
    /// Server returned invalid response
    case serverInvalidResponse
    
    /// Authentication failed
    case authenticationFailed
    
    /// Server is not a valid Nightscout instance
    case notNightscoutServer
    
    /// Server version is too old
    case serverVersionTooOld(String)
    
    public var localizedDescription: String {
        switch self {
        case .urlEmpty:
            return "Nightscout URL is required."
        case .urlInvalidFormat(let detail):
            return "Invalid URL format: \(detail)"
        case .urlNotHTTPS:
            return "Nightscout URL must use HTTPS for security."
        case .urlContainsPath(let path):
            return "URL should not contain path '\(path)'. Use just the server address."
        case .apiSecretEmpty:
            return "API secret is required for authentication."
        case .apiSecretInvalidFormat:
            return "API secret format is invalid."
        case .serverUnreachable(let detail):
            return "Could not connect to server: \(detail)"
        case .serverInvalidResponse:
            return "Server did not respond with valid Nightscout data."
        case .authenticationFailed:
            return "Authentication failed. Check your API secret."
        case .notNightscoutServer:
            return "The URL does not appear to be a Nightscout server."
        case .serverVersionTooOld(let version):
            return "Nightscout version \(version) is too old. Please update to 14.0 or newer."
        }
    }
}

// MARK: - Configuration Validator

/// Validates Nightscout URL and credentials before marking as configured
public struct NightscoutConfigurationValidator: Sendable {
    
    /// Minimum supported Nightscout version
    public static let minimumVersion = "14.0.0"
    
    /// Common incorrect path suffixes to detect
    private static let incorrectPathSuffixes = [
        "/api/v1",
        "/api/v3",
        "/api",
        "/entries",
        "/treatments",
        "/profile"
    ]
    
    public init() {}
    
    // MARK: - URL Validation
    
    /// Validate URL format without server check
    /// - Parameter urlString: The URL string to validate
    /// - Returns: Validation result with URL-only checks
    public func validateURL(_ urlString: String?) -> NightscoutValidationResult {
        var errors: [NightscoutValidationError] = []
        
        // Check empty
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            return .failure(.urlEmpty)
        }
        
        // Check URL format
        guard let url = URL(string: urlString) else {
            return .failure(.urlInvalidFormat("Could not parse URL"))
        }
        
        // Check scheme
        guard let scheme = url.scheme?.lowercased() else {
            return .failure(.urlInvalidFormat("Missing URL scheme (https://)"))
        }
        
        // Require HTTPS in production
        #if DEBUG
        // Allow HTTP in debug for local testing
        if scheme != "https" && scheme != "http" {
            errors.append(.urlInvalidFormat("URL must use https:// or http://"))
        }
        #else
        if scheme != "https" {
            errors.append(.urlNotHTTPS)
        }
        #endif
        
        // Check for host
        guard let host = url.host, !host.isEmpty else {
            errors.append(.urlInvalidFormat("Missing server address"))
            return .failure(errors)
        }
        
        // Warn about common incorrect paths
        let path = url.path
        if !path.isEmpty && path != "/" {
            for suffix in Self.incorrectPathSuffixes {
                if path.lowercased().hasPrefix(suffix) {
                    errors.append(.urlContainsPath(suffix))
                    break
                }
            }
        }
        
        if errors.isEmpty {
            return NightscoutValidationResult(isValid: true, errors: [])
        }
        return .failure(errors)
    }
    
    /// Validate API secret format (not authentication)
    /// - Parameter apiSecret: The API secret to validate
    /// - Returns: Validation result
    public func validateAPISecretFormat(_ apiSecret: String?) -> NightscoutValidationResult {
        guard let secret = apiSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return .failure(.apiSecretEmpty)
        }
        
        // API secret should be at least 12 characters (common minimum)
        // Can be plain text or SHA1 hashed (40 chars)
        if secret.count < 12 {
            return .failure(.apiSecretInvalidFormat)
        }
        
        return NightscoutValidationResult(isValid: true)
    }
    
    // MARK: - Full Validation
    
    /// Validate URL, credentials, and optionally server connectivity
    /// - Parameters:
    ///   - urlString: Nightscout server URL
    ///   - apiSecret: API secret (optional if using JWT)
    ///   - jwtToken: JWT token (optional if using API secret)
    ///   - checkServer: Whether to verify server connectivity
    ///   - discoveryClient: Client for server validation
    /// - Returns: Validation result
    public func validate(
        urlString: String?,
        apiSecret: String? = nil,
        jwtToken: String? = nil,
        checkServer: Bool = false,
        discoveryClient: InstanceDiscoveryClient? = nil
    ) async -> NightscoutValidationResult {
        var allErrors: [NightscoutValidationError] = []
        
        // Validate URL format
        let urlResult = validateURL(urlString)
        if !urlResult.isValid {
            allErrors.append(contentsOf: urlResult.errors)
        }
        
        // Validate credentials (need at least one auth method)
        let hasAPISecret = apiSecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        // JWT validation reserved for future use
        _ = jwtToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        
        if hasAPISecret {
            let secretResult = validateAPISecretFormat(apiSecret)
            if !secretResult.isValid {
                allErrors.append(contentsOf: secretResult.errors)
            }
        }
        
        // If we have URL errors, return early (can't check server)
        if !allErrors.isEmpty {
            return .failure(allErrors)
        }
        
        // Server connectivity check
        if checkServer, let client = discoveryClient,
           let urlString = urlString,
           let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            do {
                let response = try await client.validateInstance(url: url, apiSecret: apiSecret)
                
                if response.isValid {
                    // Check version if available
                    if let version = response.version {
                        if !isVersionSupported(version) {
                            allErrors.append(.serverVersionTooOld(version))
                            return .failure(allErrors)
                        }
                    }
                    
                    return .success(serverInfo: NightscoutValidationResult.ServerInfo(
                        version: response.version,
                        serverName: response.serverName,
                        apiVersion: response.apiVersion,
                        enabledPlugins: response.enabledPlugins ?? []
                    ))
                } else {
                    if let error = response.error {
                        if error.lowercased().contains("auth") {
                            allErrors.append(.authenticationFailed)
                        } else {
                            allErrors.append(.serverUnreachable(error))
                        }
                    } else {
                        allErrors.append(.notNightscoutServer)
                    }
                }
            } catch {
                allErrors.append(.serverUnreachable(error.localizedDescription))
            }
            
            return .failure(allErrors)
        }
        
        // URL-only validation passed
        return NightscoutValidationResult(isValid: true)
    }
    
    // MARK: - Version Check
    
    /// Check if server version is supported
    /// - Parameter versionString: Version string from server
    /// - Returns: True if version meets minimum requirements
    public func isVersionSupported(_ versionString: String) -> Bool {
        // Extract numeric version (e.g., "14.2.6" from "14.2.6-dev")
        let components = versionString.split(separator: "-").first ?? Substring(versionString)
        let versionParts = components.split(separator: ".").compactMap { Int($0) }
        let minimumParts = Self.minimumVersion.split(separator: ".").compactMap { Int($0) }
        
        // Compare major.minor.patch
        for i in 0..<max(versionParts.count, minimumParts.count) {
            let current = i < versionParts.count ? versionParts[i] : 0
            let minimum = i < minimumParts.count ? minimumParts[i] : 0
            
            if current > minimum { return true }
            if current < minimum { return false }
        }
        
        return true // Equal versions
    }
}
