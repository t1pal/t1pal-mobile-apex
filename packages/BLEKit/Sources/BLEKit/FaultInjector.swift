// SPDX-License-Identifier: AGPL-3.0-or-later
//
// FaultInjector.swift
// BLEKit
//
// Configurable fault injection for BLE testing.
// Enables systematic testing of error handling and edge cases.
// Trace: SIM-FAULT-001, synthesized-device-testing.md

import Foundation

// MARK: - Fault Types

/// Categories of injectable faults
public enum FaultCategory: String, Sendable, CaseIterable, Codable {
    /// Connection-related faults (drop, timeout)
    case connection
    
    /// Protocol-level faults (corruption, invalid data)
    case `protocol`
    
    /// State machine faults (unexpected transitions)
    case state
    
    /// Timing-related faults (delays, ordering)
    case timing
    
    /// Resource faults (battery, sensor failure)
    case resource
}

/// Individual fault types that can be injected
public enum FaultType: Sendable, Codable, Equatable {
    /// Drop connection after N packets
    case dropConnection(afterPackets: Int)
    
    /// Drop connection after N seconds
    case dropConnectionAfterTime(seconds: Double)
    
    /// Corrupt packet checksum with given probability (0.0-1.0)
    case corruptChecksum(probability: Double)
    
    /// Corrupt packet data with given probability
    case corruptData(probability: Double)
    
    /// Delay response by specified milliseconds
    case delayResponse(milliseconds: Int)
    
    /// Random delay between min and max milliseconds
    case randomDelay(minMs: Int, maxMs: Int)
    
    /// Return error code instead of normal response
    case returnError(code: UInt8)
    
    /// Simulate timeout (no response)
    case timeout
    
    /// Send packets out of order
    case reorderPackets
    
    /// Duplicate a packet
    case duplicatePacket(probability: Double)
    
    /// Drop a packet without notification
    case dropPacket(probability: Double)
    
    /// Simulate low battery warning
    case lowBattery(level: UInt8)
    
    /// Simulate sensor failure
    case sensorFailure(code: UInt8)
    
    /// Simulate occlusion (for pumps)
    case occlusion
    
    /// Inject warmup state
    case forceWarmup
    
    /// Inject expired state
    case forceExpired
    
    /// Custom fault with handler
    case custom(id: String)
    
    public var category: FaultCategory {
        switch self {
        case .dropConnection, .dropConnectionAfterTime, .timeout:
            return .connection
        case .corruptChecksum, .corruptData, .returnError, .duplicatePacket, .dropPacket:
            return .protocol
        case .forceWarmup, .forceExpired:
            return .state
        case .delayResponse, .randomDelay, .reorderPackets:
            return .timing
        case .lowBattery, .sensorFailure, .occlusion:
            return .resource
        case .custom:
            return .protocol
        }
    }
    
    public var displayName: String {
        switch self {
        case .dropConnection(let packets): return "Drop after \(packets) packets"
        case .dropConnectionAfterTime(let seconds): return "Drop after \(seconds)s"
        case .corruptChecksum(let p): return "Corrupt checksum (\(Int(p * 100))%)"
        case .corruptData(let p): return "Corrupt data (\(Int(p * 100))%)"
        case .delayResponse(let ms): return "Delay \(ms)ms"
        case .randomDelay(let min, let max): return "Delay \(min)-\(max)ms"
        case .returnError(let code): return "Return error 0x\(String(code, radix: 16))"
        case .timeout: return "Timeout"
        case .reorderPackets: return "Reorder packets"
        case .duplicatePacket(let p): return "Duplicate packet (\(Int(p * 100))%)"
        case .dropPacket(let p): return "Drop packet (\(Int(p * 100))%)"
        case .lowBattery(let level): return "Low battery (\(level)%)"
        case .sensorFailure(let code): return "Sensor failure (0x\(String(code, radix: 16)))"
        case .occlusion: return "Occlusion"
        case .forceWarmup: return "Force warmup state"
        case .forceExpired: return "Force expired state"
        case .custom(let id): return "Custom: \(id)"
        }
    }
}

// MARK: - Fault Trigger

/// When to trigger a fault
public enum FaultTrigger: Sendable, Codable, Equatable {
    /// Trigger immediately
    case immediate
    
    /// Trigger after N packets
    case afterPackets(Int)
    
    /// Trigger after N seconds
    case afterTime(seconds: Double)
    
    /// Trigger on specific operation
    case onOperation(String)
    
    /// Trigger probabilistically each time
    case probabilistic(probability: Double)
    
    /// Trigger once then deactivate
    case once
}

// MARK: - Fault Configuration

/// Configuration for a single fault
public struct FaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: FaultType
    public let trigger: FaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: FaultType,
        trigger: FaultTrigger = .immediate,
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

// MARK: - Fault Injection Result

/// Result of a fault injection attempt
public enum FaultInjectionResult: Sendable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected successfully
    case injected(FaultType)
    
    /// Fault was skipped (e.g., probability check failed)
    case skipped(FaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - Fault Injector Protocol

/// Protocol for fault injection in BLE testing
public protocol FaultInjecting: Sendable {
    /// Active fault configurations
    var faults: [FaultConfiguration] { get }
    
    /// Add a fault configuration
    func addFault(_ config: FaultConfiguration)
    
    /// Remove a fault by ID
    func removeFault(id: String)
    
    /// Clear all faults
    func clearFaults()
    
    /// Check if any fault should trigger for this operation
    func shouldInject(for operation: String) -> FaultInjectionResult
    
    /// Record that a packet was processed (for packet-based triggers)
    func recordPacket()
    
    /// Get elapsed time since injector started
    var elapsedTime: TimeInterval { get }
}

// MARK: - Fault Injector

/// Configurable fault injector for BLE testing
public final class FaultInjector: FaultInjecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [FaultConfiguration] = []
    private var _packetCount: Int = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    public var faults: [FaultConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return _faults
    }
    
    public var packetCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _packetCount
    }
    
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(_startTime)
    }
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [FaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    public func addFault(_ config: FaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: FaultType, trigger: FaultTrigger = .immediate) {
        addFault(FaultConfiguration(fault: fault, trigger: trigger))
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
        _packetCount = 0
        _startTime = Date()
        _triggeredOnce.removeAll()
    }
    
    public func recordPacket() {
        lock.lock()
        defer { lock.unlock() }
        _packetCount += 1
    }
    
    public func shouldInject(for operation: String = "") -> FaultInjectionResult {
        lock.lock()
        defer { lock.unlock() }
        
        for config in _faults where config.enabled {
            if shouldTrigger(config, operation: operation) {
                // Mark once-triggered faults
                if case .once = config.trigger {
                    if _triggeredOnce.contains(config.id) {
                        continue
                    }
                    _triggeredOnce.insert(config.id)
                }
                
                // Handle probabilistic faults
                if case .probabilistic(let probability) = config.trigger {
                    if Double.random(in: 0...1) > probability {
                        return .skipped(config.fault)
                    }
                }
                
                // Check probability-based fault types
                switch config.fault {
                case .corruptChecksum(let p), .corruptData(let p),
                     .duplicatePacket(let p), .dropPacket(let p):
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
    
    private func shouldTrigger(_ config: FaultConfiguration, operation: String) -> Bool {
        switch config.trigger {
        case .immediate:
            return true
            
        case .afterPackets(let count):
            return _packetCount >= count
            
        case .afterTime(let seconds):
            return elapsedTime >= seconds
            
        case .onOperation(let op):
            return operation == op
            
        case .probabilistic:
            return true // Handled in shouldInject
            
        case .once:
            return !_triggeredOnce.contains(config.id)
        }
    }
}

// MARK: - Convenience Presets

extension FaultInjector {
    /// Preset: Connection drops after 3 packets
    public static var connectionDrop: FaultInjector {
        FaultInjector(faults: [
            FaultConfiguration(
                fault: .dropConnection(afterPackets: 3),
                trigger: .immediate,
                description: "Drop connection after 3 packets"
            )
        ])
    }
    
    /// Preset: Random packet corruption
    public static var corruptionProne: FaultInjector {
        FaultInjector(faults: [
            FaultConfiguration(
                fault: .corruptChecksum(probability: 0.1),
                trigger: .immediate,
                description: "10% chance of checksum corruption"
            )
        ])
    }
    
    /// Preset: Unreliable connection (multiple faults)
    public static var unreliable: FaultInjector {
        FaultInjector(faults: [
            FaultConfiguration(
                fault: .dropPacket(probability: 0.05),
                trigger: .immediate,
                description: "5% packet drop rate"
            ),
            FaultConfiguration(
                fault: .randomDelay(minMs: 50, maxMs: 500),
                trigger: .probabilistic(probability: 0.2),
                description: "20% chance of random delay"
            ),
            FaultConfiguration(
                fault: .corruptData(probability: 0.02),
                trigger: .immediate,
                description: "2% data corruption"
            )
        ])
    }
    
    /// Preset: Sensor issues
    public static var sensorProblems: FaultInjector {
        FaultInjector(faults: [
            FaultConfiguration(
                fault: .forceWarmup,
                trigger: .once,
                description: "Initial warmup state"
            ),
            FaultConfiguration(
                fault: .sensorFailure(code: 0x01),
                trigger: .afterTime(seconds: 30),
                description: "Sensor failure after 30s"
            )
        ])
    }
    
    /// Preset: Battery dying
    public static var lowBattery: FaultInjector {
        FaultInjector(faults: [
            FaultConfiguration(
                fault: .lowBattery(level: 10),
                trigger: .afterTime(seconds: 10),
                description: "Low battery warning at 10s"
            ),
            FaultConfiguration(
                fault: .dropConnection(afterPackets: 20),
                trigger: .afterTime(seconds: 30),
                description: "Battery death at 30s"
            )
        ])
    }
}

// MARK: - Fault Statistics

/// Statistics about fault injection
public struct FaultInjectionStats: Sendable {
    public var totalPackets: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [FaultCategory: Int] = [:]
    public var lastFault: FaultType?
    public var lastFaultTime: Date?
    
    public init() {}
    
    public mutating func record(_ result: FaultInjectionResult) {
        switch result {
        case .noFault:
            break
        case .injected(let fault):
            faultsInjected += 1
            faultsByCategory[fault.category, default: 0] += 1
            lastFault = fault
            lastFaultTime = Date()
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
