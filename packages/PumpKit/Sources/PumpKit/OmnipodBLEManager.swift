// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodBLEManager.swift
// PumpKit
//
// BLE connection manager for Omnipod DASH pods.
// Handles pod discovery, pairing, and session management.
// Trace: PUMP-OMNI-004, PRD-005
//
// Usage:
//   let manager = OmnipodBLEManager()
//   try await manager.startScanning()
//   try await manager.connect(to: pod)
//   let status = try await manager.readStatus()

import Foundation
import BLEKit

// MARK: - Pod Discovery

/// Represents a discovered Omnipod DASH pod
public struct DiscoveredPod: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let rssi: Int
    public let lotNumber: String?
    public let sequenceNumber: String?
    public let discoveredAt: Date
    
    public init(
        id: String,
        name: String,
        rssi: Int,
        lotNumber: String? = nil,
        sequenceNumber: String? = nil
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.lotNumber = lotNumber
        self.sequenceNumber = sequenceNumber
        self.discoveredAt = Date()
    }
    
    /// Derive pod ID from lot and sequence (if available)
    public var derivedPodId: String? {
        guard let lot = lotNumber, let seq = sequenceNumber else { return nil }
        return "\(lot)-\(seq)"
    }
    
    public var displayName: String {
        if name.isEmpty {
            return "DASH Pod (\(id.prefix(8)))"
        }
        return name
    }
    
    /// Check if this looks like a DASH pod
    public var isDashPod: Bool {
        name.hasPrefix(OmnipodBLEConstants.advertisementPrefix) ||
        name.contains("Omnipod") ||
        name.contains("DASH")
    }
}

// MARK: - Connection State

/// BLE connection state for Omnipod DASH
public enum OmnipodConnectionState: String, Sendable, Codable {
    case disconnected
    case scanning
    case connecting
    case pairing          // Key exchange in progress
    case paired           // Keys established
    case ready            // Ready for commands
    case error
    
    public var isConnected: Bool {
        switch self {
        case .paired, .ready:
            return true
        default:
            return false
        }
    }
    
    public var canSendCommands: Bool {
        self == .ready
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension OmnipodConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .scanning: return .scanning
        case .connecting, .pairing: return .connecting
        case .paired, .ready: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Session State

/// Omnipod DASH session state
public struct OmnipodSession: Sendable {
    public let podId: String
    public let sessionId: String
    public var messageSequence: UInt32
    public let establishedAt: Date
    public var lastActivity: Date
    
    public init(podId: String) {
        self.podId = podId
        self.sessionId = UUID().uuidString
        self.messageSequence = 0
        self.establishedAt = Date()
        self.lastActivity = Date()
    }
    
    public mutating func nextSequence() -> UInt32 {
        messageSequence += 1
        lastActivity = Date()
        return messageSequence
    }
    
    public var isExpired: Bool {
        Date().timeIntervalSince(lastActivity) > OmnipodBLEConstants.sessionIdleTimeoutSeconds
    }
}

// MARK: - Omnipod BLE Manager

/// Manages BLE connection to Omnipod DASH pods
public actor OmnipodBLEManager {
    
    // MARK: - State
    
    /// Current connection state
    public private(set) var state: OmnipodConnectionState = .disconnected
    
    /// Currently connected pod
    public private(set) var connectedPod: DiscoveredPod?
    
    /// Discovered pods from scanning
    public private(set) var discoveredPods: [DiscoveredPod] = []
    
    /// Active session
    public private(set) var session: OmnipodSession?
    
    /// Last error
    public private(set) var lastError: OmnipodBLEError?
    
    // MARK: - Configuration
    
    /// Timeout for BLE connection
    public var connectionTimeout: TimeInterval = OmnipodBLEConstants.connectionTimeoutSeconds
    
    /// Timeout for commands
    public var commandTimeout: TimeInterval = OmnipodBLEConstants.commandTimeoutSeconds
    
    /// Retry count for failed commands
    public var retryCount: Int = 3
    
    // WIRE-004: Fault injection support
    public var faultInjector: PumpFaultInjector?
    
    // WIRE-004: Metrics support
    private let metrics: PumpMetrics
    
    // MARK: - Private State
    
    private var observers: [UUID: (OmnipodConnectionState) -> Void] = [:]
    private var scanTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(faultInjector: PumpFaultInjector? = nil, metrics: PumpMetrics = .shared) {
        self.faultInjector = faultInjector
        self.metrics = metrics
    }
    
    // MARK: - Factory Methods (PUMP-PG-006)
    
    /// Create manager in demo mode for playground testing
    /// Trace: PUMP-PG-006
    public static func forDemo() -> OmnipodBLEManager {
        OmnipodBLEManager()
    }
    
    /// Create manager for unit testing
    public static func forTesting() -> OmnipodBLEManager {
        OmnipodBLEManager()
    }
    
    /// Set state directly for testing/demo (PUMP-PG-006)
    public func setTestState(_ newState: OmnipodConnectionState) {
        state = newState
        notifyObservers()
    }
    
    /// Resume session for demo mode (PUMP-PG-006)
    public func resumeSession(podId: String) {
        session = OmnipodSession(podId: podId)
        state = .ready
        notifyObservers()
    }
    
    // MARK: - Scanning
    
    /// Start scanning for DASH pods
    public func startScanning() async {
        guard state == .disconnected else { return }
        
        state = .scanning
        discoveredPods = []
        notifyObservers()
        
        PumpLogger.connection.info("Starting Omnipod DASH scan")
        
        // Simulate pod discovery
        scanTask = Task {
            
            if !Task.isCancelled {
                let simPod = DiscoveredPod(
                    id: "sim-dash-001",
                    name: "TWI BOARD 12345",
                    rssi: -55,
                    lotNumber: "L12345",
                    sequenceNumber: "67890"
                )
                addDiscoveredPod(simPod)
            }
        }
    }
    
    /// Stop scanning
    public func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        
        if state == .scanning {
            state = .disconnected
            notifyObservers()
        }
        
        PumpLogger.connection.info("Stopped Omnipod DASH scan")
    }
    
    private func addDiscoveredPod(_ pod: DiscoveredPod) {
        // Update or add pod
        if let index = discoveredPods.firstIndex(where: { $0.id == pod.id }) {
            discoveredPods[index] = pod
        } else {
            discoveredPods.append(pod)
        }
        
        PumpLogger.connection.info("Discovered DASH pod: \(pod.displayName)")
    }
    
    // MARK: - Connection
    
    /// Connect to a DASH pod
    /// Trace: WIRE-004 (fault injection + metrics)
    public func connect(to pod: DiscoveredPod) async throws {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "connect")
            if case .injected(let fault) = result {
                await metrics.recordCommand("connect", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .disconnected || state == .scanning else {
            throw OmnipodBLEError.alreadyConnected
        }
        
        stopScanning()
        
        state = .connecting
        notifyObservers()
        
        PumpLogger.connection.info("Connecting to DASH pod: \(pod.displayName)")
        
        
        try Task.checkCancellation()
        
        connectedPod = pod
        state = .pairing
        notifyObservers()
        
        // Simulate pairing/key exchange
        try await performPairing(pod: pod)
        
        // WIRE-004: Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("connect", duration: duration, success: true, pumpType: .omnipodDash)
    }
    
    /// Perform ECC key exchange for pairing
    private func performPairing(pod: DiscoveredPod) async throws {
        PumpLogger.connection.info("Pairing with DASH pod...")
        
        
        // Create session
        session = OmnipodSession(podId: pod.derivedPodId ?? pod.id)
        
        state = .paired
        notifyObservers()
        
        
        state = .ready
        notifyObservers()
        
        PumpLogger.connection.info("DASH pod paired and ready")
    }
    
    /// Disconnect from current pod
    public func disconnect() async {
        guard let pod = connectedPod else { return }
        
        PumpLogger.connection.info("Disconnecting from DASH pod: \(pod.displayName)")
        
        connectedPod = nil
        session = nil
        state = .disconnected
        notifyObservers()
    }
    
    // MARK: - Commands
    
    /// Send a command to the pod
    /// Trace: WIRE-004 (fault injection + metrics)
    public func sendCommand(_ data: Data) async throws -> Data {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "omnipod.command")
            if case .injected(let fault) = result {
                await metrics.recordCommand("omnipod.command", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        guard var currentSession = session else {
            throw OmnipodBLEError.noSession
        }
        
        // Get next sequence number
        let seq = currentSession.nextSequence()
        session = currentSession
        
        PumpLogger.protocol_.info("Sending command (seq: \(seq))")
        
        
        // WIRE-004: Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("omnipod.command", duration: duration, success: true, pumpType: .omnipodDash)
        
        // Simulate response
        let response = Data([0x1D, UInt8(seq & 0xFF), 0x00, 0x00])
        
        return response
    }
    
    /// Read pod status
    public func readStatus() async throws -> OmnipodStatusResponse {
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        let statusCommand = Data([0x0E]) // Status command opcode
        _ = try await sendCommand(statusCommand)
        
        // Parse response (simulated)
        return OmnipodStatusResponse(
            deliveryStatus: .basalRunning,
            reservoirLevel: 150.0,
            minutesSinceActivation: 1440,
            alertsActive: []
        )
    }
    
    // MARK: - Observers
    
    /// Add observer for state changes
    @discardableResult
    public func addObserver(_ handler: @escaping (OmnipodConnectionState) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers() {
        for handler in observers.values {
            handler(state)
        }
    }
    
    // MARK: - Fault Handling (WIRE-004)
    
    /// Map fault type to Omnipod error
    private func mapFaultToError(_ fault: PumpFaultType) -> Error {
        switch fault {
        case .connectionDrop, .connectionTimeout:
            return OmnipodBLEError.podNotFound
        case .communicationError, .bleDisconnectMidCommand:
            return OmnipodBLEError.communicationFailed
        case .packetCorruption:
            return OmnipodBLEError.invalidResponse
        default:
            return OmnipodBLEError.communicationFailed
        }
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic info
    public func diagnosticInfo() -> OmnipodBLEDiagnostics {
        OmnipodBLEDiagnostics(
            state: state,
            connectedPod: connectedPod,
            session: session,
            discoveredPodCount: discoveredPods.count
        )
    }
    
    // MARK: - Simulation Support
    
    /// Test nonce for simulation
    private var testNonce: UInt32 = 0x12345678
    
    /// Test mode for unit testing
    public var isTestMode: Bool = false
    
    /// Set test nonce for deterministic command generation
    public func setTestNonce(_ nonce: UInt32) {
        testNonce = nonce
        isTestMode = true
    }
    
    /// Get current nonce (uses test or generates)
    private func currentNonce() -> UInt32 {
        if isTestMode {
            return testNonce
        }
        return UInt32.random(in: 0...UInt32.max)
    }
    
    // MARK: - Bolus Delivery (PUMP-PG-004)
    
    /// Deliver a bolus
    /// Trace: PUMP-PG-004, PRD-005
    /// - Parameters:
    ///   - units: Bolus amount in units (0.05 to 30.0)
    ///   - acknowledgementBeep: Play beep when starting
    ///   - completionBeep: Play beep when complete
    /// - Returns: DASHBolusResult with estimated duration
    public func deliverBolus(
        units: Double,
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = true
    ) async throws -> DASHBolusResult {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "omnipod.bolus")
            if case .injected(let fault) = result {
                await metrics.recordCommand("omnipod.bolus", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        // Validate bolus amount
        guard units >= DASHPodConstants.minBolusUnits else {
            throw OmnipodBLEError.invalidBolusAmount(units, reason: "Below minimum \(DASHPodConstants.minBolusUnits)U")
        }
        guard units <= DASHPodConstants.maxBolusUnits else {
            throw OmnipodBLEError.invalidBolusAmount(units, reason: "Above maximum \(DASHPodConstants.maxBolusUnits)U")
        }
        
        // Round to pulse size (0.05U)
        let roundedUnits = (units / DASHPodConstants.pulseSize).rounded() * DASHPodConstants.pulseSize
        
        PumpLogger.protocol_.info("DASH: Delivering bolus of \(roundedUnits)U")
        
        // Build commands
        let nonce = currentNonce()
        let scheduleCommand = DASHSetInsulinScheduleCommand.bolus(
            nonce: nonce,
            units: roundedUnits
        )
        let extraCommand = DASHBolusExtraCommand(
            units: roundedUnits,
            acknowledgementBeep: acknowledgementBeep,
            completionBeep: completionBeep
        )
        
        // Send SetInsulinSchedule command
        _ = try await sendCommand(scheduleCommand.encode())
        
        // Send BolusExtra command
        _ = try await sendCommand(extraCommand.encode())
        
        // Calculate duration
        let pulses = Int(roundedUnits / DASHPodConstants.pulseSize)
        let duration = Double(pulses) * DASHPodConstants.secondsPerBolusPulse
        
        // WIRE-004: Record metrics
        let elapsed = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("omnipod.bolus", duration: elapsed, success: true, pumpType: .omnipodDash)
        
        PumpLogger.protocol_.info("DASH: Bolus started, \(pulses) pulses, ~\(Int(duration))s duration")
        
        return DASHBolusResult(
            units: roundedUnits,
            pulses: pulses,
            estimatedDuration: duration,
            startTime: startTime
        )
    }
    
    /// Cancel an in-progress bolus
    /// Trace: PUMP-PG-004
    public func cancelBolus() async throws {
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        let nonce = currentNonce()
        let cancelCommand = DASHCancelDeliveryCommand(
            nonce: nonce,
            deliveryType: .bolus
        )
        
        _ = try await sendCommand(cancelCommand.encode())
        
        PumpLogger.protocol_.info("DASH: Bolus cancelled")
    }
    
    // MARK: - Temp Basal Delivery (PUMP-PG-005)
    
    /// Set a temporary basal rate
    /// Trace: PUMP-PG-005, PRD-005
    /// - Parameters:
    ///   - rate: Temp basal rate in U/hr (0.0 to 30.0)
    ///   - duration: Duration in minutes (30 to 720, must be multiple of 30)
    ///   - acknowledgementBeep: Play beep when starting
    ///   - completionBeep: Play beep when complete
    /// - Returns: DASHTempBasalResult with scheduled info
    public func setTempBasal(
        rate: Double,
        duration: TimeInterval,
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = false
    ) async throws -> DASHTempBasalResult {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "omnipod.tempbasal")
            if case .injected(let fault) = result {
                await metrics.recordCommand("omnipod.tempbasal", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        // Validate rate
        guard rate >= DASHPodConstants.minTempBasalRate else {
            throw OmnipodBLEError.invalidTempBasal(rate: rate, duration: duration, reason: "Rate below minimum \(DASHPodConstants.minTempBasalRate)U/hr")
        }
        guard rate <= DASHPodConstants.maxTempBasalRate else {
            throw OmnipodBLEError.invalidTempBasal(rate: rate, duration: duration, reason: "Rate above maximum \(DASHPodConstants.maxTempBasalRate)U/hr")
        }
        
        // Validate duration
        guard duration >= DASHPodConstants.minTempBasalDuration else {
            throw OmnipodBLEError.invalidTempBasal(rate: rate, duration: duration, reason: "Duration below minimum 30 minutes")
        }
        guard duration <= DASHPodConstants.maxTempBasalDuration else {
            throw OmnipodBLEError.invalidTempBasal(rate: rate, duration: duration, reason: "Duration above maximum 12 hours")
        }
        
        // Round rate to pulse size (0.05U/hr)
        let roundedRate = (rate / DASHPodConstants.pulseSize).rounded() * DASHPodConstants.pulseSize
        
        // Round duration to 30-minute segments
        let roundedDuration = (duration / DASHPodConstants.tempBasalSegmentDuration).rounded() * DASHPodConstants.tempBasalSegmentDuration
        
        PumpLogger.protocol_.info("DASH: Setting temp basal \(roundedRate)U/hr for \(Int(roundedDuration/60))min")
        
        // Build commands
        let nonce = currentNonce()
        let scheduleCommand = DASHTempBasalScheduleCommand(
            nonce: nonce,
            rate: roundedRate,
            duration: roundedDuration
        )
        let extraCommand = DASHTempBasalExtraCommand(
            rate: roundedRate,
            duration: roundedDuration,
            acknowledgementBeep: acknowledgementBeep,
            completionBeep: completionBeep
        )
        
        // Send SetInsulinSchedule command
        _ = try await sendCommand(scheduleCommand.encode())
        
        // Send TempBasalExtra command
        _ = try await sendCommand(extraCommand.encode())
        
        // WIRE-004: Record metrics
        let elapsed = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("omnipod.tempbasal", duration: elapsed, success: true, pumpType: .omnipodDash)
        
        PumpLogger.protocol_.info("DASH: Temp basal started")
        
        return DASHTempBasalResult(
            rate: roundedRate,
            duration: roundedDuration,
            startTime: startTime
        )
    }
    
    /// Cancel an active temp basal
    /// Trace: PUMP-PG-005
    public func cancelTempBasal() async throws {
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        let nonce = currentNonce()
        let cancelCommand = DASHCancelDeliveryCommand(
            nonce: nonce,
            deliveryType: .tempBasal
        )
        
        _ = try await sendCommand(cancelCommand.encode())
        
        PumpLogger.protocol_.info("DASH: Temp basal cancelled")
    }
    
    // MARK: - Suspend/Resume Delivery (PUMP-DELIVERY-003)
    
    /// Suspend all insulin delivery (basal, temp basal, bolus)
    /// Trace: PUMP-DELIVERY-003, PUMP-PG-005
    /// - Returns: The time suspension started
    public func suspendDelivery() async throws -> Date {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "omnipod.suspend")
            if case .injected(let fault) = result {
                await metrics.recordCommand("omnipod.suspend", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        PumpLogger.protocol_.info("DASH: Suspending all delivery")
        
        let nonce = currentNonce()
        let cancelCommand = DASHCancelDeliveryCommand(
            nonce: nonce,
            deliveryType: .all,  // 0x07: Cancel basal + temp + bolus
            beepType: 0x00       // No beep
        )
        
        _ = try await sendCommand(cancelCommand.encode())
        
        // WIRE-004: Record metrics
        let elapsed = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("omnipod.suspend", duration: elapsed, success: true, pumpType: .omnipodDash)
        
        PumpLogger.protocol_.info("DASH: Delivery suspended")
        
        return startTime
    }
    
    /// Resume insulin delivery with a scheduled basal rate
    /// Trace: PUMP-DELIVERY-003, PUMP-PG-005
    /// - Parameters:
    ///   - basalRate: The basal rate to resume with (U/hr)
    ///   - acknowledgementBeep: Whether to beep on command acknowledgement
    /// - Returns: The time delivery was resumed
    public func resumeDelivery(
        basalRate: Double,
        acknowledgementBeep: Bool = false
    ) async throws -> Date {
        let startTime = Date()
        
        // WIRE-004: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "omnipod.resume")
            if case .injected(let fault) = result {
                await metrics.recordCommand("omnipod.resume", duration: 0, success: false, pumpType: .omnipodDash)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw OmnipodBLEError.notConnected
        }
        
        // Validate rate
        guard basalRate >= 0 else {
            throw OmnipodBLEError.invalidBasalRate(basalRate, reason: "Rate cannot be negative")
        }
        guard basalRate <= DASHPodConstants.maxBasalRate else {
            throw OmnipodBLEError.invalidBasalRate(basalRate, reason: "Rate above maximum \(DASHPodConstants.maxBasalRate)U/hr")
        }
        
        // Round rate to pulse size (0.05U/hr)
        let roundedRate = (basalRate / DASHPodConstants.pulseSize).rounded() * DASHPodConstants.pulseSize
        
        PumpLogger.protocol_.info("DASH: Resuming delivery at \(roundedRate)U/hr")
        
        // Build SetInsulinSchedule command for basal (type 0x00)
        let nonce = currentNonce()
        let basalCommand = DASHBasalScheduleCommand(
            nonce: nonce,
            rate: roundedRate,
            acknowledgementBeep: acknowledgementBeep
        )
        
        _ = try await sendCommand(basalCommand.encode())
        
        // WIRE-004: Record metrics
        let elapsed = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("omnipod.resume", duration: elapsed, success: true, pumpType: .omnipodDash)
        
        PumpLogger.protocol_.info("DASH: Delivery resumed")
        
        return startTime
    }
}

// MARK: - Status Response

/// Pod status response
public struct OmnipodStatusResponse: Sendable {
    public let deliveryStatus: DashDeliveryState
    public let reservoirLevel: Double
    public let minutesSinceActivation: Int
    public let alertsActive: [DashPodAlert]
    
    public var hoursActive: Double {
        Double(minutesSinceActivation) / 60.0
    }
    
    public var isExpired: Bool {
        hoursActive >= 72.0
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 10.0
    }
}

// MARK: - Diagnostics

/// Diagnostic information about Omnipod BLE connection
public struct OmnipodBLEDiagnostics: Sendable {
    public let state: OmnipodConnectionState
    public let connectedPod: DiscoveredPod?
    public let session: OmnipodSession?
    public let discoveredPodCount: Int
    
    public var description: String {
        var lines: [String] = []
        lines.append("State: \(state.rawValue)")
        if let pod = connectedPod {
            lines.append("Pod: \(pod.displayName)")
            lines.append("RSSI: \(pod.rssi) dBm")
        }
        if let session = session {
            lines.append("Session: \(session.sessionId.prefix(8))")
            lines.append("Sequence: \(session.messageSequence)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

/// Omnipod BLE-specific errors
public enum OmnipodBLEError: Error, Sendable, Equatable {
    case podNotFound
    case alreadyConnected
    case notConnected
    case noSession
    case pairingFailed
    case communicationFailed
    case timeout
    case invalidResponse
    case podFaulted(OmnipodFaultCode)
    case bleNotAvailable
    case bleNotAuthorized
    case invalidBolusAmount(Double, reason: String)
    case invalidTempBasal(rate: Double, duration: TimeInterval, reason: String)
    case invalidBasalRate(Double, reason: String)
}

extension OmnipodBLEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .podNotFound:
            return "DASH pod not found"
        case .alreadyConnected:
            return "Already connected to a pod"
        case .notConnected:
            return "Not connected to pod"
        case .noSession:
            return "No active session"
        case .pairingFailed:
            return "Pod pairing failed"
        case .communicationFailed:
            return "Communication failed"
        case .timeout:
            return "Command timed out"
        case .invalidResponse:
            return "Invalid response from pod"
        case .podFaulted(let code):
            return "Pod faulted: \(code.displayName)"
        case .bleNotAvailable:
            return "Bluetooth is not available"
        case .bleNotAuthorized:
            return "Bluetooth permission not granted"
        case .invalidBolusAmount(let units, let reason):
            return "Invalid bolus \(units)U: \(reason)"
        case .invalidTempBasal(let rate, let duration, let reason):
            return "Invalid temp basal \(rate)U/hr for \(Int(duration/60))min: \(reason)"
        case .invalidBasalRate(let rate, let reason):
            return "Invalid basal rate \(rate)U/hr: \(reason)"
        }
    }
}

// MARK: - DASH Pod Constants (PUMP-PG-004)

/// Constants for DASH pod insulin delivery
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/Pod.swift
public enum DASHPodConstants {
    /// Insulin per motor pulse (0.05U)
    public static let pulseSize: Double = 0.05
    
    /// Pulses per unit of insulin (20)
    public static let pulsesPerUnit: Double = 1 / pulseSize
    
    /// Seconds between pulses during bolus delivery (2s)
    public static let secondsPerBolusPulse: Double = 2.0
    
    /// Bolus delivery rate (0.025 U/s)
    public static let bolusDeliveryRate: Double = pulseSize / secondsPerBolusPulse
    
    /// Minimum bolus amount (1 pulse = 0.05U)
    public static let minBolusUnits: Double = 0.05
    
    /// Maximum bolus amount
    public static let maxBolusUnits: Double = 30.0
    
    /// Minimum temp basal rate (0 U/hr supported on DASH)
    public static let minTempBasalRate: Double = 0.0
    
    /// Maximum temp basal rate
    public static let maxTempBasalRate: Double = 30.0
    
    /// Maximum scheduled basal rate
    public static let maxBasalRate: Double = 30.0
    
    /// Minimum temp basal duration (30 min)
    public static let minTempBasalDuration: TimeInterval = 30 * 60
    
    /// Maximum temp basal duration (12 hours)
    public static let maxTempBasalDuration: TimeInterval = 12 * 60 * 60
    
    /// Temp basal segment duration (30 min)
    public static let tempBasalSegmentDuration: TimeInterval = 30 * 60
    
    /// Max time between pulses for very low rates (5 hours)
    public static let maxTimeBetweenPulses: TimeInterval = 5 * 60 * 60
    
    /// Pod lifetime (72 hours)
    public static let podLifetimeHours: Double = 72.0
    
    /// Reservoir capacity (200U)
    public static let reservoirCapacity: Double = 200.0
}

// MARK: - DASH Bolus Result

/// Result of a DASH bolus command
public struct DASHBolusResult: Sendable, Equatable {
    /// Actual units delivered (rounded to pulse size)
    public let units: Double
    
    /// Number of pulses
    public let pulses: Int
    
    /// Estimated delivery duration in seconds
    public let estimatedDuration: TimeInterval
    
    /// When the bolus was started
    public let startTime: Date
    
    /// Estimated completion time
    public var estimatedCompletionTime: Date {
        startTime.addingTimeInterval(estimatedDuration)
    }
    
    public init(units: Double, pulses: Int, estimatedDuration: TimeInterval, startTime: Date = Date()) {
        self.units = units
        self.pulses = pulses
        self.estimatedDuration = estimatedDuration
        self.startTime = startTime
    }
}

// MARK: - DASH Command Types (PUMP-PG-004)

/// Message block type codes for DASH commands
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/MessageBlock.swift
public enum DASHMessageBlockType: UInt8, Sendable {
    case setInsulinSchedule = 0x1A
    case tempBasalExtra = 0x16
    case bolusExtra = 0x17
    case cancelDelivery = 0x1F
    case getStatus = 0x0E
}

/// Delivery schedule type for SetInsulinSchedule command
public enum DASHDeliveryScheduleType: UInt8, Sendable {
    case basalSchedule = 0
    case tempBasal = 1
    case bolus = 2
}

/// Delivery type for cancel command
public enum DASHDeliveryType: UInt8, Sendable {
    case none = 0x00
    case tempBasal = 0x01
    case bolus = 0x02
    case all = 0x07  // basal + temp + bolus
}

// MARK: - DASH SetInsulinSchedule Command

/// SetInsulinSchedule command for DASH (0x1A)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/SetInsulinScheduleCommand.swift
public struct DASHSetInsulinScheduleCommand: Sendable {
    public let nonce: UInt32
    public let scheduleType: DASHDeliveryScheduleType
    public let units: Double
    public let timeBetweenPulses: TimeInterval
    
    /// Create a bolus schedule command
    /// - Parameters:
    ///   - nonce: Security nonce
    ///   - units: Bolus amount in units
    ///   - timeBetweenPulses: Seconds between pulses (default: 2s)
    public static func bolus(
        nonce: UInt32,
        units: Double,
        timeBetweenPulses: TimeInterval = DASHPodConstants.secondsPerBolusPulse
    ) -> DASHSetInsulinScheduleCommand {
        DASHSetInsulinScheduleCommand(
            nonce: nonce,
            scheduleType: .bolus,
            units: units,
            timeBetweenPulses: timeBetweenPulses
        )
    }
    
    /// Encode command to data
    /// Format: 1A LL NNNNNNNN 02 CCCC HH SSSS PPPP [entries]
    public func encode() -> Data {
        let pulses = UInt16((units / DASHPodConstants.pulseSize).rounded())
        let multiplier = UInt16((timeBetweenPulses * 8).rounded())
        let fieldA = pulses * multiplier
        
        // Build delivery table entry (simple single-entry for immediate bolus)
        let tableEntry = DASHInsulinTableEntry(segments: 1, pulses: Int(pulses), alternateSegmentPulse: false)
        let tableData = tableEntry.encode()
        
        // Calculate checksum
        let headerData = Data([
            1,  // numSegments
            UInt8((fieldA >> 8) & 0xFF),
            UInt8(fieldA & 0xFF),
            UInt8((pulses >> 8) & 0xFF),
            UInt8(pulses & 0xFF)
        ])
        let checksum = headerData.reduce(0) { $0 + UInt16($1) } + tableEntry.checksum()
        
        // Build command
        var data = Data()
        data.append(DASHMessageBlockType.setInsulinSchedule.rawValue)  // 0x1A
        data.append(UInt8(7 + headerData.count + tableData.count))     // length
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })  // nonce
        data.append(scheduleType.rawValue)  // 0x02 for bolus
        data.append(contentsOf: withUnsafeBytes(of: checksum.bigEndian) { Array($0) })  // checksum
        data.append(headerData)
        data.append(tableData)
        
        return data
    }
}

// MARK: - DASH Insulin Table Entry

/// Insulin delivery table entry
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/InsulinTableEntry.swift
public struct DASHInsulinTableEntry: Sendable {
    public let segments: Int      // 1-16 half-hour segments
    public let pulses: Int        // pulses per segment
    public let alternateSegmentPulse: Bool  // alternate +1 pulse pattern
    
    public init(segments: Int, pulses: Int, alternateSegmentPulse: Bool) {
        self.segments = min(segments, 16)
        self.pulses = min(pulses, 1023)  // 10-bit max
        self.alternateSegmentPulse = alternateSegmentPulse
    }
    
    /// Encode to 2-byte format: napp (n=segments-1, a=alternate, pp=pulses)
    public func encode() -> Data {
        var value: UInt16 = 0
        value |= UInt16((segments - 1) & 0x0F) << 12  // top 4 bits
        if alternateSegmentPulse {
            value |= 0x0800  // bit 11
        }
        value |= UInt16(pulses & 0x03FF)  // bottom 10 bits
        
        return Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
    
    /// Checksum contribution
    public func checksum() -> UInt16 {
        let encoded = encode()
        return UInt16(encoded[0]) + UInt16(encoded[1])
    }
}

// MARK: - DASH BolusExtra Command

/// BolusExtra command for DASH (0x17)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/BolusExtraCommand.swift
public struct DASHBolusExtraCommand: Sendable {
    public let units: Double
    public let timeBetweenPulses: TimeInterval
    public let acknowledgementBeep: Bool
    public let completionBeep: Bool
    public let programReminderInterval: TimeInterval
    public let extendedUnits: Double
    public let extendedDuration: TimeInterval
    
    public init(
        units: Double,
        timeBetweenPulses: TimeInterval = DASHPodConstants.secondsPerBolusPulse,
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = true,
        programReminderInterval: TimeInterval = 0,
        extendedUnits: Double = 0,
        extendedDuration: TimeInterval = 0
    ) {
        self.units = units
        self.timeBetweenPulses = timeBetweenPulses != 0 ? timeBetweenPulses : DASHPodConstants.secondsPerBolusPulse
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
        self.extendedUnits = extendedUnits
        self.extendedDuration = extendedDuration
    }
    
    /// Encode command to data
    /// Format: 17 0d BO NNNN XXXXXXXX YYYY ZZZZZZZZ
    public func encode() -> Data {
        let reminderMinutes = Int(programReminderInterval / 60)
        var beepOptions = UInt8(reminderMinutes & 0x3F)
        if completionBeep {
            beepOptions |= (1 << 6)
        }
        if acknowledgementBeep {
            beepOptions |= (1 << 7)
        }
        
        // Pulse count × 10 for immediate bolus
        let pulseCountX10 = UInt16((units * DASHPodConstants.pulsesPerUnit * 10).rounded())
        
        // Time between pulses in hundredths of milliseconds
        let delayHundredthsMs = UInt32((timeBetweenPulses * 100_000).rounded())
        
        // Extended bolus pulse count × 10
        let extPulseCountX10 = UInt16((extendedUnits * DASHPodConstants.pulsesPerUnit * 10).rounded())
        
        // Time between extended pulses in hundredths of milliseconds
        let extDelayHundredthsMs: UInt32
        if extPulseCountX10 > 0 {
            let timeBetweenExtPulses = extendedDuration / (Double(extPulseCountX10) / 10)
            extDelayHundredthsMs = UInt32((timeBetweenExtPulses * 100_000).rounded())
        } else {
            extDelayHundredthsMs = 0
        }
        
        var data = Data()
        data.append(DASHMessageBlockType.bolusExtra.rawValue)  // 0x17
        data.append(0x0D)  // length = 13
        data.append(beepOptions)
        data.append(contentsOf: withUnsafeBytes(of: pulseCountX10.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: delayHundredthsMs.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: extPulseCountX10.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: extDelayHundredthsMs.bigEndian) { Array($0) })
        
        return data
    }
}

// MARK: - DASH CancelDelivery Command

/// CancelDelivery command for DASH (0x1F)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/CancelDeliveryCommand.swift
public struct DASHCancelDeliveryCommand: Sendable {
    public let nonce: UInt32
    public let deliveryType: DASHDeliveryType
    public let beepType: UInt8
    
    public init(nonce: UInt32, deliveryType: DASHDeliveryType, beepType: UInt8 = 0) {
        self.nonce = nonce
        self.deliveryType = deliveryType
        self.beepType = beepType
    }
    
    /// Encode command to data
    /// Format: 1F 05 NNNNNNNN TT BB
    public func encode() -> Data {
        var data = Data()
        data.append(DASHMessageBlockType.cancelDelivery.rawValue)  // 0x1F
        data.append(0x05)  // length
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })
        data.append(deliveryType.rawValue)
        data.append(beepType)
        
        return data
    }
}

// MARK: - DASH Temp Basal Types (PUMP-PG-005)

/// Result of a DASH temp basal command
public struct DASHTempBasalResult: Sendable, Equatable {
    /// Temp basal rate in U/hr
    public let rate: Double
    
    /// Duration in seconds
    public let duration: TimeInterval
    
    /// When the temp basal was started
    public let startTime: Date
    
    /// Estimated end time
    public var estimatedEndTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    /// Duration in minutes
    public var durationMinutes: Int {
        Int(duration / 60)
    }
    
    public init(rate: Double, duration: TimeInterval, startTime: Date = Date()) {
        self.rate = rate
        self.duration = duration
        self.startTime = startTime
    }
}

/// SetInsulinSchedule command for temp basal (0x1A with type=1)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/SetInsulinScheduleCommand.swift
public struct DASHTempBasalScheduleCommand: Sendable {
    public let nonce: UInt32
    public let rate: Double
    public let duration: TimeInterval
    
    public init(nonce: UInt32, rate: Double, duration: TimeInterval) {
        self.nonce = nonce
        self.rate = rate
        self.duration = duration
    }
    
    /// Encode command to data
    /// Format: 1A LL NNNNNNNN 01 CCCC HH SSSS PPPP [entries]
    public func encode() -> Data {
        // Calculate segments and pulses
        let numSegments = Int((duration / DASHPodConstants.tempBasalSegmentDuration).rounded())
        let pulsesPerHour = Int((rate / DASHPodConstants.pulseSize).rounded())
        let pulsesPerSegment = pulsesPerHour / 2  // 30 min segment = half hour
        let alternateSegmentPulse = pulsesPerHour % 2 != 0
        
        // First segment pulses (same as pulsesPerSegment for temp basal)
        let firstSegmentPulses = UInt16(pulsesPerSegment)
        
        // Seconds remaining encoded as (seconds << 3) - fixed at 30 minutes for temp basal start
        let secondsRemaining = UInt16(30 * 60) << 3
        
        // Build table entries
        var tableEntries = [DASHInsulinTableEntry]()
        var remainingSegments = numSegments
        while remainingSegments > 0 {
            let segments = min(remainingSegments, 16)
            let entry = DASHInsulinTableEntry(
                segments: segments,
                pulses: pulsesPerSegment,
                alternateSegmentPulse: segments > 1 ? alternateSegmentPulse : false
            )
            tableEntries.append(entry)
            remainingSegments -= segments
        }
        
        // Encode table entries
        var tableData = Data()
        for entry in tableEntries {
            tableData.append(entry.encode())
        }
        
        // Calculate checksum
        let headerData = Data([
            UInt8(numSegments),
            UInt8((secondsRemaining >> 8) & 0xFF),
            UInt8(secondsRemaining & 0xFF),
            UInt8((firstSegmentPulses >> 8) & 0xFF),
            UInt8(firstSegmentPulses & 0xFF)
        ])
        var checksum: UInt16 = headerData.reduce(0) { $0 + UInt16($1) }
        for entry in tableEntries {
            checksum += entry.checksum()
        }
        
        // Build command
        var data = Data()
        data.append(DASHMessageBlockType.setInsulinSchedule.rawValue)  // 0x1A
        data.append(UInt8(7 + headerData.count + tableData.count))     // length
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })  // nonce
        data.append(DASHDeliveryScheduleType.tempBasal.rawValue)  // 0x01
        data.append(contentsOf: withUnsafeBytes(of: checksum.bigEndian) { Array($0) })  // checksum
        data.append(headerData)
        data.append(tableData)
        
        return data
    }
}

/// TempBasalExtra command for DASH (0x16)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/TempBasalExtraCommand.swift
public struct DASHTempBasalExtraCommand: Sendable {
    public let rate: Double
    public let duration: TimeInterval
    public let acknowledgementBeep: Bool
    public let completionBeep: Bool
    public let programReminderInterval: TimeInterval
    
    public init(
        rate: Double,
        duration: TimeInterval,
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = false,
        programReminderInterval: TimeInterval = 0
    ) {
        self.rate = rate
        self.duration = duration
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
    }
    
    /// Encode command to data
    /// Format: 16 LL BO 00 PPPP DDDDDDDD [rate entries...]
    public func encode() -> Data {
        let reminderMinutes = Int(programReminderInterval / 60)
        var beepOptions = UInt8(reminderMinutes & 0x3F)
        if completionBeep {
            beepOptions |= (1 << 6)
        }
        if acknowledgementBeep {
            beepOptions |= (1 << 7)
        }
        
        // Generate rate entries
        let rateEntries = DASHRateEntry.makeEntries(rate: rate, duration: duration)
        
        // Remaining pulses (from first entry)
        let remainingPulses = rateEntries.first?.totalPulses ?? 0
        let remainingPulsesX10 = UInt16((remainingPulses * 10).rounded())
        
        // Delay until first pulse (from first entry)
        let delayUntilFirstPulse = rateEntries.first?.delayBetweenPulses ?? DASHPodConstants.maxTimeBetweenPulses
        let delayHundredthsMs = UInt32((delayUntilFirstPulse * 100_000).rounded())
        
        // Build command
        var data = Data()
        data.append(DASHMessageBlockType.tempBasalExtra.rawValue)  // 0x16
        data.append(UInt8(8 + rateEntries.count * 6))  // length
        data.append(beepOptions)
        data.append(0x00)  // reserved
        data.append(contentsOf: withUnsafeBytes(of: remainingPulsesX10.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: delayHundredthsMs.bigEndian) { Array($0) })
        
        // Append rate entries
        for entry in rateEntries {
            data.append(entry.encode())
        }
        
        return data
    }
}

/// Rate entry for temp basal extra command
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/BasalDeliveryTable.swift
public struct DASHRateEntry: Sendable {
    public let totalPulses: Double
    public let delayBetweenPulses: TimeInterval
    
    public init(totalPulses: Double, delayBetweenPulses: TimeInterval) {
        self.totalPulses = totalPulses
        self.delayBetweenPulses = delayBetweenPulses
    }
    
    /// Encode to 6-byte format: PPPP DDDDDDDD
    public func encode() -> Data {
        let pulsesX10 = UInt16((totalPulses * 10).rounded())
        let delayHundredthsMs = UInt32((delayBetweenPulses * 100_000).rounded())
        
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: pulsesX10.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: delayHundredthsMs.bigEndian) { Array($0) })
        return data
    }
    
    /// Create rate entries for a temp basal
    public static func makeEntries(rate: Double, duration: TimeInterval) -> [DASHRateEntry] {
        var entries = [DASHRateEntry]()
        let numSegments = max(Int((duration / DASHPodConstants.tempBasalSegmentDuration).rounded()), 1)
        
        if rate == 0 {
            // Zero temp basal: one entry per segment with no pulses
            for _ in 0..<numSegments {
                entries.append(DASHRateEntry(
                    totalPulses: 0,
                    delayBetweenPulses: DASHPodConstants.maxTimeBetweenPulses
                ))
            }
        } else {
            // Calculate pulses and timing
            let pulsesPerHour = rate / DASHPodConstants.pulseSize
            let pulsesPerSegment = pulsesPerHour / 2  // 30 min = half hour
            let delayBetweenPulses: TimeInterval = .init(3600) / pulsesPerHour
            
            // Maximum pulses per entry (16-bit value / 10)
            let maxPulsesPerEntry = 6553.5
            let maxSegmentsPerEntry = pulsesPerSegment > 0 ? Int(maxPulsesPerEntry / pulsesPerSegment) : 1
            
            var remainingSegments = numSegments
            while remainingSegments > 0 {
                let segmentsThisEntry = min(remainingSegments, min(maxSegmentsPerEntry, 16))
                let totalPulses = pulsesPerSegment * Double(segmentsThisEntry)
                entries.append(DASHRateEntry(
                    totalPulses: totalPulses,
                    delayBetweenPulses: delayBetweenPulses
                ))
                remainingSegments -= segmentsThisEntry
            }
        }
        
        return entries
    }
}

// MARK: - DASH Scheduled Basal Command (PUMP-DELIVERY-003)

/// SetInsulinSchedule command for resuming scheduled basal (0x1A with type=0)
/// Source: externals/Trio/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/SetInsulinScheduleCommand.swift
/// Trace: PUMP-DELIVERY-003
public struct DASHBasalScheduleCommand: Sendable {
    public let nonce: UInt32
    public let rate: Double
    public let acknowledgementBeep: Bool
    
    public init(nonce: UInt32, rate: Double, acknowledgementBeep: Bool = false) {
        self.nonce = nonce
        self.rate = rate
        self.acknowledgementBeep = acknowledgementBeep
    }
    
    /// Encode command to data
    /// Format: 1A LL NNNNNNNN 00 CCCC HH SSSS PPPP [entries]
    /// type=0 for scheduled basal (vs type=1 for temp basal)
    public func encode() -> Data {
        // For single-rate basal, we use 1 segment of 24 half-hour slots
        let pulsesPerHour = Int((rate / DASHPodConstants.pulseSize).rounded())
        let pulsesPerSegment = pulsesPerHour / 2  // 30 min segment
        let alternateSegmentPulse = pulsesPerHour % 2 != 0
        
        // Build table entries for 48 segments (24 hours)
        let numSegments = 48  // Full day
        var tableEntries = [DASHInsulinTableEntry]()
        var remainingSegments = numSegments
        while remainingSegments > 0 {
            let segments = min(remainingSegments, 16)
            tableEntries.append(DASHInsulinTableEntry(
                segments: segments,
                pulses: pulsesPerSegment,
                alternateSegmentPulse: segments > 1 ? alternateSegmentPulse : false
            ))
            remainingSegments -= segments
        }
        
        // First segment pulses
        let firstSegmentPulses = UInt16(pulsesPerSegment)
        
        // Seconds remaining encoded as (seconds << 3) - start of segment
        let secondsRemaining = UInt16(30 * 60) << 3
        
        // Encode table entries
        var tableData = Data()
        for entry in tableEntries {
            tableData.append(entry.encode())
        }
        
        // Calculate checksum
        let headerData = Data([
            UInt8(numSegments),
            UInt8((secondsRemaining >> 8) & 0xFF),
            UInt8(secondsRemaining & 0xFF),
            UInt8((firstSegmentPulses >> 8) & 0xFF),
            UInt8(firstSegmentPulses & 0xFF)
        ])
        var checksum: UInt16 = headerData.reduce(0) { $0 + UInt16($1) }
        for entry in tableEntries {
            checksum += entry.checksum()
        }
        
        // Build command
        var data = Data()
        data.append(DASHMessageBlockType.setInsulinSchedule.rawValue)  // 0x1A
        data.append(UInt8(7 + headerData.count + tableData.count))     // length
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })  // nonce
        data.append(DASHDeliveryScheduleType.basalSchedule.rawValue)  // 0x00 for scheduled basal
        data.append(contentsOf: withUnsafeBytes(of: checksum.bigEndian) { Array($0) })  // checksum
        data.append(headerData)
        data.append(tableData)
        
        return data
    }
}
