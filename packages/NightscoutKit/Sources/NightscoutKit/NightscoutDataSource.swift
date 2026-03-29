// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NightscoutDataSource.swift - GlucoseDataSource implementation for Nightscout
// Part of NightscoutKit
//
// Fetches glucose data from a Nightscout server using the NightscoutClient.

import Foundation
import T1PalCore

// MARK: - NightscoutDataSource

/// Data source that fetches glucose readings from a Nightscout server
public actor NightscoutDataSource: GlucoseDataSource {
    // MARK: - Properties
    
    public nonisolated let id: String
    public nonisolated let name: String
    
    private let client: NightscoutClient
    private var lastFetchDate: Date?
    private var cachedReadings: [GlucoseReading] = []
    private var currentStatus: DataSourceStatus = .disconnected
    
    // MARK: - Initialization
    
    /// Create a data source with a Nightscout client
    /// - Parameters:
    ///   - client: Configured NightscoutClient
    ///   - name: Display name for this source
    public init(client: NightscoutClient, name: String = "Nightscout") {
        self.client = client
        self.id = "nightscout-\(UUID().uuidString.prefix(8))"
        self.name = name
    }
    
    /// Create a data source with a URL and optional credentials
    /// - Parameters:
    ///   - url: Nightscout site URL
    ///   - apiSecret: Optional API secret for authentication
    ///   - token: Optional token for authentication
    ///   - name: Display name for this source
    public init(url: URL, apiSecret: String? = nil, token: String? = nil, name: String = "Nightscout") {
        let config = NightscoutConfig(url: url, apiSecret: apiSecret, token: token)
        self.client = NightscoutClient(config: config)
        self.id = "nightscout-\(UUID().uuidString.prefix(8))"
        self.name = name
    }
    
    // MARK: - GlucoseDataSource Protocol
    
    public var status: DataSourceStatus {
        get async { currentStatus }
    }
    
    public func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        currentStatus = .connecting
        
        do {
            let entries = try await client.fetchEntries(count: count)
            currentStatus = .connected
            lastFetchDate = Date()
            
            let readings = entries.compactMap { entry -> GlucoseReading? in
                guard let sgv = entry.sgv else { return nil }
                let timestamp = Date(timeIntervalSince1970: entry.date / 1000)
                return GlucoseReading(
                    sgv: sgv,
                    timestamp: timestamp,
                    direction: entry.direction,
                    source: entry.device ?? "Nightscout"
                )
            }
            
            cachedReadings = readings
            return readings
            
        } catch {
            currentStatus = .error
            throw DataSourceError.networkError(underlying: error)
        }
    }
    
    public func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        currentStatus = .connecting
        
        do {
            let query = EntriesQuery(
                count: 10000,  // Fetch up to 10k entries
                dateFrom: from,
                dateTo: to
            )
            
            let entries = try await client.fetchEntries(query: query)
            currentStatus = .connected
            lastFetchDate = Date()
            
            return entries.compactMap { entry -> GlucoseReading? in
                guard let sgv = entry.sgv else { return nil }
                let timestamp = Date(timeIntervalSince1970: entry.date / 1000)
                return GlucoseReading(
                    sgv: sgv,
                    timestamp: timestamp,
                    direction: entry.direction,
                    source: entry.device ?? "Nightscout"
                )
            }
            
        } catch {
            currentStatus = .error
            throw DataSourceError.networkError(underlying: error)
        }
    }
    
    public func latestReading() async throws -> GlucoseReading? {
        // Use cached if recent (within 30 seconds)
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < 30,
           let latest = cachedReadings.first {
            return latest
        }
        
        return try await fetchRecentReadings(count: 1).first
    }
    
    // MARK: - Additional Methods
    
    /// Verify connection to the Nightscout server
    public func verifyConnection() async throws -> Bool {
        do {
            _ = try await client.fetchEntries(count: 1)
            currentStatus = .connected
            return true
        } catch {
            currentStatus = .error
            return false
        }
    }
    
    /// Get treatments for the given time range
    public func fetchTreatments(from: Date, to: Date) async throws -> [NightscoutTreatment] {
        let query = TreatmentsQuery(
            count: 1000,
            dateFrom: from,
            dateTo: to
        )
        
        return try await client.fetchTreatments(query: query)
    }
}

// MARK: - DataSourceManager Integration

public extension DataSourceManager {
    /// Register a Nightscout data source from URL and credentials
    /// - Parameters:
    ///   - url: Nightscout site URL
    ///   - apiSecret: API secret for authentication
    ///   - name: Display name for this source
    ///   - setActive: Whether to set as the active source
    /// - Returns: The registered NightscoutDataSource
    @discardableResult
    func registerNightscout(
        url: URL,
        apiSecret: String?,
        name: String = "Nightscout",
        setActive: Bool = true
    ) -> NightscoutDataSource {
        let source = NightscoutDataSource(url: url, apiSecret: apiSecret, name: name)
        register(source)
        if setActive {
            _ = setActiveSource(id: source.id)
        }
        return source
    }
    
    /// Register a Nightscout data source from a client
    /// - Parameters:
    ///   - client: Pre-configured NightscoutClient
    ///   - name: Display name for this source
    ///   - setActive: Whether to set as the active source
    /// - Returns: The registered NightscoutDataSource
    @discardableResult
    func registerNightscout(
        client: NightscoutClient,
        name: String = "Nightscout",
        setActive: Bool = true
    ) -> NightscoutDataSource {
        let source = NightscoutDataSource(client: client, name: name)
        register(source)
        if setActive {
            _ = setActiveSource(id: source.id)
        }
        return source
    }
}

// MARK: - Factory Methods

public extension NightscoutDataSource {
    /// Create from URL string with optional credentials
    /// - Parameters:
    ///   - urlString: Nightscout site URL as string
    ///   - apiSecret: Optional API secret
    ///   - name: Display name
    /// - Returns: NightscoutDataSource or nil if URL is invalid
    static func create(
        urlString: String,
        apiSecret: String? = nil,
        name: String = "Nightscout"
    ) -> NightscoutDataSource? {
        guard let url = URL(string: urlString) else { return nil }
        return NightscoutDataSource(url: url, apiSecret: apiSecret, name: name)
    }
    
    /// Status description for display
    var statusDescription: String {
        get async {
            switch await status {
            case .connected: return "Connected"
            case .connecting: return "Connecting..."
            case .disconnected: return "Disconnected"
            case .error: return "Error"
            case .unauthorized: return "Unauthorized"
            case .configurationRequired: return "Setup Required"
            }
        }
    }
}
