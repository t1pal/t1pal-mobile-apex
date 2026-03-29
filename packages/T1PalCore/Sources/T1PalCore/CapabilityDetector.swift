// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CapabilityDetector.swift
// T1PalCore
//
// Tier capability detection and prerequisite validation
// Backlog: ENHANCE-TIER1-001
// PRD: PRD-013-progressive-enhancement.md

import Foundation

// MARK: - App Tier

/// Progressive app tiers based on enabled capabilities
public enum AppTier: Int, Comparable, Sendable, Codable, CaseIterable {
    case demo = 0       // No authentication, demo data only
    case identity = 1   // Authenticated, Nightscout connected
    case cgm = 2        // CGM device connected
    case aid = 3        // Full AID mode enabled
    
    public static func < (lhs: AppTier, rhs: AppTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// Display name for the tier
    public var displayName: String {
        switch self {
        case .demo: return "Demo Mode"
        case .identity: return "Connected"
        case .cgm: return "CGM Active"
        case .aid: return "AID Mode"
        }
    }
    
    /// Description of what this tier provides
    public var tierDescription: String {
        switch self {
        case .demo:
            return "Explore the app with simulated data"
        case .identity:
            return "Signed in with Nightscout sync enabled"
        case .cgm:
            return "Real-time CGM data from your device"
        case .aid:
            return "Automated insulin delivery active"
        }
    }
    
    /// SF Symbol for the tier
    public var symbolName: String {
        switch self {
        case .demo: return "play.circle"
        case .identity: return "person.badge.shield.checkmark"
        case .cgm: return "waveform.path.ecg"
        case .aid: return "arrow.triangle.2.circlepath"
        }
    }
    
    /// Prerequisites required to reach this tier
    public var prerequisites: [Capability] {
        switch self {
        case .demo:
            return [] // No prerequisites
        case .identity:
            return [.authentication, .nightscoutConnection]
        case .cgm:
            return [.authentication, .nightscoutConnection, .bluetoothAccess, .cgmDevice]
        case .aid:
            return [.authentication, .nightscoutConnection, .bluetoothAccess,
                    .cgmDevice, .pumpDevice, .aidTrainingComplete]
        }
    }
}

// MARK: - Capability

/// Individual capabilities that can be detected
public enum Capability: String, Sendable, Codable, CaseIterable {
    // Identity capabilities
    case authentication = "authentication"
    case nightscoutConnection = "nightscout_connection"
    case multiDevice = "multi_device"
    
    // Device capabilities
    case bluetoothAccess = "bluetooth_access"
    case backgroundRefresh = "background_refresh"
    case notifications = "notifications"
    case healthKit = "health_kit"
    
    // CGM capabilities
    case cgmDevice = "cgm_device"
    case cgmCalibration = "cgm_calibration"
    
    // Pump capabilities
    case pumpDevice = "pump_device"
    case pumpReservoir = "pump_reservoir"
    
    // AID capabilities
    case aidTrainingComplete = "aid_training_complete"
    case aidSafetyAcknowledged = "aid_safety_acknowledged"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .authentication: return "Sign In"
        case .nightscoutConnection: return "Nightscout"
        case .multiDevice: return "Multi-Device"
        case .bluetoothAccess: return "Bluetooth"
        case .backgroundRefresh: return "Background Refresh"
        case .notifications: return "Notifications"
        case .healthKit: return "Health App"
        case .cgmDevice: return "CGM Sensor"
        case .cgmCalibration: return "Calibration"
        case .pumpDevice: return "Insulin Pump"
        case .pumpReservoir: return "Reservoir"
        case .aidTrainingComplete: return "Safety Training"
        case .aidSafetyAcknowledged: return "Safety Agreement"
        }
    }
    
    /// Description of the capability
    public var capabilityDescription: String {
        switch self {
        case .authentication:
            return "Sign in to sync your data"
        case .nightscoutConnection:
            return "Connect to your Nightscout instance"
        case .multiDevice:
            return "Use on multiple devices"
        case .bluetoothAccess:
            return "Connect to BLE devices"
        case .backgroundRefresh:
            return "Update data while app is closed"
        case .notifications:
            return "Receive glucose alerts"
        case .healthKit:
            return "Sync with Apple Health"
        case .cgmDevice:
            return "Connect CGM sensor"
        case .cgmCalibration:
            return "Calibrate sensor readings"
        case .pumpDevice:
            return "Connect insulin pump"
        case .pumpReservoir:
            return "Monitor reservoir level"
        case .aidTrainingComplete:
            return "Complete safety training"
        case .aidSafetyAcknowledged:
            return "Acknowledge safety requirements"
        }
    }
    
    /// Which tier requires this capability
    public var requiredForTier: AppTier {
        switch self {
        case .authentication, .nightscoutConnection:
            return .identity
        case .multiDevice:
            return .identity
        case .bluetoothAccess, .notifications, .backgroundRefresh:
            return .cgm
        case .cgmDevice, .cgmCalibration, .healthKit:
            return .cgm
        case .pumpDevice, .pumpReservoir:
            return .aid
        case .aidTrainingComplete, .aidSafetyAcknowledged:
            return .aid
        }
    }
}

// MARK: - Capability Status

/// Status of a capability check
public struct CapabilityStatus: Sendable, Equatable {
    public let capability: Capability
    public let isAvailable: Bool
    public let reason: String?
    public let canRequest: Bool
    
    public init(
        capability: Capability,
        isAvailable: Bool,
        reason: String? = nil,
        canRequest: Bool = false
    ) {
        self.capability = capability
        self.isAvailable = isAvailable
        self.reason = reason
        self.canRequest = canRequest
    }
    
    /// Status indicating capability is available
    public static func available(_ capability: Capability) -> CapabilityStatus {
        CapabilityStatus(capability: capability, isAvailable: true)
    }
    
    /// Status indicating capability is not available
    public static func unavailable(
        _ capability: Capability,
        reason: String,
        canRequest: Bool = false
    ) -> CapabilityStatus {
        CapabilityStatus(
            capability: capability,
            isAvailable: false,
            reason: reason,
            canRequest: canRequest
        )
    }
}

// MARK: - Capability Detector Protocol

/// Protocol for capability detection
public protocol CapabilityDetectorProtocol: Sendable {
    /// Detect the current app tier based on available capabilities
    func detectCurrentTier() async -> AppTier
    
    /// Check a specific capability
    func checkCapability(_ capability: Capability) async -> CapabilityStatus
    
    /// Check all prerequisites for a tier
    func checkPrerequisites(for tier: AppTier) async -> [CapabilityStatus]
    
    /// Check if a tier is achievable (all prerequisites can be satisfied)
    func canAchieveTier(_ tier: AppTier) async -> Bool
    
    /// Get missing capabilities to reach a tier
    func missingCapabilities(for tier: AppTier) async -> [Capability]
}

// MARK: - Live Capability Detector

/// Live implementation checking real device/app state
public actor LiveCapabilityDetector: CapabilityDetectorProtocol {
    private let authProvider: IdentityProvider?
    private let sessionManager: SessionManagerProtocol?
    private let userDefaults: UserDefaults
    
    /// Cached capability statuses
    private var cache: [Capability: CachedStatus] = [:]
    private let cacheDuration: TimeInterval = 60 // 1 minute
    
    private struct CachedStatus {
        let status: CapabilityStatus
        let timestamp: Date
    }
    
    public init(
        authProvider: IdentityProvider? = nil,
        sessionManager: SessionManagerProtocol? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.authProvider = authProvider
        self.sessionManager = sessionManager
        self.userDefaults = userDefaults
    }
    
    public func detectCurrentTier() async -> AppTier {
        // Check tiers in reverse order (highest first)
        for tier in AppTier.allCases.reversed() {
            let prerequisites = await checkPrerequisites(for: tier)
            let allMet = prerequisites.allSatisfy { $0.isAvailable }
            if allMet {
                return tier
            }
        }
        return .demo
    }
    
    public func checkCapability(_ capability: Capability) async -> CapabilityStatus {
        // Check cache
        if let cached = cache[capability] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheDuration {
                return cached.status
            }
        }
        
        let status = await performCheck(capability)
        cache[capability] = CachedStatus(status: status, timestamp: Date())
        return status
    }
    
    public func checkPrerequisites(for tier: AppTier) async -> [CapabilityStatus] {
        var results: [CapabilityStatus] = []
        for capability in tier.prerequisites {
            let status = await checkCapability(capability)
            results.append(status)
        }
        return results
    }
    
    public func canAchieveTier(_ tier: AppTier) async -> Bool {
        let statuses = await checkPrerequisites(for: tier)
        // A tier is achievable if all unavailable capabilities can be requested
        return statuses.allSatisfy { $0.isAvailable || $0.canRequest }
    }
    
    public func missingCapabilities(for tier: AppTier) async -> [Capability] {
        let statuses = await checkPrerequisites(for: tier)
        return statuses.filter { !$0.isAvailable }.map { $0.capability }
    }
    
    /// Clear the capability cache
    public func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - Private Checks
    
    private func performCheck(_ capability: Capability) async -> CapabilityStatus {
        switch capability {
        case .authentication:
            return await checkAuthentication()
        case .nightscoutConnection:
            return await checkNightscoutConnection()
        case .multiDevice:
            return await checkMultiDevice()
        case .bluetoothAccess:
            return checkBluetooth()
        case .backgroundRefresh:
            return checkBackgroundRefresh()
        case .notifications:
            return checkNotifications()
        case .healthKit:
            return checkHealthKit()
        case .cgmDevice:
            return checkCGMDevice()
        case .cgmCalibration:
            return checkCGMCalibration()
        case .pumpDevice:
            return checkPumpDevice()
        case .pumpReservoir:
            return checkPumpReservoir()
        case .aidTrainingComplete:
            return checkAIDTraining()
        case .aidSafetyAcknowledged:
            return checkAIDSafety()
        }
    }
    
    private func checkAuthentication() async -> CapabilityStatus {
        guard let provider = authProvider else {
            return .unavailable(.authentication, reason: "Auth not configured", canRequest: true)
        }
        
        let isLoggedIn = await provider.isAuthenticated()
        if isLoggedIn {
            return .available(.authentication)
        } else {
            return .unavailable(.authentication, reason: "Not signed in", canRequest: true)
        }
    }
    
    private func checkNightscoutConnection() async -> CapabilityStatus {
        // Check if we have a stored Nightscout URL
        let hasURL = userDefaults.string(forKey: "nightscout_url") != nil
        if hasURL {
            return .available(.nightscoutConnection)
        }
        return .unavailable(.nightscoutConnection, reason: "No Nightscout configured", canRequest: true)
    }
    
    private func checkMultiDevice() async -> CapabilityStatus {
        guard let manager = sessionManager else {
            return .unavailable(.multiDevice, reason: "Session manager not configured")
        }
        
        let session = await manager.getCurrentSession()
        if session != nil {
            return .available(.multiDevice)
        }
        return .unavailable(.multiDevice, reason: "Device not registered", canRequest: true)
    }
    
    private func checkBluetooth() -> CapabilityStatus {
        // In a real implementation, check CBCentralManager.authorization
        let authorized = userDefaults.bool(forKey: "bluetooth_authorized")
        if authorized {
            return .available(.bluetoothAccess)
        }
        return .unavailable(.bluetoothAccess, reason: "Bluetooth access not granted", canRequest: true)
    }
    
    private func checkBackgroundRefresh() -> CapabilityStatus {
        // Check UIApplication.shared.backgroundRefreshStatus in real implementation
        let enabled = userDefaults.bool(forKey: "background_refresh_enabled")
        if enabled {
            return .available(.backgroundRefresh)
        }
        return .unavailable(.backgroundRefresh, reason: "Background refresh disabled", canRequest: true)
    }
    
    private func checkNotifications() -> CapabilityStatus {
        let authorized = userDefaults.bool(forKey: "notifications_authorized")
        if authorized {
            return .available(.notifications)
        }
        return .unavailable(.notifications, reason: "Notifications not enabled", canRequest: true)
    }
    
    private func checkHealthKit() -> CapabilityStatus {
        let authorized = userDefaults.bool(forKey: "healthkit_authorized")
        if authorized {
            return .available(.healthKit)
        }
        return .unavailable(.healthKit, reason: "Health access not granted", canRequest: true)
    }
    
    private func checkCGMDevice() -> CapabilityStatus {
        let connected = userDefaults.bool(forKey: "cgm_connected")
        if connected {
            return .available(.cgmDevice)
        }
        return .unavailable(.cgmDevice, reason: "No CGM connected", canRequest: true)
    }
    
    private func checkCGMCalibration() -> CapabilityStatus {
        // Most modern CGMs don't need calibration
        return .available(.cgmCalibration)
    }
    
    private func checkPumpDevice() -> CapabilityStatus {
        let connected = userDefaults.bool(forKey: "pump_connected")
        if connected {
            return .available(.pumpDevice)
        }
        return .unavailable(.pumpDevice, reason: "No pump connected", canRequest: true)
    }
    
    private func checkPumpReservoir() -> CapabilityStatus {
        let hasReservoir = userDefaults.bool(forKey: "pump_has_reservoir")
        if hasReservoir {
            return .available(.pumpReservoir)
        }
        return .unavailable(.pumpReservoir, reason: "Reservoir not detected")
    }
    
    private func checkAIDTraining() -> CapabilityStatus {
        let completed = userDefaults.bool(forKey: "aid_training_complete")
        if completed {
            return .available(.aidTrainingComplete)
        }
        return .unavailable(.aidTrainingComplete, reason: "Training not completed", canRequest: true)
    }
    
    private func checkAIDSafety() -> CapabilityStatus {
        let acknowledged = userDefaults.bool(forKey: "aid_safety_acknowledged")
        if acknowledged {
            return .available(.aidSafetyAcknowledged)
        }
        return .unavailable(.aidSafetyAcknowledged, reason: "Safety not acknowledged", canRequest: true)
    }
}

// MARK: - Mock Capability Detector

/// Mock implementation for testing
public actor MockCapabilityDetector: CapabilityDetectorProtocol {
    private var capabilities: [Capability: CapabilityStatus] = [:]
    public private(set) var checkCount = 0
    
    public init() {
        // Start with demo tier capabilities
        for capability in Capability.allCases {
            capabilities[capability] = .unavailable(capability, reason: "Not configured", canRequest: true)
        }
    }
    
    /// Set a capability's status
    public func setCapability(_ capability: Capability, available: Bool) {
        if available {
            capabilities[capability] = .available(capability)
        } else {
            capabilities[capability] = .unavailable(capability, reason: "Not available", canRequest: true)
        }
    }
    
    /// Enable all capabilities for a tier
    public func enableTier(_ tier: AppTier) {
        for capability in tier.prerequisites {
            capabilities[capability] = .available(capability)
        }
    }
    
    public func detectCurrentTier() async -> AppTier {
        for tier in AppTier.allCases.reversed() {
            let prerequisites = await checkPrerequisites(for: tier)
            if prerequisites.allSatisfy({ $0.isAvailable }) {
                return tier
            }
        }
        return .demo
    }
    
    public func checkCapability(_ capability: Capability) async -> CapabilityStatus {
        checkCount += 1
        return capabilities[capability] ?? .unavailable(capability, reason: "Unknown")
    }
    
    public func checkPrerequisites(for tier: AppTier) async -> [CapabilityStatus] {
        tier.prerequisites.map { capabilities[$0] ?? .unavailable($0, reason: "Unknown") }
    }
    
    public func canAchieveTier(_ tier: AppTier) async -> Bool {
        let statuses = await checkPrerequisites(for: tier)
        return statuses.allSatisfy { $0.isAvailable || $0.canRequest }
    }
    
    public func missingCapabilities(for tier: AppTier) async -> [Capability] {
        let statuses = await checkPrerequisites(for: tier)
        return statuses.filter { !$0.isAvailable }.map { $0.capability }
    }
}

// MARK: - Tier Progress

/// Progress toward achieving a tier
public struct TierProgress: Sendable {
    public let targetTier: AppTier
    public let completedCapabilities: [Capability]
    public let missingCapabilities: [Capability]
    public let progress: Double // 0.0 to 1.0
    
    public init(
        targetTier: AppTier,
        completedCapabilities: [Capability],
        missingCapabilities: [Capability]
    ) {
        self.targetTier = targetTier
        self.completedCapabilities = completedCapabilities
        self.missingCapabilities = missingCapabilities
        
        let total = completedCapabilities.count + missingCapabilities.count
        self.progress = total > 0 ? Double(completedCapabilities.count) / Double(total) : 1.0
    }
    
    /// Check if tier is complete
    public var isComplete: Bool {
        missingCapabilities.isEmpty
    }
    
    /// Next capability to complete
    public var nextStep: Capability? {
        missingCapabilities.first
    }
}

// MARK: - Tier Progress Calculator

/// Calculates progress toward tiers
public actor TierProgressCalculator {
    private let detector: CapabilityDetectorProtocol
    
    public init(detector: CapabilityDetectorProtocol) {
        self.detector = detector
    }
    
    /// Calculate progress toward a specific tier
    public func progress(for tier: AppTier) async -> TierProgress {
        let statuses = await detector.checkPrerequisites(for: tier)
        
        let completed = statuses.filter { $0.isAvailable }.map { $0.capability }
        let missing = statuses.filter { !$0.isAvailable }.map { $0.capability }
        
        return TierProgress(
            targetTier: tier,
            completedCapabilities: completed,
            missingCapabilities: missing
        )
    }
    
    /// Calculate progress for all tiers
    public func allTierProgress() async -> [AppTier: TierProgress] {
        var results: [AppTier: TierProgress] = [:]
        for tier in AppTier.allCases {
            results[tier] = await progress(for: tier)
        }
        return results
    }
    
    /// Get the next achievable tier
    public func nextAchievableTier() async -> AppTier? {
        let current = await detector.detectCurrentTier()
        
        for tier in AppTier.allCases where tier > current {
            if await detector.canAchieveTier(tier) {
                return tier
            }
        }
        
        return nil
    }
}
