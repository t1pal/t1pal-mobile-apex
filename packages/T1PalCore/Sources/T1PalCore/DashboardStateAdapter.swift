// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DashboardStateAdapter.swift - Adapts GlucoseDataSource to dashboard state
// Part of T1PalCore
//
// Converts GlucoseReading streams to GlucoseDashboardState for UI display.
// Task: DS-STREAM-001

import Foundation

// MARK: - Dashboard State Adapter

/// Adapts a GlucoseDataSource to produce GlucoseDashboardState for UI
public actor DashboardStateAdapter {
    // MARK: - Dependencies
    
    private let dataSource: any GlucoseDataSource
    private let algorithmStateProvider: AlgorithmStateProvider?
    
    // MARK: - Cached State
    
    private var lastState: DashboardState?
    private var lastUpdate: Date?
    
    // MARK: - Initialization
    
    /// Create an adapter for a data source
    /// - Parameters:
    ///   - dataSource: The glucose data source to adapt
    ///   - algorithmStateProvider: Optional provider for IOB/COB values
    public init(
        dataSource: any GlucoseDataSource,
        algorithmStateProvider: AlgorithmStateProvider? = nil
    ) {
        self.dataSource = dataSource
        self.algorithmStateProvider = algorithmStateProvider
    }
    
    // MARK: - State Generation
    
    /// Fetch current dashboard state from the data source
    /// - Returns: Current dashboard state
    public func currentState() async throws -> DashboardState {
        // Fetch latest reading
        let reading = try await dataSource.latestReading()
        let status = await dataSource.status
        
        // Get algorithm state if available
        let algorithmState = await algorithmStateProvider?.currentState()
        
        // Build dashboard state
        let state = DashboardState(
            glucose: reading.map { GlucoseState(from: $0) },
            connection: ConnectionState(
                status: status,
                sourceName: dataSource.name,
                sourceId: dataSource.id
            ),
            algorithm: algorithmState,
            lastUpdate: Date()
        )
        
        self.lastState = state
        self.lastUpdate = Date()
        
        return state
    }
    
    /// Fetch dashboard state with recent history
    /// - Parameter historyCount: Number of historical readings to include
    /// - Returns: Dashboard state with history
    public func stateWithHistory(count historyCount: Int = 24) async throws -> DashboardState {
        // Fetch readings
        let readings = try await dataSource.fetchRecentReadings(count: historyCount)
        let status = await dataSource.status
        let algorithmState = await algorithmStateProvider?.currentState()
        
        let state = DashboardState(
            glucose: readings.first.map { GlucoseState(from: $0) },
            connection: ConnectionState(
                status: status,
                sourceName: dataSource.name,
                sourceId: dataSource.id
            ),
            algorithm: algorithmState,
            history: readings.map { GlucoseState(from: $0) },
            lastUpdate: Date()
        )
        
        self.lastState = state
        self.lastUpdate = Date()
        
        return state
    }
    
    /// Get cached state without fetching
    public var cachedState: DashboardState? {
        lastState
    }
    
    /// Check if cache is stale
    /// - Parameter maxAge: Maximum age in seconds before cache is considered stale
    public func isCacheStale(maxAge: TimeInterval = 60) -> Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > maxAge
    }
}

// MARK: - Dashboard State Types

/// Complete dashboard state for UI display
public struct DashboardState: Sendable, Equatable {
    /// Current glucose reading state
    public var glucose: GlucoseState?
    
    /// Connection status
    public var connection: ConnectionState
    
    /// Algorithm state (IOB, COB, predictions)
    public var algorithm: AlgorithmDisplayState?
    
    /// Historical readings for charts
    public var history: [GlucoseState]
    
    /// Last update timestamp
    public var lastUpdate: Date
    
    public init(
        glucose: GlucoseState? = nil,
        connection: ConnectionState,
        algorithm: AlgorithmDisplayState? = nil,
        history: [GlucoseState] = [],
        lastUpdate: Date = Date()
    ) {
        self.glucose = glucose
        self.connection = connection
        self.algorithm = algorithm
        self.history = history
        self.lastUpdate = lastUpdate
    }
    
    /// Whether we have valid glucose data to display
    public var hasGlucoseData: Bool {
        glucose != nil
    }
    
    /// Whether the connection is active
    public var isConnected: Bool {
        connection.status.isAvailable
    }
    
    /// Age of the current reading in minutes
    public var readingAgeMinutes: Int? {
        guard let glucose else { return nil }
        return Int(Date().timeIntervalSince(glucose.timestamp) / 60)
    }
    
    /// Whether the reading is stale (>5 minutes old)
    public var isReadingStale: Bool {
        guard let age = readingAgeMinutes else { return true }
        return age > 5
    }
}

/// Glucose reading state for display
public struct GlucoseState: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var value: Int
    public var trend: GlucoseTrend
    public var timestamp: Date
    public var source: String
    
    public init(
        id: UUID = UUID(),
        value: Int,
        trend: GlucoseTrend = .flat,
        timestamp: Date = Date(),
        source: String = "Unknown"
    ) {
        self.id = id
        self.value = value
        self.trend = trend
        self.timestamp = timestamp
        self.source = source
    }
    
    /// Create from a GlucoseReading
    public init(from reading: GlucoseReading) {
        self.id = reading.id
        self.value = Int(reading.glucose)
        self.trend = reading.trend
        self.timestamp = reading.timestamp
        self.source = reading.source
    }
    
    /// Trend arrow string for display
    public var trendArrow: String {
        trend.arrow
    }
    
    /// Value with unit for display
    public var displayValue: String {
        "\(value) mg/dL"
    }
    
    /// Age in minutes
    public var ageMinutes: Int {
        Int(Date().timeIntervalSince(timestamp) / 60)
    }
}

/// Connection state for display
public struct ConnectionState: Sendable, Equatable {
    public var status: DataSourceStatus
    public var sourceName: String
    public var sourceId: String
    public var lastConnected: Date?
    public var errorMessage: String?
    
    public init(
        status: DataSourceStatus,
        sourceName: String,
        sourceId: String,
        lastConnected: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.sourceName = sourceName
        self.sourceId = sourceId
        self.lastConnected = lastConnected
        self.errorMessage = errorMessage
    }
    
    /// Status icon name
    public var statusIcon: String {
        status.icon
    }
    
    /// Human-readable status
    public var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error: return errorMessage ?? "Error"
        case .unauthorized: return "Authentication Required"
        case .configurationRequired: return "Setup Required"
        }
    }
}

/// Algorithm state for display (IOB, COB, predictions)
public struct AlgorithmDisplayState: Sendable, Equatable {
    public var iobUnits: Double
    public var cobGrams: Double
    public var eventualBG: Int?
    public var predictedMinBG: Int?
    public var predictedMaxBG: Int?
    public var lastLoopTime: Date?
    public var loopStatus: LoopStatus
    
    public init(
        iobUnits: Double = 0,
        cobGrams: Double = 0,
        eventualBG: Int? = nil,
        predictedMinBG: Int? = nil,
        predictedMaxBG: Int? = nil,
        lastLoopTime: Date? = nil,
        loopStatus: LoopStatus = .idle
    ) {
        self.iobUnits = iobUnits
        self.cobGrams = cobGrams
        self.eventualBG = eventualBG
        self.predictedMinBG = predictedMinBG
        self.predictedMaxBG = predictedMaxBG
        self.lastLoopTime = lastLoopTime
        self.loopStatus = loopStatus
    }
    
    /// Formatted IOB string
    public var iobText: String {
        String(format: "%.2f U", iobUnits)
    }
    
    /// Formatted COB string
    public var cobText: String {
        String(format: "%.0f g", cobGrams)
    }
    
    /// Loop status
    public enum LoopStatus: String, Sendable {
        case idle
        case running
        case waiting
        case error
        case disabled
    }
}

// MARK: - Algorithm State Provider Protocol

/// Protocol for providing algorithm state (IOB, COB, etc.)
public protocol AlgorithmStateProvider: Sendable {
    func currentState() async -> AlgorithmDisplayState?
}

// MARK: - Convenience Extensions

public extension DashboardStateAdapter {
    /// Create a simple glucose-only dashboard state
    static func glucoseOnlyState(from reading: GlucoseReading, status: DataSourceStatus = .connected, sourceName: String = "Unknown") -> DashboardState {
        DashboardState(
            glucose: GlucoseState(from: reading),
            connection: ConnectionState(
                status: status,
                sourceName: sourceName,
                sourceId: "manual"
            ),
            lastUpdate: Date()
        )
    }
    
    /// Create a state indicating no data
    static func noDataState(sourceName: String = "None", status: DataSourceStatus = .configurationRequired) -> DashboardState {
        DashboardState(
            glucose: nil,
            connection: ConnectionState(
                status: status,
                sourceName: sourceName,
                sourceId: "none"
            ),
            lastUpdate: Date()
        )
    }
}

// MARK: - Legacy Compatibility

public extension DashboardState {
    /// Convert to legacy GlucoseDashboardState format
    /// Note: Requires import of T1PalDebugKit for GlucoseDashboardState
    func toLegacyFormat() -> (glucoseValue: Int, trendDirection: String, lastReadingTime: Date, isConnected: Bool, iobUnits: Double, cobGrams: Double) {
        (
            glucoseValue: glucose?.value ?? 0,
            trendDirection: glucose?.trend.rawValue ?? "flat",
            lastReadingTime: glucose?.timestamp ?? Date(),
            isConnected: isConnected,
            iobUnits: algorithm?.iobUnits ?? 0,
            cobGrams: algorithm?.cobGrams ?? 0
        )
    }
}
