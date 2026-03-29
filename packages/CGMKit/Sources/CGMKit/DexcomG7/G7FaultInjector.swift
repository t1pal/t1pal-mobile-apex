// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7FaultInjector.swift
// CGMKit - DexcomG7
//
// Fault injection for Dexcom G7 testing.
// Enables systematic testing of error handling and edge cases.
// G7-specific: J-PAKE authentication, one-piece sensor, sensor code scenarios.
// Trace: G7-FIX-016, SIM-FAULT-001, synthesized-device-testing.md
//
// Usage:
//   let injector = G7FaultInjector.jpakeTimeout
//   if case .injected(let fault) = injector.shouldInject(for: "authenticate") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - G7 Fault Types

/// G7-specific fault types
public enum G7FaultType: Sendable, Codable, Equatable {
    // J-PAKE Authentication faults
    case jpakeTimeout                       // J-PAKE round timeout
    case jpakeRejected                      // ZK proof verification failed
    case sensorCodeMismatch                 // Wrong 4-digit code
    case pairingFailed                      // Pairing step failed
    case bondLost                           // Bonding information lost
    case sessionKeyDerivationFailed         // Key derivation error
    
    // Connection faults
    case connectionDrop                     // BLE disconnect
    case connectionTimeout                  // No response
    case scanTimeout                        // Scanning timeout
    case advertisementMissing               // Sensor not advertising
    
    // Sensor faults
    case sensorExpired                      // Sensor session expired (10 days)
    case sensorWarmup                       // Sensor in warmup period (~30 min for G7)
    case sensorFailed(code: UInt8)          // Sensor failure
    case noSignal                           // No glucose signal
    case algorithmUnreliable                // Algorithm state unreliable
    
    // Communication faults
    case packetCorruption(probability: Double)  // Corrupt packets
    case responseDelay(milliseconds: Int)   // Delayed response
    case characteristicNotFound             // Missing BLE characteristic
    case notificationDropped                // BLE notification lost
    
    // Sensor lifecycle faults
    case gracePeriodExpired                 // Grace period after session end
    case sensorNotStarted                   // Sensor never initialized
    case firmwareMismatch                   // Firmware version incompatible
    
    public var displayName: String {
        switch self {
        case .jpakeTimeout: return "J-PAKE Timeout"
        case .jpakeRejected: return "J-PAKE Rejected"
        case .sensorCodeMismatch: return "Sensor Code Mismatch"
        case .pairingFailed: return "Pairing Failed"
        case .bondLost: return "Bond Lost"
        case .sessionKeyDerivationFailed: return "Key Derivation Failed"
        case .connectionDrop: return "Connection Drop"
        case .connectionTimeout: return "Connection Timeout"
        case .scanTimeout: return "Scan Timeout"
        case .advertisementMissing: return "Advertisement Missing"
        case .sensorExpired: return "Sensor Expired"
        case .sensorWarmup: return "Sensor Warmup"
        case .sensorFailed(let code): return "Sensor Failed (0x\(String(code, radix: 16)))"
        case .noSignal: return "No Signal"
        case .algorithmUnreliable: return "Algorithm Unreliable"
        case .packetCorruption(let p): return "Packet Corruption (\(Int(p * 100))%)"
        case .responseDelay(let ms): return "Response Delay (\(ms)ms)"
        case .characteristicNotFound: return "Characteristic Not Found"
        case .notificationDropped: return "Notification Dropped"
        case .gracePeriodExpired: return "Grace Period Expired"
        case .sensorNotStarted: return "Sensor Not Started"
        case .firmwareMismatch: return "Firmware Mismatch"
        }
    }
    
    public var category: G7FaultCategory {
        switch self {
        case .jpakeTimeout, .jpakeRejected, .sensorCodeMismatch, .pairingFailed,
             .bondLost, .sessionKeyDerivationFailed:
            return .authentication
        case .connectionDrop, .connectionTimeout, .scanTimeout, .advertisementMissing:
            return .connection
        case .sensorExpired, .sensorWarmup, .sensorFailed, .noSignal, .algorithmUnreliable:
            return .sensor
        case .packetCorruption, .responseDelay, .characteristicNotFound, .notificationDropped:
            return .communication
        case .gracePeriodExpired, .sensorNotStarted, .firmwareMismatch:
            return .lifecycle
        }
    }
    
    /// Whether this fault should stop data streaming
    public var stopsStreaming: Bool {
        switch self {
        case .jpakeTimeout, .jpakeRejected, .sensorCodeMismatch, .pairingFailed,
             .bondLost, .sessionKeyDerivationFailed,
             .connectionDrop, .connectionTimeout, .sensorExpired, .sensorFailed,
             .gracePeriodExpired, .firmwareMismatch:
            return true
        default:
            return false
        }
    }
    
    /// Whether this fault allows retry with different sensor code
    public var allowsCodeRetry: Bool {
        switch self {
        case .sensorCodeMismatch, .jpakeRejected:
            return true
        default:
            return false
        }
    }
}

/// Categories of G7 faults
public enum G7FaultCategory: String, Codable, Sendable, CaseIterable {
    case authentication  // J-PAKE and pairing issues
    case connection      // BLE connection issues
    case sensor          // CGM sensor issues
    case communication   // Protocol issues
    case lifecycle       // Sensor lifecycle issues
}

// MARK: - G7 Fault Trigger

/// When to trigger a G7 fault
public enum G7FaultTrigger: Sendable, Codable, Equatable {
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
    
    /// Trigger on specific J-PAKE round
    case onJPAKERound(Int)
}

// MARK: - G7 Fault Configuration

/// Configuration for a single G7 fault
public struct G7FaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: G7FaultType
    public let trigger: G7FaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: G7FaultType,
        trigger: G7FaultTrigger = .immediate,
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

// MARK: - G7 Fault Injection Result

/// Result of a G7 fault injection attempt
public enum G7FaultInjectionResult: Sendable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(G7FaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(G7FaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - G7 Fault Injector

/// Fault injector for Dexcom G7 testing
public final class G7FaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [G7FaultConfiguration] = []
    private var _operationCount: Int = 0
    private var _readingCount: Int = 0
    private var _jpakeRound: Int = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [G7FaultConfiguration] {
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
    
    public var jpakeRound: Int {
        lock.lock()
        defer { lock.unlock() }
        return _jpakeRound
    }
    
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(_startTime)
    }
    
    // MARK: - Initialization
    
    public init() {
        _startTime = Date()
    }
    
    public init(faults: [G7FaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: G7FaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: G7FaultType, trigger: G7FaultTrigger = .immediate) {
        addFault(G7FaultConfiguration(fault: fault, trigger: trigger))
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
        _jpakeRound = 0
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
    
    public func recordJPAKERound(_ round: Int) {
        lock.lock()
        defer { lock.unlock() }
        _jpakeRound = round
    }
    
    // MARK: - Injection
    
    public func shouldInject(for operation: String = "") -> G7FaultInjectionResult {
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
    
    private func shouldTrigger(_ config: G7FaultConfiguration, operation: String) -> Bool {
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
            
        case .onJPAKERound(let round):
            return _jpakeRound == round
        }
    }
}

// MARK: - Preset G7 Fault Injectors

extension G7FaultInjector {
    
    /// Preset: J-PAKE timeout during authentication
    public static var jpakeTimeout: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .jpakeTimeout,
                trigger: .onOperation("authenticate"),
                description: "J-PAKE timeout during authentication"
            )
        ])
    }
    
    /// Preset: J-PAKE rejected (ZK proof failed)
    public static var jpakeRejected: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .jpakeRejected,
                trigger: .onOperation("authenticate"),
                description: "J-PAKE rejected - ZK proof verification failed"
            )
        ])
    }
    
    /// Preset: Sensor code mismatch (wrong 4-digit code)
    public static var sensorCodeMismatch: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .sensorCodeMismatch,
                trigger: .onOperation("authenticate"),
                description: "Wrong sensor code entered"
            )
        ])
    }
    
    /// Preset: Pairing failed scenario
    public static var pairingFailed: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .pairingFailed,
                trigger: .onOperation("pair"),
                description: "Pairing step failed"
            )
        ])
    }
    
    /// Preset: Bond lost scenario
    public static var bondLost: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .bondLost,
                trigger: .once,
                description: "Bonding information lost"
            )
        ])
    }
    
    /// Preset: Sensor expired
    public static var sensorExpired: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .sensorExpired,
                trigger: .onOperation("readGlucose"),
                description: "Sensor session expired (10 days)"
            )
        ])
    }
    
    /// Preset: Sensor warmup period (G7 ~30 min)
    public static var sensorWarmup: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .sensorWarmup,
                trigger: .immediate,
                description: "Sensor in 30-minute warmup"
            )
        ])
    }
    
    /// Preset: Unreliable connection
    public static var unreliableConnection: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of connection drop"
            ),
            G7FaultConfiguration(
                fault: .responseDelay(milliseconds: 500),
                trigger: .probabilistic(probability: 0.10),
                description: "10% chance of 500ms delay"
            ),
            G7FaultConfiguration(
                fault: .packetCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% packet corruption"
            )
        ])
    }
    
    /// Preset: No signal scenario
    public static var noSignal: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .noSignal,
                trigger: .afterTime(seconds: 30),
                description: "Signal loss after 30 seconds"
            )
        ])
    }
    
    /// Preset: J-PAKE Round 2 timeout (mid-authentication)
    public static var jpakeRound2Timeout: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .jpakeTimeout,
                trigger: .onJPAKERound(2),
                description: "J-PAKE timeout during Round 2"
            )
        ])
    }
    
    /// Preset: Stress test (multiple faults)
    public static var stressTest: G7FaultInjector {
        G7FaultInjector(faults: [
            G7FaultConfiguration(
                fault: .packetCorruption(probability: 0.15),
                trigger: .immediate,
                description: "15% packet corruption"
            ),
            G7FaultConfiguration(
                fault: .responseDelay(milliseconds: 200),
                trigger: .probabilistic(probability: 0.30),
                description: "30% chance of delays"
            ),
            G7FaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.03),
                description: "3% connection drops"
            ),
            G7FaultConfiguration(
                fault: .notificationDropped,
                trigger: .probabilistic(probability: 0.05),
                description: "5% notification drops"
            )
        ])
    }
}

// MARK: - G7 Fault Statistics

/// Statistics about G7 fault injection
public struct G7FaultInjectionStats: Sendable {
    public var totalOperations: Int = 0
    public var totalReadings: Int = 0
    public var faultsInjected: Int = 0
    public var faultsSkipped: Int = 0
    public var faultsByCategory: [G7FaultCategory: Int] = [:]
    public var lastFault: G7FaultType?
    public var lastFaultTime: Date?
    public var streamingInterruptions: Int = 0
    public var codeRetryOpportunities: Int = 0
    
    public init() {}
    
    public mutating func record(_ result: G7FaultInjectionResult) {
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
            if fault.allowsCodeRetry {
                codeRetryOpportunities += 1
            }
        case .skipped:
            faultsSkipped += 1
        case .error:
            break
        }
    }
}
