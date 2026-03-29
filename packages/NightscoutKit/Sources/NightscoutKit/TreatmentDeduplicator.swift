// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// TreatmentDeduplicator.swift - Treatment deduplication for Nightscout sync
// Part of NightscoutKit
// Trace: NS-COMPAT-010

import Foundation

// MARK: - Treatment Deduplicator

/// Deduplicates treatments during Nightscout sync
/// Prevents duplicate insulin doses, carb entries, and other treatments
public final class TreatmentDeduplicator: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = TreatmentDeduplicator()
    
    private let lock = NSLock()
    private var processedIds: Set<String> = []
    private var recentTreatments: [RecentTreatment] = []
    
    /// How long to track recent treatments (2 hours)
    public var trackingWindow: TimeInterval = 7200
    
    /// Tolerance for matching timestamps (5 seconds)
    public var timestampTolerance: TimeInterval = 5
    
    /// Tolerance for matching values (0.1 units / 1 gram)
    public var valueTolerance: Double = 0.1
    
    /// Internal init for testing via @testable import
    internal init() {}
    
    // MARK: - Deduplication
    
    /// Check if treatment should be uploaded (not a duplicate)
    public func shouldUpload(_ treatment: NightscoutTreatment) -> Bool {
        let syncId = treatment.syncIdentifier
        
        return lock.withLock {
            // Already processed this exact ID
            if processedIds.contains(syncId) {
                return false
            }
            
            // Check for similar recent treatment
            if findSimilarTreatment(treatment) != nil {
                return false
            }
            
            return true
        }
    }
    
    /// Mark treatment as processed
    public func markProcessed(_ treatment: NightscoutTreatment) {
        lock.withLock {
            processedIds.insert(treatment.syncIdentifier)
            
            // Track as recent
            let recent = RecentTreatment(
                syncId: treatment.syncIdentifier,
                eventType: treatment.eventType,
                timestamp: ISO8601DateFormatter().date(from: treatment.created_at) ?? Date(),
                insulinValue: treatment.insulin,
                carbsValue: treatment.carbs.flatMap { Double($0) },
                processedAt: Date()
            )
            recentTreatments.append(recent)
            
            // Prune old entries
            pruneOldEntries()
        }
    }
    
    /// Deduplicate an array of treatments
    public func deduplicate(_ treatments: [NightscoutTreatment]) -> [NightscoutTreatment] {
        var unique: [NightscoutTreatment] = []
        var seenIds = Set<String>()
        
        for treatment in treatments {
            let syncId = treatment.syncIdentifier
            if !seenIds.contains(syncId) && shouldUpload(treatment) {
                seenIds.insert(syncId)
                unique.append(treatment)
            }
        }
        
        return unique
    }
    
    /// Find treatments that exist locally but not remotely
    public func findMissingRemote(
        local: [NightscoutTreatment],
        remote: [NightscoutTreatment]
    ) -> [NightscoutTreatment] {
        let remoteIds = Set(remote.map(\.syncIdentifier))
        return local.filter { !remoteIds.contains($0.syncIdentifier) }
    }
    
    /// Find treatments that exist remotely but not locally
    public func findMissingLocal(
        local: [NightscoutTreatment],
        remote: [NightscoutTreatment]
    ) -> [NightscoutTreatment] {
        let localIds = Set(local.map(\.syncIdentifier))
        return remote.filter { !localIds.contains($0.syncIdentifier) }
    }
    
    // MARK: - Similar Treatment Detection
    
    private func findSimilarTreatment(_ treatment: NightscoutTreatment) -> RecentTreatment? {
        let targetTime = ISO8601DateFormatter().date(from: treatment.created_at) ?? Date()
        
        for recent in recentTreatments {
            // Same event type
            guard recent.eventType == treatment.eventType else { continue }
            
            // Similar timestamp
            let timeDiff = abs(recent.timestamp.timeIntervalSince(targetTime))
            guard timeDiff <= timestampTolerance else { continue }
            
            // Similar values (if applicable)
            if let recentInsulin = recent.insulinValue,
               let treatmentInsulin = treatment.insulin {
                if abs(recentInsulin - treatmentInsulin) <= valueTolerance {
                    return recent
                }
            }
            
            if let recentCarbs = recent.carbsValue,
               let treatmentCarbs = treatment.carbs.flatMap({ Double($0) }) {
                if abs(recentCarbs - treatmentCarbs) <= 1.0 { // 1g tolerance for carbs
                    return recent
                }
            }
            
            // If no values to compare, time + type match is enough
            if recent.insulinValue == nil && treatment.insulin == nil &&
               recent.carbsValue == nil && treatment.carbs == nil {
                return recent
            }
        }
        
        return nil
    }
    
    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-trackingWindow)
        recentTreatments.removeAll { $0.processedAt < cutoff }
        
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
            recentTreatments.removeAll()
        }
    }
    
    /// Get stats for debugging
    public var stats: DeduplicationStats {
        lock.withLock {
            DeduplicationStats(
                processedCount: processedIds.count,
                recentCount: recentTreatments.count
            )
        }
    }
}

// MARK: - Supporting Types

private struct RecentTreatment {
    let syncId: String
    let eventType: String
    let timestamp: Date
    let insulinValue: Double?
    let carbsValue: Double?
    let processedAt: Date
}

public struct DeduplicationStats: Sendable {
    public let processedCount: Int
    public let recentCount: Int
}

// MARK: - Treatment Type Helpers

extension TreatmentDeduplicator {
    
    /// Check if treatment is a bolus
    public func isBolus(_ treatment: NightscoutTreatment) -> Bool {
        treatment.eventType == "Bolus" || treatment.eventType == "Correction Bolus" ||
        treatment.eventType == "Meal Bolus" || treatment.insulin != nil
    }
    
    /// Check if treatment is a carb entry
    public func isCarbEntry(_ treatment: NightscoutTreatment) -> Bool {
        treatment.eventType == "Carb Correction" || treatment.eventType == "Meal" ||
        treatment.carbs != nil
    }
    
    /// Check if treatment is a temp basal
    public func isTempBasal(_ treatment: NightscoutTreatment) -> Bool {
        treatment.eventType == "Temp Basal"
    }
    
    /// Check if treatment is a profile switch
    public func isProfileSwitch(_ treatment: NightscoutTreatment) -> Bool {
        treatment.eventType == "Profile Switch"
    }
}

// MARK: - Batch Processing

extension TreatmentDeduplicator {
    
    /// Process a batch of treatments for upload
    /// Returns only treatments that should be uploaded
    public func processBatchForUpload(_ treatments: [NightscoutTreatment]) -> BatchResult {
        var toUpload: [NightscoutTreatment] = []
        var duplicates: [NightscoutTreatment] = []
        
        for treatment in treatments {
            if shouldUpload(treatment) {
                toUpload.append(treatment)
                markProcessed(treatment)
            } else {
                duplicates.append(treatment)
            }
        }
        
        return BatchResult(toUpload: toUpload, duplicates: duplicates)
    }
    
    public struct BatchResult {
        public let toUpload: [NightscoutTreatment]
        public let duplicates: [NightscoutTreatment]
        
        public var uploadCount: Int { toUpload.count }
        public var duplicateCount: Int { duplicates.count }
    }
}
