// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaCommands.swift
// PumpKit
//
// High-level Dana pump command implementations.
// Uses DanaBLEManager for BLE communication.
// Trace: PUMP-DANA-005, PRD-005
//
// Usage:
//   let commander = DanaCommander(manager: bleManager)
//   let status = try await commander.getStatus()
//   try await commander.setTempBasal(percent: 150, duration: 30)

import Foundation

// MARK: - Data Extension for UInt16 Parsing

extension Data {
    /// Read little-endian UInt16 at offset
    func uint16(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
}

// MARK: - Dana Command Opcodes

/// Dana pump command specification (type + opcode)
public struct DanaCommand: Sendable, Equatable {
    public let type: DanaMessageType
    public let opcode: UInt8
    public let name: String
    public let isWrite: Bool
    
    public init(type: DanaMessageType, opcode: UInt8, name: String, isWrite: Bool = false) {
        self.type = type
        self.opcode = opcode
        self.name = name
        self.isWrite = isWrite
    }
    
    public var displayName: String { name }
}

/// Standard Dana commands by category
public enum DanaCommands {
    // General commands (type 0x01)
    public static let getInitialScreen = DanaCommand(type: .general, opcode: 0x02, name: "Get Initial Screen")
    public static let getPumpCheck = DanaCommand(type: .general, opcode: 0x00, name: "Get Pump Check")
    public static let getShippingInfo = DanaCommand(type: .general, opcode: 0x06, name: "Get Shipping Info")
    public static let getPumpTime = DanaCommand(type: .general, opcode: 0x07, name: "Get Pump Time")
    public static let setPumpTime = DanaCommand(type: .general, opcode: 0x08, name: "Set Pump Time", isWrite: true)
    public static let getProfile = DanaCommand(type: .general, opcode: 0x0B, name: "Get Profile")
    public static let getBasicProfile = DanaCommand(type: .general, opcode: 0x0C, name: "Get Basic Profile")
    public static let getBolusOption = DanaCommand(type: .general, opcode: 0x0F, name: "Get Bolus Option")
    
    // Basal commands (type 0x02)
    public static let getTempBasalState = DanaCommand(type: .basal, opcode: 0x03, name: "Get Temp Basal State")
    public static let setTempBasal = DanaCommand(type: .basal, opcode: 0x01, name: "Set Temp Basal", isWrite: true)
    public static let cancelTempBasal = DanaCommand(type: .basal, opcode: 0x02, name: "Cancel Temp Basal", isWrite: true)
    public static let getBasalRate = DanaCommand(type: .basal, opcode: 0x04, name: "Get Basal Rate")
    public static let setBasalProfile = DanaCommand(type: .basal, opcode: 0x05, name: "Set Basal Profile", isWrite: true)
    
    // CRIT-PROFILE-013: Full 24-hour schedule commands (DanaKit opcodes)
    public static let getBasalSchedule = DanaCommand(type: .basal, opcode: 0x67, name: "Get Basal Schedule")
    public static let setBasalSchedule = DanaCommand(type: .basal, opcode: 0x68, name: "Set Basal Schedule", isWrite: true)
    public static let getProfileNumber = DanaCommand(type: .basal, opcode: 0x63, name: "Get Profile Number")
    public static let setProfileNumber = DanaCommand(type: .basal, opcode: 0x64, name: "Set Profile Number", isWrite: true)
    
    // Bolus commands (type 0x03)
    public static let setBolus = DanaCommand(type: .bolus, opcode: 0x01, name: "Set Bolus", isWrite: true)
    public static let setExtendedBolus = DanaCommand(type: .bolus, opcode: 0x02, name: "Set Extended Bolus", isWrite: true)
    public static let cancelBolus = DanaCommand(type: .bolus, opcode: 0x03, name: "Cancel Bolus", isWrite: true)
    public static let getBolusProgress = DanaCommand(type: .bolus, opcode: 0x04, name: "Get Bolus Progress")
    public static let setBolusOption = DanaCommand(type: .bolus, opcode: 0x05, name: "Set Bolus Option", isWrite: true)
    
    // Option commands (type 0x04)
    public static let getOption = DanaCommand(type: .option, opcode: 0x01, name: "Get Option")
    public static let setOption = DanaCommand(type: .option, opcode: 0x02, name: "Set Option", isWrite: true)
    public static let getUserSettings = DanaCommand(type: .option, opcode: 0x03, name: "Get User Settings")
    public static let setUserSettings = DanaCommand(type: .option, opcode: 0x04, name: "Set User Settings", isWrite: true)
    
    // ETC commands (type 0x05)
    public static let suspend = DanaCommand(type: .etc, opcode: 0x01, name: "Suspend", isWrite: true)
    public static let resume = DanaCommand(type: .etc, opcode: 0x02, name: "Resume", isWrite: true)
    public static let getHistoryInfo = DanaCommand(type: .etc, opcode: 0x03, name: "Get History Info")
    public static let getHistory = DanaCommand(type: .etc, opcode: 0x04, name: "Get History")
}

// MARK: - Dana Basal Schedule (CRIT-PROFILE-013)

/// Full 24-hour basal schedule for Dana pumps
/// Contains hourly basal rates (U/hr) for each hour of the day
/// Trace: CRIT-PROFILE-013
public struct DanaBasalSchedule: Sendable, Equatable {
    /// Maximum basal rate supported by pump (U/hr)
    public let maxBasal: Double
    
    /// Basal rate step/increment (U/hr)
    public let basalStep: Double
    
    /// Array of 24 hourly rates (index 0 = midnight, 23 = 11 PM)
    public let hourlyRates: [Double]
    
    public init(maxBasal: Double, basalStep: Double, hourlyRates: [Double]) {
        self.maxBasal = maxBasal
        self.basalStep = basalStep
        self.hourlyRates = hourlyRates
    }
    
    /// Parse from Dana response data
    /// Format: [maxBasal (2 bytes)][basalStep (1 byte)][24 rates × 2 bytes]
    /// Each value is UInt16 / 100.0
    public static func parse(from data: Data) -> DanaBasalSchedule? {
        // Minimum: 2 (maxBasal) + 1 (step) + 48 (24 rates × 2) = 51 bytes
        guard data.count >= 51 else {
            return nil
        }
        
        let maxBasal = Double(data.uint16(at: 0)) / 100.0
        let basalStep = Double(data[2]) / 100.0
        
        var rates: [Double] = []
        for hour in 0..<24 {
            let offset = 3 + hour * 2
            let rateValue = Double(data.uint16(at: offset)) / 100.0
            rates.append(rateValue)
        }
        
        return DanaBasalSchedule(maxBasal: maxBasal, basalStep: basalStep, hourlyRates: rates)
    }
    
    /// Encode to data for write command
    /// Format: 24 rates × 2 bytes (UInt16, value × 100)
    public var rawData: Data {
        var data = Data()
        for rate in hourlyRates {
            let encoded = UInt16(rate * 100.0)
            data.append(UInt8(encoded & 0xFF))
            data.append(UInt8(encoded >> 8))
        }
        return data
    }
    
    /// Get rate for a specific hour (0-23)
    public func rate(forHour hour: Int) -> Double? {
        guard hour >= 0 && hour < 24 && hour < hourlyRates.count else {
            return nil
        }
        return hourlyRates[hour]
    }
    
    /// Total daily basal (sum of hourly rates)
    public var totalDailyBasal: Double {
        hourlyRates.reduce(0, +)
    }
    
    /// Demo schedule for testing
    public static var demo: DanaBasalSchedule {
        DanaBasalSchedule(
            maxBasal: 3.0,
            basalStep: 0.01,
            hourlyRates: [
                0.8, 0.8, 0.8, 0.8, 0.9, 1.0,  // 00:00 - 05:00
                1.2, 1.0, 0.9, 0.8, 0.8, 0.8,  // 06:00 - 11:00
                0.9, 0.9, 0.8, 0.8, 0.9, 1.0,  // 12:00 - 17:00
                1.1, 1.0, 0.9, 0.8, 0.8, 0.8   // 18:00 - 23:00
            ]
        )
    }
}

// MARK: - Dana Pump Status

/// Complete Dana pump status
public struct DanaPumpStatus: Sendable, Equatable {
    public let errorState: DanaErrorState
    public let reservoirLevel: Double  // Units remaining
    public let batteryPercent: Int
    public let isSuspended: Bool
    public let isTempBasalActive: Bool
    public let tempBasalPercent: Int?
    public let tempBasalRemainingMinutes: Int?
    public let isExtendedBolusActive: Bool
    public let dailyTotalUnits: Double
    public let currentBasalRate: Double  // U/hr
    
    public init(
        errorState: DanaErrorState = .none,
        reservoirLevel: Double,
        batteryPercent: Int,
        isSuspended: Bool = false,
        isTempBasalActive: Bool = false,
        tempBasalPercent: Int? = nil,
        tempBasalRemainingMinutes: Int? = nil,
        isExtendedBolusActive: Bool = false,
        dailyTotalUnits: Double = 0,
        currentBasalRate: Double = 0
    ) {
        self.errorState = errorState
        self.reservoirLevel = reservoirLevel
        self.batteryPercent = batteryPercent
        self.isSuspended = isSuspended
        self.isTempBasalActive = isTempBasalActive
        self.tempBasalPercent = tempBasalPercent
        self.tempBasalRemainingMinutes = tempBasalRemainingMinutes
        self.isExtendedBolusActive = isExtendedBolusActive
        self.dailyTotalUnits = dailyTotalUnits
        self.currentBasalRate = currentBasalRate
    }
    
    public var canDeliver: Bool {
        !isSuspended && errorState.canDeliver
    }
    
    public var isLowReservoir: Bool {
        reservoirLevel < 20.0
    }
    
    public var isLowBattery: Bool {
        batteryPercent < 20
    }
}

// MARK: - Dana Temp Basal

/// Dana temp basal (percent-based)
public struct DanaTempBasal: Sendable, Equatable {
    public let percent: Int           // 0-200 percent
    public let duration: TimeInterval // Seconds
    public let startTime: Date
    
    public init(percent: Int, duration: TimeInterval, startTime: Date = Date()) {
        self.percent = percent
        self.duration = duration
        self.startTime = startTime
    }
    
    /// Duration in minutes (Dana uses 30-minute increments)
    public var durationMinutes: Int {
        Int(duration / 60)
    }
    
    /// End time of temp basal
    public var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    /// Whether temp basal has expired
    public var isExpired: Bool {
        Date() >= endTime
    }
    
    /// Remaining duration
    public var remainingDuration: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }
    
    /// Remaining minutes rounded up
    public var remainingMinutes: Int {
        Int(ceil(remainingDuration / 60))
    }
    
    /// Effective rate multiplier (1.0 = 100%)
    public var rateMultiplier: Double {
        Double(percent) / 100.0
    }
}

// MARK: - Dana Bolus State

/// Current bolus delivery state
public struct DanaBolusState: Sendable, Equatable {
    public let isDelivering: Bool
    public let requestedUnits: Double
    public let deliveredUnits: Double
    public let remainingUnits: Double
    public let startTime: Date?
    
    public init(
        isDelivering: Bool = false,
        requestedUnits: Double = 0,
        deliveredUnits: Double = 0,
        remainingUnits: Double = 0,
        startTime: Date? = nil
    ) {
        self.isDelivering = isDelivering
        self.requestedUnits = requestedUnits
        self.deliveredUnits = deliveredUnits
        self.remainingUnits = remainingUnits
        self.startTime = startTime
    }
    
    public var progress: Double {
        guard requestedUnits > 0 else { return 0 }
        return deliveredUnits / requestedUnits
    }
    
    public static let idle = DanaBolusState()
}

// MARK: - Dana Command Error

/// Dana-specific command errors
public enum DanaCommandError: Error, Sendable {
    case notConnected
    case notReady
    case suspended
    case invalidParameter(String)
    case commandFailed(DanaCommand, UInt8)
    case bolusInProgress
    case tempBasalActive
    case dailyMaxReached
    case timeout
    case communicationError(String)
}

extension DanaCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Dana pump not connected"
        case .notReady: return "Dana pump not ready for commands"
        case .suspended: return "Dana pump is suspended"
        case .invalidParameter(let param): return "Invalid parameter: \(param)"
        case .commandFailed(let cmd, let code): return "Command \(cmd.displayName) failed with code \(code)"
        case .bolusInProgress: return "Cannot change delivery while bolus in progress"
        case .tempBasalActive: return "Temp basal already active"
        case .dailyMaxReached: return "Daily maximum insulin reached"
        case .timeout: return "Command timed out"
        case .communicationError(let msg): return "Communication error: \(msg)"
        }
    }
}

// MARK: - Dana Commander

/// High-level Dana pump command interface
public actor DanaCommander {
    // MARK: - Properties
    
    private let manager: DanaBLEManager
    
    private(set) var lastStatus: DanaPumpStatus?
    private(set) var activeTempBasal: DanaTempBasal?
    private(set) var isSuspended: Bool = false
    private(set) var bolusState: DanaBolusState = .idle
    
    // Dana limits
    private let minTempBasalPercent = 0
    private let maxTempBasalPercent = 200
    private let maxTempBasalDuration: TimeInterval = 24 * 60 * 60 // 24 hours
    private let minBolusIncrement = 0.05
    private let maxBolusAmount = 25.0
    
    // MARK: - Init
    
    public init(manager: DanaBLEManager) {
        self.manager = manager
    }
    
    // MARK: - Connection Check
    
    private func ensureReady() async throws {
        let state = await manager.state
        guard state == .ready else {
            throw DanaCommandError.notReady
        }
    }
    
    private func ensureNotSuspended() throws {
        guard !isSuspended else {
            throw DanaCommandError.suspended
        }
    }
    
    private func ensureNoBolusInProgress() throws {
        guard !bolusState.isDelivering else {
            throw DanaCommandError.bolusInProgress
        }
    }
    
    // MARK: - Status Commands
    
    /// Get pump status
    public func getStatus() async throws -> DanaPumpStatus {
        try await ensureReady()
        
        PumpLogger.status.info("Reading Dana pump status")
        
        // Send status command
        let cmd = DanaCommands.getInitialScreen
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        // Simulated status response
        let status = DanaPumpStatus(
            errorState: .none,
            reservoirLevel: 180.0,
            batteryPercent: 85,
            isSuspended: isSuspended,
            isTempBasalActive: activeTempBasal != nil && !activeTempBasal!.isExpired,
            tempBasalPercent: activeTempBasal?.percent,
            tempBasalRemainingMinutes: activeTempBasal?.remainingMinutes,
            isExtendedBolusActive: false,
            dailyTotalUnits: 12.5,
            currentBasalRate: 0.8
        )
        
        lastStatus = status
        return status
    }
    
    /// Get current basal rate
    public func getBasalRate() async throws -> Double {
        try await ensureReady()
        
        let cmd = DanaCommands.getBasalRate
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        return 0.8 // Simulated U/hr
    }
    
    /// Get current temp basal state
    public func getTempBasalState() async throws -> DanaTempBasal? {
        try await ensureReady()
        
        let cmd = DanaCommands.getTempBasalState
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        // Return active temp basal if any
        if let tb = activeTempBasal, !tb.isExpired {
            return tb
        }
        
        return nil
    }
    
    // MARK: - Temp Basal Commands
    
    /// Set temp basal (percent-based)
    /// - Parameters:
    ///   - percent: Percent of basal (0-200)
    ///   - durationMinutes: Duration in minutes (must be multiple of 30)
    public func setTempBasal(percent: Int, durationMinutes: Int) async throws -> DanaTempBasal {
        try await ensureReady()
        try ensureNotSuspended()
        try ensureNoBolusInProgress()
        
        // Validate parameters
        guard percent >= minTempBasalPercent && percent <= maxTempBasalPercent else {
            throw DanaCommandError.invalidParameter("Percent must be \(minTempBasalPercent)-\(maxTempBasalPercent)")
        }
        
        guard durationMinutes > 0 && durationMinutes <= 1440 else {
            throw DanaCommandError.invalidParameter("Duration must be 1-1440 minutes")
        }
        
        // Dana uses 30-minute increments
        let roundedMinutes = ((durationMinutes + 15) / 30) * 30
        let clampedMinutes = min(max(roundedMinutes, 30), 1440)
        
        PumpLogger.delivery.info("Setting Dana temp basal: \(percent)% for \(clampedMinutes)min")
        
        // Build command: opcode + percent + duration
        let cmd = DanaCommands.setTempBasal
        var command = Data([cmd.opcode])
        command.append(UInt8(percent))
        command.append(UInt8(clampedMinutes / 30)) // Duration in 30-min increments
        
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        let duration = TimeInterval(clampedMinutes * 60)
        let tempBasal = DanaTempBasal(percent: percent, duration: duration)
        activeTempBasal = tempBasal
        
        return tempBasal
    }
    
    /// Cancel active temp basal
    public func cancelTempBasal() async throws {
        try await ensureReady()
        
        PumpLogger.delivery.info("Cancelling Dana temp basal")
        
        let cmd = DanaCommands.cancelTempBasal
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        activeTempBasal = nil
    }
    
    // MARK: - Bolus Commands
    
    /// Deliver bolus
    /// - Parameters:
    ///   - units: Amount in units (0.05 increment)
    ///   - speed: Bolus speed factor (1=normal, 2=slow, 3=slowest)
    public func deliverBolus(units: Double, speed: Int = 1) async throws {
        try await ensureReady()
        try ensureNotSuspended()
        try ensureNoBolusInProgress()
        
        // Validate
        guard units > 0 else {
            throw DanaCommandError.invalidParameter("Bolus must be > 0")
        }
        
        guard units <= maxBolusAmount else {
            throw DanaCommandError.invalidParameter("Bolus exceeds max \(maxBolusAmount)U")
        }
        
        // Round to increment
        let roundedUnits = (units / minBolusIncrement).rounded() * minBolusIncrement
        
        PumpLogger.delivery.info("Delivering Dana bolus: \(roundedUnits)U")
        
        bolusState = DanaBolusState(
            isDelivering: true,
            requestedUnits: roundedUnits,
            deliveredUnits: 0,
            remainingUnits: roundedUnits,
            startTime: Date()
        )
        
        // Build command: opcode + units (in 0.01U) + speed
        let cmd = DanaCommands.setBolus
        var command = Data([cmd.opcode])
        let unitsRaw = UInt16(roundedUnits * 100)
        command.append(UInt8(unitsRaw & 0xFF))
        command.append(UInt8((unitsRaw >> 8) & 0xFF))
        command.append(UInt8(speed))
        
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        // Simulate delivery completion
        bolusState = DanaBolusState(
            isDelivering: false,
            requestedUnits: roundedUnits,
            deliveredUnits: roundedUnits,
            remainingUnits: 0,
            startTime: bolusState.startTime
        )
    }
    
    /// Cancel active bolus
    public func cancelBolus() async throws {
        try await ensureReady()
        
        guard bolusState.isDelivering else { return }
        
        PumpLogger.delivery.info("Cancelling Dana bolus")
        
        let cmd = DanaCommands.cancelBolus
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        bolusState = DanaBolusState(
            isDelivering: false,
            requestedUnits: bolusState.requestedUnits,
            deliveredUnits: bolusState.deliveredUnits,
            remainingUnits: 0,
            startTime: bolusState.startTime
        )
    }
    
    /// Get bolus progress
    public func getBolusProgress() async throws -> DanaBolusState {
        try await ensureReady()
        
        let cmd = DanaCommands.getBolusProgress
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        return bolusState
    }
    
    // MARK: - Suspend/Resume
    
    /// Suspend insulin delivery
    public func suspend() async throws {
        try await ensureReady()
        try ensureNoBolusInProgress()
        
        PumpLogger.delivery.info("Suspending Dana pump")
        
        let cmd = DanaCommands.suspend
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        isSuspended = true
        
        // Cancel any active temp basal
        if activeTempBasal != nil {
            activeTempBasal = nil
        }
    }
    
    /// Resume insulin delivery
    public func resume() async throws {
        try await ensureReady()
        
        PumpLogger.delivery.info("Resuming Dana pump")
        
        let cmd = DanaCommands.resume
        let command = Data([cmd.opcode])
        _ = try await manager.sendCommand(command, type: cmd.type)
        
        isSuspended = false
    }
    
    // MARK: - Diagnostics
    
    /// Get command statistics
    public func commandStats() -> DanaCommandStats {
        DanaCommandStats(
            lastStatusCheck: lastStatus != nil ? Date() : nil,
            isSuspended: isSuspended,
            activeTempBasal: activeTempBasal,
            bolusInProgress: bolusState.isDelivering
        )
    }
}

// MARK: - Command Stats

/// Statistics about commander state
public struct DanaCommandStats: Sendable {
    public let lastStatusCheck: Date?
    public let isSuspended: Bool
    public let activeTempBasal: DanaTempBasal?
    public let bolusInProgress: Bool
    
    public var description: String {
        var parts: [String] = []
        if let last = lastStatusCheck {
            parts.append("Last status: \(last)")
        }
        if isSuspended {
            parts.append("SUSPENDED")
        }
        if let tb = activeTempBasal, !tb.isExpired {
            parts.append("Temp basal: \(tb.percent)%")
        }
        if bolusInProgress {
            parts.append("BOLUSING")
        }
        return parts.isEmpty ? "Idle" : parts.joined(separator: ", ")
    }
}
