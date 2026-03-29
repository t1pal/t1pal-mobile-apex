// BLEConstants.swift
// BLEKit
//
// Centralized timing constants for BLE operations.
// Extracted from PROD-HARDEN-010 audit (2026-02-20).
// Source documentation added PROD-HARDEN-014 (2026-02-21).
//
// External sources:
// - rileylink_ios/RileyLinkBLEKit/PeripheralManager.swift
// - CGMBLEKit/CGMBLEKit/Transmitter.swift
// - G7SensorKit/G7SensorKit/G7CGMManager/G7PeripheralManager.swift

import Foundation

/// BLE timing constants for scan, connect, and discovery operations.
///
/// These values are calibrated for diabetes device protocols (Dexcom G6/G7, Libre, pumps).
/// Source references included where applicable.
public enum BLETimingConstants {
    
    // MARK: - Scan Timing
    
    /// Scan polling interval for Linux BLE implementation.
    /// Used while waiting for HCI scan results.
    /// - Note: 100ms provides responsive discovery without excessive CPU usage.
    public static let linuxScanPollInterval: TimeInterval = 0.1 // 100ms
    
    /// Scan polling interval in nanoseconds for async Task.sleep.
    public static let linuxScanPollIntervalNanos: UInt64 = 100_000_000 // 100ms
    
    // MARK: - Connection Timing
    
    /// Connection timeout for CGM transmitters (G6/G7).
    /// 
    /// G6 transmitters sleep ~4.5 minutes every 5-minute cycle. The Dexcom app
    /// wakes the transmitter, so coexistence mode must wait for the full cycle.
    /// 
    /// - Source: G6-COEX-024 investigation
    /// - Note: Previous 30s timeout was too short for coexistence mode.
    public static let cgmConnectionTimeout: TimeInterval = 300 // 5 minutes
    
    /// Connection timeout in nanoseconds.
    public static let cgmConnectionTimeoutNanos: UInt64 = 300_000_000_000 // 5 minutes
    
    /// Default connection timeout for non-CGM devices.
    public static let defaultConnectionTimeout: TimeInterval = 30 // 30 seconds
    
    /// Default connection timeout in nanoseconds.
    public static let defaultConnectionTimeoutNanos: UInt64 = 30_000_000_000 // 30 seconds
    
    // MARK: - Discovery Timing
    
    /// Service discovery delay for Nightscout instance discovery.
    /// Short delay between discovery attempts to avoid flooding.
    public static let instanceDiscoveryDelay: TimeInterval = 0.2 // 200ms
    
    /// Service discovery delay in nanoseconds.
    public static let instanceDiscoveryDelayNanos: UInt64 = 200_000_000 // 200ms
    
    /// Extended discovery delay for slower services.
    public static let extendedDiscoveryDelay: TimeInterval = 0.3 // 300ms
    
    /// Extended discovery delay in nanoseconds.
    public static let extendedDiscoveryDelayNanos: UInt64 = 300_000_000 // 300ms
    
    // MARK: - Retry and Backoff
    
    /// Default retry delay for BLE operations.
    public static let defaultRetryDelay: TimeInterval = 1.0 // 1 second
    
    /// Maximum backoff delay for exponential retry.
    public static let maxBackoffDelay: TimeInterval = 60.0 // 1 minute
    
    // MARK: - Heartbeat and Keep-Alive
    
    /// Default heartbeat interval for connection monitoring.
    /// - Source: HeartbeatMonitor.swift default config
    /// - External: CGMBLEKit/Transmitter.swift:483 uses 25s keepAlive
    public static let heartbeatInterval: TimeInterval = 30.0 // 30 seconds
    
    /// Response timeout for heartbeat operations.
    public static let heartbeatResponseTimeout: TimeInterval = 5.0 // 5 seconds
}

/// CGM-specific timing constants.
///
/// These values are derived from protocol analysis and Loop/xDrip reference implementations.
public enum CGMTimingConstants {
    
    // MARK: - Dexcom G6
    
    /// G6 transmitter wake cycle duration.
    /// Transmitter wakes briefly every 5 minutes.
    public static let g6WakeCycle: TimeInterval = 300 // 5 minutes
    
    /// G6 transmitter active window within cycle.
    /// Approximately 30 seconds of each 5-minute cycle.
    public static let g6ActiveWindow: TimeInterval = 30 // 30 seconds
    
    /// G6 glucose reading interval.
    public static let g6ReadingInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Dexcom G7
    
    /// G7 glucose reading interval.
    public static let g7ReadingInterval: TimeInterval = 300 // 5 minutes
    
    /// G7 backfill request timeout.
    public static let g7BackfillTimeout: TimeInterval = 30 // 30 seconds
    
    // MARK: - Libre
    
    /// Libre 3 startup delay.
    /// Allow sensor to stabilize after connection.
    public static let libre3StartupDelay: TimeInterval = 0.1 // 100ms
    
    /// Libre 3 startup delay in nanoseconds.
    public static let libre3StartupDelayNanos: UInt64 = 100_000_000 // 100ms
    
    /// Libre glucose reading interval (1 minute for Libre 3).
    public static let libreReadingInterval: TimeInterval = 60 // 1 minute
    
    // MARK: - Cloud Polling
    
    /// Dexcom Share polling interval.
    /// - Source: DexcomShareClient.swift
    public static let dexcomSharePollInterval: TimeInterval = 300 // 5 minutes
    
    /// Dexcom Share polling interval in nanoseconds.
    public static let dexcomSharePollIntervalNanos: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes
    
    /// LibreLinkUp polling interval.
    public static let libreLinkUpPollInterval: TimeInterval = 60 // 1 minute
}

/// UI timing constants for debounce and animation.
public enum UITimingConstants {
    
    /// Short debounce for rapid UI updates.
    /// - Source: G6PairingWizardView.swift
    public static let shortDebounce: TimeInterval = 0.3 // 300ms
    
    /// Medium debounce for form validation.
    public static let mediumDebounce: TimeInterval = 0.5 // 500ms
    
    /// Long debounce for expensive operations.
    public static let longDebounce: TimeInterval = 2.0 // 2 seconds
}
