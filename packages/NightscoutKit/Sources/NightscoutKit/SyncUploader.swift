// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SyncUploader.swift - Nightscout upload with deduplication
// Part of NightscoutKit
// Trace: PRD-014 REQ-DEDUP-001, NS-UPLOAD-001

import Foundation

// MARK: - Sync Uploader

/// High-level uploader with deduplication for Nightscout sync
/// Integrates EntryDeduplicator and TreatmentDeduplicator with NightscoutClient
public actor SyncUploader {
    
    // MARK: - Properties
    
    private let client: NightscoutClient
    private let entryDeduplicator: EntryDeduplicator
    private let treatmentDeduplicator: TreatmentDeduplicator
    private let deviceId: String
    
    // MARK: - Configuration
    
    /// Whether to check remote for duplicates before upload (slower but safer)
    public var checkRemoteBeforeUpload: Bool = true
    
    /// Whether to log duplicate detections
    public var logDuplicates: Bool = true
    
    // MARK: - Initialization
    
    public init(
        client: NightscoutClient,
        deviceId: String? = nil,
        entryDeduplicator: EntryDeduplicator = .shared,
        treatmentDeduplicator: TreatmentDeduplicator = .shared
    ) {
        self.client = client
        self.deviceId = deviceId ?? Self.generateDeviceId()
        self.entryDeduplicator = entryDeduplicator
        self.treatmentDeduplicator = treatmentDeduplicator
    }
    
    // MARK: - Device ID Generation
    
    /// Generate T1Pal device identifier per REQ-DEDUP-002
    private static func generateDeviceId() -> String {
        "t1pal-\(UUID().uuidString.prefix(8).lowercased())"
    }
    
    // MARK: - Entry Upload
    
    /// Upload entries with deduplication
    /// Returns upload result with counts
    @discardableResult
    public func uploadEntries(_ entries: [NightscoutEntry]) async throws -> UploadResult<NightscoutEntry> {
        guard !entries.isEmpty else {
            return UploadResult(uploaded: [], skipped: [], errors: [])
        }
        
        // Apply sync identifiers if missing
        let identified = entries.map { ensureEntryIdentifier($0) }
        
        // Local deduplication first
        let localResult = entryDeduplicator.processBatchForUpload(identified)
        var skipped = localResult.duplicates
        
        // Remote deduplication if enabled
        var toUpload = localResult.toUpload
        if checkRemoteBeforeUpload && !toUpload.isEmpty {
            do {
                let remoteDuplicates = try await entryDeduplicator.findRemoteDuplicates(
                    for: toUpload,
                    using: client
                )
                let remoteDuplicateIds = Set(remoteDuplicates.map(\.syncIdentifier))
                let filtered = toUpload.filter { !remoteDuplicateIds.contains($0.syncIdentifier) }
                skipped.append(contentsOf: toUpload.filter { remoteDuplicateIds.contains($0.syncIdentifier) })
                toUpload = filtered
            } catch {
                // Log but continue with upload (fail-open for remote check)
                if logDuplicates {
                    NightscoutLogger.sync.warning("Remote duplicate check failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Upload remaining
        var errors: [UploadError<NightscoutEntry>] = []
        if !toUpload.isEmpty {
            do {
                try await client.uploadEntries(toUpload)
            } catch {
                errors.append(UploadError(items: toUpload, error: error))
            }
        }
        
        if logDuplicates && !skipped.isEmpty {
            NightscoutLogger.sync.info("Skipped \(skipped.count) duplicate entries")
        }
        
        return UploadResult(
            uploaded: errors.isEmpty ? toUpload : [],
            skipped: skipped,
            errors: errors
        )
    }
    
    /// Ensure entry has T1Pal sync identifier
    private func ensureEntryIdentifier(_ entry: NightscoutEntry) -> NightscoutEntry {
        // If already has a syncIdentifier, use it
        guard entry.identifier == nil else { return entry }
        
        // Generate T1Pal identifier (date is in ms)
        let syncId = "\(deviceId):sgv:\(Int(entry.date / 1000))"
        
        return NightscoutEntry(
            _id: entry._id,
            type: entry.type,
            sgv: entry.sgv,
            mbg: entry.mbg,
            slope: entry.slope,
            intercept: entry.intercept,
            scale: entry.scale,
            direction: entry.direction,
            dateString: entry.dateString,
            date: entry.date,
            device: entry.device,
            noise: entry.noise,
            filtered: entry.filtered,
            unfiltered: entry.unfiltered,
            rssi: entry.rssi,
            identifier: syncId
        )
    }
    
    // MARK: - Treatment Upload
    
    /// Upload treatments with deduplication
    /// Returns upload result with counts
    @discardableResult
    public func uploadTreatments(_ treatments: [NightscoutTreatment]) async throws -> UploadResult<NightscoutTreatment> {
        guard !treatments.isEmpty else {
            return UploadResult(uploaded: [], skipped: [], errors: [])
        }
        
        // Apply sync identifiers if missing
        let identified = treatments.map { ensureTreatmentIdentifier($0) }
        
        // Local deduplication
        let localResult = treatmentDeduplicator.processBatchForUpload(identified)
        let skipped = localResult.duplicates
        let toUpload = localResult.toUpload
        
        // Upload remaining
        var errors: [UploadError<NightscoutTreatment>] = []
        if !toUpload.isEmpty {
            do {
                try await client.uploadTreatments(toUpload)
            } catch {
                errors.append(UploadError(items: toUpload, error: error))
            }
        }
        
        if logDuplicates && !skipped.isEmpty {
            NightscoutLogger.sync.info("Skipped \(skipped.count) duplicate treatments")
        }
        
        return UploadResult(
            uploaded: errors.isEmpty ? toUpload : [],
            skipped: skipped,
            errors: errors
        )
    }
    
    /// Ensure treatment has T1Pal sync identifier
    private func ensureTreatmentIdentifier(_ treatment: NightscoutTreatment) -> NightscoutTreatment {
        // If already has a syncIdentifier, use it
        guard treatment.identifier == nil else { return treatment }
        
        // Generate T1Pal identifier
        let timestamp = ISO8601DateFormatter().date(from: treatment.created_at) ?? Date()
        let type = treatment.eventType.lowercased().replacingOccurrences(of: " ", with: "-")
        let syncId = "\(deviceId):\(type):\(Int(timestamp.timeIntervalSince1970))"
        
        return NightscoutTreatment(
            _id: treatment._id,
            eventType: treatment.eventType,
            created_at: treatment.created_at,
            insulin: treatment.insulin,
            carbs: treatment.carbs,
            duration: treatment.duration,
            absolute: treatment.absolute,
            rate: treatment.rate,
            percent: treatment.percent,
            profileIndex: treatment.profileIndex,
            profile: treatment.profile,
            targetTop: treatment.targetTop,
            targetBottom: treatment.targetBottom,
            glucose: treatment.glucose,
            glucoseType: treatment.glucoseType,
            units: treatment.units,
            enteredBy: treatment.enteredBy,
            notes: treatment.notes,
            reason: treatment.reason,
            preBolus: treatment.preBolus,
            splitNow: treatment.splitNow,
            splitExt: treatment.splitExt,
            identifier: syncId
        )
    }
    
    // MARK: - Combined Sync
    
    /// Sync both entries and treatments
    public func syncAll(
        entries: [NightscoutEntry],
        treatments: [NightscoutTreatment]
    ) async throws -> CombinedSyncResult {
        async let entryResult = uploadEntries(entries)
        async let treatmentResult = uploadTreatments(treatments)
        
        return try await CombinedSyncResult(
            entries: entryResult,
            treatments: treatmentResult
        )
    }
    
    // MARK: - Reset
    
    /// Reset deduplication state (useful for testing or full resync)
    public func resetDeduplicationState() {
        entryDeduplicator.reset()
        treatmentDeduplicator.reset()
    }
    
    /// Get current device ID
    public func getDeviceId() -> String {
        deviceId
    }
}

// MARK: - Result Types

public struct UploadResult<T: Sendable>: Sendable {
    public let uploaded: [T]
    public let skipped: [T]
    public let errors: [UploadError<T>]
    
    public var uploadedCount: Int { uploaded.count }
    public var skippedCount: Int { skipped.count }
    public var hasErrors: Bool { !errors.isEmpty }
    public var totalProcessed: Int { uploaded.count + skipped.count }
}

public struct UploadError<T: Sendable>: Sendable {
    public let items: [T]
    public let error: Error
}

public struct CombinedSyncResult: Sendable {
    public let entries: UploadResult<NightscoutEntry>
    public let treatments: UploadResult<NightscoutTreatment>
    
    public var totalUploaded: Int {
        entries.uploadedCount + treatments.uploadedCount
    }
    
    public var totalSkipped: Int {
        entries.skippedCount + treatments.skippedCount
    }
    
    public var hasErrors: Bool {
        entries.hasErrors || treatments.hasErrors
    }
}
