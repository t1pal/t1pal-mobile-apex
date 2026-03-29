// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ScenarioReplay.swift
// T1PalAlgorithm
//
// Scenario replay infrastructure for algorithm testing.
// Loads oref0-vectors and replays them through algorithms.
//
// ALG-BENCH-011: Scenario replay from fixtures

import Foundation

// MARK: - Test Vector

/// A complete test vector for algorithm replay.
public struct TestVector: Sendable, Codable, Identifiable {
    public let version: String
    public let metadata: VectorMetadata
    public let input: VectorInput
    public let expected: VectorExpected
    public let assertions: [VectorAssertion]
    public let originalOutput: OriginalOutput?
    
    public var id: String { metadata.id }
    
    public init(
        version: String = "1.0.0",
        metadata: VectorMetadata,
        input: VectorInput,
        expected: VectorExpected,
        assertions: [VectorAssertion] = [],
        originalOutput: OriginalOutput? = nil
    ) {
        self.version = version
        self.metadata = metadata
        self.input = input
        self.expected = expected
        self.assertions = assertions
        self.originalOutput = originalOutput
    }
}

/// Metadata for a test vector.
public struct VectorMetadata: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let category: String
    public let source: String
    public let description: String
    public let algorithm: String?
    
    public init(
        id: String,
        name: String,
        category: String = "general",
        source: String = "fixture",
        description: String = "",
        algorithm: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.source = source
        self.description = description
        self.algorithm = algorithm
    }
}

/// Input data for a test vector.
public struct VectorInput: Sendable, Codable, Equatable {
    public let glucoseStatus: GlucoseStatus
    public let iob: IOBStatus
    public let profile: ProfileData
    public let mealData: MealData
    public let currentTemp: TempBasalData?
    public let autosensData: AutosensData?
    public let microBolusAllowed: Bool?
    public let flatBGsDetected: Bool?
    
    public init(
        glucoseStatus: GlucoseStatus,
        iob: IOBStatus,
        profile: ProfileData,
        mealData: MealData,
        currentTemp: TempBasalData? = nil,
        autosensData: AutosensData? = nil,
        microBolusAllowed: Bool? = nil,
        flatBGsDetected: Bool? = nil
    ) {
        self.glucoseStatus = glucoseStatus
        self.iob = iob
        self.profile = profile
        self.mealData = mealData
        self.currentTemp = currentTemp
        self.autosensData = autosensData
        self.microBolusAllowed = microBolusAllowed
        self.flatBGsDetected = flatBGsDetected
    }
}

/// Glucose status snapshot.
public struct GlucoseStatus: Sendable, Codable, Equatable {
    public let glucose: Double
    public let glucoseUnit: String
    public let delta: Double
    public let shortAvgDelta: Double?
    public let longAvgDelta: Double?
    public let timestamp: String?
    public let noise: Int?
    
    public init(
        glucose: Double,
        glucoseUnit: String = "mg/dL",
        delta: Double,
        shortAvgDelta: Double? = nil,
        longAvgDelta: Double? = nil,
        timestamp: String? = nil,
        noise: Int? = nil
    ) {
        self.glucose = glucose
        self.glucoseUnit = glucoseUnit
        self.delta = delta
        self.shortAvgDelta = shortAvgDelta
        self.longAvgDelta = longAvgDelta
        self.timestamp = timestamp
        self.noise = noise
    }
}

/// IOB status.
public struct IOBStatus: Sendable, Codable, Equatable {
    public let iob: Double
    public let basalIob: Double?
    public let bolusIob: Double?
    public let activity: Double?
    public let iobWithZeroTemp: IOBWithZeroTemp?
    
    public init(
        iob: Double,
        basalIob: Double? = nil,
        bolusIob: Double? = nil,
        activity: Double? = nil,
        iobWithZeroTemp: IOBWithZeroTemp? = nil
    ) {
        self.iob = iob
        self.basalIob = basalIob
        self.bolusIob = bolusIob
        self.activity = activity
        self.iobWithZeroTemp = iobWithZeroTemp
    }
}

/// IOB with zero temp.
public struct IOBWithZeroTemp: Sendable, Codable, Equatable {
    public let iob: Double
    public let basaliob: Double?
    public let bolussnooze: Double?
    public let activity: Double?
    public let lastBolusTime: Double?
    public let time: String?
    
    public init(
        iob: Double,
        basaliob: Double? = nil,
        bolussnooze: Double? = nil,
        activity: Double? = nil,
        lastBolusTime: Double? = nil,
        time: String? = nil
    ) {
        self.iob = iob
        self.basaliob = basaliob
        self.bolussnooze = bolussnooze
        self.activity = activity
        self.lastBolusTime = lastBolusTime
        self.time = time
    }
}

/// Profile data.
public struct ProfileData: Sendable, Codable, Equatable {
    public let basalRate: Double
    public let sensitivity: Double
    public let carbRatio: Double
    public let targetLow: Double
    public let targetHigh: Double
    public let maxIob: Double?
    public let maxBasal: Double?
    public let dia: Double?
    public let maxDailyBasal: Double?
    
    public init(
        basalRate: Double,
        sensitivity: Double,
        carbRatio: Double,
        targetLow: Double,
        targetHigh: Double,
        maxIob: Double? = nil,
        maxBasal: Double? = nil,
        dia: Double? = nil,
        maxDailyBasal: Double? = nil
    ) {
        self.basalRate = basalRate
        self.sensitivity = sensitivity
        self.carbRatio = carbRatio
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.maxIob = maxIob
        self.maxBasal = maxBasal
        self.dia = dia
        self.maxDailyBasal = maxDailyBasal
    }
}

/// Meal/COB data.
public struct MealData: Sendable, Codable, Equatable {
    public let carbs: Double
    public let cob: Double
    public let lastCarbTime: Double?
    public let slopeFromMaxDeviation: Double?
    public let slopeFromMinDeviation: Double?
    
    public init(
        carbs: Double = 0,
        cob: Double = 0,
        lastCarbTime: Double? = nil,
        slopeFromMaxDeviation: Double? = nil,
        slopeFromMinDeviation: Double? = nil
    ) {
        self.carbs = carbs
        self.cob = cob
        self.lastCarbTime = lastCarbTime
        self.slopeFromMaxDeviation = slopeFromMaxDeviation
        self.slopeFromMinDeviation = slopeFromMinDeviation
    }
}

/// Current temp basal.
public struct TempBasalData: Sendable, Codable, Equatable {
    public let rate: Double
    public let duration: Int
    
    public init(rate: Double, duration: Int) {
        self.rate = rate
        self.duration = duration
    }
}

/// Autosens data.
public struct AutosensData: Sendable, Codable, Equatable {
    public let ratio: Double
    
    public init(ratio: Double = 1.0) {
        self.ratio = ratio
    }
}

/// Expected output from algorithm.
public struct VectorExpected: Sendable, Codable, Equatable {
    public let rate: Double?
    public let duration: Int?
    public let eventualBG: Double?
    public let insulinReq: Double?
    public let cob: Double?
    public let iob: Double?
    public let smb: Double?
    
    public init(
        rate: Double? = nil,
        duration: Int? = nil,
        eventualBG: Double? = nil,
        insulinReq: Double? = nil,
        cob: Double? = nil,
        iob: Double? = nil,
        smb: Double? = nil
    ) {
        self.rate = rate
        self.duration = duration
        self.eventualBG = eventualBG
        self.insulinReq = insulinReq
        self.cob = cob
        self.iob = iob
        self.smb = smb
    }
}

/// Assertion for validation.
public struct VectorAssertion: Sendable, Codable, Equatable {
    public let type: String
    public let field: String?
    public let baseline: Double?
    public let max: Double?
    public let min: Double?
    public let expected: Double?
    
    public init(
        type: String,
        field: String? = nil,
        baseline: Double? = nil,
        max: Double? = nil,
        min: Double? = nil,
        expected: Double? = nil
    ) {
        self.type = type
        self.field = field
        self.baseline = baseline
        self.max = max
        self.min = min
        self.expected = expected
    }
}

/// Original algorithm output for reference.
public struct OriginalOutput: Sendable, Codable, Equatable {
    public let temp: String?
    public let bg: Double?
    public let tick: String?
    public let eventualBG: Double?
    public let targetBG: Double?
    public let insulinReq: Double?
    public let deliverAt: String?
    public let sensitivityRatio: Double?
    public let predBGs: PredictedBGs?
    public let reason: String?
    public let rate: Double?
    public let duration: Int?
    public let units: Double?
    
    public init(
        temp: String? = nil,
        bg: Double? = nil,
        tick: String? = nil,
        eventualBG: Double? = nil,
        targetBG: Double? = nil,
        insulinReq: Double? = nil,
        deliverAt: String? = nil,
        sensitivityRatio: Double? = nil,
        predBGs: PredictedBGs? = nil,
        reason: String? = nil,
        rate: Double? = nil,
        duration: Int? = nil,
        units: Double? = nil
    ) {
        self.temp = temp
        self.bg = bg
        self.tick = tick
        self.eventualBG = eventualBG
        self.targetBG = targetBG
        self.insulinReq = insulinReq
        self.deliverAt = deliverAt
        self.sensitivityRatio = sensitivityRatio
        self.predBGs = predBGs
        self.reason = reason
        self.rate = rate
        self.duration = duration
        self.units = units
    }
}

/// Predicted blood glucose arrays.
public struct PredictedBGs: Sendable, Codable, Equatable {
    public let IOB: [Double]?
    public let COB: [Double]?
    public let UAM: [Double]?
    public let ZT: [Double]?
    
    public init(
        IOB: [Double]? = nil,
        COB: [Double]? = nil,
        UAM: [Double]? = nil,
        ZT: [Double]? = nil
    ) {
        self.IOB = IOB
        self.COB = COB
        self.UAM = UAM
        self.ZT = ZT
    }
}

// MARK: - Replay Result

/// Result from replaying a single test vector.
public struct ReplayResult: Sendable, Equatable, Identifiable {
    public let id: String
    public let vectorId: String
    public let success: Bool
    public let actual: ReplayOutput
    public let expected: VectorExpected
    public let divergences: [Divergence]
    public let executionTimeMs: Int
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        vectorId: String,
        success: Bool,
        actual: ReplayOutput,
        expected: VectorExpected,
        divergences: [Divergence] = [],
        executionTimeMs: Int = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.vectorId = vectorId
        self.success = success
        self.actual = actual
        self.expected = expected
        self.divergences = divergences
        self.executionTimeMs = executionTimeMs
        self.timestamp = timestamp
    }
}

/// Actual output from algorithm replay.
public struct ReplayOutput: Sendable, Equatable, Codable {
    public let rate: Double?
    public let duration: Int?
    public let eventualBG: Double?
    public let insulinReq: Double?
    public let smb: Double?
    public let reason: String?
    
    public init(
        rate: Double? = nil,
        duration: Int? = nil,
        eventualBG: Double? = nil,
        insulinReq: Double? = nil,
        smb: Double? = nil,
        reason: String? = nil
    ) {
        self.rate = rate
        self.duration = duration
        self.eventualBG = eventualBG
        self.insulinReq = insulinReq
        self.smb = smb
        self.reason = reason
    }
}

/// A divergence between expected and actual output.
public struct Divergence: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable {
        case info
        case warning
        case error
        case critical
    }
    
    public let field: String
    public let expected: String
    public let actual: String
    public let delta: Double?
    public let severity: Severity
    public let message: String
    
    public init(
        field: String,
        expected: String,
        actual: String,
        delta: Double? = nil,
        severity: Severity = .warning,
        message: String = ""
    ) {
        self.field = field
        self.expected = expected
        self.actual = actual
        self.delta = delta
        self.severity = severity
        self.message = message.isEmpty ? "\(field): expected \(expected), got \(actual)" : message
    }
}

// MARK: - Replay Session

/// A session for replaying multiple test vectors.
public struct ReplaySession: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let startTime: Date
    public var endTime: Date?
    public var results: [ReplayResult]
    public let vectorCount: Int
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date = Date(),
        vectorCount: Int
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = nil
        self.results = []
        self.vectorCount = vectorCount
    }
    
    public var completedCount: Int { results.count }
    public var successCount: Int { results.filter { $0.success }.count }
    public var failureCount: Int { results.filter { !$0.success }.count }
    
    public var successRate: Double {
        guard !results.isEmpty else { return 0 }
        return Double(successCount) / Double(results.count)
    }
    
    public var isComplete: Bool { results.count >= vectorCount }
    
    public var durationSeconds: Double {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    public var averageExecutionTimeMs: Int {
        guard !results.isEmpty else { return 0 }
        return results.map { $0.executionTimeMs }.reduce(0, +) / results.count
    }
    
    public mutating func addResult(_ result: ReplayResult) {
        results.append(result)
        if results.count >= vectorCount {
            endTime = Date()
        }
    }
}

// MARK: - Vector Loader

/// Protocol for loading test vectors.
public protocol VectorLoader: Sendable {
    /// Load all available vectors.
    func loadAll() async throws -> [TestVector]
    
    /// Load vectors matching a category.
    func loadByCategory(_ category: String) async throws -> [TestVector]
    
    /// Load a specific vector by ID.
    func load(id: String) async throws -> TestVector?
    
    /// List available vector IDs.
    func listVectorIds() async throws -> [String]
}

/// Loads test vectors from JSON files.
public actor FileVectorLoader: VectorLoader {
    private let directory: URL
    private var cache: [String: TestVector] = [:]
    
    public init(directory: URL) {
        self.directory = directory
    }
    
    public func loadAll() async throws -> [TestVector] {
        let ids = try await listVectorIds()
        var vectors: [TestVector] = []
        
        for id in ids {
            if let vector = try await load(id: id) {
                vectors.append(vector)
            }
        }
        
        return vectors
    }
    
    public func loadByCategory(_ category: String) async throws -> [TestVector] {
        let all = try await loadAll()
        return all.filter { $0.metadata.category == category }
    }
    
    public func load(id: String) async throws -> TestVector? {
        if let cached = cache[id] {
            return cached
        }
        
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let vector = try JSONDecoder().decode(TestVector.self, from: data)
            cache[vector.metadata.id] = vector
            
            if vector.metadata.id == id {
                return vector
            }
        }
        
        return nil
    }
    
    public func listVectorIds() async throws -> [String] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        
        var ids: [String] = []
        for file in files where file.pathExtension == "json" {
            // Extract ID from filename (TV-001-timestamp.json -> TV-001)
            let name = file.deletingPathExtension().lastPathComponent
            if let dashIndex = name.firstIndex(of: "-"),
               let secondDash = name[name.index(after: dashIndex)...].firstIndex(of: "-") {
                let id = String(name[..<secondDash])
                ids.append(id)
            } else {
                ids.append(name)
            }
        }
        
        return ids.sorted()
    }
}

/// In-memory vector loader for testing.
public actor MemoryVectorLoader: VectorLoader {
    private var vectors: [TestVector]
    
    public init(vectors: [TestVector] = []) {
        self.vectors = vectors
    }
    
    public func add(_ vector: TestVector) {
        vectors.append(vector)
    }
    
    public func loadAll() async throws -> [TestVector] {
        vectors
    }
    
    public func loadByCategory(_ category: String) async throws -> [TestVector] {
        vectors.filter { $0.metadata.category == category }
    }
    
    public func load(id: String) async throws -> TestVector? {
        vectors.first { $0.metadata.id == id }
    }
    
    public func listVectorIds() async throws -> [String] {
        vectors.map { $0.metadata.id }
    }
}

// MARK: - Replay Report

/// Summary report from a replay session.
public struct ReplayReport: Sendable {
    public let session: ReplaySession
    public let categories: [String: CategoryStats]
    public let divergencesByField: [String: Int]
    
    public init(_ session: ReplaySession) {
        self.session = session
        
        let cats: [String: (total: Int, success: Int)] = [:]
        var divFields: [String: Int] = [:]
        
        for result in session.results {
            for div in result.divergences {
                divFields[div.field, default: 0] += 1
            }
        }
        
        self.categories = cats.mapValues { CategoryStats(total: $0.total, success: $0.success) }
        self.divergencesByField = divFields
    }
    
    public var text: String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════")
        lines.append("REPLAY SESSION REPORT: \(session.name)")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        
        lines.append("Duration: \(String(format: "%.2f", session.durationSeconds))s")
        lines.append("Vectors: \(session.completedCount)/\(session.vectorCount)")
        lines.append("")
        
        lines.append("─── RESULTS ───")
        lines.append("✅ Passed: \(session.successCount)")
        lines.append("❌ Failed: \(session.failureCount)")
        lines.append("Success Rate: \(String(format: "%.1f%%", session.successRate * 100))")
        lines.append("Avg Execution: \(session.averageExecutionTimeMs)ms")
        lines.append("")
        
        if !divergencesByField.isEmpty {
            lines.append("─── DIVERGENCES BY FIELD ───")
            for (field, count) in divergencesByField.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(field): \(count)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

/// Statistics for a category.
public struct CategoryStats: Sendable {
    public let total: Int
    public let success: Int
    public var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(success) / Double(total)
    }
    
    public init(total: Int, success: Int) {
        self.total = total
        self.success = success
    }
}

// MARK: - Result Comparator

/// Compares actual output to expected output.
public struct ResultComparator: Sendable {
    public let tolerances: Tolerances
    
    public struct Tolerances: Sendable {
        public let rateTolerance: Double
        public let bgTolerance: Double
        public let insulinTolerance: Double
        public let durationTolerance: Int
        
        public init(
            rateTolerance: Double = 0.05,
            bgTolerance: Double = 5.0,
            insulinTolerance: Double = 0.05,
            durationTolerance: Int = 5
        ) {
            self.rateTolerance = rateTolerance
            self.bgTolerance = bgTolerance
            self.insulinTolerance = insulinTolerance
            self.durationTolerance = durationTolerance
        }
        
        public static let `default` = Tolerances()
        public static let strict = Tolerances(rateTolerance: 0.01, bgTolerance: 1.0, insulinTolerance: 0.01, durationTolerance: 0)
        public static let lenient = Tolerances(rateTolerance: 0.1, bgTolerance: 10.0, insulinTolerance: 0.1, durationTolerance: 10)
    }
    
    public init(tolerances: Tolerances = .default) {
        self.tolerances = tolerances
    }
    
    public func compare(actual: ReplayOutput, expected: VectorExpected) -> [Divergence] {
        var divergences: [Divergence] = []
        
        if let expRate = expected.rate, let actRate = actual.rate {
            let delta = abs(expRate - actRate)
            if delta > tolerances.rateTolerance {
                divergences.append(Divergence(
                    field: "rate",
                    expected: String(format: "%.3f", expRate),
                    actual: String(format: "%.3f", actRate),
                    delta: delta,
                    severity: delta > tolerances.rateTolerance * 2 ? .error : .warning
                ))
            }
        }
        
        if let expDur = expected.duration, let actDur = actual.duration {
            let delta = abs(expDur - actDur)
            if delta > tolerances.durationTolerance {
                divergences.append(Divergence(
                    field: "duration",
                    expected: "\(expDur)",
                    actual: "\(actDur)",
                    delta: Double(delta),
                    severity: delta > tolerances.durationTolerance * 2 ? .error : .warning
                ))
            }
        }
        
        if let expBG = expected.eventualBG, let actBG = actual.eventualBG {
            let delta = abs(expBG - actBG)
            if delta > tolerances.bgTolerance {
                divergences.append(Divergence(
                    field: "eventualBG",
                    expected: String(format: "%.1f", expBG),
                    actual: String(format: "%.1f", actBG),
                    delta: delta,
                    severity: delta > tolerances.bgTolerance * 2 ? .error : .warning
                ))
            }
        }
        
        if let expIns = expected.insulinReq, let actIns = actual.insulinReq {
            let delta = abs(expIns - actIns)
            if delta > tolerances.insulinTolerance {
                divergences.append(Divergence(
                    field: "insulinReq",
                    expected: String(format: "%.3f", expIns),
                    actual: String(format: "%.3f", actIns),
                    delta: delta,
                    severity: delta > tolerances.insulinTolerance * 2 ? .error : .warning
                ))
            }
        }
        
        return divergences
    }
}
