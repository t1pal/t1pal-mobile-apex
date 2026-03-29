// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Oref1Algorithm.swift
// T1Pal Mobile
//
// oref1 algorithm with SMB and Dynamic ISF
// Requirements: REQ-AID-002, REQ-ALGO-001
//
// Based on oref1:
// https://github.com/openaps/oref0
//
// Trace: ALG-013, PRD-009

import Foundation
import T1PalCore

// MARK: - Oref1 Algorithm

/// oref1-compatible algorithm engine with SMB and Dynamic ISF
/// Extends oref0 with:
/// - Super Micro Bolus (SMB) for faster corrections
/// - Dynamic ISF for BG-responsive sensitivity
/// - UAM (Unannounced Meals) detection
/// Thread-safe: Uses lock-protected mutable state for autosens
public final class Oref1Algorithm: AlgorithmEngine, @unchecked Sendable {
    public let name = "oref1"
    public let version = "0.1.0"
    
    public let capabilities = AlgorithmCapabilities(
        supportsTempBasal: true,
        supportsSMB: true,
        supportsUAM: true,
        supportsDynamicISF: true,
        supportsAutosens: true,
        providesPredictions: true,
        minGlucoseHistory: 3,
        recommendedGlucoseHistory: 48,  // 4 hours for UAM
        origin: .oref1
    )
    
    // Components (immutable after init)
    private let determineBasal = DetermineBasal()
    private let insulinModel: InsulinModel
    private let iobCalculator: IOBCalculator
    private let cobCalculator: COBCalculator
    private let smbCalculator: SMBCalculator
    private let autosensCalculator: AutosensCalculator
    private let dynamicISF: DynamicISF
    private let sensitivityAdjuster: SensitivityAdjuster
    
    // Settings
    public let smbSettings: SMBSettings
    public let enableDynamicISF: Bool
    public let enableUAM: Bool
    
    // Thread-safe mutable state
    private let smbHistory = SMBHistory()
    private let stateLock = NSLock()
    private var _lastAutosensResult: AutosensResult = .neutral
    
    /// Thread-safe access to last autosens result
    private var lastAutosensResult: AutosensResult {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _lastAutosensResult
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _lastAutosensResult = newValue
        }
    }
    
    public init(
        insulinType: InsulinType = .humalog,
        smbSettings: SMBSettings = .default,
        enableDynamicISF: Bool = true,
        enableUAM: Bool = true
    ) {
        self.insulinModel = InsulinModel(insulinType: insulinType)
        self.iobCalculator = IOBCalculator(model: insulinModel)
        self.cobCalculator = COBCalculator()
        self.smbCalculator = SMBCalculator(settings: smbSettings)
        self.autosensCalculator = AutosensCalculator()
        self.dynamicISF = DynamicISF()
        self.sensitivityAdjuster = SensitivityAdjuster(
            autosens: autosensCalculator,
            dynamicISF: dynamicISF
        )
        self.smbSettings = smbSettings
        self.enableDynamicISF = enableDynamicISF
        self.enableUAM = enableUAM
    }
    
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        guard let latestBG = inputs.glucose.first else {
            return AlgorithmDecision(reason: "No glucose data")
        }
        
        // Convert to algorithm profile
        let profile = createAlgorithmProfile(from: inputs.profile)
        
        // Calculate autosens if we have enough data
        let autosensResult: AutosensResult
        if inputs.glucose.count >= 24 {
            autosensResult = autosensCalculator.calculate(
                glucose: inputs.glucose,
                profile: profile,
                insulinModel: insulinModel
            )
            lastAutosensResult = autosensResult
        } else {
            autosensResult = lastAutosensResult
        }
        
        // Get adjusted profile values
        let adjustedValues = sensitivityAdjuster.adjustedProfile(
            profile: profile,
            currentBG: latestBG.glucose,
            autosensResult: autosensResult
        )
        
        // ALG-LIVE-055..057: Use real dose/carb history when available
        let now = inputs.currentTime
        let iob: Double
        let cob: Double
        
        // ALG-LIVE-055/057: Use doseHistory if provided, recalculate IOB
        if let doseHistory = inputs.doseHistory, !doseHistory.isEmpty {
            iob = iobCalculator.totalIOB(from: doseHistory, at: now)
        } else {
            iob = inputs.insulinOnBoard  // Fallback to scalar
        }
        
        // ALG-LIVE-056: Use carbHistory if provided, recalculate COB
        if let carbHistory = inputs.carbHistory, !carbHistory.isEmpty {
            cob = cobCalculator.totalCOB(from: carbHistory, at: now)
        } else {
            cob = inputs.carbsOnBoard  // Fallback to scalar
        }
        
        // Detect UAM if enabled
        let uamDetected = enableUAM ? detectUAM(glucose: inputs.glucose, cob: cob) : false
        
        // Run determine-basal with adjusted values
        let output = determineBasal.calculate(
            glucose: inputs.glucose,
            iob: iob,
            cob: cob,
            profile: profile
        )
        
        // Calculate SMB if enabled and appropriate
        let smbResult = calculateSMB(
            currentBG: latestBG.glucose,
            eventualBG: output.eventualBG,
            minPredBG: output.minPredBG,
            targetBG: profile.currentTarget(),
            iob: iob,
            cob: cob,
            sens: adjustedValues.isf,
            maxBasal: profile.maxBasal,
            uamDetected: uamDetected
        )
        
        // Build decision
        var suggestedBolus: Double? = nil
        var reason = output.reason
        
        if smbResult.shouldDeliver {
            suggestedBolus = smbResult.units
            reason += " | SMB: \(String(format: "%.2f", smbResult.units))U"
            
            // Record SMB in history
            smbHistory.record(SMBDelivery(
                units: smbResult.units,
                reason: smbResult.reason,
                bgAtDelivery: latestBG.glucose
            ))
        }
        
        // Add autosens info
        if autosensResult.ratio != 1.0 {
            reason += " | autosens: \(String(format: "%.0f", autosensResult.ratio * 100))%"
        }
        
        // Add UAM info
        if uamDetected {
            reason += " | UAM detected"
        }
        
        return AlgorithmDecision(
            timestamp: inputs.currentTime,
            suggestedTempBasal: output.rate.map { 
                TempBasal(rate: $0, duration: Double(output.duration ?? 30) * 60) 
            },
            suggestedBolus: suggestedBolus,
            reason: reason,
            predictions: buildPredictions(output: output, profile: profile)
        )
    }
    
    // MARK: - SMB Calculation
    
    private func calculateSMB(
        currentBG: Double,
        eventualBG: Double,
        minPredBG: Double,
        targetBG: Double,
        iob: Double,
        cob: Double,
        sens: Double,
        maxBasal: Double,
        uamDetected: Bool
    ) -> SMBResult {
        // Extra SMB enablement for UAM
        let effectiveCOB = uamDetected ? max(cob, 10) : cob  // Treat UAM as if there's COB
        
        return smbCalculator.calculate(
            currentBG: currentBG,
            eventualBG: eventualBG,
            minPredBG: minPredBG,
            targetBG: targetBG,
            iob: iob,
            cob: effectiveCOB,
            sens: sens,
            maxBasal: maxBasal,
            lastSMBTime: smbHistory.lastDeliveryTime
        )
    }
    
    // MARK: - UAM Detection
    
    private func detectUAM(glucose: [GlucoseReading], cob: Double) -> Bool {
        guard enableUAM else { return false }
        guard glucose.count >= 6 else { return false }  // Need 30 min of data
        guard cob < 1 else { return false }  // Only when no announced carbs
        
        // Calculate average delta over last 30 min
        let recentReadings = Array(glucose.prefix(6))
        guard let first = recentReadings.first, let last = recentReadings.last else {
            return false
        }
        
        let delta = first.glucose - last.glucose
        let avgDelta = delta / Double(recentReadings.count - 1)
        
        // UAM detected if BG rising significantly without carbs
        return avgDelta > 3.0  // Rising more than 3 mg/dL per 5 min
    }
    
    // MARK: - Profile Conversion
    
    private func createAlgorithmProfile(from therapy: TherapyProfile) -> AlgorithmProfile {
        let basalEntries = therapy.basalRates.map { rate in
            BasalScheduleEntry(startTime: rate.startTime, rate: rate.rate)
        }
        
        let isfEntries = therapy.sensitivityFactors.map { sf in
            ISFScheduleEntry(startTime: sf.startTime, sensitivity: sf.factor)
        }
        
        let icrEntries = therapy.carbRatios.map { cr in
            ICRScheduleEntry(startTime: cr.startTime, ratio: cr.ratio)
        }
        
        let targetEntries = [
            TargetScheduleEntry(
                startTime: 0,
                low: therapy.targetGlucose.low,
                high: therapy.targetGlucose.high
            )
        ]
        
        return AlgorithmProfile(
            name: "Oref1 Adjusted",
            dia: insulinModel.dia,
            basalSchedule: Schedule(entries: basalEntries.isEmpty ? [BasalScheduleEntry(startTime: 0, rate: 1.0)] : basalEntries),
            isfSchedule: Schedule(entries: isfEntries.isEmpty ? [ISFScheduleEntry(startTime: 0, sensitivity: 50)] : isfEntries),
            icrSchedule: Schedule(entries: icrEntries.isEmpty ? [ICRScheduleEntry(startTime: 0, ratio: 10)] : icrEntries),
            targetSchedule: Schedule(entries: targetEntries),
            maxBasal: 4.0,
            maxBolus: therapy.maxBolus > 0 ? therapy.maxBolus : 10.0,
            autosensMax: 1.5,
            autosensMin: 0.5
        )
    }
    
    // MARK: - Predictions
    
    private func buildPredictions(output: DetermineBasalOutput, profile: AlgorithmProfile) -> GlucosePredictions? {
        // Simplified predictions - in real implementation would use PredictionEngine
        return GlucosePredictions(
            iob: [output.eventualBG],
            cob: [output.eventualBG],
            uam: [output.eventualBG],
            zt: [output.minPredBG]
        )
    }
    
    // MARK: - Public Accessors
    
    /// Get recent SMB deliveries
    public var recentSMBs: [SMBDelivery] {
        smbHistory.recentDeliveries
    }
    
    /// Get current autosens result
    public var currentAutosens: AutosensResult {
        lastAutosensResult
    }
    
    /// Total SMB units in last hour
    public var smbUnitsLastHour: Double {
        smbHistory.totalUnitsSince(Date().addingTimeInterval(-3600))
    }
}

// MARK: - Registry Extension

extension AlgorithmRegistry {
    /// Register oref1 algorithm
    public func registerOref1(
        insulinType: InsulinType = .humalog,
        smbSettings: SMBSettings = .default,
        enableDynamicISF: Bool = true,
        enableUAM: Bool = true
    ) {
        let oref1 = Oref1Algorithm(
            insulinType: insulinType,
            smbSettings: smbSettings,
            enableDynamicISF: enableDynamicISF,
            enableUAM: enableUAM
        )
        registerOrReplace(oref1)
    }
}
