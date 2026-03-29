// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6FaultInjector.swift
// CGMKit - DexcomG6
//
// Fault injection for Dexcom G6 testing.
// Enables systematic testing of error handling and edge cases.
// Trace: G6-FIX-016, SIM-FAULT-001, synthesized-device-testing.md
//
// Usage:
//   let injector = G6FaultInjector.authTimeout
//   if case .injected(let fault) = injector.shouldInject(for: "authenticate") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - G6 Fault Types

/// G6-specific fault types
public enum G6FaultType: Sendable, Codable, Equatable {
    // Authentication faults
    case authTimeout                        // Authentication timeout
    case authRejected(code: UInt8)          // Authentication rejected
    case bondLost                           // Bonding information lost
    case challengeFailed                    // Challenge verification failed
    
    // Connection faults
    case connectionDrop                     // BLE disconnect
    case connectionTimeout                  // No response
    case scanTimeout                        // Scanning timeout
    
    // Sensor faults
    case sensorExpired                      // Sensor session expired
    case sensorWarmup                       // Sensor in warmup period
    case sensorFailed(code: UInt8)          // Sensor failure
    case noSignal                           // No glucose signal
    
    // Communication faults
    case packetCorruption(probability: Double)  // Corrupt packets
    case responseDelay(milliseconds: Int)   // Delayed response
    case characteristicNotFound             // Missing BLE characteristic
    
    // Transmitter faults
    case lowBattery(days: Int)              // Low battery warning
    case transmitterExpired                 // Transmitter past expiry
    case firmwareMismatch                   // Firmware version incompatible
    
    public var displayName: String {
        switch self {
        case .authTimeout: return "Auth Timeout"
        case .authRejected(let code): return "Auth Rejected (0x\(String(code, radix: 16)))"
        case .bondLost: return "Bond Lost"
        case .challengeFailed: return "Challenge Failed"
        case .connectionDrop: return "Connection Drop"
        case .connectionTimeout: return "Connection Timeout"
        case .scanTimeout: return "Scan Timeout"
        case .sensorExpired: return "Sensor Expired"
        case .sensorWarmup: return "Sensor Warmup"
        case .sensorFailed(let code): return "Sensor Failed (0x\(String(code, radix: 16)))"
        case .noSignal: return "No Signal"
        case .packetCorruption(let p): return "Packet Corruption (\(Int(p * 100))%)"
        case .responseDelay(let ms): return "Response Delay (\(ms)ms)"
        case .characteristicNotFound: return "Characteristic Not Found"
        case .lowBattery(let days): return "Low Battery (\(days) days)"
        case .transmitterExpired: return "Transmitter Expired"
        case .firmwareMismatch: return "Firmware Mismatch"
        }
    }
    
    public var category: G6FaultCategory {
        switch self {
        case .authTimeout, .authRejected, .bondLost, .challengeFailed:
            return .authentication
        case .connectionDrop, .connectionTimeout, .scanTimeout:
            return .connection
        case .sensorExpired, .sensorWarmup, .sensorFailed, .noSignal:
            return .sensor
        case .packetCorruption, .responseDelay, .characteristicNotFound:
            return .communication
        case .lowBattery, .transmitterExpired, .firmwareMismatch:
            return .transmitter
        }
    }
    
    /// Whether this fault should stop data streaming
    public var stopsStreaming: Bool {
        switch self {
        case .authTimeout, .authRejected, .bondLost, .challengeFailed,
             .connectionDrop, .connectionTimeout, .sensorExpired, .sensorFailed,
             .transmitterExpired, .firmwareMismatch:
            return true
        default:
            return false
        }
    }
}

/// Categories of G6 faults
public enum G6FaultCategory: String, Codable, Sendable, CaseIterable {
    case authentication  // Auth issues
    case connection      // BLE connection issues
    case sensor          // CGM sensor issues
    case communication   // Protocol issues
    case transmitter     // Transmitter issues
}

// MARK: - G6 Fault Trigger

/// When to trigger a G6 fault
public enum G6FaultTrigger: Sendable, Codable, Equatable {
    /// Trigger immediately on matching operation
    case immediate
    
    /// Trigger after N operations
    case afterOperations(Int)
    
    /// Trigger after N seconds
    case afterTime(seconds: Double)
    
    /// Trigger on specific operation type
    case onOperation(String)
    
    /// Trigger with probability
    case probabilistic(probability: Double)
    
    /// Trigger once then disable
    case once
    
    /// Trigger after N glucose readings
    case afterReadings(Int)
}

// MARK: - G6 Fault Configuration

/// Configuration for a single G6 fault
public struct G6FaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: G6FaultType
    public let trigger: G6FaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: G6FaultType,
        trigger: G6FaultTrigger = .immediate,
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

// MARK: - G6 Fault Injection Result

/// Result of a G6 fault injection attempt
public enum G6FaultInjectionResult: Sendable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(G6FaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(G6FaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - G6 Fault Injector

/// Fault injector for Dexcom G6 testing
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// - All mutable state protected by NSLock
/// - Test infrastructure requires synchronous access
/// Trace: TECH-001, PROD-READY-012
public final class G6FaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [G6FaultConfiguration] = []
    private var _operationCount: Int = 0
    private var _readingCount: Int = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [G6FaultConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return _faults
    }
    
    public var operationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _operationCount
    }
    
    public var readingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readingCount
    }
    
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(_startTime)
    }
    
    // MARK: - Initialization
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [G6FaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: G6FaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: G6FaultType, trigger: G6FaultTrigger = .immediate) {
        addFault(G6FaultConfiguration(fault: fault, trigger: trigger))
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
        _operationCount = 0
        _readingCount = 0
        _startTime = Date()
        _triggeredOnce.removeAll()
    }
    
    // MARK: - Recording
    
    public func recordOperation() {
        lock.lock()
        defer { lock.unlock() }
        _operationCount += 1
    }
    
    public func recordReading() {
        lock.lock()
        defer { lock.unlock() }
        _readingCount += 1
    }
    
    // MARK: - Injection
    
    public func shouldInject(for operation: String = "") -> G6FaultInjectionResult {
        lock.lock()
        defer { lock.unlock() }
        
        for config in _faults where config.enabled {
            if shouldTrigger(config, operation: operation) {
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
                if case .packetCorruption(let p) = config.fault {
                    if Double.random(in: 0...1) > p {
                        return .skipped(config.fault)
                    }
                }
                
                return .injected(config.fault)
            }
        }
        
        return .noFault
    }
    
    private func shouldTrigger(_ config: G6FaultConfiguration, operation: String) -> Bool {
        switch config.trigger {
        case .immediate:
            return true
            
        case .afterOperations(let count):
            return _operationCount >= count
            
        case .afterTime(let seconds):
            return elapsedTime >= seconds
            
        case .onOperation(let op):
            return operation == op
            
        case .probabilistic:
            return true  // Handled in shouldInject
            
        case .once:
            return !_triggeredOnce.contains(config.id)
            
        case .afterReadings(let count):
            return _readingCount >= count
        }
    }
}

// MARK: - Preset G6 Fault Injectors

extension G6FaultInjector {
    
    /// Preset: Authentication timeout
    public static var authTimeout: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .authTimeout,
                trigger: .onOperation("authenticate"),
                description: "Auth timeout during authentication"
            )
        ])
    }
    
    /// Preset: Authentication rejected (invalid transmitter ID)
    public static var authRejected: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .authRejected(code: 0x01),
                trigger: .onOperation("authenticate"),
                description: "Auth rejected - invalid transmitter"
            )
        ])
    }
    
    /// Preset: Bond lost scenario
    public static var bondLost: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .bondLost,
                trigger: .once,
                description: "Bonding information lost"
            )
        ])
    }
    
    /// Preset: Sensor expired
    public static var sensorExpired: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .sensorExpired,
                trigger: .onOperation("readGlucose"),
                description: "Sensor session expired"
            )
        ])
    }
    
    /// Preset: Sensor warmup period
    public static var sensorWarmup: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .sensorWarmup,
                trigger: .immediate,
                description: "Sensor in 2-hour warmup"
            )
        ])
    }
    
    /// Preset: Unreliable connection
    public static var unreliableConnection: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of connection drop"
            ),
            G6FaultConfiguration(
                fault: .responseDelay(milliseconds: 500),
                trigger: .probabilistic(probability: 0.10),
                description: "10% chance of 500ms delay"
            ),
            G6FaultConfiguration(
                fault: .packetCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% packet corruption"
            )
        ])
    }
    
    /// Preset: Low battery warning
    public static var lowBattery: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .lowBattery(days: 7),
                trigger: .afterReadings(5),
                description: "Low battery after 5 readings"
            )
        ])
    }
    
    /// Preset: No signal scenario
    public static var noSignal: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .noSignal,
                trigger: .afterTime(seconds: 30),
                description: "Signal loss after 30 seconds"
            )
        ])
    }
    
    /// Preset: Stress test (multiple faults)
    public static var stressTest: G6FaultInjector {
        G6FaultInjector(faults: [
            G6FaultConfiguration(
                fault: .packetCorruption(probability: 0.15),
                trigger: .immediate,
                description: "15% packet corruption"
            ),
            G6FaultConfiguration(
                fault: .responseDelay(milliseconds: 200),
                trigger: .probabilistic(probability: 0.30),
                description: "30% chance of delays"
            ),
            G6FaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.03),
                description: "3% connection drops"
            )
        ])
    }
}

// MARK: - G6 Fault Statistics

/// Statistics about G6 fault injection
public struct G6FaultInjectionStats: Sendable {
    public var totalOperations: Int = 0
    public var totalReadings: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [G6FaultCategory: Int] = [:]
    public var lastFault: G6FaultType?
    public var lastFaultTime: Date?
    public var streamingInterruptions: Int = 0
    
    public init() {}
    
    public mutating func record(_ result: G6FaultInjectionResult) {
        switch result {
        case .noFault:
            break
        case .injected(let fault):
            faultsInjected += 1
            faultsByCategory[fault.category, default: 0] += 1
            lastFault = fault
            lastFaultTime = Date()
            if fault.stopsStreaming {
                streamingInterruptions += 1
            }
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
