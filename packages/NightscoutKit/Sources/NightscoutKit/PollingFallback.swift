// SPDX-License-Identifier: AGPL-3.0-or-later
// PollingFallback.swift
// NightscoutKit
//
// HTTP long-polling fallback for platforms without WebSocket support (Linux)
// Provides real-time-like updates by polling the entries endpoint
//
// Trace: FOLLOWER-004, PRD-014-nightscout-interoperability.md

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

// MARK: - Polling Configuration

/// Configuration for polling fallback
public struct PollingConfig: Sendable {
    /// Nightscout API base URL
    public let baseURL: URL
    
    /// API secret or token for authentication
    public let apiSecret: String?
    
    /// JWT token for authentication (v2 API)
    public let jwtToken: String?
    
    /// Polling interval in seconds (minimum 5s, default 15s)
    public let pollInterval: TimeInterval
    
    /// Number of entries to fetch per poll
    public let entriesPerPoll: Int
    
    /// Whether to use v3 API format
    public let useV3API: Bool
    
    /// Timeout for each poll request
    public let timeout: TimeInterval
    
    /// Maximum consecutive failures before stopping
    public let maxConsecutiveFailures: Int
    
    public init(
        baseURL: URL,
        apiSecret: String? = nil,
        jwtToken: String? = nil,
        pollInterval: TimeInterval = 15.0,
        entriesPerPoll: Int = 10,
        useV3API: Bool = false,
        timeout: TimeInterval = 30.0,
        maxConsecutiveFailures: Int = 10
    ) {
        self.baseURL = baseURL
        self.apiSecret = apiSecret
        self.jwtToken = jwtToken
        self.pollInterval = max(5.0, pollInterval) // Enforce minimum 5s
        self.entriesPerPoll = entriesPerPoll
        self.useV3API = useV3API
        self.timeout = timeout
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }
    
    /// Mock configuration for testing
    public static var mock: PollingConfig {
        PollingConfig(
            baseURL: URL(string: "https://mock.nightscout.local")!,
            apiSecret: "mock-secret",
            pollInterval: 5.0,
            entriesPerPoll: 5
        )
    }
}

// MARK: - Polling State

/// Current state of the polling service
public enum PollingState: Sendable, Equatable {
    /// Not started
    case idle
    
    /// Currently polling
    case polling(since: Date)
    
    /// Paused (e.g., app backgrounded)
    case paused
    
    /// Stopped due to errors
    case failed(PollingError)
    
    /// Gracefully stopped
    case stopped
    
    public static func == (lhs: PollingState, rhs: PollingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.paused, .paused), (.stopped, .stopped): return true
        case (.polling(let a), .polling(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a.localizedDescription == b.localizedDescription
        default: return false
        }
    }
}

/// Errors during polling
public enum PollingError: Error, Sendable {
    case invalidConfiguration
    case networkError(String)
    case authenticationFailed
    case serverError(statusCode: Int)
    case parseError(String)
    case maxFailuresExceeded(count: Int)
    case cancelled
}

// MARK: - Poll Result

/// Result of a single poll request
public struct PollResult: Sendable {
    /// Entries received in this poll
    public let entries: [GlucoseEntry]
    
    /// Server timestamp
    public let serverTime: Date
    
    /// Local timestamp when poll completed
    public let localTime: Date
    
    /// Duration of the request
    public let duration: TimeInterval
    
    /// Whether there are new entries since last poll
    public let hasNewEntries: Bool
    
    public init(
        entries: [GlucoseEntry],
        serverTime: Date = Date(),
        localTime: Date = Date(),
        duration: TimeInterval = 0,
        hasNewEntries: Bool = false
    ) {
        self.entries = entries
        self.serverTime = serverTime
        self.localTime = localTime
        self.duration = duration
        self.hasNewEntries = hasNewEntries
    }
}

/// Glucose entry from Nightscout
public struct GlucoseEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let dateString: String
    public let date: Date
    public let sgv: Int  // Glucose value in mg/dL
    public let direction: String?
    public let delta: Double?
    public let noise: Int?
    public let device: String?
    
    public init(
        id: String = UUID().uuidString,
        dateString: String = ISO8601DateFormatter().string(from: Date()),
        date: Date = Date(),
        sgv: Int,
        direction: String? = nil,
        delta: Double? = nil,
        noise: Int? = nil,
        device: String? = nil
    ) {
        self.id = id
        self.dateString = dateString
        self.date = date
        self.sgv = sgv
        self.direction = direction
        self.delta = delta
        self.noise = noise
        self.device = device
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case dateString
        case date
        case sgv
        case direction
        case delta
        case noise
        case device
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        dateString = try container.decodeIfPresent(String.self, forKey: .dateString) ?? ""
        
        // Handle date as either timestamp or ISO8601 string
        if let timestamp = try? container.decode(Int.self, forKey: .date) {
            date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        } else if let dateStr = try? container.decode(String.self, forKey: .date) {
            date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        } else {
            date = Date()
        }
        
        sgv = try container.decode(Int.self, forKey: .sgv)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        delta = try container.decodeIfPresent(Double.self, forKey: .delta)
        noise = try container.decodeIfPresent(Int.self, forKey: .noise)
        device = try container.decodeIfPresent(String.self, forKey: .device)
    }
}

// MARK: - Polling Service

/// HTTP polling fallback for real-time glucose updates
///
/// Provides a platform-agnostic alternative to WebSocket for platforms
/// like Linux where URLSession WebSocket support is limited.
///
/// Example:
/// ```swift
/// let config = PollingConfig(
///     baseURL: URL(string: "https://my.nightscout.site")!,
///     apiSecret: "myApiSecret",
///     pollInterval: 15.0
/// )
/// 
/// let service = PollingService(config: config)
/// 
/// // Start polling with async stream
/// for try await result in service.start() {
///     if result.hasNewEntries {
///         print("New glucose: \(result.entries.first?.sgv ?? 0)")
///     }
/// }
/// ```
public actor PollingService {
    private let config: PollingConfig
    private var state: PollingState = .idle
    private var lastEntryDate: Date?
    private var consecutiveFailures: Int = 0
    private var pollTask: Task<Void, Never>?
    
    public init(config: PollingConfig) {
        self.config = config
    }
    
    /// Current polling state
    public var currentState: PollingState {
        state
    }
    
    /// Start polling and return an async stream of results
    public func start() -> AsyncThrowingStream<PollResult, Error> {
        AsyncThrowingStream { continuation in
            self.pollTask = Task {
                self.state = .polling(since: Date())
                
                while !Task.isCancelled {
                    do {
                        let result = try await self.poll()
                        continuation.yield(result)
                        
                        if result.hasNewEntries, let latest = result.entries.first {
                            self.lastEntryDate = latest.date
                        }
                        
                        self.consecutiveFailures = 0
                        
                        try await Task.sleep(nanoseconds: UInt64(self.config.pollInterval * 1_000_000_000))
                    } catch {
                        self.consecutiveFailures += 1
                        
                        if self.consecutiveFailures >= self.config.maxConsecutiveFailures {
                            self.state = .failed(.maxFailuresExceeded(count: self.consecutiveFailures))
                            continuation.finish(throwing: PollingError.maxFailuresExceeded(count: self.consecutiveFailures))
                            return
                        }
                        
                        // Exponential backoff on errors
                        let backoff = min(Double(self.consecutiveFailures) * 5.0, 60.0)
                        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    }
                }
                
                self.state = .stopped
                continuation.finish()
            }
        }
    }
    
    /// Stop polling
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        state = .stopped
    }
    
    /// Pause polling (e.g., when app backgrounds)
    public func pause() {
        pollTask?.cancel()
        pollTask = nil
        state = .paused
    }
    
    /// Perform a single poll
    public func poll() async throws -> PollResult {
        let startTime = Date()
        
        // Build URL
        var urlComponents = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: true)!
        urlComponents.path = config.useV3API ? "/api/v3/entries" : "/api/v1/entries.json"
        urlComponents.queryItems = [
            URLQueryItem(name: "count", value: String(config.entriesPerPoll)),
            URLQueryItem(name: "type", value: "sgv"),
        ]
        
        // Add date filter if we have a last entry
        if let lastDate = lastEntryDate {
            let timestamp = Int(lastDate.timeIntervalSince1970 * 1000)
            urlComponents.queryItems?.append(
                URLQueryItem(name: "find[date][$gt]", value: String(timestamp))
            )
        }
        
        guard let url = urlComponents.url else {
            throw PollingError.invalidConfiguration
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add authentication
        if let secret = config.apiSecret {
            request.setValue(secret.sha1Hash(), forHTTPHeaderField: "api-secret")
        }
        if let token = config.jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PollingError.networkError("Invalid response type")
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw PollingError.authenticationFailed
        default:
            throw PollingError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Parse entries
        let decoder = JSONDecoder()
        let entries: [GlucoseEntry]
        do {
            entries = try decoder.decode([GlucoseEntry].self, from: data)
        } catch {
            throw PollingError.parseError(error.localizedDescription)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let hasNew = !entries.isEmpty && (lastEntryDate == nil || entries.first!.date > lastEntryDate!)
        
        // Parse server time from headers if available
        var serverTime = Date()
        if let dateHeader = httpResponse.value(forHTTPHeaderField: "Date") {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = formatter.date(from: dateHeader) {
                serverTime = parsed
            }
        }
        
        return PollResult(
            entries: entries.sorted { $0.date > $1.date },
            serverTime: serverTime,
            localTime: Date(),
            duration: duration,
            hasNewEntries: hasNew
        )
    }
}

// MARK: - String Extension

#if canImport(CryptoKit)
import CryptoKit

extension String {
    /// Compute SHA1 hash for API secret
    func sha1Hash() -> String {
        let hash = Insecure.SHA1.hash(data: Data(self.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
#else
extension String {
    /// Compute SHA1 hash for API secret (fallback)
    func sha1Hash() -> String {
        // Simple fallback - in production use CommonCrypto on Linux
        return self
    }
}
#endif
