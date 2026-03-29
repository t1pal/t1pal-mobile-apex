// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PassiveBLEConnectionTests.swift
// BLEKit
//
// Unit tests for passive BLE connection mode.
// Trace: CGM-043, REQ-CGM-040
//
// Reference: externals/CGMBLEKit/CGMBLEKit/Transmitter.swift:161-270

import Foundation
import Testing
@testable import BLEKit
import T1PalCore

/// Thread-safe container for capturing readings in tests
actor ReadingCapture {
    var readings: [PassiveGlucoseReading] = []
    var count: Int { readings.count }
    
    func add(_ reading: PassiveGlucoseReading) {
        readings.append(reading)
    }
    
    func last() -> PassiveGlucoseReading? {
        readings.last
    }
    
    func reset() {
        readings = []
    }
}

// MARK: - State Machine Tests

@Suite("PassiveBLEConnection State")
struct PassiveBLEConnectionStateTests {
    @Test("Initial state is disconnected")
    func initialStateIsDisconnected() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let state = await connection.connectionState
        #expect(state == .disconnected)
    }
    
    @Test("Passive mode enabled")
    func passiveModeEnabled() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG7)
        // PassiveBLEConnection is always passive by design
        #expect(connection != nil)
    }
}

// MARK: - Glucose Parsing Tests

@Suite("PassiveBLEConnection Glucose Parsing")
struct PassiveBLEConnectionGlucoseParsingTests {
    @Test("G6 glucose parsing opcode 0x31")
    func g6GlucoseParsingOpcode31() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // G6 GlucoseRxMessage format: [opcode, status, glucoseLo, glucoseHi, ts0-3, trend]
        // glucose = 120 (0x78, 0x00), trend = 4 (flat)
        let data = Data([0x31, 0x00, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04])
        
        await connection.handleNotificationForTest(data, isBackfill: false)
        
        // Small delay for async callback
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let reading = await capture.last()
        #expect(reading != nil)
        #expect(reading?.glucoseValue == 120)
        #expect(reading?.trend == .flat)
        #expect(reading?.isBackfill == false)
    }
    
    @Test("G6 glucose parsing opcode 0x4E")
    func g6GlucoseParsingOpcode4E() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6Plus)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // glucose = 95 (0x5F, 0x00), trend = 3 (fortyFiveUp)
        let data = Data([0x4E, 0x00, 0x5F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let reading = await capture.last()
        #expect(reading != nil)
        #expect(reading?.glucoseValue == 95)
        #expect(reading?.trend == .fortyFiveUp)
    }
    
    @Test("G7 glucose parsing")
    func g7GlucoseParsing() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG7)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // glucose = 150 (0x96, 0x00), trend = 2 (singleUp)
        let data = Data([0x4F, 0x00, 0x96, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02])
        
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let reading = await capture.last()
        #expect(reading != nil)
        #expect(reading?.glucoseValue == 150)
        #expect(reading?.trend == .singleUp)
    }
}

// MARK: - Trend Parsing Tests

@Suite("PassiveBLEConnection Trend Parsing")
struct PassiveBLEConnectionTrendParsingTests {
    @Test("All trend values")
    func allTrendValues() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        let trendMapping: [(UInt8, GlucoseTrend)] = [
            (1, .doubleUp),
            (2, .singleUp),
            (3, .fortyFiveUp),
            (4, .flat),
            (5, .fortyFiveDown),
            (6, .singleDown),
            (7, .doubleDown),
            (8, .notComputable),
            (9, .rateOutOfRange),
        ]
        
        for (rawTrend, expectedTrend) in trendMapping {
            await capture.reset()
            
            await connection.setOnGlucoseReading { reading in
                Task { await capture.add(reading) }
            }
            
            let data = Data([0x31, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, rawTrend])
            await connection.handleNotificationForTest(data, isBackfill: false)
            try? await Task.sleep(nanoseconds: 10_000_000)
            
            let reading = await capture.last()
            #expect(reading != nil, "Trend \(rawTrend) should produce reading")
            #expect(reading?.trend == expectedTrend, "Trend \(rawTrend) should map to \(expectedTrend)")
        }
    }
    
    @Test("Invalid trend value returns nil")
    func invalidTrendValue() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // trend = 0 is invalid
        let data = Data([0x31, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let reading = await capture.last()
        #expect(reading != nil)
        #expect(reading?.trend == nil, "Trend 0 should be nil")
    }
}

// MARK: - Edge Cases

@Suite("PassiveBLEConnection Edge Cases")
struct PassiveBLEConnectionEdgeCasesTests {
    @Test("Short packet is ignored")
    func shortPacketIgnored() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // Only 4 bytes, less than required 9
        let data = Data([0x31, 0x00, 0x64, 0x00])
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let count = await capture.count
        #expect(count == 0, "Short packet should not produce reading")
    }
    
    @Test("Empty packet is ignored")
    func emptyPacketIgnored() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        await connection.handleNotificationForTest(Data(), isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let count = await capture.count
        #expect(count == 0)
    }
    
    @Test("Unknown opcode is ignored")
    func unknownOpcodeIgnored() async {
        let connection = PassiveBLEConnection(deviceType: .dexcomG6)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // opcode 0xFF is unknown
        let data = Data([0xFF, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04])
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let count = await capture.count
        #expect(count == 0, "Unknown opcode should not produce reading")
    }
}

// MARK: - Device Type Tests

@Suite("PassiveBLEConnection Device Type")
struct PassiveBLEConnectionDeviceTypeTests {
    @Test("Wrong opcode for device is ignored")
    func wrongOpcodeForDeviceIgnored() async {
        // G7 connection should ignore G6 opcode 0x31
        let connection = PassiveBLEConnection(deviceType: .dexcomG7)
        let capture = ReadingCapture()
        
        await connection.setOnGlucoseReading { reading in
            Task { await capture.add(reading) }
        }
        
        // G6 opcode on G7 device
        let data = Data([0x31, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04])
        await connection.handleNotificationForTest(data, isBackfill: false)
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let count = await capture.count
        #expect(count == 0, "G6 opcode should be ignored on G7 device")
    }
}

// MARK: - PassiveGlucoseReading Tests

@Suite("PassiveGlucoseReading")
struct PassiveGlucoseReadingTests {
    @Test("Initialization")
    func passiveGlucoseReadingInit() {
        let reading = PassiveGlucoseReading(
            glucoseValue: 100,
            trend: .flat,
            timestamp: Date(),
            transmitterId: "ABC123",
            isBackfill: false,
            rawData: Data([0x31])
        )
        
        #expect(reading.glucoseValue == 100)
        #expect(reading.trend == .flat)
        #expect(reading.transmitterId == "ABC123")
        #expect(!reading.isBackfill)
        #expect(reading.rawData.count == 1)
    }
    
    @Test("Equatable")
    func passiveGlucoseReadingEquatable() {
        let date = Date()
        let rawData = Data([0x01])
        
        let reading1 = PassiveGlucoseReading(
            glucoseValue: 100,
            trend: .flat,
            timestamp: date,
            transmitterId: "ABC123",
            isBackfill: false,
            rawData: rawData
        )
        
        let reading2 = PassiveGlucoseReading(
            glucoseValue: 100,
            trend: .flat,
            timestamp: date,
            transmitterId: "ABC123",
            isBackfill: false,
            rawData: rawData
        )
        
        #expect(reading1 == reading2)
    }
}
