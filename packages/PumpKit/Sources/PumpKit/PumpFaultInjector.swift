// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpFaultInjector.swift
// PumpKit
//
// Fault injection for pump testing.
// Enables systematic testing of error handling and edge cases.
// Trace: PUMP-CTX-007, SIM-FAULT-001
//
// Usage:
//   let injector = PumpFaultInjector.occlusion
//   if case .injected(let fault) = injector.shouldInject(for: "deliverBolus") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - Pump Fault Types

/// Pump-specific fault types
public enum PumpFaultType: Sendable, Codable, Equatable {
    // Delivery faults
    case occlusion                          // Tubing occlusion
    case airInLine                          // Air detected in tubing
    case emptyReservoir                     // Reservoir depleted
    case motorStall                         // Pump motor failure
    
    // Battery faults
    case lowBattery(level: Double)          // Low battery (0-1)
    case batteryDepleted                    // Battery dead
    
    // Communication faults
    case connectionDrop                     // BLE disconnect
    case connectionTimeout                  // No response
    case communicationError(code: UInt8)    // Protocol error
    case packetCorruption(probability: Double)  // Corrupt packets
    case bleDisconnectMidCommand            // BLE disconnect during command (MDT-FAULT-005)
    case wrongChannelResponse(sent: UInt8, received: UInt8)  // RF channel mismatch (MDT-FAULT-006)
    
    // State faults
    case unexpectedSuspend                  // Pump suspends unexpectedly
    case alarmActive(code: UInt8)           // Alarm triggered
    case primeRequired                      // Pump needs priming
    
    // Timing faults
    case commandDelay(milliseconds: Int)    // Delayed response
    case intermittentFailure(probability: Double)  // Random failures
    
    public var displayName: String {
        switch self {
        case .occlusion: return "Occlusion"
        case .airInLine: return "Air in Line"
        case .emptyReservoir: return "Empty Reservoir"
        case .motorStall: return "Motor Stall"
        case .lowBattery(let level): return "Low Battery (\(Int(level * 100))%)"
        case .batteryDepleted: return "Battery Depleted"
        case .connectionDrop: return "Connection Drop"
        case .connectionTimeout: return "Connection Timeout"
        case .communicationError(let code): return "Comm Error (0x\(String(code, radix: 16)))"
        case .packetCorruption(let p): return "Packet Corruption (\(Int(p * 100))%)"
        case .bleDisconnectMidCommand: return "BLE Disconnect Mid-Command"
        case .wrongChannelResponse(let sent, let received): return "Wrong Channel (sent:\(sent), recv:\(received))"
        case .unexpectedSuspend: return "Unexpected Suspend"
        case .alarmActive(let code): return "Alarm (0x\(String(code, radix: 16)))"
        case .primeRequired: return "Prime Required"
        case .commandDelay(let ms): return "Command Delay (\(ms)ms)"
        case .intermittentFailure(let p): return "Intermittent Failure (\(Int(p * 100))%)"
        }
    }
    
    public var category: PumpFaultCategory {
        switch self {
        case .occlusion, .airInLine, .emptyReservoir, .motorStall:
            return .delivery
        case .lowBattery, .batteryDepleted:
            return .battery
        case .connectionDrop, .connectionTimeout, .communicationError, .packetCorruption, .bleDisconnectMidCommand, .wrongChannelResponse:
            return .communication
        case .unexpectedSuspend, .alarmActive, .primeRequired:
            return .state
        case .commandDelay, .intermittentFailure:
            return .timing
        }
    }
    
    /// Whether this fault should stop delivery
    public var stopsDelivery: Bool {
        switch self {
        case .occlusion, .airInLine, .emptyReservoir, .motorStall,
             .batteryDepleted, .unexpectedSuspend, .primeRequired:
            return true
        default:
            return false
        }
    }
}

/// Categories of pump faults
public enum PumpFaultCategory: String, Codable, Sendable, CaseIterable {
    case delivery       // Insulin delivery issues
    case battery        // Power issues
    case communication  // BLE/RF issues
    case state          // Pump state issues
    case timing         // Timing issues
}

// MARK: - Pump Fault Trigger

/// When to trigger a pump fault
public enum PumpFaultTrigger: Sendable, Codable, Equatable {
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
}

// MARK: - Pump Fault Configuration

/// Configuration for a single pump fault
public struct PumpFaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: PumpFaultType
    public let trigger: PumpFaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: PumpFaultType,
        trigger: PumpFaultTrigger = .immediate,
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

// MARK: - Pump Fault Injection Result

/// Result of a pump fault injection attempt
public enum PumpFaultInjectionResult: Sendable, Equatable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(PumpFaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(PumpFaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - Pump Fault Injector

/// Fault injector for pump testing
public final class PumpFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [PumpFaultConfiguration] = []
    private var _commandCount: Int = 0
    private var _insulinDelivered: Double = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [PumpFaultConfiguration] {
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
    
    // MARK: - Initialization
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [PumpFaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: PumpFaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: PumpFaultType, trigger: PumpFaultTrigger = .immediate) {
        addFault(PumpFaultConfiguration(fault: fault, trigger: trigger))
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
    
    // MARK: - Injection
    
    public func shouldInject(for command: String = "") -> PumpFaultInjectionResult {
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
                case .packetCorruption(let p), .intermittentFailure(let p):
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
    
    private func shouldTrigger(_ config: PumpFaultConfiguration, command: String) -> Bool {
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
        }
    }
}

// MARK: - Preset Pump Fault Injectors

extension PumpFaultInjector {
    
    /// Preset: Occlusion during bolus
    public static var occlusion: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .occlusion,
                trigger: .onCommand("deliverBolus"),
                description: "Occlusion during bolus delivery"
            )
        ])
    }
    
    /// Preset: Low battery warning
    public static var lowBattery: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .lowBattery(level: 0.10),
                trigger: .afterTime(seconds: 60),
                description: "Low battery after 60 seconds"
            ),
            PumpFaultConfiguration(
                fault: .batteryDepleted,
                trigger: .afterTime(seconds: 180),
                description: "Battery depleted after 3 minutes"
            )
        ])
    }
    
    /// Preset: Unreliable connection
    public static var unreliableConnection: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of connection drop"
            ),
            PumpFaultConfiguration(
                fault: .commandDelay(milliseconds: 500),
                trigger: .probabilistic(probability: 0.10),
                description: "10% chance of 500ms delay"
            ),
            PumpFaultConfiguration(
                fault: .packetCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% packet corruption"
            )
        ])
    }
    
    /// Preset: Empty reservoir scenario
    public static var emptyReservoir: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .lowBattery(level: 0.20),
                trigger: .afterInsulinDelivery(units: 50),
                description: "Low reservoir warning at 50U remaining"
            ),
            PumpFaultConfiguration(
                fault: .emptyReservoir,
                trigger: .afterInsulinDelivery(units: 100),
                description: "Empty reservoir after 100U delivered"
            )
        ])
    }
    
    /// Preset: Motor stall during extended bolus
    public static var motorStall: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .motorStall,
                trigger: .afterCommands(10),
                description: "Motor stall after 10 commands"
            )
        ])
    }
    
    /// Preset: Intermittent failures (stress testing)
    public static var stressTest: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .intermittentFailure(probability: 0.15),
                trigger: .immediate,
                description: "15% random failure rate"
            ),
            PumpFaultConfiguration(
                fault: .commandDelay(milliseconds: 200),
                trigger: .probabilistic(probability: 0.30),
                description: "30% chance of delays"
            ),
            PumpFaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.03),
                description: "3% connection drops"
            )
        ])
    }
    
    /// Preset: Alarm scenarios
    public static var alarms: PumpFaultInjector {
        PumpFaultInjector(faults: [
            PumpFaultConfiguration(
                fault: .alarmActive(code: 0x01),  // Generic alarm
                trigger: .afterTime(seconds: 120),
                description: "Generic alarm after 2 minutes"
            )
        ])
    }
}

// MARK: - Pump Fault Statistics

/// Statistics about pump fault injection
public struct PumpFaultInjectionStats: Sendable {
    public var totalCommands: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [PumpFaultCategory: Int] = [:]
    public var lastFault: PumpFaultType?
    public var lastFaultTime: Date?
    public var deliveryInterruptions: Int = 0
    
    public init() {}
    
    public mutating func record(_ result: PumpFaultInjectionResult) {
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
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
