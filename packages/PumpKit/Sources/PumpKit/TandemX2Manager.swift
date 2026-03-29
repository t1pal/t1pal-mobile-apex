// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemX2Manager.swift
// PumpKit
//
// Tandem t:slim X2 pump manager implementing PumpManagerProtocol.
// Wraps TandemBLEManager for BLE communication with J-PAKE authentication.
//
// Trace: TANDEM-IMPL-004, PRD-005, REQ-AID-001
//
// Usage:
//   let manager = TandemX2Manager()
//   manager.pairingCode = "123456"  // 6-digit code from pump
//   try await manager.connect()
//   try await manager.deliverBolus(units: 1.5)

import Foundation
import NightscoutKit

// MARK: - Tandem X2 Manager

/// Tandem t:slim X2 pump manager implementing PumpManagerProtocol
/// Provides high-level pump control wrapping TandemBLEManager
/// Trace: TANDEM-IMPL-004, REQ-AID-001
public actor TandemX2Manager: PumpManagerProtocol {
    public nonisolated let displayName = "Tandem t:slim X2"
    public nonisolated let pumpType = PumpType.tandemX2
    
    // MARK: - Properties
    
    private let bleManager: TandemBLEManager
    
    /// Pairing code for J-PAKE authentication (6 numeric digits)
    /// Must be set before calling connect() for hardware authentication
    public var pairingCode: String? {
        get async { await bleManager.pairingCode }
    }
    
    /// Set pairing code for authentication
    public func setPairingCode(_ code: String?) async {
        await bleManager.setPairingCode(code)
    }
    
    // Configuration
    private let maxBolus: Double
    private let maxBasalRate: Double
    
    // Status
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
    
    // WIRE-014: Simulation mode for test acceleration
    private var simulationMode: SimulationMode = .demo
    
    // MARK: - Initialization
    
    public init(
        maxBolus: Double = 25.0,
        maxBasalRate: Double = 5.0
    ) {
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.bleManager = TandemBLEManager()
        self._status = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0,
            lastDelivery: nil
        )
    }
    
    /// Initialize with custom BLE manager (for testing)
    public init(
        bleManager: TandemBLEManager,
        maxBolus: Double = 25.0,
        maxBasalRate: Double = 5.0
    ) {
        self.bleManager = bleManager
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self._status = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0,
            lastDelivery: nil
        )
    }
    
    // MARK: - Simulation Mode (WIRE-014)
    
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
        
        PumpLogger.connection.info("TandemX2Manager: Starting connection")
        
        // Start scanning
        await bleManager.startScanning()
        
        // Wait for discovery with timeout
        var attempts = 0
        while attempts < 10 {
            try await simulationDelay(nanoseconds: 200_000_000)
            let diagnostics = await bleManager.diagnosticInfo()
            if diagnostics.discoveredCount > 0 {
                break
            }
            attempts += 1
        }
        
        // Get discovered pumps
        let discovered = await bleManager.discoveredPumps
        guard let pump = discovered.first else {
            updateStatus(connectionState: .disconnected)
            onError?(.connectionFailed)
            throw TandemBLEError.pumpNotFound
        }
        
        // Connect and authenticate
        do {
            try await bleManager.connect(to: pump)
            
            // Read initial status
            try await refreshStatus()
            
            updateStatus(connectionState: .connected)
            PumpLogger.connection.info("TandemX2Manager: Connected to \(pump.displayName)")
            
        } catch {
            updateStatus(connectionState: .disconnected)
            onError?(.connectionFailed)
            throw error
        }
    }
    
    public func disconnect() async {
        PumpLogger.connection.info("TandemX2Manager: Disconnecting")
        
        await bleManager.disconnect()
        
        updateStatus(connectionState: .disconnected)
        activeBolusDelivery = nil
    }
    
    // MARK: - Status
    
    private func refreshStatus() async throws {
        // Query basal status
        _ = try await bleManager.sendUnsignedCommand(opcode: .currentBasalStatusRequest)
        
        // Query IOB
        let iobResponse = try await bleManager.sendUnsignedCommand(opcode: .iobRequest)
        let iobData = iobResponse.cargo
        if iobData.count >= 4 {
            // Parse IOB from response (format: 4-byte float, little-endian)
            let iobValue = iobData.withUnsafeBytes { $0.load(as: Float32.self) }
            cachedIOB = Double(iobValue)
        }
        
        // Update status with simulated values (real values come from pump responses)
        _status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: 200.0,  // Simulated
            batteryLevel: 0.85,     // Simulated
            insulinOnBoard: cachedIOB,
            lastDelivery: _status.lastDelivery
        )
        
        onStatusChanged?(_status)
    }
    
    // MARK: - Temp Basal
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard rate >= 0 && rate <= maxBasalRate else {
            throw PumpError.exceedsMaxBasal
        }
        
        guard duration > 0 && duration <= 72 * 3600 else {
            throw PumpError.exceedsMaxBasal
        }
        
        PumpLogger.delivery.info("TandemX2Manager: Setting temp basal \(rate) U/hr for \(duration/60) min")
        
        // Build cargo: rate (2 bytes, 0.01 U/hr resolution) + duration (2 bytes, minutes)
        let rateValue = UInt16(rate * 100)
        let durationMinutes = UInt16(duration / 60)
        var cargo = Data()
        cargo.append(contentsOf: withUnsafeBytes(of: rateValue.littleEndian) { Array($0) })
        cargo.append(contentsOf: withUnsafeBytes(of: durationMinutes.littleEndian) { Array($0) })
        
        // Send signed command
        _ = try await bleManager.sendSignedCommand(opcode: .setTempRateRequest, cargo: cargo)
        
        PumpLogger.delivery.info("TandemX2Manager: Temp basal set successfully")
    }
    
    public func cancelTempBasal() async throws {
        PumpLogger.delivery.info("TandemX2Manager: Cancelling temp basal")
        
        _ = try await bleManager.sendSignedCommand(opcode: .stopTempRateRequest)
        
        PumpLogger.delivery.info("TandemX2Manager: Temp basal cancelled")
    }
    
    // MARK: - Bolus
    
    public func deliverBolus(units: Double) async throws {
        guard units > 0 && units <= maxBolus else {
            throw PumpError.exceedsMaxBolus
        }
        
        PumpLogger.bolus.info("TandemX2Manager: Initiating bolus \(units) U")
        
        // Start bolus progress tracking (BOLUS-003)
        let bolusId = UUID()
        var delivery = ActiveBolusDelivery(id: bolusId, requestedUnits: units)
        delivery.state = .delivering(requested: units, delivered: 0, remaining: units)
        activeBolusDelivery = delivery
        bolusProgressDelegate?.bolusDidStart(id: bolusId, requested: units)
        
        // Build cargo: amount (4 bytes, 0.001 U resolution)
        let amountValue = UInt32(units * 1000)
        var cargo = Data()
        cargo.append(contentsOf: withUnsafeBytes(of: amountValue.littleEndian) { Array($0) })
        
        do {
            // Send signed command
            _ = try await bleManager.sendSignedCommand(opcode: .initiateBolusRequest, cargo: cargo)
            
            // Simulate delivery time
            let deliveryTime = units * 10.0  // ~10 seconds per unit
            try await simulationDelay(nanoseconds: UInt64(deliveryTime * 1_000_000_000))
            
            // Update delivery tracking
            var completedDelivery = ActiveBolusDelivery(id: bolusId, requestedUnits: units)
            completedDelivery.state = .completed(total: units, timestamp: Date())
            activeBolusDelivery = completedDelivery
            
            // Track for IOB
            await iobTracker.recordBolus(units: units)
            cachedIOB = await iobTracker.currentIOB()
            
            // Update status
            _status = PumpStatus(
                connectionState: _status.connectionState,
                reservoirLevel: (_status.reservoirLevel ?? 0) - units,
                batteryLevel: _status.batteryLevel,
                insulinOnBoard: cachedIOB,
                lastDelivery: Date()
            )
            onStatusChanged?(_status)
            
            // Notify delegate
            bolusProgressDelegate?.bolusDidComplete(id: bolusId, delivered: units)
            
            // Report to Nightscout (BOLUS-008)
            if let reporter = deliveryReporter {
                let event = DeliveryEvent(
                    deliveryType: .bolus,
                    units: units,
                    reason: "Bolus delivery"
                )
                await reporter.queue(event)
            }
            
            PumpLogger.bolus.info("TandemX2Manager: Bolus complete \(units) U")
            
        } catch {
            // Handle delivery failure
            var failedDelivery = ActiveBolusDelivery(id: bolusId, requestedUnits: units)
            failedDelivery.state = .failed(delivered: 0, error: .deliveryFailed)
            activeBolusDelivery = failedDelivery
            bolusProgressDelegate?.bolusDidFail(id: bolusId, delivered: 0, error: .deliveryFailed)
            throw error
        }
        
        activeBolusDelivery = nil
    }
    
    public func cancelBolus() async throws {
        guard let delivery = activeBolusDelivery else {
            PumpLogger.bolus.warning("TandemX2Manager: No active bolus to cancel")
            return
        }
        
        PumpLogger.bolus.info("TandemX2Manager: Cancelling bolus \(delivery.id)")
        
        _ = try await bleManager.sendSignedCommand(opcode: .cancelBolusRequest)
        
        // Update delivery state
        let deliveredSoFar = delivery.state.deliveredUnits
        var cancelledDelivery = ActiveBolusDelivery(id: delivery.id, startTime: delivery.startTime, requestedUnits: delivery.requestedUnits)
        cancelledDelivery.state = .cancelled(delivered: deliveredSoFar, reason: .userRequested)
        activeBolusDelivery = cancelledDelivery
        
        bolusProgressDelegate?.bolusWasCancelled(id: delivery.id, delivered: deliveredSoFar, reason: .userRequested)
        activeBolusDelivery = nil
        
        PumpLogger.bolus.info("TandemX2Manager: Bolus cancelled")
    }
    
    // MARK: - Suspend/Resume
    
    public func suspend() async throws {
        PumpLogger.delivery.info("TandemX2Manager: Suspending pump")
        
        // Tandem uses the stopTempRate with special flag for suspend
        // In real implementation, this would be a specific suspend command
        _ = try await bleManager.sendSignedCommand(opcode: .stopTempRateRequest)
        
        updateStatus(connectionState: .connected)  // Still connected but suspended
        
        PumpLogger.delivery.info("TandemX2Manager: Pump suspended")
    }
    
    public func resume() async throws {
        PumpLogger.delivery.info("TandemX2Manager: Resuming pump")
        
        // In real implementation, this would be a specific resume command
        _ = try await bleManager.sendSignedCommand(opcode: .setTempRateRequest)
        
        updateStatus(connectionState: .connected)
        
        PumpLogger.delivery.info("TandemX2Manager: Pump resumed")
    }
    
    // MARK: - Helpers
    
    private func updateStatus(connectionState: PumpConnectionState) {
        _status = PumpStatus(
            connectionState: connectionState,
            reservoirLevel: _status.reservoirLevel,
            batteryLevel: _status.batteryLevel,
            insulinOnBoard: cachedIOB,
            lastDelivery: _status.lastDelivery
        )
        onStatusChanged?(_status)
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information for debugging
    public func diagnosticInfo() async -> TandemDiagnostics {
        await bleManager.diagnosticInfo()
    }
}

// MARK: - TandemBLEManager Extension for setPairingCode

extension TandemBLEManager {
    /// Set pairing code for J-PAKE authentication
    public func setPairingCode(_ code: String?) {
        pairingCode = code
    }
}
