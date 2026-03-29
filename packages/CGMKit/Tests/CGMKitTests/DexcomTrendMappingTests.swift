// SPDX-License-Identifier: MIT
//
// DexcomTrendMappingTests.swift
// CGMKitTests
//
// Unit tests for Dexcom trend byte mapping per CGM-TREND-003/004
// Validates that raw Dexcom trend values (rate of change in mg/dL/10min) map correctly

import Testing
import Foundation
import T1PalCore
@testable import CGMKit
@testable import BLEKit

/// Tests for Dexcom trend byte mapping
///
/// Reference: Loop's CGMBLEKit/Glucose+SensorDisplayable.swift
/// The G6 trend byte is a RATE OF CHANGE in mg/dL per 10 minutes (signed Int8)
/// NOT discrete 1-7 values. This matches Loop/Trio behavior.
///
/// Mapping (per Loop):
///   trend <= -30  → doubleDown (falling very fast, >= 3 mg/dL/min)
///   trend <= -20  → singleDown (falling fast, 2-3 mg/dL/min)
///   trend <= -10  → fortyFiveDown (falling, 1-2 mg/dL/min)
///   trend < 10    → flat (-1 to +1 mg/dL/min)
///   trend < 20    → fortyFiveUp (rising, 1-2 mg/dL/min)
///   trend < 30    → singleUp (rising fast, 2-3 mg/dL/min)
///   trend >= 30   → doubleUp (rising very fast, >= 3 mg/dL/min)
///
/// Trace: CGM-TREND-003, CGM-TREND-004
@Suite("Dexcom Trend Mapping Tests")
struct DexcomTrendMappingTests {
    
    // MARK: - GlucoseRxMessage parsing
    
    @Test("GlucoseRxMessage parses positive trend byte correctly")
    func glucoseRxMessagePositiveTrend() throws {
        let message = buildGlucoseRxMessage(trend: 15)
        #expect(message != nil, "GlucoseRxMessage should parse")
        #expect(message?.trend == 15, "Raw trend should be 15")
    }
    
    @Test("GlucoseRxMessage parses zero trend byte correctly")
    func glucoseRxMessageZeroTrend() throws {
        let message = buildGlucoseRxMessage(trend: 0)
        #expect(message != nil, "GlucoseRxMessage should parse")
        #expect(message?.trend == 0, "Raw trend should be 0 (flat)")
    }
    
    @Test("GlucoseRxMessage parses negative trend correctly")
    func glucoseRxMessageNegativeTrend() throws {
        let message = buildGlucoseRxMessage(trend: -15)
        #expect(message != nil, "GlucoseRxMessage should parse")
        #expect(message?.trend == -15, "Raw trend should be -15")
    }
    
    // MARK: - Trend value semantics (rate of change mapping)
    
    @Test("Trend +35 represents rising very fast (doubleUp)")
    func trend35IsRisingVeryFast() throws {
        let trend = GlucoseTrend.doubleUp
        #expect(trend.arrow == "↑↑", "doubleUp should display as ↑↑")
    }
    
    @Test("Trend 0 represents flat")
    func trend0IsFlat() throws {
        let trend = GlucoseTrend.flat
        #expect(trend.arrow == "→", "flat should display as →")
    }
    
    @Test("Trend -35 represents falling very fast (doubleDown)")
    func trendNeg35IsFallingVeryFast() throws {
        let trend = GlucoseTrend.doubleDown
        #expect(trend.arrow == "↓↓", "doubleDown should display as ↓↓")
    }
    
    // MARK: - G6 Integration via Manager (rate-of-change values per Loop)
    
    @Test("G6 manager maps trend +35 to doubleUp (rising very fast)")
    func g6ManagerTrendPositive35() async throws {
        let reading = await createG6ReadingWithTrend(35)
        #expect(reading?.trend == .doubleUp, "Trend +35 should map to doubleUp")
    }
    
    @Test("G6 manager maps trend +25 to singleUp (rising fast)")
    func g6ManagerTrendPositive25() async throws {
        let reading = await createG6ReadingWithTrend(25)
        #expect(reading?.trend == .singleUp, "Trend +25 should map to singleUp")
    }
    
    @Test("G6 manager maps trend +15 to fortyFiveUp (rising)")
    func g6ManagerTrendPositive15() async throws {
        let reading = await createG6ReadingWithTrend(15)
        #expect(reading?.trend == .fortyFiveUp, "Trend +15 should map to fortyFiveUp")
    }
    
    @Test("G6 manager maps trend 0 to flat")
    func g6ManagerTrend0() async throws {
        let reading = await createG6ReadingWithTrend(0)
        #expect(reading?.trend == .flat, "Trend 0 should map to flat")
    }
    
    @Test("G6 manager maps trend +5 to flat")
    func g6ManagerTrendPositive5() async throws {
        let reading = await createG6ReadingWithTrend(5)
        #expect(reading?.trend == .flat, "Trend +5 should map to flat (within ±10 range)")
    }
    
    @Test("G6 manager maps trend -5 to flat")
    func g6ManagerTrendNegative5() async throws {
        let reading = await createG6ReadingWithTrend(-5)
        #expect(reading?.trend == .flat, "Trend -5 should map to flat (within ±10 range)")
    }
    
    @Test("G6 manager maps trend -15 to fortyFiveDown (falling)")
    func g6ManagerTrendNegative15() async throws {
        let reading = await createG6ReadingWithTrend(-15)
        #expect(reading?.trend == .fortyFiveDown, "Trend -15 should map to fortyFiveDown")
    }
    
    @Test("G6 manager maps trend -25 to singleDown (falling fast)")
    func g6ManagerTrendNegative25() async throws {
        let reading = await createG6ReadingWithTrend(-25)
        #expect(reading?.trend == .singleDown, "Trend -25 should map to singleDown")
    }
    
    @Test("G6 manager maps trend -35 to doubleDown (falling very fast)")
    func g6ManagerTrendNegative35() async throws {
        let reading = await createG6ReadingWithTrend(-35)
        #expect(reading?.trend == .doubleDown, "Trend -35 should map to doubleDown")
    }
    
    // MARK: - Boundary tests (Loop-compatible thresholds)
    
    @Test("G6 manager maps trend +10 to fortyFiveUp (boundary)")
    func g6ManagerTrendBoundary10() async throws {
        let reading = await createG6ReadingWithTrend(10)
        #expect(reading?.trend == .fortyFiveUp, "Trend +10 should map to fortyFiveUp (at boundary)")
    }
    
    @Test("G6 manager maps trend +20 to singleUp (boundary)")
    func g6ManagerTrendBoundary20() async throws {
        let reading = await createG6ReadingWithTrend(20)
        #expect(reading?.trend == .singleUp, "Trend +20 should map to singleUp (at boundary)")
    }
    
    @Test("G6 manager maps trend -10 to fortyFiveDown (boundary)")
    func g6ManagerTrendBoundaryNeg10() async throws {
        let reading = await createG6ReadingWithTrend(-10)
        #expect(reading?.trend == .fortyFiveDown, "Trend -10 should map to fortyFiveDown (at boundary)")
    }
    
    @Test("G6 manager maps trend -20 to singleDown (boundary)")
    func g6ManagerTrendBoundaryNeg20() async throws {
        let reading = await createG6ReadingWithTrend(-20)
        #expect(reading?.trend == .singleDown, "Trend -20 should map to singleDown (at boundary)")
    }
    
    // MARK: - Helpers
    
    /// Build G6 GlucoseRxMessage data with specified trend
    private func buildGlucoseRxMessage(trend: Int8) -> GlucoseRxMessage? {
        let trendByte = UInt8(bitPattern: trend)
        let data = Data([
            0x31,       // opcode (glucoseRx)
            0x00,       // status
            0x01, 0x00, 0x00, 0x00,  // sequence
            0x64, 0x00, 0x00, 0x00,  // timestamp
            0x78, 0x00,  // glucose (120 mg/dL)
            0x06,       // state (OK)
            trendByte,  // trend
            0x00, 0x00  // crc
        ])
        return GlucoseRxMessage(data: data)
    }
    
    /// Creates a G6 reading with the specified trend byte by using the manager
    private func createG6ReadingWithTrend(_ rawTrend: Int8) async -> GlucoseReading? {
        let tx = TransmitterID("80AB12")!
        let central = MockBLECentral()
        let manager = DexcomG6Manager(transmitterId: tx, central: central, allowSimulation: true)
        
        // Use the test helper to directly invoke the mapping
        let reading = await manager.testCreateGlucoseReading(
            glucose: 120,
            rawTrend: rawTrend,
            source: "test"
        )
        
        return reading
    }
}
