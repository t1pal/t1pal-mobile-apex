// PhysiologyModelTests.swift
// T1PalAlgorithmTests
//
// Tests for physiology model types
// Trace: GLUCOS-IMPL-003

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Physiological Snapshot")
struct PhysiologicalSnapshotTests {
    @Test("Snapshot creation")
    func snapshotCreation() {
        let now = Date()
        let snapshot = PhysiologicalSnapshot(
            timestamp: now,
            glucose: 120,
            insulinDelivered: 0.5,
            insulinOnBoard: 2.0,
            carbsOnBoard: 10
        )
        
        #expect(snapshot.glucose == 120)
        #expect(snapshot.insulinDelivered == 0.5)
        #expect(snapshot.insulinOnBoard == 2.0)
        #expect(snapshot.carbsOnBoard == 10)
    }
    
    @Test("Delta calculation")
    func deltaCalculation() {
        let now = Date()
        let previous = PhysiologicalSnapshot(
            timestamp: now,
            glucose: 100,
            insulinDelivered: 0,
            insulinOnBoard: 2.0,
            carbsOnBoard: 20
        )
        let current = PhysiologicalSnapshot(
            timestamp: now.addingTimeInterval(300),  // 5 minutes
            glucose: 110,
            insulinDelivered: 0.5,
            insulinOnBoard: 1.8,
            carbsOnBoard: 15
        )
        
        let delta = current.delta(from: previous)
        
        #expect(delta.timeDelta == 300)
        #expect(delta.glucoseDelta == 10)
        #expect(delta.glucoseRatePerHour == 120)  // 10 mg/dL per 5 min = 120 per hour
        #expect(abs(delta.insulinDelta - (-0.2)) < 0.001)
        #expect(delta.carbsDelta == -5)
    }
}

@Suite("Physiological Data Frame")
struct PhysiologicalDataFrameTests {
    @Test("Empty data frame")
    func emptyDataFrame() {
        let frame = PhysiologicalDataFrame(snapshots: [])
        
        #expect(frame.isEmpty)
        #expect(frame.count == 0)
        #expect(!frame.isValid)
        #expect(frame.latestGlucose == nil)
    }
    
    @Test("Valid data frame")
    func validDataFrame() {
        let now = Date()
        var snapshots: [PhysiologicalSnapshot] = []
        
        // Create 24 snapshots (2 hours at 5-min intervals)
        for i in 0..<24 {
            let snapshot = PhysiologicalSnapshot(
                timestamp: now.addingTimeInterval(Double(i) * 300),
                glucose: 100 + Double(i),
                insulinDelivered: 0.1,
                insulinOnBoard: 2.0 - Double(i) * 0.05,
                carbsOnBoard: 0
            )
            snapshots.append(snapshot)
        }
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        
        #expect(!frame.isEmpty)
        #expect(frame.count == 24)
        #expect(frame.isValid)
        #expect(frame.latestGlucose == 123)
    }
    
    @Test("Duration")
    func duration() {
        let now = Date()
        let snapshots = [
            PhysiologicalSnapshot(timestamp: now, glucose: 100, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(3600), glucose: 120, insulinDelivered: 0, insulinOnBoard: 0)
        ]
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        #expect(frame.duration == 3600)
    }
    
    @Test("Average glucose")
    func averageGlucose() {
        let now = Date()
        let snapshots = [
            PhysiologicalSnapshot(timestamp: now, glucose: 100, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(300), glucose: 120, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(600), glucose: 140, insulinDelivered: 0, insulinOnBoard: 0)
        ]
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        #expect(frame.averageGlucose == 120)
    }
    
    @Test("Glucose range")
    func glucoseRange() {
        let now = Date()
        let snapshots = [
            PhysiologicalSnapshot(timestamp: now, glucose: 80, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(300), glucose: 120, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(600), glucose: 180, insulinDelivered: 0, insulinOnBoard: 0)
        ]
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        let range = frame.glucoseRange!
        
        #expect(range.min == 80)
        #expect(range.max == 180)
    }
    
    @Test("Deltas")
    func deltas() {
        let now = Date()
        let snapshots = [
            PhysiologicalSnapshot(timestamp: now, glucose: 100, insulinDelivered: 0, insulinOnBoard: 2.0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(300), glucose: 110, insulinDelivered: 0.1, insulinOnBoard: 1.9),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(600), glucose: 115, insulinDelivered: 0.1, insulinOnBoard: 1.8)
        ]
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        let deltas = frame.deltas
        
        #expect(deltas.count == 2)
        #expect(deltas[0].glucoseDelta == 10)
        #expect(deltas[1].glucoseDelta == 5)
    }
    
    @Test("Recent")
    func recent() {
        let now = Date()
        var snapshots: [PhysiologicalSnapshot] = []
        
        for i in 0..<10 {
            snapshots.append(PhysiologicalSnapshot(
                timestamp: now.addingTimeInterval(Double(i) * 300),
                glucose: Double(100 + i),
                insulinDelivered: 0,
                insulinOnBoard: 0
            ))
        }
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        let recent = frame.recent(3)
        
        #expect(recent.count == 3)
        #expect(recent.snapshots[0].glucose == 107)
        #expect(recent.snapshots[2].glucose == 109)
    }
    
    @Test("Sorts snapshots by timestamp")
    func sortsSnapshotsByTimestamp() {
        let now = Date()
        
        // Add out of order
        let snapshots = [
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(600), glucose: 130, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now, glucose: 100, insulinDelivered: 0, insulinOnBoard: 0),
            PhysiologicalSnapshot(timestamp: now.addingTimeInterval(300), glucose: 110, insulinDelivered: 0, insulinOnBoard: 0)
        ]
        
        let frame = PhysiologicalDataFrame(snapshots: snapshots)
        
        #expect(frame.snapshots[0].glucose == 100)
        #expect(frame.snapshots[1].glucose == 110)
        #expect(frame.snapshots[2].glucose == 130)
    }
}

@Suite("PID Temp Basal Result")
struct PIDTempBasalResultTests {
    @Test("Total PID")
    func totalPID() {
        let result = PIDTempBasalResult(
            tempBasal: 1.5,
            proportional: 0.3,
            integral: 0.1,
            derivative: -0.05
        )
        
        #expect(abs(result.totalPID - 0.35) < 0.001)
    }
    
    @Test("Digesting flag")
    func digestingFlag() {
        let result = PIDTempBasalResult(
            tempBasal: 2.0,
            isDigesting: true,
            reason: "Meal detected"
        )
        
        #expect(result.isDigesting)
        #expect(result.reason == "Meal detected")
    }
}

@Suite("IOB Result")
struct IOBResultTests {
    @Test("Hours to zero")
    func hoursToZero() {
        let result = IOBResult(
            total: 5.0,
            basal: 2.0,
            bolus: 3.0,
            timeToZero: 3 * 3600  // 3 hours
        )
        
        #expect(result.hoursToZero == 3.0)
    }
    
    @Test("Zero IOB")
    func zeroIOB() {
        let zero = IOBResult.zero
        
        #expect(zero.total == 0)
        #expect(zero.basal == 0)
        #expect(zero.bolus == 0)
        #expect(zero.timeToZero == 0)
    }
}

@Suite("Low Pass Filter")
struct LowPassFilterTests {
    @Test("Default tau")
    func defaultTau() {
        let filter = LowPassFilter()
        #expect(abs(filter.tau - 11.3 * 60) < 0.1)
    }
    
    @Test("Empty readings")
    func emptyReadings() {
        let filter = LowPassFilter()
        let result = filter.apply(to: [])
        #expect(result.isEmpty)
    }
    
    @Test("Single reading")
    func singleReading() {
        let filter = LowPassFilter()
        let reading = GlucoseReading(glucose: 120, timestamp: Date())
        let result = filter.apply(to: [reading])
        
        #expect(result.count == 1)
        #expect(result[0] == 120)
    }
    
    @Test("Smooths spikes")
    func smoothsSpikes() {
        let filter = LowPassFilter(tau: 5 * 60)  // 5 minute tau for faster response
        let now = Date()
        
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now),
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 150, timestamp: now.addingTimeInterval(600)),  // Spike
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(900)),
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(1200))
        ]
        
        let filtered = filter.apply(to: readings)
        
        // The spike should be dampened
        #expect(filtered[2] < 150)
        // Following readings should still show effect
        #expect(filtered[3] > 100)
    }
    
    @Test("Step function")
    func stepFunction() {
        let filter = LowPassFilter(tau: 60)  // 1 minute
        
        // After 1 tau, should be ~63% of the way to new value
        let result = filter.step(previous: 100, current: 200, dt: 60)
        
        // Expected: 100 + 0.632 * (200 - 100) ≈ 163.2
        #expect(abs(result - 163.2) < 1.0)
    }
    
    @Test("Zero dt returns current value")
    func zeroDtReturnsCurrentValue() {
        let filter = LowPassFilter()
        let result = filter.step(previous: 100, current: 150, dt: 0)
        #expect(result == 150)
    }
}

@Suite("Delta Glucose Calculator")
struct DeltaGlucoseCalculatorTests {
    @Test("Insufficient readings")
    func insufficientReadings() {
        let calc = DeltaGlucoseCalculator(minimumReadings: 3)
        
        let readings = [
            GlucoseReading(glucose: 100, timestamp: Date())
        ]
        
        let result = calc.calculate(from: readings)
        #expect(result == nil)
    }
    
    @Test("Steady glucose")
    func steadyGlucose() {
        let calc = DeltaGlucoseCalculator(minimumReadings: 3)
        let now = Date()
        
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now),
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(600))
        ]
        
        let result = calc.calculate(from: readings)
        #expect(result != nil)
        #expect(abs(result! - 0) < 0.1)
    }
    
    @Test("Rising glucose")
    func risingGlucose() {
        let calc = DeltaGlucoseCalculator(minimumReadings: 3)
        let now = Date()
        
        // Rising 10 mg/dL per 5 minutes = 120 mg/dL per hour
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now),
            GlucoseReading(glucose: 110, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 120, timestamp: now.addingTimeInterval(600))
        ]
        
        let result = calc.calculate(from: readings)
        #expect(result != nil)
        #expect(abs(result! - 120) < 1.0)
    }
    
    @Test("Falling glucose")
    func fallingGlucose() {
        let calc = DeltaGlucoseCalculator(minimumReadings: 3)
        let now = Date()
        
        // Falling 5 mg/dL per 5 minutes = -60 mg/dL per hour
        let readings = [
            GlucoseReading(glucose: 150, timestamp: now),
            GlucoseReading(glucose: 145, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 140, timestamp: now.addingTimeInterval(600))
        ]
        
        let result = calc.calculate(from: readings)
        #expect(result != nil)
        #expect(abs(result! - (-60)) < 1.0)
    }
    
    @Test("Expected delta")
    func expectedDelta() {
        let calc = DeltaGlucoseCalculator()
        
        // 2 units IOB, 1 unit/hr basal, ISF 50
        // Net insulin = 2 - 1 = 1 unit
        // Expected drop = -50 mg/dL
        let expected = calc.expectedDelta(
            insulinOnBoard: 2.0,
            insulinSensitivity: 50,
            basalRate: 1.0,
            hours: 1.0
        )
        
        #expect(abs(expected - (-50)) < 0.1)
    }
    
    @Test("Delta error")
    func deltaError() {
        let calc = DeltaGlucoseCalculator(minimumReadings: 3)
        let now = Date()
        
        // Actual: rising 60 mg/dL/hr
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now),
            GlucoseReading(glucose: 105, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 110, timestamp: now.addingTimeInterval(600))
        ]
        
        // Expected: falling 50 mg/dL based on IOB
        let error = calc.deltaError(
            readings: readings,
            insulinOnBoard: 2.0,
            insulinSensitivity: 50,
            basalRate: 1.0
        )
        
        #expect(error != nil)
        // Actual (+60) - Expected (-50) = +110
        #expect(abs(error! - 110) < 5.0)
    }
}
