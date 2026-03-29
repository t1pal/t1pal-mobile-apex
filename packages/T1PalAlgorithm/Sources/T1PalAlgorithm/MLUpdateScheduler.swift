// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLUpdateScheduler.swift
// T1PalAlgorithm
//
// Schedules periodic ML model retraining based on data freshness and model age.
// Coordinates MLDataCollector, MLTrainingPipeline, and MLModelStorage.
//
// Trace: ALG-SHADOW-031, PRD-028

import Foundation

// MARK: - Scheduler Configuration

/// Configuration for ML update scheduling
public struct MLUpdateSchedulerConfig: Codable, Sendable {
    /// Minimum interval between training attempts (seconds)
    public let minTrainingInterval: TimeInterval
    
    /// Default training interval (weekly)
    public let defaultTrainingInterval: TimeInterval
    
    /// Minimum new data rows required since last training
    public let minNewDataRows: Int
    
    /// Model age threshold to trigger retraining (days)
    public let maxModelAgeDays: Int
    
    /// Whether to enable automatic scheduling
    public let autoScheduleEnabled: Bool
    
    /// Algorithm ID to train for
    public let algorithmId: String
    
    public init(
        minTrainingInterval: TimeInterval = 86400,       // 1 day minimum
        defaultTrainingInterval: TimeInterval = 604800,  // 7 days (weekly)
        minNewDataRows: Int = 288,                       // 1 day of data
        maxModelAgeDays: Int = 90,
        autoScheduleEnabled: Bool = true,
        algorithmId: String = "parity-loop"
    ) {
        self.minTrainingInterval = minTrainingInterval
        self.defaultTrainingInterval = defaultTrainingInterval
        self.minNewDataRows = minNewDataRows
        self.maxModelAgeDays = maxModelAgeDays
        self.autoScheduleEnabled = autoScheduleEnabled
        self.algorithmId = algorithmId
    }
    
    public static let `default` = MLUpdateSchedulerConfig()
    
    /// Weekly schedule
    public static let weekly = MLUpdateSchedulerConfig(
        defaultTrainingInterval: 604800  // 7 days
    )
    
    /// Daily schedule (for testing)
    public static let daily = MLUpdateSchedulerConfig(
        minTrainingInterval: 3600,       // 1 hour minimum
        defaultTrainingInterval: 86400   // 1 day
    )
}

// MARK: - Schedule Status

/// Current status of the update schedule
public struct MLScheduleStatus: Sendable {
    public let isEnabled: Bool
    public let lastTrainingDate: Date?
    public let nextScheduledDate: Date?
    public let isEligibleNow: Bool
    public let eligibilityReason: EligibilityReason
    public let currentModelAge: Int?  // Days
    public let newDataRowsSinceLastTraining: Int
    
    public enum EligibilityReason: String, Sendable {
        case eligible = "Ready for training"
        case insufficientData = "Not enough new data"
        case tooSoon = "Too soon since last training"
        case modelFresh = "Current model is fresh"
        case disabled = "Scheduling disabled"
        case noCollector = "No data collector available"
    }
}

// MARK: - Training Trigger

/// What triggered a training run
public enum TrainingTrigger: String, Codable, Sendable {
    case scheduled = "Scheduled"
    case manual = "Manual"
    case modelExpired = "Model expired"
    case dataThreshold = "Data threshold reached"
}

// MARK: - ML Update Scheduler

/// Schedules and coordinates ML model updates
public actor MLUpdateScheduler {
    
    // MARK: - State
    
    private let config: MLUpdateSchedulerConfig
    private var lastTrainingDate: Date?
    private var lastTrainingResult: MLTrainingResult?
    private var rowCountAtLastTraining: Int = 0
    private var isTrainingInProgress: Bool = false
    private var scheduledTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(config: MLUpdateSchedulerConfig = .default) {
        self.config = config
    }
    
    // MARK: - Status
    
    /// Get current schedule status
    public func status(
        collector: MLDataCollector,
        storage: MLModelStorage
    ) async -> MLScheduleStatus {
        let stats = await collector.statistics()
        let activeModel = await storage.activeVersion()
        
        let modelAge = activeModel.map { version in
            Calendar.current.dateComponents([.day], from: version.createdAt, to: Date()).day ?? 0
        }
        
        let newRows = stats.trainingReadyCount - rowCountAtLastTraining
        let eligibility = checkEligibility(
            stats: stats,
            modelAge: modelAge,
            newRows: newRows
        )
        
        let nextDate = lastTrainingDate.map { last in
            last.addingTimeInterval(config.defaultTrainingInterval)
        }
        
        return MLScheduleStatus(
            isEnabled: config.autoScheduleEnabled,
            lastTrainingDate: lastTrainingDate,
            nextScheduledDate: nextDate,
            isEligibleNow: eligibility.isEligible,
            eligibilityReason: eligibility.reason,
            currentModelAge: modelAge,
            newDataRowsSinceLastTraining: max(0, newRows)
        )
    }
    
    // MARK: - Eligibility Check
    
    private func checkEligibility(
        stats: MLCollectionStats,
        modelAge: Int?,
        newRows: Int
    ) -> (isEligible: Bool, reason: MLScheduleStatus.EligibilityReason) {
        guard config.autoScheduleEnabled else {
            return (false, .disabled)
        }
        
        // Check if too soon since last training
        if let lastDate = lastTrainingDate {
            let elapsed = Date().timeIntervalSince(lastDate)
            if elapsed < config.minTrainingInterval {
                return (false, .tooSoon)
            }
        }
        
        // Check model expiration
        if let age = modelAge, age >= config.maxModelAgeDays {
            return (true, .eligible)
        }
        
        // Check if enough new data
        if newRows < config.minNewDataRows {
            return (false, .insufficientData)
        }
        
        // Check if model is still fresh (< 50% of max age)
        if let age = modelAge, age < config.maxModelAgeDays / 2 {
            return (false, .modelFresh)
        }
        
        return (true, .eligible)
    }
    
    // MARK: - Training Execution
    
    /// Check eligibility and run training if appropriate
    public func runIfEligible(
        collector: MLDataCollector,
        pipeline: MLTrainingPipeline,
        storage: MLModelStorage,
        trigger: TrainingTrigger = .scheduled
    ) async -> MLTrainingResult? {
        let status = await self.status(collector: collector, storage: storage)
        
        guard status.isEligibleNow || trigger == .manual else {
            return nil
        }
        
        return await runTraining(
            collector: collector,
            pipeline: pipeline,
            storage: storage,
            trigger: trigger
        )
    }
    
    /// Force a training run regardless of eligibility
    public func runTraining(
        collector: MLDataCollector,
        pipeline: MLTrainingPipeline,
        storage: MLModelStorage,
        trigger: TrainingTrigger
    ) async -> MLTrainingResult {
        guard !isTrainingInProgress else {
            return .failure("Training already in progress")
        }
        
        isTrainingInProgress = true
        defer { isTrainingInProgress = false }
        
        // Record row count before training
        let stats = await collector.statistics()
        
        do {
            // Prepare data
            let preparedData = try await pipeline.prepareTrainingData(
                collector: collector,
                algorithmId: config.algorithmId
            )
            
            // Train
            let result = await pipeline.train(
                preparedData: preparedData,
                algorithmId: config.algorithmId
            )
            
            // Save if successful
            if result.success {
                _ = try await pipeline.saveToStorage(storage, result: result)
                
                // Update tracking
                lastTrainingDate = Date()
                rowCountAtLastTraining = stats.trainingReadyCount
            }
            
            lastTrainingResult = result
            return result
            
        } catch {
            let result = MLTrainingResult.failure(error.localizedDescription)
            lastTrainingResult = result
            return result
        }
    }
    
    // MARK: - Background Scheduling
    
    /// Start periodic background scheduling
    public func startScheduling(
        collector: MLDataCollector,
        pipeline: MLTrainingPipeline,
        storage: MLModelStorage,
        checkInterval: TimeInterval = 3600  // Check hourly
    ) {
        stopScheduling()
        
        guard config.autoScheduleEnabled else { return }
        
        scheduledTask = Task { [weak self] in
            while !Task.isCancelled {
                // Wait for check interval
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                // Check and run if eligible
                _ = await self?.runIfEligible(
                    collector: collector,
                    pipeline: pipeline,
                    storage: storage,
                    trigger: .scheduled
                )
            }
        }
    }
    
    /// Stop periodic background scheduling
    public func stopScheduling() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }
    
    // MARK: - State Management
    
    /// Reset scheduler state
    public func reset() {
        lastTrainingDate = nil
        lastTrainingResult = nil
        rowCountAtLastTraining = 0
        stopScheduling()
    }
    
    /// Get last training result
    public var lastResult: MLTrainingResult? {
        lastTrainingResult
    }
    
    /// Check if training is currently in progress
    public var isTraining: Bool {
        isTrainingInProgress
    }
    
    // MARK: - Persistence
    
    /// State for persistence
    public struct PersistedState: Codable, Sendable {
        public let lastTrainingDate: Date?
        public let rowCountAtLastTraining: Int
    }
    
    /// Export state for persistence
    public func exportState() -> PersistedState {
        PersistedState(
            lastTrainingDate: lastTrainingDate,
            rowCountAtLastTraining: rowCountAtLastTraining
        )
    }
    
    /// Import persisted state
    public func importState(_ state: PersistedState) {
        lastTrainingDate = state.lastTrainingDate
        rowCountAtLastTraining = state.rowCountAtLastTraining
    }
}

// MARK: - Convenience Extensions

extension MLUpdateScheduler {
    
    /// Calculate next scheduled training date
    public func nextScheduledDate() -> Date? {
        guard config.autoScheduleEnabled else { return nil }
        
        if let lastDate = lastTrainingDate {
            return lastDate.addingTimeInterval(config.defaultTrainingInterval)
        }
        
        // If never trained, schedule for now
        return Date()
    }
    
    /// Days until next scheduled training
    public func daysUntilNextTraining() -> Int? {
        guard let nextDate = nextScheduledDate() else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day
    }
}
