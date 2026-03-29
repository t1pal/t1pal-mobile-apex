// StreamingDashboardViewModelTests.swift - Tests for StreamingDashboardViewModel
// Part of T1PalCoreTests
// Trace: DS-STREAM-002

#if canImport(Observation)
import Testing
import Foundation
@testable import T1PalCore

// MARK: - StreamingDashboardViewModel Tests


@Suite("StreamingDashboardViewModel")
struct StreamingDashboardViewModelTests {
    
    @Test("Initial state is connecting")
    @MainActor
    func initialState() async {
        let source = MockDataSource()
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        #expect(vm.state.connection.status == .connecting)
        #expect(vm.state.glucose == nil)
        #expect(vm.isLoading == false)
        #expect(vm.error == nil)
    }
    
    @Test("Refresh fetches state from data source")
    @MainActor
    func refreshFetchesState() async {
        let source = MockDataSource()
        let reading = GlucoseReading(
            id: UUID(),
            glucose: 130,
            timestamp: Date(),
            trend: .singleUp,
            source: "Test"
        )
        await source.setReadings([reading])
        
        let vm = StreamingDashboardViewModel(dataSource: source)
        await vm.refresh()
        
        #expect(vm.state.glucose?.value == 130)
        #expect(vm.state.glucose?.trend == .singleUp)
        #expect(vm.state.isConnected == true)
    }
    
    @Test("Refresh with history includes history")
    @MainActor
    func refreshWithHistory() async {
        let source = MockDataSource()
        let readings = createTestReadings(count: 10)
        await source.setReadings(readings)
        
        let vm = StreamingDashboardViewModel(dataSource: source)
        await vm.refreshWithHistory(count: 5)
        
        #expect(vm.state.history.count == 5)
        #expect(vm.state.glucose != nil)
    }
    
    @Test("Error sets error state")
    @MainActor
    func errorHandling() async {
        let source = MockDataSource()
        await source.setError(.networkError(underlying: URLError(.notConnectedToInternet)))
        
        let vm = StreamingDashboardViewModel(dataSource: source)
        await vm.refresh()
        
        #expect(vm.hasError == true)
        #expect(vm.error != nil)
        #expect(vm.state.connection.status == .error)
    }
    
    @Test("hasData reflects glucose presence")
    @MainActor
    func hasDataProperty() async {
        let source = MockDataSource()
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        // Initially no data
        #expect(vm.hasData == false)
        
        // After refresh with readings
        await source.setReadings(createTestReadings(count: 1))
        await vm.refresh()
        #expect(vm.hasData == true)
    }
    
    @Test("Auto-refresh can be toggled")
    @MainActor
    func autoRefreshToggle() async {
        let source = MockDataSource()
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        #expect(vm.autoRefreshEnabled == true)
        
        vm.autoRefreshEnabled = false
        #expect(vm.autoRefreshEnabled == false)
    }
    
    @Test("Refresh interval is configurable")
    @MainActor
    func refreshIntervalConfigurable() async {
        let source = MockDataSource()
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        #expect(vm.refreshInterval == 30)  // Default
        
        vm.refreshInterval = 60
        #expect(vm.refreshInterval == 60)
    }
    
    @Test("isLoading is true during refresh")
    @MainActor
    func loadingStateDuringRefresh() async {
        let source = SlowMockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        // Start refresh but don't await
        let refreshTask = Task { await vm.refresh() }
        
        // Give it a moment to start
        try? await Task.sleep(for: .milliseconds(50))
        
        // Should be loading
        #expect(vm.isLoading == true)
        
        // Wait for completion
        await refreshTask.value
        #expect(vm.isLoading == false)
    }
    
    @Test("Stop streaming cancels refresh loop")
    @MainActor
    func stopStreamingCancels() async {
        let source = MockDataSource()
        await source.setReadings(createTestReadings(count: 1))
        
        let vm = StreamingDashboardViewModel(dataSource: source)
        vm.refreshInterval = 0.1  // Fast refresh for testing
        
        vm.startStreaming()
        
        // Let it run briefly
        try? await Task.sleep(for: .milliseconds(50))
        
        vm.stopStreaming()
        
        let countBefore = await source.fetchCount
        
        // Wait and verify no more fetches
        try? await Task.sleep(for: .milliseconds(200))
        
        let countAfter = await source.fetchCount
        #expect(countAfter == countBefore)  // No additional fetches
    }
    
    @Test("needsRefresh is true when no refresh has occurred")
    @MainActor
    func needsRefreshInitially() async {
        let source = MockDataSource()
        let vm = StreamingDashboardViewModel(dataSource: source)
        
        #expect(vm.needsRefresh == true)
        
        await source.setReadings(createTestReadings(count: 1))
        await vm.refresh()
        
        #expect(vm.needsRefresh == false)
    }
}

// MARK: - DashboardError Tests

@Suite("DashboardError")
struct DashboardErrorTests {
    
    @Test("Creates from DataSourceError")
    func createsFromDataSourceError() {
        let networkError = DashboardError(from: DataSourceError.networkError(underlying: URLError(.timedOut)))
        #expect(networkError.isRecoverable == true)
        #expect(networkError.message.contains("Network"))
        
        let notConfigured = DashboardError(from: DataSourceError.notConfigured)
        #expect(notConfigured.isRecoverable == false)
        
        let unauthorized = DashboardError(from: DataSourceError.unauthorized)
        #expect(unauthorized.isRecoverable == false)
        
        let timeout = DashboardError(from: DataSourceError.timeout)
        #expect(timeout.isRecoverable == true)
    }
    
    @Test("Creates from generic error")
    func createsFromGenericError() {
        struct CustomError: Error {}
        let error = DashboardError(from: CustomError())
        
        #expect(error.isRecoverable == true)
        #expect(error.underlyingError != nil)
    }
    
    @Test("Message is accessible")
    func messageAccessible() {
        let error = DashboardError(message: "Test error", isRecoverable: true)
        #expect(error.message == "Test error")
        #expect(error.errorDescription == "Test error")
    }
}

// MARK: - Preview Factory Tests

#if DEBUG

@Suite("StreamingDashboardViewModel Previews")
struct StreamingDashboardViewModelPreviewTests {
    
    @Test("Preview factory creates valid state")
    @MainActor
    func previewFactory() async {
        let vm = StreamingDashboardViewModel.preview(
            glucose: 150,
            trend: .singleDown,
            iob: 3.0,
            cob: 25
        )
        
        #expect(vm.state.glucose?.value == 150)
        #expect(vm.state.glucose?.trend == .singleDown)
        #expect(vm.state.algorithm?.iobUnits == 3.0)
        #expect(vm.state.algorithm?.cobGrams == 25)
    }
    
    @Test("Loading preview is loading")
    @MainActor
    func loadingPreview() async {
        let vm = StreamingDashboardViewModel.loadingPreview
        #expect(vm.isLoading == true)
    }
    
    @Test("Error preview has error")
    @MainActor
    func errorPreview() async {
        let vm = StreamingDashboardViewModel.errorPreview
        #expect(vm.hasError == true)
    }
    
    @Test("No data preview has no glucose")
    @MainActor
    func noDataPreview() async {
        let vm = StreamingDashboardViewModel.noDataPreview
        #expect(vm.hasData == false)
    }
}
#endif

// MARK: - Slow Mock Data Source

/// Mock data source with artificial delay for testing loading states
actor SlowMockDataSource: GlucoseDataSource {
    nonisolated let id: String = "slow-mock"
    nonisolated let name: String = "Slow Mock Data Source"
    
    var mockReadings: [GlucoseReading] = []
    var mockStatus: DataSourceStatus = .connected
    
    var status: DataSourceStatus {
        mockStatus
    }
    
    func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        try? await Task.sleep(for: .milliseconds(200))
        return Array(mockReadings.prefix(count))
    }
    
    func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        try? await Task.sleep(for: .milliseconds(200))
        return mockReadings.filter { $0.timestamp >= from && $0.timestamp <= to }
    }
    
    func latestReading() async throws -> GlucoseReading? {
        try? await Task.sleep(for: .milliseconds(200))
        return mockReadings.first
    }
    
    func setReadings(_ readings: [GlucoseReading]) {
        mockReadings = readings
    }
}

#endif // canImport(Observation)
