// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SessionManager.swift
// T1PalCore
//
// Multi-device session management
// Backlog: ID-SESS-001
// Architecture: Kratos session tokens

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Device Session

/// Represents an authenticated session on a specific device
public struct DeviceSession: Identifiable, Codable, Sendable, Equatable {
    /// Unique session identifier
    public let id: String
    
    /// Device identifier (from Keychain/SecureEnclave)
    public let deviceId: String
    
    /// User-friendly device name
    public let deviceName: String
    
    /// Device type
    public let deviceType: DeviceType
    
    /// When the session was created
    public let createdAt: Date
    
    /// When the session was last active
    public var lastActiveAt: Date
    
    /// When the session expires (if known)
    public let expiresAt: Date?
    
    /// Whether this is the current device's session
    public let isCurrent: Bool
    
    /// Session token (only available for current device)
    public let token: String?
    
    /// Refresh token (only available for current device)
    public let refreshToken: String?
    
    public init(
        id: String = UUID().uuidString,
        deviceId: String,
        deviceName: String,
        deviceType: DeviceType = .unknown,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        expiresAt: Date? = nil,
        isCurrent: Bool = false,
        token: String? = nil,
        refreshToken: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.expiresAt = expiresAt
        self.isCurrent = isCurrent
        self.token = token
        self.refreshToken = refreshToken
    }
    
    /// Check if session is expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    /// Time remaining until expiration
    public var timeRemaining: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return expiresAt.timeIntervalSinceNow
    }
}

// MARK: - Device Type

/// Type of device
public enum DeviceType: String, Codable, Sendable, CaseIterable {
    case iPhone = "iphone"
    case iPad = "ipad"
    case watch = "watch"
    case mac = "mac"
    case web = "web"
    case unknown = "unknown"
    
    /// Display name for the device type
    public var displayName: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .watch: return "Apple Watch"
        case .mac: return "Mac"
        case .web: return "Web Browser"
        case .unknown: return "Unknown Device"
        }
    }
    
    /// SF Symbol name for the device type
    public var symbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .watch: return "applewatch"
        case .mac: return "desktopcomputer"
        case .web: return "globe"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Session Manager Errors

/// Errors from session management operations
public enum SessionError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case sessionExpired
    case sessionNotFound
    case deviceNotRegistered
    case networkError(Error)
    case serverError(Int)
    case invalidResponse
    case revokeNotAllowed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to manage sessions."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .sessionNotFound:
            return "Session not found."
        case .deviceNotRegistered:
            return "This device is not registered."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .invalidResponse:
            return "Invalid response from server."
        case .revokeNotAllowed(let reason):
            return "Cannot revoke session: \(reason)"
        }
    }
}

// MARK: - SessionError + T1PalErrorProtocol

extension SessionError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .auth }
    
    public var code: String {
        switch self {
        case .notAuthenticated: return "SESSION-AUTH-001"
        case .sessionExpired: return "SESSION-AUTH-002"
        case .sessionNotFound: return "SESSION-LOOKUP-001"
        case .deviceNotRegistered: return "SESSION-DEVICE-001"
        case .networkError: return "SESSION-NET-001"
        case .serverError: return "SESSION-SERVER-001"
        case .invalidResponse: return "SESSION-PARSE-001"
        case .revokeNotAllowed: return "SESSION-REVOKE-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .notAuthenticated: return .error
        case .sessionExpired: return .warning
        case .sessionNotFound: return .warning
        case .deviceNotRegistered: return .error
        case .networkError: return .warning
        case .serverError: return .error
        case .invalidResponse: return .error
        case .revokeNotAllowed: return .warning
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .notAuthenticated: return .none  // User must sign in
        case .sessionExpired: return .retry  // Re-authenticate
        case .sessionNotFound: return .none
        case .deviceNotRegistered: return .contactSupport
        case .networkError: return .retry
        case .serverError: return .retry
        case .invalidResponse: return .contactSupport
        case .revokeNotAllowed: return .none
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown session error"
    }
}

// MARK: - Session Manager Protocol

/// Protocol for session management operations
public protocol SessionManagerProtocol: Sendable {
    /// Get all active sessions for the current user
    func listSessions() async throws -> [DeviceSession]
    
    /// Get the current device's session
    func getCurrentSession() async -> DeviceSession?
    
    /// Register this device and create a new session
    func registerDevice(name: String, type: DeviceType) async throws -> DeviceSession
    
    /// Revoke a specific session (sign out that device)
    func revokeSession(id: String) async throws
    
    /// Revoke all sessions except current (sign out everywhere else)
    func revokeAllOtherSessions() async throws -> Int
    
    /// Update the current session's last active timestamp
    func touchSession() async throws
    
    /// Rename a device
    func renameDevice(sessionId: String, newName: String) async throws -> DeviceSession
}

// MARK: - Live Session Manager

/// Live implementation connecting to Kratos session API
public actor LiveSessionManager: SessionManagerProtocol {
    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?
    private var currentDeviceId: String?
    private var cachedSession: DeviceSession?
    
    /// API endpoints
    private enum Endpoint {
        static let sessions = "/sessions/whoami"
        static let allSessions = "/sessions"
        static let revoke = "/sessions"
        static let device = "/self-service/settings/device"
    }
    
    public init(
        baseURL: URL = URL(string: "https://auth.t1pal.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }
    
    /// Configure authentication
    public func configure(authToken: String, deviceId: String) {
        self.authToken = authToken
        self.currentDeviceId = deviceId
    }
    
    public func listSessions() async throws -> [DeviceSession] {
        let url = baseURL.appendingPathComponent(Endpoint.allSessions)
        let (data, response) = try await makeAuthenticatedRequest(url: url, method: "GET")
        
        try validateResponse(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let apiSessions = try decoder.decode([APISession].self, from: data)
        return apiSessions.map { $0.toDeviceSession(currentDeviceId: currentDeviceId) }
    }
    
    public func getCurrentSession() async -> DeviceSession? {
        cachedSession
    }
    
    public func registerDevice(name: String, type: DeviceType) async throws -> DeviceSession {
        let url = baseURL.appendingPathComponent(Endpoint.device)
        
        let body = RegisterDeviceRequest(name: name, type: type.rawValue)
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        
        let (data, response) = try await makeAuthenticatedRequest(
            url: url,
            method: "POST",
            body: bodyData
        )
        
        try validateResponse(response, expectedStatus: 201)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let apiSession = try decoder.decode(APISession.self, from: data)
        let deviceSession = apiSession.toDeviceSession(currentDeviceId: currentDeviceId)
        
        cachedSession = deviceSession
        return deviceSession
    }
    
    public func revokeSession(id: String) async throws {
        // Don't allow revoking current session through this method
        if let current = cachedSession, current.id == id {
            throw SessionError.revokeNotAllowed("Use sign out to revoke current session")
        }
        
        let url = baseURL.appendingPathComponent("\(Endpoint.revoke)/\(id)")
        let (_, response) = try await makeAuthenticatedRequest(url: url, method: "DELETE")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw SessionError.sessionNotFound
        }
        
        try validateResponse(response, expectedStatus: 204)
    }
    
    public func revokeAllOtherSessions() async throws -> Int {
        let sessions = try await listSessions()
        var revokedCount = 0
        
        for session in sessions where !session.isCurrent {
            do {
                try await revokeSession(id: session.id)
                revokedCount += 1
            } catch SessionError.sessionNotFound {
                // Already revoked, continue
            }
        }
        
        return revokedCount
    }
    
    public func touchSession() async throws {
        guard var session = cachedSession else {
            throw SessionError.notAuthenticated
        }
        
        // Update local timestamp
        session = DeviceSession(
            id: session.id,
            deviceId: session.deviceId,
            deviceName: session.deviceName,
            deviceType: session.deviceType,
            createdAt: session.createdAt,
            lastActiveAt: Date(),
            expiresAt: session.expiresAt,
            isCurrent: session.isCurrent,
            token: session.token,
            refreshToken: session.refreshToken
        )
        
        cachedSession = session
        
        // Optionally update server (fire and forget)
        Task {
            let url = baseURL.appendingPathComponent(Endpoint.sessions)
            _ = try? await makeAuthenticatedRequest(url: url, method: "PATCH", body: nil)
        }
    }
    
    public func renameDevice(sessionId: String, newName: String) async throws -> DeviceSession {
        let url = baseURL.appendingPathComponent("\(Endpoint.revoke)/\(sessionId)")
        
        let body = RenameDeviceRequest(name: newName)
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        
        let (data, response) = try await makeAuthenticatedRequest(
            url: url,
            method: "PATCH",
            body: bodyData
        )
        
        try validateResponse(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let apiSession = try decoder.decode(APISession.self, from: data)
        let deviceSession = apiSession.toDeviceSession(currentDeviceId: currentDeviceId)
        
        if deviceSession.isCurrent {
            cachedSession = deviceSession
        }
        
        return deviceSession
    }
    
    // MARK: - Private Helpers
    
    private func makeAuthenticatedRequest(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        guard let token = authToken else {
            throw SessionError.notAuthenticated
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
            throw SessionError.networkError(error)
        }
    }
    
    private func validateResponse(_ response: URLResponse, expectedStatus: Int = 200) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case expectedStatus:
            return
        case 200..<300 where expectedStatus == 200:
            return
        case 401:
            throw SessionError.sessionExpired
        case 404:
            throw SessionError.sessionNotFound
        default:
            throw SessionError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - API Types

/// API response for a session
private struct APISession: Decodable {
    let id: String
    let deviceId: String?
    let deviceName: String?
    let deviceType: String?
    let createdAt: Date?
    let lastActiveAt: Date?
    let expiresAt: Date?
    let token: String?
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case deviceName = "device_name"
        case deviceType = "device_type"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case expiresAt = "expires_at"
        case token
        case refreshToken = "refresh_token"
    }
    
    func toDeviceSession(currentDeviceId: String?) -> DeviceSession {
        DeviceSession(
            id: id,
            deviceId: deviceId ?? "unknown",
            deviceName: deviceName ?? "Unknown Device",
            deviceType: DeviceType(rawValue: deviceType ?? "") ?? .unknown,
            createdAt: createdAt ?? Date(),
            lastActiveAt: lastActiveAt ?? Date(),
            expiresAt: expiresAt,
            isCurrent: deviceId == currentDeviceId,
            token: token,
            refreshToken: refreshToken
        )
    }
}

/// Request to register a device
private struct RegisterDeviceRequest: Encodable {
    let name: String
    let type: String
}

/// Request to rename a device
private struct RenameDeviceRequest: Encodable {
    let name: String
}

// MARK: - Mock Session Manager

/// Mock implementation for testing
public actor MockSessionManager: SessionManagerProtocol {
    private var sessions: [String: DeviceSession] = [:]
    private var currentSession: DeviceSession?
    public private(set) var listSessionsCallCount = 0
    public private(set) var revokeCallCount = 0
    
    public init() {}
    
    /// Configure with a current session
    public func setCurrentSession(_ session: DeviceSession) {
        currentSession = session
        sessions[session.id] = session
    }
    
    /// Add a session (simulates another device)
    public func addSession(_ session: DeviceSession) {
        sessions[session.id] = session
    }
    
    public func listSessions() async throws -> [DeviceSession] {
        listSessionsCallCount += 1
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        return Array(sessions.values).sorted { $0.createdAt < $1.createdAt }
    }
    
    public func getCurrentSession() async -> DeviceSession? {
        currentSession
    }
    
    public func registerDevice(name: String, type: DeviceType) async throws -> DeviceSession {
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        let session = DeviceSession(
            id: UUID().uuidString,
            deviceId: UUID().uuidString,
            deviceName: name,
            deviceType: type,
            isCurrent: true,
            token: "mock-token-\(UUID().uuidString.prefix(8))",
            refreshToken: "mock-refresh-\(UUID().uuidString.prefix(8))"
        )
        
        currentSession = session
        sessions[session.id] = session
        return session
    }
    
    public func revokeSession(id: String) async throws {
        revokeCallCount += 1
        
        guard let session = sessions[id] else {
            throw SessionError.sessionNotFound
        }
        
        if session.isCurrent {
            throw SessionError.revokeNotAllowed("Cannot revoke current session")
        }
        
        sessions.removeValue(forKey: id)
    }
    
    public func revokeAllOtherSessions() async throws -> Int {
        let otherSessions = sessions.values.filter { !$0.isCurrent }
        for session in otherSessions {
            sessions.removeValue(forKey: session.id)
        }
        revokeCallCount += otherSessions.count
        return otherSessions.count
    }
    
    public func touchSession() async throws {
        guard var session = currentSession else {
            throw SessionError.notAuthenticated
        }
        
        session = DeviceSession(
            id: session.id,
            deviceId: session.deviceId,
            deviceName: session.deviceName,
            deviceType: session.deviceType,
            createdAt: session.createdAt,
            lastActiveAt: Date(),
            expiresAt: session.expiresAt,
            isCurrent: session.isCurrent,
            token: session.token,
            refreshToken: session.refreshToken
        )
        
        currentSession = session
        sessions[session.id] = session
    }
    
    public func renameDevice(sessionId: String, newName: String) async throws -> DeviceSession {
        guard var session = sessions[sessionId] else {
            throw SessionError.sessionNotFound
        }
        
        session = DeviceSession(
            id: session.id,
            deviceId: session.deviceId,
            deviceName: newName,
            deviceType: session.deviceType,
            createdAt: session.createdAt,
            lastActiveAt: session.lastActiveAt,
            expiresAt: session.expiresAt,
            isCurrent: session.isCurrent,
            token: session.token,
            refreshToken: session.refreshToken
        )
        
        sessions[sessionId] = session
        if session.isCurrent {
            currentSession = session
        }
        
        return session
    }
}

// MARK: - Device Identification

/// Helper for device identification
public struct DeviceIdentifier {
    /// Get a stable device identifier
    /// In production, this should use Keychain to persist across reinstalls
    public static func getDeviceId() -> String {
        // For now, generate a UUID that should be stored in Keychain
        // A real implementation would:
        // 1. Check Keychain for existing ID
        // 2. If not found, generate and store
        UUID().uuidString
    }
    
    /// Get device name from system
    public static func getDeviceName() -> String {
        #if os(iOS)
        // UIDevice.current.name - requires UIKit
        return "iPhone"
        #elseif os(watchOS)
        return "Apple Watch"
        #elseif os(macOS)
        // Host.current().localizedName ?? "Mac"
        return "Mac"
        #else
        return "Unknown"
        #endif
    }
    
    /// Detect device type
    public static func getDeviceType() -> DeviceType {
        #if os(iOS)
        // Check if iPad or iPhone
        return .iPhone
        #elseif os(watchOS)
        return .watch
        #elseif os(macOS)
        return .mac
        #else
        return .unknown
        #endif
    }
}
