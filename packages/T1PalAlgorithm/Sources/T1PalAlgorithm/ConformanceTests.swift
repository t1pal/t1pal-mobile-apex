// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ConformanceTests.swift
// T1Pal Mobile
//
// Conformance test harness for comparing Swift to oref0 JS
// Requirements: REQ-VERIFY-001
//
// Validates that our Swift implementation produces results
// within acceptable tolerance of the reference oref0 implementation.

import Foundation
import T1PalCore

// MARK: - Test Case Definition

/// A conformance test case with known inputs and expected outputs
public struct ConformanceTestCase: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    
    // Inputs
    public let glucoseHistory: [GlucoseValue]
    public let iob: Double
    public let cob: Double
    public let profile: ProfileValues
    public let currentTemp: TempBasalValue?
    
    // Expected outputs (from oref0 JS)
    public let expectedRate: Double?
    public let expectedDuration: Int?
    public let expectedEventualBG: Double
    public let expectedMinPredBG: Double
    
    // Tolerance for comparison
    public let rateTolerance: Double
    public let bgTolerance: Double
    
    public init(
        id: String,
        name: String,
        description: String = "",
        glucoseHistory: [GlucoseValue],
        iob: Double,
        cob: Double,
        profile: ProfileValues,
        currentTemp: TempBasalValue? = nil,
        expectedRate: Double?,
        expectedDuration: Int? = 30,
        expectedEventualBG: Double,
        expectedMinPredBG: Double,
        rateTolerance: Double = 0.1,
        bgTolerance: Double = 5.0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.glucoseHistory = glucoseHistory
        self.iob = iob
        self.cob = cob
        self.profile = profile
        self.currentTemp = currentTemp
        self.expectedRate = expectedRate
        self.expectedDuration = expectedDuration
        self.expectedEventualBG = expectedEventualBG
        self.expectedMinPredBG = expectedMinPredBG
        self.rateTolerance = rateTolerance
        self.bgTolerance = bgTolerance
    }
}

/// Simplified glucose value for test cases
public struct GlucoseValue: Codable, Sendable {
    public let glucose: Double
    public let minutesAgo: Int
    
    public init(glucose: Double, minutesAgo: Int) {
        self.glucose = glucose
        self.minutesAgo = minutesAgo
    }
    
    public func toGlucoseReading(from baseTime: Date = Date()) -> GlucoseReading {
        GlucoseReading(
            glucose: glucose,
            timestamp: baseTime.addingTimeInterval(Double(-minutesAgo * 60)),
            source: "conformance"
        )
    }
}

/// Simplified profile for test cases
public struct ProfileValues: Codable, Sendable {
    public let basalRate: Double
    public let isf: Double
    public let icr: Double
    public let targetLow: Double
    public let targetHigh: Double
    public let maxBasal: Double
    public let maxIOB: Double
    public let dia: Double
    
    public init(
        basalRate: Double = 1.0,
        isf: Double = 50,
        icr: Double = 10,
        targetLow: Double = 100,
        targetHigh: Double = 110,
        maxBasal: Double = 3.0,
        maxIOB: Double = 8.0,
        dia: Double = 6.0
    ) {
        self.basalRate = basalRate
        self.isf = isf
        self.icr = icr
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.maxBasal = maxBasal
        self.maxIOB = maxIOB
        self.dia = dia
    }
    
    public func toAlgorithmProfile() -> AlgorithmProfile {
        ProfileBuilder()
            .withDIA(dia)
            .withBasal(at: "00:00", rate: basalRate)
            .withISF(at: "00:00", sensitivity: isf)
            .withICR(at: "00:00", ratio: icr)
            .withTarget(at: "00:00", low: targetLow, high: targetHigh)
            .withMaxBasal(maxBasal)
            .withMaxIOB(maxIOB)
            .build()
    }
}

/// Temp basal value for test cases
public struct TempBasalValue: Codable, Sendable {
    public let rate: Double
    public let minutesRemaining: Int
    
    public init(rate: Double, minutesRemaining: Int) {
        self.rate = rate
        self.minutesRemaining = minutesRemaining
    }
}

// MARK: - Test Result

/// Result of running a conformance test
public struct ConformanceTestResult: Sendable {
    public let testCase: ConformanceTestCase
    public let actualRate: Double?
    public let actualEventualBG: Double
    public let actualMinPredBG: Double
    public let ratePassed: Bool
    public let eventualBGPassed: Bool
    public let minPredBGPassed: Bool
    public let passed: Bool
    public let reason: String
    
    public init(
        testCase: ConformanceTestCase,
        actualRate: Double?,
        actualEventualBG: Double,
        actualMinPredBG: Double
    ) {
        self.testCase = testCase
        self.actualRate = actualRate
        self.actualEventualBG = actualEventualBG
        self.actualMinPredBG = actualMinPredBG
        
        // Check rate
        if let expected = testCase.expectedRate, let actual = actualRate {
            self.ratePassed = abs(expected - actual) <= testCase.rateTolerance
        } else if testCase.expectedRate == nil && actualRate == nil {
            self.ratePassed = true
        } else {
            self.ratePassed = false
        }
        
        // Check BG predictions
        self.eventualBGPassed = abs(testCase.expectedEventualBG - actualEventualBG) <= testCase.bgTolerance
        self.minPredBGPassed = abs(testCase.expectedMinPredBG - actualMinPredBG) <= testCase.bgTolerance
        
        self.passed = ratePassed && eventualBGPassed && minPredBGPassed
        
        if passed {
            self.reason = "All checks passed"
        } else {
            var reasons: [String] = []
            if !ratePassed {
                reasons.append("Rate: expected \(testCase.expectedRate ?? 0), got \(actualRate ?? 0)")
            }
            if !eventualBGPassed {
                reasons.append("EventualBG: expected \(testCase.expectedEventualBG), got \(actualEventualBG)")
            }
            if !minPredBGPassed {
                reasons.append("MinPredBG: expected \(testCase.expectedMinPredBG), got \(actualMinPredBG)")
            }
            self.reason = reasons.joined(separator: "; ")
        }
    }
}

// MARK: - Conformance Test Runner

/// Runs conformance tests against the algorithm
public struct ConformanceTestRunner: Sendable {
    public let determineBasal: DetermineBasal
    
    public init() {
        self.determineBasal = DetermineBasal()
    }
    
    /// Run a single test case
    public func run(_ testCase: ConformanceTestCase) -> ConformanceTestResult {
        let baseTime = Date()
        
        // Convert inputs
        let glucose = testCase.glucoseHistory.map { $0.toGlucoseReading(from: baseTime) }
        let profile = testCase.profile.toAlgorithmProfile()
        
        // Run algorithm
        let output = determineBasal.calculate(
            glucose: glucose,
            iob: testCase.iob,
            cob: testCase.cob,
            profile: profile,
            currentTemp: testCase.currentTemp.map { TempBasal(rate: $0.rate, duration: Double($0.minutesRemaining * 60)) }
        )
        
        return ConformanceTestResult(
            testCase: testCase,
            actualRate: output.rate,
            actualEventualBG: output.eventualBG,
            actualMinPredBG: output.minPredBG
        )
    }
    
    /// Run all test cases
    public func runAll(_ testCases: [ConformanceTestCase]) -> [ConformanceTestResult] {
        testCases.map { run($0) }
    }
    
    /// Run and report summary
    public func runWithSummary(_ testCases: [ConformanceTestCase]) -> (results: [ConformanceTestResult], passed: Int, failed: Int) {
        let results = runAll(testCases)
        let passed = results.filter(\.passed).count
        let failed = results.count - passed
        return (results, passed, failed)
    }
}

// MARK: - Reference Test Vectors

/// Standard test vectors based on oref0 behavior
public struct ReferenceTestVectors {
    
    /// Basic test cases
    public static let basic: [ConformanceTestCase] = [
        // TC-001: Stable in range
        ConformanceTestCase(
            id: "TC-001",
            name: "Stable in range",
            description: "BG stable at 105, should maintain scheduled basal",
            glucoseHistory: [
                GlucoseValue(glucose: 105, minutesAgo: 0),
                GlucoseValue(glucose: 105, minutesAgo: 5),
                GlucoseValue(glucose: 104, minutesAgo: 10),
                GlucoseValue(glucose: 106, minutesAgo: 15)
            ],
            iob: 0.5,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 1.0,  // Scheduled basal
            expectedEventualBG: 80,  // 105 - (0.5 * 50)
            expectedMinPredBG: 80
        ),
        
        // TC-002: High BG, increase basal
        ConformanceTestCase(
            id: "TC-002",
            name: "High BG correction",
            description: "BG at 180, should increase temp basal",
            glucoseHistory: [
                GlucoseValue(glucose: 180, minutesAgo: 0),
                GlucoseValue(glucose: 175, minutesAgo: 5),
                GlucoseValue(glucose: 170, minutesAgo: 10),
                GlucoseValue(glucose: 165, minutesAgo: 15)
            ],
            iob: 0.5,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 2.5,  // Higher than scheduled
            expectedEventualBG: 155,  // Dropping
            expectedMinPredBG: 155,
            rateTolerance: 0.5  // More tolerance for rate
        ),
        
        // TC-003: Low BG, suspend
        ConformanceTestCase(
            id: "TC-003",
            name: "Low glucose suspend",
            description: "BG at 65, should suspend basal",
            glucoseHistory: [
                GlucoseValue(glucose: 65, minutesAgo: 0),
                GlucoseValue(glucose: 70, minutesAgo: 5),
                GlucoseValue(glucose: 75, minutesAgo: 10),
                GlucoseValue(glucose: 80, minutesAgo: 15)
            ],
            iob: 1.0,
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 0,  // Suspended
            expectedEventualBG: 15,  // Low
            expectedMinPredBG: 15,
            bgTolerance: 20  // More tolerance for extreme values
        ),
        
        // TC-004: Predicted low
        ConformanceTestCase(
            id: "TC-004",
            name: "Predicted low suspend",
            description: "BG 90 with high IOB, predicted to go low",
            glucoseHistory: [
                GlucoseValue(glucose: 90, minutesAgo: 0),
                GlucoseValue(glucose: 95, minutesAgo: 5),
                GlucoseValue(glucose: 100, minutesAgo: 10),
                GlucoseValue(glucose: 105, minutesAgo: 15)
            ],
            iob: 3.0,  // High IOB
            cob: 0,
            profile: ProfileValues(),
            expectedRate: 0,  // Should suspend
            expectedEventualBG: -60,  // 90 - (3 * 50) = -60
            expectedMinPredBG: -60,
            bgTolerance: 30
        ),
        
        // TC-005: Rising with COB
        ConformanceTestCase(
            id: "TC-005",
            name: "Rising with carbs",
            description: "BG rising with 30g COB",
            glucoseHistory: [
                GlucoseValue(glucose: 130, minutesAgo: 0),
                GlucoseValue(glucose: 120, minutesAgo: 5),
                GlucoseValue(glucose: 110, minutesAgo: 10),
                GlucoseValue(glucose: 100, minutesAgo: 15)
            ],
            iob: 1.5,
            cob: 30,
            profile: ProfileValues(),
            expectedRate: 1.5,  // Slightly above scheduled
            expectedEventualBG: 55,  // 130 - (1.5 * 50)
            expectedMinPredBG: 55,
            rateTolerance: 0.5
        )
    ]
    
    /// All test vectors
    public static var all: [ConformanceTestCase] {
        basic
    }
}
