/// Pump manager error stratification for consistent error handling
/// Pattern: LoopKit/DeviceManager/PumpManagerError.swift
///
/// Provides categorized pump errors for UI display, logging, and recovery.
/// Integrates with DeviceStatusElementState for visual presentation.

import Foundation

// MARK: - PumpManagerError

/// Categorized pump manager errors following LoopKit patterns.
///
/// Errors are stratified into 5 categories for consistent handling:
/// - **configuration**: Invalid settings or missing configuration
/// - **connection**: Unable to connect to pump
/// - **communication**: Connected but command failed
/// - **deviceState**: Pump in error/unusable state
/// - **delivery**: Insulin delivery issues
///
/// ## Usage
/// ```swift
/// do {
///     try await pump.setTempBasal(rate: 1.5, duration: .minutes(30))
/// } catch {
///     let classified = PumpManagerError.classify(error)
///     switch classified.category {
///     case .communication:
///         scheduleRetry()
///     case .deviceState:
///         alertUser(classified.localizedDescription)
///     case .delivery(.uncertain):
///         promptToCheckPumpHistory()
///     default:
///         logError(classified)
///     }
/// }
/// ```
public struct PumpManagerError: Error, Sendable, Equatable, Codable {
    
    /// Error category
    public let category: Category
    
    /// Original error description (if available)
    public let underlyingDescription: String?
    
    /// Recovery suggestion (if available)
    public let recoveryHint: String?
    
    /// Whether this error is recoverable
    public let isRecoverable: Bool
    
    /// Timestamp when error occurred
    public let occurredAt: Date
    
    /// Initialize with category and details
    public init(
        category: Category,
        underlyingDescription: String? = nil,
        recoveryHint: String? = nil,
        isRecoverable: Bool = true,
        occurredAt: Date = Date()
    ) {
        self.category = category
        self.underlyingDescription = underlyingDescription
        self.recoveryHint = recoveryHint
        self.isRecoverable = isRecoverable
        self.occurredAt = occurredAt
    }
    
    // MARK: - Error Category
    
    /// Pump error categories
    public enum Category: Sendable, Equatable, Codable {
        /// Invalid device configuration
        case configuration(ConfigurationError)
        
        /// Unable to connect to pump
        case connection(ConnectionError)
        
        /// Connected but communication failed
        case communication(CommunicationError)
        
        /// Pump in error/unusable state
        case deviceState(DeviceStateError)
        
        /// Insulin delivery issues
        case delivery(DeliveryError)
        
        /// Internal/unexpected errors
        case `internal`(InternalError)
        
        /// Category name for logging/tracking
        public var name: String {
            switch self {
            case .configuration: return "configuration"
            case .connection: return "connection"
            case .communication: return "communication"
            case .deviceState: return "deviceState"
            case .delivery: return "delivery"
            case .internal: return "internal"
            }
        }
        
        /// Issue ID for dosing decision tracking (matches Loop)
        public var issueId: String {
            name
        }
        
        /// Convert to DeviceStatusElementState
        public var elementState: DeviceStatusElementState {
            switch self {
            case .configuration:
                return .warning
            case .connection, .communication:
                return .warning
            case .deviceState:
                return .critical
            case .delivery(let error):
                return error.isUncertain ? .critical : .warning
            case .internal:
                return .critical
            }
        }
    }
    
    // MARK: - Configuration Errors
    
    /// Configuration-related errors
    public enum ConfigurationError: String, Sendable, Codable, CaseIterable {
        /// No pump configured
        case noPumpConfigured
        
        /// Insulin type not set
        case insulinTypeNotConfigured
        
        /// Basal schedule not configured
        case basalScheduleNotConfigured
        
        /// Invalid settings
        case invalidSettings
        
        /// Missing required parameter
        case missingParameter
        
        /// Pump model not supported
        case unsupportedPumpModel
        
        public var localizedDescription: String {
            switch self {
            case .noPumpConfigured:
                return "No pump configured"
            case .insulinTypeNotConfigured:
                return "Insulin type not configured"
            case .basalScheduleNotConfigured:
                return "Basal schedule not configured"
            case .invalidSettings:
                return "Invalid pump settings"
            case .missingParameter:
                return "Missing required parameter"
            case .unsupportedPumpModel:
                return "Pump model not supported"
            }
        }
        
        public var recoverySuggestion: String {
            switch self {
            case .noPumpConfigured:
                return "Go to Settings and configure your pump"
            case .insulinTypeNotConfigured:
                return "Select your insulin type in pump settings"
            case .basalScheduleNotConfigured:
                return "Configure your basal schedule"
            case .invalidSettings:
                return "Check your pump settings"
            case .missingParameter:
                return "Provide the required information"
            case .unsupportedPumpModel:
                return "Check supported pump models"
            }
        }
    }
    
    // MARK: - Connection Errors
    
    /// Connection-related errors
    public enum ConnectionError: String, Sendable, Codable, CaseIterable {
        /// No RileyLink/bridge device
        case noRileyLink
        
        /// Bluetooth disabled
        case bluetoothDisabled
        
        /// Bluetooth unauthorized
        case bluetoothUnauthorized
        
        /// Pump not found
        case pumpNotFound
        
        /// Connection timeout
        case connectionTimeout
        
        /// RSSI too low (out of range)
        case rssiTooLow
        
        /// Pod not paired (Omnipod)
        case noPodPaired
        
        public var localizedDescription: String {
            switch self {
            case .noRileyLink:
                return "No RileyLink connected"
            case .bluetoothDisabled:
                return "Bluetooth is disabled"
            case .bluetoothUnauthorized:
                return "Bluetooth permission denied"
            case .pumpNotFound:
                return "Pump not found"
            case .connectionTimeout:
                return "Connection timed out"
            case .rssiTooLow:
                return "Pump out of range"
            case .noPodPaired:
                return "No pod paired"
            }
        }
        
        public var recoverySuggestion: String {
            switch self {
            case .noRileyLink:
                return "Make sure RileyLink is charged and nearby"
            case .bluetoothDisabled:
                return "Enable Bluetooth in Settings"
            case .bluetoothUnauthorized:
                return "Grant Bluetooth permission in Settings"
            case .pumpNotFound:
                return "Make sure pump is nearby and awake"
            case .connectionTimeout:
                return "Move closer to pump and try again"
            case .rssiTooLow:
                return "Move closer to pump"
            case .noPodPaired:
                return "Pair a new pod"
            }
        }
    }
    
    // MARK: - Communication Errors
    
    /// Communication-related errors
    public enum CommunicationError: String, Sendable, Codable, CaseIterable {
        /// Command failed
        case commandFailed
        
        /// Response timeout
        case responseTimeout
        
        /// Invalid response
        case invalidResponse
        
        /// CRC/checksum error
        case checksumError
        
        /// Radio interference
        case radioInterference
        
        /// Command rejected by pump
        case commandRejected
        
        /// Pump busy
        case pumpBusy
        
        public var localizedDescription: String {
            switch self {
            case .commandFailed:
                return "Command failed"
            case .responseTimeout:
                return "No response from pump"
            case .invalidResponse:
                return "Invalid response from pump"
            case .checksumError:
                return "Communication error"
            case .radioInterference:
                return "Radio interference detected"
            case .commandRejected:
                return "Command rejected by pump"
            case .pumpBusy:
                return "Pump is busy"
            }
        }
        
        public var recoverySuggestion: String {
            switch self {
            case .commandFailed:
                return "Try again"
            case .responseTimeout:
                return "Move closer to pump and try again"
            case .invalidResponse:
                return "Try again"
            case .checksumError:
                return "Move closer to pump and try again"
            case .radioInterference:
                return "Move away from other wireless devices"
            case .commandRejected:
                return "Check pump status"
            case .pumpBusy:
                return "Wait for pump to finish current operation"
            }
        }
    }
    
    // MARK: - Device State Errors
    
    /// Device state errors
    public enum DeviceStateError: String, Sendable, Codable, CaseIterable {
        /// Pump suspended
        case suspended
        
        /// Pump faulted
        case faulted
        
        /// Pod expired (Omnipod)
        case podExpired
        
        /// Reservoir empty
        case reservoirEmpty
        
        /// Battery dead
        case batteryDead
        
        /// Bolus in progress
        case bolusInProgress
        
        /// Temp basal in progress
        case tempBasalInProgress
        
        /// Time sync needed
        case timeSyncNeeded
        
        public var localizedDescription: String {
            switch self {
            case .suspended:
                return "Pump is suspended"
            case .faulted:
                return "Pump has faulted"
            case .podExpired:
                return "Pod has expired"
            case .reservoirEmpty:
                return "Reservoir is empty"
            case .batteryDead:
                return "Pump battery is dead"
            case .bolusInProgress:
                return "Bolus already in progress"
            case .tempBasalInProgress:
                return "Temp basal in progress"
            case .timeSyncNeeded:
                return "Pump time sync needed"
            }
        }
        
        public var recoverySuggestion: String {
            switch self {
            case .suspended:
                return "Resume delivery on pump"
            case .faulted:
                return "Replace pump/pod"
            case .podExpired:
                return "Replace pod"
            case .reservoirEmpty:
                return "Refill reservoir"
            case .batteryDead:
                return "Replace pump battery"
            case .bolusInProgress:
                return "Wait for bolus to complete"
            case .tempBasalInProgress:
                return "Cancel or wait for temp basal"
            case .timeSyncNeeded:
                return "Sync pump time"
            }
        }
    }
    
    // MARK: - Delivery Errors
    
    /// Insulin delivery errors
    public enum DeliveryError: Sendable, Equatable, Codable {
        /// Definite delivery failure
        case certain(DeliveryFailureReason)
        
        /// Uncertain delivery (command sent, confirmation unknown)
        case uncertain(DeliveryFailureReason)
        
        /// Whether delivery outcome is uncertain
        public var isUncertain: Bool {
            if case .uncertain = self { return true }
            return false
        }
        
        /// The underlying failure reason
        public var reason: DeliveryFailureReason {
            switch self {
            case .certain(let reason), .uncertain(let reason):
                return reason
            }
        }
        
        public var localizedDescription: String {
            let prefix = isUncertain ? "Delivery uncertain: " : ""
            return prefix + reason.localizedDescription
        }
    }
    
    /// Delivery failure reasons
    public enum DeliveryFailureReason: String, Sendable, Codable, CaseIterable {
        /// Occlusion detected
        case occlusion
        
        /// Reservoir empty during delivery
        case reservoirEmpty
        
        /// Max bolus exceeded
        case maxBolusExceeded
        
        /// Max basal exceeded
        case maxBasalExceeded
        
        /// Max IOB exceeded
        case maxIOBExceeded
        
        /// Bolus cancelled
        case bolusCancelled
        
        /// Temp basal cancelled
        case tempBasalCancelled
        
        /// Delivery interrupted
        case deliveryInterrupted
        
        public var localizedDescription: String {
            switch self {
            case .occlusion:
                return "Occlusion detected"
            case .reservoirEmpty:
                return "Reservoir empty during delivery"
            case .maxBolusExceeded:
                return "Maximum bolus exceeded"
            case .maxBasalExceeded:
                return "Maximum basal rate exceeded"
            case .maxIOBExceeded:
                return "Maximum IOB exceeded"
            case .bolusCancelled:
                return "Bolus was cancelled"
            case .tempBasalCancelled:
                return "Temp basal was cancelled"
            case .deliveryInterrupted:
                return "Delivery was interrupted"
            }
        }
    }
    
    // MARK: - Internal Errors
    
    /// Internal/unexpected errors
    public enum InternalError: String, Sendable, Codable, CaseIterable {
        /// Unexpected error
        case unexpected
        
        /// Assertion failure
        case assertionFailure
        
        /// Invalid state
        case invalidState
        
        /// Not implemented
        case notImplemented
        
        public var localizedDescription: String {
            switch self {
            case .unexpected:
                return "An unexpected error occurred"
            case .assertionFailure:
                return "Internal error"
            case .invalidState:
                return "Invalid state"
            case .notImplemented:
                return "Feature not implemented"
            }
        }
    }
}

// MARK: - LocalizedError

extension PumpManagerError: LocalizedError {
    public var errorDescription: String? {
        switch category {
        case .configuration(let error):
            return error.localizedDescription
        case .connection(let error):
            return error.localizedDescription
        case .communication(let error):
            return error.localizedDescription
        case .deviceState(let error):
            return error.localizedDescription
        case .delivery(let error):
            return error.localizedDescription
        case .internal(let error):
            return error.localizedDescription
        }
    }
    
    public var failureReason: String? {
        underlyingDescription
    }
    
    public var recoverySuggestion: String? {
        recoveryHint
    }
}

// MARK: - Factory Methods

extension PumpManagerError {
    
    /// Create configuration error
    public static func configuration(_ error: ConfigurationError) -> PumpManagerError {
        PumpManagerError(
            category: .configuration(error),
            underlyingDescription: error.localizedDescription,
            recoveryHint: error.recoverySuggestion,
            isRecoverable: true
        )
    }
    
    /// Create connection error
    public static func connection(_ error: ConnectionError) -> PumpManagerError {
        PumpManagerError(
            category: .connection(error),
            underlyingDescription: error.localizedDescription,
            recoveryHint: error.recoverySuggestion,
            isRecoverable: true
        )
    }
    
    /// Create communication error
    public static func communication(_ error: CommunicationError) -> PumpManagerError {
        PumpManagerError(
            category: .communication(error),
            underlyingDescription: error.localizedDescription,
            recoveryHint: error.recoverySuggestion,
            isRecoverable: true
        )
    }
    
    /// Create device state error
    public static func deviceState(_ error: DeviceStateError) -> PumpManagerError {
        let recoverable = error != .faulted && error != .podExpired && error != .batteryDead
        return PumpManagerError(
            category: .deviceState(error),
            underlyingDescription: error.localizedDescription,
            recoveryHint: error.recoverySuggestion,
            isRecoverable: recoverable
        )
    }
    
    /// Create certain delivery error
    public static func deliveryCertain(_ reason: DeliveryFailureReason) -> PumpManagerError {
        PumpManagerError(
            category: .delivery(.certain(reason)),
            underlyingDescription: reason.localizedDescription,
            isRecoverable: true
        )
    }
    
    /// Create uncertain delivery error (critical safety)
    public static func deliveryUncertain(_ reason: DeliveryFailureReason) -> PumpManagerError {
        PumpManagerError(
            category: .delivery(.uncertain(reason)),
            underlyingDescription: "Delivery uncertain: \(reason.localizedDescription)",
            recoveryHint: "Check pump history to verify delivery",
            isRecoverable: false  // Requires user verification
        )
    }
    
    /// Create internal error
    public static func `internal`(_ error: InternalError) -> PumpManagerError {
        PumpManagerError(
            category: .internal(error),
            underlyingDescription: error.localizedDescription,
            isRecoverable: false
        )
    }
}

// MARK: - Error Classification

extension PumpManagerError {
    
    /// Classify an arbitrary error into PumpManagerError categories
    public static func classify(_ error: Error) -> PumpManagerError {
        // If already a PumpManagerError, return as-is
        if let pumpError = error as? PumpManagerError {
            return pumpError
        }
        
        // Check error description for classification hints
        let description = error.localizedDescription.lowercased()
        
        if description.contains("bluetooth") || description.contains("ble") {
            if description.contains("unauthorized") || description.contains("permission") {
                return .connection(.bluetoothUnauthorized)
            }
            if description.contains("disabled") || description.contains("off") {
                return .connection(.bluetoothDisabled)
            }
            return .connection(.connectionTimeout)
        }
        
        if description.contains("timeout") {
            return .communication(.responseTimeout)
        }
        
        if description.contains("occlusion") {
            return .deliveryCertain(.occlusion)
        }
        
        if description.contains("suspend") {
            return .deviceState(.suspended)
        }
        
        // Default to unexpected internal error
        return PumpManagerError(
            category: .internal(.unexpected),
            underlyingDescription: error.localizedDescription,
            isRecoverable: false
        )
    }
}

// MARK: - CustomStringConvertible

extension PumpManagerError: CustomStringConvertible {
    public var description: String {
        "PumpManagerError(\(category.name): \(errorDescription ?? "unknown"))"
    }
}
