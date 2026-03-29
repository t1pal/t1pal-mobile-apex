// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLDataCollector.swift
// T1PalAlgorithm
//
// Privacy-preserving on-device ML data collector for algorithm training.
// Collects inputs, decisions, and outcomes without sending data off-device.
//
// Trace: ALG-SHADOW-021

import Foundation
import T1PalCore

// MARK: - ML Data Collector Configuration

/// Configuration for ML data collection
public struct MLDataCollectorConfig: Codable, Sendable {
    /// Maximum number of pending rows (awaiting outcomes)
    public let maxPendingRows: Int
    
    /// Maximum number of completed rows to retain
    public let maxCompletedRows: Int
    
    /// Outcome tracking window (how long to wait for glucose outcomes)
    public let outcomeWindow: TimeInterval
    
    /// Minimum data quality score to keep row
    public let minQualityScore: Double
    
    /// Whether to collect data in shadow mode (non-enacted recommendations)
    public let collectShadowMode: Bool
    
    /// Whether collection is enabled
    public let isEnabled: Bool
    
    public init(
        maxPendingRows: Int = 288,              // 24 hours at 5-min intervals
        maxCompletedRows: Int = 4032,           // 14 days at 5-min intervals
        outcomeWindow: TimeInterval = 2 * 3600, // 2 hours
        minQualityScore: Double = 0.5,
        collectShadowMode: Bool = true,
        isEnabled: Bool = true
    ) {
        self.maxPendingRows = maxPendingRows
        self.maxCompletedRows = maxCompletedRows
        self.outcomeWindow = outcomeWindow
        self.minQualityScore = minQualityScore
        self.collectShadowMode = collectShadowMode
        self.isEnabled = isEnabled
    }
    
    public static let `default` = MLDataCollectorConfig()
}

// MARK: - Pending Outcome Tracker

/// Tracks a row awaiting outcome data
struct PendingOutcomeEntry: Codable, Sendable {
    let row: MLTrainingDataRow
    let targetTimes: [Date]  // Times to capture glucose (30, 60, 90, 120 min)
    let expiresAt: Date
    
    init(row: MLTrainingDataRow, outcomeWindow: TimeInterval) {
        self.row = row
        let base = row.timestamp
        self.targetTimes = [
            base.addingTimeInterval(30 * 60),
            base.addingTimeInterval(60 * 60),
            base.addingTimeInterval(90 * 60),
            base.addingTimeInterval(120 * 60)
        ]
        self.expiresAt = base.addingTimeInterval(outcomeWindow + 300) // 5 min grace
    }
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Collection Statistics

/// Statistics about ML data collection
public struct MLCollectionStats: Codable, Sendable {
    /// Number of rows pending outcomes
    public let pendingCount: Int
    
    /// Number of completed (training-ready) rows
    public let completedCount: Int
    
    /// Number of rows with complete outcomes
    public let trainingReadyCount: Int
    
    /// Total rows collected (including discarded)
    public let totalCollected: Int
    
    /// Rows discarded due to low quality
    public let discardedLowQuality: Int
    
    /// Rows expired without complete outcomes
    public let expiredIncomplete: Int
    
    /// Collection started timestamp
    public let collectionStarted: Date?
    
    /// Most recent collection timestamp
    public let lastCollected: Date?
    
    /// Average quality score
    public let averageQualityScore: Double
    
    public init(
        pendingCount: Int = 0,
        completedCount: Int = 0,
        trainingReadyCount: Int = 0,
        totalCollected: Int = 0,
        discardedLowQuality: Int = 0,
        expiredIncomplete: Int = 0,
        collectionStarted: Date? = nil,
        lastCollected: Date? = nil,
        averageQualityScore: Double = 0
    ) {
        self.pendingCount = pendingCount
        self.completedCount = completedCount
        self.trainingReadyCount = trainingReadyCount
        self.totalCollected = totalCollected
        self.discardedLowQuality = discardedLowQuality
        self.expiredIncomplete = expiredIncomplete
        self.collectionStarted = collectionStarted
        self.lastCollected = lastCollected
        self.averageQualityScore = averageQualityScore
    }
}

// MARK: - ML Data Collector Actor

/// Privacy-preserving on-device ML data collector.
///
/// Collects algorithm inputs, decisions, and outcomes for training personalized ML models.
/// All data remains on-device unless explicitly exported by the user.
///
/// Usage:
/// ```swift
/// let collector = MLDataCollector()
///
/// // Record a decision
/// await collector.record(inputs: inputs, decision: decision, algorithmId: "Loop", wasEnacted: true)
///
/// // Update outcomes when new glucose arrives
/// await collector.updateOutcomes(glucoseHistory: recentGlucose)
///
/// // Export training data
/// let dataset = await collector.exportDataset(algorithmId: "Loop")
/// ```
public actor MLDataCollector {
    
    // MARK: - Storage
    
    /// Pending rows awaiting outcome data
    private var pendingRows: [UUID: PendingOutcomeEntry] = [:]
    
    /// Completed rows with outcome data
    private var completedRows: [MLTrainingDataRow] = []
    
    /// Configuration
    private var config: MLDataCollectorConfig
    
    /// Statistics
    private var totalCollected: Int = 0
    private var discardedLowQuality: Int = 0
    private var expiredIncomplete: Int = 0
    private var collectionStarted: Date?
    private var lastCollected: Date?
    
    // MARK: - Initialization
    
    public init(config: MLDataCollectorConfig = .default) {
        self.config = config
    }
    
    // MARK: - Configuration
    
    /// Update collector configuration
    public func configure(_ newConfig: MLDataCollectorConfig) {
        self.config = newConfig
    }
    
    /// Check if collection is enabled
    public var isEnabled: Bool {
        config.isEnabled
    }
    
    // MARK: - Recording
    
    /// Record algorithm inputs and decision.
    /// The row will be stored as pending until outcome data is available.
    ///
    /// - Parameters:
    ///   - inputs: Algorithm inputs at time of decision
    ///   - decision: Algorithm's dosing decision
    ///   - algorithmId: Identifier of the algorithm
    ///   - wasEnacted: Whether the recommendation was enacted
    /// - Returns: The created training row (for testing/verification)
    @discardableResult
    public func record(
        inputs: AlgorithmInputs,
        decision: AlgorithmDecision,
        algorithmId: String,
        wasEnacted: Bool
    ) -> MLTrainingDataRow? {
        guard config.isEnabled else { return nil }
        
        // Skip shadow mode if not configured
        if !wasEnacted && !config.collectShadowMode {
            return nil
        }
        
        // Create training row
        let row = MLTrainingDataRow.from(
            inputs: inputs,
            decision: decision,
            algorithmId: algorithmId,
            wasEnacted: wasEnacted
        )
        
        // Check quality threshold
        if row.qualityScore < config.minQualityScore {
            discardedLowQuality += 1
            return nil
        }
        
        // Track timestamps
        if collectionStarted == nil {
            collectionStarted = Date()
        }
        lastCollected = Date()
        totalCollected += 1
        
        // Add to pending
        let entry = PendingOutcomeEntry(row: row, outcomeWindow: config.outcomeWindow)
        pendingRows[row.id] = entry
        
        // Trim pending if over limit
        trimPendingIfNeeded()
        
        return row
    }
    
    /// Record from shadow run result (multiple algorithms)
    public func recordShadowRun(
        inputs: AlgorithmInputs,
        result: ShadowRunResult,
        primaryAlgorithmId: String?
    ) {
        guard config.isEnabled && config.collectShadowMode else { return }
        
        for recommendation in result.recommendations where recommendation.success {
            let isPrimary = recommendation.algorithmId == primaryAlgorithmId
            
            // Create a decision from the shadow recommendation
            let decision = AlgorithmDecision(
                suggestedTempBasal: recommendation.suggestedTempBasalRate.map { rate in
                    T1PalAlgorithm.TempBasal(
                        rate: rate,
                        duration: recommendation.suggestedTempBasalDuration ?? 1800
                    )
                },
                suggestedBolus: recommendation.suggestedBolus,
                reason: recommendation.reason
            )
            
            record(
                inputs: inputs,
                decision: decision,
                algorithmId: recommendation.algorithmId,
                wasEnacted: isPrimary  // Only primary was enacted
            )
        }
    }
    
    // MARK: - Outcome Updates
    
    /// Update pending rows with new glucose data.
    /// Call this whenever new glucose readings arrive.
    ///
    /// - Parameter glucoseHistory: Recent glucose readings (newest first), with dates
    public func updateOutcomes(glucoseHistory: [(date: Date, glucose: Double)]) {
        guard config.isEnabled else { return }
        
        let now = Date()
        var completedIds: [UUID] = []
        
        for (id, entry) in pendingRows {
            // Check if expired
            if entry.isExpired {
                expiredIncomplete += 1
                completedIds.append(id)
                continue
            }
            
            // Try to fill outcomes
            var glucose30: Double? = nil
            var glucose60: Double? = nil
            var glucose90: Double? = nil
            var glucose120: Double? = nil
            var outcomeGlucose: [Double] = []
            
            for (targetIdx, targetTime) in entry.targetTimes.enumerated() {
                // Find closest glucose reading within 5 minutes of target
                let closest = glucoseHistory.min(by: { a, b in
                    abs(a.date.timeIntervalSince(targetTime)) < abs(b.date.timeIntervalSince(targetTime))
                })
                
                if let reading = closest,
                   abs(reading.date.timeIntervalSince(targetTime)) <= 5 * 60 {
                    switch targetIdx {
                    case 0: glucose30 = reading.glucose
                    case 1: glucose60 = reading.glucose
                    case 2: glucose90 = reading.glucose
                    case 3: glucose120 = reading.glucose
                    default: break
                    }
                }
            }
            
            // Collect all glucose in outcome window for TIR calculation
            let windowStart = entry.row.timestamp
            let windowEnd = windowStart.addingTimeInterval(config.outcomeWindow)
            outcomeGlucose = glucoseHistory
                .filter { $0.date >= windowStart && $0.date <= windowEnd }
                .map { $0.glucose }
            
            // Check if we have all required outcomes (at least 30, 60, 90 min)
            if glucose30 != nil && glucose60 != nil && glucose90 != nil {
                let completedRow = entry.row.withOutcomes(
                    glucose30min: glucose30,
                    glucose60min: glucose60,
                    glucose90min: glucose90,
                    glucose120min: glucose120,
                    glucoseHistory: outcomeGlucose
                )
                
                completedRows.append(completedRow)
                completedIds.append(id)
            }
            
            // Also complete if 120 min has passed (even with partial data)
            if now.timeIntervalSince(entry.row.timestamp) > 120 * 60 {
                let completedRow = entry.row.withOutcomes(
                    glucose30min: glucose30,
                    glucose60min: glucose60,
                    glucose90min: glucose90,
                    glucose120min: glucose120,
                    glucoseHistory: outcomeGlucose
                )
                
                completedRows.append(completedRow)
                completedIds.append(id)
            }
        }
        
        // Remove completed/expired from pending
        for id in completedIds {
            pendingRows.removeValue(forKey: id)
        }
        
        // Trim completed if over limit
        trimCompletedIfNeeded()
    }
    
    // MARK: - Export
    
    /// Export collected data as a training dataset.
    ///
    /// - Parameters:
    ///   - algorithmId: Filter by algorithm ID (nil for all)
    ///   - trainingReadyOnly: Only include rows with complete outcomes
    /// - Returns: Training dataset
    public func exportDataset(
        algorithmId: String? = nil,
        trainingReadyOnly: Bool = true
    ) -> MLTrainingDataset {
        var rows = completedRows
        
        // Filter by algorithm
        if let algId = algorithmId {
            rows = rows.filter { $0.algorithmId == algId }
        }
        
        // Filter to training-ready
        if trainingReadyOnly {
            rows = rows.filter { $0.isTrainingReady }
        }
        
        return MLTrainingDataset(
            rows: rows,
            algorithmId: algorithmId ?? "mixed",
            version: "1.0"
        )
    }
    
    /// Export as CSV string
    public func exportCSV(
        algorithmId: String? = nil,
        trainingReadyOnly: Bool = true
    ) -> String {
        let dataset = exportDataset(algorithmId: algorithmId, trainingReadyOnly: trainingReadyOnly)
        return trainingReadyOnly ? dataset.toTrainingCSV() : dataset.toCSV()
    }
    
    // MARK: - Statistics
    
    /// Get collection statistics
    public func statistics() -> MLCollectionStats {
        let trainingReadyCount = completedRows.filter { $0.isTrainingReady }.count
        let avgQuality = completedRows.isEmpty ? 0 : 
            completedRows.map { $0.qualityScore }.reduce(0, +) / Double(completedRows.count)
        
        return MLCollectionStats(
            pendingCount: pendingRows.count,
            completedCount: completedRows.count,
            trainingReadyCount: trainingReadyCount,
            totalCollected: totalCollected,
            discardedLowQuality: discardedLowQuality,
            expiredIncomplete: expiredIncomplete,
            collectionStarted: collectionStarted,
            lastCollected: lastCollected,
            averageQualityScore: avgQuality
        )
    }
    
    // MARK: - Management
    
    /// Clear all collected data
    public func clearAll() {
        pendingRows.removeAll()
        completedRows.removeAll()
        totalCollected = 0
        discardedLowQuality = 0
        expiredIncomplete = 0
        collectionStarted = nil
        lastCollected = nil
    }
    
    /// Clear only pending data (keep completed)
    public func clearPending() {
        pendingRows.removeAll()
    }
    
    /// Get count of rows ready for training
    public var trainingReadyCount: Int {
        completedRows.filter { $0.isTrainingReady }.count
    }
    
    /// Check if minimum training data threshold is met
    /// Requires at least 14 days of data (4032 rows at 5-min intervals)
    public var hasMinimumTrainingData: Bool {
        trainingReadyCount >= 4032
    }
    
    // MARK: - Persistence
    
    /// Save collected data to file
    public func save(to url: URL) throws {
        let data = CollectorState(
            pendingRows: Array(pendingRows.values),
            completedRows: completedRows,
            totalCollected: totalCollected,
            discardedLowQuality: discardedLowQuality,
            expiredIncomplete: expiredIncomplete,
            collectionStarted: collectionStarted,
            lastCollected: lastCollected
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }
    
    /// Load collected data from file
    public func load(from url: URL) throws {
        let jsonData = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(CollectorState.self, from: jsonData)
        
        self.pendingRows = Dictionary(uniqueKeysWithValues: state.pendingRows.map { ($0.row.id, $0) })
        self.completedRows = state.completedRows
        self.totalCollected = state.totalCollected
        self.discardedLowQuality = state.discardedLowQuality
        self.expiredIncomplete = state.expiredIncomplete
        self.collectionStarted = state.collectionStarted
        self.lastCollected = state.lastCollected
    }
    
    // MARK: - Private
    
    private func trimPendingIfNeeded() {
        if pendingRows.count > config.maxPendingRows {
            // Remove oldest entries
            let sorted = pendingRows.values.sorted { $0.row.timestamp < $1.row.timestamp }
            let toRemove = sorted.prefix(pendingRows.count - config.maxPendingRows)
            for entry in toRemove {
                pendingRows.removeValue(forKey: entry.row.id)
                expiredIncomplete += 1
            }
        }
    }
    
    private func trimCompletedIfNeeded() {
        if completedRows.count > config.maxCompletedRows {
            // Keep newest rows
            let excess = completedRows.count - config.maxCompletedRows
            completedRows.removeFirst(excess)
        }
    }
}

// MARK: - Collector State (Persistence)

struct CollectorState: Codable {
    let pendingRows: [PendingOutcomeEntry]
    let completedRows: [MLTrainingDataRow]
    let totalCollected: Int
    let discardedLowQuality: Int
    let expiredIncomplete: Int
    let collectionStarted: Date?
    let lastCollected: Date?
}


