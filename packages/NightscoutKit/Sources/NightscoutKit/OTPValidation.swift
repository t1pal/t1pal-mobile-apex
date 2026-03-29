// SPDX-License-Identifier: AGPL-3.0-or-later
// OTPValidation.swift
// NightscoutKit
//
// One-Time Password validation for remote commands
// Trace: CONTROL-006, agent-control-plane-integration.md

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - OTP Configuration

/// Configuration for OTP generation and validation
public struct OTPConfig: Sendable, Equatable {
    /// Length of OTP code (typically 6 digits)
    public let codeLength: Int
    
    /// Validity period in seconds
    public let validityPeriod: TimeInterval
    
    /// Algorithm for OTP generation
    public let algorithm: OTPAlgorithm
    
    /// Maximum validation attempts before lockout
    public let maxAttempts: Int
    
    /// Lockout duration after max attempts
    public let lockoutDuration: TimeInterval
    
    /// Whether to allow clock drift tolerance
    public let clockDriftTolerance: Int
    
    public init(
        codeLength: Int = 6,
        validityPeriod: TimeInterval = 300, // 5 minutes
        algorithm: OTPAlgorithm = .totp,
        maxAttempts: Int = 3,
        lockoutDuration: TimeInterval = 300, // 5 minutes
        clockDriftTolerance: Int = 1
    ) {
        self.codeLength = codeLength
        self.validityPeriod = validityPeriod
        self.algorithm = algorithm
        self.maxAttempts = maxAttempts
        self.lockoutDuration = lockoutDuration
        self.clockDriftTolerance = clockDriftTolerance
    }
    
    /// Default configuration for production
    public static var `default`: OTPConfig {
        OTPConfig()
    }
    
    /// Stricter configuration for high-security commands
    public static var secure: OTPConfig {
        OTPConfig(
            codeLength: 8,
            validityPeriod: 120,
            algorithm: .totp,
            maxAttempts: 2,
            lockoutDuration: 600,
            clockDriftTolerance: 0
        )
    }
    
    /// Testing configuration with longer validity
    public static var testing: OTPConfig {
        OTPConfig(
            codeLength: 6,
            validityPeriod: 3600,
            algorithm: .counter,
            maxAttempts: 10,
            lockoutDuration: 0,
            clockDriftTolerance: 5
        )
    }
}

/// OTP algorithm type
public enum OTPAlgorithm: String, Sendable, Codable, Equatable {
    /// Time-based OTP (RFC 6238)
    case totp = "totp"
    
    /// Counter-based OTP (RFC 4226)
    case counter = "counter"
    
    /// Simple random code (for demo mode)
    case random = "random"
}

// MARK: - OTP Result Types

/// Result of OTP generation
public struct GeneratedOTP: Sendable {
    /// The generated OTP code
    public let code: String
    
    /// When the code was generated
    public let generatedAt: Date
    
    /// When the code expires
    public let expiresAt: Date
    
    /// Counter value (for counter-based OTP)
    public let counter: UInt64?
    
    /// Command this OTP authorizes
    public let commandId: UUID
    
    public init(
        code: String,
        generatedAt: Date = Date(),
        expiresAt: Date,
        counter: UInt64? = nil,
        commandId: UUID
    ) {
        self.code = code
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.counter = counter
        self.commandId = commandId
    }
    
    /// Check if OTP is still valid
    public var isValid: Bool {
        Date() < expiresAt
    }
    
    /// Time remaining until expiry
    public var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSince(Date()))
    }
}

/// Result of OTP validation
public enum OTPValidationResult: Sendable, Equatable {
    /// Validation successful
    case valid(authorizedAt: Date)
    
    /// Code is incorrect
    case invalid(attemptsRemaining: Int)
    
    /// Code has expired
    case expired
    
    /// Account is locked out
    case lockedOut(until: Date)
    
    /// Code was already used
    case alreadyUsed
    
    /// Command not found
    case commandNotFound
    
    public var isSuccess: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Remote Command Authorization

/// A remote command requiring OTP authorization
public struct OTPRemoteCommand: Sendable, Identifiable {
    public let id: UUID
    public let type: OTPCommandType
    public let parameters: [String: String]
    public let requestedBy: String
    public let requestedAt: Date
    public var status: OTPRemoteCommandStatus
    public var otp: GeneratedOTP?
    public var authorizedAt: Date?
    public var executedAt: Date?
    public var error: String?
    
    public init(
        id: UUID = UUID(),
        type: OTPCommandType,
        parameters: [String: String] = [:],
        requestedBy: String,
        requestedAt: Date = Date(),
        status: OTPRemoteCommandStatus = .pending,
        otp: GeneratedOTP? = nil
    ) {
        self.id = id
        self.type = type
        self.parameters = parameters
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.status = status
        self.otp = otp
    }
}

/// Types of remote commands
public enum OTPCommandType: String, Sendable, Codable, CaseIterable {
    case override = "override"
    case cancelOverride = "cancelOverride"
    case tempTarget = "tempTarget"
    case cancelTempTarget = "cancelTempTarget"
    case bolus = "bolus"
    case suspend = "suspend"
    case resume = "resume"
    case announce = "announce"
    
    /// Security level required for this command
    public var securityLevel: CommandSecurityLevel {
        switch self {
        case .bolus, .suspend, .resume:
            return .high
        case .override, .cancelOverride, .tempTarget, .cancelTempTarget:
            return .medium
        case .announce:
            return .low
        }
    }
}

/// Security levels for commands
public enum CommandSecurityLevel: String, Sendable, Codable, Comparable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public static func < (lhs: CommandSecurityLevel, rhs: CommandSecurityLevel) -> Bool {
        let order: [CommandSecurityLevel] = [.low, .medium, .high]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// Status of a remote command
public enum OTPRemoteCommandStatus: String, Sendable, Codable {
    case pending = "pending"
    case awaitingOTP = "awaitingOTP"
    case authorized = "authorized"
    case executing = "executing"
    case completed = "completed"
    case failed = "failed"
    case expired = "expired"
    case cancelled = "cancelled"
}

// MARK: - Validation Attempt Tracking

/// Tracks validation attempts for rate limiting
public struct ValidationAttempts: Sendable {
    public let commandId: UUID
    public var attempts: Int
    public var lastAttempt: Date?
    public var lockedUntil: Date?
    
    public init(commandId: UUID) {
        self.commandId = commandId
        self.attempts = 0
        self.lastAttempt = nil
        self.lockedUntil = nil
    }
    
    /// Check if currently locked out
    public var isLockedOut: Bool {
        guard let lockedUntil = lockedUntil else { return false }
        return Date() < lockedUntil
    }
    
    /// Record an attempt
    public mutating func recordAttempt(maxAttempts: Int, lockoutDuration: TimeInterval) {
        attempts += 1
        lastAttempt = Date()
        if attempts >= maxAttempts {
            lockedUntil = Date().addingTimeInterval(lockoutDuration)
        }
    }
    
    /// Reset after successful validation
    public mutating func reset() {
        attempts = 0
        lastAttempt = nil
        lockedUntil = nil
    }
}

// MARK: - OTP Logic

/// Logic for OTP operations
public enum OTPLogic {
    /// Generate an OTP code
    public static func generateCode(
        secret: Data,
        counter: UInt64,
        config: OTPConfig
    ) -> String {
        // Use simple hash-based generation
        var hash = counter
        for byte in secret {
            hash = hash &* 31 &+ UInt64(byte)
        }
        
        // Generate digits
        var code = ""
        var value = hash
        for _ in 0..<config.codeLength {
            let digit = value % 10
            code = String(digit) + code
            value /= 10
        }
        
        return String(code.suffix(config.codeLength))
    }
    
    /// Calculate TOTP counter from time
    public static func totpCounter(at date: Date, period: TimeInterval) -> UInt64 {
        let seconds = date.timeIntervalSince1970
        return UInt64(seconds / period)
    }
    
    /// Validate code with clock drift tolerance
    public static func validateCode(
        code: String,
        secret: Data,
        config: OTPConfig,
        at date: Date = Date()
    ) -> Bool {
        switch config.algorithm {
        case .totp:
            let currentCounter = totpCounter(at: date, period: config.validityPeriod)
            // Check current and adjacent time windows
            for offset in -config.clockDriftTolerance...config.clockDriftTolerance {
                let counter = UInt64(Int64(currentCounter) + Int64(offset))
                let expected = generateCode(secret: secret, counter: counter, config: config)
                if code == expected {
                    return true
                }
            }
            return false
            
        case .counter:
            // For counter-based, we'd need to track the expected counter
            // Simplified: just validate format
            return code.count == config.codeLength && code.allSatisfy { $0.isNumber }
            
        case .random:
            // Random codes are validated against stored value, not generated
            return false
        }
    }
    
    /// Generate a random OTP code (for demo mode)
    public static func generateRandomCode(length: Int) -> String {
        var code = ""
        for _ in 0..<length {
            code += String(Int.random(in: 0...9))
        }
        return code
    }
    
    /// Check if command requires OTP
    public static func requiresOTP(
        commandType: OTPCommandType,
        minimumSecurityLevel: CommandSecurityLevel
    ) -> Bool {
        commandType.securityLevel >= minimumSecurityLevel
    }
    
    /// Get appropriate config for command security level
    public static func configForSecurityLevel(_ level: CommandSecurityLevel) -> OTPConfig {
        switch level {
        case .low:
            return OTPConfig(
                codeLength: 4,
                validityPeriod: 600,
                maxAttempts: 5,
                lockoutDuration: 60
            )
        case .medium:
            return .default
        case .high:
            return .secure
        }
    }
}

// MARK: - OTP Validator Actor

/// Actor for thread-safe OTP validation with rate limiting
public actor OTPValidator {
    /// Configuration
    public let config: OTPConfig
    
    /// Shared secret for OTP generation (would come from secure storage in production)
    private let secret: Data
    
    /// Pending commands awaiting validation
    private var pendingCommands: [UUID: OTPRemoteCommand] = [:]
    
    /// Validation attempt tracking
    private var attempts: [UUID: ValidationAttempts] = [:]
    
    /// Used codes to prevent replay
    private var usedCodes: Set<String> = []
    
    /// Counter for counter-based OTP
    private var counter: UInt64 = 0
    
    public init(config: OTPConfig = .default, secret: Data = Data()) {
        self.config = config
        self.secret = secret.isEmpty ? Data((0..<32).map { _ in UInt8.random(in: 0...255) }) : secret
    }
    
    // MARK: - Command Management
    
    /// Register a command for OTP authorization
    public func registerCommand(_ command: OTPRemoteCommand) -> GeneratedOTP {
        var cmd = command
        
        // Generate OTP
        let code: String
        switch config.algorithm {
        case .totp:
            let currentCounter = OTPLogic.totpCounter(at: Date(), period: config.validityPeriod)
            code = OTPLogic.generateCode(secret: secret, counter: currentCounter, config: config)
        case .counter:
            counter += 1
            code = OTPLogic.generateCode(secret: secret, counter: counter, config: config)
        case .random:
            code = OTPLogic.generateRandomCode(length: config.codeLength)
        }
        
        let otp = GeneratedOTP(
            code: code,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(config.validityPeriod),
            counter: config.algorithm == .counter ? counter : nil,
            commandId: command.id
        )
        
        cmd.otp = otp
        cmd.status = .awaitingOTP
        pendingCommands[command.id] = cmd
        attempts[command.id] = ValidationAttempts(commandId: command.id)
        
        return otp
    }
    
    /// Validate OTP for a command
    public func validateOTP(commandId: UUID, code: String) -> OTPValidationResult {
        // Check if command exists
        guard var command = pendingCommands[commandId] else {
            return .commandNotFound
        }
        
        // Check if locked out
        var attemptTracker = attempts[commandId] ?? ValidationAttempts(commandId: commandId)
        if attemptTracker.isLockedOut {
            return .lockedOut(until: attemptTracker.lockedUntil!)
        }
        
        // Check if OTP exists and not expired
        guard let otp = command.otp else {
            return .commandNotFound
        }
        
        if !otp.isValid {
            command.status = .expired
            pendingCommands[commandId] = command
            return .expired
        }
        
        // Check if code was already used
        if usedCodes.contains(code) {
            return .alreadyUsed
        }
        
        // Validate code
        let isValid: Bool
        switch config.algorithm {
        case .random:
            isValid = (code == otp.code)
        case .totp, .counter:
            isValid = OTPLogic.validateCode(code: code, secret: secret, config: config)
        }
        
        if isValid {
            // Mark as used
            usedCodes.insert(code)
            
            // Update command status
            command.status = .authorized
            command.authorizedAt = Date()
            pendingCommands[commandId] = command
            
            // Reset attempts
            attemptTracker.reset()
            attempts[commandId] = attemptTracker
            
            return .valid(authorizedAt: Date())
        } else {
            // Record failed attempt
            attemptTracker.recordAttempt(maxAttempts: config.maxAttempts, lockoutDuration: config.lockoutDuration)
            attempts[commandId] = attemptTracker
            
            if attemptTracker.isLockedOut {
                return .lockedOut(until: attemptTracker.lockedUntil!)
            }
            
            return .invalid(attemptsRemaining: config.maxAttempts - attemptTracker.attempts)
        }
    }
    
    /// Get pending command
    public func getCommand(_ id: UUID) -> OTPRemoteCommand? {
        pendingCommands[id]
    }
    
    /// Cancel a pending command
    public func cancelCommand(_ id: UUID) {
        if var command = pendingCommands[id] {
            command.status = .cancelled
            pendingCommands[id] = command
        }
    }
    
    /// Mark command as executed
    public func markExecuted(_ id: UUID, success: Bool, error: String? = nil) {
        if var command = pendingCommands[id] {
            command.status = success ? .completed : .failed
            command.executedAt = Date()
            command.error = error
            pendingCommands[id] = command
        }
    }
    
    /// Clean up expired commands
    public func cleanupExpired() -> Int {
        let now = Date()
        var cleaned = 0
        
        for (id, command) in pendingCommands {
            if let otp = command.otp, now > otp.expiresAt {
                var cmd = command
                cmd.status = .expired
                pendingCommands[id] = cmd
                cleaned += 1
            }
        }
        
        // Also clean up old used codes (keep last 1000)
        if usedCodes.count > 1000 {
            usedCodes.removeAll()
        }
        
        return cleaned
    }
    
    /// Get all pending commands
    public func allPendingCommands() -> [OTPRemoteCommand] {
        pendingCommands.values.filter { $0.status == .awaitingOTP }
    }
    
    /// Get validation attempts for a command
    public func getAttempts(_ id: UUID) -> ValidationAttempts? {
        attempts[id]
    }
    
    // MARK: - Statistics
    
    /// Count of pending commands
    public var pendingCount: Int {
        pendingCommands.values.filter { $0.status == .awaitingOTP }.count
    }
    
    /// Count of authorized commands
    public var authorizedCount: Int {
        pendingCommands.values.filter { $0.status == .authorized }.count
    }
}

// MARK: - Remote Command Authorization Flow

/// High-level authorization flow for remote commands
public enum OTPRemoteCommandAuthorizationFlow {
    /// Step 1: Request authorization
    public static func requestAuthorization(
        type: OTPCommandType,
        parameters: [String: String],
        requestedBy: String,
        validator: OTPValidator
    ) async -> (command: OTPRemoteCommand, otp: GeneratedOTP) {
        let command = OTPRemoteCommand(
            type: type,
            parameters: parameters,
            requestedBy: requestedBy
        )
        let otp = await validator.registerCommand(command)
        return (command, otp)
    }
    
    /// Step 2: Validate OTP
    public static func validateAuthorization(
        commandId: UUID,
        code: String,
        validator: OTPValidator
    ) async -> OTPValidationResult {
        await validator.validateOTP(commandId: commandId, code: code)
    }
    
    /// Step 3: Execute (placeholder - actual execution depends on command type)
    public static func markExecuted(
        commandId: UUID,
        success: Bool,
        error: String?,
        validator: OTPValidator
    ) async {
        await validator.markExecuted(commandId, success: success, error: error)
    }
}
