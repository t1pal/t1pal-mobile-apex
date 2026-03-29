// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NightscoutV3Client.swift - Nightscout API v3 client
// Part of NightscoutKit
// Trace: NS-V3-001, NS-V3-002, NS-V3-003, NS-V3-004

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - V3 Query Types

/// Query parameters for v3 API SEARCH operation
public struct V3Query: Sendable {
    public var limit: Int?
    public var skip: Int?
    public var sortField: String?
    public var sortDescending: Bool = true
    public var fields: [String]?
    public var dateFrom: Date?
    public var dateTo: Date?
    
    public init(
        limit: Int? = nil,
        skip: Int? = nil,
        sortField: String? = "date",
        sortDescending: Bool = true,
        fields: [String]? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil
    ) {
        self.limit = limit
        self.skip = skip
        self.sortField = sortField
        self.sortDescending = sortDescending
        self.fields = fields
        self.dateFrom = dateFrom
        self.dateTo = dateTo
    }
    
    /// Convert to URL query items for v3 API
    public func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        
        if let limit = limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        
        if let skip = skip {
            items.append(URLQueryItem(name: "skip", value: String(skip)))
        }
        
        if let sortField = sortField {
            let sortParam = sortDescending ? "sort$desc" : "sort"
            items.append(URLQueryItem(name: sortParam, value: sortField))
        }
        
        if let fields = fields, !fields.isEmpty {
            items.append(URLQueryItem(name: "fields", value: fields.joined(separator: ",")))
        }
        
        // V3 uses date field filtering with milliseconds
        if let dateFrom = dateFrom {
            let ms = Int64(dateFrom.timeIntervalSince1970 * 1000)
            items.append(URLQueryItem(name: "date$gte", value: String(ms)))
        }
        
        if let dateTo = dateTo {
            let ms = Int64(dateTo.timeIntervalSince1970 * 1000)
            items.append(URLQueryItem(name: "date$lte", value: String(ms)))
        }
        
        return items
    }
}

// MARK: - V3 Response Types

/// Wrapper for v3 API responses
public struct V3Response<T: Decodable>: Decodable {
    public let status: Int
    public let result: T
}

/// Wrapper for v3 API array responses (handles both wrapped and unwrapped)
public struct V3ArrayResponse<T: Decodable>: Decodable {
    public let status: Int?
    public let result: [T]?
    private let directArray: [T]?
    
    public var items: [T] {
        result ?? directArray ?? []
    }
    
    public init(from decoder: Decoder) throws {
        // Try decoding as wrapped response first
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.status = try container.decodeIfPresent(Int.self, forKey: .status)
            self.result = try container.decodeIfPresent([T].self, forKey: .result)
            self.directArray = nil
        } else {
            // Fall back to direct array
            let container = try decoder.singleValueContainer()
            self.directArray = try container.decode([T].self)
            self.status = 200
            self.result = nil
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case status, result
    }
}

/// V3 CREATE response
public struct V3CreateResponse: Decodable, Sendable {
    public let status: Int
    public let identifier: String?
    public let lastModified: Int64?
    public let isDeduplication: Bool?
    public let deduplicatedIdentifier: String?
}

/// V3 version info response
public struct V3VersionResponse: Decodable, Sendable {
    public let status: Int
    public let result: V3VersionResult
}

public struct V3VersionResult: Decodable, Sendable {
    public let version: String
    public let apiVersion: String
    public let srvDate: Int64
    public let storage: V3StorageInfo?
}

public struct V3StorageInfo: Decodable, Sendable {
    public let storage: String
    public let version: String
}

/// V3 status response with permissions
public struct V3StatusResponse: Decodable, Sendable {
    public let status: Int
    public let result: V3StatusResult
}

public struct V3StatusResult: Decodable, Sendable {
    public let version: String
    public let apiVersion: String
    public let srvDate: Int64
    public let storage: V3StorageInfo?
    public let apiPermissions: [String: String]?
}

/// V3 lastModified response
public struct V3LastModifiedResponse: Decodable, Sendable {
    public let status: Int
    public let result: V3LastModifiedResult
}

public struct V3LastModifiedResult: Decodable, Sendable {
    public let srvDate: Int64
    public let collections: [String: Int64]
}

// MARK: - JWT Token Management

/// JWT token with expiration tracking
public struct JWTToken: Sendable, Codable {
    public let token: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let permissions: [String: String]?
    
    public init(token: String, issuedAt: Date, expiresAt: Date, permissions: [String: String]? = nil) {
        self.token = token
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.permissions = permissions
    }
    
    /// Check if token is expired (with 15-minute buffer)
    public var isExpired: Bool {
        Date() > expiresAt.addingTimeInterval(-15 * 60)
    }
    
    /// Check if token needs refresh (within 15 minutes of expiry)
    public var needsRefresh: Bool {
        Date() > expiresAt.addingTimeInterval(-15 * 60)
    }
}

/// JWT authorization response from /api/v2/authorization/request
public struct JWTAuthResponse: Decodable, Sendable {
    public let token: String
    public let iat: Int64  // issued at (seconds)
    public let exp: Int64  // expires at (seconds)
    public let sub: String? // subject
    public let permissionGroups: [String]?
}

// MARK: - V3 Client Actor

/// Nightscout API v3 client with JWT authentication
public actor NightscoutV3Client {
    
    // MARK: - Properties
    
    private let baseURL: URL
    private let accessToken: String  // The token=xxx style access token
    private var jwtToken: JWTToken?
    private let session: URLSession
    
    // MARK: - Initialization
    
    /// Initialize with base URL and access token
    /// - Parameters:
    ///   - baseURL: Nightscout instance URL (e.g., https://yoursite.herokuapp.com)
    ///   - accessToken: Access token in format "token=name-hash" or just "name-hash"
    public init(baseURL: URL, accessToken: String) {
        self.baseURL = baseURL
        // Normalize token format
        if accessToken.hasPrefix("token=") {
            self.accessToken = accessToken
        } else {
            self.accessToken = "token=\(accessToken)"
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - JWT Authentication (NS-V3-004)
    
    /// Request a JWT token from the authorization endpoint
    public func requestJWT() async throws -> JWTToken {
        // Check if we have a valid cached token
        if let existing = jwtToken, !existing.needsRefresh {
            return existing
        }
        
        // Request new JWT via /api/v2/authorization/request/{token}
        let authURL = baseURL.appendingPathComponent("api/v2/authorization/request/\(accessToken)")
        var request = URLRequest(url: authURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw V3Error.authenticationFailed(statusCode: httpResponse.statusCode)
        }
        
        let authResponse = try JSONDecoder().decode(JWTAuthResponse.self, from: data)
        
        let token = JWTToken(
            token: authResponse.token,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(authResponse.iat)),
            expiresAt: Date(timeIntervalSince1970: TimeInterval(authResponse.exp)),
            permissions: nil
        )
        
        self.jwtToken = token
        return token
    }
    
    /// Clear cached JWT token (forces re-authentication)
    public func clearJWT() {
        jwtToken = nil
    }
    
    // MARK: - Version & Status
    
    /// Get server version (public endpoint, no auth required)
    public func getVersion() async throws -> V3VersionResult {
        let url = baseURL.appendingPathComponent("api/v3/version")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw V3Error.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let versionResponse = try JSONDecoder().decode(V3VersionResponse.self, from: data)
        return versionResponse.result
    }
    
    /// Get server status with permissions (requires auth)
    public func getStatus() async throws -> V3StatusResult {
        let url = baseURL.appendingPathComponent("api/v3/status")
        let request = try await authenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw V3Error.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let statusResponse = try JSONDecoder().decode(V3StatusResponse.self, from: data)
        return statusResponse.result
    }
    
    /// Get last modified timestamps for all collections
    public func getLastModified() async throws -> V3LastModifiedResult {
        let url = baseURL.appendingPathComponent("api/v3/lastModified")
        let request = try await authenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw V3Error.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let lastModResponse = try JSONDecoder().decode(V3LastModifiedResponse.self, from: data)
        return lastModResponse.result
    }
    
    // MARK: - Entries (NS-V3-001)
    
    /// Search entries with query parameters
    public func searchEntries(query: V3Query = V3Query()) async throws -> [NightscoutEntry] {
        return try await search(collection: "entries", query: query)
    }
    
    /// Get a single entry by identifier
    public func getEntry(identifier: String) async throws -> NightscoutEntry {
        return try await read(collection: "entries", identifier: identifier)
    }
    
    /// Create a new entry
    public func createEntry(_ entry: NightscoutEntry) async throws -> V3CreateResponse {
        return try await create(collection: "entries", document: entry)
    }
    
    /// Create multiple entries
    public func createEntries(_ entries: [NightscoutEntry]) async throws -> [V3CreateResponse] {
        var responses: [V3CreateResponse] = []
        for entry in entries {
            let response = try await create(collection: "entries", document: entry)
            responses.append(response)
        }
        return responses
    }
    
    /// Get entries history since lastModified timestamp
    public func getEntriesHistory(since: Int64) async throws -> [NightscoutEntry] {
        return try await history(collection: "entries", since: since)
    }
    
    // MARK: - Treatments (NS-V3-002)
    
    /// Search treatments with query parameters
    public func searchTreatments(query: V3Query = V3Query()) async throws -> [NightscoutTreatment] {
        return try await search(collection: "treatments", query: query)
    }
    
    /// Get a single treatment by identifier
    public func getTreatment(identifier: String) async throws -> NightscoutTreatment {
        return try await read(collection: "treatments", identifier: identifier)
    }
    
    /// Create a new treatment
    public func createTreatment(_ treatment: NightscoutTreatment) async throws -> V3CreateResponse {
        return try await create(collection: "treatments", document: treatment)
    }
    
    /// Create multiple treatments
    public func createTreatments(_ treatments: [NightscoutTreatment]) async throws -> [V3CreateResponse] {
        var responses: [V3CreateResponse] = []
        for treatment in treatments {
            let response = try await create(collection: "treatments", document: treatment)
            responses.append(response)
        }
        return responses
    }
    
    /// Update a treatment
    public func updateTreatment(identifier: String, treatment: NightscoutTreatment) async throws {
        try await update(collection: "treatments", identifier: identifier, document: treatment)
    }
    
    /// Delete a treatment
    public func deleteTreatment(identifier: String) async throws {
        try await delete(collection: "treatments", identifier: identifier)
    }
    
    /// Get treatments history since lastModified timestamp
    public func getTreatmentsHistory(since: Int64) async throws -> [NightscoutTreatment] {
        return try await history(collection: "treatments", since: since)
    }
    
    // MARK: - Device Status (NS-V3-003)
    
    /// Search device status with query parameters
    public func searchDeviceStatus(query: V3Query = V3Query()) async throws -> [NightscoutDeviceStatus] {
        return try await search(collection: "devicestatus", query: query)
    }
    
    /// Get a single device status by identifier
    public func getDeviceStatus(identifier: String) async throws -> NightscoutDeviceStatus {
        return try await read(collection: "devicestatus", identifier: identifier)
    }
    
    /// Create a new device status
    public func createDeviceStatus(_ status: NightscoutDeviceStatus) async throws -> V3CreateResponse {
        return try await create(collection: "devicestatus", document: status)
    }
    
    /// Get device status history since lastModified timestamp
    public func getDeviceStatusHistory(since: Int64) async throws -> [NightscoutDeviceStatus] {
        return try await history(collection: "devicestatus", since: since)
    }
    
    // MARK: - Generic CRUD Operations
    
    /// Generic SEARCH operation
    private func search<T: Decodable>(collection: String, query: V3Query) async throws -> [T] {
        var url = baseURL.appendingPathComponent("api/v3/\(collection)")
        let queryItems = query.toQueryItems()
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }
        
        let request = try await authenticatedRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
        
        let arrayResponse = try JSONDecoder().decode(V3ArrayResponse<T>.self, from: data)
        return arrayResponse.items
    }
    
    /// Generic READ operation
    private func read<T: Decodable>(collection: String, identifier: String) async throws -> T {
        let url = baseURL.appendingPathComponent("api/v3/\(collection)/\(identifier)")
        let request = try await authenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw V3Error.notFound(identifier: identifier)
            }
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
        
        let wrapped = try JSONDecoder().decode(V3Response<T>.self, from: data)
        return wrapped.result
    }
    
    /// Generic CREATE operation
    private func create<T: Encodable>(collection: String, document: T) async throws -> V3CreateResponse {
        let url = baseURL.appendingPathComponent("api/v3/\(collection)")
        var request = try await authenticatedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(document)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard (200...201).contains(httpResponse.statusCode) else {
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(V3CreateResponse.self, from: data)
    }
    
    /// Generic UPDATE operation
    private func update<T: Encodable>(collection: String, identifier: String, document: T) async throws {
        let url = baseURL.appendingPathComponent("api/v3/\(collection)/\(identifier)")
        var request = try await authenticatedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(document)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw V3Error.notFound(identifier: identifier)
            }
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Generic DELETE operation
    private func delete(collection: String, identifier: String) async throws {
        let url = baseURL.appendingPathComponent("api/v3/\(collection)/\(identifier)")
        let request = try await authenticatedRequest(url: url, method: "DELETE")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw V3Error.notFound(identifier: identifier)
            }
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Generic HISTORY operation
    private func history<T: Decodable>(collection: String, since: Int64) async throws -> [T] {
        let url = baseURL.appendingPathComponent("api/v3/\(collection)/history/\(since)")
        let request = try await authenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3Error.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw V3Error.serverError(statusCode: httpResponse.statusCode)
        }
        
        let arrayResponse = try JSONDecoder().decode(V3ArrayResponse<T>.self, from: data)
        return arrayResponse.items
    }
    
    // MARK: - Request Helpers
    
    /// Create an authenticated request with JWT bearer token
    private func authenticatedRequest(url: URL, method: String) async throws -> URLRequest {
        let jwt = try await requestJWT()
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(jwt.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        
        return request
    }
}

// MARK: - V3 Errors

public enum V3Error: Error, LocalizedError, @unchecked Sendable {
    case authenticationFailed(statusCode: Int)
    case serverError(statusCode: Int)
    case notFound(identifier: String)
    case invalidResponse
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let code):
            return "Authentication failed with status \(code)"
        case .serverError(let code):
            return "Server error with status \(code)"
        case .notFound(let id):
            return "Document not found: \(id)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - V3 Client Factory

extension NightscoutV3Client {
    
    /// Create a V3 client from a NightscoutConfig
    /// - Parameter config: Nightscout configuration with URL and credentials
    /// - Returns: NightscoutV3Client if config has token or apiSecret, nil otherwise
    public static func from(config: NightscoutConfig) -> NightscoutV3Client? {
        guard let token = config.token ?? config.apiSecret else {
            return nil
        }
        return NightscoutV3Client(baseURL: config.url, accessToken: token)
    }
    
    /// Check if V3 API is available on a server
    /// - Parameters:
    ///   - url: Nightscout server URL
    ///   - apiSecret: Optional API secret for authenticated check
    /// - Returns: true if server supports V3 API (version 15+)
    public static func isV3Available(url: URL, apiSecret: String? = nil) async throws -> Bool {
        let detector = NightscoutVersionDetector.shared
        let features = try await detector.detectFeatures(url: url, apiSecret: apiSecret)
        return features.supportsV3API
    }
}

// MARK: - T1PalErrorProtocol Conformance

import T1PalCore

extension V3Error: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .network }
    
    public var code: String {
        switch self {
        case .authenticationFailed(let statusCode): return "V3-AUTH-\(statusCode)"
        case .serverError(let statusCode): return "V3-SERVER-\(statusCode)"
        case .notFound: return "V3-NOT-FOUND"
        case .invalidResponse: return "V3-RESPONSE-001"
        case .decodingError: return "V3-DECODE-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .authenticationFailed: return .critical
        case .serverError(let code) where code >= 500: return .error
        case .serverError: return .warning
        case .notFound: return .warning
        case .invalidResponse, .decodingError: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .authenticationFailed: return .reauthenticate
        case .serverError(let code) where code >= 500: return .waitAndRetry
        case .serverError: return .checkNetwork
        case .notFound: return .none
        case .invalidResponse, .decodingError: return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown Nightscout V3 error"
    }
}
