// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopOracleTests.swift
// T1Pal Mobile
//
// Oracle tests comparing our implementation against Loop's exact formulas
// extracted from externals/LoopWorkspace/LoopKit/LoopKit/InsulinKit/
//
// Goal: Zero divergence between our code and Loop's reference implementation
// Trace: ALG-ZERO-DIV, ALG-VAL-003

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Loop Oracle Implementation (extracted from LoopKit)

/// Oracle: Loop's ExponentialInsulinModel exactly as implemented in LoopKit
/// Source: externals/LoopWorkspace/LoopKit/LoopKit/InsulinKit/ExponentialInsulinModel.swift
private struct LoopOracleInsulinModel {
    let actionDuration: TimeInterval
    let peakActivityTime: TimeInterval
    let delay: TimeInterval
    
    // Precomputed terms (exact match to Loop)
    private let τ: Double
    private let a: Double
    private let S: Double
    
    init(actionDuration: TimeInterval, peakActivityTime: TimeInterval, delay: TimeInterval = 600) {
        self.actionDuration = actionDuration
        self.peakActivityTime = peakActivityTime
        self.delay = delay
        
        // Exact formula from Loop
        self.τ = peakActivityTime * (1 - peakActivityTime / actionDuration) / (1 - 2 * peakActivityTime / actionDuration)
        self.a = 2 * τ / actionDuration
        self.S = 1 / (1 - a + (1 + a) * exp(-actionDuration / τ))
    }
    
    /// Loop's percentEffectRemaining exactly as implemented
    func percentEffectRemaining(at time: TimeInterval) -> Double {
        let timeAfterDelay = time - delay
        switch timeAfterDelay {
        case let t where t <= 0:
            return 1
        case let t where t >= actionDuration:
            return 0
        default:
            let t = timeAfterDelay
            return 1 - S * (1 - a) *
                ((pow(t, 2) / (τ * actionDuration * (1 - a)) - t / τ - 1) * exp(-t / τ) + 1)
        }
    }
    
    var effectDuration: TimeInterval {
        return actionDuration + delay
    }
}

/// Oracle: Loop's DoseEntry.insulinOnBoard exactly as implemented
/// Source: externals/LoopWorkspace/LoopKit/LoopKit/InsulinKit/InsulinMath.swift:39-51
private struct LoopOracleDose {
    let startDate: Date
    let endDate: Date
    let netBasalUnits: Double
    
    /// Loop's continuousDeliveryInsulinOnBoard exactly as implemented
    /// Source: InsulinMath.swift:17-36
    private func continuousDeliveryInsulinOnBoard(at date: Date, model: LoopOracleInsulinModel, delta: TimeInterval) -> Double {
        let doseDuration = endDate.timeIntervalSince(startDate)  // t1
        let time = date.timeIntervalSince(startDate)
        var iob: Double = 0
        var doseDate = TimeInterval(0)  // i

        repeat {
            let segment: Double

            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }

            iob += segment * model.percentEffectRemaining(at: time - doseDate)
            doseDate += delta
        } while doseDate <= min(floor((time + model.delay) / delta) * delta, doseDuration)

        return iob
    }

    /// Loop's insulinOnBoard exactly as implemented
    /// Source: InsulinMath.swift:39-51
    func insulinOnBoard(at date: Date, model: LoopOracleInsulinModel, delta: TimeInterval) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else {
            return 0
        }

        // Consider doses within the delta time window as momentary
        if endDate.timeIntervalSince(startDate) <= 1.05 * delta {
            return netBasalUnits * model.percentEffectRemaining(at: time)
        } else {
            return netBasalUnits * continuousDeliveryInsulinOnBoard(at: date, model: model, delta: delta)
        }
    }
}

// MARK: - Test Fixtures

/// Standard insulin model parameters from Loop
/// Source: LoopKit/InsulinKit/InsulinType.swift - rapidActingAdult
private let oracleRapidActingAdult = LoopOracleInsulinModel(
    actionDuration: 21600,  // 6 hours
    peakActivityTime: 4500, // 75 minutes
    delay: 600              // 10 minutes
)

// MARK: - Oracle Tests

// MARK: - Glucose Effect Oracle (extracted from InsulinMath.swift:53-87)

extension LoopOracleDose {
    /// Loop's continuousDeliveryGlucoseEffect exactly as implemented
    /// Source: InsulinMath.swift:53-73
    private func continuousDeliveryGlucoseEffect(at date: Date, model: LoopOracleInsulinModel, delta: TimeInterval) -> Double {
        let doseDuration = endDate.timeIntervalSince(startDate)
        let time = date.timeIntervalSince(startDate)
        var value: Double = 0
        var doseDate = TimeInterval(0)
        
        repeat {
            let segment: Double
            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }
            value += segment * (1.0 - model.percentEffectRemaining(at: time - doseDate))
            doseDate += delta
        } while doseDate <= min(floor((time + model.delay) / delta) * delta, doseDuration)
        
        return value
    }
    
    /// Loop's glucoseEffect exactly as implemented
    /// Source: InsulinMath.swift:75-88
    func glucoseEffect(at date: Date, model: LoopOracleInsulinModel, insulinSensitivity: Double, delta: TimeInterval) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else { return 0 }
        
        // Consider doses within the delta time window as momentary
        if endDate.timeIntervalSince(startDate) <= 1.05 * delta {
            return netBasalUnits * -insulinSensitivity * (1.0 - model.percentEffectRemaining(at: time))
        } else {
            return netBasalUnits * -insulinSensitivity * continuousDeliveryGlucoseEffect(at: date, model: model, delta: delta)
        }
    }
}

@Suite("Loop Oracle Tests")
struct LoopOracleTests {
    
    var now: Date { Date() }
    let delta: TimeInterval = 300 // 5 minutes
    let isf: Double = 50.0 // mg/dL per unit
    
    // MARK: - Insulin Model Tests
    
    @Test("Insulin model percentEffectRemaining matches oracle exactly")
    func insulinModel_percentEffectRemaining_exactMatch() {
        // Our implementation
        let ours = LoopInsulinModelPreset.rapidActingAdult.model
        
        // Test at various time points through the insulin curve
        let testTimes: [TimeInterval] = [
            0,                    // At dose time
            300,                  // 5 min (within delay)
            600,                  // 10 min (delay complete)
            900,                  // 15 min
            1800,                 // 30 min
            2700,                 // 45 min
            3600,                 // 1 hour
            4500,                 // 75 min (peak)
            5400,                 // 90 min
            7200,                 // 2 hours
            10800,                // 3 hours
            14400,                // 4 hours
            18000,                // 5 hours
            21600,                // 6 hours
            22200,                // 6h 10min (action complete)
            25200,                // 7 hours (past effect)
        ]
        
        for time in testTimes {
            let oracleValue = oracleRapidActingAdult.percentEffectRemaining(at: time)
            let ourValue = ours.percentEffectRemaining(at: time)
            
            #expect(
                abs(ourValue - oracleValue) < 1e-15,
                "Divergence at \(time/60) min: ours=\(ourValue) oracle=\(oracleValue)"
            )
        }
    }
    
    @Test("Insulin model precomputed terms match oracle exactly")
    func insulinModel_precomputedTerms_exactMatch() {
        // Verify τ, a, S match exactly
        let ours = LoopInsulinModelPreset.rapidActingAdult.model
        
        // We can't access private fields directly, but we can verify
        // the formula outputs match exactly, which proves terms match
        
        // Sample 100 points across the curve
        for i in 0..<100 {
            let time = TimeInterval(i) * 220  // ~6 hours coverage
            let oracleValue = oracleRapidActingAdult.percentEffectRemaining(at: time)
            let ourValue = ours.percentEffectRemaining(at: time)
            
            #expect(abs(ourValue - oracleValue) < 1e-15,
                    "Point \(i) at \(time)s diverged")
        }
    }
    
    // MARK: - IOB Calculation Tests
    
    @Test("Momentary dose IOB matches oracle exactly")
    func iob_momentaryDose_exactMatch() {
        // Bolus dose (momentary - duration < 1.05 * delta)
        let oracleDose = LoopOracleDose(
            startDate: now,
            endDate: now,  // Instantaneous
            netBasalUnits: 5.0
        )
        
        let ourDose = BasalRelativeDose(
            type: .bolus,
            startDate: now,
            endDate: now,
            volume: 5.0,
            insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
        )
        
        // Test at various times
        let testTimes: [TimeInterval] = [0, 300, 600, 1800, 3600, 7200, 14400, 21600]
        
        for offset in testTimes {
            let testDate = now.addingTimeInterval(offset)
            
            let oracleIOB = oracleDose.insulinOnBoard(at: testDate, model: oracleRapidActingAdult, delta: delta)
            let ourIOB = ourDose.insulinOnBoard(at: testDate, delta: delta)
            
            #expect(
                abs(ourIOB - oracleIOB) < 1e-8,
                "IOB divergence at \(offset/60) min: ours=\(ourIOB) oracle=\(oracleIOB)"
            )
        }
    }
    
    @Test("Continuous delivery IOB matches oracle exactly")
    func iob_continuousDelivery_exactMatch() {
        // Temp basal: 2 U/hr for 30 min, scheduled 1 U/hr → net +0.5 U
        let oracleDose = LoopOracleDose(
            startDate: now,
            endDate: now.addingTimeInterval(1800),  // 30 min
            netBasalUnits: 0.5  // (2.0 - 1.0) * 0.5hr
        )
        
        let ourDose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            volume: 1.0,  // 2.0 U/hr * 0.5hr = 1.0 U delivered
            insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
        )
        
        // Test at various times through and after the delivery
        let testTimes: [TimeInterval] = [
            0,      // Start
            300,    // 5 min (during delivery)
            600,    // 10 min
            900,    // 15 min
            1500,   // 25 min
            1800,   // 30 min (end of delivery)
            2100,   // 35 min (after delivery)
            3600,   // 1 hour
            7200,   // 2 hours
            14400,  // 4 hours
            21600,  // 6 hours
        ]
        
        for offset in testTimes {
            let testDate = now.addingTimeInterval(offset)
            
            let oracleIOB = oracleDose.insulinOnBoard(at: testDate, model: oracleRapidActingAdult, delta: delta)
            let ourIOB = ourDose.insulinOnBoard(at: testDate, delta: delta)
            
            #expect(
                abs(ourIOB - oracleIOB) < 1e-8,
                "Continuous IOB divergence at \(offset/60) min: ours=\(ourIOB) oracle=\(oracleIOB)"
            )
        }
    }
    
    @Test("Negative net basal IOB matches oracle exactly")
    func iob_negativeNetBasal_exactMatch() {
        // Zero temp (suspend): 0 U/hr for 30 min, scheduled 1 U/hr → net -0.5 U
        let oracleDose = LoopOracleDose(
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            netBasalUnits: -0.5  // (0.0 - 1.0) * 0.5hr
        )
        
        let ourDose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            volume: 0.0,  // Suspend
            insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
        )
        
        for offset in [0.0, 600.0, 1800.0, 3600.0, 7200.0] {
            let testDate = now.addingTimeInterval(offset)
            
            let oracleIOB = oracleDose.insulinOnBoard(at: testDate, model: oracleRapidActingAdult, delta: delta)
            let ourIOB = ourDose.insulinOnBoard(at: testDate, delta: delta)
            
            #expect(abs(ourIOB - oracleIOB) < 1e-8,
                    "Negative IOB divergence at \(offset/60) min")
        }
    }
    
    // MARK: - Multi-Dose Aggregate Tests
    
    @Test("Multi-dose aggregate IOB matches oracle exactly")
    func iob_multiDoseAggregate_exactMatch() {
        // Realistic scenario: bolus + temp basal
        let bolus = (
            oracle: LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 3.0),
            ours: BasalRelativeDose(type: .bolus, startDate: now, endDate: now, 
                                     volume: 3.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        )
        
        // Temp basal: 2.5 U/hr for 30 min, scheduled 1.0 U/hr
        // Delivered: 2.5 * 0.5hr = 1.25 U
        // Scheduled: 1.0 * 0.5hr = 0.5 U
        // Net: 1.25 - 0.5 = 0.75 U
        let tempBasal = (
            oracle: LoopOracleDose(
                startDate: now.addingTimeInterval(-1800),  // Started 30 min ago
                endDate: now,                              // Ended now (30 min duration)
                netBasalUnits: 0.75
            ),
            ours: BasalRelativeDose(
                type: .basal(scheduledRate: 1.0),
                startDate: now.addingTimeInterval(-1800),
                endDate: now,                              // Fixed: 30 min duration
                volume: 1.25,  // 2.5 U/hr * 0.5hr = 1.25 U
                insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
            )
        )
        
        // Sum IOB at current time
        let oracleTotalIOB = bolus.oracle.insulinOnBoard(at: now, model: oracleRapidActingAdult, delta: delta)
                          + tempBasal.oracle.insulinOnBoard(at: now, model: oracleRapidActingAdult, delta: delta)
        
        let ourTotalIOB = bolus.ours.insulinOnBoard(at: now, delta: delta)
                        + tempBasal.ours.insulinOnBoard(at: now, delta: delta)
        
        #expect(abs(ourTotalIOB - oracleTotalIOB) < 1e-8,
                "Multi-dose aggregate IOB diverged")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("IOB before dose time returns zero")
    func iob_beforeDoseTime_returnsZero() {
        let oracleDose = LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 5.0)
        let ourDose = BasalRelativeDose(type: .bolus, startDate: now, endDate: now,
                                         volume: 5.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        
        let beforeDose = now.addingTimeInterval(-60)
        
        let oracleIOB = oracleDose.insulinOnBoard(at: beforeDose, model: oracleRapidActingAdult, delta: delta)
        let ourIOB = ourDose.insulinOnBoard(at: beforeDose, delta: delta)
        
        #expect(oracleIOB == 0.0)
        #expect(ourIOB == 0.0)
    }
    
    @Test("IOB at exactly dose time returns full IOB")
    func iob_atExactlyDoseTime_fullIOB() {
        let oracleDose = LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 5.0)
        let ourDose = BasalRelativeDose(type: .bolus, startDate: now, endDate: now,
                                         volume: 5.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        
        let oracleIOB = oracleDose.insulinOnBoard(at: now, model: oracleRapidActingAdult, delta: delta)
        let ourIOB = ourDose.insulinOnBoard(at: now, delta: delta)
        
        // At t=0, percentEffectRemaining = 1.0, so IOB = netBasalUnits
        #expect(abs(oracleIOB - 5.0) < 1e-15)
        #expect(abs(ourIOB - 5.0) < 1e-15)
    }
    
    @Test("IOB way past action duration returns zero")
    func iob_wayPastActionDuration_zeroIOB() {
        let oracleDose = LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 5.0)
        let ourDose = BasalRelativeDose(type: .bolus, startDate: now, endDate: now,
                                         volume: 5.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        
        let wayPast = now.addingTimeInterval(10 * 3600)  // 10 hours later
        
        let oracleIOB = oracleDose.insulinOnBoard(at: wayPast, model: oracleRapidActingAdult, delta: delta)
        let ourIOB = ourDose.insulinOnBoard(at: wayPast, delta: delta)
        
        #expect(oracleIOB == 0.0)
        #expect(ourIOB == 0.0)
    }
    
    // MARK: - Glucose Effect Oracle Tests
    
    @Test("Momentary dose glucose effect matches oracle exactly")
    func glucoseEffect_momentaryDose_exactMatch() {
        // Bolus: 2 U with ISF 50 → eventual effect = -100 mg/dL
        let oracleDose = LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 2.0)
        let ourDose = BasalRelativeDose(type: .bolus, startDate: now, endDate: now,
                                         volume: 2.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        
        let testTimes: [TimeInterval] = [0, 600, 1800, 3600, 7200, 14400, 21600, 25200]
        
        for offset in testTimes {
            let testDate = now.addingTimeInterval(offset)
            
            let oracleEffect = oracleDose.glucoseEffect(at: testDate, model: oracleRapidActingAdult, 
                                                        insulinSensitivity: isf, delta: delta)
            let ourEffect = ourDose.glucoseEffect(at: testDate, insulinSensitivity: isf, delta: delta)
            
            #expect(
                abs(ourEffect - oracleEffect) < 1e-8,
                "Glucose effect divergence at \(offset/60) min: ours=\(ourEffect) oracle=\(oracleEffect)"
            )
        }
    }
    
    @Test("Continuous delivery glucose effect matches oracle exactly")
    func glucoseEffect_continuousDelivery_exactMatch() {
        // Temp basal: net +0.5 U over 30 min
        let oracleDose = LoopOracleDose(
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            netBasalUnits: 0.5
        )
        
        let ourDose = BasalRelativeDose(
            type: .basal(scheduledRate: 1.0),
            startDate: now,
            endDate: now.addingTimeInterval(1800),
            volume: 1.0,  // 2.0 U/hr * 0.5hr = 1.0 U
            insulinModel: LoopInsulinModelPreset.rapidActingAdult.model
        )
        
        let testTimes: [TimeInterval] = [0, 600, 1800, 3600, 7200, 14400, 21600]
        
        for offset in testTimes {
            let testDate = now.addingTimeInterval(offset)
            
            let oracleEffect = oracleDose.glucoseEffect(at: testDate, model: oracleRapidActingAdult,
                                                        insulinSensitivity: isf, delta: delta)
            let ourEffect = ourDose.glucoseEffect(at: testDate, insulinSensitivity: isf, delta: delta)
            
            #expect(
                abs(ourEffect - oracleEffect) < 1e-8,
                "Continuous glucose effect divergence at \(offset/60) min"
            )
        }
    }
    
    @Test("Glucose effect eventual value matches expected")
    func glucoseEffect_eventualValue_matchesExpected() {
        // After all insulin absorbed (10+ hours), glucose effect should equal -netBasalUnits * ISF
        let oracleDose = LoopOracleDose(startDate: now, endDate: now, netBasalUnits: 2.0)
        let ourDose = BasalRelativeDose(type: .bolus, startDate: now, endDate: now,
                                         volume: 2.0, insulinModel: LoopInsulinModelPreset.rapidActingAdult.model)
        
        let wayPast = now.addingTimeInterval(10 * 3600)
        
        let oracleEffect = oracleDose.glucoseEffect(at: wayPast, model: oracleRapidActingAdult,
                                                    insulinSensitivity: isf, delta: delta)
        let ourEffect = ourDose.glucoseEffect(at: wayPast, insulinSensitivity: isf, delta: delta)
        
        // Expected: -2.0 * 50 = -100 mg/dL
        #expect(abs(oracleEffect - (-100.0)) < 1e-8)
        #expect(abs(ourEffect - (-100.0)) < 1e-8)
        #expect(abs(ourEffect - oracleEffect) < 1e-8)
    }
}

// MARK: - Oracle Bridge for Scenario Fixtures (oracle-bridge task)

/// Tests that verify our IOB calculation matches the Loop oracle when given
/// the same dose inputs. This isolates algorithm correctness from input
/// reconstruction issues.
///
/// Key insight: If our algorithm matches oracle exactly but still diverges
/// from Loop's reported IOB, the problem is in input reconstruction (dose
/// history assembly), not the IOB formula itself.
@Suite("Oracle Bridge Tests")
struct OracleBridgeTests {
    
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/algorithm-replays")
    }
    
    /// Oracle comparison: Given the SAME dose inputs, verify our IOB calculation
    /// matches the oracle exactly. This isolates algorithm correctness from
    /// input reconstruction issues.
    @Test("Oracle IOB with fixture doses matches exactly")
    func oracleIOBWithFixtureDoses() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return  // Skip if fixture not found
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let treatments = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        // Get temp basals from treatments
        let tempBasals = treatments.filter { $0.eventType == "Temp Basal" }
        guard !tempBasals.isEmpty else {
            return  // XCTSkip("No temp basals in fixture")
        }
        
        // Our model (uses same parameters as oracle)
        let ourModel = LoopInsulinModelPreset.rapidActingAdult.model
        
        // Build dose list from first 10 temp basals
        let testBasals = Array(tempBasals.prefix(10))
        let referenceTime = testBasals.first!.timestamp
        
        var oracleTotalIOB = 0.0
        var ourTotalIOB = 0.0
        
        for (i, basal) in testBasals.enumerated() {
            guard let rate = basal.rate ?? basal.absolute else { continue }
            let duration = (basal.duration ?? 30) * 60  // Convert to seconds
            let scheduledRate = 1.7  // From fixture profile
            
            let netUnits = (rate - scheduledRate) * (duration / 3600)
            let startDate = basal.timestamp
            let endDate = startDate.addingTimeInterval(duration)
            
            let oracleDose = LoopOracleDose(
                startDate: startDate,
                endDate: endDate,
                netBasalUnits: netUnits
            )
            
            let ourDose = BasalRelativeDose(
                type: .basal(scheduledRate: scheduledRate),
                startDate: startDate,
                endDate: endDate,
                volume: rate * (duration / 3600),
                insulinModel: ourModel
            )
            
            let oracleIOB = oracleDose.insulinOnBoard(at: referenceTime, model: oracleRapidActingAdult, delta: 300)
            let ourIOB = ourDose.insulinOnBoard(at: referenceTime, delta: 300)
            
            if i < 3 {
                print("Dose \(i): rate=\(rate), net=\(String(format: "%.3f", netUnits))U, " +
                      "oracleIOB=\(String(format: "%.4f", oracleIOB)), ourIOB=\(String(format: "%.4f", ourIOB))")
            }
            
            oracleTotalIOB += oracleIOB
            ourTotalIOB += ourIOB
        }
        
        print("\nTotal: oracleIOB=\(String(format: "%.4f", oracleTotalIOB)), ourIOB=\(String(format: "%.4f", ourTotalIOB))")
        
        // Verify our algorithm matches oracle when given same inputs
        let divergence = abs(ourTotalIOB - oracleTotalIOB)
        #expect(divergence < 0.001, "IOB divergence with same inputs should be < 0.001 U")
    }
    
    /// Diagnose: Compare Loop's reported IOB vs oracle-calculated IOB from fixture doses.
    /// This identifies whether divergence is in input reconstruction or algorithm.
    @Test("Diagnose scenario IOB divergence")
    func diagnoseScenarioIOBDivergence() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return  // Skip if fixture not found
        }
        
        try runDiagnostic(url: url)
    }
    
    /// Test scenario-meal-active which has a bolus
    @Test("Diagnose meal active with bolus")
    func diagnoseMealActiveWithBolus() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-meal-active.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return  // Skip if fixture not found
        }
        
        try runDiagnostic(url: url)
    }
    
    /// Helper to get scheduled basal rate at a specific time
    private func scheduledBasalRate(for date: Date, schedule: [BasalScheduleEntry]) -> Double {
        // Convert date to seconds since midnight
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let secondsSinceMidnight = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        
        // Find applicable rate (schedule is sorted by startTime)
        var rate = schedule.first?.rate ?? 1.0
        for entry in schedule {
            if entry.startTime <= secondsSinceMidnight {
                rate = entry.rate
            } else {
                break
            }
        }
        return rate
    }
    
    private func runDiagnostic(url: URL) throws {
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let deviceStatuses = NSScenarioFixtureLoader.toDeviceStatusRecords(scenario)
        let treatments = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        // Get basal schedule from profile
        let profile = NSScenarioFixtureLoader.toProfileData(scenario)
        let basalSchedule = profile?.basalSchedule ?? [BasalScheduleEntry(startTime: 0, rate: 1.7)]
        
        guard let firstStatus = deviceStatuses.first else {
            return  // XCTSkip("No device status in fixture")
        }
        
        let loopReportedIOB = firstStatus.loop.iob.iob
        
        // Build oracle IOB from ALL treatments before this deviceStatus
        let visibleTreatments = treatments.filter { $0.timestamp <= firstStatus.createdAt }
        let tempBasals = visibleTreatments.filter { $0.eventType == "Temp Basal" }
        let boluses = visibleTreatments.filter { 
            $0.eventType == "Correction Bolus" || $0.eventType == "Bolus" || $0.eventType == "SMB"
        }
        
        var oracleTempBasalIOB = 0.0
        var oracleBolusIOB = 0.0
        
        // Calculate temp basal IOB using time-varying scheduled rate
        for basal in tempBasals {
            guard let rate = basal.rate ?? basal.absolute else { continue }
            let duration = (basal.duration ?? 30) * 60
            
            // ALG-INPUT-002: Use time-varying scheduled basal rate
            let scheduledRate = scheduledBasalRate(for: basal.timestamp, schedule: basalSchedule)
            let netUnits = (rate - scheduledRate) * (duration / 3600)
            
            let oracleDose = LoopOracleDose(
                startDate: basal.timestamp,
                endDate: basal.timestamp.addingTimeInterval(duration),
                netBasalUnits: netUnits
            )
            
            oracleTempBasalIOB += oracleDose.insulinOnBoard(at: firstStatus.createdAt, model: oracleRapidActingAdult, delta: 300)
        }
        
        // Calculate bolus IOB (bolus = momentary dose, so netBasalUnits = insulin)
        for bolus in boluses {
            guard let insulin = bolus.insulin, insulin > 0 else { continue }
            
            let oracleDose = LoopOracleDose(
                startDate: bolus.timestamp,
                endDate: bolus.timestamp,  // Momentary
                netBasalUnits: insulin
            )
            
            oracleBolusIOB += oracleDose.insulinOnBoard(at: firstStatus.createdAt, model: oracleRapidActingAdult, delta: 300)
        }
        
        let oracleTotalIOB = oracleTempBasalIOB + oracleBolusIOB
        
        print("\n=== IOB Divergence Diagnosis: \(url.lastPathComponent) ===")
        print("Basal schedule: \(basalSchedule.map { "\($0.startTime/3600)h: \($0.rate)U/hr" }.joined(separator: ", "))")
        print("Loop reported IOB: \(String(format: "%.3f", loopReportedIOB)) U")
        print("Oracle temp basal IOB: \(String(format: "%.3f", oracleTempBasalIOB)) U (\(tempBasals.count) basals)")
        print("Oracle bolus IOB: \(String(format: "%.3f", oracleBolusIOB)) U (\(boluses.count) boluses)")
        print("Oracle total IOB: \(String(format: "%.3f", oracleTotalIOB)) U")
        print("Divergence: \(String(format: "%.3f", abs(loopReportedIOB - oracleTotalIOB))) U")
        
        // Analysis
        let divergence = abs(loopReportedIOB - oracleTotalIOB)
        if divergence > 0.5 {
            print("⚠️ Large divergence suggests missing data in NS fixture (Loop had more treatments)")
        } else if divergence > 0.1 {
            print("⚠️ Moderate divergence - may be timing or dose boundary issues")
        } else {
            print("✅ Oracle closely matches Loop - focus on our implementation")
        }
        
        // Pass regardless - this is diagnostic
    }
    
    /// Test our replay engine IOB vs Loop reported IOB with detailed diagnostics
    @Test("Replay engine vs Loop reported IOB")
    func replayEngineVsLoopReported() throws {
        let url = fixturesRoot.appendingPathComponent("scenario-stable.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return  // Skip if fixture not found
        }
        
        let scenario = try NSScenarioFixtureLoader.load(from: url)
        let deviceStatuses = NSScenarioFixtureLoader.toDeviceStatusRecords(scenario)
        let treatments = NSScenarioFixtureLoader.toTreatmentRecords(scenario)
        
        // IOB-FIX-005: Extract profile from fixture (use actual basal schedule, not defaults)
        let profile = NSScenarioFixtureLoader.toProfileData(scenario) ?? NightscoutProfileData(
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.5)],
            isfSchedule: [ScheduleValue(startTime: 0, value: 40)],
            crSchedule: [ScheduleValue(startTime: 0, value: 10)],
            targetLow: 100,
            targetHigh: 110,
            dia: 6 * 3600
        )
        
        let settings = NSScenarioFixtureLoader.toSettings(scenario) ?? TherapySettingsSnapshot(
            suspendThreshold: 70,
            maxBasalRate: 4.0,
            insulinSensitivity: 40,
            carbRatio: 10,
            targetLow: 100,
            targetHigh: 110,
            basalSchedule: [BasalScheduleEntry(startTime: 0, rate: 1.5)],
            insulinModel: .rapidActingAdult,
            dia: 6 * 3600
        )
        
        // Create replay engine
        let engine = LoopReplayEngine(
            deviceStatuses: deviceStatuses,
            treatments: treatments,
            glucose: [],
            profile: profile,
            settings: settings
        )
        
        // Run replay
        let results = engine.replay()
        
        print("\n=== Replay Engine vs Loop (scenario-stable) ===")
        print("Basal schedule: \(profile.basalSchedule.map { "\($0.startTime/3600)h: \($0.rate)U/hr" }.joined(separator: ", "))")
        
        var passCount = 0
        for (i, result) in results.prefix(10).enumerated() {
            let loopIOB = result.cycle.loopReportedIOB
            let ourIOB = result.ourIOB
            let divergence = ourIOB - loopIOB
            let pass = abs(divergence) <= 0.1
            if pass { passCount += 1 }
            
            print("Cycle \(i): Loop=\(String(format: "%.3f", loopIOB)), Ours=\(String(format: "%.3f", ourIOB)), Δ=\(String(format: "%+.3f", divergence)) \(pass ? "✅" : "❌")")
        }
        
        print("Pass rate (first 10): \(passCount)/10")
        print("")
        
        // Extra diagnostics: show dose list for cycle 0
        if let cycle0 = results.first {
            print("Cycle 0 dose details:")
            print("  calculationTime: \(cycle0.iobInput.calculationTime)")
            print("  includingPending: \(cycle0.iobInput.includingPendingInsulin)")
            print("  doses: \(cycle0.iobInput.doses.count)")
            
            // Compare against NS treatments visible to this cycle
            let loopTime = cycle0.cycle.cgmReadingTime
            let visibleTreatments = treatments.filter { $0.timestamp <= loopTime && $0.eventType == "Temp Basal" }
            print("  NS temp basals visible: \(visibleTreatments.count)")
            
            // Print IOB details
            print("  Loop reported IOB: \(cycle0.cycle.loopReportedIOB)")
            print("  Our IOB: \(cycle0.ourIOB)")
        }
    }
}
