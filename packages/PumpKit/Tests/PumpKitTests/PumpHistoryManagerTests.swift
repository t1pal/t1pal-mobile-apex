// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PumpHistoryManagerTests.swift
// PumpKitTests
//
// Tests for PumpHistoryManager (LIFE-PUMP-008)

import Testing
import Foundation
@testable import PumpKit

// MARK: - PumpConsumableEntry Tests

@Suite("PumpConsumableEntry Tests")
struct PumpConsumableEntryTests {
    
    @Test("Entry calculates duration correctly")
    func durationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(72 * 3600)  // 72 hours
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: start,
            deactivationDate: end,
            plannedLifetimeHours: 80
        )
        
        #expect(abs(entry.actualDurationHours - 72) < 0.01)
    }
    
    @Test("Entry formats duration text correctly")
    func durationTextFormatting() {
        let start = Date()
        let end = start.addingTimeInterval(75 * 3600)  // 75 hours = 3d 3h
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: start,
            deactivationDate: end,
            plannedLifetimeHours: 80
        )
        
        #expect(entry.durationText == "3d 3h")
    }
    
    @Test("Entry formats short duration correctly")
    func shortDurationText() {
        let start = Date()
        let end = start.addingTimeInterval(12 * 3600)  // 12 hours
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: start,
            deactivationDate: end,
            plannedLifetimeHours: 80
        )
        
        #expect(entry.durationText == "12h")
    }
    
    @Test("Entry detects full lifetime usage")
    func fullLifetimeUsage() {
        let start = Date()
        let end = start.addingTimeInterval(78 * 3600)  // 78 hours (>95% of 80)
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: start,
            deactivationDate: end,
            plannedLifetimeHours: 80
        )
        
        #expect(entry.usedFullLifetime == true)
    }
    
    @Test("Entry detects early replacement")
    func earlyReplacement() {
        let start = Date()
        let end = start.addingTimeInterval(40 * 3600)  // 40 hours (<95% of 80)
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: start,
            deactivationDate: end,
            plannedLifetimeHours: 80
        )
        
        #expect(entry.usedFullLifetime == false)
    }
    
    @Test("Entry returns correct consumable name for Omnipod")
    func consumableNameOmnipod() {
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 80
        )
        
        #expect(entry.consumableName == "Pod")
    }
    
    @Test("Entry returns correct consumable name for Medtronic")
    func consumableNameMedtronic() {
        let entry = PumpConsumableEntry(
            pumpType: .medtronic,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 72
        )
        
        #expect(entry.consumableName == "Reservoir")
    }
    
    @Test("Entry returns correct consumable name for Tandem")
    func consumableNameTandem() {
        let entry = PumpConsumableEntry(
            pumpType: .tandemX2,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 72
        )
        
        #expect(entry.consumableName == "Cartridge")
    }
    
    @Test("Entry is Codable")
    func codableSupport() throws {
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 80,
            insulinDelivered: 150.5,
            podLotNumber: "L12345"
        )
        
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(PumpConsumableEntry.self, from: data)
        
        #expect(decoded.pumpType == entry.pumpType)
        #expect(decoded.insulinDelivered == entry.insulinDelivered)
        #expect(decoded.podLotNumber == entry.podLotNumber)
    }
}

// MARK: - PumpConsumableEndReason Tests

@Suite("PumpConsumableEndReason Tests")
struct PumpConsumableEndReasonTests {
    
    @Test("End reason has display text")
    func displayText() {
        #expect(PumpConsumableEndReason.expired.displayText == "Expired")
        #expect(PumpConsumableEndReason.empty.displayText == "Empty")
        #expect(PumpConsumableEndReason.occlusion.displayText == "Occlusion detected")
        #expect(PumpConsumableEndReason.podFault.displayText == "Pod fault")
    }
    
    @Test("End reason identifies failures correctly")
    func failureIdentification() {
        // Not failures
        #expect(PumpConsumableEndReason.expired.isFailure == false)
        #expect(PumpConsumableEndReason.empty.isFailure == false)
        #expect(PumpConsumableEndReason.userReplaced.isFailure == false)
        
        // Failures
        #expect(PumpConsumableEndReason.occlusion.isFailure == true)
        #expect(PumpConsumableEndReason.podFault.isFailure == true)
        #expect(PumpConsumableEndReason.siteFailure.isFailure == true)
        #expect(PumpConsumableEndReason.communication.isFailure == true)
    }
    
    @Test("End reason is CaseIterable")
    func caseIterable() {
        #expect(PumpConsumableEndReason.allCases.count == 8)
    }
}

// MARK: - PumpHistorySummary Tests

@Suite("PumpHistorySummary Tests")
struct PumpHistorySummaryTests {
    
    @Test("Summary calculates averages correctly")
    func averageCalculation() {
        let start = Date()
        let entries = [
            PumpConsumableEntry(
                pumpType: .omnipodDash,
                activationDate: start,
                deactivationDate: start.addingTimeInterval(72 * 3600),
                plannedLifetimeHours: 80
            ),
            PumpConsumableEntry(
                pumpType: .omnipodDash,
                activationDate: start,
                deactivationDate: start.addingTimeInterval(80 * 3600),
                plannedLifetimeHours: 80
            )
        ]
        
        let summary = PumpHistorySummary(history: entries)
        
        #expect(summary.totalConsumables == 2)
        #expect(abs(summary.averageDurationHours - 76) < 0.01)  // (72 + 80) / 2
    }
    
    @Test("Summary calculates failure rate correctly")
    func failureRateCalculation() {
        let start = Date()
        let entries = [
            PumpConsumableEntry(
                pumpType: .omnipodDash,
                activationDate: start,
                deactivationDate: start.addingTimeInterval(72 * 3600),
                plannedLifetimeHours: 80,
                endReason: .expired
            ),
            PumpConsumableEntry(
                pumpType: .omnipodDash,
                activationDate: start,
                deactivationDate: start.addingTimeInterval(40 * 3600),
                plannedLifetimeHours: 80,
                endReason: .occlusion
            )
        ]
        
        let summary = PumpHistorySummary(history: entries)
        
        #expect(abs(summary.failureRate - 0.5) < 0.01)  // 1 failure out of 2
    }
    
    @Test("Summary handles empty history")
    func emptyHistory() {
        let summary = PumpHistorySummary(history: [])
        
        #expect(summary.totalConsumables == 0)
        #expect(summary.averageDurationHours == 0)
        #expect(summary.failureRate == 0)
    }
    
    @Test("Summary formats failure rate as percentage")
    func failureRateText() {
        let start = Date()
        let entries = [
            PumpConsumableEntry(
                pumpType: .omnipodDash,
                activationDate: start,
                deactivationDate: start.addingTimeInterval(72 * 3600),
                plannedLifetimeHours: 80,
                endReason: .occlusion
            )
        ]
        
        let summary = PumpHistorySummary(history: entries)
        
        #expect(summary.failureRateText == "100.0%")
    }
    
    @Test("Summary groups by pump type")
    func groupByPumpType() {
        let start = Date()
        let entries = [
            PumpConsumableEntry(pumpType: .omnipodDash, activationDate: start, deactivationDate: start.addingTimeInterval(3600), plannedLifetimeHours: 80),
            PumpConsumableEntry(pumpType: .omnipodDash, activationDate: start, deactivationDate: start.addingTimeInterval(3600), plannedLifetimeHours: 80),
            PumpConsumableEntry(pumpType: .medtronic, activationDate: start, deactivationDate: start.addingTimeInterval(3600), plannedLifetimeHours: 72)
        ]
        
        let summary = PumpHistorySummary(history: entries)
        
        #expect(summary.byPumpType[.omnipodDash] == 2)
        #expect(summary.byPumpType[.medtronic] == 1)
    }
}

// MARK: - InMemoryPumpHistoryPersistence Tests

@Suite("InMemoryPumpHistoryPersistence Tests")
struct InMemoryPumpHistoryPersistenceTests {
    
    @Test("Persistence saves and loads entries")
    func saveAndLoad() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 80
        )
        
        await persistence.saveEntry(entry)
        let history = await persistence.loadHistory()
        
        #expect(history.count == 1)
        #expect(history.first?.pumpType == .omnipodDash)
    }
    
    @Test("Persistence clears history")
    func clearHistory() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 80
        )
        
        await persistence.saveEntry(entry)
        await persistence.clearHistory()
        let history = await persistence.loadHistory()
        
        #expect(history.isEmpty)
    }
    
    @Test("Persistence returns sorted by deactivation date")
    func sortedByDate() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let now = Date()
        
        // Add older entry first
        await persistence.saveEntry(PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: now.addingTimeInterval(-200 * 3600),
            deactivationDate: now.addingTimeInterval(-100 * 3600),
            plannedLifetimeHours: 80
        ))
        
        // Add newer entry second
        await persistence.saveEntry(PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: now.addingTimeInterval(-80 * 3600),
            deactivationDate: now,
            plannedLifetimeHours: 80
        ))
        
        let history = await persistence.loadHistory()
        
        #expect(history.count == 2)
        #expect(history.first!.deactivationDate > history.last!.deactivationDate)
    }
}

// MARK: - PumpHistoryManager Tests

@Suite("PumpHistoryManager Tests")
struct PumpHistoryManagerTests {
    
    @Test("Manager logs consumable entry")
    func logEntry() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        
        let entry = PumpConsumableEntry(
            pumpType: .omnipodDash,
            activationDate: Date(),
            deactivationDate: Date(),
            plannedLifetimeHours: 80
        )
        
        await manager.logConsumable(entry)
        let history = await manager.getHistory()
        
        #expect(history.count == 1)
    }
    
    @Test("Manager logs consumable with parameters")
    func logWithParameters() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        
        let now = Date()
        await manager.logConsumable(
            pumpType: .medtronic,
            activationDate: now.addingTimeInterval(-72 * 3600),
            deactivationDate: now,
            plannedLifetimeHours: 72,
            endReason: .empty,
            insulinDelivered: 180.5
        )
        
        let history = await manager.getHistory()
        
        #expect(history.count == 1)
        #expect(history.first?.pumpType == .medtronic)
        #expect(history.first?.endReason == .empty)
        #expect(history.first?.insulinDelivered == 180.5)
    }
    
    @Test("Manager filters by pump type")
    func filterByPumpType() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80)
        await manager.logConsumable(pumpType: .medtronic, activationDate: now, deactivationDate: now, plannedLifetimeHours: 72)
        
        let dashHistory = await manager.getHistory(for: .omnipodDash)
        let medtronicHistory = await manager.getHistory(for: .medtronic)
        
        #expect(dashHistory.count == 2)
        #expect(medtronicHistory.count == 1)
    }
    
    @Test("Manager filters by end reason")
    func filterByEndReason() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .expired)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .occlusion)
        
        let expired = await manager.getHistory(endReason: .expired)
        let occlusions = await manager.getHistory(endReason: .occlusion)
        
        #expect(expired.count == 1)
        #expect(occlusions.count == 1)
    }
    
    @Test("Manager returns failures only")
    func getFailures() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .expired)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .occlusion)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .podFault)
        
        let failures = await manager.getFailures()
        
        #expect(failures.count == 2)  // occlusion + podFault
    }
    
    @Test("Manager limits recent history")
    func recentHistoryLimit() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        for i in 0..<20 {
            await manager.logConsumable(
                pumpType: .omnipodDash,
                activationDate: now.addingTimeInterval(Double(-i * 100) * 3600),
                deactivationDate: now.addingTimeInterval(Double(-i * 100 + 80) * 3600),
                plannedLifetimeHours: 80
            )
        }
        
        let recent = await manager.getRecentHistory(limit: 5)
        
        #expect(recent.count == 5)
    }
    
    @Test("Manager generates summary")
    func generateSummary() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now.addingTimeInterval(-80 * 3600), deactivationDate: now, plannedLifetimeHours: 80)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now.addingTimeInterval(-72 * 3600), deactivationDate: now, plannedLifetimeHours: 80)
        
        let summary = await manager.getSummary()
        
        #expect(summary.totalConsumables == 2)
    }
    
    @Test("Manager calculates average duration for pump type")
    func averageDurationForPumpType() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now.addingTimeInterval(-72 * 3600), deactivationDate: now, plannedLifetimeHours: 80)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now.addingTimeInterval(-80 * 3600), deactivationDate: now, plannedLifetimeHours: 80)
        
        let avgDuration = await manager.getAverageDuration(for: .omnipodDash)
        
        #expect(avgDuration != nil)
        // Average of 72h and 80h = 76h = 273600 seconds
        #expect(abs(avgDuration! - 273600) < 100)
    }
    
    @Test("Manager calculates failure rate for pump type")
    func failureRateForPumpType() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .expired)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .expired)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .occlusion)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, endReason: .podFault)
        
        let failureRate = await manager.getFailureRate(for: .omnipodDash)
        
        #expect(failureRate != nil)
        #expect(abs(failureRate! - 0.5) < 0.01)  // 2 failures out of 4
    }
    
    @Test("Manager clears history")
    func clearHistory() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80)
        await manager.clearHistory()
        
        let count = await manager.getTotalCount()
        
        #expect(count == 0)
    }
    
    @Test("Manager calculates total insulin delivered")
    func totalInsulinDelivered() async {
        let persistence = InMemoryPumpHistoryPersistence()
        let manager = PumpHistoryManager(persistence: persistence)
        let now = Date()
        
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, insulinDelivered: 100.0)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80, insulinDelivered: 150.0)
        await manager.logConsumable(pumpType: .omnipodDash, activationDate: now, deactivationDate: now, plannedLifetimeHours: 80)  // No insulin data
        
        let total = await manager.getTotalInsulinDelivered()
        
        #expect(abs(total - 250.0) < 0.01)
    }
}
