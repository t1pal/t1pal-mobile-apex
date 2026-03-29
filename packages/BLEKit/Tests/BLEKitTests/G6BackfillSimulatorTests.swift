// SPDX-License-Identifier: MIT
//
// G6BackfillSimulatorTests.swift
// BLEKit Tests
//
// Tests for G6 backfill request handling.
// Trace: PRD-007 REQ-SIM-006

import Testing
import Foundation
@testable import BLEKit

// MARK: - BackfillRecord Tests

@Suite("BackfillRecord Tests")
struct BackfillRecordTests {
    
    @Test("Record serializes to correct size")
    func recordSize() {
        let record = BackfillRecord(glucose: 120, trend: 2, timestamp: 1000, quality: 95)
        let bytes = record.toBytes()
        
        #expect(bytes.count == BackfillRecord.size)
        #expect(BackfillRecord.size == 8)
    }
    
    @Test("Record round-trips through serialization")
    func recordRoundTrip() {
        let original = BackfillRecord(glucose: 185, trend: -3, timestamp: 123456, quality: 88)
        let bytes = original.toBytes()
        let parsed = BackfillRecord.fromBytes(bytes)
        
        #expect(parsed != nil)
        #expect(parsed?.glucose == 185)
        #expect(parsed?.trend == -3)
        #expect(parsed?.timestamp == 123456)
        #expect(parsed?.quality == 88)
    }
    
    @Test("Record handles edge values")
    func edgeValues() {
        // Max glucose
        let highGlucose = BackfillRecord(glucose: 400, trend: 8, timestamp: UInt32.max, quality: 100)
        let highBytes = highGlucose.toBytes()
        let parsedHigh = BackfillRecord.fromBytes(highBytes)
        #expect(parsedHigh?.glucose == 400)
        #expect(parsedHigh?.trend == 8)
        
        // Min glucose
        let lowGlucose = BackfillRecord(glucose: 40, trend: -8, timestamp: 0, quality: 0)
        let lowBytes = lowGlucose.toBytes()
        let parsedLow = BackfillRecord.fromBytes(lowBytes)
        #expect(parsedLow?.glucose == 40)
        #expect(parsedLow?.trend == -8)
    }
    
    @Test("Record parsing fails for short data")
    func shortDataFails() {
        let shortData = Data([0x01, 0x02, 0x03])  // Too short
        let parsed = BackfillRecord.fromBytes(shortData)
        #expect(parsed == nil)
    }
}

// MARK: - BackfillRequest Tests

@Suite("BackfillRequest Tests")
struct BackfillRequestTests {
    
    @Test("Request parses valid BackfillTx message")
    func parseValidRequest() {
        // Build BackfillTx: opcode + startTime + endTime
        var data = Data()
        data.append(G6BackfillOpcode.backfillTx.rawValue)  // 0x50
        // Start time: 1000 (little endian)
        data.append(0xE8); data.append(0x03); data.append(0x00); data.append(0x00)
        // End time: 2000 (little endian)
        data.append(0xD0); data.append(0x07); data.append(0x00); data.append(0x00)
        
        let request = BackfillRequest.parse(data)
        
        #expect(request != nil)
        #expect(request?.startTime == 1000)
        #expect(request?.endTime == 2000)
    }
    
    @Test("Request fails for wrong opcode")
    func wrongOpcodeFails() {
        var data = Data()
        data.append(0x30)  // Wrong opcode (GlucoseTx)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let request = BackfillRequest.parse(data)
        #expect(request == nil)
    }
    
    @Test("Request fails for short message")
    func shortMessageFails() {
        let data = Data([0x50, 0x00, 0x00])  // Too short
        let request = BackfillRequest.parse(data)
        #expect(request == nil)
    }
}

// MARK: - StaticBackfillProvider Tests

@Suite("StaticBackfillProvider Tests")
struct StaticBackfillProviderTests {
    
    @Test("Provider returns records in range")
    func recordsInRange() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
            BackfillRecord(glucose: 130, trend: 1, timestamp: 400, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        
        let result = provider.getBackfillRecords(startTime: 150, endTime: 350)
        
        #expect(result.count == 2)
        #expect(result[0].timestamp == 200)
        #expect(result[1].timestamp == 300)
    }
    
    @Test("Provider returns empty for out of range")
    func outOfRange() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        
        let result = provider.getBackfillRecords(startTime: 500, endTime: 600)
        
        #expect(result.isEmpty)
    }
    
    @Test("Provider tracks oldest and newest")
    func oldestNewest() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        
        #expect(provider.oldestAvailableTime() == 100)
        #expect(provider.newestAvailableTime() == 300)
    }
    
    @Test("Provider handles empty records")
    func emptyRecords() {
        let provider = StaticBackfillProvider(records: [])
        
        #expect(provider.oldestAvailableTime() == nil)
        #expect(provider.newestAvailableTime() == nil)
        #expect(provider.getBackfillRecords(startTime: 0, endTime: 1000).isEmpty)
    }
    
    @Test("Provider can add records")
    func addRecords() {
        let provider = StaticBackfillProvider()
        #expect(provider.count == 0)
        
        provider.addRecord(BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100))
        #expect(provider.count == 1)
        
        provider.addRecords([
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
        ])
        #expect(provider.count == 3)
    }
    
    @Test("Provider can clear records")
    func clearRecords() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        #expect(provider.count == 2)
        
        provider.clear()
        #expect(provider.count == 0)
    }
}

// MARK: - GeneratedBackfillProvider Tests

@Suite("GeneratedBackfillProvider Tests")
struct GeneratedBackfillProviderTests {
    
    @Test("Provider generates records at intervals")
    func generatesAtIntervals() {
        let glucoseProvider = StaticGlucoseProvider(glucose: 120, trend: 1)
        let provider = GeneratedBackfillProvider(
            glucoseProvider: glucoseProvider,
            interval: 300  // 5 minutes
        )
        
        // Request 15 minutes of data
        let records = provider.getBackfillRecords(startTime: 0, endTime: 900)
        
        // Should have 4 records: 0, 300, 600, 900
        #expect(records.count == 4)
        #expect(records[0].timestamp == 0)
        #expect(records[1].timestamp == 300)
        #expect(records[2].timestamp == 600)
        #expect(records[3].timestamp == 900)
    }
    
    @Test("Provider uses glucose from provider")
    func usesGlucoseProvider() {
        let glucoseProvider = StaticGlucoseProvider(glucose: 185, trend: -2)
        let provider = GeneratedBackfillProvider(
            glucoseProvider: glucoseProvider,
            interval: 300
        )
        
        let records = provider.getBackfillRecords(startTime: 0, endTime: 300)
        
        #expect(records.allSatisfy { $0.glucose == 185 })
        #expect(records.allSatisfy { $0.trend == -2 })
    }
    
    @Test("Provider aligns to interval boundaries")
    func alignsToInterval() {
        let glucoseProvider = StaticGlucoseProvider(glucose: 100)
        let provider = GeneratedBackfillProvider(
            glucoseProvider: glucoseProvider,
            interval: 300
        )
        
        // Request starting at 150 (not aligned)
        let records = provider.getBackfillRecords(startTime: 150, endTime: 700)
        
        // Should align to 300 and 600
        #expect(records.count == 2)
        #expect(records[0].timestamp == 300)
        #expect(records[1].timestamp == 600)
    }
}

// MARK: - G6BackfillSimulator Tests

@Suite("G6BackfillSimulator Tests")
struct G6BackfillSimulatorTests {
    
    @Test("Simulator processes valid backfill request")
    func processValidRequest() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        // Build request for all records
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(0x00); request.append(0x00); request.append(0x00); request.append(0x00)  // start: 0
        request.append(0xF4); request.append(0x01); request.append(0x00); request.append(0x00)  // end: 500
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(let header, let packets) = result {
            #expect(header[0] == G6BackfillOpcode.backfillRx.rawValue)
            #expect(header[1] == G6BackfillStatus.available.rawValue)
            #expect(packets.count > 0)
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
    
    @Test("Simulator returns no data for empty range")
    func noDataResponse() {
        let provider = StaticBackfillProvider(records: [])
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(0x00); request.append(0x00); request.append(0x00); request.append(0x00)
        request.append(0x00); request.append(0x01); request.append(0x00); request.append(0x00)
        
        let result = simulator.processMessage(request)
        
        if case .noData(let response) = result {
            #expect(response[0] == G6BackfillOpcode.backfillRx.rawValue)
            #expect(response[1] == G6BackfillStatus.noData.rawValue)
        } else {
            Issue.record("Expected noData result")
        }
    }
    
    @Test("Simulator rejects invalid opcode")
    func rejectsInvalidOpcode() {
        let provider = StaticBackfillProvider()
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        let result = simulator.processMessage(Data([0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        
        if case .invalidMessage = result {
            // Expected
        } else {
            Issue.record("Expected invalidMessage result")
        }
    }
    
    @Test("Simulator rejects empty message")
    func rejectsEmptyMessage() {
        let provider = StaticBackfillProvider()
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        let result = simulator.processMessage(Data())
        
        if case .invalidMessage = result {
            // Expected
        } else {
            Issue.record("Expected invalidMessage result")
        }
    }
    
    @Test("Simulator tracks request count")
    func tracksRequestCount() {
        let records = [BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100)]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        #expect(simulator.requestCount == 0)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])
        
        _ = simulator.processMessage(request)
        #expect(simulator.requestCount == 1)
        
        _ = simulator.processMessage(request)
        #expect(simulator.requestCount == 2)
    }
    
    @Test("Simulator tracks records sent")
    func tracksRecordsSent() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0xF4, 0x01, 0x00, 0x00])  // 0-500
        
        _ = simulator.processMessage(request)
        #expect(simulator.recordsSent == 3)
    }
    
    @Test("Simulator can reset statistics")
    func resetStatistics() {
        let records = [BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100)]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])
        
        _ = simulator.processMessage(request)
        #expect(simulator.requestCount == 1)
        #expect(simulator.recordsSent == 1)
        
        simulator.resetStatistics()
        #expect(simulator.requestCount == 0)
        #expect(simulator.recordsSent == 0)
    }
    
    @Test("Simulator respects max records per packet")
    func maxRecordsPerPacket() {
        var records: [BackfillRecord] = []
        for i in 0..<10 {
            records.append(BackfillRecord(glucose: UInt16(100 + i * 10), trend: 0, timestamp: UInt32(i * 300), quality: 100))
        }
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider, maxRecordsPerPacket: 3)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00])  // 0-65535
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(_, let packets) = result {
            // 10 records / 3 per packet = 4 packets (3+3+3+1)
            #expect(packets.count == 4)
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
    
    @Test("Data packets have correct structure")
    func dataPacketStructure() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider, maxRecordsPerPacket: 2)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00])
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(_, let packets) = result {
            #expect(packets.count == 1)
            let packet = packets[0]
            #expect(packet[0] == G6BackfillOpcode.backfillDataRx.rawValue)  // Opcode
            #expect(packet[1] == 0)  // Packet number
            #expect(packet[2] == 2)  // Records in packet
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
    
    @Test("Header response has correct structure")
    func headerStructure() {
        let records = [
            BackfillRecord(glucose: 100, trend: 0, timestamp: 100, quality: 100),
            BackfillRecord(glucose: 110, trend: 1, timestamp: 200, quality: 100),
            BackfillRecord(glucose: 120, trend: 2, timestamp: 300, quality: 100),
        ]
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider, maxRecordsPerPacket: 2)
        
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        // Start: 50, End: 350
        request.append(0x32); request.append(0x00); request.append(0x00); request.append(0x00)
        request.append(0x5E); request.append(0x01); request.append(0x00); request.append(0x00)
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(let header, let packets) = result {
            #expect(header.count == 13)
            #expect(header[0] == G6BackfillOpcode.backfillRx.rawValue)
            #expect(header[1] == G6BackfillStatus.available.rawValue)
            // Record count: 3 (little endian)
            #expect(header[2] == 3)
            #expect(header[3] == 0)
            // Packet count: 2 (3 records / 2 per packet)
            #expect(header[4] == 2)
            #expect(packets.count == 2)
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
}

// MARK: - Integration Tests

@Suite("Backfill Integration Tests")
struct BackfillIntegrationTests {
    
    @Test("End-to-end backfill flow")
    func endToEndFlow() {
        // Create historical data
        var records: [BackfillRecord] = []
        for hour in 0..<24 {
            records.append(BackfillRecord(
                glucose: UInt16(100 + hour * 5),
                trend: Int8(hour % 5 - 2),
                timestamp: UInt32(hour * 3600),
                quality: 100
            ))
        }
        
        let provider = StaticBackfillProvider(records: records)
        let simulator = G6BackfillSimulator(backfillProvider: provider, maxRecordsPerPacket: 4)
        
        // Request 12 hours of data (12 records)
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        // Start: 0
        request.append(0x00); request.append(0x00); request.append(0x00); request.append(0x00)
        // End: 12 * 3600 = 43200
        request.append(0xE0); request.append(0xA8); request.append(0x00); request.append(0x00)
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(let header, let packets) = result {
            // Should have 13 records (0-12 inclusive)
            let recordCount = Int(header[2]) | (Int(header[3]) << 8)
            #expect(recordCount == 13)
            
            // Should have 4 packets (13 / 4 = 4)
            #expect(packets.count == 4)
            
            // Verify all records can be parsed from packets
            var parsedRecords: [BackfillRecord] = []
            for packet in packets {
                let recordsInPacket = Int(packet[2])
                for i in 0..<recordsInPacket {
                    if let record = BackfillRecord.fromBytes(packet, offset: 3 + i * BackfillRecord.size) {
                        parsedRecords.append(record)
                    }
                }
            }
            
            #expect(parsedRecords.count == 13)
            #expect(parsedRecords.first?.glucose == 100)
            #expect(parsedRecords.last?.glucose == 160)
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
    
    @Test("Backfill with generated provider")
    func generatedProviderFlow() {
        let glucoseProvider = StaticGlucoseProvider(glucose: 120, trend: 1)
        let backfillProvider = GeneratedBackfillProvider(
            glucoseProvider: glucoseProvider,
            interval: 300,
            historyDuration: 3600
        )
        let simulator = G6BackfillSimulator(backfillProvider: backfillProvider)
        
        // Request 30 minutes of data
        var request = Data()
        request.append(G6BackfillOpcode.backfillTx.rawValue)
        request.append(0x00); request.append(0x00); request.append(0x00); request.append(0x00)  // Start: 0
        request.append(0x08); request.append(0x07); request.append(0x00); request.append(0x00)  // End: 1800
        
        let result = simulator.processMessage(request)
        
        if case .sendBackfill(let header, _) = result {
            let recordCount = Int(header[2]) | (Int(header[3]) << 8)
            // 1800 / 300 + 1 = 7 records at intervals 0, 300, 600, 900, 1200, 1500, 1800
            #expect(recordCount == 7)
        } else {
            Issue.record("Expected sendBackfill result")
        }
    }
}
