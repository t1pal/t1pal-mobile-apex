// SPDX-License-Identifier: MIT
//
// MenstrualCycleAgentTests.swift
// T1PalAlgorithmTests
//
// Tests for MenstrualCycleAgent
// Backlog: EFFECT-AGENT-004

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Menstrual Cycle Agent")
struct MenstrualCycleAgentTests {
    
    var agent: MenstrualCycleAgent {
        MenstrualCycleAgent()
    }
    
    // Helper to create AgentContext with correct parameter order
    private func makeContext(time: Date = Date()) -> AgentContext {
        AgentContext(
            currentGlucose: 120,
            glucoseTrend: 0.0,
            timeOfDay: time,
            iob: 2.0,
            cob: 0
        )
    }
    
    // MARK: - Privacy Tier Tests
    
    @Test("Privacy tier is on device only")
    func privacyTierIsOnDeviceOnly() async {
        // Most important test - privacy guarantee
        #expect(agent.privacyTier == .onDeviceOnly)
    }
    
    @Test("Effect bundle has on device only tier")
    func effectBundleHasOnDeviceOnlyTier() async {
        let testAgent = agent
        await testAgent.enable()
        await testAgent.logPeriodStart(date: Date().addingTimeInterval(-7 * 24 * 3600))  // 7 days ago
        
        let bundle = await testAgent.evaluate(context: makeContext())
        
        if let bundle = bundle {
            #expect(bundle.privacyTier == .onDeviceOnly)
            #expect(bundle.reason == nil)  // No reason to preserve privacy
        }
    }
    
    @Test("Privacy tier never syncs")
    func privacyTierNeverSyncs() {
        // Verify onDeviceOnly tier never syncs
        #expect(!PrivacyTier.onDeviceOnly.syncsEffects)
    }
    
    // MARK: - Cycle Phase Tests
    
    @Test("Cycle phase default sensitivity")
    func cyclePhaseDefaultSensitivity() {
        #expect(CyclePhase.menstrual.defaultSensitivityFactor == 1.0)
        #expect(CyclePhase.follicular.defaultSensitivityFactor == 0.9)
        #expect(CyclePhase.ovulation.defaultSensitivityFactor == 1.0)
        #expect(CyclePhase.luteal.defaultSensitivityFactor == 1.15)
    }
    
    @Test("Cycle phase day ranges")
    func cyclePhaseDayRanges() {
        #expect(CyclePhase.menstrual.typicalDayRange == 1...5)
        #expect(CyclePhase.follicular.typicalDayRange == 6...13)
        #expect(CyclePhase.ovulation.typicalDayRange == 14...16)
        #expect(CyclePhase.luteal.typicalDayRange == 17...28)
    }
    
    // MARK: - Cycle State Tests
    
    @Test("Cycle day calculation")
    func cycleDayCalculation() {
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -10, to: Date())!
        
        let state = CycleState(lastPeriodStart: periodStart)
        
        #expect(state.cycleDay() == 11)  // 10 days ago + 1 for 1-based
    }
    
    @Test("Cycle day does not go negative")
    func cycleDayDoesNotGoNegative() {
        // Future date - should return 1
        let futureDate = Date().addingTimeInterval(7 * 24 * 3600)
        let state = CycleState(lastPeriodStart: futureDate)
        
        #expect(state.cycleDay() == 1)
    }
    
    @Test("Predicted phase follicular")
    func predictedPhaseFollicular() {
        // Day 8 should be follicular
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        let state = CycleState(lastPeriodStart: periodStart)
        let phase = state.predictedPhase()
        
        #expect(phase == .follicular)
    }
    
    @Test("Predicted phase luteal")
    func predictedPhaseLuteal() {
        // Day 20 should be luteal
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -19, to: Date())!
        
        let state = CycleState(lastPeriodStart: periodStart)
        let phase = state.predictedPhase()
        
        #expect(phase == .luteal)
    }
    
    @Test("Predicted cycle length from history")
    func predictedCycleLengthFromHistory() {
        let state = CycleState(
            lastPeriodStart: Date(),
            historicalCycleLengths: [28, 30, 26]
        )
        
        #expect(state.predictedCycleLength == 28)  // Average
    }
    
    @Test("Predicted cycle length defaults to 28")
    func predictedCycleLengthDefaultsTo28() {
        let state = CycleState(lastPeriodStart: Date())
        
        #expect(state.predictedCycleLength == 28)
    }
    
    // MARK: - Agent Enable/Disable Tests
    
    @Test("Agent disabled by default")
    func agentDisabledByDefault() async {
        let enabled = await agent.checkEnabled()
        #expect(!enabled)
    }
    
    @Test("Agent can be enabled")
    func agentCanBeEnabled() async {
        let testAgent = agent
        await testAgent.enable()
        let enabled = await testAgent.checkEnabled()
        #expect(enabled)
    }
    
    @Test("Agent can be disabled")
    func agentCanBeDisabled() async {
        let testAgent = agent
        await testAgent.enable()
        await testAgent.disable()
        let enabled = await testAgent.checkEnabled()
        #expect(!enabled)
    }
    
    @Test("Disabled agent returns nil")
    func disabledAgentReturnsNil() async {
        let testAgent = agent
        // Don't enable - should return nil
        await testAgent.logPeriodStart()
        
        let bundle = await testAgent.evaluate(context: makeContext())
        #expect(bundle == nil)
    }
    
    // MARK: - Period Logging Tests
    
    @Test("Log period start")
    func logPeriodStart() async {
        let testAgent = agent
        let now = Date()
        await testAgent.logPeriodStart(date: now)
        
        let state = await testAgent.getCurrentState()
        
        #expect(state != nil)
        #expect(state?.lastPeriodStart == now)
        #expect(state?.isInPeriod ?? false)
    }
    
    @Test("Log period end")
    func logPeriodEnd() async {
        let testAgent = agent
        await testAgent.logPeriodStart()
        await testAgent.logPeriodEnd()
        
        let state = await testAgent.getCurrentState()
        
        #expect(!(state?.isInPeriod ?? true))
    }
    
    @Test("Historical cycle length tracking")
    func historicalCycleLengthTracking() async {
        let testAgent = agent
        let calendar = Calendar.current
        
        // Log first period
        let firstPeriod = calendar.date(byAdding: .day, value: -30, to: Date())!
        await testAgent.logPeriodStart(date: firstPeriod)
        
        // Log second period 28 days later
        let secondPeriod = calendar.date(byAdding: .day, value: -2, to: Date())!
        await testAgent.logPeriodStart(date: secondPeriod)
        
        let state = await testAgent.getCurrentState()
        #expect(state?.historicalCycleLengths.count == 1)
        #expect(state?.historicalCycleLengths.first == 28)
    }
    
    // MARK: - Phase Confirmation Tests
    
    @Test("Confirm phase overrides prediction")
    func confirmPhaseOverridesPrediction() async {
        let testAgent = agent
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        await testAgent.logPeriodStart(date: periodStart)
        await testAgent.confirmPhase(.luteal)  // Override to luteal
        
        let phase = await testAgent.getCurrentPhase()
        #expect(phase == .luteal)
    }
    
    // MARK: - Sensitivity Effect Tests
    
    @Test("Follicular phase increases sensitivity")
    func follicularPhaseIncreasesSensitivity() async {
        let testAgent = agent
        await testAgent.enable()
        
        // Day 8 = follicular phase
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -7, to: Date())!
        await testAgent.logPeriodStart(date: periodStart)
        await testAgent.logPeriodEnd()
        
        let bundle = await testAgent.evaluate(context: makeContext())
        
        #expect(bundle != nil)
        
        // Should have sensitivity effect < 1.0 (more sensitive)
        if let effect = bundle?.effects.first, case .sensitivity(let spec) = effect {
            #expect(spec.factor < 1.0)
        } else {
            Issue.record("Expected sensitivity effect")
        }
    }
    
    @Test("Luteal phase decreases sensitivity")
    func lutealPhaseDecreasesSensitivity() async {
        let testAgent = agent
        await testAgent.enable()
        
        // Day 20 = luteal phase
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -19, to: Date())!
        await testAgent.logPeriodStart(date: periodStart)
        await testAgent.logPeriodEnd()
        
        let bundle = await testAgent.evaluate(context: makeContext())
        
        #expect(bundle != nil)
        
        // Should have sensitivity effect > 1.0 (less sensitive)
        if let effect = bundle?.effects.first, case .sensitivity(let spec) = effect {
            #expect(spec.factor > 1.0)
        } else {
            Issue.record("Expected sensitivity effect")
        }
    }
    
    @Test("Menstrual phase no effect")
    func menstrualPhaseNoEffect() async {
        let testAgent = agent
        await testAgent.enable()
        
        // Day 3 = menstrual phase (baseline sensitivity 1.0)
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -2, to: Date())!
        await testAgent.logPeriodStart(date: periodStart)
        
        let bundle = await testAgent.evaluate(context: makeContext())
        
        // Baseline (1.0) should produce no effect
        #expect(bundle == nil)
    }
    
    // MARK: - Confidence Decay Tests
    
    @Test("Confidence decays over time")
    func confidenceDecaysOverTime() async {
        let testAgent = agent
        await testAgent.enable()
        
        // 35 days ago - well past confidence decay threshold
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -35, to: Date())!
        await testAgent.logPeriodStart(date: periodStart)
        
        let bundle = await testAgent.evaluate(context: makeContext())
        
        if let bundle = bundle {
            // Confidence should be lower than base (0.7)
            #expect(bundle.confidence < 0.7)
        }
    }
    
    @Test("Confidence has minimum floor")
    func confidenceHasMinimumFloor() async {
        let config = CycleConfiguration(
            minimumConfidence: 0.3
        )
        let customAgent = MenstrualCycleAgent(configuration: config)
        await customAgent.enable()
        
        // 60 days ago - very old
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -60, to: Date())!
        await customAgent.logPeriodStart(date: periodStart)
        
        let bundle = await customAgent.evaluate(context: makeContext())
        
        if let bundle = bundle {
            #expect(bundle.confidence >= 0.3)
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test("Cycle length bounds")
    func cycleLengthBounds() {
        // Should clamp to valid range
        let tooShort = CycleConfiguration(cycleLengthDays: 15)
        #expect(tooShort.cycleLengthDays == 21)
        
        let tooLong = CycleConfiguration(cycleLengthDays: 60)
        #expect(tooLong.cycleLengthDays == 45)
    }
    
    @Test("Sensitivity overrides")
    func sensitivityOverrides() {
        let config = CycleConfiguration(
            sensitivityOverrides: [.luteal: 1.25]
        )
        
        #expect(config.sensitivityFactor(for: .luteal) == 1.25)
        #expect(config.sensitivityFactor(for: .follicular) == 0.9)  // Default
    }
    
    @Test("Sensitivity override safety bounds")
    func sensitivityOverrideSafetyBounds() {
        // Should clamp extreme values
        let config = CycleConfiguration(
            sensitivityOverrides: [
                .luteal: 2.0,      // Too high
                .follicular: 0.2  // Too low
            ]
        )
        
        #expect(config.sensitivityFactor(for: .luteal) == 1.5)     // Clamped
        #expect(config.sensitivityFactor(for: .follicular) == 0.5) // Clamped
    }
    
    @Test("Conservative configuration")
    func conservativeConfiguration() {
        let config = CycleConfiguration.conservative
        
        #expect(config.sensitivityFactor(for: .luteal) == 1.1)
        #expect(config.sensitivityFactor(for: .follicular) == 0.95)
        #expect(config.baseConfidence == 0.5)
    }
    
    // MARK: - Data Export/Import Tests
    
    @Test("Export import backup")
    func exportImportBackup() async throws {
        let testAgent = agent
        await testAgent.logPeriodStart()
        
        let exported = await testAgent.exportForBackup()
        #expect(exported != nil)
        
        let newAgent = MenstrualCycleAgent()
        try await newAgent.importFromBackup(exported!)
        
        let state = await newAgent.getCurrentState()
        #expect(state != nil)
    }
    
    @Test("Delete all data")
    func deleteAllData() async {
        let testAgent = agent
        await testAgent.enable()
        await testAgent.logPeriodStart()
        
        await testAgent.deleteAllData()
        
        let state = await testAgent.getCurrentState()
        let enabled = await testAgent.checkEnabled()
        
        #expect(state == nil)
        #expect(!enabled)
    }
    
    // MARK: - Agent Metadata Tests
    
    @Test("Agent metadata")
    func agentMetadata() async {
        #expect(agent.agentId == "menstrualCycle")
        #expect(agent.name == "Menstrual Cycle")
        #expect(agent.description.contains("on-device only"))
    }
    
    @Test("No cycle state returns nil")
    func noCycleStateReturnsNil() async {
        let testAgent = agent
        await testAgent.enable()
        // Don't log any period
        
        let bundle = await testAgent.evaluate(context: makeContext())
        #expect(bundle == nil)
    }
}
