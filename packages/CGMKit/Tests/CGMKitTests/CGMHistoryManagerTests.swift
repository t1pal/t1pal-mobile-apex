// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CGMHistoryManagerTests.swift
// Trace: LIFE-CGM-007, LIFE-CGM-008

import Testing
import Foundation
@testable import CGMKit

// MARK: - TransmitterHistoryEntry Tests

@Suite("TransmitterHistoryEntry Tests")
struct TransmitterHistoryEntryTests {
    
    @Test("Create transmitter history entry")
    func createEntry() {
        let activation = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let deactivation = Date()
        
        let entry = TransmitterHistoryEntry(
            transmitterId: "ABC123",
            cgmType: .dexcomG6,
            activationDate: activation,
            deactivationDate: deactivation,
            plannedLifetimeDays: 90,
            endReason: .expired,
            sensorsUsed: 3
        )
        
        #expect(entry.transmitterId == "ABC123")
        #expect(entry.cgmType == .dexcomG6)
        #expect(entry.plannedLifetimeDays == 90)
        #expect(entry.sensorsUsed == 3)
        #expect(entry.actualDurationDays >= 29 && entry.actualDurationDays <= 31)
    }
    
    @Test("Create from TransmitterSession")
    func createFromSession() {
        let session = TransmitterSession(
            transmitterId: "DEF456",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-86400 * 60)
        )
        
        let entry = TransmitterHistoryEntry(
            from: session,
            deactivationDate: Date(),
            endReason: .batteryDepleted,
            sensorsUsed: 6
        )
        
        #expect(entry.transmitterId == "DEF456")
        #expect(entry.cgmType == .dexcomG6)
        #expect(entry.endReason == .batteryDepleted)
        #expect(entry.sensorsUsed == 6)
    }
    
    @Test("Full lifetime detection")
    func fullLifetimeDetection() {
        let activation = Date().addingTimeInterval(-86400 * 88) // 88 days ago
        let entry = TransmitterHistoryEntry(
            transmitterId: "FULL",
            cgmType: .dexcomG6,
            activationDate: activation,
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        #expect(entry.usedFullLifetime == true)
    }
    
    @Test("Early replacement detection")
    func earlyReplacementDetection() {
        let activation = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let entry = TransmitterHistoryEntry(
            transmitterId: "EARLY",
            cgmType: .dexcomG6,
            activationDate: activation,
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        #expect(entry.usedFullLifetime == false)
    }
    
    @Test("Duration text formatting")
    func durationTextFormatting() {
        let activation = Date().addingTimeInterval(-86400 * 45) // 45 days ago
        let entry = TransmitterHistoryEntry(
            transmitterId: "FORMAT",
            cgmType: .dexcomG6,
            activationDate: activation,
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        #expect(entry.durationText == "45 days")
    }
}

// MARK: - TransmitterEndReason Tests

@Suite("TransmitterEndReason Tests")
struct TransmitterEndReasonTests {
    
    @Test("All reasons have display text")
    func allReasonsHaveDisplayText() {
        for reason in TransmitterEndReason.allCases {
            #expect(!reason.displayText.isEmpty)
        }
    }
    
    @Test("Expired display text")
    func expiredDisplayText() {
        #expect(TransmitterEndReason.expired.displayText == "Expired")
    }
    
    @Test("Battery depleted display text")
    func batteryDepletedDisplayText() {
        #expect(TransmitterEndReason.batteryDepleted.displayText == "Battery depleted")
    }
}

// MARK: - SensorHistoryEntry Extension Tests

@Suite("SensorHistoryEntry Extension Tests")
struct SensorHistoryEntryExtensionTests {
    
    @Test("Duration hours calculation")
    func durationHoursCalculation() {
        let start = Date().addingTimeInterval(-3600 * 48) // 48 hours ago
        let end = Date()
        
        let entry = SensorHistoryEntry(
            sensorType: "dexcomG6",
            startDate: start,
            endDate: end,
            endReason: .expired
        )
        
        let hours = entry.durationHours
        #expect(hours >= 47 && hours <= 49)
    }
    
    @Test("Duration text for multi-day")
    func durationTextMultiDay() {
        let start = Date().addingTimeInterval(-3600 * 72) // 72 hours ago
        let end = Date()
        
        let entry = SensorHistoryEntry(
            sensorType: "dexcomG6",
            startDate: start,
            endDate: end,
            endReason: .expired
        )
        
        let text = entry.durationText
        #expect(text.contains("d"))
    }
    
    @Test("CGM type derivation")
    func cgmTypeDerivation() {
        let entry = SensorHistoryEntry(
            sensorType: "dexcomG6",
            startDate: Date(),
            endDate: Date(),
            endReason: .expired
        )
        
        #expect(entry.cgmType == .dexcomG6)
    }
}

// MARK: - InMemoryCGMHistoryPersistence Tests

@Suite("InMemoryCGMHistoryPersistence Tests")
struct InMemoryCGMHistoryPersistenceTests {
    
    @Test("Save and load sensor entry")
    func saveAndLoadSensor() async {
        let persistence = InMemoryCGMHistoryPersistence()
        
        let entry = SensorHistoryEntry(
            sensorType: "dexcomG7",
            startDate: Date().addingTimeInterval(-86400),
            endDate: Date(),
            endReason: .expired
        )
        
        await persistence.saveSensorEntry(entry)
        let loaded = await persistence.loadSensorHistory()
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.sensorType == "dexcomG7")
    }
    
    @Test("Save and load transmitter entry")
    func saveAndLoadTransmitter() async {
        let persistence = InMemoryCGMHistoryPersistence()
        
        let entry = TransmitterHistoryEntry(
            transmitterId: "TEST123",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-86400 * 90),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        await persistence.saveTransmitterEntry(entry)
        let loaded = await persistence.loadTransmitterHistory()
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.transmitterId == "TEST123")
    }
    
    @Test("Clear sensor history")
    func clearSensorHistory() async {
        let persistence = InMemoryCGMHistoryPersistence()
        
        let entry = SensorHistoryEntry(
            sensorType: "libre2",
            startDate: Date(),
            endDate: Date(),
            endReason: .removed
        )
        
        await persistence.saveSensorEntry(entry)
        await persistence.clearSensorHistory()
        let loaded = await persistence.loadSensorHistory()
        
        #expect(loaded.isEmpty)
    }
    
    @Test("Clear transmitter history")
    func clearTransmitterHistory() async {
        let persistence = InMemoryCGMHistoryPersistence()
        
        let entry = TransmitterHistoryEntry(
            transmitterId: "CLEAR",
            cgmType: .dexcomG6,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        await persistence.saveTransmitterEntry(entry)
        await persistence.clearTransmitterHistory()
        let loaded = await persistence.loadTransmitterHistory()
        
        #expect(loaded.isEmpty)
    }
}

// MARK: - CGMHistoryManager Tests

@Suite("CGMHistoryManager Tests")
struct CGMHistoryManagerTests {
    
    @Test("Manager can be created")
    func managerCreation() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        let history = await manager.getSensorHistory()
        #expect(history.isEmpty)
    }
    
    @Test("Log sensor session")
    func logSensorSession() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        await manager.logSensorSession(
            sensorType: "dexcomG6",
            transmitterId: "ABC123",
            startDate: Date().addingTimeInterval(-86400 * 10),
            endDate: Date(),
            endReason: .expired
        )
        
        let history = await manager.getSensorHistory()
        #expect(history.count == 1)
    }
    
    @Test("Log transmitter")
    func logTransmitter() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        await manager.logTransmitter(
            transmitterId: "XMIT001",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-86400 * 90),
            deactivationDate: Date(),
            plannedLifetimeDays: 90,
            endReason: .expired,
            sensorsUsed: 9
        )
        
        let history = await manager.getTransmitterHistory()
        #expect(history.count == 1)
        #expect(history.first?.sensorsUsed == 9)
    }
    
    @Test("Sensor count tracking")
    func sensorCountTracking() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        // Log 3 sensors
        for i in 1...3 {
            await manager.logSensorSession(
                sensorType: "dexcomG6",
                startDate: Date().addingTimeInterval(Double(-86400 * i * 10)),
                endDate: Date().addingTimeInterval(Double(-86400 * (i - 1) * 10)),
                endReason: .expired
            )
        }
        
        let count = await manager.getCurrentSensorCount()
        #expect(count == 3)
    }
    
    @Test("Sensor count resets on transmitter log")
    func sensorCountResetsOnTransmitterLog() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        // Log 2 sensors
        for _ in 1...2 {
            await manager.logSensorSession(
                sensorType: "dexcomG6",
                startDate: Date(),
                endDate: Date(),
                endReason: .expired
            )
        }
        
        // Log transmitter
        await manager.logTransmitter(
            transmitterId: "RESET",
            cgmType: .dexcomG6,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        let count = await manager.getCurrentSensorCount()
        #expect(count == 0)
    }
    
    @Test("Get recent sensor history")
    func getRecentSensorHistory() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        // Log 5 sensors
        for i in 1...5 {
            await manager.logSensorSession(
                sensorType: "dexcomG6",
                startDate: Date().addingTimeInterval(Double(-86400 * i)),
                endDate: Date().addingTimeInterval(Double(-86400 * (i - 1))),
                endReason: .expired
            )
        }
        
        let recent = await manager.getRecentSensorHistory(limit: 3)
        #expect(recent.count == 3)
    }
    
    @Test("Get history summary")
    func getHistorySummary() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        await manager.logSensorSession(
            sensorType: "dexcomG6",
            startDate: Date().addingTimeInterval(-86400 * 10),
            endDate: Date(),
            endReason: .expired
        )
        
        await manager.logTransmitter(
            transmitterId: "SUM001",
            cgmType: .dexcomG6,
            activationDate: Date().addingTimeInterval(-86400 * 90),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        let summary = await manager.getSummary()
        #expect(summary.totalSensors == 1)
        #expect(summary.totalTransmitters == 1)
    }
    
    @Test("Clear all history")
    func clearAllHistory() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        await manager.logSensorSession(
            sensorType: "libre2",
            startDate: Date(),
            endDate: Date(),
            endReason: .expired
        )
        
        await manager.logTransmitter(
            transmitterId: "CLEAR",
            cgmType: .dexcomG6,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        await manager.clearAllHistory()
        
        let sensors = await manager.getSensorHistory()
        let transmitters = await manager.getTransmitterHistory()
        
        #expect(sensors.isEmpty)
        #expect(transmitters.isEmpty)
    }
    
    @Test("Filter by CGM type")
    func filterByCGMType() async {
        let manager = CGMHistoryManager(persistence: InMemoryCGMHistoryPersistence())
        
        await manager.logTransmitter(
            transmitterId: "G6_001",
            cgmType: .dexcomG6,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeDays: 90
        )
        
        await manager.logTransmitter(
            transmitterId: "G7_001",
            cgmType: .dexcomG7,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeDays: 10
        )
        
        let g6History = await manager.getTransmitterHistory(for: .dexcomG6)
        let g7History = await manager.getTransmitterHistory(for: .dexcomG7)
        
        #expect(g6History.count == 1)
        #expect(g7History.count == 1)
        #expect(g6History.first?.transmitterId == "G6_001")
    }
}

// MARK: - CGMHistorySummary Tests

@Suite("CGMHistorySummary Tests")
struct CGMHistorySummaryTests {
    
    @Test("Empty history summary")
    func emptyHistorySummary() {
        let summary = CGMHistorySummary(sensorHistory: [], transmitterHistory: [])
        
        #expect(summary.totalSensors == 0)
        #expect(summary.totalTransmitters == 0)
        #expect(summary.averageSensorDurationHours == 0)
        #expect(summary.averageTransmitterDurationDays == 0)
    }
    
    @Test("Summary with transmitters")
    func summaryWithTransmitters() {
        let entries = [
            TransmitterHistoryEntry(
                transmitterId: "T1",
                cgmType: .dexcomG6,
                activationDate: Date().addingTimeInterval(-86400 * 90),
                deactivationDate: Date(),
                plannedLifetimeDays: 90
            ),
            TransmitterHistoryEntry(
                transmitterId: "T2",
                cgmType: .dexcomG6,
                activationDate: Date().addingTimeInterval(-86400 * 60),
                deactivationDate: Date(),
                plannedLifetimeDays: 90
            )
        ]
        
        let summary = CGMHistorySummary(sensorHistory: [], transmitterHistory: entries)
        
        #expect(summary.totalTransmitters == 2)
        #expect(summary.averageTransmitterDurationDays > 0)
    }
}
