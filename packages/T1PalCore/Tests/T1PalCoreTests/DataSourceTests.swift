// DataSourceTests.swift - Unit tests for GlucoseDataSource infrastructure
// Part of T1PalCoreTests
// Trace: TEST-DS-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Mock Data Source

/// Test data source for unit testing
actor MockDataSource: GlucoseDataSource {
    nonisolated let id: String = "mock"
    nonisolated let name: String = "Mock Data Source"
    
    var mockReadings: [GlucoseReading] = []
    var mockStatus: DataSourceStatus = .connected
    var shouldThrow: DataSourceError?
    var fetchCount: Int = 0
    
    var status: DataSourceStatus {
        mockStatus
    }
    
    func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        fetchCount += 1
        if let error = shouldThrow { throw error }
        return Array(mockReadings.prefix(count))
    }
    
    func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        fetchCount += 1
        if let error = shouldThrow { throw error }
        return mockReadings.filter { $0.timestamp >= from && $0.timestamp <= to }
    }
    
    func latestReading() async throws -> GlucoseReading? {
        fetchCount += 1
        if let error = shouldThrow { throw error }
        return mockReadings.first
    }
    
    // Test setup helpers
    func setReadings(_ readings: [GlucoseReading]) {
        mockReadings = readings
    }
    
    func setStatus(_ status: DataSourceStatus) {
        mockStatus = status
    }
    
    func setError(_ error: DataSourceError?) {
        shouldThrow = error
    }
}

// MARK: - Data Source Protocol Tests

@Suite("GlucoseDataSource Protocol")
struct DataSourceProtocolTests {
    
    @Test("Data source has required properties")
    func dataSourceProperties() async {
        let source = MockDataSource()
        #expect(source.id == "mock")
        #expect(source.name == "Mock Data Source")
        
        let status = await source.status
        #expect(status == .connected)
    }
    
    @Test("Fetch recent readings returns correct count")
    func fetchRecentReadings() async throws {
        let source = MockDataSource()
        let readings = createTestReadings(count: 10)
        await source.setReadings(readings)
        
        let fetched = try await source.fetchRecentReadings(count: 5)
        #expect(fetched.count == 5)
    }
    
    @Test("Fetch readings by date range filters correctly")
    func fetchReadingsByDateRange() async throws {
        let source = MockDataSource()
        let now = Date()
        
        // Create readings at 5-minute intervals for 1 hour
        var readings: [GlucoseReading] = []
        for i in 0..<12 {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 300))
            readings.append(GlucoseReading(
                glucose: 100 + Double(i),
                timestamp: timestamp,
                trend: .flat
            ))
        }
        await source.setReadings(readings)
        
        // Fetch last 30 minutes
        let from = now.addingTimeInterval(-1800)
        let to = now
        let fetched = try await source.fetchReadings(from: from, to: to)
        
        #expect(fetched.count == 7) // 0, 5, 10, 15, 20, 25, 30 min
    }
    
    @Test("Latest reading returns most recent")
    func latestReading() async throws {
        let source = MockDataSource()
        let readings = createTestReadings(count: 5)
        await source.setReadings(readings)
        
        let latest = try await source.latestReading()
        #expect(latest?.glucose == readings[0].glucose)
    }
    
    @Test("Error propagation works")
    func errorHandling() async {
        let source = MockDataSource()
        await source.setError(.notConfigured)
        
        do {
            _ = try await source.fetchRecentReadings(count: 5)
            Issue.record("Expected error to be thrown")
        } catch let error as DataSourceError {
            if case .notConfigured = error {
                // Expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - DataSourceStatus Tests

@Suite("DataSourceStatus")
struct DataSourceStatusTests {
    
    @Test("Connected status is ready")
    func connectedIsReady() {
        let status = DataSourceStatus.connected
        #expect(status.isAvailable)
    }
    
    @Test("Connecting status is not ready")
    func connectingNotReady() {
        let status = DataSourceStatus.connecting
        #expect(!status.isAvailable)
    }
    
    @Test("Error status is not ready")
    func errorNotReady() {
        let status = DataSourceStatus.error
        #expect(!status.isAvailable)
    }
    
    @Test("Status equality works")
    func statusEquality() {
        #expect(DataSourceStatus.connected == DataSourceStatus.connected)
        #expect(DataSourceStatus.disconnected == DataSourceStatus.disconnected)
        #expect(DataSourceStatus.error == DataSourceStatus.error)
        #expect(DataSourceStatus.connected != DataSourceStatus.disconnected)
    }
}

// MARK: - Glucose Cache Tests

@Suite("GlucoseCache")
struct GlucoseCacheTests {
    
    @Test("Cache stores and retrieves readings")
    func basicCacheOperations() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let readings = createTestReadings(count: 5)
        
        await cache.add(readings)
        
        let all = await cache.allReadings()
        #expect(all.count == 5)
        
        let recent = await cache.recentReadings(count: 3)
        #expect(recent.count == 3)
        
        let latest = await cache.latestReading()
        #expect(latest != nil)
    }
    
    @Test("Cache deduplicates readings")
    func deduplication() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let now = Date()
        
        let reading1 = GlucoseReading(glucose: 100, timestamp: now, trend: .flat)
        let reading2 = GlucoseReading(glucose: 105, timestamp: now.addingTimeInterval(10), trend: .flat)
        
        await cache.add(reading1)
        await cache.add(reading2)  // Within 30 seconds - should be deduplicated
        
        let all = await cache.allReadings()
        #expect(all.count == 1)
    }
    
    @Test("Cache maintains sorted order")
    func sortedOrder() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let now = Date()
        
        // Add readings out of order
        let older = GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-600), trend: .flat)
        let newer = GlucoseReading(glucose: 110, timestamp: now, trend: .flat)
        
        await cache.add(older)
        await cache.add(newer)
        
        let all = await cache.allReadings()
        #expect(all[0].glucose == 110)  // Newest first
        #expect(all[1].glucose == 100)
    }
    
    @Test("Cache trims to max size")
    func trimBySize() async {
        let cache = GlucoseCache(configuration: .init(maxMemoryReadings: 5, persistToDisk: false))
        let readings = createTestReadings(count: 10)
        
        await cache.add(readings)
        
        let all = await cache.allReadings()
        #expect(all.count == 5)  // Trimmed to max
    }
    
    @Test("Cache filters by date range")
    func dateRangeFilter() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let now = Date()
        
        // Create readings over 2 hours
        var readings: [GlucoseReading] = []
        for i in 0..<24 {
            readings.append(GlucoseReading(
                glucose: 100 + Double(i),
                timestamp: now.addingTimeInterval(TimeInterval(-i * 300)),
                trend: .flat
            ))
        }
        await cache.add(readings)
        
        // Query last hour only
        let from = now.addingTimeInterval(-3600)
        let filtered = await cache.readings(from: from, to: now)
        #expect(filtered.count == 13)  // 0-60 min at 5-min intervals
    }
    
    @Test("Cache statistics are accurate")
    func cacheStatistics() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let readings = createTestReadings(count: 10)
        await cache.add(readings)
        
        let stats = await cache.statistics()
        #expect(stats.readingCount == 10)
        #expect(stats.oldestReading != nil)
        #expect(stats.newestReading != nil)
        #expect(stats.timeSpan != nil)
    }
    
    @Test("Clear removes all readings")
    func clearCache() async {
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        await cache.add(createTestReadings(count: 5))
        
        await cache.clear()
        
        let all = await cache.allReadings()
        #expect(all.isEmpty)
    }
}

// MARK: - Caching Data Source Tests

@Suite("CachingDataSource")
struct CachingDataSourceTests {
    
    @Test("Caching wrapper uses cache for recent reads")
    func cachingWrapper() async throws {
        let mock = MockDataSource()
        let cache = GlucoseCache(configuration: .init(persistToDisk: false))
        let readings = createTestReadings(count: 10)
        await mock.setReadings(readings)
        
        let cached = CachingDataSource(wrapping: mock, cache: cache)
        
        // First fetch - goes to source
        let first = try await cached.fetchRecentReadings(count: 5)
        #expect(first.count == 5)
        
        let fetchCount = await mock.fetchCount
        #expect(fetchCount == 1)
    }
    
    @Test("Caching wrapper has correct identity")
    func cachingWrapperIdentity() async {
        let mock = MockDataSource()
        let cached = CachingDataSource(wrapping: mock)
        
        #expect(cached.id == "cached-mock")
        #expect(cached.name == "Mock Data Source")
    }
}

// MARK: - Settings Store Tests

@Suite("SettingsStore")
struct SettingsStoreTests {
    
    @Test("Default values are correct")
    func defaultValues() {
        let store = SettingsStore(userDefaults: createTestDefaults())
        
        #expect(store.glucoseUnit == .mgdL)
        #expect(store.highGlucoseThreshold == 180.0)
        #expect(store.lowGlucoseThreshold == 70.0)
        #expect(store.chartTimeRangeHours == 3)
        #expect(store.notificationsEnabled == true)
        #expect(store.colorScheme == .system)
    }
    
    @Test("Setting values persists")
    func setPersists() {
        let store = SettingsStore(userDefaults: createTestDefaults())
        
        store.glucoseUnit = .mmolL
        store.highGlucoseThreshold = 200.0
        store.chartTimeRangeHours = 6
        
        #expect(store.glucoseUnit == .mmolL)
        #expect(store.highGlucoseThreshold == 200.0)
        #expect(store.chartTimeRangeHours == 6)
    }
    
    @Test("Reset clears custom values")
    func resetToDefaults() {
        let store = SettingsStore(userDefaults: createTestDefaults())
        
        store.glucoseUnit = .mmolL
        store.highGlucoseThreshold = 200.0
        
        store.resetToDefaults()
        
        #expect(store.glucoseUnit == .mgdL)
        #expect(store.highGlucoseThreshold == 180.0)
    }
    
    @Test("Codable storage works")
    func codableStorage() {
        let store = SettingsStore(userDefaults: createTestDefaults())
        
        struct TestData: Codable, Equatable {
            let name: String
            let value: Int
        }
        
        let data = TestData(name: "test", value: 42)
        store.set(data, forKey: "test.codable")
        
        let retrieved = store.get(TestData.self, forKey: "test.codable")
        #expect(retrieved == data)
    }
}

// MARK: - GlucoseUnit Tests

@Suite("GlucoseUnit")
struct GlucoseUnitTests {
    
    @Test("mg/dL conversion is identity")
    func mgdLConversion() {
        let unit = GlucoseUnit.mgdL
        #expect(unit.convert(100) == 100)
        #expect(unit.format(100) == "100")
    }
    
    @Test("mmol/L conversion is correct")
    func mmolConversion() {
        let unit = GlucoseUnit.mmolL
        let converted = unit.convert(100)
        #expect(abs(converted - 5.55) < 0.1)
        // 100 / 18.0182 = 5.549... rounds to 5.5
        #expect(unit.format(100) == "5.5")
    }
    
    @Test("Unit suffix is correct")
    func unitSuffix() {
        #expect(GlucoseUnit.mgdL.suffix == "mg/dL")
        #expect(GlucoseUnit.mmolL.suffix == "mmol/L")
    }
}

// MARK: - Test Helpers

func createTestReadings(count: Int) -> [GlucoseReading] {
    let now = Date()
    var readings: [GlucoseReading] = []
    for i in 0..<count {
        readings.append(GlucoseReading(
            glucose: 100 + Double(i * 5),
            timestamp: now.addingTimeInterval(TimeInterval(-i * 300)),
            trend: .flat
        ))
    }
    return readings
}

func createTestDefaults() -> UserDefaults {
    // Use a unique suite name to avoid test pollution
    let suiteName = "com.t1pal.tests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}
