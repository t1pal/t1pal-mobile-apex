// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmDiagnostics.swift
// T1Pal Mobile
//
// Immutable diagnostic output from algorithm calculations.
// Replaces mutable class state with value-type return data.
//
// Trace: ALG-DIAG-030

import Foundation
import T1PalCore

// MARK: - Top-Level Diagnostics

/// Diagnostic data produced by an algorithm calculation cycle.
///
/// Each algorithm populates only the fields relevant to its implementation.
/// All fields are optional so algorithms only emit what they compute.
/// This replaces mutable `_last*` state that was previously stored on algorithm classes.
public struct AlgorithmDiagnostics: Sendable {
    
    /// Loop-specific diagnostics (predictions, RC, ICE, IOB breakdown)
    public let loop: LoopDiagnostics?
    
    /// oref1-specific diagnostics (autosens, SMB history)
    public let oref1: Oref1Diagnostics?
    
    /// GlucOS-specific diagnostics (predicted points)
    public let glucos: GlucOSDiagnostics?
    
    public init(
        loop: LoopDiagnostics? = nil,
        oref1: Oref1Diagnostics? = nil,
        glucos: GlucOSDiagnostics? = nil
    ) {
        self.loop = loop
        self.oref1 = oref1
        self.glucos = glucos
    }
}

// MARK: - Loop Diagnostics

/// Diagnostic output from a Loop algorithm calculation cycle.
///
/// Previously stored as mutable `_last*` vars with NSLock guards on LoopAlgorithm.
/// Now returned immutably in AlgorithmDecision.diagnostics.
public struct LoopDiagnostics: Sendable {
    
    // MARK: Retrospective Correction (ALG-RC-008)
    
    /// RC diagnostics from the last calculation
    public let rcDiagnostics: RCDiagnostics?
    
    // MARK: Insulin Counteraction Effects (ALG-DIAG-ICE-001)
    
    /// Insulin counteraction effects computed during this cycle
    public let insulinCounteractionEffects: [GlucoseEffectVelocity]
    
    /// Insulin effects timeline used in ICE calculation (ALG-RC-004)
    public let insulinEffects: [GlucoseEffectValue]
    
    // MARK: IOB Breakdown (ALG-RC-007)
    
    /// Computed IOB value
    public let computedIOB: Double
    
    /// Input IOB from the algorithm inputs (for comparison)
    public let inputIOB: Double
    
    /// Number of dose entries used in IOB calculation
    public let doseCount: Int
    
    /// Whether the basal schedule annotation path was used for IOB
    public let iobUsedBasalSchedule: Bool
    
    /// Timestamp used for the IOB calculation
    public let iobCalculationTime: Date?
    
    // MARK: Correction History
    
    /// Recent retrospective correction results from the legacy RC path
    public let recentCorrections: [RetrospectiveCorrectionResult]
    
    public init(
        rcDiagnostics: RCDiagnostics? = nil,
        insulinCounteractionEffects: [GlucoseEffectVelocity] = [],
        insulinEffects: [GlucoseEffectValue] = [],
        computedIOB: Double = 0,
        inputIOB: Double = 0,
        doseCount: Int = 0,
        iobUsedBasalSchedule: Bool = false,
        iobCalculationTime: Date? = nil,
        recentCorrections: [RetrospectiveCorrectionResult] = []
    ) {
        self.rcDiagnostics = rcDiagnostics
        self.insulinCounteractionEffects = insulinCounteractionEffects
        self.insulinEffects = insulinEffects
        self.computedIOB = computedIOB
        self.inputIOB = inputIOB
        self.doseCount = doseCount
        self.iobUsedBasalSchedule = iobUsedBasalSchedule
        self.iobCalculationTime = iobCalculationTime
        self.recentCorrections = recentCorrections
    }
}

// MARK: - Oref1 Diagnostics

/// Diagnostic output from an oref1 algorithm calculation cycle.
///
/// `_lastAutosensResult` is moved here. SMB history remains stateful
/// on the class because it's a safety-critical accumulator across cycles.
public struct Oref1Diagnostics: Sendable {
    
    /// Autosens result computed (or carried forward) during this cycle
    public let autosensResult: AutosensResult
    
    /// Recent SMB deliveries snapshot at time of calculation
    public let recentSMBs: [SMBDelivery]
    
    /// Total SMB units delivered in the last hour
    public let smbUnitsLastHour: Double
    
    /// Whether UAM was detected during this cycle
    public let uamDetected: Bool
    
    public init(
        autosensResult: AutosensResult = .neutral,
        recentSMBs: [SMBDelivery] = [],
        smbUnitsLastHour: Double = 0,
        uamDetected: Bool = false
    ) {
        self.autosensResult = autosensResult
        self.recentSMBs = recentSMBs
        self.smbUnitsLastHour = smbUnitsLastHour
        self.uamDetected = uamDetected
    }
}

// MARK: - GlucOS Diagnostics

/// Diagnostic output from a GlucOS algorithm calculation cycle.
public struct GlucOSDiagnostics: Sendable {
    
    /// Predicted glucose points from this cycle
    public let predictedPoints: [PredictedGlucose]
    
    public init(predictedPoints: [PredictedGlucose] = []) {
        self.predictedPoints = predictedPoints
    }
}
