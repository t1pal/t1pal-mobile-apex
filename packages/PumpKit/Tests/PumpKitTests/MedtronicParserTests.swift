// SPDX-License-Identifier: MIT
//
// MedtronicParserTests.swift
// PumpKitTests
//
// Tests for Medtronic response parsers
// Trace: RL-PARSE-003 - Parser unit tests with decocare fixtures
//
// These tests validate byte-level parsing against the decocare Python reference:
// https://github.com/bewest/decoding-carelink/blob/master/decocare/commands.py

import Testing
import Foundation
@testable import PumpKit

/// Parser tests that don't require BLE - pure byte parsing validation
@Suite("MedtronicParserTests")
struct MedtronicParserTests {
    
    // MARK: - Status Response Parser Tests (RL-PARSE-005)
    
    /// Tests for MedtronicStatusResponse.parse() per decocare ReadPumpStatus
    /// Reference: decocare/commands.py line 1347
    @Test("Parse status response normal state")
    func parseStatusResponse_normalState() throws {
        // Format: [0]=status (03=normal), [1]=bolusing, [2]=suspended
        let normalData = Data([0x03, 0x00, 0x00])
        let normal = MedtronicStatusResponse.parse(from: normalData)
        
        #expect(normal != nil)
        #expect(!normal!.bolusing)
        #expect(!normal!.suspended)
        #expect(normal!.normalBasalRunning)
    }
    
    @Test("Parse status response bolusing")
    func parseStatusResponse_bolusing() throws {
        // Bolusing state: [1]=1
        let bolusData = Data([0x03, 0x01, 0x00])
        let bolusing = MedtronicStatusResponse.parse(from: bolusData)
        
        #expect(bolusing != nil)
        #expect(bolusing!.bolusing)
        #expect(!bolusing!.suspended)
    }
    
    @Test("Parse status response suspended")
    func parseStatusResponse_suspended() throws {
        // Suspended state: [2]=1
        let suspendData = Data([0x03, 0x00, 0x01])
        let suspended = MedtronicStatusResponse.parse(from: suspendData)
        
        #expect(suspended != nil)
        #expect(!suspended!.bolusing)
        #expect(suspended!.suspended)
        #expect(!suspended!.normalBasalRunning)
    }
    
    @Test("Parse status response too short")
    func parseStatusResponse_tooShort() throws {
        // Too short - should return nil
        let shortData = Data([0x03, 0x00])
        #expect(MedtronicStatusResponse.parse(from: shortData) == nil)
    }
    
    // MARK: - Battery Response Parser Tests (RL-PARSE-004)
    
    /// Tests for MedtronicBatteryResponse.parse() per decocare ReadBatteryStatus
    /// Reference: decocare/commands.py line 688
    @Test("Parse battery response normal")
    func parseBatteryResponse_normal() throws {
        // Format: [0]=indicator (0=normal, 1=low), [1..2]=voltage (big-endian, /100)
        // Normal battery at 1.45V (0x0091 = 145)
        let normalData = Data([0x00, 0x00, 0x91])
        let normal = MedtronicBatteryResponse.parse(from: normalData)
        
        #expect(normal != nil)
        #expect(normal!.status == .normal)
        #expect(abs(normal!.volts - 1.45) < 0.01)
    }
    
    @Test("Parse battery response low")
    func parseBatteryResponse_low() throws {
        // Low battery at 1.15V (0x0073 = 115)
        let lowData = Data([0x01, 0x00, 0x73])
        let low = MedtronicBatteryResponse.parse(from: lowData)
        
        #expect(low != nil)
        #expect(low!.status == .low)
        #expect(abs(low!.volts - 1.15) < 0.01)
    }
    
    @Test("Parse battery response full voltage")
    func parseBatteryResponse_fullVoltage() throws {
        // High voltage battery at 1.55V (0x009B = 155)
        let highData = Data([0x00, 0x00, 0x9B])
        let high = MedtronicBatteryResponse.parse(from: highData)
        
        #expect(high != nil)
        #expect(abs(high!.volts - 1.55) < 0.01)
        #expect(high!.estimatedPercent == 100)
    }
    
    @Test("Parse battery response too short")
    func parseBatteryResponse_tooShort() throws {
        let shortData = Data([0x00, 0x00])
        #expect(MedtronicBatteryResponse.parse(from: shortData) == nil)
    }
    
    // MARK: - Reservoir Response Parser Tests (RL-PARSE-001, MDT-HIST-020)
    
    /// Tests for MedtronicReservoirResponse.parse() per MinimedKit
    /// Reference: ReadRemainingInsulinMessageBody.swift
    /// 
    /// MDT-DIAG-FIX: parse() expects BODY ONLY (headers already stripped by caller)
    /// Production code strips 5-byte header before calling parse() - tests must match
    @Test("Parse reservoir response 523 plus")
    func parseReservoirResponse_523Plus() throws {
        // 523+ pumps (scale=40): body[3:5] = 0x1770 = 6000 strokes = 150.0U
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x17, 0x70])  // body[3:5] = 0x1770
        let reservoir523 = MedtronicReservoirResponse.parse(from: body, scale: 40)
        
        #expect(reservoir523 != nil)
        #expect(abs(reservoir523!.unitsRemaining - 150.0) < 0.1)
    }
    
    @Test("Parse reservoir response older pumps")
    func parseReservoirResponse_olderPumps() throws {
        // Older pumps (scale=10): body[1:3] = 0x05DC = 1500 strokes = 150.0U
        // Body only - no header
        let body = Data([0x00, 0x05, 0xDC])  // body[1:3] = 0x05DC
        let reservoirOld = MedtronicReservoirResponse.parse(from: body, scale: 10)
        
        #expect(reservoirOld != nil)
        #expect(abs(reservoirOld!.unitsRemaining - 150.0) < 0.1)
    }
    
    @Test("Parse reservoir response low level")
    func parseReservoirResponse_lowLevel() throws {
        // Low reservoir: 15U = 600 strokes at scale 40 (0x0258)
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x02, 0x58])  // body[3:5] = 0x0258
        let lowReservoir = MedtronicReservoirResponse.parse(from: body, scale: 40)
        
        #expect(lowReservoir != nil)
        #expect(abs(lowReservoir!.unitsRemaining - 15.0) < 0.1)
    }
    
    @Test("Parse reservoir response empty")
    func parseReservoirResponse_empty() throws {
        // Empty reservoir: 0U
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x00, 0x00])  // body[3:5] = 0x0000
        let empty = MedtronicReservoirResponse.parse(from: body, scale: 40)
        
        #expect(empty != nil)
        #expect(abs(empty!.unitsRemaining - 0.0) < 0.01)
    }
    
    @Test("Parse reservoir response too short")
    func parseReservoirResponse_tooShort() throws {
        // Too short - body needs at least 5 bytes for x23+ (indices [3:5])
        // Body only - no header
        let shortBody = Data([0x00, 0x00, 0x00, 0x17])  // only 4 bytes, need 5
        #expect(MedtronicReservoirResponse.parse(from: shortBody, scale: 40) == nil)
    }
    
    // MARK: - Variant Scale Tests
    
    /// Tests for MedtronicVariant.insulinBitPackingScale per decocare
    @Test("Variant scale older pumps")
    func variantScale_olderPumps() throws {
        // Older pumps (x22) use scale 10
        #expect(MedtronicVariant.model522_NA.insulinBitPackingScale == 10)
        #expect(MedtronicVariant.model522_WW.insulinBitPackingScale == 10)
        #expect(MedtronicVariant.model722_NA.insulinBitPackingScale == 10)
        #expect(MedtronicVariant.model722_WW.insulinBitPackingScale == 10)
    }
    
    @Test("Variant scale 523 plus")
    func variantScale_523Plus() throws {
        // 523+ pumps use scale 40
        #expect(MedtronicVariant.model523_NA.insulinBitPackingScale == 40)
        #expect(MedtronicVariant.model523_WW.insulinBitPackingScale == 40)
        #expect(MedtronicVariant.model723_NA.insulinBitPackingScale == 40)
        #expect(MedtronicVariant.model530_NA.insulinBitPackingScale == 40)
        #expect(MedtronicVariant.model554_NA.insulinBitPackingScale == 40)
        #expect(MedtronicVariant.model754_NA.insulinBitPackingScale == 40)
    }
    
    // MARK: - Battery Percent Estimation Tests
    
    @Test("Battery percent estimation")
    func batteryPercentEstimation() throws {
        // Test the voltage-based percentage estimation
        
        // Full battery (1.55V) = 100%
        let full = MedtronicBatteryResponse.parse(from: Data([0x00, 0x00, 0x9B]))
        #expect(full!.estimatedPercent == 100)
        
        // Mid-range (1.35V) ≈ 55%
        let mid = MedtronicBatteryResponse.parse(from: Data([0x00, 0x00, 0x87]))
        #expect(mid!.estimatedPercent > 40)
        #expect(mid!.estimatedPercent < 70)
        
        // Empty (1.1V) = 0%
        let empty = MedtronicBatteryResponse.parse(from: Data([0x01, 0x00, 0x6E]))
        #expect(empty!.estimatedPercent == 0)
    }
}
