// SPDX-License-Identifier: MIT
//
// DropoutRecoveryTests.swift
// CGMKitTests
//
// Tests for CGM signal dropout detection, reconnection, and data recovery.
// Validates that the CGM system correctly handles connection losses and
// merges data after reconnection to maintain continuous glucose history.
//
// Trace: TEST-GAP-007, DOC-TEST-003, CRITICAL-PATH-TESTS.md
// Requirements: REQ-CGM-001, PROD-HARDEN

import Testing
import Foundation
@testable import CGMKit

// MARK: - Test Infrastructure

/// Simulated CGM connection state for testing dropout scenarios
enum SimulatedConnectionState: Sendable {
    case connected
    case disconnected(reason: DisconnectReason)
    case reconnecting(attempt: Int)
    case failed(error: Error)
    
    enum DisconnectReason: Sendable {
        case signalLoss
        case userInitiated
        case sensorExpired
        case bluetoothOff
        case outOfRange
    }
}

/// Simulated glucose reading with gap tracking
struct GapAwareReading: Sendable, Identifiable, Equatable {
    let id: UUID
    let glucose: Double
    let timestamp: Date
    let sequenceNumber: UInt32
    let isBackfilled: Bool  // True if reading was recovered after dropout
    
    init(glucose: Double, timestamp: Date, sequenceNumber: UInt32, isBackfilled: Bool = false) {
        self.id = UUID()
        self.glucose = glucose
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.isBackfilled = isBackfilled
    }
    
    static func == (lhs: GapAwareReading, rhs: GapAwareReading) -> Bool {
        lhs.sequenceNumber == rhs.sequenceNumber && lhs.glucose == rhs.glucose
    }
}

/// Gap detection result
struct GapInfo: Sendable {
    let startTime: Date
    let endTime: Date
    let missedReadings: Int
    let durationMinutes: Double
    
    var isSignificant: Bool {
        durationMinutes >= 5  // 5+ minutes is significant gap
    }
}

/// Mock CGM manager for dropout testing
actor MockDropoutCGMManager {
    private var connectionState: SimulatedConnectionState = .disconnected(reason: .signalLoss)
    private var readings: [GapAwareReading] = []
    private var reconnectAttempts: Int = 0
    private var maxReconnectAttempts: Int = 5
    private var reconnectDelayMs: UInt64 = 100
    private var lastSequenceNumber: UInt32 = 0
    private var shouldFailReconnect: Bool = false
    private var reconnectFailuresRemaining: Int = 0
    private var gapsDetected: [GapInfo] = []
    private var connectionStateHistory: [SimulatedConnectionState] = []
    private var recoveredReadingsLog: [[GapAwareReading]] = []
    
    // Configuration
    func setMaxReconnectAttempts(_ max: Int) {
        maxReconnectAttempts = max
    }
    
    func setReconnectDelay(_ delayMs: UInt64) {
        reconnectDelayMs = delayMs
    }
    
    func setReconnectFailures(_ count: Int) {
        reconnectFailuresRemaining = count
        shouldFailReconnect = count > 0
    }
    
    // Connection management
    func connect() async throws {
        connectionState = .reconnecting(attempt: 1)
        connectionStateHistory.append(connectionState)
        
        // Simulate connection delay
        try await Task.sleep(nanoseconds: reconnectDelayMs * 1_000_000)
        
        connectionState = .connected
        connectionStateHistory.append(connectionState)
    }
    
    func disconnect(reason: SimulatedConnectionState.DisconnectReason) {
        connectionState = .disconnected(reason: reason)
        connectionStateHistory.append(connectionState)
    }
    
    func simulateDropout(reason: SimulatedConnectionState.DisconnectReason = .signalLoss) {
        disconnect(reason: reason)
    }
    
    // Reconnection with retry logic
    func attemptReconnect() async -> Bool {
        reconnectAttempts = 0
        
        while reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            connectionState = .reconnecting(attempt: reconnectAttempts)
            connectionStateHistory.append(connectionState)
            
            // Simulate reconnection delay with exponential backoff
            let delay = reconnectDelayMs * UInt64(1 << min(reconnectAttempts - 1, 4))
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            
            // Check if reconnect should fail
            if shouldFailReconnect && reconnectFailuresRemaining > 0 {
                reconnectFailuresRemaining -= 1
                if reconnectFailuresRemaining == 0 {
                    shouldFailReconnect = false
                }
                continue
            }
            
            // Success
            connectionState = .connected
            connectionStateHistory.append(connectionState)
            return true
        }
        
        // All attempts failed
        connectionState = .failed(error: CGMError.connectionFailed)
        connectionStateHistory.append(connectionState)
        return false
    }
    
    // Reading management
    func addReading(_ reading: GapAwareReading) {
        // Check for gap
        if let last = readings.last {
            let timeDiff = reading.timestamp.timeIntervalSince(last.timestamp)
            let expectedInterval: TimeInterval = 300  // 5 minutes for CGM
            
            if timeDiff > expectedInterval * 1.5 {  // >7.5 min = gap
                let missedReadings = Int(timeDiff / expectedInterval) - 1
                let gap = GapInfo(
                    startTime: last.timestamp,
                    endTime: reading.timestamp,
                    missedReadings: missedReadings,
                    durationMinutes: timeDiff / 60
                )
                gapsDetected.append(gap)
            }
        }
        
        readings.append(reading)
        lastSequenceNumber = reading.sequenceNumber
    }
    
    func backfillReadings(_ backfilled: [GapAwareReading]) {
        // Merge backfilled readings in chronological order
        var allReadings = readings + backfilled
        allReadings.sort { $0.timestamp < $1.timestamp }
        
        // Deduplicate by sequence number
        var seen = Set<UInt32>()
        readings = allReadings.filter { reading in
            if seen.contains(reading.sequenceNumber) {
                return false
            }
            seen.insert(reading.sequenceNumber)
            return true
        }
        
        recoveredReadingsLog.append(backfilled)
    }
    
    func getReadings() -> [GapAwareReading] {
        readings
    }
    
    func getGapsDetected() -> [GapInfo] {
        gapsDetected
    }
    
    func getReconnectAttempts() -> Int {
        reconnectAttempts
    }
    
    func getConnectionState() -> SimulatedConnectionState {
        connectionState
    }
    
    func getConnectionStateHistory() -> [SimulatedConnectionState] {
        connectionStateHistory
    }
    
    func getRecoveredReadingsLog() -> [[GapAwareReading]] {
        recoveredReadingsLog
    }
    
    func clearReadings() {
        readings.removeAll()
        gapsDetected.removeAll()
    }
}

/// Generator for simulating CGM reading streams with gaps
struct ReadingStreamGenerator {
    let baseGlucose: Double
    let interval: TimeInterval  // seconds between readings
    
    func generate(count: Int, startTime: Date, startSequence: UInt32 = 1) -> [GapAwareReading] {
        var readings: [GapAwareReading] = []
        for i in 0..<count {
            let timestamp = startTime.addingTimeInterval(Double(i) * interval)
            let glucose = baseGlucose + Double.random(in: -20...20)
            let reading = GapAwareReading(
                glucose: glucose,
                timestamp: timestamp,
                sequenceNumber: startSequence + UInt32(i)
            )
            readings.append(reading)
        }
        return readings
    }
    
    func generateWithGap(
        beforeGap: Int,
        afterGap: Int,
        gapDurationMinutes: Double,
        startTime: Date,
        startSequence: UInt32 = 1
    ) -> (before: [GapAwareReading], after: [GapAwareReading], gap: GapInfo) {
        // Generate readings before gap
        let before = generate(count: beforeGap, startTime: startTime, startSequence: startSequence)
        
        // Calculate gap info
        let lastBeforeTime = before.last!.timestamp
        let gapEnd = lastBeforeTime.addingTimeInterval(gapDurationMinutes * 60)
        let missedReadings = Int(gapDurationMinutes * 60 / interval)
        let gap = GapInfo(
            startTime: lastBeforeTime,
            endTime: gapEnd,
            missedReadings: missedReadings,
            durationMinutes: gapDurationMinutes
        )
        
        // Generate readings after gap
        let afterStartSequence = startSequence + UInt32(beforeGap) + UInt32(missedReadings)
        let after = generate(count: afterGap, startTime: gapEnd, startSequence: afterStartSequence)
        
        return (before, after, gap)
    }
    
    func generateBackfill(for gap: GapInfo, startSequence: UInt32) -> [GapAwareReading] {
        var readings: [GapAwareReading] = []
        var time = gap.startTime.addingTimeInterval(interval)
        var seq = startSequence
        
        while time < gap.endTime {
            let glucose = baseGlucose + Double.random(in: -20...20)
            let reading = GapAwareReading(
                glucose: glucose,
                timestamp: time,
                sequenceNumber: seq,
                isBackfilled: true
            )
            readings.append(reading)
            time = time.addingTimeInterval(interval)
            seq += 1
        }
        return readings
    }
}

// MARK: - Dropout Detection Tests

@Suite("Dropout Detection")
struct DropoutDetectionTests {
    
    @Test("Detects signal dropout from connection loss")
    func detectsSignalDropout() async {
        let manager = MockDropoutCGMManager()
        
        try? await manager.connect()
        await manager.simulateDropout(reason: .signalLoss)
        
        let history = await manager.getConnectionStateHistory()
        let hasSignalLoss = history.contains { state in
            if case .disconnected(reason: .signalLoss) = state { return true }
            return false
        }
        #expect(hasSignalLoss)
    }
    
    @Test("Detects gap in reading timeline")
    func detectsTimelineGap() async {
        let manager = MockDropoutCGMManager()
        
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let startTime = Date()
        
        // Add readings with a 15-minute gap
        let (before, after, _) = generator.generateWithGap(
            beforeGap: 3,
            afterGap: 2,
            gapDurationMinutes: 15,
            startTime: startTime
        )
        
        for reading in before {
            await manager.addReading(reading)
        }
        for reading in after {
            await manager.addReading(reading)
        }
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.count >= 1)
        #expect(gaps.first!.isSignificant)
        #expect(gaps.first!.missedReadings >= 2)  // 15 min gap = 2 missed readings (at 5min and 10min)
    }
    
    @Test("Does not flag normal intervals as gaps")
    func normalIntervalsNotGaps() async {
        let manager = MockDropoutCGMManager()
        
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let readings = generator.generate(count: 10, startTime: Date())
        
        for reading in readings {
            await manager.addReading(reading)
        }
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.isEmpty)
    }
    
    @Test("Identifies dropout reason correctly")
    func identifiesDropoutReason() async {
        let manager = MockDropoutCGMManager()
        
        await manager.simulateDropout(reason: .signalLoss)
        await manager.simulateDropout(reason: .outOfRange)
        await manager.simulateDropout(reason: .bluetoothOff)
        
        let history = await manager.getConnectionStateHistory()
        var reasons: [SimulatedConnectionState.DisconnectReason] = []
        for state in history {
            if case .disconnected(let reason) = state {
                reasons.append(reason)
            }
        }
        
        #expect(reasons.count == 3)
        #expect(reasons[0] == .signalLoss)
        #expect(reasons[1] == .outOfRange)
        #expect(reasons[2] == .bluetoothOff)
    }
}

// MARK: - Reconnection Tests

@Suite("Reconnection Logic")
struct ReconnectionTests {
    
    @Test("Reconnects successfully after dropout")
    func reconnectsAfterDropout() async {
        let manager = MockDropoutCGMManager()
        await manager.setReconnectDelay(10)  // Fast for testing
        
        try? await manager.connect()
        await manager.simulateDropout()
        
        let success = await manager.attemptReconnect()
        let state = await manager.getConnectionState()
        
        #expect(success)
        if case .connected = state {
            // Expected
        } else {
            Issue.record("Expected connected state")
        }
    }
    
    @Test("Retries reconnection with exponential backoff")
    func retriesWithBackoff() async {
        let manager = MockDropoutCGMManager()
        await manager.setReconnectDelay(5)
        await manager.setReconnectFailures(3)  // Fail first 3 attempts
        
        let startTime = Date()
        let success = await manager.attemptReconnect()
        let elapsed = Date().timeIntervalSince(startTime)
        
        #expect(success)
        // Should have taken at least 3 failed attempts + 1 success
        // With backoff: 5ms + 10ms + 20ms + 40ms ≈ 75ms minimum
        #expect(elapsed > 0.05)  // At least 50ms
    }
    
    @Test("Stops after max reconnect attempts")
    func stopsAfterMaxAttempts() async {
        let manager = MockDropoutCGMManager()
        await manager.setMaxReconnectAttempts(3)
        await manager.setReconnectDelay(5)
        await manager.setReconnectFailures(10)  // Always fail
        
        let success = await manager.attemptReconnect()
        let attempts = await manager.getReconnectAttempts()
        let state = await manager.getConnectionState()
        
        #expect(!success)
        #expect(attempts == 3)
        if case .failed = state {
            // Expected
        } else {
            Issue.record("Expected failed state")
        }
    }
    
    @Test("Does not reconnect after user-initiated disconnect")
    func noReconnectAfterUserDisconnect() async {
        let manager = MockDropoutCGMManager()
        
        try? await manager.connect()
        await manager.disconnect(reason: .userInitiated)
        
        let state = await manager.getConnectionState()
        if case .disconnected(reason: .userInitiated) = state {
            // Expected - should stay disconnected
        } else {
            Issue.record("Expected user-initiated disconnect state")
        }
    }
    
    @Test("Tracks reconnection attempt count")
    func tracksAttemptCount() async {
        let manager = MockDropoutCGMManager()
        await manager.setReconnectDelay(5)
        await manager.setReconnectFailures(2)  // Fail first 2
        
        _ = await manager.attemptReconnect()
        let attempts = await manager.getReconnectAttempts()
        
        #expect(attempts == 3)  // 2 failures + 1 success
    }
}

// MARK: - Data Recovery Tests

@Suite("Data Recovery After Dropout")
struct DataRecoveryTests {
    
    @Test("Backfills missed readings after reconnect")
    func backfillsMissedReadings() async {
        let manager = MockDropoutCGMManager()
        
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let startTime = Date()
        
        // Simulate: readings before gap, gap, then backfill
        let (before, _, gap) = generator.generateWithGap(
            beforeGap: 3,
            afterGap: 0,
            gapDurationMinutes: 15,
            startTime: startTime
        )
        
        for reading in before {
            await manager.addReading(reading)
        }
        
        // Simulate backfill after reconnection
        let backfilled = generator.generateBackfill(for: gap, startSequence: 4)
        await manager.backfillReadings(backfilled)
        
        let recoveredLog = await manager.getRecoveredReadingsLog()
        #expect(recoveredLog.count == 1)
        #expect(recoveredLog.first!.count == backfilled.count)
        #expect(recoveredLog.first!.allSatisfy { $0.isBackfilled })
    }
    
    @Test("Merges backfilled readings in chronological order")
    func mergesInChronologicalOrder() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let startTime = Date()
        
        // Add readings with gap
        let (before, after, gap) = generator.generateWithGap(
            beforeGap: 3,
            afterGap: 2,
            gapDurationMinutes: 15,
            startTime: startTime
        )
        
        for reading in before {
            await manager.addReading(reading)
        }
        for reading in after {
            await manager.addReading(reading)
        }
        
        // Backfill the gap
        let backfilled = generator.generateBackfill(for: gap, startSequence: 4)
        await manager.backfillReadings(backfilled)
        
        // Verify chronological order
        let allReadings = await manager.getReadings()
        for i in 0..<allReadings.count - 1 {
            #expect(allReadings[i].timestamp <= allReadings[i + 1].timestamp)
        }
    }
    
    @Test("Deduplicates readings during merge")
    func deduplicatesDuringMerge() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let readings = generator.generate(count: 5, startTime: Date())
        
        // Add original readings
        for reading in readings {
            await manager.addReading(reading)
        }
        
        // Try to backfill with duplicates
        await manager.backfillReadings(readings)
        
        let allReadings = await manager.getReadings()
        #expect(allReadings.count == 5)  // No duplicates
    }
    
    @Test("Marks backfilled readings appropriately")
    func marksBackfilledReadings() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let startTime = Date()
        
        // Add some original readings
        let original = generator.generate(count: 3, startTime: startTime)
        for reading in original {
            await manager.addReading(reading)
        }
        
        // Add backfilled readings
        let backfilled = [
            GapAwareReading(glucose: 130, timestamp: startTime.addingTimeInterval(900), sequenceNumber: 4, isBackfilled: true),
            GapAwareReading(glucose: 125, timestamp: startTime.addingTimeInterval(1200), sequenceNumber: 5, isBackfilled: true)
        ]
        await manager.backfillReadings(backfilled)
        
        let allReadings = await manager.getReadings()
        let backfilledCount = allReadings.filter { $0.isBackfilled }.count
        
        #expect(backfilledCount == 2)
    }
}

// MARK: - History Continuity Tests

@Suite("History Continuity")
struct HistoryContinuityTests {
    
    @Test("Maintains continuous sequence numbers")
    func maintainsContinuousSequence() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        
        // Generate continuous readings
        let readings = generator.generate(count: 20, startTime: Date())
        for reading in readings {
            await manager.addReading(reading)
        }
        
        let allReadings = await manager.getReadings()
        
        // Verify sequence continuity
        for i in 0..<allReadings.count - 1 {
            let current = allReadings[i].sequenceNumber
            let next = allReadings[i + 1].sequenceNumber
            #expect(next == current + 1)
        }
    }
    
    @Test("Detects sequence number gaps")
    func detectsSequenceGaps() async {
        let manager = MockDropoutCGMManager()
        
        // Add readings with sequence gap
        await manager.addReading(GapAwareReading(glucose: 120, timestamp: Date(), sequenceNumber: 1))
        await manager.addReading(GapAwareReading(glucose: 125, timestamp: Date().addingTimeInterval(300), sequenceNumber: 2))
        await manager.addReading(GapAwareReading(glucose: 130, timestamp: Date().addingTimeInterval(1200), sequenceNumber: 5))  // Gap: 3, 4 missing
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.count == 1)
    }
    
    @Test("Calculates correct gap duration")
    func calculatesGapDuration() async {
        let manager = MockDropoutCGMManager()
        
        let baseTime = Date()
        await manager.addReading(GapAwareReading(glucose: 120, timestamp: baseTime, sequenceNumber: 1))
        await manager.addReading(GapAwareReading(glucose: 125, timestamp: baseTime.addingTimeInterval(1800), sequenceNumber: 7))  // 30 min gap
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.count >= 1)
        #expect(abs(gaps.first!.durationMinutes - 30) < 0.1)
    }
    
    @Test("Handles multiple gaps in history")
    func handlesMultipleGaps() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        let startTime = Date()
        
        // Create readings with multiple gaps
        // Gap 1: 3 readings, then 15 min gap
        let batch1 = generator.generate(count: 3, startTime: startTime, startSequence: 1)
        for reading in batch1 {
            await manager.addReading(reading)
        }
        
        // Gap 2: after gap, 2 readings, then another gap
        let batch2StartTime = startTime.addingTimeInterval(900 + 600)  // 15 + 10 min after last
        let batch2 = generator.generate(count: 2, startTime: batch2StartTime, startSequence: 7)
        for reading in batch2 {
            await manager.addReading(reading)
        }
        
        // After second gap
        let batch3StartTime = batch2StartTime.addingTimeInterval(600 + 1200)  // 10 + 20 min
        let batch3 = generator.generate(count: 2, startTime: batch3StartTime, startSequence: 13)
        for reading in batch3 {
            await manager.addReading(reading)
        }
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.count == 2)
    }
}

// MARK: - Edge Cases

@Suite("Dropout Edge Cases")
struct DropoutEdgeCases {
    
    @Test("Handles rapid connect/disconnect cycles")
    func handlesRapidCycles() async {
        let manager = MockDropoutCGMManager()
        await manager.setReconnectDelay(1)
        
        for _ in 0..<10 {
            try? await manager.connect()
            await manager.simulateDropout()
        }
        
        // Should not crash or leak resources
        let state = await manager.getConnectionState()
        if case .disconnected = state {
            // Expected final state
        } else {
            Issue.record("Expected disconnected state after cycles")
        }
    }
    
    @Test("Handles empty backfill gracefully")
    func handlesEmptyBackfill() async {
        let manager = MockDropoutCGMManager()
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        
        let readings = generator.generate(count: 5, startTime: Date())
        for reading in readings {
            await manager.addReading(reading)
        }
        
        // Backfill with empty array
        await manager.backfillReadings([])
        
        let allReadings = await manager.getReadings()
        #expect(allReadings.count == 5)  // No change
    }
    
    @Test("Handles very long gaps")
    func handlesVeryLongGaps() async {
        let manager = MockDropoutCGMManager()
        
        let baseTime = Date()
        await manager.addReading(GapAwareReading(glucose: 120, timestamp: baseTime, sequenceNumber: 1))
        // 4 hour gap
        await manager.addReading(GapAwareReading(glucose: 130, timestamp: baseTime.addingTimeInterval(14400), sequenceNumber: 49))
        
        let gaps = await manager.getGapsDetected()
        #expect(gaps.count >= 1)
        #expect(gaps.first!.durationMinutes >= 240)
        #expect(gaps.first!.missedReadings >= 47)
    }
    
    @Test("Handles readings arriving out of order")
    func handlesOutOfOrderReadings() async {
        let manager = MockDropoutCGMManager()
        let baseTime = Date()
        
        // Add readings out of chronological order
        await manager.addReading(GapAwareReading(glucose: 120, timestamp: baseTime, sequenceNumber: 1))
        await manager.addReading(GapAwareReading(glucose: 140, timestamp: baseTime.addingTimeInterval(600), sequenceNumber: 3))
        
        // Backfill the middle reading
        await manager.backfillReadings([
            GapAwareReading(glucose: 130, timestamp: baseTime.addingTimeInterval(300), sequenceNumber: 2, isBackfilled: true)
        ])
        
        let readings = await manager.getReadings()
        #expect(readings.count == 3)
        #expect(readings[1].sequenceNumber == 2)  // Middle reading in correct position
    }
    
    @Test("Preserves reading data through dropout/recovery cycle")
    func preservesDataThroughCycle() async {
        let manager = MockDropoutCGMManager()
        await manager.setReconnectDelay(5)
        let generator = ReadingStreamGenerator(baseGlucose: 120, interval: 300)
        
        // Add initial readings
        let initial = generator.generate(count: 5, startTime: Date())
        for reading in initial {
            await manager.addReading(reading)
        }
        
        // Simulate dropout and reconnect
        try? await manager.connect()
        await manager.simulateDropout()
        _ = await manager.attemptReconnect()
        
        // Verify readings preserved
        let readings = await manager.getReadings()
        #expect(readings.count == 5)
        for (i, reading) in readings.enumerated() {
            #expect(reading.sequenceNumber == initial[i].sequenceNumber)
        }
    }
}

// MARK: - CGMHistoryManager Integration

@Suite("CGMHistoryManager Dropout Integration")
struct CGMHistoryManagerDropoutTests {
    
    @Test("History survives connection dropout")
    func historySurvivesDropout() async {
        let persistence = InMemoryCGMHistoryPersistence()
        let manager = CGMHistoryManager(persistence: persistence)
        
        // Log sensor session before dropout (use SensorHistoryEntry directly for active sessions)
        let entry = SensorHistoryEntry(
            sensorType: "dexcomG6",
            transmitterID: "80AB12",
            startDate: Date().addingTimeInterval(-86400),
            endDate: nil,  // Still active
            endReason: .unknown
        )
        await manager.logSensorSession(entry)
        
        // Simulate dropout (session persists)
        let history = await manager.getSensorHistory()
        #expect(history.count == 1)
        #expect(history.first?.endDate == nil)  // Session still active
    }
    
    @Test("Logs sensor session after dropout recovery")
    func logsSessionAfterRecovery() async {
        let persistence = InMemoryCGMHistoryPersistence()
        let manager = CGMHistoryManager(persistence: persistence)
        
        // First session (ended due to failure/dropout)
        await manager.logSensorSession(
            sensorType: "dexcomG6",
            transmitterId: "80AB12",
            startDate: Date().addingTimeInterval(-172800),
            endDate: Date().addingTimeInterval(-86400),
            endReason: .failed  // Use .failed for signal loss scenarios
        )
        
        // Second session after recovery
        await manager.logSensorSession(
            sensorType: "dexcomG6",
            transmitterId: "80AB12",
            startDate: Date().addingTimeInterval(-86400),
            endDate: Date(),
            endReason: .unknown  // Still active effectively
        )
        
        let history = await manager.getSensorHistory()
        #expect(history.count == 2)
    }
}
