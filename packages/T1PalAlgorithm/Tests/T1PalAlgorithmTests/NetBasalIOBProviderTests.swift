// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NetBasalIOBProviderTests.swift
// T1Pal Mobile
//
// Tests for NetBasalIOBProvider protocol
// Trace: ALG-NET-001

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("NetBasalIOBProvider")
struct NetBasalIOBProviderTests {
    
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
        // Rate in U/hr, 5 min segment = rate * (5/60) units
        let units = rate * (5.0 / 60.0)
        return InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "temp_basal"
        )
    }
    
    // MARK: - Protocol Conformance Tests
    
    @Test("LoopNetBasalCalculator conforms to protocol")
    func loopNetBasalCalculatorConformsToProtocol() {
        // Given
        let calculator = LoopNetBasalIOBCalculator()
        
        // Then - compiles successfully, proving conformance
        let _: NetBasalIOBProvider = calculator
    }
    
    // MARK: - Bolus IOB Tests
    
    @Test("Bolus IOB at time zero")
    func bolusIOBAtTimeZero() {
        // Given: 5U bolus just delivered
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Full IOB (100% remaining)
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Bolus IOB decays over time")
    func bolusIOBDecaysOverTime() {
        // Given: 5U bolus 1 hour ago
        let calculator = LoopNetBasalIOBCalculator()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let doses = [bolus(units: 5.0, at: oneHourAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Some decay (roughly 70-85% remaining at 1 hour for rapid-acting)
        #expect(iob < 5.0)
        #expect(iob > 3.0)
    }
    
    @Test("Bolus IOB near zero at 6 hours")
    func bolusIOBNearZeroAt6Hours() {
        // Given: 5U bolus 6 hours ago
        let calculator = LoopNetBasalIOBCalculator()
        let sixHoursAgo = now.addingTimeInterval(-6 * 3600)
        let doses = [bolus(units: 5.0, at: sixHoursAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Nearly zero IOB
        #expect(iob < 0.1)
    }
    
    // MARK: - Net Basal IOB Tests
    
    @Test("Temp basal at scheduled rate has zero net IOB")
    func tempBasalAtScheduledRateHasZeroNetIOB() {
        // Given: Temp basal at exactly scheduled rate (1 U/hr)
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 1.0, at: now)]  // 1 U/hr = scheduled
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Net IOB is zero (delivered == scheduled)
        #expect(abs(iob - 0.0) < 0.001)
    }
    
    @Test("Temp basal above scheduled has positive net IOB")
    func tempBasalAboveScheduledHasPositiveNetIOB() {
        // Given: Temp basal at 2 U/hr when scheduled is 1 U/hr
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 2.0, at: now)]  // 2 U/hr delivered
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Net IOB is positive (delivered > scheduled)
        // Net = (2 - 1) * 5/60 = 1 * 0.0833 = 0.0833 U net contribution
        #expect(iob > 0.0)
        #expect(abs(iob - 0.0833) < 0.01)
    }
    
    @Test("Temp basal below scheduled has negative net IOB")
    func tempBasalBelowScheduledHasNegativeNetIOB() {
        // Given: Temp basal at 0 U/hr when scheduled is 1 U/hr (suspend)
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 0.0, at: now)]  // 0 U/hr (suspended)
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Net IOB is negative (delivered < scheduled)
        // Net = (0 - 1) * 5/60 = -1 * 0.0833 = -0.0833 U net contribution
        #expect(iob < 0.0)
        #expect(abs(iob - (-0.0833)) < 0.01)
    }
    
    // MARK: - Combined Doses Tests
    
    @Test("Bolus and temp basal combined")
    func bolusAndTempBasalCombined() {
        // Given: 5U bolus + suspend (0 U/hr temp basal)
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [
            bolus(units: 5.0, at: now),
            tempBasal(rate: 0.0, at: now)  // Suspend
        ]
        let basalSchedule = flatBasalSchedule(at: now)  // 1 U/hr scheduled
        
        // When
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: 5.0 from bolus - 0.0833 from suspend = ~4.92
        #expect(abs(iob - (5.0 - 0.0833)) < 0.01)
    }
    
    // MARK: - Activity Tests
    
    @Test("Bolus activity at time zero")
    func bolusActivityAtTimeZero() {
        // Given: 5U bolus just delivered (within delay period)
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let activity = calculator.insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Zero activity during delay period
        #expect(abs(activity - 0.0) < 0.001)
    }
    
    @Test("Bolus activity after delay")
    func bolusActivityAfterDelay() {
        // Given: 5U bolus 15 minutes ago (past 10-min delay)
        let calculator = LoopNetBasalIOBCalculator()
        let fifteenMinutesAgo = now.addingTimeInterval(-15 * 60)
        let doses = [bolus(units: 5.0, at: fifteenMinutesAgo)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let activity = calculator.insulinActivityNetBasal(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Then: Some activity (absorption started)
        #expect(activity > 0.0)
    }
    
    // MARK: - Timeline Tests
    
    @Test("IOB timeline generation")
    func iobTimelineGeneration() {
        // Given
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When: Generate 1-hour timeline
        let timeline = calculator.iobTimeline(
            doses: doses,
            basalSchedule: basalSchedule,
            from: now,
            to: now.addingTimeInterval(3600)
        )
        
        // Then: Timeline should have points every 5 minutes = 13 points for 1 hour
        #expect(timeline.count == 13)
        
        // First point should be full IOB
        #expect(abs((timeline.first?.value ?? 0) - 5.0) < 0.01)
        
        // Values should generally decrease
        for i in 1..<timeline.count {
            #expect(timeline[i].value <= timeline[i-1].value + 0.01)
        }
    }
    
    // MARK: - Comparison Tests
    
    @Test("Absolute vs net basal comparison")
    func absoluteVsNetBasalComparison() {
        // Given: Temp basal at 0 U/hr (suspend)
        let absoluteCalculator = LoopIOBCalculator(
            modelType: .rapidActingAdult
        )
        let netCalculator = LoopNetBasalIOBCalculator()
        let doses = [tempBasal(rate: 0.0, at: now)]
        let basalSchedule = flatBasalSchedule(at: now)
        
        // When
        let comparison = compareIOBCalculations(
            doses: doses,
            basalSchedule: basalSchedule,
            at: now,
            absoluteCalculator: absoluteCalculator,
            netCalculator: netCalculator
        )
        
        // Then:
        // - Absolute IOB: 0 (no insulin delivered)
        // - Net IOB: negative (missed scheduled basal)
        #expect(abs(comparison.absoluteIOB - 0.0) < 0.001)
        #expect(comparison.netBasalIOB < 0.0)
        #expect(comparison.difference > 0.0)  // absolute > net
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty doses")
    func emptyDoses() {
        let calculator = LoopNetBasalIOBCalculator()
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: [],
            basalSchedule: basalSchedule,
            at: now
        )
        
        #expect(iob == 0.0)
    }
    
    @Test("Empty basal schedule")
    func emptyBasalSchedule() {
        let calculator = LoopNetBasalIOBCalculator()
        let doses = [bolus(units: 5.0, at: now)]
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: doses,
            basalSchedule: [],
            at: now
        )
        
        // Boluses should still work (they don't need basal annotation)
        #expect(abs(iob - 5.0) < 0.01)
    }
    
    @Test("Future dose")
    func futureDose() {
        let calculator = LoopNetBasalIOBCalculator()
        let futureDose = bolus(units: 5.0, at: now.addingTimeInterval(3600))
        let basalSchedule = flatBasalSchedule(at: now)
        
        let iob = calculator.insulinOnBoardNetBasal(
            doses: [futureDose],
            basalSchedule: basalSchedule,
            at: now
        )
        
        // Future doses should contribute 0 IOB
        #expect(abs(iob - 0.0) < 0.001)
    }
}
