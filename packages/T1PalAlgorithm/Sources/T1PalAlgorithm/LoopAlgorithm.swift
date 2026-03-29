// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopAlgorithm.swift
// T1Pal Mobile
//
// Loop-compatible algorithm integrating all Loop components
// Requirements: REQ-ALGO-013
//
// Combines:
// - LoopInsulinMath (IOB calculation)
// - LoopCarbMath (COB calculation)
// - LoopGlucosePrediction (momentum, insulin, carb effects)
// - RetrospectiveCorrection (prediction accuracy adjustment)
// - LoopDoseRecommendation (temp basal and bolus decisions)
//
// Trace: ALG-020, PRD-009

import Foundation
import T1PalCore

// MARK: - Loop Algorithm Configuration

/// Configuration for the Loop algorithm
public struct LoopAlgorithmConfiguration: Sendable {
    /// Which Loop variant this configuration targets
    /// Community = LoopKit/LoopWorkspace (what most users run)
    /// Tidepool = tidepool-org/LoopAlgorithm (FDA-cleared, may differ)
    public let variant: LoopAlgorithmVariant
    
    /// Insulin model to use
    public let insulinModel: LoopInsulinModel
    
    /// Carb absorption model to use
    public let carbModel: LoopCarbAbsorption
    
    /// Default carb absorption time
    public let defaultAbsorptionTime: TimeInterval
    
    /// Prediction duration
    public let predictionDuration: TimeInterval
    
    /// Enable retrospective correction
    public let enableRetrospectiveCorrection: Bool
    
    /// Retrospective correction configuration
    public let retrospectiveCorrectionConfig: RetrospectiveCorrection.Configuration
    
    /// Maximum basal rate
    public let maxBasalRate: Double
    
    /// Maximum bolus
    public let maxBolus: Double
    
    /// Suspend threshold (glucose)
    public let suspendThreshold: Double
    
    // ALG-LIVE-066: Prediction effect toggles
    /// Whether to include momentum effect in predictions
    public let includeMomentum: Bool
    
    /// Whether to include carb effect in predictions
    public let includeCarbEffect: Bool
    
    /// Whether to include insulin effect in predictions
    public let includeInsulinEffect: Bool
    
    /// Whether to use Integral RC (experimental) instead of Standard RC
    /// Default: false (Standard RC) — matches Loop's default
    /// Set to true only if user has enabled "Integral Retrospective Correction" in Loop's Algorithm Experiments
    public let useIntegralRetrospectiveCorrection: Bool
    
    public init(
        variant: LoopAlgorithmVariant = .community,
        insulinModel: LoopInsulinModel = ExponentialInsulinModel.rapidActingAdult,
        carbModel: LoopCarbAbsorption = PiecewiseLinearCarbAbsorption(),
        defaultAbsorptionTime: TimeInterval = 3 * 3600,
        predictionDuration: TimeInterval = 6 * 3600,
        enableRetrospectiveCorrection: Bool = true,
        retrospectiveCorrectionConfig: RetrospectiveCorrection.Configuration = .default,
        maxBasalRate: Double = 5.0,
        maxBolus: Double = 10.0,
        suspendThreshold: Double = 70.0,
        includeMomentum: Bool = true,
        includeCarbEffect: Bool = true,
        includeInsulinEffect: Bool = true,
        useIntegralRetrospectiveCorrection: Bool = false  // Default: Standard RC
    ) {
        self.variant = variant
        self.insulinModel = insulinModel
        self.carbModel = carbModel
        self.defaultAbsorptionTime = defaultAbsorptionTime
        self.predictionDuration = predictionDuration
        self.enableRetrospectiveCorrection = enableRetrospectiveCorrection
        self.retrospectiveCorrectionConfig = retrospectiveCorrectionConfig
        self.maxBasalRate = maxBasalRate
        self.maxBolus = maxBolus
        self.suspendThreshold = suspendThreshold
        self.includeMomentum = includeMomentum
        self.includeCarbEffect = includeCarbEffect
        self.includeInsulinEffect = includeInsulinEffect
        self.useIntegralRetrospectiveCorrection = useIntegralRetrospectiveCorrection
    }
    
    /// Default configuration (community variant)
    public static let `default` = LoopAlgorithmConfiguration()
    
    /// Community variant - matches LoopKit/LoopWorkspace
    public static let community = LoopAlgorithmConfiguration(variant: .community)
    
    /// Tidepool variant - matches tidepool-org/LoopAlgorithm
    public static let tidepool = LoopAlgorithmConfiguration(variant: .tidepool)
    
    /// Conservative configuration for new users
    public static let conservative = LoopAlgorithmConfiguration(
        maxBasalRate: 2.0,
        maxBolus: 5.0,
        suspendThreshold: 80.0
    )
    
    /// Configuration optimized for Fiasp insulin
    public static let fiasp = LoopAlgorithmConfiguration(
        insulinModel: ExponentialInsulinModel.fiasp
    )
    
    /// Configuration optimized for Lyumjev insulin
    public static let lyumjev = LoopAlgorithmConfiguration(
        insulinModel: ExponentialInsulinModel.lyumjev
    )
    
    /// NS-IOB-001c: Create configuration from TherapyProfile
    /// Uses profile's insulinModel setting for IOB calculations
    public static func from(profile: TherapyProfile) -> LoopAlgorithmConfiguration {
        let insulinPreset = LoopInsulinModelPreset.fromProfileString(profile.insulinModel)
        return LoopAlgorithmConfiguration(
            insulinModel: insulinPreset.loopModel,
            maxBasalRate: profile.maxBasalRate ?? 5.0,
            maxBolus: profile.maxBolus,
            suspendThreshold: profile.suspendThreshold ?? 70.0
        )
    }
}

// MARK: - Loop Algorithm Variant
/// Specifies which Loop implementation variant to use
public enum LoopAlgorithmVariant: String, Sendable, Codable {
    /// Community version from LoopKit/LoopWorkspace
    /// This is what most users run
    case community
    
    /// Tidepool FDA-cleared version from tidepool-org/LoopAlgorithm
    /// Standalone SPM package, may differ from community
    case tidepool
    
    /// Reference path in externals/
    public var externalPath: String {
        switch self {
        case .community: return "externals/LoopWorkspace/LoopKit/LoopKit/"
        case .tidepool: return "externals/LoopAlgorithm/Sources/LoopAlgorithm/"
        }
    }
    
    /// Origin for registry
    public var origin: AlgorithmOrigin {
        switch self {
        case .community: return .loopCommunity
        case .tidepool: return .loopTidepool
        }
    }
}

// MARK: - RC Diagnostics (ALG-RC-008)

/// Diagnostic state from the last RC calculation for debugging divergence
public struct RCDiagnostics: Sendable {
    /// Type of RC used (Standard vs Integral)
    public let rcType: String
    
    /// Number of discrepancies passed to RC
    public let discrepancyCount: Int
    
    /// The discrepancy values (summed)
    public let discrepancies: [LoopGlucoseChange]
    
    /// Last discrepancy value used for velocity calculation
    public let lastDiscrepancyValue: Double?
    
    /// Duration used for velocity calculation (seconds)
    public let discrepancyDuration: TimeInterval?
    
    /// Velocity (mg/dL per second) used for decay effect
    public let velocityPerSecond: Double?
    
    /// Was RC skipped due to recency check?
    public let skippedDueToRecency: Bool
    
    /// RC effect timeline (the output)
    public let effectTimeline: [GlucoseEffect]
    
    /// Total glucose correction effect (from Standard RC)
    public let totalGlucoseCorrectionEffect: Double?
    
    public init(
        rcType: String,
        discrepancyCount: Int,
        discrepancies: [LoopGlucoseChange],
        lastDiscrepancyValue: Double?,
        discrepancyDuration: TimeInterval?,
        velocityPerSecond: Double?,
        skippedDueToRecency: Bool,
        effectTimeline: [GlucoseEffect],
        totalGlucoseCorrectionEffect: Double?
    ) {
        self.rcType = rcType
        self.discrepancyCount = discrepancyCount
        self.discrepancies = discrepancies
        self.lastDiscrepancyValue = lastDiscrepancyValue
        self.discrepancyDuration = discrepancyDuration
        self.velocityPerSecond = velocityPerSecond
        self.skippedDueToRecency = skippedDueToRecency
        self.effectTimeline = effectTimeline
        self.totalGlucoseCorrectionEffect = totalGlucoseCorrectionEffect
    }
}

// MARK: - Loop Algorithm

/// Loop-compatible algorithm engine
/// Integrates all Loop math components into a single cohesive algorithm
///
/// Remains a class (not struct) because cycle-to-cycle state is required:
/// - `_lastPredictions`: Retrospective correction compares prior predictions to actuals
/// - `_correctionHistory`: Tracks RC results for the legacy RC path
/// These are NOT pure diagnostics — they affect algorithm output on subsequent calls.
///
/// All pure diagnostic state (ICE, insulin effects, IOB breakdown, RC diagnostics)
/// is now returned in AlgorithmDecision.diagnostics instead of cached here.
public final class LoopAlgorithm: AlgorithmEngine, @unchecked Sendable {
    /// Name includes variant for disambiguation
    public var name: String {
        switch configuration.variant {
        case .community: return "Loop"  // Default/primary
        case .tidepool: return "Loop-Tidepool"
        }
    }
    public let version = "1.0.0"
    
    /// Capabilities with origin based on variant
    public var capabilities: AlgorithmCapabilities {
        AlgorithmCapabilities(
            supportsTempBasal: true,
            supportsSMB: false,  // Loop uses temp basals, not SMBs
            supportsUAM: false,
            supportsDynamicISF: false,
            supportsAutosens: false,
            providesPredictions: true,
            minGlucoseHistory: 3,
            recommendedGlucoseHistory: 36,  // 3 hours
            origin: configuration.variant.origin
        )
    }
    
    // Configuration
    public let configuration: LoopAlgorithmConfiguration
    
    // Components (immutable after init)
    private let iobCalculator: LoopIOBCalculator
    private let cobCalculator: LoopCOBCalculator
    private let carbEffectCalculator: LoopCarbEffectCalculator
    private let predictionEngine: LoopGlucosePrediction
    private let retrospectiveCorrection: RetrospectiveCorrection
    private let doseCalculator: LoopDoseCalculator
    
    // Cycle-to-cycle state required for algorithm correctness (NOT diagnostics).
    // _lastPredictions: retrospective correction needs prior cycle's predictions.
    // _correctionHistory: legacy RC path accumulates corrections over time.
    // _lastDiagnostics: cached for backward-compatible public accessors.
    private let stateLock = NSLock()
    private var _lastPredictions: [PredictedGlucose] = []
    private var _correctionHistory: [RetrospectiveCorrectionResult] = []
    private var _lastDiagnostics: LoopDiagnostics?
    
    /// Thread-safe access to last predictions
    private var lastPredictions: [PredictedGlucose] {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _lastPredictions
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _lastPredictions = newValue
        }
    }
    
    /// Thread-safe access to correction history
    private var correctionHistory: [RetrospectiveCorrectionResult] {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _correctionHistory
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _correctionHistory = newValue
        }
    }
    
    public init(configuration: LoopAlgorithmConfiguration = .default) {
        self.configuration = configuration
        
        // Initialize components
        self.iobCalculator = LoopIOBCalculator(model: configuration.insulinModel)
        self.cobCalculator = LoopCOBCalculator(absorptionModel: configuration.carbModel)
        self.carbEffectCalculator = LoopCarbEffectCalculator(cobCalculator: cobCalculator)
        
        // ALG-LIVE-066: Wire effect toggles to prediction engine
        self.predictionEngine = LoopGlucosePrediction(
            configuration: .init(
                predictionDuration: configuration.predictionDuration,
                includeMomentum: configuration.includeMomentum,
                includeCarbEffect: configuration.includeCarbEffect,
                includeInsulinEffect: configuration.includeInsulinEffect
            )
        )
        
        self.retrospectiveCorrection = RetrospectiveCorrection(
            configuration: configuration.retrospectiveCorrectionConfig
        )
        
        self.doseCalculator = LoopDoseCalculator(
            configuration: .init(
                maxBasalRate: configuration.maxBasalRate,
                maxBolus: configuration.maxBolus,
                suspendThreshold: configuration.suspendThreshold
            )
        )
    }
    
    // MARK: - State Seeding (ALG-PRED-001)
    
    /// Seed lastPredictions for retrospective correction on first run
    /// Use this to provide Loop's actual predictions from deviceStatus when running in replay mode
    /// - Parameter predictions: Loop's predicted glucose values from a previous cycle
    public func seedPredictions(_ predictions: [PredictedGlucose]) {
        lastPredictions = predictions
    }
    
    /// Convenience method to seed from raw glucose values starting at a given date
    /// - Parameters:
    ///   - values: Glucose values in mg/dL (5-min intervals expected)
    ///   - startDate: When the first prediction value applies
    public func seedPredictions(values: [Double], startDate: Date) {
        var predictions: [PredictedGlucose] = []
        for (index, glucose) in values.enumerated() {
            let date = startDate.addingTimeInterval(TimeInterval(index * 300))  // 5-min intervals
            predictions.append(PredictedGlucose(date: date, glucose: glucose))
        }
        lastPredictions = predictions
    }
    
    // MARK: - AlgorithmEngine Implementation
    
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        let now = inputs.currentTime
        
        // Validate inputs
        let errors = validate(inputs)
        if !errors.isEmpty {
            throw errors.first!
        }
        
        guard let latestGlucose = inputs.glucose.first else {
            return AlgorithmDecision(reason: "No glucose data")
        }
        
        // Extract therapy values (ALG-FIX-T5-003: use time-aware lookup)
        let profile = inputs.profile
        let scheduledBasal = profile.basalRates.rateAt(date: now) ?? profile.basalRates.first?.rate ?? 1.0
        let isf = profile.sensitivityFactors.factorAt(date: now) ?? profile.sensitivityFactors.first?.factor ?? 50.0
        let icr = profile.carbRatios.ratioAt(date: now) ?? profile.carbRatios.first?.ratio ?? 10.0
        let targetGlucose = profile.targetGlucose.midpoint
        
        // Build dose entries: use real history if available, else synthesize from IOB
        let doseEntries: [InsulinDose]
        let usingRealDoseHistory: Bool
        if let history = inputs.doseHistory, !history.isEmpty {
            doseEntries = history  // High-fidelity path (ALG-LIVE-048)
            usingRealDoseHistory = true
        } else {
            doseEntries = buildDoseEntries(iob: inputs.insulinOnBoard, at: now)
            usingRealDoseHistory = false
        }
        
        // Build carb entries: use real history if available, else synthesize from COB
        let carbEntries: [CarbEntry]
        let usingRealCarbHistory: Bool
        if let history = inputs.carbHistory, !history.isEmpty {
            carbEntries = history  // High-fidelity path (ALG-LIVE-049)
            usingRealCarbHistory = true
        } else {
            carbEntries = buildCarbEntries(cob: inputs.carbsOnBoard, at: now)
            usingRealCarbHistory = false
        }
        
        // Log fidelity mode for debugging
        _ = (usingRealDoseHistory, usingRealCarbHistory)  // Available for future diagnostics
        
        // Calculate IOB from dose history
        // ALG-WIRE-002/003: Use parity IOB with net basal units when basalSchedule is available
        let iob: Double
        if let basalSchedule = inputs.basalSchedule, !basalSchedule.isEmpty {
            // Loop-parity path: net basal units calculation
            // This uses BasalRelativeDose annotation for accurate IOB
            iob = doseEntries.insulinOnBoardParity(
                at: now,
                basalSchedule: basalSchedule
            )
        } else {
            // Legacy path: absolute units calculation
            // Used when basal schedule not available (fallback)
            iob = iobCalculator.insulinOnBoard(
                doses: doseEntries,
                at: now
            )
        }
        
        // ALG-RC-007: Track IOB diagnostic values locally (output via AlgorithmDiagnostics)
        let diagIOBUsedBasalSchedule = inputs.basalSchedule != nil && !(inputs.basalSchedule?.isEmpty ?? true)
        
        // ALG-DIAG-GEFF-005: Use CGM reading time for prediction alignment
        let predictionStartDate = latestGlucose.timestamp
        
        // ALG-DIAG-ICE-001: Compute Insulin Counteraction Effects
        // ICE measures how much glucose changed vs what insulin effect predicted
        // Positive ICE = something countering insulin (carbs, stress, etc.)
        // This is used for dynamic carb absorption and retrospective correction
        var insulinCounteractionEffects: [GlucoseEffectVelocity] = []
        var diagInsulinEffects: [GlucoseEffectValue] = []  // ALG-RC-004: for diagnostics output
        if let basalSchedule = inputs.basalSchedule, !basalSchedule.isEmpty {
            // Compute insulin effects timeline for ICE calculation
            // ALG-100-RECONCILE: Reconcile overlapping doses before annotation
            let rawDoses = doseEntries.toReconciledRawInsulinDoses()
            let annotatedDoses = rawDoses.annotated(with: basalSchedule)
            let insulinEffects = annotatedDoses.glucoseEffects(
                insulinSensitivity: isf,
                from: predictionStartDate.addingTimeInterval(-6 * 3600),  // Look back 6 hours for effect history
                to: predictionStartDate.addingTimeInterval(6 * 3600),     // Look forward for prediction
                delta: 5 * 60  // 5-minute intervals
            )
            
            // ALG-RC-004: Track insulin effects for diagnostics output
            diagInsulinEffects = insulinEffects
            
            // Convert GlucoseEffectValue to GlucoseEffect for counteractionEffects
            let effectsForICE = insulinEffects.map { GlucoseEffect(date: $0.startDate, quantity: $0.value) }
            
            // Compute counteraction: actual glucose change - expected insulin effect change
            insulinCounteractionEffects = inputs.glucose.counteractionEffects(to: effectsForICE)
        }
        
        // Calculate COB from carb history
        // ALG-DIAG-ICE-002: Use ICE for dynamic carb absorption when available
        let cob: Double
        // Keep carbStatus in scope for RC discrepancy calculation
        var carbStatusForRC: [CarbStatus<CarbEntry>]? = nil
        if usingRealCarbHistory && !insulinCounteractionEffects.isEmpty {
            // Loop-parity path with ICE: dynamic absorption based on observed glucose changes
            // This maps carbs to observed effects using ICE
            let carbStatus = carbEntries.map(
                to: insulinCounteractionEffects,
                insulinSensitivity: isf,
                carbRatio: icr
            )
            cob = carbStatus.dynamicCarbsOnBoard(at: now)
            carbStatusForRC = carbStatus  // Save for RC calculation
        } else if usingRealCarbHistory {
            // Parity path without ICE: piecewise linear absorption with effect delay
            cob = carbEntries.carbsOnBoardParity(at: now)
        } else {
            // Legacy path: simple absorption model
            cob = cobCalculator.carbsOnBoard(
                entries: carbEntries,
                at: now
            )
        }
        
        // ALG-DIAG-ICE-003: Compute retrospective correction from ICE
        // RC = discrepancies from ICE - expected carb effects
        var rcEffects: [GlucoseEffect]? = nil
        var correctionApplied = false
        var diagRCDiagnostics: RCDiagnostics? = nil  // ALG-RC-008: for diagnostics output
        
        if configuration.enableRetrospectiveCorrection && !insulinCounteractionEffects.isEmpty {
            // T6-005: Check if glucose data is smooth enough for RC
            // Loop disables RC when glucose has large jumps (>40 mg/dL)
            let rcWindowStart = predictionStartDate.addingTimeInterval(-RetrospectiveCorrectionConstants.groupingInterval)
            let recentReadings = inputs.glucose.filter { $0.timestamp >= rcWindowStart && $0.timestamp <= predictionStartDate }
            let useRC = hasGradualTransitions(recentReadings, threshold: 40.0)
            
            if useRC {
                // ALG-DIAG-ICE-004: Compute carb effect velocities for discrepancy calculation
                var carbEffectVelocities: [GlucoseEffectVelocity] = []
                if let carbStatus = carbStatusForRC, !carbStatus.isEmpty {
                    // Compute carb glucose effects timeline and convert to velocities
                    let rcStart = predictionStartDate.addingTimeInterval(-RetrospectiveCorrectionConstants.standardRetrospectionInterval)
                    let carbEffects = carbStatus.dynamicGlucoseEffects(
                        from: rcStart,
                        to: predictionStartDate,
                        insulinSensitivity: isf,
                        carbRatio: icr
                    )
                    carbEffectVelocities = carbStatus.glucoseEffectVelocities(from: carbEffects)
                }
                
                // Calculate discrepancies: ICE - carb_effects
                let discrepancies = DiscrepancyCalculator.calculateDiscrepancies(
                    insulinCounteractionEffects: insulinCounteractionEffects,
                    carbEffects: carbEffectVelocities,
                    groupingInterval: RetrospectiveCorrectionConstants.groupingInterval
                )
                
                // Select RC type based on configuration
                // Standard RC = proportional controller using ONLY last discrepancy (Loop default)
                // Integral RC = accumulates discrepancies over time (experimental, more aggressive)
                // AID-IRC-001: Check for runtime override via UserDefaults
                let useIntegralRC = Self.checkIntegralRCOverride() ?? configuration.useIntegralRetrospectiveCorrection
                let loopRCEffects: [LoopGlucoseEffect]
                
                if useIntegralRC {
                    var rc = IntegralRetrospectiveCorrection()
                    loopRCEffects = rc.computeEffect(
                        startingAt: SimpleGlucoseValue(startDate: latestGlucose.timestamp, quantity: latestGlucose.glucose),
                        retrospectiveGlucoseDiscrepanciesSummed: discrepancies,
                        recencyInterval: RetrospectiveCorrectionConstants.recencyInterval,
                        retrospectiveCorrectionGroupingInterval: RetrospectiveCorrectionConstants.groupingInterval
                    )
                    // Build diagnostics for Integral RC
                    diagRCDiagnostics = RCDiagnostics(
                        rcType: "Integral",
                        discrepancyCount: discrepancies.count,
                        discrepancies: discrepancies,
                        lastDiscrepancyValue: discrepancies.last?.quantity,
                        discrepancyDuration: discrepancies.last?.duration,
                        velocityPerSecond: nil,  // Integral RC doesn't use simple velocity
                        skippedDueToRecency: loopRCEffects.isEmpty,
                        effectTimeline: loopRCEffects.map { GlucoseEffect(date: $0.startDate, quantity: $0.quantity) },
                        totalGlucoseCorrectionEffect: nil
                    )
                } else {
                    var rc = StandardRetrospectiveCorrection()
                    loopRCEffects = rc.computeEffect(
                        startingAt: SimpleGlucoseValue(startDate: latestGlucose.timestamp, quantity: latestGlucose.glucose),
                        retrospectiveGlucoseDiscrepanciesSummed: discrepancies,
                        recencyInterval: RetrospectiveCorrectionConstants.recencyInterval,
                        retrospectiveCorrectionGroupingInterval: RetrospectiveCorrectionConstants.groupingInterval
                    )
                    // Build diagnostics for Standard RC (ALG-RC-008)
                    diagRCDiagnostics = RCDiagnostics(
                        rcType: "Standard",
                        discrepancyCount: rc.discrepancyCount,
                        discrepancies: discrepancies,
                        lastDiscrepancyValue: rc.lastDiscrepancyValue,
                        discrepancyDuration: rc.discrepancyDuration,
                        velocityPerSecond: rc.velocityPerSecond,
                        skippedDueToRecency: rc.skippedDueToRecency,
                        effectTimeline: loopRCEffects.map { GlucoseEffect(date: $0.startDate, quantity: $0.quantity) },
                        totalGlucoseCorrectionEffect: rc.totalGlucoseCorrectionEffect
                    )
                }
                
                // RC diagnostics tracked in diagRCDiagnostics for output
                
                // Convert to GlucoseEffect for prediction engine
                // ALG-100-RC: RC effects from decayEffect are CUMULATIVE (starting at current glucose)
                // Our combinedPrediction expects cumulative values and computes deltas internally
                // (same as Loop's predictGlucose at LoopMath.swift:121-127)
                if !loopRCEffects.isEmpty {
                    rcEffects = loopRCEffects.map { effect in
                        GlucoseEffect(date: effect.startDate, quantity: effect.quantity)
                    }
                    correctionApplied = true
                }
            }
        }
        
        // Generate glucose predictions
        // ALG-DIAG-GEFF: Wire basalSchedule for parity glucose effects
        var predictions = predictionEngine.predict(
            currentGlucose: latestGlucose.glucose,
            glucoseHistory: inputs.glucose,
            doses: doseEntries,
            carbEntries: carbEntries,
            insulinSensitivity: isf,
            carbRatio: icr,
            startDate: predictionStartDate,
            basalSchedule: inputs.basalSchedule,
            retrospectiveCorrectionEffects: rcEffects
        )
        
        // Legacy RC path (only if ICE path didn't apply)
        if !correctionApplied && configuration.enableRetrospectiveCorrection && !lastPredictions.isEmpty {
            let correctionResult = retrospectiveCorrection.analyze(
                predictions: lastPredictions,
                actuals: inputs.glucose,
                referenceDate: now
            )
            
            if correctionResult.isSignificant {
                // Apply correction to predictions
                predictions = applyCorrection(
                    predictions: predictions,
                    correction: correctionResult.correctionEffect
                )
                correctionApplied = true
                correctionHistory.append(correctionResult)
            }
        }
        
        // Store predictions for next cycle's retrospective correction
        lastPredictions = predictions
        
        // Calculate min and eventual glucose from predictions
        let minGlucose = predictions.map { $0.glucose }.min() ?? latestGlucose.glucose
        let eventualGlucose = predictions.last?.glucose ?? latestGlucose.glucose
        
        // Get dose recommendation
        // ALG-DIAG-024: Pass ISF and target schedules for parity insulin correction
        // ALG-PRED-001: Pass RC effects so dose calculator uses RC-adjusted predictions
        let doseResult = doseCalculator.recommendTempBasal(
            currentGlucose: latestGlucose.glucose,
            glucoseHistory: inputs.glucose,
            doses: doseEntries,
            carbEntries: carbEntries,
            scheduledBasalRate: scheduledBasal,
            insulinSensitivity: isf,
            carbRatio: icr,
            targetGlucose: targetGlucose,
            basalSchedule: inputs.basalSchedule,
            insulinSensitivitySchedule: inputs.insulinSensitivitySchedule,
            correctionRangeSchedule: inputs.correctionRangeSchedule,
            retrospectiveCorrectionEffects: rcEffects  // ALG-PRED-001
        )
        
        // Build reason string
        var reason = doseResult.recommendation.reason
        if correctionApplied {
            reason += " | RC"
        }
        // ALG-100-IOB: Include both computed and input IOB for debugging
        let inputIOB = inputs.insulinOnBoard
        if abs(iob - inputIOB) > 0.01 {
            reason += " | IOB \(String(format: "%.3f", iob))U (Loop: \(String(format: "%.3f", inputIOB))U)"
        } else {
            reason += " | IOB \(String(format: "%.1f", iob))U"
        }
        if cob > 0 {
            reason += " | COB \(String(format: "%.0f", cob))g"
        }
        reason += " | min \(String(format: "%.0f", minGlucose)) eventual \(String(format: "%.0f", eventualGlucose))"
        
        // Convert to AlgorithmDecision
        // ALG-LIVE-064: Apply safety limits from profile (if provided) or configuration
        let effectiveMaxBasal = profile.maxBasalRate ?? configuration.maxBasalRate
        let effectiveMaxBolus = profile.maxBolus > 0 ? profile.maxBolus : configuration.maxBolus
        _ = profile.suspendThreshold ?? configuration.suspendThreshold  // effectiveSuspendThreshold for safety reference
        
        // GAP-012: High basal threshold constraint
        // If minGlucose < target lower bound, cap temp basal at neutral (scheduled) rate
        let targetLowerBound = profile.targetGlucose.low
        let minGlucoseBelowTarget = minGlucose < targetLowerBound
        
        let tempBasal: TempBasal?
        switch doseResult.recommendation.type {
        case .tempBasal:
            var rate = doseResult.recommendation.rate ?? scheduledBasal
            
            // GAP-012: Cap to neutral if min prediction dips below target
            if minGlucoseBelowTarget && rate > scheduledBasal {
                rate = scheduledBasal
            }
            
            // GAP-013: In automatic bolus mode, always use neutral basal
            // (Correction is delivered via bolus, not increased basal)
            if profile.isAutomaticBolus {
                rate = scheduledBasal
            }
            
            // ALG-LIVE-064: Cap to max basal rate
            rate = min(rate, effectiveMaxBasal)
            tempBasal = TempBasal(
                rate: rate,
                duration: doseResult.recommendation.duration ?? 30 * 60
            )
        case .suspend:
            tempBasal = TempBasal(rate: 0, duration: 30 * 60)
        default:
            tempBasal = nil
        }
        
        // ALG-LIVE-063: Calculate automatic bolus if dosing strategy is "automaticBolus"
        var suggestedBolus: Double? = nil
        if profile.isAutomaticBolus {
            // Calculate SMB-like bolus: portion of needed correction delivered as bolus
            // Loop delivers ~40% of needed insulin as automatic bolus per cycle
            let correctionNeeded = (eventualGlucose - targetGlucose) / isf
            
            // GAP-014: Block automatic bolus if ANY prediction dips below target
            // This is a critical safety check matching Loop's DoseMath behavior
            if correctionNeeded > 0 && iob < profile.maxIOB && !minGlucoseBelowTarget {
                let availableIOBRoom = profile.maxIOB - iob
                let bolusAmount = min(correctionNeeded * 0.4, availableIOBRoom)
                // ALG-LIVE-064: Cap to max bolus
                suggestedBolus = min(max(bolusAmount, 0), effectiveMaxBolus)
                if suggestedBolus! < 0.05 {
                    suggestedBolus = nil  // Below minimum deliverable
                }
            }
        }
        
        // Update reason with applied limits
        var updatedReason = reason
        if profile.maxBasalRate != nil || profile.suspendThreshold != nil || profile.isAutomaticBolus {
            updatedReason += " | limits: max \(String(format: "%.1f", effectiveMaxBasal))U/hr"
            if profile.isAutomaticBolus {
                updatedReason += " AB"
            }
        }
        
        // Build predictions for output
        let glucosePredictions = buildGlucosePredictions(from: predictions, minGlucose: minGlucose)
        
        // ALG-DIAG-030: Build diagnostics from local values (replaces mutable _last* state)
        let loopDiagnostics = LoopDiagnostics(
            rcDiagnostics: diagRCDiagnostics,
            insulinCounteractionEffects: insulinCounteractionEffects,
            insulinEffects: diagInsulinEffects,
            computedIOB: iob,
            inputIOB: inputs.insulinOnBoard,
            doseCount: doseEntries.count,
            iobUsedBasalSchedule: diagIOBUsedBasalSchedule,
            iobCalculationTime: now,
            recentCorrections: Array(correctionHistory.suffix(10).reversed())
        )
        
        // Cache diagnostics for backward-compatible public accessors
        stateLock.lock()
        _lastDiagnostics = loopDiagnostics
        stateLock.unlock()
        
        return AlgorithmDecision(
            timestamp: now,
            suggestedTempBasal: tempBasal,
            suggestedBolus: suggestedBolus,
            reason: updatedReason,
            predictions: glucosePredictions,
            diagnostics: AlgorithmDiagnostics(loop: loopDiagnostics)
        )
    }
    
    // MARK: - Helper Methods
    
    private func buildDoseEntries(iob: Double, at date: Date) -> [InsulinDose] {
        // Simplified: create a single dose entry representing current IOB
        // Real implementation would track actual dose history
        guard iob > 0 else { return [] }
        
        // Backdate dose to give reasonable IOB curve
        let doseTime = date.addingTimeInterval(-2 * 3600)  // 2 hours ago
        return [
            InsulinDose(
                units: iob * 2,  // Approximate original dose
                timestamp: doseTime
            )
        ]
    }
    
    private func buildCarbEntries(cob: Double, at date: Date) -> [CarbEntry] {
        // Simplified: create a single carb entry representing current COB
        guard cob > 0 else { return [] }
        
        // Backdate carbs
        let carbTime = date.addingTimeInterval(-1 * 3600)  // 1 hour ago
        return [
            CarbEntry(
                grams: cob * 2,  // Approximate original carbs
                timestamp: carbTime,
                absorptionTime: configuration.defaultAbsorptionTime / 3600  // hours
            )
        ]
    }
    
    private func applyCorrection(
        predictions: [PredictedGlucose],
        correction: [GlucoseEffect]
    ) -> [PredictedGlucose] {
        guard !correction.isEmpty else { return predictions }
        
        // Create a dictionary of corrections by date
        var correctionByDate: [Date: Double] = [:]
        for effect in correction {
            correctionByDate[effect.date] = effect.quantity
        }
        
        // Apply corrections to predictions
        // ALG-DIAG-T6-003: Skip predictions[0] - the starting glucose should not be modified by RC
        return predictions.enumerated().map { (index, prediction) in
            // Don't modify the starting point (index 0)
            if index == 0 {
                return prediction
            }
            
            // Find nearest correction
            let correctionValue = correctionByDate[prediction.date] ??
                findNearestCorrection(for: prediction.date, in: correction)
            
            return PredictedGlucose(
                date: prediction.date,
                glucose: max(39, min(400, prediction.glucose + correctionValue))
            )
        }
    }
    
    private func findNearestCorrection(for date: Date, in corrections: [GlucoseEffect]) -> Double {
        guard let nearest = corrections.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            return 0
        }
        return nearest.quantity
    }
    
    private func buildGlucosePredictions(
        from predictions: [PredictedGlucose],
        minGlucose: Double
    ) -> GlucosePredictions {
        // Extract glucose values from predictions
        let values = predictions.map { $0.glucose }
        
        return GlucosePredictions(
            iob: values,  // Using combined as proxy
            cob: values,
            uam: [],      // Loop doesn't have UAM
            zt: [minGlucose]
        )
    }
    
    // MARK: - Public Accessors
    
    /// Get IOB for a set of doses at a specific time
    public func calculateIOB(doses: [InsulinDose], at date: Date) -> Double {
        iobCalculator.insulinOnBoard(doses: doses, at: date)
    }
    
    /// Get COB for carb entries at a specific time
    public func calculateCOB(
        carbs: [CarbEntry],
        at date: Date,
        absorptionTime: TimeInterval? = nil
    ) -> Double {
        cobCalculator.carbsOnBoard(
            entries: carbs,
            at: date
        )
    }
    
    /// Get glucose prediction
    public func predict(
        startingGlucose: Double,
        at date: Date,
        doses: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        isf: Double,
        icr: Double,
        basalSchedule: [AbsoluteScheduleValue<Double>]? = nil
    ) -> [PredictedGlucose] {
        predictionEngine.predict(
            currentGlucose: startingGlucose,
            doses: doses,
            carbEntries: carbs,
            insulinSensitivity: isf,
            carbRatio: icr,
            startDate: date,
            basalSchedule: basalSchedule
        )
    }
    
    /// Get dose recommendation for a meal
    public func recommendMealBolus(
        currentGlucose: Double,
        carbGrams: Double,
        doses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        targetGlucose: Double,
        isf: Double,
        icr: Double
    ) -> LoopRecommendationResult {
        doseCalculator.recommendBolus(
            currentGlucose: currentGlucose,
            carbsToEat: carbGrams,
            doses: doses,
            carbEntries: carbEntries,
            insulinSensitivity: isf,
            carbRatio: icr,
            targetGlucose: targetGlucose
        )
    }
    
    /// Get retrospective correction history
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.recentCorrections instead.
    public var recentCorrections: [RetrospectiveCorrectionResult] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.recentCorrections ?? []
    }
    
    /// Get last RC diagnostics for debugging (ALG-RC-008)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.rcDiagnostics instead.
    public var lastRCDiagnostics: RCDiagnostics? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.rcDiagnostics
    }
    
    /// Get last insulin counteraction effects for debugging (ALG-RC-001)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.insulinCounteractionEffects instead.
    public var debugLastInsulinCounteractionEffects: [GlucoseEffectVelocity] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.insulinCounteractionEffects ?? []
    }
    
    /// Get last insulin effects for debugging (ALG-RC-004)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.insulinEffects instead.
    public var debugLastInsulinEffects: [GlucoseEffectValue] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.insulinEffects ?? []
    }
    
    /// Get last computed IOB for debugging (ALG-RC-007)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.computedIOB instead.
    public var debugLastIOB: Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.computedIOB ?? 0
    }
    
    /// Get last input IOB for debugging (ALG-RC-007)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.inputIOB instead.
    public var debugLastInputIOB: Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.inputIOB ?? 0
    }
    
    /// Get last dose count for debugging (ALG-RC-007)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.doseCount instead.
    public var debugLastDoseCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.doseCount ?? 0
    }
    
    /// Get whether last IOB used basal schedule (ALG-RC-007)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.iobUsedBasalSchedule instead.
    public var debugLastIOBUsedBasalSchedule: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.iobUsedBasalSchedule ?? false
    }
    
    /// Get last IOB calculation time (ALG-RC-007)
    /// Prefer reading from AlgorithmDecision.diagnostics?.loop?.iobCalculationTime instead.
    public var debugLastIOBCalculationTime: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastDiagnostics?.iobCalculationTime
    }
    
    // MARK: - Runtime IRC Override (AID-IRC-001)
    
    /// UserDefaults key for IRC override
    private static let ircOverrideKey = "algorithm.useIntegralRetrospectiveCorrection"
    
    /// Check for runtime IRC setting override
    /// - Returns: The override value if set, nil to use configuration default
    public static func checkIntegralRCOverride() -> Bool? {
        // Check if key exists in UserDefaults
        let defaults = UserDefaults.standard
        if defaults.object(forKey: ircOverrideKey) != nil {
            return defaults.bool(forKey: ircOverrideKey)
        }
        return nil  // No override, use configuration
    }
    
    /// Set IRC override for runtime configuration
    /// - Parameter enabled: true to use Integral RC, false for Standard RC, nil to clear override
    public static func setIntegralRCOverride(_ enabled: Bool?) {
        let defaults = UserDefaults.standard
        if let enabled = enabled {
            defaults.set(enabled, forKey: ircOverrideKey)
        } else {
            defaults.removeObject(forKey: ircOverrideKey)
        }
    }
    
    /// Clear stored state (for testing)
    public func reset() {
        lastPredictions = []
        correctionHistory = []
        stateLock.lock()
        _lastDiagnostics = nil
        stateLock.unlock()
    }
}

// MARK: - Registry Extension

extension AlgorithmRegistry {
    /// Register Loop algorithm with default configuration
    public func registerLoop() {
        let loop = LoopAlgorithm()
        registerOrReplace(loop)
    }
    
    /// Register Loop algorithm with custom configuration
    public func registerLoop(configuration: LoopAlgorithmConfiguration) {
        let loop = LoopAlgorithm(configuration: configuration)
        registerOrReplace(loop)
    }
    
    /// Register Loop algorithm optimized for Fiasp
    public func registerLoopFiasp() {
        let loop = LoopAlgorithm(configuration: .fiasp)
        registerOrReplace(loop)
    }
    
    /// Register Loop algorithm optimized for Lyumjev
    public func registerLoopLyumjev() {
        let loop = LoopAlgorithm(configuration: .lyumjev)
        registerOrReplace(loop)
    }
}

// MARK: - Convenience Initializers

extension LoopAlgorithm {
    /// Create with a specific insulin model
    public convenience init(insulinModel: LoopInsulinModel) {
        self.init(configuration: LoopAlgorithmConfiguration(insulinModel: insulinModel))
    }
    
    /// Create with safety limits
    public convenience init(
        maxBasalRate: Double,
        maxBolus: Double,
        suspendThreshold: Double = 70.0
    ) {
        self.init(configuration: LoopAlgorithmConfiguration(
            maxBasalRate: maxBasalRate,
            maxBolus: maxBolus,
            suspendThreshold: suspendThreshold
        ))
    }
}

// MARK: - Helper Functions

/// Check if glucose readings have gradual transitions (no large jumps)
/// Matches Loop's hasGradualTransitions from GlucoseMath.swift
/// - Parameters:
///   - readings: Array of glucose readings
///   - threshold: Maximum allowed difference between consecutive readings (default 40 mg/dL)
/// - Returns: True if all consecutive differences are within threshold
private func hasGradualTransitions(_ readings: [GlucoseReading], threshold: Double = 40.0) -> Bool {
    guard readings.count > 1 else {
        return false  // A single point could be a spike
    }
    
    let sorted = readings.sorted { $0.timestamp < $1.timestamp }
    
    for i in 0..<(sorted.count - 1) {
        let current = sorted[i].glucose
        let next = sorted[i + 1].glucose
        let difference = abs(next - current)
        
        if difference > threshold {
            return false
        }
    }
    
    return true
}

// MARK: - Time-Aware Schedule Lookup (ALG-FIX-T5-003)

extension Array where Element == BasalRate {
    /// Get the active basal rate for a given date
    /// Uses closestPrior semantics matching Loop's approach
    func rateAt(date: Date) -> Double? {
        guard !isEmpty else { return nil }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let secondsFromMidnight = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        
        // Find the last entry that starts at or before the current time
        let sorted = self.sorted { $0.startTime < $1.startTime }
        var result = sorted.first
        for entry in sorted {
            if entry.startTime <= secondsFromMidnight {
                result = entry
            } else {
                break
            }
        }
        return result?.rate
    }
}

extension Array where Element == SensitivityFactor {
    /// Get the active ISF for a given date
    func factorAt(date: Date) -> Double? {
        guard !isEmpty else { return nil }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let secondsFromMidnight = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        
        let sorted = self.sorted { $0.startTime < $1.startTime }
        var result = sorted.first
        for entry in sorted {
            if entry.startTime <= secondsFromMidnight {
                result = entry
            } else {
                break
            }
        }
        return result?.factor
    }
}

extension Array where Element == CarbRatio {
    /// Get the active ICR for a given date
    func ratioAt(date: Date) -> Double? {
        guard !isEmpty else { return nil }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let secondsFromMidnight = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        
        let sorted = self.sorted { $0.startTime < $1.startTime }
        var result = sorted.first
        for entry in sorted {
            if entry.startTime <= secondsFromMidnight {
                result = entry
            } else {
                break
            }
        }
        return result?.ratio
    }
}
