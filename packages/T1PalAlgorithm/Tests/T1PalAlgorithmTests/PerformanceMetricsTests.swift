// PerformanceMetricsTests.swift
// T1PalAlgorithm
//
// Tests for performance metrics infrastructure.

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Execution Metrics Tests

@Suite("Execution Metrics")
struct ExecutionMetricsTests {
    
    @Test("Creates metrics with all fields")
    func createsWithAllFields() {
        let metrics = ExecutionMetrics(
            calculationTimeMs: 15.5,
            peakMemoryBytes: 1024 * 1024,
            cpuTimeMs: 12.3,
            predictionCount: 288,
            doseEvaluations: 5,
            predictionTimeMs: 8.0,
            insulinCalcTimeMs: 3.0,
            carbCalcTimeMs: 2.0
        )
        
        #expect(metrics.calculationTimeMs == 15.5)
        #expect(metrics.peakMemoryBytes == 1024 * 1024)
        #expect(metrics.cpuTimeMs == 12.3)
        #expect(metrics.predictionCount == 288)
        #expect(metrics.doseEvaluations == 5)
    }
    
    @Test("Creates metrics with defaults")
    func createsWithDefaults() {
        let metrics = ExecutionMetrics(calculationTimeMs: 10.0)
        
        #expect(metrics.peakMemoryBytes == 0)
        #expect(metrics.cpuTimeMs == nil)
        #expect(metrics.predictionCount == 0)
    }
    
    @Test("Formats time in microseconds")
    func formatsTimeMicroseconds() {
        let metrics = ExecutionMetrics(calculationTimeMs: 0.5)
        #expect(metrics.formattedTime.contains("µs"))
    }
    
    @Test("Formats time in milliseconds")
    func formatsTimeMilliseconds() {
        let metrics = ExecutionMetrics(calculationTimeMs: 15.0)
        #expect(metrics.formattedTime.contains("ms"))
    }
    
    @Test("Formats time in seconds")
    func formatsTimeSeconds() {
        let metrics = ExecutionMetrics(calculationTimeMs: 1500.0)
        #expect(metrics.formattedTime.contains("s"))
    }
    
    @Test("Formats memory in bytes")
    func formatsMemoryBytes() {
        let metrics = ExecutionMetrics(calculationTimeMs: 1.0, peakMemoryBytes: 500)
        #expect(metrics.formattedMemory.contains("B"))
    }
    
    @Test("Formats memory in kilobytes")
    func formatsMemoryKilobytes() {
        let metrics = ExecutionMetrics(calculationTimeMs: 1.0, peakMemoryBytes: 50 * 1024)
        #expect(metrics.formattedMemory.contains("KB"))
    }
    
    @Test("Formats memory in megabytes")
    func formatsMemoryMegabytes() {
        let metrics = ExecutionMetrics(calculationTimeMs: 1.0, peakMemoryBytes: 5 * 1024 * 1024)
        #expect(metrics.formattedMemory.contains("MB"))
    }
}

// MARK: - Execution Context Tests

@Suite("Execution Context")
struct ExecutionContextTests {
    
    @Test("Creates context with all fields")
    func createsWithAllFields() {
        let context = ExecutionContext(
            vectorId: "TV-001",
            inputGlucoseCount: 288,
            inputDuration: 86400,
            hasActiveCOB: true,
            hasActiveIOB: true,
            isOverrideActive: false,
            platform: "iOS"
        )
        
        #expect(context.vectorId == "TV-001")
        #expect(context.inputGlucoseCount == 288)
        #expect(context.hasActiveCOB == true)
        #expect(context.platform == "iOS")
    }
    
    @Test("Creates context with defaults")
    func createsWithDefaults() {
        let context = ExecutionContext()
        
        #expect(context.vectorId == nil)
        #expect(context.inputGlucoseCount == 0)
        #expect(context.hasActiveCOB == false)
    }
    
    @Test("Detects current platform")
    func detectsCurrentPlatform() {
        let platform = ExecutionContext.currentPlatform
        #expect(!platform.isEmpty)
        #expect(platform != "unknown")
    }
}

// MARK: - Performance Snapshot Tests

@Suite("Performance Snapshot")
struct PerformanceSnapshotTests {
    
    @Test("Creates snapshot with all fields")
    func createsSnapshot() {
        let metrics = ExecutionMetrics(calculationTimeMs: 10.0)
        let context = ExecutionContext(platform: "iOS")
        
        let snapshot = PerformanceSnapshot(
            algorithmId: "oref1",
            metrics: metrics,
            context: context
        )
        
        #expect(snapshot.algorithmId == "oref1")
        #expect(snapshot.metrics.calculationTimeMs == 10.0)
        #expect(snapshot.context.platform == "iOS")
        #expect(!snapshot.id.isEmpty)
    }
    
    @Test("Generates unique IDs")
    func generatesUniqueIds() {
        let metrics = ExecutionMetrics(calculationTimeMs: 1.0)
        let context = ExecutionContext()
        
        let snap1 = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: context)
        let snap2 = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: context)
        
        #expect(snap1.id != snap2.id)
    }
}

// MARK: - Timing Stats Tests

@Suite("Timing Stats")
struct TimingStatsTests {
    
    @Test("Creates timing stats")
    func createsStats() {
        let stats = TimingStats(
            min: 1.0,
            max: 10.0,
            mean: 5.0,
            median: 4.5,
            p95: 9.0,
            p99: 9.5,
            stdDev: 2.0
        )
        
        #expect(stats.min == 1.0)
        #expect(stats.max == 10.0)
        #expect(stats.mean == 5.0)
        #expect(stats.p95 == 9.0)
    }
    
    @Test("Generates summary string")
    func generatesSummary() {
        let stats = TimingStats(
            min: 1.0, max: 10.0, mean: 5.0,
            median: 4.5, p95: 9.0, p99: 9.5, stdDev: 2.0
        )
        
        let summary = stats.summary
        #expect(summary.contains("mean"))
        #expect(summary.contains("p95"))
        #expect(summary.contains("p99"))
    }
}

// MARK: - Memory Stats Tests

@Suite("Memory Stats")
struct MemoryStatsTests {
    
    @Test("Creates memory stats")
    func createsStats() {
        let stats = MemoryStats(
            min: 1024,
            max: 10 * 1024 * 1024,
            mean: 5 * 1024 * 1024,
            median: 4 * 1024 * 1024
        )
        
        #expect(stats.min == 1024)
        #expect(stats.max == 10 * 1024 * 1024)
    }
    
    @Test("Generates summary string")
    func generatesSummary() {
        let stats = MemoryStats(
            min: 1024, max: 10 * 1024 * 1024,
            mean: 5 * 1024 * 1024, median: 4 * 1024 * 1024
        )
        
        let summary = stats.summary
        #expect(summary.contains("MB"))
    }
}

// MARK: - Throughput Stats Tests

@Suite("Throughput Stats")
struct ThroughputStatsTests {
    
    @Test("Creates throughput stats")
    func createsStats() {
        let stats = ThroughputStats(
            iterationsPerSecond: 100.0,
            predictionsPerSecond: 28800.0
        )
        
        #expect(stats.iterationsPerSecond == 100.0)
        #expect(stats.predictionsPerSecond == 28800.0)
    }
    
    @Test("Generates summary string")
    func generatesSummary() {
        let stats = ThroughputStats(
            iterationsPerSecond: 100.0,
            predictionsPerSecond: 28800.0
        )
        
        let summary = stats.summary
        #expect(summary.contains("iter/s"))
        #expect(summary.contains("pred/s"))
    }
}

// MARK: - Performance Statistics Tests

@Suite("Performance Statistics")
struct PerformanceStatisticsTests {
    
    @Test("Creates empty statistics")
    func createsEmpty() {
        let stats = PerformanceStatistics.empty
        
        #expect(stats.sampleCount == 0)
        #expect(stats.timing.mean == 0)
        #expect(stats.memory.mean == 0)
    }
    
    @Test("Creates full statistics")
    func createsFull() {
        let timing = TimingStats(min: 1, max: 10, mean: 5, median: 4.5, p95: 9, p99: 9.5, stdDev: 2)
        let memory = MemoryStats(min: 1024, max: 1024 * 1024, mean: 512 * 1024, median: 500 * 1024)
        let throughput = ThroughputStats(iterationsPerSecond: 100, predictionsPerSecond: 28800)
        
        let stats = PerformanceStatistics(
            sampleCount: 100,
            timing: timing,
            memory: memory,
            throughput: throughput
        )
        
        #expect(stats.sampleCount == 100)
        #expect(stats.timing.mean == 5)
        #expect(stats.memory.max == 1024 * 1024)
    }
}

// MARK: - Performance Collector Tests

@Suite("Performance Collector")
struct PerformanceCollectorTests {
    
    @Test("Records snapshots")
    func recordsSnapshots() async {
        let collector = PerformanceCollector(algorithmId: "test")
        
        let metrics = ExecutionMetrics(calculationTimeMs: 10.0)
        let context = ExecutionContext()
        let snapshot = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: context)
        
        await collector.record(snapshot)
        
        let count = await collector.count
        #expect(count == 1)
    }
    
    @Test("Records execution")
    func recordsExecution() async {
        let collector = PerformanceCollector(algorithmId: "test")
        
        await collector.recordExecution(
            calculationTimeMs: 15.0,
            peakMemoryBytes: 1024,
            predictionCount: 288,
            context: ExecutionContext()
        )
        
        let snapshots = await collector.allSnapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].metrics.calculationTimeMs == 15.0)
    }
    
    @Test("Limits snapshots")
    func limitsSnapshots() async {
        let collector = PerformanceCollector(algorithmId: "test", maxSnapshots: 5)
        
        for i in 0..<10 {
            let metrics = ExecutionMetrics(calculationTimeMs: Double(i))
            let snapshot = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: ExecutionContext())
            await collector.record(snapshot)
        }
        
        let count = await collector.count
        #expect(count == 5)
        
        let snapshots = await collector.allSnapshots()
        #expect(snapshots.first?.metrics.calculationTimeMs == 5.0)
    }
    
    @Test("Returns recent snapshots")
    func returnsRecentSnapshots() async {
        let collector = PerformanceCollector(algorithmId: "test")
        
        for i in 0..<20 {
            let metrics = ExecutionMetrics(calculationTimeMs: Double(i))
            let snapshot = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: ExecutionContext())
            await collector.record(snapshot)
        }
        
        let recent = await collector.recentSnapshots(count: 5)
        #expect(recent.count == 5)
        #expect(recent.last?.metrics.calculationTimeMs == 19.0)
    }
    
    @Test("Clears snapshots")
    func clearsSnapshots() async {
        let collector = PerformanceCollector(algorithmId: "test")
        
        let metrics = ExecutionMetrics(calculationTimeMs: 10.0)
        let snapshot = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: ExecutionContext())
        await collector.record(snapshot)
        
        await collector.clear()
        
        let count = await collector.count
        #expect(count == 0)
    }
    
    @Test("Measures operation")
    func measuresOperation() async {
        let collector = PerformanceCollector(algorithmId: "test")
        let context = ExecutionContext(platform: "test")
        
        let (result, metrics) = await collector.measure(context: context) {
            // Simulate work
            var sum = 0
            for i in 0..<1000 {
                sum += i
            }
            return sum
        }
        
        #expect(result == 499500)
        #expect(metrics.calculationTimeMs > 0)
        
        let count = await collector.count
        #expect(count == 1)
    }
    
    @Test("Computes statistics")
    func computesStatistics() async {
        let collector = PerformanceCollector(algorithmId: "test")
        
        for i in 1...10 {
            let metrics = ExecutionMetrics(
                calculationTimeMs: Double(i),
                peakMemoryBytes: i * 1024,
                predictionCount: i * 10
            )
            let snapshot = PerformanceSnapshot(algorithmId: "test", metrics: metrics, context: ExecutionContext())
            await collector.record(snapshot)
        }
        
        let stats = await collector.computeStatistics()
        
        #expect(stats.sampleCount == 10)
        #expect(stats.timing.min == 1.0)
        #expect(stats.timing.max == 10.0)
        #expect(stats.timing.mean == 5.5)
    }
    
    @Test("Computes empty statistics")
    func computesEmptyStatistics() async {
        let collector = PerformanceCollector(algorithmId: "test")
        let stats = await collector.computeStatistics()
        
        #expect(stats.sampleCount == 0)
        #expect(stats.timing.mean == 0)
    }
    
    @Test("Gets current memory usage")
    func getsCurrentMemoryUsage() {
        let memory = PerformanceCollector.currentMemoryUsage()
        // Should return a positive value on most platforms
        #expect(memory >= 0)
    }
}

// MARK: - Performance Report Tests

@Suite("Performance Report")
struct PerformanceReportTests {
    
    func sampleStats() -> PerformanceStatistics {
        let timing = TimingStats(min: 1, max: 10, mean: 5, median: 4.5, p95: 9, p99: 9.5, stdDev: 2)
        let memory = MemoryStats(min: 1024, max: 10 * 1024 * 1024, mean: 5 * 1024 * 1024, median: 4 * 1024 * 1024)
        let throughput = ThroughputStats(iterationsPerSecond: 100, predictionsPerSecond: 28800)
        return PerformanceStatistics(sampleCount: 100, timing: timing, memory: memory, throughput: throughput)
    }
    
    @Test("Creates report")
    func createsReport() {
        let report = PerformanceReport(
            statistics: sampleStats(),
            algorithmId: "oref1"
        )
        
        #expect(report.algorithmId == "oref1")
        #expect(report.statistics.sampleCount == 100)
    }
    
    @Test("Generates text summary")
    func generatesTextSummary() {
        let report = PerformanceReport(
            statistics: sampleStats(),
            algorithmId: "oref1"
        )
        
        let text = report.textSummary()
        
        #expect(text.contains("PERFORMANCE REPORT"))
        #expect(text.contains("oref1"))
        #expect(text.contains("Timing"))
        #expect(text.contains("Memory"))
        #expect(text.contains("Throughput"))
    }
    
    @Test("Generates compact summary")
    func generatesCompactSummary() {
        let report = PerformanceReport(
            statistics: sampleStats(),
            algorithmId: "oref1"
        )
        
        let compact = report.compactSummary()
        
        #expect(compact.contains("oref1"))
        #expect(compact.contains("mean"))
        #expect(compact.contains("p99"))
    }
    
    @Test("Generates JSON report")
    func generatesJsonReport() throws {
        let report = PerformanceReport(
            statistics: sampleStats(),
            algorithmId: "oref1"
        )
        
        let data = try report.jsonReport()
        #expect(data.count > 0)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["algorithmId"] as? String == "oref1")
        #expect(json?["sampleCount"] as? Int == 100)
    }
}

// MARK: - Benchmark Runner Tests

@Suite("Benchmark Runner")
struct BenchmarkRunnerTests {
    
    @Test("Runs benchmark")
    func runsBenchmark() {
        let runner = BenchmarkRunner(warmupIterations: 2, measureIterations: 5)
        let config = BenchmarkRunner.Config(algorithmId: "test", warmupIterations: 2, measureIterations: 5)
        
        var counter = 0
        let result = runner.run(config: config) {
            counter += 1
            return counter
        }
        
        // 2 warmup + 5 measure = 7 total calls
        #expect(counter == 7)
        #expect(result.statistics.sampleCount == 5)
        #expect(result.allTimings.count == 5)
    }
    
    @Test("Calculates timing statistics")
    func calculatesTimingStats() {
        let runner = BenchmarkRunner()
        let config = BenchmarkRunner.Config(algorithmId: "test", warmupIterations: 1, measureIterations: 10)
        
        let result = runner.run(config: config) {
            // Simulate varying work
            var sum = 0
            for i in 0..<1000 {
                sum += i
            }
            return sum
        }
        
        #expect(result.statistics.timing.min <= result.statistics.timing.mean)
        #expect(result.statistics.timing.mean <= result.statistics.timing.max)
        #expect(result.statistics.timing.p95 <= result.statistics.timing.max)
    }
    
    @Test("Captures memory")
    func capturesMemory() {
        let runner = BenchmarkRunner()
        let config = BenchmarkRunner.Config(algorithmId: "test", warmupIterations: 0, measureIterations: 3)
        
        let result = runner.run(config: config) {
            // Allocate some memory
            let data = Array(repeating: 0, count: 1000)
            return data.count
        }
        
        #expect(result.allMemory.count == 3)
    }
}

// MARK: - Performance Comparison Tests

@Suite("Performance Comparison")
struct PerformanceComparisonTests {
    
    func makeStats(mean: Double, memory: Int) -> PerformanceStatistics {
        let timing = TimingStats(min: mean * 0.5, max: mean * 1.5, mean: mean, median: mean, p95: mean * 1.2, p99: mean * 1.3, stdDev: mean * 0.1)
        let mem = MemoryStats(min: memory / 2, max: memory * 2, mean: memory, median: memory)
        let throughput = ThroughputStats(iterationsPerSecond: 1000 / mean, predictionsPerSecond: 28800 / mean)
        return PerformanceStatistics(sampleCount: 100, timing: timing, memory: mem, throughput: throughput)
    }
    
    @Test("Detects faster performance")
    func detectsFaster() {
        let baseline = makeStats(mean: 10.0, memory: 1024 * 1024)
        let current = makeStats(mean: 5.0, memory: 512 * 1024)
        
        let comparison = PerformanceComparison(
            baseline: baseline,
            current: current
        )
        
        #expect(comparison.isFaster == true)
        #expect(comparison.usesLessMemory == true)
        #expect(comparison.timingDifferencePercent < 0)
        #expect(comparison.verdict == .improved)
    }
    
    @Test("Detects slower performance")
    func detectsSlower() {
        let baseline = makeStats(mean: 5.0, memory: 512 * 1024)
        let current = makeStats(mean: 10.0, memory: 1024 * 1024)
        
        let comparison = PerformanceComparison(
            baseline: baseline,
            current: current
        )
        
        #expect(comparison.isFaster == false)
        #expect(comparison.usesLessMemory == false)
        #expect(comparison.timingDifferencePercent > 0)
        #expect(comparison.verdict == .regressed)
    }
    
    @Test("Detects unchanged performance")
    func detectsUnchanged() {
        let baseline = makeStats(mean: 10.0, memory: 1024 * 1024)
        let current = makeStats(mean: 10.2, memory: 1024 * 1024) // 2% difference
        
        let comparison = PerformanceComparison(
            baseline: baseline,
            current: current
        )
        
        #expect(comparison.verdict == .unchanged)
    }
    
    @Test("Detects mixed changes")
    func detectsMixed() {
        let baseline = makeStats(mean: 10.0, memory: 512 * 1024)
        let current = makeStats(mean: 5.0, memory: 1024 * 1024) // Faster but more memory
        
        let comparison = PerformanceComparison(
            baseline: baseline,
            current: current
        )
        
        #expect(comparison.isFaster == true)
        #expect(comparison.usesLessMemory == false)
        #expect(comparison.verdict == .mixed)
    }
    
    @Test("Generates comparison report")
    func generatesReport() {
        let baseline = makeStats(mean: 10.0, memory: 1024 * 1024)
        let current = makeStats(mean: 8.0, memory: 800 * 1024)
        
        let comparison = PerformanceComparison(
            baseline: baseline,
            current: current,
            baselineName: "v1.0",
            currentName: "v1.1"
        )
        
        let report = comparison.textReport()
        
        #expect(report.contains("PERFORMANCE COMPARISON"))
        #expect(report.contains("v1.0"))
        #expect(report.contains("v1.1"))
        #expect(report.contains("Timing"))
        #expect(report.contains("Memory"))
    }
}

// MARK: - Performance Display Tests

@Suite("Performance Display")
struct PerformanceDisplayTests {
    
    @Test("Generates status bar text")
    func generatesStatusBarText() {
        let metrics = ExecutionMetrics(
            calculationTimeMs: 15.5,
            peakMemoryBytes: 512 * 1024
        )
        
        let text = PerformanceDisplay.statusBarText(metrics: metrics)
        
        #expect(text.contains("ms"))
        #expect(text.contains("KB"))
    }
    
    @Test("Generates detail text")
    func generatesDetailText() {
        let metrics = ExecutionMetrics(
            calculationTimeMs: 10.0,
            peakMemoryBytes: 1024 * 1024,
            predictionCount: 288
        )
        let context = ExecutionContext(platform: "iOS")
        let snapshot = PerformanceSnapshot(
            algorithmId: "oref1",
            metrics: metrics,
            context: context
        )
        
        let text = PerformanceDisplay.detailText(snapshot: snapshot)
        
        #expect(text.contains("oref1"))
        #expect(text.contains("288"))
        #expect(text.contains("iOS"))
    }
    
    @Test("Generates dashboard text")
    func generatesDashboardText() {
        let timing = TimingStats(min: 1, max: 10, mean: 5, median: 4.5, p95: 9, p99: 9.5, stdDev: 2)
        let memory = MemoryStats(min: 1024, max: 1024 * 1024, mean: 512 * 1024, median: 500 * 1024)
        let throughput = ThroughputStats(iterationsPerSecond: 100, predictionsPerSecond: 28800)
        let stats = PerformanceStatistics(sampleCount: 100, timing: timing, memory: memory, throughput: throughput)
        
        let text = PerformanceDisplay.dashboardText(stats: stats)
        
        #expect(text.contains("100"))
        #expect(text.contains("Mean"))
        #expect(text.contains("P99"))
    }
}
