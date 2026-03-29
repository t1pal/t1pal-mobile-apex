// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmInputRecorder.swift
// T1PalAlgorithm
//
// Records algorithm inputs and outputs for replay and audit
// Task: ALG-SHADOW-010

import Foundation
import T1PalCore

// MARK: - Recorded Session

/// A recorded algorithm calculation session
public struct RecordedSession: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let inputs: RecordedInputs
    public let outputs: [RecordedOutput]
    public let metadata: RecordedMetadata
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        inputs: RecordedInputs,
        outputs: [RecordedOutput],
        metadata: RecordedMetadata = RecordedMetadata()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.inputs = inputs
        self.outputs = outputs
        self.metadata = metadata
    }
}

/// Recorded algorithm inputs
public struct RecordedInputs: Codable, Sendable {
    public let glucose: [RecordedGlucose]
    public let insulinOnBoard: Double
    public let carbsOnBoard: Double
    public let profile: RecordedProfile
    public let currentTime: Date
    
    public init(
        glucose: [RecordedGlucose],
        insulinOnBoard: Double,
        carbsOnBoard: Double,
        profile: RecordedProfile,
        currentTime: Date = Date()
    ) {
        self.glucose = glucose
        self.insulinOnBoard = insulinOnBoard
        self.carbsOnBoard = carbsOnBoard
        self.profile = profile
        self.currentTime = currentTime
    }
    
    /// Convert from AlgorithmInputs
    public init(from inputs: AlgorithmInputs) {
        self.glucose = inputs.glucose.map { RecordedGlucose(from: $0) }
        self.insulinOnBoard = inputs.insulinOnBoard
        self.carbsOnBoard = inputs.carbsOnBoard
        self.profile = RecordedProfile(from: inputs.profile)
        self.currentTime = inputs.currentTime
    }
    
    /// Convert back to AlgorithmInputs
    public func toAlgorithmInputs() -> AlgorithmInputs {
        AlgorithmInputs(
            glucose: glucose.map { $0.toGlucoseReading() },
            insulinOnBoard: insulinOnBoard,
            carbsOnBoard: carbsOnBoard,
            profile: profile.toTherapyProfile(),
            currentTime: currentTime
        )
    }
}

/// Recorded glucose reading
public struct RecordedGlucose: Codable, Sendable {
    public let value: Double
    public let timestamp: Date
    public let trend: String
    
    public init(value: Double, timestamp: Date, trend: String) {
        self.value = value
        self.timestamp = timestamp
        self.trend = trend
    }
    
    public init(from reading: GlucoseReading) {
        self.value = reading.glucose
        self.timestamp = reading.timestamp
        self.trend = reading.trend.rawValue
    }
    
    public func toGlucoseReading() -> GlucoseReading {
        GlucoseReading(
            glucose: value,
            timestamp: timestamp,
            trend: GlucoseTrend(rawValue: trend) ?? .flat
        )
    }
}

/// Recorded therapy profile
public struct RecordedProfile: Codable, Sendable {
    public let basalRates: [RecordedBasalRate]
    public let carbRatios: [RecordedCarbRatio]
    public let sensitivityFactors: [RecordedSensitivityFactor]
    public let targetLow: Double
    public let targetHigh: Double
    public let maxIOB: Double?
    public let maxBolus: Double?
    
    public init(
        basalRates: [RecordedBasalRate],
        carbRatios: [RecordedCarbRatio],
        sensitivityFactors: [RecordedSensitivityFactor],
        targetLow: Double,
        targetHigh: Double,
        maxIOB: Double? = nil,
        maxBolus: Double? = nil
    ) {
        self.basalRates = basalRates
        self.carbRatios = carbRatios
        self.sensitivityFactors = sensitivityFactors
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.maxIOB = maxIOB
        self.maxBolus = maxBolus
    }
    
    public init(from profile: TherapyProfile) {
        self.basalRates = profile.basalRates.map { RecordedBasalRate(startTime: $0.startTime, rate: $0.rate) }
        self.carbRatios = profile.carbRatios.map { RecordedCarbRatio(startTime: $0.startTime, ratio: $0.ratio) }
        self.sensitivityFactors = profile.sensitivityFactors.map { RecordedSensitivityFactor(startTime: $0.startTime, factor: $0.factor) }
        self.targetLow = profile.targetGlucose.low
        self.targetHigh = profile.targetGlucose.high
        self.maxIOB = profile.maxIOB
        self.maxBolus = profile.maxBolus
    }
    
    public func toTherapyProfile() -> TherapyProfile {
        TherapyProfile(
            basalRates: basalRates.map { BasalRate(startTime: $0.startTime, rate: $0.rate) },
            carbRatios: carbRatios.map { CarbRatio(startTime: $0.startTime, ratio: $0.ratio) },
            sensitivityFactors: sensitivityFactors.map { SensitivityFactor(startTime: $0.startTime, factor: $0.factor) },
            targetGlucose: TargetRange(low: targetLow, high: targetHigh),
            maxIOB: maxIOB ?? 8.0,
            maxBolus: maxBolus ?? 10.0
        )
    }
}

public struct RecordedBasalRate: Codable, Sendable {
    public let startTime: TimeInterval
    public let rate: Double
    
    public init(startTime: TimeInterval, rate: Double) {
        self.startTime = startTime
        self.rate = rate
    }
}

public struct RecordedCarbRatio: Codable, Sendable {
    public let startTime: TimeInterval
    public let ratio: Double
    
    public init(startTime: TimeInterval, ratio: Double) {
        self.startTime = startTime
        self.ratio = ratio
    }
}

public struct RecordedSensitivityFactor: Codable, Sendable {
    public let startTime: TimeInterval
    public let factor: Double
    
    public init(startTime: TimeInterval, factor: Double) {
        self.startTime = startTime
        self.factor = factor
    }
}

/// Recorded algorithm output
public struct RecordedOutput: Codable, Sendable {
    public let algorithmId: String
    public let tempBasalRate: Double?
    public let tempBasalDuration: Double?
    public let suggestedBolus: Double?
    public let reason: String
    public let executionTimeMs: Double
    public let success: Bool
    public let error: String?
    
    public init(
        algorithmId: String,
        tempBasalRate: Double? = nil,
        tempBasalDuration: Double? = nil,
        suggestedBolus: Double? = nil,
        reason: String = "",
        executionTimeMs: Double = 0,
        success: Bool = true,
        error: String? = nil
    ) {
        self.algorithmId = algorithmId
        self.tempBasalRate = tempBasalRate
        self.tempBasalDuration = tempBasalDuration
        self.suggestedBolus = suggestedBolus
        self.reason = reason
        self.executionTimeMs = executionTimeMs
        self.success = success
        self.error = error
    }
    
    /// Create from AlgorithmDecision
    public init(algorithmId: String, decision: AlgorithmDecision, executionTimeMs: Double) {
        self.algorithmId = algorithmId
        self.tempBasalRate = decision.suggestedTempBasal?.rate
        self.tempBasalDuration = decision.suggestedTempBasal?.duration
        self.suggestedBolus = decision.suggestedBolus
        self.reason = decision.reason
        self.executionTimeMs = executionTimeMs
        self.success = true
        self.error = nil
    }
}

/// Session metadata
public struct RecordedMetadata: Codable, Sendable {
    public let deviceId: String?
    public let appVersion: String?
    public let platform: String?
    public let notes: String?
    
    public init(
        deviceId: String? = nil,
        appVersion: String? = nil,
        platform: String? = nil,
        notes: String? = nil
    ) {
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.platform = platform
        self.notes = notes
    }
}

// MARK: - Algorithm Input Recorder

/// Actor for recording algorithm inputs and outputs
/// Thread-safe storage with export capabilities
public actor AlgorithmInputRecorder {
    
    /// Shared singleton instance
    public static let shared = AlgorithmInputRecorder()
    
    /// Maximum number of sessions to store
    private let maxSessions: Int
    
    /// Recorded sessions (circular buffer)
    private var sessions: [RecordedSession] = []
    
    /// Whether recording is enabled
    private var _enabled: Bool = false
    
    /// Recording enabled state
    public var enabled: Bool { _enabled }
    
    // MARK: - Initialization
    
    public init(maxSessions: Int = 1000) {
        self.maxSessions = maxSessions
    }
    
    // MARK: - Configuration
    
    /// Enable or disable recording
    public func setEnabled(_ enabled: Bool) {
        _enabled = enabled
    }
    
    // MARK: - Recording
    
    /// Record a session with inputs and multiple algorithm outputs
    public func record(
        inputs: AlgorithmInputs,
        outputs: [RecordedOutput],
        metadata: RecordedMetadata = RecordedMetadata()
    ) {
        guard _enabled else { return }
        
        let session = RecordedSession(
            inputs: RecordedInputs(from: inputs),
            outputs: outputs,
            metadata: metadata
        )
        
        sessions.append(session)
        
        // Trim to max size
        if sessions.count > maxSessions {
            sessions.removeFirst(sessions.count - maxSessions)
        }
    }
    
    /// Record a single algorithm run
    public func recordSingle(
        inputs: AlgorithmInputs,
        algorithmId: String,
        decision: AlgorithmDecision,
        executionTimeMs: Double,
        metadata: RecordedMetadata = RecordedMetadata()
    ) {
        let output = RecordedOutput(
            algorithmId: algorithmId,
            decision: decision,
            executionTimeMs: executionTimeMs
        )
        record(inputs: inputs, outputs: [output], metadata: metadata)
    }
    
    /// Record an error
    public func recordError(
        inputs: AlgorithmInputs,
        algorithmId: String,
        error: Error,
        executionTimeMs: Double,
        metadata: RecordedMetadata = RecordedMetadata()
    ) {
        let output = RecordedOutput(
            algorithmId: algorithmId,
            reason: error.localizedDescription,
            executionTimeMs: executionTimeMs,
            success: false,
            error: error.localizedDescription
        )
        record(inputs: inputs, outputs: [output], metadata: metadata)
    }
    
    // MARK: - Query
    
    /// Get all recorded sessions
    public func allSessions() -> [RecordedSession] {
        sessions
    }
    
    /// Get recent sessions
    public func recentSessions(count: Int = 100) -> [RecordedSession] {
        Array(sessions.suffix(count))
    }
    
    /// Get sessions in date range
    public func sessions(from startDate: Date, to endDate: Date) -> [RecordedSession] {
        sessions.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
    }
    
    /// Get session count
    public var sessionCount: Int {
        sessions.count
    }
    
    // MARK: - Export
    
    /// Export all sessions as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(sessions)
    }
    
    /// Export recent sessions as JSON
    public func exportRecentJSON(count: Int = 100) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(recentSessions(count: count))
    }
    
    /// Export sessions in date range as JSON
    public func exportJSON(from startDate: Date, to endDate: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(sessions(from: startDate, to: endDate))
    }
    
    // MARK: - Import
    
    /// Import sessions from JSON
    public func importJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([RecordedSession].self, from: data)
        sessions.append(contentsOf: imported)
        
        // Trim to max size
        if sessions.count > maxSessions {
            sessions.removeFirst(sessions.count - maxSessions)
        }
        
        return imported.count
    }
    
    // MARK: - Maintenance
    
    /// Clear all recorded sessions
    public func clear() {
        sessions.removeAll()
    }
    
    /// Remove sessions older than date
    public func removeOlderThan(_ date: Date) -> Int {
        let before = sessions.count
        sessions.removeAll { $0.timestamp < date }
        return before - sessions.count
    }
    
    // MARK: - Fixture Export (ALG-SHADOW-011)
    
    /// Export a single session as a test fixture
    public func exportFixture(_ session: RecordedSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }
    
    /// Export session as fixture with generated filename
    public func exportFixtureWithName(_ session: RecordedSession) throws -> (filename: String, data: Data) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: session.timestamp)
        let algorithms = session.outputs.map { $0.algorithmId }.joined(separator: "-")
        let filename = "algorithm_fixture_\(timestamp)_\(algorithms).json"
        let data = try exportFixture(session)
        return (filename, data)
    }
    
    /// Export all sessions as individual fixtures
    public func exportAllFixtures() throws -> [(filename: String, data: Data)] {
        try sessions.map { try exportFixtureWithName($0) }
    }
    
    /// Create a sample fixture for testing
    public static func createSampleFixture(
        glucose: Double = 120,
        iob: Double = 1.0,
        cob: Double = 0,
        algorithmResults: [(id: String, rate: Double?, reason: String)] = [
            ("oref0", 1.0, "Sample oref0 result"),
            ("Loop", 1.2, "Sample Loop result")
        ]
    ) -> RecordedSession {
        let inputs = RecordedInputs(
            glucose: [RecordedGlucose(value: glucose, timestamp: Date(), trend: "flat")],
            insulinOnBoard: iob,
            carbsOnBoard: cob,
            profile: RecordedProfile(
                basalRates: [RecordedBasalRate(startTime: 0, rate: 1.0)],
                carbRatios: [RecordedCarbRatio(startTime: 0, ratio: 10)],
                sensitivityFactors: [RecordedSensitivityFactor(startTime: 0, factor: 50)],
                targetLow: 90,
                targetHigh: 110
            ),
            currentTime: Date()
        )
        
        let outputs = algorithmResults.map { result in
            RecordedOutput(
                algorithmId: result.id,
                tempBasalRate: result.rate,
                tempBasalDuration: 1800,
                reason: result.reason
            )
        }
        
        return RecordedSession(
            inputs: inputs,
            outputs: outputs,
            metadata: RecordedMetadata(
                appVersion: "test",
                platform: "fixture",
                notes: "Sample fixture for testing"
            )
        )
    }
    
    /// Generate multiple sample fixtures for test suite
    public static func generateTestFixtures() -> [RecordedSession] {
        [
            // Low glucose scenario
            createSampleFixture(
                glucose: 65,
                iob: 0.5,
                algorithmResults: [
                    ("oref0", 0, "Low glucose - suspend"),
                    ("Loop", 0, "Predicted low - zero temp")
                ]
            ),
            // In-range scenario
            createSampleFixture(
                glucose: 110,
                iob: 1.0,
                algorithmResults: [
                    ("oref0", 1.0, "In range - no change"),
                    ("Loop", 1.0, "Target achieved")
                ]
            ),
            // High glucose scenario
            createSampleFixture(
                glucose: 200,
                iob: 0.5,
                algorithmResults: [
                    ("oref0", 2.5, "High glucose - increase basal"),
                    ("Loop", 2.8, "Correction needed")
                ]
            ),
            // With carbs scenario
            createSampleFixture(
                glucose: 140,
                iob: 2.0,
                cob: 30,
                algorithmResults: [
                    ("oref0", 1.5, "Active carbs - moderate increase"),
                    ("Loop", 1.8, "COB absorption pending")
                ]
            )
        ]
    }
}
