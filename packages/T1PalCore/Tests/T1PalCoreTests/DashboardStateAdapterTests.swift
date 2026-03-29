// DashboardStateAdapterTests.swift - Tests for DashboardStateAdapter
// Part of T1PalCoreTests
// Trace: DS-STREAM-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - DashboardStateAdapter Tests

@Suite("DashboardStateAdapter")
struct DashboardStateAdapterTests {
    
    @Test("Creates state from data source reading")
    func basicStateCreation() async throws {
        let source = MockDataSource()
        let reading = GlucoseReading(
            id: UUID(),
            glucose: 120,
            timestamp: Date(),
            trend: .fortyFiveUp,
            source: "Test"
        )
        await source.setReadings([reading])
        
        let adapter = DashboardStateAdapter(dataSource: source)
        let state = try await adapter.currentState()
        
        #expect(state.glucose?.value == 120)
        #expect(state.glucose?.trend == .fortyFiveUp)
        #expect(state.isConnected == true)
        #expect(state.connection.sourceName == "Mock Data Source")
    }
    
    @Test("Creates state with history")
    func stateWithHistory() async throws {
        let source = MockDataSource()
        let readings = createTestReadings(count: 10)
        await source.setReadings(readings)
        
        let adapter = DashboardStateAdapter(dataSource: source)
        let state = try await adapter.stateWithHistory(count: 5)
        
        #expect(state.glucose != nil)
        #expect(state.history.count == 5)
        #expect(state.history[0].value == state.glucose?.value)
    }
    
    @Test("Reflects connection status from source")
    func connectionStatusReflection() async throws {
        let source = MockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let adapter = DashboardStateAdapter(dataSource: source)
        
        // Test connected
        await source.setStatus(.connected)
        var state = try await adapter.currentState()
        #expect(state.isConnected == true)
        #expect(state.connection.status == .connected)
        
        // Test disconnected
        await source.setStatus(.disconnected)
        state = try await adapter.currentState()
        #expect(state.isConnected == false)
        #expect(state.connection.status == .disconnected)
        
        // Test error
        await source.setStatus(.error)
        state = try await adapter.currentState()
        #expect(state.isConnected == false)
        #expect(state.connection.status == .error)
    }
    
    @Test("Handles no data gracefully")
    func noDataHandling() async throws {
        let source = MockDataSource()
        // No readings set
        
        let adapter = DashboardStateAdapter(dataSource: source)
        let state = try await adapter.currentState()
        
        #expect(state.glucose == nil)
        #expect(state.hasGlucoseData == false)
    }
    
    @Test("Caches state")
    func stateCaching() async throws {
        let source = MockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let adapter = DashboardStateAdapter(dataSource: source)
        
        // Initially no cache
        var cached = await adapter.cachedState
        #expect(cached == nil)
        
        // Fetch populates cache
        _ = try await adapter.currentState()
        cached = await adapter.cachedState
        #expect(cached != nil)
    }
    
    @Test("Detects stale cache")
    func staleCacheDetection() async throws {
        let source = MockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let adapter = DashboardStateAdapter(dataSource: source)
        
        // Fresh cache
        _ = try await adapter.currentState()
        var isStale = await adapter.isCacheStale(maxAge: 60)
        #expect(isStale == false)
        
        // With very short maxAge, should be stale
        isStale = await adapter.isCacheStale(maxAge: 0)
        #expect(isStale == true)
    }
    
    @Test("Includes algorithm state when provider set")
    func algorithmStateIntegration() async throws {
        let source = MockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let algorithmProvider = MockAlgorithmStateProvider(state: AlgorithmDisplayState(
            iobUnits: 2.5,
            cobGrams: 30,
            eventualBG: 140,
            loopStatus: .running
        ))
        
        let adapter = DashboardStateAdapter(dataSource: source, algorithmStateProvider: algorithmProvider)
        let state = try await adapter.currentState()
        
        #expect(state.algorithm?.iobUnits == 2.5)
        #expect(state.algorithm?.cobGrams == 30)
        #expect(state.algorithm?.eventualBG == 140)
        #expect(state.algorithm?.loopStatus == .running)
    }
}

// MARK: - DashboardState Tests

@Suite("DashboardState")
struct DashboardStateTests {
    
    @Test("Reading age calculation is correct")
    func readingAgeCalculation() {
        let now = Date()
        let state = DashboardState(
            glucose: GlucoseState(
                value: 100,
                trend: .flat,
                timestamp: now.addingTimeInterval(-300)  // 5 minutes ago
            ),
            connection: ConnectionState(
                status: .connected,
                sourceName: "Test",
                sourceId: "test"
            )
        )
        
        #expect(state.readingAgeMinutes == 5)
        #expect(state.isReadingStale == false)  // Exactly 5 minutes is not stale
    }
    
    @Test("Stale reading detection")
    func staleReadingDetection() {
        let now = Date()
        let staleState = DashboardState(
            glucose: GlucoseState(
                value: 100,
                trend: .flat,
                timestamp: now.addingTimeInterval(-400)  // 6+ minutes ago
            ),
            connection: ConnectionState(
                status: .connected,
                sourceName: "Test",
                sourceId: "test"
            )
        )
        
        #expect(staleState.isReadingStale == true)
    }
    
    @Test("No glucose means stale")
    func noGlucoseIsStale() {
        let state = DashboardState(
            glucose: nil,
            connection: ConnectionState(
                status: .connected,
                sourceName: "Test",
                sourceId: "test"
            )
        )
        
        #expect(state.hasGlucoseData == false)
        #expect(state.isReadingStale == true)
        #expect(state.readingAgeMinutes == nil)
    }
    
    @Test("Legacy format conversion works")
    func legacyFormatConversion() {
        let state = DashboardState(
            glucose: GlucoseState(
                value: 125,
                trend: .singleUp,
                timestamp: Date()
            ),
            connection: ConnectionState(
                status: .connected,
                sourceName: "Test",
                sourceId: "test"
            ),
            algorithm: AlgorithmDisplayState(
                iobUnits: 1.5,
                cobGrams: 20
            )
        )
        
        let legacy = state.toLegacyFormat()
        #expect(legacy.glucoseValue == 125)
        #expect(legacy.trendDirection == "SingleUp")  // Matches GlucoseTrend.singleUp.rawValue
        #expect(legacy.isConnected == true)
        #expect(legacy.iobUnits == 1.5)
        #expect(legacy.cobGrams == 20)
    }
}

// MARK: - GlucoseState Tests

@Suite("GlucoseState")
struct GlucoseStateTests {
    
    @Test("Creates from GlucoseReading")
    func createsFromReading() {
        let reading = GlucoseReading(
            id: UUID(),
            glucose: 150,
            timestamp: Date(),
            trend: .singleDown,
            source: "CGM"
        )
        
        let state = GlucoseState(from: reading)
        
        #expect(state.value == 150)
        #expect(state.trend == .singleDown)
        #expect(state.source == "CGM")
    }
    
    @Test("Trend arrow is correct")
    func trendArrow() {
        let upState = GlucoseState(value: 100, trend: .singleUp)
        #expect(upState.trendArrow == "↑")
        
        let downState = GlucoseState(value: 100, trend: .singleDown)
        #expect(downState.trendArrow == "↓")
        
        let flatState = GlucoseState(value: 100, trend: .flat)
        #expect(flatState.trendArrow == "→")
    }
    
    @Test("Display value is formatted")
    func displayValueFormat() {
        let state = GlucoseState(value: 120, trend: .flat)
        #expect(state.displayValue == "120 mg/dL")
    }
    
    @Test("Age calculation works")
    func ageCalculation() {
        let state = GlucoseState(
            value: 100,
            trend: .flat,
            timestamp: Date().addingTimeInterval(-180)  // 3 minutes ago
        )
        #expect(state.ageMinutes == 3)
    }
}

// MARK: - ConnectionState Tests

@Suite("ConnectionState")
struct ConnectionStateTests {
    
    @Test("Status text is correct")
    func statusText() {
        let connected = ConnectionState(status: .connected, sourceName: "Test", sourceId: "test")
        #expect(connected.statusText == "Connected")
        
        let disconnected = ConnectionState(status: .disconnected, sourceName: "Test", sourceId: "test")
        #expect(disconnected.statusText == "Disconnected")
        
        let configRequired = ConnectionState(status: .configurationRequired, sourceName: "Test", sourceId: "test")
        #expect(configRequired.statusText == "Setup Required")
    }
    
    @Test("Error message is used when present")
    func errorMessageDisplay() {
        let errorState = ConnectionState(
            status: .error,
            sourceName: "Test",
            sourceId: "test",
            errorMessage: "Network timeout"
        )
        #expect(errorState.statusText == "Network timeout")
    }
}

// MARK: - AlgorithmDisplayState Tests

@Suite("AlgorithmDisplayState")
struct AlgorithmDisplayStateTests {
    
    @Test("IOB text is formatted")
    func iobTextFormat() {
        let state = AlgorithmDisplayState(iobUnits: 2.5)
        #expect(state.iobText == "2.50 U")
    }
    
    @Test("COB text is formatted")
    func cobTextFormat() {
        let state = AlgorithmDisplayState(cobGrams: 35)
        #expect(state.cobText == "35 g")
    }
    
    @Test("Default values are sensible")
    func defaultValues() {
        let state = AlgorithmDisplayState()
        #expect(state.iobUnits == 0)
        #expect(state.cobGrams == 0)
        #expect(state.loopStatus == .idle)
    }
}

// MARK: - Convenience Methods Tests

@Suite("DashboardStateAdapter Convenience")
struct DashboardStateAdapterConvenienceTests {
    
    @Test("glucoseOnlyState creates valid state")
    func glucoseOnlyState() {
        let reading = GlucoseReading(glucose: 110, timestamp: Date(), trend: .flat)
        let state = DashboardStateAdapter.glucoseOnlyState(from: reading, sourceName: "Test")
        
        #expect(state.glucose?.value == 110)
        #expect(state.connection.sourceName == "Test")
        #expect(state.algorithm == nil)
    }
    
    @Test("noDataState creates proper empty state")
    func noDataState() {
        let state = DashboardStateAdapter.noDataState(sourceName: "None")
        
        #expect(state.glucose == nil)
        #expect(state.hasGlucoseData == false)
        #expect(state.connection.status == .configurationRequired)
    }
}

// MARK: - Mock Algorithm State Provider

actor MockAlgorithmStateProvider: AlgorithmStateProvider {
    var state: AlgorithmDisplayState?
    
    init(state: AlgorithmDisplayState? = nil) {
        self.state = state
    }
    
    func currentState() async -> AlgorithmDisplayState? {
        state
    }
}
