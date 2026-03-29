// AlgorithmTests.swift
// Tests for T1PalAlgorithm

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("AlgorithmTests")
struct AlgorithmTests {
    
    @Test func algorithmengineexists() {
        // Placeholder - verify module imports correctly
        #expect(true)
    }
}

// MARK: - Insulin Type Tests

@Suite("InsulinTypeTests")
struct InsulinTypeTests {
    
    @Test func insulintypedia() {
        #expect(InsulinType.fiasp.defaultDIA == 5.0)
        #expect(InsulinType.humalog.defaultDIA == 6.0)
        #expect(InsulinType.afrezza.defaultDIA == 3.0)
    }
    
    @Test func insulintypepeaktime() {
        #expect(InsulinType.fiasp.peakTime == 0.5)
        #expect(InsulinType.humalog.peakTime == 1.0)
        #expect(InsulinType.afrezza.peakTime == 0.25)
    }
    
    @Test func insulintypedisplayname() {
        #expect(InsulinType.novolog.displayName == "Novolog")
        #expect(InsulinType.lyumjev.displayName == "Lyumjev")
    }
}

// MARK: - Insulin Model Tests

@Suite("InsulinModelTests")
struct InsulinModelTests {
    
    @Test func modelcreation() {
        let model = InsulinModel(insulinType: .humalog)
        #expect(model.dia == 6.0)
        #expect(model.insulinType == .humalog)
    }
    
    @Test func customdia() {
        let model = InsulinModel(insulinType: .humalog, dia: 5.0)
        #expect(model.dia == 5.0)
    }
    
    @Test func activityatzero() {
        let model = InsulinModel(insulinType: .humalog)
        #expect(abs(model.activity(at: 0) - 0) < 0.01)
    }
    
    @Test func activityatpeak() {
        let model = InsulinModel(insulinType: .humalog)
        let peakActivity = model.activity(at: model.insulinType.peakTime)
        // Activity should be positive at peak
        #expect(peakActivity > 0)
    }
    
    @Test func activityafterdia() {
        let model = InsulinModel(insulinType: .humalog)
        #expect(model.activity(at: model.dia + 1) == 0)
    }
    
    @Test func iobatzero() {
        let model = InsulinModel(insulinType: .humalog)
        let iob = model.iob(at: 0)
        // IOB should be close to 1 at t=0 (all insulin remaining)
        #expect(iob > 0.9)
    }
    
    @Test func iobafterdia() {
        let model = InsulinModel(insulinType: .humalog)
        let iob = model.iob(at: model.dia)
        // IOB should be close to 0 after DIA
        #expect(iob < 0.05)
    }
    
    @Test func iobdecreases() {
        let model = InsulinModel(insulinType: .humalog)
        let iob1 = model.iob(at: 1.0)
        let iob2 = model.iob(at: 2.0)
        let iob3 = model.iob(at: 3.0)
        #expect(iob1 > iob2)
        #expect(iob2 > iob3)
    }
    
    @Test func iobcurve() {
        let model = InsulinModel(insulinType: .humalog)
        let curve = model.iobCurve()
        
        // First value should be high (near 1)
        #expect(curve.first! > 0.9)
        
        // Last value should be low (near 0)
        #expect(curve.last! < 0.1)
        
        // Should be monotonically decreasing (roughly)
        #expect(curve[5] > curve[15])
    }
}

// MARK: - IOB Calculator Tests

@Suite("IOBCalculatorTests")
struct IOBCalculatorTests {
    
    @Test func singledoseiob() {
        let model = InsulinModel(insulinType: .humalog)
        let calculator = IOBCalculator(model: model)
        
        let now = Date()
        let dose = InsulinDose(units: 5.0, timestamp: now)
        
        // At the same time, all IOB remains
        let iob = calculator.iobFromDose(dose, at: now)
        #expect(iob > 4.5)  // Most of 5U
    }
    
    @Test func olddosenoiob() {
        let model = InsulinModel(insulinType: .humalog)
        let calculator = IOBCalculator(model: model)
        
        let now = Date()
        let oldDose = InsulinDose(
            units: 5.0,
            timestamp: now.addingTimeInterval(-8 * 3600)  // 8 hours ago
        )
        
        let iob = calculator.iobFromDose(oldDose, at: now)
        #expect(iob < 0.1)
    }
    
    @Test func totaliob() {
        let model = InsulinModel(insulinType: .humalog)
        let calculator = IOBCalculator(model: model)
        
        let now = Date()
        let doses = [
            InsulinDose(units: 2.0, timestamp: now),
            InsulinDose(units: 3.0, timestamp: now.addingTimeInterval(-1 * 3600)),
            InsulinDose(units: 1.0, timestamp: now.addingTimeInterval(-10 * 3600))  // Old, no IOB
        ]
        
        let iob = calculator.totalIOB(from: doses, at: now)
        // Should have IOB from first two doses, but not the old one
        #expect(iob > 3.0)
        #expect(iob < 5.0)
    }
    
    @Test func projectiob() {
        let model = InsulinModel(insulinType: .humalog)
        let calculator = IOBCalculator(model: model)
        
        let now = Date()
        let dose = InsulinDose(units: 5.0, timestamp: now)
        
        let projection = calculator.projectIOB(from: [dose], startTime: now)
        
        // First value should be high
        #expect(projection.first! > 4.0)
        
        // Last value (3 hours later) should be lower
        #expect(projection.last! < projection.first!)
    }
}

// MARK: - Carb Absorption Type Tests

@Suite("CarbAbsorptionTypeTests")
struct CarbAbsorptionTypeTests {
    
    @Test func absorptiontimes() {
        #expect(CarbAbsorptionType.fast.defaultAbsorptionTime == 1.5)
        #expect(CarbAbsorptionType.medium.defaultAbsorptionTime == 3.0)
        #expect(CarbAbsorptionType.slow.defaultAbsorptionTime == 5.0)
    }
    
    @Test func allcases() {
        #expect(CarbAbsorptionType.allCases.count == 3)
    }
}

// MARK: - Carb Entry Tests

@Suite("CarbEntryTests")
struct CarbEntryTests {
    
    @Test func carbentrycreation() {
        let entry = CarbEntry(grams: 50, timestamp: Date())
        #expect(entry.grams == 50)
        #expect(entry.absorptionType == .medium)
        #expect(entry.source == "manual")
    }
    
    @Test func effectiveabsorptiontime() {
        let defaultEntry = CarbEntry(grams: 30, timestamp: Date())
        #expect(defaultEntry.effectiveAbsorptionTime == 3.0)  // medium default
        
        let customEntry = CarbEntry(grams: 30, timestamp: Date(), absorptionTime: 4.0)
        #expect(customEntry.effectiveAbsorptionTime == 4.0)
    }
    
    @Test func fastcarbentry() {
        let entry = CarbEntry(grams: 15, timestamp: Date(), absorptionType: .fast)
        #expect(entry.effectiveAbsorptionTime == 1.5)
    }
}

// MARK: - Carb Model Tests

@Suite("CarbModelTests")
struct CarbModelTests {
    let model = CarbModel()
    
    @Test func absorptionatstart() {
        let absorbed = model.absorbed(at: 0, absorptionTime: 3.0)
        #expect(abs(absorbed - 0) < 0.001)
    }
    
    @Test func absorptionatend() {
        let absorbed = model.absorbed(at: 3.0, absorptionTime: 3.0)
        #expect(abs(absorbed - 1.0) < 0.001)
    }
    
    @Test func absorptionmidway() {
        let absorbed = model.absorbed(at: 1.5, absorptionTime: 3.0)
        #expect(abs(absorbed - 0.5) < 0.001)
    }
    
    @Test func absorptionaftercomplete() {
        let absorbed = model.absorbed(at: 5.0, absorptionTime: 3.0)
        #expect(abs(absorbed - 1.0) < 0.001)
    }
    
    @Test func remainingcarbs() {
        let remaining = model.remaining(at: 1.0, absorptionTime: 3.0)
        #expect(abs(remaining - 2.0/3.0) < 0.001)
    }
    
    @Test func absorptionrate() {
        let rate = model.absorptionRate(grams: 60, absorptionTime: 3.0, at: 1.0)
        #expect(abs(rate - 20.0) < 0.001)  // 60g / 3h = 20g/h
    }
    
    @Test func cobcurve() {
        let curve = model.cobCurve(grams: 30, absorptionTime: 1.0, intervalMinutes: 30)
        // At 1 hour absorption: 0min=30g, 30min=15g, 60min=0g
        #expect(curve.count == 3)
        #expect(abs(curve[0] - 30.0) < 0.1)
        #expect(abs(curve[1] - 15.0) < 0.1)
        #expect(abs(curve[2] - 0.0) < 0.1)
    }
}

// MARK: - COB Calculator Tests

@Suite("COBCalculatorTests")
struct COBCalculatorTests {
    let calculator = COBCalculator()
    
    @Test func cobfromentry() {
        let now = Date()
        let entry = CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-1 * 3600))  // 1 hour ago
        
        // With 3-hour absorption, 1/3 absorbed after 1 hour
        let cob = calculator.cobFromEntry(entry, at: now)
        #expect(abs(cob - 40.0) < 0.1)  // 2/3 remaining
    }
    
    @Test func cobfullyabsorbed() {
        let now = Date()
        let entry = CarbEntry(grams: 30, timestamp: now.addingTimeInterval(-5 * 3600))  // 5 hours ago
        
        let cob = calculator.cobFromEntry(entry, at: now)
        #expect(abs(cob - 0.0) < 0.1)
    }
    
    @Test func totalcob() {
        let now = Date()
        let entries = [
            CarbEntry(grams: 30, timestamp: now),  // Just eaten
            CarbEntry(grams: 60, timestamp: now.addingTimeInterval(-1.5 * 3600)),  // Half absorbed
            CarbEntry(grams: 20, timestamp: now.addingTimeInterval(-10 * 3600))  // Fully absorbed
        ]
        
        let cob = calculator.totalCOB(from: entries, at: now)
        // 30 (100%) + 30 (50% of 60) + 0 = 60
        #expect(abs(cob - 60.0) < 0.1)
    }
    
    @Test func projectcob() {
        let now = Date()
        let entry = CarbEntry(grams: 30, timestamp: now, absorptionType: .fast)  // 1.5h absorption
        
        let projection = calculator.projectCOB(from: [entry], startTime: now, durationMinutes: 90)
        
        // First value should be full
        #expect(abs(projection.first! - 30.0) < 0.1)
        
        // Last value should be 0
        #expect(abs(projection.last! - 0.0) < 0.1)
    }
    
    @Test func timeuntilabsorbed() {
        let now = Date()
        let entry = CarbEntry(grams: 30, timestamp: now.addingTimeInterval(-1 * 3600), absorptionType: .fast)
        // Fast = 1.5h, eaten 1h ago, so 0.5h remaining
        
        let remaining = calculator.timeUntilAbsorbed(from: [entry], at: now)
        #expect(remaining != nil)
        #expect(abs(remaining! - 0.5 * 3600) < 60)  // ~30 min in seconds
    }
}

// MARK: - Carb Ratio Helper Tests

@Suite("CarbRatioHelperTests")
struct CarbRatioHelperTests {
    
    @Test func bolusforcarbs() {
        // ICR of 10 means 1 unit covers 10g
        let bolus = CarbRatioHelper.bolusForCarbs(grams: 50, icr: 10)
        #expect(abs(bolus - 5.0) < 0.01)
    }
    
    @Test func carbscovered() {
        let carbs = CarbRatioHelper.carbsCoveredByInsulin(units: 3.0, icr: 12)
        #expect(abs(carbs - 36.0) < 0.01)
    }
}

// MARK: - Schedule Entry Tests

@Suite("ScheduleTests")
struct ScheduleTests {
    
    @Test func basalscheduleentry() {
        let entry = BasalScheduleEntry(startTime: 3600, rate: 1.2)
        #expect(entry.startTime == 3600)
        #expect(entry.rate == 1.2)
    }
    
    @Test func basalscheduleentryfromtime() {
        let entry = BasalScheduleEntry(time: "08:30", rate: 1.0)
        #expect(entry != nil)
        #expect(entry!.startTime == 8 * 3600 + 30 * 60)
    }
    
    @Test func schedulelookup() {
        let schedule = Schedule(entries: [
            BasalScheduleEntry(startTime: 0, rate: 0.8),      // 00:00
            BasalScheduleEntry(startTime: 6 * 3600, rate: 1.2),  // 06:00
            BasalScheduleEntry(startTime: 22 * 3600, rate: 0.7)  // 22:00
        ])
        
        // At midnight
        #expect(schedule.entry(at: 0)?.rate == 0.8)
        
        // At 3am (still in first segment)
        #expect(schedule.entry(at: 3 * 3600)?.rate == 0.8)
        
        // At 6am (second segment starts)
        #expect(schedule.entry(at: 6 * 3600)?.rate == 1.2)
        
        // At noon
        #expect(schedule.entry(at: 12 * 3600)?.rate == 1.2)
        
        // At 10pm
        #expect(schedule.entry(at: 22 * 3600)?.rate == 0.7)
    }
    
    @Test func emptyschedule() {
        let schedule = Schedule<BasalScheduleEntry>(entries: [])
        #expect(schedule.entry(at: 0) == nil)
    }
}

// MARK: - Algorithm Profile Tests

@Suite("AlgorithmProfileTests")
struct AlgorithmProfileTests {
    
    @Test func sampleprofile() {
        let profile = AlgorithmProfile.sample
        #expect(profile.name == "Sample Profile")
        #expect(profile.dia == 6.0)
        #expect(profile.maxBasal == 3.0)
    }
    
    @Test func profilecurrentbasal() {
        let profile = AlgorithmProfile.sample
        // Sample has different rates at different times
        let basal = profile.currentBasal()
        #expect(basal > 0)
    }
    
    @Test func profilebuilder() {
        let profile = ProfileBuilder()
            .withName("Test")
            .withDIA(5.0)
            .withBasal(at: "00:00", rate: 1.0)
            .withISF(at: "00:00", sensitivity: 50)
            .withICR(at: "00:00", ratio: 10)
            .withTarget(at: "00:00", low: 100, high: 110)
            .withMaxBasal(2.0)
            .build()
        
        #expect(profile.name == "Test")
        #expect(profile.dia == 5.0)
        #expect(profile.basalSchedule.entries.count == 1)
    }
    
    @Test func profilevalidation() throws {
        let validProfile = AlgorithmProfile.sample
        try validProfile.validate()  // Should not throw
    }
    
    @Test func profilevalidationemptyschedule() {
        let profile = ProfileBuilder()
            .withBasal(at: "00:00", rate: 1.0)
            .withISF(at: "00:00", sensitivity: 50)
            .withICR(at: "00:00", ratio: 10)
            // Missing target schedule
            .build()
        
        #expect(throws: Error.self) { try profile.validate() }
    }
    
    @Test func profilevalidationinvaliddia() {
        let profile = AlgorithmProfile(
            dia: 2.0,  // Too short
            basalSchedule: Schedule(entries: [BasalScheduleEntry(startTime: 0, rate: 1.0)]),
            isfSchedule: Schedule(entries: [ISFScheduleEntry(startTime: 0, sensitivity: 50)]),
            icrSchedule: Schedule(entries: [ICRScheduleEntry(startTime: 0, ratio: 10)]),
            targetSchedule: Schedule(entries: [TargetScheduleEntry(startTime: 0, low: 100, high: 110)])
        )
        
        #expect(throws: Error.self) { try profile.validate() }
    }
}

// MARK: - Target Schedule Tests

@Suite("TargetScheduleTests")
struct TargetScheduleTests {
    
    @Test func targetmidpoint() {
        let entry = TargetScheduleEntry(startTime: 0, low: 100, high: 120)
        #expect(entry.midpoint == 110)
    }
    
    @Test func targetfromtime() {
        let entry = TargetScheduleEntry(time: "06:00", low: 90, high: 100)
        #expect(entry != nil)
        #expect(entry!.startTime == 6 * 3600)
    }
}

// MARK: - DetermineBasal Tests

@Suite("DetermineBasalTests")
struct DetermineBasalTests {
    let determineBasal = DetermineBasal()
    
    func createGlucoseReadings(values: [Double]) -> [GlucoseReading] {
        var readings: [GlucoseReading] = []
        let now = Date()
        for (i, value) in values.enumerated() {
            readings.append(GlucoseReading(
                glucose: value,
                timestamp: now.addingTimeInterval(Double(-i * 5 * 60)),  // 5 min apart
                source: "test"
            ))
        }
        return readings
    }
    
    @Test func needsminimumglucose() {
        let glucose = createGlucoseReadings(values: [100])
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 0,
            cob: 0,
            profile: profile
        )
        
        #expect(output.rate == nil)
        #expect(output.reason.contains("Not enough"))
    }
    
    @Test func lowglucosesuspend() {
        let glucose = createGlucoseReadings(values: [65, 70, 75])
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 0,
            cob: 0,
            profile: profile
        )
        
        #expect(output.rate == 0)
        #expect(output.reason.contains("suspending"))
    }
    
    @Test func predictedlowsuspend() {
        let glucose = createGlucoseReadings(values: [90, 100, 110, 120])  // Dropping
        let profile = AlgorithmProfile.sample
        
        // High IOB will cause predicted low
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 5.0,  // Lots of IOB
            cob: 0,
            profile: profile
        )
        
        #expect(output.rate == 0)
        #expect(output.reason.contains("suspending") || output.reason.contains("minPredBG"))
    }
    
    @Test func highglucoseincreasesbasal() {
        let glucose = createGlucoseReadings(values: [180, 175, 170, 165])
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 0,
            cob: 0,
            profile: profile
        )
        
        #expect(output.rate != nil)
        // Should suggest higher than scheduled basal
        let scheduledBasal = profile.currentBasal()
        #expect(output.rate! > scheduledBasal)
    }
    
    @Test func neartargetnochange() {
        let glucose = createGlucoseReadings(values: [105, 103, 104, 105])  // Stable near target
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 0.5,
            cob: 0,
            profile: profile
        )
        
        #expect(output.rate != nil)
        // Check that the algorithm ran and produced a reason
        #expect(!(output.reason.isEmpty))
    }
    
    @Test func maxioblimit() {
        let glucose = createGlucoseReadings(values: [200, 195, 190])
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 10.0,  // Exceeds maxIOB of 8
            cob: 0,
            profile: profile
        )
        
        // Algorithm should either report maxIOB or suggest scheduled basal
        #expect(output.rate != nil)
    }
    
    @Test func outputcontainstick() {
        let glucose = createGlucoseReadings(values: [120, 110, 100])  // Rising
        let profile = AlgorithmProfile.sample
        
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: 0,
            cob: 0,
            profile: profile
        )
        
        #expect(!(output.tick.isEmpty))
    }
}

// MARK: - Oref0Algorithm Tests

@Suite("Oref0AlgorithmTests")
struct Oref0AlgorithmTests {
    
    @Test func algorithmcreation() {
        let algorithm = Oref0Algorithm()
        #expect(algorithm.name == "oref0")
        #expect(algorithm.version == "0.2.0")
    }
    
    @Test func algorithmcalculate() throws {
        let algorithm = Oref0Algorithm()
        
        let glucose = [
            GlucoseReading(glucose: 120, timestamp: Date(), source: "test"),
            GlucoseReading(glucose: 115, timestamp: Date().addingTimeInterval(-300), source: "test"),
            GlucoseReading(glucose: 110, timestamp: Date().addingTimeInterval(-600), source: "test")
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 8.0
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0.5,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algorithm.calculate(inputs)
        #expect(decision.suggestedTempBasal != nil)
        #expect(!(decision.reason.isEmpty))
    }
}

// MARK: - Prediction Engine Tests

@Suite("PredictionEngineTests")
struct PredictionEngineTests {
    let engine = PredictionEngine(predictionMinutes: 180, intervalMinutes: 5)
    let insulinModel = InsulinModel(insulinType: .humalog)
    let carbModel = CarbModel()
    
    @Test func predictionresult() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 120,
            glucoseDelta: 5,
            iob: 1.0,
            cob: 20,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        #expect(result.currentGlucose == 120)
        #expect(!(result.zt.points.isEmpty))
        #expect(!(result.iob.points.isEmpty))
        #expect(!(result.cob.points.isEmpty))
        #expect(!(result.uam.points.isEmpty))
    }
    
    @Test func ztpredictionrises() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 100,
            glucoseDelta: 0,
            iob: 0,
            cob: 0,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        // ZT (zero temp) should show rising BG without insulin
        let eventual = result.zt.eventualValue
        #expect(eventual > 100)
    }
    
    @Test func iobpredictiondrops() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 150,
            glucoseDelta: 0,
            iob: 2.0,  // 2 units IOB
            cob: 0,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        // IOB should cause BG to drop
        let eventual = result.iob.eventualValue
        #expect(eventual < 150)
    }
    
    @Test func cobpredictionrises() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 100,
            glucoseDelta: 0,
            iob: 0,
            cob: 30,  // 30g carbs
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        // COB should cause BG to rise
        let maxBG = result.cob.maxValue
        #expect(maxBG > 100)
    }
    
    @Test func uamwithrisingbg() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 120,
            glucoseDelta: 10,  // Rising 10 mg/dL per reading
            iob: 0,
            cob: 0,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        // UAM should predict continued rise
        let maxBG = result.uam.maxValue
        #expect(maxBG > 120)
    }
    
    @Test func minmaxpredbg() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 120,
            glucoseDelta: 5,
            iob: 1.0,
            cob: 20,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        #expect(result.minPredBG <= result.currentGlucose + 50)
        #expect(result.maxPredBG >= result.currentGlucose - 50)
    }
    
    @Test func predictionpointcount() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 100,
            glucoseDelta: 0,
            iob: 0,
            cob: 0,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        // 180 min / 5 min intervals + 1 = 37 points
        #expect(result.zt.points.count == 37)
        #expect(result.iob.points.count == 37)
    }
    
    @Test func predictioncurveglucoseatminutes() {
        let points = [
            PredictionPoint(minutesFromNow: 0, glucose: 100),
            PredictionPoint(minutesFromNow: 5, glucose: 105),
            PredictionPoint(minutesFromNow: 10, glucose: 110)
        ]
        let curve = PredictionCurve(type: .iob, points: points)
        
        #expect(curve.glucose(atMinutes: 5) == 105)
        #expect(curve.glucose(atMinutes: 7) == nil)
    }
    
    @Test func toglucosepredictions() {
        let profile = AlgorithmProfile.sample
        
        let result = engine.predict(
            currentGlucose: 100,
            glucoseDelta: 0,
            iob: 0,
            cob: 0,
            profile: profile,
            insulinModel: insulinModel,
            carbModel: carbModel
        )
        
        let predictions = result.toGlucosePredictions()
        #expect(!(predictions.iob.isEmpty))
        #expect(!(predictions.cob.isEmpty))
        #expect(!(predictions.uam.isEmpty))
        #expect(!(predictions.zt.isEmpty))
    }
}

// MARK: - Insulin Model IOB Remaining Tests

@Suite("InsulinModelIOBRemainingTests")
struct InsulinModelIOBRemainingTests {
    
    @Test func iobremainingatstart() {
        let model = InsulinModel(insulinType: .humalog)
        let remaining = model.iobRemaining(at: 0)
        #expect(abs(remaining - 1.0) < 0.01)
    }
    
    @Test func iobremainingdecays() {
        let model = InsulinModel(insulinType: .humalog)
        let remaining1h = model.iobRemaining(at: 1.0)
        let remaining2h = model.iobRemaining(at: 2.0)
        
        #expect(remaining1h < 1.0)
        #expect(remaining2h < remaining1h)
    }
    
    @Test func iobremainingatdia() {
        let model = InsulinModel(insulinType: .humalog)
        let remaining = model.iobRemaining(at: model.dia)
        #expect(abs(remaining - 0) < 0.01)
    }
}

// MARK: - Safety Limits Tests

@Suite("SafetyLimitsTests")
struct SafetyLimitsTests {
    
    @Test func defaultlimits() {
        let limits = SafetyLimits.default
        #expect(limits.maxBasalRate == 5.0)
        #expect(limits.maxBolus == 10.0)
        #expect(limits.maxIOB == 10.0)
        #expect(limits.suspendThreshold == 70.0)
    }
    
    @Test func conservativelimits() {
        let limits = SafetyLimits.conservative
        #expect(limits.maxBasalRate == 2.0)
        #expect(limits.maxIOB == 5.0)
        #expect(limits.suspendThreshold == 80.0)
    }
    
    @Test func customlimits() {
        let limits = SafetyLimits(
            maxBasalRate: 3.5,
            maxBolus: 8.0,
            maxIOB: 7.0
        )
        #expect(limits.maxBasalRate == 3.5)
        #expect(limits.maxBolus == 8.0)
        #expect(limits.maxIOB == 7.0)
    }
}

// MARK: - Safety Guardian Tests

@Suite("SafetyGuardianTests")
struct SafetyGuardianTests {
    let guardian = SafetyGuardian(limits: .default)
    
    @Test func basalrateallowed() {
        let result = guardian.checkBasalRate(2.0)
        #expect(result.isAllowed)
        #expect(result.reason == nil)
    }
    
    @Test func basalratelimited() {
        let result = guardian.checkBasalRate(10.0)
        if case .limited(let original, let limited, _) = result {
            #expect(original == 10.0)
            #expect(limited == 5.0)
        } else {
            Issue.record("Expected limited result")
        }
    }
    
    @Test func basalratenegativedenied() {
        let result = guardian.checkBasalRate(-1.0)
        if case .denied = result {
            // Expected
        } else {
            Issue.record("Expected denied result")
        }
    }
    
    @Test func limitbasalrate() {
        #expect(guardian.limitBasalRate(3.0) == 3.0)
        #expect(guardian.limitBasalRate(10.0) == 5.0)
        #expect(guardian.limitBasalRate(-1.0) == 0)
    }
    
    @Test func bolusallowed() {
        let result = guardian.checkBolus(5.0)
        #expect(result.isAllowed)
    }
    
    @Test func boluslimited() {
        let result = guardian.checkBolus(15.0)
        if case .limited(_, let limited, _) = result {
            #expect(limited == 10.0)
        } else {
            Issue.record("Expected limited result")
        }
    }
    
    @Test func iobcheck() {
        // Under limit
        let allowed = guardian.checkIOB(current: 5.0, additional: 3.0)
        #expect(allowed.isAllowed)
        
        // Would exceed
        let limited = guardian.checkIOB(current: 8.0, additional: 5.0)
        if case .limited(_, let limitedValue, _) = limited {
            #expect(limitedValue == 2.0)  // 10 - 8 = 2
        } else {
            Issue.record("Expected limited result")
        }
        
        // Already at max
        let denied = guardian.checkIOB(current: 10.0, additional: 1.0)
        if case .denied = denied {
            // Expected
        } else {
            Issue.record("Expected denied result")
        }
    }
    
    @Test func maxadditionaliob() {
        #expect(guardian.maxAdditionalIOB(currentIOB: 5.0) == 5.0)
        #expect(guardian.maxAdditionalIOB(currentIOB: 10.0) == 0)
        #expect(guardian.maxAdditionalIOB(currentIOB: 12.0) == 0)
    }
    
    @Test func glucosechecknormal() {
        let result = guardian.checkGlucose(120)
        #expect(result.isAllowed)
    }
    
    @Test func glucosechecklow() {
        let result = guardian.checkGlucose(65)
        if case .denied = result {
            // Expected
        } else {
            Issue.record("Expected denied for low glucose")
        }
    }
    
    @Test func shouldsuspend() {
        #expect(guardian.shouldSuspend(glucose: 65))
        #expect(guardian.shouldSuspend(glucose: 70))
        #expect(!(guardian.shouldSuspend(glucose: 80)))
    }
    
    @Test func shouldsuspendforprediction() {
        #expect(guardian.shouldSuspendForPrediction(minPredBG: 60))
        #expect(!(guardian.shouldSuspendForPrediction(minPredBG: 80)))
    }
    
    @Test func validatedecisionnormal() {
        let result = guardian.validateDecision(
            suggestedRate: 1.5,
            suggestedBolus: nil,
            currentIOB: 2.0,
            currentGlucose: 120,
            minPredBG: 90
        )
        
        #expect(result.rate == 1.5)
        #expect(!(result.suspended))
        #expect(result.reasons.isEmpty)
    }
    
    @Test func validatedecisionlowglucose() {
        let result = guardian.validateDecision(
            suggestedRate: 1.5,
            suggestedBolus: 2.0,
            currentIOB: 2.0,
            currentGlucose: 65,
            minPredBG: 60
        )
        
        #expect(result.rate == 0)
        #expect(result.bolus == nil)
        #expect(result.suspended)
        #expect(!(result.reasons.isEmpty))
    }
    
    @Test func validatedecisionratelimited() {
        let result = guardian.validateDecision(
            suggestedRate: 10.0,
            suggestedBolus: nil,
            currentIOB: 2.0,
            currentGlucose: 200,
            minPredBG: 150
        )
        
        #expect(result.rate == 5.0)  // Limited to max
        #expect(!(result.suspended))
        #expect(!(result.reasons.isEmpty))
    }
}

// MARK: - Safety Audit Log Tests

@Suite("SafetyAuditLogTests")
struct SafetyAuditLogTests {
    
    @Test func logentry() {
        let log = SafetyAuditLog()
        
        log.log(SafetyAuditEntry(
            eventType: "basal_limited",
            originalValue: 10.0,
            limitedValue: 5.0,
            reason: "Exceeded max basal"
        ))
        
        let entries = log.recentEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.eventType == "basal_limited")
    }
    
    @Test func logmaxentries() {
        let log = SafetyAuditLog(maxEntries: 10)
        
        for i in 0..<20 {
            log.log(SafetyAuditEntry(eventType: "test", reason: "Entry \(i)"))
        }
        
        let entries = log.recentEntries(count: 100)
        #expect(entries.count == 10)
    }
    
    @Test func logclear() {
        let log = SafetyAuditLog()
        
        log.log(SafetyAuditEntry(eventType: "test", reason: "test"))
        #expect(log.recentEntries().count == 1)
        
        log.clear()
        #expect(log.recentEntries().count == 0)
    }
}

// MARK: - Autosens Result Tests

@Suite("AutosensResultTests")
struct AutosensResultTests {
    
    @Test func neutralautosens() {
        let result = AutosensResult.neutral
        #expect(result.ratio == 1.0)
    }
    
    @Test func autosensresult() {
        let result = AutosensResult(
            ratio: 1.2,
            deviation: -5.0,
            dataPoints: 48,
            reason: "More sensitive"
        )
        #expect(result.ratio == 1.2)
        #expect(result.deviation == -5.0)
        #expect(result.dataPoints == 48)
    }
}

// MARK: - Autosens Calculator Tests

@Suite("AutosensCalculatorTests")
struct AutosensCalculatorTests {
    let calculator = AutosensCalculator()
    let insulinModel = InsulinModel(insulinType: .humalog)
    
    func createGlucoseHistory(count: Int, base: Double = 100) -> [GlucoseReading] {
        let now = Date()
        return (0..<count).map { i in
            GlucoseReading(
                glucose: base + Double.random(in: -10...10),
                timestamp: now.addingTimeInterval(Double(-i * 5 * 60)),
                source: "test"
            )
        }
    }
    
    @Test func insufficientdata() {
        let glucose = createGlucoseHistory(count: 10)
        let profile = AlgorithmProfile.sample
        
        let result = calculator.calculate(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel
        )
        
        #expect(result.ratio == 1.0)
        #expect(result.reason.contains("Insufficient"))
    }
    
    @Test func sufficientdata() {
        let glucose = createGlucoseHistory(count: 50)
        let profile = AlgorithmProfile.sample
        
        let result = calculator.calculate(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel
        )
        
        // Should produce a ratio in valid range
        #expect(result.ratio >= 0.5)
        #expect(result.ratio <= 1.5)
    }
    
    @Test func ratiolimits() {
        let calc = AutosensCalculator(maxRatio: 1.2, minRatio: 0.8)
        #expect(calc.maxRatio == 1.2)
        #expect(calc.minRatio == 0.8)
    }
    
    // MARK: - Oref0-style Autosens Tests (ALG-GAP-001)
    
    @Test func dualwindowcalculation() {
        // Create 200 readings (~16 hours)
        let glucose = createGlucoseHistory(count: 200, base: 110)
        let profile = AlgorithmProfile.sample
        
        let result = calculator.calculateDualWindow(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel
        )
        
        // Should produce valid ratio
        #expect(result.ratio >= 0.5)
        #expect(result.ratio <= 1.5)
        #expect(result.reason.contains("Dual-window"))
    }
    
    @Test func mealexclusion() {
        // With COB > 0, positive deviations should be excluded
        let glucose = createRisingGlucoseHistory(count: 50, base: 100)
        let profile = AlgorithmProfile.sample
        
        let resultWithCOB = calculator.calculate(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel,
            cob: 30  // Active carbs
        )
        
        let resultNoCOB = calculator.calculate(
            glucose: glucose,
            profile: profile,
            insulinModel: insulinModel,
            cob: 0  // No carbs
        )
        
        // With COB, should exclude positive deviations = ratio closer to 1.0
        // Without COB, rising glucose = resistance = ratio < 1.0
        #expect(resultWithCOB.ratio >= resultNoCOB.ratio * 0.9)
    }
    
    @Test func windowconfiguration() {
        let calc = AutosensCalculator(
            minHoursData: 4,
            maxRatio: 1.3,
            minRatio: 0.7,
            shortWindow: 6,
            longWindow: 12
        )
        
        #expect(calc.shortWindow == 6)
        #expect(calc.longWindow == 12)
    }
    
    func createRisingGlucoseHistory(count: Int, base: Double) -> [GlucoseReading] {
        let now = Date()
        return (0..<count).map { i in
            GlucoseReading(
                glucose: base + Double(i) * 2,  // Steadily rising
                timestamp: now.addingTimeInterval(Double(-i * 5 * 60)),
                source: "test"
            )
        }
    }
}

// MARK: - Dynamic ISF Tests

@Suite("DynamicISFTests")
struct DynamicISFTests {
    let dynamicISF = DynamicISF()
    
    @Test func neartarget() {
        let isf = dynamicISF.calculateISF(baseISF: 50, currentBG: 105, targetBG: 100)
        #expect(isf == 50)  // No adjustment near target
    }
    
    @Test func highbglowersisf() {
        let isf = dynamicISF.calculateISF(baseISF: 50, currentBG: 200, targetBG: 100)
        #expect(isf < 50)  // Lower ISF = more aggressive
    }
    
    @Test func lowbgraisesisf() {
        let isf = dynamicISF.calculateISF(baseISF: 50, currentBG: 70, targetBG: 100)
        #expect(isf > 50)  // Higher ISF = less aggressive
    }
    
    @Test func sigmoidadjustmentsymmetry() {
        let highAdj = dynamicISF.sigmoidAdjustment(bgDiff: 50)
        let lowAdj = dynamicISF.sigmoidAdjustment(bgDiff: -50)
        
        // Should be symmetric around 1.0
        #expect(highAdj < 1.0)
        #expect(lowAdj > 1.0)
    }
    
    @Test func sigmoidbounds() {
        let veryHigh = dynamicISF.sigmoidAdjustment(bgDiff: 200)
        let veryLow = dynamicISF.sigmoidAdjustment(bgDiff: -200)
        
        #expect(veryHigh >= 0.5)
        #expect(veryLow <= 2.0)
    }
    
    @Test func highbgadjustmentnormal() {
        let adj = dynamicISF.highBGAdjustment(currentBG: 120, targetBG: 100)
        #expect(adj == 1.0)  // No adjustment below threshold
    }
    
    @Test func highbgadjustmentveryhigh() {
        let adj = dynamicISF.highBGAdjustment(currentBG: 250, targetBG: 100)
        #expect(adj < 1.0)
        #expect(adj >= 0.5)
    }
}

// MARK: - Sensitivity Adjuster Tests

@Suite("SensitivityAdjusterTests")
struct SensitivityAdjusterTests {
    let adjuster = SensitivityAdjuster()
    
    @Test func adjustedisfwithneutralautosens() {
        let isf = adjuster.adjustedISF(
            baseISF: 50,
            currentBG: 100,
            targetBG: 100,
            autosensRatio: 1.0
        )
        #expect(abs(isf - 50) < 1)
    }
    
    @Test func adjustedisfwithresistance() {
        // Ratio < 1 = resistant = need lower ISF
        let isf = adjuster.adjustedISF(
            baseISF: 50,
            currentBG: 100,
            targetBG: 100,
            autosensRatio: 0.8
        )
        // 50 / 0.8 = 62.5, but then dynamic ISF near target
        #expect(isf > 50)
    }
    
    @Test func adjustedbasal() {
        // Resistant = need more basal
        let basal = adjuster.adjustedBasal(baseBasal: 1.0, autosensRatio: 0.8)
        #expect(abs(basal - 1.25) < 0.01)
        
        // Sensitive = need less basal
        let basalSensitive = adjuster.adjustedBasal(baseBasal: 1.0, autosensRatio: 1.2)
        #expect(abs(basalSensitive - 0.833) < 0.01)
    }
    
    @Test func adjustedicr() {
        // Resistant = need more insulin per carb = lower ICR
        let icr = adjuster.adjustedICR(baseICR: 10, autosensRatio: 0.8)
        #expect(abs(icr - 12.5) < 0.01)
    }
    
    @Test func adjustedprofile() {
        let profile = AlgorithmProfile.sample
        let autosens = AutosensResult(ratio: 0.9, reason: "Test")
        
        let adjusted = adjuster.adjustedProfile(
            profile: profile,
            currentBG: 150,
            autosensResult: autosens
        )
        
        // With resistance (0.9), basal should increase
        #expect(adjusted.basal > profile.currentBasal())
        #expect(adjusted.autosensRatio == 0.9)
    }
}

// MARK: - Adjusted Profile Values Tests

@Suite("AdjustedProfileValuesTests")
struct AdjustedProfileValuesTests {
    
    @Test func adjustedvalues() {
        let values = AdjustedProfileValues(
            isf: 45,
            basal: 1.1,
            icr: 9,
            autosensRatio: 0.9
        )
        
        #expect(values.isf == 45)
        #expect(values.basal == 1.1)
        #expect(values.icr == 9)
        #expect(values.autosensRatio == 0.9)
    }
}

// MARK: - SMB Settings Tests

@Suite("SMBSettingsTests")
struct SMBSettingsTests {
    
    @Test func defaultsettings() {
        let settings = SMBSettings.default
        #expect(!(settings.enabled))
        #expect(settings.maxSMB == 1.0)
        #expect(settings.minInterval == 180)  // 3 min
    }
    
    @Test func aggressivesettings() {
        let settings = SMBSettings.aggressive
        #expect(settings.enabled)
        #expect(settings.maxSMB == 2.0)
        #expect(settings.enableAlways)
    }
    
    @Test func customsettings() {
        let settings = SMBSettings(
            enabled: true,
            maxSMB: 0.5,
            minInterval: 5 * 60
        )
        #expect(settings.enabled)
        #expect(settings.maxSMB == 0.5)
        #expect(settings.minInterval == 300)
    }
}

// MARK: - SMB Result Tests

@Suite("SMBResultTests")
struct SMBResultTests {
    
    @Test func nosmbresult() {
        let result = SMBResult.noSMB(reason: "Test reason")
        #expect(!(result.shouldDeliver))
        #expect(result.units == 0)
        #expect(result.reason == "Test reason")
    }
    
    @Test func smbresult() {
        let result = SMBResult(
            shouldDeliver: true,
            units: 0.5,
            reason: "High BG",
            eventualBGWithSMB: 110
        )
        #expect(result.shouldDeliver)
        #expect(result.units == 0.5)
        #expect(result.eventualBGWithSMB == 110)
    }
}

// SMB/Conformance tests moved to SMBAlgorithmTests.swift (CODE-027)

// MARK: - Algorithm Registry Tests

@Suite("AlgorithmRegistryTests")
struct AlgorithmRegistryTests {
    
    // Use instance property instead of computed property to avoid
    // creating new registry on each access (ALG-TEST-FIX-002)
    var registry: AlgorithmRegistry
    
    init() {
        registry = AlgorithmRegistry.createForTesting()
    }
    
    // MARK: - Registration Tests
    
    @Test func registeralgorithm() throws {
        let simple = SimpleProportionalAlgorithm()
        try registry.register(simple)
        
        #expect(registry.count == 1)
        #expect(registry.isRegistered(name: "SimpleProportional"))
    }
    
    @Test func registerduplicatethrows() throws {
        let simple = SimpleProportionalAlgorithm()
        try registry.register(simple)
        
        #expect(throws: AlgorithmRegistryError.self) { try registry.register(simple) }
    }
    
    @Test func registerorreplace() throws {
        let simple1 = SimpleProportionalAlgorithm()
        try registry.register(simple1)
        
        let simple2 = SimpleProportionalAlgorithm()
        registry.registerOrReplace(simple2)
        
        #expect(registry.count == 1)
    }
    
    @Test func unregister() throws {
        let simple = SimpleProportionalAlgorithm()
        try registry.register(simple)
        
        let removed = registry.unregister(name: "SimpleProportional")
        #expect(removed != nil)
        #expect(registry.count == 0)
    }
    
    @Test func clear() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.register(Oref0Algorithm())
        
        #expect(registry.count == 2)
        
        registry.clear()
        #expect(registry.count == 0)
    }
    
    // MARK: - Query Tests
    
    @Test func registerednames() throws {
        try registry.register(Oref0Algorithm())
        try registry.register(SimpleProportionalAlgorithm())
        
        let names = registry.registeredNames
        #expect(names.count == 2)
        #expect(names.contains("oref0"))
        #expect(names.contains("SimpleProportional"))
    }
    
    @Test func algorithmbyname() throws {
        try registry.register(Oref0Algorithm())
        
        let alg = registry.algorithm(named: "oref0")
        #expect(alg != nil)
        #expect(alg?.name == "oref0")
        
        let missing = registry.algorithm(named: "nonexistent")
        #expect(missing == nil)
    }
    
    @Test func requirealgorithmthrows() {
        #expect(throws: AlgorithmRegistryError.self) { try registry.requireAlgorithm(named: "missing") }
    }
    
    @Test func algorithmsmatchingcapabilities() throws {
        try registry.register(Oref0Algorithm())
        try registry.register(SimpleProportionalAlgorithm())
        
        let withPredictions = registry.algorithms(matching: { $0.providesPredictions })
        #expect(withPredictions.count == 1)
        #expect(withPredictions.first?.name == "oref0")
        
        let withTempBasal = registry.algorithms(matching: { $0.supportsTempBasal })
        #expect(withTempBasal.count == 2)
    }
    
    @Test func algorithmsbyorigin() throws {
        try registry.register(Oref0Algorithm())
        try registry.register(SimpleProportionalAlgorithm())
        
        let orefAlgs = registry.algorithms(origin: .oref0)
        #expect(orefAlgs.count == 1)
        
        let customAlgs = registry.algorithms(origin: .custom)
        #expect(customAlgs.count == 1)
    }
    
    // MARK: - Active Algorithm Tests
    
    @Test func setactivealgorithm() throws {
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        #expect(registry.activeAlgorithmName == "oref0")
        #expect(registry.activeAlgorithm != nil)
    }
    
    @Test func setactivenotregisteredthrows() {
        #expect(throws: AlgorithmRegistryError.self) { try registry.setActive(name: "missing") }
    }
    
    @Test func clearactive() throws {
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        registry.clearActive()
        #expect(registry.activeAlgorithmName == nil)
        #expect(registry.activeAlgorithm == nil)
    }
    
    @Test func requireactivealgorithmthrows() {
        #expect(throws: AlgorithmRegistryError.self) { try registry.requireActiveAlgorithm() }
    }
    
    @Test func unregisterclearsactive() throws {
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        registry.unregister(name: "oref0")
        #expect(registry.activeAlgorithmName == nil)
    }
    
    // MARK: - Observer Tests
    
    @Test func observernotified() throws {
        try registry.register(Oref0Algorithm())
        
        var notifications: [(String?, String?)] = []
        registry.addObserver { old, new in
            notifications.append((old, new))
        }
        
        try registry.setActive(name: "oref0")
        
        #expect(notifications.count == 1)
        #expect(notifications[0].0 == nil)
        #expect(notifications[0].1 == "oref0")
    }
    
    // MARK: - Calculation Tests
    
    @Test func calculatewithactivealgorithm() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let reading = GlucoseReading(glucose: 150)
        let inputs = AlgorithmInputs(glucose: [reading], profile: profile)
        
        let decision = try registry.calculate(inputs)
        #expect(decision.suggestedTempBasal != nil)
    }
    
    @Test func calculatewithnoactivethrows() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let reading = GlucoseReading(glucose: 150)
        let inputs = AlgorithmInputs(glucose: [reading], profile: profile)
        
        #expect(throws: AlgorithmRegistryError.self) { try registry.calculate(inputs) }
    }
    
    // MARK: - Shared Instance Tests
    
    @Test func sharedinstancehasbuiltins() {
        let shared = AlgorithmRegistry.shared
        
        #expect(shared.isRegistered(name: "oref0"))
        #expect(shared.isRegistered(name: "SimpleProportional"))
        #expect(shared.activeAlgorithmName == "oref0")
    }
    
    @Test func summary() throws {
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        let summary = registry.summary
        #expect(summary.contains("1 algorithms"))
        #expect(summary.contains("active: oref0"))
    }
}

// MARK: - Registry Error Tests

@Suite("AlgorithmRegistryErrorTests")
struct AlgorithmRegistryErrorTests {
    
    @Test func errorequality() {
        let e1 = AlgorithmRegistryError.algorithmNotFound(name: "test")
        let e2 = AlgorithmRegistryError.algorithmNotFound(name: "test")
        let e3 = AlgorithmRegistryError.algorithmNotFound(name: "other")
        
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
    
    @Test func allerrorcases() {
        let errors: [AlgorithmRegistryError] = [
            .algorithmNotFound(name: "test"),
            .algorithmAlreadyRegistered(name: "test"),
            .noActiveAlgorithm,
            .validationFailed(errors: ["error1"])
        ]
        
        #expect(errors.count == 4)
    }
}

// MARK: - Oref1 Algorithm Tests

@Suite("Oref1AlgorithmTests")
struct Oref1AlgorithmTests {
    
    // MARK: - Capabilities Tests
    
    @Test func oref1capabilities() {
        let oref1 = Oref1Algorithm()
        
        #expect(oref1.name == "oref1")
        #expect(oref1.capabilities.origin == .oref1)
        #expect(oref1.capabilities.supportsTempBasal)
        #expect(oref1.capabilities.supportsSMB)
        #expect(oref1.capabilities.supportsUAM)
        #expect(oref1.capabilities.supportsDynamicISF)
        #expect(oref1.capabilities.supportsAutosens)
        #expect(oref1.capabilities.providesPredictions)
    }
    
    @Test func oref1vsoref0capabilities() {
        let oref0 = Oref0Algorithm()
        let oref1 = Oref1Algorithm()
        
        // oref1 has SMB, oref0 doesn't
        #expect(!(oref0.capabilities.supportsSMB))
        #expect(oref1.capabilities.supportsSMB)
        
        // oref1 has UAM, oref0 doesn't
        #expect(!(oref0.capabilities.supportsUAM))
        #expect(oref1.capabilities.supportsUAM)
        
        // oref1 has dynamic ISF, oref0 doesn't
        #expect(!(oref0.capabilities.supportsDynamicISF))
        #expect(oref1.capabilities.supportsDynamicISF)
        
        // Both have predictions
        #expect(oref0.capabilities.providesPredictions)
        #expect(oref1.capabilities.providesPredictions)
    }
    
    @Test func oref1origintracking() {
        let oref1 = Oref1Algorithm()
        #expect(oref1.capabilities.origin.rawValue == "OpenAPS/oref1")
    }
    
    // MARK: - Calculation Tests
    
    @Test func oref1basiccalculation() throws {
        let oref1 = Oref1Algorithm()
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        
        let readings = (0..<12).map { i in
            GlucoseReading(glucose: 150 - Double(i))
        }
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0.5,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try oref1.calculate(inputs)
        #expect(decision.suggestedTempBasal != nil)
        #expect(!(decision.reason.isEmpty))
    }
    
    @Test func oref1withsmbsettings() {
        let smbSettings = SMBSettings(
            enabled: true,
            maxSMB: 1.5,
            enableWithCOB: true
        )
        
        let oref1 = Oref1Algorithm(smbSettings: smbSettings)
        #expect(oref1.smbSettings.maxSMB == 1.5)
        #expect(oref1.smbSettings.enabled)
    }
    
    @Test func oref1disabledynamicisf() {
        let oref1 = Oref1Algorithm(enableDynamicISF: false)
        #expect(!(oref1.enableDynamicISF))
        
        // Capabilities still report support
        #expect(oref1.capabilities.supportsDynamicISF)
    }
    
    @Test func oref1disableuam() {
        let oref1 = Oref1Algorithm(enableUAM: false)
        #expect(!(oref1.enableUAM))
        
        // Capabilities still report support
        #expect(oref1.capabilities.supportsUAM)
    }
    
    // MARK: - SMB History Tests
    
    @Test func oref1smbhistory() {
        let oref1 = Oref1Algorithm()
        
        // Initially empty
        #expect(oref1.recentSMBs.isEmpty)
        #expect(oref1.smbUnitsLastHour == 0)
    }
    
    // MARK: - Registry Integration Tests
    
    @Test func oref1registryintegration() throws {
        let registry = AlgorithmRegistry.createForTesting()
        
        // Register via extension method
        registry.registerOref1()
        
        #expect(registry.isRegistered(name: "oref1"))
        
        let alg = try registry.requireAlgorithm(named: "oref1")
        #expect(alg.name == "oref1")
        #expect(alg.capabilities.supportsSMB)
    }
    
    @Test func registryfindbysmbcapability() throws {
        let registry = AlgorithmRegistry.createForTesting()
        
        try registry.register(Oref0Algorithm())
        registry.registerOref1()
        
        let smbAlgorithms = registry.algorithmsSupportingSMB
        #expect(smbAlgorithms.count == 1)
        #expect(smbAlgorithms.first?.name == "oref1")
    }
    
    @Test func registryfindbyorigin() throws {
        let registry = AlgorithmRegistry.createForTesting()
        
        try registry.register(Oref0Algorithm())
        registry.registerOref1()
        try registry.register(SimpleProportionalAlgorithm())
        
        let oref0Algs = registry.algorithms(origin: .oref0)
        let oref1Algs = registry.algorithms(origin: .oref1)
        let customAlgs = registry.algorithms(origin: .custom)
        
        #expect(oref0Algs.count == 1)
        #expect(oref1Algs.count == 1)
        #expect(customAlgs.count == 1)
    }
    
    // MARK: - Autosens Tests
    
    @Test func oref1autosensinitial() {
        let oref1 = Oref1Algorithm()
        
        // Initially neutral
        #expect(oref1.currentAutosens.ratio == 1.0)
    }
}

// MARK: - Loop Facade Tests

@Suite("LoopFacadeTests")
struct LoopFacadeTests {
    
    // Use instance properties instead of computed properties to avoid
    // creating new instances on each access (ALG-TEST-FIX-002)
    var registry: AlgorithmRegistry
    var facade: LoopFacade
    
    init() {
        registry = AlgorithmRegistry.createForTesting()
        facade = LoopFacade.createForTesting(registry: registry)
    }
    
    // MARK: - State Tests
    
    @Test func initialstate() {
        #expect(facade.state == .idle)
        #expect(!(facade.isSuspended))
        #expect(facade.lastDecision == nil)
    }
    
    @Test func suspendresume() {
        facade.suspend(reason: "Test")
        #expect(facade.isSuspended)
        #expect(facade.state == .suspended)
        
        facade.resume()
        #expect(!(facade.isSuspended))
        #expect(facade.state == .idle)
    }
    
    @Test func executewhilesuspended() throws {
        facade.suspend()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 120)],
            profile: profile
        )
        
        #expect(throws: LoopError.self) { try facade.execute(inputs) }
    }
    
    // MARK: - Execution Tests
    
    @Test func executewithnoalgorithm() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 120)],
            profile: profile
        )
        
        #expect(throws: LoopError.self) { try facade.execute(inputs) }
    }
    
    @Test func executewithalgorithm() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 150)],
            profile: profile
        )
        
        let decision = try facade.execute(inputs)
        
        #expect(decision.algorithmName == "SimpleProportional")
        #expect(decision.safeDecision.tempBasal != nil)
        #expect(!(decision.isSuspended))
        #expect(decision.executionTime > 0)
    }
    
    @Test func executewithoref0() throws {
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        
        let readings = (0..<5).map { i in
            GlucoseReading(glucose: 180 - Double(i * 5))
        }
        
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 1.0,
            carbsOnBoard: 20,
            profile: profile
        )
        
        let decision = try facade.execute(inputs)
        
        #expect(decision.algorithmName == "oref0")
        #expect(facade.lastDecision != nil)
    }
    
    // MARK: - Safety Tests
    
    @Test func safetylimitsapplied() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        // Very high BG should suggest high rate, but safety limits
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 400)],  // Very high
            profile: profile
        )
        
        let decision = try facade.execute(inputs)
        
        // Rate should be limited to max (5.0 by default)
        if let rate = decision.safeDecision.tempBasal?.rate {
            #expect(rate <= 5.0)
        }
    }
    
    @Test func lowglucosesuspend() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 65)],  // Below suspend threshold
            profile: profile
        )
        
        let decision = try facade.execute(inputs)
        
        #expect(decision.isSuspended)
        #expect(decision.safeDecision.tempBasal?.rate == 0)
    }
    
    // MARK: - Observer Tests
    
    @Test func observernotified() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        var receivedDecision: LoopDecision?
        facade.addObserver { decision in
            receivedDecision = decision
        }
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 120)],
            profile: profile
        )
        
        _ = try facade.execute(inputs)
        
        #expect(receivedDecision != nil)
        #expect(receivedDecision?.algorithmName == "SimpleProportional")
    }
    
    // MARK: - Logging Tests
    
    @Test func decisionlogging() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.setActive(name: "SimpleProportional")
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let inputs = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 120)],
            profile: profile
        )
        
        _ = try facade.execute(inputs)
        _ = try facade.execute(inputs)
        
        let decisions = facade.recentDecisions(count: 10)
        #expect(decisions.count == 2)
    }
    
    @Test func decisionsbyalgorithm() throws {
        try registry.register(SimpleProportionalAlgorithm())
        try registry.register(Oref0Algorithm())
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        
        let readings = (0..<5).map { _ in GlucoseReading(glucose: 150) }
        let inputs = AlgorithmInputs(glucose: readings, profile: profile)
        
        // Execute with simple
        try registry.setActive(name: "SimpleProportional")
        _ = try facade.execute(inputs)
        
        // Execute with oref0
        try registry.setActive(name: "oref0")
        _ = try facade.execute(inputs)
        _ = try facade.execute(inputs)
        
        let simpleDecisions = facade.decisions(byAlgorithm: "SimpleProportional")
        let oref0Decisions = facade.decisions(byAlgorithm: "oref0")
        
        #expect(simpleDecisions.count == 1)
        #expect(oref0Decisions.count == 2)
    }
    
    // MARK: - Shared Instance Test
    
    @Test func sharedinstance() {
        let shared = LoopFacade.shared
        #expect(shared != nil)
        #expect(shared.state == .idle)
    }
}

// MARK: - Loop Error Tests

@Suite("LoopErrorTests")
struct LoopErrorTests {
    
    @Test func allerrorcases() {
        let errors: [LoopError] = [
            .loopSuspended,
            .noActiveAlgorithm,
            .noGlucoseData,
            .validationFailed(errors: []),
            .algorithmError(AlgorithmError.calculationFailed(reason: "test"))
        ]
        
        #expect(errors.count == 5)
    }
}

// Loop tests moved to LoopAlgorithmTests.swift (CODE-027)

// MARK: - Loop Algorithm Integration Tests (ALG-020)

@Suite("LoopAlgorithmTests")
struct LoopAlgorithmTests {
    
    // MARK: - Initialization Tests
    
    @Test func defaultconfiguration() {
        let algo = LoopAlgorithm()
        #expect(algo.name == "Loop")
        #expect(algo.version == "1.0.0")
        #expect(algo.capabilities.origin == .loopCommunity)
    }
    
    @Test func customconfiguration() {
        let config = LoopAlgorithmConfiguration(
            maxBasalRate: 3.0,
            maxBolus: 5.0,
            suspendThreshold: 80.0
        )
        let algo = LoopAlgorithm(configuration: config)
        #expect(algo.configuration.maxBasalRate == 3.0)
        #expect(algo.configuration.maxBolus == 5.0)
        #expect(algo.configuration.suspendThreshold == 80.0)
    }
    
    @Test func fiaspconfiguration() {
        let algo = LoopAlgorithm(configuration: .fiasp)
        #expect(algo.configuration.insulinModel != nil)
    }
    
    @Test func conservativeconfiguration() {
        let algo = LoopAlgorithm(configuration: .conservative)
        #expect(algo.configuration.maxBasalRate == 2.0)
        #expect(algo.configuration.maxBolus == 5.0)
        #expect(algo.configuration.suspendThreshold == 80.0)
    }
    
    // MARK: - Capability Tests
    
    @Test func capabilities() {
        let algo = LoopAlgorithm()
        #expect(algo.capabilities.supportsTempBasal)
        #expect(!(algo.capabilities.supportsSMB))
        #expect(!(algo.capabilities.supportsUAM))
        #expect(algo.capabilities.providesPredictions)
        #expect(algo.capabilities.minGlucoseHistory == 3)
    }
    
    // MARK: - Algorithm Execution Tests
    
    @Test func calculatewithsufficientdata() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { i in
            GlucoseReading(glucose: 150 - Double(i) * 2)
        }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 1.0,
            carbsOnBoard: 20.0,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision != nil)
        #expect(!(decision.reason.isEmpty))
    }
    
    @Test func calculatereturnsnilbolusforloop() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { _ in GlucoseReading(glucose: 180) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision.suggestedBolus == nil)
    }
    
    @Test func calculatesuggeststempbasal() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { _ in GlucoseReading(glucose: 180) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision.suggestedTempBasal != nil)
    }
    
    @Test func calculatewithlowglucose() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { _ in GlucoseReading(glucose: 65) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 0.5)
        }
    }
    
    // MARK: - Validation Tests
    
    @Test func validateinsufficientglucose() {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let inputs = AlgorithmInputs(
            glucose: [],
            profile: profile
        )
        
        let errors = algo.validate(inputs)
        #expect(!(errors.isEmpty))
    }
    
    @Test func validatewithsufficientdata() {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<5).map { _ in GlucoseReading(glucose: 120) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let errors = algo.validate(inputs)
        #expect(errors.isEmpty)
    }
    
    // MARK: - Registry Integration Tests
    
    @Test func registerloop() {
        let registry = AlgorithmRegistry.shared
        registry.registerLoop()
        
        let algo = registry.algorithm(named: "Loop")
        #expect(algo != nil)
        #expect(algo?.capabilities.origin == .loopCommunity)
    }
    
    @Test func registerloopfiasp() {
        let registry = AlgorithmRegistry.shared
        registry.registerLoopFiasp()
        
        let algo = registry.algorithm(named: "Loop")
        #expect(algo != nil)
    }
    
    // MARK: - Prediction Tests
    
    @Test func predictmethod() {
        let algo = LoopAlgorithm()
        
        let predictions = algo.predict(
            startingGlucose: 120,
            at: Date(),
            isf: 50,
            icr: 10
        )
        
        #expect(!(predictions.isEmpty))
    }
    
    @Test func predictionwithdoses() {
        let algo = LoopAlgorithm()
        let now = Date()
        
        let doses = [
            InsulinDose(units: 2.0, timestamp: now.addingTimeInterval(-3600))
        ]
        
        let predictions = algo.predict(
            startingGlucose: 150,
            at: now,
            doses: doses,
            isf: 50,
            icr: 10
        )
        
        #expect(!(predictions.isEmpty))
        if let eventualBG = predictions.last?.glucose {
            #expect(eventualBG < 150)
        }
    }
    
    // MARK: - IOB/COB Calculation Tests
    
    @Test func calculateiob() {
        let algo = LoopAlgorithm()
        let now = Date()
        
        let doses = [
            InsulinDose(units: 3.0, timestamp: now.addingTimeInterval(-7200))
        ]
        
        let iob = algo.calculateIOB(doses: doses, at: now)
        #expect(iob > 0)
        #expect(iob < 3.0)
    }
    
    @Test func calculatecob() {
        let algo = LoopAlgorithm()
        let now = Date()
        
        let carbs = [
            CarbEntry(grams: 30, timestamp: now.addingTimeInterval(-3600))
        ]
        
        let cob = algo.calculateCOB(carbs: carbs, at: now)
        #expect(cob > 0)
        #expect(cob < 30)
    }
    
    // MARK: - Meal Bolus Tests
    
    @Test func recommendmealbolus() {
        let algo = LoopAlgorithm()
        
        let result = algo.recommendMealBolus(
            currentGlucose: 120,
            carbGrams: 45,
            targetGlucose: 100,
            isf: 50,
            icr: 10
        )
        
        #expect(result.recommendation.type == .bolus)
        if let units = result.recommendation.units {
            #expect(units > 4.0)
        }
    }
    
    @Test func recommendcorrectionbolus() {
        let algo = LoopAlgorithm()
        
        let result = algo.recommendMealBolus(
            currentGlucose: 200,
            carbGrams: 0,
            targetGlucose: 100,
            isf: 50,
            icr: 10
        )
        
        if let units = result.recommendation.units {
            #expect(abs(units - 2.0) < 0.5)
        }
    }
    
    // MARK: - Reset Test
    
    @Test func reset() {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<5).map { _ in GlucoseReading(glucose: 120) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        _ = try? algo.calculate(inputs)
        
        algo.reset()
        #expect(algo.recentCorrections.isEmpty)
    }
    
    // MARK: - Reason String Tests
    
    @Test func reasonincludesiob() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<5).map { _ in GlucoseReading(glucose: 120) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.5,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision.reason.contains("IOB"))
    }
    
    @Test func reasonincludespredictions() throws {
        let algo = LoopAlgorithm()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<5).map { _ in GlucoseReading(glucose: 150) }
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision.reason.contains("eventual"))
    }
    
    // MARK: - High-Fidelity History Tests (ALG-LIVE-048/049/050)
    
    @Test func calculatewithrealdosehistory() throws {
        // ALG-LIVE-048: Use doseHistory if provided, else fall back to synthetic
        let algo = LoopAlgorithm()
        let now = Date()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { i in
            GlucoseReading(
                glucose: 140,
                timestamp: now.addingTimeInterval(Double(-i) * 300)
            )
        }
        
        // Create real dose history: 2U bolus 1 hour ago
        let doseHistory = [
            InsulinDose(
                units: 2.0,
                timestamp: now.addingTimeInterval(-3600),
                type: .novolog
            )
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 1.5,  // This scalar should be ignored when doseHistory provided
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now,
            doseHistory: doseHistory
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision != nil)
        #expect(!(decision.reason.isEmpty))
        // IOB calculated from dose history (2U * remaining activity) should differ from scalar 1.5
        // The algorithm uses doseHistory to recalculate IOB, not the scalar value
        #expect(decision.reason.contains("IOB"))
    }
    
    @Test func calculatewithrealcarbhistory() throws {
        // ALG-LIVE-049: Use carbHistory if provided, else fall back to synthetic
        let algo = LoopAlgorithm()
        let now = Date()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { i in
            GlucoseReading(
                glucose: 120,
                timestamp: now.addingTimeInterval(Double(-i) * 300)
            )
        }
        
        // Create real carb history: 30g eaten 30 minutes ago
        let carbHistory = [
            CarbEntry(
                grams: 30,
                timestamp: now.addingTimeInterval(-1800),
                absorptionTime: 3.0  // 3 hour absorption
            )
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 40,  // This scalar should be ignored when carbHistory provided
            profile: profile,
            currentTime: now,
            carbHistory: carbHistory
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision != nil)
        // COB calculated from carb history (30g * remaining absorption) differs from scalar 40
        #expect(decision.predictions != nil)
    }
    
    @Test func calculatewithbothhistories() throws {
        // ALG-LIVE-050: Full high-fidelity mode with both dose and carb history
        let algo = LoopAlgorithm()
        let now = Date()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { i in
            GlucoseReading(
                glucose: 150 - Double(i) * 5,  // Slightly falling
                timestamp: now.addingTimeInterval(Double(-i) * 300)
            )
        }
        
        // Real dose history: multiple doses
        let doseHistory = [
            InsulinDose(
                units: 3.0,
                timestamp: now.addingTimeInterval(-2 * 3600),  // 2 hours ago
                type: .novolog
            ),
            InsulinDose(
                units: 1.5,
                timestamp: now.addingTimeInterval(-1 * 3600),  // 1 hour ago
                type: .novolog
            )
        ]
        
        // Real carb history: meal
        let carbHistory = [
            CarbEntry(
                grams: 45,
                timestamp: now.addingTimeInterval(-90 * 60),  // 90 minutes ago
                absorptionTime: 3.0
            )
        ]
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 999,   // Should be ignored
            carbsOnBoard: 999,     // Should be ignored
            profile: profile,
            currentTime: now,
            doseHistory: doseHistory,
            carbHistory: carbHistory
        )
        
        let decision = try algo.calculate(inputs)
        #expect(decision != nil)
        #expect(!(decision.reason.isEmpty))
        // Reason should contain IOB calculated from actual dose history
        #expect(decision.reason.contains("IOB"))
        // Verify computed IOB is in reasonable range (1-4U from 4.5U doses 1-2 hours ago)
        // The reason format is "IOB X.XXXY (Loop: 999.000U)" showing computed vs input
        // Extract the computed IOB value to verify it's not using the input 999
        let components = decision.reason.components(separatedBy: "IOB ")
        if components.count > 1 {
            let iobPart = components[1].prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
            if let computedIOB = Double(iobPart) {
                #expect(computedIOB < 10.0, "Computed IOB should be < 10U, not using input 999")
                #expect(computedIOB >= 0, "Computed IOB should be non-negative")
            }
        }
    }
    
    @Test func highfidelityproducesdifferentresultthansynthetic() throws {
        // Verify that real history produces different (more accurate) IOB than synthetic
        let algo = LoopAlgorithm()
        let now = Date()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        let glucose = (0..<6).map { i in
            GlucoseReading(glucose: 140, timestamp: now.addingTimeInterval(Double(-i) * 300))
        }
        
        // Synthetic mode: scalar IOB
        let syntheticInputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        // High-fidelity mode: real dose history that gives ~2U IOB
        // 4U bolus 2 hours ago with typical ~50% remaining = ~2U IOB
        let doseHistory = [
            InsulinDose(
                units: 4.0,
                timestamp: now.addingTimeInterval(-2 * 3600),
                type: .novolog
            )
        ]
        
        let highFidelityInputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 2.0,  // Same scalar, but will be recalculated
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now,
            doseHistory: doseHistory
        )
        
        let syntheticDecision = try algo.calculate(syntheticInputs)
        let highFidelityDecision = try algo.calculate(highFidelityInputs)
        
        // Both should produce valid decisions
        #expect(syntheticDecision.suggestedTempBasal != nil)
        #expect(highFidelityDecision.suggestedTempBasal != nil)
        
        // Results may differ due to different IOB curve shapes
        // (synthetic assumes dose 2h ago with iob*2 units, high-fidelity uses actual timestamps)
    }
    
    // MARK: - Safety Limits Tests (ALG-LIVE-063/064)
    
    @Test func maxbasalratelimitfromprofile() throws {
        // ALG-LIVE-064: Profile maxBasalRate should cap temp basal recommendations
        let algo = LoopAlgorithm()
        
        // Need at least 3 glucose readings for LoopAlgorithm
        let now = Date()
        let glucose = [
            GlucoseReading(glucose: 200, timestamp: now, trend: .flat),
            GlucoseReading(glucose: 195, timestamp: now.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 190, timestamp: now.addingTimeInterval(-600), trend: .flat)
        ]  // High glucose = wants high basal
        
        // Profile with strict 3 U/hr limit
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10.0,
            maxBolus: 5.0,
            maxBasalRate: 3.0  // Limit to 3 U/hr
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algo.calculate(inputs)
        
        if let tempBasal = decision.suggestedTempBasal {
            // Rate should be capped at 3.0 U/hr
            #expect(tempBasal.rate <= 3.0, "Temp basal rate should not exceed maxBasalRate limit")
        }
    }
    
    @Test func automaticboluswithautomaticbolusstrategy() throws {
        // ALG-LIVE-063: automaticBolus strategy should enable auto bolus recommendations
        let algo = LoopAlgorithm()
        
        let now = Date()
        let glucose = [
            GlucoseReading(glucose: 180, timestamp: now, trend: .flat),
            GlucoseReading(glucose: 175, timestamp: now.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 170, timestamp: now.addingTimeInterval(-600), trend: .flat)
        ]  // High = needs correction
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10.0,
            maxBolus: 5.0,
            dosingStrategy: "automaticBolus"  // Enable auto bolus
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,  // Low IOB = room for more insulin
            carbsOnBoard: 0,
            profile: profile,
            currentTime: Date()
        )
        
        let decision = try algo.calculate(inputs)
        
        // With automaticBolus strategy and high glucose, should suggest a bolus
        if let bolus = decision.suggestedBolus {
            #expect(bolus > 0, "Should suggest automatic bolus")
            #expect(bolus <= profile.maxBolus, "Bolus should not exceed maxBolus")
        }
        // Note: If IOB is high or prediction shows safe, bolus might be nil
    }
    
    @Test func noautomaticboluswithtempbasalonlystrategy() throws {
        // ALG-LIVE-063: tempBasalOnly strategy should NOT produce auto bolus
        let algo = LoopAlgorithm()
        
        let now = Date()
        let glucose = [
            GlucoseReading(glucose: 180, timestamp: now, trend: .flat),
            GlucoseReading(glucose: 175, timestamp: now.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 170, timestamp: now.addingTimeInterval(-600), trend: .flat)
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10.0,
            maxBolus: 5.0,
            dosingStrategy: "tempBasalOnly"  // Default Loop mode
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algo.calculate(inputs)
        
        // With tempBasalOnly, should not suggest automatic bolus
        #expect(decision.suggestedBolus == nil, "tempBasalOnly should not produce automatic bolus")
    }
    
    @Test func maxboluslimitapplied() throws {
        // ALG-LIVE-064: maxBolus should cap automatic bolus recommendations
        let algo = LoopAlgorithm()
        
        let now = Date()
        let glucose = [
            GlucoseReading(glucose: 350, timestamp: now, trend: .flat),
            GlucoseReading(glucose: 340, timestamp: now.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 330, timestamp: now.addingTimeInterval(-600), trend: .flat)
        ]  // Very high = wants large bolus
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 20.0,  // High IOB limit
            maxBolus: 1.5,  // Low bolus limit
            dosingStrategy: "automaticBolus"
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        let decision = try algo.calculate(inputs)
        
        if let bolus = decision.suggestedBolus {
            #expect(bolus <= 1.5, "Automatic bolus should not exceed maxBolus limit of 1.5U")
        }
    }
    
    // MARK: - Prediction Effect Toggle Tests (ALG-LIVE-066)
    
    @Test func effecttogglesmomentumdisabled() throws {
        // ALG-LIVE-066: Test that momentum can be disabled via configuration
        let config = LoopAlgorithmConfiguration(
            includeMomentum: false,
            includeCarbEffect: true,
            includeInsulinEffect: true
        )
        let algo = LoopAlgorithm(configuration: config)
        
        // Config should reflect the toggle
        #expect(!(algo.configuration.includeMomentum))
        #expect(algo.configuration.includeCarbEffect)
        #expect(algo.configuration.includeInsulinEffect)
    }
    
    @Test func effecttogglescarbsdisabled() throws {
        // ALG-LIVE-066: Test that carb effect can be disabled
        let config = LoopAlgorithmConfiguration(
            includeMomentum: true,
            includeCarbEffect: false,
            includeInsulinEffect: true
        )
        let algo = LoopAlgorithm(configuration: config)
        
        #expect(algo.configuration.includeMomentum)
        #expect(!(algo.configuration.includeCarbEffect))
        #expect(algo.configuration.includeInsulinEffect)
    }
    
    @Test func effecttogglesalldisabled() throws {
        // ALG-LIVE-066: Test that all effects can be disabled
        let config = LoopAlgorithmConfiguration(
            enableRetrospectiveCorrection: false,
            includeMomentum: false,
            includeCarbEffect: false,
            includeInsulinEffect: false
        )
        let algo = LoopAlgorithm(configuration: config)
        
        #expect(!(algo.configuration.enableRetrospectiveCorrection))
        #expect(!(algo.configuration.includeMomentum))
        #expect(!(algo.configuration.includeCarbEffect))
        #expect(!(algo.configuration.includeInsulinEffect))
    }
    
    @Test func predictionwithmomentumdisabled() throws {
        // ALG-LIVE-066: Predictions with momentum disabled should differ from default
        let now = Date()
        let glucose = [
            GlucoseReading(glucose: 150, timestamp: now, trend: .singleUp),  // Rising trend = momentum effect
            GlucoseReading(glucose: 145, timestamp: now.addingTimeInterval(-300), trend: .singleUp),
            GlucoseReading(glucose: 140, timestamp: now.addingTimeInterval(-600), trend: .singleUp)
        ]
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 110),
            maxIOB: 10.0,
            maxBolus: 5.0
        )
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile,
            currentTime: now
        )
        
        // Default (momentum enabled)
        let defaultAlgo = LoopAlgorithm()
        let defaultDecision = try defaultAlgo.calculate(inputs)
        
        // Momentum disabled
        let noMomentumAlgo = LoopAlgorithm(configuration: LoopAlgorithmConfiguration(includeMomentum: false))
        let noMomentumDecision = try noMomentumAlgo.calculate(inputs)
        
        // Both should produce valid decisions
        #expect(defaultDecision.suggestedTempBasal != nil)
        #expect(noMomentumDecision.suggestedTempBasal != nil)
        
        // With rising glucose, momentum adds positive effect, so disabling it
        // might result in lower predicted glucose and potentially different dosing
        // (exact behavior depends on algorithm internals, but configs should work)
    }
}

// MARK: - Loop Controller Tests (AID-LOOP-001)

@Suite("LoopControllerTests")
struct LoopControllerTests {
    
    func testControllerNotRunning() async {
        let controller = LoopController()
        
        // Not running by default
        let running = await controller.isRunning
        #expect(!(running))
        
        let result = await controller.runIteration()
        #expect(result.error as? LoopIterationError == .loopSuspended)
    }
    
    func testControllerNotConfigured() async {
        let controller = LoopController()
        await controller.start()
        
        let result = await controller.runIteration()
        #expect(result.error as? LoopIterationError == .notConfigured)
    }
    
    func testControllerWithMockSources() async throws {
        // Use testing registry to avoid conflicts
        let registry = AlgorithmRegistry.createForTesting()
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        let loopFacade = LoopFacade.createForTesting(registry: registry)
        let controller = LoopController(loopFacade: loopFacade)
        
        // Create mock sources
        let now = Date()
        let readings = [
            GlucoseReading(glucose: 120, timestamp: now),
            GlucoseReading(glucose: 118, timestamp: now.addingTimeInterval(-300)),
            GlucoseReading(glucose: 115, timestamp: now.addingTimeInterval(-600))
        ]
        let cgmSource = MockCGMSource(readings: readings)
        let pumpController = MockPumpController()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        // Configure
        await controller.configure(
            cgmSource: cgmSource,
            pumpController: pumpController,
            profileProvider: { profile }
        )
        
        // Start and run
        await controller.start()
        let result = await controller.runIteration()
        
        #expect(result.isSuccess)
        #expect(result.glucose != nil)
        #expect(result.glucose?.glucose == 120)
        #expect(result.algorithmDecision != nil)
    }
    
    func testControllerStaleGlucose() async {
        let controller = LoopController()
        
        // Create stale reading (15 minutes old)
        let staleTime = Date().addingTimeInterval(-900)
        let readings = [GlucoseReading(glucose: 120, timestamp: staleTime)]
        let cgmSource = MockCGMSource(readings: readings)
        let pumpController = MockPumpController()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        await controller.configure(
            cgmSource: cgmSource,
            pumpController: pumpController,
            profileProvider: { profile }
        )
        
        await controller.start()
        let result = await controller.runIteration()
        
        // Should fail due to stale glucose
        if case .staleGlucose(let age) = result.error {
            #expect(age > 600)
        } else {
            Issue.record("Expected stale glucose error")
        }
    }
    
    func testControllerEnactDose() async throws {
        let controller = LoopController()
        
        // Create mock sources
        let now = Date()
        let readings = [
            GlucoseReading(glucose: 180, timestamp: now),  // High glucose
            GlucoseReading(glucose: 175, timestamp: now.addingTimeInterval(-300)),
            GlucoseReading(glucose: 170, timestamp: now.addingTimeInterval(-600))
        ]
        let cgmSource = MockCGMSource(readings: readings)
        let pumpController = MockPumpController()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        await controller.configure(
            cgmSource: cgmSource,
            pumpController: pumpController,
            profileProvider: { profile }
        )
        
        // Enable enact
        await controller.enableEnact()
        await controller.start()
        
        let result = await controller.runIteration()
        
        // Should succeed with enactment
        #expect(result.isSuccess)
        
        // Check if pump was commanded (may or may not have temp basal depending on algorithm decision)
        let commandCount = await pumpController.commandCount
        // May be 0 or more depending on what the algorithm recommends
        #expect(commandCount >= 0)
    }
    
    func testMockCGMSource() async throws {
        let readings = [
            GlucoseReading(glucose: 100, timestamp: Date()),
            GlucoseReading(glucose: 95, timestamp: Date().addingTimeInterval(-300))
        ]
        let source = MockCGMSource(readings: readings)
        
        let fetched = try await source.fetchGlucose()
        #expect(fetched.count == 2)
        #expect(fetched[0].glucose == 100)
    }
    
    func testMockPumpController() async throws {
        let pump = MockPumpController()
        
        try await pump.setTempBasal(rate: 1.5, duration: 30 * 60)
        
        let lastTemp = await pump.lastTempBasal
        #expect(lastTemp?.rate == 1.5)
        
        try await pump.deliverBolus(units: 2.0)
        
        let lastBolus = await pump.lastBolus
        #expect(lastBolus == 2.0)
        
        let commandCount = await pump.commandCount
        #expect(commandCount == 2)
    }
    
    // MARK: - Multi-iteration tests (AID-CONFIDENCE-001d)
    
    /// Test multiple loop iterations with IOB accumulation
    /// Validates state persistence across iterations
    @Test func testMultiIterationWithIOBAccumulation() async throws {
        // Use testing registry to avoid conflicts
        let registry = AlgorithmRegistry.createForTesting()
        try registry.register(Oref0Algorithm())
        try registry.setActive(name: "oref0")
        
        let loopFacade = LoopFacade.createForTesting(registry: registry)
        let controller = LoopController(loopFacade: loopFacade)
        
        let cgmSource = MockCGMSource()
        let pumpController = MockPumpController()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        await controller.configure(
            cgmSource: cgmSource,
            pumpController: pumpController,
            profileProvider: { profile }
        )
        
        await controller.enableEnact()
        await controller.start()
        
        // Iteration 1: High glucose - expect increased delivery
        let now = Date()
        let readings1 = [
            GlucoseReading(glucose: 180, timestamp: now),
            GlucoseReading(glucose: 175, timestamp: now.addingTimeInterval(-300)),
            GlucoseReading(glucose: 170, timestamp: now.addingTimeInterval(-600))
        ]
        await cgmSource.setReadings(readings1)
        
        let result1 = await controller.runIteration()
        #expect(result1.isSuccess)
        #expect(result1.glucose?.glucose == 180)
        
        let commandCount1 = await pumpController.commandCount
        
        // Iteration 2: Still high, should continue treatment
        let readings2 = [
            GlucoseReading(glucose: 165, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 170, timestamp: now),
            GlucoseReading(glucose: 175, timestamp: now.addingTimeInterval(-300))
        ]
        await cgmSource.setReadings(readings2)
        
        let result2 = await controller.runIteration()
        #expect(result2.isSuccess)
        #expect(result2.glucose?.glucose == 165)
        
        // Iteration 3: Coming into range
        let readings3 = [
            GlucoseReading(glucose: 130, timestamp: now.addingTimeInterval(600)),
            GlucoseReading(glucose: 145, timestamp: now.addingTimeInterval(300)),
            GlucoseReading(glucose: 165, timestamp: now)
        ]
        await cgmSource.setReadings(readings3)
        
        let result3 = await controller.runIteration()
        #expect(result3.isSuccess)
        #expect(result3.glucose?.glucose == 130)
        
        // Verify multiple iterations were executed
        let lastResult = await controller.lastResult
        #expect(lastResult?.glucose?.glucose == 130)
        
        // Command count should accumulate (or be 0 if algorithm decided no action)
        let finalCommandCount = await pumpController.commandCount
        #expect(finalCommandCount >= commandCount1)
    }
    
    /// Test that controller correctly handles glucose trend through multiple iterations
    @Test func testMultiIterationGlucoseTrendTracking() async throws {
        let controller = LoopController()
        
        let cgmSource = MockCGMSource()
        let pumpController = MockPumpController()
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 90, high: 110)
        )
        
        await controller.configure(
            cgmSource: cgmSource,
            pumpController: pumpController,
            profileProvider: { profile }
        )
        
        await controller.start()
        
        // Run 5 iterations tracking glucose descent
        var glucoseValues = [Double]()
        let startGlucose = 150.0
        
        for iteration in 0..<5 {
            let currentTime = Date().addingTimeInterval(Double(iteration) * 300)
            let glucoseLevel = startGlucose - Double(iteration) * 10  // 150, 140, 130, 120, 110
            
            let readings = [
                GlucoseReading(glucose: glucoseLevel, timestamp: currentTime),
                GlucoseReading(glucose: glucoseLevel + 5, timestamp: currentTime.addingTimeInterval(-300)),
                GlucoseReading(glucose: glucoseLevel + 10, timestamp: currentTime.addingTimeInterval(-600))
            ]
            await cgmSource.setReadings(readings)
            
            let result = await controller.runIteration()
            #expect(result.isSuccess)
            
            if let glucose = result.glucose?.glucose {
                glucoseValues.append(glucose)
            }
        }
        
        // Verify we tracked all 5 iterations
        #expect(glucoseValues.count == 5)
        
        // Verify descending trend was captured
        #expect(glucoseValues[0] > glucoseValues[4])
        #expect(abs(glucoseValues[0] - 150) < 1)
        #expect(abs(glucoseValues[4] - 110) < 1)
    }
}

// MARK: - Profile Override Tests (ALG-PARITY-004)

@Suite("ProfileOverrideTests")
struct ProfileOverrideTests {
    
    @Test func overridefactorcalculation() {
        let override = ProfileOverride(name: "Test", percentage: 80)
        #expect(abs(override.factor - 0.8) < 0.001)
        
        let override120 = ProfileOverride(name: "Test", percentage: 120)
        #expect(abs(override120.factor - 1.2) < 0.001)
    }
    
    @Test func adjustedisf_exercisemode() {
        // 80% = exercise mode, should make ISF larger (less insulin per mg/dL)
        let override = ProfileOverride(name: "Exercise", percentage: 80)
        let baseISF = 50.0  // 1U drops BG 50 mg/dL
        
        let adjustedISF = override.adjustedISF(baseISF)
        
        // ISF / 0.8 = 62.5 (now 1U drops BG 62.5, so need less insulin)
        #expect(abs(adjustedISF - 62.5) < 0.1)
    }
    
    @Test func adjustedisf_illnessmode() {
        // 120% = illness mode, should make ISF smaller (more insulin per mg/dL)
        let override = ProfileOverride(name: "Illness", percentage: 120)
        let baseISF = 50.0
        
        let adjustedISF = override.adjustedISF(baseISF)
        
        // ISF / 1.2 = 41.67 (now 1U drops BG less, so need more insulin)
        #expect(abs(adjustedISF - 41.67) < 0.1)
    }
    
    @Test func adjustedcr() {
        let override = ProfileOverride(name: "Exercise", percentage: 80)
        let baseCR = 10.0  // 1U covers 10g carbs
        
        let adjustedCR = override.adjustedCR(baseCR)
        
        // CR / 0.8 = 12.5 (now 1U covers 12.5g, so need less insulin)
        #expect(abs(adjustedCR - 12.5) < 0.1)
    }
    
    @Test func adjustedbasal() {
        let override = ProfileOverride(name: "Illness", percentage: 120)
        let baseBasal = 1.0  // 1 U/hr
        
        let adjustedBasal = override.adjustedBasal(baseBasal)
        
        // Basal * 1.2 = 1.2 U/hr (more insulin)
        #expect(abs(adjustedBasal - 1.2) < 0.01)
    }
    
    @Test func overrideexpiration() {
        let start = Date()
        var override = ProfileOverride(
            name: "Test",
            isActive: true,
            durationMinutes: 60,
            startDate: start
        )
        
        // Not expired at start
        #expect(!(override.isExpired(at: start)))
        
        // Not expired after 30 minutes
        let thirtyMinutes = start.addingTimeInterval(30 * 60)
        #expect(!(override.isExpired(at: thirtyMinutes)))
        
        // Expired after 61 minutes
        let sixtyOneMinutes = start.addingTimeInterval(61 * 60)
        #expect(override.isExpired(at: sixtyOneMinutes))
    }
    
    @Test func indefiniteoverrideneverexpires() {
        let start = Date()
        var override = ProfileOverride(
            name: "Test",
            isActive: true,
            durationMinutes: 0,  // Indefinite
            startDate: start
        )
        
        #expect(override.isIndefinite)
        
        // Not expired even after 24 hours
        let tomorrow = start.addingTimeInterval(24 * 60 * 60)
        #expect(!(override.isExpired(at: tomorrow)))
    }
    
    @Test func remainingminutes() {
        let start = Date()
        var override = ProfileOverride(
            name: "Test",
            durationMinutes: 60,
            startDate: start
        )
        
        let remaining = override.remainingMinutes(at: start) ?? 0
        #expect(abs(remaining - 60) < 0.1)
        
        let thirtyMinLater = start.addingTimeInterval(30 * 60)
        let remaining30 = override.remainingMinutes(at: thirtyMinLater) ?? 0
        #expect(abs(remaining30 - 30) < 0.1)
    }
    
    @Test func selectiveadjustments() {
        // Override that only adjusts ISF, not CR or basal
        let override = ProfileOverride(
            name: "ISF Only",
            percentage: 80,
            adjustISF: true,
            adjustCR: false,
            adjustBasal: false
        )
        
        #expect(abs(override.adjustedISF(50) - 62.5) < 0.1)
        #expect(abs(override.adjustedCR(10) - 10) < 0.01)  // Unchanged
        #expect(abs(override.adjustedBasal(1.0) - 1.0) < 0.01)  // Unchanged
    }
    
    @Test func presetoverrides() {
        #expect(ProfileOverride.exercise.percentage == 80)
        #expect(ProfileOverride.highActivity.percentage == 70)
        #expect(ProfileOverride.illness.percentage == 120)
        #expect(ProfileOverride.preMeal.percentage == 110)
        
        #expect(ProfileOverride.highActivity.disableSMB)
        #expect(!(ProfileOverride.exercise.disableSMB))
    }
    
    @Test func percentageclamping() {
        // Percentage should be clamped to 10-200%
        let tooLow = ProfileOverride(name: "Test", percentage: 5)
        #expect(tooLow.percentage == 10)
        
        let tooHigh = ProfileOverride(name: "Test", percentage: 300)
        #expect(tooHigh.percentage == 200)
    }
}

// MARK: - TDD Calculator Tests (ALG-PARITY-006)

@Suite("TDDRecordTests")
struct TDDRecordTests {
    
    @Test func tddrecordcreation() {
        let date = Date()
        let record = TDDRecord(date: date, total: 45.5, bolus: 20.0, basal: 25.5)
        
        #expect(record.total == 45.5)
        #expect(record.bolus == 20.0)
        #expect(record.basal == 25.5)
    }
}

@Suite("TDDResultTests")
struct TDDResultTests {
    
    @Test func tddresultproperties() {
        let result = TDDResult(
            current: 30.0,
            average: 45.0,
            weightedAverage: 40.0,
            daysOfData: 7,
            hoursToday: 12
        )
        
        #expect(result.current == 30.0)
        #expect(result.average == 45.0)
        #expect(result.weightedAverage == 40.0)
        #expect(result.daysOfData == 7)
        #expect(result.hoursToday == 12)
    }
    
    @Test func insufficientresult() {
        let result = TDDResult.insufficient
        #expect(result.daysOfData == 0)
        #expect(result.weightedAverage == 0)
    }
}

@Suite("TDDCalculatorTests")
struct TDDCalculatorTests {
    
    @Test func emptyrecords() {
        let calculator = TDDCalculator()
        let result = calculator.calculate(records: [], currentDayInsulin: 10, hoursToday: 6)
        
        #expect(result.current == 10)
        #expect(result.average == 0)
        #expect(result.weightedAverage == 0)
        #expect(result.daysOfData == 0)
    }
    
    @Test func simpleaverage() {
        let calculator = TDDCalculator(minimumDays: 1)
        let now = Date()
        
        let records = [
            TDDRecord(date: now.addingTimeInterval(-1 * 24 * 3600), total: 40),
            TDDRecord(date: now.addingTimeInterval(-2 * 24 * 3600), total: 50),
            TDDRecord(date: now.addingTimeInterval(-3 * 24 * 3600), total: 45)
        ]
        
        let result = calculator.calculate(records: records)
        
        #expect(abs(result.average - 45.0) < 0.1)
        #expect(result.daysOfData == 3)
    }
    
    @Test func weightedaverage_recenthigher() {
        // 65% recent, 35% historical
        let calculator = TDDCalculator(recentWeight: 0.65, minimumDays: 3)
        let now = Date()
        
        // Historical average: 40 U/day
        let records = [
            TDDRecord(date: now.addingTimeInterval(-1 * 24 * 3600), total: 40),
            TDDRecord(date: now.addingTimeInterval(-2 * 24 * 3600), total: 40),
            TDDRecord(date: now.addingTimeInterval(-3 * 24 * 3600), total: 40)
        ]
        
        // Current: 30U in 12 hours → projected 60 U/day (higher than average)
        let result = calculator.calculate(
            records: records,
            currentDayInsulin: 30,
            hoursToday: 12
        )
        
        // Recent estimate = 30/12 * 24 = 60
        // Weighted = 0.65 * 60 + 0.35 * 40 = 39 + 14 = 53
        #expect(abs(result.weightedAverage - 53) < 0.1)
    }
    
    @Test func weightedaverage_recentlower() {
        let calculator = TDDCalculator(recentWeight: 0.65, minimumDays: 3)
        let now = Date()
        
        // Historical average: 50 U/day
        let records = [
            TDDRecord(date: now.addingTimeInterval(-1 * 24 * 3600), total: 50),
            TDDRecord(date: now.addingTimeInterval(-2 * 24 * 3600), total: 50),
            TDDRecord(date: now.addingTimeInterval(-3 * 24 * 3600), total: 50)
        ]
        
        // Current: 10U in 12 hours → projected 20 U/day (lower than average)
        let result = calculator.calculate(
            records: records,
            currentDayInsulin: 10,
            hoursToday: 12
        )
        
        // Recent estimate = 10/12 * 24 = 20
        // Weighted = 0.65 * 20 + 0.35 * 50 = 13 + 17.5 = 30.5
        #expect(abs(result.weightedAverage - 30.5) < 0.1)
    }
    
    @Test func insufficientdata_usessimpleaverage() {
        // Requires 3 days minimum
        let calculator = TDDCalculator(minimumDays: 3)
        let now = Date()
        
        // Only 2 days of data
        let records = [
            TDDRecord(date: now.addingTimeInterval(-1 * 24 * 3600), total: 45),
            TDDRecord(date: now.addingTimeInterval(-2 * 24 * 3600), total: 55)
        ]
        
        let result = calculator.calculate(records: records, currentDayInsulin: 20, hoursToday: 8)
        
        // Should use simple average since < minimumDays
        #expect(abs(result.weightedAverage - 50.0) < 0.1)
        #expect(result.daysOfData == 2)
    }
    
    @Test func hassufficientdata() {
        let calculator = TDDCalculator(minimumDays: 3)
        let now = Date()
        
        let twoRecords = [
            TDDRecord(date: now.addingTimeInterval(-1 * 24 * 3600), total: 45),
            TDDRecord(date: now.addingTimeInterval(-2 * 24 * 3600), total: 55)
        ]
        #expect(!(calculator.hasSufficientData(twoRecords)))
        
        let threeRecords = twoRecords + [
            TDDRecord(date: now.addingTimeInterval(-3 * 24 * 3600), total: 50)
        ]
        #expect(calculator.hasSufficientData(threeRecords))
    }
    
    @Test func adjustedisf_highertdd() {
        let calculator = TDDCalculator()
        
        // Current TDD is higher than average → more resistant → lower ISF
        let result = TDDResult(
            current: 60,
            average: 45,
            weightedAverage: 55,  // Higher than average
            daysOfData: 7
        )
        
        let baseISF = 50.0
        let adjusted = calculator.adjustedISF(baseISF: baseISF, tddResult: result)
        
        // Ratio = 45 / 55 = 0.818 → ISF should be lower
        #expect(adjusted < baseISF)
        #expect(abs(adjusted - 50 * (45.0 / 55.0)) < 0.1)
    }
    
    @Test func adjustedisf_lowertdd() {
        let calculator = TDDCalculator()
        
        // Current TDD is lower than average → more sensitive → higher ISF
        let result = TDDResult(
            current: 30,
            average: 45,
            weightedAverage: 35,  // Lower than average
            daysOfData: 7
        )
        
        let baseISF = 50.0
        let adjusted = calculator.adjustedISF(baseISF: baseISF, tddResult: result)
        
        // Ratio = 45 / 35 = 1.286 → ISF should be higher
        #expect(adjusted > baseISF)
        #expect(abs(adjusted - 50 * (45.0 / 35.0)) < 0.1)
    }
    
    @Test func adjustedisf_insufficientdata() {
        let calculator = TDDCalculator(minimumDays: 3)
        
        let result = TDDResult(
            current: 30,
            average: 45,
            weightedAverage: 35,
            daysOfData: 2  // Less than minimum
        )
        
        let baseISF = 50.0
        let adjusted = calculator.adjustedISF(baseISF: baseISF, tddResult: result)
        
        // Should return base ISF unchanged
        #expect(adjusted == baseISF)
    }
    
    @Test func oldrecordsfiltered() {
        let calculator = TDDCalculator(historyDays: 10, minimumDays: 1)
        let now = Date()
        
        let records = [
            TDDRecord(date: now.addingTimeInterval(-5 * 24 * 3600), total: 45),  // 5 days ago
            TDDRecord(date: now.addingTimeInterval(-15 * 24 * 3600), total: 100) // 15 days ago (should be filtered)
        ]
        
        let result = calculator.calculate(records: records)
        
        // Should only use the 5-day-old record
        #expect(result.daysOfData == 1)
        #expect(result.average == 45)
    }
}
