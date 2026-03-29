// ScenarioReplayTests.swift
// T1PalAlgorithm Tests
//
// Tests for ScenarioReplay infrastructure.
// ALG-BENCH-011: Scenario replay from fixtures

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Test Vector Tests

@Suite("Test Vector")
struct TestVectorTests {
    
    @Test("Vector creation with metadata")
    func vectorCreation() {
        let metadata = VectorMetadata(
            id: "TV-001",
            name: "Test Vector 1",
            category: "basal-adjustment",
            source: "fixture"
        )
        
        let input = VectorInput(
            glucoseStatus: GlucoseStatus(glucose: 120, delta: 5),
            iob: IOBStatus(iob: 0.5),
            profile: ProfileData(
                basalRate: 1.0,
                sensitivity: 50,
                carbRatio: 10,
                targetLow: 100,
                targetHigh: 110
            ),
            mealData: MealData()
        )
        
        let expected = VectorExpected(rate: 1.2, duration: 30)
        
        let vector = TestVector(
            metadata: metadata,
            input: input,
            expected: expected
        )
        
        #expect(vector.id == "TV-001")
        #expect(vector.metadata.category == "basal-adjustment")
        #expect(vector.input.glucoseStatus.glucose == 120)
        #expect(vector.expected.rate == 1.2)
    }
    
    @Test("Vector is Identifiable")
    func identifiable() {
        let vector = TestVector(
            metadata: VectorMetadata(id: "test-id", name: "Test"),
            input: VectorInput(
                glucoseStatus: GlucoseStatus(glucose: 100, delta: 0),
                iob: IOBStatus(iob: 0),
                profile: ProfileData(basalRate: 1, sensitivity: 50, carbRatio: 10, targetLow: 100, targetHigh: 110),
                mealData: MealData()
            ),
            expected: VectorExpected()
        )
        
        #expect(vector.id == "test-id")
    }
    
    @Test("Vector is Codable")
    func codable() throws {
        let vector = TestVector(
            metadata: VectorMetadata(id: "TV-002", name: "Codable Test"),
            input: VectorInput(
                glucoseStatus: GlucoseStatus(glucose: 150, delta: 10),
                iob: IOBStatus(iob: 1.5),
                profile: ProfileData(basalRate: 0.8, sensitivity: 45, carbRatio: 8, targetLow: 90, targetHigh: 100),
                mealData: MealData(cob: 20)
            ),
            expected: VectorExpected(rate: 1.5, eventualBG: 130)
        )
        
        let data = try JSONEncoder().encode(vector)
        let decoded = try JSONDecoder().decode(TestVector.self, from: data)
        
        #expect(decoded.id == vector.id)
        #expect(decoded.input.glucoseStatus.glucose == 150)
        #expect(decoded.expected.rate == 1.5)
    }
}

// MARK: - Vector Metadata Tests

@Suite("Vector Metadata")
struct VectorMetadataTests {
    
    @Test("Metadata creation")
    func creation() {
        let metadata = VectorMetadata(
            id: "TV-001",
            name: "Basal Increase",
            category: "basal-adjustment",
            source: "aaps/replay",
            description: "Test basal increase scenario",
            algorithm: "OpenAPSSMB"
        )
        
        #expect(metadata.id == "TV-001")
        #expect(metadata.algorithm == "OpenAPSSMB")
    }
    
    @Test("Metadata default values")
    func defaults() {
        let metadata = VectorMetadata(id: "test", name: "Test")
        
        #expect(metadata.category == "general")
        #expect(metadata.source == "fixture")
        #expect(metadata.algorithm == nil)
    }
}

// MARK: - Glucose Status Tests

@Suite("Glucose Status")
struct GlucoseStatusTests {
    
    @Test("Glucose status creation")
    func creation() {
        let status = GlucoseStatus(
            glucose: 120.5,
            glucoseUnit: "mg/dL",
            delta: 5.5,
            shortAvgDelta: 4.0,
            longAvgDelta: -2.0
        )
        
        #expect(status.glucose == 120.5)
        #expect(status.delta == 5.5)
        #expect(status.shortAvgDelta == 4.0)
    }
    
    @Test("Glucose status is Equatable")
    func equatable() {
        let status1 = GlucoseStatus(glucose: 100, delta: 0)
        let status2 = GlucoseStatus(glucose: 100, delta: 0)
        
        #expect(status1 == status2)
    }
}

// MARK: - IOB Status Tests

@Suite("IOB Status")
struct IOBStatusTests {
    
    @Test("IOB status creation")
    func creation() {
        let iob = IOBStatus(
            iob: 1.5,
            basalIob: 0.5,
            bolusIob: 1.0,
            activity: 0.01
        )
        
        #expect(iob.iob == 1.5)
        #expect(iob.basalIob == 0.5)
        #expect(iob.bolusIob == 1.0)
    }
    
    @Test("IOB with zero temp")
    func withZeroTemp() {
        let zeroTemp = IOBWithZeroTemp(
            iob: 0.8,
            basaliob: 0.3,
            activity: 0.005
        )
        
        let iob = IOBStatus(iob: 0.8, iobWithZeroTemp: zeroTemp)
        
        #expect(iob.iobWithZeroTemp?.iob == 0.8)
    }
}

// MARK: - Profile Data Tests

@Suite("Profile Data")
struct ProfileDataTests {
    
    @Test("Profile creation")
    func creation() {
        let profile = ProfileData(
            basalRate: 0.85,
            sensitivity: 50.0,
            carbRatio: 10.0,
            targetLow: 100,
            targetHigh: 110,
            maxIob: 3.0,
            maxBasal: 2.0,
            dia: 5.0
        )
        
        #expect(profile.basalRate == 0.85)
        #expect(profile.sensitivity == 50.0)
        #expect(profile.maxIob == 3.0)
    }
}

// MARK: - Meal Data Tests

@Suite("Meal Data")
struct MealDataTests {
    
    @Test("Meal data creation")
    func creation() {
        let meal = MealData(carbs: 30, cob: 25)
        
        #expect(meal.carbs == 30)
        #expect(meal.cob == 25)
    }
    
    @Test("Empty meal data")
    func emptyMeal() {
        let meal = MealData()
        
        #expect(meal.carbs == 0)
        #expect(meal.cob == 0)
    }
}

// MARK: - Vector Expected Tests

@Suite("Vector Expected")
struct VectorExpectedTests {
    
    @Test("Expected output creation")
    func creation() {
        let expected = VectorExpected(
            rate: 1.2,
            duration: 30,
            eventualBG: 130,
            insulinReq: 0.5
        )
        
        #expect(expected.rate == 1.2)
        #expect(expected.duration == 30)
        #expect(expected.eventualBG == 130)
    }
    
    @Test("Empty expected")
    func empty() {
        let expected = VectorExpected()
        
        #expect(expected.rate == nil)
        #expect(expected.smb == nil)
    }
}

// MARK: - Vector Assertion Tests

@Suite("Vector Assertion")
struct VectorAssertionTests {
    
    @Test("Assertion creation")
    func creation() {
        let assertion = VectorAssertion(
            type: "rate_increased",
            baseline: 0.85
        )
        
        #expect(assertion.type == "rate_increased")
        #expect(assertion.baseline == 0.85)
    }
    
    @Test("Safety limit assertion")
    func safetyLimit() {
        let assertion = VectorAssertion(
            type: "safety_limit",
            field: "rate",
            max: 2.0
        )
        
        #expect(assertion.field == "rate")
        #expect(assertion.max == 2.0)
    }
}

// MARK: - Replay Result Tests

@Suite("Replay Result")
struct ReplayResultTests {
    
    @Test("Successful result")
    func successResult() {
        let result = ReplayResult(
            vectorId: "TV-001",
            success: true,
            actual: ReplayOutput(rate: 1.0, duration: 30),
            expected: VectorExpected(rate: 1.0, duration: 30),
            executionTimeMs: 15
        )
        
        #expect(result.success == true)
        #expect(result.divergences.isEmpty)
        #expect(result.executionTimeMs == 15)
    }
    
    @Test("Failed result with divergences")
    func failedResult() {
        let divergence = Divergence(
            field: "rate",
            expected: "1.0",
            actual: "1.5",
            delta: 0.5,
            severity: .warning
        )
        
        let result = ReplayResult(
            vectorId: "TV-002",
            success: false,
            actual: ReplayOutput(rate: 1.5),
            expected: VectorExpected(rate: 1.0),
            divergences: [divergence]
        )
        
        #expect(result.success == false)
        #expect(result.divergences.count == 1)
    }
}

// MARK: - Divergence Tests

@Suite("Divergence")
struct DivergenceTests {
    
    @Test("Divergence creation")
    func creation() {
        let div = Divergence(
            field: "eventualBG",
            expected: "130",
            actual: "145",
            delta: 15,
            severity: .error
        )
        
        #expect(div.field == "eventualBG")
        #expect(div.delta == 15)
        #expect(div.severity == .error)
    }
    
    @Test("Divergence auto-generates message")
    func autoMessage() {
        let div = Divergence(
            field: "rate",
            expected: "1.0",
            actual: "1.2"
        )
        
        #expect(div.message.contains("rate"))
        #expect(div.message.contains("1.0"))
        #expect(div.message.contains("1.2"))
    }
    
    @Test("Severity levels")
    func severityLevels() {
        let severities: [Divergence.Severity] = [.info, .warning, .error, .critical]
        #expect(severities.count == 4)
    }
}

// MARK: - Replay Session Tests

@Suite("Replay Session")
struct ReplaySessionTests {
    
    @Test("Session creation")
    func creation() {
        let session = ReplaySession(name: "Test Session", vectorCount: 10)
        
        #expect(session.name == "Test Session")
        #expect(session.vectorCount == 10)
        #expect(session.completedCount == 0)
        #expect(!session.isComplete)
    }
    
    @Test("Session adds results")
    func addResults() {
        var session = ReplaySession(name: "Test", vectorCount: 2)
        
        let result1 = ReplayResult(
            vectorId: "TV-001",
            success: true,
            actual: ReplayOutput(),
            expected: VectorExpected()
        )
        
        let result2 = ReplayResult(
            vectorId: "TV-002",
            success: false,
            actual: ReplayOutput(),
            expected: VectorExpected()
        )
        
        session.addResult(result1)
        session.addResult(result2)
        
        #expect(session.completedCount == 2)
        #expect(session.successCount == 1)
        #expect(session.failureCount == 1)
        #expect(session.isComplete)
    }
    
    @Test("Session success rate")
    func successRate() {
        var session = ReplaySession(name: "Test", vectorCount: 4)
        
        for i in 0..<4 {
            session.addResult(ReplayResult(
                vectorId: "TV-\(i)",
                success: i < 3,  // 3 success, 1 failure
                actual: ReplayOutput(),
                expected: VectorExpected()
            ))
        }
        
        #expect(session.successRate == 0.75)
    }
    
    @Test("Session average execution time")
    func averageExecutionTime() {
        var session = ReplaySession(name: "Test", vectorCount: 3)
        
        session.addResult(ReplayResult(vectorId: "1", success: true, actual: ReplayOutput(), expected: VectorExpected(), executionTimeMs: 10))
        session.addResult(ReplayResult(vectorId: "2", success: true, actual: ReplayOutput(), expected: VectorExpected(), executionTimeMs: 20))
        session.addResult(ReplayResult(vectorId: "3", success: true, actual: ReplayOutput(), expected: VectorExpected(), executionTimeMs: 30))
        
        #expect(session.averageExecutionTimeMs == 20)
    }
}

// MARK: - Memory Vector Loader Tests

@Suite("Memory Vector Loader")
struct MemoryVectorLoaderTests {
    
    func createTestVector(id: String, category: String = "test") -> TestVector {
        TestVector(
            metadata: VectorMetadata(id: id, name: "Test \(id)", category: category),
            input: VectorInput(
                glucoseStatus: GlucoseStatus(glucose: 100, delta: 0),
                iob: IOBStatus(iob: 0),
                profile: ProfileData(basalRate: 1, sensitivity: 50, carbRatio: 10, targetLow: 100, targetHigh: 110),
                mealData: MealData()
            ),
            expected: VectorExpected()
        )
    }
    
    @Test("Load all vectors")
    func loadAll() async throws {
        let loader = MemoryVectorLoader()
        await loader.add(createTestVector(id: "TV-001"))
        await loader.add(createTestVector(id: "TV-002"))
        
        let vectors = try await loader.loadAll()
        #expect(vectors.count == 2)
    }
    
    @Test("Load by category")
    func loadByCategory() async throws {
        let loader = MemoryVectorLoader()
        await loader.add(createTestVector(id: "TV-001", category: "basal"))
        await loader.add(createTestVector(id: "TV-002", category: "bolus"))
        await loader.add(createTestVector(id: "TV-003", category: "basal"))
        
        let basalVectors = try await loader.loadByCategory("basal")
        #expect(basalVectors.count == 2)
    }
    
    @Test("Load by ID")
    func loadById() async throws {
        let loader = MemoryVectorLoader()
        await loader.add(createTestVector(id: "TV-001"))
        await loader.add(createTestVector(id: "TV-002"))
        
        let vector = try await loader.load(id: "TV-002")
        #expect(vector?.id == "TV-002")
    }
    
    @Test("Load non-existent ID returns nil")
    func loadNonExistent() async throws {
        let loader = MemoryVectorLoader()
        let vector = try await loader.load(id: "not-found")
        #expect(vector == nil)
    }
    
    @Test("List vector IDs")
    func listIds() async throws {
        let loader = MemoryVectorLoader()
        await loader.add(createTestVector(id: "A"))
        await loader.add(createTestVector(id: "B"))
        
        let ids = try await loader.listVectorIds()
        #expect(ids.contains("A"))
        #expect(ids.contains("B"))
    }
}

// MARK: - Result Comparator Tests

@Suite("Result Comparator")
struct ResultComparatorTests {
    
    @Test("No divergence when values match")
    func noDivergence() {
        let comparator = ResultComparator()
        
        let actual = ReplayOutput(rate: 1.0, duration: 30)
        let expected = VectorExpected(rate: 1.0, duration: 30)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.isEmpty)
    }
    
    @Test("Rate divergence detected")
    func rateDivergence() {
        let comparator = ResultComparator()
        
        let actual = ReplayOutput(rate: 1.2)
        let expected = VectorExpected(rate: 1.0)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.count == 1)
        #expect(divergences[0].field == "rate")
    }
    
    @Test("BG divergence detected")
    func bgDivergence() {
        let comparator = ResultComparator()
        
        let actual = ReplayOutput(eventualBG: 145)
        let expected = VectorExpected(eventualBG: 130)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.count == 1)
        #expect(divergences[0].field == "eventualBG")
    }
    
    @Test("Within tolerance no divergence")
    func withinTolerance() {
        let comparator = ResultComparator(tolerances: .lenient)
        
        let actual = ReplayOutput(rate: 1.05)
        let expected = VectorExpected(rate: 1.0)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.isEmpty)
    }
    
    @Test("Strict tolerances catch small differences")
    func strictTolerance() {
        let comparator = ResultComparator(tolerances: .strict)
        
        let actual = ReplayOutput(rate: 1.02)
        let expected = VectorExpected(rate: 1.0)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.count == 1)
    }
    
    @Test("Multiple divergences detected")
    func multipleDivergences() {
        let comparator = ResultComparator()
        
        let actual = ReplayOutput(rate: 1.5, duration: 60, eventualBG: 180)
        let expected = VectorExpected(rate: 1.0, duration: 30, eventualBG: 130)
        
        let divergences = comparator.compare(actual: actual, expected: expected)
        #expect(divergences.count == 3)
    }
}

// MARK: - Replay Report Tests

@Suite("Replay Report")
struct ReplayReportTests {
    
    @Test("Report from session")
    func reportFromSession() {
        var session = ReplaySession(name: "Test Report", vectorCount: 3)
        
        session.addResult(ReplayResult(
            vectorId: "TV-001",
            success: true,
            actual: ReplayOutput(),
            expected: VectorExpected()
        ))
        
        session.addResult(ReplayResult(
            vectorId: "TV-002",
            success: false,
            actual: ReplayOutput(),
            expected: VectorExpected(),
            divergences: [Divergence(field: "rate", expected: "1.0", actual: "1.5")]
        ))
        
        session.addResult(ReplayResult(
            vectorId: "TV-003",
            success: false,
            actual: ReplayOutput(),
            expected: VectorExpected(),
            divergences: [Divergence(field: "rate", expected: "1.0", actual: "1.3")]
        ))
        
        let report = ReplayReport(session)
        
        #expect(report.divergencesByField["rate"] == 2)
    }
    
    @Test("Report text contains session name")
    func reportText() {
        let session = ReplaySession(name: "My Test Session", vectorCount: 5)
        let report = ReplayReport(session)
        
        #expect(report.text.contains("My Test Session"))
    }
}

// MARK: - Category Stats Tests

@Suite("Category Stats")
struct CategoryStatsTests {
    
    @Test("Success rate calculation")
    func successRate() {
        let stats = CategoryStats(total: 10, success: 8)
        #expect(stats.successRate == 0.8)
    }
    
    @Test("Zero total has zero rate")
    func zeroTotal() {
        let stats = CategoryStats(total: 0, success: 0)
        #expect(stats.successRate == 0)
    }
}

// MARK: - Original Output Tests

@Suite("Original Output")
struct OriginalOutputTests {
    
    @Test("Original output creation")
    func creation() {
        let output = OriginalOutput(
            temp: "absolute",
            bg: 120,
            eventualBG: 150,
            rate: 1.5,
            duration: 30
        )
        
        #expect(output.temp == "absolute")
        #expect(output.rate == 1.5)
    }
    
    @Test("Predicted BGs")
    func predictedBGs() {
        let preds = PredictedBGs(
            IOB: [100, 110, 120],
            COB: [100, 115, 130]
        )
        
        #expect(preds.IOB?.count == 3)
        #expect(preds.COB?.count == 3)
    }
}
