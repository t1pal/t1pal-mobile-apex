// SPDX-License-Identifier: MIT
//
// AlgorithmStatePersistenceTests.swift
// T1Pal Mobile
//
// Tests for algorithm state persistence
// Trace: PROD-AID-002

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Persisted Algorithm State Tests

@Suite("Persisted Algorithm State")
struct PersistedAlgorithmStateTests {
    
    @Test("Create state with IOB and COB")
    func createStateWithIOBAndCOB() {
        let state = PersistedAlgorithmState(
            iob: 2.5,
            basalIOB: 1.0,
            bolusIOB: 1.5,
            cob: 30.0
        )
        
        #expect(state.iob == 2.5)
        #expect(state.basalIOB == 1.0)
        #expect(state.bolusIOB == 1.5)
        #expect(state.cob == 30.0)
    }
    
    @Test("State age calculation")
    func stateAgeCalculation() {
        let oldState = PersistedAlgorithmState(
            timestamp: Date().addingTimeInterval(-120),  // 2 minutes ago
            iob: 1.0,
            cob: 0
        )
        
        #expect(oldState.age >= 120)
        #expect(oldState.age < 130)  // Allow some tolerance
    }
    
    @Test("State staleness detection")
    func stateStalenessDetection() {
        let freshState = PersistedAlgorithmState(
            timestamp: Date(),
            iob: 1.0,
            cob: 0
        )
        #expect(freshState.isStale == false)
        #expect(freshState.isVeryStale == false)
        
        let staleState = PersistedAlgorithmState(
            timestamp: Date().addingTimeInterval(-700),  // 11+ minutes
            iob: 1.0,
            cob: 0
        )
        #expect(staleState.isStale == true)
        #expect(staleState.isVeryStale == false)
        
        let veryStaleState = PersistedAlgorithmState(
            timestamp: Date().addingTimeInterval(-2000),  // 33+ minutes
            iob: 1.0,
            cob: 0
        )
        #expect(veryStaleState.isStale == true)
        #expect(veryStaleState.isVeryStale == true)
    }
    
    @Test("State with glucose context")
    func stateWithGlucoseContext() {
        let state = PersistedAlgorithmState(
            iob: 2.0,
            cob: 20.0,
            currentGlucose: 120.0,
            targetLow: 100.0,
            targetHigh: 120.0
        )
        
        #expect(state.currentGlucose == 120.0)
        #expect(state.targetLow == 100.0)
        #expect(state.targetHigh == 120.0)
    }
    
    @Test("State with temp basal info")
    func stateWithTempBasalInfo() {
        let tempStart = Date().addingTimeInterval(-1800)
        let state = PersistedAlgorithmState(
            iob: 1.5,
            cob: 0,
            lastTempBasalRate: 0.5,
            lastTempBasalStart: tempStart
        )
        
        #expect(state.lastTempBasalRate == 0.5)
        #expect(state.lastTempBasalStart == tempStart)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedAlgorithmState(
            iob: 3.2,
            basalIOB: 1.2,
            bolusIOB: 2.0,
            cob: 45.0,
            currentGlucose: 110.0,
            targetLow: 100.0,
            targetHigh: 120.0,
            algorithmVersion: "oref1-1.0",
            loopActive: true,
            autosensRatio: 0.95
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedAlgorithmState.self, from: data)
        
        #expect(decoded.iob == original.iob)
        #expect(decoded.basalIOB == original.basalIOB)
        #expect(decoded.bolusIOB == original.bolusIOB)
        #expect(decoded.cob == original.cob)
        #expect(decoded.currentGlucose == original.currentGlucose)
        #expect(decoded.algorithmVersion == "oref1-1.0")
        #expect(decoded.autosensRatio == 0.95)
    }
}

// MARK: - Algorithm Decision Record Tests

@Suite("Algorithm Decision Record")
struct AlgorithmDecisionRecordTests {
    
    @Test("Create temp basal decision")
    func createTempBasalDecision() {
        let decision = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 1.5,
            suggestedTempBasalDuration: 1800,
            reason: "BG dropping, reduce insulin",
            iobAtDecision: 2.0,
            cobAtDecision: 30.0,
            glucoseAtDecision: 95.0
        )
        
        #expect(decision.decisionType == .tempBasal)
        #expect(decision.suggestedTempBasalRate == 1.5)
        #expect(decision.suggestedTempBasalDuration == 1800)
        #expect(decision.iobAtDecision == 2.0)
        #expect(decision.cobAtDecision == 30.0)
    }
    
    @Test("Create SMB decision")
    func createSMBDecision() {
        let decision = AlgorithmDecisionRecord(
            decisionType: .smb,
            suggestedSMB: 0.5,
            reason: "UAM detected, need more insulin",
            iobAtDecision: 1.5,
            cobAtDecision: 0,
            glucoseAtDecision: 180.0
        )
        
        #expect(decision.decisionType == .smb)
        #expect(decision.suggestedSMB == 0.5)
    }
    
    @Test("Create no-action decision")
    func createNoActionDecision() {
        let decision = AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "BG in range, no action needed",
            iobAtDecision: 0.5,
            cobAtDecision: 0
        )
        
        #expect(decision.decisionType == .noAction)
        #expect(decision.suggestedTempBasalRate == nil)
        #expect(decision.suggestedSMB == nil)
    }
    
    @Test("Enacted decision")
    func enactedDecision() {
        let enactTime = Date()
        let decision = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 0.0,
            suggestedTempBasalDuration: 1800,
            reason: "Zero temp",
            iobAtDecision: 3.0,
            cobAtDecision: 0,
            enacted: true,
            enactedAt: enactTime
        )
        
        #expect(decision.enacted == true)
        #expect(decision.enactedAt == enactTime)
        #expect(decision.failureReason == nil)
    }
    
    @Test("Failed decision")
    func failedDecision() {
        let decision = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 2.0,
            suggestedTempBasalDuration: 1800,
            reason: "Increase basal",
            iobAtDecision: 0.5,
            cobAtDecision: 50.0,
            enacted: false,
            failureReason: "Pump communication error"
        )
        
        #expect(decision.enacted == false)
        #expect(decision.failureReason == "Pump communication error")
    }
    
    @Test("Decision record is identifiable")
    func decisionRecordIdentifiable() {
        let decision1 = AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "Test 1",
            iobAtDecision: 0,
            cobAtDecision: 0
        )
        let decision2 = AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "Test 2",
            iobAtDecision: 0,
            cobAtDecision: 0
        )
        
        #expect(decision1.id != decision2.id)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 1.2,
            suggestedTempBasalDuration: 3600,
            reason: "Test reason",
            iobAtDecision: 2.5,
            cobAtDecision: 40.0,
            glucoseAtDecision: 130.0,
            enacted: true,
            enactedAt: Date()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AlgorithmDecisionRecord.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.decisionType == .tempBasal)
        #expect(decoded.suggestedTempBasalRate == 1.2)
        #expect(decoded.iobAtDecision == 2.5)
    }
}

// MARK: - Algorithm Decision Type Tests

@Suite("Algorithm Decision Type")
struct AlgorithmDecisionTypeTests {
    
    @Test("All decision types have raw values")
    func allDecisionTypesHaveRawValues() {
        for type in AlgorithmDecisionType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test("Decision types are unique")
    func decisionTypesAreUnique() {
        let rawValues = AlgorithmDecisionType.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
}

// MARK: - Loop Cycle Record Tests

@Suite("Loop Cycle Record")
struct LoopCycleRecordTests {
    
    @Test("Create successful cycle")
    func createSuccessfulCycle() {
        let cycle = LoopCycleRecord(
            duration: 2.5,
            success: true,
            cgmDataAge: 120
        )
        
        #expect(cycle.success == true)
        #expect(cycle.duration == 2.5)
        #expect(cycle.cgmDataAge == 120)
        #expect(cycle.errorMessage == nil)
    }
    
    @Test("Create failed cycle")
    func createFailedCycle() {
        let cycle = LoopCycleRecord(
            duration: 5.0,
            success: false,
            errorMessage: "CGM data too old"
        )
        
        #expect(cycle.success == false)
        #expect(cycle.errorMessage == "CGM data too old")
    }
    
    @Test("Cycle with decision reference")
    func cycleWithDecisionReference() {
        let decisionID = UUID()
        let cycle = LoopCycleRecord(
            duration: 3.0,
            success: true,
            decisionID: decisionID
        )
        
        #expect(cycle.decisionID == decisionID)
    }
    
    @Test("Cycle is identifiable")
    func cycleIdentifiable() {
        let cycle1 = LoopCycleRecord(duration: 1.0, success: true)
        let cycle2 = LoopCycleRecord(duration: 1.0, success: true)
        
        #expect(cycle1.id != cycle2.id)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = LoopCycleRecord(
            duration: 2.8,
            success: true,
            cgmDataAge: 150,
            decisionID: UUID()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LoopCycleRecord.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.duration == original.duration)
        #expect(decoded.success == original.success)
    }
}

// MARK: - In-Memory Store Tests

@Suite("In-Memory Algorithm State Store")
struct InMemoryAlgorithmStateStoreTests {
    
    @Test("Save and load state")
    func saveAndLoadState() async throws {
        let store = InMemoryAlgorithmStateStore()
        let state = PersistedAlgorithmState(iob: 2.5, cob: 30.0)
        
        try await store.saveState(state)
        let loaded = try await store.loadState()
        
        #expect(loaded != nil)
        #expect(loaded?.iob == 2.5)
        #expect(loaded?.cob == 30.0)
    }
    
    @Test("Clear state")
    func clearState() async throws {
        let store = InMemoryAlgorithmStateStore()
        let state = PersistedAlgorithmState(iob: 1.0, cob: 10.0)
        
        try await store.saveState(state)
        try await store.clearState()
        let loaded = try await store.loadState()
        
        #expect(loaded == nil)
    }
    
    @Test("Save and load decisions")
    func saveAndLoadDecisions() async throws {
        let store = InMemoryAlgorithmStateStore()
        
        let decision1 = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            reason: "Decision 1",
            iobAtDecision: 1.0,
            cobAtDecision: 0
        )
        let decision2 = AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "Decision 2",
            iobAtDecision: 0.5,
            cobAtDecision: 0
        )
        
        try await store.saveDecision(decision1)
        try await store.saveDecision(decision2)
        
        let loaded = try await store.loadDecisions(hours: 1)
        #expect(loaded.count == 2)
    }
    
    @Test("Decisions filtered by time")
    func decisionsFilteredByTime() async throws {
        let store = InMemoryAlgorithmStateStore()
        
        // Recent decision
        let recent = AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "Recent",
            iobAtDecision: 0,
            cobAtDecision: 0
        )
        try await store.saveDecision(recent)
        
        // 1 hour of decisions
        let decisions = try await store.loadDecisions(hours: 1)
        #expect(decisions.count == 1)
    }
    
    @Test("Save and load cycles")
    func saveAndLoadCycles() async throws {
        let store = InMemoryAlgorithmStateStore()
        
        let cycle1 = LoopCycleRecord(duration: 2.0, success: true)
        let cycle2 = LoopCycleRecord(duration: 3.0, success: false, errorMessage: "Error")
        
        try await store.saveCycle(cycle1)
        try await store.saveCycle(cycle2)
        
        let loaded = try await store.loadCycles(hours: 1)
        #expect(loaded.count == 2)
    }
    
    @Test("Clear history")
    func clearHistory() async throws {
        let store = InMemoryAlgorithmStateStore()
        
        // Add some data
        try await store.saveDecision(AlgorithmDecisionRecord(
            decisionType: .noAction,
            reason: "Test",
            iobAtDecision: 0,
            cobAtDecision: 0
        ))
        try await store.saveCycle(LoopCycleRecord(duration: 1.0, success: true))
        
        // Clear everything older than 0 hours (everything)
        try await store.clearHistory(olderThan: 0)
        
        let decisions = try await store.loadDecisions(hours: 1)
        let cycles = try await store.loadCycles(hours: 1)
        
        #expect(decisions.isEmpty)
        #expect(cycles.isEmpty)
    }
}

// MARK: - File Store Tests

@Suite("File Algorithm State Store")
struct FileAlgorithmStateStoreTests {
    
    @Test("Save and load state from file")
    func saveAndLoadStateFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileAlgorithmStateStore(directory: tempDir)
        let state = PersistedAlgorithmState(iob: 3.5, cob: 40.0)
        
        try await store.saveState(state)
        
        // Create new store to verify persistence
        let store2 = try FileAlgorithmStateStore(directory: tempDir)
        let loaded = try await store2.loadState()
        
        #expect(loaded != nil)
        #expect(loaded?.iob == 3.5)
        #expect(loaded?.cob == 40.0)
    }
    
    @Test("Clear state removes file")
    func clearStateRemovesFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileAlgorithmStateStore(directory: tempDir)
        let state = PersistedAlgorithmState(iob: 1.0, cob: 0)
        
        try await store.saveState(state)
        try await store.clearState()
        
        let store2 = try FileAlgorithmStateStore(directory: tempDir)
        let loaded = try await store2.loadState()
        
        #expect(loaded == nil)
    }
    
    @Test("Save and load decisions from file")
    func saveAndLoadDecisionsFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileAlgorithmStateStore(directory: tempDir)
        
        let decision = AlgorithmDecisionRecord(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 1.0,
            reason: "Test",
            iobAtDecision: 2.0,
            cobAtDecision: 0
        )
        try await store.saveDecision(decision)
        
        let store2 = try FileAlgorithmStateStore(directory: tempDir)
        let loaded = try await store2.loadDecisions(hours: 1)
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.decisionType == .tempBasal)
    }
    
    @Test("Save and load cycles from file")
    func saveAndLoadCyclesFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let store = try FileAlgorithmStateStore(directory: tempDir)
        
        let cycle = LoopCycleRecord(duration: 2.5, success: true, cgmDataAge: 60)
        try await store.saveCycle(cycle)
        
        let store2 = try FileAlgorithmStateStore(directory: tempDir)
        let loaded = try await store2.loadCycles(hours: 1)
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.duration == 2.5)
    }
}

// MARK: - Algorithm State Manager Tests

@Suite("Algorithm State Manager")
struct AlgorithmStateManagerTests {
    
    @Test("Update and get state")
    func updateAndGetState() async throws {
        let manager = AlgorithmStateManager.inMemory()
        
        try await manager.updateState(
            iob: 2.5,
            basalIOB: 1.0,
            bolusIOB: 1.5,
            cob: 30.0,
            currentGlucose: 120.0
        )
        
        let state = try await manager.getCurrentState()
        #expect(state?.iob == 2.5)
        #expect(state?.cob == 30.0)
    }
    
    @Test("Get current IOB")
    func getCurrentIOB() async {
        let manager = AlgorithmStateManager.inMemory()
        
        // No state = 0
        var iob = await manager.getCurrentIOB()
        #expect(iob == 0)
        
        // With state
        try? await manager.updateState(iob: 3.0, cob: 0)
        iob = await manager.getCurrentIOB()
        #expect(iob == 3.0)
    }
    
    @Test("Get current COB")
    func getCurrentCOB() async {
        let manager = AlgorithmStateManager.inMemory()
        
        // No state = 0
        var cob = await manager.getCurrentCOB()
        #expect(cob == 0)
        
        // With state
        try? await manager.updateState(iob: 0, cob: 45.0)
        cob = await manager.getCurrentCOB()
        #expect(cob == 45.0)
    }
    
    @Test("Loop active detection")
    func loopActiveDetection() async {
        let manager = AlgorithmStateManager.inMemory()
        
        // No state = not active
        var active = await manager.isLoopActive()
        #expect(active == false)
        
        // With active state
        try? await manager.updateState(iob: 0, cob: 0, loopActive: true)
        active = await manager.isLoopActive()
        #expect(active == true)
    }
    
    @Test("Record decision")
    func recordDecision() async throws {
        let manager = AlgorithmStateManager.inMemory()
        
        let id = try await manager.recordDecision(
            decisionType: .tempBasal,
            suggestedTempBasalRate: 1.5,
            suggestedTempBasalDuration: 1800,
            reason: "Test decision",
            iobAtDecision: 2.0,
            cobAtDecision: 20.0
        )
        
        let decisions = try await manager.getRecentDecisions(hours: 1)
        #expect(decisions.count == 1)
        #expect(decisions.first?.id == id)
    }
    
    @Test("Record cycle")
    func recordCycle() async throws {
        let manager = AlgorithmStateManager.inMemory()
        
        try await manager.recordCycle(
            duration: 2.5,
            success: true,
            cgmDataAge: 120
        )
        
        let cycles = try await manager.getRecentCycles(hours: 1)
        #expect(cycles.count == 1)
        #expect(cycles.first?.duration == 2.5)
    }
    
    @Test("Get statistics")
    func getStatistics() async throws {
        let manager = AlgorithmStateManager.inMemory()
        
        // Record some decisions
        _ = try await manager.recordDecision(
            decisionType: .tempBasal,
            reason: "Test 1",
            iobAtDecision: 1.0,
            cobAtDecision: 0
        )
        _ = try await manager.recordDecision(
            decisionType: .noAction,
            reason: "Test 2",
            iobAtDecision: 0.5,
            cobAtDecision: 0
        )
        
        // Record some cycles
        try await manager.recordCycle(duration: 2.0, success: true)
        try await manager.recordCycle(duration: 3.0, success: true)
        try await manager.recordCycle(duration: 5.0, success: false, errorMessage: "Error")
        
        let stats = try await manager.getStatistics(hours: 1)
        
        #expect(stats.totalDecisions == 2)
        #expect(stats.tempBasalDecisions == 1)
        #expect(stats.noActionDecisions == 1)
        #expect(stats.totalCycles == 3)
        #expect(stats.successfulCycles == 2)
        #expect(stats.failedCycles == 1)
    }
}

// MARK: - Algorithm Statistics Tests

@Suite("Algorithm Statistics")
struct AlgorithmStatisticsTests {
    
    @Test("Success rate calculation")
    func successRateCalculation() {
        let cycles = [
            LoopCycleRecord(duration: 1.0, success: true),
            LoopCycleRecord(duration: 1.0, success: true),
            LoopCycleRecord(duration: 1.0, success: false),
            LoopCycleRecord(duration: 1.0, success: true),
        ]
        
        let stats = AlgorithmStatistics(decisions: [], cycles: cycles)
        
        #expect(stats.successRate == 75.0)
    }
    
    @Test("Success rate with no cycles")
    func successRateWithNoCycles() {
        let stats = AlgorithmStatistics(decisions: [], cycles: [])
        #expect(stats.successRate == 0)
    }
    
    @Test("Average cycle duration")
    func averageCycleDuration() {
        let cycles = [
            LoopCycleRecord(duration: 2.0, success: true),
            LoopCycleRecord(duration: 3.0, success: true),
            LoopCycleRecord(duration: 4.0, success: true),
        ]
        
        let stats = AlgorithmStatistics(decisions: [], cycles: cycles)
        
        #expect(stats.averageCycleDuration == 3.0)
    }
    
    @Test("Enactment rate calculation")
    func enactmentRateCalculation() {
        let decisions = [
            AlgorithmDecisionRecord(
                decisionType: .tempBasal,
                reason: "1",
                iobAtDecision: 0,
                cobAtDecision: 0,
                enacted: true
            ),
            AlgorithmDecisionRecord(
                decisionType: .tempBasal,
                reason: "2",
                iobAtDecision: 0,
                cobAtDecision: 0,
                enacted: false
            ),
            AlgorithmDecisionRecord(
                decisionType: .smb,
                reason: "3",
                iobAtDecision: 0,
                cobAtDecision: 0,
                enacted: true
            ),
            AlgorithmDecisionRecord(
                decisionType: .noAction,
                reason: "4",
                iobAtDecision: 0,
                cobAtDecision: 0
            ),
        ]
        
        let stats = AlgorithmStatistics(decisions: decisions, cycles: [])
        
        // 2 enacted out of 3 enactable (tempBasal + SMB, not noAction)
        #expect(abs(stats.enactmentRate - 66.666) < 1)  // ~66.67%
    }
}

// MARK: - Algorithm State Error Tests

@Suite("Algorithm State Error")
struct AlgorithmStateErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let errors: [AlgorithmStateError] = [
            .stateNotFound,
            .invalidData,
            .stateStale(age: 900)
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("Stale error includes age")
    func staleErrorIncludesAge() {
        let error = AlgorithmStateError.stateStale(age: 900)  // 15 minutes
        let description = error.errorDescription ?? ""
        #expect(description.contains("15"))
    }
}

// MARK: - A/B Testing Types (ALG-AB-001, ALG-AB-003)

@Suite("Algorithm A/B Testing")
struct AlgorithmABTestingTests {
    
    @Test("AlgorithmDecisionRecord includes algorithm origin")
    func decisionRecordIncludesAlgorithmOrigin() {
        let record = AlgorithmDecisionRecord(
            algorithmOrigin: .oref1,
            decisionType: .tempBasal,
            reason: "Test reason",
            iobAtDecision: 2.0,
            cobAtDecision: 15.0
        )
        
        #expect(record.algorithmOrigin == .oref1)
        #expect(record.decisionType == .tempBasal)
    }
    
    @Test("AlgorithmDecisionRecord defaults to Loop origin")
    func decisionRecordDefaultsToLoop() {
        let record = AlgorithmDecisionRecord(
            decisionType: .smb,
            reason: "SMB for predicted high",
            iobAtDecision: 1.5,
            cobAtDecision: 0
        )
        
        #expect(record.algorithmOrigin == .loop)
    }
    
    @Test("AlgorithmTIRResult calculates TIR percentage")
    func tirResultCalculatesPercentage() {
        let result = AlgorithmTIRResult(
            algorithmOrigin: .oref0,
            timeInRange: 0.75,
            timeBelowRange: 0.05,
            timeAboveRange: 0.20,
            averageGlucose: 140.0,
            gmi: 6.8,
            cv: 32.0,
            decisionCount: 100,
            enactedCount: 95
        )
        
        #expect(result.tirPercentage == "75.0%")
        #expect(result.enactmentRate == 0.95)
        #expect(result.id == "OpenAPS/oref0")
    }
    
    @Test("AlgorithmTIRComparison finds best algorithm")
    func tirComparisonFindsBest() {
        let results = [
            AlgorithmTIRResult(
                algorithmOrigin: .oref0,
                timeInRange: 0.70,
                timeBelowRange: 0.05,
                timeAboveRange: 0.25,
                averageGlucose: 145.0,
                gmi: 6.9,
                cv: 35.0,
                decisionCount: 100,
                enactedCount: 90
            ),
            AlgorithmTIRResult(
                algorithmOrigin: .oref1,
                timeInRange: 0.78,
                timeBelowRange: 0.04,
                timeAboveRange: 0.18,
                averageGlucose: 135.0,
                gmi: 6.6,
                cv: 30.0,
                decisionCount: 100,
                enactedCount: 95
            )
        ]
        
        let comparison = AlgorithmTIRComparison(
            startDate: Date().addingTimeInterval(-86400 * 7),
            endDate: Date(),
            algorithmResults: results,
            totalReadings: 2016
        )
        
        #expect(comparison.bestByTIR?.algorithmOrigin == .oref1)
        #expect(comparison.result(for: .oref0)?.timeInRange == 0.70)
        #expect(comparison.totalReadings == 2016)
    }
    
    @Test("AlgorithmTIRResult handles zero decisions")
    func tirResultHandlesZeroDecisions() {
        let result = AlgorithmTIRResult(
            algorithmOrigin: .custom,
            timeInRange: 0.65,
            timeBelowRange: 0.10,
            timeAboveRange: 0.25,
            averageGlucose: 160.0,
            gmi: 7.2,
            cv: 40.0,
            decisionCount: 0,
            enactedCount: 0
        )
        
        #expect(result.enactmentRate == 0)
    }
}
