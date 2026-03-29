// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEScannable.swift
// BLEKit
//
// Common protocol and helpers for BLE device scanning.
// Reduces duplication across CGMKit and PumpKit managers.
// Trace: COMPL-DUP-003, PRD-008

import Foundation

// MARK: - BLE Scannable Protocol

/// Protocol for types that can scan for BLE devices
///
/// Provides a common interface for device scanning across different
/// BLE managers (CGM, pump, etc.). Implementations handle device-specific
/// filtering and processing.
///
/// The protocol uses optional methods with default implementations to
/// accommodate different manager signatures (sync vs async).
///
/// Example conformance:
/// ```swift
/// extension RileyLinkManager: BLEScannable {
///     public var isScanning: Bool { state == .scanning }
///     // Existing startScanning/stopScanning methods satisfy protocol
/// }
/// ```
///
/// Trace: COMPL-DUP-003
public protocol BLEScannable: Sendable {
    /// Whether scanning is currently active
    var isScanning: Bool { get }
}

/// Extended scanning protocol with async methods
/// Use when you need to call scanning methods through a protocol reference
public protocol BLEScannableAsync: BLEScannable {
    /// Start scanning for devices
    /// - Throws: BLEError if scanning cannot start
    func startScanning() async throws
    
    /// Stop scanning
    func stopScanning() async
}

/// Extended scanning protocol with sync methods
/// Use when you need to call sync scanning methods through a protocol reference
public protocol BLEScannableSync: BLEScannable {
    /// Start scanning for devices (sync version)
    func startScanning()
    
    /// Stop scanning (sync version)
    func stopScanning()
}

// MARK: - Scan Controller

/// Reusable scan state machine for BLE managers
///
/// Encapsulates common scanning lifecycle patterns:
/// - State guard (only scan when disconnected)
/// - Task management (cancel previous scan)
/// - Timeout handling
///
/// Usage:
/// ```swift
/// actor MyBLEManager {
///     private var scanController = BLEScanController()
///
///     func startScanning() async throws {
///         try scanController.startScan(
///             guard: state == .disconnected,
///             onStart: { self.state = .scanning }
///         )
///         // ... begin actual scan
///     }
///
///     func stopScanning() async {
///         scanController.stopScan(onStop: { self.state = .disconnected })
///     }
/// }
/// ```
///
/// Trace: COMPL-DUP-003
public final class BLEScanController: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Current scan task
    private var scanTask: Task<Void, Never>?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Whether scanning is active
    public private(set) var isScanning: Bool = false
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Scan Lifecycle
    
    /// Start scanning with guard check
    ///
    /// - Parameters:
    ///   - guard: Condition that must be true to start scanning
    ///   - onStart: Called when scan starts (update state here)
    /// - Throws: BLEScanError.alreadyScanning if guard fails
    public func startScan(
        guard condition: Bool,
        onStart: @escaping () -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard condition else {
            throw BLEScanError.alreadyScanning
        }
        
        // Cancel any existing scan
        scanTask?.cancel()
        scanTask = nil
        
        isScanning = true
        onStart()
    }
    
    /// Start scanning (unconditionally)
    ///
    /// - Parameter onStart: Called when scan starts
    public func startScanUnconditionally(onStart: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        scanTask?.cancel()
        scanTask = nil
        
        isScanning = true
        onStart()
    }
    
    /// Register the scan task for cancellation management
    ///
    /// - Parameter task: The scan task to manage
    public func setScanTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        scanTask = task
    }
    
    /// Stop scanning
    ///
    /// - Parameter onStop: Called when scan stops (update state here)
    public func stopScan(onStop: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        scanTask?.cancel()
        scanTask = nil
        
        if isScanning {
            isScanning = false
            onStop()
        }
    }
    
    /// Mark scan as complete (for self-terminating scans)
    public func scanComplete() {
        lock.lock()
        defer { lock.unlock() }
        
        scanTask = nil
        isScanning = false
    }
    
    /// Cancel scan task without state change callback
    public func cancelScanTask() {
        lock.lock()
        defer { lock.unlock() }
        
        scanTask?.cancel()
        scanTask = nil
    }
}

// MARK: - Scan Error

/// Errors that can occur during BLE scanning
public enum BLEScanError: Error, Sendable, CustomStringConvertible {
    /// Already scanning or in wrong state
    case alreadyScanning
    
    /// Scan timed out
    case timeout(TimeInterval)
    
    /// BLE not available
    case bleUnavailable(String)
    
    public var description: String {
        switch self {
        case .alreadyScanning:
            return "Already scanning or not in correct state"
        case .timeout(let seconds):
            return "Scan timed out after \(seconds) seconds"
        case .bleUnavailable(let reason):
            return "BLE unavailable: \(reason)"
        }
    }
}

// MARK: - Scan Configuration

/// Configuration for BLE scanning
public struct BLEScanConfiguration: Sendable {
    /// Service UUIDs to scan for (nil = all devices)
    public let serviceUUIDs: [BLEUUID]?
    
    /// Scan timeout (nil = no timeout)
    public let timeout: TimeInterval?
    
    /// Whether to allow duplicate advertisements
    public let allowDuplicates: Bool
    
    /// Default configuration
    public static let `default` = BLEScanConfiguration(
        serviceUUIDs: nil,
        timeout: 30.0,
        allowDuplicates: false
    )
    
    public init(
        serviceUUIDs: [BLEUUID]? = nil,
        timeout: TimeInterval? = 30.0,
        allowDuplicates: Bool = false
    ) {
        self.serviceUUIDs = serviceUUIDs
        self.timeout = timeout
        self.allowDuplicates = allowDuplicates
    }
}

// MARK: - Scan Result Wrapper

/// Generic wrapper for scan results
public struct BLEDiscoveredDevice<DeviceInfo: Sendable>: Sendable {
    /// Device-specific info
    public let device: DeviceInfo
    
    /// Signal strength
    public let rssi: Int
    
    /// Discovery timestamp
    public let discoveredAt: Date
    
    public init(device: DeviceInfo, rssi: Int, discoveredAt: Date = Date()) {
        self.device = device
        self.rssi = rssi
        self.discoveredAt = discoveredAt
    }
}
