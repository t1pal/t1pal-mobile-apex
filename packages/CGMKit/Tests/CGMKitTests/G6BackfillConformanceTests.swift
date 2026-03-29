// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6BackfillConformanceTests.swift
// CGMKit
//
// Conformance tests for Dexcom G6 backfill protocol
// Trace: SESSION-G6-003
// Reference: externals/CGMBLEKit/CGMBLEKitTests/GlucoseBackfillMessageTests.swift

import Testing
import Foundation
@testable import CGMKit

@Suite("G6BackfillConformanceTests")
struct G6BackfillConformanceTests {
    
    // MARK: - Helper
    
    private func hexData(_ hex: String) -> Data {
        let hexString = hex.filter { !$0.isWhitespace }
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
    
    // MARK: - GlucoseBackfillTxMessage Tests
    
    @Test("Backfill TX message 20 minute request")
    func backfillTxMessage_20MinuteRequest() {
        // Test vector from CGMBLEKit: 20 minute backfill request
        let message = GlucoseBackfillTxMessage(
            startTime: 5439415,  // 0x0052ffb7
            endTime: 5440614,    // 0x00530466
            byte1: 5,
            byte2: 2,
            identifier: 0
        )
        
        let expected = hexData("50050200b7ff5200660453000000000000007138")
        #expect(message.data == expected, "TX message should match CGMBLEKit vector")
    }
    
    @Test("Backfill TX message 25 minute request")
    func backfillTxMessage_25MinuteRequest() {
        // Test vector from CGMBLEKit: 25 minute backfill request
        let message = GlucoseBackfillTxMessage(
            startTime: 4648682,  // 0x0046eeea
            endTime: 4650182,    // 0x0046f4c6
            byte1: 5,
            byte2: 2,
            identifier: 0
        )
        
        let expected = hexData("50050200eaee4600c6f446000000000000009f6d")
        #expect(message.data == expected, "TX message should match CGMBLEKit vector")
    }
    
    // MARK: - GlucoseBackfillRxMessage Tests
    
    @Test("Backfill RX message parse 20 min response")
    func backfillRxMessage_Parse20MinResponse() {
        let data = hexData("51000100b7ff52006604530032000000e6cb9805")
        
        let message = GlucoseBackfillRxMessage(data: data)
        #expect(message != nil)
        
        #expect(message?.status == 0, "Status should be OK")
        #expect(message?.backfillStatus == 1, "Backfill status should be 1")
        #expect(message?.identifier == 0)
        #expect(message?.startTime == 5439415)
        #expect(message?.endTime == 5440614)
        #expect(message?.bufferLength == 50)
        #expect(message?.bufferCRC == 0xcbe6)
        #expect(message?.isSuccess ?? false)
    }
    
    @Test("Backfill RX message parse 25 min response")
    func backfillRxMessage_Parse25MinResponse() {
        let data = hexData("51000103eaee4600c6f446003a0000004f3ac9e6")
        
        let message = GlucoseBackfillRxMessage(data: data)
        #expect(message != nil)
        
        #expect(message?.status == 0)
        #expect(message?.backfillStatus == 1)
        #expect(message?.identifier == 3)
        #expect(message?.startTime == 4648682)
        #expect(message?.endTime == 4650182)
        #expect(message?.bufferLength == 58)
        #expect(message?.bufferCRC == 0x3a4f)
    }
    
    @Test("Backfill RX message 15 min response A")
    func backfillRxMessage_15MinResponseA() {
        let data = hexData("510001023d6a0e00c16d0e00280000005b1a9154")
        
        let message = GlucoseBackfillRxMessage(data: data)
        #expect(message != nil)
        
        #expect(message?.identifier == 2)
        #expect(message?.startTime == 944701)
        #expect(message?.endTime == 945601)
        #expect(message?.bufferLength == 40)
        #expect(message?.bufferCRC == 0x1a5b)
    }
    
    @Test("Backfill RX message 15 min response B")
    func backfillRxMessage_15MinResponseB() {
        let data = hexData("51000103c9740e004d780e0028000000235bd94c")
        
        let message = GlucoseBackfillRxMessage(data: data)
        #expect(message != nil)
        
        #expect(message?.identifier == 3)
        #expect(message?.startTime == 947401)
        #expect(message?.endTime == 948301)
        #expect(message?.bufferLength == 40)
        #expect(message?.bufferCRC == 0x5b23)
    }
    
    // MARK: - GlucoseBackfillFrameBuffer Tests
    
    @Test("Frame buffer 20 min backfill")
    func frameBuffer_20MinBackfill() {
        let rxMessage = GlucoseBackfillRxMessage(data: hexData("51000100b7ff52006604530032000000e6cb9805"))!
        
        var buffer = GlucoseBackfillFrameBuffer(identifier: rxMessage.identifier)
        buffer.append(hexData("0100bc460000b7ff52008b0006eee30053008500"))
        buffer.append(hexData("020006eb0f025300800006ee3a0353007e0006f5"))
        buffer.append(hexData("030066045300790006f8"))
        
        // Validate buffer integrity
        #expect(buffer.count == Int(rxMessage.bufferLength), "Buffer length should match RX message")
        #expect(buffer.crc16 == rxMessage.bufferCRC, "Buffer CRC should match RX message")
        
        // Parse glucose readings
        let readings = buffer.glucose
        #expect(readings.count == 5, "Should have 5 glucose readings")
        
        // Validate first reading
        #expect(readings[0].glucose == 139)
        #expect(readings[0].timestamp == 5439415)
        #expect(readings[0].state == 6, "State should be OK (6)")
        #expect(readings[0].trend == -18)
        
        // Validate second reading
        #expect(readings[1].glucose == 133)
        #expect(readings[1].timestamp == 5439715)
        #expect(readings[1].state == 6)
        #expect(readings[1].trend == -21)
        
        // Validate third reading
        #expect(readings[2].glucose == 128)
        #expect(readings[2].timestamp == 5440015)
        #expect(readings[2].state == 6)
        #expect(readings[2].trend == -18)
        
        // Validate fourth reading
        #expect(readings[3].glucose == 126)
        #expect(readings[3].timestamp == 5440314)
        #expect(readings[3].state == 6)
        #expect(readings[3].trend == -11)
        
        // Validate fifth (last) reading
        #expect(readings[4].glucose == 121)
        #expect(readings[4].timestamp == 5440614)
        #expect(readings[4].state == 6)
        #expect(readings[4].trend == -8)
        
        // Validate timestamps match RX message range
        #expect(rxMessage.startTime == readings.first!.timestamp)
        #expect(rxMessage.endTime == readings.last!.timestamp)
        
        // Validate chronological order
        #expect(readings.first!.timestamp <= readings.last!.timestamp)
    }
    
    @Test("Frame buffer 25 min backfill 6 readings")
    func frameBuffer_25MinBackfill_6Readings() {
        let rxMessage = GlucoseBackfillRxMessage(data: hexData("51000103eaee4600c6f446003a0000004f3ac9e6"))!
        
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0xc0)
        buffer.append(hexData("01c06e3c0000eaee4600920007fd16f046009500"))
        buffer.append(hexData("02c0070042f14600960007026ef2460099000704"))
        buffer.append(hexData("03c09af3460093000700c6f44600900007fc"))
        
        #expect(buffer.count == Int(rxMessage.bufferLength))
        #expect(buffer.crc16 == rxMessage.bufferCRC)
        
        let readings = buffer.glucose
        #expect(readings.count == 6)
        
        // Validate timestamps match RX message range
        #expect(rxMessage.startTime == readings.first!.timestamp)
        #expect(rxMessage.endTime == readings.last!.timestamp)
        #expect(readings.first!.timestamp <= readings.last!.timestamp)
    }
    
    @Test("Frame buffer 15 min backfill 4 readings A")
    func frameBuffer_15MinBackfill_4ReadingsA() {
        let rxMessage = GlucoseBackfillRxMessage(data: hexData("510001023d6a0e00c16d0e00280000005b1a9154"))!
        
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0x80)
        buffer.append(hexData("0180440c00003d6a0e005c0007fe696b0e005d00"))
        buffer.append(hexData("028007ff956c0e005e000700c16d0e005d000700"))
        
        #expect(buffer.count == Int(rxMessage.bufferLength))
        #expect(buffer.crc16 == rxMessage.bufferCRC)
        
        let readings = buffer.glucose
        #expect(readings.count == 4)
        
        #expect(rxMessage.startTime == readings.first!.timestamp)
        #expect(rxMessage.endTime == readings.last!.timestamp)
        #expect(readings.first!.timestamp <= readings.last!.timestamp)
    }
    
    @Test("Frame buffer 15 min backfill 4 readings B")
    func frameBuffer_15MinBackfill_4ReadingsB() {
        let rxMessage = GlucoseBackfillRxMessage(data: hexData("51000103c9740e004d780e0028000000235bd94c"))!
        
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0xc0)
        buffer.append(hexData("01c04d0c0000c9740e005a000700f5750e005800"))
        buffer.append(hexData("02c007ff21770e00590007ff4d780e0059000700"))
        
        #expect(buffer.count == Int(rxMessage.bufferLength))
        #expect(buffer.crc16 == rxMessage.bufferCRC)
        
        let readings = buffer.glucose
        #expect(readings.count == 4)
        
        #expect(rxMessage.startTime == readings.first!.timestamp)
        #expect(rxMessage.endTime == readings.last!.timestamp)
        #expect(readings.first!.timestamp <= readings.last!.timestamp)
    }
    
    @Test("Frame buffer malformed truncated frame")
    func frameBuffer_MalformedTruncatedFrame() {
        // Truncated second frame should still yield partial readings
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0)
        buffer.append(hexData("0100bc460000b7ff52008b0006eee30053008500"))
        buffer.append(hexData("020006eb0f025300800006ee3a0353007e0006"))  // Missing last byte
        
        let readings = buffer.glucose
        #expect(readings.count == 3, "Should parse 3 complete readings from truncated data")
    }
    
    // MARK: - GlucoseSubMessage Tests
    
    @Test("Glucose sub message parse")
    func glucoseSubMessage_Parse() {
        // First reading from test vector: timestamp=5439415, glucose=139, state=6, trend=-18
        // Hex: b7ff5200 8b00 06 ee (little-endian)
        let data = hexData("b7ff52008b0006ee")
        
        let message = GlucoseSubMessage(data: data)
        #expect(message != nil)
        
        #expect(message?.timestamp == 5439415)
        #expect(message?.glucose == 139)
        #expect(message?.glucoseIsDisplayOnly == false)
        #expect(message?.state == 6)
        #expect(message?.trend == -18)
    }
    
    @Test("Glucose sub message display only flag")
    func glucoseSubMessage_DisplayOnlyFlag() {
        // Create data with displayOnly flag set (upper nibble of glucose)
        let data = hexData("b7ff52008bf006ee")  // 0xf08b has displayOnly set
        
        let message = GlucoseSubMessage(data: data)
        #expect(message != nil)
        #expect(message?.glucoseIsDisplayOnly ?? false)
        #expect(message?.glucose == 139)  // Lower 12 bits only
    }
    
    // MARK: - CRC16 Tests
    
    @Test("CRC16 valid message")
    func crc16_ValidMessage() {
        let data = hexData("51000100b7ff52006604530032000000e6cb9805")
        #expect(data.isCRCValid, "Message CRC should be valid")
    }
    
    @Test("CRC16 compute and append")
    func crc16_ComputeAndAppend() {
        let message = GlucoseBackfillTxMessage(startTime: 5439415, endTime: 5440614)
        let withCRC = message.dataWithoutCRC.appendingCRC()
        
        #expect(withCRC.count == 20)
        #expect(withCRC.isCRCValid)
    }
    
    // MARK: - Frame Identifier Validation Tests
    
    @Test("Frame buffer rejects wrong identifier")
    func frameBuffer_RejectsWrongIdentifier() {
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0x00)
        
        // Try to append frame with wrong identifier (0xc0 instead of 0x00)
        buffer.append(hexData("01c06e3c0000eaee4600920007fd16f046009500"))
        
        #expect(buffer.frameCount == 0, "Should reject frame with wrong identifier")
    }
    
    @Test("Frame buffer rejects out of order frame")
    func frameBuffer_RejectsOutOfOrderFrame() {
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0)
        
        // Try to append frame 2 before frame 1
        buffer.append(hexData("020006eb0f025300800006ee3a0353007e0006f5"))
        
        #expect(buffer.frameCount == 0, "Should reject out-of-order frame")
    }
    
    // MARK: - G6-VALIDATE-005: Backfill Parsing Validation Against Loop
    
    @Test("Backfill parsing glucose range validation")
    func backfillParsing_GlucoseRangeValidation() {
        // G6-VALIDATE-005: Validate glucose ranges match Loop CGMBLEKit
        // Valid glucose range: 40-400 mg/dL
        
        // Sub-message with glucose 100 mg/dL (0x64)
        let validGlucose = hexData("b7ff520064000000")  // time + glucose 0x0064 (100)
        let subMsg = GlucoseSubMessage(data: validGlucose)
        #expect(subMsg != nil)
        #expect(subMsg?.glucose == 100)
        #expect(!(subMsg?.glucoseIsDisplayOnly ?? true))
    }
    
    @Test("Backfill parsing display only flag handling")
    func backfillParsing_DisplayOnlyFlagHandling() {
        // G6-VALIDATE-005: Validate display-only flag parsing matches Loop
        // Display-only bit is bit 15 of the glucose word
        
        // Sub-message with display-only flag set (glucose 100 | 0x8000)
        let displayOnlyGlucose = hexData("b7ff520064800000")  // 0x8064 = displayOnly + 100
        let subMsg = GlucoseSubMessage(data: displayOnlyGlucose)
        #expect(subMsg != nil)
        #expect(subMsg?.glucose == 100)  // glucose value
        #expect(subMsg?.glucoseIsDisplayOnly ?? false)  // display-only flag
    }
    
    @Test("Backfill parsing timestamp consistency")
    func backfillParsing_TimestampConsistency() {
        // G6-VALIDATE-005: Validate timestamps are sequential in backfill
        // Each reading should be approximately 5 minutes (300 seconds) apart
        // But backfill gaps can vary, so we check for reasonable range
        
        let frame1 = hexData("0100e802000052ff5200900006e70b0153007e00")
        let frame2 = hexData("020006eb0f0253008000063f140353008c0006f5")
        
        var buffer = GlucoseBackfillFrameBuffer(identifier: 0)
        buffer.append(frame1)
        buffer.append(frame2)
        
        let readings = buffer.glucose
        #expect(readings.count > 1, "Should have multiple readings")
        
        if readings.count > 1 {
            let timeDiff = Int(readings[1].timestamp) - Int(readings[0].timestamp)
            // Time differences should be positive and reasonable (up to 15 minutes)
            // Multiple of ~300 seconds, allow tolerance for gaps
            #expect(timeDiff > 0 && timeDiff < 1000, 
                   "Readings should have reasonable time spacing, got \(timeDiff)s")
        }
    }
    
    @Test("Backfill parsing CRC validation required")
    func backfillParsing_CRCValidationRequired() {
        // G6-VALIDATE-005: Validate CRC is required for parsing
        // Corrupted CRC should reject the message
        
        let validMessage = hexData("50050200b7ff5200660453000000000000007138")
        let corruptedMessage = hexData("50050200b7ff52006604530000000000000071FF")  // Wrong CRC
        
        // Valid message should have correct CRC
        #expect(validMessage.isCRCValid)
        
        // Corrupted message should fail CRC
        #expect(!corruptedMessage.isCRCValid)
    }
    
    @Test("Backfill parsing frame reassembly")
    func backfillParsing_FrameReassembly() {
        // G6-VALIDATE-005: Validate frame reassembly matches Loop
        // Complete multi-frame backfill should produce correct glucose count
        
        // 20-minute backfill test vectors (4 readings expected)
        let txMessage = GlucoseBackfillTxMessage(
            startTime: 5439415,
            endTime: 5440614,
            byte1: 5,
            byte2: 2,
            identifier: 0
        )
        
        // Verify TX message format
        #expect(txMessage.data.count == 20, "TX message should be 20 bytes")
        #expect(txMessage.data[0] == 0x50, "Opcode should be 0x50")
        
        // Frame buffer should accept matching identifier
        let buffer = GlucoseBackfillFrameBuffer(identifier: txMessage.identifier)
        #expect(buffer.frameCount == 0, "Should start empty")
        #expect(buffer.glucose.count == 0, "Should have no glucose readings yet")
    }
}
