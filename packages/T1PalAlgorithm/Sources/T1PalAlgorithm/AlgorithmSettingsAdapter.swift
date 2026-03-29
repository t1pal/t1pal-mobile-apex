// SPDX-License-Identifier: AGPL-3.0-or-later
// AlgorithmSettingsAdapter.swift
// T1PalAlgorithm
//
// Adapts settings UI visibility based on active algorithm capabilities.
// Requirements: REQ-ALGO-009
// Trace: ALG-SETTINGS-001, PRD-009

import Foundation

// MARK: - Algorithm Settings Adapter

/// Adapts settings UI based on active algorithm capabilities
/// Per REQ-ALGO-009, settings should only show options relevant to the selected algorithm
public final class AlgorithmSettingsAdapter: @unchecked Sendable {
    
    // MARK: - Visibility Properties
    
    /// Whether to show SMB-related settings (oref1, dynamicISF, trio)
    public var showSMBSettings: Bool = false
    
    /// Whether to show UAM settings (oref1, dynamicISF, trio)
    public var showUAMSettings: Bool = false
    
    /// Whether to show Dynamic ISF curve settings (oref1, dynamicISF, trio)
    public var showDynamicISFSettings: Bool = false
    
    /// Whether to show Autosens settings (oref0, oref1)
    public var showAutosensSettings: Bool = false
    
    /// Whether to show predictions display (most algorithms)
    public var showPredictions: Bool = false
    
    /// Current algorithm name for display
    public var currentAlgorithmName: String = "Unknown"
    
    /// Current algorithm capabilities
    public private(set) var capabilities: AlgorithmCapabilities?
    
    // MARK: - Private State
    
    private let registry: AlgorithmRegistry
    
    // MARK: - Initialization
    
    public init(registry: AlgorithmRegistry = .shared) {
        self.registry = registry
        refresh()
        setupObserver()
    }
    
    /// Create for testing with specific registry
    public static func createForTesting(registry: AlgorithmRegistry) -> AlgorithmSettingsAdapter {
        AlgorithmSettingsAdapter(registry: registry)
    }
    
    // MARK: - Refresh
    
    /// Refresh visibility based on current active algorithm
    public func refresh() {
        guard let algorithm = registry.activeAlgorithm else {
            resetToDefaults()
            return
        }
        
        let caps = algorithm.capabilities
        self.capabilities = caps
        self.currentAlgorithmName = algorithm.name
        
        // Update visibility based on capabilities
        showSMBSettings = caps.supportsSMB
        showUAMSettings = caps.supportsUAM
        showDynamicISFSettings = caps.supportsDynamicISF
        showAutosensSettings = caps.supportsAutosens
        showPredictions = caps.providesPredictions
    }
    
    /// Reset to safe defaults (show nothing algorithm-specific)
    private func resetToDefaults() {
        capabilities = nil
        currentAlgorithmName = "None"
        showSMBSettings = false
        showUAMSettings = false
        showDynamicISFSettings = false
        showAutosensSettings = false
        showPredictions = false
    }
    
    // MARK: - Observer
    
    private func setupObserver() {
        // Register for algorithm changes
        registry.addObserver { [weak self] oldName, newName in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Check if any advanced features are available
    public var hasAdvancedFeatures: Bool {
        showSMBSettings || showUAMSettings || showDynamicISFSettings
    }
    
    /// Get list of available feature names for display
    public var availableFeatures: [String] {
        var features: [String] = []
        if showSMBSettings { features.append("Super Micro Bolus (SMB)") }
        if showUAMSettings { features.append("Unannounced Meals (UAM)") }
        if showDynamicISFSettings { features.append("Dynamic ISF") }
        if showAutosensSettings { features.append("Autosens") }
        return features
    }
    
    /// Get summary of algorithm capabilities
    public var capabilitySummary: String {
        guard let caps = capabilities else {
            return "No algorithm selected"
        }
        
        var parts: [String] = []
        if caps.supportsTempBasal { parts.append("Temp Basal") }
        if caps.supportsSMB { parts.append("SMB") }
        if caps.supportsUAM { parts.append("UAM") }
        if caps.supportsDynamicISF { parts.append("Dynamic ISF") }
        if caps.supportsAutosens { parts.append("Autosens") }
        
        return parts.isEmpty ? "Basic features only" : parts.joined(separator: ", ")
    }
}

// MARK: - Algorithm Capabilities Extension

public extension AlgorithmCapabilities {
    
    /// Get settings visibility based on these capabilities
    var settingsVisibility: AlgorithmSettingsVisibility {
        AlgorithmSettingsVisibility(
            showSMB: supportsSMB,
            showUAM: supportsUAM,
            showDynamicISF: supportsDynamicISF,
            showAutosens: supportsAutosens,
            showRetrospectiveCorrection: origin == .loop,
            showAutoBolus: origin == .loop
        )
    }
}

/// Visibility configuration for algorithm-specific settings
public struct AlgorithmSettingsVisibility: Sendable, Equatable {
    public let showSMB: Bool
    public let showUAM: Bool
    public let showDynamicISF: Bool
    public let showAutosens: Bool
    public let showRetrospectiveCorrection: Bool
    public let showAutoBolus: Bool
    
    public init(
        showSMB: Bool = false,
        showUAM: Bool = false,
        showDynamicISF: Bool = false,
        showAutosens: Bool = false,
        showRetrospectiveCorrection: Bool = false,
        showAutoBolus: Bool = false
    ) {
        self.showSMB = showSMB
        self.showUAM = showUAM
        self.showDynamicISF = showDynamicISF
        self.showAutosens = showAutosens
        self.showRetrospectiveCorrection = showRetrospectiveCorrection
        self.showAutoBolus = showAutoBolus
    }
    
    /// All settings visible (for testing/debugging)
    public static let all = AlgorithmSettingsVisibility(
        showSMB: true,
        showUAM: true,
        showDynamicISF: true,
        showAutosens: true,
        showRetrospectiveCorrection: true,
        showAutoBolus: true
    )
    
    /// No advanced settings visible
    public static let none = AlgorithmSettingsVisibility()
    
    /// oref0 visibility
    public static let oref0 = AlgorithmSettingsVisibility(
        showAutosens: true
    )
    
    /// oref1 visibility
    public static let oref1 = AlgorithmSettingsVisibility(
        showSMB: true,
        showUAM: true,
        showDynamicISF: true,
        showAutosens: true
    )
    
    /// Loop visibility
    public static let loop = AlgorithmSettingsVisibility(
        showRetrospectiveCorrection: true,
        showAutoBolus: true
    )
}
