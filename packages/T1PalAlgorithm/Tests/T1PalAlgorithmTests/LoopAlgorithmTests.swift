// SPDX-License-Identifier: AGPL-3.0-or-later
// LoopAlgorithmTests.swift - Loop algorithm integration tests
// Extracted from AlgorithmTests.swift (CODE-027)
// Trace: ALG-LOOP-001

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - Loop Insulin Math Tests

@Suite("LoopInsulinMathTests")
struct LoopInsulinMathTests {
    
    // MARK: - Model Type Tests
    
    @Test func modeltypedefaults() {
        #expect(LoopInsulinModelType.walsh.defaultActionDuration == 6.0)
        #expect(LoopInsulinModelType.rapidActingAdult.peakActivityTime == 1.25)
        // T6-001 fix: Fiasp uses 6.0h DIA to match Loop (was 5.5)
        #expect(LoopInsulinModelType.fiasp.defaultActionDuration == 6.0)
        // T6-001 fix: Afrezza peak is 29 min to match Loop (was 0.35 = 21 min)
        #expect(abs(LoopInsulinModelType.afrezza.peakActivityTime - 29.0/60.0) < 0.01)
    }
    
    @Test func modeltypedisplaynames() {
        #expect(LoopInsulinModelType.walsh.displayName == "Walsh")
        #expect(LoopInsulinModelType.rapidActingChild.displayName == "Rapid-Acting Child")
        #expect(LoopInsulinModelType.fiasp.displayName == "Fiasp")
    }
    
    // MARK: - Walsh Model Tests
    
    @Test func walshmodelinitialization() {
        let model = WalshInsulinModel()
        #expect(model.actionDuration == 6 * 3600)
        #expect(model.peakActivityTime == 1.5 * 3600)
    }
    
    @Test func walshmodeliob() {
        let model = WalshInsulinModel()
        
        // At time 0, IOB should be 100%
        #expect(abs(model.percentEffectRemaining(at: 0) - 1.0) < 0.01)
        
        // At DIA, IOB should be 0
        #expect(abs(model.percentEffectRemaining(at: 6 * 3600) - 0.0) < 0.01)
        
        // IOB should decrease over time
        let iob1 = model.percentEffectRemaining(at: 1 * 3600)
        let iob2 = model.percentEffectRemaining(at: 2 * 3600)
        let iob3 = model.percentEffectRemaining(at: 3 * 3600)
        #expect(iob1 > iob2)
        #expect(iob2 > iob3)
    }
    
    @Test func walshmodelactivity() {
        let model = WalshInsulinModel()
        
        // Activity should be 0 before time 0
        #expect(model.percentActivity(at: -1) == 0.0)
        
        // Activity should be 0 after DIA
        #expect(model.percentActivity(at: 7 * 3600) == 0.0)
        
        // Activity should be positive during action
        let activity = model.percentActivity(at: 1.5 * 3600)
        #expect(activity > 0)
    }
    
    // MARK: - Exponential Model Tests
    
    @Test func exponentialmodelinitialization() {
        let model = ExponentialInsulinModel.rapidActingAdult
        #expect(model.actionDuration == 6 * 3600)
        #expect(model.peakActivityTime == 75 * 60)
    }
    
    @Test func exponentialmodeliob() {
        let model = ExponentialInsulinModel.rapidActingAdult
        
        // At time 0, IOB should be 100%
        #expect(abs(model.percentEffectRemaining(at: 0) - 1.0) < 0.01)
        
        // At DIA, IOB should be ~0
        #expect(abs(model.percentEffectRemaining(at: 6 * 3600) - 0.0) < 0.05)
        
        // IOB should decrease monotonically
        var previousIOB = 1.0
        for hour in 1...6 {
            let iob = model.percentEffectRemaining(at: Double(hour) * 3600)
            #expect(iob < previousIOB)
            previousIOB = iob
        }
    }
    
    @Test func exponentialmodelactivity() {
        let model = ExponentialInsulinModel.rapidActingAdult
        
        // Activity should be 0 at time 0
        #expect(abs(model.percentActivity(at: 0) - 0.0) < 0.01)
        
        // Activity should be 0 after DIA
        #expect(model.percentActivity(at: 7 * 3600) == 0.0)
        
        // Activity should peak around peak time
        let activityAtPeak = model.percentActivity(at: 75 * 60)
        let activityBefore = model.percentActivity(at: 30 * 60)
        let activityAfter = model.percentActivity(at: 3 * 3600)  // 3 hours - well past peak
        
        #expect(activityAtPeak > activityBefore)
        #expect(activityAtPeak > activityAfter)
    }
    
    @Test func presetmodels() {
        #expect(ExponentialInsulinModel.rapidActingAdult.peakActivityTime == 75 * 60)
        // T6-001 fix: Child peak is 65 min to match Loop (was 60)
        #expect(ExponentialInsulinModel.rapidActingChild.peakActivityTime == 65 * 60)
        #expect(ExponentialInsulinModel.fiasp.peakActivityTime == 55 * 60)
        // T6-001 fix: Lyumjev peak is 55 min to match Loop (was 50)
        #expect(ExponentialInsulinModel.lyumjev.peakActivityTime == 55 * 60)
        // T6-001 fix: Afrezza peak is 29 min to match Loop (was 20)
        #expect(ExponentialInsulinModel.afrezza.peakActivityTime == 29 * 60)
    }
    
    // MARK: - IOB Calculator Tests
    
    @Test func loopiobcalculatorsingledose() {
        let calculator = LoopIOBCalculator(model: ExponentialInsulinModel.rapidActingAdult)
        
        let dose = InsulinDose(
            units: 5.0,
            timestamp: Date(),
            type: .novolog
        )
        
        // At time of dose, IOB should equal dose
        let iob = calculator.insulinOnBoard(dose: dose, at: dose.timestamp)
        #expect(abs(iob - 5.0) < 0.01)
        
        // 3 hours later, IOB should be less
        let later = dose.timestamp.addingTimeInterval(3 * 3600)
        let iobLater = calculator.insulinOnBoard(dose: dose, at: later)
        #expect(iobLater < 5.0)
        #expect(iobLater > 0)
    }
    
    @Test func loopiobcalculatormultipledoses() {
        let calculator = LoopIOBCalculator(model: ExponentialInsulinModel.rapidActingAdult)
        
        let now = Date()
        let doses = [
            InsulinDose(units: 3.0, timestamp: now.addingTimeInterval(-3600), type: .novolog),
            InsulinDose(units: 2.0, timestamp: now.addingTimeInterval(-1800), type: .novolog),
            InsulinDose(units: 1.0, timestamp: now, type: .novolog)
        ]
        
        let totalIOB = calculator.insulinOnBoard(doses: doses, at: now)
        
        // Total IOB should be less than sum of doses (some has absorbed)
        #expect(totalIOB < 6.0)
        #expect(totalIOB > 1.0)  // At least the recent dose
    }
    
    @Test func loopiobcalculatorprojection() {
        let calculator = LoopIOBCalculator(model: ExponentialInsulinModel.rapidActingAdult)
        
        let dose = InsulinDose(
            units: 5.0,
            timestamp: Date(),
            type: .novolog
        )
        
        let projection = calculator.projectIOB(
            doses: [dose],
            duration: 6 * 3600,
            interval: 30 * 60  // 30 min intervals
        )
        
        // Should have 13 points (0, 0.5, 1, ... 6 hours)
        #expect(projection.count == 13)
        
        // IOB should decrease over time
        #expect(projection[0].iob > projection[6].iob)
        
        // Last point should be near 0
        #expect(projection.last?.iob ?? 1 < 0.1)
    }
    
    @Test func loopiobcalculatorinsulineffect() {
        let calculator = LoopIOBCalculator(model: ExponentialInsulinModel.rapidActingAdult)
        
        let dose = InsulinDose(
            units: 1.0,
            timestamp: Date(),
            type: .novolog
        )
        
        let effect = calculator.insulinEffect(
            doses: [dose],
            insulinSensitivity: 50,  // 50 mg/dL per unit
            duration: 6 * 3600,
            interval: 30 * 60
        )
        
        // Effect should start at 0
        #expect(abs(effect[0].effect - 0) < 0.01)
        
        // Effect should increase (more negative BG impact)
        #expect(effect[6].effect > effect[0].effect)
        
        // Total effect should approach ISF * dose
        let finalEffect = effect.last?.effect ?? 0
        #expect(abs(finalEffect - 50) < 5)  // 50 mg/dL for 1U at ISF 50
    }
    
    // MARK: - Model Factory Tests
    
    @Test func modelfactory() {
        let walsh = LoopInsulinModelFactory.model(for: .walsh)
        #expect(walsh is WalshInsulinModel)
        
        let rapid = LoopInsulinModelFactory.model(for: .rapidActingAdult)
        #expect(rapid is ExponentialInsulinModel)
        
        let fiasp = LoopInsulinModelFactory.model(for: .fiasp)
        #expect(fiasp is ExponentialInsulinModel)
    }
    
    @Test func calculatorwithmodeltype() {
        let calculator = LoopIOBCalculator(modelType: .fiasp)
        // T6-001 fix: Fiasp uses 6.0h DIA to match Loop (was 5.5)
        #expect(calculator.model.actionDuration == 6.0 * 3600)
    }
}

// MARK: - Loop Carb Math Tests

@Suite("LoopCarbMathTests")
struct LoopCarbMathTests {
    
    // MARK: - Linear Absorption Tests
    
    @Test func linearabsorptionatzero() {
        let model = LinearCarbAbsorption()
        #expect(abs(model.fractionAbsorbed(at: 0, absorptionTime: 3600) - 0.0) < 0.01)
    }
    
    @Test func linearabsorptionatend() {
        let model = LinearCarbAbsorption()
        #expect(abs(model.fractionAbsorbed(at: 3600, absorptionTime: 3600) - 1.0) < 0.01)
    }
    
    @Test func linearabsorptionatmiddle() {
        let model = LinearCarbAbsorption()
        #expect(abs(model.fractionAbsorbed(at: 1800, absorptionTime: 3600) - 0.5) < 0.01)
    }
    
    @Test func linearabsorptionrate() {
        let model = LinearCarbAbsorption()
        let rate = model.absorptionRate(at: 1800, absorptionTime: 3600)
        #expect(abs(rate - 1.0 / 3600) < 0.0001)
    }
    
    // MARK: - Parabolic Absorption Tests
    
    @Test func parabolicabsorptionboundaries() {
        let model = ParabolicCarbAbsorption()
        #expect(abs(model.fractionAbsorbed(at: 0, absorptionTime: 3600) - 0.0) < 0.01)
        #expect(abs(model.fractionAbsorbed(at: 3600, absorptionTime: 3600) - 1.0) < 0.01)
    }
    
    @Test func parabolicabsorptionshape() {
        let model = ParabolicCarbAbsorption()
        
        // Parabolic should absorb more in first half than linear
        let atQuarter = model.fractionAbsorbed(at: 900, absorptionTime: 3600)
        #expect(atQuarter > 0.25)  // More than linear 0.25
        
        let atHalf = model.fractionAbsorbed(at: 1800, absorptionTime: 3600)
        #expect(atHalf > 0.5)  // More than linear 0.5
    }
    
    @Test func parabolicabsorptionrate() {
        let model = ParabolicCarbAbsorption()
        
        // Rate should be higher at start than at end
        let rateAtStart = model.absorptionRate(at: 0, absorptionTime: 3600)
        let rateAtEnd = model.absorptionRate(at: 3500, absorptionTime: 3600)
        #expect(rateAtStart > rateAtEnd)
    }
    
    // MARK: - Piecewise Linear Tests
    
    @Test func piecewiselinearboundaries() {
        let model = PiecewiseLinearCarbAbsorption()
        #expect(abs(model.fractionAbsorbed(at: 0, absorptionTime: 3600) - 0.0) < 0.01)
        #expect(abs(model.fractionAbsorbed(at: 3600, absorptionTime: 3600) - 1.0) < 0.01)
    }
    
    @Test func piecewiselineardelayphase() {
        let model = PiecewiseLinearCarbAbsorption(delayFraction: 0.167)
        
        // During delay, absorption is slower
        let duringDelay = model.fractionAbsorbed(at: 300, absorptionTime: 3600)  // 5 min into 1 hour
        let linear = 300.0 / 3600.0  // What linear would be
        
        #expect(duringDelay < linear)
    }
    
    @Test func piecewiselinearratechange() {
        let model = PiecewiseLinearCarbAbsorption()
        
        // Rate during delay should be lower than after
        let rateDuringDelay = model.absorptionRate(at: 100, absorptionTime: 3600)
        let rateAfterDelay = model.absorptionRate(at: 1800, absorptionTime: 3600)
        
        #expect(rateDuringDelay < rateAfterDelay)
    }
    
    // MARK: - COB Calculator Tests
    
    @Test func loopcobcalculatorsingleentry() {
        let calculator = LoopCOBCalculator(model: .linear)
        
        let entry = CarbEntry(
            grams: 50,
            timestamp: Date(),
            absorptionType: .medium  // 3 hours
        )
        
        // At time of eating, COB should equal grams
        let cob = calculator.carbsOnBoard(entry: entry, at: entry.timestamp)
        #expect(abs(cob - 50) < 0.01)
        
        // After absorption time, COB should be 0
        let later = entry.timestamp.addingTimeInterval(3 * 3600 + 1)
        let cobLater = calculator.carbsOnBoard(entry: entry, at: later)
        #expect(abs(cobLater - 0) < 0.01)
    }
    
    @Test func loopcobcalculatormidabsorption() {
        let calculator = LoopCOBCalculator(model: .linear)
        
        let entry = CarbEntry(
            grams: 60,
            timestamp: Date(),
            absorptionTime: 2.0  // 2 hours
        )
        
        // At 1 hour (halfway), COB should be 30g with linear model
        let halfway = entry.timestamp.addingTimeInterval(3600)
        let cob = calculator.carbsOnBoard(entry: entry, at: halfway)
        #expect(abs(cob - 30) < 1)
    }
    
    @Test func loopcobcalculatormultipleentries() {
        let calculator = LoopCOBCalculator(model: .linear)
        
        let now = Date()
        let entries = [
            CarbEntry(grams: 30, timestamp: now, absorptionTime: 2.0),
            CarbEntry(grams: 20, timestamp: now.addingTimeInterval(-1800), absorptionTime: 2.0)
        ]
        
        let totalCOB = calculator.carbsOnBoard(entries: entries, at: now)
        
        // First entry: 30g (just started)
        // Second entry: 20g * (1 - 0.5/2) = 20 * 0.75 = 15g (30 min in)
        #expect(abs(totalCOB - 45) < 1)
    }
    
    @Test func loopcobcalculatorabsorptionrate() {
        let calculator = LoopCOBCalculator(model: .linear)
        
        let entry = CarbEntry(
            grams: 60,
            timestamp: Date(),
            absorptionTime: 2.0  // 2 hours
        )
        
        // Linear rate should be 60g / 2hr = 30 g/hr
        let rate = calculator.absorptionRate(entry: entry, at: entry.timestamp)
        #expect(abs(rate - 30) < 1)
    }
    
    @Test func loopcobcalculatorprojection() {
        let calculator = LoopCOBCalculator(model: .linear)
        
        let entry = CarbEntry(
            grams: 60,
            timestamp: Date(),
            absorptionTime: 2.0
        )
        
        let projection = calculator.projectCOB(
            entries: [entry],
            duration: 3 * 3600,
            interval: 30 * 60
        )
        
        // Should have 7 points (0, 0.5, 1, 1.5, 2, 2.5, 3 hours)
        #expect(projection.count == 7)
        
        // COB should decrease
        #expect(projection[0].cob > projection[3].cob)
        
        // Should be 0 by end
        #expect(abs(projection.last?.cob ?? 1 - 0) < 0.1)
    }
    
    // MARK: - Carb Effect Calculator Tests
    
    @Test func carbeffectcalculation() {
        let calculator = LoopCarbEffectCalculator(absorptionModel: .linear)
        
        let entry = CarbEntry(
            grams: 30,
            timestamp: Date(),
            absorptionTime: 1.0  // 1 hour
        )
        
        let effect = calculator.glucoseEffect(
            entries: [entry],
            carbRatio: 10,           // 10g per unit
            insulinSensitivity: 50,  // 50 mg/dL per unit
            duration: 2 * 3600,
            interval: 30 * 60
        )
        
        // Effect should start at 0
        #expect(abs(effect[0].effect - 0) < 0.01)
        
        // Effect should increase as carbs absorb
        #expect(effect[2].effect > effect[0].effect)
        
        // Total effect should approach: (30g / 10) * 50 = 150 mg/dL
        let finalEffect = effect.last?.effect ?? 0
        #expect(abs(finalEffect - 150) < 10)
    }
    
    @Test func expectedbgrise() {
        let calculator = LoopCarbEffectCalculator()
        
        let entry = CarbEntry(
            grams: 45,
            timestamp: Date()
        )
        
        // Expected rise = (45 / 15) * 50 = 150 mg/dL
        let rise = calculator.expectedBGRise(
            entry: entry,
            carbRatio: 15,
            insulinSensitivity: 50
        )
        
        #expect(abs(rise - 150) < 0.1)
    }
    
    // MARK: - Dynamic Absorption Tests
    
    @Test func observedabsorptionrate() {
        let rate = DynamicCarbAbsorption.observedAbsorptionRate(
            bgChange: 100,         // BG rose 100 mg/dL
            duration: 3600,        // Over 1 hour
            insulinEffect: -20,    // Insulin would have dropped 20 mg/dL
            carbRatio: 10,
            insulinSensitivity: 50
        )
        
        // Net carb effect = 100 - (-20) = 120 mg/dL
        // Carbs = (120 / 50) * 10 = 24g in 1 hour
        #expect(abs(rate - 24) < 1)
    }
    
    @Test func absorptionmultiplierclamping() {
        // Very high observed rate should clamp to 2x
        let high = DynamicCarbAbsorption.absorptionMultiplier(observedRate: 60, expectedRate: 10)
        #expect(abs(high - 2.0) < 0.01)
        
        // Very low observed rate should clamp to 0.5x
        let low = DynamicCarbAbsorption.absorptionMultiplier(observedRate: 2, expectedRate: 10)
        #expect(abs(low - 0.5) < 0.01)
        
        // Normal ratio should pass through
        let normal = DynamicCarbAbsorption.absorptionMultiplier(observedRate: 15, expectedRate: 10)
        #expect(abs(normal - 1.5) < 0.01)
    }
    
    // MARK: - Model Factory Tests
    
    @Test func carbmodelfactory() {
        let linear = LoopCarbModelFactory.model(for: .linear)
        #expect(linear is LinearCarbAbsorption)
        
        let parabolic = LoopCarbModelFactory.model(for: .parabolic)
        #expect(parabolic is ParabolicCarbAbsorption)
        
        let piecewise = LoopCarbModelFactory.model(for: .piecewiseLinear)
        #expect(piecewise is PiecewiseLinearCarbAbsorption)
    }
    
    @Test func absorptionmodeldisplaynames() {
        #expect(LoopCarbAbsorptionModel.linear.displayName == "Linear")
        #expect(LoopCarbAbsorptionModel.parabolic.displayName == "Parabolic")
        #expect(LoopCarbAbsorptionModel.piecewiseLinear.displayName == "Piecewise Linear (Loop)")
    }
}

// MARK: - Loop Glucose Prediction Tests

@Suite("LoopGlucosePredictionTests")
struct LoopGlucosePredictionTests {
    
    // MARK: - Configuration Tests
    
    @Test func defaultconfiguration() {
        let config = LoopGlucosePrediction.Configuration.default
        #expect(config.predictionDuration == 6 * 3600)
        #expect(config.predictionInterval == 5 * 60)
        #expect(config.includeMomentum)
        #expect(config.includeCarbEffect)
        #expect(config.includeInsulinEffect)
    }
    
    @Test func customconfiguration() {
        let config = LoopGlucosePrediction.Configuration(
            predictionDuration: 3 * 3600,
            includeMomentum: false
        )
        #expect(config.predictionDuration == 3 * 3600)
        #expect(!(config.includeMomentum))
    }
    
    // MARK: - Momentum Effect Tests
    
    @Test func momentumeffectwithrisingtrend() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create rising trend: 5 mg/dL per 5 minutes
        let history = (0..<6).map { i in
            GlucoseReading(
                glucose: 100 + Double(i) * 5,
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let effects = predictor.momentumEffect(glucoseHistory: history, startDate: now)
        
        #expect(!(effects.isEmpty))
        
        // Early effects should be positive (rising)
        #expect(effects[1].quantity > 0)
        
        // Effects should grow then stabilize (momentum accumulates then decays)
        // Compare effect at 10 min vs 5 min - magnitude should increase initially
        let effect5min = effects[1].quantity
        let effect10min = effects[2].quantity
        #expect(abs(effect10min) > abs(effect5min) * 0.5)  // Should maintain momentum
    }
    
    @Test func momentumeffectwithfallingtrend() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create falling trend: -3 mg/dL per 5 minutes
        let history = (0..<6).map { i in
            GlucoseReading(
                glucose: 150 - Double(i) * 3,
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let effects = predictor.momentumEffect(glucoseHistory: history, startDate: now)
        
        #expect(!(effects.isEmpty))
        
        // Early effects should be negative (falling)
        #expect(effects[1].quantity < 0)
    }
    
    @Test func momentumeffectwithinsufficienthistory() {
        let predictor = LoopGlucosePrediction()
        
        // Only one reading - not enough for momentum
        let history = [GlucoseReading(glucose: 100, timestamp: Date())]
        
        let effects = predictor.momentumEffect(glucoseHistory: history)
        #expect(effects.isEmpty)
    }
    
    // MARK: - GAP-031: Momentum Validation Tests
    
    @Test func momentumeffectblockedbylargejump() {
        // GAP-031: Large jumps (> 40 mg/dL) should disable momentum
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create history with a large jump (100 -> 200 mg/dL)
        let history = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-600)),
            GlucoseReading(glucose: 200, timestamp: now.addingTimeInterval(-300)),  // 100 mg/dL jump!
            GlucoseReading(glucose: 210, timestamp: now)
        ]
        
        let effects = predictor.momentumEffect(glucoseHistory: history, startDate: now)
        #expect(effects.isEmpty, "Momentum should be disabled for large jumps")
    }
    
    @Test func momentumeffectblockedbydatagap() {
        // GAP-031: Gaps (> 7.5 min) should disable momentum
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create history with a gap (15 minute gap between readings)
        let history = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-900)),  // -15 min
            GlucoseReading(glucose: 105, timestamp: now.addingTimeInterval(-300)),  // -5 min (10 min gap!)
            GlucoseReading(glucose: 110, timestamp: now)
        ]
        
        let effects = predictor.momentumEffect(glucoseHistory: history, startDate: now)
        #expect(effects.isEmpty, "Momentum should be disabled for data gaps")
    }
    
    @Test func momentumeffectallowedforvaliddata() {
        // GAP-031: Continuous, gradual data should allow momentum
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create valid history: continuous (5 min intervals), gradual changes
        let history = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(-600)),
            GlucoseReading(glucose: 105, timestamp: now.addingTimeInterval(-300)),
            GlucoseReading(glucose: 110, timestamp: now)
        ]
        
        let effects = predictor.momentumEffect(glucoseHistory: history, startDate: now)
        #expect(!effects.isEmpty, "Momentum should be allowed for valid data")
    }

    // MARK: - Insulin Effect Tests
    
    @Test func insulineffectlowersglucose() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        let doses = [
            InsulinDose(units: 5.0, timestamp: now, type: .novolog)
        ]
        
        let effects = predictor.insulinEffect(
            doses: doses,
            insulinSensitivity: 50,
            startDate: now
        )
        
        #expect(!(effects.isEmpty))
        
        // Later effects should be negative (insulin lowers BG)
        let midEffect = effects[effects.count / 2].quantity
        #expect(midEffect < 0)
    }
    
    @Test func insulineffectmagnitude() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        let doses = [
            InsulinDose(units: 1.0, timestamp: now, type: .novolog)
        ]
        
        let effects = predictor.insulinEffect(
            doses: doses,
            insulinSensitivity: 50,  // 50 mg/dL per unit
            startDate: now
        )
        
        // Final effect should approach -50 mg/dL (1 unit * 50 ISF)
        let finalEffect = effects.last?.quantity ?? 0
        #expect(abs(finalEffect - -50) < 5)
    }
    
    // MARK: - Carb Effect Tests
    
    @Test func carbeffectraisesglucose() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        let entries = [
            CarbEntry(grams: 30, timestamp: now, absorptionTime: 2.0)
        ]
        
        let effects = predictor.carbEffect(
            entries: entries,
            carbRatio: 10,
            insulinSensitivity: 50,
            startDate: now
        )
        
        #expect(!(effects.isEmpty))
        
        // Later effects should be positive (carbs raise BG)
        let midEffect = effects[effects.count / 2].quantity
        #expect(midEffect > 0)
    }
    
    @Test func carbeffectmagnitude() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        let entries = [
            CarbEntry(grams: 30, timestamp: now, absorptionTime: 2.0)
        ]
        
        let effects = predictor.carbEffect(
            entries: entries,
            carbRatio: 10,          // 10g per unit
            insulinSensitivity: 50,  // 50 mg/dL per unit
            startDate: now
        )
        
        // Final effect should approach (30/10)*50 = 150 mg/dL
        let finalEffect = effects.last?.quantity ?? 0
        #expect(abs(finalEffect - 150) < 20)
    }
    
    // MARK: - Combined Prediction Tests
    
    @Test func combinedpredictionwithalleffects() {
        let predictor = LoopGlucosePrediction()
        let now = Date()
        
        // Create balanced scenario
        let history = (0..<6).map { i in
            GlucoseReading(
                glucose: 120,  // Flat trend
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let doses = [
            InsulinDose(units: 3.0, timestamp: now.addingTimeInterval(-1800), type: .novolog)
        ]
        
        let entries = [
            CarbEntry(grams: 30, timestamp: now, absorptionTime: 2.0)
        ]
        
        let predictions = predictor.predict(
            currentGlucose: 120,
            glucoseHistory: history,
            doses: doses,
            carbEntries: entries,
            insulinSensitivity: 50,
            carbRatio: 10
        )
        
        #expect(!(predictions.isEmpty))
        
        // First prediction should be close to current glucose
        #expect(abs((predictions.first?.glucose ?? 0) - 120) < 10)
    }
    
    @Test func flatpredictionwithnoeffects() {
        let config = LoopGlucosePrediction.Configuration(
            includeMomentum: false,
            includeCarbEffect: false,
            includeInsulinEffect: false
        )
        let predictor = LoopGlucosePrediction(configuration: config)
        
        let predictions = predictor.predict(
            currentGlucose: 100,
            insulinSensitivity: 50,
            carbRatio: 10
        )
        
        #expect(!(predictions.isEmpty))
        
        // All predictions should equal starting glucose
        for prediction in predictions {
            #expect(abs(prediction.glucose - 100) < 0.01)
        }
    }
    
    // MARK: - Prediction Summary Tests
    
    @Test func predictionsummary() {
        let now = Date()
        let predictions = [
            PredictedGlucose(date: now, glucose: 120),
            PredictedGlucose(date: now.addingTimeInterval(300), glucose: 130),
            PredictedGlucose(date: now.addingTimeInterval(600), glucose: 140),  // Max
            PredictedGlucose(date: now.addingTimeInterval(900), glucose: 110),
            PredictedGlucose(date: now.addingTimeInterval(1200), glucose: 90),   // Min
            PredictedGlucose(date: now.addingTimeInterval(1500), glucose: 100)   // Eventual
        ]
        
        let summary = PredictionSummary(predictions: predictions)
        
        #expect(abs(summary.minGlucose - 90) < 0.01)
        #expect(abs(summary.maxGlucose - 140) < 0.01)
        #expect(abs(summary.eventualGlucose - 100) < 0.01)
        #expect(summary.timeToMinMinutes == 20)
        #expect(summary.timeToMaxMinutes == 10)
    }
    
    @Test func emptypredictionsummary() {
        let summary = PredictionSummary(predictions: [])
        #expect(summary.minGlucose == 0)
        #expect(summary.maxGlucose == 0)
        #expect(summary.eventualGlucose == 0)
    }
    
    // MARK: - Effect Combiner Tests
    
    @Test func effectcombinercombine() {
        let now = Date()
        
        let insulinEffects = [
            GlucoseEffect(date: now, quantity: 0),
            GlucoseEffect(date: now.addingTimeInterval(300), quantity: -10),
            GlucoseEffect(date: now.addingTimeInterval(600), quantity: -25)
        ]
        
        let carbEffects = [
            GlucoseEffect(date: now, quantity: 0),
            GlucoseEffect(date: now.addingTimeInterval(300), quantity: 15),
            GlucoseEffect(date: now.addingTimeInterval(600), quantity: 40)
        ]
        
        let combined = EffectCombiner.combine(
            effects: [insulinEffects, carbEffects],
            startDate: now,
            duration: 600,
            interval: 300
        )
        
        #expect(combined.count == 3)
        
        // Check combined values
        #expect(abs(combined[0].quantity - 0) < 0.01)      // 0 + 0
        #expect(abs(combined[1].quantity - 5) < 0.01)      // -10 + 15
        #expect(abs(combined[2].quantity - 15) < 0.01)     // -25 + 40
    }
    
    @Test func effectcombinerinterpolate() {
        let now = Date()
        
        let effects = [
            GlucoseEffect(date: now, quantity: 0),
            GlucoseEffect(date: now.addingTimeInterval(600), quantity: 60)
        ]
        
        let interpolated = EffectCombiner.interpolate(
            effects: effects,
            startDate: now,
            duration: 600,
            interval: 300
        )
        
        #expect(interpolated.count == 3)
        
        // Middle point should be interpolated
        #expect(abs(interpolated[0].quantity - 0) < 0.01)
        #expect(abs(interpolated[1].quantity - 30) < 0.01)  // Midpoint
        #expect(abs(interpolated[2].quantity - 60) < 0.01)
    }
}

// MARK: - Retrospective Correction Tests

@Suite("RetrospectiveCorrectionTests")
struct RetrospectiveCorrectionTests {
    
    // MARK: - Configuration Tests
    
    @Test func defaultconfiguration() {
        let config = RetrospectiveCorrection.Configuration.default
        #expect(config.retrospectiveDuration == 30 * 60)
        #expect(config.minimumDiscrepancies == 3)
        #expect(config.significanceThreshold == 10)
        #expect(config.correctionDuration == 60 * 60)
    }
    
    @Test func customconfiguration() {
        let config = RetrospectiveCorrection.Configuration(
            retrospectiveDuration: 45 * 60,
            minimumDiscrepancies: 5,
            significanceThreshold: 15
        )
        #expect(config.retrospectiveDuration == 45 * 60)
        #expect(config.minimumDiscrepancies == 5)
        #expect(config.significanceThreshold == 15)
    }
    
    // MARK: - Discrepancy Tests
    
    @Test func glucosediscrepancycalculation() {
        let discrepancy = GlucoseDiscrepancy(
            date: Date(),
            predicted: 100,
            actual: 120
        )
        
        #expect(discrepancy.discrepancy == 20)
        #expect(abs(discrepancy.percentageError - 20) < 0.1)
    }
    
    @Test func discrepancywithloweractual() {
        let discrepancy = GlucoseDiscrepancy(
            date: Date(),
            predicted: 150,
            actual: 130
        )
        
        #expect(discrepancy.discrepancy == -20)
        #expect(discrepancy.percentageError < 0)
    }
    
    // MARK: - Discrepancy Calculation Tests
    
    @Test func calculatediscrepancies() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Create predictions
        let predictions = (0..<6).map { i in
            PredictedGlucose(
                date: now.addingTimeInterval(Double(i - 5) * 300),
                glucose: 100
            )
        }
        
        // Create actuals that are higher than predicted
        let actuals = (0..<6).map { i in
            GlucoseReading(
                glucose: 115,  // 15 higher than predicted
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let discrepancies = correction.calculateDiscrepancies(
            predictions: predictions,
            actuals: actuals,
            referenceDate: now
        )
        
        #expect(!(discrepancies.isEmpty))
        
        // All discrepancies should be positive (actual > predicted)
        for d in discrepancies {
            #expect(abs(d.discrepancy - 15) < 1)
        }
    }
    
    @Test func calculatediscrepancieswithnomatch() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Predictions far in the future
        let predictions = [
            PredictedGlucose(date: now.addingTimeInterval(3600), glucose: 100)
        ]
        
        // Actuals in the past
        let actuals = [
            GlucoseReading(glucose: 115, timestamp: now.addingTimeInterval(-600))
        ]
        
        let discrepancies = correction.calculateDiscrepancies(
            predictions: predictions,
            actuals: actuals,
            referenceDate: now
        )
        
        // Should still find closest match
        #expect(discrepancies.count == 1)
    }
    
    // MARK: - Correction Calculation Tests
    
    @Test func correctionwithinsufficientdiscrepancies() {
        let correction = RetrospectiveCorrection()
        
        // Only 2 discrepancies (minimum is 3)
        let discrepancies = [
            GlucoseDiscrepancy(date: Date(), predicted: 100, actual: 120),
            GlucoseDiscrepancy(date: Date().addingTimeInterval(-300), predicted: 100, actual: 115)
        ]
        
        let result = correction.calculateCorrection(discrepancies: discrepancies)
        
        #expect(!(result.isSignificant))
        #expect(result.correctionEffect.isEmpty)
    }
    
    @Test func correctionwithsignificantdiscrepancy() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Create significant positive discrepancies (actual > predicted by 20)
        let discrepancies = (0..<5).map { i in
            GlucoseDiscrepancy(
                date: now.addingTimeInterval(Double(-i) * 300),
                predicted: 100,
                actual: 120
            )
        }
        
        let result = correction.calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: now
        )
        
        #expect(result.isSignificant)
        #expect(!(result.correctionEffect.isEmpty))
        #expect(abs(result.averageDiscrepancy - 20) < 0.1)
        
        // Correction should be positive (we need to adjust predictions up)
        #expect(result.correctionEffect.first?.quantity ?? 0 > 0)
    }
    
    @Test func correctionwithinsignificantdiscrepancy() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Create small discrepancies (below threshold)
        let discrepancies = (0..<5).map { i in
            GlucoseDiscrepancy(
                date: now.addingTimeInterval(Double(-i) * 300),
                predicted: 100,
                actual: 105  // Only 5 difference
            )
        }
        
        let result = correction.calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: now
        )
        
        #expect(!(result.isSignificant))
        #expect(result.correctionEffect.isEmpty)
    }
    
    @Test func correctionweightedaverage() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Recent discrepancy is larger than old ones
        let discrepancies = [
            GlucoseDiscrepancy(date: now, predicted: 100, actual: 130),  // +30, most recent
            GlucoseDiscrepancy(date: now.addingTimeInterval(-600), predicted: 100, actual: 110),  // +10
            GlucoseDiscrepancy(date: now.addingTimeInterval(-1200), predicted: 100, actual: 110)  // +10
        ]
        
        let result = correction.calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: now
        )
        
        // Weighted should be higher than simple average due to recent high discrepancy
        let simpleAverage = (30.0 + 10.0 + 10.0) / 3.0  // ~16.67
        #expect(result.weightedDiscrepancy > simpleAverage)
    }
    
    @Test func correctioneffectdecays() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        let discrepancies = (0..<5).map { i in
            GlucoseDiscrepancy(
                date: now.addingTimeInterval(Double(-i) * 300),
                predicted: 100,
                actual: 130
            )
        }
        
        let result = correction.calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: now
        )
        
        #expect(!(result.correctionEffect.isEmpty))
        
        // Effect should decay over time
        let firstEffect = result.correctionEffect.first?.quantity ?? 0
        let lastEffect = result.correctionEffect.last?.quantity ?? 0
        
        #expect(abs(firstEffect) > abs(lastEffect))
    }
    
    // MARK: - Velocity Tests
    
    @Test func discrepancyvelocity() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        // Increasing discrepancy over time
        let discrepancies = [
            GlucoseDiscrepancy(date: now.addingTimeInterval(-1800), predicted: 100, actual: 110),  // +10, 30 min ago
            GlucoseDiscrepancy(date: now.addingTimeInterval(-900), predicted: 100, actual: 115),   // +15, 15 min ago
            GlucoseDiscrepancy(date: now, predicted: 100, actual: 120)  // +20, now
        ]
        
        let result = correction.calculateCorrection(
            discrepancies: discrepancies,
            referenceDate: now
        )
        
        // Velocity should be positive (discrepancy increasing)
        #expect(result.discrepancyVelocity > 0)
    }
    
    // MARK: - Full Analysis Tests
    
    @Test func fullanalysis() {
        let correction = RetrospectiveCorrection()
        let now = Date()
        
        let predictions = (0..<6).map { i in
            PredictedGlucose(
                date: now.addingTimeInterval(Double(i - 5) * 300),
                glucose: 100
            )
        }
        
        let actuals = (0..<6).map { i in
            GlucoseReading(
                glucose: 125,
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let result = correction.analyze(
            predictions: predictions,
            actuals: actuals,
            referenceDate: now
        )
        
        #expect(result.isSignificant)
        #expect(abs(result.averageDiscrepancy - 25) < 1)
    }
    
    // MARK: - Statistics Tests
    
    @Test func retrospectivecorrectionstats() {
        let now = Date()
        
        let discrepancyBatches = [
            // First analysis: significant correction
            (0..<5).map { i in
                GlucoseDiscrepancy(
                    date: now.addingTimeInterval(Double(-i) * 300),
                    predicted: 100,
                    actual: 120
                )
            },
            // Second analysis: insignificant
            (0..<5).map { i in
                GlucoseDiscrepancy(
                    date: now.addingTimeInterval(Double(-i) * 300),
                    predicted: 100,
                    actual: 105
                )
            }
        ]
        
        let stats = RetrospectiveCorrectionStats(discrepancies: discrepancyBatches)
        
        #expect(stats.totalAnalyses == 2)
        #expect(stats.significantCorrections == 1)
        #expect(abs(stats.correctionRate - 50) < 0.1)
        #expect(stats.averageAbsoluteError > 0)
        #expect(stats.rmse > 0)
    }
    
    @Test func emptystats() {
        let stats = RetrospectiveCorrectionStats(discrepancies: [])
        
        #expect(stats.totalAnalyses == 0)
        #expect(stats.averageAbsoluteError == 0)
        #expect(stats.rmse == 0)
        #expect(stats.bias == 0)
    }
}

// MARK: - Loop Dose Recommendation Tests

@Suite("LoopDoseRecommendationTests")
struct LoopDoseRecommendationTests {
    
    // MARK: - Configuration Tests
    
    @Test func defaultconfiguration() {
        let config = LoopDoseCalculator.Configuration.default
        #expect(config.maxBasalRate == 5.0)
        #expect(config.maxBolus == 10.0)
        #expect(config.suspendThreshold == 70)
        #expect(config.tempBasalDuration == 30 * 60)
    }
    
    @Test func customconfiguration() {
        let config = LoopDoseCalculator.Configuration(
            maxBasalRate: 3.0,
            maxBolus: 8.0,
            suspendThreshold: 80
        )
        #expect(config.maxBasalRate == 3.0)
        #expect(config.maxBolus == 8.0)
        #expect(config.suspendThreshold == 80)
    }
    
    // MARK: - Dose Recommendation Types
    
    @Test func tempbasalrecommendation() {
        let rec = DoseRecommendation.tempBasal(
            rate: 1.5,
            duration: 30 * 60,
            reason: "Test"
        )
        
        #expect(rec.type == .tempBasal)
        #expect(rec.rate == 1.5)
        #expect(rec.duration == TimeInterval(30 * 60))
        #expect(rec.units == nil)
    }
    
    @Test func bolusrecommendation() {
        let rec = DoseRecommendation.bolus(units: 3.5, reason: "Test bolus")
        
        #expect(rec.type == .bolus)
        #expect(rec.units == 3.5)
        #expect(rec.rate == nil)
    }
    
    @Test func suspendrecommendation() {
        let rec = DoseRecommendation.suspend(reason: "Low predicted")
        
        #expect(rec.type == .suspend)
        #expect(rec.rate == 0)
    }
    
    // MARK: - Temp Basal Recommendation Tests
    
    @Test func tempbasalhighglucose() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 180,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(result.recommendation.type == .tempBasal)
        
        // Should recommend higher than scheduled for high BG
        #expect(result.recommendation.rate ?? 0 > 1.0)
    }
    
    @Test func tempbasallowglucose() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 75,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        // Should recommend zero or suspend for low BG
        #expect(result.recommendation.rate ?? 1 <= 0)
    }
    
    @Test func tempbasalsuspendonpredictedlow() {
        let calculator = LoopDoseCalculator(configuration: .init(suspendThreshold: 70))
        
        // Simulate falling glucose
        let now = Date()
        let history = (0..<6).map { i in
            GlucoseReading(
                glucose: 100 - Double(i) * 8,  // Falling 8 mg/dL per 5 min
                timestamp: now.addingTimeInterval(Double(i - 5) * 300)
            )
        }
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 85,
            glucoseHistory: history,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        // Should recommend lower than scheduled due to falling trend and below target
        #expect(result.recommendation.rate ?? 10 < 1.0)
    }
    
    @Test func tempbasalattarget() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 100,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(result.recommendation.type == .tempBasal)
        
        // Rate should be close to scheduled when at target
        #expect(abs((result.recommendation.rate ?? 0) - 1.0) < 0.5)
    }
    
    @Test func tempbasalrespectmaxrate() {
        let config = LoopDoseCalculator.Configuration(maxBasalRate: 3.0)
        let calculator = LoopDoseCalculator(configuration: config)
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 300,  // Very high
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(result.recommendation.rate ?? 10 <= 3.0)
        #expect(result.safetyLimited)
    }
    
    // MARK: - Bolus Recommendation Tests
    
    @Test func bolusformeal() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendBolus(
            currentGlucose: 100,
            carbsToEat: 50,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(result.recommendation.type == .bolus)
        
        // 50g / 10 ICR = 5U carb bolus
        #expect(abs((result.recommendation.units ?? 0) - 5.0) < 0.1)
    }
    
    @Test func bolusformealpluscorrection() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendBolus(
            currentGlucose: 150,  // 50 above target
            carbsToEat: 30,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        // 30g / 10 ICR = 3U carb + (150-100)/50 = 1U correction = 4U
        #expect(abs((result.recommendation.units ?? 0) - 4.0) < 0.5)
    }
    
    @Test func bolussubtractsiob() {
        let calculator = LoopDoseCalculator()
        let now = Date()
        
        // Existing IOB from recent bolus
        let doses = [
            InsulinDose(units: 2.0, timestamp: now.addingTimeInterval(-1800), type: .novolog)
        ]
        
        let result = calculator.recommendBolus(
            currentGlucose: 180,  // 80 above target
            carbsToEat: 0,
            doses: doses,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        // Correction would be 80/50 = 1.6U, but should subtract IOB
        #expect(result.recommendation.units ?? 10 < 1.6)
    }
    
    @Test func bolusrespectmaxbolus() {
        let config = LoopDoseCalculator.Configuration(maxBolus: 5.0)
        let calculator = LoopDoseCalculator(configuration: config)
        
        let result = calculator.recommendBolus(
            currentGlucose: 100,
            carbsToEat: 100,  // Would need 10U
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(abs((result.recommendation.units ?? 0) - 5.0) < 0.01)
        #expect(result.safetyLimited)
    }
    
    @Test func bolusnocorrectwhenlow() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendBolus(
            currentGlucose: 70,  // Low, below minimumBGGuard
            carbsToEat: 30,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        // Should only get carb bolus, no correction
        #expect(abs((result.recommendation.units ?? 0) - 3.0) < 0.1)  // 30/10 = 3U
        #expect(result.safetyLimited)
    }
    
    // MARK: - Correction Bolus Tests
    
    @Test func correctionbolusonly() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendCorrectionBolus(
            currentGlucose: 200,
            insulinSensitivity: 50,
            targetGlucose: 100
        )
        
        // (200-100)/50 = 2U correction
        #expect(abs((result.recommendation.units ?? 0) - 2.0) < 0.1)
    }
    
    @Test func nocorrectionwhenattarget() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendCorrectionBolus(
            currentGlucose: 100,
            insulinSensitivity: 50,
            targetGlucose: 100
        )
        
        #expect(abs((result.recommendation.units ?? 0) - 0) < 0.05)
    }
    
    // MARK: - Integration Tests
    
    @Test func recommendationincludespredictions() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 150,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(!(result.predictions.isEmpty))
        #expect(result.predictedEventual > 0)
    }
    
    @Test func recommendationresultfields() {
        let calculator = LoopDoseCalculator()
        
        let result = calculator.recommendTempBasal(
            currentGlucose: 120,
            scheduledBasalRate: 1.0,
            insulinSensitivity: 50,
            carbRatio: 10,
            targetGlucose: 100
        )
        
        #expect(result.currentGlucose == 120)
        #expect(result.targetGlucose == 100)
        #expect(result.currentIOB >= 0)
        #expect(result.currentCOB >= 0)
    }
}

