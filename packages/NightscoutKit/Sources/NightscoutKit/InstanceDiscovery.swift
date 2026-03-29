// SPDX-License-Identifier: AGPL-3.0-or-later
//
// InstanceDiscovery.swift
// NightscoutKit
//
// Nightscout instance discovery after authentication
// Backlog: ID-NS-001
// Architecture: ID-RESEARCH-004-nightscout-binding.md
//
// This service discovers a user's Nightscout instances after OAuth login,
// supporting both T1Pal-hosted and self-hosted instances.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Instance Binding

/// Binding between a user identity and a Nightscout instance
public struct InstanceBinding: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    
    /// Instance URL
    public let url: URL
    
    /// User-friendly display name
    public let displayName: String
    
    /// User's role on this instance
    public let role: InstanceRole
    
    /// Permission level
    public let permissionLevel: PermissionLevel
    
    /// Whether this is the user's primary instance
    public let isPrimary: Bool
    
    /// Instance hosting type
    public let hostingType: HostingType
    
    /// When the binding was created
    public let createdAt: Date
    
    /// Last sync time
    public let lastSyncAt: Date?
    
    public init(
        id: String,
        url: URL,
        displayName: String,
        role: InstanceRole = .owner,
        permissionLevel: PermissionLevel = .full,
        isPrimary: Bool = false,
        hostingType: HostingType = .selfHosted,
        createdAt: Date = Date(),
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.role = role
        self.permissionLevel = permissionLevel
        self.isPrimary = isPrimary
        self.hostingType = hostingType
        self.createdAt = createdAt
        self.lastSyncAt = lastSyncAt
    }
}

// MARK: - Instance Role

/// User's role on a Nightscout instance
public enum InstanceRole: String, Codable, Sendable, CaseIterable {
    /// Created/registered the instance
    case owner = "owner"
    
    /// Full access granted by owner
    case admin = "admin"
    
    /// Follow and limited write access
    case caregiver = "caregiver"
    
    /// View-only access
    case readonly = "readonly"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .caregiver: return "Caregiver"
        case .readonly: return "Read Only"
        }
    }
    
    /// Whether this role can invite others
    public var canInvite: Bool {
        switch self {
        case .owner, .admin: return true
        case .caregiver, .readonly: return false
        }
    }
    
    /// Whether this role can modify settings
    public var canModifySettings: Bool {
        switch self {
        case .owner, .admin: return true
        case .caregiver, .readonly: return false
        }
    }
}

// MARK: - Permission Level

/// Permission level for instance access
public enum PermissionLevel: String, Codable, Sendable, CaseIterable {
    /// Full read/write access to all collections
    case full = "full"
    
    /// Read/write entries and treatments, read-only profile
    case readWrite = "read_write"
    
    /// Read-only access to all collections
    case readOnly = "read_only"
    
    /// Read-only access to entries (glucose) only
    case entriesOnly = "entries_only"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .full: return "Full Access"
        case .readWrite: return "Read & Write"
        case .readOnly: return "Read Only"
        case .entriesOnly: return "Glucose Only"
        }
    }
    
    /// Can write entries
    public var canWriteEntries: Bool {
        self == .full || self == .readWrite
    }
    
    /// Can write treatments
    public var canWriteTreatments: Bool {
        self == .full || self == .readWrite
    }
    
    /// Can read profile
    public var canReadProfile: Bool {
        self != .entriesOnly
    }
}

// MARK: - Hosting Type

/// Type of Nightscout hosting
public enum HostingType: String, Codable, Sendable, CaseIterable {
    /// Self-hosted instance (user's own server)
    case selfHosted = "self_hosted"
    
    /// T1Pal managed hosting
    case t1palHosted = "t1pal_hosted"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .selfHosted: return "Self-Hosted"
        case .t1palHosted: return "T1Pal Hosted"
        }
    }
}

// MARK: - Discovery Response

/// Response from instance discovery endpoint
public struct DiscoveryResponse: Codable, Sendable {
    /// User's bound instances
    public let instances: [InstanceBinding]
    
    /// Total instance count
    public let totalCount: Int
    
    /// Whether user has more instances (pagination)
    public let hasMore: Bool
    
    public init(instances: [InstanceBinding], totalCount: Int? = nil, hasMore: Bool = false) {
        self.instances = instances
        self.totalCount = totalCount ?? instances.count
        self.hasMore = hasMore
    }
}

// MARK: - Validation Response

/// Response from self-hosted instance validation
public struct ValidationResponse: Codable, Sendable {
    /// Whether the URL is a valid Nightscout server
    public let isValid: Bool
    
    /// Nightscout version
    public let version: String?
    
    /// Server name
    public let serverName: String?
    
    /// Available API version (v1, v3)
    public let apiVersion: String?
    
    /// Enabled plugins
    public let enabledPlugins: [String]?
    
    /// Error message if invalid
    public let error: String?
    
    public init(
        isValid: Bool,
        version: String? = nil,
        serverName: String? = nil,
        apiVersion: String? = nil,
        enabledPlugins: [String]? = nil,
        error: String? = nil
    ) {
        self.isValid = isValid
        self.version = version
        self.serverName = serverName
        self.apiVersion = apiVersion
        self.enabledPlugins = enabledPlugins
        self.error = error
    }
}

// MARK: - Discovery Error

/// Errors from instance discovery
public enum DiscoveryError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case networkError(String)
    case invalidResponse
    case serverError(Int, String?)
    case instanceNotFound
    case validationFailed(String)
    case alreadyBound
    case insufficientPermission
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to discover Nightscout instances."
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .instanceNotFound:
            return "Nightscout instance not found."
        case .validationFailed(let reason):
            return "Instance validation failed: \(reason)"
        case .alreadyBound:
            return "This instance is already connected to your account."
        case .insufficientPermission:
            return "You don't have permission to perform this action."
        }
    }
}

// MARK: - Discovery Client Protocol

/// Protocol for instance discovery operations
public protocol InstanceDiscoveryClient: Sendable {
    /// Discover all instances bound to the current user
    func discoverInstances() async throws -> DiscoveryResponse
    
    /// Validate a self-hosted Nightscout URL
    func validateInstance(url: URL, apiSecret: String?) async throws -> ValidationResponse
    
    /// Bind a self-hosted instance to the current user
    func bindInstance(
        url: URL,
        apiSecret: String,
        displayName: String
    ) async throws -> InstanceBinding
    
    /// Unbind an instance from the current user
    func unbindInstance(id: String) async throws
    
    /// Get the primary instance for the current user
    func getPrimaryInstance() async throws -> InstanceBinding?
    
    /// Set an instance as primary
    func setPrimaryInstance(id: String) async throws
}

// MARK: - Mock Discovery Client

/// Mock implementation for testing and development
public actor MockDiscoveryClient: InstanceDiscoveryClient {
    private var bindings: [String: InstanceBinding] = [:]
    private var primaryId: String?
    
    public init() {}
    
    /// Add a pre-configured binding for testing
    public func addBinding(_ binding: InstanceBinding) {
        bindings[binding.id] = binding
        if binding.isPrimary {
            primaryId = binding.id
        }
    }
    
    public func discoverInstances() async throws -> DiscoveryResponse {
        let instances = Array(bindings.values).sorted { $0.createdAt < $1.createdAt }
        return DiscoveryResponse(instances: instances)
    }
    
    public func validateInstance(url: URL, apiSecret: String?) async throws -> ValidationResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Simple validation: URL must start with https
        guard url.scheme == "https" || url.scheme == "http" else {
            return ValidationResponse(isValid: false, error: "URL must use HTTPS")
        }
        
        // Mock successful validation
        return ValidationResponse(
            isValid: true,
            version: "15.0.2",
            serverName: url.host ?? "Nightscout",
            apiVersion: "v3",
            enabledPlugins: ["careportal", "iob", "cob", "pump"]
        )
    }
    
    public func bindInstance(
        url: URL,
        apiSecret: String,
        displayName: String
    ) async throws -> InstanceBinding {
        // Check if already bound
        for binding in bindings.values {
            if binding.url == url {
                throw DiscoveryError.alreadyBound
            }
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let binding = InstanceBinding(
            id: UUID().uuidString,
            url: url,
            displayName: displayName,
            role: .owner,
            permissionLevel: .full,
            isPrimary: bindings.isEmpty,  // First instance is primary
            hostingType: .selfHosted,
            createdAt: Date()
        )
        
        bindings[binding.id] = binding
        if binding.isPrimary {
            primaryId = binding.id
        }
        
        return binding
    }
    
    public func unbindInstance(id: String) async throws {
        guard bindings[id] != nil else {
            throw DiscoveryError.instanceNotFound
        }
        
        bindings.removeValue(forKey: id)
        
        // If we removed the primary, pick a new one
        if primaryId == id {
            primaryId = bindings.keys.first
        }
    }
    
    public func getPrimaryInstance() async throws -> InstanceBinding? {
        guard let id = primaryId else { return nil }
        return bindings[id]
    }
    
    public func setPrimaryInstance(id: String) async throws {
        guard bindings[id] != nil else {
            throw DiscoveryError.instanceNotFound
        }
        
        // Update all bindings
        for (bindingId, binding) in bindings {
            let newBinding = InstanceBinding(
                id: binding.id,
                url: binding.url,
                displayName: binding.displayName,
                role: binding.role,
                permissionLevel: binding.permissionLevel,
                isPrimary: bindingId == id,
                hostingType: binding.hostingType,
                createdAt: binding.createdAt,
                lastSyncAt: binding.lastSyncAt
            )
            bindings[bindingId] = newBinding
        }
        
        primaryId = id
    }
}

// MARK: - Live Discovery Client

/// Production implementation connecting to T1Pal discovery API
public actor LiveDiscoveryClient: InstanceDiscoveryClient {
    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?
    
    public init(
        baseURL: URL = URL(string: "https://api.t1pal.com/discover")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }
    
    /// Set the access token for authenticated requests
    public func setAccessToken(_ token: String?) {
        self.accessToken = token
    }
    
    public func discoverInstances() async throws -> DiscoveryResponse {
        guard let token = accessToken else {
            throw DiscoveryError.notAuthenticated
        }
        
        let url = baseURL.appendingPathComponent("instances")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DiscoveryResponse.self, from: data)
        case 401:
            throw DiscoveryError.notAuthenticated
        default:
            let message = String(data: data, encoding: .utf8)
            throw DiscoveryError.serverError(httpResponse.statusCode, message)
        }
    }
    
    public func validateInstance(url: URL, apiSecret: String?) async throws -> ValidationResponse {
        let validateURL = baseURL.appendingPathComponent("validate")
        var request = URLRequest(url: validateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct ValidateRequest: Encodable {
            let url: String
            let apiSecret: String?
        }
        
        let body = ValidateRequest(url: url.absoluteString, apiSecret: apiSecret)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(ValidationResponse.self, from: data)
        default:
            let message = String(data: data, encoding: .utf8)
            throw DiscoveryError.serverError(httpResponse.statusCode, message)
        }
    }
    
    public func bindInstance(
        url: URL,
        apiSecret: String,
        displayName: String
    ) async throws -> InstanceBinding {
        guard let token = accessToken else {
            throw DiscoveryError.notAuthenticated
        }
        
        let bindURL = baseURL.appendingPathComponent("instances")
        var request = URLRequest(url: bindURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct BindRequest: Encodable {
            let url: String
            let apiSecret: String
            let displayName: String
        }
        
        let body = BindRequest(url: url.absoluteString, apiSecret: apiSecret, displayName: displayName)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 201:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(InstanceBinding.self, from: data)
        case 401:
            throw DiscoveryError.notAuthenticated
        case 409:
            throw DiscoveryError.alreadyBound
        default:
            let message = String(data: data, encoding: .utf8)
            throw DiscoveryError.serverError(httpResponse.statusCode, message)
        }
    }
    
    public func unbindInstance(id: String) async throws {
        guard let token = accessToken else {
            throw DiscoveryError.notAuthenticated
        }
        
        let unbindURL = baseURL.appendingPathComponent("instances/\(id)")
        var request = URLRequest(url: unbindURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 204:
            return
        case 401:
            throw DiscoveryError.notAuthenticated
        case 404:
            throw DiscoveryError.instanceNotFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw DiscoveryError.serverError(httpResponse.statusCode, message)
        }
    }
    
    public func getPrimaryInstance() async throws -> InstanceBinding? {
        let response = try await discoverInstances()
        return response.instances.first { $0.isPrimary }
    }
    
    public func setPrimaryInstance(id: String) async throws {
        guard let token = accessToken else {
            throw DiscoveryError.notAuthenticated
        }
        
        let primaryURL = baseURL.appendingPathComponent("instances/\(id)/primary")
        var request = URLRequest(url: primaryURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200, 204:
            return
        case 401:
            throw DiscoveryError.notAuthenticated
        case 404:
            throw DiscoveryError.instanceNotFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw DiscoveryError.serverError(httpResponse.statusCode, message)
        }
    }
}
