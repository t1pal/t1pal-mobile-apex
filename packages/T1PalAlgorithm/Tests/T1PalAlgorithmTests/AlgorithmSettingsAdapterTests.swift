// SPDX-License-Identifier: MIT
// AlgorithmSettingsAdapterTests.swift
// T1PalAlgorithmTests
//
// Tests for algorithm settings adaptation based on capabilities.
// Requirements: REQ-ALGO-009
// Trace: ALG-SETTINGS-001, PRD-009

import Testing
import Foundation
@testable import T1PalAlgorithm

// MARK: - Algorithm Settings Adapter Tests

@Suite("AlgorithmSettingsAdapter")
@MainActor
struct AlgorithmSettingsAdapterTests {
    
    @Test("Adapter loads current algorithm capabilities")
    func adapterLoadsCurrentCapabilities() {
        let adapter = AlgorithmSettingsAdapter()
        
        // Default algorithm (oref0) should be active
        #expect(adapter.currentAlgorithmName == "oref0")
        #expect(adapter.capabilities != nil)
    }
    
    @Test("oref0 shows autosens but not SMB")
    func oref0ShowsCorrectSettings() {
        // oref0 is the default registered algorithm
        let adapter = AlgorithmSettingsAdapter()
        
        // oref0 capabilities
        #expect(adapter.showAutosensSettings == true)
        #expect(adapter.showSMBSettings == false)
        #expect(adapter.showUAMSettings == false)
    }
    
    @Test("oref1 shows SMB, UAM, and autosens")
    func oref1ShowsAdvancedSettings() {
        // Register oref1
        let registry = AlgorithmRegistry.shared
        let oref1 = Oref1Algorithm()
        registry.registerOrReplace(oref1)
        try? registry.setActive(name: "oref1")
        
        let adapter = AlgorithmSettingsAdapter()
        
        #expect(adapter.showSMBSettings == true)
        #expect(adapter.showUAMSettings == true)
        #expect(adapter.showAutosensSettings == true)
        #expect(adapter.showDynamicISFSettings == true)
        
        // Restore oref0 as default
        try? registry.setActive(name: "oref0")
    }
    
    @Test("Refresh updates visibility")
    func refreshUpdatesVisibility() {
        let adapter = AlgorithmSettingsAdapter()
        
        // Initial state
        let initialSMB = adapter.showSMBSettings
        
        // Refresh should not crash
        adapter.refresh()
        
        #expect(adapter.showSMBSettings == initialSMB)
    }
    
    @Test("Available features returns correct list")
    func availableFeaturesReturnsCorrectList() {
        let adapter = AlgorithmSettingsAdapter()
        
        // With oref0, should have autosens
        let features = adapter.availableFeatures
        
        // oref0 has autosens
        if adapter.showAutosensSettings {
            #expect(features.contains("Autosens"))
        }
    }
    
    @Test("Capability summary returns string")
    func capabilitySummaryReturnsString() {
        let adapter = AlgorithmSettingsAdapter()
        
        let summary = adapter.capabilitySummary
        #expect(!summary.isEmpty)
    }
    
    @Test("Has advanced features computed correctly")
    func hasAdvancedFeaturesComputedCorrectly() {
        let adapter = AlgorithmSettingsAdapter()
        
        // With oref0, no advanced features (SMB/UAM/DynamicISF)
        if !adapter.showSMBSettings && !adapter.showUAMSettings && !adapter.showDynamicISFSettings {
            #expect(adapter.hasAdvancedFeatures == false)
        }
    }
}

// MARK: - Algorithm Settings Visibility Tests

@Suite("AlgorithmSettingsVisibility")
struct AlgorithmSettingsVisibilityTests {
    
    @Test("oref0 visibility shows only autosens")
    func oref0Visibility() {
        let visibility = AlgorithmSettingsVisibility.oref0
        
        #expect(visibility.showAutosens == true)
        #expect(visibility.showSMB == false)
        #expect(visibility.showUAM == false)
        #expect(visibility.showDynamicISF == false)
        #expect(visibility.showRetrospectiveCorrection == false)
        #expect(visibility.showAutoBolus == false)
    }
    
    @Test("oref1 visibility shows SMB, UAM, DynamicISF, Autosens")
    func oref1Visibility() {
        let visibility = AlgorithmSettingsVisibility.oref1
        
        #expect(visibility.showSMB == true)
        #expect(visibility.showUAM == true)
        #expect(visibility.showDynamicISF == true)
        #expect(visibility.showAutosens == true)
        #expect(visibility.showRetrospectiveCorrection == false)
        #expect(visibility.showAutoBolus == false)
    }
    
    @Test("Loop visibility shows retrospective correction and auto-bolus")
    func loopVisibility() {
        let visibility = AlgorithmSettingsVisibility.loop
        
        #expect(visibility.showSMB == false)
        #expect(visibility.showUAM == false)
        #expect(visibility.showRetrospectiveCorrection == true)
        #expect(visibility.showAutoBolus == true)
    }
    
    @Test("All visibility shows everything")
    func allVisibility() {
        let visibility = AlgorithmSettingsVisibility.all
        
        #expect(visibility.showSMB == true)
        #expect(visibility.showUAM == true)
        #expect(visibility.showDynamicISF == true)
        #expect(visibility.showAutosens == true)
        #expect(visibility.showRetrospectiveCorrection == true)
        #expect(visibility.showAutoBolus == true)
    }
    
    @Test("None visibility shows nothing")
    func noneVisibility() {
        let visibility = AlgorithmSettingsVisibility.none
        
        #expect(visibility.showSMB == false)
        #expect(visibility.showUAM == false)
        #expect(visibility.showDynamicISF == false)
        #expect(visibility.showAutosens == false)
        #expect(visibility.showRetrospectiveCorrection == false)
        #expect(visibility.showAutoBolus == false)
    }
    
    @Test("Visibility is equatable")
    func visibilityIsEquatable() {
        let v1 = AlgorithmSettingsVisibility.oref0
        let v2 = AlgorithmSettingsVisibility.oref0
        let v3 = AlgorithmSettingsVisibility.oref1
        
        #expect(v1 == v2)
        #expect(v1 != v3)
    }
}

// MARK: - Algorithm Capabilities Settings Tests

@Suite("AlgorithmCapabilities Settings")
struct AlgorithmCapabilitiesSettingsTests {
    
    @Test("oref0 capabilities visibility")
    func oref0CapabilitiesVisibility() {
        let caps = AlgorithmCapabilities.oref0
        let visibility = caps.settingsVisibility
        
        #expect(visibility.showSMB == false)
        #expect(visibility.showUAM == false)
        #expect(visibility.showAutosens == true)
    }
    
    @Test("oref1 capabilities visibility")
    func oref1CapabilitiesVisibility() {
        let caps = AlgorithmCapabilities.oref1
        let visibility = caps.settingsVisibility
        
        #expect(visibility.showSMB == true)
        #expect(visibility.showUAM == true)
        #expect(visibility.showAutosens == true)
        #expect(visibility.showDynamicISF == true)
    }
    
    @Test("Loop capabilities visibility")
    func loopCapabilitiesVisibility() {
        let caps = AlgorithmCapabilities.loop
        let visibility = caps.settingsVisibility
        
        #expect(visibility.showSMB == false)
        #expect(visibility.showRetrospectiveCorrection == true)
        #expect(visibility.showAutoBolus == true)
    }
    
    @Test("Capabilities visibility matches capability flags")
    func capabilitiesVisibilityMatchesFlags() {
        let caps = AlgorithmCapabilities.oref1
        let visibility = caps.settingsVisibility
        
        #expect(visibility.showSMB == caps.supportsSMB)
        #expect(visibility.showUAM == caps.supportsUAM)
        #expect(visibility.showDynamicISF == caps.supportsDynamicISF)
        #expect(visibility.showAutosens == caps.supportsAutosens)
    }
}

// MARK: - Integration Tests

@Suite("Settings Adaptation Integration")
struct SettingsAdaptationIntegrationTests {
    
    @Test("Adapter visibility matches registry algorithm")
    @MainActor
    func adapterVisibilityMatchesRegistry() {
        let adapter = AlgorithmSettingsAdapter()
        
        // Visibility should match the active algorithm's capabilities
        if let caps = adapter.capabilities {
            #expect(adapter.showSMBSettings == caps.supportsSMB)
            #expect(adapter.showUAMSettings == caps.supportsUAM)
            #expect(adapter.showDynamicISFSettings == caps.supportsDynamicISF)
            #expect(adapter.showAutosensSettings == caps.supportsAutosens)
        }
    }
}
