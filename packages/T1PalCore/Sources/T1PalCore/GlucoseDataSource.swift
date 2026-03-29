// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// GlucoseDataSource.swift - Protocol for glucose data providers
// Part of T1PalCore
//
// This protocol abstracts glucose data fetching for charts and displays.
// Implementations include NightscoutDataSource, DemoDataSource, CGMDataSource.

import Foundation

// MARK: - GlucoseDataSource Protocol

/// Protocol for fetching glucose readings from various sources
public protocol GlucoseDataSource: Sendable {
    /// Unique identifier for this data source
    var id: String { get }
    
    /// Human-readable name
    var name: String { get }
    
    /// Current connection status
    var status: DataSourceStatus { get async }
    
    /// Fetch recent glucose readings
    /// - Parameter count: Maximum number of readings to fetch
    /// - Returns: Array of glucose readings, most recent first
    func fetchRecentReadings(count: Int) async throws -> [GlucoseReading]
    
    /// Fetch glucose readings within a time range
    /// - Parameters:
    ///   - from: Start of time range
    ///   - to: End of time range
    /// - Returns: Array of glucose readings within the range
    func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading]
    
    /// Get the most recent reading if available
    func latestReading() async throws -> GlucoseReading?
}

// MARK: - Default Implementations

public extension GlucoseDataSource {
    /// Default implementation: fetch most recent reading
    func latestReading() async throws -> GlucoseReading? {
        try await fetchRecentReadings(count: 1).first
    }
}

// MARK: - Data Source Status

/// Connection/availability status of a data source
public enum DataSourceStatus: String, Codable, Sendable {
    case connected
    case connecting
    case disconnected
    case error
    case unauthorized
    case configurationRequired
    
    public var isAvailable: Bool {
        self == .connected
    }
    
    public var icon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.clockwise"
        case .disconnected: return "xmark.circle"
        case .error: return "exclamationmark.triangle"
        case .unauthorized: return "lock.fill"
        case .configurationRequired: return "gear"
        }
    }
}

// MARK: - Data Source Error

/// Errors that can occur when fetching glucose data
public enum DataSourceError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case networkError(underlying: Error)
    case noData
    case parseError(String)
    case timeout
    case rateLimited
    
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Data source is not configured"
        case .unauthorized:
            return "Authentication required"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .noData:
            return "No glucose data available"
        case .parseError(let message):
            return "Failed to parse data: \(message)"
        case .timeout:
            return "Request timed out"
        case .rateLimited:
            return "Too many requests, please wait"
        }
    }
}

// MARK: - Streaming Data Source

/// Protocol for data sources that provide real-time streaming via AsyncStream
public protocol StreamingDataSource: GlucoseDataSource {
    /// Stream of glucose readings updated in real-time
    /// - Parameter interval: Update interval in seconds (default 300 = 5 minutes)
    /// - Returns: AsyncStream of glucose readings
    func stream(interval: TimeInterval) -> AsyncStream<GlucoseReading>
}

public extension StreamingDataSource {
    /// Default stream with 5-minute interval
    func stream() -> AsyncStream<GlucoseReading> {
        stream(interval: 300)
    }
}

// MARK: - Observable Data Source

/// Protocol extension for data sources that can push updates
public protocol ObservableDataSource: GlucoseDataSource {
    /// Subscribe to real-time glucose updates
    /// - Parameter handler: Callback invoked when new readings are available
    /// - Returns: A token that can be used to unsubscribe
    func subscribe(handler: @escaping @Sendable (GlucoseReading) -> Void) -> SubscriptionToken
    
    /// Unsubscribe from updates
    func unsubscribe(token: SubscriptionToken)
}

/// Token for managing data source subscriptions
public struct SubscriptionToken: Hashable, Sendable {
    public let id: UUID
    
    public init() {
        self.id = UUID()
    }
}

// MARK: - Multi-Source Manager Protocol

/// Protocol for managing multiple data sources
public protocol DataSourceManagerProtocol: Sendable {
    /// All available data sources
    var sources: [any GlucoseDataSource] { get async }
    
    /// Currently active data source
    var activeSource: (any GlucoseDataSource)? { get async }
    
    /// Set the active data source
    func setActiveSource(_ source: any GlucoseDataSource) async
    
    /// Fetch from the active source
    func fetchRecentReadings(count: Int) async throws -> [GlucoseReading]
}

// MARK: - Glucose Reading Extensions

public extension GlucoseReading {
    /// Create from NightscoutKit entry values
    /// - Parameters:
    ///   - sgv: Sensor glucose value in mg/dL
    ///   - timestamp: Reading timestamp
    ///   - direction: Trend arrow string
    ///   - source: Device or source identifier
    init(sgv: Int, timestamp: Date, direction: String?, source: String = "Nightscout") {
        self.init(
            id: UUID(),
            glucose: Double(sgv),
            timestamp: timestamp,
            trend: GlucoseTrend(fromDirection: direction),
            source: source
        )
    }
}

public extension GlucoseTrend {
    /// Initialize from Nightscout direction string
    init(fromDirection direction: String?) {
        switch direction?.uppercased() {
        case "DOUBLEUP", "↑↑":
            self = .doubleUp
        case "SINGLEUP", "↑":
            self = .singleUp
        case "FORTYFIVEUP", "↗":
            self = .fortyFiveUp
        case "FLAT", "→":
            self = .flat
        case "FORTYFIVEDOWN", "↘":
            self = .fortyFiveDown
        case "SINGLEDOWN", "↓":
            self = .singleDown
        case "DOUBLEDOWN", "↓↓":
            self = .doubleDown
        default:
            self = .flat
        }
    }
}
