// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LibreFaultInjector.swift
// CGMKit - Libre2
//
// Fault injection for FreeStyle Libre 2/3 testing.
// Enables systematic testing of error handling and edge cases.
// Trace: LIBRE-FIX-015, SIM-FAULT-001
//
// Usage:
//   let injector = LibreFaultInjector.unlockTimeout
//   if case .injected(let fault) = injector.shouldInject(for: "unlock") {
//       // Handle fault injection
//   }

import Foundation

// MARK: - Libre Fault Types

/// Libre-specific fault types
public enum LibreFaultType: Sendable, Codable, Equatable {
    // Authentication faults
    case unlockTimeout                      // Unlock sequence timeout
    case unlockRejected(code: UInt8)        // Unlock rejected by sensor
    case cryptoFailed                       // Decryption/encryption failure
    case unlockCountMismatch                // Unlock counter out of sync
    
    // Connection faults
    case connectionDrop                     // BLE disconnect
    case connectionTimeout                  // No response
    case scanTimeout                        // Scanning timeout
    case nfcRequired                        // NFC activation needed first
    
    // Sensor faults
    case sensorExpired                      // Sensor past 14-day life
    case sensorWarmup                       // Sensor in 60-min warmup
    case sensorFailed(code: UInt8)          // Sensor hardware failure
    case sensorNotActivated                 // NFC not yet used
    case sensorReplaced                     // Different sensor detected
    
    // Communication faults
    case packetCorruption(probability: Double)  // Corrupt packets
    case responseDelay(milliseconds: Int)   // Delayed response
    case characteristicNotFound             // Missing BLE characteristic
    case invalidDataFrame                   // Data frame CRC failure
    
    // Region/firmware faults
    case regionLocked                       // Wrong region firmware
    case firmwareUnsupported                // Firmware version unknown
    case patchInfoMismatch                  // Patch info doesn't match sensor
    
    public var displayName: String {
        switch self {
        case .unlockTimeout: return "Unlock Timeout"
        case .unlockRejected(let code): return "Unlock Rejected (0x\(String(code, radix: 16)))"
        case .cryptoFailed: return "Crypto Failed"
        case .unlockCountMismatch: return "Unlock Count Mismatch"
        case .connectionDrop: return "Connection Drop"
        case .connectionTimeout: return "Connection Timeout"
        case .scanTimeout: return "Scan Timeout"
        case .nfcRequired: return "NFC Required"
        case .sensorExpired: return "Sensor Expired"
        case .sensorWarmup: return "Sensor Warmup"
        case .sensorFailed(let code): return "Sensor Failed (0x\(String(code, radix: 16)))"
        case .sensorNotActivated: return "Sensor Not Activated"
        case .sensorReplaced: return "Sensor Replaced"
        case .packetCorruption(let p): return "Packet Corruption (\(Int(p * 100))%)"
        case .responseDelay(let ms): return "Response Delay (\(ms)ms)"
        case .characteristicNotFound: return "Characteristic Not Found"
        case .invalidDataFrame: return "Invalid Data Frame"
        case .regionLocked: return "Region Locked"
        case .firmwareUnsupported: return "Firmware Unsupported"
        case .patchInfoMismatch: return "Patch Info Mismatch"
        }
    }
    
    public var category: LibreFaultCategory {
        switch self {
        case .unlockTimeout, .unlockRejected, .cryptoFailed, .unlockCountMismatch:
            return .authentication
        case .connectionDrop, .connectionTimeout, .scanTimeout, .nfcRequired:
            return .connection
        case .sensorExpired, .sensorWarmup, .sensorFailed, .sensorNotActivated, .sensorReplaced:
            return .sensor
        case .packetCorruption, .responseDelay, .characteristicNotFound, .invalidDataFrame:
            return .communication
        case .regionLocked, .firmwareUnsupported, .patchInfoMismatch:
            return .firmware
        }
    }
    
    /// Whether this fault should stop data streaming
    public var stopsStreaming: Bool {
        switch self {
        case .unlockTimeout, .unlockRejected, .cryptoFailed, .unlockCountMismatch,
             .connectionDrop, .connectionTimeout, .sensorExpired, .sensorFailed,
             .sensorNotActivated, .sensorReplaced, .regionLocked, .firmwareUnsupported:
            return true
        default:
            return false
        }
    }
}

/// Categories of Libre faults
public enum LibreFaultCategory: String, Codable, Sendable, CaseIterable {
    case authentication  // Unlock/crypto issues
    case connection      // BLE connection issues
    case sensor          // CGM sensor issues
    case communication   // Protocol issues
    case firmware        // Firmware/region issues
}

// MARK: - Libre Fault Trigger

/// When to trigger a Libre fault
public enum LibreFaultTrigger: Sendable, Codable, Equatable {
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

// MARK: - Libre Fault Configuration

/// Configuration for a single Libre fault
public struct LibreFaultConfiguration: Sendable, Codable, Equatable {
    public let id: String
    public let fault: LibreFaultType
    public let trigger: LibreFaultTrigger
    public var enabled: Bool
    public var description: String
    
    public init(
        id: String = UUID().uuidString,
        fault: LibreFaultType,
        trigger: LibreFaultTrigger = .immediate,
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

// MARK: - Libre Fault Injection Result

/// Result of a Libre fault injection attempt
public enum LibreFaultInjectionResult: Sendable {
    /// No fault was injected
    case noFault
    
    /// Fault was injected
    case injected(LibreFaultType)
    
    /// Fault was skipped (probability check failed)
    case skipped(LibreFaultType)
    
    /// Error during injection
    case error(String)
}

// MARK: - Libre Fault Injector

/// Fault injector for FreeStyle Libre testing
public final class LibreFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var _faults: [LibreFaultConfiguration] = []
    private var _operationCount: Int = 0
    private var _readingCount: Int = 0
    private var _startTime: Date = Date()
    private var _triggeredOnce: Set<String> = []
    
    // MARK: - Properties
    
    public var faults: [LibreFaultConfiguration] {
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
    
    public init(faults: [LibreFaultConfiguration]) {
        _startTime = Date()
        _faults = faults
    }
    
    // MARK: - Configuration
    
    public func addFault(_ config: LibreFaultConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _faults.append(config)
    }
    
    public func addFault(_ fault: LibreFaultType, trigger: LibreFaultTrigger = .immediate) {
        addFault(LibreFaultConfiguration(fault: fault, trigger: trigger))
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
    
    public func shouldInject(for operation: String = "") -> LibreFaultInjectionResult {
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
    
    private func shouldTrigger(_ config: LibreFaultConfiguration, operation: String) -> Bool {
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

// MARK: - Preset Libre Fault Injectors

extension LibreFaultInjector {
    
    /// Preset: Unlock timeout
    public static var unlockTimeout: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .unlockTimeout,
                trigger: .onOperation("unlock"),
                description: "Unlock timeout during BLE authentication"
            )
        ])
    }
    
    /// Preset: Unlock rejected (bad unlock count)
    public static var unlockRejected: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .unlockRejected(code: 0x01),
                trigger: .onOperation("unlock"),
                description: "Unlock rejected - invalid sequence"
            )
        ])
    }
    
    /// Preset: Unlock counter mismatch
    public static var unlockCountMismatch: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .unlockCountMismatch,
                trigger: .once,
                description: "Unlock counter out of sync with sensor"
            )
        ])
    }
    
    /// Preset: Crypto failure
    public static var cryptoFailed: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .cryptoFailed,
                trigger: .onOperation("decrypt"),
                description: "Decryption failed"
            )
        ])
    }
    
    /// Preset: Sensor expired
    public static var sensorExpired: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .sensorExpired,
                trigger: .onOperation("readGlucose"),
                description: "Sensor past 14-day life"
            )
        ])
    }
    
    /// Preset: Sensor warmup period
    public static var sensorWarmup: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .sensorWarmup,
                trigger: .immediate,
                description: "Sensor in 60-minute warmup"
            )
        ])
    }
    
    /// Preset: NFC activation required
    public static var nfcRequired: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .nfcRequired,
                trigger: .onOperation("connect"),
                description: "Sensor must be NFC activated first"
            )
        ])
    }
    
    /// Preset: Sensor replaced
    public static var sensorReplaced: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .sensorReplaced,
                trigger: .onOperation("scan"),
                description: "Different sensor UID detected"
            )
        ])
    }
    
    /// Preset: Unreliable connection
    public static var unreliableConnection: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .connectionDrop,
                trigger: .probabilistic(probability: 0.05),
                description: "5% chance of connection drop"
            ),
            LibreFaultConfiguration(
                fault: .responseDelay(milliseconds: 500),
                trigger: .probabilistic(probability: 0.10),
                description: "10% chance of 500ms delay"
            ),
            LibreFaultConfiguration(
                fault: .packetCorruption(probability: 0.02),
                trigger: .immediate,
                description: "2% packet corruption"
            )
        ])
    }
    
    /// Preset: Region locked scenario
    public static var regionLocked: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .regionLocked,
                trigger: .onOperation("connect"),
                description: "Sensor firmware locked to different region"
            )
        ])
    }
    
    /// Preset: Patch info mismatch
    public static var patchInfoMismatch: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .patchInfoMismatch,
                trigger: .onOperation("unlock"),
                description: "Patch info doesn't match stored sensor"
            )
        ])
    }
    
    /// Preset: Invalid data frame (CRC error)
    public static var invalidDataFrame: LibreFaultInjector {
        LibreFaultInjector(faults: [
            LibreFaultConfiguration(
                fault: .invalidDataFrame,
                trigger: .afterReadings(3),
                description: "CRC error after 3 readings"
            )
        ])
    }
}
