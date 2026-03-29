// PumpTimingConstants.swift
// PumpKit
//
// Centralized timing constants for pump operations.
// Extracted from PROD-HARDEN-011 audit (2026-02-20).
// Source documentation added PROD-HARDEN-014 (2026-02-21).
//
// External sources:
// - rileylink_ios/RileyLinkBLEKit/PeripheralManager.swift (BLE timing)
// - rileylink_ios/MinimedKit/PumpOps*.swift (Medtronic timing)
// - LoopWorkspaceApex/OmniBLE (DASH timing)
// - LoopWorkspaceApex/OmniKit (Eros timing)

import Foundation

/// Pump timing constants for RF communication, polling, and command execution.
///
/// These values are calibrated for diabetes pump protocols (Medtronic, Omnipod, Dana, Tandem).
/// Source references included where applicable.
public enum PumpTimingConstants {
    
    // MARK: - RileyLink RF Communication
    
    /// Polling interval for responseCount characteristic.
    /// Used when waiting for pump RF response via BLE notification.
    /// - Source: RileyLinkManager.swift line 1016
    /// - External: rileylink_ios/RileyLinkBLEKit/PeripheralManager.swift:153 (discoveryTimeout: 2)
    public static let responseCountPollInterval: TimeInterval = 0.05 // 50ms
    
    /// Polling interval in nanoseconds.
    public static let responseCountPollIntervalNanos: UInt64 = 50_000_000 // 50ms
    
    /// Fallback polling interval for data characteristic.
    /// Used when BLE notifications aren't available.
    /// - Source: RileyLinkManager.swift line 1028
    public static let dataCharPollInterval: TimeInterval = 0.1 // 100ms
    
    /// Fallback polling interval in nanoseconds.
    public static let dataCharPollIntervalNanos: UInt64 = 100_000_000 // 100ms
    
    // MARK: - Medtronic Timing
    
    /// Medtronic pump wake timeout.
    /// Time to wait for pump to respond to wake sequence.
    public static let medtronicWakeTimeout: TimeInterval = 3.0 // 3 seconds
    
    /// Medtronic command response timeout.
    /// Maximum time to wait for pump command response.
    public static let medtronicCommandTimeout: TimeInterval = 5.0 // 5 seconds
    
    /// Medtronic history page read timeout.
    /// History pages require longer timeout due to data transfer size.
    public static let medtronicHistoryTimeout: TimeInterval = 10.0 // 10 seconds
    
    /// Medtronic pump sleep cycle.
    /// Pump enters low-power mode after this period of inactivity.
    public static let medtronicSleepCycle: TimeInterval = 60.0 // 1 minute
    
    /// Post-wakeup settling delay.
    /// Brief pause after wakeup sequence before sending commands.
    /// - Source: Loop usleep(200000) after wakeup response
    /// - Trace: PROD-HARDEN-021
    public static let postWakeupDelay: TimeInterval = 0.2 // 200ms
    
    /// Post-wakeup settling delay in nanoseconds.
    public static let postWakeupDelayNanos: UInt64 = 200_000_000 // 200ms
    
    /// Retry backoff delay between command attempts.
    /// - Trace: PROD-HARDEN-021
    public static let retryBackoffDelay: TimeInterval = 0.05 // 50ms
    
    /// Retry backoff delay in nanoseconds.
    public static let retryBackoffDelayNanos: UInt64 = 50_000_000 // 50ms
    
    // MARK: - Omnipod Eros Timing
    
    /// Eros pod discovery delay.
    /// Delay between discovery attempts.
    /// - Source: ErosBLEManager.swift line 272
    public static let erosDiscoveryDelay: TimeInterval = 0.5 // 500ms
    
    /// Eros discovery delay in nanoseconds.
    public static let erosDiscoveryDelayNanos: UInt64 = 500_000_000 // 500ms
    
    /// Eros command timeout.
    /// Maximum time to wait for pod response.
    public static let erosCommandTimeout: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Omnipod DASH Timing
    
    /// DASH pod Bluetooth connection timeout.
    public static let dashConnectionTimeout: TimeInterval = 30.0 // 30 seconds
    
    /// DASH command timeout.
    public static let dashCommandTimeout: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Dana Timing
    
    /// Dana pump connection timeout.
    public static let danaConnectionTimeout: TimeInterval = 30.0 // 30 seconds
    
    /// Dana command timeout.
    public static let danaCommandTimeout: TimeInterval = 10.0 // 10 seconds
    
    // MARK: - Tandem Timing
    
    /// Tandem X2 connection timeout.
    public static let tandemConnectionTimeout: TimeInterval = 30.0 // 30 seconds
    
    /// Tandem command timeout.
    public static let tandemCommandTimeout: TimeInterval = 15.0 // 15 seconds
    
    // MARK: - Command Verification
    
    /// Delay between command verification retries.
    /// - Source: CommandVerifier.swift line 345
    public static let verificationRetryDelay: TimeInterval = 1.0 // 1 second
}

/// Simulation timing constants for pump testing.
///
/// These values provide realistic delays for simulated pump operations.
public enum PumpSimulationTimingConstants {
    
    // MARK: - SimulatedPumpSource Timing
    
    /// Status read delay.
    /// - Source: SimulatedPumpSource.swift line 66
    public static let statusReadDelay: TimeInterval = 0.3 // 300ms
    
    /// Status read delay in nanoseconds.
    public static let statusReadDelayNanos: UInt64 = 300_000_000 // 300ms
    
    /// Quick response delay (IOB, battery, etc.).
    /// - Source: SimulatedPumpSource.swift line 131
    public static let quickResponseDelay: TimeInterval = 0.1 // 100ms
    
    /// Quick response delay in nanoseconds.
    public static let quickResponseDelayNanos: UInt64 = 100_000_000 // 100ms
    
    /// Very quick response delay (simple reads).
    /// - Source: SimulatedPumpSource.swift line 151
    public static let veryQuickResponseDelay: TimeInterval = 0.05 // 50ms
    
    /// Very quick response delay in nanoseconds.
    public static let veryQuickResponseDelayNanos: UInt64 = 50_000_000 // 50ms
    
    /// Command execution delay.
    /// - Source: SimulatedPumpSource.swift line 176
    public static let commandExecutionDelay: TimeInterval = 0.2 // 200ms
    
    /// Command execution delay in nanoseconds.
    public static let commandExecutionDelayNanos: UInt64 = 200_000_000 // 200ms
    
    /// Maximum bolus delivery simulation time.
    /// - Source: SimulatedPumpSource.swift line 183
    public static let maxBolusSimulationTime: TimeInterval = 2.0 // 2 seconds cap
    
    /// Maximum bolus simulation time in nanoseconds.
    public static let maxBolusSimulationTimeNanos: UInt64 = 2_000_000_000 // 2 seconds
    
    /// Pump status update interval.
    /// - Source: SimulatedPumpSource.swift line 263
    public static let statusUpdateInterval: TimeInterval = 60.0 // 60 seconds
    
    /// Status update interval in nanoseconds.
    public static let statusUpdateIntervalNanos: UInt64 = 60_000_000_000 // 60 seconds
}
