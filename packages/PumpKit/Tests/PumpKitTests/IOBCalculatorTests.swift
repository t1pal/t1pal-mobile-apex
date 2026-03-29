// SPDX-License-Identifier: MIT
//
// IOBCalculatorTests.swift
// PumpKit
//
// Tests for IOB calculation
// Trace: PUMP-INT-001

import Testing
import Foundation
@testable import PumpKit

@Suite("IOB Calculator Tests", .serialized)
struct IOBCalculatorTests {
    
    // MARK: - PumpIOBCalculator Tests
    
    @Test("IOB fraction at zero is 100%")
    func iobFractionAtZero() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        
        // At t=0, all insulin should be on board
        let iob = calculator.iobFraction(at: 0)
        #expect(abs(iob - 1.0) < 0.01, "IOB at t=0 should be ~100%")
    }
    
    @Test("IOB fraction at DIA is 0%")
    func iobFractionAtDIA() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        
        // At t=DIA, no insulin should remain
        let iob = calculator.iobFraction(at: 5.0)
        #expect(abs(iob - 0.0) < 0.01, "IOB at t=DIA should be ~0%")
    }
    
    @Test("IOB fraction at half DIA is between 10% and 90%")
    func iobFractionAtHalfDIA() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        
        // At t=DIA/2, roughly half should remain (depends on curve)
        let iob = calculator.iobFraction(at: 2.5)
        #expect(iob > 0.1, "IOB at half-DIA should be > 10%")
        #expect(iob < 0.9, "IOB at half-DIA should be < 90%")
    }
    
    @Test("IOB decreases monotonically")
    func iobDecreaseMonotonically() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        
        // IOB should decrease over time
        var previousIOB = calculator.iobFraction(at: 0)
        for hour in stride(from: 0.5, through: 5.0, by: 0.5) {
            let currentIOB = calculator.iobFraction(at: hour)
            #expect(currentIOB <= previousIOB, 
                "IOB should decrease monotonically at hour \(hour)")
            previousIOB = currentIOB
        }
    }
    
    @Test("IOB from delivery record")
    func iobFromDeliveryRecord() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        let now = Date()
        
        // 2U bolus 1 hour ago
        let delivery = InsulinDeliveryRecord(
            timestamp: now.addingTimeInterval(-3600),
            units: 2.0,
            type: .bolus
        )
        
        let iob = calculator.iobFromDelivery(delivery, at: now)
        #expect(iob > 0, "Should have some IOB")
        #expect(iob < 2.0, "Should have less than full dose")
    }
    
    @Test("Total IOB from multiple deliveries")
    func totalIOBFromMultipleDeliveries() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        let now = Date()
        
        let deliveries = [
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-1800), units: 1.0, type: .bolus),  // 30 min ago
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-3600), units: 2.0, type: .bolus),  // 1 hr ago
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-7200), units: 1.5, type: .bolus),  // 2 hr ago
        ]
        
        let totalIOB = calculator.totalIOB(from: deliveries, at: now)
        #expect(totalIOB > 0, "Should have combined IOB")
        #expect(totalIOB < 4.5, "Should be less than total delivered")
    }
    
    @Test("Old deliveries excluded")
    func oldDeliveriesExcluded() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        let now = Date()
        
        // Delivery 6 hours ago (beyond DIA)
        let oldDelivery = InsulinDeliveryRecord(
            timestamp: now.addingTimeInterval(-6 * 3600),
            units: 5.0,
            type: .bolus
        )
        
        let iob = calculator.totalIOB(from: [oldDelivery], at: now)
        #expect(abs(iob - 0.0) < 0.01, "Old deliveries should have 0 IOB")
    }
    
    @Test("Prune deliveries")
    func pruneDeliveries() {
        let calculator = PumpIOBCalculator(dia: 5.0)
        let now = Date()
        
        let deliveries = [
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-1 * 3600), units: 1.0, type: .bolus),
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-7 * 3600), units: 2.0, type: .bolus),  // Should be pruned
            InsulinDeliveryRecord(timestamp: now.addingTimeInterval(-3 * 3600), units: 1.5, type: .bolus),
        ]
        
        let pruned = calculator.pruneDeliveries(deliveries, at: now)
        #expect(pruned.count == 2, "Should keep 2 recent deliveries")
    }
    
    // MARK: - IOBTracker Tests
    
    @Test("IOB tracker record and calculate")
    func iobTrackerRecordAndCalculate() async {
        let tracker = IOBTracker(dia: 5.0)
        
        await tracker.recordBolus(units: 2.0)
        
        let iob = await tracker.currentIOB()
        #expect(iob > 1.9, "Just-delivered bolus should have ~100% IOB")
    }
    
    @Test("IOB tracker multiple deliveries")
    func iobTrackerMultipleDeliveries() async {
        let tracker = IOBTracker(dia: 5.0)
        
        await tracker.recordBolus(units: 1.0)
        await tracker.recordBolus(units: 2.0)
        await tracker.recordTempBasal(units: 0.5)
        
        let iob = await tracker.currentIOB()
        #expect(iob > 3.0, "Combined IOB should be high")
    }
    
    @Test("IOB tracker clear history")
    func iobTrackerClearHistory() async {
        let tracker = IOBTracker(dia: 5.0)
        
        await tracker.recordBolus(units: 5.0)
        await tracker.clearHistory()
        
        let iob = await tracker.currentIOB()
        #expect(iob == 0.0, "After clear, IOB should be 0")
    }
    
    // MARK: - Integration with PumpStatus
    
    @Test("Simulation pump IOB")
    func simulationPumpIOB() async throws {
        let pump = SimulationPump()
        
        try await pump.connect()
        
        // Deliver a bolus
        try await pump.deliverBolus(units: 1.0)
        
        // Status should now show IOB > 0
        let status = await pump.status
        #expect(status.insulinOnBoard > 0.9, 
            "IOB should reflect delivered bolus")
    }
    
    @Test("DIA clamping")
    func diaClamping() {
        // DIA should be clamped to safe range
        let shortDIA = PumpIOBCalculator(dia: 1.0)  // Too short
        #expect(shortDIA.dia == 3.0, "DIA should be clamped to minimum 3 hours")
        
        let longDIA = PumpIOBCalculator(dia: 12.0)  // Too long  
        #expect(longDIA.dia == 8.0, "DIA should be clamped to maximum 8 hours")
        
        let normalDIA = PumpIOBCalculator(dia: 5.0)
        #expect(normalDIA.dia == 5.0, "Normal DIA should be unchanged")
    }
}
