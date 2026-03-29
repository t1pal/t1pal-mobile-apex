// SPDX-License-Identifier: AGPL-3.0-or-later
// T1PalCore - ObservabilityContext
// Unified observability infrastructure for metrics, traces, and feature flags
// Trace: PRD-025 REQ-OBS-001, OBS-001, OBS-002

import Foundation

// MARK: - Metrics Collector

/// Protocol for collecting metrics (latency, error counts, throughput)
/// REQ-OBS-001.1
public protocol MetricsCollector: Sendable {
    /// Record a timing metric
    func recordTiming(_ name: String, duration: TimeInterval, tags: [String: String])
    
    /// Increment a counter metric
    func incrementCounter(_ name: String, value: Int, tags: [String: String])
    
    /// Record a gauge value
    func recordGauge(_ name: String, value: Double, tags: [String: String])
}

// MARK: - Performance Thresholds (DATA-SCALE-006)

/// Configuration for performance warning thresholds.
/// When timing metrics exceed these thresholds, warnings are logged.
/// Trace: DATA-SCALE-006
public struct PerformanceThresholds: Sendable {
    /// Default threshold for store load operations (100ms)
    public static let storeLoadWarning: TimeInterval = 0.100
    
    /// Default threshold for store save operations (50ms)
    public static let storeSaveWarning: TimeInterval = 0.050
    
    /// Default threshold for fetch operations (50ms)
    public static let fetchWarning: TimeInterval = 0.050
    
    /// Default threshold for general operations (100ms)
    public static let generalWarning: TimeInterval = 0.100
    
    /// Get threshold for a given metric name
    public static func threshold(for metricName: String) -> TimeInterval {
        if metricName.contains(".load") {
            return storeLoadWarning
        } else if metricName.contains(".save") {
            return storeSaveWarning
        } else if metricName.contains(".fetch") {
            return fetchWarning
        }
        return generalWarning
    }
    
    /// Check if duration exceeds threshold and return warning message if so
    public static func checkThreshold(name: String, duration: TimeInterval) -> String? {
        let threshold = self.threshold(for: name)
        if duration > threshold {
            let durationMs = duration * 1000
            let thresholdMs = threshold * 1000
            return "⚠️ SLOW: \(name) took \(String(format: "%.1f", durationMs))ms (threshold: \(String(format: "%.0f", thresholdMs))ms)"
        }
        return nil
    }
}

/// Default no-op metrics collector for production (REQ-OBS-001.1 PROD lightweight)
public struct NoOpMetricsCollector: MetricsCollector, Sendable {
    public init() {}
    
    public func recordTiming(_ name: String, duration: TimeInterval, tags: [String: String]) {}
    public func incrementCounter(_ name: String, value: Int, tags: [String: String]) {}
    public func recordGauge(_ name: String, value: Double, tags: [String: String]) {}
}

/// Debug metrics collector that logs to console (REQ-OBS-001.1 DEBUG verbose)
/// DATA-SCALE-006: Includes threshold checking with warnings
public struct DebugMetricsCollector: MetricsCollector, Sendable {
    public init() {}
    
    public func recordTiming(_ name: String, duration: TimeInterval, tags: [String: String]) {
        #if DEBUG
        // DATA-SCALE-006: Check thresholds and warn if exceeded
        if let warning = PerformanceThresholds.checkThreshold(name: name, duration: duration) {
            T1PalCoreLogger.metrics.warning("\(warning)")
        }
        T1PalCoreLogger.metrics.debug("timing \(name): \(String(format: "%.3f", duration * 1000))ms \(tags)")
        #endif
    }
    
    public func incrementCounter(_ name: String, value: Int, tags: [String: String]) {
        #if DEBUG
        T1PalCoreLogger.metrics.debug("counter \(name): +\(value) \(tags)")
        #endif
    }
    
    public func recordGauge(_ name: String, value: Double, tags: [String: String]) {
        #if DEBUG
        T1PalCoreLogger.metrics.debug("gauge \(name): \(value) \(tags)")
        #endif
    }
}

// MARK: - Storing Metrics Collector (OBS-002)

/// Metric data point for storage
public struct MetricDataPoint: Sendable {
    public let name: String
    public let timestamp: Date
    public let value: Double
    public let tags: [String: String]
    public let type: MetricType
    
    public enum MetricType: String, Sendable {
        case timing
        case counter
        case gauge
    }
    
    public init(name: String, timestamp: Date = Date(), value: Double, tags: [String: String], type: MetricType) {
        self.name = name
        self.timestamp = timestamp
        self.value = value
        self.tags = tags
        self.type = type
    }
}

/// Metrics collector that stores metrics in memory for debugging/display (OBS-002)
/// Thread-safe storage with configurable capacity
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public final class StoringMetricsCollector: MetricsCollector, @unchecked Sendable {
    private var metrics: [MetricDataPoint] = []
    private let maxCapacity: Int
    private let logToConsole: Bool
    
    public init(maxCapacity: Int = 1000, logToConsole: Bool = true) {
        self.maxCapacity = maxCapacity
        self.logToConsole = logToConsole
    }
    
    public nonisolated func recordTiming(_ name: String, duration: TimeInterval, tags: [String: String]) {
        let point = MetricDataPoint(name: name, value: duration * 1000, tags: tags, type: .timing)
        Task { @MainActor in
            self.store(point)
        }
        if logToConsole {
            #if DEBUG
            // DATA-SCALE-006: Check thresholds and warn if exceeded
            if let warning = PerformanceThresholds.checkThreshold(name: name, duration: duration) {
                T1PalCoreLogger.metrics.warning("\(warning)")
            }
            T1PalCoreLogger.metrics.debug("timing \(name): \(String(format: "%.3f", duration * 1000))ms \(tags)")
            #endif
        }
    }
    
    public nonisolated func incrementCounter(_ name: String, value: Int, tags: [String: String]) {
        let point = MetricDataPoint(name: name, value: Double(value), tags: tags, type: .counter)
        Task { @MainActor in
            self.store(point)
        }
        if logToConsole {
            #if DEBUG
            T1PalCoreLogger.metrics.debug("counter \(name): +\(value) \(tags)")
            #endif
        }
    }
    
    public nonisolated func recordGauge(_ name: String, value: Double, tags: [String: String]) {
        let point = MetricDataPoint(name: name, value: value, tags: tags, type: .gauge)
        Task { @MainActor in
            self.store(point)
        }
        if logToConsole {
            #if DEBUG
            T1PalCoreLogger.metrics.debug("gauge \(name): \(value) \(tags)")
            #endif
        }
    }
    
    private func store(_ point: MetricDataPoint) {
        metrics.append(point)
        if metrics.count > maxCapacity {
            metrics.removeFirst(metrics.count - maxCapacity)
        }
    }
    
    /// Get all stored metrics
    public var allMetrics: [MetricDataPoint] { metrics }
    
    /// Get metrics by name
    public func metrics(named name: String) -> [MetricDataPoint] {
        metrics.filter { $0.name == name }
    }
    
    /// Get metrics by type
    public func metrics(ofType type: MetricDataPoint.MetricType) -> [MetricDataPoint] {
        metrics.filter { $0.type == type }
    }
    
    /// Clear all stored metrics
    public func clear() {
        metrics.removeAll()
    }
    
    /// Get summary statistics for a timing metric
    public func timingSummary(named name: String) -> (count: Int, min: Double, max: Double, avg: Double)? {
        let timings = metrics(named: name).filter { $0.type == .timing }
        guard !timings.isEmpty else { return nil }
        let values = timings.map { $0.value }
        return (
            count: values.count,
            min: values.min() ?? 0,
            max: values.max() ?? 0,
            avg: values.reduce(0, +) / Double(values.count)
        )
    }
}

/// Factory for creating build-variant appropriate MetricsCollector (OBS-002)
public enum MetricsCollectorFactory {
    /// Create metrics collector appropriate for current build variant
    /// Note: Use debug() for StoringMetricsCollector with MainActor context
    public static func create() -> any MetricsCollector {
        #if DEBUG
        return DebugMetricsCollector()
        #else
        return NoOpMetricsCollector()
        #endif
    }
    
    /// Create debug metrics collector with storage (verbose logging + in-memory storage)
    /// Must be called from MainActor context
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    @MainActor
    public static func debug() -> StoringMetricsCollector {
        StoringMetricsCollector(maxCapacity: 1000, logToConsole: true)
    }
    
    /// Create lightweight debug collector (logging only, no storage)
    public static func debugLightweight() -> DebugMetricsCollector {
        DebugMetricsCollector()
    }
    
    /// Create production metrics collector (no-op)
    public static func production() -> NoOpMetricsCollector {
        NoOpMetricsCollector()
    }
}

// MARK: - Trace Collector

/// Protocol for distributed tracing (correlation IDs, spans)
/// REQ-OBS-001.2
public protocol TraceCollector: Sendable {
    /// Start a new trace span
    func startSpan(_ name: String, traceId: String?) -> TraceSpan
    
    /// Get current correlation ID
    var currentTraceId: String? { get }
}

/// Represents a trace span
public struct TraceSpan: Sendable {
    public let spanId: String
    public let traceId: String
    public let name: String
    public let startTime: Date
    
    public init(spanId: String = UUID().uuidString, traceId: String = UUID().uuidString, name: String, startTime: Date = Date()) {
        self.spanId = spanId
        self.traceId = traceId
        self.name = name
        self.startTime = startTime
    }
    
    /// End the span and return duration
    public func end() -> TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

/// Default no-op trace collector for production
public struct NoOpTraceCollector: TraceCollector, Sendable {
    public init() {}
    
    public func startSpan(_ name: String, traceId: String?) -> TraceSpan {
        TraceSpan(name: name)
    }
    
    public var currentTraceId: String? { nil }
}

/// Debug trace collector that logs spans
public struct DebugTraceCollector: TraceCollector, Sendable {
    public init() {}
    
    public func startSpan(_ name: String, traceId: String?) -> TraceSpan {
        let span = TraceSpan(traceId: traceId ?? UUID().uuidString, name: name)
        #if DEBUG
        T1PalCoreLogger.traces.debug("start \(name) span=\(span.spanId.prefix(8)) trace=\(span.traceId.prefix(8))")
        #endif
        return span
    }
    
    public var currentTraceId: String? { nil }
}

// MARK: - Feature Flag Provider

/// Protocol for feature flags and remote config
/// REQ-OBS-001.3
public protocol FeatureFlagProvider: Sendable {
    /// Check if a feature is enabled
    func isEnabled(_ flag: String) -> Bool
    
    /// Get a string config value
    func getString(_ key: String, default: String) -> String
    
    /// Get an integer config value
    func getInt(_ key: String, default: Int) -> Int
}

/// Default feature flag provider with local defaults
public struct DefaultFeatureFlagProvider: FeatureFlagProvider, Sendable {
    private let overrides: [String: Bool]
    
    public init(overrides: [String: Bool] = [:]) {
        self.overrides = overrides
    }
    
    public func isEnabled(_ flag: String) -> Bool {
        overrides[flag] ?? false
    }
    
    public func getString(_ key: String, default defaultValue: String) -> String {
        defaultValue
    }
    
    public func getInt(_ key: String, default defaultValue: Int) -> Int {
        defaultValue
    }
}

// MARK: - Observability Context

/// Unified observability context for the entire data pipeline
/// REQ-OBS-001
public struct ObservabilityContext: Sendable {
    /// Metrics collection (latency, error rates, counts)
    public let metrics: any MetricsCollector
    
    /// Distributed tracing (correlation IDs, spans)
    public let traces: any TraceCollector
    
    /// Feature flags (remote config, experiments)
    public let flags: any FeatureFlagProvider
    
    public init(
        metrics: any MetricsCollector,
        traces: any TraceCollector,
        flags: any FeatureFlagProvider
    ) {
        self.metrics = metrics
        self.traces = traces
        self.flags = flags
    }
    
    // MARK: - Factory Methods (REQ-OBS-003)
    
    /// Create debug configuration with verbose logging
    public static func debug() -> ObservabilityContext {
        ObservabilityContext(
            metrics: DebugMetricsCollector(),
            traces: DebugTraceCollector(),
            flags: DefaultFeatureFlagProvider()
        )
    }
    
    /// Create TestFlight configuration with standard metrics
    public static func testFlight() -> ObservabilityContext {
        ObservabilityContext(
            metrics: DebugMetricsCollector(),
            traces: NoOpTraceCollector(),
            flags: DefaultFeatureFlagProvider()
        )
    }
    
    /// Create production configuration with lightweight metrics
    public static func production() -> ObservabilityContext {
        ObservabilityContext(
            metrics: NoOpMetricsCollector(),
            traces: NoOpTraceCollector(),
            flags: DefaultFeatureFlagProvider()
        )
    }
    
    /// Create appropriate context based on build configuration
    public static var current: ObservabilityContext {
        #if DEBUG
        return .debug()
        #else
        return .production()
        #endif
    }
}

// MARK: - Convenience Extensions

public extension ObservabilityContext {
    /// Measure execution time of a closure
    func measure<T>(_ name: String, tags: [String: String] = [:], operation: () throws -> T) rethrows -> T {
        let span = traces.startSpan(name, traceId: nil)
        defer {
            let duration = span.end()
            metrics.recordTiming(name, duration: duration, tags: tags)
        }
        return try operation()
    }
    
    /// Measure execution time of an async closure
    func measureAsync<T>(_ name: String, tags: [String: String] = [:], operation: () async throws -> T) async rethrows -> T {
        let span = traces.startSpan(name, traceId: nil)
        defer {
            let duration = span.end()
            metrics.recordTiming(name, duration: duration, tags: tags)
        }
        return try await operation()
    }
}
