// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpCommandDelivery.swift
// T1Pal Mobile
//
// Pump command delivery with retry logic, history tracking, safety checks
// Requirements: PROD-AID-003, REQ-SAFETY-001
//
// Trace: PROD-AID-003, PRD-009

import Foundation
import T1PalCore

// MARK: - Pump Command Types

/// Types of pump commands
public enum PumpCommandType: String, Codable, Sendable, CaseIterable {
    case tempBasal = "temp_basal"
    case cancelTempBasal = "cancel_temp_basal"
    case bolus = "bolus"
    case smb = "smb"
    case suspend = "suspend"
    case resume = "resume"
}

/// Status of a pump command
public enum PumpCommandStatus: String, Codable, Sendable {
    case pending = "pending"
    case inProgress = "in_progress"
    case success = "success"
    case failed = "failed"
    case retrying = "retrying"
    case cancelled = "cancelled"
    case timeout = "timeout"
}

// MARK: - Pump Command

/// A command to be sent to the pump
public struct PumpCommand: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let type: PumpCommandType
    public let timestamp: Date
    
    /// Temp basal rate (U/hr) - for temp_basal commands
    public let tempBasalRate: Double?
    
    /// Temp basal duration (seconds) - for temp_basal commands
    public let tempBasalDuration: TimeInterval?
    
    /// Bolus amount (units) - for bolus/smb commands
    public let bolusAmount: Double?
    
    /// Source of the command
    public let source: PumpCommandSource
    
    /// Current status
    public var status: PumpCommandStatus
    
    /// Retry count
    public var retryCount: Int
    
    /// Error message if failed
    public var errorMessage: String?
    
    /// Completion timestamp
    public var completedAt: Date?
    
    public init(
        id: UUID = UUID(),
        type: PumpCommandType,
        timestamp: Date = Date(),
        tempBasalRate: Double? = nil,
        tempBasalDuration: TimeInterval? = nil,
        bolusAmount: Double? = nil,
        source: PumpCommandSource = .algorithm,
        status: PumpCommandStatus = .pending,
        retryCount: Int = 0,
        errorMessage: String? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.tempBasalRate = tempBasalRate
        self.tempBasalDuration = tempBasalDuration
        self.bolusAmount = bolusAmount
        self.source = source
        self.status = status
        self.retryCount = retryCount
        self.errorMessage = errorMessage
        self.completedAt = completedAt
    }
    
    /// Age of command in seconds
    public var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    /// Create temp basal command
    public static func tempBasal(rate: Double, duration: TimeInterval, source: PumpCommandSource = .algorithm) -> PumpCommand {
        PumpCommand(
            type: .tempBasal,
            tempBasalRate: rate,
            tempBasalDuration: duration,
            source: source
        )
    }
    
    /// Create cancel temp basal command
    public static func cancelTempBasal(source: PumpCommandSource = .algorithm) -> PumpCommand {
        PumpCommand(type: .cancelTempBasal, source: source)
    }
    
    /// Create bolus command
    public static func bolus(amount: Double, source: PumpCommandSource = .user) -> PumpCommand {
        PumpCommand(type: .bolus, bolusAmount: amount, source: source)
    }
    
    /// Create SMB command
    public static func smb(amount: Double) -> PumpCommand {
        PumpCommand(type: .smb, bolusAmount: amount, source: .algorithm)
    }
    
    /// Create suspend command
    public static func suspend(source: PumpCommandSource = .user) -> PumpCommand {
        PumpCommand(type: .suspend, source: source)
    }
    
    /// Create resume command
    public static func resume(source: PumpCommandSource = .user) -> PumpCommand {
        PumpCommand(type: .resume, source: source)
    }
}

/// Source of pump command
public enum PumpCommandSource: String, Codable, Sendable, CaseIterable {
    case algorithm = "algorithm"
    case user = "user"
    case safety = "safety"
    case manual = "manual"
}

// MARK: - Pump Command Result

/// Result of executing a pump command
public struct PumpCommandResult: Sendable {
    public let command: PumpCommand
    public let success: Bool
    public let errorMessage: String?
    public let duration: TimeInterval
    public let retryCount: Int
    
    public init(
        command: PumpCommand,
        success: Bool,
        errorMessage: String? = nil,
        duration: TimeInterval = 0,
        retryCount: Int = 0
    ) {
        self.command = command
        self.success = success
        self.errorMessage = errorMessage
        self.duration = duration
        self.retryCount = retryCount
    }
}

// MARK: - Command Delivery Configuration

/// Configuration for pump command delivery
public struct PumpCommandDeliveryConfiguration: Sendable, Codable {
    /// Maximum retries for failed commands
    public let maxRetries: Int
    
    /// Delay between retries in seconds
    public let retryDelay: TimeInterval
    
    /// Command timeout in seconds
    public let commandTimeout: TimeInterval
    
    /// Minimum interval between SMBs in seconds
    public let minimumSMBInterval: TimeInterval
    
    /// Maximum SMB size in units
    public let maxSMBSize: Double
    
    /// Maximum temp basal rate (U/hr)
    public let maxTempBasalRate: Double
    
    /// Maximum temp basal duration (seconds)
    public let maxTempBasalDuration: TimeInterval
    
    /// Whether to allow SMB delivery
    public let smbEnabled: Bool
    
    public init(
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 2.0,
        commandTimeout: TimeInterval = 30.0,
        minimumSMBInterval: TimeInterval = 180.0,  // 3 minutes
        maxSMBSize: Double = 1.0,
        maxTempBasalRate: Double = 10.0,
        maxTempBasalDuration: TimeInterval = 1800,  // 30 minutes
        smbEnabled: Bool = false
    ) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.commandTimeout = commandTimeout
        self.minimumSMBInterval = minimumSMBInterval
        self.maxSMBSize = maxSMBSize
        self.maxTempBasalRate = maxTempBasalRate
        self.maxTempBasalDuration = maxTempBasalDuration
        self.smbEnabled = smbEnabled
    }
    
    /// Default safe configuration
    public static let `default` = PumpCommandDeliveryConfiguration()
    
    /// Aggressive configuration (SMB enabled)
    public static let aggressive = PumpCommandDeliveryConfiguration(
        maxRetries: 5,
        retryDelay: 1.0,
        maxSMBSize: 1.5,
        smbEnabled: true
    )
    
    /// Conservative configuration
    public static let conservative = PumpCommandDeliveryConfiguration(
        maxRetries: 2,
        retryDelay: 3.0,
        maxSMBSize: 0.5,
        maxTempBasalRate: 5.0,
        smbEnabled: false
    )
}

// MARK: - Command History

/// History of pump commands
public struct PumpCommandHistory: Sendable, Codable {
    public var commands: [PumpCommand]
    
    /// Maximum entries to keep
    public static let maxEntries = 288  // 24 hours of commands
    
    public init(commands: [PumpCommand] = []) {
        self.commands = commands
    }
    
    /// Add a command to history
    public mutating func addCommand(_ command: PumpCommand) {
        commands.insert(command, at: 0)
        if commands.count > Self.maxEntries {
            commands = Array(commands.prefix(Self.maxEntries))
        }
    }
    
    /// Update command status
    public mutating func updateCommand(_ id: UUID, status: PumpCommandStatus, error: String? = nil, completedAt: Date? = nil) {
        if let index = commands.firstIndex(where: { $0.id == id }) {
            commands[index].status = status
            commands[index].errorMessage = error
            commands[index].completedAt = completedAt ?? Date()
        }
    }
    
    /// Get commands from last N hours
    public func commands(lastHours: Int) -> [PumpCommand] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        return commands.filter { $0.timestamp >= cutoff }
    }
    
    /// Get last command of specific type
    public func lastCommand(of type: PumpCommandType) -> PumpCommand? {
        commands.first { $0.type == type && $0.status == .success }
    }
    
    /// Get total insulin delivered in last N hours
    public func insulinDelivered(lastHours: Int) -> Double {
        let recent = commands(lastHours: lastHours)
        return recent
            .filter { $0.status == .success && ($0.type == .bolus || $0.type == .smb) }
            .compactMap { $0.bolusAmount }
            .reduce(0, +)
    }
}

// MARK: - Command Delivery Statistics

/// Statistics for command delivery
public struct PumpCommandStatistics: Sendable {
    public let totalCommands: Int
    public let successfulCommands: Int
    public let failedCommands: Int
    public let retryCommands: Int
    public let tempBasalCommands: Int
    public let bolusCommands: Int
    public let smbCommands: Int
    public let averageDeliveryTime: TimeInterval
    public let successRate: Double
    
    public init(
        totalCommands: Int,
        successfulCommands: Int,
        failedCommands: Int,
        retryCommands: Int,
        tempBasalCommands: Int,
        bolusCommands: Int,
        smbCommands: Int,
        averageDeliveryTime: TimeInterval,
        successRate: Double
    ) {
        self.totalCommands = totalCommands
        self.successfulCommands = successfulCommands
        self.failedCommands = failedCommands
        self.retryCommands = retryCommands
        self.tempBasalCommands = tempBasalCommands
        self.bolusCommands = bolusCommands
        self.smbCommands = smbCommands
        self.averageDeliveryTime = averageDeliveryTime
        self.successRate = successRate
    }
    
    /// Calculate from history
    public static func from(history: PumpCommandHistory, lastHours: Int = 24) -> PumpCommandStatistics {
        let commands = history.commands(lastHours: lastHours)
        let total = commands.count
        let successful = commands.filter { $0.status == .success }.count
        let failed = commands.filter { $0.status == .failed }.count
        let retried = commands.filter { $0.retryCount > 0 }.count
        let tempBasal = commands.filter { $0.type == .tempBasal || $0.type == .cancelTempBasal }.count
        let bolus = commands.filter { $0.type == .bolus }.count
        let smb = commands.filter { $0.type == .smb }.count
        
        let rate = total > 0 ? Double(successful) / Double(total) * 100 : 0
        let avgTime: TimeInterval = 0  // Would need timing data
        
        return PumpCommandStatistics(
            totalCommands: total,
            successfulCommands: successful,
            failedCommands: failed,
            retryCommands: retried,
            tempBasalCommands: tempBasal,
            bolusCommands: bolus,
            smbCommands: smb,
            averageDeliveryTime: avgTime,
            successRate: rate
        )
    }
}

// MARK: - Command Delivery Errors

/// Errors for pump command delivery
public enum PumpCommandError: Error, LocalizedError {
    case pumpNotConnected
    case commandTimeout
    case maxRetriesExceeded
    case commandRejected(String)
    case safetyLimitExceeded(String)
    case invalidCommand(String)
    case communicationError(String)
    case smbNotEnabled
    case smbTooSoon(remainingSeconds: TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .pumpNotConnected:
            return "Pump is not connected"
        case .commandTimeout:
            return "Command timed out"
        case .maxRetriesExceeded:
            return "Maximum retries exceeded"
        case .commandRejected(let reason):
            return "Command rejected: \(reason)"
        case .safetyLimitExceeded(let reason):
            return "Safety limit exceeded: \(reason)"
        case .invalidCommand(let reason):
            return "Invalid command: \(reason)"
        case .communicationError(let message):
            return "Communication error: \(message)"
        case .smbNotEnabled:
            return "SMB delivery is not enabled"
        case .smbTooSoon(let remaining):
            return "SMB too soon, wait \(Int(remaining)) seconds"
        }
    }
}

// MARK: - Pump Command Delivery Manager

/// Manages pump command delivery with retry logic and safety checks
public actor PumpCommandDeliveryManager {
    
    // MARK: - State
    
    private var configuration: PumpCommandDeliveryConfiguration
    private var history: PumpCommandHistory = PumpCommandHistory()
    private var lastSMBTime: Date?
    private var pumpController: (any PumpController)?
    
    // MARK: - Callbacks
    
    public var onCommandComplete: (@Sendable (PumpCommandResult) -> Void)?
    public var onError: (@Sendable (PumpCommandError) -> Void)?
    
    // MARK: - Initialization
    
    public init(configuration: PumpCommandDeliveryConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Configure with pump controller
    public func configure(pumpController: any PumpController) {
        self.pumpController = pumpController
    }
    
    /// Update configuration
    public func updateConfiguration(_ config: PumpCommandDeliveryConfiguration) {
        self.configuration = config
    }
    
    // MARK: - Command Execution
    
    /// Execute a pump command with retry logic
    public func execute(_ command: PumpCommand) async -> PumpCommandResult {
        var mutableCommand = command
        let startTime = Date()
        
        // Validate command
        if let error = validateCommand(mutableCommand) {
            mutableCommand.status = .failed
            mutableCommand.errorMessage = error.localizedDescription
            mutableCommand.completedAt = Date()
            history.addCommand(mutableCommand)
            onError?(error)
            return PumpCommandResult(
                command: mutableCommand,
                success: false,
                errorMessage: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // Check pump connection
        guard let pump = pumpController else {
            mutableCommand.status = .failed
            mutableCommand.errorMessage = "Pump not configured"
            mutableCommand.completedAt = Date()
            history.addCommand(mutableCommand)
            let error = PumpCommandError.pumpNotConnected
            onError?(error)
            return PumpCommandResult(
                command: mutableCommand,
                success: false,
                errorMessage: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // Execute with retries
        var lastError: Error?
        mutableCommand.status = .inProgress
        history.addCommand(mutableCommand)
        
        for attempt in 0...configuration.maxRetries {
            if attempt > 0 {
                mutableCommand.status = .retrying
                mutableCommand.retryCount = attempt
                // Delay between retries
                try? await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
            }
            
            do {
                try await executeOnPump(mutableCommand, pump: pump)
                
                // Success
                mutableCommand.status = .success
                mutableCommand.completedAt = Date()
                
                // Update SMB timing
                if mutableCommand.type == .smb {
                    lastSMBTime = Date()
                }
                
                history.updateCommand(mutableCommand.id, status: .success, completedAt: Date())
                
                let result = PumpCommandResult(
                    command: mutableCommand,
                    success: true,
                    duration: Date().timeIntervalSince(startTime),
                    retryCount: attempt
                )
                onCommandComplete?(result)
                return result
                
            } catch {
                lastError = error
                continue
            }
        }
        
        // All retries failed
        mutableCommand.status = .failed
        mutableCommand.errorMessage = lastError?.localizedDescription ?? "Unknown error"
        mutableCommand.completedAt = Date()
        
        history.updateCommand(
            mutableCommand.id,
            status: .failed,
            error: mutableCommand.errorMessage,
            completedAt: Date()
        )
        
        let result = PumpCommandResult(
            command: mutableCommand,
            success: false,
            errorMessage: mutableCommand.errorMessage,
            duration: Date().timeIntervalSince(startTime),
            retryCount: configuration.maxRetries
        )
        onError?(.maxRetriesExceeded)
        return result
    }
    
    /// Execute from algorithm decision
    public func executeFromDecision(_ decision: AlgorithmDecision) async -> [PumpCommandResult] {
        var results: [PumpCommandResult] = []
        
        // Temp basal
        if let tempBasal = decision.suggestedTempBasal {
            let command = PumpCommand.tempBasal(
                rate: tempBasal.rate,
                duration: tempBasal.duration
            )
            let result = await execute(command)
            results.append(result)
        }
        
        // SMB
        if let smb = decision.suggestedBolus, smb > 0 {
            let command = PumpCommand.smb(amount: smb)
            let result = await execute(command)
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Convenience Methods
    
    /// Set temp basal
    public func setTempBasal(rate: Double, duration: TimeInterval) async -> PumpCommandResult {
        let command = PumpCommand.tempBasal(rate: rate, duration: duration)
        return await execute(command)
    }
    
    /// Cancel temp basal
    public func cancelTempBasal() async -> PumpCommandResult {
        let command = PumpCommand.cancelTempBasal()
        return await execute(command)
    }
    
    /// Deliver bolus
    public func deliverBolus(amount: Double) async -> PumpCommandResult {
        let command = PumpCommand.bolus(amount: amount)
        return await execute(command)
    }
    
    /// Deliver SMB
    public func deliverSMB(amount: Double) async -> PumpCommandResult {
        let command = PumpCommand.smb(amount: amount)
        return await execute(command)
    }
    
    /// Suspend delivery
    public func suspend() async -> PumpCommandResult {
        let command = PumpCommand.suspend()
        return await execute(command)
    }
    
    /// Resume delivery
    public func resume() async -> PumpCommandResult {
        let command = PumpCommand.resume()
        return await execute(command)
    }
    
    // MARK: - Statistics
    
    /// Get command statistics
    public func getStatistics(lastHours: Int = 24) -> PumpCommandStatistics {
        PumpCommandStatistics.from(history: history, lastHours: lastHours)
    }
    
    /// Get command history
    public func getHistory() -> PumpCommandHistory {
        history
    }
    
    /// Get total insulin delivered
    public func getInsulinDelivered(lastHours: Int = 24) -> Double {
        history.insulinDelivered(lastHours: lastHours)
    }
    
    // MARK: - Private Helpers
    
    private func validateCommand(_ command: PumpCommand) -> PumpCommandError? {
        switch command.type {
        case .tempBasal:
            guard let rate = command.tempBasalRate else {
                return .invalidCommand("Missing temp basal rate")
            }
            if rate < 0 {
                return .invalidCommand("Temp basal rate cannot be negative")
            }
            if rate > configuration.maxTempBasalRate {
                return .safetyLimitExceeded("Temp basal rate \(rate) exceeds max \(configuration.maxTempBasalRate)")
            }
            if let duration = command.tempBasalDuration, duration > configuration.maxTempBasalDuration {
                return .safetyLimitExceeded("Temp basal duration exceeds max")
            }
            
        case .smb:
            if !configuration.smbEnabled {
                return .smbNotEnabled
            }
            guard let amount = command.bolusAmount else {
                return .invalidCommand("Missing SMB amount")
            }
            if amount <= 0 {
                return .invalidCommand("SMB amount must be positive")
            }
            if amount > configuration.maxSMBSize {
                return .safetyLimitExceeded("SMB size \(amount) exceeds max \(configuration.maxSMBSize)")
            }
            // Check timing
            if let lastSMB = lastSMBTime {
                let elapsed = Date().timeIntervalSince(lastSMB)
                if elapsed < configuration.minimumSMBInterval {
                    let remaining = configuration.minimumSMBInterval - elapsed
                    return .smbTooSoon(remainingSeconds: remaining)
                }
            }
            
        case .bolus:
            guard let amount = command.bolusAmount else {
                return .invalidCommand("Missing bolus amount")
            }
            if amount <= 0 {
                return .invalidCommand("Bolus amount must be positive")
            }
            
        case .cancelTempBasal, .suspend, .resume:
            // No validation needed
            break
        }
        
        return nil
    }
    
    private func executeOnPump(_ command: PumpCommand, pump: any PumpController) async throws {
        switch command.type {
        case .tempBasal:
            guard let rate = command.tempBasalRate,
                  let duration = command.tempBasalDuration else {
                throw PumpCommandError.invalidCommand("Missing temp basal parameters")
            }
            try await pump.setTempBasal(rate: rate, duration: duration)
            
        case .cancelTempBasal:
            try await pump.cancelTempBasal()
            
        case .bolus, .smb:
            guard let amount = command.bolusAmount else {
                throw PumpCommandError.invalidCommand("Missing bolus amount")
            }
            try await pump.deliverBolus(units: amount)
            
        case .suspend:
            // Suspend = zero temp for 30 minutes
            try await pump.setTempBasal(rate: 0, duration: 1800)
            
        case .resume:
            try await pump.cancelTempBasal()
        }
    }
}

// MARK: - Testing Helpers

/// Mock pump command delivery manager for testing
public actor MockPumpCommandDeliveryManager {
    public var executeCallCount = 0
    public var lastCommand: PumpCommand?
    public var mockResult: PumpCommandResult?
    private var shouldFail = false
    
    public init() {}
    
    public func setFail(_ fail: Bool) {
        shouldFail = fail
    }
    
    public func execute(_ command: PumpCommand) async -> PumpCommandResult {
        executeCallCount += 1
        lastCommand = command
        
        if shouldFail {
            return PumpCommandResult(
                command: command,
                success: false,
                errorMessage: "Mock failure"
            )
        }
        
        return mockResult ?? PumpCommandResult(
            command: command,
            success: true,
            duration: 1.0
        )
    }
}
