/// Algorithm readiness states for AID loop execution
/// Pattern: Loop/LoopKit algorithm state and error handling
///
/// Determines if the algorithm can run, is degraded, or cannot execute.
/// Integrates with DeviceStatusElementState for UI representation.

import Foundation

// MARK: - AlgorithmReadiness

/// Represents the overall readiness state of the AID algorithm.
///
/// The algorithm can be in one of three states:
/// - `ready`: All inputs available, algorithm can execute normally
/// - `degraded`: Some inputs stale or missing, limited predictions
/// - `cannotRun`: Critical inputs missing, algorithm cannot execute
///
/// ## Usage
/// ```swift
/// let readiness = AlgorithmReadiness.evaluate(
///     glucoseFreshness: .glucose(lastReading: lastGlucose),
///     insulinFreshness: InsulinFreshness(lastDoseDate: lastDose),
///     hasPump: pumpManager != nil,
///     pumpSuspended: pumpStatus.suspended
/// )
///
/// switch readiness.state {
/// case .ready:
///     runAlgorithm()
/// case .degraded(let reasons):
///     runWithLimitedPredictions(reasons)
/// case .cannotRun(let reasons):
///     showError(reasons)
/// }
/// ```
public struct AlgorithmReadiness: Sendable, Equatable, Codable {
    
    /// Current readiness state
    public let state: State
    
    /// Timestamp when readiness was evaluated
    public let evaluatedAt: Date
    
    /// Individual component states
    public let components: Components
    
    /// Initialize with explicit state
    public init(state: State, evaluatedAt: Date = Date(), components: Components = .init()) {
        self.state = state
        self.evaluatedAt = evaluatedAt
        self.components = components
    }
    
    // MARK: - State Enum
    
    /// Algorithm readiness state
    public enum State: Sendable, Equatable, Codable {
        /// Algorithm ready to run with full functionality
        case ready
        
        /// Algorithm can run but with limited predictions/functionality
        case degraded([DegradedReason])
        
        /// Algorithm cannot run - missing critical inputs
        case cannotRun([CannotRunReason])
        
        /// Whether algorithm can execute (even if degraded)
        public var canExecute: Bool {
            switch self {
            case .ready, .degraded:
                return true
            case .cannotRun:
                return false
            }
        }
        
        /// Whether algorithm is at full functionality
        public var isFullyReady: Bool {
            if case .ready = self {
                return true
            }
            return false
        }
        
        /// Convert to DeviceStatusElementState for UI
        public var elementState: DeviceStatusElementState {
            switch self {
            case .ready:
                return .normalCGM  // Using CGM as algorithm is tied to glucose
            case .degraded:
                return .warning
            case .cannotRun:
                return .critical
            }
        }
    }
    
    // MARK: - Degraded Reasons
    
    /// Reasons the algorithm is running in degraded mode
    public enum DegradedReason: String, Sendable, Codable, CaseIterable {
        /// Glucose data is stale but usable (5-12 min old)
        case glucoseStale
        
        /// Insulin data is aging (recent activity > 1 hour old)
        case insulinDataAging
        
        /// Pump communication delayed (5-30 min since last)
        case pumpCommunicationDelayed
        
        /// Carb data unavailable (COB estimation limited)
        case carbDataUnavailable
        
        /// Glucose trend unreliable (momentum effect degraded)
        case glucoseTrendUnreliable
        
        /// CGM sensor in warmup or temporary issue
        case cgmTemporaryIssue
        
        /// Human-readable description
        public var localizedDescription: String {
            switch self {
            case .glucoseStale:
                return "Glucose data is stale"
            case .insulinDataAging:
                return "Insulin activity data is aging"
            case .pumpCommunicationDelayed:
                return "Pump communication delayed"
            case .carbDataUnavailable:
                return "Carb data unavailable"
            case .glucoseTrendUnreliable:
                return "Glucose trend unreliable"
            case .cgmTemporaryIssue:
                return "CGM has temporary issue"
            }
        }
    }
    
    // MARK: - Cannot Run Reasons
    
    /// Reasons the algorithm cannot run
    public enum CannotRunReason: String, Sendable, Codable, CaseIterable {
        /// No glucose data available
        case noGlucoseData
        
        /// Glucose data too old (>12 min)
        case glucoseExpired
        
        /// No pump configured
        case noPumpConfigured
        
        /// Pump is suspended
        case pumpSuspended
        
        /// Pump communication failed
        case pumpCommunicationFailed
        
        /// Missing basal schedule
        case missingBasalSchedule
        
        /// Missing insulin sensitivity
        case missingInsulinSensitivity
        
        /// Missing carb ratio
        case missingCarbRatio
        
        /// Missing glucose target
        case missingGlucoseTarget
        
        /// CGM sensor failed or expired
        case cgmSensorFailed
        
        /// Delivery outcome uncertain - must check pump history
        case uncertainDelivery
        
        /// Human-readable description
        public var localizedDescription: String {
            switch self {
            case .noGlucoseData:
                return "No glucose data available"
            case .glucoseExpired:
                return "Glucose data is too old"
            case .noPumpConfigured:
                return "No pump configured"
            case .pumpSuspended:
                return "Pump is suspended"
            case .pumpCommunicationFailed:
                return "Pump communication failed"
            case .missingBasalSchedule:
                return "Missing basal schedule"
            case .missingInsulinSensitivity:
                return "Missing insulin sensitivity"
            case .missingCarbRatio:
                return "Missing carb ratio"
            case .missingGlucoseTarget:
                return "Missing glucose target"
            case .cgmSensorFailed:
                return "CGM sensor failed or expired"
            case .uncertainDelivery:
                return "Uncertain delivery - check pump history"
            }
        }
        
        /// SF Symbol for this reason
        public var symbolName: String {
            switch self {
            case .noGlucoseData, .glucoseExpired, .cgmSensorFailed:
                return "drop.triangle.fill"
            case .noPumpConfigured, .pumpSuspended, .pumpCommunicationFailed, .uncertainDelivery:
                return "cross.circle.fill"
            case .missingBasalSchedule, .missingInsulinSensitivity, .missingCarbRatio, .missingGlucoseTarget:
                return "gearshape.fill"
            }
        }
    }
    
    // MARK: - Components
    
    /// Individual component readiness states
    public struct Components: Sendable, Equatable, Codable {
        public var glucoseReady: Bool
        public var pumpReady: Bool
        public var configurationReady: Bool
        public var insulinDataReady: Bool
        
        public init(
            glucoseReady: Bool = true,
            pumpReady: Bool = true,
            configurationReady: Bool = true,
            insulinDataReady: Bool = true
        ) {
            self.glucoseReady = glucoseReady
            self.pumpReady = pumpReady
            self.configurationReady = configurationReady
            self.insulinDataReady = insulinDataReady
        }
        
        /// All components ready
        public var allReady: Bool {
            glucoseReady && pumpReady && configurationReady && insulinDataReady
        }
    }
}

// MARK: - Factory Methods

extension AlgorithmReadiness {
    
    /// Evaluate readiness from component states
    public static func evaluate(
        glucoseFreshness: DataFreshness,
        insulinFreshness: InsulinFreshness? = nil,
        hasPump: Bool = true,
        pumpSuspended: Bool = false,
        pumpCommunicationFailed: Bool = false,
        hasBasalSchedule: Bool = true,
        hasInsulinSensitivity: Bool = true,
        hasCarbRatio: Bool = true,
        hasGlucoseTarget: Bool = true,
        cgmSensorFailed: Bool = false,
        evaluatedAt: Date = Date()
    ) -> AlgorithmReadiness {
        
        var cannotRunReasons: [CannotRunReason] = []
        var degradedReasons: [DegradedReason] = []
        
        // Check CGM/glucose state
        if cgmSensorFailed {
            cannotRunReasons.append(.cgmSensorFailed)
        } else if !glucoseFreshness.hasData {
            cannotRunReasons.append(.noGlucoseData)
        } else if glucoseFreshness.isExpired {
            cannotRunReasons.append(.glucoseExpired)
        } else if glucoseFreshness.isStale {
            degradedReasons.append(.glucoseStale)
        }
        
        // Check pump state
        if !hasPump {
            cannotRunReasons.append(.noPumpConfigured)
        } else if pumpSuspended {
            cannotRunReasons.append(.pumpSuspended)
        } else if pumpCommunicationFailed {
            cannotRunReasons.append(.pumpCommunicationFailed)
        }
        
        // Check configuration
        if !hasBasalSchedule {
            cannotRunReasons.append(.missingBasalSchedule)
        }
        if !hasInsulinSensitivity {
            cannotRunReasons.append(.missingInsulinSensitivity)
        }
        if !hasCarbRatio {
            cannotRunReasons.append(.missingCarbRatio)
        }
        if !hasGlucoseTarget {
            cannotRunReasons.append(.missingGlucoseTarget)
        }
        
        // Check insulin data
        if let insulin = insulinFreshness, !insulin.isActive {
            degradedReasons.append(.insulinDataAging)
        }
        
        // Build components
        let components = Components(
            glucoseReady: glucoseFreshness.hasData && !glucoseFreshness.isExpired && !cgmSensorFailed,
            pumpReady: hasPump && !pumpSuspended && !pumpCommunicationFailed,
            configurationReady: hasBasalSchedule && hasInsulinSensitivity && hasCarbRatio && hasGlucoseTarget,
            insulinDataReady: insulinFreshness?.isActive ?? true
        )
        
        // Determine final state
        let state: State
        if !cannotRunReasons.isEmpty {
            state = .cannotRun(cannotRunReasons)
        } else if !degradedReasons.isEmpty {
            state = .degraded(degradedReasons)
        } else {
            state = .ready
        }
        
        return AlgorithmReadiness(
            state: state,
            evaluatedAt: evaluatedAt,
            components: components
        )
    }
    
    /// Create a ready state
    public static func ready(evaluatedAt: Date = Date()) -> AlgorithmReadiness {
        AlgorithmReadiness(state: .ready, evaluatedAt: evaluatedAt)
    }
    
    /// Create a cannot-run state with reasons
    public static func cannotRun(_ reasons: [CannotRunReason], evaluatedAt: Date = Date()) -> AlgorithmReadiness {
        AlgorithmReadiness(state: .cannotRun(reasons), evaluatedAt: evaluatedAt)
    }
    
    /// Create a degraded state with reasons
    public static func degraded(_ reasons: [DegradedReason], evaluatedAt: Date = Date()) -> AlgorithmReadiness {
        AlgorithmReadiness(state: .degraded(reasons), evaluatedAt: evaluatedAt)
    }
    
    // MARK: - Mode-Aware Evaluation (AID-PARTIAL-003)
    
    /// Evaluate readiness based on LoopMode (pump-optional support)
    ///
    /// When mode is `cgmOnly`, pump-related issues are not treated as errors.
    /// Instead, the algorithm runs in degraded mode with limited functionality.
    ///
    /// - Parameters:
    ///   - loopMode: Current loop mode (affects pump requirements)
    ///   - glucoseFreshness: CGM data freshness
    ///   - insulinFreshness: Optional insulin data freshness
    ///   - hasPump: Whether pump is configured and connected
    ///   - pumpSuspended: Whether pump is suspended
    ///   - evaluatedAt: Timestamp for evaluation
    public static func evaluateForMode(
        loopMode: LoopMode,
        glucoseFreshness: DataFreshness,
        insulinFreshness: InsulinFreshness? = nil,
        hasPump: Bool = true,
        pumpSuspended: Bool = false,
        pumpCommunicationFailed: Bool = false,
        hasBasalSchedule: Bool = true,
        hasInsulinSensitivity: Bool = true,
        hasCarbRatio: Bool = true,
        hasGlucoseTarget: Bool = true,
        cgmSensorFailed: Bool = false,
        evaluatedAt: Date = Date()
    ) -> AlgorithmReadiness {
        
        var cannotRunReasons: [CannotRunReason] = []
        var degradedReasons: [DegradedReason] = []
        
        // Check CGM/glucose state (always required)
        if cgmSensorFailed {
            cannotRunReasons.append(.cgmSensorFailed)
        } else if !glucoseFreshness.hasData {
            cannotRunReasons.append(.noGlucoseData)
        } else if glucoseFreshness.isExpired {
            cannotRunReasons.append(.glucoseExpired)
        } else if glucoseFreshness.isStale {
            degradedReasons.append(.glucoseStale)
        }
        
        // Check pump state (only if mode requires pump)
        if loopMode.requiresPump {
            if !hasPump {
                cannotRunReasons.append(.noPumpConfigured)
            } else if pumpSuspended {
                cannotRunReasons.append(.pumpSuspended)
            } else if pumpCommunicationFailed {
                cannotRunReasons.append(.pumpCommunicationFailed)
            }
        } else {
            // Pump not required (cgmOnly mode) - degrade instead of error
            if !hasPump {
                degradedReasons.append(.insulinDataAging)  // Use existing reason
            }
        }
        
        // Check configuration (only if dosing is possible)
        if loopMode.requiresPump && hasPump {
            if !hasBasalSchedule {
                cannotRunReasons.append(.missingBasalSchedule)
            }
            if !hasInsulinSensitivity {
                cannotRunReasons.append(.missingInsulinSensitivity)
            }
            if !hasCarbRatio {
                cannotRunReasons.append(.missingCarbRatio)
            }
            if !hasGlucoseTarget {
                cannotRunReasons.append(.missingGlucoseTarget)
            }
        }
        
        // Check insulin data
        if let insulin = insulinFreshness, !insulin.isActive {
            degradedReasons.append(.insulinDataAging)
        }
        
        // Build components
        let pumpReady = loopMode.requiresPump 
            ? (hasPump && !pumpSuspended && !pumpCommunicationFailed)
            : true  // Pump not required
        
        let configReady = loopMode.requiresPump
            ? (hasBasalSchedule && hasInsulinSensitivity && hasCarbRatio && hasGlucoseTarget)
            : true  // Config not required for cgmOnly
        
        let components = Components(
            glucoseReady: glucoseFreshness.hasData && !glucoseFreshness.isExpired && !cgmSensorFailed,
            pumpReady: pumpReady,
            configurationReady: configReady,
            insulinDataReady: insulinFreshness?.isActive ?? true
        )
        
        // Determine final state
        let state: State
        if !cannotRunReasons.isEmpty {
            state = .cannotRun(cannotRunReasons)
        } else if !degradedReasons.isEmpty {
            state = .degraded(degradedReasons)
        } else {
            state = .ready
        }
        
        return AlgorithmReadiness(
            state: state,
            evaluatedAt: evaluatedAt,
            components: components
        )
    }
}

// MARK: - Convenience Properties

extension AlgorithmReadiness {
    
    /// Whether automatic dosing should be allowed
    public var allowsAutomaticDosing: Bool {
        state.canExecute
    }
    
    /// Summary message for current state
    public var summaryMessage: String {
        switch state {
        case .ready:
            return "Algorithm ready"
        case .degraded(let reasons):
            if reasons.count == 1 {
                return reasons[0].localizedDescription
            }
            return "Algorithm running with limitations"
        case .cannotRun(let reasons):
            if reasons.count == 1 {
                return reasons[0].localizedDescription
            }
            return "Algorithm cannot run"
        }
    }
    
    /// Detailed reasons list
    public var detailedReasons: [String] {
        switch state {
        case .ready:
            return []
        case .degraded(let reasons):
            return reasons.map { $0.localizedDescription }
        case .cannotRun(let reasons):
            return reasons.map { $0.localizedDescription }
        }
    }
}

// MARK: - CustomStringConvertible

extension AlgorithmReadiness: CustomStringConvertible {
    public var description: String {
        switch state {
        case .ready:
            return "AlgorithmReadiness(ready)"
        case .degraded(let reasons):
            return "AlgorithmReadiness(degraded: \(reasons.map { $0.rawValue }.joined(separator: ", ")))"
        case .cannotRun(let reasons):
            return "AlgorithmReadiness(cannotRun: \(reasons.map { $0.rawValue }.joined(separator: ", ")))"
        }
    }
}
