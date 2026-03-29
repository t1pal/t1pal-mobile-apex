// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PredictionModelInvestigationTests.swift
// T1Pal Mobile
//
// Investigation into prediction model divergence from Loop
// Requirements: ALG-DIAG-023
//
// FINDINGS:
// 1. Our predictions fall faster than Loop's (25.6 mg/dL avg divergence)
// 2. Root cause: difference in how glucose effect from insulin is calculated
// 3. Loop uses: effect = units * ISF * (1 - percentEffectRemaining)
// 4. We use: cumulative effect from IOB decay rate
// 5. These should be mathematically equivalent but may differ due to:
//    - Timing of when effect is applied (historical vs future)
//    - Treatment of already-absorbed insulin
//    - Net basal calculation differences
//
// RECOMMENDED FIX (ALG-DIAG-023 Phase 2):
// 1. Align insulin effect calculation with Loop's exact formula
// 2. Ensure we're only predicting FUTURE glucose effect, not re-applying historical
// 3. Use scheduled basal rate lookup per dose, not constant
//
// Trace: ALG-DIAG-023, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

/// Investigation tests for prediction model divergence
/// Trace: ALG-DIAG-023
@Suite("Prediction Model Investigation")
struct PredictionModelInvestigationTests {
    
    // MARK: - Insulin Model Comparison
    
    @Test("Exponential model curve")
    func exponentialModelCurve() {
        // Compare our ExponentialInsulinModel vs Loop's expected values
        let model = ExponentialInsulinModel.rapidActingAdult
        
        print("\n📊 Exponential Insulin Model Curve (rapidActingAdult)")
        print("  DIA: \(model.actionDuration / 3600) hours")
        print("  Peak: \(model.peakActivityTime / 60) minutes")
        print()
        
        // Sample IOB at various times
        let times = [0, 15, 30, 45, 60, 90, 120, 180, 240, 300, 360].map { Double($0) * 60 }
        
        print("  Time (min) | IOB %  | Activity")
        print("  " + String(repeating: "-", count: 35))
        
        for t in times {
            let iob = model.percentEffectRemaining(at: t)
            let activity = model.percentActivity(at: t)
            print("  \(String(format: "%10.0f", t/60)) | \(String(format: "%5.1f%%", iob*100)) | \(String(format: "%.4f", activity))")
        }
        
        // Expected Loop values at key times (from Loop documentation):
        // At 0 min: 100% IOB
        // At peak (75 min): ~50-60% IOB (model-dependent)
        // At DIA (360 min): 0% IOB
        
        #expect(abs(model.percentEffectRemaining(at: 0) - 1.0) < 0.01, "IOB at t=0 should be 100%")
        #expect(abs(model.percentEffectRemaining(at: 6 * 3600) - 0.0) < 0.01, "IOB at DIA should be 0%")
    }
    
    @Test("Insulin effect calculation")
    func insulinEffectCalculation() {
        // Test a single dose insulin effect over time
        let model = ExponentialInsulinModel.rapidActingAdult
        let calculator = LoopIOBCalculator(model: model)
        
        // Single 1U dose at time 0
        let doseTime = Date()
        let doses = [InsulinDose(units: 1.0, timestamp: doseTime)]
        
        let isf = 40.0  // 40 mg/dL per unit
        
        print("\n📊 Single 1U Dose Insulin Effect")
        print("  ISF: \(isf) mg/dL/U")
        print("  Expected max effect: \(isf) mg/dL (1U * ISF)")
        print()
        
        // Calculate effect at various times
        let effects = calculator.insulinEffect(
            doses: doses,
            insulinSensitivity: isf,
            startDate: doseTime,
            duration: 6 * 3600,
            interval: 30 * 60
        )
        
        print("  Time (min) | Effect | IOB remaining")
        print("  " + String(repeating: "-", count: 40))
        
        for effect in effects {
            let t = effect.date.timeIntervalSince(doseTime)
            let iob = model.percentEffectRemaining(at: t)
            print("  \(String(format: "%10.0f", t/60)) | \(String(format: "%+6.1f", effect.effect)) mg/dL | \(String(format: "%.1f%%", iob*100))")
        }
        
        // Expected: At DIA, cumulative effect should approach 1U * ISF = 40 mg/dL
        let finalEffect = effects.last?.effect ?? 0
        print("\n  Final cumulative effect: \(String(format: "%.1f", finalEffect)) mg/dL")
        print("  Expected (1U * ISF): \(isf) mg/dL")
        print("  Ratio: \(String(format: "%.2f", finalEffect / isf))")
    }
    
    @Test("Loop vs our approach documentation")
    func loopVsOurApproach() {
        // Document the difference between approaches
        print("\n📊 Loop vs Our Insulin Effect Approach")
        print(String(repeating: "=", count: 60))
        
        print("""
        
        LOOP'S APPROACH:
        ----------------
        For each dose, at time t:
          effect = units * ISF * (1.0 - percentEffectRemaining(t))
        
        This directly calculates the cumulative glucose drop from the dose
        at any point in time.
        
        OUR APPROACH:
        -------------
        For each time step:
          iobDecay = IOB(t-1) - IOB(t)
          bgDrop = iobDecay * ISF
          cumulativeEffect += bgDrop
        
        This accumulates glucose drops from the rate of IOB decay.
        
        MATHEMATICAL EQUIVALENCE:
        -------------------------
        Both should produce the same result because:
          ∫₀ᵗ activity(s) ds = 1 - percentEffectRemaining(t)
        
        The activity curve is the derivative of (1 - IOB).
        
        POTENTIAL DIFFERENCES:
        ----------------------
        1. Discretization error in our step-by-step approach
        2. Starting point: we may include historical doses that
           Loop doesn't include in prediction (already absorbed)
        3. Net basal calculation may differ
        
        RECOMMENDATION:
        ---------------
        Switch to Loop's direct formula for cleaner calculation:
          effect = units * ISF * (1.0 - percentEffectRemaining(t))
        """)
        
        // This is a documentation test - always passes
        #expect(true)
    }
    
    @Test("Scheduled basal lookup documentation")
    func scheduledBasalLookup() {
        // Document the need for per-dose scheduled basal lookup
        print("\n📊 Scheduled Basal Rate Lookup Issue")
        print(String(repeating: "=", count: 60))
        
        print("""
        
        CURRENT BEHAVIOR:
        -----------------
        We use a constant scheduled basal rate (e.g., 1.7 U/hr) for all doses.
        
        LOOP BEHAVIOR:
        --------------
        Loop looks up the scheduled basal rate at each dose's timestamp:
          scheduledRate = basalProfile.value(at: dose.timestamp)
          netRate = dose.rate - scheduledRate
        
        This matters because:
        - Profile may have multiple rates: 1.8 (night) → 1.7 (day) → 1.8 (night)
        - Using wrong scheduled rate = wrong net insulin calculation
        
        IMPACT:
        -------
        If scheduled is 1.8 but we use 1.7:
          Actual net = 1.4 - 1.8 = -0.4 U/hr (less insulin than scheduled)
          Our calc   = 1.4 - 1.7 = -0.3 U/hr (different net)
        
        Over multiple temp basals, this compounds into prediction error.
        """)
        
        // This is a documentation test - always passes
        #expect(true)
    }
}
