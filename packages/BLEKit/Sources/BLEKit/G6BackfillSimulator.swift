// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6BackfillSimulator.swift
// BLEKit
//
// Server-side Dexcom G6 backfill handling for transmitter simulation.
// Provides historical glucose data to clients that missed readings.
// Trace: PRD-007 REQ-SIM-006

import Foundation

// MARK: - Backfill Opcodes

/// G6 backfill-related opcodes
public enum G6BackfillOpcode: UInt8, Sendable {
    /// Backfill request from client (0x50)
    case backfillTx = 0x50
    
    /// Backfill response header (0x51)
    case backfillRx = 0x51
    
    /// Backfill data packet (0x52)
    case backfillDataTx = 0x52
    
    /// Backfill data response (0x53)
    case backfillDataRx = 0x53
}

// MARK: - Backfill Status

/// Status codes for backfill responses
public enum G6BackfillStatus: UInt8, Sendable, Codable {
    /// Backfill available
    case available = 0x00
    
    /// No backfill data available
    case noData = 0x01
    
    /// Backfill request range invalid
    case invalidRange = 0x02
    
    /// Backfill in progress
    case inProgress = 0x03
    
    /// Backfill complete
    case complete = 0x04
}

// MARK: - Backfill Record

/// A single backfill glucose record
public struct BackfillRecord: Sendable, Codable, Equatable {
    /// Glucose value in mg/dL
    public let glucose: UInt16
    
    /// Trend value (-8 to +8)
    public let trend: Int8
    
    /// Timestamp in transmitter time (seconds since activation)
    public let timestamp: UInt32
    
    /// Quality/confidence indicator (0-100)
    public let quality: UInt8
    
    /// Create a backfill record
    public init(glucose: UInt16, trend: Int8, timestamp: UInt32, quality: UInt8 = 100) {
        self.glucose = glucose
        self.trend = trend
        self.timestamp = timestamp
        self.quality = quality
    }
    
    /// Size of a backfill record in bytes
    public static let size: Int = 8
    
    /// Serialize to bytes
    public func toBytes() -> Data {
        var data = Data(capacity: Self.size)
        // Format: glucose(2) + trend(1) + quality(1) + timestamp(4)
        data.append(UInt8(glucose & 0xFF))
        data.append(UInt8(glucose >> 8))
        data.append(UInt8(bitPattern: trend))
        data.append(quality)
        data.append(UInt8(timestamp & 0xFF))
        data.append(UInt8((timestamp >> 8) & 0xFF))
        data.append(UInt8((timestamp >> 16) & 0xFF))
        data.append(UInt8((timestamp >> 24) & 0xFF))
        return data
    }
    
    /// Parse from bytes
    public static func fromBytes(_ data: Data, offset: Int = 0) -> BackfillRecord? {
        guard data.count >= offset + size else { return nil }
        
        let glucose = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        let trend = Int8(bitPattern: data[offset + 2])
        let quality = data[offset + 3]
        let timestamp = UInt32(data[offset + 4]) |
                       (UInt32(data[offset + 5]) << 8) |
                       (UInt32(data[offset + 6]) << 16) |
                       (UInt32(data[offset + 7]) << 24)
        
        return BackfillRecord(glucose: glucose, trend: trend, timestamp: timestamp, quality: quality)
    }
}

// MARK: - Backfill Request

/// Parsed backfill request from client
public struct BackfillRequest: Sendable, Equatable {
    /// Start timestamp (oldest data requested)
    public let startTime: UInt32
    
    /// End timestamp (newest data requested)
    public let endTime: UInt32
    
    /// Create a backfill request
    public init(startTime: UInt32, endTime: UInt32) {
        self.startTime = startTime
        self.endTime = endTime
    }
    
    /// Parse from BackfillTx message
    public static func parse(_ data: Data) -> BackfillRequest? {
        // Format: opcode(1) + startTime(4) + endTime(4) = 9 bytes minimum
        guard data.count >= 9, data[0] == G6BackfillOpcode.backfillTx.rawValue else {
            return nil
        }
        
        let startTime = UInt32(data[1]) |
                       (UInt32(data[2]) << 8) |
                       (UInt32(data[3]) << 16) |
                       (UInt32(data[4]) << 24)
        
        let endTime = UInt32(data[5]) |
                     (UInt32(data[6]) << 8) |
                     (UInt32(data[7]) << 16) |
                     (UInt32(data[8]) << 24)
        
        return BackfillRequest(startTime: startTime, endTime: endTime)
    }
}

// MARK: - Backfill Provider Protocol

/// Protocol for providing historical glucose data
public protocol BackfillProvider: Sendable {
    /// Get backfill records for a time range
    /// - Parameters:
    ///   - startTime: Start timestamp (transmitter time)
    ///   - endTime: End timestamp (transmitter time)
    /// - Returns: Array of backfill records within the range
    func getBackfillRecords(startTime: UInt32, endTime: UInt32) -> [BackfillRecord]
    
    /// Get the oldest available timestamp
    func oldestAvailableTime() -> UInt32?
    
    /// Get the newest available timestamp
    func newestAvailableTime() -> UInt32?
}

// MARK: - Static Backfill Provider

/// Simple backfill provider with pre-loaded records
public final class StaticBackfillProvider: BackfillProvider, @unchecked Sendable {
    private var records: [BackfillRecord]
    private let lock = NSLock()
    
    public init(records: [BackfillRecord] = []) {
        self.records = records.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Add a record to the backfill history
    public func addRecord(_ record: BackfillRecord) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
        records.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Add multiple records
    public func addRecords(_ newRecords: [BackfillRecord]) {
        lock.lock()
        defer { lock.unlock() }
        records.append(contentsOf: newRecords)
        records.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Clear all records
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll()
    }
    
    /// Get record count
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }
    
    public func getBackfillRecords(startTime: UInt32, endTime: UInt32) -> [BackfillRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }
    
    public func oldestAvailableTime() -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return records.first?.timestamp
    }
    
    public func newestAvailableTime() -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return records.last?.timestamp
    }
}

// MARK: - Generated Backfill Provider

/// Backfill provider that generates historical data from a glucose pattern
public final class GeneratedBackfillProvider: BackfillProvider, @unchecked Sendable {
    private let glucoseProvider: GlucoseProvider
    private let interval: UInt32  // Seconds between readings (usually 300 = 5 min)
    private let historyDuration: UInt32  // How far back to generate (seconds)
    private let lock = NSLock()
    
    public init(
        glucoseProvider: GlucoseProvider,
        interval: UInt32 = 300,
        historyDuration: UInt32 = 3 * 3600  // 3 hours default
    ) {
        self.glucoseProvider = glucoseProvider
        self.interval = interval
        self.historyDuration = historyDuration
    }
    
    public func getBackfillRecords(startTime: UInt32, endTime: UInt32) -> [BackfillRecord] {
        lock.lock()
        defer { lock.unlock() }
        
        var records: [BackfillRecord] = []
        
        // Generate records at each interval
        var timestamp = startTime - (startTime % interval)  // Align to interval
        if timestamp < startTime {
            timestamp += interval
        }
        
        while timestamp <= endTime {
            let record = BackfillRecord(
                glucose: glucoseProvider.currentGlucose(),
                trend: glucoseProvider.currentTrend(),
                timestamp: timestamp,
                quality: 100
            )
            records.append(record)
            timestamp += interval
        }
        
        return records
    }
    
    public func oldestAvailableTime() -> UInt32? {
        // Can generate from historyDuration ago to now
        let now = UInt32(Date().timeIntervalSince1970)
        return now > historyDuration ? now - historyDuration : 0
    }
    
    public func newestAvailableTime() -> UInt32? {
        return UInt32(Date().timeIntervalSince1970)
    }
}

// MARK: - Backfill Result

/// Result of processing a backfill request
public enum G6BackfillResult: Sendable {
    /// Send header response followed by data packets
    case sendBackfill(header: Data, dataPackets: [Data])
    
    /// No data available for the requested range
    case noData(Data)
    
    /// Invalid or unexpected message
    case invalidMessage(String)
}

// MARK: - G6 Backfill Simulator

/// Server-side G6 backfill request handler for transmitter simulation
///
/// Handles BackfillTx (0x50) requests and generates BackfillRx (0x51) header
/// responses followed by BackfillDataRx (0x53) data packets.
///
/// ## Usage
/// ```swift
/// let provider = StaticBackfillProvider(records: historicalRecords)
/// let simulator = G6BackfillSimulator(backfillProvider: provider)
///
/// // When client sends BackfillTx:
/// let result = simulator.processMessage(clientData)
/// switch result {
/// case .sendBackfill(let header, let packets):
///     // Send header, then each data packet
/// case .noData(let response):
///     // Send no-data response
/// case .invalidMessage(let reason):
///     // Handle error
/// }
/// ```
public final class G6BackfillSimulator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Backfill data provider
    public var backfillProvider: BackfillProvider
    
    /// Maximum records per data packet
    public let maxRecordsPerPacket: Int
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Statistics
    
    /// Number of backfill requests processed
    public private(set) var requestCount: Int = 0
    
    /// Total records sent
    public private(set) var recordsSent: Int = 0
    
    // MARK: - Initialization
    
    /// Create a backfill simulator
    /// - Parameters:
    ///   - backfillProvider: Provider for historical data
    ///   - maxRecordsPerPacket: Maximum records per data packet (default 2)
    public init(
        backfillProvider: BackfillProvider,
        maxRecordsPerPacket: Int = 2
    ) {
        self.backfillProvider = backfillProvider
        self.maxRecordsPerPacket = maxRecordsPerPacket
    }
    
    // MARK: - Message Processing
    
    /// Process a backfill request message
    /// - Parameter data: Raw message data from client
    /// - Returns: Result with header and data packets to send
    public func processMessage(_ data: Data) -> G6BackfillResult {
        guard !data.isEmpty else {
            return .invalidMessage("Empty message")
        }
        
        let opcode = data[0]
        
        guard opcode == G6BackfillOpcode.backfillTx.rawValue else {
            return .invalidMessage("Expected BackfillTx (0x50), got 0x\(String(format: "%02X", opcode))")
        }
        
        return handleBackfillRequest(data)
    }
    
    // MARK: - Private Methods
    
    private func handleBackfillRequest(_ data: Data) -> G6BackfillResult {
        guard let request = BackfillRequest.parse(data) else {
            return .invalidMessage("Failed to parse BackfillTx message")
        }
        
        lock.lock()
        requestCount += 1
        lock.unlock()
        
        // Get records for the requested range
        let records = backfillProvider.getBackfillRecords(
            startTime: request.startTime,
            endTime: request.endTime
        )
        
        if records.isEmpty {
            return .noData(buildNoDataResponse())
        }
        
        // Build header response
        let header = buildHeaderResponse(recordCount: records.count, request: request)
        
        // Build data packets
        let packets = buildDataPackets(records: records)
        
        lock.lock()
        recordsSent += records.count
        lock.unlock()
        
        return .sendBackfill(header: header, dataPackets: packets)
    }
    
    private func buildNoDataResponse() -> Data {
        var response = Data(capacity: 5)
        response.append(G6BackfillOpcode.backfillRx.rawValue)
        response.append(G6BackfillStatus.noData.rawValue)
        response.append(0x00)  // Record count low
        response.append(0x00)  // Record count high
        response.append(0x00)  // Packet count
        return response
    }
    
    private func buildHeaderResponse(recordCount: Int, request: BackfillRequest) -> Data {
        let packetCount = (recordCount + maxRecordsPerPacket - 1) / maxRecordsPerPacket
        
        var response = Data(capacity: 13)
        // Opcode
        response.append(G6BackfillOpcode.backfillRx.rawValue)
        // Status
        response.append(G6BackfillStatus.available.rawValue)
        // Record count (2 bytes)
        response.append(UInt8(recordCount & 0xFF))
        response.append(UInt8((recordCount >> 8) & 0xFF))
        // Packet count
        response.append(UInt8(packetCount))
        // Start time (4 bytes)
        response.append(UInt8(request.startTime & 0xFF))
        response.append(UInt8((request.startTime >> 8) & 0xFF))
        response.append(UInt8((request.startTime >> 16) & 0xFF))
        response.append(UInt8((request.startTime >> 24) & 0xFF))
        // End time (4 bytes)
        response.append(UInt8(request.endTime & 0xFF))
        response.append(UInt8((request.endTime >> 8) & 0xFF))
        response.append(UInt8((request.endTime >> 16) & 0xFF))
        response.append(UInt8((request.endTime >> 24) & 0xFF))
        
        return response
    }
    
    private func buildDataPackets(records: [BackfillRecord]) -> [Data] {
        var packets: [Data] = []
        var index = 0
        var packetNumber: UInt8 = 0
        
        while index < records.count {
            var packet = Data()
            // Opcode
            packet.append(G6BackfillOpcode.backfillDataRx.rawValue)
            // Packet number
            packet.append(packetNumber)
            // Records in this packet
            let recordsInPacket = min(maxRecordsPerPacket, records.count - index)
            packet.append(UInt8(recordsInPacket))
            
            // Append record data
            for i in 0..<recordsInPacket {
                packet.append(records[index + i].toBytes())
            }
            
            packets.append(packet)
            index += recordsInPacket
            packetNumber += 1
        }
        
        return packets
    }
    
    // MARK: - Reset
    
    /// Reset statistics
    public func resetStatistics() {
        lock.lock()
        defer { lock.unlock() }
        requestCount = 0
        recordsSent = 0
    }
}
