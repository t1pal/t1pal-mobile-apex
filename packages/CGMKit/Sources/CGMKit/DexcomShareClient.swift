// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DexcomShareClient.swift
// T1Pal Mobile
//
// Dexcom Share cloud API client
// Requirements: REQ-CGM-004
//
// Reference: https://github.com/nightscout/share2nightscout-bridge

import Foundation
import T1PalCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Configuration

/// Dexcom Share server regions
public enum DexcomShareServer: String, Codable, Sendable {
    case us = "share2.dexcom.com"
    case ous = "shareous1.dexcom.com"  // Outside US
    
    var baseURL: URL {
        URL(string: "https://\(rawValue)/ShareWebServices/Services")!
    }
}

/// Dexcom Share credentials
public struct DexcomShareCredentials: Codable, Sendable {
    public let username: String
    public let password: String
    public let server: DexcomShareServer
    
    public init(username: String, password: String, server: DexcomShareServer = .us) {
        self.username = username
        self.password = password
        self.server = server
    }
}

// MARK: - API Types

/// Dexcom Share glucose reading from API
public struct DexcomShareGlucose: Codable, Sendable {
    public let WT: String           // Weird timestamp format: "/Date(1234567890000)/"
    public let ST: String           // System time
    public let DT: String           // Display time  
    public let Value: Int           // Glucose in mg/dL
    public let Trend: Int           // Trend arrow (1-7)
    
    /// Convert to GlucoseReading
    public func toGlucoseReading() -> GlucoseReading? {
        guard let timestamp = parseTimestamp() else { return nil }
        
        return GlucoseReading(
            glucose: Double(Value),
            timestamp: timestamp,
            trend: trendFromDexcom(Trend),
            source: "DexcomShare"
        )
    }
    
    private func parseTimestamp() -> Date? {
        // Format: "/Date(1234567890000)/"
        let pattern = #"/Date\((\d+)\)/"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: WT, range: NSRange(WT.startIndex..., in: WT)),
              let range = Range(match.range(at: 1), in: WT),
              let milliseconds = Double(WT[range]) else {
            return nil
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
    
    private func trendFromDexcom(_ trend: Int) -> GlucoseTrend {
        // Dexcom trend values: 1=DoubleUp, 2=SingleUp, 3=FortyFiveUp, 4=Flat, 5=FortyFiveDown, 6=SingleDown, 7=DoubleDown
        switch trend {
        case 1: return .doubleUp
        case 2: return .singleUp
        case 3: return .fortyFiveUp
        case 4: return .flat
        case 5: return .fortyFiveDown
        case 6: return .singleDown
        case 7: return .doubleDown
        default: return .notComputable
        }
    }
}

// MARK: - Error Types

public enum DexcomShareError: Error, Sendable, LocalizedError {
    case authenticationFailed
    case sessionExpired
    case accountNotFound
    case invalidCredentials
    case networkError(String)
    case parseError
    case noData
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Dexcom Share authentication failed. Please check your credentials."
        case .sessionExpired:
            return "Your Dexcom Share session has expired. Please sign in again."
        case .accountNotFound:
            return "Dexcom Share account not found. Please verify your username."
        case .invalidCredentials:
            return "Invalid Dexcom Share username or password."
        case .networkError(let message):
            return "Network error connecting to Dexcom Share: \(message)"
        case .parseError:
            return "Failed to parse Dexcom Share response."
        case .noData:
            return "No glucose data available from Dexcom Share."
        }
    }
}

// MARK: - DexcomShareError + T1PalErrorProtocol

extension DexcomShareError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .cgm }
    
    public var code: String {
        switch self {
        case .authenticationFailed: return "DEXSHARE-AUTH-001"
        case .sessionExpired: return "DEXSHARE-AUTH-002"
        case .accountNotFound: return "DEXSHARE-AUTH-003"
        case .invalidCredentials: return "DEXSHARE-AUTH-004"
        case .networkError: return "DEXSHARE-NET-001"
        case .parseError: return "DEXSHARE-PARSE-001"
        case .noData: return "DEXSHARE-DATA-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .authenticationFailed: return .error
        case .sessionExpired: return .warning
        case .accountNotFound: return .error
        case .invalidCredentials: return .error
        case .networkError: return .warning
        case .parseError: return .error
        case .noData: return .warning
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .authenticationFailed: return .retry
        case .sessionExpired: return .retry
        case .accountNotFound: return .contactSupport
        case .invalidCredentials: return .none  // User must fix credentials
        case .networkError: return .retry
        case .parseError: return .contactSupport
        case .noData: return .none  // Transient, will resolve
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown Dexcom Share error"
    }
}

// MARK: - Client

/// Dexcom Share API client
/// Requirements: REQ-CGM-004
public actor DexcomShareClient {
    private let credentials: DexcomShareCredentials
    private var sessionId: String?
    private let applicationId = "d89443d2-327c-4a6f-89e5-496bbb0317db"  // Standard Dexcom app ID
    
    public init(credentials: DexcomShareCredentials) {
        self.credentials = credentials
    }
    
    /// Authenticate and get session ID
    public func authenticate() async throws -> String {
        let url = credentials.server.baseURL
            .appendingPathComponent("General/AuthenticatePublisherAccount")
        
        let body: [String: Any] = [
            "accountName": credentials.username,
            "password": credentials.password,
            "applicationId": applicationId
        ]
        
        let sessionId = try await postJSON(url: url, body: body, responseType: String.self)
        self.sessionId = sessionId
        return sessionId
    }
    
    /// Fetch recent glucose readings
    /// - Parameters:
    ///   - minutes: How far back to fetch (default 1440 = 24 hours)
    ///   - maxCount: Maximum readings to return (default 288 = 24 hours at 5-min intervals)
    public func fetchGlucose(minutes: Int = 1440, maxCount: Int = 288) async throws -> [GlucoseReading] {
        // Ensure we have a session
        if sessionId == nil {
            _ = try await authenticate()
        }
        
        guard let session = sessionId else {
            throw DexcomShareError.sessionExpired
        }
        
        let url = credentials.server.baseURL
            .appendingPathComponent("Publisher/ReadPublisherLatestGlucoseValues")
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: session),
            URLQueryItem(name: "minutes", value: String(minutes)),
            URLQueryItem(name: "maxCount", value: String(maxCount))
        ]
        
        let readings = try await getJSON(url: components.url!, responseType: [DexcomShareGlucose].self)
        
        return readings.compactMap { $0.toGlucoseReading() }
    }
    
    /// Get the latest glucose reading
    public func fetchLatest() async throws -> GlucoseReading? {
        let readings = try await fetchGlucose(minutes: 10, maxCount: 1)
        return readings.first
    }
    
    // MARK: - Network Helpers
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    
    private func postJSON<T: Decodable>(url: URL, body: [String: Any], responseType: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexcomShareError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 500 {
            // Check for specific error codes
            if let errorBody = String(data: data, encoding: .utf8) {
                if errorBody.contains("AccountPasswordInvalid") {
                    throw DexcomShareError.invalidCredentials
                }
                if errorBody.contains("SessionNotValid") {
                    sessionId = nil
                    throw DexcomShareError.sessionExpired
                }
            }
            throw DexcomShareError.authenticationFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DexcomShareError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        // Handle string response (session ID is returned as quoted string)
        if T.self == String.self {
            guard let string = String(data: data, encoding: .utf8) else {
                throw DexcomShareError.parseError
            }
            // Remove quotes
            let cleaned = string.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard let result = cleaned as? T else {
                throw DexcomShareError.parseError
            }
            return result
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func getJSON<T: Decodable>(url: URL, responseType: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DexcomShareError.networkError("Request failed")
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    #else
    
    // Linux stubs - Dexcom Share requires network access
    private func postJSON<T: Decodable>(url: URL, body: [String: Any], responseType: T.Type) async throws -> T {
        throw DexcomShareError.networkError("Not implemented on Linux")
    }
    
    private func getJSON<T: Decodable>(url: URL, responseType: T.Type) async throws -> T {
        throw DexcomShareError.networkError("Not implemented on Linux")
    }
    
    #endif
}

// MARK: - CGM Manager Integration

/// Dexcom Share CGM driver
/// Requirements: REQ-CGM-004
public actor DexcomShareCGM: CGMManagerProtocol {
    public let displayName = "Dexcom Share"
    public let cgmType = CGMType.dexcomShare
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private let client: DexcomShareClient
    private var fetchTask: Task<Void, Never>?
    
    public init(credentials: DexcomShareCredentials) {
        self.client = DexcomShareClient(credentials: credentials)
    }
    
    public func startScanning() async throws {
        // Dexcom Share doesn't need scanning - authenticate instead
        do {
            _ = try await client.authenticate()
            sensorState = .active
            onSensorStateChanged?(.active)
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
    
    private func startFetching() {
        fetchTask = Task {
            while !Task.isCancelled {
                await fetchLatest()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)  // 5 minutes
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
