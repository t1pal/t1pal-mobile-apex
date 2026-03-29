// SPDX-License-Identifier: AGPL-3.0-or-later
//
// InstanceProvisioning.swift
// T1Pal Mobile
//
// Managed Nightscout instance provisioning API client
// Requirements: BIZ-004, PRD-015 (REQ-PROV-001 through REQ-PROV-003)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Types

/// Hosting region for managed Nightscout instances
public enum HostingRegion: String, Codable, Sendable, CaseIterable {
    case usEast = "US East"
    case usWest = "US West"
    case euWest = "EU West"
    case apacSydney = "APAC Sydney"
}

/// Status of a managed Nightscout instance
public enum InstanceStatus: String, Codable, Sendable {
    case provisioning    // Being created
    case running         // Active and healthy
    case suspended       // Payment issue
    case maintenance     // Scheduled downtime
    case error           // Needs attention
}

/// Configuration for a managed Nightscout instance
public struct NightscoutInstanceConfig: Codable, Sendable {
    public var subdomain: String           // mysite.t1pal.org
    public var region: HostingRegion       // US, EU, APAC
    public var displayUnits: String        // mg/dL or mmol/L
    public var targetLow: Int              // 70
    public var targetHigh: Int             // 180
    public var enabledPlugins: [String]    // careportal, pump, etc.
    
    public init(
        subdomain: String,
        region: HostingRegion = .usEast,
        displayUnits: String = "mg/dL",
        targetLow: Int = 70,
        targetHigh: Int = 180,
        enabledPlugins: [String] = ["careportal", "iob", "cob"]
    ) {
        self.subdomain = subdomain
        self.region = region
        self.displayUnits = displayUnits
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.enabledPlugins = enabledPlugins
    }
}

/// A managed Nightscout instance
public struct ManagedInstance: Identifiable, Codable, Sendable {
    public let id: UUID
    public var config: NightscoutInstanceConfig
    public var status: InstanceStatus
    public var url: URL
    public var apiSecret: String           // Stored in Keychain
    public var createdAt: Date
    public var lastAccessedAt: Date?
    
    public init(
        id: UUID = UUID(),
        config: NightscoutInstanceConfig,
        status: InstanceStatus = .provisioning,
        url: URL,
        apiSecret: String,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.config = config
        self.status = status
        self.url = url
        self.apiSecret = apiSecret
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}

// MARK: - Protocol

/// Protocol for instance provisioning operations
public protocol ProvisioningClient: Sendable {
    /// List all managed instances for the current user
    func listInstances() async throws -> [ManagedInstance]
    
    /// Create a new managed instance
    func createInstance(config: NightscoutInstanceConfig) async throws -> ManagedInstance
    
    /// Get details for a specific instance
    func getInstance(id: UUID) async throws -> ManagedInstance
    
    /// Update instance configuration
    func updateInstance(id: UUID, config: NightscoutInstanceConfig) async throws -> ManagedInstance
    
    /// Delete a managed instance
    func deleteInstance(id: UUID) async throws
    
    /// Check if a subdomain is available
    func checkSubdomainAvailable(subdomain: String) async throws -> Bool
}

// MARK: - Errors

public enum ProvisioningError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case insufficientTier           // Need Silver+ for provisioning
    case subdomainTaken
    case invalidConfiguration(String)
    case provisioningFailed(String)
    case instanceNotFound
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to manage Nightscout instances."
        case .insufficientTier:
            return "Managed Nightscout hosting requires a Silver or Gold subscription."
        case .subdomainTaken:
            return "This subdomain is already taken. Please choose another."
        case .invalidConfiguration(let reason):
            return "Invalid instance configuration: \(reason)"
        case .provisioningFailed(let reason):
            return "Failed to provision instance: \(reason)"
        case .instanceNotFound:
            return "Nightscout instance not found."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Mock Implementation

/// Mock implementation for testing and development
public actor MockProvisioningClient: ProvisioningClient {
    private var instances: [UUID: ManagedInstance] = [:]
    private var usedSubdomains: Set<String> = []
    
    public init() {}
    
    public func listInstances() async throws -> [ManagedInstance] {
        Array(instances.values)
    }
    
    public func createInstance(config: NightscoutInstanceConfig) async throws -> ManagedInstance {
        guard !usedSubdomains.contains(config.subdomain) else {
            throw ProvisioningError.subdomainTaken
        }
        
        // Simulate provisioning delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        let instance = ManagedInstance(
            id: UUID(),
            config: config,
            status: .running,
            url: URL(string: "https://\(config.subdomain).t1pal.org")!,
            apiSecret: UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased() + "",
            createdAt: Date()
        )
        
        instances[instance.id] = instance
        usedSubdomains.insert(config.subdomain)
        
        return instance
    }
    
    public func getInstance(id: UUID) async throws -> ManagedInstance {
        guard let instance = instances[id] else {
            throw ProvisioningError.instanceNotFound
        }
        return instance
    }
    
    public func updateInstance(id: UUID, config: NightscoutInstanceConfig) async throws -> ManagedInstance {
        guard var instance = instances[id] else {
            throw ProvisioningError.instanceNotFound
        }
        
        // Check subdomain change
        if config.subdomain != instance.config.subdomain {
            guard !usedSubdomains.contains(config.subdomain) else {
                throw ProvisioningError.subdomainTaken
            }
            usedSubdomains.remove(instance.config.subdomain)
            usedSubdomains.insert(config.subdomain)
        }
        
        instance.config = config
        instance.url = URL(string: "https://\(config.subdomain).t1pal.org")!
        instances[id] = instance
        
        return instance
    }
    
    public func deleteInstance(id: UUID) async throws {
        guard let instance = instances[id] else {
            throw ProvisioningError.instanceNotFound
        }
        usedSubdomains.remove(instance.config.subdomain)
        instances.removeValue(forKey: id)
    }
    
    public func checkSubdomainAvailable(subdomain: String) async throws -> Bool {
        !usedSubdomains.contains(subdomain)
    }
}

// MARK: - Live Implementation

/// Live implementation connecting to T1Pal provisioning API
public actor LiveProvisioningClient: ProvisioningClient {
    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?
    
    /// API endpoints
    private enum Endpoint {
        static let instances = "/api/v1/instances"
        static let subdomain = "/api/v1/subdomains/check"
    }
    
    public init(
        baseURL: URL = URL(string: "https://api.t1pal.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }
    
    /// Set authentication token for API calls
    public func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    public func listInstances() async throws -> [ManagedInstance] {
        let url = baseURL.appendingPathComponent(Endpoint.instances)
        let (data, response) = try await makeAuthenticatedRequest(url: url, method: "GET")
        
        try validateResponse(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ManagedInstance].self, from: data)
    }
    
    public func createInstance(config: NightscoutInstanceConfig) async throws -> ManagedInstance {
        // Validate subdomain format
        guard isValidSubdomain(config.subdomain) else {
            throw ProvisioningError.invalidConfiguration("Subdomain must be 3-20 lowercase alphanumeric characters")
        }
        
        let url = baseURL.appendingPathComponent(Endpoint.instances)
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(config)
        
        let (data, response) = try await makeAuthenticatedRequest(
            url: url,
            method: "POST",
            body: body
        )
        
        try validateResponse(response, expectedStatus: 201)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManagedInstance.self, from: data)
    }
    
    public func getInstance(id: UUID) async throws -> ManagedInstance {
        let url = baseURL.appendingPathComponent("\(Endpoint.instances)/\(id.uuidString)")
        let (data, response) = try await makeAuthenticatedRequest(url: url, method: "GET")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProvisioningError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 404 {
            throw ProvisioningError.instanceNotFound
        }
        
        try validateResponse(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManagedInstance.self, from: data)
    }
    
    public func updateInstance(id: UUID, config: NightscoutInstanceConfig) async throws -> ManagedInstance {
        let url = baseURL.appendingPathComponent("\(Endpoint.instances)/\(id.uuidString)")
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(config)
        
        let (data, response) = try await makeAuthenticatedRequest(
            url: url,
            method: "PUT",
            body: body
        )
        
        try validateResponse(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManagedInstance.self, from: data)
    }
    
    public func deleteInstance(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("\(Endpoint.instances)/\(id.uuidString)")
        let (_, response) = try await makeAuthenticatedRequest(url: url, method: "DELETE")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProvisioningError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 404 {
            throw ProvisioningError.instanceNotFound
        }
        
        try validateResponse(response, expectedStatus: 204)
    }
    
    public func checkSubdomainAvailable(subdomain: String) async throws -> Bool {
        guard isValidSubdomain(subdomain) else {
            return false
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent(Endpoint.subdomain), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "subdomain", value: subdomain)]
        
        guard let url = components.url else {
            throw ProvisioningError.invalidConfiguration("Invalid subdomain check URL")
        }
        
        let (data, response) = try await makeAuthenticatedRequest(url: url, method: "GET")
        try validateResponse(response)
        
        struct AvailabilityResponse: Decodable {
            let available: Bool
        }
        
        let result = try JSONDecoder().decode(AvailabilityResponse.self, from: data)
        return result.available
    }
    
    // MARK: - Private Helpers
    
    private func makeAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        guard let token = authToken else {
            throw ProvisioningError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            return try await session.data(for: request)
        } catch {
            throw ProvisioningError.networkError(error)
        }
    }
    
    private func validateResponse(_ response: URLResponse, expectedStatus: Int = 200) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProvisioningError.networkError(URLError(.badServerResponse))
        }
        
        switch httpResponse.statusCode {
        case expectedStatus, 200..<300:
            return
        case 401:
            throw ProvisioningError.notAuthenticated
        case 402:
            throw ProvisioningError.insufficientTier
        case 409:
            throw ProvisioningError.subdomainTaken
        case 400..<500:
            throw ProvisioningError.invalidConfiguration("Request error: \(httpResponse.statusCode)")
        default:
            throw ProvisioningError.provisioningFailed("Server error: \(httpResponse.statusCode)")
        }
    }
    
    private func isValidSubdomain(_ subdomain: String) -> Bool {
        let pattern = "^[a-z0-9]{3,20}$"
        return subdomain.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Instance Creation Flow

/// Orchestrates instance creation with discovery binding
public actor InstanceCreationFlow {
    private let provisioningClient: ProvisioningClient
    private let discoveryClient: InstanceDiscoveryClient
    
    public init(
        provisioningClient: ProvisioningClient,
        discoveryClient: InstanceDiscoveryClient
    ) {
        self.provisioningClient = provisioningClient
        self.discoveryClient = discoveryClient
    }
    
    /// Create a new managed instance and bind it to the user's account
    public func createAndBind(config: NightscoutInstanceConfig) async throws -> InstanceBinding {
        // Step 1: Provision the instance
        let instance = try await provisioningClient.createInstance(config: config)
        
        // Step 2: Bind to discovery (apiSecret from provisioned instance)
        let binding = try await discoveryClient.bindInstance(
            url: instance.url,
            apiSecret: instance.apiSecret,
            displayName: config.subdomain
        )
        
        return binding
    }
    
    /// Check subdomain availability before creation
    public func checkAvailability(subdomain: String) async throws -> SubdomainAvailability {
        let available = try await provisioningClient.checkSubdomainAvailable(subdomain: subdomain)
        
        if available {
            return .available
        } else {
            return .taken(suggestedAlternatives: generateAlternatives(subdomain))
        }
    }
    
    /// Generate alternative subdomain suggestions
    private func generateAlternatives(_ base: String) -> [String] {
        let suffixes = ["1", "2", "ns", "cgm", "data"]
        return suffixes.compactMap { suffix in
            let alternative = "\(base)\(suffix)"
            return alternative.count <= 20 ? alternative : nil
        }
    }
}

/// Subdomain availability result
public enum SubdomainAvailability: Sendable {
    case available
    case taken(suggestedAlternatives: [String])
    case invalid(reason: String)
}

// MARK: - Provisioning Status Poller

/// Polls for provisioning completion
public actor ProvisioningStatusPoller {
    private let client: ProvisioningClient
    private let pollInterval: TimeInterval
    private let maxAttempts: Int
    
    public init(
        client: ProvisioningClient,
        pollInterval: TimeInterval = 2.0,
        maxAttempts: Int = 30
    ) {
        self.client = client
        self.pollInterval = pollInterval
        self.maxAttempts = maxAttempts
    }
    
    /// Wait for instance to become running
    public func waitForRunning(instanceId: UUID) async throws -> ManagedInstance {
        for attempt in 1...maxAttempts {
            let instance = try await client.getInstance(id: instanceId)
            
            switch instance.status {
            case .running:
                return instance
            case .error:
                throw ProvisioningError.provisioningFailed("Instance entered error state")
            case .provisioning, .maintenance:
                // Continue waiting
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            case .suspended:
                throw ProvisioningError.provisioningFailed("Instance was suspended")
            }
        }
        
        throw ProvisioningError.provisioningFailed("Timeout waiting for instance to become ready")
    }
}
