// AlgorithmPlaygroundToggleTests.swift
// T1PalAlgorithm
//
// Tests for multi-algorithm toggle support.

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Algorithm Info Tests

@Suite("Algorithm Info")
struct AlgorithmInfoTests {
    
    @Test("Creates info with all fields")
    func createsWithAllFields() {
        let info = AlgorithmInfo(
            id: "oref1",
            name: "OpenAPS oref1",
            version: "2.0.0",
            origin: .oref1,
            supportsSMB: true,
            providesPredictions: true,
            isActive: true
        )
        
        #expect(info.id == "oref1")
        #expect(info.name == "OpenAPS oref1")
        #expect(info.version == "2.0.0")
        #expect(info.origin == .oref1)
        #expect(info.supportsSMB == true)
        #expect(info.providesPredictions == true)
        #expect(info.isActive == true)
    }
    
    @Test("Creates info with defaults")
    func createsWithDefaults() {
        let info = AlgorithmInfo(id: "test", name: "Test Algorithm")
        
        #expect(info.version == "1.0.0")
        #expect(info.origin == .custom)
        #expect(info.supportsSMB == false)
        #expect(info.providesPredictions == true)
        #expect(info.isActive == false)
    }
    
    @Test("Generates display label")
    func generatesDisplayLabel() {
        let info = AlgorithmInfo(id: "oref1", name: "oref1", version: "2.0.0")
        #expect(info.displayLabel == "oref1 v2.0.0")
    }
    
    @Test("Generates short description with features")
    func generatesShortDescription() {
        let info = AlgorithmInfo(
            id: "test",
            name: "Test",
            origin: .oref0,
            supportsSMB: true,
            providesPredictions: true
        )
        
        let desc = info.shortDescription
        #expect(desc.contains("oref0") || desc.contains("OpenAPS"))
        #expect(desc.contains("SMB"))
        #expect(desc.contains("predictions"))
    }
    
    @Test("Generates short description without features")
    func generatesShortDescriptionNoFeatures() {
        let info = AlgorithmInfo(
            id: "test",
            name: "Test",
            origin: .custom,
            supportsSMB: false,
            providesPredictions: false
        )
        
        #expect(info.shortDescription == "Custom")
    }
}

// MARK: - Playground Algorithm Selector Tests

@Suite("Playground Algorithm Selector")
struct PlaygroundAlgorithmSelectorTests {
    
    @Test("Registers algorithm")
    func registersAlgorithm() async {
        let selector = PlaygroundAlgorithmSelector()
        let info = AlgorithmInfo(id: "test1", name: "Test 1")
        
        await selector.registerAlgorithm(info)
        
        let algorithms = await selector.algorithms
        #expect(algorithms.count == 1)
        #expect(algorithms[0].id == "test1")
    }
    
    @Test("Does not duplicate algorithm")
    func doesNotDuplicate() async {
        let selector = PlaygroundAlgorithmSelector()
        let info = AlgorithmInfo(id: "test1", name: "Test 1")
        
        await selector.registerAlgorithm(info)
        await selector.registerAlgorithm(info)
        
        let algorithms = await selector.algorithms
        #expect(algorithms.count == 1)
    }
    
    @Test("Unregisters algorithm")
    func unregistersAlgorithm() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "test1", name: "Test 1"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "test2", name: "Test 2"))
        
        await selector.unregisterAlgorithm(id: "test1")
        
        let algorithms = await selector.algorithms
        #expect(algorithms.count == 1)
        #expect(algorithms[0].id == "test2")
    }
    
    @Test("Selects algorithm")
    func selectsAlgorithm() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "test1", name: "Test 1"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "test2", name: "Test 2"))
        
        try await selector.select(algorithmId: "test2")
        
        let selected = await selector.selectedAlgorithm
        #expect(selected?.id == "test2")
    }
    
    @Test("Throws on selecting unknown algorithm")
    func throwsOnUnknown() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "test1", name: "Test 1"))
        
        do {
            try await selector.select(algorithmId: "unknown")
            #expect(Bool(false), "Should have thrown")
        } catch let error as PlaygroundToggleError {
            #expect(error == .algorithmNotFound(id: "unknown"))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("Selects next algorithm")
    func selectsNext() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "c", name: "C"))
        try? await selector.select(algorithmId: "a")
        
        await selector.selectNext()
        
        let selected = await selector.selectedId
        #expect(selected == "b")
    }
    
    @Test("Selects next wraps around")
    func selectsNextWraps() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        try? await selector.select(algorithmId: "b")
        
        await selector.selectNext()
        
        let selected = await selector.selectedId
        #expect(selected == "a")
    }
    
    @Test("Selects previous algorithm")
    func selectsPrevious() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "c", name: "C"))
        try? await selector.select(algorithmId: "c")
        
        await selector.selectPrevious()
        
        let selected = await selector.selectedId
        #expect(selected == "b")
    }
    
    @Test("Undoes selection")
    func undoesSelection() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        try await selector.select(algorithmId: "a")
        try await selector.select(algorithmId: "b")
        
        await selector.undoSelection()
        
        let selected = await selector.selectedId
        #expect(selected == "a")
    }
    
    @Test("Can undo returns false when empty")
    func canUndoWhenEmpty() async {
        let selector = PlaygroundAlgorithmSelector()
        let canUndo = await selector.canUndo
        #expect(canUndo == false)
    }
    
    @Test("Can undo returns true after selection")
    func canUndoAfterSelection() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        try await selector.select(algorithmId: "a")
        try await selector.select(algorithmId: "b")
        
        let canUndo = await selector.canUndo
        #expect(canUndo == true)
    }
}

// MARK: - Comparison Mode Tests

@Suite("Comparison Mode")
struct ComparisonModeTests {
    
    @Test("Adds to comparison")
    func addsToComparison() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        try await selector.addToComparison(algorithmId: "a")
        try await selector.addToComparison(algorithmId: "b")
        
        let comparison = await selector.comparisonAlgorithms
        #expect(comparison.count == 2)
    }
    
    @Test("Removes from comparison")
    func removesFromComparison() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        try await selector.addToComparison(algorithmId: "a")
        try await selector.addToComparison(algorithmId: "b")
        await selector.removeFromComparison(algorithmId: "a")
        
        let comparison = await selector.comparisonAlgorithms
        #expect(comparison.count == 1)
        #expect(comparison[0].id == "b")
    }
    
    @Test("Toggles comparison")
    func togglesComparison() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        
        try await selector.toggleComparison(algorithmId: "a")
        var isIn = await selector.isInComparison(algorithmId: "a")
        #expect(isIn == true)
        
        try await selector.toggleComparison(algorithmId: "a")
        isIn = await selector.isInComparison(algorithmId: "a")
        #expect(isIn == false)
    }
    
    @Test("Clears comparison")
    func clearsComparison() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        try await selector.addToComparison(algorithmId: "a")
        try await selector.addToComparison(algorithmId: "b")
        await selector.clearComparison()
        
        let count = await selector.comparisonCount
        #expect(count == 0)
    }
    
    @Test("Comparison count is accurate")
    func comparisonCountAccurate() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "c", name: "C"))
        
        try await selector.addToComparison(algorithmId: "a")
        try await selector.addToComparison(algorithmId: "c")
        
        let count = await selector.comparisonCount
        #expect(count == 2)
    }
}

// MARK: - Toggle State Tests

@Suite("Playground Toggle State")
struct PlaygroundToggleStateTests {
    
    @Test("Creates state with defaults")
    func createsWithDefaults() {
        let state = PlaygroundToggleState()
        
        #expect(state.algorithms.isEmpty)
        #expect(state.selectedId == nil)
        #expect(state.comparisonIds.isEmpty)
        #expect(state.canUndo == false)
        #expect(state.isComparisonMode == false)
    }
    
    @Test("Gets selected algorithm")
    func getsSelectedAlgorithm() {
        let state = PlaygroundToggleState(
            algorithms: [
                AlgorithmInfo(id: "a", name: "A"),
                AlgorithmInfo(id: "b", name: "B")
            ],
            selectedId: "b"
        )
        
        let selected = state.selectedAlgorithm
        #expect(selected?.id == "b")
    }
    
    @Test("Gets comparison algorithms")
    func getsComparisonAlgorithms() {
        let state = PlaygroundToggleState(
            algorithms: [
                AlgorithmInfo(id: "a", name: "A"),
                AlgorithmInfo(id: "b", name: "B"),
                AlgorithmInfo(id: "c", name: "C")
            ],
            comparisonIds: ["a", "c"]
        )
        
        let comparison = state.comparisonAlgorithms
        #expect(comparison.count == 2)
    }
    
    @Test("Checks if selected")
    func checksIfSelected() {
        let state = PlaygroundToggleState(
            algorithms: [AlgorithmInfo(id: "a", name: "A")],
            selectedId: "a"
        )
        
        #expect(state.isSelected("a") == true)
        #expect(state.isSelected("b") == false)
    }
    
    @Test("Checks if in comparison")
    func checksIfInComparison() {
        let state = PlaygroundToggleState(
            algorithms: [AlgorithmInfo(id: "a", name: "A")],
            comparisonIds: ["a"]
        )
        
        #expect(state.isInComparison("a") == true)
        #expect(state.isInComparison("b") == false)
    }
}

// MARK: - Toggle Reducer Tests

@Suite("Playground Toggle Reducer")
struct PlaygroundToggleReducerTests {
    
    @Test("Processes select action")
    func processesSelectAction() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = try await reducer.reduce(.select(algorithmId: "b"))
        
        #expect(state.selectedId == "b")
    }
    
    @Test("Processes selectNext action")
    func processesSelectNextAction() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        try await selector.select(algorithmId: "a")
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = try await reducer.reduce(.selectNext)
        
        #expect(state.selectedId == "b")
    }
    
    @Test("Processes undo action")
    func processesUndoAction() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        await selector.registerAlgorithm(AlgorithmInfo(id: "b", name: "B"))
        try await selector.select(algorithmId: "a")
        try await selector.select(algorithmId: "b")
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = try await reducer.reduce(.undo)
        
        #expect(state.selectedId == "a")
    }
    
    @Test("Processes toggle comparison action")
    func processesToggleComparisonAction() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = try await reducer.reduce(.toggleComparison(algorithmId: "a"))
        
        #expect(state.comparisonIds.contains("a"))
    }
    
    @Test("Processes clear comparison action")
    func processesClearComparisonAction() async throws {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        try await selector.addToComparison(algorithmId: "a")
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = try await reducer.reduce(.clearComparison)
        
        #expect(state.comparisonIds.isEmpty)
    }
    
    @Test("Processes set comparison mode action")
    func processesSetComparisonModeAction() async throws {
        let reducer = PlaygroundToggleReducer()
        
        var state = try await reducer.reduce(.setComparisonMode(true))
        #expect(state.isComparisonMode == true)
        
        state = try await reducer.reduce(.setComparisonMode(false))
        #expect(state.isComparisonMode == false)
    }
    
    @Test("Gets current state")
    func getsCurrentState() async {
        let selector = PlaygroundAlgorithmSelector()
        await selector.registerAlgorithm(AlgorithmInfo(id: "a", name: "A"))
        try? await selector.select(algorithmId: "a")
        
        let reducer = PlaygroundToggleReducer(selector: selector)
        let state = await reducer.currentState()
        
        #expect(state.algorithms.count == 1)
        #expect(state.selectedId == "a")
    }
}

// MARK: - Comparison Result Tests

@Suite("Algorithm Comparison Result")
struct AlgorithmComparisonResultTests {
    
    func sampleInput() -> ComparisonInput {
        ComparisonInput(
            glucose: 150,
            glucoseDelta: 5,
            iob: 1.5,
            cob: 20,
            targetGlucose: 100,
            isf: 50,
            carbRatio: 10,
            basalRate: 1.0
        )
    }
    
    @Test("Detects unanimous result")
    func detectsUnanimous() {
        let result = AlgorithmComparisonResult(
            input: sampleInput(),
            results: [
                SingleAlgorithmResult(algorithmId: "a", algorithmName: "A", action: "Temp 0.5U/hr", suggestedRate: 0.5, eventualBG: 120, reason: "High", executionTimeMs: 5),
                SingleAlgorithmResult(algorithmId: "b", algorithmName: "B", action: "Temp 0.5U/hr", suggestedRate: 0.5, eventualBG: 118, reason: "Elevated", executionTimeMs: 8)
            ]
        )
        
        #expect(result.isUnanimous == true)
    }
    
    @Test("Detects divergent result")
    func detectsDivergent() {
        let result = AlgorithmComparisonResult(
            input: sampleInput(),
            results: [
                SingleAlgorithmResult(algorithmId: "a", algorithmName: "A", action: "Temp 0.5U/hr", suggestedRate: 0.5, eventualBG: 120, reason: "High", executionTimeMs: 5),
                SingleAlgorithmResult(algorithmId: "b", algorithmName: "B", action: "No change", suggestedRate: nil, eventualBG: 110, reason: "OK", executionTimeMs: 8)
            ]
        )
        
        #expect(result.isUnanimous == false)
    }
    
    @Test("Gets majority action")
    func getsMajorityAction() {
        let result = AlgorithmComparisonResult(
            input: sampleInput(),
            results: [
                SingleAlgorithmResult(algorithmId: "a", algorithmName: "A", action: "Temp", suggestedRate: 0.5, eventualBG: 120, reason: "", executionTimeMs: 5),
                SingleAlgorithmResult(algorithmId: "b", algorithmName: "B", action: "Temp", suggestedRate: 0.6, eventualBG: 118, reason: "", executionTimeMs: 8),
                SingleAlgorithmResult(algorithmId: "c", algorithmName: "C", action: "None", suggestedRate: nil, eventualBG: 110, reason: "", executionTimeMs: 6)
            ]
        )
        
        #expect(result.majorityAction == "Temp")
    }
    
    @Test("Gets diverging results")
    func getsDivergingResults() {
        let result = AlgorithmComparisonResult(
            input: sampleInput(),
            results: [
                SingleAlgorithmResult(algorithmId: "a", algorithmName: "A", action: "Temp", suggestedRate: 0.5, eventualBG: 120, reason: "", executionTimeMs: 5),
                SingleAlgorithmResult(algorithmId: "b", algorithmName: "B", action: "Temp", suggestedRate: 0.6, eventualBG: 118, reason: "", executionTimeMs: 8),
                SingleAlgorithmResult(algorithmId: "c", algorithmName: "C", action: "None", suggestedRate: nil, eventualBG: 110, reason: "", executionTimeMs: 6)
            ]
        )
        
        let diverging = result.divergingResults
        #expect(diverging.count == 1)
        #expect(diverging[0].algorithmId == "c")
    }
}

// MARK: - Single Algorithm Result Tests

@Suite("Single Algorithm Result")
struct SingleAlgorithmResultTests {
    
    @Test("Creates success result")
    func createsSuccessResult() {
        let result = SingleAlgorithmResult(
            algorithmId: "oref1",
            algorithmName: "OpenAPS oref1",
            action: "Temp 0.5U/hr",
            suggestedRate: 0.5,
            eventualBG: 120,
            reason: "BG rising",
            executionTimeMs: 5.5
        )
        
        #expect(result.success == true)
        #expect(result.error == nil)
        #expect(result.algorithmId == "oref1")
        #expect(result.suggestedRate == 0.5)
    }
    
    @Test("Creates error result")
    func createsErrorResult() {
        let result = SingleAlgorithmResult(
            algorithmId: "test",
            algorithmName: "Test",
            action: "error",
            suggestedRate: nil,
            eventualBG: 0,
            reason: "Failed",
            executionTimeMs: 0,
            success: false,
            error: "Algorithm not found"
        )
        
        #expect(result.success == false)
        #expect(result.error == "Algorithm not found")
    }
}

// MARK: - Comparison Input Tests

@Suite("Comparison Input")
struct ComparisonInputTests {
    
    @Test("Creates input with all fields")
    func createsWithAllFields() {
        let input = ComparisonInput(
            glucose: 150,
            glucoseDelta: 5,
            iob: 1.5,
            cob: 20,
            targetGlucose: 100,
            isf: 50,
            carbRatio: 10,
            basalRate: 1.0
        )
        
        #expect(input.glucose == 150)
        #expect(input.glucoseDelta == 5)
        #expect(input.iob == 1.5)
        #expect(input.cob == 20)
        #expect(input.targetGlucose == 100)
        #expect(input.isf == 50)
        #expect(input.carbRatio == 10)
        #expect(input.basalRate == 1.0)
    }
    
    @Test("Is equatable")
    func isEquatable() {
        let input1 = ComparisonInput(glucose: 150, glucoseDelta: 5, iob: 1.5, cob: 20, targetGlucose: 100, isf: 50, carbRatio: 10, basalRate: 1.0)
        let input2 = ComparisonInput(glucose: 150, glucoseDelta: 5, iob: 1.5, cob: 20, targetGlucose: 100, isf: 50, carbRatio: 10, basalRate: 1.0)
        
        #expect(input1 == input2)
    }
}

// MARK: - Display Formatter Tests

@Suite("Comparison Display Formatter")
struct ComparisonDisplayFormatterTests {
    
    func sampleResult() -> AlgorithmComparisonResult {
        AlgorithmComparisonResult(
            input: ComparisonInput(glucose: 150, glucoseDelta: 5, iob: 1.5, cob: 20, targetGlucose: 100, isf: 50, carbRatio: 10, basalRate: 1.0),
            results: [
                SingleAlgorithmResult(algorithmId: "a", algorithmName: "Algorithm A", action: "Temp 0.5U/hr", suggestedRate: 0.5, eventualBG: 120, reason: "High", executionTimeMs: 5.5),
                SingleAlgorithmResult(algorithmId: "b", algorithmName: "Algorithm B", action: "Temp 0.5U/hr", suggestedRate: 0.5, eventualBG: 118, reason: "Elevated", executionTimeMs: 8.2)
            ]
        )
    }
    
    @Test("Generates summary table")
    func generatesSummaryTable() {
        let result = sampleResult()
        let table = ComparisonDisplayFormatter.summaryTable(result)
        
        #expect(table.contains("ALGORITHM COMPARISON"))
        #expect(table.contains("Algorithm A"))
        #expect(table.contains("Algorithm B"))
        #expect(table.contains("UNANIMOUS"))
    }
    
    @Test("Generates inline result")
    func generatesInlineResult() {
        let single = SingleAlgorithmResult(
            algorithmId: "a",
            algorithmName: "Test",
            action: "Temp 0.5U/hr",
            suggestedRate: 0.5,
            eventualBG: 120,
            reason: "",
            executionTimeMs: 5
        )
        
        let inline = ComparisonDisplayFormatter.inlineResult(single)
        #expect(inline == "Test: Temp 0.5U/hr")
    }
    
    @Test("Generates performance summary")
    func generatesPerformanceSummary() {
        let result = sampleResult()
        let summary = ComparisonDisplayFormatter.performanceSummary(result)
        
        #expect(summary.contains("Avg"))
        #expect(summary.contains("Fastest"))
        #expect(summary.contains("Slowest"))
    }
}

// MARK: - Error Tests

@Suite("Playground Toggle Errors")
struct PlaygroundToggleErrorTests {
    
    @Test("Algorithm not found error")
    func algorithmNotFoundError() {
        let error = PlaygroundToggleError.algorithmNotFound(id: "unknown")
        #expect(error == .algorithmNotFound(id: "unknown"))
    }
    
    @Test("No algorithm selected error")
    func noAlgorithmSelectedError() {
        let error = PlaygroundToggleError.noAlgorithmSelected
        #expect(error == .noAlgorithmSelected)
    }
    
    @Test("Comparison limit exceeded error")
    func comparisonLimitExceededError() {
        let error = PlaygroundToggleError.comparisonLimitExceeded(max: 5)
        #expect(error == .comparisonLimitExceeded(max: 5))
    }
}
