// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TreatmentsSyncManager.swift
// NightscoutKit
//
// Treatments synchronization manager for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-005)
// Requirements: REQ-NS-004

import Foundation

// MARK: - Treatments Sync State

/// Sync state for tracking treatments sync
public struct TreatmentsSyncState: Codable, Sendable {
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

// MARK: - Treatments Sync Result

/// Sync result from a treatments sync operation
public struct TreatmentsSyncResult: Sendable {
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

// MARK: - Treatments Sync Manager

/// Treatments sync manager for bidirectional synchronization
/// Requirements: REQ-NS-004
public actor TreatmentsSyncManager {
    private let client: NightscoutClient
    private var state: TreatmentsSyncState
    private var localTreatments: Set<NightscoutTreatment>
    private var pendingUploads: [NightscoutTreatment]
    
    public init(client: NightscoutClient, state: TreatmentsSyncState = TreatmentsSyncState()) {
        self.client = client
        self.state = state
        self.localTreatments = []
        self.pendingUploads = []
    }
    
    /// Current sync state
    public var syncState: TreatmentsSyncState { state }
    
    /// Add treatments for upload (will be deduplicated)
    public func queueForUpload(_ treatments: [NightscoutTreatment]) {
        let newTreatments = treatments.filter { !localTreatments.contains($0) }
        pendingUploads.append(contentsOf: newTreatments)
        for treatment in newTreatments {
            localTreatments.insert(treatment)
        }
    }
    
    /// Fetch treatments from server and return new ones
    public func fetchNew(since: Date? = nil, count: Int = 288) async throws -> [NightscoutTreatment] {
        let query = TreatmentsQuery(
            count: count,
            dateFrom: since ?? state.lastDownloadedDate
        )
        
        let treatments = try await client.fetchTreatments(query: query)
        
        // Filter out duplicates
        let newTreatments = treatments.filter { !localTreatments.contains($0) }
        for treatment in newTreatments {
            localTreatments.insert(treatment)
        }
        
        // Update state
        if let latest = treatments.compactMap({ $0.timestamp }).max() {
            state.lastDownloadedDate = latest
        }
        state.downloadedCount += newTreatments.count
        
        return newTreatments
    }
    
    /// Upload queued treatments
    public func uploadPending() async throws -> Int {
        guard !pendingUploads.isEmpty else { return 0 }
        
        let toUpload = pendingUploads
        pendingUploads = []
        
        try await client.uploadTreatments(toUpload)
        
        // Update state
        if let latest = toUpload.compactMap({ $0.timestamp }).max() {
            state.lastUploadedDate = latest
        }
        state.uploadedCount += toUpload.count
        
        return toUpload.count
    }
    
    /// Perform full bidirectional sync
    public func sync(since: Date? = nil) async -> TreatmentsSyncResult {
        var errors: [Error] = []
        var uploaded = 0
        var downloaded = 0
        var skipped = 0
        
        // Download first
        do {
            let treatments = try await fetchNew(since: since)
            downloaded = treatments.count
            let totalFetched = (try? await client.fetchTreatments(query: TreatmentsQuery(count: 288, dateFrom: since)).count) ?? 0
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
        
        return TreatmentsSyncResult(
            uploaded: uploaded,
            downloaded: downloaded,
            duplicatesSkipped: max(0, skipped),
            errors: errors
        )
    }
    
    /// Queue a treatment received from WebSocket for local storage
    public func queueDownload(_ treatment: NightscoutTreatment) {
        if !localTreatments.contains(treatment) {
            localTreatments.insert(treatment)
            state.downloadedCount += 1
            if let timestamp = treatment.timestamp, timestamp > (state.lastDownloadedDate ?? Date.distantPast) {
                state.lastDownloadedDate = timestamp
            }
        }
    }
    
    /// Fetch recent bolus treatments
    public func recentBoluses(count: Int = 50) async throws -> [NightscoutTreatment] {
        let all = try await client.fetchTreatments(count: count)
        return all.filter { $0.isInsulinTreatment }
    }
    
    /// Fetch recent carb entries
    public func recentCarbs(count: Int = 50) async throws -> [NightscoutTreatment] {
        let all = try await client.fetchTreatments(count: count)
        return all.filter { $0.isCarbTreatment }
    }
    
    /// Fetch recent temp basals
    public func recentTempBasals(count: Int = 50) async throws -> [NightscoutTreatment] {
        let all = try await client.fetchTreatments(count: count)
        return all.filter { $0.isTempBasal }
    }
    
    /// Create bolus treatment for upload
    public static func bolusFromInsulin(
        units: Double,
        timestamp: Date,
        type: TreatmentEventType = .correctionBolus,
        device: String = "t1pal",
        notes: String? = nil
    ) -> NightscoutTreatment {
        let formatter = ISO8601DateFormatter()
        return NightscoutTreatment(
            eventType: type.rawValue,
            created_at: formatter.string(from: timestamp),
            insulin: units,
            enteredBy: device,
            notes: notes
        )
    }
    
    /// Create carb treatment for upload
    public static func carbEntry(
        grams: Double,
        timestamp: Date,
        device: String = "t1pal",
        notes: String? = nil
    ) -> NightscoutTreatment {
        let formatter = ISO8601DateFormatter()
        return NightscoutTreatment(
            eventType: TreatmentEventType.mealCarbs.rawValue,
            created_at: formatter.string(from: timestamp),
            carbs: grams,
            enteredBy: device,
            notes: notes
        )
    }
    
    /// Create temp basal treatment for upload
    public static func tempBasal(
        rate: Double,
        duration: Double,
        timestamp: Date,
        device: String = "t1pal"
    ) -> NightscoutTreatment {
        let formatter = ISO8601DateFormatter()
        return NightscoutTreatment(
            eventType: TreatmentEventType.tempBasal.rawValue,
            created_at: formatter.string(from: timestamp),
            duration: duration,
            absolute: rate,
            rate: rate,
            enteredBy: device
        )
    }
}
