// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutDiscovery.swift
// NightscoutKit
//
// Nightscout instance discovery and validation
// Extracted from NightscoutClient.swift (NS-REFACTOR-011)
// Requirements: REQ-ID-003

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Discovery Result

/// Discovery result from Nightscout server probe
/// Requirements: REQ-ID-003
public struct NightscoutDiscoveryResult: Sendable {
    public let url: URL
    public let serverName: String?
    public let version: String?
    public let apiEnabled: Bool
    public let careportalEnabled: Bool
    public let authRequired: Bool
    public let authValid: Bool
    public let permissions: Set<String>
    public let discoveredAt: Date
    
    public init(
        url: URL,
        serverName: String? = nil,
        version: String? = nil,
        apiEnabled: Bool = true,
        careportalEnabled: Bool = false,
        authRequired: Bool = true,
        authValid: Bool = false,
        permissions: Set<String> = [],
        discoveredAt: Date = Date()
    ) {
        self.url = url
        self.serverName = serverName
        self.version = version
        self.apiEnabled = apiEnabled
        self.careportalEnabled = careportalEnabled
        self.authRequired = authRequired
        self.authValid = authValid
        self.permissions = permissions
        self.discoveredAt = discoveredAt
    }
    
    /// Check if server can provide read-only access
    public var canRead: Bool {
        !authRequired || (authValid && permissions.contains("readable"))
    }
    
    /// Check if server allows write access
    public var canWrite: Bool {
        authValid && permissions.contains("api:*:create")
    }
}

// MARK: - Discovery Error

/// Discovery error types
/// Requirements: REQ-ID-003
public enum NightscoutDiscoveryError: Error, Sendable {
    case invalidUrl(String)
    case networkError(String)
    case serverNotFound
    case notNightscoutServer
    case authenticationFailed
    case insufficientPermissions(Set<String>)
    case timeout
    case unsupportedVersion(String)
}

// MARK: - Server Status

/// Server status from Nightscout API
/// Requirements: REQ-ID-003
public struct NightscoutServerStatus: Codable, Sendable {
    public let status: String?
    public let name: String?
    public let version: String?
    public let serverTime: String?
    public let apiEnabled: Bool?
    public let careportalEnabled: Bool?
    public let settings: NightscoutSettings?
    
    public init(
        status: String? = nil,
        name: String? = nil,
        version: String? = nil,
        serverTime: String? = nil,
        apiEnabled: Bool? = nil,
        careportalEnabled: Bool? = nil,
        settings: NightscoutSettings? = nil
    ) {
        self.status = status
        self.name = name
        self.version = version
        self.serverTime = serverTime
        self.apiEnabled = apiEnabled
        self.careportalEnabled = careportalEnabled
        self.settings = settings
    }
}

// MARK: - Server Settings

/// Nightscout server settings subset
/// Requirements: REQ-ID-003
public struct NightscoutSettings: Codable, Sendable {
    public let units: String?
    public let timeFormat: Int?
    public let theme: String?
    public let language: String?
    
    public init(
        units: String? = nil,
        timeFormat: Int? = nil,
        theme: String? = nil,
        language: String? = nil
    ) {
        self.units = units
        self.timeFormat = timeFormat
        self.theme = theme
        self.language = language
    }
}

// MARK: - Auth Result

/// Authorization verification result
/// Requirements: REQ-ID-003
public struct NightscoutAuthResult: Codable, Sendable {
    public let rolefound: String?
    public let message: String?
    public let isAdmin: Bool?
    public let isReadable: Bool?
    public let permissions: [String]?
    
    public init(
        rolefound: String? = nil,
        message: String? = nil,
        isAdmin: Bool? = nil,
        isReadable: Bool? = nil,
        permissions: [String]? = nil
    ) {
        self.rolefound = rolefound
        self.message = message
        self.isAdmin = isAdmin
        self.isReadable = isReadable
        self.permissions = permissions
    }
}

// MARK: - Nightscout Discovery Actor

/// Nightscout instance discovery and validation
/// Requirements: REQ-ID-003
public actor NightscoutDiscovery {
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }
    
    /// Normalize and validate URL
    public func normalizeUrl(_ input: String) throws -> URL {
        var urlString = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https if no scheme
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        // Remove trailing slash
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        
        guard let url = URL(string: urlString) else {
            throw NightscoutDiscoveryError.invalidUrl("Cannot parse URL: \(input)")
        }
        
        guard let host = url.host, !host.isEmpty else {
            throw NightscoutDiscoveryError.invalidUrl("Missing host: \(input)")
        }
        
        return url
    }
    
    #if canImport(FoundationNetworking)
    // Linux implementation using synchronous networking
    
    /// Discover Nightscout server status
    public func discover(url: URL, apiSecret: String? = nil) async throws -> NightscoutDiscoveryResult {
        let statusUrl = url.appendingPathComponent("/api/v1/status.json")
        
        var request = URLRequest(url: statusUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        
        if let secret = apiSecret {
            request.setValue("api-secret " + secret.sha1(), forHTTPHeaderField: "Authorization")
        }
        
        let status = try await performSyncRequest(request, as: NightscoutServerStatus.self)
        
        // Check auth if secret provided
        var authResult: NightscoutAuthResult? = nil
        var permissions: Set<String> = []
        
        if apiSecret != nil {
            let authUrl = url.appendingPathComponent("/api/v1/verifyauth")
            var authRequest = URLRequest(url: authUrl)
            authRequest.httpMethod = "GET"
            authRequest.timeoutInterval = timeout
            authRequest.setValue("api-secret " + apiSecret!.sha1(), forHTTPHeaderField: "Authorization")
            
            authResult = try? await performSyncRequest(authRequest, as: NightscoutAuthResult.self)
            if let perms = authResult?.permissions {
                permissions = Set(perms)
            }
        }
        
        return NightscoutDiscoveryResult(
            url: url,
            serverName: status.name,
            version: status.version,
            apiEnabled: status.apiEnabled ?? true,
            careportalEnabled: status.careportalEnabled ?? false,
            authRequired: true,  // Assume auth required for safety
            authValid: authResult != nil,
            permissions: permissions
        )
    }
    
    private func performSyncRequest<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        // Use nonisolated(unsafe) for callback safety - semaphore provides synchronization
        nonisolated(unsafe) var result: Result<T, Error>?
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = .failure(NightscoutDiscoveryError.networkError(error.localizedDescription))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                result = .failure(NightscoutDiscoveryError.serverNotFound)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                result = .failure(NightscoutDiscoveryError.authenticationFailed)
                return
            }
            
            guard let data = data else {
                result = .failure(NightscoutDiscoveryError.notNightscoutServer)
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                result = .success(decoded)
            } catch {
                result = .failure(NightscoutDiscoveryError.notNightscoutServer)
            }
        }
        
        task.resume()
        
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            task.cancel()
            throw NightscoutDiscoveryError.timeout
        }
        
        return try result!.get()
    }
    
    #else
    // Darwin implementation using async networking
    
    /// Discover Nightscout server status
    public func discover(url: URL, apiSecret: String? = nil) async throws -> NightscoutDiscoveryResult {
        let statusUrl = url.appendingPathComponent("/api/v1/status.json")
        
        var request = URLRequest(url: statusUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        
        if let secret = apiSecret {
            request.setValue("api-secret " + secret.sha1(), forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightscoutDiscoveryError.serverNotFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NightscoutDiscoveryError.notNightscoutServer
        }
        
        let status: NightscoutServerStatus
        do {
            status = try JSONDecoder().decode(NightscoutServerStatus.self, from: data)
        } catch {
            throw NightscoutDiscoveryError.notNightscoutServer
        }
        
        // Check auth if secret provided
        var permissions: Set<String> = []
        var authValid = false
        
        if let secret = apiSecret {
            let authUrl = url.appendingPathComponent("/api/v1/verifyauth")
            var authRequest = URLRequest(url: authUrl)
            authRequest.httpMethod = "GET"
            authRequest.setValue("api-secret " + secret.sha1(), forHTTPHeaderField: "Authorization")
            
            if let (authData, authResponse) = try? await URLSession.shared.data(for: authRequest),
               let authHttp = authResponse as? HTTPURLResponse,
               authHttp.statusCode == 200,
               let authResult = try? JSONDecoder().decode(NightscoutAuthResult.self, from: authData) {
                authValid = true
                if let perms = authResult.permissions {
                    permissions = Set(perms)
                }
            }
        }
        
        return NightscoutDiscoveryResult(
            url: url,
            serverName: status.name,
            version: status.version,
            apiEnabled: status.apiEnabled ?? true,
            careportalEnabled: status.careportalEnabled ?? false,
            authRequired: true,
            authValid: authValid,
            permissions: permissions
        )
    }
    #endif
    
    /// Quick connectivity test
    public func testConnectivity(url: URL) async -> Bool {
        do {
            _ = try await discover(url: url)
            return true
        } catch {
            return false
        }
    }
    
    /// Validate API secret
    public func validateSecret(url: URL, apiSecret: String) async throws -> Bool {
        let result = try await discover(url: url, apiSecret: apiSecret)
        return result.authValid
    }
    
    /// Create NightscoutInstance from discovery
    public func createInstance(
        url: URL,
        name: String,
        apiSecret: String? = nil,
        isDefault: Bool = false
    ) async throws -> NightscoutInstance {
        let normalized = try normalizeUrl(url.absoluteString)
        
        // Verify server is reachable
        let result = try await discover(url: normalized, apiSecret: apiSecret)
        
        guard result.apiEnabled else {
            throw NightscoutDiscoveryError.insufficientPermissions(["api:*:read"])
        }
        
        let config = NightscoutConfig(url: normalized, apiSecret: apiSecret)
        let label = name.isEmpty ? (result.serverName ?? normalized.host ?? "Nightscout") : name
        
        return NightscoutInstance(
            label: label,
            config: config,
            priority: isDefault ? .primary : .secondary,
            role: .readWrite
        )
    }
}

// MARK: - URL Parser

/// URL input helper for common Nightscout formats
/// Requirements: REQ-ID-003
public struct NightscoutUrlParser: Sendable {
    
    /// Parse user input into normalized Nightscout URL (async version)
    /// - Parameter input: User-provided URL string
    /// - Returns: Normalized Nightscout URL
    public static func parse(_ input: String) async throws -> URL {
        let discovery = NightscoutDiscovery()
        return try await discovery.normalizeUrl(input)
    }
    
    /// Parse user input into normalized Nightscout URL (sync version)
    /// - Note: Prefer the async version when possible
    @available(*, deprecated, message: "Use async parse(_:) instead")
    public static func parseSync(_ input: String) throws -> URL {
        let discovery = NightscoutDiscovery()
        
        // Use Task to wrap async call
        var result: URL?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = try await discovery.normalizeUrl(input)
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        if let error = error {
            throw error
        }
        return result!
    }
    
    /// Common Nightscout hosting patterns
    public static func suggestUrl(from partial: String) -> [String] {
        var suggestions: [String] = []
        let clean = partial.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If looks like just a name, suggest common hosts
        if !clean.contains(".") {
            suggestions.append("https://\(clean).fly.dev")
            suggestions.append("https://\(clean).herokuapp.com")
            suggestions.append("https://\(clean).azurewebsites.net")
            suggestions.append("https://\(clean).railway.app")
            suggestions.append("https://\(clean).render.com")
        }
        
        return suggestions
    }
}
