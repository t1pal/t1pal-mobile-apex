// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ProfileSyncManager.swift
// NightscoutKit
//
// Profile synchronization manager for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-007)
// Requirements: REQ-NS-006

import Foundation

// MARK: - Profile Sync State

/// Sync state for profile data
public struct ProfileSyncState: Codable, Sendable {
    public var lastSyncDate: Date?
    public var lastUploadDate: Date?
    public var lastDownloadDate: Date?
    public var profileCount: Int
    
    public init(
        lastSyncDate: Date? = nil,
        lastUploadDate: Date? = nil,
        lastDownloadDate: Date? = nil,
        profileCount: Int = 0
    ) {
        self.lastSyncDate = lastSyncDate
        self.lastUploadDate = lastUploadDate
        self.lastDownloadDate = lastDownloadDate
        self.profileCount = profileCount
    }
}

// MARK: - Profile Sync Result

/// Result of a profile sync operation
public struct ProfileSyncResult: Sendable {
    public let success: Bool
    public let profiles: [NightscoutProfile]
    public let uploadedCount: Int
    public let downloadedCount: Int
    public let errors: [Error]
    
    public init(
        success: Bool,
        profiles: [NightscoutProfile] = [],
        uploadedCount: Int = 0,
        downloadedCount: Int = 0,
        errors: [Error] = []
    ) {
        self.success = success
        self.profiles = profiles
        self.uploadedCount = uploadedCount
        self.downloadedCount = downloadedCount
        self.errors = errors
    }
}

// MARK: - Profile Sync Manager

/// Manager for syncing profile data with Nightscout
/// Requirements: REQ-NS-006
public actor ProfileSyncManager {
    private let client: NightscoutClient
    private var syncState: ProfileSyncState
    private var uploadQueue: [NightscoutProfile] = []
    
    public init(client: NightscoutClient, initialState: ProfileSyncState = ProfileSyncState()) {
        self.client = client
        self.syncState = initialState
    }
    
    /// Get current sync state
    public func getState() -> ProfileSyncState {
        syncState
    }
    
    /// Fetch profiles from Nightscout
    public func fetch(query: ProfileQuery = ProfileQuery(count: 10)) async throws -> [NightscoutProfile] {
        let profiles = try await client.fetchProfiles(query: query)
        syncState.lastDownloadDate = Date()
        syncState.lastSyncDate = Date()
        syncState.profileCount = profiles.count
        return profiles
    }
    
    /// Fetch active profile
    public func fetchActiveProfile() async throws -> NightscoutProfile? {
        let profiles = try await fetch(query: ProfileQuery(count: 1))
        return profiles.first
    }
    
    /// Queue a profile for upload
    public func queueUpload(_ profile: NightscoutProfile) {
        uploadQueue.append(profile)
    }
    
    /// Process upload queue
    public func processUploadQueue() async -> ProfileSyncResult {
        var errors: [Error] = []
        var uploadedCount = 0
        
        while !uploadQueue.isEmpty {
            let profile = uploadQueue.removeFirst()
            do {
                try await client.uploadProfile(profile)
                uploadedCount += 1
            } catch {
                errors.append(error)
            }
        }
        
        if uploadedCount > 0 {
            syncState.lastUploadDate = Date()
            syncState.lastSyncDate = Date()
        }
        
        return ProfileSyncResult(
            success: errors.isEmpty,
            uploadedCount: uploadedCount,
            errors: errors
        )
    }
    
    /// Upload a profile immediately
    public func upload(_ profile: NightscoutProfile) async throws {
        try await client.uploadProfile(profile)
        syncState.lastUploadDate = Date()
        syncState.lastSyncDate = Date()
    }
    
    /// Create a profile from local therapy settings
    public static func profileFromSettings(
        basalRates: [(startTime: Int, rate: Double)],
        carbRatios: [(startTime: Int, ratio: Double)],
        sensitivities: [(startTime: Int, isf: Double)],
        targetLow: [(startTime: Int, target: Double)],
        targetHigh: [(startTime: Int, target: Double)],
        dia: Double,
        units: String = "mg/dL",
        timezone: String = "UTC",
        profileName: String = "default",
        enteredBy: String = "T1Pal"
    ) -> NightscoutProfile {
        let store = ProfileStore(
            dia: dia,
            carbratio: carbRatios.map { ScheduleEntry(timeAsSeconds: $0.startTime, value: $0.ratio) },
            sens: sensitivities.map { ScheduleEntry(timeAsSeconds: $0.startTime, value: $0.isf) },
            basal: basalRates.map { ScheduleEntry(timeAsSeconds: $0.startTime, value: $0.rate) },
            target_low: targetLow.map { ScheduleEntry(timeAsSeconds: $0.startTime, value: $0.target) },
            target_high: targetHigh.map { ScheduleEntry(timeAsSeconds: $0.startTime, value: $0.target) },
            timezone: timezone,
            units: units
        )
        
        let formatter = ISO8601DateFormatter()
        let now = Date()
        
        return NightscoutProfile(
            defaultProfile: profileName,
            startDate: formatter.string(from: now),
            mills: Int64(now.timeIntervalSince1970 * 1000),
            units: units,
            store: [profileName: store],
            created_at: formatter.string(from: now),
            enteredBy: enteredBy
        )
    }
}
