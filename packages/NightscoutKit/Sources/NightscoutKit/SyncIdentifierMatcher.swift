// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SyncIdentifierMatcher.swift - Entry sync identifier matching for deduplication
// Part of NightscoutKit
// Trace: NS-COMPAT-009

import Foundation

// MARK: - Sync Identifier Matcher

/// Matches entries by sync identifier for deduplication
/// Supports Loop, Trio, xDrip+, and T1Pal identifier patterns
public final class SyncIdentifierMatcher: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = SyncIdentifierMatcher()
    
    private init() {}
    
    // MARK: - Matching
    
    /// Check if two entries match by sync identifier
    public func entriesMatch(_ entry1: NightscoutEntry, _ entry2: NightscoutEntry) -> Bool {
        entry1.syncIdentifier == entry2.syncIdentifier
    }
    
    /// Check if two treatments match by sync identifier
    public func treatmentsMatch(_ t1: NightscoutTreatment, _ t2: NightscoutTreatment) -> Bool {
        t1.syncIdentifier == t2.syncIdentifier
    }
    
    /// Find matching entry in array
    public func findMatch(for entry: NightscoutEntry, in entries: [NightscoutEntry]) -> NightscoutEntry? {
        let targetId = entry.syncIdentifier
        return entries.first { $0.syncIdentifier == targetId }
    }
    
    /// Find matching treatment in array
    public func findMatch(for treatment: NightscoutTreatment, in treatments: [NightscoutTreatment]) -> NightscoutTreatment? {
        let targetId = treatment.syncIdentifier
        return treatments.first { $0.syncIdentifier == targetId }
    }
    
    /// Deduplicate entries by sync identifier
    public func deduplicate(_ entries: [NightscoutEntry]) -> [NightscoutEntry] {
        var seen = Set<String>()
        var unique: [NightscoutEntry] = []
        
        for entry in entries {
            let id = entry.syncIdentifier
            if !seen.contains(id) {
                seen.insert(id)
                unique.append(entry)
            }
        }
        
        return unique
    }
    
    /// Deduplicate treatments by sync identifier
    public func deduplicate(_ treatments: [NightscoutTreatment]) -> [NightscoutTreatment] {
        var seen = Set<String>()
        var unique: [NightscoutTreatment] = []
        
        for treatment in treatments {
            let id = treatment.syncIdentifier
            if !seen.contains(id) {
                seen.insert(id)
                unique.append(treatment)
            }
        }
        
        return unique
    }
    
    // MARK: - Pattern Detection
    
    /// Detect the source app from a sync identifier
    public func detectSource(from syncId: String) -> DataSource {
        let lowerId = syncId.lowercased()
        
        if lowerId.hasPrefix("loop:") || lowerId.contains("loopkit") {
            return .loop
        }
        if lowerId.hasPrefix("trio:") || lowerId.contains("freeaps") {
            return .trio
        }
        if lowerId.hasPrefix("xdrip") || lowerId.contains("xdrip") {
            return .xdrip
        }
        if lowerId.hasPrefix("t1pal:") || lowerId.contains("t1pal") {
            return .t1pal
        }
        if lowerId.hasPrefix("aaps:") || lowerId.contains("androidaps") {
            return .aaps
        }
        
        return .unknown
    }
    
    /// Parse timestamp from sync identifier if present
    public func parseTimestamp(from syncId: String) -> Date? {
        // Pattern: "device:type:timestamp" where timestamp is Unix ms
        let parts = syncId.split(separator: ":")
        guard parts.count >= 3,
              let timestampStr = parts.last,
              let timestamp = Int64(timestampStr) else {
            return nil
        }
        
        // Handle both seconds and milliseconds
        if timestamp > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000)
        } else {
            return Date(timeIntervalSince1970: Double(timestamp))
        }
    }
    
    /// Known data sources
    public enum DataSource: String, Sendable {
        case loop = "Loop"
        case trio = "Trio"
        case xdrip = "xDrip+"
        case t1pal = "T1Pal"
        case aaps = "AndroidAPS"
        case unknown = "Unknown"
    }
}

// MARK: - Merge Utilities

extension SyncIdentifierMatcher {
    
    /// Merge two entry arrays, deduplicating by sync identifier
    /// Later entries take precedence (assumed to be updates)
    public func merge(_ existing: [NightscoutEntry], with new: [NightscoutEntry]) -> [NightscoutEntry] {
        var byId: [String: NightscoutEntry] = [:]
        
        // Add existing entries
        for entry in existing {
            byId[entry.syncIdentifier] = entry
        }
        
        // Override with new entries
        for entry in new {
            byId[entry.syncIdentifier] = entry
        }
        
        // Sort by date
        return byId.values.sorted { $0.date > $1.date }
    }
    
    /// Find entries in new that don't exist in existing
    public func findNew(existing: [NightscoutEntry], new: [NightscoutEntry]) -> [NightscoutEntry] {
        let existingIds = Set(existing.map(\.syncIdentifier))
        return new.filter { !existingIds.contains($0.syncIdentifier) }
    }
    
    /// Find entries that exist in both arrays (by sync identifier)
    public func findCommon(existing: [NightscoutEntry], new: [NightscoutEntry]) -> [(NightscoutEntry, NightscoutEntry)] {
        let newById = Dictionary(uniqueKeysWithValues: new.map { ($0.syncIdentifier, $0) })
        
        return existing.compactMap { existingEntry in
            if let newEntry = newById[existingEntry.syncIdentifier] {
                return (existingEntry, newEntry)
            }
            return nil
        }
    }
}

// MARK: - Statistics

extension SyncIdentifierMatcher {
    
    /// Analyze entries to determine source distribution
    public func analyzeSourceDistribution(_ entries: [NightscoutEntry]) -> [DataSource: Int] {
        var counts: [DataSource: Int] = [:]
        
        for entry in entries {
            let source = detectSource(from: entry.syncIdentifier)
            counts[source, default: 0] += 1
        }
        
        return counts
    }
    
    /// Find duplicate entries (same sync identifier)
    public func findDuplicates(_ entries: [NightscoutEntry]) -> [[NightscoutEntry]] {
        var byId: [String: [NightscoutEntry]] = [:]
        
        for entry in entries {
            byId[entry.syncIdentifier, default: []].append(entry)
        }
        
        return byId.values.filter { $0.count > 1 }
    }
}
