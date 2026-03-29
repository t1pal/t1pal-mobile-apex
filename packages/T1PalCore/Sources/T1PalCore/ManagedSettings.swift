// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ManagedSettings.swift
// T1PalCore
//
// Provider-managed settings for clinic/enterprise deployments.
// Enables healthcare organizations to push therapy settings to patient devices.
// Trace: ID-ENT-003, PRD-003

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Settings Policy

/// Policy for a managed setting field
public enum SettingsPolicy: String, Codable, Sendable, CaseIterable {
    /// Setting is locked by provider - patient cannot modify
    case locked
    
    /// Setting is suggested by provider - patient can override
    case suggested
    
    /// Setting uses default/local value - not managed
    case `default`
    
    /// Whether this policy allows local overrides
    public var allowsOverride: Bool {
        switch self {
        case .locked: return false
        case .suggested, .default: return true
        }
    }
    
    /// Display description
    public var description: String {
        switch self {
        case .locked: return "Set by your care team"
        case .suggested: return "Recommended by your care team"
        case .default: return "Your preference"
        }
    }
    
    /// SF Symbol icon name
    public var iconName: String {
        switch self {
        case .locked: return "lock.fill"
        case .suggested: return "sparkles"
        case .default: return "person.fill"
        }
    }
}

// MARK: - Managed Setting Value

/// A single managed setting with value and policy
public struct ManagedSettingValue<T: Codable & Sendable>: Codable, Sendable {
    /// The value from the provider
    public let value: T
    
    /// Policy for this setting
    public let policy: SettingsPolicy
    
    /// Reason/explanation from provider (optional)
    public let reason: String?
    
    public init(value: T, policy: SettingsPolicy = .suggested, reason: String? = nil) {
        self.value = value
        self.policy = policy
        self.reason = reason
    }
}

// MARK: - Managed Settings Payload

/// Complete managed settings payload from provider API
public struct ManagedSettingsPayload: Codable, Sendable, Equatable {
    /// Provider identifier
    public let providerId: String
    
    /// Provider display name
    public let providerName: String
    
    /// When these settings were issued
    public let issuedAt: Date
    
    /// When these settings expire (optional)
    public let expiresAt: Date?
    
    /// Version for conflict resolution
    public let version: Int
    
    // MARK: - Glucose Display Settings
    
    /// Glucose unit preference
    public let glucoseUnit: ManagedSettingValue<String>?
    
    /// High glucose threshold (mg/dL)
    public let highGlucoseThreshold: ManagedSettingValue<Double>?
    
    /// Low glucose threshold (mg/dL)
    public let lowGlucoseThreshold: ManagedSettingValue<Double>?
    
    /// Urgent high threshold (mg/dL)
    public let urgentHighThreshold: ManagedSettingValue<Double>?
    
    /// Urgent low threshold (mg/dL)
    public let urgentLowThreshold: ManagedSettingValue<Double>?
    
    // MARK: - Alert Settings
    
    /// High alert enabled
    public let highAlertEnabled: ManagedSettingValue<Bool>?
    
    /// Low alert enabled
    public let lowAlertEnabled: ManagedSettingValue<Bool>?
    
    /// Urgent alert enabled
    public let urgentAlertEnabled: ManagedSettingValue<Bool>?
    
    /// Stale data alert enabled
    public let staleDataAlertEnabled: ManagedSettingValue<Bool>?
    
    /// Stale data threshold (minutes)
    public let staleDataMinutes: ManagedSettingValue<Int>?
    
    // MARK: - Algorithm Settings (for AID)
    
    /// Target glucose (mg/dL)
    public let targetGlucose: ManagedSettingValue<Double>?
    
    /// Correction range low (mg/dL)
    public let correctionRangeLow: ManagedSettingValue<Double>?
    
    /// Correction range high (mg/dL)
    public let correctionRangeHigh: ManagedSettingValue<Double>?
    
    /// Max basal rate (U/hr)
    public let maxBasalRate: ManagedSettingValue<Double>?
    
    /// Max bolus (U)
    public let maxBolus: ManagedSettingValue<Double>?
    
    /// Suspend threshold (mg/dL)
    public let suspendThreshold: ManagedSettingValue<Double>?
    
    // MARK: - Custom Settings
    
    /// Additional provider-specific settings
    public let customSettings: [String: AnyCodable]?
    
    public init(
        providerId: String,
        providerName: String,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        version: Int = 1,
        glucoseUnit: ManagedSettingValue<String>? = nil,
        highGlucoseThreshold: ManagedSettingValue<Double>? = nil,
        lowGlucoseThreshold: ManagedSettingValue<Double>? = nil,
        urgentHighThreshold: ManagedSettingValue<Double>? = nil,
        urgentLowThreshold: ManagedSettingValue<Double>? = nil,
        highAlertEnabled: ManagedSettingValue<Bool>? = nil,
        lowAlertEnabled: ManagedSettingValue<Bool>? = nil,
        urgentAlertEnabled: ManagedSettingValue<Bool>? = nil,
        staleDataAlertEnabled: ManagedSettingValue<Bool>? = nil,
        staleDataMinutes: ManagedSettingValue<Int>? = nil,
        targetGlucose: ManagedSettingValue<Double>? = nil,
        correctionRangeLow: ManagedSettingValue<Double>? = nil,
        correctionRangeHigh: ManagedSettingValue<Double>? = nil,
        maxBasalRate: ManagedSettingValue<Double>? = nil,
        maxBolus: ManagedSettingValue<Double>? = nil,
        suspendThreshold: ManagedSettingValue<Double>? = nil,
        customSettings: [String: AnyCodable]? = nil
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.version = version
        self.glucoseUnit = glucoseUnit
        self.highGlucoseThreshold = highGlucoseThreshold
        self.lowGlucoseThreshold = lowGlucoseThreshold
        self.urgentHighThreshold = urgentHighThreshold
        self.urgentLowThreshold = urgentLowThreshold
        self.highAlertEnabled = highAlertEnabled
        self.lowAlertEnabled = lowAlertEnabled
        self.urgentAlertEnabled = urgentAlertEnabled
        self.staleDataAlertEnabled = staleDataAlertEnabled
        self.staleDataMinutes = staleDataMinutes
        self.targetGlucose = targetGlucose
        self.correctionRangeLow = correctionRangeLow
        self.correctionRangeHigh = correctionRangeHigh
        self.maxBasalRate = maxBasalRate
        self.maxBolus = maxBolus
        self.suspendThreshold = suspendThreshold
        self.customSettings = customSettings
    }
    
    /// Check if payload has expired
    public var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return Date() > expiry
    }
    
    /// Parse from JSON data
    public static func parse(from data: Data) throws -> ManagedSettingsPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManagedSettingsPayload.self, from: data)
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for custom settings
public struct AnyCodable: Codable, @unchecked Sendable, Equatable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unsupported type"
            ))
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality for common types
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        default: return false
        }
    }
}

// MARK: - Settings Field Identifier

/// Identifiers for managed settings fields
public enum ManagedSettingField: String, Sendable, CaseIterable {
    case glucoseUnit
    case highGlucoseThreshold
    case lowGlucoseThreshold
    case urgentHighThreshold
    case urgentLowThreshold
    case highAlertEnabled
    case lowAlertEnabled
    case urgentAlertEnabled
    case staleDataAlertEnabled
    case staleDataMinutes
    case targetGlucose
    case correctionRangeLow
    case correctionRangeHigh
    case maxBasalRate
    case maxBolus
    case suspendThreshold
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .glucoseUnit: return "Glucose Unit"
        case .highGlucoseThreshold: return "High Threshold"
        case .lowGlucoseThreshold: return "Low Threshold"
        case .urgentHighThreshold: return "Urgent High"
        case .urgentLowThreshold: return "Urgent Low"
        case .highAlertEnabled: return "High Alerts"
        case .lowAlertEnabled: return "Low Alerts"
        case .urgentAlertEnabled: return "Urgent Alerts"
        case .staleDataAlertEnabled: return "Stale Data Alerts"
        case .staleDataMinutes: return "Stale Threshold"
        case .targetGlucose: return "Target Glucose"
        case .correctionRangeLow: return "Correction Low"
        case .correctionRangeHigh: return "Correction High"
        case .maxBasalRate: return "Max Basal"
        case .maxBolus: return "Max Bolus"
        case .suspendThreshold: return "Suspend Threshold"
        }
    }
}

// MARK: - Managed Settings Manager

/// Actor for managing provider-controlled settings
public actor ManagedSettingsManager {
    
    /// Currently applied managed settings
    private var currentPayload: ManagedSettingsPayload?
    
    /// Policy cache for quick lookups
    private var policyCache: [ManagedSettingField: SettingsPolicy] = [:]
    
    /// Storage key for persistence
    private let storageKey = "com.t1pal.managedSettings"
    
    /// Settings store reference
    private let settingsStore: SettingsStore
    
    public init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore
        Task { await self.loadPersistedSettingsAsync() }
    }
    
    /// Load persisted settings asynchronously
    private func loadPersistedSettingsAsync() {
        loadPersistedSettings()
    }
    
    // MARK: - Public API
    
    /// Get the currently active managed settings payload
    public func currentSettings() -> ManagedSettingsPayload? {
        currentPayload
    }
    
    /// Get policy for a specific field
    public func policy(for field: ManagedSettingField) -> SettingsPolicy {
        policyCache[field] ?? .default
    }
    
    /// Check if a field can be modified by the user
    public func canModify(field: ManagedSettingField) -> Bool {
        policy(for: field).allowsOverride
    }
    
    /// Get the provider name if settings are managed
    public func providerName() -> String? {
        currentPayload?.providerName
    }
    
    /// Check if any settings are currently managed
    public func hasManagedSettings() -> Bool {
        currentPayload != nil && !(currentPayload?.isExpired ?? true)
    }
    
    /// Fetch managed settings from provider URL
    public func fetchSettings(from url: URL, accessToken: String) async throws -> ManagedSettingsPayload {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManagedSettingsError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ManagedSettingsError.fetchFailed("HTTP \(httpResponse.statusCode)")
        }
        
        return try ManagedSettingsPayload.parse(from: data)
    }
    
    /// Apply managed settings to the settings store
    public func apply(_ payload: ManagedSettingsPayload) throws {
        // Don't apply expired settings
        if payload.isExpired {
            throw ManagedSettingsError.settingsExpired
        }
        
        // Check version - don't downgrade
        if let current = currentPayload, current.version > payload.version {
            throw ManagedSettingsError.versionConflict(
                current: current.version,
                incoming: payload.version
            )
        }
        
        // Apply each setting
        applySettings(from: payload)
        
        // Update state
        currentPayload = payload
        buildPolicyCache(from: payload)
        persistSettings()
    }
    
    /// Clear all managed settings
    public func clearManagedSettings() {
        currentPayload = nil
        policyCache.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    // MARK: - Private Helpers
    
    private func applySettings(from payload: ManagedSettingsPayload) {
        // Glucose display
        if let setting = payload.glucoseUnit {
            if let unit = GlucoseUnit(rawValue: setting.value) {
                settingsStore.glucoseUnit = unit
            }
        }
        
        if let setting = payload.highGlucoseThreshold {
            settingsStore.highGlucoseThreshold = setting.value
        }
        
        if let setting = payload.lowGlucoseThreshold {
            settingsStore.lowGlucoseThreshold = setting.value
        }
        
        if let setting = payload.urgentHighThreshold {
            settingsStore.urgentHighThreshold = setting.value
        }
        
        if let setting = payload.urgentLowThreshold {
            settingsStore.urgentLowThreshold = setting.value
        }
        
        // Alerts
        if let setting = payload.highAlertEnabled {
            settingsStore.highAlertEnabled = setting.value
        }
        
        if let setting = payload.lowAlertEnabled {
            settingsStore.lowAlertEnabled = setting.value
        }
        
        if let setting = payload.urgentAlertEnabled {
            settingsStore.urgentAlertEnabled = setting.value
        }
        
        if let setting = payload.staleDataAlertEnabled {
            settingsStore.staleDataAlertEnabled = setting.value
        }
        
        if let setting = payload.staleDataMinutes {
            settingsStore.staleDataMinutes = setting.value
        }
        
        settingsStore.synchronize()
    }
    
    private func buildPolicyCache(from payload: ManagedSettingsPayload) {
        policyCache.removeAll()
        
        if let s = payload.glucoseUnit { policyCache[.glucoseUnit] = s.policy }
        if let s = payload.highGlucoseThreshold { policyCache[.highGlucoseThreshold] = s.policy }
        if let s = payload.lowGlucoseThreshold { policyCache[.lowGlucoseThreshold] = s.policy }
        if let s = payload.urgentHighThreshold { policyCache[.urgentHighThreshold] = s.policy }
        if let s = payload.urgentLowThreshold { policyCache[.urgentLowThreshold] = s.policy }
        if let s = payload.highAlertEnabled { policyCache[.highAlertEnabled] = s.policy }
        if let s = payload.lowAlertEnabled { policyCache[.lowAlertEnabled] = s.policy }
        if let s = payload.urgentAlertEnabled { policyCache[.urgentAlertEnabled] = s.policy }
        if let s = payload.staleDataAlertEnabled { policyCache[.staleDataAlertEnabled] = s.policy }
        if let s = payload.staleDataMinutes { policyCache[.staleDataMinutes] = s.policy }
        if let s = payload.targetGlucose { policyCache[.targetGlucose] = s.policy }
        if let s = payload.correctionRangeLow { policyCache[.correctionRangeLow] = s.policy }
        if let s = payload.correctionRangeHigh { policyCache[.correctionRangeHigh] = s.policy }
        if let s = payload.maxBasalRate { policyCache[.maxBasalRate] = s.policy }
        if let s = payload.maxBolus { policyCache[.maxBolus] = s.policy }
        if let s = payload.suspendThreshold { policyCache[.suspendThreshold] = s.policy }
    }
    
    private func persistSettings() {
        guard let payload = currentPayload else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadPersistedSettings() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let payload = try? ManagedSettingsPayload.parse(from: data) else {
            return
        }
        
        // Don't load expired settings
        if payload.isExpired {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        
        currentPayload = payload
        buildPolicyCache(from: payload)
    }
}

// MARK: - Errors

/// Errors during managed settings operations
public enum ManagedSettingsError: Error, LocalizedError, Sendable {
    case networkError(String)
    case fetchFailed(String)
    case parseFailed(String)
    case settingsExpired
    case versionConflict(current: Int, incoming: Int)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .fetchFailed(let detail):
            return "Could not fetch settings: \(detail)"
        case .parseFailed(let detail):
            return "Invalid settings format: \(detail)"
        case .settingsExpired:
            return "These settings have expired. Please contact your care team."
        case .versionConflict(let current, let incoming):
            return "Settings version conflict (current: \(current), incoming: \(incoming))"
        }
    }
}

// MARK: - Managed Setting Extension for Equatable

extension ManagedSettingValue: Equatable where T: Equatable {}
