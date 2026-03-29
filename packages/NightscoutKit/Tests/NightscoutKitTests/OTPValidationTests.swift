// SPDX-License-Identifier: MIT
// OTPValidationTests.swift
// NightscoutKitTests
//
// Tests for OTP validation for remote commands
// Trace: CONTROL-006

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - OTP Config Tests

@Suite("OTP Config")
struct OTPConfigTests {
    @Test("Default config has expected values")
    func defaultConfig() {
        let config = OTPConfig.default
        
        #expect(config.codeLength == 6)
        #expect(config.validityPeriod == 300)
        #expect(config.algorithm == .totp)
        #expect(config.maxAttempts == 3)
        #expect(config.lockoutDuration == 300)
        #expect(config.clockDriftTolerance == 1)
    }
    
    @Test("Secure config is stricter")
    func secureConfig() {
        let config = OTPConfig.secure
        
        #expect(config.codeLength == 8)
        #expect(config.validityPeriod == 120)
        #expect(config.maxAttempts == 2)
        #expect(config.clockDriftTolerance == 0)
    }
    
    @Test("Testing config is lenient")
    func testingConfig() {
        let config = OTPConfig.testing
        
        #expect(config.validityPeriod == 3600)
        #expect(config.algorithm == .counter)
        #expect(config.maxAttempts == 10)
    }
    
    @Test("Custom config")
    func customConfig() {
        let config = OTPConfig(
            codeLength: 4,
            validityPeriod: 60,
            algorithm: .random,
            maxAttempts: 5,
            lockoutDuration: 120,
            clockDriftTolerance: 2
        )
        
        #expect(config.codeLength == 4)
        #expect(config.validityPeriod == 60)
        #expect(config.algorithm == .random)
    }
}

// MARK: - OTP Algorithm Tests

@Suite("OTP Algorithm")
struct OTPAlgorithmTests {
    @Test("All algorithms have raw values")
    func rawValues() {
        #expect(OTPAlgorithm.totp.rawValue == "totp")
        #expect(OTPAlgorithm.counter.rawValue == "counter")
        #expect(OTPAlgorithm.random.rawValue == "random")
    }
}

// MARK: - Generated OTP Tests

@Suite("Generated OTP")
struct GeneratedOTPTests {
    @Test("OTP is valid when not expired")
    func validWhenNotExpired() {
        let otp = GeneratedOTP(
            code: "123456",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(300),
            commandId: UUID()
        )
        
        #expect(otp.isValid == true)
        #expect(otp.timeRemaining > 0)
    }
    
    @Test("OTP is invalid when expired")
    func invalidWhenExpired() {
        let otp = GeneratedOTP(
            code: "123456",
            generatedAt: Date().addingTimeInterval(-600),
            expiresAt: Date().addingTimeInterval(-300),
            commandId: UUID()
        )
        
        #expect(otp.isValid == false)
        #expect(otp.timeRemaining == 0)
    }
    
    @Test("OTP with counter")
    func withCounter() {
        let otp = GeneratedOTP(
            code: "123456",
            expiresAt: Date().addingTimeInterval(300),
            counter: 42,
            commandId: UUID()
        )
        
        #expect(otp.counter == 42)
    }
}

// MARK: - OTP Validation Result Tests

@Suite("OTP Validation Result")
struct OTPValidationResultTests {
    @Test("Valid result is success")
    func validIsSuccess() {
        let result = OTPValidationResult.valid(authorizedAt: Date())
        #expect(result.isSuccess == true)
    }
    
    @Test("Invalid result is not success")
    func invalidIsNotSuccess() {
        let result = OTPValidationResult.invalid(attemptsRemaining: 2)
        #expect(result.isSuccess == false)
    }
    
    @Test("Expired is not success")
    func expiredIsNotSuccess() {
        #expect(OTPValidationResult.expired.isSuccess == false)
    }
    
    @Test("Locked out is not success")
    func lockedOutIsNotSuccess() {
        let result = OTPValidationResult.lockedOut(until: Date().addingTimeInterval(300))
        #expect(result.isSuccess == false)
    }
    
    @Test("Already used is not success")
    func alreadyUsedIsNotSuccess() {
        #expect(OTPValidationResult.alreadyUsed.isSuccess == false)
    }
    
    @Test("Command not found is not success")
    func commandNotFoundIsNotSuccess() {
        #expect(OTPValidationResult.commandNotFound.isSuccess == false)
    }
}

// MARK: - Remote Command Type Tests

@Suite("Remote Command Type")
struct OTPCommandTypeTests {
    @Test("All command types have security levels")
    func securityLevels() {
        for type in OTPCommandType.allCases {
            let level = type.securityLevel
            #expect([.low, .medium, .high].contains(level))
        }
    }
    
    @Test("Bolus has high security")
    func bolusHighSecurity() {
        #expect(OTPCommandType.bolus.securityLevel == .high)
    }
    
    @Test("Override has medium security")
    func overrideMediumSecurity() {
        #expect(OTPCommandType.override.securityLevel == .medium)
    }
    
    @Test("Announce has low security")
    func announceLowSecurity() {
        #expect(OTPCommandType.announce.securityLevel == .low)
    }
}

// MARK: - Command Security Level Tests

@Suite("Command Security Level")
struct CommandSecurityLevelTests {
    @Test("Security levels are comparable")
    func comparable() {
        #expect(CommandSecurityLevel.low < CommandSecurityLevel.medium)
        #expect(CommandSecurityLevel.medium < CommandSecurityLevel.high)
        #expect(CommandSecurityLevel.low < CommandSecurityLevel.high)
    }
    
    @Test("Equal levels")
    func equal() {
        #expect(CommandSecurityLevel.medium == CommandSecurityLevel.medium)
    }
}

// MARK: - Remote Command Tests

@Suite("Remote Command")
struct OTPRemoteCommandTests {
    @Test("Default command is pending")
    func defaultPending() {
        let command = OTPRemoteCommand(
            type: .override,
            requestedBy: "caregiver@example.com"
        )
        
        #expect(command.status == .pending)
    }
    
    @Test("Command with parameters")
    func withParameters() {
        let command = OTPRemoteCommand(
            type: .bolus,
            parameters: ["amount": "2.0", "carbs": "30"],
            requestedBy: "caregiver@example.com"
        )
        
        #expect(command.parameters["amount"] == "2.0")
        #expect(command.parameters["carbs"] == "30")
    }
}

// MARK: - Validation Attempts Tests

@Suite("Validation Attempts")
struct ValidationAttemptsTests {
    @Test("Initial state is not locked")
    func initialNotLocked() {
        let attempts = ValidationAttempts(commandId: UUID())
        
        #expect(attempts.attempts == 0)
        #expect(attempts.isLockedOut == false)
    }
    
    @Test("Record attempt increments count")
    func recordIncrementsCount() {
        var attempts = ValidationAttempts(commandId: UUID())
        
        attempts.recordAttempt(maxAttempts: 3, lockoutDuration: 300)
        #expect(attempts.attempts == 1)
        #expect(attempts.lastAttempt != nil)
        #expect(attempts.isLockedOut == false)
    }
    
    @Test("Lockout after max attempts")
    func lockoutAfterMax() {
        var attempts = ValidationAttempts(commandId: UUID())
        
        attempts.recordAttempt(maxAttempts: 3, lockoutDuration: 300)
        attempts.recordAttempt(maxAttempts: 3, lockoutDuration: 300)
        attempts.recordAttempt(maxAttempts: 3, lockoutDuration: 300)
        
        #expect(attempts.attempts == 3)
        #expect(attempts.isLockedOut == true)
        #expect(attempts.lockedUntil != nil)
    }
    
    @Test("Reset clears state")
    func resetClears() {
        var attempts = ValidationAttempts(commandId: UUID())
        attempts.recordAttempt(maxAttempts: 3, lockoutDuration: 300)
        
        attempts.reset()
        
        #expect(attempts.attempts == 0)
        #expect(attempts.lastAttempt == nil)
        #expect(attempts.lockedUntil == nil)
    }
}

// MARK: - OTP Logic Tests

@Suite("OTP Logic")
struct OTPLogicTests {
    @Test("Generate code has correct length")
    func generateCodeLength() {
        let secret = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let config = OTPConfig(codeLength: 6)
        
        let code = OTPLogic.generateCode(secret: secret, counter: 1, config: config)
        
        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
    }
    
    @Test("Generate code with different lengths")
    func differentLengths() {
        let secret = Data([1, 2, 3, 4])
        
        let config4 = OTPConfig(codeLength: 4)
        let config8 = OTPConfig(codeLength: 8)
        
        let code4 = OTPLogic.generateCode(secret: secret, counter: 1, config: config4)
        let code8 = OTPLogic.generateCode(secret: secret, counter: 1, config: config8)
        
        #expect(code4.count == 4)
        #expect(code8.count == 8)
    }
    
    @Test("Same inputs produce same code")
    func deterministic() {
        let secret = Data([1, 2, 3, 4])
        let config = OTPConfig(codeLength: 6)
        
        let code1 = OTPLogic.generateCode(secret: secret, counter: 42, config: config)
        let code2 = OTPLogic.generateCode(secret: secret, counter: 42, config: config)
        
        #expect(code1 == code2)
    }
    
    @Test("Different counters produce different codes")
    func differentCounters() {
        let secret = Data([1, 2, 3, 4])
        let config = OTPConfig(codeLength: 6)
        
        let code1 = OTPLogic.generateCode(secret: secret, counter: 1, config: config)
        let code2 = OTPLogic.generateCode(secret: secret, counter: 2, config: config)
        
        #expect(code1 != code2)
    }
    
    @Test("TOTP counter calculation")
    func totpCounter() {
        let date = Date(timeIntervalSince1970: 60000)
        let counter = OTPLogic.totpCounter(at: date, period: 30)
        
        #expect(counter == 2000)
    }
    
    @Test("Generate random code has correct length")
    func randomCodeLength() {
        let code = OTPLogic.generateRandomCode(length: 6)
        
        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
    }
    
    @Test("Requires OTP for high security")
    func requiresOTPHigh() {
        let result = OTPLogic.requiresOTP(
            commandType: .bolus,
            minimumSecurityLevel: .medium
        )
        #expect(result == true)
    }
    
    @Test("No OTP for low security below threshold")
    func noOTPLowSecurity() {
        let result = OTPLogic.requiresOTP(
            commandType: .announce,
            minimumSecurityLevel: .medium
        )
        #expect(result == false)
    }
    
    @Test("Config for security level")
    func configForLevel() {
        let lowConfig = OTPLogic.configForSecurityLevel(.low)
        let mediumConfig = OTPLogic.configForSecurityLevel(.medium)
        let highConfig = OTPLogic.configForSecurityLevel(.high)
        
        #expect(lowConfig.codeLength == 4)
        #expect(mediumConfig.codeLength == 6)
        #expect(highConfig.codeLength == 8)
    }
}

// MARK: - OTP Validator Tests

@Suite("OTP Validator")
struct OTPValidatorTests {
    @Test("Register command returns OTP")
    func registerReturnsOTP() async {
        let validator = OTPValidator(config: .testing)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        let otp = await validator.registerCommand(command)
        
        #expect(otp.code.count == 6)
        #expect(otp.commandId == command.id)
        #expect(otp.isValid == true)
    }
    
    @Test("Validate correct code succeeds")
    func validateCorrectCode() async {
        let config = OTPConfig(algorithm: .random)
        let validator = OTPValidator(config: config)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        let otp = await validator.registerCommand(command)
        let result = await validator.validateOTP(commandId: command.id, code: otp.code)
        
        #expect(result.isSuccess == true)
    }
    
    @Test("Validate incorrect code fails")
    func validateIncorrectCode() async {
        let config = OTPConfig(algorithm: .random)
        let validator = OTPValidator(config: config)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        _ = await validator.registerCommand(command)
        let result = await validator.validateOTP(commandId: command.id, code: "wrong1")
        
        if case .invalid(let remaining) = result {
            #expect(remaining == 2)
        } else {
            #expect(Bool(false), "Expected invalid result")
        }
    }
    
    @Test("Lockout after max attempts")
    func lockoutAfterMaxAttempts() async {
        let config = OTPConfig(algorithm: .random, maxAttempts: 2, lockoutDuration: 300)
        let validator = OTPValidator(config: config)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        _ = await validator.registerCommand(command)
        _ = await validator.validateOTP(commandId: command.id, code: "wrong1")
        let result = await validator.validateOTP(commandId: command.id, code: "wrong2")
        
        if case .lockedOut = result {
            // Expected
        } else {
            #expect(Bool(false), "Expected locked out result")
        }
    }
    
    @Test("Command not found for unknown ID")
    func commandNotFound() async {
        let validator = OTPValidator()
        
        let result = await validator.validateOTP(commandId: UUID(), code: "123456")
        
        #expect(result == .commandNotFound)
    }
    
    @Test("Get pending command")
    func getPendingCommand() async {
        let validator = OTPValidator(config: .testing)
        let command = OTPRemoteCommand(type: .bolus, requestedBy: "test@example.com")
        
        _ = await validator.registerCommand(command)
        let retrieved = await validator.getCommand(command.id)
        
        #expect(retrieved?.id == command.id)
        #expect(retrieved?.status == .awaitingOTP)
    }
    
    @Test("Cancel command")
    func cancelCommand() async {
        let validator = OTPValidator(config: .testing)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        _ = await validator.registerCommand(command)
        await validator.cancelCommand(command.id)
        
        let retrieved = await validator.getCommand(command.id)
        #expect(retrieved?.status == .cancelled)
    }
    
    @Test("Mark executed success")
    func markExecutedSuccess() async {
        let config = OTPConfig(algorithm: .random)
        let validator = OTPValidator(config: config)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        let otp = await validator.registerCommand(command)
        _ = await validator.validateOTP(commandId: command.id, code: otp.code)
        await validator.markExecuted(command.id, success: true)
        
        let retrieved = await validator.getCommand(command.id)
        #expect(retrieved?.status == .completed)
        #expect(retrieved?.executedAt != nil)
    }
    
    @Test("Mark executed failure")
    func markExecutedFailure() async {
        let config = OTPConfig(algorithm: .random)
        let validator = OTPValidator(config: config)
        let command = OTPRemoteCommand(type: .override, requestedBy: "test@example.com")
        
        let otp = await validator.registerCommand(command)
        _ = await validator.validateOTP(commandId: command.id, code: otp.code)
        await validator.markExecuted(command.id, success: false, error: "Pump communication failed")
        
        let retrieved = await validator.getCommand(command.id)
        #expect(retrieved?.status == .failed)
        #expect(retrieved?.error == "Pump communication failed")
    }
    
    @Test("Pending count")
    func pendingCount() async {
        let validator = OTPValidator(config: .testing)
        
        _ = await validator.registerCommand(OTPRemoteCommand(type: .override, requestedBy: "a"))
        _ = await validator.registerCommand(OTPRemoteCommand(type: .bolus, requestedBy: "b"))
        
        let count = await validator.pendingCount
        #expect(count == 2)
    }
    
    @Test("All pending commands")
    func allPendingCommands() async {
        let validator = OTPValidator(config: .testing)
        
        _ = await validator.registerCommand(OTPRemoteCommand(type: .override, requestedBy: "a"))
        _ = await validator.registerCommand(OTPRemoteCommand(type: .bolus, requestedBy: "b"))
        
        let pending = await validator.allPendingCommands()
        #expect(pending.count == 2)
    }
}

// MARK: - Remote Command Authorization Flow Tests

@Suite("Remote Command Authorization Flow")
struct OTPRemoteCommandAuthorizationFlowTests {
    @Test("Full authorization flow")
    func fullFlow() async {
        let config = OTPConfig(algorithm: .random)
        let validator = OTPValidator(config: config)
        
        // Step 1: Request
        let (command, otp) = await OTPRemoteCommandAuthorizationFlow.requestAuthorization(
            type: .override,
            parameters: ["name": "Exercise"],
            requestedBy: "caregiver@example.com",
            validator: validator
        )
        
        #expect(otp.commandId == command.id)
        
        // Step 2: Validate
        let result = await OTPRemoteCommandAuthorizationFlow.validateAuthorization(
            commandId: command.id,
            code: otp.code,
            validator: validator
        )
        
        #expect(result.isSuccess == true)
        
        // Step 3: Execute
        await OTPRemoteCommandAuthorizationFlow.markExecuted(
            commandId: command.id,
            success: true,
            error: nil,
            validator: validator
        )
        
        let finalCommand = await validator.getCommand(command.id)
        #expect(finalCommand?.status == .completed)
    }
}

// MARK: - Remote Command Status Tests

@Suite("Remote Command Status")
struct OTPRemoteCommandStatusTests {
    @Test("All statuses have raw values")
    func rawValues() {
        let statuses: [OTPRemoteCommandStatus] = [
            .pending, .awaitingOTP, .authorized, .executing,
            .completed, .failed, .expired, .cancelled
        ]
        
        for status in statuses {
            #expect(!status.rawValue.isEmpty)
        }
    }
}
