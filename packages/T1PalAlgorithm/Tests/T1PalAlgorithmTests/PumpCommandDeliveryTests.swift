// SPDX-License-Identifier: MIT
//
// PumpCommandDeliveryTests.swift
// T1Pal Mobile
//
// Tests for pump command delivery
// Trace: PROD-AID-003

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Pump Command Type Tests

@Suite("Pump Command Type")
struct PumpCommandTypeTests {
    
    @Test("All command types have raw values")
    func allCommandTypesHaveRawValues() {
        for type in PumpCommandType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test("Command types are unique")
    func commandTypesAreUnique() {
        let rawValues = PumpCommandType.allCases.map { $0.rawValue }
        let unique = Set(rawValues)
        #expect(rawValues.count == unique.count)
    }
}

// MARK: - Pump Command Tests

@Suite("Pump Command")
struct PumpCommandTests {
    
    @Test("Create temp basal command")
    func createTempBasalCommand() {
        let command = PumpCommand.tempBasal(rate: 1.5, duration: 1800)
        
        #expect(command.type == .tempBasal)
        #expect(command.tempBasalRate == 1.5)
        #expect(command.tempBasalDuration == 1800)
        #expect(command.status == .pending)
        #expect(command.source == .algorithm)
    }
    
    @Test("Create cancel temp basal command")
    func createCancelTempBasalCommand() {
        let command = PumpCommand.cancelTempBasal()
        
        #expect(command.type == .cancelTempBasal)
        #expect(command.tempBasalRate == nil)
    }
    
    @Test("Create bolus command")
    func createBolusCommand() {
        let command = PumpCommand.bolus(amount: 2.5)
        
        #expect(command.type == .bolus)
        #expect(command.bolusAmount == 2.5)
        #expect(command.source == .user)
    }
    
    @Test("Create SMB command")
    func createSMBCommand() {
        let command = PumpCommand.smb(amount: 0.5)
        
        #expect(command.type == .smb)
        #expect(command.bolusAmount == 0.5)
        #expect(command.source == .algorithm)
    }
    
    @Test("Create suspend command")
    func createSuspendCommand() {
        let command = PumpCommand.suspend()
        
        #expect(command.type == .suspend)
        #expect(command.source == .user)
    }
    
    @Test("Create resume command")
    func createResumeCommand() {
        let command = PumpCommand.resume()
        
        #expect(command.type == .resume)
    }
    
    @Test("Command age calculation")
    func commandAgeCalculation() {
        let oldCommand = PumpCommand(
            type: .tempBasal,
            timestamp: Date().addingTimeInterval(-60),
            tempBasalRate: 1.0,
            tempBasalDuration: 1800
        )
        
        #expect(oldCommand.age >= 60)
        #expect(oldCommand.age < 65)
    }
    
    @Test("Command is identifiable")
    func commandIsIdentifiable() {
        let command1 = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        let command2 = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        
        #expect(command1.id != command2.id)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PumpCommand.tempBasal(rate: 1.5, duration: 3600)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PumpCommand.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.tempBasalRate == original.tempBasalRate)
    }
}

// MARK: - Pump Command Source Tests

@Suite("Pump Command Source")
struct PumpCommandSourceTests {
    
    @Test("All sources have raw values")
    func allSourcesHaveRawValues() {
        for source in PumpCommandSource.allCases {
            #expect(!source.rawValue.isEmpty)
        }
    }
}

// MARK: - Pump Command Result Tests

@Suite("Pump Command Result")
struct PumpCommandResultTests {
    
    @Test("Create success result")
    func createSuccessResult() {
        let command = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        let result = PumpCommandResult(
            command: command,
            success: true,
            duration: 1.5
        )
        
        #expect(result.success == true)
        #expect(result.duration == 1.5)
        #expect(result.errorMessage == nil)
    }
    
    @Test("Create failure result")
    func createFailureResult() {
        let command = PumpCommand.bolus(amount: 1.0)
        let result = PumpCommandResult(
            command: command,
            success: false,
            errorMessage: "Pump not connected",
            duration: 0.5
        )
        
        #expect(result.success == false)
        #expect(result.errorMessage == "Pump not connected")
    }
    
    @Test("Result with retries")
    func resultWithRetries() {
        let command = PumpCommand.smb(amount: 0.5)
        let result = PumpCommandResult(
            command: command,
            success: true,
            duration: 3.0,
            retryCount: 2
        )
        
        #expect(result.retryCount == 2)
    }
}

// MARK: - Command Delivery Configuration Tests

@Suite("Pump Command Delivery Configuration")
struct PumpCommandDeliveryConfigurationTests {
    
    @Test("Default configuration")
    func defaultConfiguration() {
        let config = PumpCommandDeliveryConfiguration.default
        
        #expect(config.maxRetries == 3)
        #expect(config.retryDelay == 2.0)
        #expect(config.commandTimeout == 30.0)
        #expect(config.minimumSMBInterval == 180.0)
        #expect(config.maxSMBSize == 1.0)
        #expect(config.maxTempBasalRate == 10.0)
        #expect(config.smbEnabled == false)
    }
    
    @Test("Aggressive configuration")
    func aggressiveConfiguration() {
        let config = PumpCommandDeliveryConfiguration.aggressive
        
        #expect(config.maxRetries == 5)
        #expect(config.maxSMBSize == 1.5)
        #expect(config.smbEnabled == true)
    }
    
    @Test("Conservative configuration")
    func conservativeConfiguration() {
        let config = PumpCommandDeliveryConfiguration.conservative
        
        #expect(config.maxRetries == 2)
        #expect(config.maxSMBSize == 0.5)
        #expect(config.maxTempBasalRate == 5.0)
        #expect(config.smbEnabled == false)
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = PumpCommandDeliveryConfiguration(
            maxRetries: 10,
            retryDelay: 5.0,
            maxSMBSize: 2.0,
            smbEnabled: true
        )
        
        #expect(config.maxRetries == 10)
        #expect(config.retryDelay == 5.0)
        #expect(config.maxSMBSize == 2.0)
        #expect(config.smbEnabled == true)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PumpCommandDeliveryConfiguration(
            maxRetries: 5,
            maxSMBSize: 1.5,
            smbEnabled: true
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PumpCommandDeliveryConfiguration.self, from: data)
        
        #expect(decoded.maxRetries == original.maxRetries)
        #expect(decoded.maxSMBSize == original.maxSMBSize)
        #expect(decoded.smbEnabled == original.smbEnabled)
    }
}

// MARK: - Command History Tests

@Suite("Pump Command History")
struct PumpCommandHistoryTests {
    
    @Test("Add commands to history")
    func addCommandsToHistory() {
        var history = PumpCommandHistory()
        
        let command1 = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        let command2 = PumpCommand.bolus(amount: 2.0)
        
        history.addCommand(command1)
        history.addCommand(command2)
        
        #expect(history.commands.count == 2)
        // Most recent first
        #expect(history.commands.first?.type == .bolus)
    }
    
    @Test("History respects max entries")
    func historyRespectsMaxEntries() {
        var history = PumpCommandHistory()
        
        for _ in 0..<300 {
            history.addCommand(PumpCommand.tempBasal(rate: 1.0, duration: 1800))
        }
        
        #expect(history.commands.count == PumpCommandHistory.maxEntries)
    }
    
    @Test("Update command status")
    func updateCommandStatus() {
        var history = PumpCommandHistory()
        let command = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        
        history.addCommand(command)
        history.updateCommand(command.id, status: .success)
        
        #expect(history.commands.first?.status == .success)
    }
    
    @Test("Get last command of type")
    func getLastCommandOfType() {
        var history = PumpCommandHistory()
        
        var command1 = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        command1.status = .success
        var command2 = PumpCommand.tempBasal(rate: 2.0, duration: 1800)
        command2.status = .success
        var command3 = PumpCommand.bolus(amount: 1.0)
        command3.status = .success
        
        history.addCommand(command1)
        history.addCommand(command2)
        history.addCommand(command3)
        
        let lastTempBasal = history.lastCommand(of: .tempBasal)
        #expect(lastTempBasal?.tempBasalRate == 2.0)
    }
    
    @Test("Calculate insulin delivered")
    func calculateInsulinDelivered() {
        var history = PumpCommandHistory()
        
        var bolus1 = PumpCommand.bolus(amount: 2.0)
        bolus1.status = .success
        var bolus2 = PumpCommand.bolus(amount: 1.5)
        bolus2.status = .success
        var smb = PumpCommand.smb(amount: 0.5)
        smb.status = .success
        var failed = PumpCommand.bolus(amount: 3.0)
        failed.status = .failed
        
        history.addCommand(bolus1)
        history.addCommand(bolus2)
        history.addCommand(smb)
        history.addCommand(failed)
        
        let delivered = history.insulinDelivered(lastHours: 1)
        #expect(delivered == 4.0)  // 2.0 + 1.5 + 0.5, not 3.0 (failed)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        var history = PumpCommandHistory()
        history.addCommand(PumpCommand.tempBasal(rate: 1.0, duration: 1800))
        history.addCommand(PumpCommand.bolus(amount: 2.0))
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PumpCommandHistory.self, from: data)
        
        #expect(decoded.commands.count == 2)
    }
}

// MARK: - Command Statistics Tests

@Suite("Pump Command Statistics")
struct PumpCommandStatisticsTests {
    
    @Test("Calculate from history")
    func calculateFromHistory() {
        var history = PumpCommandHistory()
        
        var temp1 = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        temp1.status = .success
        var temp2 = PumpCommand.cancelTempBasal()
        temp2.status = .success
        var bolus = PumpCommand.bolus(amount: 2.0)
        bolus.status = .success
        var smb = PumpCommand.smb(amount: 0.5)
        smb.status = .failed
        
        history.addCommand(temp1)
        history.addCommand(temp2)
        history.addCommand(bolus)
        history.addCommand(smb)
        
        let stats = PumpCommandStatistics.from(history: history, lastHours: 1)
        
        #expect(stats.totalCommands == 4)
        #expect(stats.successfulCommands == 3)
        #expect(stats.failedCommands == 1)
        #expect(stats.tempBasalCommands == 2)
        #expect(stats.bolusCommands == 1)
        #expect(stats.smbCommands == 1)
        #expect(stats.successRate == 75.0)
    }
    
    @Test("Empty history statistics")
    func emptyHistoryStatistics() {
        let history = PumpCommandHistory()
        let stats = PumpCommandStatistics.from(history: history)
        
        #expect(stats.totalCommands == 0)
        #expect(stats.successRate == 0)
    }
}

// MARK: - Command Delivery Error Tests

@Suite("Pump Command Error")
struct PumpCommandErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let errors: [PumpCommandError] = [
            .pumpNotConnected,
            .commandTimeout,
            .maxRetriesExceeded,
            .commandRejected("Test"),
            .safetyLimitExceeded("Rate too high"),
            .invalidCommand("Missing parameter"),
            .communicationError("BLE error"),
            .smbNotEnabled,
            .smbTooSoon(remainingSeconds: 120)
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("SMB too soon error includes time")
    func smbTooSoonErrorIncludesTime() {
        let error = PumpCommandError.smbTooSoon(remainingSeconds: 90)
        let description = error.errorDescription ?? ""
        
        #expect(description.contains("90"))
    }
}

// MARK: - Pump Command Delivery Manager Tests

@Suite("Pump Command Delivery Manager")
struct PumpCommandDeliveryManagerTests {
    
    @Test("Execute without pump returns error")
    func executeWithoutPumpReturnsError() async {
        let manager = PumpCommandDeliveryManager()
        let command = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        
        let result = await manager.execute(command)
        
        #expect(result.success == false)
        #expect(result.errorMessage?.contains("not") == true)
    }
    
    @Test("Execute temp basal")
    func executeTempBasal() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.setTempBasal(rate: 1.5, duration: 1800)
        
        #expect(result.success == true)
        let lastTemp = await mockPump.lastTempBasal
        #expect(lastTemp?.rate == 1.5)
    }
    
    @Test("Execute cancel temp basal")
    func executeCancelTempBasal() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.cancelTempBasal()
        
        #expect(result.success == true)
        let cancelled = await mockPump.tempBasalCancelled
        #expect(cancelled == true)
    }
    
    @Test("Execute bolus")
    func executeBolus() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.deliverBolus(amount: 2.5)
        
        #expect(result.success == true)
        let lastBolus = await mockPump.lastBolus
        #expect(lastBolus == 2.5)
    }
    
    @Test("SMB rejected when disabled")
    func smbRejectedWhenDisabled() async {
        let manager = PumpCommandDeliveryManager(configuration: .default)
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.deliverSMB(amount: 0.5)
        
        #expect(result.success == false)
        #expect(result.errorMessage?.contains("not enabled") == true)
    }
    
    @Test("SMB allowed when enabled")
    func smbAllowedWhenEnabled() async {
        let config = PumpCommandDeliveryConfiguration(smbEnabled: true)
        let manager = PumpCommandDeliveryManager(configuration: config)
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.deliverSMB(amount: 0.5)
        
        #expect(result.success == true)
    }
    
    @Test("Validates temp basal rate limit")
    func validatesTempBasalRateLimit() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        // Rate exceeds default max of 10
        let result = await manager.setTempBasal(rate: 15.0, duration: 1800)
        
        #expect(result.success == false)
        #expect(result.errorMessage?.contains("exceeds") == true)
    }
    
    @Test("Validates bolus amount positive")
    func validatesBolusAmountPositive() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.deliverBolus(amount: -1.0)
        
        #expect(result.success == false)
        #expect(result.errorMessage?.contains("positive") == true)
    }
    
    @Test("Track command history")
    func trackCommandHistory() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        _ = await manager.setTempBasal(rate: 1.0, duration: 1800)
        _ = await manager.deliverBolus(amount: 2.0)
        
        let history = await manager.getHistory()
        #expect(history.commands.count == 2)
    }
    
    @Test("Get statistics")
    func getStatistics() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        _ = await manager.setTempBasal(rate: 1.0, duration: 1800)
        _ = await manager.setTempBasal(rate: 0.5, duration: 1800)
        _ = await manager.deliverBolus(amount: 2.0)
        
        let stats = await manager.getStatistics(lastHours: 1)
        
        #expect(stats.totalCommands == 3)
        #expect(stats.successfulCommands == 3)
        #expect(stats.tempBasalCommands == 2)
        #expect(stats.bolusCommands == 1)
    }
    
    @Test("Get insulin delivered")
    func getInsulinDelivered() async {
        let manager = PumpCommandDeliveryManager()
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        _ = await manager.deliverBolus(amount: 3.0)
        _ = await manager.deliverBolus(amount: 1.5)
        
        let delivered = await manager.getInsulinDelivered(lastHours: 1)
        #expect(delivered == 4.5)
    }
    
    @Test("Update configuration")
    func updateConfiguration() async {
        let manager = PumpCommandDeliveryManager()
        let newConfig = PumpCommandDeliveryConfiguration(maxRetries: 10)
        
        await manager.updateConfiguration(newConfig)
        
        // Configuration updated (verified by behavior)
        let mockPump = MockPumpController()
        await manager.configure(pumpController: mockPump)
        
        let result = await manager.setTempBasal(rate: 1.0, duration: 1800)
        #expect(result.success == true)
    }
}

// MARK: - Mock Pump Command Delivery Tests

@Suite("Mock Pump Command Delivery Manager")
struct MockPumpCommandDeliveryManagerTests {
    
    @Test("Mock tracks calls")
    func mockTracksCalls() async {
        let mock = MockPumpCommandDeliveryManager()
        
        let command = PumpCommand.tempBasal(rate: 1.0, duration: 1800)
        _ = await mock.execute(command)
        _ = await mock.execute(command)
        
        let count = await mock.executeCallCount
        let lastCommand = await mock.lastCommand
        
        #expect(count == 2)
        #expect(lastCommand?.type == .tempBasal)
    }
    
    @Test("Mock returns success by default")
    func mockReturnsSuccessByDefault() async {
        let mock = MockPumpCommandDeliveryManager()
        
        let result = await mock.execute(PumpCommand.bolus(amount: 1.0))
        
        #expect(result.success == true)
    }
    
    @Test("Mock returns failure when configured")
    func mockReturnsFailureWhenConfigured() async {
        let mock = MockPumpCommandDeliveryManager()
        await mock.setFail(true)
        
        let result = await mock.execute(PumpCommand.bolus(amount: 1.0))
        
        #expect(result.success == false)
        #expect(result.errorMessage == "Mock failure")
    }
}
