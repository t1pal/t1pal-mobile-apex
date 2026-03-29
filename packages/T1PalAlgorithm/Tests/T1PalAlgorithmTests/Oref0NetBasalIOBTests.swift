// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Oref0NetBasalIOBTests.swift
// T1Pal Mobile
//
// Tests for oref0 NetBasalIOBProvider implementation
// Trace: ALG-NET-002

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Oref0 Net Basal IOB")
struct Oref0NetBasalIOBTests {
    
    // MARK: - Test Fixtures
    
    private var now: Date { Date() }
    
    /// Create a simple basal schedule: 1.0 U/hr all day
    private func flatBasalSchedule(at date: Date) -> [AbsoluteScheduleValue<Double>] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return [AbsoluteScheduleValue(startDate: start, endDate: end, value: 1.0)]
    }
    
    /// Create a bolus dose
    private func bolus(units: Double, at date: Date) -> InsulinDose {
        InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "bolus"
        )
    }
    
    /// Create a temp basal dose (5-minute segment)
    private func tempBasal(rate: Double, at date: Date) -> InsulinDose {
        let units = rate * (5.0 / 60.0)
        return InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "temp_basal"
        )
    }
    
    // MARK: - Protocol Conformance Tests
    
    @Test("Oref0 calculator conforms to protocol")
    func oref0CalculatorConformsToProtocol() {
        let calculator = Oref0NetBasalIOBCalculator()
        let _: NetBasalIOBProvider = calculator
    }
    
    // MARK: - Bolus IOB Tests
    
    @Test("Bolus IOB at time zero")
    func bolusIOBAtTimeZero() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // At time 0, full IOB expected
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Bolus IOB decays over time")
    func bolusIOBDecaysOverTime() {
        let calculator = Oref0NetBasalIOBCalculator()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Some decay expected at 1 hour
        #expect(iob < 5.0)
        #expect(iob > 2.0)
    }
    
    @Test("Bolus IOB near zero at DIA")
    func bolusIOBNearZeroAtDIA() {
        let calculator = Oref0NetBasalIOBCalculator(insulinType: .novolog)
        // Novolog DIA is 6 hours
        let sixHoursAgo = now.addingTimeInterval(-6 * 3600)
        let doses = [bolus(units: 5.0, at: sixHoursAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // IOB should be near zero at DIA
        #expect(iob < 0.1)
    }
    
    // MARK: - Net Basal IOB Tests
    
    @Test("Temp basal at scheduled rate has zero net IOB")
    func tempBasalAtScheduledRateHasZeroNetIOB() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [tempBasal(rate: 1.0, at: now)]  // 1 U/hr = scheduled
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Net IOB is zero (delivered == scheduled)
        #expect(abs(iob - 0.0) < 0.001)
    }
    
    @Test("Temp basal above scheduled has positive net IOB")
    func tempBasalAboveScheduledHasPositiveNetIOB() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [tempBasal(rate: 2.0, at: now)]  // 2 U/hr delivered
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Net = (2 - 1) * 5/60 = 0.0833 U
        #expect(iob > 0.0)
        #expect(abs(iob - 0.0833) < 0.01)
    }
    
    @Test("Temp basal below scheduled has negative net IOB")
    func tempBasalBelowScheduledHasNegativeNetIOB() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [tempBasal(rate: 0.0, at: now)]  // 0 U/hr (suspended)
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Net = (0 - 1) * 5/60 = -0.0833 U
        #expect(iob < 0.0)
        #expect(abs(iob - (-0.0833)) < 0.01)
    }
    
    // MARK: - Activity Tests
    
    @Test("Bolus activity at time zero")
    func bolusActivityAtTimeZero() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let activity = calculator.insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // oref0 model has minimal activity at t=0 (curve starts from 0)
        #expect(activity < 0.1)
    }
    
    @Test("Bolus activity at peak")
    func bolusActivityAtPeak() {
        let calculator = Oref0NetBasalIOBCalculator(insulinType: .novolog)
        // Novolog peaks at ~1 hour
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let activity = calculator.insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Should have significant activity at peak
        #expect(activity > 0.0)
    }
    
    // MARK: - Cross-Algorithm Comparison Tests
    
    @Test("Oref0 Loop comparison for bolus")
    func oref0LoopComparisonForBolus() {
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let loopCalculator = LoopNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareOref0LoopIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            oref0Calculator: oref0Calculator,
            loopCalculator: loopCalculator
        )
        
        // Both should show full IOB at t=0
        #expect(abs(comparison.oref0IOB - 5.0) < 0.01)
        #expect(abs(comparison.loopIOB - 5.0) < 0.01)
        #expect(comparison.isWithinTolerance(0.1))
    }
    
    @Test("Oref0 Loop comparison for temp basal")
    func oref0LoopComparisonForTempBasal() {
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let loopCalculator = LoopNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 2.0, at: now)]  // Extra insulin
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareOref0LoopIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            oref0Calculator: oref0Calculator,
            loopCalculator: loopCalculator
        )
        
        // Both should show same net IOB
        #expect(abs(comparison.oref0IOB - comparison.loopIOB) < 0.02)
        #expect(comparison.isWithinTolerance(0.05))
    }
    
    @Test("Oref0 Loop comparison at one hour")
    func oref0LoopComparisonAtOneHour() {
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let loopCalculator = LoopNetBasalIOBCalculator()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareOref0LoopIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            oref0Calculator: oref0Calculator,
            loopCalculator: loopCalculator
        )
        
        // Both should show significant decay
        #expect(comparison.oref0IOB < 5.0)
        #expect(comparison.loopIOB < 5.0)
        
        // oref0 and Loop use different models, so some divergence expected
        // But should be within 20% of each other
        #expect(comparison.relativeDifference < 20.0)
    }
    
    // MARK: - Oref1Algorithm Integration Tests
    
    @Test("Oref1 algorithm create net basal calculator")
    func oref1AlgorithmCreateNetBasalCalculator() {
        let algorithm = Oref1Algorithm()
        let calculator = algorithm.createNetBasalIOBCalculator()
        
        let doses = [bolus(units: 3.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(iob - 3.0) < 0.01)
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty doses")
    func emptyDoses() {
        let calculator = Oref0NetBasalIOBCalculator()
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: [],
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(iob == 0.0)
    }
    
    @Test("Empty basal schedule")
    func emptyBasalSchedule() {
        let calculator = Oref0NetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: [],
            at: now,
            delta: 5 * 60
        )
        
        // Boluses should still work
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Future dose")
    func futureDose() {
        let calculator = Oref0NetBasalIOBCalculator()
        let futureDose = bolus(units: 5.0, at: now.addingTimeInterval(3600))
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: [futureDose],
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Future doses should contribute 0 IOB
        #expect(abs(iob - 0.0) < 0.001)
    }
    
    @Test("Different insulin types")
    func differentInsulinTypes() {
        let fiaspCalculator = Oref0NetBasalIOBCalculator(insulinType: .fiasp)
        let novologCalculator = Oref0NetBasalIOBCalculator(insulinType: .novolog)
        
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let fiaspIOB = fiaspCalculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        let novologIOB = novologCalculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        // Fiasp is faster-acting, so should have less IOB remaining at 1 hour
        #expect(fiaspIOB < novologIOB)
    }
}
