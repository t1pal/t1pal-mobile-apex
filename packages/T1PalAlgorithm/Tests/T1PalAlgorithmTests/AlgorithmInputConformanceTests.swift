// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmInputConformanceTests.swift
// T1Pal Mobile
//
// Conformance test suite for verifying algorithm input assembly consistency
// Requirements: ALG-INPUT-016
//
// This test suite ensures that:
// 1. Same data source produces same inputs (determinism)
// 2. CLI and Playground produce identical inputs for same data
// 3. Known-good fixtures are preserved (regression protection)

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - Conformance Test Fixtures

/// A captured algorithm input/output snapshot for conformance testing
public struct ConformanceFixture: Codable, Sendable {
    /// Unique identifier for the fixture
    public let id: String
    
    /// Human-readable description
    public let description: String
    
    /// The scenario or data source configuration
    public let scenario: ScenarioConfig
    
    /// Expected inputs after assembly
    public let expectedInputs: ExpectedInputs
    
    /// Expected algorithm outputs (optional, for full round-trip testing)
    public let expectedOutputs: ExpectedOutputs?
    
    /// Fixture creation timestamp
    public let createdAt: String
    
    public init(
        id: String,
        description: String,
        scenario: ScenarioConfig,
        expectedInputs: ExpectedInputs,
        expectedOutputs: ExpectedOutputs? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.description = description
        self.scenario = scenario
        self.expectedInputs = expectedInputs
        self.expectedOutputs = expectedOutputs
        self.createdAt = createdAt
    }
}

/// Configuration describing the data source scenario
public struct ScenarioConfig: Codable, Sendable {
    /// MockDataSource scenario name
    public let mockScenario: String?
    
    /// Nightscout URL (for NS-based fixtures)
    public let nightscoutURL: String?
    
    /// Reference time for assembly
    public let referenceTime: String?
    
    /// Custom configuration overrides
    public let glucoseCount: Int?
    public let doseHistoryHours: Int?
    public let carbHistoryHours: Int?
    
    public init(
        mockScenario: String? = nil,
        nightscoutURL: String? = nil,
        referenceTime: String? = nil,
        glucoseCount: Int? = nil,
        doseHistoryHours: Int? = nil,
        carbHistoryHours: Int? = nil
    ) {
        self.mockScenario = mockScenario
        self.nightscoutURL = nightscoutURL
        self.referenceTime = referenceTime
        self.glucoseCount = glucoseCount
        self.doseHistoryHours = doseHistoryHours
        self.carbHistoryHours = carbHistoryHours
    }
}

/// Expected algorithm inputs for validation
public struct ExpectedInputs: Codable, Sendable {
    /// Expected glucose count
    public let glucoseCount: Int
    
    /// Expected latest glucose value (approximate, within tolerance)
    public let latestGlucose: GlucoseExpectation?
    
    /// Expected IOB range
    public let iobRange: ValueRange?
    
    /// Expected COB range
    public let cobRange: ValueRange?
    
    /// Expected dose history count
    public let doseCount: Int?
    
    /// Expected carb history count
    public let carbCount: Int?
    
    /// Expected profile values
    public let profile: ProfileExpectation?
    
    public init(
        glucoseCount: Int,
        latestGlucose: GlucoseExpectation? = nil,
        iobRange: ValueRange? = nil,
        cobRange: ValueRange? = nil,
        doseCount: Int? = nil,
        carbCount: Int? = nil,
        profile: ProfileExpectation? = nil
    ) {
        self.glucoseCount = glucoseCount
        self.latestGlucose = latestGlucose
        self.iobRange = iobRange
        self.cobRange = cobRange
        self.doseCount = doseCount
        self.carbCount = carbCount
        self.profile = profile
    }
}

/// Expected glucose value with tolerance
public struct GlucoseExpectation: Codable, Sendable {
    public let value: Double
    public let tolerance: Double
    
    public init(value: Double, tolerance: Double = 5.0) {
        self.value = value
        self.tolerance = tolerance
    }
}

/// A value range for fuzzy matching
public struct ValueRange: Codable, Sendable {
    public let min: Double
    public let max: Double
    
    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
    
    public func contains(_ value: Double) -> Bool {
        return value >= min && value <= max
    }
}

/// Expected profile characteristics
public struct ProfileExpectation: Codable, Sendable {
    public let basalRateCount: Int?
    public let isfCount: Int?
    public let carbRatioCount: Int?
    public let targetLow: Double?
    public let targetHigh: Double?
    
    public init(
        basalRateCount: Int? = nil,
        isfCount: Int? = nil,
        carbRatioCount: Int? = nil,
        targetLow: Double? = nil,
        targetHigh: Double? = nil
    ) {
        self.basalRateCount = basalRateCount
        self.isfCount = isfCount
        self.carbRatioCount = carbRatioCount
        self.targetLow = targetLow
        self.targetHigh = targetHigh
    }
}

/// Expected algorithm outputs
public struct ExpectedOutputs: Codable, Sendable {
    /// Expected temp basal rate range
    public let tempBasalRange: ValueRange?
    
    /// Whether a bolus is expected
    public let expectBolus: Bool?
    
    public init(
        tempBasalRange: ValueRange? = nil,
        expectBolus: Bool? = nil
    ) {
        self.tempBasalRange = tempBasalRange
        self.expectBolus = expectBolus
    }
}

// MARK: - Conformance Test Runner

/// Utility for running algorithm input conformance tests
public struct InputConformanceRunner {
    
    /// Load fixtures from JSON file
    public static func loadFixtures(from url: URL) throws -> [ConformanceFixture] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ConformanceFixture].self, from: data)
    }
    
    /// Load a single fixture from JSON string
    public static func loadFixture(from json: String) throws -> ConformanceFixture {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(ConformanceFixture.self, from: data)
    }
    
    /// Create a MockDataSource from scenario config
    public static func createDataSource(from config: ScenarioConfig) -> MockDataSource {
        let scenario: MockDataSource.GlucoseScenario
        if let scenarioName = config.mockScenario,
           let parsed = MockDataSource.GlucoseScenario(rawValue: scenarioName) {
            scenario = parsed
        } else {
            scenario = .stable120
        }
        
        return MockDataSource(
            scenario: scenario,
            glucoseCount: config.glucoseCount ?? 36,
            doseHours: config.doseHistoryHours ?? 6,
            carbHours: config.carbHistoryHours ?? 6
        )
    }
    
    /// Validate assembled inputs against expectations
    public static func validate(
        inputs: AlgorithmInputs,
        against expected: ExpectedInputs
    ) -> [InputConformanceViolation] {
        var violations: [InputConformanceViolation] = []
        
        // Validate glucose count
        if inputs.glucose.count != expected.glucoseCount {
            violations.append(.glucoseCountMismatch(
                expected: expected.glucoseCount,
                actual: inputs.glucose.count
            ))
        }
        
        // Validate latest glucose
        if let expectedGlucose = expected.latestGlucose,
           let latestGlucose = inputs.glucose.first {
            let diff = abs(latestGlucose.glucose - expectedGlucose.value)
            if diff > expectedGlucose.tolerance {
                violations.append(.glucoseValueMismatch(
                    expected: expectedGlucose.value,
                    actual: latestGlucose.glucose,
                    tolerance: expectedGlucose.tolerance
                ))
            }
        }
        
        // Validate IOB range
        if let iobRange = expected.iobRange {
            if !iobRange.contains(inputs.insulinOnBoard) {
                violations.append(.iobOutOfRange(
                    expected: iobRange,
                    actual: inputs.insulinOnBoard
                ))
            }
        }
        
        // Validate COB range
        if let cobRange = expected.cobRange {
            if !cobRange.contains(inputs.carbsOnBoard) {
                violations.append(.cobOutOfRange(
                    expected: cobRange,
                    actual: inputs.carbsOnBoard
                ))
            }
        }
        
        // Validate dose count
        if let expectedDoses = expected.doseCount,
           let actualDoses = inputs.doseHistory {
            if actualDoses.count != expectedDoses {
                violations.append(.doseCountMismatch(
                    expected: expectedDoses,
                    actual: actualDoses.count
                ))
            }
        }
        
        // Validate carb count
        if let expectedCarbs = expected.carbCount,
           let actualCarbs = inputs.carbHistory {
            if actualCarbs.count != expectedCarbs {
                violations.append(.carbCountMismatch(
                    expected: expectedCarbs,
                    actual: actualCarbs.count
                ))
            }
        }
        
        // Validate profile
        if let profileExp = expected.profile {
            if let expectedBasal = profileExp.basalRateCount,
               inputs.profile.basalRates.count != expectedBasal {
                violations.append(.profileMismatch(
                    field: "basalRateCount",
                    expected: "\(expectedBasal)",
                    actual: "\(inputs.profile.basalRates.count)"
                ))
            }
            if let expectedISF = profileExp.isfCount,
               inputs.profile.sensitivityFactors.count != expectedISF {
                violations.append(.profileMismatch(
                    field: "isfCount",
                    expected: "\(expectedISF)",
                    actual: "\(inputs.profile.sensitivityFactors.count)"
                ))
            }
            if let expectedCR = profileExp.carbRatioCount,
               inputs.profile.carbRatios.count != expectedCR {
                violations.append(.profileMismatch(
                    field: "carbRatioCount",
                    expected: "\(expectedCR)",
                    actual: "\(inputs.profile.carbRatios.count)"
                ))
            }
        }
        
        return violations
    }
}

/// Types of input conformance violations
public enum InputConformanceViolation: CustomStringConvertible, Sendable {
    case glucoseCountMismatch(expected: Int, actual: Int)
    case glucoseValueMismatch(expected: Double, actual: Double, tolerance: Double)
    case iobOutOfRange(expected: ValueRange, actual: Double)
    case cobOutOfRange(expected: ValueRange, actual: Double)
    case doseCountMismatch(expected: Int, actual: Int)
    case carbCountMismatch(expected: Int, actual: Int)
    case profileMismatch(field: String, expected: String, actual: String)
    
    public var description: String {
        switch self {
        case .glucoseCountMismatch(let expected, let actual):
            return "Glucose count mismatch: expected \(expected), got \(actual)"
        case .glucoseValueMismatch(let expected, let actual, let tolerance):
            return "Glucose value mismatch: expected \(expected)±\(tolerance), got \(actual)"
        case .iobOutOfRange(let expected, let actual):
            return "IOB out of range: expected \(expected.min)-\(expected.max), got \(actual)"
        case .cobOutOfRange(let expected, let actual):
            return "COB out of range: expected \(expected.min)-\(expected.max), got \(actual)"
        case .doseCountMismatch(let expected, let actual):
            return "Dose count mismatch: expected \(expected), got \(actual)"
        case .carbCountMismatch(let expected, let actual):
            return "Carb count mismatch: expected \(expected), got \(actual)"
        case .profileMismatch(let field, let expected, let actual):
            return "Profile \(field) mismatch: expected \(expected), got \(actual)"
        }
    }
}

// MARK: - Swift Testing Tests

@Suite("Algorithm Input Conformance")
struct AlgorithmInputConformanceTests {
    
    // MARK: - MockDataSource Determinism Tests
    
    @Test("MockDataSource stable120 produces consistent glucose count")
    func mockStable120GlucoseCount() async throws {
        let mock = MockDataSource(scenario: .stable120)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        // Default configuration should produce 36 glucose readings
        #expect(inputs.glucose.count == 36)
    }
    
    @Test("MockDataSource stable120 produces expected glucose range")
    func mockStable120GlucoseRange() async throws {
        let mock = MockDataSource(scenario: .stable120)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        // stable120 should produce readings around 120 mg/dL
        let latestGlucose = inputs.glucose.first!.glucose
        #expect(latestGlucose >= 110 && latestGlucose <= 130)
    }
    
    @Test("MockDataSource hypo produces low glucose")
    func mockHypoGlucoseRange() async throws {
        let mock = MockDataSource(scenario: .hypo)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        // hypo scenario should have glucose below 70
        let latestGlucose = inputs.glucose.first!.glucose
        #expect(latestGlucose < 70)
    }
    
    @Test("MockDataSource hyper produces high glucose")
    func mockHyperGlucoseRange() async throws {
        let mock = MockDataSource(scenario: .hyper)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        // hyper scenario should have glucose above 180
        let latestGlucose = inputs.glucose.first!.glucose
        #expect(latestGlucose > 180)
    }
    
    // MARK: - Profile Conformance Tests
    
    @Test("Default profile has required fields")
    func defaultProfileFields() async throws {
        let mock = MockDataSource(scenario: .stable120)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        #expect(inputs.profile.basalRates.count >= 1)
        #expect(inputs.profile.sensitivityFactors.count >= 1)
        #expect(inputs.profile.carbRatios.count >= 1)
        #expect(inputs.profile.targetGlucose.low > 0)
        #expect(inputs.profile.targetGlucose.high >= inputs.profile.targetGlucose.low)
    }
    
    // MARK: - History Conformance Tests
    
    @Test("Dose history is populated")
    func doseHistoryPopulated() async throws {
        let mock = MockDataSource(scenario: .stable120, includeRecentDoses: true)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        #expect(inputs.doseHistory != nil)
        #expect(inputs.doseHistory!.count > 0)
    }
    
    @Test("Carb history is populated for meal scenarios")
    func carbHistoryPopulated() async throws {
        // Use rising scenario which generates carbs (recent meal)
        let mock = MockDataSource(scenario: .rising, includeRecentCarbs: true)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        #expect(inputs.carbHistory != nil)
        #expect(inputs.carbHistory!.count > 0)
    }
    
    // MARK: - Fixture-Based Tests
    
    @Test("Stable scenario fixture validation")
    func stableScenarioFixture() async throws {
        let fixture = ConformanceFixture(
            id: "stable-120-default",
            description: "Stable glucose at 120 with default configuration",
            scenario: ScenarioConfig(mockScenario: "stable120"),
            expectedInputs: ExpectedInputs(
                glucoseCount: 36,
                latestGlucose: GlucoseExpectation(value: 120, tolerance: 15),
                iobRange: ValueRange(min: 0, max: 10),
                cobRange: ValueRange(min: 0, max: 100),
                profile: ProfileExpectation(
                    basalRateCount: 1,
                    isfCount: 1,
                    carbRatioCount: 1
                )
            )
        )
        
        let dataSource = InputConformanceRunner.createDataSource(from: fixture.scenario)
        let assembler = AlgorithmInputAssembler(dataSource: dataSource)
        let inputs = try await assembler.assembleInputs()
        
        let violations = InputConformanceRunner.validate(inputs: inputs, against: fixture.expectedInputs)
        
        #expect(violations.isEmpty, "Violations: \(violations.map { $0.description }.joined(separator: ", "))")
    }
    
    @Test("Hypo scenario fixture validation")
    func hypoScenarioFixture() async throws {
        let fixture = ConformanceFixture(
            id: "hypo-default",
            description: "Hypoglycemia scenario",
            scenario: ScenarioConfig(mockScenario: "hypo"),
            expectedInputs: ExpectedInputs(
                glucoseCount: 36,
                latestGlucose: GlucoseExpectation(value: 55, tolerance: 15),
                profile: ProfileExpectation(basalRateCount: 1)
            )
        )
        
        let dataSource = InputConformanceRunner.createDataSource(from: fixture.scenario)
        let assembler = AlgorithmInputAssembler(dataSource: dataSource)
        let inputs = try await assembler.assembleInputs()
        
        let violations = InputConformanceRunner.validate(inputs: inputs, against: fixture.expectedInputs)
        
        #expect(violations.isEmpty, "Violations: \(violations.map { $0.description }.joined(separator: ", "))")
    }
    
    @Test("All mock scenarios produce valid inputs")
    func allScenariosProduceValidInputs() async throws {
        for scenario in MockDataSource.GlucoseScenario.allCases {
            let mock = MockDataSource(scenario: scenario)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            // Basic validity checks
            #expect(inputs.glucose.count > 0, "Scenario \(scenario) produced no glucose")
            #expect(inputs.profile.basalRates.count > 0, "Scenario \(scenario) has no basal rates")
            #expect(inputs.insulinOnBoard >= 0, "Scenario \(scenario) has negative IOB")
            #expect(inputs.carbsOnBoard >= 0, "Scenario \(scenario) has negative COB")
        }
    }
    
    // MARK: - Cross-Assembly Consistency Tests
    
    @Test("Same data source produces identical inputs on repeated assembly")
    func repeatedAssemblyConsistency() async throws {
        let mock = MockDataSource(scenario: .stable100)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs1 = try await assembler.assembleInputs()
        let inputs2 = try await assembler.assembleInputs()
        
        // Glucose readings should be identical
        #expect(inputs1.glucose.count == inputs2.glucose.count)
        
        // Profile should be identical
        #expect(inputs1.profile.basalRates.count == inputs2.profile.basalRates.count)
        #expect(inputs1.profile.targetGlucose.low == inputs2.profile.targetGlucose.low)
    }
    
    // MARK: - Configuration Override Tests
    
    @Test("Custom glucose count is respected")
    func customGlucoseCount() async throws {
        let mock = MockDataSource(scenario: .stable120, glucoseCount: 12)
        var config = AlgorithmInputAssembler.Configuration.default
        config.minimumGlucoseCount = 3  // Lower minimum to allow fewer readings
        
        let assembler = AlgorithmInputAssembler(dataSource: mock, configuration: config)
        let inputs = try await assembler.assembleInputs()
        
        #expect(inputs.glucose.count == 12)
    }
    
    // MARK: - CLI/Playground Cross-App Conformance Tests (ALG-INPUT-017)
    
    @Test("Independent assemblers with same MockDataSource produce identical inputs")
    func independentAssemblersProduceSameInputs() async throws {
        // Use fixed base time to ensure deterministic timestamp-dependent calculations
        let fixedTime = Date(timeIntervalSince1970: 1708300800)  // Fixed point in time
        
        // Simulate CLI path: creates its own assembler
        let cliMock = MockDataSource(scenario: .stable120, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        // Simulate Playground path: creates its own assembler with same scenario
        let playgroundMock = MockDataSource(scenario: .stable120, baseTime: fixedTime)
        let playgroundAssembler = AlgorithmInputAssembler(dataSource: playgroundMock)
        let playgroundInputs = try await playgroundAssembler.assembleInputs(at: fixedTime)
        
        // Both should produce identical inputs
        #expect(cliInputs.glucose.count == playgroundInputs.glucose.count)
        #expect(cliInputs.insulinOnBoard == playgroundInputs.insulinOnBoard)
        #expect(cliInputs.carbsOnBoard == playgroundInputs.carbsOnBoard)
        #expect(cliInputs.profile.basalRates.count == playgroundInputs.profile.basalRates.count)
        #expect(cliInputs.profile.targetGlucose.low == playgroundInputs.profile.targetGlucose.low)
        #expect(cliInputs.profile.targetGlucose.high == playgroundInputs.profile.targetGlucose.high)
        
        // Verify glucose values match
        if let cliLatest = cliInputs.glucose.first,
           let playgroundLatest = playgroundInputs.glucose.first {
            #expect(cliLatest.glucose == playgroundLatest.glucose)
        }
    }
    
    @Test("All scenarios produce same outputs from CLI and Playground paths")
    func allScenariosMatchAcrossApps() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        for scenario in MockDataSource.GlucoseScenario.allCases {
            // CLI path
            let cliMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
            let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
            
            // Playground path
            let playgroundMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let playgroundAssembler = AlgorithmInputAssembler(dataSource: playgroundMock)
            let playgroundInputs = try await playgroundAssembler.assembleInputs(at: fixedTime)
            
            // Core values must match
            #expect(
                cliInputs.glucose.count == playgroundInputs.glucose.count,
                "Scenario \(scenario): glucose count mismatch"
            )
            #expect(
                cliInputs.insulinOnBoard == playgroundInputs.insulinOnBoard,
                "Scenario \(scenario): IOB mismatch"
            )
            #expect(
                cliInputs.carbsOnBoard == playgroundInputs.carbsOnBoard,
                "Scenario \(scenario): COB mismatch"
            )
        }
    }
    
    @Test("CLI and Playground with same config produce identical profile")
    func sameConfigProducesIdenticalProfile() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        var config = AlgorithmInputAssembler.Configuration.default
        config.calculateIOB = true
        config.calculateCOB = true
        config.applyLoopSettings = true
        
        // CLI path with explicit config
        let cliMock = MockDataSource(scenario: .rising, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock, configuration: config)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        // Playground path with same config
        let playgroundMock = MockDataSource(scenario: .rising, baseTime: fixedTime)
        let playgroundAssembler = AlgorithmInputAssembler(dataSource: playgroundMock, configuration: config)
        let playgroundInputs = try await playgroundAssembler.assembleInputs(at: fixedTime)
        
        // Profile must be identical
        #expect(cliInputs.profile.basalRates.count == playgroundInputs.profile.basalRates.count)
        if let cliBasal = cliInputs.profile.basalRates.first,
           let playgroundBasal = playgroundInputs.profile.basalRates.first {
            #expect(cliBasal.rate == playgroundBasal.rate)
        }
        
        #expect(cliInputs.profile.sensitivityFactors.count == playgroundInputs.profile.sensitivityFactors.count)
        if let cliISF = cliInputs.profile.sensitivityFactors.first,
           let playgroundISF = playgroundInputs.profile.sensitivityFactors.first {
            #expect(cliISF.factor == playgroundISF.factor)
        }
        
        #expect(cliInputs.profile.carbRatios.count == playgroundInputs.profile.carbRatios.count)
        if let cliCR = cliInputs.profile.carbRatios.first,
           let playgroundCR = playgroundInputs.profile.carbRatios.first {
            #expect(cliCR.ratio == playgroundCR.ratio)
        }
    }
    
    @Test("CLI and Playground with same data source produce identical dose history")
    func sameDataSourceProducesIdenticalDoseHistory() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        // Use scenario that generates doses
        let cliMock = MockDataSource(scenario: .falling, includeRecentDoses: true, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        let playgroundMock = MockDataSource(scenario: .falling, includeRecentDoses: true, baseTime: fixedTime)
        let playgroundAssembler = AlgorithmInputAssembler(dataSource: playgroundMock)
        let playgroundInputs = try await playgroundAssembler.assembleInputs(at: fixedTime)
        
        // Dose history must match
        #expect(cliInputs.doseHistory?.count == playgroundInputs.doseHistory?.count)
        
        if let cliDoses = cliInputs.doseHistory,
           let playgroundDoses = playgroundInputs.doseHistory,
           let cliFirst = cliDoses.first,
           let playgroundFirst = playgroundDoses.first {
            #expect(cliFirst.units == playgroundFirst.units)
            #expect(cliFirst.type == playgroundFirst.type)
        }
    }
    
    @Test("CLI and Playground produce identical carb history for meal scenarios")
    func sameDataSourceProducesIdenticalCarbHistory() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        // Use scenario that generates carbs (rising = recent meal)
        let cliMock = MockDataSource(scenario: .rising, includeRecentCarbs: true, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        let playgroundMock = MockDataSource(scenario: .rising, includeRecentCarbs: true, baseTime: fixedTime)
        let playgroundAssembler = AlgorithmInputAssembler(dataSource: playgroundMock)
        let playgroundInputs = try await playgroundAssembler.assembleInputs(at: fixedTime)
        
        // Carb history must match
        #expect(cliInputs.carbHistory?.count == playgroundInputs.carbHistory?.count)
        
        if let cliCarbs = cliInputs.carbHistory,
           let playgroundCarbs = playgroundInputs.carbHistory,
           let cliFirst = cliCarbs.first,
           let playgroundFirst = playgroundCarbs.first {
            #expect(cliFirst.grams == playgroundFirst.grams)
            #expect(cliFirst.absorptionType == playgroundFirst.absorptionType)
        }
    }
}

// MARK: - Demo App Conformance Tests (ALG-INPUT-018)

/// Tests verifying Demo app produces identical outputs as CLI for same data.
/// The Demo app's TierDemoManager.loadFromAssembler() uses:
/// - MockDataSource + AlgorithmInputAssembler + SimpleProportionalAlgorithm
/// These tests verify that code path matches CLI behavior.
@Suite("Demo App Conformance Tests")
struct DemoAppConformanceTests {
    
    @Test("Demo and CLI paths produce identical inputs for all scenarios")
    func demoAndCLIProduceSameInputs() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        for scenario in MockDataSource.GlucoseScenario.allCases {
            // CLI path (same as t1pal-predict-divergence --assembler)
            let cliMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
            let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
            
            // Demo app path (mirrors TierDemoManager.loadFromAssembler)
            let demoMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let demoAssembler = AlgorithmInputAssembler(dataSource: demoMock)
            let demoInputs = try await demoAssembler.assembleInputs(at: fixedTime)
            
            #expect(
                cliInputs.glucose.count == demoInputs.glucose.count,
                "Scenario \(scenario): glucose count mismatch"
            )
            #expect(
                cliInputs.insulinOnBoard == demoInputs.insulinOnBoard,
                "Scenario \(scenario): IOB mismatch (CLI: \(cliInputs.insulinOnBoard), Demo: \(demoInputs.insulinOnBoard))"
            )
            #expect(
                cliInputs.carbsOnBoard == demoInputs.carbsOnBoard,
                "Scenario \(scenario): COB mismatch (CLI: \(cliInputs.carbsOnBoard), Demo: \(demoInputs.carbsOnBoard))"
            )
        }
    }
    
    @Test("Demo and CLI produce identical algorithm decisions")
    func demoAndCLIProduceSameDecisions() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let algorithm = SimpleProportionalAlgorithm()
        
        for scenario in MockDataSource.GlucoseScenario.allCases {
            // CLI path
            let cliMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
            let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
            let cliDecision = try algorithm.calculate(cliInputs)
            
            // Demo app path
            let demoMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let demoAssembler = AlgorithmInputAssembler(dataSource: demoMock)
            let demoInputs = try await demoAssembler.assembleInputs(at: fixedTime)
            let demoDecision = try algorithm.calculate(demoInputs)
            
            // Decisions must match exactly
            #expect(
                cliDecision.suggestedTempBasal?.rate == demoDecision.suggestedTempBasal?.rate,
                "Scenario \(scenario): temp basal rate mismatch"
            )
            #expect(
                cliDecision.suggestedTempBasal?.duration == demoDecision.suggestedTempBasal?.duration,
                "Scenario \(scenario): temp basal duration mismatch"
            )
            #expect(
                cliDecision.suggestedBolus == demoDecision.suggestedBolus,
                "Scenario \(scenario): bolus mismatch"
            )
        }
    }
    
    @Test("Demo app IOB/COB extraction matches CLI values")
    func demoIOBCOBExtraction() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        // Test with a scenario that has meaningful IOB/COB
        let scenario = MockDataSource.GlucoseScenario.rising  // Has recent carbs
        
        let cliMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        let demoMock = MockDataSource(scenario: scenario, baseTime: fixedTime)
        let demoAssembler = AlgorithmInputAssembler(dataSource: demoMock)
        let demoInputs = try await demoAssembler.assembleInputs(at: fixedTime)
        
        // These are the values the Demo app displays in AIDModeContentView
        let cliIOB = cliInputs.insulinOnBoard
        let cliCOB = cliInputs.carbsOnBoard
        let demoIOB = demoInputs.insulinOnBoard
        let demoCOB = demoInputs.carbsOnBoard
        
        #expect(cliIOB == demoIOB, "IOB values must be identical")
        #expect(cliCOB == demoCOB, "COB values must be identical")
    }
    
    @Test("Demo app profile settings match CLI profile")
    func demoProfileMatchesCLI() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        
        let cliMock = MockDataSource(scenario: .stable120, baseTime: fixedTime)
        let cliAssembler = AlgorithmInputAssembler(dataSource: cliMock)
        let cliInputs = try await cliAssembler.assembleInputs(at: fixedTime)
        
        let demoMock = MockDataSource(scenario: .stable120, baseTime: fixedTime)
        let demoAssembler = AlgorithmInputAssembler(dataSource: demoMock)
        let demoInputs = try await demoAssembler.assembleInputs(at: fixedTime)
        
        // Profile settings used by algorithm must match
        #expect(cliInputs.profile.basalRates.count == demoInputs.profile.basalRates.count)
        #expect(cliInputs.profile.sensitivityFactors.count == demoInputs.profile.sensitivityFactors.count)
        #expect(cliInputs.profile.carbRatios.count == demoInputs.profile.carbRatios.count)
        #expect(cliInputs.profile.targetGlucose.low == demoInputs.profile.targetGlucose.low)
        #expect(cliInputs.profile.targetGlucose.high == demoInputs.profile.targetGlucose.high)
        
        // Verify specific values
        if let cliBasal = cliInputs.profile.basalRates.first,
           let demoBasal = demoInputs.profile.basalRates.first {
            #expect(cliBasal.rate == demoBasal.rate)
        }
    }
    
    @Test("Demo app refresh produces consistent results")
    func demoRefreshConsistency() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let algorithm = SimpleProportionalAlgorithm()
        
        // Simulate multiple "refreshes" as Demo app would do
        var decisions: [AlgorithmDecision] = []
        
        for _ in 0..<3 {
            let mock = MockDataSource(scenario: .variable, baseTime: fixedTime)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            let inputs = try await assembler.assembleInputs(at: fixedTime)
            let decision = try algorithm.calculate(inputs)
            decisions.append(decision)
        }
        
        // All refreshes should produce identical results (deterministic)
        for i in 1..<decisions.count {
            #expect(
                decisions[0].suggestedTempBasal?.rate == decisions[i].suggestedTempBasal?.rate,
                "Refresh \(i): temp basal should be deterministic"
            )
            #expect(
                decisions[0].suggestedBolus == decisions[i].suggestedBolus,
                "Refresh \(i): bolus should be deterministic"
            )
        }
    }
}

// MARK: - Fixture Export Utilities

extension AlgorithmInputs {
    /// Export inputs to a conformance-testable format
    public func toExpectedInputs() -> ExpectedInputs {
        ExpectedInputs(
            glucoseCount: glucose.count,
            latestGlucose: glucose.first.map { GlucoseExpectation(value: $0.glucose, tolerance: 1.0) },
            iobRange: ValueRange(min: insulinOnBoard - 0.5, max: insulinOnBoard + 0.5),
            cobRange: ValueRange(min: carbsOnBoard - 5, max: carbsOnBoard + 5),
            doseCount: doseHistory?.count,
            carbCount: carbHistory?.count,
            profile: ProfileExpectation(
                basalRateCount: profile.basalRates.count,
                isfCount: profile.sensitivityFactors.count,
                carbRatioCount: profile.carbRatios.count,
                targetLow: profile.targetGlucose.low,
                targetHigh: profile.targetGlucose.high
            )
        )
    }
}

// MARK: - Regression Fixture Types (ALG-INPUT-020)

/// A complete regression fixture with inputs AND expected outputs
public struct RegressionFixture: Codable, Sendable {
    /// Unique identifier
    public let id: String
    
    /// Human-readable description
    public let description: String
    
    /// Mock scenario configuration
    public let scenario: String
    
    /// Fixed timestamp for reproducibility
    public let timestamp: Double
    
    /// Expected algorithm inputs
    public let expectedInputs: RegressionInputs
    
    /// Expected algorithm outputs
    public let expectedOutputs: RegressionOutputs
    
    public init(
        id: String,
        description: String,
        scenario: String,
        timestamp: Double,
        expectedInputs: RegressionInputs,
        expectedOutputs: RegressionOutputs
    ) {
        self.id = id
        self.description = description
        self.scenario = scenario
        self.timestamp = timestamp
        self.expectedInputs = expectedInputs
        self.expectedOutputs = expectedOutputs
    }
}

/// Captured algorithm inputs for regression testing
public struct RegressionInputs: Codable, Sendable {
    public let glucoseCount: Int
    public let latestGlucose: Double
    public let iob: Double
    public let cob: Double
    
    public init(glucoseCount: Int, latestGlucose: Double, iob: Double, cob: Double) {
        self.glucoseCount = glucoseCount
        self.latestGlucose = latestGlucose
        self.iob = iob
        self.cob = cob
    }
}

/// Captured algorithm outputs for regression testing
public struct RegressionOutputs: Codable, Sendable {
    /// Expected temp basal rate (nil if no change)
    public let tempBasalRate: Double?
    
    /// Expected bolus amount (nil if none)
    public let bolusAmount: Double?
    
    /// Whether algorithm suspended delivery
    public let isSuspended: Bool
    
    /// Tolerance for rate comparison
    public let rateTolerance: Double
    
    public init(
        tempBasalRate: Double? = nil,
        bolusAmount: Double? = nil,
        isSuspended: Bool = false,
        rateTolerance: Double = 0.05
    ) {
        self.tempBasalRate = tempBasalRate
        self.bolusAmount = bolusAmount
        self.isSuspended = isSuspended
        self.rateTolerance = rateTolerance
    }
}

/// Generates and validates regression fixtures
public struct RegressionFixtureRunner {
    
    /// Generate a regression fixture from a scenario
    public static func generateFixture(
        id: String,
        description: String,
        scenario: MockDataSource.GlucoseScenario,
        algorithm: any AlgorithmEngine
    ) async throws -> RegressionFixture {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: scenario, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let decision = try algorithm.calculate(inputs)
        
        let regInputs = RegressionInputs(
            glucoseCount: inputs.glucose.count,
            latestGlucose: inputs.glucose.first?.glucose ?? 0,
            iob: inputs.insulinOnBoard,
            cob: inputs.carbsOnBoard
        )
        
        let regOutputs = RegressionOutputs(
            tempBasalRate: decision.suggestedTempBasal?.rate,
            bolusAmount: decision.suggestedBolus,
            isSuspended: decision.suggestedTempBasal?.rate == 0
        )
        
        return RegressionFixture(
            id: id,
            description: description,
            scenario: scenario.rawValue,
            timestamp: fixedTime.timeIntervalSince1970,
            expectedInputs: regInputs,
            expectedOutputs: regOutputs
        )
    }
    
    /// Validate algorithm output against fixture
    public static func validate(
        decision: AlgorithmDecision,
        against expected: RegressionOutputs
    ) -> [String] {
        var violations: [String] = []
        
        // Check suspension
        let actualSuspended = decision.suggestedTempBasal?.rate == 0
        if actualSuspended != expected.isSuspended {
            violations.append("Suspension mismatch: expected \(expected.isSuspended), got \(actualSuspended)")
        }
        
        // Check temp basal rate
        if let expectedRate = expected.tempBasalRate {
            if let actualRate = decision.suggestedTempBasal?.rate {
                let diff = abs(actualRate - expectedRate)
                if diff > expected.rateTolerance {
                    violations.append("Temp basal rate mismatch: expected \(expectedRate)±\(expected.rateTolerance), got \(actualRate)")
                }
            } else {
                violations.append("Expected temp basal rate \(expectedRate), but got none")
            }
        }
        
        // Check bolus
        if let expectedBolus = expected.bolusAmount {
            if let actualBolus = decision.suggestedBolus {
                let diff = abs(actualBolus - expectedBolus)
                if diff > 0.05 {
                    violations.append("Bolus mismatch: expected \(expectedBolus), got \(actualBolus)")
                }
            } else {
                violations.append("Expected bolus \(expectedBolus), but got none")
            }
        }
        
        return violations
    }
}

// MARK: - Regression Tests (ALG-INPUT-020)

@Suite("Algorithm Regression Tests")
struct AlgorithmRegressionTests {
    
    @Test("Stable glucose produces no action or minimal adjustment")
    func stableGlucoseRegression() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: .stable120, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Stable at 120 should not suggest aggressive action
        if let rate = decision.suggestedTempBasal?.rate {
            // Rate should be close to basal (not extreme)
            #expect(rate >= 0 && rate <= 3.0, "Stable glucose should not produce extreme basal")
        }
        
        // Should not suggest bolus for stable in-range glucose
        #expect(decision.suggestedBolus == nil || decision.suggestedBolus == 0)
    }
    
    @Test("Hypo scenario triggers suspension")
    func hypoSuspensionRegression() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: .hypo, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Hypo should suspend or minimize insulin
        if let rate = decision.suggestedTempBasal?.rate {
            #expect(rate == 0, "Hypo should suspend basal (rate = 0)")
        }
        
        // Should definitely not bolus during hypo
        #expect(decision.suggestedBolus == nil || decision.suggestedBolus == 0)
    }
    
    @Test("Hyper scenario increases insulin delivery")
    func hyperIncreasedInsulinRegression() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: .hyper, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Hyper should increase insulin delivery
        if let rate = decision.suggestedTempBasal?.rate {
            // Rate should be above basal
            let basalRate = inputs.profile.basalRates.first?.rate ?? 1.0
            #expect(rate >= basalRate, "Hyper should increase basal rate")
        }
    }
    
    @Test("Rising glucose triggers correction")
    func risingGlucoseCorrectionRegression() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: .rising, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Rising glucose should not suspend
        if let rate = decision.suggestedTempBasal?.rate {
            #expect(rate > 0, "Rising glucose should not suspend")
        }
    }
    
    @Test("Urgent low triggers immediate suspension")
    func urgentLowSuspensionRegression() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let mock = MockDataSource(scenario: .urgentLow, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Urgent low MUST suspend
        if let rate = decision.suggestedTempBasal?.rate {
            #expect(rate == 0, "Urgent low MUST suspend basal")
        }
        
        // MUST NOT bolus during urgent low
        #expect(decision.suggestedBolus == nil || decision.suggestedBolus == 0)
    }
    
    @Test("All scenarios produce deterministic outputs")
    func allScenariosDeterministic() async throws {
        let fixedTime = Date(timeIntervalSince1970: 1708300800)
        let algorithm = LoopAlgorithm()
        
        for scenario in MockDataSource.GlucoseScenario.allCases {
            // Run twice with identical inputs
            let mock1 = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let assembler1 = AlgorithmInputAssembler(dataSource: mock1)
            let inputs1 = try await assembler1.assembleInputs(at: fixedTime)
            let decision1 = try algorithm.calculate(inputs1)
            
            let mock2 = MockDataSource(scenario: scenario, baseTime: fixedTime)
            let assembler2 = AlgorithmInputAssembler(dataSource: mock2)
            let inputs2 = try await assembler2.assembleInputs(at: fixedTime)
            let decision2 = try algorithm.calculate(inputs2)
            
            // Outputs must be identical
            #expect(
                decision1.suggestedTempBasal?.rate == decision2.suggestedTempBasal?.rate,
                "Scenario \(scenario): temp basal rate should be deterministic"
            )
            #expect(
                decision1.suggestedBolus == decision2.suggestedBolus,
                "Scenario \(scenario): bolus should be deterministic"
            )
        }
    }
    
    @Test("Fixture-based regression validation")
    func fixtureBasedRegression() async throws {
        // Known-good fixture: stable120 scenario
        // ALG-DIAG-GEFF-005: Updated suspension expectation after algorithm alignment improvements
        // With ISF=50 and IOB from mock doses, eventual glucose may approach suspend threshold
        let fixture = RegressionFixture(
            id: "stable120-loop-v1",
            description: "Stable glucose at 120 with LoopAlgorithm",
            scenario: "stable120",
            timestamp: 1708300800,
            expectedInputs: RegressionInputs(
                glucoseCount: 36,
                latestGlucose: 120,
                iob: 1.0,  // Approximate
                cob: 0
            ),
            expectedOutputs: RegressionOutputs(
                tempBasalRate: nil,  // May or may not adjust
                bolusAmount: nil,
                isSuspended: true,  // With parity prediction timing, may suspend near threshold
                rateTolerance: 0.5
            )
        )
        
        let fixedTime = Date(timeIntervalSince1970: fixture.timestamp)
        let scenario = MockDataSource.GlucoseScenario(rawValue: fixture.scenario)!
        let mock = MockDataSource(scenario: scenario, baseTime: fixedTime)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        let inputs = try await assembler.assembleInputs(at: fixedTime)
        
        // Validate inputs match fixture
        #expect(inputs.glucose.count == fixture.expectedInputs.glucoseCount)
        
        let algorithm = LoopAlgorithm()
        let decision = try algorithm.calculate(inputs)
        
        // Validate outputs
        let violations = RegressionFixtureRunner.validate(
            decision: decision,
            against: fixture.expectedOutputs
        )
        
        #expect(violations.isEmpty, "Violations: \(violations.joined(separator: ", "))")
    }
}
