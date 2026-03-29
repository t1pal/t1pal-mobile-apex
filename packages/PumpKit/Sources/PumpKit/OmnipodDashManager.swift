// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodDashManager.swift
// PumpKit
//
// Omnipod DASH pump manager implementation
// Trace: PUMP-009, PRD-005, REQ-AID-001, LOG-ADOPT-006
//
// This provides the PumpManagerProtocol implementation for Omnipod DASH.
// Uses simulation for testing, can be extended with real OmniBLE integration.

import Foundation
import NightscoutKit

// MARK: - Pod State

/// Omnipod DASH pod state
public struct DashPodState: Sendable, Codable {
    public let podId: String
    public let activationDate: Date
    public var deliveryState: DashDeliveryState
    public var reservoirLevel: Double
    public var totalDelivered: Double
    public var lastTempBasal: DashTempBasalState?
    public var alerts: [DashPodAlert]
    public var faultCode: UInt8?
    
    public var isExpired: Bool {
        Date().timeIntervalSince(activationDate) > 72 * 3600 // 72 hours
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 10
    }
    
    public init(
        podId: String = UUID().uuidString.prefix(8).lowercased(),
        activationDate: Date = Date(),
        deliveryState: DashDeliveryState = .basalRunning,
        reservoirLevel: Double = 200,
        totalDelivered: Double = 0,
        lastTempBasal: DashTempBasalState? = nil,
        alerts: [DashPodAlert] = [],
        faultCode: UInt8? = nil
    ) {
        self.podId = String(podId)
        self.activationDate = activationDate
        self.deliveryState = deliveryState
        self.reservoirLevel = reservoirLevel
        self.totalDelivered = totalDelivered
        self.lastTempBasal = lastTempBasal
        self.alerts = alerts
        self.faultCode = faultCode
    }
}

/// DASH delivery state
public enum DashDeliveryState: String, Sendable, Codable {
    case suspended
    case basalRunning
    case tempBasalRunning
    case bolusInProgress
    case faulted
    case deactivated
}

/// DASH temp basal state (uses duration instead of endTime)
public struct DashTempBasalState: Sendable, Codable {
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

/// DASH pod alerts
public enum DashPodAlert: String, Sendable, Codable {
    case lowReservoir
    case podExpiring
    case podExpired
    case occlusionDetected
    case suspended
}

// MARK: - Omnipod DASH Manager

/// Omnipod DASH pump manager
/// Implements PumpManagerProtocol for Omnipod DASH pods
/// Trace: PUMP-009, REQ-AID-001
public actor OmnipodDashManager: PumpManagerProtocol {
    public nonisolated let displayName = "Omnipod DASH"
    public nonisolated let pumpType = PumpType.omnipodDash
    
    public private(set) var status: PumpStatus
    
    public var onStatusChanged: (@Sendable (PumpStatus) -> Void)?
    public var onError: (@Sendable (PumpError) -> Void)?
    
    // BOLUS-003: Bolus progress tracking
    public private(set) var activeBolusDelivery: ActiveBolusDelivery?
    public var bolusProgressDelegate: (any BolusProgressDelegate)?
    
    // BOLUS-008: Nightscout sync
    public var deliveryReporter: DeliveryReporter?
    
    /// Set the bolus progress delegate (actor-isolated setter)
    public func setBolusProgressDelegate(_ delegate: (any BolusProgressDelegate)?) {
        bolusProgressDelegate = delegate
    }
    
    // Pod state
    private var podState: DashPodState?
    private var isConnected: Bool = false
    
    // Configuration
    private let basalRate: Double
    private let maxBolus: Double
    private let maxBasalRate: Double
    
    /// Audit log for command recording
    public let auditLog: PumpAuditLog?
    
    /// Session logger for verbose protocol debugging (PROTO-DASH-DIAG)
    public var sessionLogger: DASHSessionLogger?
    
    /// Optional fault injector for testing error paths
    /// Trace: SWIFT-FAULT-005, SIM-FAULT-001
    private var faultInjector: PumpFaultInjector?
    
    /// Delivery tracker for IOB calculation
    private let iobTracker = IOBTracker()
    
    /// Cached IOB value (updated after each delivery)
    private var cachedIOB: Double = 0
    
    /// Pod lifecycle expiration monitor (LIFE-PUMP-003)
    private var lifecycleMonitor: PodExpirationMonitor?
    
    /// Pod expiration notification callback
    public var onPodExpirationWarning: (@Sendable (PodExpirationNotification) async -> Void)?
    
    // MARK: - Initialization
    
    public init(
        basalRate: Double = 1.0,
        maxBolus: Double = 10.0,
        maxBasalRate: Double = 5.0,
        auditLog: PumpAuditLog? = nil,
        faultInjector: PumpFaultInjector? = nil
    ) {
        self.basalRate = basalRate
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.auditLog = auditLog
        self.faultInjector = faultInjector
        self.status = PumpStatus(connectionState: .disconnected)
        // LIFE-PUMP-009: Create lifecycle monitor with UserDefaults persistence
        self.lifecycleMonitor = PodExpirationMonitor(persistence: UserDefaultsPodPersistence())
        PumpLogger.general.info("OmnipodDashManager: initialized")
    }
    
    /// LIFE-PUMP-009: Restore lifecycle state from persistence
    /// Call this after init to restore any saved pod session
    public func restoreLifecycleState() async {
        await lifecycleMonitor?.restoreSession()
        if let session = await lifecycleMonitor?.currentSession() {
            PumpLogger.general.info("OmnipodDashManager: restored pod session \(session.podId)")
        }
    }
    
    // MARK: - Fault Injection (SWIFT-FAULT-005)
    
    /// Set or replace the fault injector
    public func setFaultInjector(_ injector: PumpFaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Get current fault injector (for testing)
    public var currentFaultInjector: PumpFaultInjector? {
        faultInjector
    }
    
    /// Check for fault injection and throw if triggered
    private func checkFaultInjection(for operation: String) throws {
        guard let injector = faultInjector else { return }
        
        if case .injected(let fault) = injector.shouldInject(for: operation) {
            PumpLogger.general.warning("Fault injected for \(operation): \(fault.displayName)")
            
            switch fault {
            case .occlusion:
                throw PumpError.occluded
            case .emptyReservoir:
                throw PumpError.insufficientReservoir
            case .connectionDrop, .bleDisconnectMidCommand:
                isConnected = false
                updateStatus()
                throw PumpError.notConnected
            case .connectionTimeout:
                throw PumpError.communicationError
            case .communicationError:
                throw PumpError.communicationError
            case .unexpectedSuspend:
                if var pod = podState {
                    pod.deliveryState = .suspended
                    podState = pod
                    updateStatus()
                }
                throw PumpError.suspended
            case .alarmActive(let code):
                if var pod = podState {
                    pod.faultCode = code
                    pod.deliveryState = .faulted
                    podState = pod
                    updateStatus()
                }
                throw PumpError.pumpFaulted
            default:
                // Other faults log but don't throw
                break
            }
        }
    }
    
    // MARK: - Pod Management
    
    /// Activate a new pod
    public func activatePod() async throws {
        guard podState == nil || podState?.deliveryState == .deactivated else {
            throw PumpError.alreadyActivated
        }
        
        // Create new pod
        podState = DashPodState()
        
        // Start lifecycle monitoring (LIFE-PUMP-003, LIFE-PUMP-009)
        if let pod = podState {
            let session = PodSession(
                podId: pod.podId,
                variant: .dash,
                activationDate: pod.activationDate
            )
            await lifecycleMonitor?.startSession(session)
        }
        
        // Update status
        updateStatus()
        await auditLog?.record(.activatePod(podId: podState?.podId ?? "unknown"))
    }
    
    /// Deactivate current pod
    public func deactivatePod() async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        pod.deliveryState = .deactivated
        podState = pod
        
        // Clear lifecycle monitoring (LIFE-PUMP-003, LIFE-PUMP-009)
        await lifecycleMonitor?.endSession()
        
        updateStatus()
        await auditLog?.record(.deactivatePod(podId: pod.podId))
    }
    
    /// Get current pod state
    public var currentPodState: DashPodState? {
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
    
    // MARK: - PumpManagerProtocol
    
    public func connect() async throws {
        guard podState != nil else {
            throw PumpError.noPodPaired
        }
        
        // Check fault injection before connecting
        try checkFaultInjection(for: "connect")
        
        // Log connection attempt
        sessionLogger?.transitionTo(.connecting, reason: "connect() called")
        sessionLogger?.logCommandSent(command: "CONNECT", notes: "BLE connection")
        
        // In production: actual BLE connection provides timing
        // In tests: instant completion
        
        isConnected = true
        sessionLogger?.logCommandResponse(command: "CONNECT", success: true, notes: "Connected")
        sessionLogger?.transitionTo(.sessionEstablished, reason: "BLE connected")
        updateStatus()
        await auditLog?.record(AuditCommand.connect)
    }
    
    public func disconnect() async {
        sessionLogger?.transitionTo(.disconnecting, reason: "disconnect() called")
        isConnected = false
        sessionLogger?.transitionTo(.idle, reason: "Disconnected")
        updateStatus()
        await auditLog?.record(AuditCommand.disconnect)
    }
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Check fault injection before operation
        try checkFaultInjection(for: "setTempBasal")
        
        guard rate <= maxBasalRate else {
            throw PumpError.exceedsMaxBasal
        }
        
        guard pod.deliveryState != .faulted && pod.deliveryState != .deactivated else {
            throw PumpError.pumpFaulted
        }
        
        // Log command
        sessionLogger?.transitionTo(.commandPending, reason: "setTempBasal")
        sessionLogger?.logCommandSent(command: "SET_TEMP_BASAL", notes: "\(rate)U/h for \(duration/60)min")
        
        // Set temp basal
        pod.lastTempBasal = DashTempBasalState(rate: rate, duration: duration)
        let previousState = pod.deliveryState.rawValue
        pod.deliveryState = .tempBasalRunning
        podState = pod
        
        sessionLogger?.logTempBasal(rate: rate, duration: duration, isSet: true)
        sessionLogger?.logDeliveryStateChange(from: previousState, to: pod.deliveryState.rawValue, reason: "Temp basal set")
        sessionLogger?.logCommandResponse(command: "SET_TEMP_BASAL", success: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "setTempBasal success")
        
        updateStatus()
        await auditLog?.record(.setTempBasal(rate: rate, durationMinutes: duration / 60))
        PumpLogger.basal.tempBasalSet(rate: rate, duration: duration)
    }
    
    public func cancelTempBasal() async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Check fault injection before operation
        try checkFaultInjection(for: "cancelTempBasal")
        
        // Log command
        sessionLogger?.transitionTo(.commandPending, reason: "cancelTempBasal")
        sessionLogger?.logCommandSent(command: "CANCEL_TEMP_BASAL")
        
        let previousState = pod.deliveryState.rawValue
        pod.lastTempBasal = nil
        pod.deliveryState = .basalRunning
        podState = pod
        
        sessionLogger?.logTempBasal(rate: 0, duration: 0, isSet: false)
        sessionLogger?.logDeliveryStateChange(from: previousState, to: pod.deliveryState.rawValue, reason: "Temp basal cancelled")
        sessionLogger?.logCommandResponse(command: "CANCEL_TEMP_BASAL", success: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "cancelTempBasal success")
        
        updateStatus()
        await auditLog?.record(.cancelTempBasal)
        PumpLogger.basal.tempBasalCancelled()
    }
    
    public func deliverBolus(units: Double) async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Check fault injection before bolus (critical operation)
        try checkFaultInjection(for: "deliverBolus")
        
        guard units <= maxBolus else {
            throw PumpError.exceedsMaxBolus
        }
        
        guard units <= pod.reservoirLevel else {
            throw PumpError.insufficientReservoir
        }
        
        guard pod.deliveryState != .faulted && pod.deliveryState != .deactivated else {
            throw PumpError.pumpFaulted
        }
        
        // BOLUS-005: Create active bolus delivery tracking
        let delivery = ActiveBolusDelivery(requestedUnits: units)
        activeBolusDelivery = delivery
        
        // Notify delegate: initiating
        bolusProgressDelegate?.bolusDidStart(id: delivery.id, requested: units)
        
        // Log command
        sessionLogger?.transitionTo(.commandPending, reason: "deliverBolus")
        sessionLogger?.logCommandSent(command: "DELIVER_BOLUS", notes: "\(units)U")
        
        let previousState = pod.deliveryState
        pod.deliveryState = .bolusInProgress
        podState = pod
        sessionLogger?.logDeliveryStateChange(from: previousState.rawValue, to: pod.deliveryState.rawValue, reason: "Bolus started")
        updateStatus()
        
        // Update state to delivering
        activeBolusDelivery?.state = .delivering(requested: units, delivered: 0, remaining: units)
        let percentComplete = 0.0
        bolusProgressDelegate?.bolusDidProgress(id: delivery.id, delivered: 0, remaining: units, percentComplete: percentComplete)
        
        // In production: actual pod delivery provides timing via BLE notifications
        // DASH delivers at ~0.5 U/sec for pulses, 2 sec per 0.05U pulse = 0.025 U/s
        let deliveryRate = 0.025 // U/sec (standard Omnipod pulse rate)
        let deliveryTime = units / deliveryRate // seconds
        
        // BOLUS-011: Handle mid-delivery failures (occlusion, pump fault, etc.)
        do {
            try checkFaultInjection(for: "deliverBolusMidway")
        } catch let error as PumpError {
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
            
            // Update state and notify delegate
            activeBolusDelivery?.state = .failed(delivered: deliveredUnits, error: error)
            bolusProgressDelegate?.bolusDidFail(id: delivery.id, delivered: deliveredUnits, error: error)
            activeBolusDelivery = nil
            
            // Restore pod state
            pod.deliveryState = previousState
            podState = pod
            updateStatus()
            
            sessionLogger?.logBolusDelivery(units: deliveredUnits, duration: elapsedTime, success: false)
            sessionLogger?.transitionTo(.error, reason: "Bolus failed: \(error)")
            PumpLogger.bolus.bolusFailed(error: error)
            
            throw error
        }
        
        // Update state to completing
        activeBolusDelivery?.state = .completing(total: units)
        
        // Update after delivery
        pod.reservoirLevel -= units
        pod.totalDelivered += units
        pod.deliveryState = previousState
        podState = pod
        
        // Track delivery for IOB calculation
        await iobTracker.recordBolus(units: units)
        cachedIOB = await iobTracker.currentIOB()
        
        // Update state to completed
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
        
        sessionLogger?.logBolusDelivery(units: units, duration: deliveryTime, success: true)
        sessionLogger?.logDeliveryStateChange(from: DashDeliveryState.bolusInProgress.rawValue, to: pod.deliveryState.rawValue, reason: "Bolus complete")
        sessionLogger?.logCommandResponse(command: "DELIVER_BOLUS", success: true, notes: "Delivered \(units)U")
        sessionLogger?.transitionTo(.commandComplete, reason: "deliverBolus success")
        
        updateStatus()
        await auditLog?.record(.deliverBolus(units: units))
        PumpLogger.bolus.bolusDelivered(units: units)
    }
    
    // RESEARCH-AID-005: Cancel in-progress bolus delivery
    public func cancelBolus() async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Only cancel if bolus is in progress
        guard pod.deliveryState == .bolusInProgress else {
            return // No bolus to cancel
        }
        
        sessionLogger?.logCommandSent(command: "CANCEL_BOLUS", notes: "User requested")
        
        // BOLUS-005: Update active delivery to cancelled state
        // BOLUS-007: Record partial delivery to IOBTracker
        if let delivery = activeBolusDelivery {
            // Calculate how much was delivered based on elapsed time
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
        
        let previousState = pod.deliveryState
        pod.deliveryState = .basalRunning
        podState = pod
        
        sessionLogger?.logDeliveryStateChange(from: previousState.rawValue, to: pod.deliveryState.rawValue, reason: "Bolus cancelled")
        sessionLogger?.logCommandResponse(command: "CANCEL_BOLUS", success: true)
        
        updateStatus()
        PumpLogger.bolus.bolusCancelled()
    }
    
    public func suspend() async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Check fault injection before operation
        try checkFaultInjection(for: "suspend")
        
        // Log command
        sessionLogger?.transitionTo(.commandPending, reason: "suspend")
        sessionLogger?.logCommandSent(command: "SUSPEND")
        
        let previousState = pod.deliveryState.rawValue
        pod.deliveryState = .suspended
        pod.lastTempBasal = nil
        podState = pod
        
        sessionLogger?.logDeliveryStateChange(from: previousState, to: pod.deliveryState.rawValue, reason: "Delivery suspended")
        sessionLogger?.logCommandResponse(command: "SUSPEND", success: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "suspend success")
        
        updateStatus()
        await auditLog?.record(.suspend)
        PumpLogger.delivery.deliverySuspended()
    }
    
    public func resume() async throws {
        guard var pod = podState else {
            throw PumpError.noPodPaired
        }
        
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Check fault injection before operation
        try checkFaultInjection(for: "resume")
        
        guard pod.deliveryState == .suspended else {
            return // Already running
        }
        
        // Log command
        sessionLogger?.transitionTo(.commandPending, reason: "resume")
        sessionLogger?.logCommandSent(command: "RESUME")
        
        let previousState = pod.deliveryState.rawValue
        pod.deliveryState = .basalRunning
        podState = pod
        
        sessionLogger?.logDeliveryStateChange(from: previousState, to: pod.deliveryState.rawValue, reason: "Delivery resumed")
        sessionLogger?.logCommandResponse(command: "RESUME", success: true)
        sessionLogger?.transitionTo(.commandComplete, reason: "resume success")
        
        updateStatus()
        await auditLog?.record(.resume)
        PumpLogger.delivery.deliveryResumed()
    }
    
    // MARK: - Private
    
    private func updateStatus() {
        guard let pod = podState else {
            status = PumpStatus(connectionState: .disconnected)
            onStatusChanged?(status)
            return
        }
        
        let connectionState: PumpConnectionState
        switch pod.deliveryState {
        case .suspended:
            connectionState = isConnected ? .suspended : .disconnected
        case .faulted, .deactivated:
            connectionState = .error
        default:
            connectionState = isConnected ? .connected : .disconnected
        }
        
        status = PumpStatus(
            connectionState: connectionState,
            reservoirLevel: pod.reservoirLevel,
            batteryLevel: nil, // DASH pods don't have accessible battery
            insulinOnBoard: cachedIOB,
            lastDelivery: Date()
        )
        onStatusChanged?(status)
    }
}
