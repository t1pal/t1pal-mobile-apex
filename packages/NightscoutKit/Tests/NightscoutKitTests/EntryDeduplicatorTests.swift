// EntryDeduplicatorTests.swift
// Tests for EntryDeduplicator
// Trace: NS-UPLOAD-001, PRD-014 REQ-DEDUP-001

import Foundation
import Testing
@testable import NightscoutKit

// MARK: - Test Helpers

private func now() -> Double {
    Date().timeIntervalSince1970 * 1000
}

private func makeEntry(sgv: Int, date: Double, identifier: String? = nil) -> NightscoutEntry {
    NightscoutEntry(
        type: "sgv",
        sgv: sgv,
        direction: "Flat",
        dateString: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: date / 1000)),
        date: date,
        identifier: identifier
    )
}

// MARK: - Basic Deduplication

@Suite("EntryDeduplicator Basic")
struct EntryDeduplicatorBasicTests {
    @Test("Should upload new entry")
    func shouldUploadNewEntry() {
        let deduplicator = EntryDeduplicator()
        let entry = makeEntry(sgv: 120, date: now())
        
        #expect(deduplicator.shouldUpload(entry))
    }
    
    @Test("Should not upload after processed")
    func shouldNotUploadAfterProcessed() {
        let deduplicator = EntryDeduplicator()
        let entry = makeEntry(sgv: 120, date: now())
        
        #expect(deduplicator.shouldUpload(entry))
        deduplicator.markProcessed(entry)
        #expect(!deduplicator.shouldUpload(entry))
    }
    
    @Test("Should not upload duplicate sync ID")
    func shouldNotUploadDuplicateSyncId() {
        let deduplicator = EntryDeduplicator()
        let entry1 = makeEntry(sgv: 120, date: now(), identifier: "t1pal-abc:sgv:12345")
        let entry2 = makeEntry(sgv: 125, date: now(), identifier: "t1pal-abc:sgv:12345")
        
        deduplicator.markProcessed(entry1)
        #expect(!deduplicator.shouldUpload(entry2), "Same sync ID should be duplicate")
    }
}

// MARK: - Similar Entry Detection

@Suite("EntryDeduplicator Similar Detection")
struct EntryDeduplicatorSimilarTests {
    @Test("Should detect similar entry same time window")
    func shouldDetectSimilarEntrySameTimeWindow() {
        let deduplicator = EntryDeduplicator()
        let baseTime = now()
        let entry1 = makeEntry(sgv: 120, date: baseTime, identifier: "id1")
        let entry2 = makeEntry(sgv: 122, date: baseTime + 10_000, identifier: "id2") // +10 seconds, +2 mg/dL
        
        deduplicator.markProcessed(entry1)
        #expect(!deduplicator.shouldUpload(entry2), "Similar time + value should be duplicate")
    }
    
    @Test("Should allow different time window")
    func shouldAllowDifferentTimeWindow() {
        let deduplicator = EntryDeduplicator()
        let baseTime = now()
        let entry1 = makeEntry(sgv: 120, date: baseTime, identifier: "id1")
        let entry2 = makeEntry(sgv: 120, date: baseTime + 60_000, identifier: "id2") // +60 seconds
        
        deduplicator.markProcessed(entry1)
        #expect(deduplicator.shouldUpload(entry2), "Different time window should not be duplicate")
    }
    
    @Test("Should allow different value")
    func shouldAllowDifferentValue() {
        let deduplicator = EntryDeduplicator()
        let baseTime = now()
        let entry1 = makeEntry(sgv: 120, date: baseTime, identifier: "id1")
        let entry2 = makeEntry(sgv: 150, date: baseTime + 5_000, identifier: "id2") // Same time, different value
        
        deduplicator.markProcessed(entry1)
        #expect(deduplicator.shouldUpload(entry2), "Different value should not be duplicate")
    }
}

// MARK: - Batch Processing

@Suite("EntryDeduplicator Batch")
struct EntryDeduplicatorBatchTests {
    @Test("Deduplicate batch")
    func deduplicateBatch() {
        let deduplicator = EntryDeduplicator()
        let entries = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
            makeEntry(sgv: 125, date: now() + 300_000, identifier: "id2"),
            makeEntry(sgv: 120, date: now(), identifier: "id1"), // Duplicate sync ID
        ]
        
        let deduplicated = deduplicator.deduplicate(entries)
        #expect(deduplicated.count == 2)
    }
    
    @Test("Process batch for upload")
    func processBatchForUpload() {
        let deduplicator = EntryDeduplicator()
        let entries = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
            makeEntry(sgv: 125, date: now() + 300_000, identifier: "id2"),
            makeEntry(sgv: 120, date: now(), identifier: "id1"), // Duplicate
        ]
        
        let result = deduplicator.processBatchForUpload(entries)
        #expect(result.uploadCount == 2)
        #expect(result.duplicateCount == 1)
    }
}

// MARK: - Missing Remote/Local

@Suite("EntryDeduplicator Missing")
struct EntryDeduplicatorMissingTests {
    @Test("Find missing remote")
    func findMissingRemote() {
        let deduplicator = EntryDeduplicator()
        let local = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
            makeEntry(sgv: 125, date: now() + 300_000, identifier: "id2"),
            makeEntry(sgv: 130, date: now() + 600_000, identifier: "id3"),
        ]
        let remote = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
        ]
        
        let missing = deduplicator.findMissingRemote(local: local, remote: remote)
        #expect(missing.count == 2)
        #expect(Set(missing.map(\.syncIdentifier)) == Set(["id2", "id3"]))
    }
    
    @Test("Find missing local")
    func findMissingLocal() {
        let deduplicator = EntryDeduplicator()
        let local = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
        ]
        let remote = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
            makeEntry(sgv: 125, date: now() + 300_000, identifier: "id2"),
        ]
        
        let missing = deduplicator.findMissingLocal(local: local, remote: remote)
        #expect(missing.count == 1)
        #expect(missing.first?.syncIdentifier == "id2")
    }
}

// MARK: - Stats

@Suite("EntryDeduplicator Stats")
struct EntryDeduplicatorStatsTests {
    @Test("Stats tracking")
    func statsTracking() {
        let deduplicator = EntryDeduplicator()
        let entries = [
            makeEntry(sgv: 120, date: now(), identifier: "id1"),
            makeEntry(sgv: 125, date: now() + 300_000, identifier: "id2"),
        ]
        
        for entry in entries {
            deduplicator.markProcessed(entry)
        }
        
        let stats = deduplicator.stats
        #expect(stats.processedCount == 2)
        #expect(stats.recentCount == 2)
    }
    
    @Test("Reset")
    func reset() {
        let deduplicator = EntryDeduplicator()
        let entry = makeEntry(sgv: 120, date: now())
        deduplicator.markProcessed(entry)
        
        #expect(!deduplicator.shouldUpload(entry))
        
        deduplicator.reset()
        
        #expect(deduplicator.shouldUpload(entry))
    }
}

// MARK: - Tolerances

@Suite("EntryDeduplicator Tolerances")
struct EntryDeduplicatorToleranceTests {
    @Test("30-second tolerance window (REQ-DEDUP-003)")
    func toleranceWindowExactly30Seconds() {
        let deduplicator = EntryDeduplicator()
        let baseTime = now()
        let entry1 = makeEntry(sgv: 120, date: baseTime, identifier: "id1")
        
        // Entry at exactly 30 seconds should still be considered duplicate
        let entryAt30s = makeEntry(sgv: 122, date: baseTime + 30_000, identifier: "id2")
        
        // Entry at 31 seconds should NOT be duplicate
        let entryAt31s = makeEntry(sgv: 122, date: baseTime + 31_000, identifier: "id3")
        
        deduplicator.markProcessed(entry1)
        
        #expect(!deduplicator.shouldUpload(entryAt30s), "Entry at exactly 30s should be duplicate")
        #expect(deduplicator.shouldUpload(entryAt31s), "Entry at 31s should not be duplicate")
    }
    
    @Test("Value tolerance within 5 mg/dL")
    func valueToleranceWithin5mgdL() {
        let deduplicator = EntryDeduplicator()
        let baseTime = now()
        let entry1 = makeEntry(sgv: 120, date: baseTime, identifier: "id1")
        
        // Entry with +5 mg/dL should be duplicate
        let entryPlus5 = makeEntry(sgv: 125, date: baseTime + 5_000, identifier: "id2")
        
        // Entry with +6 mg/dL should NOT be duplicate
        let entryPlus6 = makeEntry(sgv: 126, date: baseTime + 5_000, identifier: "id3")
        
        deduplicator.markProcessed(entry1)
        
        #expect(!deduplicator.shouldUpload(entryPlus5), "Entry with +5 mg/dL should be duplicate")
        #expect(deduplicator.shouldUpload(entryPlus6), "Entry with +6 mg/dL should not be duplicate")
    }
}

// MARK: - SyncUploader Integration Tests
// Note: Full integration tests for SyncUploader require MockNightscoutServer
// See MockNightscoutServerTests.swift for the integration test pattern
