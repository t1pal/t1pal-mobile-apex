// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RemoteCommandHandler.swift
// NightscoutKit
//
// Remote command types and execution for Nightscout careportal
// Extracted from NightscoutClient.swift (NS-REFACTOR-009)
// Requirements: REQ-NS-008

import Foundation

// MARK: - Remote Command Types

/// Remote command types supported by Nightscout careportal
public enum RemoteCommandType: String, Codable, Sendable, CaseIterable {
    case tempTarget = "Temporary Target"
    case cancelTempTarget = "Temporary Target Cancel"
    case profileSwitch = "Profile Switch"
    case announcement = "Announcement"
    case note = "Note"
    case question = "Question"
    case exercise = "Exercise"
    case pumpSiteChange = "Site Change"
    case cgmSensorInsert = "Sensor Start"
    case cgmSensorChange = "Sensor Change"
    case insulinChange = "Insulin Change"
    case bgCheck = "BG Check"
    case openapsOffline = "OpenAPS Offline"
    
    /// Commands that require OTP verification
    public var requiresOTP: Bool {
        switch self {
        case .tempTarget, .cancelTempTarget, .profileSwitch, .openapsOffline:
            return true
        default:
            return false
        }
    }
}

// MARK: - Remote Command

/// Remote command request
public struct RemoteCommand: Codable, Sendable {
    public let commandType: RemoteCommandType
    public let notes: String?
    public let duration: Double?          // Minutes for temp target
    public let targetTop: Double?         // High target mg/dL
    public let targetBottom: Double?      // Low target mg/dL
    public let reason: String?            // Reason for temp target
    public let profile: String?           // Profile name for switch
    public let glucose: Double?           // BG value for check
    public let glucoseType: String?       // "Finger" or "Sensor"
    public let otp: String?               // One-time password for secure commands
    public let enteredBy: String
    public let timestamp: Date
    
    public init(
        commandType: RemoteCommandType,
        notes: String? = nil,
        duration: Double? = nil,
        targetTop: Double? = nil,
        targetBottom: Double? = nil,
        reason: String? = nil,
        profile: String? = nil,
        glucose: Double? = nil,
        glucoseType: String? = nil,
        otp: String? = nil,
        enteredBy: String = "T1Pal",
        timestamp: Date = Date()
    ) {
        self.commandType = commandType
        self.notes = notes
        self.duration = duration
        self.targetTop = targetTop
        self.targetBottom = targetBottom
        self.reason = reason
        self.profile = profile
        self.glucose = glucose
        self.glucoseType = glucoseType
        self.otp = otp
        self.enteredBy = enteredBy
        self.timestamp = timestamp
    }
    
    /// Convert to NightscoutTreatment for upload
    public func toTreatment() -> NightscoutTreatment {
        let formatter = ISO8601DateFormatter()
        
        return NightscoutTreatment(
            eventType: commandType.rawValue,
            created_at: formatter.string(from: timestamp),
            duration: duration,
            targetTop: targetTop,
            targetBottom: targetBottom,
            glucose: glucose,
            glucoseType: glucoseType,
            enteredBy: enteredBy,
            notes: notes,
            reason: reason
        )
    }
}

// MARK: - Remote Command Result

/// Result of remote command execution
public struct RemoteCommandResult: Sendable {
    public let success: Bool
    public let command: RemoteCommand
    public let error: Error?
    public let requiresOTP: Bool
    public let timestamp: Date
    
    public init(
        success: Bool,
        command: RemoteCommand,
        error: Error? = nil,
        requiresOTP: Bool = false,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.command = command
        self.error = error
        self.requiresOTP = requiresOTP
        self.timestamp = timestamp
    }
}

// MARK: - Remote Command Error

/// Error types for remote commands
public enum RemoteCommandError: Error, Sendable, LocalizedError {
    case otpRequired
    case otpInvalid
    case commandNotSupported
    case networkError(String)
    case serverError(Int)
    case unauthorized
    
    public var errorDescription: String? {
        switch self {
        case .otpRequired:
            return "One-time password required for this command."
        case .otpInvalid:
            return "Invalid one-time password. Please try again."
        case .commandNotSupported:
            return "This remote command is not supported."
        case .networkError(let message):
            return "Network error sending command: \(message)"
        case .serverError(let code):
            return "Server error (\(code)) processing command."
        case .unauthorized:
            return "Not authorized to send remote commands."
        }
    }
}

// MARK: - Remote Command Manager

/// Manager for executing remote commands via Nightscout
/// Requirements: REQ-NS-008
public actor RemoteCommandManager {
    private let client: NightscoutClient
    private var commandHistory: [RemoteCommandResult] = []
    private var pendingCommands: [RemoteCommand] = []
    
    public init(client: NightscoutClient) {
        self.client = client
    }
    
    /// Execute a remote command
    public func execute(_ command: RemoteCommand) async throws -> RemoteCommandResult {
        // Check if OTP is required
        if command.commandType.requiresOTP && command.otp == nil {
            let result = RemoteCommandResult(
                success: false,
                command: command,
                error: RemoteCommandError.otpRequired,
                requiresOTP: true
            )
            commandHistory.append(result)
            return result
        }
        
        do {
            // Convert to treatment and upload
            let treatment = command.toTreatment()
            try await client.uploadTreatments([treatment])
            
            let result = RemoteCommandResult(success: true, command: command)
            commandHistory.append(result)
            return result
        } catch {
            let result = RemoteCommandResult(
                success: false,
                command: command,
                error: error
            )
            commandHistory.append(result)
            throw error
        }
    }
    
    /// Queue a command for later execution
    public func queue(_ command: RemoteCommand) {
        pendingCommands.append(command)
    }
    
    /// Execute all pending commands
    public func executePending() async -> [RemoteCommandResult] {
        var results: [RemoteCommandResult] = []
        
        while !pendingCommands.isEmpty {
            let command = pendingCommands.removeFirst()
            do {
                let result = try await execute(command)
                results.append(result)
            } catch {
                results.append(RemoteCommandResult(
                    success: false,
                    command: command,
                    error: error
                ))
            }
        }
        
        return results
    }
    
    /// Get command history
    public func getHistory() -> [RemoteCommandResult] {
        commandHistory
    }
    
    /// Get pending commands count
    public func getPendingCount() -> Int {
        pendingCommands.count
    }
    
    /// Clear command history
    public func clearHistory() {
        commandHistory = []
    }
    
    // MARK: - Convenience Methods
    
    /// Set a temporary target
    public func setTempTarget(
        low: Double,
        high: Double,
        duration: Double,
        reason: String? = nil,
        otp: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .tempTarget,
            duration: duration,
            targetTop: high,
            targetBottom: low,
            reason: reason,
            otp: otp,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Cancel temporary target
    public func cancelTempTarget(otp: String? = nil, enteredBy: String = "T1Pal") async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .cancelTempTarget,
            otp: otp,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Switch profile
    public func switchProfile(
        to profileName: String,
        otp: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .profileSwitch,
            profile: profileName,
            otp: otp,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Post announcement
    public func postAnnouncement(
        message: String,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .announcement,
            notes: message,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Log note
    public func logNote(
        message: String,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .note,
            notes: message,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Log BG check
    public func logBGCheck(
        glucose: Double,
        glucoseType: String = "Finger",
        notes: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .bgCheck,
            notes: notes,
            glucose: glucose,
            glucoseType: glucoseType,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Log site change
    public func logSiteChange(
        notes: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .pumpSiteChange,
            notes: notes,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Log sensor start
    public func logSensorStart(
        notes: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .cgmSensorInsert,
            notes: notes,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
    
    /// Log exercise
    public func logExercise(
        duration: Double,
        notes: String? = nil,
        enteredBy: String = "T1Pal"
    ) async throws -> RemoteCommandResult {
        let command = RemoteCommand(
            commandType: .exercise,
            notes: notes,
            duration: duration,
            enteredBy: enteredBy
        )
        return try await execute(command)
    }
}

// MARK: - T1PalErrorProtocol Conformance

import T1PalCore

extension RemoteCommandError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .network }
    
    public var code: String {
        switch self {
        case .otpRequired: return "REMOTE-OTP-001"
        case .otpInvalid: return "REMOTE-OTP-002"
        case .commandNotSupported: return "REMOTE-CMD-001"
        case .networkError: return "REMOTE-NET-001"
        case .serverError(let code): return "REMOTE-SERVER-\(code)"
        case .unauthorized: return "REMOTE-AUTH-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .otpRequired: return .warning
        case .otpInvalid: return .warning
        case .commandNotSupported: return .error
        case .networkError: return .error
        case .serverError: return .error
        case .unauthorized: return .critical
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .otpRequired, .otpInvalid: return .reauthenticate
        case .commandNotSupported: return .none
        case .networkError: return .checkNetwork
        case .serverError(let code) where code >= 500: return .waitAndRetry
        case .serverError: return .retry
        case .unauthorized: return .reauthenticate
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown remote command error"
    }
}
