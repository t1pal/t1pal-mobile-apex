// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// GlucoseCache.swift - In-memory and persistent cache for glucose readings
// Part of T1PalCore
// Trace: CACHE-001

import Foundation

// MARK: - Glucose Cache

/// Thread-safe cache for glucose readings with optional persistence
public actor GlucoseCache {
    // MARK: - Configuration
    
    /// Cache configuration
    public struct Configuration: Sendable {
        /// Maximum number of readings to keep in memory
        public let maxMemoryReadings: Int
        
        /// How long readings are considered valid (seconds)
        public let validityDuration: TimeInterval
        
        /// Whether to persist cache to disk
        public let persistToDisk: Bool
        
        /// Directory for disk persistence (nil = use default caches directory)
        public let cacheDirectory: URL?
        
        public init(
            maxMemoryReadings: Int = 2016,  // 7 days at 5-min intervals
            validityDuration: TimeInterval = 7 * 24 * 3600,  // 7 days
            persistToDisk: Bool = true,
            cacheDirectory: URL? = nil
        ) {
            self.maxMemoryReadings = maxMemoryReadings
            self.validityDuration = validityDuration
            self.persistToDisk = persistToDisk
            self.cacheDirectory = cacheDirectory
        }
        
        public static let `default` = Configuration()
        
        /// Minimal cache for widgets
        public static let widget = Configuration(
            maxMemoryReadings: 288,  // 24 hours
            validityDuration: 24 * 3600,
            persistToDisk: false
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var readings: [GlucoseReading] = []
    private var lastModified: Date = .distantPast
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Singleton
    
    /// Shared cache instance
    public static let shared = GlucoseCache()
    
    // MARK: - Read Operations
    
    /// Get all cached readings
    public func allReadings() -> [GlucoseReading] {
        readings
    }
    
    /// Get readings within a time range
    public func readings(from: Date, to: Date) -> [GlucoseReading] {
        readings.filter { $0.timestamp >= from && $0.timestamp <= to }
    }
    
    /// Get recent readings
    public func recentReadings(count: Int) -> [GlucoseReading] {
        Array(readings.prefix(count))
    }
    
    /// Get the latest reading
    public func latestReading() -> GlucoseReading? {
        readings.first
    }
    
    /// Check if cache contains readings for a time range
    public func hasReadings(from: Date, to: Date) -> Bool {
        !readings(from: from, to: to).isEmpty
    }
    
    /// Get cache statistics
    public func statistics() -> CacheStatistics {
        let oldest = readings.last?.timestamp
        let newest = readings.first?.timestamp
        return CacheStatistics(
            readingCount: readings.count,
            oldestReading: oldest,
            newestReading: newest,
            lastModified: lastModified,
            memorySizeEstimate: readings.count * MemoryLayout<GlucoseReading>.stride
        )
    }
    
    // MARK: - Write Operations
    
    /// Add a single reading
    public func add(_ reading: GlucoseReading) {
        insertReading(reading)
        trimIfNeeded()
        lastModified = Date()
        
        if config.persistToDisk {
            Task { await persistToDisk() }
        }
    }
    
    /// Add multiple readings (deduplicates automatically)
    public func add(_ newReadings: [GlucoseReading]) {
        for reading in newReadings {
            insertReading(reading)
        }
        trimIfNeeded()
        lastModified = Date()
        
        if config.persistToDisk {
            Task { await persistToDisk() }
        }
    }
    
    /// Replace all readings
    public func replace(with newReadings: [GlucoseReading]) {
        readings = newReadings.sorted { $0.timestamp > $1.timestamp }
        trimIfNeeded()
        lastModified = Date()
        
        if config.persistToDisk {
            Task { await persistToDisk() }
        }
    }
    
    /// Clear all cached readings
    public func clear() {
        readings = []
        lastModified = Date()
        
        if config.persistToDisk {
            deleteDiskCache()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Insert reading in sorted order, avoiding duplicates
    private func insertReading(_ reading: GlucoseReading) {
        // Check for duplicate (same timestamp within 30 seconds)
        let isDuplicate = readings.contains { existing in
            abs(existing.timestamp.timeIntervalSince(reading.timestamp)) < 30
        }
        
        guard !isDuplicate else { return }
        
        // Binary search for insert position (sorted by timestamp descending)
        let insertIndex = readings.firstIndex { $0.timestamp < reading.timestamp } ?? readings.endIndex
        readings.insert(reading, at: insertIndex)
    }
    
    /// Remove old readings beyond max count
    private func trimIfNeeded() {
        // Trim by count
        if readings.count > config.maxMemoryReadings {
            readings = Array(readings.prefix(config.maxMemoryReadings))
        }
        
        // Trim by age
        let cutoff = Date().addingTimeInterval(-config.validityDuration)
        readings = readings.filter { $0.timestamp >= cutoff }
    }
    
    // MARK: - Disk Persistence
    
    private var cacheFileURL: URL? {
        guard let directory = config.cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent("glucose_cache.json")
    }
    
    /// Load cache from disk
    public func loadFromDisk() async {
        guard config.persistToDisk, let fileURL = cacheFileURL else { return }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try JSONDecoder().decode(CachedReadings.self, from: data)
            readings = cached.readings
            lastModified = cached.lastModified
            trimIfNeeded()
        } catch {
            // No cache file or corrupted - start fresh
        }
    }
    
    /// Save cache to disk
    private func persistToDisk() async {
        guard config.persistToDisk, let fileURL = cacheFileURL else { return }
        
        do {
            let cached = CachedReadings(readings: readings, lastModified: lastModified)
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently fail - cache is optional
        }
    }
    
    private func deleteDiskCache() {
        guard let fileURL = cacheFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Cache Statistics

/// Statistics about the glucose cache
public struct CacheStatistics: Sendable {
    public let readingCount: Int
    public let oldestReading: Date?
    public let newestReading: Date?
    public let lastModified: Date
    public let memorySizeEstimate: Int
    
    /// Time span covered by cache
    public var timeSpan: TimeInterval? {
        guard let oldest = oldestReading, let newest = newestReading else { return nil }
        return newest.timeIntervalSince(oldest)
    }
    
    /// Human-readable time span
    public var timeSpanDescription: String {
        guard let span = timeSpan else { return "Empty" }
        let hours = Int(span / 3600)
        if hours < 24 {
            return "\(hours) hours"
        } else {
            let days = hours / 24
            return "\(days) days"
        }
    }
}

// MARK: - Cached Readings (Serializable)

private struct CachedReadings: Codable {
    let readings: [GlucoseReading]
    let lastModified: Date
}

// MARK: - Caching Data Source

/// Data source wrapper that adds caching
public actor CachingDataSource: GlucoseDataSource {
    public nonisolated let id: String
    public nonisolated let name: String
    
    private let wrapped: any GlucoseDataSource
    private let cache: GlucoseCache
    
    /// Create a caching wrapper around another data source
    public init(wrapping source: any GlucoseDataSource, cache: GlucoseCache = .shared) {
        self.wrapped = source
        self.cache = cache
        self.id = "cached-\(source.id)"
        self.name = source.name
    }
    
    public var status: DataSourceStatus {
        get async { await wrapped.status }
    }
    
    public func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        // Try cache first
        let cached = await cache.recentReadings(count: count)
        if cached.count >= count {
            // Check if fresh enough (< 5 min old)
            if let newest = cached.first, Date().timeIntervalSince(newest.timestamp) < 300 {
                return cached
            }
        }
        
        // Fetch from source
        let fresh = try await wrapped.fetchRecentReadings(count: count)
        await cache.add(fresh)
        return fresh
    }
    
    public func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        // Check cache coverage
        let cached = await cache.readings(from: from, to: to)
        
        // If cache covers the range, use it
        if !cached.isEmpty {
            let cacheFrom = cached.last?.timestamp ?? Date.distantFuture
            let cacheTo = cached.first?.timestamp ?? Date.distantPast
            
            // Cache covers at least 90% of requested range
            let requestedDuration = to.timeIntervalSince(from)
            let cachedDuration = cacheTo.timeIntervalSince(cacheFrom)
            if cachedDuration >= requestedDuration * 0.9 {
                return cached
            }
        }
        
        // Fetch from source
        let fresh = try await wrapped.fetchReadings(from: from, to: to)
        await cache.add(fresh)
        return fresh
    }
    
    public func latestReading() async throws -> GlucoseReading? {
        // Check cache
        if let cached = await cache.latestReading() {
            // Fresh enough (< 1 min)
            if Date().timeIntervalSince(cached.timestamp) < 60 {
                return cached
            }
        }
        
        // Fetch from source
        if let fresh = try await wrapped.latestReading() {
            await cache.add(fresh)
            return fresh
        }
        
        // Fall back to cached
        return await cache.latestReading()
    }
}
