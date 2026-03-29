// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaManager.swift
// PumpKit
//
// Dana pump manager implementing PumpManagerProtocol
// Wraps DanaBLEManager for BLE communication
// Trace: DANA-IMPL-004, PRD-005, REQ-AID-001

import Foundation
import NightscoutKit

// MARK: - Dana Manager

/// Dana pump manager implementing PumpManagerProtocol
/// Provides high-level pump control wrapping DanaBLEManager
/// Trace: DANA-IMPL-004, REQ-AID-001
public actor DanaManager: PumpManagerProtocol {
    public nonisolated let displayName = "Dana Pump"
    public nonisolated let pumpType = PumpType.danaRS
    
    // MARK: - Properties
    
    private let bleManager: DanaBLEManager
    private let basalRate: Double
    private let maxBolus: Double
    private let maxBasalRate: Double
    
    /// Session logger for verbose protocol debugging (PROTO-DANA-DIAG)
    public var sessionLogger: DanaSessionLogger?
    
    private var _status: PumpStatus
    public var status: PumpStatus { _status }
    
    public var onStatusChanged: (@Sendable (PumpStatus) -> Void)?
    public var onError: (@Sendable (PumpError) -> Void)?
    
    // BOLUS-003: Bolus progress tracking
    public private(set) var activeBolusDelivery: ActiveBolusDelivery?
    public var bolusProgressDelegate: (any BolusProgressDelegate)?
    
    // BOLUS-008: Nightscout sync
    public var deliveryReporter: DeliveryReporter?
    
    // BOLUS-004: Delivery tracker for IOB calculation
    private let iobTracker = IOBTracker()
    
    /// Cached IOB value (updated after each delivery)
    private var cachedIOB: Double = 0
    
    // MARK: - Initialization
    
    public init(
        basalRate: Double = 1.0,
        maxBolus: Double = 25.0,
        maxBasalRate: Double = 5.0
    ) {
        self.basalRate = basalRate
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.bleManager = DanaBLEManager()
        self._status = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0,
            lastDelivery: nil
        )
    }
    
    // WIRE-014: Simulation mode for test acceleration
    private var simulationMode: SimulationMode = .demo
    
    public func setSimulationMode(_ mode: SimulationMode) {
        simulationMode = mode
    }
    
    public func enableTestMode() {
        setSimulationMode(.test)
    }
    
    private func simulationDelay(nanoseconds: UInt64) async throws {
        try await simulationMode.delay(nanoseconds: nanoseconds)
    }
    
    // MARK: - Connection
    
    public func connect() async throws {
        updateStatus(connectionState: .connecting)
        sessionLogger?.transitionTo(.scanning, reason: "connect() called")
        
        // Start scanning and wait for discovery
        await bleManager.startScanning()
        
        // Wait for discovery with timeout (WIRE-014: use simulationDelay)
        var attempts = 0
        while attempts < 10 {
            try await simulationDelay(nanoseconds: 200_000_000)
            let diagnostics = await bleManager.diagnosticInfo()
            if diagnostics.discoveredCount > 0 {
                break
            }
            attempts += 1
        }
        
        let discoveredPumps = await bleManager.discoveredPumps
        guard let pump = discoveredPumps.first else {
            await bleManager.stopScanning()
            sessionLogger?.transitionTo(.error, reason: "No pumps discovered")
            updateStatus(connectionState: .error)
            onError?(.connectionFailed)
            throw PumpError.connectionFailed
        }
        
        do {
            sessionLogger?.transitionTo(.connecting, reason: "Pump discovered")
            try await bleManager.connect(to: pump)
            
            sessionLogger?.transitionTo(.readingStatus, reason: "Connected, reading status")
            // Read initial status
            let danaStatus = try await bleManager.readStatus()
            updateStatus(
                connectionState: .connected,
                reservoirLevel: danaStatus.reservoirLevel,
                batteryLevel: Double(danaStatus.batteryPercent) / 100.0,
                isSuspended: danaStatus.isSuspended
            )
            
            sessionLogger?.transitionTo(.sessionEstablished, reason: "Status read complete")
            PumpLogger.connection.info("Dana pump connected successfully")
        } catch {
            sessionLogger?.transitionTo(.error, reason: error.localizedDescription)
            updateStatus(connectionState: .error)
            onError?(.connectionFailed)
            throw PumpError.connectionFailed
        }
    }
    
    public func disconnect() async {
        sessionLogger?.transitionTo(.disconnecting, reason: "disconnect() called")
        await bleManager.disconnect()
        sessionLogger?.transitionTo(.idle, reason: "Disconnected")
        updateStatus(connectionState: .disconnected)
        PumpLogger.connection.info("Dana pump disconnected")
    }
    
    // MARK: - Insulin Delivery
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard _status.connectionState == .connected else {
            throw PumpError.notConnected
        }
        
        guard rate <= maxBasalRate else {
            throw PumpError.exceedsMaxBasal
        }
        
        sessionLogger?.transitionTo(.commandPending, reason: "setTempBasal")
        
        // Dana temp basal command: 0x02 + rate (0.01 U/hr units) + duration (minutes)
        let rateValue = UInt16(rate * 100)
        let durationMinutes = UInt8(min(duration / 60, 480)) // Max 8 hours
        
        var command = Data([0x02])
        command.append(contentsOf: withUnsafeBytes(of: rateValue.littleEndian) { Array($0) })
        command.append(durationMinutes)
        
        sessionLogger?.logCommandSent(opcode: 0x02, description: "SET_TEMP_BASAL", data: command)
        let response = try await bleManager.sendCommand(command, type: .basal)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x02, success: false, data: response)
            sessionLogger?.transitionTo(.error, reason: "Temp basal command failed")
            onError?(.deliveryFailed)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x02, success: true, data: response)
        sessionLogger?.logTempBasal(rate: rate, duration: duration, isSet: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "setTempBasal success")
        
        PumpLogger.delivery.info("Dana temp basal set: \(rate) U/hr for \(Int(duration/60)) min")
    }
    
    public func cancelTempBasal() async throws {
        guard _status.connectionState == .connected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.commandPending, reason: "cancelTempBasal")
        
        // Dana cancel temp basal: 0x03
        let command = Data([0x03])
        sessionLogger?.logCommandSent(opcode: 0x03, description: "CANCEL_TEMP_BASAL", data: command)
        let response = try await bleManager.sendCommand(command, type: .basal)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x03, success: false, data: response)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x03, success: true, data: response)
        sessionLogger?.logTempBasal(rate: 0, duration: 0, isSet: false)
        sessionLogger?.transitionTo(.commandComplete, reason: "cancelTempBasal success")
        
        PumpLogger.delivery.info("Dana temp basal cancelled")
    }
    
    public func deliverBolus(units: Double) async throws {
        guard _status.connectionState == .connected else {
            throw PumpError.notConnected
        }
        
        guard units <= maxBolus else {
            throw PumpError.exceedsMaxBolus
        }
        
        guard let reservoir = _status.reservoirLevel, reservoir >= units else {
            throw PumpError.insufficientReservoir
        }
        
        // BOLUS-004: Create active bolus delivery tracking
        let delivery = ActiveBolusDelivery(requestedUnits: units)
        activeBolusDelivery = delivery
        
        // Notify delegate: initiating
        bolusProgressDelegate?.bolusDidStart(id: delivery.id, requested: units)
        
        sessionLogger?.transitionTo(.bolusing, reason: "deliverBolus \(units)U")
        
        // Update state to delivering
        activeBolusDelivery?.state = .delivering(requested: units, delivered: 0, remaining: units)
        bolusProgressDelegate?.bolusDidProgress(id: delivery.id, delivered: 0, remaining: units, percentComplete: 0.0)
        
        // Dana bolus command: 0x04 + units (0.01 U units)
        let bolusValue = UInt16(units * 100)
        var command = Data([0x04])
        command.append(contentsOf: withUnsafeBytes(of: bolusValue.littleEndian) { Array($0) })
        
        sessionLogger?.logCommandSent(opcode: 0x04, description: "DELIVER_BOLUS", data: command)
        let response = try await bleManager.sendCommand(command, type: .bolus)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x04, success: false, data: response)
            sessionLogger?.transitionTo(.error, reason: "Bolus command failed")
            
            // BOLUS-011: Update state and notify delegate of failure
            activeBolusDelivery?.state = .failed(delivered: 0, error: .deliveryFailed)
            bolusProgressDelegate?.bolusDidFail(id: delivery.id, delivered: 0, error: .deliveryFailed)
            activeBolusDelivery = nil
            
            onError?(.deliveryFailed)
            PumpLogger.bolus.bolusFailed(error: .deliveryFailed)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x04, success: true, data: response)
        sessionLogger?.logBolusDelivery(units: units, success: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "deliverBolus success")
        
        // Update state to completing
        activeBolusDelivery?.state = .completing(total: units)
        
        // BOLUS-004: Track delivery for IOB calculation
        await iobTracker.recordBolus(units: units)
        cachedIOB = await iobTracker.currentIOB()
        
        // Update state to completed and notify delegate
        activeBolusDelivery?.state = .completed(total: units, timestamp: Date())
        bolusProgressDelegate?.bolusDidComplete(id: delivery.id, delivered: units)
        
        // BOLUS-008: Queue for Nightscout sync
        if let reporter = deliveryReporter {
            let event = DeliveryEvent(
                deliveryType: .bolus,
                units: units,
                reason: "Bolus delivery"
            )
            await reporter.queue(event)
        }
        
        // Clear active delivery
        activeBolusDelivery = nil
        
        updateStatus(insulinOnBoard: cachedIOB, lastDelivery: Date())
        PumpLogger.delivery.info("Dana bolus delivered: \(units) U")
    }
    
    // RESEARCH-AID-005: Cancel in-progress bolus delivery
    // BOLUS-004: Added progress tracking and IOB recording for partial delivery
    public func cancelBolus() async throws {
        guard _status.connectionState == .connected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.commandPending, reason: "cancelBolus")
        
        // BOLUS-004: Update active delivery to cancelled state and record partial delivery
        if let delivery = activeBolusDelivery {
            // Calculate how much was delivered based on elapsed time
            // Dana pumps deliver at ~0.025 U/sec (1.5 U/min standard rate)
            let deliveryRate = 0.025 // U/sec
            let elapsedTime = delivery.elapsedTime
            let deliveredUnits = min(delivery.requestedUnits, elapsedTime * deliveryRate)
            
            // Record partial delivery for IOB calculation
            if deliveredUnits > 0 {
                await iobTracker.recordBolus(units: deliveredUnits)
                cachedIOB = await iobTracker.currentIOB()
                
                // BOLUS-008: Queue partial delivery for Nightscout sync
                if let reporter = deliveryReporter {
                    let event = DeliveryEvent(
                        deliveryType: .bolus,
                        units: deliveredUnits,
                        reason: "Bolus cancelled (partial delivery)"
                    )
                    await reporter.queue(event)
                }
            }
            
            activeBolusDelivery?.state = .cancelled(delivered: deliveredUnits, reason: .userRequested)
            bolusProgressDelegate?.bolusWasCancelled(id: delivery.id, delivered: deliveredUnits, reason: .userRequested)
            activeBolusDelivery = nil
        }
        
        // Dana cancel bolus command: 0x07
        let command = Data([0x07])
        sessionLogger?.logCommandSent(opcode: 0x07, description: "CANCEL_BOLUS", data: command)
        let response = try await bleManager.sendCommand(command, type: .bolus)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x07, success: false, data: response)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x07, success: true, data: response)
        sessionLogger?.transitionTo(.commandComplete, reason: "cancelBolus success")
        
        PumpLogger.bolus.bolusCancelled()
    }
    
    public func suspend() async throws {
        guard _status.connectionState == .connected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.commandPending, reason: "suspend")
        
        // Dana suspend command: 0x05
        let command = Data([0x05])
        sessionLogger?.logCommandSent(opcode: 0x05, description: "SUSPEND", data: command)
        let response = try await bleManager.sendCommand(command, type: .basal)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x05, success: false, data: response)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x05, success: true, data: response)
        sessionLogger?.transitionTo(.commandComplete, reason: "suspend success")
        
        updateStatus(connectionState: .suspended)
        PumpLogger.delivery.info("Dana pump suspended")
    }
    
    public func resume() async throws {
        guard _status.connectionState == .suspended else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.commandPending, reason: "resume")
        
        // Dana resume command: 0x06
        let command = Data([0x06])
        sessionLogger?.logCommandSent(opcode: 0x06, description: "RESUME", data: command)
        let response = try await bleManager.sendCommand(command, type: .basal)
        
        guard response.first == 0x01 else {
            sessionLogger?.logCommandResponse(opcode: 0x06, success: false, data: response)
            throw PumpError.deliveryFailed
        }
        
        sessionLogger?.logCommandResponse(opcode: 0x06, success: true, data: response)
        sessionLogger?.transitionTo(.sessionEstablished, reason: "resume success")
        
        updateStatus(connectionState: .connected)
        PumpLogger.delivery.info("Dana pump resumed")
    }
    
    // MARK: - Status Updates
    
    private func updateStatus(
        connectionState: PumpConnectionState? = nil,
        reservoirLevel: Double? = nil,
        batteryLevel: Double? = nil,
        insulinOnBoard: Double? = nil,
        lastDelivery: Date? = nil,
        isSuspended: Bool = false
    ) {
        let newState = connectionState ?? (isSuspended ? .suspended : _status.connectionState)
        _status = PumpStatus(
            connectionState: newState,
            reservoirLevel: reservoirLevel ?? _status.reservoirLevel,
            batteryLevel: batteryLevel ?? _status.batteryLevel,
            insulinOnBoard: insulinOnBoard ?? _status.insulinOnBoard,
            lastDelivery: lastDelivery ?? _status.lastDelivery
        )
        onStatusChanged?(_status)
    }
    
    // MARK: - Diagnostics
    
    /// Get underlying BLE manager for diagnostics
    public var diagnostics: DanaBLEManager {
        bleManager
    }
}
