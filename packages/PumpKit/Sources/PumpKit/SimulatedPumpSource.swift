// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SimulatedPumpSource.swift
// PumpKit
//
// Simulated pump data source for demo and testing.
// Generates configurable pump patterns without real hardware.
// Trace: PUMP-CTX-002, PRD-005
//
// Usage:
//   let source = SimulatedPumpSource(config: .init(pattern: .normal))
//   try await source.start()
//   let status = await source.status

import Foundation

// MARK: - Simulated Pump Source

/// Pump source that generates simulated data
public actor SimulatedPumpSource: PumpSource {
    
    public nonisolated let sourceType: PumpDataSourceType = .simulated
    
    // MARK: - State
    
    private var config: SimulatedPumpConfig
    private var isRunning: Bool = false
    private var updateTask: Task<Void, Never>?
    
    // Current simulated state
    private var currentStatus: PumpStatus
    private var currentTempBasal: TempBasalInfo?
    private var bolusInProgress: BolusInfo?
    private var isSuspended: Bool = false
    
    // Protocol logger for simulated bytes
    private let protocolLogger: PumpProtocolLogger
    
    // MARK: - Initialization
    
    public init(config: SimulatedPumpConfig = SimulatedPumpConfig()) {
        self.config = config
        self.protocolLogger = PumpProtocolLogger(pumpType: "simulation", pumpId: "sim-\(UUID().uuidString.prefix(8))")
        
        self.currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: config.reservoirLevel,
            batteryLevel: config.batteryLevel,
            insulinOnBoard: config.iobBase
        )
    }
    
    // MARK: - PumpSource Protocol
    
    public var status: PumpStatus {
        currentStatus
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        isRunning = true
        
        // Simulate connection
        protocolLogger.tx(Data([0x00, 0x01]), context: "Connect")
        try await Task.sleep(nanoseconds: 300_000_000)  // 300ms
        protocolLogger.rx(Data([0x00, 0x01, 0x00]), context: "Connected ACK")
        
        currentStatus = PumpStatus(
            connectionState: .connected,
            reservoirLevel: config.reservoirLevel,
            batteryLevel: config.batteryLevel,
            insulinOnBoard: config.iobBase,
            lastDelivery: Date()
        )
        
        // Start background update task based on pattern
        startPatternUpdates()
    }
    
    public func stop() async {
        isRunning = false
        updateTask?.cancel()
        updateTask = nil
        
        protocolLogger.tx(Data([0x00, 0xFF]), context: "Disconnect")
        
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
        
        switch command {
        case .setTempBasal(let rate, let durationMinutes):
            return try await setTempBasal(rate: rate, durationMinutes: durationMinutes)
            
        case .cancelTempBasal:
            return try await cancelTempBasal()
            
        case .deliverBolus(let units):
            return try await deliverBolus(units: units)
            
        case .suspend:
            return try await suspend()
            
        case .resume:
            return try await resume()
            
        case .readStatus:
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
        }
    }
    
    // MARK: - Command Implementations
    
    private func setTempBasal(rate: Double, durationMinutes: Double) async throws -> PumpSourceResult {
        // Log protocol bytes
        let rateBytes = UInt16(rate * 100)
        let durationBytes = UInt16(durationMinutes)
        protocolLogger.tx(Data([0x4C, UInt8(rateBytes >> 8), UInt8(rateBytes & 0xFF), UInt8(durationBytes >> 8), UInt8(durationBytes & 0xFF)]), context: "SetTempBasal \(rate)U/hr \(Int(durationMinutes))min")
        
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        protocolLogger.rx(Data([0x06, 0x4C, 0x00]), context: "ACK")
        
        currentTempBasal = TempBasalInfo(
            rate: rate,
            startTime: Date(),
            durationMinutes: durationMinutes
        )
        
        return PumpSourceResult(
            success: true,
            command: .setTempBasal(rate: rate, durationMinutes: durationMinutes),
            message: "Temp basal set: \(rate)U/hr for \(Int(durationMinutes))min",
            updatedStatus: currentStatus
        )
    }
    
    private func cancelTempBasal() async throws -> PumpSourceResult {
        protocolLogger.tx(Data([0x4D, 0x00]), context: "CancelTempBasal")
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        protocolLogger.rx(Data([0x06, 0x4D, 0x00]), context: "ACK")
        
        currentTempBasal = nil
        
        return PumpSourceResult(
            success: true,
            command: .cancelTempBasal,
            message: "Temp basal cancelled"
        )
    }
    
    private func deliverBolus(units: Double) async throws -> PumpSourceResult {
        guard !isSuspended else {
            return PumpSourceResult(success: false, command: .deliverBolus(units: units), message: "Pump is suspended")
        }
        
        guard let reservoir = currentStatus.reservoirLevel, reservoir >= units else {
            return PumpSourceResult(success: false, command: .deliverBolus(units: units), message: "Insufficient reservoir")
        }
        
        // Log protocol bytes
        let unitsBytes = UInt16(units * 40)  // 0.025U steps
        protocolLogger.tx(Data([0x4E, UInt8(unitsBytes >> 8), UInt8(unitsBytes & 0xFF)]), context: "Bolus \(units)U")
        
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms command
        protocolLogger.rx(Data([0x06, 0x4E, 0x00]), context: "ACK")
        
        // Simulate bolus delivery (1U = 10 seconds)
        bolusInProgress = BolusInfo(units: units, startTime: Date())
        
        let deliveryTime = UInt64(units * 10_000_000_000)  // 10s per unit
        try await Task.sleep(nanoseconds: min(deliveryTime, 2_000_000_000))  // Cap at 2s for simulation
        
        bolusInProgress = nil
        
        // Update reservoir and IOB
        let newReservoir = (currentStatus.reservoirLevel ?? 0) - units
        let newIOB = currentStatus.insulinOnBoard + units
        
        currentStatus = PumpStatus(
            connectionState: currentStatus.connectionState,
            reservoirLevel: newReservoir,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: newIOB,
            lastDelivery: Date()
        )
        
        return PumpSourceResult(
            success: true,
            command: .deliverBolus(units: units),
            message: "Delivered \(units)U bolus",
            updatedStatus: currentStatus
        )
    }
    
    private func suspend() async throws -> PumpSourceResult {
        protocolLogger.tx(Data([0x4F, 0x01]), context: "Suspend")
        try await Task.sleep(nanoseconds: 100_000_000)
        protocolLogger.rx(Data([0x06, 0x4F, 0x00]), context: "ACK")
        
        isSuspended = true
        currentTempBasal = nil
        
        currentStatus = PumpStatus(
            connectionState: .suspended,
            reservoirLevel: currentStatus.reservoirLevel,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
        
        return PumpSourceResult(
            success: true,
            command: .suspend,
            message: "Pump suspended",
            updatedStatus: currentStatus
        )
    }
    
    private func resume() async throws -> PumpSourceResult {
        protocolLogger.tx(Data([0x50, 0x01]), context: "Resume")
        try await Task.sleep(nanoseconds: 100_000_000)
        protocolLogger.rx(Data([0x06, 0x50, 0x00]), context: "ACK")
        
        isSuspended = false
        
        currentStatus = PumpStatus(
            connectionState: .connected,
            reservoirLevel: currentStatus.reservoirLevel,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
        
        return PumpSourceResult(
            success: true,
            command: .resume,
            message: "Pump resumed",
            updatedStatus: currentStatus
        )
    }
    
    // MARK: - Pattern Updates
    
    private func startPatternUpdates() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                await self.applyPatternUpdate()
                
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // Every 60s
            }
        }
    }
    
    private func applyPatternUpdate() {
        guard isRunning else { return }
        
        switch config.pattern {
        case .normal:
            // Slight IOB decay
            let newIOB = max(0, currentStatus.insulinOnBoard - 0.1)
            updateStatus(iob: newIOB)
            
        case .lowReservoir:
            // Decrease reservoir
            let newReservoir = max(0, (currentStatus.reservoirLevel ?? 0) - 2)
            updateStatus(reservoir: newReservoir)
            
        case .lowBattery:
            // Decrease battery
            let newBattery = max(0, (currentStatus.batteryLevel ?? 1.0) - 0.05)
            updateStatus(battery: newBattery)
            
        case .frequentTempBasal:
            // Random temp basal changes
            let rate = Double.random(in: 0.0...3.0)
            currentTempBasal = TempBasalInfo(rate: rate, startTime: Date(), durationMinutes: 30)
            
        case .suspended:
            isSuspended = true
            updateStatus(connectionState: .suspended)
            
        case .error:
            // Random errors
            if Bool.random() {
                updateStatus(connectionState: .error)
            } else {
                updateStatus(connectionState: .connected)
            }
        }
    }
    
    private func updateStatus(
        connectionState: PumpConnectionState? = nil,
        reservoir: Double? = nil,
        battery: Double? = nil,
        iob: Double? = nil
    ) {
        currentStatus = PumpStatus(
            connectionState: connectionState ?? currentStatus.connectionState,
            reservoirLevel: reservoir ?? currentStatus.reservoirLevel,
            batteryLevel: battery ?? currentStatus.batteryLevel,
            insulinOnBoard: iob ?? currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
    }
}

// MARK: - Supporting Types

struct TempBasalInfo {
    let rate: Double
    let startTime: Date
    let durationMinutes: Double
    
    var endTime: Date {
        startTime.addingTimeInterval(durationMinutes * 60)
    }
    
    var isActive: Bool {
        Date() < endTime
    }
}

struct BolusInfo {
    let units: Double
    let startTime: Date
}
