// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicVariantTests.swift
// PumpKitTests
//
// MDT-SYNTH-011: Model-variant conformance tests for Medtronic pumps
// Tests that scale and byte offset are correctly determined for all pump models.
//
// Key insight: hasPrefix("5") logic is WRONG - model 515/522 are pre-523 (scale=10)
// This test suite prevents regression of the scale determination bug.
//
// Trace: MDT-SYNTH-011, RL-WIRE-012

import Testing
import Foundation
@testable import PumpKit

// MARK: - Model Scale Determination Tests

@Suite("Medtronic Model Variant Tests")
struct MedtronicModelVariantTests {
    
    // MARK: - Pre-523 Models (Scale = 10)
    
    @Test("Model 508 uses scale=10 (pre-523)")
    func model508_isPre523() {
        #expect(MinimedPumpModel.model508.isPre523 == true)
        #expect(MinimedPumpModel.model508.insulinBitPackingScale == 10)
    }
    
    @Test("Model 511 uses scale=10 (pre-523)")
    func model511_isPre523() {
        #expect(MinimedPumpModel.model511.isPre523 == true)
        #expect(MinimedPumpModel.model511.insulinBitPackingScale == 10)
    }
    
    @Test("Model 512 uses scale=10 (pre-523)")
    func model512_isPre523() {
        #expect(MinimedPumpModel.model512.isPre523 == true)
        #expect(MinimedPumpModel.model512.insulinBitPackingScale == 10)
    }
    
    @Test("Model 515 uses scale=10 (pre-523) - NOT scale=40!")
    func model515_isPre523() {
        // Bug: hasPrefix("5") would incorrectly match 515 as 5xx (newer)
        // 515 is actually older and uses scale=10
        #expect(MinimedPumpModel.model515.isPre523 == true)
        #expect(MinimedPumpModel.model515.insulinBitPackingScale == 10)
    }
    
    @Test("Model 522 uses scale=10 (pre-523)")
    func model522_isPre523() {
        // Bug: hasPrefix("5") would incorrectly match 522 as 5xx (newer)
        // 522 is older and uses scale=10
        #expect(MinimedPumpModel.model522.isPre523 == true)
        #expect(MinimedPumpModel.model522.insulinBitPackingScale == 10)
    }
    
    @Test("Model 722 uses scale=10 (pre-523)")
    func model722_isPre523() {
        #expect(MinimedPumpModel.model722.isPre523 == true)
        #expect(MinimedPumpModel.model722.insulinBitPackingScale == 10)
    }
    
    // MARK: - 523+ Models (Scale = 40)
    
    @Test("Model 523 uses scale=40 (523+)")
    func model523_isPost523() {
        #expect(MinimedPumpModel.model523.isPre523 == false)
        #expect(MinimedPumpModel.model523.insulinBitPackingScale == 40)
    }
    
    @Test("Model 723 uses scale=40 (523+)")
    func model723_isPost523() {
        #expect(MinimedPumpModel.model723.isPre523 == false)
        #expect(MinimedPumpModel.model723.insulinBitPackingScale == 40)
    }
    
    @Test("Model 530G uses scale=40 (523+)")
    func model530_isPost523() {
        #expect(MinimedPumpModel.model530.isPre523 == false)
        #expect(MinimedPumpModel.model530.insulinBitPackingScale == 40)
    }
    
    @Test("Model 730G uses scale=40 (523+)")
    func model730_isPost523() {
        #expect(MinimedPumpModel.model730.isPre523 == false)
        #expect(MinimedPumpModel.model730.insulinBitPackingScale == 40)
    }
    
    @Test("Model 554 uses scale=40 (523+)")
    func model554_isPost523() {
        #expect(MinimedPumpModel.model554.isPre523 == false)
        #expect(MinimedPumpModel.model554.insulinBitPackingScale == 40)
    }
    
    @Test("Model 754 uses scale=40 (523+)")
    func model754_isPost523() {
        #expect(MinimedPumpModel.model754.isPre523 == false)
        #expect(MinimedPumpModel.model754.insulinBitPackingScale == 40)
    }
}

// MARK: - MedtronicVariant Scale Tests

@Suite("MedtronicVariant Scale Tests")
struct MedtronicVariantScaleTests {
    
    @Test("Variant 522 NA uses scale=10")
    func variant522NA_scale10() {
        let variant = MedtronicVariant(model: .model522, region: .northAmerica)
        #expect(variant.insulinBitPackingScale == 10)
    }
    
    @Test("Variant 515 NA uses scale=10")
    func variant515NA_scale10() {
        let variant = MedtronicVariant(model: .model515, region: .northAmerica)
        #expect(variant.insulinBitPackingScale == 10)
    }
    
    @Test("Variant 722 WW uses scale=10")
    func variant722WW_scale10() {
        let variant = MedtronicVariant(model: .model722, region: .worldWide)
        #expect(variant.insulinBitPackingScale == 10)
    }
    
    @Test("Variant 523 NA uses scale=40")
    func variant523NA_scale40() {
        let variant = MedtronicVariant(model: .model523, region: .northAmerica)
        #expect(variant.insulinBitPackingScale == 40)
    }
    
    @Test("Variant 723 WW uses scale=40")
    func variant723WW_scale40() {
        let variant = MedtronicVariant(model: .model723, region: .worldWide)
        #expect(variant.insulinBitPackingScale == 40)
    }
    
    @Test("Variant 554 NA uses scale=40")
    func variant554NA_scale40() {
        let variant = MedtronicVariant(model: .model554, region: .northAmerica)
        #expect(variant.insulinBitPackingScale == 40)
    }
}

// MARK: - Reservoir Parsing with Variant Tests

@Suite("Reservoir Parsing by Model Variant")
struct ReservoirParsingVariantTests {
    
    // MARK: - Pre-523 Reservoir Parsing (body[1:3], scale=10)
    
    @Test("Model 515 reservoir 120U parses correctly (fixture vector)")
    func model515_reservoir120U() throws {
        // From fixture_reservoir.json: Model 515 - 120.0U remaining
        // Body bytes[1:3]: 04 B0 -> 1200 strokes -> 1200/10 = 120.0U
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x00, 0x04, 0xB0])  // body[1:3] = 0x04B0
        let scale = MinimedPumpModel.model515.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 120.0)
    }
    
    @Test("Model 522 reservoir 135U parses correctly (Loop test vector)")
    func model522_reservoir135U() throws {
        // From fixture_reservoir.json: Loop Test Vector - Model 522 135.0U
        // Body bytes[1:3]: 05 46 -> 1350 strokes -> 1350/10 = 135.0U
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x02, 0x05, 0x46])  // body[1:3] = 0x0546
        let scale = MinimedPumpModel.model522.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 135.0)
    }
    
    @Test("Model 722 reservoir 150U parses correctly")
    func model722_reservoir150U() throws {
        // 1500 strokes / 10 = 150.0U
        // Body bytes[1:3]: 05 DC -> 1500 strokes
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x00, 0x05, 0xDC])  // body[1:3] = 0x05DC
        let scale = MinimedPumpModel.model722.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 150.0)
    }
    
    // MARK: - 523+ Reservoir Parsing (body[3:5], scale=40)
    
    @Test("Model 723 reservoir 80.875U parses correctly (Loop test vector)")
    func model723_reservoir80_875U() throws {
        // From fixture_reservoir.json: Loop Test Vector - Model 723 80.875U
        // Body bytes[3:5] = 0x0CA3 = 3235 strokes -> 3235/40 = 80.875U
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x04, 0x00, 0x00, 0x0C, 0xA3])  // body[3:5] = 0x0CA3
        let scale = MinimedPumpModel.model723.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(abs(result.unitsRemaining - 80.875) < 0.001)
    }
    
    @Test("Model 523 reservoir 180U parses correctly (fixture vector)")
    func model523_reservoir180U() throws {
        // From fixture_reservoir.json: Model 523 - 180.0U remaining
        // Body bytes[3:5] = 0x1C20 = 7200 strokes -> 7200/40 = 180.0U
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x00, 0x00, 0x00, 0x1C, 0x20])  // body[3:5] = 0x1C20
        let scale = MinimedPumpModel.model523.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 180.0)
    }
    
    @Test("Model 554 reservoir 200U parses correctly (fixture vector)")
    func model554_reservoir200U() throws {
        // From fixture_reservoir.json: Model 554 - 200.0U full
        // Body bytes[3:5] = 0x1F40 = 8000 strokes -> 8000/40 = 200.0U
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x00, 0x00, 0x00, 0x1F, 0x40])  // body[3:5] = 0x1F40
        let scale = MinimedPumpModel.model554.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 200.0)
    }
    
    @Test("Model 754 reservoir 300U parses correctly (large reservoir)")
    func model754_reservoir300U() throws {
        // 12000 strokes / 40 = 300.0U (large reservoir)
        // Body bytes[3:5] = 0x2EE0 = 12000 strokes
        // MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
        let body = Data([0x00, 0x00, 0x00, 0x2E, 0xE0])  // body[3:5] = 0x2EE0
        let scale = MinimedPumpModel.model754.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 300.0)
    }
}

// MARK: - Bug Regression Tests

@Suite("Scale Bug Regression Tests")
struct ScaleBugRegressionTests {
    
    @Test("hasPrefix('5') bug: 515 must NOT use scale=40")
    func hasPrefixBug_model515() {
        // Bug scenario: if code used hasPrefix("5") to determine scale,
        // it would incorrectly treat 515 as a 5xx (newer) model with scale=40
        // Correct: 515 is an older model with scale=10
        
        let model = MinimedPumpModel.model515
        let modelString = model.rawValue  // "515"
        
        // Demonstrate the bug:
        let hasPrefixFive = modelString.hasPrefix("5")
        #expect(hasPrefixFive == true)  // 515 DOES start with 5
        
        // But scale should still be 10, not 40
        #expect(model.insulinBitPackingScale == 10)
        #expect(model.isPre523 == true)
    }
    
    @Test("hasPrefix('5') bug: 522 must NOT use scale=40")
    func hasPrefixBug_model522() {
        // Bug scenario: if code used hasPrefix("5") to determine scale,
        // it would incorrectly treat 522 as a 5xx (newer) model with scale=40
        // Correct: 522 is an older model with scale=10
        
        let model = MinimedPumpModel.model522
        let modelString = model.rawValue  // "522"
        
        // Demonstrate the bug:
        let hasPrefixFive = modelString.hasPrefix("5")
        #expect(hasPrefixFive == true)  // 522 DOES start with 5
        
        // But scale should still be 10, not 40
        #expect(model.insulinBitPackingScale == 10)
        #expect(model.isPre523 == true)
    }
    
    @Test("hasPrefix('5') bug: 554 correctly uses scale=40")
    func hasPrefixBug_model554() {
        // 554 is a newer model that DOES use scale=40
        let model = MinimedPumpModel.model554
        
        #expect(model.rawValue.hasPrefix("5") == true)
        #expect(model.insulinBitPackingScale == 40)
        #expect(model.isPre523 == false)
    }
    
    @Test("All pre-523 models correctly identified")
    func allPre523ModelsCorrect() {
        let pre523Models: [MinimedPumpModel] = [
            .model508, .model511, .model512, .model515, .model522, .model722
        ]
        
        for model in pre523Models {
            #expect(model.isPre523 == true, "Model \(model.rawValue) should be pre-523")
            #expect(model.insulinBitPackingScale == 10, "Model \(model.rawValue) should use scale=10")
        }
    }
    
    @Test("All post-523 models correctly identified")
    func allPost523ModelsCorrect() {
        // EXT-MDT-005: Added missing models
        let post523Models: [MinimedPumpModel] = [
            .model523, .model723, .model530, .model730,
            .model540, .model740, .model551, .model751,
            .model554, .model754
        ]
        
        for model in post523Models {
            #expect(model.isPre523 == false, "Model \(model.rawValue) should be post-523")
            #expect(model.insulinBitPackingScale == 40, "Model \(model.rawValue) should use scale=40")
        }
    }
}

// MARK: - Generation Classification Tests

@Suite("Medtronic Generation Classification")
struct MedtronicGenerationTests {
    
    @Test("Paradigm generation includes all pre-523 models")
    func paradigmGeneration() {
        // EXT-MDT-005: Added missing 7xx variants
        let paradigmModels: [MinimedPumpModel] = [
            .model508, .model511, .model711, .model512, .model712,
            .model515, .model715, .model522, .model722
        ]
        
        for model in paradigmModels {
            let variant = MedtronicVariant(model: model, region: .northAmerica)
            #expect(variant.generation == .paradigm, "Model \(model.rawValue) should be Paradigm generation")
        }
    }
    
    @Test("Paradigm Revel generation includes 523/723")
    func paradigmRevelGeneration() {
        let revelModels: [MinimedPumpModel] = [.model523, .model723]
        
        for model in revelModels {
            let variant = MedtronicVariant(model: model, region: .northAmerica)
            #expect(variant.generation == .paradigmRevel, "Model \(model.rawValue) should be Paradigm Revel generation")
        }
    }
    
    @Test("MiniMed G-Series includes 530/730/540/740")
    func minimedGGeneration() {
        // EXT-MDT-005: Added 540/740
        let gSeriesModels: [MinimedPumpModel] = [.model530, .model730, .model540, .model740]
        
        for model in gSeriesModels {
            let variant = MedtronicVariant(model: model, region: .northAmerica)
            #expect(variant.generation == .minimedG, "Model \(model.rawValue) should be MiniMed G generation")
        }
    }
    
    @Test("MiniMed X-Series includes 551/751/554/754")
    func minimedXGeneration() {
        // EXT-MDT-005: Added 551/751
        let xSeriesModels: [MinimedPumpModel] = [.model551, .model751, .model554, .model754]
        
        for model in xSeriesModels {
            let variant = MedtronicVariant(model: model, region: .northAmerica)
            #expect(variant.generation == .minimedX, "Model \(model.rawValue) should be MiniMed X generation")
        }
    }
}

// MARK: - MySentry Support Tests

@Suite("MySentry CGM Support")
struct MySentrySupportTests {
    
    @Test("Pre-Revel models do not support MySentry")
    func preRevelNoMySentry() {
        // EXT-MDT-005: Added missing 7xx variants
        let preRevelModels: [MinimedPumpModel] = [
            .model508, .model511, .model711, .model512, .model712,
            .model515, .model715, .model522, .model722
        ]
        
        for model in preRevelModels {
            #expect(model.supportsMySentry == false, "Model \(model.rawValue) should not support MySentry")
        }
    }
    
    @Test("Revel and later models support MySentry")
    func revelAndLaterSupportMySentry() {
        // All models with generation >= 23 support MySentry
        // Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:54
        let mySentryModels: [MinimedPumpModel] = [
            .model523, .model723, .model530, .model730,
            .model540, .model740, .model551, .model751,
            .model554, .model754
        ]
        
        for model in mySentryModels {
            #expect(model.supportsMySentry == true, "Model \(model.rawValue) should support MySentry")
        }
    }
    
    @Test("X-Series models (551+) DO support MySentry per Loop definition")
    func xSeriesHasMySentry() {
        // Loop's definition: hasMySentry = generation >= 23
        // 554/754 have generation 54, so they DO have MySentry support
        // Source: externals/MinimedKit/MinimedKit/Models/PumpModel.swift:54
        #expect(MinimedPumpModel.model554.supportsMySentry == true)
        #expect(MinimedPumpModel.model754.supportsMySentry == true)
        
        // And they also have low suspend (generation >= 51)
        #expect(MinimedPumpModel.model554.hasLowSuspend == true)
        #expect(MinimedPumpModel.model754.hasLowSuspend == true)
    }
}

// MARK: - Reservoir Size Tests

@Suite("Reservoir Size by Model")
struct ReservoirSizeTests {
    
    @Test("5xx models have small (176U) reservoir")
    func smallReservoirModels() {
        // EXT-MDT-005: Added missing models
        let smallReservoirModels: [MinimedPumpModel] = [
            .model508, .model511, .model512, .model515, .model522, .model523,
            .model530, .model540, .model551, .model554
        ]
        
        for model in smallReservoirModels {
            #expect(model.reservoirCapacity == 176, "Model \(model.rawValue) should have 176U reservoir")
        }
    }
    
    @Test("7xx models have large (300U) reservoir")
    func largeReservoirModels() {
        // EXT-MDT-005: Added missing models
        let largeReservoirModels: [MinimedPumpModel] = [
            .model711, .model712, .model715, .model722, .model723,
            .model730, .model740, .model751, .model754
        ]
        
        for model in largeReservoirModels {
            #expect(model.reservoirCapacity == 300, "Model \(model.rawValue) should have 300U reservoir")
        }
    }
}
