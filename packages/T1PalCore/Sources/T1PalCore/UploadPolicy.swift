/// Upload policy for Nightscout sync based on LoopMode
/// AID-PARTIAL-006: NS upload in all modes (CGM always uploads)
///
/// Key principle: CGM data uploads regardless of pump state.
/// This enables:
/// - CGM-only users to share glucose data
/// - Continued monitoring when pump disconnects
/// - Caregivers to see glucose even when pump is offline
///
/// ## Usage
/// ```swift
/// let policy = UploadPolicy.for(mode: currentLoopMode)
/// if policy.shouldUploadCGM {
///     await nightscoutClient.uploadEntries(glucoseReadings)
/// }
/// ```

import Foundation

// MARK: - UploadPolicy

/// Defines what data should upload to Nightscout based on current mode
public struct UploadPolicy: Sendable, Equatable {
    
    /// Whether CGM glucose readings should upload
    public let shouldUploadCGM: Bool
    
    /// Whether treatment data (bolus, carbs) should upload
    public let shouldUploadTreatments: Bool
    
    /// Whether device status should upload
    public let shouldUploadDeviceStatus: Bool
    
    /// Whether algorithm predictions should upload
    public let shouldUploadPredictions: Bool
    
    /// Whether pump data should upload (when available)
    public let shouldUploadPumpData: Bool
    
    /// Policy name for logging
    public let policyName: String
    
    /// Initialize with explicit values
    public init(
        shouldUploadCGM: Bool,
        shouldUploadTreatments: Bool,
        shouldUploadDeviceStatus: Bool,
        shouldUploadPredictions: Bool,
        shouldUploadPumpData: Bool,
        policyName: String
    ) {
        self.shouldUploadCGM = shouldUploadCGM
        self.shouldUploadTreatments = shouldUploadTreatments
        self.shouldUploadDeviceStatus = shouldUploadDeviceStatus
        self.shouldUploadPredictions = shouldUploadPredictions
        self.shouldUploadPumpData = shouldUploadPumpData
        self.policyName = policyName
    }
    
    // MARK: - Factory Methods
    
    /// Get upload policy for a LoopMode
    public static func `for`(mode: LoopMode) -> UploadPolicy {
        switch mode {
        case .cgmOnly:
            return .cgmOnly
        case .openLoop:
            return .openLoop
        case .tempBasalOnly:
            return .tempBasalOnly
        case .closedLoop:
            return .closedLoop
        }
    }
    
    /// CGM-only mode: upload CGM and basic device status
    public static let cgmOnly = UploadPolicy(
        shouldUploadCGM: true,          // Always upload CGM
        shouldUploadTreatments: false,  // No pump = no treatments
        shouldUploadDeviceStatus: true, // Upload CGM device status
        shouldUploadPredictions: false, // No predictions without insulin data
        shouldUploadPumpData: false,    // No pump
        policyName: "cgmOnly"
    )
    
    /// Open loop: upload everything except enacted recommendations
    public static let openLoop = UploadPolicy(
        shouldUploadCGM: true,
        shouldUploadTreatments: true,   // Manual boluses, carbs
        shouldUploadDeviceStatus: true,
        shouldUploadPredictions: true,  // Show predictions even if not enacting
        shouldUploadPumpData: true,
        policyName: "openLoop"
    )
    
    /// Temp basal only: upload everything
    public static let tempBasalOnly = UploadPolicy(
        shouldUploadCGM: true,
        shouldUploadTreatments: true,
        shouldUploadDeviceStatus: true,
        shouldUploadPredictions: true,
        shouldUploadPumpData: true,
        policyName: "tempBasalOnly"
    )
    
    /// Closed loop: full uploads
    public static let closedLoop = UploadPolicy(
        shouldUploadCGM: true,
        shouldUploadTreatments: true,
        shouldUploadDeviceStatus: true,
        shouldUploadPredictions: true,
        shouldUploadPumpData: true,
        policyName: "closedLoop"
    )
    
    /// Policy when pump is disconnected (regardless of mode)
    public static let pumpDisconnected = UploadPolicy(
        shouldUploadCGM: true,          // CGM always uploads
        shouldUploadTreatments: false,  // Can't enact
        shouldUploadDeviceStatus: true, // Report disconnected status
        shouldUploadPredictions: false, // Predictions stale without pump
        shouldUploadPumpData: false,    // No pump data
        policyName: "pumpDisconnected"
    )
    
    /// Disabled uploads (e.g., airplane mode, user preference)
    public static let disabled = UploadPolicy(
        shouldUploadCGM: false,
        shouldUploadTreatments: false,
        shouldUploadDeviceStatus: false,
        shouldUploadPredictions: false,
        shouldUploadPumpData: false,
        policyName: "disabled"
    )
}

// MARK: - UploadPolicyEvaluator

/// Evaluates upload policy based on current system state
public struct UploadPolicyEvaluator: Sendable {
    
    /// Current loop mode
    public let loopMode: LoopMode
    
    /// Whether pump is currently connected
    public let isPumpConnected: Bool
    
    /// Whether CGM is currently connected
    public let isCGMConnected: Bool
    
    /// Whether user has enabled Nightscout uploads
    public let uploadsEnabled: Bool
    
    /// Initialize evaluator
    public init(
        loopMode: LoopMode,
        isPumpConnected: Bool,
        isCGMConnected: Bool,
        uploadsEnabled: Bool = true
    ) {
        self.loopMode = loopMode
        self.isPumpConnected = isPumpConnected
        self.isCGMConnected = isCGMConnected
        self.uploadsEnabled = uploadsEnabled
    }
    
    /// Get effective upload policy
    public var effectivePolicy: UploadPolicy {
        // User disabled uploads
        guard uploadsEnabled else {
            return .disabled
        }
        
        // CGM not connected = nothing to upload
        guard isCGMConnected else {
            return .disabled
        }
        
        // Get base policy from mode
        let basePolicy = UploadPolicy.for(mode: loopMode)
        
        // If mode requires pump but pump disconnected, degrade
        if loopMode.requiresPump && !isPumpConnected {
            return .pumpDisconnected
        }
        
        return basePolicy
    }
    
    /// Whether CGM data should upload (convenience)
    public var shouldUploadCGM: Bool {
        effectivePolicy.shouldUploadCGM
    }
    
    /// Whether treatments should upload (convenience)
    public var shouldUploadTreatments: Bool {
        effectivePolicy.shouldUploadTreatments
    }
}

// MARK: - UploadDecision

/// Represents a decision about what to upload with reasoning
public struct UploadDecision: Sendable, Equatable {
    
    /// What type of data
    public enum DataType: String, Sendable, CaseIterable {
        case cgmGlucose = "CGM Glucose"
        case treatments = "Treatments"
        case deviceStatus = "Device Status"
        case predictions = "Predictions"
        case pumpData = "Pump Data"
    }
    
    /// The data type
    public let dataType: DataType
    
    /// Whether upload is allowed
    public let allowed: Bool
    
    /// Reason for decision
    public let reason: String
    
    /// Initialize
    public init(dataType: DataType, allowed: Bool, reason: String) {
        self.dataType = dataType
        self.allowed = allowed
        self.reason = reason
    }
    
    /// Create decisions from policy
    public static func from(policy: UploadPolicy, policySource: String) -> [UploadDecision] {
        return [
            UploadDecision(
                dataType: .cgmGlucose,
                allowed: policy.shouldUploadCGM,
                reason: policy.shouldUploadCGM ? "CGM always uploads in \(policySource)" : "CGM uploads disabled"
            ),
            UploadDecision(
                dataType: .treatments,
                allowed: policy.shouldUploadTreatments,
                reason: policy.shouldUploadTreatments ? "Treatments enabled in \(policySource)" : "No pump data available"
            ),
            UploadDecision(
                dataType: .deviceStatus,
                allowed: policy.shouldUploadDeviceStatus,
                reason: policy.shouldUploadDeviceStatus ? "Device status enabled" : "Device status disabled"
            ),
            UploadDecision(
                dataType: .predictions,
                allowed: policy.shouldUploadPredictions,
                reason: policy.shouldUploadPredictions ? "Predictions available" : "Predictions unavailable without insulin data"
            ),
            UploadDecision(
                dataType: .pumpData,
                allowed: policy.shouldUploadPumpData,
                reason: policy.shouldUploadPumpData ? "Pump data available" : "No pump connected"
            )
        ]
    }
}

// MARK: - CustomStringConvertible

extension UploadPolicy: CustomStringConvertible {
    public var description: String {
        "UploadPolicy(\(policyName): CGM=\(shouldUploadCGM), treatments=\(shouldUploadTreatments))"
    }
}

extension UploadPolicyEvaluator: CustomStringConvertible {
    public var description: String {
        "UploadPolicyEvaluator(mode=\(loopMode), pump=\(isPumpConnected), cgm=\(isCGMConnected)) → \(effectivePolicy.policyName)"
    }
}
