// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEPumpSource.swift
// PumpKit
//
// BLE pump source protocol for real hardware integration.
// Provides the interface that real pump drivers conform to.
// Trace: PUMP-CTX-005, PRD-005
//
// Usage:
//   class OmnipodDashSource: BLEPumpSourceProtocol { ... }
//   let source = BLEPumpSource(config: config)
//   try await source.start()

import Foundation
import T1PalCore

// MARK: - BLE Pump Source

/// Pump source for real BLE hardware
/// This is a wrapper that delegates to actual pump driver implementations
public actor BLEPumpSource: PumpSource {
    
    public nonisolated let sourceType: PumpDataSourceType = .ble
    
    // MARK: - State
    
    private var config: BLEPumpConfig
    private var isRunning: Bool = false
    private var currentStatus: PumpStatus
    private var delegate: (any BLEPumpDelegate)?
    
    // Protocol logger for debugging
    private let protocolLogger: PumpProtocolLogger
    
    // Connection state
    private var connectionAttempts: Int = 0
    private var maxRetries: Int = 3
    private var lastConnectionAttempt: Date?
    
    // WIRE-010: Fault injection and metrics
    public var faultInjector: PumpFaultInjector?
    private let metrics: PumpMetrics
    
    // WIRE-012: Simulation mode for test acceleration
    private var simulationMode: SimulationMode = .demo
    
    // MARK: - Initialization
    
    public init(
        config: BLEPumpConfig,
        faultInjector: PumpFaultInjector? = nil,
        metrics: PumpMetrics = .shared
    ) {
        self.faultInjector = faultInjector
        self.metrics = metrics
        self.config = config
        self.protocolLogger = PumpProtocolLoggerRegistry.shared.logger(
            for: config.pumpSerial ?? "unknown",
            pumpType: config.pumpType.rawValue
        )
        
        self.currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0
        )
    }
    
    // WIRE-012: Simulation mode control
    public func setSimulationMode(_ mode: SimulationMode) {
        simulationMode = mode
    }
    
    public func enableTestMode() {
        setSimulationMode(.test)
    }
    
    /// Conditional delay that skips in test mode (WIRE-012)
    private func simulationDelay(nanoseconds: UInt64) async throws {
        try await simulationMode.delay(nanoseconds: nanoseconds)
    }
    
    // MARK: - PumpSource Protocol
    
    public var status: PumpStatus {
        currentStatus
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        let startTime = Date()
        
        // WIRE-010: Check for fault injection on connect
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "blepumpsource.connect")
            if case .injected(let fault) = result {
                await metrics.recordCommand("blepumpsource.connect", duration: 0, success: false, pumpType: config.pumpType)
                throw mapFaultToError(fault)
            }
        }
        
        currentStatus = PumpStatus(
            connectionState: .connecting,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0
        )
        
        connectionAttempts = 0
        
        // Try to connect with retries
        while connectionAttempts < maxRetries {
            connectionAttempts += 1
            lastConnectionAttempt = Date()
            
            do {
                try await connect()
                isRunning = true
                let duration = Date().timeIntervalSince(startTime)
                await metrics.recordCommand("blepumpsource.connect", duration: duration, success: true, pumpType: config.pumpType)
                return
            } catch {
                if connectionAttempts >= maxRetries {
                    currentStatus = PumpStatus(
                        connectionState: .error,
                        reservoirLevel: nil,
                        batteryLevel: nil,
                        insulinOnBoard: 0
                    )
                    let duration = Date().timeIntervalSince(startTime)
                    await metrics.recordCommand("blepumpsource.connect", duration: duration, success: false, pumpType: config.pumpType)
                    throw BLEPumpError.connectionFailed(attempts: connectionAttempts)
                }
                
                // WIRE-012: Exponential backoff using simulationDelay
                let delay = UInt64(pow(2.0, Double(connectionAttempts))) * 1_000_000_000
                try? await simulationDelay(nanoseconds: delay)
            }
        }
    }
    
    public func stop() async {
        isRunning = false
        
        await disconnect()
        
        currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: currentStatus.reservoirLevel,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
    }
    
    public func execute(_ command: PumpSourceCommand) async throws -> PumpSourceResult {
        guard isRunning else {
            return PumpSourceResult(success: false, command: command, message: "Not connected")
        }
        
        guard currentStatus.connectionState == .connected else {
            return PumpSourceResult(success: false, command: command, message: "Connection not ready")
        }
        
        let startTime = Date()
        let commandName = "blepumpsource.\(command.name)"
        
        // WIRE-010: Check for fault injection on command
        if let injector = faultInjector {
            let result = injector.shouldInject(for: commandName)
            if case .injected(let fault) = result {
                await metrics.recordCommand(commandName, duration: 0, success: false, pumpType: config.pumpType)
                throw mapFaultToError(fault)
            }
        }
        
        // Delegate to actual pump driver
        if let delegate = delegate {
            let result = try await delegate.executeCommand(command, logger: protocolLogger)
            let duration = Date().timeIntervalSince(startTime)
            await metrics.recordCommand(commandName, duration: duration, success: result.success, pumpType: config.pumpType)
            return result
        }
        
        // No delegate - use stub implementation for testing
        let result = try await executeStub(command)
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand(commandName, duration: duration, success: result.success, pumpType: config.pumpType)
        return result
    }
    
    // MARK: - Connection
    
    private func connect() async throws {
        protocolLogger.tx(Data([0x00, 0x01]), context: "BLE Connect")
        
        // In real implementation, this would:
        // 1. Scan for pump BLE advertisement
        // 2. Connect to peripheral
        // 3. Discover services/characteristics
        // 4. Perform authentication handshake
        
        // WIRE-012: simulate connection delay
        try await simulationDelay(nanoseconds: 500_000_000)
        
        // WIRE-012: simulate authentication delay
        protocolLogger.tx(Data([0xA0, 0x01]), context: "Auth Challenge")
        try await simulationDelay(nanoseconds: 200_000_000)
        protocolLogger.rx(Data([0xA0, 0x01, 0x00]), context: "Auth Success")
        
        currentStatus = PumpStatus(
            connectionState: .connected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0
        )
        
        // Read initial status
        let result = try await execute(.readStatus)
        if let status = result.updatedStatus {
            currentStatus = status
        }
    }
    
    private func disconnect() async {
        protocolLogger.tx(Data([0x00, 0xFF]), context: "BLE Disconnect")
        delegate = nil
    }
    
    // MARK: - Stub Implementation
    
    private func executeStub(_ command: PumpSourceCommand) async throws -> PumpSourceResult {
        switch command {
        case .readStatus:
            protocolLogger.tx(Data([0x03, 0x00]), context: "ReadStatus")
            try await simulationDelay(nanoseconds: 100_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x03, 0x00, 0x50, 0x64, 0x00]), context: "Status Response")
            
            currentStatus = PumpStatus(
                connectionState: .connected,
                reservoirLevel: 80,
                batteryLevel: 1.0,
                insulinOnBoard: 2.5,
                lastDelivery: Date()
            )
            
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
            
        case .setTempBasal(let rate, let duration):
            protocolLogger.tx(Data([0x4C, UInt8(rate * 10), UInt8(duration)]), context: "SetTempBasal")
            try await simulationDelay(nanoseconds: 150_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x06, 0x4C, 0x00]), context: "ACK")
            
            return PumpSourceResult(success: true, command: command, message: "Temp basal set")
            
        case .cancelTempBasal:
            protocolLogger.tx(Data([0x4D, 0x00]), context: "CancelTempBasal")
            try await simulationDelay(nanoseconds: 100_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x06, 0x4D, 0x00]), context: "ACK")
            
            return PumpSourceResult(success: true, command: command, message: "Temp basal cancelled")
            
        case .deliverBolus(let units):
            guard currentStatus.connectionState == .connected else {
                return PumpSourceResult(success: false, command: command, message: "Not connected")
            }
            
            protocolLogger.tx(Data([0x4E, UInt8(units * 10)]), context: "Bolus \(units)U")
            try await simulationDelay(nanoseconds: 200_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x06, 0x4E, 0x00]), context: "ACK")
            
            // Update reservoir
            let newReservoir = max(0, (currentStatus.reservoirLevel ?? 0) - units)
            currentStatus = PumpStatus(
                connectionState: currentStatus.connectionState,
                reservoirLevel: newReservoir,
                batteryLevel: currentStatus.batteryLevel,
                insulinOnBoard: currentStatus.insulinOnBoard + units,
                lastDelivery: Date()
            )
            
            return PumpSourceResult(success: true, command: command, message: "Bolus delivered", updatedStatus: currentStatus)
            
        case .suspend:
            protocolLogger.tx(Data([0x4F, 0x01]), context: "Suspend")
            try await simulationDelay(nanoseconds: 100_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x06, 0x4F, 0x00]), context: "ACK")
            
            currentStatus = PumpStatus(
                connectionState: .suspended,
                reservoirLevel: currentStatus.reservoirLevel,
                batteryLevel: currentStatus.batteryLevel,
                insulinOnBoard: currentStatus.insulinOnBoard,
                lastDelivery: currentStatus.lastDelivery
            )
            
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
            
        case .resume:
            protocolLogger.tx(Data([0x50, 0x01]), context: "Resume")
            try await simulationDelay(nanoseconds: 100_000_000)  // WIRE-012
            protocolLogger.rx(Data([0x06, 0x50, 0x00]), context: "ACK")
            
            currentStatus = PumpStatus(
                connectionState: .connected,
                reservoirLevel: currentStatus.reservoirLevel,
                batteryLevel: currentStatus.batteryLevel,
                insulinOnBoard: currentStatus.insulinOnBoard,
                lastDelivery: currentStatus.lastDelivery
            )
            
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
        }
    }
    
    // MARK: - Delegate
    
    /// Set delegate for real pump driver
    public func setDelegate(_ delegate: any BLEPumpDelegate) {
        self.delegate = delegate
    }
    
    // MARK: - Fault Injection Support (WIRE-010)
    
    private func mapFaultToError(_ fault: PumpFaultType) -> BLEPumpError {
        switch fault {
        case .connectionTimeout, .connectionDrop:
            return .connectionFailed(attempts: connectionAttempts)
        case .communicationError, .packetCorruption, .wrongChannelResponse:
            return .communicationError
        case .bleDisconnectMidCommand, .commandDelay:
            return .timeout
        case .occlusion, .airInLine, .emptyReservoir, .motorStall,
             .unexpectedSuspend, .alarmActive, .primeRequired:
            return .communicationError  // Pump-specific faults map to communication error
        case .lowBattery, .batteryDepleted:
            return .communicationError  // Battery faults treated as comm error
        case .intermittentFailure:
            return .communicationError  // Random failures
        }
    }
}

// MARK: - BLE Pump Delegate Protocol

/// Protocol for real pump driver implementations to conform to
public protocol BLEPumpDelegate: Actor {
    /// Execute a pump command
    func executeCommand(_ command: PumpSourceCommand, logger: PumpProtocolLogger) async throws -> PumpSourceResult
    
    /// Connect to pump hardware
    func connect() async throws
    
    /// Disconnect from pump
    func disconnect() async
    
    /// Current connection status
    var isConnected: Bool { get async }
    
    /// Pump identifier (serial, pod ID, etc.)
    var pumpIdentifier: String { get }
}

// MARK: - BLE Pump Errors

public enum BLEPumpError: Error, LocalizedError, Sendable {
    case connectionFailed(attempts: Int)
    case authenticationFailed
    case communicationError
    case timeout
    case pumpNotFound
    case bridgeNotFound
    case unsupportedPump
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let attempts):
            return "Connection failed after \(attempts) attempts"
        case .authenticationFailed:
            return "Pump authentication failed"
        case .communicationError:
            return "Communication error with pump"
        case .timeout:
            return "Pump communication timeout"
        case .pumpNotFound:
            return "Pump not found during BLE scan"
        case .bridgeNotFound:
            return "RF bridge device not found"
        case .unsupportedPump:
            return "Pump type not supported"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance (COMPL-DUP-004)

extension BLEPumpError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .pump }
    
    public var code: String {
        switch self {
        case .connectionFailed: return "PUMP-CONN-001"
        case .authenticationFailed: return "PUMP-AUTH-001"
        case .communicationError: return "PUMP-COMM-001"
        case .timeout: return "PUMP-TIMEOUT-001"
        case .pumpNotFound: return "PUMP-NOTFOUND-001"
        case .bridgeNotFound: return "PUMP-BRIDGE-001"
        case .unsupportedPump: return "PUMP-UNSUPPORTED-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .authenticationFailed, .unsupportedPump: return .critical
        case .timeout, .communicationError: return .error
        default: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .connectionFailed, .communicationError, .timeout: return .reconnect
        case .authenticationFailed: return .reauthenticate
        case .pumpNotFound, .bridgeNotFound: return .checkDevice
        case .unsupportedPump: return .contactSupport
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Pump error"
    }
}

// MARK: - PumpSourceCommand Name Extension (WIRE-010)

extension PumpSourceCommand {
    /// Command name for metrics and fault injection
    var name: String {
        switch self {
        case .readStatus:
            return "readStatus"
        case .setTempBasal:
            return "setTempBasal"
        case .cancelTempBasal:
            return "cancelTempBasal"
        case .deliverBolus:
            return "deliverBolus"
        case .suspend:
            return "suspend"
        case .resume:
            return "resume"
        }
    }
}
