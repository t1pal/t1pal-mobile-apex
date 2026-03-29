// SPDX-License-Identifier: AGPL-3.0-or-later
// OverrideManager.swift
// NightscoutKit
//
// Local override creation and control plane sync (CONTROL-004)
// Trace: agent-control-plane-integration.md

import Foundation

// MARK: - Override Preset (CONTROL-004)

/// Predefined override preset for quick activation
public struct OverridePreset: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let symbol: String?
    public let settings: OverrideSettings
    public let defaultDuration: TimeInterval?
    public let isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        settings: OverrideSettings,
        defaultDuration: TimeInterval? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.settings = settings
        self.defaultDuration = defaultDuration
        self.isEnabled = isEnabled
    }
    
    /// Common presets
    public static let exercise = OverridePreset(
        name: "Exercise",
        symbol: "🏃",
        settings: OverrideSettings(
            targetRange: 140...160,
            insulinSensitivityMultiplier: 1.5,
            basalMultiplier: 0.5
        ),
        defaultDuration: 3600
    )
    
    public static let preMeal = OverridePreset(
        name: "Pre-Meal",
        symbol: "🍽️",
        settings: OverrideSettings(
            targetRange: 80...100
        ),
        defaultDuration: 3600
    )
    
    public static let sleep = OverridePreset(
        name: "Sleep",
        symbol: "😴",
        settings: OverrideSettings(
            targetRange: 100...120
        ),
        defaultDuration: 28800 // 8 hours
    )
    
    public static let sick = OverridePreset(
        name: "Sick Day",
        symbol: "🤒",
        settings: OverrideSettings(
            targetRange: 120...140,
            insulinSensitivityMultiplier: 0.8,
            basalMultiplier: 1.2
        ),
        defaultDuration: nil // Indefinite
    )
    
    public static let allDefaults: [OverridePreset] = [
        .exercise, .preMeal, .sleep, .sick
    ]
}

/// Override settings that modify algorithm behavior
public struct OverrideSettings: Sendable, Codable, Equatable {
    public let targetRange: ClosedRange<Double>?
    public let insulinSensitivityMultiplier: Double?
    public let carbRatioMultiplier: Double?
    public let basalMultiplier: Double?
    
    public init(
        targetRange: ClosedRange<Double>? = nil,
        insulinSensitivityMultiplier: Double? = nil,
        carbRatioMultiplier: Double? = nil,
        basalMultiplier: Double? = nil
    ) {
        self.targetRange = targetRange
        self.insulinSensitivityMultiplier = insulinSensitivityMultiplier
        self.carbRatioMultiplier = carbRatioMultiplier
        self.basalMultiplier = basalMultiplier
    }
    
    /// Whether any settings are modified
    public var hasModifications: Bool {
        targetRange != nil ||
        insulinSensitivityMultiplier != nil ||
        carbRatioMultiplier != nil ||
        basalMultiplier != nil
    }
    
    /// Merge with another settings (other takes precedence)
    public func merged(with other: OverrideSettings) -> OverrideSettings {
        OverrideSettings(
            targetRange: other.targetRange ?? self.targetRange,
            insulinSensitivityMultiplier: other.insulinSensitivityMultiplier ?? self.insulinSensitivityMultiplier,
            carbRatioMultiplier: other.carbRatioMultiplier ?? self.carbRatioMultiplier,
            basalMultiplier: other.basalMultiplier ?? self.basalMultiplier
        )
    }
}

/// Active override instance
public struct ActiveOverride: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let presetId: UUID?
    public let name: String
    public let settings: OverrideSettings
    public let activatedAt: Date
    public let expiresAt: Date?
    public let source: OverrideSource
    public let syncedToControlPlane: Bool
    
    public init(
        id: UUID = UUID(),
        presetId: UUID? = nil,
        name: String,
        settings: OverrideSettings,
        activatedAt: Date = Date(),
        expiresAt: Date? = nil,
        source: OverrideSource = .local,
        syncedToControlPlane: Bool = false
    ) {
        self.id = id
        self.presetId = presetId
        self.name = name
        self.settings = settings
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
        self.source = source
        self.syncedToControlPlane = syncedToControlPlane
    }
    
    /// Whether override is expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    /// Whether override is still active
    public var isActive: Bool {
        !isExpired
    }
    
    /// Remaining duration in seconds
    public var remainingDuration: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSince(Date())
        return max(0, remaining)
    }
    
    /// Duration since activation
    public var activeDuration: TimeInterval {
        Date().timeIntervalSince(activatedAt)
    }
    
    /// Create with sync status updated
    public func withSyncStatus(_ synced: Bool) -> ActiveOverride {
        ActiveOverride(
            id: id,
            presetId: presetId,
            name: name,
            settings: settings,
            activatedAt: activatedAt,
            expiresAt: expiresAt,
            source: source,
            syncedToControlPlane: synced
        )
    }
}

/// Source of override activation
public enum OverrideSource: String, Sendable, Codable, CaseIterable {
    case local = "local"
    case caregiver = "caregiver"
    case nightscout = "nightscout"
    case schedule = "schedule"
    
    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .caregiver: return "Caregiver"
        case .nightscout: return "Nightscout"
        case .schedule: return "Scheduled"
        }
    }
}

/// Override history entry
public struct OverrideHistoryEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let override: ActiveOverride
    public let deactivatedAt: Date
    public let deactivationReason: DeactivationReason
    
    public init(
        id: UUID = UUID(),
        override: ActiveOverride,
        deactivatedAt: Date = Date(),
        deactivationReason: DeactivationReason
    ) {
        self.id = id
        self.override = override
        self.deactivatedAt = deactivatedAt
        self.deactivationReason = deactivationReason
    }
    
    /// Total duration the override was active
    public var totalDuration: TimeInterval {
        deactivatedAt.timeIntervalSince(override.activatedAt)
    }
}

/// Reason for override deactivation
public enum DeactivationReason: String, Sendable, Codable, CaseIterable {
    case userCancelled = "user_cancelled"
    case expired = "expired"
    case replacedByNew = "replaced_by_new"
    case remoteCancelled = "remote_cancelled"
    case systemReset = "system_reset"
    
    public var displayName: String {
        switch self {
        case .userCancelled: return "Cancelled by user"
        case .expired: return "Expired"
        case .replacedByNew: return "Replaced by new override"
        case .remoteCancelled: return "Cancelled remotely"
        case .systemReset: return "System reset"
        }
    }
}

/// Result of override activation
public struct OverrideActivationResult: Sendable, Equatable {
    public let success: Bool
    public let activeOverride: ActiveOverride?
    public let previousOverride: ActiveOverride?
    public let error: String?
    
    public init(
        success: Bool,
        activeOverride: ActiveOverride? = nil,
        previousOverride: ActiveOverride? = nil,
        error: String? = nil
    ) {
        self.success = success
        self.activeOverride = activeOverride
        self.previousOverride = previousOverride
        self.error = error
    }
    
    public static func success(_ override: ActiveOverride, replacing previous: ActiveOverride? = nil) -> OverrideActivationResult {
        OverrideActivationResult(success: true, activeOverride: override, previousOverride: previous)
    }
    
    public static func failure(_ error: String) -> OverrideActivationResult {
        OverrideActivationResult(success: false, error: error)
    }
}

/// Actor for managing overrides with control plane sync
public actor OverrideManager {
    private var presets: [OverridePreset]
    private var activeOverride: ActiveOverride?
    private var history: [OverrideHistoryEntry] = []
    private var pendingSyncEvents: [OverrideInstanceEvent] = []
    private let maxHistorySize: Int
    
    public init(
        presets: [OverridePreset] = OverridePreset.allDefaults,
        maxHistorySize: Int = 100
    ) {
        self.presets = presets
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Preset Management
    
    /// Get all presets
    public func getPresets() -> [OverridePreset] {
        presets.filter { $0.isEnabled }
    }
    
    /// Add a preset
    public func addPreset(_ preset: OverridePreset) {
        presets.append(preset)
    }
    
    /// Remove a preset
    public func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }
    
    /// Update a preset
    public func updatePreset(_ preset: OverridePreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        }
    }
    
    // MARK: - Override Activation
    
    /// Activate an override from a preset
    public func activate(
        preset: OverridePreset,
        duration: TimeInterval? = nil,
        source: OverrideSource = .local
    ) -> OverrideActivationResult {
        let effectiveDuration = duration ?? preset.defaultDuration
        let expiresAt = effectiveDuration.map { Date().addingTimeInterval($0) }
        
        let newOverride = ActiveOverride(
            presetId: preset.id,
            name: preset.name,
            settings: preset.settings,
            expiresAt: expiresAt,
            source: source
        )
        
        return activateOverride(newOverride)
    }
    
    /// Activate a custom override
    public func activateCustom(
        name: String,
        settings: OverrideSettings,
        duration: TimeInterval? = nil,
        source: OverrideSource = .local
    ) -> OverrideActivationResult {
        let expiresAt = duration.map { Date().addingTimeInterval($0) }
        
        let newOverride = ActiveOverride(
            name: name,
            settings: settings,
            expiresAt: expiresAt,
            source: source
        )
        
        return activateOverride(newOverride)
    }
    
    /// Internal activation logic
    private func activateOverride(_ newOverride: ActiveOverride) -> OverrideActivationResult {
        // Deactivate current override if any
        let previousOverride = activeOverride
        if let current = activeOverride {
            addToHistory(current, reason: .replacedByNew)
        }
        
        activeOverride = newOverride
        
        // Create sync event
        let syncEvent = OverrideInstanceEvent(
            source: eventSource(from: newOverride.source),
            overrideName: newOverride.name,
            duration: newOverride.expiresAt.map { $0.timeIntervalSince(newOverride.activatedAt) },
            targetRange: newOverride.settings.targetRange,
            insulinSensitivityMultiplier: newOverride.settings.insulinSensitivityMultiplier,
            carbRatioMultiplier: newOverride.settings.carbRatioMultiplier,
            basalMultiplier: newOverride.settings.basalMultiplier
        )
        pendingSyncEvents.append(syncEvent)
        
        return .success(newOverride, replacing: previousOverride)
    }
    
    /// Deactivate current override
    public func deactivate(reason: DeactivationReason = .userCancelled) -> ActiveOverride? {
        guard let current = activeOverride else { return nil }
        
        addToHistory(current, reason: reason)
        activeOverride = nil
        
        return current
    }
    
    /// Get current active override
    public func getActiveOverride() -> ActiveOverride? {
        // Check for expiration
        if let current = activeOverride, current.isExpired {
            addToHistory(current, reason: .expired)
            activeOverride = nil
            return nil
        }
        return activeOverride
    }
    
    /// Check if an override is active
    public func hasActiveOverride() -> Bool {
        getActiveOverride() != nil
    }
    
    // MARK: - History
    
    /// Get override history
    public func getHistory() -> [OverrideHistoryEntry] {
        history
    }
    
    /// Get recent history
    public func getRecentHistory(count: Int = 10) -> [OverrideHistoryEntry] {
        Array(history.suffix(count))
    }
    
    /// Clear history
    public func clearHistory() {
        history.removeAll()
    }
    
    private func addToHistory(_ override: ActiveOverride, reason: DeactivationReason) {
        let entry = OverrideHistoryEntry(
            override: override,
            deactivationReason: reason
        )
        history.append(entry)
        
        // Trim history if needed
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }
    }
    
    // MARK: - Control Plane Sync
    
    /// Get pending sync events
    public func getPendingSyncEvents() -> [OverrideInstanceEvent] {
        pendingSyncEvents
    }
    
    /// Clear pending sync events (after successful upload)
    public func clearPendingSyncEvents() {
        pendingSyncEvents.removeAll()
        
        // Mark active override as synced
        if let current = activeOverride {
            activeOverride = current.withSyncStatus(true)
        }
    }
    
    /// Apply remote override from control plane
    public func applyRemoteOverride(event: OverrideInstanceEvent) -> OverrideActivationResult {
        let settings = OverrideSettings(
            targetRange: event.targetRange,
            insulinSensitivityMultiplier: event.insulinSensitivityMultiplier,
            carbRatioMultiplier: event.carbRatioMultiplier,
            basalMultiplier: event.basalMultiplier
        )
        
        let expiresAt = event.duration.map { event.timestamp.addingTimeInterval($0) }
        let source: OverrideSource = event.source == .caregiver ? .caregiver : .nightscout
        
        let remoteOverride = ActiveOverride(
            id: event.id,
            name: event.overrideName,
            settings: settings,
            activatedAt: event.timestamp,
            expiresAt: expiresAt,
            source: source,
            syncedToControlPlane: true
        )
        
        // Deactivate current if any
        let previousOverride = activeOverride
        if let current = activeOverride {
            addToHistory(current, reason: .remoteCancelled)
        }
        
        activeOverride = remoteOverride
        
        return .success(remoteOverride, replacing: previousOverride)
    }
    
    /// Apply remote cancellation
    public func applyRemoteCancellation(event: OverrideCancelEvent) -> ActiveOverride? {
        guard let current = activeOverride else { return nil }
        
        addToHistory(current, reason: .remoteCancelled)
        activeOverride = nil
        
        return current
    }
    
    // MARK: - Helpers
    
    private func eventSource(from source: OverrideSource) -> EventSource {
        switch source {
        case .local: return .user
        case .caregiver: return .caregiver
        case .nightscout: return .system
        case .schedule: return .app
        }
    }
}

/// Logic for override calculations
public struct OverrideLogic: Sendable {
    public init() {}
    
    /// Apply override settings to a base target range
    public func applyTarget(
        base: ClosedRange<Double>,
        override: OverrideSettings
    ) -> ClosedRange<Double> {
        override.targetRange ?? base
    }
    
    /// Apply override multiplier to ISF
    public func applyISF(
        base: Double,
        override: OverrideSettings
    ) -> Double {
        if let multiplier = override.insulinSensitivityMultiplier {
            return base * multiplier
        }
        return base
    }
    
    /// Apply override multiplier to carb ratio
    public func applyCarbRatio(
        base: Double,
        override: OverrideSettings
    ) -> Double {
        if let multiplier = override.carbRatioMultiplier {
            return base * multiplier
        }
        return base
    }
    
    /// Apply override multiplier to basal rate
    public func applyBasal(
        base: Double,
        override: OverrideSettings
    ) -> Double {
        if let multiplier = override.basalMultiplier {
            return base * multiplier
        }
        return base
    }
    
    /// Format remaining time for display
    public func formatRemainingTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "<1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
    }
}
