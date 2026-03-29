// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// EntryDeduplicator.swift - Entry deduplication for Nightscout sync
// Part of NightscoutKit
// Trace: PRD-014 REQ-DEDUP-001

import Foundation

// MARK: - Entry Deduplicator

/// Deduplicates entries during Nightscout sync
/// Prevents duplicate glucose readings when colocated with Loop/Trio
public final class EntryDeduplicator: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = EntryDeduplicator()
    
    private let lock = NSLock()
    private var processedIds: Set<String> = []
    private var recentEntries: [RecentEntry] = []
    
    /// How long to track recent entries (1 hour)
    public var trackingWindow: TimeInterval = 3600
    
    /// Tolerance for matching timestamps (30 seconds per REQ-DEDUP-003)
    public var timestampTolerance: TimeInterval = 30
    
    /// Tolerance for matching glucose values (5 mg/dL)
    public var valueTolerance: Double = 5.0
    
    /// Internal init for testing via @testable import
    internal init() {}
    
    // MARK: - Deduplication
    
    /// Check if entry should be uploaded (not a duplicate)
    public func shouldUpload(_ entry: NightscoutEntry) -> Bool {
        let syncId = entry.syncIdentifier
        
        return lock.withLock {
            // Already processed this exact ID
            if processedIds.contains(syncId) {
                return false
            }
            
            // Check for similar recent entry
            if findSimilarEntry(entry) != nil {
                return false
            }
            
            return true
        }
    }
    
    /// Mark entry as processed
    public func markProcessed(_ entry: NightscoutEntry) {
        lock.withLock {
            processedIds.insert(entry.syncIdentifier)
            
            // Track as recent (entry.date is in milliseconds)
            let recent = RecentEntry(
                syncId: entry.syncIdentifier,
                timestamp: Date(timeIntervalSince1970: entry.date / 1000),
                sgv: entry.sgv,
                processedAt: Date()
            )
            recentEntries.append(recent)
            
            // Prune old entries
            pruneOldEntries()
        }
    }
    
    /// Deduplicate an array of entries
    public func deduplicate(_ entries: [NightscoutEntry]) -> [NightscoutEntry] {
        var unique: [NightscoutEntry] = []
        var seenIds = Set<String>()
        
        for entry in entries {
            let syncId = entry.syncIdentifier
            if !seenIds.contains(syncId) && shouldUpload(entry) {
                seenIds.insert(syncId)
                unique.append(entry)
            }
        }
        
        return unique
    }
    
    /// Find entries that exist locally but not remotely
    public func findMissingRemote(
        local: [NightscoutEntry],
        remote: [NightscoutEntry]
    ) -> [NightscoutEntry] {
        let remoteIds = Set(remote.map(\.syncIdentifier))
        return local.filter { !remoteIds.contains($0.syncIdentifier) }
    }
    
    /// Find entries that exist remotely but not locally
    public func findMissingLocal(
        local: [NightscoutEntry],
        remote: [NightscoutEntry]
    ) -> [NightscoutEntry] {
        let localIds = Set(local.map(\.syncIdentifier))
        return remote.filter { !localIds.contains($0.syncIdentifier) }
    }
    
    // MARK: - Similar Entry Detection
    
    private func findSimilarEntry(_ entry: NightscoutEntry) -> RecentEntry? {
        let targetTime = Date(timeIntervalSince1970: entry.date / 1000)
        
        for recent in recentEntries {
            // Similar timestamp (within tolerance per REQ-DEDUP-003)
            let timeDiff = abs(recent.timestamp.timeIntervalSince(targetTime))
            guard timeDiff <= timestampTolerance else { continue }
            
            // Similar glucose value (within tolerance)
            if let recentSgv = recent.sgv, let entrySgv = entry.sgv {
                if abs(Double(recentSgv) - Double(entrySgv)) <= valueTolerance {
                    return recent
                }
            }
            
            // If no SGV to compare but timestamp matches, treat as duplicate
            if recent.sgv == nil && entry.sgv == nil {
                return recent
            }
        }
        
        return nil
    }
    
    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-trackingWindow)
        recentEntries.removeAll { $0.processedAt < cutoff }
        
        // Limit processed IDs to prevent unbounded growth
        if processedIds.count > 10000 {
            processedIds.removeAll()
        }
    }
    
    // MARK: - Reset
    
    /// Clear all tracking data
    public func reset() {
        lock.withLock {
            processedIds.removeAll()
            recentEntries.removeAll()
        }
    }
    
    /// Get stats for debugging
    public var stats: EntryDeduplicationStats {
        lock.withLock {
            EntryDeduplicationStats(
                processedCount: processedIds.count,
                recentCount: recentEntries.count
            )
        }
    }
}

// MARK: - Supporting Types

private struct RecentEntry {
    let syncId: String
    let timestamp: Date
    let sgv: Int?
    let processedAt: Date
}

public struct EntryDeduplicationStats: Sendable {
    public let processedCount: Int
    public let recentCount: Int
}

// MARK: - Batch Processing

extension EntryDeduplicator {
    
    /// Process a batch of entries for upload
    /// Returns only entries that should be uploaded
    public func processBatchForUpload(_ entries: [NightscoutEntry]) -> BatchResult {
        var toUpload: [NightscoutEntry] = []
        var duplicates: [NightscoutEntry] = []
        
        for entry in entries {
            if shouldUpload(entry) {
                toUpload.append(entry)
                markProcessed(entry)
            } else {
                duplicates.append(entry)
            }
        }
        
        return BatchResult(toUpload: toUpload, duplicates: duplicates)
    }
    
    public struct BatchResult {
        public let toUpload: [NightscoutEntry]
        public let duplicates: [NightscoutEntry]
        
        public var uploadCount: Int { toUpload.count }
        public var duplicateCount: Int { duplicates.count }
    }
}

// MARK: - Remote Query

extension EntryDeduplicator {
    
    /// Check remote Nightscout for existing entries within window
    /// Per REQ-DEDUP-003: Query existing entries within ±30s window before uploading
    public func findRemoteDuplicates(
        for entries: [NightscoutEntry],
        using client: NightscoutClient
    ) async throws -> [NightscoutEntry] {
        guard !entries.isEmpty else { return [] }
        
        // Find time range of entries to check (entry.date is in ms)
        let dates = entries.map { Date(timeIntervalSince1970: $0.date / 1000) }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return [] }
        
        // Expand window by tolerance on each side
        let queryFrom = minDate.addingTimeInterval(-timestampTolerance)
        let queryTo = maxDate.addingTimeInterval(timestampTolerance)
        
        // Fetch remote entries in window
        let remote = try await client.fetchEntries(from: queryFrom, to: queryTo)
        
        // Find which local entries have duplicates
        let remoteSyncIds = Set(remote.map(\.syncIdentifier))
        
        return entries.filter { entry in
            // Exact match by syncIdentifier
            if remoteSyncIds.contains(entry.syncIdentifier) {
                return true
            }
            
            // Fuzzy match: same time window and similar value
            for remoteEntry in remote {
                let entryDate = Date(timeIntervalSince1970: entry.date / 1000)
                let remoteDate = Date(timeIntervalSince1970: remoteEntry.date / 1000)
                let timeDiff = abs(entryDate.timeIntervalSince(remoteDate))
                if timeDiff <= timestampTolerance,
                   let localSgv = entry.sgv,
                   let remoteSgv = remoteEntry.sgv,
                   abs(Double(localSgv) - Double(remoteSgv)) <= valueTolerance {
                    return true
                }
            }
            
            return false
        }
    }
}
