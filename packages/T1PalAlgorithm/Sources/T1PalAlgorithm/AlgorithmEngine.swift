// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmEngine.swift
// T1Pal Mobile
//
// AID algorithm execution engine
// Requirements: REQ-AID-002

import Foundation
import T1PalCore

/// Algorithm input data
/// Requirements: REQ-AID-002
public struct AlgorithmInputs: Sendable {
    public let glucose: [GlucoseReading]
    public let insulinOnBoard: Double
    public let carbsOnBoard: Double
    public let profile: TherapyProfile
    public let currentTime: Date
    
    /// Active profile override (ALG-PARITY-004)
    public let activeOverride: ProfileOverride?
    
    // ALG-LIVE-045/046: High-fidelity history (optional - use when available)
    /// Actual dose history for accurate IOB curve calculation
    public let doseHistory: [InsulinDose]?
    /// Actual carb history for accurate COB calculation
    public let carbHistory: [CarbEntry]?
    
    // ALG-WIRE-001: Basal schedule for net IOB calculation
    /// Scheduled basal rates timeline for dose annotation (enables Loop-compatible net IOB)
    /// When provided, doses can be annotated with `annotated(with:)` to produce `BasalRelativeDose`
    public let basalSchedule: [AbsoluteScheduleValue<Double>]?
    
    // ALG-DIAG-024: ISF and correction range schedules for parity dose recommendation
    /// Insulin sensitivity timeline for Loop-parity insulin correction calculation
    public let insulinSensitivitySchedule: [AbsoluteScheduleValue<Double>]?
    /// Correction range timeline for Loop-parity insulin correction calculation
    public let correctionRangeSchedule: [AbsoluteScheduleValue<ClosedRange<Double>>]?
    
    // ALG-EFF-003: Effect modifiers from physiological agents
    /// Active effect modifiers that adjust ISF, CR, and basal multipliers
    /// Multiple modifiers are composed multiplicatively with safety bounds enforced
    public let effectModifiers: [EffectModifier]?
    
    // ALG-PARITY-005: Pre-calculated insulin activity from IOB subsystem
    /// Insulin activity rate (U/min) at current time, from per-dose IOB calculation.
    /// When provided, used instead of the IOB/tau approximation for prediction accuracy.
    public let insulinActivity: Double?
    
    /// IOB projected assuming zero temp basal (counterfactual for safety guards)
    public let iobWithZeroTemp: Double?
    /// Activity rate assuming zero temp basal
    public let iobWithZeroTempActivity: Double?
    
    // ALG-PARITY-006: Pre-calculated glucose deltas from CGM subsystem
    /// BG change per 5-min interval. When provided, overrides computation from glucose array.
    public let glucoseDelta: Double?
    /// Short-term average delta (~15 min). From glucose_status.short_avgdelta in oref0.
    public let shortAvgDelta: Double?
    /// Long-term average delta (~45 min). From glucose_status.long_avgdelta in oref0.
    public let longAvgDelta: Double?
    
    public init(
        glucose: [GlucoseReading],
        insulinOnBoard: Double = 0,
        carbsOnBoard: Double = 0,
        profile: TherapyProfile,
        currentTime: Date = Date(),
        activeOverride: ProfileOverride? = nil,
        doseHistory: [InsulinDose]? = nil,
        carbHistory: [CarbEntry]? = nil,
        basalSchedule: [AbsoluteScheduleValue<Double>]? = nil,
        insulinSensitivitySchedule: [AbsoluteScheduleValue<Double>]? = nil,
        correctionRangeSchedule: [AbsoluteScheduleValue<ClosedRange<Double>>]? = nil,
        effectModifiers: [EffectModifier]? = nil,
        insulinActivity: Double? = nil,
        iobWithZeroTemp: Double? = nil,
        iobWithZeroTempActivity: Double? = nil,
        glucoseDelta: Double? = nil,
        shortAvgDelta: Double? = nil,
        longAvgDelta: Double? = nil
    ) {
        self.glucose = glucose
        self.insulinOnBoard = insulinOnBoard
        self.carbsOnBoard = carbsOnBoard
        self.profile = profile
        self.currentTime = currentTime
        self.activeOverride = activeOverride
        self.doseHistory = doseHistory
        self.carbHistory = carbHistory
        self.basalSchedule = basalSchedule
        self.insulinSensitivitySchedule = insulinSensitivitySchedule
        self.correctionRangeSchedule = correctionRangeSchedule
        self.effectModifiers = effectModifiers
        self.insulinActivity = insulinActivity
        self.iobWithZeroTemp = iobWithZeroTemp
        self.iobWithZeroTempActivity = iobWithZeroTempActivity
        self.glucoseDelta = glucoseDelta
        self.shortAvgDelta = shortAvgDelta
        self.longAvgDelta = longAvgDelta
    }
    
    // MARK: - Effect Modifier Application (ALG-EFF-003)
    
    /// Get the composed effect modifier from all active modifiers
    public var composedEffectModifier: EffectModifier {
        guard let modifiers = effectModifiers, !modifiers.isEmpty else {
            return .identity
        }
        return EffectModifier.compose(modifiers.filter { $0.isValid })
    }
    
    /// Get the effective ISF multiplier to apply to profile ISF values
    public var isfMultiplier: Double {
        composedEffectModifier.isfMultiplier
    }
    
    /// Get the effective carb ratio multiplier to apply to profile CR values
    public var carbRatioMultiplier: Double {
        composedEffectModifier.crMultiplier
    }
    
    /// Get the effective basal rate multiplier to apply to profile basal values
    public var basalRateMultiplier: Double {
        composedEffectModifier.basalMultiplier
    }
    
    /// Whether any effect modifiers are active
    public var hasActiveEffects: Bool {
        guard let modifiers = effectModifiers else { return false }
        return modifiers.contains { $0.isValid && !$0.isIdentity }
    }
}

/// Algorithm decision output
/// Requirements: REQ-AID-002
public struct AlgorithmDecision: Sendable {
    public let timestamp: Date
    public let suggestedTempBasal: TempBasal?
    public let suggestedBolus: Double?
    public let reason: String
    public let predictions: GlucosePredictions?
    
    /// Diagnostic data from this calculation cycle (ALG-DIAG-030).
    /// Replaces mutable `_last*` state previously stored on algorithm classes.
    /// Nil for algorithms that don't emit diagnostics or when diagnostics are disabled.
    public let diagnostics: AlgorithmDiagnostics?
    
    public init(
        timestamp: Date = Date(),
        suggestedTempBasal: TempBasal? = nil,
        suggestedBolus: Double? = nil,
        reason: String = "",
        predictions: GlucosePredictions? = nil,
        diagnostics: AlgorithmDiagnostics? = nil
    ) {
        self.timestamp = timestamp
        self.suggestedTempBasal = suggestedTempBasal
        self.suggestedBolus = suggestedBolus
        self.reason = reason
        self.predictions = predictions
        self.diagnostics = diagnostics
    }
}

/// A temporary basal rate adjustment recommended by the algorithm.
public struct TempBasal: Sendable {
    /// Basal rate in units per hour (U/hr)
    public let rate: Double
    /// Duration in seconds
    public let duration: TimeInterval
    
    public init(rate: Double, duration: TimeInterval) {
        self.rate = rate
        self.duration = duration
    }
}

/// Predicted glucose trajectories under different scenarios.
/// Used to visualize algorithm predictions on a glucose chart.
public struct GlucosePredictions: Sendable {
    /// Predicted glucose considering only insulin on board
    public let iob: [Double]
    /// Predicted glucose considering carbs on board
    public let cob: [Double]
    /// Predicted glucose with unannounced meal detection
    public let uam: [Double]
    /// Predicted glucose if temp basal is set to zero
    public let zt: [Double]
    
    public init(iob: [Double], cob: [Double], uam: [Double], zt: [Double]) {
        self.iob = iob
        self.cob = cob
        self.uam = uam
        self.zt = zt
    }
}

// MARK: - Algorithm Capabilities

/// Declares what features an algorithm supports
/// Requirements: REQ-ALGO-001, REQ-ALGO-004
public struct AlgorithmCapabilities: Sendable, Equatable {
    /// Algorithm supports temp basal adjustments
    public let supportsTempBasal: Bool
    
    /// Algorithm supports SMB (Super Micro Bolus)
    public let supportsSMB: Bool
    
    /// Algorithm supports UAM (Unannounced Meals) detection
    public let supportsUAM: Bool
    
    /// Algorithm supports dynamic ISF
    public let supportsDynamicISF: Bool
    
    /// Algorithm supports autotune/autosens
    public let supportsAutosens: Bool
    
    /// Algorithm provides glucose predictions
    public let providesPredictions: Bool
    
    /// Minimum glucose history required (number of readings)
    public let minGlucoseHistory: Int
    
    /// Recommended glucose history (number of readings)
    public let recommendedGlucoseHistory: Int
    
    /// Algorithm origin (for pedigree tracking)
    public let origin: AlgorithmOrigin
    
    public init(
        supportsTempBasal: Bool = true,
        supportsSMB: Bool = false,
        supportsUAM: Bool = false,
        supportsDynamicISF: Bool = false,
        supportsAutosens: Bool = false,
        providesPredictions: Bool = false,
        minGlucoseHistory: Int = 3,
        recommendedGlucoseHistory: Int = 36,
        origin: AlgorithmOrigin = .custom
    ) {
        self.supportsTempBasal = supportsTempBasal
        self.supportsSMB = supportsSMB
        self.supportsUAM = supportsUAM
        self.supportsDynamicISF = supportsDynamicISF
        self.supportsAutosens = supportsAutosens
        self.providesPredictions = providesPredictions
        self.minGlucoseHistory = minGlucoseHistory
        self.recommendedGlucoseHistory = recommendedGlucoseHistory
        self.origin = origin
    }
}

/// Algorithm origin for pedigree tracking
/// Requirements: REQ-ALGO-005
public enum AlgorithmOrigin: String, Sendable, Codable {
    case oref0 = "OpenAPS/oref0"
    case oref1 = "OpenAPS/oref1"
    case loop = "Loop"
    case loopCommunity = "Loop/Community"      // LoopKit/LoopWorkspace
    case loopTidepool = "Loop/Tidepool"        // tidepool-org/LoopAlgorithm
    case trio = "Trio"
    case glucos = "GlucOS"
    case custom = "Custom"
    
    /// Human-readable description
    public var displayName: String {
        switch self {
        case .oref0: return "oref0 (OpenAPS)"
        case .oref1: return "oref1 (OpenAPS)"
        case .loop: return "Loop (Generic)"
        case .loopCommunity: return "Loop Community (LoopKit/LoopWorkspace)"
        case .loopTidepool: return "Loop Tidepool (FDA-cleared)"
        case .trio: return "Trio"
        case .glucos: return "GlucOS (Experimental)"
        case .custom: return "Custom"
        }
    }
    
    /// Reference repository URL
    public var repositoryURL: String? {
        switch self {
        case .loopCommunity: return "https://github.com/LoopKit/LoopWorkspace"
        case .loopTidepool: return "https://github.com/tidepool-org/LoopAlgorithm"
        case .trio: return "https://github.com/nightscout/Trio"
        case .oref0, .oref1: return "https://github.com/openaps/oref0"
        default: return nil
        }
    }
}

// MARK: - Common Capability Presets

extension AlgorithmCapabilities {
    /// oref0 capabilities: autosens but no SMB/UAM
    public static let oref0 = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: false,
        supportsUAM: false,
        supportsDynamicISF: false,
        supportsAutosens: true,
        providesPredictions: true,
        origin: .oref0
    )
    
    /// oref1 capabilities: SMB, UAM, dynamic ISF, autosens
    public static let oref1 = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: true,
        supportsUAM: true,
        supportsDynamicISF: true,
        supportsAutosens: true,
        providesPredictions: true,
        origin: .oref1
    )
    
    /// Loop capabilities: no SMB, retrospective correction, auto-bolus
    public static let loop = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: false,
        supportsUAM: false,
        supportsDynamicISF: false,
        supportsAutosens: false,
        providesPredictions: true,
        origin: .loop
    )
    
    /// Trio capabilities: SMB, UAM, dynamic ISF
    public static let trio = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: true,
        supportsUAM: true,
        supportsDynamicISF: true,
        supportsAutosens: true,
        providesPredictions: true,
        origin: .trio
    )
    
    /// GlucOS capabilities: dynamic ISF, predictive alerts, exercise mode
    /// Source: UC Davis GlucOS research project
    /// Trace: ADR-010
    public static let glucos = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: false,
        supportsUAM: false,
        supportsDynamicISF: true,
        supportsAutosens: false,
        providesPredictions: true,
        minGlucoseHistory: 5,
        recommendedGlucoseHistory: 24,  // 2 hours for data frames
        origin: .glucos
    )
}

// MARK: - Algorithm Validation

/// Errors during algorithm execution
public enum AlgorithmError: Error, Sendable, LocalizedError {
    case insufficientGlucoseData(required: Int, provided: Int)
    case invalidProfile(reason: String)
    case calculationFailed(reason: String)
    case capabilityNotSupported(capability: String)
    case configurationError(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientGlucoseData(let required, let provided):
            return "Insufficient glucose data: need \(required) readings, have \(provided)"
        case .invalidProfile(let reason):
            return "Invalid profile: \(reason)"
        case .calculationFailed(let reason):
            return "Calculation failed: \(reason)"
        case .capabilityNotSupported(let capability):
            return "Capability not supported: \(capability)"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}

// MARK: - AlgorithmError + T1PalErrorProtocol

extension AlgorithmError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .algorithm }
    
    public var code: String {
        switch self {
        case .insufficientGlucoseData: return "ALG-DATA-001"
        case .invalidProfile: return "ALG-PROFILE-001"
        case .calculationFailed: return "ALG-CALC-001"
        case .capabilityNotSupported: return "ALG-CAP-001"
        case .configurationError: return "ALG-CONFIG-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .insufficientGlucoseData: return .error
        case .invalidProfile: return .critical
        case .calculationFailed: return .error
        case .capabilityNotSupported: return .warning
        case .configurationError: return .critical
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .insufficientGlucoseData: return .checkDevice
        case .invalidProfile: return .contactSupport
        case .calculationFailed: return .retry
        case .capabilityNotSupported: return .none
        case .configurationError: return .contactSupport
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown algorithm error"
    }
}

// MARK: - Algorithm Protocol

/// Protocol for algorithm implementations
/// Requirements: REQ-AID-002, REQ-ALGO-001
public protocol AlgorithmEngine: Sendable {
    /// Unique algorithm identifier
    var name: String { get }
    
    /// Semantic version string
    var version: String { get }
    
    /// Algorithm capabilities
    var capabilities: AlgorithmCapabilities { get }
    
    /// Execute the algorithm with given inputs
    func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision
    
    /// Validate inputs before calculation
    func validate(_ inputs: AlgorithmInputs) -> [AlgorithmError]
}

// Default implementation for validation
public extension AlgorithmEngine {
    func validate(_ inputs: AlgorithmInputs) -> [AlgorithmError] {
        var errors: [AlgorithmError] = []
        
        // Check glucose history
        if inputs.glucose.count < capabilities.minGlucoseHistory {
            errors.append(.insufficientGlucoseData(
                required: capabilities.minGlucoseHistory,
                provided: inputs.glucose.count
            ))
        }
        
        // Check profile validity
        if inputs.profile.basalRates.isEmpty {
            errors.append(.invalidProfile(reason: "No basal rates defined"))
        }
        
        return errors
    }
}

/// Reference implementation - simple proportional controller
/// For testing only - not for production use
/// Stateless and immutable - inherently Sendable
public struct SimpleProportionalAlgorithm: AlgorithmEngine, Sendable {
    public let name = "SimpleProportional"
    public let version = "0.1.0"
    
    public let capabilities = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: false,
        supportsUAM: false,
        supportsDynamicISF: false,
        supportsAutosens: false,
        providesPredictions: false,
        minGlucoseHistory: 1,
        recommendedGlucoseHistory: 12,
        origin: .custom
    )
    
    public init() {}
    
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        guard let latest = inputs.glucose.first else {
            return AlgorithmDecision(reason: "No glucose data")
        }
        
        let target = inputs.profile.targetGlucose.midpoint
        let error = latest.glucose - target
        
        // Simple proportional response
        // This is NOT a real algorithm - just for testing
        let kp = 0.01  // Very conservative gain
        let adjustment = error * kp
        
        // Get scheduled basal (ALG-FIX-T5-003: use time-aware lookup)
        let scheduledBasal = inputs.profile.basalRates.rateAt(date: inputs.currentTime) ?? inputs.profile.basalRates.first?.rate ?? 1.0
        
        // Calculate suggested temp basal
        let suggestedRate = max(0, scheduledBasal + adjustment)
        
        return AlgorithmDecision(
            suggestedTempBasal: TempBasal(rate: suggestedRate, duration: 30 * 60),
            reason: "BG \(Int(latest.glucose)), target \(Int(target)), adjustment \(String(format: "%.2f", adjustment))"
        )
    }
}
