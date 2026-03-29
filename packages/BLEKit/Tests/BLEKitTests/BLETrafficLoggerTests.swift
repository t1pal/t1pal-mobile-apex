// SPDX-License-Identifier: MIT
//
// BLETrafficLoggerTests.swift
// BLEKit Tests
//
// Tests for BLE traffic logging functionality.
// Trace: PRD-007 REQ-SIM-008

import Testing
import Foundation
@testable import BLEKit

// MARK: - Traffic Entry Tests

@Suite("TrafficEntry Tests")
struct TrafficEntryTests {
    
    @Test("Entry captures opcode from first byte")
    func capturesOpcode() {
        let data = Data([0x30, 0x01, 0x02, 0x03])
        let entry = TrafficEntry(direction: .outgoing, data: data)
        
        #expect(entry.opcode == 0x30)
    }
    
    @Test("Entry provides hex string")
    func hexString() {
        let data = Data([0x01, 0x02, 0xAB, 0xCD])
        let entry = TrafficEntry(direction: .incoming, data: data)
        
        #expect(entry.hexString == "01 02 AB CD")
    }
    
    @Test("Entry tracks size")
    func tracksSize() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let entry = TrafficEntry(direction: .outgoing, data: data)
        
        #expect(entry.size == 5)
    }
    
    @Test("Entry has unique ID")
    func uniqueId() {
        let data = Data([0x01])
        let entry1 = TrafficEntry(direction: .outgoing, data: data)
        let entry2 = TrafficEntry(direction: .outgoing, data: data)
        
        #expect(entry1.id != entry2.id)
    }
    
    @Test("Entry short description includes direction")
    func shortDescription() {
        let outgoing = TrafficEntry(direction: .outgoing, data: Data([0x30]))
        let incoming = TrafficEntry(direction: .incoming, data: Data([0x31]))
        
        #expect(outgoing.shortDescription.contains("→"))
        #expect(incoming.shortDescription.contains("←"))
    }
    
    @Test("Entry is codable")
    func codable() throws {
        let original = TrafficEntry(
            direction: .outgoing,
            data: Data([0x30, 0x01, 0x02]),
            characteristic: "2A37",
            note: "Test note"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrafficEntry.self, from: data)
        
        #expect(decoded.opcode == original.opcode)
        #expect(decoded.direction == original.direction)
        #expect(decoded.data == original.data)
        #expect(decoded.note == original.note)
    }
}

// MARK: - Traffic Filter Tests

@Suite("TrafficFilter Tests")
struct TrafficFilterTests {
    
    @Test("Empty filter matches all")
    func emptyMatchesAll() {
        let filter = TrafficFilter()
        
        let entry1 = TrafficEntry(direction: .outgoing, data: Data([0x01]))
        let entry2 = TrafficEntry(direction: .incoming, data: Data([0x02]))
        
        #expect(filter.matches(entry1))
        #expect(filter.matches(entry2))
    }
    
    @Test("Direction filter")
    func directionFilter() {
        let filter = TrafficFilter.direction(.outgoing)
        
        let outgoing = TrafficEntry(direction: .outgoing, data: Data([0x01]))
        let incoming = TrafficEntry(direction: .incoming, data: Data([0x02]))
        
        #expect(filter.matches(outgoing))
        #expect(!filter.matches(incoming))
    }
    
    @Test("Opcode include filter")
    func opcodeIncludeFilter() {
        let filter = TrafficFilter.opcodes(0x30, 0x31)
        
        let match1 = TrafficEntry(direction: .outgoing, data: Data([0x30]))
        let match2 = TrafficEntry(direction: .outgoing, data: Data([0x31]))
        let noMatch = TrafficEntry(direction: .outgoing, data: Data([0x50]))
        
        #expect(filter.matches(match1))
        #expect(filter.matches(match2))
        #expect(!filter.matches(noMatch))
    }
    
    @Test("Opcode exclude filter")
    func opcodeExcludeFilter() {
        var filter = TrafficFilter()
        filter.excludeOpcodes = [0x00, 0xFF]
        
        let excluded1 = TrafficEntry(direction: .outgoing, data: Data([0x00]))
        let excluded2 = TrafficEntry(direction: .outgoing, data: Data([0xFF]))
        let included = TrafficEntry(direction: .outgoing, data: Data([0x30]))
        
        #expect(!filter.matches(excluded1))
        #expect(!filter.matches(excluded2))
        #expect(filter.matches(included))
    }
    
    @Test("Time range filter")
    func timeRangeFilter() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let later = now.addingTimeInterval(3600)
        
        let filter = TrafficFilter.timeRange(start: earlier, end: later)
        
        let inRange = TrafficEntry(timestamp: now, direction: .outgoing, data: Data([0x01]))
        let tooEarly = TrafficEntry(timestamp: earlier.addingTimeInterval(-1), direction: .outgoing, data: Data([0x01]))
        let tooLate = TrafficEntry(timestamp: later.addingTimeInterval(1), direction: .outgoing, data: Data([0x01]))
        
        #expect(filter.matches(inRange))
        #expect(!filter.matches(tooEarly))
        #expect(!filter.matches(tooLate))
    }
    
    @Test("Size filter")
    func sizeFilter() {
        var filter = TrafficFilter()
        filter.minSize = 3
        filter.maxSize = 10
        
        let tooSmall = TrafficEntry(direction: .outgoing, data: Data([0x01, 0x02]))
        let justRight = TrafficEntry(direction: .outgoing, data: Data([0x01, 0x02, 0x03, 0x04, 0x05]))
        let tooBig = TrafficEntry(direction: .outgoing, data: Data(repeating: 0x00, count: 15))
        
        #expect(!filter.matches(tooSmall))
        #expect(filter.matches(justRight))
        #expect(!filter.matches(tooBig))
    }
    
    @Test("Characteristic filter")
    func characteristicFilter() {
        var filter = TrafficFilter()
        filter.characteristic = "2A37"
        
        let match = TrafficEntry(direction: .outgoing, data: Data([0x01]), characteristic: "2A37")
        let noMatch = TrafficEntry(direction: .outgoing, data: Data([0x01]), characteristic: "2A38")
        let noChar = TrafficEntry(direction: .outgoing, data: Data([0x01]))
        
        #expect(filter.matches(match))
        #expect(!filter.matches(noMatch))
        #expect(!filter.matches(noChar))
    }
}

// MARK: - BLE Traffic Logger Tests

@Suite("BLETrafficLogger Tests")
struct BLETrafficLoggerTests {
    
    @Test("Logger starts empty")
    func startsEmpty() {
        let logger = BLETrafficLogger()
        
        #expect(logger.count == 0)
        #expect(logger.entries.isEmpty)
    }
    
    @Test("Logger logs entries")
    func logsEntries() {
        let logger = BLETrafficLogger()
        
        logger.log(direction: .outgoing, data: Data([0x30, 0x01]))
        logger.log(direction: .incoming, data: Data([0x31, 0x02, 0x03]))
        
        #expect(logger.count == 2)
    }
    
    @Test("Logger convenience methods")
    func convenienceMethods() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x01]))
        logger.logIncoming(Data([0x02]))
        
        #expect(logger.count == 2)
        #expect(logger.entries[0].direction == .outgoing)
        #expect(logger.entries[1].direction == .incoming)
    }
    
    @Test("Logger respects max entries")
    func maxEntries() {
        let logger = BLETrafficLogger(maxEntries: 3)
        
        for i in 0..<10 {
            logger.log(direction: .outgoing, data: Data([UInt8(i)]))
        }
        
        #expect(logger.count == 3)
        // Should have last 3 entries (7, 8, 9)
        #expect(logger.entries[0].opcode == 7)
        #expect(logger.entries[1].opcode == 8)
        #expect(logger.entries[2].opcode == 9)
    }
    
    @Test("Logger can be disabled")
    func canBeDisabled() {
        let logger = BLETrafficLogger()
        logger.isEnabled = false
        
        let entry = logger.log(direction: .outgoing, data: Data([0x01]))
        
        #expect(entry == nil)
        #expect(logger.count == 0)
    }
    
    @Test("Logger ignores empty data")
    func ignoresEmptyData() {
        let logger = BLETrafficLogger()
        
        let entry = logger.log(direction: .outgoing, data: Data())
        
        #expect(entry == nil)
        #expect(logger.count == 0)
    }
    
    @Test("Logger filters by direction")
    func filtersByDirection() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x01]))
        logger.logOutgoing(Data([0x02]))
        logger.logIncoming(Data([0x03]))
        
        let outgoing = logger.entries(direction: .outgoing)
        let incoming = logger.entries(direction: .incoming)
        
        #expect(outgoing.count == 2)
        #expect(incoming.count == 1)
    }
    
    @Test("Logger filters by opcode")
    func filtersByOpcode() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x30, 0x01]))
        logger.logOutgoing(Data([0x31, 0x02]))
        logger.logOutgoing(Data([0x30, 0x03]))
        
        let filtered = logger.entries(opcode: 0x30)
        
        #expect(filtered.count == 2)
    }
    
    @Test("Logger clears entries")
    func clearsEntries() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x01]))
        logger.logOutgoing(Data([0x02]))
        #expect(logger.count == 2)
        
        logger.clear()
        #expect(logger.count == 0)
    }
    
    @Test("Logger gets last N entries")
    func lastNEntries() {
        let logger = BLETrafficLogger()
        
        for i in 0..<10 {
            logger.log(direction: .outgoing, data: Data([UInt8(i)]))
        }
        
        let last3 = logger.lastEntries(3)
        
        #expect(last3.count == 3)
        #expect(last3[0].opcode == 7)
        #expect(last3[1].opcode == 8)
        #expect(last3[2].opcode == 9)
    }
    
    @Test("Logger finds entries containing pattern")
    func findsPattern() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x01, 0x02, 0x03, 0x04]))
        logger.logOutgoing(Data([0xAB, 0xCD, 0xEF]))
        logger.logOutgoing(Data([0x00, 0x02, 0x03, 0x00]))
        
        let found = logger.find(containing: Data([0x02, 0x03]))
        
        #expect(found.count == 2)
    }
}

// MARK: - Statistics Tests

@Suite("TrafficStatistics Tests")
struct TrafficStatisticsTests {
    
    @Test("Statistics counts correctly")
    func countsCorrectly() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x30, 0x01, 0x02]))  // 3 bytes
        logger.logOutgoing(Data([0x31, 0x01]))        // 2 bytes
        logger.logIncoming(Data([0x32, 0x01, 0x02, 0x03, 0x04]))  // 5 bytes
        
        let stats = logger.statistics
        
        #expect(stats.totalEntries == 3)
        #expect(stats.outgoingCount == 2)
        #expect(stats.incomingCount == 1)
        #expect(stats.bytesSent == 5)
        #expect(stats.bytesReceived == 5)
    }
    
    @Test("Statistics tracks unique opcodes")
    func tracksUniqueOpcodes() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x30]))
        logger.logOutgoing(Data([0x31]))
        logger.logOutgoing(Data([0x30]))
        logger.logOutgoing(Data([0x32]))
        
        let stats = logger.statistics
        
        #expect(stats.uniqueOpcodes.count == 3)
        #expect(stats.uniqueOpcodes.contains(0x30))
        #expect(stats.uniqueOpcodes.contains(0x31))
        #expect(stats.uniqueOpcodes.contains(0x32))
    }
    
    @Test("Statistics computes average size")
    func averageSize() {
        let logger = BLETrafficLogger()
        
        logger.logOutgoing(Data([0x01, 0x02]))  // 2 bytes
        logger.logOutgoing(Data([0x01, 0x02, 0x03, 0x04]))  // 4 bytes
        
        let stats = logger.statistics
        
        #expect(stats.averagePacketSize == 3.0)
    }
    
    @Test("Empty statistics")
    func emptyStats() {
        let logger = BLETrafficLogger()
        let stats = logger.statistics
        
        #expect(stats.totalEntries == 0)
        #expect(stats.duration == 0)
        #expect(stats.averagePacketSize == 0)
        #expect(stats.firstTimestamp == nil)
    }
}

// MARK: - Export Tests

@Suite("Traffic Export Tests")
struct TrafficExportTests {
    
    @Test("Export to JSON")
    func exportJSON() {
        let logger = BLETrafficLogger()
        logger.logOutgoing(Data([0x30, 0x01]))
        logger.logIncoming(Data([0x31, 0x02]))
        
        let json = logger.export(format: .json)
        
        #expect(json.contains("\"direction\""))
        #expect(json.contains("\"outgoing\""))
        #expect(json.contains("\"incoming\""))
    }
    
    @Test("Export to hex dump")
    func exportHexDump() {
        let logger = BLETrafficLogger()
        logger.logOutgoing(Data([0x30, 0x01, 0xAB]))
        logger.logIncoming(Data([0x31, 0x02]))
        
        let hex = logger.export(format: .hexDump)
        
        #expect(hex.contains("TX:"))
        #expect(hex.contains("RX:"))
        #expect(hex.contains("30 01 AB"))
    }
    
    @Test("Export to CSV")
    func exportCSV() {
        let logger = BLETrafficLogger()
        logger.logOutgoing(Data([0x30, 0x01]))
        
        let csv = logger.export(format: .csv)
        
        #expect(csv.contains("timestamp,direction,opcode,size,data"))
        #expect(csv.contains("outgoing"))
        #expect(csv.contains("0x30"))
    }
    
    @Test("Export to pcap text")
    func exportPcapText() {
        let logger = BLETrafficLogger()
        logger.logOutgoing(Data([0x30, 0x01]))
        
        let pcap = logger.export(format: .pcapText)
        
        #expect(pcap.contains("Frame 1:"))
        #expect(pcap.contains("Central -> Peripheral"))
    }
    
    @Test("Export with filter")
    func exportWithFilter() {
        let logger = BLETrafficLogger()
        logger.logOutgoing(Data([0x30]))
        logger.logOutgoing(Data([0x31]))
        logger.logIncoming(Data([0x32]))
        
        let filter = TrafficFilter.direction(.outgoing)
        let json = logger.export(format: .json, filter: filter)
        
        #expect(json.contains("\"outgoing\""))
        #expect(!json.contains("\"incoming\""))
    }
}

// MARK: - Session Tests

@Suite("LoggerSession Tests")
struct LoggerSessionTests {
    
    @Test("Session captures entries")
    func capturesEntries() {
        let logger = BLETrafficLogger()
        var session = logger.startSession(name: "Test")
        
        logger.logOutgoing(Data([0x01]))
        logger.logOutgoing(Data([0x02]))
        
        logger.endSession(&session)
        
        #expect(session.entries.count == 2)
        #expect(session.endTime != nil)
        #expect(session.name == "Test")
    }
    
    @Test("Session has duration")
    func hasDuration() {
        let session = LoggerSession(name: "Test")
        
        Thread.sleep(forTimeInterval: 0.01)
        
        #expect(session.duration > 0)
    }
}

// MARK: - Thread Safety Tests

@Suite("Thread Safety Tests")
struct ThreadSafetyTests {
    
    @Test("Concurrent logging is safe")
    func concurrentLogging() async {
        let logger = BLETrafficLogger()
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    logger.log(direction: .outgoing, data: Data([UInt8(i % 256)]))
                }
            }
        }
        
        #expect(logger.count == 100)
    }
    
    @Test("Concurrent read/write is safe")
    func concurrentReadWrite() async {
        let logger = BLETrafficLogger()
        
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    logger.log(direction: .outgoing, data: Data([UInt8(i % 256)]))
                }
            }
            
            // Readers
            for _ in 0..<50 {
                group.addTask {
                    _ = logger.count
                    _ = logger.statistics
                }
            }
        }
        
        #expect(logger.count == 50)
    }
}
