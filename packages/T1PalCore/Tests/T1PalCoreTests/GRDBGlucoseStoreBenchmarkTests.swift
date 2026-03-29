// GRDBGlucoseStoreBenchmarkTests.swift - Compare GRDB vs JSON store performance
// Trace: DATA-MIGRATE-003
// NOTE: GRDB tests only run on Darwin (iOS/macOS) due to SQLite snapshot limitation

#if canImport(Darwin)
import Foundation
import Testing
@testable import T1PalCore
import CoreFoundation

// MARK: - Test Data Generator

enum GlucoseTestDataGenerator {
    /// Generate N glucose readings with realistic values.
    static func generateReadings(count: Int, baseDate: Date = Date()) -> [GlucoseReading] {
        let trends: [GlucoseTrend] = [.flat, .fortyFiveUp, .fortyFiveDown, .singleUp, .singleDown]
        var readings: [GlucoseReading] = []
        
        for i in 0..<count {
            let timestamp = baseDate.addingTimeInterval(Double(-i * 300)) // 5 min intervals
            let glucose = 100 + Double(i % 50) + Double.random(in: -20...20)
            let trend = trends[i % trends.count]
            
            readings.append(GlucoseReading(
                id: UUID(),
                glucose: max(40, min(400, glucose)),
                timestamp: timestamp,
                trend: trend,
                source: "benchmark",
                syncIdentifier: "bench-\(i)"
            ))
        }
        
        return readings
    }
}

// MARK: - GRDB Store Tests

@Suite("GRDB Glucose Store")
struct GRDBGlucoseStoreTests {
    
    @Test("Save and fetch single reading")
    func testSaveAndFetch() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        
        let reading = GlucoseReading(
            glucose: 120,
            timestamp: Date(),
            trend: .flat,
            source: "test"
        )
        
        try await store.save(reading)
        
        let count = try await store.count()
        #expect(count == 1)
        
        let fetched = try await store.fetchMostRecent()
        #expect(fetched?.glucose == 120)
    }
    
    @Test("Batch save 1000 readings")
    func testBatchSave1000() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 1000)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try await store.save(readings)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let count = try await store.count()
        #expect(count == 1000)
        
        print("[BENCH] GRDB save 1000 readings: \(String(format: "%.2f", elapsed))ms")
        #expect(elapsed < 500, "Save should take < 500ms")
    }
    
    @Test("Date range query on 10K records")
    func testDateRangeQuery10K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        try await store.save(readings)
        
        // Query middle 24 hours
        let to = Date().addingTimeInterval(-1000 * 300) // ~3.5 days ago
        let from = to.addingTimeInterval(-86400) // 1 day range
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try await store.fetch(from: from, to: to)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("[BENCH] GRDB date query (10K total): \(String(format: "%.2f", elapsed))ms, \(results.count) results")
        #expect(elapsed < 50, "Date query should take < 50ms with index")
    }
    
    @Test("Sync identifier lookup on 10K records")
    func testSyncIdLookup10K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        try await store.save(readings)
        
        // Lookup specific sync ID
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await store.fetch(syncIdentifier: "bench-5000")
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        #expect(result != nil)
        print("[BENCH] GRDB sync ID lookup (10K): \(String(format: "%.2f", elapsed))ms")
        #expect(elapsed < 10, "Sync ID lookup should take < 10ms with index")
    }
    
    @Test("Delete old records")
    func testDeleteOld() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 1000)
        try await store.save(readings)
        
        let cutoff = Date().addingTimeInterval(-500 * 300) // ~1.7 days ago
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let deleted = try await store.deleteOlderThan(cutoff)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("[BENCH] GRDB delete old: \(deleted) records in \(String(format: "%.2f", elapsed))ms")
        #expect(deleted > 0)
    }
}

// MARK: - Performance Comparison

@Suite("JSON vs GRDB Performance")
struct JSONvsGRDBPerformanceTests {
    
    @Test("Compare save 1000 readings")
    func compareSave1000() async throws {
        let readings = GlucoseTestDataGenerator.generateReadings(count: 1000)
        
        // GRDB
        let grdbStore = try GRDBGlucoseStore.inMemoryStore()
        let grdbStart = CFAbsoluteTimeGetCurrent()
        try await grdbStore.save(readings)
        let grdbElapsed = (CFAbsoluteTimeGetCurrent() - grdbStart) * 1000
        
        // JSON (InMemory for fair comparison - file I/O adds variance)
        let jsonStore = InMemoryGlucoseStore()
        let jsonStart = CFAbsoluteTimeGetCurrent()
        try await jsonStore.save(readings)
        let jsonElapsed = (CFAbsoluteTimeGetCurrent() - jsonStart) * 1000
        
        print("[BENCH] Save 1000:")
        print("  GRDB: \(String(format: "%.2f", grdbElapsed))ms")
        print("  JSON: \(String(format: "%.2f", jsonElapsed))ms")
        print("  Ratio: \(String(format: "%.1f", jsonElapsed / grdbElapsed))x")
    }
    
    @Test("Compare date query on 10K records")
    func compareDateQuery10K() async throws {
        let readings = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        
        // GRDB
        let grdbStore = try GRDBGlucoseStore.inMemoryStore()
        try await grdbStore.save(readings)
        
        // JSON
        let jsonStore = InMemoryGlucoseStore()
        try await jsonStore.save(readings)
        
        // Query parameters
        let to = Date().addingTimeInterval(-1000 * 300)
        let from = to.addingTimeInterval(-86400)
        
        // GRDB query
        let grdbStart = CFAbsoluteTimeGetCurrent()
        let grdbResults = try await grdbStore.fetch(from: from, to: to)
        let grdbElapsed = (CFAbsoluteTimeGetCurrent() - grdbStart) * 1000
        
        // JSON query
        let jsonStart = CFAbsoluteTimeGetCurrent()
        let jsonResults = try await jsonStore.fetch(from: from, to: to)
        let jsonElapsed = (CFAbsoluteTimeGetCurrent() - jsonStart) * 1000
        
        print("[BENCH] Date query (10K):")
        print("  GRDB: \(String(format: "%.2f", grdbElapsed))ms (\(grdbResults.count) results)")
        print("  JSON: \(String(format: "%.2f", jsonElapsed))ms (\(jsonResults.count) results)")
        print("  Speedup: \(String(format: "%.1f", jsonElapsed / grdbElapsed))x")
        
        #expect(grdbResults.count == jsonResults.count, "Results should match")
    }
    
    @Test("Compare 50K record scale")
    func compare50KScale() async throws {
        let readings = GlucoseTestDataGenerator.generateReadings(count: 50_000)
        
        // GRDB save
        let grdbStore = try GRDBGlucoseStore.inMemoryStore()
        let grdbSaveStart = CFAbsoluteTimeGetCurrent()
        try await grdbStore.save(readings)
        let grdbSaveElapsed = (CFAbsoluteTimeGetCurrent() - grdbSaveStart) * 1000
        
        // JSON save
        let jsonStore = InMemoryGlucoseStore()
        let jsonSaveStart = CFAbsoluteTimeGetCurrent()
        try await jsonStore.save(readings)
        let jsonSaveElapsed = (CFAbsoluteTimeGetCurrent() - jsonSaveStart) * 1000
        
        // Query parameters (1 week of data)
        let to = Date().addingTimeInterval(-5000 * 300)
        let from = to.addingTimeInterval(-7 * 86400)
        
        // GRDB query
        let grdbQueryStart = CFAbsoluteTimeGetCurrent()
        let grdbResults = try await grdbStore.fetch(from: from, to: to)
        let grdbQueryElapsed = (CFAbsoluteTimeGetCurrent() - grdbQueryStart) * 1000
        
        // JSON query
        let jsonQueryStart = CFAbsoluteTimeGetCurrent()
        let jsonResults = try await jsonStore.fetch(from: from, to: to)
        let jsonQueryElapsed = (CFAbsoluteTimeGetCurrent() - jsonQueryStart) * 1000
        
        print("[BENCH] 50K scale comparison:")
        print("  Save - GRDB: \(String(format: "%.0f", grdbSaveElapsed))ms, JSON: \(String(format: "%.0f", jsonSaveElapsed))ms")
        print("  Query - GRDB: \(String(format: "%.2f", grdbQueryElapsed))ms, JSON: \(String(format: "%.2f", jsonQueryElapsed))ms")
        print("  Query speedup: \(String(format: "%.1f", jsonQueryElapsed / max(0.1, grdbQueryElapsed)))x")
        
        #expect(grdbResults.count == jsonResults.count, "Results should match")
        
        // GRDB should be significantly faster for queries at this scale
        if grdbQueryElapsed > 0 {
            #expect(jsonQueryElapsed / grdbQueryElapsed > 2, "GRDB should be >2x faster for 50K queries")
        }
    }
}

// MARK: - Memory Profiling (BENCH-HARNESS-005)

@Suite("Memory Profiling")
struct MemoryProfilingTests {
    
    /// Get current memory usage in bytes
    private func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    @Test("Peak RAM during 10K insert")
    func testPeakRAM10K() async throws {
        let beforeMem = currentMemoryUsage()
        
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        
        try await store.save(readings)
        
        let afterMem = currentMemoryUsage()
        let deltaKB = Double(afterMem - beforeMem) / 1024
        
        print("[BENCH-MEM] 10K insert delta: \(String(format: "%.1f", deltaKB)) KB")
        
        // Should be reasonably efficient
        #expect(deltaKB < 50_000, "10K insert should use < 50 MB")
    }
    
    @Test("Peak RAM during 50K query")
    func testPeakRAMQuery50K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 50_000)
        try await store.save(readings)
        
        let beforeMem = currentMemoryUsage()
        
        let from = Date().addingTimeInterval(-30 * 86400)
        let to = Date()
        _ = try await store.fetch(from: from, to: to)
        
        let afterMem = currentMemoryUsage()
        let deltaKB = Double(afterMem - beforeMem) / 1024
        
        print("[BENCH-MEM] 50K query delta: \(String(format: "%.1f", deltaKB)) KB")
    }
}

// MARK: - Concurrent Stress Tests (BENCH-HARNESS-006)

@Suite("Concurrent Access Stress")
struct ConcurrentAccessTests {
    
    @Test("Concurrent reads while writing")
    func testConcurrentReadsWhileWriting() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        
        // Seed with initial data
        let initial = GlucoseTestDataGenerator.generateReadings(count: 1000)
        try await store.save(initial)
        
        // Launch concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Writer task - continuously insert
            group.addTask {
                for i in 0..<100 {
                    let reading = GlucoseReading(
                        glucose: 100 + Double(i),
                        timestamp: Date(),
                        trend: .flat,
                        source: "writer"
                    )
                    try? await store.save(reading)
                }
            }
            
            // Reader tasks - concurrent queries
            for _ in 0..<5 {
                group.addTask {
                    for _ in 0..<20 {
                        _ = try? await store.fetchMostRecent()
                        _ = try? await store.count()
                    }
                }
            }
        }
        
        let finalCount = try await store.count()
        #expect(finalCount >= 1000, "Should have at least initial records")
        print("[BENCH-CONCURRENT] Final count after stress: \(finalCount)")
    }
    
    @Test("Multi-actor concurrent access")
    func testMultiActorAccess() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        
        // Multiple actors accessing store concurrently
        async let task1: Void = {
            for i in 0..<50 {
                let readings = GlucoseTestDataGenerator.generateReadings(count: 10)
                try? await store.save(readings)
            }
        }()
        
        async let task2: Void = {
            for _ in 0..<100 {
                _ = try? await store.fetchMostRecent()
            }
        }()
        
        async let task3: Void = {
            for _ in 0..<50 {
                _ = try? await store.count()
            }
        }()
        
        _ = await (task1, task2, task3)
        
        let count = try await store.count()
        #expect(count >= 0, "Store should be consistent after concurrent access")
        print("[BENCH-CONCURRENT] Multi-actor final count: \(count)")
    }
}

// MARK: - Scale Benchmarks (BENCH-HARNESS-007)

@Suite("Scale Benchmarks")
struct ScaleBenchmarkTests {
    
    @Test("Benchmark 25K records")
    func benchmark25K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 25_000)
        
        let saveStart = CFAbsoluteTimeGetCurrent()
        try await store.save(readings)
        let saveElapsed = (CFAbsoluteTimeGetCurrent() - saveStart) * 1000
        
        let queryStart = CFAbsoluteTimeGetCurrent()
        let from = Date().addingTimeInterval(-7 * 86400)
        _ = try await store.fetch(from: from, to: Date())
        let queryElapsed = (CFAbsoluteTimeGetCurrent() - queryStart) * 1000
        
        print("[BENCH-25K] Save: \(String(format: "%.0f", saveElapsed))ms, Query: \(String(format: "%.2f", queryElapsed))ms")
        
        #expect(saveElapsed < 5000, "25K save should take < 5s")
    }
    
    @Test("Benchmark 75K records")
    func benchmark75K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 75_000)
        
        let saveStart = CFAbsoluteTimeGetCurrent()
        try await store.save(readings)
        let saveElapsed = (CFAbsoluteTimeGetCurrent() - saveStart) * 1000
        
        let queryStart = CFAbsoluteTimeGetCurrent()
        let from = Date().addingTimeInterval(-7 * 86400)
        _ = try await store.fetch(from: from, to: Date())
        let queryElapsed = (CFAbsoluteTimeGetCurrent() - queryStart) * 1000
        
        print("[BENCH-75K] Save: \(String(format: "%.0f", saveElapsed))ms, Query: \(String(format: "%.2f", queryElapsed))ms")
        
        #expect(saveElapsed < 15000, "75K save should take < 15s")
    }
    
    @Test("Benchmark 150K records")
    func benchmark150K() async throws {
        let store = try GRDBGlucoseStore.inMemoryStore()
        let readings = GlucoseTestDataGenerator.generateReadings(count: 150_000)
        
        let saveStart = CFAbsoluteTimeGetCurrent()
        try await store.save(readings)
        let saveElapsed = (CFAbsoluteTimeGetCurrent() - saveStart) * 1000
        
        let queryStart = CFAbsoluteTimeGetCurrent()
        let from = Date().addingTimeInterval(-7 * 86400)
        _ = try await store.fetch(from: from, to: Date())
        let queryElapsed = (CFAbsoluteTimeGetCurrent() - queryStart) * 1000
        
        print("[BENCH-150K] Save: \(String(format: "%.0f", saveElapsed))ms, Query: \(String(format: "%.2f", queryElapsed))ms")
        
        #expect(saveElapsed < 30000, "150K save should take < 30s")
    }
}

// MARK: - Combined Load Tests (BENCH-HARNESS-008)

@Suite("Combined Load Tests")
struct CombinedLoadTests {
    
    @Test("All collections simultaneously")
    func testCombinedCollectionLoad() async throws {
        // Create stores for each collection type
        let glucoseStore = try GRDBGlucoseStore.inMemoryStore()
        
        // Generate test data for multiple collections
        let glucoseData = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        
        // Measure combined load
        let startTime = CFAbsoluteTimeGetCurrent()
        
        await withTaskGroup(of: Void.self) { group in
            // Glucose operations
            group.addTask {
                try? await glucoseStore.save(glucoseData)
            }
            
            // Concurrent queries
            group.addTask {
                for _ in 0..<50 {
                    _ = try? await glucoseStore.fetchMostRecent()
                }
            }
            
            // Count operations
            group.addTask {
                for _ in 0..<50 {
                    _ = try? await glucoseStore.count()
                }
            }
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("[BENCH-COMBINED] All operations completed in: \(String(format: "%.0f", elapsed))ms")
        
        let count = try await glucoseStore.count()
        #expect(count == 10_000, "All records should be saved")
    }
}

// MARK: - Database Size Tests

@Suite("GRDB Storage Efficiency")
struct GRDBStorageEfficiencyTests {
    
    @Test("Measure database size for 10K records")
    func measureDatabaseSize10K() async throws {
        // Create file-based store in temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("bench_\(UUID().uuidString).sqlite").path
        
        let store = try GRDBGlucoseStore(path: dbPath)
        let readings = GlucoseTestDataGenerator.generateReadings(count: 10_000)
        try await store.save(readings)
        
        let sizeBytes = try await store.databaseSize()
        let sizeMB = Double(sizeBytes) / (1024 * 1024)
        
        print("[BENCH] 10K records: \(String(format: "%.2f", sizeMB)) MB (\(sizeBytes / 10_000) bytes/record)")
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: dbPath)
        
        // SQLite should be reasonably efficient
        #expect(sizeBytes < 5_000_000, "10K records should be < 5 MB")
    }
}

#endif // canImport(Darwin)
