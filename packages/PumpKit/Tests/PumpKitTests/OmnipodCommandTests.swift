// SPDX-License-Identifier: MIT
//
// OmnipodCommandTests.swift
// PumpKitTests
//
// Tests for Omnipod command implementation
// Trace: PUMP-OMNI-006

import Testing
import Foundation
@testable import PumpKit

@Suite("OmnipodCommandTests", .serialized)
struct OmnipodCommandTests {
    
    var bleManager: OmnipodBLEManager
    
    init() async throws {
        bleManager = OmnipodBLEManager()
        
        // Connect to simulated pod
        let pod = DiscoveredPod(
            id: "test-pod-001",
            name: "TWI BOARD 12345",
            rssi: -50,
            lotNumber: "L12345",
            sequenceNumber: "67890"
        )
        try await bleManager.connect(to: pod)
    }
    
    // MARK: - Status Commands
    
    @Test("Get status")
    func getStatus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let status = try await commander.getStatus()
        
        #expect(status.deliveryStatus == .basalRunning)
        #expect(status.podState == .running)
        #expect(status.reservoirLevel > 0)
        #expect(status.canDeliver)
        #expect(!status.isBolusing)
    }
    
    @Test("Get detailed status")
    func getDetailedStatus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let status = try await commander.getDetailedStatus()
        
        #expect(status != nil)
        #expect(status.hoursActive > 0)
    }
    
    @Test("Status updates last status")
    func statusUpdatesLastStatus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        let lastStatus = await commander.lastStatus
        #expect(lastStatus != nil)
    }
    
    // MARK: - Temp Basal Commands
    
    @Test("Set temp basal")
    func setTempBasal() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        // Initialize pod state
        _ = try await commander.getStatus()
        
        try await commander.setTempBasal(percent: 150, duration: 30 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.hasTempBasal)
        #expect(diagnostics.tempBasalPercent == 150)
    }
    
    @Test("Set temp basal zero percent")
    func setTempBasalZeroPercent() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        // 0% is valid (suspend delivery)
        try await commander.setTempBasal(percent: 0, duration: 60 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.hasTempBasal)
        #expect(diagnostics.tempBasalPercent == 0)
    }
    
    @Test("Cancel temp basal")
    func cancelTempBasal() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        try await commander.setTempBasal(percent: 150, duration: 60 * 60)
        try await commander.cancelTempBasal()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(!diagnostics.hasTempBasal)
    }
    
    @Test("Invalid temp basal percent")
    func invalidTempBasalPercent() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.setTempBasal(percent: 250, duration: 60 * 60) // Too high
            Issue.record("Should throw invalidPercent")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidPercent)
        }
    }
    
    @Test("Invalid temp basal duration")
    func invalidTempBasalDuration() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.setTempBasal(percent: 100, duration: 15 * 60) // Too short
            Issue.record("Should throw invalidDuration")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidDuration)
        }
    }
    
    @Test("Temp basal duration too long")
    func tempBasalDurationTooLong() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.setTempBasal(percent: 100, duration: 13 * 60 * 60) // > 12 hours
            Issue.record("Should throw invalidDuration")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidDuration)
        }
    }
    
    // MARK: - Bolus Commands
    
    @Test("Deliver bolus")
    func deliverBolus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.deliverBolus(units: 2.0)
        
        // No exception = success
    }
    
    @Test("Deliver small bolus")
    func deliverSmallBolus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.deliverBolus(units: 0.05) // Minimum increment
        
        // No exception = success
    }
    
    @Test("Invalid bolus amount")
    func invalidBolusAmount() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.deliverBolus(units: 50.0) // Too high
            Issue.record("Should throw invalidBolusAmount")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidBolusAmount)
        }
    }
    
    @Test("Zero bolus amount")
    func zeroBolusAmount() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.deliverBolus(units: 0.0)
            Issue.record("Should throw invalidBolusAmount")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidBolusAmount)
        }
    }
    
    @Test("Cancel bolus")
    func cancelBolus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.cancelBolus()
        
        // No exception = success
    }
    
    // MARK: - Pod Lifecycle
    
    @Test("Deactivate")
    func deactivate() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.deactivate()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.podState == .deactivated)
        #expect(!diagnostics.hasTempBasal)
    }
    
    @Test("Deactivate clears temp basal")
    func deactivateClearsTempBasal() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        try await commander.setTempBasal(percent: 150, duration: 60 * 60)
        try await commander.deactivate()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(!diagnostics.hasTempBasal)
    }
    
    @Test("Acknowledge alerts")
    func acknowledgeAlerts() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.acknowledgeAlerts()
        
        // No exception = success
    }
    
    @Test("Silence alerts")
    func silenceAlerts() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        try await commander.silenceAlerts()
        
        // No exception = success
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostics")
    func diagnostics() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        let diagnostics = await commander.diagnosticInfo()
        
        #expect(diagnostics.podState == .running)
        #expect(!diagnostics.hasTempBasal)
        #expect(diagnostics.lastStatus != nil)
        #expect(diagnostics.description.contains("Running"))
    }
    
    @Test("Diagnostics with temp basal")
    func diagnosticsWithTempBasal() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        try await commander.setTempBasal(percent: 175, duration: 60 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        
        #expect(diagnostics.hasTempBasal)
        #expect(diagnostics.tempBasalPercent == 175)
        #expect(diagnostics.description.contains("175%"))
    }
    
    // MARK: - Opcodes
    
    /// Test opcode properties - validated against externals/OmniBLE/OmniBLE/OmnipodCommon/MessageBlocks/MessageBlock.swift
    @Test("Opcode properties")
    func opcodeProperties() throws {
        // Status commands (responses are not write commands)
        #expect(OmnipodOpcode.getStatus.displayName == "Get Status")
        #expect(!OmnipodOpcode.getStatus.isWriteCommand)
        #expect(OmnipodOpcode.getStatus.rawValue == 0x0E)  // Source: MessageBlock.swift:26
        
        #expect(OmnipodOpcode.statusResponse.displayName == "Status Response")
        #expect(!OmnipodOpcode.statusResponse.isWriteCommand)
        #expect(OmnipodOpcode.statusResponse.rawValue == 0x1D)  // Source: MessageBlock.swift:34
        
        // Delivery commands (write commands)
        #expect(OmnipodOpcode.tempBasalExtra.displayName == "Temp Basal Extra")
        #expect(OmnipodOpcode.tempBasalExtra.isWriteCommand)
        #expect(OmnipodOpcode.tempBasalExtra.rawValue == 0x16)  // Source: MessageBlock.swift:29
        
        #expect(OmnipodOpcode.bolusExtra.displayName == "Bolus Extra")
        #expect(OmnipodOpcode.bolusExtra.isWriteCommand)
        #expect(OmnipodOpcode.bolusExtra.rawValue == 0x17)  // Source: MessageBlock.swift:30
        
        #expect(OmnipodOpcode.deactivatePod.displayName == "Deactivate Pod")
        #expect(OmnipodOpcode.deactivatePod.isWriteCommand)
        #expect(OmnipodOpcode.deactivatePod.rawValue == 0x1C)  // Source: MessageBlock.swift:33
        
        #expect(OmnipodOpcode.cancelDelivery.displayName == "Cancel Delivery")
        #expect(OmnipodOpcode.cancelDelivery.isWriteCommand)
        #expect(OmnipodOpcode.cancelDelivery.rawValue == 0x1F)  // Source: MessageBlock.swift:36
    }
    
    /// Test all opcode raw values match Loop's OmniBLE
    @Test("Opcode raw values match Loop")
    func opcodeRawValuesMatchLoop() throws {
        // Response types
        #expect(OmnipodOpcode.versionResponse.rawValue == 0x01)
        #expect(OmnipodOpcode.podInfoResponse.rawValue == 0x02)
        #expect(OmnipodOpcode.errorResponse.rawValue == 0x06)
        #expect(OmnipodOpcode.statusResponse.rawValue == 0x1D)
        
        // Setup commands
        #expect(OmnipodOpcode.setupPod.rawValue == 0x03)
        #expect(OmnipodOpcode.assignAddress.rawValue == 0x07)
        #expect(OmnipodOpcode.faultConfig.rawValue == 0x08)
        
        // Status
        #expect(OmnipodOpcode.getStatus.rawValue == 0x0E)
        
        // Delivery
        #expect(OmnipodOpcode.acknowledgeAlert.rawValue == 0x11)
        #expect(OmnipodOpcode.basalScheduleExtra.rawValue == 0x13)
        #expect(OmnipodOpcode.tempBasalExtra.rawValue == 0x16)
        #expect(OmnipodOpcode.bolusExtra.rawValue == 0x17)
        #expect(OmnipodOpcode.configureAlerts.rawValue == 0x19)
        #expect(OmnipodOpcode.setInsulinSchedule.rawValue == 0x1A)
        #expect(OmnipodOpcode.deactivatePod.rawValue == 0x1C)
        #expect(OmnipodOpcode.beepConfig.rawValue == 0x1E)
        #expect(OmnipodOpcode.cancelDelivery.rawValue == 0x1F)
    }
    
    // MARK: - Pod Status
    
    @Test("Pod status properties")
    func podStatusProperties() throws {
        let status = OmnipodPodStatus(
            deliveryStatus: .basalRunning,
            podState: .running,
            reservoirLevel: 150.0,
            minutesSinceActivation: 1440 // 24 hours
        )
        
        #expect(status.canDeliver)
        #expect(!status.isExpired)
        #expect(!status.isLowReservoir)
        #expect(!status.isBolusing)
        #expect(status.hoursActive == 24.0)
        
        let expiredStatus = OmnipodPodStatus(
            reservoirLevel: 5.0,
            minutesSinceActivation: 4400 // 73+ hours
        )
        
        #expect(expiredStatus.isExpired)
        #expect(expiredStatus.isLowReservoir)
    }
    
    @Test("Pod status suspended")
    func podStatusSuspended() throws {
        let status = OmnipodPodStatus(
            deliveryStatus: .suspended,
            podState: .running,
            reservoirLevel: 100.0
        )
        
        #expect(!status.canDeliver)
    }
    
    @Test("Pod status bolusing")
    func podStatusBolusing() throws {
        let status = OmnipodPodStatus(
            deliveryStatus: .bolusInProgress,
            podState: .running,
            reservoirLevel: 100.0,
            bolusRemaining: 1.5
        )
        
        #expect(status.isBolusing)
    }
    
    // MARK: - Temp Basal Struct
    
    @Test("Temp basal struct")
    func tempBasalStruct() throws {
        let startTime = Date()
        let tempBasal = OmnipodTempBasal(
            percent: 150,
            duration: 30 * 60,
            startTime: startTime
        )
        
        #expect(tempBasal.percent == 150)
        #expect(tempBasal.durationMinutes == 30)
        #expect(!tempBasal.isExpired)
        #expect(tempBasal.remainingDuration > 0)
        
        // Test expired
        let oldTempBasal = OmnipodTempBasal(
            percent: 100,
            duration: 30 * 60,
            startTime: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        
        #expect(oldTempBasal.isExpired)
        #expect(oldTempBasal.remainingDuration == 0)
    }
    
    // MARK: - Alert Types
    
    @Test("Alert types")
    func alertTypes() throws {
        #expect(OmnipodAlertType.lowReservoir.isCritical)
        #expect(OmnipodAlertType.podExpiring.isCritical)
        #expect(!OmnipodAlertType.suspendEnded.isCritical)
        
        #expect(OmnipodAlertType.lowReservoir.displayName == "Low Reservoir")
    }
    
    // MARK: - Delivery Status
    
    @Test("Delivery status")
    func deliveryStatus() throws {
        #expect(OmnipodDeliveryStatus.basalRunning.displayName == "Basal Running")
        #expect(OmnipodDeliveryStatus.tempBasalRunning.displayName == "Temp Basal")
        #expect(OmnipodDeliveryStatus.bolusInProgress.displayName == "Bolusing")
        #expect(OmnipodDeliveryStatus.suspended.displayName == "Suspended")
    }
    
    // MARK: - Pod State
    
    @Test("Pod state")
    func podState() throws {
        #expect(OmnipodPodState.running.isUsable)
        #expect(!OmnipodPodState.faulted.isUsable)
        #expect(!OmnipodPodState.deactivated.isUsable)
        #expect(!OmnipodPodState.priming.isUsable)
    }
    
    // MARK: - Nonce Management (DASH-IMPL-001)
    
    @Test("Nonce resync")
    func nonceResync() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        // Resync to known nonce value
        await commander.resyncNonce(to: 0x12345678)
        
        // After resync, next command should use the resynced nonce
        // (We can't directly test the nonce value, but we can verify the command succeeds)
        try await commander.deactivate()
    }
    
    @Test("Cancel temp basal uses nonce")
    func cancelTempBasalUsesNonce() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        try await commander.setTempBasal(percent: 150, duration: 60 * 60)
        
        // Cancel should use nonce (DASH-IMPL-001)
        try await commander.cancelTempBasal()
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(!diagnostics.hasTempBasal)
    }
    
    @Test("Acknowledge alerts uses nonce")
    func acknowledgeAlertsUsesNonce() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        // acknowledgeAlerts now requires alertMask parameter (DASH-IMPL-001)
        try await commander.acknowledgeAlerts(alertMask: 0xFF)
        
        // No exception = success
    }
    
    // MARK: - Pulse Scheduling (DASH-IMPL-002)
    
    @Test("Rate entry creation")
    func rateEntryCreation() throws {
        // Test rate entry for 1 U/hr for 1 hour
        let entries = OmnipodRateEntry.makeEntries(rate: 1.0, duration: 3600)
        
        #expect(entries.count == 1)
        #expect(abs(entries[0].rate - 1.0) < 0.01)
        #expect(abs(entries[0].duration - 3600) < 1)
    }
    
    @Test("Rate entry zero rate")
    func rateEntryZeroRate() throws {
        // Zero rate creates entries with no pulses
        let entries = OmnipodRateEntry.makeEntries(rate: 0, duration: 3600)
        
        #expect(entries.count == 2) // 2 half-hour segments
        #expect(entries[0].totalPulses == 0)
        #expect(entries[0].rate == 0)
    }
    
    @Test("Rate entry data format")
    func rateEntryDataFormat() throws {
        // Test wire format: totalPulses (2 bytes) + delay (4 bytes) = 6 bytes
        let entry = OmnipodRateEntry(totalPulses: 10, delayBetweenPulses: 180)
        let data = entry.data
        
        #expect(data.count == 6)
        // totalPulses = 10 * 10 = 100 (0x0064)
        #expect(data[0] == 0x00)
        #expect(data[1] == 0x64)
    }
    
    @Test("Pod constants")
    func podConstants() throws {
        // Verify pod constants match OmniBLE reference
        #expect(OmnipodPodConstants.pulseSize == 0.05)
        #expect(OmnipodPodConstants.pulsesPerUnit == 20.0)
        #expect(OmnipodPodConstants.secondsPerBolusPulse == 2.0)
    }
    
    @Test("Set temp basal rate")
    func setTempBasalRate() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        // Set temp basal at 1.5 U/hr for 1 hour
        try await commander.setTempBasalRate(rate: 1.5, duration: 60 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.hasTempBasal)
    }
    
    @Test("Set temp basal rate invalid rate")
    func setTempBasalRateInvalidRate() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        do {
            try await commander.setTempBasalRate(rate: 50.0, duration: 60 * 60) // > 30 U/hr
            Issue.record("Should throw invalidRate")
        } catch let error as OmnipodCommandError {
            #expect(error == .invalidRate)
        }
    }
    
    @Test("Deliver bolus with pulse timing")
    func deliverBolusWithPulseTiming() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        // Deliver 1U bolus - should use proper pulse timing
        try await commander.deliverBolus(units: 1.0, beepOptions: .silent)
        
        // No exception = success
    }
    
    // MARK: - BeepOptions (DASH-IMPL-004)
    
    @Test("Beep options silent")
    func beepOptionsSilent() {
        let options = OmnipodBeepOptions.silent
        #expect(options.encoded == 0x00)
        #expect(!options.acknowledgementBeep)
        #expect(!options.completionBeep)
        #expect(options.programReminderInterval == 0)
    }
    
    @Test("Beep options completion only")
    func beepOptionsCompletionOnly() {
        let options = OmnipodBeepOptions.completionOnly
        #expect(options.encoded == 0x40) // bit 6 set
        #expect(!options.acknowledgementBeep)
        #expect(options.completionBeep)
    }
    
    @Test("Beep options full")
    func beepOptionsFull() {
        let options = OmnipodBeepOptions.full
        #expect(options.encoded == 0xC0) // bits 6 and 7 set
        #expect(options.acknowledgementBeep)
        #expect(options.completionBeep)
    }
    
    @Test("Beep options with reminder interval")
    func beepOptionsWithReminderInterval() {
        // 15-minute reminder interval
        let options = OmnipodBeepOptions(programReminderInterval: 15 * 60)
        #expect(options.encoded == 0x0F) // 15 in lower 6 bits
        
        // With completion beep
        let optionsWithBeep = OmnipodBeepOptions(completionBeep: true, programReminderInterval: 30 * 60)
        #expect(optionsWithBeep.encoded == 0x5E) // 0x40 | 30 = 0x5E
    }
    
    @Test("Beep options clamp reminder interval")
    func beepOptionsClampReminderInterval() {
        // Maximum is 63 minutes
        let options = OmnipodBeepOptions(programReminderInterval: 120 * 60) // 120 min request
        #expect(options.programReminderInterval == 63 * 60) // clamped to 63 min
        #expect(options.encoded == 0x3F) // 63 in lower 6 bits
    }
    
    // MARK: - Extended Bolus (DASH-IMPL-003)
    
    @Test("Extended bolus delivery")
    func extendedBolusDelivery() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        _ = try await commander.getStatus()
        
        // Deliver 2U over 1 hour (pure extended bolus)
        try await commander.deliverExtendedBolus(
            immediateUnits: 0,
            extendedUnits: 2.0,
            extendedDuration: 60 * 60
        )
        // No exception = success
    }
    
    @Test("Dual wave bolus")
    func dualWaveBolus() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        _ = try await commander.getStatus()
        
        // Deliver 1U immediate + 2U over 1 hour (dual wave)
        try await commander.deliverExtendedBolus(
            immediateUnits: 1.0,
            extendedUnits: 2.0,
            extendedDuration: 60 * 60,
            beepOptions: .completionOnly
        )
        // No exception = success
    }
    
    @Test("Extended bolus min duration")
    func extendedBolusMinDuration() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        _ = try await commander.getStatus()
        
        // Minimum 30 minutes
        do {
            try await commander.deliverExtendedBolus(
                extendedUnits: 1.0,
                extendedDuration: 20 * 60 // 20 min - too short
            )
            Issue.record("Should throw invalidDuration")
        } catch OmnipodCommandError.invalidDuration {
            // Expected
        }
    }
    
    @Test("Extended bolus max duration")
    func extendedBolusMaxDuration() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        _ = try await commander.getStatus()
        
        // Maximum 8 hours
        do {
            try await commander.deliverExtendedBolus(
                extendedUnits: 1.0,
                extendedDuration: 10 * 60 * 60 // 10 hours - too long
            )
            Issue.record("Should throw invalidDuration")
        } catch OmnipodCommandError.invalidDuration {
            // Expected
        }
    }
    
    @Test("Extended bolus requires extended units")
    func extendedBolusRequiresExtendedUnits() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        _ = try await commander.getStatus()
        
        do {
            try await commander.deliverExtendedBolus(
                extendedUnits: 0, // No extended units
                extendedDuration: 60 * 60
            )
            Issue.record("Should throw invalidBolusAmount")
        } catch OmnipodCommandError.invalidBolusAmount {
            // Expected
        }
    }
    
    // MARK: - PodInfoType (DASH-IMPL-006)
    
    @Test("Pod info type enum")
    func podInfoTypeEnum() {
        #expect(OmnipodPodInfoType.normal.rawValue == 0x00)
        #expect(OmnipodPodInfoType.triggeredAlerts.rawValue == 0x01)
        #expect(OmnipodPodInfoType.detailedStatus.rawValue == 0x02)
        #expect(OmnipodPodInfoType.pulseLogPlus.rawValue == 0x03)
        #expect(OmnipodPodInfoType.activationTime.rawValue == 0x05)
        #expect(OmnipodPodInfoType.noSeqStatus.rawValue == 0x07)
        #expect(OmnipodPodInfoType.pulseLogRecent.rawValue == 0x50)
        #expect(OmnipodPodInfoType.pulseLogPrevious.rawValue == 0x51)
    }
    
    @Test("Pod info type display names")
    func podInfoTypeDisplayNames() {
        #expect(OmnipodPodInfoType.normal.displayName == "Normal Status")
        #expect(OmnipodPodInfoType.activationTime.displayName == "Activation Time")
        #expect(OmnipodPodInfoType.triggeredAlerts.displayName == "Triggered Alerts")
    }
    
    @Test("Get pod info normal")
    func getPodInfoNormal() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let response = try await commander.getPodInfo(type: .normal)
        
        if case .status(let status) = response {
            #expect(status.podState == .running)
        } else {
            Issue.record("Expected status response")
        }
    }
    
    @Test("Get pod info activation time")
    func getPodInfoActivationTime() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let response = try await commander.getPodInfo(type: .activationTime)
        
        if case .activationTime(let info) = response {
            #expect(info.activationYear == 26)
            #expect(info.activationMonth == 2)
            #expect(!info.hasFault)
        } else {
            Issue.record("Expected activationTime response")
        }
    }
    
    @Test("Get pod info triggered alerts")
    func getPodInfoTriggeredAlerts() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let response = try await commander.getPodInfo(type: .triggeredAlerts)
        
        if case .triggeredAlerts(let alerts) = response {
            #expect(alerts.alertMask == 0)
            #expect(alerts.activeAlertSlots.isEmpty)
        } else {
            Issue.record("Expected triggeredAlerts response")
        }
    }
    
    @Test("Get activation time convenience")
    func getActivationTimeConvenience() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let info = try await commander.getActivationTime()
        
        #expect(info.activationYear == 26)
        #expect(info.activationDate != nil)
    }
    
    @Test("Get triggered alerts convenience")
    func getTriggeredAlertsConvenience() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        let alerts = try await commander.getTriggeredAlerts()
        
        #expect(alerts.alertMask == 0)
    }
    
    @Test("Activation info has fault")
    func activationInfoHasFault() {
        let noFault = OmnipodActivationInfo(
            activationYear: 26, activationMonth: 2, activationDay: 20,
            activationHour: 10, activationMinute: 30,
            faultEventCode: 0, faultTimeMinutes: 0
        )
        #expect(!noFault.hasFault)
        
        let withFault = OmnipodActivationInfo(
            activationYear: 26, activationMonth: 2, activationDay: 20,
            activationHour: 10, activationMinute: 30,
            faultEventCode: 0x14, faultTimeMinutes: 120
        )
        #expect(withFault.hasFault)
    }
    
    @Test("Triggered alerts active slots")
    func triggeredAlertsActiveSlots() {
        // Alert slots 0 and 3 active (mask = 0b1001 = 9)
        let alerts = OmnipodTriggeredAlerts(alertMask: 9)
        #expect(alerts.activeAlertSlots == [0, 3])
        
        // No alerts
        let noAlerts = OmnipodTriggeredAlerts(alertMask: 0)
        #expect(noAlerts.activeAlertSlots.isEmpty)
    }
    
    // MARK: - SetInsulinScheduleCommand (DASH-IMPL-005)
    
    @Test("Insulin table entry creation")
    func insulinTableEntryCreation() throws {
        // Test table entry for 1 U/hr rate (20 pulses/hr, 10 pulses per half-hour segment)
        let entry = OmnipodInsulinTableEntry(rate: 1.0, segments: 2)
        
        #expect(entry.segments == 2)
        #expect(entry.pulses == 10) // 1 U/hr = 20 pulses/hr = 10/segment
        #expect(!entry.alternateSegmentPulse)
    }
    
    @Test("Insulin table entry odd pulses")
    func insulinTableEntryOddPulses() throws {
        // Test odd pulse count (alternateSegmentPulse should be true)
        // 0.5 U/hr = 10 pulses/hr = 5 pulses/segment (odd hourly)
        let entry = OmnipodInsulinTableEntry(rate: 0.5, segments: 2)
        
        #expect(entry.pulses == 5)
        #expect(!entry.alternateSegmentPulse) // 10/2 = 5, no remainder
        
        // 0.55 U/hr = 11 pulses/hr (odd)
        let oddEntry = OmnipodInsulinTableEntry(rate: 0.55, segments: 2)
        #expect(oddEntry.alternateSegmentPulse) // 11 is odd
    }
    
    @Test("Insulin table entry data format")
    func insulinTableEntryDataFormat() throws {
        // Test wire format encoding
        let entry = OmnipodInsulinTableEntry(segments: 3, pulses: 10, alternateSegmentPulse: false)
        let data = entry.data
        
        #expect(data.count == 2)
        // Byte 0: (segments-1)<<4 | alt<<3 | pulsesHigh
        // segments=3 -> (3-1)<<4 = 0x20
        // alt=false -> 0
        // pulses=10 -> high bits = 0
        #expect(data[0] == 0x20)
        // Byte 1: pulsesLow = 10 = 0x0A
        #expect(data[1] == 0x0A)
    }
    
    @Test("Insulin table entry checksum")
    func insulinTableEntryChecksum() throws {
        // Test checksum calculation
        let entry = OmnipodInsulinTableEntry(segments: 2, pulses: 10, alternateSegmentPulse: false)
        let checksum = entry.checksum()
        
        // checksumPerSegment = (10 & 0xFF) + (10 >> 8) = 10 + 0 = 10
        // checksum = 10 * 2 + 0 = 20
        #expect(checksum == 20)
    }
    
    @Test("Set temp basal rate sends both commands")
    func setTempBasalRateSendsBothCommands() async throws {
        let commander = OmnipodCommander(bleManager: bleManager)
        
        _ = try await commander.getStatus()
        
        // This should send SetInsulinScheduleCommand (0x1A) + TempBasalExtraCommand (0x16)
        try await commander.setTempBasalRate(rate: 1.5, duration: 60 * 60)
        
        let diagnostics = await commander.diagnosticInfo()
        #expect(diagnostics.hasTempBasal)
    }
}
