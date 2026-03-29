// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// AlgorithmPlaygroundToggle.swift
// T1PalAlgorithm
//
// Multi-algorithm toggle support for AlgorithmPlayground.
// Enables switching between registered algorithms for comparison.
//
// ALG-BENCH-010: AlgorithmPlayground multi-algorithm toggle

import Foundation
import T1PalCore

// MARK: - Playground Algorithm Selection

/// Manages algorithm selection for playground/comparison scenarios.
public actor PlaygroundAlgorithmSelector {
    /// Available algorithms for selection.
    private var availableAlgorithms: [AlgorithmInfo] = []
    
    /// Currently selected algorithm ID.
    private var selectedAlgorithmId: String?
    
    /// Comparison mode algorithms (for side-by-side).
    private var comparisonAlgorithmIds: Set<String> = []
    
    /// Selection history for undo support.
    private var selectionHistory: [String] = []
    
    /// Maximum history entries.
    private let maxHistory: Int
    
    public init(maxHistory: Int = 20) {
        self.maxHistory = maxHistory
    }
    
    // MARK: - Algorithm Registration
    
    /// Refresh available algorithms from registry.
    public func refreshFromRegistry() {
        let registry = AlgorithmRegistry.shared
        availableAlgorithms = registry.allAlgorithms.map { alg in
            AlgorithmInfo(
                id: alg.name,
                name: alg.name,
                version: alg.version,
                origin: alg.capabilities.origin,
                supportsSMB: alg.capabilities.supportsSMB,
                providesPredictions: alg.capabilities.providesPredictions,
                isActive: alg.name == registry.activeAlgorithmName
            )
        }.sorted { $0.name < $1.name }
        
        // Set selected to active if not set
        if selectedAlgorithmId == nil {
            selectedAlgorithmId = registry.activeAlgorithmName
        }
    }
    
    /// Register a custom algorithm for testing.
    public func registerAlgorithm(_ info: AlgorithmInfo) {
        if !availableAlgorithms.contains(where: { $0.id == info.id }) {
            availableAlgorithms.append(info)
            availableAlgorithms.sort { $0.name < $1.name }
        }
    }
    
    /// Unregister an algorithm.
    public func unregisterAlgorithm(id: String) {
        availableAlgorithms.removeAll { $0.id == id }
        if selectedAlgorithmId == id {
            selectedAlgorithmId = availableAlgorithms.first?.id
        }
        comparisonAlgorithmIds.remove(id)
    }
    
    // MARK: - Selection
    
    /// Get all available algorithms.
    public var algorithms: [AlgorithmInfo] {
        availableAlgorithms
    }
    
    /// Get the currently selected algorithm.
    public var selectedAlgorithm: AlgorithmInfo? {
        guard let id = selectedAlgorithmId else { return nil }
        return availableAlgorithms.first { $0.id == id }
    }
    
    /// Get the selected algorithm ID.
    public var selectedId: String? {
        selectedAlgorithmId
    }
    
    /// Select an algorithm by ID.
    public func select(algorithmId: String) throws {
        guard availableAlgorithms.contains(where: { $0.id == algorithmId }) else {
            throw PlaygroundToggleError.algorithmNotFound(id: algorithmId)
        }
        
        if let current = selectedAlgorithmId {
            selectionHistory.append(current)
            if selectionHistory.count > maxHistory {
                selectionHistory.removeFirst()
            }
        }
        
        selectedAlgorithmId = algorithmId
    }
    
    /// Select the next algorithm in the list.
    public func selectNext() {
        guard !availableAlgorithms.isEmpty else { return }
        guard let currentId = selectedAlgorithmId,
              let currentIndex = availableAlgorithms.firstIndex(where: { $0.id == currentId }) else {
            selectedAlgorithmId = availableAlgorithms.first?.id
            return
        }
        
        let nextIndex = (currentIndex + 1) % availableAlgorithms.count
        if let current = selectedAlgorithmId {
            selectionHistory.append(current)
        }
        selectedAlgorithmId = availableAlgorithms[nextIndex].id
    }
    
    /// Select the previous algorithm in the list.
    public func selectPrevious() {
        guard !availableAlgorithms.isEmpty else { return }
        guard let currentId = selectedAlgorithmId,
              let currentIndex = availableAlgorithms.firstIndex(where: { $0.id == currentId }) else {
            selectedAlgorithmId = availableAlgorithms.last?.id
            return
        }
        
        let prevIndex = currentIndex == 0 ? availableAlgorithms.count - 1 : currentIndex - 1
        if let current = selectedAlgorithmId {
            selectionHistory.append(current)
        }
        selectedAlgorithmId = availableAlgorithms[prevIndex].id
    }
    
    /// Undo the last selection.
    public func undoSelection() {
        guard let previous = selectionHistory.popLast() else { return }
        selectedAlgorithmId = previous
    }
    
    /// Check if undo is available.
    public var canUndo: Bool {
        !selectionHistory.isEmpty
    }
    
    // MARK: - Comparison Mode
    
    /// Get algorithms selected for comparison.
    public var comparisonAlgorithms: [AlgorithmInfo] {
        availableAlgorithms.filter { comparisonAlgorithmIds.contains($0.id) }
    }
    
    /// Add an algorithm to comparison.
    public func addToComparison(algorithmId: String) throws {
        guard availableAlgorithms.contains(where: { $0.id == algorithmId }) else {
            throw PlaygroundToggleError.algorithmNotFound(id: algorithmId)
        }
        comparisonAlgorithmIds.insert(algorithmId)
    }
    
    /// Remove an algorithm from comparison.
    public func removeFromComparison(algorithmId: String) {
        comparisonAlgorithmIds.remove(algorithmId)
    }
    
    /// Toggle an algorithm in comparison mode.
    public func toggleComparison(algorithmId: String) throws {
        if comparisonAlgorithmIds.contains(algorithmId) {
            comparisonAlgorithmIds.remove(algorithmId)
        } else {
            try addToComparison(algorithmId: algorithmId)
        }
    }
    
    /// Check if an algorithm is in comparison mode.
    public func isInComparison(algorithmId: String) -> Bool {
        comparisonAlgorithmIds.contains(algorithmId)
    }
    
    /// Clear all comparison selections.
    public func clearComparison() {
        comparisonAlgorithmIds.removeAll()
    }
    
    /// Number of algorithms in comparison.
    public var comparisonCount: Int {
        comparisonAlgorithmIds.count
    }
    
    // MARK: - Registry Integration
    
    /// Apply the current selection to the global registry.
    public func applyToRegistry() throws {
        guard let algorithmId = selectedAlgorithmId else {
            throw PlaygroundToggleError.noAlgorithmSelected
        }
        try AlgorithmRegistry.shared.setActive(name: algorithmId)
    }
    
    /// Sync selection from the global registry.
    public func syncFromRegistry() {
        selectedAlgorithmId = AlgorithmRegistry.shared.activeAlgorithmName
        refreshFromRegistry()
    }
}

// MARK: - Algorithm Info

/// Information about an available algorithm.
public struct AlgorithmInfo: Sendable, Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let version: String
    public let origin: AlgorithmOrigin
    public let supportsSMB: Bool
    public let providesPredictions: Bool
    public var isActive: Bool
    
    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        origin: AlgorithmOrigin = .custom,
        supportsSMB: Bool = false,
        providesPredictions: Bool = true,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.origin = origin
        self.supportsSMB = supportsSMB
        self.providesPredictions = providesPredictions
        self.isActive = isActive
    }
    
    /// Display label for UI.
    public var displayLabel: String {
        "\(name) v\(version)"
    }
    
    /// Short description for list display.
    public var shortDescription: String {
        var features: [String] = []
        if supportsSMB { features.append("SMB") }
        if providesPredictions { features.append("predictions") }
        return features.isEmpty ? origin.rawValue : "\(origin.rawValue) | \(features.joined(separator: ", "))"
    }
}

// MARK: - Errors

/// Errors from playground toggle operations.
public enum PlaygroundToggleError: Error, Sendable, Equatable {
    case algorithmNotFound(id: String)
    case noAlgorithmSelected
    case comparisonLimitExceeded(max: Int)
}

// MARK: - Toggle State

/// Observable state for algorithm toggle UI.
public struct PlaygroundToggleState: Sendable, Equatable {
    /// All available algorithms.
    public var algorithms: [AlgorithmInfo]
    
    /// Currently selected algorithm ID.
    public var selectedId: String?
    
    /// Algorithm IDs in comparison mode.
    public var comparisonIds: Set<String>
    
    /// Whether undo is available.
    public var canUndo: Bool
    
    /// Whether comparison mode is active.
    public var isComparisonMode: Bool
    
    public init(
        algorithms: [AlgorithmInfo] = [],
        selectedId: String? = nil,
        comparisonIds: Set<String> = [],
        canUndo: Bool = false,
        isComparisonMode: Bool = false
    ) {
        self.algorithms = algorithms
        self.selectedId = selectedId
        self.comparisonIds = comparisonIds
        self.canUndo = canUndo
        self.isComparisonMode = isComparisonMode
    }
    
    /// Get the selected algorithm.
    public var selectedAlgorithm: AlgorithmInfo? {
        guard let id = selectedId else { return nil }
        return algorithms.first { $0.id == id }
    }
    
    /// Get comparison algorithms.
    public var comparisonAlgorithms: [AlgorithmInfo] {
        algorithms.filter { comparisonIds.contains($0.id) }
    }
    
    /// Check if an algorithm is selected.
    public func isSelected(_ algorithmId: String) -> Bool {
        selectedId == algorithmId
    }
    
    /// Check if an algorithm is in comparison.
    public func isInComparison(_ algorithmId: String) -> Bool {
        comparisonIds.contains(algorithmId)
    }
}

// MARK: - Toggle Actions

/// Actions for algorithm toggle.
public enum PlaygroundToggleAction: Sendable, Equatable {
    case refresh
    case select(algorithmId: String)
    case selectNext
    case selectPrevious
    case undo
    case toggleComparison(algorithmId: String)
    case clearComparison
    case applyToRegistry
    case syncFromRegistry
    case setComparisonMode(Bool)
}

// MARK: - Toggle Reducer

/// Reduces toggle actions to state changes.
public actor PlaygroundToggleReducer {
    private let selector: PlaygroundAlgorithmSelector
    private var isComparisonMode: Bool = false
    
    public init(selector: PlaygroundAlgorithmSelector = PlaygroundAlgorithmSelector()) {
        self.selector = selector
    }
    
    /// Process an action and return updated state.
    public func reduce(_ action: PlaygroundToggleAction) async throws -> PlaygroundToggleState {
        switch action {
        case .refresh:
            await selector.refreshFromRegistry()
            
        case .select(let algorithmId):
            try await selector.select(algorithmId: algorithmId)
            
        case .selectNext:
            await selector.selectNext()
            
        case .selectPrevious:
            await selector.selectPrevious()
            
        case .undo:
            await selector.undoSelection()
            
        case .toggleComparison(let algorithmId):
            try await selector.toggleComparison(algorithmId: algorithmId)
            
        case .clearComparison:
            await selector.clearComparison()
            
        case .applyToRegistry:
            try await selector.applyToRegistry()
            
        case .syncFromRegistry:
            await selector.syncFromRegistry()
            
        case .setComparisonMode(let enabled):
            isComparisonMode = enabled
        }
        
        return await currentState()
    }
    
    /// Get the current state.
    public func currentState() async -> PlaygroundToggleState {
        let algorithms = await selector.algorithms
        let selectedId = await selector.selectedId
        let comparisonAlgorithms = await selector.comparisonAlgorithms
        let canUndo = await selector.canUndo
        
        return PlaygroundToggleState(
            algorithms: algorithms,
            selectedId: selectedId,
            comparisonIds: Set(comparisonAlgorithms.map(\.id)),
            canUndo: canUndo,
            isComparisonMode: isComparisonMode
        )
    }
}

// MARK: - Comparison Result

/// Result of running multiple algorithms on the same input.
public struct AlgorithmComparisonResult: Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let input: ComparisonInput
    public let results: [SingleAlgorithmResult]
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        input: ComparisonInput,
        results: [SingleAlgorithmResult]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.input = input
        self.results = results
    }
    
    /// Check if all algorithms agree on the action.
    public var isUnanimous: Bool {
        guard let first = results.first else { return true }
        return results.allSatisfy { $0.action == first.action }
    }
    
    /// Get the majority action.
    public var majorityAction: String? {
        let counts = Dictionary(grouping: results, by: { $0.action }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Get results that diverge from the majority.
    public var divergingResults: [SingleAlgorithmResult] {
        guard let majority = majorityAction else { return [] }
        return results.filter { $0.action != majority }
    }
}

/// Input used for comparison.
public struct ComparisonInput: Sendable, Codable, Equatable {
    public var glucose: Double
    public var glucoseDelta: Double
    public var iob: Double
    public var cob: Double
    public var targetGlucose: Double
    public var isf: Double
    public var carbRatio: Double
    public var basalRate: Double
    
    public init(
        glucose: Double,
        glucoseDelta: Double,
        iob: Double,
        cob: Double,
        targetGlucose: Double,
        isf: Double,
        carbRatio: Double,
        basalRate: Double
    ) {
        self.glucose = glucose
        self.glucoseDelta = glucoseDelta
        self.iob = iob
        self.cob = cob
        self.targetGlucose = targetGlucose
        self.isf = isf
        self.carbRatio = carbRatio
        self.basalRate = basalRate
    }
}

/// Result from a single algorithm.
public struct SingleAlgorithmResult: Sendable, Identifiable {
    public let id: String
    public let algorithmId: String
    public let algorithmName: String
    public let action: String
    public let suggestedRate: Double?
    public let eventualBG: Double
    public let reason: String
    public let executionTimeMs: Double
    public let success: Bool
    public let error: String?
    
    public init(
        id: String = UUID().uuidString,
        algorithmId: String,
        algorithmName: String,
        action: String,
        suggestedRate: Double?,
        eventualBG: Double,
        reason: String,
        executionTimeMs: Double,
        success: Bool = true,
        error: String? = nil
    ) {
        self.id = id
        self.algorithmId = algorithmId
        self.algorithmName = algorithmName
        self.action = action
        self.suggestedRate = suggestedRate
        self.eventualBG = eventualBG
        self.reason = reason
        self.executionTimeMs = executionTimeMs
        self.success = success
        self.error = error
    }
}

// MARK: - Comparison Runner

/// Runs comparison across multiple algorithms.
public actor AlgorithmComparisonRunner {
    private let performanceCollector: PerformanceCollector
    
    public init() {
        self.performanceCollector = PerformanceCollector(algorithmId: "comparison")
    }
    
    /// Run all selected algorithms on the same input.
    public func runComparison(
        input: ComparisonInput,
        algorithmIds: [String]
    ) async -> AlgorithmComparisonResult {
        var results: [SingleAlgorithmResult] = []
        
        let registry = AlgorithmRegistry.shared
        
        for algorithmId in algorithmIds {
            guard let algorithm = registry.algorithm(named: algorithmId) else {
                results.append(SingleAlgorithmResult(
                    algorithmId: algorithmId,
                    algorithmName: algorithmId,
                    action: "error",
                    suggestedRate: nil,
                    eventualBG: 0,
                    reason: "Algorithm not found",
                    executionTimeMs: 0,
                    success: false,
                    error: "Algorithm not found in registry"
                ))
                continue
            }
            
            let startTime = DispatchTime.now()
            
            do {
                let algorithmInput = createAlgorithmInputs(from: input)
                let decision = try algorithm.calculate(algorithmInput)
                
                let endTime = DispatchTime.now()
                let timeMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                
                let action = describeAction(decision)
                
                // Get eventual BG from predictions if available
                let eventualBG: Double
                if let predictions = decision.predictions, !predictions.iob.isEmpty {
                    eventualBG = predictions.iob.last ?? input.glucose
                } else {
                    eventualBG = input.glucose
                }
                
                results.append(SingleAlgorithmResult(
                    algorithmId: algorithmId,
                    algorithmName: algorithm.name,
                    action: action,
                    suggestedRate: decision.suggestedTempBasal?.rate,
                    eventualBG: eventualBG,
                    reason: decision.reason,
                    executionTimeMs: timeMs
                ))
            } catch {
                results.append(SingleAlgorithmResult(
                    algorithmId: algorithmId,
                    algorithmName: algorithm.name,
                    action: "error",
                    suggestedRate: nil,
                    eventualBG: 0,
                    reason: error.localizedDescription,
                    executionTimeMs: 0,
                    success: false,
                    error: "\(error)"
                ))
            }
        }
        
        return AlgorithmComparisonResult(
            input: input,
            results: results
        )
    }
    
    private func createAlgorithmInputs(from input: ComparisonInput) -> AlgorithmInputs {
        let glucose = GlucoseReading(
            glucose: input.glucose,
            timestamp: Date(),
            trend: .flat
        )
        
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: input.basalRate)],
            carbRatios: [CarbRatio(startTime: 0, ratio: input.carbRatio)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: input.isf)],
            targetGlucose: TargetRange(low: input.targetGlucose, high: input.targetGlucose + 10),
            maxIOB: 10.0,
            maxBolus: 10.0
        )
        
        return AlgorithmInputs(
            glucose: [glucose],
            insulinOnBoard: input.iob,
            carbsOnBoard: input.cob,
            profile: profile
        )
    }
    
    private func describeAction(_ decision: AlgorithmDecision) -> String {
        if let bolus = decision.suggestedBolus, bolus > 0 {
            return "Bolus \(String(format: "%.2f", bolus))U"
        } else if let temp = decision.suggestedTempBasal {
            if temp.rate == 0 {
                return "Zero temp"
            } else if temp.rate > 0 {
                return "Temp \(String(format: "%.2f", temp.rate))U/hr"
            }
        }
        return "No change"
    }
}

// MARK: - Display Helpers

/// Formats comparison results for display.
public struct ComparisonDisplayFormatter: Sendable {
    
    /// Format a comparison result as a summary table.
    public static func summaryTable(_ result: AlgorithmComparisonResult) -> String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════")
        lines.append("  ALGORITHM COMPARISON")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        lines.append("Input: BG=\(Int(result.input.glucose)) Δ=\(String(format: "%.1f", result.input.glucoseDelta)) IOB=\(String(format: "%.2f", result.input.iob)) COB=\(Int(result.input.cob))")
        lines.append("")
        lines.append("─── Results ───")
        
        for r in result.results {
            let status = r.success ? "✓" : "✗"
            lines.append("  \(status) \(r.algorithmName): \(r.action) (\(String(format: "%.1fms", r.executionTimeMs)))")
        }
        
        lines.append("")
        if result.isUnanimous {
            lines.append("Verdict: UNANIMOUS (\(result.majorityAction ?? "unknown"))")
        } else {
            lines.append("Verdict: DIVERGENT (\(result.divergingResults.count) differ)")
        }
        lines.append("═══════════════════════════════════════════")
        
        return lines.joined(separator: "\n")
    }
    
    /// Format a single result for inline display.
    public static func inlineResult(_ result: SingleAlgorithmResult) -> String {
        "\(result.algorithmName): \(result.action)"
    }
    
    /// Format execution times for performance display.
    public static func performanceSummary(_ result: AlgorithmComparisonResult) -> String {
        let times = result.results.map { $0.executionTimeMs }
        let avg = times.reduce(0, +) / Double(times.count)
        let fastest = times.min() ?? 0
        let slowest = times.max() ?? 0
        
        return "Avg: \(String(format: "%.2fms", avg)) | Fastest: \(String(format: "%.2fms", fastest)) | Slowest: \(String(format: "%.2fms", slowest))"
    }
}
