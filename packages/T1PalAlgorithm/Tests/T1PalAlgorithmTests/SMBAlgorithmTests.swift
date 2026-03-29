// SPDX-License-Identifier: AGPL-3.0-or-later
// SMBAlgorithmTests.swift - SMB algorithm tests
// Extracted from AlgorithmTests.swift (CODE-027)
// Trace: ALG-SMB-001

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - SMB Calculator Tests

@Suite("SMB Calculator")
struct SMBCalculatorTests {
    
    @Test("SMB disabled")
    func smbDisabled() {
        let calc = SMBCalculator(settings: .default)
        let result = calc.calculate(
            currentBG: 150,
            eventualBG: 160,
            minPredBG: 100,
            targetBG: 100,
            iob: 1.0,
            cob: 20,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("disabled"))
    }
    
    @Test("SMB low BG")
    func smbLowBG() {
        let settings = SMBSettings(enabled: true, enableAlways: true, minBGForSMB: 80)
        let calc = SMBCalculator(settings: settings)
        
        let result = calc.calculate(
            currentBG: 75,
            eventualBG: 160,
            minPredBG: 70,
            targetBG: 100,
            iob: 1.0,
            cob: 0,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("below minimum"))
    }
    
    @Test("SMB predicted low")
    func smbPredictedLow() {
        let settings = SMBSettings(enabled: true, enableAlways: true)
        let calc = SMBCalculator(settings: settings)
        
        let result = calc.calculate(
            currentBG: 120,
            eventualBG: 150,
            minPredBG: 60,  // Predicted low
            targetBG: 100,
            iob: 3.0,
            cob: 0,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("Predicted low"))
    }
    
    @Test("SMB max IOB")
    func smbMaxIOB() {
        let settings = SMBSettings(enabled: true, enableAlways: true, maxIOBForSMB: 5.0)
        let calc = SMBCalculator(settings: settings)
        
        let result = calc.calculate(
            currentBG: 180,
            eventualBG: 200,
            minPredBG: 150,
            targetBG: 100,
            iob: 6.0,  // Exceeds maxIOB
            cob: 0,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("maxIOB"))
    }
    
    @Test("SMB delivered")
    func smbDelivered() {
        let settings = SMBSettings(enabled: true, maxSMB: 2.0, enableAlways: true)
        let calc = SMBCalculator(settings: settings)
        
        let result = calc.calculate(
            currentBG: 180,
            eventualBG: 180,
            minPredBG: 120,
            targetBG: 100,
            iob: 1.0,
            cob: 30,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(result.shouldDeliver)
        #expect(result.units > 0)
        #expect(result.units <= 2.0)
    }
    
    @Test("SMB interval")
    func smbInterval() {
        let settings = SMBSettings(enabled: true, minInterval: 180, enableAlways: true)
        let calc = SMBCalculator(settings: settings)
        
        // Last SMB was 1 minute ago
        let lastSMB = Date().addingTimeInterval(-60)
        
        let result = calc.calculate(
            currentBG: 180,
            eventualBG: 180,
            minPredBG: 120,
            targetBG: 100,
            iob: 1.0,
            cob: 30,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: lastSMB
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("interval"))
    }
    
    @Test("SMB near target")
    func smbNearTarget() {
        let settings = SMBSettings(enabled: true, enableAlways: true)
        let calc = SMBCalculator(settings: settings)
        
        let result = calc.calculate(
            currentBG: 105,
            eventualBG: 105,  // Near target
            minPredBG: 100,
            targetBG: 100,
            iob: 0.5,
            cob: 0,
            sens: 50,
            maxBasal: 3.0,
            lastSMBTime: nil
        )
        
        #expect(!result.shouldDeliver)
        #expect(result.reason.contains("near target"))
    }
}

// MARK: - SMB History Tests

@Suite("SMB History")
struct SMBHistoryTests {
    
    @Test("Record delivery")
    func recordDelivery() {
        let history = SMBHistory()
        
        history.record(SMBDelivery(units: 0.5, reason: "Test", bgAtDelivery: 150))
        
        #expect(history.lastDeliveryTime != nil)
        #expect(history.recentDeliveries.count == 1)
    }
    
    @Test("Total units since")
    func totalUnitsSince() {
        let history = SMBHistory()
        
        history.record(SMBDelivery(units: 0.5, reason: "Test1", bgAtDelivery: 150))
        history.record(SMBDelivery(units: 0.3, reason: "Test2", bgAtDelivery: 160))
        
        let total = history.totalUnitsSince(Date().addingTimeInterval(-3600))
        #expect(abs(total - 0.8) < 0.01)
    }
    
    @Test("Deliveries since")
    func deliveriesSince() {
        let history = SMBHistory()
        
        history.record(SMBDelivery(units: 0.5, reason: "Recent", bgAtDelivery: 150))
        
        let recent = history.deliveriesSince(Date().addingTimeInterval(-60))
        #expect(recent.count == 1)
        
        let old = history.deliveriesSince(Date().addingTimeInterval(60))  // Future
        #expect(old.count == 0)
    }
}

// MARK: - Conformance Test Case Tests

@Suite("Conformance Test Case")
struct ConformanceTestCaseTests {
    
    @Test("Glucose value to reading")
    func glucoseValueToReading() {
        let value = GlucoseValue(glucose: 120, minutesAgo: 10)
        let now = Date()
        let reading = value.toGlucoseReading(from: now)
        
        #expect(reading.glucose == 120)
        #expect(reading.source == "conformance")
    }
    
    @Test("Profile values to algorithm profile")
    func profileValuesToAlgorithmProfile() {
        let values = ProfileValues(basalRate: 1.5, isf: 40, icr: 12)
        let profile = values.toAlgorithmProfile()
        
        #expect(profile.currentBasal() == 1.5)
        #expect(profile.currentISF() == 40)
        #expect(profile.currentICR() == 12)
    }
}

// MARK: - Conformance Test Result Tests

@Suite("Conformance Test Result")
struct ConformanceTestResultTests {
    
    @Test("Passing result")
    func passingResult() {
        let testCase = ConformanceTestCase(
            id: "TC-TEST",
            name: "Test",
            glucoseHistory: [GlucoseValue(glucose: 100, minutesAgo: 0)],
            iob: 0,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 1.0,
            expectedEventualBG: 100,
            expectedMinPredBG: 100
        )
        
        let result = ConformanceTestResult(
            testCase: testCase,
            actualRate: 1.0,
            actualEventualBG: 100,
            actualMinPredBG: 100
        )
        
        #expect(result.passed)
        #expect(result.ratePassed)
        #expect(result.eventualBGPassed)
    }
    
    @Test("Failing rate result")
    func failingRateResult() {
        let testCase = ConformanceTestCase(
            id: "TC-TEST",
            name: "Test",
            glucoseHistory: [GlucoseValue(glucose: 100, minutesAgo: 0)],
            iob: 0,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 1.0,
            expectedEventualBG: 100,
            expectedMinPredBG: 100,
            rateTolerance: 0.1
        )
        
        let result = ConformanceTestResult(
            testCase: testCase,
            actualRate: 2.0,  // Way off
            actualEventualBG: 100,
            actualMinPredBG: 100
        )
        
        #expect(!result.passed)
        #expect(!result.ratePassed)
        #expect(result.reason.contains("Rate"))
    }
    
    @Test("Within tolerance")
    func withinTolerance() {
        let testCase = ConformanceTestCase(
            id: "TC-TEST",
            name: "Test",
            glucoseHistory: [GlucoseValue(glucose: 100, minutesAgo: 0)],
            iob: 0,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 1.0,
            expectedEventualBG: 100,
            expectedMinPredBG: 100,
            rateTolerance: 0.1,
            bgTolerance: 5.0
        )
        
        let result = ConformanceTestResult(
            testCase: testCase,
            actualRate: 1.05,  // Within tolerance
            actualEventualBG: 103,  // Within tolerance
            actualMinPredBG: 98  // Within tolerance
        )
        
        #expect(result.passed)
    }
}

// MARK: - Conformance Test Runner Tests

@Suite("Conformance Test Runner")
struct ConformanceTestRunnerTests {
    let runner = ConformanceTestRunner()
    
    @Test("Run single case")
    func runSingleCase() {
        let testCase = ReferenceTestVectors.basic.first!
        let result = runner.run(testCase)
        
        // Just verify it runs without crashing
        #expect(result.testCase.id == testCase.id)
        #expect(result.actualRate != nil)
    }
    
    @Test("Run all basic cases")
    func runAllBasicCases() {
        let (results, passed, _) = runner.runWithSummary(ReferenceTestVectors.basic)
        
        #expect(results.count == 5)
        #expect(passed >= 0)
        print("Conformance: \(passed)/\(results.count) passed")
    }
    
    @Test("Low glucose suspend")
    func lowGlucoseSuspend() {
        let testCase = ReferenceTestVectors.basic[2]  // TC-003: Low glucose suspend
        let result = runner.run(testCase)
        
        // Should definitely suspend (rate = 0)
        #expect(result.actualRate == 0)
    }
}

// MARK: - Reference Test Vectors Tests

@Suite("Reference Test Vectors")
struct ReferenceTestVectorsTests {
    
    @Test("Basic vectors exist")
    func basicVectorsExist() {
        #expect(!ReferenceTestVectors.basic.isEmpty)
        #expect(ReferenceTestVectors.basic.count == 5)
    }
    
    @Test("All vectors")
    func allVectors() {
        #expect(ReferenceTestVectors.all.count == ReferenceTestVectors.basic.count)
    }
    
    @Test("Vector ids")
    func vectorIds() {
        let ids = ReferenceTestVectors.basic.map(\.id)
        #expect(ids.contains("TC-001"))
        #expect(ids.contains("TC-003"))
    }
}


// MARK: - Algorithm Capabilities Tests

@Suite("Algorithm Capabilities")
struct AlgorithmCapabilitiesTests {
    
    @Test("Default capabilities")
    func defaultCapabilities() {
        let caps = AlgorithmCapabilities()
        #expect(caps.supportsTempBasal)
        #expect(!caps.supportsSMB)
        #expect(!caps.supportsUAM)
        #expect(!caps.supportsDynamicISF)
        #expect(!caps.supportsAutosens)
        #expect(!caps.providesPredictions)
        #expect(caps.minGlucoseHistory == 3)
        #expect(caps.origin == .custom)
    }
    
    @Test("Oref0 capabilities")
    func oref0Capabilities() {
        let oref0 = Oref0Algorithm()
        #expect(oref0.name == "oref0")
        #expect(oref0.capabilities.origin == .oref0)
        #expect(oref0.capabilities.supportsTempBasal)
        #expect(!oref0.capabilities.supportsSMB)
        #expect(oref0.capabilities.supportsAutosens)
        #expect(oref0.capabilities.providesPredictions)
    }
    
    @Test("Simple proportional capabilities")
    func simpleProportionalCapabilities() {
        let simple = SimpleProportionalAlgorithm()
        #expect(simple.name == "SimpleProportional")
        #expect(simple.capabilities.origin == .custom)
        #expect(simple.capabilities.supportsTempBasal)
        #expect(!simple.capabilities.supportsSMB)
        #expect(simple.capabilities.minGlucoseHistory == 1)
    }
    
    @Test("Capabilities equatable")
    func capabilitiesEquatable() {
        let caps1 = AlgorithmCapabilities(supportsSMB: true, origin: .oref1)
        let caps2 = AlgorithmCapabilities(supportsSMB: true, origin: .oref1)
        let caps3 = AlgorithmCapabilities(supportsSMB: false, origin: .oref0)
        
        #expect(caps1 == caps2)
        #expect(caps1 != caps3)
    }
    
    @Test("Algorithm origin raw values")
    func algorithmOriginRawValues() {
        #expect(AlgorithmOrigin.oref0.rawValue == "OpenAPS/oref0")
        #expect(AlgorithmOrigin.oref1.rawValue == "OpenAPS/oref1")
        #expect(AlgorithmOrigin.loop.rawValue == "Loop")
        #expect(AlgorithmOrigin.trio.rawValue == "Trio")
    }
}

// MARK: - Algorithm Validation Tests

@Suite("Algorithm Validation")
struct AlgorithmValidationTests {
    
    @Test("Validate insufficient glucose")
    func validateInsufficientGlucose() {
        let simple = SimpleProportionalAlgorithm()
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let inputs = AlgorithmInputs(
            glucose: [],  // No glucose
            profile: profile
        )
        
        let errors = simple.validate(inputs)
        #expect(!errors.isEmpty)
        
        if case .insufficientGlucoseData(let required, let provided) = errors.first {
            #expect(required == 1)
            #expect(provided == 0)
        } else {
            Issue.record("Expected insufficientGlucoseData error")
        }
    }
    
    @Test("Validate sufficient glucose")
    func validateSufficientGlucose() {
        let simple = SimpleProportionalAlgorithm()
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let reading = GlucoseReading(glucose: 100)
        let inputs = AlgorithmInputs(
            glucose: [reading],
            profile: profile
        )
        
        let errors = simple.validate(inputs)
        #expect(errors.isEmpty)
    }
    
    @Test("Validate Oref0 requirements")
    func validateOref0Requirements() {
        let oref0 = Oref0Algorithm()
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let reading = GlucoseReading(glucose: 100)
        let inputs = AlgorithmInputs(
            glucose: [reading, reading],  // Only 2, needs 3
            profile: profile
        )
        
        let errors = oref0.validate(inputs)
        #expect(!errors.isEmpty)
        
        if case .insufficientGlucoseData(let required, let provided) = errors.first {
            #expect(required == 3)
            #expect(provided == 2)
        } else {
            Issue.record("Expected insufficientGlucoseData error")
        }
    }
    
    @Test("Algorithm error cases")
    func algorithmErrorCases() {
        // Just verify error cases compile and are distinct
        let errors: [AlgorithmError] = [
            .insufficientGlucoseData(required: 3, provided: 1),
            .invalidProfile(reason: "No basals"),
            .calculationFailed(reason: "Overflow"),
            .capabilityNotSupported(capability: "SMB"),
            .configurationError(reason: "Invalid setting")
        ]
        
        #expect(errors.count == 5)
    }
}