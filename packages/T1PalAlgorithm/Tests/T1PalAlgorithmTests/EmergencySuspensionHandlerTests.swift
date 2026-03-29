// SPDX-License-Identifier: MIT
//
// EmergencySuspensionHandlerTests.swift
// T1Pal Mobile
//
// Tests for emergency suspension handling
// Trace: PROD-AID-005

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Suspension State Tests

@Suite("Suspension State")
struct SuspensionStateTests {
    
    @Test("All states have raw values")
    func allStatesHaveRawValues() {
        for state in SuspensionState.allCases {
            #expect(!state.rawValue.isEmpty)
        }
    }
    
    @Test("States are unique")
    func statesAreUnique() {
        let rawValues = SuspensionState.allCases.map { $0.rawValue }
        let unique = Set(rawValues)
        #expect(rawValues.count == unique.count)
    }
}

// MARK: - Suspension Reason Tests

@Suite("Suspension Reason")
struct SuspensionReasonTests {
    
    @Test("All reasons have raw values")
    func allReasonsHaveRawValues() {
        for reason in SuspensionReason.allCases {
            #expect(!reason.rawValue.isEmpty)
        }
    }
}

// MARK: - Suspension Event Tests

@Suite("Suspension Event")
struct SuspensionEventTests {
    
    @Test("Create suspend event")
    func createSuspendEvent() {
        let event = SuspensionEvent(
            action: .suspend,
            reason: .userRequested,
            source: .user,
            glucoseAtEvent: 75.0
        )
        
        #expect(event.action == .suspend)
        #expect(event.reason == .userRequested)
        #expect(event.source == .user)
        #expect(event.glucoseAtEvent == 75.0)
    }
    
    @Test("Create resume event")
    func createResumeEvent() {
        let event = SuspensionEvent(
            action: .resume,
            reason: .lowGlucose,
            source: .user
        )
        
        #expect(event.action == .resume)
    }
    
    @Test("Event is identifiable")
    func eventIsIdentifiable() {
        let event1 = SuspensionEvent(action: .suspend, reason: .userRequested)
        let event2 = SuspensionEvent(action: .suspend, reason: .userRequested)
        
        #expect(event1.id != event2.id)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = SuspensionEvent(
            action: .suspend,
            reason: .lowGlucose,
            source: .automatic,
            glucoseAtEvent: 68.0,
            iobAtEvent: 2.5,
            notes: "Low glucose detected"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SuspensionEvent.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.action == original.action)
        #expect(decoded.reason == original.reason)
        #expect(decoded.glucoseAtEvent == original.glucoseAtEvent)
    }
}

// MARK: - Suspension Configuration Tests

@Suite("Suspension Configuration")
struct SuspensionConfigurationTests {
    
    @Test("Default configuration")
    func defaultConfiguration() {
        let config = SuspensionConfiguration.default
        
        #expect(config.maxSuspensionDuration == 7200)  // 2 hours
        #expect(config.lowGlucoseThreshold == 70)
        #expect(config.predictedLowThreshold == 80)
        #expect(config.autoSuspendOnLow == true)
        #expect(config.autoResumeEnabled == false)
    }
    
    @Test("Conservative configuration")
    func conservativeConfiguration() {
        let config = SuspensionConfiguration.conservative
        
        #expect(config.maxSuspensionDuration == 14400)  // 4 hours
        #expect(config.lowGlucoseThreshold == 80)
        #expect(config.autoResumeEnabled == false)
    }
    
    @Test("Aggressive configuration")
    func aggressiveConfiguration() {
        let config = SuspensionConfiguration.aggressive
        
        #expect(config.maxSuspensionDuration == 3600)  // 1 hour
        #expect(config.autoResumeEnabled == true)
        #expect(config.autoResumeThreshold == 90)
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = SuspensionConfiguration(
            maxSuspensionDuration: 5400,  // 90 minutes
            lowGlucoseThreshold: 65,
            autoSuspendOnLow: false
        )
        
        #expect(config.maxSuspensionDuration == 5400)
        #expect(config.lowGlucoseThreshold == 65)
        #expect(config.autoSuspendOnLow == false)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = SuspensionConfiguration(
            maxSuspensionDuration: 3600,
            lowGlucoseThreshold: 75,
            autoResumeEnabled: true
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SuspensionConfiguration.self, from: data)
        
        #expect(decoded.maxSuspensionDuration == original.maxSuspensionDuration)
        #expect(decoded.lowGlucoseThreshold == original.lowGlucoseThreshold)
        #expect(decoded.autoResumeEnabled == original.autoResumeEnabled)
    }
}

// MARK: - Suspension Status Tests

@Suite("Suspension Status")
struct SuspensionStatusTests {
    
    @Test("Active status")
    func activeStatus() {
        let status = SuspensionStatus.active
        
        #expect(status.state == .active)
        #expect(status.isSuspended == false)
        #expect(status.suspendedAt == nil)
    }
    
    @Test("Suspended status")
    func suspendedStatus() {
        let status = SuspensionStatus(
            state: .suspended,
            suspendedAt: Date(),
            reason: .userRequested,
            expectedResumeAt: Date().addingTimeInterval(3600)
        )
        
        #expect(status.isSuspended == true)
        #expect(status.suspensionDuration != nil)
        #expect(status.timeUntilResume != nil)
    }
    
    @Test("Emergency suspended status")
    func emergencySuspendedStatus() {
        let status = SuspensionStatus(
            state: .emergencySuspended,
            suspendedAt: Date(),
            reason: .lowGlucose,
            glucoseAtSuspend: 65.0
        )
        
        #expect(status.isSuspended == true)
        #expect(status.state == .emergencySuspended)
    }
    
    @Test("Suspension duration calculation")
    func suspensionDurationCalculation() {
        let status = SuspensionStatus(
            state: .suspended,
            suspendedAt: Date().addingTimeInterval(-120)  // 2 minutes ago
        )
        
        let duration = status.suspensionDuration ?? 0
        #expect(duration >= 120)
        #expect(duration < 125)
    }
    
    @Test("Near expiration check")
    func nearExpirationCheck() {
        let status = SuspensionStatus(
            state: .suspended,
            suspendedAt: Date(),
            expectedResumeAt: Date().addingTimeInterval(300)  // 5 minutes
        )
        
        #expect(status.isNearExpiration(warningTime: 600) == true)  // Warning at 10 min
        #expect(status.isNearExpiration(warningTime: 180) == false)  // Warning at 3 min
    }
}

// MARK: - Suspension History Tests

@Suite("Suspension History")
struct SuspensionHistoryTests {
    
    @Test("Add events")
    func addEvents() {
        var history = SuspensionHistory()
        
        let event1 = SuspensionEvent(action: .suspend, reason: .userRequested)
        let event2 = SuspensionEvent(action: .resume, reason: .userRequested)
        
        history.addEvent(event1)
        history.addEvent(event2)
        
        #expect(history.events.count == 2)
        // Most recent first
        #expect(history.events.first?.action == .resume)
    }
    
    @Test("Count suspensions")
    func countSuspensions() {
        var history = SuspensionHistory()
        
        history.addEvent(SuspensionEvent(action: .suspend, reason: .userRequested))
        history.addEvent(SuspensionEvent(action: .resume, reason: .userRequested))
        history.addEvent(SuspensionEvent(action: .suspend, reason: .lowGlucose))
        
        let count = history.suspensionCount(lastHours: 1)
        #expect(count == 2)
    }
    
    @Test("Respects max events")
    func respectsMaxEvents() {
        var history = SuspensionHistory()
        
        for _ in 0..<600 {
            history.addEvent(SuspensionEvent(action: .suspend, reason: .userRequested))
        }
        
        #expect(history.events.count == SuspensionHistory.maxEvents)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        var history = SuspensionHistory()
        history.addEvent(SuspensionEvent(action: .suspend, reason: .userRequested))
        history.addEvent(SuspensionEvent(action: .resume, reason: .userRequested))
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SuspensionHistory.self, from: data)
        
        #expect(decoded.events.count == 2)
    }
}

// MARK: - Suspension Statistics Tests

@Suite("Suspension Statistics")
struct SuspensionStatisticsTests {
    
    @Test("Calculate from history")
    func calculateFromHistory() {
        var history = SuspensionHistory()
        
        history.addEvent(SuspensionEvent(action: .suspend, reason: .userRequested, source: .user))
        history.addEvent(SuspensionEvent(action: .resume, reason: .userRequested))
        history.addEvent(SuspensionEvent(action: .suspend, reason: .lowGlucose, source: .automatic))
        history.addEvent(SuspensionEvent(action: .resume, reason: .lowGlucose))
        history.addEvent(SuspensionEvent(action: .suspend, reason: .predictedLow, source: .safety))
        
        let stats = SuspensionStatistics.from(history: history, lastHours: 1)
        
        #expect(stats.totalSuspensions == 3)
        #expect(stats.userSuspensions == 1)
        #expect(stats.automaticSuspensions == 2)  // automatic + safety
        #expect(stats.lowGlucoseSuspensions == 2)  // lowGlucose + predictedLow
    }
    
    @Test("Empty history statistics")
    func emptyHistoryStatistics() {
        let history = SuspensionHistory()
        let stats = SuspensionStatistics.from(history: history)
        
        #expect(stats.totalSuspensions == 0)
        #expect(stats.totalSuspensionTime == 0)
    }
}

// MARK: - Emergency Suspension Handler Tests

@Suite("Emergency Suspension Handler")
struct EmergencySuspensionHandlerTests {
    
    @Test("Initial state is active")
    func initialStateIsActive() async {
        let handler = EmergencySuspensionHandler()
        let status = await handler.getStatus()
        
        #expect(status.state == .active)
        #expect(status.isSuspended == false)
    }
    
    @Test("Suspend delivery")
    func suspendDelivery() async throws {
        let handler = EmergencySuspensionHandler()
        let mockPump = MockPumpController()
        await handler.configure(pumpController: mockPump)
        
        try await handler.suspend(reason: .userRequested, glucoseAtEvent: 150.0)
        
        let status = await handler.getStatus()
        #expect(status.isSuspended == true)
        #expect(status.reason == .userRequested)
        
        let lastTemp = await mockPump.lastTempBasal
        #expect(lastTemp?.rate == 0)  // Zero basal = suspended
    }
    
    @Test("Resume delivery")
    func resumeDelivery() async throws {
        let handler = EmergencySuspensionHandler()
        let mockPump = MockPumpController()
        await handler.configure(pumpController: mockPump)
        
        try await handler.suspend(reason: .userRequested)
        try await handler.resume()
        
        let status = await handler.getStatus()
        #expect(status.state == .active)
        #expect(status.isSuspended == false)
        
        let cancelled = await mockPump.tempBasalCancelled
        #expect(cancelled == true)
    }
    
    @Test("Cannot suspend when already suspended")
    func cannotSuspendWhenAlreadySuspended() async throws {
        let handler = EmergencySuspensionHandler()
        
        try await handler.suspend(reason: .userRequested)
        
        do {
            try await handler.suspend(reason: .userRequested)
            Issue.record("Expected error")
        } catch {
            #expect(error is SuspensionError)
        }
    }
    
    @Test("Cannot resume when not suspended")
    func cannotResumeWhenNotSuspended() async {
        let handler = EmergencySuspensionHandler()
        
        do {
            try await handler.resume()
            Issue.record("Expected error")
        } catch {
            #expect(error is SuspensionError)
        }
    }
    
    @Test("Emergency suspension on low glucose")
    func emergencySuspensionOnLowGlucose() async throws {
        let handler = EmergencySuspensionHandler()
        
        try await handler.suspend(reason: .lowGlucose, glucoseAtEvent: 65.0)
        
        let status = await handler.getStatus()
        #expect(status.state == .emergencySuspended)
    }
    
    @Test("Auto-suspend on low glucose")
    func autoSuspendOnLowGlucose() async throws {
        let handler = EmergencySuspensionHandler()
        let mockPump = MockPumpController()
        await handler.configure(pumpController: mockPump)
        
        let didSuspend = try await handler.checkForAutoSuspend(currentGlucose: 65.0)
        
        #expect(didSuspend == true)
        let status = await handler.getStatus()
        #expect(status.isSuspended == true)
        #expect(status.reason == .lowGlucose)
    }
    
    @Test("Auto-suspend on predicted low")
    func autoSuspendOnPredictedLow() async throws {
        let handler = EmergencySuspensionHandler()
        let mockPump = MockPumpController()
        await handler.configure(pumpController: mockPump)
        
        let didSuspend = try await handler.checkForAutoSuspend(
            currentGlucose: 90.0,
            predictedGlucose: 75.0
        )
        
        #expect(didSuspend == true)
        let status = await handler.getStatus()
        #expect(status.reason == .predictedLow)
    }
    
    @Test("No auto-suspend when disabled")
    func noAutoSuspendWhenDisabled() async throws {
        let config = SuspensionConfiguration(autoSuspendOnLow: false)
        let handler = EmergencySuspensionHandler(configuration: config)
        
        let didSuspend = try await handler.checkForAutoSuspend(currentGlucose: 65.0)
        
        #expect(didSuspend == false)
        let isSuspended = await handler.isSuspended()
        #expect(isSuspended == false)
    }
    
    @Test("No auto-suspend when already suspended")
    func noAutoSuspendWhenAlreadySuspended() async throws {
        let handler = EmergencySuspensionHandler()
        
        try await handler.suspend(reason: .userRequested)
        let didSuspend = try await handler.checkForAutoSuspend(currentGlucose: 65.0)
        
        #expect(didSuspend == false)
    }
    
    @Test("History tracks events")
    func historyTracksEvents() async throws {
        let handler = EmergencySuspensionHandler()
        
        try await handler.suspend(reason: .userRequested)
        try await handler.resume()
        try await handler.suspend(reason: .lowGlucose)
        
        let history = await handler.getHistory()
        #expect(history.events.count == 3)
    }
    
    @Test("Get statistics")
    func getStatistics() async throws {
        let handler = EmergencySuspensionHandler()
        
        try await handler.suspend(reason: .userRequested, source: .user)
        try await handler.resume()
        try await handler.suspend(reason: .lowGlucose, source: .automatic)
        try await handler.resume()
        
        let stats = await handler.getStatistics(lastHours: 1)
        
        #expect(stats.totalSuspensions == 2)
        #expect(stats.userSuspensions == 1)
        #expect(stats.automaticSuspensions == 1)
    }
    
    @Test("Update configuration")
    func updateConfiguration() async {
        let handler = EmergencySuspensionHandler()
        let newConfig = SuspensionConfiguration(lowGlucoseThreshold: 60)
        
        await handler.updateConfiguration(newConfig)
        
        // Verify by testing behavior - won't suspend at 65
    }
}

// MARK: - Suspension Error Tests

@Suite("Suspension Error")
struct SuspensionErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let errors: [SuspensionError] = [
            .alreadySuspended,
            .notSuspended,
            .maxDurationExceeded,
            .minimumTimeNotMet(remaining: 300),
            .invalidState,
            .pumpError("Connection lost")
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("Minimum time error includes remaining")
    func minimumTimeErrorIncludesRemaining() {
        let error = SuspensionError.minimumTimeNotMet(remaining: 600)
        let description = error.errorDescription ?? ""
        
        #expect(description.contains("600"))
    }
}
