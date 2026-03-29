// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ProfileStore.swift
// T1Pal - Open Source AID
//
// Protocol for therapy profile storage and persistence.
// Abstracts profile storage to support multiple backends:
// - LocalProfileStore (UserDefaults)
// - NightscoutProfileStore (REST API)
// - PumpProfileStore (device sync)
//
// Trace: CRIT-PROFILE-001

import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - Profile Store Protocol

/// Protocol for therapy profile storage
/// Provides async CRUD operations for TherapyProfile
public protocol ProfileStore: AnyObject, Sendable {
    /// The current active profile
    var currentProfile: TherapyProfile { get async }
    
    /// Load the profile from storage
    /// - Returns: The stored profile, or default if none exists
    func load() async throws -> TherapyProfile
    
    /// Save a profile to storage
    /// - Parameter profile: The profile to save
    func save(_ profile: TherapyProfile) async throws
    
    /// Update specific fields of the profile
    /// - Parameter update: Closure that modifies the profile
    func update(_ update: @Sendable (inout TherapyProfile) -> Void) async throws
    
    /// Delete the stored profile and reset to defaults
    func reset() async throws
    
    /// Whether the store has unsaved changes
    var hasUnsavedChanges: Bool { get async }
    
    /// Discard unsaved changes and reload from storage
    func discardChanges() async throws
}

// MARK: - Profile Store Events

/// Events emitted by profile stores for observation
public enum ProfileStoreEvent: Sendable {
    /// Profile was loaded from storage
    case loaded(TherapyProfile)
    
    /// Profile was saved to storage
    case saved(TherapyProfile)
    
    /// Profile was reset to defaults
    case reset
    
    /// Error occurred during operation
    case error(ProfileStoreError)
    
    /// Profile sync started (for remote stores)
    case syncStarted
    
    /// Profile sync completed
    case syncCompleted
}

// MARK: - Profile Store Errors

/// Errors that can occur during profile operations
public enum ProfileStoreError: Error, Sendable, LocalizedError {
    /// Profile could not be loaded
    case loadFailed(underlying: Error?)
    
    /// Profile could not be saved
    case saveFailed(underlying: Error?)
    
    /// Profile validation failed
    case validationFailed(reason: String)
    
    /// Network error (for remote stores)
    case networkError(underlying: Error?)
    
    /// Conflict between local and remote profile
    case conflictDetected(local: TherapyProfile, remote: TherapyProfile)
    
    /// Profile store is not available
    case unavailable(reason: String)
    
    /// Sync failed (CRIT-PROFILE-010)
    case syncFailed(underlying: Error?)
    
    public var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load profile: \(error?.localizedDescription ?? "unknown error")"
        case .saveFailed(let error):
            return "Failed to save profile: \(error?.localizedDescription ?? "unknown error")"
        case .validationFailed(let reason):
            return "Profile validation failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error?.localizedDescription ?? "unknown error")"
        case .conflictDetected:
            return "Profile conflict detected between local and remote"
        case .unavailable(let reason):
            return "Profile store unavailable: \(reason)"
        case .syncFailed(let error):
            return "Profile sync failed: \(error?.localizedDescription ?? "unknown error")"
        }
    }
}

// MARK: - Profile Validation

/// Validates therapy profile values for safety
public struct ProfileValidator: Sendable {
    
    public init() {}
    
    /// Validate a therapy profile
    /// - Parameter profile: The profile to validate
    /// - Returns: Validation result with any errors
    public func validate(_ profile: TherapyProfile) -> ProfileValidationResult {
        var errors: [String] = []
        
        // Basal rates
        if profile.basalRates.isEmpty {
            errors.append("At least one basal rate is required")
        }
        for rate in profile.basalRates {
            if rate.rate <= 0 {
                errors.append("Basal rate must be greater than 0")
            }
            if rate.rate > 35 {
                errors.append("Basal rate exceeds maximum (35 U/hr)")
            }
        }
        
        // Carb ratios
        if profile.carbRatios.isEmpty {
            errors.append("At least one carb ratio is required")
        }
        for ratio in profile.carbRatios {
            if ratio.ratio <= 0 {
                errors.append("Carb ratio must be greater than 0")
            }
            if ratio.ratio > 150 {
                errors.append("Carb ratio exceeds maximum (150 g/U)")
            }
        }
        
        // Sensitivity factors
        if profile.sensitivityFactors.isEmpty {
            errors.append("At least one ISF is required")
        }
        for factor in profile.sensitivityFactors {
            if factor.factor <= 0 {
                errors.append("ISF must be greater than 0")
            }
            if factor.factor > 500 {
                errors.append("ISF exceeds maximum (500 mg/dL/U)")
            }
        }
        
        // Target glucose
        if profile.targetGlucose.low >= profile.targetGlucose.high {
            errors.append("Target low must be less than target high")
        }
        if profile.targetGlucose.low < 70 {
            errors.append("Target low below minimum (70 mg/dL)")
        }
        if profile.targetGlucose.high > 180 {
            errors.append("Target high exceeds maximum (180 mg/dL)")
        }
        
        // Safety limits
        if profile.maxIOB < 0 {
            errors.append("Max IOB cannot be negative")
        }
        if profile.maxBolus < 0 {
            errors.append("Max bolus cannot be negative")
        }
        if let maxBasal = profile.maxBasalRate, maxBasal < 0 {
            errors.append("Max basal rate cannot be negative")
        }
        
        return ProfileValidationResult(isValid: errors.isEmpty, errors: errors)
    }
}

/// Result of profile validation
public struct ProfileValidationResult: Sendable {
    /// Whether the profile is valid
    public let isValid: Bool
    
    /// List of validation errors (empty if valid)
    public let errors: [String]
    
    public init(isValid: Bool, errors: [String]) {
        self.isValid = isValid
        self.errors = errors
    }
}

#if canImport(Combine)

// MARK: - Observable Profile Store Wrapper

/// ObservableObject wrapper for SwiftUI integration
/// Wraps any ProfileStore implementation for use in views
@MainActor
public final class ObservableProfileStore: ObservableObject {
    /// The underlying profile store
    private let store: any ProfileStore
    
    /// The current profile (observable)
    @Published public private(set) var profile: TherapyProfile
    
    /// Whether the store is currently loading
    @Published public private(set) var isLoading: Bool = false
    
    /// Whether there are unsaved changes
    @Published public private(set) var hasChanges: Bool = false
    
    /// Last error that occurred
    @Published public var lastError: ProfileStoreError?
    
    /// Initialize with a profile store
    /// - Parameter store: The underlying store implementation
    public init(store: any ProfileStore) {
        self.store = store
        self.profile = TherapyProfile.default
    }
    
    /// Load profile from storage
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            profile = try await store.load()
            hasChanges = false
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
        } catch {
            lastError = .loadFailed(underlying: error)
        }
    }
    
    /// Save current profile to storage
    public func save() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await store.save(profile)
            hasChanges = false
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(underlying: error)
        }
    }
    
    /// Save and sync to remote store (CRIT-PROFILE-021)
    /// Saves locally first, then pushes to Nightscout if syncable
    /// - Parameter syncToRemote: Whether to sync to remote after saving (default: true if syncable)
    public func saveAndSync(syncToRemote: Bool = true) async {
        // First save locally
        await save()
        
        // If save failed, don't try to sync
        guard lastError == nil else { return }
        
        // Sync to remote if requested and store is syncable
        if syncToRemote && isSyncable {
            await pushToRemote()
        }
    }
    
    /// Update the profile
    /// - Parameter update: Closure that modifies the profile
    public func update(_ update: (inout TherapyProfile) -> Void) {
        update(&profile)
        hasChanges = true
    }
    
    /// Discard changes and reload
    public func discardChanges() async {
        await load()
    }
    
    /// Reset to defaults
    public func reset() async {
        do {
            try await store.reset()
            profile = TherapyProfile.default
            hasChanges = false
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(underlying: error)
        }
    }
    
    // MARK: - Sync Support (CRIT-PROFILE-010)
    
    /// Current sync status (for syncable stores)
    @Published public private(set) var syncStatus: ProfileSyncStatus = .disconnected
    
    /// Pending conflict requiring user resolution (CRIT-PROFILE-025)
    @Published public var pendingConflict: ProfileConflict?
    
    /// Whether the store supports remote sync
    public var isSyncable: Bool {
        store is any SyncableProfileStore
    }
    
    /// Sync with remote store (if syncable)
    /// Now includes conflict detection (CRIT-PROFILE-025)
    public func sync() async {
        guard let syncStore = store as? any SyncableProfileStore else {
            return
        }
        
        syncStatus = .syncing
        
        do {
            // Fetch remote first to check for conflicts
            let remoteProfile = try await syncStore.fetchRemote()
            let localProfile = profile
            
            // Check for meaningful differences
            let conflict = ProfileConflict(local: localProfile, remote: remoteProfile)
            
            if conflict.hasDifferences && hasChanges {
                // User has local changes AND remote differs - conflict!
                pendingConflict = conflict
                syncStatus = .idle
                lastError = .conflictDetected(local: localProfile, remote: remoteProfile)
                return
            }
            
            // No conflict - apply remote profile
            profile = remoteProfile
            hasChanges = false
            syncStatus = .synced(Date())
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
            syncStatus = .error(error.localizedDescription)
        } catch {
            lastError = .syncFailed(underlying: error)
            syncStatus = .error(error.localizedDescription)
        }
    }
    
    /// Resolve a pending conflict with user's choice (CRIT-PROFILE-025)
    /// - Parameter resolution: The user's resolution choice
    public func resolveConflict(_ resolution: ProfileConflictResolution) async {
        guard let conflict = pendingConflict else { return }
        
        switch resolution {
        case .keepLocal:
            // Push local to remote, overwriting
            await pushToRemote()
            
        case .useRemote:
            // Accept remote profile
            profile = conflict.remote
            hasChanges = false
            syncStatus = .synced(Date())
            lastError = nil
            
        case .cancelSync:
            // Do nothing, keep local but don't sync
            syncStatus = .idle
            lastError = nil
        }
        
        pendingConflict = nil
    }
    
    /// Fetch from remote without merging (pull)
    public func fetchFromRemote() async {
        guard let syncStore = store as? any SyncableProfileStore else {
            return
        }
        
        syncStatus = .syncing
        
        do {
            profile = try await syncStore.fetchRemote()
            hasChanges = false
            syncStatus = .synced(Date())
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
            syncStatus = .error(error.localizedDescription)
        } catch {
            lastError = .loadFailed(underlying: error)
            syncStatus = .error(error.localizedDescription)
        }
    }
    
    /// Push current profile to remote
    public func pushToRemote() async {
        guard let syncStore = store as? any SyncableProfileStore else {
            return
        }
        
        syncStatus = .syncing
        
        do {
            try await syncStore.pushToRemote()
            syncStatus = .synced(Date())
            lastError = nil
        } catch let error as ProfileStoreError {
            lastError = error
            syncStatus = .error(error.localizedDescription)
        } catch {
            lastError = .saveFailed(underlying: error)
            syncStatus = .error(error.localizedDescription)
        }
    }
    
    /// Update sync status from underlying store
    public func refreshSyncStatus() async {
        guard let syncStore = store as? any SyncableProfileStore else {
            syncStatus = .disconnected
            return
        }
        
        syncStatus = await syncStore.syncStatus
    }
}
#endif

// MARK: - Profile Sync Status

/// Status of profile synchronization with remote stores
public enum ProfileSyncStatus: Sendable, Equatable {
    case disconnected
    case idle
    case syncing
    case synced(Date)
    case error(String)
    
    public var isConnected: Bool {
        switch self {
        case .disconnected: return false
        default: return true
        }
    }
    
    public var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Profile Conflict Detection (CRIT-PROFILE-025)

/// Represents a detected conflict between local and remote profiles
/// Trace: CRIT-PROFILE-025
public struct ProfileConflict: Sendable {
    /// The local profile version
    public let local: TherapyProfile
    /// The remote (Nightscout) profile version
    public let remote: TherapyProfile
    /// Summary of which fields differ
    public let differences: ProfileDifferences
    /// When the conflict was detected
    public let detectedAt: Date
    
    public init(local: TherapyProfile, remote: TherapyProfile, detectedAt: Date = Date()) {
        self.local = local
        self.remote = remote
        self.differences = ProfileDifferences.compare(local: local, remote: remote)
        self.detectedAt = detectedAt
    }
    
    /// Whether any meaningful differences exist
    public var hasDifferences: Bool {
        differences.hasAnyDifference
    }
}

/// Summary of field-level differences between two profiles
/// Trace: CRIT-PROFILE-025
public struct ProfileDifferences: Sendable, Equatable {
    public let basalRatesDiffer: Bool
    public let carbRatiosDiffer: Bool
    public let sensitivityFactorsDiffer: Bool
    public let targetGlucoseDiffers: Bool
    public let safetyLimitsDiffer: Bool
    
    public var hasAnyDifference: Bool {
        basalRatesDiffer || carbRatiosDiffer || sensitivityFactorsDiffer ||
        targetGlucoseDiffers || safetyLimitsDiffer
    }
    
    /// Human-readable summary of differences
    public var summary: [String] {
        var items: [String] = []
        if basalRatesDiffer { items.append("Basal rates") }
        if carbRatiosDiffer { items.append("Carb ratios") }
        if sensitivityFactorsDiffer { items.append("Sensitivity factors") }
        if targetGlucoseDiffers { items.append("Target glucose") }
        if safetyLimitsDiffer { items.append("Safety limits") }
        return items
    }
    
    /// Compare two profiles and return differences
    public static func compare(local: TherapyProfile, remote: TherapyProfile) -> ProfileDifferences {
        ProfileDifferences(
            basalRatesDiffer: !basalRatesEqual(local.basalRates, remote.basalRates),
            carbRatiosDiffer: !carbRatiosEqual(local.carbRatios, remote.carbRatios),
            sensitivityFactorsDiffer: !sensitivityFactorsEqual(local.sensitivityFactors, remote.sensitivityFactors),
            targetGlucoseDiffers: local.targetGlucose != remote.targetGlucose,
            safetyLimitsDiffer: !safetyLimitsEqual(local: local, remote: remote)
        )
    }
    
    private static func basalRatesEqual(_ a: [BasalRate], _ b: [BasalRate]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.startTime == $1.startTime && abs($0.rate - $1.rate) < 0.001 }
    }
    
    private static func carbRatiosEqual(_ a: [CarbRatio], _ b: [CarbRatio]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.startTime == $1.startTime && abs($0.ratio - $1.ratio) < 0.1 }
    }
    
    private static func sensitivityFactorsEqual(_ a: [SensitivityFactor], _ b: [SensitivityFactor]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.startTime == $1.startTime && abs($0.factor - $1.factor) < 0.1 }
    }
    
    private static func safetyLimitsEqual(local: TherapyProfile, remote: TherapyProfile) -> Bool {
        abs(local.maxIOB - remote.maxIOB) < 0.1 &&
        abs(local.maxBolus - remote.maxBolus) < 0.1 &&
        (local.maxBasalRate ?? 0) == (remote.maxBasalRate ?? 0) &&
        (local.suspendThreshold ?? 0) == (remote.suspendThreshold ?? 0)
    }
}

/// Resolution choice for profile conflicts
/// Trace: CRIT-PROFILE-025
public enum ProfileConflictResolution: String, Sendable, CaseIterable {
    case keepLocal = "keepLocal"
    case useRemote = "useRemote"
    case cancelSync = "cancelSync"
    
    public var displayName: String {
        switch self {
        case .keepLocal: return "Keep Local"
        case .useRemote: return "Use Nightscout"
        case .cancelSync: return "Cancel"
        }
    }
}

// MARK: - Syncable Profile Store Protocol

/// Protocol for profile stores that support remote synchronization
/// Trace: CRIT-PROFILE-010
public protocol SyncableProfileStore: ProfileStore {
    /// Current sync status
    var syncStatus: ProfileSyncStatus { get async }
    
    /// Sync profile to remote store
    /// - Returns: The synced profile (may be updated from remote)
    func sync() async throws -> TherapyProfile
    
    /// Fetch latest profile from remote
    func fetchRemote() async throws -> TherapyProfile
    
    /// Push local profile to remote
    func pushToRemote() async throws
}

// MARK: - Profile Store Factory

/// Factory for creating profile store instances
public enum ProfileStoreType: String, Sendable, CaseIterable {
    case local = "local"
    case nightscout = "nightscout"
    case pump = "pump"
}
