// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodErosManager.swift
// PumpKit
//
// Omnipod Eros pump manager implementation.
// Uses ErosBLEManager for RF communication via RileyLink.
// Trace: EROS-IMPL-003, PUMP-OMNI-003, PRD-005, REQ-AID-001
//
// This provides the PumpManagerProtocol implementation for Omnipod Eros pods.
// Requires RileyLink/OrangeLink bridge for RF communication at 433.91 MHz.

import Foundation
import NightscoutKit

// MARK: - Eros Pod State

/// Omnipod Eros pod state (persisted between sessions)
public struct ErosPodState: Sendable, Codable {
    public let podAddress: UInt32
    public let lotNumber: UInt32
    public let tid: UInt32
    public let activationDate: Date
    public var deliveryState: ErosDeliveryState
    public var reservoirLevel: Double?  // nil if > 50U
    public var totalDelivered: Double
    public var packetSequence: Int
    public var messageSequence: Int
    public var lastTempBasal: ErosTempBasalState?
    public var alerts: [ErosPodAlert]
    public var faultCode: UInt8?
    
    public var isExpired: Bool {
        Date().timeIntervalSince(activationDate) > 72 * 3600 // 72 hours
    }
    
    public var isLowReservoir: Bool {
        if let level = reservoirLevel {
            return level < 10
        }
        return false
    }
    
    public var addressHex: String {
        String(format: "0x%08X", podAddress)
    }
    
    public init(
        podAddress: UInt32,
        lotNumber: UInt32 = 0,
        tid: UInt32 = 0,
        activationDate: Date = Date(),
        deliveryState: ErosDeliveryState = .basalRunning,
        reservoirLevel: Double? = nil,
        totalDelivered: Double = 0,
        packetSequence: Int = 0,
        messageSequence: Int = 0,
        lastTempBasal: ErosTempBasalState? = nil,
        alerts: [ErosPodAlert] = [],
        faultCode: UInt8? = nil
    ) {
        self.podAddress = podAddress
        self.lotNumber = lotNumber
        self.tid = tid
        self.activationDate = activationDate
        self.deliveryState = deliveryState
        self.reservoirLevel = reservoirLevel
        self.totalDelivered = totalDelivered
        self.packetSequence = packetSequence
        self.messageSequence = messageSequence
        self.lastTempBasal = lastTempBasal
        self.alerts = alerts
        self.faultCode = faultCode
    }
}

/// Eros delivery state
public enum ErosDeliveryState: String, Sendable, Codable {
    case uninitialized
    case pairingCompleted
    case insertingCannula
    case aboveFiftyUnits      // Running, reservoir > 50U
    case belowFiftyUnits      // Running, reservoir <= 50U
    case basalRunning
    case tempBasalRunning
    case bolusInProgress
    case suspended
    case faulted
    case deactivated
}

/// Eros temp basal state
public struct ErosTempBasalState: Sendable, Codable {
    public let rate: Double
    public let startTime: Date
    public let duration: TimeInterval
    
    public var isActive: Bool {
        Date() < startTime.addingTimeInterval(duration)
    }
    
    public init(rate: Double, startTime: Date = Date(), duration: TimeInterval) {
        self.rate = rate
        self.startTime = startTime
        self.duration = duration
    }
}

/// Eros pod alerts
public enum ErosPodAlert: String, Sendable, Codable {
    case lowReservoir
    case podExpiring
    case podExpired
    case occlusionDetected
    case suspended
    case autoOff
}

// MARK: - Omnipod Eros Manager

/// Omnipod Eros pump manager
/// Implements PumpManagerProtocol for Omnipod Eros pods via RileyLink
/// Trace: EROS-IMPL-003, REQ-AID-001
public actor OmnipodErosManager: PumpManagerProtocol {
    public nonisolated let displayName = "Omnipod (Eros)"
    public nonisolated let pumpType = PumpType.omnipodEros
    
    public private(set) var status: PumpStatus
    
    public var onStatusChanged: (@Sendable (PumpStatus) -> Void)?
    public var onError: (@Sendable (PumpError) -> Void)?
    
    // BOLUS-003: Bolus progress tracking
    public private(set) var activeBolusDelivery: ActiveBolusDelivery?
    public var bolusProgressDelegate: (any BolusProgressDelegate)?
    
    // BOLUS-008: Nightscout sync
    public var deliveryReporter: DeliveryReporter?
    
    // BLE Manager for RF communication
    private let bleManager: ErosBLEManager
    
    // Pod state
    private var podState: ErosPodState?
    private var isConnected: Bool = false
    
    // Configuration
    private let basalRate: Double
    private let maxBolus: Double
    private let maxBasalRate: Double
    
    /// Audit log for command recording
    public let auditLog: PumpAuditLog?
    
    /// Optional fault injector for testing error paths
    private var faultInjector: PumpFaultInjector?
    
    /// Session logger for diagnostic tracing (EROS-DIAG-003)
    public var sessionLogger: ErosSessionLogger?
    
    /// Delivery tracker for IOB calculation
    private let iobTracker = IOBTracker()
    
    /// Cached IOB value
    private var cachedIOB: Double = 0
    
    /// Pod lifecycle expiration monitor (LIFE-PUMP-003)
    private var lifecycleMonitor: PodExpirationMonitor?
    
    /// Pod expiration notification callback
    public var onPodExpirationWarning: (@Sendable (PodExpirationNotification) async -> Void)?
    
    // MARK: - Initialization
    
    public init(
        bleManager: ErosBLEManager = ErosBLEManager(),
        basalRate: Double = 1.0,
        maxBolus: Double = 10.0,
        maxBasalRate: Double = 5.0,
        auditLog: PumpAuditLog? = nil,
        faultInjector: PumpFaultInjector? = nil
    ) {
        self.bleManager = bleManager
        self.basalRate = basalRate
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.auditLog = auditLog
        self.faultInjector = faultInjector
        self.status = PumpStatus(connectionState: .disconnected)
        // LIFE-PUMP-009: Create lifecycle monitor with UserDefaults persistence
        self.lifecycleMonitor = PodExpirationMonitor(persistence: UserDefaultsPodPersistence())
        PumpLogger.general.info("OmnipodErosManager: initialized")
    }
    
    /// LIFE-PUMP-009: Restore lifecycle state from persistence
    /// Call this after init to restore any saved pod session
    public func restoreLifecycleState() async {
        await lifecycleMonitor?.restoreSession()
        if let session = await lifecycleMonitor?.currentSession() {
            PumpLogger.general.info("OmnipodErosManager: restored pod session \(session.podId)")
        }
    }
    
    /// Create manager in test mode
    public static func forTesting(faultInjector: PumpFaultInjector? = nil) -> OmnipodErosManager {
        OmnipodErosManager(
            bleManager: ErosBLEManager.forTesting(),
            faultInjector: faultInjector
        )
    }
    
    // MARK: - Fault Injection
    
    /// Set or replace the fault injector
    public func setFaultInjector(_ injector: PumpFaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Check for fault injection and throw if triggered
    private func checkFaultInjection(for operation: String) throws {
        guard let injector = faultInjector else { return }
        
        if case .injected(let fault) = injector.shouldInject(for: operation) {
            PumpLogger.general.warning("Fault injected for \(operation): \(fault.displayName)")
            
            switch fault {
            case .occlusion, .airInLine, .motorStall:
                throw PumpError.occluded
            case .emptyReservoir:
                throw PumpError.insufficientReservoir
            case .connectionDrop, .bleDisconnectMidCommand:
                isConnected = false
                updateStatus()
                throw PumpError.notConnected
            case .connectionTimeout, .communicationError, .packetCorruption, .wrongChannelResponse:
                throw PumpError.communicationError
            case .lowBattery, .batteryDepleted:
                throw PumpError.communicationError
            case .unexpectedSuspend, .alarmActive, .primeRequired:
                throw PumpError.suspended
            case .commandDelay, .intermittentFailure:
                throw PumpError.communicationError
            }
        }
    }
    
    // MARK: - Connection
    
    public func connect() async throws {
        try checkFaultInjection(for: "connect")
        
        sessionLogger?.transitionTo(.scanning, reason: "connect() called")
        PumpLogger.general.info("OmnipodErosManager: connecting...")
        
        // Check for existing pod state
        if let state = podState {
            await bleManager.resumeSession(
                podAddress: state.podAddress,
                packetSequence: state.packetSequence,
                messageSequence: state.messageSequence
            )
        }
        
        isConnected = true
        updateStatus()
        sessionLogger?.transitionTo(.running, reason: "Connected")
        
        await auditLog?.record(.connect)
    }
    
    public func disconnect() async {
        sessionLogger?.transitionTo(.deactivating, reason: "disconnect() called")
        PumpLogger.general.info("OmnipodErosManager: disconnecting")
        
        // Save current session state before disconnecting
        if var state = podState, let session = await bleManager.currentSession {
            state.packetSequence = session.packetSequence
            state.messageSequence = session.messageSequence
            podState = state
        }
        
        await bleManager.disconnect()
        isConnected = false
        updateStatus()
        sessionLogger?.transitionTo(.idle, reason: "Disconnected")
        
        await auditLog?.record(.disconnect)
    }
    
    // MARK: - Pod Pairing
    
    /// Pair with a new Eros pod
    public func pairPod(address: UInt32) async throws {
        try checkFaultInjection(for: "pairPod")
        
        sessionLogger?.transitionTo(.assigning, reason: "pairPod")
        PumpLogger.general.info("OmnipodErosManager: pairing with pod \(String(format: "0x%08X", address))")
        
        podState = ErosPodState(podAddress: address)
        
        try await bleManager.pairPod(address: address)
        
        // Start lifecycle monitoring (LIFE-PUMP-003, LIFE-PUMP-009)
        if let pod = podState {
            let session = PodSession(
                podId: pod.addressHex,
                variant: .eros,
                activationDate: pod.activationDate
            )
            await lifecycleMonitor?.startSession(session)
        }
        
        isConnected = true
        updateStatus()
        sessionLogger?.transitionTo(.running, reason: "pairPod success")
        
        await auditLog?.record(.activatePod(podId: String(format: "0x%08X", address)))
    }
    
    /// Load existing pod state (from persistence)
    public func loadPodState(_ state: ErosPodState) {
        podState = state
        PumpLogger.general.info("OmnipodErosManager: loaded pod state for \(state.addressHex)")
    }
    
    /// Get current pod state
    public var currentPodState: ErosPodState? {
        podState
    }
    
    /// Get current pod lifecycle progress (LIFE-PUMP-003)
    public func getPodProgress() async -> PodProgress? {
        guard let session = await lifecycleMonitor?.currentSession() else {
            return nil
        }
        return PodProgress(session: session)
    }
    
    /// Check pod expiration and trigger notification if needed (LIFE-PUMP-003)
    public func checkPodLifecycle() async {
        guard let monitor = lifecycleMonitor else { return }
        
        let result = await monitor.checkExpiration()
        switch result {
        case .warning(let notification):
            await monitor.markWarningSent(notification.warning)
            await onPodExpirationWarning?(notification)
            PumpLogger.general.warning("Pod expiration warning: \(notification.warning.message)")
        case .inGracePeriod(let graceRemaining):
            PumpLogger.general.warning("Pod in grace period: \(Int(graceRemaining))h remaining")
        case .stopped:
            PumpLogger.general.error("Pod delivery stopped - past grace period")
        default:
            break
        }
    }
    
    // MARK: - Status
    
    public func refreshStatus() async throws {
        try checkFaultInjection(for: "refreshStatus")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        let podInfo = try await bleManager.getPodStatus()
        
        if var state = podState {
            state.reservoirLevel = podInfo.reservoirLevel
            state.faultCode = podInfo.faultCode
            podState = state
        }
        
        updateStatus()
    }
    
    // MARK: - Bolus
    
    public func deliverBolus(units: Double) async throws {
        try checkFaultInjection(for: "deliverBolus")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        guard units > 0 && units <= maxBolus else {
            throw PumpError.exceedsMaxBolus
        }
        
        if let level = podState?.reservoirLevel, level < units {
            throw PumpError.insufficientReservoir
        }
        
        // BOLUS-007: Create active bolus delivery tracking
        let delivery = ActiveBolusDelivery(requestedUnits: units)
        activeBolusDelivery = delivery
        
        // Notify delegate: initiating
        bolusProgressDelegate?.bolusDidStart(id: delivery.id, requested: units)
        
        sessionLogger?.transitionTo(.bolusing, reason: "deliverBolus \(units)U")
        PumpLogger.general.info("OmnipodErosManager: delivering bolus \(units)U")
        
        // Update state to delivering
        activeBolusDelivery?.state = .delivering(requested: units, delivered: 0, remaining: units)
        bolusProgressDelegate?.bolusDidProgress(id: delivery.id, delivered: 0, remaining: units, percentComplete: 0.0)
        
        // BOLUS-011: Handle mid-delivery failures (occlusion, pump fault, etc.)
        do {
            try await bleManager.deliverBolus(units: units)
        } catch let error as PumpError {
            // Calculate partial delivery based on elapsed time
            let deliveryRate = 0.025 // U/sec (standard Omnipod pulse rate)
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
            
            // Update state and notify delegate
            activeBolusDelivery?.state = .failed(delivered: deliveredUnits, error: error)
            bolusProgressDelegate?.bolusDidFail(id: delivery.id, delivered: deliveredUnits, error: error)
            activeBolusDelivery = nil
            
            updateStatus()
            PumpLogger.bolus.bolusFailed(error: error)
            
            throw error
        } catch {
            // Non-PumpError failures
            let deliveryRate = 0.025
            let elapsedTime = delivery.elapsedTime
            let deliveredUnits = min(units, elapsedTime * deliveryRate)
            
            if deliveredUnits > 0 {
                await iobTracker.recordBolus(units: deliveredUnits)
                cachedIOB = await iobTracker.currentIOB()
            }
            
            let pumpError = PumpError.communicationError
            activeBolusDelivery?.state = .failed(delivered: deliveredUnits, error: pumpError)
            bolusProgressDelegate?.bolusDidFail(id: delivery.id, delivered: deliveredUnits, error: pumpError)
            activeBolusDelivery = nil
            
            updateStatus()
            PumpLogger.bolus.bolusFailed(error: pumpError)
            
            throw error
        }
        
        if var state = podState {
            state.deliveryState = .bolusInProgress
            state.totalDelivered += units
            if let level = state.reservoirLevel {
                state.reservoirLevel = level - units
            }
            podState = state
        }
        
        await iobTracker.recordBolus(units: units)
        cachedIOB = await iobTracker.currentIOB()
        
        // BOLUS-007: Update state to completed and notify delegate
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
        
        sessionLogger?.transitionTo(.running, reason: "deliverBolus success")
        updateStatus()
        
        await auditLog?.record(.deliverBolus(units: units))
        PumpLogger.bolus.bolusDelivered(units: units)
    }
    
    public func cancelBolus() async throws {
        try checkFaultInjection(for: "cancelBolus")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.running, reason: "cancelBolus")
        PumpLogger.general.info("OmnipodErosManager: canceling bolus")
        
        // BOLUS-007: Record partial delivery to IOBTracker
        if let delivery = activeBolusDelivery {
            // Calculate how much was delivered based on elapsed time
            let deliveryRate = 0.025 // U/sec (Eros standard rate)
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
        
        try await bleManager.cancelDelivery()
        
        if var state = podState {
            state.deliveryState = .basalRunning
            podState = state
        }
        
        updateStatus()
    }
    
    // MARK: - Temp Basal
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        try checkFaultInjection(for: "setTempBasal")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        guard rate >= 0 && rate <= maxBasalRate else {
            throw PumpError.exceedsMaxBasal
        }
        
        guard duration >= 1800 && duration <= 43200 else {
            throw PumpError.exceedsMaxBasal
        }
        
        sessionLogger?.transitionTo(.tempBasal, reason: "setTempBasal \(rate)U/hr")
        PumpLogger.general.info("OmnipodErosManager: setting temp basal \(rate)U/hr for \(duration/60)min")
        
        try await bleManager.setTempBasal(rate: rate, duration: duration)
        
        if var state = podState {
            state.deliveryState = .tempBasalRunning
            state.lastTempBasal = ErosTempBasalState(rate: rate, duration: duration)
            podState = state
        }
        
        updateStatus()
        
        await auditLog?.record(.setTempBasal(rate: rate, durationMinutes: duration / 60))
        PumpLogger.basal.tempBasalSet(rate: rate, duration: duration)
    }
    
    public func cancelTempBasal() async throws {
        try checkFaultInjection(for: "cancelTempBasal")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.running, reason: "cancelTempBasal")
        PumpLogger.general.info("OmnipodErosManager: canceling temp basal")
        
        try await bleManager.cancelDelivery()
        
        if var state = podState {
            state.deliveryState = .basalRunning
            state.lastTempBasal = nil
            podState = state
        }
        
        updateStatus()
        
        await auditLog?.record(.cancelTempBasal)
        PumpLogger.basal.tempBasalCancelled()
    }
    
    // MARK: - Suspend/Resume
    
    public func suspend() async throws {
        try checkFaultInjection(for: "suspend")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.idle, reason: "suspend")
        PumpLogger.general.info("OmnipodErosManager: suspending delivery")
        
        try await bleManager.cancelDelivery()
        
        if var state = podState {
            state.deliveryState = .suspended
            state.lastTempBasal = nil
            podState = state
        }
        
        updateStatus()
        
        await auditLog?.record(.suspend)
        PumpLogger.delivery.deliverySuspended()
    }
    
    public func resume() async throws {
        try checkFaultInjection(for: "resume")
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.running, reason: "resume")
        PumpLogger.general.info("OmnipodErosManager: resuming delivery")
        
        if var state = podState {
            state.deliveryState = .basalRunning
            podState = state
        }
        
        updateStatus()
        
        await auditLog?.record(.resume)
        PumpLogger.delivery.deliveryResumed()
    }
    
    // MARK: - Pod Deactivation
    
    /// Deactivate current pod
    public func deactivatePod() async throws {
        try checkFaultInjection(for: "deactivatePod")
        
        guard let pod = podState else {
            throw PumpError.notConnected
        }
        
        sessionLogger?.transitionTo(.deactivating, reason: "deactivatePod")
        PumpLogger.general.info("OmnipodErosManager: deactivating pod")
        
        try await bleManager.deactivatePod()
        
        if var state = podState {
            state.deliveryState = .deactivated
            podState = state
        }
        
        // Clear lifecycle monitoring (LIFE-PUMP-003, LIFE-PUMP-009)
        await lifecycleMonitor?.endSession()
        
        updateStatus()
        sessionLogger?.transitionTo(.idle, reason: "deactivatePod complete")
        
        await auditLog?.record(.deactivatePod(podId: pod.addressHex))
    }
    
    /// Discard pod state
    public func discardPod() async {
        // Clear lifecycle monitoring (LIFE-PUMP-003, LIFE-PUMP-009)
        await lifecycleMonitor?.endSession()
        
        podState = nil
        isConnected = false
        updateStatus()
        PumpLogger.general.info("OmnipodErosManager: pod state discarded")
    }
    
    // MARK: - Private Helpers
    
    private func updateStatus() {
        let connectionState: PumpConnectionState = isConnected ? .connected : .disconnected
        
        let newStatus = PumpStatus(
            connectionState: connectionState,
            reservoirLevel: podState?.reservoirLevel,
            batteryLevel: nil,
            insulinOnBoard: cachedIOB,
            lastDelivery: Date()
        )
        
        status = newStatus
        onStatusChanged?(newStatus)
    }
}

// MARK: - Testing Support

extension OmnipodErosManager {
    /// Create a simulated active pod for testing
    public func simulateActivePod(address: UInt32 = 0x1F01482A, reservoirLevel: Double = 150) {
        podState = ErosPodState(
            podAddress: address,
            activationDate: Date().addingTimeInterval(-3600),
            deliveryState: .basalRunning,
            reservoirLevel: reservoirLevel
        )
        isConnected = true
        updateStatus()
    }
    
    /// Create a faulted pod state for testing
    public func simulateFaultedPod(address: UInt32 = 0x1F01482A, faultCode: UInt8 = 0x14) {
        podState = ErosPodState(
            podAddress: address,
            activationDate: Date().addingTimeInterval(-7200),
            deliveryState: .faulted,
            reservoirLevel: nil,
            faultCode: faultCode
        )
        isConnected = false
        updateStatus()
    }
}
