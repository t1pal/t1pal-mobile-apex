// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ErosFaultInjector.swift
// PumpKit
//
// Fault injection for Omnipod Eros testing.
// Enables systematic testing of error handling and edge cases.
// Trace: EROS-FIX-006, SIM-FAULT-001
//
// Fault codes sourced from:
// - docs/architecture/EROS-COMMAND-REFERENCE.md
// - externals/openomni.wiki/6A-67-34-Fault-Events-analisis.md
//
// Usage:
//   let injector = ErosFaultInjector.occlusion
//   if case .injected(let fault) = injector.shouldInject(for: "deliverBolus") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - Eros Fault Types

/// Eros-specific fault types matching pod fault codes
public enum ErosFaultType: Sendable, Codable, Equatable {
    // Pod Hardware Faults
    case occlusion                          // 0x14 - Primary occlusion detection
    case emptyReservoir                     // 0x18 - Reservoir empty
    case podExpired                         // 0x1C - Exceeded 80 hour maximum life
    case encoderOpenHigh                    // 0x40 - Pump encoder issue
    case encoderCountLow                    // 0x42 - Delivery problem inside pod
    case encoderCountProblem                // 0x43 - General encoder issue
    case timedPumpCheck                     // 0x6A - Threshold exceeded
    case resetUnknown                       // 0x34 - Battery/static on day 3
    
    // Infusion Faults (0x80-0x8F)
    case basalUnderInfusion                 // 0x80
    case basalOverInfusion                  // 0x81
    case tempBasalUnderInfusion             // 0x82
    case tempBasalOverInfusion              // 0x83
    case bolusUnderInfusion                 // 0x84
    case bolusOverInfusion                  // 0x85
    
    // RF Communication Faults
    case rfTimeout                          // No response from pod
    case rfCRCMismatch                      // CRC8/CRC16 validation failed
    case rfChannelError(sent: UInt8, received: UInt8)  // Wrong channel
    case rfRetryExhausted(attempts: Int)    // Max retries exceeded
    case rfPacketCorruption(probability: Double)  // Corrupt RF packets
    case rfNackError                        // NACK received
    
    // RileyLink Faults
    case rileyLinkDisconnect                // BLE disconnect from RileyLink
    case rileyLinkBatteryLow                // RileyLink battery low
    case rileyLinkRadioError                // RileyLink radio error
    
    // Pod State Faults
    case podScreener                        // Pod alarming (screamer mode)
    case podDeactivated                     // Pod already deactivated
    case podNotPaired                       // Pod not paired
    case unexpectedPodState(state: UInt8)   // Wrong pod progress state
    case nonceError                         // Nonce synchronization error
    
    // Timing Faults
    case commandDelay(milliseconds: Int)    // Delayed response
    case segmentTimingFault                 // 0x67 - Temp basal started too soon
    case intermittentFailure(probability: Double)  // Random failures
    
    /// Fault code if applicable (from EROS-COMMAND-REFERENCE.md)
    public var faultCode: UInt8? {
        switch self {
        case .occlusion: return 0x14
        case .emptyReservoir: return 0x18
        case .podExpired: return 0x1C
        case .resetUnknown: return 0x34
        case .encoderOpenHigh: return 0x40
        case .encoderCountLow: return 0x42
        case .encoderCountProblem: return 0x43
        case .timedPumpCheck: return 0x6A
        case .segmentTimingFault: return 0x67
        case .basalUnderInfusion: return 0x80
        case .basalOverInfusion: return 0x81
        case .tempBasalUnderInfusion: return 0x82
        case .tempBasalOverInfusion: return 0x83
        case .bolusUnderInfusion: return 0x84
        case .bolusOverInfusion: return 0x85
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
        case .resetUnknown: return "Reset Unknown (0x34)"
        case .basalUnderInfusion: return "Basal Under Infusion (0x80)"
        case .basalOverInfusion: return "Basal Over Infusion (0x81)"
        case .tempBasalUnderInfusion: return "Temp Basal Under Infusion (0x82)"
        case .tempBasalOverInfusion: return "Temp Basal Over Infusion (0x83)"
        case .bolusUnderInfusion: return "Bolus Under Infusion (0x84)"
        case .bolusOverInfusion: return "Bolus Over Infusion (0x85)"
        case .rfTimeout: return "RF Timeout"
        case .rfCRCMismatch: return "RF CRC Mismatch"
        case .rfChannelError(let sent, let recv): return "RF Channel Error (sent:\(sent), recv:\(recv))"
        case .rfRetryExhausted(let attempts): return "RF Retry Exhausted (\(attempts) attempts)"
        case .rfPacketCorruption(let p): return "RF Packet Corruption (\(Int(p * 100))%)"
        case .rfNackError: return "RF NACK Error"
        case .rileyLinkDisconnect: return "RileyLink Disconnect"
        case .rileyLinkBatteryLow: return "RileyLink Battery Low"
        case .rileyLinkRadioError: return "RileyLink Radio Error"
        case .podScreener: return "Pod Screamer"
        case .podDeactivated: return "Pod Deactivated"
        case .podNotPaired: return "Pod Not Paired"
        case .unexpectedPodState(let state): return "Unexpected Pod State (0x\(String(state, radix: 16)))"
        case .nonceError: return "Nonce Error"
        case .commandDelay(let ms): return "Command Delay (\(ms)ms)"
        case .segmentTimingFault: return "Segment Timing Fault (0x67)"
        case .intermittentFailure(let p): return "Intermittent Failure (\(Int(p * 100))%)"
        }
    }
    
    public var category: ErosFaultCategory {
        switch self {
        case .occlusion, .emptyReservoir, .podExpired, .encoderOpenHigh,
             .encoderCountLow, .encoderCountProblem, .timedPumpCheck, .resetUnknown:
            return .hardware
        case .basalUnderInfusion, .basalOverInfusion, .tempBasalUnderInfusion,
             .tempBasalOverInfusion, .bolusUnderInfusion, .bolusOverInfusion:
            return .infusion
        case .rfTimeout, .rfCRCMismatch, .rfChannelError, .rfRetryExhausted,
             .rfPacketCorruption, .rfNackError:
            return .rfCommunication
        case .rileyLinkDisconnect, .rileyLinkBatteryLow, .rileyLinkRadioError:
            return .rileyLink
        case .podScreener, .podDeactivated, .podNotPaired, .unexpectedPodState, .nonceError:
            return .podState
        case .commandDelay, .segmentTimingFault, .intermittentFailure:
            return .timing
        }
    }
    
    /// Whether this fault requires pod deactivation
    public var requiresDeactivation: Bool {
        switch self {
        case .occlusion, .emptyReservoir, .podExpired, .encoderOpenHigh,
             .encoderCountLow, .encoderCountProblem, .timedPumpCheck, .resetUnknown,
             .basalUnderInfusion, .basalOverInfusion, .tempBasalUnderInfusion,
             .tempBasalOverInfusion, .bolusUnderInfusion, .bolusOverInfusion,
             .podScreener, .segmentTimingFault:
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

/// Categories of Eros faults
public enum ErosFaultCategory: String, Codable, Sendable, CaseIterable {
    case hardware           // Pod hardware issues
    case infusion           // Insulin infusion issues
    case rfCommunication    // RF layer issues
    case rileyLink          // RileyLink issues
    case podState           // Pod state issues
    case timing             // Timing issues
}

// MARK: - Eros Fault Trigger

/// When to trigger an Eros fault
public enum ErosFaultTrigger: Sendable, Codable, Equatable {
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
    
    /// Trigger at segment boundary (for timing faults)
    case atSegment(Int)
}

// MARK: - Eros Fault Configuration

/// Configuration for a single Eros fault
public struct ErosFaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: ErosFaultType
    public let trigger: ErosFaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: ErosFaultType,
        trigger: ErosFaultTrigger = .immediate,
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

// MARK: - Eros Fault Injection Result

/// Result of an Eros fault injection attempt
public enum ErosFaultInjectionResult: Sendable, Equatable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(ErosFaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(ErosFaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - Eros Fault Injector

/// Fault injector for Omnipod Eros testing
public final class ErosFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [ErosFaultConfiguration] = []
    private var _commandCount: Int = 0
    private var _insulinDelivered: Double = 0
    private var _currentSegment: Int = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [ErosFaultConfiguration] {
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
    
    public var currentSegment: Int {
        lock.lock()
        defer { lock.unlock() }
        return _currentSegment
    }
    
    // MARK: - Initialization
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [ErosFaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: ErosFaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: ErosFaultType, trigger: ErosFaultTrigger = .immediate) {
        addFault(ErosFaultConfiguration(fault: fault, trigger: trigger))
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
        _currentSegment = 0
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
    
    public func recordSegmentChange(_ segment: Int) {
        lock.lock()
        defer { lock.unlock() }
        _currentSegment = segment
    }
    
    // MARK: - Injection
    
    public func shouldInject(for command: String = "") -> ErosFaultInjectionResult {
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
                case .rfPacketCorruption(let p), .intermittentFailure(let p):
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
    
    private func shouldTrigger(_ config: ErosFaultConfiguration, command: String) -> Bool {
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
            
        case .atSegment(let segment):
            return _currentSegment == segment
        }
    }
}

// MARK: - Preset Eros Fault Injectors

extension ErosFaultInjector {
    
    /// Preset: Occlusion during bolus
    public static var occlusion: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus"),
                description: "Occlusion during bolus delivery"
            )
        ])
    }
    
    /// Preset: Empty reservoir after 50U
    public static var emptyReservoir: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .emptyReservoir,
                trigger: .afterInsulinDelivery(units: 50),
                description: "Empty reservoir after 50U delivered"
            )
        ])
    }
    
    /// Preset: Pod expired scenario (day 3+)
    public static var podExpired: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .podExpired,
                trigger: .afterTime(seconds: 80 * 60 * 60),  // 80 hours
                description: "Pod expired after 80 hours"
            )
        ])
    }
    
    /// Preset: Unreliable RF connection
    public static var unreliableRF: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .rfTimeout,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of RF timeout"
            ),
            ErosFaultConfiguration(
                fault: .rfPacketCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% RF packet corruption"
            ),
            ErosFaultConfiguration(
                fault: .rfRetryExhausted(attempts: 5),
                trigger: .probabilistic(probability: 0.01),
                description: "1% retry exhaustion"
            )
        ])
    }
    
    /// Preset: RileyLink battery scenario
    public static var rileyLinkBattery: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .rileyLinkBatteryLow,
                trigger: .afterTime(seconds: 3600),
                description: "RileyLink low battery after 1 hour"
            ),
            ErosFaultConfiguration(
                fault: .rileyLinkDisconnect,
                trigger: .afterTime(seconds: 7200),
                description: "RileyLink disconnect after 2 hours"
            )
        ])
    }
    
    /// Preset: Segment timing fault (day 3 race condition)
    public static var segmentTiming: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .segmentTimingFault,
                trigger: .atSegment(2),
                description: "Segment 2 timing fault (0x67)"
            )
        ])
    }
    
    /// Preset: Encoder failure (pump hardware)
    public static var encoderFailure: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .encoderCountLow,
                trigger: .afterCommands(50),
                description: "Encoder count low after 50 commands"
            )
        ])
    }
    
    /// Preset: Nonce synchronization error
    public static var nonceError: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .nonceError,
                trigger: .probabilistic(probability: 0.03),
                description: "3% chance of nonce error"
            )
        ])
    }
    
    /// Preset: Stress testing (multiple intermittent faults)
    public static var stressTest: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .intermittentFailure(probability: 0.10),
                trigger: .immediate,
                description: "10% random failure rate"
            ),
            ErosFaultConfiguration(
                fault: .commandDelay(milliseconds: 300),
                trigger: .probabilistic(probability: 0.20),
                description: "20% chance of delays"
            ),
            ErosFaultConfiguration(
                fault: .rfTimeout,
                trigger: .probabilistic(probability: 0.03),
                description: "3% RF timeouts"
            ),
            ErosFaultConfiguration(
                fault: .nonceError,
                trigger: .probabilistic(probability: 0.02),
                description: "2% nonce errors"
            )
        ])
    }
    
    /// Preset: Pod screamer scenario
    public static var podScreener: ErosFaultInjector {
        ErosFaultInjector(faults: [
            ErosFaultConfiguration(
                fault: .podScreener,
                trigger: .afterTime(seconds: 300),
                description: "Pod screamer after 5 minutes"
            )
        ])
    }
}

// MARK: - Eros Fault Statistics

/// Statistics about Eros fault injection
public struct ErosFaultInjectionStats: Sendable {
    public var totalCommands: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [ErosFaultCategory: Int] = [:]
    public var lastFault: ErosFaultType?
    public var lastFaultTime: Date?
    public var deliveryInterruptions: Int = 0
    public var deactivationsRequired: Int = 0
    
    public init() {}
    
    public mutating func record(_ result: ErosFaultInjectionResult) {
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
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
