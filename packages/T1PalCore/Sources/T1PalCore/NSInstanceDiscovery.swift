// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NSInstanceDiscovery.swift
// T1PalCore
//
// Protocol for Nightscout instance discovery after authentication.
// Implementations provided by NightscoutKit.
//
// Trace: PRD-003, REQ-ID-004, REQ-ID-005

import Foundation

// MARK: - Instance Types

/// A discovered Nightscout instance binding
public struct NSInstanceBinding: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    
    /// Instance URL
    public let url: URL
    
    /// User-friendly display name
    public let displayName: String
    
    /// User's role on this instance
    public let role: NSInstanceRole
    
    /// Whether this is the user's primary instance
    public let isPrimary: Bool
    
    /// Instance hosting type
    public let hostingType: NSHostingType
    
    /// When the binding was created
    public let createdAt: Date
    
    public init(
        id: String,
        url: URL,
        displayName: String,
        role: NSInstanceRole = .owner,
        isPrimary: Bool = false,
        hostingType: NSHostingType = .selfHosted,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.role = role
        self.isPrimary = isPrimary
        self.hostingType = hostingType
        self.createdAt = createdAt
    }
}

/// User's role on a Nightscout instance
public enum NSInstanceRole: String, Codable, Sendable, CaseIterable {
    /// Owner/admin of the instance
    case owner
    /// Caregiver with read/write access
    case caregiver
    /// Follower with read-only access
    case follower
    /// Healthcare provider
    case provider
    
    public var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .caregiver: return "Caregiver"
        case .follower: return "Follower"
        case .provider: return "Healthcare Provider"
        }
    }
    
    public var canWriteTreatments: Bool {
        switch self {
        case .owner, .caregiver, .provider: return true
        case .follower: return false
        }
    }
}

/// Instance hosting type
public enum NSHostingType: String, Codable, Sendable, CaseIterable {
    /// Hosted by T1Pal
    case t1palHosted
    /// Self-hosted
    case selfHosted
    /// Heroku-hosted
    case heroku
    /// Other hosting provider
    case other
    
    public var displayName: String {
        switch self {
        case .t1palHosted: return "T1Pal Hosted"
        case .selfHosted: return "Self-Hosted"
        case .heroku: return "Heroku"
        case .other: return "Other"
        }
    }
}

// MARK: - Discovery Response

/// Response from instance discovery
public struct NSDiscoveryResponse: Codable, Sendable {
    /// Discovered instances
    public let instances: [NSInstanceBinding]
    
    /// Total count (may differ from instances.count if paginated)
    public let totalCount: Int
    
    /// Whether more instances are available
    public let hasMore: Bool
    
    public init(instances: [NSInstanceBinding], totalCount: Int? = nil, hasMore: Bool = false) {
        self.instances = instances
        self.totalCount = totalCount ?? instances.count
        self.hasMore = hasMore
    }
}

// MARK: - Validation Response

/// Response from instance validation
public struct NSValidationResponse: Codable, Sendable {
    /// Whether the instance is valid and reachable
    public let isValid: Bool
    
    /// Nightscout version if available
    public let version: String?
    
    /// API capabilities
    public let capabilities: [String]
    
    /// Error message if validation failed
    public let error: String?
    
    public init(isValid: Bool, version: String? = nil, capabilities: [String] = [], error: String? = nil) {
        self.isValid = isValid
        self.version = version
        self.capabilities = capabilities
        self.error = error
    }
}

// MARK: - Discovery Protocol

/// Protocol for Nightscout instance discovery
/// Implementations in NightscoutKit (LiveDiscoveryClient, MockDiscoveryClient)
public protocol NSInstanceDiscoveryProtocol: Sendable {
    /// Discover user's Nightscout instances after authentication
    /// - Returns: Discovery response with instances
    /// - Throws: NSDiscoveryError if discovery fails
    func discoverInstances() async throws -> NSDiscoveryResponse
    
    /// Validate a Nightscout instance URL
    /// - Parameters:
    ///   - url: Instance URL to validate
    ///   - apiSecret: Optional API secret
    /// - Returns: Validation response
    func validateInstance(url: URL, apiSecret: String?) async throws -> NSValidationResponse
    
    /// Set the access token for authenticated requests
    func setAccessToken(_ token: String?) async
}

// MARK: - Discovery Errors

/// Errors during Nightscout instance discovery
public enum NSDiscoveryError: Error, LocalizedError, Sendable {
    /// Not authenticated (no access token)
    case notAuthenticated
    /// Network request failed
    case networkError(String)
    /// Server returned an error
    case serverError(Int, String?)
    /// Invalid response from server
    case invalidResponse
    /// Instance not found
    case instanceNotFound
    /// Instance validation failed
    case validationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in first."
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .invalidResponse:
            return "Invalid response from server."
        case .instanceNotFound:
            return "Nightscout instance not found."
        case .validationFailed(let detail):
            return "Instance validation failed: \(detail)"
        }
    }
}

// MARK: - Mock Implementation

/// Mock implementation for testing
public actor MockNSDiscoveryClient: NSInstanceDiscoveryProtocol {
    private var mockInstances: [NSInstanceBinding] = []
    private var accessToken: String?
    private var shouldFail = false
    private var failureError: NSDiscoveryError?
    
    public init() {}
    
    /// Configure mock instances
    public func setMockInstances(_ instances: [NSInstanceBinding]) {
        self.mockInstances = instances
    }
    
    /// Configure failure mode
    public func setFailure(_ error: NSDiscoveryError?) {
        self.shouldFail = error != nil
        self.failureError = error
    }
    
    public func setAccessToken(_ token: String?) {
        self.accessToken = token
    }
    
    public func discoverInstances() async throws -> NSDiscoveryResponse {
        guard accessToken != nil else {
            throw NSDiscoveryError.notAuthenticated
        }
        
        if shouldFail, let error = failureError {
            throw error
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        return NSDiscoveryResponse(instances: mockInstances)
    }
    
    public func validateInstance(url: URL, apiSecret: String?) async throws -> NSValidationResponse {
        if shouldFail, let error = failureError {
            throw error
        }
        
        // Simulate validation
        return NSValidationResponse(
            isValid: true,
            version: "15.0.2",
            capabilities: ["careportal", "rawbg", "iob", "cob"]
        )
    }
}
