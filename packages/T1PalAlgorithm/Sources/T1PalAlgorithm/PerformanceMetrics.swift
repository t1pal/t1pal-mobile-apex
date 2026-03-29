// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PerformanceMetrics.swift
// T1PalAlgorithm
//
// Performance metrics infrastructure for algorithm benchmarking.
// Captures timing, memory usage, and execution statistics.
//
// ALG-BENCH-013: Performance metrics display

import Foundation

// MARK: - Performance Snapshot

/// A single performance measurement snapshot.
public struct PerformanceSnapshot: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let algorithmId: String
    public let metrics: ExecutionMetrics
    public let context: ExecutionContext
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        algorithmId: String,
        metrics: ExecutionMetrics,
        context: ExecutionContext
    ) {
        self.id = id
        self.timestamp = timestamp
        self.algorithmId = algorithmId
        self.metrics = metrics
        self.context = context
    }
}

/// Core execution timing and resource metrics.
public struct ExecutionMetrics: Sendable, Codable, Equatable {
    /// Calculation time in milliseconds.
    public let calculationTimeMs: Double
    
    /// Peak memory usage in bytes.
    public let peakMemoryBytes: Int
    
    /// CPU time in milliseconds (if available).
    public let cpuTimeMs: Double?
    
    /// Number of glucose predictions calculated.
    public let predictionCount: Int
    
    /// Number of dose recommendations evaluated.
    public let doseEvaluations: Int
    
    /// Time spent in glucose prediction in ms.
    public let predictionTimeMs: Double?
    
    /// Time spent in insulin calculations in ms.
    public let insulinCalcTimeMs: Double?
    
    /// Time spent in carb calculations in ms.
    public let carbCalcTimeMs: Double?
    
    public init(
        calculationTimeMs: Double,
        peakMemoryBytes: Int = 0,
        cpuTimeMs: Double? = nil,
        predictionCount: Int = 0,
        doseEvaluations: Int = 0,
        predictionTimeMs: Double? = nil,
        insulinCalcTimeMs: Double? = nil,
        carbCalcTimeMs: Double? = nil
    ) {
        self.calculationTimeMs = calculationTimeMs
        self.peakMemoryBytes = peakMemoryBytes
        self.cpuTimeMs = cpuTimeMs
        self.predictionCount = predictionCount
        self.doseEvaluations = doseEvaluations
        self.predictionTimeMs = predictionTimeMs
        self.insulinCalcTimeMs = insulinCalcTimeMs
        self.carbCalcTimeMs = carbCalcTimeMs
    }
    
    /// Returns formatted memory usage string.
    public var formattedMemory: String {
        if peakMemoryBytes < 1024 {
            return "\(peakMemoryBytes) B"
        } else if peakMemoryBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(peakMemoryBytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(peakMemoryBytes) / (1024 * 1024))
        }
    }
    
    /// Returns formatted calculation time.
    public var formattedTime: String {
        if calculationTimeMs < 1 {
            return String(format: "%.2f µs", calculationTimeMs * 1000)
        } else if calculationTimeMs < 1000 {
            return String(format: "%.2f ms", calculationTimeMs)
        } else {
            return String(format: "%.2f s", calculationTimeMs / 1000)
        }
    }
}

/// Context about the execution environment.
public struct ExecutionContext: Sendable, Codable, Equatable {
    public let vectorId: String?
    public let inputGlucoseCount: Int
    public let inputDuration: TimeInterval
    public let hasActiveCOB: Bool
    public let hasActiveIOB: Bool
    public let isOverrideActive: Bool
    public let platform: String
    
    public init(
        vectorId: String? = nil,
        inputGlucoseCount: Int = 0,
        inputDuration: TimeInterval = 0,
        hasActiveCOB: Bool = false,
        hasActiveIOB: Bool = false,
        isOverrideActive: Bool = false,
        platform: String = "unknown"
    ) {
        self.vectorId = vectorId
        self.inputGlucoseCount = inputGlucoseCount
        self.inputDuration = inputDuration
        self.hasActiveCOB = hasActiveCOB
        self.hasActiveIOB = hasActiveIOB
        self.isOverrideActive = isOverrideActive
        self.platform = platform
    }
    
    /// Platform detection helper.
    public static var currentPlatform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(Linux)
        return "Linux"
        #else
        return "unknown"
        #endif
    }
}

// MARK: - Performance Statistics

/// Aggregated performance statistics.
public struct PerformanceStatistics: Sendable, Codable, Equatable {
    public let sampleCount: Int
    public let timing: TimingStats
    public let memory: MemoryStats
    public let throughput: ThroughputStats
    
    public init(
        sampleCount: Int,
        timing: TimingStats,
        memory: MemoryStats,
        throughput: ThroughputStats
    ) {
        self.sampleCount = sampleCount
        self.timing = timing
        self.memory = memory
        self.throughput = throughput
    }
    
    /// Creates empty statistics.
    public static var empty: PerformanceStatistics {
        PerformanceStatistics(
            sampleCount: 0,
            timing: TimingStats(min: 0, max: 0, mean: 0, median: 0, p95: 0, p99: 0, stdDev: 0),
            memory: MemoryStats(min: 0, max: 0, mean: 0, median: 0),
            throughput: ThroughputStats(iterationsPerSecond: 0, predictionsPerSecond: 0)
        )
    }
}

/// Timing statistics in milliseconds.
public struct TimingStats: Sendable, Codable, Equatable {
    public let min: Double
    public let max: Double
    public let mean: Double
    public let median: Double
    public let p95: Double
    public let p99: Double
    public let stdDev: Double
    
    public init(min: Double, max: Double, mean: Double, median: Double, p95: Double, p99: Double, stdDev: Double) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
        self.p95 = p95
        self.p99 = p99
        self.stdDev = stdDev
    }
    
    /// Formatted summary string.
    public var summary: String {
        String(format: "mean: %.2fms, p95: %.2fms, p99: %.2fms", mean, p95, p99)
    }
}

/// Memory statistics in bytes.
public struct MemoryStats: Sendable, Codable, Equatable {
    public let min: Int
    public let max: Int
    public let mean: Int
    public let median: Int
    
    public init(min: Int, max: Int, mean: Int, median: Int) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
    }
    
    /// Formatted summary string.
    public var summary: String {
        let maxMB = Double(max) / (1024 * 1024)
        let meanMB = Double(mean) / (1024 * 1024)
        return String(format: "mean: %.2f MB, max: %.2f MB", meanMB, maxMB)
    }
}

/// Throughput statistics.
public struct ThroughputStats: Sendable, Codable, Equatable {
    public let iterationsPerSecond: Double
    public let predictionsPerSecond: Double
    
    public init(iterationsPerSecond: Double, predictionsPerSecond: Double) {
        self.iterationsPerSecond = iterationsPerSecond
        self.predictionsPerSecond = predictionsPerSecond
    }
    
    /// Formatted summary string.
    public var summary: String {
        String(format: "%.1f iter/s, %.0f pred/s", iterationsPerSecond, predictionsPerSecond)
    }
}

// MARK: - Performance Collector

/// Actor for collecting performance metrics.
public actor PerformanceCollector {
    private var snapshots: [PerformanceSnapshot] = []
    private let maxSnapshots: Int
    private let algorithmId: String
    
    public init(algorithmId: String = "default", maxSnapshots: Int = 1000) {
        self.algorithmId = algorithmId
        self.maxSnapshots = maxSnapshots
    }
    
    /// Records a performance snapshot.
    public func record(_ snapshot: PerformanceSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst()
        }
    }
    
    /// Records metrics from an execution.
    public func recordExecution(
        calculationTimeMs: Double,
        peakMemoryBytes: Int = 0,
        predictionCount: Int = 0,
        context: ExecutionContext
    ) {
        let metrics = ExecutionMetrics(
            calculationTimeMs: calculationTimeMs,
            peakMemoryBytes: peakMemoryBytes,
            predictionCount: predictionCount
        )
        let snapshot = PerformanceSnapshot(
            algorithmId: algorithmId,
            metrics: metrics,
            context: context
        )
        record(snapshot)
    }
    
    /// Measures execution time of a closure.
    public func measure<T>(
        context: ExecutionContext,
        operation: () throws -> T
    ) rethrows -> (result: T, metrics: ExecutionMetrics) {
        let startTime = DispatchTime.now()
        let memoryBefore = Self.currentMemoryUsage()
        
        let result = try operation()
        
        let memoryAfter = Self.currentMemoryUsage()
        let endTime = DispatchTime.now()
        
        let nanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeMs = Double(nanos) / 1_000_000
        let memoryDelta = max(0, memoryAfter - memoryBefore)
        
        let metrics = ExecutionMetrics(
            calculationTimeMs: timeMs,
            peakMemoryBytes: memoryDelta
        )
        
        let snapshot = PerformanceSnapshot(
            algorithmId: algorithmId,
            metrics: metrics,
            context: context
        )
        record(snapshot)
        
        return (result, metrics)
    }
    
    /// Returns all collected snapshots.
    public func allSnapshots() -> [PerformanceSnapshot] {
        snapshots
    }
    
    /// Returns the most recent snapshots.
    public func recentSnapshots(count: Int = 10) -> [PerformanceSnapshot] {
        Array(snapshots.suffix(count))
    }
    
    /// Clears all snapshots.
    public func clear() {
        snapshots.removeAll()
    }
    
    /// Returns current snapshot count.
    public var count: Int {
        snapshots.count
    }
    
    /// Computes aggregate statistics.
    public func computeStatistics() -> PerformanceStatistics {
        guard !snapshots.isEmpty else { return .empty }
        
        let times = snapshots.map { $0.metrics.calculationTimeMs }.sorted()
        let memories = snapshots.map { $0.metrics.peakMemoryBytes }.sorted()
        let predictions = snapshots.map { $0.metrics.predictionCount }
        
        let timing = Self.computeTimingStats(times)
        let memory = Self.computeMemoryStats(memories)
        
        let totalTime = times.reduce(0, +)
        let totalPredictions = predictions.reduce(0, +)
        let iterPerSec = totalTime > 0 ? Double(times.count) / (totalTime / 1000) : 0
        let predPerSec = totalTime > 0 ? Double(totalPredictions) / (totalTime / 1000) : 0
        
        let throughput = ThroughputStats(
            iterationsPerSecond: iterPerSec,
            predictionsPerSecond: predPerSec
        )
        
        return PerformanceStatistics(
            sampleCount: snapshots.count,
            timing: timing,
            memory: memory,
            throughput: throughput
        )
    }
    
    private static func computeTimingStats(_ sorted: [Double]) -> TimingStats {
        guard !sorted.isEmpty else {
            return TimingStats(min: 0, max: 0, mean: 0, median: 0, p95: 0, p99: 0, stdDev: 0)
        }
        
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let median = percentile(sorted, 0.5)
        let p95 = percentile(sorted, 0.95)
        let p99 = percentile(sorted, 0.99)
        
        let variance = sorted.map { pow($0 - mean, 2) }.reduce(0, +) / Double(sorted.count)
        let stdDev = sqrt(variance)
        
        return TimingStats(min: min, max: max, mean: mean, median: median, p95: p95, p99: p99, stdDev: stdDev)
    }
    
    private static func computeMemoryStats(_ sorted: [Int]) -> MemoryStats {
        guard !sorted.isEmpty else {
            return MemoryStats(min: 0, max: 0, mean: 0, median: 0)
        }
        
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let mean = sorted.reduce(0, +) / sorted.count
        let medianIdx = sorted.count / 2
        let median = sorted[medianIdx]
        
        return MemoryStats(min: min, max: max, mean: mean, median: median)
    }
    
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(Int(Double(sorted.count) * p), sorted.count - 1)
        return sorted[index]
    }
    
    /// Returns current process memory usage (approximate).
    public static func currentMemoryUsage() -> Int {
        #if os(Linux)
        // Read /proc/self/statm on Linux
        if let data = FileManager.default.contents(atPath: "/proc/self/statm"),
           let content = String(data: data, encoding: .utf8) {
            let parts = content.split(separator: " ")
            if parts.count > 1, let pages = Int(parts[1]) {
                return pages * 4096 // Convert pages to bytes
            }
        }
        return 0
        #else
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
        #endif
    }
}

// MARK: - Performance Report

/// Generates formatted performance reports.
public struct PerformanceReport: Sendable {
    public let statistics: PerformanceStatistics
    public let algorithmId: String
    public let generatedAt: Date
    public let platform: String
    
    public init(
        statistics: PerformanceStatistics,
        algorithmId: String,
        generatedAt: Date = Date(),
        platform: String = ExecutionContext.currentPlatform
    ) {
        self.statistics = statistics
        self.algorithmId = algorithmId
        self.generatedAt = generatedAt
        self.platform = platform
    }
    
    /// Generates a text summary report.
    public func textSummary() -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════")
        lines.append("  PERFORMANCE REPORT: \(algorithmId)")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        lines.append("Platform: \(platform)")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("Samples: \(statistics.sampleCount)")
        lines.append("")
        lines.append("─── Timing ───")
        lines.append("  Mean:   \(String(format: "%.2f ms", statistics.timing.mean))")
        lines.append("  Median: \(String(format: "%.2f ms", statistics.timing.median))")
        lines.append("  Min:    \(String(format: "%.2f ms", statistics.timing.min))")
        lines.append("  Max:    \(String(format: "%.2f ms", statistics.timing.max))")
        lines.append("  P95:    \(String(format: "%.2f ms", statistics.timing.p95))")
        lines.append("  P99:    \(String(format: "%.2f ms", statistics.timing.p99))")
        lines.append("  StdDev: \(String(format: "%.2f ms", statistics.timing.stdDev))")
        lines.append("")
        lines.append("─── Memory ───")
        lines.append("  Mean: \(formatBytes(statistics.memory.mean))")
        lines.append("  Max:  \(formatBytes(statistics.memory.max))")
        lines.append("")
        lines.append("─── Throughput ───")
        lines.append("  \(String(format: "%.1f", statistics.throughput.iterationsPerSecond)) iterations/second")
        lines.append("  \(String(format: "%.0f", statistics.throughput.predictionsPerSecond)) predictions/second")
        lines.append("")
        lines.append("═══════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }
    
    /// Generates a compact one-line summary.
    public func compactSummary() -> String {
        String(format: "%@ | mean: %.2fms | p99: %.2fms | %.1f iter/s",
               algorithmId,
               statistics.timing.mean,
               statistics.timing.p99,
               statistics.throughput.iterationsPerSecond)
    }
    
    /// Generates JSON report.
    public func jsonReport() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let report = [
            "algorithmId": algorithmId,
            "platform": platform,
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "sampleCount": statistics.sampleCount,
            "timing": [
                "mean_ms": statistics.timing.mean,
                "median_ms": statistics.timing.median,
                "min_ms": statistics.timing.min,
                "max_ms": statistics.timing.max,
                "p95_ms": statistics.timing.p95,
                "p99_ms": statistics.timing.p99,
                "stdDev_ms": statistics.timing.stdDev
            ],
            "memory": [
                "mean_bytes": statistics.memory.mean,
                "max_bytes": statistics.memory.max
            ],
            "throughput": [
                "iterations_per_second": statistics.throughput.iterationsPerSecond,
                "predictions_per_second": statistics.throughput.predictionsPerSecond
            ]
        ] as [String: Any]
        
        return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Benchmark Runner

/// Runs algorithm benchmarks with consistent methodology.
public struct BenchmarkRunner: Sendable {
    public let warmupIterations: Int
    public let measureIterations: Int
    
    public init(warmupIterations: Int = 3, measureIterations: Int = 10) {
        self.warmupIterations = warmupIterations
        self.measureIterations = measureIterations
    }
    
    /// Benchmark configuration.
    public struct Config: Sendable {
        public let algorithmId: String
        public let context: ExecutionContext
        public let warmupIterations: Int
        public let measureIterations: Int
        
        public init(
            algorithmId: String,
            context: ExecutionContext = ExecutionContext(),
            warmupIterations: Int = 3,
            measureIterations: Int = 10
        ) {
            self.algorithmId = algorithmId
            self.context = context
            self.warmupIterations = warmupIterations
            self.measureIterations = measureIterations
        }
    }
    
    /// Benchmark result.
    public struct Result: Sendable {
        public let config: Config
        public let statistics: PerformanceStatistics
        public let allTimings: [Double]
        public let allMemory: [Int]
        
        public init(
            config: Config,
            statistics: PerformanceStatistics,
            allTimings: [Double],
            allMemory: [Int]
        ) {
            self.config = config
            self.statistics = statistics
            self.allTimings = allTimings
            self.allMemory = allMemory
        }
    }
    
    /// Runs a benchmark with the given configuration.
    public func run<T>(
        config: Config,
        operation: () throws -> T
    ) rethrows -> Result {
        // Warmup
        for _ in 0..<config.warmupIterations {
            _ = try operation()
        }
        
        // Measure
        var timings: [Double] = []
        var memories: [Int] = []
        
        for _ in 0..<config.measureIterations {
            let startTime = DispatchTime.now()
            let memoryBefore = PerformanceCollector.currentMemoryUsage()
            
            _ = try operation()
            
            let memoryAfter = PerformanceCollector.currentMemoryUsage()
            let endTime = DispatchTime.now()
            
            let nanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let timeMs = Double(nanos) / 1_000_000
            let memoryDelta = max(0, memoryAfter - memoryBefore)
            
            timings.append(timeMs)
            memories.append(memoryDelta)
        }
        
        let sortedTimings = timings.sorted()
        let sortedMemories = memories.sorted()
        
        let timing = computeTimingStats(sortedTimings)
        let memory = computeMemoryStats(sortedMemories)
        
        let totalTime = timings.reduce(0, +)
        let iterPerSec = totalTime > 0 ? Double(timings.count) / (totalTime / 1000) : 0
        
        let throughput = ThroughputStats(
            iterationsPerSecond: iterPerSec,
            predictionsPerSecond: 0
        )
        
        let statistics = PerformanceStatistics(
            sampleCount: timings.count,
            timing: timing,
            memory: memory,
            throughput: throughput
        )
        
        return Result(
            config: config,
            statistics: statistics,
            allTimings: timings,
            allMemory: memories
        )
    }
    
    private func computeTimingStats(_ sorted: [Double]) -> TimingStats {
        guard !sorted.isEmpty else {
            return TimingStats(min: 0, max: 0, mean: 0, median: 0, p95: 0, p99: 0, stdDev: 0)
        }
        
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let median = percentile(sorted, 0.5)
        let p95 = percentile(sorted, 0.95)
        let p99 = percentile(sorted, 0.99)
        
        let variance = sorted.map { pow($0 - mean, 2) }.reduce(0, +) / Double(sorted.count)
        let stdDev = sqrt(variance)
        
        return TimingStats(min: min, max: max, mean: mean, median: median, p95: p95, p99: p99, stdDev: stdDev)
    }
    
    private func computeMemoryStats(_ sorted: [Int]) -> MemoryStats {
        guard !sorted.isEmpty else {
            return MemoryStats(min: 0, max: 0, mean: 0, median: 0)
        }
        
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let mean = sorted.reduce(0, +) / sorted.count
        let medianIdx = sorted.count / 2
        let median = sorted[medianIdx]
        
        return MemoryStats(min: min, max: max, mean: mean, median: median)
    }
    
    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(Int(Double(sorted.count) * p), sorted.count - 1)
        return sorted[index]
    }
}

// MARK: - Performance Comparison

/// Compares performance between algorithms or runs.
public struct PerformanceComparison: Sendable {
    public let baseline: PerformanceStatistics
    public let current: PerformanceStatistics
    public let baselineName: String
    public let currentName: String
    
    public init(
        baseline: PerformanceStatistics,
        current: PerformanceStatistics,
        baselineName: String = "baseline",
        currentName: String = "current"
    ) {
        self.baseline = baseline
        self.current = current
        self.baselineName = baselineName
        self.currentName = currentName
    }
    
    /// Timing difference as a percentage (positive = slower, negative = faster).
    public var timingDifferencePercent: Double {
        guard baseline.timing.mean > 0 else { return 0 }
        return ((current.timing.mean - baseline.timing.mean) / baseline.timing.mean) * 100
    }
    
    /// Memory difference as a percentage.
    public var memoryDifferencePercent: Double {
        guard baseline.memory.mean > 0 else { return 0 }
        return ((Double(current.memory.mean) - Double(baseline.memory.mean)) / Double(baseline.memory.mean)) * 100
    }
    
    /// Whether current is faster than baseline.
    public var isFaster: Bool {
        current.timing.mean < baseline.timing.mean
    }
    
    /// Whether current uses less memory.
    public var usesLessMemory: Bool {
        current.memory.mean < baseline.memory.mean
    }
    
    /// Comparison verdict.
    public enum Verdict: String, Sendable {
        case improved = "IMPROVED"
        case regressed = "REGRESSED"
        case unchanged = "UNCHANGED"
        case mixed = "MIXED"
    }
    
    /// Overall verdict based on timing.
    public var verdict: Verdict {
        let timeDiff = abs(timingDifferencePercent)
        if timeDiff < 5 {
            return .unchanged
        } else if isFaster && usesLessMemory {
            return .improved
        } else if !isFaster && !usesLessMemory {
            return .regressed
        } else {
            return .mixed
        }
    }
    
    /// Generates a comparison report.
    public func textReport() -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════")
        lines.append("  PERFORMANCE COMPARISON")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        lines.append("Baseline: \(baselineName) (\(baseline.sampleCount) samples)")
        lines.append("Current:  \(currentName) (\(current.sampleCount) samples)")
        lines.append("")
        lines.append("─── Timing ───")
        lines.append("  Baseline mean: \(String(format: "%.2f ms", baseline.timing.mean))")
        lines.append("  Current mean:  \(String(format: "%.2f ms", current.timing.mean))")
        lines.append("  Difference:    \(String(format: "%+.1f%%", timingDifferencePercent))")
        lines.append("")
        lines.append("─── Memory ───")
        lines.append("  Baseline mean: \(formatBytes(baseline.memory.mean))")
        lines.append("  Current mean:  \(formatBytes(current.memory.mean))")
        lines.append("  Difference:    \(String(format: "%+.1f%%", memoryDifferencePercent))")
        lines.append("")
        lines.append("─── Verdict: \(verdict.rawValue) ───")
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Debug Display

/// Formats metrics for debug UI display.
public struct PerformanceDisplay: Sendable {
    
    /// Single-line summary for status bar.
    public static func statusBarText(metrics: ExecutionMetrics) -> String {
        "\(metrics.formattedTime) | \(metrics.formattedMemory)"
    }
    
    /// Multi-line detail for debug panel.
    public static func detailText(snapshot: PerformanceSnapshot) -> String {
        """
        Algorithm: \(snapshot.algorithmId)
        Time: \(snapshot.metrics.formattedTime)
        Memory: \(snapshot.metrics.formattedMemory)
        Predictions: \(snapshot.metrics.predictionCount)
        Platform: \(snapshot.context.platform)
        """
    }
    
    /// Statistics summary for dashboard.
    public static func dashboardText(stats: PerformanceStatistics) -> String {
        """
        Samples: \(stats.sampleCount)
        Mean: \(String(format: "%.2f ms", stats.timing.mean))
        P99: \(String(format: "%.2f ms", stats.timing.p99))
        Memory: \(formatBytes(stats.memory.mean))
        Rate: \(String(format: "%.1f/s", stats.throughput.iterationsPerSecond))
        """
    }
    
    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
