// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BackgroundLoopExecutor.swift
// T1Pal Mobile
//
// Background loop execution using BGProcessingTask
// Requirements: PROD-AID-001, REQ-AID-002
//
// Trace: PROD-AID-001, PRD-009

import Foundation
import T1PalCore

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// MARK: - Background Loop Task Identifiers

/// Background task identifiers for AID loop
public enum LoopTaskIdentifier {
    /// Main loop processing task (5-minute cycle)
    public static let loopProcess = "com.t1pal.aid.loop"
    
    /// Extended algorithm processing task
    public static let algorithmProcess = "com.t1pal.aid.algorithm"
    
    /// Pump communication task
    public static let pumpCommunication = "com.t1pal.aid.pump"
}

// MARK: - Background Loop Configuration

/// Configuration for background loop execution
public struct BackgroundLoopConfiguration: Sendable, Codable {
    /// Target loop interval in seconds (default: 5 minutes)
    public let loopInterval: TimeInterval
    
    /// Maximum time allowed for loop execution in seconds
    public let maxExecutionTime: TimeInterval
    
    /// Whether to require external power for processing
    public let requiresExternalPower: Bool
    
    /// Whether to require network connectivity
    public let requiresNetwork: Bool
    
    /// Minimum battery level required (0-100)
    public let minimumBatteryLevel: Int
    
    /// Whether to allow cellular data
    public let allowsCellular: Bool
    
    /// Maximum consecutive failures before pausing
    public let maxConsecutiveFailures: Int
    
    public init(
        loopInterval: TimeInterval = 300,  // 5 minutes
        maxExecutionTime: TimeInterval = 30,  // 30 seconds max
        requiresExternalPower: Bool = false,
        requiresNetwork: Bool = false,
        minimumBatteryLevel: Int = 10,
        allowsCellular: Bool = true,
        maxConsecutiveFailures: Int = 3
    ) {
        self.loopInterval = loopInterval
        self.maxExecutionTime = maxExecutionTime
        self.requiresExternalPower = requiresExternalPower
        self.requiresNetwork = requiresNetwork
        self.minimumBatteryLevel = minimumBatteryLevel
        self.allowsCellular = allowsCellular
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }
    
    /// Default AID loop configuration
    public static let `default` = BackgroundLoopConfiguration()
    
    /// Aggressive configuration for better timing adherence
    public static let aggressive = BackgroundLoopConfiguration(
        loopInterval: 300,
        maxExecutionTime: 45,
        requiresExternalPower: false,
        requiresNetwork: false,
        minimumBatteryLevel: 5,
        allowsCellular: true,
        maxConsecutiveFailures: 5
    )
    
    /// Conservative configuration for battery preservation
    public static let conservative = BackgroundLoopConfiguration(
        loopInterval: 300,
        maxExecutionTime: 20,
        requiresExternalPower: false,
        requiresNetwork: false,
        minimumBatteryLevel: 20,
        allowsCellular: true,
        maxConsecutiveFailures: 2
    )
}

// MARK: - Loop Execution State

/// Current state of the background loop executor
public enum LoopExecutionState: String, Sendable, Codable, CaseIterable {
    case idle = "idle"
    case scheduled = "scheduled"
    case running = "running"
    case paused = "paused"
    case suspended = "suspended"
    case error = "error"
}

// MARK: - Loop Execution Result

/// Result of a background loop execution
public struct LoopExecutionResult: Sendable {
    /// Whether the execution was successful
    public let success: Bool
    
    /// Timestamp of execution
    public let timestamp: Date
    
    /// Execution duration in seconds
    public let duration: TimeInterval
    
    /// Loop iteration result (if available)
    public let loopResult: LoopIterationSummary?
    
    /// Error message (if failed)
    public let errorMessage: String?
    
    /// Whether a dose was enacted
    public let doseEnacted: Bool
    
    public init(
        success: Bool,
        timestamp: Date = Date(),
        duration: TimeInterval = 0,
        loopResult: LoopIterationSummary? = nil,
        errorMessage: String? = nil,
        doseEnacted: Bool = false
    ) {
        self.success = success
        self.timestamp = timestamp
        self.duration = duration
        self.loopResult = loopResult
        self.errorMessage = errorMessage
        self.doseEnacted = doseEnacted
    }
    
    /// Create success result
    public static func success(
        duration: TimeInterval,
        loopResult: LoopIterationSummary?,
        doseEnacted: Bool
    ) -> LoopExecutionResult {
        LoopExecutionResult(
            success: true,
            duration: duration,
            loopResult: loopResult,
            doseEnacted: doseEnacted
        )
    }
    
    /// Create failure result
    public static func failure(_ message: String, duration: TimeInterval = 0) -> LoopExecutionResult {
        LoopExecutionResult(
            success: false,
            duration: duration,
            errorMessage: message
        )
    }
}

/// Summary of a loop iteration (for persistence)
public struct LoopIterationSummary: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let glucose: Double?
    public let iob: Double
    public let cob: Double
    public let suggestedTempBasal: Double?
    public let suggestedSMB: Double?
    public let enacted: Bool
    public let reason: String
    
    public init(
        timestamp: Date = Date(),
        glucose: Double? = nil,
        iob: Double = 0,
        cob: Double = 0,
        suggestedTempBasal: Double? = nil,
        suggestedSMB: Double? = nil,
        enacted: Bool = false,
        reason: String = ""
    ) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.iob = iob
        self.cob = cob
        self.suggestedTempBasal = suggestedTempBasal
        self.suggestedSMB = suggestedSMB
        self.enacted = enacted
        self.reason = reason
    }
}

// MARK: - Loop Execution History

/// History of loop executions
public struct LoopExecutionHistory: Sendable, Codable {
    public var entries: [LoopExecutionHistoryEntry]
    
    /// Maximum number of entries to keep
    public static let maxEntries = 288  // 24 hours at 5-min intervals
    
    public init(entries: [LoopExecutionHistoryEntry] = []) {
        self.entries = entries
    }
    
    /// Add a new entry
    public mutating func addEntry(_ entry: LoopExecutionHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }
    
    /// Get entries from the last N hours
    public func entries(lastHours: Int) -> [LoopExecutionHistoryEntry] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastHours * 3600))
        return entries.filter { $0.timestamp >= cutoff }
    }
    
    /// Calculate success rate for last N hours
    public func successRate(lastHours: Int = 1) -> Double {
        let recent = entries(lastHours: lastHours)
        guard !recent.isEmpty else { return 0 }
        let successes = recent.filter { $0.success }.count
        return Double(successes) / Double(recent.count) * 100
    }
    
    /// Get average loop interval
    public func averageInterval(lastHours: Int = 1) -> TimeInterval {
        let recent = entries(lastHours: lastHours).sorted { $0.timestamp > $1.timestamp }
        guard recent.count >= 2 else { return 0 }
        
        var totalInterval: TimeInterval = 0
        for i in 0..<(recent.count - 1) {
            totalInterval += recent[i].timestamp.timeIntervalSince(recent[i + 1].timestamp)
        }
        return totalInterval / Double(recent.count - 1)
    }
}

/// Single entry in loop execution history
public struct LoopExecutionHistoryEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let success: Bool
    public let duration: TimeInterval
    public let doseEnacted: Bool
    public let glucose: Double?
    public let errorMessage: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        success: Bool,
        duration: TimeInterval,
        doseEnacted: Bool = false,
        glucose: Double? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.success = success
        self.duration = duration
        self.doseEnacted = doseEnacted
        self.glucose = glucose
        self.errorMessage = errorMessage
    }
}

// MARK: - Loop Execution Statistics

/// Statistics for loop execution
public struct LoopExecutionStatistics: Sendable {
    public let totalExecutions: Int
    public let successfulExecutions: Int
    public let failedExecutions: Int
    public let dosesEnacted: Int
    public let averageDuration: TimeInterval
    public let successRate: Double
    public let averageInterval: TimeInterval
    public let lastExecutionTime: Date?
    
    public init(
        totalExecutions: Int,
        successfulExecutions: Int,
        failedExecutions: Int,
        dosesEnacted: Int,
        averageDuration: TimeInterval,
        successRate: Double,
        averageInterval: TimeInterval,
        lastExecutionTime: Date?
    ) {
        self.totalExecutions = totalExecutions
        self.successfulExecutions = successfulExecutions
        self.failedExecutions = failedExecutions
        self.dosesEnacted = dosesEnacted
        self.averageDuration = averageDuration
        self.successRate = successRate
        self.averageInterval = averageInterval
        self.lastExecutionTime = lastExecutionTime
    }
    
    /// Create from history
    public static func from(history: LoopExecutionHistory, lastHours: Int = 24) -> LoopExecutionStatistics {
        let entries = history.entries(lastHours: lastHours)
        let total = entries.count
        let successful = entries.filter { $0.success }.count
        let failed = total - successful
        let enacted = entries.filter { $0.doseEnacted }.count
        let avgDuration = entries.isEmpty ? 0 : entries.reduce(0.0) { $0 + $1.duration } / Double(total)
        let rate = total == 0 ? 0 : Double(successful) / Double(total) * 100
        let interval = history.averageInterval(lastHours: lastHours)
        let lastTime = entries.first?.timestamp
        
        return LoopExecutionStatistics(
            totalExecutions: total,
            successfulExecutions: successful,
            failedExecutions: failed,
            dosesEnacted: enacted,
            averageDuration: avgDuration,
            successRate: rate,
            averageInterval: interval,
            lastExecutionTime: lastTime
        )
    }
}

// MARK: - Background Loop Executor Protocol

/// Protocol for background loop execution
public protocol BackgroundLoopExecutorProtocol: Sendable {
    /// Current execution state
    var state: LoopExecutionState { get async }
    
    /// Current configuration
    var configuration: BackgroundLoopConfiguration { get async }
    
    /// Start background loop execution
    func start() async throws
    
    /// Stop background loop execution
    func stop() async
    
    /// Pause execution (temporary stop)
    func pause() async
    
    /// Resume after pause
    func resume() async throws
    
    /// Execute a single loop iteration
    func executeLoop() async -> LoopExecutionResult
    
    /// Get execution statistics
    func getStatistics(lastHours: Int) async -> LoopExecutionStatistics
    
    /// Get execution history
    func getHistory() async -> LoopExecutionHistory
}

// MARK: - Background Loop Executor

/// Main implementation of background loop execution
public actor BackgroundLoopExecutor: BackgroundLoopExecutorProtocol {
    
    // MARK: - State
    
    public private(set) var state: LoopExecutionState = .idle
    public private(set) var configuration: BackgroundLoopConfiguration
    
    private var history: LoopExecutionHistory = LoopExecutionHistory()
    private var consecutiveFailures: Int = 0
    private var lastExecutionTime: Date?
    
    // MARK: - Dependencies
    
    private var loopHandler: (@Sendable () async -> LoopExecutionResult)?
    
    // MARK: - Callbacks
    
    public var onExecutionComplete: (@Sendable (LoopExecutionResult) -> Void)?
    public var onStateChange: (@Sendable (LoopExecutionState) -> Void)?
    public var onError: (@Sendable (String) -> Void)?
    
    // MARK: - Initialization
    
    public init(configuration: BackgroundLoopConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Configure the loop handler
    public func configure(loopHandler: @escaping @Sendable () async -> LoopExecutionResult) {
        self.loopHandler = loopHandler
    }
    
    /// Update configuration
    public func updateConfiguration(_ config: BackgroundLoopConfiguration) {
        self.configuration = config
    }
    
    // MARK: - Lifecycle
    
    public func start() async throws {
        guard state == .idle || state == .suspended else {
            throw LoopExecutorError.invalidState(current: state, expected: .idle)
        }
        
        setState(.scheduled)
        scheduleBackgroundTask()
    }
    
    public func stop() async {
        setState(.idle)
        cancelBackgroundTask()
        consecutiveFailures = 0
    }
    
    public func pause() async {
        guard state == .running || state == .scheduled else { return }
        setState(.paused)
    }
    
    public func resume() async throws {
        guard state == .paused else {
            throw LoopExecutorError.invalidState(current: state, expected: .paused)
        }
        
        consecutiveFailures = 0
        setState(.scheduled)
        scheduleBackgroundTask()
    }
    
    // MARK: - Loop Execution
    
    public func executeLoop() async -> LoopExecutionResult {
        let startTime = Date()
        setState(.running)
        
        defer {
            if state == .running {
                setState(.scheduled)
                scheduleBackgroundTask()
            }
        }
        
        // Check for handler
        guard let handler = loopHandler else {
            let result = LoopExecutionResult.failure("Loop handler not configured")
            recordExecution(result)
            return result
        }
        
        // Execute the loop
        let result = await handler()
        let duration = Date().timeIntervalSince(startTime)
        
        // Update result with actual duration
        let finalResult = LoopExecutionResult(
            success: result.success,
            timestamp: startTime,
            duration: duration,
            loopResult: result.loopResult,
            errorMessage: result.errorMessage,
            doseEnacted: result.doseEnacted
        )
        
        recordExecution(finalResult)
        
        // Handle failures
        if !finalResult.success {
            consecutiveFailures += 1
            if consecutiveFailures >= configuration.maxConsecutiveFailures {
                setState(.error)
                onError?("Too many consecutive failures (\(consecutiveFailures))")
            }
        } else {
            consecutiveFailures = 0
        }
        
        onExecutionComplete?(finalResult)
        return finalResult
    }
    
    // MARK: - Statistics
    
    public func getStatistics(lastHours: Int = 24) async -> LoopExecutionStatistics {
        return LoopExecutionStatistics.from(history: history, lastHours: lastHours)
    }
    
    public func getHistory() async -> LoopExecutionHistory {
        return history
    }
    
    /// Get consecutive failure count
    public func getConsecutiveFailures() -> Int {
        return consecutiveFailures
    }
    
    /// Reset consecutive failures
    public func resetFailures() {
        consecutiveFailures = 0
    }
    
    // MARK: - Private Helpers
    
    private func setState(_ newState: LoopExecutionState) {
        state = newState
        onStateChange?(newState)
    }
    
    private func recordExecution(_ result: LoopExecutionResult) {
        let entry = LoopExecutionHistoryEntry(
            success: result.success,
            duration: result.duration,
            doseEnacted: result.doseEnacted,
            glucose: result.loopResult?.glucose,
            errorMessage: result.errorMessage
        )
        history.addEntry(entry)
        lastExecutionTime = result.timestamp
    }
    
    private func scheduleBackgroundTask() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard #available(iOS 13.0, *) else { return }
        
        let request = BGProcessingTaskRequest(identifier: LoopTaskIdentifier.loopProcess)
        request.requiresExternalPower = configuration.requiresExternalPower
        request.requiresNetworkConnectivity = configuration.requiresNetwork
        request.earliestBeginDate = Date(timeIntervalSinceNow: configuration.loopInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            onError?("Failed to schedule background task: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func cancelBackgroundTask() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard #available(iOS 13.0, *) else { return }
        
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: LoopTaskIdentifier.loopProcess)
        #endif
    }
}

// MARK: - Loop Executor Errors

/// Errors for loop executor operations
public enum LoopExecutorError: Error, LocalizedError {
    case invalidState(current: LoopExecutionState, expected: LoopExecutionState)
    case notConfigured
    case executionTimeout
    case schedulingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidState(let current, let expected):
            return "Invalid state: \(current.rawValue), expected \(expected.rawValue)"
        case .notConfigured:
            return "Loop executor not configured"
        case .executionTimeout:
            return "Loop execution timed out"
        case .schedulingFailed(let message):
            return "Failed to schedule background task: \(message)"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance

extension LoopExecutorError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .algorithm }
    
    public var code: String {
        switch self {
        case .invalidState: return "LOOP-STATE-001"
        case .notConfigured: return "LOOP-CONFIG-001"
        case .executionTimeout: return "LOOP-TIMEOUT-001"
        case .schedulingFailed: return "LOOP-SCHED-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .invalidState: return .warning
        case .notConfigured: return .error
        case .executionTimeout: return .error
        case .schedulingFailed: return .critical
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .invalidState: return .retry
        case .notConfigured: return .none
        case .executionTimeout: return .waitAndRetry
        case .schedulingFailed: return .checkDevice
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown loop executor error"
    }
}

// MARK: - Background Task Handler

#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks

/// Extension for handling background tasks
@available(iOS 13.0, *)
public extension BackgroundLoopExecutor {
    
    /// Register background task handlers
    /// Call this from AppDelegate.application(_:didFinishLaunchingWithOptions:)
    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LoopTaskIdentifier.loopProcess,
            using: nil
        ) { task in
            // This is handled by the app's main background task handler
            task.setTaskCompleted(success: true)
        }
    }
    
    /// Handle incoming background task
    /// - Parameter task: The background task to handle
    /// - Parameter executor: The executor to run
    static func handleBackgroundTask(
        _ task: BGProcessingTask,
        executor: BackgroundLoopExecutor
    ) {
        // Set up expiration handler
        task.expirationHandler = {
            Task {
                await executor.pause()
            }
        }
        
        // Execute the loop
        Task {
            let result = await executor.executeLoop()
            task.setTaskCompleted(success: result.success)
        }
    }
}
#endif

// MARK: - Mock Executor for Testing

/// Mock implementation for testing
public actor MockBackgroundLoopExecutor: BackgroundLoopExecutorProtocol {
    public private(set) var state: LoopExecutionState = .idle
    public private(set) var configuration: BackgroundLoopConfiguration
    
    private var history: LoopExecutionHistory = LoopExecutionHistory()
    public var mockResult: LoopExecutionResult?
    public var startCallCount = 0
    public var stopCallCount = 0
    public var executeCallCount = 0
    
    public init(configuration: BackgroundLoopConfiguration = .default) {
        self.configuration = configuration
    }
    
    public func start() async throws {
        startCallCount += 1
        state = .scheduled
    }
    
    public func stop() async {
        stopCallCount += 1
        state = .idle
    }
    
    public func pause() async {
        state = .paused
    }
    
    public func resume() async throws {
        state = .scheduled
    }
    
    public func executeLoop() async -> LoopExecutionResult {
        executeCallCount += 1
        state = .running
        let result = mockResult ?? LoopExecutionResult.success(
            duration: 2.0,
            loopResult: nil,
            doseEnacted: false
        )
        
        let entry = LoopExecutionHistoryEntry(
            success: result.success,
            duration: result.duration,
            doseEnacted: result.doseEnacted,
            glucose: result.loopResult?.glucose
        )
        history.addEntry(entry)
        
        state = .scheduled
        return result
    }
    
    public func getStatistics(lastHours: Int = 24) async -> LoopExecutionStatistics {
        return LoopExecutionStatistics.from(history: history, lastHours: lastHours)
    }
    
    public func getHistory() async -> LoopExecutionHistory {
        return history
    }
}
