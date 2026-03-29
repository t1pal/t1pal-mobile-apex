// LoopReplayEngine.swift
// T1PalAlgorithm
//
// ALG-ARCH-010: Orchestrates Loop replay with the new architecture.
// Design: docs/architecture/ALG-ARCH-002-005-design.md

import Foundation
import T1PalCore

/// Orchestrates Loop replay with structural temporal alignment.
///
/// Usage:
/// ```swift
/// let engine = LoopReplayEngine(
///     deviceStatuses: records,
///     treatments: treatments,
///     glucose: glucose,
///     profile: profile,
///     settings: settings
/// )
///
/// for result in engine.replay() {
///     print(result.comparison.prediction.significance)
/// }
/// ```
public final class LoopReplayEngine: Sendable {
    
    /// Devicestatus sequence with cross-record linking
    public let sequence: DeviceStatusSequence
    
    /// Input reconstructor for each cycle
    public let reconstructor: InputReconstructor
    
    /// Algorithm runner (injected for testability)
    private let algorithmRunner: AlgorithmRunnerProtocol
    
    // MARK: - Initialization
    
    /// Create a replay engine from Nightscout data
    public init(
        deviceStatuses: [DeviceStatusRecord],
        treatments: [TreatmentRecord],
        glucose: [GlucoseRecord],
        profile: NightscoutProfileData,
        settings: TherapySettingsSnapshot,
        algorithmRunner: AlgorithmRunnerProtocol = DefaultAlgorithmRunner()
    ) {
        self.sequence = DeviceStatusSequence(
            records: deviceStatuses,
            defaultSettings: settings
        )
        self.reconstructor = InputReconstructor(
            treatments: treatments,
            glucose: glucose,
            profile: profile
        )
        self.algorithmRunner = algorithmRunner
    }
    
    // MARK: - Replay
    
    /// Replay all cycles and return comparisons
    public func replay() -> [LoopReplayResult] {
        sequence.cycles.map { cycle in
            replayCycle(cycle)
        }
    }
    
    /// Replay a single cycle
    public func replayCycle(_ cycle: LoopCycleState) -> LoopReplayResult {
        // 1. Build inputs from Loop's perspective
        let iobInput = reconstructor.buildIOBInput(for: cycle)
        let predictionInput = reconstructor.buildPredictionInput(for: cycle)
        
        // 2. Run our algorithm
        let ourIOB = algorithmRunner.calculateIOB(iobInput)
        let ourPrediction = algorithmRunner.calculatePrediction(predictionInput)
        let ourRecommendation = algorithmRunner.calculateRecommendation(predictionInput)
        
        // 3. Calculate enacted (after ifNecessary filter) - ALG-ZERO-DIV-012
        let scheduledBasalRate = cycle.settings.basalSchedule.first?.rate ?? 1.0
        let ourEnacted = algorithmRunner.calculateEnacted(
            recommendation: ourRecommendation,
            previousEnacted: cycle.previousEnacted,
            scheduledBasalRate: scheduledBasalRate,
            at: cycle.cgmReadingTime
        )
        
        // 4. Compare against Loop's values
        let comparison = Comparator.compareCycle(
            ourIOB: ourIOB,
            ourPrediction: ourPrediction,
            ourRecommendation: ourRecommendation,
            ourEnacted: ourEnacted,
            cycle: cycle
        )
        
        return LoopReplayResult(
            cycle: cycle,
            iobInput: iobInput,
            predictionInput: predictionInput,
            ourIOB: ourIOB,
            ourPrediction: ourPrediction,
            ourRecommendation: ourRecommendation,
            ourEnacted: ourEnacted,
            comparison: comparison
        )
    }
    
    /// Replay and return aggregate statistics
    public func replayWithStatistics() -> (results: [LoopReplayResult], statistics: AggregateStatistics) {
        let results = replay()
        let comparisons = results.map { $0.comparison }
        let statistics = Comparator.aggregateStatistics(comparisons)
        return (results, statistics)
    }
    
    /// Quick validation: returns true if all cycles pass
    public func validate() -> Bool {
        let (_, stats) = replayWithStatistics()
        return stats.passRate == 1.0
    }
    
    // MARK: - Gap Analysis
    
    /// Get cycles that follow gaps (may have unreliable state)
    public var cyclesWithGaps: [LoopCycleState] {
        sequence.cyclesAfterGap
    }
    
    /// True if sequence has gaps
    public var hasGaps: Bool {
        sequence.hasGaps
    }
    
    /// Gap details
    public var gaps: [SequenceGap] {
        sequence.gaps
    }
}

// MARK: - Replay Result

/// Result of replaying a single cycle
public struct LoopReplayResult: Sendable, Identifiable {
    public var id: String { cycle.deviceStatusID }
    
    /// The cycle that was replayed
    public let cycle: LoopCycleState
    
    /// Inputs used for IOB calculation
    public let iobInput: IOBInput
    
    /// Inputs used for prediction
    public let predictionInput: PredictionInput
    
    /// Our calculated IOB
    public let ourIOB: Double
    
    /// Our calculated prediction
    public let ourPrediction: [Double]
    
    /// Our dose recommendation
    public let ourRecommendation: ReplayDoseRecommendation?
    
    /// Our enacted dose after ifNecessary filter (ALG-ZERO-DIV-012)
    public let ourEnacted: EnactedDose?
    
    /// Comparison against Loop
    public let comparison: CycleComparison
    
    /// True if this cycle passes validation
    public var passes: Bool {
        comparison.overallSignificance.passes
    }
    
    /// Quick summary for logging
    public var summary: String {
        let sig = comparison.overallSignificance
        let mae = comparison.prediction.mae
        let iobDelta = comparison.iob.delta
        return "\(sig.symbol) Cycle \(cycle.cycleIndex): MAE=\(String(format: "%.1f", mae)) mg/dL, IOB Δ=\(String(format: "%.3f", iobDelta))U"
    }
}

// MARK: - Algorithm Runner Protocol

/// Protocol for algorithm execution (allows injection for testing)
public protocol AlgorithmRunnerProtocol: Sendable {
    /// Calculate IOB from inputs
    func calculateIOB(_ input: IOBInput) -> Double
    
    /// Calculate prediction from inputs
    func calculatePrediction(_ input: PredictionInput) -> [Double]
    
    /// Calculate dose recommendation from inputs
    func calculateRecommendation(_ input: PredictionInput) -> ReplayDoseRecommendation?
    
    /// Calculate enacted dose after ifNecessary() filter (ALG-ZERO-DIV-012)
    func calculateEnacted(
        recommendation: ReplayDoseRecommendation?,
        previousEnacted: EnactedDose?,
        scheduledBasalRate: Double,
        at date: Date
    ) -> EnactedDose?
}

/// Default algorithm runner using T1PalAlgorithm
public struct DefaultAlgorithmRunner: AlgorithmRunnerProtocol, Sendable {
    
    public init() {}
    
    public func calculateIOB(_ input: IOBInput) -> Double {
        // ALG-IOB-SUSPEND: Use net basal IOB to account for suspended/reduced basal
        // When temp basal < scheduled basal, this contributes NEGATIVE IOB
        
        // ALG-PENDING-001: Trim ongoing temp basals when includingPendingInsulin: false
        // Loop uses basalDosingEnd = includingPendingInsulin ? nil : now()
        // When false: trim ongoing temps to calculationTime (exclude future delivery)
        // When true: use full temp duration (include scheduled future delivery)
        let basalDosingEnd: Date? = input.includingPendingInsulin ? nil : input.calculationTime
        
        // Convert ReplayInsulinDose to InsulinDose (algorithm type)
        // IMPORTANT: Include zero-rate temp basals (suspensions) - they contribute negative IOB
        let algorithmDoses = input.doses.compactMap { dose -> InsulinDose? in
            switch dose.type {
            case .bolus:
                guard let units = dose.units else { return nil }
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    type: .novolog,
                    source: "pump"
                )
            case .tempBasal:
                // ALG-PENDING-001: Trim temp basals to basalDosingEnd if set
                var effectiveEndDate = dose.endDate
                if let dosingEnd = basalDosingEnd, dose.endDate > dosingEnd {
                    // Trim ongoing temp to calculation time
                    effectiveEndDate = max(dose.startDate, dosingEnd)
                }
                
                // Skip if dose is completely in the future
                if let dosingEnd = basalDosingEnd, dose.startDate >= dosingEnd {
                    return nil
                }
                
                // Calculate delivered units based on (possibly trimmed) duration
                let effectiveDuration = effectiveEndDate.timeIntervalSince(dose.startDate)
                guard effectiveDuration > 0 else { return nil }
                
                let hours = effectiveDuration / 3600
                let units = (dose.rate ?? 0) * hours
                let durationMinutes = Int(effectiveDuration / 60)
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    endDate: effectiveEndDate,
                    type: .novolog,
                    source: "temp_basal_\(durationMinutes)min"  // Required for toRawInsulinDose
                )
            case .basal:
                return nil  // Scheduled basal handled via basalSchedule
            }
        }
        
        // IOB-BASAL-COVERAGE: Find earliest dose to ensure basal schedule covers all doses
        // Doses may start before calculationTime - DIA if they were uploaded earlier
        let earliestDoseStart = algorithmDoses.map { $0.timestamp }.min()
        let effectiveStartDate: Date
        if let earliest = earliestDoseStart, earliest < input.calculationTime.addingTimeInterval(-input.dia) {
            // Extend basal schedule to cover earliest dose
            effectiveStartDate = earliest
        } else {
            effectiveStartDate = input.calculationTime.addingTimeInterval(-input.dia)
        }
        
        // Convert basal schedule to absolute schedule values
        // IOB-TZ-001: Pass timezone for proper schedule interpretation
        let basalSchedule = buildAbsoluteBasalSchedule(
            from: input.basalSchedule,
            fromDate: effectiveStartDate,
            toDate: input.calculationTime,
            timezone: input.profileTimezone
        )
        
        // Map insulin model type
        let loopModelType = mapInsulinModelType(input.insulinModel)
        
        // Create net basal IOB calculator (accounts for scheduled vs delivered)
        let netBasalCalculator = LoopNetBasalIOBCalculator(
            insulinModel: loopModelType.toExponentialModel(actionDuration: input.dia)
        )
        
        // Calculate IOB using net basal (negative IOB for suspended basal)
        return netBasalCalculator.insulinOnBoardNetBasal(
            doses: algorithmDoses,
            basalSchedule: basalSchedule,
            at: input.calculationTime
        )
    }
    
    /// Convert relative basal schedule entries to absolute schedule values
    /// covering a specific date range
    /// IOB-TZ-001: Now accepts timezone for proper basal schedule interpretation
    private func buildAbsoluteBasalSchedule(
        from entries: [BasalScheduleEntry],
        fromDate startDate: Date,
        toDate endDate: Date,
        timezone: TimeZone? = nil
    ) -> [AbsoluteScheduleValue<Double>] {
        guard !entries.isEmpty else { return [] }
        
        var schedule: [AbsoluteScheduleValue<Double>] = []
        
        // IOB-TZ-001: Use profile timezone if provided, otherwise system default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone ?? TimeZone.current
        
        // Get midnight of the start date (in profile's timezone)
        var currentDate = calendar.startOfDay(for: startDate)
        
        while currentDate < endDate {
            for entry in entries {
                let entryStart = currentDate.addingTimeInterval(entry.startTime)
                
                // Skip entries before our window
                guard entryStart < endDate else { continue }
                
                // Find the end time (next entry or end of day)
                let nextEntryStart: Date
                if let nextEntry = entries.first(where: { $0.startTime > entry.startTime }) {
                    nextEntryStart = currentDate.addingTimeInterval(nextEntry.startTime)
                } else {
                    // Wrap to first entry of next day
                    nextEntryStart = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                        .addingTimeInterval(entries.first!.startTime)
                }
                
                // Clip to our window
                let clippedStart = max(entryStart, startDate)
                let clippedEnd = min(nextEntryStart, endDate)
                
                guard clippedStart < clippedEnd else { continue }
                
                schedule.append(AbsoluteScheduleValue(
                    startDate: clippedStart,
                    endDate: clippedEnd,
                    value: entry.rate
                ))
            }
            
            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return schedule.sorted { $0.startDate < $1.startDate }
    }
    
    public func calculatePrediction(_ input: PredictionInput) -> [Double] {
        // Get starting glucose
        guard let lastGlucose = input.glucose.last else { return [] }
        
        // ALG-PENDING-001: Apply basalDosingEnd trimming for predictions
        // Loop uses basalDosingEnd = includingPendingInsulin ? nil : now()
        // When includingPendingInsulin: true (default for NS predictions), use full temp duration
        // When includingPendingInsulin: false, trim ongoing temps to predictionStart
        let basalDosingEnd: Date? = input.includingPendingInsulin ? nil : input.predictionStart
        
        // Convert doses to algorithm type
        // ALG-ZERO-DIV-010: Include ALL doses including zero-rate suspensions
        // Zero-rate temps contribute via net-basal calculation (scheduled - 0 = negative)
        let algorithmDoses = input.doses.compactMap { dose -> InsulinDose? in
            switch dose.type {
            case .bolus:
                guard let units = dose.units else { return nil }
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    type: .novolog,
                    source: "pump"
                )
            case .tempBasal:
                // ALG-PENDING-001: Trim temp basals to basalDosingEnd if set
                var effectiveEndDate = dose.endDate
                if let dosingEnd = basalDosingEnd, dose.endDate > dosingEnd {
                    effectiveEndDate = max(dose.startDate, dosingEnd)
                }
                
                // Skip if dose is completely in the future
                if let dosingEnd = basalDosingEnd, dose.startDate >= dosingEnd {
                    return nil
                }
                
                // ALG-ZERO-DIV-010: Include zero-rate doses for net-basal calculation
                let effectiveDuration = effectiveEndDate.timeIntervalSince(dose.startDate)
                guard effectiveDuration > 0 else { return nil }
                
                let hours = effectiveDuration / 3600
                let units = (dose.rate ?? 0) * hours
                let durationMinutes = Int(effectiveDuration / 60)
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    endDate: effectiveEndDate,
                    type: .novolog,
                    source: "temp_basal_\(durationMinutes)min"  // Required for proper basal type detection
                )
            case .basal:
                return nil
            }
        }
        
        // Convert carbs to algorithm type
        let algorithmCarbs = input.carbs.map { carb in
            CarbEntry(
                grams: carb.grams,
                timestamp: carb.date,
                absorptionTime: 3 * 3600  // Default 3 hour absorption
            )
        }
        
        // Convert glucose history for momentum calculation
        // ALG-ZERO-DIV-010: Use actual glucose history for momentum effect
        let glucoseHistory: [T1PalCore.GlucoseReading] = input.glucose.map { glucose in
            T1PalCore.GlucoseReading(
                glucose: glucose.value,
                timestamp: glucose.date,
                source: "replay"
            )
        }
        
        // IOB-BASAL-COVERAGE: Find earliest dose to ensure basal schedule covers all doses
        let earliestDoseStart = algorithmDoses.map { $0.timestamp }.min()
        let effectiveStartDate: Date
        if let earliest = earliestDoseStart, earliest < input.predictionStart.addingTimeInterval(-input.dia) {
            effectiveStartDate = earliest
        } else {
            effectiveStartDate = input.predictionStart.addingTimeInterval(-input.dia)
        }
        
        // Build absolute basal schedule for net-basal calculation
        // ALG-ZERO-DIV-010: Required for proper insulin effects with suspended basals
        // IOB-TZ-001: Pass timezone for proper schedule interpretation
        let basalSchedule = buildAbsoluteBasalSchedule(
            from: input.basalSchedule,
            fromDate: effectiveStartDate,
            toDate: input.predictionStart,
            timezone: input.profileTimezone
        )
        
        // Map insulin model type
        let loopModelType = mapInsulinModelType(input.insulinModel)
        
        // Create prediction engine
        let engine = LoopGlucosePrediction(insulinModel: loopModelType)
        
        // ALG-ZERO-DIV-010 RC: Calculate retrospective correction effects
        // RC requires: insulin effects, counteraction effects, carb effects, discrepancies
        let rcEffects = calculateRetrospectiveCorrectionEffects(
            glucoseHistory: glucoseHistory,
            algorithmDoses: algorithmDoses,
            algorithmCarbs: algorithmCarbs,
            basalSchedule: basalSchedule,
            isf: input.isf,
            carbRatio: input.carbRatio,
            predictionStart: input.predictionStart
        )
        
        // Convert [LoopGlucoseEffect] to [GlucoseEffect] for prediction engine
        let rcGlucoseEffects = rcEffects.map { effect in
            GlucoseEffect(date: effect.startDate, quantity: effect.quantity)
        }
        
        // Run prediction with full inputs including RC
        // ALG-ZERO-DIV-010: Use complete predict() with momentum, basal schedule, and RC
        let predictions = engine.predict(
            currentGlucose: lastGlucose.value,
            glucoseHistory: glucoseHistory,  // For momentum
            doses: algorithmDoses,
            carbEntries: algorithmCarbs,
            insulinSensitivity: input.isf,
            carbRatio: input.carbRatio,
            startDate: input.predictionStart,
            basalSchedule: basalSchedule,  // For net-basal effects
            retrospectiveCorrectionEffects: rcGlucoseEffects.isEmpty ? nil : rcGlucoseEffects  // RC effects
        )
        
        // Convert to Double array
        return predictions.map { $0.glucose }
    }
    
    /// Calculate retrospective correction effects from glucose history and doses
    /// ALG-ZERO-DIV-010 RC: Implements Loop's RC algorithm for replay
    ///
    /// Steps:
    /// 1. Calculate insulin effects (cumulative)
    /// 2. Calculate counteraction effects (actual BG change - expected insulin effect)
    /// 3. Calculate carb effects as velocities
    /// 4. Calculate discrepancies (ICE - carb effects)
    /// 5. Apply StandardRetrospectiveCorrection to get decay effects
    private func calculateRetrospectiveCorrectionEffects(
        glucoseHistory: [T1PalCore.GlucoseReading],
        algorithmDoses: [InsulinDose],
        algorithmCarbs: [CarbEntry],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        isf: Double,
        carbRatio: Double,
        predictionStart: Date
    ) -> [LoopGlucoseEffect] {
        // Need at least 2 glucose readings for ICE calculation
        guard glucoseHistory.count >= 2 else { return [] }
        
        // Step 1: Calculate insulin effects (cumulative) over glucose history period
        // We need effects that cover the retrospection window (30 min before predictionStart)
        // For RC, we need cumulative effects at 5-min intervals covering the glucose history
        let retrospectionStart = predictionStart.addingTimeInterval(-RetrospectiveCorrectionConstants.standardRetrospectionInterval)
        
        // Use annotated doses path for net-basal effects (same as prediction)
        guard !basalSchedule.isEmpty else {
            // No basal schedule - can't calculate proper net insulin effects
            return []
        }
        
        let rawDoses = algorithmDoses.toReconciledRawInsulinDoses()
        let annotatedDoses = rawDoses.annotated(with: basalSchedule)
        
        // Calculate cumulative insulin effects (these are negative for insulin)
        let delta: TimeInterval = .minutes(5)
        let insulinEffectValues = annotatedDoses.glucoseEffects(
            insulinSensitivity: isf,
            from: retrospectionStart,
            to: predictionStart,
            delta: delta
        )
        
        // Convert to GlucoseEffect for counteractionEffects
        let insulinEffects = insulinEffectValues.map { GlucoseEffect(date: $0.startDate, quantity: $0.value) }
        
        guard !insulinEffects.isEmpty else { return [] }
        
        // Step 2: Calculate counteraction effects (ICE)
        // ICE = actual glucose change - expected insulin effect change
        let ice = glucoseHistory.counteractionEffects(to: insulinEffects)
        
        guard !ice.isEmpty else { return [] }
        
        // Step 3: Calculate carb effects as velocities
        // These need to match the ICE intervals for subtraction
        let carbEffects = calculateCarbEffectVelocities(
            carbs: algorithmCarbs,
            carbRatio: carbRatio,
            isf: isf,
            predictionStart: predictionStart
        )
        
        // Step 4: Calculate discrepancies (ICE - carb effects)
        let discrepancies = DiscrepancyCalculator.calculateDiscrepancies(
            insulinCounteractionEffects: ice,
            carbEffects: carbEffects
        )
        
        guard !discrepancies.isEmpty else { return [] }
        
        // Step 5: Apply retrospective correction
        guard let lastGlucose = glucoseHistory.last else { return [] }
        let startingGlucose = SimpleGlucoseValue(
            startDate: lastGlucose.timestamp,
            quantity: lastGlucose.glucose
        )
        
        var rc = StandardRetrospectiveCorrection()
        let effects = rc.computeEffect(
            startingAt: startingGlucose,
            retrospectiveGlucoseDiscrepanciesSummed: discrepancies,
            recencyInterval: RetrospectiveCorrectionConstants.recencyInterval,
            retrospectiveCorrectionGroupingInterval: RetrospectiveCorrectionConstants.groupingInterval
        )
        
        return effects
    }
    
    /// Calculate carb effect velocities for discrepancy calculation
    /// Returns velocities that can be subtracted from ICE
    private func calculateCarbEffectVelocities(
        carbs: [CarbEntry],
        carbRatio: Double,
        isf: Double,
        predictionStart: Date
    ) -> [GlucoseEffectVelocity] {
        guard !carbs.isEmpty else { return [] }
        
        // Calculate carb effects using LoopCOBParity
        // Convert carbs to effects at 5-min intervals
        var velocities: [GlucoseEffectVelocity] = []
        let delta: TimeInterval = .minutes(5)
        let retrospectionWindow: TimeInterval = .minutes(30)
        let defaultAbsorptionTime: TimeInterval = 3 * 3600  // 3 hours default
        
        for carb in carbs {
            // Only consider carbs within retrospection window
            let carbAge = predictionStart.timeIntervalSince(carb.timestamp)
            guard carbAge >= 0 else { continue }
            
            // Simple linear absorption model for replay (matches Loop's COB approach)
            let absorptionTime = carb.absorptionTime ?? defaultAbsorptionTime
            guard absorptionTime > 0 else { continue }
            
            let gramsPerSecond = carb.grams / absorptionTime
            
            // Effect per gram = ISF / carbRatio (mg/dL per gram)
            let effectPerGram = isf / carbRatio
            let effectPerSecond = gramsPerSecond * effectPerGram
            
            // Create velocity samples at 5-min intervals during absorption
            var t: TimeInterval = 0
            while t < absorptionTime {
                let sampleStart = carb.timestamp.addingTimeInterval(t)
                let sampleEnd = sampleStart.addingTimeInterval(delta)
                
                // Only include samples within retrospection window
                if sampleEnd <= predictionStart && sampleStart >= predictionStart.addingTimeInterval(-retrospectionWindow) {
                    velocities.append(GlucoseEffectVelocity(
                        startDate: sampleStart,
                        endDate: sampleEnd,
                        quantity: effectPerSecond  // Per-second velocity
                    ))
                }
                t += delta
            }
        }
        
        return velocities
    }
    
    public func calculateRecommendation(_ input: PredictionInput) -> ReplayDoseRecommendation? {
        // ALG-ZERO-DIV-011: Calculate dose recommendation for comparison with Loop's automaticDoseRecommendation
        
        // Get starting glucose
        guard let lastGlucose = input.glucose.last else { return nil }
        
        // Convert doses to algorithm type (same as calculatePrediction)
        let algorithmDoses = input.doses.compactMap { dose -> InsulinDose? in
            switch dose.type {
            case .bolus:
                guard let units = dose.units else { return nil }
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    type: .novolog,
                    source: "pump"
                )
            case .tempBasal:
                let hours = dose.duration / 3600
                let units = (dose.rate ?? 0) * hours
                let durationMinutes = Int(dose.duration / 60)
                return InsulinDose(
                    units: units,
                    timestamp: dose.startDate,
                    endDate: dose.endDate,
                    type: .novolog,
                    source: "temp_basal_\(durationMinutes)min"
                )
            case .basal:
                return nil
            }
        }
        
        // Convert carbs to algorithm type
        let algorithmCarbs = input.carbs.map { carb in
            CarbEntry(
                grams: carb.grams,
                timestamp: carb.date,
                absorptionTime: 3 * 3600
            )
        }
        
        // Convert glucose history for momentum
        let glucoseHistory: [T1PalCore.GlucoseReading] = input.glucose.map { glucose in
            T1PalCore.GlucoseReading(
                glucose: glucose.value,
                timestamp: glucose.date,
                source: "replay"
            )
        }
        
        // IOB-BASAL-COVERAGE: Find earliest dose to ensure basal schedule covers all doses
        let earliestDoseStart = algorithmDoses.map { $0.timestamp }.min()
        let effectiveStartDate: Date
        if let earliest = earliestDoseStart, earliest < input.predictionStart.addingTimeInterval(-input.dia) {
            effectiveStartDate = earliest
        } else {
            effectiveStartDate = input.predictionStart.addingTimeInterval(-input.dia)
        }
        
        // Build absolute basal schedule
        // IOB-TZ-001: Pass timezone for proper schedule interpretation
        let basalSchedule = buildAbsoluteBasalSchedule(
            from: input.basalSchedule,
            fromDate: effectiveStartDate,
            toDate: input.predictionStart,
            timezone: input.profileTimezone
        )
        
        // Get scheduled basal rate at prediction time
        let scheduledBasalRate = basalSchedule.first { $0.startDate <= input.predictionStart && $0.endDate > input.predictionStart }?.value ?? input.basalSchedule.first?.rate ?? 1.0
        
        // Map insulin model type
        let loopModelType = mapInsulinModelType(input.insulinModel)
        
        // Create dose calculator with replay settings
        let config = LoopDoseCalculator.Configuration(
            maxBasalRate: input.maxBasalRate,
            maxBolus: 10.0,  // Default max bolus
            suspendThreshold: input.suspendThreshold,
            tempBasalDuration: 30 * 60,  // 30 minutes
            minimumBGGuard: input.suspendThreshold,
            allowZeroTemp: true
        )
        let calculator = LoopDoseCalculator(
            configuration: config,
            insulinModel: loopModelType
        )
        
        // Calculate recommendation
        let result = calculator.recommendTempBasal(
            currentGlucose: lastGlucose.value,
            glucoseHistory: glucoseHistory,
            doses: algorithmDoses,
            carbEntries: algorithmCarbs,
            scheduledBasalRate: scheduledBasalRate,
            insulinSensitivity: input.isf,
            carbRatio: input.carbRatio,
            targetGlucose: (input.targetRange.lowerBound + input.targetRange.upperBound) / 2,
            basalSchedule: basalSchedule
        )
        
        // Convert to ReplayDoseRecommendation
        switch result.recommendation.type {
        case .tempBasal:
            return ReplayDoseRecommendation(
                tempBasalRate: result.recommendation.rate,
                tempBasalDuration: (result.recommendation.duration ?? 1800) / 60,  // Convert to minutes
                bolusVolume: 0
            )
        case .suspend:
            return ReplayDoseRecommendation(
                tempBasalRate: 0,
                tempBasalDuration: 30,
                bolusVolume: 0
            )
        case .bolus:
            return ReplayDoseRecommendation(
                tempBasalRate: nil,
                tempBasalDuration: nil,
                bolusVolume: result.recommendation.units ?? 0
            )
        case .resume:
            return nil  // No adjustment needed
        }
    }
    
    // MARK: - ALG-ZERO-DIV-012: Enacted Calculation
    
    public func calculateEnacted(
        recommendation: ReplayDoseRecommendation?,
        previousEnacted: EnactedDose?,
        scheduledBasalRate: Double,
        at date: Date
    ) -> EnactedDose? {
        // If no recommendation, no enacted dose
        guard let rec = recommendation,
              let tempRate = rec.tempBasalRate else {
            return nil
        }
        
        // Build a LoopTempBasal to use ifNecessary()
        let durationSeconds = TimeInterval((rec.tempBasalDuration ?? 30) * 60)
        let tempBasalRec = LoopTempBasal(
            rate: tempRate,
            duration: durationSeconds
        )
        
        // Build current delivery state from previous enacted
        let currentState: CurrentDeliveryState
        if let prev = previousEnacted {
            // Previous temp basal may still be running
            let runningTemp = LoopTempBasal(
                rate: prev.rate,
                duration: prev.duration * 60  // Convert to seconds
            )
            let tempEndTime = prev.timestamp.addingTimeInterval(prev.duration * 60)
            currentState = CurrentDeliveryState(
                currentTempBasal: runningTemp,
                tempBasalEndTime: tempEndTime,
                scheduledBasalRate: scheduledBasalRate
            )
        } else {
            // No previous temp, just scheduled basal
            currentState = CurrentDeliveryState(
                currentTempBasal: nil,
                tempBasalEndTime: nil,
                scheduledBasalRate: scheduledBasalRate
            )
        }
        
        // Apply ifNecessary() filter
        let action = tempBasalRec.ifNecessary(currentState: currentState, at: date)
        
        switch action {
        case .noAction:
            // No command sent - return nil
            return nil
            
        case .cancelTempBasal:
            // Cancel means return to scheduled - effectively no temp
            return nil
            
        case .setTempBasal(let newRec):
            // New temp basal enacted
            return EnactedDose(
                rate: newRec.rate,
                duration: newRec.duration / 60,  // Convert to minutes
                timestamp: date,
                received: true
            )
        }
    }
    
    // MARK: - Helpers
    
    private func mapInsulinModelType(_ type: InsulinModelType) -> LoopInsulinModelType {
        switch type {
        case .rapidActingAdult: return .rapidActingAdult
        case .rapidActingChild: return .rapidActingChild
        case .fiasp: return .fiasp
        case .lyumjev: return .lyumjev
        case .afrezza: return .afrezza
        }
    }
}

// MARK: - LoopInsulinModelType to LoopExponentialInsulinModel

extension LoopInsulinModelType {
    /// Convert to exponential model for net basal IOB calculation
    func toExponentialModel(actionDuration: TimeInterval) -> LoopExponentialInsulinModel {
        let preset: LoopInsulinModelPreset
        switch self {
        case .walsh: preset = .rapidActingAdult  // Walsh uses adult curve
        case .rapidActingAdult: preset = .rapidActingAdult
        case .rapidActingChild: preset = .rapidActingChild
        case .fiasp: preset = .fiasp
        case .lyumjev: preset = .lyumjev
        case .afrezza: preset = .afrezza
        }
        // Use preset's peak time but allow custom action duration
        let baseModel = preset.model
        return LoopExponentialInsulinModel(
            actionDuration: actionDuration,
            peakActivityTime: baseModel.peakActivityTime,
            delay: baseModel.delay
        )
    }
}

// MARK: - Convenience Extensions

extension LoopReplayEngine {
    
    /// Print replay summary to console
    public func printSummary() {
        let (results, stats) = replayWithStatistics()
        
        print("=== Loop Replay Summary ===")
        print("Cycles: \(sequence.count)")
        if hasGaps {
            print("⚠️ Gaps detected: \(gaps.count) (total \(String(format: "%.1f", sequence.totalGapMinutes)) min)")
        }
        print("")
        print(stats.summary)
        print("")
        
        // Show worst cycles
        let worst = results
            .filter { !$0.passes }
            .sorted { $0.comparison.prediction.mae > $1.comparison.prediction.mae }
            .prefix(5)
        
        if !worst.isEmpty {
            print("Worst divergent cycles:")
            for result in worst {
                print("  \(result.summary)")
            }
        }
    }
}
