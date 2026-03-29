// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutProfileStore.swift
// NightscoutKit
//
// ProfileStore implementation using Nightscout REST API.
// Fetches and uploads profiles via NightscoutClient.
//
// Trace: CRIT-PROFILE-002

import Foundation
import T1PalCore

// Type alias to disambiguate from NightscoutKit.ProfileStore
public typealias TherapyProfileStore = T1PalCore.ProfileStore

// MARK: - Nightscout Profile Store

/// Actor-based profile storage using Nightscout REST API
/// Conforms to T1PalCore.ProfileStore protocol for async CRUD operations
public actor NightscoutProfileStore: TherapyProfileStore {
    
    // MARK: - Properties
    
    /// The Nightscout client for API calls
    private let client: NightscoutClient
    
    /// Profile name to use in Nightscout store
    private let profileName: String
    
    /// Cached profile for fast access
    private var cachedProfile: TherapyProfile?
    
    /// Tracks if there are unsaved changes
    private var _hasUnsavedChanges: Bool = false
    
    /// Last fetched NightscoutProfile (for updates)
    private var lastFetchedProfile: NightscoutProfile?
    
    /// Entry identifier for uploads
    private let enteredBy: String
    
    // MARK: - Initialization
    
    /// Initialize with a Nightscout client
    /// - Parameters:
    ///   - client: NightscoutClient for API calls
    ///   - profileName: Name of the profile in Nightscout store (default: "Default")
    ///   - enteredBy: Identifier for uploads (default: "T1Pal")
    public init(
        client: NightscoutClient,
        profileName: String = "Default",
        enteredBy: String = "T1Pal"
    ) {
        self.client = client
        self.profileName = profileName
        self.enteredBy = enteredBy
    }
    
    // MARK: - ProfileStore Protocol
    
    /// The current active profile
    public var currentProfile: TherapyProfile {
        get async {
            if let cached = cachedProfile {
                return cached
            }
            return (try? await load()) ?? TherapyProfile.default
        }
    }
    
    /// Whether the store has unsaved changes
    public var hasUnsavedChanges: Bool {
        get async {
            _hasUnsavedChanges
        }
    }
    
    /// Load the profile from Nightscout
    /// - Returns: The stored profile, or default if none exists
    public func load() async throws -> TherapyProfile {
        do {
            let profiles = try await client.fetchProfiles(count: 1)
            
            guard let nsProfile = profiles.first,
                  let store = nsProfile.activeProfile else {
                // No profile found, return default
                let defaultProfile = TherapyProfile.default
                cachedProfile = defaultProfile
                _hasUnsavedChanges = false
                return defaultProfile
            }
            
            lastFetchedProfile = nsProfile
            let therapyProfile = convertToTherapyProfile(store, units: nsProfile.units)
            cachedProfile = therapyProfile
            _hasUnsavedChanges = false
            return therapyProfile
            
        } catch {
            throw ProfileStoreError.loadFailed(underlying: error)
        }
    }
    
    /// Save a profile to Nightscout
    /// - Parameter profile: The profile to save
    public func save(_ profile: TherapyProfile) async throws {
        // Validate before saving
        let validator = ProfileValidator()
        let result = validator.validate(profile)
        
        if !result.isValid {
            throw ProfileStoreError.validationFailed(reason: result.errors.joined(separator: ", "))
        }
        
        do {
            let nsProfile = convertToNightscoutProfile(profile)
            try await client.uploadProfile(nsProfile)
            cachedProfile = profile
            _hasUnsavedChanges = false
        } catch {
            throw ProfileStoreError.saveFailed(underlying: error)
        }
    }
    
    /// Update specific fields of the profile
    /// - Parameter update: Closure that modifies the profile
    public func update(_ update: @Sendable (inout TherapyProfile) -> Void) async throws {
        var profile = await currentProfile
        update(&profile)
        cachedProfile = profile
        _hasUnsavedChanges = true
    }
    
    /// Delete the stored profile and reset to defaults
    public func reset() async throws {
        // Note: Nightscout doesn't support profile deletion via API
        // We just reset the cached profile to default
        cachedProfile = TherapyProfile.default
        _hasUnsavedChanges = false
    }
    
    /// Discard unsaved changes and reload from Nightscout
    public func discardChanges() async throws {
        _ = try await load()
    }
    
    // MARK: - Conversion Methods
    
    /// Convert NightscoutKit ProfileStore to T1PalCore TherapyProfile
    private func convertToTherapyProfile(_ store: ProfileStore, units: String?) -> TherapyProfile {
        let isMmol = units?.lowercased().contains("mmol") ?? false
        let conversionFactor = isMmol ? 18.0182 : 1.0
        
        // Convert basal rates
        let basalRates = (store.basal ?? []).compactMap { entry -> BasalRate? in
            guard let value = entry.value else { return nil }
            return BasalRate(
                startTime: entry.secondsFromMidnight,
                rate: value
            )
        }
        
        // Convert carb ratios
        let carbRatios = (store.carbratio ?? []).compactMap { entry -> CarbRatio? in
            guard let value = entry.value else { return nil }
            return CarbRatio(
                startTime: entry.secondsFromMidnight,
                ratio: value
            )
        }
        
        // Convert sensitivity factors (with unit conversion)
        let sensitivityFactors = (store.sens ?? []).compactMap { entry -> SensitivityFactor? in
            guard let value = entry.value else { return nil }
            return SensitivityFactor(
                startTime: entry.secondsFromMidnight,
                factor: value * conversionFactor
            )
        }
        
        // Convert target glucose (with unit conversion)
        let targetLow = (store.target_low?.first?.value ?? 100) * conversionFactor
        let targetHigh = (store.target_high?.first?.value ?? 120) * conversionFactor
        let targetGlucose = TargetRange(low: targetLow, high: targetHigh)
        
        return TherapyProfile(
            basalRates: basalRates.isEmpty ? [BasalRate(startTime: 0, rate: 1.0)] : basalRates,
            carbRatios: carbRatios.isEmpty ? [CarbRatio(startTime: 0, ratio: 10)] : carbRatios,
            sensitivityFactors: sensitivityFactors.isEmpty ? [SensitivityFactor(startTime: 0, factor: 50)] : sensitivityFactors,
            targetGlucose: targetGlucose,
            maxIOB: 10.0, // Not stored in NS profile, use reasonable default
            maxBolus: 10.0 // Not stored in NS profile, use reasonable default
        )
    }
    
    /// Convert T1PalCore TherapyProfile to NightscoutKit NightscoutProfile
    private func convertToNightscoutProfile(_ profile: TherapyProfile) -> NightscoutProfile {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let startDate = formatter.string(from: now)
        
        // Convert basal rates
        let basal = profile.basalRates.map { rate in
            ScheduleEntry(
                time: formatTimeFromSeconds(rate.startTime),
                timeAsSeconds: Int(rate.startTime),
                value: rate.rate
            )
        }
        
        // Convert carb ratios
        let carbratio = profile.carbRatios.map { ratio in
            ScheduleEntry(
                time: formatTimeFromSeconds(ratio.startTime),
                timeAsSeconds: Int(ratio.startTime),
                value: ratio.ratio
            )
        }
        
        // Convert sensitivity factors
        let sens = profile.sensitivityFactors.map { factor in
            ScheduleEntry(
                time: formatTimeFromSeconds(factor.startTime),
                timeAsSeconds: Int(factor.startTime),
                value: factor.factor
            )
        }
        
        // Convert target glucose
        let targetLow = [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: profile.targetGlucose.low)]
        let targetHigh = [ScheduleEntry(time: "00:00", timeAsSeconds: 0, value: profile.targetGlucose.high)]
        
        let store = ProfileStore(
            dia: 6.0, // Default DIA
            carbratio: carbratio,
            sens: sens,
            basal: basal,
            target_low: targetLow,
            target_high: targetHigh,
            timezone: TimeZone.current.identifier,
            units: "mg/dL",
            startDate: startDate,
            carbs_hr: nil,
            delay: nil
        )
        
        return NightscoutProfile(
            _id: nil,
            defaultProfile: profileName,
            startDate: startDate,
            mills: Int64(now.timeIntervalSince1970 * 1000),
            units: "mg/dL",
            store: [profileName: store],
            created_at: startDate,
            enteredBy: enteredBy,
            loopSettings: nil
        )
    }
    
    /// Format seconds since midnight as HH:mm
    private func formatTimeFromSeconds(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

// MARK: - SyncableProfileStore Conformance (CRIT-PROFILE-010)

extension NightscoutProfileStore: SyncableProfileStore {
    
    /// Current sync status based on connection state
    public var syncStatus: ProfileSyncStatus {
        get async {
            // Check if we have a valid client configuration
            if cachedProfile != nil && !_hasUnsavedChanges {
                return .idle
            } else if _hasUnsavedChanges {
                return .idle  // Has changes but not actively syncing
            }
            return .idle
        }
    }
    
    /// Sync profile with Nightscout (bidirectional)
    /// For now, this pulls the latest from NS
    /// - Returns: The synced profile
    public func sync() async throws -> TherapyProfile {
        // If we have unsaved changes, push first
        if _hasUnsavedChanges, let profile = cachedProfile {
            try await save(profile)
        }
        
        // Then pull latest
        return try await load()
    }
    
    /// Fetch latest profile from Nightscout
    public func fetchRemote() async throws -> TherapyProfile {
        return try await load()
    }
    
    /// Push local profile to Nightscout
    public func pushToRemote() async throws {
        guard let profile = cachedProfile else {
            throw ProfileStoreError.unavailable(reason: "No profile to push")
        }
        try await save(profile)
    }
}

// MARK: - ScheduleEntry Helper Extension

extension ScheduleEntry {
    /// Get seconds from midnight, parsing time string if needed
    var secondsFromMidnight: TimeInterval {
        // First check the timeAsSeconds field
        if let seconds = timeAsSeconds {
            return TimeInterval(seconds)
        }
        // Parse HH:mm format
        guard let timeStr = time else { return 0 }
        let components = timeStr.split(separator: ":")
        guard components.count >= 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]) else {
            return 0
        }
        return TimeInterval(hours * 3600 + minutes * 60)
    }
}
