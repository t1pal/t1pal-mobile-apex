/// Uncertain delivery handling for safety-critical insulin delivery tracking
/// Pattern: Loop DeliveryUncertaintyAlertManager + UnfinalizedDose
///
/// When insulin delivery outcome is unknown (command sent but unconfirmed),
/// automation must stop and the user must be alerted.
///
/// ## Safety Behavior
/// - Automation stops immediately when uncertainty detected
/// - User is alerted with clear instructions
/// - System cannot resume until uncertainty is resolved
/// - All uncertain states are logged for safety audit

import Foundation

// MARK: - UncertainDeliveryState

/// Tracks the current state of delivery uncertainty.
///
/// When `isUncertain` is true:
/// - Algorithm must not issue new commands
/// - User must be notified
/// - Recovery must be attempted or pod replaced
public struct UncertainDeliveryState: Sendable, Equatable, Codable {
    
    /// Whether delivery is currently uncertain
    public let isUncertain: Bool
    
    /// The type of delivery that is uncertain (if any)
    public let uncertainDeliveryType: DeliveryType?
    
    /// When uncertainty was detected
    public let detectedAt: Date?
    
    /// The error that caused uncertainty (if available)
    public let causingError: String?
    
    /// Expected insulin amount (if known)
    public let expectedUnits: Double?
    
    /// Recovery attempts made
    public let recoveryAttempts: Int
    
    /// Maximum recovery attempts before requiring user action
    public static let maxRecoveryAttempts = 3
    
    /// Initialize certain state (no uncertainty)
    public init() {
        self.isUncertain = false
        self.uncertainDeliveryType = nil
        self.detectedAt = nil
        self.causingError = nil
        self.expectedUnits = nil
        self.recoveryAttempts = 0
    }
    
    /// Initialize uncertain state
    public init(
        type: DeliveryType,
        detectedAt: Date = Date(),
        causingError: String? = nil,
        expectedUnits: Double? = nil,
        recoveryAttempts: Int = 0
    ) {
        self.isUncertain = true
        self.uncertainDeliveryType = type
        self.detectedAt = detectedAt
        self.causingError = causingError
        self.expectedUnits = expectedUnits
        self.recoveryAttempts = recoveryAttempts
    }
    
    /// Certain delivery state
    public static let certain = UncertainDeliveryState()
    
    /// Create state from PumpManagerError
    public static func from(error: PumpManagerError, expectedUnits: Double? = nil) -> UncertainDeliveryState {
        if case .delivery(let delivery) = error.category, delivery.isUncertain {
            let type: DeliveryType
            switch delivery.reason {
            case .occlusion, .reservoirEmpty, .deliveryInterrupted:
                type = .unknown
            case .maxBolusExceeded, .bolusCancelled:
                type = .bolus
            case .maxBasalExceeded, .tempBasalCancelled:
                type = .tempBasal
            case .maxIOBExceeded:
                type = .unknown
            }
            return UncertainDeliveryState(
                type: type,
                causingError: error.errorDescription,
                expectedUnits: expectedUnits
            )
        }
        return .certain
    }
    
    /// Whether automation can run
    public var canRunAutomation: Bool {
        !isUncertain
    }
    
    /// Whether max recovery attempts exhausted
    public var recoveryExhausted: Bool {
        recoveryAttempts >= Self.maxRecoveryAttempts
    }
    
    /// Create state with incremented recovery attempt
    public func withRecoveryAttempt() -> UncertainDeliveryState {
        guard isUncertain else { return self }
        return UncertainDeliveryState(
            type: uncertainDeliveryType ?? .unknown,
            detectedAt: detectedAt ?? Date(),
            causingError: causingError,
            expectedUnits: expectedUnits,
            recoveryAttempts: recoveryAttempts + 1
        )
    }
    
    // MARK: - Delivery Type
    
    /// Type of delivery that is uncertain
    public enum DeliveryType: String, Sendable, Codable, CaseIterable {
        /// Bolus delivery uncertain
        case bolus
        
        /// Temp basal delivery uncertain
        case tempBasal
        
        /// Basal resume uncertain
        case basalResume
        
        /// Suspend uncertain
        case suspend
        
        /// Unknown delivery type
        case unknown
        
        public var localizedDescription: String {
            switch self {
            case .bolus: return "bolus"
            case .tempBasal: return "temp basal"
            case .basalResume: return "basal resume"
            case .suspend: return "suspend"
            case .unknown: return "insulin delivery"
            }
        }
    }
}

// MARK: - UncertainDeliveryAlert

/// Alert information for uncertain delivery situations
public struct UncertainDeliveryAlert: Sendable, Equatable {
    
    /// Alert title
    public let title: String
    
    /// Alert message
    public let message: String
    
    /// Recovery instructions
    public let recoveryInstructions: [String]
    
    /// Whether pod/pump replacement may be needed
    public let mayRequireReplacement: Bool
    
    /// Monitoring duration warning (hours)
    public let monitoringDurationHours: Int
    
    /// Create alert from uncertainty state
    public init(state: UncertainDeliveryState) {
        self.title = "Unable To Reach Pump"
        
        let deliveryType = state.uncertainDeliveryType?.localizedDescription ?? "insulin delivery"
        
        if let units = state.expectedUnits {
            self.message = "A \(deliveryType) command for \(String(format: "%.2f", units)) U was sent, but we couldn't confirm if the pump received it. Automation has been paused."
        } else {
            self.message = "A \(deliveryType) command was sent, but we couldn't confirm if the pump received it. Automation has been paused."
        }
        
        self.recoveryInstructions = [
            "Check your pump/pod to verify if insulin was delivered",
            "Try toggling Bluetooth off and on",
            "Move closer to your pump/pod",
            "If unable to reconnect, you may need to replace your pod"
        ]
        
        self.mayRequireReplacement = state.recoveryExhausted
        self.monitoringDurationHours = 6  // Standard DIA monitoring period
    }
    
    /// Warning message about glucose monitoring
    public var monitoringWarning: String {
        "Monitor your glucose closely for the next \(monitoringDurationHours) hours, as there may or may not be insulin actively working in your body."
    }
}

// MARK: - UncertainDeliveryHandler

/// Handles uncertain delivery situations with safety-first approach
public struct UncertainDeliveryHandler: Sendable {
    
    /// Current uncertainty state
    public private(set) var state: UncertainDeliveryState
    
    /// Callback for state changes
    public var onStateChange: (@Sendable (UncertainDeliveryState) -> Void)?
    
    /// Callback for alert display
    public var onAlertRequired: (@Sendable (UncertainDeliveryAlert) -> Void)?
    
    /// Callback for safety log entries
    public var onSafetyLog: (@Sendable (SafetyLogEntry) -> Void)?
    
    /// Initialize with certain state
    public init() {
        self.state = .certain
    }
    
    /// Initialize with existing state
    public init(state: UncertainDeliveryState) {
        self.state = state
    }
    
    /// Report uncertain delivery (stops automation)
    public mutating func reportUncertainDelivery(
        type: UncertainDeliveryState.DeliveryType,
        expectedUnits: Double? = nil,
        causingError: String? = nil
    ) {
        let newState = UncertainDeliveryState(
            type: type,
            causingError: causingError,
            expectedUnits: expectedUnits
        )
        
        state = newState
        
        // Log safety event
        onSafetyLog?(SafetyLogEntry(
            event: .uncertainDeliveryDetected,
            details: "Type: \(type.rawValue), Units: \(expectedUnits.map { String($0) } ?? "unknown")",
            timestamp: Date()
        ))
        
        // Notify state change
        onStateChange?(newState)
        
        // Require alert
        onAlertRequired?(UncertainDeliveryAlert(state: newState))
    }
    
    /// Report uncertain delivery from error
    public mutating func reportError(_ error: PumpManagerError, expectedUnits: Double? = nil) {
        let newState = UncertainDeliveryState.from(error: error, expectedUnits: expectedUnits)
        
        if newState.isUncertain {
            state = newState
            onStateChange?(newState)
            onAlertRequired?(UncertainDeliveryAlert(state: newState))
            
            onSafetyLog?(SafetyLogEntry(
                event: .uncertainDeliveryDetected,
                details: error.errorDescription ?? "Unknown error",
                timestamp: Date()
            ))
        }
    }
    
    /// Attempt recovery (e.g., after Bluetooth toggle)
    public mutating func attemptRecovery() -> RecoveryResult {
        guard state.isUncertain else {
            return .notNeeded
        }
        
        let newState = state.withRecoveryAttempt()
        state = newState
        
        onSafetyLog?(SafetyLogEntry(
            event: .recoveryAttempted,
            details: "Attempt \(newState.recoveryAttempts) of \(UncertainDeliveryState.maxRecoveryAttempts)",
            timestamp: Date()
        ))
        
        if newState.recoveryExhausted {
            return .exhausted
        }
        
        return .attempting(attempt: newState.recoveryAttempts)
    }
    
    /// Confirm delivery was successful (resolves uncertainty)
    public mutating func confirmDelivery() {
        guard state.isUncertain else { return }
        
        onSafetyLog?(SafetyLogEntry(
            event: .deliveryConfirmed,
            details: "Uncertainty resolved - delivery confirmed",
            timestamp: Date()
        ))
        
        state = .certain
        onStateChange?(state)
    }
    
    /// Confirm delivery failed (resolves uncertainty)
    public mutating func confirmDeliveryFailed() {
        guard state.isUncertain else { return }
        
        onSafetyLog?(SafetyLogEntry(
            event: .deliveryFailedConfirmed,
            details: "Uncertainty resolved - delivery did not occur",
            timestamp: Date()
        ))
        
        state = .certain
        onStateChange?(state)
    }
    
    /// User acknowledged and will monitor manually
    public mutating func userAcknowledged() {
        guard state.isUncertain else { return }
        
        onSafetyLog?(SafetyLogEntry(
            event: .userAcknowledged,
            details: "User acknowledged uncertainty, will monitor manually",
            timestamp: Date()
        ))
        
        // State remains uncertain until confirmed or pod replaced
    }
    
    /// Pod/pump replaced (resolves uncertainty)
    public mutating func deviceReplaced() {
        onSafetyLog?(SafetyLogEntry(
            event: .deviceReplaced,
            details: "Pod/pump replaced, uncertainty resolved",
            timestamp: Date()
        ))
        
        state = .certain
        onStateChange?(state)
    }
    
    // MARK: - Recovery Result
    
    /// Result of recovery attempt
    public enum RecoveryResult: Sendable, Equatable {
        /// No recovery needed (not uncertain)
        case notNeeded
        
        /// Recovery being attempted
        case attempting(attempt: Int)
        
        /// Max recovery attempts exhausted
        case exhausted
    }
    
    // MARK: - Safety Log Entry
    
    /// Safety audit log entry
    public struct SafetyLogEntry: Sendable, Equatable, Codable {
        public let event: Event
        public let details: String
        public let timestamp: Date
        
        public enum Event: String, Sendable, Codable {
            case uncertainDeliveryDetected
            case recoveryAttempted
            case deliveryConfirmed
            case deliveryFailedConfirmed
            case userAcknowledged
            case deviceReplaced
        }
    }
}

// MARK: - AlgorithmReadiness Integration

extension AlgorithmReadiness {
    
    /// Evaluate with uncertain delivery check
    public static func evaluate(
        glucoseFreshness: DataFreshness,
        insulinFreshness: InsulinFreshness? = nil,
        hasPump: Bool = true,
        deliveryState: UncertainDeliveryState,
        pumpSuspended: Bool = false,
        pumpCommunicationFailed: Bool = false,
        hasBasalSchedule: Bool = true,
        hasInsulinSensitivity: Bool = true,
        hasCarbRatio: Bool = true,
        hasGlucoseTarget: Bool = true,
        cgmSensorFailed: Bool = false,
        evaluatedAt: Date = Date()
    ) -> AlgorithmReadiness {
        // Uncertain delivery is a hard stop - check first
        if deliveryState.isUncertain {
            return AlgorithmReadiness(
                state: .cannotRun([.uncertainDelivery]),
                evaluatedAt: evaluatedAt
            )
        }
        
        // Otherwise delegate to standard evaluation
        return evaluate(
            glucoseFreshness: glucoseFreshness,
            insulinFreshness: insulinFreshness,
            hasPump: hasPump,
            pumpSuspended: pumpSuspended,
            pumpCommunicationFailed: pumpCommunicationFailed,
            hasBasalSchedule: hasBasalSchedule,
            hasInsulinSensitivity: hasInsulinSensitivity,
            hasCarbRatio: hasCarbRatio,
            hasGlucoseTarget: hasGlucoseTarget,
            cgmSensorFailed: cgmSensorFailed,
            evaluatedAt: evaluatedAt
        )
    }
}

// MARK: - CustomStringConvertible

extension UncertainDeliveryState: CustomStringConvertible {
    public var description: String {
        if isUncertain {
            return "UncertainDelivery(\(uncertainDeliveryType?.rawValue ?? "unknown"), attempts: \(recoveryAttempts))"
        }
        return "CertainDelivery"
    }
}
