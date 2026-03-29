// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeviceStatusSyncManager.swift
// NightscoutKit
//
// DeviceStatus synchronization manager for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-006)
// Requirements: REQ-NS-005

import Foundation

// MARK: - DeviceStatus Sync State

/// Sync state for tracking device status uploads
public struct DeviceStatusSyncState: Codable, Sendable {
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

// MARK: - DeviceStatus Sync Result

/// Sync result from a device status sync operation
public struct DeviceStatusSyncResult: Sendable {
    public let uploaded: Int
    public let downloaded: Int
    public let errors: [Error]
    
    public var success: Bool { errors.isEmpty }
    
    public init(uploaded: Int = 0, downloaded: Int = 0, errors: [Error] = []) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.errors = errors
    }
}

// MARK: - DeviceStatus Sync Manager

/// DeviceStatus sync manager for uploading algorithm state
/// Requirements: REQ-NS-005
public actor DeviceStatusSyncManager {
    private let client: NightscoutClient
    private var state: DeviceStatusSyncState
    private var pendingUploads: [NightscoutDeviceStatus]
    
    public init(client: NightscoutClient, state: DeviceStatusSyncState = DeviceStatusSyncState()) {
        self.client = client
        self.state = state
        self.pendingUploads = []
    }
    
    /// Current sync state
    public var syncState: DeviceStatusSyncState { state }
    
    /// Queue device status for upload
    public func queueForUpload(_ status: NightscoutDeviceStatus) {
        pendingUploads.append(status)
    }
    
    /// Upload queued device statuses
    public func uploadPending() async throws -> Int {
        guard !pendingUploads.isEmpty else { return 0 }
        
        var uploadedCount = 0
        for status in pendingUploads {
            try await client.uploadDeviceStatus(status)
            uploadedCount += 1
        }
        
        // Update state
        if let latest = pendingUploads.last?.timestamp {
            state.lastUploadedDate = latest
        }
        state.uploadedCount += uploadedCount
        pendingUploads = []
        
        return uploadedCount
    }
    
    /// Fetch recent device statuses
    public func fetchRecent(count: Int = 10) async throws -> [NightscoutDeviceStatus] {
        let statuses = try await client.fetchDeviceStatus(count: count)
        
        if let latest = statuses.first?.timestamp {
            state.lastDownloadedDate = latest
        }
        state.downloadedCount += statuses.count
        
        return statuses
    }
    
    /// Upload a single device status immediately
    public func upload(_ status: NightscoutDeviceStatus) async throws {
        try await client.uploadDeviceStatus(status)
        state.lastUploadedDate = status.timestamp
        state.uploadedCount += 1
    }
    
    /// Perform sync (primarily upload, optionally fetch)
    public func sync(fetchRecent: Bool = false, fetchCount: Int = 10) async -> DeviceStatusSyncResult {
        var errors: [Error] = []
        var uploaded = 0
        var downloaded = 0
        
        // Upload first
        do {
            uploaded = try await uploadPending()
        } catch {
            errors.append(error)
        }
        
        // Optionally fetch
        if fetchRecent {
            do {
                let statuses = try await self.fetchRecent(count: fetchCount)
                downloaded = statuses.count
            } catch {
                errors.append(error)
            }
        }
        
        state.lastSyncDate = Date()
        
        return DeviceStatusSyncResult(
            uploaded: uploaded,
            downloaded: downloaded,
            errors: errors
        )
    }
    
    /// Queue a device status received from WebSocket for local storage
    public func queueDownload(_ status: NightscoutDeviceStatus) {
        state.downloadedCount += 1
        if let timestamp = status.timestamp, timestamp > (state.lastDownloadedDate ?? Date.distantPast) {
            state.lastDownloadedDate = timestamp
        }
    }
    
    // MARK: - Factory Methods
    
    /// Create Loop-format device status
    public static func loopStatus(
        iob: Double,
        cob: Double,
        predictedBGs: [Double],
        tempBasalRate: Double?,
        tempBasalDuration: Double?,
        timestamp: Date,
        reservoir: Double? = nil,
        batteryPercent: Int? = nil,
        device: String = "t1pal"
    ) -> NightscoutDeviceStatus {
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: timestamp)
        
        return NightscoutDeviceStatus(
            device: device,
            created_at: timestampStr,
            mills: Int64(timestamp.timeIntervalSince1970 * 1000),
            loop: NightscoutDeviceStatus.LoopStatus(
                iob: NightscoutDeviceStatus.LoopStatus.IOBStatus(iob: iob, timestamp: timestampStr),
                cob: NightscoutDeviceStatus.LoopStatus.COBStatus(cob: cob, timestamp: timestampStr),
                predicted: NightscoutDeviceStatus.LoopStatus.PredictedStatus(startDate: timestampStr, values: predictedBGs),
                enacted: tempBasalRate.map { rate in
                    NightscoutDeviceStatus.LoopStatus.EnactedStatus(
                        rate: rate,
                        duration: tempBasalDuration,
                        timestamp: timestampStr,
                        received: true
                    )
                },
                timestamp: timestampStr
            ),
            pump: reservoir.map { res in
                NightscoutDeviceStatus.PumpStatus(
                    reservoir: res,
                    battery: batteryPercent.map { NightscoutDeviceStatus.PumpStatus.BatteryStatus(percent: $0) }
                )
            }
        )
    }
    
    /// Create OpenAPS-format device status
    public static func openapsStatus(
        bg: Double,
        iob: Double,
        cob: Double,
        tempBasalRate: Double?,
        tempBasalDuration: Int?,
        eventualBG: Double?,
        reason: String,
        predBGs: NightscoutDeviceStatus.OpenAPSStatus.SuggestedStatus.PredBGs?,
        timestamp: Date,
        reservoir: Double? = nil,
        batteryPercent: Int? = nil,
        device: String = "t1pal"
    ) -> NightscoutDeviceStatus {
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: timestamp)
        
        let suggested = NightscoutDeviceStatus.OpenAPSStatus.SuggestedStatus(
            bg: bg,
            temp: tempBasalRate != nil ? "absolute" : nil,
            rate: tempBasalRate,
            duration: tempBasalDuration,
            reason: reason,
            eventualBG: eventualBG,
            predBGs: predBGs,
            COB: cob,
            IOB: iob,
            timestamp: timestampStr
        )
        
        return NightscoutDeviceStatus(
            device: device,
            created_at: timestampStr,
            mills: Int64(timestamp.timeIntervalSince1970 * 1000),
            openaps: NightscoutDeviceStatus.OpenAPSStatus(
                iob: NightscoutDeviceStatus.OpenAPSStatus.IOBData(iob: iob, timestamp: timestampStr),
                suggested: suggested,
                enacted: tempBasalRate.map { rate in
                    NightscoutDeviceStatus.OpenAPSStatus.EnactedStatus(
                        bg: bg,
                        temp: "absolute",
                        rate: rate,
                        duration: tempBasalDuration,
                        reason: reason,
                        received: true,
                        timestamp: timestampStr
                    )
                },
                timestamp: timestampStr
            ),
            pump: reservoir.map { res in
                NightscoutDeviceStatus.PumpStatus(
                    reservoir: res,
                    battery: batteryPercent.map { NightscoutDeviceStatus.PumpStatus.BatteryStatus(percent: $0) }
                )
            }
        )
    }
}
