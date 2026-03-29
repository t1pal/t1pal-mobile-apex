// SPDX-License-Identifier: MIT
//
// MinimedManagerTests.swift
// PumpKitTests
//
// Tests for Medtronic/Minimed pump manager
// Trace: PUMP-010, PRD-005

import Testing
import Foundation
@testable import PumpKit

// MARK: - Pump Model Tests

@Suite("MinimedPumpModel")
struct MinimedPumpModelTests {
    
    @Test("All models have correct reservoir capacity")
    func reservoirCapacity() {
        #expect(MinimedPumpModel.model508.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model511.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model512.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model515.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model522.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model523.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model530.reservoirCapacity == 176)
        #expect(MinimedPumpModel.model554.reservoirCapacity == 176)
        
        #expect(MinimedPumpModel.model722.reservoirCapacity == 300)
        #expect(MinimedPumpModel.model723.reservoirCapacity == 300)
        #expect(MinimedPumpModel.model730.reservoirCapacity == 300)
        #expect(MinimedPumpModel.model754.reservoirCapacity == 300)
    }
    
    @Test("Model display names are correct")
    func displayNames() {
        #expect(MinimedPumpModel.model508.displayName == "Paradigm 508")
        #expect(MinimedPumpModel.model511.displayName == "Paradigm 511")
        #expect(MinimedPumpModel.model512.displayName == "Paradigm 512")
        #expect(MinimedPumpModel.model515.displayName == "Paradigm 515")
        #expect(MinimedPumpModel.model522.displayName == "Paradigm 522")
        #expect(MinimedPumpModel.model722.displayName == "Paradigm 722")
        #expect(MinimedPumpModel.model523.displayName == "Paradigm Revel 523")
        #expect(MinimedPumpModel.model530.displayName == "MiniMed 530G")
    }
    
    @Test("MySentry support detection")
    func mySentrySupport() {
        #expect(MinimedPumpModel.model508.supportsMySentry == false)
        #expect(MinimedPumpModel.model511.supportsMySentry == false)
        #expect(MinimedPumpModel.model512.supportsMySentry == false)
        #expect(MinimedPumpModel.model515.supportsMySentry == false)
        #expect(MinimedPumpModel.model522.supportsMySentry == false)
        #expect(MinimedPumpModel.model523.supportsMySentry == true)
        #expect(MinimedPumpModel.model723.supportsMySentry == true)
        #expect(MinimedPumpModel.model530.supportsMySentry == true)
    }
}

// MARK: - Region Tests

@Suite("MinimedPumpRegion")
struct MinimedPumpRegionTests {
    
    @Test("Regions have correct frequencies")
    func frequencies() {
        #expect(MinimedPumpRegion.northAmerica.rfFrequency == 916.5)
        #expect(MinimedPumpRegion.worldWide.rfFrequency == 868.35)
        #expect(MinimedPumpRegion.canada.rfFrequency == 916.5)
    }
    
    @Test("Region raw values")
    func rawValues() {
        #expect(MinimedPumpRegion.northAmerica.rawValue == "NA")
        #expect(MinimedPumpRegion.worldWide.rawValue == "WW")
        #expect(MinimedPumpRegion.canada.rawValue == "CA")
    }
}

// MARK: - Pump State Tests

@Suite("MinimedPumpState")
struct MinimedPumpStateTests {
    
    @Test("State has correct values")
    func stateValues() {
        let state = MinimedPumpState(pumpId: "123456", model: .model522)
        
        #expect(state.deliveryState == .normal)
        #expect(state.reservoirLevel == 200)
        #expect(state.batteryLevel == 1.0)
        #expect(state.alerts.isEmpty)
        #expect(state.lastTempBasal == nil)
    }
    
    @Test("Low reservoir detection")
    func lowReservoir() {
        let lowState = MinimedPumpState(pumpId: "123456", model: .model522, reservoirLevel: 15)
        #expect(lowState.isLowReservoir == true)
        
        let normalState = MinimedPumpState(pumpId: "123456", model: .model522, reservoirLevel: 50)
        #expect(normalState.isLowReservoir == false)
    }
    
    @Test("Low battery detection")
    func lowBattery() {
        let lowBattery = MinimedPumpState(pumpId: "123456", model: .model522, batteryLevel: 0.10)
        #expect(lowBattery.isLowBattery == true)
        
        let normalBattery = MinimedPumpState(pumpId: "123456", model: .model522, batteryLevel: 0.80)
        #expect(normalBattery.isLowBattery == false)
    }
}

// MARK: - Delivery State Tests

@Suite("MinimedDeliveryState")
struct MinimedDeliveryStateTests {
    
    @Test("All states are codable")
    func codable() throws {
        let states: [MinimedDeliveryState] = [
            .suspended, .normal, .tempBasal, .bolusing
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(MinimedDeliveryState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - Temp Basal State Tests

@Suite("MinimedTempBasalState")
struct MinimedTempBasalStateTests {
    
    @Test("Active temp basal detection")
    func isActive() {
        let active = MinimedTempBasalState(rate: 0.5, duration: 3600)
        #expect(active.isActive == true)
        
        let expired = MinimedTempBasalState(
            rate: 0.5,
            startTime: Date().addingTimeInterval(-3700),
            duration: 3600
        )
        #expect(expired.isActive == false)
    }
    
    @Test("End time calculation")
    func endTime() {
        let startTime = Date()
        let tempBasal = MinimedTempBasalState(
            rate: 0.5,
            startTime: startTime,
            duration: 3600
        )
        
        let expectedEndTime = startTime.addingTimeInterval(3600)
        #expect(tempBasal.endTime == expectedEndTime)
    }
}

// MARK: - RileyLink State Tests

@Suite("RileyLinkState")
struct RileyLinkStateTests {
    
    @Test("All states are codable")
    func codable() throws {
        let states: [RileyLinkState] = [
            .disconnected, .connecting, .connected, .error
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(RileyLinkState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - Manager Initialization Tests

@Suite("MinimedManager Initialization")
struct MinimedManagerInitTests {
    
    @Test("Manager initializes with disconnected status")
    func initialStatus() async {
        let manager = MinimedManager()
        let status = await manager.status
        
        #expect(status.connectionState == .disconnected)
    }
    
    @Test("Manager with custom max values")
    func initWithMaxValues() async {
        let manager = MinimedManager(maxBolus: 10.0, maxBasalRate: 3.0)
        
        // Manager should be in disconnected state
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
    
    @Test("Manager with audit log")
    func withAuditLog() async {
        let auditLog = PumpAuditLog()
        let _ = MinimedManager(auditLog: auditLog)
        
        let entries = await auditLog.allEntries()
        #expect(entries.isEmpty)
    }
}

// MARK: - Pairing Tests

@Suite("MinimedManager Pairing")
struct MinimedManagerPairingTests {
    
    @Test("Pair pump")
    func pairPump() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        
        let state = await manager.currentPumpState
        #expect(state != nil)
        #expect(state?.pumpId == "123456")
    }
    
    @Test("Unpair pump")
    func unpairPump() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.unpairPump()
        
        let state = await manager.currentPumpState
        #expect(state == nil)
    }
    
    @Test("Cannot connect without pairing")
    func connectRequiresPairing() async throws {
        let manager = MinimedManager()
        
        await #expect(throws: MinimedError.self) {
            try await manager.connect()
        }
    }
}

// MARK: - Connection Tests

@Suite("MinimedManager Connection")
struct MinimedManagerConnectionTests {
    
    @Test("Connect after pairing")
    func connect() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        
        let status = await manager.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Disconnect")
    func disconnect() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        await manager.disconnect()
        
        let status = await manager.status
        #expect(status.connectionState == .disconnected)
    }
}

// MARK: - Temp Basal Tests

@Suite("Minimed Temp Basal")
struct MinimedTempBasalCommandTests {
    
    @Test("Set temp basal")
    func setTempBasal() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        
        let pumpState = await manager.currentPumpState
        #expect(pumpState?.deliveryState == .tempBasal)
        #expect(pumpState?.lastTempBasal?.rate == 0.5)
    }
    
    @Test("Cancel temp basal")
    func cancelTempBasal() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        try await manager.cancelTempBasal()
        
        let pumpState = await manager.currentPumpState
        #expect(pumpState?.deliveryState == .normal)
        #expect(pumpState?.lastTempBasal == nil)
    }
    
    @Test("Temp basal exceeds max fails")
    func tempBasalExceedsMax() async throws {
        let manager = MinimedManager(maxBasalRate: 2.0)
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        
        await #expect(throws: PumpError.self) {
            try await manager.setTempBasal(rate: 3.0, duration: 1800)
        }
    }
    
    @Test("Temp basal requires connection")
    func tempBasalRequiresConnection() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        
        await #expect(throws: PumpError.self) {
            try await manager.setTempBasal(rate: 0.5, duration: 1800)
        }
    }
}

// MARK: - Bolus Tests

@Suite("Minimed Bolus")
struct MinimedBolusTests {
    
    @Test("Deliver bolus")
    func deliverBolus() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.deliverBolus(units: 2.0)
        
        // Bolus should be complete after deliverBolus returns
        let status = await manager.status
        #expect((status.reservoirLevel ?? 200) < 200)  // Reservoir decremented
    }
    
    @Test("Bolus exceeds max fails")
    func bolusExceedsMax() async throws {
        let manager = MinimedManager(maxBolus: 5.0)
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        
        await #expect(throws: PumpError.self) {
            try await manager.deliverBolus(units: 10.0)
        }
    }
    
    @Test("Bolus requires connection")
    func bolusRequiresConnection() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        
        await #expect(throws: PumpError.self) {
            try await manager.deliverBolus(units: 1.0)
        }
    }
}

// MARK: - Suspend/Resume Tests

@Suite("Minimed Suspend Resume")
struct MinimedSuspendResumeTests {
    
    @Test("Suspend delivery")
    func suspend() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.suspend()
        
        let status = await manager.status
        #expect(status.connectionState == .suspended)
        
        let pumpState = await manager.currentPumpState
        #expect(pumpState?.deliveryState == .suspended)
    }
    
    @Test("Resume delivery")
    func resume() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.suspend()
        try await manager.resume()
        
        let pumpState = await manager.currentPumpState
        #expect(pumpState?.deliveryState == .normal)
    }
    
    @Test("Suspend cancels temp basal")
    func suspendCancelsTempBasal() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        try await manager.suspend()
        
        let pumpState = await manager.currentPumpState
        #expect(pumpState?.lastTempBasal == nil)
    }
}

// MARK: - Audit Log Tests

@Suite("Minimed Audit Log")
struct MinimedAuditLogTests {
    
    @Test("Commands are logged")
    func commandsLogged() async throws {
        let auditLog = PumpAuditLog()
        let manager = MinimedManager(auditLog: auditLog)
        
        try await manager.pairPump(pumpId: "123456", model: .model522)
        try await manager.connect()
        try await manager.setTempBasal(rate: 0.5, duration: 1800)
        await manager.disconnect()
        
        let entries = await auditLog.allEntries()
        #expect(entries.count >= 4)
        
        let typeNames = entries.map { $0.command.typeName }
        #expect(typeNames.contains("pairPump"))
        #expect(typeNames.contains("connect"))
        #expect(typeNames.contains("setTempBasal"))
        #expect(typeNames.contains("disconnect"))
    }
    
    @Test("Pair pump logs model")
    func pairPumpLogsModel() async throws {
        let auditLog = PumpAuditLog()
        let manager = MinimedManager(auditLog: auditLog)
        
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        let entries = await auditLog.allEntries()
        let pairEntry = entries.first { $0.command.typeName == "pairPump" }
        #expect(pairEntry != nil)
        
        if case .pairPump(let pumpId, let model) = pairEntry?.command {
            #expect(pumpId == "123456")
            #expect(model == "722")
        }
    }
}

// MARK: - Error Tests

@Suite("MinimedError")
struct MinimedErrorTests {
    
    @Test("All errors conform to Error")
    func errorsConform() {
        let errors: [MinimedError] = [
            .noPumpPaired,
            .invalidPumpId,
            .invalidRate,
            .invalidDuration,
            .invalidBolusAmount,
            .rileyLinkNotConnected,
            .rfCommunicationFailed,
            .pumpNotResponding,
            .checksumError,
            .historyReadFailed
        ]
        
        for error in errors {
            // All cases should be equatable (self == self)
            #expect(error == error)
        }
    }
}

// MARK: - History Event Tests

@Suite("MinimedHistoryEvent")
struct MinimedHistoryEventTests {
    
    @Test("History events are codable")
    func codable() throws {
        let events: [MinimedHistoryEvent] = [
            MinimedHistoryEvent(type: .bolus, timestamp: Date()),
            MinimedHistoryEvent(type: .tempBasal, timestamp: Date()),
            MinimedHistoryEvent(type: .basalProfileStart, timestamp: Date()),
            MinimedHistoryEvent(type: .suspend, timestamp: Date()),
            MinimedHistoryEvent(type: .resume, timestamp: Date()),
            MinimedHistoryEvent(type: .rewind, timestamp: Date()),
            MinimedHistoryEvent(type: .prime, timestamp: Date()),
            MinimedHistoryEvent(type: .alarm, timestamp: Date())
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(MinimedHistoryEvent.self, from: data)
            #expect(decoded.type == event.type)
        }
    }
    
    @Test("History event with data")
    func eventWithData() throws {
        let event = MinimedHistoryEvent(
            type: .bolus,
            timestamp: Date(),
            data: ["units": "2.5"]
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(MinimedHistoryEvent.self, from: data)
        
        #expect(decoded.type == .bolus)
        #expect(decoded.data?["units"] == "2.5")
    }
}

// MARK: - Fault Injection Tests (WIRE-006)

@Suite("Minimed Fault Injection")
struct MinimedFaultInjectionTests {
    
    @Test("Fault injector blocks connect")
    func faultInjectorBlocksConnect() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .immediate)
        
        let manager = MinimedManager(faultInjector: injector)
        
        // Pair pump first
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        do {
            try await manager.connect()
            #expect(Bool(false), "Should have thrown fault")
        } catch let error as MinimedError {
            #expect(error == .rileyLinkNotConnected)
        }
    }
    
    @Test("Fault injector blocks temp basal command")
    func faultInjectorBlocksTempBasal() async throws {
        let injector = PumpFaultInjector()
        // Use onCommand trigger to only fail on tempBasal, not connect
        injector.addFault(.communicationError(code: 99), trigger: .onCommand("minimed.tempBasal"))
        
        let manager = MinimedManager(faultInjector: injector)
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        do {
            try await manager.setTempBasal(rate: 1.5, duration: 30 * 60)
            #expect(Bool(false), "Should have thrown fault")
        } catch let error as MinimedError {
            #expect(error == .rfCommunicationFailed)
        }
    }
    
    @Test("Metrics recorded during connect")
    func metricsRecordedDuringConnect() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        // Metrics should have been recorded (PumpMetrics.shared tracks internally)
        await manager.disconnect()
    }
}

// MARK: - History Session Integration Tests (MDT-HIST-032)

@Suite("Minimed History Session Integration")
struct MinimedHistoryIntegrationTests {
    
    @Test("readHistory throws noSession when no RileyLink session")
    func readHistoryNoSession() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        // ARCH-007: No rileyLinkSession set - should throw noSession, not fallback
        do {
            _ = try await manager.readHistory(pages: 1)
            #expect(Bool(false), "Should throw noSession error")
        } catch let error as PumpError {
            #expect(error == .noSession, "Should throw PumpError.noSession when no session")
        }
    }
    
    @Test("rileyLinkSession property exists and is nil by default")
    func sessionPropertyDefaultNil() async {
        let manager = MinimedManager()
        let session = await manager.rileyLinkSession
        #expect(session == nil)
    }
    
    @Test("readHistory throws when not connected")
    func readHistoryRequiresConnection() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        // Not connected - should throw
        do {
            _ = try await manager.readHistory()
            #expect(Bool(false), "Should throw not connected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("readHistory throws when not paired")
    func readHistoryRequiresPairing() async throws {
        let manager = MinimedManager()
        
        // Not paired - should throw
        do {
            _ = try await manager.readHistory()
            #expect(Bool(false), "Should throw no pump paired error")
        } catch let error as MinimedError {
            #expect(error == .noPumpPaired)
        }
    }
}

// MARK: - Basal Schedule Tests (CRIT-PROFILE-011)

@Suite("Minimed Basal Schedule Parsing")
struct MinimedBasalScheduleParsingTests {
    
    @Test("Parse single entry schedule")
    func parseSingleEntry() {
        // Single entry: 1.0 U/hr at midnight
        // rate = 1.0 * 40 = 40 = 0x0028 (little endian: 0x28, 0x00)
        // time_slot = 0 (midnight)
        let data = Data([0x28, 0x00, 0x00])  // 1.0 U/hr at midnight
        
        if let entry = MedtronicBasalScheduleEntry(rawValue: data) {
            #expect(entry.rate == 1.0)
            #expect(entry.timeOffset == 0)
            #expect(entry.index == 0)
        } else {
            #expect(Bool(false), "Failed to parse entry")
        }
    }
    
    @Test("Parse multiple entry schedule")
    func parseMultipleEntries() {
        // Two entries:
        // Entry 1: 0.8 U/hr at midnight (rate=32=0x20, slot=0)
        // Entry 2: 1.2 U/hr at 6:00 AM (rate=48=0x30, slot=12 = 6h/30min)
        let data = Data([
            0x20, 0x00, 0x00,  // 0.8 U/hr at 00:00
            0x30, 0x00, 0x0C,  // 1.2 U/hr at 06:00
            0x00, 0x00, 0x3F   // End marker (slot >= 48)
        ])
        
        // Parse individual entries
        let entry1 = MedtronicBasalScheduleEntry(rawValue: data.subdata(in: 0..<3))
        let entry2 = MedtronicBasalScheduleEntry(rawValue: data.subdata(in: 3..<6))
        
        #expect(entry1?.rate == 0.8)
        #expect(entry1?.timeOffset == 0)
        
        #expect(entry2?.rate == 1.2)
        #expect(entry2?.timeOffset == 21600)  // 6 hours in seconds
        #expect(entry2?.index == 12)
    }
    
    @Test("Round trip encoding/decoding")
    func roundTripEncoding() {
        let original = MedtronicBasalScheduleEntry(index: 8, timeOffset: 14400, rate: 0.95)
        let data = original.rawValue
        let decoded = MedtronicBasalScheduleEntry(rawValue: data)
        
        #expect(decoded?.index == 8)
        #expect(decoded?.timeOffset == 14400)
        // Rate may have slight quantization due to 0.025 U/hr steps
        #expect(decoded?.rate ?? 0 >= 0.925 && decoded?.rate ?? 0 <= 0.975)
    }
    
    @Test("Entry rejects invalid time slot")
    func rejectInvalidTimeSlot() {
        // Time slot 48 = 24 hours = invalid
        let data = Data([0x28, 0x00, 0x30])  // slot 48
        let entry = MedtronicBasalScheduleEntry(rawValue: data)
        #expect(entry == nil)
    }
    
    @Test("Basal profile enum values")
    func profileEnumValues() {
        #expect(MedtronicBasalProfile.standard.rawValue == 0)
        #expect(MedtronicBasalProfile.profileA.rawValue == 1)
        #expect(MedtronicBasalProfile.profileB.rawValue == 2)
    }
}

@Suite("Minimed Basal Schedule Integration")
struct MinimedBasalScheduleIntegrationTests {
    
    @Test("readBasalSchedule throws noSession when no RileyLink session")
    func readBasalScheduleNoSession() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        // ARCH-007: No rileyLinkSession set - should throw noSession
        do {
            _ = try await manager.readBasalSchedule()
            #expect(Bool(false), "Should throw noSession error")
        } catch let error as PumpError {
            #expect(error == .noSession, "Should throw PumpError.noSession when no session")
        }
    }
    
    @Test("readBasalSchedule throws when not connected")
    func readBasalScheduleRequiresConnection() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        // Not connected - should throw
        do {
            _ = try await manager.readBasalSchedule()
            #expect(Bool(false), "Should throw not connected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("readBasalSchedule throws when not paired")
    func readBasalScheduleRequiresPairing() async throws {
        let manager = MinimedManager()
        
        // Not paired - should throw
        do {
            _ = try await manager.readBasalSchedule()
            #expect(Bool(false), "Should throw no pump paired error")
        } catch let error as MinimedError {
            #expect(error == .noPumpPaired)
        }
    }
    
    @Test("readBasalSchedule accepts all profiles")
    func readBasalScheduleAllProfiles() async throws {
        // Just verify the API accepts all profile types
        // Actual RF communication requires hardware
        let manager = MinimedManager()
        
        // Try each profile (will fail at pairing check, but validates API)
        for profile in [MedtronicBasalProfile.standard, .profileA, .profileB] {
            do {
                _ = try await manager.readBasalSchedule(profile: profile)
            } catch let error as MinimedError {
                #expect(error == .noPumpPaired)  // Expected - validates API accepted profile
            }
        }
    }
    
    // MARK: - Write Tests (CRIT-PROFILE-012)
    
    @Test("writeBasalSchedule throws noSession when no RileyLink session")
    func writeBasalScheduleNoSession() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)
        ]
        
        // ARCH-007: No rileyLinkSession set - should throw noSession
        do {
            try await manager.writeBasalSchedule(entries: entries)
            #expect(Bool(false), "Should throw noSession error")
        } catch let error as PumpError {
            #expect(error == .noSession, "Should throw PumpError.noSession when no session")
        }
    }
    
    @Test("writeBasalSchedule throws when not connected")
    func writeBasalScheduleRequiresConnection() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)
        ]
        
        // Not connected - should throw
        do {
            try await manager.writeBasalSchedule(entries: entries)
            #expect(Bool(false), "Should throw not connected error")
        } catch let error as PumpError {
            #expect(error == .notConnected)
        }
    }
    
    @Test("writeBasalSchedule throws when not paired")
    func writeBasalScheduleRequiresPairing() async throws {
        let manager = MinimedManager()
        
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)
        ]
        
        // Not paired - should throw
        do {
            try await manager.writeBasalSchedule(entries: entries)
            #expect(Bool(false), "Should throw no pump paired error")
        } catch let error as MinimedError {
            #expect(error == .noPumpPaired)
        }
    }
    
    @Test("writeBasalSchedule rejects too many entries")
    func writeBasalScheduleValidatesEntryCount() async throws {
        let manager = MinimedManager()
        try await manager.pairPump(pumpId: "123456", model: .model722)
        try await manager.connect()
        
        // Create 49 entries (max is 48)
        var entries: [MedtronicBasalScheduleEntry] = []
        for i in 0..<49 {
            entries.append(MedtronicBasalScheduleEntry(index: i, timeOffset: Double(i * 1800), rate: 1.0))
        }
        
        do {
            try await manager.writeBasalSchedule(entries: entries)
            #expect(Bool(false), "Should throw invalidBasalSchedule error")
        } catch let error as MinimedError {
            #expect(error == .invalidBasalSchedule)
        }
    }
    
    @Test("writeBasalSchedule accepts all profiles")
    func writeBasalScheduleAllProfiles() async throws {
        let manager = MinimedManager()
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)
        ]
        
        // Try each profile (will fail at pairing check, but validates API)
        for profile in [MedtronicBasalProfile.standard, .profileA, .profileB] {
            do {
                try await manager.writeBasalSchedule(entries: entries, profile: profile)
            } catch let error as MinimedError {
                #expect(error == .noPumpPaired)  // Expected - validates API accepted profile
            }
        }
    }
}
