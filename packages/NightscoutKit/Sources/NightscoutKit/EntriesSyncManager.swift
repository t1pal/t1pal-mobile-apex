// SPDX-License-Identifier: AGPL-3.0-or-later
//
// EntriesSyncManager.swift
// NightscoutKit
//
// Entries synchronization manager for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-004)
// Requirements: REQ-NS-003

import Foundation
import T1PalCore

// MARK: - Entries Sync State

/// Sync state for tracking last sync
public struct EntriesSyncState: Codable, Sendable {
    public var lastSyncDate: Date?
    public var lastUploadedDate: Date?
    public var lastDownloadedDate: Date?
    public var uploadedCount: Int
    public var downloadedCount: Int
    
    public init(
        lastSyncDate: Date? = nil,
        lastUploadedDate: Date? = nil,
        lastDownloadedDate: Date? = nil,
        uploadedCount: Int = 0,
        downloadedCount: Int = 0
    ) {
        self.lastSyncDate = lastSyncDate
        self.lastUploadedDate = lastUploadedDate
        self.lastDownloadedDate = lastDownloadedDate
        self.uploadedCount = uploadedCount
        self.downloadedCount = downloadedCount
    }
}

// MARK: - Entries Sync Result

/// Sync result from a sync operation
public struct EntriesSyncResult: Sendable {
    public let uploaded: Int
    public let downloaded: Int
    public let duplicatesSkipped: Int
    public let errors: [Error]
    
    public var success: Bool { errors.isEmpty }
    
    public init(uploaded: Int = 0, downloaded: Int = 0, duplicatesSkipped: Int = 0, errors: [Error] = []) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.duplicatesSkipped = duplicatesSkipped
        self.errors = errors
    }
}

// MARK: - Entries Sync Delegate

/// Delegate for receiving entries during sync
public protocol EntriesSyncDelegate: Sendable {
    func entriesSyncManager(_ manager: EntriesSyncManager, didDownload entries: [NightscoutEntry])
    func entriesSyncManager(_ manager: EntriesSyncManager, willUpload entries: [NightscoutEntry])
}

// MARK: - Entries Sync Manager

/// Entries sync manager for bidirectional synchronization
/// Requirements: REQ-NS-003
public actor EntriesSyncManager {
    private let client: NightscoutClient
    private var state: EntriesSyncState
    private var localEntries: Set<NightscoutEntry>
    private var pendingUploads: [NightscoutEntry]
    
    public init(client: NightscoutClient, state: EntriesSyncState = EntriesSyncState()) {
        self.client = client
        self.state = state
        self.localEntries = []
        self.pendingUploads = []
    }
    
    /// Current sync state
    public var syncState: EntriesSyncState { state }
    
    /// Add entries for upload (will be deduplicated)
    public func queueForUpload(_ entries: [NightscoutEntry]) {
        let newEntries = entries.filter { !localEntries.contains($0) }
        pendingUploads.append(contentsOf: newEntries)
        for entry in newEntries {
            localEntries.insert(entry)
        }
    }
    
    /// Fetch entries from server and return new ones
    public func fetchNew(since: Date? = nil, count: Int = 288) async throws -> [NightscoutEntry] {
        let query = EntriesQuery(
            count: count,
            dateFrom: since ?? state.lastDownloadedDate
        )
        
        let entries = try await client.fetchEntries(query: query)
        
        // Filter out duplicates
        let newEntries = entries.filter { !localEntries.contains($0) }
        for entry in newEntries {
            localEntries.insert(entry)
        }
        
        // Update state
        if let latest = entries.max(by: { $0.date < $1.date }) {
            state.lastDownloadedDate = latest.timestamp
        }
        state.downloadedCount += newEntries.count
        
        return newEntries
    }
    
    /// Upload queued entries
    public func uploadPending() async throws -> Int {
        guard !pendingUploads.isEmpty else { return 0 }
        
        let toUpload = pendingUploads
        pendingUploads = []
        
        try await client.uploadEntries(toUpload)
        
        // Update state
        if let latest = toUpload.max(by: { $0.date < $1.date }) {
            state.lastUploadedDate = latest.timestamp
        }
        state.uploadedCount += toUpload.count
        
        return toUpload.count
    }
    
    /// Perform full bidirectional sync
    public func sync(since: Date? = nil) async -> EntriesSyncResult {
        var errors: [Error] = []
        var uploaded = 0
        var downloaded = 0
        var skipped = 0
        
        // Download first
        do {
            let entries = try await fetchNew(since: since)
            downloaded = entries.count
            // Skip count is approximated from local set size before vs after
            let totalFetched = (try? await client.fetchEntries(query: EntriesQuery(count: 288, dateFrom: since)).count) ?? 0
            skipped = totalFetched - downloaded
        } catch {
            errors.append(error)
        }
        
        // Then upload
        do {
            uploaded = try await uploadPending()
        } catch {
            errors.append(error)
        }
        
        state.lastSyncDate = Date()
        
        return EntriesSyncResult(
            uploaded: uploaded,
            downloaded: downloaded,
            duplicatesSkipped: max(0, skipped),
            errors: errors
        )
    }
    
    /// Queue an entry received from WebSocket for local storage
    public func queueDownload(_ entry: NightscoutEntry) {
        if !localEntries.contains(entry) {
            localEntries.insert(entry)
            state.downloadedCount += 1
            if entry.timestamp > (state.lastDownloadedDate ?? Date.distantPast) {
                state.lastDownloadedDate = entry.timestamp
            }
        }
    }
    
    /// Convert downloaded entries to GlucoseReadings
    public func recentReadings(count: Int = 36) async throws -> [GlucoseReading] {
        let entries = try await client.fetchEntries(count: count)
        return entries.compactMap { $0.toGlucoseReading() }
    }
    
    /// Create entries from glucose readings for upload
    public static func entriesFromReadings(_ readings: [GlucoseReading], device: String = "t1pal") -> [NightscoutEntry] {
        let formatter = ISO8601DateFormatter()
        
        return readings.map { reading in
            let direction: String
            switch reading.trend {
            case .doubleUp: direction = "DoubleUp"
            case .singleUp: direction = "SingleUp"
            case .fortyFiveUp: direction = "FortyFiveUp"
            case .flat: direction = "Flat"
            case .fortyFiveDown: direction = "FortyFiveDown"
            case .singleDown: direction = "SingleDown"
            case .doubleDown: direction = "DoubleDown"
            default: direction = "NOT COMPUTABLE"
            }
            
            return NightscoutEntry(
                type: "sgv",
                sgv: Int(reading.glucose),
                direction: direction,
                dateString: formatter.string(from: reading.timestamp),
                date: reading.timestamp.timeIntervalSince1970 * 1000,
                device: device
            )
        }
    }
}
