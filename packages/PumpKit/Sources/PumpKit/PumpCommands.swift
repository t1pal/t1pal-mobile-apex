// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpCommands.swift
// T1Pal Mobile
//
// Pump command types for insulin delivery
// Requirements: REQ-AID-001

import Foundation

// MARK: - Temp Basal Commands

/// Temp basal command to set temporary basal rate
public struct TempBasalCommand: Sendable, Equatable {
    public let rate: Double  // U/hr
    public let duration: TimeInterval  // seconds
    public let timestamp: Date
    
    public init(rate: Double, duration: TimeInterval, timestamp: Date = Date()) {
        self.rate = rate
        self.duration = duration
        self.timestamp = timestamp
    }
    
    /// Duration in minutes
    public var durationMinutes: Int {
        Int(duration / 60)
    }
    
    /// Total insulin to be delivered
    public var totalUnits: Double {
        rate * (duration / 3600)
    }
}

/// Active temp basal state
public struct TempBasalState: Sendable, Equatable {
    public let rate: Double
    public let startTime: Date
    public let endTime: Date
    
    public init(rate: Double, startTime: Date, endTime: Date) {
        self.rate = rate
        self.startTime = startTime
        self.endTime = endTime
    }
    
    public var isActive: Bool {
        Date() < endTime
    }
    
    public var remainingDuration: TimeInterval {
        max(0, endTime.timeIntervalSinceNow)
    }
}

// MARK: - Bolus Commands

/// Bolus type
public enum BolusType: String, Sendable, Codable {
    case normal
    case extended
    case square
    case combo
}

/// Bolus command for insulin delivery
public struct BolusCommand: Sendable, Equatable {
    public let units: Double
    public let type: BolusType
    public let duration: TimeInterval?  // For extended/square
    public let timestamp: Date
    
    public init(
        units: Double,
        type: BolusType = .normal,
        duration: TimeInterval? = nil,
        timestamp: Date = Date()
    ) {
        self.units = units
        self.type = type
        self.duration = duration
        self.timestamp = timestamp
    }
    
    /// Create a normal bolus
    public static func normal(_ units: Double) -> BolusCommand {
        BolusCommand(units: units, type: .normal)
    }
    
    /// Create an extended bolus
    public static func extended(_ units: Double, duration: TimeInterval) -> BolusCommand {
        BolusCommand(units: units, type: .extended, duration: duration)
    }
}

/// Bolus progress during delivery
public struct BolusProgress: Sendable {
    public let command: BolusCommand
    public let deliveredUnits: Double
    public let percentComplete: Double
    public let startTime: Date
    
    public init(command: BolusCommand, deliveredUnits: Double, startTime: Date) {
        self.command = command
        self.deliveredUnits = deliveredUnits
        self.percentComplete = command.units > 0 ? deliveredUnits / command.units : 0
        self.startTime = startTime
    }
    
    public var remainingUnits: Double {
        max(0, command.units - deliveredUnits)
    }
    
    public var isComplete: Bool {
        deliveredUnits >= command.units
    }
}

// MARK: - Suspend/Resume Commands

/// Suspend command
public struct SuspendCommand: Sendable, Equatable {
    public let timestamp: Date
    public let reason: SuspendReason?
    
    public init(timestamp: Date = Date(), reason: SuspendReason? = nil) {
        self.timestamp = timestamp
        self.reason = reason
    }
}

/// Reason for pump suspension
public enum SuspendReason: String, Sendable, Codable {
    case userRequested
    case lowGlucose
    case predictedLow
    case occlusion
    case reservoirEmpty
    case podExpired
}

/// Resume command
public struct ResumeCommand: Sendable, Equatable {
    public let timestamp: Date
    
    public init(timestamp: Date = Date()) {
        self.timestamp = timestamp
    }
}

// MARK: - Command Result

/// Result of a pump command
public enum PumpCommandResult: Sendable, Equatable {
    case success
    case pending
    case failed(PumpError)
    case cancelled
}

/// Queued command awaiting execution
public struct QueuedCommand: Sendable, Identifiable {
    public let id: UUID
    public let command: PumpCommand
    public let enqueuedAt: Date
    public var status: PumpCommandResult
    
    public init(command: PumpCommand, enqueuedAt: Date = Date()) {
        self.id = UUID()
        self.command = command
        self.enqueuedAt = enqueuedAt
        self.status = .pending
    }
}

/// Union type for all pump commands
public enum PumpCommand: Sendable {
    case tempBasal(TempBasalCommand)
    case cancelTempBasal
    case bolus(BolusCommand)
    case cancelBolus
    case suspend(SuspendCommand)
    case resume(ResumeCommand)
    
    public var displayName: String {
        switch self {
        case .tempBasal(let cmd):
            return "Temp Basal \(cmd.rate) U/hr"
        case .cancelTempBasal:
            return "Cancel Temp Basal"
        case .bolus(let cmd):
            return "Bolus \(cmd.units) U"
        case .cancelBolus:
            return "Cancel Bolus"
        case .suspend:
            return "Suspend"
        case .resume:
            return "Resume"
        }
    }
}

// MARK: - Delivery State

/// Current delivery state of the pump
public struct DeliveryState: Sendable {
    public let basalRate: Double  // Current scheduled basal
    public let tempBasal: TempBasalState?
    public let bolusInProgress: BolusProgress?
    public let isSuspended: Bool
    public let suspendedAt: Date?
    
    public init(
        basalRate: Double = 0,
        tempBasal: TempBasalState? = nil,
        bolusInProgress: BolusProgress? = nil,
        isSuspended: Bool = false,
        suspendedAt: Date? = nil
    ) {
        self.basalRate = basalRate
        self.tempBasal = tempBasal
        self.bolusInProgress = bolusInProgress
        self.isSuspended = isSuspended
        self.suspendedAt = suspendedAt
    }
    
    /// Effective basal rate (temp if active, else scheduled)
    public var effectiveBasalRate: Double {
        if isSuspended { return 0 }
        if let temp = tempBasal, temp.isActive {
            return temp.rate
        }
        return basalRate
    }
}
