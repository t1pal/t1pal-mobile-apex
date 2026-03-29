// SPDX-License-Identifier: AGPL-3.0-or-later
// NightscoutKit - MockNightscoutServer
// INT-001: Mock Nightscout server for offline testing
// Provides deterministic NS responses without network dependency

import Foundation

// MARK: - Mock Response Types

/// Represents a mock Nightscout server response
public struct MockNightscoutResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]
    public let delay: TimeInterval
    
    public init(
        statusCode: Int = 200,
        data: Data = Data(),
        headers: [String: String] = ["Content-Type": "application/json"],
        delay: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
        self.delay = delay
    }
    
    /// Create a successful JSON response
    public static func json(_ string: String, statusCode: Int = 200, delay: TimeInterval = 0) -> MockNightscoutResponse {
        MockNightscoutResponse(
            statusCode: statusCode,
            data: string.data(using: .utf8) ?? Data(),
            headers: ["Content-Type": "application/json"],
            delay: delay
        )
    }
    
    /// Create an error response
    public static func error(statusCode: Int, message: String = "Error") -> MockNightscoutResponse {
        let json = #"{"status": \#(statusCode), "message": "\#(message)"}"#
        return MockNightscoutResponse(
            statusCode: statusCode,
            data: json.data(using: .utf8) ?? Data(),
            headers: ["Content-Type": "application/json"]
        )
    }
    
    /// 401 Unauthorized
    public static var unauthorized: MockNightscoutResponse {
        .error(statusCode: 401, message: "Unauthorized")
    }
    
    /// 500 Internal Server Error
    public static var serverError: MockNightscoutResponse {
        .error(statusCode: 500, message: "Internal Server Error")
    }
    
    /// Empty success response
    public static var emptySuccess: MockNightscoutResponse {
        MockNightscoutResponse(statusCode: 200, data: "[]".data(using: .utf8)!)
    }
    
    /// Network timeout simulation
    public static func timeout(after seconds: TimeInterval = 30) -> MockNightscoutResponse {
        MockNightscoutResponse(statusCode: 0, data: Data(), delay: seconds)
    }
    
    /// 207 Multi-Status partial success response
    public static func partialSuccess(inserted: Int, failed: Int) -> MockNightscoutResponse {
        let json = """
        {
            "ok": false,
            "inserted": \(inserted),
            "failed": \(failed),
            "results": []
        }
        """
        return MockNightscoutResponse(
            statusCode: 207,
            data: json.data(using: .utf8)!,
            headers: ["Content-Type": "application/json"]
        )
    }
}

// MARK: - Endpoint Matching

/// Matches URL paths to mock responses
public enum MockEndpointMatcher: Sendable {
    case exact(String)
    case prefix(String)
    case regex(String)
    case any
    
    public func matches(_ path: String) -> Bool {
        switch self {
        case .exact(let pattern):
            return path == pattern
        case .prefix(let pattern):
            return path.hasPrefix(pattern)
        case .regex(let pattern):
            return (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                in: path,
                range: NSRange(path.startIndex..., in: path)
            ) != nil
        case .any:
            return true
        }
    }
}

/// A registered mock endpoint
public struct MockEndpoint: Sendable {
    public let method: String
    public let matcher: MockEndpointMatcher
    public let response: MockNightscoutResponse
    
    public init(method: String = "GET", matcher: MockEndpointMatcher, response: MockNightscoutResponse) {
        self.method = method.uppercased()
        self.matcher = matcher
        self.response = response
    }
}

// MARK: - Mock Nightscout Server

/// Mock Nightscout server for offline testing
/// Provides deterministic responses without network dependency
public actor MockNightscoutServer {
    
    /// Registered endpoints and their responses
    private var endpoints: [MockEndpoint] = []
    
    /// Request history for verification
    private var requestHistory: [RecordedRequest] = []
    
    /// Whether to record requests
    public var recordRequests: Bool = true
    
    /// Default response for unmatched requests
    public var defaultResponse: MockNightscoutResponse = .error(statusCode: 404, message: "Not Found")
    
    public init() {
        // Register default endpoints synchronously during init
        registerDefaultEndpointsSync()
    }
    
    // MARK: - Endpoint Registration
    
    /// Register a mock endpoint
    public func register(_ endpoint: MockEndpoint) {
        endpoints.append(endpoint)
    }
    
    /// Register multiple endpoints
    public func register(_ newEndpoints: [MockEndpoint]) {
        endpoints.append(contentsOf: newEndpoints)
    }
    
    /// Register a GET endpoint with a response
    public func registerGET(_ path: String, response: MockNightscoutResponse) {
        register(MockEndpoint(method: "GET", matcher: .prefix(path), response: response))
    }
    
    /// Register a POST endpoint with a response
    public func registerPOST(_ path: String, response: MockNightscoutResponse) {
        register(MockEndpoint(method: "POST", matcher: .prefix(path), response: response))
    }
    
    /// Clear all registered endpoints
    public func clearEndpoints() {
        endpoints.removeAll()
    }
    
    /// Reset to default state
    public func reset() {
        endpoints.removeAll()
        requestHistory.removeAll()
        registerDefaultEndpoints()
    }
    
    // MARK: - Request Handling
    
    /// Handle a mock request and return a response
    public func handleRequest(method: String, path: String, body: Data? = nil, headers: [String: String] = [:]) async -> MockNightscoutResponse {
        // Ensure defaults are registered
        ensureDefaultEndpoints()
        
        // Record request
        if recordRequests {
            requestHistory.append(RecordedRequest(
                method: method,
                path: path,
                body: body,
                headers: headers,
                timestamp: Date()
            ))
        }
        
        // Find matching endpoint (last registered wins for same matcher)
        for endpoint in endpoints.reversed() {
            if endpoint.method == method.uppercased() && endpoint.matcher.matches(path) {
                // Apply delay if specified
                if endpoint.response.delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(endpoint.response.delay * 1_000_000_000))
                }
                return endpoint.response
            }
        }
        
        return defaultResponse
    }
    
    // MARK: - Request History
    
    /// Get all recorded requests
    public func getRequestHistory() -> [RecordedRequest] {
        requestHistory
    }
    
    /// Get requests matching a path
    public func getRequests(matching path: String) -> [RecordedRequest] {
        requestHistory.filter { $0.path.contains(path) }
    }
    
    /// Clear request history
    public func clearHistory() {
        requestHistory.removeAll()
    }
    
    /// Check if a specific endpoint was called
    public func wasCalled(method: String, path: String) -> Bool {
        requestHistory.contains { $0.method == method.uppercased() && $0.path.contains(path) }
    }
    
    /// Count calls to an endpoint
    public func callCount(method: String, path: String) -> Int {
        requestHistory.filter { $0.method == method.uppercased() && $0.path.contains(path) }.count
    }
    
    // MARK: - Default Endpoints
    
    /// Synchronous version for init (nonisolated context)
    private nonisolated func registerDefaultEndpointsSync() {
        // Endpoints will be registered on first access via reset() or handleRequest()
        // This is a no-op - we'll use lazy initialization instead
    }
    
    private func registerDefaultEndpoints() {
        // Status endpoint
        registerGET("/api/v1/status", response: .json(MockNightscoutData.statusJSON))
        
        // Entries endpoints
        registerGET("/api/v1/entries", response: .json(MockNightscoutData.entriesJSON))
        registerGET("/api/v1/entries/sgv", response: .json(MockNightscoutData.entriesJSON))
        registerGET("/api/v1/entries/current", response: .json(MockNightscoutData.currentEntryJSON))
        registerPOST("/api/v1/entries", response: .json(#"{"ok": true}"#))
        
        // Treatments endpoints
        registerGET("/api/v1/treatments", response: .json(MockNightscoutData.treatmentsJSON))
        registerPOST("/api/v1/treatments", response: .json(#"{"ok": true}"#))
        
        // Device status endpoints
        registerGET("/api/v1/devicestatus", response: .json(MockNightscoutData.deviceStatusJSON))
        registerPOST("/api/v1/devicestatus", response: .json(#"{"ok": true}"#))
        
        // Profile endpoints
        registerGET("/api/v1/profile", response: .json(MockNightscoutData.profileJSON))
        registerPOST("/api/v1/profile", response: .json(#"{"ok": true}"#))
    }
    
    /// Ensure default endpoints are registered (lazy init)
    private func ensureDefaultEndpoints() {
        if endpoints.isEmpty {
            registerDefaultEndpoints()
        }
    }
}

// MARK: - Recorded Request

/// A recorded mock request for verification
public struct RecordedRequest: Sendable {
    public let method: String
    public let path: String
    public let body: Data?
    public let headers: [String: String]
    public let timestamp: Date
    
    /// Decode body as JSON
    public func bodyJSON<T: Decodable>(as type: T.Type) -> T? {
        guard let body = body else { return nil }
        return try? JSONDecoder().decode(type, from: body)
    }
    
    /// Get body as string
    public var bodyString: String? {
        guard let body = body else { return nil }
        return String(data: body, encoding: .utf8)
    }
}

// MARK: - Mock Data

/// Pre-built mock Nightscout data for common scenarios
public enum MockNightscoutData {
    
    // MARK: - Status
    
    public static let statusJSON = """
    {
        "status": "ok",
        "name": "Mock Nightscout",
        "version": "14.2.6",
        "serverTime": "\(ISO8601DateFormatter().string(from: Date()))",
        "apiEnabled": true,
        "careportalEnabled": true,
        "head": "abc123",
        "settings": {
            "units": "mg/dl",
            "timeFormat": 12,
            "language": "en"
        }
    }
    """
    
    // MARK: - Entries
    
    public static var entriesJSON: String {
        let now = Date()
        var entries: [[String: Any]] = []
        
        // Generate 12 entries (1 hour of data at 5-min intervals)
        for i in 0..<12 {
            let date = now.addingTimeInterval(Double(-i * 300))
            let dateMs = Int64(date.timeIntervalSince1970 * 1000)
            let sgv = 120 + (i % 3) * 10 - (i % 5) * 5 // Some variation
            
            entries.append([
                "sgv": sgv,
                "date": dateMs,
                "dateString": ISO8601DateFormatter().string(from: date),
                "trend": 4,
                "direction": "Flat",
                "device": "MockCGM",
                "type": "sgv"
            ])
        }
        
        return try! String(data: JSONSerialization.data(withJSONObject: entries), encoding: .utf8)!
    }
    
    public static var currentEntryJSON: String {
        let now = Date()
        let dateMs = Int64(now.timeIntervalSince1970 * 1000)
        return """
        {
            "sgv": 120,
            "date": \(dateMs),
            "dateString": "\(ISO8601DateFormatter().string(from: now))",
            "trend": 4,
            "direction": "Flat",
            "device": "MockCGM",
            "type": "sgv"
        }
        """
    }
    
    // MARK: - Treatments
    
    public static var treatmentsJSON: String {
        let now = Date()
        return """
        [
            {
                "eventType": "Temp Basal",
                "rate": 0.5,
                "duration": 30,
                "created_at": "\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-1800)))",
                "enteredBy": "Loop"
            },
            {
                "eventType": "Meal Bolus",
                "insulin": 5.0,
                "carbs": 45,
                "created_at": "\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600)))",
                "enteredBy": "Loop"
            },
            {
                "eventType": "Correction Bolus",
                "insulin": 1.5,
                "created_at": "\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-7200)))",
                "enteredBy": "Loop"
            }
        ]
        """
    }
    
    // MARK: - Device Status
    
    public static var deviceStatusJSON: String {
        let now = Date()
        return """
        [
            {
                "device": "loop://iPhone",
                "created_at": "\(ISO8601DateFormatter().string(from: now))",
                "loop": {
                    "iob": {
                        "iob": 2.5,
                        "timestamp": "\(ISO8601DateFormatter().string(from: now))"
                    },
                    "cob": {
                        "cob": 30.0,
                        "timestamp": "\(ISO8601DateFormatter().string(from: now))"
                    },
                    "predicted": {
                        "values": [120, 125, 130, 128, 122, 118, 115, 112, 110]
                    },
                    "enacted": {
                        "rate": 0.5,
                        "duration": 30,
                        "timestamp": "\(ISO8601DateFormatter().string(from: now))"
                    }
                },
                "pump": {
                    "reservoir": 150.0,
                    "battery": {"percent": 75}
                }
            }
        ]
        """
    }
    
    // MARK: - Profile
    
    public static let profileJSON = """
    [
        {
            "defaultProfile": "Default",
            "store": {
                "Default": {
                    "dia": 6,
                    "carbratio": [{"time": "00:00", "value": 10}],
                    "sens": [{"time": "00:00", "value": 50}],
                    "basal": [{"time": "00:00", "value": 1.0}],
                    "target_low": [{"time": "00:00", "value": 100}],
                    "target_high": [{"time": "00:00", "value": 120}],
                    "timezone": "America/Los_Angeles",
                    "units": "mg/dl"
                }
            },
            "startDate": "2024-01-01T00:00:00.000Z"
        }
    ]
    """
    
    // MARK: - Scenario Presets
    
    /// Generate entries for a low glucose scenario
    public static func lowGlucoseEntries(count: Int = 12) -> String {
        let now = Date()
        var entries: [[String: Any]] = []
        
        for i in 0..<count {
            let date = now.addingTimeInterval(Double(-i * 300))
            let dateMs = Int64(date.timeIntervalSince1970 * 1000)
            let sgv = max(55, 70 - i * 2) // Falling to 55
            
            entries.append([
                "sgv": sgv,
                "date": dateMs,
                "dateString": ISO8601DateFormatter().string(from: date),
                "trend": 6,
                "direction": "SingleDown",
                "device": "MockCGM",
                "type": "sgv"
            ])
        }
        
        return try! String(data: JSONSerialization.data(withJSONObject: entries), encoding: .utf8)!
    }
    
    /// Generate entries for a high glucose scenario
    public static func highGlucoseEntries(count: Int = 12) -> String {
        let now = Date()
        var entries: [[String: Any]] = []
        
        for i in 0..<count {
            let date = now.addingTimeInterval(Double(-i * 300))
            let dateMs = Int64(date.timeIntervalSince1970 * 1000)
            let sgv = min(300, 200 + i * 5) // Rising to 300
            
            entries.append([
                "sgv": sgv,
                "date": dateMs,
                "dateString": ISO8601DateFormatter().string(from: date),
                "trend": 2,
                "direction": "SingleUp",
                "device": "MockCGM",
                "type": "sgv"
            ])
        }
        
        return try! String(data: JSONSerialization.data(withJSONObject: entries), encoding: .utf8)!
    }
    
    /// Generate entries for stable in-range glucose
    public static func stableGlucoseEntries(count: Int = 12, around: Int = 110) -> String {
        let now = Date()
        var entries: [[String: Any]] = []
        
        for i in 0..<count {
            let date = now.addingTimeInterval(Double(-i * 300))
            let dateMs = Int64(date.timeIntervalSince1970 * 1000)
            let sgv = around + (i % 3 - 1) * 3 // Small variation ±3
            
            entries.append([
                "sgv": sgv,
                "date": dateMs,
                "dateString": ISO8601DateFormatter().string(from: date),
                "trend": 4,
                "direction": "Flat",
                "device": "MockCGM",
                "type": "sgv"
            ])
        }
        
        return try! String(data: JSONSerialization.data(withJSONObject: entries), encoding: .utf8)!
    }
}

// MARK: - Scenario Configuration

/// Pre-configured mock server scenarios
public enum MockNightscoutScenario {
    case normal
    case lowGlucose
    case highGlucose
    case stableInRange
    case unauthorized
    case serverError
    case staleData
    case noData
    
    /// Configure a mock server for this scenario
    public func configure(_ server: MockNightscoutServer) async {
        await server.reset()
        
        switch self {
        case .normal:
            // Default configuration is already normal
            break
            
        case .lowGlucose:
            await server.registerGET("/api/v1/entries", response: .json(MockNightscoutData.lowGlucoseEntries()))
            
        case .highGlucose:
            await server.registerGET("/api/v1/entries", response: .json(MockNightscoutData.highGlucoseEntries()))
            
        case .stableInRange:
            await server.registerGET("/api/v1/entries", response: .json(MockNightscoutData.stableGlucoseEntries()))
            
        case .unauthorized:
            await server.register(MockEndpoint(method: "GET", matcher: .any, response: .unauthorized))
            await server.register(MockEndpoint(method: "POST", matcher: .any, response: .unauthorized))
            
        case .serverError:
            await server.register(MockEndpoint(method: "GET", matcher: .any, response: .serverError))
            await server.register(MockEndpoint(method: "POST", matcher: .any, response: .serverError))
            
        case .staleData:
            // Generate entries from 30 minutes ago
            let staleEntries = MockNightscoutData.stableGlucoseEntries(count: 6)
            await server.registerGET("/api/v1/entries", response: .json(staleEntries))
            
        case .noData:
            await server.registerGET("/api/v1/entries", response: .emptySuccess)
            await server.registerGET("/api/v1/treatments", response: .emptySuccess)
        }
    }
}
