// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpManager.swift
// T1Pal Mobile
//
// Pump driver abstraction
// Requirements: REQ-AID-001

import Foundation
import T1PalCore
import NightscoutKit
import BLEKit

/// Pump connection state
public enum PumpConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case suspended
    case error
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension PumpConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected, .suspended: return .connected
        case .error: return .error
        }
    }
}

/// Pump type
///
/// - Important: This enum is **non-frozen** and may gain new cases in future versions.
///   Switch statements should either:
///   1. Handle all cases exhaustively (recommended for core logic), or
///   2. Use `@unknown default` to future-proof against new cases
///
/// Requirements: REQ-AID-001
/// Trace: CODE-QUALITY-001 — Enum extension policy documented
public enum PumpType: String, Codable, Sendable {
    case omnipodEros
    case omnipodDash
    case danaRS
    case danaI
    case medtronic
    case tandemX2
    case simulation
}

/// Pump status
public struct PumpStatus: Sendable {
    public let connectionState: PumpConnectionState
    public let reservoirLevel: Double?  // Units
    public let batteryLevel: Double?    // 0-1
    public let insulinOnBoard: Double   // Units
    public let lastDelivery: Date?
    
    public init(
        connectionState: PumpConnectionState = .disconnected,
        reservoirLevel: Double? = nil,
        batteryLevel: Double? = nil,
        insulinOnBoard: Double = 0,
        lastDelivery: Date? = nil
    ) {
        self.connectionState = connectionState
        self.reservoirLevel = reservoirLevel
        self.batteryLevel = batteryLevel
        self.insulinOnBoard = insulinOnBoard
        self.lastDelivery = lastDelivery
    }
}

/// Pump error types
public enum PumpError: Error, Sendable, Equatable, LocalizedError {
    case connectionFailed
    case communicationError
    case deliveryFailed
    case suspended
    case reservoirEmpty
    case occluded
    case expired
    case notConnected
    case noSession
    case exceedsMaxBasal
    case exceedsMaxBolus
    case noPodPaired
    case alreadyActivated
    case pumpFaulted
    case insufficientReservoir
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to pump"
        case .communicationError:
            return "Pump communication error"
        case .deliveryFailed:
            return "Insulin delivery failed"
        case .suspended:
            return "Pump is suspended"
        case .reservoirEmpty:
            return "Pump reservoir is empty"
        case .occluded:
            return "Pump infusion site may be occluded"
        case .expired:
            return "Pump or pod has expired"
        case .notConnected:
            return "Pump is not connected"
        case .noSession:
            return "No active session with pump relay device"
        case .exceedsMaxBasal:
            return "Basal rate exceeds maximum limit"
        case .exceedsMaxBolus:
            return "Bolus amount exceeds maximum limit"
        case .noPodPaired:
            return "No pod is currently paired"
        case .alreadyActivated:
            return "Pod is already activated"
        case .pumpFaulted:
            return "Pump has faulted and requires attention"
        case .insufficientReservoir:
            return "Insufficient insulin in reservoir"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance (PROD-HARDEN-033)

extension PumpError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .pump }
    
    public var code: String {
        switch self {
        case .connectionFailed: return "CONNECTION_FAILED"
        case .communicationError: return "COMM_ERROR"
        case .deliveryFailed: return "DELIVERY_FAILED"
        case .suspended: return "SUSPENDED"
        case .reservoirEmpty: return "RESERVOIR_EMPTY"
        case .occluded: return "OCCLUDED"
        case .expired: return "EXPIRED"
        case .notConnected: return "NOT_CONNECTED"
        case .noSession: return "NO_SESSION"
        case .exceedsMaxBasal: return "EXCEEDS_MAX_BASAL"
        case .exceedsMaxBolus: return "EXCEEDS_MAX_BOLUS"
        case .noPodPaired: return "NO_POD_PAIRED"
        case .alreadyActivated: return "ALREADY_ACTIVATED"
        case .pumpFaulted: return "PUMP_FAULTED"
        case .insufficientReservoir: return "INSUFFICIENT_RESERVOIR"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .pumpFaulted, .occluded:
            return .critical
        case .reservoirEmpty, .expired, .insufficientReservoir:
            return .critical
        case .suspended:
            return .warning
        case .exceedsMaxBasal, .exceedsMaxBolus:
            return .warning
        default:
            return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .connectionFailed, .notConnected, .noSession:
            return .reconnect
        case .communicationError:
            return .retry
        case .pumpFaulted, .occluded:
            return .checkDevice
        case .reservoirEmpty, .expired, .insufficientReservoir:
            return .none  // Requires physical intervention
        case .suspended:
            return .none  // User must resume
        case .exceedsMaxBasal, .exceedsMaxBolus:
            return .none  // Safety limit
        default:
            return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Pump error"
    }
}

// MARK: - Bolus Delivery Architecture (BOLUS-001, BOLUS-002)

/// Reason for bolus cancellation
/// Trace: BOLUS-001
public enum BolusCancelReason: String, Sendable {
    case userRequested
    case pumpDisconnected
    case pumpFaulted
    case occlusionDetected
    case lowReservoir
    case timeout
}

/// Bolus delivery state machine (BOLUS-001)
/// Models asynchronous insulin delivery: pump takes time to deliver (e.g., 2U takes ~40s)
/// Trace: BOLUS-001, REQ-AID-001
public enum BolusDeliveryState: Sendable, Equatable {
    /// No bolus in progress
    case idle
    
    /// Bolus command sent, waiting for pump acknowledgment
    case initiating(requested: Double)
    
    /// Bolus actively delivering (pump sending progress notifications)
    case delivering(requested: Double, delivered: Double, remaining: Double)
    
    /// Bolus delivery finishing (final pulses)
    case completing(total: Double)
    
    /// Bolus successfully completed
    case completed(total: Double, timestamp: Date)
    
    /// Bolus was cancelled before completion
    case cancelled(delivered: Double, reason: BolusCancelReason)
    
    /// Bolus failed during delivery
    case failed(delivered: Double, error: PumpError)
    
    /// Is a bolus currently in progress?
    public var isActive: Bool {
        switch self {
        case .initiating, .delivering, .completing:
            return true
        case .idle, .completed, .cancelled, .failed:
            return false
        }
    }
    
    /// Amount delivered so far (0 if idle)
    public var deliveredUnits: Double {
        switch self {
        case .idle, .initiating:
            return 0
        case .delivering(_, let delivered, _):
            return delivered
        case .completing(let total), .completed(let total, _):
            return total
        case .cancelled(let delivered, _), .failed(let delivered, _):
            return delivered
        }
    }
    
    /// Amount remaining to deliver (0 if not active)
    public var remainingUnits: Double {
        switch self {
        case .idle, .completed, .cancelled, .failed, .completing:
            return 0
        case .initiating(let requested):
            return requested
        case .delivering(_, _, let remaining):
            return remaining
        }
    }
    
    /// Progress as percentage (0-1, nil if not active)
    public var progress: Double? {
        switch self {
        case .idle, .completed, .cancelled, .failed:
            return nil
        case .initiating:
            return 0
        case .delivering(let requested, let delivered, _):
            return requested > 0 ? delivered / requested : 0
        case .completing:
            return 1.0
        }
    }
}

/// Bolus progress delegate protocol (BOLUS-002)
/// Receives notifications about bolus delivery progress
/// Trace: BOLUS-002, REQ-AID-001
public protocol BolusProgressDelegate: AnyObject, Sendable {
    /// Called when bolus delivery starts
    func bolusDidStart(id: UUID, requested: Double)
    
    /// Called periodically during delivery with progress updates
    func bolusDidProgress(id: UUID, delivered: Double, remaining: Double, percentComplete: Double)
    
    /// Called when bolus completes successfully
    func bolusDidComplete(id: UUID, delivered: Double)
    
    /// Called if bolus fails during delivery
    func bolusDidFail(id: UUID, delivered: Double, error: PumpError)
    
    /// Called if bolus is cancelled before completion
    func bolusWasCancelled(id: UUID, delivered: Double, reason: BolusCancelReason)
}

/// Default implementations for optional delegate methods
public extension BolusProgressDelegate {
    func bolusDidProgress(id: UUID, delivered: Double, remaining: Double, percentComplete: Double) {}
}

/// Active bolus delivery info (BOLUS-003 prep)
/// Trace: BOLUS-001
public struct ActiveBolusDelivery: Sendable {
    public let id: UUID
    public let startTime: Date
    public let requestedUnits: Double
    public var state: BolusDeliveryState
    
    public init(id: UUID = UUID(), startTime: Date = Date(), requestedUnits: Double) {
        self.id = id
        self.startTime = startTime
        self.requestedUnits = requestedUnits
        self.state = .initiating(requested: requestedUnits)
    }
    
    /// Elapsed time since bolus started
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Estimated remaining time based on delivery rate
    public func estimatedRemainingTime(deliveryRate: Double = 1.5) -> TimeInterval? {
        guard case .delivering(_, _, let remaining) = state else { return nil }
        // Default: 1.5 U/min = 0.025 U/s
        return remaining / (deliveryRate / 60.0)
    }
}

/// Protocol for pump drivers
/// Requirements: REQ-AID-001
public protocol PumpManagerProtocol: Actor {
    nonisolated var displayName: String { get }
    nonisolated var pumpType: PumpType { get }
    var status: PumpStatus { get }
    
    func connect() async throws
    func disconnect() async
    
    func setTempBasal(rate: Double, duration: TimeInterval) async throws
    func cancelTempBasal() async throws
    func deliverBolus(units: Double) async throws
    func cancelBolus() async throws  // RESEARCH-AID-005
    func suspend() async throws
    func resume() async throws
    
    var onStatusChanged: (@Sendable (PumpStatus) -> Void)? { get set }
    var onError: (@Sendable (PumpError) -> Void)? { get set }
    
    // MARK: - Bolus Progress Tracking (BOLUS-003)
    
    /// Current active bolus delivery, if any
    /// Returns nil when no bolus is in progress
    var activeBolusDelivery: ActiveBolusDelivery? { get }
    
    /// Delegate for bolus progress notifications
    var bolusProgressDelegate: (any BolusProgressDelegate)? { get set }
    
    // MARK: - Nightscout Sync (BOLUS-008)
    
    /// Delivery reporter for Nightscout sync
    /// Reports completed and cancelled boluses to Nightscout
    var deliveryReporter: DeliveryReporter? { get set }
}

// MARK: - Unified Callback Naming (ARCH-001)

/// Unified callback aliases for cross-protocol consistency
/// Trace: ARCH-001 — Service protocol naming unification
public extension PumpManagerProtocol {
    /// Unified alias for onStatusChanged (matches CGM onDataReceived pattern)
    /// PumpStatus includes both data (reservoir, battery) and state (connection)
    var onDataReceived: (@Sendable (PumpStatus) -> Void)? {
        get { onStatusChanged }
        set { onStatusChanged = newValue }
    }
    
    /// Unified alias for onStatusChanged (matches CGM onStateChanged pattern)
    var onStateChanged: (@Sendable (PumpStatus) -> Void)? {
        get { onStatusChanged }
        set { onStatusChanged = newValue }
    }
}

// MARK: - Pump Profile Sync Protocol (CRIT-PROFILE-015)

/// Protocol for pumps that support basal schedule programming
/// Trace: CRIT-PROFILE-015 — Profile changes sync to pump
public protocol PumpProfileSyncable: PumpManagerProtocol {
    /// Write basal schedule to pump
    /// - Parameter profile: TherapyProfile containing basal rates
    /// - Throws: PumpError if write fails
    func syncBasalSchedule(from profile: TherapyProfile) async throws
    
    /// Read current basal schedule from pump
    /// - Returns: BasalRate array representing pump's current schedule
    func readBasalSchedule() async throws -> [BasalRate]
    
    /// Whether the pump is ready to receive profile sync
    var canSyncProfile: Bool { get async }
}

/// Default implementation for canSyncProfile
public extension PumpProfileSyncable {
    var canSyncProfile: Bool {
        get async {
            status.connectionState == .connected
        }
    }
}

/// Simulation pump for demo mode
/// Requirements: REQ-DEMO-004
public actor SimulationPump: PumpManagerProtocol {
    public nonisolated let displayName = "Simulation Pump"
    public nonisolated let pumpType = PumpType.simulation
    
    public private(set) var status: PumpStatus
    
    public var onStatusChanged: (@Sendable (PumpStatus) -> Void)?
    public var onError: (@Sendable (PumpError) -> Void)?
    
    // BOLUS-003: Bolus progress tracking
    public private(set) var activeBolusDelivery: ActiveBolusDelivery?
    public var bolusProgressDelegate: (any BolusProgressDelegate)?
    
    // BOLUS-008: Nightscout sync
    public var deliveryReporter: DeliveryReporter?
    
    private var currentTempBasal: (rate: Double, endTime: Date)?
    private var totalDelivered: Double = 0
    
    /// Optional audit log for command recording
    public let auditLog: PumpAuditLog?
    
    /// Delivery tracker for IOB calculation
    private let iobTracker = IOBTracker()
    
    // WIRE-013: Simulation mode for test acceleration
    private var simulationMode: SimulationMode = .demo
    
    public init(auditLog: PumpAuditLog? = nil) {
        self.auditLog = auditLog
        status = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: 200,
            batteryLevel: 1.0,
            insulinOnBoard: 0
        )
    }
    
    // WIRE-013: Test mode control
    public func setSimulationMode(_ mode: SimulationMode) {
        simulationMode = mode
    }
    
    public func enableTestMode() {
        setSimulationMode(.test)
    }
    
    private func simulationDelay(nanoseconds: UInt64) async throws {
        try await simulationMode.delay(nanoseconds: nanoseconds)
    }
    
    public func connect() async throws {
        // WIRE-013: Use simulationDelay
        try await simulationDelay(nanoseconds: 500_000_000)
        
        status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: status.reservoirLevel,
            batteryLevel: status.batteryLevel,
            insulinOnBoard: status.insulinOnBoard,
            lastDelivery: status.lastDelivery
        )
        onStatusChanged?(status)
        await auditLog?.record(AuditCommand.connect)
    }
    
    public func disconnect() async {
        status = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: status.reservoirLevel,
            batteryLevel: status.batteryLevel,
            insulinOnBoard: status.insulinOnBoard,
            lastDelivery: status.lastDelivery
        )
        onStatusChanged?(status)
        await auditLog?.record(AuditCommand.disconnect)
    }
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        guard status.connectionState == .connected else {
            await auditLog?.recordFailure(
                AuditCommand.setTempBasal(rate: rate, durationMinutes: duration / 60),
                error: "Not connected"
            )
            throw PumpError.connectionFailed
        }
        
        currentTempBasal = (rate: rate, endTime: Date().addingTimeInterval(duration))
        await auditLog?.record(AuditCommand.setTempBasal(rate: rate, durationMinutes: duration / 60))
        
        // Log the temp basal
        PumpLogger.basal.info("SimulationPump: Set temp basal \(rate) U/hr for \(duration/60) min")
    }
    
    public func cancelTempBasal() async throws {
        currentTempBasal = nil
        await auditLog?.record(AuditCommand.cancelTempBasal)
        PumpLogger.basal.info("SimulationPump: Cancelled temp basal")
    }
    
    public func deliverBolus(units: Double) async throws {
        guard status.connectionState == .connected else {
            await auditLog?.recordFailure(AuditCommand.deliverBolus(units: units), error: "Not connected")
            throw PumpError.connectionFailed
        }
        
        guard let reservoir = status.reservoirLevel, reservoir >= units else {
            await auditLog?.recordFailure(AuditCommand.deliverBolus(units: units), error: "Reservoir empty")
            throw PumpError.reservoirEmpty
        }
        
        // WIRE-013: Simulate delivery time using simulationDelay
        let deliveryTime = UInt64(units * 10) * 1_000_000_000
        try await simulationDelay(nanoseconds: deliveryTime)
        
        totalDelivered += units
        
        // Track delivery for IOB calculation
        await iobTracker.recordBolus(units: units)
        let currentIOB = await iobTracker.currentIOB()
        
        // BOLUS-008: Queue for Nightscout sync
        if let reporter = deliveryReporter {
            let event = DeliveryEvent(
                deliveryType: .bolus,
                units: units,
                reason: "Bolus delivery"
            )
            await reporter.queue(event)
        }
        
        status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: reservoir - units,
            batteryLevel: status.batteryLevel,
            insulinOnBoard: currentIOB,
            lastDelivery: Date()
        )
        onStatusChanged?(status)
        await auditLog?.record(AuditCommand.deliverBolus(units: units))
        
        PumpLogger.bolus.info("SimulationPump: Delivered \(units)U bolus")
    }
    
    // RESEARCH-AID-005: Cancel in-progress bolus delivery
    public func cancelBolus() async throws {
        // In simulation, bolus is instant after delay, so this is a no-op
        // Real pump implementations would send cancel command
        PumpLogger.bolus.debug("SimulationPump: Cancel bolus requested (no-op in simulation)")
    }
    
    public func suspend() async throws {
        status = PumpStatus(
            connectionState: .suspended,
            reservoirLevel: status.reservoirLevel,
            batteryLevel: status.batteryLevel,
            insulinOnBoard: status.insulinOnBoard,
            lastDelivery: status.lastDelivery
        )
        onStatusChanged?(status)
        await auditLog?.record(AuditCommand.suspend)
    }
    
    public func resume() async throws {
        status = PumpStatus(
            connectionState: .connected,
            reservoirLevel: status.reservoirLevel,
            batteryLevel: status.batteryLevel,
            insulinOnBoard: status.insulinOnBoard,
            lastDelivery: status.lastDelivery
        )
        onStatusChanged?(status)
        await auditLog?.record(AuditCommand.resume)
    }
    
    /// CRIT-BOLUS-005: Set delivery reporter for Nightscout sync
    public func setDeliveryReporter(_ reporter: DeliveryReporter?) {
        self.deliveryReporter = reporter
    }
}
