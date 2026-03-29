// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CrossAlgorithmIOBFixtures.swift
// T1Pal Mobile
//
// Cross-algorithm IOB validation fixtures and generator
// Requirements: REQ-ALGO-006
//
// This module provides:
// - JSON-serializable fixture format for IOB scenarios
// - Fixture generator using all three algorithm calculators
// - Validation utilities for regression testing
//
// Trace: ALG-NET-004, PRD-009

import Foundation
import T1PalCore

// MARK: - Fixture Data Structures

/// Complete IOB scenario fixture for cross-algorithm validation
///
/// Includes inputs (doses, basal schedule, test time) and expected outputs
/// from all three algorithms (Loop, oref0, GlucOS).
///
/// **Fixture Format:**
/// ```json
/// {
///   "id": "BOLUS-001",
///   "description": "Simple 5U bolus at t=0",
///   "inputs": { ... },
///   "expected": {
///     "loop": { "iob": 4.2, "activity": 0.02 },
///     "oref0": { "iob": 4.1, "activity": 0.019 },
///     "glucos": { "iob": 4.1, "activity": 0.019 }
///   },
///   "metadata": { ... }
/// }
/// ```
///
/// Trace: ALG-NET-004
public struct IOBScenarioFixture: Codable, Sendable {
    /// Unique scenario identifier (e.g., "BOLUS-001", "TEMPBASAL-005")
    public let id: String
    
    /// Human-readable description of the scenario
    public let description: String
    
    /// Scenario input data
    public let inputs: IOBScenarioInputs
    
    /// Expected outputs from each algorithm
    public let expected: IOBExpectedOutputs
    
    /// Fixture metadata
    public let metadata: IOBFixtureMetadata
    
    public init(
        id: String,
        description: String,
        inputs: IOBScenarioInputs,
        expected: IOBExpectedOutputs,
        metadata: IOBFixtureMetadata
    ) {
        self.id = id
        self.description = description
        self.inputs = inputs
        self.expected = expected
        self.metadata = metadata
    }
}

/// Input data for an IOB scenario
public struct IOBScenarioInputs: Codable, Sendable {
    /// Insulin doses (boluses and temp basals)
    public let doses: [IOBDoseEntry]
    
    /// Basal schedule entries
    public let basalSchedule: [IOBBasalEntry]
    
    /// Time to calculate IOB at (ISO8601)
    public let evaluationTime: String
    
    /// Insulin type (novolog, humalog, fiasp, etc.)
    public let insulinType: String
    
    /// Duration of insulin action in hours
    public let dia: Double
    
    /// Reference time for relative dose timestamps (ISO8601)
    public let referenceTime: String
    
    public init(
        doses: [IOBDoseEntry],
        basalSchedule: [IOBBasalEntry],
        evaluationTime: String,
        insulinType: String = "novolog",
        dia: Double = 6.0,
        referenceTime: String
    ) {
        self.doses = doses
        self.basalSchedule = basalSchedule
        self.evaluationTime = evaluationTime
        self.insulinType = insulinType
        self.dia = dia
        self.referenceTime = referenceTime
    }
}

/// Dose entry in fixture format
public struct IOBDoseEntry: Codable, Sendable {
    /// Dose type: "bolus", "tempBasal", "suspend"
    public let type: String
    
    /// Dose start time (ISO8601)
    public let startTime: String
    
    /// Dose end time (ISO8601, same as start for bolus)
    public let endTime: String
    
    /// Units delivered
    public let units: Double
    
    /// For temp basals: the rate in U/hr
    public let rate: Double?
    
    public init(
        type: String,
        startTime: String,
        endTime: String,
        units: Double,
        rate: Double? = nil
    ) {
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.units = units
        self.rate = rate
    }
}

/// Basal schedule entry in fixture format
public struct IOBBasalEntry: Codable, Sendable {
    /// Start time as seconds from midnight
    public let startTime: Int
    
    /// Rate in U/hr
    public let rate: Double
    
    public init(startTime: Int, rate: Double) {
        self.startTime = startTime
        self.rate = rate
    }
}

/// Expected outputs from all three algorithms
public struct IOBExpectedOutputs: Codable, Sendable {
    /// Loop algorithm expected output
    public let loop: IOBAlgorithmOutput
    
    /// oref0 algorithm expected output
    public let oref0: IOBAlgorithmOutput
    
    /// GlucOS algorithm expected output
    public let glucos: IOBAlgorithmOutput
    
    /// Maximum acceptable difference between algorithms
    public let tolerance: Double
    
    public init(
        loop: IOBAlgorithmOutput,
        oref0: IOBAlgorithmOutput,
        glucos: IOBAlgorithmOutput,
        tolerance: Double = 0.1
    ) {
        self.loop = loop
        self.oref0 = oref0
        self.glucos = glucos
        self.tolerance = tolerance
    }
}

/// Single algorithm's expected output
public struct IOBAlgorithmOutput: Codable, Sendable {
    /// Insulin on board (units)
    public let iob: Double
    
    /// Insulin activity (units/hour)
    public let activity: Double
    
    public init(iob: Double, activity: Double) {
        self.iob = iob
        self.activity = activity
    }
}

/// Fixture metadata
public struct IOBFixtureMetadata: Codable, Sendable {
    /// Version of fixture format
    public let version: String
    
    /// When fixture was generated (ISO8601)
    public let generatedAt: String
    
    /// Generator tool/version
    public let generator: String
    
    /// Category (e.g., "bolus", "tempBasal", "mixed", "edgeCase")
    public let category: String
    
    /// Tags for filtering
    public let tags: [String]
    
    public init(
        version: String = "1.0",
        generatedAt: String,
        generator: String = "T1PalAlgorithm/CrossAlgorithmIOBFixtures",
        category: String,
        tags: [String] = []
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.generator = generator
        self.category = category
        self.tags = tags
    }
}

// MARK: - Fixture Generator

/// Generates cross-algorithm IOB validation fixtures
///
/// Creates fixtures by running scenarios through all three algorithm
/// implementations and recording the results.
///
/// **Usage:**
/// ```swift
/// let generator = IOBFixtureGenerator()
/// let fixtures = generator.generateStandardScenarios()
/// let json = try generator.exportAsJSON(fixtures)
/// ```
///
/// Trace: ALG-NET-004
public struct IOBFixtureGenerator: Sendable {
    private let loopCalculator: LoopNetBasalIOBCalculator
    private let oref0Calculator: Oref0NetBasalIOBCalculator
    private let glucosCalculator: GlucOSNetBasalIOBCalculator
    
    /// ISO8601 date formatter
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    public init(
        insulinType: InsulinType = .novolog,
        dia: Double = 6.0
    ) {
        // Loop uses its own model (uses default preset for now)
        self.loopCalculator = LoopNetBasalIOBCalculator()
        // oref0 and GlucOS use InsulinModel with type and DIA
        self.oref0Calculator = Oref0NetBasalIOBCalculator(
            insulinType: insulinType,
            dia: dia
        )
        self.glucosCalculator = GlucOSNetBasalIOBCalculator(
            insulinType: insulinType,
            dia: dia
        )
    }
    
    // MARK: - Scenario Generation
    
    /// Generate all standard validation scenarios
    public func generateStandardScenarios() -> [IOBScenarioFixture] {
        var fixtures: [IOBScenarioFixture] = []
        
        // Bolus scenarios
        fixtures.append(contentsOf: generateBolusScenarios())
        
        // Temp basal scenarios
        fixtures.append(contentsOf: generateTempBasalScenarios())
        
        // Mixed scenarios
        fixtures.append(contentsOf: generateMixedScenarios())
        
        // Edge case scenarios
        fixtures.append(contentsOf: generateEdgeCaseScenarios())
        
        return fixtures
    }
    
    /// Generate bolus-only scenarios
    public func generateBolusScenarios() -> [IOBScenarioFixture] {
        let referenceDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z
        let basalSchedule = createSimpleBasalSchedule(rate: 1.0)
        
        var fixtures: [IOBScenarioFixture] = []
        
        // BOLUS-001: Simple 5U bolus at t=0, check at t=0
        fixtures.append(createFixture(
            id: "BOLUS-001",
            description: "5U bolus at t=0, check immediately",
            doses: [createBolus(units: 5.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate,
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["simple", "immediate"]
        ))
        
        // BOLUS-002: 5U bolus, check at 1 hour
        fixtures.append(createFixture(
            id: "BOLUS-002",
            description: "5U bolus at t=0, check at t=1h",
            doses: [createBolus(units: 5.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["simple", "decay"]
        ))
        
        // BOLUS-003: 5U bolus, check at 2 hours
        fixtures.append(createFixture(
            id: "BOLUS-003",
            description: "5U bolus at t=0, check at t=2h",
            doses: [createBolus(units: 5.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(7200),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["simple", "decay"]
        ))
        
        // BOLUS-004: 5U bolus, check at 4 hours
        fixtures.append(createFixture(
            id: "BOLUS-004",
            description: "5U bolus at t=0, check at t=4h",
            doses: [createBolus(units: 5.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(14400),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["simple", "decay", "late"]
        ))
        
        // BOLUS-005: 5U bolus, check at DIA (should be ~0)
        fixtures.append(createFixture(
            id: "BOLUS-005",
            description: "5U bolus at t=0, check at t=DIA (6h)",
            doses: [createBolus(units: 5.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(21600),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["simple", "complete"]
        ))
        
        // BOLUS-006: Multiple stacked boluses
        fixtures.append(createFixture(
            id: "BOLUS-006",
            description: "Stacked boluses: 3U at t=0, 2U at t=30m",
            doses: [
                createBolus(units: 3.0, at: referenceDate),
                createBolus(units: 2.0, at: referenceDate.addingTimeInterval(1800))
            ],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["stacked", "multiple"]
        ))
        
        // BOLUS-007: Small bolus (precision test)
        fixtures.append(createFixture(
            id: "BOLUS-007",
            description: "Small 0.5U bolus precision test",
            doses: [createBolus(units: 0.5, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(1800),
            referenceTime: referenceDate,
            category: "bolus",
            tags: ["precision", "small"]
        ))
        
        return fixtures
    }
    
    /// Generate temp basal scenarios
    public func generateTempBasalScenarios() -> [IOBScenarioFixture] {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        let basalSchedule = createSimpleBasalSchedule(rate: 1.0)
        
        var fixtures: [IOBScenarioFixture] = []
        
        // TEMPBASAL-001: High temp basal (2 U/hr for 30 min)
        fixtures.append(createFixture(
            id: "TEMPBASAL-001",
            description: "High temp basal 2 U/hr for 30m, check at 1h",
            doses: [createTempBasal(rate: 2.0, duration: 1800, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "tempBasal",
            tags: ["high", "short"]
        ))
        
        // TEMPBASAL-002: Zero temp (suspend) for 30 min
        fixtures.append(createFixture(
            id: "TEMPBASAL-002",
            description: "Zero temp (suspend) for 30m, check at 1h",
            doses: [createTempBasal(rate: 0.0, duration: 1800, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "tempBasal",
            tags: ["suspend", "negative"]
        ))
        
        // TEMPBASAL-003: Temp at scheduled rate (net zero)
        fixtures.append(createFixture(
            id: "TEMPBASAL-003",
            description: "Temp at scheduled rate (1 U/hr) - net zero",
            doses: [createTempBasal(rate: 1.0, duration: 3600, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "tempBasal",
            tags: ["neutral", "net-zero"]
        ))
        
        // TEMPBASAL-004: Max temp basal scenario
        fixtures.append(createFixture(
            id: "TEMPBASAL-004",
            description: "Max temp basal 5 U/hr for 1h",
            doses: [createTempBasal(rate: 5.0, duration: 3600, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "tempBasal",
            tags: ["max", "aggressive"]
        ))
        
        // TEMPBASAL-005: Consecutive temp basals
        fixtures.append(createFixture(
            id: "TEMPBASAL-005",
            description: "Consecutive temps: 2 U/hr 30m then 0.5 U/hr 30m",
            doses: [
                createTempBasal(rate: 2.0, duration: 1800, at: referenceDate),
                createTempBasal(rate: 0.5, duration: 1800, at: referenceDate.addingTimeInterval(1800))
            ],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "tempBasal",
            tags: ["consecutive", "varying"]
        ))
        
        return fixtures
    }
    
    /// Generate mixed bolus + temp basal scenarios
    public func generateMixedScenarios() -> [IOBScenarioFixture] {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        let basalSchedule = createSimpleBasalSchedule(rate: 1.0)
        
        var fixtures: [IOBScenarioFixture] = []
        
        // MIXED-001: Bolus + high temp
        fixtures.append(createFixture(
            id: "MIXED-001",
            description: "5U bolus + 2 U/hr temp for 30m",
            doses: [
                createBolus(units: 5.0, at: referenceDate),
                createTempBasal(rate: 2.0, duration: 1800, at: referenceDate)
            ],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "mixed",
            tags: ["bolus", "tempBasal"]
        ))
        
        // MIXED-002: Correction + suspend
        fixtures.append(createFixture(
            id: "MIXED-002",
            description: "2U correction + immediate suspend",
            doses: [
                createBolus(units: 2.0, at: referenceDate),
                createTempBasal(rate: 0.0, duration: 3600, at: referenceDate)
            ],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "mixed",
            tags: ["correction", "suspend"]
        ))
        
        // MIXED-003: Meal scenario
        fixtures.append(createFixture(
            id: "MIXED-003",
            description: "Meal: 8U bolus + high temps over 2h",
            doses: [
                createBolus(units: 8.0, at: referenceDate),
                createTempBasal(rate: 2.5, duration: 3600, at: referenceDate),
                createTempBasal(rate: 1.5, duration: 3600, at: referenceDate.addingTimeInterval(3600))
            ],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(7200),
            referenceTime: referenceDate,
            category: "mixed",
            tags: ["meal", "extended"]
        ))
        
        return fixtures
    }
    
    /// Generate edge case scenarios
    public func generateEdgeCaseScenarios() -> [IOBScenarioFixture] {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        let basalSchedule = createSimpleBasalSchedule(rate: 1.0)
        
        var fixtures: [IOBScenarioFixture] = []
        
        // EDGE-001: Empty doses
        fixtures.append(createFixture(
            id: "EDGE-001",
            description: "No doses - should be zero IOB",
            doses: [],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate,
            referenceTime: referenceDate,
            category: "edgeCase",
            tags: ["empty", "zero"]
        ))
        
        // EDGE-002: Very old dose (past DIA)
        fixtures.append(createFixture(
            id: "EDGE-002",
            description: "Dose from 8h ago (past DIA)",
            doses: [createBolus(units: 5.0, at: referenceDate.addingTimeInterval(-28800))],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate,
            referenceTime: referenceDate,
            category: "edgeCase",
            tags: ["expired", "zero"]
        ))
        
        // EDGE-003: Future dose
        fixtures.append(createFixture(
            id: "EDGE-003",
            description: "Future dose (should be zero IOB)",
            doses: [createBolus(units: 5.0, at: referenceDate.addingTimeInterval(3600))],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate,
            referenceTime: referenceDate,
            category: "edgeCase",
            tags: ["future", "zero"]
        ))
        
        // EDGE-004: Micro dose
        fixtures.append(createFixture(
            id: "EDGE-004",
            description: "Micro dose 0.05U",
            doses: [createBolus(units: 0.05, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(1800),
            referenceTime: referenceDate,
            category: "edgeCase",
            tags: ["micro", "precision"]
        ))
        
        // EDGE-005: Large bolus
        fixtures.append(createFixture(
            id: "EDGE-005",
            description: "Large 20U bolus",
            doses: [createBolus(units: 20.0, at: referenceDate)],
            basalSchedule: basalSchedule,
            evaluationTime: referenceDate.addingTimeInterval(3600),
            referenceTime: referenceDate,
            category: "edgeCase",
            tags: ["large", "scale"]
        ))
        
        return fixtures
    }
    
    // MARK: - Fixture Creation Helpers
    
    private func createFixture(
        id: String,
        description: String,
        doses: [InsulinDose],
        basalSchedule: [AbsoluteScheduleValue<Double>],
        evaluationTime: Date,
        referenceTime: Date,
        category: String,
        tags: [String]
    ) -> IOBScenarioFixture {
        let delta = IOBConstants.defaultDelta
        
        // Calculate outputs from all three algorithms
        let loopIOB = loopCalculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        let loopActivity = loopCalculator.insulinActivityNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        
        let oref0IOB = oref0Calculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        let oref0Activity = oref0Calculator.insulinActivityNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        
        let glucosIOB = glucosCalculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        let glucosActivity = glucosCalculator.insulinActivityNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evaluationTime, delta: delta
        )
        
        // Convert doses to fixture format
        let doseEntries = doses.map { dose -> IOBDoseEntry in
            // Determine type from source string
            let typeStr = dose.source.contains("temp") ? "tempBasal" : "bolus"
            let dateStr = Self.dateFormatter.string(from: dose.timestamp)
            
            return IOBDoseEntry(
                type: typeStr,
                startTime: dateStr,
                endTime: dateStr,
                units: dose.units,
                rate: nil
            )
        }
        
        // Convert basal schedule to fixture format
        let basalEntries = basalSchedule.map { entry -> IOBBasalEntry in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute, .second], from: entry.startDate)
            let secondsFromMidnight = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
            return IOBBasalEntry(startTime: secondsFromMidnight, rate: entry.value)
        }
        
        // Calculate tolerance based on max difference
        let maxDiff = max(abs(loopIOB - oref0IOB), abs(loopIOB - glucosIOB), abs(oref0IOB - glucosIOB))
        let tolerance = max(0.1, maxDiff * 1.1) // 10% margin over observed difference
        
        return IOBScenarioFixture(
            id: id,
            description: description,
            inputs: IOBScenarioInputs(
                doses: doseEntries,
                basalSchedule: basalEntries,
                evaluationTime: Self.dateFormatter.string(from: evaluationTime),
                insulinType: "novolog",
                dia: 6.0,
                referenceTime: Self.dateFormatter.string(from: referenceTime)
            ),
            expected: IOBExpectedOutputs(
                loop: IOBAlgorithmOutput(iob: loopIOB, activity: loopActivity),
                oref0: IOBAlgorithmOutput(iob: oref0IOB, activity: oref0Activity),
                glucos: IOBAlgorithmOutput(iob: glucosIOB, activity: glucosActivity),
                tolerance: tolerance
            ),
            metadata: IOBFixtureMetadata(
                generatedAt: Self.dateFormatter.string(from: Date()),
                category: category,
                tags: tags
            )
        )
    }
    
    private func createBolus(units: Double, at date: Date) -> InsulinDose {
        InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "bolus"
        )
    }
    
    private func createTempBasal(rate: Double, duration: TimeInterval, at date: Date) -> InsulinDose {
        // For simplicity, we create multiple 5-min segments
        // But for now, just create a single dose representing the total
        let units = rate * (duration / 3600)
        return InsulinDose(
            id: UUID(),
            units: units,
            timestamp: date,
            source: "temp_basal"
        )
    }
    
    private func createSimpleBasalSchedule(rate: Double) -> [AbsoluteScheduleValue<Double>] {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        let midnight = Calendar.current.startOfDay(for: referenceDate)
        return [
            AbsoluteScheduleValue(startDate: midnight, endDate: midnight.addingTimeInterval(86400), value: rate)
        ]
    }
    
    // MARK: - Export
    
    /// Export fixtures as JSON
    public func exportAsJSON(_ fixtures: [IOBScenarioFixture]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(fixtures)
    }
    
    /// Export fixtures as JSON string
    public func exportAsJSONString(_ fixtures: [IOBScenarioFixture]) throws -> String {
        let data = try exportAsJSON(fixtures)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Fixture Validation

/// Validates scenarios against expected outputs
public struct IOBFixtureValidator: Sendable {
    private let loopCalculator: LoopNetBasalIOBCalculator
    private let oref0Calculator: Oref0NetBasalIOBCalculator
    private let glucosCalculator: GlucOSNetBasalIOBCalculator
    
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    public init(insulinType: InsulinType = .novolog, dia: Double = 6.0) {
        self.loopCalculator = LoopNetBasalIOBCalculator()
        self.oref0Calculator = Oref0NetBasalIOBCalculator(insulinType: insulinType, dia: dia)
        self.glucosCalculator = GlucOSNetBasalIOBCalculator(insulinType: insulinType, dia: dia)
    }
    
    /// Validation result for a single fixture
    public struct ValidationResult: Sendable {
        public let fixtureId: String
        public let passed: Bool
        public let loopDiff: Double
        public let oref0Diff: Double
        public let glucosDiff: Double
        public let message: String
        
        public init(fixtureId: String, passed: Bool, loopDiff: Double, oref0Diff: Double, glucosDiff: Double, message: String) {
            self.fixtureId = fixtureId
            self.passed = passed
            self.loopDiff = loopDiff
            self.oref0Diff = oref0Diff
            self.glucosDiff = glucosDiff
            self.message = message
        }
    }
    
    /// Validate a single fixture
    public func validate(_ fixture: IOBScenarioFixture) -> ValidationResult {
        // Parse inputs
        guard let evalTime = Self.dateFormatter.date(from: fixture.inputs.evaluationTime) else {
            return ValidationResult(
                fixtureId: fixture.id,
                passed: false,
                loopDiff: 0, oref0Diff: 0, glucosDiff: 0,
                message: "Failed to parse evaluation time"
            )
        }
        
        let doses = parseDoses(fixture.inputs.doses)
        let basalSchedule = parseBasalSchedule(fixture.inputs.basalSchedule, referenceTime: fixture.inputs.referenceTime)
        
        let delta = IOBConstants.defaultDelta
        
        // Calculate actual values
        let actualLoopIOB = loopCalculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evalTime, delta: delta
        )
        let actualOref0IOB = oref0Calculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evalTime, delta: delta
        )
        let actualGlucosIOB = glucosCalculator.insulinOnBoardNetBasal(
            doses: doses, basalSchedule: basalSchedule, at: evalTime, delta: delta
        )
        
        // Compare with expected
        let loopDiff = abs(actualLoopIOB - fixture.expected.loop.iob)
        let oref0Diff = abs(actualOref0IOB - fixture.expected.oref0.iob)
        let glucosDiff = abs(actualGlucosIOB - fixture.expected.glucos.iob)
        
        let tolerance = fixture.expected.tolerance
        let passed = loopDiff <= tolerance && oref0Diff <= tolerance && glucosDiff <= tolerance
        
        let message = passed
            ? "All algorithms within tolerance"
            : "Differences exceed tolerance: Loop=\(loopDiff), oref0=\(oref0Diff), GlucOS=\(glucosDiff)"
        
        return ValidationResult(
            fixtureId: fixture.id,
            passed: passed,
            loopDiff: loopDiff,
            oref0Diff: oref0Diff,
            glucosDiff: glucosDiff,
            message: message
        )
    }
    
    /// Validate all fixtures
    public func validateAll(_ fixtures: [IOBScenarioFixture]) -> [ValidationResult] {
        fixtures.map { validate($0) }
    }
    
    private func parseDoses(_ entries: [IOBDoseEntry]) -> [InsulinDose] {
        entries.compactMap { entry -> InsulinDose? in
            guard let startDate = Self.dateFormatter.date(from: entry.startTime) else {
                return nil
            }
            
            // Map entry type to source string
            let source = entry.type.contains("temp") ? "temp_basal" : "bolus"
            
            return InsulinDose(
                id: UUID(),
                units: entry.units,
                timestamp: startDate,
                source: source
            )
        }
    }
    
    private func parseBasalSchedule(_ entries: [IOBBasalEntry], referenceTime: String) -> [AbsoluteScheduleValue<Double>] {
        guard let refDate = Self.dateFormatter.date(from: referenceTime) else {
            return []
        }
        
        let midnight = Calendar.current.startOfDay(for: refDate)
        
        return entries.map { entry in
            let startDate = midnight.addingTimeInterval(Double(entry.startTime))
            let endDate = midnight.addingTimeInterval(86400) // Next midnight
            return AbsoluteScheduleValue(startDate: startDate, endDate: endDate, value: entry.rate)
        }
    }
}

// MARK: - Fixture File Manager

/// Manages fixture file I/O
public struct IOBFixtureFileManager: Sendable {
    private let fixturesDirectory: URL
    
    public init(fixturesDirectory: URL) {
        self.fixturesDirectory = fixturesDirectory
    }
    
    /// Load fixtures from JSON file
    public func loadFixtures(from filename: String) throws -> [IOBScenarioFixture] {
        let url = fixturesDirectory.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([IOBScenarioFixture].self, from: data)
    }
    
    /// Save fixtures to JSON file
    public func saveFixtures(_ fixtures: [IOBScenarioFixture], to filename: String) throws {
        let url = fixturesDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixtures)
        try data.write(to: url)
    }
}
