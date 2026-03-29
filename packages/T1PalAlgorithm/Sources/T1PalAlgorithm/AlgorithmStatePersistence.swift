// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmStatePersistence.swift
// T1Pal Mobile
//
// Algorithm state persistence for IOB/COB/decision history
// Trace: PROD-AID-002, PRD-009

import Foundation

// MARK: - Persisted Algorithm State

/// Complete algorithm state snapshot for persistence
public struct PersistedAlgorithmState: Codable, Sendable, Equatable {
    /// Timestamp of this state snapshot
    public let timestamp: Date
    
    /// Current IOB value in units
    public let iob: Double
    
    /// IOB from basal adjustments
    public let basalIOB: Double?
    
    /// IOB from boluses
    public let bolusIOB: Double?
    
    /// Current COB value in grams
    public let cob: Double
    
    /// Active carbs remaining (decaying)
    public let activeCarbsRemaining: Double?
    
    /// Current glucose value (for context)
    public let currentGlucose: Double?
    
    /// Target glucose range
    public let targetLow: Double?
    public let targetHigh: Double?
    
    /// Last temp basal rate (U/hr)
    public let lastTempBasalRate: Double?
    
    /// Last temp basal start time
    public let lastTempBasalStart: Date?
    
    /// Algorithm version used
    public let algorithmVersion: String?
    
    /// Whether loop was active
    public let loopActive: Bool
    
    /// Autosens ratio (if enabled)
    public let autosensRatio: Double?
    
    public init(
        timestamp: Date = Date(),
        iob: Double,
        basalIOB: Double? = nil,
        bolusIOB: Double? = nil,
        cob: Double,
        activeCarbsRemaining: Double? = nil,
        currentGlucose: Double? = nil,
        targetLow: Double? = nil,
        targetHigh: Double? = nil,
        lastTempBasalRate: Double? = nil,
        lastTempBasalStart: Date? = nil,
        algorithmVersion: String? = nil,
        loopActive: Bool = true,
        autosensRatio: Double? = nil
    ) {
        self.timestamp = timestamp
        self.iob = iob
        self.basalIOB = basalIOB
        self.bolusIOB = bolusIOB
        self.cob = cob
        self.activeCarbsRemaining = activeCarbsRemaining
        self.currentGlucose = currentGlucose
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.lastTempBasalRate = lastTempBasalRate
        self.lastTempBasalStart = lastTempBasalStart
        self.algorithmVersion = algorithmVersion
        self.loopActive = loopActive
        self.autosensRatio = autosensRatio
    }
    
    /// Age of this state in seconds
    public var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    /// Whether state is stale (> 10 minutes old)
    public var isStale: Bool {
        age > 600  // 10 minutes
    }
    
    /// Whether state is very stale (> 30 minutes old)
    public var isVeryStale: Bool {
        age > 1800  // 30 minutes
    }
}

// MARK: - Algorithm Decision Record

/// Recorded algorithm decision for history/audit
/// Trace: ALG-AB-001 (algorithm identifier for A/B testing)
public struct AlgorithmDecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    
    /// Algorithm that made this decision (for A/B testing comparison)
    public let algorithmOrigin: AlgorithmOrigin
    
    /// Decision type
    public let decisionType: AlgorithmDecisionType
    
    /// Suggested temp basal rate (U/hr)
    public let suggestedTempBasalRate: Double?
    
    /// Suggested temp basal duration (seconds)
    public let suggestedTempBasalDuration: TimeInterval?
    
    /// Suggested SMB (units)
    public let suggestedSMB: Double?
    
    /// Algorithm reason string
    public let reason: String
    
    /// IOB at decision time
    public let iobAtDecision: Double
    
    /// COB at decision time
    public let cobAtDecision: Double
    
    /// Current glucose at decision time
    public let glucoseAtDecision: Double?
    
    /// Whether decision was enacted
    public let enacted: Bool
    
    /// Enactment timestamp (if enacted)
    public let enactedAt: Date?
    
    /// Failure reason if not enacted
    public let failureReason: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        algorithmOrigin: AlgorithmOrigin = .loop,
        decisionType: AlgorithmDecisionType,
        suggestedTempBasalRate: Double? = nil,
        suggestedTempBasalDuration: TimeInterval? = nil,
        suggestedSMB: Double? = nil,
        reason: String,
        iobAtDecision: Double,
        cobAtDecision: Double,
        glucoseAtDecision: Double? = nil,
        enacted: Bool = false,
        enactedAt: Date? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.algorithmOrigin = algorithmOrigin
        self.decisionType = decisionType
        self.suggestedTempBasalRate = suggestedTempBasalRate
        self.suggestedTempBasalDuration = suggestedTempBasalDuration
        self.suggestedSMB = suggestedSMB
        self.reason = reason
        self.iobAtDecision = iobAtDecision
        self.cobAtDecision = cobAtDecision
        self.glucoseAtDecision = glucoseAtDecision
        self.enacted = enacted
        self.enactedAt = enactedAt
        self.failureReason = failureReason
    }
}

/// Algorithm decision type
public enum AlgorithmDecisionType: String, Codable, Sendable, CaseIterable {
    case tempBasal = "temp_basal"
    case smb = "smb"
    case suspend = "suspend"
    case resume = "resume"
    case noAction = "no_action"
}

// MARK: - Loop Cycle Record

/// Record of a complete loop cycle
public struct LoopCycleRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    
    /// Cycle duration in seconds
    public let duration: TimeInterval
    
    /// Whether cycle completed successfully
    public let success: Bool
    
    /// Error message if failed
    public let errorMessage: String?
    
    /// CGM data age at cycle start (seconds)
    public let cgmDataAge: TimeInterval?
    
    /// Decision made during this cycle
    public let decisionID: UUID?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval,
        success: Bool,
        errorMessage: String? = nil,
        cgmDataAge: TimeInterval? = nil,
        decisionID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.success = success
        self.errorMessage = errorMessage
        self.cgmDataAge = cgmDataAge
        self.decisionID = decisionID
    }
}

// MARK: - Algorithm State Store Protocol

/// Protocol for algorithm state persistence
public protocol AlgorithmStateStore: Sendable {
    /// Save current algorithm state
    func saveState(_ state: PersistedAlgorithmState) async throws
    
    /// Load most recent algorithm state
    func loadState() async throws -> PersistedAlgorithmState?
    
    /// Clear current state
    func clearState() async throws
    
    /// Save decision record
    func saveDecision(_ decision: AlgorithmDecisionRecord) async throws
    
    /// Load recent decisions (last N hours)
    func loadDecisions(hours: Int) async throws -> [AlgorithmDecisionRecord]
    
    /// Save loop cycle record
    func saveCycle(_ cycle: LoopCycleRecord) async throws
    
    /// Load recent cycles (last N hours)
    func loadCycles(hours: Int) async throws -> [LoopCycleRecord]
    
    /// Clear all history older than specified hours
    func clearHistory(olderThan hours: Int) async throws
}

// MARK: - Algorithm State Errors

/// Errors for algorithm state operations
public enum AlgorithmStateError: Error, LocalizedError {
    case stateNotFound
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileWriteFailed(Error)
    case fileReadFailed(Error)
    case invalidData
    case stateStale(age: TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .stateNotFound:
            return "Algorithm state not found"
        case .encodingFailed(let error):
            return "Failed to encode state: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode state: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to write state file: \(error.localizedDescription)"
        case .fileReadFailed(let error):
            return "Failed to read state file: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid algorithm state data"
        case .stateStale(let age):
            return "Algorithm state is stale (\(Int(age / 60)) minutes old)"
        }
    }
}

// MARK: - In-Memory Store

/// In-memory implementation for testing
public actor InMemoryAlgorithmStateStore: AlgorithmStateStore {
    private var currentState: PersistedAlgorithmState?
    private var decisions: [AlgorithmDecisionRecord] = []
    private var cycles: [LoopCycleRecord] = []
    
    public init() {}
    
    public func saveState(_ state: PersistedAlgorithmState) async throws {
        currentState = state
    }
    
    public func loadState() async throws -> PersistedAlgorithmState? {
        return currentState
    }
    
    public func clearState() async throws {
        currentState = nil
    }
    
    public func saveDecision(_ decision: AlgorithmDecisionRecord) async throws {
        decisions.append(decision)
    }
    
    public func loadDecisions(hours: Int) async throws -> [AlgorithmDecisionRecord] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return decisions.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func saveCycle(_ cycle: LoopCycleRecord) async throws {
        cycles.append(cycle)
    }
    
    public func loadCycles(hours: Int) async throws -> [LoopCycleRecord] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return cycles.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func clearHistory(olderThan hours: Int) async throws {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        decisions = decisions.filter { $0.timestamp >= cutoff }
        cycles = cycles.filter { $0.timestamp >= cutoff }
    }
    
    /// Testing helper - get decision count
    public func getDecisionCount() -> Int {
        decisions.count
    }
    
    /// Testing helper - get cycle count
    public func getCycleCount() -> Int {
        cycles.count
    }
}

// MARK: - File-Based Store

/// File-based implementation for production
public actor FileAlgorithmStateStore: AlgorithmStateStore {
    private let stateURL: URL
    private let decisionsURL: URL
    private let cyclesURL: URL
    
    private var cachedState: PersistedAlgorithmState?
    private var cachedDecisions: [AlgorithmDecisionRecord]?
    private var cachedCycles: [LoopCycleRecord]?
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init(directory: URL? = nil) throws {
        let baseDir: URL
        if let dir = directory {
            baseDir = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseDir = appSupport.appendingPathComponent("T1Pal/Algorithm", isDirectory: true)
        }
        
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        self.stateURL = baseDir.appendingPathComponent("algorithm-state.json")
        self.decisionsURL = baseDir.appendingPathComponent("algorithm-decisions.json")
        self.cyclesURL = baseDir.appendingPathComponent("loop-cycles.json")
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    public func saveState(_ state: PersistedAlgorithmState) async throws {
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        cachedState = state
    }
    
    public func loadState() async throws -> PersistedAlgorithmState? {
        if let cached = cachedState {
            return cached
        }
        
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: stateURL)
            let state = try decoder.decode(PersistedAlgorithmState.self, from: data)
            cachedState = state
            return state
        } catch {
            throw AlgorithmStateError.decodingFailed(error)
        }
    }
    
    public func clearState() async throws {
        cachedState = nil
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }
    }
    
    public func saveDecision(_ decision: AlgorithmDecisionRecord) async throws {
        var decisions = try await loadAllDecisions()
        decisions.append(decision)
        
        let data = try encoder.encode(decisions)
        try data.write(to: decisionsURL, options: .atomic)
        cachedDecisions = decisions
    }
    
    public func loadDecisions(hours: Int) async throws -> [AlgorithmDecisionRecord] {
        let all = try await loadAllDecisions()
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return all.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func loadAllDecisions() async throws -> [AlgorithmDecisionRecord] {
        if let cached = cachedDecisions {
            return cached
        }
        
        guard FileManager.default.fileExists(atPath: decisionsURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: decisionsURL)
        let decisions = try decoder.decode([AlgorithmDecisionRecord].self, from: data)
        cachedDecisions = decisions
        return decisions
    }
    
    public func saveCycle(_ cycle: LoopCycleRecord) async throws {
        var cycles = try await loadAllCycles()
        cycles.append(cycle)
        
        let data = try encoder.encode(cycles)
        try data.write(to: cyclesURL, options: .atomic)
        cachedCycles = cycles
    }
    
    public func loadCycles(hours: Int) async throws -> [LoopCycleRecord] {
        let all = try await loadAllCycles()
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        return all.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func loadAllCycles() async throws -> [LoopCycleRecord] {
        if let cached = cachedCycles {
            return cached
        }
        
        guard FileManager.default.fileExists(atPath: cyclesURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: cyclesURL)
        let cycles = try decoder.decode([LoopCycleRecord].self, from: data)
        cachedCycles = cycles
        return cycles
    }
    
    public func clearHistory(olderThan hours: Int) async throws {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        
        // Filter decisions
        var decisions = try await loadAllDecisions()
        decisions = decisions.filter { $0.timestamp >= cutoff }
        let decisionData = try encoder.encode(decisions)
        try decisionData.write(to: decisionsURL, options: .atomic)
        cachedDecisions = decisions
        
        // Filter cycles
        var cycles = try await loadAllCycles()
        cycles = cycles.filter { $0.timestamp >= cutoff }
        let cycleData = try encoder.encode(cycles)
        try cycleData.write(to: cyclesURL, options: .atomic)
        cachedCycles = cycles
    }
}

// MARK: - Algorithm State Manager

/// High-level manager for algorithm state
public actor AlgorithmStateManager {
    private let store: AlgorithmStateStore
    
    /// Default retention period in hours
    public static let defaultRetentionHours = 72  // 3 days
    
    /// Maximum decisions to keep
    public static let maxDecisions = 1000
    
    public init(store: AlgorithmStateStore) {
        self.store = store
    }
    
    /// Create in-memory manager for testing
    public static func inMemory() -> AlgorithmStateManager {
        AlgorithmStateManager(store: InMemoryAlgorithmStateStore())
    }
    
    /// Create file-based manager for production
    public static func fileBased() throws -> AlgorithmStateManager {
        let store = try FileAlgorithmStateStore()
        return AlgorithmStateManager(store: store)
    }
    
    // MARK: - State Operations
    
    /// Update algorithm state from IOB/COB values
    public func updateState(
        iob: Double,
        basalIOB: Double? = nil,
        bolusIOB: Double? = nil,
        cob: Double,
        currentGlucose: Double? = nil,
        targetLow: Double? = nil,
        targetHigh: Double? = nil,
        loopActive: Bool = true
    ) async throws {
        let state = PersistedAlgorithmState(
            iob: iob,
            basalIOB: basalIOB,
            bolusIOB: bolusIOB,
            cob: cob,
            currentGlucose: currentGlucose,
            targetLow: targetLow,
            targetHigh: targetHigh,
            loopActive: loopActive
        )
        try await store.saveState(state)
    }
    
    /// Get current algorithm state
    public func getCurrentState() async throws -> PersistedAlgorithmState? {
        try await store.loadState()
    }
    
    /// Get current IOB (returns 0 if state is stale)
    public func getCurrentIOB() async -> Double {
        guard let state = try? await store.loadState(),
              !state.isStale else {
            return 0
        }
        return state.iob
    }
    
    /// Get current COB (returns 0 if state is stale)
    public func getCurrentCOB() async -> Double {
        guard let state = try? await store.loadState(),
              !state.isStale else {
            return 0
        }
        return state.cob
    }
    
    /// Check if loop is currently active
    public func isLoopActive() async -> Bool {
        guard let state = try? await store.loadState(),
              !state.isVeryStale else {
            return false
        }
        return state.loopActive
    }
    
    // MARK: - Decision Recording
    
    /// Record an algorithm decision
    public func recordDecision(
        decisionType: AlgorithmDecisionType,
        suggestedTempBasalRate: Double? = nil,
        suggestedTempBasalDuration: TimeInterval? = nil,
        suggestedSMB: Double? = nil,
        reason: String,
        iobAtDecision: Double,
        cobAtDecision: Double,
        glucoseAtDecision: Double? = nil
    ) async throws -> UUID {
        let decision = AlgorithmDecisionRecord(
            decisionType: decisionType,
            suggestedTempBasalRate: suggestedTempBasalRate,
            suggestedTempBasalDuration: suggestedTempBasalDuration,
            suggestedSMB: suggestedSMB,
            reason: reason,
            iobAtDecision: iobAtDecision,
            cobAtDecision: cobAtDecision,
            glucoseAtDecision: glucoseAtDecision
        )
        try await store.saveDecision(decision)
        return decision.id
    }
    
    /// Get recent decisions
    public func getRecentDecisions(hours: Int = 6) async throws -> [AlgorithmDecisionRecord] {
        try await store.loadDecisions(hours: hours)
    }
    
    // MARK: - Cycle Recording
    
    /// Record a loop cycle
    public func recordCycle(
        duration: TimeInterval,
        success: Bool,
        errorMessage: String? = nil,
        cgmDataAge: TimeInterval? = nil,
        decisionID: UUID? = nil
    ) async throws {
        let cycle = LoopCycleRecord(
            duration: duration,
            success: success,
            errorMessage: errorMessage,
            cgmDataAge: cgmDataAge,
            decisionID: decisionID
        )
        try await store.saveCycle(cycle)
    }
    
    /// Get recent cycles
    public func getRecentCycles(hours: Int = 6) async throws -> [LoopCycleRecord] {
        try await store.loadCycles(hours: hours)
    }
    
    // MARK: - Statistics
    
    /// Get algorithm statistics for the last N hours
    public func getStatistics(hours: Int = 24) async throws -> AlgorithmStatistics {
        let decisions = try await store.loadDecisions(hours: hours)
        let cycles = try await store.loadCycles(hours: hours)
        
        return AlgorithmStatistics(decisions: decisions, cycles: cycles)
    }
    
    // MARK: - Maintenance
    
    /// Clean up old data
    public func performMaintenance() async throws {
        try await store.clearHistory(olderThan: Self.defaultRetentionHours)
    }
}

// MARK: - Algorithm Statistics

/// Statistics calculated from algorithm history
public struct AlgorithmStatistics: Sendable {
    public let totalDecisions: Int
    public let tempBasalDecisions: Int
    public let smbDecisions: Int
    public let noActionDecisions: Int
    public let enactedDecisions: Int
    public let failedDecisions: Int
    
    public let totalCycles: Int
    public let successfulCycles: Int
    public let failedCycles: Int
    public let averageCycleDuration: TimeInterval
    
    /// Percentage of successful cycles
    public var successRate: Double {
        guard totalCycles > 0 else { return 0 }
        return Double(successfulCycles) / Double(totalCycles) * 100
    }
    
    /// Percentage of decisions enacted
    public var enactmentRate: Double {
        let enactable = tempBasalDecisions + smbDecisions
        guard enactable > 0 else { return 0 }
        return Double(enactedDecisions) / Double(enactable) * 100
    }
    
    public init(decisions: [AlgorithmDecisionRecord], cycles: [LoopCycleRecord]) {
        self.totalDecisions = decisions.count
        self.tempBasalDecisions = decisions.filter { $0.decisionType == .tempBasal }.count
        self.smbDecisions = decisions.filter { $0.decisionType == .smb }.count
        self.noActionDecisions = decisions.filter { $0.decisionType == .noAction }.count
        self.enactedDecisions = decisions.filter { $0.enacted }.count
        self.failedDecisions = decisions.filter { !$0.enacted && ($0.decisionType == .tempBasal || $0.decisionType == .smb) }.count
        
        self.totalCycles = cycles.count
        self.successfulCycles = cycles.filter { $0.success }.count
        self.failedCycles = cycles.filter { !$0.success }.count
        
        let totalDuration = cycles.reduce(0.0) { $0 + $1.duration }
        self.averageCycleDuration = cycles.isEmpty ? 0 : totalDuration / Double(cycles.count)
    }
}

// MARK: - A/B Testing Comparison (ALG-AB-003)

/// Historical time-in-range comparison between algorithms over a period
/// Trace: ALG-AB-003
public struct AlgorithmTIRComparison: Codable, Sendable, Equatable {
    /// Period analyzed
    public let startDate: Date
    public let endDate: Date
    
    /// Results per algorithm
    public let algorithmResults: [AlgorithmTIRResult]
    
    /// Total glucose readings analyzed
    public let totalReadings: Int
    
    public init(
        startDate: Date,
        endDate: Date,
        algorithmResults: [AlgorithmTIRResult],
        totalReadings: Int
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.algorithmResults = algorithmResults
        self.totalReadings = totalReadings
    }
    
    /// Get result for a specific algorithm
    public func result(for origin: AlgorithmOrigin) -> AlgorithmTIRResult? {
        algorithmResults.first { $0.algorithmOrigin == origin }
    }
    
    /// Best performing algorithm by TIR
    public var bestByTIR: AlgorithmTIRResult? {
        algorithmResults.max { $0.timeInRange < $1.timeInRange }
    }
}

/// TIR statistics for a single algorithm
public struct AlgorithmTIRResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String { algorithmOrigin.rawValue }
    
    /// Algorithm identifier
    public let algorithmOrigin: AlgorithmOrigin
    
    /// Time in range (70-180 mg/dL) as decimal (0.0-1.0)
    public let timeInRange: Double
    
    /// Time below range (<70 mg/dL) as decimal
    public let timeBelowRange: Double
    
    /// Time above range (>180 mg/dL) as decimal
    public let timeAboveRange: Double
    
    /// Average glucose (mg/dL)
    public let averageGlucose: Double
    
    /// Glucose Management Indicator (estimated A1c)
    public let gmi: Double
    
    /// Coefficient of variation (glucose variability)
    public let cv: Double
    
    /// Number of decisions made by this algorithm
    public let decisionCount: Int
    
    /// Number of decisions enacted
    public let enactedCount: Int
    
    public init(
        algorithmOrigin: AlgorithmOrigin,
        timeInRange: Double,
        timeBelowRange: Double,
        timeAboveRange: Double,
        averageGlucose: Double,
        gmi: Double,
        cv: Double,
        decisionCount: Int,
        enactedCount: Int
    ) {
        self.algorithmOrigin = algorithmOrigin
        self.timeInRange = timeInRange
        self.timeBelowRange = timeBelowRange
        self.timeAboveRange = timeAboveRange
        self.averageGlucose = averageGlucose
        self.gmi = gmi
        self.cv = cv
        self.decisionCount = decisionCount
        self.enactedCount = enactedCount
    }
    
    /// Time in range as percentage string
    public var tirPercentage: String {
        String(format: "%.1f%%", timeInRange * 100)
    }
    
    /// Enactment rate as percentage
    public var enactmentRate: Double {
        guard decisionCount > 0 else { return 0 }
        return Double(enactedCount) / Double(decisionCount)
    }
}
