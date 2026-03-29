// SPDX-License-Identifier: AGPL-3.0-or-later
//
// InsulinModelPresetTests.swift
// T1Pal - Open Source AID
//
// Tests for LoopInsulinModelPreset bridging from profile strings.
//
// Trace: NS-IOB-001b, NS-IOB-001c

import Testing
import Foundation
@testable import T1PalAlgorithm
@testable import T1PalCore

// MARK: - Insulin Model Preset Tests

@Suite("LoopInsulinModelPreset Tests")
struct InsulinModelPresetTests {
    
    // MARK: - NS-IOB-001b: Profile String Bridge
    
    @Test("fromProfileString returns preset for valid string")
    func testFromProfileStringValid() {
        #expect(LoopInsulinModelPreset.fromProfileString("rapidActingAdult") == .rapidActingAdult)
        #expect(LoopInsulinModelPreset.fromProfileString("rapidActingChild") == .rapidActingChild)
        #expect(LoopInsulinModelPreset.fromProfileString("fiasp") == .fiasp)
        #expect(LoopInsulinModelPreset.fromProfileString("lyumjev") == .lyumjev)
        #expect(LoopInsulinModelPreset.fromProfileString("afrezza") == .afrezza)
    }
    
    @Test("fromProfileString returns default for nil")
    func testFromProfileStringNil() {
        let result = LoopInsulinModelPreset.fromProfileString(nil)
        #expect(result == .rapidActingAdult)
    }
    
    @Test("fromProfileString returns default for invalid string")
    func testFromProfileStringInvalid() {
        #expect(LoopInsulinModelPreset.fromProfileString("invalid") == .rapidActingAdult)
        #expect(LoopInsulinModelPreset.fromProfileString("") == .rapidActingAdult)
        #expect(LoopInsulinModelPreset.fromProfileString("Fiasp") == .rapidActingAdult) // case-sensitive
    }
    
    @Test("All presets have display name")
    func testDisplayNames() {
        for preset in LoopInsulinModelPreset.allCases {
            #expect(!preset.displayName.isEmpty, "Preset \(preset) should have display name")
        }
    }
    
    @Test("All presets produce valid model")
    func testAllPresetsProduceModel() {
        for preset in LoopInsulinModelPreset.allCases {
            let model = preset.model
            #expect(model.actionDuration > 0, "Preset \(preset) should have positive action duration")
            #expect(model.peakActivityTime > 0, "Preset \(preset) should have positive peak time")
        }
    }
    
    @Test("Preset raw values match expected strings")
    func testRawValues() {
        #expect(LoopInsulinModelPreset.rapidActingAdult.rawValue == "rapidActingAdult")
        #expect(LoopInsulinModelPreset.rapidActingChild.rawValue == "rapidActingChild")
        #expect(LoopInsulinModelPreset.fiasp.rawValue == "fiasp")
        #expect(LoopInsulinModelPreset.lyumjev.rawValue == "lyumjev")
        #expect(LoopInsulinModelPreset.afrezza.rawValue == "afrezza")
    }
    
    // MARK: - NS-IOB-001c: LoopModel Property
    
    @Test("loopModel returns ExponentialInsulinModel for all presets")
    func testLoopModelProperty() {
        for preset in LoopInsulinModelPreset.allCases {
            let loopModel = preset.loopModel
            #expect(loopModel.actionDuration > 0, "Preset \(preset) loopModel should have action duration")
            #expect(loopModel.peakActivityTime > 0, "Preset \(preset) loopModel should have peak time")
        }
    }
    
    @Test("loopModel parameters match expected values")
    func testLoopModelParameters() {
        // Fiasp: DIA 6h, peak 55min
        let fiasp = LoopInsulinModelPreset.fiasp.loopModel
        #expect(fiasp.actionDuration == 6 * 3600)
        #expect(fiasp.peakActivityTime == 55 * 60)
        
        // Afrezza: DIA 5h, peak 29min
        let afrezza = LoopInsulinModelPreset.afrezza.loopModel
        #expect(afrezza.actionDuration == 5 * 3600)
        #expect(afrezza.peakActivityTime == 29 * 60)
    }
}

// MARK: - NS-IOB-001c: Configuration from Profile Tests

@Suite("LoopAlgorithmConfiguration Profile Tests")
struct LoopAlgorithmConfigurationProfileTests {
    
    @Test("Configuration from profile uses default insulin model")
    func testConfigFromProfileDefault() {
        let profile = TherapyProfile.default
        let config = LoopAlgorithmConfiguration.from(profile: profile)
        
        // Default profile has nil insulinModel → rapidActingAdult
        #expect(config.insulinModel.actionDuration == 6 * 3600)
    }
    
    @Test("Configuration from profile uses specified insulin model")
    func testConfigFromProfileFiasp() {
        var profile = TherapyProfile.default
        profile.insulinModel = "fiasp"
        
        let config = LoopAlgorithmConfiguration.from(profile: profile)
        
        // Fiasp: peak 55min
        #expect(config.insulinModel.peakActivityTime == 55 * 60)
    }
    
    @Test("Configuration from profile uses maxBasalRate")
    func testConfigFromProfileMaxBasal() {
        var profile = TherapyProfile.default
        profile.maxBasalRate = 3.5
        
        let config = LoopAlgorithmConfiguration.from(profile: profile)
        
        #expect(config.maxBasalRate == 3.5)
    }
    
    @Test("Configuration from profile uses suspendThreshold")
    func testConfigFromProfileSuspend() {
        var profile = TherapyProfile.default
        profile.suspendThreshold = 75.0
        
        let config = LoopAlgorithmConfiguration.from(profile: profile)
        
        #expect(config.suspendThreshold == 75.0)
    }
}
