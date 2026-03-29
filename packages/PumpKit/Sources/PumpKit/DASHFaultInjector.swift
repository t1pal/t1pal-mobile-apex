// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DASHFaultInjector.swift
// PumpKit
//
// Fault injection for Omnipod DASH testing.
// Enables systematic testing of error handling and edge cases.
// Trace: DASH-FIX-015, SIM-FAULT-001
//
// Fault codes sourced from:
// - docs/architecture/EROS-COMMAND-REFERENCE.md (DASH-Specific BLE Faults)
//
// Usage:
//   let injector = DASHFaultInjector.bleTimeout
//   if case .injected(let fault) = injector.shouldInject(for: "sendCommand") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - DASH Fault Types

/// DASH-specific fault types matching pod fault codes
public enum DASHFaultType: Sendable, Codable, Equatable {
    // Pod Hardware Faults (shared with Eros)
    case occlusion                          // 0x14 - Primary occlusion detection
    case emptyReservoir                     // 0x18 - Reservoir empty
    case podExpired                         // 0x1C - Exceeded 72 hour maximum life
    case encoderOpenHigh                    // 0x40 - Pump encoder issue
    case encoderCountLow                    // 0x42 - Delivery problem inside pod
    case encoderCountProblem                // 0x43 - General encoder issue
    case timedPumpCheck                     // 0x6A - Threshold exceeded
    
    // Infusion Faults (0x80-0x8F)
    case basalUnderInfusion                 // 0x80
    case basalOverInfusion                  // 0x81
    case tempBasalUnderInfusion             // 0x82
    case tempBasalOverInfusion              // 0x83
    case bolusUnderInfusion                 // 0x84
    case bolusOverInfusion                  // 0x85
    
    // DASH-Specific BLE Faults (0xA0-0xC2)
    case bleRetryTimeout                    // 0xA0 - BLE retry timeout
    case bleCRCFailure                      // 0xA8 - BLE CRC failure
    case blePingTimeout                     // 0xA9 - BLE ping timeout
    case bleExcessiveResets                 // 0xAA - BLE excessive resets
    case bleNackError                       // 0xAB - BLE NACK error
    
    // BLE Communication Faults
    case bleDisconnect                      // Unexpected BLE disconnect
    case bleConnectionTimeout               // Connection attempt timeout
    case bleScanTimeout                     // Scanning timeout
    case bleCharacteristicNotFound          // Missing GATT characteristic
    case bleEncryptionError                 // Encryption/decryption failure
    case blePacketCorruption(probability: Double)  // Corrupt BLE packets
    case bleRetryExhausted(attempts: Int)   // Max retries exceeded
    
    // Pairing Faults
    case pairingAKARejected                 // AKA (Authentication Key Agreement) rejected
    case pairingKeyExchangeFailed           // Key exchange failure
    case pairingTimeout                     // Pairing sequence timeout
    case pairingAlreadyPaired               // Pod already paired to another device
    case pairingNotInRange                  // Pod not in BLE range during pairing
    
    // Pod State Faults
    case podScreener                        // Pod alarming (screamer mode)
    case podDeactivated                     // Pod already deactivated
    case podNotPaired                       // Pod not paired
    case unexpectedPodState(state: UInt8)   // Wrong pod progress state
    case podActivationFailed                // Activation sequence failed
    
    // Timing Faults
    case commandDelay(milliseconds: Int)    // Delayed response
    case intermittentFailure(probability: Double)  // Random failures
    
    /// Fault code if applicable (from EROS-COMMAND-REFERENCE.md)
    public var faultCode: UInt8? {
        switch self {
        case .occlusion: return 0x14
        case .emptyReservoir: return 0x18
        case .podExpired: return 0x1C
        case .encoderOpenHigh: return 0x40
        case .encoderCountLow: return 0x42
        case .encoderCountProblem: return 0x43
        case .timedPumpCheck: return 0x6A
        case .basalUnderInfusion: return 0x80
        case .basalOverInfusion: return 0x81
        case .tempBasalUnderInfusion: return 0x82
        case .tempBasalOverInfusion: return 0x83
        case .bolusUnderInfusion: return 0x84
        case .bolusOverInfusion: return 0x85
        case .bleRetryTimeout: return 0xA0
        case .bleCRCFailure: return 0xA8
        case .blePingTimeout: return 0xA9
        case .bleExcessiveResets: return 0xAA
        case .bleNackError: return 0xAB
        default: return nil
        }
    }
    
    public var displayName: String {
        switch self {
        case .occlusion: return "Occlusion (0x14)"
        case .emptyReservoir: return "Empty Reservoir (0x18)"
        case .podExpired: return "Pod Expired (0x1C)"
        case .encoderOpenHigh: return "Encoder Open High (0x40)"
        case .encoderCountLow: return "Encoder Count Low (0x42)"
        case .encoderCountProblem: return "Encoder Count Problem (0x43)"
        case .timedPumpCheck: return "Timed Pump Check (0x6A)"
        case .basalUnderInfusion: return "Basal Under Infusion (0x80)"
        case .basalOverInfusion: return "Basal Over Infusion (0x81)"
        case .tempBasalUnderInfusion: return "Temp Basal Under Infusion (0x82)"
        case .tempBasalOverInfusion: return "Temp Basal Over Infusion (0x83)"
        case .bolusUnderInfusion: return "Bolus Under Infusion (0x84)"
        case .bolusOverInfusion: return "Bolus Over Infusion (0x85)"
        case .bleRetryTimeout: return "BLE Retry Timeout (0xA0)"
        case .bleCRCFailure: return "BLE CRC Failure (0xA8)"
        case .blePingTimeout: return "BLE Ping Timeout (0xA9)"
        case .bleExcessiveResets: return "BLE Excessive Resets (0xAA)"
        case .bleNackError: return "BLE NACK Error (0xAB)"
        case .bleDisconnect: return "BLE Disconnect"
        case .bleConnectionTimeout: return "BLE Connection Timeout"
        case .bleScanTimeout: return "BLE Scan Timeout"
        case .bleCharacteristicNotFound: return "BLE Characteristic Not Found"
        case .bleEncryptionError: return "BLE Encryption Error"
        case .blePacketCorruption(let p): return "BLE Packet Corruption (\(Int(p * 100))%)"
        case .bleRetryExhausted(let attempts): return "BLE Retry Exhausted (\(attempts) attempts)"
        case .pairingAKARejected: return "Pairing AKA Rejected"
        case .pairingKeyExchangeFailed: return "Pairing Key Exchange Failed"
        case .pairingTimeout: return "Pairing Timeout"
        case .pairingAlreadyPaired: return "Pod Already Paired"
        case .pairingNotInRange: return "Pod Not In Range"
        case .podScreener: return "Pod Screamer"
        case .podDeactivated: return "Pod Deactivated"
        case .podNotPaired: return "Pod Not Paired"
        case .unexpectedPodState(let state): return "Unexpected Pod State (0x\(String(state, radix: 16)))"
        case .podActivationFailed: return "Pod Activation Failed"
        case .commandDelay(let ms): return "Command Delay (\(ms)ms)"
        case .intermittentFailure(let p): return "Intermittent Failure (\(Int(p * 100))%)"
        }
    }
    
    public var category: DASHFaultCategory {
        switch self {
        case .occlusion, .emptyReservoir, .podExpired, .encoderOpenHigh,
             .encoderCountLow, .encoderCountProblem, .timedPumpCheck:
            return .hardware
        case .basalUnderInfusion, .basalOverInfusion, .tempBasalUnderInfusion,
             .tempBasalOverInfusion, .bolusUnderInfusion, .bolusOverInfusion:
            return .infusion
        case .bleRetryTimeout, .bleCRCFailure, .blePingTimeout, .bleExcessiveResets,
             .bleNackError, .bleDisconnect, .bleConnectionTimeout, .bleScanTimeout,
             .bleCharacteristicNotFound, .bleEncryptionError, .blePacketCorruption,
             .bleRetryExhausted:
            return .bleCommunication
        case .pairingAKARejected, .pairingKeyExchangeFailed, .pairingTimeout,
             .pairingAlreadyPaired, .pairingNotInRange:
            return .pairing
        case .podScreener, .podDeactivated, .podNotPaired, .unexpectedPodState,
             .podActivationFailed:
            return .podState
        case .commandDelay, .intermittentFailure:
            return .timing
        }
    }
    
    /// Whether this fault requires pod deactivation
    public var requiresDeactivation: Bool {
        switch self {
        case .occlusion, .emptyReservoir, .podExpired, .encoderOpenHigh,
             .encoderCountLow, .encoderCountProblem, .timedPumpCheck,
             .basalUnderInfusion, .basalOverInfusion, .tempBasalUnderInfusion,
             .tempBasalOverInfusion, .bolusUnderInfusion, .bolusOverInfusion,
             .podScreener:
            return true
        default:
            return false
        }
    }
    
    /// Whether this fault stops insulin delivery
    public var stopsDelivery: Bool {
        switch self {
        case .occlusion, .emptyReservoir, .podExpired, .podScreener, .podDeactivated,
             .encoderOpenHigh, .encoderCountLow, .encoderCountProblem, .timedPumpCheck:
            return true
        default:
            return false
        }
    }
}

/// Categories of DASH faults
public enum DASHFaultCategory: String, Codable, Sendable, CaseIterable {
    case hardware           // Pod hardware issues
    case infusion           // Insulin infusion issues
    case bleCommunication   // BLE layer issues
    case pairing            // Pairing/key exchange issues
    case podState           // Pod state issues
    case timing             // Timing issues
}

// MARK: - DASH Fault Trigger

/// When to trigger a DASH fault
public enum DASHFaultTrigger: Sendable, Codable, Equatable {
    /// Trigger immediately on matching operation
    case immediate
    
    /// Trigger after N commands
    case afterCommands(Int)
    
    /// Trigger after N seconds
    case afterTime(seconds: Double)
    
    /// Trigger on specific command type
    case onCommand(String)
    
    /// Trigger with probability
    case probabilistic(probability: Double)
    
    /// Trigger once then disable
    case once
    
    /// Trigger after N units of insulin delivered
    case afterInsulinDelivery(units: Double)
    
    /// Trigger during pairing sequence
    case duringPairing
}

// MARK: - DASH Fault Configuration

/// Configuration for a single DASH fault
public struct DASHFaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: DASHFaultType
    public let trigger: DASHFaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: DASHFaultType,
        trigger: DASHFaultTrigger = .immediate,
        enabled: Bool = true,
        description: String = ""
    ) {
        self.id = id
        self.fault = fault
        self.trigger = trigger
        self.enabled = enabled
        self.description = description.isEmpty ? fault.displayName : description
    }
}

// MARK: - DASH Fault Injection Result

/// Result of a DASH fault injection attempt
public enum DASHFaultInjectionResult: Sendable, Equatable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(DASHFaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(DASHFaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - DASH Fault Injector

/// Fault injector for Omnipod DASH testing
public final class DASHFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [DASHFaultConfiguration] = []
    private var _commandCount: Int = 0
    private var _insulinDelivered: Double = 0
    private var _isPairing: Bool = false
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [DASHFaultConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return _faults
    }
    
    public var commandCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _commandCount
    }
    
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(_startTime)
    }
    
    public var insulinDelivered: Double {
        lock.lock()
        defer { lock.unlock() }
        return _insulinDelivered
    }
    
    public var isPairing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPairing
    }
    
    // MARK: - Initialization
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [DASHFaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: DASHFaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: DASHFaultType, trigger: DASHFaultTrigger = .immediate) {
        addFault(DASHFaultConfiguration(fault: fault, trigger: trigger))
    }
    
    public func removeFault(id: String) {
        lock.lock()
        defer { lock.unlock() }
        _faults.removeAll { $0.id == id }
    }
    
    public func clearFaults() {
        lock.lock()
        defer { lock.unlock() }
        _faults.removeAll()
        _triggeredOnce.removeAll()
    }
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _commandCount = 0
        _insulinDelivered = 0
        _isPairing = false
        _startTime = Date()
        _triggeredOnce.removeAll()
    }
    
    // MARK: - Recording
    
    public func recordCommand() {
        lock.lock()
        defer { lock.unlock() }
        _commandCount += 1
    }
    
    public func recordInsulinDelivered(_ units: Double) {
        lock.lock()
        defer { lock.unlock() }
        _insulinDelivered += units
    }
    
    public func recordPairingStart() {
        lock.lock()
        defer { lock.unlock() }
        _isPairing = true
    }
    
    public func recordPairingEnd() {
        lock.lock()
        defer { lock.unlock() }
        _isPairing = false
    }
    
    // MARK: - Injection
    
    public func shouldInject(for command: String = "") -> DASHFaultInjectionResult {
        lock.lock()
        defer { lock.unlock() }
        
        for config in _faults where config.enabled {
            if shouldTrigger(config, command: command) {
                // Handle once-triggered faults
                if case .once = config.trigger {
                    if _triggeredOnce.contains(config.id) {
                        continue
                    }
                    _triggeredOnce.insert(config.id)
                }
                
                // Handle probabilistic triggers
                if case .probabilistic(let probability) = config.trigger {
                    if Double.random(in: 0...1) > probability {
                        return .skipped(config.fault)
                    }
                }
                
                // Handle probabilistic fault types
                switch config.fault {
                case .blePacketCorruption(let p), .intermittentFailure(let p):
                    if Double.random(in: 0...1) > p {
                        return .skipped(config.fault)
                    }
                default:
                    break
                }
                
                return .injected(config.fault)
            }
        }
        
        return .noFault
    }
    
    private func shouldTrigger(_ config: DASHFaultConfiguration, command: String) -> Bool {
        switch config.trigger {
        case .immediate:
            return true
            
        case .afterCommands(let count):
            return _commandCount >= count
            
        case .afterTime(let seconds):
            return elapsedTime >= seconds
            
        case .onCommand(let cmd):
            return command == cmd
            
        case .probabilistic:
            return true  // Handled in shouldInject
            
        case .once:
            return !_triggeredOnce.contains(config.id)
            
        case .afterInsulinDelivery(let units):
            return _insulinDelivered >= units
            
        case .duringPairing:
            return _isPairing
        }
    }
}

// MARK: - Preset DASH Fault Injectors

extension DASHFaultInjector {
    
    /// Preset: Occlusion during bolus
    public static var occlusion: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus"),
                description: "Occlusion during bolus delivery"
            )
        ])
    }
    
    /// Preset: Empty reservoir after 50U
    public static var emptyReservoir: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .emptyReservoir,
                trigger: .afterInsulinDelivery(units: 50),
                description: "Empty reservoir after 50U delivered"
            )
        ])
    }
    
    /// Preset: Pod expired scenario (day 3)
    public static var podExpired: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .podExpired,
                trigger: .afterTime(seconds: 72 * 60 * 60),  // 72 hours
                description: "Pod expired after 72 hours"
            )
        ])
    }
    
    /// Preset: Unreliable BLE connection
    public static var unreliableBLE: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .bleDisconnect,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of BLE disconnect"
            ),
            DASHFaultConfiguration(
                fault: .blePacketCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% BLE packet corruption"
            ),
            DASHFaultConfiguration(
                fault: .bleRetryExhausted(attempts: 5),
                trigger: .probabilistic(probability: 0.01),
                description: "1% retry exhaustion"
            )
        ])
    }
    
    /// Preset: BLE timeout scenario
    public static var bleTimeout: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .bleRetryTimeout,
                trigger: .afterCommands(10),
                description: "BLE retry timeout after 10 commands"
            )
        ])
    }
    
    /// Preset: Pairing failure
    public static var pairingFailure: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .pairingAKARejected,
                trigger: .duringPairing,
                description: "AKA rejection during pairing"
            )
        ])
    }
    
    /// Preset: Pairing timeout
    public static var pairingTimeout: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .pairingTimeout,
                trigger: .duringPairing,
                description: "Timeout during pairing sequence"
            )
        ])
    }
    
    /// Preset: Encoder failure (pump hardware)
    public static var encoderFailure: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .encoderCountLow,
                trigger: .afterCommands(50),
                description: "Encoder count low after 50 commands"
            )
        ])
    }
    
    /// Preset: BLE CRC failure
    public static var bleCRCFailure: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .bleCRCFailure,
                trigger: .probabilistic(probability: 0.03),
                description: "3% chance of BLE CRC failure"
            )
        ])
    }
    
    /// Preset: Stress testing (multiple intermittent faults)
    public static var stressTest: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .intermittentFailure(probability: 0.10),
                trigger: .immediate,
                description: "10% random failure rate"
            ),
            DASHFaultConfiguration(
                fault: .commandDelay(milliseconds: 300),
                trigger: .probabilistic(probability: 0.20),
                description: "20% chance of delays"
            ),
            DASHFaultConfiguration(
                fault: .bleDisconnect,
                trigger: .probabilistic(probability: 0.03),
                description: "3% BLE disconnects"
            ),
            DASHFaultConfiguration(
                fault: .bleNackError,
                trigger: .probabilistic(probability: 0.02),
                description: "2% NACK errors"
            )
        ])
    }
    
    /// Preset: Pod screamer scenario
    public static var podScreener: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .podScreener,
                trigger: .afterTime(seconds: 300),
                description: "Pod screamer after 5 minutes"
            )
        ])
    }
    
    /// Preset: Encryption error (AES-CCM)
    public static var encryptionError: DASHFaultInjector {
        DASHFaultInjector(faults: [
            DASHFaultConfiguration(
                fault: .bleEncryptionError,
                trigger: .probabilistic(probability: 0.02),
                description: "2% chance of encryption error"
            )
        ])
    }
}

// MARK: - DASH Fault Statistics

/// Statistics about DASH fault injection
public struct DASHFaultInjectionStats: Sendable {
    public var totalCommands: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [DASHFaultCategory: Int] = [:]
    public var lastFault: DASHFaultType?
    public var lastFaultTime: Date?
    public var deliveryInterruptions: Int = 0
    public var deactivationsRequired: Int = 0
    public var pairingFailures: Int = 0
    
    public init() {}
    
    public mutating func record(_ result: DASHFaultInjectionResult) {
        switch result {
        case .noFault:
            break
        case .injected(let fault):
            faultsInjected += 1
            faultsByCategory[fault.category, default: 0] += 1
            lastFault = fault
            lastFaultTime = Date()
            if fault.stopsDelivery {
                deliveryInterruptions += 1
            }
            if fault.requiresDeactivation {
                deactivationsRequired += 1
            }
            if fault.category == .pairing {
                pairingFailures += 1
            }
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
