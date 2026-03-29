// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopFacade.swift
// T1Pal Mobile
//
// Unified control loop interface
// Requirements: REQ-AID-002, REQ-ALGO-003
//
// Trace: ALG-014, PRD-005

import Foundation
import T1PalCore

// MARK: - Loop Decision

/// Complete decision from the loop facade
public struct LoopDecision: Sendable {
    /// Timestamp of the decision
    public let timestamp: Date
    
    /// Algorithm that made the decision
    public let algorithmName: String
    
    /// Algorithm version
    public let algorithmVersion: String
    
    /// Raw decision from algorithm (before safety)
    public let rawDecision: AlgorithmDecision
    
    /// Decision after safety limits applied
    public let safeDecision: SafeDecision
    
    /// Safety reasons if limits were applied
    public let safetyReasons: [String]
    
    /// Whether the loop is suspended
    public let isSuspended: Bool
    
    /// Execution duration
    public let executionTime: TimeInterval
    
    public init(
        timestamp: Date = Date(),
        algorithmName: String,
        algorithmVersion: String,
        rawDecision: AlgorithmDecision,
        safeDecision: SafeDecision,
        safetyReasons: [String] = [],
        isSuspended: Bool = false,
        executionTime: TimeInterval = 0
    ) {
        self.timestamp = timestamp
        self.algorithmName = algorithmName
        self.algorithmVersion = algorithmVersion
        self.rawDecision = rawDecision
        self.safeDecision = safeDecision
        self.safetyReasons = safetyReasons
        self.isSuspended = isSuspended
        self.executionTime = executionTime
    }
}

/// Safe decision after limits applied
public struct SafeDecision: Sendable {
    public let tempBasal: TempBasal?
    public let bolus: Double?
    public let reason: String
    public let predictions: GlucosePredictions?
    
    public init(
        tempBasal: TempBasal? = nil,
        bolus: Double? = nil,
        reason: String,
        predictions: GlucosePredictions? = nil
    ) {
        self.tempBasal = tempBasal
        self.bolus = bolus
        self.reason = reason
        self.predictions = predictions
    }
}

// MARK: - Loop State

/// Current state of the loop
public enum LoopState: String, Sendable {
    case idle
    case running
    case suspended
    case error
}

// MARK: - Loop Facade

/// Unified interface for control loop execution
/// Routes to active algorithm via registry and applies safety limits
public final class LoopFacade: @unchecked Sendable {
    
    /// Shared singleton instance
    public static let shared = LoopFacade()
    
    // Dependencies
    private let registry: AlgorithmRegistry
    private let safetyGuardian: SafetyGuardian
    private let auditLog: SafetyAuditLog
    private let decisionLog: DecisionLog
    
    // State
    private let lock = NSLock()
    private var _state: LoopState = .idle
    private var _lastDecision: LoopDecision?
    private var _isSuspended: Bool = false
    private var observers: [(LoopDecision) -> Void] = []
    
    // MARK: - Initialization
    
    public init(
        registry: AlgorithmRegistry = .shared,
        safetyLimits: SafetyLimits = .default
    ) {
        self.registry = registry
        self.safetyGuardian = SafetyGuardian(limits: safetyLimits)
        self.auditLog = SafetyAuditLog()
        self.decisionLog = DecisionLog()
    }
    
    /// Create for testing with custom registry
    public static func createForTesting(
        registry: AlgorithmRegistry? = nil,
        safetyLimits: SafetyLimits = .default
    ) -> LoopFacade {
        return LoopFacade(
            registry: registry ?? AlgorithmRegistry.createForTesting(),
            safetyLimits: safetyLimits
        )
    }
    
    // MARK: - State
    
    /// Current loop state
    public var state: LoopState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }
    
    /// Whether the loop is manually suspended
    public var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSuspended
    }
    
    /// Last decision made by the loop
    public var lastDecision: LoopDecision? {
        lock.lock()
        defer { lock.unlock() }
        return _lastDecision
    }
    
    /// Active algorithm name
    public var activeAlgorithmName: String? {
        registry.activeAlgorithmName
    }
    
    // MARK: - Control
    
    /// Suspend the loop
    public func suspend(reason: String = "User requested") {
        lock.lock()
        _isSuspended = true
        _state = .suspended
        lock.unlock()
        
        auditLog.log(SafetyAuditEntry(
            eventType: "loop_suspended",
            reason: reason
        ))
    }
    
    /// Resume the loop
    public func resume() {
        lock.lock()
        _isSuspended = false
        _state = .idle
        lock.unlock()
        
        auditLog.log(SafetyAuditEntry(
            eventType: "loop_resumed",
            reason: "User resumed"
        ))
    }
    
    // MARK: - Execution
    
    /// Execute the loop with given inputs
    /// - Parameter inputs: Algorithm inputs
    /// - Returns: Complete loop decision with safety applied
    /// - Throws: LoopError if execution fails
    public func execute(_ inputs: AlgorithmInputs) throws -> LoopDecision {
        let startTime = Date()
        
        // Check if suspended
        guard !isSuspended else {
            throw LoopError.loopSuspended
        }
        
        // Get active algorithm
        guard let algorithm = registry.activeAlgorithm else {
            throw LoopError.noActiveAlgorithm
        }
        
        // Update state
        lock.lock()
        _state = .running
        lock.unlock()
        
        defer {
            lock.lock()
            _state = _isSuspended ? .suspended : .idle
            lock.unlock()
        }
        
        // Validate inputs
        let validationErrors = algorithm.validate(inputs)
        if !validationErrors.isEmpty {
            throw LoopError.validationFailed(errors: validationErrors)
        }
        
        // Get current glucose for safety checks
        guard let currentGlucose = inputs.glucose.first?.glucose else {
            throw LoopError.noGlucoseData
        }
        
        // Execute algorithm
        let rawDecision: AlgorithmDecision
        do {
            rawDecision = try algorithm.calculate(inputs)
        } catch {
            lock.lock()
            _state = .error
            lock.unlock()
            throw LoopError.algorithmError(error)
        }
        
        // Apply safety limits
        let (safeRate, safeBolus, suspended, safetyReasons) = safetyGuardian.validateDecision(
            suggestedRate: rawDecision.suggestedTempBasal?.rate,
            suggestedBolus: rawDecision.suggestedBolus,
            currentIOB: inputs.insulinOnBoard,
            currentGlucose: currentGlucose,
            minPredBG: rawDecision.predictions?.zt.min() ?? currentGlucose
        )
        
        // Build safe decision
        let safeTempBasal: TempBasal?
        if let rate = safeRate {
            safeTempBasal = TempBasal(
                rate: rate,
                duration: rawDecision.suggestedTempBasal?.duration ?? 30 * 60
            )
        } else {
            safeTempBasal = nil
        }
        
        var safeReason = rawDecision.reason
        if !safetyReasons.isEmpty {
            safeReason += " | Safety: " + safetyReasons.joined(separator: "; ")
        }
        
        let safeDecision = SafeDecision(
            tempBasal: safeTempBasal,
            bolus: safeBolus,
            reason: safeReason,
            predictions: rawDecision.predictions
        )
        
        // Log safety events
        for reason in safetyReasons {
            auditLog.log(SafetyAuditEntry(
                eventType: "safety_limit_applied",
                originalValue: rawDecision.suggestedTempBasal?.rate,
                limitedValue: safeRate,
                reason: reason
            ))
        }
        
        // Build complete decision
        let executionTime = Date().timeIntervalSince(startTime)
        let loopDecision = LoopDecision(
            algorithmName: algorithm.name,
            algorithmVersion: algorithm.version,
            rawDecision: rawDecision,
            safeDecision: safeDecision,
            safetyReasons: safetyReasons,
            isSuspended: suspended,
            executionTime: executionTime
        )
        
        // Log decision
        decisionLog.log(loopDecision)
        
        // Update state
        lock.lock()
        _lastDecision = loopDecision
        lock.unlock()
        
        // Notify observers
        notifyObservers(loopDecision)
        
        return loopDecision
    }
    
    // MARK: - Observers
    
    /// Add an observer for loop decisions
    public func addObserver(_ observer: @escaping (LoopDecision) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }
    
    /// Remove all observers
    public func removeAllObservers() {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll()
    }
    
    private func notifyObservers(_ decision: LoopDecision) {
        let obs = lock.withLock { observers }
        for observer in obs {
            observer(decision)
        }
    }
    
    // MARK: - Logs
    
    /// Get recent safety audit entries
    public func recentSafetyEvents(count: Int = 50) -> [SafetyAuditEntry] {
        auditLog.recentEntries(count: count)
    }
    
    /// Get recent decisions
    public func recentDecisions(count: Int = 50) -> [LoopDecision] {
        decisionLog.recentDecisions(count: count)
    }
    
    /// Get decisions by algorithm
    public func decisions(byAlgorithm name: String, count: Int = 50) -> [LoopDecision] {
        decisionLog.decisions(byAlgorithm: name, count: count)
    }
}

// MARK: - Loop Errors

/// Errors from loop execution
public enum LoopError: Error, Sendable, LocalizedError {
    case loopSuspended
    case noActiveAlgorithm
    case noGlucoseData
    case validationFailed(errors: [AlgorithmError])
    case algorithmError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .loopSuspended:
            return "Closed loop is currently suspended."
        case .noActiveAlgorithm:
            return "No dosing algorithm is active."
        case .noGlucoseData:
            return "No recent glucose data available."
        case .validationFailed(let errors):
            let messages = errors.compactMap { $0.errorDescription }.joined(separator: "; ")
            return "Algorithm validation failed: \(messages)"
        case .algorithmError(let error):
            return "Algorithm error: \(error.localizedDescription)"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance

extension LoopError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .algorithm }
    
    public var code: String {
        switch self {
        case .loopSuspended: return "LOOP-STATE-001"
        case .noActiveAlgorithm: return "LOOP-CONFIG-001"
        case .noGlucoseData: return "LOOP-DATA-001"
        case .validationFailed: return "LOOP-VALID-001"
        case .algorithmError: return "LOOP-EXEC-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .loopSuspended: return .warning
        case .noActiveAlgorithm: return .critical
        case .noGlucoseData: return .error
        case .validationFailed: return .critical
        case .algorithmError: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .loopSuspended: return .none  // User intentionally suspended
        case .noActiveAlgorithm: return .checkDevice
        case .noGlucoseData: return .checkDevice
        case .validationFailed: return .contactSupport
        case .algorithmError: return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown loop error"
    }
}

// MARK: - Decision Log

/// Thread-safe log of loop decisions
public final class DecisionLog: @unchecked Sendable {
    private var decisions: [LoopDecision] = []
    private let lock = NSLock()
    private let maxEntries: Int
    
    public init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }
    
    public func log(_ decision: LoopDecision) {
        lock.lock()
        defer { lock.unlock() }
        
        decisions.append(decision)
        
        if decisions.count > maxEntries {
            decisions.removeFirst(decisions.count - maxEntries)
        }
    }
    
    public func recentDecisions(count: Int = 50) -> [LoopDecision] {
        lock.lock()
        defer { lock.unlock() }
        return Array(decisions.suffix(count))
    }
    
    public func decisions(byAlgorithm name: String, count: Int = 50) -> [LoopDecision] {
        lock.lock()
        defer { lock.unlock() }
        return decisions.filter { $0.algorithmName == name }.suffix(count).map { $0 }
    }
    
    public func decisionsSince(_ date: Date) -> [LoopDecision] {
        lock.lock()
        defer { lock.unlock() }
        return decisions.filter { $0.timestamp >= date }
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        decisions.removeAll()
    }
}

// MARK: - NSLock Extension

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
