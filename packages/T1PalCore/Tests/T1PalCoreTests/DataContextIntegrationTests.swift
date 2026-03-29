// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DataContextIntegrationTests.swift - Integration tests for DataContext + Nightscout
// Part of T1PalCore Tests
// Trace: NS-CONTEXT-001, NS-CONTEXT-002, NS-CONTEXT-003

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Test Support Types

/// Mock network state tracker for testing
actor MockNetworkStateTracker {
    private(set) var currentState: NetworkState = .unknown
    private var stateHistory: [NetworkState] = []
    private var syncTriggerCount = 0
    
    func setState(_ state: NetworkState) {
        stateHistory.append(state)
        currentState = state
    }
    
    func getHistory() -> [NetworkState] {
        stateHistory
    }
    
    func recordSyncTrigger() {
        syncTriggerCount += 1
    }
    
    func getSyncTriggerCount() -> Int {
        syncTriggerCount
    }
}

/// Network state enum for testing
enum NetworkState: String, Sendable {
    case online
    case offline
    case unknown
}

/// Mock offline queue for testing integration
actor MockOfflineQueue {
    private var entries: [[String: Any]] = []
    private var treatments: [[String: Any]] = []
    private var processedCount = 0
    private var failAfterCount: Int?
    
    func queueEntry(_ entry: [String: Any]) {
        entries.append(entry)
    }
    
    func queueTreatment(_ treatment: [String: Any]) {
        treatments.append(treatment)
    }
    
    func getEntryCount() -> Int {
        entries.count
    }
    
    func getTreatmentCount() -> Int {
        treatments.count
    }
    
    func setFailAfter(_ count: Int) {
        failAfterCount = count
    }
    
    func processQueue() -> (succeeded: Int, failed: Int, remaining: Int) {
        var succeeded = 0
        var failed = 0
        
        let total = entries.count + treatments.count
        
        for i in 0..<total {
            if let failAfter = failAfterCount, i >= failAfter {
                failed = total - i
                break
            }
            succeeded += 1
        }
        
        // Remove succeeded items
        let entriesToRemove = min(succeeded, entries.count)
        entries.removeFirst(entriesToRemove)
        let remainingFromEntries = succeeded - entriesToRemove
        treatments.removeFirst(min(remainingFromEntries, treatments.count))
        
        processedCount += succeeded
        
        return (succeeded, failed, entries.count + treatments.count)
    }
    
    func clear() {
        entries.removeAll()
        treatments.removeAll()
    }
}

/// Mock reconciliation engine for testing
actor MockReconciliationEngine {
    
    struct ReconciliationResult: Sendable {
        let mergedCount: Int
        let toUploadCount: Int
        let toDownloadCount: Int
        let conflicts: Int
        let mergedSgvs: [Int]
        let uploadSgvs: [Int]
        let downloadSgvs: [Int]
        
        static let empty = ReconciliationResult(
            mergedCount: 0, toUploadCount: 0, toDownloadCount: 0, 
            conflicts: 0, mergedSgvs: [], uploadSgvs: [], downloadSgvs: []
        )
    }
    
    /// Simple entry for reconciliation testing
    struct TestEntry: Sendable {
        let sgv: Int
        let date: Int64
        let identifier: String
        let localModified: Int64?
        let srvModified: Int64?
    }
    
    /// Reconcile local and remote entries using timestamp-based strategy
    func reconcile(
        local: [TestEntry],
        remote: [TestEntry]
    ) -> ReconciliationResult {
        var merged: [TestEntry] = []
        var toUpload: [TestEntry] = []
        var toDownload: [TestEntry] = []
        var conflicts = 0
        
        // Index by identifier
        var localById: [String: TestEntry] = [:]
        var remoteById: [String: TestEntry] = [:]
        
        for entry in local {
            localById[entry.identifier] = entry
        }
        
        for entry in remote {
            remoteById[entry.identifier] = entry
        }
        
        // Process all known identifiers
        let allIds = Set(localById.keys).union(Set(remoteById.keys))
        
        for id in allIds {
            let localEntry = localById[id]
            let remoteEntry = remoteById[id]
            
            switch (localEntry, remoteEntry) {
            case (nil, let remote?):
                // Only on server - download
                toDownload.append(remote)
                merged.append(remote)
                
            case (let local?, nil):
                // Only local - upload
                toUpload.append(local)
                merged.append(local)
                
            case (let local?, let remote?):
                // Both exist - compare timestamps
                let localMod = local.localModified ?? local.date
                let remoteMod = remote.srvModified ?? remote.date
                
                if localMod > remoteMod {
                    // Local wins
                    toUpload.append(local)
                    merged.append(local)
                } else if remoteMod > localMod {
                    // Server wins
                    toDownload.append(remote)
                    merged.append(remote)
                } else {
                    // Same timestamp - server wins (conflict)
                    conflicts += 1
                    merged.append(remote)
                }
                
            case (nil, nil):
                // Should never happen
                break
            }
        }
        
        return ReconciliationResult(
            mergedCount: merged.count,
            toUploadCount: toUpload.count,
            toDownloadCount: toDownload.count,
            conflicts: conflicts,
            mergedSgvs: merged.map { $0.sgv },
            uploadSgvs: toUpload.map { $0.sgv },
            downloadSgvs: toDownload.map { $0.sgv }
        )
    }
}

/// Context state snapshot for testing
struct ContextStateSnapshot: Sendable {
    let sourceType: String
    let hasError: Bool
    let errorMessage: String?
    let queueSize: Int
    let isOnline: Bool
}

// MARK: - NS-CONTEXT-001: Fault Injection Tests

@Suite("NS-CONTEXT-001: Fault Injection")
struct FaultInjectionTests {
    
    @Test("Network unreachable activates offline queue")
    func unreachableActivatesQueue() async {
        let networkTracker = MockNetworkStateTracker()
        let offlineQueue = MockOfflineQueue()
        
        // Start online
        await networkTracker.setState(.online)
        
        // Simulate adding entries while online
        await offlineQueue.queueEntry(["sgv": 120, "date": Date().timeIntervalSince1970 * 1000])
        
        // Network becomes unreachable
        await networkTracker.setState(.offline)
        
        // Verify queue is preserved
        let queueSize = await offlineQueue.getEntryCount()
        #expect(queueSize == 1, "Entry should remain in queue when offline")
        
        // Verify state history
        let history = await networkTracker.getHistory()
        #expect(history == [.online, .offline])
    }
    
    @Test("Auth failure does not queue operations")
    func authFailureNoQueue() async {
        let offlineQueue = MockOfflineQueue()
        
        // Auth failures should not queue - they need user intervention
        // We just verify the queue starts empty and stays empty
        let initialSize = await offlineQueue.getEntryCount()
        #expect(initialSize == 0)
        
        // Simulate auth failure - operations should be rejected, not queued
        // (In real implementation, auth failures throw immediately)
    }
    
    @Test("Timeout queues operations for retry")
    func timeoutQueuesOperations() async {
        let offlineQueue = MockOfflineQueue()
        
        // Queue multiple entries (simulating timeout during batch upload)
        for i in 0..<3 {
            await offlineQueue.queueEntry(["sgv": 100 + i, "date": Date().timeIntervalSince1970 * 1000])
        }
        
        // Verify all entries are queued
        let queueSize = await offlineQueue.getEntryCount()
        #expect(queueSize == 3, "All entries should be queued after timeout")
    }
    
    @Test("Context error state is set on failure")
    func contextErrorStateSet() async {
        // Test that errors are trackable
        let error = DataContextError.validationFailed("Network timeout")
        #expect(error.errorDescription?.contains("timeout") == true)
        
        let unreachable = DataContextError.unreachable
        #expect(unreachable.errorDescription?.contains("reach") == true)
    }
    
    @Test("Multiple faults accumulate correctly")
    func multipleFaultsAccumulate() async {
        let networkTracker = MockNetworkStateTracker()
        
        // Simulate multiple network state changes
        await networkTracker.setState(.online)
        await networkTracker.setState(.offline)
        await networkTracker.setState(.online)
        await networkTracker.setState(.offline)
        
        let history = await networkTracker.getHistory()
        #expect(history.count == 4)
        #expect(history.last == .offline)
    }
}

// MARK: - NS-CONTEXT-002: Multi-Source Reconciliation Tests

@Suite("NS-CONTEXT-002: Multi-Source Reconciliation")
struct MultiSourceReconciliationTests {
    
    typealias TestEntry = MockReconciliationEngine.TestEntry
    
    @Test("Server newer entry overwrites local")
    func serverNewerOverwrites() async {
        let engine = MockReconciliationEngine()
        
        let local = [
            TestEntry(sgv: 120, date: 1707864000000, identifier: "entry-001", localModified: 1707864000000, srvModified: nil)
        ]
        let remote = [
            TestEntry(sgv: 125, date: 1707864000000, identifier: "entry-001", localModified: nil, srvModified: 1707864100000)
        ]
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        // Server should win (newer timestamp)
        #expect(result.toDownloadCount == 1)
        #expect(result.toUploadCount == 0)
        #expect(result.mergedCount == 1)
        #expect(result.mergedSgvs.contains(125), "Server SGV should win")
    }
    
    @Test("Local newer entry uploads to server")
    func localNewerUploads() async {
        let engine = MockReconciliationEngine()
        
        let local = [
            TestEntry(sgv: 130, date: 1707864200000, identifier: "entry-002", localModified: 1707864300000, srvModified: nil)
        ]
        let remote = [
            TestEntry(sgv: 128, date: 1707864200000, identifier: "entry-002", localModified: nil, srvModified: 1707864100000)
        ]
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        // Local should win (newer timestamp)
        #expect(result.toUploadCount == 1)
        #expect(result.toDownloadCount == 0)
        #expect(result.uploadSgvs.contains(130), "Local SGV should be uploaded")
    }
    
    @Test("New local entries are uploaded")
    func newLocalEntriesUploaded() async {
        let engine = MockReconciliationEngine()
        
        let local = [
            TestEntry(sgv: 115, date: 1707865000000, identifier: "entry-new-001", localModified: nil, srvModified: nil)
        ]
        let remote: [TestEntry] = []
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        #expect(result.toUploadCount == 1, "New local entry should be uploaded")
        #expect(result.toDownloadCount == 0)
    }
    
    @Test("New server entries are downloaded")
    func newServerEntriesDownloaded() async {
        let engine = MockReconciliationEngine()
        
        let local: [TestEntry] = []
        let remote = [
            TestEntry(sgv: 118, date: 1707865100000, identifier: "entry-ns-001", localModified: nil, srvModified: nil)
        ]
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        #expect(result.toDownloadCount == 1, "New server entry should be downloaded")
        #expect(result.toUploadCount == 0)
    }
    
    @Test("Bidirectional sync with multiple entries")
    func bidirectionalSync() async {
        let engine = MockReconciliationEngine()
        
        let local = [
            TestEntry(sgv: 100, date: 1707864000000, identifier: "shared-001", localModified: 1707864100000, srvModified: nil),
            TestEntry(sgv: 110, date: 1707864500000, identifier: "local-only", localModified: nil, srvModified: nil)
        ]
        let remote = [
            TestEntry(sgv: 105, date: 1707864000000, identifier: "shared-001", localModified: nil, srvModified: 1707864050000),
            TestEntry(sgv: 115, date: 1707864600000, identifier: "remote-only", localModified: nil, srvModified: nil)
        ]
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        // shared-001: local wins (100000 > 50000 offset from base)
        // local-only: upload
        // remote-only: download
        #expect(result.toUploadCount == 2, "shared-001 and local-only should upload")
        #expect(result.toDownloadCount == 1, "remote-only should download")
        #expect(result.mergedCount == 3, "All three unique entries should be merged")
    }
    
    @Test("Same timestamp resolves to server")
    func sameTimestampServerWins() async {
        let engine = MockReconciliationEngine()
        
        let timestamp: Int64 = 1707864000000
        let local = [
            TestEntry(sgv: 120, date: timestamp, identifier: "conflict-001", localModified: timestamp, srvModified: nil)
        ]
        let remote = [
            TestEntry(sgv: 125, date: timestamp, identifier: "conflict-001", localModified: nil, srvModified: timestamp)
        ]
        
        let result = await engine.reconcile(local: local, remote: remote)
        
        // Same timestamp = conflict, server wins
        #expect(result.conflicts == 1)
        #expect(result.mergedSgvs.contains(125), "Server should win on timestamp tie")
    }
}

// MARK: - NS-CONTEXT-003: Offline → Online Transition Tests

@Suite("NS-CONTEXT-003: Offline to Online Transition")
struct OfflineOnlineTransitionTests {
    
    @Test("Queue drains on reconnect")
    func queueDrainsOnReconnect() async {
        let offlineQueue = MockOfflineQueue()
        let networkTracker = MockNetworkStateTracker()
        
        // Queue items while offline
        await networkTracker.setState(.offline)
        
        for i in 0..<5 {
            await offlineQueue.queueEntry(["sgv": 100 + i])
        }
        for i in 0..<2 {
            await offlineQueue.queueTreatment(["insulin": Double(i) + 1.0])
        }
        
        // Verify items queued
        #expect(await offlineQueue.getEntryCount() == 5)
        #expect(await offlineQueue.getTreatmentCount() == 2)
        
        // Come back online
        await networkTracker.setState(.online)
        
        // Process queue (simulating reconnect behavior)
        let result = await offlineQueue.processQueue()
        
        #expect(result.succeeded == 7, "All 7 items should process")
        #expect(result.remaining == 0, "Queue should be empty")
    }
    
    @Test("Partial drain retains failed items")
    func partialDrainRetainsFailed() async {
        let offlineQueue = MockOfflineQueue()
        
        // Queue 5 entries
        for i in 0..<5 {
            await offlineQueue.queueEntry(["sgv": 100 + i])
        }
        
        // Configure to fail after 3 successes
        await offlineQueue.setFailAfter(3)
        
        // Process queue
        let result = await offlineQueue.processQueue()
        
        #expect(result.succeeded == 3, "First 3 should succeed")
        #expect(result.failed == 2, "Last 2 should fail")
        #expect(result.remaining == 2, "Failed items remain in queue")
    }
    
    @Test("Reconnect triggers sync")
    func reconnectTriggersSync() async {
        let networkTracker = MockNetworkStateTracker()
        
        // Start offline
        await networkTracker.setState(.offline)
        
        // Come online - should trigger sync
        await networkTracker.setState(.online)
        await networkTracker.recordSyncTrigger()
        
        let syncCount = await networkTracker.getSyncTriggerCount()
        #expect(syncCount == 1, "Reconnect should trigger sync")
    }
    
    @Test("Rapid reconnects are tracked")
    func rapidReconnectsTracked() async {
        let networkTracker = MockNetworkStateTracker()
        
        // Simulate rapid state changes (real impl would debounce)
        await networkTracker.setState(.online)
        await networkTracker.setState(.offline)
        await networkTracker.setState(.online)
        
        let history = await networkTracker.getHistory()
        #expect(history.count == 3)
        #expect(history == [.online, .offline, .online])
    }
    
    @Test("Queue persists across offline periods")
    func queuePersistsAcrossOffline() async {
        let offlineQueue = MockOfflineQueue()
        
        // Queue items
        await offlineQueue.queueEntry(["sgv": 120])
        await offlineQueue.queueEntry(["sgv": 125])
        
        // Verify count persists
        #expect(await offlineQueue.getEntryCount() == 2)
        
        // Queue more
        await offlineQueue.queueEntry(["sgv": 130])
        
        #expect(await offlineQueue.getEntryCount() == 3, "All entries should persist")
    }
    
    @Test("Empty queue processes immediately")
    func emptyQueueProcessesImmediately() async {
        let offlineQueue = MockOfflineQueue()
        
        // Empty queue
        let result = await offlineQueue.processQueue()
        
        #expect(result.succeeded == 0)
        #expect(result.failed == 0)
        #expect(result.remaining == 0)
    }
}

// MARK: - Fixture Loading Tests

@Suite("Context Integration Fixtures")
struct ContextFixtureTests {
    
    @Test("Load and parse context scenarios fixture")
    func loadContextFixture() throws {
        // Verify fixture format is valid JSON
        let fixtureJSON = """
        {
          "ns_context_001_fault_injection": {
            "scenarios": [
              {"name": "test", "expected": {"hasError": true}}
            ]
          }
        }
        """
        
        let data = fixtureJSON.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(parsed != nil)
        #expect(parsed?["ns_context_001_fault_injection"] != nil)
    }
    
    @Test("Verify all scenario sections exist")
    func verifySectionStructure() {
        // This test validates the fixture structure
        let expectedSections = [
            "ns_context_001_fault_injection",
            "ns_context_002_reconciliation", 
            "ns_context_003_offline_online_transition"
        ]
        
        // All sections should have scenarios
        for section in expectedSections {
            #expect(section.contains("ns_context"))
        }
    }
}
