// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MinimedManager.swift
// PumpKit
//
// Medtronic/Minimed pump manager implementation
// Trace: PUMP-010, PRD-005, REQ-AID-001, LOG-ADOPT-005
//
// This provides the PumpManagerProtocol implementation for Medtronic pumps.
// Uses simulation for testing, can be extended with real MinimedKit integration.
// Note: Requires RileyLink hardware for actual RF communication.

import Foundation
import NightscoutKit
import T1PalCore

// MARK: - Pump Models

/// Supported Medtronic pump models
/// Bug fix: EXT-MDT-005 - Added missing models from externals/MinimedKit/MinimedKit/Models/PumpModel.swift
/// Also fixed: 530G/730G -> 530/730 to match Loop convention
public enum MinimedPumpModel: String, Sendable, Codable, CaseIterable {
    // Pre-523 models (scale=10, generation < 23)
    case model508 = "508"
    case model511 = "511"
    case model711 = "711"  // EXT-MDT-005: Added missing 7xx variant
    case model512 = "512"
    case model712 = "712"  // EXT-MDT-005: Added missing 7xx variant
    case model515 = "515"
    case model715 = "715"  // EXT-MDT-005: Added missing 7xx variant
    case model522 = "522"
    case model722 = "722"
    
    // 523+ models (scale=40, generation >= 23)
    case model523 = "523"
    case model723 = "723"
    case model530 = "530"  // EXT-MDT-005: Changed from "530G" to match Loop
    case model730 = "730"  // EXT-MDT-005: Changed from "730G" to match Loop
    case model540 = "540"  // EXT-MDT-005: Added missing model
    case model740 = "740"  // EXT-MDT-005: Added missing model
    case model551 = "551"  // EXT-MDT-005: Added missing model (has low suspend)
    case model751 = "751"  // EXT-MDT-005: Added missing model (has low suspend)
    case model554 = "554"
    case model754 = "754"
    
    /// Generation number (last two digits of model number)
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:38
    private var generation: Int {
        Int(rawValue)! % 100
    }
    
    /// Size category (first digit: 5=small, 7=large)
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:34
    private var size: Int {
        Int(rawValue)! / 100
    }
    
    public var displayName: String {
        switch self {
        case .model508: return "Paradigm 508"
        case .model511: return "Paradigm 511"
        case .model711: return "Paradigm 711"
        case .model512: return "Paradigm 512"
        case .model712: return "Paradigm 712"
        case .model515: return "Paradigm 515"
        case .model715: return "Paradigm 715"
        case .model522: return "Paradigm 522"
        case .model722: return "Paradigm 722"
        case .model523: return "Paradigm Revel 523"
        case .model723: return "Paradigm Revel 723"
        case .model530: return "MiniMed 530G"
        case .model730: return "MiniMed 730G"
        case .model540: return "MiniMed 540G"
        case .model740: return "MiniMed 740G"
        case .model551: return "MiniMed 551"
        case .model751: return "MiniMed 751"
        case .model554: return "MiniMed 554"
        case .model754: return "MiniMed 754"
        }
    }
    
    /// Reservoir capacity in units
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:75-84
    public var reservoirCapacity: Double {
        switch size {
        case 5: return 176
        case 7: return 300
        default: return 176  // Fallback
        }
    }
    
    /// Whether this model supports MySentry CGM (generation >= 23)
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:54
    public var supportsMySentry: Bool {
        generation >= 23
    }
    
    /// Whether this model has low suspend feature (generation >= 51)
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:58
    public var hasLowSuspend: Bool {
        generation >= 51
    }
    
    /// Whether this is a pre-523 model (generation < 23)
    /// Uses generation-based logic to match Loop exactly
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:43
    public var isPre523: Bool {
        generation < 23
    }
    
    /// Insulin bit packing scale for reservoir parsing
    /// Reference: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:66-68
    public var insulinBitPackingScale: Int {
        generation >= 23 ? 40 : 10
    }
    
    /// Pulses per unit (inverse of minimum delivery volume)
    /// Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:71-73
    public var pulsesPerUnit: Int {
        generation >= 23 ? 40 : 20
    }
}

/// Pump region for RF frequency
public enum MinimedPumpRegion: String, Sendable, Codable {
    case northAmerica = "NA"    // 916.5 MHz
    case worldWide = "WW"        // 868.35 MHz
    case canada = "CA"           // 916.5 MHz
    
    public var rfFrequency: Double {
        switch self {
        case .northAmerica, .canada:
            return 916.5  // MHz
        case .worldWide:
            return 868.35  // MHz
        }
    }
}

// MARK: - Pump State

/// Medtronic pump state
public struct MinimedPumpState: Sendable, Codable {
    public let pumpId: String
    public let model: MinimedPumpModel
    public let region: MinimedPumpRegion
    public var deliveryState: MinimedDeliveryState
    public var reservoirLevel: Double
    public var batteryLevel: Double  // 0-1
    public var lastTempBasal: MinimedTempBasalState?
    public var bolusInProgress: MinimedBolusState?
    public var suspendedSince: Date?
    public var alerts: [MinimedPumpAlert]
    
    public var isSuspended: Bool {
        deliveryState == .suspended
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 20
    }
    
    public var isLowBattery: Bool {
        batteryLevel < 0.20
    }
    
    public init(
        pumpId: String,
        model: MinimedPumpModel,
        region: MinimedPumpRegion = .northAmerica,
        deliveryState: MinimedDeliveryState = .normal,
        reservoirLevel: Double = 200,
        batteryLevel: Double = 1.0,
        lastTempBasal: MinimedTempBasalState? = nil,
        bolusInProgress: MinimedBolusState? = nil,
        suspendedSince: Date? = nil,
        alerts: [MinimedPumpAlert] = []
    ) {
        self.pumpId = pumpId
        self.model = model
        self.region = region
        self.deliveryState = deliveryState
        self.reservoirLevel = reservoirLevel
        self.batteryLevel = batteryLevel
        self.lastTempBasal = lastTempBasal
        self.bolusInProgress = bolusInProgress
        self.suspendedSince = suspendedSince
        self.alerts = alerts
    }
}

/// Medtronic delivery state
public enum MinimedDeliveryState: String, Sendable, Codable {
    case normal           // Scheduled basal running
    case tempBasal        // Temp basal active
    case suspended        // All delivery suspended
    case bolusing         // Bolus in progress
    case priming          // Priming/filling tubing
}

/// Medtronic temp basal state
public struct MinimedTempBasalState: Sendable, Codable {
    public let rate: Double
    public let startTime: Date
    public let duration: TimeInterval
    
    public var isActive: Bool {
        Date() < startTime.addingTimeInterval(duration)
    }
    
    public var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    public init(rate: Double, startTime: Date = Date(), duration: TimeInterval) {
        self.rate = rate
        self.startTime = startTime
        self.duration = duration
    }
}

/// Medtronic bolus state
public struct MinimedBolusState: Sendable, Codable {
    public let requestedUnits: Double
    public let deliveredUnits: Double
    public let startTime: Date
    
    public var isComplete: Bool {
        deliveredUnits >= requestedUnits
    }
    
    public init(requestedUnits: Double, deliveredUnits: Double = 0, startTime: Date = Date()) {
        self.requestedUnits = requestedUnits
        self.deliveredUnits = deliveredUnits
        self.startTime = startTime
    }
}

/// Medtronic pump alerts
public enum MinimedPumpAlert: String, Sendable, Codable {
    case lowReservoir
    case lowBattery
    case noDelivery
    case autoOff
    case buttonError
    case maxBasalExceeded
    case maxBolusExceeded
}

// MARK: - RileyLink State

/// RileyLink connection state
public enum RileyLinkState: String, Sendable, Codable {
    case disconnected
    case connecting
    case connected
    case scanning
    case error
}

// MARK: - Minimed Manager

/// Medtronic/Minimed pump manager
/// Implements PumpManagerProtocol for Medtronic insulin pumps
/// Trace: PUMP-010, REQ-AID-001
///
/// Note: Actual RF communication requires RileyLink hardware.
/// This implementation uses simulation for testing.
public actor MinimedManager: PumpManagerProtocol, PumpProfileSyncable {
    public nonisolated let displayName = "Medtronic Pump"
    public nonisolated let pumpType = PumpType.medtronic
    
    public private(set) var status: PumpStatus
    
    public var onStatusChanged: (@Sendable (PumpStatus) -> Void)?
    public var onError: (@Sendable (PumpError) -> Void)?
    
    // BOLUS-003: Bolus progress tracking
    public private(set) var activeBolusDelivery: ActiveBolusDelivery?
    public var bolusProgressDelegate: (any BolusProgressDelegate)?
    
    // BOLUS-008: Nightscout sync
    public var deliveryReporter: DeliveryReporter?
    
    // Pump state
    private var pumpState: MinimedPumpState?
    private var rileyLinkState: RileyLinkState = .disconnected
    
    /// RileyLink session for RF communication (MDT-HIST-032)
    /// Set this to enable actual hardware communication
    public var rileyLinkSession: RileyLinkSession?
    
    // Configuration
    private let basalRate: Double
    private let maxBolus: Double
    private let maxBasalRate: Double
    
    /// Audit log for command recording
    public let auditLog: PumpAuditLog?
    
    // WIRE-006: Fault injection support
    public var faultInjector: PumpFaultInjector?
    
    // WIRE-006: Metrics support
    private let metrics: PumpMetrics
    
    /// Delivery tracker for IOB calculation
    private let iobTracker = IOBTracker()
    
    /// Cached IOB value (updated after each delivery)
    private var cachedIOB: Double = 0
    
    /// Reservoir and battery monitor (LIFE-PUMP-004/005)
    private var reservoirMonitor: ReservoirMonitor?
    
    /// Reservoir warning notification callback
    private var _onReservoirWarning: (@Sendable (ReservoirNotification) async -> Void)?
    
    /// Battery warning notification callback
    private var _onBatteryWarning: (@Sendable (PumpBatteryNotification) async -> Void)?
    
    /// Set reservoir warning callback
    public func setReservoirWarningHandler(_ handler: @escaping @Sendable (ReservoirNotification) async -> Void) {
        _onReservoirWarning = handler
    }
    
    /// Set battery warning callback
    public func setBatteryWarningHandler(_ handler: @escaping @Sendable (PumpBatteryNotification) async -> Void) {
        _onBatteryWarning = handler
    }
    
    // MARK: - Initialization
    
    public init(
        basalRate: Double = 1.0,
        maxBolus: Double = 25.0,
        maxBasalRate: Double = 10.0,
        auditLog: PumpAuditLog? = nil,
        faultInjector: PumpFaultInjector? = nil,
        metrics: PumpMetrics = .shared
    ) {
        self.basalRate = basalRate
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.auditLog = auditLog
        self.faultInjector = faultInjector
        self.metrics = metrics
        self.status = PumpStatus(connectionState: .disconnected)
        // LIFE-PUMP-009: Create reservoir monitor with UserDefaults persistence
        self.reservoirMonitor = ReservoirMonitor(persistence: UserDefaultsReservoirPersistence())
        PumpLogger.general.info("MinimedManager: initialized")
    }
    
    /// LIFE-PUMP-009: Restore lifecycle state from persistence
    /// Call this after init to restore any saved pump state
    public func restoreLifecycleState() async {
        await reservoirMonitor?.restoreState()
        if let status = await reservoirMonitor?.currentReservoirStatus() {
            PumpLogger.general.info("MinimedManager: restored pump state for \(status.pumpId)")
        }
    }
    
    // MARK: - Pump Pairing
    
    /// Pair with a Medtronic pump
    public func pairPump(pumpId: String, model: MinimedPumpModel, region: MinimedPumpRegion = .northAmerica) async throws {
        guard pumpState == nil else {
            throw PumpError.alreadyActivated
        }
        
        // Validate pump ID format (6 digits)
        guard pumpId.count == 6, pumpId.allSatisfy({ $0.isNumber }) else {
            throw MinimedError.invalidPumpId
        }
        
        // Create pump state
        pumpState = MinimedPumpState(
            pumpId: pumpId,
            model: model,
            region: region,
            reservoirLevel: model.reservoirCapacity
        )
        
        // Start reservoir monitoring (LIFE-PUMP-004/005, LIFE-PUMP-009)
        await reservoirMonitor?.startTracking(pumpId: pumpId, reservoirCapacity: model.reservoirCapacity)
        await reservoirMonitor?.updateReservoirLevel(model.reservoirCapacity)
        await reservoirMonitor?.updateBatteryLevel(1.0)
        
        updateStatus()
        await auditLog?.record(.pairPump(pumpId: pumpId, model: model.rawValue))
    }
    
    /// Unpair current pump
    public func unpairPump() async throws {
        guard let pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        // Clear reservoir monitoring (LIFE-PUMP-004/005, LIFE-PUMP-009)
        await reservoirMonitor?.stopTracking()
        
        await auditLog?.record(.unpairPump(pumpId: pump.pumpId))
        pumpState = nil
        rileyLinkState = .disconnected
        updateStatus()
    }
    
    /// Get current pump state
    public var currentPumpState: MinimedPumpState? {
        pumpState
    }
    
    /// Get RileyLink connection state
    public var currentRileyLinkState: RileyLinkState {
        rileyLinkState
    }
    
    // MARK: - Reservoir & Battery Monitoring (LIFE-PUMP-004/005)
    
    /// Get current reservoir status
    public func getReservoirStatus() async -> ReservoirStatus? {
        await reservoirMonitor?.currentReservoirStatus()
    }
    
    /// Get current battery status
    public func getBatteryStatus() async -> PumpBatteryStatus? {
        await reservoirMonitor?.currentBatteryStatus()
    }
    
    /// Check reservoir and battery levels, trigger notifications if needed
    public func checkConsumables() async {
        guard let monitor = reservoirMonitor else { return }
        
        // Check reservoir
        let reservoirResult = await monitor.checkReservoir()
        switch reservoirResult {
        case .warning(let notification):
            await monitor.markReservoirWarningSent(notification.warning)
            await _onReservoirWarning?(notification)
            PumpLogger.general.warning("Reservoir warning: \(notification.warning.message)")
        default:
            break
        }
        
        // Check battery
        let batteryResult = await monitor.checkBattery()
        switch batteryResult {
        case .warning(let notification):
            await monitor.markBatteryWarningSent(notification.warning)
            await _onBatteryWarning?(notification)
            PumpLogger.general.warning("Battery warning: \(notification.warning.message)")
        default:
            break
        }
    }
    
    /// Update reservoir level (call after reading from pump)
    public func updateReservoirLevel(_ level: Double) async {
        if var state = pumpState {
            state.reservoirLevel = level
            pumpState = state
        }
        await reservoirMonitor?.updateReservoirLevel(level)
        updateStatus()
    }
    
    /// Update battery level (call after reading from pump)
    public func updateBatteryLevel(_ level: Double) async {
        if var state = pumpState {
            state.batteryLevel = level
            pumpState = state
        }
        await reservoirMonitor?.updateBatteryLevel(level)
        updateStatus()
    }
    
    /// Notify that reservoir was changed (resets warnings)
    public func reservoirChanged() async {
        await reservoirMonitor?.reservoirChanged()
        PumpLogger.general.info("Reservoir changed - warnings reset")
    }
    
    /// Notify that battery was changed (resets warnings)
    public func batteryChanged() async {
        await reservoirMonitor?.batteryChanged()
        PumpLogger.general.info("Battery changed - warnings reset")
    }
    
    // MARK: - PumpManagerProtocol
    
    /// Connect to the pump via RileyLink
    /// Trace: WIRE-006 (fault injection + metrics)
    public func connect() async throws {
        let startTime = Date()
        
        // WIRE-006: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "connect")
            if case .injected(let fault) = result {
                await metrics.recordCommand("connect", duration: 0, success: false, pumpType: .medtronic)
                throw mapFaultToError(fault)
            }
        }
        
        guard pumpState != nil else {
            throw MinimedError.noPumpPaired
        }
        
        // Simulate RileyLink connection
        rileyLinkState = .connecting
        updateStatus()
        
        
        rileyLinkState = .connected
        updateStatus()
        await auditLog?.record(AuditCommand.connect)
        
        // WIRE-006: Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("connect", duration: duration, success: true, pumpType: .medtronic)
    }
    
    public func disconnect() async {
        rileyLinkState = .disconnected
        updateStatus()
        await auditLog?.record(AuditCommand.disconnect)
    }
    
    /// Set temporary basal rate
    /// Trace: WIRE-006 (fault injection + metrics)
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        let startTime = Date()
        
        // WIRE-006: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "minimed.tempBasal")
            if case .injected(let fault) = result {
                await metrics.recordCommand("minimed.tempBasal", duration: 0, success: false, pumpType: .medtronic)
                throw mapFaultToError(fault)
            }
        }
        
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        guard rate <= maxBasalRate else {
            throw PumpError.exceedsMaxBasal
        }
        
        guard rate >= 0 else {
            throw MinimedError.invalidRate
        }
        
        // Validate duration (Medtronic supports 30 min increments up to 24 hours)
        guard duration >= 30 * 60 && duration <= 24 * 3600 else {
            throw MinimedError.invalidDuration
        }
        
        
        pump.lastTempBasal = MinimedTempBasalState(rate: rate, duration: duration)
        pump.deliveryState = .tempBasal
        pumpState = pump
        
        updateStatus()
        await auditLog?.record(.setTempBasal(rate: rate, durationMinutes: duration / 60))
        PumpLogger.basal.tempBasalSet(rate: rate, duration: duration)
        
        // WIRE-006: Record metrics
        let commandDuration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("minimed.tempBasal", duration: commandDuration, success: true, pumpType: .medtronic)
    }
    
    public func cancelTempBasal() async throws {
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        
        pump.lastTempBasal = nil
        pump.deliveryState = .normal
        pumpState = pump
        
        updateStatus()
        await auditLog?.record(.cancelTempBasal)
        PumpLogger.basal.tempBasalCancelled()
    }
    
    public func deliverBolus(units: Double) async throws {
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        guard units <= maxBolus else {
            throw PumpError.exceedsMaxBolus
        }
        
        guard units > 0 else {
            throw MinimedError.invalidBolusAmount
        }
        
        guard pump.reservoirLevel >= units else {
            throw PumpError.insufficientReservoir
        }
        
        guard pump.deliveryState != .suspended else {
            throw PumpError.suspended
        }
        
        // BOLUS-006: Create active bolus delivery tracking
        let delivery = ActiveBolusDelivery(requestedUnits: units)
        activeBolusDelivery = delivery
        
        // Notify delegate: initiating
        bolusProgressDelegate?.bolusDidStart(id: delivery.id, requested: units)
        
        // Start bolus
        pump.deliveryState = .bolusing
        pump.bolusInProgress = MinimedBolusState(requestedUnits: units)
        pumpState = pump
        updateStatus()
        
        // Update state to delivering
        activeBolusDelivery?.state = .delivering(requested: units, delivered: 0, remaining: units)
        bolusProgressDelegate?.bolusDidProgress(id: delivery.id, delivered: 0, remaining: units, percentComplete: 0.0)
        
        // Medtronic pumps deliver at ~0.025 U/sec (1.5 U/min standard)
        let deliveryRate = 0.025 // U/sec
        
        // BOLUS-011: Check for mid-delivery failures (occlusion, pump fault, etc.)
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "minimed.bolusMidway")
            if case .injected(let fault) = result {
                // Calculate partial delivery based on elapsed time
                let elapsedTime = delivery.elapsedTime
                let deliveredUnits = min(units, elapsedTime * deliveryRate)
                
                // Record partial delivery for IOB calculation
                if deliveredUnits > 0 {
                    await iobTracker.recordBolus(units: deliveredUnits)
                    cachedIOB = await iobTracker.currentIOB()
                    
                    // Queue partial delivery for Nightscout sync
                    if let reporter = deliveryReporter {
                        let event = DeliveryEvent(
                            deliveryType: .bolus,
                            units: deliveredUnits,
                            reason: "Bolus failed (partial delivery)"
                        )
                        await reporter.queue(event)
                    }
                }
                
                // Restore pump state
                pump.bolusInProgress = nil
                pump.deliveryState = pump.lastTempBasal?.isActive == true ? .tempBasal : .normal
                pumpState = pump
                
                // Update bolus state and notify delegate
                let pumpError = mapFaultToError(fault) as? PumpError ?? PumpError.pumpFaulted
                activeBolusDelivery?.state = .failed(delivered: deliveredUnits, error: pumpError)
                bolusProgressDelegate?.bolusDidFail(id: delivery.id, delivered: deliveredUnits, error: pumpError)
                activeBolusDelivery = nil
                
                updateStatus()
                PumpLogger.bolus.bolusFailed(error: pumpError)
                
                throw mapFaultToError(fault)
            }
        }
        
        // In production: RF status polling would track actual delivery progress
        
        // Update state to completing
        activeBolusDelivery?.state = .completing(total: units)
        
        // Complete bolus
        pump.reservoirLevel -= units
        pump.bolusInProgress = nil
        pump.deliveryState = pump.lastTempBasal?.isActive == true ? .tempBasal : .normal
        pumpState = pump
        
        // Track delivery for IOB calculation
        await iobTracker.recordBolus(units: units)
        cachedIOB = await iobTracker.currentIOB()
        
        // BOLUS-006: Update state to completed and notify delegate
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
        
        updateStatus()
        await auditLog?.record(.deliverBolus(units: units))
        PumpLogger.bolus.bolusDelivered(units: units)
    }
    
    // RESEARCH-AID-005: Cancel in-progress bolus delivery
    public func cancelBolus() async throws {
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        // Only cancel if bolus is in progress
        guard pump.deliveryState == .bolusing, pump.bolusInProgress != nil else {
            return // No bolus to cancel
        }
        
        // BOLUS-006: Update active delivery to cancelled state
        // BOLUS-007: Record partial delivery to IOBTracker
        if let delivery = activeBolusDelivery {
            // Calculate how much was delivered based on elapsed time
            let deliveryRate = 0.025 // U/sec (Medtronic standard rate)
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
        
        // Cancel bolus (real implementation would send RF command)
        pump.bolusInProgress = nil
        pump.deliveryState = pump.lastTempBasal?.isActive == true ? .tempBasal : .normal
        pumpState = pump
        updateStatus()
        
        PumpLogger.bolus.bolusCancelled()
    }
    
    public func suspend() async throws {
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        
        pump.deliveryState = .suspended
        pump.suspendedSince = Date()
        pump.lastTempBasal = nil
        pumpState = pump
        
        updateStatus()
        await auditLog?.record(.suspend)
        PumpLogger.delivery.deliverySuspended()
    }
    
    public func resume() async throws {
        guard var pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        
        pump.deliveryState = .normal
        pump.suspendedSince = nil
        pumpState = pump
        
        updateStatus()
        await auditLog?.record(.resume)
        PumpLogger.delivery.deliveryResumed()
    }
    
    // MARK: - Medtronic-Specific Operations
    
    /// Read pump history pages
    /// MDT-HIST-031/032: History page retrieval via RF
    /// - Parameter pages: Number of history pages to read (0 = most recent)
    /// - Returns: Array of parsed history events
    /// - Throws: `PumpError.noSession` if RileyLink session unavailable
    public func readHistory(pages: Int = 1) async throws -> [MinimedHistoryEvent] {
        guard let pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let session = rileyLinkSession else {
            PumpLogger.general.error("MinimedManager: Cannot read history - no RileyLink session")
            throw PumpError.noSession
        }
        
        // MDT-HIST-032: Use RileyLinkSession for history retrieval
        var allEvents: [MinimedHistoryEvent] = []
        
        for pageNum in 0..<pages {
            do {
                let events = try await session.readHistoryPage(
                    serial: pump.pumpId,
                    pageNumber: pageNum,
                    wakeFirst: pageNum == 0,
                    pumpModel: pump.model.rawValue
                )
                allEvents.append(contentsOf: events)
                PumpLogger.general.info("MinimedManager: Read \(events.count) events from page \(pageNum)")
            } catch {
                PumpLogger.general.warning("MinimedManager: Failed to read history page \(pageNum): \(error)")
                if pageNum == 0 {
                    throw error  // First page failure is fatal
                }
                break  // Partial read on subsequent pages
            }
        }
        
        return allEvents
    }
    
    /// Read basal schedule from pump
    /// CRIT-PROFILE-011: Port getBasalSchedule from PumpOpsSession → MinimedManager
    /// - Parameter profile: Which basal profile to read (standard, A, or B)
    /// - Returns: Array of basal schedule entries
    /// - Throws: `PumpError.noSession` if RileyLink session unavailable
    public func readBasalSchedule(profile: MedtronicBasalProfile = .standard) async throws -> [MedtronicBasalScheduleEntry] {
        guard let pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let session = rileyLinkSession else {
            PumpLogger.general.error("MinimedManager: Cannot read basal schedule - no RileyLink session")
            throw PumpError.noSession
        }
        
        do {
            let entries = try await session.readBasalSchedule(
                serial: pump.pumpId,
                profile: profile,
                wakeFirst: true
            )
            PumpLogger.general.info("MinimedManager: Read \(entries.count) basal entries from profile \(String(describing: profile))")
            return entries
        } catch {
            PumpLogger.general.warning("MinimedManager: Failed to read basal schedule: \(error)")
            throw error
        }
    }
    
    /// Write basal schedule to pump
    /// CRIT-PROFILE-012: Port setBasalSchedule from PumpOpsSession → MinimedManager
    /// - Parameters:
    ///   - entries: Array of basal schedule entries to write
    ///   - profile: Which basal profile to write (standard, A, or B)
    /// - Throws: `PumpError.noSession` if RileyLink session unavailable
    public func writeBasalSchedule(
        entries: [MedtronicBasalScheduleEntry],
        profile: MedtronicBasalProfile = .standard
    ) async throws {
        guard let pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        // Validate entry count (max 48 for 30-min slots)
        guard entries.count <= 48 else {
            PumpLogger.general.error("MinimedManager: Too many basal entries (\(entries.count) > 48)")
            throw MinimedError.invalidBasalSchedule
        }
        
        // ARCH-007: Fail explicit - no silent fallback to simulated data
        guard let session = rileyLinkSession else {
            PumpLogger.general.error("MinimedManager: Cannot write basal schedule - no RileyLink session")
            throw PumpError.noSession
        }
        
        do {
            try await session.writeBasalSchedule(
                serial: pump.pumpId,
                entries: entries,
                profile: profile,
                wakeFirst: true
            )
            PumpLogger.general.info("MinimedManager: Wrote \(entries.count) basal entries to profile \(String(describing: profile))")
        } catch {
            PumpLogger.general.warning("MinimedManager: Failed to write basal schedule: \(error)")
            throw error
        }
    }
    
    // MARK: - PumpProfileSyncable (CRIT-PROFILE-015)
    
    /// Sync basal schedule from TherapyProfile to pump
    /// Converts T1PalCore.BasalRate to MedtronicBasalScheduleEntry format
    public func syncBasalSchedule(from profile: TherapyProfile) async throws {
        // Convert TherapyProfile basal rates to Medtronic format
        let entries = profile.basalRates.enumerated().map { index, rate in
            MedtronicBasalScheduleEntry(
                index: index,
                timeOffset: rate.startTime,
                rate: rate.rate
            )
        }
        
        guard !entries.isEmpty else {
            PumpLogger.general.warning("MinimedManager: Cannot sync empty basal schedule")
            throw MinimedError.invalidBasalSchedule
        }
        
        PumpLogger.general.info("MinimedManager: Syncing \(entries.count) basal entries from profile to pump")
        try await writeBasalSchedule(entries: entries)
    }
    
    /// Read basal schedule from pump and convert to T1PalCore format
    /// - Parameter profile: Which basal profile to read (default: standard)
    /// - Returns: Array of BasalRate for TherapyProfile
    public func readBasalSchedule() async throws -> [BasalRate] {
        let entries = try await readBasalSchedule(profile: .standard)
        return entries.map { entry in
            BasalRate(startTime: entry.timeOffset, rate: entry.rate)
        }
    }
    
    /// Get pump settings
    public func readSettings() async throws -> MinimedSettings {
        guard let pump = pumpState else {
            throw MinimedError.noPumpPaired
        }
        
        guard rileyLinkState == .connected else {
            throw PumpError.notConnected
        }
        
        
        return MinimedSettings(
            pumpId: pump.pumpId,
            model: pump.model,
            maxBasal: maxBasalRate,
            maxBolus: maxBolus
        )
    }
    
    // MARK: - Private Methods
    
    private func updateStatus() {
        let connectionState: PumpConnectionState = switch rileyLinkState {
        case .connected:
            if pumpState?.deliveryState == .suspended {
                .suspended
            } else {
                .connected
            }
        case .connecting: .connecting
        default: .disconnected
        }
        
        status = PumpStatus(
            connectionState: connectionState,
            reservoirLevel: pumpState?.reservoirLevel,
            batteryLevel: pumpState?.batteryLevel,
            insulinOnBoard: cachedIOB,
            lastDelivery: nil
        )
        
        onStatusChanged?(status)
    }
    
    // MARK: - Fault Handling (WIRE-006)
    
    /// Map fault type to Minimed error
    private func mapFaultToError(_ fault: PumpFaultType) -> Error {
        switch fault {
        case .connectionDrop, .connectionTimeout:
            return MinimedError.rileyLinkNotConnected
        case .communicationError, .bleDisconnectMidCommand:
            return MinimedError.rfCommunicationFailed
        case .packetCorruption:
            return MinimedError.checksumError
        default:
            return MinimedError.rfCommunicationFailed
        }
    }
}

// MARK: - Minimed-Specific Errors

/// Minimed-specific errors
public enum MinimedError: Error, Sendable, Equatable {
    case noPumpPaired
    case invalidPumpId
    case invalidRate
    case invalidDuration
    case invalidBolusAmount
    case invalidBasalSchedule  // CRIT-PROFILE-012: Too many entries or invalid format
    case rileyLinkNotConnected
    case rfCommunicationFailed
    case pumpNotResponding
    case checksumError
    case historyReadFailed
}

// MARK: - History Events

/// Medtronic pump history event types
public enum MinimedHistoryEventType: String, Sendable, Codable {
    case bolus
    case tempBasal
    case basalProfileStart
    case suspend
    case resume
    case rewind
    case prime
    case alarm
    case bgReceived
    case unknown  // For unparsed events (RL-WIRE-016)
}

/// Medtronic pump history event
public struct MinimedHistoryEvent: Sendable, Codable {
    public let type: MinimedHistoryEventType
    public let timestamp: Date
    public let data: [String: String]?
    public let rawData: Data?  // Raw bytes for debugging (RL-WIRE-016)
    
    public init(type: MinimedHistoryEventType, timestamp: Date, data: [String: String]? = nil, rawData: Data? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.data = data
        self.rawData = rawData
    }
}

// MARK: - Settings

/// Medtronic pump settings
public struct MinimedSettings: Sendable, Codable {
    public let pumpId: String
    public let model: MinimedPumpModel
    public let maxBasal: Double
    public let maxBolus: Double
    
    public init(pumpId: String, model: MinimedPumpModel, maxBasal: Double, maxBolus: Double) {
        self.pumpId = pumpId
        self.model = model
        self.maxBasal = maxBasal
        self.maxBolus = maxBolus
    }
}
