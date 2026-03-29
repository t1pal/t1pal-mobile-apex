// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMCapabilityGate.swift
// T1PalCore
//
// CGM tier detection and permission gates
// Backlog: ENHANCE-TIER2-001
// PRD: PRD-013-progressive-enhancement.md

import Foundation

// MARK: - Bluetooth Permission Status

/// Bluetooth permission states
public enum BluetoothPermissionStatus: String, Sendable, Equatable {
    case notDetermined = "not_determined"
    case authorized = "authorized"
    case denied = "denied"
    case restricted = "restricted"
    case unsupported = "unsupported"
    
    /// Whether Bluetooth is usable
    public var isUsable: Bool {
        self == .authorized
    }
    
    /// Whether permission can be requested
    public var canRequest: Bool {
        self == .notDetermined
    }
    
    /// Display description
    public var displayDescription: String {
        switch self {
        case .notDetermined:
            return "Bluetooth permission not requested"
        case .authorized:
            return "Bluetooth access granted"
        case .denied:
            return "Bluetooth access denied"
        case .restricted:
            return "Bluetooth restricted by device policy"
        case .unsupported:
            return "Bluetooth not supported on this device"
        }
    }
}

// MARK: - CGM Connection Status

/// CGM connection states for tier 2 detection
public enum CGMConnectionStatus: String, Sendable, Equatable {
    case disconnected = "disconnected"
    case scanning = "scanning"
    case connecting = "connecting"
    case connected = "connected"
    case streaming = "streaming"
    
    /// Whether actively receiving data
    public var isReceivingData: Bool {
        self == .connected || self == .streaming
    }
    
    /// Display description
    public var displayDescription: String {
        switch self {
        case .disconnected:
            return "CGM not connected"
        case .scanning:
            return "Scanning for CGM"
        case .connecting:
            return "Connecting to CGM"
        case .connected:
            return "CGM connected"
        case .streaming:
            return "Receiving CGM data"
        }
    }
}

// MARK: - CGM Data Freshness

/// Freshness of CGM data
public struct CGMDataFreshness: Sendable, Equatable {
    public let lastReadingDate: Date?
    public let checkDate: Date
    
    /// Maximum age for data to be considered fresh (5 minutes)
    public static let freshThreshold: TimeInterval = 300
    
    /// Maximum age for data to be considered stale but usable (15 minutes)
    public static let staleThreshold: TimeInterval = 900
    
    public init(lastReadingDate: Date?, checkDate: Date = Date()) {
        self.lastReadingDate = lastReadingDate
        self.checkDate = checkDate
    }
    
    /// Age of the last reading in seconds
    public var ageSeconds: TimeInterval? {
        guard let lastReadingDate else { return nil }
        return checkDate.timeIntervalSince(lastReadingDate)
    }
    
    /// Whether data is fresh (within 5 minutes)
    public var isFresh: Bool {
        guard let age = ageSeconds else { return false }
        return age <= Self.freshThreshold
    }
    
    /// Whether data is stale but usable (5-15 minutes)
    public var isStale: Bool {
        guard let age = ageSeconds else { return false }
        return age > Self.freshThreshold && age <= Self.staleThreshold
    }
    
    /// Whether data is too old (over 15 minutes)
    public var isExpired: Bool {
        guard let age = ageSeconds else { return true }
        return age > Self.staleThreshold
    }
    
    /// Freshness level for display
    public var freshnessLevel: FreshnessLevel {
        if isFresh { return .fresh }
        if isStale { return .stale }
        return .expired
    }
    
    public enum FreshnessLevel: String, Sendable {
        case fresh = "fresh"
        case stale = "stale"
        case expired = "expired"
        
        public var symbolName: String {
            switch self {
            case .fresh: return "checkmark.circle.fill"
            case .stale: return "exclamationmark.triangle.fill"
            case .expired: return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - CGM Capability Gate

/// Tier 2 (CGM) capability detection and gates
public protocol CGMCapabilityGateProtocol: Sendable {
    /// Check Bluetooth permission status
    func checkBluetoothPermission() async -> BluetoothPermissionStatus
    
    /// Check CGM connection status
    func checkCGMConnection() async -> CGMConnectionStatus
    
    /// Check CGM data freshness
    func checkDataFreshness() async -> CGMDataFreshness
    
    /// Check if all tier 2 requirements are met
    func isTier2Ready() async -> Bool
    
    /// Get detailed tier 2 status
    func getTier2Status() async -> CGMTierStatus
}

// MARK: - CGM Tier Status

/// Detailed status for tier 2 readiness
public struct CGMTierStatus: Sendable, Equatable {
    public let bluetoothStatus: BluetoothPermissionStatus
    public let connectionStatus: CGMConnectionStatus
    public let dataFreshness: CGMDataFreshness
    public let isReady: Bool
    public let blockers: [CGMBlocker]
    
    public init(
        bluetoothStatus: BluetoothPermissionStatus,
        connectionStatus: CGMConnectionStatus,
        dataFreshness: CGMDataFreshness
    ) {
        self.bluetoothStatus = bluetoothStatus
        self.connectionStatus = connectionStatus
        self.dataFreshness = dataFreshness
        
        var blockers: [CGMBlocker] = []
        
        if !bluetoothStatus.isUsable {
            blockers.append(.bluetoothPermission(bluetoothStatus))
        }
        
        if !connectionStatus.isReceivingData {
            blockers.append(.cgmConnection(connectionStatus))
        }
        
        if dataFreshness.isExpired {
            blockers.append(.dataFreshness(dataFreshness.freshnessLevel))
        }
        
        self.blockers = blockers
        self.isReady = blockers.isEmpty
    }
    
    /// First blocker to address
    public var primaryBlocker: CGMBlocker? {
        blockers.first
    }
    
    /// User-facing message for current state
    public var statusMessage: String {
        if isReady {
            return "CGM tier active"
        }
        return primaryBlocker?.userMessage ?? "CGM not ready"
    }
}

// MARK: - CGM Blocker

/// Specific blockers preventing tier 2 activation
public enum CGMBlocker: Sendable, Equatable {
    case bluetoothPermission(BluetoothPermissionStatus)
    case cgmConnection(CGMConnectionStatus)
    case dataFreshness(CGMDataFreshness.FreshnessLevel)
    
    /// User-facing message
    public var userMessage: String {
        switch self {
        case .bluetoothPermission(let status):
            return status.displayDescription
        case .cgmConnection(let status):
            return status.displayDescription
        case .dataFreshness(let level):
            switch level {
            case .fresh: return "CGM data is current"
            case .stale: return "CGM data is stale"
            case .expired: return "CGM data is expired"
            }
        }
    }
    
    /// Action user can take
    public var actionPrompt: String {
        switch self {
        case .bluetoothPermission(let status):
            if status.canRequest {
                return "Enable Bluetooth access"
            } else if status == .denied {
                return "Open Settings to enable Bluetooth"
            }
            return "Bluetooth unavailable"
        case .cgmConnection:
            return "Connect your CGM device"
        case .dataFreshness:
            return "Check CGM sensor connection"
        }
    }
    
    /// Whether this blocker can be resolved by user action
    public var isResolvable: Bool {
        switch self {
        case .bluetoothPermission(let status):
            return status.canRequest || status == .denied
        case .cgmConnection:
            return true
        case .dataFreshness:
            return true
        }
    }
}

// MARK: - Live CGM Capability Gate

/// Live implementation checking real device state
public actor LiveCGMCapabilityGate: CGMCapabilityGateProtocol {
    private let bluetoothChecker: BluetoothPermissionCheckerProtocol
    private let connectionProvider: CGMConnectionStatusProviderProtocol
    private let freshnessProvider: CGMDataFreshnessProviderProtocol
    
    public init(
        bluetoothChecker: BluetoothPermissionCheckerProtocol? = nil,
        connectionProvider: CGMConnectionStatusProviderProtocol? = nil,
        freshnessProvider: CGMDataFreshnessProviderProtocol? = nil
    ) {
        self.bluetoothChecker = bluetoothChecker ?? DefaultBluetoothPermissionChecker()
        self.connectionProvider = connectionProvider ?? DefaultCGMConnectionStatusProvider()
        self.freshnessProvider = freshnessProvider ?? DefaultCGMDataFreshnessProvider()
    }
    
    public func checkBluetoothPermission() async -> BluetoothPermissionStatus {
        await bluetoothChecker.checkPermission()
    }
    
    public func checkCGMConnection() async -> CGMConnectionStatus {
        await connectionProvider.getCurrentStatus()
    }
    
    public func checkDataFreshness() async -> CGMDataFreshness {
        await freshnessProvider.checkFreshness()
    }
    
    public func isTier2Ready() async -> Bool {
        let status = await getTier2Status()
        return status.isReady
    }
    
    public func getTier2Status() async -> CGMTierStatus {
        let bluetooth = await checkBluetoothPermission()
        let connection = await checkCGMConnection()
        let freshness = await checkDataFreshness()
        
        return CGMTierStatus(
            bluetoothStatus: bluetooth,
            connectionStatus: connection,
            dataFreshness: freshness
        )
    }
}

// MARK: - Mock CGM Capability Gate

/// Mock implementation for testing
public actor MockCGMCapabilityGate: CGMCapabilityGateProtocol {
    public var bluetoothStatus: BluetoothPermissionStatus = .notDetermined
    public var connectionStatus: CGMConnectionStatus = .disconnected
    public var lastReadingDate: Date? = nil
    
    public private(set) var checkCount = 0
    
    public init() {}
    
    /// Configure mock for a specific tier 2 state
    public func configure(
        bluetooth: BluetoothPermissionStatus,
        connection: CGMConnectionStatus,
        lastReading: Date?
    ) {
        self.bluetoothStatus = bluetooth
        self.connectionStatus = connection
        self.lastReadingDate = lastReading
    }
    
    /// Configure for tier 2 ready state
    public func enableTier2() {
        self.bluetoothStatus = .authorized
        self.connectionStatus = .streaming
        self.lastReadingDate = Date()
    }
    
    public func checkBluetoothPermission() async -> BluetoothPermissionStatus {
        checkCount += 1
        return bluetoothStatus
    }
    
    public func checkCGMConnection() async -> CGMConnectionStatus {
        checkCount += 1
        return connectionStatus
    }
    
    public func checkDataFreshness() async -> CGMDataFreshness {
        checkCount += 1
        return CGMDataFreshness(lastReadingDate: lastReadingDate)
    }
    
    public func isTier2Ready() async -> Bool {
        let status = await getTier2Status()
        return status.isReady
    }
    
    public func getTier2Status() async -> CGMTierStatus {
        CGMTierStatus(
            bluetoothStatus: bluetoothStatus,
            connectionStatus: connectionStatus,
            dataFreshness: CGMDataFreshness(lastReadingDate: lastReadingDate)
        )
    }
}

// MARK: - Bluetooth Permission Checker Protocol

/// Protocol for checking Bluetooth permission
public protocol BluetoothPermissionCheckerProtocol: Sendable {
    func checkPermission() async -> BluetoothPermissionStatus
}

/// Default implementation using UserDefaults (real would use CBCentralManager)
public struct DefaultBluetoothPermissionChecker: BluetoothPermissionCheckerProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func checkPermission() async -> BluetoothPermissionStatus {
        // In real implementation: check CBCentralManager.authorization
        // For now, read from UserDefaults
        if let rawValue = userDefaults.string(forKey: "bluetooth_permission_status"),
           let status = BluetoothPermissionStatus(rawValue: rawValue) {
            return status
        }
        
        // Check legacy key
        if userDefaults.bool(forKey: "bluetooth_authorized") {
            return .authorized
        }
        
        return .notDetermined
    }
}

// MARK: - CGM Connection Status Provider Protocol

/// Protocol for checking CGM connection status
public protocol CGMConnectionStatusProviderProtocol: Sendable {
    func getCurrentStatus() async -> CGMConnectionStatus
}

/// Default implementation using UserDefaults
public struct DefaultCGMConnectionStatusProvider: CGMConnectionStatusProviderProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func getCurrentStatus() async -> CGMConnectionStatus {
        if let rawValue = userDefaults.string(forKey: "cgm_connection_status"),
           let status = CGMConnectionStatus(rawValue: rawValue) {
            return status
        }
        
        // Check legacy key
        if userDefaults.bool(forKey: "cgm_connected") {
            return .connected
        }
        
        return .disconnected
    }
}

// MARK: - CGM Data Freshness Provider Protocol

/// Protocol for checking CGM data freshness
public protocol CGMDataFreshnessProviderProtocol: Sendable {
    func checkFreshness() async -> CGMDataFreshness
}

/// Default implementation using UserDefaults
public struct DefaultCGMDataFreshnessProvider: CGMDataFreshnessProviderProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func checkFreshness() async -> CGMDataFreshness {
        let lastReadingInterval = userDefaults.double(forKey: "cgm_last_reading_timestamp")
        
        if lastReadingInterval > 0 {
            let lastReadingDate = Date(timeIntervalSince1970: lastReadingInterval)
            return CGMDataFreshness(lastReadingDate: lastReadingDate)
        }
        
        return CGMDataFreshness(lastReadingDate: nil)
    }
}

// MARK: - CGM Tier Progress Extension

/// Extension to integrate with TierProgressCalculator
public extension CGMTierStatus {
    /// Convert to capability statuses for tier progress tracking
    var capabilityStatuses: [CapabilityStatus] {
        var statuses: [CapabilityStatus] = []
        
        // Bluetooth access
        if bluetoothStatus.isUsable {
            statuses.append(.available(.bluetoothAccess))
        } else {
            statuses.append(.unavailable(
                .bluetoothAccess,
                reason: bluetoothStatus.displayDescription,
                canRequest: bluetoothStatus.canRequest
            ))
        }
        
        // CGM device
        if connectionStatus.isReceivingData {
            statuses.append(.available(.cgmDevice))
        } else {
            statuses.append(.unavailable(
                .cgmDevice,
                reason: connectionStatus.displayDescription,
                canRequest: true
            ))
        }
        
        return statuses
    }
}
