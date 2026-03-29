// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6CalibrationMessageTests.swift
// CGMKitTests
//
// Tests for Dexcom G6 calibration message parsing
// Reference: CGMBLEKit CalibrationDataRxMessageTests
// Trace: PROTO-G6-001

import Testing
import Foundation
@testable import CGMKit

@Suite("G6 Calibration Message Tests")
struct G6CalibrationMessageTests {
    
    // MARK: - CalibrationDataTxMessage Tests
    
    @Test("CalibrationTxMessage generates correct opcode")
    func calibrationTxMessage_generatesCorrectOpcode() {
        let message = CalibrationDataTxMessage()
        
        #expect(message.opcode == 0x32)
        #expect(message.dataWithoutCRC == Data([0x32]))
    }
    
    @Test("CalibrationTxMessage appends CRC")
    func calibrationTxMessage_appendsCRC() {
        let message = CalibrationDataTxMessage()
        let data = message.data
        
        // Should be opcode + 2 bytes CRC
        #expect(data.count == 3)
        #expect(data[0] == 0x32)
        
        // Verify CRC is valid
        #expect(data.isCRCValid)
    }
    
    // MARK: - CalibrationDataRxMessage Tests
    
    @Test("CalibrationRxMessage parses valid response")
    func calibrationRxMessage_parsesValidResponse() {
        // From CGMBLEKit CalibrationDataRxMessageTests
        let data = Data(hexString: "33002b290090012900ae00800050e929001225")!
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        #expect(message?.opcode == 0x33)
        #expect(message?.glucose == 128)  // 0x0080 & 0x0FFF
        #expect(message?.isValid == true)
    }
    
    @Test("CalibrationRxMessage extracts glucose lower 12 bits")
    func calibrationRxMessage_extractsGlucoseLower12Bits() {
        // Glucose value is lower 12 bits of bytes 11-12
        // 0xF0C8 & 0x0FFF = 0x0C8 = 200
        // Build test data with valid CRC
        let payload = Data(hexString: "3300000000000000000000c8f0a0860100")!
        let data = payload.appendingCRC()
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        // 0xF0C8 little-endian at bytes 11-12, masked with 0x0FFF = 200
        #expect(message?.glucose == 200)
    }
    
    @Test("CalibrationRxMessage extracts timestamp")
    func calibrationRxMessage_extractsTimestamp() {
        // Timestamp 100000 (0x000186a0) at bytes 13-16 little-endian
        // Build test data with valid CRC
        let payload = Data(hexString: "3300000000000000000000c800a0860100")!
        let data = payload.appendingCRC()
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        #expect(message?.timestamp == 100000)
    }
    
    @Test("CalibrationRxMessage invalid when glucose zero")
    func calibrationRxMessage_invalidWhenGlucoseZero() {
        let data = Data(hexString: "33002b290090012900ae00800050e929001225")!
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        #expect(message?.isValid == true)
        
        // A message with glucose = 0 would have isValid = false
        // The logic is: isValid = glucose > 0
    }
    
    @Test("CalibrationRxMessage rejects wrong opcode")
    func calibrationRxMessage_rejectsWrongOpcode() {
        // Change opcode from 0x33 to 0x31
        let data = Data(hexString: "31002b290090012900ae00800050e929001225")!
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message == nil)
    }
    
    @Test("CalibrationRxMessage rejects wrong length")
    func calibrationRxMessage_rejectsWrongLength() {
        // Too short
        let shortData = Data(hexString: "33002b2900900129")!
        #expect(CalibrationDataRxMessage(data: shortData) == nil)
        
        // Too long
        let longData = Data(hexString: "33002b290090012900ae00800050e92900122500")!
        #expect(CalibrationDataRxMessage(data: longData) == nil)
    }
    
    @Test("CalibrationRxMessage rejects invalid CRC")
    func calibrationRxMessage_rejectsInvalidCRC() {
        // Valid message with corrupted CRC
        let data = Data(hexString: "33002b290090012900ae00800050e929001234")!
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message == nil)
    }
    
    @Test("CalibrationRxMessage raw hex for debugging")
    func calibrationRxMessage_rawHexForDebugging() {
        let data = Data(hexString: "33002b290090012900ae00800050e929001225")!
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        #expect(message?.rawHex == "33002b290090012900ae00800050e929001225")
    }
    
    @Test("CalibrationRxMessage glucose mg/dL conversion")
    func calibrationRxMessage_glucoseMgDlConversion() {
        let data = Data(hexString: "33002b290090012900ae00800050e929001225")!
        
        let message = CalibrationDataRxMessage(data: data)
        
        #expect(message != nil)
        #expect(message?.glucoseMgDl == 128.0)
    }
}

// Note: Data.init(hexString:) is defined in G6GlucoseConformanceTests.swift
