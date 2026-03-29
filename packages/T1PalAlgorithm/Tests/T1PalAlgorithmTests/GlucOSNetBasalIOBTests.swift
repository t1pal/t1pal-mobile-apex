// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GlucOSNetBasalIOBTests.swift
// T1Pal Mobile
//
// Tests for GlucOS NetBasalIOBProvider implementation
// Trace: ALG-NET-003

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("GlucOS NetBasalIOB")
struct GlucOSNetBasalIOBTests {
    
    // MARK: - Test Fixtures
    
    private var now: Date { Date() }
    
    private func flatBasalSchedule(at date: Date) -> [AbsoluteScheduleValue<Double>] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return [AbsoluteScheduleValue(startDate: start, endDate: end, value: 1.0)]
    }
    
    private func bolus(units: Double, at date: Date) -> InsulinDose {
        InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "bolus"
        )
    }
    
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
    
    @Test("GlucOS calculator conforms to protocol")
    func glucOSCalculatorConformsToProtocol() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let _: NetBasalIOBProvider = calculator
    }
    
    // MARK: - Bolus IOB Tests
    
    @Test("Bolus IOB at time zero")
    func bolusIOBAtTimeZero() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Bolus IOB decays over time")
    func bolusIOBDecaysOverTime() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(iob < 5.0)
        #expect(iob > 2.0)
    }
    
    @Test("Bolus IOB near zero at DIA")
    func bolusIOBNearZeroAtDIA() {
        let calculator = GlucOSNetBasalIOBCalculator(insulinType: .novolog)
        let sixHoursAgo = now.addingTimeInterval(-6 * 3600)
        let doses = [bolus(units: 5.0, at: sixHoursAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(iob < 0.1)
    }
    
    // MARK: - Net Basal IOB Tests
    
    @Test("Temp basal at scheduled rate has zero net IOB")
    func tempBasalAtScheduledRateHasZeroNetIOB() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 1.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(iob - 0.0) < 0.001)
    }
    
    @Test("Temp basal above scheduled has positive net IOB")
    func tempBasalAboveScheduledHasPositiveNetIOB() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 2.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(iob > 0.0)
        #expect(abs(iob - 0.0833) < 0.01)
    }
    
    @Test("Temp basal below scheduled has negative net IOB")
    func tempBasalBelowScheduledHasNegativeNetIOB() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 0.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(iob < 0.0)
        #expect(abs(iob - (-0.0833)) < 0.01)
    }
    
    // MARK: - Activity Tests
    
    @Test("Bolus activity at peak")
    func bolusActivityAtPeak() {
        let calculator = GlucOSNetBasalIOBCalculator(insulinType: .novolog)
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let activity = calculator.insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(activity > 0.0)
    }
    
    // MARK: - Three-Way Comparison Tests
    
    @Test("Three-way comparison for bolus")
    func threeWayComparisonForBolus() {
        let loopCalculator = LoopNetBasalIOBCalculator()
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let glucosCalculator = GlucOSNetBasalIOBCalculator()
        
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareAllAlgorithmsIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            loopCalculator: loopCalculator,
            oref0Calculator: oref0Calculator,
            glucosCalculator: glucosCalculator
        )
        
        // All should show full IOB at t=0
        #expect(abs(comparison.loopIOB - 5.0) < 0.01)
        #expect(abs(comparison.oref0IOB - 5.0) < 0.01)
        #expect(abs(comparison.glucosIOB - 5.0) < 0.01)
        #expect(comparison.isAligned(tolerance: 0.1))
    }
    
    @Test("Three-way comparison for temp basal")
    func threeWayComparisonForTempBasal() {
        let loopCalculator = LoopNetBasalIOBCalculator()
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let glucosCalculator = GlucOSNetBasalIOBCalculator()
        
        let doses = [tempBasal(rate: 2.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareAllAlgorithmsIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            loopCalculator: loopCalculator,
            oref0Calculator: oref0Calculator,
            glucosCalculator: glucosCalculator
        )
        
        // All should show same net IOB at t=0
        #expect(comparison.isAligned(tolerance: 0.05))
        #expect(comparison.outlier == nil)
    }
    
    @Test("Three-way comparison at one hour")
    func threeWayComparisonAtOneHour() {
        let loopCalculator = LoopNetBasalIOBCalculator()
        let oref0Calculator = Oref0NetBasalIOBCalculator()
        let glucosCalculator = GlucOSNetBasalIOBCalculator()
        
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let comparison = compareAllAlgorithmsIOB(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            loopCalculator: loopCalculator,
            oref0Calculator: oref0Calculator,
            glucosCalculator: glucosCalculator
        )
        
        // All should show significant decay
        #expect(comparison.loopIOB < 5.0)
        #expect(comparison.oref0IOB < 5.0)
        #expect(comparison.glucosIOB < 5.0)
        
        // oref0 and GlucOS use same model, should be identical
        #expect(abs(comparison.oref0IOB - comparison.glucosIOB) < 0.001)
    }
    
    @Test("Three-way statistics")
    func threeWayStatistics() {
        let comparison = ThreeWayIOBComparison(
            loopIOB: 3.5,
            oref0IOB: 3.4,
            glucosIOB: 3.4
        )
        
        #expect(abs(comparison.averageIOB - 3.433) < 0.01)
        #expect(abs(comparison.maxDifference - 0.1) < 0.001)
        #expect(comparison.standardDeviation < 0.1)
        #expect(comparison.isAligned(tolerance: 0.15))
    }
    
    // MARK: - GlucOSAlgorithm Integration Tests
    
    @Test("GlucOS algorithm creates net basal calculator")
    func glucOSAlgorithmCreateNetBasalCalculator() {
        let algorithm = GlucOSAlgorithm()
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
        let calculator = GlucOSNetBasalIOBCalculator()
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
        let calculator = GlucOSNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: [],
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Future dose")
    func futureDose() {
        let calculator = GlucOSNetBasalIOBCalculator()
        let futureDose = bolus(units: 5.0, at: now.addingTimeInterval(3600))
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: [futureDose],
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(iob - 0.0) < 0.001)
    }
    
    @Test("GlucOS matches oref0")
    func glucOSMatchesOref0() {
        // GlucOS and oref0 use the same underlying InsulinModel
        // so they should produce identical results
        let glucosCalculator = GlucOSNetBasalIOBCalculator(insulinType: .novolog)
        let oref0Calculator = Oref0NetBasalIOBCalculator(insulinType: .novolog)
        
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        let glucosIOB = glucosCalculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        let oref0IOB = oref0Calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            delta: 5 * 60
        )
        
        #expect(abs(glucosIOB - oref0IOB) < 0.0001)
    }
}
