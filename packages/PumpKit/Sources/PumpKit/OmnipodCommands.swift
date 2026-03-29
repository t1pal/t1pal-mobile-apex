// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OmnipodCommands.swift
// PumpKit
//
// High-level Omnipod DASH command implementations.
// Uses OmnipodBLEManager for BLE communication.
// Trace: PUMP-OMNI-006, PRD-005
//
// Usage:
//   let commander = OmnipodCommander(bleManager: manager)
//   let status = try await commander.getStatus()
//   try await commander.setTempBasal(percent: 150, duration: 30 * 60)

import Foundation

// MARK: - Omnipod Command Opcodes

/// Omnipod message block types (Layer 3 - Insulin control)
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/MessageBlock.swift
/// See: https://github.com/openaps/openomni/wiki/Message-Types
public enum OmnipodOpcode: UInt8, Sendable {
    // Response types
    case versionResponse = 0x01     // Pod version info
    case podInfoResponse = 0x02     // Pod info response
    case errorResponse = 0x06       // Error response
    case statusResponse = 0x1D      // Status response
    
    // Setup commands
    case setupPod = 0x03            // Setup pod
    case assignAddress = 0x07       // Assign address
    case faultConfig = 0x08         // Configure fault handling
    
    // Status commands
    case getStatus = 0x0E           // Request status
    
    // Delivery commands
    case acknowledgeAlert = 0x11    // Acknowledge alerts
    case basalScheduleExtra = 0x13  // Basal schedule (extra)
    case tempBasalExtra = 0x16      // Temp basal (extra)
    case bolusExtra = 0x17          // Bolus (extra)
    case configureAlerts = 0x19     // Configure alerts
    case setInsulinSchedule = 0x1A  // Set insulin schedule (main)
    case deactivatePod = 0x1C       // Deactivate pod
    case beepConfig = 0x1E          // Configure beeps
    case cancelDelivery = 0x1F      // Cancel delivery (basal/bolus)
    
    public var displayName: String {
        switch self {
        case .versionResponse: return "Version Response"
        case .podInfoResponse: return "Pod Info Response"
        case .errorResponse: return "Error Response"
        case .statusResponse: return "Status Response"
        case .setupPod: return "Setup Pod"
        case .assignAddress: return "Assign Address"
        case .faultConfig: return "Fault Config"
        case .getStatus: return "Get Status"
        case .acknowledgeAlert: return "Acknowledge Alert"
        case .basalScheduleExtra: return "Basal Schedule Extra"
        case .tempBasalExtra: return "Temp Basal Extra"
        case .bolusExtra: return "Bolus Extra"
        case .configureAlerts: return "Configure Alerts"
        case .setInsulinSchedule: return "Set Insulin Schedule"
        case .deactivatePod: return "Deactivate Pod"
        case .beepConfig: return "Beep Config"
        case .cancelDelivery: return "Cancel Delivery"
        }
    }
    
    /// Whether this is a command (vs response)
    public var isCommand: Bool {
        switch self {
        case .versionResponse, .podInfoResponse, .errorResponse, .statusResponse:
            return false
        default:
            return true
        }
    }
    
    /// Whether this modifies delivery
    public var isWriteCommand: Bool {
        switch self {
        case .basalScheduleExtra, .tempBasalExtra, .bolusExtra,
             .setInsulinSchedule, .cancelDelivery, .deactivatePod:
            return true
        default:
            return false
        }
    }
}

// MARK: - Pod Status

/// Omnipod pod status response
public struct OmnipodPodStatus: Sendable, Equatable {
    public let deliveryStatus: OmnipodDeliveryStatus
    public let podState: OmnipodPodState
    public let reservoirLevel: Double   // Units remaining (> 50 shows as 50+)
    public let minutesSinceActivation: Int
    public let bolusRemaining: Double   // Units of active bolus
    public let tempBasalActive: Bool
    public let tempBasalPercent: Int?
    public let tempBasalRemaining: TimeInterval?
    public let alerts: [OmnipodAlertType]
    
    public init(
        deliveryStatus: OmnipodDeliveryStatus = .basalRunning,
        podState: OmnipodPodState = .running,
        reservoirLevel: Double,
        minutesSinceActivation: Int = 0,
        bolusRemaining: Double = 0,
        tempBasalActive: Bool = false,
        tempBasalPercent: Int? = nil,
        tempBasalRemaining: TimeInterval? = nil,
        alerts: [OmnipodAlertType] = []
    ) {
        self.deliveryStatus = deliveryStatus
        self.podState = podState
        self.reservoirLevel = reservoirLevel
        self.minutesSinceActivation = minutesSinceActivation
        self.bolusRemaining = bolusRemaining
        self.tempBasalActive = tempBasalActive
        self.tempBasalPercent = tempBasalPercent
        self.tempBasalRemaining = tempBasalRemaining
        self.alerts = alerts
    }
    
    public var hoursActive: Double {
        Double(minutesSinceActivation) / 60.0
    }
    
    public var isExpired: Bool {
        hoursActive >= 72.0
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 10.0
    }
    
    public var canDeliver: Bool {
        podState == .running && deliveryStatus != .suspended
    }
    
    public var isBolusing: Bool {
        bolusRemaining > 0
    }
}

// MARK: - Delivery Status

/// Pod delivery status
public enum OmnipodDeliveryStatus: String, Codable, Sendable {
    case basalRunning = "basal"
    case tempBasalRunning = "tempBasal"
    case bolusInProgress = "bolus"
    case suspended = "suspended"
    case scheduledBasalPaused = "paused"
    case none = "none"
    
    public var displayName: String {
        switch self {
        case .basalRunning: return "Basal Running"
        case .tempBasalRunning: return "Temp Basal"
        case .bolusInProgress: return "Bolusing"
        case .suspended: return "Suspended"
        case .scheduledBasalPaused: return "Paused"
        case .none: return "None"
        }
    }
}

// MARK: - Pod State

/// Pod lifecycle state
public enum OmnipodPodState: String, Codable, Sendable {
    case uninitialized = "uninitialized"
    case paired = "paired"
    case priming = "priming"
    case insertingCannula = "insertingCannula"
    case running = "running"
    case faulted = "faulted"
    case deactivated = "deactivated"
    
    public var displayName: String {
        switch self {
        case .uninitialized: return "Not Paired"
        case .paired: return "Paired"
        case .priming: return "Priming"
        case .insertingCannula: return "Inserting"
        case .running: return "Running"
        case .faulted: return "Faulted"
        case .deactivated: return "Deactivated"
        }
    }
    
    public var isUsable: Bool {
        self == .running
    }
}

// MARK: - Alert Types

/// Omnipod alert types
public enum OmnipodAlertType: String, Codable, Sendable, CaseIterable {
    case podExpiring = "podExpiring"
    case lowReservoir = "lowReservoir"
    case suspendEnded = "suspendEnded"
    case suspendInProgress = "suspendInProgress"
    case userPodExpiration = "userPodExpiration"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .podExpiring: return "Pod Expiring"
        case .lowReservoir: return "Low Reservoir"
        case .suspendEnded: return "Suspend Ended"
        case .suspendInProgress: return "Suspended"
        case .userPodExpiration: return "Expiration Reminder"
        case .unknown: return "Unknown Alert"
        }
    }
    
    public var isCritical: Bool {
        switch self {
        case .lowReservoir, .podExpiring:
            return true
        default:
            return false
        }
    }
}

// MARK: - Temp Basal

/// Active temp basal info
public struct OmnipodTempBasal: Sendable, Equatable {
    public let percent: Int           // 0-200%
    public let duration: TimeInterval
    public let startTime: Date
    
    public init(percent: Int, duration: TimeInterval, startTime: Date = Date()) {
        self.percent = percent
        self.duration = duration
        self.startTime = startTime
    }
    
    public var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    public var isExpired: Bool {
        Date() >= endTime
    }
    
    public var remainingDuration: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }
    
    public var durationMinutes: Int {
        Int(duration / 60)
    }
}

// MARK: - Pod Info Types (DASH-IMPL-006)

/// Pod info request subtypes for detailed queries
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/PodInfo.swift
public enum OmnipodPodInfoType: UInt8, Sendable, CaseIterable {
    case normal = 0x00              // Normal status response
    case triggeredAlerts = 0x01     // Unacknowledged triggered alerts
    case detailedStatus = 0x02      // Detailed status (returned after pod fault)
    case pulseLogPlus = 0x03        // Last 60 pulse log entries + additional info
    case activationTime = 0x05      // Pod activation time and possible fault info
    case noSeqStatus = 0x07         // DASH only: status without incrementing msg seq
    case pulseLogRecent = 0x50      // Last 50 pulse log entries
    case pulseLogPrevious = 0x51    // Previous 50 entries before the last 50
    
    public var displayName: String {
        switch self {
        case .normal: return "Normal Status"
        case .triggeredAlerts: return "Triggered Alerts"
        case .detailedStatus: return "Detailed Status"
        case .pulseLogPlus: return "Pulse Log Plus"
        case .activationTime: return "Activation Time"
        case .noSeqStatus: return "Status (No Seq)"
        case .pulseLogRecent: return "Recent Pulse Log"
        case .pulseLogPrevious: return "Previous Pulse Log"
        }
    }
}

/// Pod activation time and fault info (type 0x05)
public struct OmnipodActivationInfo: Sendable, Equatable {
    public let activationYear: Int
    public let activationMonth: Int
    public let activationDay: Int
    public let activationHour: Int
    public let activationMinute: Int
    public let faultEventCode: UInt8
    public let faultTimeMinutes: Int
    
    public var activationDate: Date? {
        var components = DateComponents()
        components.year = 2000 + activationYear // YY format
        components.month = activationMonth
        components.day = activationDay
        components.hour = activationHour
        components.minute = activationMinute
        return Calendar.current.date(from: components)
    }
    
    public var hasFault: Bool {
        faultEventCode != 0
    }
}

/// Triggered alerts info (type 0x01)
public struct OmnipodTriggeredAlerts: Sendable, Equatable {
    public let alertMask: UInt16
    
    public var activeAlertSlots: [Int] {
        (0..<16).filter { (alertMask & (1 << $0)) != 0 }
    }
}

/// Pod info response container
public enum OmnipodPodInfoResponse: Sendable {
    case status(OmnipodPodStatus)
    case activationTime(OmnipodActivationInfo)
    case triggeredAlerts(OmnipodTriggeredAlerts)
    case detailedStatus(OmnipodPodStatus)
    case pulseLog(entries: Int, data: Data)
}

// MARK: - Beep Options (DASH-IMPL-004)

/// Beep configuration options for Omnipod DASH commands
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/TempBasalExtraCommand.swift
public struct OmnipodBeepOptions: Sendable, Equatable {
    /// Beep when command is acknowledged by pod
    public let acknowledgementBeep: Bool
    
    /// Beep when delivery completes
    public let completionBeep: Bool
    
    /// Interval for reminder beeps during delivery (0 = no reminder)
    /// Maximum 63 minutes
    public let programReminderInterval: TimeInterval
    
    public init(
        acknowledgementBeep: Bool = false,
        completionBeep: Bool = false,
        programReminderInterval: TimeInterval = 0
    ) {
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        // Clamp to 63 minutes (6-bit field)
        self.programReminderInterval = min(programReminderInterval, 63 * 60)
    }
    
    /// Silent - no beeps
    public static let silent = OmnipodBeepOptions()
    
    /// Completion beep only
    public static let completionOnly = OmnipodBeepOptions(completionBeep: true)
    
    /// Both acknowledgement and completion beeps
    public static let full = OmnipodBeepOptions(acknowledgementBeep: true, completionBeep: true)
    
    /// Encode beep options byte
    /// Format: bit7 = ack beep, bit6 = completion beep, bits5-0 = reminder minutes
    public var encoded: UInt8 {
        var byte: UInt8 = 0
        if acknowledgementBeep { byte |= 0x80 }
        if completionBeep { byte |= 0x40 }
        byte |= UInt8(Int(programReminderInterval / 60) & 0x3F)
        return byte
    }
}

// MARK: - Pulse Scheduling (DASH-IMPL-002)

/// Pod hardware constants for pulse timing
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/Pod.swift
public enum OmnipodPodConstants {
    /// Units per pulse (0.05 U)
    public static let pulseSize: Double = 0.05
    
    /// Pulses per unit (20 pulses = 1 U)
    public static let pulsesPerUnit: Double = 1.0 / pulseSize
    
    /// Seconds between bolus pulses (2 seconds = 1.5 U/min)
    public static let secondsPerBolusPulse: Double = 2.0
    
    /// Maximum time between pulses (used for zero/near-zero rates)
    /// 36000 seconds = 10 hours (max delay)
    public static let maxTimeBetweenPulses: TimeInterval = 36000.0
}

/// Rate entry for pulse scheduling (DASH-IMPL-002)
/// Represents a segment of insulin delivery with specific pulse timing
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/BasalDeliveryTable.swift
public struct OmnipodRateEntry: Sendable, Equatable {
    /// Total pulses for this entry (in 1/10th pulse units internally)
    public let totalPulses: Double
    
    /// Delay between pulses in seconds
    public let delayBetweenPulses: TimeInterval
    
    public init(totalPulses: Double, delayBetweenPulses: TimeInterval) {
        self.totalPulses = totalPulses
        self.delayBetweenPulses = delayBetweenPulses
    }
    
    /// Computed rate in U/hr based on pulse timing
    public var rate: Double {
        guard totalPulses > 0, delayBetweenPulses > 0 else { return 0 }
        // rate = (pulses/hour) / pulsesPerUnit = (3600/delay) / 20
        return (3600.0 / delayBetweenPulses) / OmnipodPodConstants.pulsesPerUnit
    }
    
    /// Duration of this rate entry
    public var duration: TimeInterval {
        guard totalPulses > 0 else { return 1800 } // 30 min for zero rate
        return delayBetweenPulses * totalPulses
    }
    
    /// Encode to wire format: totalPulses (2 bytes) + delay (4 bytes)
    public var data: Data {
        var data = Data()
        // Total pulses as 1/10th units (big-endian UInt16)
        let pulsesX10 = UInt16(round(totalPulses * 10))
        data.append(UInt8((pulsesX10 >> 8) & 0xFF))
        data.append(UInt8(pulsesX10 & 0xFF))
        // Delay in hundredths of milliseconds (big-endian UInt32)
        let delayHundredths = UInt32(delayBetweenPulses * 100_000)
        data.append(UInt8((delayHundredths >> 24) & 0xFF))
        data.append(UInt8((delayHundredths >> 16) & 0xFF))
        data.append(UInt8((delayHundredths >> 8) & 0xFF))
        data.append(UInt8(delayHundredths & 0xFF))
        return data
    }
    
    /// Create rate entries for a given rate and duration
    /// Splits into 30-minute segments as required by pod hardware
    public static func makeEntries(rate: Double, duration: TimeInterval) -> [OmnipodRateEntry] {
        let numHalfHours = max(1, Int(round(duration / 1800)))
        
        // Zero rate: one entry per half-hour with no pulses
        if rate <= 0 {
            return (0..<numHalfHours).map { _ in
                OmnipodRateEntry(totalPulses: 0, delayBetweenPulses: OmnipodPodConstants.maxTimeBetweenPulses)
            }
        }
        
        // Calculate pulses per half-hour segment
        let pulsesPerSegment = round(rate / OmnipodPodConstants.pulseSize) / 2
        let delayBetweenPulses = 3600.0 / (rate * OmnipodPodConstants.pulsesPerUnit)
        
        // Build entries (each covers multiple half-hour segments if possible)
        var entries: [OmnipodRateEntry] = []
        var remainingSegments = numHalfHours
        
        while remainingSegments > 0 {
            let segmentsThisEntry = remainingSegments // Simplify: one entry covers all
            let totalPulses = pulsesPerSegment * Double(segmentsThisEntry)
            entries.append(OmnipodRateEntry(totalPulses: totalPulses, delayBetweenPulses: delayBetweenPulses))
            remainingSegments = 0
        }
        
        return entries
    }
}

// MARK: - Insulin Schedule Table Entry (DASH-IMPL-005)

/// Insulin table entry for SetInsulinScheduleCommand (0x1A)
/// Source: externals/OmniBLE/OmniBLE/OmnipodCommon/InsulinTableEntry.swift
/// Format: 2 bytes encoding segments, pulses, and alternateSegmentPulse flag
public struct OmnipodInsulinTableEntry: Sendable, Equatable {
    /// Number of 30-minute segments (1-16)
    public let segments: Int
    
    /// Pulses per segment (0-1023)
    public let pulses: Int
    
    /// Whether to alternate +1 pulse on odd segments
    public let alternateSegmentPulse: Bool
    
    public init(segments: Int, pulses: Int, alternateSegmentPulse: Bool = false) {
        self.segments = min(max(segments, 1), 16)
        self.pulses = min(max(pulses, 0), 1023)
        self.alternateSegmentPulse = alternateSegmentPulse
    }
    
    /// Create table entry for a given rate and number of segments
    public init(rate: Double, segments: Int) {
        let pulsesPerHour = Int(round(rate / OmnipodPodConstants.pulseSize))
        let pulsesPerSegment = pulsesPerHour / 2
        self.segments = min(max(segments, 1), 16)
        self.pulses = pulsesPerSegment
        self.alternateSegmentPulse = (pulsesPerHour % 2) != 0
    }
    
    /// Encode to wire format (2 bytes)
    /// Byte 0: [segments-1:4][altPulse:1][pulsesHigh:3]
    /// Byte 1: [pulsesLow:8]
    public var data: Data {
        let pulsesHighBits = UInt8((pulses >> 8) & 0b11)
        let pulsesLowBits = UInt8(pulses & 0xFF)
        let byte0 = UInt8((segments - 1) << 4) | UInt8(alternateSegmentPulse ? 1 : 0) << 3 | pulsesHighBits
        return Data([byte0, pulsesLowBits])
    }
    
    /// Checksum contribution for this entry
    public func checksum() -> UInt16 {
        let checksumPerSegment = (pulses & 0xFF) + (pulses >> 8)
        return UInt16(checksumPerSegment * segments + (alternateSegmentPulse ? segments / 2 : 0))
    }
}

// MARK: - Omnipod Commander

/// High-level Omnipod pod command interface
public actor OmnipodCommander {
    // MARK: - Properties
    
    private let bleManager: OmnipodBLEManager
    
    private(set) var lastStatus: OmnipodPodStatus?
    private(set) var activeTempBasal: OmnipodTempBasal?
    private(set) var podState: OmnipodPodState = .uninitialized
    
    // Nonce management (DASH-IMPL-001)
    // Nonce is used to prevent replay attacks
    // Starts with random seed, increments after each use
    private var currentNonce: UInt32
    
    // Pod limits
    public let maxTempBasalPercent: Int = 200
    public let minTempBasalPercent: Int = 0
    public let maxBolus: Double = 30.0
    public let bolusIncrement: Double = 0.05
    public let maxTempBasalDuration: TimeInterval = 12 * 60 * 60 // 12 hours
    
    // MARK: - Init
    
    public init(bleManager: OmnipodBLEManager) {
        self.bleManager = bleManager
        // Initialize nonce with random seed (DASH-IMPL-001)
        self.currentNonce = UInt32.random(in: UInt32.min...UInt32.max)
    }
    
    // MARK: - Nonce Management (DASH-IMPL-001)
    
    /// Get the next nonce for a command
    /// Increments the nonce counter to prevent replay attacks
    private func getNextNonce() -> UInt32 {
        let nonce = currentNonce
        // Increment nonce (wraps around on overflow)
        currentNonce = currentNonce &+ 1
        return nonce
    }
    
    /// Build command data with nonce prefix
    /// Format: [opcode, length, nonce (4 bytes big-endian), payload...]
    private func buildNoncedCommand(opcode: OmnipodOpcode, payload: Data = Data()) -> Data {
        let nonce = getNextNonce()
        var data = Data()
        data.append(opcode.rawValue)
        data.append(UInt8(4 + payload.count)) // length = nonce (4) + payload
        // Append nonce as big-endian
        data.append(UInt8((nonce >> 24) & 0xFF))
        data.append(UInt8((nonce >> 16) & 0xFF))
        data.append(UInt8((nonce >> 8) & 0xFF))
        data.append(UInt8(nonce & 0xFF))
        data.append(payload)
        return data
    }
    
    /// Resync nonce after a nonce error from the pod
    /// Pod sends its expected nonce in error response
    public func resyncNonce(to expectedNonce: UInt32) {
        PumpLogger.general.warning("Resyncing nonce to \(expectedNonce)")
        currentNonce = expectedNonce
    }
    
    // MARK: - Status Commands
    
    /// Get pod status
    public func getStatus() async throws -> OmnipodPodStatus {
        PumpLogger.status.info("Reading Omnipod status")
        
        let command = Data([OmnipodOpcode.getStatus.rawValue])
        _ = try await bleManager.sendCommand(command)
        
        // Check for active temp basal expiry
        if let tempBasal = activeTempBasal, tempBasal.isExpired {
            activeTempBasal = nil
        }
        
        // Simulated response
        let status = OmnipodPodStatus(
            deliveryStatus: activeTempBasal != nil ? .tempBasalRunning : .basalRunning,
            podState: podState == .uninitialized ? .running : podState,
            reservoirLevel: 150.0,
            minutesSinceActivation: 1440, // 24 hours
            bolusRemaining: 0,
            tempBasalActive: activeTempBasal != nil,
            tempBasalPercent: activeTempBasal?.percent,
            tempBasalRemaining: activeTempBasal?.remainingDuration,
            alerts: []
        )
        
        lastStatus = status
        if podState == .uninitialized {
            podState = .running
        }
        
        return status
    }
    
    /// Get detailed status with more information (via podInfoResponse)
    public func getDetailedStatus() async throws -> OmnipodPodStatus {
        PumpLogger.status.info("Reading Omnipod detailed status")
        
        // Request pod info (0x02) - returns more detailed information
        let command = Data([OmnipodOpcode.podInfoResponse.rawValue])
        _ = try await bleManager.sendCommand(command)
        
        return try await getStatus()
    }
    
    /// Get pod info by type (DASH-IMPL-006)
    /// Uses getStatus (0x0E) opcode with podInfoType parameter
    /// Format: 0E TT (opcode, podInfoType)
    ///
    /// - Parameter type: The type of pod info to request
    /// - Returns: Response container with type-specific data
    public func getPodInfo(type: OmnipodPodInfoType) async throws -> OmnipodPodInfoResponse {
        PumpLogger.status.info("Reading Omnipod pod info: \(type.displayName)")
        
        // Build command: 0x0E + podInfoType
        let command = Data([OmnipodOpcode.getStatus.rawValue, type.rawValue])
        _ = try await bleManager.sendCommand(command)
        
        // Parse response based on type (simulated for now)
        switch type {
        case .normal, .noSeqStatus:
            let status = try await getStatus()
            return .status(status)
            
        case .activationTime:
            // Simulated activation info
            let activation = OmnipodActivationInfo(
                activationYear: 26,
                activationMonth: 2,
                activationDay: 20,
                activationHour: 10,
                activationMinute: 30,
                faultEventCode: 0,
                faultTimeMinutes: 0
            )
            return .activationTime(activation)
            
        case .triggeredAlerts:
            // Simulated: no triggered alerts
            let alerts = OmnipodTriggeredAlerts(alertMask: 0)
            return .triggeredAlerts(alerts)
            
        case .detailedStatus:
            let status = try await getStatus()
            return .detailedStatus(status)
            
        case .pulseLogPlus, .pulseLogRecent, .pulseLogPrevious:
            // Simulated pulse log (empty)
            return .pulseLog(entries: 0, data: Data())
        }
    }
    
    /// Convenience: Get activation time info
    public func getActivationTime() async throws -> OmnipodActivationInfo {
        let response = try await getPodInfo(type: .activationTime)
        guard case .activationTime(let info) = response else {
            throw OmnipodCommandError.invalidResponse
        }
        return info
    }
    
    /// Convenience: Get triggered alerts
    public func getTriggeredAlerts() async throws -> OmnipodTriggeredAlerts {
        let response = try await getPodInfo(type: .triggeredAlerts)
        guard case .triggeredAlerts(let alerts) = response else {
            throw OmnipodCommandError.invalidResponse
        }
        return alerts
    }
    
    // MARK: - Temp Basal Commands
    
    /// Set temp basal (percent-based)
    /// Uses tempBasalExtra (0x16) opcode
    public func setTempBasal(percent: Int, duration: TimeInterval) async throws {
        guard percent >= minTempBasalPercent && percent <= maxTempBasalPercent else {
            throw OmnipodCommandError.invalidPercent
        }
        
        guard duration >= 30 * 60 && duration <= maxTempBasalDuration else {
            throw OmnipodCommandError.invalidDuration
        }
        
        guard podState == .running else {
            throw OmnipodCommandError.podNotReady
        }
        
        PumpLogger.basal.info("Setting Omnipod temp basal: \(percent)% for \(Int(duration/60)) min")
        
        // Build command
        var params = Data()
        params.append(UInt8(percent))
        params.append(UInt8(duration / 1800)) // Half-hour units
        
        let command = Data([OmnipodOpcode.tempBasalExtra.rawValue]) + params
        _ = try await bleManager.sendCommand(command)
        
        activeTempBasal = OmnipodTempBasal(percent: percent, duration: duration)
    }
    
    /// Set temp basal (rate-based with full hardware protocol) (DASH-IMPL-002, DASH-IMPL-005)
    /// Sends paired commands: SetInsulinScheduleCommand (0x1A) + TempBasalExtraCommand (0x16)
    /// Both commands are required for proper hardware delivery
    /// Set temp basal rate with proper pulse timing (DASH-IMPL-002, DASH-IMPL-004, DASH-IMPL-005)
    /// Uses setInsulinSchedule (0x1A) + tempBasalExtra (0x16) opcodes
    public func setTempBasalRate(rate: Double, duration: TimeInterval, beepOptions: OmnipodBeepOptions = .silent) async throws {
        guard rate >= 0 && rate <= 30.0 else {
            throw OmnipodCommandError.invalidRate
        }
        
        guard duration >= 30 * 60 && duration <= maxTempBasalDuration else {
            throw OmnipodCommandError.invalidDuration
        }
        
        guard podState == .running else {
            throw OmnipodCommandError.podNotReady
        }
        
        PumpLogger.basal.info("Setting Omnipod temp basal rate: \(rate) U/hr for \(Int(duration/60)) min")
        
        // Calculate pulse parameters
        let numHalfHours = max(1, Int(round(duration / 1800)))
        let pulsesPerHour = Int(round(rate / OmnipodPodConstants.pulseSize))
        let firstSegmentPulses = UInt16(pulsesPerHour / 2)
        
        // Build table entry for SetInsulinScheduleCommand (DASH-IMPL-005)
        let tableEntry = OmnipodInsulinTableEntry(rate: rate, segments: numHalfHours)
        
        // Calculate checksum for 0x1A command
        // Checksum = sum of schedule data bytes + table entry checksum
        let secondsRemaining: UInt16 = 30 * 60 // Start of first segment
        let secondsField = secondsRemaining << 3
        let checksumBase: UInt16 = UInt16(numHalfHours) +
            UInt16((secondsField >> 8) & 0xFF) + UInt16(secondsField & 0xFF) +
            UInt16((firstSegmentPulses >> 8) & 0xFF) + UInt16(firstSegmentPulses & 0xFF)
        let checksum = checksumBase + tableEntry.checksum()
        
        // Build SetInsulinScheduleCommand (0x1A) with nonce (DASH-IMPL-005)
        // Format: 1A LEN NNNNNNNN TT CCCC [scheduleData] [tableEntries]
        //   TT = schedule type (0x01 for temp basal)
        //   CCCC = checksum
        var scheduleCmd = Data()
        scheduleCmd.append(OmnipodOpcode.setInsulinSchedule.rawValue)
        let scheduleDataLen = 5 + 2 // header (5) + one table entry (2)
        scheduleCmd.append(UInt8(7 + scheduleDataLen)) // length = nonce(4) + type(1) + checksum(2) + data
        
        // Append nonce (DASH-IMPL-001)
        let nonce = getNextNonce()
        scheduleCmd.append(UInt8((nonce >> 24) & 0xFF))
        scheduleCmd.append(UInt8((nonce >> 16) & 0xFF))
        scheduleCmd.append(UInt8((nonce >> 8) & 0xFF))
        scheduleCmd.append(UInt8(nonce & 0xFF))
        
        // Schedule type (temp basal = 0x01)
        scheduleCmd.append(0x01)
        
        // Checksum (big-endian)
        scheduleCmd.append(UInt8((checksum >> 8) & 0xFF))
        scheduleCmd.append(UInt8(checksum & 0xFF))
        
        // Schedule data: numSegments, secondsRemaining, firstSegmentPulses
        scheduleCmd.append(UInt8(numHalfHours))
        scheduleCmd.append(UInt8((secondsField >> 8) & 0xFF))
        scheduleCmd.append(UInt8(secondsField & 0xFF))
        scheduleCmd.append(UInt8((firstSegmentPulses >> 8) & 0xFF))
        scheduleCmd.append(UInt8(firstSegmentPulses & 0xFF))
        
        // Table entry
        scheduleCmd.append(tableEntry.data)
        
        // Send SetInsulinScheduleCommand (0x1A) first
        _ = try await bleManager.sendCommand(scheduleCmd)
        
        // Build TempBasalExtraCommand (0x16) (DASH-IMPL-002)
        let rateEntries = OmnipodRateEntry.makeEntries(rate: rate, duration: duration)
        let remainingPulses = rateEntries.first?.totalPulses ?? 0
        let delayUntilFirst = rateEntries.first?.delayBetweenPulses ?? OmnipodPodConstants.maxTimeBetweenPulses
        
        var extraCmd = Data()
        extraCmd.append(OmnipodOpcode.tempBasalExtra.rawValue)
        extraCmd.append(UInt8(8 + rateEntries.count * 6))
        extraCmd.append(beepOptions.encoded) // beep options (DASH-IMPL-004)
        extraCmd.append(0x00)
        
        let pulsesX10 = UInt16(round(remainingPulses * 10))
        extraCmd.append(UInt8((pulsesX10 >> 8) & 0xFF))
        extraCmd.append(UInt8(pulsesX10 & 0xFF))
        
        let delayHundredths = UInt32(delayUntilFirst * 100_000)
        extraCmd.append(UInt8((delayHundredths >> 24) & 0xFF))
        extraCmd.append(UInt8((delayHundredths >> 16) & 0xFF))
        extraCmd.append(UInt8((delayHundredths >> 8) & 0xFF))
        extraCmd.append(UInt8(delayHundredths & 0xFF))
        
        for entry in rateEntries {
            extraCmd.append(entry.data)
        }
        
        // Send TempBasalExtraCommand (0x16) second
        _ = try await bleManager.sendCommand(extraCmd)
        
        // Store as percent approximation
        let nominalBasal = 1.0
        let percent = Int((rate / nominalBasal) * 100)
        activeTempBasal = OmnipodTempBasal(percent: percent, duration: duration)
    }
    
    /// Cancel active temp basal
    /// Uses cancelDelivery (0x1F) opcode with nonce (DASH-IMPL-001)
    /// Format: 1F 05 NNNNNNNN DD (opcode, length, nonce, deliveryType)
    public func cancelTempBasal() async throws {
        PumpLogger.basal.tempBasalCancelled()
        
        // CancelDelivery requires nonce (DASH-IMPL-001)
        // deliveryType 0x02 = temp basal
        let payload = Data([0x02])
        let command = buildNoncedCommand(opcode: .cancelDelivery, payload: payload)
        _ = try await bleManager.sendCommand(command)
        
        activeTempBasal = nil
    }
    
    // MARK: - Bolus Commands
    
    /// Deliver bolus with proper pulse timing (DASH-IMPL-002, DASH-IMPL-004)
    /// Uses bolusExtra (0x17) opcode
    /// Format: 17 0D BB PPPP DDDDDDDD EEEE FFFFFFFF
    ///   BB = beep options, PPPP = pulses, DDDD = delay between pulses
    ///   EEEE = extended pulses, FFFF = extended delay
    public func deliverBolus(units: Double, beepOptions: OmnipodBeepOptions = .silent) async throws {
        guard units > 0 && units <= maxBolus else {
            throw OmnipodCommandError.invalidBolusAmount
        }
        
        // Round to increment
        let roundedUnits = (units / bolusIncrement).rounded() * bolusIncrement
        
        guard podState == .running else {
            throw OmnipodCommandError.podNotReady
        }
        
        if let status = lastStatus {
            guard status.canDeliver else {
                throw OmnipodCommandError.podNotReady
            }
            guard !status.isBolusing else {
                throw OmnipodCommandError.bolusInProgress
            }
        }
        
        PumpLogger.bolus.bolusDelivered(units: roundedUnits)
        
        // Build BolusExtraCommand with proper pulse timing (DASH-IMPL-002)
        // Format: 17 0D BB PPPP DDDDDDDD EEEE FFFFFFFF
        var data = Data()
        data.append(OmnipodOpcode.bolusExtra.rawValue)
        data.append(0x0D) // fixed length for BolusExtraCommand
        data.append(beepOptions.encoded) // beep options (DASH-IMPL-004)
        
        // Immediate pulses (1/10th units, big-endian UInt16)
        let pulses = roundedUnits * OmnipodPodConstants.pulsesPerUnit
        let pulsesX10 = UInt16(round(pulses * 10))
        data.append(UInt8((pulsesX10 >> 8) & 0xFF))
        data.append(UInt8(pulsesX10 & 0xFF))
        
        // Time between pulses (2 seconds, in hundredths of ms)
        let timeBetweenPulses = OmnipodPodConstants.secondsPerBolusPulse
        let delayHundredths = UInt32(timeBetweenPulses * 100_000)
        data.append(UInt8((delayHundredths >> 24) & 0xFF))
        data.append(UInt8((delayHundredths >> 16) & 0xFF))
        data.append(UInt8((delayHundredths >> 8) & 0xFF))
        data.append(UInt8(delayHundredths & 0xFF))
        
        // Extended bolus (none for immediate bolus)
        data.append(contentsOf: [0x00, 0x00]) // extended pulses = 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // extended delay = 0
        
        _ = try await bleManager.sendCommand(data)
    }
    
    /// Cancel in-progress bolus
    /// Uses cancelDelivery (0x1F) opcode with nonce (DASH-IMPL-001)
    /// Format: 1F 05 NNNNNNNN DD (opcode, length, nonce, deliveryType)
    public func cancelBolus() async throws {
        PumpLogger.bolus.info("Cancelling Omnipod bolus")
        
        // CancelDelivery requires nonce (DASH-IMPL-001)
        // deliveryType 0x04 = bolus
        let payload = Data([0x04])
        let command = buildNoncedCommand(opcode: .cancelDelivery, payload: payload)
        _ = try await bleManager.sendCommand(command)
    }
    
    /// Deliver extended (square wave) bolus over time (DASH-IMPL-003)
    /// Uses bolusExtra (0x17) opcode
    /// Format: 17 0D BB PPPP DDDDDDDD EEEE FFFFFFFF
    ///   BB = beep options, PPPP = immediate pulses, DDDD = immediate delay
    ///   EEEE = extended pulses, FFFF = extended delay (time between pulses)
    ///
    /// - Parameters:
    ///   - immediateUnits: Units to deliver immediately (0 for pure extended bolus)
    ///   - extendedUnits: Units to deliver over the extended duration
    ///   - extendedDuration: Duration to deliver extended units (seconds)
    ///   - beepOptions: Beep configuration
    public func deliverExtendedBolus(
        immediateUnits: Double = 0,
        extendedUnits: Double,
        extendedDuration: TimeInterval,
        beepOptions: OmnipodBeepOptions = .silent
    ) async throws {
        let totalUnits = immediateUnits + extendedUnits
        guard totalUnits > 0 && totalUnits <= maxBolus else {
            throw OmnipodCommandError.invalidBolusAmount
        }
        
        guard extendedUnits > 0 else {
            throw OmnipodCommandError.invalidBolusAmount
        }
        
        guard extendedDuration >= 30 * 60 else { // Minimum 30 minutes
            throw OmnipodCommandError.invalidDuration
        }
        
        guard extendedDuration <= 8 * 60 * 60 else { // Maximum 8 hours
            throw OmnipodCommandError.invalidDuration
        }
        
        guard podState == .running else {
            throw OmnipodCommandError.podNotReady
        }
        
        if let status = lastStatus {
            guard status.canDeliver else {
                throw OmnipodCommandError.podNotReady
            }
            guard !status.isBolusing else {
                throw OmnipodCommandError.bolusInProgress
            }
        }
        
        PumpLogger.bolus.info("Delivering extended bolus: \(immediateUnits)U immediate + \(extendedUnits)U over \(Int(extendedDuration/60)) min")
        
        // Build BolusExtraCommand (DASH-IMPL-003)
        // Format: 17 0D BB PPPP DDDDDDDD EEEE FFFFFFFF
        var data = Data()
        data.append(OmnipodOpcode.bolusExtra.rawValue)
        data.append(0x0D) // fixed length
        data.append(beepOptions.encoded) // beep options (DASH-IMPL-004)
        
        // Immediate pulses (pulses * 10, big-endian UInt16)
        let immediatePulses = immediateUnits * OmnipodPodConstants.pulsesPerUnit
        let immediatePulsesX10 = UInt16(round(immediatePulses * 10))
        data.append(UInt8((immediatePulsesX10 >> 8) & 0xFF))
        data.append(UInt8(immediatePulsesX10 & 0xFF))
        
        // Time between immediate pulses (2 seconds, in hundredths of ms)
        let immediateDelay: TimeInterval = immediateUnits > 0 ? OmnipodPodConstants.secondsPerBolusPulse : 0
        let immediateDelayHundredths = UInt32(immediateDelay * 100_000)
        data.append(UInt8((immediateDelayHundredths >> 24) & 0xFF))
        data.append(UInt8((immediateDelayHundredths >> 16) & 0xFF))
        data.append(UInt8((immediateDelayHundredths >> 8) & 0xFF))
        data.append(UInt8(immediateDelayHundredths & 0xFF))
        
        // Extended pulses (pulses * 10, big-endian UInt16)
        let extendedPulses = extendedUnits * OmnipodPodConstants.pulsesPerUnit
        let extendedPulsesX10 = UInt16(round(extendedPulses * 10))
        data.append(UInt8((extendedPulsesX10 >> 8) & 0xFF))
        data.append(UInt8(extendedPulsesX10 & 0xFF))
        
        // Time between extended pulses = duration / (pulses * 10 / 10)
        // = duration / actual pulse count
        let actualExtendedPulses = Double(extendedPulsesX10) / 10.0
        let timeBetweenExtendedPulses = actualExtendedPulses > 0 ? extendedDuration / actualExtendedPulses : 0
        let extendedDelayHundredths = UInt32(timeBetweenExtendedPulses * 100_000)
        data.append(UInt8((extendedDelayHundredths >> 24) & 0xFF))
        data.append(UInt8((extendedDelayHundredths >> 16) & 0xFF))
        data.append(UInt8((extendedDelayHundredths >> 8) & 0xFF))
        data.append(UInt8(extendedDelayHundredths & 0xFF))
        
        _ = try await bleManager.sendCommand(data)
    }
    
    // MARK: - Pod Lifecycle
    
    /// Deactivate pod (permanent)
    /// Uses deactivatePod (0x1C) opcode with nonce (DASH-IMPL-001)
    /// Format: 1C 04 NNNNNNNN (opcode, length, nonce)
    public func deactivate() async throws {
        PumpLogger.delivery.info("Deactivating Omnipod")
        
        // DeactivatePod requires nonce for security (DASH-IMPL-001)
        let command = buildNoncedCommand(opcode: .deactivatePod)
        _ = try await bleManager.sendCommand(command)
        
        podState = .deactivated
        activeTempBasal = nil
        lastStatus = nil
    }
    
    /// Acknowledge alerts
    /// Uses acknowledgeAlert (0x11) opcode with nonce (DASH-IMPL-001)
    /// Format: 11 05 NNNNNNNN MM (opcode, length, nonce, alertMask)
    public func acknowledgeAlerts(alertMask: UInt8 = 0xFF) async throws {
        PumpLogger.general.info("Acknowledging Omnipod alerts")
        
        // AcknowledgeAlert requires nonce (DASH-IMPL-001)
        let payload = Data([alertMask])
        let command = buildNoncedCommand(opcode: .acknowledgeAlert, payload: payload)
        _ = try await bleManager.sendCommand(command)
    }
    
    /// Silence alerts temporarily (via beep configuration)
    /// Uses beepConfig (0x1E) opcode
    public func silenceAlerts() async throws {
        PumpLogger.general.info("Silencing Omnipod alerts")
        
        let command = Data([OmnipodOpcode.beepConfig.rawValue])
        _ = try await bleManager.sendCommand(command)
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic info
    public func diagnosticInfo() async -> OmnipodCommanderDiagnostics {
        OmnipodCommanderDiagnostics(
            podState: podState,
            hasTempBasal: activeTempBasal != nil,
            tempBasalPercent: activeTempBasal?.percent,
            lastStatus: lastStatus
        )
    }
}

// MARK: - Diagnostics

/// Diagnostic information
public struct OmnipodCommanderDiagnostics: Sendable {
    public let podState: OmnipodPodState
    public let hasTempBasal: Bool
    public let tempBasalPercent: Int?
    public let lastStatus: OmnipodPodStatus?
    
    public var description: String {
        var parts: [String] = []
        parts.append("Pod: \(podState.displayName)")
        if hasTempBasal, let percent = tempBasalPercent {
            parts.append("TempBasal: \(percent)%")
        }
        if let status = lastStatus {
            parts.append("Reservoir: \(status.reservoirLevel)U")
            parts.append("Hours: \(String(format: "%.1f", status.hoursActive))")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Command Errors

/// Omnipod command errors
public enum OmnipodCommandError: Error, Sendable, Equatable {
    case notConnected
    case podNotReady
    case podDeactivated
    case invalidPercent
    case invalidDuration
    case invalidBolusAmount
    case invalidRate
    case bolusInProgress
    case commandFailed(String)
    case communicationFailed
    case timeout
    case podFaulted
    case invalidResponse
}

extension OmnipodCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to pod"
        case .podNotReady:
            return "Pod not ready for commands"
        case .podDeactivated:
            return "Pod has been deactivated"
        case .invalidPercent:
            return "Invalid temp basal percent (must be 0-200%)"
        case .invalidDuration:
            return "Invalid duration (must be 30min-12hr)"
        case .invalidBolusAmount:
            return "Invalid bolus amount"
        case .invalidRate:
            return "Invalid basal rate (must be 0-30 U/hr)"
        case .bolusInProgress:
            return "Bolus already in progress"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        case .communicationFailed:
            return "Communication failed"
        case .timeout:
            return "Command timed out"
        case .podFaulted:
            return "Pod has faulted"
        case .invalidResponse:
            return "Invalid response from pod"
        }
    }
}
