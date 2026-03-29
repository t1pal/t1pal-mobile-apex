// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LibreLinkUpClient.swift
// CGMKit
//
// Abbott LibreLink Up cloud API client
// Requirements: REQ-CGM-002, PRD-004 CGM-006
//
// Reference: https://github.com/nightscout/nightscout-librelink-up

import Foundation
import T1PalCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Configuration

/// LibreLink Up server regions
public enum LibreLinkUpRegion: String, Codable, Sendable {
    case us = "api-us.libreview.io"
    case eu = "api-eu.libreview.io"
    case de = "api-de.libreview.io"
    case fr = "api-fr.libreview.io"
    case jp = "api-jp.libreview.io"
    case ap = "api-ap.libreview.io"
    case au = "api-au.libreview.io"
    
    var baseURL: URL {
        URL(string: "https://\(rawValue)/llu")!
    }
}

/// LibreLink Up credentials
public struct LibreLinkUpCredentials: Codable, Sendable {
    public let email: String
    public let password: String
    public let region: LibreLinkUpRegion
    
    public init(email: String, password: String, region: LibreLinkUpRegion = .us) {
        self.email = email
        self.password = password
        self.region = region
    }
}

// MARK: - API Response Types

/// Login response
struct LibreLinkUpLoginResponse: Codable {
    let status: Int
    let data: LoginData?
    
    struct LoginData: Codable {
        let authTicket: AuthTicket?
        let user: User?
        let redirect: Bool?
        let region: String?
    }
    
    struct AuthTicket: Codable {
        let token: String
        let expires: Int
        let duration: Int
    }
    
    struct User: Codable {
        let id: String
        let firstName: String?
        let lastName: String?
        let email: String?
    }
}

/// Connections response (list of patients)
struct LibreLinkUpConnectionsResponse: Codable {
    let status: Int
    let data: [Connection]?
    
    struct Connection: Codable {
        let patientId: String
        let firstName: String?
        let lastName: String?
        let glucoseMeasurement: GlucoseMeasurement?
    }
    
    struct GlucoseMeasurement: Codable {
        let Value: Double
        let TrendArrow: Int?
        let Timestamp: String?
        let FactoryTimestamp: String?
    }
}

/// Graph data response
struct LibreLinkUpGraphResponse: Codable {
    let status: Int
    let data: GraphData?
    
    struct GraphData: Codable {
        let connection: ConnectionInfo?
        let graphData: [GlucoseEntry]?
    }
    
    struct ConnectionInfo: Codable {
        let glucoseMeasurement: GlucoseMeasurement?
    }
    
    struct GlucoseMeasurement: Codable {
        let Value: Double
        let TrendArrow: Int?
        let Timestamp: String?
    }
    
    struct GlucoseEntry: Codable {
        let Value: Double
        let Timestamp: String?
        let FactoryTimestamp: String?
    }
}

// MARK: - Public Types

/// LibreLink Up glucose reading
public struct LibreLinkUpGlucose: Sendable {
    public let value: Double           // mg/dL
    public let timestamp: Date
    public let trend: GlucoseTrend
    
    public func toGlucoseReading() -> GlucoseReading {
        GlucoseReading(
            glucose: value,
            timestamp: timestamp,
            trend: trend,
            source: "LibreLinkUp"
        )
    }
}

/// LibreLink Up connection (patient)
public struct LibreLinkUpConnection: Sendable {
    public let patientId: String
    public let firstName: String?
    public let lastName: String?
    public let latestGlucose: LibreLinkUpGlucose?
    
    public var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Error Types

public enum LibreLinkUpError: Error, Sendable, LocalizedError {
    case authenticationFailed
    case invalidCredentials
    case accountLocked
    case termsNotAccepted
    case regionRedirect(String)
    case sessionExpired
    case noConnections
    case networkError(String)
    case parseError
    case notImplemented
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "LibreLink Up authentication failed."
        case .invalidCredentials:
            return "Invalid LibreLink Up email or password."
        case .accountLocked:
            return "Your LibreLink Up account is locked. Please try again later."
        case .termsNotAccepted:
            return "Please accept the LibreLink Up terms of service in the official app."
        case .regionRedirect(let region):
            return "Your account requires the \(region) server. Please update your region setting."
        case .sessionExpired:
            return "Your LibreLink Up session has expired. Please sign in again."
        case .noConnections:
            return "No sensor connections found in your LibreLink Up account."
        case .networkError(let message):
            return "Network error connecting to LibreLink Up: \(message)"
        case .parseError:
            return "Failed to parse LibreLink Up response."
        case .notImplemented:
            return "This LibreLink Up feature is not yet implemented."
        }
    }
}

// MARK: - Client

/// LibreLink Up API client
/// Requirements: REQ-CGM-002, PRD-004 CGM-006
public actor LibreLinkUpClient {
    private var credentials: LibreLinkUpCredentials
    private var authToken: String?
    private var tokenExpiry: Date?
    private var patientId: String?
    
    // API headers
    private let version = "4.7.0"
    private let product = "llu.ios"
    
    public init(credentials: LibreLinkUpCredentials) {
        self.credentials = credentials
    }
    
    /// Authenticate and get auth token
    public func authenticate() async throws -> String {
        let url = credentials.region.baseURL.appendingPathComponent("auth/login")
        
        let body: [String: String] = [
            "email": credentials.email,
            "password": credentials.password
        ]
        
        let response: LibreLinkUpLoginResponse = try await postJSON(url: url, body: body)
        
        // Check for region redirect
        if let redirect = response.data?.redirect, redirect,
           let newRegion = response.data?.region {
            throw LibreLinkUpError.regionRedirect(newRegion)
        }
        
        guard response.status == 0,
              let authTicket = response.data?.authTicket else {
            if response.status == 2 {
                throw LibreLinkUpError.invalidCredentials
            }
            throw LibreLinkUpError.authenticationFailed
        }
        
        self.authToken = authTicket.token
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(authTicket.duration))
        
        return authTicket.token
    }
    
    /// Fetch available connections (patients)
    public func fetchConnections() async throws -> [LibreLinkUpConnection] {
        try await ensureAuthenticated()
        
        let url = credentials.region.baseURL.appendingPathComponent("connections")
        let response: LibreLinkUpConnectionsResponse = try await getJSON(url: url)
        
        guard response.status == 0, let connections = response.data else {
            throw LibreLinkUpError.noConnections
        }
        
        return connections.map { conn in
            var latestGlucose: LibreLinkUpGlucose?
            if let measurement = conn.glucoseMeasurement {
                latestGlucose = LibreLinkUpGlucose(
                    value: measurement.Value,
                    timestamp: parseTimestamp(measurement.Timestamp) ?? Date(),
                    trend: trendFromArrow(measurement.TrendArrow ?? 0)
                )
            }
            
            return LibreLinkUpConnection(
                patientId: conn.patientId,
                firstName: conn.firstName,
                lastName: conn.lastName,
                latestGlucose: latestGlucose
            )
        }
    }
    
    /// Set the active patient ID
    public func selectPatient(_ patientId: String) {
        self.patientId = patientId
    }
    
    /// Fetch glucose history for selected patient
    public func fetchGlucoseHistory() async throws -> [GlucoseReading] {
        try await ensureAuthenticated()
        
        if patientId == nil {
            // Try to get first connection
            let connections = try await fetchConnections()
            guard let first = connections.first else {
                throw LibreLinkUpError.noConnections
            }
            self.patientId = first.patientId
        }
        
        guard let currentPatientId = patientId else {
            throw LibreLinkUpError.noConnections
        }
        
        let url = credentials.region.baseURL
            .appendingPathComponent("connections")
            .appendingPathComponent(currentPatientId)
            .appendingPathComponent("graph")
        
        let response: LibreLinkUpGraphResponse = try await getJSON(url: url)
        
        guard response.status == 0, let graphData = response.data?.graphData else {
            return []
        }
        
        return graphData.compactMap { entry -> GlucoseReading? in
            guard let timestamp = parseTimestamp(entry.Timestamp) else { return nil }
            return GlucoseReading(
                glucose: entry.Value,
                timestamp: timestamp,
                trend: .notComputable,  // Historical data doesn't have trend
                source: "LibreLinkUp"
            )
        }
    }
    
    /// Get the latest glucose reading
    public func fetchLatest() async throws -> GlucoseReading? {
        try await ensureAuthenticated()
        
        let connections = try await fetchConnections()
        
        // Use selected patient or first available
        let connection: LibreLinkUpConnection?
        if let patientId = patientId {
            connection = connections.first { $0.patientId == patientId }
        } else {
            connection = connections.first
            self.patientId = connection?.patientId
        }
        
        return connection?.latestGlucose?.toGlucoseReading()
    }
    
    // MARK: - Helpers
    
    private func ensureAuthenticated() async throws {
        if authToken == nil || (tokenExpiry ?? Date.distantPast) < Date() {
            _ = try await authenticate()
        }
    }
    
    private func parseTimestamp(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        
        // Try ISO8601 format first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        
        // Try MM/dd/yyyy format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy h:mm:ss a"
        return dateFormatter.date(from: string)
    }
    
    private func trendFromArrow(_ arrow: Int) -> GlucoseTrend {
        // LibreLink trend arrows: 1=Down, 2=FortyFiveDown, 3=Flat, 4=FortyFiveUp, 5=Up
        switch arrow {
        case 1: return .singleDown
        case 2: return .fortyFiveDown
        case 3: return .flat
        case 4: return .fortyFiveUp
        case 5: return .singleUp
        default: return .notComputable
        }
    }
    
    // MARK: - Network
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    
    private func postJSON<T: Decodable>(url: URL, body: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(version, forHTTPHeaderField: "version")
        request.setValue(product, forHTTPHeaderField: "product")
        request.httpBody = try JSONEncoder().encode(body)
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibreLinkUpError.networkError("Invalid response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                authToken = nil
                throw LibreLinkUpError.sessionExpired
            }
            throw LibreLinkUpError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func getJSON<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(version, forHTTPHeaderField: "version")
        request.setValue(product, forHTTPHeaderField: "product")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibreLinkUpError.networkError("Invalid response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                authToken = nil
                throw LibreLinkUpError.sessionExpired
            }
            throw LibreLinkUpError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    #else
    
    // Linux stubs
    private func postJSON<T: Decodable>(url: URL, body: [String: String]) async throws -> T {
        throw LibreLinkUpError.notImplemented
    }
    
    private func getJSON<T: Decodable>(url: URL) async throws -> T {
        throw LibreLinkUpError.notImplemented
    }
    
    #endif
}

// MARK: - CGM Manager Integration

/// LibreLink Up CGM driver
/// Requirements: REQ-CGM-002, PRD-004 CGM-006
public actor LibreLinkUpCGM: CGMManagerProtocol {
    public let displayName = "LibreLink Up"
    public let cgmType = CGMType.libre2  // Uses same type as direct Libre
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private let client: LibreLinkUpClient
    private var fetchTask: Task<Void, Never>?
    private let fetchIntervalSeconds: TimeInterval
    
    public init(credentials: LibreLinkUpCredentials, fetchIntervalSeconds: TimeInterval = 60) {
        self.client = LibreLinkUpClient(credentials: credentials)
        self.fetchIntervalSeconds = fetchIntervalSeconds
    }
    
    public func startScanning() async throws {
        do {
            _ = try await client.authenticate()
            sensorState = .active
            onSensorStateChanged?(.active)
        } catch LibreLinkUpError.regionRedirect(let region) {
            // Handle region redirect
            onError?(.connectionFailed)
            throw LibreLinkUpError.regionRedirect(region)
        } catch {
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw error
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
        startFetching()
    }
    
    public func disconnect() async {
        fetchTask?.cancel()
        fetchTask = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    /// Select a specific patient (for multi-follower accounts)
    public func selectPatient(_ patientId: String) async {
        await client.selectPatient(patientId)
    }
    
    /// Get available connections
    public func fetchConnections() async throws -> [LibreLinkUpConnection] {
        try await client.fetchConnections()
    }
    
    private func startFetching() {
        fetchTask = Task {
            while !Task.isCancelled {
                await fetchLatest()
                try? await Task.sleep(nanoseconds: UInt64(fetchIntervalSeconds * 1_000_000_000))
            }
        }
    }
    
    private func fetchLatest() async {
        do {
            if let reading = try await client.fetchLatest() {
                latestReading = reading
                onReadingReceived?(reading)
            }
        } catch {
            onError?(.dataUnavailable)
        }
    }
}
