// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// StreamingDashboardViewModel.swift - Observable view model for dashboard
// Part of T1PalCore
//
// Provides reactive dashboard state updates from GlucoseDataSource.
// Task: DS-STREAM-002, A11Y-VO-008

// @Observable requires Darwin platforms (iOS 17+, macOS 14+)
#if canImport(Observation)
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Task Holder for Deinit Safety

/// Helper class to hold task reference outside actor isolation
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private final class TaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Streaming Dashboard ViewModel

/// Observable view model that streams dashboard state from a data source
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
@Observable
public final class StreamingDashboardViewModel {
    // MARK: - Published State
    
    /// Current dashboard state
    public private(set) var state: DashboardState
    
    /// Loading state
    public private(set) var isLoading = false
    
    /// Error state
    public private(set) var error: DashboardError?
    
    /// Whether auto-refresh is enabled
    public var autoRefreshEnabled = true
    
    /// Auto-refresh interval in seconds
    public var refreshInterval: TimeInterval = 30
    
    // MARK: - Private Properties
    
    private let adapter: DashboardStateAdapter
    // Task reference stored outside @MainActor isolation for deinit access
    private let taskHolder = TaskHolder()
    private var lastRefreshTime: Date?
    
    // A11Y-VO-008: Track previous trend for change announcements
    private var previousTrend: GlucoseTrend?
    private var previousRangeStatus: GlucoseRangeStatus?
    
    // MARK: - Initialization
    
    /// Create a streaming view model with a data source
    /// - Parameters:
    ///   - dataSource: The glucose data source to stream from
    ///   - algorithmStateProvider: Optional algorithm state provider
    public init(
        dataSource: any GlucoseDataSource,
        algorithmStateProvider: AlgorithmStateProvider? = nil
    ) {
        self.adapter = DashboardStateAdapter(
            dataSource: dataSource,
            algorithmStateProvider: algorithmStateProvider
        )
        self.state = DashboardState(
            glucose: nil,
            connection: ConnectionState(
                status: .connecting,
                sourceName: dataSource.name,
                sourceId: dataSource.id
            )
        )
    }
    
    /// Create with a pre-configured adapter
    public init(adapter: DashboardStateAdapter, initialState: DashboardState? = nil) {
        self.adapter = adapter
        self.state = initialState ?? DashboardState(
            glucose: nil,
            connection: ConnectionState(
                status: .connecting,
                sourceName: "Unknown",
                sourceId: "unknown"
            )
        )
    }
    
    // MARK: - Public API
    
    /// Start streaming dashboard updates
    public func startStreaming() {
        stopStreaming()
        taskHolder.task = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }
    
    /// Stop streaming dashboard updates
    public func stopStreaming() {
        taskHolder.cancel()
    }
    
    /// Manually refresh the dashboard state
    public func refresh() async {
        await fetchState()
    }
    
    /// Refresh with history
    public func refreshWithHistory(count: Int = 24) async {
        await fetchStateWithHistory(count: count)
    }
    
    // MARK: - Private Methods
    
    private func runRefreshLoop() async {
        // Initial fetch
        await fetchState()
        
        // Continue refreshing while not cancelled
        while !Task.isCancelled && autoRefreshEnabled {
            try? await Task.sleep(for: .seconds(refreshInterval))
            
            if Task.isCancelled { break }
            
            await fetchState()
        }
    }
    
    private func fetchState() async {
        isLoading = true
        error = nil
        
        // A11Y-VO-008: Capture previous state for change detection
        let previousGlucose = state.glucose
        
        do {
            state = try await adapter.currentState()
            lastRefreshTime = Date()
            
            // A11Y-VO-008: Announce significant changes
            if let newGlucose = state.glucose {
                announceSignificantChanges(from: previousGlucose, to: newGlucose)
            }
        } catch {
            self.error = DashboardError(from: error)
            // Keep existing state but update connection status
            state.connection = ConnectionState(
                status: .error,
                sourceName: state.connection.sourceName,
                sourceId: state.connection.sourceId,
                errorMessage: error.localizedDescription
            )
        }
        
        isLoading = false
    }
    
    private func fetchStateWithHistory(count: Int) async {
        isLoading = true
        error = nil
        
        // A11Y-VO-008: Capture previous state for change detection
        let previousGlucose = state.glucose
        
        do {
            state = try await adapter.stateWithHistory(count: count)
            lastRefreshTime = Date()
            
            // A11Y-VO-008: Announce significant changes
            if let newGlucose = state.glucose {
                announceSignificantChanges(from: previousGlucose, to: newGlucose)
            }
        } catch {
            self.error = DashboardError(from: error)
            state.connection = ConnectionState(
                status: .error,
                sourceName: state.connection.sourceName,
                sourceId: state.connection.sourceId,
                errorMessage: error.localizedDescription
            )
        }
        
        isLoading = false
    }
    
    // MARK: - Computed Properties
    
    /// Whether dashboard has valid data to display
    public var hasData: Bool {
        state.hasGlucoseData
    }
    
    /// Whether an error is present
    public var hasError: Bool {
        error != nil
    }
    
    /// Time since last successful refresh
    public var timeSinceRefresh: TimeInterval? {
        lastRefreshTime.map { Date().timeIntervalSince($0) }
    }
    
    /// Whether data is stale and needs refresh
    public var needsRefresh: Bool {
        guard let elapsed = timeSinceRefresh else { return true }
        return elapsed > refreshInterval
    }
    
    // MARK: - A11Y-VO-008: Accessibility Announcements
    
    /// Announce significant glucose changes for VoiceOver users
    private func announceSignificantChanges(from previous: GlucoseState?, to current: GlucoseState) {
        var announcements: [String] = []
        
        // Check for trend direction change
        if let prevTrend = previous?.trend {
            let trendChange = detectTrendChange(from: prevTrend, to: current.trend)
            if let change = trendChange {
                announcements.append(change)
            }
        }
        
        // Check for range status change
        let currentRange = rangeStatus(for: current.value)
        if let prevValue = previous?.value {
            let previousRange = rangeStatus(for: prevValue)
            if currentRange != previousRange {
                announcements.append(rangeChangeAnnouncement(from: previousRange, to: currentRange))
            }
        }
        
        // Post combined announcement if any changes
        if !announcements.isEmpty {
            let message = announcements.joined(separator: ". ")
            postAccessibilityAnnouncement(message)
        }
    }
    
    /// Detect significant trend direction changes
    private func detectTrendChange(from previous: GlucoseTrend, to current: GlucoseTrend) -> String? {
        // Rising to falling (or vice versa) is significant
        let wasRising = previous == .doubleUp || previous == .singleUp || previous == .fortyFiveUp
        let wasFalling = previous == .doubleDown || previous == .singleDown || previous == .fortyFiveDown
        let isRising = current == .doubleUp || current == .singleUp || current == .fortyFiveUp
        let isFalling = current == .doubleDown || current == .singleDown || current == .fortyFiveDown
        
        if wasRising && isFalling {
            return "Glucose now falling"
        } else if wasFalling && isRising {
            return "Glucose now rising"
        } else if (wasRising || wasFalling) && current == .flat {
            return "Glucose now stable"
        } else if previous == .flat && isRising {
            return "Glucose starting to rise"
        } else if previous == .flat && isFalling {
            return "Glucose starting to fall"
        }
        
        // Rapid change alerts
        if current == .doubleUp && previous != .doubleUp {
            return "Glucose rising rapidly"
        } else if current == .doubleDown && previous != .doubleDown {
            return "Glucose falling rapidly"
        }
        
        return nil
    }
    
    /// Determine range status for a glucose value
    private func rangeStatus(for value: Int) -> GlucoseRangeStatus {
        switch value {
        case ..<54:
            return .urgentLow
        case ..<70:
            return .low
        case ..<180:
            return .inRange
        case ..<250:
            return .high
        default:
            return .urgentHigh
        }
    }
    
    /// Generate announcement for range change
    private func rangeChangeAnnouncement(from previous: GlucoseRangeStatus, to current: GlucoseRangeStatus) -> String {
        switch current {
        case .urgentLow:
            return "Urgent: glucose critically low"
        case .low:
            return previous == .urgentLow ? "Glucose recovering from urgent low" : "Glucose now low"
        case .inRange:
            if previous == .low || previous == .urgentLow {
                return "Glucose back in range"
            } else {
                return "Glucose returning to range"
            }
        case .high:
            return previous == .urgentHigh ? "Glucose coming down from urgent high" : "Glucose now high"
        case .urgentHigh:
            return "Warning: glucose very high"
        }
    }
    
    /// Post an accessibility announcement (Darwin platforms only)
    private func postAccessibilityAnnouncement(_ message: String) {
        #if canImport(UIKit)
        // Use UIAccessibility for iOS/tvOS (deployment target is iOS 17+)
        AccessibilityNotification.Announcement(message).post()
        #elseif canImport(AppKit)
        // macOS accessibility announcement
        if #available(macOS 14.0, *) {
            AccessibilityNotification.Announcement(message).post()
        }
        #endif
    }
    
    deinit {
        taskHolder.cancel()
    }
}

// MARK: - Glucose Range Status

/// Glucose range status for accessibility announcements
/// A11Y-VO-008
enum GlucoseRangeStatus: Equatable {
    case urgentLow   // < 54 mg/dL
    case low         // 54-69 mg/dL
    case inRange     // 70-179 mg/dL
    case high        // 180-249 mg/dL
    case urgentHigh  // >= 250 mg/dL
}

// MARK: - Dashboard Error

/// Error type for dashboard operations
public struct DashboardError: Error, LocalizedError, Sendable {
    public let message: String
    public let underlyingError: Error?
    public let isRecoverable: Bool
    
    public init(message: String, underlyingError: Error? = nil, isRecoverable: Bool = true) {
        self.message = message
        self.underlyingError = underlyingError
        self.isRecoverable = isRecoverable
    }
    
    /// Create from any error
    public init(from error: Error) {
        if let dataSourceError = error as? DataSourceError {
            switch dataSourceError {
            case .notConfigured:
                self.message = "Data source not configured"
                self.isRecoverable = false
            case .unauthorized:
                self.message = "Authentication required"
                self.isRecoverable = false
            case .networkError(let underlying):
                self.message = "Network error: \(underlying.localizedDescription)"
                self.isRecoverable = true
            case .noData:
                self.message = "No data available"
                self.isRecoverable = true
            case .parseError(let msg):
                self.message = "Data error: \(msg)"
                self.isRecoverable = true
            case .timeout:
                self.message = "Request timed out"
                self.isRecoverable = true
            case .rateLimited:
                self.message = "Too many requests"
                self.isRecoverable = true
            }
            self.underlyingError = dataSourceError
        } else {
            self.message = error.localizedDescription
            self.underlyingError = error
            self.isRecoverable = true
        }
    }
    
    public var errorDescription: String? {
        message
    }
}

// MARK: - Preview Support

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public extension StreamingDashboardViewModel {
    /// Create a preview view model with mock state
    static func preview(
        glucose: Int = 120,
        trend: GlucoseTrend = .flat,
        iob: Double = 2.5,
        cob: Double = 20
    ) -> StreamingDashboardViewModel {
        let vm = StreamingDashboardViewModel(
            dataSource: PreviewDataSource()
        )
        vm.state = DashboardState(
            glucose: GlucoseState(
                value: glucose,
                trend: trend,
                timestamp: Date()
            ),
            connection: ConnectionState(
                status: .connected,
                sourceName: "Preview",
                sourceId: "preview"
            ),
            algorithm: AlgorithmDisplayState(
                iobUnits: iob,
                cobGrams: cob,
                loopStatus: .running
            )
        )
        return vm
    }
    
    /// Create a preview with loading state
    static var loadingPreview: StreamingDashboardViewModel {
        let vm = StreamingDashboardViewModel(dataSource: PreviewDataSource())
        vm.isLoading = true
        return vm
    }
    
    /// Create a preview with error state
    static var errorPreview: StreamingDashboardViewModel {
        let vm = StreamingDashboardViewModel(dataSource: PreviewDataSource())
        vm.error = DashboardError(message: "Connection failed", isRecoverable: true)
        return vm
    }
    
    /// Create a preview with no data
    static var noDataPreview: StreamingDashboardViewModel {
        let vm = StreamingDashboardViewModel(dataSource: PreviewDataSource())
        vm.state = DashboardState(
            glucose: nil,
            connection: ConnectionState(
                status: .configurationRequired,
                sourceName: "Not Configured",
                sourceId: "none"
            )
        )
        return vm
    }
}

/// Preview data source for SwiftUI previews
private actor PreviewDataSource: GlucoseDataSource {
    nonisolated let id = "preview"
    nonisolated let name = "Preview"
    
    var status: DataSourceStatus { .connected }
    
    func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        // Generate mock readings
        let now = Date()
        return (0..<count).map { i in
            GlucoseReading(
                id: UUID(),
                glucose: Double(120 + Int.random(in: -20...20)),
                timestamp: now.addingTimeInterval(TimeInterval(-i * 300)),
                trend: .flat,
                source: "Preview"
            )
        }
    }
    
    func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        try await fetchRecentReadings(count: 24)
    }
}
#endif

// MARK: - SwiftUI Convenience

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public extension StreamingDashboardViewModel {
    /// Binding for auto-refresh toggle
    var autoRefreshBinding: Binding<Bool> {
        Binding(
            get: { self.autoRefreshEnabled },
            set: { self.autoRefreshEnabled = $0 }
        )
    }
    
    /// View modifier to start/stop streaming with view lifecycle
    func onAppear() {
        startStreaming()
    }
    
    func onDisappear() {
        stopStreaming()
    }
}
#endif

#endif // canImport(Observation)
