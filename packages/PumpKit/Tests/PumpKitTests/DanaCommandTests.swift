// SPDX-License-Identifier: MIT
//
// DanaCommandTests.swift
// PumpKitTests
//
// Tests for DanaCommander
// Trace: PUMP-DANA-005, PRD-005

import Testing
import Foundation
@testable import PumpKit

@Suite("Dana Command Tests", .serialized)
struct DanaCommandTests {
    var manager: DanaBLEManager
    var commander: DanaCommander
    
    init() async throws {
        manager = DanaBLEManager()
        commander = DanaCommander(manager: manager)
        
        // Connect to simulated pump
        await manager.startScanning()
        try? await Task.sleep(nanoseconds: 600_000_000)
        
        let pumps = await manager.discoveredPumps
        if let pump = pumps.first {
            try await manager.connect(to: pump)
        }
    }
    
    // MARK: - Status Tests
    
    @Test("Get status returns valid data")
    mutating func getStatus() async throws {
        let status = try await commander.getStatus()
        
        #expect(status.errorState == .none)
        #expect(status.reservoirLevel > 0)
        #expect(status.batteryPercent > 0)
        #expect(!status.isSuspended)
        #expect(status.canDeliver)
    }
    
    @Test("Status reflects suspended state")
    mutating func statusReflectsSuspendedState() async throws {
        // Suspend pump
        try await commander.suspend()
        
        let status = try await commander.getStatus()
        #expect(status.isSuspended)
        #expect(!status.canDeliver)
    }
    
    @Test("Get basal rate returns positive value")
    mutating func getBasalRate() async throws {
        let rate = try await commander.getBasalRate()
        #expect(rate > 0)
    }
    
    // MARK: - Temp Basal Tests
    
    @Test("Set temp basal")
    mutating func setTempBasal() async throws {
        let tb = try await commander.setTempBasal(percent: 150, durationMinutes: 60)
        
        #expect(tb.percent == 150)
        #expect(tb.durationMinutes == 60)
        #expect(!tb.isExpired)
        #expect(tb.rateMultiplier == 1.5)
    }
    
    @Test("Temp basal rounds to 30 minutes")
    mutating func tempBasalRoundsTo30Minutes() async throws {
        // 45 minutes should round to 60 (nearest 30)
        let tb = try await commander.setTempBasal(percent: 100, durationMinutes: 45)
        #expect(tb.durationMinutes == 60)
    }
    
    @Test("Cancel temp basal")
    mutating func cancelTempBasal() async throws {
        _ = try await commander.setTempBasal(percent: 120, durationMinutes: 30)
        
        try await commander.cancelTempBasal()
        
        let state = try await commander.getTempBasalState()
        #expect(state == nil)
    }
    
    @Test("Temp basal zero percent")
    mutating func tempBasalZeroPercent() async throws {
        let tb = try await commander.setTempBasal(percent: 0, durationMinutes: 60)
        #expect(tb.percent == 0)
        #expect(tb.rateMultiplier == 0)
    }
    
    @Test("Temp basal max percent")
    mutating func tempBasalMaxPercent() async throws {
        let tb = try await commander.setTempBasal(percent: 200, durationMinutes: 60)
        #expect(tb.percent == 200)
        #expect(tb.rateMultiplier == 2.0)
    }
    
    @Test("Temp basal percent too high throws error")
    mutating func tempBasalPercentTooHigh() async throws {
        do {
            _ = try await commander.setTempBasal(percent: 250, durationMinutes: 60)
            Issue.record("Should throw invalidParameter")
        } catch DanaCommandError.invalidParameter {
            // Expected
        }
    }
    
    @Test("Temp basal duration too long throws error")
    mutating func tempBasalDurationTooLong() async throws {
        do {
            _ = try await commander.setTempBasal(percent: 100, durationMinutes: 2000)
            Issue.record("Should throw invalidParameter")
        } catch DanaCommandError.invalidParameter {
            // Expected
        }
    }
    
    @Test("Temp basal while suspended fails")
    mutating func tempBasalWhileSuspendedFails() async throws {
        try await commander.suspend()
        
        do {
            _ = try await commander.setTempBasal(percent: 150, durationMinutes: 60)
            Issue.record("Should throw suspended")
        } catch DanaCommandError.suspended {
            // Expected
        }
    }
    
    // MARK: - Bolus Tests
    
    @Test("Deliver bolus")
    mutating func deliverBolus() async throws {
        try await commander.deliverBolus(units: 1.5)
        
        let state = await commander.bolusState
        #expect(!state.isDelivering)
        #expect(state.deliveredUnits == 1.5)
    }
    
    @Test("Bolus rounds to increment")
    mutating func bolusRoundsToIncrement() async throws {
        // 1.23U should round to 1.25U (0.05 increment)
        try await commander.deliverBolus(units: 1.23)
        
        let state = await commander.bolusState
        #expect(abs(state.deliveredUnits - 1.25) < 0.01)
    }
    
    @Test("Zero bolus amount throws error")
    mutating func zeroBolusAmount() async throws {
        do {
            try await commander.deliverBolus(units: 0)
            Issue.record("Should throw invalidParameter")
        } catch DanaCommandError.invalidParameter {
            // Expected
        }
    }
    
    @Test("Bolus too large throws error")
    mutating func bolusTooLarge() async throws {
        do {
            try await commander.deliverBolus(units: 30.0)
            Issue.record("Should throw invalidParameter")
        } catch DanaCommandError.invalidParameter {
            // Expected
        }
    }
    
    @Test("Bolus while suspended throws error")
    mutating func bolusWhileSuspended() async throws {
        try await commander.suspend()
        
        do {
            try await commander.deliverBolus(units: 1.0)
            Issue.record("Should throw suspended")
        } catch DanaCommandError.suspended {
            // Expected
        }
    }
    
    @Test("Cancel bolus")
    mutating func cancelBolus() async throws {
        // Normally you'd test mid-bolus cancellation
        // For simulation, just verify no-op when not bolusing
        try await commander.cancelBolus()
        
        let state = await commander.bolusState
        #expect(!state.isDelivering)
    }
    
    // MARK: - Suspend/Resume Tests
    
    @Test("Suspend pump")
    mutating func suspendPump() async throws {
        try await commander.suspend()
        
        let isSuspended = await commander.isSuspended
        #expect(isSuspended)
    }
    
    @Test("Resume pump")
    mutating func resumePump() async throws {
        try await commander.suspend()
        try await commander.resume()
        
        let isSuspended = await commander.isSuspended
        #expect(!isSuspended)
    }
    
    @Test("Suspend cancels temp basal")
    mutating func suspendCancelsTempBasal() async throws {
        _ = try await commander.setTempBasal(percent: 150, durationMinutes: 60)
        
        try await commander.suspend()
        
        let tb = await commander.activeTempBasal
        #expect(tb == nil)
    }
    
    // MARK: - Stats Tests
    
    @Test("Command stats initial state")
    mutating func commandStats() async throws {
        let stats = await commander.commandStats()
        
        #expect(stats.lastStatusCheck == nil)
        #expect(!stats.isSuspended)
        #expect(stats.activeTempBasal == nil)
        #expect(!stats.bolusInProgress)
    }
    
    @Test("Command stats after operations")
    mutating func commandStatsAfterOperations() async throws {
        _ = try await commander.getStatus()
        _ = try await commander.setTempBasal(percent: 130, durationMinutes: 60)
        
        let stats = await commander.commandStats()
        
        #expect(stats.activeTempBasal != nil)
        #expect(stats.activeTempBasal?.percent == 130)
    }
    
    // MARK: - DanaTempBasal Struct Tests
    
    @Test("Temp basal struct properties")
    func tempBasalStruct() {
        let tb = DanaTempBasal(percent: 150, duration: 3600)
        
        #expect(tb.percent == 150)
        #expect(tb.durationMinutes == 60)
        #expect(tb.rateMultiplier == 1.5)
        #expect(!tb.isExpired)
        #expect(tb.remainingMinutes == 60)
    }
    
    // MARK: - DanaBolusState Struct Tests
    
    @Test("Bolus state progress")
    func bolusStateProgress() {
        let state = DanaBolusState(
            isDelivering: true,
            requestedUnits: 2.0,
            deliveredUnits: 1.0,
            remainingUnits: 1.0
        )
        
        #expect(state.progress == 0.5)
    }
    
    @Test("Bolus state idle")
    func bolusStateIdle() {
        let state = DanaBolusState.idle
        
        #expect(!state.isDelivering)
        #expect(state.requestedUnits == 0)
        #expect(state.progress == 0)
    }
    
    // MARK: - DanaPumpStatus Tests
    
    @Test("Pump status flags")
    func pumpStatusFlags() {
        let status = DanaPumpStatus(
            reservoirLevel: 15.0,
            batteryPercent: 15,
            isSuspended: true
        )
        
        #expect(status.isLowReservoir)
        #expect(status.isLowBattery)
        #expect(!status.canDeliver)
    }
    
    @Test("Pump status healthy")
    func pumpStatusHealthy() {
        let status = DanaPumpStatus(
            reservoirLevel: 150.0,
            batteryPercent: 80
        )
        
        #expect(!status.isLowReservoir)
        #expect(!status.isLowBattery)
        #expect(status.canDeliver)
    }
    
    // MARK: - DanaCommandError Tests
    
    @Test("Command error descriptions")
    func commandErrorDescriptions() {
        let errors: [DanaCommandError] = [
            .notConnected,
            .notReady,
            .suspended,
            .invalidParameter("test"),
            .commandFailed(DanaCommands.setBolus, 1),
            .bolusInProgress,
            .tempBasalActive,
            .dailyMaxReached,
            .timeout,
            .communicationError("test")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - Command Tests
    
    @Test("Command display names")
    func commandDisplayNames() {
        #expect(DanaCommands.setBolus.displayName == "Set Bolus")
        #expect(DanaCommands.setTempBasal.displayName == "Set Temp Basal")
        #expect(DanaCommands.suspend.displayName == "Suspend")
        #expect(DanaCommands.resume.displayName == "Resume")
    }
    
    @Test("Command isWrite flag")
    func commandIsWrite() {
        #expect(DanaCommands.setBolus.isWrite)
        #expect(DanaCommands.setTempBasal.isWrite)
        #expect(DanaCommands.suspend.isWrite)
        #expect(!DanaCommands.getBasalRate.isWrite)
        #expect(!DanaCommands.getTempBasalState.isWrite)
    }
    
    @Test("Message type display names")
    func messageTypeDisplayNames() {
        #expect(DanaMessageType.general.displayName == "General")
        #expect(DanaMessageType.basal.displayName == "Basal")
        #expect(DanaMessageType.bolus.displayName == "Bolus")
        #expect(DanaMessageType.encryption.displayName == "Encryption")
    }
}

// MARK: - Dana Basal Schedule Tests (CRIT-PROFILE-013)

@Suite("Dana Basal Schedule Parsing Tests")
struct DanaBasalScheduleParsingTests {
    
    @Test("Parse valid 24-hour schedule from raw data")
    func parseValidSchedule() {
        // Build test data: [maxBasal 2B][basalStep 1B][24 rates × 2B]
        var data = Data()
        
        // maxBasal = 3.0 (300 as UInt16)
        data.append(contentsOf: [0x2C, 0x01]) // 300 = 0x012C little-endian
        
        // basalStep = 0.01 (1)
        data.append(0x01)
        
        // 24 hourly rates (all 0.8 U/hr = 80)
        for _ in 0..<24 {
            data.append(contentsOf: [0x50, 0x00]) // 80 = 0x0050
        }
        
        let schedule = DanaBasalSchedule.parse(from: data)
        
        #expect(schedule != nil)
        #expect(schedule!.maxBasal == 3.0)
        #expect(schedule!.basalStep == 0.01)
        #expect(schedule!.hourlyRates.count == 24)
        #expect(schedule!.hourlyRates.allSatisfy { $0 == 0.8 })
        #expect(abs(schedule!.totalDailyBasal - 19.2) < 0.001) // 0.8 * 24
    }
    
    @Test("Parse schedule with varying rates")
    func parseVaryingRates() {
        var data = Data()
        
        // maxBasal = 2.0
        data.append(contentsOf: [0xC8, 0x00]) // 200
        
        // basalStep = 0.05
        data.append(0x05)
        
        // Varying rates: 0.5, 0.6, ..., 1.7 (24 values)
        for hour in 0..<24 {
            let rate = UInt16(50 + hour * 5) // 0.50 + 0.05 per hour
            data.append(UInt8(rate & 0xFF))
            data.append(UInt8(rate >> 8))
        }
        
        let schedule = DanaBasalSchedule.parse(from: data)
        
        #expect(schedule != nil)
        #expect(schedule!.maxBasal == 2.0)
        #expect(schedule!.basalStep == 0.05)
        #expect(schedule!.hourlyRates[0] == 0.5)
        #expect(schedule!.hourlyRates[12] == 1.1) // 50 + 60 = 110 → 1.10
        #expect(schedule!.hourlyRates[23] == 1.65) // 50 + 115 = 165 → 1.65
    }
    
    @Test("Parse fails with insufficient data")
    func parseFailsShortData() {
        // Only 50 bytes (needs 51)
        let data = Data(repeating: 0x00, count: 50)
        let schedule = DanaBasalSchedule.parse(from: data)
        
        #expect(schedule == nil)
    }
    
    @Test("Get rate for specific hour")
    func getRateForHour() {
        let schedule = DanaBasalSchedule.demo
        
        #expect(schedule.rate(forHour: 0) == 0.8)
        #expect(schedule.rate(forHour: 6) == 1.2)
        #expect(schedule.rate(forHour: 23) == 0.8)
        #expect(schedule.rate(forHour: -1) == nil)
        #expect(schedule.rate(forHour: 24) == nil)
    }
    
    @Test("Demo schedule has valid structure")
    func demoScheduleValid() {
        let demo = DanaBasalSchedule.demo
        
        #expect(demo.maxBasal == 3.0)
        #expect(demo.basalStep == 0.01)
        #expect(demo.hourlyRates.count == 24)
        #expect(demo.totalDailyBasal > 0)
    }
    
    @Test("Raw data encoding round-trip")
    func rawDataRoundTrip() {
        let original = DanaBasalSchedule.demo
        let encoded = original.rawData
        
        // Encoded should be 48 bytes (24 rates × 2 bytes)
        #expect(encoded.count == 48)
        
        // Re-parse (need to add header for full parse)
        var fullData = Data()
        fullData.append(contentsOf: [0x2C, 0x01]) // maxBasal = 3.0
        fullData.append(0x01) // basalStep = 0.01
        fullData.append(encoded)
        
        let reparsed = DanaBasalSchedule.parse(from: fullData)
        
        #expect(reparsed != nil)
        #expect(reparsed!.hourlyRates == original.hourlyRates)
    }
}

@Suite("Dana Basal Schedule Manager Tests", .serialized)
struct DanaBasalScheduleManagerTests {
    var manager: DanaBLEManager
    
    init() async throws {
        manager = DanaBLEManager()
        await manager.startScanning()
        try? await Task.sleep(nanoseconds: 600_000_000)
        
        let pumps = await manager.discoveredPumps
        if let pump = pumps.first {
            try await manager.connect(to: pump)
        }
    }
    
    @Test("Read basal schedule returns valid schedule")
    mutating func readBasalSchedule() async throws {
        let schedule = try await manager.readBasalSchedule()
        
        #expect(schedule.hourlyRates.count == 24)
        #expect(schedule.maxBasal > 0)
        #expect(schedule.totalDailyBasal > 0)
    }
    
    @Test("Write basal schedule validates 24 entries")
    mutating func writeBasalScheduleValidatesCount() async throws {
        // Invalid: only 12 rates
        let invalid = DanaBasalSchedule(
            maxBasal: 3.0,
            basalStep: 0.01,
            hourlyRates: Array(repeating: 0.8, count: 12)
        )
        
        do {
            try await manager.writeBasalSchedule(invalid)
            Issue.record("Should throw invalidSchedule")
        } catch DanaBLEError.invalidSchedule {
            // Expected
        }
    }
    
    @Test("Get basal schedule command exists")
    func getBasalScheduleCommandExists() {
        let cmd = DanaCommands.getBasalSchedule
        #expect(cmd.opcode == 0x67)
        #expect(!cmd.isWrite)
    }
    
    @Test("Set basal schedule command exists")
    func setBasalScheduleCommandExists() {
        let cmd = DanaCommands.setBasalSchedule
        #expect(cmd.opcode == 0x68)
        #expect(cmd.isWrite)
    }
}
